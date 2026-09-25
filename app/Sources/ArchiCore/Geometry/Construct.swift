// Oanarina Archi Tool — GPL-3.0-or-later
// Construction geometry: tangents, Apollonius circles, arcs by height/length, conic constructions, regular polygons,
// splitting curves at points, clipping, welding and gap creation.
import Foundation

public enum Construct {
    // MARK: Lines
    /// Tangent points on a circle seen from an outside point (0 or 2 points).
    public static func tangentPoints(from p: Vec2, center c: Vec2, radius r: Double) -> [Vec2] {
        let d = p - c, dl = d.length
        guard dl > r + 1e-12 else { return [] }
        let a = acos(r / dl)
        return [c + Vec2.polar(r, d.angle + a), c + Vec2.polar(r, d.angle - a)]
    }

    public enum TangentKind { case outer, inner }
    /// Common tangent segments of two circles (tangent point on the first, tangent point on the second).
    public static func commonTangents(_ c1: Vec2, _ r1: Double, _ c2: Vec2, _ r2: Double, kind: TangentKind) -> [(Vec2, Vec2)] {
        let d = c2 - c1, dl = d.length
        guard dl > 1e-12 else { return [] }
        let base = d.angle
        switch kind {
        case .outer:
            guard dl > abs(r1 - r2) + 1e-12 else { return [] }
            let a = acos((r1 - r2) / dl)
            return [1.0, -1.0].map { s in (c1 + Vec2.polar(r1, base + s * a), c2 + Vec2.polar(r2, base + s * a)) }
        case .inner:
            guard dl > r1 + r2 + 1e-12 else { return [] }
            let a = acos((r1 + r2) / dl)
            return [1.0, -1.0].map { s in (c1 + Vec2.polar(r1, base + s * a), c2 + Vec2.polar(r2, base + s * a + .pi)) }
        }
    }

