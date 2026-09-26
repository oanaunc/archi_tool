// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Grip roles: what dragging the grip does.
public enum GripKind: String, Codable, Hashable {
    /// Endpoint / vertex / fit or control point: stretches that point.
    case vertex
    /// Midpoint of a line or polyline segment, or of an arc.
    case midpoint
    /// Centre of a circle, arc or ellipse: moves the object.
    case center
    /// Quadrant of a circle / axis end of an ellipse: changes the radius / axis.
    case quadrant
    /// Base point of text, blocks, images, tables and solids: moves the object.
    case insertion
    /// Right edge of multiline text: changes its wrap width.
    case textWidth
    /// Extension line origin (measured point) of a dimension.
    case dimOrigin
    /// Dimension line / text location of a dimension.
    case dimText
}

/// One grip of an object: its location, role and the index of the defining point it edits.
public struct Grip: Equatable, Hashable {
    public var point: Vec2
    public var kind: GripKind
    public var index: Int
    public init(point: Vec2, kind: GripKind, index: Int) { self.point = point; self.kind = kind; self.index = index }
}

/// Grip operating modes cycled with Space/Enter while a grip is hot (SEL-034).
public enum GripMode: String, CaseIterable, Codable {
    case stretch, move, rotate, scale, mirror
    public var next: GripMode { let a = GripMode.allCases; return a[(a.firstIndex(of: self)! + 1) % a.count] }
}

/// Options of the multi-functional grip menu (SEL-035).
public enum GripAction: String, CaseIterable, Codable {
    case stretch, lengthen, addVertex, removeVertex, convertToArc, convertToLine, radius
    public var title: String {
        switch self {
        case .stretch: return "Stretch"; case .lengthen: return "Lengthen"; case .addVertex: return "Add Vertex"
        case .removeVertex: return "Remove Vertex"; case .convertToArc: return "Convert to Arc"; case .convertToLine: return "Convert to Line"
        case .radius: return "Radius"
        }
    }
}

/// Grip points and grip editing of drafting geometry (SEL-032/033/035/037): the core used by the canvas, scripts and tests.
public enum Grips {
    // MARK: Grip points

    public static func grips(_ g: Geometry) -> [Grip] {
        switch g {
        case .point(let p): return [Grip(point: p, kind: .insertion, index: 0)]
        case .line(let l): return [Grip(point: l.a, kind: .vertex, index: 0), Grip(point: (l.a + l.b) / 2, kind: .midpoint, index: 1), Grip(point: l.b, kind: .vertex, index: 2)]
        case .circle(let c):
            return [Grip(point: c.center, kind: .center, index: 0)] + (0..<4).map { Grip(point: c.center + Vec2.polar(c.radius, Double($0) * .pi / 2), kind: .quadrant, index: $0 + 1) }
        case .arc(let a):
            return [Grip(point: a.startPoint, kind: .vertex, index: 0), Grip(point: a.midPoint, kind: .midpoint, index: 1),
                    Grip(point: a.endPoint, kind: .vertex, index: 2), Grip(point: a.center, kind: .center, index: 3)]
        case .ellipse(let e):
            return [Grip(point: e.center, kind: .center, index: 0), Grip(point: e.center + e.majorAxis, kind: .quadrant, index: 1),
                    Grip(point: e.center - e.majorAxis, kind: .quadrant, index: 2), Grip(point: e.center + e.majorAxis.perp * e.ratio, kind: .quadrant, index: 3),
                    Grip(point: e.center - e.majorAxis.perp * e.ratio, kind: .quadrant, index: 4)]
        case .polyline(let p):
            var out = p.vertices.enumerated().map { Grip(point: $0.element.p, kind: .vertex, index: $0.offset) }
            let n = p.vertices.count
            let segs = p.closed ? n : n - 1
            if segs >= 1 {
                for i in 0..<segs {
                    let a = p.vertices[i], b = p.vertices[(i + 1) % n]
                    out.append(Grip(point: CurvePiece.bulge(a.p, b.p, a.bulge).point(0.5), kind: .midpoint, index: i))
                }
            }
            return out
        case .spline(let s):
            let pts = s.fitPoints.isEmpty ? s.controlPoints : s.fitPoints
            return pts.enumerated().map { Grip(point: $0.element, kind: .vertex, index: $0.offset) }
        case .text(let t):
            var out = [Grip(point: t.position, kind: .insertion, index: 0)]
            if t.width > 0 {
                // Width grip at the right end of the first line (text frame edge).
                let x: Double
                switch t.halign { case .left: x = t.width; case .center: x = t.width / 2; case .right: x = 0 }
                out.append(Grip(point: t.position + Vec2.polar(x, t.rotation), kind: .textWidth, index: 1))
            }
            return out
        case .dimension(let d):
            let pts = DimensionRenderer.definitionPoints(d)
            let slot = dimTextSlot(d.kind)
            return pts.enumerated().map { Grip(point: $0.element, kind: $0.offset == slot ? .dimText : .dimOrigin, index: $0.offset) }
        case .hatch(let h):
            // Hatches move with their boundary; one grip at the centroid of the outer loop moves the hatch.
            guard let loop = h.loops.first, loop.count >= 3 else { return [] }
            return [Grip(point: GeometryOps.centroid(GeometryOps.polylinePoints(loop, closed: true)), kind: .center, index: 0)]
        case .insert(let i): return [Grip(point: i.position, kind: .insertion, index: 0)]
        case .leader(let l): return l.points.enumerated().map { Grip(point: $0.element, kind: .vertex, index: $0.offset) }
        case .image(let im):
            let u = Vec2.polar(1, im.rotation), v = u.perp
            return [Grip(point: im.origin, kind: .insertion, index: 0), Grip(point: im.origin + u * im.size.x, kind: .vertex, index: 1),
                    Grip(point: im.origin + u * im.size.x + v * im.size.y, kind: .vertex, index: 2), Grip(point: im.origin + v * im.size.y, kind: .vertex, index: 3)]
        case .table(let tb): return [Grip(point: tb.origin, kind: .insertion, index: 0)]
        case .solid(let s): return [Grip(point: s.origin.xy, kind: .insertion, index: 0)]
        }
    }

