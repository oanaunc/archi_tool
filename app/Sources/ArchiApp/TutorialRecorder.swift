// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import ArchiCore

/// Plays tutorial scripts against the real app (command line, ribbon, canvas, 3D view) and records them as MP4 videos
/// with an animated cursor, click ripples, captions and keystroke pills. Everything the video shows is the app's own
/// behaviour: typed text goes into the command line and is submitted like Enter, ribbon and panel buttons are pressed
/// through their accessibility actions, and canvas clicks are delivered to the plan view as mouse events.
@MainActor
final class TutorialRecorder {
    struct Options {
        var outputDir: URL
        var sourceDir: URL?
        var only: [String] = []
        var dryRun = false
        var scale: CGFloat?
        var quitWhenDone = false
        var layerCapture = false
    }

    struct Outcome {
        var name: String
        var file: URL?
        var seconds: Double
        var frames: Int
        var pixels: (Int, Int)
        var bytes: Int64
        var problems: [String]
    }

    static private(set) var current: TutorialRecorder?
    static var isRecording: Bool { current != nil }

    let model: AppModel
    let options: Options
    private var overlay = TutorialOverlay()
    private var writer: TutorialVideoWriter?
    private var frameCount = 0
    private var time: Double { Double(frameCount) / Double(TutorialTiming.fps) }
    private var problems: [String] = []
    private var cps = 14.0
    private var lastLayers: [TutorialCapture.Layer]?
    private var staticMode = false
    private var stepLabel = ""
    private var logURL: URL?
    private var logLines: [String] = []
    /// What was typed and what the app answered, written next to the video.
    private var trace: [String] = []
    private var watchdog: Timer?
    private var savedDefaults: [String: Any?] = [:]
    private var ribbonTabCache: [String: String] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var captureTime = 0.0, encodeTime = 0.0, captures = 0
    /// Frames up to which the last window capture is reused (slow captures).
    private var reuseUntil = 0
    private var axDumped = false

    /// Directory where tutorial commands write their exports (typed as /tmp/ArchiTutorial/…).
    static let scratch = URL(fileURLWithPath: "/tmp/ArchiTutorial", isDirectory: true)
    static let restoredKeys = ["ribbonTab", "ribbonCollapsed", L10n.key, "archi.script.code", "RecentDocuments", WindowStateMemory.panelsKey, WindowStateMemory.tabKey, "layoutTabs", "quickProperties"]

    init(model: AppModel, options: Options) {
        self.model = model
        self.options = options
    }

    // MARK: Script discovery

