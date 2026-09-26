// Oanarina Archi Tool — GPL-3.0-or-later
// Two-dimensional steady-state heat conduction (ANL-026) after EN ISO 10211: a finite-volume model on a rectilinear
// grid (cells of solid material with conductivity λ, surrounding environments with an air temperature and a surface
// resistance, adiabatic cut-off planes), solved with the Jacobi-preconditioned conjugate gradient method. It gives the
// thermal coupling coefficient L2D of a junction and its linear thermal transmittance ψ = L2D − Σ U·l (external and
// internal dimensions). Verified against the analytic Fourier-series solution of a rectangle with one heated side
// (the analytic benchmark of EN ISO 10211 Annex C) and the one-dimensional U-value (ψ = 0 for a plain wall).
import Foundation

public enum HeatConduction2D {
    public enum Cell: Hashable {
        /// Solid material with conductivity λ (W/m·K).
        case solid(Double)
        /// Air of environment `index` (see `Model.environments`).
        case environment(Int)
        /// Outside the model (adiabatic).
        case adiabatic
    }

    public struct Environment: Hashable {
        public var temperature: Double
        /// Surface resistance Rs (m²K/W) between the air and the solid surface (0 = prescribed surface temperature).
        public var surfaceResistance: Double
        public init(temperature: Double, surfaceResistance: Double) { self.temperature = temperature; self.surfaceResistance = surfaceResistance }
    }

    public struct Model {
        /// Grid lines (m), ascending: nx + 1 and ny + 1 values.
        public var xs: [Double], ys: [Double]
        public var cells: [Cell]
        public var environments: [Environment]
        public var nx: Int { xs.count - 1 }
        public var ny: Int { ys.count - 1 }
        public subscript(x: Int, y: Int) -> Cell { cells[y * nx + x] }

        /// Model whose cells are classified by `material` at their centres.
        public init(xs: [Double], ys: [Double], environments: [Environment], material: (Vec2) -> Cell) {
            self.xs = xs; self.ys = ys; self.environments = environments
            var c: [Cell] = []
            c.reserveCapacity(max(0, xs.count - 1) * max(0, ys.count - 1))
            for j in 0..<max(0, ys.count - 1) {
                for i in 0..<max(0, xs.count - 1) { c.append(material(Vec2((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2))) }
            }
            cells = c
        }
    }

    public struct Result {
        public var model: Model
        /// Temperature per cell (NaN for environment and adiabatic cells).
        public var temperatures: [Double]
        /// Heat flow (W per metre of junction length) from the solid into each environment (negative = into the solid).
        public var heatFlow: [Double]
        public var iterations: Int
        public var converged: Bool

        public func cellIndex(at p: Vec2) -> Int? {
            func find(_ lines: [Double], _ v: Double) -> Int? {
                guard let f = lines.first, let l = lines.last, v >= f, v <= l else { return nil }
                var lo = 0, hi = lines.count - 1
                while hi - lo > 1 { let m = (lo + hi) / 2; if lines[m] <= v { lo = m } else { hi = m } }
                return lo
            }
            guard let i = find(model.xs, p.x), let j = find(model.ys, p.y) else { return nil }
            return j * model.nx + i
        }
        /// Temperature of the cell containing `p` (nil outside the solid).
        public func temperature(at p: Vec2) -> Double? {
            guard let c = cellIndex(at: p), temperatures[c].isFinite else { return nil }
            return temperatures[c]
        }
        /// Centre of the cell containing `p`.
        public func cellCenter(at p: Vec2) -> Vec2? {
            guard let c = cellIndex(at: p) else { return nil }
            let i = c % model.nx, j = c / model.nx
            return Vec2((model.xs[i] + model.xs[i + 1]) / 2, (model.ys[j] + model.ys[j + 1]) / 2)
        }
        /// Lowest surface-cell temperature next to environment `env` (for the temperature factor fRsi).
        public func minimumSurfaceTemperature(env: Int) -> Double? {
            let nx = model.nx, ny = model.ny
            var best: Double?
            for j in 0..<ny {
                for i in 0..<nx {
                    let c = j * nx + i
                    guard temperatures[c].isFinite else { continue }
                    let nb = [(i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1)]
                    guard nb.contains(where: { $0.0 >= 0 && $0.0 < nx && $0.1 >= 0 && $0.1 < ny && model[$0.0, $0.1] == .environment(env) }) else { continue }
                    best = min(best ?? .infinity, temperatures[c])
                }
            }
            return best
        }
    }

