// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import AppKit
import ArchiCore

/// Metadata written next to each recovery file.
struct AutosaveInfo: Codable, Hashable {
    var id: String
    var name: String
    var originalPath: String?
    var date: Date
    var pid: Int32
}

/// One document's autosave state. The recovery file is removed when the document is saved or closed normally.
@MainActor
final class AutosaveSession {
    let id = UUID().uuidString
    private weak var model: AppModel?
    private var timer: Timer?
    private var lastSavedChange = -1

    init(model: AppModel) {
        self.model = model
        reschedule()
    }

    var dataURL: URL { AutosaveManager.folder.appendingPathComponent("\(id).archi") }
    var infoURL: URL { AutosaveManager.folder.appendingPathComponent("\(id).json") }

    func reschedule() {
        timer?.invalidate(); timer = nil
        let minutes = AppPreferences.shared.autosaveMinutes
        guard minutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.saveNow() }
        }
    }

    /// Writes the recovery copy when the document has unsaved changes. Returns true when a file was written.
    @discardableResult
    func saveNow() -> Bool {
        guard let m = model else { return false }
        guard m.isDirty, m.editor.changeCount != lastSavedChange, !m.isEmptyDocument || m.editor.fileURL != nil else { return false }
        do {
            try FileManager.default.createDirectory(at: AutosaveManager.folder, withIntermediateDirectories: true)
            try ArchiFile.encode(m.doc).write(to: dataURL, options: .atomic)
            let info = AutosaveInfo(id: id, name: m.displayName, originalPath: m.editor.fileURL?.path, date: Date(), pid: ProcessInfo.processInfo.processIdentifier)
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            try enc.encode(info).write(to: infoURL, options: .atomic)
            lastSavedChange = m.editor.changeCount
            return true
        } catch {
            m.editor.print("Autosave failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The document was saved or closed: the recovery copy is no longer needed.
    func discard() {
        try? FileManager.default.removeItem(at: dataURL)
        try? FileManager.default.removeItem(at: infoURL)
        lastSavedChange = -1
    }

    func stop() { timer?.invalidate(); timer = nil; discard() }
}

@MainActor
enum AutosaveManager {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/Autosave", isDirectory: true)
    }

    /// Recovery files left by a previous session that ended abnormally (another process, or this process's closed windows are already removed).
    static func recoverable() -> [AutosaveInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let me = ProcessInfo.processInfo.processIdentifier
        let live = Set(AppModel.all.compactMap { $0.autosave?.id })
        return files.filter { $0.pathExtension == "json" }.compactMap { u -> AutosaveInfo? in
            guard let data = try? Data(contentsOf: u), let info = try? dec.decode(AutosaveInfo.self, from: data) else { return nil }
            guard fm.fileExists(atPath: folder.appendingPathComponent("\(info.id).archi").path) else { return nil }
            if info.pid == me || live.contains(info.id) { return nil }
            // A still-running copy of the app owns its own files.
            if kill(info.pid, 0) == 0, NSRunningApplication(processIdentifier: info.pid)?.bundleIdentifier == Bundle.main.bundleIdentifier, info.pid != me { return nil }
            return info
        }
        .sorted { $0.date > $1.date }
    }

    static func load(_ info: AutosaveInfo) throws -> ArchiDocument {
        try ArchiFile.decode(try Data(contentsOf: folder.appendingPathComponent("\(info.id).archi")))
    }

    static func remove(_ info: AutosaveInfo) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(info.id).archi"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(info.id).json"))
    }

    static func rescheduleAll() { for m in AppModel.all { m.autosave?.reschedule() } }

    /// Restores a recovery file into the model (unsaved, marked modified) and deletes the recovery copy.
    static func restore(_ info: AutosaveInfo, into model: AppModel) {
        do {
            let d = try load(info)
            model.editor.replaceDocument(d, url: nil)
            if let p = info.originalPath { model.recoveredOriginalPath = p }
            model.editor.isDirty = true
            model.showStart = false
            model.mode = .plan
            remove(info)
            model.editor.print("Recovered “\(info.name)” from the autosave of \(DateFormatter.localizedString(from: info.date, dateStyle: .medium, timeStyle: .short)). Save it to keep the changes.")
            model.revision &+= 1
            model.zoomExtents()
        } catch {
            model.files.showError(error)
        }
    }
}
