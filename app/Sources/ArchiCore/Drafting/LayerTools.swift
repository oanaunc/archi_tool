// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// Layer management services: layer states, layer filters, layer translation, layer walk, per-viewport layer freeze, merge.
// All persistent data lives in document variables as JSON so older builds keep opening the files.

/// JSON helpers for document variables.
enum VarJSON {
    static func load<T: Decodable>(_ doc: ArchiDocument, _ key: String, as: T.Type) -> T? {
        guard let s = doc.variable(key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ v: T, _ doc: inout ArchiDocument, _ key: String, empty: Bool) {
        if empty { doc.variables[key.uppercased()] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(v), let s = String(data: d, encoding: .utf8) { doc.setVariable(key, s) }
    }
}

// MARK: - Layer states

/// The saved settings of one layer inside a layer state.
public struct LayerSetting: Codable, Hashable {
    public var visible: Bool, frozen: Bool, locked: Bool, plot: Bool
    public var color: RGBA, linetype: String, lineweight: Double, transparency: Double
    public init(_ l: Layer) {
        visible = l.visible; frozen = l.frozen; locked = l.locked; plot = l.plot
        color = l.color; linetype = l.linetype; lineweight = l.lineweight; transparency = l.transparency
    }
}

/// A named snapshot of layer settings (LAYERSTATE). Stored as JSON in the document variable "LAYERSTATE:<NAME>", the same
/// format the Layer States Manager of the app uses.
public struct LayerState: Codable, Hashable {
    public var name: String
    public var description: String
    public var currentLayer: String?
    public var layers: [String: LayerSetting]
    public var date: Date?
    public init(name: String, description: String = "", currentLayer: String?, layers: [String: LayerSetting], date: Date? = nil) {
        self.name = name; self.description = description; self.currentLayer = currentLayer; self.layers = layers; self.date = date
    }
    private enum K: String, CodingKey { case name, description, currentLayer, layers, date }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        currentLayer = try c.decodeIfPresent(String.self, forKey: .currentLayer)
        layers = try c.decodeIfPresent([String: LayerSetting].self, forKey: .layers) ?? [:]
        date = try c.decodeIfPresent(Date.self, forKey: .date)
    }
    public func setting(for layer: String) -> LayerSetting? {
        layers[layer] ?? layers.first { $0.key.caseInsensitiveCompare(layer) == .orderedSame }?.value
    }
}

public enum LayerStates {
    public static let prefix = "LAYERSTATE:"
    /// Properties a restore can apply.
    public enum Property: String, CaseIterable, Codable { case onOff, frozen, locked, plot, color, linetype, lineweight, transparency, current }

    static func key(_ n: String) -> String { prefix + n.uppercased() }
    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .sortedKeys; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    public static func names(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
    }
    public static func named(_ n: String, _ doc: ArchiDocument) -> LayerState? {
        guard let s = doc.variables[key(n)], let d = s.data(using: .utf8), var st = try? decoder.decode(LayerState.self, from: d) else { return nil }
        if st.name.isEmpty { st.name = n.uppercased() }
        return st
    }
    public static func all(_ doc: ArchiDocument) -> [LayerState] { names(doc).compactMap { named($0, doc) } }
    public static func put(_ st: LayerState, _ doc: inout ArchiDocument) {
        if let d = try? encoder.encode(st), let s = String(data: d, encoding: .utf8) { doc.variables[key(st.name)] = s }
    }

