// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Editor input helpers shared by the command set

extension Editor {
    /// A single word/name (quotes allow spaces in scripts). Keywords are matched by their shortcut. nil on Enter.
    func getWord(_ msg: String, defaultValue: String? = nil, keywords: [String] = []) async throws -> String? {
        let r = await ask(InputRequest(msg, kinds: [.keyword, .string], keywords: keywords, defaultValue: defaultValue))
        switch r {
        case .keyword(let k): return k
        case .text(let t):
            let s = t.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { return defaultValue }
            if !keywords.isEmpty, let k = InputParser.matchKeyword(s, keywords) { return k }
            return s
        case .number(let d): return fmt(d)
        case .point(let p): return p.description
        case .selection(let ids): return ids.map { "#\($0)" }.joined(separator: ",")
        case .enter: return defaultValue
        case .cancel: throw CommandError.cancelled
        }
    }

    /// A plain number (scale factors, counts with decimals). Accepts arithmetic.
    func getReal(_ msg: String, defaultValue: Double? = nil, keywords: [String] = []) async throws -> NumberAnswer {
        var kinds: Set<InputRequest.Kind> = [.distance]
        if !keywords.isEmpty { kinds.insert(.keyword) }
        let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords, defaultValue: defaultValue.map { fmt($0) }))
        switch r {
        case .number(let d): return .value(d)
        case .keyword(let k): return .keyword(k)
        case .enter: if let d = defaultValue { return .value(d) }; return .none
        case .cancel: throw CommandError.cancelled
        default: return defaultValue.map { .value($0) } ?? .none
        }
    }

    /// Positive distance with validation (re-asks on invalid values in interactive use).
    func getPositive(_ msg: String, base: Vec2? = nil, defaultValue: Double, allowZero: Bool = false) async throws -> Double {
        for _ in 0..<20 {
            let v = try await getDistance(msg, base: base, defaultValue: defaultValue).value ?? defaultValue
            if v > 0 || (allowZero && v == 0) { return v }
            print(allowZero ? "Value must be zero or positive." : "Value must be positive.")
        }
        return defaultValue
    }

    func getYesNo(_ msg: String, defaultValue: Bool) async throws -> Bool {
        let k = try await getKeyword(msg, ["Yes", "No"], defaultValue: defaultValue ? "Yes" : "No")
        return (k ?? (defaultValue ? "Yes" : "No")) == "Yes"
    }

    public struct Pick { public var id: EntityID; public var point: Vec2 }
    public enum PickAnswer { case pick(Pick), keyword(String), none }

    /// Picks one object with the point used to pick it (needed by TRIM, FILLET, OFFSET, BREAK...).
    func pickObject(_ msg: String, keywords: [String] = [], filter: ((EntityID) -> Bool)? = nil) async throws -> PickAnswer {
        var tries = 0
        while tries < 100 {
            tries += 1
            var kinds: Set<InputRequest.Kind> = [.entity, .point]
            if !keywords.isEmpty { kinds.insert(.keyword) }
            let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords))
            switch r {
            case .point(let p):
                if let id = pickFiltered(at: p, filter: filter) { return .pick(Pick(id: id, point: p)) }
                print("No suitable object found.")
            case .selection(let ids):
                if let id = ids.first(where: { isSelectable($0) && (filter?($0) ?? true) }) {
                    return .pick(Pick(id: id, point: representativePoint(id)))
                }
                print("Object is not suitable or is on a locked layer.")
            case .keyword(let k): return .keyword(k)
            case .enter: return .none
            case .cancel: throw CommandError.cancelled
            default: return .none
            }
        }
        return .none
    }

    /// Topmost selectable object near a point that passes a filter (entities and elements of the current level).
    func pickFiltered(at p: Vec2, filter: ((EntityID) -> Bool)?, tolerance: Double? = nil) -> EntityID? {
        let tol = tolerance ?? pickTolerance
        var best: (EntityID, Double)?
        for e in doc.entities where doc.isEditable(layer: e.layer) && (filter?(e.id) ?? true) {
            let d = GeometryOps.distance(from: p, to: e.geometry, doc: doc)
            if d <= tol, d < (best?.1 ?? .infinity) { best = (e.id, d) }
        }
        for el in doc.elements where doc.isEditable(layer: el.layer) && el.level == doc.currentLevel && (filter?(el.id) ?? true) {
            var d = CommandHelpers.elementDistance(p, el, doc: doc)
            // Openings sit on top of their wall: prefer them when close.
            if case .opening = el.geometry { d = max(0, d - tol * 0.5) }
            if d <= tol, d < (best?.1 ?? .infinity) { best = (el.id, d) }
        }
        return best?.0
    }

    /// A point on an object, used when it was chosen by ID.
    func representativePoint(_ id: EntityID) -> Vec2 {
        if let e = doc.entity(id) {
            let pls = GeometryOps.tessellate(e.geometry, doc: doc)
            if let pl = pls.first(where: { $0.count > 1 }) { return CommandHelpers.pointAlong(pl, fraction: 0.5).0 }
            return pls.first?.first ?? .zero
        }
        if let el = doc.element(id) {
            let f = CommandHelpers.footprint(el, doc: doc)
            if f.count >= 2 { return CommandHelpers.axisMidpoint(el, doc: doc) ?? GeometryOps.centroid(f) }
        }
        return .zero
    }

    /// Adds a drawing entity on the current layer with the current color / linetype / lineweight.
    @discardableResult
    func addEntity(_ g: Geometry, layer: String? = nil) -> EntityID {
        var e = Entity(layer: layer ?? doc.currentLayer, geometry: g)
        if let c = doc.variable("CECOLOR"), let cr = ColorRef.parse(c) { e.color = cr }
        if let lt = doc.variable("CELTYPE"), !lt.isEmpty, lt.lowercased() != "bylayer" { e.linetype = lt }
        if let lw = doc.variable("CELWEIGHT"), let v = Double(lw), v >= 0 { e.lineweight = v }
        return doc.add(e)
    }

    /// Selection limited to drawing entities (BIM elements are skipped with a message).
    func getEntitySelection(_ msg: String = "Select objects") async throws -> [EntityID] {
        let ids = try await getSelection(msg)
        let ents = ids.filter { doc.entity($0) != nil }
        if ents.count < ids.count { print("\(ids.count - ents.count) building element(s) ignored.") }
        return ents
    }

    /// Number setting stored as a document variable, with a fallback default.
    func variableDouble(_ name: String, _ def: Double) -> Double { doc.variable(name).flatMap { Double($0) } ?? def }

    var currentLevelHeight: Double { doc.level(doc.currentLevel)?.height ?? 3000 }

    /// Rubber-band preview of objects transformed by t (entities, and element footprints).
    func transformedPreview(_ ids: [EntityID], _ t: Transform2D) -> [Geometry] {
        var out: [Geometry] = []
        for id in ids.prefix(400) {
            if let e = doc.entity(id) { out.append(GeometryOps.transform(e.geometry, t)) }
            else if let el = doc.element(id) {
                let f = CommandHelpers.footprint(el, doc: doc)
                if f.count >= 2 { out.append(.polyline(PolylineGeom(points: f.map(t.apply), closed: true))) }
            }
        }
        return out
    }

    /// Applies a transform to objects; with `copy` new objects are created. Returns the IDs of the results.
    @discardableResult
    func transformObjects(_ ids: [EntityID], _ t: Transform2D, copy: Bool) -> [EntityID] {
        var out: [EntityID] = []
        let idSet = Set(ids)
        var wallMap: [EntityID: EntityID] = [:]
        // Entities
        for id in ids {
            guard let i = doc.entityIndex(id) else { continue }
            let g = GeometryOps.transform(doc.entities[i].geometry, t)
            if copy { var e = doc.entities[i]; e.geometry = g; out.append(doc.add(e)) }
            else { doc.entities[i].geometry = g; out.append(id) }
        }
        // Elements (non-openings first so hosts exist)
        let els = ids.compactMap { doc.element($0) }
        for el in els {
            if case .opening = el.geometry { continue }
            let g = CommandHelpers.transform(el.geometry, t)
            if copy {
                var n = el; n.geometry = g; n.id = doc.allocateID(); doc.elements.append(n)
                wallMap[el.id] = n.id; out.append(n.id)
            } else if let i = doc.elementIndex(el.id) { doc.elements[i].geometry = g; out.append(el.id) }
        }
        // Openings: follow their host when it was transformed, otherwise slide along the host wall.
        for el in els {
            guard case .opening(var o) = el.geometry else { continue }
            if let newHost = wallMap[o.hostWall] {
                if copy { o.hostWall = newHost }
            } else if !idSet.contains(o.hostWall), let host = doc.element(o.hostWall), case .wall(let w) = host.geometry {
                let c = CommandHelpers.openingCenter(o, wall: w)
                let moved = t.apply(c)
                let along = (moved - w.centerStart).dot(w.direction)
                o.offset = max(o.width / 2, min(w.length - o.width / 2, along))
            }
            if t.isMirroring { o.flipHand.toggle() }
            if copy {
                var n = el; n.geometry = .opening(o); n.id = doc.allocateID(); doc.elements.append(n); out.append(n.id)
            } else if let i = doc.elementIndex(el.id) { doc.elements[i].geometry = .opening(o); out.append(el.id) }
        }
        // Copy openings hosted by copied walls when they were not selected themselves.
        if copy {
            for el in doc.elements {
                guard case .opening(var o) = el.geometry, let nh = wallMap[o.hostWall], !idSet.contains(el.id) else { continue }
                o.hostWall = nh
                if t.isMirroring { o.flipHand.toggle() }
                var n = el; n.geometry = .opening(o); n.id = doc.allocateID(); doc.elements.append(n)
            }
        }
        return out
    }

    /// Runs command lines one after another (for SCRIPT and agents). Each line is its own undo step.
    public func runScript(_ text: String) async {
        for raw in CommandHelpers.scriptLines(text) {
            await run(raw)
        }
    }
}

