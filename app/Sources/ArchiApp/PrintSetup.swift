// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import PDFKit
import ArchiCore

/// Parsing of PostScript Printer Description (PPD) option lists: paper sizes, input trays (InputSlot), media types.
enum PPDOptions {
    struct Choice: Hashable { var key: String; var label: String }
    /// Choices of an option (`*InputSlot Tray1/Tray 1: "…"`) and its default (`*DefaultInputSlot: Tray1`).
    static func parse(_ ppd: String, option: String) -> (choices: [Choice], defaultKey: String?) {
        var out: [Choice] = [], def: String?
        for raw in ppd.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("*Default\(option):") {
                def = line.dropFirst("*Default\(option):".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("*\(option) ") else { continue }
            let rest = line.dropFirst(option.count + 2)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            let spec = rest[..<colon].trimmingCharacters(in: .whitespaces)
            let parts = spec.split(separator: "/", maxSplits: 1).map(String.init)
            guard let key = parts.first, !key.isEmpty, !out.contains(where: { $0.key == key }) else { continue }
            out.append(Choice(key: key, label: parts.count > 1 ? parts[1] : key))
        }
        return (out, def)
    }
}

/// Installed printers with their PPD (for trays and paper sizes).
enum PrinterCatalog {
    struct Printer: Hashable { var id: String; var name: String; var ppd: URL? }

    static func printers() -> [Printer] {
        var listRef: Unmanaged<CFArray>?
        guard PMServerCreatePrinterList(nil, &listRef) == noErr, let list = listRef?.takeRetainedValue() else { return [] }
        var out: [Printer] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let p = unsafeBitCast(raw, to: PMPrinter.self)
            let id = str(PMPrinterGetID(p)) ?? ""
            let name = str(PMPrinterGetName(p)) ?? id
            var urlRef: Unmanaged<CFURL>?
            var ppd: URL?
            if PMPrinterCopyDescriptionURL(p, "PPD" as CFString, &urlRef) == noErr, let u = urlRef?.takeRetainedValue() { ppd = u as URL }
            out.append(Printer(id: id, name: name, ppd: ppd))
        }
        return out
    }

    // The PrintCore getters are imported as Unmanaged or managed CFString depending on the SDK's annotations.
    private static func str(_ v: Unmanaged<CFString>?) -> String? { v?.takeUnretainedValue() as String? }
    private static func str(_ v: CFString?) -> String? { v as String? }

    static func ppdText(_ p: Printer) -> String {
        guard let u = p.ppd, let d = try? Data(contentsOf: u) else { return "" }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
    }
}

/// Print options beyond the system dialog: printer, paper, tray, scaling and copies (remembered between prints).
struct PrintOptions: Codable, Equatable {
    enum Scaling: String, Codable, CaseIterable { case fit = "Fit to Paper", actual = "Actual Size (1:1 paper)", custom = "Custom %" }
    var printer = ""
    var paper = ""
    var tray = ""
    var mediaType = ""
    var scaling: Scaling = .fit
    var percent = 100.0
    var copies = 1
    var showSystemDialog = false
    /// Large format (SHT-038): nil/"printer" = the printer's paper; "drawing" = a custom page the size of the sheet;
    /// "roll" = roll paper of `rollWidth` mm, cut to the drawing's length. Optional so saved options still decode.
    var sizeMode: String?
    var rollWidth: Double?

    enum SizeMode: String, CaseIterable { case printer = "Printer paper", drawing = "Match drawing (custom size)", roll = "Roll paper" }
    var size: SizeMode { SizeMode.allCases.first { $0.rawValue == sizeMode || "\($0)" == sizeMode } ?? .printer }

