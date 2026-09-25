// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum GeometryOps {
    /// Chord tolerance for curve tessellation, in drawing units.
    public static var chordTolerance = 0.5

    static func segments(radius: Double, sweep: Double) -> Int {
        guard radius > geomEpsilon else { return 1 }
        let tol = min(chordTolerance, radius * 0.5)
        let step = 2 * acos(max(-1, min(1, 1 - tol / radius)))
        return max(4, min(720, Int((abs(sweep) / max(step, 0.005)).rounded(.up))))
    }

    public static func arcPoints(center: Vec2, radius: Double, start: Double, sweep: Double) -> [Vec2] {
        let n = segments(radius: radius, sweep: sweep)
        return (0...n).map { center + Vec2.polar(radius, start + sweep * Double($0) / Double(n)) }
    }

    /// Arc through a bulge segment.
    public static func bulgeArc(_ a: Vec2, _ b: Vec2, _ bulge: Double) -> (center: Vec2, radius: Double, start: Double, sweep: Double) {
        let sweep = 4 * atan(bulge)
        let chord = a.distance(to: b)
        let r = chord / (2 * sin(abs(sweep) / 2))
        let mid = (a + b) / 2
        let h = r * cos(abs(sweep) / 2) // distance from chord midpoint to center
        let n = (b - a).normalized.perp
        let center = mid + n * (bulge > 0 ? h : -h) * (abs(sweep) > .pi ? -1 : 1)
        let start = (a - center).angle
        return (center, abs(r), start, sweep)
    }

    public static func polylinePoints(_ pl: PolylineGeom) -> [Vec2] {
        polylinePoints(pl.vertices, closed: pl.closed)
    }
    public static func polylinePoints(_ v: [PolyVertex], closed: Bool) -> [Vec2] {
        guard let first = v.first else { return [] }
        var out = [first.p]
        let count = closed ? v.count : v.count - 1
        guard count > 0 else { return out }
        for i in 0..<count {
            let a = v[i], b = v[(i + 1) % v.count]
            if abs(a.bulge) > 1e-9 {
                let arc = bulgeArc(a.p, b.p, a.bulge)
                out.append(contentsOf: arcPoints(center: arc.center, radius: arc.radius, start: arc.start, sweep: arc.sweep).dropFirst())
            } else { out.append(b.p) }
        }
        return out
    }

    /// Evaluates a B-spline/NURBS (or a Catmull-Rom interpolation through fit points if no control points).
    public static func splinePoints(_ s: SplineGeom, samplesPerSpan: Int = 16) -> [Vec2] {
        if s.controlPoints.count < 2 {
            return catmullRom(s.fitPoints, closed: s.closed, samples: samplesPerSpan)
        }
        let p = max(1, min(s.degree, s.controlPoints.count - 1))
        let n = s.controlPoints.count
        var knots = s.knots
        if knots.count != n + p + 1 {
            // Clamped uniform knot vector.
            knots = Array(repeating: 0, count: p + 1)
            let inner = n - p - 1
            if inner > 0 { for i in 1...inner { knots.append(Double(i) / Double(inner + 1)) } }
            knots += Array(repeating: 1, count: p + 1)
        }
        let w = s.weights ?? Array(repeating: 1, count: n)
        let t0 = knots[p], t1 = knots[n]
        let total = max(8, (n - p) * samplesPerSpan)
        var out: [Vec2] = []
        for i in 0...total {
            let t = t0 + (t1 - t0) * Double(i) / Double(total)
            out.append(deBoor(t: min(t, t1 - 1e-12 * (i == total ? 0 : 1)), p: p, knots: knots, ctrl: s.controlPoints, w: w))
        }
        if let last = s.controlPoints.last, s.knots.isEmpty || knots[n] == knots.last! { out[out.count - 1] = last }
        return out
    }

    static func deBoor(t: Double, p: Int, knots: [Double], ctrl: [Vec2], w: [Double]) -> Vec2 {
        let n = ctrl.count
        var k = p
        while k < n - 1 && t >= knots[k + 1] { k += 1 }
        var d: [(Vec2, Double)] = (0...p).map { j in
            let idx = j + k - p
            return (ctrl[idx] * w[idx], w[idx])
        }
        if p >= 1 {
            for r in 1...p {
                for j in stride(from: p, through: r, by: -1) {
                    let i = j + k - p
                    let denom = knots[i + p - r + 1] - knots[i]
                    let alpha = denom == 0 ? 0 : (t - knots[i]) / denom
                    d[j] = (d[j - 1].0 * (1 - alpha) + d[j].0 * alpha, d[j - 1].1 * (1 - alpha) + d[j].1 * alpha)
                }
            }
        }
        return d[p].0 / (d[p].1 == 0 ? 1 : d[p].1)
    }

    public static func catmullRom(_ pts: [Vec2], closed: Bool, samples: Int) -> [Vec2] {
        guard pts.count > 2 else { return pts }
        var out: [Vec2] = []
        let n = pts.count
        let segs = closed ? n : n - 1
        for i in 0..<segs {
            let p0 = pts[closed ? (i - 1 + n) % n : max(i - 1, 0)], p1 = pts[i]
            let p2 = pts[(i + 1) % n], p3 = pts[closed ? (i + 2) % n : min(i + 2, n - 1)]
            for s in 0..<samples {
                let t = Double(s) / Double(samples), t2 = t * t, t3 = t2 * t
                let a = p1 * 2
                let b = (p2 - p0) * t
                let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
                let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
                out.append((a + b + c + d) * 0.5)
            }
        }
        out.append(closed ? pts[0] : pts[n - 1])
        return out
    }

    public static func ellipsePoints(_ e: EllipseGeom) -> [Vec2] {
        var sweep = e.end - e.start
        if e.isFull { sweep = 2 * .pi } else { sweep = normAngle(sweep) }
        let n = segments(radius: e.majorAxis.length, sweep: sweep)
        return (0...n).map { e.point(at: e.start + sweep * Double($0) / Double(n)) }
    }

    /// Polylines approximating the curve parts of a geometry (text, hatch fill and solids excluded; blocks expanded).
    public static func tessellate(_ g: Geometry, doc: ArchiDocument?, depth: Int = 0) -> [[Vec2]] {
        switch g {
        case .point(let p): return [[p]]
        case .line(let l): return [[l.a, l.b]]
        case .circle(let c): return [arcPoints(center: c.center, radius: c.radius, start: 0, sweep: 2 * .pi)]
        case .arc(let a): return [arcPoints(center: a.center, radius: a.radius, start: a.start, sweep: a.sweep)]
        case .ellipse(let e): return [ellipsePoints(e)]
        case .polyline(let p): return [polylinePoints(p)]
        case .spline(let s): return [splinePoints(s)]
        case .hatch(let h): return h.loops.map { polylinePoints($0, closed: true) }
        case .leader(let l): return [l.points]
        case .text(let t): return [textBoxCorners(t) + [textBoxCorners(t)[0]]]
        case .dimension(let d): return [d.points]
        case .image(let im):
            let t = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
            return [[Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y), Vec2(0, 0)].map(t.apply)]
        case .table(let tb):
            let w = tb.columnWidths.reduce(0, +), h = tb.rowHeight * Double(tb.cells.count)
            let o = tb.origin
            return [[o, o + Vec2(w, 0), o + Vec2(w, -h), o + Vec2(0, -h), o]]
        case .solid(let s):
            return [solidFootprint(s)]
        case .insert(let ins):
            guard depth < 8, let doc = doc, let b = doc.blocks[ins.block] else { return [[ins.position]] }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            return b.entities.flatMap { tessellate($0.geometry, doc: doc, depth: depth + 1) }.map { $0.map(t.apply) }
        }
    }

    public static func solidFootprint(_ s: SolidGeom) -> [Vec2] {
        let o = s.origin.xy
        let rot = Transform2D.translation(o) * Transform2D.rotation(s.rotation)
        switch s.kind {
        case .box: return [Vec2(0, 0), Vec2(s.size.x, 0), Vec2(s.size.x, s.size.y), Vec2(0, s.size.y), Vec2(0, 0)].map(rot.apply)
        case .cylinder, .cone, .sphere: return arcPoints(center: o, radius: s.size.x, start: 0, sweep: 2 * .pi)
        case .extrusion, .revolve: return (s.profile + (s.profile.first.map { [$0] } ?? [])).map(rot.apply)
        case .mesh: return BBox2(points: s.meshVertices.map(\.xy)).corners
        }
    }

    /// Approximate text box (for picking/bounds) — width estimated at 0.6 × height per character.
    public static func textBoxCorners(_ t: TextGeom) -> [Vec2] {
        let lines = t.content.components(separatedBy: "\n")
        let longest = Double(lines.map(\.count).max() ?? 0)
        let w = t.width > 0 ? t.width : longest * t.height * 0.62
        let h = t.height * (1 + 1.5 * Double(lines.count - 1))
        var x0 = 0.0, y0 = 0.0
        switch t.halign { case .left: x0 = 0; case .center: x0 = -w / 2; case .right: x0 = -w }
        switch t.valign { case .baseline: y0 = -(h - t.height); case .bottom: y0 = -(h - t.height) - t.height * 0.2; case .middle: y0 = -h / 2 + (h - t.height) / 2 - (h - t.height); case .top: y0 = -h }
        if lines.count > 1 { y0 = t.valign == .top ? -h : y0 }
        let tr = Transform2D.translation(t.position) * Transform2D.rotation(t.rotation)
        return [Vec2(x0, y0), Vec2(x0 + w, y0), Vec2(x0 + w, y0 + h), Vec2(x0, y0 + h)].map(tr.apply)
    }

    public static func bounds(_ g: Geometry, doc: ArchiDocument?) -> BBox2 {
        switch g {
        case .circle(let c): return BBox2(min: c.center - Vec2(c.radius, c.radius), max: c.center + Vec2(c.radius, c.radius))
        case .dimension(let d): return BBox2(points: d.points)
        default:
            var b = BBox2.empty
            for pl in tessellate(g, doc: doc) { for p in pl { b.add(p) } }
            return b
        }
    }

    public static func bounds(of doc: ArchiDocument, includeElements: Bool = true) -> BBox2 {
        var b = BBox2.empty
        for e in doc.entities where doc.isVisible(layer: e.layer) { b.add(bounds(e.geometry, doc: doc)) }
        if includeElements { for el in doc.elements where doc.isVisible(layer: el.layer) { b.add(PlanRepresentation.bounds(el, doc: doc)) } }
        return b
    }

    public static func distance(point p: Vec2, segA a: Vec2, segB b: Vec2) -> Double {
        let ab = b - a
        let l2 = ab.lengthSquared
        if l2 < geomEpsilon { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return p.distance(to: a + ab * t)
    }
    public static func closestOnSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Vec2 {
        let ab = b - a; let l2 = ab.lengthSquared
        if l2 < geomEpsilon { return a }
        return a + ab * max(0, min(1, (p - a).dot(ab) / l2))
    }

    public static func distance(from p: Vec2, toPolyline pts: [Vec2]) -> Double {
        if pts.count == 1 { return p.distance(to: pts[0]) }
        var best = Double.infinity
        for i in 0..<max(0, pts.count - 1) { best = min(best, distance(point: p, segA: pts[i], segB: pts[i + 1])) }
        return best
    }

    public static func distance(from p: Vec2, to g: Geometry, doc: ArchiDocument?) -> Double {
        switch g {
        case .circle(let c): return abs(p.distance(to: c.center) - c.radius)
        case .text(let t):
            let box = textBoxCorners(t)
            if pointInPolygon(p, box) { return 0 }
            return distance(from: p, toPolyline: box + [box[0]])
        case .hatch(let h):
            let loops = h.loops.map { polylinePoints($0, closed: true) }
            var inside = false
            for l in loops where pointInPolygon(p, l) { inside.toggle() }
            if inside { return 0 }
            return loops.map { distance(from: p, toPolyline: $0) }.min() ?? .infinity
        case .dimension(let d):
            let prims = DimensionRenderer.primitives(d, style: doc?.dimStyle(d.style) ?? DimStyle(name: "Standard"))
            return prims.lines.map { distance(from: p, toPolyline: $0) }.min() ?? .infinity
        default:
            return tessellate(g, doc: doc).map { distance(from: p, toPolyline: $0) }.min() ?? .infinity
        }
    }

    /// Whether the geometry has a part inside the box (for crossing selection).
    public static func crosses(_ g: Geometry, box: BBox2, doc: ArchiDocument?) -> Bool {
        for pl in tessellate(g, doc: doc) {
            for p in pl where box.contains(p) { return true }
            if pl.count > 1 { for i in 0..<(pl.count - 1) where segmentIntersectsBox(pl[i], pl[i + 1], box) { return true } }
        }
        return false
    }

    public static func segmentIntersectsBox(_ a: Vec2, _ b: Vec2, _ box: BBox2) -> Bool {
        if box.contains(a) || box.contains(b) { return true }
        let c = box.corners
        for i in 0..<4 where segmentIntersection(a, b, c[i], c[(i + 1) % 4]) != nil { return true }
        return false
    }

    public static func segmentIntersection(_ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ p4: Vec2) -> Vec2? {
        let d1 = p2 - p1, d2 = p4 - p3
        let den = d1.cross(d2)
        if abs(den) < 1e-12 { return nil }
        let t = (p3 - p1).cross(d2) / den, u = (p3 - p1).cross(d1) / den
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        return p1 + d1 * t
    }

    /// Infinite line intersection.
    public static func lineIntersection(_ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ p4: Vec2) -> Vec2? {
        let d1 = p2 - p1, d2 = p4 - p3
        let den = d1.cross(d2)
        if abs(den) < 1e-12 { return nil }
        let t = (p3 - p1).cross(d2) / den
        return p1 + d1 * t
    }

    public static func pointInPolygon(_ p: Vec2, _ poly: [Vec2]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Signed area (positive = counter-clockwise).
    public static func signedArea(_ poly: [Vec2]) -> Double {
        guard poly.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<poly.count { a += poly[i].cross(poly[(i + 1) % poly.count]) }
        return a / 2
    }
    public static func centroid(_ poly: [Vec2]) -> Vec2 {
        let a = signedArea(poly)
        guard abs(a) > geomEpsilon else { return poly.reduce(.zero, +) / Double(max(poly.count, 1)) }
        var c = Vec2.zero
        for i in 0..<poly.count { let p = poly[i], q = poly[(i + 1) % poly.count]; c += (p + q) * p.cross(q) }
        return c / (6 * a)
    }
    public static func length(_ g: Geometry, doc: ArchiDocument?) -> Double {
        switch g {
        case .circle(let c): return 2 * .pi * c.radius
        case .arc(let a): return a.radius * a.sweep
        default:
            return tessellate(g, doc: doc).reduce(0) { acc, pl in
                acc + zip(pl, pl.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            }
        }
    }
    /// Area enclosed by a closed geometry (circle, ellipse, closed polyline, hatch).
    public static func area(_ g: Geometry, doc: ArchiDocument?) -> Double? {
        switch g {
        case .circle(let c): return .pi * c.radius * c.radius
        case .ellipse(let e) where e.isFull: return .pi * e.majorAxis.length * e.majorAxis.length * e.ratio
        case .polyline(let p) where p.closed: return abs(signedArea(polylinePoints(p)))
        case .spline(let s) where s.closed: return abs(signedArea(splinePoints(s)))
        case .hatch(let h):
            let loops = h.loops.map { abs(signedArea(polylinePoints($0, closed: true))) }.sorted(by: >)
            guard let outer = loops.first else { return nil }
            return outer - loops.dropFirst().reduce(0, +)
        default: return nil
        }
    }

    // MARK: Transform
    public static func transform(_ g: Geometry, _ t: Transform2D) -> Geometry {
        let s = t.scaleFactor, rot = t.rotationAngle, mirror = t.isMirroring
        func tv(_ v: [PolyVertex]) -> [PolyVertex] { v.map { PolyVertex(t.apply($0.p), bulge: mirror ? -$0.bulge : $0.bulge) } }
        switch g {
        case .point(let p): return .point(t.apply(p))
        case .line(let l): return .line(LineGeom(t.apply(l.a), t.apply(l.b)))
        case .circle(let c): return .circle(CircleGeom(t.apply(c.center), c.radius * s))
        case .arc(let a):
            if mirror {
                let sp = t.apply(a.endPoint), ep = t.apply(a.startPoint), c = t.apply(a.center)
                return .arc(ArcGeom(c, a.radius * s, (sp - c).angle, (ep - c).angle))
            }
            return .arc(ArcGeom(t.apply(a.center), a.radius * s, a.start + rot, a.end + rot))
        case .ellipse(var e):
            let c = t.apply(e.center)
            let major = t.applyVector(e.majorAxis)
            if mirror && !e.isFull {
                let sp = t.apply(e.point(at: e.end)), ep = t.apply(e.point(at: e.start))
                e.center = c; e.majorAxis = major
                e.start = ellipseParam(e, sp); e.end = ellipseParam(e, ep)
            } else { e.center = c; e.majorAxis = major }
            return .ellipse(e)
        case .polyline(var p): p.vertices = tv(p.vertices); p.width *= s; return .polyline(p)
        case .spline(var sp): sp.controlPoints = sp.controlPoints.map(t.apply); sp.fitPoints = sp.fitPoints.map(t.apply); return .spline(sp)
        case .text(var tx):
            tx.position = t.apply(tx.position); tx.height *= s; tx.width *= s
            var dir = normAngle(t.applyVector(Vec2.polar(1, tx.rotation)).angle)
            if mirror && dir > .pi / 2 + 1e-9 && dir <= 3 * .pi / 2 + 1e-9 { dir = normAngle(dir - .pi) } // keep text readable (MIRRTEXT 0)
            tx.rotation = dir
            return .text(tx)
        case .dimension(var d):
            d.points = d.points.map(t.apply)
            if let r = d.rotation { d.rotation = r + rot }
            return .dimension(d)
        case .hatch(var h): h.loops = h.loops.map(tv); h.scale *= s; h.angle += rot; return .hatch(h)
        case .insert(var i):
            i.position = t.apply(i.position); i.rotation += rot
            i.scale = Vec2(i.scale.x * s * (mirror ? -1 : 1), i.scale.y * s)
            return .insert(i)
        case .leader(var l): l.points = l.points.map(t.apply); l.textHeight *= s; return .leader(l)
        case .image(var im): im.origin = t.apply(im.origin); im.size = im.size * s; im.rotation += rot; return .image(im)
        case .table(var tb): tb.origin = t.apply(tb.origin); tb.columnWidths = tb.columnWidths.map { $0 * s }; tb.rowHeight *= s; tb.textHeight *= s; return .table(tb)
        case .solid(var so):
            let o = t.apply(so.origin.xy); so.origin = Vec3(o.x, o.y, so.origin.z * s); so.size = so.size * s
            so.profile = so.profile.map { $0 * s }; so.rotation += rot
            so.meshVertices = so.meshVertices.map { let q = t.apply($0.xy); return Vec3(q.x, q.y, $0.z * s) }
            if so.kind == .extrusion { so.height *= s }
            return .solid(so)
        }
    }

    static func ellipseParam(_ e: EllipseGeom, _ p: Vec2) -> Double {
        let local = p - e.center
        let u = e.majorAxis.normalized
        let x = local.dot(u) / e.majorAxis.length
        let y = local.dot(u.perp) / (e.majorAxis.length * e.ratio)
        return normAngle(atan2(y, x))
    }

    /// Characteristic points used for grips and endpoint/midpoint snaps.
    public static func grips(_ g: Geometry) -> [Vec2] {
        switch g {
        case .point(let p): return [p]
        case .line(let l): return [l.a, (l.a + l.b) / 2, l.b]
        case .circle(let c): return [c.center] + (0..<4).map { c.center + Vec2.polar(c.radius, Double($0) * .pi / 2) }
        case .arc(let a): return [a.startPoint, a.midPoint, a.endPoint, a.center]
        case .ellipse(let e): return [e.center, e.center + e.majorAxis, e.center - e.majorAxis, e.center + e.majorAxis.perp * e.ratio, e.center - e.majorAxis.perp * e.ratio]
        case .polyline(let p): return p.vertices.map(\.p)
        case .spline(let s): return s.fitPoints.isEmpty ? s.controlPoints : s.fitPoints
        case .text(let t): return [t.position]
        case .dimension(let d): return d.points
        case .hatch: return []
        case .insert(let i): return [i.position]
        case .leader(let l): return l.points
        case .image(let im): return [im.origin]
        case .table(let tb): return [tb.origin]
        case .solid(let s): return [s.origin.xy]
        }
    }
}

extension BBox2 {
    public var corners: [Vec2] { [min, Vec2(max.x, min.y), max, Vec2(min.x, max.y)] }
}
