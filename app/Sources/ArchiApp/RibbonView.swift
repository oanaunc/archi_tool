// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// A command button definition shared by the ribbon and the menus.
struct CmdItem: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let symbol: String
    /// Candidate command names/aliases; the first registered one is used.
    let names: [String]
    /// Extra inputs appended after the command name.
    var args: String = ""
}

enum CommandCatalog {
    static let draw: [CmdItem] = [
        CmdItem(title: "Line", symbol: "line.diagonal", names: ["LINE"]),
        CmdItem(title: "Polyline", symbol: "point.topleft.down.curvedto.point.bottomright.up", names: ["PLINE", "POLYLINE"]),
        CmdItem(title: "Circle", symbol: "circle", names: ["CIRCLE"]),
        CmdItem(title: "Arc", symbol: "rainbow", names: ["ARC"]),
        CmdItem(title: "Rectangle", symbol: "rectangle", names: ["RECTANG", "RECTANGLE", "REC"]),
        CmdItem(title: "Polygon", symbol: "hexagon", names: ["POLYGON"]),
        CmdItem(title: "Ellipse", symbol: "oval", names: ["ELLIPSE"]),
        CmdItem(title: "Spline", symbol: "scribble.variable", names: ["SPLINE"]),
        CmdItem(title: "Hatch", symbol: "square.grid.3x3.fill", names: ["HATCH", "BHATCH"]),
    ]
    static let modify: [CmdItem] = [
        CmdItem(title: "Move", symbol: "arrow.up.and.down.and.arrow.left.and.right", names: ["MOVE"]),
        CmdItem(title: "Copy", symbol: "plus.square.on.square", names: ["COPY"]),
        CmdItem(title: "Rotate", symbol: "arrow.clockwise", names: ["ROTATE"]),
        CmdItem(title: "Mirror", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", names: ["MIRROR"]),
        CmdItem(title: "Scale", symbol: "arrow.up.left.and.arrow.down.right", names: ["SCALE"]),
        CmdItem(title: "Stretch", symbol: "arrow.left.and.right", names: ["STRETCH"]),
        CmdItem(title: "Trim", symbol: "scissors", names: ["TRIM"]),
        CmdItem(title: "Extend", symbol: "arrow.right.to.line", names: ["EXTEND"]),
        CmdItem(title: "Offset", symbol: "square.on.square.dashed", names: ["OFFSET"]),
        CmdItem(title: "Fillet", symbol: "arrow.turn.up.right", names: ["FILLET"]),
        CmdItem(title: "Chamfer", symbol: "triangle.lefthalf.filled", names: ["CHAMFER"]),
        CmdItem(title: "Array", symbol: "square.grid.3x3", names: ["ARRAY", "ARRAYRECT"]),
        CmdItem(title: "Explode", symbol: "burst", names: ["EXPLODE"]),
        CmdItem(title: "Erase", symbol: "eraser", names: ["ERASE"]),
        CmdItem(title: "Join", symbol: "link", names: ["JOIN"]),
        CmdItem(title: "Break", symbol: "minus.square", names: ["BREAK"]),
    ]
    static let text: [CmdItem] = [
        CmdItem(title: "Text", symbol: "textformat", names: ["TEXT", "DTEXT"]),
        CmdItem(title: "MText", symbol: "text.alignleft", names: ["MTEXT"]),
    ]
    static let dimensions: [CmdItem] = [
        CmdItem(title: "Linear", symbol: "ruler", names: ["DIMLINEAR", "DLI"]),
        CmdItem(title: "Aligned", symbol: "arrow.up.right", names: ["DIMALIGNED", "DAL"]),
        CmdItem(title: "Angular", symbol: "angle", names: ["DIMANGULAR", "DAN"]),
        CmdItem(title: "Radius", symbol: "circle.and.line.horizontal", names: ["DIMRADIUS", "DRA"]),
        CmdItem(title: "Diameter", symbol: "circle.circle", names: ["DIMDIAMETER", "DDI"]),
        CmdItem(title: "Leader", symbol: "text.bubble", names: ["LEADER", "MLEADER", "QLEADER"]),
        CmdItem(title: "Table", symbol: "tablecells", names: ["TABLE"]),
    ]
    static let build: [CmdItem] = [
        CmdItem(title: "Wall", symbol: "rectangle.split.2x1", names: ["WALL"]),
        CmdItem(title: "Door", symbol: "door.left.hand.open", names: ["DOOR"]),
        CmdItem(title: "Window", symbol: "window.vertical.closed", names: ["WINDOW"]),
        CmdItem(title: "Opening", symbol: "rectangle.dashed", names: ["OPENING", "WALLOPENING"]),
        CmdItem(title: "Curtain Wall", symbol: "square.grid.4x3.fill", names: ["CURTAINWALL", "CWALL"]),
        CmdItem(title: "Column", symbol: "cylinder", names: ["COLUMN"]),
        CmdItem(title: "Beam", symbol: "minus.rectangle", names: ["BEAM"]),
        CmdItem(title: "Slab", symbol: "square.3.layers.3d.bottom.filled", names: ["SLAB", "FLOOR"]),
        CmdItem(title: "Roof", symbol: "house", names: ["ROOF"]),
        CmdItem(title: "Ceiling", symbol: "square.3.layers.3d.top.filled", names: ["CEILING"]),
        CmdItem(title: "Stair", symbol: "stairs", names: ["STAIR", "STAIRS"]),
        CmdItem(title: "Railing", symbol: "line.3.horizontal", names: ["RAILING"]),
    ]
    static let spaces: [CmdItem] = [
        CmdItem(title: "Room", symbol: "square.dashed.inset.filled", names: ["ROOM", "SPACE"]),
        CmdItem(title: "Grid", symbol: "grid", names: ["GRID", "GRIDLINE"]),
        CmdItem(title: "Component", symbol: "sofa", names: ["COMPONENT", "FURNITURE"]),
        CmdItem(title: "Quick Building", symbol: "building.2", names: ["QUICKBUILDING", "QBUILD", "BUILDING"]),
    ]
    static let furniture: [(String, String)] = [
        ("Chair", "chair"), ("Table", "table.furniture"), ("Desk", "desktopcomputer"), ("Sofa", "sofa"), ("Bed", "bed.double"),
        ("Wardrobe", "cabinet"), ("Kitchen", "refrigerator"), ("Sink", "sink"), ("WC", "toilet"), ("Bath", "bathtub"), ("Car", "car"),
    ]
    /// All menu-mirrored categories.
    static let menus: [(String, [CmdItem])] = [("Draw", draw), ("Modify", modify), ("Annotate", text + dimensions), ("Architecture", build + spaces)]
}

enum RibbonTab: String, CaseIterable, Identifiable {
    case home = "Home", annotate = "Annotate", architecture = "Architecture", view = "View", output = "Output", manage = "Manage", script = "Script"
    var id: String { rawValue }
}

/// Large (icon over label) or small (icon + label in a row) ribbon button.
struct RibbonButton: View {
    enum Size { case large, small }
    let title: String
    let symbol: String
    var size: Size = .large
    var active = false
    var enabled = true
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if size == .large {
                    VStack(spacing: 3) {
                        Image(systemName: symbol)
                            .font(.system(size: 19, weight: .regular))
                            .frame(height: 24)
                        Text(title)
                            .font(.system(size: 10))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 50, height: 58, alignment: .top)
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .frame(width: 16)
                        Text(title).font(.system(size: 11)).lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 20)
                    .frame(minWidth: 70, alignment: .leading)
                }
            }
            .foregroundStyle(!enabled ? Theme.textFaint : (active ? Theme.accentText : Theme.text))
            .background(RoundedRectangle(cornerRadius: 4).fill(active ? Theme.accent : (hovering && enabled ? Theme.hover : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help.isEmpty ? title : help)
    }
}

