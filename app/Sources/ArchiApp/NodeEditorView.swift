// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
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
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentViewController = NSHostingController(rootView: NodeEditorView(model: model).preferredColorScheme(.dark))
        w.center(); w.makeKeyAndOrderFront(nil)
        windows[key] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = windows.removeValue(forKey: key) }
        }
    }
}

private enum NodeLayout {
    static let width: CGFloat = 188
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
                        links(ev)
                        ForEach(graph.nodes) { n in
                            NodeBox(node: binding(n.id), graph: $graph, value: ev.values[n.id], error: ev.errors[n.id],
                                    isOutput: graph.outputNodes.contains(n.id), dragLink: $dragLink, onLinkEnd: finishLink)
                                .offset(x: n.x, y: n.y)
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

    private func binding(_ id: Int) -> Binding<GraphNode> {
        Binding(get: { graph.node(id) ?? GraphNode(id: id, kind: .number, x: 0, y: 0) },
                set: { v in if let i = graph.nodes.firstIndex(where: { $0.id == id }) { graph.nodes[i] = v } })
    }

    private func toolbar(_ ev: NodeGraph.Evaluation) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(["Numbers", "Geometry", "Solids", "Transform"], id: \.self) { cat in
                    Section(cat) {
                        ForEach(NodeKind.allCases.filter { $0.category == cat }) { k in
                            Button(k.title) { let c = graph.nodes.count; graph.add(k, x: 40 + Double(c % 6) * 36, y: 40 + Double(c % 8) * 30) }
                        }
                    }
                }
            } label: { Label("Add Node", systemImage: "plus.circle") }
            .menuStyle(.borderlessButton).fixedSize()
            Button { graph = NodeGraph.sample } label: { Label("Sample", systemImage: "wand.and.stars") }.buttonStyle(FlatButtonStyle(compact: true))
            Button { graph = NodeGraph() } label: { Label("Clear", systemImage: "trash") }.buttonStyle(FlatButtonStyle(compact: true))
            Divider().frame(height: 16)
            Toggle("Live", isOn: $live).toggleStyle(.switch).controlSize(.mini)
                .help("Update the drawing on every change (the baked objects are replaced)")
            Button { bake() } label: { Label("Bake to Drawing", systemImage: "square.and.arrow.down.on.square") }
                .buttonStyle(FlatButtonStyle(prominent: true)).disabled(ev.output.isEmpty)
                .help("Write the output geometry into the drawing (one undo step; replaces the previous bake)")
            Button { saveGraph() } label: { Label("Save Graph", systemImage: "square.and.arrow.down") }.buttonStyle(FlatButtonStyle(compact: true))
                .help("Store the graph in the drawing (.archi)")
            Spacer()
            if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
            Text("\(graph.nodes.count) nodes · \(ev.output.count) objects\(ev.errors.isEmpty ? "" : " · \(ev.errors.count) error(s)")")
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
                NodePreview3D(geometry: ev.output)
            } else {
                NodePreviewPlan(geometry: ev.output)
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
        let out = graph.evaluate().output
        let g = graph
        var ids: [EntityID] = []
        model.editor.transaction("Node Graph") { d in
            ids = NodeGraphBake.bake(out, into: &d)
            g.store(in: &d)
        }
        status = "Baked \(ids.count) object(s) on layer NODES."
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
                case .geometry: Text("connect").font(.system(size: 9.5)).foregroundStyle(Theme.textFaint)
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
        }
    }
}

// MARK: - Previews

private struct NodePreviewPlan: View {
    let geometry: [Geometry]
    var body: some View {
        Canvas { ctx, size in
            let polys = geometry.flatMap { GeometryOps.tessellate($0, doc: nil) }
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
            Text("\(geometry.count) object(s)").font(Theme.fontSmall).foregroundStyle(Theme.textDim).padding(6)
        }
    }
}

private struct NodePreview3D: NSViewRepresentable {
    let geometry: [Geometry]
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
