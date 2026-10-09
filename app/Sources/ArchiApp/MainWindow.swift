// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// One document window: ribbon, workspace (2D / 3D / split / sheet), panels, command line, status bar.
struct MainWindow: View {
    let request: DocumentRequest?
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    @State private var didSetup = false
    /// Docked panel column width (drag the divider; remembered across launches).
    @AppStorage("panelWidth") private var panelWidth = 300.0
    @AppStorage(CommandLineAppearance.floatingKey) private var floatingCommandLine = false

    var body: some View {
        VStack(spacing: 0) {
            if !model.cleanScreen {
                RibbonView(model: model)
                ContextualRibbonStrip(model: model)
                HSeparator()
            }
            if FileTabs.visible {
                FileTabsBar(model: model)
                HSeparator()
            }
            HStack(spacing: 0) {
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { ViewportBadge(model: model).padding(8) }
                    .overlay(alignment: .topTrailing) {
                        // Quick Properties (QP): shown while objects are selected, hidden otherwise (APP-025).
                        if model.showQuickProperties && !model.editor.selection.isEmpty && model.mode != .sheet {
                            QuickPropertiesView(model: model, compact: true)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel.opacity(0.96)))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator, lineWidth: 1))
                                .padding(10)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        // Floating command line (CMD-014): over the canvas, draggable by its grip.
                        if floatingCommandLine {
                            FloatingCommandLine(model: model)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let mv = model.maximizedViewport {
                            Button { model.runCommand("VPMIN") } label: {
                                Label("Viewport \(mv.viewport + 1) of \(model.doc.layouts.indices.contains(mv.layout) ? model.doc.layouts[mv.layout].name : "sheet") maximised — click or VPMIN to return", systemImage: "arrow.down.right.and.arrow.up.left")
                                    .font(Theme.fontSmall).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.accent)).foregroundStyle(Theme.accentText)
                            }.buttonStyle(.plain).padding(8)
                        }
                    }
                if model.showPanels && !model.cleanScreen {
                    PanelResizeHandle(width: $panelWidth)
                    PanelsView(model: model).frame(width: CGFloat(panelWidth))
                }
            }
            if model.showLayoutTabs && !model.cleanScreen {
                LayoutTabsBar(model: model)
            }
            if model.showScriptConsole {
                HSeparator()
                ScriptConsoleView(model: model).frame(height: 210)
            }
            if !floatingCommandLine {
                HSeparator()
                CommandLineView(model: model)
            }
            HSeparator()
            StatusBarView(model: model)
        }
        .background(Theme.canvas)
        .overlay {
            if model.showStart {
                StartView(model: model).transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if model.showCommandSearch {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25).ignoresSafeArea().onTapGesture { model.showCommandSearch = false }
                    CommandSearchPalette(model: model).padding(.top, 90)
                }
            }
        }
        .sheet(item: $model.sheet) { s in sheetView(s) }
        .navigationTitle(model.windowTitle)
        .background(WindowAccessor { w in attach(w) })
        .focusedSceneObject(model)
        .preferredColorScheme(Theme.colorScheme)
        .frame(minWidth: 600, minHeight: 480)
        .onAppear(perform: setup)
        .onChange(of: model.revision) { _ in updateWindowState() }
    }

    @ViewBuilder private var workspace: some View {
        switch model.mode {
        case .plan:
            PlanCanvas(model: model)
        case .model:
            Viewport3DView(model: model)
        case .split:
            TiledViews(model: model)
        case .sheet:
            SheetView(model: model)
        }
    }

    @ViewBuilder private func sheetView(_ s: ModalSheet) -> some View {
        switch s {
        case .units: UnitsSheet(model: model)
        case .drafting: DraftingSettingsSheet(model: model)
        case .schedule(let k): ScheduleSheet(model: model, kind: k)
        case .commandReference: CommandReferenceView(registry: model.editor.registry, onClose: { model.sheet = nil }).frame(width: 720, height: 560)
        case .shortcuts: ShortcutsView(onClose: { model.sheet = nil }).frame(width: 560, height: 520)
        case .quickSelect: QuickSelectSheet(model: model)
        case .layerStates: LayerStatesSheet(model: model)
        case .pageSetup(let i): PageSetupSheet(model: model, layoutIndex: i)
        case .titleBlock(let i): TitleBlockSheet(model: model, layoutIndex: i)
        case .connectClaude: ConnectClaudeSheet(onClose: { model.sheet = nil })
        case .saveCamera: SaveCameraSheet(model: model)
        case .spelling: SpellingSheet(model: model)
        case .plotStyles: PlotStyleSheet(model: model)
        case .batchPublish: BatchPublishSheet(model: model)
        }
    }

    private func attach(_ w: NSWindow) {
        if model.window !== w {
            model.window = w
            w.appearance = Theme.appearance
            w.backgroundColor = Theme.nsPanel
            // Opaque window: inactive windows must never show through (no vibrancy).
            w.isOpaque = true
            w.titlebarAppearsTransparent = false
            WindowRepaint.install(on: w)
            WindowTabs.configure(w)
            updateWindowState()
            if AppModel.all.count == 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { FloatingPanels.restore(for: model) } }
        }
        model.files.installCloseGuard(on: w)
    }

    private func updateWindowState() {
        guard let w = model.window else { return }
        if w.isDocumentEdited != model.isDirty { w.isDocumentEdited = model.isDirty }
        if w.representedURL != model.editor.fileURL { w.representedURL = model.editor.fileURL }
        if w.title != model.windowTitle { w.title = model.windowTitle }
        MaterialTextures.documentFolder = model.editor.fileURL?.deletingLastPathComponent()
    }

    private func setup() {
        WindowRouter.openWindow = { r in openWindow(value: r) }
        guard !didSetup else { return }
        didSetup = true
        WindowStateMemory.restore(model)
        AppCommands.registerAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { ScriptLibrary.runStartup(for: model) }
        if AppModel.all.count <= 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { WhatsNew.checkOnLaunch(model: model) } }
        if !WindowRouter.pendingURLs.isEmpty {
            let url = WindowRouter.pendingURLs.removeFirst()
            model.files.load(url)
            for u in WindowRouter.pendingURLs { WindowRouter.open(DocumentRequest(kind: .open, path: u.path)) }
            WindowRouter.pendingURLs.removeAll()
            return
        }
        switch request?.kind {
        case .none, .start?:
            model.showStart = true
        case .open?:
            if let p = request?.path, model.files.load(URL(fileURLWithPath: p)) { } else { model.showStart = true }
        case .sample?:
            model.newDocument(.sample)
            model.buildSampleHouse()
        case .template?:
            if let id = request?.path, let t = TemplateLibrary.all().first(where: { $0.id == id }) ?? (FileManager.default.fileExists(atPath: id) ? TemplateLibrary.template(for: URL(fileURLWithPath: id)) : nil) {
                TemplateLibrary.apply(t, to: model)
            } else { model.showStart = true }
        case let k?:
            model.newDocument(k)
        }
    }
}

