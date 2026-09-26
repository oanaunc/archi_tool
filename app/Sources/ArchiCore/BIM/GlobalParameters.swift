// Oanarina Archi Tool — GPL-3.0-or-later
// Global (project) parameters (PAR-024): named values and formulas stored in the document. Element dimensions bind to
// them through props "gp.<field>" = expression (e.g. gp.height = "StoreyHeight - 300"); family formulas can use them too.
import Foundation

public enum GlobalParameters {
    /// Bindable fields per element kind.
    public static let fields: [String: [String]] = [
        "wall": ["height", "thickness", "baseOffset", "topOffset"],
        "slab": ["thickness", "topOffset"],
        "opening": ["width", "height", "sill"],
        "column": ["width", "depth", "height", "baseOffset"],
    ]

    static func kind(_ g: BIMGeometry) -> String? {
        switch g {
        case .wall: return "wall"
        case .slab: return "slab"
        case .opening: return "opening"
        case .column: return "column"
        default: return nil
        }
    }

    /// Resolved numeric values (lower-cased names) of the global parameters.
    public static func values(_ doc: ArchiDocument) -> [String: Double] {
        guard !doc.globalParameters.isEmpty else { return [:] }
        return FamilyExpr.resolve(FamilyDefinition(name: "Global", parameters: doc.globalParameters)).values
    }

    public static func errors(_ doc: ArchiDocument) -> [String] {
        FamilyExpr.resolve(FamilyDefinition(name: "Global", parameters: doc.globalParameters)).errors
    }

    static func get(_ g: BIMGeometry, _ f: String) -> Double? {
        switch (g, f) {
        case (.wall(let w), "height"): return w.height
        case (.wall(let w), "thickness"): return w.thickness
        case (.wall(let w), "baseOffset"): return w.baseOffset
        case (.wall(let w), "topOffset"): return w.topOffset
        case (.slab(let s), "thickness"): return s.thickness
        case (.slab(let s), "topOffset"): return s.topOffset
        case (.opening(let o), "width"): return o.width
        case (.opening(let o), "height"): return o.height
        case (.opening(let o), "sill"): return o.sill
        case (.column(let c), "width"): return c.width
        case (.column(let c), "depth"): return c.depth
        case (.column(let c), "height"): return c.height
        case (.column(let c), "baseOffset"): return c.baseOffset
        default: return nil
        }
    }

    static func set(_ g: BIMGeometry, _ f: String, _ v: Double) -> BIMGeometry {
        switch g {
        case .wall(var w):
            switch f { case "height": w.height = v; case "thickness": w.thickness = v; case "baseOffset": w.baseOffset = v; case "topOffset": w.topOffset = v; default: break }
            return .wall(w)
        case .slab(var s):
            switch f { case "thickness": s.thickness = v; case "topOffset": s.topOffset = v; default: break }
            return .slab(s)
        case .opening(var o):
            switch f { case "width": o.width = v; case "height": o.height = v; case "sill": o.sill = v; default: break }
            return .opening(o)
        case .column(var c):
            switch f { case "width": c.width = v; case "depth": c.depth = v; case "height": c.height = v; case "baseOffset": c.baseOffset = v; default: break }
            return .column(c)
        default: return g
        }
    }

    /// Canonical field name for a user-typed one (case-insensitive), or nil when the element kind lacks it.
    public static func field(_ name: String, for g: BIMGeometry) -> String? {
        guard let k = kind(g) else { return nil }
        return fields[k]?.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func hasBindings(_ doc: ArchiDocument) -> Bool {
        (!doc.globalParameters.isEmpty || !doc.projectParameters.isEmpty) && doc.elements.contains { $0.props.keys.contains { $0.hasPrefix("gp.") } }
    }

    /// Applies every binding. Returns true when an element changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard hasBindings(doc) else { return false }
        let vals = values(doc)
        var changed = false
        for i in doc.elements.indices {
            let el = doc.elements[i]
            // Project parameters of the element (PAR-023) join the global values.
            var ev = vals
            if !doc.projectParameters.isEmpty { for (k, x) in ProjectParameters.numericValues(el, doc: doc) { ev[k] = x } }
            for (k, expr) in el.props where k.hasPrefix("gp.") {
                guard let f = field(String(k.dropFirst(3)), for: el.geometry), let x = FamilyExpr.evaluate(expr, ev), x.isFinite else { continue }
                if let cur = get(doc.elements[i].geometry, f), abs(cur - x) > 1e-9 {
                    doc.elements[i].geometry = set(doc.elements[i].geometry, f, x); changed = true
                }
            }
        }
        return changed
    }

