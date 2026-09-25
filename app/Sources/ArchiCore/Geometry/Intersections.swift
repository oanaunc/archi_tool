// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Curve primitives shared by Intersections, Modify and Snap

/// A straight segment or circular arc (signed sweep, CCW > 0). Pieces of tessellated curves
/// (ellipse, spline) are flagged `approx` and carry the source curve parameter range u0…u1.
struct CurvePiece {
    var isArc: Bool
    var p0: Vec2
    var p1: Vec2
    var center = Vec2.zero
    var radius = 0.0
    var a0 = 0.0
    var sweep = 0.0
    var approx = false
    var u0 = 0.0
    var u1 = 0.0
    /// Polyline vertex index of the piece start (or a source index).
    var tag = 0

    init(seg a: Vec2, _ b: Vec2) { isArc = false; p0 = a; p1 = b }
    init(arc c: Vec2, _ r: Double, _ start: Double, _ sweep: Double) {
        isArc = true; center = c; radius = r; a0 = start; self.sweep = sweep
        p0 = c + Vec2.polar(r, start); p1 = c + Vec2.polar(r, start + sweep)
    }
    /// Polyline bulge segment (bulge = tan(sweep/4)).
    static func bulge(_ a: Vec2, _ b: Vec2, _ bulge: Double) -> CurvePiece {
        if abs(bulge) < 1e-12 || a.isClose(b, tol: 1e-12) { return CurvePiece(seg: a, b) }
        let sw = 4 * atan(bulge)
        let d = b - a, len = d.length
        let r = len / (2 * sin(abs(sw) / 2))
        let c = (a + b) / 2 + d.normalized.perp * ((sw > 0 ? 1 : -1) * r * cos(abs(sw) / 2))
        var p = CurvePiece(arc: c, r, (a - c).angle, sw)
        p.p0 = a; p.p1 = b
        return p
    }
    var bulgeValue: Double { isArc ? tan(sweep / 4) : 0 }
    var length: Double { isArc ? abs(sweep) * radius : p0.distance(to: p1) }
    var isDegenerate: Bool { length < 1e-12 }
    func point(_ t: Double) -> Vec2 {
        if isArc { return center + Vec2.polar(radius, a0 + sweep * t) }
        return p0 + (p1 - p0) * t
    }
    /// Unit tangent in the direction of travel.
    func tangent(_ t: Double) -> Vec2 {
        if isArc { return Vec2.polar(1, a0 + sweep * t).perp * (sweep >= 0 ? 1 : -1) }
        return (p1 - p0).normalized
    }
    /// Unclamped parameter of the projection of p (arcs: extension on the angularly nearer side).
    func param(_ p: Vec2) -> Double {
        if isArc {
            let s = abs(sweep)
            guard s > 1e-15 else { return 0 }
            let ang = (p - center).angle
            var d = sweep >= 0 ? normAngle(ang - a0) : normAngle(a0 - ang)
            if d > s + 1e-12 {
                let over = d - s, under = 2 * .pi - d
                if under < over { d = -under }
            }
            return d / s
        }
        let d = p1 - p0, l2 = d.lengthSquared
        return l2 < 1e-24 ? 0 : (p - p0).dot(d) / l2
    }
    func closestParam(_ p: Vec2) -> Double { Swift.min(1, Swift.max(0, param(p))) }
    func closestPoint(_ p: Vec2) -> Vec2 { point(closestParam(p)) }
    /// Parameter tolerance equivalent to ~1e-8 drawing units.
    var paramEps: Double { Swift.max(1e-9, 1e-8 / Swift.max(length, 1e-12)) }
    func sub(_ t0: Double, _ t1: Double) -> CurvePiece {
        var r = isArc ? CurvePiece(arc: center, radius, a0 + sweep * t0, sweep * (t1 - t0)) : CurvePiece(seg: point(t0), point(t1))
        if t0 == 0 { r.p0 = p0 } else if t0 == 1 { r.p0 = p1 }
        if t1 == 1 { r.p1 = p1 } else if t1 == 0 { r.p1 = p0 }
        r.approx = approx; r.u0 = u0 + (u1 - u0) * t0; r.u1 = u0 + (u1 - u0) * t1; r.tag = tag
        return r
    }
    var reversed: CurvePiece {
        var r = isArc ? CurvePiece(arc: center, radius, a0 + sweep, -sweep) : CurvePiece(seg: p1, p0)
        r.p0 = p1; r.p1 = p0; r.approx = approx; r.u0 = u1; r.u1 = u0; r.tag = tag
        return r
    }
    /// Piece ending at x (x on the carrier); nil if that would reverse or collapse it.
    func withEnd(_ x: Vec2) -> CurvePiece? {
        let t = param(x)
        guard t > paramEps else { return nil }
        var r = isArc ? CurvePiece(arc: center, radius, a0, sweep * t) : CurvePiece(seg: p0, x)
        r.p0 = p0; r.p1 = x; r.tag = tag
        return r
    }
    func withStart(_ x: Vec2) -> CurvePiece? {
        let t = param(x)
        guard t < 1 - paramEps else { return nil }
        var r = isArc ? CurvePiece(arc: center, radius, a0 + sweep * t, sweep * (1 - t)) : CurvePiece(seg: x, p1)
        r.p0 = x; r.p1 = p1; r.tag = tag
        return r
    }
    var bounds: BBox2 {
        var b = BBox2(points: [p0, p1])
        if isArc {
            let s = sweep >= 0 ? a0 : a0 + sweep, sw = abs(sweep)
            for k in 0..<4 {
                let ang = Double(k) * .pi / 2
                if sw >= 2 * .pi - 1e-12 || normAngle(ang - s) <= sw { b.add(center + Vec2.polar(radius, ang)) }
            }
        }
        return b
    }
    /// Signed distance to the carrier (line: left positive; circle: outside positive).
    func signedDistance(_ p: Vec2) -> Double {
        if isArc { return p.distance(to: center) - radius }
        let d = (p1 - p0).normalized
        return d.cross(p - p0)
    }
    func transformed(_ t: Transform2D) -> CurvePiece {
        if isArc {
            let c = t.apply(center), s = t.scaleFactor
            var r = CurvePiece(arc: c, radius * s, t.isMirroring ? (t.apply(p0) - c).angle : a0 + t.rotationAngle,
                               t.isMirroring ? -sweep : sweep)
            r.p0 = t.apply(p0); r.p1 = t.apply(p1); r.tag = tag
            return r
        }
        var r = CurvePiece(seg: t.apply(p0), t.apply(p1)); r.approx = approx; r.tag = tag
        return r
    }
    /// ArcGeom (always CCW) for an arc piece.
    var arcGeom: ArcGeom {
        sweep >= 0 ? ArcGeom(center, radius, normAngle(a0), normAngle(a0 + sweep))
                   : ArcGeom(center, radius, normAngle(a0 + sweep), normAngle(a0))
    }
    var geometry: Geometry { isArc ? .arc(arcGeom) : .line(LineGeom(p0, p1)) }
}

