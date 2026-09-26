// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Props that follow transforms

/// Entity props holding coordinates or directions, kept in step when objects are moved, rotated, scaled or mirrored.
public enum DraftProps {
    public static func point(_ s: String?) -> Vec2? {
        guard let s = s else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return p.count == 2 ? Vec2(p[0], p[1]) : nil
    }
    public static func text(_ p: Vec2) -> String { "\(fmt(p.x, 9)),\(fmt(p.y, 9))" }

    public static func transform(_ props: inout [String: String], _ t: Transform2D) {
        if let o = point(props[DraftRendering.hatchOriginProp]) { props[DraftRendering.hatchOriginProp] = text(t.apply(o)) }
        if let a = props[DraftRendering.gradientAngleProp].flatMap(Double.init) {
            let v = t.applyVector(Vec2.polar(1, rad(a)))
            if v.lengthSquared > 0 { props[DraftRendering.gradientAngleProp] = fmt(deg(normAngle(v.angle)), 9) }
        }
    }
}

// MARK: - Revision symbols

public enum RevisionSymbols {
    /// Revision delta: an equilateral triangle (apex up, rotated by `angle`) with the revision number centred inside.
    public static func triangle(center c: Vec2, size: Double, label: String, angle: Double = 0) -> [Geometry] {
        guard size > 0 else { return [] }
        let r = size / 3.0.squareRoot()              // circumradius of a triangle with side `size`
        let pts = (0..<3).map { c + Vec2.polar(r, angle + .pi / 2 + Double($0) * 2 * .pi / 3) }
        // The centroid is the circumcentre; text sits slightly below it (the triangle is wider at the bottom).
        let tpos = c + Vec2.polar(r * 0.1, angle - .pi / 2)
        return [.polyline(PolylineGeom(points: pts, closed: true)),
                .text(TextGeom(position: tpos, height: size * 0.32, content: label, rotation: angle, halign: .center, valign: .middle))]
    }

    public static let header = ["REV", "DATE", "BY", "DESCRIPTION"]

    /// A revision schedule table (header row + one row per revision).
    public static func table(origin: Vec2, textHeight: Double, rows: [[String]]) -> TableGeom {
        let th = textHeight > 0 ? textHeight : 2.5
        let widths = [th * 4, th * 8, th * 4, th * 20]
        return TableGeom(origin: origin, columnWidths: widths, rowHeight: th * 2, cells: [header] + rows.map { r in (0..<4).map { $0 < r.count ? r[$0] : "" } }, textHeight: th)
    }

    /// Next revision label after the given one: numbers count up, letters go A…Z, AA…
    public static func next(after s: String?) -> String {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return "1" }
        if let n = Int(s) { return "\(n + 1)" }
        let up = s.uppercased()
        guard up.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return s + "1" }
        var chars = Array(up)
        var i = chars.count - 1
        while i >= 0 {
            if chars[i] == "Z" { chars[i] = "A"; i -= 1 } else { chars[i] = Character(UnicodeScalar(chars[i].unicodeScalars.first!.value + 1)!); return String(chars) }
        }
        return "A" + String(chars)
    }
}

// MARK: - FLATTEN

public enum Flatten {
    /// Props that give an object height or elevation.
    public static let zProps = ["elevation", "z", "vertexZ", "thickness", "z1", "z2"]

    /// 2D replacement of a geometry: solids become their plan outline (closed polylines / edges); everything else is kept.
    public static func flatten(_ g: Geometry) -> [Geometry] {
        guard case .solid(let s) = g else { return [g] }
        if s.kind == .mesh && !s.meshTriangles.isEmpty {
            let edges = MeshTools.planEdges(vertices: s.meshVertices, triangles: s.meshTriangles)
            return edges.filter { $0.count >= 2 }.map { .polyline(PolylineGeom(points: $0)) }
        }
        var fp = GeometryOps.solidFootprint(s)
        guard fp.count >= 2 else { return [] }
        let closed = fp.count > 2 && fp.first!.isClose(fp.last!, tol: 1e-9)
        if closed { fp.removeLast() }
        if s.kind == .cylinder || s.kind == .cone || s.kind == .sphere {
            return [.circle(CircleGeom(Vec2(s.origin.x, s.origin.y), max(s.size.x, s.kind == .cone ? s.size.y : 0)))]
        }
        return [.polyline(PolylineGeom(points: fp, closed: closed || fp.count > 2))]
    }

