// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import ArchiCore

enum PlotColorMode: String, Codable, CaseIterable, Identifiable {
    case color = "Color", monochrome = "Monochrome", grayscale = "Grayscale"
    var id: String { rawValue }
}

/// Plot settings of a sheet (or of model space), stored in the document variables as JSON (PAGESETUP).
struct PageSetup: Codable, Hashable {
    var colorMode: PlotColorMode = .color
    /// Multiplier on plotted lineweights.
    var lineweightScale: Double = 1
    /// File name, sheet and date printed along the bottom edge.
    var plotStamp = false
    /// Model-space plots: paper name and fixed scale ratio (nil = largest standard scale that fits).
    var modelPaper = "A3"
    var modelPortrait = false
    var modelScale: Double?
    /// Colour-dependent plot style table name (PLOTSTYLE); nil = none.
    var plotStyleTable: String?
    /// Plot stamp text with fields {project} {number} {sheet} {date} {time} {user} {file} {style}; nil = default.
    var stampText: String?
    /// Model-space plot area (SHT-028): drawing extents, the displayed view, the drawing limits or a window.
    var plotArea: PlotArea = .extents
    /// Display / window rectangle in model units: [minX, minY, maxX, maxY].
    var plotWindow: [Double]?
    /// Fit to paper at the exact ratio (not rounded to a standard scale) (SHT-029).
    var exactFit = false
    /// Named plot style table (STB); when set it is used instead of the colour-dependent table (SHT-031).
    var namedStyleTable: String?

    enum PlotArea: String, Codable, CaseIterable, Identifiable { case extents = "Extents", display = "Display", limits = "Limits", window = "Window"; var id: String { rawValue } }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorMode = try c.decodeIfPresent(PlotColorMode.self, forKey: .colorMode) ?? .color
        lineweightScale = try c.decodeIfPresent(Double.self, forKey: .lineweightScale) ?? 1
        plotStamp = try c.decodeIfPresent(Bool.self, forKey: .plotStamp) ?? false
        modelPaper = try c.decodeIfPresent(String.self, forKey: .modelPaper) ?? "A3"
        modelPortrait = try c.decodeIfPresent(Bool.self, forKey: .modelPortrait) ?? false
        modelScale = try c.decodeIfPresent(Double.self, forKey: .modelScale)
        plotStyleTable = try c.decodeIfPresent(String.self, forKey: .plotStyleTable)
        stampText = try c.decodeIfPresent(String.self, forKey: .stampText)
        plotArea = try c.decodeIfPresent(PlotArea.self, forKey: .plotArea) ?? .extents
        plotWindow = try c.decodeIfPresent([Double].self, forKey: .plotWindow)
        exactFit = try c.decodeIfPresent(Bool.self, forKey: .exactFit) ?? false
        namedStyleTable = try c.decodeIfPresent(String.self, forKey: .namedStyleTable)
    }

    var windowBox: BBox2? {
        guard let w = plotWindow, w.count == 4 else { return nil }
        let b = BBox2(points: [Vec2(w[0], w[1]), Vec2(w[2], w[3])])
        return b.width > 0 && b.height > 0 ? b : nil
    }
    mutating func setWindow(_ b: BBox2?) { plotWindow = b.map { [$0.min.x, $0.min.y, $0.max.x, $0.max.y] } }

    static let modelKey = "PAGESETUP:*MODEL*"
    static func key(_ doc: ArchiDocument, layoutIndex: Int?) -> String {
        guard let i = layoutIndex, doc.layouts.indices.contains(i) else { return modelKey }
        return "PAGESETUP:" + doc.layouts[i].name.uppercased()
    }
    static func load(_ doc: ArchiDocument, layoutIndex: Int?) -> PageSetup {
        guard let s = doc.variables[key(doc, layoutIndex: layoutIndex)], let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode(PageSetup.self, from: d) else { return PageSetup() }
        return v
    }
    func store(in doc: inout ArchiDocument, layoutIndex: Int?) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let k = PageSetup.key(doc, layoutIndex: layoutIndex)
        if self == PageSetup() { doc.variables[k] = nil; return }
        if let d = try? enc.encode(self), let s = String(data: d, encoding: .utf8) { doc.variables[k] = s }
    }

    var modelPaperSize: PaperSize {
        let p = PaperCatalog.find(modelPaper) ?? PaperSize.standard[1]
        return modelPortrait ? PaperSize(name: p.name + " portrait", width: p.height, height: p.width) : p
    }
}

