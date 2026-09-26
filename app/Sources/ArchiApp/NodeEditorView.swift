// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import UniformTypeIdentifiers
import ArchiCore

@MainActor
enum NodeEditorWindow {
    private static var windows: [ObjectIdentifier: NSWindow] = [:]
    static func show(model: AppModel) {
        let key = ObjectIdentifier(model)
        if let w = windows[key] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Node Editor — \(model.displayName)"
        w.isReleasedWhenClosed = false
        w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: NodeEditorView(model: model).preferredColorScheme(Theme.colorScheme))
        w.center(); w.makeKeyAndOrderFront(nil)
        windows[key] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = windows.removeValue(forKey: key) }
        }
    }
}

enum NodeLayout {
    static let width: CGFloat = 188
    /// Approximate drawn height of a node (header, input rows, number slider, footer).
    static func height(_ k: NodeKind) -> CGFloat { header + row * CGFloat(k.inputs.count) + (k == .number ? 52 : 0) + 22 }
    static let header: CGFloat = 24
    static let row: CGFloat = 26
    static func inputPort(_ n: GraphNode, _ i: Int) -> CGPoint { CGPoint(x: n.x, y: n.y + header + row * CGFloat(i) + row / 2) }
    static func outputPort(_ n: GraphNode) -> CGPoint { CGPoint(x: n.x + width, y: n.y + header / 2) }
}

struct NodeEditorView: View {
    @ObservedObject var model: AppModel
    @State private var graph = NodeGraph()
    @State private var loaded = false
    @State private var live = false
    @State private var dragLink: (from: Int, to: CGPoint)?
    @State private var previewMode = "3D"
    @State private var status = ""
    @State private var bakeTask: Task<Void, Never>?