    /// Flattens entities in place (new pieces keep the source's properties). Returns the number of objects changed.
    @discardableResult
    public static func apply(_ ids: Set<EntityID>, _ doc: inout ArchiDocument) -> Int {
        var n = 0
        var out: [Entity] = []
        for e in doc.entities {
            guard ids.contains(e.id) else { out.append(e); continue }
            var base = e
            let hadZ = zProps.contains { base.props[$0] != nil }
            for k in zProps { base.props[k] = nil }
            let gs = flatten(e.geometry)
            let changed = hadZ || gs.count != 1 || gs.first != e.geometry
            if changed { n += 1 }
            guard !gs.isEmpty else { continue }
            var first = base; first.geometry = gs[0]; out.append(first)
            for g in gs.dropFirst() { var x = base; x.id = doc.allocateID(); x.geometry = g; out.append(x) }
        }
        doc.entities = out
        return n
    }
}

// MARK: - CHSPACE

public enum ChangeSpace {
    /// Model → paper transform of a viewport (paper mm).
    public static func toPaper(_ vp: Viewport) -> Transform2D {
        let s = vp.scale > 0 ? vp.scale : 1
        return Transform2D.translation(vp.origin + vp.size / 2) * Transform2D.scale(1 / s, 1 / s) * Transform2D.translation(-vp.viewCenter)
    }

    /// Moves model-space entities into a layout's paper space through a viewport, scaled so they look the same on the sheet.
    @discardableResult
    public static func modelToPaper(_ ids: Set<EntityID>, layout li: Int, viewport vi: Int, _ doc: inout ArchiDocument) -> Int {
        guard doc.layouts.indices.contains(li), doc.layouts[li].viewports.indices.contains(vi) else { return 0 }
        let t = toPaper(doc.layouts[li].viewports[vi])
        var moved: [Entity] = []
        for e in doc.entities where ids.contains(e.id) {
            var x = e; x.geometry = GeometryOps.transform(e.geometry, t); DraftProps.transform(&x.props, t); moved.append(x)
        }
        doc.entities.removeAll { ids.contains($0.id) }
        doc.layouts[li].entities += moved
        return moved.count
    }

    /// Moves paper-space entities of a layout into model space through a viewport.
    @discardableResult
    public static func paperToModel(_ ids: Set<EntityID>, layout li: Int, viewport vi: Int, _ doc: inout ArchiDocument) -> Int {
        guard doc.layouts.indices.contains(li), doc.layouts[li].viewports.indices.contains(vi) else { return 0 }
        let t = toPaper(doc.layouts[li].viewports[vi]).inverted
        let moved = doc.layouts[li].entities.filter { ids.contains($0.id) }
        doc.layouts[li].entities.removeAll { ids.contains($0.id) }
        for e in moved {
            var x = e; x.geometry = GeometryOps.transform(e.geometry, t); DraftProps.transform(&x.props, t)
            if doc.entity(x.id) != nil || x.id == 0 { x.id = doc.allocateID() }
            doc.entities.append(x)
        }
        return moved.count
    }

    /// Index of the viewport whose paper rectangle contains the model-space bounds of the objects best (largest overlap),
    /// falling back to the first viewport.
    public static func viewport(for box: BBox2, in layout: Layout) -> Int? {
        guard !layout.viewports.isEmpty else { return nil }
        var best: (Int, Double)? = nil
        for (i, vp) in layout.viewports.enumerated() {
            let s = vp.scale > 0 ? vp.scale : 1
            let half = vp.size / 2 * s
            let view = BBox2(min: vp.viewCenter - half, max: vp.viewCenter + half)
            let ox = max(0, min(view.max.x, box.max.x) - max(view.min.x, box.min.x))
            let oy = max(0, min(view.max.y, box.max.y) - max(view.min.y, box.min.y))
            let a = ox * oy + (view.contains(box.center) ? 1e-9 : 0)
            if a > (best?.1 ?? -1) { best = (i, a) }
        }
        return best?.0
    }
}

// MARK: - Splines (SPLINEDIT, BLEND, control vertices)

