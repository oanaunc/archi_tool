// Oanarina Archi Tool — GPL-3.0-or-later
// Document safety and history on disk: version history (named snapshots saved next to the drawing, restore, diff),
// backup copies on save (.bak), an append-only change journal for crash recovery (periodic autosave of deltas),
// repair of damaged .archi files (RECOVER) and the compressed package format (.archiz).
import Foundation

// MARK: - Version history

public struct DocumentVersion: Codable, Hashable {
    public var number: Int
    public var date: Date
    public var message: String
    public var author: String
    /// Snapshot file name inside the versions folder.
    public var file: String
    public var entities: Int
    public var elements: Int
    /// SHA-like fingerprint of the snapshot (FNV-1a 64 of the encoded document) to skip identical saves.
    public var fingerprint: String
}

/// Snapshots live in "<drawing>.archi-versions/" next to the drawing: vNNNN.archi files plus versions.json.
public enum DocumentVersions {
    public static func folder(for documentURL: URL) -> URL {
        documentURL.deletingLastPathComponent().appendingPathComponent(documentURL.lastPathComponent + "-versions", isDirectory: true)
    }
    static func manifestURL(_ documentURL: URL) -> URL { folder(for: documentURL).appendingPathComponent("versions.json") }

    static func fingerprint(_ data: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in data { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    public static func list(for documentURL: URL) -> [DocumentVersion] {
        guard let d = try? Data(contentsOf: manifestURL(documentURL)) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return ((try? dec.decode([DocumentVersion].self, from: d)) ?? []).sorted { $0.number < $1.number }
    }

    static func writeManifest(_ v: [DocumentVersion], _ documentURL: URL) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(v.sorted { $0.number < $1.number }).write(to: manifestURL(documentURL), options: .atomic)
    }

    /// Saves a named checkpoint. Returns nil (nothing written) when the document equals the latest snapshot.
    @discardableResult
    public static func save(_ doc: ArchiDocument, documentURL: URL, message: String, author: String? = nil, date: Date = Date(), force: Bool = false) throws -> DocumentVersion? {
        let dir = folder(for: documentURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try ArchiFile.encode(doc)
        let fp = fingerprint(data)
        var all = list(for: documentURL)
        if !force, let last = all.last, last.fingerprint == fp { return nil }
        let n = (all.map(\.number).max() ?? 0) + 1
        let file = String(format: "v%04d.archi", n)
        try data.write(to: dir.appendingPathComponent(file), options: .atomic)
        let v = DocumentVersion(number: n, date: date, message: message.isEmpty ? "Checkpoint \(n)" : message, author: author ?? Markups.author(doc),
                                file: file, entities: doc.entities.count, elements: doc.elements.count, fingerprint: fp)
        all.append(v)
        try writeManifest(all, documentURL)
        return v
    }

    public static func load(_ number: Int, documentURL: URL) throws -> ArchiDocument {
        guard let v = list(for: documentURL).first(where: { $0.number == number }) else { throw DocumentIO.IOError(message: "no version \(number)") }
        return try ArchiFile.decode(Data(contentsOf: folder(for: documentURL).appendingPathComponent(v.file)))
    }

    /// Differences between two versions (or a version and `current` when `to` is nil).
    public static func diff(from: Int, to: Int?, documentURL: URL, current: ArchiDocument? = nil) throws -> DocumentDiff {
        let a = try load(from, documentURL: documentURL)
        let b: ArchiDocument
        if let t = to { b = try load(t, documentURL: documentURL) } else if let c = current { b = c } else { throw DocumentIO.IOError(message: "nothing to compare with") }
        return DocumentCompare.compare(a, b, matchGeometry: false)
    }

    public static func delete(_ number: Int, documentURL: URL) throws {
        var all = list(for: documentURL)
        guard let i = all.firstIndex(where: { $0.number == number }) else { throw DocumentIO.IOError(message: "no version \(number)") }
        try? FileManager.default.removeItem(at: folder(for: documentURL).appendingPathComponent(all[i].file))
        all.remove(at: i)
        try writeManifest(all, documentURL)
    }

    /// Keeps the newest `keep` versions.
    public static func prune(keep: Int, documentURL: URL) throws {
        let all = list(for: documentURL)
        guard all.count > keep else { return }
        for v in all.prefix(all.count - max(keep, 0)) { try delete(v.number, documentURL: documentURL) }
    }
}

// MARK: - Backups and recovery of damaged files

public struct RecoveryReport {
    public var messages: [String] = []
    public var droppedEntities = 0
    public var droppedElements = 0
    public var droppedBlocks = 0
    public var droppedKeys: [String] = []
    public var truncatedRepaired = false
    public var fixes = 0
    public var isClean: Bool { messages.isEmpty }
    public var text: String { messages.isEmpty ? "No errors found." : messages.joined(separator: "\n") }
}

public extension ArchiFile {
    /// Backup name for a drawing: "<name>.bak" (AutoCAD style).
    static func backupURL(for url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("bak") }

    /// Writes the drawing; the previous file is kept as <name>.bak when `backup` (system variable ISAVEBAK ≠ 0).
    static func save(_ doc: ArchiDocument, to url: URL, backup: Bool = true, preview: PreviewImage? = nil) throws {
        let data = try encode(doc, preview: preview)
        let fm = FileManager.default
        if backup, fm.fileExists(atPath: url.path) {
            let bak = backupURL(for: url)
            try? fm.removeItem(at: bak)
            try fm.copyItem(at: url, to: bak)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Repairs a damaged drawing: truncated JSON is closed at the last complete value, objects that no longer decode are
    /// dropped one by one (entities, elements, blocks, then whole settings), and the model is audited (dangling hosted
    /// openings, missing layers, IDs). Throws only when nothing usable is left.
    static func recover(_ data: Data) throws -> (ArchiDocument, RecoveryReport) {
        var rep = RecoveryReport()
        if let d = try? decode(data) {
            var doc = d
            audit(&doc, &rep)
            return (doc, rep)
        }
        var raw: Any? = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if raw == nil, let fixed = repairTruncatedJSON(data) {
            raw = try? JSONSerialization.jsonObject(with: fixed, options: [])
            if raw != nil { rep.truncatedRepaired = true; rep.messages.append("The file was truncated; it was closed after the last complete object.") }
        }
        guard let root = raw as? [String: Any] else { throw FileError.corrupt("not readable as JSON") }
        let docObj: [String: Any]
        if let inner = root["document"] as? [String: Any] { docObj = inner }
        else if root["layers"] != nil || root["entities"] != nil { docObj = root }
        else { throw FileError.notAnArchiFile }
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        func item<T: Decodable>(_ t: T.Type, _ obj: Any) -> T? {
            guard JSONSerialization.isValidJSONObject([obj]), let d = try? JSONSerialization.data(withJSONObject: [obj]) else { return nil }
            return (try? dec.decode([T].self, from: d))?.first
        }
        var entities: [Entity] = []
        for o in docObj["entities"] as? [Any] ?? [] { if let e = item(Entity.self, o) { entities.append(e) } else { rep.droppedEntities += 1 } }
        var elements: [BIMElement] = []
        for o in docObj["elements"] as? [Any] ?? [] { if let e = item(BIMElement.self, o) { elements.append(e) } else { rep.droppedElements += 1 } }
        var blocks: [String: Block] = [:]
        for (k, o) in docObj["blocks"] as? [String: Any] ?? [:] { if let b = item(Block.self, o) { blocks[k] = b } else { rep.droppedBlocks += 1 } }
        // Settings: keep every top-level key that decodes on its own.
        var rest = docObj
        rest["entities"] = nil; rest["elements"] = nil; rest["blocks"] = nil
        var good: [String: Any] = [:]
        for (k, v) in rest {
            if item(ArchiDocument.self, [k: v]) != nil { good[k] = v } else { rep.droppedKeys.append(k) }
        }
        if let v = good["formatVersion"] as? Int, v > ArchiDocument.currentFormatVersion { throw FileError.newerVersion(found: v, supported: ArchiDocument.currentFormatVersion) }
        var doc = item(ArchiDocument.self, good) ?? ArchiDocument()
        doc.entities = entities; doc.elements = elements; doc.blocks = blocks
        doc.formatVersion = ArchiDocument.currentFormatVersion
        if rep.droppedEntities > 0 { rep.messages.append("\(rep.droppedEntities) damaged drawing objects removed.") }
        if rep.droppedElements > 0 { rep.messages.append("\(rep.droppedElements) damaged building elements removed.") }
        if rep.droppedBlocks > 0 { rep.messages.append("\(rep.droppedBlocks) damaged block definitions removed.") }
        if !rep.droppedKeys.isEmpty { rep.messages.append("Damaged settings reset to defaults: " + rep.droppedKeys.sorted().joined(separator: ", ") + ".") }
        audit(&doc, &rep)
        return (doc, rep)
    }

    /// AUDIT-style consistency fixes after recovery.
    static func audit(_ doc: inout ArchiDocument, _ rep: inout RecoveryReport) {
        let wallIDs = Set(doc.elements.compactMap { el -> EntityID? in if case .wall = el.geometry { return el.id }; return nil })
        let before = doc.elements.count
        doc.elements.removeAll { el in if case .opening(let o) = el.geometry { return !wallIDs.contains(o.hostWall) }; return false }
        if doc.elements.count < before { rep.fixes += before - doc.elements.count; rep.messages.append("\(before - doc.elements.count) doors/windows without a host wall removed.") }
        // Duplicate IDs get fresh ones.
        var seen = Set<EntityID>()
        var dup = 0
        let maxID = max(doc.entities.map(\.id).max() ?? 0, doc.elements.map(\.id).max() ?? 0)
        if doc.nextID <= maxID { doc.nextID = maxID + 1 }
        for i in doc.entities.indices { if !seen.insert(doc.entities[i].id).inserted { doc.entities[i].id = doc.allocateID(); dup += 1 } }
        for i in doc.elements.indices { if !seen.insert(doc.elements[i].id).inserted { doc.elements[i].id = doc.allocateID(); dup += 1 } }
        if dup > 0 { rep.fixes += dup; rep.messages.append("\(dup) duplicate object IDs renumbered.") }
        var missing = Set<String>()
        for e in doc.entities where doc.layer(named: e.layer) == nil { missing.insert(e.layer) }
        for e in doc.elements where doc.layer(named: e.layer) == nil { missing.insert(e.layer) }
        for l in missing.sorted() { doc.ensureLayer(l) }
        if !missing.isEmpty { rep.fixes += missing.count; rep.messages.append("Missing layers recreated: " + missing.sorted().joined(separator: ", ") + ".") }
        if doc.layer(named: "0") == nil { doc.layers.insert(Layer(name: "0"), at: 0); rep.fixes += 1; rep.messages.append("Layer 0 recreated.") }
        if doc.layer(named: doc.currentLayer) == nil { doc.currentLayer = "0" }
        if doc.levels.isEmpty { doc.levels = [Level(id: 0, name: "Ground Floor", elevation: 0)]; rep.fixes += 1; rep.messages.append("Levels recreated.") }
        if doc.level(doc.currentLevel) == nil { doc.currentLevel = doc.levels[0].id }
        if doc.layouts.isEmpty { doc.layouts = [Layout(name: "Sheet 1")] }
    }

    /// Closes a truncated JSON text after its last complete object or array (every open container is closed after it).
    /// Nil if no candidate parses.
    static func repairTruncatedJSON(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var stack: [UInt8] = []
        var inString = false, escape = false
        var cuts: [(Int, [UInt8])] = []
        for (i, b) in bytes.enumerated() {
            if inString {
                if escape { escape = false } else if b == 0x5C { escape = true } else if b == 0x22 { inString = false }
                continue
            }
            switch b {
            case 0x22: inString = true
            case 0x7B, 0x5B: stack.append(b)
            case 0x7D, 0x5D:
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
                if stack.isEmpty { return Data(bytes[0...i]) }
                cuts.append((i + 1, stack))
                if cuts.count > 4096 { cuts.removeFirst(2048) }
            default: break
            }
        }
        for (cut, open) in cuts.reversed().prefix(64) {
            var out = Array(bytes[0..<cut])
            for t in open.reversed() { out.append(t == 0x7B ? 0x7D : 0x5D) }
            let d = Data(out)
            if (try? JSONSerialization.jsonObject(with: d)) != nil { return d }
        }
        return nil
    }
}

// MARK: - Change journal (autosave of deltas for crash recovery)

/// One journal line: a base snapshot or a delta (upserted / removed entities and elements by id, new order when it
/// changed, and the remaining document settings when they changed).
struct JournalRecord: Codable {
    var t: String
    var date: Date
    var label: String?
    var doc: ArchiDocument?
    var meta: ArchiDocument?
    var upsertEntities: [Entity]?
    var removeEntities: [EntityID]?
    var entityOrder: [EntityID]?
    var upsertElements: [BIMElement]?
    var removeElements: [EntityID]?
    var elementOrder: [EntityID]?
}

/// Append-only change journal: a base snapshot followed by one JSON line per recorded change. Replaying the journal after
/// a forced quit restores the last recorded state; a partially written last line is ignored.
public final class DocumentJournal {
    public let url: URL
    private var last: ArchiDocument
    private var lastMeta: ArchiDocument
    public private(set) var recordCount = 0

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
    static func meta(_ d: ArchiDocument) -> ArchiDocument { var m = d; m.entities = []; m.elements = []; return m }

    /// Default folder for journals: ~/Library/Application Support/Oanarina Archi Tool/Recovery.
    public static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/Recovery", isDirectory: true)
    }

    /// Starts a journal at `url` (replacing an old one) with `base` as the first snapshot.
    public init(url: URL, base: ArchiDocument) throws {
        self.url = url; last = base; lastMeta = DocumentJournal.meta(base)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = try DocumentJournal.encoder().encode(JournalRecord(t: "base", date: Date(), label: nil, doc: base))
        try (line + Data([0x0A])).write(to: url, options: .atomic)
    }

    /// Records the change from the last recorded state to `doc`. Returns false when nothing changed.
    @discardableResult
    public func record(_ doc: ArchiDocument, label: String? = nil) throws -> Bool {
        guard doc != last else { return false }
        var r = JournalRecord(t: "delta", date: Date(), label: label)
        func delta<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> (upsert: [T], remove: [T.ID], order: [T.ID]?) where T.ID: Hashable {
            var o: [T.ID: T] = [:]
            for x in old { o[x.id] = x }
            let upsert = new.filter { o[$0.id] != $0 }
            let newIDs = Set(new.map(\.id))
            let remove = old.map(\.id).filter { !newIDs.contains($0) }
            // Order is written only when the surviving objects changed their relative order.
            let keptOld = old.map(\.id).filter { newIDs.contains($0) }
            let oldSet = Set(keptOld)
            let keptNew = new.map(\.id).filter { oldSet.contains($0) }
            return (upsert, remove, keptOld == keptNew ? nil : new.map(\.id))
        }
        let de = delta(last.entities, doc.entities)
        if !de.upsert.isEmpty { r.upsertEntities = de.upsert }
        if !de.remove.isEmpty { r.removeEntities = de.remove }
        r.entityOrder = de.order
        let dl = delta(last.elements, doc.elements)
        if !dl.upsert.isEmpty { r.upsertElements = dl.upsert }
        if !dl.remove.isEmpty { r.removeElements = dl.remove }
        r.elementOrder = dl.order
        let m = DocumentJournal.meta(doc)
        if m != lastMeta { r.meta = m; lastMeta = m }
        let line = try DocumentJournal.encoder().encode(r) + Data([0x0A])
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: line)
        last = doc
        recordCount += 1
        return true
    }

    /// Rewrites the journal as a single base snapshot of the last recorded state.
    public func compact() throws {
        let line = try DocumentJournal.encoder().encode(JournalRecord(t: "base", date: Date(), label: nil, doc: last))
        try (line + Data([0x0A])).write(to: url, options: .atomic)
        recordCount = 0
    }

    /// Removes the journal (the document was saved or closed normally).
    public func discard() { try? FileManager.default.removeItem(at: url) }

    /// Replays a journal. Returns the recovered document, the number of changes applied and whether a damaged tail was skipped.
    public static func recover(_ url: URL) throws -> (doc: ArchiDocument, applied: Int, damagedTail: Bool, date: Date?) {
        let data = try Data(contentsOf: url)
        let dec = decoder()
        var doc: ArchiDocument?
        var applied = 0, damaged = false
        var lastDate: Date?
        for chunk in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let r = try? dec.decode(JournalRecord.self, from: Data(chunk)) else { damaged = true; break }
            lastDate = r.date
            if r.t == "base", let b = r.doc { doc = b; applied = 0; continue }
            guard var d = doc else { continue }
            if let m = r.meta { let ents = d.entities, els = d.elements; d = m; d.entities = ents; d.elements = els }
            func apply<T: Identifiable>(_ list: inout [T], _ up: [T]?, _ rm: [T.ID]?, _ order: [T.ID]?) where T.ID: Hashable {
                if let rm = rm { let s = Set(rm); list.removeAll { s.contains($0.id) } }
                if let up = up {
                    var idx: [T.ID: Int] = [:]
                    for (i, x) in list.enumerated() { idx[x.id] = i }
                    for x in up { if let i = idx[x.id] { list[i] = x } else { idx[x.id] = list.count; list.append(x) } }
                }
                if let order = order {
                    var byID: [T.ID: T] = [:]
                    for x in list { byID[x.id] = x }
                    let ordered = order.compactMap { byID[$0] }
                    let inOrder = Set(order)
                    list = ordered + list.filter { !inOrder.contains($0.id) }
                }
            }
            apply(&d.entities, r.upsertEntities, r.removeEntities, r.entityOrder)
            apply(&d.elements, r.upsertElements, r.removeElements, r.elementOrder)
            let maxID = max(d.entities.map(\.id).max() ?? 0, d.elements.map(\.id).max() ?? 0)
            if d.nextID <= maxID { d.nextID = maxID + 1 }
            doc = d
            applied += 1
        }
        guard let out = doc else { throw DocumentIO.IOError(message: "the journal has no readable snapshot") }
        return (out, applied, damaged, lastDate)
    }
}

/// Periodic journal of an editor's document (autosave to the recovery folder). `tick()` records a delta when the document
/// changed; `start` schedules ticks every `interval` seconds on the main actor.
@MainActor
public final class AutosaveJournal {
    public static private(set) var active: [ObjectIdentifier: AutosaveJournal] = [:]
    public let journal: DocumentJournal
    public private(set) weak var editor: Editor?
    public var interval: TimeInterval
    private var task: Task<Void, Never>?

