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
    case home = "Home", insert = "Insert", annotate = "Annotate", architecture = "Architecture", modeling = "Modeling", analyze = "Analyze"
    case collaborate = "Collaborate", view = "View", output = "Output", manage = "Manage", script = "Script"
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

    @ObservedObject private var prefs = AppPreferences.shared

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
        // Opaque theme background: never transparent, also in inactive windows.
        .background(Theme.ribbonTabBar)
    }

    /// Quick access toolbar: each button runs the same command as typing its name.
    private var quickAccessBar: some View {
        HStack(spacing: 0) {
            ForEach(prefs.quickAccess, id: \.self) { name in
                let def = model.editor.registry.lookup(name)
                let disabled = def == nil || (name == "UNDO" || name == "U") && !model.editor.history.canUndo || name == "REDO" && !model.editor.history.canRedo
                IconButton(symbol: QuickAccess.symbol(for: name), help: def.map { "\($0.name) — \($0.summary)" } ?? "\(name) is not available") {
                    model.runCommand(name)
                }
                .disabled(disabled)
            }
            Menu {
                ForEach(["NEW", "OPEN", "SAVE", "SAVEAS", "UNDO", "REDO", "PLOT", "PREVIEW", "PUBLISH", "MATCHPROP", "QSELECTDIALOG", "LAYER", "RENDER", "OPTIONS"], id: \.self) { n in
                    Button {
                        if let i = prefs.quickAccess.firstIndex(of: n) { prefs.quickAccess.remove(at: i) } else { prefs.quickAccess.append(n) }
                    } label: {
                        if prefs.quickAccess.contains(n) { Label(n, systemImage: "checkmark") } else { Text(n) }
                    }
                }
                Divider()
                Button("More Commands…") { PreferencesWindow.show(.toolbar) }
            } label: { Image(systemName: "chevron.down").font(.system(size: 8)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Customize the quick access toolbar")
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            Button { AboutWindow.show() } label: { AppIconView(size: 18) }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .help("About Oanarina Archi Tool")
            quickAccessBar
            VSeparator().frame(height: 14).padding(.horizontal, 4)
            ForEach(RibbonTab.allCases.filter { !prefs.hiddenRibbonTabs.contains($0.rawValue) || $0 == tab }) { t in
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
            IconButton(symbol: "magnifyingglass", help: "Search commands (⌘K)") { model.showCommandSearch = true }
            IconButton(symbol: "rectangle.dashed", help: "Clean screen (⌃0)") { model.cleanScreen.toggle() }
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
        case .insert: insertTab
        case .annotate: annotateTab
        case .architecture: architectureTab
        case .modeling: modelingTab
        case .analyze: analyzeTab
        case .collaborate: collaborateTab
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
                        action("States", "rectangle.stack", .small, help: "Layer States Manager (LAYERSTATE)") { model.sheet = .layerStates }
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
                action("Quick Select", "line.3.horizontal.decrease.circle", help: "Quick Select dialog (QSELECTDIALOG)") { model.sheet = .quickSelect }
                VStack(alignment: .leading, spacing: 1) {
                    cmd(CmdItem(title: "Match Props", symbol: "paintbrush.pointed", names: ["MATCHPROP"]), .small)
                    cmd(CmdItem(title: "Similar", symbol: "square.on.square.intersection.dashed", names: ["SELECTSIMILAR"]), .small)
                    action("Properties", "slider.horizontal.3", .small, help: "Show the Properties panel") { model.showPanels = true; model.panelTab = .properties }
                }
                commandMenu("More", "ellipsis.circle", CommandCatalog.selection, help: "Selection tools: QSELECT, invert, by layer/type, chain, filter, named sets")
            }
            RibbonGroup(title: "Groups") { smallColumns(CommandCatalog.groups) }
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Draw", symbol: "pencil.and.outline",
                                  sections: [("Draw More", CommandCatalog.drawMore), ("Construction", CommandCatalog.construction)], help: "More drawing and construction tools")
                RibbonCatalogMenu(model: model, title: "Modify", symbol: "wand.and.rays",
                                  sections: [("Modify More", CommandCatalog.modifyMore), ("Clipboard & Selection", CommandCatalog.clipboard), ("Drafting Extras", CommandCatalog.draftingExtra)], help: "More modify, clipboard and selection tools")
                RibbonCatalogMenu(model: model, title: "Layers", symbol: "square.3.layers.3d.middle.filled",
                                  sections: [("Layer Tools", CommandCatalog.layersMore)], help: "Layer tools (LAYISO, LAYFRZ, LAYMRG…)")
            }
        }
    }

    /// Large button opening a menu of commands.
    private func commandMenu(_ title: String, _ symbol: String, _ items: [CmdItem], help: String) -> some View {
        Menu {
            ForEach(items) { item in
                let r = model.command(item.names)
                Button { if let r { model.runCommand(item.args.isEmpty ? r : r + " " + item.args) } } label: { Label(item.title, systemImage: item.symbol) }
                    .disabled(r == nil)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19)).frame(height: 24)
                Text(title).font(.system(size: 10))
            }
            .frame(width: 50, height: 58, alignment: .top).padding(.top, 4)
            .foregroundStyle(Theme.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(help)
    }

    private var insertTab: some View {
        Group {
            RibbonGroup(title: "Import") {
                cmd(CommandCatalog.importItems[0])
                cmd(CommandCatalog.importItems[1])
                smallColumns(Array(CommandCatalog.importItems.dropFirst(2)))
            }
            RibbonGroup(title: "Block & Reference") {
                cmd(CommandCatalog.referenceItems[0])
                smallColumns(Array(CommandCatalog.referenceItems.dropFirst()))
            }
            RibbonGroup(title: "Content") {
                action("Tool Palettes", "square.grid.3x3.square", active: model.showPanels && model.panelTab == .tools, help: "Blocks, components and tools; drag onto the drawing (TOOLPALETTES)") { model.showPanels = true; model.panelTab = .tools }
                action("Materials", "paintpalette", help: "Material library browser (MATBROWSER)") { MaterialLibraryWindow.show(model: model) }
                componentMenu
            }
            RibbonGroup(title: "Export") { smallColumns(CommandCatalog.exportItems) }
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Blocks", symbol: "square.on.square.dashed", sections: [("Blocks & Attributes", CommandCatalog.blocksMore), ("Dynamic Blocks", CommandCatalog.blocksExtra)], help: "Block and attribute tools")
                RibbonCatalogMenu(model: model, title: "Exchange", symbol: "arrow.left.arrow.right.square", sections: [("Import & Export", CommandCatalog.exchange), ("File", CommandCatalog.fileCommands)], help: "More import/export formats and file commands")
            }
            RibbonGroup(title: "Images & Geo") {
                cmd(CommandCatalog.imagesGeo[0])
                smallColumns(Array(CommandCatalog.imagesGeo.dropFirst()))
            }
            RibbonGroup(title: "Library") {
                action("Block Library", "books.vertical", help: "Browse folders of drawings as a block library with thumbnails; drag a block onto the drawing (BLOCKLIBRARY)") { BlockLibraryWindow.show(model: model) }
            }
        }
    }

    private var modelingTab: some View {
        Group {
            RibbonGroup(title: "Solids") {
                cmd(CommandCatalog.solids[0])
                cmd(CommandCatalog.solids[4])
                smallColumns([CommandCatalog.solids[1], CommandCatalog.solids[2], CommandCatalog.solids[3], CommandCatalog.solids[5]], rows: 2)
            }
            RibbonGroup(title: "Solid Editing") {
                cmd(CommandCatalog.modeling[0])
                smallColumns(Array(CommandCatalog.modeling.dropFirst()))
            }
            RibbonGroup(title: "Booleans") {
                ForEach(CommandCatalog.booleans.prefix(3)) { cmd($0) }
                smallColumns(Array(CommandCatalog.booleans.dropFirst(3)), rows: 2)
            }
            RibbonGroup(title: "3D Operations") { smallColumns(CommandCatalog.transform3D) }
            RibbonGroup(title: "Site") {
                cmd(CommandCatalog.site[0])
                smallColumns(Array(CommandCatalog.site.dropFirst()), rows: 2)
            }
            RibbonGroup(title: "Surfaces") { RibbonCatalogMenu(model: model, title: "Surfaces", symbol: "square.stack.3d.up", sections: [("Surfaces & Mesh", CommandCatalog.surfaces), ("Solid Features", CommandCatalog.solidsExtra)], help: "Ruled, tabulated, revolved and edge surfaces; mesh repair") }
            RibbonGroup(title: "Visual Programming") {
                action("Node Editor", "point.3.connected.trianglepath.dotted", help: "Visual node editor with live preview (NODEEDITOR)") { NodeEditorWindow.show(model: model) }
            }
        }
    }

    private var analyzeTab: some View {
        Group {
            RibbonGroup(title: "Inquiry") {
                cmd(CommandCatalog.inquiry[0])
                cmd(CommandCatalog.inquiry[1])
                smallColumns(Array(CommandCatalog.inquiry.dropFirst(2)), rows: 2)
            }
            RibbonGroup(title: "Quantities") {
                cmd(CommandCatalog.analysis[0])
                cmd(CommandCatalog.analysis[1])
                smallColumns(Array(CommandCatalog.analysis.dropFirst(2)), rows: 2)
            }
            RibbonGroup(title: "Coordination") { ForEach(CommandCatalog.coordination) { cmd($0) } }
            RibbonGroup(title: "Checks") {
                cmd(CommandCatalog.checks[0])
                cmd(CommandCatalog.checks[1])
                smallColumns(Array(CommandCatalog.checks.dropFirst(2)), rows: 2)
            }
            RibbonGroup(title: "Measure") { smallColumns(CommandCatalog.inquiryExtra, rows: 2) }
            RibbonGroup(title: "3D Measure") {
                action("Measure 3D", "ruler", active: Measure3DState.shared.active, help: "Pick two points on the 3D model to measure distance, ΔX/ΔY/ΔZ (MEASURE3D)") {
                    if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                    Measure3DState.shared.toggle(); model.revision &+= 1
                }
            }
            RibbonGroup(title: "Building Physics") { RibbonCatalogMenu(model: model, title: "More", symbol: "ellipsis.circle", sections: [("Analysis & Checks", CommandCatalog.analysisMore)], help: "Energy, daylight, acoustics, carbon and code checks") }
        }
    }

    private var collaborateTab: some View {
        Group {
            RibbonGroup(title: "Review") {
                action("Markups", "text.bubble", help: "Markup and comment manager: add, reply, resolve, zoom to (MARKUP)") { MarkupWindow.show(model: model) }
                action("Compare", "rectangle.on.rectangle.angled", help: "Compare this drawing with another version and show the differences as an overlay (COMPARE)") { CompareWindow.show(model: model) }
                smallColumns(Array(CommandCatalog.review.dropFirst(2)))
            }
            RibbonGroup(title: "Versions & Issues") {
                cmd(CommandCatalog.versioning[0])
                cmd(CommandCatalog.versioning[1])
                smallColumns(Array(CommandCatalog.versioning.dropFirst(2)))
            }
            RibbonGroup(title: "Share") {
                action("Share", "square.and.arrow.up", help: "Share the project and a PDF with Mail, Messages, AirDrop… (SHARE)") { model.runCommand("SHARE Both") }
                cmd(CommandCatalog.sharing[0])
                smallColumns(Array(CommandCatalog.sharing.dropFirst()))
            }
            RibbonGroup(title: "Sheets") {
                action("Revision Clouds", "cloud", help: "Revision clouds of the sheets: list, add, zoom to, delete") { RevisionCloudWindow.show(model: model) }
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
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Dims", symbol: "ruler", sections: [("Dimensions", CommandCatalog.dimMore)], help: "Baseline, continue, ordinate, QDIM, dimension editing")
                RibbonCatalogMenu(model: model, title: "Text", symbol: "textformat", sections: [("Text, Leaders & Tables", CommandCatalog.textMore), ("Annotation Extras", CommandCatalog.annotateExtra)], help: "Text editing, spelling, fields, tables, symbols")
            }
            RibbonGroup(title: "Parametric") {
                RibbonCatalogMenu(model: model, title: "Constrain", symbol: "link.circle", sections: [("Parametric", CommandCatalog.parametric)], help: "Geometric and dimensional constraints")
                action("Show Constraints", "eye.square", active: ConstraintGlyphs.isOn(model.doc), help: "Show or hide constraint glyphs in the plan (CONSTRAINTBAR)") { model.runCommand("CONSTRAINTBAR Toggle") }
            }
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
            RibbonGroup(title: "Build+") { smallColumns(Array(CommandCatalog.buildMore.prefix(6))) }
            RibbonGroup(title: "Room & Area") {
                cmd(CommandCatalog.spaces[0])
                cmd(CommandCatalog.spaces[1])
                smallColumns(CommandCatalog.roomsMore)
            }
            RibbonGroup(title: "Documentation") {
                smallColumns(Array(CommandCatalog.documentation.prefix(9)))
                commandMenu("More", "ellipsis.circle", Array(CommandCatalog.documentation.dropFirst(9)) + Array(CommandCatalog.buildMore.dropFirst(6)), help: "More BIM tools")
            }
            RibbonGroup(title: "Model") {
                componentMenu
                cmd(CommandCatalog.spaces[3])
            }
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Systems", symbol: "square.stack.3d.up.fill",
                                  sections: [("BIM Data", CommandCatalog.bimMore), ("BIM Authoring", CommandCatalog.bimAuthoring), ("Structure", CommandCatalog.structure), ("MEP", CommandCatalog.mep), ("Site", CommandCatalog.siteMore)],
                                  help: "BIM data, structure, MEP and site tools")
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
                        ForEach(VisualStyleDef.menuNames(model.doc), id: \.self) { s in
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
            RibbonGroup(title: "3D Tools") {
                action("Section Box", "cube.transparent", active: model.showSectionBoxPanel, help: "Cut the 3D model with a box (SECTIONBOX)") {
                    if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                    model.showSectionBoxPanel.toggle()
                }
                action("Sun Study", "sun.max", active: model.showSunStudy, help: "Animate the sun and shadows (SUNSTUDY)") {
                    if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                    model.showSunStudy.toggle()
                }
                VStack(alignment: .leading, spacing: 1) {
                    action("View Cube", "cube", .small, active: model.showViewCube, help: "Show or hide the view cube (NAVVCUBE)") { model.showViewCube.toggle() }
                    action("Orbit Selection", "scope", .small, enabled: !model.editor.selection.isEmpty, help: "Orbit around and zoom to the selection (ORBITSELECTION)") { model.runCommand("ORBITSELECTION") }
                    action("Save Camera", "camera", .small, help: "Save the 3D camera (SAVECAMERA)") {
                        if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                        model.sheet = .saveCamera
                    }
                }
            }
            RibbonGroup(title: "Presentation") {
                action("Render", "camera.aperture", help: "Render a photorealistic image") { RenderController.renderImage(model: model) }
                action("Walk", "figure.walk", active: model.walkMode, help: "Walk through the model (WASD + mouse)") { model.files.handle(.walkthrough) }
                RibbonCatalogMenu(model: model, title: "Animate", symbol: "film", sections: [("Animation & Export", CommandCatalog.animationItems)], help: "Walkthrough path, sun study video, 360° panorama")
                VStack(alignment: .leading, spacing: 1) {
                    action("Camera Paths", "point.topleft.down.to.point.bottomright.curvepath", .small, help: "Keyframe camera paths with a timeline and video export (CAMERAPATHEDIT)") { CameraPathWindow.show(model: model) }
                    action("Render Queue", "square.stack.3d.forward.dottedline", .small, help: "Queue renders of views and cameras; render history (RENDERQUEUE)") { RenderQueueWindow.show(model: model) }
                    action("Gizmo", "move.3d", .small, active: Gizmo3DState.shared.mode != .off, help: "Move/rotate gizmo on the selection in 3D (GIZMO3D)") {
                        if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                        Gizmo3DState.shared.mode = Gizmo3DState.shared.mode == .off ? .move : .off; model.revision &+= 1
                    }
                }
            }
            RibbonGroup(title: "More") { RibbonCatalogMenu(model: model, title: "View", symbol: "eye", sections: [("View", CommandCatalog.viewMore), ("Views & Graphics", CommandCatalog.viewsExtra)], help: "Every view command") }
            RibbonGroup(title: "Interface") {
                Menu {
                    ForEach(Workspaces.all) { w in
                        Button { Workspaces.apply(w, to: model) } label: {
                            if w.name == Workspaces.currentName { Label(w.name, systemImage: "checkmark") } else { Text(w.name) }
                        }
                    }
                    Divider()
                    Button("Save Current Workspace…") { model.runCommand("WSSAVE") }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "rectangle.3.group").font(.system(size: 19)).frame(height: 24)
                        Text("Workspace").font(.system(size: 10))
                    }
                    .frame(width: 58, height: 58, alignment: .top).padding(.top, 4)
                    .foregroundStyle(Theme.text)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Switch workspace (WSCURRENT)")
                action("Clean Screen", "rectangle.dashed", active: model.cleanScreen, help: "Hide the ribbon and panels (⌃0)") { model.cleanScreen.toggle() }
            }
        }
    }

    private var outputTab: some View {
        Group {
            RibbonGroup(title: "Plot") {
                action("Plot / Print", "printer", help: "Print the drawing or the active sheet (⌘P)") { Plotter.printDrawing(model: model) }
                action("Preview", "eye", help: "Plot dialog with live preview (PREVIEW)") { PlotPreviewWindow.show(model: model) }
                action("Print Setup", "printer.filled.and.paper", help: "Print with printer, paper, tray, scale and copies (PRINTSETUP)") { PrintSetupWindow.show(model: model) }
                VStack(alignment: .leading, spacing: 1) {
                    action("Page Setup", "doc.badge.gearshape", .small, help: "Paper, plot style, lineweights, plot stamp (PAGESETUP)") {
                        model.sheet = .pageSetup(model.mode == .sheet ? model.activeLayout : -1)
                    }
                    action("Export PDF", "doc.richtext", .small, help: "Export the drawing or the active sheet as vector PDF") { model.files.export(format: "pdf", path: nil) }
                    action("Publish", "doc.on.doc", .small, enabled: !model.doc.layouts.isEmpty, help: "All sheets in one PDF (PUBLISH)") { Plotter.publish(model: model, path: nil) }
                }
            }
            RibbonGroup(title: "Sheets") {
                action("Title Block", "list.bullet.rectangle.portrait", enabled: !model.doc.layouts.isEmpty, help: "Edit the title block and project info (TITLEBLOCK)") {
                    model.mode = .sheet
                    model.sheet = .titleBlock(min(max(model.activeLayout, 0), max(model.doc.layouts.count - 1, 0)))
                }
                action("Sheet Set", "rectangle.stack", active: model.showPanels && model.panelTab == .sheets, help: "Sheet set manager: numbering, order, index, revisions (SHEETSET)") {
                    model.showPanels = true; model.panelTab = .sheets
                }
                VStack(alignment: .leading, spacing: 1) {
                    action("View Titles", "textformat.size", .small, enabled: !model.doc.layouts.isEmpty, help: "Add or refresh view titles under the viewports of the active sheet (VIEWTITLE)") {
                        let li = min(max(model.activeLayout, 0), max(model.doc.layouts.count - 1, 0))
                        if model.doc.layouts.indices.contains(li) { model.runCommand("VIEWTITLE \(model.doc.layouts[li].name)") }
                    }
                    action("Revision", "clock.badge.checkmark", .small, enabled: !model.doc.layouts.isEmpty, help: "Add a revision to the active sheet (SHEETREVISION)") {
                        model.showPanels = true; model.panelTab = .sheets
                    }
                    action("Sheet Index", "list.number", .small, enabled: !model.doc.layouts.isEmpty, help: "Place or refresh the sheet list table on the active sheet (SHEETINDEX)") {
                        model.runCommand("SHEETINDEX")
                    }
                }
            }
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Output", symbol: "printer.dotmatrix", sections: [("Output", CommandCatalog.outputMore), ("Plot Styles", CommandCatalog.plotItems)], help: "Every output command, plot styles, batch publish")
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
                action("Tools", "square.grid.3x3.square", active: model.showPanels && model.panelTab == .tools, help: "Tool palettes") { model.showPanels = true; model.panelTab = .tools }
                action("Materials", "paintpalette", active: model.showPanels && model.panelTab == .materials, help: "Materials") { model.showPanels = true; model.panelTab = .materials }
            }
            RibbonGroup(title: "Settings") {
                action("Units", "ruler", help: "Drawing units") { model.sheet = .units }
                action("Drafting", "slider.horizontal.3", help: "Drafting settings: grid, snap, polar, object snaps") { model.sheet = .drafting }
                action("Options", "gearshape", help: "Application settings (OPTIONS, ⌘,)") { PreferencesWindow.show() }
            }
            RibbonGroup(title: "History") {
                action("History", "clock.arrow.circlepath", active: model.showPanels && model.panelTab == .history, help: "Undo history and command history") { model.showPanels = true; model.panelTab = .history }
            }
            RibbonGroup(title: "Cleanup") {
                action("Purge", "trash.slash", help: "Remove unused layers, blocks and styles") { model.purge() }
                action("Audit", "checkmark.shield", help: "Check the drawing for errors and fix them") { model.audit() }
            }
            RibbonGroup(title: "More") {
                RibbonCatalogMenu(model: model, title: "Settings", symbol: "gearshape.2", sections: [("Settings", CommandCatalog.settingsMore), ("System Variables", CommandCatalog.variableItems)], help: "Settings and system variables")
                RibbonCatalogMenu(model: model, title: "Tools", symbol: "wrench.and.screwdriver", sections: [("Tools & Scripting", CommandCatalog.tools), ("Help", CommandCatalog.helpCommands)], help: "Action recorder, aliases, scripting, help")
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
                Menu {
                    let scripts = ScriptLibrary.scripts()
                    if scripts.isEmpty { Text("No scripts in the library yet") }
                    ForEach(scripts, id: \.self) { u in Button(u.lastPathComponent) { model.runScriptFile(u) } }
                    Divider()
                    Button("Open Script Library Folder") { ScriptLibrary.revealFolder() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "books.vertical").font(.system(size: 19)).frame(height: 24)
                        Text("Library").font(.system(size: 10))
                    }
                    .frame(width: 50, height: 58, alignment: .top).padding(.top, 4)
                    .foregroundStyle(Theme.text)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Run a script from the library (startup.js runs in every new window)")
            }
            RibbonGroup(title: "Automation") {
                RibbonCatalogMenu(model: model, title: "Tools", symbol: "wrench.and.screwdriver", sections: [("Tools & Scripting", CommandCatalog.tools), ("Script Control", CommandCatalog.scriptingExtra)], help: "Action recorder, script recorder, aliases, macros")
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
                    HStack(spacing: 4) {
                        if model.agentRunning {
                            Button("Copy token") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(AgentServer.shared.token, forType: .string)
                            }
                            .buttonStyle(FlatButtonStyle(compact: true))
                            .help("Copy the session token agents must send")
                        }
                        Button("Settings…") { PreferencesWindow.show(.agents) }.buttonStyle(FlatButtonStyle(compact: true))
                    }
                }
                .padding(.top, 6)
                action("Connect Claude", "sparkles", help: "How to connect Claude with archi-cli --mcp") { model.sheet = .connectClaude }
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
