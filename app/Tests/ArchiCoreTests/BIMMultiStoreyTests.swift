// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMMultiStoreyTests: XCTestCase {
    func wallGroup(_ doc: ArchiDocument, _ id: EntityID) -> Mesh {
        var m = Mesh()
        for g in MeshBuilder.build(doc: doc) where g.id == id && g.kind == "wall" { m.append(g.mesh) }
        return m
    }

    func testStackedOpeningsCutSeparateHoles() {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200, height: 3000)))
        // A door under a high window whose width overlaps the door along the wall.
        _ = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1500, width: 900, height: 2100)))
        _ = doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 1800, width: 1200, height: 500, sill: 2400)))
        let v = MeshTools.signedVolume(wallGroup(doc, w))
        let full: Double = 5000 * 200 * 3000, door: Double = 900 * 2100 * 200, win: Double = 1200 * 500 * 200
        let expected = full - door - win
        XCTAssertEqual(v, expected, accuracy: expected * 1e-9)
        // Two windows stacked exactly (ground window under an upper window).
        var d2 = ArchiDocument()
        let w2 = d2.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 300, height: 6000)))
        _ = d2.addElement(.opening(OpeningGeom(kind: .window, hostWall: w2, offset: 2000, width: 1000, height: 1200, sill: 900)))
        _ = d2.addElement(.opening(OpeningGeom(kind: .window, hostWall: w2, offset: 2000, width: 1000, height: 1200, sill: 3900)))
        let v2 = MeshTools.signedVolume(wallGroup(d2, w2))
        let full2: Double = 4000 * 300 * 6000, win2: Double = 2 * 1000 * 1200 * 300
        XCTAssertEqual(v2, full2 - win2, accuracy: 1)
        // The band between the windows (2100–3900) stays solid: a ray through the wall at z = 3000 hits wall faces.
        let hit = MeshTools.triangles(wallGroup(d2, w2)).contains { t -> Bool in
            let ys: [Double] = [t.0.y, t.1.y, t.2.y], zs: [Double] = [t.0.z, t.1.z, t.2.z], xs: [Double] = [t.0.x, t.1.x, t.2.x]
            let onFace = ys.allSatisfy { abs($0 - 150) < 1e-6 }
            let spansZ = zs.min()! <= 3000 && zs.max()! >= 3000
            let spansX = xs.min()! <= 2000 && xs.max()! >= 2000
            return onFace && spansZ && spansX
        }
        XCTAssertTrue(hit)
    }

    func testWallUpToLevelSpansAndShowsOnUpperPlan() async {
        let ed = Editor()
        ed.doc.levels.append(Level(id: 2, name: "Roof", elevation: 6000))
        await ed.run("WALL Top Roof 0 0,0 5000,0 ")
        guard let el = ed.doc.elements.first, case .wall(let w) = el.geometry else { return XCTFail() }
        XCTAssertEqual(w.topLevel, 2)
        XCTAssertEqual(w.height, 6000, accuracy: 1e-9)
        XCTAssertEqual(BIMConstraints.wallRange(el, doc: ed.doc).z1, 6000, accuracy: 1e-9)
        XCTAssertEqual(BIMConstraints.extraLevels(el, doc: ed.doc), [1])
        XCTAssertTrue(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1)).contains { $0.id == el.id })
        XCTAssertFalse(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 2)).contains { $0.id == el.id })
        // A door on the ground floor does not break the wall in the first-floor plan.
        await ed.run("DOOR 2500,0 ")
        func fills(_ level: Int) -> Int {
            DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: level)).first { $0.id == el.id }!.items.filter { if case .fill = $0 { return true }; return false }.count
        }
        XCTAssertEqual(fills(0), 2)
        XCTAssertEqual(fills(1), 1)
        let doorID = ed.doc.elements.last!.id
        XCTAssertFalse(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1)).contains { $0.id == doorID })
        ed.undo()
        // Moving the top level updates the constrained height.
        await ed.run("LEVEL Elevation Roof 7000")
        guard case .wall(let w2) = ed.doc.elements[0].geometry else { return XCTFail() }
        XCTAssertEqual(w2.height, 7000, accuracy: 1e-9)
        // WALLTOP: unconnected, then up to the next level with an offset.
        ed.selection = [el.id]
        await ed.run("WALLTOP Unconnected 2500")
        guard case .wall(let w3) = ed.doc.elements[0].geometry else { return XCTFail() }
        XCTAssertNil(w3.topLevel); XCTAssertEqual(w3.height, 2500)
        ed.selection = [el.id]
        await ed.run("WALLTOP Next -200")
        guard case .wall(let w4) = ed.doc.elements[0].geometry else { return XCTFail() }
        XCTAssertEqual(w4.topLevel, 1); XCTAssertEqual(w4.height, 2800, accuracy: 1e-9)
    }

    func testWallAttachToSlabAndRoof() async {
        let ed = Editor()
        await ed.run("WALL H 3500 0,0 4000,0 ")
        let wall = ed.doc.elements[0].id
        ed.doc.currentLevel = 1
        await ed.run("SLAB -500,-500 4500,-500 4500,500 -500,500 ")
        let slab = ed.doc.elements.last!.id
        ed.doc.currentLevel = 0
        ed.selection = [wall]
        await ed.run("WALLATTACH Top #\(slab)")
        XCTAssertEqual(ed.doc.element(wall)?.props["attachTopTo"], "\(slab)")
        let r = BIMConstraints.wallRange(ed.doc.element(wall)!, doc: ed.doc)
        XCTAssertEqual(r.z1, 2800, accuracy: 1e-9)   // level 1 at 3000, slab 200 thick
        // Sloped slab: the wall follows the soffit (infill above the lowest point).
        if let i = ed.doc.elementIndex(slab), case .slab(var s) = ed.doc.elements[i].geometry {
            s.slope = 5; s.slopeDirection = 0; s.slopeOrigin = Vec2(-500, 0); ed.doc.elements[i].geometry = .slab(s)
        }
        let flatVol = 4000.0 * 200 * 2800
        let vol = MeshTools.signedVolume(wallGroup(ed.doc, wall))
        XCTAssertGreaterThan(vol, flatVol * 1.05)
        ed.selection = [wall]
        await ed.run("WALLATTACH Detach Both")
        XCTAssertNil(ed.doc.element(wall)?.props["attachTopTo"])
        XCTAssertEqual(BIMConstraints.wallRange(ed.doc.element(wall)!, doc: ed.doc).z1, 3500, accuracy: 1e-9)
    }

    func testCopyToLevelRehostsOpenings() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 6000,4000 ")
        await ed.run("DOOR 3000,0 ")
        let n0 = ed.doc.elements.count
        XCTAssertEqual(n0, 3)
        ed.selection = Set(ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }.map(\.id))
        await ed.run("COPYTOLEVEL Above")
        XCTAssertEqual(ed.doc.elements.count, 6)
        let upper = ed.doc.elements.filter { $0.level == 1 }
        XCTAssertEqual(upper.count, 3)
        guard let door = upper.first(where: { if case .opening = $0.geometry { return true }; return false }), case .opening(let o) = door.geometry else { return XCTFail() }
        XCTAssertEqual(ed.doc.element(o.hostWall)?.level, 1)
        ed.undo()
        XCTAssertEqual(ed.doc.elements.count, n0)
    }

    func testStairLandingsAndLevels() async {
        let g = StairGeom(start: .zero, width: 1000, totalRise: 3150, riserCount: 18, treadDepth: 280, landingDepth: 1100, landingAt: 9)
        let l = StairShapes.layout(g)
        XCTAssertEqual(l.treads.count, 17)
        XCTAssertEqual(l.treads.filter(\.landing).count, 1)
        XCTAssertEqual(l.treads.first { $0.landing }?.step, 9)
        let expected127_1: Double = 8 * 280 + 1100 + 8 * 280
        XCTAssertEqual(l.walk.last!.x, expected127_1, accuracy: 1e-9)
        XCTAssertTrue(BIMConstraints.stairIssues(g).isEmpty, BIMConstraints.stairIssues(g).joined())
        XCTAssertTrue(BIMConstraints.stairIssues(StairGeom(start: .zero, totalRise: 4000, riserCount: 22)).contains { $0.contains("flight") })
        // U stair with a custom landing depth.
        let u = StairShapes.layout(StairGeom(start: .zero, riserCount: 18, kind: .uShape, landingDepth: 1400))
        let land = u.treads.first { $0.landing }!
        XCTAssertEqual(BBox2(points: land.poly).width, 1400, accuracy: 1e-6)
        // STAIR between levels: arrives at the level above and shows DN there.
        let ed = Editor()
        await ed.run("STAIR 0,0 0")
        guard let st = ed.doc.elements.last, case .stair(let s) = st.geometry else { return XCTFail() }
        XCTAssertEqual(s.topLevel, 1); XCTAssertEqual(s.totalRise, 3000)
        let up = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1)).first { $0.id == st.id }
        XCTAssertNotNil(up)
        XCTAssertTrue(up!.items.contains { if case .text(let t, _, _) = $0 { return t.content == "DN" }; return false })
        await ed.run("STAIR Landing 9 1200 0,3000 0")
        guard case .stair(let s2) = ed.doc.elements.last!.geometry else { return XCTFail() }
        XCTAssertEqual(s2.landingAt, 9); XCTAssertEqual(s2.landingDepth, 1200)
    }

    func testRampFlightsAndLandings() async {
        guard let p = RampLayout.build(path: [.zero, Vec2(12000, 0)], width: 1200, rise: 1000, thickness: 200, maxRise: 500, landingLength: 1500) else { return XCTFail() }
        XCTAssertEqual(p.filter { !$0.landing }.count, 2)
        XCTAssertEqual(p.filter(\.landing).count, 1)
        let last = p.last!.slab
        XCTAssertEqual(last.topHeight(at: Vec2(12000, 0)), 1000, accuracy: 1e-6)
        XCTAssertEqual(p[1].slab.topOffset, 500, accuracy: 1e-6)
        // L-shaped path: a corner landing joins the two flights.
        guard let lp = RampLayout.build(path: [.zero, Vec2(8000, 0), Vec2(8000, 6000)], width: 1200, rise: 600, thickness: 150, maxRise: 0, landingLength: 1500) else { return XCTFail() }
        XCTAssertEqual(lp.count, 3)
        XCTAssertTrue(lp[1].landing)
        XCTAssertEqual(lp[2].slab.topHeight(at: Vec2(8000, 6000)), 600, accuracy: 1e-6)
        let ed = Editor()
        await ed.run("RAMP R 1000 Landings 500 1500 0,0 12000,0")
        XCTAssertEqual(ed.doc.elements.count, 3)
        XCTAssertEqual(ed.doc.elements.filter { $0.props["kind"] == "landing" }.count, 1)
    }

    func testRoomBoundingRules() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("WALL 4000,0 4000,5000 ")
        let partition = ed.doc.elements.last!.id
        await ed.run("ROOM 2000,2500 ")
        guard case .space(let small) = ed.doc.elements.last!.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(small.boundary)), 3800 * 4800, accuracy: 1)
        ed.selection = [partition]
        await ed.run("ROOMBOUNDING No")
        XCTAssertEqual(ed.doc.element(partition)?.props["roomBounding"], "0")
        ed.doc.elements.removeLast()
        await ed.run("ROOM 2000,2500 ")
        guard case .space(let big) = ed.doc.elements.last!.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(big.boundary)), 7800 * 4800, accuracy: 1)
        // Walls rising from the level below bound rooms on the upper level.
        let ed2 = Editor()
        ed2.doc.levels.append(Level(id: 2, name: "Roof", elevation: 6000))
        await ed2.run("WALL Top Roof 0 0,0 6000,0 6000,4000 0,4000 C")
        XCTAssertNil(RoomBounding.boundary(at: Vec2(3000, 2000), doc: ed2.doc, level: 2))
        XCTAssertNotNil(RoomBounding.boundary(at: Vec2(3000, 2000), doc: ed2.doc, level: 1))
    }

    func testCeilingByRoomAndCurtainWallDoor() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 5000,4000 0,4000 C")
        await ed.run("ROOM Height 2600 2500,2000 ")
        await ed.run("CEILING Room 2500,2000 ")
        guard let c = ed.doc.elements.last, case .slab(let s) = c.geometry else { return XCTFail() }
        XCTAssertEqual(c.props["kind"], "ceiling")
        XCTAssertEqual(s.topOffset - s.thickness, 2600, accuracy: 1e-9)
        var doc = ArchiDocument()
        let id = doc.addElement(.curtainWall(CurtainWallGeom(start: .zero, end: Vec2(3600, 0), height: 3000, gridU: 1200, gridV: 2400)))
        let plain = MeshBuilder.build(doc: doc).reduce(0) { $0 + $1.mesh.triangleCount }
        if let i = doc.elementIndex(id), case .curtainWall(var g) = doc.elements[i].geometry { g.panels["1,0"] = "door"; doc.elements[i].geometry = .curtainWall(g) }
        let withDoor = MeshBuilder.build(doc: doc).reduce(0) { $0 + $1.mesh.triangleCount }
        XCTAssertGreaterThan(withDoor, plain)
        let items = PlanRepresentation.items(doc.element(id)!, doc: doc)
        XCTAssertGreaterThan(items.count, PlanRepresentation.items(BIMElement(id: 99, geometry: .curtainWall(CurtainWallGeom(start: .zero, end: Vec2(3600, 0), height: 3000, gridU: 1200, gridV: 2400))), doc: doc).count)
    }

    func testDatums3D() {
        var doc = ArchiDocument()
        _ = doc.addElement(.gridLine(GridLineGeom(start: .zero, end: Vec2(0, 10000), label: "1")))
        _ = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        XCTAssertFalse(MeshBuilder.build(doc: doc).contains { $0.kind == "datum" })
        doc.setVariable("DATUMS3D", "1")
        let d = MeshBuilder.build(doc: doc).filter { $0.kind == "datum" }
        XCTAssertEqual(d.count, 2)
        XCTAssertTrue(d.allSatisfy { $0.mesh.isEmpty && !$0.edges.isEmpty })
        let zs = Set(d.flatMap { $0.edges.flatMap { $0.map(\.z) } })
        XCTAssertTrue(zs.contains(0) && zs.contains(3000))
        // Grids are drawn on every level plan.
        XCTAssertTrue(DrawListBuilder.entries(doc: doc, options: DrawOptions(level: 1)).contains { $0.id == 1 })
    }

    func testComponentLibraryFamilies() async {
        XCTAssertGreaterThanOrEqual(ComponentLibrary.families.count, 25)
        XCTAssertEqual(Set(ComponentLibrary.families.map(\.id)).count, ComponentLibrary.families.count)
        for f in ComponentLibrary.families {
            let g = ComponentGeom(category: f.category, position: .zero, rotation: 0, size: f.size, family: f.id)
            let groups = ComponentLibrary.meshGroups(f, g, id: 1, z0: 0, overrides: [:])
            XCTAssertFalse(groups.isEmpty, f.id)
            var b = BBox3.empty
            for gr in groups { XCTAssertTrue(gr.mesh.triangleCount > 0, f.id); for p in gr.mesh.positions { b.add(p) } }
            XCTAssertGreaterThan(b.min.z, -1e-6, f.id)
            XCTAssertLessThanOrEqual(max(-b.min.x, b.max.x), f.size.x / 2 + 1e-6, f.id)
            XCTAssertLessThanOrEqual(max(-b.min.y, b.max.y), f.size.y / 2 + 60, f.id)   // handles and taps may stand proud of the front
            // Rotation and position are applied.
            let moved = ComponentLibrary.meshGroups(f, ComponentGeom(position: Vec2(1000, 2000), rotation: .pi / 2, size: f.size, family: f.id), id: 1, z0: 500, overrides: [:])
            var mb = BBox3.empty
            for gr in moved { for p in gr.mesh.positions { mb.add(p) } }
            XCTAssertEqual(mb.max.x - mb.min.x, b.max.y - b.min.y, accuracy: 1e-6, f.id)
            XCTAssertEqual(mb.min.z, b.min.z + 500, accuracy: 1e-6, f.id)
            let sym = ComponentLibrary.symbol(f, size: f.size)
            XCTAssertTrue(sym.contains { $0.outline }, f.id)
            // Parametric: a wider instance gives a wider mesh.
            let wide = ComponentLibrary.meshGroups(f, ComponentGeom(position: .zero, size: Vec3(f.size.x * 1.5, f.size.y, f.size.z), family: f.id), id: 1, z0: 0, overrides: [:])
            var wb = BBox3.empty
            for gr in wide { for p in gr.mesh.positions { wb.add(p) } }
            XCTAssertGreaterThan(wb.max.x - wb.min.x, f.size.x * 1.2, f.id)
            for gr in groups { XCTAssertNotNil(ComponentLibrary.materials.first { $0.name == gr.material } ?? Material.library.first { $0.name == gr.material }, "\(f.id): \(gr.material)") }
        }
        XCTAssertEqual(ComponentLibrary.family("Double Bed")?.id, "bed-double")
        XCTAssertEqual(ComponentLibrary.family("toilet")?.id, "wc")
        let ed = Editor()
        await ed.run("COMPONENT sofa 1000,1000 ")
        guard let el = ed.doc.elements.last, case .component(let c) = el.geometry else { return XCTFail() }
        XCTAssertEqual(c.family, "sofa")
        XCTAssertNotNil(ed.doc.material("Fabric"))
        XCTAssertTrue(MeshBuilder.build(doc: ed.doc).contains { $0.id == el.id && $0.material == "Fabric" })
        await ed.run("COMPONENT KitchenWall 0,3000 ")
        guard case .component(let kw) = ed.doc.elements.last!.geometry else { return XCTFail() }
        XCTAssertEqual(kw.baseOffset, 1450)
    }
}
