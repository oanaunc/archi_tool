// Oanarina Archi Tool — GPL-3.0-or-later
// Co-editing (COL-016): a conflict-free replicated document. Every object of a drawing (entity, element, layer,
// block, variable, level, material, layout, project info and the remaining settings) is a last-writer-wins register
// stamped with a Lamport clock and the site name; tombstones record deletions. Replicas exchange operations through
// append-only logs in a shared folder (iCloud Drive, a network share, Dropbox…) — one "<site>.ops.jsonl" per user —
// and converge to the same document whatever the order of synchronisation. New objects get ids from a range owned by
// the site, so ids (and references such as a door's host wall) never collide between users. Concurrent edits of the
// same object keep the later stamp and are reported as conflicts; edits of different objects are all kept.
import Foundation

public struct CoEditStamp: Codable, Hashable, Comparable {
    public var clock: Int
    public var site: String
    public static func < (a: CoEditStamp, b: CoEditStamp) -> Bool { a.clock != b.clock ? a.clock < b.clock : a.site < b.site }
}

public struct CoEditOp: Codable, Hashable {
    public var key: String
    /// Canonical JSON of the object; nil = deleted.
    public var value: Data?
    public var stamp: CoEditStamp
}

public final class CoEditSession {
    public let site: String
    public private(set) var clock = 0
    /// Latest register per object key.
    private(set) var registers: [String: (stamp: CoEditStamp, value: Data?)] = [:]
    /// First stamp of each key (canonical ordering of entities, layers, …).
    private var created: [String: CoEditStamp] = [:]
    /// Object values as of the last commit/materialise (to find local edits).
    private var synced: [String: Data] = [:]
    /// Operations not yet written to the shared log.
    public private(set) var outbox: [CoEditOp] = []
    private var readOffsets: [String: UInt64] = [:]
    public private(set) var conflicts: [String] = []

    /// First id of the range owned by `site` (1e9 ids per site; stays below 2^53 for JavaScript clients).
    public static func idBase(_ site: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in site.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return (Int(h % 999_999) + 1) * 1_000_000_000
    }
    public var idBase: Int { Self.idBase(site) }

    /// Starts a session on a document that every participant opened from the same file.
    public init(site: String, document: ArchiDocument) {
        self.site = site
        let objs = Self.objects(document)
        for (k, v) in objs {
            let s = CoEditStamp(clock: 0, site: "")
            registers[k] = (s, v)
            created[k] = CoEditStamp(clock: 0, site: String(format: "%09d", Self.initialOrder(document, k)))
        }
        synced = objs
    }

