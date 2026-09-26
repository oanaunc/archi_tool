// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Result of FILLET / CHAMFER: the two modified objects and the connecting arc or chamfer line (nil for a sharp corner).
/// When both inputs are the same polyline, `first` and `second` are the same updated polyline and `arc` is nil.
public struct FilletResult {
    public var first: Geometry; public var second: Geometry; public var arc: Geometry?
    public init(first: Geometry, second: Geometry, arc: Geometry?) { self.first = first; self.second = second; self.arc = arc }
}

/// AutoCAD-style modification algorithms on geometry values (no document mutation).
public enum Modify {

    // MARK: Trim / Extend

    /// Removes the part of `g` that contains `pick` between the nearest intersections with `boundaries`.
    /// Returns the replacement pieces ([] = delete the object), or nil when nothing can be trimmed.
    public static func trim(_ g: Geometry, at pick: Vec2, boundaries: [Geometry], doc: ArchiDocument?) -> [Geometry]? {
        guard let path = CurvePath.make(g) else { return nil }
        let n = path.count
        var params: [Double] = []
        for b in boundaries where b != g {
            for bp in CurvePath.all(b, doc: doc) {
                for r in CurveMath.intersect(path, bp) { params.append(r.sa) }
            }
        }
        let eps = 1e-9 * Swift.max(1, n)
        let sp = path.closest(pick).s
        if path.closed {
            let ps = CurveMath.dedupeSorted(params.map { $0 >= n - eps ? 0 : Swift.max(0, $0) }, tol: eps)
            var uniq = ps
            if uniq.count > 1, let f = uniq.first, let l = uniq.last, n - l + f <= eps { uniq.removeLast() }
            guard uniq.count >= 2 else { return nil }
            let a = uniq.last(where: { $0 < sp }) ?? uniq.last!
            let b = uniq.first(where: { $0 > sp }) ?? uniq.first!
            return path.geometry(b, a).map { [$0] } ?? []
        }
        let ps = CurveMath.dedupeSorted(params.filter { $0 > eps && $0 < n - eps }, tol: eps)
        guard !ps.isEmpty else { return nil }
        let a = ps.last(where: { $0 < sp }), b = ps.first(where: { $0 > sp })
        var out: [Geometry] = []
        if let a = a, let g0 = path.geometry(0, a) { out.append(g0) }
        if let b = b, let g1 = path.geometry(b, n) { out.append(g1) }
        return out
    }

    /// Parameter (on the piece, unclamped) where the piece extended beyond its end/start first meets a boundary.
    static func extendParam(_ piece: CurvePiece, atEnd: Bool, boundaries: [CurvePath]) -> Double? {
        var best: Double?
        for bp in boundaries {
            for q in bp.pieces {
                for r in CurveMath.intersect(piece, q, extA: true, extB: false) {
                    var t: Double
                    if piece.isArc {
                        let phi = (r.p - piece.center).angle, sw = abs(piece.sweep), sg = piece.sweep >= 0 ? 1.0 : -1.0
                        let endAng = piece.a0 + piece.sweep
                        let delta = atEnd ? (sg > 0 ? normAngle(phi - endAng) : normAngle(endAng - phi))
                                          : (sg > 0 ? normAngle(piece.a0 - phi) : normAngle(phi - piece.a0))
                        guard delta > 1e-9, delta < 2 * .pi - sw - 1e-9 else { continue }
                        t = atEnd ? 1 + delta / sw : -delta / sw
                    } else {
                        t = r.ta
                        if atEnd { guard t > 1 + piece.paramEps else { continue } } else { guard t < -piece.paramEps else { continue } }
                    }
                    if let b = best { if atEnd ? t < b : t > b { best = t } } else { best = t }
                }
            }
        }
        return best
    }