    var body: some View {
        let ev = graph.evaluate()
        VStack(spacing: 0) {
            toolbar(ev)
            HSeparator()
            HSplitView {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Color(white: 0.13).frame(width: 2400, height: 1600)
                            .onTapGesture { }
                        GridBackground().frame(width: 2400, height: 1600)
                        ForEach(graph.groups) { g in
                            NodeFrameBox(frame: groupBinding(g.id), graph: $graph).offset(x: g.x, y: g.y)
                        }
                        links(ev)
                        ForEach(graph.nodes) { n in
                            NodeBox(node: binding(n.id), graph: $graph, value: ev.values[n.id], error: ev.errors[n.id],
                                    isOutput: graph.outputNodes.contains(n.id), dragLink: $dragLink, onLinkEnd: finishLink)
                                .offset(x: n.x, y: n.y)
                        }
                        ForEach(graph.comments) { c in
                            NodeCommentBox(comment: commentBinding(c.id), graph: $graph).offset(x: c.x, y: c.y)
                        }
                    }
                    .coordinateSpace(name: "graph")
                    .frame(width: 2400, height: 1600, alignment: .topLeading)
                }
                .frame(minWidth: 520)
                preview(ev).frame(minWidth: 260, idealWidth: 340)
            }
        }
        .background(Theme.panel)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            graph = NodeGraph.load(model.doc) ?? NodeGraph.sample
        }
        .onChange(of: graph) { _ in if live { scheduleBake() } }
    }

    private func groupBinding(_ id: Int) -> Binding<NodeFrame> {
        Binding(get: { graph.groups.first { $0.id == id } ?? NodeFrame(id: id, title: "", x: 0, y: 0, width: 0, height: 0) },
                set: { v in if let i = graph.groups.firstIndex(where: { $0.id == id }) { graph.groups[i] = v } })
    }
    private func commentBinding(_ id: Int) -> Binding<NodeComment> {
        Binding(get: { graph.comments.first { $0.id == id } ?? NodeComment(id: id, text: "", x: 0, y: 0) },
                set: { v in if let i = graph.comments.firstIndex(where: { $0.id == id }) { graph.comments[i] = v } })
    }

    private func exportScript() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.javaScript]
        p.nameFieldStringValue = "graph.js"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try NodeGraphScript.javascript(graph, name: u.deletingPathExtension().lastPathComponent).write(to: u, atomically: true, encoding: .utf8); status = "Exported \(u.lastPathComponent)." }
        catch { status = error.localizedDescription }
    }
    private func openInConsole() {
        UserDefaults.standard.set(NodeGraphScript.javascript(graph), forKey: "archi.script.code")
        model.showScriptConsole = true
        status = "The graph script is in the JavaScript console."
    }

    private func binding(_ id: Int) -> Binding<GraphNode> {
        Binding(get: { graph.node(id) ?? GraphNode(id: id, kind: .number, x: 0, y: 0) },
                set: { v in if let i = graph.nodes.firstIndex(where: { $0.id == id }) { graph.nodes[i] = v } })
    }

    private func toolbar(_ ev: NodeGraph.Evaluation) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(["Numbers", "Geometry", "Solids", "Transform", "Building"], id: \.self) { cat in
                    Section(cat) {
                        ForEach(NodeKind.allCases.filter { $0.category == cat }) { k in
                            Button(k.title) { let c = graph.nodes.count; graph.add(k, x: 40 + Double(c % 6) * 36, y: 40 + Double(c % 8) * 30) }
                        }
                    }
                }
            } label: { Label("Add Node", systemImage: "plus.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { graph = NodeGraph.sample } label: { Label("Sample", systemImage: "wand.and.stars") }.buttonStyle(FlatButtonStyle(compact: true))
            Button { graph.addGroup(title: "Group \(graph.groups.count + 1)", around: graph.nodes.map(\.id).filter { id in !graph.groups.contains { g in g.contains(graph.node(id)!) } }) } label: { Label("Group", systemImage: "rectangle.dashed") }
                .buttonStyle(FlatButtonStyle(compact: true)).help("Frame the ungrouped nodes in a titled group; drag its title to move the group with its nodes")
            Button { graph.addComment("Note", x: 60 + Double(graph.comments.count * 24), y: 60) } label: { Label("Comment", systemImage: "note.text") }
                .buttonStyle(FlatButtonStyle(compact: true)).help("Add a sticky note to the canvas")
            Button { graph = NodeGraph() } label: { Label("Clear", systemImage: "trash") }.buttonStyle(FlatButtonStyle(compact: true))
            Menu {
                let names = NodeGraph.names(model.doc)
                if names.isEmpty { Text("No named graphs in this drawing") }
                ForEach(names, id: \.self) { n in Button("Open “\(n)”") { if let g = NodeGraph.load(model.doc, name: n) { graph = g; status = "Opened graph “\(n)”." } } }
                Divider()
                Button("Save As…") { saveNamed() }
                Menu("Delete") {
                    ForEach(names, id: \.self) { n in Button(n) { model.editor.transaction("Delete Node Graph") { NodeGraph.delete(n, in: &$0) }; status = "Deleted graph “\(n)”." } }
                }.disabled(names.isEmpty)
                Divider()
                Button("Export JSON…") { exportJSON() }
                Button("Export as Script…") { exportScript() }
                Button("Open as Script in Console") { openInConsole() }
                Button("Import JSON…") { importJSON() }
            } label: { Label("Graphs", systemImage: "folder") }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Named graphs stored in the drawing, JSON import/export")
            NodePackagesMenu(graph: $graph, status: $status)
            Divider().frame(height: 16)
            Toggle("Live", isOn: $live).toggleStyle(.switch).controlSize(.mini)
                .help("Update the drawing on every change (the baked objects are replaced)")
            Button { bake() } label: { Label("Bake to Drawing", systemImage: "square.and.arrow.down.on.square") }
                .buttonStyle(FlatButtonStyle(prominent: true)).disabled(ev.output.isEmpty && ev.elementOutput.isEmpty)
                .help("Write the output geometry into the drawing (one undo step; replaces the previous bake)")
            Button { saveGraph() } label: { Label("Save Graph", systemImage: "square.and.arrow.down") }.buttonStyle(FlatButtonStyle(compact: true))
                .help("Store the graph in the drawing (.archi)")
            Spacer()
            if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
            Text("\(graph.nodes.count) nodes · \(ev.output.count) objects · \(ev.elementOutput.count) elements\(ev.errors.isEmpty ? "" : " · \(ev.errors.count) error(s)")")
                .font(Theme.fontSmall).foregroundStyle(ev.errors.isEmpty ? Theme.textDim : Theme.danger)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func links(_ ev: NodeGraph.Evaluation) -> some View {
        Canvas { ctx, _ in
            for l in graph.links {
                guard let a = graph.node(l.from), let b = graph.node(l.to), let pi = b.kind.inputs.firstIndex(where: { $0.name == l.port }) else { continue }
                let p = NodeLayout.outputPort(a), q = NodeLayout.inputPort(b, pi)
                ctx.stroke(curve(p, q), with: .color(ev.errors[l.from] == nil ? Theme.accent.opacity(0.85) : Theme.danger), lineWidth: 2)
            }
            if let d = dragLink, let a = graph.node(d.from) {
                ctx.stroke(curve(NodeLayout.outputPort(a), d.to), with: .color(Theme.accent.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .frame(width: 2400, height: 1600)
        .allowsHitTesting(false)
    }

    private func curve(_ p: CGPoint, _ q: CGPoint) -> Path {
        var path = Path()
        path.move(to: p)
        let dx = max(40, abs(q.x - p.x) * 0.5)
        path.addCurve(to: q, control1: CGPoint(x: p.x + dx, y: p.y), control2: CGPoint(x: q.x - dx, y: q.y))
        return path
    }

    private func finishLink(_ from: Int, _ at: CGPoint) {
        dragLink = nil
        for n in graph.nodes where n.id != from {
            for (i, p) in n.kind.inputs.enumerated() {
                let c = NodeLayout.inputPort(n, i)
                if hypot(c.x - at.x, c.y - at.y) < 16 {
                    if !graph.connect(from: from, to: n.id, port: p.name) { status = "Cannot connect: type mismatch or cycle."; NSSound.beep() } else { status = "" }
                    return
                }
            }
        }
    }

    @ViewBuilder private func preview(_ ev: NodeGraph.Evaluation) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $previewMode) { Text("3D").tag("3D"); Text("Plan").tag("Plan") }
                .pickerStyle(.segmented).labelsHidden().padding(6)
            if previewMode == "3D" {
                NodePreview3D(geometry: ev.output, elements: ev.elementOutput)
            } else {
                NodePreviewPlan(geometry: ev.output, elements: ev.elementOutput)
            }
        }
        .background(Color(white: 0.1))
    }

    private func scheduleBake() {
        bakeTask?.cancel()
        bakeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !Task.isCancelled { bake() }
        }
    }

    private func bake() {
        let ev = graph.evaluate()
        let out = ev.output, els = ev.elementOutput
        let g = graph
        var ids: [EntityID] = []
        model.editor.transaction("Node Graph") { d in
            ids = NodeGraphBake.bake(out, elements: els, into: &d)
            g.store(in: &d)
        }
        status = "Baked \(ids.count) object(s) on layer NODES."
    }

    private func saveNamed() {
        let a = NSAlert()
        a.messageText = "Save graph as"
        a.informativeText = "Named graphs are stored in the drawing (.archi) and can be opened from the Graphs menu."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        f.stringValue = "Graph \(NodeGraph.names(model.doc).count + 1)"
        a.accessoryView = f
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let g = graph
        model.editor.transaction("Save Node Graph") { g.store(in: &$0, name: name) }
        status = "Graph saved as “\(name)”."
    }

    private func exportJSON() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "graph.json"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try graph.json().write(to: u); status = "Exported \(u.lastPathComponent)." } catch { status = error.localizedDescription }
    }

    private func importJSON() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let u = p.url else { return }
        if let d = try? Data(contentsOf: u), let g = try? JSONDecoder().decode(NodeGraph.self, from: d) { graph = g; status = "Imported \(u.lastPathComponent)." }
        else { status = "Not a node graph file."; NSSound.beep() }
    }

    private func saveGraph() {
        let g = graph
        model.editor.transaction("Save Node Graph") { g.store(in: &$0) }
        status = "Graph saved in the drawing."
    }
}

private struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            stride(from: 0.0, through: size.width, by: 24).forEach { x in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0.0, through: size.height, by: 24).forEach { y in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
            ctx.stroke(p, with: .color(Color.white.opacity(0.035)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

private struct NodeBox: View {
    @Binding var node: GraphNode
    @Binding var graph: NodeGraph
    let value: NodeValue?
    let error: String?
    let isOutput: Bool
    @Binding var dragLink: (from: Int, to: CGPoint)?
    let onLinkEnd: (Int, CGPoint) -> Void
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(node.kind.inputs.enumerated()), id: \.offset) { i, p in inputRow(i, p) }
            if node.kind == .number { numberBody }
            footer
        }
        .frame(width: NodeLayout.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(error != nil ? Theme.danger : (isOutput ? Theme.accent : Color.white.opacity(0.15)), lineWidth: isOutput || error != nil ? 1.5 : 1))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(node.kind.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
            if isOutput { Image(systemName: "arrow.down.to.line").font(.system(size: 9)).foregroundStyle(Theme.accent).help("Output: previewed and baked") }
            Spacer()
            Button { graph.remove(node.id) } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
                .help("Delete node")
        }
        .padding(.horizontal, 8)
        .frame(height: NodeLayout.header)
        .background(RoundedRectangle(cornerRadius: 7).fill(color(node.kind.output).opacity(0.28)))
        .contentShape(Rectangle())
        .gesture(DragGesture(coordinateSpace: .named("graph")).onChanged { g in
            if dragStart == nil { dragStart = CGPoint(x: node.x, y: node.y) }
            node.x = max(0, Double(dragStart!.x + g.translation.width)); node.y = max(0, Double(dragStart!.y + g.translation.height))
        }.onEnded { _ in dragStart = nil })
        .overlay(alignment: .trailing) {
            Circle().fill(color(node.kind.output)).frame(width: 11, height: 11).offset(x: 6)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("graph"))
                    .onChanged { g in dragLink = (node.id, g.location) }
                    .onEnded { g in onLinkEnd(node.id, g.location) })
                .help("Drag to an input to connect")
        }
    }

    private func inputRow(_ i: Int, _ p: NodeKind.Port) -> some View {
        let linked = graph.links.contains { $0.to == node.id && $0.port == p.name }
        return HStack(spacing: 4) {
            Circle().fill(linked ? color(p.type) : Color(white: 0.35)).frame(width: 10, height: 10).offset(x: -5)
                .onTapGesture { if linked { graph.disconnect(to: node.id, port: p.name) } }
                .help(linked ? "Click to disconnect" : "\(p.type.rawValue) input")
            Text(p.name).font(.system(size: 10)).foregroundStyle(Theme.textDim).frame(width: 52, alignment: .leading).lineLimit(1)
            if !linked {
                switch p.type {
                case .number: field(p.name, p.defaultValue, width: 96)
                case .point:
                    field(p.name + ".x", p.defaultValue, width: 36); field(p.name + ".y", 0, width: 36); field(p.name + ".z", 0, width: 30)
                case .geometry, .element: Text("connect").font(.system(size: 9.5)).foregroundStyle(Theme.textFaint)
                }
            } else {
                Text("linked").font(.system(size: 9.5)).foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(height: NodeLayout.row)
    }

    private var numberBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Slider(value: Binding(get: { node.param("value", 1000) }, set: { node.params["value"] = ($0 * 1000).rounded() / 1000 }),
                       in: node.param("min", 0)...max(node.param("max", 10000), node.param("min", 0) + 1e-6)).controlSize(.mini)
                field("value", 1000, width: 58)
            }
            HStack(spacing: 4) {
                Text("min").font(.system(size: 9)).foregroundStyle(Theme.textFaint); field("min", 0, width: 50)
                Text("max").font(.system(size: 9)).foregroundStyle(Theme.textFaint); field("max", 10000, width: 58)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private var footer: some View {
        Text(error ?? value?.summary ?? "—")
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(error != nil ? Theme.danger : Theme.textDim)
            .lineLimit(2)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func field(_ key: String, _ def: Double, width: CGFloat) -> some View {
        TextField("", value: Binding(get: { node.params[key] ?? def }, set: { node.params[key] = $0 }), format: .number.precision(.fractionLength(0...3)))
            .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 3).frame(width: width, height: 18)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35)))
    }

    private func color(_ t: NodePortType) -> Color {
        switch t {
        case .number: return Color(red: 0.45, green: 0.75, blue: 1)
        case .point: return Color(red: 0.5, green: 0.9, blue: 0.55)
        case .geometry: return Theme.accent
        case .element: return Color(red: 0.95, green: 0.55, blue: 0.35)
        }
    }
}