/// A connected chain of pieces representing one curve. Global parameter s ∈ [0, pieces.count].
struct CurvePath {
    enum Kind { case line, arc, circle, ellipse, polyline, spline, other }
    var kind: Kind
    var pieces: [CurvePiece]
    var closed: Bool
    var eval: ((Double) -> Vec2)? = nil
    var ellipse: EllipseGeom? = nil
    var spline: SplineGeom? = nil
    var polyWidth = 0.0

    init(kind: Kind, pieces: [CurvePiece], closed: Bool) { self.kind = kind; self.pieces = pieces; self.closed = closed }

    var count: Double { Double(pieces.count) }
    var isEmpty: Bool { pieces.isEmpty }
    var start: Vec2 { pieces.first?.p0 ?? .zero }
    var end: Vec2 { pieces.last?.p1 ?? .zero }
    /// Whether `extended` intersection treats this as an infinite line / full circle.
    var extendable: Bool { kind == .line || kind == .arc }

    func index(_ s: Double) -> (Int, Double) {
        guard !pieces.isEmpty else { return (0, 0) }
        let i = Swift.max(0, Swift.min(pieces.count - 1, Int(s.rounded(.down))))
        return (i, s - Double(i))
    }
    func point(_ s: Double) -> Vec2 { let (i, t) = index(s); return pieces[i].point(t) }
    func tangent(_ s: Double) -> Vec2 { let (i, t) = index(s); return pieces[i].tangent(t) }
    func u(_ s: Double) -> Double { let (i, t) = index(s); let p = pieces[i]; return p.u0 + (p.u1 - p.u0) * t }

