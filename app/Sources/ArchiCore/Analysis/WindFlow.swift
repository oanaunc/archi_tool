// Oanarina Archi Tool — GPL-3.0-or-later
// Built-in wind flow solver (ANL-028): a two-dimensional lattice Boltzmann solver (D2Q9, BGK collision with a
// Smagorinsky sub-grid model for stability at building Reynolds numbers, Guo body-force scheme, half-way bounce-back
// on obstacles) used for pedestrian-level wind screening without an external CFD package. The plan section of the
// building mass above pedestrian height is rasterised onto the lattice (enclosed interiors are filled), a uniform
// inflow with the log-law pedestrian speed enters on the upwind side, the downwind side is a zero-gradient outlet and
// the lateral sides are free-slip. After a warm-up of two flow-through times the velocity is time-averaged over one
// more flow-through (vortex shedding behind the building is averaged out). Speeds are reported as amplification
// factors of the free-stream speed and as Lawson comfort classes; results feed the same wind arrows as imported
// OpenFOAM samples (WindStudy.arrows). The solver is verified against the analytic Poiseuille channel profile.
// Limitation: a 2D section ignores down-wash from tall buildings, so corner speed-ups of towers are under-estimated —
// use the OpenFOAM case (CFDEXPORT) for design decisions.
import Foundation

public enum WindFlow {
    public enum XBoundary: Hashable { case inletOutlet, periodic }
    public enum YBoundary: Hashable { case slip, wall, periodic }

    /// Obstacle mask of a rectangular lattice (row-major, x fastest).
    public struct Lattice: Hashable {
        public let nx: Int, ny: Int
        public var solid: [Bool]
        public init(nx: Int, ny: Int, solid: [Bool]? = nil) {
            self.nx = max(1, nx); self.ny = max(1, ny)
            self.solid = solid ?? Array(repeating: false, count: max(1, nx) * max(1, ny))
        }
        public subscript(x: Int, y: Int) -> Bool {
            get { solid[y * nx + x] }
            set { solid[y * nx + x] = newValue }
        }
        public var fluidCount: Int { solid.lazy.filter { !$0 }.count }

        /// Marks every fluid cell not 4-connected to the domain boundary as solid (interiors of closed buildings).
        public mutating func fillEnclosed() {
            var seen = [Bool](repeating: false, count: nx * ny)
            var stack: [Int] = []
            for x in 0..<nx { for y in [0, ny - 1] where !solid[y * nx + x] { stack.append(y * nx + x) } }
            for y in 0..<ny { for x in [0, nx - 1] where !solid[y * nx + x] { stack.append(y * nx + x) } }
            while let c = stack.popLast() {
                if seen[c] || solid[c] { continue }
                seen[c] = true
                let x = c % nx, y = c / nx
                if x > 0 { stack.append(c - 1) }
                if x < nx - 1 { stack.append(c + 1) }
                if y > 0 { stack.append(c - nx) }
                if y < ny - 1 { stack.append(c + nx) }
            }
            for c in 0..<(nx * ny) where !seen[c] { solid[c] = true }
        }
    }

    public struct Settings: Hashable {
        /// Inflow speed in lattice units (keep ≤ 0.1 for the low-Mach assumption).
        public var inletSpeed = 0.08
        /// Relaxation time (kinematic viscosity ν = (τ − ½)/3).
        public var tau = 0.56
        /// Smagorinsky constant (0 = plain BGK).
        public var smagorinsky = 0.17
        /// Body force per cell (lattice units).
        public var force = Vec2(0, 0)
        public var xBoundary: XBoundary = .inletOutlet
        public var yBoundary: YBoundary = .slip
        public var maxIterations = 20_000
        /// Stops when the mean speed changes less than this (relative) between checks (0 = run all iterations).
        public var tolerance = 1e-7
        public var checkEvery = 100
        /// When set, the velocity is averaged from this iteration on and convergence checks are skipped.
        public var averageFrom: Int? = nil
        public init() {}
    }

    public struct Field {
        public let nx: Int, ny: Int
        public var ux: [Double], uy: [Double], rho: [Double]
        public var solid: [Bool]
        public var iterations: Int
        public var converged: Bool
        public var stable: Bool
        public func speed(_ x: Int, _ y: Int) -> Double { let i = y * nx + x; return (ux[i] * ux[i] + uy[i] * uy[i]).squareRoot() }
        public func velocity(_ x: Int, _ y: Int) -> Vec2 { let i = y * nx + x; return Vec2(ux[i], uy[i]) }
        public func isSolid(_ x: Int, _ y: Int) -> Bool { solid[y * nx + x] }
    }

