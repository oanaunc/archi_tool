// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

// MARK: - URL scheme for Shortcuts and other apps (SCR-024) and AppleScript "do script" (SCR-025)

/// `oanarina-archi://` URLs that Shortcuts ("Open URLs"), AppleScript (`open location`), the Terminal (`open`) or
/// any app can use to drive the front drawing:
///   oanarina-archi://run?command=LINE%200,0%201000,0      run a command line
///   oanarina-archi://open?path=/Users/me/House.archi        open a drawing
///   oanarina-archi://export?format=pdf&path=/tmp/Plan.pdf   export (pdf, dxf, svg, ifc, obj, png …)
///   oanarina-archi://script?path=/Users/me/setup.scr         run a command script file
///   oanarina-archi://new                                     new drawing
/// Links from other apps ask for confirmation first unless "Always Allow" was chosen.
enum AutomationURL {
    static let scheme = "oanarina-archi"
    enum Action: Equatable {
        case run(String), open(String), export(format: String, path: String?), script(String), new
    }

    static func parse(_ url: URL) -> Action? {
        guard url.scheme?.lowercased() == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var q: [String: String] = [:]
        for i in c.queryItems ?? [] { if let v = i.value { q[i.name.lowercased()] = v } }
        let verb = (c.host ?? c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        func path(_ k: String) -> String? { q[k].map { ($0 as NSString).expandingTildeInPath }.flatMap { $0.isEmpty ? nil : $0 } }
        switch verb {
        case "run", "command":
            guard let cmd = q["command"] ?? q["cmd"], !cmd.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return .run(cmd)
        case "open": return path("path").map { .open($0) }
        case "export":
            guard let f = q["format"]?.lowercased(), !f.isEmpty, f.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
            return .export(format: f, path: path("path"))
        case "script": return path("path").map { .script($0) }
        case "new": return .new
        default: return nil
        }
    }

    /// Command line equivalent (shown in the confirmation and logged).
    static func describe(_ a: Action) -> String {
        switch a {
        case .run(let c): return "run the command “\(c)”"
        case .open(let p): return "open \(p)"
        case .export(let f, let p): return "export \(f.uppercased())" + (p.map { " to \($0)" } ?? "")
        case .script(let p): return "run the script \(p)"
        case .new: return "create a new drawing"
        }
    }

    static let allowKey = "automation.alwaysAllowURLs"

    @MainActor static func handle(_ url: URL) {
        guard let a = parse(url) else { NSSound.beep(); return }
        if !UserDefaults.standard.bool(forKey: allowKey) {
            let alert = NSAlert()
            alert.messageText = "Allow automation?"
            alert.informativeText = "Another app asks Oanarina Archi Tool to \(describe(a))."
            alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Always Allow"); alert.addButton(withTitle: "Cancel")
            let r = alert.runModal()
            if r == .alertThirdButtonReturn { return }
            if r == .alertSecondButtonReturn { UserDefaults.standard.set(true, forKey: allowKey) }
        }
        perform(a)
    }

    @MainActor static func perform(_ a: Action) {
        switch a {
        case .open(let p): WindowRouter.openFile(URL(fileURLWithPath: p))
        case .new: front()?.runCommand("NEW")
        case .run(let c): front()?.runCommand(c)
        case .script(let p): front()?.runCommand("SCRIPT \"\(p)\"")
        case .export(let f, let p):
            guard let m = front() else { return }
            m.editor.host?.perform(.export(format: f, path: p), editor: m.editor)
        }
    }
    @MainActor static func front() -> AppModel? {
        AppModel.all.first { $0.window?.isKeyWindow == true } ?? AppModel.all.first { $0.window?.isMainWindow == true } ?? AppModel.all.first
    }
}

/// AppleScript / JXA: `tell application "Oanarina Archi Tool" to «event miscdosc» "LINE 0,0 1000,0 "` (the standard
/// "do script" event) runs command lines in the front drawing and returns their output; `open location` takes the
/// oanarina-archi:// URLs above. AppleScript access is guarded by macOS Automation permission.
@MainActor
final class AppleScriptBridge: NSObject {
    static let shared = AppleScriptBridge()
    static let doScriptClass: AEEventClass = 0x6D697363   // 'misc'
    static let doScriptID: AEEventID = 0x646F7363      // 'dosc'

    func install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(doScript(_:reply:)), forEventClass: AppleScriptBridge.doScriptClass, andEventID: AppleScriptBridge.doScriptID)
    }

    /// Lines to run from the direct parameter (one command per line; blank lines are Enter).
    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(";") }
    }

    @objc func doScript(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue ?? ""
        guard let m = AutomationURL.front() else {
            reply.setParam(NSAppleEventDescriptor(string: "No drawing is open."), forKeyword: keyErrorString); return
        }
        let suspended = NSAppleEventManager.shared().suspendCurrentAppleEvent()
        Task { @MainActor in
            var out: [String] = []
            for l in AppleScriptBridge.lines(text) { out += await m.editor.run(l) }
            if let s = suspended {
                let r = NSAppleEventManager.shared().replyAppleEvent(forSuspensionID: s)
                r.setParam(NSAppleEventDescriptor(string: out.joined(separator: "\n")), forKeyword: keyDirectObject)
                NSAppleEventManager.shared().resume(withSuspensionID: s)
            }
        }
    }
}
