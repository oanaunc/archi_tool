// Oanarina Archi Tool — GPL-3.0-or-later
// Crash recovery and file versions for archi-engine: the portable twins of ArchiApp/Autosave.swift (AutosaveSession,
// AutosaveManager, DRAWINGRECOVERY and the start screen's "Recovered documents") and ArchiApp/AppRound11Support.swift
// (FileVersions, VersionsBrowser, FILEVERSIONS). The Mac keeps versions in the macOS document-versions store; Windows has
// none, so every save of an .archi file copies it into a versions folder of its own (one folder per drawing, newest
// kept, up to the Keep count), with the same Browse / List / Restore / Open / Save / Keep operations.
//
// Recovery files are "<id>.archi" + "<id>.json" ({id, name, originalPath, date, pid, heartbeat}) in the recovery folder the
// shell passes with `recovery.setup`. The shell calls `recovery.autosave` every 30 s: it refreshes the heartbeat and writes
// the drawing when it has unsaved changes and the autosave interval has passed. Files whose heartbeat is older than
// `staleSeconds` belong to a window that ended abnormally and are offered on the start screen.
import Foundation

struct EngineRecoveryInfo: Codable, Hashable {
    var id: String
    var name: String
    var originalPath: String?
    var date: Date
    var pid: Int32
    var heartbeat: Date?
}

struct EngineVersion: Codable, Hashable {
    var file: String
    var date: Date
    var computer: String?
}

@MainActor
final class EngineRecoveryState {
    var folder: URL?
    var versionsFolder: URL?
    var keep = 50
    var versionsOnSave = true
    /// FILEPREVIEW Icons: embed the Explorer thumbnail picture in every saved .archi file (Mac: Finder preview icons).
    var previewOnSave = true
    let id = UUID().uuidString
    var lastSavedChange = -1
    var recoveredOriginalPath: String?
    weak var owner: Editor?
    static var sessions: [ObjectIdentifier: EngineRecoveryState] = [:]
    static func of(_ ed: Editor) -> EngineRecoveryState {
        let k = ObjectIdentifier(ed)
        if let s = sessions[k], s.owner === ed { return s }
        sessions = sessions.filter { $0.value.owner != nil }
        let s = EngineRecoveryState()
        s.owner = ed
        sessions[k] = s
        return s
    }
}

enum EngineRecovery {
    /// A recovery file whose heartbeat is older than this belongs to a window that is no longer running.
    static var staleSeconds: TimeInterval = 75

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    static func dateText(_ d: Date, date: DateFormatter.Style, time: DateFormatter.Style) -> String {
        let f = DateFormatter()
        f.dateStyle = date
        f.timeStyle = time
        return f.string(from: d)
    }

    // MARK: Recovery files (AutosaveManager)

    static func dataURL(_ folder: URL, _ id: String) -> URL { folder.appendingPathComponent(id + ".archi") }
    static func infoURL(_ folder: URL, _ id: String) -> URL { folder.appendingPathComponent(id + ".json") }

    static func readInfo(_ u: URL) -> EngineRecoveryInfo? {
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? decoder().decode(EngineRecoveryInfo.self, from: data)
    }

    /// Recovery files left by windows that ended abnormally (not `excluding`, heartbeat older than staleSeconds), newest first.
    static func recoverable(_ folder: URL, excluding own: String?, now: Date = Date()) -> [EngineRecoveryInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var out: [EngineRecoveryInfo] = []
        for u in files where u.pathExtension.lowercased() == "json" {
            guard let info = readInfo(u), info.id != own else { continue }
            guard fm.fileExists(atPath: dataURL(folder, info.id).path) else { continue }
            let beat = info.heartbeat ?? info.date
            if now.timeIntervalSince(beat) < staleSeconds { continue }
            out.append(info)
        }
        return out.sorted { $0.date > $1.date }
    }

    static func remove(_ folder: URL, _ id: String) {
        try? FileManager.default.removeItem(at: dataURL(folder, id))
        try? FileManager.default.removeItem(at: infoURL(folder, id))
    }

    // MARK: Versions (FileVersions)

