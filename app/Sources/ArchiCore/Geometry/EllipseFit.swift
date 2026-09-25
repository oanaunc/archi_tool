// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Ellipses tangent to four lines (DRW-048).
///
/// The ellipses tangent to four lines form a one-parameter family (a pencil of dual conics). With the dual conic
/// S = [[c cᵀ − Q, c], [cᵀ, 1]] (centre c, shape Q: the ellipse is {x : (x−c)ᵀ Q⁻¹ (x−c) = 1}) a line (n, d) is tangent
/// iff (n, d) S (n, d)ᵀ = 0 — linear in the six entries of S. The four tangency conditions leave a 2-D null space
/// S(θ) = cos θ A + sin θ B; the centre of every member lies on the Newton line of the quadrilateral. The canonical choice
/// is the member of largest area (unique, equal to the midpoint-tangent ellipse for a parallelogram).
extension InscribedEllipse {
    /// Line a x + b y + c = 0 through two points (normalised so a² + b² = 1).
    static func line(_ p: Vec2, _ q: Vec2) -> (Double, Double, Double)? {
        let d = q - p
        let l = d.length
        guard l > 1e-12 else { return nil }
        let a = -d.y / l, b = d.x / l
        return (a, b, -(a * p.x + b * p.y))
    }

    /// Null space of a 4×6 matrix by Gaussian elimination with full pivoting (two vectors when the rows are independent).
    static func nullSpace(_ m0: [[Double]]) -> [[Double]] {
        var m = m0
        let rows = m.count, cols = m[0].count
        var pivCols: [Int] = []
        var r = 0
        var used = Set<Int>()
        let scale = m.flatMap { $0 }.map(abs).max() ?? 1
        while r < rows {
            // Pick the largest remaining entry.
            var best = 0.0, bi = -1, bj = -1
            for i in r..<rows { for j in 0..<cols where !used.contains(j) { if abs(m[i][j]) > best { best = abs(m[i][j]); bi = i; bj = j } } }
            guard bi >= 0, best > 1e-13 * max(scale, 1e-300) else { break }
            m.swapAt(r, bi)
            let pv = m[r][bj]
            for j in 0..<cols { m[r][j] /= pv }
            for i in 0..<rows where i != r {
                let f = m[i][bj]
                if f != 0 { for j in 0..<cols { m[i][j] -= f * m[r][j] } }
            }
            pivCols.append(bj); used.insert(bj); r += 1
        }
        let free = (0..<cols).filter { !used.contains($0) }
        return free.map { fcol in
            var v = [Double](repeating: 0, count: cols)
            v[fcol] = 1
            for (ri, pc) in pivCols.enumerated() { v[pc] = -m[ri][fcol] }
            return v
        }
    }

    /// Centre and shape of the dual conic s = (s11, s12, s22, s13, s23, s33); nil unless it is a real ellipse.
    static func ellipseParts(_ s: [Double]) -> (c: Vec2, q: (Double, Double, Double))? {
        guard abs(s[5]) > 1e-300 else { return nil }
        let n = s.map { $0 / s[5] }
        let c = Vec2(n[3], n[4])
        let q11 = c.x * c.x - n[0], q12 = c.x * c.y - n[1], q22 = c.y * c.y - n[2]
        let det = q11 * q22 - q12 * q12
        guard q11 > 0, q22 > 0, det > 0, det.isFinite else { return nil }
        return (c, (q11, q12, q22))
    }

    static func ellipse(center c: Vec2, q: (Double, Double, Double)) -> EllipseGeom {
        let (a, b, d) = q
        let tr = a + d, disc = sqrt(max(0, (a - d) * (a - d) / 4 + b * b))
        let l1 = tr / 2 + disc, l2 = max(0, tr / 2 - disc)
        var e1: Vec2
        if abs(b) > 1e-300 { e1 = Vec2(l1 - d, b) } else { e1 = a >= d ? Vec2(1, 0) : Vec2(0, 1) }
        if e1.lengthSquared < 1e-300 { e1 = Vec2(1, 0) }
        e1 = e1.normalized
        let major = sqrt(l1)
        return EllipseGeom(center: c, majorAxis: e1 * major, ratio: major > 0 ? sqrt(l2) / major : 1)
    }

    static func pointInConvex(_ p: Vec2, _ q: [Vec2]) -> Bool {
        var sign = 0.0
        for i in 0..<q.count {
            let a = q[i], b = q[(i + 1) % q.count]
            let cr = (b - a).cross(p - a)
            if abs(cr) < 1e-12 { continue }
            if sign == 0 { sign = cr } else if (sign > 0) != (cr > 0) { return false }
        }
        return true
    }

