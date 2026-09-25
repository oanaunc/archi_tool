// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Quick Select dialog (QSELECT with a dialog)

struct QuickSelectSheet: View {
    @ObservedObject var model: AppModel
    @State private var scope = 0          // 0 = whole drawing (current level), 1 = current selection
    @State private var type = "*"
    @State private var property = "*"
    @State private var op: ObjectQuery.Op = .eq
    @State private var value = ""
    @State private var mode = "New"

    static let properties = ["*", "layer", "color", "linetype", "lineweight", "length", "area", "radius", "height", "contents", "name", "material", "level", "x", "y"]

    private var candidates: [EntityID] {
        let ed = model.editor
        if scope == 1 { return Array(ed.selection) }
        return model.doc.entities.filter { ed.isSelectable($0.id) }.map(\.id)
            + model.doc.elements.filter { ed.isSelectable($0.id) && $0.level == model.doc.currentLevel }.map(\.id)
    }

    private var types: [String] {
        let d = model.doc
        let ids = d.entities.map(\.id) + d.elements.filter { $0.level == d.currentLevel }.map(\.id)
        return ["*"] + Array(Set(ids.compactMap { ObjectQuery.typeName($0, doc: d) })).sorted()
    }

    private var matches: [EntityID] {
        let d = model.doc
        var ids = candidates.filter { ObjectQuery.typeMatches($0, type, doc: d) }
        if property != "*" {
            let c = ObjectQuery.Criterion(property, op, value)
            ids = ids.filter { c.matches($0, doc: d) }
        }
        return ids
    }