    // D2Q9 lattice.
    static let cx = [0, 1, 0, -1, 0, 1, -1, -1, 1]
    static let cy = [0, 0, 1, 0, -1, 1, 1, -1, -1]
    static let w: [Double] = [4.0 / 9, 1.0 / 9, 1.0 / 9, 1.0 / 9, 1.0 / 9, 1.0 / 36, 1.0 / 36, 1.0 / 36, 1.0 / 36]
    static let opp = [0, 3, 4, 1, 2, 7, 8, 5, 6]
    /// Direction with the y component mirrored (specular reflection on slip walls).
    static let mirY = [0, 1, 4, 3, 2, 8, 7, 6, 5]

    @inline(__always) static func feq(_ i: Int, _ rho: Double, _ ux: Double, _ uy: Double) -> Double {
        let cu = 3 * (Double(cx[i]) * ux + Double(cy[i]) * uy)
        return w[i] * rho * (1 + cu + 0.5 * cu * cu - 1.5 * (ux * ux + uy * uy))
    }

    /// Runs the lattice Boltzmann solver to a steady (or time-averaged) state.
    public static func solve(_ lat: Lattice, _ s: Settings) -> Field {
        let nx = lat.nx, ny = lat.ny, n = nx * ny
        let f = UnsafeMutablePointer<Double>.allocate(capacity: n * 9)
        let g = UnsafeMutablePointer<Double>.allocate(capacity: n * 9)
        let mux = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let muy = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let mrho = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let sux = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let suy = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let solid = UnsafeMutablePointer<Bool>.allocate(capacity: n)
        defer { f.deallocate(); g.deallocate(); mux.deallocate(); muy.deallocate(); mrho.deallocate(); sux.deallocate(); suy.deallocate(); solid.deallocate() }
        for c in 0..<n { solid[c] = lat.solid[c]; mux[c] = 0; muy[c] = 0; mrho[c] = 1; sux[c] = 0; suy[c] = 0 }
        let u0 = s.xBoundary == .inletOutlet ? s.inletSpeed : 0
        var inflow = [Double](repeating: 0, count: 9)
        for i in 0..<9 { inflow[i] = feq(i, 1, u0, 0) }
        for c in 0..<n {
            let u = solid[c] ? 0 : u0
            for i in 0..<9 { f[c * 9 + i] = feq(i, 1, u, 0); g[c * 9 + i] = f[c * 9 + i] }
            if !solid[c] { mux[c] = u }
        }
        let tau0 = max(0.5001, s.tau), cs2 = s.smagorinsky * s.smagorinsky
        let fx = s.force.x, fy = s.force.y
        let hasForce = fx != 0 || fy != 0
        let chunks = max(1, min(ny, ProcessInfo.processInfo.activeProcessorCount * 2))
        var cur = f, nxt = g
        var iterations = 0, converged = false, stable = true, prevMean = -1.0, averaged = 0
        let xb = s.xBoundary, yb = s.yBoundary

        // Lattice tables as raw buffers (fast in unoptimised builds too).
        let ci = UnsafeMutablePointer<Int>.allocate(capacity: 9), cj = UnsafeMutablePointer<Int>.allocate(capacity: 9)
        let op = UnsafeMutablePointer<Int>.allocate(capacity: 9), mir = UnsafeMutablePointer<Int>.allocate(capacity: 9)
        let inf = UnsafeMutablePointer<Double>.allocate(capacity: 9)
        defer { ci.deallocate(); cj.deallocate(); op.deallocate(); mir.deallocate(); inf.deallocate() }
        for i in 0..<9 { ci[i] = cx[i]; cj[i] = cy[i]; op[i] = opp[i]; mir[i] = mirY[i]; inf[i] = inflow[i] }

        func collide(_ p: UnsafeMutablePointer<Double>) {
            DispatchQueue.concurrentPerform(iterations: chunks) { k in
                let y0 = k * ny / chunks, y1 = (k + 1) * ny / chunks
                for y in y0..<y1 {
                    for x in 0..<nx {
                        let c = y * nx + x
                        if solid[c] { continue }
                        let q = p + c * 9
                        let f0 = q[0], f1 = q[1], f2 = q[2], f3 = q[3], f4 = q[4], f5 = q[5], f6 = q[6], f7 = q[7], f8 = q[8]
                        var rho = f0 + f1 + f2 + f3 + f4 + f5 + f6 + f7 + f8
                        if !(rho > 1e-9) || !rho.isFinite { rho = 1 }
                        let jx = f1 - f3 + f5 - f6 - f7 + f8, jy = f2 - f4 + f5 + f6 - f7 - f8
                        let ux = (jx + 0.5 * fx) / rho, uy = (jy + 0.5 * fy) / rho
                        mux[c] = ux; muy[c] = uy; mrho[c] = rho
                        let usq = 1.5 * (ux * ux + uy * uy)
                        let r0 = rho * (4.0 / 9), r1 = rho / 9, r2 = rho / 36
                        let e0 = r0 * (1 - usq)
                        let e1 = r1 * (1 + 3 * ux + 4.5 * ux * ux - usq), e3 = r1 * (1 - 3 * ux + 4.5 * ux * ux - usq)
                        let e2 = r1 * (1 + 3 * uy + 4.5 * uy * uy - usq), e4 = r1 * (1 - 3 * uy + 4.5 * uy * uy - usq)
                        let a = ux + uy, b = uy - ux
                        let e5 = r2 * (1 + 3 * a + 4.5 * a * a - usq), e7 = r2 * (1 - 3 * a + 4.5 * a * a - usq)
                        let e6 = r2 * (1 + 3 * b + 4.5 * b * b - usq), e8 = r2 * (1 - 3 * b + 4.5 * b * b - usq)
                        let d0 = f0 - e0, d1 = f1 - e1, d2 = f2 - e2, d3 = f3 - e3, d4 = f4 - e4, d5 = f5 - e5, d6 = f6 - e6, d7 = f7 - e7, d8 = f8 - e8
                        var tau = tau0
                        if cs2 > 0 {
                            let pxx = d1 + d3 + d5 + d6 + d7 + d8, pyy = d2 + d4 + d5 + d6 + d7 + d8, pxy = d5 - d6 + d7 - d8
                            let qn = (pxx * pxx + pyy * pyy + 2 * pxy * pxy).squareRoot()
                            tau = 0.5 * (tau0 + (tau0 * tau0 + 18 * 1.4142135623730951 * cs2 * qn / rho).squareRoot())
                        }
                        let om = 1 / tau
                        q[0] = f0 - om * d0; q[1] = f1 - om * d1; q[2] = f2 - om * d2; q[3] = f3 - om * d3; q[4] = f4 - om * d4
                        q[5] = f5 - om * d5; q[6] = f6 - om * d6; q[7] = f7 - om * d7; q[8] = f8 - om * d8
                        if hasForce {
                            let g = 1 - 0.5 * om
                            for i in 0..<9 {
                                let ex = Double(ci[i]), ey = Double(cj[i])
                                let wi: Double = i == 0 ? 4.0 / 9.0 : (i < 5 ? 1.0 / 9.0 : 1.0 / 36.0)
                                let cu = ex * ux + ey * uy
                                q[i] += g * wi * (3 * ((ex - ux) * fx + (ey - uy) * fy) + 9 * cu * (ex * fx + ey * fy))
                            }
                        }
                    }
                }
            }
        }

        func stream(_ src: UnsafeMutablePointer<Double>, _ dst: UnsafeMutablePointer<Double>) {
            DispatchQueue.concurrentPerform(iterations: chunks) { k in
                let y0 = k * ny / chunks, y1 = (k + 1) * ny / chunks
                for y in y0..<y1 {
                    for x in 0..<nx {
                        let c = y * nx + x
                        let b = c * 9
                        if solid[c] { continue }
                        for i in 0..<9 {
                            var sx = x - ci[i], sy = y - cj[i]
                            var dir = i
                            if sy < 0 || sy >= ny {
                                switch yb {
                                case .periodic: sy = (sy + ny) % ny
                                case .wall: dst[b + i] = src[b + op[i]]; continue
                                case .slip: sy = y; dir = mir[i]
                                }
                            }
                            if sx < 0 || sx >= nx {
                                if xb == .periodic { sx = (sx + nx) % nx }
                                else if sx < 0 { dst[b + i] = inf[i]; continue }
                                else { sx = nx - 1 }
                            }
                            let sc = sy * nx + sx
                            if solid[sc] { dst[b + i] = src[b + op[i]] }
                            else { dst[b + i] = src[sc * 9 + dir] }
                        }
                    }
                }
            }
        }

        while iterations < s.maxIterations {
            collide(cur)
            stream(cur, nxt)
            swap(&cur, &nxt)
            iterations += 1
            if let a = s.averageFrom, iterations > a {
                for c in 0..<n where !solid[c] { sux[c] += mux[c]; suy[c] += muy[c] }
                averaged += 1
            }
            if iterations % max(1, s.checkEvery) == 0 {
                var sum = 0.0, cnt = 0
                for c in 0..<n where !solid[c] { sum += (mux[c] * mux[c] + muy[c] * muy[c]).squareRoot(); cnt += 1 }
                let mean = cnt > 0 ? sum / Double(cnt) : 0
                if !mean.isFinite || mean > 0.6 { stable = false; break }
                if s.averageFrom == nil, s.tolerance > 0, prevMean >= 0, abs(mean - prevMean) <= s.tolerance * max(mean, 1e-12) { converged = true; break }
                prevMean = mean
            }
        }
        // Macroscopic fields of the final state (or the time average).
        var ux = [Double](repeating: 0, count: n), uy = ux, rho = [Double](repeating: 1, count: n)
        for c in 0..<n where !solid[c] {
            var r = 0.0, jx = 0.0, jy = 0.0
            for i in 0..<9 { let v = cur[c * 9 + i]; r += v; jx += v * Double(cx[i]); jy += v * Double(cy[i]) }
            rho[c] = r
            if averaged > 0 { ux[c] = sux[c] / Double(averaged); uy[c] = suy[c] / Double(averaged) }
            else if r > 1e-12 { ux[c] = (jx + 0.5 * fx) / r; uy[c] = (jy + 0.5 * fy) / r }
            if !ux[c].isFinite || !uy[c].isFinite { stable = false; ux[c] = 0; uy[c] = 0 }
        }
        if averaged > 0 { converged = stable }
        return Field(nx: nx, ny: ny, ux: ux, uy: uy, rho: rho, solid: lat.solid, iterations: iterations, converged: converged, stable: stable)
    }

