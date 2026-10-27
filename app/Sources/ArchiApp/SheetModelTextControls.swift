// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

struct SheetModelTextControls: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var id = 0
    @State private var error = ""
    private var texts: [Entity] { model.doc.entities.filter { if case .text = $0.geometry { return true }; return false } }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Text from drawing on this sheet").font(.headline)
            Picker("Drawing text", selection: $id) {
                Text("Choose text…").tag(0)
                ForEach(texts, id: \.id) { entity in
                    if case .text(let text) = entity.geometry { Text("#\(entity.id): \(text.content)").tag(entity.id) }
                }
            }
            if id != 0 {
                let hidden = SheetModelText.isHidden(id, in: model.doc.layouts[layoutIndex])
                Button(hidden ? "Show Text on This Sheet" : "Hide Text on This Sheet") {
                    do {
                        var doc = model.doc
                        try SheetModelText.set(&doc, layoutIndex: layoutIndex, id: id, hidden: !hidden)
                        model.editor.transaction("Sheet Model Text") { $0 = doc }; error = ""
                    } catch { self.error = error.localizedDescription }
                }
            }
            Text("For a title such as PIANTA PIANO PRIMO drawn in 2D. Hides only this text on this sheet and its PDF; the drawing and other sheets keep it. Text inside a block is edited with BEDIT.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            Divider()
        }
    }
}