    static func initialOrder(_ d: ArchiDocument, _ key: String) -> Int {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return 0 }
        switch parts[0] {
        case "e": return d.entities.firstIndex { "\($0.id)" == parts[1] } ?? 0
        case "b": return d.elements.firstIndex { "\($0.id)" == parts[1] } ?? 0
        case "l": return d.layers.firstIndex { $0.name == parts[1] } ?? 0
        case "lv": return d.levels.firstIndex { "\($0.id)" == parts[1] } ?? 0
        case "m": return d.materials.firstIndex { $0.name == parts[1] } ?? 0
        case "lo": return d.layouts.firstIndex { $0.name == parts[1] } ?? 0
        default: return 0
        }
    }

    // MARK: Objects

    static func enc<T: Encodable>(_ v: T) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return (try? e.encode(v)) ?? Data()
    }
    static func dec<T: Decodable>(_ t: T.Type, _ d: Data) -> T? {
        let x = JSONDecoder(); x.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try? x.decode(t, from: d)
    }

    /// The document split into independently mergeable objects.
    public static func objects(_ d: ArchiDocument) -> [String: Data] {
        var o: [String: Data] = [:]
        for e in d.entities { o["e:\(e.id)"] = enc(e) }
        for e in d.elements { o["b:\(e.id)"] = enc(e) }
        for l in d.layers { o["l:\(l.name)"] = enc(l) }
        for (n, b) in d.blocks { o["k:\(n)"] = enc(b) }
        for (n, v) in d.variables where n != "EDITTIMELAST" { o["v:\(n)"] = enc(v) }
        for l in d.levels { o["lv:\(l.id)"] = enc(l) }
        for m in d.materials { o["m:\(m.name)"] = enc(m) }
        for l in d.layouts { o["lo:\(l.name)"] = enc(l) }
        o["info"] = enc(d.info)
        var rest = d
        rest.entities = []; rest.elements = []; rest.layers = []; rest.blocks = [:]; rest.variables = [:]; rest.levels = []
        rest.materials = []; rest.layouts = []; rest.info = ProjectInfo(); rest.nextID = 1; rest.formatVersion = ArchiDocument.currentFormatVersion
        o["rest"] = enc(rest)
        return o
    }

    /// Rebuilds the document from the registers (canonical order), keeping `local`'s id counter in the site's range.
    public func materialize(local: ArchiDocument) -> ArchiDocument {
        var d = registers["rest"]?.value.flatMap { Self.dec(ArchiDocument.self, $0) } ?? local
        let live = registers.filter { $0.value.value != nil }.sorted { (created[$0.key] ?? $0.value.stamp, $0.key) < (created[$1.key] ?? $1.value.stamp, $1.key) }
        d.entities = []; d.elements = []; d.layers = []; d.blocks = [:]; d.variables = [:]; d.levels = []; d.materials = []; d.layouts = []
        for (k, r) in live {
            guard let v = r.value else { continue }
            if k.hasPrefix("e:"), let x = Self.dec(Entity.self, v) { d.entities.append(x) }
            else if k.hasPrefix("b:"), let x = Self.dec(BIMElement.self, v) { d.elements.append(x) }
            else if k.hasPrefix("lv:"), let x = Self.dec(Level.self, v) { d.levels.append(x) }
            else if k.hasPrefix("lo:"), let x = Self.dec(Layout.self, v) { d.layouts.append(x) }
            else if k.hasPrefix("l:"), let x = Self.dec(Layer.self, v) { d.layers.append(x) }
            else if k.hasPrefix("k:"), let x = Self.dec(Block.self, v) { d.blocks[String(k.dropFirst(2))] = x }
            else if k.hasPrefix("v:"), let x = Self.dec(String.self, v) { d.variables[String(k.dropFirst(2))] = x }
            else if k.hasPrefix("m:"), let x = Self.dec(Material.self, v) { d.materials.append(x) }
            else if k == "info", let x = Self.dec(ProjectInfo.self, v) { d.info = x }
        }
        if let t = local.variables["EDITTIMELAST"] { d.variables["EDITTIMELAST"] = t }
        if d.layers.isEmpty { d.layers = [Layer(name: "0")] }
        if d.levels.isEmpty { d.levels = local.levels }
        d.nextID = nextLocalID(d)
        synced = Self.objects(d)
        return d
    }

    /// Next id in this site's range.
    public func nextLocalID(_ d: ArchiDocument) -> Int {
        let lo = idBase, hi = idBase + 1_000_000_000
        let own = (d.entities.map(\.id) + d.elements.map(\.id)).filter { $0 >= lo && $0 < hi }
        return (own.max() ?? (lo - 1)) + 1
    }

    /// Moves the document's id counter into this site's range (call after joining).
    public func claimIDs(_ d: inout ArchiDocument) { d.nextID = max(d.nextID >= idBase && d.nextID < idBase + 1_000_000_000 ? d.nextID : 0, nextLocalID(d)) }

    // MARK: Local edits

    /// Turns the differences since the last sync into operations (queued in the outbox). Returns them.
    @discardableResult
    public func commit(_ d: ArchiDocument) -> [CoEditOp] {
        let cur = Self.objects(d)
        var ops: [CoEditOp] = []
        let changed = cur.filter { synced[$0.key] != $0.value }.map(\.key) + synced.keys.filter { cur[$0] == nil }
        guard !changed.isEmpty else { return [] }
        clock += 1
        let st = CoEditStamp(clock: clock, site: site)
        for k in changed.sorted() {
            let op = CoEditOp(key: k, value: cur[k], stamp: st)
            ops.append(op)
            registers[k] = (st, cur[k])
            if created[k] == nil { created[k] = st }
        }
        synced = cur
        outbox += ops
        return ops
    }

    // MARK: Remote operations

    /// Applies remote operations (idempotent, any order). Returns the keys that changed.
    @discardableResult
    public func apply(_ ops: [CoEditOp], localPending: Set<String> = []) -> [String] {
        var changed: [String] = []
        for op in ops where op.stamp.site != site {
            clock = max(clock, op.stamp.clock)
            if created[op.key] == nil || op.stamp < created[op.key]! { if op.value != nil || created[op.key] == nil { created[op.key] = op.stamp } }
            if let r = registers[op.key], !(r.stamp < op.stamp) {
                if r.stamp != op.stamp, r.stamp.site == site, r.value != op.value { conflicts.append(op.key) }
                continue
            }
            if localPending.contains(op.key) { conflicts.append(op.key) }
            if let r = registers[op.key], r.stamp.site == site, r.stamp.clock > 0, r.value != op.value, !conflicts.contains(op.key) { conflicts.append(op.key) }
            registers[op.key] = (op.stamp, op.value)
            changed.append(op.key)
        }
        return changed
    }

    // MARK: Shared-folder transport

    public struct SyncResult { public var sent: Int; public var received: Int; public var conflicts: [String]; public var document: ArchiDocument }

    static func logURL(_ folder: URL, _ site: String) -> URL {
        folder.appendingPathComponent(site.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.map(String.init).joined() + ".ops.jsonl")
    }

    /// Commits local edits, appends them to this site's log, reads the other logs and returns the merged document.
    public func sync(_ d: ArchiDocument, folder: URL) throws -> SyncResult {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        commit(d)
        let sent = outbox.count
        if !outbox.isEmpty {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
            var chunk = Data()
            for op in outbox { chunk += try enc.encode(op); chunk.append(0x0A) }
            let mine = Self.logURL(folder, site)
            if !fm.fileExists(atPath: mine.path) { fm.createFile(atPath: mine.path, contents: nil) }
            let h = try FileHandle(forWritingTo: mine)
            try h.seekToEnd(); try h.write(contentsOf: chunk); try h.close()
            outbox = []
        }
        let before = conflicts.count
        var received = 0
        let logs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasSuffix(".ops.jsonl") && $0.lastPathComponent != Self.logURL(folder, site).lastPathComponent }
        for u in logs.sorted(by: { $0.path < $1.path }) {
            guard let h = try? FileHandle(forReadingFrom: u) else { continue }
            let off = readOffsets[u.lastPathComponent] ?? 0
            try h.seek(toOffset: off)
            let data = try h.readToEnd() ?? Data()
            try? h.close()
            // Only complete lines (a writer may be mid-append).
            guard let lastNL = data.lastIndex(of: 0x0A) else { continue }
            let complete = data[data.startIndex...lastNL]
            readOffsets[u.lastPathComponent] = off + UInt64(complete.count)
            let dec = JSONDecoder()
            let ops = complete.split(separator: 0x0A).compactMap { try? dec.decode(CoEditOp.self, from: Data($0)) }
            received += apply(ops).count
        }
        let merged = materialize(local: d)
        return SyncResult(sent: sent, received: received, conflicts: Array(conflicts[before...]), document: merged)
    }
}