    /// Largest ellipse inscribed in the convex quadrilateral p0 p1 p2 p3 (tangent to all four sides). nil when the
    /// quadrilateral is degenerate or not convex.
    public static func inQuadrilateral(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2) -> EllipseGeom? {
        let q = [p0, p1, p2, p3]
        // Convexity (all turns the same way, non-zero area).
        var turn = 0.0
        for i in 0..<4 {
            let cr = (q[(i + 1) % 4] - q[i]).cross(q[(i + 2) % 4] - q[(i + 1) % 4])
            if abs(cr) < 1e-12 * max(1, (q[(i + 1) % 4] - q[i]).lengthSquared) { return nil }
            if turn == 0 { turn = cr } else if (turn > 0) != (cr > 0) { return nil }
        }
        // Work in coordinates centred and scaled to the quadrilateral for conditioning.
        let ctr = (p0 + p1 + p2 + p3) / 4
        let sc = q.map { ($0 - ctr).length }.max() ?? 1
        let u = q.map { ($0 - ctr) / sc }
        var lines: [(Double, Double, Double)] = []
        for i in 0..<4 { guard let l = line(u[i], u[(i + 1) % 4]) else { return nil }; lines.append(l) }
        return tangentToLines(lines, inside: u).map { e in
            EllipseGeom(center: ctr + e.center * sc, majorAxis: e.majorAxis * sc, ratio: e.ratio)
        }
    }

    /// Largest ellipse tangent to four lines (a, b, c: a x + b y + c = 0) whose centre lies inside the convex polygon `inside`.
    static func tangentToLines(_ lines: [(Double, Double, Double)], inside poly: [Vec2]) -> EllipseGeom? {
        let m = lines.map { l -> [Double] in
            let (a, b, c) = l
            return [a * a, 2 * a * b, b * b, 2 * a * c, 2 * b * c, c * c]
        }
        let ns = nullSpace(m)
        guard ns.count >= 2 else { return nil }
        let A = ns[0], B = ns[1]
        func member(_ t: Double) -> [Double] { (0..<6).map { cos(t) * A[$0] + sin(t) * B[$0] } }
        func area(_ t: Double) -> Double {
            guard let e = ellipseParts(member(t)), pointInConvex(e.c, poly) else { return -1 }
            return e.q.0 * e.q.2 - e.q.1 * e.q.1
        }
        // Coarse scan, then golden-section refinement around the best sample.
        let n = 3600
        var bestT = 0.0, best = -1.0
        for k in 0..<n { let t = Double.pi * Double(k) / Double(n); let a = area(t); if a > best { best = a; bestT = t } }
        guard best > 0 else { return nil }
        var lo = bestT - .pi / Double(n), hi = bestT + .pi / Double(n)
        let g = (sqrt(5.0) - 1) / 2
        var x1 = hi - g * (hi - lo), x2 = lo + g * (hi - lo)
        var f1 = area(x1), f2 = area(x2)
        for _ in 0..<200 {
            if f1 < f2 { lo = x1; x1 = x2; f1 = f2; x2 = lo + g * (hi - lo); f2 = area(x2) }
            else { hi = x2; x2 = x1; f2 = f1; x1 = hi - g * (hi - lo); f1 = area(x1) }
            if hi - lo < 1e-15 { break }
        }
        let t = f1 > best || f2 > best ? (f1 > f2 ? x1 : x2) : bestT
        guard let e = ellipseParts(member(t)) else { return nil }
        return ellipse(center: e.c, q: e.q)
    }

    /// Largest ellipse tangent to four lines given by point pairs, taken in order around the quadrilateral they bound.
    public static func tangentToFourLines(_ ls: [(Vec2, Vec2)]) -> EllipseGeom? {
        guard ls.count == 4 else { return nil }
        var corners: [Vec2] = []
        for i in 0..<4 {
            let (a, b) = ls[i], (c, d) = ls[(i + 1) % 4]
            let r = b - a, s = d - c
            let den = r.cross(s)
            guard abs(den) > 1e-12 * r.length * s.length else { return nil }
            corners.append(a + r * ((c - a).cross(s) / den))
        }
        // Corner i is side i ∩ side i+1: rotate so each side runs between consecutive corners.
        return inQuadrilateral(corners[3], corners[0], corners[1], corners[2])
    }

    /// Tangency error of an ellipse against the line through a and b: |distance from the centre| − support width (0 when tangent).
    public static func tangencyResidual(_ e: EllipseGeom, _ a: Vec2, _ b: Vec2) -> Double {
        // Distance from the line to the ellipse's supporting point: |n·c + d| − sqrt(nᵀ Q n) (0 when tangent).
        guard let (na, nb, nc) = line(a, b) else { return .infinity }
        let n = Vec2(na, nb)
        let u = e.majorAxis, v = Vec2(-e.majorAxis.y, e.majorAxis.x) * e.ratio
        let support = sqrt(pow(n.dot(u), 2) + pow(n.dot(v), 2))
        return abs(abs(n.dot(e.center) + nc) - support)
    }
}