// MARK: - Geometry helpers

public enum CommandHelpers {
    static func scriptLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("//") }
    }

    /// Point at a fraction of the length of a polyline, and the tangent direction there.
    static func pointAlong(_ pl: [Vec2], fraction: Double) -> (Vec2, Vec2) {
        let total = zip(pl, pl.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        return pointAt(pl, distance: total * fraction)
    }
    static func pointAt(_ pl: [Vec2], distance s: Double) -> (Vec2, Vec2) {
        guard pl.count > 1 else { return (pl.first ?? .zero, Vec2(1, 0)) }
        var acc = 0.0
        for i in 0..<(pl.count - 1) {
            let l = pl[i].distance(to: pl[i + 1])
            if acc + l >= s - 1e-9 && l > 0 {
                let t = max(0, min(1, (s - acc) / l))
                return (pl[i].lerp(pl[i + 1], t), (pl[i + 1] - pl[i]).normalized)
            }
            acc += l
        }
        let n = pl.count
        return (pl[n - 1], (pl[n - 1] - pl[n - 2]).normalized)
    }
    static func polylineLength(_ pl: [Vec2]) -> Double { zip(pl, pl.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

    /// Circle through three points.
    public static func circleFrom3(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> CircleGeom? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        guard abs(d) > 1e-12 else { return nil }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        let ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        let center = Vec2(ux, uy)
        return CircleGeom(center, center.distance(to: a))
    }

    /// Arc through start, a point on the arc and end (stored counter-clockwise).
    public static func arcFrom3(_ s: Vec2, _ m: Vec2, _ e: Vec2) -> ArcGeom? {
        guard let c = circleFrom3(s, m, e) else { return nil }
        let a0 = (s - c.center).angle, a1 = (e - c.center).angle
        return ArcGeom(c.center, c.radius, a0, a1).flippedIfNeeded(s: s, m: m)
    }

    /// Bulge of a polyline arc segment from `a` to `b` that leaves `a` along `tangent`.
    public static func bulge(from a: Vec2, tangent: Vec2, to b: Vec2) -> Double {
        let chord = b - a
        guard chord.length > geomEpsilon, tangent.length > geomEpsilon else { return 0 }
        var th = chord.angle - tangent.angle
        while th > .pi { th -= 2 * .pi }
        while th <= -.pi { th += 2 * .pi }
        return tan(th / 2)
    }
    /// Bulge of the arc a → m → b.
    public static func bulge3(_ a: Vec2, _ m: Vec2, _ b: Vec2) -> Double {
        guard let c = circleFrom3(a, m, b) else { return 0 }
        let tangentAtA = (a - c.center).perp * ((m - a).cross(b - m) > 0 ? 1 : -1)
        return bulge(from: a, tangent: tangentAtA, to: b)
    }
    /// Tangent direction at the end of a bulge segment.
    public static func endTangent(_ a: Vec2, _ b: Vec2, bulge: Double) -> Vec2 {
        let sweep = 4 * atan(bulge)
        return (b - a).normalized.rotated(by: sweep / 2)
    }
    /// Converts an arc to polyline vertices (start with bulge, end).
    static func arcVertices(_ a: ArcGeom) -> [PolyVertex] {
        let sw = a.sweep
        if sw > .pi * 1.999 {
            let p0 = a.startPoint, p1 = a.center + Vec2.polar(a.radius, a.start + .pi)
            return [PolyVertex(p0, bulge: 1), PolyVertex(p1, bulge: 1), PolyVertex(p0)]
        }
        return [PolyVertex(a.startPoint, bulge: tan(sw / 4)), PolyVertex(a.endPoint)]
    }

    /// Converts a curve to polyline vertices if possible (for PEDIT / JOIN / hatch boundaries).
    static func polylineVertices(_ g: Geometry) -> (vertices: [PolyVertex], closed: Bool)? {
        switch g {
        case .line(let l): return ([PolyVertex(l.a), PolyVertex(l.b)], false)
        case .arc(let a): return (arcVertices(a), false)
        case .polyline(let p): return (p.vertices, p.closed)
        case .circle(let c):
            return ([PolyVertex(c.center + Vec2(c.radius, 0), bulge: 1), PolyVertex(c.center - Vec2(c.radius, 0), bulge: 1)], true)
        case .ellipse(let e): return (GeometryOps.ellipsePoints(e).map { PolyVertex($0) }, e.isFull)
        case .spline(let s): return (GeometryOps.splinePoints(s).map { PolyVertex($0) }, s.closed)
        default: return nil
        }
    }

    /// Closed loop of a closed curve (with bulges when available).
    static func closedLoop(_ g: Geometry) -> [PolyVertex]? {
        switch g {
        case .polyline(let p) where p.closed && p.vertices.count >= 2: return p.vertices
        case .polyline(let p) where p.vertices.count >= 4 && p.vertices.first!.p.isClose(p.vertices.last!.p, tol: 1e-6):
            return Array(p.vertices.dropLast())
        case .circle, .ellipse, .spline:
            guard let v = polylineVertices(g), v.closed else { return nil }
            var vs = v.vertices
            if vs.count > 2, vs.first!.p.isClose(vs.last!.p, tol: 1e-6) { vs.removeLast() }
            return vs
        case .hatch(let h): return h.loops.first
        default: return nil
        }
    }

    static func loopPoints(_ v: [PolyVertex]) -> [Vec2] {
        var pts = GeometryOps.polylinePoints(v, closed: true)
        if pts.count > 1, pts.first!.isClose(pts.last!, tol: 1e-9) { pts.removeLast() }
        return pts
    }

    /// Miter offset of a simple polygon (positive = outward).
    public static func offsetPolygon(_ pts: [Vec2], _ d: Double) -> [Vec2] {
        let n = pts.count
        guard n >= 3 else { return pts }
        let ccw = GeometryOps.signedArea(pts) > 0
        let s = ccw ? -d : d  // outward normal of a CCW polygon is the right-hand side
        var out: [Vec2] = []
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n]
            let n0 = (p1 - p0).normalized.perp * s, n1 = (p2 - p1).normalized.perp * s
            if let x = GeometryOps.lineIntersection(p0 + n0, p1 + n0, p1 + n1, p2 + n1) { out.append(x) }
            else { out.append(p1 + n0) }
        }
        return out
    }

    /// Removes duplicate consecutive and collinear vertices.
    public static func simplify(_ pts: [Vec2], tol: Double = 1e-6) -> [Vec2] {
        var p = pts
        if p.count > 1, p.first!.isClose(p.last!, tol: tol) { p.removeLast() }
        var changed = true
        while changed && p.count > 3 {
            changed = false
            var i = 0
            while i < p.count && p.count > 3 {
                let a = p[(i - 1 + p.count) % p.count], b = p[i], c = p[(i + 1) % p.count]
                if a.isClose(b, tol: tol) || abs((b - a).cross(c - b)) <= tol * max(1, (c - a).length) && (b - a).dot(c - b) >= 0 {
                    p.remove(at: i); changed = true
                } else { i += 1 }
            }
        }
        return p
    }

    // MARK: Formatting

    /// "12.35 m²" (metric) or "132.9 ft²" (imperial) for an area in drawing units.
    public static func areaText(_ a: Double, units: Units) -> String {
        let mm2 = a * units.mm * units.mm
        switch units {
        case .inches, .feet: return String(format: "%.2f ft²", mm2 / (304.8 * 304.8))
        default: return String(format: "%.2f m²", mm2 / 1e6)
        }
    }
    public static func lengthText(_ l: Double, units: Units) -> String {
        let mm = l * units.mm
        switch units {
        case .inches, .feet: return String(format: "%.2f ft", mm / 304.8)
        default: return String(format: "%.2f m", mm / 1000)
        }
    }
    public static func areaMessage(area: Double, perimeter: Double, units: Units) -> String {
        "Area = \(areaText(area, units: units)), Perimeter = \(lengthText(perimeter, units: units))"
    }

    // MARK: BIM element helpers

    static func openingCenter(_ o: OpeningGeom, wall w: WallGeom) -> Vec2 { w.centerStart + w.direction * o.offset }

    /// Plan footprint polygon of a wall (drawn-line justification applied).
    static func wallRect(_ w: WallGeom) -> [Vec2] {
        let d = w.direction, n = d.perp * (w.thickness / 2)
        let a = w.centerStart, b = w.centerEnd
        if abs(w.bulge) > 1e-9 {
            let arc = GeometryOps.bulgeArc(a, b, w.bulge)
            let pts = GeometryOps.arcPoints(center: arc.center, radius: arc.radius, start: arc.start, sweep: arc.sweep)
            let outer = pts.map { p -> Vec2 in let r = (p - arc.center).normalized; return p + r * (w.thickness / 2) }
            let inner = pts.map { p -> Vec2 in let r = (p - arc.center).normalized; return p - r * (w.thickness / 2) }
            return outer + inner.reversed()
        }
        return [a - n, b - n, b + n, a + n]
    }

    /// Plan footprint of any element (used for picking, previews and boundary detection).
    public static func footprint(_ el: BIMElement, doc: ArchiDocument) -> [Vec2] {
        switch el.geometry {
        case .wall(let w):
            let o = PlanRepresentation.wallOutline(el.id, doc: doc)
            return o.count >= 3 ? o : wallRect(w)
        case .curtainWall(let c): return wallRect(WallGeom(start: c.start, end: c.end, thickness: max(c.mullionSize, 50)))
        case .slab(let s): return s.boundary
        case .roof(let r): return r.boundary
        case .space(let s): return s.boundary
        case .railing(let r): return r.path
        case .gridLine(let g): return [g.start, g.end]
        case .beam(let b): return wallRect(WallGeom(start: b.start, end: b.end, thickness: b.width))
        case .column(let c):
            if c.round { return Array(GeometryOps.arcPoints(center: c.position, radius: c.width / 2, start: 0, sweep: 2 * .pi).dropLast()) }
            let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
            return [Vec2(-c.width / 2, -c.depth / 2), Vec2(c.width / 2, -c.depth / 2), Vec2(c.width / 2, c.depth / 2), Vec2(-c.width / 2, c.depth / 2)].map(t.apply)
        case .component(let c):
            let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
            return [Vec2(-c.size.x / 2, -c.size.y / 2), Vec2(c.size.x / 2, -c.size.y / 2), Vec2(c.size.x / 2, c.size.y / 2), Vec2(-c.size.x / 2, c.size.y / 2)].map(t.apply)
        case .stair(let s):
            let d = Vec2.polar(1, s.direction), n = d.perp * (s.width / 2)
            let e = s.start + d * max(s.runLength, s.treadDepth)
            return [s.start - n, e - n, e + n, s.start + n]
        case .opening(let o):
            guard let h = doc.element(o.hostWall), case .wall(let w) = h.geometry else { return [] }
            let c = openingCenter(o, wall: w), d = w.direction * (o.width / 2), n = w.direction.perp * (w.thickness / 2)
            return [c - d - n, c + d - n, c + d + n, c - d + n]
        }
    }

    static func isOpenPath(_ el: BIMElement) -> Bool {
        switch el.geometry { case .railing, .gridLine: return true; default: return false }
    }

    static func axisMidpoint(_ el: BIMElement, doc: ArchiDocument) -> Vec2? {
        switch el.geometry {
        case .wall(let w): return (w.centerStart + w.centerEnd) / 2
        case .curtainWall(let c): return (c.start + c.end) / 2
        case .beam(let b): return (b.start + b.end) / 2
        case .gridLine(let g): return (g.start + g.end) / 2
        case .opening(let o):
            guard let h = doc.element(o.hostWall), case .wall(let w) = h.geometry else { return nil }
            return openingCenter(o, wall: w)
        default: return nil
        }
    }

    /// Distance from a point to an element in plan (0 inside its footprint).
    public static func elementDistance(_ p: Vec2, _ el: BIMElement, doc: ArchiDocument) -> Double {
        let rep = PlanRepresentation.distance(from: p, to: el, doc: doc)
        let f = footprint(el, doc: doc)
        guard !f.isEmpty else { return rep }
        let own: Double
        if isOpenPath(el) { own = GeometryOps.distance(from: p, toPolyline: f) }
        else if f.count >= 3 && GeometryOps.pointInPolygon(p, f) {
            // Rooms and slabs are picked on their edges only (so walls inside stay pickable).
            switch el.geometry {
            case .space, .slab, .roof: own = GeometryOps.distance(from: p, toPolyline: f + [f[0]])
            default: own = 0
            }
        } else { own = GeometryOps.distance(from: p, toPolyline: f + [f[0]]) }
        return min(rep, own)
    }

    /// Applies a 2D transform to a building element (sizes are kept; positions move).
    public static func transform(_ g: BIMGeometry, _ t: Transform2D) -> BIMGeometry {
        let rot = t.rotationAngle, mirror = t.isMirroring
        func dirAngle(_ a: Double) -> Double { t.applyVector(Vec2.polar(1, a)).angle }
        func poly(_ p: [Vec2]) -> [Vec2] { let q = p.map(t.apply); return mirror ? q.reversed() : q }
        switch g {
        case .wall(var w):
            w.start = t.apply(w.start); w.end = t.apply(w.end)
            if mirror {
                w.bulge = -w.bulge
                switch w.justification { case .left: w.justification = .right; case .right: w.justification = .left; default: break }
            }
            return .wall(w)
        case .slab(var s): s.boundary = poly(s.boundary); s.holes = s.holes.map(poly); return .slab(s)
        case .column(var c): c.position = t.apply(c.position); c.rotation = dirAngle(c.rotation); return .column(c)
        case .beam(var b): b.start = t.apply(b.start); b.end = t.apply(b.end); return .beam(b)
        case .opening(var o): if mirror { o.flipHand.toggle() }; return .opening(o)
        case .roof(var r):
            let n = r.boundary.count
            r.boundary = poly(r.boundary)
            if mirror && n > 1 { r.eaveEdge = (n - 2 - r.eaveEdge + n) % n }
            return .roof(r)
        case .stair(var s):
            s.start = t.apply(s.start); s.direction = dirAngle(s.direction); _ = rot
            return .stair(s)
        case .railing(var r): r.path = r.path.map(t.apply); return .railing(r)
        case .space(var s): s.boundary = poly(s.boundary); return .space(s)
        case .curtainWall(var c): c.start = t.apply(c.start); c.end = t.apply(c.end); return .curtainWall(c)
        case .component(var c): c.position = t.apply(c.position); c.rotation = dirAngle(c.rotation); return .component(c)
        case .gridLine(var gl): gl.start = t.apply(gl.start); gl.end = t.apply(gl.end); return .gridLine(gl)
        }
    }

    // MARK: Expression evaluation (CAL)

    /// Evaluates arithmetic with + - * / ^, parentheses, pi, e and functions sqrt, abs, sin, cos, tan (degrees), asin, acos, atan, ln, log, exp, round, floor, ceil, r2d, d2r.
    public static func evaluate(_ s: String) -> Double? {
        var p = Calc(Array(s.lowercased().replacingOccurrences(of: " ", with: "")))
        guard let v = p.expr(), p.i == p.c.count, v.isFinite else { return nil }
        return v
    }
    struct Calc {
        var c: [Character]; var i = 0
        init(_ c: [Character]) { self.c = c }
        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" { let op = c[i]; i += 1; guard let r = term() else { return nil }; v = op == "+" ? v + r : v - r }
            return v
        }
        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < c.count, c[i] == "*" || c[i] == "/" { let op = c[i]; i += 1; guard let r = power() else { return nil }; v = op == "*" ? v * r : v / r }
            return v
        }
        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if i < c.count, c[i] == "^" { i += 1; guard let e = power() else { return nil }; return pow(b, e) }
            return b
        }
        mutating func unary() -> Double? {
            if i < c.count, c[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < c.count, c[i] == "+" { i += 1; return unary() }
            return atom()
        }
        mutating func atom() -> Double? {
            if i < c.count, c[i] == "(" { i += 1; let v = expr(); guard i < c.count, c[i] == ")" else { return nil }; i += 1; return v }
            if i < c.count, c[i].isLetter {
                var name = ""
                while i < c.count, c[i].isLetter || c[i].isNumber { name.append(c[i]); i += 1 }
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                guard i < c.count, c[i] == "(" else { return nil }
                i += 1
                guard let a = expr(), i < c.count, c[i] == ")" else { return nil }
                i += 1
                switch name {
                case "sqrt": return a.squareRoot()
                case "abs": return abs(a)
                case "sin": return sin(rad(a))
                case "cos": return cos(rad(a))
                case "tan": return tan(rad(a))
                case "asin": return deg(asin(a))
                case "acos": return deg(acos(a))
                case "atan": return deg(atan(a))
                case "ln": return log(a)
                case "log": return log10(a)
                case "exp": return exp(a)
                case "round": return a.rounded()
                case "floor": return a.rounded(.down)
                case "ceil": return a.rounded(.up)
                case "r2d": return deg(a)
                case "d2r": return rad(a)
                default: return nil
                }
            }
            var s = ""
            while i < c.count, "0123456789.".contains(c[i]) || (c[i] == "e" && !s.isEmpty && i + 1 < c.count && "0123456789-+".contains(c[i + 1])) {
                s.append(c[i]); i += 1
                if s.last == "e", i < c.count, c[i] == "-" || c[i] == "+" { s.append(c[i]); i += 1 }
            }
            if let v = Double(s) { return v }
            // feet-inch or plain number forms handled by the command-line parser
            return nil
        }
    }
}