public enum SplineTools {
    /// Exact control-vertex form of a fit-point spline as drawn (uniform Catmull–Rom): piecewise cubic Bézier segments as a
    /// degree-3 B-spline with triple interior knots.
    public static func controlForm(_ s: SplineGeom) -> SplineGeom? {
        let pts = s.fitPoints
        guard s.controlPoints.count < 2, pts.count >= 2 else { return nil }
        let n = pts.count
        if n == 2 { return SplineGeom(degree: 1, controlPoints: pts, knots: [0, 0, 1, 1], fitPoints: [], closed: false) }
        let closed = s.closed
        let segs = closed ? n : n - 1
        var ctrl: [Vec2] = [pts[0]]
        for i in 0..<segs {
            let p0 = pts[closed ? (i - 1 + n) % n : max(i - 1, 0)], p1 = pts[i]
            let p2 = pts[(i + 1) % n], p3 = pts[closed ? (i + 2) % n : min(i + 2, n - 1)]
            ctrl.append(p1 + (p2 - p0) / 6)
            ctrl.append(p2 - (p3 - p1) / 6)
            ctrl.append(p2)
        }
        var knots = [0.0, 0, 0, 0]
        for k in 1..<segs { knots += [Double(k), Double(k), Double(k)] }
        knots += Array(repeating: Double(segs), count: 4)
        return SplineGeom(degree: 3, controlPoints: ctrl, knots: knots, fitPoints: [], closed: closed)
    }

    /// Point of a spline at parameter t in its knot range (control-vertex splines).
    public static func evaluate(_ s: SplineGeom, _ t: Double) -> Vec2? {
        let n = s.controlPoints.count
        guard n >= 2 else { return nil }
        let p = max(1, min(s.degree, n - 1))
        var knots = s.knots
        if knots.count != n + p + 1 {
            knots = Array(repeating: 0, count: p + 1)
            let inner = n - p - 1
            if inner > 0 { for i in 1...inner { knots.append(Double(i) / Double(inner + 1)) } }
            knots += Array(repeating: 1, count: p + 1)
        }
        let tt = min(max(t, knots[p]), knots[n])
        if tt >= knots[n] { return s.controlPoints[n - 1] }
        return GeometryOps.deBoor(t: tt, p: p, knots: knots, ctrl: s.controlPoints, w: s.weights ?? Array(repeating: 1, count: n))
    }

    /// Unit tangent leaving a curve at one of its ends (outward), and that end point.
    public static func endTangent(_ g: Geometry, atStart: Bool, doc: ArchiDocument?) -> (point: Vec2, dir: Vec2)? {
        switch g {
        case .line(let l):
            let d = (atStart ? l.a - l.b : l.b - l.a)
            return d.lengthSquared > 0 ? (atStart ? l.a : l.b, d.normalized) : nil
        case .arc(let a):
            // CCW arc: at the end the tangent points CCW; at the start (outward) it points CW.
            return atStart ? (a.startPoint, Vec2.polar(1, a.start - .pi / 2)) : (a.endPoint, Vec2.polar(1, a.end + .pi / 2))
        case .polyline(let p) where !p.closed && p.vertices.count >= 2:
            let v = p.vertices
            if atStart {
                let a = v[0], b = v[1]
                if abs(a.bulge) < 1e-12 { return (a.p, (a.p - b.p).normalized) }
                let arc = GeometryOps.bulgeArc(a.p, b.p, a.bulge)
                let ang = (a.p - arc.center).angle
                return (a.p, Vec2.polar(1, arc.sweep > 0 ? ang - .pi / 2 : ang + .pi / 2))
            } else {
                let a = v[v.count - 2], b = v[v.count - 1]
                if abs(a.bulge) < 1e-12 { return (b.p, (b.p - a.p).normalized) }
                let arc = GeometryOps.bulgeArc(a.p, b.p, a.bulge)
                let ang = (b.p - arc.center).angle
                return (b.p, Vec2.polar(1, arc.sweep > 0 ? ang + .pi / 2 : ang - .pi / 2))
            }
        case .spline(let s) where !s.closed:
            if s.controlPoints.count >= 2 {
                let c = s.controlPoints
                // Clamped B-spline: the end tangent is along the first/last control polygon leg.
                let d = atStart ? c[0] - c[1] : c[c.count - 1] - c[c.count - 2]
                return d.lengthSquared > 0 ? (atStart ? c[0] : c[c.count - 1], d.normalized) : nil
            }
            let f = s.fitPoints
            guard f.count >= 2 else { return nil }
            // Catmull–Rom with duplicated end points: end tangent = (p1 - p0)/2 direction.
            let d = atStart ? f[0] - f[1] : f[f.count - 1] - f[f.count - 2]
            return d.lengthSquared > 0 ? (atStart ? f[0] : f[f.count - 1], d.normalized) : nil
        default:
            guard let pl = GeometryOps.tessellate(g, doc: doc).first, pl.count >= 2 else { return nil }
            let d = atStart ? pl[0] - pl[1] : pl[pl.count - 1] - pl[pl.count - 2]
            return d.lengthSquared > 0 ? (atStart ? pl[0] : pl[pl.count - 1], d.normalized) : nil
        }
    }

