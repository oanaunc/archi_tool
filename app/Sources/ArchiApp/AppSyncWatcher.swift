// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// Cloud-synced drawings (COL-013): when the open file changes on disk — iCloud Drive, Dropbox or a colleague on a
/// shared folder saved a newer version — a window without unsaved edits reloads it, and a window with unsaved edits
/// merges the disk version in with the three-way merge (base = the version this window last read or wrote), so no
/// one's work is lost; true conflicts keep the local edit and are listed. iCloud's own conflict versions
/// (`NSFileVersion.unresolvedConflictVersionsOfItem`) are merged the same way and marked resolved.
@MainActor
enum SyncWatcher {
    struct Tracked {
        weak var model: AppModel?
        var url: URL
        var base: ArchiDocument
        var stamp: Stamp
    }
    struct Stamp: Equatable { var modified: Date?; var size: Int; var hash: Int }

    private static var tracked: [ObjectIdentifier: Tracked] = [:]
    private static var timer: Timer?
    static var interval: TimeInterval = 3

    static func stamp(_ url: URL) -> Stamp? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), let data = try? Data(contentsOf: url) else { return nil }
        var h = Hasher(); h.combine(data)
        return Stamp(modified: a[.modificationDate] as? Date, size: data.count, hash: h.finalize())
    }

    /// Starts (or refreshes) watching the window's file after it was opened or saved.
    static func track(_ model: AppModel, url: URL, doc: ArchiDocument) {
        guard url.pathExtension.lowercased() == ArchiFile.fileExtension, let s = stamp(url) else { tracked[ObjectIdentifier(model)] = nil; return }
        tracked[ObjectIdentifier(model)] = Tracked(model: model, url: url, base: doc, stamp: s)
        start()
    }
    static func untrack(_ model: AppModel) { tracked[ObjectIdentifier(model)] = nil }
    static func isTracking(_ model: AppModel) -> Bool { tracked[ObjectIdentifier(model)] != nil }

    private static func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { poll() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { poll() }
        }
    }

    enum Outcome: Equatable { case none, reloaded, merged(taken: Int, conflicts: Int), conflictVersions(Int) }

    /// Checks every watched window; returns what happened per window (for tests and logs).
    @discardableResult
    static func poll() -> [Outcome] {
        var out: [Outcome] = []
        for (k, t) in tracked {
            guard let m = t.model else { tracked[k] = nil; continue }
            guard m.editor.fileURL?.standardizedFileURL == t.url.standardizedFileURL else { tracked[k] = nil; continue }
            out.append(check(m, t))
        }
        return out
    }

    private static func check(_ m: AppModel, _ t: Tracked) -> Outcome {
        let k = ObjectIdentifier(m)
        // iCloud conflict versions first (they come with a changed file).
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: t.url) ?? []
        if !conflicts.isEmpty, m.editor.isIdle {
            let n = mergeConflictVersions(m, url: t.url, versions: conflicts)
            if let s = stamp(t.url) { tracked[k]?.stamp = s }
            return .conflictVersions(n)
        }
        guard let s = stamp(t.url), s != t.stamp, s.hash != t.stamp.hash || s.size != t.stamp.size else {
            if let s = stamp(t.url) { tracked[k]?.stamp = s }
            return .none
        }
        guard m.editor.isIdle, let theirs = try? DocumentIO.read(t.url) else { return .none }   // retry on the next poll
        if !m.isDirty {
            let files = m.files
            _ = files?.load(t.url)
            m.editor.print("\(t.url.lastPathComponent) changed on disk (sync or another user) — reloaded.")
            tracked[k] = Tracked(model: m, url: t.url, base: theirs, stamp: s)
            return .reloaded
        }
        let r = ThreeWayMerge.merge(base: t.base, ours: m.doc, theirs: theirs)
        m.editor.transaction("Merge changes from disk") { $0 = r.doc }
        m.editor.print("\(t.url.lastPathComponent) changed on disk — merged \(r.takenFromTheirs) change(s) into your unsaved edits; \(r.conflicts.count) conflict(s) kept yours. Save to keep both.")
        for c in r.conflicts.prefix(20) { m.editor.print("  \(c.kind) \(c.key): \(c.reason)") }
        m.revision &+= 1
        tracked[k] = Tracked(model: m, url: t.url, base: theirs, stamp: s)
        return .merged(taken: r.takenFromTheirs, conflicts: r.conflicts.count)
    }

    /// Merges iCloud conflict versions into the window (one undo step) and marks them resolved. Returns how many merged.
    @discardableResult
    static func mergeConflictVersions(_ m: AppModel, url: URL, versions: [NSFileVersion]) -> Int {
        var merged = 0
        var doc = m.doc
        var report: [String] = []
        for v in versions {
            guard let theirs = try? DocumentIO.read(v.url) else { continue }
            let base = ConflictCopies.base(for: url, ours: doc, theirs: theirs, theirsDate: v.modificationDate ?? Date())
            let r = ThreeWayMerge.merge(base: base, ours: doc, theirs: theirs)
            doc = r.doc
            merged += 1
            report.append("\(v.localizedNameOfSavingComputer ?? "another Mac"): \(r.takenFromTheirs) change(s), \(r.conflicts.count) conflict(s)")
            v.isResolved = true
        }
        if merged > 0 {
            m.editor.transaction("Merge iCloud conflicts") { $0 = doc }
            m.editor.print("iCloud conflict versions merged — " + report.joined(separator: "; ") + ". Save to keep the merged drawing.")
            m.revision &+= 1
        }
        return merged
    }
}
