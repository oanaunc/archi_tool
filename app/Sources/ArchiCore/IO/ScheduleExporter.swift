// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// CSV schedules of BIM elements. Lengths are in document units, areas in m², volumes in m³.
public enum ScheduleExporter {
    public static let kinds = ["walls", "doors", "windows", "rooms", "slabs", "all"]

    public static func csv(doc: ArchiDocument, kind: String) -> String {
        let rows = table(doc: doc, kind: kind)
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Header row followed by data rows.
    public static func table(doc: ArchiDocument, kind: String) -> [[String]] {
        let u = doc.units.mm
        let area = { (a: Double) -> String in fmt(a * u * u / 1_000_000, 3) }
        let vol = { (v: Double) -> String in fmt(v * u * u * u / 1_000_000_000, 3) }
        let len = { (v: Double) -> String in fmt(v, 2) }
        func levelName(_ id: Int) -> String { doc.level(id)?.name ?? "\(id)" }
        func sortKey(_ el: BIMElement) -> (Double, Int) { (doc.level(el.level)?.elevation ?? 0, el.id) }
        let els = doc.elements.sorted { sortKey($0) < sortKey($1) }

        switch kind.lowercased() {
        case "walls", "wall":
            var rows = [["id", "type", "length", "height", "thickness", "area", "volume", "level", "material"]]
            for el in els { if case .wall(let w) = el.geometry {
                let len0 = wallLength(w)
                let gross = len0 * w.height
                let net = max(0, gross - openingArea(el.id, doc: doc))
                rows.append(["\(el.id)", w.wallType ?? "Generic", len(len0), len(w.height), len(w.thickness), area(net), vol(net * w.thickness), levelName(el.level), el.material ?? ""])
            } }
            return rows
        case "doors", "door", "windows", "window":
            let want: OpeningKind = kind.lowercased().hasPrefix("door") ? .door : .window
            var rows = [["mark", "width", "height", "sill", "host wall", "level"]]
            for el in els { if case .opening(let o) = el.geometry, o.kind == want {
                rows.append([mark(el, prefix: want == .door ? "D" : "W"), len(o.width), len(o.height), len(o.sill), "\(o.hostWall)", levelName(el.level)])
            } }
            return rows
        case "rooms", "room", "spaces":
            var rows = [["number", "name", "area", "perimeter", "level"]]
            for el in els { if case .space(let s) = el.geometry {
                rows.append([s.number, s.name, area(abs(GeometryOps.signedArea(s.boundary))), len(perimeter(s.boundary)), levelName(el.level)])
            } }
            return rows
        case "slabs", "slab":
            var rows = [["id", "area", "thickness", "volume", "level", "material"]]
            for el in els { if case .slab(let s) = el.geometry {
                let a = slabArea(s)
                rows.append(["\(el.id)", area(a), len(s.thickness), vol(a * s.thickness), levelName(el.level), el.material ?? ""])
            } }
            return rows
        default: // "all"
            var rows = [["id", "category", "name", "level", "material", "length", "area", "volume"]]
            for el in els {
                var l = "", a = "", v = ""
                switch el.geometry {
                case .wall(let w):
                    let net = max(0, wallLength(w) * w.height - openingArea(el.id, doc: doc))
                    l = len(wallLength(w)); a = area(net); v = vol(net * w.thickness)
                case .slab(let s): let sa = slabArea(s); a = area(sa); v = vol(sa * s.thickness)
                case .space(let s): a = area(abs(GeometryOps.signedArea(s.boundary))); l = len(perimeter(s.boundary))
                case .beam(let b): let bl = b.start.distance(to: b.end); l = len(bl); v = vol(bl * b.width * b.depth)
                case .column(let c):
                    let sec = c.round ? Double.pi * c.width * c.width / 4 : c.width * c.depth
                    l = len(c.height); v = vol(sec * c.height)
                case .opening(let o): a = area(o.width * o.height)
                case .railing(let r): l = len(perimeter(r.path, closed: false))
                case .roof(let r): a = area(abs(GeometryOps.signedArea(r.boundary)) / max(cos(rad(r.kind == .flat ? 0 : r.pitch)), 0.05))
                case .curtainWall(let c): l = len(c.start.distance(to: c.end)); a = area(c.start.distance(to: c.end) * c.height)
                case .gridLine(let g): l = len(g.start.distance(to: g.end))
                case .stair(let s): l = len(s.runLength)
                case .component: break
                }
                let cat = el.typeName
                let nm: String
                if case .space(let s) = el.geometry { nm = s.name } else if case .gridLine(let g) = el.geometry { nm = g.label } else { nm = el.name }
                rows.append(["\(el.id)", cat, nm, levelName(el.level), el.material ?? "", l, a, v])
            }
            return rows
        }
    }

    static func mark(_ el: BIMElement, prefix: String) -> String {
        if let m = el.props["mark"] ?? el.props["Mark"], !m.isEmpty { return m }
        if !el.name.isEmpty { return el.name }
        return "\(prefix)\(el.id)"
    }

    static func wallLength(_ w: WallGeom) -> Double {
        guard abs(w.bulge) > 1e-9 else { return w.length }
        let sweep = 4 * atan(w.bulge)
        let chord = w.length
        let r = chord / (2 * sin(abs(sweep) / 2))
        return abs(r * sweep)
    }

    static func openingArea(_ wallID: EntityID, doc: ArchiDocument) -> Double {
        var a = 0.0
        for el in doc.elements { if case .opening(let o) = el.geometry, o.hostWall == wallID { a += o.width * o.height } }
        return a
    }

    static func slabArea(_ s: SlabGeom) -> Double {
        max(0, abs(GeometryOps.signedArea(s.boundary)) - s.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) })
    }

    static func perimeter(_ pts: [Vec2], closed: Bool = true) -> Double {
        guard pts.count >= 2 else { return 0 }
        var p = 0.0
        for i in 0..<(pts.count - 1) { p += pts[i].distance(to: pts[i + 1]) }
        if closed, let f = pts.first, let l = pts.last { p += l.distance(to: f) }
        return p
    }

    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