    /// Definition point that locates a dimension's text / dimension line.
    public static func dimTextSlot(_ k: DimKind) -> Int {
        switch k { case .angular, .arcLength: return 3; case .ordinate: return 1; default: return 2 }
    }

    // MARK: Stretch

    /// The geometry after dragging `grip` to `p` (stretch mode).
    public static func stretched(_ g: Geometry, grip: Grip, to p: Vec2) -> Geometry {
        let d = p - grip.point
        switch g {
        case .point: return .point(p)
        case .line(var l):
            switch grip.index { case 0: l.a = p; case 2: l.b = p; default: l.a += d; l.b += d }
            return .line(l)
        case .circle(var c):
            if grip.index == 0 { c.center = p } else { c.radius = Swift.max(c.center.distance(to: p), 1e-9) }
            return .circle(c)
        case .arc(let a):
            switch grip.index {
            case 3: var x = a; x.center = p; return .arc(x)
            case 1: return arc3(a.startPoint, p, a.endPoint).map(Geometry.arc) ?? g
            case 0: return arc3(p, a.midPoint, a.endPoint).map(Geometry.arc) ?? g
            default: return arc3(a.startPoint, a.midPoint, p).map(Geometry.arc) ?? g
            }
        case .ellipse(var e):
            switch grip.index {
            case 0: e.center = p
            case 1, 2:
                let v = grip.index == 1 ? p - e.center : e.center - p
                if v.length > 1e-9 { let minor = e.ratio * e.majorAxis.length; e.majorAxis = v; e.ratio = Swift.min(1e6, minor / v.length) }
            default: e.ratio = Swift.max(1e-6, e.center.distance(to: p) / Swift.max(e.majorAxis.length, 1e-9))
            }
            return .ellipse(e)
        case .polyline(var pl):
            if grip.kind == .midpoint {
                // Straight segment: moves both ends; arc segment: the arc passes through the new point.
                let n = pl.vertices.count
                guard pl.vertices.indices.contains(grip.index), n >= 2 else { return g }
                let j = (grip.index + 1) % n
                if abs(pl.vertices[grip.index].bulge) < 1e-12 {
                    pl.vertices[grip.index].p += d; pl.vertices[j].p += d
                } else {
                    pl.vertices[grip.index].bulge = bulgeThrough(pl.vertices[grip.index].p, p, pl.vertices[j].p)
                }
            } else if pl.vertices.indices.contains(grip.index) { pl.vertices[grip.index].p = p }
            return .polyline(pl)
        case .spline(var s):
            if !s.fitPoints.isEmpty { if s.fitPoints.indices.contains(grip.index) { s.fitPoints[grip.index] = p } }
            else if s.controlPoints.indices.contains(grip.index) { s.controlPoints[grip.index] = p }
            return .spline(s)
        case .text(var t):
            if grip.kind == .textWidth {
                // Width measured along the text direction from the insertion point (left/right/centre aligned).
                let along = (p - t.position).dot(Vec2.polar(1, t.rotation))
                let w: Double
                switch t.halign { case .left: w = along; case .center: w = 2 * along; case .right: w = t.width }
                if w > 1e-9 { t.width = w }
                return .text(t)
            }
            t.position = p
            return .text(t)
        case .dimension(var dm):
            if dm.points.indices.contains(grip.index) { dm.points[grip.index] = p }
            return .dimension(dm)
        case .leader(var l):
            if l.points.indices.contains(grip.index) { l.points[grip.index] = p }
            return .leader(l)
        case .image(var im) where grip.index > 0:
            // Corner grips resize keeping the aspect ratio (opposite corner = origin).
            let u = Vec2.polar(1, im.rotation), v = u.perp
            let local = Vec2((p - im.origin).dot(u), (p - im.origin).dot(v))
            let s: Double
            switch grip.index {
            case 1: s = local.x / Swift.max(im.size.x, 1e-12)
            case 3: s = local.y / Swift.max(im.size.y, 1e-12)
            default: s = Swift.max(local.x / Swift.max(im.size.x, 1e-12), local.y / Swift.max(im.size.y, 1e-12))
            }
            if s > 1e-9 { im.size = im.size * s }
            return .image(im)
        default:
            return GeometryOps.transform(g, .translation(d))
        }
    }

