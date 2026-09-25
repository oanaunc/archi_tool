// Oanarina Archi Tool — GPL-3.0-or-later
// Area schemes (RICS GEA/GIA/NIA, DIN 277 BGF/NRF, Gross/Rentable) with boundaries derived from walls,
// kept associative: area boundaries created from a seed point regenerate when walls move.
import Foundation

public enum AreaSchemes {
    public enum Rule: String, Codable, CaseIterable {
        /// Outside face of the external walls (gross external / Brutto-Grundfläche).
        case exterior
        /// Inside face of the external walls, internal walls included (gross internal).
        case interior
        /// Individual rooms between wall faces (net internal / Netto-Raumfläche / rentable).
        case rooms
    }
    public struct Scheme: Hashable {
        public var code: String
        public var name: String
        public var rule: Rule
        public var standard: String
    }
    public static let standard: [Scheme] = [
        Scheme(code: "GEA", name: "Gross External Area", rule: .exterior, standard: "RICS IPMS"),
        Scheme(code: "GIA", name: "Gross Internal Area", rule: .interior, standard: "RICS IPMS"),
        Scheme(code: "NIA", name: "Net Internal Area", rule: .rooms, standard: "RICS IPMS"),
        Scheme(code: "BGF", name: "Brutto-Grundfläche", rule: .exterior, standard: "DIN 277"),
        Scheme(code: "NRF", name: "Netto-Raumfläche", rule: .rooms, standard: "DIN 277"),
        Scheme(code: "Gross", name: "Gross Area", rule: .exterior, standard: "BOMA"),
        Scheme(code: "Rentable", name: "Rentable Area", rule: .rooms, standard: "BOMA"),
    ]

    /// Scheme by code or name (case-insensitive); unknown names are custom schemes measured to room faces.
    public static func scheme(_ key: String) -> Scheme {
        let k = key.trimmingCharacters(in: .whitespaces)
        if let s = standard.first(where: { $0.code.caseInsensitiveCompare(k) == .orderedSame || $0.name.caseInsensitiveCompare(k) == .orderedSame }) { return s }
        return Scheme(code: k, name: k, rule: .rooms, standard: "Custom")
    }

    /// Wall outlines (mitred, as drawn in plan) of the room-bounding walls of a level.
    static func wallLoops(doc: ArchiDocument, level: Int) -> [(id: EntityID, loop: [Vec2])] {
        let ctx = PlanRepresentation.context(doc)
        var out: [(id: EntityID, loop: [Vec2])] = []
        for el in RoomBounding.boundingElements(doc: doc, level: level) {
            var l: [Vec2]
            if let f = ctx.frames[el.id] ?? WallFrame(el) { l = ctx.outline(f) } else { l = CommandHelpers.footprint(el, doc: doc) }
            l = RG.dedupe(l, closed: true)
            if l.count >= 3, abs(GeometryOps.signedArea(l)) > 1e-9 { out.append((el.id, l)) }
        }
        return out
    }

    /// Union of all wall outlines on a level (outer loops CCW, holes CW).
    static func wallUnion(_ loops: [[Vec2]]) -> [[Vec2]] {
        var acc: [[Vec2]] = []
        for l in loops { acc = acc.isEmpty ? PolygonBoolean.normalize([l]) : PolygonBoolean.apply(.union, acc, [l]) }
        return acc
    }

    /// Boundary loops of a scheme on a level (CCW). `exterior` and `interior` give one loop per building outline,
    /// `rooms` one loop per enclosed room.
    public static func regions(_ s: Scheme, doc: ArchiDocument, level: Int) -> [[Vec2]] {
        let walls = wallLoops(doc: doc, level: level)
        guard !walls.isEmpty else { return [] }
        let u = wallUnion(walls.map(\.loop))
        let outers = u.filter { GeometryOps.signedArea($0) > 0 }
        switch s.rule {
        case .exterior: return outers
        case .rooms: return u.filter { GeometryOps.signedArea($0) < 0 }.map { Array($0.reversed()) }
        case .interior:
            let tol = max(1 / doc.units.mm, 1e-6)
            var out: [[Vec2]] = []
            for o in outers {
                let ring = o + [o[0]]
                // External walls: outlines touching the outer building face.
                let ext = walls.filter { w in w.loop.contains { GeometryOps.distance(from: $0, toPolyline: ring) <= tol } }.map(\.loop)
                guard !ext.isEmpty else { out.append(o); continue }
                let r = PolygonBoolean.apply(.subtract, [o], wallUnion(ext))
                out += r.filter { GeometryOps.signedArea($0) > 0 }
            }
            return out
        }
    }