    func closest(_ p: Vec2) -> (s: Double, point: Vec2, dist: Double) {
        var best = (s: 0.0, point: start, dist: Double.infinity)
        for (i, pc) in pieces.enumerated() {
            let t = pc.closestParam(p), q = pc.point(t), d = q.distance(to: p)
            if d < best.dist { best = (Double(i) + t, q, d) }
        }
        return best
    }

    var length: Double { pieces.reduce(0) { $0 + $1.length } }
    func param(atLength l: Double) -> Double {
        var acc = 0.0
        for (i, p) in pieces.enumerated() {
            let pl = p.length
            if acc + pl >= l - 1e-12 { return Double(i) + (pl < 1e-15 ? 0 : Swift.max(0, Swift.min(1, (l - acc) / pl))) }
            acc += pl
        }
        return count
    }
    func length(at s: Double) -> Double {
        let (i, t) = index(s)
        return pieces[..<i].reduce(0) { $0 + $1.length } + pieces[i].length * t
    }

    func subPieces(_ s0: Double, _ s1: Double) -> [CurvePiece] {
        guard s1 > s0, !pieces.isEmpty else { return [] }
        var out: [CurvePiece] = []
        let i0 = Swift.max(0, Int(s0.rounded(.down))), i1 = Swift.min(pieces.count - 1, Int((s1 - 1e-12).rounded(.down)))
        guard i0 <= i1 else { return [] }
        for i in i0...i1 {
            let t0 = Swift.max(0, s0 - Double(i)), t1 = Swift.min(1, s1 - Double(i))
            if t1 - t0 > 1e-12 { out.append(pieces[i].sub(t0, t1)) }
        }
        return out
    }
    /// Pieces from s0 to s1 (wrapping through the start for closed paths when s1 < s0).
    func span(_ s0: Double, _ s1: Double) -> [CurvePiece] {
        if closed && s1 <= s0 { return subPieces(s0, count) + subPieces(0, s1) }
        return subPieces(s0, s1)
    }

