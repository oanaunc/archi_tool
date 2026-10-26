// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Always reachable below the scrolling sheet toolbar, including on smaller displays.
struct SheetCustomizationView: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var part: SheetCustomization.Part = .north
    @State private var offsetX = "0"
    @State private var offsetY = "0"
    @State private var viewportIndex = 0
    @State private var x = "0"
    @State private var y = "0"
    @State private var width = "100"
    @State private var height = "100"
    @State private var centerX = "0"
    @State private var centerY = "0"
    @State private var scale = "100"
    @State private var error = ""
    private var layout: ArchiCore.Layout? { model.doc.layouts.indices.contains(layoutIndex) ? model.doc.layouts[layoutIndex] : nil }
    private var viewport: Viewport? { layout.flatMap { $0.viewports.indices.contains(viewportIndex) ? $0.viewports[viewportIndex] : nil } }
    private var locked: Bool { ViewportLock.isLocked(model.doc, layoutIndex: layoutIndex, viewport: viewportIndex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Customize Sheet").font(.headline)
                Text("Changes apply to this sheet and its PDF. ⌘Z undoes each change.").font(.caption).foregroundStyle(.secondary)
                if let l = layout {
                    ForEach(SheetCustomization.Part.allCases, id: \.self) { p in
                        Toggle(label(p), isOn: Binding(get: { SheetCustomization.visible(p, in: l) }, set: { on in
                            model.editor.transaction("Sheet \(p.rawValue)") { d in
                                SheetCustomization.set(p, visible: on, offset: SheetCustomization.offset(p, in: d.layouts[layoutIndex]), in: &d.layouts[layoutIndex])
                            }
                        })).toggleStyle(.checkbox)
                    }
                    Picker("Move element", selection: $part) {
                        ForEach([SheetCustomization.Part.titleBlock, .north, .scaleBar], id: \.self) { Text(label($0)).tag($0) }
                    }.onChange(of: part) { _ in loadOffset() }
                    HStack { field("ΔX mm", $offsetX); field("ΔY mm", $offsetY) }
                    Button("Apply Element Offset") { applyOffset() }
                    Text("Offsets from the default position: +X right, +Y up.").font(.caption).foregroundStyle(.secondary)
                    Button("Edit Title Block…") { model.sheet = .titleBlock(layoutIndex) }
                    Text("Text, studio name, project, client, date, revision and logo. For a custom drawing: TITLEBLOCKDESIGN.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Viewport / plan").font(.headline)
                    if l.viewports.isEmpty { Text("Add a viewport first.").foregroundStyle(.secondary) }
                    else {
                        Picker("Viewport", selection: $viewportIndex) {
                            ForEach(Array(l.viewports.enumerated()), id: \.offset) { i, v in Text("\(i + 1). \(SheetComposer.viewTitle(v, doc: model.doc))").tag(i) }
                        }.onChange(of: viewportIndex) { _ in loadViewport() }
                        Toggle("Lock viewport", isOn: Binding(get: { locked }, set: { on in
                            model.editor.transaction("Viewport Lock") { ViewportLock.set(&$0, layoutIndex: layoutIndex, viewport: viewportIndex, locked: on) }
                        })).toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { field("X mm", $x); field("Y mm", $y) }
                            Button("Apply Position") { edit("Position", x, y) }
                            HStack { field("Width mm", $width); field("Height mm", $height) }
                            Button("Apply Size") { edit("Size", width, height) }
                            field("Scale 1:", $scale)
                            Button("Apply Scale (keep frame)") { edit("Scale", scale) }
                            HStack { field("Centre X", $centerX); field("Centre Y", $centerY) }
                            Button("Apply Model Centre") { edit("Center", centerX, centerY) }
                            Button("Centre Content (keep scale)") { edit("CenterContent") }
                            Button("Centre Frame on Page") { edit("CenterOnSheet") }
                            Button("Fit Content (changes scale)") { model.syncCurrentTab(); model.runCommand("VPFIT \(viewportIndex + 1)") }
                            Text("Paper position is the frame's lower-left corner. Model centre uses drawing units. You can also drag the frame on the sheet.").font(.caption).foregroundStyle(.secondary)
                        }.disabled(locked)
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            }.padding(14)
        }
        .frame(width: 310, height: 620)
        .onAppear { viewportIndex = model.selectedSheetViewport ?? 0; loadOffset(); loadViewport() }
        .onChange(of: model.revision) { _ in loadOffset(); loadViewport() }
    }
    private func label(_ p: SheetCustomization.Part) -> String {
        switch p { case .frame: return "Page border"; case .titleBlock: return "Title block / cartiglio"; case .north: return "North arrow / Nord"; case .scaleBar: return "Scale bar"; case .captions: return "Automatic view captions" }
    }
    private func field(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(.secondary); TextField(label, text: value).textFieldStyle(.roundedBorder) }
    }
    private func number(_ text: String) -> Double? {
        guard let n = Double(text.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return nil }; return n
    }
    private func loadOffset() {
        guard let l = layout else { return }; let p = SheetCustomization.offset(part, in: l)
        offsetX = fmt(p.x, 3); offsetY = fmt(p.y, 3)
    }
    private func loadViewport() {
        guard let v = viewport else { return }
        x = fmt(v.origin.x, 3); y = fmt(v.origin.y, 3); width = fmt(v.size.x, 3); height = fmt(v.size.y, 3)
        centerX = fmt(v.viewCenter.x, 3); centerY = fmt(v.viewCenter.y, 3); scale = fmt(v.scale * model.doc.units.mm, 4)
    }
    private func applyOffset() {
        guard let dx = number(offsetX), let dy = number(offsetY) else { error = "Enter numeric offsets."; return }
        model.editor.transaction("Move Sheet Element") { d in
            SheetCustomization.set(part, visible: SheetCustomization.visible(part, in: d.layouts[layoutIndex]), offset: Vec2(dx, dy), in: &d.layouts[layoutIndex])
        }; error = ""
    }
    private func edit(_ property: String, _ first: String = "0", _ second: String = "0") {
        guard let vp = viewport, let a = number(first), let b = number(second) else { error = "Enter numeric values."; return }
        do {
            let result = try SheetViewportEditing.updated(vp, property: property, point: Vec2(a, b), ratio: a, doc: model.doc, layoutIndex: layoutIndex, index: viewportIndex)
            model.editor.transaction("Viewport \(property)") { $0.layouts[layoutIndex].viewports[viewportIndex] = result }
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}
