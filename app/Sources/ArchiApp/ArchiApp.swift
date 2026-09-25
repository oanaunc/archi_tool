// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

@main
struct ArchiToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Oanarina Archi Tool", id: "document", for: DocumentRequest.self) { $request in
            MainWindow(request: request)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { ArchiCommands() }

        Window("Command Reference", id: "command-reference") {
            CommandReferenceView(registry: .shared, onClose: nil)
                .frame(minWidth: 620, minHeight: 460)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 760, height: 620)

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            ShortcutsView(onClose: nil)
                .frame(minWidth: 520, minHeight: 460)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 560, height: 560)
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSWindow.allowsAutomaticWindowTabbing = true
        CommandRegistry.shared.ensureBuiltins()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated { AppDelegate.handleFunctionKey(e) } ? nil : e
        }
    }

    /// F3/F7/F8/F9/F10/F12 drafting toggles work wherever the keyboard focus is (canvas or command line).
    @MainActor static func handleFunctionKey(_ e: NSEvent) -> Bool {
        let map: [UInt16: (WritableKeyPath<DraftSettings, Bool>, String)] = [
            99: (\.objectSnap, "Osnap"), 98: (\.showGrid, "Grid"), 100: (\.ortho, "Ortho"), 101: (\.gridSnap, "Snap"),
            109: (\.polarTracking, "Polar"), 111: (\.dynamicInput, "Dyn"),
        ]
        guard let (kp, name) = map[e.keyCode] else { return false }
        let win = e.window ?? NSApp.keyWindow
        guard let m = AppModel.all.first(where: { $0.window === win }) else { return false }
        m.editor.settings[keyPath: kp].toggle()
        let on = m.editor.settings[keyPath: kp]
        if on && e.keyCode == 100 { m.editor.settings.polarTracking = false }
        if on && e.keyCode == 109 { m.editor.settings.ortho = false }
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
    static let type = NSPasteboard.PasteboardType("com.oanarina.archi.objects")
}

@MainActor
enum Clipboard {
    /// The key window's field editor handles text commands itself.
    static var textIsFocused: Bool { NSApp.keyWindow?.firstResponder is NSText }

