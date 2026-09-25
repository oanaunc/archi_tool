// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Right-side docked panels (Properties, Layers, Levels, Project Browser, Materials).
struct PanelsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let floating = FloatingPanels.floatingTabs(model)
        let tabs = PanelTab.allCases.filter { !floating.contains($0) }
        let current = tabs.contains(model.panelTab) ? model.panelTab : (tabs.first ?? .properties)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs) { t in
                    Button { model.panelTab = t } label: {
                        VStack(spacing: 2) {
                            Image(systemName: t.symbol).font(.system(size: 12))
                            Text(t.rawValue).font(.system(size: 8.5)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(current == t ? Theme.accent : Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(current == t ? Theme.hover : Color.clear)
                        .overlay(alignment: .bottom) { if current == t { Rectangle().fill(Theme.accent).frame(height: 2) } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.rawValue + " — right-click to float")
                    .contextMenu { Button("Float \(t.rawValue) Panel") { FloatingPanels.float(t, model: model) } }
                }
                VStack(spacing: 0) {
                    IconButton(symbol: "macwindow.on.rectangle", help: "Float this panel in its own window (FLOATPANEL)") { FloatingPanels.float(current, model: model) }
                        .disabled(tabs.isEmpty)
                    IconButton(symbol: "xmark", help: "Hide panels") { model.showPanels = false }
                }
                .padding(.horizontal, 2)
            }
            .background(Theme.ribbonTabBar)
            HSeparator()
            Group {
                if tabs.isEmpty {
                    Text("All panels are floating.").font(Theme.font).foregroundStyle(Theme.textDim).padding()
                } else {
                    PanelContent(model: model, tab: current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.panel)
    }
}

// MARK: - Properties

private func humanize(_ name: String) -> String {
    var out = ""
    for (i, ch) in name.enumerated() {
        if ch == "." || ch == "_" { out.append(" "); continue }
        if ch.isUppercase && i > 0 && !(out.last?.isWhitespace ?? true) { out.append(" ") }
        out.append(i == 0 ? Character(ch.uppercased()) : ch)
    }
    return out.replacingOccurrences(of: "Id", with: "ID")
}

struct PropertiesPanel: View {
    @ObservedObject var model: AppModel

    private struct Row: Identifiable { var id: String { name }; var name: String; var value: String; var readOnly: Bool }

    private var rows: [Row] {
        let ids = model.selectedIDs
        guard !ids.isEmpty else { return [] }
        let doc = model.doc
        let limited = ids.prefix(300)
        var result: [Row] = []
        var first = true
        var map: [String: (String, Bool, Int)] = [:]
        for id in limited {
            let ps = PropertyAccess.properties(of: id, in: doc)
            if first {
                result = ps.map { Row(name: $0.name, value: $0.value, readOnly: $0.readOnly) }
                for (i, p) in ps.enumerated() { map[p.name] = (p.value, p.readOnly, i) }
                first = false
            } else {
                let names = Set(ps.map(\.name))
                result.removeAll { !names.contains($0.name) }
                for p in ps {
                    if let k = result.firstIndex(where: { $0.name == p.name }) {
                        if result[k].value != p.value { result[k].value = "*VARIES*" }
                        if p.readOnly { result[k].readOnly = true }
                    }
                }
            }
        }
        if ids.count > 1 { result.removeAll { $0.name == "id" } }
        return result
    }

    private var typeCounts: [(String, Int)] {
        let doc = model.doc
        let types = model.selectedIDs.compactMap { doc.entity($0)?.typeName ?? doc.element($0)?.typeName }
        return Dictionary(grouping: types, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func narrow(to type: String) {
        let doc = model.doc
        model.editor.selection = Set(model.selectedIDs.filter { (doc.entity($0)?.typeName ?? doc.element($0)?.typeName) == type })
    }

    private func zoomToSelection() {
        let doc = model.doc
        var b = BBox2.empty
        for e in model.selectedEntities { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
        for el in model.selectedElements { for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) } }
        guard !b.isEmpty else { return }
        if model.mode == .model { model.viewport3D?.orbitSelection(model.editor.selection, frame: true); return }
        let pad = max(b.width, b.height) * 0.15 + 100
        model.canvas?.zoom(to: b.expanded(by: pad))
    }

    private var typeSummary: String {
        let doc = model.doc
        let types = model.selectedIDs.compactMap { doc.entity($0)?.typeName ?? doc.element($0)?.typeName }
        let counts = Dictionary(grouping: types, by: { $0 }).mapValues(\.count)
        if counts.count == 1, let (t, n) = counts.first { return n == 1 ? t.capitalized : "\(n) × \(t.capitalized)" }
        return "\(types.count) objects (" + counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.editor.selection.isEmpty {
                    documentInfo
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        let counts = typeCounts
                        if counts.count > 1 {
                            // Narrow a mixed selection to one object type (AutoCAD Properties drop-down).
                            Menu {
                                ForEach(counts, id: \.0) { t, n in
                                    Button("\(t.capitalized) (\(n))") { narrow(to: t) }
                                }
                            } label: { Text(typeSummary).font(Theme.fontBold).lineLimit(2) }
                            .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
                            .help("Keep only one object type in the selection")
                        } else {
                            Text(typeSummary).font(Theme.fontBold).foregroundStyle(Theme.text).lineLimit(2)
                        }
                        Spacer()
                        IconButton(symbol: "xmark.circle", help: "Clear selection") { model.editor.selection = [] }
                    }
                    .padding(.horizontal, 10).padding(.top, 8)
                    HStack(spacing: 2) {
                        IconButton(symbol: "line.3.horizontal.decrease.circle", help: "Quick Select…") { model.sheet = .quickSelect }
                        IconButton(symbol: "paintbrush.pointed", help: "Match properties from the first selected object (MATCHPROP)") { model.runCommand("MATCHPROP") }
                            .disabled(!model.has("MATCHPROP"))
                        IconButton(symbol: "square.on.square.intersection.dashed", help: "Select similar objects (SELECTSIMILAR)") { model.runCommand("SELECTSIMILAR") }
                            .disabled(!model.has("SELECTSIMILAR"))
                        IconButton(symbol: "arrow.left.arrow.right.square", help: "Invert the selection (SELECTINVERT)") { model.runCommand("SELECTINVERT") }
                            .disabled(!model.has("SELECTINVERT"))
                        IconButton(symbol: "scope", help: "Zoom to the selection") { zoomToSelection() }
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.top, 2)
                    let rs = rows
                    let general = ["id", "type", "name", "layer", "color", "linetype", "lineweight", "material", "level"]
                    PanelHeader(title: "General")
                    ForEach(rs.filter { general.contains($0.name) }) { row($0) }
                    let geo = rs.filter { !general.contains($0.name) }
                    if !geo.isEmpty {
                        PanelHeader(title: "Geometry & Parameters")
                        ForEach(geo) { row($0) }
                    }
                    if model.selectedIDs.count > 1 {
                        Text("Editing a field changes all \(model.selectedIDs.count) selected objects.")
                            .font(Theme.fontSmall).foregroundStyle(Theme.textFaint).padding(10)
                    }
                    }
                    .id(model.selectedIDs)
                }
            }
        }
    }

    @ViewBuilder private func row(_ r: Row) -> some View {
        HStack(spacing: 6) {
            Text(humanize(r.name))
                .font(Theme.font)
                .foregroundStyle(Theme.textDim)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
            editor(for: r)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
    }

    @ViewBuilder private func editor(for r: Row) -> some View {
        let doc = model.doc
        if r.readOnly {
            Text(r.value).font(Theme.font).foregroundStyle(Theme.text).textSelection(.enabled).lineLimit(1)
        } else {
            switch r.name {
            case "layer":
                Menu {
                    ForEach(doc.layers, id: \.name) { l in Button(l.name) { set(r.name, l.name) } }
                } label: { Text(r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            case "color":
                Menu {
                    Button("ByLayer") { set("color", "ByLayer") }
                    Button("ByBlock") { set("color", "ByBlock") }
                    ForEach(basicColors, id: \.0) { n, c in
                        Button { set("color", c.text) } label: { Label { Text(n) } icon: { Image(nsImage: swatchImage(displayColor(c, layer: "0", doc: doc))) } }
                    }
                    Button("More Colors…") { ColorPanelBridge.shared.pick(initial: .white) { set("color", $0.hex) } }
                } label: {
                    HStack(spacing: 5) {
                        if let c = ColorRef.parse(r.value) {
                            Image(nsImage: swatchImage(displayColor(c, layer: model.selectedEntities.first?.layer ?? doc.currentLayer, doc: doc)))
                            Text(colorName(c)).font(Theme.font)
                        } else { Text(r.value).font(Theme.font) }
                    }
                }
                .menuStyle(.borderlessButton).darkField()
            case "linetype":
                Menu {
                    Button("ByLayer") { set("linetype", "ByLayer") }
                    ForEach(doc.linetypes, id: \.name) { lt in Button(lt.name) { set("linetype", lt.name) } }
                } label: { Text(r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            case "lineweight":
                Menu {
                    Button("ByLayer") { set("lineweight", "ByLayer") }
                    ForEach(standardLineweights, id: \.self) { w in Button(String(format: "%.2f mm", w)) { set("lineweight", fmt(w)) } }
                } label: { Text(r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            case "level":
                Menu {
                    ForEach(doc.levels, id: \.id) { l in Button(l.name) { set("level", "\(l.id)") } }
                } label: { Text(Int(r.value).flatMap { doc.level($0)?.name } ?? r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            case "material":
                Menu {
                    Button("None") { set("material", "") }
                    ForEach(doc.materials, id: \.name) { m in
                        Button { set("material", m.name) } label: { Label { Text(m.name) } icon: { Image(nsImage: swatchImage(m.color)) } }
                    }
                } label: { Text(r.value.isEmpty ? "None" : r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            case "wallType":
                Menu {
                    Button("Generic") { set("wallType", "") }
                    ForEach(doc.wallTypes, id: \.name) { w in Button("\(w.name)  (\(fmt(w.thickness)))") { set("wallType", w.name) } }
                } label: { Text(r.value.isEmpty ? "Generic" : r.value).font(Theme.font) }
                .menuStyle(.borderlessButton).darkField()
            default:
                if r.value == "true" || r.value == "false" {
                    Toggle("", isOn: Binding(get: { r.value == "true" }, set: { set(r.name, $0 ? "true" : "false") }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                } else {
                    PropertyField(value: r.value) { set(r.name, $0) }
                }
            }
        }
    }

    private func set(_ name: String, _ value: String) {
        let ids = model.selectedIDs
        var failed = 0
        model.editor.transaction("Properties") { d in
            for id in ids where !PropertyAccess.set(name, value, of: id, in: &d) { failed += 1 }
        }
        if failed > 0 { model.editor.print("Invalid value \"\(value)\" for \(humanize(name)) (\(failed) object(s) unchanged).") }
    }

    private var documentInfo: some View {
        let doc = model.doc
        return VStack(alignment: .leading, spacing: 0) {
            Text("No selection").font(Theme.fontBold).foregroundStyle(Theme.text).padding(.horizontal, 10).padding(.top, 8)
            Text("Click objects or drag a window to select. Properties of the selection appear here.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textFaint).padding(.horizontal, 10).padding(.top, 2)
            PanelHeader(title: "Project")
            infoField("Name", doc.info.name) { v in model.editor.transaction("Project Info") { $0.info.name = v } }
            infoField("Number", doc.info.number) { v in model.editor.transaction("Project Info") { $0.info.number = v } }
            infoField("Client", doc.info.client) { v in model.editor.transaction("Project Info") { $0.info.client = v } }
            infoField("Address", doc.info.address) { v in model.editor.transaction("Project Info") { $0.info.address = v } }
            infoField("Author", doc.info.author) { v in model.editor.transaction("Project Info") { $0.info.author = v } }
            PanelHeader(title: "Drawing")
            infoRow("Units", doc.units.rawValue.capitalized)
            infoRow("Current layer", doc.currentLayer)
            infoRow("Current level", doc.level(doc.currentLevel)?.name ?? "—")
            infoRow("Objects", "\(doc.entities.count)")
            infoRow("Building elements", "\(doc.elements.count)")
            infoRow("Layers", "\(doc.layers.count)")
            infoRow("Blocks", "\(doc.blocks.count)")
            infoRow("File", model.editor.fileURL?.lastPathComponent ?? "Not saved")
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.font).foregroundStyle(Theme.textDim).frame(width: 96, alignment: .leading)
            Text(v).font(Theme.font).foregroundStyle(Theme.text).lineLimit(1).textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 10).frame(height: 22)
    }

    private func infoField(_ k: String, _ v: String, _ commit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(k).font(Theme.font).foregroundStyle(Theme.textDim).frame(width: 96, alignment: .leading)
            PropertyField(value: v, commit: commit)
        }
        .padding(.horizontal, 10).frame(height: 24)
    }
}

/// Text field that commits on Return or when it loses focus.
struct PropertyField: View {
    let value: String
    var commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .darkField()
            .onAppear { text = value }
            .onChange(of: value) { v in if !focused { text = v } }
            .onChange(of: focused) { f in if !f && text != value { commit(text) } }
            .onSubmit { if text != value { commit(text) } }
    }
}

// MARK: - Layers

struct LayersPanel: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?
    @State private var filter = LayerFilter()
    @State private var savedFilterName: String?

    var body: some View {
        let doc = model.doc
        let usage = layerUsage(doc)
        let layers = doc.layers.filter { filter.matches($0, used: (usage[$0.name.uppercased()] ?? 0) > 0) }
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { newLayer() } label: { Label("New", systemImage: "plus") }.buttonStyle(FlatButtonStyle(compact: true)).help("New layer")
                Button { deleteLayer(usage) } label: { Label("Delete", systemImage: "minus") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(!canDelete(selected, usage)).help("Delete the selected layer (must be empty, not 0 or current)")
                Button { if let s = selected { model.setCurrentLayer(s) } } label: { Label("Current", systemImage: "checkmark.circle") }
                    .buttonStyle(FlatButtonStyle(compact: true)).disabled(selected == nil).help("Make the selected layer current")
                Spacer()
                Button { model.sheet = .layerStates } label: { Image(systemName: "rectangle.stack") }
                    .buttonStyle(FlatButtonStyle(compact: true)).help("Layer States Manager (LAYERSTATE)")
            }
            .padding(8)
            HStack(spacing: 4) {
                TextField("Filter: name, A-*, ~*TEXT*", text: $filter.pattern).darkField()
                Menu {
                    Toggle("On and thawed only", isOn: $filter.onlyVisible)
                    Toggle("Used layers only", isOn: $filter.onlyUsed)
                    Toggle("Unlocked only", isOn: $filter.onlyUnlocked)
                    Divider()
                    let names = LayerFilter.names(doc)
                    if !names.isEmpty {
                        Section("Saved filters") {
                            ForEach(names, id: \.self) { n in
                                Button { if let f = LayerFilter.saved(n, in: doc) { filter = f; savedFilterName = n } } label: {
                                    if savedFilterName == n { Label(n, systemImage: "checkmark") } else { Text(n) }
                                }
                            }
                        }
                    }
                    Button("Save Filter…") { saveFilter() }.disabled(filter.isEmpty)
                    if let n = savedFilterName { Button("Delete Filter \(n)") { model.editor.transaction("Delete Layer Filter") { $0.variables[LayerFilter.prefix + n] = nil }; savedFilterName = nil } }
                    Button("Clear Filter") { filter = LayerFilter(); savedFilterName = nil }.disabled(filter.isEmpty)
                } label: {
                    Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filter.isEmpty ? Theme.text : Theme.accent)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Layer filters (saved with the drawing)")
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            HSeparator()
            HStack(spacing: 4) {
                Text("").frame(width: 16)
                Image(systemName: "eye").frame(width: 16)
                Image(systemName: "snowflake").frame(width: 16)
                Image(systemName: "lock").frame(width: 16)
                Image(systemName: "paintpalette").frame(width: 16)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Linetype").frame(width: 62, alignment: .leading)
                Text("LW").frame(width: 36, alignment: .leading)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 8).frame(height: 20)
            HSeparator()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(layers, id: \.name) { l in
                        LayerRow(model: model, layer: l, isCurrent: l.name.caseInsensitiveCompare(doc.currentLayer) == .orderedSame,
                                 isSelected: selected == l.name, count: usage[l.name.uppercased()] ?? 0)
                            .onTapGesture { selected = l.name }
                    }
                }
            }
            .background(Theme.panel)
            HSeparator()
            Text(filter.isEmpty ? "\(doc.layers.count) layers · double-click the radio to make current" : "\(layers.count) of \(doc.layers.count) layers match the filter")
                .font(Theme.fontSmall).foregroundStyle(filter.isEmpty ? Theme.textFaint : Theme.accent).padding(6)
        }
        .onAppear { if let f = model.layerFilterRequest { filter = f; model.layerFilterRequest = nil } }
        .onChange(of: model.layerFilterRequest) { f in if let f { filter = f; model.layerFilterRequest = nil } }
    }

    private func saveFilter() {
        let a = NSAlert()
        a.messageText = "Save Layer Filter"
        a.informativeText = "Name for the filter “\(filter.stored.trimmingCharacters(in: .whitespaces))”:"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        tf.stringValue = savedFilterName ?? "Filter \(LayerFilter.names(model.doc).count + 1)"
        a.accessoryView = tf
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        guard !n.isEmpty else { return }
        let f = filter
        model.editor.transaction("Save Layer Filter") { $0.variables[LayerFilter.prefix + n] = f.stored }
        savedFilterName = n
    }

    private func layerUsage(_ doc: ArchiDocument) -> [String: Int] {
        var u: [String: Int] = [:]
        for e in doc.entities { u[e.layer.uppercased(), default: 0] += 1 }
        for e in doc.elements { u[e.layer.uppercased(), default: 0] += 1 }
        for b in doc.blocks.values { for e in b.entities { u[e.layer.uppercased(), default: 0] += 1 } }
        return u
    }

    private func canDelete(_ name: String?, _ usage: [String: Int]) -> Bool {
        guard let n = name else { return false }
        return n != "0" && n.caseInsensitiveCompare(model.doc.currentLayer) != .orderedSame && (usage[n.uppercased()] ?? 0) == 0
    }

    private func newLayer() {
        var i = 1
        while model.doc.layer(named: "Layer\(i)") != nil { i += 1 }
        let name = "Layer\(i)"
        model.editor.transaction("New Layer") { $0.layers.append(Layer(name: name)) }
        selected = name
    }

    private func deleteLayer(_ usage: [String: Int]) {
        guard let s = selected, canDelete(s, usage) else { return }
        model.editor.transaction("Delete Layer") { d in d.layers.removeAll { $0.name == s } }
        selected = nil
    }
}

private struct LayerRow: View {
    @ObservedObject var model: AppModel
    let layer: Layer
    let isCurrent: Bool
    let isSelected: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Button { model.setCurrentLayer(layer.name) } label: {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCurrent ? Theme.accent : Theme.textFaint)
            }
            .buttonStyle(.plain).frame(width: 16).help(isCurrent ? "Current layer" : "Make current")
            toggle(layer.visible ? "eye" : "eye.slash", on: layer.visible, help: layer.visible ? "On — click to turn off" : "Off — click to turn on") { $0.visible.toggle() }
            toggle(layer.frozen ? "snowflake" : "sun.max", on: !layer.frozen, help: layer.frozen ? "Frozen — click to thaw" : "Thawed — click to freeze") { $0.frozen.toggle() }
            toggle(layer.locked ? "lock.fill" : "lock.open", on: !layer.locked, help: layer.locked ? "Locked — click to unlock" : "Unlocked — click to lock") { $0.locked.toggle() }
            Menu {
                ForEach(basicColors, id: \.0) { n, c in
                    Button { update { $0.color = aciRGBA(c) } } label: { Label { Text(n) } icon: { Image(nsImage: swatchImage(aciRGBA(c))) } }
                }
                Divider()
                Button("More Colors…") { ColorPanelBridge.shared.pick(initial: layer.color) { c in update { $0.color = c } } }
            } label: { Image(nsImage: swatchImage(layer.color, size: 12)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 16).help("Layer color \(layer.color.hex)")
            LayerNameField(name: layer.name, editable: layer.name != "0") { rename(to: $0) }
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(model.doc.linetypes, id: \.name) { lt in Button(lt.name) { update { $0.linetype = lt.name } } }
            } label: { Text(layer.linetype).font(.system(size: 10)).lineLimit(1) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 62, alignment: .leading)
            Menu {
                ForEach(standardLineweights, id: \.self) { w in Button(String(format: "%.2f mm", w)) { update { $0.lineweight = w } } }
            } label: { Text(String(format: "%.2f", layer.lineweight)).font(.system(size: 10)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 36, alignment: .leading)
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(isSelected ? Theme.accent.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .help("\(layer.name) — \(count) object(s)")
    }

    private func toggle(_ symbol: String, on: Bool, help: String, _ change: @escaping (inout Layer) -> Void) -> some View {
        Button { update(change) } label: {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(on ? Theme.text : Theme.accent)
        }
        .buttonStyle(.plain).frame(width: 16).help(help)
    }

    private func update(_ change: @escaping (inout Layer) -> Void) {
        let n = layer.name
        model.editor.transaction("Layer \(n)") { d in
            if let i = d.layerIndex(n) { change(&d.layers[i]) }
        }
        let sel = model.editor.selection
        if !sel.isEmpty { model.editor.selection = sel.filter { model.editor.isSelectable($0) } }
    }

    private func rename(to newName: String) {
        let old = layer.name
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != old else { return }
        if model.doc.layer(named: n) != nil && n.caseInsensitiveCompare(old) != .orderedSame {
            model.editor.print("A layer named \"\(n)\" already exists."); return
        }
        model.editor.transaction("Rename Layer") { d in
            guard let i = d.layerIndex(old) else { return }
            d.layers[i].name = n
            for k in d.entities.indices where d.entities[k].layer == old { d.entities[k].layer = n }
            for k in d.elements.indices where d.elements[k].layer == old { d.elements[k].layer = n }
            for key in d.blocks.keys { d.blocks[key]!.entities = d.blocks[key]!.entities.map { var e = $0; if e.layer == old { e.layer = n }; return e } }
            if d.currentLayer == old { d.currentLayer = n }
        }
    }
}

private struct LayerNameField: View {
    let name: String
    let editable: Bool
    var commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        if editable {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.font)
                .focused($focused)
                .onAppear { text = name }
                .onChange(of: name) { text = $0 }
                .onSubmit { commit(text) }
                .onChange(of: focused) { f in if !f && text != name { commit(text) } }
        } else {
            Text(name).font(Theme.font)
        }
    }
}

func aciRGBA(_ c: ColorRef) -> RGBA {
    switch c {
    case .aci(let i): return aciColor(i)
    case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    default: return .white
    }
}

// MARK: - Levels

struct LevelsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let doc = model.doc
        let counts = Dictionary(grouping: doc.elements, by: \.level).mapValues(\.count)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { addLevel() } label: { Label("Add Level", systemImage: "plus") }.buttonStyle(FlatButtonStyle(compact: true))
                    .help("Add a level above the highest one")
                Spacer()
            }
            .padding(8)
            HStack(spacing: 4) {
                Text("").frame(width: 16)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Elevation").frame(width: 64, alignment: .leading)
                Text("Height").frame(width: 56, alignment: .leading)
                Text("").frame(width: 20)
            }
            .font(.system(size: 9.5)).foregroundStyle(Theme.textDim).padding(.horizontal, 8).frame(height: 20)
            HSeparator()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(doc.levels.sorted { $0.elevation > $1.elevation }, id: \.id) { l in
                        HStack(spacing: 4) {
                            Button { model.setCurrentLevel(l.id) } label: {
                                Image(systemName: l.id == doc.currentLevel ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(l.id == doc.currentLevel ? Theme.accent : Theme.textFaint)
                            }
                            .buttonStyle(.plain).frame(width: 16).help("Make current")
                            PropertyField(value: l.name) { v in update(l.id) { $0.name = v } }
                                .frame(maxWidth: .infinity)
                            PropertyField(value: fmt(l.elevation)) { v in if let x = InputParser.parseNumber(v) { update(l.id) { $0.elevation = x } } }
                                .frame(width: 64)
                            PropertyField(value: fmt(l.height)) { v in if let x = InputParser.parseNumber(v), x > 0 { update(l.id) { $0.height = x } } }
                                .frame(width: 56)
                            Button { remove(l.id, count: counts[l.id] ?? 0) } label: { Image(systemName: "trash").font(.system(size: 10)) }
                                .buttonStyle(.plain).foregroundStyle(Theme.textDim).frame(width: 20)
                                .disabled(doc.levels.count <= 1 || (counts[l.id] ?? 0) > 0)
                                .help((counts[l.id] ?? 0) > 0 ? "Level has \(counts[l.id] ?? 0) element(s) — move or delete them first" : "Delete level")
                        }
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(l.id == doc.currentLevel ? Theme.accent.opacity(0.10) : Color.clear)
                    }
                }
            }
            HSeparator()
            Text("Elevations in \(doc.units.abbreviation). New walls, slabs and rooms go on the current level.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textFaint).padding(8)
        }
    }

    private func update(_ id: Int, _ change: @escaping (inout Level) -> Void) {
        model.editor.transaction("Edit Level") { d in if let i = d.levels.firstIndex(where: { $0.id == id }) { change(&d.levels[i]) } }
    }
    private func addLevel() {
        model.editor.transaction("Add Level") { d in
            let top = d.levels.max { $0.elevation < $1.elevation }
            let id = (d.levels.map(\.id).max() ?? -1) + 1
            let elev = (top?.elevation ?? 0) + (top?.height ?? 3000)
            d.levels.append(Level(id: id, name: "Level \(id)", elevation: elev, height: top?.height ?? 3000))
        }
    }
    private func remove(_ id: Int, count: Int) {
        guard count == 0, model.doc.levels.count > 1 else { return }
        model.editor.transaction("Delete Level") { d in
            d.levels.removeAll { $0.id == id }
            if d.currentLevel == id { d.currentLevel = d.levels.min { $0.elevation < $1.elevation }?.id ?? 0 }
        }
    }
}

// MARK: - Project browser

struct ProjectBrowserPanel: View {
    @ObservedObject var model: AppModel
    @State private var openLevels = true
    @State private var openViews = true
    @State private var openSheets = true
    @State private var openSchedules = true

    var body: some View {
        let doc = model.doc
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Floor Plans", "square.split.bottomrightquarter", $openLevels) {
                    ForEach(doc.levels.sorted { $0.elevation > $1.elevation }, id: \.id) { l in
                        item(l.name, "square.grid.3x1.below.line.grid.1x2", active: model.mode != .sheet && l.id == doc.currentLevel) {
                            model.setCurrentLevel(l.id)
                            if model.mode == .sheet || model.mode == .model { model.mode = .plan }
                        }
                    }
                }
                section("3D Views", "cube", $openViews) {
                    ForEach(["Iso", "Top", "Front", "Right", "Back", "Left"], id: \.self) { v in
                        item("3D — \(v)", "cube.transparent", active: (model.mode == .model || model.mode == .split) && model.viewDirection == v) {
                            if model.mode == .plan || model.mode == .sheet { model.mode = .model }
                            model.files.handle(.setView(v))
                        }
                    }
                    ForEach(doc.namedViews, id: \.name) { v in
                        item(v.name, "eye", active: false) {
                            if v.camera != nil { model.mode = .model; model.files.handle(.setView(v.name)) }
                            else {
                                model.mode = .plan
                                let h = v.height, w = h * 1.6
                                DispatchQueue.main.async { model.canvas?.zoom(toRect: CGRect(x: v.center.x - w / 2, y: v.center.y - h / 2, width: w, height: h)) }
                            }
                        }
                    }
                }
                section("Sheets", "doc.richtext", $openSheets) {
                    ForEach(Array(doc.layouts.enumerated()), id: \.offset) { i, l in
                        item(l.name, "doc", active: model.mode == .sheet && model.activeLayout == i) {
                            model.activeLayout = i
                            model.mode = .sheet
                        }
                    }
                }
                section("Schedules", "tablecells", $openSchedules) {
                    ForEach(ScheduleExporter.kinds, id: \.self) { k in
                        item("\(k.capitalized) Schedule", "list.bullet.rectangle", active: false) { model.sheet = .schedule(k) }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func section<C: View>(_ title: String, _ symbol: String, _ open: Binding<Bool>, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open.wrappedValue.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: open.wrappedValue ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    Image(systemName: symbol).font(.system(size: 11))
                    Text(title).font(Theme.fontBold)
                    Spacer()
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8).frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open.wrappedValue { content() }
        }
    }

    private func item(_ title: String, _ symbol: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10)).frame(width: 14)
                Text(title).font(Theme.font).lineLimit(1)
                Spacer()
            }
            .foregroundStyle(active ? Theme.accent : Theme.text)
            .padding(.leading, 30).padding(.trailing, 8).frame(height: 22)
            .background(active ? Theme.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

