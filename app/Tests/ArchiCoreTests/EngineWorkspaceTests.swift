// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine panels and workspace (Host/EngineWorkspace.swift, EngineWorkspaceCommands.swift, EngineMCPExtras.swift):
// Alerts, Navigator, Content (Design Center), Outliner, projection tiles, macro buttons, plugin undo groups, the AI
// assistant's context / trial run / apply, the portable panel, view, window and settings commands and the extra MCP tools.
import XCTest
@testable import ArchiCore

extension EngineSessionTests {
    @MainActor func workspaceSession() -> (EngineSession, NotificationSink) {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        EngineSession.registerToolCommands(reg)
        let sink = NotificationSink()
        let s = EngineSession(editor: Editor(registry: reg), emit: { sink.lines.append($0) })
        return (s, sink)
    }

    @MainActor func hosts(_ s: EngineSession, _ sink: NotificationSink) -> [EngineJSON] {
        s.flushNotifications()
        return hostActions(sink)
    }

    @MainActor func wsRun(_ s: EngineSession, _ text: String) async throws {
        _ = try await s.call("command.run", obj([("line", .string(text))]))
        if !s.editor.isIdle { _ = try await s.call("input.key", obj([("key", .string("Enter"))])) }
    }

    @MainActor func testWorkspacePanelCommands() async throws {
        let (s, sink) = workspaceSession()
        for n in ["NOTIFICATIONS", "NAVIGATOR", "ADCENTER", "OUTLINERPANEL", "FLOATPANEL", "TILEDVIEWS", "DVIEW", "PERSPECTIVE", "KEYBOARDNAV", "ASSISTANT",
                  "LANGUAGE", "EXPORTSETTINGS", "IMPORTSETTINGS", "CMDLINEOPTIONS", "CRASHREPORTS", "FILETAB", "FILETABCLOSE", "WINDOWTABS", "SYSWINDOWS", "FULLSCREEN"] {
            XCTAssertNotNil(s.editor.registry.lookup(n), n)
        }
        XCTAssertEqual(s.editor.registry.lookup("WARNINGS")?.name, "NOTIFICATIONS")
        XCTAssertEqual(s.editor.registry.lookup("DESIGNCENTER")?.name, "ADCENTER")
        try await wsRun(s, "NOTIFICATIONS")
        XCTAssertEqual(hosts(s, sink).last?["panel"]?.stringValue, "Alerts")
        XCTAssertTrue(s.editor.log.contains("No warnings."))
        try await wsRun(s, "NAVIGATOR")
        var h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "showPanel")
        XCTAssertEqual(h?["panel"]?.stringValue, "Navigator")
        XCTAssertEqual(h?["mode"]?.stringValue, "2D")
        try await wsRun(s, "ADC")
        XCTAssertEqual(hosts(s, sink).last?["panel"]?.stringValue, "Content")
        try await wsRun(s, "OUTLINERPANEL")
        XCTAssertEqual(hosts(s, sink).last?["dialog"]?.stringValue, "outliner")
        try await wsRun(s, "FLOATPANEL Layers")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "floatPanel")
        XCTAssertEqual(h?["panel"]?.stringValue, "Layers")
        try await wsRun(s, "TILEDVIEWS 3")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "tiledViews")
        XCTAssertEqual(h?["arrangement"]?.stringValue, "3")
    }

    @MainActor func testWorkspaceViewCommands() async throws {
        let (s, sink) = workspaceSession()
        try await wsRun(s, "DVIEW TW 30")
        XCTAssertEqual(s.editor.doc.variable("VIEWTWIST").flatMap(Double.init) ?? 0, 30, accuracy: 1e-6)
        XCTAssertTrue(s.editor.log.contains("View twist 30°."))
        try await wsRun(s, "DVIEW Off")
        XCTAssertNil(s.editor.doc.variable("VIEWTWIST"))
        let canvas = try await s.call("canvas.state")
        XCTAssertEqual(canvas["twist"]?.doubleValue, 0)
        try await wsRun(s, "PERSPECTIVE 0")
        let hs = hosts(s, sink)
        XCTAssertEqual(hs.last?["action"]?.stringValue, "setView")
        XCTAssertEqual(hs.last?["view"]?.stringValue, "ortho")
        XCTAssertEqual(hs.dropLast().last?["action"]?.stringValue, "show3D")
        XCTAssertEqual(s.editor.doc.variable("PERSPECTIVE"), "0")
        try await wsRun(s, "PERSPECTIVE 2")
        XCTAssertEqual(s.editor.doc.variable("PERSPECTIVE"), "0")
        try await wsRun(s, "KEYBOARDNAV 25")
        let k = hosts(s, sink).last
        XCTAssertEqual(k?["key"]?.stringValue, "keyboardCursorStep")
        XCTAssertEqual(k?["value"]?.intValue, 25)
        XCTAssertEqual(EngineSession.uiPreferences["keyboardCursorStep"], "25")
        XCTAssertTrue(s.editor.log.contains { $0.contains("arrow keys move the crosshair") })
    }

    @MainActor func testWorkspaceSettingsAndWindowCommands() async throws {
        let (s, sink) = workspaceSession()
        EngineSession.uiPreferences["uiLanguage"] = "auto"
        try await wsRun(s, "LANGUAGE Deutsch")
        var h = hosts(s, sink).last
        XCTAssertEqual(h?["key"]?.stringValue, "uiLanguage")
        XCTAssertEqual(h?["value"]?.stringValue, "de")
        XCTAssertTrue(s.editor.log.contains("Interface language: Deutsch."))
        XCTAssertEqual(s.editor.registry.lookup("LIMBA")?.name, "LANGUAGE")
        try await wsRun(s, "CMDLINEOPTIONS Lines 8")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["key"]?.stringValue, "cmdline")
        XCTAssertEqual(h?["value"]?["lines"]?.intValue, 8)
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Command line: ") && $0.contains("8 line(s)") })
        try await wsRun(s, "CMDLINEOPTIONS Lines 99")
        XCTAssertEqual(EngineSession.uiPreferences["cmdline.lines"], "8")
        try await wsRun(s, "CRASHREPORTS On")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "crashReports")
        XCTAssertEqual(h?["op"]?.stringValue, "On")
        try await wsRun(s, "EXPORTSETTINGS")
        XCTAssertEqual(hosts(s, sink).last?["action"]?.stringValue, "exportSettings")
        try await wsRun(s, "IMPORTSETTINGS")
        XCTAssertEqual(hosts(s, sink).last?["action"]?.stringValue, "importSettings")
        try await wsRun(s, "FILETAB")
        XCTAssertEqual(hosts(s, sink).last?["on"], .bool(true))
        XCTAssertTrue(s.editor.log.contains("File tabs on."))
        try await wsRun(s, "FILETABCLOSE")
        XCTAssertEqual(hosts(s, sink).last?["on"], .bool(false))
        try await wsRun(s, "WINDOWTABS Tabs")
        XCTAssertEqual(hosts(s, sink).last?["op"]?.stringValue, "Tabs")
        XCTAssertTrue(s.editor.log.contains("New drawings open as tabs."))
        try await wsRun(s, "SYSWINDOWS Cascade")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "arrangeWindows")
        XCTAssertEqual(h?["mode"]?.stringValue, "Cascade")
        try await wsRun(s, "FULLSCREEN")
        XCTAssertEqual(hosts(s, sink).last?["action"]?.stringValue, "fullScreen")
        try await wsRun(s, "ASSISTANT Panel")
        XCTAssertEqual(hosts(s, sink).last?["dialog"]?.stringValue, "assistant")
        for n in ["LANGUAGE", "FULLSCREEN", "SYSWINDOWS", "ASSISTANT", "TILEDVIEWS"] { XCTAssertFalse(s.editor.registry.lookup(n)?.modifies ?? true, n) }
    }

    @MainActor func testWorkspaceAlertsNavigatorOutliner() async throws {
        let (s, _) = workspaceSession()
        try await wsRun(s, "LINE 0,0 1000,0 ")
        try await wsRun(s, "WALL 0,1000 5000,1000 ")
        var d = s.editor.doc
        d.entities[0].layer = "NO-SUCH-LAYER"
        s.editor.doc = d
        var r = try await s.call("alerts.get", obj([("showInfo", .bool(true))]))
        let items = r["items"]?.arrayValue ?? []
        let missing = items.first { $0["code"]?.stringValue == "LAYER-MISSING" }
        XCTAssertNotNil(missing)
        XCTAssertEqual(missing?["severity"]?.stringValue, "info")
        XCTAssertEqual(missing?["ids"]?[0]?.intValue, s.editor.doc.entities[0].id)
        XCTAssertNotNil(missing?["bounds"]?.arrayValue)
        r = try await s.call("alerts.get", obj([("showInfo", .bool(false))]))
        XCTAssertFalse((r["items"]?.arrayValue ?? []).contains { $0["code"]?.stringValue == "LAYER-MISSING" })
        let key = missing?["key"]?.stringValue ?? ""
        r = try await s.call("alerts.get", obj([("showInfo", .bool(true)), ("dismissed", EngineJSON.strings([key]))]))
        XCTAssertFalse((r["items"]?.arrayValue ?? []).contains { $0["key"]?.stringValue == key })
        let nav = try await s.call("navigator.get")
        XCTAssertGreaterThanOrEqual(nav["lines"]?.arrayValue?.count ?? 0, 2)
        XCTAssertEqual(nav["extents"]?.arrayValue?.count, 4)
        let out = try await s.call("outliner.get", obj([("filter", .string(""))]))
        XCTAssertEqual(out["empty"], .bool(true))
        let tile = try await s.call("view.projection", obj([("view", .string("South"))]))
        XCTAssertEqual(tile["title"]?.stringValue, "South Elevation")
        XCTAssertGreaterThan(tile["items"]?.arrayValue?.count ?? 0, 0)
        let img = try await s.call("view.projection", obj([("view", .string("South")), ("width", .int(200)), ("height", .int(120))]))
        XCTAssertEqual(img["width"]?.intValue, 200)
        let png = Data(base64Encoded: img["png"]?.stringValue ?? "") ?? Data()
        let decoded = try RGBAImage.decodePNG(png)
        XCTAssertEqual(decoded.width, 200)
        XCTAssertEqual(decoded.height, 120)
        XCTAssertEqual(img["rect"]?.arrayValue?.count, 4)
        do { _ = try await s.call("view.projection", obj([("view", .string("Top"))])); XCTFail("Top is not a projection tile") } catch {}
    }

    @MainActor func testWorkspaceDesignCenter() async throws {
        let (s, _) = workspaceSession()
        let path = EngineSessionTests.cedarHouse.path
        let scan = try await s.call("content.scan", obj([("path", .string(path))]))
        XCTAssertEqual(scan["name"]?.stringValue, "Cedar House")
        let kinds = scan["kinds"]?.arrayValue ?? []
        XCTAssertEqual(kinds.count, 6)
        let layers = (kinds.first { $0["kind"]?.stringValue == "Layers" }?["names"]?.arrayValue ?? []).compactMap { $0.stringValue }
        let newOnes = layers.filter { s.editor.doc.layer(named: $0) == nil }
        XCTAssertFalse(newOnes.isEmpty)
        let before = s.editor.doc.layers.count
        var r = try await s.call("content.add", obj([("path", .string(path)), ("kind", .string("Layers")), ("names", EngineJSON.strings([newOnes[0]]))]))
        XCTAssertEqual(r["added"]?.arrayValue?.count, 1)
        XCTAssertEqual(s.editor.doc.layers.count, before + 1)
        XCTAssertEqual(s.editor.history.undoLabel, "Design Center")
        r = try await s.call("content.add", obj([("path", .string(path)), ("kind", .string("Layers")), ("names", EngineJSON.strings([newOnes[0]]))]))
        XCTAssertEqual(r["message"]?.stringValue, "Nothing new: those names already exist here.")
        r = try await s.call("content.add", obj([("path", .string(path)), ("kind", .string("Layers")), ("all", .bool(true))]))
        XCTAssertEqual(s.editor.doc.layers.count, before + newOnes.count)
        do { _ = try await s.call("content.scan", obj([("path", .string("/no/such/file.archi"))])); XCTFail("missing file") } catch {}
    }

    @MainActor func testWorkspaceMacroButtonsAndUndoGroups() async throws {
        let (s, _) = workspaceSession()
        var d = s.editor.doc
        MacroButtons.setDocument([MacroButton(name: "Line100", macro: "^C^CLINE 0,0 100,0 ;", icon: "line.diagonal", tooltip: "A 100 mm line")], &d)
        s.editor.doc = d
        let list = try await s.call("macro.buttons")
        let b = list.arrayValue?.first { $0["name"]?.stringValue == "Line100" }
        XCTAssertEqual(b?["tooltip"]?.stringValue, "A 100 mm line")
        let st = try await s.call("macro.run", obj([("macro", .string("^C^CLINE 0,0 100,0 ;"))]))
        if st["active"]?.boolValue == true { _ = try await s.call("input.key", obj([("key", .string("Escape"))])) }
        XCTAssertEqual(s.editor.doc.entities.count, 1)
        let n0 = s.editor.doc.entities.count
        _ = try await s.call("undo.begin")
        try await wsRun(s, "LINE 0,0 500,0 ")
        try await wsRun(s, "CIRCLE 0,0 200")
        let end = try await s.call("undo.end", obj([("label", .string("MYPLUGIN"))]))
        XCTAssertEqual(end["collapsed"], .bool(true))
        XCTAssertEqual(s.editor.history.undoLabel, "MYPLUGIN")
        XCTAssertEqual(s.editor.doc.entities.count, n0 + 2)
        _ = try await s.call("edit.undo")
        XCTAssertEqual(s.editor.doc.entities.count, n0)
        _ = try await s.call("undo.begin")
        let none = try await s.call("undo.end", obj([("label", .string("NOTHING"))]))
        XCTAssertEqual(none["collapsed"], .bool(false))
    }

    @MainActor func testWorkspaceAssistant() async throws {
        let (s, _) = workspaceSession()
        let ctx = try await s.call("assistant.context")
        XCTAssertTrue(ctx["system"]?.stringValue?.contains("Commands by category:") ?? false)
        XCTAssertTrue(ctx["context"]?.stringValue?.contains("Selection: none.") ?? false)
        XCTAssertEqual(ctx["toolName"]?.stringValue, "run_commands")
        let a = try await s.call("assistant.assess", obj([("commands", EngineJSON.strings(["LINE 0,0 1000,0 ", "CIRCLE 0,0 300"]))]))
        XCTAssertEqual(a["added"]?.intValue, 2)
        XCTAssertEqual(a["bulk"], .bool(false))
        XCTAssertEqual(s.editor.doc.entities.count, 0, "assessed on a copy")
        let bulk = try await s.call("assistant.assess", obj([("commands", EngineJSON.strings(["LINE 0,0 1000,0 "])), ("bulkLimit", .int(0))]))
        XCTAssertEqual(bulk["bulk"], .bool(true))
        let r = try await s.call("assistant.apply", obj([("commands", EngineJSON.strings(["LINE 0,0 1000,0 "]))]))
        XCTAssertEqual(r["count"]?.intValue, 1)
        XCTAssertEqual(s.editor.doc.entities.count, 1)
        do { _ = try await s.call("assistant.apply", obj([("commands", EngineJSON.strings([]))])); XCTFail("no commands") } catch {}
    }

    @MainActor func testMCPExtraTools() async throws {
        let s = EngineSession()
        let server = EngineMCPServer(session: s, path: nil, write: { _ in })
        let names = server.tools.compactMap { $0["name"]?.stringValue }
        for n in ["run_batch", "cost_estimate", "clash", "sun_position"] { XCTAssertTrue(names.contains(n), n) }
        let sun = try await server.call("sun_position", obj([("datetime", .string("2025-06-21T12:00:00+00:00")), ("latitude", .number(45)), ("longitude", .number(0))]))
        XCTAssertEqual(sun["altitude"]?.doubleValue ?? 0, 68.4, accuracy: 1.0)
        XCTAssertNotNil(sun["sunriseUTC"]?.stringValue)
        let clash = try await server.call("clash", obj([]))
        XCTAssertEqual(clash["count"]?.intValue, 0)
        _ = await s.runLines("WALL 0,0 5000,0 ")
        let cost = try await server.call("cost_estimate", obj([("prices", obj([("currency", .string("EUR")), ("wall:length", .number(100))]))]))
        XCTAssertEqual(cost["currency"]?.stringValue, "EUR")
        XCTAssertGreaterThan(cost["total"]?.doubleValue ?? 0, 0)
        do { _ = try await server.call("cost_estimate", obj([])); XCTFail("no unit rates") } catch {}
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("archi-batch-" + String(ProcessInfo.processInfo.processIdentifier) + ".archi")
        let job = obj([("commands", EngineJSON.strings(["LINE 0,0 1000,0 "])), ("save", .string(out.path))])
        let batch = try await server.call("run_batch", obj([("jobs", .array([job]))]))
        XCTAssertNotNil(batch.fields)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        try? FileManager.default.removeItem(at: out)
    }
}