    // MARK: Grip modes

    /// Transform of a grip mode from the base (hot grip) to `p`: Move translates, Rotate turns by the angle of p from the
    /// base, Scale uses |p − base| / reference, Mirror mirrors about the line base–p. Nil for Stretch or a degenerate input.
    public static func modeTransform(_ mode: GripMode, base: Vec2, to p: Vec2, reference: Double = 1) -> Transform2D? {
        let v = p - base
        switch mode {
        case .stretch: return nil
        case .move: return .translation(v)
        case .rotate:
            guard v.length > 1e-12 else { return nil }
            return .rotation(v.angle, around: base)
        case .scale:
            guard v.length > 1e-12, reference > 1e-12 else { return nil }
            let f = v.length / reference
            return .translation(base) * .scale(f, f) * .translation(-base)
        case .mirror:
            guard v.length > 1e-12 else { return nil }
            let a = v.angle
            return .translation(base) * .rotation(a) * .scale(1, -1) * .rotation(-a) * .translation(-base)
        }
    }

    // MARK: Multi-functional grips

    /// Options offered when hovering a grip.
    public static func actions(_ g: Geometry, grip: Grip) -> [GripAction] {
        switch g {
        case .line: return grip.kind == .vertex ? [.stretch, .lengthen] : [.stretch]
        case .arc: return grip.kind == .vertex ? [.stretch, .lengthen] : (grip.kind == .midpoint ? [.stretch, .radius] : [.stretch])
        case .polyline(let pl):
            if grip.kind == .midpoint {
                let arc = pl.vertices.indices.contains(grip.index) && abs(pl.vertices[grip.index].bulge) > 1e-12
                return [.stretch, .addVertex, arc ? .convertToLine : .convertToArc]
            }
            return pl.vertices.count > 2 ? [.stretch, .addVertex, .removeVertex] : [.stretch, .addVertex]
        default: return [.stretch]
        }
    }