    /// Foot of the perpendicular from p onto the infinite line ab.
    public static func foot(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Vec2 {
        let d = (b - a).normalized
        return a + d * (p - a).dot(d)
    }

    /// Unit bisector direction of two lines (through their intersection), choosing the bisector of the angle containing `toward`.
    public static func bisector(_ l1: LineGeom, _ l2: LineGeom, toward: Vec2?) -> (origin: Vec2, dir: Vec2)? {
        guard let x = GeometryOps.lineIntersection(l1.a, l1.b, l2.a, l2.b) else { return nil }
        let u = (l1.b - l1.a).normalized, v = (l2.b - l2.a).normalized
        var cands = [(u + v).normalized, (u - v).normalized].filter { $0 != .zero }
        cands += cands.map { -$0 }
        guard !cands.isEmpty else { return nil }
        let t = toward ?? (x + (u + v))
        let dir = cands.max { ($0.dot(t - x)) < ($1.dot(t - x)) }!
        return (x, dir)
    }

    // MARK: Circles
    public enum TangentItem: Equatable { case point(Vec2), line(Vec2, Vec2), circle(Vec2, Double) }

    /// Circles tangent to / through the given items (up to three), solved numerically for every tangency variant.
    public static func apollonius(_ items: [TangentItem], radius fixedR: Double? = nil) -> [CircleGeom] {
        let nEq = items.count + (fixedR == nil ? 0 : 1)
        guard nEq == 3 else { return [] }
        // Variants: line side ±1, circle external / internal (new inside) / enclosing.
        var variantSets: [[Int]] = [[]]
        for it in items {
            let vs: [Int]
            switch it { case .point: vs = [0]; case .line: vs = [1, -1]; case .circle: vs = [0, 1, 2] }
            variantSets = variantSets.flatMap { s in vs.map { s + [$0] } }
        }
        var ext = BBox2.empty
        for it in items {
            switch it {
            case .point(let p): ext.add(p)
            case .line(let a, let b): ext.add(a); ext.add(b)
            case .circle(let o, let r): ext.add(o - Vec2(r, r)); ext.add(o + Vec2(r, r))
            }
        }
        let size = max(ext.width, ext.height, 1e-6)
        let scale = max(size, ext.max.x.magnitude, ext.max.y.magnitude, ext.min.x.magnitude, ext.min.y.magnitude, 1)
        func F(_ z: [Double], _ vr: [Int]) -> [Double] {
            let c = Vec2(z[0], z[1]), r = fixedR ?? z[2]
            var out: [Double] = []
            for (i, it) in items.enumerated() {
                switch it {
                case .point(let p): out.append(c.distance(to: p) - r)
                case .line(let a, let b):
                    let d = (b - a).normalized
                    out.append(Double(vr[i]) * d.cross(c - a) - r)
                case .circle(let o, let R):
                    let dd = c.distance(to: o)
                    switch vr[i] { case 0: out.append(dd - (R + r)); case 1: out.append(dd - (R - r)); default: out.append(dd - (r - R)) }
                }
            }
            if let fr = fixedR { _ = fr }
            return out
        }
        // Seeds around the configuration.
        var seeds: [Vec2] = [ext.center]
        for it in items {
            switch it {
            case .point(let p): seeds.append(p)
            case .line(let a, let b): seeds.append((a + b) / 2)
            case .circle(let o, _): seeds.append(o)
            }
        }
        let ring = (0..<8).map { ext.center + Vec2.polar(size * 0.75, Double($0) * .pi / 4) }
        seeds += ring
        var sols: [CircleGeom] = []
        let unknowns = fixedR == nil ? 3 : 2
        for vr in variantSets {
            for s in seeds {
                for r0 in (fixedR == nil ? [size * 0.25, size * 0.6, size * 1.5] : [fixedR!]) {
                    var z = [s.x, s.y, r0]
                    var ok = false
                    for _ in 0..<60 {
                        let f = F(z, vr)
                        let fn = f.map { abs($0) }.max() ?? 0
                        if fn < 1e-11 * scale { ok = true; break }
                        // Jacobian (numeric) and Newton step.
                        var J = [[Double]](repeating: [Double](repeating: 0, count: unknowns), count: 3)
                        for j in 0..<unknowns {
                            var zp = z, zm = z
                            let h = 1e-7 * max(1, abs(z[j]))
                            zp[j] += h; zm[j] -= h
                            let fp = F(zp, vr), fm = F(zm, vr)
                            for i in 0..<3 { J[i][j] = (fp[i] - fm[i]) / (2 * h) }
                        }
                        let step: [Double]?
                        if unknowns == 3 { step = Constraints.solveLinear(J, f.map { -$0 }) }
                        else {
                            // 3 equations, 2 unknowns (fixed radius): least squares via normal equations.
                            var A = [[0.0, 0.0], [0.0, 0.0]], b = [0.0, 0.0]
                            for i in 0..<3 { for a in 0..<2 { b[a] -= J[i][a] * f[i]; for c in 0..<2 { A[a][c] += J[i][a] * J[i][c] } } }
                            step = Constraints.solveLinear(A, b)
                        }
                        guard let st = step, st.allSatisfy({ $0.isFinite }) else { break }
                        var t = 1.0
                        let n0 = f.map { $0 * $0 }.reduce(0, +)
                        var improved = false
                        for _ in 0..<20 {
                            var zn = z
                            for j in 0..<unknowns { zn[j] += t * st[j] }
                            if F(zn, vr).map({ $0 * $0 }).reduce(0, +) < n0 { z = zn; improved = true; break }
                            t *= 0.5
                        }
                        if !improved { break }
                    }
                    let r = fixedR ?? z[2]
                    guard ok, r > 1e-9 * scale, r.isFinite, r < 1e4 * scale else { continue }
                    let c = CircleGeom(Vec2(z[0], z[1]), r)
                    if !sols.contains(where: { $0.center.isClose(c.center, tol: 1e-7 * scale) && abs($0.radius - c.radius) < 1e-7 * scale }) { sols.append(c) }
                }
            }
        }
        return sols
    }

    /// Point where a circle touches an item (for choosing among solutions by pick points).
    public static func touchPoint(_ c: CircleGeom, _ it: TangentItem) -> Vec2 {
        switch it {
        case .point(let p): return p
        case .line(let a, let b): return foot(c.center, a, b)
        case .circle(let o, let R):
            let d = (c.center - o).normalized
            let d1 = d == .zero ? Vec2(1, 0) : d
            let p1 = o + d1 * R, p2 = o - d1 * R
            return abs(p1.distance(to: c.center) - c.radius) <= abs(p2.distance(to: c.center) - c.radius) ? p1 : p2
        }
    }

    /// The solution whose touch points are nearest the picks.
    public static func best(_ sols: [CircleGeom], items: [TangentItem], picks: [Vec2?]) -> CircleGeom? {
        sols.min { a, b in
            func score(_ c: CircleGeom) -> Double {
                var s = 0.0
                for (i, it) in items.enumerated() { if i < picks.count, let p = picks[i] { s += touchPoint(c, it).distance(to: p) } }
                return s
            }
            return score(a) < score(b)
        }
    }

    /// Circle inscribed in the triangle formed by three lines (nil if two are parallel).
    public static func incircle(_ l1: LineGeom, _ l2: LineGeom, _ l3: LineGeom) -> CircleGeom? {
        guard let a = GeometryOps.lineIntersection(l2.a, l2.b, l3.a, l3.b), let b = GeometryOps.lineIntersection(l1.a, l1.b, l3.a, l3.b),
              let c = GeometryOps.lineIntersection(l1.a, l1.b, l2.a, l2.b) else { return nil }
        let la = b.distance(to: c), lb = a.distance(to: c), lc = a.distance(to: b)
        let p = la + lb + lc
        guard p > 1e-12 else { return nil }
        let center = (a * la + b * lb + c * lc) / p
        let s = p / 2
        let area = abs((b - a).cross(c - a)) / 2
        guard area > 1e-12 else { return nil }
        return CircleGeom(center, area / s)
    }

    /// Circle through two points with a radius; `side` picks which of the two centres.
    public static func circle2PR(_ p1: Vec2, _ p2: Vec2, radius r: Double, side: Vec2) -> CircleGeom? {
        let d = p1.distance(to: p2)
        guard d > 1e-12, r >= d / 2 - 1e-12 else { return nil }
        let m = (p1 + p2) / 2, n = (p2 - p1).normalized.perp
        let h = max(0, r * r - d * d / 4).squareRoot()
        let c1 = m + n * h, c2 = m - n * h
        return CircleGeom(c1.distance(to: side) <= c2.distance(to: side) ? c1 : c2, r)
    }

    // MARK: Arcs
    /// Arc from p1 to p2 whose sagitta (height at the chord midpoint) is `h`; positive h bulges to the left of p1→p2.
    public static func arcByHeight(_ p1: Vec2, _ p2: Vec2, height h: Double) -> ArcGeom? {
        let c = p1.distance(to: p2)
        guard c > 1e-12, abs(h) > 1e-12 else { return nil }
        // |bulge| = tan(θ/4) = 2h/c; a positive bulge turns clockwise-right of p1→p2, so a left bulge is negative.
        return arcFromBulge(p1, p2, -2 * h / c)
    }
    /// Arc from p1 to p2 with arc length `L` (> chord); `left` bulges to the left of p1→p2.
    public static func arcByLength(_ p1: Vec2, _ p2: Vec2, length L: Double, left: Bool) -> ArcGeom? {
        let c = p1.distance(to: p2)
        guard c > 1e-12, L > c * (1 + 1e-12), L < .pi * c * 1e6 else { return nil }
        // c/L = sin(θ/2)/(θ/2), θ ∈ (0, 2π): the ratio decreases monotonically on (0, 2π).
        let k = c / L
        var lo = 1e-12, hi = 2 * .pi - 1e-12
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if sin(mid / 2) / (mid / 2) > k { lo = mid } else { hi = mid }
        }
        let theta = (lo + hi) / 2
        return arcFromBulge(p1, p2, (left ? -1 : 1) * tan(theta / 4))
    }
    static func arcFromBulge(_ a: Vec2, _ b: Vec2, _ bulge: Double) -> ArcGeom {
        let arc = GeometryOps.bulgeArc(a, b, bulge)
        if arc.sweep >= 0 { return ArcGeom(arc.center, arc.radius, normAngle(arc.start), normAngle(arc.start + arc.sweep)) }
        return ArcGeom(arc.center, arc.radius, normAngle(arc.start + arc.sweep), normAngle(arc.start))
    }

