// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Graphic styles manager: dialog for the core graphic-style data (`GraphicStyles`): named line styles and their
/// layer assignments (LAY-034), lineweights by view scale (LAY-035), pen sets (LAY-036) and rule-based graphic
/// override filters (LAY-037). Every edit is one undo step in the drawing.
private struct GraphicStylesView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0
    @State private var newStyle = ""
    @State private var lwText = ""
    @State private var penName = ""
    @State private var penText = ""
    @State private var message = ""
    @State private var rule = GraphicStyles.FilterRule(name: "Rule", field: "layer", op: "=", value: "", override: GraphicOverride(color: RGBA(1, 0, 0)))
    @State private var ruleColor = "#FF0000"
    @State private var ruleWeight = ""

    private var doc: ArchiDocument { model.doc }
    private func edit(_ label: String, _ f: (inout ArchiDocument) -> Void) { model.editor.transaction(label, f) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $page) {
                Text("Line Styles").tag(0); Text("Layers").tag(1); Text("Lineweight by Scale").tag(2); Text("Pen Sets").tag(3); Text("Filters").tag(4)
            }
            .pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    switch page {
                    case 0: lineStyles
                    case 1: layers
                    case 2: lwTable
                    case 3: pens
                    default: filters
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .font(Theme.font)
        .padding(12)
        .frame(minWidth: 620, minHeight: 420)
        .background(Theme.panel)
        .onAppear {
            lwText = doc.variable(GraphicStyles.lineweightTableVariable) ?? ""
        }
    }

    // MARK: Line styles

    @ViewBuilder private var lineStyles: some View {
        ForEach(GraphicStyles.lineStyleNames(doc), id: \.self) { key in
            if let s = GraphicStyles.lineStyle(key, doc: doc) {
                HStack(spacing: 8) {
                    Text(s.name).frame(width: 130, alignment: .leading)
                    TextField("Colour (ByLayer, 1–255, r,g,b)", text: Binding(get: { s.color?.text ?? "" }, set: { v in var n = s; n.color = v.isEmpty ? nil : ColorRef.parse(v); edit("Line Style") { GraphicStyles.setLineStyle(n, doc: &$0) } }))
                        .darkField().frame(width: 110)
                    TextField("mm", value: Binding(get: { s.lineweight ?? -1 }, set: { v in var n = s; n.lineweight = v >= 0 ? min(v, 5) : nil; edit("Line Style") { GraphicStyles.setLineStyle(n, doc: &$0) } }), format: .number)
                        .darkField().frame(width: 60).help("Lineweight in mm (−1 = ByLayer)")
                    Picker("", selection: Binding(get: { s.linetype ?? "" }, set: { v in var n = s; n.linetype = v.isEmpty ? nil : v; edit("Line Style") { GraphicStyles.setLineStyle(n, doc: &$0) } })) {
                        Text("ByLayer").tag("")
                        ForEach(doc.linetypes.map(\.name), id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    IconButton(symbol: "trash", help: "Delete the line style") { edit("Delete Line Style") { GraphicStyles.deleteLineStyle(key, doc: &$0) } }
                }
            }
        }
        HStack {
            TextField("New line style name", text: $newStyle).darkField().frame(width: 200)
            Button("Add") {
                let n = newStyle.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                edit("New Line Style") { GraphicStyles.setLineStyle(GraphicStyles.LineStyle(name: n, lineweight: 0.25), doc: &$0) }
                newStyle = ""
            }.buttonStyle(FlatButtonStyle(compact: true))
        }
    }

    @ViewBuilder private var layers: some View {
        let styles = GraphicStyles.lineStyleNames(doc).compactMap { GraphicStyles.lineStyle($0, doc: doc)?.name }
        if styles.isEmpty { Text("Add line styles first.").foregroundStyle(Theme.textDim) }
        ForEach(doc.layers.map(\.name), id: \.self) { l in
            HStack {
                Text(l).frame(width: 180, alignment: .leading)
                Picker("", selection: Binding(get: { GraphicStyles.layerLineStyle(l, doc: doc) ?? "" }, set: { v in edit("Layer Line Style") { GraphicStyles.setLayerLineStyle(l, v.isEmpty ? nil : v, doc: &$0) } })) {
                    Text("None").tag("")
                    ForEach(styles, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }
        }
    }

    // MARK: Lineweight table

    @ViewBuilder private var lwTable: some View {
        Text("Lineweight factor per view scale, e.g. 1:20=1.4; 1:50=1; 1:100=0.7; 1:200=0.5").foregroundStyle(Theme.textDim)
        HStack {
            TextField("", text: $lwText).darkField()
            Button("Apply") {
                let rows = GraphicStyles.parseTable(lwText)
                if lwText.trimmingCharacters(in: .whitespaces).isEmpty { edit("Lineweight Table") { $0.variables[GraphicStyles.lineweightTableVariable] = nil }; message = "Table cleared."; return }
                guard !rows.isEmpty else { message = "No valid rows (use 1:50=1)."; return }
                edit("Lineweight Table") { $0.setVariable(GraphicStyles.lineweightTableVariable, lwText) }
                message = "\(rows.count) row(s)."
            }.buttonStyle(FlatButtonStyle(compact: true))
        }
        ForEach(Array(GraphicStyles.lineweightTable(doc).enumerated()), id: \.offset) { _, r in
            Text("1:\(fmt(r.scale, 0)) → × \(fmt(r.factor, 2))").font(Theme.mono)
        }
    }

    // MARK: Pen sets

    @ViewBuilder private var pens: some View {
        let names = GraphicStyles.penSetNames(doc)
        HStack {
            Text("Active pen set")
            Picker("", selection: Binding(get: { doc.variable(GraphicStyles.currentPenSetVariable) ?? "" }, set: { v in edit("Pen Set") { if v.isEmpty { $0.variables[GraphicStyles.currentPenSetVariable] = nil } else { $0.setVariable(GraphicStyles.currentPenSetVariable, v) } } })) {
                Text("None").tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden().frame(width: 160)
            Toggle("Show on screen", isOn: Binding(get: { doc.variable(GraphicStyles.penSetDisplayVariable) == "1" }, set: { v in edit("Pen Set Display") { $0.setVariable(GraphicStyles.penSetDisplayVariable, v ? "1" : "0") } }))
        }
        ForEach(names, id: \.self) { n in
            HStack {
                Text(n).frame(width: 120, alignment: .leading)
                Text(doc.variable(GraphicStyles.penSetPrefix + n) ?? "").font(Theme.mono).lineLimit(1).truncationMode(.tail)
                Spacer()
                Button("Edit") { penName = n; penText = doc.variable(GraphicStyles.penSetPrefix + n) ?? "" }.buttonStyle(FlatButtonStyle(compact: true))
                IconButton(symbol: "trash", help: "Delete") { edit("Delete Pen Set") { $0.variables[(GraphicStyles.penSetPrefix + n).uppercased()] = nil } }
            }
        }
        Text("Pens: number=weight[,colour]; e.g. 1=0.18;2=0.25;3=0.35,0,0,0;7=0.5").foregroundStyle(Theme.textDim)
        HStack {
            TextField("Name", text: $penName).darkField().frame(width: 120)
            TextField("Pens", text: $penText).darkField()
            Button("Save") {
                let n = penName.trimmingCharacters(in: .whitespaces)
                let p = GraphicStyles.parsePens(penText)
                guard !n.isEmpty, !p.isEmpty else { message = "Give a name and at least one pen."; return }
                edit("Pen Set") { GraphicStyles.setPenSet(n, p, doc: &$0) }
                message = "Pen set \(n): \(p.count) pen(s)."
            }.buttonStyle(FlatButtonStyle(compact: true))
        }
    }

    // MARK: Filters

    @ViewBuilder private var filters: some View {
        let fs = GraphicStyles.filters(doc)
        ForEach(Array(fs.enumerated()), id: \.offset) { i, r in
            HStack {
                Toggle("", isOn: Binding(get: { r.enabled }, set: { v in var all = fs; all[i].enabled = v; edit("Graphic Filter") { GraphicStyles.setFilters(all, doc: &$0) } })).labelsHidden()
                Text(r.name).frame(width: 110, alignment: .leading)
                Text("\(r.field) \(r.op) \(r.value)").font(Theme.mono)
                Text(describe(r.override)).foregroundStyle(Theme.textDim)
                Spacer()
                IconButton(symbol: "arrow.up", help: "Higher priority") { var all = fs; if i > 0 { all.swapAt(i, i - 1) }; edit("Graphic Filter") { GraphicStyles.setFilters(all, doc: &$0) } }.disabled(i == 0)
                IconButton(symbol: "trash", help: "Delete") { var all = fs; all.remove(at: i); edit("Graphic Filter") { GraphicStyles.setFilters(all, doc: &$0) } }
            }
        }
        Divider()
        HStack {
            TextField("Name", text: $rule.name).darkField().frame(width: 90)
            Picker("", selection: $rule.field) { ForEach(["layer", "type", "color", "linetype", "lineweight"], id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 100)
            Picker("", selection: $rule.op) { ForEach(GraphicStyles.ops, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 90)
            TextField("Value", text: $rule.value).darkField().frame(width: 90)
        }
        HStack {
            TextField("Colour #RRGGBB", text: $ruleColor).darkField().frame(width: 110)
            TextField("Lineweight", text: $ruleWeight).darkField().frame(width: 80)
            Toggle("Halftone", isOn: Binding(get: { rule.override.halftone ?? false }, set: { rule.override.halftone = $0 ? true : nil }))
            Toggle("Hide", isOn: Binding(get: { rule.override.hidden ?? false }, set: { rule.override.hidden = $0 ? true : nil }))
            Button("Add Rule") {
                var r = rule
                r.override.color = RGBA(hexString: ruleColor)
                r.override.lineweight = Double(ruleWeight).flatMap { $0 >= 0 ? $0 : nil }
                guard !r.value.isEmpty, !r.override.isEmpty else { message = "Give a value and an override."; return }
                edit("Graphic Filter") { GraphicStyles.setFilters(GraphicStyles.filters($0) + [r], doc: &$0) }
                message = "Rule \(r.name) added."
            }.buttonStyle(FlatButtonStyle(compact: true))
        }
    }
    private func describe(_ o: GraphicOverride) -> String {
        var p: [String] = []
        if o.hidden == true { p.append("hidden") }
        if let c = o.color { p.append(c.hexRGB) }
        if let w = o.lineweight { p.append(fmt(w, 2) + " mm") }
        if o.halftone == true { p.append("halftone") }
        return p.joined(separator: ", ")
    }
}

@MainActor
enum GraphicStylesWindow {
    private static var window: NSWindow?
    static func show(model: AppModel) {
        let view = GraphicStylesView(model: model).preferredColorScheme(Theme.colorScheme)
        if let w = window { w.contentViewController = NSHostingController(rootView: view); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Graphic Styles"; w.isReleasedWhenClosed = false; w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: view)
        w.center(); w.makeKeyAndOrderFront(nil)
        window = w
    }
}