    /// Tangent-continuous blend (cubic Bézier as a clamped B-spline) from point a leaving along ta to point b arriving
    /// against tb (both unit tangents point away from their curves). `smooth` uses a quintic with zero curvature change.
    public static func blend(_ a: Vec2, _ ta: Vec2, _ b: Vec2, _ tb: Vec2, smooth: Bool = false) -> SplineGeom {
        let d = a.distance(to: b)
        if smooth {
            let k = d / 5
            let c = [a, a + ta * k, a + ta * (2 * k), b + tb * (2 * k), b + tb * k, b]
            return SplineGeom(degree: 5, controlPoints: c, knots: Array(repeating: 0, count: 6) + Array(repeating: 1, count: 6))
        }
        let k = d / 3
        return SplineGeom(degree: 3, controlPoints: [a, a + ta * k, b + tb * k, b], knots: [0, 0, 0, 0, 1, 1, 1, 1])
    }

    /// Nearest end of a curve to a point: true = start.
    public static func nearestEndIsStart(_ g: Geometry, to p: Vec2, doc: ArchiDocument?) -> Bool {
        guard let s = endTangent(g, atStart: true, doc: doc), let e = endTangent(g, atStart: false, doc: doc) else { return true }
        return s.point.distance(to: p) <= e.point.distance(to: p)
    }

    /// Editable points (fit points, or control vertices) of a spline.
    public static func editPoints(_ s: SplineGeom) -> [Vec2] { s.controlPoints.count >= 2 ? s.controlPoints : s.fitPoints }
    public static func withEditPoints(_ s: SplineGeom, _ pts: [Vec2]) -> SplineGeom {
        var x = s
        if s.controlPoints.count >= 2 {
            x.controlPoints = pts
            x.knots = []           // re-derive a clamped uniform knot vector for the new count
            x.weights = s.weights.map { w in pts.indices.map { $0 < w.count ? w[$0] : 1 } }
            x.degree = min(s.degree, max(1, pts.count - 1))
        } else { x.fitPoints = pts }
        return x
    }
    /// Inserts a point between the two edit points closest to it (or at the nearer end).
    public static func addPoint(_ s: SplineGeom, _ p: Vec2) -> SplineGeom {
        var pts = editPoints(s)
        guard pts.count >= 2 else { return withEditPoints(s, pts + [p]) }
        var best = (0, Double.infinity)
        let segs = s.closed ? pts.count : pts.count - 1
        for i in 0..<segs {
            let d = GeometryOps.distance(point: p, segA: pts[i], segB: pts[(i + 1) % pts.count])
            if d < best.1 { best = (i, d) }
        }
        let i = best.0
        if !s.closed && i == 0 && (p - pts[0]).dot(pts[1] - pts[0]) < 0 { pts.insert(p, at: 0) }
        else if !s.closed && i == segs - 1 && (p - pts[pts.count - 1]).dot(pts[pts.count - 2] - pts[pts.count - 1]) < 0 { pts.append(p) }
        else { pts.insert(p, at: i + 1) }
        return withEditPoints(s, pts)
    }
    public static func nearestPoint(_ s: SplineGeom, _ p: Vec2) -> Int? {
        let pts = editPoints(s)
        return pts.indices.min { pts[$0].distance(to: p) < pts[$1].distance(to: p) }
    }
    public static func deletePoint(_ s: SplineGeom, at i: Int) -> SplineGeom? {
        var pts = editPoints(s)
        guard pts.indices.contains(i), pts.count > 2 else { return nil }
        pts.remove(at: i)
        return withEditPoints(s, pts)
    }
    public static func movePoint(_ s: SplineGeom, at i: Int, to p: Vec2) -> SplineGeom? {
        var pts = editPoints(s)
        guard pts.indices.contains(i) else { return nil }
        pts[i] = p
        return withEditPoints(s, pts)
    }
}

// MARK: - Polyline vertex editing (PEDIT Edit vertex, segment type)

public enum PolylineEdit {
    public static func segmentCount(_ p: PolylineGeom) -> Int { p.closed ? p.vertices.count : max(0, p.vertices.count - 1) }

