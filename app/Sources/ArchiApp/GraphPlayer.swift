// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Graph player (SCR-014): runs a saved node graph with its exposed inputs (the Number nodes, named like the script
/// export parameters) without opening the node editor; values are clamped to each input's range and the result is
/// baked as one undo step. Evaluation is deterministic (random nodes use their seed input).
enum GraphPlayer {
    struct Input: Equatable, Identifiable {
        var id: Int
        var name: String
        var value: Double
        var min: Double
        var max: Double
    }

    static func inputs(_ g: NodeGraph) -> [Input] {
        g.nodes.filter { $0.kind == .number }.map { n in
            let lo = n.param("min", 0), hi = n.param("max", 10000)
            return Input(id: n.id, name: g.parameterName(n), value: n.param("value", 0), min: Swift.min(lo, hi), max: Swift.max(lo, hi))
        }
    }

    /// The graph with input values (by parameter name or node id) applied and clamped to their ranges.
    static func applying(_ g0: NodeGraph, _ values: [String: Double]) -> NodeGraph {
        var g = g0
        for inp in inputs(g0) {
            guard let v = values[inp.name] ?? values["\(inp.id)"], let i = g.nodes.firstIndex(where: { $0.id == inp.id }) else { continue }
            g.nodes[i].params["value"] = Swift.min(Swift.max(v, inp.min), inp.max)
        }
        return g
    }

    /// Graphs available to play: the current one and the named ones.
    static func graphs(_ doc: ArchiDocument) -> [(name: String, graph: NodeGraph)] {
        var out: [(String, NodeGraph)] = []
        if let g = NodeGraph.load(doc) { out.append(("Current", g)) }
        for n in NodeGraph.names(doc) { if let g = NodeGraph.load(doc, name: n) { out.append((n, g)) } }
        return out
    }

    /// Evaluates and bakes into the document; returns the baked ids and the evaluation.
    @discardableResult
    static func run(_ g: NodeGraph, values: [String: Double], into doc: inout ArchiDocument) -> (ids: [EntityID], errors: [Int: String]) {
        let played = applying(g, values)
        let ev = played.evaluate()
        let ids = NodeGraphBake.bake(ev.output, elements: ev.elementOutput, into: &doc)
        return (ids, ev.errors)
    }
}

enum GraphPlayerWindow {
    @MainActor private static var window: NSWindow?
    @MainActor static func show(model: AppModel) {
        let v = GraphPlayerView(model: model).preferredColorScheme(Theme.colorScheme)
        if let w = window { w.contentViewController = NSHostingController(rootView: v); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 420), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Graph Player"
        w.isReleasedWhenClosed = false
        w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: v)
        w.center(); w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct GraphPlayerView: View {
    @ObservedObject var model: AppModel
    @State private var graphName = "Current"
    @State private var values: [String: Double] = [:]
    @State private var status = ""

    var body: some View {
        let all = GraphPlayer.graphs(model.doc)
        let g = all.first { $0.name == graphName }?.graph ?? all.first?.graph
        VStack(alignment: .leading, spacing: 10) {
            if all.isEmpty {
                Text("No saved graphs. Build one in the Node Editor (NODEEDITOR) and save it.").foregroundStyle(Theme.textDim)
            } else {
                Picker("Graph", selection: $graphName) { ForEach(all.map(\.name), id: \.self) { Text($0).tag($0) } }
                    .onChange(of: graphName) { values = [:] }
                if let g {
                    let ins = GraphPlayer.inputs(g)
                    if ins.isEmpty { Text("This graph has no Number inputs.").foregroundStyle(Theme.textDim) }
                    ForEach(ins) { inp in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(inp.name): \(fmt(values[inp.name] ?? inp.value, 2))").font(Theme.font)
                            Slider(value: Binding(get: { values[inp.name] ?? inp.value }, set: { values[inp.name] = $0 }), in: inp.min...max(inp.max, inp.min + 1e-9))
                        }
                    }
                    HStack {
                        Button("Reset") { values = [:] }
                        Spacer()
                        Button("Run") {
                            var ids: [EntityID] = []
                            model.editor.transaction("Graph Player") { d in ids = GraphPlayer.run(g, values: values, into: &d).ids }
                            status = "Baked \(ids.count) object(s)."
                        }.keyboardShortcut(.defaultAction)
                    }
                }
            }
            if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
            Spacer()
        }
        .padding(14).font(Theme.font).foregroundStyle(Theme.text).background(Theme.panel)
    }
}
