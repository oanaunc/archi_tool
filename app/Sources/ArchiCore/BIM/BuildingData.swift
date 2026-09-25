// Oanarina Archi Tool — GPL-3.0-or-later
// Building information data: zones (BIM-095), property sets (BIM-129/130) and classification codes (BIM-128).
import Foundation

public enum Zones {
    public static let types = ["Fire", "HVAC", "Department", "Security", "Other"]

    public struct Zone: Hashable {
        public var type: String
        public var name: String
        public var rooms: [EntityID]
        public var area: Double
    }

    static func key(_ type: String) -> String { "zone." + type }

    /// Zones of one type (or all types), sorted by type then name.
    public static func all(_ doc: ArchiDocument, type: String? = nil) -> [Zone] {
        var map: [String: Zone] = [:]
        for el in doc.elements {
            guard case .space(let s) = el.geometry else { continue }
            for (k, v) in el.props where k.hasPrefix("zone.") && !v.isEmpty {
                let t = String(k.dropFirst(5))
                if let type = type, t.caseInsensitiveCompare(type) != .orderedSame { continue }
                let id = t + "\u{1}" + v
                var z = map[id] ?? Zone(type: t, name: v, rooms: [], area: 0)
                z.rooms.append(el.id); z.area += abs(GeometryOps.signedArea(s.boundary))
                map[id] = z
            }
        }
        return map.values.sorted { ($0.type, $0.name) < ($1.type, $1.name) }
    }

    /// Zone outline: the rooms grown by `gap` (bridging the walls between them), united, then shrunk back.
    public static func outline(_ zone: Zone, doc: ArchiDocument, gap: Double) -> [[Vec2]] {
        var region: [[Vec2]] = []
        for id in zone.rooms {
            guard case .space(let s)? = doc.element(id)?.geometry else { continue }
            var b = RG.dedupe(s.boundary, closed: true)
            guard b.count >= 3 else { continue }
            if GeometryOps.signedArea(b) < 0 { b.reverse() }
            let grown = RG.offsetPolygon(b, gap)
            region = region.isEmpty ? [grown] : PolygonBoolean.apply(.union, region, [grown])
        }
        return region.compactMap { l -> [Vec2]? in
            let ccw = GeometryOps.signedArea(l) > 0
            let r = RG.offsetPolygon(ccw ? l : l.reversed(), ccw ? -gap : gap)
            return r.count >= 3 ? (ccw ? r : r.reversed()) : nil
        }
    }

    /// Assigns rooms to a zone of a type (empty name removes them from that type).
    public static func assign(_ doc: inout ArchiDocument, rooms: [EntityID], type: String, name: String) -> Int {
        var n = 0
        for id in rooms {
            guard let i = doc.elementIndex(id), case .space = doc.elements[i].geometry else { continue }
            doc.elements[i].props[key(type)] = name.isEmpty ? nil : name
            n += 1
        }
        return n
    }
}

public enum PropertySets {
    /// Property values of an element grouped by set: set → [(property, value)].
    public static func sets(_ el: BIMElement) -> [String: [(String, String)]] {
        var out: [String: [(String, String)]] = [:]
        for (k, v) in el.props.sorted(by: { $0.key < $1.key }) {
            guard let dot = k.firstIndex(of: "."), dot != k.startIndex else { continue }
            let set = String(k[..<dot])
            guard set.hasPrefix("Pset_") || set.hasPrefix("Pset") || set.hasPrefix("CPset") else { continue }
            out[set, default: []].append((String(k[k.index(after: dot)...]), v))
        }
        return out
    }

    /// Sets a property; returns an error message instead when the template rejects it.
    public static func set(_ doc: inout ArchiDocument, _ id: EntityID, pset: String, property: String, value: String) -> String? {
        guard let i = doc.elementIndex(id) else { return "not a building element" }
        var v = value
        if let t = doc.psetTemplate(pset) {
            guard t.applies(to: doc.elements[i].typeName) else { return "\(t.name) does not apply to a \(doc.elements[i].typeName)" }
            if let p = t.property(property) {
                guard let n = p.normalize(value) else { return "\(p.name) expects a \(p.kind.rawValue) value" }
                v = n
                doc.elements[i].props["\(t.name).\(p.name)"] = v
                return nil
            }
            if doc.psetTemplates.contains(where: { $0.name.caseInsensitiveCompare(pset) == .orderedSame }) { return "\(property) is not in template \(t.name)" }
        }
        doc.elements[i].props["\(pset).\(property)"] = v
        return nil
    }

    /// Adds the template's properties with defaults (Reference = name, IsExternal from the model) to applicable elements
    /// that lack them. Returns the number of elements touched.
    public static func apply(_ doc: inout ArchiDocument, template t: PsetTemplate, to ids: [EntityID]) -> Int {
        var n = 0
        for id in ids {
            guard let i = doc.elementIndex(id), t.applies(to: doc.elements[i].typeName) else { continue }
            let el = doc.elements[i]
            var touched = false
            for p in t.properties where el.props["\(t.name).\(p.name)"] == nil {
                var def = p.defaultValue
                if def == nil, p.name == "Reference" { def = el.name.isEmpty ? el.typeName : el.name }
                if def == nil, p.name == "IsExternal" { def = Classification.isExternal(el, doc: doc) ? "true" : "false" }
                guard let d = def else { continue }
                doc.elements[i].props["\(t.name).\(p.name)"] = d; touched = true
            }
            if touched { n += 1 }
        }
        return n
    }