    /// Geometry of the part of this curve between s0 and s1, keeping the source type where possible.
    func geometry(_ s0: Double, _ s1: Double) -> Geometry? {
        let pcs = span(s0, s1)
        guard !pcs.isEmpty, pcs.reduce(0, { $0 + $1.length }) > 1e-9 else { return nil }
        switch kind {
        case .line: return .line(LineGeom(pcs.first!.p0, pcs.last!.p1))
        case .arc, .circle:
            let p = pieces[0]
            let a = p.a0 + p.sweep * s0, b = p.a0 + p.sweep * s1
            return .arc(ArcGeom(p.center, p.radius, normAngle(a), normAngle(b)))
        case .ellipse:
            guard var e = ellipse else { return nil }
            e.start = normAngle(pcs.first!.u0); e.end = normAngle(pcs.last!.u1)
            if abs(e.end - e.start) < 1e-12 { e.end = e.start + 2 * .pi }
            return .ellipse(e)
        case .spline:
            guard let ev = eval else { return nil }
            var pts = [ev(pcs[0].u0)]
            for p in pcs { pts.append(ev(p.u1)) }
            pts[0] = pcs[0].p0; pts[pts.count - 1] = pcs.last!.p1
            if pts.count == 2 { return .line(LineGeom(pts[0], pts[1])) }
            return .spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: pts))
        case .polyline, .other:
            var v = pcs.map { PolyVertex($0.p0, bulge: $0.bulgeValue) }
            v.append(PolyVertex(pcs.last!.p1))
            return .polyline(PolylineGeom(v, closed: false, width: polyWidth))
        }
    }

    // MARK: Construction

    static func fromPoints(_ pts: [Vec2], closed: Bool = false, kind: Kind = .other) -> CurvePath? {
        guard pts.count >= 2 else { return nil }
        var pcs: [CurvePiece] = []
        for i in 0..<(pts.count - 1) where !pts[i].isClose(pts[i + 1], tol: 1e-12) {
            var p = CurvePiece(seg: pts[i], pts[i + 1]); p.tag = i; pcs.append(p)
        }
        if closed, let f = pts.first, let l = pts.last, !f.isClose(l, tol: 1e-12) {
            var p = CurvePiece(seg: l, f); p.tag = pts.count - 1; pcs.append(p)
        }
        return pcs.isEmpty ? nil : CurvePath(kind: kind, pieces: pcs, closed: closed)
    }

    static func polylinePath(_ v: [PolyVertex], closed: Bool) -> CurvePath? {
        guard v.count >= 2 else { return nil }
        var pcs: [CurvePiece] = []
        let n = closed ? v.count : v.count - 1
        for i in 0..<n {
            let a = v[i], b = v[(i + 1) % v.count]
            if a.p.isClose(b.p, tol: 1e-12) { continue }
            var p = CurvePiece.bulge(a.p, b.p, a.bulge); p.tag = i; pcs.append(p)
        }
        return pcs.isEmpty ? nil : CurvePath(kind: .polyline, pieces: pcs, closed: closed)
    }

    static func ellipsePath(_ e: EllipseGeom, from u0: Double, sweep: Double, closed: Bool) -> CurvePath? {
        guard e.majorAxis.length > geomEpsilon, abs(sweep) > 1e-12 else { return nil }
        let n = Swift.max(64, Swift.min(2048, GeometryOps.segments(radius: e.majorAxis.length, sweep: abs(sweep)) * 2))
        var pcs: [CurvePiece] = []
        var prev = e.point(at: u0)
        for i in 1...n {
            let u = u0 + sweep * Double(i) / Double(n)
            let q = e.point(at: u)
            var p = CurvePiece(seg: prev, q); p.approx = true
            p.u0 = u0 + sweep * Double(i - 1) / Double(n); p.u1 = u; p.tag = i - 1
            pcs.append(p); prev = q
        }
        var path = CurvePath(kind: .ellipse, pieces: pcs, closed: closed)
        path.eval = { e.point(at: $0) }; path.ellipse = e
        return path
    }

    /// Parametric evaluator of a spline: (f, u0, u1, sample count).
    static func splineEvaluator(_ s: SplineGeom) -> (f: (Double) -> Vec2, u0: Double, u1: Double, samples: Int)? {
        if s.controlPoints.count >= 2 {
            let n = s.controlPoints.count
            let p = Swift.max(1, Swift.min(s.degree, n - 1))
            var knots = s.knots
            if knots.count != n + p + 1 {
                knots = Array(repeating: 0, count: p + 1)
                let inner = n - p - 1
                if inner > 0 { for i in 1...inner { knots.append(Double(i) / Double(inner + 1)) } }
                knots += Array(repeating: 1, count: p + 1)
            }
            let w = (s.weights?.count == n) ? s.weights! : Array(repeating: 1, count: n)
            let t0 = knots[p], t1 = knots[n]
            guard t1 > t0 else { return nil }
            let ctrl = s.controlPoints
            let clampedEnd = knots[n] == knots[knots.count - 1]
            let f: (Double) -> Vec2 = { t in
                if t >= t1 && clampedEnd { return ctrl[n - 1] }
                let tt = Swift.min(Swift.max(t, t0), t1 - 1e-12 * Swift.max(1, abs(t1)))
                return GeometryOps.deBoor(t: tt, p: p, knots: knots, ctrl: ctrl, w: w)
            }
            return (f, t0, t1, Swift.max(32, (n - p) * 16))
        }
        let pts = s.fitPoints
        guard pts.count >= 2 else { return nil }
        let n = pts.count, closed = s.closed && n > 2
        let segs = closed ? n : n - 1
        let f: (Double) -> Vec2 = { u in
            let uu = Swift.max(0, Swift.min(Double(segs), u))
            let i = Swift.min(segs - 1, Int(uu.rounded(.down))), t = uu - Double(i)
            let p0 = pts[closed ? (i - 1 + n) % n : Swift.max(i - 1, 0)], p1 = pts[i]
            let p2 = pts[(i + 1) % n], p3 = pts[closed ? (i + 2) % n : Swift.min(i + 2, n - 1)]
            let t2 = t * t, t3 = t2 * t
            let a = p1 * 2, b = (p2 - p0) * t
            let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
            let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
            return (a + b + c + d) * 0.5
        }
        return (f, 0, Double(segs), Swift.max(16, segs * 16))
    }

    static func splinePath(_ s: SplineGeom) -> CurvePath? {
        guard let ev = splineEvaluator(s) else { return nil }
        let n = ev.samples
        var pcs: [CurvePiece] = []
        var prevU = ev.u0, prev = ev.f(ev.u0)
        for i in 1...n {
            let u = ev.u0 + (ev.u1 - ev.u0) * Double(i) / Double(n)
            let q = ev.f(u)
            var p = CurvePiece(seg: prev, q); p.approx = true; p.u0 = prevU; p.u1 = u; p.tag = i - 1
            if !p.isDegenerate { pcs.append(p) }
            prev = q; prevU = u
        }
        guard !pcs.isEmpty else { return nil }
        let closed = s.closed && pcs.first!.p0.isClose(pcs.last!.p1, tol: 1e-6)
        var path = CurvePath(kind: .spline, pieces: pcs, closed: closed)
        path.eval = ev.f; path.spline = s
        return path
    }

    /// Path of a single-curve geometry (line, arc, circle, ellipse, polyline, spline); nil otherwise.
    static func make(_ g: Geometry) -> CurvePath? {
        switch g {
        case .line(let l):
            guard !l.a.isClose(l.b, tol: 1e-12) else { return nil }
            return CurvePath(kind: .line, pieces: [CurvePiece(seg: l.a, l.b)], closed: false)
        case .arc(let a):
            guard a.radius > geomEpsilon else { return nil }
            return CurvePath(kind: .arc, pieces: [CurvePiece(arc: a.center, a.radius, a.start, a.sweep)], closed: false)
        case .circle(let c):
            guard c.radius > geomEpsilon else { return nil }
            return CurvePath(kind: .circle, pieces: [CurvePiece(arc: c.center, c.radius, 0, 2 * .pi)], closed: true)
        case .ellipse(let e):
            if e.isFull { return ellipsePath(e, from: e.start, sweep: 2 * .pi, closed: true) }
            return ellipsePath(e, from: e.start, sweep: normAngle(e.end - e.start), closed: false)
        case .polyline(let p):
            guard var path = polylinePath(p.vertices, closed: p.closed) else { return nil }
            path.polyWidth = p.width
            return path
        case .spline(let s): return splinePath(s)
        default: return nil
        }
    }

    /// All curve paths of any geometry (text boxes, hatch loops, dimension lines, block contents…).
    static func all(_ g: Geometry, doc: ArchiDocument?, depth: Int = 0) -> [CurvePath] {
        if let p = make(g) { return [p] }
        switch g {
        case .point, .line, .arc, .circle, .ellipse, .polyline, .spline: return []
        case .hatch(let h): return h.loops.compactMap { polylinePath($0, closed: true) }
        case .text(let t): return [fromPoints(GeometryOps.textBoxCorners(t), closed: true)].compactMap { $0 }
        case .dimension(let d):
            let st = doc?.dimStyle(d.style) ?? DimStyle(name: "Standard")
            let pr = DimensionRenderer.primitives(d, style: st)
            return pr.lines.compactMap { fromPoints($0) }
        case .leader(let l): return [fromPoints(l.points)].compactMap { $0 }
        case .insert(let ins):
            guard depth < 8, let doc = doc, let b = doc.blocks[ins.block] else { return [] }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            return b.entities.flatMap { all(GeometryTransform.apply($0.geometry, t), doc: doc, depth: depth + 1) }
        case .image, .table, .solid:
            return GeometryOps.tessellate(g, doc: doc).compactMap { fromPoints($0) }
        }
    }
}

