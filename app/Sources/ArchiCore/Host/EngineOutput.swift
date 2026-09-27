// Oanarina Archi Tool — GPL-3.0-or-later
// Output methods of archi-engine for the Windows shell: the Plot / Preview dialog (plot.preview writes the PDF that is
// printed or saved, exactly as the Mac PlotPreviewView does, and returns the same pages as SVG for the preview and for
// Windows printing), PDF and layered PDF output, publishing sheet sets, plot style tables, the plot log, camera paths
// and sun frames for walkthrough / sun-study videos, and the web viewer export. docs/ENGINE-PROTOCOL.md "Output".
import Foundation

public enum EngineOutputMethods {
    /// Protocol methods answered by `EngineSession.callOutput` (listed in engine.hello "methods").
    public static let all: [String] = [
        "plot.info", "plot.preview", "plot.pdf", "plot.publish", "plot.sheetSVG",
        "plotstyle.list", "plotstyle.save", "plotstyle.named", "plotlog.get", "plotlog.clear",
        "camerapath.list", "camerapath.set", "camerapath.frames", "render.sunFrames", "render.window", "render.queueName",
        "webviewer.export", "pathtrace.start", "pathtrace.status", "pathtrace.stop", "pathtrace.save", "pathtrace.mix",
        "render.pass", "plot.shadePlotImage",
    ]
}

/// State of the output session (temporary preview PDFs, the running path tracer).
final class EngineOutputState {
    var previewPDF: URL?
    var previewSVGs: [URL] = []
    var previewCount = 0
    var tracer: EnginePathTraceJob?
}

extension EngineSession {
    private static var outputStates: [ObjectIdentifier: EngineOutputState] = [:]
    var output: EngineOutputState {
        let k = ObjectIdentifier(self)
        if let s = EngineSession.outputStates[k] { return s }
        let s = EngineOutputState()
        EngineSession.outputStates[k] = s
        return s
    }