extension ArcGeom {
    /// Ensures the arc passes through `m` (swaps start/end otherwise).
    func flippedIfNeeded(s: Vec2, m: Vec2) -> ArcGeom {
        let am = normAngle((m - center).angle - start)
        if am <= sweep + 1e-9 { return self }
        return ArcGeom(center, radius, end, start)
    }
}

// MARK: - Boundary detection (HATCH, BOUNDARY, ROOM, SLAB from walls)

public enum RegionFinder {
    public struct Region: Equatable {
        public var outer: [PolyVertex]
        public var holes: [[PolyVertex]]
        public var outerPoints: [Vec2] { CommandHelpers.loopPoints(outer) }
        public var area: Double {
            abs(GeometryOps.signedArea(outerPoints)) - holes.reduce(0) { $0 + abs(GeometryOps.signedArea(CommandHelpers.loopPoints($1))) }
        }
    }

    /// Smallest region around `p` bounded by the given curves: closed curves are used directly (keeping arcs),
    /// open curves (lines, arcs, open polylines) are combined into a planar graph and the enclosing face is traced.
    public static func region(at p: Vec2, curves: [Geometry], doc: ArchiDocument?) -> Region? {
        var closed: [[PolyVertex]] = []
        var polylines: [[Vec2]] = []
        for g in curves {
            switch g {
            case .text, .dimension, .insert, .table, .image, .solid, .point, .hatch: continue
            default: break
            }
            if let loop = CommandHelpers.closedLoop(g) { closed.append(loop) }
            for pl in GeometryOps.tessellate(g, doc: doc) where pl.count > 1 { polylines.append(pl) }
        }
        // Candidate 1: smallest closed curve containing p.
        var best: (loop: [PolyVertex], area: Double)?
        for l in closed {
            let pts = CommandHelpers.loopPoints(l)
            guard pts.count >= 3, GeometryOps.pointInPolygon(p, pts) else { continue }
            let a = abs(GeometryOps.signedArea(pts))
            if a < (best?.area ?? .infinity) { best = (l, a) }
        }
        // Candidate 2: face of the planar arrangement.
        var faceOuter: [Vec2]? = nil
        var faceHoles: [[Vec2]] = []
        if let f = planarFace(containing: p, polylines: polylines) { faceOuter = f.outer; faceHoles = f.holes }

        var outer: [PolyVertex]
        var outerPts: [Vec2]
        if let fo = faceOuter, abs(GeometryOps.signedArea(fo)) < (best?.area ?? .infinity) * (1 - 1e-6) {
            outerPts = CommandHelpers.simplify(fo)
            outer = outerPts.map { PolyVertex($0) }
        } else if let b = best {
            outer = b.loop; outerPts = CommandHelpers.loopPoints(b.loop)
        } else { return nil }

        // Islands: closed curves inside the outer boundary that do not contain p (outermost only).
        var holes: [[PolyVertex]] = []
        var holePts: [[Vec2]] = []
        let outerArea = abs(GeometryOps.signedArea(outerPts))
        let candidates = closed.map { ($0, CommandHelpers.loopPoints($0)) }
            .filter { $0.1.count >= 3 && !GeometryOps.pointInPolygon(p, $0.1) }
            .sorted { abs(GeometryOps.signedArea($0.1)) > abs(GeometryOps.signedArea($1.1)) }
        for (loop, pts) in candidates {
            let a = abs(GeometryOps.signedArea(pts))
            guard a < outerArea * (1 - 1e-9), pts.allSatisfy({ GeometryOps.pointInPolygon($0, outerPts) || GeometryOps.distance(from: $0, toPolyline: outerPts + [outerPts[0]]) < 1e-6 }) else { continue }
            if holePts.contains(where: { h in pts.allSatisfy { GeometryOps.pointInPolygon($0, h) } }) { continue }
            holes.append(loop); holePts.append(pts)
        }
        for h in faceHoles {
            let a = abs(GeometryOps.signedArea(h))
            guard a > 1e-9 else { continue }
            if holePts.contains(where: { hp in abs(abs(GeometryOps.signedArea(hp)) - a) < a * 1e-3 && GeometryOps.pointInPolygon(GeometryOps.centroid(h), hp) }) { continue }
            let s = CommandHelpers.simplify(h)
            holes.append(s.map { PolyVertex($0) }); holePts.append(s)
        }
        return Region(outer: outer, holes: holes)
    }

