// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Named layer states (LAYERSTATE): snapshots of every layer's on/freeze/lock/plot/color/linetype/lineweight,
/// stored in the document variables as JSON so they travel with the .archi file.
enum LayerStates {
    struct Entry: Codable, Hashable {
        var visible: Bool; var frozen: Bool; var locked: Bool; var plot: Bool
        var color: RGBA; var linetype: String; var lineweight: Double; var transparency: Double
    }
    struct State: Codable, Hashable {
        var layers: [String: Entry]
        var currentLayer: String?
        var date: Date?
    }
    static let prefix = "LAYERSTATE:"

    static func key(_ name: String) -> String { prefix + name.uppercased() }

    static func names(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
    }

    static func capture(_ doc: ArchiDocument) -> State {
        var m: [String: Entry] = [:]
        for l in doc.layers {
            m[l.name] = Entry(visible: l.visible, frozen: l.frozen, locked: l.locked, plot: l.plot, color: l.color,
                              linetype: l.linetype, lineweight: l.lineweight, transparency: l.transparency)
        }
        return State(layers: m, currentLayer: doc.currentLayer, date: Date())
    }

    static func state(_ name: String, in doc: ArchiDocument) -> State? {
        guard let s = doc.variables[key(name)], let data = s.data(using: .utf8) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(State.self, from: data)
    }

    static func save(_ name: String, in doc: inout ArchiDocument) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .sortedKeys
        if let data = try? enc.encode(capture(doc)), let s = String(data: data, encoding: .utf8) { doc.variables[key(name)] = s }
    }

    static func delete(_ name: String, in doc: inout ArchiDocument) { doc.variables[key(name)] = nil }

    /// Restores a state; layers created after the state was saved are left unchanged. Returns the number of layers changed.
    @discardableResult
    static func restore(_ name: String, in doc: inout ArchiDocument, restoreCurrentLayer: Bool = true) -> Int? {
        guard let st = state(name, in: doc) else { return nil }
        var n = 0
        for i in doc.layers.indices {
            guard let e = st.layers[doc.layers[i].name] ?? st.layers.first(where: { $0.key.caseInsensitiveCompare(doc.layers[i].name) == .orderedSame })?.value else { continue }
            var l = doc.layers[i]
            l.visible = e.visible; l.frozen = e.frozen; l.locked = e.locked; l.plot = e.plot
            l.color = e.color; l.linetype = e.linetype; l.lineweight = e.lineweight; l.transparency = e.transparency
            if l != doc.layers[i] { doc.layers[i] = l; n += 1 }
        }
        if restoreCurrentLayer, let c = st.currentLayer, doc.layer(named: c) != nil, !(doc.layer(named: c)?.frozen ?? false) { doc.currentLayer = c }
        return n
    }

    static func rename(_ old: String, to new: String, in doc: inout ArchiDocument) {
        guard let v = doc.variables[key(old)] else { return }
        doc.variables[key(old)] = nil
        doc.variables[key(new)] = v
    }
}

/// Layer filters for the Layers panel: name wildcards (*, ?, comma-separated, ~ to exclude) plus property flags.
struct LayerFilter: Hashable {
    var pattern = ""
    var onlyVisible = false
    var onlyUsed = false
    var onlyUnlocked = false

    static let prefix = "LAYERFILTER:"

    /// "on used A-*" style stored text: flags then the pattern.
    var stored: String {
        var p: [String] = []
        if onlyVisible { p.append("#on") }
        if onlyUsed { p.append("#used") }
        if onlyUnlocked { p.append("#unlocked") }
        p.append(pattern)
        return p.joined(separator: " ")
    }
    init(pattern: String = "", onlyVisible: Bool = false, onlyUsed: Bool = false, onlyUnlocked: Bool = false) {
        self.pattern = pattern; self.onlyVisible = onlyVisible; self.onlyUsed = onlyUsed; self.onlyUnlocked = onlyUnlocked
    }
    init(stored: String) {
        var rest: [String] = []
        for t in stored.split(separator: " ").map(String.init) {
            switch t.lowercased() {
            case "#on": onlyVisible = true
            case "#used": onlyUsed = true
            case "#unlocked": onlyUnlocked = true
            default: rest.append(t)
            }
        }
        pattern = rest.joined(separator: " ")
    }

    var isEmpty: Bool { pattern.trimmingCharacters(in: .whitespaces).isEmpty && !onlyVisible && !onlyUsed && !onlyUnlocked }

    /// AutoCAD-style wildcard match (case-insensitive): * any run, ? one character, # a digit, @ a letter.
    static func wildcard(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        var dp = Array(repeating: Array(repeating: false, count: t.count + 1), count: p.count + 1)
        dp[0][0] = true
        for i in 1...max(p.count, 1) where i <= p.count { if p[i - 1] == "*" { dp[i][0] = dp[i - 1][0] } }
        if p.isEmpty { return t.isEmpty }
        for i in 1...p.count {
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

    /// Pattern list "A-*,S-*,~*TEXT*": a name matches if it matches any positive item and no ~ item.
    /// A bare word without wildcards matches as a substring.
    static func matchesPattern(_ pattern: String, _ name: String) -> Bool {
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

    func matches(_ l: Layer, used: Bool) -> Bool {
        if onlyVisible && (!l.visible || l.frozen) { return false }
        if onlyUnlocked && l.locked { return false }
        if onlyUsed && !used { return false }
        return LayerFilter.matchesPattern(pattern, l.name)
    }

    static func names(_ doc: ArchiDocument) -> [String] {
        doc.variables.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
    }
    static func saved(_ name: String, in doc: ArchiDocument) -> LayerFilter? {
        doc.variables[prefix + name.uppercased()].map { LayerFilter(stored: $0) }
    }
}