    /// Extends the end of `g` nearest to `pick` to the nearest boundary along the curve.
    public static func extend(_ g: Geometry, at pick: Vec2, boundaries: [Geometry], doc: ArchiDocument?) -> Geometry? {
        let bpaths = boundaries.filter { $0 != g }.flatMap { CurvePath.all($0, doc: doc) }
        guard !bpaths.isEmpty else { return nil }
        switch g {
        case .line(let l):
            let pc = CurvePiece(seg: l.a, l.b)
            guard !pc.isDegenerate else { return nil }
            let atEnd = pc.param(pick) >= 0.5
            guard let t = extendParam(pc, atEnd: atEnd, boundaries: bpaths) else { return nil }
            return atEnd ? .line(LineGeom(l.a, pc.point(t))) : .line(LineGeom(pc.point(t), l.b))
        case .arc(let a):
            let pc = CurvePiece(arc: a.center, a.radius, a.start, a.sweep)
            let atEnd = pc.closestParam(pick) >= 0.5
            guard let t = extendParam(pc, atEnd: atEnd, boundaries: bpaths) else { return nil }
            let ang = normAngle(a.start + a.sweep * t)
            return atEnd ? .arc(ArcGeom(a.center, a.radius, a.start, ang)) : .arc(ArcGeom(a.center, a.radius, ang, a.end))
        case .polyline(var p) where !p.closed:
            guard let path = CurvePath.make(g) else { return nil }
            let atEnd = path.closest(pick).s >= path.count / 2
            let pc = atEnd ? path.pieces.last! : path.pieces.first!
            guard let t = extendParam(pc, atEnd: atEnd, boundaries: bpaths) else { return nil }
            let np = pc.point(t)
            if atEnd {
                let k = pc.tag + 1
                p.vertices.removeSubrange((k + 1)..<p.vertices.count)
                p.vertices[k].p = np
                if pc.isArc { p.vertices[pc.tag].bulge = tan(pc.sweep * t / 4) }
            } else {
                p.vertices.removeSubrange(0..<pc.tag)
                p.vertices[0].p = np
                if pc.isArc { p.vertices[0].bulge = tan(pc.sweep * (1 - t) / 4) }
            }
            return .polyline(p)
        case .ellipse(var e) where !e.isFull:
            guard let path = CurvePath.make(g) else { return nil }
            let atEnd = path.closest(pick).s >= path.count / 2
            let sweep = normAngle(e.end - e.start)
            let rest = 2 * .pi - sweep
            guard rest > 1e-9, let comp = CurvePath.ellipsePath(e, from: e.start + sweep, sweep: rest, closed: false) else { return nil }
            var ss: [Double] = []
            for bp in bpaths { for r in CurveMath.intersect(comp, bp) { ss.append(r.sa) } }
            let eps = 1e-9 * comp.count
            if atEnd {
                guard let s = ss.filter({ $0 > eps && $0 < comp.count - eps }).min() else { return nil }
                e.end = normAngle(comp.u(s))
            } else {
                guard let s = ss.filter({ $0 > eps && $0 < comp.count - eps }).max() else { return nil }
                e.start = normAngle(comp.u(s))
            }
            return .ellipse(e)
        case .spline(let s):
            return extendSpline(s, at: pick, boundaries: bpaths)
        default:
            return nil
        }
    }

    // MARK: Offset

    static func offsetPiece(_ p: CurvePiece, _ sd: Double) -> CurvePiece? {
        if p.isArc {
            let r = p.radius - (p.sweep >= 0 ? 1 : -1) * sd
            guard r > 1e-9 else { return nil }
            var q = CurvePiece(arc: p.center, r, p.a0, p.sweep); q.tag = p.tag
            return q
        }
        let n = (p.p1 - p.p0).normalized.perp * sd
        var q = CurvePiece(seg: p.p0 + n, p.p1 + n); q.tag = p.tag
        return q
    }

    /// Whether offsetting to the left of travel moves toward `side`.
    static func leftSide(_ path: CurvePath, _ side: Vec2) -> Bool {
        if path.closed {
            let poly = path.pieces.flatMap { pc -> [Vec2] in
                pc.isArc ? GeometryOps.arcPoints(center: pc.center, radius: pc.radius, start: pc.a0, sweep: pc.sweep).dropLast() : [pc.p0]
            }
            let inside = GeometryOps.pointInPolygon(side, poly)
            return inside == (GeometryOps.signedArea(poly) > 0)
        }
        let c = path.closest(side)
        return path.tangent(c.s).cross(side - c.point) > 0
    }

    /// Offsets `g` by `distance` toward the point `side` (lines, arcs, circles, polylines with bulges, ellipses and splines).
    public static func offset(_ g: Geometry, distance: Double, towards side: Vec2) -> Geometry? {
        let d = abs(distance)
        guard d > geomEpsilon else { return nil }
        switch g {
        case .line(let l):
            let dir = (l.b - l.a).normalized
            guard dir != .zero else { return nil }
            let n = dir.perp * (dir.cross(side - l.a) >= 0 ? d : -d)
            return .line(LineGeom(l.a + n, l.b + n))
        case .circle(let c):
            let r = side.distance(to: c.center) < c.radius ? c.radius - d : c.radius + d
            return r > geomEpsilon ? .circle(CircleGeom(c.center, r)) : nil
        case .arc(let a):
            let r = side.distance(to: a.center) < a.radius ? a.radius - d : a.radius + d
            return r > geomEpsilon ? .arc(ArcGeom(a.center, r, a.start, a.end)) : nil
        case .polyline(let p):
            return offsetPolyline(p, d, side)
        case .ellipse, .spline:
            guard let path = CurvePath.make(g) else { return nil }
            return offsetSampled(path, leftSide(path, side) ? d : -d)
        default:
            return nil
        }
    }