    public static func capture(_ doc: ArchiDocument, name: String, description: String = "") -> LayerState {
        var m: [String: LayerSetting] = [:]
        for l in doc.layers { m[l.name] = LayerSetting(l) }
        return LayerState(name: name, description: description, currentLayer: doc.currentLayer, layers: m, date: Date())
    }
    /// Saves (or replaces) a state with the current layer settings.
    @discardableResult
    public static func save(_ doc: inout ArchiDocument, name: String, description: String = "") -> LayerState {
        let st = capture(doc, name: name, description: description)
        put(st, &doc)
        return st
    }
    @discardableResult
    public static func delete(_ doc: inout ArchiDocument, name: String) -> Bool {
        guard doc.variables[key(name)] != nil else { return false }
        doc.variables[key(name)] = nil
        return true
    }
    public static func rename(_ doc: inout ArchiDocument, from old: String, to new: String) -> Bool {
        guard var st = named(old, doc) else { return false }
        doc.variables[key(old)] = nil
        st.name = new; put(st, &doc)
        return true
    }
    /// Applies a state. Layers of the state missing from the drawing are created when `createMissing`; drawing layers not
    /// in the state are turned off when `turnOffOthers`. Returns the number of layers changed.
    @discardableResult
    public static func restore(_ st: LayerState, into doc: inout ArchiDocument, properties: Set<Property> = Set(Property.allCases),
                               createMissing: Bool = false, turnOffOthers: Bool = false) -> Int {
        var changed = 0
        if createMissing {
            for n in st.layers.keys.sorted() where doc.layer(named: n) == nil { doc.layers.append(Layer(name: n)); changed += 1 }
        }
        for i in doc.layers.indices {
            guard let s = st.setting(for: doc.layers[i].name) else {
                if turnOffOthers && doc.layers[i].visible { doc.layers[i].visible = false; changed += 1 }
                continue
            }
            let old = doc.layers[i]
            var l = old
            if properties.contains(.onOff) { l.visible = s.visible }
            if properties.contains(.frozen) { l.frozen = s.frozen }
            if properties.contains(.locked) { l.locked = s.locked }
            if properties.contains(.plot) { l.plot = s.plot }
            if properties.contains(.color) { l.color = s.color }
            if properties.contains(.linetype), doc.linetype(s.linetype) != nil { l.linetype = s.linetype }
            if properties.contains(.lineweight) { l.lineweight = s.lineweight }
            if properties.contains(.transparency) { l.transparency = s.transparency }
            if l != old { doc.layers[i] = l; changed += 1 }
        }
        if properties.contains(.current), let c = st.currentLayer, let l = doc.layer(named: c), !l.frozen { doc.currentLayer = l.name }
        return changed
    }
    /// Export format (JSON, extension .las.json).
    public static func export(_ st: LayerState) -> String {
        let enc = encoder; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(st)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    public static func importState(_ text: String) -> LayerState? {
        guard let d = text.data(using: .utf8), let st = try? decoder.decode(LayerState.self, from: d), !st.name.isEmpty else { return nil }
        return st
    }
}

// MARK: - Layer filters

/// A named layer filter: property rules (glob patterns / flags) or a group (explicit list). Filters can be inverted.
public struct LayerFilter: Codable, Hashable {
    public enum Kind: String, Codable { case property, group }
    public var name: String
    public var kind: Kind
    /// Property rules. Keys: name, color (hex or ACI), linetype, lineweight, on, frozen, locked, plot, used, description.
    /// Text values accept "*"/"?" wildcards and comma-separated alternatives; flags accept yes/no.
    public var rules: [String: String]
    public var layers: [String]
    public var inverted: Bool
    public init(name: String, kind: Kind = .property, rules: [String: String] = [:], layers: [String] = [], inverted: Bool = false) {
        self.name = name; self.kind = kind; self.rules = rules; self.layers = layers; self.inverted = inverted
    }
    private enum K: String, CodingKey { case name, kind, rules, layers, inverted }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .property
        rules = try c.decodeIfPresent([String: String].self, forKey: .rules) ?? [:]
        layers = try c.decodeIfPresent([String].self, forKey: .layers) ?? []
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
    }

    static func flag(_ s: String) -> Bool? {
        switch s.lowercased() { case "1", "yes", "y", "on", "true": return true; case "0", "no", "n", "off", "false": return false; default: return nil }
    }
    static func globAny(_ patterns: String, _ s: String) -> Bool {
        patterns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains { SettingsCommands.glob($0, s) }
    }