    var body: some View {
        let hits = matches
        VStack(spacing: 0) {
            HStack { Text("Quick Select").font(.system(size: 13, weight: .semibold)); Spacer() }.padding(14)
            HSeparator()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                GridRow {
                    Text("Apply to").foregroundStyle(Theme.textDim)
                    Picker("", selection: $scope) {
                        Text("Current level").tag(0)
                        Text("Current selection (\(model.editor.selection.count))").tag(1)
                    }.labelsHidden().frame(width: 240)
                }
                GridRow {
                    Text("Object type").foregroundStyle(Theme.textDim)
                    Picker("", selection: $type) { ForEach(types, id: \.self) { Text($0 == "*" ? "Multiple (all types)" : $0.capitalized).tag($0) } }
                        .labelsHidden().frame(width: 240)
                }
                GridRow {
                    Text("Property").foregroundStyle(Theme.textDim)
                    Picker("", selection: $property) { ForEach(QuickSelectSheet.properties, id: \.self) { Text($0 == "*" ? "None (type only)" : $0.capitalized).tag($0) } }
                        .labelsHidden().frame(width: 240)
                }
                if property != "*" {
                    GridRow {
                        Text("Operator").foregroundStyle(Theme.textDim)
                        Picker("", selection: $op) { ForEach(ObjectQuery.Op.allCases, id: \.self) { Text(opName($0)).tag($0) } }
                            .labelsHidden().frame(width: 240)
                    }
                    GridRow {
                        Text("Value").foregroundStyle(Theme.textDim)
                        HStack(spacing: 4) {
                            TextField(property == "layer" ? "Layer name or wildcard (A-*)" : "Value (wildcards * ? allowed for text)", text: $value)
                                .darkField().frame(width: 200)
                            if property == "layer" {
                                Menu { ForEach(model.doc.layers, id: \.name) { l in Button(l.name) { value = l.name } } } label: { Image(systemName: "chevron.down") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                        }
                    }
                }
                GridRow {
                    Text("How to apply").foregroundStyle(Theme.textDim)
                    Picker("", selection: $mode) {
                        Text("Replace the selection").tag("New")
                        Text("Add to the selection").tag("Append")
                        Text("Remove from the selection").tag("Exclude")
                    }.labelsHidden().pickerStyle(.radioGroup)
                }
            }
            .padding(14)
            HSeparator()
            HStack {
                Text("\(hits.count) object(s) match").foregroundStyle(hits.isEmpty ? Theme.textDim : Theme.accent)
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Select") { apply(hits) }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .font(Theme.font)
        .frame(width: 440)
        .background(Theme.panel)
        .onAppear { if model.editor.selection.count > 1 { scope = 0 } }
    }

    private func opName(_ o: ObjectQuery.Op) -> String {
        switch o {
        case .eq: return "= Equals"
        case .ne: return "≠ Not equal"
        case .gt: return "> Greater than"
        case .lt: return "< Less than"
        case .ge: return "≥ Greater or equal"
        case .le: return "≤ Less or equal"
        }
    }

    private func apply(_ ids: [EntityID]) {
        let ed = model.editor
        switch mode {
        case "Append": ed.selection.formUnion(ids)
        case "Exclude": ed.selection.subtract(ids)
        default: ed.selection = Set(ids)
        }
        ed.previousSelection = ed.selection
        let crit = property == "*" ? "*" : "\(property) \(op.rawValue) \(value.contains(" ") ? "\"\(value)\"" : value)"
        ed.print("QSELECT \(type) \(crit) → \(ids.count) matched; \(ed.selection.count) selected.")
        model.sheet = nil
        model.revision &+= 1
    }
}

// MARK: - Layer States Manager (LAYERSTATE)

struct LayerStatesSheet: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var newName = ""
    @State private var renaming = ""

    var body: some View {
        let names = LayerStates.names(model.doc)
        VStack(spacing: 0) {
            HStack { Text("Layer States Manager").font(.system(size: 13, weight: .semibold)); Spacer() }.padding(14)
            HSeparator()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if names.isEmpty {
                        Text("No layer states yet. Save the current layer settings below.").foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(names, id: \.self) { n in
                                    let st = LayerStates.state(n, in: model.doc)
                                    HStack {
                                        Image(systemName: "rectangle.stack").foregroundStyle(Theme.accent)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(n).font(Theme.fontBold)
                                            Text("\(st?.layers.count ?? 0) layers\(st?.date.map { " · " + DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "")")
                                                .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8).frame(height: 34)
                                    .background(selected == n ? Theme.accent.opacity(0.14) : Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = n; renaming = n }
                                    .onTapGesture(count: 2) { restore(n) }
                                }
                            }
                        }
                    }
                }
                .frame(width: 280, height: 220)
                .background(Theme.field)
                .overlay(Rectangle().stroke(Theme.separator))
                VStack(alignment: .leading, spacing: 6) {
                    Button("Restore") { if let s = selected { restore(s) } }.buttonStyle(FlatButtonStyle(prominent: true)).disabled(selected == nil)
                    Button("Update") { if let s = selected { save(s) } }.buttonStyle(FlatButtonStyle()).disabled(selected == nil)
                        .help("Overwrite the state with the current layer settings")
                    Button("Delete") { delete() }.buttonStyle(FlatButtonStyle()).disabled(selected == nil)
                    if selected != nil {
                        TextField("Rename", text: $renaming).darkField().frame(width: 120).onSubmit(rename)
                    }
                    Spacer()
                }
            }
            .padding(14)
            HStack(spacing: 6) {
                TextField("New state name", text: $newName).darkField().frame(width: 200).onSubmit { save(newName) }
                Button("Save Current Layers") { save(newName) }.buttonStyle(FlatButtonStyle()).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.bottom, 10)
            HSeparator()
            HStack {
                Text("States are saved in the drawing and restore on/off, freeze, lock, plot, color, linetype and lineweight.")
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Close") { model.sheet = nil }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .font(Theme.font)
        .frame(width: 470)
        .background(Theme.panel)
    }

    private func save(_ raw: String) {
        let n = raw.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        model.editor.transaction("Save Layer State") { LayerStates.save(n, in: &$0) }
        selected = n.uppercased(); renaming = selected ?? ""; newName = ""
        model.editor.print("Layer state \(n.uppercased()) saved.")
    }
    private func restore(_ n: String) {
        var changed = 0
        model.editor.transaction("Restore Layer State") { changed = LayerStates.restore(n, in: &$0) ?? 0 }
        model.editor.print("Layer state \(n) restored (\(changed) layer(s) changed).")
        model.canvas?.invalidateCache()
    }
    private func delete() {
        guard let s = selected else { return }
        model.editor.transaction("Delete Layer State") { LayerStates.delete(s, in: &$0) }
        selected = nil
    }
    private func rename() {
        guard let s = selected else { return }
        let n = renaming.trimmingCharacters(in: .whitespaces).uppercased()
        guard !n.isEmpty, n != s, !LayerStates.names(model.doc).contains(n) else { return }
        model.editor.transaction("Rename Layer State") { LayerStates.rename(s, to: n, in: &$0) }
        selected = n
    }
}