enum PlotStamp {
    static let defaultTemplate = "{project}  ·  {sheet}  ·  plotted {date} {time}  ·  Oanarina Archi Tool"
    static let fields = ["{project}", "{number}", "{sheet}", "{date}", "{time}", "{user}", "{file}", "{style}"]

    /// Stamp text from a template with fields.
    static func text(doc: ArchiDocument, name: String, template: String? = nil, file: String? = nil, style: String? = nil, date: Date = Date()) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        var t = (template?.isEmpty == false ? template! : defaultTemplate)
        let values: [String: String] = [
            "{project}": doc.info.name, "{number}": doc.info.number, "{sheet}": name, "{date}": df.string(from: date), "{time}": tf.string(from: date),
            "{user}": doc.info.author.isEmpty ? NSFullUserName() : doc.info.author, "{file}": file ?? "", "{style}": style ?? "",
        ]
        for (k, v) in values { t = t.replacingOccurrences(of: k, with: v) }
        return t
    }
    static func entry(doc: ArchiDocument, name: String, paperWidth: Double, setup: PageSetup? = nil) -> DrawEntry {
        let style = setup.map { $0.plotStyleTable ?? $0.colorMode.rawValue }
        let content = text(doc: doc, name: name, template: setup?.stampText, file: nil, style: style)
        return DrawEntry(id: nil, items: [.text(TextGeom(position: Vec2(SheetComposer.bindingMargin + 1, 4), height: 1.8, content: content), font: "Helvetica", color: .black)])
    }
}

