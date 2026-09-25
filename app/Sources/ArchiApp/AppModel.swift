// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Which views are visible in the main window.
enum WorkspaceMode: String, CaseIterable, Identifiable { case plan = "2D", model = "3D", split = "Split", sheet = "Sheet"
    var id: String { rawValue } }

/// Side panel tabs.
enum PanelTab: String, CaseIterable, Identifiable {
    case properties = "Properties", layers = "Layers", levels = "Levels", browser = "Browser", materials = "Materials", tools = "Tools", sheets = "Sheets", history = "History"
    case selection = "Selection", navigator = "Navigator", alerts = "Alerts"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .properties: return "slider.horizontal.3"
        case .layers: return "square.3.layers.3d"
        case .levels: return "building.2"
        case .browser: return "list.bullet.indent"
        case .materials: return "paintpalette"
        case .history: return "clock.arrow.circlepath"
        case .tools: return "square.grid.3x3.square"
        case .sheets: return "rectangle.stack"
        case .selection: return "info.square"
        case .navigator: return "map"
        case .alerts: return "bell.badge"
        }
    }
}

/// Modal sheets presented over the main window.
enum ModalSheet: Identifiable, Equatable {
    case units, drafting, schedule(String), commandReference, shortcuts
    case quickSelect, layerStates, pageSetup(Int), titleBlock(Int), connectClaude, saveCamera
    case spelling, plotStyles, batchPublish
    var id: String {
        switch self {
        case .spelling: return "spelling"
        case .plotStyles: return "plotstyles"
        case .batchPublish: return "batchpublish"
        case .quickSelect: return "qselect"
        case .layerStates: return "layerstates"
        case .pageSetup(let i): return "pagesetup-\(i)"
        case .titleBlock(let i): return "titleblock-\(i)"
        case .connectClaude: return "connectclaude"
        case .saveCamera: return "savecamera"
        case .units: return "units"
        case .drafting: return "drafting"
        case .schedule(let k): return "schedule-\(k)"
        case .commandReference: return "commands"
        case .shortcuts: return "shortcuts"
        }
    }
}

/// Fast-changing values (cursor, snap) kept apart so SwiftUI does not re-render the whole window on mouse moves.
@MainActor
final class LiveState: ObservableObject {
    @Published var cursorWorld: Vec2 = .zero
    @Published var snapHint: String?
    @Published var zoomPercent: Double = 100
}

/// Observable wrapper around the core Editor. One per document window.
@MainActor
final class AppModel: ObservableObject {
    let editor: Editor
    /// Bumped whenever the document or selection changes (views redraw).
    @Published var revision = 0
    @Published var promptText = "Command:"
    @Published var commandLog: [String] = []
    @Published var mode: WorkspaceMode = .plan
    @Published var viewStyle: String = "Shaded with Edges"
    @Published var showLayers = true
    @Published var showProperties = true
    @Published var showScriptConsole = false
    @Published var activeLayout: Int = 0

    /// Keeps the core CTAB variable (read by VIEWTITLE, LAYOUT and other sheet commands) in step with the sheet shown in the window.
    func syncCurrentTab() {
        let layouts = editor.doc.layouts
        let name = mode == .sheet && layouts.indices.contains(activeLayout) ? layouts[activeLayout].name : "Model"
        if editor.doc.variable("CTAB") != name { editor.doc.setVariable("CTAB", name) }
    }