    /// Index of the segment nearest to a point.
    public static func nearestSegment(_ p: PolylineGeom, to q: Vec2) -> Int? {
        let n = segmentCount(p)
        guard n > 0 else { return nil }
        var best: (Int, Double)? = nil
        for i in 0..<n {
            let a = p.vertices[i], b = p.vertices[(i + 1) % p.vertices.count]
            let pts = GeometryOps.polylinePoints([a, PolyVertex(b.p)], closed: false)
            let d = GeometryOps.distance(from: q, toPolyline: pts)
            if d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    /// Makes segment i straight (bulge 0) or an arc through `through`.
    public static func setSegment(_ p: PolylineGeom, _ i: Int, arcThrough through: Vec2?) -> PolylineGeom? {
        guard i >= 0, i < segmentCount(p) else { return nil }
        var x = p
        if let m = through {
            let a = p.vertices[i].p, b = p.vertices[(i + 1) % p.vertices.count].p
            guard abs((b - a).cross(m - a)) > 1e-12 else { return nil }
            x.vertices[i].bulge = CommandHelpers.bulge3(a, m, b)
        } else { x.vertices[i].bulge = 0 }
        return x
    }

    public static func moveVertex(_ p: PolylineGeom, _ i: Int, to q: Vec2) -> PolylineGeom? {
        guard p.vertices.indices.contains(i) else { return nil }
        var x = p; x.vertices[i].p = q; return x
    }

    /// Inserts a vertex after vertex i (the segment i is split; its arc becomes straight pieces).
    public static func insertAfter(_ p: PolylineGeom, _ i: Int, _ q: Vec2) -> PolylineGeom? {
        guard p.vertices.indices.contains(i), p.closed || i < p.vertices.count - 1 else { return nil }
        var x = p
        x.vertices[i].bulge = 0
        x.vertices.insert(PolyVertex(q), at: i + 1)
        return x
    }

    /// Straightens everything between vertices i and j (removes the vertices in between, one straight segment).
    public static func straighten(_ p: PolylineGeom, _ i: Int, _ j: Int) -> PolylineGeom? {
        let (a, b) = (min(i, j), max(i, j))
        guard a >= 0, b < p.vertices.count, a != b else { return nil }
        var x = p
        x.vertices.removeSubrange((a + 1)..<b)
        x.vertices[a].bulge = 0
        return x
    }

    /// Breaks the polyline between vertices i and j: an open polyline gives up to two pieces, a closed one gives one open piece.
    public static func breakBetween(_ p: PolylineGeom, _ i: Int, _ j: Int) -> [PolylineGeom] {
        let v = p.vertices
        guard v.indices.contains(i), v.indices.contains(j) else { return [p] }
        var (a, b) = (min(i, j), max(i, j))
        if p.closed {
            // Keep the path from b round to a.
            if a == b { var x = p; x.closed = false; x.vertices = Array(v[a...] + v[..<a]) + [PolyVertex(v[a].p)]; return [x] }
            var pts = Array(v[b...]) + Array(v[...a])
            pts[pts.count - 1].bulge = 0
            return [PolylineGeom(pts, closed: false, width: p.width)]
        }
        if a == b { if a == 0 || a == v.count - 1 { return [p] }; b = a }
        var out: [PolylineGeom] = []
        if a > 0 { var first = Array(v[...a]); first[first.count - 1].bulge = 0; out.append(PolylineGeom(first, closed: false, width: p.width)) }
        if b < v.count - 1 { out.append(PolylineGeom(Array(v[b...]), closed: false, width: p.width)) }
        if a == b { a = 0 }
        return out
    }

    /// Appends straight segments (and optional arc bulges) to the end (or start) of an open polyline.
    public static func append(_ p: PolylineGeom, points: [Vec2], atStart: Bool) -> PolylineGeom {
        guard !p.closed, !points.isEmpty else { return p }
        var x = p
        if atStart {
            x.vertices = points.reversed().map { PolyVertex($0) } + x.vertices
        } else {
            if !x.vertices.isEmpty { x.vertices[x.vertices.count - 1].bulge = 0 }
            x.vertices += points.map { PolyVertex($0) }
        }
        return x
    }
}

// MARK: - TXTEXP (letters)

public enum TextExplode {
    /// One single-character text object per visible character, positioned with the approximate glyph advances.
    public static func letters(_ t: TextGeom) -> [TextGeom] {
        let chars = Array(t.content.replacingOccurrences(of: "\\P", with: " ").replacingOccurrences(of: "\n", with: " "))
        guard !chars.isEmpty, t.height > 0 else { return [] }
        let widths = chars.map { ArcText.advance($0) * t.height }
        let total = widths.reduce(0, +)
        var x0: Double
        switch t.halign { case .left: x0 = 0; case .center: x0 = -total / 2; case .right: x0 = -total }
        let u = Vec2.polar(1, t.rotation)
        var out: [TextGeom] = []
        for (c, w) in zip(chars, widths) {
            if c != " " {
                var g = t
                g.content = String(c); g.width = 0; g.halign = .left
                g.position = t.position + u * x0
                out.append(g)
            }
            x0 += w
        }
        return out
    }
}

// MARK: - Dynamic blocks (stretch and array parameters)

/// Dynamic block parameters are listed in the variable "BDYNPARAMS:<block>" as
/// "name|kind|x0,y0,x1,y1|dx,dy|base" entries separated by ";" (kind = stretch: base = distance, window = stretch frame,
/// d = unit direction; kind = array: base = 1, window = objects to repeat, d = spacing vector).
/// A reference with values (prop "dynValues" = "Width=1200;Count=3") points at a generated variant block
/// "<block>$D<hash>" (prop "dynBase" = the base block), so display, export and snaps need no special handling.
public enum DynamicBlocks {
    public enum Kind: String { case stretch, array, constraint }
    public struct Param: Hashable {
        public var name: String; public var kind: Kind; public var window: BBox2; public var vector: Vec2; public var base: Double
        public init(name: String, kind: Kind, window: BBox2, vector: Vec2, base: Double) {
            self.name = name; self.kind = kind; self.window = window; self.vector = vector; self.base = base
        }
        var text: String {
            "\(name)|\(kind.rawValue)|\(fmt(window.min.x, 9)),\(fmt(window.min.y, 9)),\(fmt(window.max.x, 9)),\(fmt(window.max.y, 9))|\(fmt(vector.x, 9)),\(fmt(vector.y, 9))|\(fmt(base, 9))"
        }
    }
    public static let valuesProp = "dynValues", baseProp = "dynBase"
    public static func key(_ block: String) -> String { "BDYNPARAMS:" + block }

    public static func params(_ block: String, _ doc: ArchiDocument) -> [Param] {
        var out = storedParams(block, doc).filter { $0.kind != .constraint }
        // Named length constraints of a parametric block (BLK-027) are parameters too.
        for (n, v) in BlockConstraints.parameters(block, doc: doc) where !out.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) {
            out.append(Param(name: n, kind: .constraint, window: BBox2(points: [.zero]), vector: .zero, base: v))
        }
        return out
    }
    static func storedParams(_ block: String, _ doc: ArchiDocument) -> [Param] {
        (doc.variable(key(block)) ?? "").split(separator: ";").compactMap { s in
            let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5, let k = Kind(rawValue: f[1]), let b = Double(f[4]) else { return nil }
            let w = f[2].split(separator: ",").compactMap { Double($0) }, v = f[3].split(separator: ",").compactMap { Double($0) }
            guard w.count == 4, v.count == 2 else { return nil }
            return Param(name: f[0], kind: k, window: BBox2(points: [Vec2(w[0], w[1]), Vec2(w[2], w[3])]), vector: Vec2(v[0], v[1]), base: b)
        }
    }
    public static func setParams(_ block: String, _ ps0: [Param], _ doc: inout ArchiDocument) {
        let ps = ps0.filter { $0.kind != .constraint }
        if ps.isEmpty { doc.variables[key(block).uppercased()] = nil } else { doc.setVariable(key(block), ps.map(\.text).joined(separator: ";")) }
    }

    public static func values(_ props: [String: String]) -> [String: Double] {
        var out: [String: Double] = [:]
        for part in (props[valuesProp] ?? "").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, let v = Double(kv[1]) { out[kv[0]] = v }
        }
        return out
    }
    public static func valuesText(_ v: [String: Double]) -> String { v.keys.sorted().map { "\($0)=\(fmt(v[$0]!, 9))" }.joined(separator: ";") }