extension AppModel {
    /// Replaces the (empty) document with a template.
    func newDocument(_ kind: DocumentRequest.Kind) {
        let prefs = AppPreferences.shared
        var k = kind
        if kind == .blankMetric, prefs.defaultUnits == .inches || prefs.defaultUnits == .feet { k = .blankImperial }
        var (d, s) = FileController.template(k)
        if kind == .blankMetric {
            d.units = prefs.defaultUnits
            if d.units == .centimeters || d.units == .meters {
                let f = d.units.mm
                s.textHeight /= f; s.wallThickness /= f; s.wallHeight /= f; s.offsetDistance /= f
            } else if d.units == .feet {
                s.textHeight /= 12; s.wallThickness /= 12; s.wallHeight /= 12; s.offsetDistance /= 12; s.gridSpacing = 1
            }
        }
        s = prefs.draftDefaults(base: s, units: d.units)
        editor.replaceDocument(d, url: nil)
        editor.settings = s
        planUserZoomed = false
        showStart = false
        mode = .plan
        let label: String
        switch kind {
        case .blankImperial: label = "New drawing (imperial, inches)"
        case .building: label = "New building (levels, grid and sheets)"
        case .sample: label = "Sample house"
        default: label = "New drawing (metric, millimetres)"
        }
        editor.print(label)
        revision &+= 1
        zoomExtents()
    }
}

/// Small top-left badge on the workspace (AutoCAD viewport label): mode + level.
private struct ViewportBadge: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceMode.allCases) { m in
                Button { model.mode = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 10, weight: model.mode == m ? .semibold : .regular))
                        .foregroundStyle(model.mode == m ? Theme.accentText : Theme.textDim)
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(model.mode == m ? Theme.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(m.rawValue)")
            }
            if model.mode == .plan || model.mode == .split {
                Text(model.doc.level(model.doc.currentLevel)?.name ?? "")
                    .font(.system(size: 10)).foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 7)
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Reports the hosting NSWindow.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowTrackingView {
        let v = WindowTrackingView()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ v: WindowTrackingView, context: Context) {
        v.onWindow = onWindow
        if let w = v.window { DispatchQueue.main.async { onWindow(w) } }
    }
}

final class WindowTrackingView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window { let cb = onWindow; DispatchQueue.main.async { cb?(w) } }
    }
}

// MARK: - Sheets

