// Oanarina Archi Tool — GPL-3.0-or-later
// Named element sets carried by element properties: worksets, design options, and formula-driven type parameters.
import Foundation

// MARK: - Formula-driven type parameters

/// Evaluates type formulas ("height" = "width * 1.5") in dependency order with cycle and unknown-name detection.
public enum TypeFormulas {
    static let functions: Set<String> = ["sqrt", "abs", "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "exp", "round", "floor", "ceil", "r2d", "d2r", "pi", "e"]

    /// Identifiers (parameter names) used by an expression, lower-cased, excluding built-in functions and constants.
    public static func identifiers(_ expr: String) -> [String] {
        var out: [String] = [], cur = ""
        func flush() {
            if !cur.isEmpty, let f = cur.first, f.isLetter || f == "_" {
                let l = cur.lowercased()
                if !functions.contains(l) && !out.contains(l) { out.append(l) }
            }
            cur = ""
        }
        for ch in expr {
            if ch.isLetter || ch.isNumber || ch == "_" { cur.append(ch) }
            else if ch == "." && !cur.isEmpty && cur.first!.isNumber { cur.append(ch) }
            else { flush() }
        }
        flush()
        return out
    }

    /// Evaluates formulas over `values` (name → number, case-insensitive). Returns the completed values and errors.
    public static func evaluate(_ formulas: [String: String], values: [String: Double]) -> (values: [String: Double], errors: [String]) {
        var known: [String: Double] = [:]
        for (k, v) in values { known[k.lowercased()] = v }
        var pending: [String: String] = [:]
        for (k, f) in formulas where !f.trimmingCharacters(in: .whitespaces).isEmpty { pending[k.lowercased()] = f }
        for k in pending.keys { known[k] = nil }
        var errors: [String] = []
        var progress = true
        while !pending.isEmpty && progress {
            progress = false
            for (k, f) in pending.sorted(by: { $0.key < $1.key }) {
                let ids = identifiers(f)
                if let bad = ids.first(where: { known[$0] == nil && pending[$0] == nil }) {
                    errors.append("\(k): unknown parameter \"\(bad)\""); pending[k] = nil; progress = true; continue
                }
                guard ids.allSatisfy({ known[$0] != nil }) else { continue }
                var s = f
                for id in ids.sorted(by: { $0.count > $1.count }) { s = Constraints.replaceIdentifier(s, id, "(\(known[id]!))") }
                if let v = CommandHelpers.evaluate(s) { known[k] = v } else { errors.append("\(k): cannot evaluate \"\(f)\"") }
                pending[k] = nil; progress = true
            }
        }
        for k in pending.keys.sorted() { errors.append("\(k): circular reference") }
        return (known, errors)
    }

    public static func resolve(_ t: OpeningType) -> (type: OpeningType, errors: [String]) {
        guard !t.formulas.isEmpty else { return (t, []) }
        var vals: [String: Double] = ["width": t.width, "height": t.height, "sill": t.sill, "framewidth": t.frameWidth,
                                      "mullions": Double(t.mullions), "transoms": Double(t.transoms)]
        for (k, v) in t.params { if let d = Double(v.trimmingCharacters(in: .whitespaces)) { vals[k.lowercased()] = d } }
        let (r, errs) = evaluate(t.formulas, values: vals)
        var o = t
        if let v = r["width"], v > 0 { o.width = v }
        if let v = r["height"], v > 0 { o.height = v }
        if let v = r["sill"] { o.sill = v }
        if let v = r["framewidth"], v >= 0 { o.frameWidth = v }
        if let v = r["mullions"] { o.mullions = max(0, Int(v.rounded())) }
        if let v = r["transoms"] { o.transoms = max(0, Int(v.rounded())) }
        let builtins: Set<String> = ["width", "height", "sill", "framewidth", "mullions", "transoms"]
        for k in t.formulas.keys where !builtins.contains(k.lowercased()) {
            guard let v = r[k.lowercased()] else { continue }
            let key = t.params.keys.first { $0.caseInsensitiveCompare(k) == .orderedSame } ?? k
            o.params[key] = fmt(v, 3)
        }
        return (o, errs)
    }
}

// MARK: - Worksets

/// Worksets as named element sets (props["workset"]); elements without one are in `defaultName`.
/// WORKSET = current workset for new elements, WORKSETS = known names ("|"-separated), WORKSETSHIDDEN = hidden names.
public enum Worksets {
    public static let prop = "workset"
    public static let currentVariable = "WORKSET"
    public static let listVariable = "WORKSETS"
    public static let hiddenVariable = "WORKSETSHIDDEN"
    public static let defaultName = "Workset1"