    /// Analytic Poiseuille profile of a force-driven channel with half-way bounce-back walls (lattice units):
    /// u(y) = F / (2ν) · (y + ½)(H − ½ − y) for fluid rows y = 0…H−1.
    public static func poiseuille(y: Int, height: Int, force: Double, tau: Double) -> Double {
        let nu = (tau - 0.5) / 3
        let yy = Double(y) + 0.5
        return force / (2 * nu) * yy * (Double(height) - yy)
    }

    // MARK: Pedestrian-level study

    public struct Study {
        /// Samples in the WindStudy frame (metres, wind along +X), z = pedestrian height, velocity in m/s.
        public var samples: [WindStudy.Sample]
        public var field: Field
        /// Lattice origin (metres, rotated frame) and cell size (m).
        public var origin: Vec2
        public var cell: Double
        /// Free-stream pedestrian-level speed (m/s) from the log law.
        public var pedestrianSpeed: Double
        /// Largest speed-up factor relative to the free stream.
        public var maxAmplification: Double
        /// Share (%) of the analysed outdoor area in each Lawson comfort class.
        public var comfort: [String: Double]
    }

    /// Log-law speed at `height` (m) for a reference speed at `referenceHeight` over roughness z0.
    public static func logLaw(_ o: WindStudy.Options, height: Double) -> Double {
        let z0 = max(1e-4, o.roughness)
        let h = max(height, z0 * 1.01), r = max(o.referenceHeight, z0 * 1.01)
        return o.speed * log(h / z0) / log(r / z0)
    }

