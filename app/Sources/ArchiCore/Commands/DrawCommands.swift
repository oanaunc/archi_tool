// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension Editor {
    /// Distance typed or picked (the picked point is returned too, e.g. to orient polygons).
    func getDistanceOrPoint(_ msg: String, base: Vec2, defaultValue: Double? = nil, keywords: [String] = [], preview: ((Vec2) -> [Geometry])? = nil) async throws -> (value: Double?, point: Vec2?, keyword: String?) {
        var kinds: Set<InputRequest.Kind> = [.distance, .point]
        if !keywords.isEmpty { kinds.insert(.keyword) }
        let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords, defaultValue: defaultValue.map { fmt($0) }, base: base, preview: preview))
        switch r {
        case .number(let d): return (d, nil, nil)
        case .point(let p): return (base.distance(to: p), p, nil)
        case .keyword(let k): return (nil, nil, k)
        case .enter: return (defaultValue, nil, nil)
        case .cancel: throw CommandError.cancelled
        default: return (defaultValue, nil, nil)
        }
    }

    /// End point and tangent of the last line/arc/polyline drawn (for ARC and PLINE continuation).
    func lastCurveEnd() -> (Vec2, Vec2)? {
        for e in doc.entities.reversed() {
            switch e.geometry {
            case .line(let l): return (l.b, (l.b - l.a).normalized)
            case .arc(let a): return (a.endPoint, Vec2.polar(1, a.end + .pi / 2))
            case .polyline(let p) where !p.closed && p.vertices.count >= 2:
                let a = p.vertices[p.vertices.count - 2], b = p.vertices[p.vertices.count - 1]
                return (b.p, CommandHelpers.endTangent(a.p, b.p, bulge: a.bulge))
            default: continue
            }
        }
        return nil
    }
}

enum DrawCommands {
    static func arcFromBulge(_ a: Vec2, _ b: Vec2, _ bulge: Double) -> ArcGeom {
        let arc = GeometryOps.bulgeArc(a, b, bulge)
        if arc.sweep >= 0 { return ArcGeom(arc.center, arc.radius, normAngle(arc.start), normAngle(arc.start + arc.sweep)) }
        return ArcGeom(arc.center, arc.radius, normAngle(arc.start + arc.sweep), normAngle(arc.start))
    }

    static func rectangle(_ p1: Vec2, _ p2: Vec2, rotation: Double, fillet: Double, chamfer: (Double, Double), width: Double) -> PolylineGeom {
        let u = Vec2.polar(1, rotation), v = u.perp
        let local = (p2 - p1).rotated(by: -rotation)
        var pts = [p1, p1 + u * local.x, p1 + u * local.x + v * local.y, p1 + v * local.y]
        if GeometryOps.signedArea(pts) < 0 { pts.reverse() }
        let minSide = min(abs(local.x), abs(local.y))
        var verts: [PolyVertex] = []
        if fillet > 0 && fillet * 2 <= minSide + 1e-9 {
            for i in 0..<4 {
                let c = pts[i], prev = pts[(i + 3) % 4], next = pts[(i + 1) % 4]
                verts.append(PolyVertex(c + (prev - c).normalized * fillet, bulge: tan(.pi / 8)))
                verts.append(PolyVertex(c + (next - c).normalized * fillet))
            }
        } else if chamfer.0 > 0 && chamfer.1 > 0 && chamfer.0 + chamfer.1 <= minSide + 1e-9 {
            for i in 0..<4 {
                let c = pts[i], prev = pts[(i + 3) % 4], next = pts[(i + 1) % 4]
                verts.append(PolyVertex(c + (prev - c).normalized * chamfer.0))
                verts.append(PolyVertex(c + (next - c).normalized * chamfer.1))
            }
        } else { verts = pts.map { PolyVertex($0) } }
        return PolylineGeom(verts, closed: true, width: width)
    }

    static func regularPolygon(center: Vec2, radius: Double, sides n: Int, firstAngle: Double) -> [Vec2] {
        (0..<n).map { center + Vec2.polar(radius, firstAngle + 2 * .pi * Double($0) / Double(n)) }
    }

    /// Revision cloud along a closed or open point chain.
    static func cloud(_ input: [Vec2], closed: Bool, arcLength: Double) -> PolylineGeom {
        var pts = input
        if closed && GeometryOps.signedArea(pts) < 0 { pts.reverse() }
        var verts: [PolyVertex] = []
        let count = closed ? pts.count : pts.count - 1
        let bulge = tan(rad(120) / 4)
        for i in 0..<max(count, 0) {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let n = max(1, Int((a.distance(to: b) / max(arcLength, 1e-9)).rounded()))
            for k in 0..<n { verts.append(PolyVertex(a.lerp(b, Double(k) / Double(n)), bulge: bulge)) }
        }
        if !closed, let l = pts.last { verts.append(PolyVertex(l)) }
        return PolylineGeom(verts, closed: closed)
    }

    // MARK: Tangent circles (TTR)
    enum Curve { case line(Vec2, Vec2), circle(Vec2, Double) }
    static func curve(_ g: Geometry) -> Curve? {
        switch g {
        case .line(let l): return .line(l.a, l.b)
        case .circle(let c): return .circle(c.center, c.radius)
        case .arc(let a): return .circle(a.center, a.radius)
        default: return nil
        }
    }
    static func offsets(_ c: Curve, _ r: Double) -> [Curve] {
        switch c {
        case .line(let a, let b):
            let n = (b - a).normalized.perp * r
            return [.line(a + n, b + n), .line(a - n, b - n)]
        case .circle(let o, let R):
            var out: [Curve] = [.circle(o, R + r)]
            if abs(R - r) > 1e-9 { out.append(.circle(o, abs(R - r))) }
            return out
        }
    }
    static func intersect(_ a: Curve, _ b: Curve) -> [Vec2] {
        switch (a, b) {
        case let (.line(p1, p2), .line(p3, p4)): return GeometryOps.lineIntersection(p1, p2, p3, p4).map { [$0] } ?? []
        case let (.line(p1, p2), .circle(c, r)), let (.circle(c, r), .line(p1, p2)):
            let d = (p2 - p1).normalized
            guard d != .zero else { return [] }
            let t0 = (c - p1).dot(d)
            let foot = p1 + d * t0
            let h2 = r * r - foot.distance(to: c) * foot.distance(to: c)
            if h2 < -1e-9 { return [] }
            let h = max(0, h2).squareRoot()
            return h < 1e-12 ? [foot] : [foot + d * h, foot - d * h]
        case let (.circle(c1, r1), .circle(c2, r2)):
            let dd = c1.distance(to: c2)
            guard dd > 1e-12, dd <= r1 + r2 + 1e-9, dd >= abs(r1 - r2) - 1e-9 else { return [] }
            let a = (r1 * r1 - r2 * r2 + dd * dd) / (2 * dd)
            let h = max(0, r1 * r1 - a * a).squareRoot()
            let m = c1 + (c2 - c1) * (a / dd)
            let n = (c2 - c1).normalized.perp
            return h < 1e-12 ? [m] : [m + n * h, m - n * h]
        }
    }
    static func tangentPoint(_ c: Curve, center: Vec2) -> Vec2 {
        switch c {
        case .line(let a, let b): return GeometryOps.lineIntersection(a, b, center, center + (b - a).perp) ?? a
        case .circle(let o, let R): return o + (center - o).normalized * R
        }
    }
    static func ttrCenter(_ g1: Geometry, _ p1: Vec2, _ g2: Geometry, _ p2: Vec2, radius r: Double) -> Vec2? {
        guard let c1 = curve(g1), let c2 = curve(g2) else { return nil }
        var best: (Vec2, Double)?
        for o1 in offsets(c1, r) { for o2 in offsets(c2, r) { for x in intersect(o1, o2) {
            let score = tangentPoint(c1, center: x).distance(to: p1) + tangentPoint(c2, center: x).distance(to: p2)
            if score < (best?.1 ?? .infinity) { best = (x, score) }
        } } }
        return best?.0
    }

