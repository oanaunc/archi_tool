// Oanarina Archi Tool — GPL-3.0-or-later
// Collaboration on documents: three-way merge of .archi branches (base / ours / theirs) and office standards packages
// (layers, linetypes, styles, materials, types and hatch patterns shared as one .archistd file).
import Foundation

// MARK: - Three-way merge

public struct MergeConflict: Hashable {
    /// "entity", "element", "layer", "block", "level", "material", "wallType", "layout", "variable", "info", "units".
    public var kind: String
    public var key: String
    public var reason: String
}

public struct MergeResult {
    public var doc: ArchiDocument
    public var conflicts: [MergeConflict] = []
    /// Changes taken from "theirs" (added / modified / removed objects and settings).
    public var takenFromTheirs = 0
    public var keptOurs = 0
    /// Objects both sides added under the same id (theirs were renumbered).
    public var renumbered: [EntityID: EntityID] = [:]
    public var report: String {
        var s = "Merge: \(takenFromTheirs) changes from theirs, \(keptOurs) of ours kept, \(conflicts.count) conflicts"
        if !renumbered.isEmpty { s += ", \(renumbered.count) objects renumbered" }
        for c in conflicts { s += "\n  conflict \(c.kind) \(c.key): \(c.reason) (ours kept)" }
        return s
    }
}

public enum ThreeWayMerge {
    /// Merges one keyed collection. Order: ours, then objects only theirs has (in their order).
    static func mergeKeyed<T: Equatable, K: Hashable>(_ base: [T], _ ours: [T], _ theirs: [T], key: (T) -> K, kind: String, label: (K) -> String,
                                                     result: inout MergeResult) -> [T] {
        var b: [K: T] = [:], t: [K: T] = [:]
        for x in base { b[key(x)] = x }
        for x in theirs { t[key(x)] = x }
        var out: [T] = []
        var seen = Set<K>()
        for o in ours {
            let k = key(o); seen.insert(k)
            let bb = b[k], tt = t[k]
            if tt == o { out.append(o); continue }
            if bb == nil {
                // Only ours has it (theirs never had it) or both added differently.
                if tt != nil { result.conflicts.append(MergeConflict(kind: kind, key: label(k), reason: "added differently on both sides")); result.keptOurs += 1 }
                out.append(o); continue
            }
            if bb == o {
                // Ours unchanged: take theirs (modified, or removed when nil).
                if let tt = tt { out.append(tt) }
                result.takenFromTheirs += 1
                continue
            }
            if tt == bb { out.append(o); result.keptOurs += 1; continue }
            // Both changed (or theirs removed what ours modified).
            result.conflicts.append(MergeConflict(kind: kind, key: label(k), reason: tt == nil ? "modified by us, removed by them" : "modified on both sides"))
            result.keptOurs += 1
            out.append(o)
        }
        for x in theirs {
            let k = key(x)
            guard !seen.contains(k) else { continue }
            if let bb = b[k] {
                // We removed it; they kept it: removal wins unless they modified it.
                if bb != x { result.conflicts.append(MergeConflict(kind: kind, key: label(k), reason: "removed by us, modified by them")) }
                continue
            }
            out.append(x); result.takenFromTheirs += 1
        }
        return out
    }

    static func mergeValue<T: Equatable>(_ base: T, _ ours: T, _ theirs: T, kind: String, key: String, result: inout MergeResult) -> T {
        if ours == theirs || theirs == base { return ours }
        if ours == base { result.takenFromTheirs += 1; return theirs }
        result.conflicts.append(MergeConflict(kind: kind, key: key, reason: "changed on both sides"))
        return ours
    }