    /// Elements whose bindings reference the parameter `name`.
    public static func dependents(_ name: String, doc: ArchiDocument) -> [EntityID] {
        let l = name.lowercased()
        return doc.elements.filter { $0.props.contains { $0.key.hasPrefix("gp.") && FamilyExpr.identifiers($0.value).contains(l) } }.map(\.id)
    }
}

/// Unused family and family-type purge (PAR-033).
public enum FamilyPurge {
    /// Families with no instances that no used family nests or references, and types no instance uses (a used family
    /// always keeps at least one type).
    public static func unused(_ doc: ArchiDocument) -> (families: [String], types: [(family: String, type: String)]) {
        func key(_ s: String) -> String { s.lowercased() }
        var usedTypes: [String: Set<String>] = [:]
        var used = Set<String>()
        for el in doc.elements {
            var fam: String?
            if case .component(let g) = el.geometry { fam = g.family }
            if fam == nil || doc.family(named: fam) == nil { fam = el.props["family"] }
            guard let f = fam, let def = doc.family(named: f) else { continue }
            used.insert(key(def.name))
            if let t = el.props["familyType"] { usedTypes[key(def.name), default: []].insert(key(t)) }
            for (k, v) in el.props where k.hasPrefix("fp.") {
                if def.parameter(String(k.dropFirst(3)))?.kind == .familyType { let (a, b) = FamilyParameterKind.splitFamilyType(v); used.insert(key(a)); if let b = b { usedTypes[key(a), default: []].insert(key(b)) } }
            }
        }
        // Profile families are referenced by name from sweeps, railings and gutters: never purged here.
        for f in doc.families where f.category == "Profile" { used.insert(key(f.name)) }
        // Nested and family-type references of used families, transitively.
        var queue = Array(used)
        while let n = queue.popLast() {
            guard let def = doc.family(named: n) else { continue }
            var refs: [(String, String?)] = def.forms.compactMap { f in f.kind == .nested ? f.family.flatMap { $0.hasPrefix("=") ? nil : ($0, f.dims["type"]) } : nil }
            for p in def.parameters where p.kind == .familyType {
                let (a, b) = FamilyParameterKind.splitFamilyType(p.value); refs.append((a, b))
                for (_, tv) in def.types { if let v = tv.first(where: { $0.key.caseInsensitiveCompare(p.name) == .orderedSame })?.value { let (c, d) = FamilyParameterKind.splitFamilyType(v); refs.append((c, d)) } }
            }
            for (f, t) in refs {
                if let t = t { usedTypes[key(f), default: []].insert(key(t)) }
                if used.insert(key(f)).inserted { queue.append(f) }
            }
        }
        let fams = doc.families.filter { !used.contains(key($0.name)) }.map(\.name)
        var types: [(String, String)] = []
        for f in doc.families where used.contains(key(f.name)) && f.types.count > 1 {
            let u = usedTypes[key(f.name)] ?? []
            var unusedT = f.types.keys.sorted().filter { !u.contains(key($0)) }
            if unusedT.count == f.types.count { unusedT.removeFirst() }   // keep one type
            types += unusedT.map { (f.name, $0) }
        }
        return (fams, types)
    }

    public static func apply(_ doc: inout ArchiDocument, families: [String], types: [(family: String, type: String)]) {
        doc.families.removeAll { f in families.contains { $0.caseInsensitiveCompare(f.name) == .orderedSame } }
        for (f, t) in types { if let i = doc.familyIndex(f) { doc.families[i].types[t] = nil } }
    }
}