// MARK: - Command search palette (⌘K)

enum CommandSearch {
    /// Ranks commands for a query: exact name/alias, then name prefix (shorter first), alias prefix, name contains, summary words.
    static func rank(_ query: String, registry: CommandRegistry, limit: Int = 12) -> [CommandDef] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return [] }
        var scored: [(Int, CommandDef)] = []
        for c in registry.commands.values {
            var s = Int.max
            if c.name == q { s = 0 }
            else if c.aliases.contains(q) { s = 1 }
            else if c.name.hasPrefix(q) { s = 10 + c.name.count }
            else if c.aliases.contains(where: { $0.hasPrefix(q) }) { s = 60 + c.name.count }
            else if c.name.contains(q) { s = 120 + c.name.count }
            else if c.summary.uppercased().contains(q) { s = 300 + c.name.count }
            else if c.category.uppercased().hasPrefix(q) { s = 500 + c.name.count }
            if s != Int.max { scored.append((s, c)) }
        }
        return scored.sorted { ($0.0, $0.1.name) < ($1.0, $1.1.name) }.prefix(limit).map(\.1)
    }
}

struct CommandSearchPalette: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = CommandSearch.rank(query, registry: model.editor.registry)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                TextField("Search commands (e.g. wal, hatch, plot)…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($focused)
                    .onSubmit { if results.indices.contains(index) { run(results[index]) } }
                    .onChange(of: query) { _ in index = 0 }
                Text("esc").font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
            }
            .padding(12)
            if !results.isEmpty {
                HSeparator()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.offset) { i, c in
                            Button { run(c) } label: {
                                HStack(spacing: 10) {
                                    Text(c.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(i == index ? Theme.accentText : Theme.accent).frame(width: 150, alignment: .leading)
                                    Text(c.summary).font(Theme.font).foregroundStyle(i == index ? Theme.accentText : Theme.text).lineLimit(1)
                                    Spacer()
                                    Text(c.aliases.prefix(3).joined(separator: " ")).font(Theme.mono).foregroundStyle(i == index ? Theme.accentText.opacity(0.7) : Theme.textFaint)
                                }
                                .padding(.horizontal, 12).frame(height: 28)
                                .background(i == index ? Theme.accent : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { if $0 { index = i } }
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 620)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        .onAppear { focused = true }
        .onExitCommand { model.showCommandSearch = false }
        .background(KeyArrowCatcher(onUp: { index = max(0, index - 1) }, onDown: { index = min(max(results.count - 1, 0), index + 1) }))
    }

    private func run(_ c: CommandDef) {
        model.showCommandSearch = false
        model.runCommand(c.name)
    }
}

/// Up/down arrows while the palette's text field has focus.
private struct KeyArrowCatcher: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.install()
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { context.coordinator.parent = self }
    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) { coordinator.remove() }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        var parent: KeyArrowCatcher
        var monitor: Any?
        init(_ p: KeyArrowCatcher) { parent = p }
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self else { return e }
                if e.keyCode == 126 { self.parent.onUp(); return nil }
                if e.keyCode == 125 { self.parent.onDown(); return nil }
                return e
            }
        }
        func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
    }
}
