// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Dynamic block visibility states. A block's states are listed in the variable "BVSTATES:<block>"; an entity of the block is
/// hidden in the states listed in its prop "visHidden". A reference showing a state points at a generated variant block
/// "<block>$<state>" (so display, export and snaps need no special handling) and keeps "visBase"/"visibility" props.
public enum BlockVisibility {
    public static let separator = "$"
    public static func key(_ block: String) -> String { "BVSTATES:" + block }
    public static func states(_ block: String, _ doc: ArchiDocument) -> [String] {
        (doc.variable(key(block)) ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }
    public static func setStates(_ block: String, _ states: [String], _ doc: inout ArchiDocument) {
        if states.isEmpty { doc.variables[key(block).uppercased()] = nil } else { doc.setVariable(key(block), states.joined(separator: "|")) }
    }
    public static func variantName(_ block: String, _ state: String) -> String { block + separator + state }
    /// Base block of a reference (itself when it has no visibility state).
    public static func baseBlock(of ins: InsertGeom, props: [String: String]) -> String { props["visBase"] ?? ins.block }
    public static func isHidden(_ e: Entity, in state: String) -> Bool {
        (e.props["visHidden"] ?? "").split(separator: "|").contains { $0.caseInsensitiveCompare(state) == .orderedSame }
    }
    public static func setHidden(_ e: inout Entity, _ hidden: Bool, in state: String) {
        var s = (e.props["visHidden"] ?? "").split(separator: "|").map(String.init).filter { $0.caseInsensitiveCompare(state) != .orderedSame }
        if hidden { s.append(state) }
        e.props["visHidden"] = s.isEmpty ? nil : s.joined(separator: "|")
    }
    /// Rebuilds the variant blocks of a block and repoints its references.
    public static func regenerate(_ block: String, _ doc: inout ArchiDocument) {
        guard let base = doc.blocks[block] else { return }
        let sts = states(block, doc)
        // Remove stale variants.
        for k in doc.blocks.keys where k.hasPrefix(block + separator) && !sts.contains(where: { variantName(block, $0) == k }) { doc.blocks[k] = nil }
        for s in sts {
            var v = base
            v.name = variantName(block, s)
            v.entities = base.entities.filter { !isHidden($0, in: s) }
            v.description = "Visibility state \(s) of \(block)"
            doc.blocks[v.name] = v
        }
        for i in doc.entities.indices {
            guard case .insert(var ins) = doc.entities[i].geometry, baseBlock(of: ins, props: doc.entities[i].props) == block,
                  let st = doc.entities[i].props["visibility"] else { continue }
            if let s = sts.first(where: { $0.caseInsensitiveCompare(st) == .orderedSame }) { ins.block = variantName(block, s) }
            else { ins.block = block; doc.entities[i].props["visibility"] = nil; doc.entities[i].props["visBase"] = nil }
            doc.entities[i].geometry = .insert(ins)
        }
    }
    /// Shows a state on a reference (nil = the full base block).
    public static func apply(_ state: String?, toInsert i: Int, _ doc: inout ArchiDocument) {
        guard case .insert(var ins) = doc.entities[i].geometry else { return }
        let block = baseBlock(of: ins, props: doc.entities[i].props)
        if let s = state, let st = states(block, doc).first(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
            if doc.blocks[variantName(block, st)] == nil { regenerate(block, &doc) }
            ins.block = variantName(block, st)
            doc.entities[i].props["visBase"] = block; doc.entities[i].props["visibility"] = st
        } else {
            ins.block = block
            doc.entities[i].props["visBase"] = nil; doc.entities[i].props["visibility"] = nil
        }
        doc.entities[i].geometry = .insert(ins)
    }
}

/// Persistent command history file (one command line per line).
public enum CommandHistoryFile {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/history.txt")
    }
    public static func append(_ line: String, to url: URL) {
        let l = line.replacingOccurrences(of: "\n", with: " ") + "\n"
        guard let data = l.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
        else { try? data.write(to: url) }
    }
    public static func load(_ url: URL, limit: Int = 1000) -> [String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(s.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.suffix(limit))
    }
    public static func save(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Hidden / isolated objects (HIDEOBJECTS, ISOLATEOBJECTS): removed from the drawing and kept in the variable HIDDENOBJECTS
/// so they survive saving and are restored by UNISOLATEOBJECTS.
public struct HiddenObjects: Codable, Equatable {
    public var entities: [Entity] = []
    public var elements: [BIMElement] = []
    public init() {}
    public static let variable = "HIDDENOBJECTS"
    public static func load(_ doc: ArchiDocument) -> HiddenObjects {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8), let h = try? JSONDecoder().decode(HiddenObjects.self, from: d) else { return HiddenObjects() }
        return h
    }
    public func save(_ doc: inout ArchiDocument) {
        if entities.isEmpty && elements.isEmpty { doc.variables[HiddenObjects.variable] = nil; return }
        if let d = try? JSONEncoder().encode(self), let s = String(data: d, encoding: .utf8) { doc.setVariable(HiddenObjects.variable, s) }
    }
    /// Hides objects (openings follow their host wall). Returns the number hidden.
    @discardableResult
    public static func hide(_ ids: Set<EntityID>, in doc: inout ArchiDocument) -> Int {
        var all = ids
        for el in doc.elements { if case .opening(let o) = el.geometry, ids.contains(o.hostWall) { all.insert(el.id) } }
        var h = load(doc)
        let ents = doc.entities.filter { all.contains($0.id) }, els = doc.elements.filter { all.contains($0.id) }
        guard !ents.isEmpty || !els.isEmpty else { return 0 }
        h.entities += ents; h.elements += els
        doc.entities.removeAll { all.contains($0.id) }
        doc.elements.removeAll { all.contains($0.id) }
        h.save(&doc)
        return ents.count + els.count
    }
    /// Restores every hidden object. Returns the number restored.
    @discardableResult
    public static func restoreAll(in doc: inout ArchiDocument) -> Int {
        let h = load(doc)
        let existing = Set(doc.allIDs)
        for e in h.entities where !existing.contains(e.id) { doc.ensureLayer(e.layer); doc.entities.append(e) }
        for e in h.elements where !existing.contains(e.id) { doc.ensureLayer(e.layer); doc.elements.append(e) }
        if let m = (h.entities.map(\.id) + h.elements.map(\.id)).max(), m >= doc.nextID { doc.nextID = m + 1 }
        doc.variables[HiddenObjects.variable] = nil
        return h.entities.count + h.elements.count
    }
}
