// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

struct NamedPageSetupControls: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    let draft: () -> ArchiDocument
    let load: (NamedPageSetup) -> Void
    @State private var name = ""
    @State private var selected = ""
    @State private var targets = Set<Int>()
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAMED PAGE SETUPS").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            HStack {
                Picker("Setup", selection: $selected) {
                    Text("Choose…").tag("")
                    ForEach(NamedPageSetups.names(model.doc), id: \.self) { Text($0).tag($0) }
                }
                Button("Load") { if let p = NamedPageSetups.find(selected, doc: model.doc) { load(p) } }
                    .disabled(selected.isEmpty).buttonStyle(FlatButtonStyle(compact: true))
                Button("Delete") { model.editor.transaction("Delete Page Setup") { NamedPageSetups.delete(selected, doc: &$0) }; selected = "" }
                    .disabled(selected.isEmpty).buttonStyle(FlatButtonStyle(compact: true))
            }
            HStack {
                TextField("Save current settings as…", text: $name).darkField()
                Button("Save") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    guard let preset = NamedPageSetups.capture(draft(), layoutIndex: layoutIndex), !n.isEmpty else { return }
                    model.editor.transaction("Save Page Setup") { NamedPageSetups.save(preset, name: n, doc: &$0) }
                    selected = n; message = "Saved \(n)."
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).buttonStyle(FlatButtonStyle(compact: true))
                Button("Import…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "archi")!]
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    do {
                        let source = try DocumentIO.read(url)
                        var count = 0
                        model.editor.transaction("Import Page Setups") { count = NamedPageSetups.importFrom(source, doc: &$0) }
                        message = "Imported \(count) setup(s)."
                    } catch { message = error.localizedDescription }
                }.buttonStyle(FlatButtonStyle(compact: true))
            }
            HStack {
                Menu("Sheets (\(targets.count))") {
                    Button("Select All") { targets = Set(model.doc.layouts.indices) }
                    Button("Current Sheet") { targets = [layoutIndex] }
                    Divider()
                    ForEach(Array(model.doc.layouts.enumerated()), id: \.offset) { i, sheet in
                        Toggle(sheet.name, isOn: Binding(get: { targets.contains(i) }, set: { on in if on { targets.insert(i) } else { targets.remove(i) } }))
                    }
                }
                Button("Apply to Selected") { apply(to: targets.sorted()) }
                    .disabled(selected.isEmpty || targets.isEmpty).buttonStyle(FlatButtonStyle(compact: true))
                Button("Apply to All") { apply(to: Array(model.doc.layouts.indices)) }
                    .disabled(selected.isEmpty).buttonStyle(FlatButtonStyle(compact: true))
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .onAppear { targets = [layoutIndex] }
    }

    private func apply(to indices: [Int]) {
        guard let preset = NamedPageSetups.find(selected, doc: model.doc) else { return }
        do {
            var updated = model.doc
            try NamedPageSetups.apply(preset, to: indices, doc: &updated)
            model.editor.transaction("Apply Page Setup") { $0 = updated }
            if indices.contains(layoutIndex) { load(preset) }
            message = "Applied to \(indices.count) sheet(s). Undo restores the previous settings."
        } catch { message = error.localizedDescription }
    }
}
