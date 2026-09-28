// Oanarina Archi Tool — GPL-3.0-or-later
// Output of archi-engine for the Windows shell (Host/EnginePlot.swift, EnginePDF.swift, EngineOutput.swift,
// EngineOutputCommands.swift, EnginePathTracer.swift, IO/JPEGDecoder.swift): plot style tables, the Cedar House
// sheet A-102 of tutorial 10 plotted to PDF (plain and layered), publishing with bookmarks, the plot dialog preview,
// the model plot frame, the plot log, camera paths and sun frames for videos, the path tracer and data passes, the
// render commands' host actions, the web viewer and the baseline JPEG decoder.
import XCTest
@testable import ArchiCore

final class EngineOutputTests: XCTestCase {
    static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized }
    static var cedarHouse: URL { repo.appendingPathComponent("assets/demo/Cedar House.archi") }

    func obj(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        var o = EngineObject()
        for (k, v) in pairs { o.set(k, v) }
        return o.json
    }
    func tmp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-output-" + String(ProcessInfo.processInfo.processIdentifier) + "-" + name)
    }

    @MainActor func session() -> (EngineSession, NotificationSink) {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        EngineSession.registerOutputCommands(reg)
        let sink = NotificationSink()
        let s = EngineSession(editor: Editor(registry: reg), emit: { sink.lines.append($0) })
        return (s, sink)
    }
    @MainActor func hostActions(_ s: EngineSession, _ sink: NotificationSink) -> [EngineJSON] {
        s.flushNotifications()
        return sink.lines.compactMap { try? EngineJSON.parse($0) }.filter { $0["method"]?.stringValue == "host" }.compactMap { $0["params"] }
    }
    @MainActor func run(_ s: EngineSession, _ line: String) async throws {
        let st = try await s.call("command.run", obj([("line", .string(line))]))
        if st["active"]?.boolValue == true { _ = try await s.call("input.key", obj([("key", .string("Escape"))])) }
    }

    /// Cedar House with the sheet "A-102 Plans" of tutorial 10 (three viewports and title block fields), shown.
    @MainActor func cedarA102() async throws -> (EngineSession, NotificationSink) {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, sink) = session()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        try await run(s, "LAYOUT New \"A-102 Plans\"")
        try await run(s, "MVIEW 15,40 205,280 1:150 Plan \"Ground Floor\"")
        try await run(s, "LEVEL Set \"Upper Floor\"")
        try await run(s, "MVIEW 215,150 405,280 1:200 Plan \"Upper Floor\"")
        try await run(s, "LEVEL Set \"Ground Floor\"")
        try await run(s, "MVIEW 215,40 405,140 1:200 South \"South Elevation\"")
        try await run(s, "LAYOUT Titleblock Title \"Plans\" Number \"A-102\" ;")
        return (s, sink)
    }

    // MARK: Plot style tables

    func testPlotStyleTables() throws {
        let t = EnginePlotStyleTable.archiPens
        XCTAssertEqual(EnginePlotStyleTable.aciIndex(RGBA(0, 0, 0)), 7)
        XCTAssertEqual(EnginePlotStyleTable.aciIndex(aciColor(1)), 1)
        XCTAssertNil(EnginePlotStyleTable.aciIndex(RGBA(0.123, 0.456, 0.789)))
        let (c, w) = t.resolve(color: aciColor(5), lineweight: 0.25)
        XCTAssertEqual(w, 0.5)
        XCTAssertEqual(c.r, 0, accuracy: 1e-9)
        let (c8, _) = t.resolve(color: aciColor(8), lineweight: 0.25)
        XCTAssertEqual(c8.r, 0.5, accuracy: 1e-9)   // 50 % screening towards white
        // The Mac PlotStyleTable JSON (Int keys as strings) decodes and a stored table is listed after the built-ins.
        let json = #"{"name":"office.ctb","pens":{"1":{"color":16711680,"lineweight":0.35},"0":{"screening":40}}}"#
        let custom = try JSONDecoder().decode(EnginePlotStyleTable.self, from: Data(json.utf8))
        XCTAssertEqual(custom.pens[1]?.color, 0xFF0000)
        XCTAssertEqual(custom.pens[0]?.screening, 40)
        var doc = ArchiDocument()
        custom.store(in: &doc)
        XCTAssertEqual(EnginePlotStyleTable.all(doc).map(\.name), ["monochrome.ctb", "grayscale.ctb", "archi pens.ctb", "office.ctb"])
        XCTAssertEqual(EnginePlotStyleTable.named("OFFICE.CTB", in: doc)?.pens.count, 2)
        // Pen resolution of the renderer: paper rules and plot styles.
        var r = EnginePlotRenderer(transform: .identity, devicePerMM: EnginePlot.pointsPerMM, paper: true, minLineWidth: 0.12)
        XCTAssertEqual(r.color(RGBA(1, 1, 1)), RGBA(0, 0, 0))
        XCTAssertEqual(r.color(RGBA(0.9, 0.9, 0.5)).r, 0.9 * 0.55, accuracy: 1e-9)
        r.colorMode = "Monochrome"
        XCTAssertEqual(r.color(aciColor(1)), RGBA(0, 0, 0))
        r.colorMode = "Color"
        r.lineweightScale = 2
        XCTAssertEqual(r.width(StrokeStyle(color: RGBA(0, 0, 0), lineweight: 0.5)), 0.5 * EnginePlot.pointsPerMM * 2, accuracy: 1e-9)
        XCTAssertEqual(EngineNamedPlotStyles.defaultTable["Heavy"]?.lineweight, 0.7)
    }

    // MARK: Sheet A-102 (tutorial 10)

    @MainActor func testPlotSheetA102ToPDF() async throws {
        let (s, _) = try await cedarA102()
        let doc = s.editor.doc
        let li = try XCTUnwrap(doc.layouts.firstIndex { $0.name == "A-102 Plans" })
        XCTAssertEqual(li, 1)
        XCTAssertEqual(doc.layouts[li].viewports.count, 3)
        XCTAssertEqual(s.activeSheetIndex, li)
        // Composition: frame, title block (sheet number A-102 from the index), north arrow, scale bar, three captions.
        let deco = EnginePlot.decorations(doc: doc, layout: doc.layouts[li], layoutIndex: li)
        let texts = deco.flatMap(\.items).compactMap { item -> String? in if case .text(let t, _, _) = item { return t.content }; return nil }
        XCTAssertTrue(texts.contains("A-102"))
        XCTAssertTrue(texts.contains("OANARINA ARCHI TOOL"))
        XCTAssertTrue(texts.contains("Cedar House"))
        XCTAssertTrue(texts.contains("As indicated"))
        XCTAssertTrue(texts.contains("Ground Floor"))
        XCTAssertTrue(texts.contains("South Elevation"))
        XCTAssertTrue(texts.contains("1:150"))
        XCTAssertTrue(texts.contains("N"))
        XCTAssertTrue(texts.contains { $0.hasPrefix("SCALE 1:150") })
        // PLOT <file> plots the shown sheet like the Mac: one A3 landscape page, viewports clipped, Helvetica text.
        let url = tmp("A-102.pdf")
        // The plot log is one shared file per user; parallel test processes append to it too, so this test logs to its own folder.
        let logDir = tmp("plotlog")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let savedLogFolder = EnginePlotLog.folder
        EnginePlotLog.folder = logDir
        defer { EnginePlotLog.folder = savedLogFolder; try? FileManager.default.removeItem(at: logDir) }
        try await run(s, "PLOT " + url.path)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(8), as: UTF8.self), "%PDF-1.4")
        let head = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(head.contains("/MediaBox [0 0 1190.551 841.89]"))
        XCTAssertTrue(head.contains("/Count 1"))
        XCTAssertTrue(head.contains("/BaseFont /Helvetica"))
        XCTAssertTrue(head.contains("/Filter /FlateDecode"))
        let page = try XCTUnwrap(EnginePlot.sheetPage(doc: doc, layoutIndex: li))
        XCTAssertEqual(page.parts.count, 4)
        XCTAssertEqual(page.parts[0].clip?.count, 4)
        let out = EnginePDF.document([page], doc: doc, title: "A-102", layered: false)
        let body = out.contents[0]
        XCTAssertTrue(body.contains(" re W n") || body.contains(" h W n"))
        XCTAssertTrue(body.contains(EnginePDF.hex("A-102")))
        XCTAssertTrue(body.contains(EnginePDF.hex("South Elevation")))
        XCTAssertGreaterThan(body.components(separatedBy: " S Q").count, 500)
        // The plot log has the sheet.
        let log = try await s.call("plotlog.get", obj([]))
        let lastRow = log["rows"]?.arrayValue?.last?.arrayValue ?? []
        XCTAssertTrue(lastRow.contains(.string(url.path)), "plot log " + String(describing: log["path"]) + ": " + String(describing: log["rows"]))
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor func testLayeredPDFAndPreview() async throws {
        let (s, _) = try await cedarA102()
        let url = tmp("A-102-layered.pdf")
        try await run(s, "EXPORTPDF Current " + url.path)
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("%PDF-1.6"))
        XCTAssertTrue(text.contains("/OCProperties"))
        XCTAssertTrue(text.contains("/Type /OCG"))
        XCTAssertTrue(text.contains(EnginePDF.pdfString("Sheet")))
        try? FileManager.default.removeItem(at: url)
        // The Plot dialog: targets, a preview PDF and the same page as SVG (true size).
        let info = try await s.call("plot.info")
        XCTAssertEqual(info["default"]?.stringValue, "sheet:1")
        XCTAssertEqual(info["what"]?.arrayValue?.count, 4)
        let pv = try await s.call("plot.preview", obj([("what", .string("sheet:1")), ("setup", obj([("colorMode", .string("Monochrome"))]))]))
        XCTAssertEqual(pv["pageCount"]?.intValue, 1)
        let pdf = try XCTUnwrap(pv["pdf"]?.stringValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pdf))
        let svg = try XCTUnwrap(pv["pages"]?[0]?["svg"]?.stringValue)
        XCTAssertTrue(svg.contains("width=\"420mm\" height=\"297mm\""))
        XCTAssertTrue(svg.contains("clipPath"))
        XCTAssertFalse(svg.contains("stroke=\"#ff0000\""))   // monochrome
        // Save PDF… copies the previewed file.
        let saved = tmp("saved.pdf")
        _ = try await s.call("plot.pdf", obj([("what", .string("sheet:1")), ("path", .string(saved.path)), ("fromPreview", .bool(true))]))
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: URL(fileURLWithPath: pdf)))
        try? FileManager.default.removeItem(at: saved)
    }

    @MainActor func testPublishWithBookmarksAndModelPlot() async throws {
        let (s, _) = try await cedarA102()
        let url = tmp("sheets.pdf")
        let r = try await s.call("plot.publish", obj([("path", .string(url.path)), ("bookmarks", .bool(true))]))
        XCTAssertEqual(r["pages"]?.intValue, 2)
        XCTAssertEqual(r["bookmarks"]?.arrayValue?.map { $0.stringValue ?? "" }, ["A-101 — Sheet 1", "A-102 Plans"])
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(text.contains("/Type /Outlines"))
        XCTAssertTrue(text.contains("/Count 2"))
        try? FileManager.default.removeItem(at: url)
        // Placeholder sheets are skipped.
        s.editor.transaction("Placeholder") { $0.layouts[0].titleBlock["placeholder"] = "1" }
        let r2 = try await s.call("plot.publish", obj([("path", .string(url.path)), ("quiet", .bool(true))]))
        XCTAssertEqual(r2["pages"]?.intValue, 1)
        try? FileManager.default.removeItem(at: url)
        // Model space: A3 landscape, frame and title strip, the largest standard scale that fits.
        let doc = s.editor.doc
        let m = EnginePlot.modelPage(doc: doc, level: doc.currentLevel)
        XCTAssertEqual(m.page.widthMM, 420)
        XCTAssertTrue(EnginePlot.standardRatios.contains(m.ratio))
        var fixed = EnginePageSetup()
        fixed.modelScale = 500
        fixed.modelPaper = "A1"
        fixed.modelPortrait = true
        let m2 = EnginePlot.modelPage(doc: doc, level: doc.currentLevel, setup: fixed)
        XCTAssertEqual(m2.ratio, 500)
        XCTAssertEqual(m2.page.widthMM, 594)
        var exact = EnginePageSetup()
        exact.exactFit = true
        let f = EnginePlot.modelFrame(doc: doc, setup: exact, extents: BBox2(min: .zero, max: Vec2(10000, 5000)), area: BBox2(min: .zero, max: Vec2(100, 100)))
        XCTAssertEqual(f.ratio, 100, accuracy: 1e-9)
    }

    @MainActor func testPlotCommandsAndStyles() async throws {
        let (s, sink) = session()
        _ = try await s.call("doc.new")
        try await run(s, "PREVIEW")
        XCTAssertTrue(hostActions(s, sink).contains { $0["dialog"]?.stringValue == "plotPreview" })
        try await run(s, "PRINTSETUP")
        XCTAssertTrue(hostActions(s, sink).contains { $0["dialog"]?.stringValue == "printSetup" })
        try await run(s, "PLOTSTYLE Set archi pens.ctb")
        XCTAssertEqual(EnginePageSetup.load(s.editor.doc, layoutIndex: nil).plotStyleTable, "archi pens.ctb")
        try await run(s, "PLOTAREA Limits Exact")
        let ps = EnginePageSetup.load(s.editor.doc, layoutIndex: nil)
        XCTAssertEqual(ps.plotArea, "Limits")
        XCTAssertTrue(ps.exactFit)
        let saved = try await s.call("plotstyle.save", obj([("table", obj([("name", .string("Office")), ("pens", obj([("1", obj([("color", .string("#000000")), ("lineweight", .number(0.5))]))]))]))]))
        XCTAssertEqual(saved["name"]?.stringValue, "Office.ctb")
        XCTAssertEqual(s.editor.history.undoLabel, "Plot Style Table")
        XCTAssertNotNil(EnginePlotStyleTable.named("office.ctb", in: s.editor.doc))
        try await run(s, "PLOTSTYLENAME Table \"archi named.stb\"")
        XCTAssertEqual(EnginePageSetup.load(s.editor.doc, layoutIndex: nil).namedStyleTable, "archi named.stb")
        _ = try await s.call("command.run", obj([("line", .string("PUBLISH"))]))
        _ = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertTrue(hostActions(s, sink).contains { $0["action"]?.stringValue == "output" && $0["op"]?.stringValue == "publish" })
    }

    // MARK: Render commands, camera paths, sun frames

    @MainActor func testRenderCommandsAndCameraPaths() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, sink) = session()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        try await run(s, "RENDERSAVE Goldenhour Front 800 600 out.png")
        let save = try XCTUnwrap(hostActions(s, sink).last { $0["op"]?.stringValue == "renderSave" })
        XCTAssertEqual(save["preset"]?.stringValue, "Golden hour")
        XCTAssertEqual(save["camera"]?.stringValue, "Front")
        XCTAssertEqual(save["width"]?.intValue, 800)
        XCTAssertEqual(save["supersample"]?.intValue, 3)
        XCTAssertTrue(save["path"]?.stringValue?.hasSuffix("out.png") ?? false)
        XCTAssertNotNil(save["cameraData"]?["eye"])
        try await run(s, "RENDERQUEUE Cameras")
        let q = try XCTUnwrap(hostActions(s, sink).last { $0["dialog"]?.stringValue == "renderQueue" })
        XCTAssertEqual(q["add"]?.arrayValue?.count, 3)
        try await run(s, "WALKTHROUGHVIDEO 4 walk.mp4")
        let v = try XCTUnwrap(hostActions(s, sink).last { $0["op"]?.stringValue == "video" })
        XCTAssertEqual(v["kind"]?.stringValue, "walkthrough")
        XCTAssertEqual(v["seconds"]?.doubleValue, 4)
        let frames = try await s.call("camerapath.frames", obj([("seconds", .number(2)), ("fps", .int(10))]))
        XCTAssertEqual(frames["count"]?.intValue, 20)
        let firstEye = frames["frames"]?[0]?["eye"]
        XCTAssertEqual(firstEye, EngineJSON.point3(s.editor.doc.namedViews[0].camera!.eye))
        // Camera paths: stored as the Mac CAMERAPATHS JSON, keys at times, one undo step.
        let cam = EngineOutputFormat.cameraJSON(s.editor.doc.namedViews[0].camera!)
        let cam2 = EngineOutputFormat.cameraJSON(s.editor.doc.namedViews[1].camera!)
        let keys: [EngineJSON] = [obj([("name", .string("A")), ("time", .number(0)), ("camera", cam)]), obj([("name", .string("B")), ("time", .number(3)), ("camera", cam2)])]
        let list = try await s.call("camerapath.set", obj([("paths", .array([obj([("name", .string("Path")), ("fps", .int(10)), ("keys", .array(keys))])])), ("label", .string("Add Camera Key"))]))
        XCTAssertEqual(list["paths"]?[0]?["duration"]?.doubleValue, 3)
        XCTAssertEqual(s.editor.history.undoLabel, "Add Camera Key")
        let pf = try await s.call("camerapath.frames", obj([("path", .string("Path"))]))
        XCTAssertEqual(pf["count"]?.intValue, 31)
        XCTAssertEqual(pf["frames"]?[30]?["eye"], EngineJSON.point3(s.editor.doc.namedViews[1].camera!.eye))
        let sun = try await s.call("render.sunFrames", obj([("day", .int(172)), ("fromHour", .number(7)), ("toHour", .number(19)), ("seconds", .number(1)), ("fps", .int(5))]))
        let sf = sun["frames"]?.arrayValue ?? []
        XCTAssertEqual(sf.count, 5)
        XCTAssertGreaterThan(sf[2]["altitude"]?.doubleValue ?? 0, 50)   // 13:00 in June at 44° N
        try await run(s, "CAMERAPATHEDIT")
        XCTAssertTrue(hostActions(s, sink).contains { $0["dialog"]?.stringValue == "cameraPaths" })
        let rw = try await s.call("render.window", obj([("day", .int(172)), ("hour", .number(15))]))
        XCTAssertEqual(rw["presets"]?.arrayValue?.count, 10)
        XCTAssertEqual(rw["cameras"]?.arrayValue?.count, 3)
        XCTAssertTrue(rw["sunText"]?.stringValue?.hasPrefix("Sun altitude") ?? false)
    }

    // MARK: Path tracer and passes

    @MainActor func testPathTracerAndPasses() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, _) = session()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        let cam = EngineOutputFormat.cameraJSON(s.editor.doc.namedViews[0].camera!)
        let st = try await s.call("pathtrace.start", obj([("width", .int(48)), ("height", .int(32)), ("samples", .int(2)), ("sync", .bool(true)), ("camera", cam), ("lod", .int(2))]))
        XCTAssertGreaterThan(st["triangles"]?.intValue ?? 0, 1000)
        XCTAssertGreaterThan(st["textures"]?.intValue ?? 0, 0)   // baseline JPEG textures of the sample
        let status = try await s.call("pathtrace.status", obj([]))
        XCTAssertEqual(status["samples"]?.intValue, 2)
        XCTAssertEqual(status["running"], .bool(false))
        XCTAssertTrue(status["image"]?.stringValue?.hasPrefix("data:image/png;base64,") ?? false)
        let png = tmp("pt.png")
        _ = try await s.call("pathtrace.save", obj([("path", .string(png.path))]))
        let d = try Data(contentsOf: png)
        XCTAssertEqual(Array(d.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        try? FileManager.default.removeItem(at: png)
        let depth = tmp("depth.png")
        let r = try await s.call("render.pass", obj([("pass", .string("Material ID")), ("width", .int(40)), ("height", .int(30)), ("camera", cam), ("lod", .int(2)), ("path", .string(depth.path))]))
        XCTAssertEqual(r["width"]?.intValue, 40)
        XCTAssertGreaterThan(r["materials"]?.arrayValue?.count ?? 0, 3)
        try? FileManager.default.removeItem(at: depth)
        XCTAssertEqual(EngineSession.hsb(0, 0.75, 0.95), RGBA(0.95, 0.95 * 0.25, 0.95 * 0.25))
        let web = tmp("viewer.html")
        _ = try await s.call("webviewer.export", obj([("path", .string(web.path))]))
        XCTAssertTrue(try String(contentsOf: web, encoding: .utf8).contains("<canvas id=\"c\">"))
        try? FileManager.default.removeItem(at: web)
    }

    func testJPEGDecoder() throws {
        let url = Self.repo.appendingPathComponent("assets/demo/textures/cedar.jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("textures not found") }
        let img = try JPEGDecoder.decode(try Data(contentsOf: url))
        XCTAssertEqual(img.width, 2048)
        XCTAssertEqual(img.height, 2048)
        var s = [0.0, 0.0, 0.0], n = 0.0
        for y in stride(from: 0, to: img.height, by: 7) {
            for x in stride(from: 0, to: img.width, by: 7) {
                let o = (y * img.width + x) * 3
                s[0] += Double(img.rgb[o]); s[1] += Double(img.rgb[o + 1]); s[2] += Double(img.rgb[o + 2]); n += 1
            }
        }
        // Pillow (libjpeg): 114.7, 57.5, 33.1.
        XCTAssertEqual(s[0] / n, 114.7, accuracy: 2.5)
        XCTAssertEqual(s[1] / n, 57.5, accuracy: 2.5)
        XCTAssertEqual(s[2] / n, 33.1, accuracy: 2.5)
        XCTAssertThrowsError(try JPEGDecoder.decode(Data([0x89, 0x50])))
    }

    func testPDFNumbersAndText() {
        XCTAssertEqual(EnginePDF.num(1.5), "1.5")
        XCTAssertEqual(EnginePDF.num(2), "2")
        XCTAssertEqual(EnginePDF.num(-0.0004), "0")
        XCTAssertEqual(EnginePDF.num(-12.3456), "-12.346")
        XCTAssertEqual(EnginePDF.hex("A—é"), "4197E9")
        XCTAssertEqual(EnginePDF.width("Hello", size: 10, bold: false), 22.78, accuracy: 1e-9)
        XCTAssertEqual(EnginePDF.pdfString("A"), "<FEFF0041>")
        XCTAssertEqual(EngineOutputFormat.hex24(0xF5C518), "#f5c518")
        XCTAssertEqual(EngineOutputFormat.parseHex24("#F5C518"), 0xF5C518)
    }
}
