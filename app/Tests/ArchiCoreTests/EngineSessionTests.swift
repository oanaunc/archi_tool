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

    /// render.preset behaves like the Mac RENDERPRESET command: the drawing is changed and the 3D view shows Realistic.
    @MainActor func testRenderPresetSwitchesTheViewToRealistic() async throws {
        let (s, sink) = dialogSession()
        _ = try await s.call("view3d.setVariable", obj([("name", .string("VSCURRENT")), ("value", .string("Shaded with Edges"))]))
        XCTAssertFalse(s.editor.isDirty)
        _ = try await s.call("render.preset", obj([("name", .string("Goldenhour"))]))
        XCTAssertTrue(s.editor.isDirty)
        s.flushNotifications()
        let h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "setViewStyle")
        XCTAssertEqual(h?["style"]?.stringValue, "Realistic")
        let info = try await s.call("view3d.info")
        XCTAssertEqual(info["visualStyle"]?.stringValue, "Realistic")
        XCTAssertEqual(info["renderPreset"]?.stringValue, "Golden hour")
        _ = try await s.call("command.run", obj([("line", .string("RENDERPRESET Off"))]))
        XCTAssertNil(s.editor.doc.variable("RENDERPRESET"))
        s.flushNotifications()
        XCTAssertEqual(hostActions(sink).last?["style"]?.stringValue, "Realistic")
    }
}

// MARK: - Scripting, agents and the Windows dialogs (EngineScripting.swift, EngineDialogs.swift, EngineMCP.swift)

extension EngineSessionTests {
    @MainActor func script(_ s: EngineSession, _ fn: String, _ args: [EngineJSON] = []) async throws -> EngineJSON {
        try await s.call("script.call", obj([("fn", .string(fn)), ("args", .array(args))]))
    }

