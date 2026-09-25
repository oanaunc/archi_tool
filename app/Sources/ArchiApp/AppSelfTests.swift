// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// In-app regression checks for logic that lives in the app target (node graphs, sheet sets, presets, clipboard,
/// ribbon catalog, command search). Run with APPSELFTEST from the command line, scripts or the agent server.
@MainActor
enum AppSelfTests {
    struct Result { var passed = 0; var failures: [String] = [] }

    static func run() -> Result {
        var r = Result()
        func check(_ ok: Bool, _ name: String) { if ok { r.passed += 1 } else { r.failures.append(name) } }

        // Node graph: sample graph = octagon extruded, arrayed 3 × 2.
        let sample = NodeGraph.sample
        let ev = sample.evaluate()
        check(ev.errors.isEmpty, "node sample has no errors")
        check(ev.output.count == 6, "node sample makes 6 solids (got \(ev.output.count))")
        if case .solid(let s)? = ev.output.first { check(s.kind == .extrusion && abs(s.height - 3000) < 1e-9 && s.profile.count == 8, "extrusion height and octagon profile") }
        else { check(false, "node output is a solid") }
        // Range → Point → Circle broadcasting.
        var g = NodeGraph()
        let range = g.add(.range, x: 0, y: 0)
        let pt = g.add(.point, x: 0, y: 0)
        let circ = g.add(.circle, x: 0, y: 0)
        check(g.connect(from: range, to: pt, port: "x"), "connect range → point.x")
        check(g.connect(from: pt, to: circ, port: "center"), "connect point → circle.center")
        check(!g.connect(from: circ, to: pt, port: "y"), "type mismatch refused")
        let e2 = g.evaluate()
        check(e2.output.count == 5, "range of 5 gives 5 circles (got \(e2.output.count))")
        if case .circle(let c)? = e2.output.last { check(abs(c.center.x - 10000) < 1e-9, "last circle at x = 10000") }
        // Cycles are refused.
        var g3 = NodeGraph()
        let m1 = g3.add(.move, x: 0, y: 0), m2 = g3.add(.move, x: 0, y: 0)
        check(g3.connect(from: m1, to: m2, port: "geometry"), "connect move → move")
        check(!g3.connect(from: m2, to: m1, port: "geometry"), "cycle refused")
        // Polar array spacing over a full circle.
        var g4 = NodeGraph()
        let c4 = g4.add(.circle, x: 0, y: 0)
        g4.nodes[0].params = ["center.x": 1000, "radius": 50]
        let pa = g4.add(.polarArray, x: 0, y: 0)
        g4.nodes[1].params = ["count": 4]
        g4.connect(from: c4, to: pa, port: "geometry")
        let e4 = g4.evaluate()
        check(e4.output.count == 4, "polar array count")
        if e4.output.count == 4, case .circle(let q) = e4.output[1] { check(q.center.isClose(Vec2(0, 1000), tol: 1e-6), "polar array 90° step") }
        // Persistence round trip through a document variable.
        var doc = ArchiDocument()
        sample.store(in: &doc)
        check(NodeGraph.load(doc) == sample, "node graph JSON round trip")
        let ids = NodeGraphBake.bake(ev.output, into: &doc)
        _ = NodeGraphBake.bake(ev.output, into: &doc)
        check(ids.count == 6 && NodeGraphBake.bakedCount(doc) == 6, "bake replaces earlier output")

        // Sheet sets.
        check(SheetSet.nextCode(after: nil) == "A", "first revision A")
        check(SheetSet.nextCode(after: "B") == "C", "B → C")
        check(SheetSet.nextCode(after: "Z") == "AA", "Z → AA")
        check(SheetSet.nextCode(after: "AZ") == "BA", "AZ → BA")
        check(SheetSet.nextCode(after: "P01") == "P02", "P01 → P02")
        check(SheetSet.nextCode(after: "9") == "10", "9 → 10")
        var sd = ArchiDocument()
        sd.layouts = [ArchiCore.Layout(name: "Plans"), ArchiCore.Layout(name: "Sections"), ArchiCore.Layout(name: "Details")]
        SheetSet.renumber(&sd, prefix: "A-", start: 101)
        check(SheetSet.number(sd, 2) == "A-103", "renumber A-103")
        SheetSet.addRevision(&sd, 0, description: "Issued for comment", by: "OA", date: "2026-09-25")
        SheetSet.addRevision(&sd, 0, description: "Planning", by: "OA", date: "2026-10-01")
        let revs = SheetSet.revisions(sd.layouts[0])
        check(revs.map(\.code) == ["A", "B"] && sd.layouts[0].titleBlock["revision"] == "B", "revisions A, B and title block field")
        SheetSet.move(&sd, from: 0, to: 2)
        check(sd.layouts.map(\.name) == ["Sections", "Details", "Plans"], "move sheet to the end")
        let dup = SheetSet.duplicate(&sd, 2)
        check(dup == 3 && sd.layouts[3].name == "Plans (2)" && SheetSet.revisions(sd.layouts[3]).isEmpty, "duplicate sheet without revisions")
        SheetSet.placeIndex(&sd, on: 0); SheetSet.placeIndex(&sd, on: 0)
        let idx = sd.layouts[0].entities.filter { $0.props["sheetIndex"] != nil }
        if idx.count == 1, case .table(let t) = idx[0].geometry { check(t.cells.count == 5 && t.cells[2][0] == "A-103" && t.cells[4][0] == "A-104", "sheet index rows") }
        else { check(false, "one sheet index table") }
        sd.layouts[1].viewports = [Viewport(origin: Vec2(40, 100), size: Vec2(120, 80), viewCenter: .zero)]
        SheetSet.refreshViewTitles(&sd, 1)
        if let i = sd.layouts[1].entities.firstIndex(where: { $0.props["viewTitleRole"] == "title" }), case .text(var tg) = sd.layouts[1].entities[i].geometry {
            tg.content = "Ground Floor Plan"; sd.layouts[1].entities[i].geometry = .text(tg)
        }
        SheetSet.refreshViewTitles(&sd, 1)
        let kept = sd.layouts[1].entities.contains { if case .text(let t) = $0.geometry { return t.content == "Ground Floor Plan" }; return false }
        check(kept && sd.layouts[1].entities.filter { $0.props["viewTitle"] != nil }.count == 5, "view titles keep edited text")

        // Render presets saved before the new settings still decode.
        let legacy = #"[{"name":"Old","width":800,"height":600,"antialias":true,"exposure":0.5,"background":"White"}]"#
        if let p = try? JSONDecoder().decode([RenderPreset].self, from: Data(legacy.utf8)).first {
            var s = RenderSettings(); s.clay = true
            p.apply(to: &s)
            check(s.width == 800 && s.background == .white && !s.clay && s.shadowQuality == .high, "legacy render preset applies defaults")
        } else { check(false, "legacy render preset decodes") }

        // Clipboard payloads written by 1.0 (no blocks/layers) still paste.
        let clipJSON = #"{"entities":[],"elements":[],"base":{"x":1,"y":2}}"#
        check((try? JSONDecoder().decode(ClipboardPayload.self, from: Data(clipJSON.utf8)))?.clip.base == Vec2(1, 2), "legacy clipboard payload")

        // Every ribbon/menu item resolves to a registered command.
        CommandRegistry.shared.ensureBuiltins()
        AppCommands.registerAll()
        let missing = CommandCatalog.allItems.filter { i in !i.names.contains { CommandRegistry.shared.lookup($0) != nil } }.map(\.title)
        check(missing.isEmpty, "ribbon items without a command: \(missing.joined(separator: ", "))")
        // Every registered command is reachable from the ribbon, a menu or a palette (or intentionally elsewhere).
        let cov = CommandCatalog.coverage(.shared)
        lastCoverage = cov
        check(cov.missing.isEmpty, "commands without a ribbon/menu/palette entry: \(cov.missing.joined(separator: ", "))")
        extraChecks(check)
        check(CommandSearch.rank("prspl", registry: .shared).first?.name == "PRESSPULL", "fuzzy search finds PRESSPULL")
        check(CommandSearch.rank("tag all", registry: .shared).contains { $0.name == "TAGALL" }, "ribbon title search finds TAGALL")
        return r
    }