    /// Grid lines through every break, subdivided so that no cell is wider than `maxStep`.
    public static func grid(_ breaks: [Double], maxStep: Double) -> [Double] {
        let b = Array(Set(breaks.map { ($0 * 1e9).rounded() / 1e9 })).sorted()
        guard b.count >= 2 else { return b }
        var out = [b[0]]
        for k in 1..<b.count {
            let a = b[k - 1], e = b[k]
            let n = max(1, Int(((e - a) / max(maxStep, 1e-6)).rounded(.up)))
            for s in 1...n { out.append(a + (e - a) * Double(s) / Double(n)) }
        }
        return out
    }

    /// Solves the steady-state temperature field.
    public static func solve(_ m: Model, tolerance: Double = 1e-11, maxIterations: Int = 50_000) -> Result {
        let nx = m.nx, ny = m.ny
        var index = [Int](repeating: -1, count: nx * ny)
        var lambdas: [Double] = []
        var cellOf: [Int] = []
        for c in 0..<(nx * ny) { if case .solid(let l) = m.cells[c] { index[c] = cellOf.count; cellOf.append(c); lambdas.append(max(l, 1e-9)) } }
        let n = cellOf.count
        var temps = [Double](repeating: .nan, count: nx * ny)
        var flows = [Double](repeating: 0, count: m.environments.count)
        guard n > 0 else { return Result(model: m, temperatures: temps, heatFlow: flows, iterations: 0, converged: true) }
        // Assemble: diagonal, off-diagonal couplings, right-hand side and environment couplings.
        var diag = [Double](repeating: 0, count: n), rhs = [Double](repeating: 0, count: n)
        var nbStart = [Int](repeating: 0, count: n + 1), nbIdx: [Int] = [], nbG: [Double] = []
        var envLinks: [(cell: Int, env: Int, g: Double)] = []
        for u in 0..<n {
            let c = cellOf[u], i = c % nx, j = c / nx
            let dx = m.xs[i + 1] - m.xs[i], dy = m.ys[j + 1] - m.ys[j], lam = lambdas[u]
            for (di, dj) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let ii = i + di, jj = j + dj
                guard ii >= 0, ii < nx, jj >= 0, jj < ny else { continue }
                let horizontal = di != 0
                let area = horizontal ? dy : dx, half = (horizontal ? dx : dy) / 2
                switch m[ii, jj] {
                case .solid(let l2):
                    let d2 = (horizontal ? (m.xs[ii + 1] - m.xs[ii]) : (m.ys[jj + 1] - m.ys[jj])) / 2
                    let g = area / (half / lam + d2 / max(l2, 1e-9))
                    diag[u] += g; nbIdx.append(index[jj * nx + ii]); nbG.append(g)
                case .environment(let k):
                    guard k >= 0, k < m.environments.count else { continue }
                    let e = m.environments[k]
                    let g = area / (half / lam + max(0, e.surfaceResistance))
                    diag[u] += g; rhs[u] += g * e.temperature
                    envLinks.append((u, k, g))
                case .adiabatic: break
                }
            }
            nbStart[u + 1] = nbIdx.count
        }
        func apply(_ x: [Double], _ y: inout [Double]) {
            for u in 0..<n {
                var s = diag[u] * x[u]
                for k in nbStart[u]..<nbStart[u + 1] { s -= nbG[k] * x[nbIdx[k]] }
                y[u] = s
            }
        }
        // Preconditioned conjugate gradients.
        let t0 = m.environments.map(\.temperature).reduce(0, +) / Double(max(1, m.environments.count))
        var x = [Double](repeating: t0, count: n)
        var ax = [Double](repeating: 0, count: n)
        apply(x, &ax)
        var r = (0..<n).map { rhs[$0] - ax[$0] }
        var z = (0..<n).map { diag[$0] > 0 ? r[$0] / diag[$0] : r[$0] }
        var p = z
        var rz = zip(r, z).reduce(0) { $0 + $1.0 * $1.1 }
        let bnorm = max(rhs.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-30)
        var it = 0, converged = false
        var ap = [Double](repeating: 0, count: n)
        while it < maxIterations {
            let rn = r.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if rn <= tolerance * bnorm { converged = true; break }
            apply(p, &ap)
            let pap = zip(p, ap).reduce(0) { $0 + $1.0 * $1.1 }
            guard pap > 0 else { break }
            let alpha = rz / pap
            for u in 0..<n { x[u] += alpha * p[u]; r[u] -= alpha * ap[u] }
            for u in 0..<n { z[u] = diag[u] > 0 ? r[u] / diag[u] : r[u] }
            let rz2 = zip(r, z).reduce(0) { $0 + $1.0 * $1.1 }
            let beta = rz2 / rz
            rz = rz2
            for u in 0..<n { p[u] = z[u] + beta * p[u] }
            it += 1
        }
        for u in 0..<n { temps[cellOf[u]] = x[u] }
        for l in envLinks { flows[l.env] += l.g * (x[l.cell] - m.environments[l.env].temperature) }
        return Result(model: m, temperatures: temps, heatFlow: flows, iterations: it, converged: converged)
    }
}