    public init(editor: Editor, url: URL? = nil, interval: TimeInterval = 60) throws {
        let name = (editor.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + "-" + String(UUID().uuidString.prefix(8)) + ".archijournal"
        journal = try DocumentJournal(url: url ?? DocumentJournal.defaultFolder.appendingPathComponent(name), base: editor.doc)
        self.editor = editor
        self.interval = interval
    }

    /// Journal of an editor, if one is running.
    public static func session(for editor: Editor) -> AutosaveJournal? { active[ObjectIdentifier(editor)] }

    public func start() {
        guard let ed = editor else { return }
        AutosaveJournal.active[ObjectIdentifier(ed)] = self
        task?.cancel()
        let ns = UInt64(max(interval, 1) * 1_000_000_000)
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard let s = self, !Task.isCancelled else { return }
                _ = s.tick()
            }
        }
    }

    /// Records the current document if it changed. Returns true when a change was written.
    @discardableResult
    public func tick() -> Bool {
        guard let ed = editor else { return false }
        return (try? journal.record(ed.doc)) ?? false
    }

    /// Stops journaling; `keep` leaves the journal on disk (else it is deleted, as after a normal save/close).
    public func stop(keep: Bool = false) {
        task?.cancel(); task = nil
        if let ed = editor { AutosaveJournal.active[ObjectIdentifier(ed)] = nil }
        if !keep { journal.discard() }
    }
}