    // Additions
    @Published var showStart = false
    @Published var showPanels = true
    @Published var panelTab: PanelTab = .properties
    @Published var viewDirection: String = "Iso"
    @Published var walkMode = false
    @Published var sheet: ModalSheet?
    /// Text currently typed on the command line (shared so the canvas can forward keystrokes).
    @Published var commandInput = ""
    /// Incremented to ask the command line to take keyboard focus.
    @Published var commandFocusToken = 0
    @Published var agentRunning = false
    /// Clean screen (CLEANSCREENON): hides the ribbon and the side panels.
    @Published var cleanScreen = false
    /// 3D view cube widget (NAVVCUBE).
    @Published var showViewCube = UserDefaults.standard.object(forKey: "showViewCube") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showViewCube, forKey: "showViewCube") }
    }
    /// 3D section box panel visible (SECTIONBOX).
    @Published var showSectionBoxPanel = false
    /// Sun study panel visible (SUNSTUDY).
    @Published var showSunStudy = false
    /// Command search palette (⌘K).
    @Published var showCommandSearch = false
    /// The 3D viewport controller of this window, when a 3D view is shown.
    weak var viewport3D: Viewport3DController?
    /// Autosave bookkeeping (crash recovery).
    var autosave: AutosaveSession?
    /// Asks the Layers panel to apply a filter (LAYERFILTER command).
    @Published var layerFilterRequest: LayerFilter?
    /// Where a recovered document originally lived (Save As suggests it).
    var recoveredOriginalPath: String?
    /// True while the 2D canvas waits for a zoom-window rectangle.
    var zoomWindowPending = false
    /// Click-to-place item from the tool palette (drop string) and its quarter turns (Space rotates 90°, MOD-029).
    var placement: (item: String, turns: Int)?
    func startPlacement(_ item: String) {
        if !editor.isIdle { editor.cancel() }
        placement = (item, 0)
        live.snapHint = "Click to place · Space rotates 90° (Shift+Space −90°) · Esc cancels"
        canvas?.focus()
        revision &+= 1
    }

    let live = LiveState()
    var cursorWorld: Vec2 {
        get { live.cursorWorld }
        set { live.cursorWorld = newValue }
    }
    var snapHint: String? {
        get { live.snapHint }
        set { live.snapHint = newValue }
    }

    /// View requests sent to the 2D canvas / 3D viewport.
    var zoomExtentsRequest = 0
    var pendingHostAction: HostAction?

    /// Lines entered on the command line (up/down recall).
    var inputHistory: [String] = []
    private(set) var files: FileController!
    weak var canvas: PlanCanvasView?
    weak var window: NSWindow?

    private static var instances: [WeakModel] = []
    static var all: [AppModel] { instances.compactMap(\.model) }

    init(document: ArchiDocument = ArchiDocument()) {
        editor = Editor(document: document)
        files = FileController(model: self)
        editor.host = files
        editor.onChange = { [weak self] in self?.revision &+= 1 }
        editor.onSelectionChange = { [weak self] in self?.revision &+= 1 }
        editor.onPromptChange = { [weak self] in
            guard let self else { return }
            self.promptText = self.editor.promptText
            self.revision &+= 1
        }
        editor.onLog = { [weak self] line in
            guard let self else { return }
            self.commandLog.append(line)
            if self.commandLog.count > 2000 { self.commandLog.removeFirst(500) }
        }
        autosave = AutosaveSession(model: self)
        AppModel.instances.removeAll { $0.model == nil }
        AppModel.instances.append(WeakModel(model: self))
    }

    var doc: ArchiDocument { editor.doc }

    // MARK: Naming / title
    var displayName: String {
        if let u = editor.fileURL { return u.deletingPathExtension().lastPathComponent }
        let n = doc.info.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty || n == ProjectInfo().name ? "Untitled" : n
    }
    var windowTitle: String { "\(displayName) — Oanarina Archi Tool" }
    var isDirty: Bool { editor.isDirty }
    var isEmptyDocument: Bool { doc.entities.isEmpty && doc.elements.isEmpty }

    // MARK: Commands
    /// First registered command among candidate names/aliases.
    func command(_ candidates: [String]) -> String? {
        for c in candidates { if let d = editor.registry.lookup(c) { return d.name } }
        return nil
    }
    func has(_ name: String) -> Bool { editor.registry.lookup(name) != nil }

    /// Runs a command like a ribbon button: cancels the active command first (AutoCAD behaviour).
    func runCommand(_ line: String) {
        placement = nil
        syncCurrentTab()
        if !editor.isIdle { editor.cancel() }
        let l = line
        // Let the cancelled command unwind before starting the next one.
        Task { @MainActor in
            var n = 0
            while !self.editor.isIdle && n < 50 { await Task.yield(); n += 1 }
            self.editor.submit(l)
            self.canvas?.focus()
        }
    }

    /// Submits a command line typed by the user.
    func submitLine(_ line: String) {
        if editor.isIdle { syncCurrentTab() }
        let t = line.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { inputHistory.append(t); if inputHistory.count > 200 { inputHistory.removeFirst(50) } }
        editor.submit(line)
    }

    func cancelCommand() {
        if !editor.isIdle { editor.cancel() } else if !editor.selection.isEmpty { editor.selection = [] }
        commandInput = ""
    }

    func focusCommandLine() { commandFocusToken &+= 1 }

    /// Enter / Space / right-click: submits what was typed, or answers Enter (repeats the last command when idle).
    func enterPressed() {
        let t = commandInput
        commandInput = ""
        submitLine(t)
    }

    /// Saved 2D view (restored when the canvas is recreated after a mode switch).
    var planViewCenter: CGPoint?
    var planViewScale: CGFloat?
    /// True once the user zoomed or panned the 2D view; false after a zoom-extents fit (the view then re-fits when resized).
    var planUserZoomed = false

    func zoomExtents() {
        zoomExtentsRequest &+= 1
        canvas?.zoomExtents()
        if mode == .model || mode == .split { pendingHostAction = .zoomExtents; revision &+= 1 }
    }

    // MARK: Selection helpers
    var selectedIDs: [EntityID] { editor.selection.sorted() }
    var selectedEntities: [Entity] { doc.entities.filter { editor.selection.contains($0.id) } }
    var selectedElements: [BIMElement] { doc.elements.filter { editor.selection.contains($0.id) } }

    func selectAll() {
        editor.selection = Set(doc.entities.filter { doc.isEditable(layer: $0.layer) }.map(\.id)
                               + doc.elements.filter { doc.isEditable(layer: $0.layer) && $0.level == doc.currentLevel }.map(\.id))
    }

    func deleteSelection() {
        let ids = editor.selection
        guard !ids.isEmpty else { return }
        editor.transaction("Erase") { $0.remove(ids: ids) }
        editor.selection = []
    }

    // MARK: Document settings
    func setCurrentLayer(_ name: String) {
        editor.transaction("Current Layer") { $0.currentLayer = name }
    }

    /// Layer dropdown: moves the selection to the layer, or makes it current when nothing is selected.
    func applyLayer(_ name: String) {
        let sel = editor.selection
        if sel.isEmpty { setCurrentLayer(name); return }
        editor.transaction("Change Layer") { d in
            for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].layer = name }
            for i in d.elements.indices where sel.contains(d.elements[i].id) { d.elements[i].layer = name }
        }
    }

    func setCurrentLevel(_ id: Int) {
        guard doc.currentLevel != id else { return }
        editor.selection = []
        editor.transaction("Current Level") { $0.currentLevel = id }
    }

    /// Applies color / linetype / lineweight to the selection, or sets the current value (CECOLOR, CELTYPE, CELWEIGHT).
    func applyColor(_ c: ColorRef) {
        let sel = editor.selection
        editor.transaction("Color") { d in
            if sel.isEmpty { d.setVariable("CECOLOR", c.text); return }
            for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].color = c }
        }
    }
    func applyLinetype(_ lt: String?) {
        let sel = editor.selection
        editor.transaction("Linetype") { d in
            if sel.isEmpty { d.setVariable("CELTYPE", lt ?? "ByLayer"); return }
            for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].linetype = lt }
        }
    }
    func applyLineweight(_ lw: Double?) {
        let sel = editor.selection
        editor.transaction("Lineweight") { d in
            if sel.isEmpty { d.setVariable("CELWEIGHT", lw.map { fmt($0) } ?? "ByLayer"); return }
            for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].lineweight = lw }
        }
    }

    var currentColor: ColorRef { doc.variable("CECOLOR").flatMap(ColorRef.parse) ?? .byLayer }
    var currentLinetype: String { doc.variable("CELTYPE") ?? "ByLayer" }
    var currentLineweight: Double? { doc.variable("CELWEIGHT").flatMap(Double.init) }

    // MARK: Manage
    /// Removes unused layers, blocks, text/dim styles. Uses the PURGE command when available.
    func purge() {
        if has("PURGE") { runCommand("PURGE"); return }
        var removed: [String] = []
        editor.transaction("Purge") { d in
            var usedLayers: Set<String> = ["0", d.currentLayer.uppercased()]
            var usedBlocks: Set<String> = []
            func scan(_ es: [Entity]) {
                for e in es {
                    usedLayers.insert(e.layer.uppercased())
                    if case .insert(let ins) = e.geometry { usedBlocks.insert(ins.block) }
                }
            }
            scan(d.entities)
            for l in d.layouts { scan(l.entities) }
            for el in d.elements { usedLayers.insert(el.layer.uppercased()); if case .component(let c) = el.geometry, let b = c.block { usedBlocks.insert(b) } }
            // Blocks referenced by other used blocks.
            var changed = true
            while changed {
                changed = false
                for b in usedBlocks { for e in d.blocks[b]?.entities ?? [] { if case .insert(let i) = e.geometry, !usedBlocks.contains(i.block) { usedBlocks.insert(i.block); changed = true } } }
            }
            for b in d.blocks.keys where !usedBlocks.contains(b) { d.blocks[b] = nil; removed.append("block \(b)") }
            for b in d.blocks.values { for e in b.entities { usedLayers.insert(e.layer.uppercased()) } }
            let before = d.layers.map(\.name)
            d.layers.removeAll { !usedLayers.contains($0.name.uppercased()) }
            removed += Set(before).subtracting(d.layers.map(\.name)).sorted().map { "layer \($0)" }
        }
        editor.print(removed.isEmpty ? "Purge: nothing to remove." : "Purged \(removed.count) item(s): " + removed.joined(separator: ", "))
    }

    /// Checks the document for inconsistencies and fixes them. Uses the AUDIT command when available.
    func audit() {
        if has("AUDIT") { runCommand("AUDIT"); return }
        var fixes: [String] = []
        editor.transaction("Audit") { d in
            var seen: Set<EntityID> = []
            var maxID = 0
            for i in d.entities.indices {
                if seen.contains(d.entities[i].id) { d.entities[i].id = d.nextID + i + 100000; fixes.append("duplicate id") }
                seen.insert(d.entities[i].id); maxID = max(maxID, d.entities[i].id)
            }
            for i in d.elements.indices {
                if seen.contains(d.elements[i].id) { d.elements[i].id = d.nextID + i + 200000; fixes.append("duplicate element id") }
                seen.insert(d.elements[i].id); maxID = max(maxID, d.elements[i].id)
            }
            if d.nextID <= maxID { d.nextID = maxID + 1; fixes.append("next id counter") }
            for e in d.entities where d.layer(named: e.layer) == nil { d.ensureLayer(e.layer); fixes.append("missing layer \(e.layer)") }
            for e in d.elements where d.layer(named: e.layer) == nil { d.ensureLayer(e.layer); fixes.append("missing layer \(e.layer)") }
            let wallIDs = Set(d.elements.compactMap { el -> EntityID? in if case .wall = el.geometry { return el.id }; return nil })
            let orphanCount = d.elements.filter { if case .opening(let o) = $0.geometry { return !wallIDs.contains(o.hostWall) }; return false }.count
            if orphanCount > 0 {
                d.elements.removeAll { if case .opening(let o) = $0.geometry { return !wallIDs.contains(o.hostWall) }; return false }
                fixes.append("\(orphanCount) orphan opening(s)")
            }
            let levelIDs = Set(d.levels.map(\.id))
            if d.levels.isEmpty { d.levels = [Level(id: 0, name: "Ground Floor", elevation: 0)]; fixes.append("no levels") }
            for i in d.elements.indices where !levelIDs.contains(d.elements[i].level) { d.elements[i].level = d.levels[0].id; fixes.append("element on missing level") }
            if d.level(d.currentLevel) == nil { d.currentLevel = d.levels[0].id; fixes.append("current level") }
            if d.layer(named: d.currentLayer) == nil { d.currentLayer = "0"; d.ensureLayer("0"); fixes.append("current layer") }
        }
        editor.print(fixes.isEmpty ? "Audit: no errors found." : "Audit fixed \(fixes.count) problem(s): " + fixes.joined(separator: ", "))
    }

    // MARK: Agent server
    func toggleAgentServer() {
        if AgentServer.shared.isRunning {
            AgentServer.shared.stop()
            editor.print("Agent server stopped.")
        } else {
            do {
                try AgentServer.shared.start(model: self)
                editor.print("Agent server listening on 127.0.0.1:\(AgentServer.shared.port)")
            } catch {
                editor.print("Agent server could not start: \(error.localizedDescription)")
            }
        }
        for m in AppModel.all { m.agentRunning = AgentServer.shared.isRunning }
    }

    // MARK: Scripts
    /// Runs a script file: JavaScript (.js, with the `archi` API) or an AutoCAD-style command script (.scr / .txt).
    func runScriptFile(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            editor.print("Cannot read script \(url.lastPathComponent)."); return
        }
        editor.print("Running script \(url.lastPathComponent)…")
        if url.pathExtension.lowercased() == "js" {
            let engine = scriptEngine ?? ScriptEngine(model: self)
            scriptEngine = engine
            Task { @MainActor in
                let r = await engine.evaluate(text)
                for l in r.output { self.editor.print(l) }
                if let e = r.error { self.editor.print("Script error: \(e)") } else if let v = r.value { self.editor.print("→ \(v)") }
                self.zoomExtents()
            }
        } else {
            Task { @MainActor in
                await self.editor.runScript(text)
                self.editor.print("Script \(url.lastPathComponent) finished.")
                self.zoomExtents()
            }
        }
    }
    var scriptEngine: ScriptEngine?
}

private struct WeakModel { weak var model: AppModel? }