    /// Page for a PDF page of `pdf` points: custom sizes and rolls (width across the roll, length along it) and the
    /// scale that fits (1 = true size). Nil keeps the printer's paper.
    static func page(for pdf: CGSize, mode: SizeMode, rollWidthMM: Double) -> (size: CGSize, scale: CGFloat, rotated: Bool)? {
        let pt = 72 / 25.4
        switch mode {
        case .printer: return nil
        case .drawing: return (pdf, 1, false)
        case .roll:
            let roll = CGFloat(max(100, rollWidthMM) * pt)
            let long = max(pdf.width, pdf.height), short = min(pdf.width, pdf.height)
            // Least paper: the long side across the roll when it fits, else the short side, else scaled down.
            if long <= roll + 0.5 { return (CGSize(width: roll, height: short), 1, pdf.height > pdf.width) }
            if short <= roll + 0.5 { return (CGSize(width: roll, height: long), 1, pdf.width > pdf.height) }
            let k = roll / short
            return (CGSize(width: roll, height: long * k), k, pdf.width > pdf.height)
        }
    }

    static let key = "print.options"
    static func load() -> PrintOptions {
        guard let d = UserDefaults.standard.data(forKey: key), let o = try? JSONDecoder().decode(PrintOptions.self, from: d) else { return PrintOptions() }
        return o
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }

    /// NSPrintInfo scaling factor and PDFKit scaling mode for the options.
    var scale: (factor: CGFloat, mode: PDFPrintScalingMode) {
        switch scaling {
        case .fit: return (1, .pageScaleToFit)
        case .actual: return (1, .pageScaleNone)
        case .custom: return (CGFloat(max(1, min(1000, percent)) / 100), .pageScaleNone)
        }
    }
}

enum PrintSetupWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        let v = PrintSetupView(model: model)
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Print", key: "ArchiPrintSetup", size: NSSize(width: 420, height: 420), content: v)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Prints the drawing or the active sheet with the options (no system dialog unless asked).
    @MainActor static func print(model: AppModel, options o: PrintOptions) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiPrint-\(UUID().uuidString).pdf")
        let layout: Int? = model.mode == .sheet && model.doc.layouts.indices.contains(model.activeLayout) ? model.activeLayout : nil
        do {
            try Plotter.exportPDF(model: model, to: url, layoutIndex: layout)
            guard let pdf = PDFDocument(url: url) else { return }
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            if !o.printer.isEmpty, let p = NSPrinter(name: o.printer) { info.printer = p }
            if !o.paper.isEmpty { info.paperName = NSPrinter.PaperName(o.paper) }
            if let page = pdf.page(at: 0) { let r = page.bounds(for: .mediaBox); info.orientation = r.width > r.height ? .landscape : .portrait }
            var s = o.scale
            // Large format: a custom page (CUPS Custom.WxH) the size of the sheet, or roll paper cut to length.
            if let page = pdf.page(at: 0), let lf = PrintOptions.page(for: page.bounds(for: .mediaBox).size, mode: o.size, rollWidthMM: o.rollWidth ?? 914) {
                info.orientation = .portrait
                info.paperSize = NSSize(width: lf.rotated ? lf.size.height : lf.size.width, height: lf.rotated ? lf.size.width : lf.size.height)
                if lf.rotated { info.orientation = .landscape }
                info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
                s = (lf.scale, lf.scale < 1 ? .pageScaleToFit : .pageScaleNone)
            }
            info.scalingFactor = s.factor
            info.isHorizontallyCentered = true; info.isVerticallyCentered = true
            info.dictionary()[NSPrintInfo.AttributeKey.copies.rawValue] = max(1, o.copies)
            let settings = OpaquePointer(info.pmPrintSettings())
            if !o.tray.isEmpty { PMPrintSettingsSetValue(settings, "InputSlot" as CFString, o.tray as CFString, false) }
            if !o.mediaType.isEmpty { PMPrintSettingsSetValue(settings, "MediaType" as CFString, o.mediaType as CFString, false) }
            info.updateFromPMPrintSettings()
            guard let op = pdf.printOperation(for: info, scalingMode: s.mode, autoRotate: o.scaling == .fit) else { return }
            op.jobTitle = model.doc.info.name
            op.showsPrintPanel = o.showSystemDialog
            op.showsProgressPanel = true
            if let w = model.window { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
            model.editor.print("Sent \(model.doc.info.name) to \(o.printer.isEmpty ? "the default printer" : o.printer)\(o.tray.isEmpty ? "" : ", tray \(o.tray)"), \(o.scaling == .custom ? "\(fmt(o.percent, 0))%" : o.scaling.rawValue), \(o.copies) cop\(o.copies == 1 ? "y" : "ies").")
        } catch { model.editor.print("Print failed: \(error.localizedDescription)") }
    }
}

