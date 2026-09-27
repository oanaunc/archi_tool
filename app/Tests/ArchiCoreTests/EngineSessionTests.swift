// Oanarina Archi Tool — GPL-3.0-or-later
// The archi-engine session (Host/EngineSession.swift) driven directly, without a process: the JSON-RPC methods the
// Windows shell uses, from the handshake to drawing a line, undo, the Cedar House sample, meshes and render presets.
import XCTest
@testable import ArchiCore

final class EngineSessionTests: XCTestCase {
    static var cedarHouse: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../assets/demo/Cedar House.archi").standardized
    }

    func obj(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
        var o = EngineObject()
        for (k, v) in pairs { o.set(k, v) }
        return o.json
    }

    func point(_ x: Double, _ y: Double, snap: Bool = false) -> EngineJSON {
        obj([("x", .number(x)), ("y", .number(y)), ("snap", .bool(snap))])
    }

    /// Strokes of the plan draw list that belong to object `id`.
    func strokes(_ list: EngineJSON, id: Int) -> [EngineJSON] {
        (list["items"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "stroke" && $0["id"]?.intValue == id }
    }

    // MARK: Protocol

    func testJSONRoundTrip() throws {
        let text = #"{"a":[1,2.5,-3e-2,true,false,null],"s":"quote \" slash \\ tab \t nl \n é 🏠 A","o":{}}"#
        let v = try EngineJSON.parse(text)
        XCTAssertEqual(v["a"]?[1]?.doubleValue, 2.5)
        XCTAssertEqual(v["a"]?[2]?.doubleValue, -0.03)
        XCTAssertEqual(v["a"]?[3], .bool(true))
        XCTAssertEqual(v["s"]?.stringValue, "quote \" slash \\ tab \t nl \n é 🏠 A")
        XCTAssertEqual(try EngineJSON.parse(v.serialized), v)
        XCTAssertEqual(EngineJSON.number(3).serialized, "3")
        XCTAssertEqual(EngineJSON.number(0.1 + 0.2).serialized, "0.3")
        XCTAssertEqual(EngineJSON.number(.nan).serialized, "null")
        XCTAssertThrowsError(try EngineJSON.parse("{\"a\":}"))
        XCTAssertEqual(EngineDrawJSON.hex(RGBA(0.961, 0.773, 0.094)), "#f5c518")
    }

    @MainActor func testRequestLinesAndErrors() async throws {
        let s = EngineSession()
        let r = await s.handle(line: #"{"jsonrpc":"2.0","id":7,"method":"doc.info","params":{}}"#)
        let resp = try EngineJSON.parse(XCTUnwrap(r))
        XCTAssertEqual(resp["id"]?.intValue, 7)
        XCTAssertEqual(resp["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(resp["result"]?["units"]?.stringValue, "millimeters")
        let r2 = await s.handle(line: #"{"jsonrpc":"2.0","id":"x","method":"nope"}"#)
        let unknown = try EngineJSON.parse(XCTUnwrap(r2))
        XCTAssertEqual(unknown["error"]?["code"]?.intValue, EngineError.methodNotFound)
        XCTAssertEqual(unknown["id"]?.stringValue, "x")
        let r3 = await s.handle(line: "{not json")
        let bad = try EngineJSON.parse(XCTUnwrap(r3))
        XCTAssertEqual(bad["error"]?["code"]?.intValue, EngineError.parseError)
        let r4 = await s.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"input.point","params":{}}"#)
        let missing = try EngineJSON.parse(XCTUnwrap(r4))
        XCTAssertEqual(missing["error"]?["code"]?.intValue, EngineError.invalidParams)
        // A request without an id is a notification: handled, no response.
        let none = await s.handle(line: #"{"jsonrpc":"2.0","method":"edit.undo","params":{}}"#)
        XCTAssertNil(none)
        let blank = await s.handle(line: "   ")
        XCTAssertNil(blank)
    }

    @MainActor func testHello() async throws {
        let h = try await EngineSession().call("engine.hello")
        XCTAssertEqual(h["name"]?.stringValue, "archi-engine")
        XCTAssertEqual(h["protocol"]?.stringValue, EngineProtocol.version)
        let cmds = h["commands"]?.arrayValue ?? []
        XCTAssertGreaterThan(cmds.count, 500)
        let line = cmds.first { $0["name"]?.stringValue == "LINE" }
        XCTAssertNotNil(line)
        XCTAssertTrue(line?["aliases"]?.arrayValue?.contains(.string("L")) ?? false)
        XCTAssertFalse(line?["category"]?.stringValue?.isEmpty ?? true)
        XCTAssertTrue(h["sysvars"]?.arrayValue?.contains { $0["name"]?.stringValue == "OSMODE" } ?? false)
        for m in ["view.drawList", "model.meshes", "input.cursor", "panel.set"] {
            XCTAssertTrue(h["methods"]?.arrayValue?.contains(.string(m)) ?? false, m)
        }
    }

    // MARK: Drawing a line

    @MainActor func testNewDocumentLineDrawListAndUndo() async throws {
        var notes: [String] = []
        let s = EngineSession(emit: { notes.append($0) })
        let info = try await s.call("doc.new")
        XCTAssertEqual(info["dirty"], .bool(false))
        XCTAssertEqual(info["levels"]?.arrayValue?.count, 2)
        XCTAssertEqual(info["currentLevel"]?.stringValue, "Ground Floor")

        var p = try await s.call("command.run", obj([("line", .string("LINE"))]))
        XCTAssertEqual(p["active"], .bool(true))
        XCTAssertEqual(p["command"]?.stringValue, "LINE")
        XCTAssertEqual(p["kinds"], EngineJSON.strings(["point"]))
        XCTAssertEqual(p["message"]?.stringValue, "Specify first point:")

        p = try await s.call("input.point", point(0, 0))
        XCTAssertEqual(p["base"]?.vec2, Vec2(0, 0))
        XCTAssertEqual(p["message"]?.stringValue, "Specify next point:")
        // The rubber band follows the cursor (as on the Mac canvas).
        p = try await s.call("input.cursor", obj([("x", .number(1000)), ("y", .number(0)), ("pixelsPerUnit", .number(0.1))]))
        XCTAssertEqual(p["cursor"]?.vec2, Vec2(1000, 0))
        let preview = p["preview"]?.arrayValue ?? []
        XCTAssertTrue(preview.contains { $0["type"]?.stringValue == "stroke" && $0["points"]?[1]?.vec2 == Vec2(1000, 0) }, "\(preview)")

        p = try await s.call("input.point", point(1000, 0))
        XCTAssertTrue(p["keywords"]?.arrayValue?.contains(.string("Undo")) ?? false)
        p = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertEqual(p["active"], .bool(false))
        XCTAssertEqual(p["message"]?.stringValue, "Command:")

        XCTAssertEqual(s.editor.doc.entities.count, 1)
        let lineID = try XCTUnwrap(s.editor.doc.entities.first?.id)
        guard case .line(let g) = s.editor.doc.entities[0].geometry else { return XCTFail("not a line") }
        XCTAssertEqual(g.a, Vec2(0, 0)); XCTAssertEqual(g.b, Vec2(1000, 0))

        let list = try await s.call("view.drawList", obj([("rect", .numbers([-100, -100, 1100, 100])), ("pixelsPerUnit", .number(0.5))]))
        let st = strokes(list, id: lineID)
        XCTAssertEqual(st.count, 1)
        XCTAssertEqual(st.first?["points"]?[0]?.vec2, Vec2(0, 0))
        XCTAssertEqual(st.first?["points"]?[1]?.vec2, Vec2(1000, 0))
        XCTAssertTrue(st.first?["style"]?["color"]?.stringValue?.hasPrefix("#") ?? false)
        // Outside the requested rectangle nothing is sent.
        let away = try await s.call("view.drawList", obj([("rect", .numbers([50000, 50000, 60000, 60000]))]))
        XCTAssertTrue(strokes(away, id: lineID).isEmpty)

        let hist = try await s.call("edit.undo")
        XCTAssertEqual(hist["redo"], EngineJSON.strings(["LINE"]))
        XCTAssertTrue(s.editor.doc.entities.isEmpty)
        let afterUndo = try await s.call("view.drawList", obj([]))
        XCTAssertTrue(strokes(afterUndo, id: lineID).isEmpty)
        _ = try await s.call("edit.redo")
        XCTAssertEqual(s.editor.doc.entities.count, 1)

        s.flushNotifications()
        let methods = notes.compactMap { (try? EngineJSON.parse($0))?["method"]?.stringValue }
        XCTAssertTrue(methods.contains("log"))
        XCTAssertTrue(methods.contains("changed"))
        XCTAssertTrue(notes.contains { $0.contains("Command: LINE") })
    }

    /// The Windows shell's File ▸ New from Template sends the built-in names, not file paths.
    @MainActor func testBuiltInTemplates() async throws {
        let s = EngineSession()
        let metric = try await s.call("doc.new", obj([("template", .string("metric"))]))
        XCTAssertEqual(metric["units"]?.stringValue, "millimeters")
        let imperial = try await s.call("doc.new", obj([("template", .string("imperial"))]))
        XCTAssertEqual(imperial["units"]?.stringValue, "inches")
        let building = try await s.call("doc.new", obj([("template", .string("building"))]))
        XCTAssertEqual(building["levels"]?.arrayValue?.count, 3)
        XCTAssertEqual(building["layouts"]?.arrayValue?.count, 3)
    }

    @MainActor func testTypedCoordinatesAndKeys() async throws {
        let s = EngineSession()
        _ = try await s.call("command.run", obj([("line", .string("LINE 0,0 2000,0"))]))
        var p = try await s.call("input.text", obj([("text", .string("@0,1000"))]))
        XCTAssertEqual(p["active"], .bool(true))
        p = try await s.call("input.key", obj([("key", .string("Escape"))]))
        XCTAssertEqual(p["active"], .bool(false))
        XCTAssertEqual(s.editor.doc.entities.count, 2)
        // Up recalls the last line typed; Tab completes command names.
        let up = try await s.call("input.key", obj([("key", .string("Up"))]))
        XCTAssertEqual(up["text"]?.stringValue, "@0,1000")
        let tab = try await s.call("input.key", obj([("key", .string("Tab")), ("text", .string("CIRC"))]))
        XCTAssertEqual(tab["text"]?.stringValue, "CIRCLE")
        // Enter at the idle prompt repeats the last command, as on the Mac command line.
        p = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertEqual(p["command"]?.stringValue, "LINE")
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
    }

    @MainActor func testSelectionPickGripsAndErase() async throws {
        let s = EngineSession()
        _ = try await s.call("command.run", obj([("line", .string("LINE 0,0 1000,0 ;"))]))
        XCTAssertTrue(s.editor.isIdle, "\";\" ends LINE")
        let id = try XCTUnwrap(s.editor.doc.entities.first?.id)
        var sel = try await s.call("select.window", obj([("x0", .number(-10)), ("y0", .number(-10)), ("x1", .number(1010)), ("y1", .number(10))]))
        XCTAssertEqual(sel["ids"], EngineJSON.ints([id]))
        XCTAssertEqual(sel["summary"]?.stringValue, "1 object: line")
        let grips = try await s.call("grips.get")
        XCTAssertGreaterThanOrEqual(grips.arrayValue?.count ?? 0, 2)
        XCTAssertEqual(grips[0]?["id"]?.intValue, id)
        let drag = try await s.call("grips.drag", obj([("id", .int(id)), ("index", .int(0)), ("x", .number(-500)), ("y", .number(0)), ("snap", .bool(false))]))
        XCTAssertEqual(drag["changed"], EngineJSON.ints([id]))
        guard case .line(let g) = s.editor.doc.entities[0].geometry else { return XCTFail("not a line") }
        XCTAssertEqual(g.a, Vec2(-500, 0))
        // Properties of the selection.
        let props = try await s.call("panel.properties")
        XCTAssertFalse(props["rows"]?.arrayValue?.isEmpty ?? true)
        sel = try await s.call("select.set", obj([("ids", .array([]))]))
        XCTAssertEqual(sel["ids"], .array([]))
        // ERASE: the selection prompt takes a pick, Enter ends it.
        var p = try await s.call("command.run", obj([("line", .string("ERASE"))]))
        XCTAssertTrue(p["kinds"]?.arrayValue?.contains(.string("selection")) ?? false)
        sel = try await s.call("pick", obj([("x", .number(0)), ("y", .number(1)), ("tolerance", .number(5))]))
        XCTAssertEqual(sel["hit"]?.intValue, id)
        p = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertEqual(p["active"], .bool(false))
        XCTAssertTrue(s.editor.doc.entities.isEmpty)
    }

    // MARK: Panels, variables, files

    @MainActor func testPanelsAndVariables() async throws {
        let s = EngineSession()
        let layers = try await s.call("panel.layers")
        XCTAssertTrue(layers["layers"]?.arrayValue?.contains { $0["name"]?.stringValue == "A-WALL" } ?? false)
        let after = try await s.call("panel.set", obj([("panel", .string("layers")), ("key", .string("new")), ("value", .string("X-TEST"))]))
        XCTAssertTrue(after["layers"]?.arrayValue?.contains { $0["name"]?.stringValue == "X-TEST" } ?? false)
        _ = try await s.call("panel.set", obj([("panel", .string("layers")), ("key", .string("X-TEST.visible")), ("value", .bool(false))]))
        XCTAssertEqual(s.editor.doc.layer(named: "X-TEST")?.visible, false)
        let levels = try await s.call("panel.set", obj([("panel", .string("levels")), ("key", .string("current")), ("value", .string("First Floor"))]))
        XCTAssertEqual(levels["currentId"]?.intValue, 1)
        XCTAssertEqual(s.editor.doc.currentLevel, 1)
        let mats = try await s.call("panel.materials")
        XCTAssertTrue(mats["materials"]?.arrayValue?.contains { $0["name"]?.stringValue == "Concrete" } ?? false)
        let sheets = try await s.call("panel.sheets")
        XCTAssertEqual(sheets["sheets"]?.arrayValue?.count, 1)
        let hist = try await s.call("panel.history")
        XCTAssertEqual(hist["undo"]?.arrayValue?.count, 3)
        let proj = try await s.call("panel.set", obj([("panel", .string("properties")), ("key", .string("project.name")), ("value", .string("Engine Test"))]))
        XCTAssertEqual(proj["project"]?["name"]?.stringValue, "Engine Test")

        let v = try await s.call("sysvar.set", obj([("name", .string("ORTHOMODE")), ("value", .string("1"))]))
        XCTAssertEqual(v["value"]?.stringValue, "1")
        XCTAssertTrue(s.editor.settings.ortho)
    }

    @MainActor func testSaveAndOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = EngineSession()
        s.baseDirectory = dir
        _ = try await s.call("command.run", obj([("line", .string("CIRCLE 0,0 500"))]))
        let saved = try await s.call("doc.save", obj([("path", .string("round.archi"))]))
        XCTAssertEqual(saved["dirty"], .bool(false))
        XCTAssertEqual(saved["title"]?.stringValue, "round")
        let exported = try await s.call("file.export", obj([("path", .string("round.dxf"))]))
        XCTAssertGreaterThan(exported["bytes"]?.intValue ?? 0, 100)
        let t = EngineSession()
        let info = try await t.call("doc.open", obj([("path", .string(dir.appendingPathComponent("round.archi").path))]))
        XCTAssertEqual(info["entities"]?.intValue, 1)
        let fresh = EngineSession()
        XCTAssertThrowsError(try fresh.saveDocument(.object([])), "a new document needs a path")
        do { _ = try await t.call("doc.open", obj([("path", .string("/no/such/file.archi"))])); XCTFail("opened a missing file") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.engineFailure) }
    }

    // MARK: Cedar House, meshes and lighting

    @MainActor func testCedarHouseSampleMeshesAndDrawList() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let s = EngineSession()
        let info = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        XCTAssertEqual(info["title"]?.stringValue, "Cedar House")
        XCTAssertGreaterThanOrEqual(info["levels"]?.arrayValue?.count ?? 0, 2)
        XCTAssertEqual(info["empty"], .bool(false))
        let ext = try XCTUnwrap(info["extents"])
        let list = try await s.call("view.drawList", obj([("rect", ext), ("pixelsPerUnit", .number(0.05))]))
        let items = list["items"]?.arrayValue ?? []
        XCTAssertGreaterThan(items.count, 100)
        XCTAssertTrue(items.contains { $0["type"]?.stringValue == "fill" })
        XCTAssertTrue(items.contains { $0["type"]?.stringValue == "text" && !($0["text"]?["content"]?.stringValue ?? "").isEmpty })

        let lvl = s.editor.doc.currentLevel
        let m = try await s.call("model.meshes", obj([("level", .int(lvl))]))
        let meshes = m["meshes"]?.arrayValue ?? []
        XCTAssertFalse(meshes.isEmpty)
        XCTAssertTrue(meshes.contains { $0["kind"]?.stringValue == "wall" })
        let first = try XCTUnwrap(meshes.first)
        let pos = EngineMeshJSON.decodeFloats(first["positions"]?.stringValue ?? "")
        XCTAssertEqual(pos.count, (first["vertexCount"]?.intValue ?? -1) * 3)
        XCTAssertEqual(EngineMeshJSON.decodeFloats(first["normals"]?.stringValue ?? "").count, pos.count)
        XCTAssertTrue(first["color"]?.stringValue?.hasPrefix("#") ?? false)
        XCTAssertNotNil(m["sun"]?["direction"])
        XCTAssertNotNil(m["bounds"]?[1])
        // Binary transfer: the same buffers in one file, described by offsets.
        let bin = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: bin) }
        let mb = try await s.call("model.meshes", obj([("level", .int(lvl)), ("binary", .string(bin.path))]))
        XCTAssertEqual(mb["meshes"]?.arrayValue?.count, meshes.count)
        XCTAssertEqual(mb["meshes"]?[0]?["positions"]?["length"]?.intValue, pos.count * 4)
        XCTAssertEqual(try Data(contentsOf: bin).count, mb["binaryLength"]?.intValue)

        // Sheets: paper millimetres with viewport clips.
        if let sheet = s.editor.doc.layouts.first(where: { !$0.viewports.isEmpty }) {
            let sl = try await s.call("view.drawList", obj([("layout", .string(sheet.name))]))
            XCTAssertEqual(sl["paper"]?["width"]?.doubleValue, sheet.paper.width)
            XCTAssertEqual(sl["viewports"]?.arrayValue?.count, sheet.viewports.filter { $0.size.x > 0 && $0.scale > 0 }.count)
        }
    }

    @MainActor func testRenderPresetsMirrorTheMac() async throws {
        let s = EngineSession()
        var r = try await s.call("render.settings")
        XCTAssertEqual(r["preset"]?.stringValue, "Daylight")
        XCTAssertEqual(r["sunAltitude"]?.doubleValue, 46)
        XCTAssertEqual(r["sunAzimuth"]?.doubleValue, 222)
        XCTAssertEqual(r["exposure"]?.doubleValue, 0.6)
        r = try await s.call("render.preset", obj([("name", .string("Goldenhour"))]))
        XCTAssertEqual(r["preset"]?.stringValue, "Golden hour")
        XCTAssertEqual(r["sunAltitude"]?.doubleValue, 11)
        XCTAssertEqual(r["sunAzimuth"]?.doubleValue, 228)
        XCTAssertEqual(r["exposure"]?.doubleValue, 0.75)
        XCTAssertEqual(r["bloom"]?.doubleValue, 0.22)
        XCTAssertEqual(r["sunColor"], EngineJSON.numbers([1.0, 0.66, 0.38]))
        XCTAssertEqual(s.editor.doc.variable("RENDERPRESET"), "Golden hour")
        r = try await s.call("render.preset", obj([("name", .string("night"))]))
        XCTAssertEqual(r["windowGlow"]?.doubleValue, 1.6)
        XCTAssertEqual(r["lampGlow"]?.doubleValue, 3)
        XCTAssertEqual(r["sky"]?.stringValue, "night")
        r = try await s.call("render.preset", obj([("name", .string("Overcast"))]))
        XCTAssertEqual(r["shadowRadius"]?.doubleValue, 22)
        XCTAssertEqual(r["envIntensity"]?.doubleValue, 1.55)
        // Each preset change is an undo step, like the RENDERPRESET command.
        _ = try await s.call("edit.undo")
        XCTAssertEqual(s.editor.doc.variable("RENDERPRESET"), "Night")
        do { _ = try await s.call("render.preset", obj([("name", .string("Disco"))])); XCTFail("accepted an unknown preset") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
        // The sun direction points up and towards the azimuth (X east, Y north).
        let d = try XCTUnwrap(r["sunDirection"]?.arrayValue?.compactMap(\.doubleValue))
        XCTAssertGreaterThan(d[2], 0)
    }

    @MainActor func testPortableRenderPresetCommand() async throws {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        let ed = Editor(registry: reg)
        let s = EngineSession(editor: ed)
        if reg.lookup("RENDERPRESET")?.category != "View" { return XCTFail("RENDERPRESET not registered") }
        _ = try await s.call("command.run", obj([("line", .string("RENDERPRESET Overcast"))]))
        XCTAssertEqual(ed.doc.variable("RENDERPRESET"), "Overcast")
        let settings = try await s.call("render.settings")
        XCTAssertEqual(settings["preset"]?.stringValue, "Overcast")
    }
}