    static func offsetPolyline(_ pl: PolylineGeom, _ d: Double, _ side: Vec2) -> Geometry? {
        guard let path = CurvePath.make(.polyline(pl)) else { return nil }
        let sd = leftSide(path, side) ? d : -d
        var items: [(piece: CurvePiece, vEnd: Vec2)] = path.pieces.compactMap { p in offsetPiece(p, sd).map { ($0, p.p1) } }
        let tol = 1e-7 * Swift.max(1, d)
        for _ in 0..<(path.pieces.count + 2) {
            let m = items.count
            guard m > 0, !(path.closed && m < 2) else { return nil }
            var work = items.map(\.piece)
            var extra: [Int: CurvePiece] = [:]
            var bad: Int?
            let joins = path.closed ? m : m - 1
            for j in 0..<joins {
                let k = (j + 1) % m
                let P = work[j], Q = work[k]
                if P.p1.isClose(Q.p0, tol: tol) { work[k].p0 = P.p1; continue }
                let target = (P.p1 + Q.p0) / 2
                let xs = CurveMath.intersect(P, Q, extA: true, extB: true)
                if let x = xs.min(by: { $0.p.distance(to: target) < $1.p.distance(to: target) }) {
                    guard let np = P.withEnd(x.p) else { bad = j; break }
                    guard let nq = Q.withStart(x.p) else { bad = k; break }
                    work[j] = np; work[k] = nq
                } else {
                    // Round join around the original vertex.
                    let v = items[j].vEnd
                    let a0 = (P.p1 - v).angle
                    var sw = (Q.p0 - v).angle - a0
                    while sw > .pi { sw -= 2 * .pi }
                    while sw <= -.pi { sw += 2 * .pi }
                    var arc = CurvePiece(arc: v, P.p1.distance(to: v), a0, sw)
                    arc.p0 = P.p1; arc.p1 = Q.p0
                    extra[j] = arc
                }
            }
            if let b = bad { items.remove(at: b); continue }
            var verts: [PolyVertex] = []
            for j in 0..<m {
                verts.append(PolyVertex(work[j].p0, bulge: work[j].bulgeValue))
                if let e = extra[j] { verts.append(PolyVertex(e.p0, bulge: e.bulgeValue)) }
            }
            if !path.closed { verts.append(PolyVertex(work[m - 1].p1)) }
            var out = pl
            out.vertices = verts
            if path.closed {
                let a0 = GeometryOps.signedArea(GeometryOps.polylinePoints(pl.vertices, closed: true))
                let a1 = GeometryOps.signedArea(GeometryOps.polylinePoints(verts, closed: true))
                guard a0 * a1 > 0, abs(a1) > 1e-12 else { return nil }
            }
            return .polyline(out)
        }
        return nil
    }