/// Linear thermal transmittance of typical envelope junctions computed numerically (EN ISO 10211).
public enum JunctionPsi {
    public struct Layer: Hashable {
        public var thickness: Double   // m
        public var lambda: Double      // W/m·K
        public init(_ thickness: Double, _ lambda: Double) { self.thickness = thickness; self.lambda = lambda }
    }
    public struct Result: Hashable {
        /// Thermal coupling coefficient per metre (W/m·K).
        public var l2d: Double
        /// U-value of the plain wall (W/m²K).
        public var u: Double
        public var psiExternal: Double
        public var psiInternal: Double
        /// Temperature factor at the internal surface, fRsi = (θsi,min − θe)/(θi − θe).
        public var fRsi: Double
        public var converged: Bool
    }

    public static func thickness(_ layers: [Layer]) -> Double { layers.reduce(0) { $0 + max(0, $1.thickness) } }
    public static func uValue(_ layers: [Layer], rsi: Double = 0.13, rse: Double = 0.04) -> Double {
        1 / (rsi + rse + layers.reduce(0) { $0 + max(0, $1.thickness) / max($1.lambda, 1e-9) })
    }
    /// λ at `depth` measured from the face where `layers[0]` starts.
    static func lambda(_ layers: [Layer], depth: Double) -> Double {
        var acc = 0.0
        for l in layers { acc += max(0, l.thickness); if depth < acc { return l.lambda } }
        return layers.last?.lambda ?? 1
    }
    static func breaks(_ layers: [Layer]) -> [Double] {
        var acc = 0.0, out = [0.0]
        for l in layers { acc += max(0, l.thickness); out.append(acc) }
        return out
    }
    static let envOut = 0, envIn = 1

    static func run(_ xs: [Double], _ ys: [Double], rsi: Double, rse: Double, _ material: (Vec2) -> HeatConduction2D.Cell) -> (l2d: Double, fRsi: Double, converged: Bool) {
        let m = HeatConduction2D.Model(xs: xs, ys: ys, environments: [.init(temperature: 0, surfaceResistance: rse), .init(temperature: 1, surfaceResistance: rsi)], material: material)
        let r = HeatConduction2D.solve(m)
        // Heat entering the solid from the inside equals the heat leaving to the outside at convergence.
        let l2d = (r.heatFlow[envOut] - r.heatFlow[envIn]) / 2
        return (l2d, r.minimumSurfaceTemperature(env: envIn) ?? 1, r.converged)
    }