    /// The block's entities with parameter values applied (in parameter order; stretches first, then arrays).
    public static func entities(of b: Block, params: [Param], values: [String: Double], constraints: ConstraintSet? = nil) -> [Entity] {
        var ents = b.entities
        if let cs = constraints {
            let cv = values.filter { k, _ in params.contains { $0.kind == .constraint && $0.name == k } }
            if !cv.isEmpty { ents = BlockConstraints.solved(ents, set: cs, values: cv) }
        }
        for p in params where p.kind == .stretch {
            guard let v = values[p.name] else { continue }
            let dir = p.vector.lengthSquared > 0 ? p.vector.normalized : Vec2(1, 0)
            let d = dir * (v - p.base)
            guard d.lengthSquared > 0 else { continue }
            for i in ents.indices {
                let g = ents[i].geometry
                let bb = GeometryOps.bounds(g, doc: nil)
                if !bb.isEmpty && p.window.contains(bb) { ents[i].geometry = GeometryOps.transform(g, .translation(d)) }
                else { ents[i].geometry = Modify.stretch(g, window: p.window, by: d) }
            }
        }
        for p in params where p.kind == .array {
            guard let v = values[p.name] else { continue }
            let count = max(1, min(Int(v.rounded()), 1000))
            guard count > 1 else { continue }
            let src = ents.filter { let bb = GeometryOps.bounds($0.geometry, doc: nil); return !bb.isEmpty && p.window.contains(bb) }
            for k in 1..<count {
                let t = Transform2D.translation(p.vector * Double(k))
                for e in src { var c = e; c.geometry = GeometryOps.transform(e.geometry, t); ents.append(c) }
            }
        }
        return ents
    }

    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 36).uppercased()
    }
    public static func variantName(_ block: String, _ values: [String: Double]) -> String { block + "$D" + hash(valuesText(values)) }

    /// Applies parameter values to a reference (nil or all-default values = the base block).
    public static func apply(_ values: [String: Double]?, toInsert i: Int, _ doc: inout ArchiDocument) -> Bool {
        guard doc.entities.indices.contains(i), case .insert(var ins) = doc.entities[i].geometry else { return false }
        let block = doc.entities[i].props[baseProp] ?? ins.block
        guard let b = doc.blocks[block] else { return false }
        let ps = params(block, doc)
        var vals = values ?? [:]
        vals = vals.filter { k, v in ps.contains { $0.name == k && abs($0.base - v) > 1e-9 } }
        if vals.isEmpty {
            ins.block = block
            doc.entities[i].props[baseProp] = nil; doc.entities[i].props[valuesProp] = nil
        } else {
            let name = variantName(block, vals)
            if doc.blocks[name] == nil {
                doc.blocks[name] = Block(name: name, basePoint: b.basePoint, entities: entities(of: b, params: ps, values: vals, constraints: BlockConstraints.load(block, doc: doc)),
                                         description: "Dynamic variant of \(block): \(valuesText(vals))")
            }
            ins.block = name
            doc.entities[i].props[baseProp] = block; doc.entities[i].props[valuesProp] = valuesText(vals)
        }
        doc.entities[i].geometry = .insert(ins)
        return true
    }

    /// Rebuilds all variants of a block (after its definition or parameters changed).
    public static func regenerate(_ block: String, _ doc: inout ArchiDocument) {
        for k in doc.blocks.keys where k.hasPrefix(block + "$D") { doc.blocks[k] = nil }
        for i in doc.entities.indices where doc.entities[i].props[baseProp] == block {
            _ = apply(values(doc.entities[i].props), toInsert: i, &doc)
        }
    }
}