enum CurveMath {
    static func lineLine(_ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ p4: Vec2) -> Vec2? {
        let d1 = p2 - p1, d2 = p4 - p3
        let den = d1.cross(d2)
        if abs(den) <= 1e-12 * d1.length * d2.length || abs(den) < 1e-300 { return nil }
        return p1 + d1 * ((p3 - p1).cross(d2) / den)
    }
    static func lineCircle(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ r: Double) -> [Vec2] {
        let d = b - a, l2 = d.lengthSquared
        guard l2 > 1e-24 else { return [] }
        let t = (c - a).dot(d) / l2
        let foot = a + d * t
        let h = foot.distance(to: c), tol = 1e-9 * Swift.max(1, r)
        if h > r + tol { return [] }
        if abs(h - r) <= tol { return [foot] }
        let k = (r * r - h * h).squareRoot() / l2.squareRoot()
        return [a + d * (t - k), a + d * (t + k)]
    }
    static func circleCircle(_ c1: Vec2, _ r1: Double, _ c2: Vec2, _ r2: Double) -> [Vec2] {
        let d = c2 - c1, dist = d.length, tol = 1e-9 * Swift.max(1, r1, r2)
        guard dist > 1e-12 else { return [] }
        if dist > r1 + r2 + tol || dist < abs(r1 - r2) - tol { return [] }
        let a = (r1 * r1 - r2 * r2 + dist * dist) / (2 * dist)
        let h2 = r1 * r1 - a * a
        let m = c1 + d * (a / dist)
        if h2 <= 1e-14 * Swift.max(1, r1 * r1) { return [m] }
        let n = d.perp / dist * h2.squareRoot()
        return [m + n, m - n]
    }