    /// Layers-panel pattern list "A-*,S-*,~*TEXT*": matches any positive item and no "~" item; wildcards * ? # @;
    /// a bare word without wildcards matches as a substring.
    public static func matchesPattern(_ pattern: String, _ name: String) -> Bool {
        let items = pattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return true }
        func m(_ item: String) -> Bool {
            if item.contains(where: { "*?#@".contains($0) }) { return wildcard(item, name) }
            return name.lowercased().contains(item.lowercased())
        }
        let neg = items.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
        let pos = items.filter { !$0.hasPrefix("~") }
        if neg.contains(where: m) { return false }
        return pos.isEmpty || pos.contains(where: m)
    }
    /// Wildcard match: * any run, ? one character, # a digit, @ a letter (case-insensitive).
    public static func wildcard(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        var dp = [[Bool]](repeating: [Bool](repeating: false, count: t.count + 1), count: p.count + 1)
        dp[0][0] = true
        for i in stride(from: 1, through: p.count, by: 1) {
            for j in 0...t.count {
                switch p[i - 1] {
                case "*": dp[i][j] = dp[i - 1][j] || (j > 0 && dp[i][j - 1])
                case "?": dp[i][j] = j > 0 && dp[i - 1][j - 1]
                case "#": dp[i][j] = j > 0 && t[j - 1].isNumber && dp[i - 1][j - 1]
                case "@": dp[i][j] = j > 0 && t[j - 1].isLetter && dp[i - 1][j - 1]
                default: dp[i][j] = j > 0 && t[j - 1] == p[i - 1] && dp[i - 1][j - 1]
                }
            }
        }
        return dp[p.count][t.count]
    }

    public func matches(_ l: Layer, used: Set<String>) -> Bool {
        var ok: Bool
        switch kind {
        case .group: ok = layers.contains { $0.caseInsensitiveCompare(l.name) == .orderedSame }
        case .property:
            ok = true
            for (k, v) in rules {
                switch k.lowercased() {
                case "name": ok = ok && LayerFilter.globAny(v, l.name)
                case "pattern": ok = ok && LayerFilter.matchesPattern(v, l.name)
                case "visible": ok = ok && LayerFilter.flag(v).map { $0 == (l.visible && !l.frozen) } ?? true
                case "description": ok = ok && LayerFilter.globAny(v, l.description)
                case "linetype": ok = ok && LayerFilter.globAny(v, l.linetype)
                case "color":
                    let alts = v.split(separator: ",").compactMap { ColorRef.parse(String($0)).flatMap(SettingsCommands.rgba)?.hex }
                    ok = ok && alts.contains(l.color.hex)
                case "lineweight": ok = ok && (Double(v).map { abs($0 - l.lineweight) < 1e-9 } ?? false)
                case "on": ok = ok && LayerFilter.flag(v).map { $0 == l.visible } ?? true
                case "frozen": ok = ok && LayerFilter.flag(v).map { $0 == l.frozen } ?? true
                case "locked": ok = ok && LayerFilter.flag(v).map { $0 == l.locked } ?? true
                case "plot": ok = ok && LayerFilter.flag(v).map { $0 == l.plot } ?? true
                case "used": ok = ok && LayerFilter.flag(v).map { $0 == used.contains(l.name.lowercased()) } ?? true
                default: break
                }
            }
        }
        return inverted ? !ok : ok
    }
}