// MARK: - Previews

private struct NodePreviewPlan: View {
    let geometry: [Geometry]
    var elements: [BIMGeometry] = []
    var body: some View {
        Canvas { ctx, size in
            var d = ArchiDocument()
            let footprints = elements.prefix(2000).map { g -> [Vec2] in
                let id = d.addElement(g)
                guard let el = d.element(id) else { return [] }
                let f = CommandHelpers.footprint(el, doc: d)
                return f.isEmpty ? f : f + [f[0]]
            }
            let polys = geometry.flatMap { GeometryOps.tessellate($0, doc: nil) } + footprints
            var b = BBox2.empty
            for p in polys { for v in p { b.add(v) } }
            guard !b.isEmpty else { return }
            let w = max(b.width, 1), h = max(b.height, 1)
            let s = min((size.width - 30) / w, (size.height - 30) / h)
            func map(_ v: Vec2) -> CGPoint { CGPoint(x: size.width / 2 + (v.x - b.center.x) * s, y: size.height / 2 - (v.y - b.center.y) * s) }
            var path = Path()
            for p in polys where p.count >= 2 {
                path.move(to: map(p[0])); for v in p.dropFirst() { path.addLine(to: map(v)) }
            }
            ctx.stroke(path, with: .color(Theme.accent), lineWidth: 1.2)
        }
        .overlay(alignment: .bottomLeading) {
            Text("\(geometry.count) object(s)\(elements.isEmpty ? "" : ", \(elements.count) element(s)")").font(Theme.fontSmall).foregroundStyle(Theme.textDim).padding(6)
        }
    }
}