    static func split(_ s: String?) -> [String] { (s ?? "").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    public static func name(of props: [String: String]) -> String { props[prop].flatMap { $0.isEmpty ? nil : $0 } ?? defaultName }

    /// All workset names: declared ones plus any used by elements, default first.
    public static func all(_ doc: ArchiDocument) -> [String] {
        var out = [defaultName]
        for n in split(doc.variable(listVariable)) where !out.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { out.append(n) }
        for el in doc.elements { let n = name(of: el.props); if !out.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { out.append(n) } }
        return out
    }
    public static func hidden(_ doc: ArchiDocument) -> Set<String> { Set(split(doc.variable(hiddenVariable)).map { $0.lowercased() }) }
    public static func isShown(_ props: [String: String], doc: ArchiDocument) -> Bool {
        guard let h = doc.variable(hiddenVariable), !h.isEmpty else { return true }
        return !hidden(doc).contains(name(of: props).lowercased())
    }
    public static func declare(_ n: String, doc: inout ArchiDocument) {
        var l = split(doc.variable(listVariable))
        if !l.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) && n.caseInsensitiveCompare(defaultName) != .orderedSame { l.append(n) }
        doc.setVariable(listVariable, l.joined(separator: "|"))
    }
    public static func setHidden(_ n: String, _ hide: Bool, doc: inout ArchiDocument) {
        var l = split(doc.variable(hiddenVariable)).filter { $0.caseInsensitiveCompare(n) != .orderedSame }
        if hide { l.append(n) }
        doc.setVariable(hiddenVariable, l.joined(separator: "|"))
    }
    /// Element count per workset.
    public static func counts(_ doc: ArchiDocument) -> [String: Int] {
        var c: [String: Int] = [:]
        for el in doc.elements { c[name(of: el.props), default: 0] += 1 }
        return c
    }
}

// MARK: - Design options

/// Design options (Revit): alternative versions of part of the model. Elements carry props["designOption"] = "Set:Option";
/// elements without one are the main model and always shown. Each set has a primary option shown by default;
/// DESIGNOPTIONVIEW overrides the displayed option per set ("Set:Option|Set2:Option").
public struct DesignOptionSet: Codable, Hashable {
    public var name: String
    public var options: [String]
    public var primary: String
    public init(name: String, options: [String], primary: String) { self.name = name; self.options = options; self.primary = primary }
}

public enum DesignOptions {
    public static let prop = "designOption"
    public static let setsVariable = "DESIGNOPTIONSETS"
    public static let viewVariable = "DESIGNOPTIONVIEW"
    public static let editingVariable = "DESIGNOPTIONEDIT"

