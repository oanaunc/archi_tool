// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

@main
struct ArchiToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// `--selftest`: runs APPSELFTEST headless (no window), prints the report and exits with 0 (pass) or 1 (fail).
    init() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        let failed: Bool = MainActor.assumeIsolated {
            let r = AppSelfTests.run()
            if let cov = AppSelfTests.lastCoverage {
                print("Command coverage: \(cov.total) commands, \(cov.intentional.count) system variables in palettes, \(cov.missing.count) without UI entry\(cov.missing.isEmpty ? "" : ": " + cov.missing.joined(separator: ", "))")
            }
            for f in r.failures { print("FAIL: \(f)") }
            print("\(r.passed) check(s) passed, \(r.failures.count) failed.")
            return !r.failures.isEmpty
        }
        exit(failed ? 1 : 0)
    }

    var body: some Scene {
        WindowGroup("Oanarina Archi Tool", id: "document", for: DocumentRequest.self) { $request in
            MainWindow(request: request)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ArchiCommands() }

        Window("Command Reference", id: "command-reference") {
            CommandReferenceView(registry: .shared, onClose: nil)
                .frame(minWidth: 620, minHeight: 460)
                .preferredColorScheme(Theme.colorScheme)
        }
        .defaultSize(width: 760, height: 620)

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            ShortcutsView(onClose: nil)
                .frame(minWidth: 520, minHeight: 460)
                .preferredColorScheme(Theme.colorScheme)
        }
        .defaultSize(width: 560, height: 560)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = Theme.appearance
        NSWindow.allowsAutomaticWindowTabbing = true
        AppIcon.install()
        Clipboard.install()
        CommandRegistry.shared.ensureBuiltins()
        AppCommands.registerAll()
        _ = AppPreferences.shared
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated { ShortcutDispatcher.handle(e) || AppDelegate.handleFunctionKey(e) } ? nil : e
        }
        if AppPreferences.shared.agentAutoStart {
            // Wait for the first document window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                MainActor.assumeIsolated {
                    guard !AgentServer.shared.isRunning, let m = AppModel.all.first else { return }
                    try? AgentServer.shared.start(model: m, port: UInt16(clamping: max(1024, min(AppPreferences.shared.agentPort, 65535))))
                    for x in AppModel.all { x.agentRunning = AgentServer.shared.isRunning }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            // A normal quit: the user already decided about unsaved changes.
            for m in AppModel.all { m.autosave?.stop() }
        }
    }

    /// F3/F7/F8/F9/F10/F11/F12 drafting toggles work wherever the keyboard focus is (canvas or command line).
    @MainActor static func handleFunctionKey(_ e: NSEvent) -> Bool {
        let map: [UInt16: (WritableKeyPath<DraftSettings, Bool>, String)] = [
            99: (\.objectSnap, "Osnap"), 98: (\.showGrid, "Grid"), 100: (\.ortho, "Ortho"), 101: (\.gridSnap, "Snap"),
            109: (\.polarTracking, "Polar"), 103: (\.objectSnapTracking, "Object snap tracking"), 111: (\.dynamicInput, "Dyn"),
        ]
        let win = e.window ?? NSApp.keyWindow
        // ⌃0 toggles clean screen; ⌘K opens command search.
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .control, e.keyCode == 29, let m = AppModel.all.first(where: { $0.window === win }) { m.cleanScreen.toggle(); return true }
        guard let (kp, name) = map[e.keyCode], flags.isDisjoint(with: [.command, .control, .option]) else { return false }
        guard let m = AppModel.all.first(where: { $0.window === win }) else { return false }
        m.editor.settings[keyPath: kp].toggle()
        let on = m.editor.settings[keyPath: kp]
        if on && e.keyCode == 100 { m.editor.settings.polarTracking = false }
        if on && e.keyCode == 109 { m.editor.settings.ortho = false }
        if !on && e.keyCode == 103 { Snap.tracker.clear() }
        m.editor.print("<\(name) \(on ? "on" : "off")>")
        m.revision &+= 1
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { WindowRouter.openFile(u) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for m in AppModel.all where m.isDirty {
            m.window?.makeKeyAndOrderFront(nil)
            if !m.files.confirmClose() { return .terminateCancel }
            m.editor.isDirty = false
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Clipboard (entities and building elements as JSON)

struct ClipboardPayload: Codable {
    var entities: [Entity]
    var elements: [BIMElement]
    var base: Vec2
    /// Block definitions and layers the objects use (absent in payloads written by 1.0).
    var blocks: [String: Block]?
    var layers: [Layer]?
    static let type = NSPasteboard.PasteboardType("com.oanarina.archi.objects")

    init(_ c: DraftClipboard) { entities = c.entities; elements = c.elements; base = c.base; blocks = c.blocks; layers = c.layers }
    var clip: DraftClipboard { DraftClipboard(entities: entities, elements: elements, blocks: blocks ?? [:], layers: layers ?? [], base: base) }
}

/// Cmd+X/C/V and COPYCLIP/CUTCLIP/COPYBASE/PASTECLIP/PASTEORIG/PASTEBLOCK share one clipboard: the core
/// `DraftClipboard`, mirrored to the system pasteboard so objects can be pasted into another open drawing.
@MainActor
enum Clipboard {
    /// The key window's field editor handles text commands itself.
    static var textIsFocused: Bool { NSApp.keyWindow?.firstResponder is NSText }

    /// Mirrors every core clipboard change (COPYCLIP, CUTCLIP, COPYBASE) to the system pasteboard.
    static func install() {
        DraftClipboard.onChange = { clip in MainActor.assumeIsolated { write(clip) } }
    }

    static func write(_ clip: DraftClipboard) {
        guard let data = try? JSONEncoder().encode(ClipboardPayload(clip)) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: ClipboardPayload.type)
        pb.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
    }

    static func copy(_ model: AppModel) -> Bool {
        let ids = model.selectedEntities.map(\.id) + model.selectedElements.map(\.id)
        guard !ids.isEmpty else { return false }
        var b = BBox2.empty
        for e in model.selectedEntities { b.add(GeometryOps.bounds(e.geometry, doc: model.doc)) }
        for el in model.selectedElements { for p in CommandHelpers.footprint(el, doc: model.doc) { b.add(p) } }
        let clip = DraftClipboard.capture(ids, from: model.doc, base: b.isEmpty ? .zero : b.min)
        DraftClipboard.current = clip
        write(clip)
        model.editor.print("\(clip.entities.count + clip.elements.count) object(s) copied to the clipboard.")
        return true
    }

    static var canPaste: Bool { NSPasteboard.general.data(forType: ClipboardPayload.type) != nil || !(DraftClipboard.current?.isEmpty ?? true) }

    /// The system pasteboard's objects (from any open drawing), else the in-process clipboard.
    static var current: DraftClipboard? {
        if let data = NSPasteboard.general.data(forType: ClipboardPayload.type) ?? NSPasteboard.general.string(forType: .string)?.data(using: .utf8),
           let p = try? JSONDecoder().decode(ClipboardPayload.self, from: data) { return p.clip }
        return DraftClipboard.current
    }

    static func paste(_ model: AppModel) {
        guard let clip = current, !clip.isEmpty else { return }
        DraftClipboard.current = clip   // PASTECLIP / PASTEORIG / PASTEBLOCK use the same objects
        let target = model.canvas != nil ? model.cursorWorld : clip.base
        var newIDs: [EntityID] = []
        model.editor.transaction("Paste") { d in newIDs = clip.paste(into: &d, offset: target - clip.base, level: d.currentLevel) }
        model.editor.selection = Set(newIDs)
        model.editor.print("Pasted \(newIDs.count) object(s).")
    }
}

// MARK: - Menus

struct ArchiCommands: Commands {
    @FocusedObject private var model: AppModel?
    @Environment(\.openWindow) private var openWindow

    private func run(_ item: CmdItem) {
        guard let m = model, let r = m.command(item.names) else { return }
        m.runCommand(item.args.isEmpty ? r : r + " " + item.args)
    }

    private func openFromMenu() {
        if let m = model { m.files.openPanel(); return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [.archiDocument, .dxfDrawing]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { openWindow(value: DocumentRequest(kind: .open, path: u.path)) }
    }

    @ViewBuilder private func menuItems(_ items: [CmdItem]) -> some View {
        ForEach(items) { item in
            Button(item.title) { run(item) }
                .disabled(model?.command(item.names) == nil)
        }
    }

    @ViewBuilder private func extraMenu(_ i: Int) -> some View {
        ForEach(CommandCatalog.extraMenus[i].1, id: \.0) { name, items in
            Section(name) { menuItems(items) }
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Oanarina Archi Tool") { AboutWindow.show() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { PreferencesWindow.show() }
                .keyboardShortcut(",")
            Button("Agent Server…") { PreferencesWindow.show(.agents) }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Drawing") { openWindow(value: DocumentRequest(kind: .start)) }
                .keyboardShortcut("n")
            Menu("New from Template") {
                Button("Metric Drawing (mm)") { openWindow(value: DocumentRequest(kind: .blankMetric)) }
                Button("Imperial Drawing (in)") { openWindow(value: DocumentRequest(kind: .blankImperial)) }
                Button("Building (levels, grid, sheets)") { openWindow(value: DocumentRequest(kind: .building)) }
                ForEach(TemplateLibrary.all().filter { $0.id != "builtin:metric" && $0.id != "builtin:imperial" && $0.id != "builtin:building" }) { t in
                    Button(t.name) { openWindow(value: DocumentRequest(kind: .template, path: t.id)) }
                }
                Button("Save Drawing as Template…") { model?.runCommand("SAVEASTEMPLATE") }.disabled(model == nil)
                Button("Show Templates Folder") {
                    try? FileManager.default.createDirectory(at: FileLocations.templates, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([FileLocations.templates])
                }
                Divider()
                Button("Sample House") { openWindow(value: DocumentRequest(kind: .sample)) }
            }
            Button("Open…") { openFromMenu() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(RecentFiles.urls, id: \.self) { u in
                    Button(u.lastPathComponent) {
                        if let m = model { m.files.openURL(u) } else { openWindow(value: DocumentRequest(kind: .open, path: u.path)) }
                    }
                }
                Divider()
                Button("Clear Menu") { RecentFiles.clear() }
            }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Button("Save") { model?.files.save() }
                .keyboardShortcut("s")
                .disabled(model == nil)
            Button("Save As…") { model?.files.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
            Button("Import…") { model?.files.importPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model == nil)
            Menu("Insert") { menuItems(CommandCatalog.importItems + CommandCatalog.referenceItems) }
                .disabled(model == nil)
            Menu("Export") {
                ForEach(ExportFormat.all, id: \.ext) { f in
                    Button("\(f.title)…") { model?.files.export(format: f.ext, path: nil) }
                }
                Divider()
                menuItems(CommandCatalog.exportItems)
                Divider()
                Menu("Schedules (CSV)") {
                    ForEach(ScheduleExporter.kinds, id: \.self) { k in
                        Button("\(k.capitalized)…") { model?.files.export(format: "csv:\(k)", path: nil) }
                    }
                }
            }
            .disabled(model == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") { if let m = model { m.sheet = .pageSetup(m.mode == .sheet ? m.activeLayout : -1) } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Plot Preview…") { if let m = model { PlotPreviewWindow.show(model: m) } }
                .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                .disabled(model == nil)
            Button("Plot / Print…") { if let m = model { Plotter.printDrawing(model: m) } }
                .keyboardShortcut("p")
                .disabled(model == nil)
            Button("Publish All Sheets to PDF…") { if let m = model { Plotter.publish(model: m, path: nil) } }
                .disabled(model == nil || (model?.doc.layouts.isEmpty ?? true))
            Button("Batch Publish…") { model?.sheet = .batchPublish }
                .disabled(model == nil || (model?.doc.layouts.isEmpty ?? true))
            Button("Plot Style Tables…") { model?.sheet = .plotStyles }
                .disabled(model == nil)
            Button("Title Block…") { if let m = model, !m.doc.layouts.isEmpty { m.mode = .sheet; m.sheet = .titleBlock(min(max(m.activeLayout, 0), m.doc.layouts.count - 1)) } }
                .disabled(model == nil || (model?.doc.layouts.isEmpty ?? true))
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model?.editor.history.undoLabel.map { "Undo \($0)" } ?? "Undo") {
                if Clipboard.textIsFocused, let t = NSApp.keyWindow?.firstResponder as? NSTextView, !t.string.isEmpty, t.undoManager?.canUndo == true { t.undoManager?.undo() }
                else { model?.editor.undo() }
            }
            .keyboardShortcut("z")
            .disabled(!(model?.editor.history.canUndo ?? false))
            Button(model?.editor.history.redoLabel.map { "Redo \($0)" } ?? "Redo") { model?.editor.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(model?.editor.history.canRedo ?? false))
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if Clipboard.textIsFocused { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil); return }
                if let m = model, Clipboard.copy(m) { m.deleteSelection() }
            }
            .keyboardShortcut("x")
            Button("Copy") {
                if Clipboard.textIsFocused { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil); return }
                if let m = model { _ = Clipboard.copy(m) }
            }
            .keyboardShortcut("c")
            Button("Paste") {
                if Clipboard.textIsFocused && !Clipboard.canPaste { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil); return }
                if let m = model { Clipboard.paste(m) }
            }
            .keyboardShortcut("v")
            Button("Delete") {
                guard let m = model else { return }
                if m.has("ERASE") && !m.editor.selection.isEmpty { m.runCommand("ERASE") } else { m.deleteSelection() }
            }
            .disabled(model?.editor.selection.isEmpty ?? true)
            Divider()
            Button("Select All") {
                if Clipboard.textIsFocused, let t = NSApp.keyWindow?.firstResponder as? NSText, !t.string.isEmpty { t.selectAll(nil); return }
                model?.selectAll()
            }
            .keyboardShortcut("a")
            Button("Deselect All") { model?.editor.selection = [] }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Quick Select…") { model?.sheet = .quickSelect }
                .disabled(model == nil)
            Menu("Selection Tools") { menuItems(CommandCatalog.selection) }
                .disabled(model == nil)
            Menu("Groups & Isolation") { menuItems(CommandCatalog.groups) }
                .disabled(model == nil)
            Button("Match Properties") { model?.runCommand("MATCHPROP") }
                .disabled(model == nil)
        }
        CommandGroup(before: .toolbar) {
            Picker("Workspace", selection: Binding(get: { model?.mode ?? .plan }, set: { model?.mode = $0 })) {
                Text("2D Plan").tag(WorkspaceMode.plan)
                Text("3D Model").tag(WorkspaceMode.model)
                Text("Split").tag(WorkspaceMode.split)
                Text("Sheet").tag(WorkspaceMode.sheet)
            }
            .pickerStyle(.inline)
            .disabled(model == nil)
            Button("2D Plan") { model?.mode = .plan }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("3D Model") { model?.mode = .model }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Split View") { model?.mode = .split }.keyboardShortcut("3", modifiers: [.command, .option])
            Button("Sheets") { model?.mode = .sheet }.keyboardShortcut("4", modifiers: [.command, .option])
            Divider()
            Button("Zoom Extents") { model?.zoomExtents() }.keyboardShortcut("0")
            Button("Zoom In") { model?.canvas?.zoomBy(1.5) }.keyboardShortcut("=")
            Button("Zoom Out") { model?.canvas?.zoomBy(1 / 1.5) }.keyboardShortcut("-")
            Button("Zoom Window") { model?.zoomWindowPending = true; model?.canvas?.focus() }
            Menu("Visual Style") {
                ForEach(["Wireframe", "Hidden", "Shaded", "Shaded with Edges", "Realistic", "X-Ray"], id: \.self) { s in
                    Button(s) { model?.files.handle(.setViewStyle(s)) }
                }
            }
            Menu("3D View") {
                ForEach(["Top", "Front", "Right", "Back", "Left", "Iso"], id: \.self) { v in Button(v) { model?.files.handle(.setView(v)) } }
            }
            Divider()
            Button((model?.showPanels ?? true) ? "Hide Panels" : "Show Panels") { model?.showPanels.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Layers Panel") { model?.showPanels = true; model?.panelTab = .layers }
            Button("Properties Panel") { model?.showPanels = true; model?.panelTab = .properties }
            Button("Levels Panel") { model?.showPanels = true; model?.panelTab = .levels }
            Button("Project Browser") { model?.showPanels = true; model?.panelTab = .browser }
            Button("Materials Panel") { model?.showPanels = true; model?.panelTab = .materials }
            Button("History Panel") { model?.showPanels = true; model?.panelTab = .history }
            Button("Sheet Set Manager") { model?.showPanels = true; model?.panelTab = .sheets }
            Button("Tool Palettes") { model?.showPanels = true; model?.panelTab = .tools }
            Menu("Float Panel") {
                ForEach(PanelTab.allCases) { t in Button(t.rawValue) { if let m = model { FloatingPanels.float(t, model: m) } } }
            }
            .disabled(model == nil)
            Button("Material Library…") { if let m = model { MaterialLibraryWindow.show(model: m) } }.disabled(model == nil)
            Button("Layer States…") { model?.sheet = .layerStates }
            Menu("Workspace") {
                ForEach(Workspaces.all) { w in
                    Button(w.name) { if let m = model { Workspaces.apply(w, to: m) } }
                }
                Divider()
                Button("Save Current Workspace…") { model?.runCommand("WSSAVE") }
            }
            .disabled(model == nil)
            Button((model?.cleanScreen ?? false) ? "Exit Clean Screen" : "Clean Screen") { model?.cleanScreen.toggle() }
            Menu("3D Tools") {
                Button("View Cube") { model?.showViewCube.toggle() }
                Button("Section Box") { if let m = model { if m.mode == .plan || m.mode == .sheet { m.mode = .model }; m.showSectionBoxPanel.toggle() } }
                Button("Sun Study") { if let m = model { if m.mode == .plan || m.mode == .sheet { m.mode = .model }; m.showSunStudy.toggle() } }
                Button("Orbit Around Selection") { model?.runCommand("ORBITSELECTION") }
                Button("Save Camera…") { if let m = model { if m.mode == .plan || m.mode == .sheet { m.mode = .model }; m.sheet = .saveCamera } }
            }
            .disabled(model == nil)
            Button((model?.showScriptConsole ?? false) ? "Hide Script Console" : "Show Script Console") { model?.showScriptConsole.toggle() }
                .keyboardShortcut("j", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("Draw") { menuItems(CommandCatalog.draw) }
        CommandMenu("Modify") { menuItems(CommandCatalog.modify) }
        CommandMenu("Annotate") { menuItems(CommandCatalog.text + CommandCatalog.dimensions) }
        CommandMenu("Architecture") {
            menuItems(CommandCatalog.build + CommandCatalog.spaces)
            Divider()
            Menu("More Building Tools") { menuItems(CommandCatalog.buildMore) }
            Menu("Rooms & Areas") { menuItems(CommandCatalog.roomsMore) }
            Menu("Documentation") { menuItems(CommandCatalog.documentation) }
        }
        CommandMenu("Model") {
            extraMenu(0)
            Divider()
            Button("Node Editor…") { if let m = model { NodeEditorWindow.show(model: m) } }.disabled(model == nil)
        }
        CommandMenu("Analyze") { extraMenu(1) }
        CommandMenu("Tools") {
            ForEach(CommandCatalog.coverageMenus, id: \.0) { name, items in
                Menu(name) { menuItems(items) }
            }
            Menu("System Variables") { menuItems(CommandCatalog.variableItems) }
            Divider()
            Menu("All Commands") {
                let reg = CommandRegistry.shared
                let groups = Dictionary(grouping: reg.sorted, by: \.category).sorted { $0.key < $1.key }
                ForEach(groups, id: \.key) { cat, list in
                    Menu(cat) {
                        ForEach(list, id: \.name) { d in
                            Button(d.name) { model?.runCommand(d.name) }.disabled(model == nil)
                        }
                    }
                }
            }
        }
        CommandGroup(replacing: .help) {
            Button("Search Commands…") { model?.showCommandSearch = true }
                .keyboardShortcut("k")
                .disabled(model == nil)
            Button("Command Reference") { openWindow(id: "command-reference") }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            Button("User Guide") {
                if let u = Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") { NSWorkspace.shared.open(u) }
            }
            .disabled(Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") == nil)
            Button("Keyboard Shortcuts") { openWindow(id: "keyboard-shortcuts") }
            Button("Start Screen") { model?.showStart = true }.disabled(model == nil)
            Button("Check Command Coverage") { model?.runCommand("APPSELFTEST") }.disabled(model == nil)
            Button("Export Command Reference…") { model?.runCommand("EXPORTCOMMANDS") }.disabled(model == nil)
            Button("Customize Shortcuts…") { PreferencesWindow.show(.shortcuts) }
            Divider()
            Button("Connect Claude…") { model?.sheet = .connectClaude }
                .disabled(model == nil)
            Button("Oanarina Website") { if let u = URL(string: "https://oanarina.com") { NSWorkspace.shared.open(u) } }
        }
    }
}

// MARK: - Help windows

struct CommandReferenceView: View {
    let registry: CommandRegistry
    var onClose: (() -> Void)?
    @State private var query = ""

    var body: some View {
        registry.ensureBuiltins()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let cmds = registry.sorted.filter { c in
            q.isEmpty || c.name.lowercased().contains(q) || c.aliases.contains { $0.lowercased().contains(q) } || c.summary.lowercased().contains(q) || c.category.lowercased().contains(q)
        }
        let groups = Dictionary(grouping: cmds, by: \.category).sorted { $0.key < $1.key }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal").foregroundStyle(Theme.accent)
                Text("Command Reference").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(cmds.count) of \(registry.commands.count)").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                TextField("Search commands, aliases, descriptions", text: $query).darkField().frame(width: 280)
                if let c = onClose { Button("Done", action: c).buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction) }
            }
            .padding(12)
            HSeparator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.key) { cat, list in
                        Section {
                            ForEach(list, id: \.name) { c in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(c.name).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                                        .frame(width: 150, alignment: .leading)
                                        .textSelection(.enabled)
                                    Text(c.aliases.joined(separator: ", ")).font(Theme.mono).foregroundStyle(Theme.textDim)
                                        .frame(width: 130, alignment: .leading)
                                    Text(c.summary).font(Theme.font).foregroundStyle(Theme.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            }
                        } header: {
                            Text(cat.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(Theme.ribbon)
                        }
                    }
                }
            }
        }
        .background(Theme.panel)
    }
}