    // MARK: Ellipses
    /// Ellipse from its two foci and a point on it.
    public static func ellipseFoci(_ f1: Vec2, _ f2: Vec2, through p: Vec2) -> EllipseGeom? {
        let a = (p.distance(to: f1) + p.distance(to: f2)) / 2
        let c = f1.distance(to: f2) / 2
        guard a > c + 1e-12, a > 1e-12 else { return nil }
        let b = (a * a - c * c).squareRoot()
        let dir = c > 1e-12 ? (f2 - f1).normalized : Vec2(1, 0)
        return EllipseGeom(center: (f1 + f2) / 2, majorAxis: dir * a, ratio: b / a)
    }
    /// Ellipse with a given centre through three points (general orientation): A u² + B uv + C v² = 1.
    public static func ellipseCenter3(_ c: Vec2, _ p: [Vec2]) -> EllipseGeom? {
        guard p.count == 3 else { return nil }
        let rows = p.map { q -> [Double] in let u = q - c; return [u.x * u.x, u.x * u.y, u.y * u.y] }
        guard let s = Constraints.solveLinear(rows, [1, 1, 1]), s.allSatisfy({ $0.isFinite }) else { return nil }
        // Check the fit (singular systems are regularised by solveLinear).
        for r in rows where abs(r[0] * s[0] + r[1] * s[1] + r[2] * s[2] - 1) > 1e-9 { return nil }
        return conicToEllipse(A: s[0], B: s[1], C: s[2], center: c)
    }
    /// Ellipse A u² + B uv + C v² = 1 (centred) → axes.
    static func conicToEllipse(A: Double, B: Double, C: Double, center: Vec2) -> EllipseGeom? {
        guard 4 * A * C - B * B > 1e-18 * max(1, (A * A + C * C)), A + C > 0 else { return nil }
        // Eigen-decomposition of [[A, B/2], [B/2, C]].
        let tr = A + C, det = A * C - B * B / 4
        let disc = max(0, tr * tr / 4 - det).squareRoot()
        let l1 = tr / 2 - disc, l2 = tr / 2 + disc      // l1 ≤ l2 → semi-axes 1/√l1 ≥ 1/√l2
        guard l1 > 0 else { return nil }
        let a = 1 / l1.squareRoot(), b = 1 / l2.squareRoot()
        var v: Vec2
        if abs(B) > 1e-15 { v = Vec2(B / 2, l1 - A).normalized } else { v = A <= C ? Vec2(1, 0) : Vec2(0, 1) }
        if v == .zero { v = Vec2(1, 0) }
        return EllipseGeom(center: center, majorAxis: v * a, ratio: b / a)
    }
    /// Ellipse through four points with its axes at `rotation`: A x² + C y² + D x + E y = 1 in the rotated frame.
    public static func ellipse4(_ p: [Vec2], rotation: Double = 0) -> EllipseGeom? {
        guard p.count == 4 else { return nil }
        let q = p.map { $0.rotated(by: -rotation) }
        let rows = q.map { [$0.x * $0.x, $0.y * $0.y, $0.x, $0.y] }
        // Normalise coordinates for conditioning.
        guard let s = Constraints.solveLinear(rows, [1, 1, 1, 1]) else { return nil }
        for (r, _) in zip(rows, q) where abs(r[0] * s[0] + r[1] * s[1] + r[2] * s[2] + r[3] * s[3] - 1) > 1e-7 { return nil }
        let A = s[0], C = s[1], D = s[2], E = s[3]
        guard A > 0, C > 0 else { return nil }
        let cx = -D / (2 * A), cy = -E / (2 * C)
        let k = 1 + A * cx * cx + C * cy * cy
        guard k > 0 else { return nil }
        let a = (k / A).squareRoot(), b = (k / C).squareRoot()
        let center = Vec2(cx, cy).rotated(by: rotation)
        if a >= b { return EllipseGeom(center: center, majorAxis: Vec2.polar(a, rotation), ratio: b / a) }
        return EllipseGeom(center: center, majorAxis: Vec2.polar(b, rotation + .pi / 2), ratio: a / b)
    }