    /// Runs one of `EngineOutputMethods.all` (nil for other methods).
    func callOutput(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "plot.info": return plotInfo()
        case "plot.preview": return try plotPreview(p)
        case "plot.pdf": return try plotPDF(p)
        case "plot.publish": return try plotPublish(p)
        case "plot.sheetSVG": return try plotSheetSVG(p)
        case "plotstyle.list": return plotStyleList()
        case "plotstyle.save": return try plotStyleSave(p)
        case "plotstyle.named": return plotStyleNamed()
        case "plotlog.get": return plotLogGet(p)
        case "plotlog.clear": EnginePlotLog.clear(); editor.print("Plot log cleared."); return .object([])
        case "camerapath.list": return cameraPathList()
        case "camerapath.set": return try cameraPathSet(p)
        case "camerapath.frames": return try cameraPathFrames(p)
        case "render.sunFrames": return try renderSunFrames(p)
        case "render.window": return renderWindowInfo(p)
        case "render.queueName": return renderQueueName(p)
        case "webviewer.export": return try webViewerExport(p)
        case "pathtrace.start": return try pathTraceStart(p)
        case "pathtrace.status": return try pathTraceStatus(p)
        case "pathtrace.stop": return pathTraceStop()
        case "pathtrace.save": return try pathTraceSave(p)
        case "pathtrace.mix": return try pathTraceMix(p)
        case "render.pass": return try renderPass(p)
        case "plot.shadePlotImage": return try shadePlotImage(p)
        default: return nil
        }
    }

    // MARK: Plot

    /// The sheet the shell shows (CTAB), nil in model space.
    var activeSheetIndex: Int? {
        let doc = editor.doc
        guard let c = doc.variable("CTAB"), c.caseInsensitiveCompare("Model") != .orderedSame else { return nil }
        return doc.layouts.firstIndex { $0.name.caseInsensitiveCompare(c) == .orderedSame }
    }

    /// What the Plot dialog offers: model (current level), each sheet, all sheets; the default choice.
    func plotInfo() -> EngineJSON {
        let doc = editor.doc
        var items: [EngineJSON] = []
        let levelName = doc.level(doc.currentLevel)?.name ?? "current level"
        items.append(.object([EngineJSONField("value", .string("model")), EngineJSONField("title", .string("Model — " + levelName))]))
        for (i, l) in doc.layouts.enumerated() {
            items.append(.object([EngineJSONField("value", .string("sheet:" + String(i))), EngineJSONField("title", .string("Sheet — " + l.name))]))
        }
        if doc.layouts.count > 1 {
            items.append(.object([EngineJSONField("value", .string("all")), EngineJSONField("title", .string("All sheets (" + String(doc.layouts.count) + " pages)"))]))
        }
        var sheets: [EngineJSON] = []
        for (i, l) in doc.layouts.enumerated() {
            let s = EnginePageSetup.load(doc, layoutIndex: i)
            var o = EngineObject()
            o.set("index", i)
            o.set("name", l.name)
            o.set("number", EngineSheets.number(doc, i))
            o.set("paper", l.paper.name)
            o.set("style", EnginePlot.styleText(s))
            o.set("placeholder", EnginePlot.isPlaceholder(l))
            o.set("bookmark", EnginePlot.bookmarkTitle(doc, i))
            sheets.append(o.json)
        }
        var o = EngineObject()
        o.set("what", EngineJSON.array(items))
        o.set("default", activeSheetIndex.map { "sheet:" + String($0) } ?? "model")
        o.set("sheets", EngineJSON.array(sheets))
        o.set("title", "Plot Preview — " + doc.info.name)
        o.set("documentName", doc.info.name)
        o.set("sheetNote", "Sheets plot at 1:1 on their own paper; change paper and viewports in the Sheet view.")
        o.set("suggestedModel", doc.info.name + ".pdf")
        o.set("suggestedAll", doc.info.name + " — sheets.pdf")
        return o.json
    }

    /// "model", "sheet:<i>" (or a `layout` param), "all".
    func plotTarget(_ p: EngineJSON) throws -> (kind: String, layout: Int?) {
        if let l = p["layout"], !l.isNull { return ("sheet", try layoutIndex(l)) }
        let w = p["what"]?.stringValue ?? (activeSheetIndex.map { "sheet:" + String($0) } ?? "model")
        if w == "model" { return ("model", nil) }
        if w == "all" { return ("all", nil) }
        if w.hasPrefix("sheet:"), let i = Int(w.dropFirst(6)), editor.doc.layouts.indices.contains(i) { return ("sheet", i) }
        if w == "sheet", let i = activeSheetIndex ?? (editor.doc.layouts.isEmpty ? nil : 0) { return ("sheet", i) }
        throw EngineError.params("unknown plot target '" + w + "' (model, sheet:<n>, all)")
    }

    /// A page setup from the dialog (`setup`, `scaleText`) over the stored one.
    func plotSetup(_ p: EngineJSON, layout: Int?) throws -> EnginePageSetup {
        var s = EnginePageSetup.load(editor.doc, layoutIndex: layout)
        if let v = p["setup"], !v.isNull { try s.apply(v) }
        if let t = p["scaleText"]?.stringValue { s.modelScale = t == "Fit" ? nil : Double(t.dropFirst(2)) }
        return s
    }

    /// Plotted pages of a target with the dialog's setup (all sheets keep their own setups; placeholders skipped).
    func plotPages(_ p: EngineJSON, layered: Bool = false) throws -> (pages: [EnginePlotPage], ratio: Double?, title: String) {
        let doc = editor.doc
        let t = try plotTarget(p)
        switch t.kind {
        case "model":
            let lv: Int? = p["level"].flatMap { $0.isNull ? nil : $0.intValue } ?? doc.currentLevel
            let m = EnginePlot.modelPage(doc: doc, level: lv, setup: try plotSetup(p, layout: nil), layered: layered)
            return ([m.page], m.ratio, doc.info.name)
        case "sheet":
            let li = t.layout ?? 0
            guard let page = EnginePlot.sheetPage(doc: doc, layoutIndex: li, setup: try plotSetup(p, layout: li)) else { throw EngineError.failed("No sheet " + String(li)) }
            return ([page], nil, doc.layouts[li].name)
        default:
            let list = EnginePlot.publishable(doc)
            guard !list.isEmpty else { throw EngineError.failed("The document has no sheets. Create one in the Sheet view first.") }
            let pages = list.compactMap { EnginePlot.sheetPage(doc: doc, layoutIndex: $0) }
            return (pages, nil, doc.info.name + " — " + String(pages.count) + " sheet(s)")
        }
    }

    /// Plot dialog preview: writes the temporary PDF that Print and Save PDF use and returns the pages as SVG.
    func plotPreview(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let (pages, ratio, title) = try plotPages(p)
        let out = EnginePDF.document(pages, doc: doc, title: title, layered: false, outline: pages.count > 1)
        let st = output
        st.previewCount += 1
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiPlot-" + String(ProcessInfo.processInfo.processIdentifier) + "-" + String(st.previewCount) + ".pdf")
        try out.data.write(to: url)
        if let old = st.previewPDF { try? FileManager.default.removeItem(at: old) }
        st.previewPDF = url
        var list: [EngineJSON] = []
        let wantSVG = p["svg"]?.boolValue ?? true
        // The shell of the Windows app reads large pages from files (svgFiles) instead of the JSON line.
        let files = p["svgFiles"]?.boolValue ?? false
        for old in st.previewSVGs { try? FileManager.default.removeItem(at: old) }
        st.previewSVGs = []
        for (k, page) in pages.enumerated() {
            let r = EnginePDF.resolve(page, doc: doc, layered: false)
            var o = EngineObject()
            o.set("name", page.name)
            o.set("width", page.widthMM)
            o.set("height", page.heightMM)
            if files {
                let f = url.deletingPathExtension().appendingPathExtension("p" + String(k + 1) + ".svg")
                try EnginePlotSVG.svg(r).write(to: f, atomically: true, encoding: .utf8)
                st.previewSVGs.append(f)
                o.set("svgPath", f.path)
            } else if wantSVG { o.set("svg", EnginePlotSVG.svg(r)) }
            list.append(o.json)
        }
        var o = EngineObject()
        o.set("pdf", url.path)
        o.set("bytes", out.data.count)
        o.set("pageCount", pages.count)
        o.set("pages", EngineJSON.array(list))
        o.set("title", title)
        o.set("ratio", ratio.map { EngineJSON.number($0) } ?? .null)
        o.set("status", String(pages.count) + " page(s)")
        return o.json
    }

    /// Writes a plot to a PDF file (Save PDF…, PLOT <file>, EXPORTPDF): plain or layered; logged in the plot log.
    func plotPDF(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let path = try string(p, "path")
        let dest = url(path)
        // Save PDF… of the preview copies the previewed file (the preview is the output).
        if p["fromPreview"]?.boolValue == true, let src = output.previewPDF, FileManager.default.fileExists(atPath: src.path) {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: src, to: dest)
            editor.print("Plotted to " + dest.path)
            let t = try plotTarget(p)
            logPlot(kind: t.kind, layout: t.layout, file: dest.path, layered: false, setup: try plotSetup(p, layout: t.layout))
            return .object([EngineJSONField("path", .string(dest.path)), EngineJSONField("bytes", .int((try? Data(contentsOf: dest).count) ?? 0))])
        }
        let layered = p["layered"]?.boolValue ?? false
        let (pages, ratio, title) = try plotPages(p, layered: layered)
        let out = EnginePDF.document(pages, doc: doc, title: title, layered: layered, outline: pages.count > 1)
        do { try out.data.write(to: dest) } catch { throw EngineError.failed("Cannot create PDF at " + dest.path + ".") }
        let t = try plotTarget(p)
        logPlot(kind: t.kind, layout: t.layout, file: dest.path, layered: layered, setup: try plotSetup(p, layout: t.layout), ratio: ratio)
        var o = EngineObject()
        o.set("path", dest.path)
        o.set("bytes", out.data.count)
        o.set("pages", out.pages)
        o.set("layers", EngineJSON.strings(out.layers))
        o.set("links", out.links)
        o.set("ratio", ratio.map { EngineJSON.number($0) } ?? .null)
        if p["quiet"]?.boolValue != true {
            if layered {
                let note = ratio.map { " at 1:" + fmt($0, 0) } ?? ""
                editor.print(String(out.pages) + " page(s)" + note + ", " + String(out.layers.count) + " PDF layer(s), " + String(out.links) + " link(s): " + dest.path)
            } else { editor.print("Plotted to " + dest.path) }
        }
        return o.json
    }

    func logPlot(kind: String, layout: Int?, file: String, layered: Bool, setup: EnginePageSetup, ratio: Double? = nil) {
        let doc = editor.doc
        switch kind {
        case "model":
            let paper = EnginePlot.modelPaper(setup)
            let levelName = doc.level(doc.currentLevel)?.name ?? "All levels"
            let r = ratio.map { ", 1:" + fmt($0, 0) } ?? ""
            let what = layered ? "Layered PDF" + (ratio.map { " at 1:" + fmt($0, 0) } ?? "") : "PDF (model, " + paper.name + r + ")"
            EnginePlotLog.record(drawing: doc.info.name, output: what, sheets: levelName, style: layered ? "OCG" : EnginePlot.styleText(setup), file: file)
        case "sheet":
            let li = layout ?? 0
            EnginePlotLog.record(drawing: doc.info.name, output: layered ? "Layered PDF" : "PDF (sheet)", sheets: EngineSheets.number(doc, li),
                                 style: layered ? "OCG" : EnginePlot.styleText(setup), file: file)
        default:
            let list = EnginePlot.publishable(doc)
            EnginePlotLog.record(drawing: doc.info.name, output: layered ? "Layered PDF" : "Publish", sheets: list.map { EngineSheets.number(doc, $0) }.joined(separator: " "),
                                 style: layered ? "OCG" : "sheet setups", file: file)
        }
    }

    /// PUBLISH / BATCHPUBLISH: chosen sheets (default all publishable) in one PDF with bookmarks; optional sheet index.
    func plotPublish(_ p: EngineJSON) throws -> EngineJSON {
        let path = try string(p, "path")
        let dest = url(path)
        let bookmarks = p["bookmarks"]?.boolValue ?? true
        if p["index"]?.boolValue == true {
            editor.transaction("Sheet Index") { _ = EngineSheets.placeIndex(&$0, on: 0) }
        }
        let doc = editor.doc
        var chosen = EnginePlot.publishable(doc)
        if let a = p["layouts"]?.arrayValue {
            var l: [Int] = []
            for v in a { l.append(try layoutIndex(v)) }
            chosen = l.sorted()
        }
        let list = chosen.filter { doc.layouts.indices.contains($0) && !EnginePlot.isPlaceholder(doc.layouts[$0]) }
        guard !list.isEmpty else { throw EngineError.failed("The document has no sheets. Create one in the Sheet view first.") }
        let pages = list.compactMap { EnginePlot.sheetPage(doc: doc, layoutIndex: $0) }
        let title = doc.info.name + " — " + String(pages.count) + " sheet(s)"
        let out = EnginePDF.document(pages, doc: doc, title: title, layered: false, outline: bookmarks)
        do { try out.data.write(to: dest) } catch { throw EngineError.failed("Cannot create PDF at " + dest.path + ".") }
        var styles = Set<String>()
        for i in list { styles.insert(EnginePlot.styleText(EnginePageSetup.load(doc, layoutIndex: i))) }
        EnginePlotLog.record(drawing: doc.info.name, output: bookmarks ? "Publish (bookmarks)" : "Publish", sheets: list.map { EngineSheets.number(doc, $0) }.joined(separator: " "),
                             style: styles.sorted().joined(separator: " "), file: dest.path)
        let skipped = chosen.count - list.count
        if p["quiet"]?.boolValue != true {
            if p["layouts"] == nil {
                let extra = doc.layouts.count > list.count ? " (" + String(doc.layouts.count - list.count) + " placeholder sheet(s) skipped)" : ""
                editor.print("Published " + String(list.count) + " sheet(s) to " + dest.path + extra)
            } else {
                editor.print("Published " + String(list.count) + " sheet(s)" + (bookmarks ? " with bookmarks" : "") + " to " + dest.path)
            }
        }
        var o = EngineObject()
        o.set("path", dest.path)
        o.set("pages", out.pages)
        o.set("bytes", out.data.count)
        o.set("skipped", skipped)
        o.set("bookmarks", EngineJSON.strings(bookmarks ? pages.map { $0.bookmark ?? $0.name } : []))
        return o.json
    }

    /// SHEETSVG: true-size SVG of sheets with one group per drawing layer.
    func plotSheetSVG(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        guard !doc.layouts.isEmpty else { throw EngineError.failed("The drawing has no sheets.") }
        var list: [Int] = []
        if p["all"]?.boolValue == true { list = EnginePlot.publishable(doc) }
        else { list = [try p["layout"].map { try layoutIndex($0) } ?? (activeSheetIndex ?? 0)] }
        let path = try string(p, "path")
        var base = url(path)
        var isDir: ObjCBool = false
        let single = list.count == 1 && base.pathExtension.lowercased() == "svg"
        if !single && !(FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir) && isDir.boolValue) { base = base.deletingLastPathComponent() }
        var files: [String] = []
        for li in list {
            guard let page = EnginePlot.sheetPage(doc: doc, layoutIndex: li) else { continue }
            let r = EnginePDF.resolve(page, doc: doc, layered: true)
            let name = doc.layouts[li].name.replacingOccurrences(of: "/", with: "-")
            let u = single ? base : base.appendingPathComponent(EngineSheets.number(doc, li) + " " + name + ".svg")
            do { try EnginePlotSVG.svg(r).write(to: u, atomically: true, encoding: .utf8) } catch { throw EngineError.failed("Cannot write " + u.path + ".") }
            editor.print("Wrote " + u.path)
            files.append(u.path)
        }
        return .object([EngineJSONField("files", EngineJSON.strings(files))])
    }

    /// PLOT <file> (and the host action without a dialog): the active sheet or the current level's model space.
    func plotToFile(_ path: String) throws {
        var p = EngineObject()
        p.set("path", path)
        p.set("quiet", true)
        if let li = activeSheetIndex { p.set("layout", li) } else { p.set("what", "model") }
        _ = try plotPDF(p.json)
        editor.print("Plotted to " + url(path).path)
    }

    // MARK: Plot style tables

    static func penJSON(_ pen: EnginePen?) -> EngineJSON {
        guard let pen else { return .null }
        var o = EngineObject()
        o.set("color", pen.color.map { EngineJSON.string(EngineOutputFormat.hex24($0)) } ?? .null)
        o.set("lineweight", pen.lineweight.map { EngineJSON.number($0) } ?? .null)
        o.set("screening", pen.screening)
        return o.json
    }
    static func pen(from j: EngineJSON) -> EnginePen {
        var p = EnginePen()
        if let c = j["color"]?.stringValue, let v = EngineOutputFormat.parseHex24(c) { p.color = v }
        if let w = j["lineweight"]?.doubleValue, w >= 0 { p.lineweight = w }
        if let s = j["screening"]?.doubleValue { p.screening = min(max(s.rounded(), 0), 100) }
        return p
    }

    /// Plot style tables with their pens (object colour swatches for the editor's rows), the current sheet's table.
    func plotStyleList() -> EngineJSON {
        let doc = editor.doc
        var tables: [EngineJSON] = []
        for t in EnginePlotStyleTable.all(doc) {
            var pens: [EngineJSONField] = []
            for k in t.pens.keys.sorted() { pens.append(EngineJSONField(String(k), EngineSession.penJSON(t.pens[k]))) }
            var o = EngineObject()
            o.set("name", t.name)
            o.set("pens", EngineJSON.object(pens))
            o.set("count", t.pens.count)
            o.set("builtIn", EnginePlotStyleTable.builtIn.contains { $0.name == t.name } && doc.variables[EnginePlotStyleTable.variablePrefix + t.name.uppercased()] == nil)
            tables.append(o.json)
        }
        var aci: [EngineJSON] = []
        for i in 0...255 { aci.append(.string(i == 0 ? "" : EngineOutputFormat.hex(aciColor(i)))) }
        let li = activeSheetIndex
        let cur = EnginePageSetup.load(doc, layoutIndex: li).plotStyleTable
        var o = EngineObject()
        o.set("tables", EngineJSON.array(tables))
        o.set("current", EnginePlotStyleTable.named(cur, in: doc)?.name ?? "archi pens.ctb")
        o.set("aci", EngineJSON.array(aci))
        o.set("lineweights", EngineJSON.numbers(EngineOutputFormat.standardLineweights))
        o.set("rows", EngineJSON.ints([0] + Array(1...9) + [250, 251, 252, 253, 254, 255]))
        return o.json
    }

    /// Save in Drawing: stores a table (".ctb" added), one "Plot Style Table" undo step.
    func plotStyleSave(_ p: EngineJSON) throws -> EngineJSON {
        guard let tj = p["table"], var name = tj["name"]?.stringValue?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { throw EngineError.params("missing table name") }
        if !name.lowercased().hasSuffix(".ctb") { name += ".ctb" }
        var t = EnginePlotStyleTable(name: name)
        for f in tj["pens"]?.fields ?? [] {
            guard let i = Int(f.key), (0...255).contains(i), !f.value.isNull else { continue }
            t.pens[i] = EngineSession.pen(from: f.value)
        }
        editor.transaction("Plot Style Table") { t.store(in: &$0) }
        editor.print("Plot style table " + t.name + " saved in the drawing. Choose it in Page Setup (or PLOTSTYLE Set).")
        var o = EngineObject()
        o.set("name", t.name)
        o.set("list", plotStyleList())
        return o.json
    }

    /// Named plot style tables (STB) with their styles.
    func plotStyleNamed() -> EngineJSON {
        let doc = editor.doc
        var out: [EngineJSON] = []
        for n in EngineNamedPlotStyles.tables(doc) {
            let t = EngineNamedPlotStyles.table(n, in: doc) ?? [:]
            var styles: [EngineJSONField] = []
            for k in t.keys.sorted() { styles.append(EngineJSONField(k, EngineSession.penJSON(t[k]))) }
            out.append(.object([EngineJSONField("name", .string(n)), EngineJSONField("styles", .object(styles))]))
        }
        return .object([EngineJSONField("tables", .array(out))])
    }

    // MARK: Plot log

    func plotLogGet(_ p: EngineJSON) -> EngineJSON {
        let rows = EnginePlotLog.entries()
        let limit = p["limit"]?.intValue ?? 200
        var out: [EngineJSON] = []
        for r in rows.suffix(limit) { out.append(EngineJSON.strings(r)) }
        var o = EngineObject()
        o.set("path", EnginePlotLog.url.path)
        o.set("columns", EngineJSON.strings(["Date", "Drawing", "Output", "Sheets", "Plot style", "File"]))
        o.set("rows", EngineJSON.array(out))
        return o.json
    }

    // MARK: Camera paths (RenderQueue.swift CameraPathDef, "CAMERAPATHS")

    func cameraPathList() -> EngineJSON {
        let doc = editor.doc
        var list: [EngineJSON] = []
        for path in EngineCameraPaths.load(doc) { list.append(EngineCameraPaths.json(path)) }
        var cams: [EngineJSON] = []
        for v in doc.namedViews { if let c = v.camera { cams.append(EngineOutputFormat.cameraJSON(c, name: v.name)) } }
        var o = EngineObject()
        o.set("paths", EngineJSON.array(list))
        o.set("cameras", EngineJSON.array(cams))
        return o.json
    }

    /// Replaces the camera paths (one undo step with the editor's label, e.g. "Add Camera Key").
    func cameraPathSet(_ p: EngineJSON) throws -> EngineJSON {
        guard let arr = p["paths"]?.arrayValue else { throw EngineError.params("missing 'paths'") }
        var paths: [EngineCameraPath] = []
        for a in arr { paths.append(try EngineCameraPaths.path(from: a)) }
        let label = p["label"]?.stringValue ?? "Camera Paths"
        editor.transaction(label) { EngineCameraPaths.store(paths, in: &$0) }
        return cameraPathList()
    }

    /// Cameras of every video frame: a camera path by name (keys at their times, `fps`), or a smooth path through the
    /// saved cameras (or `cameras`) in equal time per segment over `seconds` (walkthrough).
    func cameraPathFrames(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        var cams: [Camera] = []
        if let n = p["path"]?.stringValue {
            guard let path = EngineCameraPaths.load(doc).first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw EngineError.params("no camera path '" + n + "'") }
            let fps = max(1, p["fps"]?.intValue ?? path.fps)
            let frames = max(2, Int(path.duration * Double(fps)) + 1)
            for i in 0..<frames { if let c = path.sample(at: Double(i) / Double(fps)) { cams.append(c) } }
            return EngineOutputFormat.framesJSON(cams, fps: fps)
        }
        var keys: [Camera] = []
        if let a = p["cameras"]?.arrayValue { keys = a.compactMap { EngineOutputFormat.camera(from: $0) } }
        else { keys = doc.namedViews.compactMap(\.camera) }
        guard keys.count >= 2 else { throw EngineError.failed("A walkthrough needs at least two saved cameras (SAVECAMERA).") }
        let fps = max(1, p["fps"]?.intValue ?? 30)
        let seconds = min(max(p["seconds"]?.doubleValue ?? 10, 0.1), 600)
        let frames = max(2, Int(seconds * Double(fps)))
        for i in 0..<frames { if let c = EngineCameraPaths.sample(keys, t: Double(i) / Double(frames - 1)) { cams.append(c) } }
        var o = EngineOutputFormat.framesJSON(cams, fps: fps)
        if case .object(var f) = o { f.append(EngineJSONField("pathLength", .number(EngineCameraPaths.length(keys)))); o = .object(f) }
        return o
    }

    /// Sun directions of a sun-study time-lapse (RenderEngine.sunStudy): day of year, hours, frames.
    func renderSunFrames(_ p: EngineJSON) throws -> EngineJSON {
        let info = editor.doc.info
        let day = p["day"]?.intValue ?? 172
        let a = p["fromHour"]?.doubleValue ?? 7, b = p["toHour"]?.doubleValue ?? 19
        guard (1...366).contains(day) else { throw EngineError.params("day of year 1–366") }
        guard b > a else { throw EngineError.failed("The end hour must be after the start hour.") }
        let fps = max(1, p["fps"]?.intValue ?? 30)
        let seconds = min(max(p["seconds"]?.doubleValue ?? 10, 0.1), 600)
        let frames = max(2, Int(seconds * Double(fps)))
        let tz = (info.longitude / 15).rounded()
        var out: [EngineJSON] = []
        for i in 0..<frames {
            let hour = a + (b - a) * Double(i) / Double(frames - 1)
            let s = EngineOutputFormat.sun(day: day, hour: hour, latitude: info.latitude, longitude: info.longitude, tz: tz)
            let d = EngineOutputFormat.sunDirection(altitude: s.0, azimuth: s.1, north: info.northAngle)
            var o = EngineObject()
            o.set("hour", hour)
            o.set("altitude", s.0 * 180 / .pi)
            o.set("azimuth", s.1 * 180 / .pi)
            o.set("direction", EngineJSON.point3(d))
            o.set("above", s.0 > 0)
            out.append(o.json)
        }
        var o = EngineObject()
        o.set("fps", fps)
        o.set("frames", EngineJSON.array(out))
        return o.json
    }

    /// Render window data: output presets, site, saved cameras and the sun for a date/hour.
    func renderWindowInfo(_ p: EngineJSON) -> EngineJSON {
        let doc = editor.doc
        let info = doc.info
        var o = EngineObject()
        o.set("presets", EngineRenderOutputPresets.json)
        o.set("resolutions", EngineJSON.strings(["1280×720", "1920×1080", "2560×1440", "3840×2160", "5120×2880", "7680×4320", "1080×1080", "Custom"]))
        o.set("passes", EngineJSON.strings(["Beauty", "Alpha", "Depth", "Normal", "Material ID"]))
        o.set("styles", EngineJSON.strings(["Photographic", "Sketch", "Watercolour"]))
        o.set("backgrounds", EngineJSON.strings(["Sky", "White", "Transparent"]))
        o.set("environments", EngineJSON.strings(["Physical Sky", "Clear Sky", "Overcast", "Sunset", "Studio", "Night", "HDRI File"]))
        o.set("shadowQualities", EngineJSON.strings(["Off", "Low", "Medium", "High", "Ultra"]))
        o.set("looks", EngineJSON.strings(["Daylight", "Golden hour", "Overcast", "Night"]))
        o.set("latitude", info.latitude)
        o.set("longitude", info.longitude)
        o.set("northAngle", info.northAngle)
        o.set("site", "Site " + fmt(info.latitude, 3) + "°, " + fmt(info.longitude, 3) + "°")
        var cams: [EngineJSON] = []
        for v in doc.namedViews { if let c = v.camera { cams.append(EngineOutputFormat.cameraJSON(c, name: v.name)) } }
        o.set("cameras", EngineJSON.array(cams))
        let day = p["day"]?.intValue ?? 172
        let hour = p["hour"]?.doubleValue ?? 15
        let tz = (info.longitude / 15).rounded()
        let s = EngineOutputFormat.sun(day: day, hour: hour, latitude: info.latitude, longitude: info.longitude, tz: tz)
        o.set("sunText", "Sun altitude " + fmt(s.0 * 180 / .pi, 1) + "°, azimuth " + fmt(s.1 * 180 / .pi, 1) + "°")
        o.set("sunDirection", EngineJSON.point3(EngineOutputFormat.sunDirection(altitude: s.0, azimuth: s.1, north: info.northAngle)))
        o.set("sunAltitude", s.0 * 180 / .pi)
        o.set("sunAzimuth", s.1 * 180 / .pi)
        o.set("preset", EngineRenderPresets.current(doc))
        o.set("title", "Render — " + info.name)
        return o.json
    }

    /// File name of a render queue job: safe characters, numbered when it exists in the folder (RenderQueue.fileName).
    func renderQueueName(_ p: EngineJSON) -> EngineJSON {
        let name = p["name"]?.stringValue ?? "Render"
        var existing = Set<String>()
        if let f = p["folder"]?.stringValue {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: url(f).path)) ?? []
            for i in items { existing.insert(i.lowercased()) }
        }
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var base = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Render" }
        var n = base + ".png"
        var k = 2
        while existing.contains(n.lowercased()) { n = base + " " + String(k) + ".png"; k += 1 }
        return .object([EngineJSONField("file", .string(n))])
    }

    /// Stores the shell's render of a "Rendered" shade-plot viewport (SHADEPLOTIMAGE:<sheet>:<n> = image path).
    func shadePlotImage(_ p: EngineJSON) throws -> EngineJSON {
        let li = try layoutIndex(p["layout"] ?? .null)
        guard let i = p["index"]?.intValue, editor.doc.layouts[li].viewports.indices.contains(i) else { throw EngineError.params("no such viewport") }
        let key = "SHADEPLOTIMAGE:" + editor.doc.layouts[li].name.uppercased() + ":" + String(i)
        let path = p["path"]?.stringValue.map { url($0).path }
        editor.transaction("Shade Plot") { d in d.variables[key] = path }
        return .object([EngineJSONField("key", .string(key)), EngineJSONField("path", EngineJSON.optString(path))])
    }

    // MARK: Web viewer

    func webViewerExport(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let s = EngineWebViewer.scene(doc: doc)
        guard s.triangles > 0 else { throw EngineError.failed("The model has no 3D content.") }
        let dest = url(try string(p, "path"))
        do { try EngineWebViewer.html(doc: doc).write(to: dest, atomically: true, encoding: .utf8) } catch { throw EngineError.failed("Cannot write " + dest.path + ".") }
        editor.print("Web viewer: " + String(s.batches.count) + " material(s), " + String(s.triangles) + " triangles → " + dest.path)
        return .object([EngineJSONField("path", .string(dest.path)), EngineJSONField("triangles", .int(s.triangles))])
    }
}

