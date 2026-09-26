// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import ArchiCore

extension Plotter {
    /// Bookmark titles of sheets: "A101 — Ground Floor Plan".
    static func bookmarkTitle(_ doc: ArchiDocument, _ i: Int) -> String {
        let num = SheetSet.number(doc, i)
        let name = doc.layouts[i].name
        return num.isEmpty || name.hasPrefix(num) ? name : "\(num) — \(name)"
    }

    /// Multi-page PDF of the chosen sheets; with bookmarks, the PDF outline lists every sheet (batch publish).
    @MainActor static func publishPDF(doc: ArchiDocument, layouts: [Int], to url: URL, bookmarks: Bool, progress: ((Int, Int) -> Bool)? = nil) throws {
        let list = layouts.filter { doc.layouts.indices.contains($0) && !SheetTools.isPlaceholder(doc.layouts[$0]) }
        try writeSheetsPDF(doc: doc, to: url, layouts: list, progress: progress)
        PlotLog.record(drawing: doc.info.name, output: bookmarks ? "Publish (bookmarks)" : "Publish", sheets: list.map { SheetSet.number(doc, $0) }.joined(separator: " "),
                       style: Set(list.map { PageSetup.load(doc, layoutIndex: $0).plotStyleTable ?? PageSetup.load(doc, layoutIndex: $0).colorMode.rawValue }).sorted().joined(separator: " "),
                       file: url.path)
        guard bookmarks, let pdf = PDFDocument(url: url) else { return }
        let root = PDFOutline()
        for (k, li) in list.enumerated() {
            guard let page = pdf.page(at: k) else { continue }
            let item = PDFOutline()
            item.label = bookmarkTitle(doc, li)
            let box = page.bounds(for: .mediaBox)
            item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: box.height))
            root.insertChild(item, at: root.numberOfChildren)
        }
        pdf.outlineRoot = root
        pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] = "\(doc.info.name) — \(list.count) sheet(s)"
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf")
        guard pdf.write(to: tmp) else { throw ExportError(errorDescription: "Could not add bookmarks to \(url.lastPathComponent).") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

// MARK: - Batch publish (BATCHPUBLISH)

struct BatchPublishSheet: View {
    @ObservedObject var model: AppModel
    @State private var chosen: Set<Int> = []
    @State private var bookmarks = true
    @State private var index = false
    @State private var status = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Batch Publish to PDF").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(chosen.count) of \(model.doc.layouts.count) sheets").foregroundStyle(Theme.textDim) }
                .padding(14)
            HSeparator()
            List {
                ForEach(Array(model.doc.layouts.enumerated()), id: \.offset) { i, l in
                    Toggle(isOn: Binding(get: { chosen.contains(i) }, set: { if $0 { chosen.insert(i) } else { chosen.remove(i) } })) {
                        HStack {
                            Text(SheetSet.number(model.doc, i)).font(Theme.mono).frame(width: 70, alignment: .leading)
                            Text(l.name)
                            Spacer()
                            Text("\(l.paper.name) · \(PageSetup.load(model.doc, layoutIndex: i).plotStyleTable ?? PageSetup.load(model.doc, layoutIndex: i).colorMode.rawValue)")
                                .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            }
            .frame(height: 260)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("PDF bookmarks (sheet number — name)", isOn: $bookmarks)
                Toggle("Refresh the sheet index table on the first sheet", isOn: $index)
                if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.accent) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            HSeparator()
            HStack {
                Button("All") { chosen = Set(model.doc.layouts.indices) }.buttonStyle(FlatButtonStyle(compact: true))
                Button("None") { chosen = [] }.buttonStyle(FlatButtonStyle(compact: true))
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Publish…") { publish() }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).disabled(chosen.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 560)
        .font(Theme.font)
        .background(Theme.panel)
        .onAppear { chosen = Set(model.doc.layouts.indices) }
    }

    private func publish() {
        if index { model.editor.transaction("Sheet Index") { _ = SheetSet.placeIndex(&$0, on: 0) } }
        let p = NSSavePanel()
        p.allowedContentTypes = [.pdf]
        p.nameFieldStringValue = "\(model.displayName) — sheets.pdf"
        if let d = FileLocations.exportFolder ?? model.editor.fileURL?.deletingLastPathComponent() { p.directoryURL = d }
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try Plotter.publishPDF(doc: model.doc, layouts: chosen.sorted(), to: url, bookmarks: bookmarks)
            model.editor.print("Published \(chosen.count) sheet(s)\(bookmarks ? " with bookmarks" : "") to \(url.path)")
            model.sheet = nil
        } catch { status = error.localizedDescription }
    }
}