    /// Traces the face of the planar arrangement of polylines that contains p. Returns nil if p is in the unbounded face.
    public static func planarFace(containing p: Vec2, polylines: [[Vec2]]) -> (outer: [Vec2], holes: [[Vec2]])? {
        // 1. Segments
        var segs: [(Vec2, Vec2)] = []
        var ext = BBox2.empty
        for pl in polylines {
            for i in 0..<(pl.count - 1) where pl[i].distance(to: pl[i + 1]) > 1e-9 { segs.append((pl[i], pl[i + 1])); ext.add(pl[i]); ext.add(pl[i + 1]) }
        }
        guard segs.count >= 3, segs.count < 60000 else { return nil }
        let size = max(ext.width, ext.height, 1)
        let tol = size * 1e-9 + 1e-9
        // 2. Split at intersections
        var params: [[Double]] = Array(repeating: [0, 1], count: segs.count)
        let boxes = segs.map { BBox2(points: [$0.0, $0.1]).expanded(by: tol * 10) }
        let order = (0..<segs.count).sorted { boxes[$0].min.x < boxes[$1].min.x }
        for oi in 0..<order.count {
            let i = order[oi]
            var oj = oi + 1
            while oj < order.count {
                let j = order[oj]; oj += 1
                if boxes[j].min.x > boxes[i].max.x { break }
                guard boxes[i].intersects(boxes[j]) else { continue }
                let (a, b) = segs[i], (c, d) = segs[j]
                let r = b - a, s = d - c
                let den = r.cross(s)
                if abs(den) > 1e-12 * r.length * s.length {
                    let t = (c - a).cross(s) / den, u = (c - a).cross(r) / den
                    let et = tol / max(r.length, 1e-12), eu = tol / max(s.length, 1e-12)
                    if t >= -et && t <= 1 + et && u >= -eu && u <= 1 + eu {
                        params[i].append(min(1, max(0, t))); params[j].append(min(1, max(0, u)))
                    }
                } else {
                    // Collinear overlap: split each at the other's endpoints.
                    let rl = r.lengthSquared, sl = s.lengthSquared
                    guard rl > 0, sl > 0, abs((c - a).cross(r)) / r.length < tol * 10 else { continue }
                    for q in [c, d] { let t = (q - a).dot(r) / rl; if t > 0 && t < 1 { params[i].append(t) } }
                    for q in [a, b] { let u = (q - c).dot(s) / sl; if u > 0 && u < 1 { params[j].append(u) } }
                }
            }
        }
        // 3. Vertices (merged within tolerance) and undirected edges
        var verts: [Vec2] = []
        var index: [String: Int] = [:]
        let q = max(size * 1e-7, 1e-6)
        func vid(_ v: Vec2) -> Int {
            let kx = Int((v.x / q).rounded()), ky = Int((v.y / q).rounded())
            for dx in -1...1 { for dy in -1...1 { if let i = index["\(kx + dx),\(ky + dy)"], verts[i].distance(to: v) <= q * 1.5 { return i } } }
            verts.append(v); index["\(kx),\(ky)"] = verts.count - 1
            return verts.count - 1
        }
        var edgeSet = Set<[Int]>()
        for (k, s) in segs.enumerated() {
            let ts = Array(Set(params[k])).sorted()
            var prev = vid(s.0.lerp(s.1, ts[0]))
            for t in ts.dropFirst() {
                let cur = vid(s.0.lerp(s.1, t))
                if cur != prev { edgeSet.insert([min(prev, cur), max(prev, cur)]) }
                prev = cur
            }
        }
        var adj: [[Int]] = Array(repeating: [], count: verts.count)
        for e in edgeSet { adj[e[0]].append(e[1]); adj[e[1]].append(e[0]) }
        // 4. Prune dangling edges
        var stack = (0..<verts.count).filter { adj[$0].count == 1 }
        while let v = stack.popLast() {
            guard adj[v].count == 1 else { continue }
            let w = adj[v][0]
            adj[v] = []; adj[w].removeAll { $0 == v }
            if adj[w].count == 1 { stack.append(w) }
        }
        for v in 0..<verts.count { adj[v].sort { (verts[$0] - verts[v]).angle < (verts[$1] - verts[v]).angle } }
        // Component labels (to skip islands already handled)
        var comp = Array(repeating: -1, count: verts.count)
        var cid = 0
        for v in 0..<verts.count where comp[v] < 0 && !adj[v].isEmpty {
            var st = [v]; comp[v] = cid
            while let x = st.popLast() { for y in adj[x] where comp[y] < 0 { comp[y] = cid; st.append(y) } }
            cid += 1
        }
        // 5. Ray cast to +x and trace faces
        var hits: [(x: Double, u: Int, v: Int)] = []
        for v in 0..<verts.count {
            for w in adj[v] where v < w {
                let a = verts[v], b = verts[w]
                if (a.y > p.y) != (b.y > p.y) {
                    let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                    if x > p.x { hits.append(a.y < b.y ? (x, v, w) : (x, w, v)) }
                }
            }
        }
        hits.sort { $0.x < $1.x }
        var holes: [[Vec2]] = []
        var skip = Set<Int>()
        for h in hits {
            if skip.contains(comp[h.u]) { continue }
            guard let loop = traceFace(from: h.u, to: h.v, verts: verts, adj: adj) else { continue }
            let pts = loop.map { verts[$0] }
            let area = GeometryOps.signedArea(pts)
            if area > 0 && GeometryOps.pointInPolygon(p, pts) { return (pts, holes) }
            if area <= 0 { holes.append(pts.reversed()); skip.insert(comp[h.u]) }
        }
        return nil
    }