// MARK: - Macros with pauses

public enum MacroPause {
    /// Token that stops feeding a macro until the user answers the current prompt (AutoCAD "\").
    public static let mark = "\u{3}"
}

// MARK: - QDIM

/// Quick dimension layouts for a set of points and arcs/circles.
public struct QuickDim {
    public var points: [Vec2]
    public var curves: [(center: Vec2, radius: Double, isCircle: Bool)]
    public var style: String
    public var spacing: Double
    public init(points: [Vec2], curves: [(center: Vec2, radius: Double, isCircle: Bool)] = [], style: String = "Standard", spacing: Double) {
        self.points = points; self.curves = curves; self.style = style; self.spacing = spacing
    }

    /// Dimensions for a mode (Continuous, Staggered, Baseline, Ordinate, Radius, Diameter) placed at `loc`.
    public func build(_ mode: String, at loc: Vec2, datum: Vec2 = .zero) -> [DimensionGeom] {
        switch mode {
        case "Radius", "Diameter":
            return curves.map { c in
                let w = (loc - c.center).lengthSquared > 1e-18 ? (loc - c.center).normalized : Vec2(1, 0)
                let kind: DimKind = mode == "Radius" ? .radius : .diameter
                return DimensionGeom(kind: kind, points: [c.center, c.center + w * c.radius, c.center + w * (c.radius + spacing)], style: style)
            }
        default: break
        }
        guard points.count >= 2 else { return [] }
        let bb = BBox2(points: points)
        let vertical = loc.y >= bb.min.y && loc.y <= bb.max.y && !(loc.x >= bb.min.x && loc.x <= bb.max.x)
        let key: (Vec2) -> Double = vertical ? { $0.y } : { $0.x }
        var sorted: [Vec2] = []
        for p in points.sorted(by: { key($0) < key($1) }) where sorted.last.map({ abs(key($0) - key(p)) > 1e-6 }) ?? true { sorted.append(p) }
        guard sorted.count >= 2 else { return [] }
        let rot = vertical ? Double.pi / 2 : 0
        // Direction away from the objects.
        let n = vertical ? Vec2(loc.x < bb.min.x ? -1 : 1, 0) : Vec2(0, loc.y < bb.min.y ? -1 : 1)
        var out: [DimensionGeom] = []
        switch mode {
        case "Ordinate":
            for p in sorted {
                // Leaders run to the dimension line position; vertical leaders measure X, horizontal ones Y.
                let end = vertical ? Vec2(loc.x, p.y) : Vec2(p.x, loc.y)
                out.append(DimensionGeom(kind: .ordinate, points: [p, end, datum], style: style))
            }
        case "Baseline":
            for i in 1..<sorted.count {
                out.append(DimensionGeom(kind: .linear, points: [sorted[0], sorted[i], loc + n * spacing * Double(i - 1)], rotation: rot, style: style))
            }
        case "Staggered":
            // Nested from the middle out: the innermost pair on the dimension line, each outer pair one spacing further.
            var lo = (sorted.count - 1) / 2, hi = sorted.count / 2
            if lo == hi { lo -= 1; hi += 1 }
            var level = 0.0
            while lo >= 0 && hi < sorted.count {
                out.append(DimensionGeom(kind: .linear, points: [sorted[lo], sorted[hi], loc + n * spacing * level], rotation: rot, style: style))
                lo -= 1; hi += 1; level += 1
            }
        default:
            for i in 1..<sorted.count {
                out.append(DimensionGeom(kind: .linear, points: [sorted[i - 1], sorted[i], loc], rotation: rot, style: style))
            }
        }
        return out
    }
}