// MARK: - Formatting helpers

enum EngineOutputFormat {
    static let standardLineweights: [Double] = [0, 0.05, 0.09, 0.13, 0.15, 0.18, 0.2, 0.25, 0.3, 0.35, 0.4, 0.5, 0.53, 0.6, 0.7, 0.8, 0.9, 1.0, 1.06, 1.2, 1.4, 1.58, 2.0, 2.11]

    static func hex24(_ v: UInt32) -> String {
        let d = Array("0123456789abcdef")
        var s = "#"
        for shift in stride(from: 20, through: 0, by: -4) { s.append(d[Int((v >> UInt32(shift)) & 15)]) }
        return s
    }
    static func hex(_ c: RGBA) -> String {
        let r = UInt32((max(0, min(1, c.r)) * 255).rounded()), g = UInt32((max(0, min(1, c.g)) * 255).rounded()), b = UInt32((max(0, min(1, c.b)) * 255).rounded())
        return hex24(r << 16 | g << 8 | b)
    }
    static func parseHex24(_ s: String) -> UInt32? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6 else { return nil }
        return UInt32(t, radix: 16)
    }

    static func cameraJSON(_ c: Camera, name: String? = nil) -> EngineJSON {
        var o = EngineObject()
        if let name { o.set("name", name) }
        o.set("eye", EngineJSON.point3(c.eye))
        o.set("target", EngineJSON.point3(c.target))
        o.set("fov", c.fov)
        o.set("orthographic", c.orthographic)
        return o.json
    }
    static func vec3(_ j: EngineJSON?) -> Vec3? {
        guard let a = j?.arrayValue, a.count >= 3, let x = a[0].doubleValue, let y = a[1].doubleValue, let z = a[2].doubleValue else { return nil }
        return Vec3(x, y, z)
    }
    static func camera(from j: EngineJSON) -> Camera? {
        guard let e = vec3(j["eye"]), let t = vec3(j["target"]) else { return nil }
        return Camera(eye: e, target: t, fov: j["fov"]?.doubleValue ?? 50, orthographic: j["orthographic"]?.boolValue ?? false)
    }
    static func framesJSON(_ cams: [Camera], fps: Int) -> EngineJSON {
        var o = EngineObject()
        o.set("fps", fps)
        o.set("frames", EngineJSON.array(cams.map { cameraJSON($0) }))
        o.set("count", cams.count)
        return o.json
    }

    /// Sun altitude and azimuth (radians) at a local solar-study time (SunPosition.compute with SolarCalculator).
    static func sun(day: Int, hour: Double, latitude: Double, longitude: Double, tz: Double) -> (Double, Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? cal.timeZone
        let year = cal.component(.year, from: Date())
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let date = jan1.addingTimeInterval(Double(day - 1) * 86400 + (hour - tz) * 3600)
        let p = SolarCalculator.position(date: date, latitude: latitude, longitude: longitude)
        return (p.altitude * .pi / 180, p.azimuth * .pi / 180)
    }
    /// Unit vector towards the sun in model coordinates (X east, Y project north, Z up).
    static func sunDirection(altitude: Double, azimuth: Double, north: Double) -> Vec3 {
        let d = Vec2(sin(azimuth), cos(azimuth)).rotated(by: rad(north)) * cos(altitude)
        return Vec3(d.x, d.y, sin(altitude))
    }
}

