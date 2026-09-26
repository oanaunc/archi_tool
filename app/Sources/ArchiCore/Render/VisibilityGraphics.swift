// Oanarina Archi Tool — GPL-3.0-or-later
// Visibility/graphics overrides (DOC-020) and rule-based view filters (DOC-021). Both are view settings (variables
// VGCATEGORIES and VIEWFILTERS, JSON) so they belong to the current view and to view templates — placed drawing views
// and sheets with another template are unaffected.
import Foundation

public struct GraphicOverride: Codable, Hashable {
    public var hidden: Bool?
    public var color: RGBA?
    public var lineweight: Double?
    public var halftone: Bool?
    public init(hidden: Bool? = nil, color: RGBA? = nil, lineweight: Double? = nil, halftone: Bool? = nil) {
        self.hidden = hidden; self.color = color; self.lineweight = lineweight; self.halftone = halftone
    }
    public var isEmpty: Bool { hidden == nil && color == nil && lineweight == nil && halftone == nil }
    /// `other` wins where it sets a value.
    public func merged(_ other: GraphicOverride) -> GraphicOverride {
        GraphicOverride(hidden: other.hidden ?? hidden, color: other.color ?? color, lineweight: other.lineweight ?? lineweight, halftone: other.halftone ?? halftone)
    }
}

public struct ViewFilterRule: Codable, Hashable {
    public var name: String
    /// Categories the filter applies to (schedule category names or element types; empty = all).
    public var categories: [String]
    public var field: String
    public var op: String
    public var value: String
    public var override: GraphicOverride
    public var enabled: Bool
    public init(name: String, categories: [String] = [], field: String, op: String, value: String, override: GraphicOverride, enabled: Bool = true) {
        self.name = name; self.categories = categories; self.field = field; self.op = op; self.value = value; self.override = override; self.enabled = enabled
    }
}

public enum VisibilityGraphics {
    public static let categoriesKey = "VGCATEGORIES"
    public static let filtersKey = "VIEWFILTERS"

    /// Category name of an element as used by VG and filters (wall, door, window, opening, slab, ceiling, column, beam,
    /// roof, stair, railing, room, area, curtainWall, component, grid).
    public static func category(_ el: BIMElement) -> String {
        switch el.geometry {
        case .space: return el.props["areaScheme"] != nil ? "area" : "room"
        case .slab: return el.props["kind"] == "ceiling" ? "ceiling" : "slab"
        default: return el.typeName
        }
    }

    static func norm(_ c: String) -> String {
        var k = c.lowercased().trimmingCharacters(in: .whitespaces)
        if k.hasSuffix("s") && k != "grids" { k.removeLast() }
        if k == "grids" { k = "grid" }
        if k == "curtainwall" { return "curtainwall" }
        return k
    }

    public static func categoryOverrides(_ doc: ArchiDocument) -> [String: GraphicOverride] {
        guard let s = doc.variable(categoriesKey), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([String: GraphicOverride].self, from: d) else { return [:] }
        return Dictionary(v.map { (norm($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    public static func setCategoryOverrides(_ v: [String: GraphicOverride], doc: inout ArchiDocument) {
        let clean = v.filter { !$0.value.isEmpty }
        if clean.isEmpty { doc.variables[categoriesKey] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        doc.setVariable(categoriesKey, String(decoding: (try? enc.encode(clean)) ?? Data(), as: UTF8.self))
    }
    public static func filters(_ doc: ArchiDocument) -> [ViewFilterRule] {
        guard let s = doc.variable(filtersKey), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([ViewFilterRule].self, from: d) else { return [] }
        return v
    }
    public static func setFilters(_ v: [ViewFilterRule], doc: inout ArchiDocument) {
        if v.isEmpty { doc.variables[filtersKey] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        doc.setVariable(filtersKey, String(decoding: (try? enc.encode(v)) ?? Data(), as: UTF8.self))
    }

    public static func isActive(_ doc: ArchiDocument) -> Bool { doc.variable(categoriesKey) != nil || doc.variable(filtersKey) != nil }

    /// The combined override of an element in the current view: category override, then matching filters in order.
    public static func override(_ el: BIMElement, doc: ArchiDocument, categories: [String: GraphicOverride]? = nil, filters fs: [ViewFilterRule]? = nil) -> GraphicOverride {
        let cat = category(el)
        var o = (categories ?? categoryOverrides(doc))[norm(cat)] ?? GraphicOverride()
        for f in fs ?? filters(doc) where f.enabled {
            if !f.categories.isEmpty && !f.categories.contains(where: { norm($0) == norm(cat) }) { continue }
            let v = Schedules.value(f.field, Schedules.Obj(id: el.id, element: el), doc: doc)
            if Schedules.compare(v, f.op, f.value) { o = o.merged(f.override) }
        }
        return o
    }

    /// Applies an override to draw items (nil = the element is hidden).
    public static func apply(_ o: GraphicOverride, to items: [DrawItem]) -> [DrawItem]? {
        if o.hidden == true { return nil }
        if o.isEmpty { return items }
        func col(_ c: RGBA) -> RGBA {
            var r = o.color.map { RGBA($0.r, $0.g, $0.b, c.a) } ?? c
            if o.halftone == true { r = PlanRepresentation.blend(r, RGBA(0.55, 0.55, 0.55, r.a), 0.55) }
            return r
        }
        return items.map { it in
            switch it {
            case .stroke(let p, let c, var st):
                st.color = col(st.color)
                if let lw = o.lineweight { st.lineweight = lw } else if o.halftone == true { st.lineweight = min(st.lineweight, 0.18) }
                return .stroke(points: p, closed: c, style: st)
            case .fill(let l, let c): return .fill(loops: l, color: col(c))
            case .text(let t, let f, let c): return .text(t, font: f, color: col(c))
            case .image: return it
            }
        }
    }

    /// Parses "hide", "show", "color:r,g,b", "lw:0.5", "halftone" (comma-free parts separated by ';').
    public static func parseOverride(_ s: String) -> GraphicOverride? {
        var o = GraphicOverride()
        for part in s.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !part.isEmpty {
            if part == "hide" || part == "hidden" { o.hidden = true }
            else if part == "show" { o.hidden = false }
            else if part == "halftone" { o.halftone = true }
            else if part.hasPrefix("color:") || part.hasPrefix("colour:") {
                let v = String(part.split(separator: ":", maxSplits: 1)[1])
                guard let c = named(v) ?? ScheduleCommands.color(v) else { return nil }
                o.color = c
            } else if part.hasPrefix("lw:") || part.hasPrefix("lineweight:") {
                guard let x = Double(part.split(separator: ":", maxSplits: 1)[1]), x > 0 else { return nil }
                o.lineweight = x
            } else { return nil }
        }
        return o
    }
    static func named(_ s: String) -> RGBA? {
        switch s { case "red": return RGBA(0.9, 0.15, 0.15); case "green": return RGBA(0.15, 0.7, 0.2); case "blue": return RGBA(0.2, 0.4, 0.95)
        case "magenta": return RGBA(0.9, 0.2, 0.8); case "cyan": return RGBA(0.2, 0.85, 0.9); case "yellow": return RGBA(0.96, 0.77, 0.09); default: return nil }
    }
}