    @MainActor static func elevation(_ ed: Editor) -> Double { ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0 }
    /// A tangent direction for SPLINE tangency: an angle, or a point giving the direction from the last point.
    @MainActor static func tangentInput(_ ed: Editor, _ msg: String) async throws -> Vec2? {
        guard let a = try await ed.getAngle(msg, base: ed.lastPoint).value else { return nil }
        return Vec2.polar(1, a)
    }

    static var all: [CommandDef] { basic + curves + fills + solids + FeatureCommands9.drawOverrides }

    // MARK: - Lines and polylines
    static var basic: [CommandDef] { [
        CommandDef("LINE", aliases: ["L"], category: "Draw", summary: "Draws straight line segments.") { ed in
            var first = try await ed.requirePoint("Specify first point")
            var start = first
            var created: [EntityID] = []
            while true {
                let kws = created.count >= 2 ? ["Close", "Undo"] : (created.count >= 1 ? ["Undo"] : [])
                let s = start
                let a = try await ed.getPoint("Specify next point", base: start, keywords: kws) { c in [.line(LineGeom(s, c))] }
                switch a {
                case .point(let p):
                    guard !p.isClose(start, tol: 1e-9) else { ed.print("Zero-length segment ignored."); continue }
                    created.append(ed.addEntity(.line(LineGeom(start, p)))); start = p
                case .keyword("Close"):
                    ed.addEntity(.line(LineGeom(start, first))); return
                case .keyword("Undo"):
                    if let last = created.popLast(), let e = ed.doc.entity(last), case .line(let l) = e.geometry {
                        ed.doc.remove(ids: [last]); start = l.a
                    }
                    if created.isEmpty { first = start }
                default: return
                }
            }
        },
        CommandDef("XLINE", aliases: ["XL"], category: "Draw", summary: "Draws infinite construction lines: through two points, Horizontal, Vertical, at an Angle (or relative to a Reference line), Bisecting an angle, or Offset from a line.") { ed in
            let big = ConstructionLines.reach
            @MainActor @discardableResult func add(_ base: Vec2, _ dir: Vec2) -> EntityID? {
                guard let c = ConstructionLines.make(.xline, base: base, direction: dir) else { return nil }
                let id = ed.addEntity(c.geometry)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props.merge(c.props) { $1 } }
                return id
            }
            var fixedDir: Vec2? = nil
            let a = try await ed.getPoint("Specify a point", keywords: ["Hor", "Ver", "Ang", "Bisect", "Offset"])
            var origin: Vec2
            switch a {
            case .point(let p): origin = p
            case .keyword("Hor"): fixedDir = Vec2(1, 0); origin = try await ed.requirePoint("Specify through point")
            case .keyword("Ver"): fixedDir = Vec2(0, 1); origin = try await ed.requirePoint("Specify through point")
            case .keyword("Ang"):
                let r = try await ed.getAngle("Enter angle of xline or [Reference]", defaultValue: 0, keywords: ["Reference"])
                var ang = r.value ?? 0
                if case .keyword("Reference") = r {
                    guard case .pick(let pk) = try await ed.pickObject("Select a line object"), case .line(let l)? = ed.doc.entity(pk.id)?.geometry else { throw CommandError.invalid("Requires a line.") }
                    ang = (l.b - l.a).angle + (try await ed.getAngle("Enter angle of xline", defaultValue: 0).value ?? 0)
                }
                fixedDir = Vec2.polar(1, ang); origin = try await ed.requirePoint("Specify through point")
            case .keyword("Bisect"):
                let v = try await ed.requirePoint("Specify angle vertex point")
                let s = try await ed.requirePoint("Specify angle start point", base: v)
                while let e = try await ed.getPoint("Specify angle end point", base: v).point {
                    let d = ((s - v).normalized + (e - v).normalized).normalized
                    add(v, d == .zero ? (s - v).normalized.perp : d)
                }
                return
            case .keyword("Offset"):
                let r = try await ed.getDistance("Specify offset distance or [Through]", defaultValue: ed.settings.offsetDistance, keywords: ["Through"])
                let through = r == .keyword("Through")
                let dist = r.value ?? ed.settings.offsetDistance
                if !through { ed.settings.offsetDistance = dist }
                while case .pick(let pk) = try await ed.pickObject("Select a line object"), let e = ed.doc.entity(pk.id), case .line(let l) = e.geometry {
                    let d = (l.b - l.a).normalized
                    guard d != .zero else { continue }
                    let q = try await ed.requirePoint(through ? "Specify through point" : "Specify side to offset")
                    let base: Vec2
                    if through { base = q } else {
                        let n = d.perp * ((q - l.a).cross(d) < 0 ? dist : -dist)
                        base = l.a + n
                    }
                    add(base + d * ((l.a - base).dot(d) + (l.b - l.a).length / 2), d)
                }
                return
            default: return
            }
            if let d = fixedDir { add(origin, d) }
            while true {
                let o = origin
                let fd = fixedDir
                guard let p = try await ed.getPoint("Specify through point", base: origin, preview: { c in
                    let d = fd ?? (c - o).normalized; return d == .zero ? [] : [.line(LineGeom(o - d * big, o + d * big))] }).point else { return }
                if let fd = fixedDir { origin = p; add(p, fd); continue }
                add(origin, p - origin)
            }
        },
        CommandDef("RAY", category: "Draw", summary: "Draws semi-infinite construction lines from a start point through each given point.") { ed in
            let s = try await ed.requirePoint("Specify start point")
            let big = ConstructionLines.reach
            while let p = try await ed.getPoint("Specify through point", base: s, preview: { c in [.line(LineGeom(s, s + (c - s).normalized * big))] }).point {
                guard let c = ConstructionLines.make(.ray, base: s, direction: p - s) else { continue }
                let id = ed.addEntity(c.geometry)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props.merge(c.props) { $1 } }
            }
        },
        CommandDef("PLINE", aliases: ["PL"], category: "Draw", summary: "Draws a 2D polyline of line and arc segments.") { ed in
            let start = try await ed.requirePoint("Specify start point")
            var verts = [PolyVertex(start)]
            var width = ed.variableDouble("PLINEWID", 0)
            var arcMode = false
            var closed = false
            var tangent: Vec2? = nil
            func recomputeTangent() {
                if verts.count >= 2 { let a = verts[verts.count - 2], b = verts[verts.count - 1]; tangent = CommandHelpers.endTangent(a.p, b.p, bulge: a.bulge) }
                else { tangent = nil }
            }
            func previewWith(_ c: Vec2, bulge: Double) -> [Geometry] {
                var v = verts; v[v.count - 1].bulge = bulge; v.append(PolyVertex(c))
                return [.polyline(PolylineGeom(v, closed: false, width: width))]
            }
            func addArc(to p: Vec2, bulge: Double) {
                verts[verts.count - 1].bulge = bulge
                verts.append(PolyVertex(p)); recomputeTangent()
            }
            loop: while true {
                let cur = verts[verts.count - 1].p
                if !arcMode {
                    var kws = ["Arc", "Halfwidth", "Length", "Undo", "Width"]
                    if verts.count >= 3 { kws.insert("Close", at: 1) }
                    let a = try await ed.getPoint("Specify next point", base: cur, keywords: kws) { c in previewWith(c, bulge: 0) }
                    switch a {
                    case .point(let p):
                        guard !p.isClose(cur, tol: 1e-9) else { continue }
                        verts[verts.count - 1].bulge = 0; verts.append(PolyVertex(p)); tangent = (p - cur).normalized
                    case .keyword("Arc"): arcMode = true
                    case .keyword("Close"): closed = true; break loop
                    case .keyword("Halfwidth"):
                        width = 2 * (try await ed.getPositive("Specify starting half-width", base: cur, defaultValue: width / 2, allowZero: true))
                    case .keyword("Width"):
                        width = try await ed.getPositive("Specify starting width", base: cur, defaultValue: width, allowZero: true)
                        _ = try await ed.getDistance("Specify ending width", base: cur, defaultValue: width)
                    case .keyword("Length"):
                        guard let len = try await ed.getDistance("Specify length of line", base: cur).value, len > 0 else { continue }
                        let d = tangent ?? Vec2(1, 0)
                        verts[verts.count - 1].bulge = 0; verts.append(PolyVertex(cur + d * len))
                    case .keyword("Undo"):
                        if verts.count > 1 { verts.removeLast(); verts[verts.count - 1].bulge = 0; recomputeTangent() } else { ed.print("All segments already undone.") }
                    default: break loop
                    }
                } else {
                    var kws = ["Angle", "CEnter", "Direction", "Halfwidth", "Line", "Radius", "Second", "Undo", "Width"]
                    if verts.count >= 2 { kws.insert("CLose", at: 1) }
                    let t = tangent ?? Vec2(1, 0)
                    let a = try await ed.getPoint("Specify endpoint of arc", base: cur, keywords: kws) { c in previewWith(c, bulge: CommandHelpers.bulge(from: cur, tangent: t, to: c)) }
                    switch a {
                    case .point(let p):
                        guard !p.isClose(cur, tol: 1e-9) else { continue }
                        addArc(to: p, bulge: CommandHelpers.bulge(from: cur, tangent: t, to: p))
                    case .keyword("CLose"):
                        verts[verts.count - 1].bulge = CommandHelpers.bulge(from: cur, tangent: t, to: verts[0].p); closed = true; break loop
                    case .keyword("Line"): arcMode = false
                    case .keyword("Angle"):
                        guard let inc = try await ed.getAngle("Specify included angle").value, abs(inc) > 1e-9, abs(inc) < 2 * .pi else { continue }
                        let p = try await ed.requirePoint("Specify endpoint of arc", base: cur) { c in previewWith(c, bulge: tan(inc / 4)) }
                        addArc(to: p, bulge: tan(inc / 4))
                    case .keyword("CEnter"):
                        let c = try await ed.requirePoint("Specify center point of arc", base: cur)
                        let r = c.distance(to: cur)
                        guard r > 1e-9 else { continue }
                        let a0 = (cur - c).angle
                        let e = try await ed.requirePoint("Specify endpoint of arc", base: c) { p in [.arc(ArcGeom(c, r, a0, (p - c).angle))] }
                        let sweep = normAngle((e - c).angle - a0)
                        guard sweep > 1e-9 else { continue }
                        addArc(to: c + Vec2.polar(r, a0 + sweep), bulge: tan(sweep / 4))
                    case .keyword("Direction"):
                        guard let dirAng = try await ed.getAngle("Specify the tangent direction for the start point of arc", base: cur).value else { continue }
                        let d = Vec2.polar(1, dirAng)
                        let p = try await ed.requirePoint("Specify endpoint of the arc", base: cur) { c in previewWith(c, bulge: CommandHelpers.bulge(from: cur, tangent: d, to: c)) }
                        addArc(to: p, bulge: CommandHelpers.bulge(from: cur, tangent: d, to: p))
                    case .keyword("Radius"):
                        guard let r = try await ed.getDistance("Specify radius of arc", base: cur).value, r > 0 else { continue }
                        let p = try await ed.requirePoint("Specify endpoint of arc", base: cur)
                        let chord = cur.distance(to: p)
                        guard chord <= 2 * r + 1e-9 else { ed.print("Radius too small for this chord."); continue }
                        let sweep = 2 * asin(min(1, chord / (2 * r)))
                        addArc(to: p, bulge: tan(sweep / 4))
                    case .keyword("Second"):
                        let m = try await ed.requirePoint("Specify second point on arc", base: cur)
                        let p = try await ed.requirePoint("Specify end point of arc", base: m) { c in previewWith(c, bulge: CommandHelpers.bulge3(cur, m, c)) }
                        addArc(to: p, bulge: CommandHelpers.bulge3(cur, m, p))
                    case .keyword("Halfwidth"):
                        width = 2 * (try await ed.getPositive("Specify starting half-width", base: cur, defaultValue: width / 2, allowZero: true))
                    case .keyword("Width"):
                        width = try await ed.getPositive("Specify starting width", base: cur, defaultValue: width, allowZero: true)
                    case .keyword("Undo"):
                        if verts.count > 1 { verts.removeLast(); verts[verts.count - 1].bulge = 0; recomputeTangent() }
                    default: break loop
                    }
                }
            }
            ed.doc.setVariable("PLINEWID", fmt(width))
            guard verts.count >= 2 else { ed.print("A polyline needs at least two points."); return }
            if !closed { verts[verts.count - 1].bulge = 0 }
            ed.addEntity(.polyline(PolylineGeom(verts, closed: closed, width: width)))
        },
        CommandDef("RECTANG", aliases: ["REC", "RECTANGLE"], category: "Draw", summary: "Draws a rectangular polyline (optionally filleted or chamfered).") { ed in
            var fillet = ed.variableDouble("RECTFILLET", 0)
            var ch1 = ed.variableDouble("RECTCHAMFER1", 0), ch2 = ed.variableDouble("RECTCHAMFER2", 0)
            var width = ed.variableDouble("RECTWIDTH", 0)
            var rotation = 0.0
            var p1: Vec2
            while true {
                let a = try await ed.getPoint("Specify first corner point", keywords: ["Chamfer", "Fillet", "Width", "3P", "CEnter"])
                switch a {
                case .point(let p): p1 = p
                case .keyword("3P"):
                    let q1 = try await ed.requirePoint("Specify first point of the edge")
                    let q2 = try await ed.requirePoint("Specify second point of the edge", base: q1) { c in [.line(LineGeom(q1, c))] }
                    let q3 = try await ed.requirePoint("Specify a point on the opposite side", base: q2) { c in
                        DraftGeometry.rectangle3P(q1, q2, c).map { [.polyline(PolylineGeom(points: $0, closed: true))] } ?? [] }
                    guard let pts = DraftGeometry.rectangle3P(q1, q2, q3) else { throw CommandError.invalid("The rectangle has zero width or height.") }
                    let r = rectangle(pts[0], pts[2], rotation: (pts[1] - pts[0]).angle, fillet: fillet, chamfer: (ch1, ch2), width: width)
                    ed.addEntity(.polyline(r)); return
                case .keyword("CEnter"):
                    let c = try await ed.requirePoint("Specify center point")
                    let q = try await ed.requirePoint("Specify corner point", base: c) { p in
                        [.polyline(rectangle(c * 2 - p, p, rotation: 0, fillet: fillet, chamfer: (ch1, ch2), width: width))] }
                    let d = q - c
                    guard abs(d.x) > 1e-9, abs(d.y) > 1e-9 else { throw CommandError.invalid("The rectangle has zero width or height.") }
                    ed.addEntity(.polyline(rectangle(c - d, q, rotation: 0, fillet: fillet, chamfer: (ch1, ch2), width: width))); return
                case .keyword("Chamfer"):
                    ch1 = try await ed.getPositive("Specify first chamfer distance for rectangles", defaultValue: ch1, allowZero: true)
                    ch2 = try await ed.getPositive("Specify second chamfer distance for rectangles", defaultValue: ch1, allowZero: true)
                    fillet = 0; continue
                case .keyword("Fillet"):
                    fillet = try await ed.getPositive("Specify fillet radius for rectangles", defaultValue: fillet, allowZero: true); ch1 = 0; ch2 = 0; continue
                case .keyword("Width"):
                    width = try await ed.getPositive("Specify line width for rectangles", defaultValue: width, allowZero: true); continue
                default: return
                }
                break
            }
            ed.doc.setVariable("RECTFILLET", fmt(fillet)); ed.doc.setVariable("RECTCHAMFER1", fmt(ch1)); ed.doc.setVariable("RECTCHAMFER2", fmt(ch2)); ed.doc.setVariable("RECTWIDTH", fmt(width))
            let start = p1
            while true {
                let rot = rotation, f = fillet, c1 = ch1, c2 = ch2, w = width
                let a = try await ed.getPoint("Specify other corner point", base: start, keywords: ["Area", "Dimensions", "Rotation"]) { c in
                    [.polyline(rectangle(start, c, rotation: rot, fillet: f, chamfer: (c1, c2), width: w))] }
                let u = Vec2.polar(1, rotation), v = u.perp
                switch a {
                case .point(let p2):
                    let local = (p2 - start).rotated(by: -rotation)
                    guard abs(local.x) > 1e-9, abs(local.y) > 1e-9 else { throw CommandError.invalid("The rectangle has zero width or height.") }
                    ed.addEntity(.polyline(rectangle(start, p2, rotation: rotation, fillet: fillet, chamfer: (ch1, ch2), width: width))); return
                case .keyword("Rotation"):
                    rotation = try await ed.getAngle("Specify rotation angle", base: start, defaultValue: rotation).value ?? rotation
                case .keyword("Area"):
                    let area = try await ed.getPositive("Enter area of rectangle in current units", defaultValue: 100 * 100)
                    let k = try await ed.getKeyword("Calculate rectangle dimensions based on", ["Length", "Width"], defaultValue: "Length") ?? "Length"
                    let known = try await ed.getPositive(k == "Length" ? "Enter rectangle length" : "Enter rectangle width", defaultValue: area.squareRoot())
                    let l = k == "Length" ? known : area / known, wd = k == "Length" ? area / known : known
                    ed.addEntity(.polyline(rectangle(start, start + u * l + v * wd, rotation: rotation, fillet: fillet, chamfer: (ch1, ch2), width: width))); return
                case .keyword("Dimensions"):
                    let l = try await ed.getPositive("Specify length for rectangles", base: start, defaultValue: ed.variableDouble("RECTLEN", 1000))
                    let wd = try await ed.getPositive("Specify width for rectangles", base: start, defaultValue: ed.variableDouble("RECTWID", 1000))
                    ed.doc.setVariable("RECTLEN", fmt(l)); ed.doc.setVariable("RECTWID", fmt(wd))
                    var sx = 1.0, sy = 1.0
                    if let q = try await ed.getPoint("Specify other corner point", base: start, preview: { c in
                        let lc = (c - start).rotated(by: -rot)
                        return [.polyline(rectangle(start, start + u * (lc.x < 0 ? -l : l) + v * (lc.y < 0 ? -wd : wd), rotation: rot, fillet: f, chamfer: (c1, c2), width: w))] }).point {
                        let lc = (q - start).rotated(by: -rotation); sx = lc.x < 0 ? -1 : 1; sy = lc.y < 0 ? -1 : 1
                    }
                    ed.addEntity(.polyline(rectangle(start, start + u * (l * sx) + v * (wd * sy), rotation: rotation, fillet: fillet, chamfer: (ch1, ch2), width: width))); return
                default: return
                }
            }
        },
        CommandDef("POLYGON", aliases: ["POL"], category: "Draw", summary: "Draws an equilateral closed polyline.") { ed in
            let prev = Int(ed.variableDouble("POLYSIDES", 4))
            guard let n = try await ed.getInteger("Enter number of sides", defaultValue: prev), (3...1024).contains(n) else { throw CommandError.invalid("Requires an integer between 3 and 1024.") }
            ed.doc.setVariable("POLYSIDES", "\(n)")
            let a = try await ed.getPoint("Specify center of polygon", keywords: ["Edge"])
            if a == .keyword("Edge") {
                let e1 = try await ed.requirePoint("Specify first endpoint of edge")
                func poly(_ e2: Vec2) -> [Vec2]? {
                    let s = e1.distance(to: e2); guard s > 1e-9 else { return nil }
                    let apothem = s / (2 * tan(.pi / Double(n)))
                    let c = (e1 + e2) / 2 + (e2 - e1).normalized.perp * apothem
                    return regularPolygon(center: c, radius: c.distance(to: e1), sides: n, firstAngle: (e1 - c).angle)
                }
                let e2 = try await ed.requirePoint("Specify second endpoint of edge", base: e1) { c in poly(c).map { [.polyline(PolylineGeom(points: $0, closed: true))] } ?? [] }
                guard let pts = poly(e2) else { throw CommandError.invalid("Edge has zero length.") }
                ed.addEntity(.polyline(PolylineGeom(points: pts, closed: true))); return
            }
            guard let c = a.point else { return }
            let mode = try await ed.getKeyword("Enter an option", ["Inscribed", "Circumscribed"], defaultValue: ed.doc.variable("POLYMODE") ?? "Inscribed") ?? "Inscribed"
            ed.doc.setVariable("POLYMODE", mode)
            func poly(_ r: Double, _ p: Vec2?) -> [Vec2] {
                let vr = mode == "Inscribed" ? r : r / cos(.pi / Double(n))
                let first: Double
                if let p = p { first = (p - c).angle + (mode == "Inscribed" ? 0 : .pi / Double(n)) } else { first = -.pi / 2 + .pi / Double(n) }
                return regularPolygon(center: c, radius: vr, sides: n, firstAngle: first)
            }
            let r = try await ed.getDistanceOrPoint("Specify radius of circle", base: c) { p in [.polyline(PolylineGeom(points: poly(c.distance(to: p), p), closed: true))] }
            guard let rv = r.value, rv > 0 else { throw CommandError.invalid("Radius must be positive.") }
            ed.addEntity(.polyline(PolylineGeom(points: poly(rv, r.point), closed: true)))
        },
    ] }

    // MARK: - Curves
    static var curves: [CommandDef] { [
        CommandDef("CIRCLE", aliases: ["C"], category: "Draw", summary: "Draws a circle (center/radius, diameter, 2P, 3P, tangent-tangent-radius, tangent-tangent-tangent).") { ed in
            let a = try await ed.getPoint("Specify center point for circle", keywords: ["3P", "2P", "Ttr", "TTT"])
            let lastR = ed.variableDouble("CIRCLERAD", 0)
            var result: CircleGeom?
            switch a {
            case .point(let c):
                let r = try await ed.getDistance("Specify radius of circle", base: c, defaultValue: lastR > 0 ? lastR : nil, keywords: ["Diameter"]) { p in [.circle(CircleGeom(c, c.distance(to: p)))] }
                switch r {
                case .value(let v): result = CircleGeom(c, v)
                case .keyword:
                    let d = try await ed.getDistance("Specify diameter of circle", base: c, defaultValue: lastR > 0 ? lastR * 2 : nil) { p in [.circle(CircleGeom(c, c.distance(to: p) / 2))] }
                    if let v = d.value { result = CircleGeom(c, v / 2) }
                default: return
                }
            case .keyword("3P"):
                let p1 = try await ed.requirePoint("Specify first point on circle")
                let p2 = try await ed.requirePoint("Specify second point on circle", base: p1)
                let p3 = try await ed.requirePoint("Specify third point on circle", base: p2) { c in CommandHelpers.circleFrom3(p1, p2, c).map { [.circle($0)] } ?? [] }
                result = CommandHelpers.circleFrom3(p1, p2, p3)
                if result == nil { throw CommandError.invalid("The three points are collinear.") }
            case .keyword("2P"):
                let p1 = try await ed.requirePoint("Specify first end point of circle's diameter")
                let p2 = try await ed.requirePoint("Specify second end point of circle's diameter", base: p1) { c in [.circle(CircleGeom((p1 + c) / 2, p1.distance(to: c) / 2))] }
                result = CircleGeom((p1 + p2) / 2, p1.distance(to: p2) / 2)
            case .keyword("TTT"):
                try await DraftConstructionCommands.apolloniusCommand(ed, tangents: 3, points: 0); return
            case .keyword("Ttr"):
                guard case .pick(let k1) = try await ed.pickObject("Specify point on object for first tangent of circle"),
                      case .pick(let k2) = try await ed.pickObject("Specify point on object for second tangent of circle") else { return }
                guard let r = try await ed.getDistance("Specify radius of circle", defaultValue: lastR > 0 ? lastR : nil).value, r > 0 else { return }
                guard let g1 = ed.doc.entity(k1.id)?.geometry, let g2 = ed.doc.entity(k2.id)?.geometry,
                      let c = ttrCenter(g1, k1.point, g2, k2.point, radius: r) else { throw CommandError.invalid("Circle does not exist (select lines, circles or arcs).") }
                result = CircleGeom(c, r)
            default: return
            }
            guard let circle = result, circle.radius > 1e-9, circle.radius.isFinite else { throw CommandError.invalid("Radius must be positive.") }
            ed.doc.setVariable("CIRCLERAD", fmt(circle.radius))
            ed.addEntity(.circle(circle))
        },
        CommandDef("ARC", aliases: ["A"], category: "Draw", summary: "Draws an arc (3 points, start-center-end, start-end-radius, center-start-angle, continue).") { ed in
            let first = try await ed.getPoint("Specify start point of arc (Enter to continue from last line/arc)", keywords: ["Center"])
            func centerThen(_ c: Vec2, _ s: Vec2) async throws -> ArcGeom? {
                let r = c.distance(to: s); guard r > 1e-9 else { return nil }
                let a0 = (s - c).angle
                let e = try await ed.getPoint("Specify end point of arc", base: c, keywords: ["Angle", "chordLength"]) { p in [.arc(ArcGeom(c, r, a0, (p - c).angle))] }
                switch e {
                case .point(let p): return ArcGeom(c, r, a0, (p - c).angle)
                case .keyword("Angle"):
                    guard let inc = try await ed.getAngle("Specify included angle", base: c).value, abs(inc) > 1e-9 else { return nil }
                    return inc > 0 ? ArcGeom(c, r, a0, a0 + inc) : ArcGeom(c, r, a0 + inc, a0)
                case .keyword("chordLength"):
                    guard let l = try await ed.getDistance("Specify length of chord", base: s).value, l > 0, l <= 2 * r else { return nil }
                    return ArcGeom(c, r, a0, a0 + 2 * asin(l / (2 * r)))
                default: return nil
                }
            }
            var arc: ArcGeom?
            switch first {
            case .none:
                guard let (s, t) = ed.lastCurveEnd() else { throw CommandError.invalid("No line or arc to continue.") }
                let e = try await ed.requirePoint("Specify end point of arc", base: s) { p in [.arc(arcFromBulge(s, p, CommandHelpers.bulge(from: s, tangent: t, to: p)))] }
                arc = arcFromBulge(s, e, CommandHelpers.bulge(from: s, tangent: t, to: e))
            case .keyword("Center"):
                let c = try await ed.requirePoint("Specify center point of arc")
                let s = try await ed.requirePoint("Specify start point of arc", base: c)
                arc = try await centerThen(c, s)
            case .point(let s):
                let second = try await ed.getPoint("Specify second point of arc", base: s, keywords: ["Center", "End"])
                switch second {
                case .point(let m):
                    let e = try await ed.requirePoint("Specify end point of arc", base: m) { p in CommandHelpers.arcFrom3(s, m, p).map { [.arc($0)] } ?? [] }
                    arc = CommandHelpers.arcFrom3(s, m, e)
                case .keyword("Center"):
                    let c = try await ed.requirePoint("Specify center point of arc", base: s)
                    arc = try await centerThen(c, s)
                case .keyword("End"):
                    let e = try await ed.requirePoint("Specify end point of arc", base: s)
                    guard e.distance(to: s) > 1e-9 else { throw CommandError.invalid("Start and end points coincide.") }
                    let k = try await ed.getPoint("Specify center point of arc", base: s, keywords: ["Angle", "Direction", "Radius"]) { c in
                        let r = c.distance(to: s); return [.arc(ArcGeom(c, r, (s - c).angle, (e - c).angle))] }
                    switch k {
                    case .point(let c): arc = ArcGeom(c, c.distance(to: s), (s - c).angle, (e - c).angle)
                    case .keyword("Angle"):
                        guard let inc = try await ed.getAngle("Specify included angle", base: s).value, abs(inc) > 1e-9, abs(inc) < 2 * .pi else { return }
                        arc = arcFromBulge(s, e, tan(inc / 4))
                    case .keyword("Direction"):
                        guard let d = try await ed.getAngle("Specify tangent direction for the start point of arc", base: s).value else { return }
                        arc = arcFromBulge(s, e, CommandHelpers.bulge(from: s, tangent: Vec2.polar(1, d), to: e))
                    case .keyword("Radius"):
                        guard let r = try await ed.getDistance("Specify radius of arc", base: e).value, abs(r) > 1e-9 else { return }
                        let chord = s.distance(to: e)
                        guard chord <= 2 * abs(r) + 1e-9 else { throw CommandError.invalid("Radius is too small for these end points.") }
                        var sweep = 2 * asin(min(1, chord / (2 * abs(r))))
                        if r < 0 { sweep = 2 * .pi - sweep } // negative radius = major arc (AutoCAD)
                        arc = arcFromBulge(s, e, tan(sweep / 4))
                    default: return
                    }
                default: return
                }
            default: return
            }
            guard let a = arc, a.radius > 1e-9, a.radius.isFinite else { throw CommandError.invalid("Invalid arc (points may be collinear).") }
            ed.addEntity(.arc(a))
        },
        CommandDef("ELLIPSE", aliases: ["EL"], category: "Draw", summary: "Draws an ellipse or elliptical arc.") { ed in
            var isArc = false
            var center: Vec2, major: Vec2
            var a = try await ed.getPoint("Specify axis endpoint of ellipse", keywords: ["Arc", "Center"])
            if a == .keyword("Arc") { isArc = true; a = try await ed.getPoint("Specify axis endpoint of elliptical arc", keywords: ["Center"]) }
            switch a {
            case .keyword("Center"):
                center = try await ed.requirePoint("Specify center of ellipse")
                let c = center
                let e = try await ed.requirePoint("Specify endpoint of axis", base: center) { p in [.line(LineGeom(c, p))] }
                major = e - center
            case .point(let p1):
                let p2 = try await ed.requirePoint("Specify other endpoint of axis", base: p1) { p in [.line(LineGeom(p1, p))] }
                center = (p1 + p2) / 2; major = p2 - center
            default: return
            }
            guard major.length > 1e-9 else { throw CommandError.invalid("Axis has zero length.") }
            let c = center, mj = major
            let r = try await ed.getDistance("Specify distance to other axis", base: center, keywords: ["Rotation"]) { p in
                let d = abs((p - c).dot(mj.normalized.perp)); return d > 1e-9 ? [.ellipse(EllipseGeom(center: c, majorAxis: mj, ratio: d / mj.length))] : [] }
            var minor: Double
            switch r {
            case .value(let v): minor = v
            case .keyword:
                let rot = try await ed.getAngle("Specify rotation around major axis", defaultValue: 0).value ?? 0
                guard abs(cos(rot)) > 1e-3 else { throw CommandError.invalid("Rotation must be less than 89.4°.") }
                minor = major.length * abs(cos(rot))
            default: return
            }
            guard minor > 1e-9 else { throw CommandError.invalid("Minor axis must be positive.") }
            var e: EllipseGeom
            if minor > major.length { e = EllipseGeom(center: center, majorAxis: major.normalized.perp * minor, ratio: major.length / minor) }
            else { e = EllipseGeom(center: center, majorAxis: major, ratio: minor / major.length) }
            if isArc {
                let s = try await ed.getAngle("Specify start angle", base: center, defaultValue: 0).value ?? 0
                let en = try await ed.getAngle("Specify end angle", base: center, defaultValue: .pi).value ?? .pi
                let base = e.majorAxis.angle
                // Angles picked in world direction → convert to ellipse parameters.
                func param(_ worldAngle: Double) -> Double {
                    let d = Vec2.polar(1, worldAngle - base)
                    return normAngle(atan2(d.y / max(e.ratio, 1e-12), d.x))
                }
                e.start = param(base + s); e.end = param(base + en)
                if abs(e.end - e.start) < 1e-9 { throw CommandError.invalid("Start and end angles coincide.") }
            }
            ed.addEntity(.ellipse(e))
        },
        CommandDef("SPLINE", aliases: ["SPL"], category: "Draw", summary: "Draws a smooth curve through fit points, or by control vertices (Method CV, Degree 1-5).") { ed in
            var method = ed.doc.variable("SPLMETHOD") == "1" ? "CV" : "Fit"
            var degree = Int(ed.variableDouble("SPLDEGREE", 3))
            var first: Vec2? = nil
            var startTan: Vec2? = nil, endTan: Vec2? = nil
            while first == nil {
                let a = try await ed.getPoint(method == "CV" ? "Specify first control vertex or [Method/Degree]" : "Specify first point or [Method/Tangency]",
                                              keywords: method == "CV" ? ["Method", "Degree"] : ["Method", "Tangency"])
                switch a {
                case .point(let p): first = p
                case .keyword("Tangency"):
                    // Start tangency: given as a direction (angle or a vector from the origin to a picked point).
                    startTan = try await tangentInput(ed, "Specify start tangent direction")
                case .keyword("Method"):
                    method = try await ed.getKeyword("Enter spline creation method", ["Fit", "CV"], defaultValue: method) ?? method
                    ed.doc.setVariable("SPLMETHOD", method == "CV" ? "1" : "0")
                case .keyword("Degree"):
                    guard let d = try await ed.getInteger("Enter degree of spline (1-5)", defaultValue: degree), (1...5).contains(d) else { ed.print("Requires an integer between 1 and 5."); continue }
                    degree = d; ed.doc.setVariable("SPLDEGREE", "\(d)")
                default: return
                }
            }
            if method == "CV" {
                var cv = [first!]
                var closedCV = false
                while true {
                    let cur = cv, deg = degree
                    let a = try await ed.getPoint("Enter next control vertex", base: cv.last, keywords: cv.count >= 3 ? ["Close", "Undo"] : ["Undo"]) { c in
                        let pts = cur + [c]
                        return [.spline(SplineGeom(degree: min(deg, pts.count - 1), controlPoints: pts)), .polyline(PolylineGeom(points: pts))]
                    }
                    switch a {
                    case .point(let p): if !p.isClose(cv.last!, tol: 1e-9) { cv.append(p) }; continue
                    case .keyword("Undo"): if cv.count > 1 { cv.removeLast() }; continue
                    case .keyword("Close"): closedCV = true
                    default: break
                    }
                    break
                }
                guard cv.count >= 2 else { throw CommandError.invalid("A spline needs at least two control vertices.") }
                if closedCV {
                    // Closed: wrap the first `degree` vertices so the curve closes smoothly (uniform periodic knots).
                    let p = min(degree, cv.count - 1)
                    let pts = cv + Array(cv.prefix(p))
                    let knots = (0..<(pts.count + p + 1)).map { Double($0) }
                    ed.addEntity(.spline(SplineGeom(degree: p, controlPoints: pts, knots: knots, closed: true)))
                } else {
                    ed.addEntity(.spline(SplineGeom(degree: min(degree, cv.count - 1), controlPoints: cv)))
                }
                return
            }
            var pts = [first!]
            var closed = false
            while true {
                let kws = pts.count >= 3 ? ["Close", "Tangency", "Undo"] : ["Tangency", "Undo"]
                let cur = pts, st = startTan
                let a = try await ed.getPoint("Enter next point", base: pts.last, keywords: kws) { c in
                    [.spline(st.flatMap { SplineFit.interpolate(cur + [c], startTangent: $0) } ?? SplineGeom(controlPoints: [], fitPoints: cur + [c]))] }
                switch a {
                case .point(let p): if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
                case .keyword("Close"): closed = true
                case .keyword("Tangency"):
                    endTan = try await tangentInput(ed, "Specify end tangent direction"); if pts.count >= 2 { break }; continue
                case .keyword("Undo"): if pts.count > 1 { pts.removeLast() }; continue
                default: break
                }
                if closed || a == .none || endTan != nil { break }
            }
            guard pts.count >= 2 else { throw CommandError.invalid("A spline needs at least two points.") }
            if !closed && (startTan != nil || endTan != nil), let s = SplineFit.interpolate(pts, startTangent: startTan, endTangent: endTan) {
                // Tangency control: an interpolating clamped cubic (fit points kept for editing).
                ed.addEntity(.spline(s))
            } else {
                ed.addEntity(.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: pts, closed: closed)))
            }
        },
        CommandDef("POINT", aliases: ["PO"], category: "Draw", summary: "Creates point objects (style: PDMODE/PDSIZE).") { ed in
            while let p = try await ed.getPoint("Specify a point").point { ed.addEntity(.point(p)) }
        },
        CommandDef("DONUT", aliases: ["DO", "DOUGHNUT"], category: "Draw", summary: "Draws filled rings or solid dots.") { ed in
            let id = try await ed.getPositive("Specify inside diameter of donut", defaultValue: ed.variableDouble("DONUTID", 50), allowZero: true)
            let od = try await ed.getPositive("Specify outside diameter of donut", defaultValue: ed.variableDouble("DONUTOD", 100))
            guard od > id else { throw CommandError.invalid("Outside diameter must be larger than inside diameter.") }
            ed.doc.setVariable("DONUTID", fmt(id)); ed.doc.setVariable("DONUTOD", fmt(od))
            let r = (id + od) / 4, w = (od - id) / 2
            func donut(_ c: Vec2) -> Geometry { .polyline(PolylineGeom([PolyVertex(c - Vec2(r, 0), bulge: 1), PolyVertex(c + Vec2(r, 0), bulge: 1)], closed: true, width: w)) }
            while let c = try await ed.getPoint("Specify center of donut", preview: { [donut($0)] }).point { ed.addEntity(donut(c)) }
        },
        CommandDef("REVCLOUD", category: "Draw", summary: "Draws a revision cloud: polygonal, rectangular, freehand, from an object or enclosing objects (attached: it moves with them); tagged with the current revision.") { ed in
            var arcLen = ed.variableDouble("REVCLOUDARC", 500)
            var rev = ed.doc.variable("REVCLOUDREV") ?? ed.doc.variable("REVNUMBER")
            @MainActor func finish(_ id: EntityID, hosts: [EntityID] = []) {
                guard let i = ed.doc.entityIndex(id) else { return }
                ed.doc.entities[i].props["revcloud"] = "1"
                if let r = rev { ed.doc.entities[i].props[RevisionClouds.revisionProp] = r }
                if !hosts.isEmpty { RevisionClouds.attach(&ed.doc.entities[i], to: hosts, doc: ed.doc) }
                let added = RevisionClouds.syncTable(&ed.doc)
                if !added.isEmpty { ed.print("Revision table: added revision \(added.joined(separator: ", ")).") }
            }
            while true {
                let a = try await ed.getPoint("Specify first point",
                                              keywords: ["Arclength", "Object", "Rectangular", "Polygonal", "Freehand", "Enclose", "reVision"])
                switch a {
                case .keyword("Arclength"):
                    arcLen = try await ed.getPositive("Specify arc length", defaultValue: arcLen); ed.doc.setVariable("REVCLOUDARC", fmt(arcLen)); continue
                case .keyword("reVision"):
                    guard let r = try await ed.getWord("Enter revision for new clouds", defaultValue: rev ?? "1") else { continue }
                    rev = r; ed.doc.setVariable("REVCLOUDREV", r); continue
                case .keyword("Polygonal"): continue
                case .keyword("Rectangular"):
                    let p1 = try await ed.requirePoint("Specify first corner point")
                    let al = arcLen
                    let p2 = try await ed.requirePoint("Specify opposite corner", base: p1) { c in [.polyline(cloud(BBox2(points: [p1, c]).corners, closed: true, arcLength: al))] }
                    let b = BBox2(points: [p1, p2]); guard b.width > 1e-9, b.height > 1e-9 else { return }
                    finish(ed.addEntity(.polyline(cloud(b.corners, closed: true, arcLength: arcLen)))); return
                case .keyword("Freehand"):
                    // Freehand: the cursor path (points picked or streamed while dragging), resampled at the arc length.
                    let p0 = try await ed.requirePoint("Specify start point")
                    var path = [p0]
                    let al = arcLen
                    while let q = try await ed.getPoint("Guide crosshairs along cloud path (Enter to finish)", base: path.last, preview: { c in
                        let r = RevisionClouds.freehand(path + [c], arcLength: al)
                        return r.points.count >= 2 ? [.polyline(cloud(r.points, closed: r.closed, arcLength: al))] : []
                    }).point {
                        path.append(q)
                    }
                    let r = RevisionClouds.freehand(path, arcLength: arcLen)
                    guard r.points.count >= (r.closed ? 3 : 2) else { throw CommandError.invalid("The path is too short for this arc length.") }
                    finish(ed.addEntity(.polyline(cloud(r.points, closed: r.closed, arcLength: arcLen))))
                    ed.print(r.closed ? "Revision cloud finished." : "Revision cloud finished (open)."); return
                case .keyword("Enclose"):
                    let ids = try await ed.getSelection("Select objects to enclose")
                    ed.selection = []
                    let margin = try await ed.getPositive("Specify offset from the objects", defaultValue: arcLen * 0.5, allowZero: true)
                    guard let box = RevisionClouds.enclosure(ids, doc: ed.doc, margin: margin) else { throw CommandError.invalid("Nothing selected.") }
                    finish(ed.addEntity(.polyline(cloud(box, closed: true, arcLength: arcLen))), hosts: ids)
                    ed.print("Revision cloud attached to \(ids.count) object(s)."); return
                case .keyword("Object"):
                    guard case .pick(let pk) = try await ed.pickObject("Select object"), let e = ed.doc.entity(pk.id) else { return }
                    let closed = CommandHelpers.closedLoop(e.geometry) != nil
                    var pts = GeometryOps.tessellate(e.geometry, doc: ed.doc).first ?? []
                    if closed, pts.count > 1, pts.first!.isClose(pts.last!, tol: 1e-6) { pts.removeLast() }
                    guard pts.count >= 2 else { return }
                    // Simplify dense curves so arcs keep roughly the requested length.
                    var simp: [Vec2] = [pts[0]]
                    for p in pts.dropFirst() where p.distance(to: simp.last!) >= arcLen * 0.5 { simp.append(p) }
                    if !closed, let l = pts.last, simp.last != l { simp.append(l) }
                    guard let i = ed.doc.entityIndex(pk.id) else { return }
                    ed.doc.entities[i].geometry = .polyline(cloud(simp.count >= 2 ? simp : pts, closed: closed, arcLength: arcLen))
                    finish(pk.id)
                    ed.print("Revision cloud finished."); return
                case .point(let p):
                    var pts = [p]
                    while true {
                        let cur = pts, al = arcLen
                        guard let q = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(cloud(cur + [c], closed: false, arcLength: al))] }).point else { break }
                        pts.append(q)
                    }
                    guard pts.count >= 3 else { throw CommandError.invalid("A revision cloud needs at least three points.") }
                    finish(ed.addEntity(.polyline(cloud(pts, closed: true, arcLength: arcLen)))); return
                default: return
                }
            }
        },
    ] }

    // MARK: - Fills, boundaries, tables
    @MainActor static func hatchCurves(_ ed: Editor) -> [Geometry] {
        ed.doc.entities.filter { ed.doc.isVisible(layer: $0.layer) }.map(\.geometry)
    }

    static var fills: [CommandDef] { [
        CommandDef("HATCH", aliases: ["H", "BHATCH", "BH"], category: "Draw", summary: "Fills an enclosed area or selected objects with a hatch pattern or solid fill.") { ed in
            var pattern = ed.doc.variable("HPNAME") ?? "ANSI31"
            var scale = ed.variableDouble("HPSCALE", 1)
            var angle = rad(ed.variableDouble("HPANG", 0))
            var fill: ColorRef? = ed.doc.variable("HPCOLOR").flatMap { ColorRef.parse($0) }
            var created: [EntityID] = []
            @MainActor func make(_ loops: [[PolyVertex]]) {
                let id = ed.addEntity(.hatch(HatchGeom(loops: loops, pattern: pattern, scale: scale, angle: angle, fill: fill)))
                created.append(id)
                // HPORIGIN: pattern origin for new hatches (0,0 = default).
                if let o = DraftProps.point(ed.doc.variable("HPORIGIN")), o != .zero, let i = ed.doc.entityIndex(id) {
                    ed.doc.entities[i].props[DraftRendering.hatchOriginProp] = DraftProps.text(o)
                }
                // HPTYPE: model (real size) or drafting (paper size) patterns for new hatches (ANN-071).
                if let t = ed.doc.variable("HPTYPE"), pattern.uppercased() != "SOLID", let i = ed.doc.entityIndex(id) {
                    ed.doc.entities[i].props[HatchPatterns.patternTypeProp] = t
                }
            }
            while true {
                let a = try await ed.getPoint("Pick internal point", keywords: ["Select", "Pattern", "Scale", "Angle", "Color", "Undo"])
                switch a {
                case .point(let p):
                    guard let region = RegionFinder.region(at: p, curves: hatchCurves(ed), doc: ed.doc) else { ed.print("Valid hatch boundary not found."); continue }
                    make([region.outer] + region.holes)
                    if ed.doc.variable("HPASSOC") != "0", let h = created.last {
                        let bnd = AssociativeHatch.boundaryObjects(of: [region.outer] + region.holes, candidates: ed.doc.entities.filter { $0.id != h && ed.doc.isVisible(layer: $0.layer) }, doc: ed.doc)
                        AssociativeHatch.attach(&ed.doc, hatch: h, boundary: bnd, seed: p)
                    }
                    ed.print("Hatch created: area = \(CommandHelpers.areaText(region.area, units: ed.doc.units)).")
                case .keyword("Select"):
                    let ids = try await ed.getEntitySelection("Select objects")
                    var loops = ids.compactMap { ed.doc.entity($0).flatMap { CommandHelpers.closedLoop($0.geometry) } }
                    if loops.isEmpty {
                        let joined = Modify.join(ids.compactMap { ed.doc.entity($0)?.geometry })
                        loops = joined.compactMap { CommandHelpers.closedLoop($0) }
                    }
                    guard !loops.isEmpty else { ed.print("No closed boundary in the selection."); continue }
                    loops.sort { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) > abs(GeometryOps.signedArea(CommandHelpers.loopPoints($1))) }
                    make(loops); ed.selection = []
                    if ed.doc.variable("HPASSOC") != "0", let h = created.last {
                        let bnd = ids.filter { id in
                            guard let e = ed.doc.entity(id) else { return false }
                            if case .hatch = e.geometry { return false }
                            return true
                        }
                        AssociativeHatch.attach(&ed.doc, hatch: h, boundary: bnd, seed: nil)
                    }
                case .keyword("Pattern"):
                    let name = try await ed.getWord("Enter a pattern name or [?]", defaultValue: pattern) ?? pattern
                    if name == "?" { ed.print("Patterns: " + HatchPatterns.allNames.joined(separator: ", ")); continue }
                    pattern = name.uppercased()
                    if !HatchPatterns.allNames.contains(pattern) { ed.print("Note: pattern \(pattern) is not in the built-in library.") }
                    ed.doc.setVariable("HPNAME", pattern)
                case .keyword("Scale"):
                    if let s = try await ed.getReal("Specify a scale for the pattern", defaultValue: scale).value, s > 0 { scale = s; ed.doc.setVariable("HPSCALE", fmt(s)) }
                case .keyword("Angle"):
                    angle = try await ed.getAngle("Specify an angle for the pattern", defaultValue: angle).value ?? angle; ed.doc.setVariable("HPANG", fmt(deg(angle)))
                case .keyword("Color"):
                    if let c = try await ed.getWord("Enter fill color (ByLayer, 1-255, #RRGGBB)", defaultValue: fill?.text ?? "ByLayer"), let cr = ColorRef.parse(c) {
                        fill = cr == .byLayer ? nil : cr; ed.doc.setVariable("HPCOLOR", cr.text)
                    }
                case .keyword("Undo"):
                    if let l = created.popLast() { ed.doc.remove(ids: [l]) }
                default: return
                }
            }
        },
        CommandDef("BOUNDARY", aliases: ["BO", "BPOLY"], category: "Draw", summary: "Creates closed polylines from the area enclosed around a picked point.") { ed in
            while let p = try await ed.getPoint("Pick internal point").point {
                guard let region = RegionFinder.region(at: p, curves: hatchCurves(ed), doc: ed.doc) else { ed.print("Valid boundary not found."); continue }
                for loop in [region.outer] + region.holes { ed.addEntity(.polyline(PolylineGeom(loop, closed: true))) }
                ed.print("BOUNDARY created \(1 + region.holes.count) polyline(s), area = \(CommandHelpers.areaText(region.area, units: ed.doc.units)).")
            }
        },
        CommandDef("REGION", aliases: ["REG"], category: "Draw", summary: "Converts closed chains of lines/arcs into closed polylines (regions).") { ed in
            let ids = try await ed.getEntitySelection()
            let geoms = ids.compactMap { ed.doc.entity($0) }
            guard !geoms.isEmpty else { return }
            let layer = geoms[0].layer
            let joined = Modify.join(geoms.map(\.geometry))
            var count = 0
            var used = Set<EntityID>()
            for g in joined {
                guard let loop = CommandHelpers.closedLoop(g) else { continue }
                ed.addEntity(.polyline(PolylineGeom(loop, closed: true)), layer: layer); count += 1
            }
            if count > 0 {
                for e in geoms {
                    switch e.geometry { case .line, .arc, .polyline, .spline, .circle, .ellipse: used.insert(e.id); default: break }
                }
                ed.doc.remove(ids: used)
            }
            ed.selection = []
            ed.print("\(count) region(s) created.")
        },
        CommandDef("WIPEOUT", category: "Draw", summary: "Creates a masking area (solid background fill) that covers objects beneath.") { ed in
            let a = try await ed.getPoint("Specify first point", keywords: ["Polyline"])
            var pts: [Vec2] = []
            switch a {
            case .keyword("Polyline"):
                guard case .pick(let pk) = try await ed.pickObject("Select a closed polyline"), let e = ed.doc.entity(pk.id), let loop = CommandHelpers.closedLoop(e.geometry) else { throw CommandError.invalid("Select a closed polyline.") }
                pts = CommandHelpers.loopPoints(loop)
                if try await ed.getYesNo("Erase polyline?", defaultValue: false) { ed.doc.remove(ids: [pk.id]) }
            case .point(let p):
                pts = [p]
                while true {
                    let cur = pts
                    guard let q = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(PolylineGeom(points: cur + [c], closed: true))] }).point else { break }
                    pts.append(q)
                }
            default: return
            }
            guard pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-9 else { throw CommandError.invalid("A wipeout needs at least three non-collinear points.") }
            let id = ed.addEntity(.hatch(HatchGeom(loops: [pts.map { PolyVertex($0) }], pattern: "SOLID", fill: .rgb(255, 255, 255))))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["wipeout"] = "1" }
        },
        CommandDef("TABLE", aliases: ["TB"], category: "Draw", summary: "Inserts an empty table.") { ed in
            let th = ed.settings.textHeight
            guard let cols = try await ed.getInteger("Enter number of columns", defaultValue: 5), cols > 0, cols <= 200,
                  let rows = try await ed.getInteger("Enter number of data rows", defaultValue: 5), rows > 0, rows <= 5000 else { throw CommandError.invalid("Invalid table size.") }
            let cw = try await ed.getPositive("Specify column width", defaultValue: th * 10)
            let rh = try await ed.getPositive("Specify row height", defaultValue: th * 2)
            let o = try await ed.requirePoint("Specify insertion point") { p in
                [.table(TableGeom(origin: p, columnWidths: Array(repeating: cw, count: cols), rowHeight: rh, cells: Array(repeating: Array(repeating: "", count: cols), count: rows + 1), textHeight: th))] }
            let title = try await ed.getString("Enter table title", defaultValue: "")
            var cells = Array(repeating: Array(repeating: "", count: cols), count: rows + 1)
            if let t = title, !t.isEmpty { cells[0][0] = t }
            let tid = ed.addEntity(.table(TableGeom(origin: o, columnWidths: Array(repeating: cw, count: cols), rowHeight: rh, cells: cells, textHeight: th)))
            // New tables follow the current table style (ANN-058).
            if let st = ed.doc.variable("CTABLESTYLE"), st.caseInsensitiveCompare("Standard") != .orderedSame, TableStyle.named(st, ed.doc) != nil, let i = ed.doc.entityIndex(tid) {
                ed.doc.entities[i].props[TableStyle.prop] = st
            }
        },
    ] }

    // MARK: - 3D solids
    static var solids: [CommandDef] { [
        CommandDef("BOX", category: "Draw", summary: "Creates a 3D solid box.") { ed in
            let z = elevation(ed)
            let a = try await ed.getPoint("Specify first corner", keywords: ["Center"])
            var p1: Vec2, p2: Vec2
            switch a {
            case .keyword("Center"):
                let c = try await ed.requirePoint("Specify center")
                let k = try await ed.requirePoint("Specify corner", base: c) { p in [.polyline(PolylineGeom(points: BBox2(points: [p, c * 2 - p]).corners, closed: true))] }
                p1 = c * 2 - k; p2 = k
            case .point(let p):
                p1 = p
                let r = try await ed.getPoint("Specify other corner", base: p, keywords: ["Cube", "Length"]) { c in [.polyline(PolylineGeom(points: BBox2(points: [p, c]).corners, closed: true))] }
                switch r {
                case .point(let q): p2 = q
                case .keyword("Cube"):
                    let l = try await ed.getPositive("Specify length", base: p, defaultValue: 1000)
                    let b = SolidGeom(kind: .box, origin: Vec3(p.x, p.y, z), size: Vec3(l, l, l))
                    ed.addEntity(.solid(b)); return
                case .keyword("Length"):
                    let l = try await ed.getPositive("Specify length", base: p, defaultValue: 1000)
                    let w = try await ed.getPositive("Specify width", base: p, defaultValue: l)
                    p2 = p + Vec2(l, w)
                default: return
                }
            default: return
            }
            let b = BBox2(points: [p1, p2])
            guard b.width > 1e-9, b.height > 1e-9 else { throw CommandError.invalid("Box base has zero area.") }
            let h = try await ed.getDistance("Specify height", base: b.center, defaultValue: ed.variableDouble("BOXHEIGHT", 1000)).value ?? 1000
            guard abs(h) > 1e-9 else { throw CommandError.invalid("Height must not be zero.") }
            ed.doc.setVariable("BOXHEIGHT", fmt(h))
            ed.addEntity(.solid(SolidGeom(kind: .box, origin: Vec3(b.min.x, b.min.y, h < 0 ? z + h : z), size: Vec3(b.width, b.height, abs(h)))))
        },
        CommandDef("CONE", category: "Draw", summary: "Creates a 3D solid cone or frustum.") { ed in
            let c = try await ed.requirePoint("Specify center point of base")
            guard let radius = try await ed.getDistance("Specify base radius", base: c, preview: { p in [.circle(CircleGeom(c, c.distance(to: p)))] }).value, radius > 0 else { return }
            var top = 0.0
            var hAns = try await ed.getDistance("Specify height", base: c, defaultValue: ed.variableDouble("BOXHEIGHT", 1000), keywords: ["Top radius"])
            if case .keyword = hAns {
                top = try await ed.getPositive("Specify top radius", defaultValue: 0, allowZero: true)
                hAns = try await ed.getDistance("Specify height", base: c, defaultValue: ed.variableDouble("BOXHEIGHT", 1000))
            }
            guard let h = hAns.value, abs(h) > 1e-9 else { throw CommandError.invalid("Height must not be zero.") }
            let z = elevation(ed)
            ed.addEntity(.solid(SolidGeom(kind: .cone, origin: Vec3(c.x, c.y, h < 0 ? z + h : z), size: Vec3(radius, top, abs(h)))))
        },
        CommandDef("SPHERE", category: "Draw", summary: "Creates a 3D solid sphere.") { ed in
            let c = try await ed.requirePoint("Specify center point")
            guard let r = try await ed.getDistance("Specify radius", base: c, preview: { p in [.circle(CircleGeom(c, c.distance(to: p)))] }).value, r > 0 else { throw CommandError.invalid("Radius must be positive.") }
            ed.addEntity(.solid(SolidGeom(kind: .sphere, origin: Vec3(c.x, c.y, elevation(ed)), size: Vec3(r, r, r))))
        },
    ] }
}