/// Co-editing sessions of editors (COEDIT command).
public enum CoEdit {
    struct Link { var session: CoEditSession; var folder: URL }
    @MainActor static var links: [ObjectIdentifier: Link] = [:]

    @MainActor public static func session(of ed: Editor) -> CoEditSession? { links[ObjectIdentifier(ed)]?.session }

    @MainActor public static func join(_ ed: Editor, folder: URL, site: String) {
        let s = CoEditSession(site: site, document: ed.doc)
        s.claimIDs(&ed.doc)
        links[ObjectIdentifier(ed)] = Link(session: s, folder: folder)
    }

    @MainActor public static func sync(_ ed: Editor) throws -> CoEditSession.SyncResult? {
        guard let l = links[ObjectIdentifier(ed)] else { return nil }
        let r = try l.session.sync(ed.doc, folder: l.folder)
        if r.document != ed.doc { ed.doc = r.document }
        return r
    }

    @MainActor public static func leave(_ ed: Editor) { links.removeValue(forKey: ObjectIdentifier(ed)) }

    static var command: CommandDef {
        CommandDef("COEDIT", aliases: ["COLLABORATE", "LIVESHARE", "COEDITSYNC"], category: "Collaborate",
                   summary: "Co-editing through a shared folder: Join (folder, your name), Sync (send your edits, receive the others'; also after each command with AUTOSYNC), Status, Leave. Edits of different objects merge; concurrent edits of one object keep the latest and are reported.") { ed in
            let k = try await ed.getKeyword("Option [Join/Sync/Status/Leave]", ["Join", "Sync", "Status", "Leave"], defaultValue: session(of: ed) == nil ? "Join" : "Sync") ?? "Sync"
            switch k {
            case "Join":
                let folder = try await IOCommands.path(ed, "Shared folder")
                let def = ed.doc.info.author.isEmpty ? (ProcessInfo.processInfo.environment["USER"] ?? "user") : ed.doc.info.author
                let site = try await ed.getWord("Your name <\(def)>") ?? def
                join(ed, folder: folder, site: site.isEmpty ? def : site)
                let r = try sync(ed)
                ed.print("Joined \(folder.path) as \(site.isEmpty ? def : site); received \(r?.received ?? 0) change(s).")
            case "Sync":
                guard let r = try sync(ed) else { throw CommandError.invalid("Not co-editing: COEDIT Join first.") }
                ed.print("Sent \(r.sent), received \(r.received) change(s).")
                if !r.conflicts.isEmpty { ed.print("Concurrent edits (latest kept): " + r.conflicts.joined(separator: ", ")) }
            case "Status":
                guard let s = session(of: ed), let l = links[ObjectIdentifier(ed)] else { ed.print("Not co-editing."); return }
                ed.print("Co-editing \(l.folder.path) as \(s.site) (clock \(s.clock), ids from \(s.idBase)); \(s.conflicts.count) conflict(s) so far.")
            default:
                leave(ed); ed.print("Left the co-editing session.")
            }
        }
    }
}