/// A titled ribbon panel.
struct RibbonGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                HStack(alignment: .top, spacing: 2) { content }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .frame(maxHeight: .infinity, alignment: .top)
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .padding(.bottom, 3)
            }
            VSeparator().padding(.vertical, 6)
        }
    }
}

struct RibbonView: View {
    @ObservedObject var model: AppModel
    @AppStorage("ribbonTab") private var tabRaw = RibbonTab.home.rawValue
    @AppStorage("ribbonCollapsed") private var collapsed = false

    private var tab: RibbonTab { RibbonTab(rawValue: tabRaw) ?? .home }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            if !collapsed {
                HSeparator()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) { content }
                        .frame(height: 90)
                }
                .background(Theme.ribbon)
            }
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 14, height: 14)
                    .overlay(Text("A").font(.system(size: 10, weight: .black)).foregroundStyle(Theme.accentText))
            }
            .padding(.horizontal, 8)
            .help("Oanarina Archi Tool")
            ForEach(RibbonTab.allCases) { t in
                Button { tabRaw = t.rawValue; if collapsed { collapsed = false } } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Theme.text : Theme.textDim)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .overlay(alignment: .bottom) {
                            if tab == t { Rectangle().fill(Theme.accent).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            IconButton(symbol: "square.and.arrow.down", help: "Save (⌘S)") { model.files.save() }
            IconButton(symbol: "arrow.uturn.backward", help: model.editor.history.undoLabel.map { "Undo \($0) (⌘Z)" } ?? "Nothing to undo") { model.editor.undo() }
                .disabled(!model.editor.history.canUndo)
            IconButton(symbol: "arrow.uturn.forward", help: model.editor.history.redoLabel.map { "Redo \($0) (⇧⌘Z)" } ?? "Nothing to redo") { model.editor.redo() }
                .disabled(!model.editor.history.canRedo)
            IconButton(symbol: "sidebar.right", help: model.showPanels ? "Hide panels" : "Show panels", active: model.showPanels) { model.showPanels.toggle() }
            IconButton(symbol: collapsed ? "chevron.down" : "chevron.up", help: collapsed ? "Expand the ribbon" : "Collapse the ribbon") { collapsed.toggle() }
                .padding(.trailing, 6)
        }
        .frame(height: 26)
        .background(Theme.ribbonTabBar)
    }

    // MARK: Buttons

    private func cmd(_ item: CmdItem, _ size: RibbonButton.Size = .large) -> some View {
        let resolved = model.command(item.names)
        let def = resolved.flatMap { model.editor.registry.lookup($0) }
        let help = def.map { "\(item.title) — \($0.summary)  [\($0.name)\($0.aliases.isEmpty ? "" : ", " + $0.aliases.joined(separator: ", "))]" }
            ?? "\(item.title) is not available in this build"
        return RibbonButton(title: item.title, symbol: item.symbol, size: size, active: resolved != nil && model.editor.activeCommand?.name == resolved,
                            enabled: resolved != nil, help: help) {
            if let r = resolved { model.runCommand(item.args.isEmpty ? r : r + " " + item.args) }
        }
    }

    private func smallColumns(_ items: [CmdItem], rows: Int = 3) -> some View {
        let cols = stride(from: 0, to: items.count, by: rows).map { Array(items[$0..<min($0 + rows, items.count)]) }
        return HStack(alignment: .top, spacing: 2) {
            ForEach(cols, id: \.self) { col in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(col) { cmd($0, .small) }
                }
            }
        }
    }

    private func action(_ title: String, _ symbol: String, _ size: RibbonButton.Size = .large, active: Bool = false, enabled: Bool = true, help: String = "", _ act: @escaping () -> Void) -> some View {
        RibbonButton(title: title, symbol: symbol, size: size, active: active, enabled: enabled, help: help, action: act)
    }

    // MARK: Content per tab

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: homeTab
        case .annotate: annotateTab
        case .architecture: architectureTab
        case .view: viewTab
        case .output: outputTab
        case .manage: manageTab
        case .script: scriptTab
        }
    }

    private var homeTab: some View {
        Group {
            RibbonGroup(title: "Draw") {
                ForEach(CommandCatalog.draw.prefix(4)) { cmd($0) }
                smallColumns(Array(CommandCatalog.draw.dropFirst(4)))
            }
            RibbonGroup(title: "Modify") { smallColumns(CommandCatalog.modify) }
            RibbonGroup(title: "Layers") {
                VStack(alignment: .leading, spacing: 4) {
                    LayerDropdown(model: model).frame(width: 170)
                    HStack(spacing: 4) {
                        action("Layer Properties", "square.3.layers.3d", .small, help: "Open the Layers panel") { model.showPanels = true; model.panelTab = .layers }
                    }
                }
            }
            RibbonGroup(title: "Properties") {
                VStack(alignment: .leading, spacing: 3) {
                    ColorDropdown(model: model).frame(width: 150)
                    LinetypeDropdown(model: model).frame(width: 150)
                    LineweightDropdown(model: model).frame(width: 150)
                }
            }
            RibbonGroup(title: "Selection") {
                action("Select All", "checkmark.rectangle.stack", help: "Select all objects (⌘A)") { model.selectAll() }
                action("Properties", "slider.horizontal.3", help: "Show the Properties panel") { model.showPanels = true; model.panelTab = .properties }
            }
        }
    }

    private var annotateTab: some View {
        Group {
            RibbonGroup(title: "Text") { ForEach(CommandCatalog.text) { cmd($0) } }
            RibbonGroup(title: "Dimensions") {
                cmd(CommandCatalog.dimensions[0])
                smallColumns(Array(CommandCatalog.dimensions[1..<5]))
            }
            RibbonGroup(title: "Leaders & Tables") { ForEach(CommandCatalog.dimensions.suffix(2)) { cmd($0) } }
            RibbonGroup(title: "Style") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dimension style").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    Menu {
                        ForEach(model.doc.dimStyles, id: \.name) { s in
                            Button { model.editor.transaction("Dimension Style") { $0.currentDimStyle = s.name } } label: {
                                if s.name == model.doc.currentDimStyle { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                            }
                        }
                    } label: {
                        Text(model.doc.currentDimStyle).font(Theme.font)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 170)
                    .darkField()
                    Text("Text height: \(fmt(model.editor.settings.textHeight, 2))").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .padding(.top, 4)
            }
        }
    }

    private var architectureTab: some View {
        Group {
            RibbonGroup(title: "Build") {
                ForEach(CommandCatalog.build.prefix(3)) { cmd($0) }
                smallColumns(Array(CommandCatalog.build.dropFirst(3)))
            }
            RibbonGroup(title: "Room & Area") {
                cmd(CommandCatalog.spaces[0])
                cmd(CommandCatalog.spaces[1])
            }
            RibbonGroup(title: "Model") {
                componentMenu
                cmd(CommandCatalog.spaces[3])
            }
            RibbonGroup(title: "Level") {
                VStack(alignment: .leading, spacing: 4) {
                    LevelDropdown(model: model).frame(width: 170)
                    action("Levels", "building.2", .small, help: "Open the Levels panel") { model.showPanels = true; model.panelTab = .levels }
                }
            }
        }
    }

    private var componentMenu: some View {
        let resolved = model.command(CommandCatalog.spaces[2].names)
        return Menu {
            ForEach(CommandCatalog.furniture, id: \.0) { name, sym in
                Button { if let r = resolved { model.runCommand("\(r) \(name)") } } label: { Label(name, systemImage: sym) }
            }
            Divider()
            Button("Component…") { if let r = resolved { model.runCommand(r) } }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "sofa").font(.system(size: 19)).frame(height: 24)
                Text("Component").font(.system(size: 10))
            }
            .frame(width: 58, height: 58, alignment: .top)
            .padding(.top, 4)
            .foregroundStyle(resolved == nil ? Theme.textFaint : Theme.text)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(resolved == nil)
        .help(resolved == nil ? "Components are not available in this build" : "Place furniture and fixtures")
    }

    private var viewTab: some View {
        Group {
            RibbonGroup(title: "Workspace") {
                action("2D Plan", "square", active: model.mode == .plan, help: "2D plan canvas") { model.mode = .plan }
                action("3D Model", "cube", active: model.mode == .model, help: "3D model viewport") { model.mode = .model }
                action("Split", "rectangle.split.2x1", active: model.mode == .split, help: "Plan and 3D side by side") { model.mode = .split }
                action("Sheet", "doc.richtext", active: model.mode == .sheet, help: "Paper space layouts") { model.mode = .sheet }
            }
            RibbonGroup(title: "Navigate") {
                action("Extents", "arrow.up.backward.and.arrow.down.forward", help: "Zoom to the drawing extents") { model.zoomExtents() }
                VStack(alignment: .leading, spacing: 1) {
                    action("Window", "plus.magnifyingglass", .small, active: model.zoomWindowPending, enabled: model.mode != .model && model.mode != .sheet, help: "Drag a rectangle to zoom into") {
                        model.zoomWindowPending = true; model.canvas?.focus(); model.revision &+= 1
                    }
                    action("Zoom In", "plus.magnifyingglass", .small, enabled: model.canvas != nil && model.mode != .model, help: "Zoom in") { model.canvas?.zoomBy(1.5) }
                    action("Zoom Out", "minus.magnifyingglass", .small, enabled: model.canvas != nil && model.mode != .model, help: "Zoom out") { model.canvas?.zoomBy(1 / 1.5) }
                }
            }
            RibbonGroup(title: "Visual Style") {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(["Wireframe", "Hidden", "Shaded", "Shaded with Edges", "Realistic", "X-Ray"], id: \.self) { s in
                            Button { model.files.handle(.setViewStyle(s)) } label: {
                                if s == model.viewStyle { Label(s, systemImage: "checkmark") } else { Text(s) }
                            }
                        }
                    } label: { Label(model.viewStyle, systemImage: "circle.lefthalf.filled").font(Theme.font) }
                    .menuStyle(.borderlessButton)
                    .frame(width: 170)
                    .darkField()
                    Text("Applies to the 3D viewport").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .padding(.top, 4)
            }
            RibbonGroup(title: "Views") {
                let views: [(String, String)] = [("Top", "square.tophalf.filled"), ("Front", "square.bottomhalf.filled"), ("Right", "square.righthalf.filled"),
                                                 ("Back", "square.tophalf.filled"), ("Left", "square.lefthalf.filled"), ("Iso", "cube")]
                HStack(alignment: .top, spacing: 2) {
                    ForEach([0, 3], id: \.self) { start in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(views[start..<start + 3], id: \.0) { v in
                                action(v.0, v.1, .small, active: model.viewDirection == v.0 && model.mode != .plan, help: "\(v.0) view in the 3D viewport") { model.files.handle(.setView(v.0)) }
                            }
                        }
                    }
                }
            }
            RibbonGroup(title: "Presentation") {
                action("Render", "camera.aperture", help: "Render a photorealistic image") { RenderController.renderImage(model: model) }
                action("Walk", "figure.walk", active: model.walkMode, help: "Walk through the model (WASD + mouse)") { model.files.handle(.walkthrough) }
            }
        }
    }

    private var outputTab: some View {
        Group {
            RibbonGroup(title: "Plot") {
                action("Plot / Print", "printer", help: "Print the drawing or the active sheet (⌘P)") { Plotter.printDrawing(model: model) }
                action("Export PDF", "doc.richtext", help: "Export the drawing or the active sheet as vector PDF") { model.files.export(format: "pdf", path: nil) }
            }
            RibbonGroup(title: "Export") {
                let items = ExportFormat.all.filter { $0.ext != "pdf" }
                HStack(alignment: .top, spacing: 2) {
                    ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { s in
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(items[s..<min(s + 3, items.count)], id: \.ext) { f in
                                action(f.ext.uppercased(), f.symbol, .small, help: "Export \(f.title)") { model.files.export(format: f.ext, path: nil) }
                            }
                        }
                    }
                }
            }
            RibbonGroup(title: "Schedules") {
                Menu {
                    ForEach(ScheduleExporter.kinds, id: \.self) { k in
                        Button("\(k.capitalized) schedule (CSV)…") { model.files.export(format: "csv:\(k)", path: nil) }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "tablecells").font(.system(size: 19)).frame(height: 24)
                        Text("CSV").font(.system(size: 10))
                    }
                    .frame(width: 50, height: 58, alignment: .top).padding(.top, 4)
                    .foregroundStyle(Theme.text)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Export schedules as CSV")
                action("View", "list.bullet.rectangle", help: "Show a schedule table") { model.sheet = .schedule("all") }
            }
        }
    }

    private var manageTab: some View {
        Group {
            RibbonGroup(title: "Panels") {
                action("Layers", "square.3.layers.3d", active: model.showPanels && model.panelTab == .layers, help: "Layer properties manager") { model.showPanels = true; model.panelTab = .layers }
                action("Browser", "list.bullet.indent", active: model.showPanels && model.panelTab == .browser, help: "Project browser") { model.showPanels = true; model.panelTab = .browser }
                action("Materials", "paintpalette", active: model.showPanels && model.panelTab == .materials, help: "Materials") { model.showPanels = true; model.panelTab = .materials }
            }
            RibbonGroup(title: "Settings") {
                action("Units", "ruler", help: "Drawing units") { model.sheet = .units }
                action("Drafting", "slider.horizontal.3", help: "Drafting settings: grid, snap, polar, object snaps") { model.sheet = .drafting }
            }
            RibbonGroup(title: "Cleanup") {
                action("Purge", "trash.slash", help: "Remove unused layers, blocks and styles") { model.purge() }
                action("Audit", "checkmark.shield", help: "Check the drawing for errors and fix them") { model.audit() }
            }
        }
    }

    private var scriptTab: some View {
        Group {
            RibbonGroup(title: "Scripting") {
                action("JS Console", "terminal", active: model.showScriptConsole, help: "JavaScript console with the archi API") { model.showScriptConsole.toggle() }
                action("Run Script", "play.rectangle", help: "Run a JavaScript file (.js) or a command script (.scr)") {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.javaScript, UTType(filenameExtension: "scr") ?? .plainText, .plainText]
                    p.message = "Choose a JavaScript file (archi API) or a command script (one command line per line)"
                    if p.runModal() == .OK, let u = p.url { model.runScriptFile(u) }
                }
            }
            RibbonGroup(title: "AI Agents") {
                action(model.agentRunning ? "Stop Server" : "Start Server", "antenna.radiowaves.left.and.right", active: model.agentRunning,
                       help: "Local JSON-RPC agent server on 127.0.0.1:\(AgentServer.shared.port)") { model.toggleAgentServer() }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(model.agentRunning ? Color.green : Theme.textFaint).frame(width: 7, height: 7)
                        Text(model.agentRunning ? "Listening" : "Stopped").font(Theme.font).foregroundStyle(Theme.text)
                    }
                    Text("127.0.0.1:\(AgentServer.shared.port)").font(Theme.mono).foregroundStyle(Theme.textDim)
                    if model.agentRunning {
                        Button("Copy token") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AgentServer.shared.token, forType: .string)
                        }
                        .buttonStyle(FlatButtonStyle(compact: true))
                        .help("Copy the session token agents must send")
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Dropdowns (shared with the status bar)

