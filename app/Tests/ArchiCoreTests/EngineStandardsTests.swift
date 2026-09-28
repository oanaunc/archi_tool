// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine graphic standards, clipboard and sharing (Host/EngineStandards.swift, EngineStandardsCommands.swift):
// the Graphic Styles, Object Styles, Material Fill Patterns and Image Adjust dialogs, custom visual styles, the
// lineweight display scale, Paste from Other App, Copy as Picture, Share, Describe Drawing, node packages, the AR
// export and the rendered shade plot drawn without the shell.
import XCTest
@testable import ArchiCore

extension EngineSessionTests {
    @MainActor func testStandardsGraphicStylesDialogs() async throws {
        let (s, sink) = dialogSession()
        func last(_ action: String) -> EngineJSON? { s.flushNotifications(); return hostActions(sink).last { $0["action"]?.stringValue == action } }
        for m in EngineStandardsMethods.all {
            let h = try await s.call("engine.hello")
            XCTAssertTrue(h["methods"]?.arrayValue?.contains(.string(m)) ?? false, m)
        }
        _ = try await s.call("command.run", obj([("line", .string("GRAPHICSTYLES"))]))
        XCTAssertEqual(last("dialog")?["dialog"]?.stringValue, "graphicStyles")
        // Line styles and their layers.
        var g = try await s.call("graphicstyles.edit", obj([("op", .string("addLineStyle")), ("name", .string("Walls"))]))
        XCTAssertEqual(s.editor.history.undoLabel, "New Line Style")
        let key = try XCTUnwrap(g["lineStyles"]?[0]?["key"]?.stringValue)
        XCTAssertEqual(g["lineStyles"]?[0]?["lineweight"]?.doubleValue, 0.25)
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setLineStyle")), ("key", .string(key)), ("lineweight", .number(9)), ("color", .string("1"))]))
        XCTAssertEqual(g["lineStyles"]?[0]?["lineweight"]?.doubleValue, 5, "clamped to 5 mm")
        XCTAssertEqual(g["lineStyles"]?[0]?["color"]?.stringValue, "1")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setLayerLineStyle")), ("layer", .string("0")), ("style", .string("Walls"))]))
        XCTAssertEqual(g["layers"]?.arrayValue?.first { $0["name"]?.stringValue == "0" }?["lineStyle"]?.stringValue, "Walls")
        // Lineweights by scale.
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setLwTable")), ("text", .string("1:50=1; 1:100=0.7"))]))
        XCTAssertEqual(g["message"]?.stringValue, "2 row(s).")
        XCTAssertEqual(g["lwRows"]?[1]?["text"]?.stringValue, "1:100 → × 0.7")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setLwTable")), ("text", .string("nonsense"))]))
        XCTAssertEqual(g["message"]?.stringValue, "No valid rows (use 1:50=1).")
        // Pen sets.
        g = try await s.call("graphicstyles.edit", obj([("op", .string("savePenSet")), ("name", .string("Print")), ("pens", .string("1=0.18;7=0.5"))]))
        XCTAssertEqual(g["message"]?.stringValue, "Pen set Print: 2 pen(s).")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setActivePenSet")), ("name", .string("Print"))]))
        XCTAssertEqual(g["activePenSet"]?.stringValue, "Print")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setPenSetDisplay")), ("on", .bool(true))]))
        XCTAssertEqual(g["penSetDisplay"], .bool(true))
        // Graphic override filters.
        g = try await s.call("graphicstyles.edit", obj([("op", .string("addFilter")), ("name", .string("Red")), ("value", .string(""))]))
        XCTAssertEqual(g["message"]?.stringValue, "Give a value and an override.")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("addFilter")), ("name", .string("Red")), ("field", .string("layer")), ("operator", .string("=")),
                                                        ("value", .string("0")), ("color", .string("#ff0000")), ("halftone", .bool(true))]))
        XCTAssertEqual(g["message"]?.stringValue, "Rule Red added.")
        XCTAssertEqual(g["filters"]?[0]?["effect"]?.stringValue, "#FF0000, halftone")
        _ = try await s.call("graphicstyles.edit", obj([("op", .string("addFilter")), ("name", .string("Hide")), ("value", .string("A-")), ("hide", .bool(true))]))
        g = try await s.call("graphicstyles.edit", obj([("op", .string("raiseFilter")), ("index", .int(1))]))
        XCTAssertEqual(g["filters"]?[0]?["name"]?.stringValue, "Hide")
        g = try await s.call("graphicstyles.edit", obj([("op", .string("setFilterEnabled")), ("index", .int(0)), ("enabled", .bool(false))]))
        XCTAssertEqual(g["filters"]?[0]?["enabled"], .bool(false))
        g = try await s.call("graphicstyles.edit", obj([("op", .string("deleteFilter")), ("index", .int(0))]))
        XCTAssertEqual(g["filters"]?.arrayValue?.count, 1)
        XCTAssertEqual(s.editor.history.undoLabel, "Graphic Filter")
        _ = try await s.call("edit.undo")
        XCTAssertEqual(GraphicStyles.filters(s.editor.doc).count, 2, "every edit is one undo step")

        // Object styles.
        _ = try await s.call("command.run", obj([("line", .string("OBJECTSTYLESDIALOG"))]))
        XCTAssertEqual(last("dialog")?["dialog"]?.stringValue, "objectStyles")
        let os = try await s.call("objectstyles.get")
        XCTAssertEqual(os["rows"]?[0]?["category"]?.stringValue, "wall")
        XCTAssertEqual(os["rows"]?[0]?["title"]?.stringValue, "Wall")
        let bad = try await s.call("objectstyles.set", obj([("rows", .array([obj([("category", .string("wall")), ("cut", .string("x"))])]))]))
        XCTAssertEqual(bad["ok"], .bool(false))
        XCTAssertEqual(bad["message"]?.stringValue, "Check: wall: cut lineweight")
        let row = obj([("category", .string("wall")), ("cut", .string("0,7")), ("projection", .string("")), ("color", .null), ("fill", .string("#202020")), ("pattern", .string("ANSI31"))])
        let good = try await s.call("objectstyles.set", obj([("rows", .array([row]))]))
        XCTAssertEqual(good["message"]?.stringValue, "1 category styled.")
        XCTAssertEqual(ObjectStyles.style("wall", doc: s.editor.doc)?.cutLineweight, 0.7)
        XCTAssertEqual(good["data"]?["rows"]?[0]?["fill"]?.stringValue, "#202020")
        XCTAssertEqual(s.editor.history.undoLabel, "Object Styles")

        // Material fill patterns.
        _ = try await s.call("command.run", obj([("line", .string("MATPATTERNDIALOG"))]))
        XCTAssertEqual(last("dialog")?["dialog"]?.stringValue, "matPatterns")
        let mp = try await s.call("matpatterns.get")
        if let name = mp["rows"]?[0]?["name"]?.stringValue {
            let r = try await s.call("matpatterns.set", obj([("rows", .array([obj([("name", .string(name)), ("cut", .string("AR-CONC")), ("surface", .string(""))])]))]))
            XCTAssertEqual(MaterialPatterns.pattern(name, kind: .cut, doc: s.editor.doc), "AR-CONC")
            XCTAssertTrue(r["message"]?.stringValue?.hasSuffix("changed.") ?? false)
        }

        // Custom visual styles.
        _ = try await s.call("command.run", obj([("line", .string("VISUALSTYLES New Ghost Shaded Yes 30 No #FF0000"))]))
        var vs = try await s.call("visualstyles.list")
        XCTAssertEqual(vs["custom"]?[0]?["name"]?.stringValue, "Ghost")
        XCTAssertEqual(vs["custom"]?[0]?["faceOpacity"]?.doubleValue, 0.3)
        XCTAssertEqual(vs["custom"]?[0]?["edgeColor"]?.stringValue, "#FF0000")
        XCTAssertEqual(vs["menu"]?.arrayValue?.last?.stringValue, "Ghost")
        XCTAssertTrue(s.editor.log.contains("Visual style Ghost saved. VISUALSTYLES Current Ghost shows it."))
        _ = try await s.call("command.run", obj([("line", .string("VISUALSTYLES Current ghost"))]))
        let cur = try XCTUnwrap(last("visualStyle"))
        XCTAssertEqual(cur["name"]?.stringValue, "Ghost")
        XCTAssertEqual(cur["base"]?.stringValue, "Shaded")
        XCTAssertEqual(cur["custom"]?["shadows"], .bool(false))
        _ = try await s.call("command.run", obj([("line", .string("VISUALSTYLES Current xray"))]))
        XCTAssertEqual(last("visualStyle")?["name"]?.stringValue, "X-Ray")
        XCTAssertEqual(last("visualStyle")?["custom"], .null)
        _ = try await s.call("command.run", obj([("line", .string("VISUALSTYLES Current Nope"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Unknown style Nope.") })
        _ = try await s.call("command.run", obj([("line", .string("VISUALSTYLES Delete Ghost"))]))
        vs = try await s.call("visualstyles.list")
        XCTAssertEqual(vs["custom"]?.arrayValue?.count, 0)
        XCTAssertNil(s.editor.doc.variable("VISUALSTYLES"))

        // Lineweight display scale (an application setting the shell keeps).
        _ = try await s.call("command.run", obj([("line", .string("LWDISPLAYSCALE 2"))]))
        XCTAssertEqual(last("preference")?["key"]?.stringValue, "lwDisplayScale")
        XCTAssertEqual(last("preference")?["value"]?.doubleValue, 2)
        XCTAssertTrue(s.editor.log.contains("Lineweight display scale 2."))
        _ = try await s.call("command.run", obj([("line", .string("LWDISPLAYSCALE 9"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("Requires a value from 0.1 to 5.") })
        EngineSession.uiPreferences["lwDisplayScale"] = nil
    }

    @MainActor func testStandardsClipboardShareAndSpeech() async throws {
        let (s, sink) = dialogSession()
        func last(_ action: String) -> EngineJSON? { s.flushNotifications(); return hostActions(sink).last { $0["action"]?.stringValue == action } }
        try await line(s, "LINE 0,0 4000,0 4000,3000")
        // Copy as Picture: the whole drawing (Enter at the selection prompt).
        _ = try await s.call("command.run", obj([("line", .string("COPYPICTURE"))]))
        if !s.editor.isIdle { _ = try await s.call("input.key", obj([("key", .string("Enter"))])) }
        let pic = try XCTUnwrap(last("copyPicture"))
        let pdfPath = try XCTUnwrap(pic["pdf"]?.stringValue)
        XCTAssertEqual(String(decoding: try Data(contentsOf: URL(fileURLWithPath: pdfPath)).prefix(4), as: UTF8.self), "%PDF")
        XCTAssertTrue(pic["svg"]?.stringValue?.contains("<svg") ?? false)
        XCTAssertEqual(pic["ratio"]?.doubleValue, 20, "4 m fits 280 mm at 1:20")
        XCTAssertTrue(s.editor.log.contains("Copied the drawing as a PDF at 1:20 and a PNG picture."), s.editor.log.suffix(3).joined(separator: " | "))
        let made = try await s.call("copypicture.make", obj([("ids", .ints(s.editor.doc.entities.map(\.id)))]))
        XCTAssertGreaterThan(made["width"]?.doubleValue ?? 0, 0)

        // Paste from Other App.
        EngineSession.uiPreferences["clipboardExternal"] = "0"
        _ = try await s.call("command.run", obj([("line", .string("PASTESPECIAL"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("The clipboard holds nothing from another app") })
        EngineSession.uiPreferences["clipboardExternal"] = "1"
        _ = try await s.call("command.run", obj([("line", .string("PASTESPECIAL 500,500"))]))
        XCTAssertEqual(last("pasteSpecial")?["x"]?.doubleValue, 500)
        EngineSession.uiPreferences["clipboardExternal"] = nil
        let before = s.editor.doc.entities.count
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><line x1="0" y1="0" x2="100" y2="50" stroke="black"/></svg>"#
        let pasted = try await s.call("clipboard.paste", obj([("type", .string("svg")), ("data", .string(Data(svg.utf8).base64EncodedString())), ("x", .number(500)), ("y", .number(500))]))
        XCTAssertEqual(pasted["ok"], .bool(true))
        XCTAssertGreaterThan(s.editor.doc.entities.count, before)
        XCTAssertEqual(s.editor.history.undoLabel, "Paste SVG")
        XCTAssertTrue(s.editor.log.last?.hasPrefix("Pasted ") ?? false)
        let text = try await s.call("clipboard.paste", obj([("type", .string("text")), ("data", .string(Data("Kitchen".utf8).base64EncodedString())), ("x", .number(0)), ("y", .number(-1000))]))
        XCTAssertEqual(text["ok"], .bool(true))

        // Share: a snapshot of the project and a PDF of the drawing.
        _ = try await s.call("command.run", obj([("line", .string("SHARE Both"))]))
        let paths = (last("share")?["paths"]?.arrayValue ?? []).compactMap(\.stringValue)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].hasSuffix(".archi") && paths[1].hasSuffix(".pdf"))
        for p in paths { XCTAssertTrue(FileManager.default.fileExists(atPath: p), p) }
        XCTAssertEqual(String(decoding: try Data(contentsOf: URL(fileURLWithPath: paths[1])).prefix(4), as: UTF8.self), "%PDF")
        _ = try? FileManager.default.removeItem(at: URL(fileURLWithPath: paths[0]).deletingLastPathComponent())

        // Describe Drawing (spoken by the shell).
        EngineSession.uiPreferences["viewMode"] = "2D"
        _ = try await s.call("select.set", obj([("ids", .ints([s.editor.doc.entities[0].id]))]))
        _ = try await s.call("command.run", obj([("line", .string("SPEAKDRAWING"))]))
        let spoken = try XCTUnwrap(last("speak")?["text"]?.stringValue)
        XCTAssertTrue(spoken.hasPrefix("Plan, "), spoken)
        XCTAssertTrue(spoken.contains("Selected: 1 "), spoken)
        XCTAssertTrue(spoken.contains("Ready for a command."), spoken)
        XCTAssertTrue(s.editor.log.contains(spoken))
        EngineSession.uiPreferences["viewMode"] = nil
        let described = try await s.call("drawing.describe")
        XCTAssertTrue(described["text"]?.stringValue?.contains("drawing objects") ?? false)
    }

    @MainActor func testStandardsNodePackagesImagesAndAR() async throws {
        let (s, sink) = dialogSession()
        func last(_ action: String) -> EngineJSON? { s.flushNotifications(); return hostActions(sink).last { $0["action"]?.stringValue == action } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-nodepkg-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir); EngineSession.uiPreferences["nodePackagesFolder"] = nil }
        EngineSession.uiPreferences["nodePackagesFolder"] = dir.appendingPathComponent("Library").path
        _ = try await s.call("command.run", obj([("line", .string("NODEPACKAGE List"))]))
        XCTAssertTrue(s.editor.log.contains("No node packages installed."))
        var graph = NodeGraph()
        graph.nodes = [GraphNode(id: 1, kind: .number, x: 10, y: 10), GraphNode(id: 2, kind: .rectangle, x: 200, y: 10)]
        graph.links = [GraphLink(from: 1, to: 2, port: "width")]
        graph.nextID = 3
        s.editor.transaction("Graph") { graph.store(in: &$0) }
        let file = dir.appendingPathComponent("Shapes.archinodes").path
        func answer(_ line: String, _ inputs: [String]) async throws {
            _ = try await s.call("command.run", obj([("line", .string(line))]))
            for t in inputs { _ = try await s.call("input.text", obj([("text", .string(t))])) }
        }
        try await answer("NODEPACKAGE Create", ["Shapes", file])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file), s.editor.log.suffix(3).joined(separator: " | "))
        XCTAssertEqual(EngineNodePackages.installed().first?.name, "Shapes")
        let json = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertTrue(json.contains("\"format\" : \"oanarina-archi-nodes\""), json)
        try await answer("NODEPACKAGE Insert", ["Shapes", "Shapes"])
        XCTAssertEqual(NodeGraph.load(s.editor.doc)?.nodes.count, 4)
        XCTAssertEqual(NodeGraph.load(s.editor.doc)?.links.count, 2)
        XCTAssertTrue(s.editor.log.contains("Inserted Shapes: 2 node(s). Open the Node Editor to connect and bake it."))
        try await answer("NODEPACKAGE Remove", ["Shapes"])
        XCTAssertTrue(EngineNodePackages.installed().isEmpty)
        try await answer("NODEPACKAGE Install", [file])
        XCTAssertTrue(s.editor.log.contains("Installed Shapes 1.0: 1 snippet(s)."))

        // Image Adjust.
        var iid: EntityID = 0
        s.editor.transaction("Add") { d in iid = d.add(.image(ImageGeom(path: "missing.png", origin: Vec2(0, 0), size: Vec2(1000, 500)))) }
        _ = try await s.call("select.set", obj([("ids", .ints([iid]))]))
        _ = try await s.call("command.run", obj([("line", .string("IMAGEADJUSTDIALOG"))]))
        XCTAssertEqual(last("dialog")?["dialog"]?.stringValue, "imageAdjust")
        XCTAssertEqual(last("dialog")?["ids"], EngineJSON.ints([iid]))
        var ia = try await s.call("imageadjust.get", obj([("ids", .ints([iid]))]))
        XCTAssertEqual(ia["brightness"]?.doubleValue, 50)
        let set = try await s.call("imageadjust.set", obj([("ids", .ints([iid])), ("brightness", .number(70)), ("contrast", .number(40)), ("fade", .number(120))]))
        XCTAssertEqual(set["message"]?.stringValue, "1 image adjusted.")
        ia = try await s.call("imageadjust.get", obj([("ids", .ints([iid]))]))
        XCTAssertEqual(ia["fade"]?.doubleValue, 100, "clamped like the sliders")
        XCTAssertEqual(s.editor.history.undoLabel, "Image Adjust")

        // AR view: a real-scale glTF opened by the Windows 3D viewer.
        try await line(s, "WALL 0,0 5000,0")
        _ = try await s.call("command.run", obj([("line", .string("ARQUICKLOOK Preview"))]))
        let glb = try XCTUnwrap(last("openFile")?["path"]?.stringValue)
        XCTAssertTrue(glb.hasSuffix(".glb"))
        XCTAssertEqual(String(decoding: try Data(contentsOf: URL(fileURLWithPath: glb)).prefix(4), as: UTF8.self), "glTF")
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("glTF at real-world scale (0.001 m per unit)") })
    }

    @MainActor func testStandardsShadePlotRenderedWithoutShell() async throws {
        let s = EngineSession()
        try await line(s, "WALL 0,0 5000,0 5000,4000")
        let oldPixels = EngineShadePlot.fallbackMaxPixels, oldPasses = EngineShadePlot.fallbackPasses
        EngineShadePlot.fallbackMaxPixels = 40
        EngineShadePlot.fallbackPasses = 1
        defer { EngineShadePlot.fallbackMaxPixels = oldPixels; EngineShadePlot.fallbackPasses = oldPasses }
        _ = try await s.call("command.run", obj([("line", .string("LAYOUT New \"A-301\""))]))
        s.editor.transaction("Viewport") { d in
            d.layouts[d.layouts.count - 1].viewports.append(Viewport(origin: Vec2(20, 20), size: Vec2(150, 100), viewCenter: Vec2(0, 0), scale: 100, view: .axonometric, level: nil))
            d.setVariable(EngineShadePlot.key(d.layouts[d.layouts.count - 1].name, 0), "Rendered")
        }
        let layout = s.editor.doc.layouts[s.editor.doc.layouts.count - 1]
        let ents = EngineShadePlot.entries(doc: s.editor.doc, vp: layout.viewports[0], layout: layout.name, index: 0)
        let images = ents.flatMap(\.items).compactMap { it -> ImageGeom? in if case .image(let im) = it { return im }; return nil }
        let im = try XCTUnwrap(images.first, "a path-traced image replaces the hidden-line drawing")
        let png = try Data(contentsOf: URL(fileURLWithPath: im.path))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(im.size.x, 0)
        // Cached: the same file for the same drawing and camera.
        let again = EngineShadePlot.entries(doc: s.editor.doc, vp: layout.viewports[0], layout: layout.name, index: 0)
        let path2 = again.flatMap(\.items).compactMap { it -> String? in if case .image(let x) = it { return x.path }; return nil }.first
        XCTAssertEqual(path2, im.path)
    }
}
