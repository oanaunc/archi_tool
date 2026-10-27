// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

struct SheetRevisionControls: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var width = "180"
    @State private var rowHeight = "5"
    @State private var error = ""
    private var layout: ArchiCore.Layout { model.doc.layouts[layoutIndex] }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Revision history / revisioni").font(.headline)
            Picker("Placement", selection: Binding(get: { SheetRevisionPresentation.placement(layout) }, set: { mode in
                apply(mode: mode)
            })) {
                Text("Above cartiglio").tag(SheetRevisionPresentation.Placement.above)
                Text("Inside cartiglio").tag(SheetRevisionPresentation.Placement.inside)
                Text("Cartiglio fields only").tag(SheetRevisionPresentation.Placement.fields)
            }
            HStack {
                VStack(alignment: .leading) { Text("Table width mm").font(.caption); TextField("Width", text: $width) }
                VStack(alignment: .leading) { Text("Row height mm").font(.caption); TextField("Row height", text: $rowHeight) }
            }.textFieldStyle(.roundedBorder)
            Button("Apply Revision Table Size") { apply(mode: SheetRevisionPresentation.placement(layout)) }
            Text("Fields only removes the separate table. Revision fields still update automatically. In a custom cartiglio, reserve space for the table or use {revision}, {revisionDate}, {revisionDescription}, {revisionBy}. Use {revision.1.code}, {revision.1.date}, {revision.1.description}, {revision.1.by} for history rows.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }.onAppear { load() }
        .onChange(of: model.revision) { _ in load() }
    }
    private func load() { width = fmt(SheetRevisionPresentation.width(layout)); rowHeight = fmt(SheetRevisionPresentation.rowHeight(layout)) }
    private func apply(mode: SheetRevisionPresentation.Placement) {
        guard let w = Double(width.replacingOccurrences(of: ",", with: ".")), let h = Double(rowHeight.replacingOccurrences(of: ",", with: ".")) else { error = "Enter numeric sizes."; return }
        do {
            var l = layout
            try SheetRevisionPresentation.set(mode, width: w, rowHeight: h, in: &l)
            model.editor.transaction("Revision Table") { $0.layouts[layoutIndex] = l }; error = ""
        } catch { self.error = error.localizedDescription }
    }
}