    /// Intersections of two pieces; ext* treats a segment as an infinite line and an arc as its full circle.
    static func intersect(_ A: CurvePiece, _ B: CurvePiece, extA: Bool = false, extB: Bool = false) -> [(p: Vec2, ta: Double, tb: Double)] {
        let pts: [Vec2]
        switch (A.isArc, B.isArc) {
        case (false, false): pts = lineLine(A.p0, A.p1, B.p0, B.p1).map { [$0] } ?? []
        case (false, true): pts = lineCircle(A.p0, A.p1, B.center, B.radius)
        case (true, false): pts = lineCircle(B.p0, B.p1, A.center, A.radius)
        case (true, true): pts = circleCircle(A.center, A.radius, B.center, B.radius)
        }
        var out: [(p: Vec2, ta: Double, tb: Double)] = []
        let ea = A.paramEps, eb = B.paramEps
        for p in pts {
            let ta = A.param(p), tb = B.param(p)
            if (extA || (ta >= -ea && ta <= 1 + ea)) && (extB || (tb >= -eb && tb <= 1 + eb)) { out.append((p, ta, tb)) }
        }
        return out
    }

    /// Refines an intersection of an approximated piece of `path` with an exact piece by bisection on the source curve.
    static func refine(_ piece: CurvePiece, eval: (Double) -> Vec2, against exact: CurvePiece) -> (p: Vec2, t: Double)? {
        var lo = piece.u0, hi = piece.u1
        var flo = exact.signedDistance(eval(lo)), fhi = exact.signedDistance(eval(hi))
        guard flo * fhi <= 0, abs(hi - lo) > 0 else { return nil }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2, fm = exact.signedDistance(eval(mid))
            if (fm <= 0) == (flo <= 0) { lo = mid; flo = fm } else { hi = mid; fhi = fm }
        }
        _ = fhi
        let u = (lo + hi) / 2
        return (eval(u), (u - piece.u0) / (piece.u1 - piece.u0))
    }

    /// Intersections between two paths with global parameters.
    static func intersect(_ A: CurvePath, _ B: CurvePath, extA: Bool = false, extB: Bool = false) -> [(p: Vec2, sa: Double, sb: Double)] {
        var out: [(p: Vec2, sa: Double, sb: Double)] = []
        let bbA = A.pieces.map { $0.bounds.expanded(by: 1e-7) }, bbB = B.pieces.map { $0.bounds.expanded(by: 1e-7) }
        var allB = BBox2.empty; bbB.forEach { allB.add($0) }
        for (i, pa) in A.pieces.enumerated() {
            if !extA && !extB && !bbA[i].intersects(allB) { continue }
            for (j, pb) in B.pieces.enumerated() {
                if !extA && !extB && !bbA[i].intersects(bbB[j]) { continue }
                for r in intersect(pa, pb, extA: extA, extB: extB) {
                    var p = r.p, ta = r.ta, tb = r.tb
                    if pa.approx && !pb.approx, let ev = A.eval, let f = refine(pa, eval: ev, against: pb) {
                        p = f.p; ta = f.t; tb = pb.param(p)
                    } else if pb.approx && !pa.approx, let ev = B.eval, let f = refine(pb, eval: ev, against: pa) {
                        p = f.p; tb = f.t; ta = pa.param(p)
                    }
                    out.append((p, Double(i) + ta, Double(j) + tb))
                }
            }
        }
        return out
    }

    static func dedupe(_ pts: [Vec2], tol: Double = 1e-7) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where !out.contains(where: { $0.isClose(p, tol: tol) }) { out.append(p) }
        return out
    }
    static func dedupeSorted(_ vals: [Double], tol: Double) -> [Double] {
        var out: [Double] = []
        for v in vals.sorted() where out.last.map({ v - $0 > tol }) ?? true { out.append(v) }
        return out
    }
}