    static func offsetSampled(_ path: CurvePath, _ sd: Double) -> Geometry? {
        guard let ev = path.eval, let f = path.pieces.first, let l = path.pieces.last else { return nil }
        let u0 = f.u0, u1 = l.u1
        let n = Swift.max(64, Swift.min(512, path.pieces.count))
        let h = (u1 - u0) * 1e-5
        var pts: [Vec2] = []
        let count = path.closed ? n : n + 1
        for i in 0..<count {
            let u = u0 + (u1 - u0) * Double(i) / Double(n)
            var ua = u - h, ub = u + h
            if !path.closed { ua = Swift.max(u0, ua); ub = Swift.min(u1, ub) }
            let t = (ev(ub) - ev(ua)).normalized
            pts.append(ev(u) + t.perp * sd)
        }
        return .spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: pts, closed: path.closed))
    }

    // MARK: Fillet / Chamfer

    /// Carrier curve for fillet: line → segment, arc → CCW arc, circle → full circle.
    static func carrier(_ g: Geometry) -> CurvePiece? {
        switch g {
        case .line(let l): return l.a.isClose(l.b, tol: 1e-12) ? nil : CurvePiece(seg: l.a, l.b)
        case .arc(let a): return a.radius > geomEpsilon ? CurvePiece(arc: a.center, a.radius, a.start, a.sweep) : nil
        case .circle(let c): return c.radius > geomEpsilon ? CurvePiece(arc: c.center, c.radius, 0, 2 * .pi) : nil
        default: return nil
        }
    }
    static func offsetCarriers(_ c: CurvePiece, _ r: Double) -> [CurvePiece] {
        if c.isArc {
            var out = [CurvePiece(arc: c.center, c.radius + r, 0, 2 * .pi)]
            if c.radius - r > 1e-9 { out.append(CurvePiece(arc: c.center, c.radius - r, 0, 2 * .pi)) }
            return out
        }
        let n = (c.p1 - c.p0).normalized.perp * r
        return [CurvePiece(seg: c.p0 + n, c.p1 + n), CurvePiece(seg: c.p0 - n, c.p1 - n)]
    }
    static func foot(_ c: CurvePiece, _ p: Vec2) -> Vec2? {
        if c.isArc {
            let d = p - c.center
            return d.length < 1e-12 ? nil : c.center + d.normalized * c.radius
        }
        return c.p0 + (c.p1 - c.p0) * c.param(p)
    }

    /// Trims/extends `g` so it ends at the tangent point `t`, keeping the part opposite to direction `u` (into the fillet).
    static func tangentTrim(_ g: Geometry, at t: Vec2, into u: Vec2) -> Geometry? {
        switch g {
        case .line(let l):
            let da = (l.a - t).dot(u), db = (l.b - t).dot(u)
            let tol = 1e-9 * Swift.max(1, l.a.distance(to: l.b))
            if da > db { return db < -tol ? .line(LineGeom(t, l.b)) : nil }
            return da < -tol ? .line(LineGeom(l.a, t)) : nil
        case .arc(let a):
            let phi = (t - a.center).angle
            let tau = Vec2.polar(1, phi).perp
            let r = tau.dot(u) > 0 ? ArcGeom(a.center, a.radius, a.start, phi) : ArcGeom(a.center, a.radius, phi, a.end)
            return normAngle(r.end - r.start) > 1e-9 ? .arc(r) : nil
        case .circle: return g
        default: return nil
        }
    }
    /// Trims/extends `g` to the corner point `x`, keeping the side containing `pick`.
    static func cornerTrim(_ g: Geometry, pick: Vec2, at x: Vec2) -> Geometry? {
        switch g {
        case .line(let l):
            let c = CurvePiece(seg: l.a, l.b)
            let tp = c.param(pick), tx = c.param(x)
            let r = tp < tx ? LineGeom(l.a, x) : LineGeom(x, l.b)
            return r.a.isClose(r.b, tol: 1e-9) ? nil : .line(r)
        case .arc(let a):
            let c = CurvePiece(arc: a.center, a.radius, a.start, a.sweep)
            let phi = (x - a.center).angle, tx = c.param(x)
            let r: ArcGeom
            if tx < 0 { r = ArcGeom(a.center, a.radius, phi, a.end) }
            else if tx > 1 { r = ArcGeom(a.center, a.radius, a.start, phi) }
            else { r = c.closestParam(pick) < tx ? ArcGeom(a.center, a.radius, a.start, phi) : ArcGeom(a.center, a.radius, phi, a.end) }
            return normAngle(r.end - r.start) > 1e-9 ? .arc(r) : nil
        case .circle: return g
        default: return nil
        }
    }

    /// Fillets two lines/arcs/circles (radius 0 = sharp corner), or two adjacent straight segments of one polyline.
    public static func fillet(_ a: Geometry, pickA: Vec2, _ b: Geometry, pickB: Vec2, radius: Double) -> FilletResult? {
        let r = Swift.max(0, radius)
        if a == b, case .polyline(let pl) = a {
            return polylineCorner(pl, pickA, pickB) { v, pa, pb, _ in
                guard r > geomEpsilon else { return [PolyVertex(v)] }
                let da = (pa - v).normalized, db = (pb - v).normalized
                let theta = acos(Swift.max(-1, Swift.min(1, da.dot(db))))
                guard theta > 1e-9, theta < .pi - 1e-9 else { return nil }
                let td = r / tan(theta / 2)
                guard td <= pa.distance(to: v) + 1e-9, td <= pb.distance(to: v) + 1e-9 else { return nil }
                let turn: Double = (v - pa).cross(pb - v) >= 0 ? 1 : -1
                return [PolyVertex(v + da * td, bulge: tan((.pi - theta) * turn / 4)), PolyVertex(v + db * td)]
            }
        }
        guard let ca = carrier(a), let cb = carrier(b) else { return filletCurves(a, pickA: pickA, b, pickB: pickB, radius: r) }
        if r < geomEpsilon {
            let xs = CurveMath.intersect(ca, cb, extA: true, extB: true)
            guard let x = xs.min(by: { $0.p.distance(to: pickA) + $0.p.distance(to: pickB) < $1.p.distance(to: pickA) + $1.p.distance(to: pickB) }),
                  let na = cornerTrim(a, pick: pickA, at: x.p), let nb = cornerTrim(b, pick: pickB, at: x.p) else { return nil }
            return FilletResult(first: na, second: nb, arc: nil)
        }
        var best: (c: Vec2, ta: Vec2, tb: Vec2, score: Double)?
        for oa in offsetCarriers(ca, r) {
            for ob in offsetCarriers(cb, r) {
                for x in CurveMath.intersect(oa, ob, extA: true, extB: true) {
                    guard let ta = foot(ca, x.p), let tb = foot(cb, x.p) else { continue }
                    let s = ta.distance(to: pickA) + tb.distance(to: pickB)
                    if best == nil || s < best!.score { best = (x.p, ta, tb, s) }
                }
            }
        }
        guard let f = best, !f.ta.isClose(f.tb, tol: 1e-9) else { return nil }
        let cr = (f.ta - f.c).cross(f.tb - f.c)
        let sg: Double = cr >= 0 ? 1 : -1
        let ua = (f.ta - f.c).normalized.perp * sg
        let ub = (f.tb - f.c).normalized.perp * -sg
        guard let na = tangentTrim(a, at: f.ta, into: ua), let nb = tangentTrim(b, at: f.tb, into: ub) else { return nil }
        let arc = sg > 0 ? ArcGeom(f.c, r, (f.ta - f.c).angle, (f.tb - f.c).angle) : ArcGeom(f.c, r, (f.tb - f.c).angle, (f.ta - f.c).angle)
        return FilletResult(first: na, second: nb, arc: .arc(arc))
    }

    /// Chamfers two lines (distances d1 on the first, d2 on the second), or two adjacent straight segments of one polyline.
    public static func chamfer(_ a: Geometry, pickA: Vec2, _ b: Geometry, pickB: Vec2, d1: Double, d2: Double) -> FilletResult? {
        let d1 = Swift.max(0, d1), d2 = Swift.max(0, d2)
        if a == b, case .polyline(let pl) = a {
            return polylineCorner(pl, pickA, pickB) { v, pa, pb, aFirst in
                let da = aFirst ? d1 : d2, db = aFirst ? d2 : d1
                if da < geomEpsilon && db < geomEpsilon { return [PolyVertex(v)] }
                guard da <= pa.distance(to: v) + 1e-9, db <= pb.distance(to: v) + 1e-9 else { return nil }
                return [PolyVertex(v + (pa - v).normalized * da), PolyVertex(v + (pb - v).normalized * db)]
            }
        }
        guard case .line(let la) = a, case .line(let lb) = b else { return chamferSegments(a, pickA: pickA, b, pickB: pickB, d1: d1, d2: d2) }
        guard let x = CurveMath.lineLine(la.a, la.b, lb.a, lb.b),
              let (na, ca) = chamferSide(la, pickA, x, d1), let (nb, cb) = chamferSide(lb, pickB, x, d2) else { return nil }
        let line: Geometry? = ca.isClose(cb, tol: 1e-9) ? nil : .line(LineGeom(ca, cb))
        return FilletResult(first: .line(na), second: .line(nb), arc: line)
    }

    static func chamferSide(_ l: LineGeom, _ pick: Vec2, _ x: Vec2, _ d: Double) -> (LineGeom, Vec2)? {
        let c = CurvePiece(seg: l.a, l.b)
        let dir = (l.b - l.a).normalized
        let tol = 1e-9 * Swift.max(1, c.length)
        if c.param(pick) >= c.param(x) {
            let p = x + dir * d
            guard (l.b - p).dot(dir) > tol else { return nil }
            return (LineGeom(p, l.b), p)
        }
        let p = x - dir * d
        guard (p - l.a).dot(dir) > tol else { return nil }
        return (LineGeom(l.a, p), p)
    }

    /// Replaces the shared vertex of two adjacent straight polyline segments picked at pickA/pickB.
    /// `make(vertex, prevPoint, nextPoint, pickAIsFirstSegment)` returns the replacement vertices.
    static func polylineCorner(_ pl: PolylineGeom, _ pickA: Vec2, _ pickB: Vec2,
                               make: (Vec2, Vec2, Vec2, Bool) -> [PolyVertex]?) -> FilletResult? {
        guard let path = CurvePath.make(.polyline(pl)) else { return nil }
        let ia = path.index(path.closest(pickA).s).0, ib = path.index(path.closest(pickB).s).0
        let pa = path.pieces[ia], pb = path.pieces[ib]
        guard ia != ib, !pa.isArc, !pb.isArc else { return nil }
        let m = pl.vertices.count
        let first: CurvePiece, second: CurvePiece, aFirst: Bool
        if (pa.tag + 1) % m == pb.tag { first = pa; second = pb; aFirst = true }
        else if (pb.tag + 1) % m == pa.tag { first = pb; second = pa; aFirst = false }
        else { return nil }
        let k = second.tag
        guard pl.closed || (k > 0 && k < m - 1), first.p1.isClose(pl.vertices[k].p, tol: 1e-9) else { return nil }
        guard var rep = make(pl.vertices[k].p, first.p0, second.p1, aFirst) else { return nil }
        rep[rep.count - 1].bulge = pl.vertices[k].bulge
        var out = pl
        out.vertices.replaceSubrange(k...k, with: rep)
        return FilletResult(first: .polyline(out), second: .polyline(out), arc: nil)
    }

    // MARK: Break / Join / Explode

    /// Breaks `g` between p1 and p2 (a single point when p1 == p2 splits the object).
    public static func breakAt(_ g: Geometry, _ p1: Vec2, _ p2: Vec2) -> [Geometry]? {
        guard let path = CurvePath.make(g) else { return nil }
        let n = path.count
        let s1 = path.closest(p1).s, s2 = path.closest(p2).s
        let eps = 1e-9 * Swift.max(1, n)
        let single = p1.isClose(p2, tol: 1e-9) || abs(s1 - s2) < eps
        if path.closed {
            if single {
                switch path.kind {
                case .polyline, .spline, .other:
                    let pcs = path.subPieces(s1, n) + path.subPieces(0, s1)
                    guard !pcs.isEmpty else { return nil }
                    if path.kind == .spline, let ev = path.eval {
                        var pts = [pcs[0].p0]; pts += pcs.map { ev($0.u1) }
                        return [.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: pts))]
                    }
                    var v = pcs.map { PolyVertex($0.p0, bulge: $0.bulgeValue) }
                    v.append(PolyVertex(pcs.last!.p1))
                    return [.polyline(PolylineGeom(v, closed: false, width: path.polyWidth))]
                default: return nil
                }
            }
            return path.geometry(s2, s1).map { [$0] }
        }
        if single {
            guard s1 > eps, s1 < n - eps, let a = path.geometry(0, s1), let b = path.geometry(s1, n) else { return nil }
            return [a, b]
        }
        let lo = Swift.min(s1, s2), hi = Swift.max(s1, s2)
        var out: [Geometry] = []
        if lo > eps, let a = path.geometry(0, lo) { out.append(a) }
        if hi < n - eps, let b = path.geometry(hi, n) { out.append(b) }
        return out
    }

    /// Joins lines, arcs and open polylines that share endpoints into polylines (collinear lines → line,
    /// co-circular arcs → arc/circle). Other geometries are returned unchanged.
    public static func join(_ gs: [Geometry]) -> [Geometry] {
        struct Chain { var pieces: [CurvePiece]; var sources: [Geometry]; var width: Double }
        var pending: [Chain] = []
        var others: [Geometry] = []
        var ext = BBox2.empty
        for g in gs {
            switch g {
            case .line, .arc:
                if let p = CurvePath.make(g) { pending.append(Chain(pieces: p.pieces, sources: [g], width: 0)); p.pieces.forEach { ext.add($0.bounds) } }
                else { others.append(g) }
            case .polyline(let pl) where !pl.closed:
                if let p = CurvePath.make(g) { pending.append(Chain(pieces: p.pieces, sources: [g], width: pl.width)); p.pieces.forEach { ext.add($0.bounds) } }
                else { others.append(g) }
            default: others.append(g)
            }
        }
        let tol = 1e-6 * Swift.max(1, ext.isEmpty ? 1 : Swift.max(ext.width, ext.height))
        var results: [Geometry] = []
        while !pending.isEmpty {
            var ch = pending.removeFirst()
            var changed = true
            while changed {
                changed = false
                let s = ch.pieces.first!.p0, e = ch.pieces.last!.p1
                if ch.pieces.count > 1 && s.isClose(e, tol: tol) { break }
                for i in pending.indices {
                    let o = pending[i]
                    let os = o.pieces.first!.p0, oe = o.pieces.last!.p1
                    if os.isClose(e, tol: tol) { ch.pieces += o.pieces }
                    else if oe.isClose(e, tol: tol) { ch.pieces += o.pieces.reversed().map(\.reversed) }
                    else if oe.isClose(s, tol: tol) { ch.pieces = o.pieces + ch.pieces }
                    else if os.isClose(s, tol: tol) { ch.pieces = o.pieces.reversed().map(\.reversed) + ch.pieces }
                    else { continue }
                    ch.sources += o.sources; ch.width = Swift.max(ch.width, o.width)
                    pending.remove(at: i); changed = true
                    break
                }
            }
            if ch.sources.count == 1 { results.append(ch.sources[0]); continue }
            let s = ch.pieces.first!.p0, e = ch.pieces.last!.p1
            let closed = s.isClose(e, tol: tol)
            let pcs = ch.pieces
            if !closed && pcs.allSatisfy({ !$0.isArc }) {
                let dir = (e - s).normalized
                if dir != .zero && pcs.allSatisfy({ abs(dir.cross($0.p1 - $0.p0)) <= tol && dir.dot($0.p1 - $0.p0) > 0 }) {
                    results.append(.line(LineGeom(s, e))); continue
                }
            }
            if let f = pcs.first, f.isArc,
               pcs.allSatisfy({ $0.isArc && $0.center.isClose(f.center, tol: tol) && abs($0.radius - f.radius) <= tol && ($0.sweep >= 0) == (f.sweep >= 0) }) {
                let total = pcs.reduce(0) { $0 + $1.sweep }
                if closed && abs(abs(total) - 2 * .pi) < 1e-6 { results.append(.circle(CircleGeom(f.center, f.radius))); continue }
                if !closed && abs(total) < 2 * .pi {
                    results.append(CurvePiece(arc: f.center, f.radius, f.a0, total).geometry); continue
                }
            }
            var v = pcs.map { PolyVertex($0.p0, bulge: $0.bulgeValue) }
            if !closed { v.append(PolyVertex(e)) }
            results.append(.polyline(PolylineGeom(v, closed: closed, width: ch.width)))
        }
        return results + others
    }

    /// Explodes compound geometry into simpler pieces; nil when `g` cannot be exploded.
    public static func explode(_ g: Geometry, doc: ArchiDocument) -> [Geometry]? {
        switch g {
        case .polyline:
            guard let p = CurvePath.make(g) else { return nil }
            return p.pieces.map(\.geometry)
        case .insert(let ins):
            guard let b = doc.blocks[ins.block] else { return nil }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            return b.entities.map { GeometryTransform.apply($0.geometry, t) }
        case .hatch(let h):
            return h.loops.filter { $0.count >= 2 }.map { .polyline(PolylineGeom($0, closed: true)) }
        case .dimension(let d):
            let pr = DimensionRenderer.primitives(d, style: doc.dimStyle(d.style))
            var out: [Geometry] = []
            for l in pr.lines where l.count >= 2 {
                out.append(l.count == 2 ? .line(LineGeom(l[0], l[1])) : .polyline(PolylineGeom(points: l)))
            }
            for a in pr.arrows where a.count >= 2 {
                out.append(a.count >= 3 ? .hatch(HatchGeom(loops: [a.map { PolyVertex($0) }])) : .line(LineGeom(a[0], a[1])))
            }
            if let t = pr.text { out.append(.text(t)) }
            return out
        case .leader(let l):
            var out: [Geometry] = []
            for i in 0..<Swift.max(0, l.points.count - 1) where !l.points[i].isClose(l.points[i + 1], tol: 1e-12) {
                out.append(.line(LineGeom(l.points[i], l.points[i + 1])))
            }
            if !l.text.isEmpty, let last = l.points.last {
                let prev = l.points.count > 1 ? l.points[l.points.count - 2] : last - Vec2(1, 0)
                let right = last.x >= prev.x
                out.append(.text(TextGeom(position: last + Vec2(right ? l.textHeight * 0.5 : -l.textHeight * 0.5, 0), height: l.textHeight,
                                          content: l.text, halign: right ? .left : .right, valign: .middle)))
            }
            return out
        case .table(let tb):
            let w = tb.columnWidths.reduce(0, +), rows = tb.cells.count, h = tb.rowHeight * Double(rows)
            let o = tb.origin
            var out: [Geometry] = []
            for i in 0...rows { let y = o.y - Double(i) * tb.rowHeight; out.append(.line(LineGeom(Vec2(o.x, y), Vec2(o.x + w, y)))) }
            var x = o.x
            out.append(.line(LineGeom(Vec2(x, o.y), Vec2(x, o.y - h))))
            for cw in tb.columnWidths { x += cw; out.append(.line(LineGeom(Vec2(x, o.y), Vec2(x, o.y - h)))) }
            for (r, row) in tb.cells.enumerated() {
                var cx = o.x
                for (c, text) in row.enumerated() where c < tb.columnWidths.count {
                    let cw = tb.columnWidths[c]
                    if !text.isEmpty {
                        out.append(.text(TextGeom(position: Vec2(cx + cw / 2, o.y - (Double(r) + 0.5) * tb.rowHeight), height: tb.textHeight,
                                                  content: text, halign: .center, valign: .middle)))
                    }
                    cx += cw
                }
            }
            return out
        default:
            return nil
        }
    }

    // MARK: Stretch / Lengthen

    /// Moves the defining points of `g` that lie inside `window` by `delta` (whole object if its defining point is inside).
    public static func stretch(_ g: Geometry, window: BBox2, by delta: Vec2) -> Geometry {
        func mv(_ p: Vec2) -> Vec2 { window.contains(p) ? p + delta : p }
        switch g {
        case .line(let l): return .line(LineGeom(mv(l.a), mv(l.b)))
        case .arc(let a):
            let s = a.startPoint, e = a.endPoint
            let si = window.contains(s), ei = window.contains(e)
            if si && ei { return GeometryOps.transform(g, .translation(delta)) }
            if !si && !ei { return window.contains(a.center) ? GeometryOps.transform(g, .translation(delta)) : g }
            let ns = mv(s), ne = mv(e)
            guard !ns.isClose(ne, tol: 1e-9) else { return g }
            let pc = CurvePiece.bulge(ns, ne, tan(a.sweep / 4))
            return pc.geometry
        case .polyline(var p): p.vertices = p.vertices.map { PolyVertex(mv($0.p), bulge: $0.bulge) }; return .polyline(p)
        case .spline(var s): s.controlPoints = s.controlPoints.map(mv); s.fitPoints = s.fitPoints.map(mv); return .spline(s)
        case .dimension(var d): d.points = d.points.map(mv); return .dimension(d)
        case .hatch(var h): h.loops = h.loops.map { $0.map { PolyVertex(mv($0.p), bulge: $0.bulge) } }; return .hatch(h)
        case .leader(var l): l.points = l.points.map(mv); return .leader(l)
        default:
            let key: Vec2
            switch g {
            case .point(let p): key = p
            case .circle(let c): key = c.center
            case .ellipse(let e): key = e.center
            case .text(let t): key = t.position
            case .insert(let i): key = i.position
            case .image(let im): key = im.origin
            case .table(let tb): key = tb.origin
            case .solid(let s): key = s.origin.xy
            default: return g
            }
            return window.contains(key) ? GeometryOps.transform(g, .translation(delta)) : g
        }
    }

    /// Lengthens (delta > 0) or shortens (delta < 0) `g` at the end nearest to `pick`, measured along the curve.
    public static func lengthen(_ g: Geometry, at pick: Vec2, delta: Double) -> Geometry? {
        guard let path = CurvePath.make(g), !path.closed else { return nil }
        let total = path.length
        let atEnd = path.closest(pick).s >= path.count / 2
        let newLen = total + delta
        guard newLen > 1e-9 else { return nil }
        if delta <= 0 {
            if path.kind == .spline || path.kind == .ellipse || path.kind == .polyline || path.kind == .line || path.kind == .arc {
                let s = path.param(atLength: atEnd ? newLen : -delta)
                return atEnd ? path.geometry(0, s) : path.geometry(s, path.count)
            }
            return nil
        }
        switch g {
        case .line(let l):
            let dir = (l.b - l.a).normalized
            return atEnd ? .line(LineGeom(l.a, l.a + dir * newLen)) : .line(LineGeom(l.b - dir * newLen, l.b))
        case .arc(let a):
            let d = delta / a.radius
            guard a.sweep + d < 2 * .pi - 1e-9 else { return nil }
            return atEnd ? .arc(ArcGeom(a.center, a.radius, a.start, normAngle(a.end + d))) : .arc(ArcGeom(a.center, a.radius, normAngle(a.start - d), a.end))
        case .polyline(var p):
            let pc = atEnd ? path.pieces.last! : path.pieces.first!
            let t: Double
            if pc.isArc {
                let extra = delta / (pc.radius * abs(pc.sweep))
                guard abs(pc.sweep) * (1 + extra) < 2 * .pi - 1e-9 else { return nil }
                t = atEnd ? 1 + extra : -extra
            } else { t = atEnd ? 1 + delta / pc.length : -delta / pc.length }
            if atEnd {
                let k = pc.tag + 1
                p.vertices.removeSubrange((k + 1)..<p.vertices.count)
                p.vertices[k].p = pc.point(t)
                if pc.isArc { p.vertices[pc.tag].bulge = tan(pc.sweep * t / 4) }
            } else {
                p.vertices.removeSubrange(0..<pc.tag)
                p.vertices[0].p = pc.point(t)
                if pc.isArc { p.vertices[0].bulge = tan(pc.sweep * (1 - t) / 4) }
            }
            return .polyline(p)
        default:
            return nil
        }
    }

    // MARK: Divide / Measure / Reverse / Closest point

    static func curvePath(_ g: Geometry, doc: ArchiDocument?) -> CurvePath? {
        if let p = CurvePath.make(g) { return p }
        let all = CurvePath.all(g, doc: doc)
        return all.count == 1 ? all[0] : nil
    }

    /// Points dividing the curve into `count` equal-length parts (closed curves: `count` points starting at the start).
    public static func divide(_ g: Geometry, count: Int, doc: ArchiDocument?) -> [Vec2] {
        guard count >= 2, let path = curvePath(g, doc: doc) else { return [] }
        let total = path.length
        guard total > 1e-12 else { return [] }
        let range = path.closed ? 0..<count : 1..<count
        return range.map { path.point(path.param(atLength: total * Double($0) / Double(count))) }
    }

    /// Points every `segmentLength` along the curve from its start.
    public static func measure(_ g: Geometry, segmentLength: Double, doc: ArchiDocument?) -> [Vec2] {
        guard segmentLength > 1e-12, let path = curvePath(g, doc: doc) else { return [] }
        let total = path.length
        var out: [Vec2] = []
        var l = segmentLength
        while l < total - 1e-9 && out.count < 100_000 {
            out.append(path.point(path.param(atLength: l)))
            l += segmentLength
        }
        return out
    }

    /// Reverses the direction of lines, polylines and splines (arcs/circles/ellipses are always CCW and are returned unchanged).
    public static func reverse(_ g: Geometry) -> Geometry {
        switch g {
        case .line(let l): return .line(LineGeom(l.b, l.a))
        case .polyline(var p):
            let v = p.vertices, n = v.count
            guard n > 1 else { return g }
            if p.closed {
                p.vertices = (0..<n).map { i in PolyVertex(v[(n - i) % n].p, bulge: -v[(n - i - 1 + n) % n].bulge) }
            } else {
                p.vertices = (0..<n).map { i in PolyVertex(v[n - 1 - i].p, bulge: i < n - 1 ? -v[n - 2 - i].bulge : 0) }
            }
            return .polyline(p)
        case .spline(var s):
            s.controlPoints.reverse(); s.fitPoints.reverse()
            if let w = s.weights { s.weights = w.reversed() }
            if let k0 = s.knots.first, let k1 = s.knots.last { s.knots = s.knots.reversed().map { k0 + k1 - $0 } }
            return .spline(s)
        case .leader(var l): l.points.reverse(); return .leader(l)
        default: return g
        }
    }

    /// Closest point on the geometry to `p`.
    public static func closestPoint(on g: Geometry, to p: Vec2, doc: ArchiDocument?) -> Vec2? {
        if case .point(let q) = g { return q }
        var best: (Vec2, Double)?
        for path in CurvePath.all(g, doc: doc) {
            let c = path.closest(p)
            if best == nil || c.dist < best!.1 { best = (c.point, c.dist) }
        }
        return best?.0
    }

    /// Point at a fraction (0…1) of the curve length.
    public static func point(on g: Geometry, atFraction f: Double, doc: ArchiDocument?) -> Vec2? {
        guard let path = curvePath(g, doc: doc) else { return nil }
        return path.point(path.param(atLength: path.length * Swift.max(0, Swift.min(1, f))))
    }

    /// Unit tangent (direction of travel) at the point of the curve nearest to `p`.
    public static func tangent(on g: Geometry, near p: Vec2, doc: ArchiDocument?) -> Vec2? {
        guard let path = curvePath(g, doc: doc) else { return nil }
        return path.tangent(path.closest(p).s)
    }
}