    /// Follows half-edges keeping the face on the left.
    static func traceFace(from u0: Int, to v0: Int, verts: [Vec2], adj: [[Int]]) -> [Int]? {
        var loop: [Int] = [u0]
        var u = u0, v = v0
        var steps = 0
        while steps < 200000 {
            steps += 1
            if v == u0 && loop.count > 1 {
                // Closed when we return along the starting half-edge.
                if let nx = nextEdge(u, v, adj: adj), nx == v0 { return loop }
            }
            loop.append(v)
            guard let w = nextEdge(u, v, adj: adj) else { return nil }
            u = v; v = w
            if u == u0 && v == v0 { loop.removeLast(); return loop }
        }
        return nil
    }
    static func nextEdge(_ u: Int, _ v: Int, adj: [[Int]]) -> Int? {
        let out = adj[v]
        guard let idx = out.firstIndex(of: u), !out.isEmpty else { return nil }
        return out[(idx - 1 + out.count) % out.count]
    }

    /// Room boundary from wall faces around a point (walls and curtain walls on the given level).
    public static func roomBoundary(at p: Vec2, doc: ArchiDocument, level: Int, extraCurves: [Geometry] = []) -> [Vec2]? {
        var pls: [[Vec2]] = []
        for el in doc.elements where el.level == level {
            switch el.geometry {
            case .wall, .curtainWall:
                let f = CommandHelpers.footprint(el, doc: doc)
                if f.count >= 3 { pls.append(f + [f[0]]) }
            default: break
            }
        }
        for g in extraCurves { pls.append(contentsOf: GeometryOps.tessellate(g, doc: doc).filter { $0.count > 1 }) }
        guard let f = planarFace(containing: p, polylines: pls) else { return nil }
        let s = CommandHelpers.simplify(f.outer)
        return s.count >= 3 ? s : nil
    }
}

// MARK: - Generic property access (SETPROP, LIST, the Properties panel, scripts)