/// General affine transform of geometry, including non-uniform scale (circles → ellipses, bulges → tessellated).
enum GeometryTransform {
    static func isSimilarity(_ t: Transform2D) -> Bool {
        let c1 = t.a * t.a + t.b * t.b, c2 = t.c * t.c + t.d * t.d
        return abs(c1 - c2) <= 1e-9 * Swift.max(c1, c2, 1e-300) && abs(t.a * t.c + t.b * t.d) <= 1e-9 * Swift.max(c1, 1e-300)
    }
    /// Ellipse from center and conjugate axes u (at t=0) and v (at t=π/2) over [t0, t1].
    static func ellipse(center: Vec2, u: Vec2, v: Vec2, t0: Double, t1: Double, full: Bool) -> EllipseGeom {
        var major = u, minor = v, shift = 0.0
        if v.length > u.length { major = v; minor = -u; shift = -.pi / 2 }
        let ratio = minor.length / Swift.max(major.length, 1e-300)
        var s0 = t0 + shift, s1 = t1 + shift
        if major.cross(minor) < 0 { (s0, s1) = (-s1, -s0) }
        if full { return EllipseGeom(center: center, majorAxis: major, ratio: ratio) }
        return EllipseGeom(center: center, majorAxis: major, ratio: ratio, start: normAngle(s0), end: normAngle(s1))
    }
    static func apply(_ g: Geometry, _ t: Transform2D) -> Geometry {
        if isSimilarity(t) { return GeometryOps.transform(g, t) }
        switch g {
        case .circle(let c):
            return .ellipse(ellipse(center: t.apply(c.center), u: t.applyVector(Vec2(c.radius, 0)), v: t.applyVector(Vec2(0, c.radius)), t0: 0, t1: 2 * .pi, full: true))
        case .arc(let a):
            return .ellipse(ellipse(center: t.apply(a.center), u: t.applyVector(Vec2(a.radius, 0)), v: t.applyVector(Vec2(0, a.radius)), t0: a.start, t1: a.start + a.sweep, full: false))
        case .ellipse(let e):
            let minor = e.majorAxis.perp * e.ratio
            return .ellipse(ellipse(center: t.apply(e.center), u: t.applyVector(e.majorAxis), v: t.applyVector(minor), t0: e.start, t1: e.isFull ? e.start + 2 * .pi : e.start + normAngle(e.end - e.start), full: e.isFull))
        case .polyline(var p):
            if p.vertices.contains(where: { abs($0.bulge) > 1e-12 }) {
                var pts = GeometryOps.polylinePoints(p.vertices, closed: p.closed)
                if p.closed, pts.count > 1 { pts.removeLast() }
                p.vertices = pts.map { PolyVertex(t.apply($0)) }
            } else { p.vertices = p.vertices.map { PolyVertex(t.apply($0.p)) } }
            p.width *= t.scaleFactor
            return .polyline(p)
        case .hatch(var h):
            h.loops = h.loops.map { loop in
                var pts = GeometryOps.polylinePoints(loop, closed: true)
                if pts.count > 1 { pts.removeLast() }
                return pts.map { PolyVertex(t.apply($0)) }
            }
            h.scale *= t.scaleFactor; h.angle += t.rotationAngle
            return .hatch(h)
        case .text(var tx):
            let up = t.applyVector(Vec2.polar(1, tx.rotation + .pi / 2))
            tx.position = t.apply(tx.position)
            tx.rotation = normAngle(t.applyVector(Vec2.polar(1, tx.rotation)).angle)
            tx.height *= up.length; tx.width *= t.applyVector(Vec2.polar(1, tx.rotation)).length
            return .text(tx)
        default:
            return GeometryOps.transform(g, t)
        }
    }
}