    /// Values that break their template (wrong type, or property not in a custom template): "#id Pset.Prop: reason".
    public static func check(_ doc: ArchiDocument) -> [String] {
        var out: [String] = []
        for el in doc.elements {
            for (set, props) in sets(el).sorted(by: { $0.key < $1.key }) {
                guard let t = doc.psetTemplate(set) else { continue }
                if !t.applies(to: el.typeName) { out.append("#\(el.id) \(set): not applicable to \(el.typeName)"); continue }
                for (pn, v) in props {
                    if let p = t.property(pn) { if p.normalize(v) == nil { out.append("#\(el.id) \(set).\(pn): \"\(v)\" is not \(p.kind.rawValue)") } }
                    else if doc.psetTemplates.contains(where: { $0.name == t.name }) { out.append("#\(el.id) \(set).\(pn): not in the template") }
                }
            }
        }
        return out
    }
}

/// Classification codes stored as props "Classification.<System>" (IFC export writes them in a "Classification" set).
public enum Classification {
    public static let systems = ["Uniformat", "NLSfB", "Uniclass", "OmniClass"]

    /// Exterior element: explicit flag (IsExternal / Pset_*Common.IsExternal) or, for walls, a thickness of 250 mm or more.
    public static func isExternal(_ el: BIMElement, doc: ArchiDocument) -> Bool {
        for (k, v) in el.props where k == "isExternal" || k == "IsExternal" || k.hasSuffix(".IsExternal") { return ["1", "true", "yes"].contains(v.lowercased()) }
        switch el.geometry {
        case .wall(let w): return w.thickness * doc.units.mm >= 250
        case .curtainWall, .roof: return true
        case .opening(let o):
            if let h = doc.element(o.hostWall) { return isExternal(h, doc: doc) }
            return false
        default: return false
        }
    }

    /// Automatic code (and title) for an element in a system; nil when the system has no automatic mapping or the element
    /// kind is not covered.
    public static func auto(_ el: BIMElement, system: String, doc: ArchiDocument) -> (code: String, title: String)? {
        let ext = isExternal(el, doc: doc)
        var comp: String? = nil
        if case .component(let g) = el.geometry { comp = g.family }
        switch system.lowercased() {
        case "uniformat":
            switch el.geometry {
            case .wall: return ext ? ("B2010", "Exterior Walls") : ("C1010", "Partitions")
            case .curtainWall: return ("B2010", "Exterior Walls")
            case .opening(let o):
                if o.kind == .window { return ext ? ("B2020", "Exterior Windows") : ("C1010", "Partitions") }
                return ext ? ("B2030", "Exterior Doors") : ("C1020", "Interior Doors")
            case .slab: return el.props["kind"] == "ceiling" ? ("C3030", "Ceiling Finishes") : ("B1010", "Floor Construction")
            case .roof: return ("B1020", "Roof Construction")
            case .column, .beam: return ("B1010", "Floor Construction")
            case .stair: return ("C2010", "Stair Construction")
            case .railing: return ("C2020", "Stair Finishes")
            case .space: return nil
            case .component:
                if comp == "elevator" { return ("D1010", "Elevators and Lifts") }
                if comp == "escalator" { return ("D1020", "Escalators and Moving Walks") }
                if ["kitchen-base", "kitchen-wall", "kitchen-sink", "wardrobe"].contains(comp ?? "") { return ("E2010", "Fixed Furnishings") }
                if ["wc", "basin", "shower", "bath"].contains(comp ?? "") { return ("D2010", "Plumbing Fixtures") }
                return ("E2020", "Movable Furnishings")
            default: return nil
            }
        case "nlsfb":
            switch el.geometry {
            case .wall, .curtainWall: return ext ? ("21", "Buitenwanden") : ("22", "Binnenwanden")
            case .opening: return ext ? ("31", "Buitenwandopeningen") : ("32", "Binnenwandopeningen")
            case .slab: return el.props["kind"] == "ceiling" ? ("45", "Plafondafwerkingen") : ("23", "Vloeren")
            case .stair: return ("24", "Trappen en hellingen")
            case .roof: return ("27", "Daken")
            case .column, .beam: return ("28", "Hoofddraagconstructies")
            case .railing: return ("34", "Balustrades en leuningen")
            case .component:
                if comp == "elevator" || comp == "escalator" { return ("66", "Transportinstallaties") }
                return ("73", "Losse inventaris")
            default: return nil
            }
        default: return nil
        }
    }

    public static func key(_ system: String) -> String { "Classification." + (systems.first { $0.caseInsensitiveCompare(system) == .orderedSame } ?? system) }

    /// Classifies elements automatically; `overwrite` replaces existing codes. Returns the number classified.
    public static func autoClassify(_ doc: inout ArchiDocument, system: String, ids: [EntityID]? = nil, overwrite: Bool = false) -> Int {
        var n = 0
        let snap = doc
        for (i, el) in snap.elements.enumerated() where ids?.contains(el.id) ?? true {
            let k = key(system)
            if !overwrite, el.props[k] != nil { continue }
            guard let c = auto(el, system: system, doc: snap) else { continue }
            doc.elements[i].props[k] = c.code
            doc.elements[i].props[k + "Title"] = c.title
            n += 1
        }
        return n
    }
}
