// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// TUTORIALRECORD (the in-app tutorial video recorder) and the `--record-tutorials DIR` launch option.
@MainActor
enum TutorialCommands {
    static let defaultFolder = "~/Movies/Oanarina Archi Tool Tutorials"

    static var all: [CommandDef] {
        [
            CommandDef("TUTORIALRECORD", aliases: ["RECORDTUTORIALS", "TUTORIALVIDEOS", "TUTREC"], category: "Tools",
                       summary: "Tutorial videos: plays the scripted tutorials (tutorials/*.tut) in a new window and records each as an MP4 with cursor, captions and typed keys; List, Record or Check (dry run).", modifies: false) { ed in
                let k = try await ed.getKeyword("Tutorials [List/Record/Check]", ["List", "Record", "Check"], defaultValue: "List") ?? "List"
                let urls = TutorialRecorder.scriptURLs(source: nil)
                if k == "List" {
                    guard !urls.isEmpty else { throw CommandError.invalid("No tutorial scripts are bundled with this build.") }
                    for u in urls {
                        do {
                            let s = try TutorialRecorder.load(u)
                            ed.print("\(s.name): \(s.title) — \(s.steps.count) steps, about \(Int(s.estimatedSeconds().rounded())) s")
                        } catch { ed.print("\(u.lastPathComponent): \(error)") }
                    }
                    return
                }
                guard TutorialRecorder.current == nil else { throw CommandError.invalid("A tutorial recording is already running.") }
                guard !urls.isEmpty else { throw CommandError.invalid("No tutorial scripts are bundled with this build.") }
                let names = (try await ed.getString("Tutorials to \(k.lowercased()) (numbers or names separated by spaces, Enter = all)", defaultValue: "") ?? "")
                    .split(separator: " ").map(String.init)
                var dir = TutorialCommands.defaultFolder
                if k == "Record" { dir = try await ed.getString("Output folder <\(TutorialCommands.defaultFolder)>", defaultValue: TutorialCommands.defaultFolder) ?? dir }
                let out = URL(fileURLWithPath: (dir.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath, isDirectory: true)
                ed.print("Recording in a new window; leave it alone until the recorder closes it. Videos → \(out.path)")
                let opts = TutorialRecorder.Options(outputDir: out, sourceDir: nil, only: names, dryRun: k == "Check")
                TutorialLaunch.runInNewWindow(opts) { outcomes in
                    for o in outcomes {
                        ed.print(String(format: "%@: %.0f s%@, %d problem(s)", o.name, o.seconds, o.bytes > 0 ? String(format: ", %.1f MB", Double(o.bytes) / 1e6) : "", o.problems.count))
                        for p in o.problems.prefix(5) { ed.print("  " + p) }
                    }
                    if k == "Record", outcomes.contains(where: { $0.bytes > 0 }) { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                }
            },
        ]
    }

    nonisolated static let items: [CmdItem] = [
        CmdItem(title: "Record Tutorial Videos", symbol: "video.badge.plus", names: ["TUTORIALRECORD"], args: "Record"),
        CmdItem(title: "Check Tutorial Scripts", symbol: "checklist", names: ["TUTORIALRECORD"], args: "Check"),
        CmdItem(title: "List Tutorials", symbol: "list.bullet.rectangle", names: ["TUTORIALRECORD"], args: "List"),
    ]
    nonisolated static var coverageMenus: [(String, [CmdItem])] { [("Tutorial Videos", items)] }
}

/// `--record-tutorials DIR [--tutorials-source DIR] [--only NAME]… [--dry-run] [--tutorial-scale 1|2]`: records the
/// tutorials when the app has launched, then quits (exit status 1 when a tutorial had problems).
@MainActor
enum TutorialLaunch {
    static let valueFlags: Set<String> = ["--record-tutorials", "--tutorials-source", "--only", "--tutorial-scale", "--tutorial-log", "--tutorial-capture"]
    static let plainFlags: Set<String> = ["--dry-run"]

    /// The launch arguments without the recorder's own (so they are not opened as documents).
    nonisolated static func filter(_ args: [String]) -> [String] {
        var out: [String] = [], i = 0
        while i < args.count {
            if valueFlags.contains(args[i]) { i += 2; continue }
            if plainFlags.contains(args[i]) { i += 1; continue }
            out.append(args[i]); i += 1
        }
        return out
    }

    nonisolated static func options(_ args: [String]) -> TutorialRecorder.Options? {
        guard let i = args.firstIndex(of: "--record-tutorials"), i + 1 < args.count else { return nil }
        func path(_ s: String) -> URL { URL(fileURLWithPath: (s as NSString).expandingTildeInPath, isDirectory: true) }
        var o = TutorialRecorder.Options(outputDir: path(args[i + 1]))
        o.quitWhenDone = true
        o.dryRun = args.contains("--dry-run")
        var j = 0
        while j < args.count {
            if j + 1 < args.count {
                switch args[j] {
                case "--tutorials-source": o.sourceDir = path(args[j + 1])
                case "--only": o.only.append(args[j + 1])
                case "--tutorial-scale": if let v = Double(args[j + 1]), v >= 1, v <= 3 { o.scale = CGFloat(v) }
                case "--tutorial-capture": o.layerCapture = args[j + 1].lowercased() == "layer"
                default: break
                }
            }
            j += 1
        }
        return o
    }

    /// Called once the app has finished launching.
    static func start(_ args: [String]) {
        guard let opts = options(args) else { return }
        // Launched through `open`, the app has no terminal: write the report to a file.
        if let i = args.firstIndex(of: "--tutorial-log"), i + 1 < args.count {
            freopen((args[i + 1] as NSString).expandingTildeInPath, "a", stdout)
            freopen((args[i + 1] as NSString).expandingTildeInPath, "a", stderr)
            setvbuf(stdout, nil, _IOLBF, 0)
        }
        print("Tutorial recorder starting (pid \(getpid())).")
        // Nothing may wait for an answer while recording unattended: close any modal alert shown at launch.
        let guardTimer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if let w = NSApp.modalWindow { print("Closed a modal window at launch: \(w.title)"); NSApp.abortModal() }
            }
        }
        RunLoop.main.add(guardTimer, forMode: .common)
        Task { @MainActor in
            var model: AppModel?
            for _ in 0..<200 {
                if let m = AppModel.all.first(where: { $0.window != nil }) { model = m; break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let m = model else { print("Tutorial recorder: no document window."); exit(2) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)   // let startup windows (What's New, floating panels) appear first
            guardTimer.invalidate()
            let outcomes = await TutorialRecorder(model: m, options: opts).runAll()
            for x in AppModel.all { x.editor.isDirty = false; x.autosave?.stop() }
            exit(outcomes.contains { !$0.problems.isEmpty } ? 1 : 0)
        }
    }

    /// Opens a new drawing window and records in it (TUTORIALRECORD), leaving the user's windows untouched.
    static func runInNewWindow(_ opts: TutorialRecorder.Options, done: @escaping ([TutorialRecorder.Outcome]) -> Void) {
        let existing = Set(AppModel.all.map(ObjectIdentifier.init))
        WindowRouter.open(DocumentRequest(kind: .blankMetric))
        Task { @MainActor in
            var model: AppModel?
            for _ in 0..<100 {
                if let m = AppModel.all.first(where: { !existing.contains(ObjectIdentifier($0)) && $0.window != nil }) { model = m; break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let m = model else { done([]); return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            let outcomes = await TutorialRecorder(model: m, options: opts).runAll()
            m.editor.isDirty = false
            m.window?.performClose(nil)
            done(outcomes)
        }
    }
}