    /// Lattice obstacle mask from building triangles (metres, wind along +X): every triangle reaching above the
    /// pedestrian height is projected onto the plan (the mass above doors and windows closes the openings).
    public static func obstacles(_ tris: [(Vec3, Vec3, Vec3)], height: Double, origin: Vec2, cell: Double, nx: Int, ny: Int) -> Lattice {
        var lat = Lattice(nx: nx, ny: ny)
        func mark(_ p: Vec2) {
            let x = Int(((p.x - origin.x) / cell).rounded(.down)), y = Int(((p.y - origin.y) / cell).rounded(.down))
            if x >= 0, y >= 0, x < nx, y < ny { lat[x, y] = true }
        }
        for t in tris where max(t.0.z, t.1.z, t.2.z) > height {
            let a = Vec2(t.0.x, t.0.y), b = Vec2(t.1.x, t.1.y), c = Vec2(t.2.x, t.2.y)
            for (p, q) in [(a, b), (b, c), (c, a)] {
                let steps = max(1, Int((p.distance(to: q) / (cell * 0.4)).rounded(.up)))
                for k in 0...steps { mark(p + (q - p) * (Double(k) / Double(steps))) }
            }
            let area = (b - a).cross(c - a)
            guard abs(area) > 1e-12 else { continue }
            let lo = Vec2(min(a.x, b.x, c.x), min(a.y, b.y, c.y)), hi = Vec2(max(a.x, b.x, c.x), max(a.y, b.y, c.y))
            let x0 = max(0, Int(((lo.x - origin.x) / cell).rounded(.down))), x1 = min(nx - 1, Int(((hi.x - origin.x) / cell).rounded(.down)))
            let y0 = max(0, Int(((lo.y - origin.y) / cell).rounded(.down))), y1 = min(ny - 1, Int(((hi.y - origin.y) / cell).rounded(.down)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = Vec2(origin.x + (Double(x) + 0.5) * cell, origin.y + (Double(y) + 0.5) * cell)
                    let w0 = (b - a).cross(p - a) / area, w1 = (c - b).cross(p - b) / area, w2 = (a - c).cross(p - c) / area
                    if w0 >= 0, w1 >= 0, w2 >= 0 { lat[x, y] = true }
                }
            }
        }
        lat.fillEnclosed()
        return lat
    }

