// Oanarina Archi Tool — GPL-3.0-or-later
// Global curve interpolation with end derivatives after Piegl & Tiller, "The NURBS Book", §9.2.2 (algorithm only).
import Foundation

/// Fit-point splines with tangency control (DRW-051): a clamped cubic B-spline through every fit point (chord-length
/// parameters) whose end tangents are given (or estimated from the first/last three points).
public enum SplineFit {
    /// B-spline basis functions N_{i,p}(u) for i = span-p…span.
    static func basis(_ span: Int, _ u: Double, _ p: Int, _ U: [Double]) -> [Double] {
        var N = [Double](repeating: 0, count: p + 1), left = N, right = N
        N[0] = 1
        for j in 1...p {
            left[j] = u - U[span + 1 - j]; right[j] = U[span + j] - u
            var saved = 0.0
            for r in 0..<j {
                let den = right[r + 1] + left[j - r]
                let t = den == 0 ? 0 : N[r] / den
                N[r] = saved + right[r + 1] * t
                saved = left[j - r] * t
            }
            N[j] = saved
        }
        return N
    }
    static func span(_ u: Double, _ n: Int, _ p: Int, _ U: [Double]) -> Int {
        if u >= U[n + 1] { return n }
        var lo = p, hi = n + 1, mid = (lo + hi) / 2
        while u < U[mid] || u >= U[mid + 1] { if u < U[mid] { hi = mid } else { lo = mid }; mid = (lo + hi) / 2 }
        return mid
    }

    /// Chord-length parameters of the points in [0, 1].
    public static func parameters(_ q: [Vec2]) -> [Double] {
        var d = [0.0]
        for i in 1..<q.count { d.append(d[i - 1] + q[i].distance(to: q[i - 1])) }
        let total = d.last ?? 0
        guard total > 0 else { return q.indices.map { Double($0) / Double(max(1, q.count - 1)) } }
        return d.map { $0 / total }
    }

    /// Clamped cubic spline through `points` with end derivatives. Tangent vectors give directions; their length is
    /// scaled to the total chord length (as AutoCAD does). Returns control points and knots, or nil for fewer than two
    /// distinct points.
    public static func interpolate(_ points: [Vec2], startTangent: Vec2? = nil, endTangent: Vec2? = nil) -> SplineGeom? {
        var q: [Vec2] = []
        for p in points where q.last.map({ !$0.isClose(p, tol: 1e-12) }) ?? true { q.append(p) }
        guard q.count >= 2 else { return nil }
        let n = q.count - 1, p = 3
        let u = parameters(q)
        var chord = 0.0
        for i in 1...n { chord += q[i].distance(to: q[i - 1]) }
        // Estimated end tangents: derivative of the parabola through the first / last three points (Bessel).
        func estimate(atStart: Bool) -> Vec2 {
            if n == 1 { return (q[1] - q[0]) / (u[1] - u[0]) }
            if atStart {
                let d1 = (q[1] - q[0]) / (u[1] - u[0]), d2 = (q[2] - q[1]) / (u[2] - u[1])
                let a = (u[1] - u[0]) / (u[2] - u[0])
                return d1 * (1 + a) - d2 * a
            }
            let d1 = (q[n] - q[n - 1]) / (u[n] - u[n - 1]), d0 = (q[n - 1] - q[n - 2]) / (u[n - 1] - u[n - 2])
            let a = (u[n] - u[n - 1]) / (u[n] - u[n - 2])
            return d1 * (1 + a) - d0 * a
        }
        let d0 = startTangent.map { $0.normalized * chord } ?? estimate(atStart: true)
        let dn = endTangent.map { $0.normalized * chord } ?? estimate(atStart: false)
        // Knots: 0,0,0,0, u1…u(n-1), 1,1,1,1 → n + 3 control points P0…P(n+2).
        let U = [0, 0, 0, 0] + (n > 1 ? Array(u[1..<n]) : []) + [1, 1, 1, 1]
        let m = n + 2
        var P = [Vec2](repeating: .zero, count: m + 1)
        P[0] = q[0]; P[m] = q[n]
        P[1] = q[0] + d0 * (U[p + 1] / Double(p))
        P[m - 1] = q[n] - dn * ((1 - U[m]) / Double(p))
        if n >= 2 {
            // Unknowns P2…P(n): C(u_k) = Q_k for k = 1…n-1 (dense solve; fit point counts are small).
            let k = n - 1
            var A = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
            var bx = [Double](repeating: 0, count: k), by = bx
            for r in 0..<k {
                let uk = u[r + 1]
                let s = span(uk, m, p, U)
                let N = basis(s, uk, p, U)
                var rhs = q[r + 1]
                for j in 0...p {
                    let i = s - p + j
                    if i >= 2 && i <= n { A[r][i - 2] += N[j] } else { rhs = rhs - P[i] * N[j] }
                }
                bx[r] = rhs.x; by[r] = rhs.y
            }
            guard let x = solve(A, bx), let y = solve(A, by) else { return nil }
            for i in 0..<k { P[i + 2] = Vec2(x[i], y[i]) }
        }
        return SplineGeom(degree: p, controlPoints: P, knots: U, fitPoints: q)
    }

    /// Gaussian elimination with partial pivoting.
    static func solve(_ a0: [[Double]], _ b0: [Double]) -> [Double]? {
        var a = a0, b = b0
        let n = b.count
        for c in 0..<n {
            guard let piv = (c..<n).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[piv][c]) > 1e-14 else { return nil }
            a.swapAt(c, piv); b.swapAt(c, piv)
            for r in (c + 1)..<n where a[r][c] != 0 {
                let f = a[r][c] / a[c][c]
                for k in c..<n { a[r][k] -= f * a[c][k] }
                b[r] -= f * b[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for k in (r + 1)..<n { s -= a[r][k] * x[k] }
            x[r] = s / a[r][r]
        }
        return x
    }

    /// Point of the spline at parameter u (clamped cubic from `interpolate`).
    public static func point(_ s: SplineGeom, at u: Double) -> Vec2? {
        guard s.controlPoints.count >= 2, s.knots.count == s.controlPoints.count + s.degree + 1 else { return nil }
        let n = s.controlPoints.count - 1
        let sp = span(Swift.min(Swift.max(u, s.knots[s.degree]), s.knots[n + 1]), n, s.degree, s.knots)
        let N = basis(sp, Swift.min(Swift.max(u, s.knots[s.degree]), s.knots[n + 1]), s.degree, s.knots)
        var out = Vec2.zero
        for j in 0...s.degree { out = out + s.controlPoints[sp - s.degree + j] * N[j] }
        return out
    }
}