// MARK: - Public API

public enum Intersections {
    /// Intersection points of two geometries. With `extended`, lines are treated as infinite lines,
    /// arcs as full circles and elliptical arcs as full ellipses (polylines/splines are not extended).
    public static func of(_ a: Geometry, _ b: Geometry, doc: ArchiDocument?, extended: Bool = false) -> [Vec2] {
        let pa = paths(a, doc: doc, extended: extended), pb = paths(b, doc: doc, extended: extended)
        var out: [Vec2] = []
        for x in pa {
            for y in pb {
                for r in CurveMath.intersect(x, y, extA: extended && x.extendable, extB: extended && y.extendable) { out.append(r.p) }
            }
        }
        return CurveMath.dedupe(out)
    }

    static func paths(_ g: Geometry, doc: ArchiDocument?, extended: Bool) -> [CurvePath] {
        if extended, case .ellipse(let e) = g, !e.isFull {
            return [CurvePath.ellipsePath(e, from: e.start, sweep: 2 * .pi, closed: true)].compactMap { $0 }
        }
        return CurvePath.all(g, doc: doc)
    }

    /// Self-intersections of a polyline or spline (non-adjacent pieces).
    public static func selfIntersections(_ g: Geometry) -> [Vec2] {
        guard let p = CurvePath.make(g), p.pieces.count > 2 else { return [] }
        var out: [Vec2] = []
        let n = p.pieces.count
        for i in 0..<n {
            for j in (i + 2)..<Swift.max(i + 2, n) {
                if p.closed && i == 0 && j == n - 1 { continue }
                for r in CurveMath.intersect(p.pieces[i], p.pieces[j]) { out.append(r.p) }
            }
        }
        return CurveMath.dedupe(out)
    }
}
