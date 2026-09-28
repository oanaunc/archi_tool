// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine document tools (Host/EngineDocTools.swift, EngineDocCommands.swift) and the portable raster export
// (IO/RasterExport.swift): PNG writer and rasteriser, EXPORT PNG, schedule CSV / XLSX exports, Schedule sheet rows,
// Project Browser, Selection panel, Inspector, History steps, Spelling, Text Styles, text formatting in the draw list.
import XCTest
@testable import ArchiCore

final class EngineDocToolsTests: XCTestCase {
    static var cedarHouse: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../assets/demo/Cedar House.archi").standardized
    }

    func obj(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        var o = EngineObject()
        for (k, v) in pairs { o.set(k, v) }
        return o.json
    }
    func tmp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("archi-doctools-" + String(ProcessInfo.processInfo.processIdentifier) + "-" + name)
    }

    @MainActor func session() -> (EngineSession, NotificationSink) {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        EngineSession.registerToolCommands(reg)
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
    /// Three joined walls and a free-standing one.
    @MainActor func walls(_ s: EngineSession) async throws -> [EntityID] {
        _ = try await s.call("command.run", obj([("line", .string("WALL 0,0 5000,0 5000,4000 0,4000 "))]))
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
        _ = try await s.call("command.run", obj([("line", .string("WALL 20000,0 25000,0 "))]))
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
        return s.editor.doc.elements.filter { $0.typeName == "wall" }.map(\.id)
    }

    // MARK: PNG writer and rasteriser

    func testPNGWriterRoundTrip() async throws {
        var img = RGBAImage(width: 5, height: 3, background: RGBA(1, 1, 1))
        img.blend(0, RGBA(1, 0, 0), 1)
        img.blend(7, RGBA(0, 0, 1), 0.5)
        img.dpi = 300
        let png = img.pngData()
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertNotNil(png.range(of: Data("pHYs".utf8)))
        let back = try RGBAImage.decodePNG(png)
        XCTAssertEqual(back.width, 5)
        XCTAssertEqual(back.height, 3)
        XCTAssertEqual(back.pixels, img.pixels)
        XCTAssertEqual(back.pixel(0, 0).g, 0)
        // Transparent images keep their alpha channel.
        var clear = RGBAImage(width: 2, height: 2, background: RGBA(0, 0, 0, 0))
        clear.blend(3, RGBA(0, 1, 0), 1)
        XCTAssertFalse(clear.isOpaque)
        let back2 = try RGBAImage.decodePNG(clear.pngData())
        XCTAssertEqual(back2.pixels, clear.pixels)
    }

    func testRasterFillsStrokesAndText() async throws {
        var r = DrawRaster(image: RGBAImage(width: 100, height: 100), origin: Vec2(0, 100), scale: 1)
        // Even-odd square with a hole.
        let outer = [Vec2(10, 10), Vec2(90, 10), Vec2(90, 90), Vec2(10, 90)]
        let hole = [Vec2(40, 40), Vec2(60, 40), Vec2(60, 60), Vec2(40, 60)]
        r.fill([outer, hole], RGBA(0, 0, 0))
        XCTAssertLessThan(r.image.pixel(20, 20).r, 0.05)
        XCTAssertGreaterThan(r.image.pixel(50, 50).r, 0.95, "the hole stays white")
        XCTAssertGreaterThan(r.image.pixel(5, 5).r, 0.95)
        // A 0.5 mm line at 300 dpi is ~6 px wide.
        var s = DrawRaster(image: RGBAImage(width: 100, height: 100), origin: Vec2(0, 100), scale: 1)
        s.stroke([Vec2(0, 50), Vec2(100, 50)], closed: false, style: StrokeStyle(color: RGBA(1, 0, 0), lineweight: 0.5))
        XCTAssertEqual(s.width(0.5), 0.5 * 300 / 25.4, accuracy: 1e-9)
        XCTAssertLessThan(s.image.pixel(50, 50).g, 0.05)
        XCTAssertLessThan(s.image.pixel(50, 47).g, 0.2)
        XCTAssertGreaterThan(s.image.pixel(50, 40).g, 0.95)
        XCTAssertEqual(s.width(0), 1, "hairlines draw one pixel wide")
        // Dashes leave gaps.
        let pieces = DrawRaster.dashed([Vec2(0, 0), Vec2(100, 0)], closed: false, pattern: [10, -5], dot: 1)
        XCTAssertEqual(pieces.count, 7)
        XCTAssertEqual(pieces.first?.last?.x ?? 0, 10, accuracy: 1e-9)
        // Text with underline and strike-through.
        var t = DrawRaster(image: RGBAImage(width: 200, height: 60), origin: Vec2(0, 60), scale: 1)
        let tg = TextGeom(position: Vec2(10, 20), height: 20, content: "AB")
        t.text(tg, color: RGBA(0, 0, 0), format: RasterTextFormat(underline: true, strike: true))
        let lines = DrawRaster.decorationLines(tg, widthFactor: 1, underline: true, strike: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0][0].y, 16, accuracy: 1e-9)
        var dark = 0
        for p in 0..<(200 * 60) where t.image.pixels[p * 4] < 128 { dark += 1 }
        XCTAssertGreaterThan(dark, 100)
    }

    @MainActor func testPlanPNGExport() async throws {
        let (s, _) = session()
        _ = try await walls(s)
        let url = tmp("plan.png")
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try await s.call("file.export", obj([("path", .string(url.path)), ("format", .string("png"))]))
        XCTAssertEqual(r["format"]?.stringValue, "png")
        let img = try RGBAImage.decodePNG(Data(contentsOf: url))
        // ~25 m of walls + 3 % margin at 1:100 and 300 dpi: about 3100 px on the long side.
        XCTAssertGreaterThan(img.width, 2900)
        XCTAssertLessThan(img.width, 3400)
        XCTAssertGreaterThan(img.width, img.height)
        var dark = 0
        var i = 0
        while i < img.pixels.count { if img.pixels[i] < 100 { dark += 1 }; i += 4 }
        XCTAssertGreaterThan(dark, 500, "walls are drawn")
        // EXPORT PNG <file> from the command line writes the same image.
        let url2 = tmp("plan2.png")
        defer { try? FileManager.default.removeItem(at: url2) }
        try await run(s, "EXPORT PNG " + url2.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path), s.editor.log.suffix(3).joined(separator: " | "))
        // An empty drawing cannot be exported.
        let (e, _) = session()
        do { _ = try await e.call("file.export", obj([("path", .string(tmp("empty.png").path))])); XCTFail("empty drawing exported") } catch {}
    }

    @MainActor func testCedarHousePNG() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let doc = try DocumentIO.read(Self.cedarHouse)
        // Low resolution keeps the debug test fast: the 1600 px minimum on the long side.
        let img = try PlanImageExport.render(doc: doc, dpi: 30)
        XCTAssertEqual(max(img.width, img.height), 1600)
        XCTAssertEqual(img.dpi, 30)
        var dark = 0
        var i = 0
        while i < img.pixels.count { if img.pixels[i] < 128 { dark += 1 }; i += 4 }
        XCTAssertGreaterThan(dark, 5000)
        XCTAssertEqual(img.pixel(0, 0), RGBA(1, 1, 1), "white paper")
    }

    // MARK: Schedules

    @MainActor func testScheduleExportsAndRows() async throws {
        let (s, _) = session()
        _ = try await walls(s)
        let csv = tmp("walls.csv")
        defer { try? FileManager.default.removeItem(at: csv) }
        let r = try await s.call("file.export", obj([("path", .string(csv.path)), ("format", .string("csv:walls"))]))
        XCTAssertEqual(r["format"]?.stringValue, "csv:walls")
        let text = try String(contentsOf: csv, encoding: .utf8)
        XCTAssertEqual(text, ScheduleExporter.csv(doc: s.editor.doc, kind: "walls"))
        XCTAssertEqual(text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 5, "header + 4 walls")
        let xlsx = tmp("doors.xlsx")
        defer { try? FileManager.default.removeItem(at: xlsx) }
        _ = try await s.call("file.export", obj([("path", .string(xlsx.path)), ("format", .string("xlsx:walls"))]))
        let book = try XLSX.read(Data(contentsOf: xlsx))
        XCTAssertEqual(book.first?.name, "Walls")
        XCTAssertEqual(book.first?.rows.count, 5)
        let rows = try await s.call("schedule.get", obj([("kind", .string("walls"))]))
        XCTAssertEqual(rows["count"]?.intValue, 4)
        XCTAssertEqual(rows["rows"]?.arrayValue?.count, 5)
        XCTAssertEqual(rows["kinds"]?.arrayValue?.count, ScheduleExporter.kinds.count)
    }

    // MARK: Selection, inspector, wall chain, hyperlink, quick properties

    @MainActor func testSelectionInspectorAndCommands() async throws {
        let (s, sink) = session()
        let ids = try await walls(s)
        XCTAssertEqual(ids.count, 4)
        let line = s.editor.doc.add(.line(LineGeom(Vec2(0, -2000), Vec2(3000, -2000))))
        _ = try await s.call("select.set", obj([("ids", .ints(ids + [line]))]))
        let info = try await s.call("selection.info")
        XCTAssertEqual(info["total"]?.intValue, 5)
        XCTAssertEqual(info["rows"]?[0]?["type"]?.stringValue, "wall")
        XCTAssertEqual(info["rows"]?[0]?["ids"]?.arrayValue?.count, 4)
        XCTAssertEqual(info["length"]?.doubleValue ?? 0, 3000, accuracy: 1e-6)
        XCTAssertNotNil(info["bounds"]?.arrayValue)
        let insp = try await s.call("inspect.get", obj([("ids", .ints([line]))]))
        let rows = insp["objects"]?[0]?["rows"]?.arrayValue ?? []
        XCTAssertEqual(rows.first?[1]?.stringValue, "#\(line)")
        XCTAssertTrue(rows.contains { $0[0]?.stringValue == "GUID" })
        XCTAssertTrue(insp["objects"]?[0]?["text"]?.stringValue?.contains("Geometry: ") ?? false)
        // SELECTWALLCHAIN picks the three joined walls only.
        _ = try await s.call("select.set", obj([("ids", .array([]))]))
        let st = try await s.call("command.run", obj([("line", .string("SELECTWALLCHAIN"))]))
        XCTAssertEqual(st["command"]?.stringValue, "SELECTWALLCHAIN")
        _ = try await s.call("pick", obj([("x", .number(2500)), ("y", .number(0))]))
        XCTAssertEqual(s.editor.selection.count, 3)
        XCTAssertTrue(s.editor.log.contains("3 joined wall(s) selected."))
        // HYPERLINK on the selection.
        _ = try await s.call("command.run", obj([("line", .string("HYPERLINK"))]))
        _ = try await s.call("input.text", obj([("text", .string("https://www.oanarinaldi.com"))]))
        XCTAssertEqual(s.editor.doc.element(ids[0])?.props["hyperlink"], "https://www.oanarinaldi.com")
        XCTAssertTrue(s.editor.log.contains("3 object(s) link to https://www.oanarinaldi.com."))
        // Window commands ask the shell.
        try await run(s, "SELECTIONINFO")
        XCTAssertEqual(hostActions(s, sink).last?["panel"]?.stringValue, "Selection")
        try await run(s, "QP ON")
        XCTAssertEqual(hostActions(s, sink).last?["action"]?.stringValue, "quickProps")
        XCTAssertEqual(hostActions(s, sink).last?["mode"]?.stringValue, "on")
        try await run(s, "INSPECT")
        XCTAssertEqual(hostActions(s, sink).last?["panel"]?.stringValue, "Inspector")
        try await run(s, "SPELLDIALOG")
        XCTAssertEqual(hostActions(s, sink).last?["dialog"]?.stringValue, "spelling")
        try await run(s, "TEXTSTYLEDIALOG")
        XCTAssertEqual(hostActions(s, sink).last?["dialog"]?.stringValue, "textStyles")
        let hello = try await s.call("engine.hello")
        let names = Set((hello["commands"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue })
        for n in ["SPELLDIALOG", "TEXTSTYLEDIALOG", "TEXTEDITINPLACE", "HYPERLINK", "SELECTIONINFO", "QUICKPROPS", "INSPECT", "SELECTWALLCHAIN"] {
            XCTAssertTrue(names.contains(n), n)
        }
    }

    // MARK: Text: spelling, styles, formatting, in-place editing

    @MainActor func testSpellingTextStylesAndFormatting() async throws {
        let (s, sink) = session()
        let t1 = s.editor.doc.add(.text(TextGeom(position: Vec2(0, 0), height: 250, content: "Kitchen wiht window")))
        let t2 = s.editor.doc.add(.text(TextGeom(position: Vec2(0, 1000), height: 250, content: "Wiht care")))
        let words = try await s.call("spell.words", obj([("all", .bool(true))]))
        let list = (words["words"]?.arrayValue ?? []).compactMap { $0["word"]?.stringValue }
        XCTAssertEqual(list, ["Kitchen", "wiht", "window", "Wiht", "care"])
        let ch = try await s.call("spell.replace", obj([("word", .string("wiht")), ("replacement", .string("with")), ("ids", .ints([t1]))]))
        XCTAssertEqual(ch["changed"]?.intValue, 1)
        XCTAssertEqual(s.editor.history.undoLabel, "Spelling")
        if case .text(let t)? = s.editor.doc.entity(t1)?.geometry { XCTAssertEqual(t.content, "Kitchen with window") } else { XCTFail() }
        _ = try await s.call("spell.add", obj([("word", .string("Wiht"))]))
        XCTAssertTrue(SpellCheck.customWords(s.editor.doc).contains("wiht"))
        XCTAssertEqual(s.editor.history.undoLabel, "Add to Dictionary")
        // Text styles: new, invalid, rename (text follows), current.
        var ts = try await s.call("textstyle.list")
        XCTAssertEqual(ts["newName"]?.stringValue, "Style 1")
        var r = try await s.call("textstyle.apply", obj([("name", .string("Notes")), ("font", .string("Arial")), ("height", .string("180")),
                                                         ("widthFactor", .string("0.8")), ("obliqueDegrees", .string("10"))]))
        XCTAssertEqual(r["ok"], .bool(true))
        XCTAssertEqual(s.editor.history.undoLabel, "Text Style")
        r = try await s.call("textstyle.apply", obj([("name", .string("Bad")), ("widthFactor", .string("0")), ("obliqueDegrees", .string("90"))]))
        XCTAssertEqual(r["ok"], .bool(false))
        XCTAssertEqual(r["message"]?.stringValue, "Check: width factor 0.01–100, oblique −85…85°")
        r = try await s.call("textstyle.apply", obj([("original", .string("Standard")), ("name", .string("Notes"))]))
        XCTAssertEqual(r["message"]?.stringValue, "A style with that name exists.")
        let std = s.editor.doc.textStyles.first { $0.name == "Standard" }
        r = try await s.call("textstyle.apply", obj([("original", .string("Standard")), ("name", .string("Plain")), ("font", .string(std?.font ?? "Helvetica")),
                                                     ("height", .string("0")), ("widthFactor", .string("1")), ("obliqueDegrees", .string("0"))]))
        XCTAssertEqual(r["ok"], .bool(true))
        if case .text(let t)? = s.editor.doc.entity(t2)?.geometry { XCTAssertEqual(t.style, "Plain") } else { XCTFail() }
        _ = try await s.call("textstyle.current", obj([("name", .string("Notes"))]))
        XCTAssertEqual(s.editor.doc.variable("TEXTSTYLE"), "Notes")
        ts = try await s.call("textstyle.list")
        XCTAssertEqual(ts["current"]?.stringValue, "Notes")
        XCTAssertEqual(ts["styles"]?.arrayValue?.first { $0["name"]?.stringValue == "Notes" }?["obliqueDegrees"]?.stringValue, "10")
        // Bold / strike-through through text.edit; the draw list carries the formatting.
        _ = try await s.call("text.edit", obj([("id", .int(t1)), ("content", .string("Kitchen")), ("bold", .bool(true)), ("strike", .bool(true))]))
        XCTAssertEqual(s.editor.doc.entity(t1)?.props["strike"], "1")
        XCTAssertTrue(s.editor.doc.entity(t1)?.props["mtext"]?.contains("\\K") ?? false)
        let dl = try await s.call("view.drawList")
        let item = (dl["items"]?.arrayValue ?? []).first { $0["type"]?.stringValue == "text" && $0["id"]?.intValue == t1 }
        XCTAssertEqual(item?["format"]?["bold"], .bool(true))
        XCTAssertEqual(item?["format"]?["strike"], .bool(true))
        XCTAssertEqual(item?["format"]?["italic"], .bool(false))
        let plain = (dl["items"]?.arrayValue ?? []).first { $0["type"]?.stringValue == "text" && $0["id"]?.intValue == t2 }
        XCTAssertNil(plain?["format"])
        let dc = try await s.call("canvas.doubleClick", obj([("id", .int(t1))]))
        XCTAssertEqual(dc["format"]?["strike"], .bool(true))
        // TEXTEDITINPLACE picks text and opens the canvas editor.
        _ = try await s.call("command.run", obj([("line", .string("TEXTEDITINPLACE"))]))
        _ = try await s.call("pick", obj([("x", .number(100)), ("y", .number(1100)), ("tolerance", .number(200))]))
        let h = hostActions(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "textEditor")
        XCTAssertEqual(h?["id"]?.intValue, t2)
    }

    // MARK: Project Browser and History

    @MainActor func testBrowserAndHistorySteps() async throws {
        let (s, _) = session()
        _ = try await walls(s)
        s.editor.transaction("Views") { d in
            d.namedViews.append(NamedView(name: "Cam", center: .zero, height: 1000, camera: Camera(eye: Vec3(0, -9000, 3000), target: .zero)))
            var v = ProjectViews.create("Plan A", doc: &d)
            v.crop = [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)]
            v.cropActive = true
            if let i = d.viewIndex("Plan A") { d.views[i] = v }
            d.modelGroups.append(ModelGroup(name: "G1", elements: []))
        }
        let b = try await s.call("browser.get")
        XCTAssertEqual(b["levels"]?.arrayValue?.count, s.editor.doc.levels.count)
        XCTAssertEqual(b["views3d"]?.arrayValue?.count, 6)
        XCTAssertEqual(b["namedViews"]?[0]?["name"]?.stringValue, "Cam")
        XCTAssertEqual(b["namedViews"]?[0]?["camera"], .bool(true))
        XCTAssertEqual(b["projectViews"]?[0]?["name"]?.stringValue, "Plan A")
        XCTAssertEqual(b["elevations"]?.arrayValue?.count, 5)
        XCTAssertEqual(b["elevations"]?[0]?["view"]?.stringValue, "back")
        XCTAssertEqual(b["schedules"]?.arrayValue?.count, 6)
        XCTAssertEqual(b["groups"]?[0]?["name"]?.stringValue, "G1")
        let ov = try await s.call("browser.openView", obj([("name", .string("Plan A"))]))
        XCTAssertEqual(ov["kind"]?.stringValue, "plan")
        XCTAssertEqual(ov["crop"]?[0]?.doubleValue ?? 0, -500, accuracy: 1e-6)
        XCTAssertEqual(s.editor.doc.variable(ProjectViews.currentKey), "Plan A")
        XCTAssertEqual(s.editor.history.undoLabel, "Open View")
        // History: numbered steps, back to the start and forward again.
        let steps = s.editor.history.undoStack.count
        XCTAssertGreaterThan(steps, 2)
        var h = try await s.call("history.goto", obj([("index", .int(0))]))
        XCTAssertEqual(h["undo"]?.arrayValue?.count, 0)
        XCTAssertTrue(s.editor.doc.elements.isEmpty)
        h = try await s.call("history.goto", obj([("index", .int(steps))]))
        XCTAssertEqual(h["undo"]?.arrayValue?.count, steps)
        XCTAssertEqual(s.editor.doc.elements.count, 4)
    }
}
