// Oanarina Archi Tool — GPL-3.0-or-later
// STEP B-rep tessellation (IO-040): reads the exact geometry of AP203/AP214/AP242 models without a CAD kernel.
// Edge curves: lines, circles, ellipses, polylines, B-spline / Bézier / rational curves (de Boor), composite, trimmed,
// surface and seam curves. Face surfaces: planes, cylinders, cones, spheres, tori, B-spline / Bézier / rational
// surfaces, surfaces of linear extrusion and of revolution. Each face's boundary loops are mapped into the surface's
// parameter plane (periodic seams unwrapped, poles of spheres and cones split, seam-less bands of cylinders closed),
// triangulated there with a constrained Delaunay triangulation refined by interior Steiner points on doubly curved
// surfaces, and mapped back onto the surface. AP242 tessellated geometry (triangulated faces, strips, fans) and
// assembly placements (mapped items, representation relationships with transformation) are read as well.
// Algorithms after "The NURBS Book" (Piegl & Tiller: A2.1 span search, A2.2 basis functions) and Lawson's flip
// algorithm for constrained Delaunay triangulations.
import Foundation

/// Orthonormal (optionally scaled) placement: columns x, y, z and origin o.
struct StepXform {
    var o: Vec3, x: Vec3, y: Vec3, z: Vec3
    static let identity = StepXform(o: .zero, x: Vec3(1, 0, 0), y: Vec3(0, 1, 0), z: Vec3(0, 0, 1))
    func apply(_ p: Vec3) -> Vec3 { o + x * p.x + y * p.y + z * p.z }
    func applyDir(_ v: Vec3) -> Vec3 { x * v.x + y * v.y + z * v.z }
    /// Inverse of a rigid frame (scale is undone through the squared column lengths).
    var inverse: StepXform {
        let sx = max(x.dot(x), 1e-300), sy = max(y.dot(y), 1e-300), sz = max(z.dot(z), 1e-300)
        let rx = Vec3(x.x / sx, y.x / sy, z.x / sz), ry = Vec3(x.y / sx, y.y / sy, z.y / sz), rz = Vec3(x.z / sx, y.z / sy, z.z / sz)
        let io = -(rx * o.x + ry * o.y + rz * o.z)
        return StepXform(o: io, x: rx, y: ry, z: rz)
    }
    /// `a ∘ b` (b first).
    static func * (a: StepXform, b: StepXform) -> StepXform {
        StepXform(o: a.apply(b.o), x: a.applyDir(b.x), y: a.applyDir(b.y), z: a.applyDir(b.z))
    }
    var isIdentity: Bool {
        o.length < 1e-12 && (x - Vec3(1, 0, 0)).length < 1e-12 && (y - Vec3(0, 1, 0)).length < 1e-12 && (z - Vec3(0, 0, 1)).length < 1e-12
    }
}

/// B-spline basis evaluation (The NURBS Book A2.1 / A2.2).
enum StepNURBS {
    static func span(_ n: Int, _ p: Int, _ t: Double, _ U: [Double]) -> Int {
        if t >= U[n + 1] { var s = n; while s > p && U[s] >= U[n + 1] { s -= 1 }; return max(p, s) }
        if t <= U[p] { var s = p; while s < n && U[s + 1] <= U[p] { s += 1 }; return s }
        var lo = p, hi = n + 1, mid = (lo + hi) / 2
        while t < U[mid] || t >= U[mid + 1] {
            if t < U[mid] { hi = mid } else { lo = mid }
            mid = (lo + hi) / 2
            if hi - lo <= 1 { mid = lo; break }
        }
        return mid
    }
    static func basis(_ i: Int, _ t: Double, _ p: Int, _ U: [Double]) -> [Double] {
        var N = [Double](repeating: 0, count: p + 1), left = N, right = N
        N[0] = 1
        if p == 0 { return N }
        for j in 1...p {
            left[j] = t - U[i + 1 - j]; right[j] = U[i + j] - t
            var saved = 0.0
            for r in 0..<j {
                let den = right[r + 1] + left[j - r]
                let tmp = abs(den) < 1e-300 ? 0 : N[r] / den
                N[r] = saved + right[r + 1] * tmp
                saved = left[j - r] * tmp
            }
            N[j] = saved
        }
        return N
    }
    /// Expanded knot vector from distinct knots and multiplicities.
    static func expand(_ mults: [Int], _ knots: [Double]) -> [Double] {
        var U: [Double] = []
        for (m, k) in zip(mults, knots) { U += [Double](repeating: k, count: max(0, m)) }
        return U
    }
    /// Knots for curves given without them (Bézier, uniform, quasi-uniform).
    static func implicitKnots(_ form: String, count n: Int, degree p: Int) -> [Double] {
        switch form {
        case "UNIFORM": return (0..<(n + p + 1)).map { Double($0 - p) }
        case "QUASI_UNIFORM":
            let inner = max(0, n - p - 1)
            return [Double](repeating: 0, count: p + 1) + (0..<inner).map { Double($0 + 1) } + [Double](repeating: Double(inner + 1), count: p + 1)
        default: // Bézier: a single span
            return [Double](repeating: 0, count: p + 1) + [Double](repeating: 1, count: p + 1)
        }
    }
}

struct StepBSplineCurve {
    var degree: Int, points: [Vec3], weights: [Double]?, knots: [Double]
    var range: (Double, Double) { (knots[degree], knots[points.count]) }
    var isValid: Bool { degree >= 1 && points.count > degree && knots.count == points.count + degree + 1 && range.1 > range.0 }
    func eval(_ t: Double) -> Vec3 {
        let n = points.count - 1
        let s = StepNURBS.span(n, degree, t, knots)
        let N = StepNURBS.basis(s, t, degree, knots)
        var p = Vec3.zero, w = 0.0
        for j in 0...degree {
            let i = s - degree + j
            let wi = weights?[i] ?? 1
            p = p + points[i] * (N[j] * wi); w += N[j] * wi
        }
        return abs(w) > 1e-300 ? p / w : p
    }
}

struct StepBSplineSurface {
    var du: Int, dv: Int
    var points: [[Vec3]]            // [u][v]
    var weights: [[Double]]?
    var ku: [Double], kv: [Double]
    /// Closed directions (the surface meets itself across the parameter range) and collapsed boundary rows (poles).
    var periodU: Double? = nil, periodV: Double? = nil
    var poleV0 = false, poleV1 = false
    var uRange: (Double, Double) { (ku[du], ku[points.count]) }
    var vRange: (Double, Double) { (kv[dv], kv[points[0].count]) }
    var isValid: Bool {
        guard du >= 1, dv >= 1, points.count > du, let c = points.first?.count, c > dv, points.allSatisfy({ $0.count == c }) else { return false }
        return ku.count == points.count + du + 1 && kv.count == c + dv + 1 && uRange.1 > uRange.0 && vRange.1 > vRange.0
    }
    func eval(_ u: Double, _ v: Double) -> Vec3 {
        let nu = points.count - 1, nv = points[0].count - 1
        let su = StepNURBS.span(nu, du, u, ku), sv = StepNURBS.span(nv, dv, v, kv)
        let Nu = StepNURBS.basis(su, u, du, ku), Nv = StepNURBS.basis(sv, v, dv, kv)
        var p = Vec3.zero, w = 0.0
        for a in 0...du {
            let i = su - du + a
            for b in 0...dv {
                let j = sv - dv + b
                let wij = weights?[i][j] ?? 1
                let c = Nu[a] * Nv[b] * wij
                p = p + points[i][j] * c; w += c
            }
        }
        return abs(w) > 1e-300 ? p / w : p
    }
}

/// A polyline parameterised by arc length (profiles of extrusion / revolution surfaces).
struct StepArcPolyline {
    var pts: [Vec3]
    var cum: [Double]
    init(_ p: [Vec3]) {
        pts = p; cum = [0]
        for i in 1..<max(1, p.count) { cum.append(cum[i - 1] + (p[i] - p[i - 1]).length) }
    }
    var length: Double { cum.last ?? 0 }
    var closed: Bool { pts.count > 3 && (pts[0] - pts[pts.count - 1]).length <= max(length, 1e-12) * 1e-9 }
    func eval(_ s: Double) -> Vec3 {
        guard pts.count > 1 else { return pts.first ?? .zero }
        if s <= 0 { let d = pts[1] - pts[0]; let l = max(d.length, 1e-300); return pts[0] + d * (s / l) }
        if s >= length { let n = pts.count; let d = pts[n - 1] - pts[n - 2]; let l = max(d.length, 1e-300); return pts[n - 1] + d * ((s - length) / l) }
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= s { lo = m } else { hi = m } }
        let seg = cum[hi] - cum[lo]
        let t = seg > 1e-300 ? (s - cum[lo]) / seg : 0
        return pts[lo] + (pts[hi] - pts[lo]) * t
    }
    func project(_ q: Vec3) -> Double {
        guard pts.count > 1 else { return 0 }
        var best = 0.0, bd = Double.infinity
        for i in 0..<(pts.count - 1) {
            let a = pts[i], d = pts[i + 1] - a
            let l2 = d.dot(d)
            let t = l2 > 1e-300 ? max(0, min(1, (q - a).dot(d) / l2)) : 0
            let dist = (a + d * t - q).length
            if dist < bd { bd = dist; best = cum[i] + t * (cum[i + 1] - cum[i]) }
        }
        return best
    }
}

