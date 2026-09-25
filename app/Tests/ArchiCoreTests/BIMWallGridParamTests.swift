// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMWallGridParamTests: XCTestCase {
    func grids(_ doc: ArchiDocument) -> [GridLineGeom] { doc.elements.compactMap { if case .gridLine(let g) = $0.geometry { return g }; return nil } }

    func testRectangularAndRadialGridSystems() async {
        XCTAssertEqual(GridSystems.spacings("3*6000, 4500"), [6000, 6000, 6000, 4500])
        XCTAssertNil(GridSystems.spacings("3*x"))
        XCTAssertEqual(GridSystems.letter(0), "A"); XCTAssertEqual(GridSystems.letter(8), "J"); XCTAssertEqual(GridSystems.letter(24), "AA")
        let ed = Editor()
        await ed.run("GRIDSYSTEM 0,0 \"3*6000 4500\" \"2*5000\" 1000 0")
        let g = grids(ed.doc)
        XCTAssertEqual(g.count, 5 + 3)
        XCTAssertEqual(g.filter { Int($0.label) != nil }.map { $0.start.x }, [0, 6000, 12000, 18000, 22500])
        XCTAssertEqual(g.first { $0.label == "C" }?.start, Vec2(-1000, 10000))
        XCTAssertEqual(g.first { $0.label == "1" }?.end, Vec2(0, 11000))
        // A second system continues the labels.
        await ed.run("GRIDSYSTEM 50000,0 \"6000\" \"6000\" 0 0")
        XCTAssertTrue(grids(ed.doc).contains { $0.label == "6" } && grids(ed.doc).contains { $0.label == "D" })
        // Radial grid: 7 radial lines over 90°, 3 arcs.
        let ed2 = Editor()
        await ed2.run("RADIALGRID 0,0 0 \"6*15\" 3000 \"2*6000\" 1000")
        let r = grids(ed2.doc)
        XCTAssertEqual(r.filter { $0.bulge == 0 }.count, 7)
        let arcs = r.filter { $0.bulge != 0 }
        XCTAssertEqual(arcs.count, 3)
        // Every arc point lies on its radius; radial lines start at the inner radius.
        for a in arcs { let rad = a.start.length; XCTAssertTrue(a.points.allSatisfy { abs($0.length - rad) < 1e-6 }) }
        XCTAssertEqual(Set(arcs.map { ($0.start.length).rounded() }), [3000, 9000, 15000])
        XCTAssertEqual(r.first { $0.label == "7" }!.start.distance(to: Vec2(0, 3000)), 0, accuracy: 1e-6)
        XCTAssertNil(GridSystems.radial(center: .zero, startAngle: 0, angles: [Double](repeating: .pi / 6, count: 12), innerRadius: 0, radii: [1000], overhang: 0))
        // Plan: the arc grid is drawn along the arc; persistence keeps the bulge.
        let arcEl = ed2.doc.elements.first { if case .gridLine(let g) = $0.geometry { return g.bulge != 0 }; return false }!
        let items = PlanRepresentation.items(arcEl, doc: ed2.doc)
        XCTAssertTrue(items.contains { if case .stroke(let p, _, _) = $0 { return p.count > 10 }; return false })
        let back = try! ArchiFile.decode(ArchiFile.encode(ed2.doc))
        XCTAssertEqual(back.elements.map(\.geometry), ed2.doc.elements.map(\.geometry))
        // Old files without bulge still decode.
        let old = try! JSONDecoder().decode(GridLineGeom.self, from: Data(#"{"start":{"x":0,"y":0},"end":{"x":1,"y":0},"label":"1"}"#.utf8))
        XCTAssertEqual(old.bulge, 0)
    }

    func testWallFlipSplitAndOpeningFlip() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let w = ed.doc.elements[0].id
        await ed.run("DOOR 1500,0 ")
        guard let d = ed.doc.elements.first(where: { if case .opening = $0.geometry { return true }; return false }), case .opening(let o0) = d.geometry else { return XCTFail("no door") }
        let doorBefore = MeshBuilder.build(doc: ed.doc).filter { $0.id == d.id }.reduce(BBox3.empty) { var b = $0; b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max); return b }
        ed.selection = [w]
        await ed.run("WALLFLIP")
        guard case .wall(let g1) = ed.doc.element(w)!.geometry, case .opening(let o1) = ed.doc.element(d.id)!.geometry else { return XCTFail() }
        XCTAssertEqual(g1.start, Vec2(6000, 0))
        XCTAssertEqual(o1.offset, 6000 - o0.offset, accuracy: 1e-9)
        XCTAssertNotEqual(o1.flipFacing, o0.flipFacing)
        let doorAfter = MeshBuilder.build(doc: ed.doc).filter { $0.id == d.id }.reduce(BBox3.empty) { var b = $0; b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max); return b }
        XCTAssertEqual(doorAfter.min.x, doorBefore.min.x, accuracy: 1e-6); XCTAssertEqual(doorAfter.max.y, doorBefore.max.y, accuracy: 1e-6)
        // Opening flip.
        ed.selection = [d.id]
        await ed.run("OPENINGFLIP Hand")
        guard case .opening(let o2) = ed.doc.element(d.id)!.geometry else { return XCTFail() }
        XCTAssertNotEqual(o2.flipHand, o1.flipHand); XCTAssertEqual(o2.flipFacing, o1.flipFacing)
        // Split at x = 3000 (door at x = 1500 moves to the second piece since the wall now runs 6000 → 0).
        ed.selection = []
        await ed.run("SPLITWALL 3000,0")
        let walls = ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }
        XCTAssertEqual(walls.count, 2)
        guard case .opening(let o3) = ed.doc.element(d.id)!.geometry, let host = ed.doc.element(o3.hostWall), case .wall(let hg) = host.geometry else { return XCTFail() }
        XCTAssertNotEqual(host.id, w)
        XCTAssertEqual(hg.start, Vec2(3000, 0))
        XCTAssertEqual(o3.offset, 1500, accuracy: 1e-6)
        // Splitting through the door is refused.
        XCTAssertNil(WallTools.split(&ed.doc, wall: host.id, at: Vec2(1500, 0)))
        // Split by levels: a two-storey wall becomes one wall per storey; a window on the upper storey moves up.
        let tall = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 5000), end: Vec2(6000, 5000), height: 6000)))
        let win = ed.doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: tall, offset: 3000, width: 1200, height: 1200, sill: 3900)))
        ed.selection = [tall]
        await ed.run("SPLITWALL Levels")
        let pieces = ed.doc.elements.filter { if case .wall(let g) = $0.geometry { return g.start.y == 5000 }; return false }
        XCTAssertEqual(pieces.count, 2)
        guard case .opening(let wo) = ed.doc.element(win)!.geometry, let up = ed.doc.element(wo.hostWall), case .wall(let ug) = up.geometry else { return XCTFail() }
        XCTAssertEqual(up.level, 1); XCTAssertEqual(wo.sill, 900, accuracy: 1e-9); XCTAssertEqual(ug.height, 3000, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.element(win)!.level, 1)
        guard case .wall(let lg) = ed.doc.element(tall)!.geometry else { return XCTFail() }
        XCTAssertEqual(lg.height, 3000, accuracy: 1e-9); XCTAssertEqual(lg.topLevel, 1)
    }

    func testGlobalParametersReferencePlanesAndPurge() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let w = ed.doc.elements[0].id
        await ed.run("GLOBALPARAM New StoreyHeight 3200")
        await ed.run("GLOBALPARAM New WallHeight =StoreyHeight - 300")
        ed.selection = [w]
        await ed.run("GLOBALPARAM Bind height WallHeight")
        guard case .wall(let g) = ed.doc.element(w)!.geometry else { return XCTFail() }
        XCTAssertEqual(g.height, 2900, accuracy: 1e-9)
        await ed.run("GLOBALPARAM Set StoreyHeight 3500")
        guard case .wall(let g2) = ed.doc.element(w)!.geometry else { return XCTFail() }
        XCTAssertEqual(g2.height, 3200, accuracy: 1e-9)
        XCTAssertEqual(GlobalParameters.dependents("WallHeight", doc: ed.doc), [w])
        // Circular formulas are refused.
        await ed.run("GLOBALPARAM Set StoreyHeight =WallHeight + 1")
        XCTAssertEqual(GlobalParameters.values(ed.doc)["storeyheight"], 3500)
        // Deleting a driving parameter is refused.
        await ed.run("GLOBALPARAM Delete WallHeight")
        XCTAssertEqual(ed.doc.globalParameters.count, 2)

        // Reference planes drive family forms; globals reach family formulas.
        await ed.run("FAMILY New Shelf Furniture")
        await ed.run("FAMILY Ref Shelf Right X Width - 20")
        var def = ed.doc.family(named: "Shelf")!
        XCTAssertEqual(def.referencePlanes.first?.name, "Right")
        def.forms = [FamilyForm(.box, name: "Side", x: "Right", dims: ["width": "20", "depth": "Depth", "height": "StoreyHeight / 2"], material: "Wood")]
        ed.doc.families[ed.doc.familyIndex("Shelf")!] = def
        var r = FamilyEngine.evaluate(def, doc: ed.doc)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(r.bounds.min.x, 580, accuracy: 1e-9)
        XCTAssertEqual(r.bounds.max.z, 1750, accuracy: 1e-9)
        XCTAssertEqual(r.planes["Right"]?.offset, 580)
        r = FamilyEngine.evaluate(def, doc: ed.doc, props: ["fp.Width": "1000"])
        XCTAssertEqual(r.bounds.min.x, 980, accuracy: 1e-9, "the form follows the plane when Width flexes")

        // Purge: an unused family and an unused type go; a used family keeps its used type.
        await ed.run("FAMILY New Spare Generic")
        ed.doc.families[ed.doc.familyIndex("Shelf")!].types = ["Low": ["Height": "400"], "High": ["Height": "2000"]]
        await ed.run("FAMILY Place Shelf Low 0,0 0 ")
        let (fams, types) = FamilyPurge.unused(ed.doc)
        XCTAssertEqual(fams, ["Spare"])
        XCTAssertEqual(types.map(\.type), ["High"])
        await ed.run("FAMILY Purge")
        XCTAssertNil(ed.doc.family(named: "Spare"))
        XCTAssertEqual(Set(ed.doc.family(named: "Shelf")!.types.keys), ["Low"])
        // Persistence of globals, bindings and reference planes.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.globalParameters, ed.doc.globalParameters)
        XCTAssertEqual(back.family(named: "Shelf")?.referencePlanes, ed.doc.family(named: "Shelf")?.referencePlanes)
        XCTAssertEqual(back.element(w)?.props["gp.height"], "WallHeight")
    }
}
