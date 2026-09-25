// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Multi-storey constraints: walls whose top follows a level ("up to level"), walls attached to slabs/roofs,
/// stairs that climb to a level, and which levels an element spans (for display on upper floor plans).
public enum BIMConstraints {
    /// Height of the plan cut plane above a level (CUTPLANE variable, default 1200 mm).
    public static func cutHeight(_ doc: ArchiDocument) -> Double {
        doc.variable("CUTPLANE").flatMap(Double.init) ?? 1200 / doc.units.mm
    }

    static func elevation(_ doc: ArchiDocument, _ level: Int) -> Double { doc.level(level)?.elevation ?? 0 }

    /// Referenced host element of an attachment property ("attachTopTo" / "attachBaseTo").
    static func attached(_ el: BIMElement, _ key: String, doc: ArchiDocument) -> BIMElement? {
        guard let id = el.props[key].flatMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }), id != el.id else { return nil }
        return doc.element(id)
    }

    /// Absolute top of a slab at a plan point.
    public static func slabTop(_ el: BIMElement, at p: Vec2, doc: ArchiDocument) -> Double? {
        guard case .slab(let s) = el.geometry else { return nil }
        return elevation(doc, el.level) + s.topHeight(at: p)
    }
    /// Absolute underside of a slab at a plan point (sloped soffits are parallel to the top).
    public static func slabBottom(_ el: BIMElement, at p: Vec2, doc: ArchiDocument) -> Double? {
        guard case .slab(let s) = el.geometry, let t = slabTop(el, at: p, doc: doc) else { return nil }
        let k = s.isSloped ? 1 / max(cos(s.slope * .pi / 180), 0.05) : 1
        return t - s.thickness * k
    }

    /// Nominal base of a wall (level + base offset); opening sills are measured from here.
    public static func wallNominalBase(_ el: BIMElement, doc: ArchiDocument) -> Double {
        guard case .wall(let g) = el.geometry else { return elevation(doc, el.level) }
        return elevation(doc, el.level) + g.baseOffset
    }

    /// Absolute bottom and top of a wall after level constraints and slab attachments.
    /// A top attached to a sloped slab returns the lowest point; `slabTopInfill` adds the part above it.
    public static func wallRange(_ el: BIMElement, doc: ArchiDocument) -> (z0: Double, z1: Double) {
        guard case .wall(let g) = el.geometry else { return (0, 0) }
        let nominal = wallNominalBase(el, doc: doc)
        var z0 = nominal
        var z1 = nominal + g.height
        if let t = g.topLevel, let l = doc.level(t) {
            let top = l.elevation + g.topOffset
            if top > nominal + 1e-6 { z1 = top }
        }
        let ends = [g.start, g.end]
        if let b = attached(el, "attachBaseTo", doc: doc) {
            let tops = ends.compactMap { slabTop(b, at: $0, doc: doc) }
            if let m = tops.min(), m < z1 - 1e-6 { z0 = m }
        }
        if let t = attached(el, "attachTopTo", doc: doc) {
            let bots = ends.compactMap { slabBottom(t, at: $0, doc: doc) }
            if let m = bots.min(), m > z0 + 1e-6 { z1 = m }
        }
        return (z0, max(z1, z0))
    }

    /// Effective wall height (top − bottom).
    public static func wallHeight(_ el: BIMElement, doc: ArchiDocument) -> Double {
        let r = wallRange(el, doc: doc); return r.z1 - r.z0
    }

    /// Vertical extent of an element in absolute Z (nil for elements without height, such as rooms and grids).
    public static func zRange(_ el: BIMElement, doc: ArchiDocument) -> (z0: Double, z1: Double)? {
        let e = elevation(doc, el.level)
        switch el.geometry {
        case .wall: return wallRange(el, doc: doc)
        case .column(let c): return (e + c.baseOffset, e + c.baseOffset + c.height)
        case .curtainWall(let c): return (e + c.baseOffset, e + c.baseOffset + c.height)
        case .stair(let s): return (e, e + s.totalRise)
        default: return nil
        }
    }

    /// Levels other than the element's own whose plan cut plane passes through the element
    /// (walls "up to level", tall columns and curtain walls), plus the arrival level of stairs.
    public static func extraLevels(_ el: BIMElement, doc: ArchiDocument) -> [Int] {
        guard let r = zRange(el, doc: doc) else { return [] }
        let cut = cutHeight(doc)
        var out: [Int] = []
        for l in doc.levels where l.id != el.level {
            if case .stair(let s) = el.geometry {
                if let t = s.topLevel { if t == l.id { out.append(l.id) } }
                else if abs(l.elevation - r.z1) < max(1, 0.01 * s.totalRise) { out.append(l.id) }
                continue
            }
            let z = l.elevation + cut
            if z > r.z0 + 1e-6 && z < r.z1 - 1e-6 { out.append(l.id) }
        }
        return out
    }

    /// Whether an element is drawn in the plan of `level`.
    public static func shown(_ el: BIMElement, onLevel level: Int, doc: ArchiDocument, hosts: [EntityID: BIMElement]? = nil) -> Bool {
        if el.level == level { return true }
        switch el.geometry {
        case .gridLine: return true            // datums appear on every level
        case .wall, .column, .curtainWall, .stair: return extraLevels(el, doc: doc).contains(level)
        case .opening(let o):
            guard let host = hosts.map({ $0[o.hostWall] }) ?? doc.element(o.hostWall), case .wall = host.geometry, host.level != level,
                  extraLevels(host, doc: doc).contains(level) else { return false }
            // Only openings the cut plane passes through.
            let z = (doc.level(level)?.elevation ?? 0) + cutHeight(doc)
            let zb = wallNominalBase(host, doc: doc) + o.sill
            return z > zb && z < zb + o.height
        default: return false
        }
    }

    /// Updates stored heights from constraints so every consumer (schedules, takeoffs, exporters) sees
    /// the constrained values: walls "up to level" and stairs climbing to a level. Returns the number changed.
    @discardableResult
    public static func sync(_ doc: inout ArchiDocument) -> Int {
        var n = 0
        for i in doc.elements.indices {
            switch doc.elements[i].geometry {
            case .wall(var g):
                guard let t = g.topLevel, let l = doc.level(t) else { continue }
                let h = l.elevation + g.topOffset - wallNominalBase(doc.elements[i], doc: doc)
                if h > 1e-6, abs(h - g.height) > 1e-9 { g.height = h; doc.elements[i].geometry = .wall(g); n += 1 }
            case .stair(var s):
                guard let t = s.topLevel, let l = doc.level(t) else { continue }
                let rise = l.elevation - elevation(doc, doc.elements[i].level)
                if rise > 1e-6, abs(rise - s.totalRise) > 1e-9 { s.totalRise = rise; doc.elements[i].geometry = .stair(s); n += 1 }
            default: continue
            }
        }
        return n
    }

    /// Stair design rules (riser/going limits and the 2R + G comfort rule). Empty = compliant.
    public static func stairIssues(_ g: StairGeom, units: Units = .millimeters) -> [String] {
        let u = 1 / units.mm
        var out: [String] = []
        let r = g.riserHeight, t = g.treadDepth
        if r > 190 * u { out.append("Riser \(fmt(r * units.mm, 1)) mm is higher than 190 mm.") }
        if r < 100 * u { out.append("Riser \(fmt(r * units.mm, 1)) mm is lower than 100 mm.") }
        if t < 250 * u && g.kind != .spiral { out.append("Going \(fmt(t * units.mm, 0)) mm is shorter than 250 mm.") }
        let blondel = (2 * r + t) * units.mm
        if blondel < 600 || blondel > 660 { out.append("2R + G = \(fmt(blondel, 0)) mm is outside 600–660 mm.") }
        if g.width < 800 * u { out.append("Width \(fmt(g.width * units.mm, 0)) mm is narrower than 800 mm.") }
        let flightRisers: Int
        switch g.kind {
        case .straight: flightRisers = g.landingAt.map { max($0, g.riserCount - $0) } ?? g.riserCount
        case .lShape, .uShape: flightRisers = max(g.landingAt ?? g.riserCount / 2, g.riserCount - (g.landingAt ?? g.riserCount / 2))
        case .spiral: flightRisers = 0
        }
        if flightRisers > 18 { out.append("A flight of \(flightRisers) risers exceeds 18; add a landing.") }
        if let ld = g.landingDepth, ld < g.width - 1e-9 { out.append("Landing depth \(fmt(ld * units.mm, 0)) mm is less than the stair width.") }
        return out
    }
}