/// Named, string-valued properties of entities and building elements. Angles are in degrees, lengths in drawing units.
public enum PropertyAccess {
    struct P<T> {
        var name: String
        var get: (T) -> String
        var set: ((inout T, String) -> Bool)?
    }

    static func num(_ s: String) -> Double? { InputParser.parseNumber(s) ?? CommandHelpers.evaluate(s) }
    static func bool(_ s: String) -> Bool? {
        switch s.lowercased() { case "1", "true", "yes", "y", "on": return true; case "0", "false", "no", "n", "off": return false; default: return nil }
    }
    static func d<T>(_ name: String, _ kp: WritableKeyPath<T, Double>, min: Double? = nil) -> P<T> {
        P(name: name, get: { fmt($0[keyPath: kp]) }, set: { t, v in
            guard let x = num(v), x.isFinite else { return false }
            if let m = min, x < m { return false }
            t[keyPath: kp] = x; return true })
    }
    static func angle<T>(_ name: String, _ kp: WritableKeyPath<T, Double>) -> P<T> {
        P(name: name, get: { fmt(deg($0[keyPath: kp])) }, set: { t, v in guard let x = num(v) else { return false }; t[keyPath: kp] = rad(x); return true })
    }
    static func b<T>(_ name: String, _ kp: WritableKeyPath<T, Bool>) -> P<T> {
        P(name: name, get: { $0[keyPath: kp] ? "true" : "false" }, set: { t, v in guard let x = bool(v) else { return false }; t[keyPath: kp] = x; return true })
    }
    static func s<T>(_ name: String, _ kp: WritableKeyPath<T, String>) -> P<T> {
        P(name: name, get: { $0[keyPath: kp] }, set: { t, v in t[keyPath: kp] = v; return true })
    }
    static func i<T>(_ name: String, _ kp: WritableKeyPath<T, Int>, min: Int = Int.min) -> P<T> {
        P(name: name, get: { "\($0[keyPath: kp])" }, set: { t, v in guard let x = num(v), Int(x.rounded()) >= min else { return false }; t[keyPath: kp] = Int(x.rounded()); return true })
    }
    static func ro<T>(_ name: String, _ f: @escaping (T) -> String) -> P<T> { P(name: name, get: f, set: nil) }
    static func e<T, E: RawRepresentable & CaseIterable>(_ name: String, _ kp: WritableKeyPath<T, E>) -> P<T> where E.RawValue == String {
        P(name: name, get: { $0[keyPath: kp].rawValue }, set: { t, v in
            guard let x = E.allCases.first(where: { $0.rawValue.lowercased() == v.lowercased() }) ?? E.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(v.lowercased()) }) else { return false }
            t[keyPath: kp] = x; return true })
    }
    static func v<T>(_ name: String, _ kp: WritableKeyPath<T, Vec2>) -> [P<T>] {
        [P(name: name + "X", get: { fmt($0[keyPath: kp].x) }, set: { t, v in guard let x = num(v) else { return false }; t[keyPath: kp].x = x; return true }),
         P(name: name + "Y", get: { fmt($0[keyPath: kp].y) }, set: { t, v in guard let x = num(v) else { return false }; t[keyPath: kp].y = x; return true })]
    }
    static func optS<T>(_ name: String, _ kp: WritableKeyPath<T, String?>) -> P<T> {
        P(name: name, get: { $0[keyPath: kp] ?? "" }, set: { t, v in t[keyPath: kp] = (v.isEmpty || v.lowercased() == "none") ? nil : v; return true })
    }
    /// Lifts payload properties to the enum wrapper.
    static func lift<T, G>(_ ps: [P<G>], extract: @escaping (T) -> G?, embed: @escaping (inout T, G) -> Void) -> [P<T>] {
        ps.map { p in
            P<T>(name: p.name, get: { t in extract(t).map(p.get) ?? "" }, set: p.set.map { setter in { t, v in
                guard var g = extract(t) else { return false }
                guard setter(&g, v) else { return false }
                embed(&t, g); return true } })
        }
    }

    // MARK: Elements
    static func elementProps(_ el: BIMElement) -> [P<BIMElement>] {
        var ps: [P<BIMElement>] = [
            ro("id") { "\($0.id)" }, ro("type") { $0.typeName },
            s("name", \.name), s("layer", \.layer), optS("material", \.material), i("level", \.level),
        ]
        func L<G>(_ g: [P<G>], _ ex: @escaping (BIMGeometry) -> G?, _ em: @escaping (G) -> BIMGeometry) -> [P<BIMElement>] {
            lift(g, extract: { ex($0.geometry) }, embed: { $0.geometry = em($1) })
        }
        switch el.geometry {
        case .wall:
            ps += L(v("start", \WallGeom.start) + v("end", \WallGeom.end) + [
                d("thickness", \WallGeom.thickness, min: 1), d("height", \WallGeom.height, min: 1), d("baseOffset", \WallGeom.baseOffset),
                e("justification", \WallGeom.justification), d("bulge", \WallGeom.bulge), optS("wallType", \WallGeom.wallType),
                ro("length") { fmt($0.length) }], { if case .wall(let g) = $0 { return g }; return nil }, { .wall($0) })
        case .slab:
            ps += L([d("thickness", \SlabGeom.thickness, min: 1), d("topOffset", \SlabGeom.topOffset),
                     ro("area") { fmt(abs(GeometryOps.signedArea($0.boundary)), 2) }, ro("perimeter") { fmt(CommandHelpers.polylineLength($0.boundary + [$0.boundary.first ?? .zero]), 2) },
                     ro("holes") { "\($0.holes.count)" }], { if case .slab(let g) = $0 { return g }; return nil }, { .slab($0) })
        case .column:
            ps += L(v("position", \ColumnGeom.position) + [d("width", \ColumnGeom.width, min: 1), d("depth", \ColumnGeom.depth, min: 1), d("height", \ColumnGeom.height, min: 1),
                    angle("rotation", \ColumnGeom.rotation), b("round", \ColumnGeom.round), d("baseOffset", \ColumnGeom.baseOffset)],
                    { if case .column(let g) = $0 { return g }; return nil }, { .column($0) })
        case .beam:
            ps += L(v("start", \BeamGeom.start) + v("end", \BeamGeom.end) + [d("width", \BeamGeom.width, min: 1), d("depth", \BeamGeom.depth, min: 1), d("topOffset", \BeamGeom.topOffset),
                    ro("length") { fmt($0.start.distance(to: $0.end)) }], { if case .beam(let g) = $0 { return g }; return nil }, { .beam($0) })
        case .opening:
            ps += L([ro("kind") { $0.kind.rawValue }, ro("hostWall") { "\($0.hostWall)" }, d("offset", \OpeningGeom.offset), d("width", \OpeningGeom.width, min: 1),
                     d("height", \OpeningGeom.height, min: 1), d("sill", \OpeningGeom.sill), b("flipHand", \OpeningGeom.flipHand), b("flipFacing", \OpeningGeom.flipFacing),
                     e("doorStyle", \OpeningGeom.doorStyle), e("windowStyle", \OpeningGeom.windowStyle), d("frameWidth", \OpeningGeom.frameWidth, min: 0)],
                    { if case .opening(let g) = $0 { return g }; return nil }, { .opening($0) })
        case .roof:
            ps += L([e("kind", \RoofGeom.kind), d("pitch", \RoofGeom.pitch), d("thickness", \RoofGeom.thickness, min: 1), d("overhang", \RoofGeom.overhang),
                     d("baseOffset", \RoofGeom.baseOffset), i("eaveEdge", \RoofGeom.eaveEdge, min: 0), ro("area") { fmt(abs(GeometryOps.signedArea($0.boundary)), 2) }],
                    { if case .roof(let g) = $0 { return g }; return nil }, { .roof($0) })
        case .stair:
            ps += L(v("start", \StairGeom.start) + [angle("direction", \StairGeom.direction), d("width", \StairGeom.width, min: 1), d("totalRise", \StairGeom.totalRise, min: 1),
                    i("riserCount", \StairGeom.riserCount, min: 1), d("treadDepth", \StairGeom.treadDepth, min: 1), e("kind", \StairGeom.kind),
                    ro("riserHeight") { fmt($0.riserHeight, 1) }, ro("runLength") { fmt($0.runLength) }],
                    { if case .stair(let g) = $0 { return g }; return nil }, { .stair($0) })
        case .railing:
            ps += L([d("height", \RailingGeom.height, min: 1), d("baseOffset", \RailingGeom.baseOffset), ro("length") { fmt(CommandHelpers.polylineLength($0.path)) }],
                    { if case .railing(let g) = $0 { return g }; return nil }, { .railing($0) })
        case .space:
            ps.removeAll { $0.name == "name" }
            ps += [P(name: "name", get: { el in if case .space(let g) = el.geometry { return g.name }; return el.name }, set: { el, v in
                if case .space(var g) = el.geometry { g.name = v; el.geometry = .space(g) }; el.name = v; return true })]
            ps += L([s("number", \SpaceGeom.number), d("height", \SpaceGeom.height, min: 1),
                     ro("area") { fmt(abs(GeometryOps.signedArea($0.boundary)), 2) }, ro("perimeter") { fmt(CommandHelpers.polylineLength($0.boundary + [$0.boundary.first ?? .zero]), 2) }],
                    { if case .space(let g) = $0 { return g }; return nil }, { .space($0) })
        case .curtainWall:
            ps += L(v("start", \CurtainWallGeom.start) + v("end", \CurtainWallGeom.end) + [d("height", \CurtainWallGeom.height, min: 1), d("baseOffset", \CurtainWallGeom.baseOffset),
                    d("gridU", \CurtainWallGeom.gridU, min: 1), d("gridV", \CurtainWallGeom.gridV, min: 1), d("mullionSize", \CurtainWallGeom.mullionSize, min: 1)],
                    { if case .curtainWall(let g) = $0 { return g }; return nil }, { .curtainWall($0) })
        case .component:
            ps += L([s("category", \ComponentGeom.category)] + v("position", \ComponentGeom.position) + [angle("rotation", \ComponentGeom.rotation),
                    P(name: "width", get: { fmt($0.size.x) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.x = x; return true }),
                    P(name: "depth", get: { fmt($0.size.y) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.y = x; return true }),
                    P(name: "height", get: { fmt($0.size.z) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.z = x; return true }),
                    d("baseOffset", \ComponentGeom.baseOffset), optS("block", \ComponentGeom.block)],
                    { if case .component(let g) = $0 { return g }; return nil }, { .component($0) })
        case .gridLine:
            ps += L([s("label", \GridLineGeom.label)] + v("start", \GridLineGeom.start) + v("end", \GridLineGeom.end),
                    { if case .gridLine(let g) = $0 { return g }; return nil }, { .gridLine($0) })
        }
        return ps
    }

    public static func propertyNames(of el: BIMElement) -> [String] { elementProps(el).map(\.name) }
    public static func isReadOnly(_ el: BIMElement, _ name: String) -> Bool { elementProps(el).first { $0.name.lowercased() == name.lowercased() }?.set == nil }
    public static func getProperty(_ el: BIMElement, _ name: String) -> String? {
        if let p = elementProps(el).first(where: { $0.name.lowercased() == name.lowercased() }) { return p.get(el) }
        return el.props[name]
    }
    /// Sets a property; unknown names prefixed with "prop." are stored as user properties. Returns false when invalid or read-only.
    @discardableResult
    public static func setProperty(_ el: inout BIMElement, _ name: String, _ value: String) -> Bool {
        if let p = elementProps(el).first(where: { $0.name.lowercased() == name.lowercased() }) {
            guard let set = p.set else { return false }
            return set(&el, value)
        }
        if name.lowercased().hasPrefix("prop.") { el.props[String(name.dropFirst(5))] = value; return true }
        return false
    }

    // MARK: Entities
    static func entityProps(_ en: Entity) -> [P<Entity>] {
        var ps: [P<Entity>] = [
            ro("id") { "\($0.id)" }, ro("type") { $0.typeName }, s("layer", \.layer),
            P(name: "color", get: { $0.color.text }, set: { t, v in guard let c = ColorRef.parse(v) else { return false }; t.color = c; return true }),
            P(name: "linetype", get: { $0.linetype ?? "ByLayer" }, set: { t, v in t.linetype = v.lowercased() == "bylayer" ? nil : v; return true }),
            P(name: "lineweight", get: { $0.lineweight.map { fmt($0) } ?? "ByLayer" }, set: { t, v in
                if v.lowercased() == "bylayer" { t.lineweight = nil; return true }
                guard let x = num(v), x >= 0 else { return false }; t.lineweight = x; return true }),
        ]
        func L<G>(_ g: [P<G>], _ ex: @escaping (Geometry) -> G?, _ em: @escaping (G) -> Geometry) -> [P<Entity>] {
            lift(g, extract: { ex($0.geometry) }, embed: { $0.geometry = em($1) })
        }
        switch en.geometry {
        case .point:
            ps += [P(name: "x", get: { if case .point(let p) = $0.geometry { return fmt(p.x) }; return "" }, set: { t, v in guard case .point(var p) = t.geometry, let x = num(v) else { return false }; p.x = x; t.geometry = .point(p); return true }),
                   P(name: "y", get: { if case .point(let p) = $0.geometry { return fmt(p.y) }; return "" }, set: { t, v in guard case .point(var p) = t.geometry, let x = num(v) else { return false }; p.y = x; t.geometry = .point(p); return true })]
        case .line:
            ps += L(v("start", \LineGeom.a) + v("end", \LineGeom.b) + [ro("length") { fmt($0.a.distance(to: $0.b)) }, ro("angle") { fmt(deg(normAngle(($0.b - $0.a).angle))) }],
                    { if case .line(let g) = $0 { return g }; return nil }, { .line($0) })
        case .circle:
            ps += L(v("center", \CircleGeom.center) + [d("radius", \CircleGeom.radius, min: 1e-9),
                    P(name: "diameter", get: { fmt($0.radius * 2) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.radius = x / 2; return true }),
                    ro("area") { fmt(.pi * $0.radius * $0.radius, 2) }, ro("circumference") { fmt(2 * .pi * $0.radius, 2) }],
                    { if case .circle(let g) = $0 { return g }; return nil }, { .circle($0) })
        case .arc:
            ps += L(v("center", \ArcGeom.center) + [d("radius", \ArcGeom.radius, min: 1e-9), angle("startAngle", \ArcGeom.start), angle("endAngle", \ArcGeom.end),
                    ro("length") { fmt($0.radius * $0.sweep) }], { if case .arc(let g) = $0 { return g }; return nil }, { .arc($0) })
        case .ellipse:
            ps += L(v("center", \EllipseGeom.center) + [d("ratio", \EllipseGeom.ratio, min: 1e-6), ro("majorRadius") { fmt($0.majorAxis.length) }],
                    { if case .ellipse(let g) = $0 { return g }; return nil }, { .ellipse($0) })
        case .polyline:
            ps += L([b("closed", \PolylineGeom.closed), d("width", \PolylineGeom.width, min: 0), ro("vertices") { "\($0.vertices.count)" },
                     ro("length") { fmt(GeometryOps.length(.polyline($0), doc: nil)) }, ro("area") { $0.closed ? fmt(GeometryOps.area(.polyline($0), doc: nil) ?? 0, 2) : "" }],
                    { if case .polyline(let g) = $0 { return g }; return nil }, { .polyline($0) })
        case .spline:
            ps += L([b("closed", \SplineGeom.closed), i("degree", \SplineGeom.degree, min: 1)], { if case .spline(let g) = $0 { return g }; return nil }, { .spline($0) })
        case .text:
            ps += L(v("position", \TextGeom.position) + [s("content", \TextGeom.content), d("height", \TextGeom.height, min: 1e-6), angle("rotation", \TextGeom.rotation),
                    s("style", \TextGeom.style), e2("halign", \TextGeom.halign), e2v("valign", \TextGeom.valign), d("width", \TextGeom.width, min: 0)],
                    { if case .text(let g) = $0 { return g }; return nil }, { .text($0) })
        case .dimension:
            ps += L([ro("kind") { $0.kind.rawValue }, optS("textOverride", \DimensionGeom.textOverride), s("style", \DimensionGeom.style),
                     ro("measurement") { fmt(CommandHelpers.dimMeasurement($0), 4) }], { if case .dimension(let g) = $0 { return g }; return nil }, { .dimension($0) })
        case .hatch:
            ps += L([s("pattern", \HatchGeom.pattern), d("scale", \HatchGeom.scale, min: 1e-9), angle("angle", \HatchGeom.angle),
                     ro("area") { fmt(GeometryOps.area(.hatch($0), doc: nil) ?? 0, 2) }], { if case .hatch(let g) = $0 { return g }; return nil }, { .hatch($0) })
        case .insert:
            ps += L([s("block", \InsertGeom.block)] + v("position", \InsertGeom.position) + [
                P(name: "scaleX", get: { fmt($0.scale.x) }, set: { t, v in guard let x = num(v), x != 0 else { return false }; t.scale.x = x; return true }),
                P(name: "scaleY", get: { fmt($0.scale.y) }, set: { t, v in guard let x = num(v), x != 0 else { return false }; t.scale.y = x; return true }),
                angle("rotation", \InsertGeom.rotation)], { if case .insert(let g) = $0 { return g }; return nil }, { .insert($0) })
        case .leader:
            ps += L([s("text", \LeaderGeom.text), d("textHeight", \LeaderGeom.textHeight, min: 1e-6)], { if case .leader(let g) = $0 { return g }; return nil }, { .leader($0) })
        case .image:
            ps += L([s("path", \ImageGeom.path)] + v("origin", \ImageGeom.origin) + v("size", \ImageGeom.size) + [angle("rotation", \ImageGeom.rotation)],
                    { if case .image(let g) = $0 { return g }; return nil }, { .image($0) })
        case .table:
            ps += L(v("origin", \TableGeom.origin) + [d("rowHeight", \TableGeom.rowHeight, min: 1e-6), d("textHeight", \TableGeom.textHeight, min: 1e-6),
                    ro("rows") { "\($0.cells.count)" }, ro("columns") { "\($0.columnWidths.count)" }], { if case .table(let g) = $0 { return g }; return nil }, { .table($0) })
        case .solid:
            ps += L([ro("kind") { $0.kind.rawValue },
                     P(name: "x", get: { fmt($0.origin.x) }, set: { t, v in guard let x = num(v) else { return false }; t.origin.x = x; return true }),
                     P(name: "y", get: { fmt($0.origin.y) }, set: { t, v in guard let x = num(v) else { return false }; t.origin.y = x; return true }),
                     P(name: "z", get: { fmt($0.origin.z) }, set: { t, v in guard let x = num(v) else { return false }; t.origin.z = x; return true }),
                     P(name: "sizeX", get: { fmt($0.size.x) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.x = x; return true }),
                     P(name: "sizeY", get: { fmt($0.size.y) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.y = x; return true }),
                     P(name: "sizeZ", get: { fmt($0.size.z) }, set: { t, v in guard let x = num(v), x > 0 else { return false }; t.size.z = x; return true }),
                     d("height", \SolidGeom.height), angle("rotation", \SolidGeom.rotation)],
                    { if case .solid(let g) = $0 { return g }; return nil }, { .solid($0) })
        }
        return ps
    }
    static func e2<T>(_ name: String, _ kp: WritableKeyPath<T, HAlign>) -> P<T> {
        P(name: name, get: { $0[keyPath: kp].rawValue }, set: { t, v in guard let x = HAlign(rawValue: v.lowercased()) else { return false }; t[keyPath: kp] = x; return true })
    }
    static func e2v<T>(_ name: String, _ kp: WritableKeyPath<T, VAlign>) -> P<T> {
        P(name: name, get: { $0[keyPath: kp].rawValue }, set: { t, v in guard let x = VAlign(rawValue: v.lowercased()) else { return false }; t[keyPath: kp] = x; return true })
    }

    public static func propertyNames(of e: Entity) -> [String] { entityProps(e).map(\.name) }
    public static func isReadOnly(_ e: Entity, _ name: String) -> Bool { entityProps(e).first { $0.name.lowercased() == name.lowercased() }?.set == nil }
    public static func getProperty(_ e: Entity, _ name: String) -> String? {
        if let p = entityProps(e).first(where: { $0.name.lowercased() == name.lowercased() }) { return p.get(e) }
        return e.props[name]
    }
    @discardableResult
    public static func setProperty(_ e: inout Entity, _ name: String, _ value: String) -> Bool {
        if let p = entityProps(e).first(where: { $0.name.lowercased() == name.lowercased() }) {
            guard let set = p.set else { return false }
            return set(&e, value)
        }
        if name.lowercased().hasPrefix("prop.") { e.props[String(name.dropFirst(5))] = value; return true }
        return false
    }

    /// Properties of any object in the document by ID (name, value, read-only).
    public static func properties(of id: EntityID, in doc: ArchiDocument) -> [(name: String, value: String, readOnly: Bool)] {
        if let e = doc.entity(id) { return entityProps(e).map { ($0.name, $0.get(e), $0.set == nil) } }
        if let el = doc.element(id) { return elementProps(el).map { ($0.name, $0.get(el), $0.set == nil) } }
        return []
    }
    /// Sets a property on an object in the document. Returns false if the object/property is unknown or the value invalid.
    @discardableResult
    public static func set(_ name: String, _ value: String, of id: EntityID, in doc: inout ArchiDocument) -> Bool {
        if let i = doc.entityIndex(id) {
            var e = doc.entities[i]
            guard setProperty(&e, name, value) else { return false }
            doc.ensureLayer(e.layer); doc.entities[i] = e; return true
        }
        if let i = doc.elementIndex(id) {
            var el = doc.elements[i]
            guard setProperty(&el, name, value) else { return false }
            if name.lowercased() == "level", doc.level(el.level) == nil { return false }
            doc.ensureLayer(el.layer); doc.elements[i] = el; return true
        }
        return false
    }
}