// MARK: - Camera paths

struct EngineCameraKey: Codable, Hashable {
    var name: String
    var time: Double
    var camera: Camera
}

struct EngineCameraPath: Codable, Hashable {
    var name: String
    var keys: [EngineCameraKey] = []
    var fps: Int = 30
    var duration: Double { keys.map(\.time).max() ?? 0 }
    var sorted: [EngineCameraKey] { keys.sorted { $0.time < $1.time } }

    /// Camera at a time: the key cameras at the key times, smooth in between, clamped at both ends.
    func sample(at time: Double) -> Camera? {
        let k = sorted
        guard let first = k.first, let last = k.last else { return nil }
        if k.count == 1 || time <= first.time { return first.camera }
        if time >= last.time { return last.camera }
        var i = 0
        while i + 1 < k.count - 1 && k[i + 1].time <= time { i += 1 }
        let span = max(k[i + 1].time - k[i].time, 1e-9)
        let u = min(max((time - k[i].time) / span, 0), 1)
        return EngineCameraPaths.sample(k.map(\.camera), t: (Double(i) + u) / Double(k.count - 1))
    }
}

enum EngineCameraPaths {
    static let variable = "CAMERAPATHS"
    static func load(_ doc: ArchiDocument) -> [EngineCameraPath] {
        guard let s = doc.variable(variable) else { return [] }
        return (try? JSONDecoder().decode([EngineCameraPath].self, from: Data(s.utf8))) ?? []
    }
    static func store(_ paths: [EngineCameraPath], in doc: inout ArchiDocument) {
        if paths.isEmpty { doc.variables[variable] = nil; return }
        if let d = try? JSONEncoder().encode(paths) { doc.setVariable(variable, String(decoding: d, as: UTF8.self)) }
    }
    static func json(_ p: EngineCameraPath) -> EngineJSON {
        var keys: [EngineJSON] = []
        for k in p.sorted {
            var o = EngineObject()
            o.set("name", k.name)
            o.set("time", k.time)
            o.set("camera", EngineOutputFormat.cameraJSON(k.camera))
            keys.append(o.json)
        }
        var o = EngineObject()
        o.set("name", p.name)
        o.set("fps", p.fps)
        o.set("duration", p.duration)
        o.set("keys", EngineJSON.array(keys))
        return o.json
    }
    static func path(from j: EngineJSON) throws -> EngineCameraPath {
        guard let name = j["name"]?.stringValue, !name.isEmpty else { throw EngineError.params("camera path without a name") }
        var p = EngineCameraPath(name: name)
        p.fps = max(1, min(60, j["fps"]?.intValue ?? 30))
        for k in j["keys"]?.arrayValue ?? [] {
            guard let c = k["camera"].flatMap({ EngineOutputFormat.camera(from: $0) }) else { throw EngineError.params("camera key without a camera") }
            p.keys.append(EngineCameraKey(name: k["name"]?.stringValue ?? "Key", time: max(0, k["time"]?.doubleValue ?? 0), camera: c))
        }
        return p
    }

