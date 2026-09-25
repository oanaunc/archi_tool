// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
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
                    ForEach(ToolPalettePanel.palettes.map(\.0) + ["Furniture", "My Tools"], id: \.self) { t in
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
                    case "Furniture":
                        ForEach(CommandCatalog.furniture, id: \.0) { name, sym in
                            tile(name, sym, help: "Place \(name.lowercased())") { if let r = model.command(["COMPONENT"]) { model.runCommand("\(r) \(name)") } }
                        }
                    case "My Tools":
                        ForEach(custom, id: \.self) { n in
                            let def = model.editor.registry.lookup(n)
                            tile(n.capitalized, QuickAccess.symbol(for: n), help: def?.summary ?? "Not available", enabled: def != nil) { model.runCommand(n) }
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
                            .contextMenu { Button("Add to My Tools") { if let r, !custom.contains(r) { customRaw = (custom + [r]).joined(separator: ",") } } }
                        }
                    }
                }
                .padding(8)
            }
            .background(Theme.panel)
            if tab == "My Tools" {
                HSeparator()
                HStack(spacing: 4) {
                    TextField("Add command (e.g. OFFSET)", text: $newCommand).darkField().onSubmit(add)
                    Button("Add", action: add).buttonStyle(FlatButtonStyle(compact: true))
                }
                .padding(8)
            }
            HSeparator()
            Text("Click a tool to start it · right-click to add it to My Tools").font(Theme.fontSmall).foregroundStyle(Theme.textFaint).padding(6)
        }
        .background(Theme.panel)
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