    /// Merges `theirs` into `ours` relative to their common ancestor `base`. Objects are matched by id (entities, elements,
    /// levels) or name (layers, blocks, materials, types, layouts, variables). Non-conflicting changes of both sides are
    /// combined; on a conflict ours is kept and the conflict reported. Objects both sides added under the same id are kept
    /// twice, theirs renumbered (hosted openings follow their renumbered walls).
    public static func merge(base: ArchiDocument, ours: ArchiDocument, theirs theirs0: ArchiDocument) -> MergeResult {
        var res = MergeResult(doc: ours)
        var theirs = theirs0
        // Same id added on both sides with different content: renumber theirs.
        let baseIDs = Set(base.entities.map(\.id) + base.elements.map(\.id))
        let ourEnt = Dictionary(ours.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ourEl = Dictionary(ours.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next = max(ours.nextID, theirs.nextID, base.nextID,
                       (ours.entities.map(\.id) + ours.elements.map(\.id) + theirs.entities.map(\.id) + theirs.elements.map(\.id)).max().map { $0 + 1 } ?? 1)
        var remap: [EntityID: EntityID] = [:]
        for i in theirs.entities.indices {
            let id = theirs.entities[i].id
            if !baseIDs.contains(id), let o = ourEnt[id], o != theirs.entities[i] || ourEl[id] != nil { remap[id] = next; theirs.entities[i].id = next; next += 1 }
            else if !baseIDs.contains(id), ourEl[id] != nil { remap[id] = next; theirs.entities[i].id = next; next += 1 }
        }
        for i in theirs.elements.indices {
            let id = theirs.elements[i].id
            if !baseIDs.contains(id), (ourEl[id].map { $0 != theirs.elements[i] } ?? false) || ourEnt[id] != nil { remap[id] = next; theirs.elements[i].id = next; next += 1 }
        }
        if !remap.isEmpty {
            for i in theirs.elements.indices {
                if case .opening(var o) = theirs.elements[i].geometry, let n = remap[o.hostWall] { o.hostWall = n; theirs.elements[i].geometry = .opening(o) }
            }
        }
        res.renumbered = remap
        var d = ours
        d.entities = mergeKeyed(base.entities, ours.entities, theirs.entities, key: { $0.id }, kind: "entity", label: { "#\($0)" }, result: &res)
        d.elements = mergeKeyed(base.elements, ours.elements, theirs.elements, key: { $0.id }, kind: "element", label: { "#\($0)" }, result: &res)
        d.layers = mergeKeyed(base.layers, ours.layers, theirs.layers, key: { $0.name.lowercased() }, kind: "layer", label: { $0 }, result: &res)
        d.levels = mergeKeyed(base.levels, ours.levels, theirs.levels, key: { $0.id }, kind: "level", label: { "\($0)" }, result: &res)
        d.materials = mergeKeyed(base.materials, ours.materials, theirs.materials, key: { $0.name.lowercased() }, kind: "material", label: { $0 }, result: &res)
        d.wallTypes = mergeKeyed(base.wallTypes, ours.wallTypes, theirs.wallTypes, key: { $0.name }, kind: "wallType", label: { $0 }, result: &res)
        d.openingTypes = mergeKeyed(base.openingTypes, ours.openingTypes, theirs.openingTypes, key: { $0.name }, kind: "openingType", label: { $0 }, result: &res)
        d.slabTypes = mergeKeyed(base.slabTypes, ours.slabTypes, theirs.slabTypes, key: { $0.name }, kind: "slabType", label: { $0 }, result: &res)
        d.linetypes = mergeKeyed(base.linetypes, ours.linetypes, theirs.linetypes, key: { $0.name.lowercased() }, kind: "linetype", label: { $0 }, result: &res)
        d.textStyles = mergeKeyed(base.textStyles, ours.textStyles, theirs.textStyles, key: { $0.name }, kind: "textStyle", label: { $0 }, result: &res)
        d.dimStyles = mergeKeyed(base.dimStyles, ours.dimStyles, theirs.dimStyles, key: { $0.name }, kind: "dimStyle", label: { $0 }, result: &res)
        d.layouts = mergeKeyed(base.layouts, ours.layouts, theirs.layouts, key: { $0.name }, kind: "layout", label: { $0 }, result: &res)
        d.namedViews = mergeKeyed(base.namedViews, ours.namedViews, theirs.namedViews, key: { $0.name }, kind: "view", label: { $0 }, result: &res)
        d.families = mergeKeyed(base.families, ours.families, theirs.families, key: { $0.name }, kind: "family", label: { $0 }, result: &res)
        struct KV: Equatable { var k: String; var v: String }
        func kvs(_ vars: [String: String]) -> [KV] { vars.map { KV(k: $0.key, v: $0.value) }.sorted { $0.k < $1.k } }
        let baseVars = kvs(base.variables), ourVars = kvs(ours.variables), theirVars = kvs(theirs.variables)
        let vars: [KV] = mergeKeyed(baseVars, ourVars, theirVars, key: { (kv: KV) -> String in kv.k }, kind: "variable", label: { (s: String) -> String in s }, result: &res)
        d.variables = Dictionary(vars.map { ($0.k, $0.v) }, uniquingKeysWith: { a, _ in a })
        let bl = mergeKeyed(base.blocks.values.sorted { $0.name < $1.name }, ours.blocks.values.sorted { $0.name < $1.name }, theirs.blocks.values.sorted { $0.name < $1.name },
                            key: { $0.name }, kind: "block", label: { $0 }, result: &res)
        d.blocks = Dictionary(bl.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        d.info = mergeValue(base.info, ours.info, theirs.info, kind: "info", key: "project", result: &res)
        d.units = mergeValue(base.units, ours.units, theirs.units, kind: "units", key: "units", result: &res)
        d.phases = mergeValue(base.phases, ours.phases, theirs.phases, kind: "phases", key: "phases", result: &res)
        d.keynotes = mergeValue(base.keynotes, ours.keynotes, theirs.keynotes, kind: "keynotes", key: "keynotes", result: &res)
        // Hosted openings whose wall disappeared in the merge are dropped.
        let walls = Set(d.elements.compactMap { el -> EntityID? in if case .wall = el.geometry { return el.id }; return nil })
        d.elements.removeAll { el in if case .opening(let o) = el.geometry { return !walls.contains(o.hostWall) }; return false }
        if d.layer(named: d.currentLayer) == nil { d.currentLayer = "0" }
        if d.level(d.currentLevel) == nil, let l = d.levels.first { d.currentLevel = l.id }
        for e in d.entities where d.layer(named: e.layer) == nil { d.ensureLayer(e.layer) }
        for e in d.elements where d.layer(named: e.layer) == nil { d.ensureLayer(e.layer) }
        let maxID = max(d.entities.map(\.id).max() ?? 0, d.elements.map(\.id).max() ?? 0)
        d.nextID = max(next, maxID + 1)
        res.doc = d
        return res
    }
}

// MARK: - Office standards package

/// Shared office standards (.archistd, JSON): layers, linetypes, text and dimension styles, materials, wall / floor /
/// door-window types, view templates and saved hatch patterns.
public struct StandardsPackage: Codable, Hashable {
    public var name: String
    public var created: String
    public var layers: [Layer] = []
    public var linetypes: [Linetype] = []
    public var textStyles: [TextStyle] = []
    public var dimStyles: [DimStyle] = []
    public var materials: [Material] = []
    public var wallTypes: [WallType] = []
    public var slabTypes: [SlabType] = []
    public var openingTypes: [OpeningType] = []
    public var viewTemplates: [ViewTemplate] = []
    /// Hatch pattern definitions ("HPPAT:<NAME>" variables) by name.
    public var hatchPatterns: [String: String] = [:]

    public init(name: String, from doc: ArchiDocument) {
        self.name = name; created = Markups.now()
        layers = doc.layers; linetypes = doc.linetypes; textStyles = doc.textStyles; dimStyles = doc.dimStyles
        materials = doc.materials; wallTypes = doc.wallTypes; slabTypes = doc.slabTypes; openingTypes = doc.openingTypes
        viewTemplates = doc.viewTemplates
        for (k, v) in doc.variables where k.hasPrefix("HPPAT:") { hatchPatterns[String(k.dropFirst(6))] = v }
    }

    enum CodingKeys: String, CodingKey {
        case name, created, layers, linetypes, textStyles, dimStyles, materials, wallTypes, slabTypes, openingTypes, viewTemplates, hatchPatterns
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Standards"
        created = try c.decodeIfPresent(String.self, forKey: .created) ?? ""
        layers = try c.decodeIfPresent([Layer].self, forKey: .layers) ?? []
        linetypes = try c.decodeIfPresent([Linetype].self, forKey: .linetypes) ?? []
        textStyles = try c.decodeIfPresent([TextStyle].self, forKey: .textStyles) ?? []
        dimStyles = try c.decodeIfPresent([DimStyle].self, forKey: .dimStyles) ?? []
        materials = try c.decodeIfPresent([Material].self, forKey: .materials) ?? []
        wallTypes = try c.decodeIfPresent([WallType].self, forKey: .wallTypes) ?? []
        slabTypes = try c.decodeIfPresent([SlabType].self, forKey: .slabTypes) ?? []
        openingTypes = try c.decodeIfPresent([OpeningType].self, forKey: .openingTypes) ?? []
        viewTemplates = try c.decodeIfPresent([ViewTemplate].self, forKey: .viewTemplates) ?? []
        hatchPatterns = try c.decodeIfPresent([String: String].self, forKey: .hatchPatterns) ?? [:]
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> StandardsPackage { try JSONDecoder().decode(StandardsPackage.self, from: data) }

    /// Applies the package: missing definitions are added; existing ones (same name) are replaced when `overwrite`.
    /// Returns counts of added and updated definitions.
    @discardableResult
    public func apply(to doc: inout ArchiDocument, overwrite: Bool) -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        func merge<T: Equatable>(_ list: inout [T], _ incoming: [T], _ name: (T) -> String) {
            for x in incoming {
                if let i = list.firstIndex(where: { name($0).caseInsensitiveCompare(name(x)) == .orderedSame }) {
                    if overwrite && list[i] != x { list[i] = x; updated += 1 }
                } else { list.append(x); added += 1 }
            }
        }
        merge(&doc.layers, layers, { $0.name }); merge(&doc.linetypes, linetypes, { $0.name })
        merge(&doc.textStyles, textStyles, { $0.name }); merge(&doc.dimStyles, dimStyles, { $0.name })
        merge(&doc.materials, materials, { $0.name }); merge(&doc.wallTypes, wallTypes, { $0.name })
        merge(&doc.slabTypes, slabTypes, { $0.name }); merge(&doc.openingTypes, openingTypes, { $0.name })
        merge(&doc.viewTemplates, viewTemplates, { $0.name })
        for (n, def) in hatchPatterns {
            let k = "HPPAT:" + n.uppercased()
            if let cur = doc.variable(k) { if overwrite && cur != def { doc.setVariable(k, def); updated += 1 } } else { doc.setVariable(k, def); added += 1 }
            HatchPatterns.register(name: n, definition: def)
        }
        return (added, updated)
    }

    /// Definitions of `doc` that differ from the package (for STANDARDSCHECK-style reports): name → reason.
    public func deviations(in doc: ArchiDocument) -> [String] {
        var out: [String] = []
        for l in layers {
            guard let d = doc.layer(named: l.name) else { continue }
            if d.color != l.color || d.linetype != l.linetype || abs(d.lineweight - l.lineweight) > 1e-9 { out.append("Layer \(l.name): colour/linetype/lineweight differ from the standard") }
        }
        for s in dimStyles { if let d = doc.dimStyles.first(where: { $0.name == s.name }), d != s { out.append("Dimension style \(s.name) differs from the standard") } }
        for s in textStyles { if let d = doc.textStyles.first(where: { $0.name == s.name }), d != s { out.append("Text style \(s.name) differs from the standard") } }
        for w in wallTypes { if let d = doc.wallTypes.first(where: { $0.name == w.name }), d != w { out.append("Wall type \(w.name) differs from the standard") } }
        let std = Set(layers.map { $0.name.lowercased() })
        if !std.isEmpty { for l in doc.layers where !std.contains(l.name.lowercased()) && l.name != "0" { out.append("Layer \(l.name) is not in the standard") } }
        return out
    }
}
