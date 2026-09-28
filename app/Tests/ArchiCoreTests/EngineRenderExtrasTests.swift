// Oanarina Archi Tool — GPL-3.0-or-later
// The portable render, material and environment commands of archi-engine (Host/EngineRenderExtras.swift): LIGHT, FOG,
// MATEMISSIVE, MATMAPPING, BILLBOARD, MATMAPS, MATASSET, WATER, SCATTER, RENDERPROMPT, PROCMATERIAL, AODIALOG,
// PHASEANIMATION, MECHANISMPLAY and the render.* methods the Windows shell calls for them.
import XCTest
@testable import ArchiCore

extension EngineSessionTests {
    @MainActor func testRenderExtrasCommands() async throws {
        let (s, sink) = dialogSession()
        func run(_ line: String) async throws { _ = try await s.call("command.run", obj([("line", .string(line))])) }
        /// A command answered prompt by prompt (text prompts take the rest of a command line, as on the Mac).
        func answer(_ command: String, _ inputs: [String]) async throws {
            try await run(command)
            for t in inputs { _ = try await s.call("input.text", obj([("text", .string(t))])) }
        }
        func lastHost(_ action: String) -> EngineJSON? { s.flushNotifications(); return hostActions(sink).last { $0["action"]?.stringValue == action } }
        s.editor.doc.materials = [Material(name: "Limestone", color: RGBA(0.87, 0.84, 0.77)), Material(name: "Lamp", color: RGBA(1, 0.82, 0.58))]

        // Lights: a point light as an entity with the Mac's properties, listed and exported with the meshes.
        try await run("LIGHT Point 1000,2000 2400 900 3000")
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Point light #") && $0.hasSuffix(": 900 lm, 3000 K.") }, s.editor.log.suffix(3).joined(separator: " | "))
        let light = s.editor.doc.entities.first { $0.props["light"] == "point" }
        XCTAssertEqual(light?.props["lumens"], "900")
        XCTAssertEqual(light?.props["z"], "2400")
        XCTAssertEqual(light?.layer, "LIGHTS")
        XCTAssertEqual(EngineMeshJSON.lights(s.editor.doc).arrayValue?.first?["lumens"]?.doubleValue, 900)
        try await run("LIGHT Off")
        XCTAssertEqual(s.editor.doc.variable("ARTIFICIALLIGHTS"), "0")
        XCTAssertTrue(s.editor.log.contains("Artificial lights off."))
        try await run("LIGHT On")

        // Fog, emissive materials, texture mapping.
        try await run("FOG On 4000 50000 #C7CCD6 2")
        XCTAssertEqual(s.editor.doc.variable("FOG"), "1")
        XCTAssertEqual(s.editor.doc.variable("FOGEND"), "50000")
        XCTAssertEqual(s.editor.doc.variable("FOGDENSITY"), "2")
        XCTAssertTrue(s.editor.log.contains("Fog from 4000 to 50000, #C7CCD6."))
        try await run("MATEMISSIVE Lamp 5")
        XCTAssertEqual(s.editor.doc.variable("MATEMIT:LAMP"), "5")
        XCTAssertTrue(s.editor.log.contains("Lamp glows with factor 5."))
        try await run("MATMAPPING Limestone Planar 100 0 45 2")
        XCTAssertEqual(s.editor.doc.variable("MATMAP:LIMESTONE"), "Planar;100,0;45;2")
        try await run("MATMAPPING Limestone Reset")
        XCTAssertNil(s.editor.doc.variable("MATMAP:LIMESTONE"))

        // Billboards reach the shell through view3d.info.
        try await run("BILLBOARD Tree 5000,5000 6000")
        var info = try await s.call("view3d.info")
        XCTAssertEqual(info["billboards"]?[0]?["source"]?.stringValue, "tree")
        XCTAssertEqual(info["billboards"]?[0]?["height"]?.doubleValue, 6000)
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Billboard #") && $0.hasSuffix("(tree, 6000 high).") })

        // PBR maps and material assets (the Mac JSON with sorted keys).
        try await answer("MATMAPS", ["Limestone", "Strength", "0.5"])
        XCTAssertEqual(s.editor.doc.variable("MATMAPS:LIMESTONE"), "{\"displacementScale\":0,\"normalStrength\":0.5}")
        try await answer("MATASSET", ["Limestone", "Physical", "2600", "2.3", "1000"])
        let asset = try EngineJSON.parse(s.editor.doc.variable("MATASSET:LIMESTONE") ?? "")
        XCTAssertEqual(asset["density"]?.doubleValue, 2600)
        XCTAssertEqual(asset["conductivity"]?.doubleValue, 2.3)
        try await answer("MATASSET", ["Limestone", "List"])
        XCTAssertTrue(s.editor.log.contains { $0.contains("physical: ρ 2600 kg/m³, λ 2.3 W/mK") }, s.editor.log.suffix(3).joined(separator: " | "))

        // Water from picked points (Enter closes), with the Water material marked as water.
        _ = try await s.call("command.run", obj([("line", .string("WATER Points"))]))
        for t in ["0,0", "4000,0", "4000,3000", "0,3000", "", "-100", "1500"] { _ = try await s.call("input.text", obj([("text", .string(t))])) }
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Water #") && $0.contains("12 m² at elevation -100") }, s.editor.log.suffix(3).joined(separator: " | "))
        XCTAssertEqual(s.editor.doc.variable("MATWATER:WATER"), "1")
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["water"]?.arrayValue?.first?.stringValue, "Water")