public enum LayerFilters {
    public static let variable = "LAYERFILTERS"
    /// Filters saved by the Layers panel ("LAYERFILTER:<NAME>" = "#on #used #unlocked A-*,~*TEXT*").
    public static let panelPrefix = "LAYERFILTER:"
    public static func panelFilter(name: String, stored: String) -> LayerFilter {
        var rules: [String: String] = [:], rest: [String] = []
        for t in stored.split(separator: " ").map(String.init) {
            switch t.lowercased() {
            case "#on": rules["visible"] = "yes"
            case "#used": rules["used"] = "yes"
            case "#unlocked": rules["locked"] = "no"
            default: rest.append(t)
            }
        }
        let pat = rest.joined(separator: " ")
        if !pat.isEmpty { rules["pattern"] = pat }
        return LayerFilter(name: name, rules: rules)
    }
    /// Named filters: those created by LAYFILTER (variable LAYERFILTERS) followed by the Layers panel's saved filters.
    public static func all(_ doc: ArchiDocument) -> [LayerFilter] {
        var list = VarJSON.load(doc, variable, as: [LayerFilter].self) ?? []
        for (k, v) in doc.variables where k.hasPrefix(panelPrefix) {
            let n = String(k.dropFirst(panelPrefix.count))
            if !list.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { list.append(panelFilter(name: n, stored: v)) }
        }
        return list
    }
    public static func store(_ f: [LayerFilter], _ doc: inout ArchiDocument) {
        // Panel filters that were deleted from the list are removed from the drawing too.
        for k in doc.variables.keys where k.hasPrefix(panelPrefix) {
            let n = String(k.dropFirst(panelPrefix.count))
            if !f.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { doc.variables[k] = nil }
        }
        let own = f.filter { x in !(doc.variables[panelPrefix + x.name.uppercased()].map { panelFilter(name: x.name, stored: $0) == x } ?? false) }
        VarJSON.save(own, &doc, variable, empty: own.isEmpty)
    }
    public static func named(_ n: String, _ doc: ArchiDocument) -> LayerFilter? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public static func upsert(_ f: LayerFilter, _ doc: inout ArchiDocument) {
        var list = all(doc).filter { $0.name.caseInsensitiveCompare(f.name) != .orderedSame }
        list.append(f); store(list, &doc)
    }
    /// Layers passing a filter, in drawing order.
    public static func layers(_ f: LayerFilter, doc: ArchiDocument) -> [Layer] {
        let used = SettingsCommands.usedLayers(doc)
        return doc.layers.filter { f.matches($0, used: used) }
    }
    /// Parses "name=A-*,S-* on=yes color=1" into rules.
    public static func parseRules(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in s.split(separator: " ") where part.contains("=") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0].lowercased()] = kv[1] }
        }
        return out
    }
}

// MARK: - Layer translator

/// Maps layers to standard layers (LAYTRANS): objects move to the target layers, which are created with the standard's
/// properties; translated source layers are purged when empty.
public enum LayerTranslator {
    public struct Mapping: Hashable { public var from: String; public var to: String
        public init(_ from: String, _ to: String) { self.from = from; self.to = to } }