struct ShortcutsView: View {
    var onClose: (() -> Void)?
    private let rows: [(String, String)] = [
        ("Type anywhere", "Start a command on the command line"),
        ("Enter / Space", "Finish input · repeat the last command"),
        ("Esc", "Cancel the command · clear the selection"),
        ("Right-click", "Enter while a command runs · context menu when idle"),
        ("Tab", "Accept autocomplete"), ("↑ / ↓", "Command history / suggestions"),
        ("F3", "Object snap on/off"), ("F7", "Grid display"), ("F8", "Ortho mode"), ("F9", "Grid snap"), ("F10", "Polar tracking"), ("F11", "Object snap tracking"), ("F12", "Dynamic input"),
        ("Scroll wheel / pinch", "Zoom about the cursor"), ("Two-finger scroll", "Pan"), ("Middle-drag · Space+drag", "Pan"),
        ("Double middle-click", "Zoom extents"), ("⌘0", "Zoom extents"), ("⌘= / ⌘-", "Zoom in / out"),
        ("Drag left → right", "Window selection (fully inside)"), ("Drag right → left", "Crossing selection (touching)"),
        ("Shift-click", "Toggle an object in the selection"), ("Click a grip", "Stretch the object (wall ends move joined walls)"),
        ("Double-click text", "Edit text"), ("Delete", "Erase the selection"),
        ("⌘Z / ⇧⌘Z", "Undo / Redo"), ("⌘C / ⌘X / ⌘V", "Copy / Cut / Paste objects (paste at cursor)"), ("⌘A", "Select all"),
        ("⌥⌘1 … ⌥⌘4", "2D · 3D · Split · Sheets"), ("⌥⌘P", "Show / hide panels"), ("⌥⌘J", "Script console"),
        ("⌘N / ⌘O / ⌘S / ⇧⌘S", "New · Open · Save · Save As"), ("⌘P", "Plot / Print"), ("⇧⌘P", "Page setup"), ("⌥⇧⌘P", "Plot preview"),
        ("⌘K", "Search commands"), ("⌃0", "Clean screen"), ("⌘,", "Settings (custom shortcuts, colors, autosave…)"), ("⇧⌘/", "Command reference"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "keyboard").foregroundStyle(Theme.accent)
                Text("Keyboard & Mouse").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if let c = onClose { Button("Done", action: c).buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction) }
            }
            .padding(12)
            HSeparator()
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    ForEach(rows, id: \.0) { k, v in
                        GridRow {
                            Text(k).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                            Text(v).font(Theme.font).foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.panel)
    }
}
