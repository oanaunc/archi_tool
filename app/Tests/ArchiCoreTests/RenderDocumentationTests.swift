// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class RenderDocumentationTests: XCTestCase {
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Vec2] { [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)] }

    func testColourFillSchemesAndLegend() async {
        let ed = Editor()
        let a = ed.doc.addElement(.space(SpaceGeom(boundary: rect(0, 0, 4000, 3000), name: "Office 1")))
        let b = ed.doc.addElement(.space(SpaceGeom(boundary: rect(5000, 0, 4000, 3000), name: "Lab")))
        let c = ed.doc.addElement(.space(SpaceGeom(boundary: rect(10000, 0, 2000, 3000), name: "Office 2")))
        for (id, dep) in [(a, "Admin"), (b, "Research"), (c, "Admin")] { ed.doc.elements[ed.doc.elementIndex(id)!].props["department"] = dep }
        XCTAssertNil(AreaColors.color(ed.doc.element(a)!, doc: ed.doc))
        await ed.run("COLORFILL Scheme Department")
        let legend = AreaColors.legend(ed.doc)
        XCTAssertEqual(legend.map(\.value), ["Admin", "Research"])
        XCTAssertEqual(legend[0].count, 2); XCTAssertEqual(legend[0].area, 18_000_000, accuracy: 1e-6)
        let ca = AreaColors.color(ed.doc.element(a)!, doc: ed.doc)!, cb = AreaColors.color(ed.doc.element(b)!, doc: ed.doc)!
        XCTAssertEqual(ca, AreaColors.color(ed.doc.element(c)!, doc: ed.doc)!); XCTAssertNotEqual(ca, cb)
        let fill = PlanRepresentation.items(ed.doc.element(b)!, doc: ed.doc).compactMap { if case .fill(_, let col) = $0 { return col }; return nil }.first!
        XCTAssertEqual(fill.r, cb.r, accuracy: 1e-9); XCTAssertEqual(fill.a, 0.45, accuracy: 1e-9)
        await ed.run("COLORFILL Color Research #FF0000")
        XCTAssertEqual(AreaColors.color(ed.doc.element(b)!, doc: ed.doc)!.r, 1, accuracy: 1e-9)
        let before = ed.doc.entities.count
        await ed.run("COLORFILL Legend 0,-2000")
        XCTAssertEqual(ed.doc.entities.count - before, 1 + 2 * 3)
        XCTAssertTrue(ed.doc.entities.contains { if case .rgb(255, 0, 0) = $0.color { return true }; return false })
        // Area ranges.
        ed.doc.setVariable("COLORFILL", "Area"); ed.doc.setVariable("COLORFILLBIN", "10")
        XCTAssertEqual(AreaColors.legend(ed.doc).map(\.value), ["0–10 m²", "10–20 m²"])
    }

    func testReflectedCeilingPlan() {
        var doc = ArchiDocument()
        let ceil = doc.addElement(.slab(SlabGeom(boundary: rect(0, 0, 4200, 3000), thickness: 20, topOffset: 2620)))
        doc.elements[doc.elementIndex(ceil)!].props["kind"] = "ceiling"
        let chair = doc.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(1000, 1000), size: Vec3(450, 500, 900), family: "chair")))
        let light = doc.addElement(.component(ComponentGeom(category: "Lighting", position: Vec2(2100, 1500), size: Vec3(400, 400, 100), baseOffset: 2500, family: "light-ceiling")))
        let wall = doc.addElement(.wall(WallGeom(start: Vec2(0, -100), end: Vec2(4200, -100), thickness: 200)))
        let door = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: wall, offset: 2000, width: 900, height: 2100)))
        let floor = doc.addElement(.slab(SlabGeom(boundary: rect(0, 0, 4200, 3000))))
        let lines = ReflectedCeiling.gridLines(doc.element(ceil)!, { if case .slab(let s) = doc.element(ceil)!.geometry { return s }; fatalError() }(), unit: 1)
        // Grid centred on the ceiling: 600 modules across 4200 → 7 vertical lines (6 inside + offset), 3000 → 5 horizontal.
        XCTAssertEqual(lines.count, 7 + 5)
        for l in lines { for p in l { XCTAssertTrue(p.x >= -1e-6 && p.x <= 4200 + 1e-6 && p.y >= -1e-6 && p.y <= 3000 + 1e-6) } }
        let plan = Set(DrawListBuilder.entries(doc: doc, options: DrawOptions()).compactMap(\.id))
        XCTAssertTrue(plan.isSuperset(of: [chair, door, floor, wall]))
        var o = DrawOptions(); o.reflectedCeiling = true
        let rcp = DrawListBuilder.entries(doc: doc, options: o)
        let ids = Set(rcp.compactMap(\.id))
        XCTAssertTrue(ids.contains(ceil)); XCTAssertTrue(ids.contains(light)); XCTAssertTrue(ids.contains(wall))
        XCTAssertFalse(ids.contains(chair)); XCTAssertFalse(ids.contains(door)); XCTAssertFalse(ids.contains(floor))
        let texts = rcp.first { $0.id == ceil }!.items.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        XCTAssertEqual(texts, ["CLG +2.600"])
        // The RCP variable and ceiling views use the same display.
        doc.setVariable("RCP", "1")
        XCTAssertFalse(DrawListBuilder.entries(doc: doc, options: DrawOptions()).contains { $0.id == chair })
        doc.setVariable("RCP", "0")
        XCTAssertFalse(ElevationBuilder.entries(doc: doc, view: .ceiling).contains { $0.id == chair })
    }

    func testAutoDimensionWalls() async {
        let ed = Editor()
        await ed.run("WALL 0,0 10000,0 10000,6000 0,6000 C")
        let walls = ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }
        XCTAssertEqual(walls.count, 4)
        let bottom = walls.first { if case .wall(let w) = $0.geometry { return abs(w.start.y) < 1 && abs(w.end.y) < 1 }; return false }!
        ed.doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: bottom.id, offset: 3000, width: 1200, height: 1200, sill: 900)))
        let chains = AutoDimension.wallChains(doc: ed.doc, walls: walls.map(\.id), offset: 800)
        XCTAssertEqual(chains.count, 4)
        let bc = chains.first { $0.wall == bottom.id }!
        XCTAssertEqual(bc.dims.count, 4)     // 3 segments + overall
        func len(_ d: DimensionGeom) -> Double { d.points[0].distance(to: d.points[1]) }
        XCTAssertEqual(bc.dims.dropLast().map(len).reduce(0, +), len(bc.dims.last!), accuracy: 1e-6)
        XCTAssertEqual(len(bc.dims.last!), 10200, accuracy: 1e-6)            // outer face incl. the corners
        XCTAssertTrue(bc.dims.allSatisfy { $0.points[2].y < -800 })          // outside the building
        let side = chains.first { $0.wall != bottom.id }!
        XCTAssertEqual(side.dims.count, 1)                                     // no openings: one dimension, no overall
        ed.selection = []
        await ed.run("AUTODIMWALLS ; 800 Yes")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["autoDim"] != nil }.count, 4 + 3)
    }

    func testRoofSlopeArrows() {
        var doc = ArchiDocument()
        doc.addElement(.roof(RoofGeom(boundary: rect(0, 0, 10000, 8000), kind: .gable, pitch: 35)))
        let items = PlanRepresentation.items(doc.elements[0], doc: doc)
        let texts = items.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        XCTAssertEqual(texts.count, 2)
        XCTAssertTrue(texts.allSatisfy { $0 == "35°" }, "\(texts)")
        doc.setVariable("ROOFSLOPEARROWS", "0")
        XCTAssertFalse(PlanRepresentation.items(doc.elements[0], doc: doc).contains { if case .text = $0 { return true }; return false })
    }
}