struct PrintSetupView: View {
    @ObservedObject var model: AppModel
    @State private var o = PrintOptions.load()
    @State private var printers: [PrinterCatalog.Printer] = []
    @State private var papers: [PPDOptions.Choice] = []
    @State private var trays: [PPDOptions.Choice] = []
    @State private var media: [PPDOptions.Choice] = []

    var body: some View {
        Form {
            Picker("Printer", selection: $o.printer) {
                Text("Default").tag("")
                ForEach(printers, id: \.self) { Text($0.name).tag($0.name) }
            }
            Picker("Paper", selection: $o.paper) {
                Text("Printer default").tag("")
                ForEach(papers, id: \.self) { Text($0.label).tag($0.key) }
            }
            Picker("Tray", selection: $o.tray) {
                Text("Auto select").tag("")
                ForEach(trays, id: \.self) { Text($0.label).tag($0.key) }
            }.disabled(trays.isEmpty)
            if !media.isEmpty {
                Picker("Media", selection: $o.mediaType) { Text("Printer default").tag(""); ForEach(media, id: \.self) { Text($0.label).tag($0.key) } }
            }
            Picker("Paper size", selection: Binding(get: { o.size }, set: { o.sizeMode = $0.rawValue })) { ForEach(PrintOptions.SizeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if o.size == .roll {
                HStack {
                    Text("Roll width")
                    TextField("mm", value: Binding(get: { o.rollWidth ?? 914 }, set: { o.rollWidth = max(100, $0) }), format: .number).frame(width: 70)
                    Text("mm").foregroundStyle(Theme.textDim)
                    Spacer()
                    Menu("Common") { ForEach([610.0, 841, 914, 1067, 1118, 1524], id: \.self) { w in Button("\(fmt(w, 0)) mm") { o.rollWidth = w } } }.fixedSize()
                }
            }
            if o.size == .printer {
                Picker("Scale", selection: $o.scaling) { ForEach(PrintOptions.Scaling.allCases, id: \.self) { Text($0.rawValue) } }
            }
            if o.scaling == .custom && o.size == .printer {
                HStack { Slider(value: $o.percent, in: 10...400, step: 5); Text("\(fmt(o.percent, 0)) %").font(Theme.mono).frame(width: 56) }
            }
            Stepper("Copies: \(o.copies)", value: $o.copies, in: 1...99)
            Toggle("Show the system print dialog", isOn: $o.showSystemDialog)
            Text(model.mode == .sheet ? "Prints the active sheet." : "Prints the drawing (current level). Sheets print at their plot scale with Actual Size.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            HStack {
                Spacer()
                Button("Print") { o.save(); PrintSetupWindow.print(model: model, options: o) }.buttonStyle(FlatButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .frame(minWidth: 380, minHeight: 360)
        .onAppear { printers = PrinterCatalog.printers(); loadOptions() }
        .onChange(of: o.printer) { _, _ in o.tray = ""; o.paper = ""; o.mediaType = ""; loadOptions() }
    }

    private func loadOptions() {
        let p = printers.first { $0.name == o.printer } ?? printers.first { NSPrinter(name: $0.name)?.name == NSPrintInfo.defaultPrinter?.name }
        let text = p.map(PrinterCatalog.ppdText) ?? ""
        papers = PPDOptions.parse(text, option: "PageSize").choices
        trays = PPDOptions.parse(text, option: "InputSlot").choices
        media = PPDOptions.parse(text, option: "MediaType").choices
        if !papers.contains(where: { $0.key == o.paper }) { o.paper = "" }
        if !trays.contains(where: { $0.key == o.tray }) { o.tray = "" }
    }
}