    /// Pedestrian-level wind screening of the model for the wind speed/direction/roughness of `o`.
    /// `cellSize` 0 picks the finest cell that keeps the lattice within `maxCells`.
    public static func study(_ doc: ArchiDocument, options o: WindStudy.Options, cellSize: Double = 0, maxCells: Int = 14_000,
                             maxIterations: Int = 12_000) -> Study? {
        let tris = WindStudy.buildingTriangles(doc, options: o)
        let tall = tris.filter { max($0.0.z, $0.1.z, $0.2.z) > o.sampleHeight }
        guard !tall.isEmpty else { return nil }
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for t in tall { for p in [t.0, t.1, t.2] { lo = Vec2(min(lo.x, p.x), min(lo.y, p.y)); hi = Vec2(max(hi.x, p.x), max(hi.y, p.y)) } }
        let size = max(hi.x - lo.x, hi.y - lo.y, 2)
        // Domain: 2.5 D upstream and to each side, 6 D downstream.
        let origin = Vec2(lo.x - 2.5 * size, lo.y - 2.5 * size)
        let lx = (hi.x - lo.x) + 8.5 * size, ly = (hi.y - lo.y) + 5 * size
        var cell = cellSize > 0 ? cellSize : (lx * ly / Double(max(1000, maxCells))).squareRoot()
        cell = max(cell, 0.05)
        let nx = max(20, Int((lx / cell).rounded(.up))), ny = max(10, Int((ly / cell).rounded(.up)))
        let lat = obstacles(tall, height: o.sampleHeight, origin: origin, cell: cell, nx: nx, ny: ny)
        var s = Settings()
        s.inletSpeed = 0.08; s.tau = 0.53; s.smagorinsky = 0.2
        let flowThrough = Int(Double(nx) / s.inletSpeed)
        s.averageFrom = min(maxIterations * 2 / 3, 2 * flowThrough)
        s.maxIterations = min(maxIterations, s.averageFrom! + flowThrough)
        s.checkEvery = 200
        let field = solve(lat, s)
        let ped = logLaw(o, height: o.sampleHeight)
        var samples: [WindStudy.Sample] = []
        var counts: [String: Int] = [:], total = 0, amp = 0.0
        for y in 0..<ny {
            for x in 0..<nx where !field.isSolid(x, y) {
                let v = field.velocity(x, y) * (ped / s.inletSpeed)
                let p = Vec3(origin.x + (Double(x) + 0.5) * cell, origin.y + (Double(y) + 0.5) * cell, o.sampleHeight)
                samples.append(WindStudy.Sample(p: p, u: Vec3(v.x, v.y, 0)))
                // Statistics near the building only (within one building size of its bounding box).
                if p.x > lo.x - size, p.x < hi.x + 2 * size, p.y > lo.y - size, p.y < hi.y + size {
                    counts[WindStudy.comfortClass(v.length), default: 0] += 1; total += 1
                    amp = max(amp, field.speed(x, y) / s.inletSpeed)
                }
            }
        }
        let comfort = counts.mapValues { 100 * Double($0) / Double(max(1, total)) }
        return Study(samples: samples, field: field, origin: origin, cell: cell, pedestrianSpeed: ped, maxAmplification: amp, comfort: comfort)
    }
}