    /// Tutorial scripts: the source folder when given (so edited scripts need no rebuild), else the bundled copy.
    static func scriptURLs(source: URL?) -> [URL] {
        let dirs = [source, Bundle.main.resourceURL?.appendingPathComponent("tutorials")].compactMap { $0 }
        for d in dirs {
            let files = ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == TutorialScript.fileExtension }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if !files.isEmpty { return files }
        }
        return []
    }

    static func load(_ url: URL) throws -> TutorialScript {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try TutorialScript.parse(text, name: url.deletingPathExtension().lastPathComponent)
    }

    static func matches(_ name: String, _ only: [String]) -> Bool {
        only.isEmpty || only.contains { name == $0 || name.hasPrefix($0 + "-") || name.hasPrefix($0) }
    }

    // MARK: Running

    /// Records every selected tutorial; returns one outcome per script.
    func runAll() async -> [Outcome] {
        TutorialRecorder.current = self
        defer { TutorialRecorder.current = nil }
        let urls = TutorialRecorder.scriptURLs(source: options.sourceDir).filter { TutorialRecorder.matches($0.deletingPathExtension().lastPathComponent, options.only) }
        try? FileManager.default.createDirectory(at: options.outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: TutorialRecorder.scratch, withIntermediateDirectories: true)
        say("Tutorial recorder: \(urls.count) script(s) → \(options.outputDir.path)\(options.dryRun ? " (dry run)" : "")")
        if urls.isEmpty { say("No tutorial scripts found (looked in \(options.sourceDir?.path ?? "-") and the app bundle).") }
        saveDefaults()
        TutorialCapture.useLayerRendering = options.layerCapture
        // English interface, ribbon expanded; changed only when needed (SwiftUI animates such changes, and animations do
        // not advance while the screen is locked).
        if let l = UserDefaults.standard.string(forKey: L10n.key), l != "en", l != "auto" { UserDefaults.standard.set("en", forKey: L10n.key) }
        if UserDefaults.standard.bool(forKey: "ribbonCollapsed") { UserDefaults.standard.set(false, forKey: "ribbonCollapsed") }
        startWatchdog()
        model.autosave?.stop()
        var out: [Outcome] = []
        for u in urls {
            do {
                let s = try TutorialRecorder.load(u)
                out.append(await record(s))
            } catch {
                say("PROBLEM \(u.lastPathComponent): \(error)")
                out.append(Outcome(name: u.lastPathComponent, file: nil, seconds: 0, frames: 0, pixels: (0, 0), bytes: 0, problems: ["\(error)"]))
            }
        }
        watchdog?.invalidate()
        restoreDefaults()
        model.editor.isDirty = false
        let bad = out.reduce(0) { $0 + $1.problems.count }
        say("RECORDING DONE: \(out.count) tutorial(s), \(bad) problem(s).")
        return out
    }

    private func say(_ s: String) {
        print(s)
        fflush(stdout)
        logLines.append(s)
    }

    private func problem(_ s: String) {
        let p = "[\(String(format: "%.1f", time)) s] \(stepLabel): \(s)"
        problems.append(p)
        say("  PROBLEM " + p)
    }

    private func saveDefaults() {
        for k in TutorialRecorder.restoredKeys { savedDefaults[k] = UserDefaults.standard.object(forKey: k) }
    }

    private func restoreDefaults() {
        for (k, v) in savedDefaults { if let v { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) } }
    }

    /// A step that opens a modal panel would stall the recording: abort it and report.
    private func startWatchdog() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = NSApp.modalWindow else { return }
                self.problem("a modal window (\(w.title)) opened and was closed")
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    private var window: NSWindow? { model.window }

    /// Resets the window to the recording state: 1440×900, plan view, panels on Properties, no dialogs.
    private func prepareWindow() async {
        if !model.editor.isIdle { model.editor.cancel() }
        model.sheet = nil
        model.showCommandSearch = false
        model.cleanScreen = false
        model.showScriptConsole = false
        model.showSectionBoxPanel = false
        model.showSunStudy = false
        model.showPanels = true
        model.panelTab = .properties
        model.commandInput = ""
        model.commandLog = []
        closeOtherWindows()
        if UserDefaults.standard.string(forKey: "ribbonTab") != RibbonTab.home.rawValue { UserDefaults.standard.set(RibbonTab.home.rawValue, forKey: "ribbonTab") }
        if let w = window {
            if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
            let screen = w.screen ?? NSScreen.main
            let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: 1440, height: 900)
            let origin = NSPoint(x: vf.minX + max(0, (vf.width - size.width) / 2), y: vf.maxY - size.height)
            w.setFrame(NSRect(origin: origin, size: size), display: true)
            // Clicks are mouse events: through the window when it is key, else straight to the view under the point.
            if !options.dryRun { NSApp.activate(ignoringOtherApps: true); NSApp.activate() }
            w.makeKeyAndOrderFront(nil)
        }
        await settle(3)
        await forceRedraw()
    }

    /// Resizes the window by a point and back: every view lays out and draws again. Needed while the screen is locked
    /// or asleep, when parts of the window (the ribbon's scroll view) are otherwise never drawn.
    private func forceRedraw() async {
        guard let w = window else { return }
        var f = w.frame
        f.size.width -= 1
        w.setFrame(f, display: true)
        await settle(1)
        f.size.width += 1
        w.setFrame(f, display: true)
        TutorialCapture.fullRedraw = true
        await settle(1)
    }

    private func closeOtherWindows() {
        for w in NSApp.windows where w !== window && w.isVisible && w.sheetParent == nil {
            let cls = String(describing: type(of: w))
            if cls.contains("StatusBar") || cls.contains("Menu") { continue }
            w.orderOut(nil)
        }
    }

    private func settle(_ turns: Int = 2) async {
        for _ in 0..<turns { try? await Task.sleep(nanoseconds: options.dryRun ? 5_000_000 : 30_000_000) }
    }

    // MARK: One tutorial

    func record(_ s: TutorialScript) async -> Outcome {
        problems = []
        trace = []
        let wall0 = Date()
        frameCount = 0
        reuseUntil = 0
        lastLayers = nil
        cps = 14
        lastWorkspace = nil
        stepLabel = "setup"
        overlay = TutorialOverlay()
        say("TUTORIAL \(s.name): \(s.title) (about \(Int(s.estimatedSeconds().rounded())) s)")
        let promptHook = model.editor.onPromptChange
        model.editor.onPromptChange = { [weak self] in promptHook?(); self?.promptChanges += 1 }
        defer { model.editor.onPromptChange = promptHook }
        await prepareWindow()
        model.newDocument(.blankMetric)
        model.commandLog = []
        await settle(3)
        guard let w = window else {
            return Outcome(name: s.name, file: nil, seconds: 0, frames: 0, pixels: (0, 0), bytes: 0, problems: ["no document window"])
        }
        overlay.size = w.frame.size
        overlay.cardTitle = s.title
        overlay.cardSubtitle = s.summary
        overlay.cardNumber = String(s.name.prefix { $0.isNumber })
        overlay.captionBaseline = captionBaseline()
        overlay.cursor = CGPoint(x: w.frame.width * 0.55, y: w.frame.height * 0.45)
        overlay.cursorVisible = true
        if isOverCanvas(overlay.cursor), let c = model.canvas, let e = mouseEvent(.mouseMoved, overlay.cursor) { c.mouseMoved(with: e); overlay.cursorOverCanvas = true }
        let scale = options.scale ?? w.backingScaleFactor
        let file = options.outputDir.appendingPathComponent(s.name + ".mp4")
        if !options.dryRun {
            do {
                writer = try TutorialVideoWriter(url: file, width: Int(w.frame.width * scale), height: Int(w.frame.height * scale))
            } catch {
                say("  2× video not available (\(error.localizedDescription)); recording at 1×.")
                writer = try? TutorialVideoWriter(url: file, width: Int(w.frame.width), height: Int(w.frame.height))
            }
            if writer == nil { problem("cannot create the video file"); return Outcome(name: s.name, file: nil, seconds: 0, frames: 0, pixels: (0, 0), bytes: 0, problems: problems) }
        }
        // Leading setup steps run under the title card.
        var steps = s.steps[...]
        while let st = steps.first, TutorialRecorder.isSetup(st) {
            await perform(st)
            steps = steps.dropFirst()
        }
        await settle(3)
        overlay.introEnd = TutorialTiming.intro
        staticMode = true
        await frames(seconds: TutorialTiming.intro)
        staticMode = false
        for (i, st) in steps.enumerated() {
            stepLabel = "step \(i + 1) \(TutorialRecorder.describe(st))"
            if options.dryRun { say("    · " + stepLabel) }
            await perform(st)
        }
        stepLabel = "end"
        overlay.caption("", "")
        await frames(seconds: 0.6)
        overlay.outroStart = time
        overlay.cursorVisible = false
        staticMode = true
        await frames(seconds: TutorialTiming.outro)
        staticMode = false
        if !model.editor.isIdle { model.editor.cancel() }
        var bytes: Int64 = 0
        var px = (0, 0)
        if let wr = writer {
            px = (wr.width, wr.height)
            do { try await wr.finish() } catch { problem("video: \(error.localizedDescription)") }
            bytes = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? 0
            writer = nil
        }
        writeLog(s.name)
        if captures > 0 { say(String(format: "  timing: %d captures, %.0f ms per capture, %.0f ms per frame to compose and encode", captures, 1000 * captureTime / Double(captures), 1000 * encodeTime / Double(max(1, frameCount)))) }
        captureTime = 0; encodeTime = 0; captures = 0; axDumped = false
        say("  clicks: \(clickStats.window) through the window, \(clickStats.direct) sent to the view, \(clickStats.failed) replaced by the action; app active \(NSApp.isActive), key window \(window?.isKeyWindow ?? false)")
        clickStats = (0, 0, 0)
        closeOtherWindows()
        model.editor.isDirty = false
        say(String(format: "  recorded in %.0f s", Date().timeIntervalSince(wall0)))
        say(String(format: "  %@: %.1f s, %d frames%@%@, %d problem(s)", s.name, time, frameCount,
                   px.0 > 0 ? ", \(px.0)×\(px.1)" : "", bytes > 0 ? String(format: ", %.1f MB → %@", Double(bytes) / 1e6, file.path) : "", problems.count))
        return Outcome(name: s.name, file: options.dryRun ? nil : file, seconds: time, frames: frameCount, pixels: px, bytes: bytes, problems: problems)
    }

    /// The command log of the tutorial, next to the video (useful to check a script).
    private func writeLog(_ name: String) {
        let text = trace.joined(separator: "\n") + "\n\n" + problems.map { "PROBLEM " + $0 }.joined(separator: "\n") + "\n"
        try? text.write(to: options.outputDir.appendingPathComponent(name + ".log"), atomically: true, encoding: .utf8)
    }

    static func isSetup(_ st: TutorialStep) -> Bool {
        switch st {
        case .open, .run, .runFile, .panels, .speed, .closeWindow, .jsClear: return true
        default: return false
        }
    }

    static func describe(_ st: TutorialStep) -> String {
        switch st {
        case .type(let l): return "type \(l)"
        case .typeLine(let l): return "typeline \(l)"
        case .run(let l): return "run \(l)"
        case .click(let t): return "click \(t)"
        case .pick(let x, let y): return "pick \(x),\(y)"
        default: return String(describing: st).prefix(60).description
        }
    }

    /// Top of the command line: captions and pills sit just above it.
    private func captionBaseline() -> CGFloat {
        if let c = model.canvas, c.window != nil {
            let r = c.convert(c.bounds, to: nil)
            return max(60, r.minY + 6)
        }
        return 150
    }

    // MARK: Frames

    private func frames(seconds: Double, _ update: ((Double) -> Void)? = nil) async {
        let n = max(1, Int((seconds * Double(TutorialTiming.fps)).rounded()))
        for i in 0..<n {
            update?(Double(i + 1) / Double(n))
            await emit()
        }
    }

    /// Captures and writes one frame (or only advances the clock in a dry run).
    private func emit() async {
        overlay.time = time
        if frameCount % 15 == 0 { overlay.captionBaseline = captionBaseline() }
        if options.dryRun {
            frameCount += 1
            if frameCount % 4 == 0 { await Task.yield() }
            return
        }
        try? await Task.sleep(nanoseconds: 4_000_000)
        guard let w = window, let wr = writer else { frameCount += 1; return }
        // Static stretches (waits, cards) re-capture every third frame.
        let layers: [TutorialCapture.Layer]
        let t0 = CFAbsoluteTimeGetCurrent()
        // A view that is slow to draw (a sheet with 3D viewports) is captured less often: the window picture is reused
        // for as many frames as its capture took, while the cursor and captions still move at the full frame rate.
        let reuse = lastLayers != nil && !TutorialCapture.fullRedraw && (frameCount < reuseUntil || (staticMode && frameCount % 3 != 0))
        if reuse, let l = lastLayers { layers = l } else {
            layers = TutorialCapture.layers(main: w); lastLayers = layers; captures += 1
            let cost = CFAbsoluteTimeGetCurrent() - t0
            reuseUntil = frameCount + min(12, Int(cost * Double(TutorialTiming.fps) * 0.8))
        }
        let t1 = CFAbsoluteTimeGetCurrent()
        captureTime += t1 - t0
        defer { encodeTime += CFAbsoluteTimeGetCurrent() - t1 }
        let ov = overlay
        let size = w.frame.size
        do {
            try wr.append { ctx in
                let sx = CGFloat(wr.width) / size.width, sy = CGFloat(wr.height) / size.height
                ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: wr.width, height: wr.height))
                ctx.interpolationQuality = .high
                ctx.scaleBy(x: sx, y: sy)
                for l in layers {
                    ctx.saveGState()
                    if l.shadow { ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: CGColor(gray: 0, alpha: 0.55)) }
                    ctx.draw(l.image, in: l.rect)
                    ctx.restoreGState()
                }
                ov.draw(in: ctx)
            }
        } catch { if !problems.contains(where: { $0.contains("video frame") }) { problem("video frame: \(error.localizedDescription)") } }
        frameCount += 1
    }

    private func jitter() -> Double { Double.random(in: 0.7...1.35, using: &rng) }

    // MARK: Steps

    private func perform(_ st: TutorialStep) async {
        switch st {
        case .open(let k, let arg): await open(k, arg)
        case .caption(let t, let s):
            overlay.caption(t, s)
            await frames(seconds: t.isEmpty ? 0.2 : 0.6)
        case .note(let text, let anchor, let d):
            var p: CGPoint?
            switch anchor {
            case .top: p = nil
            case .model(let x, let y): p = modelPoint(x, y)
            case .ui(let t): p = await locate(t)?.point
            }
            overlay.notes.append(.init(text: text, point: p, start: time, end: time + d))
            await frames(seconds: 0.3)
        case .type(let l): await typeTokens(TutorialScript.typedTokens(substitute(l)))
        case .typeLine(let l): await typeLine(substitute(l))
        case .enter:
            let idle = model.editor.isIdle
            if idle { overlay.pill = "" }
            await pressEnter()
            if idle, let c = model.editor.activeCommand { overlay.pill = "⏎ " + c.name }
        case .escape:
            model.cancelCommand()
            overlay.pill = "Esc"; overlay.pillTime = time
            await frames(seconds: TutorialTiming.afterEnter)
        case .click(let t): await click(t, press: true)
        case .hover(let t): await click(t, press: false)
        case .pick(let x, let y): await canvasClick(x, y, click: true)
        case .move(let x, let y): await canvasClick(x, y, click: false)
        case .drag(let x1, let y1, let x2, let y2): await drag(x1, y1, x2, y2)
        case .orbit(let deg, let secs): await orbit(deg, secs)
        case .camera(let n): await typeTokens(["CAMERA", n])
        case .style(let n): await typeTokens(["VSCURRENT", n])
        case .zoom(let z): await zoom(z)
        case .wait(let s):
            staticMode = true
            await frames(seconds: s)
            staticMode = false
        case .speed(let v): cps = v
        case .js(let line): await typeScript(line)
        case .jsClear:
            model.showScriptConsole = true
            await settle(3)
            setScriptCode("")
            await settle()
        case .run(let l):
            let before = model.commandLog.count
            await model.editor.run(substitute(l))
            model.canvas?.needsDisplay = true
            checkLog(from: before, command: l)
            await settle()
        case .runFile(let f):
            let dirs = [options.sourceDir, Bundle.main.resourceURL?.appendingPathComponent("tutorials")].compactMap { $0 }
            guard let u = dirs.map({ $0.appendingPathComponent(f) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let text = try? String(contentsOf: u, encoding: .utf8) else { problem("setup file \(f) not found"); return }
            for raw in text.components(separatedBy: .newlines) {
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix(";") || l.hasPrefix("#") { continue }
                let before = model.commandLog.count
                await model.editor.run(substitute(l))
                checkLog(from: before, command: l)
            }
            model.editor.history = UndoHistory()
            model.commandLog = []
            model.zoomExtents()
            await settle(3)
        case .closeWindow(let title):
            if title.lowercased() == "sheet" || title.lowercased() == "dialog" { model.sheet = nil; await settle(2); return }
            for w in NSApp.windows where w !== window && w.isVisible && w.title.lowercased().hasPrefix(title.lowercased()) { w.orderOut(nil) }
            await settle()
        case .panels(let on): model.showPanels = on; await settle()
        }
    }

    private func substitute(_ s: String) -> String {
        s.replacingOccurrences(of: "$TMP", with: TutorialRecorder.scratch.path)
    }

    private func open(_ kind: String, _ arg: String?) async {
        switch kind {
        case "start": model.newDocument(.blankMetric); model.showStart = true
        case "new": model.newDocument(.blankMetric)
        case "imperial": model.newDocument(.blankImperial)
        case "building": model.newDocument(.building)
        case "sample":
            let name = arg ?? "Cedar House"
            guard let u = SampleProjects.bundled(name) ?? options.sourceDir.map({ $0.deletingLastPathComponent().appendingPathComponent("assets/demo/\(name).archi") }),
                  FileManager.default.fileExists(atPath: u.path) else { problem("sample \(name) not found"); return }
            _ = model.files.load(u)
        case "file":
            let p = (substitute(arg ?? "") as NSString).expandingTildeInPath
            let u = p.hasPrefix("/") ? URL(fileURLWithPath: p) : (options.sourceDir ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent(p)
            if !model.files.load(u) { problem("cannot open \(u.path)") }
        default: break
        }
        model.editor.isDirty = false
        model.commandLog = []
        TutorialCapture.fullRedraw = true
        await settle(4)
        model.zoomExtents()
        await settle(2)
        await forceRedraw()
    }

    // MARK: Typing

    private func typeChars(_ s: String) async {
        for ch in s {
            model.commandInput.append(ch)
            overlay.pill += String(ch)
            overlay.pillTime = time
            await frames(seconds: jitter() / cps)
        }
    }

    private func typeTokens(_ tokens: [String]) async {
        if model.editor.isIdle { overlay.pill = "" }
        for tok in tokens {
            if !overlay.pill.isEmpty && !overlay.pill.hasSuffix(" ") { overlay.pill += " " }
            let before = model.commandLog.count
            await typeChars(tok)
            await frames(seconds: 0.12)
            await pressEnter(logFrom: before, label: tok)
        }
    }

    private func typeLine(_ line: String) async {
        if model.editor.isIdle { overlay.pill = "" }
        let before = model.commandLog.count
        await typeChars(line)
        await frames(seconds: 0.15)
        await pressEnter(logFrom: before, label: line)
    }

    private func pressEnter(logFrom: Int? = nil, label: String = "") async {
        let before = logFrom ?? model.commandLog.count
        overlay.pillEnter = time
        overlay.pillTime = time
        if overlay.pill.isEmpty { overlay.pill = "Enter" }
        let prompts = promptChanges
        model.enterPressed()
        await waitForEditor(since: prompts, logFrom: before)
        TutorialCapture.fullRedraw = true
        checkLog(from: before, command: label)
        await frames(seconds: model.editor.isIdle ? TutorialTiming.afterEnter : TutorialTiming.betweenInputs)
    }

    /// Waits until the editor asks for the next input or finishes; long work (renders, exports) does not stretch the video.
    private func waitForEditor(since prompts: Int? = nil, logFrom: Int? = nil, maxSeconds: Double = 180) async {
        let ed = model.editor
        let start = Date()
        var n = 0
        await frames(seconds: 2.0 / Double(TutorialTiming.fps))
        // Ready for the next input: the command ended, or it asked a new question (a rejected input re-prints the
        // prompt without asking again, which shows as new log lines).
        func ready() -> Bool {
            if ed.isIdle { return true }
            guard ed.request != nil else { return false }
            guard let p = prompts else { return true }
            if promptChanges != p { return true }
            if let l = logFrom, model.commandLog.count > l, Date().timeIntervalSince(start) > 0.3 { return true }
            return Date().timeIntervalSince(start) > 4
        }
        while !ready() {
            if Date().timeIntervalSince(start) > maxSeconds { problem("command still running after \(Int(maxSeconds)) s; cancelled"); ed.cancel(); break }
            if n < 36 { await emit(); n += 1 } else { try? await Task.sleep(nanoseconds: 20_000_000) }
        }
        model.canvas?.needsDisplay = true
    }

    private static let errorMarkers = ["Unknown command", "Error:", "not found", "No suitable object", "Invalid", "invalid", "Cannot ", "cannot ",
                                       "must be", "needs at least", "Requires", "is shorter than", "is taller than", "would overlap", "No enclosing",
                                       "Choose a level", "Use a size", "No saved", "Open the 3D view first", "needs a document window", "Select one or more",
                                       "Select building elements first", "has no 3D content", "Nothing", "failed", "Failed"]

    private func checkLog(from: Int, command: String) {
        let lines = model.commandLog.count >= from ? Array(model.commandLog[from...]) : model.commandLog
        trace.append(String(format: "[%6.1f] » %@", time, command))
        trace += lines.map { "          " + $0 }
        for l in lines where TutorialRecorder.errorMarkers.contains(where: { l.contains($0) }) {
            problem("\"\(command)\" → \(l)")
        }
    }

    // MARK: Script console

    /// The console's code editor (an NSTextView), found in the window.
    private func consoleTextView() -> NSTextView? {
        guard let root = window?.contentView else { return nil }
        func find(_ v: NSView) -> NSTextView? {
            if let tv = v as? NSTextView, String(describing: type(of: tv)) == "ScriptTextView" { return tv }
            for sv in v.subviews { if let t = find(sv) { return t } }
            return nil
        }
        return find(root)
    }

    /// Sets the console code the way typing does: through the editor's text view, so the console's own state follows.
    private func setScriptCode(_ code: String) {
        UserDefaults.standard.set(code, forKey: "archi.script.code")
        guard let tv = consoleTextView() else { return }
        if tv.string != code {
            tv.string = code
            tv.setSelectedRange(NSRange(location: (code as NSString).length, length: 0))
            tv.didChangeText()
            tv.scrollRangeToVisible(tv.selectedRange())
        }
    }

    private func typeScript(_ line: String) async {
        if !model.showScriptConsole { model.showScriptConsole = true; await settle(3); await frames(seconds: 0.4) }
        var code = consoleTextView()?.string ?? UserDefaults.standard.string(forKey: "archi.script.code") ?? ""
        if !code.isEmpty && !code.hasSuffix("\n") { code += "\n" }
        setScriptCode(code)
        let perChar = jitter() / (cps * 1.6)
        var pending = 0.0
        for ch in line {
            code.append(ch)
            pending += perChar
            // Several characters per frame when typing is faster than the frame rate; never stop right after "archi."
            // (the editor would open its completion list).
            if (pending >= 1.0 / Double(TutorialTiming.fps) || options.dryRun) && !code.hasSuffix("archi.") && !code.hasSuffix("archi.run(\"") {
                setScriptCode(code)
                await frames(seconds: pending)
                pending = 0
            }
        }
        code.append("\n")
        setScriptCode(code)
        await frames(seconds: 0.15)
    }

    // MARK: Cursor and UI targets

    private func modelPoint(_ x: Double, _ y: Double) -> CGPoint? {
        guard let c = model.canvas, c.window != nil else { return nil }
        return c.convert(c.toView(Vec2(x, y)), to: nil)
    }

    private func isOverCanvas(_ p: CGPoint) -> Bool {
        guard let c = model.canvas, c.window != nil else { return false }
        return c.convert(c.bounds, to: nil).contains(p)
    }

    private func mouseEvent(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent? {
        guard let w = window else { return nil }
        return NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
    }

    /// Smooth cursor motion (ease in/out); over the plan the canvas receives mouse-moved events so snaps and rubber bands follow.
    private func moveCursor(to p: CGPoint, dragging: Bool = false) async {
        let a = overlay.cursor
        let d = hypot(p.x - a.x, p.y - a.y)
        let secs = d < 2 ? 0.05 : min(0.95, max(0.3, Double(d) / 1150))
        // A slight arc looks like a hand movement.
        let bend = CGPoint(x: -(p.y - a.y) * 0.08, y: (p.x - a.x) * 0.08)
        await frames(seconds: secs) { t in
            let e = CGFloat(t * t * (3 - 2 * t))
            let arc = CGFloat(4 * t * (1 - t))
            let q = CGPoint(x: a.x + (p.x - a.x) * e + bend.x * arc, y: a.y + (p.y - a.y) * e + bend.y * arc)
            let wasOver = self.overlay.cursorOverCanvas
            self.overlay.cursor = q
            self.overlay.cursorOverCanvas = self.isOverCanvas(q) && self.model.mode != .model
            if let c = self.model.canvas, c.window != nil, c.convert(c.bounds, to: nil).contains(q), let ev = self.mouseEvent(dragging ? .leftMouseDragged : .mouseMoved, q) {
                if dragging { c.mouseDragged(with: ev) } else { c.mouseMoved(with: ev) }
            } else if wasOver, let c = self.model.canvas, let ev = self.mouseEvent(.mouseMoved, q) {
                c.mouseExited(with: ev)
            }
        }
    }

    private func pressAnimation(at p: CGPoint) async {
        overlay.pressed = true
        overlay.click(at: p)
        await frames(seconds: 0.1)
    }

    private func canvasClick(_ x: Double, _ y: Double, click: Bool) async {
        if model.mode == .model || model.mode == .sheet { problem("canvas click needs the 2D plan (mode is \(model.mode.rawValue))"); return }
        guard let p = modelPoint(x, y), let c = model.canvas else { problem("no plan canvas"); return }
        if !c.convert(c.visibleRect, to: nil).contains(p) { problem("point \(x),\(y) is outside the visible plan") }
        await moveCursor(to: p)
        await frames(seconds: 0.12)
        guard click else { return }
        let before = model.commandLog.count
        await pressAnimation(at: p)
        if let d = mouseEvent(.leftMouseDown, p) { c.mouseDown(with: d) }
        if let u = mouseEvent(.leftMouseUp, p) { c.mouseUp(with: u) }
        overlay.pressed = false
        await waitForEditor()
        checkLog(from: before, command: "pick \(x),\(y)")
        await frames(seconds: 0.35)
    }

    private func drag(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) async {
        guard let a = modelPoint(x1, y1), let b = modelPoint(x2, y2), let c = model.canvas else { problem("drag needs the 2D plan"); return }
        await moveCursor(to: a)
        overlay.pressed = true
        overlay.click(at: a)
        if let d = mouseEvent(.leftMouseDown, a) { c.mouseDown(with: d) }
        await frames(seconds: 0.1)
        await moveCursor(to: b, dragging: true)
        await frames(seconds: 0.15)
        if let u = mouseEvent(.leftMouseUp, b) { c.mouseUp(with: u) }
        overlay.pressed = false
        await waitForEditor()
        await frames(seconds: 0.4)
    }

    /// Count of document objects, to see whether a script ran.
    private var docSize: Int { model.doc.entities.count + model.doc.elements.count }

    /// Waits (in real time, while recording frames) until the document changes; scripts run asynchronously.
    private func waitForDocChange(from n: Int, seconds: Double) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            if docSize != n { return true }
            if options.dryRun { try? await Task.sleep(nanoseconds: 20_000_000) } else { await emit() }
        }
        return docSize != n
    }

    /// The console's Run button: a click, then ⌘↩, then running the code with the console's engine. The console
    /// records what it ran in its history, which tells whether it ran the typed code (while the screen is locked
    /// SwiftUI may not have applied the typing to the console's state yet).
    private func pressRun(_ hit: Hit?) async {
        let code = consoleTextView()?.string ?? UserDefaults.standard.string(forKey: "archi.script.code") ?? ""
        let docBefore = model.editor.doc
        let historyKey = "archi.script.history"
        let lastRun = UserDefaults.standard.stringArray(forKey: historyKey)?.first
        let sizeBefore = docSize
        /// nil: nothing ran yet; true: the typed code ran; false: the console ran other (older) code.
        func ranTyped() -> Bool? {
            let h = UserDefaults.standard.stringArray(forKey: historyKey)?.first
            guard h != lastRun || docSize != sizeBefore || model.editor.doc != docBefore else { return nil }
            return h?.trimmingCharacters(in: .whitespacesAndNewlines) == code.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Reopen the console between two frames: the new console reads the typed code from its stored state.
        UserDefaults.standard.set(code, forKey: "archi.script.code")
        model.showScriptConsole = false
        await settle(3)
        model.showScriptConsole = true
        await settle(4)
        await forceRedraw()
        var how = ""
        if let h = hit, let hw = h.window, let lp = h.local, !options.dryRun {
            await pressAnimation(at: h.point)
            await TutorialLocator.click(lp, in: hw)
            overlay.pressed = false
            await frames(seconds: 1.0)
            if ranTyped() != nil { how = "clicked" }
        }
        if how.isEmpty, let w = window, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                                                 windowNumber: w.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
            _ = w.performKeyEquivalent(with: e)
            await frames(seconds: 1.0)
            if ranTyped() != nil { how = "⌘↩" }
        }
        if ranTyped() == true { clickStats.window += 1; trace.append("          (Run \(how): the typed code ran)"); return }
        if ranTyped() == false {
            // The console ran older code: undo its changes before running the typed code.
            model.editor.transaction("Tutorial") { $0 = docBefore }
        }
        clickStats.failed += 1
        let r = await ScriptEngine.forModel(model).evaluate(code)
        for l in r.output { model.editor.print(l) }
        if let e = r.error { problem("script error: \(e)") }
        _ = await waitForDocChange(from: docSize, seconds: 0.5)
        trace.append("          (Run by the console's engine directly\(how.isEmpty ? "" : "; the console ran older code") )")
    }

    private func click(_ t: TutorialTarget, press: Bool) async {
        if case .button(let label, _) = t, press, TutorialLocator.norm(label) == "run" {
            let hit = await locate(t)
            if let h = hit { await moveCursor(to: h.point); await frames(seconds: 0.15) }
            await pressRun(hit)
            await frames(seconds: 0.45)
            return
        }
        // A ribbon button on another tab: click the tab first, like a user would.
        if case .ribbon(let cmd) = t {
            if let tab = await ribbonTab(for: cmd), tab != UserDefaults.standard.string(forKey: "ribbonTab") { await click(.ribbonTab(tab), press: true) }
        }
        guard let hit = await locate(t) else {
            problem("UI target \(t) not found\(press ? "; used its action directly" : "")")
            dumpText()
            if press { fallback(t) }
            await frames(seconds: 0.5)
            return
        }
        await moveCursor(to: hit.point)
        await frames(seconds: 0.15)
        guard press else { return }
        let before = model.commandLog.count
        let state = uiState()
        if !options.dryRun { await forceRedraw() }
        await pressAnimation(at: hit.point)
        if let hw = hit.window, let lp = hit.local {
            await TutorialLocator.click(lp, in: hw)
            await settle(3)
            if !verify(t, logFrom: before, stateBefore: state) {
                await TutorialLocator.click(lp, in: hw, direct: true)
                await settle(3)
                if verify(t, logFrom: before, stateBefore: state) { clickStats.direct += 1 } else { clickStats.failed += 1 }
            } else { clickStats.window += 1 }
        } else { _ = hit.press() }
        TutorialCapture.fullRedraw = true
        overlay.pressed = false
        await settle(2)
        if !verify(t, logFrom: before, stateBefore: state) {
            if !options.dryRun { say("  (\(t): the click did not take effect; using its action)") }
            fallback(t)
            await settle(3)
            if case .button(let label, _) = t, TutorialLocator.norm(label) == "run", !verify(t, logFrom: before, stateBefore: state) {
                // Last resort for the console: evaluate its code with the console's engine.
                let code = UserDefaults.standard.string(forKey: "archi.script.code") ?? ""
                let r = await ScriptEngine.forModel(model).evaluate(code)
                for l in r.output { model.editor.print(l) }
                if let e = r.error { problem("script error: \(e)") }
            }
        }
        if case .ribbon = t { await waitForEditor() }
        if case .ribbonTab = t { await forceRedraw() }
        checkLog(from: before, command: "click \(t)")
        await frames(seconds: 0.45)
    }

    /// Writes the text the locator reads in the window to text-<time>.txt (once per tutorial) to help fix a script's targets.
    private func dumpText() {
        guard !axDumped, !options.dryRun, let w = window else { return }
        axDumped = true
        let words = TutorialLocator.words(in: w).filter(\.line)
        let text = words.map { "\($0.text)\t\(Int($0.rect.minX)),\(Int($0.rect.minY)) \(Int($0.rect.width))×\(Int($0.rect.height))" }.joined(separator: "\n")
        try? text.write(to: options.outputDir.appendingPathComponent("text-\(Int(time)).txt"), atomically: true, encoding: .utf8)
        say("  (\(words.count) text lines of the window written to text-\(Int(time)).txt)")
    }

    /// What a target's button does, used when its accessibility element cannot be found.
    private func fallback(_ t: TutorialTarget) {
        switch t {
        case .ribbon(let c): model.runCommand(c)
        case .ribbonTab(let n): UserDefaults.standard.set(RibbonTab.allCases.first { $0.rawValue.lowercased() == n.lowercased() }?.rawValue ?? n, forKey: "ribbonTab")
        case .mode(let m): if let wm = WorkspaceMode.allCases.first(where: { $0.rawValue.lowercased() == m.lowercased() }) { model.mode = wm }
        case .panel(let n): if let p = PanelTab.allCases.first(where: { $0.rawValue.lowercased() == n.lowercased() }) { model.showPanels = true; model.panelTab = p }
        case .commandLine: model.focusCommandLine()
        case .statusBar(let n):
            let map: [String: WritableKeyPath<DraftSettings, Bool>] = ["GRID": \.showGrid, "SNAP": \.gridSnap, "ORTHO": \.ortho, "POLAR": \.polarTracking,
                                                                        "OTRACK": \.objectSnapTracking, "OSNAP": \.objectSnap, "DYN": \.dynamicInput, "LWT": \.lineweightDisplay]
            if let kp = map[n.uppercased()] { model.editor.settings[keyPath: kp].toggle(); model.revision &+= 1 }
        case .button(let label, let win):
            // What the app's own buttons do, for buttons whose click could not be delivered (inactive app, locked screen).
            switch TutorialLocator.norm(label) {
            case "cedar house", "nordic house":
                let name = label.lowercased().hasPrefix("cedar") ? "Cedar House" : "Nordic House"
                if let u = SampleProjects.prepare(name) ?? SampleProjects.bundled(name) { model.files.openURL(u) }
            case "new drawing": model.newDocument(.blankMetric)
            case "build sample house": model.newDocument(.sample); model.buildSampleHouse()
            case "run", "render":
                // The console's Run and the render window's Render buttons are also ⌘↩.
                let wins = NSApp.orderedWindows.filter { x in x.isVisible && (win.map { t in x.title.lowercased().hasPrefix(t.lowercased()) } ?? (x === window)) }
                if let w = wins.first ?? window, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                                            windowNumber: w.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                    _ = w.performKeyEquivalent(with: e)
                }
            default: problem("button \(label) has no known action")
            }
        }
    }

    struct Hit { var point: CGPoint; var window: NSWindow? = nil; var local: CGPoint? = nil; var press: () -> Bool = { false } }

    /// Top edge of the workspace (below the ribbon), in window coordinates.
    private func workspaceRect() -> CGRect? {
        if let c = model.canvas, c.window != nil { return c.convert(c.bounds, to: nil) }
        if let v = model.viewport3D?.view, v.window != nil { return v.convert(v.bounds, to: nil) }
        return nil
    }

    /// Workspace (below the ribbon) as last seen with the plan: the mode badge and panel tabs are placed from it.
    private var lastWorkspace: CGRect?
    private var clickStats = (window: 0, direct: 0, failed: 0)
    /// Counts the editor's prompt changes (a new question or the end of a command).
    private var promptChanges = 0

    /// Finds a UI element: controls with a fixed order (ribbon tabs, the 2D/3D/Split/Sheet badge, panel tabs) from the
    /// window's control frames; labelled buttons (ribbon commands, dialogs, the start screen) by reading their text with
    /// Vision. Pressing sends real mouse events to the window.
    private func locate(_ t: TutorialTarget) async -> Hit? {
        guard let w = window else { return nil }
        if options.dryRun { return dryHit(t) }
        TutorialCapture.fullRedraw = true
        let W = w.frame.width, H = w.frame.height
        if let r = workspaceRect(), model.mode == .plan { lastWorkspace = r }
        let ws = lastWorkspace ?? workspaceRect() ?? CGRect(x: 0, y: 150, width: W - 300, height: H - 300)
        func at(_ r: CGRect) -> Hit {
            let p = CGPoint(x: r.midX, y: r.midY)
            return Hit(point: p, window: w, local: p)
        }
        func labelled(_ word: TutorialLocator.Word) -> Hit { at(TutorialLocator.control(for: word, in: w) ?? word.rect) }
        switch t {
        case .ribbon(let cmd):
            let titles = TutorialRecorder.ribbonTitles(cmd).sorted { $0.count > $1.count }
            let words = TutorialLocator.words(in: w)
            let region = CGRect(x: 0, y: ws.maxY, width: W, height: H - 60 - ws.maxY)
            for title in titles { if let m = TutorialLocator.find(title, in: words, region: region) { return labelled(m) } }
            return nil
        case .ribbonTab(let name):
            let prefs = AppPreferences.shared
            let current = UserDefaults.standard.string(forKey: "ribbonTab") ?? RibbonTab.home.rawValue
            let tabs = RibbonTab.allCases.filter { !prefs.hiddenRibbonTabs.contains($0.rawValue) || $0.rawValue == current }
            let rects = TutorialLocator.controls(in: w, region: CGRect(x: 0, y: H - 64, width: W, height: 40), width: 30...200, height: 20...32)
            if rects.count == tabs.count, let i = tabs.firstIndex(where: { $0.rawValue.lowercased() == name.lowercased() }) { return at(rects[i]) }
            let words = TutorialLocator.words(in: w)
            return TutorialLocator.find(L10n.t(name), in: words, region: CGRect(x: 0, y: H - 64, width: W, height: 40)).map(labelled)
        case .mode(let m):
            let rects = TutorialLocator.controls(in: w, region: CGRect(x: ws.minX, y: ws.maxY - 40, width: 320, height: 40), height: 10...26)
            if rects.count >= WorkspaceMode.allCases.count, let i = WorkspaceMode.allCases.firstIndex(where: { $0.rawValue.lowercased() == m.lowercased() }) { return at(rects[i]) }
            return nil
        case .panel(let name):
            guard model.showPanels else { return nil }
            let tabs = PanelTab.allCases.filter { !FloatingPanels.floatingTabs(model).contains($0) }
            let rects = TutorialLocator.controls(in: w, region: CGRect(x: ws.maxX, y: ws.maxY - 150, width: W - ws.maxX, height: 152), width: 16...60, height: 26...48)
            if rects.count == tabs.count, let i = tabs.firstIndex(where: { $0.rawValue.lowercased() == name.lowercased() }) { return at(rects[i]) }
            let words = TutorialLocator.words(in: w)
            return TutorialLocator.find(name, in: words, region: CGRect(x: ws.maxX, y: ws.maxY - 150, width: W - ws.maxX, height: 152)).map(labelled)
        case .statusBar(let name):
            let words = TutorialLocator.words(in: w)
            return TutorialLocator.find(name, in: words, region: CGRect(x: 0, y: 0, width: W, height: 30)).map(labelled)
        case .commandLine:
            let y = ws.minY - 50
            let p = CGPoint(x: min(260, W * 0.2), y: max(30, min(y, 90)))
            return Hit(point: p) { [weak model] in model?.focusCommandLine(); return true }
        case .button(let label, let win):
            var wins = NSApp.orderedWindows.filter { $0 !== w && $0.isVisible && $0.frame.intersects(w.frame) } + [w]
            if let win { wins = NSApp.orderedWindows.filter { $0.isVisible && $0.title.lowercased().hasPrefix(win.lowercased()) } }
            for x in wins {
                // Not the window title ("Render — Cedar House").
                let body = CGRect(x: 0, y: 0, width: x.frame.width, height: x.contentLayoutRect.maxY)
                guard let m = TutorialLocator.find(label, in: TutorialLocator.words(in: x), region: body) else { continue }
                let r = TutorialLocator.control(for: m, in: x) ?? m.rect
                let local = CGPoint(x: r.midX, y: r.midY)
                let p = CGPoint(x: local.x + x.frame.minX - w.frame.minX, y: local.y + x.frame.minY - w.frame.minY)
                return Hit(point: p, window: x, local: local)
            }
            return nil
        }
    }

    /// Dry runs do not read the screen: targets resolve to their actions.
    private func dryHit(_ t: TutorialTarget) -> Hit? {
        _ = t
        return Hit(point: overlay.cursor) { false }
    }

    /// A fingerprint of what a button can change (document, file, dialogs, windows, view), to tell whether a click worked.
    private func uiState() -> String {
        let d = model.doc
        let wins = NSApp.windows.filter(\.isVisible).count
        return "\(model.editor.fileURL?.path ?? "")|\(d.entities.count)|\(d.elements.count)|\(model.showStart)|\(model.sheet?.id ?? "")|\(wins)|\(model.mode.rawValue)|\(model.panelTab.rawValue)|\(model.showPanels)|\(d.layouts.count)|\(model.editor.activeCommand?.name ?? "")|\(model.commandLog.count)|\(UserDefaults.standard.string(forKey: "ribbonTab") ?? "")"
    }

    /// Whether pressing a target had its effect (otherwise the recorder performs the action directly).
    private func verify(_ t: TutorialTarget, logFrom: Int, stateBefore: String = "") -> Bool {
        switch t {
        case .ribbon(let c):
            let name = CommandRegistry.shared.lookup(c)?.name ?? c
            return model.editor.activeCommand?.name == name || model.commandLog.dropFirst(logFrom).contains { $0 == "Command: \(name)" }
        case .ribbonTab(let n): return UserDefaults.standard.string(forKey: "ribbonTab")?.lowercased() == n.lowercased()
        case .mode(let m): return model.mode.rawValue.lowercased() == m.lowercased()
        case .panel(let n): return model.showPanels && model.panelTab.rawValue.lowercased() == n.lowercased()
        case .button, .statusBar: return uiState() != stateBefore
        case .commandLine: return true
        }
    }

    /// Ribbon titles of a command (English and the UI language).
    static func ribbonTitles(_ cmd: String) -> Set<String> {
        let c = cmd.uppercased()
        let def = CommandRegistry.shared.lookup(c)
        let items = CommandCatalog.allItems.filter { item in item.names.contains(c) || (def.map { d in item.names.contains(d.name) } ?? false) }
        return Set(items.map(\.title) + items.map { L10n.t($0.title) })
    }

    /// The ribbon tab that shows a command's button, found by looking at each tab without recording frames.
    private func ribbonTab(for cmd: String) async -> String? {
        if let t = ribbonTabCache[cmd] { return t }
        guard let w = window, !options.dryRun else { return nil }
        let titles = TutorialRecorder.ribbonTitles(cmd)
        guard !titles.isEmpty else { return nil }
        let original = UserDefaults.standard.string(forKey: "ribbonTab") ?? RibbonTab.home.rawValue
        let top = (lastWorkspace ?? workspaceRect())?.maxY ?? w.frame.height - 150
        let region = CGRect(x: 0, y: top, width: w.frame.width, height: w.frame.height - 60 - top)
        func present() -> Bool {
            TutorialCapture.fullRedraw = true
            let ws = TutorialLocator.words(in: w)
            return titles.contains { TutorialLocator.find($0, in: ws, region: region) != nil }
        }
        var found: String?
        if present() { found = original } else {
            for tab in RibbonTab.allCases {
                UserDefaults.standard.set(tab.rawValue, forKey: "ribbonTab")
                await settle(2)
                if present() { found = tab.rawValue; break }
            }
            UserDefaults.standard.set(original, forKey: "ribbonTab")
            await settle(2)
        }
        if let f = found { ribbonTabCache[cmd] = f }
        return found
    }

    // MARK: Views

    private func zoom(_ z: String) async {
        let parts = z.split(separator: " ").map(String.init)
        if model.mode == .model {
            if parts.first == "extents" { model.zoomExtents() }
            await frames(seconds: 0.8)
            return
        }
        guard let c = model.canvas, c.window != nil else { problem("zoom needs the 2D plan"); return }
        func visible() -> CGRect {
            let a = c.toWorld(CGPoint(x: c.bounds.minX, y: c.bounds.minY)), b = c.toWorld(CGPoint(x: c.bounds.maxX, y: c.bounds.maxY))
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        }
        let from = visible()
        var to = from
        switch parts.first ?? "" {
        case "extents":
            c.zoomExtents()
            to = visible()
            c.zoom(toRect: from, margin: 0, recordHistory: false)
        case "in", "out":
            let f: CGFloat = parts[0] == "in" ? 1 / 1.8 : 1.8
            to = CGRect(x: from.midX - from.width * f / 2, y: from.midY - from.height * f / 2, width: from.width * f, height: from.height * f)
        case "window":
            guard parts.count == 3, let a = TutorialScript.point(parts[1]), let b = TutorialScript.point(parts[2]) else { return }
            to = CGRect(x: min(a.0, b.0), y: min(a.1, b.1), width: abs(b.0 - a.0), height: abs(b.1 - a.1))
        default:
            if let f = Double(parts[0]), f > 0 {
                let k = CGFloat(1 / f)
                to = CGRect(x: from.midX - from.width * k / 2, y: from.midY - from.height * k / 2, width: from.width * k, height: from.height * k)
            }
        }
        guard to.width > 0, to.height > 0 else { return }
        await frames(seconds: 0.8) { t in
            let e = CGFloat(t * t * (3 - 2 * t))
            // Interpolate in log scale for the size so zooming feels even.
            let w = exp(log(from.width) + (log(to.width) - log(from.width)) * e), h = exp(log(from.height) + (log(to.height) - log(from.height)) * e)
            let cx = from.midX + (to.midX - from.midX) * e, cy = from.midY + (to.midY - from.midY) * e
            c.zoom(toRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), margin: 0, recordHistory: t >= 1)
        }
        await frames(seconds: 0.2)
    }

    private func orbit(_ degrees: Double, _ seconds: Double) async {
        if model.mode == .plan || model.mode == .sheet { model.mode = .model; await settle(6) }
        guard let vc = model.viewport3D, let v = vc.view else { problem("orbit needs the 3D view"); return }
        let r = v.convert(v.bounds, to: nil)
        let startP = CGPoint(x: r.midX - r.width * 0.12 * CGFloat(degrees >= 0 ? 1 : -1), y: r.midY)
        await moveCursor(to: startP)
        overlay.pressed = true
        let start = vc.currentCamera
        let n = max(1, Int(seconds * Double(TutorialTiming.fps)))
        var done = 0
        await frames(seconds: seconds) { t in
            let e = t * t * (3 - 2 * t)
            let a = degrees * e * .pi / 180
            let d = start.eye - start.target
            let eye = Vec3(start.target.x + d.x * cos(a) - d.y * sin(a), start.target.y + d.x * sin(a) + d.y * cos(a), start.eye.z)
            var cam = start; cam.eye = eye
            vc.apply(camera: cam, animated: false)
            self.overlay.cursor = CGPoint(x: startP.x + r.width * 0.24 * CGFloat(e) * CGFloat(degrees >= 0 ? 1 : -1), y: startP.y + CGFloat(sin(e * .pi)) * 12)
            done += 1
        }
        _ = n; _ = done
        overlay.pressed = false
        await frames(seconds: 0.3)
    }
}
