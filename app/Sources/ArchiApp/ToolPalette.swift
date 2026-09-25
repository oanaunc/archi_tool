// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// Tool palettes (TOOLPALETTES): grouped command tiles plus a user palette. Every tile runs the command like typing it.
struct ToolPalettePanel: View {
    @ObservedObject var model: AppModel
    @AppStorage("toolPalette.custom") private var customRaw = "WALL,DOOR,WINDOW,ROOM,DIMLINEAR,HATCH"
    @AppStorage("toolPalette.tab") private var tab = "Draw"
    @State private var newCommand = ""

    private var custom: [String] { customRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }

    static let palettes: [(String, [CmdItem])] = [
        ("Draw", CommandCatalog.draw),
        ("Modify", CommandCatalog.modify),
        ("Annotate", CommandCatalog.text + CommandCatalog.dimensions),
        ("Build", CommandCatalog.build + CommandCatalog.spaces),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(ToolPalettePanel.palettes.map(\.0) + ["Blocks", "Components", "My Tools"], id: \.self) { t in
                        Button { tab = t } label: {
                            Text(t).font(.system(size: 10.5, weight: tab == t ? .semibold : .regular))
                                .foregroundStyle(tab == t ? Theme.accentText : Theme.text)
                                .padding(.horizontal, 8).frame(height: 22)
                                .background(RoundedRectangle(cornerRadius: 4).fill(tab == t ? Theme.accent : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            HSeparator()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                    switch tab {
                    case "Blocks":
                        let names = model.doc.blocks.keys.filter { !$0.hasPrefix("*") }.sorted()
                        if names.isEmpty {
                            Text("No blocks in this drawing. Create one with BLOCK or insert a drawing with INSERT.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        }
                        ForEach(names, id: \.self) { n in
                            ShapeTile(title: n, shapes: BlockThumb.shapes(n, doc: model.doc), help: "Click to insert \(n) · drag onto the drawing to place it") {
                                model.runCommand("INSERT \(n)")
                            }
                            .onDrag { NSItemProvider(object: (ToolDrop.blockPrefix + n) as NSString) }
                        }
                    case "Components":
                        ForEach(ComponentLibrary.families, id: \.id) { f in
                            ShapeTile(title: f.name, shapes: BlockThumb.shapes(f), help: "\(f.category) · \(fmt(f.size.x, 0))×\(fmt(f.size.y, 0))×\(fmt(f.size.z, 0)) — click to place, or drag onto the drawing") {
                                if let r = model.command(["COMPONENT"]) { model.runCommand("\(r) \(f.name.replacingOccurrences(of: " ", with: ""))") }
                            }
                            .onDrag { NSItemProvider(object: (ToolDrop.componentPrefix + f.id) as NSString) }
                        }
                    case "My Tools":
                        ForEach(custom, id: \.self) { n in
                            let def = model.editor.registry.lookup(n)
                            tile(n.capitalized, QuickAccess.symbol(for: n), help: def?.summary ?? "Not available", enabled: def != nil) { model.runCommand(n) }
                                .onDrag { NSItemProvider(object: (ToolDrop.commandPrefix + n) as NSString) }
                                .onDrop(of: [.plainText, .utf8PlainText], isTargeted: nil) { providers in reorder(onto: n, providers) }
                                .contextMenu {
                                    Button("Remove from My Tools") { customRaw = custom.filter { $0 != n }.joined(separator: ",") }
                                }
                        }
                    default:
                        ForEach(ToolPalettePanel.palettes.first { $0.0 == tab }?.1 ?? [], id: \.id) { item in
                            let r = model.command(item.names)
                            tile(item.title, item.symbol, help: r.flatMap { model.editor.registry.lookup($0)?.summary } ?? "Not available in this build", enabled: r != nil) {
                                if let r { model.runCommand(item.args.isEmpty ? r : r + " " + item.args) }
                            }
                            .onDrag { NSItemProvider(object: (ToolDrop.commandPrefix + (r ?? item.names[0])) as NSString) }
                            .contextMenu { Button("Add to My Tools") { if let r, !custom.contains(r) { customRaw = (custom + [r]).joined(separator: ",") } } }
                        }
                    }
                }
                .padding(8)
            }
            .background(Theme.panel)
            .onDrop(of: [.plainText, .utf8PlainText], isTargeted: nil) { providers in
                guard tab == "My Tools", let p = providers.first else { return false }
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let str = obj as? String, str.hasPrefix(ToolDrop.commandPrefix) else { return }
                    let name = String(str.dropFirst(ToolDrop.commandPrefix.count))
                    DispatchQueue.main.async { if !custom.contains(name) { customRaw = (custom + [name]).joined(separator: ",") } }
                }
                return true
            }
            if tab == "My Tools" {
                HSeparator()
                HStack(spacing: 4) {
                    TextField("Add command (e.g. OFFSET)", text: $newCommand).darkField().onSubmit(add)
                    Button("Add", action: add).buttonStyle(FlatButtonStyle(compact: true))
                }
                .padding(8)
            }
            HSeparator()
            Text(tab == "My Tools" ? "Drag tiles here from other palettes · drag within to reorder" : "Click to start · drag onto the drawing · right-click to add to My Tools")
                .font(Theme.fontSmall).foregroundStyle(Theme.textFaint).padding(6)
        }
        .background(Theme.panel)
    }

    /// Drop of a tool tile on a My Tools tile: adds a new tool or moves an existing one before the target.
    private func reorder(onto target: String, _ providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let str = obj as? String, str.hasPrefix(ToolDrop.commandPrefix) else { return }
            let name = String(str.dropFirst(ToolDrop.commandPrefix.count))
            DispatchQueue.main.async {
                var list = custom.filter { $0 != name }
                let i = list.firstIndex(of: target) ?? list.count
                list.insert(name, at: i)
                customRaw = list.joined(separator: ",")
            }
        }
        return true
    }

    private func add() {
        guard let def = model.editor.registry.lookup(newCommand.trimmingCharacters(in: .whitespaces)) else { NSSound.beep(); return }
        if !custom.contains(def.name) { customRaw = (custom + [def.name]).joined(separator: ",") }
        newCommand = ""
    }

    private func tile(_ title: String, _ symbol: String, help: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        ToolTile(title: title, symbol: symbol, enabled: enabled, action: action).help(help)
    }
}

private struct ToolTile: View {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17)).frame(height: 22)
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(enabled ? Theme.text : Theme.textFaint)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering && enabled ? Theme.hover : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(hovering && enabled ? Theme.accent.opacity(0.6) : Theme.separator))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