    public static func sets(_ doc: ArchiDocument) -> [DesignOptionSet] {
        guard let s = doc.variable(setsVariable), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([DesignOptionSet].self, from: d) else { return [] }
        return v
    }
    public static func save(_ sets: [DesignOptionSet], doc: inout ArchiDocument) {
        if sets.isEmpty { doc.variables[setsVariable] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(sets), let s = String(data: d, encoding: .utf8) { doc.setVariable(setsVariable, s) }
    }
    /// ("Set", "Option") of a props value.
    public static func parse(_ v: String?) -> (set: String, option: String)? {
        guard let v = v, let i = v.firstIndex(of: ":") else { return nil }
        let a = v[..<i].trimmingCharacters(in: .whitespaces), b = v[v.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return a.isEmpty || b.isEmpty ? nil : (a, b)
    }
    /// Displayed option per set name (lower-cased set → option).
    public static func displayed(_ doc: ArchiDocument) -> [String: String] {
        var out: [String: String] = [:]
        for s in sets(doc) { out[s.name.lowercased()] = s.primary }
        for part in (doc.variable(viewVariable) ?? "").split(separator: "|") {
            if let p = parse(String(part)) { out[p.set.lowercased()] = p.option }
        }
        return out
    }
    public static func isShown(_ props: [String: String], doc: ArchiDocument) -> Bool {
        guard let p = parse(props[prop]) else { return true }
        guard let shown = displayed(doc)[p.set.lowercased()] else { return true }
        return shown.caseInsensitiveCompare(p.option) == .orderedSame
    }
    /// Keeps the primary option of a set as main model: deletes the other options' elements and the set.
    public static func acceptPrimary(_ setName: String, doc: inout ArchiDocument) -> (kept: Int, removed: Int)? {
        var all = sets(doc)
        guard let i = all.firstIndex(where: { $0.name.caseInsensitiveCompare(setName) == .orderedSame }) else { return nil }
        let s = all[i]
        var drop = Set<EntityID>(), kept = 0
        for (k, el) in doc.elements.enumerated() {
            guard let p = parse(el.props[prop]), p.set.caseInsensitiveCompare(s.name) == .orderedSame else { continue }
            if p.option.caseInsensitiveCompare(s.primary) == .orderedSame { doc.elements[k].props[prop] = nil; kept += 1 } else { drop.insert(el.id) }
        }
        doc.remove(ids: drop)
        all.remove(at: i)
        save(all, doc: &doc)
        let view = (doc.variable(viewVariable) ?? "").split(separator: "|").filter { parse(String($0))?.set.caseInsensitiveCompare(s.name) != .orderedSame }
        doc.setVariable(viewVariable, view.joined(separator: "|"))
        if let e = parse(doc.variable(editingVariable)), e.set.caseInsensitiveCompare(s.name) == .orderedSame { doc.variables[editingVariable] = nil }
        return (kept, drop.count)
    }
}

/// Combined model-set visibility used by the plan and 3D builders.
public enum ModelSets {
    public static func isShown(_ props: [String: String], doc: ArchiDocument) -> Bool {
        Worksets.isShown(props, doc: doc) && DesignOptions.isShown(props, doc: doc) && MEPSystemFilter.isShown(props, doc: doc)
    }
    /// The document with elements/entities hidden by worksets or design options removed (unchanged when no filter is active).
    public static func visibleModel(_ doc: ArchiDocument) -> ArchiDocument {
        guard active(doc) else { return doc }
        var d = doc
        d.elements.removeAll { !isShown($0.props, doc: doc) }
        d.entities.removeAll { !isShown($0.props, doc: doc) }
        return d
    }
    /// True when any filter could hide something (fast path for documents without worksets/options).
    public static func active(_ doc: ArchiDocument) -> Bool {
        !(doc.variable(Worksets.hiddenVariable) ?? "").isEmpty || doc.variable(DesignOptions.setsVariable) != nil
            || !(doc.variable(MEPSystemFilter.variable) ?? "").isEmpty
    }

    // MARK: Public filter API (views, schedules, exports and analyses)

    /// Whether props pass an explicit filter (nil fields fall back to the document's settings).
    public static func isShown(_ props: [String: String], doc: ArchiDocument, filter f: ModelFilter) -> Bool {
        // Worksets.
        if let only = f.worksets {
            let n = Worksets.name(of: props).lowercased()
            if !only.contains(where: { $0.lowercased() == n }) { return false }
        } else if let hidden = f.hiddenWorksets {
            let n = Worksets.name(of: props).lowercased()
            if hidden.contains(where: { $0.lowercased() == n }) { return false }
        } else if !Worksets.isShown(props, doc: doc) { return false }
        // Design options.
        if let p = DesignOptions.parse(props[DesignOptions.prop]) {
            switch f.designOptions {
            case .all: break
            case .mainModelOnly: return false
            case .document: if !DesignOptions.isShown(props, doc: doc) { return false }
            case .primary:
                if let s = DesignOptions.sets(doc).first(where: { $0.name.caseInsensitiveCompare(p.set) == .orderedSame }),
                   s.primary.caseInsensitiveCompare(p.option) != .orderedSame { return false }
            case .options(let m):
                let shown = m.first { $0.key.caseInsensitiveCompare(p.set) == .orderedSame }?.value
                    ?? DesignOptions.displayed(doc)[p.set.lowercased()]
                if let s = shown, s.caseInsensitiveCompare(p.option) != .orderedSame { return false }
            }
        }
        // MEP systems.
        if let sys = f.systems {
            if !sys.isEmpty, let s = props["system"], !s.isEmpty, !sys.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) { return false }
        } else if !MEPSystemFilter.isShown(props, doc: doc) { return false }
        // Phases: hide elements not existing in the phase (future / demolished before it).
        if f.respectPhase, Phasing.isActive(doc) {
            let st = Phasing.status(props, doc: doc, phase: f.phase.flatMap { Phasing.phaseIndex($0, doc) })
            if st == .future || st == .gone { return false }
        }
        return true
    }

    /// Elements passing a filter (the document's own settings by default).
    public static func elements(_ doc: ArchiDocument, filter: ModelFilter = .document) -> [BIMElement] {
        doc.elements.filter { isShown($0.props, doc: doc, filter: filter) }
    }

    /// The document reduced to what a filter shows (elements and entities). Hosted openings follow their host wall.
    public static func filtered(_ doc: ArchiDocument, _ filter: ModelFilter) -> ArchiDocument {
        var d = doc
        d.elements.removeAll { !isShown($0.props, doc: doc, filter: filter) }
        d.entities.removeAll { !isShown($0.props, doc: doc, filter: filter) }
        let walls = Set(d.elements.map(\.id))
        d.elements.removeAll { if case .opening(let o) = $0.geometry { return !walls.contains(o.hostWall) }; return false }
        return d
    }

    /// The model schedules and quantity take-offs should count: SCHEDULEFILTER = "document" (default: what the views show),
    /// "primary" (main model + primary options, all worksets) or "all" (everything).
    public static func scheduleModel(_ doc: ArchiDocument) -> ArchiDocument {
        filtered(doc, ModelFilter.named(doc.variable("SCHEDULEFILTER")) ?? .document)
    }

    /// The model exporters should write: EXPORTFILTER = "document" | "primary" (default) | "all".
    public static func exportModel(_ doc: ArchiDocument) -> ArchiDocument {
        filtered(doc, ModelFilter.named(doc.variable("EXPORTFILTER")) ?? .primaryModel)
    }
}

/// An explicit model filter for views, schedules and exports (worksets, design options, MEP systems, phase).
/// Other areas call `ModelSets.filtered(doc, filter)` / `ModelSets.elements(doc, filter:)` / `scheduleModel` / `exportModel`.
public struct ModelFilter: Hashable {
    public enum Options: Hashable {
        /// What the document's views show (primary options unless DESIGNOPTIONVIEW overrides).
        case document
        /// Main model plus each set's primary option.
        case primary
        /// Every option of every set.
        case all
        /// Main model only (no option elements).
        case mainModelOnly
        /// Explicit option per set (others as the document).
        case options([String: String])
    }
    /// Only these worksets (nil = not restricted by this field).
    public var worksets: Set<String>?
    /// Hide these worksets (used when `worksets` is nil; nil = the document's hidden worksets).
    public var hiddenWorksets: Set<String>?
    public var designOptions: Options
    /// Only these MEP systems (props["system"]); empty = all systems; nil = the document's MEPSYSTEMSHOW setting.
    public var systems: Set<String>?
    /// Hide elements that do not exist in `phase` (default: the current phase).
    public var respectPhase: Bool
    public var phase: String?
    public init(worksets: Set<String>? = nil, hiddenWorksets: Set<String>? = nil, designOptions: Options = .document,
                systems: Set<String>? = nil, respectPhase: Bool = false, phase: String? = nil) {
        self.worksets = worksets; self.hiddenWorksets = hiddenWorksets; self.designOptions = designOptions
        self.systems = systems; self.respectPhase = respectPhase; self.phase = phase
    }
    /// What the views show.
    public static let document = ModelFilter()
    /// All worksets, main model + primary options, all systems.
    public static let primaryModel = ModelFilter(hiddenWorksets: [], designOptions: .primary, systems: [])
    /// Everything in the file.
    public static let everything = ModelFilter(hiddenWorksets: [], designOptions: .all, systems: [])
    /// "document" / "primary" / "all" (nil for anything else).
    public static func named(_ s: String?) -> ModelFilter? {
        switch (s ?? "").lowercased() {
        case "document", "view", "views": return .document
        case "primary", "main": return .primaryModel
        case "all", "everything": return .everything
        default: return nil
        }
    }
}

/// MEP system display filter: MEPSYSTEMSHOW = "DCW|SAN" shows only those systems (elements without a system are unaffected).
public enum MEPSystemFilter {
    public static let variable = "MEPSYSTEMSHOW"
    public static func shown(_ doc: ArchiDocument) -> Set<String>? {
        let l = Worksets.split(doc.variable(variable)).map { $0.uppercased() }
        return l.isEmpty ? nil : Set(l)
    }
    public static func isShown(_ props: [String: String], doc: ArchiDocument) -> Bool {
        guard let only = shown(doc), let s = props["system"], !s.isEmpty else { return true }
        return only.contains(s.uppercased())
    }
}
