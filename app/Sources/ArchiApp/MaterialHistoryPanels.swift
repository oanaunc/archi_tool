// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

// MARK: - Materials panel with editor (color, roughness, metalness, transparency, texture, cut pattern)

struct MaterialsPanel: View {
    @ObservedObject var model: AppModel
    @State private var selected: String?

    var body: some View {
        let doc = model.doc
        let usage = Dictionary(grouping: doc.elements.compactMap(\.material), by: { $0.lowercased() }).mapValues(\.count)
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { newMaterial(copyOf: nil) } label: { Label("New", systemImage: "plus") }.buttonStyle(FlatButtonStyle(compact: true))
                Button { if let s = selected { newMaterial(copyOf: s) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .buttonStyle(FlatButtonStyle(compact: true)).disabled(selected == nil)
                Button { delete(usage) } label: { Label("Delete", systemImage: "minus") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(selected == nil || (usage[selected!.lowercased()] ?? 0) > 0)
                    .help("Delete the selected material (only when no element uses it)")
                Spacer()
                Button { assignToSelection() } label: { Image(systemName: "paintbrush.pointed") }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(selected == nil || model.selectedElements.isEmpty).help("Assign the material to the selected building elements")
            }
            .padding(8)
            HSeparator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(doc.materials, id: \.name) { m in
                        row(m, count: usage[m.name.lowercased()])
                    }
                }
            }
            .frame(maxHeight: selected == nil ? .infinity : 190)
            .background(Theme.panel)
            if let s = selected, let m = doc.material(s) {
                HSeparator()
                MaterialEditor(model: model, material: m, onRename: { selected = $0 })
                    .id(m.name)
            }
        }
        .background(Theme.panel)
    }

    private func row(_ m: ArchiCore.Material, count: Int?) -> some View {
        let isSel = selected == m.name
        return HStack(spacing: 8) {
            MaterialSwatch(material: m, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(Theme.fontBold).foregroundStyle(Theme.text)
                Text("Rough \(fmt(m.roughness, 2)) · Metal \(fmt(m.metalness, 2))\(m.transparency > 0 ? " · Transp \(fmt(m.transparency, 2))" : "")\(m.texture != nil ? " · Texture" : "")")
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            Spacer()
            if let n = count {
                Text("\(n)").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 5).background(Capsule().fill(Theme.hover)).help("\(n) element(s) use this material")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(isSel ? Theme.accent.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = isSel ? nil : m.name }
    }

    private func newMaterial(copyOf src: String?) {
        let doc = model.doc
        var base = src.flatMap { doc.material($0) } ?? ArchiCore.Material(name: "Material", color: RGBA(0.8, 0.8, 0.8))
        var n = 1
        let stem = src ?? "Material"
        var name = src == nil ? "Material 1" : "\(stem) copy"
        while doc.material(name) != nil { n += 1; name = src == nil ? "Material \(n)" : "\(stem) copy \(n)" }
        base.name = name
        let m = base
        model.editor.transaction("New Material") { $0.materials.append(m) }
        selected = name
    }

    private func delete(_ usage: [String: Int]) {
        guard let s = selected, (usage[s.lowercased()] ?? 0) == 0 else { return }
        model.editor.transaction("Delete Material") { d in d.materials.removeAll { $0.name == s } }
        selected = nil
    }

    private func assignToSelection() {
        guard let s = selected else { return }
        let ids = Set(model.selectedElements.map(\.id))
        model.editor.transaction("Assign Material") { d in
            for i in d.elements.indices where ids.contains(d.elements[i].id) { d.elements[i].material = s }
        }
        model.editor.print("Material \(s) assigned to \(ids.count) element(s).")
    }
}

/// Rendered-looking material preview sphere.
struct MaterialSwatch: View {
    let material: ArchiCore.Material
    var size: CGFloat = 26
    var body: some View {
        let c = Color(material.color)
        ZStack {
            if let img = MaterialTextures.image(material.texture) {
                Image(nsImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Circle().fill(c)
            }
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.85 * (1 - material.roughness) + 0.1), .clear],
                                         center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.45))
            Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.45 + 0.2 * material.metalness)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: size * 0.2, endRadius: size * 0.7))
        }
        .opacity(1 - material.transparency * 0.6)
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
}