enum StepSurface {
    case plane(StepXform)
    case cylinder(StepXform, Double)
    case cone(StepXform, Double, Double)          // radius at v = 0, tan(semi-angle)
    case sphere(StepXform, Double)
    case torus(StepXform, Double, Double)         // major, minor
    case bspline(StepBSplineSurface)
    case extrusion(StepArcPolyline, Vec3)         // profile, unit direction
    case revolution(StepArcPolyline, StepXform)   // profile, axis frame (z = axis, x = towards the profile)

    var periodU: Double? {
        switch self {
        case .cylinder, .cone, .sphere, .torus, .revolution: return 2 * .pi
        case .bspline(let b): return b.periodU
        case .extrusion(let c, _): return c.closed ? c.length : nil
        default: return nil
        }
    }
    var periodV: Double? {
        switch self {
        case .torus: return 2 * .pi
        case .bspline(let b): return b.periodV
        case .revolution(let c, _): return c.closed ? c.length : nil
        default: return nil
        }
    }
    var isPlanar: Bool { if case .plane = self { return true }; return false }

    func eval(_ u: Double, _ v: Double) -> Vec3 {
        switch self {
        case .plane(let f): return f.apply(Vec3(u, v, 0))
        case .cylinder(let f, let r): return f.apply(Vec3(r * cos(u), r * sin(u), v))
        case .cone(let f, let r, let t): let rr = r + v * t; return f.apply(Vec3(rr * cos(u), rr * sin(u), v))
        case .sphere(let f, let r): return f.apply(Vec3(r * cos(v) * cos(u), r * cos(v) * sin(u), r * sin(v)))
        case .torus(let f, let R, let r): let rr = R + r * cos(v); return f.apply(Vec3(rr * cos(u), rr * sin(u), r * sin(v)))
        case .bspline(let s):
            let (u0, u1) = s.uRange, (v0, v1) = s.vRange
            return s.eval(max(u0, min(u1, u)), max(v0, min(v1, v)))
        case .extrusion(let c, let d): return c.eval(u) + d * v
        case .revolution(let c, let f):
            let q = f.inverse.apply(c.eval(v))          // profile point in the axis frame
            let rho = (q.x * q.x + q.y * q.y).squareRoot(), a0 = atan2(q.y, q.x)
            return f.apply(Vec3(rho * cos(a0 + u), rho * sin(a0 + u), q.z))
        }
    }

    /// Parameters of a point on (or near) the surface; `u` is NaN at a pole (sphere poles, cone apex).
    func param(_ p: Vec3, hint: Vec2?, grid: [(Vec2, Vec3)]) -> Vec2 {
        switch self {
        case .plane(let f): let q = f.inverse.apply(p); return Vec2(q.x, q.y)
        case .cylinder(let f, _):
            let q = f.inverse.apply(p); return Vec2(atan2(q.y, q.x), q.z)
        case .cone(let f, let r, let t):
            let q = f.inverse.apply(p)
            let rho = (q.x * q.x + q.y * q.y).squareRoot()
            return Vec2(rho < 1e-9 * max(1, abs(r)) || abs(t) > 1e9 ? .nan : atan2(q.y, q.x), q.z)
        case .sphere(let f, let r):
            let q = f.inverse.apply(p)
            let rho = (q.x * q.x + q.y * q.y).squareRoot()
            let v = atan2(q.z, rho)
            return Vec2(rho < 1e-9 * max(1, r) ? .nan : atan2(q.y, q.x), v)
        case .torus(let f, let R, _):
            let q = f.inverse.apply(p)
            let rho = (q.x * q.x + q.y * q.y).squareRoot()
            return Vec2(atan2(q.y, q.x), atan2(q.z, rho - R))
        case .extrusion(let c, let d):
            let v = (p - c.pts[0]).dot(d)
            return Vec2(c.project(p - d * v), v)
        case .revolution(let c, let f):
            let q = f.inverse.apply(p)
            let rho = (q.x * q.x + q.y * q.y).squareRoot()
            // Profile half-plane: rotate the point back to the profile's own angle.
            let prof0 = f.inverse.apply(c.pts[0])
            let a0 = atan2(prof0.y, prof0.x)
            let s = c.project(f.apply(Vec3(rho * cos(a0), rho * sin(a0), q.z)))
            return Vec2(rho < 1e-9 ? .nan : atan2(q.y, q.x) - a0, s)
        case .bspline(let s):
            let q = StepSurface.newton(s, p, hint: hint, grid: grid)
            let (v0, v1) = s.vRange, tv = (v1 - v0) * 1e-7
            if (s.poleV0 && q.y - v0 < tv) || (s.poleV1 && v1 - q.y < tv) { return Vec2(.nan, q.y) }
            return q
        }
    }

    static func newton(_ s: StepBSplineSurface, _ p: Vec3, hint: Vec2?, grid: [(Vec2, Vec3)]) -> Vec2 {
        let (u0, u1) = s.uRange, (v0, v1) = s.vRange
        var starts: [Vec2] = []
        if let g = grid.min(by: { ($0.1 - p).length < ($1.1 - p).length }) { starts.append(g.0) }
        if let h = hint, h.x.isFinite, h.y.isFinite { starts.append(h) }
        if starts.isEmpty { starts.append(Vec2((u0 + u1) / 2, (v0 + v1) / 2)) }
        var best = starts[0], bestD = Double.infinity
        let hu = (u1 - u0) * 1e-5, hv = (v1 - v0) * 1e-5
        for st in starts {
            var u = st.x, v = st.y
            for _ in 0..<25 {
                let S = s.eval(u, v)
                let r = S - p
                let uu = u + hu <= u1 ? u + hu : u - hu, vv = v + hv <= v1 ? v + hv : v - hv
                let Su = (s.eval(uu, v) - S) / (uu - u), Sv = (s.eval(u, vv) - S) / (vv - v)
                let a = Su.dot(Su), b = Su.dot(Sv), c = Sv.dot(Sv)
                let det = a * c - b * b
                guard abs(det) > 1e-300 else { break }
                let gu = Su.dot(r), gv = Sv.dot(r)
                let du = (c * gu - b * gv) / det, dv = (a * gv - b * gu) / det
                let nu = max(u0, min(u1, u - du)), nv = max(v0, min(v1, v - dv))
                let moved = abs(nu - u) / (u1 - u0) + abs(nv - v) / (v1 - v0)
                u = nu; v = nv
                if moved < 1e-10 { break }
            }
            let d = (s.eval(u, v) - p).length
            if d < bestD { bestD = d; best = Vec2(u, v) }
        }
        return best
    }

    /// Normal (∂S/∂u × ∂S/∂v, not normalised) by central differences.
    func normal(_ u: Double, _ v: Double, scale: Vec2) -> Vec3 {
        let hu = max(1e-7, abs(scale.x) * 1e-4), hv = max(1e-7, abs(scale.y) * 1e-4)
        let su = eval(u + hu, v) - eval(u - hu, v), sv = eval(u, v + hv) - eval(u, v - hv)
        return su.cross(sv)
    }
}

/// Constrained Delaunay triangulation of polygons with holes (even–odd rule): incremental Delaunay insertion with
/// Lawson flips inside a super-triangle, constraint recovery by flipping (Sloan 1993), flood-fill classification across
/// the constrained edges, then Steiner points inserted into the inside triangles.
struct StepCDT {
    var pts: [Vec2] = []
    var tv: [Int] = []
    var alive: [Bool] = []
    var inside: [Bool] = []
    var edges: [UInt64: (Int, Int)] = [:]
    var constrained: Set<UInt64> = []
    var last = 0