    // MARK: Polygons and points
    /// Regular polygon of n sides given the midpoint of one side (p1) and the opposite side's midpoint (even n) or opposite vertex (odd n).
    public static func polygonSideSide(sides n: Int, _ p1: Vec2, _ p2: Vec2) -> [Vec2]? {
        guard n >= 3, p1.distance(to: p2) > 1e-12 else { return nil }
        let across = p1.distance(to: p2)
        let apothem = n % 2 == 0 ? across / 2 : across / (1 + 1 / cos(.pi / Double(n)))
        let R = apothem / cos(.pi / Double(n))
        let dir = (p1 - p2).normalized
        let center = p1 - dir * apothem
        let a0 = dir.angle - .pi / Double(n)
        return (0..<n).map { center + Vec2.polar(R, a0 + 2 * .pi * Double($0) / Double(n)) }
    }
    /// `count` points evenly spaced from a to b inclusive.
    public static func pointsOnLine(_ a: Vec2, _ b: Vec2, count: Int) -> [Vec2] {
        guard count >= 1 else { return [] }
        if count == 1 { return [(a + b) / 2] }
        return (0..<count).map { a.lerp(b, Double($0) / Double(count - 1)) }
    }
    /// Lattice of columns × rows points from `origin` with spacings (in the direction of `angle`).
    public static func lattice(origin: Vec2, columns: Int, rows: Int, dx: Double, dy: Double, angle: Double = 0) -> [Vec2] {
        guard columns >= 1, rows >= 1 else { return [] }
        var out: [Vec2] = []
        for r in 0..<rows { for c in 0..<columns { out.append(origin + Vec2(Double(c) * dx, Double(r) * dy).rotated(by: angle)) } }
        return out
    }