    static func copy(_ model: AppModel) -> Bool {
        let ents = model.selectedEntities
        let els = model.selectedElements
        guard !ents.isEmpty || !els.isEmpty else { return false }
        // Openings travel with their host walls only.
        let hostIDs = Set(els.map(\.id))
        var elements = els.filter { if case .opening(let o) = $0.geometry { return hostIDs.contains(o.hostWall) }; return true }
        let hosted = model.doc.elements.filter { if case .opening(let o) = $0.geometry { return hostIDs.contains(o.hostWall) && !elements.contains($0) }; return false }
        elements += hosted
        var b = BBox2.empty
        for e in ents { b.add(GeometryOps.bounds(e.geometry, doc: model.doc)) }
        for el in elements { for p in CommandHelpers.footprint(el, doc: model.doc) { b.add(p) } }
        let payload = ClipboardPayload(entities: ents, elements: elements, base: b.isEmpty ? .zero : b.min)
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: ClipboardPayload.type)
        pb.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
        model.editor.print("\(ents.count + elements.count) object(s) copied to the clipboard.")
        return true
    }

    static var canPaste: Bool { NSPasteboard.general.data(forType: ClipboardPayload.type) != nil }

    static func paste(_ model: AppModel) {
        guard let data = NSPasteboard.general.data(forType: ClipboardPayload.type) ?? NSPasteboard.general.string(forType: .string)?.data(using: .utf8),
              let p = try? JSONDecoder().decode(ClipboardPayload.self, from: data) else { return }
        let target = model.canvas != nil ? model.cursorWorld : p.base
        let t = Transform2D.translation(target - p.base)
        var newIDs: [EntityID] = []
        model.editor.transaction("Paste") { d in
            var map: [EntityID: EntityID] = [:]
            for var e in p.entities {
                e.geometry = GeometryOps.transform(e.geometry, t)
                let old = e.id
                let nid = d.add(e)
                map[old] = nid
                newIDs.append(nid)
            }
            let ordered = p.elements.filter { if case .opening = $0.geometry { return false }; return true } + p.elements.filter { if case .opening = $0.geometry { return true }; return false }
            for el in ordered {
                var n = el
                if case .opening(var o) = n.geometry {
                    guard let h = map[o.hostWall] else { continue }
                    o.hostWall = h
                    n.geometry = .opening(o)
                } else {
                    n.geometry = CommandHelpers.transform(n.geometry, t)
                }
                n.id = d.allocateID()
                n.level = d.currentLevel
                map[el.id] = n.id
                d.ensureLayer(n.layer)
                d.elements.append(n)
                newIDs.append(n.id)
            }
        }
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

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Drawing") { openWindow(value: DocumentRequest(kind: .start)) }
                .keyboardShortcut("n")
            Menu("New from Template") {
                Button("Metric Drawing (mm)") { openWindow(value: DocumentRequest(kind: .blankMetric)) }
                Button("Imperial Drawing (in)") { openWindow(value: DocumentRequest(kind: .blankImperial)) }
                Button("Building (levels, grid, sheets)") { openWindow(value: DocumentRequest(kind: .building)) }
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
            Button("Import DXF…") { model?.files.importPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model == nil)
            Menu("Export") {
                ForEach(ExportFormat.all, id: \.ext) { f in
                    Button("\(f.title)…") { model?.files.export(format: f.ext, path: nil) }
                }
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
            Button("Page Setup (Sheets)") { model?.mode = .sheet }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Plot / Print…") { if let m = model { Plotter.printDrawing(model: m) } }
                .keyboardShortcut("p")
                .disabled(model == nil)
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
            Button((model?.showScriptConsole ?? false) ? "Hide Script Console" : "Show Script Console") { model?.showScriptConsole.toggle() }
                .keyboardShortcut("j", modifiers: [.command, .option])
            Divider()
        }
        CommandMenu("Draw") { menuItems(CommandCatalog.draw) }
        CommandMenu("Modify") { menuItems(CommandCatalog.modify) }
        CommandMenu("Annotate") { menuItems(CommandCatalog.text + CommandCatalog.dimensions) }
        CommandMenu("Architecture") { menuItems(CommandCatalog.build + CommandCatalog.spaces) }
        CommandGroup(replacing: .help) {
            Button("Command Reference") { openWindow(id: "command-reference") }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            Button("User Guide") {
                if let u = Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") { NSWorkspace.shared.open(u) }
            }
            .disabled(Bundle.main.url(forResource: "USER-GUIDE", withExtension: "md") == nil)
            Button("Keyboard Shortcuts") { openWindow(id: "keyboard-shortcuts") }
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
        ("F3", "Object snap on/off"), ("F7", "Grid display"), ("F8", "Ortho mode"), ("F9", "Grid snap"), ("F10", "Polar tracking"), ("F12", "Dynamic input"),
        ("Scroll wheel / pinch", "Zoom about the cursor"), ("Two-finger scroll", "Pan"), ("Middle-drag · Space+drag", "Pan"),
        ("Double middle-click", "Zoom extents"), ("⌘0", "Zoom extents"), ("⌘= / ⌘-", "Zoom in / out"),
        ("Drag left → right", "Window selection (fully inside)"), ("Drag right → left", "Crossing selection (touching)"),
        ("Shift-click", "Toggle an object in the selection"), ("Click a grip", "Stretch the object (wall ends move joined walls)"),
        ("Double-click text", "Edit text"), ("Delete", "Erase the selection"),
        ("⌘Z / ⇧⌘Z", "Undo / Redo"), ("⌘C / ⌘X / ⌘V", "Copy / Cut / Paste objects (paste at cursor)"), ("⌘A", "Select all"),
        ("⌥⌘1 … ⌥⌘4", "2D · 3D · Split · Sheets"), ("⌥⌘P", "Show / hide panels"), ("⌥⌘J", "Script console"),
        ("⌘N / ⌘O / ⌘S / ⇧⌘S", "New · Open · Save · Save As"), ("⌘P", "Plot / Print"), ("⇧⌘/", "Command reference"),
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
