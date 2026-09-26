// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import Darwin
import ArchiCore

/// Opt-in, privacy-preserving crash reports (SYS-025). Off by default. When on, fatal signals and uncaught
/// Objective-C exceptions write a small report (app and macOS version, CPU, the signal or exception and the stack of
/// the crashing thread — never drawing contents or file names) to ~/Library/Logs/Oanarina Archi Tool. On the next
/// launch the app shows the report and lets the user copy it or send it as a GitHub issue — nothing is sent
/// automatically. The signal handler only uses async-signal-safe calls on a file descriptor opened in advance.
enum CrashReporter {
    static let optInKey = "crashReports.optIn"
    static let issueURL = "https://github.com/oanaunc/archi_tool/issues/new"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: optInKey) }
        set { UserDefaults.standard.set(newValue, forKey: optInKey); if newValue { install() } else { uninstall() } }
    }

    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Oanarina Archi Tool", isDirectory: true)
    }

    // State used from the signal handler (plain globals; written before any handler can run).
    nonisolated(unsafe) private static var fd: Int32 = -1
    nonisolated(unsafe) private static var header: [UInt8] = []
    nonisolated(unsafe) private static var path = ""
    nonisolated(unsafe) private static var installed = false
    /// Report file of this run (empty unless the app crashes).
    static var currentReportPath: String { path }
    static var isInstalled: Bool { installed }
    private static let signals: [Int32] = [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP]

    /// Environment line of every report (no user data).
    static func environment() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? "dev"
        let b = info["CFBundleVersion"] as? String ?? "0"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let cpu = "arm64"
        #else
        let cpu = "x86_64"
        #endif
        return "Oanarina Archi Tool \(v) (\(b)), macOS \(os), \(cpu)"
    }

    /// Opens the report file of this run and installs the handlers (no-op unless opted in).
    static func install(force: Bool = false) {
        guard enabled || force, !installed else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        path = folder.appendingPathComponent("crash-\(ProcessInfo.processInfo.processIdentifier)-\(Int(Date().timeIntervalSince1970)).log").path
        fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        header = Array("Crash report\n\(environment())\n".utf8)
        installed = true
        for s in signals { signal(s, CrashReporter.handleSignal) }
        NSSetUncaughtExceptionHandler { e in
            CrashReporter.writeException(name: e.name.rawValue, reason: e.reason ?? "", stack: e.callStackSymbols)
        }
    }

    /// Normal quit: the empty report file of this run is removed.
    static func uninstall() {
        guard installed else { return }
        for s in signals { signal(s, SIG_DFL) }
        NSSetUncaughtExceptionHandler(nil)
        if fd >= 0 { close(fd); fd = -1 }
        if let a = try? FileManager.default.attributesOfItem(atPath: path), (a[.size] as? Int ?? 0) == 0 { try? FileManager.default.removeItem(atPath: path) }
        installed = false
    }

    // MARK: Writing (async-signal-safe)

    private static let handleSignal: @convention(c) (Int32) -> Void = { sig in
        CrashReporter.writeSignal(sig)
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Writes the signal and the stack of the current thread (write(2) and backtrace_symbols_fd only).
    static func writeSignal(_ sig: Int32) {
        guard fd >= 0 else { return }
        header.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, $0.count) }
        var line: [UInt8] = Array("Signal ".utf8)
        var n = sig, digits: [UInt8] = []
        repeat { digits.insert(UInt8(48 + n % 10), at: 0); n /= 10 } while n > 0
        line += digits + [10]
        line.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, $0.count) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
        let c = frames.withUnsafeMutableBufferPointer { backtrace($0.baseAddress, 64) }
        frames.withUnsafeBufferPointer { backtrace_symbols_fd($0.baseAddress, c, fd) }
        fsync(fd)
    }

    static func writeException(name: String, reason: String, stack: [String]) {
        guard fd >= 0 else { return }
        let text = String(decoding: header, as: UTF8.self) + "Exception \(name): \(redact(reason))\n" + stack.joined(separator: "\n") + "\n"
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, $0.count) }
        fsync(fd)
    }

    // MARK: Reports of earlier runs

    /// Non-empty reports left by runs that crashed (not the current run's file).
    static func pendingReports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "log" && $0.path != path
            && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 }.sorted { $0.path < $1.path }
    }

    /// Removes home-folder paths and anything that looks like a file name from report text.
    static func redact(_ s: String) -> String {
        var t = s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let re = try? NSRegularExpression(pattern: "(/[^\\s/]+)+/[^\\s/]+\\.(archi|dxf|dwg|ifc|pdf|png|jpg|obj|skp|3dm)", options: [.caseInsensitive]) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "<file>")
        }
        return t
    }

    static func report(_ url: URL) -> String { redact((try? String(contentsOf: url, encoding: .utf8)) ?? "") }

    static func issueURL(_ text: String) -> URL? {
        var c = URLComponents(string: issueURL)
        c?.queryItems = [URLQueryItem(name: "title", value: "Crash report"), URLQueryItem(name: "body", value: "```\n" + String(text.prefix(5000)) + "\n```")]
        return c?.url
    }

    /// Next launch: offers to review and send reports of runs that crashed.
    @MainActor static func offerPendingReports() {
        let pending = pendingReports()
        guard !pending.isEmpty else { return }
        let text = pending.map(report).joined(separator: "\n\n")
        let alert = NSAlert()
        alert.messageText = "Oanarina Archi Tool quit unexpectedly"
        alert.informativeText = "A crash report was saved (no drawing contents or file names). Would you like to send it? You can review it first."
        alert.addButton(withTitle: "Open GitHub Issue"); alert.addButton(withTitle: "Copy Report"); alert.addButton(withTitle: "Show Report"); alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: if let u = issueURL(text) { NSWorkspace.shared.open(u) }
        case .alertSecondButtonReturn: NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        case .alertThirdButtonReturn: NSWorkspace.shared.activateFileViewerSelecting(pending); return
        default: break
        }
        for u in pending { try? FileManager.default.removeItem(at: u) }
    }
}

/// Settings ▸ General: the opt-in switch.
struct CrashReportToggle: View {
    @State private var on = CrashReporter.enabled
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Save a crash report if the app quits unexpectedly", isOn: Binding(get: { on }, set: { on = $0; CrashReporter.enabled = $0 }))
            Text("Off by default. Reports hold the app and macOS version and the crashing code's stack — no drawing contents or file names — and are only sent if you choose to after reviewing them.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }
}