    /// FNV-1a of the file's path: one versions folder per drawing.
    static func pathHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
    static func versionsDir(_ root: URL, for file: URL) -> URL {
        let name = file.deletingPathExtension().lastPathComponent
        let safe = String(name.map { "\\/:*?\"<>|".contains($0) ? "-" : $0 })
        let key = file.standardizedFileURL.path.lowercased()
        return root.appendingPathComponent(safe + " " + pathHash(key), isDirectory: true)
    }
    static func index(_ dir: URL) -> [EngineVersion] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("versions.json")),
              let list = try? decoder().decode([EngineVersion].self, from: data) else { return [] }
        return list
    }
    static func writeIndex(_ dir: URL, _ list: [EngineVersion]) {
        guard let data = try? encoder().encode(list) else { return }
        try? data.write(to: dir.appendingPathComponent("versions.json"), options: .atomic)
    }
    /// Saved versions of a file, newest first.
    static func list(_ root: URL, _ file: URL) -> [EngineVersion] {
        let dir = versionsDir(root, for: file)
        let fm = FileManager.default
        return index(dir).filter { fm.fileExists(atPath: dir.appendingPathComponent($0.file).path) }.sorted { $0.date > $1.date }
    }
    /// Indices (newest-first order) of versions to discard to keep at most `keep`.
    static func pruneIndices(count: Int, keep: Int) -> [Int] { count > keep ? Array(max(0, keep)..<count) : [] }

    static func computerName() -> String {
        let env = ProcessInfo.processInfo.environment
        return env["COMPUTERNAME"] ?? env["HOSTNAME"] ?? ProcessInfo.processInfo.hostName
    }

    /// Adds a version with the file's current contents; false when the file or the store is not available.
    @discardableResult
    static func add(_ root: URL, _ file: URL, keep: Int, date: Date = Date()) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return false }
        let dir = versionsDir(root, for: file)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var name = f.string(from: date) + "." + file.pathExtension
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = f.string(from: date) + " (" + String(n) + ")." + file.pathExtension
            n += 1
        }
        do { try fm.copyItem(at: file, to: dir.appendingPathComponent(name)) } catch { return false }
        var all = index(dir).filter { fm.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        all.append(EngineVersion(file: name, date: date, computer: computerName()))
        all.sort { $0.date > $1.date }
        for i in pruneIndices(count: all.count, keep: max(1, keep)).reversed() {
            try? fm.removeItem(at: dir.appendingPathComponent(all[i].file))
            all.remove(at: i)
        }
        writeIndex(dir, all)
        return true
    }

    static func label(_ v: EngineVersion) -> String {
        dateText(v.date, date: .medium, time: .medium) + (v.computer.map { " — " + $0 } ?? "")
    }

    /// A copy of a version in the temporary folder (opened in its own window, never overwriting the store).
    static func copy(_ root: URL, _ v: EngineVersion, of file: URL) throws -> URL {
        let fm = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = fm.temporaryDirectory.appendingPathComponent("ArchiVersions", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent(file.deletingPathExtension().lastPathComponent + " (" + f.string(from: v.date) + ")." + file.pathExtension)
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.copyItem(at: versionsDir(root, for: file).appendingPathComponent(v.file), to: dst)
        return dst
    }

    /// Replaces the file with a version (the current file is kept as a version first).
    static func restore(_ root: URL, _ v: EngineVersion, file: URL, keep: Int) throws {
        let src = versionsDir(root, for: file).appendingPathComponent(v.file)
        let data = try Data(contentsOf: src)
        add(root, file, keep: keep)
        try data.write(to: file, options: .atomic)
    }

    // MARK: Commands

    static var commands: [CommandDef] { [drawingRecovery, fileVersions, filePreview] }

    @MainActor static func isEmptyDocument(_ d: ArchiDocument) -> Bool { d.entities.isEmpty && d.elements.isEmpty && d.layouts.allSatisfy { $0.viewports.isEmpty && $0.entities.isEmpty } }

    static var drawingRecovery: CommandDef {
        CommandDef("DRAWINGRECOVERY", aliases: ["DRM"], category: "File", summary: "Shows documents recovered from autosave after a crash.", modifies: false) { ed in
            let s = try EngineToolCommands.session(ed)
            let st = EngineRecoveryState.of(ed)
            let list = st.folder.map { recoverable($0, excluding: st.id) } ?? []
            if list.isEmpty { ed.print("No recovered documents."); return }
            for (i, r) in list.enumerated() { ed.print("  \(i + 1). \(r.name) — \(dateText(r.date, date: .short, time: .short))") }
            if isEmptyDocument(ed.doc) && !ed.isDirty,
               let n = try await ed.getInteger("Enter number to restore in this window or Enter to show the list", defaultValue: 0), n > 0, n <= list.count {
                try s.restoreRecovery(list[n - 1])
                try EngineToolCommands.host(ed, "recovered", [("name", .string(list[n - 1].name))])
            } else {
                try EngineToolCommands.host(ed, "startScreen")
            }
        }
    }

    @MainActor static func savedURL(_ ed: Editor) throws -> URL {
        guard let u = ed.fileURL, u.pathExtension.lowercased() == ArchiFile.fileExtension, FileManager.default.fileExists(atPath: u.path) else {
            throw CommandError.invalid("Save the drawing as an .archi file first.")
        }
        return u
    }

    @MainActor static func versionsRoot(_ ed: Editor) throws -> URL {
        guard let r = EngineRecoveryState.of(ed).versionsFolder else { throw CommandError.invalid("Versions are not available on this volume.") }
        return r
    }

    static var fileVersions: CommandDef {
        CommandDef("FILEVERSIONS", aliases: ["BROWSEVERSIONS", "MACVERSIONS", "REVERTTO"], category: "File", summary: "Versions of the saved file (every save keeps one): Browse window, List, Restore a version, Open a copy, Save a version now, Keep count.", modifies: false) { ed in
            let url = try savedURL(ed)
            let st = EngineRecoveryState.of(ed)
            let k = try await ed.getKeyword("Versions [Browse/List/Restore/Open/Save/Keep]", ["Browse", "List", "Restore", "Open", "Save", "Keep"], defaultValue: "Browse") ?? "Browse"
            let vs = st.versionsFolder.map { list($0, url) } ?? []
            switch k {
            case "List":
                if vs.isEmpty { ed.print("No saved versions of \(url.lastPathComponent)."); return }
                for (i, v) in vs.enumerated() { ed.print("  \(i + 1). \(label(v))") }
            case "Restore", "Open":
                guard !vs.isEmpty else { throw CommandError.invalid("No saved versions of \(url.lastPathComponent).") }
                guard let n = try await ed.getInteger("Version number (1 = newest) <1>", defaultValue: 1), vs.indices.contains(n - 1) else { throw CommandError.invalid("Enter 1–\(vs.count).") }
                let root = try versionsRoot(ed)
                if k == "Open" {
                    let u = try copy(root, vs[n - 1], of: url)
                    try EngineToolCommands.host(ed, "openWindow", [("path", .string(u.path))])
                    ed.print("Opened a copy of the version of \(label(vs[n - 1])).")
                } else {
                    try EngineToolCommands.session(ed).restoreVersion(vs[n - 1], url: url)
                    ed.print("Restored the version of \(label(vs[n - 1])); the previous file is kept as a version.")
                }
            case "Save":
                let ok = st.versionsFolder.map { add($0, url, keep: st.keep) } ?? false
                ed.print(ok ? "Version of \(url.lastPathComponent) saved (\(list(st.versionsFolder!, url).count) in all)." : "Versions are not available on this volume.")
            case "Keep":
                guard let n = try await ed.getInteger("Versions to keep per file <\(st.keep)>", defaultValue: st.keep), (1...1000).contains(n) else { throw CommandError.invalid("Enter 1–1000.") }
                st.keep = n
                try EngineToolCommands.host(ed, "preference", [("key", .string("fileVersionsKeep")), ("value", .int(n))])
                ed.print("Keeping up to \(n) versions per file.")
            default:
                try EngineToolCommands.dialog(ed, "versions", [("path", .string(url.path))])
            }
        }
    }
}