    static func catmullRom(_ p0: Vec3, _ p1: Vec3, _ p2: Vec3, _ p3: Vec3, _ u: Double) -> Vec3 {
        let u2 = u * u, u3 = u2 * u
        let a = p1 * 2
        let b = (p2 - p0) * u
        let c1 = p0 * 2 - p1 * 5
        let c = (c1 + p2 * 4 - p3) * u2
        let d1 = p1 * 3 - p0
        let d = (d1 - p2 * 3 + p3) * u3
        let s = a + b + c + d
        return s * 0.5
    }
    /// Camera at t ∈ [0, 1] along a smooth path through the key cameras (CameraPath.sample).
    static func sample(_ keys: [Camera], t: Double) -> Camera? {
        guard let first = keys.first else { return nil }
        guard keys.count > 1 else { return first }
        let segs = Double(keys.count - 1)
        let x = min(max(t, 0), 1) * segs
        let i = min(Int(x), keys.count - 2)
        let u = x - Double(i)
        func at(_ k: Int) -> Camera { keys[min(max(k, 0), keys.count - 1)] }
        let eye = catmullRom(at(i - 1).eye, at(i).eye, at(i + 1).eye, at(i + 2).eye, u)
        let target = catmullRom(at(i - 1).target, at(i).target, at(i + 1).target, at(i + 2).target, u)
        let fov = at(i).fov + (at(i + 1).fov - at(i).fov) * u
        return Camera(eye: eye, target: target, fov: fov, orthographic: false)
    }
    static func length(_ keys: [Camera], samples: Int = 200) -> Double {
        guard keys.count > 1 else { return 0 }
        var l = 0.0
        var prev = keys[0].eye
        for s in 1...samples {
            guard let c = sample(keys, t: Double(s) / Double(samples)) else { continue }
            l += (c.eye - prev).length
            prev = c.eye
        }
        return l
    }
}

