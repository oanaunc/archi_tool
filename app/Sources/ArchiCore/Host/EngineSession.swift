// Oanarina Archi Tool — GPL-3.0-or-later
// The engine session behind archi-engine: one Editor (document, command line, selection, undo) driven by JSON-RPC
// requests from the Windows shell, the way the Mac CommandLineView / CanvasView / AppModel drive it. Commands run on
// the main actor; a request that starts or answers a command returns as soon as the command waits for input (or ends),
// so the shell keeps sending pointer, key and cursor requests while a command is active.
import Foundation

/// Receives the editor's host actions (OPEN, SAVE, EXPORT, ZOOM…) for the session (Editor.host is weak).
final class EngineHostBridge: EditorHost {
    weak var session: EngineSession?
    func perform(_ action: HostAction, editor: Editor) {
        MainActor.assumeIsolated { session?.perform(action) }
    }
}

@MainActor
public final class EngineSession {
    public static let engineVersion = "1.0.0"
    public static let previewColor = RGBA(0.86, 0.88, 0.92)

    public let editor: Editor
    /// Writes one notification line (stdout in archi-engine; a buffer in tests).
    public var emit: (String) -> Void
    /// Relative paths in requests are resolved against this folder.
    public var baseDirectory: URL
    /// Screen pixels per drawing unit of the shell's 2D view (last view.drawList / input.* value): snap and pick apertures.
    public private(set) var pixelsPerUnit: Double = 1
    private let bridge = EngineHostBridge()
    private var changed: [String] = []
    private var flushScheduled = false
    private var inputHistory: [String] = []
    private var historyIndex: Int?
    var drawCache: (count: Int, options: DrawOptions, entries: [DrawEntry])?

    public init(editor: Editor? = nil, emit: @escaping (String) -> Void = { _ in }) {
        self.editor = editor ?? Editor()
        self.emit = emit
        self.baseDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        bridge.session = self
        self.editor.host = bridge
        self.editor.onChange = { [weak self] in self?.markChanged("document") }
        self.editor.onSelectionChange = { [weak self] in self?.markChanged("selection") }
        self.editor.onPromptChange = { [weak self] in self?.markChanged("prompt") }
        self.editor.onSysVarChange = { [weak self] _ in self?.markChanged("sysvars") }
        self.editor.onLog = { [weak self] line in self?.log(line) }
    }

    // MARK: Notifications

    private func log(_ line: String) {
        var o = EngineObject()
        o.set("text", line)
        emit(EngineProtocol.notification("log", o.json))
    }