    /// The scheme boundary containing a point (rooms: the room-bounding face around it, honouring separation lines).
    public static func boundary(_ s: Scheme, at p: Vec2, doc: ArchiDocument, level: Int) -> [Vec2]? {
        if s.rule == .rooms {
            let seps = ArchitectureCommands.separators(doc, level: level)
            if let b = RoomBounding.boundary(at: p, doc: doc, level: level, extraCurves: seps) { return GeometryOps.signedArea(b) < 0 ? b.reversed() : b }
        }
        let rs = regions(s, doc: doc, level: level).filter { GeometryOps.pointInPolygon(p, $0) }
        return rs.min { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }.map { CommandHelpers.simplify($0) }
    }

    /// Creates an associative area boundary (props areaScheme, areaAuto = 1, areaSeed) around a point.
    @discardableResult
    public static func create(_ s: Scheme, at p: Vec2, doc: inout ArchiDocument, level: Int) -> EntityID? {
        guard let b = boundary(s, at: p, doc: doc, level: level), b.count >= 3 else { return nil }
        doc.ensureLayer("A-AREA-PLAN")
        let id = doc.addElement(.space(SpaceGeom(boundary: b, name: "\(s.code) Area", number: "", height: 0)), level: level, layer: "A-AREA-PLAN", name: "\(s.code) Area")
        if let i = doc.elementIndex(id) {
            doc.elements[i].props["areaScheme"] = s.code
            doc.elements[i].props["areaAuto"] = "1"
            doc.elements[i].props["areaSeed"] = "\(fmt(p.x, 6)),\(fmt(p.y, 6))"
            doc.elements[i].props["tag"] = "1"
        }
        return id
    }

    static func seed(_ el: BIMElement) -> Vec2? {
        guard let s = el.props["areaSeed"] else { return nil }
        let c = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return c.count == 2 ? Vec2(c[0], c[1]) : nil
    }

    /// Regenerates associative area boundaries from the current walls. Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        let idx = doc.elements.indices.filter { doc.elements[$0].props["areaAuto"] == "1" && doc.elements[$0].props["areaScheme"] != nil }
        guard !idx.isEmpty else { return false }
        let snapshot = doc
        var changed = false
        var cache: [String: [[Vec2]]] = [:]
        for i in idx {
            let el = snapshot.elements[i]
            guard case .space(var g) = el.geometry, let p = seed(el), let code = el.props["areaScheme"] else { continue }
            let s = scheme(code)
            var nb: [Vec2]?
            if s.rule == .rooms { nb = boundary(s, at: p, doc: snapshot, level: el.level) }
            else {
                let key = "\(s.rule.rawValue)#\(el.level)"
                let rs = cache[key] ?? regions(s, doc: snapshot, level: el.level)
                cache[key] = rs
                nb = rs.filter { GeometryOps.pointInPolygon(p, $0) }.min { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }.map { CommandHelpers.simplify($0) }
            }
            guard let b = nb, b.count >= 3 else { continue }
            if b.count != g.boundary.count || zip(b, g.boundary).contains(where: { !$0.0.isClose($0.1, tol: 1e-7) }) {
                g.boundary = b; doc.elements[i].geometry = .space(g); changed = true
            }
        }
        return changed
    }

    /// Area totals per scheme (drawing units²) on a level (nil = all levels), for filtered/scheduled models.
    public static func totals(doc: ArchiDocument, level: Int? = nil) -> [(scheme: String, area: Double, count: Int)] {
        var t: [String: (Double, Int)] = [:]
        for el in ModelSets.scheduleModel(doc).elements where level == nil || el.level == level {
            guard case .space(let s) = el.geometry, let sc = el.props["areaScheme"] else { continue }
            let a = abs(GeometryOps.signedArea(s.boundary))
            t[sc, default: (0, 0)].0 += a; t[sc, default: (0, 0)].1 += 1
        }
        return t.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.scheme < $1.scheme }
    }
}