    @MainActor func testScriptCallArchiAPI() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let line = try await script(s, "add", [try EngineJSON.parse(#"{"type":"line","a":[0,0],"b":[1000,0],"color":"red"}"#)])
        let id = try XCTUnwrap(line.intValue)
        let got = try await script(s, "get", [.int(id)])
        XCTAssertEqual(got["geometry"]?["b"]?["x"]?.doubleValue, 1000)
        let moved = try await script(s, "update", [.int(id), try EngineJSON.parse(#"{"b":[2000,500],"layer":"NOTES"}"#)])
        XCTAssertEqual(moved["layer"]?.stringValue, "NOTES")
        guard case .line(let g) = try XCTUnwrap(s.editor.doc.entity(id)).geometry else { return XCTFail("not a line") }
        XCTAssertEqual(g.b, Vec2(2000, 500))
        let lines = try await script(s, "entities", [obj([("type", .string("line"))])])
        XCTAssertEqual(lines.arrayValue?.count, 1)
        // Building helpers: wall, door, window, slab, room, column (each one undo step with the Mac label).
        let wallJSON = try await script(s, "wall", [.number(0), .number(0), .number(6000), .number(0), obj([("thickness", .number(250))])])
        let wall = try XCTUnwrap(wallJSON.intValue)
        let door = try await script(s, "door", [.int(wall), .number(1500), obj([("width", .number(900))])])
        XCTAssertNotNil(door.intValue)
        do { _ = try await script(s, "window", [.int(wall), .number(5900)]); XCTFail("an opening past the wall end was accepted") }
        catch let e as EngineError { XCTAssertTrue(e.message.contains("does not fit"), e.message) }
        _ = try await script(s, "slab", [try EngineJSON.parse("[[0,0],[6000,0],[6000,4000],[0,4000]]")])
        _ = try await script(s, "room", [try EngineJSON.parse("[[0,0],[6000,0],[6000,4000],[0,4000]]"), .string("Office")])
        _ = try await script(s, "column", [.number(0), .number(0), obj([("size", .number(400))])])
        XCTAssertEqual(s.editor.history.undoLabel, "Script Column")
        let walls = try await script(s, "elements", [obj([("type", .string("wall"))])])
        XCTAssertEqual(walls.arrayValue?.count, 1)
        let summary = try await script(s, "summary")
        XCTAssertEqual(summary["elementCount"]?.intValue, 5)
        XCTAssertEqual(summary["entitiesByType"]?["line"]?.intValue, 1)
        // Selection, variables, command lines.
        _ = try await script(s, "select", [.array([.int(id), .int(99999)])])
        let sel = try await script(s, "selection")
        XCTAssertEqual(sel, EngineJSON.ints([id]))
        _ = try await script(s, "setVar", [.string("ltscale"), .string("2")])
        let lt = try await script(s, "getVar", [.string("LTSCALE")])
        XCTAssertEqual(lt.stringValue, "2")
        let log = try await script(s, "run", [.string("CIRCLE 0,0 500")])
        XCTAssertFalse(log.arrayValue?.isEmpty ?? true)
        XCTAssertTrue(s.editor.doc.entities.contains { $0.typeName == "circle" })
        let removed = try await script(s, "remove", [.array([.int(id)])])
        XCTAssertEqual(removed.intValue, 1)
        XCTAssertNil(s.editor.doc.entity(id))
        _ = try await script(s, "undo")
        XCTAssertNotNil(s.editor.doc.entity(id))
        let cmds = try await script(s, "commands")
        XCTAssertGreaterThan(cmds.arrayValue?.count ?? 0, 500)
        // Graphs from scripts.
        let sample = ScriptJSON.encode(NodeGraph.sample)
        let ev = try await script(s, "evaluateGraph", [sample])
        XCTAssertEqual(ev["objects"]?.intValue, 6)
        let baked = try await script(s, "bakeGraph", [sample])
        XCTAssertEqual(baked.arrayValue?.count, 6)
        do { _ = try await script(s, "noSuchFunction"); XCTFail("unknown function accepted") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.methodNotFound) }
    }

    @MainActor func testAgentCallMethods() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        func agent(_ m: String, _ params: EngineJSON = .object([])) async throws -> EngineJSON {
            try await s.call("agent.call", obj([("method", .string(m)), ("params", params)]))
        }
        let methods = try await agent("list_methods")
        XCTAssertTrue(methods.arrayValue?.contains { $0["name"]?.stringValue == "eval_js" } ?? false)
        let r = try await agent("run_command", obj([("command", .string("LINE 0,0 1000,0 "))]))
        XCTAssertFalse(r["log"]?.arrayValue?.isEmpty ?? true)
        XCTAssertEqual(s.editor.doc.entities.count, 1)
        let add = try await agent("add_element", obj([("element", try EngineJSON.parse(#"{"type":"wall","start":[0,0],"end":[5000,0]}"#))]))
        let wall = try XCTUnwrap(add["ids"]?[0]?.intValue)
        let upd = try await agent("update_entity", obj([("id", .int(wall)), ("patch", try EngineJSON.parse(#"{"height":2500}"#))]))
        XCTAssertEqual(upd["geometry"]?["height"]?.doubleValue, 2500)
        XCTAssertEqual(s.editor.history.undoLabel, "Agent Update")
        let summary = try await agent("get_document_summary")
        XCTAssertEqual(summary["elementCount"]?.intValue, 1)
        let tools = try await agent("list_tools")
        XCTAssertGreaterThan(tools.arrayValue?.count ?? 0, 5)
        let del = try await agent("delete", obj([("ids", EngineJSON.ints([wall]))]))
        XCTAssertEqual(del["deleted"]?.intValue, 1)
        let resources = try await agent("list_resources")
        XCTAssertFalse(resources.arrayValue?.isEmpty ?? true)
        do { _ = try await agent("eval_js", obj([("code", .string("1"))])); XCTFail("eval_js must be answered by the shell") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.methodNotFound) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("agent-export-\(UUID().uuidString).dxf")
        let ex = try await agent("export", obj([("format", .string("dxf")), ("path", .string(tmp.path))]))
        XCTAssertEqual(ex["path"]?.stringValue, tmp.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        try? FileManager.default.removeItem(at: tmp)
    }

    @MainActor func testNodeGraphMethods() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let sample = ScriptJSON.encode(NodeGraph.sample)
        let ev = try await s.call("graph.evaluate", obj([("graph", sample), ("preview", .string("plan")), ("kinds", .bool(true))]))
        XCTAssertEqual(ev["objects"]?.intValue, 6)
        XCTAssertEqual(ev["outputNodes"], EngineJSON.ints([4]))
        XCTAssertEqual(ev["nodes"]?["4"]?["summary"]?.stringValue, "6 objects")
        XCTAssertFalse(ev["items"]?.arrayValue?.isEmpty ?? true)
        XCTAssertEqual(ev["kinds"]?.arrayValue?.count, NodeKind.allCases.count)
        let ev3 = try await s.call("graph.evaluate", obj([("graph", sample), ("preview", .string("3D"))]))
        XCTAssertFalse(ev3["meshes"]?.arrayValue?.isEmpty ?? true)
        let bake = try await s.call("graph.bake", obj([("graph", sample)]))
        XCTAssertEqual(bake["ids"]?.arrayValue?.count, 6)
        XCTAssertEqual(s.editor.history.undoLabel, "Node Graph")
        XCTAssertEqual(NodeGraph.load(s.editor.doc), NodeGraph.sample)
        // Baking again replaces the previous output.
        _ = try await s.call("graph.bake", obj([("graph", sample)]))
        XCTAssertEqual(NodeGraphBake.bakedCount(s.editor.doc), 6)
        let saved = try await s.call("graph.save", obj([("graph", sample), ("name", .string("Columns"))]))
        XCTAssertEqual(saved["names"], EngineJSON.strings(["Columns"]))
        let loaded = try await s.call("graph.load", obj([("name", .string("Columns"))]))
        // Objects compare by key order, so compare the decoded graphs.
        XCTAssertEqual(try ScriptJSON.decode(NodeGraph.self, from: loaded), NodeGraph.sample)
        let js = try await s.call("graph.script", obj([("graph", sample), ("name", .string("cols"))]))
        XCTAssertTrue(js.stringValue?.contains("archi.bakeGraph(graph)") ?? false)
        let del = try await s.call("graph.delete", obj([("name", .string("Columns"))]))
        XCTAssertEqual(del["names"], EngineJSON.strings([]))
        // A graph with a bad link reports the node error.
        var bad = NodeGraph()
        _ = bad.add(.range, x: 0, y: 0)
        bad.nodes[0].params = ["count": 0]
        let evBad = try await s.call("graph.evaluate", obj([("graph", ScriptJSON.encode(bad))]))
        XCTAssertEqual(evBad["nodes"]?["1"]?["error"]?.stringValue, "Count must be at least 1.")
    }

    @MainActor func testSheetSetAndTitleBlockMethods() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let n0 = s.editor.doc.layouts.count
        var r = try await s.call("sheetset.edit", obj([("op", .string("new")), ("paper", .string("A1"))]))
        XCTAssertEqual(s.editor.doc.layouts.count, n0 + 1)
        XCTAssertEqual(s.editor.doc.layouts.last?.paper.name, "A1")
        XCTAssertEqual(s.editor.history.undoLabel, "New Sheet")
        r = try await s.call("sheetset.edit", obj([("op", .string("renumber")), ("prefix", .string("S-")), ("start", .int(1))]))
        XCTAssertEqual(r["sheets"]?["sheets"]?[0]?["number"]?.stringValue, "S-001")
        _ = try await s.call("sheetset.edit", obj([("op", .string("addRevision")), ("index", .int(0)), ("description", .string("Issued")), ("by", .string("OR"))]))
        _ = try await s.call("sheetset.edit", obj([("op", .string("addRevision")), ("index", .int(0)), ("description", .string("Planning")), ("by", .string(""))]))
        let get = try await s.call("sheetset.get")
        let revs = get["sheets"]?[0]?["revisions"]?.arrayValue ?? []
        XCTAssertEqual(revs.map { $0["code"]?.stringValue ?? "" }, ["A", "B"])
        XCTAssertEqual(s.editor.doc.layouts[0].titleBlock["revision"], "B")
        _ = try await s.call("sheetset.edit", obj([("op", .string("index")), ("index", .int(0))]))
        XCTAssertTrue(s.editor.doc.layouts[0].entities.contains { $0.props["sheetIndex"] != nil })
        _ = try await s.call("sheetset.edit", obj([("op", .string("duplicate")), ("index", .int(0))]))
        XCTAssertTrue(s.editor.doc.layouts[1].name.hasSuffix("(2)"))
        XCTAssertTrue(EngineSheets.revisions(s.editor.doc.layouts[1]).isEmpty)
        _ = try await s.call("sheetset.edit", obj([("op", .string("move")), ("index", .int(1)), ("to", .int(0))]))
        XCTAssertTrue(s.editor.doc.layouts[0].name.hasSuffix("(2)"))
        _ = try await s.call("sheetset.edit", obj([("op", .string("rename")), ("index", .int(0)), ("name", .string("Plans"))]))
        XCTAssertEqual(s.editor.doc.layouts[0].name, "Plans")
        _ = try await s.call("sheetset.edit", obj([("op", .string("deleteRevision")), ("index", .int(1)), ("revision", .int(0))]))
        XCTAssertEqual(EngineSheets.revisions(s.editor.doc.layouts[1]).map(\.code), ["B"])
        XCTAssertEqual(EngineSheets.nextCode(after: "Z"), "AA")
        XCTAssertEqual(EngineSheets.nextCode(after: "P09"), "P10")
        // Title block dialog.
        let tb = try await s.call("titleblock.apply", obj([("layout", .int(0)), ("info", obj([("name", .string("Cedar House")), ("client", .string("Oana"))])),
                                                          ("projectCustom", obj([("PHASE", .string("Design"))])), ("sheetCustom", obj([("PHASE", .string("Tender"))])),
                                                          ("fields", obj([("scale", .string("1:50")), ("sheetName", .string(""))])), ("applyToAll", EngineJSON.strings(["scale"]))]))
        XCTAssertEqual(s.editor.history.undoLabel, "Title Block")
        XCTAssertEqual(s.editor.doc.info.name, "Cedar House")
        XCTAssertEqual(s.editor.doc.variables["PROJFIELD:PHASE"], "Design")
        XCTAssertEqual(s.editor.doc.layouts[0].titleBlock["custom:PHASE"], "Tender")
        XCTAssertEqual(s.editor.doc.layouts[1].titleBlock["scale"], "1:50")
        XCTAssertNil(s.editor.doc.layouts[0].titleBlock["sheetName"])
        XCTAssertEqual(tb["defaults"]?["project"]?.stringValue, "Cedar House")
        XCTAssertEqual(tb["projectCustom"]?["PHASE"]?.stringValue, "Design")
    }

    @MainActor func testMaterialEditsAndDocVariables() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let m = ScriptJSON.encode(Material(name: "Oak", color: RGBA(0.7, 0.55, 0.36), roughness: 0.55))
        var r = try await s.call("doc.edit", obj([("label", .string("Add Material")), ("ops", .array([obj([("op", .string("addMaterial")), ("material", m)])]))]))
        XCTAssertEqual(r["messages"], EngineJSON.strings(["Added Oak."]))
        XCTAssertNotNil(s.editor.doc.material("Oak"))
        let wall = s.editor.doc.addElementForTest()
        s.editor.selection = [wall]
        r = try await s.call("doc.edit", obj([("label", .string("Assign Material")), ("ops", .array([obj([("op", .string("assignMaterial")), ("name", .string("Oak")), ("ids", EngineJSON.ints([wall]))])]))]))
        XCTAssertEqual(s.editor.doc.element(wall)?.material, "Oak")
        // Slider drags merge into one undo step.
        let undoCount = s.editor.history.undoCountForTest
        for v in [0.2, 0.3, 0.4] {
            var mm = try XCTUnwrap(s.editor.doc.material("Oak"))
            mm.roughness = v
            _ = try await s.call("doc.edit", obj([("label", .string("Material Roughness")), ("merge", .bool(true)),
                                                  ("ops", .array([obj([("op", .string("setMaterial")), ("name", .string("Oak")), ("material", ScriptJSON.encode(mm))])]))]))
        }
        XCTAssertEqual(s.editor.history.undoCountForTest, undoCount + 1)
        XCTAssertEqual(s.editor.doc.material("Oak")?.roughness, 0.4)
        _ = try await s.call("doc.edit", obj([("label", .string("Material Asset")), ("ops", .array([obj([("op", .string("setVariable")), ("name", .string("MATASSET:OAK")), ("value", .string("{\"mark\":\"W1\"}"))])]))]))
        _ = try await s.call("doc.edit", obj([("label", .string("Rename Material")), ("ops", .array([obj([("op", .string("renameMaterial")), ("from", .string("Oak")), ("to", .string("White Oak"))])]))]))
        XCTAssertEqual(s.editor.doc.element(wall)?.material, "White Oak")
        XCTAssertEqual(s.editor.doc.variables["MATASSET:WHITE OAK"], "{\"mark\":\"W1\"}")
        let list = try await s.call("material.list")
        let oak = list["materials"]?.arrayValue?.first { $0["material"]?["name"]?.stringValue == "White Oak" }
        XCTAssertEqual(oak?["uses"]?.intValue, 1)
        XCTAssertTrue(list["patterns"]?.arrayValue?.contains(.string("ANSI31")) ?? false)
        let vars = try await s.call("doc.variables", obj([("prefix", .string("MATASSET:"))]))
        XCTAssertEqual(vars.fields?.count, 1)
        do { _ = try await s.call("doc.edit", obj([("label", .string("x")), ("ops", .array([obj([("op", .string("explode"))])]))])); XCTFail("unknown op") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
    }

    @MainActor func testMarkupFamilyCustomizerMethods() async throws {
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let ids = try await script(s, "add", [try EngineJSON.parse(#"{"type":"circle","center":[0,0],"radius":500}"#)])
        s.editor.selection = [try XCTUnwrap(ids.intValue)]
        var r = try await s.call("markup.edit", obj([("op", .string("addAroundSelection")), ("comment", .string("Check this")), ("title", .string("Column"))]))
        let mid = try XCTUnwrap(r["id"]?.stringValue)
        XCTAssertEqual(r["list"]?["markups"]?.arrayValue?.count, 1)
        _ = try await s.call("markup.edit", obj([("op", .string("reply")), ("id", .string(mid)), ("text", .string("Done"))]))
        r = try await s.call("markup.edit", obj([("op", .string("status")), ("id", .string(mid)), ("resolved", .bool(true))]))
        let m = r["list"]?["markups"]?[0]
        XCTAssertEqual(m?["resolved"], .bool(true))
        XCTAssertEqual(m?["replies"]?.arrayValue?.count, 1)
        XCTAssertEqual(s.editor.history.undoLabel, "Resolve Markup")
        r = try await s.call("markup.edit", obj([("op", .string("remove")), ("id", .string(mid))]))
        XCTAssertEqual(r["list"]?["markups"]?.arrayValue?.count, 0)
        // Family editor: template, evaluate (preview meshes), apply, delete.
        let draft = try await s.call("family.template", obj([("template", .string("Furniture"))]))
        XCTAssertEqual(draft["name"]?.stringValue, "Furniture")
        let ev = try await s.call("family.evaluate", obj([("draft", draft), ("type", .string("1200 x 800"))]))
        XCTAssertEqual(ev["problems"], EngineJSON.strings([]))
        XCTAssertFalse(ev["meshes"]?.arrayValue?.isEmpty ?? true)
        XCTAssertEqual(ev["values"]?["Width"]?.doubleValue ?? ev["values"]?["width"]?.doubleValue, 1200)
        let applied = try await s.call("family.apply", obj([("draft", draft)]))
        XCTAssertEqual(applied["name"]?.stringValue, "Furniture")
        XCTAssertEqual(s.editor.history.undoLabel, "New Family Furniture")
        let fl = try await s.call("family.list")
        XCTAssertEqual(fl["families"]?[0]?["name"]?.stringValue, "Furniture")
        let again = try await s.call("family.template", obj([("template", .string("Furniture"))]))
        XCTAssertEqual(again["name"]?.stringValue, "Furniture 2")
        _ = try await s.call("family.delete", obj([("name", .string("Furniture"))]))
        XCTAssertTrue(s.editor.doc.families.isEmpty)
        // Customizer with nothing scripted selected.
        let cust = try await s.call("customizer.get")
        XCTAssertEqual(cust["target"], .null)
    }

    @MainActor func testBlockLibraryMethods() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("blocklib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var lib = ArchiDocument()
        lib.blocks["Chair"] = Block(name: "Chair", basePoint: .zero, entities: [Entity(layer: "0", geometry: .circle(CircleGeom(.zero, 250)))])
        _ = lib.add(.line(LineGeom(.zero, Vec2(1000, 0))), layer: "0")
        try DocumentIO.write(lib, to: dir.appendingPathComponent("Furniture.archi"), format: "archi")
        let s = EngineSession()
        _ = try await s.call("doc.new")
        let scan = try await s.call("library.scan", obj([("folder", .string(dir.path))]))
        let items = scan["items"]?.arrayValue ?? []
        XCTAssertEqual(items.map { $0["name"]?.stringValue ?? "" }, ["Furniture", "Chair"])
        let chair = try XCTUnwrap(items.first { $0["block"]?.stringValue == "Chair" })
        let pv = try await s.call("library.preview", obj([("file", chair["file"]!), ("block", chair["block"]!)]))
        XCTAssertFalse(pv["items"]?.arrayValue?.isEmpty ?? true)
        let ins = try await s.call("library.insert", obj([("file", chair["file"]!), ("block", chair["block"]!), ("x", .number(500)), ("y", .number(500))]))
        let id = try XCTUnwrap(ins["id"]?.intValue)
        XCTAssertEqual(s.editor.selection, [id])
        XCTAssertNotNil(s.editor.doc.blocks["Chair"])
        XCTAssertEqual(s.editor.history.undoLabel, "Insert Chair")
        let blocks = try await s.call("blocks.list")
        XCTAssertEqual(blocks.arrayValue?.first?["uses"]?.intValue, 1)
    }

    @MainActor func mcp(_ server: EngineMCPServer, _ line: String) async throws -> EngineJSON {
        let r = await server.handle(line: line)
        return try EngineJSON.parse(try XCTUnwrap(r))
    }

    @MainActor func testMCPServer() async throws {
        let s = EngineSession()
        var out: [String] = []
        let server = EngineMCPServer(session: s, path: nil, write: { out.append($0) })
        let initR = try await mcp(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        XCTAssertEqual(initR["result"]?["protocolVersion"]?.stringValue, "2025-03-26")
        let note = await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(note)
        let list = try await mcp(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let names = (list["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
        for n in ["run_command", "add_entity", "save", "takeoff", "check_model"] { XCTAssertTrue(names.contains(n), n) }
        let run = try await mcp(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run_command","arguments":{"command":"CIRCLE 0,0 500"}}}"#)
        XCTAssertEqual(run["result"]?["isError"], .bool(false))
        XCTAssertEqual(s.editor.doc.entities.count, 1)
        let sum = try await mcp(server, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_document_summary","arguments":{}}}"#)
        XCTAssertEqual(sum["result"]?["structuredContent"]?["entityCount"]?.intValue, 1)
        let bad = try await mcp(server, #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"delete","arguments":{}}}"#)
        XCTAssertEqual(bad["result"]?["isError"], .bool(true))
        let unknown = try await mcp(server, #"{"jsonrpc":"2.0","id":6,"method":"nope"}"#)
        XCTAssertEqual(unknown["error"]?["code"]?.intValue, -32601)
        XCTAssertTrue(out.isEmpty)
    }

    @MainActor func testToolWindowCommands() async throws {
        let reg = CommandRegistry()
        EngineSession.registerToolCommands(reg)
        var notes: [String] = []
        let s = EngineSession(editor: Editor(registry: reg), emit: { notes.append($0) })
        _ = try await s.call("doc.new")
        func hostActions() -> [EngineJSON] {
            s.flushNotifications()
            return notes.compactMap { try? EngineJSON.parse($0) }.filter { $0["method"]?.stringValue == "host" }.compactMap { $0["params"] }
        }
        _ = try await s.call("command.run", obj([("line", .string("MATBROWSER"))]))
        XCTAssertTrue(hostActions().contains { $0["action"]?.stringValue == "dialog" && $0["dialog"]?.stringValue == "materialLibrary" })
        _ = try await s.call("command.run", obj([("line", .string("NODES"))]))
        XCTAssertTrue(hostActions().contains { $0["dialog"]?.stringValue == "nodeEditor" })
        _ = try await s.call("command.run", obj([("line", .string("SHEETSET"))]))
        XCTAssertTrue(hostActions().contains { $0["action"]?.stringValue == "showPanel" && $0["panel"]?.stringValue == "Sheets" })
        _ = try await s.call("command.run", obj([("line", .string("TUTORIALRECORD List"))]))
        XCTAssertTrue(hostActions().contains { $0["action"]?.stringValue == "tutorials" && $0["mode"]?.stringValue == "List" })
        if s.editor.doc.layouts.isEmpty { s.editor.transaction("Sheet") { $0.layouts.append(Layout(name: "Sheet 1")) } }
        _ = try await s.call("command.run", obj([("line", .string("SHEETINDEX"))]))
        XCTAssertTrue(s.editor.doc.layouts[0].entities.contains { $0.props["sheetIndex"] != nil })
        XCTAssertEqual(s.editor.history.undoLabel, "SHEETINDEX")
        // GRAPHPLAYER runs a saved graph with typed input values (clamped) and bakes it.
        s.editor.transaction("Save Node Graph") { NodeGraph.sample.store(in: &$0, name: "Columns") }
        _ = try await s.call("command.run", obj([("line", .string("GRAPHPLAYER Columns 99999"))]))
        XCTAssertEqual(NodeGraphBake.bakedCount(s.editor.doc), 6)
    }

    func testScriptJSONNormalisation() throws {
        let raw = try EngineJSON.parse(#"{"type":"pline","points":[[0,0],[100,0,0.5],{"x":100,"y":100}],"closed":true}"#)
        let g = try ScriptJSON.geometry(from: raw)
        guard case .polyline(let p) = g else { return XCTFail("not a polyline") }
        XCTAssertEqual(p.vertices.count, 3)
        XCTAssertEqual(p.vertices[1].bulge, 0.5)
        XCTAssertTrue(p.closed)
        XCTAssertThrowsError(try ScriptJSON.geometry(from: try EngineJSON.parse(#"{"type":"banana"}"#)))
        let any = ScriptJSON.fromAny(["a": 1, "b": true, "c": [1.5, "x"], "d": NSNull()] as [String: Any])
        XCTAssertEqual(any["a"], .number(1))
        XCTAssertEqual(any["b"], .bool(true))
        XCTAssertEqual(any["c"]?[1]?.stringValue, "x")
        XCTAssertEqual(any["d"], .null)
        let back = ScriptJSON.toDict(any)
        XCTAssertEqual((back["a"] as? NSNumber)?.intValue, 1)
    }
}

private extension ArchiDocument {
    /// A wall on the ground floor for the material tests.
    mutating func addElementForTest() -> EntityID { addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0)))) }
}

private extension UndoHistory {
    var undoCountForTest: Int { undoStack.count }
}

// MARK: - Dialogs (Host/EngineDialogs.swift, Host/EngineUICommands.swift)

extension EngineSessionTests {
    /// A session with its own registry holding the core and the portable UI commands, and the notifications it sends.
    @MainActor func dialogSession() -> (EngineSession, NotificationSink) {
        let reg = CommandRegistry()
        EngineSession.registerPortableAppCommands(reg)
        let sink = NotificationSink()
        let s = EngineSession(editor: Editor(registry: reg), emit: { sink.lines.append($0) })
        return (s, sink)
    }

    /// `host` notifications sent so far.
    func hostActions(_ sink: NotificationSink) -> [EngineJSON] {
        sink.lines.compactMap { try? EngineJSON.parse($0) }.filter { $0["method"]?.stringValue == "host" }.compactMap { $0["params"] }
    }

    @MainActor func testPortableHelpCommands() async throws {
        let (s, sink) = dialogSession()
        _ = try await s.call("command.run", obj([("line", .string("ABOUT"))]))
        var h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "dialog")
        XCTAssertEqual(h?["dialog"]?.stringValue, "about")
        _ = try await s.call("command.run", obj([("line", .string("CMDSEARCH"))]))
        XCTAssertEqual(hostActions(sink).last?["dialog"]?.stringValue, "commandSearch")
        _ = try await s.call("command.run", obj([("line", .string("WHATSNEW"))]))
        XCTAssertEqual(hostActions(sink).last?["dialog"]?.stringValue, "whatsNew")
        _ = try await s.call("command.run", obj([("line", .string("CLEANSCREEN"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "cleanScreen")
        XCTAssertEqual(h?["on"], .bool(true))
        XCTAssertTrue(s.editor.log.contains("Clean screen on. CLEANSCREENOFF or Ctrl+0 restores the ribbon and panels."))
        _ = try await s.call("command.run", obj([("line", .string("CLEANSCREENOFF"))]))
        XCTAssertEqual(hostActions(sink).dropLast().last?["on"], .bool(false))
        XCTAssertEqual(hostActions(sink).last?["action"]?.stringValue, "ribbonExpand")
        _ = try await s.call("command.run", obj([("line", .string("RB"))]))
        XCTAssertEqual(hostActions(sink).last?["action"]?.stringValue, "ribbonExpand")
        _ = try await s.call("command.run", obj([("line", .string("HISTORYPANEL"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "showPanel")
        XCTAssertEqual(h?["panel"]?.stringValue, "History")
        XCTAssertEqual(s.editor.registry.lookup("HISTORY")?.name, "HISTORY", "the core HISTORY command keeps its name")
        _ = try await s.call("command.run", obj([("line", .string("WELCOME"))]))
        XCTAssertEqual(hostActions(sink).last?["action"]?.stringValue, "startScreen")
        _ = try await s.call("command.run", obj([("line", .string("SAMPLEHOUSE"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "newWindow")
        XCTAssertEqual(h?["kind"]?.stringValue, "sample")
        XCTAssertTrue(s.editor.log.contains("Opening the sample house…"))
        _ = try await s.call("command.run", obj([("line", .string("EXPORTCOMMANDS"))]))
        _ = try await s.call("input.text", obj([("text", .string("C:/Temp/commands.csv"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "exportCommands")
        XCTAssertEqual(h?["path"]?.stringValue, "C:/Temp/commands.csv")
        XCTAssertEqual(h?["csv"], .bool(true))
        XCTAssertGreaterThan(h?["count"]?.intValue ?? 0, 100)
        for n in ["ABOUT", "COMMANDSEARCH", "CLEANSCREENON", "CLEANSCREENOFF", "HISTORYPANEL", "STARTSCREEN", "SAMPLEHOUSE", "WHATSNEW", "EXPORTCOMMANDS"] {
            XCTAssertFalse(s.editor.registry.lookup(n)?.modifies ?? true, n)
        }
    }

    @MainActor func testDialogUnits() async throws {
        let (s, _) = dialogSession()
        var r = try await s.call("units.get")
        XCTAssertEqual(r["units"]?.stringValue, "millimeters")
        XCTAssertEqual(r["lunits"]?.intValue, 2)
        XCTAssertEqual(r["luprec"]?.intValue, 2)
        XCTAssertEqual(r["linearPrecisionLabel"]?.stringValue, "Precision: 2 decimals")
        XCTAssertEqual(r["unitList"]?.arrayValue?.count, 5)
        XCTAssertEqual(r["unitList"]?[0]?["title"]?.stringValue, "Millimeters (mm)")
        // Preview of other values without changing the drawing (the sheet's live sample).
        r = try await s.call("units.get", obj([("units", .string("inches")), ("lunits", .int(4)), ("luprec", .int(1))]))
        XCTAssertEqual(r["sample"]?.stringValue, "Sample: 3'-6 1/2\"  ·  45°")
        XCTAssertEqual(r["linearPrecisionLabel"]?.stringValue, "Precision: 1/2\"")
        XCTAssertEqual(s.editor.doc.units, .millimeters)
        // OK: one "Units" undo step.
        _ = try await s.call("units.set", obj([("units", .string("inches")), ("lunits", .int(4)), ("luprec", .int(4)), ("aunits", .int(1)), ("auprec", .int(2))]))
        XCTAssertEqual(s.editor.doc.units, .inches)
        XCTAssertEqual(s.editor.doc.variable("LUNITS"), "4")
        XCTAssertEqual(s.editor.doc.variable("AUPREC"), "2")
        XCTAssertEqual(s.editor.history.undoStack.count, 1)
        _ = try await s.call("units.set", obj([("units", .string("inches")), ("lunits", .int(4)), ("luprec", .int(4)), ("aunits", .int(1)), ("auprec", .int(2))]))
        XCTAssertEqual(s.editor.history.undoStack.count, 1, "no change, no undo step")
        _ = try await s.call("edit.undo")
        XCTAssertEqual(s.editor.doc.units, .millimeters)
        do { _ = try await s.call("units.set", obj([("lunits", .int(9))])); XCTFail("accepted lunits 9") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
        XCTAssertEqual(UnitFormat.angle(Double.pi / 4, type: .surveyor, precision: 1), "N 45d0' E")
    }

    @MainActor func testDialogDraftingSettings() async throws {
        let (s, _) = dialogSession()
        var r = try await s.call("drafting.get")
        XCTAssertEqual(r["gridSpacing"]?.doubleValue, 100)
        XCTAssertEqual(r["snapKinds"]?.arrayValue?.count, SnapKind.allCases.count)
        XCTAssertEqual(r["polarIncrements"]?.arrayValue?.count, 8)
        r = try await s.call("drafting.set", obj([("gridSpacing", .number(250)), ("ortho", .bool(true)), ("snapModes", EngineJSON.strings(["endpoint", "midpoint"])), ("wallHeight", .number(2800))]))
        XCTAssertEqual(s.editor.settings.gridSpacing, 250)
        XCTAssertTrue(s.editor.settings.ortho)
        XCTAssertEqual(s.editor.settings.snapModes, [.endpoint, .midpoint])
        XCTAssertEqual(s.editor.settings.wallHeight, 2800)
        XCTAssertEqual(r["snapModes"]?.arrayValue?.count, 2)
        do { _ = try await s.call("drafting.set", obj([("gridSpacing", .number(-5))])); XCTFail("accepted a negative grid") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
        // Settings ▸ Drafting defaults on a new drawing in metres: grid spacing converted from millimetres, polar off with ortho.
        _ = try await s.call("doc.new", obj([("template", .string("metric"))]))
        let draft = obj([("gridSpacing", .number(500)), ("ortho", .bool(true)), ("polarTracking", .bool(true)), ("showGrid", .bool(false))])
        _ = try await s.call("drafting.defaults", obj([("units", .string("meters")), ("draft", draft)]))
        XCTAssertEqual(s.editor.doc.units, .meters)
        XCTAssertEqual(s.editor.settings.gridSpacing, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.editor.settings.wallThickness, 0.2, accuracy: 1e-9)
        XCTAssertFalse(s.editor.settings.polarTracking)
        XCTAssertFalse(s.editor.settings.showGrid)
        XCTAssertFalse(s.editor.isDirty)
    }

    @MainActor func testDialogQuickSelect() async throws {
        let (s, _) = dialogSession()
        _ = try await s.call("command.run", obj([("line", .string("LINE 0,0 1000,0 ;"))]))
        _ = try await s.call("command.run", obj([("line", .string("LINE 0,500 2000,500 ;"))]))
        _ = try await s.call("command.run", obj([("line", .string("CIRCLE 0,0 100"))]))
        _ = try await s.call("command.run", obj([("line", .string("CIRCLE 5000,0 20"))]))
        let o = try await s.call("qselect.options")
        let types = o["types"]?.arrayValue?.compactMap { $0["value"]?.stringValue } ?? []
        XCTAssertEqual(types.first, "*")
        XCTAssertTrue(types.contains("line") && types.contains("circle"))
        XCTAssertEqual(o["properties"]?[0]?["title"]?.stringValue, "None (type only)")
        XCTAssertEqual(o["operators"]?[1]?["title"]?.stringValue, "≠ Not equal")
        var r = try await s.call("qselect.run", obj([("type", .string("line"))]))
        XCTAssertEqual(r["count"]?.intValue, 2)
        XCTAssertTrue(s.editor.selection.isEmpty, "the count does not select")
        r = try await s.call("qselect.run", obj([("type", .string("circle")), ("property", .string("radius")), ("op", .string(">")), ("value", .string("50")), ("apply", .bool(true))]))
        XCTAssertEqual(r["count"]?.intValue, 1)
        XCTAssertEqual(s.editor.selection.count, 1)
        r = try await s.call("qselect.run", obj([("type", .string("line")), ("apply", .bool(true)), ("mode", .string("Append"))]))
        XCTAssertEqual(r["selected"]?.intValue, 3)
        r = try await s.call("qselect.run", obj([("type", .string("*")), ("scope", .int(1)), ("apply", .bool(true)), ("mode", .string("Exclude"))]))
        XCTAssertEqual(r["selected"]?.intValue, 0)
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("QSELECT * * → 3 matched; 0 selected.") })
    }

    @MainActor func testDialogLayerStatesAndFilters() async throws {
        let (s, _) = dialogSession()
        _ = try await s.call("panel.set", obj([("panel", .string("layers")), ("key", .string("new")), ("value", .string("X-WALL"))]))
        _ = try await s.call("panel.set", obj([("panel", .string("layers")), ("key", .string("new")), ("value", .string("X-DOOR"))]))
        var r = try await s.call("layerstate.save", obj([("name", .string("plan"))]))
        XCTAssertEqual(r["selected"]?.stringValue, "PLAN")
        XCTAssertEqual(r["states"]?[0]?["layers"]?.intValue, s.editor.doc.layers.count)
        _ = try await s.call("panel.set", obj([("panel", .string("layers")), ("key", .string("X-WALL.visible")), ("value", .bool(false))]))
        XCTAssertEqual(s.editor.doc.layer(named: "X-WALL")?.visible, false)
        r = try await s.call("layerstate.restore", obj([("name", .string("PLAN"))]))
        XCTAssertEqual(r["changed"]?.intValue, 1)
        XCTAssertEqual(s.editor.doc.layer(named: "X-WALL")?.visible, true)
        r = try await s.call("layerstate.rename", obj([("name", .string("PLAN")), ("newName", .string("ground"))]))
        XCTAssertEqual(r["selected"]?.stringValue, "GROUND")
        XCTAssertEqual(LayerStates.names(s.editor.doc), ["GROUND"])
        r = try await s.call("layerstate.delete", obj([("name", .string("GROUND"))]))
        XCTAssertEqual(r["states"]?.arrayValue?.count, 0)
        // Saved layer filters and the layer tree's bulk toggles.
        r = try await s.call("layerfilter.save", obj([("name", .string("arch")), ("filter", .string("#on X-*"))]))
        XCTAssertEqual(r["filters"]?[0]?["name"]?.stringValue, "ARCH")
        XCTAssertEqual(s.editor.doc.variables["LAYERFILTER:ARCH"], "#on X-*")
        r = try await s.call("layers.group", obj([("group", .string("X")), ("key", .string("locked")), ("value", .bool(true))]))
        XCTAssertEqual(r["changed"]?.intValue, 2)
        XCTAssertEqual(s.editor.doc.layer(named: "X-DOOR")?.locked, true)
        XCTAssertEqual(EngineSession.layerGroupKey("xref|A-WALL"), "xref|")
        XCTAssertEqual(EngineSession.layerGroupKey("0"), "(Standard)")
        _ = try await s.call("layerfilter.delete", obj([("name", .string("arch"))]))
        XCTAssertNil(s.editor.doc.variables["LAYERFILTER:ARCH"])
        let f = EngineLayerFilter(stored: "#on #used X-*,~*DOOR*")
        XCTAssertEqual(f.stored, "#on #used X-*,~*DOOR*")
        XCTAssertTrue(EngineLayerFilter.matchesPattern(f.pattern, "X-WALL"))
        XCTAssertFalse(EngineLayerFilter.matchesPattern(f.pattern, "X-DOOR"))
        XCTAssertTrue(EngineLayerFilter.matchesPattern("wall", "X-WALL-EXT"))
    }

    @MainActor func testDialogPageSetup() async throws {
        let (s, _) = dialogSession()
        var r = try await s.call("pagesetup.get")
        XCTAssertEqual(r["isSheet"], .bool(false))
        XCTAssertEqual(r["title"]?.stringValue, "Page Setup — Model")
        XCTAssertEqual(r["scaleText"]?.stringValue, "Fit")
        XCTAssertEqual(r["setup"]?["colorMode"]?.stringValue, "Color")
        XCTAssertEqual(r["tables"]?.arrayValue?.count, 3)
        XCTAssertEqual(r["namedTables"]?[0]?.stringValue, "archi named.stb")
        let papers = r["papers"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        XCTAssertEqual(papers.prefix(2), ["A4", "A3"])
        XCTAssertTrue(papers.contains("ANSI E") && papers.contains("ARCH E1"))
        _ = try await s.call("pagesetup.set", obj([("setup", obj([("colorMode", .string("Monochrome")), ("plotStamp", .bool(true))])), ("scaleText", .string("1:100"))]))
        let stored = try XCTUnwrap(s.editor.doc.variables["PAGESETUP:*MODEL*"])
        XCTAssertTrue(stored.contains("\"colorMode\":\"Monochrome\"") && stored.contains("\"modelScale\":100"), stored)
        r = try await s.call("pagesetup.get")
        XCTAssertEqual(r["scaleText"]?.stringValue, "1:100")
        // Back to the defaults: the variable is removed (as PageSetup.store).
        _ = try await s.call("pagesetup.set", obj([("setup", obj([("colorMode", .string("Color")), ("plotStamp", .bool(false))])), ("scaleText", .string("Fit"))]))
        XCTAssertNil(s.editor.doc.variables["PAGESETUP:*MODEL*"])
        // A sheet: paper and orientation, one undo step.
        let undo = s.editor.history.undoStack.count
        r = try await s.call("pagesetup.set", obj([("layout", .int(0)), ("paper", .string("A1")), ("portrait", .bool(true)), ("setup", obj([("lineweightScale", .number(1.5))]))]))
        XCTAssertEqual(s.editor.doc.layouts[0].paper.name, "A1 portrait")
        XCTAssertEqual(s.editor.doc.layouts[0].paper.width, 594)
        XCTAssertEqual(r["paper"]?.stringValue, "A1")
        XCTAssertEqual(r["portrait"], .bool(true))
        XCTAssertEqual(r["setup"]?["lineweightScale"]?.doubleValue, 1.5)
        XCTAssertEqual(s.editor.history.undoStack.count, undo + 1)
        do { _ = try await s.call("pagesetup.set", obj([("setup", obj([("plotArea", .string("Everything"))]))])); XCTFail("accepted an unknown plot area") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
    }

    @MainActor func testDialogTemplates() async throws {
        let (s, _) = dialogSession()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-templates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var r = try await s.call("templates.list", obj([("folder", .string(dir.path))]))
        XCTAssertEqual(r["templates"]?.arrayValue?.count, 4)
        XCTAssertEqual(r["templates"]?[1]?["id"]?.stringValue, "builtin:metricArchitectural")
        _ = try await s.call("command.run", obj([("line", .string("LINE 0,0 1000,0 ;"))]))
        r = try await s.call("templates.save", obj([("name", .string("Office")), ("folder", .string(dir.path))]))
        let path = try XCTUnwrap(r["path"]?.stringValue)
        XCTAssertTrue(path.hasSuffix("Office.architemplate"))
        r = try await s.call("templates.list", obj([("folder", .string(dir.path))]))
        XCTAssertEqual(r["templates"]?[4]?["name"]?.stringValue, "Office")
        XCTAssertEqual(r["templates"]?[4]?["subtitle"]?.stringValue, "Templates folder")
        r = try await s.call("templates.new", obj([("id", .string(path))]))
        XCTAssertEqual(s.editor.doc.info.name, "Untitled Project")
        XCTAssertEqual(s.editor.doc.entities.count, 1)
        XCTAssertNil(s.editor.fileURL)
        XCTAssertFalse(s.editor.isDirty)
        _ = try await s.call("templates.new", obj([("id", .string("builtin:metricArchitectural"))]))
        XCTAssertNotNil(s.editor.doc.layer(named: "A-COLS"))
        XCTAssertEqual(s.editor.doc.currentDimStyle, "Architectural 1:100")
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("New drawing from the Metric Architectural template") })
    }

    @MainActor func testPortableUICommands() async throws {
        let (s, sink) = dialogSession()
        _ = try await s.call("command.run", obj([("line", .string("OPTIONS Drafting"))]))
        var h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "dialog")
        XCTAssertEqual(h?["dialog"]?.stringValue, "options")
        XCTAssertEqual(h?["tab"]?.stringValue, "Drafting")
        _ = try await s.call("command.run", obj([("line", .string("QSD"))]))
        XCTAssertEqual(hostActions(sink).last?["dialog"]?.stringValue, "quickSelect")
        _ = try await s.call("command.run", obj([("line", .string("LAYERSTATE"))]))
        _ = try await s.call("input.key", obj([("key", .string("Enter"))]))
        XCTAssertEqual(hostActions(sink).last?["dialog"]?.stringValue, "layerStates")
        _ = try await s.call("command.run", obj([("line", .string("PAGESETUP"))]))
        XCTAssertEqual(hostActions(sink).last?["dialog"]?.stringValue, "pageSetup")
        // Settings values: range checks and the "preference" host action.
        _ = try await s.call("command.run", obj([("line", .string("CURSORSIZE 150"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Requires an integer between 1 and 100.") }, s.editor.log.suffix(4).joined(separator: " | "))
        _ = try await s.call("command.run", obj([("line", .string("CURSORSIZE 25"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "preference")
        XCTAssertEqual(h?["key"]?.stringValue, "cursorSize")
        XCTAssertEqual(h?["value"]?.intValue, 25)
        _ = try await s.call("command.run", obj([("line", .string("SAVETIME 0"))]))
        XCTAssertTrue(s.editor.log.contains("Autosave is off."))
        // Workspaces: names from the shell (ui.prefs), prefix match.
        _ = try await s.call("ui.prefs", obj([("values", obj([("workspaces", .string("Drafting & Annotation|3D Modeling|My Layout")), ("workspace", .string("Drafting & Annotation"))]))]))
        _ = try await s.call("command.run", obj([("line", .string("WSCURRENT my"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "workspace")
        XCTAssertEqual(h?["name"]?.stringValue, "My Layout")
        XCTAssertTrue(s.editor.log.contains("Workspace: My Layout"))
        _ = try await s.call("command.run", obj([("line", .string("WSCURRENT Nowhere"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Workspace \"Nowhere\" not found.") })
        // Ribbon customisation from the command line.
        _ = try await s.call("command.run", obj([("line", .string("CUI Add Home"))]))
        _ = try await s.call("input.text", obj([("text", .string("Quick"))]))
        _ = try await s.call("input.text", obj([("text", .string("LINE,ZOOM E"))]))
        h = hostActions(sink).last
        XCTAssertEqual(h?["action"]?.stringValue, "cui")
        XCTAssertEqual(h?["data"]?["panels"]?[0]?["title"]?.stringValue, "Quick")
        XCTAssertEqual(h?["data"]?["panels"]?[0]?["commands"], EngineJSON.strings(["LINE", "ZOOM E"]))
        XCTAssertTrue(s.editor.log.contains("Ribbon: 1 custom panel(s), 0 hidden."))
        _ = try await s.call("command.run", obj([("line", .string("CUI Add Home"))]))
        _ = try await s.call("input.text", obj([("text", .string("Bad"))]))
        _ = try await s.call("input.text", obj([("text", .string("NOSUCHCOMMAND"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Unknown command(s): NOSUCHCOMMAND") })
        // Templates from the command line.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-cmd-templates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await s.call("ui.prefs", obj([("values", obj([("templatesFolder", .string(dir.path))]))]))
        _ = try await s.call("command.run", obj([("line", .string("SAVEASTEMPLATE Studio"))]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Studio.architemplate").path))
        _ = try await s.call("doc.new")
        _ = try await s.call("command.run", obj([("line", .string("NEWFROMTEMPLATE Imperial"))]))
        XCTAssertEqual(s.editor.doc.units, .inches)
        XCTAssertEqual(hostActions(sink).last?["action"]?.stringValue, "zoomExtents")
        let hello = try await s.call("engine.hello")
        let methods = hello["methods"]?.arrayValue?.compactMap(\.stringValue) ?? []
        XCTAssertTrue(methods.contains("units.get") && methods.contains("templates.new"))
    }
}

// MARK: - Canvas (Host/EngineCanvas.swift): the 2D canvas methods of the Windows shell

extension EngineSessionTests {
    @MainActor func line(_ s: EngineSession, _ text: String) async throws {
        _ = try await s.call("command.run", obj([("line", .string(text))]))
        if !s.editor.isIdle { _ = try await s.call("input.key", obj([("key", .string("Enter"))])) }
    }

    @MainActor func testCanvasMethodsAndState() async throws {
        let s = EngineSession()
        let h = try await s.call("engine.hello")
        for m in EngineCanvasMethods.all { XCTAssertTrue(h["methods"]?.arrayValue?.contains(.string(m)) ?? false, m) }
        s.editor.doc.setVariable("VIEWTWIST", "30")
        let st = try await s.call("canvas.state")
        XCTAssertEqual(st["twist"]?.doubleValue, 30)
        XCTAssertEqual(st["ucs"]?["world"], .bool(true))
        XCTAssertEqual(st["ucsIcon"]?["on"], .bool(true))
        XCTAssertEqual(st["isometric"], .bool(false))
        // Dynamic-input fields and the tracking state come with every cursor move while a point is asked.
        _ = try await s.call("command.run", obj([("line", .string("LINE"))]))
        _ = try await s.call("input.point", point(0, 0))
        let c = try await s.call("input.cursor", obj([("x", .number(300)), ("y", .number(400)), ("pixelsPerUnit", .number(0.1))]))
        XCTAssertEqual(c["dynamic"]?["length"]?.doubleValue ?? 0, 500, accuracy: 1e-6)
        XCTAssertEqual(c["dynamic"]?["angle"]?.doubleValue ?? 0, 53.130102, accuracy: 1e-4)
        XCTAssertNotNil(c["tracking"])
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
    }

    @MainActor func testCanvasGripsPreviewEditAndModes() async throws {
        let s = EngineSession()
        try await line(s, "PLINE 0,0 4000,0 4000,2000")
        let pl = try XCTUnwrap(s.editor.doc.entities.last?.id)
        _ = try await s.call("select.set", obj([("ids", .ints([pl]))]))
        let grips = try await s.call("grips.get").arrayValue ?? []
        let mid = try XCTUnwrap(grips.first { $0["kind"]?.stringValue == "midpoint" })
        let mi = try XCTUnwrap(mid["index"]?.intValue)
        let acts = try await s.call("grips.actions", obj([("id", .int(pl)), ("index", .int(mi))])).arrayValue ?? []
        XCTAssertTrue(acts.contains { $0["action"]?.stringValue == "addVertex" && $0["title"]?.stringValue == "Add Vertex" }, "\(acts)")
        let pv = try await s.call("grips.preview", obj([("id", .int(pl)), ("index", .int(0)), ("x", .number(-500)), ("y", .number(-500)), ("snap", .bool(false))]))
        XCTAssertEqual(pv["point"]?.vec2, Vec2(-500, -500))
        XCTAssertFalse(pv["items"]?.arrayValue?.isEmpty ?? true)
        let mv = try await s.call("grips.preview", obj([("id", .int(pl)), ("index", .int(0)), ("x", .number(1000)), ("y", .number(0)), ("mode", .string("MO")), ("snap", .bool(false))]))
        XCTAssertFalse(mv["items"]?.arrayValue?.isEmpty ?? true)
        // Nothing changes until the grip edit is committed (one undo step).
        guard case .polyline(let before) = s.editor.doc.entities.last!.geometry else { return XCTFail("not a polyline") }
        XCTAssertEqual(before.vertices.first?.p, Vec2(0, 0))
        let ed = try await s.call("grips.edit", obj([("id", .int(pl)), ("index", .int(0)), ("x", .number(-500)), ("y", .number(-500))]))
        XCTAssertEqual(ed["changed"], EngineJSON.ints([pl]))
        guard case .polyline(let after) = s.editor.doc.entity(pl)!.geometry else { return XCTFail("not a polyline") }
        XCTAssertEqual(after.vertices.first?.p, Vec2(-500, -500))
        XCTAssertEqual(s.editor.history.undoLabel, "Grip Edit")
        // Grip Move mode with Copy keeps the original and adds a copy.
        let n = s.editor.doc.entities.count
        _ = try await s.call("grips.edit", obj([("id", .int(pl)), ("index", .int(0)), ("x", .number(0)), ("y", .number(5000)), ("mode", .string("move")), ("copy", .bool(true))]))
        XCTAssertEqual(s.editor.doc.entities.count, n + 1)
        XCTAssertEqual(s.editor.history.undoLabel, "Grip Move Copy")
        // A typed value while the grip is hot: Rotate 90 about the grip.
        _ = try await s.call("grips.typed", obj([("id", .int(pl)), ("index", .int(0)), ("mode", .string("RO")), ("value", .number(90)), ("x", .number(0)), ("y", .number(0))]))
        XCTAssertEqual(s.editor.history.undoLabel, "Grip Rotate")
        // Add Vertex from the multi-functional grip menu.
        let count0 = after.vertices.count
        _ = try await s.call("edit.undo")
        _ = try await s.call("edit.undo")
        _ = try await s.call("grips.edit", obj([("id", .int(pl)), ("index", .int(mi)), ("x", .number(1500)), ("y", .number(-800)), ("action", .string("addVertex"))]))
        guard case .polyline(let added) = s.editor.doc.entity(pl)!.geometry else { return XCTFail("not a polyline") }
        XCTAssertEqual(added.vertices.count, count0 + 1)
    }

    @MainActor func testCanvasLassoCyclingAndChain() async throws {
        let s = EngineSession()
        try await line(s, "LINE 0,0 1000,0")
        try await line(s, "LINE 0,0 1000,0")
        let ids = s.editor.doc.entities.map(\.id)
        XCTAssertEqual(ids.count, 2)
        let cands = try await s.call("pick.candidates", obj([("x", .number(500)), ("y", .number(0)), ("tolerance", .number(5))]))
        XCTAssertEqual(Set(cands["ids"]?.arrayValue?.compactMap(\.intValue) ?? []), Set(ids))
        XCTAssertEqual(cands["types"]?.arrayValue?.first?.stringValue, "line")
        // Cycling swaps the selected object for the next one.
        let first = try XCTUnwrap(cands["ids"]?[0]?.intValue), second = try XCTUnwrap(cands["ids"]?[1]?.intValue)
        _ = try await s.call("select.set", obj([("ids", .ints([first]))]))
        let sw = try await s.call("select.modify", obj([("remove", .ints([first])), ("add", .ints([second]))]))
        XCTAssertEqual(sw["ids"], EngineJSON.ints([second]))
        _ = try await s.call("select.set", obj([("ids", .array([]))]))
        // Clockwise lasso = window: both lines inside.
        let cw: [Vec2] = [Vec2(-100, -100), Vec2(-100, 100), Vec2(1100, 100), Vec2(1100, -100)]
        let w = try await s.call("select.lasso", obj([("points", .array(cw.map { EngineJSON.point($0) }))]))
        XCTAssertEqual(w["mode"]?.stringValue, "window")
        XCTAssertEqual(Set(w["ids"]?.arrayValue?.compactMap(\.intValue) ?? []), Set(ids))
        // Counter-clockwise lasso over half the lines = crossing; a clockwise one there selects nothing.
        _ = try await s.call("select.set", obj([("ids", .array([]))]))
        let half: [Vec2] = [Vec2(500, -100), Vec2(500, 100), Vec2(1100, 100), Vec2(1100, -100)]
        let none = try await s.call("select.lasso", obj([("points", .array(half.map { EngineJSON.point($0) }))]))
        XCTAssertEqual(none["ids"], EngineJSON.ints([]))
        let cr = try await s.call("select.lasso", obj([("points", .array(half.reversed().map { EngineJSON.point($0) }))]))
        XCTAssertEqual(cr["mode"]?.stringValue, "crossing")
        XCTAssertEqual(cr["ids"]?.arrayValue?.count, 2)
        // Arrow-key nudge.
        let nudge = try await s.call("select.nudge", obj([("dx", .number(1)), ("dy", .number(0)), ("big", .bool(true))]))
        XCTAssertEqual(nudge["moved"]?.intValue, 2)
        XCTAssertEqual(s.editor.history.undoLabel, "Nudge")
        // Joined walls: Tab selects the chain.
        try await line(s, "WALL 0,5000 4000,5000 4000,8000")
        let walls = s.editor.doc.elements.filter { $0.typeName == "wall" }.map(\.id)
        XCTAssertEqual(walls.count, 2)
        _ = try await s.call("select.set", obj([("ids", .array([]))]))
        let ch = try await s.call("select.chain", obj([("id", .int(walls[0]))]))
        XCTAssertEqual(Set(ch["chain"]?.arrayValue?.compactMap(\.intValue) ?? []), Set(walls))
    }

    @MainActor func testCanvasDoubleClickTextTempDimsAndFlips() async throws {
        let s = EngineSession()
        var tid: EntityID = 0
        s.editor.transaction("Add") { d in tid = d.add(.text(TextGeom(position: Vec2(0, 0), height: 250, content: "Hello"))) }
        let dc = try await s.call("canvas.doubleClick", obj([("id", .int(tid))]))
        XCTAssertEqual(dc["action"]?.stringValue, "textEditor")
        XCTAssertEqual(dc["content"]?.stringValue, "Hello")
        XCTAssertEqual(dc["singleLine"], .bool(true))
        _ = try await s.call("text.edit", obj([("id", .int(tid)), ("content", .string("World")), ("bold", .bool(true))]))
        guard case .text(let t) = s.editor.doc.entity(tid)!.geometry else { return XCTFail("not text") }
        XCTAssertEqual(t.content, "World")
        XCTAssertEqual(s.editor.doc.entity(tid)?.props["bold"], "1")
        XCTAssertNotNil(s.editor.doc.entity(tid)?.props["mtext"])
        XCTAssertEqual(s.editor.history.undoLabel, "Edit Text")
        // Two parallel walls: the temporary dimension between them moves the selected one.
        try await line(s, "WALL 0,0 5000,0")
        try await line(s, "WALL 0,3000 5000,3000")
        let walls = s.editor.doc.elements.filter { $0.typeName == "wall" }.map(\.id)
        XCTAssertEqual(walls.count, 2)
        let wdc = try await s.call("canvas.doubleClick", obj([("id", .int(walls[0]))]))
        XCTAssertEqual(wdc["action"]?.stringValue, "properties")
        _ = try await s.call("select.set", obj([("ids", .ints([walls[0]]))]))
        let dims = try await s.call("tempdims.get").arrayValue ?? []
        let d0 = try XCTUnwrap(dims.first)
        XCTAssertEqual(d0["value"]?.doubleValue ?? 0, 3000, accuracy: 1e-6)
        _ = try await s.call("tempdims.set", obj([("id", .int(walls[0])), ("index", .int(0)), ("value", .number(2500))]))
        guard case .wall(let w) = s.editor.doc.element(walls[0])!.geometry else { return XCTFail("not a wall") }
        XCTAssertEqual(w.start.y, 500, accuracy: 1e-6)
        XCTAssertEqual(s.editor.history.undoLabel, "Temporary Dimension")
        // Flip arrows: the selected wall has one; a door has facing and hand.
        let wf = try await s.call("flips.get", obj([("pixelsPerUnit", .number(0.1))])).arrayValue ?? []
        XCTAssertEqual(wf.first?["kind"]?.stringValue, "wall")
        try await line(s, "DOOR 2500,3000")
        let door = try XCTUnwrap(s.editor.doc.elements.last { $0.typeName == "door" || $0.typeName == "opening" })
        _ = try await s.call("select.set", obj([("ids", .ints([door.id]))]))
        let df = try await s.call("flips.get", obj([("pixelsPerUnit", .number(0.1))])).arrayValue ?? []
        XCTAssertEqual(df.compactMap { $0["kind"]?.stringValue }, ["facing", "hand"])
        let fa = try await s.call("flips.apply", obj([("id", .int(door.id)), ("kind", .string("facing"))]))
        XCTAssertEqual(fa["changed"], .bool(true))
        XCTAssertEqual(s.editor.history.undoLabel, "Flip Facing")
    }

    @MainActor func testCanvasPaletteAndDrops() async throws {
        let s = EngineSession()
        let items = try await s.call("palette.items")
        let comps = items["components"]?.arrayValue ?? []
        XCTAssertEqual(comps.count, ComponentLibrary.families.count)
        let item = try XCTUnwrap(comps.first?["item"]?.stringValue)
        XCTAssertTrue(item.hasPrefix(EngineToolDrop.componentPrefix))
        XCTAssertFalse(comps.first?["shapes"]?.arrayValue?.isEmpty ?? true)
        let pv = try await s.call("place.preview", obj([("item", .string(item)), ("x", .number(1000)), ("y", .number(1000)), ("turns", .int(1))]))
        XCTAssertFalse(pv["items"]?.arrayValue?.isEmpty ?? true)
        XCTAssertEqual(pv["degrees"]?.intValue, 90)
        XCTAssertTrue(s.editor.doc.elements.isEmpty)
        let drop = try await s.call("place.drop", obj([("item", .string(item)), ("x", .number(1000)), ("y", .number(1000)), ("turns", .int(1))]))
        XCTAssertEqual(drop["ok"], .bool(true))
        let el = try XCTUnwrap(s.editor.doc.elements.first)
        guard case .component(let c) = el.geometry else { return XCTFail("not a component") }
        XCTAssertEqual(c.position, Vec2(1000, 1000))
        XCTAssertEqual(c.rotation, .pi / 2, accuracy: 1e-9)
        XCTAssertTrue(s.editor.history.undoLabel?.hasPrefix("Place ") ?? false)
        // A command tile dropped on the drawing runs the command.
        let cmd = try await s.call("place.drop", obj([("item", .string(EngineToolDrop.commandPrefix + "LINE")), ("x", .number(0)), ("y", .number(0))]))
        XCTAssertEqual(cmd["prompt"]?["command"]?.stringValue, "LINE")
        _ = try await s.call("input.key", obj([("key", .string("Escape"))]))
        // Dropped files: a drawing is returned to open, an SVG is imported at the drop point.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let svg = dir.appendingPathComponent("shape.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><line x1="0" y1="0" x2="100" y2="0" stroke="black"/></svg>"#.write(to: svg, atomically: true, encoding: .utf8)
        let fd = try await s.call("file.drop", obj([("paths", EngineJSON.strings([svg.path, dir.appendingPathComponent("house.archi").path])), ("x", .number(0)), ("y", .number(0))]))
        XCTAssertEqual(fd["open"]?.arrayValue?.count, 1)
        XCTAssertFalse(fd["ids"]?.arrayValue?.isEmpty ?? true, "\(fd)")
        XCTAssertEqual(s.editor.history.undoLabel, "Drop shape.svg")
    }

    @MainActor func testCanvasSheetViewports() async throws {
        let reg = CommandRegistry.shared
        EngineSession.registerToolCommands(reg)
        let s = EngineSession()
        s.editor.transaction("Sheet") { d in
            var l = Layout(name: "A101")
            l.viewports = [Viewport(origin: Vec2(20, 20), size: Vec2(200, 150), viewCenter: .zero, scale: 100),
                           Viewport(origin: Vec2(240, 20), size: Vec2(100, 100), viewCenter: .zero, scale: 50)]
            d.layouts = [l]
            d.setVariable("CTAB", "A101")
        }
        var v = try await s.call("sheet.viewports")
        XCTAssertEqual(v["layout"]?.stringValue, "A101")
        XCTAssertEqual(v["viewports"]?.arrayValue?.count, 2)
        XCTAssertEqual(v["viewports"]?[0]?["ratioText"]?.stringValue, "1:100")
        v = try await s.call("sheet.viewport", obj([("index", .int(0)), ("op", .string("lock"))]))
        XCTAssertEqual(v["viewports"]?[0]?["locked"], .bool(true))
        XCTAssertEqual(s.editor.history.undoLabel, "Lock Viewport")
        do {
            _ = try await s.call("sheet.viewport", obj([("index", .int(0)), ("op", .string("move")), ("origin", .numbers([30, 30]))]))
            XCTFail("a locked viewport moved")
        } catch {}
        _ = try await s.call("sheet.viewport", obj([("index", .int(1)), ("op", .string("move")), ("origin", .numbers([250, 30]))]))
        XCTAssertEqual(s.editor.doc.layouts[0].viewports[1].origin, Vec2(250, 30))
        XCTAssertEqual(s.editor.history.undoLabel, "Move Viewport")
        v = try await s.call("sheet.viewport", obj([("index", .int(1)), ("op", .string("clip")), ("points", .array([.numbers([250, 30]), .numbers([330, 30]), .numbers([250, 110])]))]))
        XCTAssertEqual(v["viewports"]?[1]?["clip"]?.arrayValue?.count, 3)
        // VPLOCK (portable command): unlock all, then remove the first viewport; locks and clips follow the renumbering.
        _ = try await s.call("command.run", obj([("line", .string("VPLOCK Off All"))]))
        XCTAssertTrue(EngineViewports.locked(s.editor.doc, 0).isEmpty)
        v = try await s.call("sheet.viewport", obj([("index", .int(0)), ("op", .string("remove"))]))
        XCTAssertEqual(v["viewports"]?.arrayValue?.count, 1)
        XCTAssertEqual(v["viewports"]?[0]?["clip"]?.arrayValue?.count, 3)
        // VPMAX asks the shell to show the viewport's model window.
        var notes: [String] = []
        s.emit = { notes.append($0) }
        _ = try await s.call("command.run", obj([("line", .string("VPMAX"))]))
        s.flushNotifications()
        XCTAssertTrue(notes.contains { $0.contains("\"maximizeViewport\"") }, "\(notes)")
        _ = try await s.call("canvas.view", obj([("center", .numbers([123, 456])), ("scale", .number(0.1))]))
        _ = try await s.call("command.run", obj([("line", .string("VPMIN"))]))
        XCTAssertEqual(s.editor.doc.layouts[0].viewports[0].viewCenter, Vec2(123, 456))
    }
}

// MARK: - 3D view (Host/EngineView3D.swift, EngineView3DCommands.swift)

extension EngineSessionTests {
    @MainActor func testView3DInfoVariablesAndStyle() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, _) = dialogSession()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        var info = try await s.call("view3d.info")
        let names = info["cameras"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        for n in ["Front", "Aerial", "Corner"] { XCTAssertTrue(names.contains(n), "saved camera \(n) in \(names)") }
        XCTAssertNotNil(info["cameras"]?[0]?["eye"]?[2])
        XCTAssertEqual(info["perspective"], .bool(true))
        XCTAssertEqual(info["visualStyle"]?.stringValue, "Shaded with Edges")
        XCTAssertNotNil(info["materialMaps"]?.fields)
        XCTAssertGreaterThanOrEqual(info["levels"]?.arrayValue?.count ?? 0, 2)
        XCTAssertEqual(info["weather"]?["kind"]?.stringValue, "Clear")
        // Variables: one undo step each, validated.
        let r = try await s.call("view3d.setVariable", obj([("name", .string("SECTIONBOX")), ("value", .string("on;0,0,0,5000,4000,3000"))]))
        XCTAssertEqual(r["changed"], .bool(true))
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["sectionBox"]?["on"], .bool(true))
        XCTAssertEqual(info["sectionBox"]?["max"]?[0]?.doubleValue, 5000)
        _ = try await s.call("edit.undo")
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["sectionBox"], .null)
        do { _ = try await s.call("view3d.setVariable", obj([("name", .string("SECTIONPLANE")), ("value", .string("on;1,2;0,0"))])); XCTFail("invalid plane accepted") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
        do { _ = try await s.call("view3d.setVariable", obj([("name", .string("LTSCALE")), ("value", .string("2"))])); XCTFail("non-3D variable accepted") }
        catch let e as EngineError { XCTAssertEqual(e.code, EngineError.invalidParams) }
        _ = try await s.call("view3d.setVariable", obj([("name", .string("PERSPECTIVE")), ("value", .string("0"))]))
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["perspective"], .bool(false))
        _ = try await s.call("view3d.setVariable", obj([("name", .string("VSCURRENT")), ("value", .string("Realistic"))]))
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["visualStyle"]?.stringValue, "Realistic")
        _ = try await s.call("command.run", obj([("line", .string("VSCURRENT Sketchy"))]))
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["visualStyle"]?.stringValue, "Sketchy")
        // Sun study at the site.
        let sun = try await s.call("view3d.sun", obj([("day", .int(172)), ("hour", .number(13))]))
        XCTAssertGreaterThan(sun["altitude"]?.doubleValue ?? 0, 40)
        XCTAssertEqual(sun["direction"]?.arrayValue?.count, 3)
    }

    @MainActor func testView3DCapsGizmoAndBinaryMeshes() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, _) = dialogSession()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        // Caps of a horizontal cut 1.2 m above the lowest point.
        var ext = BBox3.empty
        for g in MeshBuilder.build(doc: s.editor.doc) { for p in g.mesh.positions { ext.add(p) } }
        let cutZ: Double = ext.min.z + 1200
        let capPoint = EngineJSON.point3(Vec3(0, 0, cutZ)), capNormal = EngineJSON.point3(Vec3(0, 0, 1))
        let caps = try await s.call("view3d.sectionCaps", obj([("point", capPoint), ("normal", capNormal)]))
        XCTAssertGreaterThan(caps["triangleCount"]?.intValue ?? 0, 10)
        let f = EngineMeshJSON.decodeFloats(caps["positions"]?.stringValue ?? "")
        XCTAssertEqual(f.count, (caps["triangleCount"]?.intValue ?? 0) * 9)
        XCTAssertEqual(Double(f[2]), cutZ - 0.5, accuracy: 0.01)
        // Gizmo commits: a wall moved along X, then up (one undo step each).
        let wall = try XCTUnwrap(s.editor.doc.elements.first { if case .wall = $0.geometry { return true }; return false })
        let before = wall.geometry
        let moveParams = obj([("op", .string("move")), ("axis", .int(0)), ("amount", .number(250)), ("ids", .ints([wall.id]))])
        let r = try await s.call("view3d.transform", moveParams)
        XCTAssertEqual(r["changed"]?.intValue, 1)
        XCTAssertNotEqual(s.editor.doc.element(wall.id)?.geometry, before)
        XCTAssertTrue(s.editor.log.contains("Moved 1 object(s) by 250 along X."))
        _ = try await s.call("view3d.transform", obj([("op", .string("movez")), ("amount", .number(50)), ("ids", .ints([wall.id]))]))
        if case .wall(let w) = s.editor.doc.element(wall.id)?.geometry, case .wall(let w0) = before {
            let expected: Double = w0.baseOffset + 50
            XCTAssertEqual(w.baseOffset, expected, accuracy: 1e-9)
        }
        _ = try await s.call("edit.undo")
        _ = try await s.call("edit.undo")
        XCTAssertEqual(s.editor.doc.element(wall.id)?.geometry, before)
        // Binary transfer to a temporary file chosen by the engine, with the layout and element levels.
        let m1 = try await s.call("model.meshes", obj([("lod", .int(2)), ("binary", .bool(true))]))
        let p1 = try XCTUnwrap(m1["binary"]?.stringValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p1))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: p1)).count, m1["binaryLength"]?.intValue)
        XCTAssertEqual(m1["layout"]?["byteOrder"]?.stringValue, "little-endian")
        XCTAssertTrue(m1["meshes"]?.arrayValue?.contains { $0["level"]?.intValue != nil } ?? false)
        let m2 = try await s.call("model.meshes", obj([("lod", .int(2)), ("binary", .bool(true))]))
        let p2 = try XCTUnwrap(m2["binary"]?.stringValue)
        XCTAssertNotEqual(p1, p2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: p1), "the previous transfer file is removed")
        try? FileManager.default.removeItem(atPath: p2)
    }

    @MainActor func testView3DPortableCommands() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let (s, sink) = dialogSession()
        _ = try await s.call("doc.open", obj([("path", .string(Self.cedarHouse.path))]))
        func last(_ op: String) -> EngineJSON? { s.flushNotifications(); return hostActions(sink).last { $0["action"]?.stringValue == "view3d" && $0["op"]?.stringValue == op } }
        _ = try await s.call("command.run", obj([("line", .string("GIZMO3D Rotate"))]))
        XCTAssertEqual(last("gizmo")?["mode"]?.stringValue, "Rotate")
        _ = try await s.call("command.run", obj([("line", .string("MEASURE3D On"))]))
        XCTAssertEqual(last("measure")?["on"], .bool(true))
        XCTAssertTrue(s.editor.log.contains("Click two points on the model in the 3D view."))
        var info = try await s.call("view3d.info")
        XCTAssertEqual(info["gizmo"]?.stringValue, "Off", "measuring turns the gizmo off")
        _ = try await s.call("command.run", obj([("line", .string("LEVELVIEW3D Explode 3000"))]))
        XCTAssertEqual(last("levels")?["explodeGap"]?.doubleValue, 3000)
        XCTAssertTrue(s.editor.log.contains("Levels exploded by 3000."))
        _ = try await s.call("command.run", obj([("line", .string("WEATHER Snow 0.6 0.5"))]))
        XCTAssertEqual(s.editor.doc.variable("WEATHER"), "Snow;0.6;Summer;0.5")
        _ = try await s.call("command.run", obj([("line", .string("SEASON Autumn"))]))
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["weather"]?["season"]?.stringValue, "Autumn")
        XCTAssertEqual(info["weather"]?["particles"]?["life"]?.doubleValue, 12)
        // Cameras: SAVECAMERA needs the shell's camera; CAMERA restores through the shell.
        _ = try await s.call("command.run", obj([("line", .string("SAVECAMERA Test"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Open the 3D view first.") })
        let camEye = EngineJSON.point3(Vec3(-9000, -12000, 6000)), camTarget = EngineJSON.point3(Vec3(0, 0, 0))
        _ = try await s.call("view3d.setCamera", obj([("eye", camEye), ("target", camTarget), ("fov", .number(50))]))
        _ = try await s.call("command.run", obj([("line", .string("SAVECAMERA Test"))]))
        XCTAssertTrue(s.editor.log.contains("Camera “Test” saved."))
        XCTAssertEqual(s.editor.doc.namedViews.first { $0.name == "Test" }?.camera?.fov, 50)
        _ = try await s.call("command.run", obj([("line", .string("CAMERA Test"))]))
        XCTAssertEqual(last("camera")?["camera"]?["fov"]?.doubleValue, 50)
        let cams = try await s.call("view3d.deleteCamera", obj([("name", .string("Test"))]))
        XCTAssertFalse(cams.arrayValue?.contains { $0["name"]?.stringValue == "Test" } ?? true)
        _ = try await s.call("command.run", obj([("line", .string("FOV 35"))]))
        XCTAssertEqual(last("fov")?["fov"]?.doubleValue, 35)
        XCTAssertTrue(s.editor.log.contains("Field of view 35° (38 mm lens)."))
        _ = try await s.call("command.run", obj([("line", .string("SECTIONBOX Reset"))]))
        XCTAssertTrue(s.editor.doc.variable("SECTIONBOX")?.hasPrefix("on;") ?? false)
        _ = try await s.call("command.run", obj([("line", .string("SECTIONPLANE Horizontal 1500"))]))
        XCTAssertEqual(s.editor.doc.variable("SECTIONPLANE"), "on;0,0,1500;0,0,1")
        _ = try await s.call("command.run", obj([("line", .string("SECTIONPLANE Flip"))]))
        XCTAssertEqual(s.editor.doc.variable("SECTIONPLANE"), "on;0,0,1500;0,0,-1")
        // Object animation of a door, with the leaf the shell needs to swing it.
        if let door = s.editor.doc.elements.first(where: { e in if case .opening(let o) = e.geometry { return o.kind == .door && o.doorStyle == .single }; return false }),
           !EngineDoorLeaves.leaves(door, doc: s.editor.doc).isEmpty {
            _ = try await s.call("select.set", obj([("ids", .ints([door.id]))]))
            _ = try await s.call("command.run", obj([("line", .string("ANIMATE Door"))]))
            for t in ["0", "2", "Yes", "90"] { _ = try await s.call("input.text", obj([("text", .string(t))])) }
            XCTAssertTrue(s.editor.log.contains("1 door(s) animated."), s.editor.log.suffix(6).joined(separator: " | "))
            info = try await s.call("view3d.info")
            XCTAssertEqual(info["animations"]?[0]?["kind"]?.stringValue, "Door")
            XCTAssertNotNil(info["animations"]?[0]?["leaf"]?["hinge"])
            _ = try await s.call("command.run", obj([("line", .string("ANIMATE Play"))]))
            XCTAssertEqual(last("animate")?["play"], .bool(true))
        }
        // Images the shell renders are written by the engine.
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("archi-v3d-\(UUID().uuidString)/pano.jpg")
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let jpegBytes = Data([0xFF, 0xD8, 0xFF]).base64EncodedString()
        let w = try await s.call("view3d.saveImage", obj([("path", .string(out.path)), ("data", .string(jpegBytes))]))
        XCTAssertEqual(w["bytes"]?.intValue, 3)
        XCTAssertEqual(try Data(contentsOf: out).count, 3)
        _ = try await s.call("command.run", obj([("line", .string("STEREOPANORAMA Camera 1024 64 " + out.path))]))
        let pano = last("panorama")
        XCTAssertEqual(pano?["stereo"], .bool(true))
        XCTAssertEqual(pano?["width"]?.intValue, 1024)
        XCTAssertEqual(pano?["path"]?.stringValue, out.path)
    }
}