struct LayerDropdown: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let doc = model.doc
        let cur = doc.layer(named: doc.currentLayer)
        Menu {
            ForEach(doc.layers, id: \.name) { l in
                Button { model.applyLayer(l.name) } label: {
                    Label { Text(l.name + (l.visible ? "" : "  (off)") + (l.frozen ? "  (frozen)" : "") + (l.locked ? "  (locked)" : "")) }
                        icon: { Image(nsImage: swatchImage(l.color)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: swatchImage(cur?.color ?? .white))
                Text(doc.currentLayer).font(Theme.font).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .darkField()
        .help(model.editor.selection.isEmpty ? "Current layer — choose to make another layer current" : "Move the selected objects to a layer")
    }
}

struct LevelDropdown: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let doc = model.doc
        Menu {
            ForEach(doc.levels.sorted { $0.elevation > $1.elevation }, id: \.id) { l in
                Button { model.setCurrentLevel(l.id) } label: {
                    if l.id == doc.currentLevel { Label("\(l.name)  (\(fmt(l.elevation, 0)))", systemImage: "checkmark") } else { Text("\(l.name)  (\(fmt(l.elevation, 0)))") }
                }
            }
        } label: {
            Label(doc.level(doc.currentLevel)?.name ?? "Level", systemImage: "building.2").font(Theme.font).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .darkField()
        .help("Current level (new building elements go here)")
    }
}

struct ColorDropdown: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let doc = model.doc
        let sel = model.selectedEntities
        let value: ColorRef? = sel.isEmpty ? model.currentColor : (Set(sel.map(\.color)).count == 1 ? sel[0].color : nil)
        let shown = value.map { displayColor($0, layer: sel.first?.layer ?? doc.currentLayer, doc: doc) } ?? .white
        Menu {
            Button("ByLayer") { model.applyColor(.byLayer) }
            Button("ByBlock") { model.applyColor(.byBlock) }
            Divider()
            ForEach(basicColors, id: \.0) { name, c in
                Button { model.applyColor(c) } label: { Label { Text(name) } icon: { Image(nsImage: swatchImage(displayColor(c, layer: "0", doc: doc))) } }
            }
            Divider()
            Button("More Colors…") { ColorPanelBridge.shared.pick(initial: shown) { model.applyColor(ColorRef.parse($0.hex) ?? .byLayer) } }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: swatchImage(shown))
                Text(value.map { colorName($0) } ?? "*VARIES*").font(Theme.font)
            }
        }
        .menuStyle(.borderlessButton)
        .darkField()
        .help("Color")
    }
}

