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
        check(CommandSearch.rank("prspl", registry: .shared).first?.name == "PRESSPULL", "fuzzy search finds PRESSPULL")
        check(CommandSearch.rank("tag all", registry: .shared).contains { $0.name == "TAGALL" }, "ribbon title search finds TAGALL")
        return r
    }

    static var command: CommandDef {
        CommandDef("APPSELFTEST", aliases: ["SELFTEST"], category: "Help", summary: "Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon).", modifies: false) { ed in
            let r = run()
            for f in r.failures { ed.print("FAIL: \(f)") }
            ed.print("\(r.passed) check(s) passed, \(r.failures.count) failed.")
            if !r.failures.isEmpty { throw CommandError.invalid("\(r.failures.count) self-test check(s) failed.") }
        }
    }
}