private struct SheetFrame<Content: View>: View {
    let title: String
    var onCancel: (() -> Void)?
    var onOK: (() -> Void)?
    var okTitle = "OK"
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(14)
            HSeparator()
            content.padding(14)
            HSeparator()
            HStack {
                Spacer()
                if let c = onCancel { Button("Cancel", action: c).buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction) }
                if let o = onOK { Button(okTitle, action: o).buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction) }
            }
            .padding(12)
        }
        .background(Theme.panel)
    }
}

struct UnitsSheet: View {
    @ObservedObject var model: AppModel
    @State private var units: Units = .millimeters
    @State private var lin: UnitFormat.Linear = .decimal
    @State private var lprec = 2
    @State private var ang: UnitFormat.Angular = .degrees
    @State private var aprec = 0
    var body: some View {
        SheetFrame(title: "Drawing Units", onCancel: { model.sheet = nil }, onOK: {
            let d = model.doc
            if units != d.units || lin != UnitFormat.linearType(d) || lprec != UnitFormat.linearPrecision(d) || ang != UnitFormat.angularType(d) || aprec != UnitFormat.angularPrecision(d) {
                model.editor.transaction("Units") { doc in
                    doc.units = units
                    doc.setVariable("LUNITS", "\(lin.rawValue)"); doc.setVariable("LUPREC", "\(lprec)")
                    doc.setVariable("AUNITS", "\(ang.rawValue)"); doc.setVariable("AUPREC", "\(aprec)")
                }
            }
            model.sheet = nil
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Length").font(Theme.fontBold)
                        Picker("Type", selection: $lin) { ForEach(UnitFormat.Linear.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Stepper("Precision: \(lin == .architectural || lin == .fractional ? "1/\(1 << lprec)\"" : "\(lprec) decimals")", value: $lprec, in: 0...8)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Angle").font(Theme.fontBold)
                        Picker("Type", selection: $ang) { ForEach(UnitFormat.Angular.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Stepper("Precision: \(aprec)", value: $aprec, in: 0...8)
                    }
                }
                Text("Sample: \(UnitFormat.linear(42.5 / UnitFormat.inchesPerUnit(units), units: units, type: lin, precision: lprec))  ·  \(UnitFormat.angle(0.7854, type: ang, precision: aprec))")
                    .font(Theme.mono).foregroundStyle(Theme.accent)
                Divider()
                Picker("Insertion units", selection: $units) {
                    ForEach(Units.allCases, id: \.self) { u in Text("\(u.rawValue.capitalized) (\(u.abbreviation))").tag(u) }
                }
                .pickerStyle(.radioGroup)
                Text("Coordinates are stored as drawing units. Changing the unit relabels the drawing and affects exports (1 \(units.abbreviation) = \(fmt(units.mm)) mm); it does not rescale existing geometry. Use SCALE to resize objects.")
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 360, alignment: .leading)
        }
        .onAppear {
            let d = model.doc
            units = d.units; lin = UnitFormat.linearType(d); lprec = UnitFormat.linearPrecision(d); ang = UnitFormat.angularType(d); aprec = UnitFormat.angularPrecision(d)
        }
    }
}

struct DraftingSettingsSheet: View {
    @ObservedObject var model: AppModel
    @State private var s = DraftSettings()
    var body: some View {
        SheetFrame(title: "Drafting Settings", onCancel: { model.sheet = nil }, onOK: {
            model.editor.settings = s
            model.sheet = nil
            model.revision &+= 1
        }) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snap and Grid").font(Theme.fontBold)
                    Toggle("Grid display (F7)", isOn: $s.showGrid)
                    Toggle("Grid snap (F9)", isOn: $s.gridSnap)
                    HStack { Text("Grid spacing"); TextField("", value: $s.gridSpacing, format: .number).frame(width: 80) }
                    Divider()
                    Text("Polar Tracking").font(Theme.fontBold)
                    Toggle("Ortho (F8)", isOn: $s.ortho)
                    Toggle("Polar tracking (F10)", isOn: $s.polarTracking)
                    Picker("Increment", selection: $s.polarIncrement) {
                        ForEach([5.0, 10, 15, 18, 22.5, 30, 45, 90], id: \.self) { Text("\(fmt($0))°").tag($0) }
                    }
                    .frame(width: 180)
                    Divider()
                    Toggle("Dynamic input (F12)", isOn: $s.dynamicInput)
                    Toggle("Show lineweights", isOn: $s.lineweightDisplay)
                    HStack { Text("Text height"); TextField("", value: $s.textHeight, format: .number).frame(width: 80) }
                    HStack { Text("Wall thickness"); TextField("", value: $s.wallThickness, format: .number).frame(width: 80) }
                    HStack { Text("Wall height"); TextField("", value: $s.wallHeight, format: .number).frame(width: 80) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Object snap (F3)", isOn: $s.objectSnap).font(Theme.fontBold)
                    ForEach(SnapKind.allCases, id: \.self) { k in
                        Toggle(k.rawValue.capitalized, isOn: Binding(get: { s.snapModes.contains(k) }, set: { on in if on { s.snapModes.insert(k) } else { s.snapModes.remove(k) } }))
                    }
                    HStack {
                        Button("Select All") { s.snapModes = Set(SnapKind.allCases) }.buttonStyle(FlatButtonStyle(compact: true))
                        Button("Clear All") { s.snapModes = [] }.buttonStyle(FlatButtonStyle(compact: true))
                    }
                }
            }
            .font(Theme.font)
            .frame(width: 480, alignment: .leading)
        }
        .onAppear { s = model.editor.settings }
    }
}