    static func key(_ a: Int, _ b: Int) -> UInt64 { let (x, y) = a < b ? (a, b) : (b, a); return UInt64(x) << 32 | UInt64(y) }
    static func orient(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> Double { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
    static func inCircle(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Double {
        let ax = a.x - d.x, ay = a.y - d.y, bx = b.x - d.x, by = b.y - d.y, cx = c.x - d.x, cy = c.y - d.y
        return (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay)
    }
    static func properCross(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Bool {
        let d1 = orient(a, b, c), d2 = orient(a, b, d), d3 = orient(c, d, a), d4 = orient(c, d, b)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    func verts(_ t: Int) -> (Int, Int, Int) { (tv[3 * t], tv[3 * t + 1], tv[3 * t + 2]) }
    mutating func link(_ e: UInt64, _ t: Int) {
        if var s = edges[e] { if s.0 < 0 { s.0 = t } else { s.1 = t }; edges[e] = s } else { edges[e] = (t, -1) }
    }
    mutating func unlink(_ e: UInt64, _ t: Int) {
        guard var s = edges[e] else { return }
        if s.0 == t { s.0 = s.1; s.1 = -1 } else if s.1 == t { s.1 = -1 }
        if s.0 < 0 { edges[e] = nil } else { edges[e] = s }
    }
    func neighbour(_ e: UInt64, of t: Int) -> Int? {
        guard let s = edges[e] else { return nil }
        let n = s.0 == t ? s.1 : s.0
        return n >= 0 && n != t ? n : nil
    }
    @discardableResult mutating func addTri(_ a: Int, _ b: Int, _ c: Int, _ ins: Bool) -> Int {
        var (b, c) = (b, c)
        if StepCDT.orient(pts[a], pts[b], pts[c]) < 0 { swap(&b, &c) }
        let t = alive.count
        tv += [a, b, c]; alive.append(true); inside.append(ins)
        link(StepCDT.key(a, b), t); link(StepCDT.key(b, c), t); link(StepCDT.key(c, a), t)
        last = t
        return t
    }
    mutating func removeTri(_ t: Int) {
        alive[t] = false
        let (a, b, c) = verts(t)
        unlink(StepCDT.key(a, b), t); unlink(StepCDT.key(b, c), t); unlink(StepCDT.key(c, a), t)
    }
    func third(_ t: Int, _ u: Int, _ v: Int) -> Int {
        let (a, b, c) = verts(t)
        return a != u && a != v ? a : (b != u && b != v ? b : c)
    }
    func contains(_ t: Int, _ p: Vec2) -> Bool {
        let (a, b, c) = verts(t)
        return StepCDT.orient(pts[a], pts[b], p) >= 0 && StepCDT.orient(pts[b], pts[c], p) >= 0 && StepCDT.orient(pts[c], pts[a], p) >= 0
    }

    /// Triangle containing `p`: a visibility walk from the last triangle, else a scan.
    func locate(_ p: Vec2) -> Int? {
        var t = last < alive.count && alive[last] ? last : (alive.lastIndex(of: true) ?? -1)
        guard t >= 0 else { return nil }
        var steps = 0
        walk: while steps < 20_000 {
            steps += 1
            let (a, b, c) = verts(t)
            let e = [(a, b), (b, c), (c, a)]
            for j in 0..<3 {
                let (u, v) = e[(j + steps) % 3]
                if StepCDT.orient(pts[u], pts[v], p) < 0 {
                    guard let n = neighbour(StepCDT.key(u, v), of: t) else { break walk }
                    t = n
                    continue walk
                }
            }
            return t
        }
        for i in alive.indices where alive[i] && contains(i, p) { return i }
        return nil
    }

    /// Inserts point `pi` (already in `pts`). False when it coincides with a vertex, lies on a constrained edge or,
    /// with `onlyInside`, falls outside the domain; nothing is changed then.
    mutating func insert(_ pi: Int, onlyInside: Bool = false) -> Bool {
        let p = pts[pi]
        guard let t = locate(p) else { return false }
        if onlyInside && !inside[t] { return false }
        let (a, b, c) = verts(t)
        let v = [a, b, c]
        let scale = max((pts[a] - pts[b]).length, (pts[b] - pts[c]).length, (pts[c] - pts[a]).length, 1e-300)
        if v.contains(where: { (pts[$0] - p).length <= scale * 1e-10 }) { return false }
        let area = StepCDT.orient(pts[a], pts[b], pts[c])
        let w = [StepCDT.orient(pts[b], pts[c], p), StepCDT.orient(pts[c], pts[a], p), StepCDT.orient(pts[a], pts[b], p)]
        let eps = abs(area) * 1e-9
        let ins = inside[t]
        var stack: [UInt64] = []
        if let k = (0..<3).first(where: { abs(w[$0]) <= eps }) {
            let o = v[k], e0 = v[(k + 1) % 3], e1 = v[(k + 2) % 3]
            let ek = StepCDT.key(e0, e1)
            if constrained.contains(ek) { return false }
            let n = neighbour(ek, of: t)
            removeTri(t)
            addTri(o, e0, pi, ins); addTri(e1, o, pi, ins)
            stack += [StepCDT.key(o, e0), StepCDT.key(e1, o)]
            if let n {
                let q = third(n, e0, e1), nIns = inside[n]
                removeTri(n)
                addTri(e0, q, pi, nIns); addTri(q, e1, pi, nIns)
                stack += [StepCDT.key(e0, q), StepCDT.key(q, e1)]
            }
        } else {
            removeTri(t)
            addTri(a, b, pi, ins); addTri(b, c, pi, ins); addTri(c, a, pi, ins)
            stack += [StepCDT.key(a, b), StepCDT.key(b, c), StepCDT.key(c, a)]
        }
        legalize(&stack)
        return true
    }

    mutating func legalize(_ stack: inout [UInt64]) {
        var guardN = 0
        while let e = stack.popLast(), guardN < 500_000 {
            guardN += 1
            if constrained.contains(e) { continue }
            guard let s = edges[e], s.0 >= 0, s.1 >= 0 else { continue }
            let u = Int(e >> 32), v = Int(e & 0xffff_ffff)
            let c = third(s.0, u, v), d = third(s.1, u, v)
            var (p, q) = (u, v)
            if StepCDT.orient(pts[p], pts[q], pts[c]) < 0 { swap(&p, &q) }
            let scale = max((pts[p] - pts[q]).length, (pts[c] - pts[d]).length, 1e-300)
            guard StepCDT.inCircle(pts[p], pts[q], pts[c], pts[d]) > 1e-12 * pow(scale, 4) else { continue }
            guard StepCDT.properCross(pts[c], pts[d], pts[p], pts[q]) else { continue }
            let ins = inside[s.0]
            removeTri(s.0); removeTri(s.1)
            addTri(p, d, c, ins); addTri(d, q, c, ins)
            stack += [StepCDT.key(p, d), StepCDT.key(d, q), StepCDT.key(q, c), StepCDT.key(c, p)]
        }
    }

    /// Makes a–b an edge of the triangulation (splitting it at vertices lying on it) and marks it constrained.
    mutating func enforce(_ a: Int, _ b: Int, depth: Int = 0) {
        guard a != b else { return }
        let k = StepCDT.key(a, b)
        if edges[k] != nil { constrained.insert(k); return }
        let pa = pts[a], pb = pts[b], d = pb - pa, L2 = d.x * d.x + d.y * d.y
        guard L2 > 0 else { return }
        if depth < 64 {
            for i in 3..<pts.count where i != a && i != b {
                let q = pts[i]
                let t = ((q.x - pa.x) * d.x + (q.y - pa.y) * d.y) / L2
                guard t > 1e-9 && t < 1 - 1e-9 else { continue }
                if abs(StepCDT.orient(pa, pb, q)) <= 1e-9 * L2 { enforce(a, i, depth: depth + 1); enforce(i, b, depth: depth + 1); return }
            }
        }
        // Crossing edges in order along a→b (deterministic, and the order Sloan's algorithm works best in).
        var crossT: [(t: Double, u: Int, v: Int)] = []
        for (e, _) in edges {
            let u = Int(e >> 32), v = Int(e & 0xffff_ffff)
            if u == a || u == b || v == a || v == b { continue }
            if StepCDT.properCross(pa, pb, pts[u], pts[v]) {
                let q = pts[v] - pts[u]
                let den = d.x * q.y - d.y * q.x
                let t = abs(den) > 1e-300 ? ((pts[u].x - pa.x) * q.y - (pts[u].y - pa.y) * q.x) / den : 0.5
                crossT.append((t, min(u, v), max(u, v)))
            }
        }
        crossT.sort { $0.t != $1.t ? $0.t < $1.t : ($0.u, $0.v) < ($1.u, $1.v) }
        var cross: [(Int, Int)] = crossT.map { ($0.u, $0.v) }
        var guardN = 0, head = 0
        while head < cross.count, guardN < 50_000 {
            guardN += 1
            let (u, v) = cross[head]; head += 1
            guard let s = edges[StepCDT.key(u, v)], s.0 >= 0, s.1 >= 0 else { continue }
            let c = third(s.0, u, v), dd = third(s.1, u, v)
            if StepCDT.properCross(pts[c], pts[dd], pts[u], pts[v]) {
                let ins = inside[s.0]
                removeTri(s.0); removeTri(s.1)
                addTri(c, dd, u, ins); addTri(c, dd, v, ins)
                if c != a && c != b && dd != a && dd != b && StepCDT.properCross(pa, pb, pts[c], pts[dd]) { cross.append((c, dd)) }
            } else {
                cross.append((u, v))
            }
        }
        if edges[k] != nil { constrained.insert(k) }
    }

    /// Triangles inside the loops (even–odd), with the Steiner points added inside.
    static func triangulate(loops: [[Vec2]], steiner: [Vec2]) -> (points: [Vec2], triangles: [(Int, Int, Int)]) {
        let all = loops.flatMap { $0 }
        guard all.count >= 3 else { return ([], []) }
        var lo = Vec2(Double.infinity, Double.infinity), hi = Vec2(-Double.infinity, -Double.infinity)
        for q in all { lo = Vec2(min(lo.x, q.x), min(lo.y, q.y)); hi = Vec2(max(hi.x, q.x), max(hi.y, q.y)) }
        let size = max(hi.x - lo.x, hi.y - lo.y, 1e-9), ctr = Vec2((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)
        var c = StepCDT()
        let M = size * 50
        c.pts = [ctr + Vec2(-M, -M), ctr + Vec2(M, -M), ctr + Vec2(0, M)]
        c.addTri(0, 1, 2, false)
        var index: [Vec2: Int] = [:]
        var loopIdx: [[Int]] = []
        for l in loops {
            var li: [Int] = []
            for p in l {
                if let i = index[p] { li.append(i); continue }
                let i = c.pts.count
                c.pts.append(p)
                if c.insert(i) { index[p] = i; li.append(i) } else {
                    c.pts.removeLast()
                    var best = 3, bd = Double.infinity
                    for j in 3..<c.pts.count { let dd = (c.pts[j] - p).length; if dd < bd { bd = dd; best = j } }
                    if best < c.pts.count { index[p] = best; li.append(best) }
                }
            }
            loopIdx.append(li)
        }
        for li in loopIdx where li.count >= 2 {
            for i in 0..<li.count { c.enforce(li[i], li[(i + 1) % li.count]) }
        }
        // Classify: depth = number of constrained edges crossed from the super-triangle.
        var depth = [Int](repeating: -1, count: c.alive.count)
        var queue: [Int] = c.alive.indices.filter { t in
            guard c.alive[t] else { return false }
            let (a, b, cc) = c.verts(t); return a < 3 || b < 3 || cc < 3
        }
        for t in queue { depth[t] = 0 }
        var d = 0
        while !queue.isEmpty {
            var next: [Int] = []
            var qi = 0
            while qi < queue.count {
                let t = queue[qi]; qi += 1
                let (a, b, cc) = c.verts(t)
                for (u, v) in [(a, b), (b, cc), (cc, a)] {
                    let e = StepCDT.key(u, v)
                    guard let n = c.neighbour(e, of: t), depth[n] < 0 else { continue }
                    if c.constrained.contains(e) { next.append(n) } else { depth[n] = d; queue.append(n) }
                }
            }
            d += 1
            queue = []
            for t in next where depth[t] < 0 { depth[t] = d; queue.append(t) }
        }
        for t in c.alive.indices { c.inside[t] = depth[t] > 0 && depth[t] % 2 == 1 }
        for p in steiner {
            let i = c.pts.count
            c.pts.append(p)
            if !c.insert(i, onlyInside: true) { c.pts.removeLast() }
        }
        var out: [(Int, Int, Int)] = []
        for t in c.alive.indices where c.alive[t] && c.inside[t] {
            let (a, b, cc) = c.verts(t)
            if a >= 3 && b >= 3 && cc >= 3 { out.append((a, b, cc)) }
        }
        return (c.pts, out)
    }
}

/// Reads geometry of a parsed STEP file into meshes.
final class StepBRepReader {
    let f: STEPFile
    /// Output units per file length unit.
    let k: Double
    /// Radians per file plane-angle unit.
    let angleUnit: Double
    let angleStep = Double.pi / 16
    var surfaceCache: [Int: StepSurface?] = [:]
    var curveCache: [Int: [Vec3]] = [:]
    var gridCache: [Int: [(Vec2, Vec3)]] = [:]

    init(_ f: STEPFile, scale: Double) {
        self.f = f; self.k = scale
        angleUnit = StepUnits.resolve(f).radPerAngle
    }

    func args(_ e: StepEntity, _ part: String) -> [StepValue] { e.parts[part] ?? (e.type == part ? e.args : []) }

    func point(_ id: Int?) -> Vec3? {
        guard let e = f[id] else { return nil }
        if e.type == "VERTEX_POINT" { return point(e[1].ref) }
        guard e.type == "CARTESIAN_POINT", let c = e[1].list?.compactMap({ $0.double }), c.count >= 2 else { return nil }
        return Vec3(c[0], c[1], c.count > 2 ? c[2] : 0) * k
    }
    func direction(_ id: Int?) -> Vec3? {
        guard let e = f[id] else { return nil }
        if e.type == "VECTOR" { return direction(e[1].ref) }
        guard e.type == "DIRECTION", let c = e[1].list?.compactMap({ $0.double }), c.count >= 2 else { return nil }
        let v = Vec3(c[0], c[1], c.count > 2 ? c[2] : 0); return v.length > 1e-12 ? v * (1 / v.length) : nil
    }
    /// AXIS2_PLACEMENT_3D / AXIS1_PLACEMENT / CARTESIAN_TRANSFORMATION_OPERATOR_3D as a frame.
    func frame(_ id: Int?) -> StepXform? {
        guard let e = f[id] else { return nil }
        switch e.type {
        case "AXIS2_PLACEMENT_3D", "AXIS1_PLACEMENT", "AXIS2_PLACEMENT_2D":
            let o = point(e[1].ref) ?? .zero
            let z = e.type == "AXIS2_PLACEMENT_2D" ? Vec3(0, 0, 1) : (direction(e[2].ref) ?? Vec3(0, 0, 1))
            var x = e.type == "AXIS2_PLACEMENT_3D" ? (direction(e[3].ref) ?? Vec3(0, 0, 0)) : (e.type == "AXIS2_PLACEMENT_2D" ? (direction(e[2].ref) ?? Vec3(1, 0, 0)) : Vec3(0, 0, 0))
            x = x - z * x.dot(z)
            if x.length < 1e-9 { x = (abs(z.x) < 0.9 ? Vec3(1, 0, 0) : Vec3(0, 1, 0)); x = x - z * x.dot(z) }
            x = x * (1 / x.length)
            return StepXform(o: o, x: x, y: z.cross(x), z: z)
        default:
            let ops = args(e, "CARTESIAN_TRANSFORMATION_OPERATOR")
            guard !ops.isEmpty || e.type.hasPrefix("CARTESIAN_TRANSFORMATION_OPERATOR") else { return nil }
            let a = ops.isEmpty ? e.args : ops
            let o = point(a[stepSafe: 3]?.ref) ?? .zero
            let s = a[stepSafe: 4]?.double ?? 1
            var x = direction(a[stepSafe: 1]?.ref) ?? Vec3(1, 0, 0)
            let a3 = args(e, "CARTESIAN_TRANSFORMATION_OPERATOR_3D")
            var z = direction((e.type == "CARTESIAN_TRANSFORMATION_OPERATOR_3D" ? e[5] : a3.first ?? .null).ref) ?? Vec3(0, 0, 1)
            var y = direction(a[stepSafe: 2]?.ref) ?? z.cross(x)
            x = x * (1 / max(x.length, 1e-12)); z = z * (1 / max(z.length, 1e-12)); y = y * (1 / max(y.length, 1e-12))
            return StepXform(o: o, x: x * s, y: y * s, z: z * s)
        }
    }

    // MARK: Curves

    func bsplineCurve(_ e: StepEntity) -> StepBSplineCurve? {
        var b = args(e, "B_SPLINE_CURVE")
        var kn = args(e, "B_SPLINE_CURVE_WITH_KNOTS")
        var form = ""
        if e.parts.isEmpty {
            switch e.type {
            case "B_SPLINE_CURVE_WITH_KNOTS": b = Array(e.args.dropFirst().prefix(5)); kn = Array(e.args.dropFirst(6))
            case "BEZIER_CURVE", "UNIFORM_CURVE", "QUASI_UNIFORM_CURVE", "B_SPLINE_CURVE":
                b = Array(e.args.dropFirst().prefix(5)); form = e.type.replacingOccurrences(of: "_CURVE", with: "")
            default: return nil
            }
        } else {
            if kn.isEmpty { form = e.parts["UNIFORM_CURVE"] != nil ? "UNIFORM" : (e.parts["QUASI_UNIFORM_CURVE"] != nil ? "QUASI_UNIFORM" : "BEZIER") }
        }
        guard b.count >= 2, let p = b[0].double.map({ Int($0) }) else { return nil }
        let cps = (b[1].list ?? []).compactMap { point($0.ref) }
        guard cps.count > p else { return nil }
        let U: [Double]
        if kn.count >= 2 {
            let m = (kn[0].list ?? []).compactMap { $0.double.map { Int($0) } }
            let ks = (kn[1].list ?? []).compactMap { $0.double }
            U = StepNURBS.expand(m, ks)
        } else { U = StepNURBS.implicitKnots(form, count: cps.count, degree: p) }
        var w: [Double]? = nil
        if let r = e.parts["RATIONAL_B_SPLINE_CURVE"], let l = r.first?.list?.compactMap({ $0.double }), l.count == cps.count { w = l }
        let c = StepBSplineCurve(degree: p, points: cps, weights: w, knots: U)
        return c.isValid ? c : nil
    }

    /// Dense polyline of a whole curve (nil for curves traced vertex to vertex: lines, conics).
    func densePolyline(_ e: StepEntity) -> (pts: [Vec3], closed: Bool)? {
        if let c = curveCache[e.id] { return (c, c.count > 2 && (c[0] - c[c.count - 1]).length < 1e-9 * max(1, k)) }
        var out: [Vec3]? = nil
        if let b = bsplineCurve(e) {
            out = StepBRepReader.adaptive(b)
        } else if e.type == "POLYLINE" {
            out = (e[1].list ?? []).compactMap { point($0.ref) }
        } else if e.type == "COMPOSITE_CURVE" {
            var pts: [Vec3] = []
            for sr in e[1].list ?? [] {
                guard let seg = f[sr.ref], let pc = f[seg[2].ref] else { continue }
                var sp: [Vec3] = densePolyline(pc)?.pts ?? []
                if sp.isEmpty, pc.type == "LINE" || pc.type == "TRIMMED_CURVE" { continue }
                if seg[1].enumValue == "F" { sp.reverse() }
                if let l = pts.last, let s0 = sp.first, (l - s0).length < 1e-9 * max(1, k) { sp.removeFirst() }
                pts += sp
            }
            out = pts
        }
        guard let o = out, o.count >= 2 else { return nil }
        curveCache[e.id] = o
        return (o, (o[0] - o[o.count - 1]).length < 1e-9 * max(1, k) * 10)
    }

    /// Adaptive sampling of a B-spline: knot spans split until the mid-point deviation is below 2.5 % of the chord
    /// (the same sagitta ratio as circles sampled every π/16).
    static func adaptive(_ b: StepBSplineCurve) -> [Vec3] {
        var ts: [Double] = []
        for t in b.knots[b.degree...b.points.count] where ts.last.map({ t > $0 + 1e-12 }) ?? true { ts.append(t) }
        guard ts.count >= 2 else { return [] }
        var diag = 0.0
        if let f = b.points.first { for p in b.points { diag = max(diag, (p - f).length) } }
        let absTol = max(diag * 1e-6, 1e-12)
        var out: [Vec3] = [b.eval(ts[0])]
        func sub(_ ta: Double, _ pa: Vec3, _ tb: Double, _ pb: Vec3, _ depth: Int) {
            let tm = (ta + tb) / 2, pm = b.eval(tm)
            let d = pb - pa, l2 = d.dot(d)
            let s = l2 > 1e-300 ? max(0, min(1, (pm - pa).dot(d) / l2)) : 0
            let dev = (pa + d * s - pm).length
            if depth < 12 && out.count < 2000 && (dev > max(0.025 * l2.squareRoot(), absTol) || (depth < 1 && b.degree > 1)) {
                sub(ta, pa, tm, pm, depth + 1); sub(tm, pm, tb, pb, depth + 1)
            } else { out.append(pb) }
        }
        for i in 0..<(ts.count - 1) {
            // Two sub-spans per knot span so an S-shaped span is not mistaken for a straight one.
            let tm = (ts[i] + ts[i + 1]) / 2
            let pa = out[out.count - 1], pm = b.eval(tm), pb = b.eval(ts[i + 1])
            sub(ts[i], pa, tm, pm, 0); sub(tm, pm, ts[i + 1], pb, 0)
        }
        return out
    }

    static func projectParam(_ P: [Vec3], _ q: Vec3) -> Double {
        var best = 0.0, bd = Double.infinity
        for i in 0..<(P.count - 1) {
            let a = P[i], d = P[i + 1] - a, l2 = d.dot(d)
            let t = l2 > 1e-300 ? max(0, min(1, (q - a).dot(d) / l2)) : 0
            let dist = (a + d * t - q).length
            if dist < bd { bd = dist; best = Double(i) + t }
        }
        return best
    }

    /// Points along an edge curve from `a` to `b` (b excluded).
    func edgePoints(_ curveID: Int?, _ a: Vec3, _ b: Vec3, sameSense: Bool) -> [Vec3] {
        guard let c = f[curveID] else { return [a] }
        switch c.type {
        case "LINE": return [a]
        case "SURFACE_CURVE", "SEAM_CURVE", "INTERSECTION_CURVE", "BOUNDED_SURFACE_CURVE": return edgePoints(c[1].ref, a, b, sameSense: sameSense)
        case "TRIMMED_CURVE": return edgePoints(c[1].ref, a, b, sameSense: sameSense)
        case "CIRCLE", "ELLIPSE":
            guard let fr = frame(c[1].ref), let r1 = c[2].double.map({ $0 * k }), r1 > 0 else { return [a] }
            let r2 = c.type == "ELLIPSE" ? (c[3].double.map { $0 * k } ?? r1) : r1
            func ang(_ p: Vec3) -> Double { let d = p - fr.o; return atan2(d.dot(fr.y) / r2, d.dot(fr.x) / r1) }
            var a0 = ang(a), a1 = ang(b)
            if sameSense { while a1 <= a0 + 1e-9 { a1 += 2 * .pi } } else { while a1 >= a0 - 1e-9 { a1 -= 2 * .pi } }
            let steps = min(512, max(2, Int((abs(a1 - a0) / angleStep).rounded(.up))))
            return (0..<steps).map { i in
                if i == 0 { return a }
                let t = a0 + (a1 - a0) * Double(i) / Double(steps)
                return fr.o + fr.x * (r1 * cos(t)) + fr.y * (r2 * sin(t))
            }
        default:
            guard let (P, closed) = densePolyline(c) else { return [a] }
            if c.type == "POLYLINE" && !closed {
                var pts = P
                if pts[0].distance(to: a) > pts[pts.count - 1].distance(to: a) { pts.reverse() }
                return [a] + Array(pts.dropFirst().dropLast())
            }
            let n = Double(P.count - 1)
            let ta = StepBRepReader.projectParam(P, a), tb = StepBRepReader.projectParam(P, b)
            var out: [Vec3] = [a]
            func at(_ t: Double) -> Vec3 {
                var t = t
                if closed { t = t.truncatingRemainder(dividingBy: n); if t < 0 { t += n } }
                let i = max(0, min(P.count - 2, Int(t.rounded(.down))))
                return P[i] + (P[i + 1] - P[i]) * (t - Double(i))
            }
            if sameSense {
                var end = tb
                if end <= ta + 1e-9 { if closed { end += n } else { return [a] + interior(P, from: tb, to: ta).reversed() } }
                var i = Double(Int(ta.rounded(.down)) + 1)
                while i < end - 1e-6 { out.append(at(i)); i += 1 }
            } else {
                var end = tb
                if end >= ta - 1e-9 { if closed { end -= n } else { return [a] + interior(P, from: ta, to: tb) } }
                var i = Double(Int(ta.rounded(.up)) - 1)
                while i > end + 1e-6 { out.append(at(i)); i -= 1 }
            }
            return out
        }
    }

    /// Polyline vertices strictly between parameters t0 < t1 (ascending).
    func interior(_ P: [Vec3], from t0: Double, to t1: Double) -> [Vec3] {
        var out: [Vec3] = []
        var i = Int(t0.rounded(.down)) + 1
        while Double(i) < t1 - 1e-6 && i < P.count { out.append(P[i]); i += 1 }
        return out
    }

    func loopPoints(_ loop: StepEntity) -> [Vec3] {
        switch loop.type {
        case "POLY_LOOP": return (loop[1].list ?? []).compactMap { point($0.ref) }
        case "VERTEX_LOOP": return point(loop[1].ref).map { [$0] } ?? []
        case "EDGE_LOOP":
            var pts: [Vec3] = []
            for oeRef in loop[1].list ?? [] {
                guard let oe = f[oeRef.ref], oe.type == "ORIENTED_EDGE", let ec = f[oe[3].ref] else { continue }
                let edge = ec.type == "ORIENTED_EDGE" ? f[ec[3].ref] : ec
                guard let ec2 = edge, let s0 = point(ec2[1].ref), let s1 = point(ec2[2].ref) else { continue }
                let forward = oe[4].enumValue != "F"
                let sense = ec2.type == "EDGE_CURVE" ? ec2[4].enumValue != "F" : true
                let (a, b) = forward ? (s0, s1) : (s1, s0)
                pts += edgePoints(ec2.type == "EDGE_CURVE" ? ec2[3].ref : nil, a, b, sameSense: forward == sense)
            }
            return pts
        default: return []
        }
    }

    // MARK: Surfaces

    func surface(_ id: Int?) -> StepSurface? {
        guard let id else { return nil }
        if let c = surfaceCache[id] { return c }
        let s = makeSurface(id)
        surfaceCache[id] = s
        return s
    }

    private func makeSurface(_ id: Int) -> StepSurface? {
        guard let e = f[id] else { return nil }
        switch e.type {
        case "PLANE": return frame(e[1].ref).map { .plane($0) }
        case "CYLINDRICAL_SURFACE":
            guard let fr = frame(e[1].ref), let r = e[2].double, r > 0 else { return nil }
            return .cylinder(fr, r * k)
        case "CONICAL_SURFACE":
            guard let fr = frame(e[1].ref), let r = e[2].double, let a = e[3].double else { return nil }
            return .cone(fr, r * k, tan(a * angleUnit))
        case "SPHERICAL_SURFACE":
            guard let fr = frame(e[1].ref), let r = e[2].double, r > 0 else { return nil }
            return .sphere(fr, r * k)
        case "TOROIDAL_SURFACE", "DEGENERATE_TOROIDAL_SURFACE":
            guard let fr = frame(e[1].ref), let R = e[2].double, let r = e[3].double, r > 0 else { return nil }
            return .torus(fr, R * k, r * k)
        case "RECTANGULAR_TRIMMED_SURFACE", "CURVE_BOUNDED_SURFACE": return surface(e[1].ref)
        case "SURFACE_OF_LINEAR_EXTRUSION":
            guard let c = f[e[1].ref], let d = direction(e[2].ref), let prof = profile(c) else { return nil }
            return .extrusion(StepArcPolyline(prof), d)
        case "SURFACE_OF_REVOLUTION":
            guard let c = f[e[1].ref], var ax = frame(e[2].ref), let prof = profile(c) else { return nil }
            // x axis of the frame towards the profile's first point off the axis.
            if let off = prof.first(where: { ($0 - ax.o - ax.z * ($0 - ax.o).dot(ax.z)).length > 1e-9 }) {
                var x = off - ax.o; x = x - ax.z * x.dot(ax.z); x = x * (1 / x.length)
                ax = StepXform(o: ax.o, x: x, y: ax.z.cross(x), z: ax.z)
            }
            return .revolution(StepArcPolyline(prof), ax)
        default:
            if let b = bsplineSurface(e) { return .bspline(b) }
            return nil
        }
    }

    /// Profile polyline of a swept surface's curve.
    func profile(_ c: StepEntity) -> [Vec3]? {
        switch c.type {
        case "LINE":
            guard let p = point(c[1].ref), let v = f[c[2].ref], let d = direction(v[1].ref) else { return nil }
            let m = (v[2].double ?? 1) * k
            let L = max(abs(m), 1) * 1000
            return [p - d * L, p + d * L]
        case "CIRCLE", "ELLIPSE":
            guard let fr = frame(c[1].ref), let r1 = c[2].double.map({ $0 * k }) else { return nil }
            let r2 = c.type == "ELLIPSE" ? (c[3].double.map { $0 * k } ?? r1) : r1
            return (0...64).map { i in let t = 2 * Double.pi * Double(i) / 64; return fr.o + fr.x * (r1 * cos(t)) + fr.y * (r2 * sin(t)) }
        case "TRIMMED_CURVE", "SURFACE_CURVE", "SEAM_CURVE": return f[c[1].ref].flatMap { profile($0) }
        default: return densePolyline(c)?.pts
        }
    }

    func bsplineSurface(_ e: StepEntity) -> StepBSplineSurface? {
        var b = args(e, "B_SPLINE_SURFACE")
        var kn = args(e, "B_SPLINE_SURFACE_WITH_KNOTS")
        if e.parts.isEmpty {
            switch e.type {
            case "B_SPLINE_SURFACE_WITH_KNOTS": b = Array(e.args.dropFirst().prefix(7)); kn = Array(e.args.dropFirst(8))
            case "BEZIER_SURFACE", "B_SPLINE_SURFACE", "UNIFORM_SURFACE", "QUASI_UNIFORM_SURFACE": b = Array(e.args.dropFirst().prefix(7))
            default: return nil
            }
        }
        guard b.count >= 3, let du = b[0].double.map({ Int($0) }), let dv = b[1].double.map({ Int($0) }) else { return nil }
        let cps = (b[2].list ?? []).map { ($0.list ?? []).compactMap { point($0.ref) } }
        guard let nv = cps.first?.count, nv > dv, cps.count > du, cps.allSatisfy({ $0.count == nv }) else { return nil }
        let ku: [Double], kv: [Double]
        if kn.count >= 4 {
            ku = StepNURBS.expand((kn[0].list ?? []).compactMap { $0.double.map { Int($0) } }, (kn[2].list ?? []).compactMap { $0.double })
            kv = StepNURBS.expand((kn[1].list ?? []).compactMap { $0.double.map { Int($0) } }, (kn[3].list ?? []).compactMap { $0.double })
        } else {
            let form = e.type.contains("QUASI") || e.parts["QUASI_UNIFORM_SURFACE"] != nil ? "QUASI_UNIFORM" : (e.type.contains("UNIFORM") || e.parts["UNIFORM_SURFACE"] != nil ? "UNIFORM" : "BEZIER")
            ku = StepNURBS.implicitKnots(form, count: cps.count, degree: du)
            kv = StepNURBS.implicitKnots(form, count: nv, degree: dv)
        }
        var w: [[Double]]? = nil
        if let r = e.parts["RATIONAL_B_SPLINE_SURFACE"], let rows = r.first?.list {
            let ww = rows.map { ($0.list ?? []).compactMap { $0.double } }
            if ww.count == cps.count && ww.allSatisfy({ $0.count == nv }) { w = ww }
        }
        var s = StepBSplineSurface(du: du, dv: dv, points: cps, weights: w, ku: ku, kv: kv)
        guard s.isValid else { return nil }
        var size = 0.0
        if let f0 = cps.first?.first { for row in cps { for p in row { size = max(size, (p - f0).length) } } }
        let tol = max(size * 1e-6, 1e-12)
        let (u0, u1) = s.uRange, (v0, v1) = s.vRange
        let samples = (0...6).map { Double($0) / 6 }
        if samples.allSatisfy({ (s.eval(u0, v0 + (v1 - v0) * $0) - s.eval(u1, v0 + (v1 - v0) * $0)).length < tol * 10 }) { s.periodU = u1 - u0 }
        if samples.allSatisfy({ (s.eval(u0 + (u1 - u0) * $0, v0) - s.eval(u0 + (u1 - u0) * $0, v1)).length < tol * 10 }) { s.periodV = v1 - v0 }
        s.poleV0 = samples.allSatisfy { (s.eval(u0 + (u1 - u0) * $0, v0) - s.eval(u0, v0)).length < tol * 10 }
        s.poleV1 = samples.allSatisfy { (s.eval(u0 + (u1 - u0) * $0, v1) - s.eval(u0, v1)).length < tol * 10 }
        return s
    }

    // MARK: Faces

    struct Loop { var pts: [Vec3]; var outer: Bool }

    func faceLoops(_ face: StepEntity) -> [Loop] {
        var loops: [Loop] = []
        for bRef in face[1].list ?? [] {
            guard let bound = f[bRef.ref], let loop = f[bound[1].ref] else { continue }
            var pts = loopPoints(loop)
            if bound[2].enumValue == "F" { pts.reverse() }
            var clean: [Vec3] = []
            let eps = 1e-9 * max(1, k)
            for p in pts where clean.last.map({ ($0 - p).length > eps }) ?? true { clean.append(p) }
            while clean.count > 2, (clean[0] - clean[clean.count - 1]).length < eps { clean.removeLast() }
            if clean.count >= 3 || (loop.type == "VERTEX_LOOP" && clean.count == 1) { loops.append(Loop(pts: clean, outer: bound.type == "FACE_OUTER_BOUND")) }
        }
        return loops
    }

    /// Triangles of one face (vertices in output units, counter-clockwise about the face normal).
    func tessellate(_ face: StepEntity) -> (verts: [Vec3], tris: [Int]) {
        let loops = faceLoops(face).filter { $0.pts.count >= 3 || $0.pts.count == 1 }
        guard loops.contains(where: { $0.pts.count >= 3 }) else { return ([], []) }
        if face.type != "FACE", let s = surface(face[2].ref), !s.isPlanar {
            let sense = face[3].enumValue != "F"
            let r = curved(loops, s, sense: sense, id: face[2].ref ?? 0)
            if !r.tris.isEmpty { return r }
        }
        return planar(loops.filter { $0.pts.count >= 3 })
    }

    func planar(_ loops: [Loop]) -> (verts: [Vec3], tris: [Int]) {
        guard !loops.isEmpty else { return ([], []) }
        let oi = loops.firstIndex { $0.outer } ?? loops.indices.max { area3(loops[$0].pts) < area3(loops[$1].pts) }!
        let outer = loops[oi].pts
        var n = newell(outer)
        guard n.length > 1e-12 else { return ([], []) }
        n = n * (1 / n.length)
        let u = (abs(n.z) < 0.9 ? Vec3(0, 0, 1) : Vec3(1, 0, 0)).cross(n)
        let uu = u * (1 / u.length), vv = n.cross(uu)
        let origin = outer[0]
        func proj(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(uu), d.dot(vv)) }
        var lookup: [Vec2: Vec3] = [:]
        let o2 = outer.map { p -> Vec2 in let q = proj(p); lookup[q] = p; return q }
        var holes: [[Vec2]] = []
        for (i, l) in loops.enumerated() where i != oi { holes.append(l.pts.map { p in let q = proj(p); lookup[q] = p; return q }) }
        let tr = StepCDT.triangulate(loops: [o2] + holes, steiner: [])
        let verts = tr.points.map { lookup[$0] ?? origin + uu * $0.x + vv * $0.y }
        var tris: [Int] = []
        for t in tr.triangles {
            let a = verts[t.0], b = verts[t.1], c = verts[t.2]
            if (b - a).cross(c - a).dot(n) >= 0 { tris += [t.0, t.1, t.2] } else { tris += [t.0, t.2, t.1] }
        }
        return StepBRepReader.compact(verts, tris)
    }

    /// Drops vertices no triangle uses (the triangulation's helper points).
    static func compact(_ verts: [Vec3], _ tris: [Int]) -> (verts: [Vec3], tris: [Int]) {
        var map = [Int](repeating: -1, count: verts.count)
        var out: [Vec3] = []
        let t = tris.map { i -> Int in
            if map[i] < 0 { map[i] = out.count; out.append(verts[i]) }
            return map[i]
        }
        return (out, t)
    }

    func newell(_ pts: [Vec3]) -> Vec3 {
        var n = Vec3.zero
        for i in 0..<pts.count { let a = pts[i], b = pts[(i + 1) % pts.count]; n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
        return n
    }
    func area3(_ pts: [Vec3]) -> Double { newell(pts).length }

    struct PLoop { var uv: [Vec2]; var p: [Vec3]; var drift: Vec2 }

    /// Tessellation of a face on a curved surface through its parameter plane.
    func curved(_ loops: [Loop], _ s: StepSurface, sense: Bool, id: Int = 0) -> (verts: [Vec3], tris: [Int]) {
        // Parameter grid for B-spline inversion.
        var grid: [(Vec2, Vec3)] = gridCache[id] ?? []
        if grid.isEmpty, case .bspline(let b) = s {
            let (u0, u1) = b.uRange, (v0, v1) = b.vRange
            let nu = min(40, max(8, b.points.count * 2)), nv = min(40, max(8, b.points[0].count * 2))
            for i in 0...nu { for j in 0...nv {
                let u = u0 + (u1 - u0) * Double(i) / Double(nu), v = v0 + (v1 - v0) * Double(j) / Double(nv)
                grid.append((Vec2(u, v), b.eval(u, v)))
            } }
            gridCache[id] = grid
        }
        let PU = s.periodU, PV = s.periodV
        func unwrap(_ x: Double, near: Double, period: Double?) -> Double {
            guard let P = period, x.isFinite, near.isFinite else { return x }
            return x - P * ((x - near) / P).rounded()
        }
        // 1. Loops into the parameter plane.
        var ploops: [PLoop] = []
        var poleV: [Double] = []
        /// Replaces pole points (NaN u) by the u values of their neighbours (a pole is an edge of the parameter polygon).
        func fillPoles(_ uv: [Vec2], _ pts: [Vec3]) -> ([Vec2], [Vec3]) {
            guard uv.contains(where: { !$0.x.isFinite }), uv.contains(where: { $0.x.isFinite }) else { return (uv, pts) }
            var nuv: [Vec2] = [], np: [Vec3] = []
            let n = uv.count
            for i in 0..<n {
                if uv[i].x.isFinite { nuv.append(uv[i]); np.append(pts[i]); continue }
                var a = (i + n - 1) % n; while !uv[a].x.isFinite { a = (a + n - 1) % n }
                var b = (i + 1) % n; while !uv[b].x.isFinite { b = (b + 1) % n }
                nuv.append(Vec2(uv[a].x, uv[i].y)); np.append(pts[i])
                if abs(uv[b].x - uv[a].x) > 1e-9 { nuv.append(Vec2(uv[b].x, uv[i].y)); np.append(pts[i]) }
            }
            return (nuv, np)
        }
        let orient: Double = sense ? 1 : -1
        for l in loops {
            if l.pts.count == 1 {   // vertex loop (apex)
                poleV.append(s.param(l.pts[0], hint: nil, grid: grid).y)
                continue
            }
            var uv: [Vec2] = []
            var hint: Vec2? = nil
            for p in l.pts {
                var q = s.param(p, hint: hint, grid: grid)
                if let h = hint {
                    q = Vec2(q.x.isFinite ? unwrap(q.x, near: h.x, period: PU) : q.x, unwrap(q.y, near: h.y, period: PV))
                }
                if q.x.isFinite { hint = q } else { hint = hint.map { Vec2($0.x, q.y) }; poleV.append(q.y) }
                uv.append(q)
            }
            // A seam traversed up and back between two poles (a whole sphere), or meridians bounding a lune that the
            // raw angles put on the wrong side of the seam: the way back lies one period over.
            let poles = uv.indices.filter { !uv[$0].x.isFinite }
            if poles.count >= 2, let P = PU {
                let (f0, _) = fillPoles(uv, l.pts)
                let a0 = GeometryOps.signedArea(f0) * orient
                if abs(a0) < 1e-9 * P * P || (a0 < 0 && (l.outer || loops.count == 1)) {
                    var best: [Vec2]? = nil, bestA = 0.0
                    for sgn in [1.0, -1.0] {
                        var t = uv
                        for j in (poles[0] + 1)..<poles[1] where t[j].x.isFinite { t[j].x += sgn * P }
                        let ar = GeometryOps.signedArea(fillPoles(t, l.pts).0) * orient
                        if ar > bestA { bestA = ar; best = t }
                    }
                    if let b = best { uv = b }
                }
            }
            let (fu, fp) = fillPoles(uv, l.pts)
            guard fu.allSatisfy({ $0.x.isFinite }) else { continue }
            ploops.append(PLoop(uv: fu, p: fp, drift: .zero))
        }
        guard !ploops.isEmpty else { return ([], []) }
        // Loop orientation: counter-clockwise about the surface normal after this.
        if !sense { ploops = ploops.map { PLoop(uv: $0.uv.reversed(), p: $0.p.reversed(), drift: .zero) } }
        for i in ploops.indices {
            let l = ploops[i]
            let last = l.uv[l.uv.count - 1], first = l.uv[0]
            let closeU = unwrap(first.x, near: last.x, period: PU), closeV = unwrap(first.y, near: last.y, period: PV)
            ploops[i].drift = Vec2(closeU - first.x, closeV - first.y)
        }
        // Seam-less periodic loops (a band around a cylinder / cone / torus / sphere).
        func isSeamless(_ l: PLoop) -> Bool { abs(l.drift.x) > 1e-6 || abs(l.drift.y) > 1e-6 }
        var seamless = ploops.filter(isSeamless)
        var closed = ploops.filter { !isSeamless($0) }
        var outerPoly: [Vec2]? = nil, outerP: [Vec3] = []
        func rotate(_ l: PLoop, _ r: Int) -> PLoop {
            guard r > 0 else { return l }
            let uv = Array(l.uv[r...]) + l.uv[..<r].map { $0 + l.drift }
            return PLoop(uv: uv, p: Array(l.p[r...]) + Array(l.p[..<r]), drift: l.drift)
        }
        func reversed(_ l: PLoop) -> PLoop {
            PLoop(uv: Array(l.uv.reversed()), p: Array(l.p.reversed()), drift: Vec2(-l.drift.x, -l.drift.y))
        }
        if seamless.count == 2 {
            let a = seamless[0]
            var b = seamless[1]
            let alongU = abs(a.drift.x) > 1e-6
            let da = alongU ? a.drift.x : a.drift.y, db0 = alongU ? b.drift.x : b.drift.y
            if (da > 0) == (db0 > 0) { b = reversed(b) }
            // Start b where a ends (same coordinate along the band, modulo the period).
            let endA = a.uv[0] + a.drift
            let P = alongU ? (PU ?? 2 * .pi) : (PV ?? 2 * .pi)
            var bestI = 0, bestD = Double.infinity
            for (i, q) in b.uv.enumerated() {
                let d = alongU ? abs(unwrap(q.x, near: endA.x, period: P) - endA.x) : abs(unwrap(q.y, near: endA.y, period: P) - endA.y)
                if d < bestD { bestD = d; bestI = i }
            }
            b = rotate(b, bestI)
            let shift = alongU ? unwrap(b.uv[0].x, near: endA.x, period: P) - b.uv[0].x : unwrap(b.uv[0].y, near: endA.y, period: P) - b.uv[0].y
            let bShift = alongU ? Vec2(shift, 0) : Vec2(0, shift)
            outerPoly = a.uv + [a.uv[0] + a.drift] + b.uv.map { $0 + bShift } + [b.uv[0] + bShift + b.drift]
            outerP = a.p + [a.p[0]] + b.p + [b.p[0]]
            seamless = []
        } else if seamless.count == 1, abs(seamless[0].drift.x) > 1e-6, PV == nil {
            // One band loop: the face covers a pole (sphere cap, cone up to its apex, closed B-spline end).
            let a = seamless[0]
            let up = a.drift.x > 0
            var vp: Double
            switch s {
            case .sphere: vp = up ? .pi / 2 : -.pi / 2
            case .cone(_, let r, let t): vp = abs(t) > 1e-12 ? -r / t : (up ? 1 : -1) * 1e9
            case .bspline(let b): vp = up ? b.vRange.1 : b.vRange.0
            default:
                vp = poleV.first ?? (up ? (a.uv.map(\.y).max() ?? 0) : (a.uv.map(\.y).min() ?? 0))
            }
            if let pv = poleV.first { vp = pv }
            let u0 = a.uv[0].x, u1 = u0 + a.drift.x
            outerPoly = a.uv + [Vec2(u1, a.uv[0].y), Vec2(u1, vp), Vec2(u0, vp)]
            outerP = a.p + [a.p[0], s.eval(u1, vp), s.eval(u0, vp)]
            seamless = []
        }
        closed += seamless    // anything left over is used as a plain loop
        // Outer loop and holes.
        var holesUV: [[Vec2]] = [], holesP: [[Vec3]] = []
        if outerPoly == nil {
            guard let oi = closed.indices.max(by: { abs(GeometryOps.signedArea(closed[$0].uv)) < abs(GeometryOps.signedArea(closed[$1].uv)) }) else { return ([], []) }
            outerPoly = closed[oi].uv; outerP = closed[oi].p
            closed.remove(at: oi)
        }
        guard var outer = outerPoly, outer.count >= 3 else { return ([], []) }
        let ob = bbox(outer)
        for var h in closed where h.uv.count >= 3 {
            // Move the hole into the outer loop's period.
            let c = bbox(h.uv)
            let cu = (c.0.x + c.1.x) / 2, cv = (c.0.y + c.1.y) / 2
            let ocu = (ob.0.x + ob.1.x) / 2, ocv = (ob.0.y + ob.1.y) / 2
            let du = PU.map { $0 * ((ocu - cu) / $0).rounded() } ?? 0
            let dv = PV.map { $0 * ((ocv - cv) / $0).rounded() } ?? 0
            h.uv = h.uv.map { $0 + Vec2(du, dv) }
            holesUV.append(h.uv); holesP.append(h.p)
        }
        // 2. Metric scaling of the parameter plane (lengths along u and v at the centre).
        let ext = Vec2(max(ob.1.x - ob.0.x, 1e-9), max(ob.1.y - ob.0.y, 1e-9))
        func speed(_ axis: Int) -> Double {
            var best = 0.0
            for fu in [0.25, 0.5, 0.75] { for fv in [0.25, 0.5, 0.75] {
                let u = ob.0.x + ext.x * fu, v = ob.0.y + ext.y * fv
                let h = (axis == 0 ? ext.x : ext.y) * 1e-3
                let d = axis == 0 ? (s.eval(u + h, v) - s.eval(u - h, v)).length : (s.eval(u, v + h) - s.eval(u, v - h)).length
                best = max(best, d / (2 * h))
            } }
            return best
        }
        let su = max(speed(0), 1e-9), sv = max(speed(1), 1e-9)
        func toXY(_ q: Vec2) -> Vec2 { Vec2(q.x * su, q.y * sv) }
        var lookup: [Vec2: Vec3] = [:]
        outer = outer.map(toXY)
        for (q, p) in zip(outer, outerP) { lookup[q] = p }
        let holesXY = holesUV.map { $0.map(toXY) }
        for (h, hp) in zip(holesXY, holesP) { for (q, p) in zip(h, hp) { lookup[q] = p } }
        // 3. Steiner points on doubly curved surfaces.
        var step: (Double?, Double?) = (nil, nil)
        switch s {
        case .sphere(_, let r): step = (r * angleStep, r * angleStep)
        case .torus(_, let R, let r): step = ((R + r) * angleStep, r * angleStep)
        case .revolution(let c, _): step = (su * angleStep, max(c.length / 24, 1e-9))
        case .bspline:
            // Spacing from the smallest radius of curvature met along parameter lines inside the face (sagitta
            // 2.5 % of the chord ⇒ chord ≤ 0.2 R); a direction without curvature needs no interior points.
            func radius(_ alongU: Bool) -> Double {
                var r = Double.infinity
                let n = 8
                for i in 0...n {
                    for j in 0..<n {
                        let a = Double(j) / Double(n), b2 = Double(j + 1) / Double(n), c = Double(i) / Double(n)
                        let (ua, va, ub, vb) = alongU ? (ob.0.x + ext.x * a, ob.0.y + ext.y * c, ob.0.x + ext.x * b2, ob.0.y + ext.y * c)
                                                      : (ob.0.x + ext.x * c, ob.0.y + ext.y * a, ob.0.x + ext.x * c, ob.0.y + ext.y * b2)
                        let pa = s.eval(ua, va), pb = s.eval(ub, vb), pm = s.eval((ua + ub) / 2, (va + vb) / 2)
                        let d = pb - pa, l2 = d.dot(d)
                        guard l2 > 1e-300 else { continue }
                        let t = max(0, min(1, (pm - pa).dot(d) / l2))
                        let dev = (pa + d * t - pm).length
                        if dev > 1e-9 * l2.squareRoot() { r = min(r, l2 / (8 * dev)) }
                    }
                }
                return r
            }
            let ru = radius(true), rv = radius(false)
            if ru.isFinite && rv.isFinite { step = (max(0.2 * ru, 1e-9), max(0.2 * rv, 1e-9)) }
        default: break
        }
        var steiner: [Vec2] = []
        if let hu = step.0, let hv = step.1, hu > 0, hv > 0 {
            let xb = bbox(outer)
            var hU = hu, hV = hv
            while ((xb.1.x - xb.0.x) / hU) * ((xb.1.y - xb.0.y) / hV) > 4000 { hU *= 1.5; hV *= 1.5 }
            let segs: [(Vec2, Vec2)] = ([outer] + holesXY).flatMap { l in (0..<l.count).map { (l[$0], l[($0 + 1) % l.count]) } }
            let minD = 0.45 * min(hU, hV)
            var y = xb.0.y + hV / 2
            while y < xb.1.y {
                var x = xb.0.x + hU / 2
                while x < xb.1.x {
                    let p = Vec2(x, y)
                    if GeometryOps.pointInPolygon(p, outer), !holesXY.contains(where: { GeometryOps.pointInPolygon(p, $0) }),
                       !segs.contains(where: { distToSeg(p, $0.0, $0.1) < minD }) { steiner.append(p) }
                    x += hU
                }
                y += hV
            }
        }
        let tr = StepCDT.triangulate(loops: [outer] + holesXY, steiner: steiner)
        guard !tr.triangles.isEmpty else { return ([], []) }
        let verts = tr.points.map { q in lookup[q] ?? s.eval(q.x / su, q.y / sv) }
        // The triangulation is counter-clockwise in the parameter plane, so it follows the surface orientation
        // (∂u × ∂v) everywhere the mapping is regular: one decision (a vote weighted by area) orients the whole face.
        let sgn: Double = sense ? 1 : -1
        var vote = 0.0
        for t in tr.triangles {
            let a = verts[t.0], b = verts[t.1], c = verts[t.2]
            let cq = (tr.points[t.0] + tr.points[t.1] + tr.points[t.2]) * (1.0 / 3)
            let n = s.normal(cq.x / su, cq.y / sv, scale: ext)
            let tn = (b - a).cross(c - a)
            let d = tn.dot(n), l = tn.length * n.length
            if l > 1e-300 { vote += d / l * tn.length }
        }
        let keep = (vote >= 0) == (sgn > 0)
        var tris: [Int] = []
        for t in tr.triangles { tris += keep ? [t.0, t.1, t.2] : [t.0, t.2, t.1] }
        return StepBRepReader.compact(verts, tris)
    }

    func bbox(_ p: [Vec2]) -> (Vec2, Vec2) {
        var lo = Vec2(Double.infinity, Double.infinity), hi = Vec2(-Double.infinity, -Double.infinity)
        for q in p { lo = Vec2(min(lo.x, q.x), min(lo.y, q.y)); hi = Vec2(max(hi.x, q.x), max(hi.y, q.y)) }
        return (lo, hi)
    }
    func distToSeg(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let d = b - a, l2 = d.x * d.x + d.y * d.y
        let t = l2 > 1e-300 ? max(0, min(1, ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / l2)) : 0
        return (a + d * t - p).length
    }

    // MARK: Tessellated (AP242)

    /// Triangles of TRIANGULATED_FACE / COMPLEX_TRIANGULATED_FACE / *_SURFACE_SET items.
    func tessellatedItem(_ e: StepEntity) -> (verts: [Vec3], tris: [Int])? {
        guard let cl = f[e[1].ref], cl.type == "COORDINATES_LIST" else { return nil }
        let coords = (cl[2].list ?? []).compactMap { v -> Vec3? in
            guard let c = v.list?.compactMap({ $0.double }), c.count >= 3 else { return nil }
            return Vec3(c[0], c[1], c[2]) * k
        }
        let isFace = e.type.hasSuffix("_FACE")
        let pnIdx = (e[isFace ? 5 : 4].list ?? []).compactMap { $0.double.map { Int($0) } }
        func vi(_ i: Int) -> Int? {
            let j = pnIdx.isEmpty ? i : (i >= 1 && i <= pnIdx.count ? pnIdx[i - 1] : 0)
            return j >= 1 && j <= coords.count ? j - 1 : nil
        }
        var tris: [Int] = []
        func add(_ a: Int, _ b: Int, _ c: Int) {
            guard let x = vi(a), let y = vi(b), let z = vi(c), x != y, y != z, x != z else { return }
            tris += [x, y, z]
        }
        if e.type == "TRIANGULATED_FACE" || e.type == "TRIANGULATED_SURFACE_SET" {
            for t in e[isFace ? 6 : 5].list ?? [] {
                let v = (t.list ?? []).compactMap { $0.double.map { Int($0) } }
                if v.count >= 3 { add(v[0], v[1], v[2]) }
            }
        } else if e.type == "COMPLEX_TRIANGULATED_FACE" || e.type == "COMPLEX_TRIANGULATED_SURFACE_SET" {
            let strips = e[isFace ? 6 : 5].list ?? [], fans = e[isFace ? 7 : 6].list ?? []
            for s in strips {
                let v = (s.list ?? []).compactMap { $0.double.map { Int($0) } }
                if v.count >= 3 { for i in 0..<(v.count - 2) { if i % 2 == 0 { add(v[i], v[i + 1], v[i + 2]) } else { add(v[i + 1], v[i], v[i + 2]) } } }
            }
            for fn in fans {
                let v = (fn.list ?? []).compactMap { $0.double.map { Int($0) } }
                if v.count >= 3 { for i in 1..<(v.count - 1) { add(v[0], v[i], v[i + 1]) } }
            }
        } else { return nil }
        return (coords, tris)
    }
}

extension Array {
    subscript(stepSafe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

