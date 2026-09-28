// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine APPSELFTEST, HELPWINDOW, VRVIEW, SPACEMOUSE and SPELL with the Windows spell checker's verdicts
// (Host/EngineSystemCommands.swift).
import XCTest
@testable import ArchiCore

extension EngineSessionTests {
    @MainActor func testSystemSelfTestCommand() async throws {
        let (s, sink) = workspaceSession()
        XCTAssertEqual(s.editor.registry.lookup("SELFTEST")?.name, "APPSELFTEST")
        let r = try await s.call("selftest.run")
        XCTAssertEqual(r["failures"]?.arrayValue?.count, 0, r["failures"]?.serialized ?? "")
        XCTAssertGreaterThan(r["passed"]?.intValue ?? 0, 30)
        // Headless: the engine prints the Mac report.
        EngineSession.uiPreferences["selfTest.shell"] = nil
        try await wsRun(s, "APPSELFTEST")
        XCTAssertTrue(s.editor.log.contains { $0.hasSuffix("check(s) passed, 0 failed.") }, s.editor.log.suffix(3).joined(separator: " | "))
        // With the Windows shell: the results go to the shell, which prints the report.
        _ = try await s.call("ui.prefs", obj([("values", obj([("selfTest.shell", .string("1"))]))]))
        try await wsRun(s, "SELFTEST")
        let h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "selfTest")
        XCTAssertEqual(h?["failures"]?.arrayValue?.count, 0)
        EngineSession.uiPreferences["selfTest.shell"] = nil
    }

    @MainActor func testSystemHelpWindow() async throws {
        let (s, sink) = workspaceSession()
        XCTAssertEqual(s.editor.registry.lookup("MANUAL")?.name, "HELPWINDOW")
        try await wsRun(s, "HELPWINDOW")
        XCTAssertEqual(hosts(s, sink).last?["route"]?.stringValue, "index")
        try await wsRun(s, "DOCS l")
        XCTAssertEqual(hosts(s, sink).last?["route"]?.stringValue, "cmd/LINE")
        try await wsRun(s, "HELPBROWSER shortcuts")
        let h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "helpBrowser")
        XCTAssertEqual(h?["route"]?.stringValue, "shortcuts")
        try await wsRun(s, "HELPWINDOW NOPE_NOT_A_CMD")
        XCTAssertTrue(s.editor.log.contains { $0.contains("Unknown command \"NOPE_NOT_A_CMD\".") })
    }

    @MainActor func testSystemVRView() async throws {
        let (s, sink) = workspaceSession()
        XCTAssertEqual(s.editor.registry.lookup("WEBXR")?.name, "VRVIEW")
        try await wsRun(s, "VRVIEW")
        XCTAssertTrue(s.editor.log.contains("The model has no 3D content."))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-vr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await s.call("doc.save", obj([("path", .string(dir.appendingPathComponent("Box.archi").path))]))
        try await wsRun(s, "BOX 0,0 1000,1000 1000")
        try await wsRun(s, "VRVIEW Open")
        let page = dir.appendingPathComponent("Box-VR.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: page.path), s.editor.log.suffix(4).joined(separator: " | "))
        let h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "vrView")
        XCTAssertEqual(h?["mode"]?.stringValue, "Open")
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("VR page: ") && $0.contains("Box-VR.html") })
        let html = try String(contentsOf: page, encoding: .utf8)
        XCTAssertTrue(html.contains("immersive-vr"))
    }

    @MainActor func testSystemSpaceMouse() async throws {
        let (s, sink) = workspaceSession()
        for k in ["spaceMouse.enabled", "spaceMouse.mode", "spaceMouse.sensitivity", "spaceMouse.available", "spaceMouse.devices"] { EngineSession.uiPreferences[k] = nil }
        XCTAssertEqual(s.editor.registry.lookup("3DMOUSE")?.name, "SPACEMOUSE")
        try await wsRun(s, "SPACEMOUSE")
        XCTAssertEqual(s.editor.log.last, "SpaceMouse off, Object mode, sensitivity 1; devices: none connected.")
        _ = try await s.call("ui.prefs", obj([("values", obj([("spaceMouse.available", .string("1")), ("spaceMouse.devices", .string("SpaceMouse Compact"))]))]))
        try await wsRun(s, "SPACEMOUSE Fly")
        XCTAssertEqual(s.editor.log.last, "SpaceMouse on, Fly mode, sensitivity 1; devices: SpaceMouse Compact.")
        var h = hosts(s, sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "spaceMouse")
        XCTAssertEqual(h?["mode"]?.stringValue, "Fly")
        try await wsRun(s, "SPACEMOUSE Sensitivity 20")
        XCTAssertEqual(EngineSession.uiPreferences["spaceMouse.sensitivity"], "10")
        try await wsRun(s, "SPACEMOUSE Off")
        h = hosts(s, sink).last
        XCTAssertEqual(h?["enabled"]?.boolValue, false)
        XCTAssertTrue(s.editor.log.last?.hasPrefix("SpaceMouse off, Fly mode, sensitivity 10") == true)
        for k in ["spaceMouse.enabled", "spaceMouse.mode", "spaceMouse.sensitivity", "spaceMouse.available", "spaceMouse.devices"] { EngineSession.uiPreferences[k] = nil }
    }

    @MainActor func testSystemSpellWithVerdicts() async throws {
        let (s, _) = workspaceSession()
        let oldChecker = SpellCheck.checker, oldSuggester = SpellCheck.suggester
        defer { SpellCheck.checker = oldChecker; SpellCheck.suggester = oldSuggester }
        let id = s.editor.doc.add(.text(TextGeom(position: .zero, height: 250, content: "Kitchn wall")))
        let bad = obj([("Kitchn", EngineJSON.strings(["Kitchen", "Kitchens"]))])
        let r = try await s.call("spell.verdicts", obj([("misspelled", bad)]))
        XCTAssertEqual(r["misspelled"]?.intValue, 1)
        _ = try await s.call("command.run", obj([("line", .string("SPELL"))]))
        _ = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Not in dictionary: \"Kitchn\"") && $0.contains("Kitchen, Kitchens") }, s.editor.log.suffix(3).joined(separator: " | "))
        _ = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertTrue(s.editor.log.contains("Spelling check complete (1 change(s))."), s.editor.log.suffix(3).joined(separator: " | "))
        if case .text(let t)? = s.editor.doc.entity(id)?.geometry { XCTAssertEqual(t.content, "Kitchen wall") } else { XCTFail("text") }
    }
}