    /// Coverage computed by the last run (listed by APPSELFTEST).
    static var lastCoverage: CommandCatalog.Coverage?

    /// Checks of the features added with the coverage work: camera path, panorama mapping, section caps, plot styles,
    /// bump maps, new node graph nodes, templates.
    static func extraChecks(_ check: (Bool, String) -> Void) {
        // Camera path: passes through keys, stays smooth between them.
        let keys = [Camera(eye: Vec3(0, 0, 1600), target: Vec3(1000, 0, 1600)), Camera(eye: Vec3(5000, 0, 1600), target: Vec3(6000, 0, 1600)),
                    Camera(eye: Vec3(5000, 5000, 1600), target: Vec3(5000, 6000, 1600), fov: 70)]
        check(CameraPath.sample(keys, t: 0)?.eye.isClose(keys[0].eye, tol: 1e-9) == true, "camera path starts at key 1")
        check(CameraPath.sample(keys, t: 0.5)?.eye.isClose(keys[1].eye, tol: 1e-9) == true, "camera path passes key 2")
        check(CameraPath.sample(keys, t: 1)?.eye.isClose(keys[2].eye, tol: 1e-9) == true && abs((CameraPath.sample(keys, t: 1)?.fov ?? 0) - 70) < 1e-9, "camera path ends at key 3")
        check(abs((CameraPath.sample(Array(keys.prefix(2)), t: 0.5)?.eye.x ?? 0) - 2500) < 1e-6 && abs(CameraPath.sample(Array(keys.prefix(2)), t: 0.5)?.eye.y ?? 1) < 1e-9, "two keys: straight path")
        check(CameraPath.length(Array(keys.prefix(2))) > 4999 && CameraPath.length(Array(keys.prefix(2))) < 5001, "path length")
        // Panorama: equirect centre looks forward (-Z), faces map back consistently.
        let fwd = Panorama.direction(u: 0.5, v: 0.5)
        check(fwd.isClose(Vec3(0, 0, -1), tol: 1e-9), "panorama centre is -Z")
        check(Panorama.direction(u: 0.5, v: 0).isClose(Vec3(0, 1, 0), tol: 1e-9), "panorama top is zenith")
        let lk = Panorama.lookup(fwd)
        check(lk.face == 5 && abs(lk.s - 0.5) < 1e-9 && abs(lk.t - 0.5) < 1e-9, "forward hits the -Z face centre")
        let up = Panorama.lookup(Vec3(0, 0.3, -1).normalized)
        check(up.face == 5 && up.t < 0.5, "looking up moves up in the face image")
        var faces: [[UInt8]] = []
        for i in 0..<6 { faces.append([UInt8](repeating: UInt8(i * 40), count: 4 * 4 * 4)) }
        let eq = Panorama.equirect(faces: faces, faceSize: 4, width: 16, height: 8)
        check(eq.count == 16 * 8 * 4 && eq[(4 * 16 + 8) * 4] == 200, "equirect samples the -Z face at the centre")
        // Section caps: a unit cube cut at mid height gives one square loop of area 1.
        let cube = MeshTools.triangles(MeshTools.mesh(of: SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        let loops = SectionCap.loops(cube, point: Vec3(0, 0, 500), normal: Vec3(0, 0, 1))
        check(loops.count == 1 && loops.first?.count ?? 0 >= 4, "cube cut gives one loop (got \(loops.count))")
        let capArea = SectionCap.triangles(loops, normal: Vec3(0, 0, 1)).reduce(0.0) { $0 + ($1.1 - $1.0).cross($1.2 - $1.0).length / 2 }
        check(abs(capArea - 1_000_000) < 1, "cap area of the cube section (got \(capArea))")
        check(SectionCap.loops(cube, point: Vec3(0, 0, 2000), normal: Vec3(0, 0, 1)).isEmpty, "plane above the cube cuts nothing")
        let ring = SectionCap.triangles([[Vec3(0, 0, 0), Vec3(10, 0, 0), Vec3(10, 10, 0), Vec3(0, 10, 0)], [Vec3(3, 3, 0), Vec3(7, 3, 0), Vec3(7, 7, 0), Vec3(3, 7, 0)]], normal: Vec3(0, 0, 1))
        check(abs(ring.reduce(0.0) { $0 + ($1.1 - $1.0).cross($1.2 - $1.0).length / 2 } - 84) < 1e-6, "nested loop becomes a hole")
        let pl = SectionPlane.vertical(Vec2(0, 0), Vec2(1000, 0))
        var pd = ArchiDocument(); pl?.store(in: &pd)
        check(SectionPlane.load(pd) == pl && pl?.normal.isClose(Vec3(0, 1, 0), tol: 1e-12) == true, "section plane round trip")
        // Plot styles.
        check(PlotStyleTable.aciIndex(aciColor(3)) == 3 && PlotStyleTable.aciIndex(RGBA(0.123, 0.456, 0.789)) == nil, "ACI index lookup")
        let (c1, w1) = PlotStyleTable.archiPens.resolve(color: aciColor(5), lineweight: 0.25)
        check(c1.r < 0.01 && c1.g < 0.01 && abs(w1 - 0.5) < 1e-12, "pen 5 plots black at 0.50 mm")
        let (c8, _) = PlotStyleTable.archiPens.resolve(color: aciColor(8), lineweight: 0.25)
        check(abs(c8.r - 0.5) < 0.01, "screening 50% lightens black to grey")
        let (ct, wt) = PlotStyleTable.archiPens.resolve(color: RGBA(0.2, 0.4, 0.6), lineweight: 0.35)
        check(abs(ct.b - 0.6) < 1e-9 && abs(wt - 0.35) < 1e-12, "true colours use the object pen without an Other entry")
        var sd = ArchiDocument()
        var custom = PlotStyleTable(name: "office.ctb"); custom.pens[1] = .init(color: 0x0000FF, lineweight: 0.7)
        custom.store(in: &sd)
        check(PlotStyleTable.named("OFFICE.CTB", in: sd)?.pens[1]?.lineweight == 0.7, "custom table stored in the drawing")
        var ps = PageSetup(); ps.plotStyleTable = "office.ctb"; ps.store(in: &sd, layoutIndex: nil)
        check(PageSetup.load(sd, layoutIndex: nil).plotStyleTable == "office.ctb", "page setup keeps the plot style table")
        check((try? JSONDecoder().decode(PageSetup.self, from: Data(#"{"colorMode":"Color"}"#.utf8)))?.plotStyleTable == nil, "old page setups decode")
        // Bump map: flat height gives a flat normal; a ramp tilts it.
        let flat = BumpMap.normals(height: [Double](repeating: 0.5, count: 16), width: 4, height: 4, strength: 1)
        check(flat[0] == 128 && flat[1] == 128 && flat[2] == 255, "flat height → (128,128,255)")
        let ramp = BumpMap.normals(height: (0..<64).map { Double($0 % 8) / 8 }, width: 8, height: 8, strength: 1)
        check(ramp[(3 * 8 + 3) * 4] < 128, "rising height tilts the normal against +x")
        // New node graph nodes.
        var g = NodeGraph()
        let rnd = g.add(.random, x: 0, y: 0)
        let e1 = g.evaluate().values[rnd], e2 = g.evaluate().values[rnd]
        if case .numbers(let a)? = e1 { check(a.count == 5 && a.allSatisfy { $0 >= 0 && $0 < 1000 } && e1 == e2, "random is seeded and in range") } else { check(false, "random node output") }
        var gl = NodeGraph()
        let r1 = gl.add(.rectangle, x: 0, y: 0), c2 = gl.add(.circle, x: 0, y: 0), lo = gl.add(.loft, x: 0, y: 0)
        gl.connect(from: r1, to: lo, port: "bottom"); gl.connect(from: c2, to: lo, port: "top")
        let ev = gl.evaluate()
        if case .solid(let so)? = ev.output.first { check(ev.errors.isEmpty && so.kind == .mesh && CSG.volume(so) > 0, "loft makes a closed positive solid") } else { check(false, "loft output (\(ev.errors))") }
        var gb = NodeGraph()
        let rr = gb.add(.rectangle, x: 0, y: 0), ex = gb.add(.extrude, x: 0, y: 0)
        let cc = gb.add(.circle, x: 0, y: 0), ex2 = gb.add(.extrude, x: 0, y: 0), bo = gb.add(.boolean, x: 0, y: 0)
        gb.nodes[2].params = ["radius": 200]
        gb.connect(from: rr, to: ex, port: "profile"); gb.connect(from: cc, to: ex2, port: "profile")
        gb.connect(from: ex, to: bo, port: "a"); gb.connect(from: ex2, to: bo, port: "b")
        let evb = gb.evaluate()
        if case .solid(let sb)? = evb.output.first {
            let expect = 2000.0 * 1000 * 3000 - Double.pi * 200 * 200 * 3000
            check(abs(CSG.volume(sb) - expect) / expect < 0.02, "boolean subtract volume (got \(CSG.volume(sb)))")
        } else { check(false, "boolean output (\(evb.errors))") }
        var gw = NodeGraph()
        let rect = gw.add(.rectangle, x: 0, y: 0), wall = gw.add(.wall, x: 0, y: 0), slab = gw.add(.slab, x: 0, y: 0), roof = gw.add(.roof, x: 0, y: 0)
        gw.connect(from: rect, to: wall, port: "path"); gw.connect(from: rect, to: slab, port: "boundary"); gw.connect(from: rect, to: roof, port: "boundary")
        let evw = gw.evaluate()
        let walls = evw.elementOutput.filter { if case .wall = $0 { return true }; return false }.count
        check(walls == 4 && evw.elementOutput.count == 6, "rectangle → 4 walls, 1 slab, 1 roof (got \(evw.elementOutput.count))")
        var bd = ArchiDocument()
        _ = NodeGraphBake.bake([], elements: evw.elementOutput, into: &bd)
        _ = NodeGraphBake.bake([], elements: evw.elementOutput, into: &bd)
        check(bd.elements.count == 6 && NodeGraphBake.bakedCount(bd) == 6, "baking elements replaces the earlier bake")
        var nd = ArchiDocument()
        gw.store(in: &nd, name: "Shell")
        check(NodeGraph.names(nd) == ["Shell"] && NodeGraph.load(nd, name: "Shell") == gw && NodeGraph.load(nd) == gw, "named graph stored in the drawing")
        // Plot stamp fields and the physical sky.
        var stampDoc = ArchiDocument(); stampDoc.info.name = "Cedar"; stampDoc.info.number = "P-7"; stampDoc.info.author = "OA"
        let st = PlotStamp.text(doc: stampDoc, name: "A101", template: "{project}/{number}/{sheet}/{user}/{style}", style: "archi pens.ctb")
        check(st == "Cedar/P-7/A101/OA/archi pens.ctb", "plot stamp fields (got \(st))")
        let noon = Vec3(0.2, 0.9, -0.3).normalized
        let z = SkyModel.color(Vec3(0, 1, 0), sun: noon), hz = SkyModel.color(Vec3(1, 0.02, 0), sun: noon), sunC = SkyModel.color(noon, sun: noon)
        check(z.2 > z.0 && hz.0 > z.0 && sunC.0 > 2, "sky: blue zenith, paler horizon, bright sun")
        check(SkyModel.color(Vec3(0, 1, 0), sun: Vec3(0, -0.5, 1).normalized).2 < 0.1, "sky is dark at night")
        // Command reference export lists every registered command.
        let csv = CommandReferenceExport.text(.shared, csv: true)
        check(csv.split(separator: "\n").count == CommandRegistry.shared.sorted.count + 1, "command reference export has one row per command")
        check(CommandReferenceExport.location(CommandRegistry.shared.lookup("LINE")!, registry: .shared) == "Draw", "LINE is on the Draw menu")
        // Metric Architectural template.
        let t = TemplateLibrary.metricArchitectural()
        check(t.layer(named: "A-FURN") != nil && t.dimStyles.contains { $0.name == "Architectural 1:50" } && t.currentDimStyle == "Architectural 1:100", "metric architectural template")
        check(DocumentThumbnails.stableKey("abc") == DocumentThumbnails.stableKey("abc") && DocumentThumbnails.stableKey("abc") != DocumentThumbnails.stableKey("abd"), "stable thumbnail keys")
    }

    static var command: CommandDef {
        CommandDef("APPSELFTEST", aliases: ["SELFTEST"], category: "Help", summary: "Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon).", modifies: false) { ed in
            let r = run()
            if let cov = lastCoverage {
                ed.print("Command coverage: \(cov.total - cov.missing.count - cov.intentional.count) in ribbon/menus, \(cov.intentional.count) in palettes (system variables), \(cov.missing.count) without UI entry.")
                if !cov.missing.isEmpty { ed.print("  Without UI entry: " + cov.missing.joined(separator: ", ")); NSLog("APPSELFTEST uncovered commands: %@", cov.missing.joined(separator: ", ")) }
            }
            for f in r.failures { ed.print("FAIL: \(f)") }
            ed.print("\(r.passed) check(s) passed, \(r.failures.count) failed.")
            if !r.failures.isEmpty { throw CommandError.invalid("\(r.failures.count) self-test check(s) failed.") }
        }
    }
}