/// Texture images referenced by materials (absolute paths, or names relative to the document folder).
@MainActor
enum MaterialTextures {
    private static var cache: [String: NSImage] = [:]
    static var documentFolder: URL?
    static func url(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("/") { return URL(fileURLWithPath: p) }
        if let d = documentFolder { return d.appendingPathComponent(p) }
        return nil
    }
    static func image(_ path: String?) -> NSImage? {
        guard let p = path, !p.isEmpty else { return nil }
        if let i = cache[p] { return i }
        guard let u = url(p), let i = NSImage(contentsOf: u) else { return nil }
        cache[p] = i
        return i
    }
}

private struct MaterialEditor: View {
    @ObservedObject var model: AppModel
    let material: ArchiCore.Material
    var onRename: (String) -> Void
    @State private var name = ""
    @State private var color = Color.gray

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                MaterialSwatch(material: material, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $name).darkField().onSubmit(rename)
                    HStack(spacing: 6) {
                        ColorPicker("", selection: Binding(get: { Color(material.color) }, set: { c in update("Color") { $0.color = RGBA(c) } }), supportsOpacity: false)
                            .labelsHidden()
                        Text(material.color.hex24.hexString).font(Theme.mono).foregroundStyle(Theme.textDim)
                    }
                }
            }
            slider("Roughness", \.roughness, 0...1)
            slider("Metalness", \.metalness, 0...1)
            slider("Transparency", \.transparency, 0...0.95)
            HStack(spacing: 6) {
                Text("Texture").frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                Text(material.texture.map { ($0 as NSString).lastPathComponent } ?? "None").lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseTexture() }.buttonStyle(FlatButtonStyle(compact: true))
                if material.texture != nil {
                    IconButton(symbol: "xmark.circle", help: "Remove the texture") { update("Texture") { $0.texture = nil } }
                }
            }
            if material.texture != nil {
                HStack(spacing: 6) {
                    Text("Tile size").frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                    TextField("", value: Binding(get: { material.textureScale }, set: { v in update("Texture Scale") { $0.textureScale = max(1, v) } }), format: .number)
                        .darkField().frame(width: 80)
                    Text("mm").foregroundStyle(Theme.textDim)
                }
            }
            HStack(spacing: 6) {
                Text("Cut pattern").frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
                Picker("", selection: Binding(get: { material.cutPattern.uppercased() }, set: { v in update("Cut Pattern") { $0.cutPattern = v } })) {
                    ForEach(HatchPatterns.names, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 140)
            }
        }
        .font(Theme.font)
        .padding(10)
        .onAppear { name = material.name }
    }

    private func slider(_ title: String, _ kp: WritableKeyPath<ArchiCore.Material, Double>, _ range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 76, alignment: .leading).foregroundStyle(Theme.textDim)
            Slider(value: Binding(get: { material[keyPath: kp] }, set: { v in update(title) { $0[keyPath: kp] = (v * 100).rounded() / 100 } }), in: range)
            Text(fmt(material[keyPath: kp], 2)).font(Theme.mono).frame(width: 34, alignment: .trailing)
        }
    }

    /// Consecutive edits of the same property (slider drags) merge into one undo step.
    private func update(_ label: String, _ change: @escaping (inout ArchiCore.Material) -> Void) {
        let n = material.name
        let ed = model.editor
        if ed.history.undoLabel == "Material \(label)" && lastEdit.label == label && lastEdit.name == n && Date().timeIntervalSince(lastEdit.date) < 1.5 {
            var d = ed.doc
            if let i = d.materials.firstIndex(where: { $0.name == n }) { change(&d.materials[i]); ed.doc = d; ed.isDirty = true }
        } else {
            ed.transaction("Material \(label)") { d in if let i = d.materials.firstIndex(where: { $0.name == n }) { change(&d.materials[i]) } }
        }
        lastEdit = (label, n, Date())
    }

    private func rename() {
        let new = name.trimmingCharacters(in: .whitespaces)
        let old = material.name
        guard !new.isEmpty, new != old else { return }
        guard model.doc.material(new) == nil || new.caseInsensitiveCompare(old) == .orderedSame else { name = old; NSSound.beep(); return }
        model.editor.transaction("Rename Material") { d in
            if let i = d.materials.firstIndex(where: { $0.name == old }) { d.materials[i].name = new }
            for i in d.elements.indices where d.elements[i].material?.caseInsensitiveCompare(old) == .orderedSame { d.elements[i].material = new }
            for w in d.wallTypes.indices { for p in d.wallTypes[w].plies.indices where d.wallTypes[w].plies[p].material == old { d.wallTypes[w].plies[p].material = new } }
        }
        onRename(new)
    }

    private func chooseTexture() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.message = "Choose a texture image (it tiles at the tile size on 3D faces)"
        guard p.runModal() == .OK, let u = p.url else { return }
        var path = u.path
        if let dir = model.editor.fileURL?.deletingLastPathComponent().path, path.hasPrefix(dir + "/") { path = String(path.dropFirst(dir.count + 1)) }
        update("Texture") { $0.texture = path }
    }
}