// MARK: - Render window output presets (RenderController.swift RenderPreset.builtIn)

enum EngineRenderOutputPresets {
    struct Preset {
        var name: String; var width: Int; var height: Int; var antialias: Bool; var exposure: Double; var background: String
        var environment: String? = nil; var environmentIntensity: Double? = nil; var shadowQuality: String? = nil; var shadowSoftness: Double? = nil
        var ambientOcclusion: Double? = nil; var depthOfField: Bool? = nil; var fStop: Double? = nil; var whiteBalance: Double? = nil; var clay: Bool? = nil
    }
    static let builtIn: [Preset] = [
        Preset(name: "Draft (720p, fast)", width: 1280, height: 720, antialias: false, exposure: 0, background: "Sky"),
        Preset(name: "Standard (1080p)", width: 1920, height: 1080, antialias: true, exposure: 0, background: "Sky"),
        Preset(name: "High (1440p)", width: 2560, height: 1440, antialias: true, exposure: 0, background: "Sky"),
        Preset(name: "Print (4K)", width: 3840, height: 2160, antialias: true, exposure: 0, background: "Sky"),
        Preset(name: "Presentation (white)", width: 2560, height: 1440, antialias: true, exposure: 0.3, background: "White"),
        Preset(name: "Square (1080×1080)", width: 1080, height: 1080, antialias: true, exposure: 0, background: "Sky"),
        Preset(name: "Clay Model (studio)", width: 1920, height: 1080, antialias: true, exposure: 0.2, background: "Sky",
               environment: "Studio", environmentIntensity: 1.6, shadowQuality: "High", shadowSoftness: 8, ambientOcclusion: 1.5, clay: true),
        Preset(name: "Golden Hour", width: 1920, height: 1080, antialias: true, exposure: 0.1, background: "Sky",
               environment: "Sunset", environmentIntensity: 1.1, shadowQuality: "Ultra", shadowSoftness: 6, ambientOcclusion: 1.0, whiteBalance: 5200),
        Preset(name: "Overcast Soft", width: 1920, height: 1080, antialias: true, exposure: 0.3, background: "Sky",
               environment: "Overcast", environmentIntensity: 1.8, shadowQuality: "Medium", shadowSoftness: 14, ambientOcclusion: 1.4),
        Preset(name: "Eye Level (depth of field)", width: 1920, height: 1080, antialias: true, exposure: 0, background: "Sky",
               environment: "Clear Sky", shadowQuality: "High", depthOfField: true, fStop: 2.0),
    ]
    static var json: EngineJSON {
        var out: [EngineJSON] = []
        for p in builtIn {
            var o = EngineObject()
            o.set("name", p.name)
            o.set("width", p.width)
            o.set("height", p.height)
            o.set("antialias", p.antialias)
            o.set("exposure", p.exposure)
            o.set("background", p.background)
            if let v = p.environment { o.set("environment", v) }
            if let v = p.environmentIntensity { o.set("environmentIntensity", v) }
            if let v = p.shadowQuality { o.set("shadowQuality", v) }
            if let v = p.shadowSoftness { o.set("shadowSoftness", v) }
            if let v = p.ambientOcclusion { o.set("ambientOcclusion", v) }
            if let v = p.depthOfField { o.set("depthOfField", v) }
            if let v = p.fStop { o.set("fStop", v) }
            if let v = p.whiteBalance { o.set("whiteBalance", v) }
            if let v = p.clay { o.set("clay", v) }
            out.append(o.json)
        }
        return .array(out)
    }
}