extension CommandHelpers {
    /// Dimension value (uses the renderer, with a local fallback).
    public static func dimMeasurement(_ d: DimensionGeom) -> Double {
        let m = DimensionRenderer.measurement(d)
        if m != 0 { return m }
        let p = d.points
        switch d.kind {
        case .linear:
            guard p.count >= 2 else { return 0 }
            let r = d.rotation ?? 0
            return abs((p[1] - p[0]).dot(Vec2.polar(1, r)))
        case .aligned: return p.count >= 2 ? p[0].distance(to: p[1]) : 0
        case .radius: return p.count >= 2 ? p[0].distance(to: p[1]) : 0
        case .diameter: return p.count >= 2 ? 2 * p[0].distance(to: p[1]) : 0
        case .angular:
            guard p.count >= 3 else { return 0 }
            var a = abs(normAngle((p[2] - p[0]).angle - (p[1] - p[0]).angle))
            if a > .pi { a = 2 * .pi - a }
            return deg(a)
        case .ordinate:
            guard p.count >= 2 else { return 0 }
            let datum = p.count > 2 ? p[2] : Vec2.zero, lead = p[1] - p[0]
            return abs(lead.x) > abs(lead.y) ? p[0].y - datum.y : p[0].x - datum.x
        case .arcLength:
            guard p.count >= 3 else { return 0 }
            let r = p[0].distance(to: p[1])
            return r * normAngle((p[2] - p[0]).angle - (p[1] - p[0]).angle)
        }
    }
}