// MARK: - Drag and drop payloads

/// Tool palette drags carry a prefixed string; the plan canvas places the item where it is dropped.
@MainActor
enum ToolDrop {
    static let blockPrefix = "archi-block:"
    static let componentPrefix = "archi-component:"
    static let commandPrefix = "archi-command:"
    static let materialPrefix = "archi-material:"
    /// Block library item: "archi-libblock:<file path>␟<block name or empty>".
    static let libraryBlockPrefix = "archi-libblock:"

    static func accepts(_ s: String) -> Bool { [blockPrefix, componentPrefix, commandPrefix, materialPrefix, libraryBlockPrefix].contains { s.hasPrefix($0) } }

    /// Places a dropped item at a world point. One undo step per drop. Returns false when nothing happened.
    @discardableResult
    static func drop(_ s: String, at p: Vec2, onto hit: EntityID?, model: AppModel) -> Bool {
        if s.hasPrefix(libraryBlockPrefix) {
            guard let item = BlockLibraryStore.item(fromKey: String(s.dropFirst(libraryBlockPrefix.count))) else { return false }
            return BlockLibraryStore.shared.insert(item, at: p, model: model) != nil
        }
        if s.hasPrefix(blockPrefix) {
            let name = String(s.dropFirst(blockPrefix.count))
            guard model.doc.blocks[name] != nil else { return false }
            var id: EntityID = 0
            model.editor.transaction("Insert \(name)") { id = $0.add(.insert(InsertGeom(block: name, position: p)), layer: $0.currentLayer) }
            model.editor.selection = [id]
            model.editor.print("Inserted block \(name) at \(fmt(p.x, 2)),\(fmt(p.y, 2)).")
            return true
        }
        if s.hasPrefix(componentPrefix) {
            guard let f = ComponentLibrary.family(String(s.dropFirst(componentPrefix.count))) else { return false }
            var id: EntityID = 0
            model.editor.transaction("Place \(f.name)") { d in
                ComponentLibrary.ensureMaterials(&d)
                id = d.addElement(.component(ComponentGeom(category: f.category, position: p, rotation: 0, size: f.size, baseOffset: f.baseOffset, family: f.id)), name: f.name)
            }
            model.editor.selection = [id]
            model.editor.print("Placed \(f.name.lowercased()) at \(fmt(p.x, 2)),\(fmt(p.y, 2)).")
            return true
        }
        if s.hasPrefix(commandPrefix) {
            let n = String(s.dropFirst(commandPrefix.count))
            guard model.has(n.split(separator: " ").first.map(String.init) ?? n) else { return false }
            model.runCommand(n)
            return true
        }
        if s.hasPrefix(materialPrefix) {
            let name = String(s.dropFirst(materialPrefix.count))
            guard let hit, model.doc.elements.contains(where: { $0.id == hit }) else { model.editor.print("Drop a material on a building element."); return false }
            let lib = MaterialLibrary.items.first { $0.material.name == name }
            model.editor.transaction("Assign Material") { d in
                if d.material(name) == nil, let lib { MaterialLibrary.add([lib], to: &d) }
                if let i = d.elements.firstIndex(where: { $0.id == hit }) { d.elements[i].material = name }
            }
            model.editor.print("\(name) assigned.")
            return true
        }
        return false
    }
}

/// Line thumbnails of blocks and library components.
@MainActor
enum BlockThumb {
    static func shapes(_ block: String, doc: ArchiDocument) -> [[Vec2]] {
        Array(GeometryOps.tessellate(.insert(InsertGeom(block: block, position: .zero)), doc: doc).prefix(400))
    }
    static func shapes(_ f: ComponentFamily) -> [[Vec2]] {
        ComponentLibrary.worldSymbol(f, ComponentGeom(category: f.category, position: .zero, size: f.size, family: f.id)).map { $0.closed && !$0.points.isEmpty ? $0.points + [$0.points[0]] : $0.points }
    }
}

private struct ShapeTile: View {
    let title: String
    let shapes: [[Vec2]]
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Canvas { ctx, size in
                    var b = BBox2.empty
                    for s in shapes { for p in s { b.add(p) } }
                    guard !b.isEmpty else { return }
                    let k = min((size.width - 6) / max(b.width, 1e-9), (size.height - 6) / max(b.height, 1e-9))
                    var path = Path()
                    for s in shapes where s.count >= 2 {
                        func m(_ p: Vec2) -> CGPoint { CGPoint(x: size.width / 2 + (p.x - b.center.x) * k, y: size.height / 2 - (p.y - b.center.y) * k) }
                        path.move(to: m(s[0])); for p in s.dropFirst() { path.addLine(to: m(p)) }
                    }
                    ctx.stroke(path, with: .color(Theme.text), lineWidth: 1)
                }
                .frame(height: 40)
                Text(title).font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity).frame(height: 62)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(hovering ? Theme.accent.opacity(0.6) : Theme.separator))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
