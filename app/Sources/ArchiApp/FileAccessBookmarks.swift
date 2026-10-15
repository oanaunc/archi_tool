// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit

enum AppDistribution {
    static var isAppStore: Bool { Bundle.main.object(forInfoDictionaryKey: "ArchiDistributionChannel") as? String == "app-store" }
}

/// Security-scoped grants belong to this installation's preferences, never to a shared .archi drawing.
/// Keep resolved URLs alive while windows, render jobs and watchers use paths. Release each scope on quit.
final class FileAccessBookmarks {
    static let shared = FileAccessBookmarks(defaults: .standard, enabled: AppDistribution.isAppStore)
    private let defaults: UserDefaults
    private let enabled: Bool
    private let key = "SandboxFileBookmarks"
    private let lock = NSRecursiveLock()
    private var active: [String: URL] = [:]

    init(defaults: UserDefaults, enabled: Bool) { self.defaults = defaults; self.enabled = enabled }

    @discardableResult
    func remember(_ url: URL) -> Bool {
        guard enabled else { return true }
        return lock.withLock {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
            var saved = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
            saved[url.standardizedFileURL.path] = data
            defaults.set(saved, forKey: key)
            activate(data)
            return true
        }
    }

    func restore() {
        guard enabled else { return }
        lock.withLock {
            let saved = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
            for data in saved.values { activate(data) }
        }
    }

    private func activate(_ data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        let path = url.standardizedFileURL.path
        if active[path] == nil, url.startAccessingSecurityScopedResource() { active[path] = url }
        // Refresh moved files and expired bookmark metadata while access is active.
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            var saved = defaults.dictionary(forKey: key) as? [String: Data] ?? [:]
            saved = saved.filter { $0.value != data }
            saved[path] = fresh
            defaults.set(saved, forKey: key)
        }
    }

    func stop() {
        lock.withLock {
            for url in active.values { url.stopAccessingSecurityScopedResource() }
            active.removeAll()
        }
    }

    deinit { stop() }
}

extension NSSavePanel {
    /// Capture explicit user selections, including folders for scripts, textures and batch export.
    /// Save-panel URLs may not exist yet; FileController also remembers the document after its first write.
    func runWithFileAccess() -> NSApplication.ModalResponse {
        let response = runModal()
        if response == .OK {
            let selected = (self as? NSOpenPanel)?.urls ?? url.map { [$0] } ?? []
            for item in selected { FileAccessBookmarks.shared.remember(item) }
        }
        return response
    }
}