    /// A plain wall of `length` (verification: ψ = 0).
    public static func plainWall(_ layers: [Layer], length: Double = 1, rsi: Double = 0.13, rse: Double = 0.04, maxCell: Double = 0.01) -> Result {
        let d = thickness(layers), u = uValue(layers, rsi: rsi, rse: rse)
        let xs = HeatConduction2D.grid([0, length], maxStep: maxCell * 5)
        let ys = HeatConduction2D.grid([-0.02] + breaks(layers) + [d + 0.02], maxStep: maxCell)
        let r = run(xs, ys, rsi: rsi, rse: rse) { p in
            if p.y < 0 { return .environment(envOut) }
            if p.y > d { return .environment(envIn) }
            return .solid(lambda(layers, depth: p.y))
        }
        return Result(l2d: r.l2d, u: u, psiExternal: r.l2d - u * length, psiInternal: r.l2d - u * length, fRsi: r.fRsi, converged: r.converged)
    }

    /// Two walls meeting at a right angle (layers listed from the outside face). `reentrant`: the outside is the
    /// concave side. Legs are `leg` metres long from the outer corner (≥ 1 m per EN ISO 10211).
    public static func corner(_ layers: [Layer], reentrant: Bool = false, leg: Double = 1.0, rsi: Double = 0.13, rse: Double = 0.04, maxCell: Double = 0.01) -> Result {
        let d = thickness(layers), u = uValue(layers, rsi: rsi, rse: rse)
        let L = max(leg, d + 0.2)
        let fromConvex = reentrant ? Array(layers.reversed()) : layers
        let br = breaks(fromConvex)
        let lines = HeatConduction2D.grid([-0.02] + br + [L], maxStep: maxCell)
        let convexEnv = reentrant ? envIn : envOut, concaveEnv = reentrant ? envOut : envIn
        let r = run(lines, lines, rsi: rsi, rse: rse) { p in
            if p.x < 0 || p.y < 0 { return (p.x > L || p.y > L) ? .adiabatic : .environment(convexEnv) }
            if p.x > L || p.y > L { return .adiabatic }
            if p.x > d && p.y > d { return .environment(concaveEnv) }
            return .solid(lambda(fromConvex, depth: min(p.x, p.y)))
        }
        // Surface lengths: the convex side measures L per leg, the concave side L − d.
        let outsideLength = reentrant ? 2 * (L - d) : 2 * L
        let insideLength = reentrant ? 2 * L : 2 * (L - d)
        return Result(l2d: r.l2d, u: u, psiExternal: r.l2d - u * outsideLength, psiInternal: r.l2d - u * insideLength, fRsi: r.fRsi, converged: r.converged)
    }

    /// Intermediate floor slab meeting an exterior wall (layers from the outside face). The slab bears on the wall
    /// behind its outermost insulating layer (λ ≤ 0.1), or passes through it as a cantilevered balcony when
    /// `balcony` > 0 (projection in metres, insulation interrupted).
    public static func floorEdge(wall layers: [Layer], slabThickness ts: Double, slabLambda: Double, balcony: Double = 0,
                                 leg: Double = 1.0, rsi: Double = 0.13, rse: Double = 0.04, maxCell: Double = 0.01) -> Result {
        let d = thickness(layers), u = uValue(layers, rsi: rsi, rse: rse)
        let L = max(leg, ts + 0.2)
        let slabIn = max(1.0, L)
        var start = 0.0
        if balcony > 0 { start = -balcony }
        else {
            var acc = 0.0
            for l in layers { acc += max(0, l.thickness); if l.lambda <= 0.1 { start = acc; break } }
        }
        let xs = HeatConduction2D.grid([min(start, 0) - 0.02, start, d + slabIn] + breaks(layers), maxStep: maxCell)
        let ys = HeatConduction2D.grid([-L, -ts / 2, ts / 2, L], maxStep: maxCell)
        let r = run(xs, ys, rsi: rsi, rse: rse) { p in
            if abs(p.y) < ts / 2, p.x >= start, p.x <= d + slabIn { return .solid(slabLambda) }
            if p.x > d + slabIn || abs(p.y) > L { return .adiabatic }
            if p.x < 0 { return .environment(envOut) }
            if p.x > d { return .environment(envIn) }
            return .solid(lambda(layers, depth: p.x))
        }
        return Result(l2d: r.l2d, u: u, psiExternal: r.l2d - u * 2 * L, psiInternal: r.l2d - u * (2 * L - ts), fRsi: r.fRsi, converged: r.converged)
    }
}
