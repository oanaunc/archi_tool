// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine contextual ribbon tabs (Host/EngineContextRibbon.swift), the portable sheet commands and sheet images
// (Host/EngineSheetCommands.swift, EngineSheetImage.swift), crash recovery and file versions (Host/EngineRecovery.swift).
import XCTest
@testable import ArchiCore

final class EngineSheetsRecoveryTests: XCTestCase {
    func obj(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        var o = EngineObject()
        for (k, v) in pairs { o.set(k, v) }
        return o.json
    }
    func tmp(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-sheets-" + String(ProcessInfo.processInfo.processIdentifier) + "-" + name)
        try? FileManager.default.removeItem(at: u)
        return u
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
    /// Runs a command and answers its prompts one by one ("" = Enter); cancels whatever is still asking.
    @MainActor func feed(_ s: EngineSession, _ line: String, _ answers: [String] = []) async throws {
        var st = try await s.call("command.run", obj([("line", .string(line))]))
        for a in answers where st["active"]?.boolValue == true {
            st = try await s.call("input.text", obj([("text", .string(a))]))
        }
        if st["active"]?.boolValue == true { _ = try await s.call("input.key", obj([("key", .string("Escape"))])) }
    }
    @MainActor func wall(_ s: EngineSession) async throws -> [EntityID] {
        _ = try await s.call("command.run", obj([("line", .string("WALL 0,0 5000,0 5000,4000 "))]))
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
        return s.editor.doc.elements.filter { $0.typeName == "wall" }.map(\.id)
    }
    @MainActor func sheet(_ s: EngineSession, viewports: Int = 1) {
        s.editor.doc.layouts = []  // a new drawing starts with "Sheet 1"
        var l = Layout(name: "A-101")
        for i in 0..<viewports {
            let x = 30.0 + Double(i) * 150
            l.viewports.append(Viewport(origin: Vec2(x, 70), size: Vec2(140, 100), viewCenter: Vec2(2500, 2000), scale: 50, level: s.editor.doc.currentLevel))
        }
        s.editor.doc.layouts.append(l)
        s.editor.doc.setVariable("CTAB", "A-101")
    }

    // MARK: Contextual ribbon tabs

    @MainActor func testContextualRibbonTabs() async throws {
        let (s, _) = session()
        let walls = try await wall(s)
        XCTAssertFalse(walls.isEmpty)
        let none = try await s.call("ribbon.context", .object([]))
        XCTAssertTrue(none["tab"]?.isNull ?? false, "no selection, no tab")
        _ = try await s.call("select.set", obj([("ids", EngineJSON.array(walls.map { EngineJSON.int($0) }))]))
        let w = try await s.call("ribbon.context", .object([]))
        XCTAssertEqual(w["tab"]?["title"]?.stringValue, "Modify Wall")
        let cmds = (w["tab"]?["items"]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue }
        XCTAssertEqual(Array(cmds.prefix(2)), ["DOOR", "WINDOW"])
        XCTAssertEqual(Array(cmds.suffix(6)), ["MOVE", "COPY", "ROTATE", "MIRROR", "MATCHPROP", "SELECTSIMILAR"])
        // Text, hatch, polyline and mixed selections.
        let t = s.editor.doc.add(.text(TextGeom(position: Vec2(0, 9000), height: 250, content: "Kitchen")))
        let pl = s.editor.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000)])))
        let tt = try await s.call("ribbon.context", obj([("ids", EngineJSON.array([EngineJSON.int(t)]))]))
        XCTAssertEqual(tt["tab"]?["title"]?.stringValue, "Text Editor")
        let pp = try await s.call("ribbon.context", obj([("ids", EngineJSON.array([EngineJSON.int(pl)]))]))
        XCTAssertEqual(pp["tab"]?["title"]?.stringValue, "Polyline")
        let mixed = try await s.call("ribbon.context", obj([("ids", EngineJSON.array([EngineJSON.int(t), EngineJSON.int(pl)]))]))
        XCTAssertTrue(mixed["tab"]?.isNull ?? false, "a mixed selection has no contextual tab")
        XCTAssertEqual(EngineContextRibbon.tab(s.editor.doc, Set(walls))?.category, "Wall")
    }

    // MARK: Sheet commands

    @MainActor func testSheetGridPlaceholderFieldsAndRenumber() async throws {
        let (s, _) = session()
        sheet(s)
        try await feed(s, "SHEETGRID", ["5"])
        XCTAssertEqual(s.editor.doc.variable("SHEETGRID:A-101"), "5")
        try await feed(s, "SHEETPLACEHOLDER", ["Toggle"])
        XCTAssertEqual(s.editor.doc.layouts[0].titleBlock["placeholder"], "1")
        try await feed(s, "SHEETPLACEHOLDER", ["New", "Cover"])
        XCTAssertEqual(s.editor.doc.layouts.count, 2)
        XCTAssertEqual(s.editor.doc.layouts[1].titleBlock["placeholder"], "1")
        try await feed(s, "SHEETFIELD", ["Project", "CLIENTREF", "C-42"])
        XCTAssertEqual(s.editor.doc.variable("PROJFIELD:CLIENTREF"), "C-42")
        try await feed(s, "SHEETFIELD", ["Sheet", "CLIENTREF", "C-43"])
        XCTAssertEqual(s.editor.doc.layouts[0].titleBlock["custom:CLIENTREF"], "C-43")
        XCTAssertEqual(EngineSheetCommands.fields(s.editor.doc, layout: s.editor.doc.layouts[0]).first?.1, "C-43")
        try await feed(s, "SHEETRENUMBER", ["B-", "201"])
        XCTAssertEqual(s.editor.doc.layouts[0].titleBlock["sheetNumber"], "B-201")
        XCTAssertEqual(s.editor.doc.layouts[1].titleBlock["sheetNumber"], "B-202")
        XCTAssertTrue(s.editor.log.contains { $0.contains("2 sheet(s) numbered B-201") }, s.editor.log.suffix(3).joined(separator: " | "))
        try await feed(s, "SHEETVIEWTITLES")
        XCTAssertTrue(EngineSheets.hasViewTitleEntities(s.editor.doc.layouts[0]))
        try await feed(s, "TITLEBLOCKDESIGN", ["Create"])
        XCTAssertNotNil(s.editor.doc.blocks["TB-CUSTOM"])
        XCTAssertEqual(s.editor.doc.variable("TITLEBLOCKBLOCK"), "TB-CUSTOM")
        try await feed(s, "TITLEBLOCKDESIGN", ["Builtin"])
        XCTAssertNil(s.editor.doc.variable("TITLEBLOCKBLOCK"))
    }

    @MainActor func testPolygonalViewportAndAlign() async throws {
        let (s, _) = session()
        _ = try await wall(s)
        sheet(s, viewports: 2)
        try await feed(s, "MVIEWPOLY", ["20,200", "120,200", "70,260", "", "20"])
        let l = s.editor.doc.layouts[0]
        XCTAssertEqual(l.viewports.count, 3)
        XCTAssertEqual(EngineViewports.clip(s.editor.doc, 0, 2)?.count, 3)
        XCTAssertEqual(l.viewports[2].scale, 20, accuracy: 1e-9)
        // MVSETUP Horizontal: viewport 2 pans so model point (0,0) lines up with viewport 1's (0,0).
        s.editor.doc.layouts[0].viewports[1].viewCenter = Vec2(2500, 2500)
        try await feed(s, "MVSETUP", ["Horizontal", "1", "0,0", "2", "0,0"])
        let v = s.editor.doc.layouts[0].viewports
        let a = EngineSheetCommands.paperPoint(Vec2(0, 0), in: v[0]), b = EngineSheetCommands.paperPoint(Vec2(0, 0), in: v[1])
        XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
        XCTAssertEqual(v[1].viewCenter.x, 2500, accuracy: 1e-9)
    }

    @MainActor func testLayoutTabsAndPaperZoomAskTheShell() async throws {
        let (s, sink) = session()
        try await feed(s, "LAYOUTTABS", ["OFF"])
        try await feed(s, "ZOOMXP", ["1/50XP"])
        let acts = hostActions(s, sink)
        XCTAssertEqual(acts.first { $0["action"]?.stringValue == "layoutTabs" }?["on"]?.boolValue, false)
        let z = acts.first { $0["action"]?.stringValue == "paperZoom" }
        XCTAssertEqual(z?["ratio"]?.doubleValue ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(EngineSheetCommands.paperFactor("1:100") ?? 0, 0.01, accuracy: 1e-12)
        XCTAssertNil(EngineSheetCommands.paperFactor("abc"))
        // ZOOM nXP goes through the same hook.
        try await feed(s, "ZOOM", ["1/20XP"])
        XCTAssertTrue(hostActions(s, sink).contains { $0["action"]?.stringValue == "paperZoom" && abs(($0["ratio"]?.doubleValue ?? 0) - 20) < 1e-9 })
    }

    @MainActor func testSheetImagePNGAndTIFF() async throws {
        let (s, _) = session()
        _ = try await wall(s)
        sheet(s)
        let png = tmp("sheet.png")
        try await feed(s, "SHEETIMAGE", ["A-101", "50", "Png", png.path])
        let img = try RGBAImage.decodePNG(try Data(contentsOf: png))
        let paper = s.editor.doc.layouts[0].paper
        XCTAssertEqual(Double(img.width), (paper.width * 50 / 25.4).rounded(), accuracy: 1)
        XCTAssertEqual(Double(img.height), (paper.height * 50 / 25.4).rounded(), accuracy: 1)
        var dark = 0
        var i = 0
        while i < img.pixels.count { if img.pixels[i] < 128 { dark += 1 }; i += 4 }
        XCTAssertGreaterThan(dark, 200, "frame, title block and walls are drawn")
        let tif = tmp("model.tiff")
        _ = try await s.call("sheet.image", obj([("layout", .string("Model")), ("dpi", .int(40)), ("format", .string("tiff")), ("path", .string(tif.path))]))
        let t = try Data(contentsOf: tif)
        XCTAssertEqual(Array(t.prefix(4)), [0x49, 0x49, 42, 0])
        // JPEG: a temporary PNG for the shell to encode.
        let j = try await s.call("sheet.image", obj([("layout", .int(0)), ("dpi", .int(36)), ("format", .string("jpeg"))]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: j["png"]?.stringValue ?? "/nonexistent"))
    }

    @MainActor func testPageSetupImport() async throws {
        let (s, _) = session()
        sheet(s)
        var src = ArchiDocument()
        src.layouts = [Layout(name: "S-1", paper: PaperSize.standard[0])]
        var ps = EnginePageSetup()
        ps.colorMode = "Monochrome"
        ps.store(in: &src, layoutIndex: 0)
        let f = tmp("source.archi")
        try ArchiFile.encode(src).write(to: f)
        try await feed(s, "PSETUPIN", [f.path, "1", "Current"])
        XCTAssertEqual(EnginePageSetup.load(s.editor.doc, layoutIndex: 0).colorMode, "Monochrome")
        XCTAssertEqual(s.editor.doc.layouts[0].paper, PaperSize.standard[0])
        XCTAssertTrue(s.editor.log.contains { $0.contains("Page setup S-1 applied to 1 sheet(s).") }, s.editor.log.suffix(3).joined(separator: " | "))
    }

    // MARK: Recovery and versions

    @MainActor func testAutosaveRecoveryRestore() async throws {
        let folder = tmp("recovery")
        let (a, _) = session()
        _ = try await a.call("recovery.setup", obj([("folder", .string(folder.path))]))
        _ = try await wall(a)
        let w = try await a.call("recovery.autosave", .object([]))
        XCTAssertEqual(w["written"]?.boolValue, true)
        let again = try await a.call("recovery.autosave", .object([]))
        XCTAssertEqual(again["written"]?.boolValue, false, "nothing changed since the last autosave")

        let (b, sinkB) = session()
        _ = try await b.call("recovery.setup", obj([("folder", .string(folder.path))]))
        let live = try await b.call("recovery.list", .object([]))
        XCTAssertEqual(live["items"]?.arrayValue?.count, 0, "a running window's files are not offered")
        let saved = EngineRecovery.staleSeconds
        EngineRecovery.staleSeconds = 0
        defer { EngineRecovery.staleSeconds = saved }
        let list = try await b.call("recovery.list", .object([]))
        let items = list["items"]?.arrayValue ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["name"]?.stringValue, "Untitled")
        // DRAWINGRECOVERY in the empty window restores by number.
        try await feed(b, "DRAWINGRECOVERY", ["1"])
        XCTAssertEqual(b.editor.doc.elements.filter { $0.typeName == "wall" }.count, a.editor.doc.elements.filter { $0.typeName == "wall" }.count)
        XCTAssertTrue(b.editor.isDirty)
        XCTAssertTrue(hostActions(b, sinkB).contains { $0["action"]?.stringValue == "recovered" })
        let after = try await b.call("recovery.list", .object([]))
        XCTAssertEqual(after["items"]?.arrayValue?.count, 0, "the recovery copy is removed once restored")
        // Saving discards the window's own recovery copy.
        let aid = a.recoveryState.id
        _ = try await a.call("recovery.autosave", obj([("force", .bool(true))]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: EngineRecovery.dataURL(folder, aid).path))
        let doc = tmp("saved.archi")
        _ = try await a.call("doc.save", obj([("path", .string(doc.path))]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: EngineRecovery.dataURL(folder, aid).path))
    }

    @MainActor func testFileVersions() async throws {
        let root = tmp("versions")
        let (s, sink) = session()
        _ = try await s.call("recovery.setup", obj([("folder", .string(tmp("rec2").path)), ("versionsFolder", .string(root.path)), ("keep", .int(3))]))
        _ = try await wall(s)
        let f = tmp("house.archi")
        _ = try await s.call("doc.save", obj([("path", .string(f.path))]))
        let n1 = s.editor.doc.elements.count
        try await feed(s, "WALL", ["0,10000", "3000,10000", ""])
        _ = try await s.call("doc.save", .object([]))
        let l = try await s.call("versions.list", .object([]))
        XCTAssertEqual(l["versions"]?.arrayValue?.count, 2)
        XCTAssertEqual(l["name"]?.stringValue, f.lastPathComponent)
        // Restore the older version: the drawing reloads, the replaced file becomes a version.
        _ = try await s.call("versions.restore", obj([("index", .int(1))]))
        XCTAssertEqual(s.editor.doc.elements.count, n1)
        let l2 = try await s.call("versions.list", .object([]))
        XCTAssertEqual(l2["versions"]?.arrayValue?.count, 3)
        let c = try await s.call("versions.open", obj([("index", .int(0))]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: c["path"]?.stringValue ?? "/nonexistent"))
        // Keep prunes the oldest.
        _ = try await s.call("versions.save", .object([]))
        let l3 = try await s.call("versions.list", .object([]))
        XCTAssertEqual(l3["versions"]?.arrayValue?.count, 3)
        try await feed(s, "FILEVERSIONS", ["List"])
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("  3. ") }, s.editor.log.suffix(4).joined(separator: " | "))
        try await feed(s, "FILEVERSIONS", ["Browse"])
        XCTAssertTrue(hostActions(s, sink).contains { $0["dialog"]?.stringValue == "versions" })
        XCTAssertEqual(EngineRecovery.pruneIndices(count: 5, keep: 3), [3, 4])
    }
}