// MARK: Explorer thumbnail and file metadata (FILEPREVIEW, IO-006 / IO-007)

extension EngineRecovery {
    /// Side of the preview picture embedded in saved .archi files (the Mac's Finder preview icon is 512 px too).
    static let previewSize = 512

    /// The picture embedded on save: the current level of the drawing, nil when nothing is drawn.
    static func previewImage(_ doc: ArchiDocument) -> ArchiFile.PreviewImage? {
        guard let img = PlanImageExport.thumbnail(doc: doc, level: doc.currentLevel, size: previewSize) else { return nil }
        return ArchiFile.PreviewImage(png: img.pngData(alpha: false), width: img.width, height: img.height)
    }

    /// Mac FILEPREVIEW (ArchiApp/AppCommandsRound11.swift) with Windows words: Update writes the Explorer thumbnail picture
    /// into the saved file (the Mac sets the Finder icon and the Spotlight attributes), Icons / Versions switch the
    /// picture and the version on every save, Show prints the file's metadata.
    static var filePreview: CommandDef {
        CommandDef("FILEPREVIEW", aliases: ["FINDERPREVIEW", "SPOTLIGHTINFO", "FILEMETADATA"], category: "File", summary: "Finder preview icon and Spotlight metadata of the saved drawing: Update now, Icons on/off, Versions on/off, Show the indexed metadata.", modifies: false) { ed in
            let st = EngineRecoveryState.of(ed)
            let k = try await ed.getKeyword("File preview [Update/Icons/Versions/Show]", ["Update", "Icons", "Versions", "Show"], defaultValue: "Update") ?? "Update"
            switch k {
            case "Icons":
                let on = (try await ed.getKeyword("Explorer thumbnails on save [On/Off] <\(st.previewOnSave ? "On" : "Off")>", ["On", "Off"], defaultValue: st.previewOnSave ? "On" : "Off") ?? "On") == "On"
                st.previewOnSave = on
                try EngineToolCommands.host(ed, "preference", [("key", .string("finderPreviewIcons")), ("value", .bool(on))])
                ed.print("Explorer thumbnails \(on ? "on" : "off").")
            case "Versions":
                let on = (try await ed.getKeyword("Keep a version on every save [On/Off] <\(st.versionsOnSave ? "On" : "Off")>", ["On", "Off"], defaultValue: st.versionsOnSave ? "On" : "Off") ?? "On") == "On"
                st.versionsOnSave = on
                try EngineToolCommands.host(ed, "preference", [("key", .string("fileVersionsOnSave")), ("value", .bool(on))])
                ed.print("Versions on save \(on ? "on" : "off").")
            case "Show":
                let url = try savedURL(ed)
                let a: [String: Any]
                do { a = try SpotlightMetadata.attributes(of: url) } catch { throw CommandError.invalid(EngineSession.describe(error)) }
                for key in ["kMDItemTitle", "kMDItemKeywords", "kMDItemAuthors", "org.oanarina.archi.levels", "org.oanarina.archi.rooms", "org.oanarina.archi.entityCount", "org.oanarina.archi.elementCount"] {
                    if let v = a[key] { ed.print("  \(key): \((v as? [Any]).map { $0.map { "\($0)" }.joined(separator: ", ") } ?? "\(v)")") }
                }
                let p = (try? Data(contentsOf: url)).flatMap { ArchiFile.preview(in: $0) }
                ed.print("  Explorer thumbnail: " + (p.map { "\($0.width)×\($0.height) picture in the file" } ?? "none (FILEPREVIEW Update writes one)"))
            default:
                let url = try savedURL(ed)
                let doc: ArchiDocument
                do { doc = try ArchiFile.decode(Data(contentsOf: url)) } catch { throw CommandError.invalid(EngineSession.describe(error)) }
                let preview = previewImage(doc)
                do { try ArchiFile.encode(doc, preview: preview).write(to: url, options: .atomic) } catch { throw CommandError.invalid(EngineSession.describe(error)) }
                ed.print(preview != nil ? "Explorer thumbnail of \(url.lastPathComponent) updated." : "Nothing is drawn on the current level: \(url.lastPathComponent) has no Explorer thumbnail.")
            }
        }
    }
}