    // MARK: Splitting, clipping, gaps, welding
    /// Splits a curve at the given points (projected onto it). Closed curves need at least two distinct points.
    public static func split(_ g: Geometry, at pts: [Vec2]) -> [Geometry] {
        guard let path = CurvePath.make(g), !pts.isEmpty else { return [g] }
        let n = path.count
        let eps = 1e-9 * max(1, n)
        var ss = pts.map { path.closest($0).s }.sorted()
        ss = CurveMath.dedupeSorted(ss, tol: eps)
        if path.closed {
            // Points at the seam (s = n) are the same as s = 0.
            ss = ss.map { $0 >= n - eps ? 0 : $0 }.sorted()
            ss = CurveMath.dedupeSorted(ss, tol: eps)
            guard ss.count >= 2 else {
                if ss.count == 1, path.kind != .circle, path.kind != .ellipse, let r = Modify.breakAt(g, path.point(ss[0]), path.point(ss[0])) { return r }
                return [g]
            }
            var out: [Geometry] = []
            for i in 0..<ss.count { if let piece = path.geometry(ss[i], ss[(i + 1) % ss.count]) { out.append(piece) } }
            return out.isEmpty ? [g] : out
        }
        ss = ss.filter { $0 > eps && $0 < n - eps }
        guard !ss.isEmpty else { return [g] }
        let bounds = [0.0] + ss + [n]
        var out: [Geometry] = []
        for i in 0..<(bounds.count - 1) where bounds[i + 1] - bounds[i] > eps { if let p = path.geometry(bounds[i], bounds[i + 1]) { out.append(p) } }
        return out.isEmpty ? [g] : out
    }

