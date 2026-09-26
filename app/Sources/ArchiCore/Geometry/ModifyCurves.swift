// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// FILLET / CHAMFER / EXTEND for curves without an exact carrier (MOD-037, MOD-041, MOD-042): open polylines (end
/// segments, straight or arc), ellipse arcs and splines, alone or combined with lines, arcs and circles.
extension Modify {
    /// A curve prepared for filleting: its path (lines extended far both ways so a fillet may lengthen them) and how to
    /// rebuild the kept part.
    struct FilletCurve {
        let g: Geometry
        let path: CurvePath
        let isLine: Bool
        init?(_ g: Geometry, reach: Double) {
            self.g = g
            switch g {
            case .line(let l):
                let d = (l.b - l.a).normalized
                guard d != .zero, let p = CurvePath.fromPoints([l.a - d * reach, l.b + d * reach], kind: .line) else { return nil }
                path = p; isLine = true
            case .circle, .arc:
                guard let p = CurvePath.make(g) else { return nil }
                path = p; isLine = false
            default:
                guard let p = CurvePath.make(g), !p.closed, !p.pieces.isEmpty else { return nil }
                path = p; isLine = false
            }
        }
        /// The object trimmed (or extended, for lines) to `x` on the path at parameter `sx`, keeping the pick's side.
        func kept(pick: Vec2, at x: Vec2, sx: Double) -> Geometry? {
            switch g {
            case .line(let l):
                let d = l.b - l.a
                let tp = (pick - l.a).dot(d), tx = (x - l.a).dot(d)
                let r = tp < tx ? LineGeom(l.a, x) : LineGeom(x, l.b)
                return r.a.isClose(r.b, tol: 1e-9) ? nil : .line(r)
            case .circle: return g
            case .arc(let a):
                return Modify.cornerTrim(.arc(a), pick: pick, at: x)
            default:
                let sp = path.closest(pick).s
                return sp < sx ? path.geometry(0, sx) : path.geometry(sx, path.count)
            }
        }
    }

    static func reach(_ a: Geometry, _ b: Geometry) -> Double {
        var bb = GeometryOps.bounds(a, doc: nil); bb.add(GeometryOps.bounds(b, doc: nil))
        return bb.isEmpty ? 1e6 : 4 * (bb.width + bb.height) + 1
    }

    /// Fillet between two general curves: the centre lies at distance r from both; found by root-finding the offset of
    /// the first curve against the distance to the second, choosing the solution whose tangent points are nearest the picks.
    static func filletCurves(_ a: Geometry, pickA: Vec2, _ b: Geometry, pickB: Vec2, radius r: Double) -> FilletResult? {
        let reach = reach(a, b)
        guard let A = FilletCurve(a, reach: reach), let B = FilletCurve(b, reach: reach) else { return nil }
        if r < geomEpsilon {
            let xs = CurveMath.intersect(A.path, B.path)
            guard let x = xs.min(by: { $0.p.distance(to: pickA) + $0.p.distance(to: pickB) < $1.p.distance(to: pickA) + $1.p.distance(to: pickB) }),
                  let na = A.kept(pick: pickA, at: x.p, sx: x.sa), let nb = B.kept(pick: pickB, at: x.p, sx: x.sb) else { return nil }
            return FilletResult(first: na, second: nb, arc: nil)
        }
        // Samples along A (denser on short pieces), for both offset sides.
        var ss: [Double] = []
        for i in 0..<A.pieces.count {
            let k = A.pieces[i].isArc ? 64 : (A.isLine ? 400 : 16)
            for j in 0..<k { ss.append(Double(i) + Double(j) / Double(k)) }
        }
        ss.append(A.path.count)
        var best: (c: Vec2, sa: Double, sb: Double, ta: Vec2, tb: Vec2, score: Double)?
        for side in [1.0, -1.0] {
            func center(_ s: Double) -> Vec2 { A.path.point(s) + A.path.tangent(s).perp * (side * r) }
            func f(_ s: Double) -> Double { B.path.closest(center(s)).dist - r }
            var prev = f(ss[0])
            for k in 1..<ss.count {
                let cur = f(ss[k])
                if prev.sign != cur.sign || cur == 0 {
                    var lo = ss[k - 1], hi = ss[k], flo = prev
                    for _ in 0..<60 {
                        let m = (lo + hi) / 2, fm = f(m)
                        if (fm < 0) == (flo < 0) { lo = m; flo = fm } else { hi = m }
                    }
                    let s = (lo + hi) / 2
                    let c = center(s)
                    let cb = B.path.closest(c)
                    // A true tangency on B: the foot is interior (not a clamped end) and at distance r.
                    let (bi, bt) = B.path.index(cb.s)
                    let clamped = (cb.s <= 1e-9 && B.path.pieces[bi].param(c) < -1e-6) || (cb.s >= B.path.count - 1e-9 && B.path.pieces[bi].param(c) > 1 + 1e-6)
                    _ = bt
                    if !clamped && abs(cb.dist - r) <= 1e-6 * Swift.max(1, r) {
                        let ta = A.path.point(s)
                        let score = ta.distance(to: pickA) + cb.point.distance(to: pickB)
                        if best == nil || score < best!.score { best = (c, s, cb.s, ta, cb.point, score) }
                    }
                }
                prev = cur
            }
        }
        guard let f = best, !f.ta.isClose(f.tb, tol: 1e-9),
              let na = A.kept(pick: pickA, at: f.ta, sx: f.sa), let nb = B.kept(pick: pickB, at: f.tb, sx: f.sb) else { return nil }
        // Minor arc between the tangent points.
        let arc = (f.ta - f.c).cross(f.tb - f.c) >= 0 ? ArcGeom(f.c, r, (f.ta - f.c).angle, (f.tb - f.c).angle)
                                                        : ArcGeom(f.c, r, (f.tb - f.c).angle, (f.ta - f.c).angle)
        return FilletResult(first: na, second: nb, arc: .arc(arc))
    }

