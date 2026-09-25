// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMDetailTests: XCTestCase {
    func bounds(_ groups: [MeshGroup]) -> BBox3 { groups.reduce(BBox3.empty) { var b = $0; if !$1.mesh.isEmpty { b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max) }; return b } }
    func volume(_ groups: [MeshGroup]) -> Double { groups.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) } }

    func testLayeredFloorTypesAndFinishes() async {
        let ed = Editor()
        await ed.run("SLAB 0,0 5000,0 5000,4000 0,4000")
        let slab = ed.doc.elements[0].id
        ed.selection = [slab]
        await ed.run("SLABTYPE Assign \"Floor Tiles on Screed 280\"")
        guard case .slab(let s) = ed.doc.element(slab)!.geometry else { return XCTFail() }
        XCTAssertEqual(s.thickness, 280, accuracy: 1e-9)
        let g = MeshBuilder.build(doc: ed.doc).filter { $0.id == slab }
        XCTAssertEqual(Set(g.map(\.material)), ["Tiles", "Concrete", "Insulation"])
        XCTAssertEqual(volume(g), 5000 * 4000 * 280, accuracy: 1)
        XCTAssertEqual(bounds(g.filter { $0.material == "Tiles" }).min.z, -10, accuracy: 1e-6)
        // A new type from the command line.
        await ed.run("SLABTYPE New Deck Roof Wood 30 Finish Insulation 120 Thermal Concrete 150 Structure ")
        XCTAssertEqual(ed.doc.slabType("Deck")?.thickness, 300)
        XCTAssertEqual(ed.doc.slabType("Deck")?.usage, "roof")
        // Floor finish with a tile grid on a room.
        let room = ed.doc.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Hall")))
        ed.selection = [room]
        await ed.run("FLOORFINISH Tiles 15 600x600")
        guard let fin = ed.doc.elements.first(where: { $0.props["finishOf"] == "\(room)" }) else { return XCTFail("no finish") }
        XCTAssertEqual(fin.material, "Tiles")
        let lines = PlanRepresentation.items(fin, doc: ed.doc).count
        XCTAssertGreaterThan(lines, 10, "tile grid drawn")
    }

    func testWallJoinOverrides() {
        var doc = ArchiDocument()
        let a = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200)))
        let b = doc.addElement(.wall(WallGeom(start: Vec2(4000, 0), end: Vec2(4000, 3000), thickness: 200)))
        func outline(_ id: EntityID) -> BBox2 { BBox2(points: PlanRepresentation.wallOutline(id, doc: doc)) }
        // Default mitre: both walls reach the outer corner.
        XCTAssertEqual(outline(a).max.x, 4100, accuracy: 1e-6)
        XCTAssertEqual(outline(b).min.y, -100, accuracy: 1e-6)
        // Butt: wall a stops at the inner face of wall b; wall b runs through to a's outer face.
        doc.elements[0].props["joinEnd"] = "butt"
        XCTAssertEqual(outline(a).max.x, 3900, accuracy: 1e-6)
        XCTAssertEqual(outline(b).min.y, -100, accuracy: 1e-6)
        XCTAssertEqual(outline(b).min.x, 3900, accuracy: 1e-6)
        // Square off: a square end extended over the corner; wall b keeps a square end.
        doc.elements[0].props["joinEnd"] = "square"
        XCTAssertEqual(outline(a).max.x, 4100, accuracy: 1e-6)
        XCTAssertEqual(outline(b).min.y, 0, accuracy: 1e-6)
        // Disallow: both ends square at the centreline point.
        doc.elements[0].props["joinEnd"] = "none"
        XCTAssertEqual(outline(a).max.x, 4000, accuracy: 1e-6)
        XCTAssertEqual(outline(b).min.y, 0, accuracy: 1e-6)
    }

    func testLayerWrappingAtOpenings() async {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 365, wallType: "Exterior Brick 365")))
        doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2000, width: 1200, height: 1200, sill: 900)))
        let plain = PlanRepresentation.items(doc.element(w)!, doc: doc).count
        doc.setVariable("WALLWRAP", "1")
        let wrapped = PlanRepresentation.items(doc.element(w)!, doc: doc)
        XCTAssertEqual(wrapped.count, plain + 2, "a return line at each jamb")
        let ed = Editor()
        await ed.run("WALLWRAP On")
        XCTAssertEqual(ed.doc.variable("WALLWRAP"), "1")
    }

    func testShaftsCutFloorsAndRoofsAndFollowWhenMoved() {
        var doc = ArchiDocument()
        let s0 = doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 6000), Vec2(0, 6000)])), level: 0)
        let s1 = doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 6000), Vec2(0, 6000)])), level: 1)
        let full = volume(MeshBuilder.build(doc: doc).filter { $0.id == s1 })
        let sh = Shafts.add([Vec2(1000, 1000), Vec2(2000, 1000), Vec2(2000, 2000), Vec2(1000, 2000)], base: 1, top: 1, doc: &doc)
        XCTAssertEqual(volume(MeshBuilder.build(doc: doc).filter { $0.id == s1 }), full - 1000 * 1000 * 200, accuracy: 1)
        XCTAssertEqual(volume(MeshBuilder.build(doc: doc).filter { $0.id == s0 }), full, accuracy: 1, "ground floor is below the shaft base")
        XCTAssertEqual(Shafts.holes(for: doc.element(s1)!, doc: doc).count, 1)
        // Moving the shaft moves the hole.
        if let i = doc.entityIndex(sh) { doc.entities[i].geometry = .polyline(PolylineGeom(points: [Vec2(1000, 1000), Vec2(3000, 1000), Vec2(3000, 2000), Vec2(1000, 2000)], closed: true)) }
        XCTAssertEqual(volume(MeshBuilder.build(doc: doc).filter { $0.id == s1 }), full - 2000 * 1000 * 200, accuracy: 1)
        XCTAssertFalse(Shafts.crossItems(doc.entity(sh)!, color: .white).isEmpty)
        // A hosted opening cuts only its host, including a roof.
        let roof = doc.addElement(.roof(RoofGeom(boundary: [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)], kind: .gable, pitch: 30, overhang: 0)), level: 1)
        let rv = volume(MeshBuilder.build(doc: doc).filter { $0.id == roof })
        Shafts.add([Vec2(4500, 500), Vec2(5500, 500), Vec2(5500, 1500), Vec2(4500, 1500)], base: nil, top: nil, host: roof, doc: &doc)
        let rv2 = volume(MeshBuilder.build(doc: doc).filter { $0.id == roof })
        let tv = 250 / cos(30 * Double.pi / 180)
        XCTAssertEqual(rv - rv2, 1000 * 1000 * tv, accuracy: 1000 * 1000 * tv * 0.01)
    }

    func testSkylightDormerAndRoofEdges() async {
        let ed = Editor()
        let roof = ed.doc.addElement(.roof(RoofGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)], kind: .gable, pitch: 35, overhang: 500, baseOffset: 3000)))
        ed.selection = []
        await ed.run("SKYLIGHT #\(roof) 780 1180 3000,2000 ")
        guard let sky = ed.doc.elements.first(where: { $0.props["kind"] == "skylight" }) else { return XCTFail("no skylight") }
        let sg = MeshBuilder.build(doc: ed.doc).filter { $0.id == sky.id }
        XCTAssertEqual(Set(sg.map(\.material)), ["Aluminium", "Glass"])
        XCTAssertGreaterThan(bounds(sg).min.z, 3000, "sits in the roof plane")
        XCTAssertEqual(Shafts.holes(for: ed.doc.element(roof)!, doc: ed.doc).count, 1, "the skylight cuts the roof")
        // Dormer: walls, a roof and an opening in the main roof.
        let before = ed.doc.elements.count
        await ed.run("DORMER #\(roof) 7000,2000 1800 1400 Gable")
        let dormer = ed.doc.elements.filter { $0.props["dormer"] != nil }
        XCTAssertEqual(ed.doc.elements.count - before, 4)
        XCTAssertEqual(dormer.filter { if case .wall = $0.geometry { return true }; return false }.count, 3)
        XCTAssertEqual(dormer.filter { if case .roof = $0.geometry { return true }; return false }.count, 1)
        XCTAssertEqual(Shafts.holes(for: ed.doc.element(roof)!, doc: ed.doc).count, 2)
        // Roof edges: fascia, gutter and soffit groups.
        ed.selection = [roof]
        await ed.run("ROOFEDGE 200 125 HalfRound Yes")
        let kinds = Set(MeshBuilder.build(doc: ed.doc).filter { $0.id == roof }.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: ["fascia", "gutter", "soffit"]), "\(kinds)")
        let fascia = MeshBuilder.build(doc: ed.doc).filter { $0.id == roof && $0.kind == "fascia" }
        XCTAssertEqual(bounds(fascia).max.x - bounds(fascia).min.x, 11000 + 50, accuracy: 60, "eaves run along the long sides")
    }

    func testRailingTypesElevatorGroupsAndTrim() async {
        let ed = Editor()
        await ed.run("RAILING 0,0 3000,0 ")
        let rail = ed.doc.elements[0].id
        ed.selection = [rail]
        await ed.run("RAILINGTYPE Glass")
        guard case .railing(let r) = ed.doc.element(rail)!.geometry else { return XCTFail() }
        XCTAssertEqual(r.infill, "glass")
        XCTAssertTrue(MeshBuilder.build(doc: ed.doc).filter { $0.id == rail }.contains { $0.material == "Glass" })
        ed.selection = [rail]
        await ed.run("RAILINGTYPE Balusters")
        let bal = MeshBuilder.build(doc: ed.doc).filter { $0.id == rail }
        XCTAssertGreaterThan(bal.count, 2)
        // Round-trip of the optional railing fields.
        let back = try! ArchiFile.decode(try! ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.element(rail)?.geometry, ed.doc.element(rail)?.geometry)

        // Elevator: car, shaft, walls with doors per level.
        await ed.run("ELEVATOR 10000,0 1100 1400 0 \"First Floor\" Yes")
        let lift = ed.doc.elements.filter { $0.props["elevator"] != nil }
        XCTAssertEqual(lift.filter { if case .wall = $0.geometry { return true }; return false }.count, 4)
        XCTAssertEqual(lift.filter { if case .opening = $0.geometry { return true }; return false }.count, 2)
        XCTAssertTrue(ed.doc.entities.contains { Shafts.isShaft($0) && $0.props["elevator"] != nil })
        let car = lift.first { if case .component(let g) = $0.geometry { return g.family == "elevator" }; return false }!
        XCTAssertFalse(MeshBuilder.build(doc: ed.doc).filter { $0.id == car.id }.isEmpty)

        // Model groups: create from two components, place, edit one instance, update the others.
        let c1 = ed.doc.addElement(.component(ComponentGeom(position: Vec2(20000, 0), family: "table")))
        let c2 = ed.doc.addElement(.component(ComponentGeom(position: Vec2(20000, 800), family: "chair")))
        ed.selection = [c1, c2]
        await ed.run("MODELGROUP Create Dining 20000,0")
        await ed.run("MODELGROUP Place Dining 30000,0 90 ")
        let inst = ModelGroups.instances("Dining", doc: ed.doc)
        XCTAssertEqual(inst.count, 2)
        let chair2 = inst[2]!.compactMap { ed.doc.element($0) }.first { if case .component(let g) = $0.geometry { return g.family == "chair" }; return false }!
        guard case .component(let cg) = chair2.geometry else { return XCTFail() }
        XCTAssertEqual(cg.position.x, 30000 - 800, accuracy: 1e-6, "rotated 90°")
        // Move the chair of instance 1 and push the change to instance 2.
        if let i = ed.doc.elementIndex(c2), case .component(var g) = ed.doc.elements[i].geometry { g.position = Vec2(20000, 1200); ed.doc.elements[i].geometry = .component(g) }
        XCTAssertEqual(ModelGroups.update(fromInstanceOf: c2, doc: &ed.doc), 1)
        let chairNew = ModelGroups.instances("Dining", doc: ed.doc)[2]!.compactMap { ed.doc.element($0) }.first { if case .component(let g) = $0.geometry { return g.family == "chair" }; return false }!
        guard case .component(let cg2) = chairNew.geometry else { return XCTFail() }
        XCTAssertEqual(cg2.position.x, 30000 - 1200, accuracy: 1e-6)

        // Opening trim: casings, window board and lintel.
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 10000), end: Vec2(5000, 10000), thickness: 300)))
        let win = ed.doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2500, width: 1200, height: 1200, sill: 900)))
        ed.selection = [win]
        await ed.run("OPENINGTRIM 70 200 200 150")
        let tg = MeshBuilder.build(doc: ed.doc).filter { $0.id == win }
        let lintel = tg.filter { $0.kind == "lintel" }
        XCTAssertEqual(bounds(lintel).max.x - bounds(lintel).min.x, 1500, accuracy: 1e-6)
        XCTAssertEqual(bounds(lintel).min.z, 2100, accuracy: 2)
        XCTAssertFalse(tg.filter { $0.kind == "trim" }.isEmpty)
        XCTAssertGreaterThan(PlanRepresentation.items(ed.doc.element(win)!, doc: ed.doc).count, 10)
    }
}