    /// Applies a multi-functional grip option. `p` is the dragged point (ignored by Remove Vertex / Convert to Line).
    public static func apply(_ action: GripAction, _ g: Geometry, grip: Grip, to p: Vec2) -> Geometry? {
        switch (action, g) {
        case (.stretch, _): return stretched(g, grip: grip, to: p)
        case (.lengthen, .line(var l)):
            // New length from the far end, measured along the line.
            let fixed = grip.index == 0 ? l.b : l.a
            let dir = ((grip.index == 0 ? l.a : l.b) - fixed).normalized
            guard dir != .zero else { return nil }
            let len = (p - fixed).dot(dir)
            guard len > 1e-9 else { return nil }
            if grip.index == 0 { l.a = fixed + dir * len } else { l.b = fixed + dir * len }
            return .line(l)
        case (.lengthen, .arc(var a)):
            let ang = (p - a.center).angle
            if grip.index == 0 { a.start = ang } else { a.end = ang }
            guard normAngle(a.end - a.start) > 1e-9 else { return nil }
            return .arc(a)
        case (.radius, .arc(var a)):
            let r = a.center.distance(to: p)
            guard r > 1e-9 else { return nil }
            a.radius = r
            return .arc(a)
        case (.addVertex, .polyline(var pl)):
            let n = pl.vertices.count
            guard pl.vertices.indices.contains(grip.index) else { return nil }
            if grip.kind == .midpoint || grip.kind == .vertex {
                // Inserted after the grip's vertex (a vertex grip on the last vertex of an open polyline adds at the end).
                let i = grip.index
                if !pl.closed && i == n - 1 { pl.vertices.append(PolyVertex(p)); return .polyline(pl) }
                let b = pl.vertices[i].bulge
                if abs(b) > 1e-12 {
                    // Split the arc: both halves keep passing through their original arc as closely as the new point allows.
                    let a0 = pl.vertices[i].p, a1 = pl.vertices[(i + 1) % n].p
                    let pc = CurvePiece.bulge(a0, a1, b)
                    let t = pc.closestParam(p)
                    pl.vertices[i].bulge = bulgeThrough(a0, pc.point(t / 2), p)
                    pl.vertices.insert(PolyVertex(p, bulge: bulgeThrough(p, pc.point((1 + t) / 2), a1)), at: i + 1)
                } else {
                    pl.vertices.insert(PolyVertex(p), at: i + 1)
                }
                return .polyline(pl)
            }
            return nil
        case (.removeVertex, .polyline(var pl)):
            guard pl.vertices.count > 2, pl.vertices.indices.contains(grip.index), grip.kind == .vertex else { return nil }
            pl.vertices.remove(at: grip.index)
            if pl.closed && pl.vertices.count < 3 { pl.closed = false }
            return .polyline(pl)
        case (.convertToArc, .polyline(var pl)):
            guard grip.kind == .midpoint, pl.vertices.indices.contains(grip.index), pl.vertices.count >= 2 else { return nil }
            let j = (grip.index + 1) % pl.vertices.count
            pl.vertices[grip.index].bulge = bulgeThrough(pl.vertices[grip.index].p, p, pl.vertices[j].p)
            return .polyline(pl)
        case (.convertToLine, .polyline(var pl)):
            guard grip.kind == .midpoint, pl.vertices.indices.contains(grip.index) else { return nil }
            pl.vertices[grip.index].bulge = 0
            return .polyline(pl)
        default: return nil
        }
    }

    // MARK: Helpers

    /// Counter-clockwise arc through three points (a → m → b), or nil when they are collinear.
    public static func arc3(_ a: Vec2, _ m: Vec2, _ b: Vec2) -> ArcGeom? {
        let d = 2 * (a.x * (m.y - b.y) + m.x * (b.y - a.y) + b.x * (a.y - m.y))
        guard abs(d) > 1e-12 * Swift.max(1, a.distance(to: b) * a.distance(to: m)) else { return nil }
        let a2 = a.lengthSquared, m2 = m.lengthSquared, b2 = b.lengthSquared
        let c = Vec2((a2 * (m.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - m.y)) / d, (a2 * (b.x - m.x) + m2 * (a.x - b.x) + b2 * (m.x - a.x)) / d)
        let r = c.distance(to: a)
        let sa = (a - c).angle, sm = (m - c).angle, sb = (b - c).angle
        // CCW from a through m to b, else the arc runs b → a.
        if normAngle(sm - sa) <= normAngle(sb - sa) { return ArcGeom(c, r, sa, sb) }
        return ArcGeom(c, r, sb, sa)
    }

    /// Bulge of the arc segment from a to b passing through m (0 when collinear).
    public static func bulgeThrough(_ a: Vec2, _ m: Vec2, _ b: Vec2) -> Double {
        let side = (b - a).cross(m - a)
        guard abs(side) > 1e-12 * Swift.max(1, (b - a).lengthSquared), a.distance(to: b) > 1e-12 else { return 0 }
        // Inscribed angle at m subtends the chord: sweep = 2π − 2·∠AMB.
        let u = (a - m).normalized, v = (b - m).normalized
        let angM = acos(Swift.max(-1, Swift.min(1, u.dot(v))))
        let sweep = 2 * .pi - 2 * angM
        // Positive bulge (counter-clockwise) bulges to the right of a → b.
        return tan(sweep / 4) * (side < 0 ? 1 : -1)
    }
}