// MARK: - Recovery files

public struct RecoveryFile: Hashable {
    public var url: URL
    public var kind: String   // "journal" or "autosave"
    public var date: Date
    public var name: String
}

public enum RecoveryFiles {
    /// App autosave folder (written by the app every few minutes).
    public static var autosaveFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/Autosave", isDirectory: true)
    }

    /// Journals (.archijournal) and autosave copies (.archi) in the given folders, newest first.
    public static func list(folders: [URL] = [DocumentJournal.defaultFolder, autosaveFolder]) -> [RecoveryFile] {
        var out: [RecoveryFile] = []
        let fm = FileManager.default
        for f in folders {
            for u in (try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let ext = u.pathExtension.lowercased()
                guard ext == "archijournal" || ext == "archi" else { continue }
                let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                var name = u.deletingPathExtension().lastPathComponent
                // App autosaves keep their display name in <id>.json.
                if ext == "archi", let d = try? Data(contentsOf: u.deletingPathExtension().appendingPathExtension("json")),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let n = o["name"] as? String { name = n }
                out.append(RecoveryFile(url: u, kind: ext == "archijournal" ? "journal" : "autosave", date: date, name: name))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Opens a recovery file (journal replay or autosave copy).
    public static func open(_ f: RecoveryFile) throws -> (ArchiDocument, String) {
        if f.kind == "journal" {
            let r = try DocumentJournal.recover(f.url)
            return (r.doc, "\(r.applied) recorded changes replayed" + (r.damagedTail ? " (an incomplete last change was skipped)" : ""))
        }
        let (d, rep) = try ArchiFile.recover(Data(contentsOf: f.url))
        return (d, rep.isClean ? "autosave copy" : "autosave copy repaired: " + rep.text)
    }
}

// MARK: - Compressed package (.archiz)

public enum ArchiPackage {
    public static let fileExtension = "archiz"

    /// Writes the drawing with its images, material textures and external references (paths rewritten) as a ZIP.
    public static func write(_ doc: ArchiDocument, to url: URL, documentURL: URL? = nil) throws -> TransmittalReport {
        let name = url.deletingPathExtension().lastPathComponent
        let (data, rep) = ETransmit.pack(doc, documentURL: documentURL ?? url, name: name.isEmpty ? "Drawing" : name)
        try data.write(to: url, options: .atomic)
        return rep
    }

    /// Unpacks a package (into `directory`, default a cache folder) and opens its drawing with every packaged path made
    /// absolute, so images, textures and references resolve wherever the package was opened.
    public static func read(_ url: URL, into directory: URL? = nil) throws -> ArchiDocument {
        let data = try Data(contentsOf: url)
        let dir: URL
        if let d = directory { dir = d } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            dir = caches.appendingPathComponent("Oanarina Archi Tool/Packages/" + url.deletingPathExtension().lastPathComponent + "-" + DocumentVersions.fingerprint(data), isDirectory: true)
        }
        let drawing = try ETransmit.unpack(data, to: dir)
        var d = try ArchiFile.decode(Data(contentsOf: drawing))
        let base = drawing.deletingLastPathComponent()
        func absolute(_ p: String) -> String { PathSupport.isAbsolute(p) || p.isEmpty ? p : base.appendingPathComponent(p).path }
        func fix(_ e: inout Entity) { if case .image(var im) = e.geometry { im.path = absolute(im.path); e.geometry = .image(im) } }
        for i in d.entities.indices { fix(&d.entities[i]) }
        for k in d.blocks.keys { for i in d.blocks[k]!.entities.indices { fix(&d.blocks[k]!.entities[i]) } }
        for l in d.layouts.indices { for i in d.layouts[l].entities.indices { fix(&d.layouts[l].entities[i]) } }
        for i in d.materials.indices { if let t = d.materials[i].texture { d.materials[i].texture = absolute(t) } }
        var xr = Xrefs.all(d)
        if !xr.isEmpty { for i in xr.indices { xr[i].path = absolute(xr[i].path) }; Xrefs.store(xr, &d) }
        return d
    }
}