    /// The straight end segment of an open polyline nearest `pick`, as a line, and a rebuild function taking the new
    /// end point (nil for other geometry).
    static func endSegment(_ g: Geometry, pick: Vec2) -> (line: LineGeom, rebuild: (LineGeom) -> Geometry)? {
        switch g {
        case .line(let l): return (l, { .line($0) })
        case .polyline(let pl) where !pl.closed && pl.vertices.count >= 2:
            let n = pl.vertices.count
            let first = LineGeom(pl.vertices[0].p, pl.vertices[1].p), last = LineGeom(pl.vertices[n - 2].p, pl.vertices[n - 1].p)
            let dFirst = GeometryOps.distance(point: pick, segA: first.a, segB: first.b), dLast = GeometryOps.distance(point: pick, segA: last.a, segB: last.b)
            if n == 2 || dLast <= dFirst {
                guard abs(pl.vertices[n - 2].bulge) < 1e-12 else { return nil }
                return (last, { l in var q = pl; q.vertices[n - 2].p = l.a; q.vertices[n - 1].p = l.b; return .polyline(q) })
            }
            guard abs(pl.vertices[0].bulge) < 1e-12 else { return nil }
            return (first, { l in var q = pl; q.vertices[0].p = l.a; q.vertices[1].p = l.b; return .polyline(q) })
        default: return nil
        }
    }

    /// Chamfer between lines and straight end segments of open polylines.
    static func chamferSegments(_ a: Geometry, pickA: Vec2, _ b: Geometry, pickB: Vec2, d1: Double, d2: Double) -> FilletResult? {
        guard let ea = endSegment(a, pick: pickA), let eb = endSegment(b, pick: pickB),
              let x = CurveMath.lineLine(ea.line.a, ea.line.b, eb.line.a, eb.line.b),
              let (na, ca) = chamferSide(ea.line, pickA, x, d1), let (nb, cb) = chamferSide(eb.line, pickB, x, d2) else { return nil }
        // A polyline's end segment must keep its inner vertex: the chamfer moves only the free end.
        func fix(_ orig: LineGeom, _ new: LineGeom, _ g: Geometry) -> LineGeom? {
            guard case .polyline(let pl) = g else { return new }
            let inner = pl.vertices.count >= 2 && orig.a.isClose(pl.vertices[pl.vertices.count - 2].p, tol: 1e-9) && orig.b.isClose(pl.vertices.last!.p, tol: 1e-9) ? orig.a : orig.b
            // The kept side must contain the inner vertex.
            let keepsInner = new.a.isClose(inner, tol: 1e-9) || new.b.isClose(inner, tol: 1e-9)
            return keepsInner ? new : nil
        }
        guard let fa = fix(ea.line, na, a), let fb = fix(eb.line, nb, b) else { return nil }
        let line: Geometry? = ca.isClose(cb, tol: 1e-9) ? nil : .line(LineGeom(ca, cb))
        return FilletResult(first: ea.rebuild(fa), second: eb.rebuild(fb), arc: line)
    }

    /// Extends an open spline: its end tangent is followed in a straight line to the nearest boundary and the curve gets a
    /// new end point there (fit point, or clamped control point).
    static func extendSpline(_ s: SplineGeom, at pick: Vec2, boundaries: [CurvePath]) -> Geometry? {
        guard !s.closed, let path = CurvePath.splinePath(s), !path.pieces.isEmpty else { return nil }
        let atEnd = path.closest(pick).s >= path.count / 2
        let p = atEnd ? path.end : path.start
        let t = atEnd ? path.tangent(path.count) : path.tangent(0) * -1
        guard t != .zero else { return nil }
        let ray = CurvePiece(seg: p, p + t)
        var best: Double?
        for bp in boundaries {
            for q in bp.pieces {
                for r in CurveMath.intersect(ray, q, extA: true, extB: false) where r.ta > 1e-9 {
                    if best == nil || r.ta < best! { best = r.ta }
                }
            }
        }
        guard let d = best else { return nil }
        let np = p + t * d
        var out = s
        if !out.fitPoints.isEmpty {
            if atEnd { out.fitPoints.append(np) } else { out.fitPoints.insert(np, at: 0) }
            out.controlPoints = []; out.knots = []; out.weights = nil
        } else {
            // Clamped B-spline: a new end control point on the tangent line keeps the curve G1 and ends exactly there.
            if atEnd { out.controlPoints.append(np) } else { out.controlPoints.insert(np, at: 0) }
            if let w = out.weights { out.weights = atEnd ? w + [1] : [1] + w }
            out.knots = []
        }
        return .spline(out)
    }
}

extension Modify.FilletCurve {
    var pieces: [CurvePiece] { path.pieces }
}