    /// Parses mapping lines "FROM=TO" or "FROM,TO" (wildcards allowed in FROM; # comments).
    public static func parseMappings(_ text: String) -> [Mapping] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { return nil }
            let sep: Character = line.contains("=") ? "=" : ","
            let kv = line.split(separator: sep, maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty, !kv[1].isEmpty else { return nil }
            return Mapping(kv[0], kv[1])
        }
    }

    public struct Result: Equatable { public var moved: Int; public var translated: [String: String]; public var purged: [String] }

    /// Translates layers. `standard` supplies target layer properties (e.g. layers of a standards drawing); when
    /// `forceByLayer` objects' explicit color/linetype/lineweight are reset to ByLayer; empty source layers are purged when `purge`.
    @discardableResult
    public static func translate(_ doc: inout ArchiDocument, mappings: [Mapping], standard: [Layer] = [], forceByLayer: Bool = false, purge: Bool = true) -> Result {
        var map: [String: String] = [:]   // lowercased source → target name
        for l in doc.layers {
            guard let m = mappings.first(where: { SettingsCommands.glob($0.from, l.name) }), m.to.caseInsensitiveCompare(l.name) != .orderedSame else { continue }
            map[l.name.lowercased()] = m.to
        }
        guard !map.isEmpty else { return Result(moved: 0, translated: [:], purged: []) }
        for target in Set(map.values) {
            if let std = standard.first(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
                if let i = doc.layerIndex(target) { let keepName = doc.layers[i].name; doc.layers[i] = std; doc.layers[i].name = keepName }
                else { doc.layers.append(std) }
            } else if doc.layer(named: target) == nil {
                // Take the properties of the first source layer that maps to it.
                let src = doc.layers.first { map[$0.name.lowercased()] == target }
                var l = src ?? Layer(name: target); l.name = target
                doc.layers.append(l)
            }
        }
        var moved = 0
        var resolved: [String: String] = [:]
        for (k, t) in map { resolved[k] = doc.layer(named: t)?.name ?? t }
        func fix(_ e: inout Entity) {
            if let t = resolved[e.layer.lowercased()] {
                e.layer = t; moved += 1
                if forceByLayer { e.color = .byLayer; e.linetype = nil; e.lineweight = nil }
            }
        }
        for i in doc.entities.indices { fix(&doc.entities[i]) }
        for k in Array(doc.blocks.keys) { for j in doc.blocks[k]!.entities.indices { fix(&doc.blocks[k]!.entities[j]) } }
        for li in doc.layouts.indices { for j in doc.layouts[li].entities.indices { fix(&doc.layouts[li].entities[j]) } }
        for i in doc.elements.indices { if let t = resolved[doc.elements[i].layer.lowercased()] { doc.elements[i].layer = t; moved += 1 } }
        if let t = resolved[doc.currentLayer.lowercased()] { doc.currentLayer = t }
        var purged: [String] = []
        if purge {
            let used = SettingsCommands.usedLayers(doc)
            doc.layers.removeAll { l in
                let gone = map[l.name.lowercased()] != nil && !used.contains(l.name.lowercased()) && l.name != "0" && l.name != doc.currentLayer
                if gone { purged.append(l.name) }
                return gone
            }
        }
        var translated: [String: String] = [:]
        for (k, v) in map { translated[k] = v }
        return Result(moved: moved, translated: translated, purged: purged)
    }
}

// MARK: - Layer walk, merge and previous

public enum LayerWalk {
    /// Number of objects on each layer (entities, BIM elements, objects inside blocks and on sheets), in layer order.
    public static func counts(_ doc: ArchiDocument) -> [(layer: String, count: Int)] {
        var c: [String: Int] = [:]
        for e in doc.entities { c[e.layer.lowercased(), default: 0] += 1 }
        for e in doc.elements { c[e.layer.lowercased(), default: 0] += 1 }
        for b in doc.blocks.values { for e in b.entities { c[e.layer.lowercased(), default: 0] += 1 } }
        for l in doc.layouts { for e in l.entities { c[e.layer.lowercased(), default: 0] += 1 } }
        return doc.layers.map { ($0.name, c[$0.name.lowercased()] ?? 0) }
    }
    /// Shows only the given layers (the others are turned off; walked layers are turned on and thawed). Returns the document.
    public static func show(_ names: [String], in doc: ArchiDocument) -> ArchiDocument {
        var d = doc
        let keep = Set(names.map { $0.lowercased() })
        for i in d.layers.indices {
            let on = keep.contains(d.layers[i].name.lowercased())
            d.layers[i].visible = on
            if on { d.layers[i].frozen = false }
        }
        return d
    }
    /// Objects on the given layers.
    public static func objects(on names: [String], doc: ArchiDocument) -> [EntityID] {
        let keep = Set(names.map { $0.lowercased() })
        return doc.entities.filter { keep.contains($0.layer.lowercased()) }.map(\.id) + doc.elements.filter { keep.contains($0.layer.lowercased()) }.map(\.id)
    }
}

