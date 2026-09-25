// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftLayerTests: XCTestCase {
    func tmp(_ name: String) -> String { NSTemporaryDirectory() + "archi-layer-\(UUID().uuidString)-" + name }

    func testLayerStateSaveRestoreExportImport() async throws {
        let ed = Editor()
        await ed.run("LAYERSTATE S Plan \"all on\"")
        XCTAssertEqual(LayerStates.all(ed.doc).count, 1)
        await ed.run("LAYER OFF A-DOOR F A-GLAZ LO A-WALL ")
        XCTAssertFalse(ed.doc.layer(named: "A-DOOR")!.visible)
        XCTAssertTrue(ed.doc.layer(named: "A-GLAZ")!.frozen)
        await ed.run("LAYERSTATE R Plan N")
        XCTAssertTrue(ed.doc.layer(named: "A-DOOR")!.visible)
        XCTAssertFalse(ed.doc.layer(named: "A-GLAZ")!.frozen)
        XCTAssertFalse(ed.doc.layer(named: "A-WALL")!.locked)
        // Undo of the restore brings back the edited settings.
        ed.undo()
        XCTAssertFalse(ed.doc.layer(named: "A-DOOR")!.visible)
        // Turn off layers not in the state.
        await ed.run("LAYER N NEWLAY ")
        await ed.run("LAYERSTATE R Plan Y")
        XCTAssertFalse(ed.doc.layer(named: "NEWLAY")!.visible)
        // Export / import into another drawing creates missing layers.
        let path = tmp("plan.las.json")
        await ed.run("LAYERSTATE E Plan \(path)")
        let ed2 = Editor()
        ed2.doc.layers = [Layer(name: "0")]
        await ed2.run("LAYERSTATE I \(path) Y")
        XCTAssertNotNil(LayerStates.named("Plan", ed2.doc))
        XCTAssertNotNil(ed2.doc.layer(named: "A-DOOR"))
        // Persistence.
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(LayerStates.all(back), LayerStates.all(ed.doc))
        // Same storage as the app's Layer States Manager.
        XCTAssertNotNil(ed.doc.variables["LAYERSTATE:PLAN"])
        await ed.run("LAYERSTATE D Plan")
        XCTAssertTrue(LayerStates.all(ed.doc).isEmpty)
    }

    func testLayerFiltersPropertyGroupInvert() async {
        let ed = Editor()
        ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))), layer: "A-WALL")
        await ed.run("LAYFILTER N Arch name=A-*")
        let f = LayerFilters.named("Arch", ed.doc)!
        XCTAssertEqual(Set(LayerFilters.layers(f, doc: ed.doc).map(\.name)), ["A-WALL", "A-DOOR", "A-GLAZ", "A-ELEMENTS", "A-ANNO-DIMS", "A-ANNO-TEXT", "A-AREA"])
        await ed.run("LAYFILTER N UsedArch name=A-* used=yes")
        XCTAssertEqual(LayerFilters.layers(LayerFilters.named("UsedArch", ed.doc)!, doc: ed.doc).map(\.name), ["A-WALL"])
        await ed.run("LAYFILTER G Grp 0,S-*")
        XCTAssertEqual(LayerFilters.layers(LayerFilters.named("Grp", ed.doc)!, doc: ed.doc).map(\.name), ["0", "S-GRID"])
        await ed.run("LAYFILTER I Grp")
        XCTAssertEqual(LayerFilters.layers(LayerFilters.named("Grp", ed.doc)!, doc: ed.doc).count, ed.doc.layers.count - 2)
        await ed.run("LAYFILTER S UsedArch")
        XCTAssertEqual(ed.selection.count, 1)
        XCTAssertEqual(LayerFilter(name: "x", rules: ["color": "1"]).matches(Layer(name: "r", color: RGBA(1, 0, 0)), used: []), true)
        // Filters saved by the Layers panel are visible to the core.
        ed.doc.variables["LAYERFILTER:NOTEXT"] = "#on A-*,~*TEXT*"
        XCTAssertEqual(LayerFilters.layers(LayerFilters.named("NOTEXT", ed.doc)!, doc: ed.doc).map(\.name), ["A-WALL", "A-DOOR", "A-GLAZ", "A-ELEMENTS", "A-ANNO-DIMS", "A-AREA"])
        await ed.run("LAYFILTER D NOTEXT")
        XCTAssertNil(ed.doc.variables["LAYERFILTER:NOTEXT"])
        XCTAssertNotNil(LayerFilters.named("Arch", ed.doc))
    }

    func testLayerTranslatorMergeCurWalkAndPrevious() async throws {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "WALLS-OLD")); ed.doc.layers.append(Layer(name: "WALLS-NEW"))
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))), layer: "WALLS-OLD")
        var e = ed.doc.entity(a)!; e.color = .aci(1)
        ed.doc.entities[ed.doc.entityIndex(a)!] = e
        let b = ed.doc.add(.line(LineGeom(.zero, Vec2(0, 1))), layer: "WALLS-NEW")
        // Standards drawing defines the target layer's color.
        var std = ArchiDocument(); std.layers = [Layer(name: "0"), Layer(name: "A-WALL-STD", color: RGBA(0, 1, 0))]
        let stdPath = tmp("std.archi")
        try ArchiFile.encode(std).write(to: URL(fileURLWithPath: stdPath))
        await ed.run("LAYTRANS WALLS-*=A-WALL-STD \(stdPath) Y")
        XCTAssertEqual(ed.doc.entity(a)?.layer, "A-WALL-STD"); XCTAssertEqual(ed.doc.entity(b)?.layer, "A-WALL-STD")
        XCTAssertEqual(ed.doc.entity(a)?.color, .byLayer)
        XCTAssertEqual(ed.doc.layer(named: "A-WALL-STD")?.color, RGBA(0, 1, 0))
        XCTAssertNil(ed.doc.layer(named: "WALLS-OLD"), "translated layers are purged")
        XCTAssertEqual(LayerTranslator.parseMappings("# c\nA=B\nC*,D\n"), [.init("A", "B"), .init("C*", "D")])
        // LAYMRG
        let c = ed.doc.add(.line(LineGeom(.zero, Vec2(2, 0))), layer: "A-DOOR")
        await ed.run("LAYMRG A-DOOR,A-GLAZ A-WALL")
        XCTAssertEqual(ed.doc.entity(c)?.layer, "A-WALL")
        XCTAssertNil(ed.doc.layer(named: "A-DOOR")); XCTAssertNil(ed.doc.layer(named: "A-GLAZ"))
        // LAYCUR
        await ed.run("LAYCUR #\(c) ")
        XCTAssertEqual(ed.doc.entity(c)?.layer, ed.doc.currentLayer)
        // LAYWALK shows one layer then restores.
        let before = ed.doc.layers
        await ed.run("LAYWALK A-WALL")
        XCTAssertEqual(ed.doc.layers, before)
        let shown = LayerWalk.show(["A-WALL"], in: ed.doc)
        XCTAssertEqual(shown.layers.filter(\.visible).map(\.name), ["A-WALL"])
        XCTAssertEqual(LayerWalk.counts(ed.doc).first { $0.layer == "A-WALL-STD" }?.count, 2)
        await ed.run("LAYWALK A-WALL E N")
        XCTAssertEqual(ed.doc.layers.filter(\.visible).map(\.name), ["A-WALL"], "not restored when asked")
        // LAYERP restores the previous layer settings.
        await ed.run("LAYERP")
        XCTAssertEqual(ed.doc.layers, before)
        await ed.run("LAYER OFF S-GRID ")
        await ed.run("LAYERP")
        XCTAssertTrue(ed.doc.layer(named: "S-GRID")!.visible)
    }

    func testViewportLayerFreeze() async {
        let ed = Editor()
        ed.doc.layouts = [Layout(name: "A1", viewports: [Viewport(origin: .zero, size: Vec2(100, 100), viewCenter: .zero),
                                                          Viewport(origin: Vec2(200, 0), size: Vec2(100, 100), viewCenter: .zero)])]
        let d = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))), layer: "A-DOOR")
        await ed.run("VPLAYER F A1 A-DOOR,A-GLAZ 2")
        XCTAssertEqual(ViewportLayers.frozen(ed.doc, layout: "A1", viewport: 1), ["a-door", "a-glaz"])
        XCTAssertTrue(ViewportLayers.isVisible("A-DOOR", doc: ed.doc, layout: "A1", viewport: 0))
        XCTAssertFalse(ViewportLayers.isVisible("A-DOOR", doc: ed.doc, layout: "A1", viewport: 1))
        XCTAssertFalse(ViewportLayers.visibleEntities(ed.doc, layout: "A1", viewport: 1).contains { $0.id == d })
        XCTAssertTrue(ViewportLayers.document(for: ed.doc, layout: "A1", viewport: 1).layer(named: "A-DOOR")!.frozen)
        XCTAssertTrue(ed.doc.layer(named: "A-DOOR")!.visible, "global layer state untouched")
        await ed.run("VPLAYER T A1 A-GLAZ All")
        XCTAssertEqual(ViewportLayers.frozen(ed.doc, layout: "A1", viewport: 1), ["a-door"])
        await ed.run("VPLAYER R A1 All")
        XCTAssertTrue(ViewportLayers.all(ed.doc).isEmpty)
    }
}