extension EngineSession {
    var recoveryState: EngineRecoveryState { EngineRecoveryState.of(editor) }

    func callRecovery(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "recovery.setup": return recoverySetup(p)
        case "recovery.autosave": return try recoveryAutosave(p)
        case "recovery.discard": discardRecovery(); return .object([])
        case "recovery.list": return recoveryList()
        case "recovery.restore": return try await recoveryRestoreJSON(p)
        case "recovery.remove": return try recoveryRemove(p)
        case "versions.list": return try versionsList()
        case "versions.save": return try versionsSave()
        case "versions.open": return try versionsOpen(p)
        case "versions.restore": return try await versionsRestore(p)
        default: return nil
        }
    }

    // MARK: Recovery

    /// `recovery.setup {folder, versionsFolder?, keep?, versionsOnSave?, previewOnSave?}` → `{id, folder, versionsFolder, keep}`.
    func recoverySetup(_ p: EngineJSON) -> EngineJSON {
        let st = recoveryState
        if let f = p["folder"]?.stringValue, !f.isEmpty { st.folder = url(f) }
        if let f = p["versionsFolder"]?.stringValue, !f.isEmpty { st.versionsFolder = url(f) }
        if let k = p["keep"]?.intValue { st.keep = max(1, min(1000, k)) }
        if let b = p["versionsOnSave"]?.boolValue { st.versionsOnSave = b }
        if let b = p["previewOnSave"]?.boolValue { st.previewOnSave = b }
        var o = EngineObject()
        o.set("id", st.id)
        o.set("folder", EngineJSON.optString(st.folder?.path))
        o.set("versionsFolder", EngineJSON.optString(st.versionsFolder?.path))
        o.set("keep", st.keep)
        return o.json
    }

    /// `recovery.autosave {write?=true, force?}` → `{written, path?}`: refreshes the heartbeat of this window's recovery files and writes
    /// the drawing when it has unsaved changes since the last autosave (AutosaveSession.saveNow).
    func recoveryAutosave(_ p: EngineJSON) throws -> EngineJSON {
        let st = recoveryState
        var o = EngineObject()
        guard let folder = st.folder else { o.set("written", false); return o.json }
        let fm = FileManager.default
        let data = EngineRecovery.dataURL(folder, st.id), infoURL = EngineRecovery.infoURL(folder, st.id)
        let now = Date()
        // `write: false` only refreshes the heartbeat (the shell's autosave interval has not passed yet).
        let wanted = p["force"]?.boolValue == true || (p["write"]?.boolValue != false && editor.isDirty && editor.changeCount != st.lastSavedChange)
        let meaningful = !EngineRecovery.isEmptyDocument(editor.doc) || editor.fileURL != nil
        if wanted && meaningful && editor.isDirty {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try ArchiFile.encode(editor.doc).write(to: data, options: .atomic)
                let name = editor.fileURL.map { $0.deletingPathExtension().lastPathComponent } ?? "Untitled"
                let info = EngineRecoveryInfo(id: st.id, name: name, originalPath: editor.fileURL?.path ?? st.recoveredOriginalPath, date: now,
                                              pid: ProcessInfo.processInfo.processIdentifier, heartbeat: now)
                try EngineRecovery.encoder().encode(info).write(to: infoURL, options: .atomic)
                st.lastSavedChange = editor.changeCount
                o.set("written", true)
                o.set("path", data.path)
                return o.json
            } catch {
                editor.print("Autosave failed: " + EngineSession.describe(error))
                o.set("written", false)
                return o.json
            }
        }
        if var info = EngineRecovery.readInfo(infoURL) {
            info.heartbeat = now
            if let d = try? EngineRecovery.encoder().encode(info) { try? d.write(to: infoURL, options: .atomic) }
        }
        o.set("written", false)
        return o.json
    }

    /// The document was saved or closed normally: its recovery copy is no longer needed.
    func discardRecovery() {
        let st = recoveryState
        if let f = st.folder { EngineRecovery.remove(f, st.id) }
        st.lastSavedChange = -1
    }

    func recoveryList() -> EngineJSON {
        let st = recoveryState
        let list = st.folder.map { EngineRecovery.recoverable($0, excluding: st.id) } ?? []
        var items: [EngineJSON] = []
        for r in list {
            var o = EngineObject()
            o.set("id", r.id)
            o.set("name", r.name)
            o.set("originalPath", EngineJSON.optString(r.originalPath))
            o.set("date", ISO8601DateFormatter().string(from: r.date))
            o.set("dateText", EngineRecovery.dateText(r.date, date: .medium, time: .short))
            items.append(o.json)
        }
        var o = EngineObject()
        o.set("items", EngineJSON.array(items))
        o.set("folder", EngineJSON.optString(st.folder?.path))
        return o.json
    }

    func recoveryInfo(_ p: EngineJSON) throws -> (URL, EngineRecoveryInfo) {
        guard let folder = recoveryState.folder else { throw EngineError.failed("No recovery folder (recovery.setup).") }
        let id = try string(p, "id")
        guard let info = EngineRecovery.readInfo(EngineRecovery.infoURL(folder, id)) else { throw EngineError.params("no recovered document '\(id)'") }
        return (folder, info)
    }

    /// Restores a recovery file into this window (unsaved, marked modified) and deletes the recovery copy.
    func restoreRecovery(_ info: EngineRecoveryInfo) throws {
        guard let folder = recoveryState.folder else { throw EngineError.failed("No recovery folder (recovery.setup).") }
        let d: ArchiDocument
        do { d = try ArchiFile.decode(try Data(contentsOf: EngineRecovery.dataURL(folder, info.id))) }
        catch { throw EngineError.failed("Cannot read the recovered document: " + EngineSession.describe(error)) }
        editor.replaceDocument(d, url: nil)
        drawCache = nil
        recoveryState.recoveredOriginalPath = info.originalPath
        editor.isDirty = true
        EngineRecovery.remove(folder, info.id)
        editor.print("Recovered “\(info.name)” from the autosave of \(EngineRecovery.dateText(info.date, date: .medium, time: .short)). Save it to keep the changes.")
        markChanged("document")
    }

    func recoveryRestoreJSON(_ p: EngineJSON) async throws -> EngineJSON {
        let (_, info) = try recoveryInfo(p)
        await cancelAndWait()
        try restoreRecovery(info)
        var o = EngineObject()
        o.set("doc", docInfo())
        o.set("originalPath", EngineJSON.optString(info.originalPath))
        return o.json
    }

    func recoveryRemove(_ p: EngineJSON) throws -> EngineJSON {
        let (folder, info) = try recoveryInfo(p)
        EngineRecovery.remove(folder, info.id)
        return recoveryList()
    }

    /// After every save of an .archi file: a version of the saved file and no more recovery copy (SaveExtras.afterSave).
    func afterNativeSave(_ u: URL) {
        let st = recoveryState
        discardRecovery()
        if st.versionsOnSave, let root = st.versionsFolder, u.pathExtension.lowercased() == ArchiFile.fileExtension { EngineRecovery.add(root, u, keep: st.keep) }
    }

    // MARK: Versions

    func versionsFile() throws -> (URL, URL) {
        guard let u = editor.fileURL, u.pathExtension.lowercased() == ArchiFile.fileExtension, FileManager.default.fileExists(atPath: u.path) else {
            throw EngineError.failed("Save the drawing as an .archi file first.")
        }
        guard let root = recoveryState.versionsFolder else { throw EngineError.failed("Versions are not available on this volume.") }
        return (root, u)
    }

    /// `versions.list {}` → `{path, name, keep, versions:[{index, label, date}]}` (newest first).
    func versionsList() throws -> EngineJSON {
        let (root, u) = try versionsFile()
        var items: [EngineJSON] = []
        for (i, v) in EngineRecovery.list(root, u).enumerated() {
            var o = EngineObject()
            o.set("index", i)
            o.set("label", EngineRecovery.label(v))
            o.set("date", ISO8601DateFormatter().string(from: v.date))
            items.append(o.json)
        }
        var o = EngineObject()
        o.set("path", u.path)
        o.set("name", u.lastPathComponent)
        o.set("keep", recoveryState.keep)
        o.set("versions", EngineJSON.array(items))
        return o.json
    }

    func versionsSave() throws -> EngineJSON {
        let (root, u) = try versionsFile()
        let ok = EngineRecovery.add(root, u, keep: recoveryState.keep)
        var o = EngineObject()
        o.set("ok", ok)
        o.set("message", ok ? "Version saved." : "Versions are not available on this volume.")
        o.set("count", EngineRecovery.list(root, u).count)
        return o.json
    }

    func version(_ p: EngineJSON) throws -> (URL, URL, EngineVersion) {
        let (root, u) = try versionsFile()
        let vs = EngineRecovery.list(root, u)
        guard let i = p["index"]?.intValue, vs.indices.contains(i) else { throw EngineError.params("no version \(p["index"]?.intValue ?? -1)") }
        return (root, u, vs[i])
    }

    /// `versions.open {index}` → `{path}`: a copy of the version in the temporary folder (the shell opens it in a new window).
    func versionsOpen(_ p: EngineJSON) throws -> EngineJSON {
        let (root, u, v) = try version(p)
        let c: URL
        do { c = try EngineRecovery.copy(root, v, of: u) } catch { throw EngineError.failed(EngineSession.describe(error)) }
        var o = EngineObject()
        o.set("path", c.path)
        o.set("label", EngineRecovery.label(v))
        return o.json
    }

    /// Replaces the saved file with a version (kept as a version first) and reloads the window.
    func restoreVersion(_ v: EngineVersion, url u: URL) throws {
        let st = recoveryState
        guard let root = st.versionsFolder else { throw EngineError.failed("Versions are not available on this volume.") }
        do { try EngineRecovery.restore(root, v, file: u, keep: st.keep) } catch { throw EngineError.failed(EngineSession.describe(error)) }
        try open(u)
        markChanged("document")
    }

    func versionsRestore(_ p: EngineJSON) async throws -> EngineJSON {
        let (_, u, v) = try version(p)
        await cancelAndWait()
        try restoreVersion(v, url: u)
        editor.print("Restored the version of \(EngineRecovery.label(v)); the previous file is kept as a version.")
        return docInfo()
    }
}