public enum LayerMerge {
    /// Moves every object of the source layers onto `target` and deletes the source layers (LAYMRG). Returns objects moved.
    @discardableResult
    public static func merge(_ sources: [String], into target: String, doc: inout ArchiDocument) -> Int {
        let src = Set(sources.map { $0.lowercased() }).subtracting([target.lowercased()])
        guard !src.isEmpty else { return 0 }
        doc.ensureLayer(target)
        let t = doc.layer(named: target)?.name ?? target
        var n = 0
        for i in doc.entities.indices where src.contains(doc.entities[i].layer.lowercased()) { doc.entities[i].layer = t; n += 1 }
        for i in doc.elements.indices where src.contains(doc.elements[i].layer.lowercased()) { doc.elements[i].layer = t; n += 1 }
        for k in Array(doc.blocks.keys) { for j in doc.blocks[k]!.entities.indices where src.contains(doc.blocks[k]!.entities[j].layer.lowercased()) { doc.blocks[k]!.entities[j].layer = t; n += 1 } }
        for li in doc.layouts.indices { for j in doc.layouts[li].entities.indices where src.contains(doc.layouts[li].entities[j].layer.lowercased()) { doc.layouts[li].entities[j].layer = t; n += 1 } }
        if src.contains(doc.currentLayer.lowercased()) { doc.currentLayer = t }
        doc.layers.removeAll { src.contains($0.name.lowercased()) && $0.name != "0" }
        return n
    }
}

// MARK: - Per-viewport layer freeze (VPLAYER)

/// Layers frozen in individual sheet viewports, keyed "<layout name>#<viewport index>".
public enum ViewportLayers {
    public static let variable = "VPLAYER"
    public static func key(layout: String, viewport: Int) -> String { "\(layout)#\(viewport)" }
    public static func all(_ doc: ArchiDocument) -> [String: [String]] { VarJSON.load(doc, variable, as: [String: [String]].self) ?? [:] }
    static func store(_ m: [String: [String]], _ doc: inout ArchiDocument) { VarJSON.save(m, &doc, variable, empty: m.isEmpty) }

    public static func frozen(_ doc: ArchiDocument, layout: String, viewport: Int) -> Set<String> {
        Set((all(doc)[key(layout: layout, viewport: viewport)] ?? []).map { $0.lowercased() })
    }
    /// Whether a layer is displayed in a viewport (global on/freeze and the viewport's own freeze list).
    public static func isVisible(_ layer: String, doc: ArchiDocument, layout: String, viewport: Int) -> Bool {
        doc.isVisible(layer: layer) && !frozen(doc, layout: layout, viewport: viewport).contains(layer.lowercased())
    }
    /// The model entities displayed by a viewport (for sheet rendering).
    public static func visibleEntities(_ doc: ArchiDocument, layout: String, viewport: Int) -> [Entity] {
        let fz = frozen(doc, layout: layout, viewport: viewport)
        return doc.entities.filter { doc.isVisible(layer: $0.layer) && !fz.contains($0.layer.lowercased()) }
    }
    /// A copy of the document with the viewport's frozen layers frozen globally (what the viewport shows).
    public static func document(for doc: ArchiDocument, layout: String, viewport: Int) -> ArchiDocument {
        let fz = frozen(doc, layout: layout, viewport: viewport)
        guard !fz.isEmpty else { return doc }
        var d = doc
        for i in d.layers.indices where fz.contains(d.layers[i].name.lowercased()) { d.layers[i].frozen = true }
        return d
    }
    /// Freezes (or thaws) layers matching the patterns in the given viewports. Returns the number of changes.
    @discardableResult
    public static func set(_ doc: inout ArchiDocument, patterns: String, frozen freeze: Bool, layout: String, viewports: [Int]) -> Int {
        var m = all(doc)
        let names = SettingsCommands.matchLayers(doc, patterns).map { doc.layers[$0].name }
        var n = 0
        for v in viewports {
            let k = key(layout: layout, viewport: v)
            var cur = m[k] ?? []
            for name in names {
                let has = cur.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                if freeze && !has { cur.append(name); n += 1 }
                if !freeze && has { cur.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }; n += 1 }
            }
            m[k] = cur.isEmpty ? nil : cur.sorted()
        }
        store(m, &doc)
        return n
    }
    /// Thaws every layer in the viewports (Reset).
    public static func reset(_ doc: inout ArchiDocument, layout: String, viewports: [Int]) {
        var m = all(doc)
        for v in viewports { m[key(layout: layout, viewport: v)] = nil }
        store(m, &doc)
    }
}