private struct NodePreview3D: NSViewRepresentable {
    let geometry: [Geometry]
    var elements: [BIMGeometry] = []
    func makeCoordinator() -> Scene3DBuilder { Scene3DBuilder() }
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = context.coordinator.scene
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = NSColor(white: 0.1, alpha: 1)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.automaticallyAdjustsZRange = true; cam.name = "previewCamera"
        context.coordinator.scene.rootNode.addChildNode(cam)
        v.pointOfView = cam
        update(v, context.coordinator, frame: true)
        return v
    }
    func updateNSView(_ v: SCNView, context: Context) { update(v, context.coordinator, frame: false) }

    private func update(_ v: SCNView, _ b: Scene3DBuilder, frame: Bool) {
        var d = ArchiDocument()
        d.layers = [Layer(name: "0")]
        for g in geometry.prefix(5000) { d.add(g, layer: "0", color: .aci(2)) }
        for e in elements.prefix(2000) { _ = d.addElement(e) }
        let before = b.worldSphere
        b.update(doc: d, style: "Shaded with Edges")
        let s = b.worldSphere
        let moved = abs(s.radius - before.radius) > before.radius * 0.5
        if frame || moved, let cam = v.scene?.rootNode.childNode(withName: "previewCamera", recursively: false) {
            let dist = s.radius / sin(22.5 * .pi / 180) * 1.2
            let dir = Viewport3DController.norm(SCNVector3(1, 0.9, 1.2))
            cam.position = SCNVector3(s.center.x + dir.x * dist, s.center.y + dir.y * dist, s.center.z + dir.z * dist)
            cam.look(at: s.center)
            v.pointOfView = cam
        }
    }
}


/// Group frame: title bar drags the frame with its nodes; the corner handle resizes it.
private struct NodeFrameBox: View {
    @Binding var frame: NodeFrame
    @Binding var graph: NodeGraph
    @State private var last: CGSize = .zero
    @State private var resizeStart: CGSize?
    private static let colors: [Color] = [Color(red: 0.96, green: 0.77, blue: 0.09), .blue, .green, .purple, .orange, .teal]
    var body: some View {
        let c = Self.colors[abs(frame.color) % Self.colors.count]
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(c.opacity(0.08))
            RoundedRectangle(cornerRadius: 8).stroke(c.opacity(0.5), lineWidth: 1)
            HStack(spacing: 4) {
                TextField("Group", text: $frame.title).textFieldStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(graph.members(of: frame).count) nodes").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                Button { frame.color += 1 } label: { Image(systemName: "paintpalette").font(.system(size: 9)) }.buttonStyle(.plain).help("Change colour")
                Button { graph.groups.removeAll { $0.id == frame.id } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).help("Delete the group (keeps the nodes)")
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8).fill(c.opacity(0.25)))
            .gesture(DragGesture(coordinateSpace: .named("graph")).onChanged { g in
                let dx = g.translation.width - last.width, dy = g.translation.height - last.height
                last = g.translation
                graph.moveGroup(frame.id, dx: Double(dx), dy: Double(dy))
            }.onEnded { _ in last = .zero })
            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                .frame(width: 16, height: 16)
                .offset(x: frame.width - 18, y: frame.height - 18)
                .gesture(DragGesture(coordinateSpace: .named("graph")).onChanged { g in
                    if resizeStart == nil { resizeStart = CGSize(width: frame.width, height: frame.height) }
                    frame.width = max(160, Double(resizeStart!.width + g.translation.width)); frame.height = max(80, Double(resizeStart!.height + g.translation.height))
                }.onEnded { _ in resizeStart = nil })
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }
}

/// Sticky note on the node canvas.
private struct NodeCommentBox: View {
    @Binding var comment: NodeComment
    @Binding var graph: NodeGraph
    @State private var start: CGPoint?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "note.text").font(.system(size: 9))
                Spacer()
                Button { graph.comments.removeAll { $0.id == comment.id } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
            }
            .foregroundStyle(Color.black.opacity(0.6))
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .named("graph")).onChanged { g in
                if start == nil { start = CGPoint(x: comment.x, y: comment.y) }
                comment.x = max(0, Double(start!.x + g.translation.width)); comment.y = max(0, Double(start!.y + g.translation.height))
            }.onEnded { _ in start = nil })
            TextField("Comment", text: $comment.text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.black)
        }
        .padding(6)
        .frame(width: comment.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 1, green: 0.93, blue: 0.55)))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