@MainActor private var lastEdit: (label: String, name: String, date: Date) = ("", "", .distantPast)

extension UInt32 {
    var hexString: String { String(format: "#%06X", self) }
}

// MARK: - History panel (undo steps and command history)

struct HistoryPanel: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                Text("Undo History").tag(0)
                Text("Commands").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(8)
            HSeparator()
            if page == 0 { undoList } else { commandList }
        }
        .background(Theme.panel)
    }

    /// Clicking a step restores the document to just after it (undoing or redoing the steps in between).
    private var undoList: some View {
        let h = model.editor.history
        let undo = h.undoStack.map(\.label)
        let redo = Array(h.redoStack.map(\.label).reversed())
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                stepRow(0, "Open / new document", state: undo.isEmpty ? .current : .done, total: undo.count)
                ForEach(Array(undo.enumerated()), id: \.offset) { i, l in
                    stepRow(i + 1, l, state: i == undo.count - 1 ? .current : .done, total: undo.count)
                }
                ForEach(Array(redo.enumerated()), id: \.offset) { i, l in
                    stepRow(undo.count + i + 1, l, state: .undone, total: undo.count)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private enum StepState { case done, current, undone }

    private func stepRow(_ index: Int, _ label: String, state: StepState, total: Int) -> some View {
        Button { goTo(index, current: total) } label: {
            HStack(spacing: 8) {
                Text("\(index)").font(Theme.mono).foregroundStyle(Theme.textFaint).frame(width: 28, alignment: .trailing)
                Image(systemName: state == .current ? "arrowtriangle.right.fill" : (state == .undone ? "circle.dashed" : "circle.fill"))
                    .font(.system(size: 7)).foregroundStyle(state == .current ? Theme.accent : Theme.textDim)
                Text(label).font(Theme.font).foregroundStyle(state == .undone ? Theme.textFaint : Theme.text).italic(state == .undone)
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 22)
            .background(state == .current ? Theme.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state == .undone ? "Redo up to this step" : "Undo back to this step")
    }

    private func goTo(_ index: Int, current: Int) {
        let ed = model.editor
        guard ed.isIdle else { ed.print("Finish the current command first."); return }
        if index < current { for _ in 0..<(current - index) { ed.undo() } }
        else if index > current { for _ in 0..<(index - current) { ed.redo() } }
        model.revision &+= 1
    }

    private var commandList: some View {
        let cmds = model.commandLog.filter { $0.hasPrefix("Command: ") }.map { String($0.dropFirst(9)) }
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cmds.enumerated().reversed()), id: \.offset) { _, c in
                        Button { model.runCommand(c) } label: {
                            HStack {
                                Image(systemName: "terminal").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                                Text(c).font(Theme.mono).foregroundStyle(Theme.text)
                                Spacer()
                                Text(model.editor.registry.lookup(c)?.category ?? "").font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
                            }
                            .padding(.horizontal, 10).frame(height: 21).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Run \(c) again")
                    }
                }
            }
            HSeparator()
            HStack {
                Text("\(cmds.count) command(s) this session").font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
                Spacer()
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.commandLog.joined(separator: "\n"), forType: .string)
                }
                .buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(6)
        }
    }
}