struct ScheduleSheet: View {
    @ObservedObject var model: AppModel
    @State var kind: String

    var body: some View {
        let rows = parseCSV(ScheduleExporter.csv(doc: model.doc, kind: kind))
        SheetFrame(title: "Schedule", onCancel: nil, onOK: { model.sheet = nil }, okTitle: "Close") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("Schedule", selection: $kind) {
                        ForEach(ScheduleExporter.kinds, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .frame(width: 220)
                    Spacer()
                    Button { model.files.export(format: "csv:\(kind)", path: nil) } label: { Label("Export CSV…", systemImage: "square.and.arrow.up") }
                        .buttonStyle(FlatButtonStyle())
                }
                if rows.isEmpty {
                    Text("No data for this schedule yet.").font(Theme.font).foregroundStyle(Theme.textDim).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                                GridRow {
                                    ForEach(Array(r.enumerated()), id: \.offset) { _, c in
                                        Text(c).font(i == 0 ? Theme.fontBold : Theme.font)
                                            .foregroundStyle(i == 0 ? Theme.accent : Theme.text)
                                            .textSelection(.enabled)
                                    }
                                }
                                if i == 0 { Divider() }
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: 300)
                    .background(Theme.field)
                    Text("\(rows.count - 1) row(s)").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
            }
            .frame(width: 720)
        }
    }
}

/// Minimal RFC 4180 CSV parser (quoted fields, doubled quotes).
func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var it = Array(text).makeIterator()
    var pending: Character? = nil
    while let ch = pending ?? it.next() {
        pending = nil
        if inQuotes {
            if ch == "\"" {
                if let n = it.next() { if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n } } else { inQuotes = false }
            } else { field.append(ch) }
        } else {
            switch ch {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n": row.append(field); field = ""; if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }; row = []
            case "\r": break
            default: field.append(ch)
            }
        }
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
}

/// Forces a full repaint when a window becomes visible again (un-occluded, tab switched, key/main changes), so an
/// inactive or background window never shows a stale or blank ribbon.
@MainActor
enum WindowRepaint {
    private static var observed: Set<ObjectIdentifier> = []
    static func install(on w: NSWindow) {
        let id = ObjectIdentifier(w)
        guard !observed.contains(id) else { return }
        observed.insert(id)
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeMainNotification,
                                          NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification,
                                          NSWindow.didEndLiveResizeNotification, NSWindow.didChangeScreenNotification,
                                          NSWindow.didChangeBackingPropertiesNotification, NSWindow.didEnterFullScreenNotification,
                                          NSWindow.didExitFullScreenNotification,
                                          NSWindow.didResignMainNotification, NSWindow.didResignKeyNotification, NSWindow.didDeminiaturizeNotification]
        for n in names {
            NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { note in
                guard let win = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    // Repaint after SwiftUI/AppKit have finished the new layout, not inside the notification.
                    DispatchQueue.main.async { [weak win] in if let win { repaint(win) } }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = observed.remove(id) }
        }
    }
    static func repaint(_ w: NSWindow) {
        guard w.occlusionState.contains(.visible), let v = w.contentView else { return }
        v.needsLayout = true
        v.layoutSubtreeIfNeeded()
        func mark(_ x: NSView) { x.needsDisplay = true; x.subviews.forEach(mark) }
        mark(v)
        v.needsLayout = true
        w.displayIfNeeded()
    }
}

/// Draggable divider on the left edge of the docked panel column (double-click restores the default width).
struct PanelResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?
    var body: some View {
        Rectangle().fill(Theme.separator).frame(width: 1)
            .overlay(Color.clear.frame(width: 7).contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    if start == nil { start = width }
                    width = min(620, max(220, (start ?? width) - Double(g.translation.width)))
                }.onEnded { _ in start = nil })
                .onTapGesture(count: 2) { width = 300 })
            .help("Drag to resize the panels · double-click for the default width")
    }
}