struct LinetypeDropdown: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let sel = model.selectedEntities
        let value: String? = sel.isEmpty ? model.currentLinetype : (Set(sel.map { $0.linetype ?? "ByLayer" }).count == 1 ? (sel[0].linetype ?? "ByLayer") : nil)
        Menu {
            Button("ByLayer") { model.applyLinetype(nil) }
            Divider()
            ForEach(model.doc.linetypes, id: \.name) { lt in
                Button("\(lt.name)   \(lt.description)") { model.applyLinetype(lt.name) }
            }
        } label: {
            Label(value ?? "*VARIES*", systemImage: "line.3.horizontal").font(Theme.font)
        }
        .menuStyle(.borderlessButton)
        .darkField()
        .help("Linetype")
    }
}

struct LineweightDropdown: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let sel = model.selectedEntities
        let value: String? = sel.isEmpty ? (model.currentLineweight.map { String(format: "%.2f mm", $0) } ?? "ByLayer")
            : (Set(sel.map { $0.lineweight ?? -1 }).count == 1 ? (sel[0].lineweight.map { String(format: "%.2f mm", $0) } ?? "ByLayer") : nil)
        Menu {
            Button("ByLayer") { model.applyLineweight(nil) }
            Divider()
            ForEach(standardLineweights, id: \.self) { w in
                Button(String(format: "%.2f mm", w)) { model.applyLineweight(w) }
            }
        } label: {
            Label(value ?? "*VARIES*", systemImage: "lineweight").font(Theme.font)
        }
        .menuStyle(.borderlessButton)
        .darkField()
        .help("Lineweight")
    }
}

func colorName(_ c: ColorRef) -> String {
    switch c {
    case .byLayer: return "ByLayer"
    case .byBlock: return "ByBlock"
    case .aci(let i): return basicColors.first { $0.1 == c }?.0 ?? "Color \(i)"
    case .rgb: return c.text
    }
}

/// Small color swatch image for menus (menus cannot draw SwiftUI shapes).
func swatchImage(_ c: RGBA, size: CGFloat = 11) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
        NSColor(white: 1, alpha: 0.35).setStroke()
        NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).stroke()
        return true
    }
    return img
}

/// Opens the system color panel and reports the chosen color.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var callback: ((RGBA) -> Void)?
    func pick(initial: RGBA, _ done: @escaping (RGBA) -> Void) {
        callback = done
        let p = NSColorPanel.shared
        p.showsAlpha = false
        p.color = NSColor(srgbRed: initial.r, green: initial.g, blue: initial.b, alpha: 1)
        p.setTarget(self)
        p.setAction(#selector(changed(_:)))
        p.isContinuous = false
        p.orderFront(nil)
    }
    @objc private func changed(_ sender: NSColorPanel) { callback?(RGBA(sender.color)) }
}