// MARK: - Attribute modes

/// Attribute definition modes (prop "attMode": letters I invisible, C constant, V verify, P preset, L locked position).
public enum AttributeModes {
    public static let prop = "attMode"
    public static let all = ["Invisible", "Constant", "Verify", "Preset", "Lock"]
    public static func has(_ e: Entity, _ flag: String) -> Bool { (e.props[prop] ?? "").uppercased().contains(flag.uppercased()) }
    public static func text(_ flags: Set<String>) -> String { "ICVPL".map(String.init).filter { flags.contains($0) }.joined() }
}

// MARK: - Ellipse inscribed in a parallelogram

public enum InscribedEllipse {
    /// The ellipse tangent to all four sides of the parallelogram p0 p1 p2 p3 at their midpoints (conjugate semi-diameters
    /// half of each side). nil when the points are not a (non-degenerate) parallelogram.
    public static func inParallelogram(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, tolerance: Double = 1e-6) -> EllipseGeom? {
        let u = (p1 - p0) / 2, v = (p3 - p0) / 2
        let scale = max(u.length, v.length, 1e-12)
        guard abs(u.cross(v)) > 1e-12 * scale * scale, (p0 + (p1 - p0) + (p3 - p0)).distance(to: p2) <= tolerance * max(scale, 1) else { return nil }
        return fromConjugate(center: p0 + u + v, u, v)
    }

    /// Ellipse c + u cos t + v sin t (u, v conjugate semi-diameters) as centre, major axis and ratio.
    public static func fromConjugate(center c: Vec2, _ u: Vec2, _ v: Vec2) -> EllipseGeom {
        let t0 = 0.5 * atan2(2 * u.dot(v), u.dot(u) - v.dot(v))
        var major = u * cos(t0) + v * sin(t0)
        var minor = u * cos(t0 + .pi / 2) + v * sin(t0 + .pi / 2)
        if minor.length > major.length { swap(&major, &minor) }
        return EllipseGeom(center: c, majorAxis: major, ratio: major.length > 0 ? minor.length / major.length : 1)
    }
}
