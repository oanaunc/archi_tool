// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

struct TitleBlockFieldControls: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var path = ""
    @State private var field = "revision"
    @State private var message = ""
    private var layout: ArchiCore.Layout { model.doc.layouts[layoutIndex] }
    private var block: String? { CustomTitleBlock.blockName(model.doc, layout: layout.name) }
    var body: some View {
        if let block {
            VStack(alignment: .leading, spacing: 7) {
                let texts = TitleBlockFields.texts(model.doc, block: block)
                Text("Link custom cartiglio text").font(.headline)
                Text("Current revision: \(SheetRevisionPresentation.fields(layout)["revision"] ?? "—") · \(EngineSheets.revisions(layout).count) revisions").font(.caption)
                Picker("Text to replace", selection: $path) {
                    Text("Choose text…").tag("")
                    ForEach(texts, id: \.path) { item in Text("\(item.path): \(item.text)").tag(item.path) }
                }
                Picker("Automatic field", selection: $field) {
                    Text("Revision code (A, B, 01…)").tag("revision")
                    Text("Number of revisions (0, 1, 2…)").tag("revisionCount")
                    Text("Revision date").tag("revisionDate")
                    Text("Revision description").tag("revisionDescription")
                    Text("Revision author").tag("revisionBy")
                }
                Button("Link Selected Text") {
                    do {
                        var doc = model.doc
                        try TitleBlockFields.bind(&doc, block: block, path: path, field: field)
                        model.editor.transaction("Link Cartiglio Field") { $0 = doc }
                        message = "Linked to {\(field)}."
                    } catch { message = error.localizedDescription }
                }.disabled(path.isEmpty)
                Text("Replaces the selected text with a live field, including in nested blocks. Shared blocks update on every sheet. Add a revision from Sheet Set → Revisions or SHEETREVISION.").font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).font(.caption) }
            }
        }
    }
}