// MARK: - Plot style table editor (PLOTSTYLE)

struct PlotStyleSheet: View {
    @ObservedObject var model: AppModel
    @State private var table = PlotStyleTable.archiPens
    @State private var original = ""
    @State private var showAll = false

    private var indices: [Int] { showAll ? Array(0...255) : [0] + Array(1...9) + [250, 251, 252, 253, 254, 255] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Plot Style Tables").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("", selection: Binding(get: { table.name }, set: { n in if let t = PlotStyleTable.named(n, in: model.doc) { table = t; original = t.name } })) {
                    ForEach(PlotStyleTable.all(model.doc), id: \.name) { Text($0.name).tag($0.name) }
                    if PlotStyleTable.named(table.name, in: model.doc) == nil { Text(table.name).tag(table.name) }
                }
                .labelsHidden().frame(width: 200)
                Button("New Copy") { table.name = uniqueName(table.name) }.buttonStyle(FlatButtonStyle(compact: true))
            }
            .padding(14)
            HSeparator()
            HStack { Text("Name"); TextField("", text: $table.name).darkField().frame(width: 220); Spacer(); Toggle("All 255 colours", isOn: $showAll) }
                .padding(.horizontal, 14).padding(.vertical, 8)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Object colour").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        Text("Pen colour").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        Text("Lineweight").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        Text("Screening").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    }
                    ForEach(indices, id: \.self) { i in row(i) }
                }
                .padding(14)
            }
            .frame(height: 340)
            HSeparator()
            HStack {
                Text("ACI colours map to pens; \"Other\" applies to true colours.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Close") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save in Drawing") { save() }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 620)
        .font(Theme.font)
        .background(Theme.panel)
        .onAppear {
            let li = model.mode == .sheet ? model.activeLayout : -1
            if let t = PlotStyleTable.named(PageSetup.load(model.doc, layoutIndex: li >= 0 ? li : nil).plotStyleTable, in: model.doc) { table = t }
            original = table.name
        }
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let pen = table.pens[i]
        GridRow {
            HStack(spacing: 6) {
                if i == 0 { Image(systemName: "paintpalette").frame(width: 14) } else { Image(nsImage: swatchImage(aciColor(i), size: 12)) }
                Text(i == 0 ? "Other" : "Color \(i)")
            }
            .frame(width: 110, alignment: .leading)
            HStack(spacing: 4) {
                Toggle("Object", isOn: Binding(get: { pen?.color == nil }, set: { on in update(i) { $0.color = on ? nil : 0x000000 } })).controlSize(.small)
                if let c = pen?.color {
                    ColorPicker("", selection: Binding(get: { Color(hex: c) }, set: { v in update(i) { $0.color = RGBA(v).hex24 } }), supportsOpacity: false).labelsHidden()
                }
            }
            .frame(width: 130, alignment: .leading)
            Picker("", selection: Binding(get: { pen?.lineweight ?? -1 }, set: { v in update(i) { $0.lineweight = v < 0 ? nil : v } })) {
                Text("Object").tag(-1.0)
                ForEach(standardLineweights, id: \.self) { w in Text(String(format: "%.2f mm", w)).tag(w) }
            }
            .labelsHidden().frame(width: 110)
            HStack {
                Slider(value: Binding(get: { pen?.screening ?? 100 }, set: { v in update(i) { $0.screening = v.rounded() } }), in: 0...100).frame(width: 90)
                Text("\(Int(pen?.screening ?? 100))%").font(Theme.mono).frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func update(_ i: Int, _ f: (inout PlotStyleTable.Pen) -> Void) {
        var p = table.pens[i] ?? PlotStyleTable.Pen()
        f(&p)
        table.pens[i] = p
    }

    private func uniqueName(_ base: String) -> String {
        let stem = base.replacingOccurrences(of: ".ctb", with: "")
        var k = 2
        while PlotStyleTable.named("\(stem) \(k).ctb", in: model.doc) != nil { k += 1 }
        return "\(stem) \(k).ctb"
    }

    private func save() {
        var t = table
        if !t.name.lowercased().hasSuffix(".ctb") { t.name += ".ctb" }
        let old = original
        model.editor.transaction("Plot Style Table") { d in
            if old.lowercased() != t.name.lowercased() { _ = old }
            t.store(in: &d)
        }
        table = t; original = t.name
        model.editor.print("Plot style table \(t.name) saved in the drawing. Choose it in Page Setup (or PLOTSTYLE Set).")
    }
}

// MARK: - Spelling dialog (SPELLDIALOG)

struct SpellingSheet: View {
    @ObservedObject var model: AppModel
    @State private var words: [SpellCheck.Word] = []
    @State private var index = 0
    @State private var ignored: Set<String> = []
    @State private var replacement = ""
    @State private var changed = 0

    private var current: SpellCheck.Word? { words.indices.contains(index) ? words[index] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Check Spelling").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(max(0, words.count - index)) left · \(changed) changed").foregroundStyle(Theme.textDim) }
            if let w = current {
                Text("Not in dictionary:").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                HStack {
                    Text(w.word).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                    Text("#\(w.entity) · \(w.field)").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button("Zoom To") { model.editor.selection = [w.entity]; model.zoomToSelection() }.buttonStyle(FlatButtonStyle(compact: true))
                }
                HStack { Text("Change to"); TextField("", text: $replacement).darkField() }
                let sugg = SpellCheck.suggester?(w.word) ?? []
                if !sugg.isEmpty {
                    ScrollView(.horizontal) {
                        HStack { ForEach(sugg.prefix(8), id: \.self) { s in Button(s) { replacement = s }.buttonStyle(FlatButtonStyle(compact: true)) } }
                    }
                }
                HStack {
                    Button("Change") { change(all: false) }.buttonStyle(FlatButtonStyle(prominent: true)).disabled(replacement.isEmpty || replacement == w.word)
                    Button("Change All") { change(all: true) }.buttonStyle(FlatButtonStyle()).disabled(replacement.isEmpty || replacement == w.word)
                    Button("Ignore") { next() }.buttonStyle(FlatButtonStyle())
                    Button("Ignore All") { ignored.insert(w.word.lowercased()); next() }.buttonStyle(FlatButtonStyle())
                    Button("Add to Dictionary") { add(w.word) }.buttonStyle(FlatButtonStyle())
                }
            } else {
                Text(words.isEmpty ? "No spelling errors found." : "Spelling check complete.").foregroundStyle(Theme.text)
            }
            HStack { Spacer(); Button("Done") { model.sheet = nil }.buttonStyle(FlatButtonStyle(prominent: current == nil)).keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 520)
        .font(Theme.font)
        .background(Theme.panel)
        .onAppear { scan() }
    }

    private func scan() {
        if SpellCheck.checker == nil { AppCommandsExtra.installSpellChecker() }
        let ids: Set<EntityID>? = model.editor.selection.isEmpty ? nil : model.editor.selection
        words = SpellCheck.checker.map { SpellCheck.misspelled(model.doc, ids: ids, isCorrect: $0) } ?? []
        index = 0
        skipIgnored()
    }
    private func skipIgnored() {
        while let w = current, ignored.contains(w.word.lowercased()) || SpellCheck.customWords(model.doc).contains(w.word.lowercased()) { index += 1 }
        replacement = current.flatMap { SpellCheck.suggester?($0.word).first } ?? ""
    }
    private func next() { index += 1; skipIgnored() }
    private func change(all: Bool) {
        guard let w = current else { return }
        let targets = all ? words[index...].filter { $0.word == w.word }.map(\.entity) : [w.entity]
        let r = replacement
        var n = 0
        model.editor.transaction("Spelling") { d in for id in Set(targets) { if SpellCheck.replace(w.word, with: r, in: id, doc: &d) { n += 1 } } }
        changed += n
        if all { ignored.insert(w.word.lowercased()) }
        next()
    }
    private func add(_ word: String) {
        model.editor.transaction("Add to Dictionary") { SpellCheck.addWord(word, &$0) }
        next()
    }
}