    /// Parts of a curve inside (or outside) a closed polygon.
    public static func clip(_ g: Geometry, polygon: [Vec2], keepInside: Bool, doc: ArchiDocument?) -> [Geometry] {
        guard polygon.count >= 3 else { return [g] }
        let boundary = Geometry.polyline(PolylineGeom(points: polygon, closed: true))
        let xs = Intersections.of(g, boundary, doc: doc)
        let pieces = split(g, at: xs)
        return pieces.filter { p in
            guard let m = Modify.point(on: p, atFraction: 0.5, doc: doc) else { return false }
            return GeometryOps.pointInPolygon(m, polygon) == keepInside
        }
    }

    /// Removes a gap of `width` centred on each crossing point from a curve.
    public static func gaps(_ g: Geometry, at pts: [Vec2], width: Double) -> [Geometry] {
        guard width > 0, let path = CurvePath.make(g), !pts.isEmpty else { return [g] }
        let total = path.length
        guard total > 1e-12 else { return [g] }
        var cuts: [(Double, Double)] = []
        for p in pts {
            let s = path.closest(p).s
            let l = path.length(at: s)
            cuts.append((l - width / 2, l + width / 2))
        }
        cuts.sort { $0.0 < $1.0 }
        // Merge overlapping cuts.
        var merged: [(Double, Double)] = []
        for c in cuts { if let last = merged.last, c.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, c.1) } else { merged.append(c) } }
        if path.closed {
            // Wrap: turn the closed curve into an open one starting at the middle of the first cut.
            guard let first = merged.first else { return [g] }
            var keep: [(Double, Double)] = []
            for i in 0..<merged.count {
                let a = merged[i].1, b = i + 1 < merged.count ? merged[i + 1].0 : merged[0].0 + total
                if b - a > 1e-9 { keep.append((a, b)) }
            }
            _ = first
            return keep.compactMap { k in
                let s0 = path.param(atLength: k.0.truncatingRemainder(dividingBy: total) < 0 ? k.0 + total : k.0.truncatingRemainder(dividingBy: total))
                let e = k.1.truncatingRemainder(dividingBy: total)
                let s1 = path.param(atLength: e < 0 ? e + total : e)
                return path.geometry(s0, s1)
            }
        }
        var keep: [(Double, Double)] = []
        var cur = 0.0
        for c in merged { if c.0 > cur + 1e-9 { keep.append((cur, min(c.0, total))) }; cur = max(cur, c.1) }
        if cur < total - 1e-9 { keep.append((cur, total)) }
        return keep.compactMap { path.geometry(path.param(atLength: max(0, $0.0)), path.param(atLength: min(total, $0.1))) }
    }

    /// Polyline vertices of a curve: lines/arcs/polylines exactly (bulges), other curves sampled within `tolerance` (chord height).
    public static func polylineVertices(_ g: Geometry, tolerance: Double, doc: ArchiDocument?) -> (vertices: [PolyVertex], closed: Bool)? {
        switch g {
        case .line(let l): return ([PolyVertex(l.a), PolyVertex(l.b)], false)
        case .arc(let a):
            let s = a.sweep
            return ([PolyVertex(a.startPoint, bulge: tan(s / 4)), PolyVertex(a.endPoint)], false)
        case .circle(let c):
            return ([PolyVertex(c.center + Vec2(c.radius, 0), bulge: 1), PolyVertex(c.center - Vec2(c.radius, 0), bulge: 1)], true)
        case .polyline(let p): return (p.vertices, p.closed)
        case .ellipse, .spline:
            guard let path = CurvePath.make(g) else { return nil }
            let total = path.length
            guard total > 1e-12 else { return nil }
            // Adaptive sampling: refine until the chord deviation is below tolerance.
            var ss: [Double] = (0...16).map { path.count * Double($0) / 16 }
            var guardN = 0
            var i = 0
            while i < ss.count - 1 && guardN < 20000 {
                guardN += 1
                let a = path.point(ss[i]), b = path.point(ss[i + 1]), mid = (ss[i] + ss[i + 1]) / 2
                let m = path.point(mid)
                if GeometryOps.distance(point: m, segA: a, segB: b) > max(tolerance, 1e-9) && ss[i + 1] - ss[i] > 1e-6 { ss.insert(mid, at: i + 1) } else { i += 1 }
            }
            var pts = ss.map { path.point($0) }
            if path.closed, let f = pts.first, let l = pts.last, f.isClose(l, tol: 1e-9) { pts.removeLast() }
            return (pts.map { PolyVertex($0) }, path.closed)
        default: return nil
        }
    }

    /// Merges curves that touch end to end (within `tol`) into polylines (splines/ellipses are sampled with `sampling`).
    public static func weld(_ gs: [Geometry], tol: Double, sampling: Double, doc: ArchiDocument?) -> [Geometry] {
        struct Chain { var v: [PolyVertex]; var src: Int }
        var chains: [Chain] = []
        var others: [Geometry] = []
        for (i, g) in gs.enumerated() {
            if let (v, closed) = polylineVertices(g, tolerance: sampling, doc: doc), v.count >= 2, !closed { chains.append(Chain(v: v, src: i)) }
            else { others.append(g) }
        }
        func reversed(_ v: [PolyVertex]) -> [PolyVertex] {
            let n = v.count
            return (0..<n).map { i in PolyVertex(v[n - 1 - i].p, bulge: i < n - 1 ? -v[n - 2 - i].bulge : 0) }
        }
        var out: [Geometry] = []
        var pending = chains
        while !pending.isEmpty {
            var ch = pending.removeFirst()
            var merged = 1
            var changed = true
            while changed {
                changed = false
                let s = ch.v.first!.p, e = ch.v.last!.p
                if ch.v.count > 2 && s.isClose(e, tol: tol) { break }
                for i in pending.indices {
                    var o = pending[i].v
                    if o.first!.p.isClose(e, tol: tol) {}
                    else if o.last!.p.isClose(e, tol: tol) { o = reversed(o) }
                    else if o.last!.p.isClose(s, tol: tol) { ch.v = Array(o.dropLast()) + ch.v; pending.remove(at: i); changed = true; merged += 1; break }
                    else if o.first!.p.isClose(s, tol: tol) { o = reversed(o); ch.v = Array(o.dropLast()) + ch.v; pending.remove(at: i); changed = true; merged += 1; break }
                    else { continue }
                    // Append o after the end (o starts at e).
                    ch.v[ch.v.count - 1].bulge = o[0].bulge
                    ch.v += o.dropFirst()
                    pending.remove(at: i); changed = true; merged += 1
                    break
                }
            }
            if merged == 1 { out.append(gs[ch.src]); continue }
            var closed = false
            if ch.v.count > 2, ch.v.first!.p.isClose(ch.v.last!.p, tol: tol) { ch.v.removeLast(); closed = true }
            out.append(.polyline(PolylineGeom(ch.v, closed: closed)))
        }
        return out + others
    }

    /// Spline fit through a polyline's vertices (closed polylines give closed splines).
    public static func splineFromPolyline(_ p: PolylineGeom) -> SplineGeom? {
        let pts = p.vertices.map(\.p)
        guard pts.count >= 2 else { return nil }
        return SplineGeom(degree: 3, controlPoints: [], fitPoints: pts, closed: p.closed)
    }
}