        // Scatter: Poisson-disk plants in a boundary, reproducible for a seed.
        let square = [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 10000), Vec2(0, 10000)]
        let a = EngineScatter.entities("Shrubs", boundary: square, density: 1.2, z: 0, height: 900, seed: 7)
        let b = EngineScatter.entities("Shrubs", boundary: square, density: 1.2, z: 0, height: 900, seed: 7)
        XCTAssertGreaterThan(a.count, 40)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(a.entities.first?.props["material"], "Shrub Foliage")
        let poly = s.editor.doc.add(Entity(layer: "0", geometry: .polyline(PolylineGeom(points: square, closed: true))))
        _ = try await s.call("select.set", obj([("ids", .ints([poly]))]))
        _ = try await s.call("command.run", obj([("line", .string("SCATTER Trees"))]))
        for t in ["0.05", "7000", "0", "3"] { _ = try await s.call("input.text", obj([("text", .string(t))])) }
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("Scattered ") && $0.hasSuffix(" trees over 1 area(s).") }, s.editor.log.suffix(3).joined(separator: " | "))
        XCTAssertTrue(s.editor.doc.entities.contains { $0.props["scatter"] == "Trees" && $0.props["material"] == "Tree Foliage" })

        // Render prompt → the "Prompt: …" preset for the Render window.
        try await run("RENDERPROMPT \"golden hour, soft shadows, 4K\"")
        let prompt = lastHost("output")
        XCTAssertEqual(prompt?["op"]?.stringValue, "renderPrompt")
        XCTAssertEqual(prompt?["preset"]?["environment"]?.stringValue, "Sunset")
        XCTAssertEqual(prompt?["preset"]?["width"]?.intValue, 3840)
        XCTAssertEqual(prompt?["preset"]?["shadowSoftness"]?.doubleValue, 10)
        XCTAssertTrue(s.editor.log.contains("Render style: sunset sky, 19:30, warm, soft shadows, 4K."))
        let ps = try await s.call("render.promptSettings", obj([("text", .string("clay massing, white background"))]))
        XCTAssertEqual(ps["preset"]?["clay"], .bool(true))
        XCTAssertEqual(ps["preset"]?["background"]?.stringValue, "White")

        // Procedural material and material from a photo: the shell generates the maps.
        try await answer("PROCMATERIAL", ["Tile", "Floor Tile", "#E6E6E0", "#9E9E99", "600", "4", "4", "0.01", "3"])
        let proc = lastHost("materials")
        XCTAssertEqual(proc?["op"]?.stringValue, "procedural")
        XCTAssertEqual(proc?["params"]?["kind"]?.stringValue, "Tile")
        XCTAssertEqual(proc?["params"]?["tileSize"]?.doubleValue, 600)
        XCTAssertEqual(proc?["params"]?["seed"]?.intValue, 3)
        XCTAssertTrue(s.editor.log.contains("Material Floor Tile: tile 4×4, tile 600 mm, seed 3 (albedo, normal and roughness maps)."))

        // Ambient occlusion dialog and its settings.
        try await run("AODIALOG")
        XCTAssertEqual(lastHost("dialog")?["dialog"]?.stringValue, "ambientOcclusion")
        let ao = try await s.call("render.aoSet", obj([("intensity", .number(1.5)), ("radius", .number(500)), ("samples", .int(32))]))
        XCTAssertEqual(ao["message"]?.stringValue, "Ambient occlusion 1.5.")
        XCTAssertEqual(s.editor.doc.variable("AOINTENSITY"), "1.5")
        info = try await s.call("view3d.info")
        XCTAssertEqual(info["ambientOcclusion"]?["viewport"]?["intensity"]?.doubleValue ?? 0, 1.35, accuracy: 1e-9)
        XCTAssertEqual(info["ambientOcclusion"]?["viewport"]?["radius"]?.doubleValue ?? 0, 0.5, accuracy: 1e-9)

        // 4D video needs phases or a work schedule; mechanisms need a named driving dimension.
        try await run("PHASEANIMATION")
        XCTAssertTrue(s.editor.log.contains { $0.contains("No phased elements and no work schedule") }, s.editor.log.suffix(2).joined(separator: " | "))
        _ = try await s.call("command.run", obj([("line", .string("MECHANISMPLAY"))]))
        _ = try await s.call("input.text", obj([("text", .string("crank"))]))
        XCTAssertTrue(s.editor.log.contains { $0.contains("No dimensional constraint with that name.") }, s.editor.log.suffix(2).joined(separator: " | "))
        let done = try await s.call("render.mechanismDone")
        XCTAssertEqual(done, .object([]))
    }

    @MainActor func testRenderExtrasIESAndPhaseFrames() async throws {
        let (s, _) = dialogSession()
        // IES (LM-63): a narrow downlight, 1000 lm, peak 2000 cd straight down.
        let ies = "IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 5 1 1 2 0 0 0\n1 1 50\n0 15 30 60 90\n0\n2000 1800 900 100 0\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-ies-\(UUID().uuidString).ies")
        try Data(ies.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = try await s.call("render.iesProfile", obj([("path", .string(url.path))]))
        XCTAssertEqual(p["maxCandela"]?.doubleValue, 2000)
        XCTAssertEqual(p["lumens"]?.doubleValue, 1000)
        XCTAssertEqual(p["relative"]?.arrayValue?.count, 5)
        XCTAssertEqual(p["beam"]?.doubleValue ?? 0, 57, accuracy: 1.5)
        // The light command stores the file; the meshes export its distribution for the shell.
        s.editor.doc.materials = [Material(name: "Concrete", color: RGBA(0.7, 0.7, 0.7))]
        _ = try await s.call("command.run", obj([("line", .string("LIGHT IES 0,0 0,1000 2400 \"" + url.path + "\" 1000 3000"))]))
        XCTAssertTrue(s.editor.log.contains { $0.hasPrefix("IES: 2000 cd peak, 1000 lm, beam ") }, s.editor.log.suffix(3).joined(separator: " | "))
        let l = EngineMeshJSON.lights(s.editor.doc).arrayValue?.first
        XCTAssertEqual(l?["kind"]?.stringValue, "ies")
        XCTAssertEqual(l?["iesProfile"]?["maxCandela"]?.doubleValue, 2000)

        // Construction sequence: two phases, one new wall per phase.
        var d = s.editor.doc
        d.phases = ["Existing", "New Construction"]
        let w1 = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200, height: 2700)), name: "W1")
        let w2 = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(0, 4000), thickness: 200, height: 2700)), name: "W2")
        if let i = d.elementIndex(w1) { d.elements[i].props["phaseCreated"] = "Existing" }
        if let i = d.elementIndex(w2) { d.elements[i].props["phaseCreated"] = "New Construction" }
        s.editor.doc = d
        guard Phasing.isActive(s.editor.doc) else { throw XCTSkip("phasing is not active for this document") }
        let f = try await s.call("render.phaseFrames", obj([("source", .string("Phases")), ("seconds", .number(0.1)), ("fps", .int(20))]))
        let frames = f["frames"]?.arrayValue ?? []
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames.first?["caption"]?.stringValue, "Phase 1 of 2: Existing")
        XCTAssertEqual(frames.last?["caption"]?.stringValue, "Phase 2 of 2: New Construction")
        let lastSet = frames.last?["set"]?.intValue ?? -1
        XCTAssertEqual(Set(f["sets"]?[lastSet]?.arrayValue?.compactMap { $0.intValue } ?? []), Set([w1, w2]))
    }
}