/// Viewport locks (VPLOCK), stored per sheet as "VPLOCK:<SHEET>" = "0,2".
enum ViewportLock {
    static func key(_ layoutName: String) -> String { "VPLOCK:" + layoutName.uppercased() }
    static func locked(_ doc: ArchiDocument, layoutIndex: Int) -> Set<Int> {
        guard doc.layouts.indices.contains(layoutIndex), let s = doc.variables[key(doc.layouts[layoutIndex].name)] else { return [] }
        return Set(s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }
    static func isLocked(_ doc: ArchiDocument, layoutIndex: Int, viewport: Int) -> Bool { locked(doc, layoutIndex: layoutIndex).contains(viewport) }
    static func set(_ doc: inout ArchiDocument, layoutIndex: Int, viewport: Int, locked on: Bool) {
        guard doc.layouts.indices.contains(layoutIndex) else { return }
        var l = locked(doc, layoutIndex: layoutIndex)
        if on { l.insert(viewport) } else { l.remove(viewport) }
        l = l.filter { doc.layouts[layoutIndex].viewports.indices.contains($0) }
        doc.variables[key(doc.layouts[layoutIndex].name)] = l.isEmpty ? nil : l.sorted().map(String.init).joined(separator: ",")
    }
    /// Keeps lock indices valid after a viewport is removed.
    static func removed(_ doc: inout ArchiDocument, layoutIndex: Int, viewport: Int) {
        guard doc.layouts.indices.contains(layoutIndex) else { return }
        let l = locked(doc, layoutIndex: layoutIndex).compactMap { $0 == viewport ? nil : ($0 > viewport ? $0 - 1 : $0) }
        doc.variables[key(doc.layouts[layoutIndex].name)] = l.isEmpty ? nil : l.sorted().map(String.init).joined(separator: ",")
    }
}

extension Plotter {
    /// All (or the given) sheets in one multi-page vector PDF, each page at its own paper size (PUBLISH).
    /// `progress(done, total)` is called before each page; returning false cancels (the partial file is removed).
    @MainActor static func writeSheetsPDF(doc: ArchiDocument, to url: URL, layouts: [Int]? = nil, progress: ((Int, Int) -> Bool)? = nil) throws {
        // Placeholder sheets are listed but never plotted (SHT-020).
        let list = (layouts ?? SheetTools.publishable(doc)).filter { doc.layouts.indices.contains($0) && !SheetTools.isPlaceholder(doc.layouts[$0]) }
        guard !list.isEmpty else { throw ExportError(errorDescription: "The document has no sheets. Create one in the Sheet view first.") }
        guard let ctx = CGContext(url as CFURL, mediaBox: nil, pdfInfo(doc, title: "\(doc.info.name) — \(list.count) sheet(s)")) else { throw PlotError.cannotCreate(url.path) }
        for (k, li) in list.enumerated() {
            if let progress, !progress(k, list.count) {
                ctx.closePDF()
                try? FileManager.default.removeItem(at: url)
                throw ExportError(errorDescription: "Publishing cancelled.")
            }
            let layout = doc.layouts[li]
            var box = CGRect(x: 0, y: 0, width: layout.paper.width * pointsPerMM, height: layout.paper.height * pointsPerMM)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            ctx.setFillColor(.white); ctx.fill(box)
            SheetComposer.draw(doc: doc, layoutIndex: li, in: ctx, paperToDevice: CGAffineTransform(scaleX: pointsPerMM, y: pointsPerMM),
                               devicePerMM: pointsPerMM, showViewportBorders: false, setup: PageSetup.load(doc, layoutIndex: li))
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Publishes every sheet to one PDF; asks for the file when no path is given.
    @MainActor static func publish(model: AppModel, path: String?) {
        let doc = model.doc
        let url: URL
        if let p = path, !p.isEmpty { url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "\(model.displayName) — sheets.pdf"
            if let dir = FileLocations.exportFolder ?? model.editor.fileURL?.deletingLastPathComponent() { panel.directoryURL = dir }
            guard panel.runModal() == .OK, let u = panel.url else { return }
            url = u
        }
        do {
            let list = SheetTools.publishable(doc)
            // Progress in the status bar with Cancel (APP-044); events are pumped between pages.
            let job = ProgressCenter.shared.begin("Publishing \(list.count) sheet(s)")
            defer { ProgressCenter.shared.end(job) }
            try publishPDF(doc: doc, layouts: list, to: url, bookmarks: true) { k, n in
                ProgressCenter.shared.update(job, fraction: Double(k) / Double(max(n, 1)), detail: "sheet \(k + 1) of \(n)")
                ProgressCenter.pumpEvents()
                return !ProgressCenter.shared.isCancelled(job)
            }
            model.editor.print("Published \(list.count) sheet(s) to \(url.path)" + (list.count < doc.layouts.count ? " (\(doc.layouts.count - list.count) placeholder sheet(s) skipped)" : ""))
        } catch { model.files.showError(error) }
    }
}

// MARK: - Plot dialog with live preview (PLOT / PREVIEW)

@MainActor
enum PlotPreviewWindow {
    private static var windows: [ObjectIdentifier: NSWindow] = [:]
    static func show(model: AppModel) {
        let key = ObjectIdentifier(model)
        if let w = windows[key] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Plot Preview — \(model.displayName)"
        w.isReleasedWhenClosed = false
        w.appearance = Theme.appearance
        w.backgroundColor = Theme.nsPanel
        let host = NSHostingController(rootView: PlotPreviewView(model: model, onClose: { windows[key]?.close(); windows[key] = nil }))
        host.sizingOptions = []
        w.contentViewController = host
        w.setContentSize(NSSize(width: 1080, height: 720))
        w.minSize = NSSize(width: 760, height: 500)
        w.center()
        w.makeKeyAndOrderFront(nil)
        windows[key] = w
    }
}

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument?
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = NSColor(white: 0.16, alpha: 1)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document; v.autoScales = true }
    }
}