    func markChanged(_ what: String) {
        if !changed.contains(what) { changed.append(what) }
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in self?.flushNotifications() }
    }

    /// Emits the pending "changed" and "prompt" notifications (coalesced; sent before each response).
    public func flushNotifications() {
        flushScheduled = false
        guard !changed.isEmpty else { return }
        let what = changed
        changed = []
        let others = what.filter { $0 != "prompt" }
        if !others.isEmpty {
            var o = EngineObject()
            o.set("what", EngineJSON.strings(others))
            emit(EngineProtocol.notification("changed", o.json))
        }
        if what.contains("prompt") { emit(EngineProtocol.notification("prompt", promptObject().json)) }
    }

    func hostNotify(_ action: String, _ extra: EngineObject = EngineObject()) {
        var o = EngineObject()
        o.set("action", action)
        for f in extra.fields { o.set(f.key, f.value) }
        emit(EngineProtocol.notification("host", o.json))
    }

    // MARK: Request handling

    /// Handles one request line; returns the response line (nil for client notifications and blank lines).
    public func handle(line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let msg: EngineJSON
        do { msg = try EngineJSON.parse(trimmed) } catch {
            let m = (error as? EngineJSON.ParseError)?.message ?? "invalid JSON"
            return EngineProtocol.errorResponse(id: .null, EngineError(EngineError.parseError, "Parse error: " + m))
        }
        let id = msg["id"]
        guard msg.fields != nil, let method = msg["method"]?.stringValue else {
            return EngineProtocol.errorResponse(id: id ?? .null, EngineError(EngineError.invalidRequest, "Invalid request: missing method"))
        }
        let params = msg["params"] ?? .object([])
        do {
            let result = try await call(method, params)
            flushNotifications()
            guard let id else { return nil }
            return EngineProtocol.response(id: id, result: result)
        } catch let e as EngineError {
            flushNotifications()
            return id.map { EngineProtocol.errorResponse(id: $0, e) }
        } catch {
            flushNotifications()
            return id.map { EngineProtocol.errorResponse(id: $0, EngineError.failed(EngineSession.describe(error))) }
        }
    }

    static func describe(_ error: Error) -> String {
        if let l = error as? LocalizedError, let d = l.errorDescription { return d }
        return String(describing: error)
    }

    /// Runs one method (also used directly by tests).
    public func call(_ method: String, _ params: EngineJSON = .object([])) async throws -> EngineJSON {
        switch method {
        case "engine.hello": return hello()
        case "engine.log": return logTail(params)
        case "doc.new": return try await newDocument(params)
        case "doc.open": return try await openDocument(params)
        case "doc.save": return try saveDocument(params)
        case "doc.info": return docInfo()
        case "command.run": return try await commandRun(params)
        case "command.complete": return complete(params["prefix"]?.stringValue ?? params["text"]?.stringValue ?? "")
        case "input.text": return try await inputText(params)
        case "input.point": return try await inputPoint(params)
        case "input.key": return try await inputKey(params)
        case "input.cursor": return try inputCursor(params)
        case "view.drawList": return try drawList(params)
        case "pick": return try await pick(params)
        case "select.window": return try await selectWindow(params)
        case "select.set": return try selectSet(params)
        case "select.get": return selectionResult().json
        case "grips.get": return gripsJSON()
        case "grips.drag": return try gripsDrag(params)
        case "model.meshes": return try meshes(params)
        case "render.settings": return renderSettings()
        case "render.preset": return try renderPreset(params)
        case "panel.layers": return panelLayers()
        case "panel.levels": return panelLevels()
        case "panel.properties": return panelProperties()
        case "panel.materials": return panelMaterials()
        case "panel.sheets": return panelSheets()
        case "panel.history": return panelHistory(params)
        case "panel.set": return try panelSet(params)
        case "edit.undo": return await undoRedo(redo: false)
        case "edit.redo": return await undoRedo(redo: true)
        case "sysvar.get": return try sysvarGet(params)
        case "sysvar.set": return try sysvarSet(params)
        case "file.export": return try fileExport(params)
        case "file.import": return try fileImport(params)
        case let m where EngineDialogMethods.all.contains(m): return try await dialogCall(m, params)
        case let m where EngineView3DMethods.all.contains(m): return try await view3dCall(m, params)
        default:
            if let r = try await callCanvas(method, params) { return r }
            if let r = try await callOutput(method, params) { return r }
            if let r = try await callRenderExtras(method, params) { return r }
            if let r = try await callUI(method, params) { return r }
            if let r = try await callDocTools(method, params) { return r }
            if let r = try await callSheets(method, params) { return r }
            if let r = try await callWorkspace(method, params) { return r }
            if let r = try await callStandards(method, params) { return r }
            throw EngineError(EngineError.methodNotFound, "Method not found: " + method)
        }
    }

    // MARK: Helpers

    func string(_ p: EngineJSON, _ key: String) throws -> String {
        guard let s = p[key]?.stringValue else { throw EngineError.params("missing '\(key)'") }
        return s
    }
    func number(_ p: EngineJSON, _ key: String) throws -> Double {
        guard let d = p[key]?.doubleValue, d.isFinite else { throw EngineError.params("missing number '\(key)'") }
        return d
    }

    /// Absolute or relative (to `baseDirectory`) path, with ~ expanded.
    public func url(_ path: String) -> URL {
        let p = (path as NSString).expandingTildeInPath
        let chars = Array(p)
        let absolute = p.hasPrefix("/") || p.hasPrefix("\\") || (chars.count > 1 && chars[1] == ":")
        return absolute ? URL(fileURLWithPath: p) : baseDirectory.appendingPathComponent(p)
    }

    /// Lets the running command reach its next prompt (or finish).
    func settle() async {
        await editor.waitForInputOrIdle()
        await Task.yield()
    }

    /// Cancels a running command and waits for it to unwind (as the Mac AppModel.runCommand does).
    func cancelAndWait() async {
        guard !editor.isIdle else { return }
        editor.cancel()
        var n = 0
        while !editor.isIdle && n < 200 { await Task.yield(); n += 1 }
    }

    func updatePixels(_ p: EngineJSON) {
        if let ppu = p["pixelsPerUnit"]?.doubleValue, ppu > 0, ppu.isFinite {
            pixelsPerUnit = ppu
            editor.pickTolerance = 6 / ppu
        }
    }

    static func kindNames(_ req: InputRequest?) -> [String] {
        guard let k = req?.kinds else { return [] }
        let order: [(InputRequest.Kind, String)] = [(.point, "point"), (.distance, "distance"), (.angle, "angle"), (.integer, "integer"),
                                                    (.string, "string"), (.selection, "selection"), (.entity, "entity"), (.keyword, "keyword")]
        return order.filter { k.contains($0.0) }.map { $0.1 }
    }

    // MARK: Prompt state

    /// Rubber-band preview of the active prompt at a cursor point (the Mac canvas preview).
    func previewItems(at cursor: Vec2?) -> EngineJSON {
        guard let req = editor.request, let pv = req.preview, let c = cursor else { return .array([]) }
        guard !req.kinds.isDisjoint(with: [.point, .distance, .angle]) else { return .array([]) }
        let geoms = pv(c)
        if geoms.isEmpty { return .array([]) }
        return EngineDrawJSON.items(DrawListBuilder.previewItems(geoms, doc: editor.doc, color: EngineSession.previewColor))
    }

    public func promptObject(cursor: Vec2? = nil) -> EngineObject {
        let req = editor.request
        var o = EngineObject()
        o.set("active", !editor.isIdle)
        if let c = editor.activeCommand { o.set("command", c.name) }
        if let t = editor.transparentCommand { o.set("transparent", t.name) }
        o.set("message", editor.promptText)
        o.set("label", req?.message ?? "Command")
        o.set("keywords", EngineJSON.strings(req?.keywords ?? []))
        o.set("kinds", EngineJSON.strings(EngineSession.kindNames(req)))
        if let d = req?.defaultValue { o.set("defaultValue", d) }
        if let b = req?.base { o.set("base", EngineJSON.point(b)) }
        if req?.rotatable == true { o.set("rotatable", true) }
        o.set("preview", previewItems(at: cursor ?? editor.cursor))
        return o
    }

    public func promptState() -> EngineJSON { promptObject().json }

    // MARK: engine / doc

    func hello() -> EngineJSON {
        var cmds: [EngineJSON] = []
        for c in editor.registry.sorted {
            var o = EngineObject()
            o.set("name", c.name)
            o.set("aliases", EngineJSON.strings(c.aliases))
            o.set("category", c.category)
            o.set("summary", c.summary)
            o.set("modifies", c.modifies)
            cmds.append(o.json)
        }
        var vars: [EngineJSON] = []
        for v in SysVarCatalog.all {
            var o = EngineObject()
            o.set("name", v.name)
            o.set("kind", v.kind.rawValue)
            o.set("default", v.defaultValue)
            if !v.range.isEmpty { o.set("range", v.range) }
            if v.readOnly { o.set("readOnly", true) }
            o.set("summary", v.summary)
            vars.append(o.json)
        }
        var o = EngineObject()
        o.set("name", "archi-engine")
        o.set("version", EngineSession.engineVersion)
        o.set("protocol", EngineProtocol.version)
        #if os(Windows)
        o.set("platform", "windows")
        #elseif os(Linux)
        o.set("platform", "linux")
        #else
        o.set("platform", "macos")
        #endif
        o.set("methods", EngineJSON.strings(EngineProtocol.methods + EngineStandardsMethods.all))
        o.set("commands", EngineJSON.array(cmds))
        o.set("sysvars", EngineJSON.array(vars))
        return o.json
    }

    func logTail(_ p: EngineJSON) -> EngineJSON {
        let n = max(1, min(p["limit"]?.intValue ?? 200, 5000))
        return .object([EngineJSONField("lines", EngineJSON.strings(Array(editor.log.suffix(n))))])
    }

    /// Resolves a level given by id, name or "all" (nil = all levels). Absent = the current level.
    func level(_ v: EngineJSON?) throws -> Int? {
        guard let v, !v.isNull else { return editor.doc.currentLevel }
        if case .number = v, let i = v.intValue {
            guard editor.doc.level(i) != nil else { throw EngineError.params("no level \(i)") }
            return i
        }
        let s = v.stringValue ?? ""
        if s.lowercased() == "all" { return nil }
        if let l = editor.doc.levels.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return l.id }
        if let i = Int(s), editor.doc.level(i) != nil { return i }
        throw EngineError.params("no level named '\(s)'")
    }

    func entries(_ options: DrawOptions) -> [DrawEntry] {
        if let c = drawCache, c.count == editor.changeCount, c.options == options { return c.entries }
        let e = DrawListBuilder.entries(doc: editor.doc, options: options)
        drawCache = (editor.changeCount, options, e)
        return e
    }

    /// Plan extents of the current level (as ZOOM Extents frames them).
    func extents() -> BBox2 {
        entries(DrawOptions(level: editor.doc.currentLevel)).reduce(BBox2.empty) { $0.union($1.bounds) }
    }

    func docInfo() -> EngineJSON {
        let doc = editor.doc
        var o = EngineObject()
        let title = editor.fileURL.map { $0.deletingPathExtension().lastPathComponent } ?? "Untitled"
        o.set("title", title)
        o.set("path", EngineJSON.optString(editor.fileURL?.path))
        o.set("dirty", editor.isDirty)
        o.set("units", doc.units.rawValue)
        o.set("unitAbbreviation", doc.units.abbreviation)
        var levels: [EngineJSON] = []
        for l in doc.levels {
            var lo = EngineObject()
            lo.set("id", l.id)
            lo.set("name", l.name)
            lo.set("elevation", l.elevation)
            lo.set("height", l.height)
            levels.append(lo.json)
        }
        o.set("levels", EngineJSON.array(levels))
        o.set("currentLevel", doc.level(doc.currentLevel)?.name ?? "")
        o.set("currentLevelId", doc.currentLevel)
        o.set("layouts", EngineJSON.strings(doc.layouts.map(\.name)))
        let b = extents()
        o.set("extents", b.isEmpty ? EngineJSON.numbers([0, 0, 10000, 10000]) : EngineDrawJSON.rect(b))
        o.set("empty", b.isEmpty)
        o.set("project", doc.info.name)
        o.set("currentLayer", doc.currentLayer)
        o.set("entities", doc.entities.count)
        o.set("elements", doc.elements.count)
        o.set("canUndo", editor.history.canUndo)
        o.set("canRedo", editor.history.canRedo)
        return o.json
    }

    func newDocument(_ p: EngineJSON) async throws -> EngineJSON {
        await cancelAndWait()
        var d = ArchiDocument()
        var settings: DraftSettings? = nil
        if let t = p["template"]?.stringValue, !t.isEmpty {
            if let (td, ts) = EngineTemplates.make(t) {
                d = td
                settings = ts
            } else {
                let loaded = try ArchiTemplate.decode(Data(contentsOf: url(t)))
                d = ArchiTemplate.newDocument(from: loaded.document)
            }
        }
        editor.replaceDocument(d, url: nil)
        if let settings { editor.settings = settings }
        drawCache = nil
        return docInfo()
    }

    static let nativeExtensions: Set<String> = ["archi", "archiz", "archit", "json"]

    func open(_ u: URL) throws {
        guard FileManager.default.fileExists(atPath: u.path) else { throw EngineError.failed("File not found: " + u.path) }
        let d = try DocumentIO.read(u)
        editor.replaceDocument(d, url: EngineSession.nativeExtensions.contains(u.pathExtension.lowercased()) ? u : nil)
        drawCache = nil
    }

    func openDocument(_ p: EngineJSON) async throws -> EngineJSON {
        let path = try string(p, "path")
        await cancelAndWait()
        try open(url(path))
        return docInfo()
    }

    func save(to target: URL, format: String?) throws {
        var u = target
        if u.pathExtension.isEmpty && format == nil { u = u.appendingPathExtension("archi") }
        let f = (format ?? u.pathExtension).lowercased()
        try DocumentIO.write(editor.doc, to: u, format: f)
        if EngineSession.nativeExtensions.contains(f) { editor.fileURL = u; editor.isDirty = false }
        if f == ArchiFile.fileExtension { afterNativeSave(u) }
        markChanged("document")
    }

    func saveDocument(_ p: EngineJSON) throws -> EngineJSON {
        let target: URL
        if let path = p["path"]?.stringValue, !path.isEmpty { target = url(path) }
        else if let u = editor.fileURL { target = u }
        else { throw EngineError.failed("The drawing has no file yet: pass 'path'.") }
        try save(to: target, format: p["format"]?.stringValue)
        return docInfo()
    }

    // MARK: Host actions (commands asking the UI)

    func perform(_ action: HostAction) {
        do {
            switch action {
            case .open(let p):
                if let p { try open(url(p)); editor.print("Opened " + url(p).path) } else { hostNotify("open") }
            case .save(let p):
                if let u = p.map({ url($0) }) ?? editor.fileURL { try save(to: u, format: nil); editor.print("Saved " + (editor.fileURL?.path ?? u.path)) }
                else { hostNotify("saveAs") }
            case .saveAs(let p):
                if let p { try save(to: url(p), format: nil); editor.print("Saved " + url(p).path) } else { hostNotify("saveAs") }
            case .newDocument:
                editor.replaceDocument(ArchiDocument(), url: nil)
            case .export(let format, let p):
                if let p, format.lowercased() == "pdf" {
                    // EXPORT <file.pdf>: the plot of the shown sheet or the current level, as FileController.export does on the Mac.
                    var o = EngineObject()
                    o.set("path", p); o.set("quiet", true)
                    if let li = activeSheetIndex { o.set("layout", li) } else { o.set("what", "model") }
                    _ = try plotPDF(o.json)
                    editor.print("Exported PDF to " + url(p).path)
                }
                else if let p { try DocumentIO.write(editor.doc, to: url(p), format: format, level: editor.doc.currentLevel); editor.print("Exported " + url(p).path) }
                else { var o = EngineObject(); o.set("format", format); hostNotify("export", o) }
            case .plot(let p):
                // Same plot as the Plot dialog and the Mac PLOT <file>: the shown sheet (CTAB) or the current level (EngineOutput.swift).
                if let p { try plotToFile(p) }
                else { hostNotify("plot") }
            case .importFile(let p):
                if let p { _ = try importFile(url(p), format: nil, offset: .zero) } else { hostNotify("import") }
            case .message(let m):
                editor.print(m)
            case .zoomExtents: hostNotify("zoomExtents")
            case .zoomWindow(let b): var o = EngineObject(); o.set("rect", EngineDrawJSON.rect(b)); hostNotify("zoomWindow", o)
            case .zoomScale(let s): var o = EngineObject(); o.set("scale", s); hostNotify("zoomScale", o)
            case .pan(let v): var o = EngineObject(); o.set("delta", EngineJSON.point(v)); hostNotify("pan", o)
            case .regen: drawCache = nil; hostNotify("regen")
            case .show2D: hostNotify("show2D")
            case .show3D: hostNotify("show3D")
            case .showSplit: hostNotify("showSplit")
            case .render: hostNotify("render")
            case .walkthrough: hostNotify("walkthrough")
            case .showPanel(let n): var o = EngineObject(); o.set("panel", n); hostNotify("showPanel", o)
            case .setViewStyle(let s): view3dStyleChanged(s); var o = EngineObject(); o.set("style", s); hostNotify("setViewStyle", o)
            case .setView(let s): var o = EngineObject(); o.set("view", s); hostNotify("setView", o)
            }
        } catch {
            editor.print("Error: " + EngineSession.describe(error))
        }
    }

    // MARK: Command line and input

    func submit(_ line: String) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { inputHistory.append(t); if inputHistory.count > 200 { inputHistory.removeFirst(50) } }
        historyIndex = nil
        editor.submit(line)
    }

    func commandRun(_ p: EngineJSON) async throws -> EngineJSON {
        let line = try string(p, "line")
        if p["cancel"]?.boolValue == true { await cancelAndWait() }
        submit(line)
        await settle()
        return promptState()
    }

    func inputText(_ p: EngineJSON) async throws -> EngineJSON {
        submit(try string(p, "text"))
        await settle()
        return promptState()
    }

    func complete(_ prefix: String) -> EngineJSON {
        var out: [EngineJSON] = []
        for n in editor.registry.complete(prefix).prefix(12) {
            var o = EngineObject()
            o.set("name", n)
            let def = editor.registry.lookup(n)
            o.set("command", def?.name ?? n)
            o.set("summary", def?.summary ?? "")
            out.append(o.json)
        }
        return .array(out)
    }

    func inputKey(_ p: EngineJSON) async throws -> EngineJSON {
        let key = try string(p, "key").lowercased()
        switch key {
        case "enter", "return", "space":
            submit("")
            await settle()
            return promptState()
        case "escape", "esc":
            if !editor.isIdle { await cancelAndWait() } else if !editor.selection.isEmpty { editor.selection = [] }
            return promptState()
        case "tab":
            let c = complete(p["text"]?.stringValue ?? "")
            var o = promptObject()
            o.set("completions", c)
            if let first = c[0]?["name"] { o.set("text", first) }
            return o.json
        case "up", "down":
            var o = promptObject()
            let h = inputHistory
            if key == "up" {
                if !h.isEmpty { let i = max(0, (historyIndex ?? h.count) - 1); historyIndex = i; o.set("text", h[i]) }
            } else if let cur = historyIndex {
                if cur + 1 < h.count { historyIndex = cur + 1; o.set("text", h[cur + 1]) } else { historyIndex = nil; o.set("text", "") }
            }
            return o.json
        default:
            throw EngineError.params("unknown key '\(key)' (Enter, Escape, Space, Tab, Up, Down)")
        }
    }

    /// Resolves a raw cursor point like the Mac canvas: running object snaps, grid snap, ortho/polar from the base point.
    public func resolveCursor(_ raw: Vec2) -> (point: Vec2, snap: SnapResult?) {
        guard let req = editor.request, req.kinds.contains(.point) else { return (raw, nil) }
        let s = editor.settings
        let tol = 10 / pixelsPerUnit
        if s.objectSnap, let r = Snap.find(cursor: raw, doc: editor.doc, settings: s, tolerance: tol, base: req.base) { return (r.point, r) }
        var p = raw
        if s.gridSnap, s.gridSpacing > 0 {
            let g = s.gridSpacing
            p = Vec2((p.x / g).rounded() * g, (p.y / g).rounded() * g)
        }
        if let b = req.base { p = Snap.constrain(base: b, cursor: p, settings: s) }
        return (p, nil)
    }

    func rawPoint(_ p: EngineJSON) throws -> Vec2 { Vec2(try number(p, "x"), try number(p, "y")) }

    func inputPoint(_ p: EngineJSON) async throws -> EngineJSON {
        updatePixels(p)
        let raw = try rawPoint(p)
        let pt = p["snap"]?.boolValue == false ? raw : resolveCursor(raw).point
        editor.cursor = pt
        if let req = editor.request {
            if req.kinds.contains(.point) {
                editor.feed(.point(pt))
            } else if !req.kinds.isDisjoint(with: [.selection, .entity]), let id = editor.pick(at: raw, tolerance: editor.pickTolerance) {
                editor.feed(.selection(req.kinds.contains(.selection) ? editor.expandGroups([id]) : [id]))
            }
        } else if editor.isIdle, let id = editor.pick(at: raw, tolerance: editor.pickTolerance) {
            editor.selection.formUnion(editor.expandGroups([id]))
        }
        await settle()
        return promptState()
    }

    func inputCursor(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        let raw = try rawPoint(p)
        let r = resolveCursor(raw)
        editor.cursor = r.point
        var o = promptObject(cursor: r.point)
        o.set("cursor", EngineJSON.point(r.point))
        if let s = r.snap {
            var so = EngineObject()
            so.set("kind", s.kind.rawValue)
            so.set("point", EngineJSON.point(s.point))
            if let e = s.entity { so.set("entity", e) }
            o.set("snap", so.json)
        } else {
            o.set("snap", EngineJSON.null)
        }
        let req = editor.request
        let wantsPick = editor.isIdle || (req.map { !$0.kinds.isDisjoint(with: [.selection, .entity]) && !$0.kinds.contains(.point) } ?? false)
        let hover = wantsPick ? editor.pick(at: raw, tolerance: editor.pickTolerance) : nil
        o.set("hover", hover.map { EngineJSON.int($0) } ?? .null)
        canvasCursorExtras(&o, point: r.point)
        return o.json
    }

    // MARK: Selection

    func summary(_ ids: [EntityID]) -> (text: String, types: EngineJSON) {
        let doc = editor.doc
        var counts: [String: Int] = [:]
        for id in ids {
            let t = doc.entity(id)?.typeName ?? doc.element(id)?.typeName ?? "object"
            counts[t, default: 0] += 1
        }
        let sorted = counts.sorted { $0.key < $1.key }
        var types: [EngineJSON] = []
        for (k, v) in sorted { types.append(.object([EngineJSONField("type", .string(k)), EngineJSONField("count", .int(v))])) }
        if ids.isEmpty { return ("No selection", .array([])) }
        if ids.count == 1, let only = sorted.first { return ("1 object: " + only.key, .array(types)) }
        let parts = sorted.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        return ("\(ids.count) objects: " + parts, .array(types))
    }

    func selectionResult(hit: EntityID? = nil) -> EngineObject {
        let ids = editor.selection.sorted()
        let s = summary(ids)
        var o = EngineObject()
        o.set("ids", EngineJSON.ints(ids))
        o.set("summary", s.text)
        o.set("types", s.types)
        if let hit { o.set("hit", hit) }
        o.set("prompt", promptState())
        return o
    }

    func pick(_ p: EngineJSON) async throws -> EngineJSON {
        updatePixels(p)
        let pt = try rawPoint(p)
        let tol = p["tolerance"]?.doubleValue ?? editor.pickTolerance
        let hit = editor.pick(at: pt, tolerance: tol)
        if let req = editor.request, !req.kinds.isDisjoint(with: [.selection, .entity]) {
            if let id = hit { editor.feed(.selection(req.kinds.contains(.selection) ? editor.expandGroups([id]) : [id])) }
            await settle()
            return selectionResult(hit: hit).json
        }
        let add = p["add"]?.boolValue ?? true
        let toggle = p["toggle"]?.boolValue ?? false
        if let id = hit {
            let ids = Set(editor.expandGroups([id]))
            if toggle {
                if editor.selection.contains(id) { editor.selection.subtract(ids) } else { editor.selection.formUnion(ids) }
            } else if add {
                editor.selection.formUnion(ids)
            } else {
                editor.selection = ids
            }
        } else if !add && !toggle {
            editor.selection = []
        }
        return selectionResult(hit: hit).json
    }

    func selectWindow(_ p: EngineJSON) async throws -> EngineJSON {
        let a = Vec2(try number(p, "x0"), try number(p, "y0")), b = Vec2(try number(p, "x1"), try number(p, "y1"))
        let crossing = p["crossing"]?.boolValue ?? (b.x < a.x)
        let ids = editor.expandGroups(editor.select(in: BBox2(points: [a, b]), crossing: crossing))
        if let req = editor.request, req.kinds.contains(.selection) {
            editor.feed(.selection(ids))
            await settle()
            return selectionResult().json
        }
        if p["remove"]?.boolValue == true { editor.selection.subtract(ids) }
        else if p["add"]?.boolValue == false { editor.selection = Set(ids) }
        else { editor.selection.formUnion(ids) }
        return selectionResult().json
    }

    func selectSet(_ p: EngineJSON) throws -> EngineJSON {
        guard let a = p["ids"]?.arrayValue else { throw EngineError.params("missing 'ids'") }
        let ids = a.compactMap(\.intValue).filter { editor.doc.entity($0) != nil || editor.doc.element($0) != nil }
        editor.selection = Set(ids)
        return selectionResult().json
    }

    // MARK: Grips

    func gripsJSON() -> EngineJSON {
        var out: [EngineJSON] = []
        for g in editor.selectionGrips() {
            var o = EngineObject()
            o.set("id", g.id)
            o.set("index", g.index)
            o.set("x", g.point.x)
            o.set("y", g.point.y)
            o.set("kind", g.kind?.rawValue ?? "element")
            out.append(o.json)
        }
        return .array(out)
    }

    func gripsDrag(_ p: EngineJSON) throws -> EngineJSON {
        guard let id = p["id"]?.intValue, let index = p["index"]?.intValue else { throw EngineError.params("missing 'id' / 'index'") }
        let to = try rawPoint(p)
        let pts = editor.objectGrips(id)
        guard pts.indices.contains(index) else { throw EngineError.params("object \(id) has no grip \(index)") }
        let mode = p["mode"]?.stringValue.flatMap { GripMode.keyword($0) } ?? .stretch
        let changedIDs = editor.gripEdit(id, index: index, from: pts[index], to: to, mode: mode, copy: p["copy"]?.boolValue ?? false,
                                         snap: p["snap"]?.boolValue ?? true)
        var o = EngineObject()
        o.set("changed", EngineJSON.ints(changedIDs))
        o.set("grips", gripsJSON())
        return o.json
    }

    // MARK: 2D view

    func drawOptions(_ p: EngineJSON) throws -> DrawOptions {
        var opts = DrawOptions(level: try level(p["level"]))
        if let o = p["options"] {
            if let v = o["showElements"]?.boolValue { opts.showElements = v }
            if let v = o["showAnnotations"]?.boolValue { opts.showAnnotations = v }
            if let v = o["forPaper"]?.boolValue { opts.forPaper = v }
            if let v = o["cutHatches"]?.boolValue { opts.cutHatches = v }
            if let v = o["reflectedCeiling"]?.boolValue { opts.reflectedCeiling = v }
            if let v = o["showCeilings"]?.boolValue { opts.showCeilings = v }
            if let v = o["linetypeScale"]?.doubleValue, v > 0 { opts.linetypeScale = v }
        }
        return opts
    }

    func rect(_ v: EngineJSON?) -> BBox2? {
        guard let a = v?.arrayValue, a.count == 4 else { return nil }
        let n = a.compactMap(\.doubleValue)
        guard n.count == 4 else { return nil }
        return BBox2(points: [Vec2(n[0], n[1]), Vec2(n[2], n[3])])
    }

    func drawList(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        let visible = rect(p["rect"])
        if let lay = p["layout"], !lay.isNull { return try sheetDrawList(lay, visible: visible) }
        if let v = visible { EngineSession.lastDisplayBoxes[ObjectIdentifier(self)] = v }
        let opts = try drawOptions(p)
        let es = entries(opts)
        let formats = EngineDrawJSON.textFormats(editor.doc.entities)
        var items: [EngineJSON] = []
        var all = BBox2.empty
        for e in es {
            all.add(e.bounds)
            if let v = visible, !e.bounds.isEmpty, !v.intersects(e.bounds) { continue }
            let f = e.id.flatMap { formats[$0] }
            for it in e.items { items.append(EngineDrawJSON.item(it, id: e.id, format: f)) }
        }
        var o = EngineObject()
        o.set("items", EngineJSON.array(items))
        o.set("count", items.count)
        o.set("bounds", all.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(all))
        o.set("level", opts.level.map { EngineJSON.int($0) } ?? .string("all"))
        o.set("selection", EngineJSON.ints(editor.selection.sorted()))
        var g = EngineObject()
        g.set("show", editor.settings.showGrid)
        g.set("spacing", editor.settings.gridSpacing)
        o.set("grid", g.json)
        return o.json
    }

    func layoutIndex(_ v: EngineJSON) throws -> Int {
        let ls = editor.doc.layouts
        if case .number = v, let i = v.intValue, ls.indices.contains(i) { return i }
        let s = v.stringValue ?? ""
        if let i = ls.firstIndex(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return i }
        throw EngineError.params("no layout named '\(s)'")
    }

    /// A sheet in paper millimetres: viewport contents (clipped to the viewport), then paper-space annotation.
    func sheetDrawList(_ v: EngineJSON, visible: BBox2?) throws -> EngineJSON {
        let li = try layoutIndex(v)
        let doc = editor.doc
        let l = doc.layouts[li]
        var items: [EngineJSON] = []
        var vps: [EngineJSON] = []
        let modelFormats = EngineDrawJSON.textFormats(doc.entities)
        for (i, vp) in l.viewports.enumerated() where vp.size.x > 0 && vp.size.y > 0 && vp.scale > 0 {
            let clip = BBox2(min: vp.origin, max: vp.origin + vp.size)
            var vo = EngineObject()
            vo.set("index", i)
            vo.set("rect", EngineDrawJSON.rect(clip))
            vo.set("scale", vp.scale)
            vo.set("ratio", vp.scale * doc.units.mm)
            vo.set("view", vp.view.rawValue)
            vo.set("level", vp.level.map { EngineJSON.int($0) } ?? .null)
            vo.set("title", vp.title)
            vps.append(vo.json)
            if let vis = visible, !vis.intersects(clip) { continue }
            let center = vp.origin + vp.size / 2
            for e in Presentation.viewportEntries(doc, vp) {
                let f = e.id.flatMap { modelFormats[$0] }
                for it in e.items {
                    let m = EngineDrawJSON.mapped(it, from: vp.viewCenter, scale: vp.scale, to: center)
                    items.append(EngineDrawJSON.item(m, id: e.id, clip: clip, format: f))
                }
            }
        }
        if !l.entities.isEmpty {
            var paper = doc
            paper.entities = l.entities
            paper.elements = []
            var o = DrawOptions(level: nil)
            o.forPaper = true
            let formats = EngineDrawJSON.textFormats(l.entities)
            for e in DrawListBuilder.entries(doc: paper, options: o) {
                let f = e.id.flatMap { formats[$0] }
                for it in e.items { items.append(EngineDrawJSON.item(it, id: e.id, format: f)) }
            }
        }
        var paperObj = EngineObject()
        paperObj.set("name", l.paper.name)
        paperObj.set("width", l.paper.width)
        paperObj.set("height", l.paper.height)
        var tb: [EngineJSONField] = [EngineJSONField("Project", .string(doc.info.name)), EngineJSONField("Sheet", .string(l.name))]
        for (k, val) in l.titleBlock.sorted(by: { $0.key < $1.key }) { tb.append(EngineJSONField(k, .string(val))) }
        var o = EngineObject()
        o.set("layout", l.name)
        o.set("paper", paperObj.json)
        o.set("viewports", EngineJSON.array(vps))
        o.set("titleBlock", EngineJSON.object(tb))
        o.set("items", EngineJSON.array(items))
        o.set("count", items.count)
        return o.json
    }

    // MARK: 3D

    func meshes(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let lv: Int?
        if let v = p["level"], !v.isNull { lv = try level(v) } else { lv = nil }
        let lod = max(0, p["lod"]?.intValue ?? 0)
        var elementLevel: [EntityID: Int] = [:]
        for el in doc.elements { elementLevel[el.id] = el.level }
        let binaryPath = view3dBinaryPath(p["binary"])
        let sink: EngineBinarySink? = binaryPath == nil ? nil : EngineBinarySink()
        var out: [EngineJSON] = []
        var box = BBox3.empty
        for g in MeshBuilder.build(doc: doc) {
            if let l = lv {
                guard let id = g.id, let el = elementLevel[id], el == l else { continue }
            }
            var mesh = g.mesh
            if lod > 0 && mesh.triangleCount > 0 {
                let lg = MeshLOD.build(g)
                mesh = lg.levels[min(lod, lg.levels.count - 1)]
            }
            for q in mesh.positions { box.add(q) }
            out.append(EngineMeshJSON.group(g, mesh: mesh, doc: doc, sink: sink, level: g.id.flatMap { elementLevel[$0] }))
        }
        let look = EngineRenderPresets.look(EngineRenderPresets.current(doc))
        var sun = EngineObject()
        sun.set("azimuth", look.sunAzimuth)
        sun.set("altitude", look.sunAltitude)
        sun.set("direction", EngineJSON.point3(EngineRenderPresets.sunDirection(altitude: look.sunAltitude, azimuth: look.sunAzimuth, northAngleDegrees: doc.info.northAngle)))
        sun.set("preset", look.preset)
        var o = EngineObject()
        o.set("meshes", EngineJSON.array(out))
        o.set("lights", EngineMeshJSON.lights(doc))
        o.set("sun", sun.json)
        o.set("units", doc.units.rawValue)
        o.set("bounds", box.isEmpty ? EngineJSON.null : EngineJSON.array([EngineJSON.point3(box.min), EngineJSON.point3(box.max)]))
        if let path = binaryPath, let sink {
            let u = url(path)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sink.data.write(to: u, options: .atomic)
            o.set("binary", u.path)
            o.set("binaryLength", sink.data.count)
            o.set("layout", EngineMeshJSON.binaryLayout)
        }
        return o.json
    }

    func renderSettings() -> EngineJSON {
        EngineRenderPresets.json(EngineRenderPresets.look(EngineRenderPresets.current(editor.doc)), northAngle: editor.doc.info.northAngle)
    }

    func renderPreset(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard let preset = EngineRenderPresets.named(name) else {
            throw EngineError.params("unknown preset '\(name)' (Daylight, Goldenhour, Overcast, Night)")
        }
        // Same effect as the Mac RENDERPRESET command: one undo step, stored in the drawing.
        if editor.doc.variable(EngineRenderPresets.variable) != preset {
            editor.transaction("RENDERPRESET") { $0.setVariable(EngineRenderPresets.variable, preset) }
        }
        return renderSettings()
    }

    // MARK: Undo, variables, files

    func undoRedo(redo: Bool) async -> EngineJSON {
        await cancelAndWait()
        if redo { editor.redo() } else { editor.undo() }
        return panelHistory(.object([]))
    }

    func sysvarGet(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name").uppercased()
        var o = EngineObject()
        o.set("name", name)
        o.set("value", EngineJSON.optString(SystemVariables.get(name, editor)))
        if let info = SysVarCatalog.info(name) {
            o.set("kind", info.kind.rawValue)
            o.set("readOnly", info.readOnly)
            o.set("summary", info.summary)
        }
        return o.json
    }

    func sysvarSet(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard let value = p["value"]?.stringValue else { throw EngineError.params("missing 'value'") }
        if let err = SystemVariables.set(name, value, editor) { throw EngineError.failed(err) }
        markChanged("sysvars")
        return try sysvarGet(p)
    }

    func fileExport(_ p: EngineJSON) throws -> EngineJSON {
        let u = url(try string(p, "path"))
        let format = p["format"]?.stringValue
        let lv = try level(p["level"])
        let f = (format ?? u.pathExtension).lowercased()
        if f == "png", let dpi = p["dpi"]?.doubleValue, dpi > 0 {
            // Plan image at another resolution than the Mac's 300 dpi (file.export png default).
            try PlanImageExport.write(doc: editor.doc, level: lv, to: u, dpi: dpi, imageBase: u.deletingLastPathComponent())
        } else {
            try DocumentIO.write(editor.doc, to: u, format: format, level: lv)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? (attrs?[.size] as? Int)
        var o = EngineObject()
        o.set("path", u.path)
        o.set("format", (format ?? u.pathExtension).lowercased())
        o.set("bytes", size ?? 0)
        return o.json
    }

    func importFile(_ u: URL, format: String?, offset: Vec2) throws -> EngineJSON {
        guard FileManager.default.fileExists(atPath: u.path) else { throw EngineError.failed("File not found: " + u.path) }
        var result: (DocumentMerge.Result, String)?
        try editor.transaction("Import") { d in result = try FileImport.importFile(u, into: &d, format: format, offset: offset) }
        guard let r = result else { throw EngineError.failed("import failed") }
        editor.print("Imported " + u.lastPathComponent + ": " + r.1)
        var o = EngineObject()
        o.set("summary", r.1)
        o.set("entityIds", EngineJSON.ints(r.0.entityIDs))
        o.set("elementIds", EngineJSON.ints(r.0.elementIDs))
        return o.json
    }

    func fileImport(_ p: EngineJSON) throws -> EngineJSON {
        let u = url(try string(p, "path"))
        return try importFile(u, format: p["format"]?.stringValue, offset: p["offset"]?.vec2 ?? .zero)
    }
}