struct PlotPreviewView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void
    enum What: Hashable { case model, sheet(Int), allSheets }
    @State private var what: What = .model
    @State private var setup = PageSetup()
    @State private var pdf: PDFDocument?
    @State private var pdfURL: URL?
    @State private var error = ""
    @State private var scaleText = "Fit"

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PLOT").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                Picker("What", selection: $what) {
                    Text("Model — \(model.doc.level(model.doc.currentLevel)?.name ?? "current level")").tag(What.model)
                    ForEach(Array(model.doc.layouts.enumerated()), id: \.offset) { i, l in Text("Sheet — \(l.name)").tag(What.sheet(i)) }
                    if model.doc.layouts.count > 1 { Text("All sheets (\(model.doc.layouts.count) pages)").tag(What.allSheets) }
                }
                PageSetupForm(setup: $setup, showModel: what == .model, scaleText: $scaleText, tables: PlotStyleTable.all(model.doc).map(\.name))
                if what != .model {
                    Text("Sheets plot at 1:1 on their own paper; change paper and viewports in the Sheet view.")
                        .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Save as Default") { saveSetup() }.buttonStyle(FlatButtonStyle(compact: true))
                        .disabled(what == .allSheets)
                        .help("Store these settings in the drawing's page setup")
                }
                Spacer()
                if !error.isEmpty { Text(error).font(Theme.fontSmall).foregroundStyle(Theme.danger) }
                Text(pdf.map { "\($0.pageCount) page(s)" } ?? "").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                HStack {
                    Button("Close", action: onClose).buttonStyle(FlatButtonStyle())
                    Spacer()
                    Button("Save PDF…") { savePDF() }.buttonStyle(FlatButtonStyle()).disabled(pdf == nil)
                    Button("Print…") { print() }.buttonStyle(FlatButtonStyle(prominent: true)).disabled(pdf == nil)
                }
            }
            .padding(14)
            .frame(width: 300)
            .frame(maxHeight: .infinity)
            .background(Theme.panel)
            VSeparator()
            PDFPreview(document: pdf)
        }
        .font(Theme.font)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(Theme.colorScheme)
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            what = model.mode == .sheet && model.doc.layouts.indices.contains(model.activeLayout) ? .sheet(model.activeLayout) : .model
            loadSetup()
            regenerate()
        }
        .onChange(of: what) { _ in loadSetup(); regenerate() }
        .onChange(of: setup) { _ in regenerate() }
    }

    private var layoutIndex: Int? { if case .sheet(let i) = what { return i }; return nil }

    private func loadSetup() {
        setup = PageSetup.load(model.doc, layoutIndex: what == .allSheets ? nil : layoutIndex)
        scaleText = setup.modelScale.map { "1:\(fmt($0, 0))" } ?? "Fit"
    }

    private func saveSetup() {
        let s = setup, li = layoutIndex
        model.editor.transaction("Page Setup") { s.store(in: &$0, layoutIndex: li) }
    }

    /// Writes the plot to a temporary PDF; printing and saving use exactly this file (the preview is the output).
    private func regenerate() {
        var doc = model.doc
        if what == .allSheets {
            // Each sheet keeps its own stored page setup.
        } else {
            setup.store(in: &doc, layoutIndex: layoutIndex)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiPlot-\(UUID().uuidString).pdf")
        do {
            switch what {
            case .model: try Plotter.writePDF(doc: doc, to: url, layoutIndex: nil, level: doc.currentLevel)
            case .sheet(let i): try Plotter.writePDF(doc: doc, to: url, layoutIndex: i, level: nil)
            case .allSheets: try Plotter.writeSheetsPDF(doc: doc, to: url)
            }
            if let old = pdfURL { try? FileManager.default.removeItem(at: old) }
            pdfURL = url
            pdf = PDFDocument(url: url)
            error = ""
        } catch let e { error = e.localizedDescription }
    }

    private func savePDF() {
        guard let src = pdfURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let name: String
        switch what {
        case .model: name = model.displayName
        case .sheet(let i): name = model.doc.layouts[i].name
        case .allSheets: name = "\(model.displayName) — sheets"
        }
        panel.nameFieldStringValue = name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: src, to: url)
            model.editor.print("Plotted to \(url.path)")
        } catch let e { error = e.localizedDescription }
    }

    private func print() {
        guard let pdf else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        if let page = pdf.page(at: 0) {
            let r = page.bounds(for: .mediaBox)
            info.orientation = r.width > r.height ? .landscape : .portrait
        }
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        guard let op = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
        op.jobTitle = model.doc.info.name
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

/// Plot style, lineweights, stamp and (for model space) paper and scale.
struct PageSetupForm: View {
    @Binding var setup: PageSetup
    var showModel: Bool
    @Binding var scaleText: String
    /// Plot style tables available in the document.
    var tables: [String] = []
    /// The 2D view shown in the window (for the Display plot area).
    var displayBox: BBox2? = nil
    /// Named plot style tables (STB) of the document.
    var namedTables: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Plot style", selection: $setup.colorMode) {
                ForEach(PlotColorMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if !tables.isEmpty {
                Picker("Plot style table", selection: Binding(get: { setup.plotStyleTable ?? "" }, set: { setup.plotStyleTable = $0.isEmpty ? nil : $0 })) {
                    Text("None").tag("")
                    ForEach(tables, id: \.self) { Text($0).tag($0) }
                }
            }
            if !namedTables.isEmpty {
                Picker("Named plot styles", selection: Binding(get: { setup.namedStyleTable ?? "" }, set: { setup.namedStyleTable = $0.isEmpty ? nil : $0 })) {
                    Text("None (colour-dependent)").tag("")
                    ForEach(namedTables, id: \.self) { Text($0).tag($0) }
                }
            }
            HStack {
                Text("Lineweights")
                Slider(value: $setup.lineweightScale, in: 0.25...3, step: 0.25)
                Text("×\(fmt(setup.lineweightScale, 2))").font(Theme.mono).frame(width: 44, alignment: .trailing)
            }
            Toggle("Plot stamp", isOn: $setup.plotStamp)
            if setup.plotStamp {
                TextField(PlotStamp.defaultTemplate, text: Binding(get: { setup.stampText ?? "" }, set: { setup.stampText = $0.isEmpty ? nil : $0 }))
                    .darkField()
                Text("Fields: " + PlotStamp.fields.joined(separator: " ")).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }
            if showModel {
                Divider()
                Picker("Paper", selection: $setup.modelPaper) {
                    ForEach(PaperCatalog.builtIn, id: \.name) { p in Text("\(p.name) (\(fmt(p.width, 0))×\(fmt(p.height, 0)))").tag(p.name) }
                }
                Picker("Orientation", selection: $setup.modelPortrait) {
                    Text("Landscape").tag(false)
                    Text("Portrait").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Plot area", selection: $setup.plotArea) { ForEach(PageSetup.PlotArea.allCases) { Text($0.rawValue).tag($0) } }
                    .onChange(of: setup.plotArea) { a in if (a == .display || (a == .window && setup.windowBox == nil)), let d = displayBox { setup.setWindow(d) } }
                if setup.plotArea == .window { Text("Window: PLOTAREA Window picks the corners in the drawing.").font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
                Toggle("Exact fit (not rounded to a standard scale)", isOn: $setup.exactFit).disabled(scaleText != "Fit")
                Picker("Scale", selection: $scaleText) {
                    Text("Fit to paper").tag("Fit")
                    ForEach([1.0, 5, 10, 20, 25, 50, 75, 100, 200, 250, 500, 1000], id: \.self) { r in Text("1:\(fmt(r, 0))").tag("1:\(fmt(r, 0))") }
                }
                .onChange(of: scaleText) { t in
                    setup.modelScale = t == "Fit" ? nil : Double(t.dropFirst(2))
                }
            }
        }
    }
}

/// PAGESETUP: page setup of a sheet (paper, orientation) or of model space.
struct PageSetupSheet: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var setup = PageSetup()
    @State private var paper = "A3"
    @State private var portrait = false
    @State private var scaleText = "Fit"
    @State private var sectionOverride = false
    @State private var sectionStyle = SectionSheetStyle()
    @State private var loadedPaper: PaperSize?
    @State private var loadedPreset: NamedPageSetup?

    private var isSheet: Bool { model.doc.layouts.indices.contains(layoutIndex) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isSheet ? "Page Setup — \(model.doc.layouts[layoutIndex].name)" : "Page Setup — Model").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(14)
            HSeparator()
            ScrollView {
              VStack(alignment: .leading, spacing: 10) {
                if isSheet {
                    NamedPageSetupControls(model: model, layoutIndex: layoutIndex, draft: draftDocument, load: loadPreset)
                    Divider()
                    Picker("Paper", selection: $paper) {
                        ForEach(sheetPapers, id: \.name) { p in Text("\(p.name) (\(fmt(p.width, 0))×\(fmt(p.height, 0)) mm)").tag(p.name) }
                    }
                    Picker("Orientation", selection: $portrait) {
                        Text("Landscape").tag(false)
                        Text("Portrait").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if model.doc.layouts[layoutIndex].viewports.contains(where: { $0.view == .section }) {
                        Toggle("Customize section graphics on this sheet", isOn: $sectionOverride)
                        if sectionOverride {
                            Toggle("Shaded surfaces", isOn: $sectionStyle.shaded)
                            ColorPicker("Section line colour", selection: sectionColor(fill: false), supportsOpacity: false)
                            ColorPicker("Cut fill colour", selection: sectionColor(fill: true), supportsOpacity: false)
                            HStack {
                                Text("Cut weight (mm)")
                                TextField("0.5", value: Binding(get: { sectionStyle.lines.cutLineweight ?? 0.5 }, set: { sectionStyle.lines.cutLineweight = min(5, max(0.01, $0)) }), format: .number).frame(width: 60)
                                Text("Projection (mm)")
                                TextField("0.25", value: Binding(get: { sectionStyle.lines.projectionLineweight ?? 0.25 }, set: { sectionStyle.lines.projectionLineweight = min(5, max(0.01, $0)) }), format: .number).frame(width: 60)
                            }
                            Text("Applies to section viewports on this sheet. Choose Color below to print the selected colours; Preview shows the final output.")
                                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider()
                }
                PageSetupForm(setup: $setup, showModel: !isSheet, scaleText: $scaleText, tables: PlotStyleTable.all(model.doc).map(\.name), displayBox: model.canvas?.visibleWorldBox, namedTables: NamedPlotStyles.tables(model.doc))
              }
              .padding(14)
            }
            .frame(width: 450)
            .frame(maxHeight: 580)
            HSeparator()
            HStack {
                Button("Preview…") { apply(); model.sheet = nil; PlotPreviewWindow.show(model: model) }.buttonStyle(FlatButtonStyle())
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("OK") { apply(); model.sheet = nil }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .font(Theme.font)
        .background(Theme.panel)
        .onAppear {
            setup = PageSetup.load(model.doc, layoutIndex: isSheet ? layoutIndex : nil)
            scaleText = setup.modelScale.map { "1:\(fmt($0, 0))" } ?? "Fit"
            if isSheet {
                let p = model.doc.layouts[layoutIndex].paper
                portrait = p.height > p.width
                paper = PaperCatalog.all(model.doc).first { $0.name == p.name }?.name ?? PaperCatalog.builtIn.first { p.name.hasPrefix($0.name) }?.name ?? p.name
                loadedPaper = p
                if let style = SectionSheetStyle.load(model.doc.layouts[layoutIndex]) {
                    sectionOverride = true; sectionStyle = style
                } else {
                    sectionStyle = SectionSheetStyle(lines: ObjectStyle(projectionLineweight: 0.25, cutLineweight: 0.5, color: .black, cutFill: RGBA(0.62, 0.62, 0.62)))
                }
            }
        }
    }

    private var sheetPapers: [PaperSize] {
        var papers = PaperCatalog.all(model.doc)
        if let p = loadedPaper, !papers.contains(where: { $0.name == p.name }) { papers.append(p) }
        return papers
    }

    private func draftDocument() -> ArchiDocument {
        var d = model.doc
        writeDraft(to: &d)
        return d
    }

    private func apply() {
        model.editor.transaction("Page Setup") { writeDraft(to: &$0) }
    }

    private func loadPreset(_ preset: NamedPageSetup) {
        if let value = try? JSONDecoder().decode(PageSetup.self, from: Data(preset.settings.utf8)) { setup = value }
        loadedPreset = preset
        loadedPaper = preset.paper
        paper = preset.paper.name
        portrait = preset.paper.height > preset.paper.width
        sectionOverride = preset.sectionStyle != nil
        if let style = preset.sectionStyle { sectionStyle = style }
    }

    private func writeDraft(to d: inout ArchiDocument) {
        var s = setup
        let li = isSheet ? layoutIndex : nil, isSheet = self.isSheet
        if let preset = loadedPreset, let i = li {
            try? NamedPageSetups.apply(preset, to: [i], doc: &d)
            let resolved = PageSetup.load(d, layoutIndex: i)
            let original = try? JSONDecoder().decode(PageSetup.self, from: Data(preset.settings.utf8))
            if s.plotStyleTable == original?.plotStyleTable { s.plotStyleTable = resolved.plotStyleTable }
            if s.namedStyleTable == original?.namedStyleTable { s.namedStyleTable = resolved.namedStyleTable }
        }
        let base = PaperCatalog.find(paper, doc: model.doc) ?? loadedPaper ?? PaperSize.standard[1]
        let p: PaperSize
        if let loadedPaper, loadedPaper.name == paper, (loadedPaper.height > loadedPaper.width) == portrait { p = loadedPaper }
        else {
            let name = base.name.replacingOccurrences(of: " portrait", with: "")
            p = portrait ? PaperSize(name: name + " portrait", width: min(base.width, base.height), height: max(base.width, base.height)) : PaperSize(name: name, width: max(base.width, base.height), height: min(base.width, base.height))
        }
        s.store(in: &d, layoutIndex: li)
        if isSheet, let i = li, d.layouts[i].paper != p { d.layouts[i].paper = p }
        if let i = li {
            if sectionOverride { sectionStyle.store(in: &d.layouts[i]) }
            else { d.layouts[i].titleBlock[SectionSheetStyle.key] = nil }
        }
    }

    private func sectionColor(fill: Bool) -> Binding<Color> {
        Binding(get: {
            let c = (fill ? sectionStyle.lines.cutFill : sectionStyle.lines.color) ?? .black
            return Color(red: c.r, green: c.g, blue: c.b)
        }, set: { value in
            guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
            let rgba = RGBA(c.redComponent, c.greenComponent, c.blueComponent)
            if fill { sectionStyle.lines.cutFill = rgba } else { sectionStyle.lines.color = rgba }
        })
    }
}

// MARK: - Title block editor (TITLEBLOCK)

struct TitleBlockSheet: View {
    @ObservedObject var model: AppModel
    let layoutIndex: Int
    @State private var fields: [String: String] = [:]
    @State private var info = ProjectInfo()
    @State private var applyToAll: Set<String> = []
    /// Custom fields (SHT-021): label → project value / this sheet's override.
    @State private var projectCustom: [String: String] = [:]
    @State private var sheetCustom: [String: String] = [:]
    @State private var newLabel = ""
    @State private var logo = ""

    static let sheetKeys: [(String, String)] = [("sheetName", "Sheet title"), ("sheetNumber", "Sheet number"), ("scale", "Scale"), ("date", "Date"), ("revision", "Revision")]
    static let projectOverrideKeys: [(String, String)] = [("project", "Project"), ("client", "Client"), ("author", "Drawn by"), ("number", "Project no.")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Title Block — \(model.doc.layouts.indices.contains(layoutIndex) ? model.doc.layouts[layoutIndex].name : "")").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(14)
            HSeparator()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PROJECT (ALL SHEETS)").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                    field("Project name", $info.name)
                    field("Project no.", $info.number)
                    field("Client", $info.client)
                    field("Address", $info.address)
                    field("Drawn by", $info.author)
                    Text("Every title block shows these unless a sheet overrides them.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("Logo").frame(width: 84, alignment: .leading).foregroundStyle(Theme.textDim)
                        Text(logo.isEmpty ? "None" : (logo as NSString).lastPathComponent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") {
                            let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                            if p.runModal() == .OK, let u = p.url { logo = u.path }
                        }.buttonStyle(FlatButtonStyle(compact: true))
                        if !logo.isEmpty { Button("Remove") { logo = "" }.buttonStyle(FlatButtonStyle(compact: true)) }
                    }
                    Text("CUSTOM FIELDS").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim).padding(.top, 6)
                    ForEach(Array(Set(projectCustom.keys).union(sheetCustom.keys)).sorted(), id: \.self) { k in
                        field(k.capitalized, Binding(get: { projectCustom[k] ?? "" }, set: { projectCustom[k] = $0 }), placeholder: "project value")
                        field("  this sheet", Binding(get: { sheetCustom[k] ?? "" }, set: { sheetCustom[k] = $0 }), placeholder: "same as project")
                    }
                    HStack(spacing: 6) {
                        TextField("New field label", text: $newLabel).darkField()
                        Button("Add") { let l = newLabel.trimmingCharacters(in: .whitespaces).uppercased(); if !l.isEmpty { projectCustom[l] = projectCustom[l] ?? ""; newLabel = "" } }
                            .buttonStyle(FlatButtonStyle())
                    }
                }
                .frame(width: 250)
                VStack(alignment: .leading, spacing: 7) {
                    Text("THIS SHEET").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.textDim)
                    ForEach(TitleBlockSheet.sheetKeys + TitleBlockSheet.projectOverrideKeys, id: \.0) { k, label in
                        HStack(spacing: 6) {
                            field(label, Binding(get: { fields[k] ?? "" }, set: { fields[k] = $0 }), placeholder: defaultValue(k))
                            if ["revision", "date", "scale"].contains(k) {
                                Toggle("All", isOn: Binding(get: { applyToAll.contains(k) }, set: { if $0 { applyToAll.insert(k) } else { applyToAll.remove(k) } }))
                                    .toggleStyle(.checkbox).help("Apply this value to every sheet")
                            }
                        }
                    }
                    Text("Leave a field empty to use the automatic value shown in grey.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .frame(width: 300)
            }
            .padding(14)
            HSeparator()
            HStack {
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.cancelAction)
                Button("OK") { apply(); model.sheet = nil }.buttonStyle(FlatButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .font(Theme.font)
        .background(Theme.panel)
        .onAppear {
            info = model.doc.info
            projectCustom = Dictionary(SheetTools.projectFields(model.doc), uniquingKeysWith: { a, _ in a })
            logo = model.doc.variable("TITLEBLOCKLOGO") ?? ""
            if model.doc.layouts.indices.contains(layoutIndex) {
                for (k, v) in model.doc.layouts[layoutIndex].titleBlock where k.hasPrefix(SheetTools.sheetPrefix) { sheetCustom[String(k.dropFirst(SheetTools.sheetPrefix.count))] = v }
            }
            if model.doc.layouts.indices.contains(layoutIndex) {
                // Only the lower-case keys are read by the title block.
                fields = model.doc.layouts[layoutIndex].titleBlock.filter { k, _ in (TitleBlockSheet.sheetKeys + TitleBlockSheet.projectOverrideKeys).contains { $0.0 == k } }
            }
        }
    }

    private func defaultValue(_ k: String) -> String {
        let d = model.doc
        guard d.layouts.indices.contains(layoutIndex) else { return "" }
        let l = d.layouts[layoutIndex]
        switch k {
        case "sheetName": return l.name
        case "sheetNumber": return String(format: "A-%03d", layoutIndex + 101)
        case "scale":
            let s = Array(Set(l.viewports.map { SheetComposer.ratioText($0.scale, units: d.units) })).sorted()
            return s.isEmpty ? "—" : (s.count == 1 ? s[0] : "As indicated")
        case "date": return SheetComposer.dateText()
        case "revision": return "—"
        case "project": return info.name
        case "client": return info.client
        case "author": return info.author
        case "number": return info.number
        default: return ""
        }
    }

    private func field(_ label: String, _ b: Binding<String>, placeholder: String = "") -> some View {
        HStack(spacing: 6) {
            Text(label).frame(width: 84, alignment: .leading).foregroundStyle(Theme.textDim)
            TextField(placeholder, text: b).darkField()
        }
    }

    private func apply() {
        let li = layoutIndex, newInfo = info, f = fields, all = applyToAll, pc = projectCustom, sc = sheetCustom, lg = logo
        model.editor.transaction("Title Block") { d in
            d.info = newInfo
            d.variables["TITLEBLOCKLOGO"] = lg.isEmpty ? nil : lg
            for (k, _) in SheetTools.projectFields(d) where pc[k] == nil { SheetTools.setProjectField(&d, k, nil) }
            for (k, v) in pc { SheetTools.setProjectField(&d, k, v.trimmingCharacters(in: .whitespaces)) }
            for (k, v) in sc { SheetTools.setSheetField(&d, li, k, v.trimmingCharacters(in: .whitespaces)) }
            guard d.layouts.indices.contains(li) else { return }
            var tb = d.layouts[li].titleBlock
            for (k, _) in TitleBlockSheet.sheetKeys + TitleBlockSheet.projectOverrideKeys {
                let v = (f[k] ?? "").trimmingCharacters(in: .whitespaces)
                tb[k] = v.isEmpty ? nil : v
            }
            d.layouts[li].titleBlock = tb
            for k in all {
                let v = (f[k] ?? "").trimmingCharacters(in: .whitespaces)
                for j in d.layouts.indices where j != li { d.layouts[j].titleBlock[k] = v.isEmpty ? nil : v }
            }
        }
    }
}
