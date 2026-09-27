// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Core building elements: walls from curves, joins, doors/windows, slabs by walls, columns/beams, stair railings,
/// wall types and level plans.
@MainActor
final class BIMPhase1Tests: XCTestCase {
    func walls(_ ed: Editor) -> [(EntityID, WallGeom)] { ed.doc.elements.compactMap { if case .wall(let w) = $0.geometry { return ($0.id, w) }; return nil } }
    func volume(_ el: BIMElement, _ doc: ArchiDocument, kind: String? = nil) -> Double {
        MeshBuilder.groups(for: el, doc: doc).filter { kind == nil || $0.kind == kind }.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) }
    }

    // BIM-011
    func testWallsFromLinesArcsAndPolylines() async throws {
        let ed = Editor()
        let pl = ed.doc.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(6000, 0), bulge: 0.3), PolyVertex(Vec2(6000, 4000)), PolyVertex(Vec2(0, 4000))], closed: true)))
        let ln = ed.doc.add(.line(LineGeom(Vec2(10000, 0), Vec2(14000, 0))))
        let ar = ed.doc.add(.arc(ArcGeom(Vec2(20000, 0), 2000, 0, .pi / 2)))
        ed.selection = [pl, ln, ar]
        await ed.run("WALLBYLINES 200 3000 Center Yes")
        let ws = walls(ed)
        XCTAssertEqual(ws.count, 6)
        XCTAssertTrue(ws.contains { abs($0.1.bulge - 0.3) < 1e-9 })
        XCTAssertTrue(ed.doc.entities.isEmpty, "sources deleted")
        // The closed chain joins cleanly: a room fits inside and the corners are mitred (no overlaps).
        await ed.run("ROOM 3000,2000 ")
        XCTAssertNotNil(ed.doc.elements.last.flatMap { if case .space = $0.geometry { return $0 }; return nil })
        let ctx = PlanRepresentation.context(ed.doc)
        let ring = ws.prefix(4).map { ctx.outline(ctx.frames[$0.0]!) }
        for i in 0..<ring.count { for j in (i + 1)..<ring.count {
            XCTAssertLessThan(abs(PolygonBoolean.area(PolygonBoolean.apply(.intersect, [ring[i]], [ring[j]]))), 1)
        } }
    }

    // BIM-016
    func testWallJoinsHaveNoOverlap() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 6000,4000 ")          // L corner
        await ed.run("WALL 3000,0 3000,4000 ")              // T into the first wall's side
        await ed.run("WALL 0,2000 6000,2000 ")              // X crossing the T wall
        let ctx = PlanRepresentation.context(ed.doc)
        let outlines = walls(ed).map { ctx.outline(ctx.frames[$0.0]!) }
        var overlap = 0.0
        for i in 0..<outlines.count { for j in (i + 1)..<outlines.count {
            overlap += abs(PolygonBoolean.area(PolygonBoolean.apply(.intersect, [outlines[i]], [outlines[j]])))
        } }
        XCTAssertLessThan(overlap, 200 * 200 + 1, "at most the X-crossing square overlaps")
        // L corner: the union is exactly the mitred L.
        let l = PolygonBoolean.area(PolygonBoolean.apply(.union, [outlines[0]], [outlines[1]]))
        let expected: Double = 6100.0 * 200.0 + 4000.0 * 200.0
        XCTAssertEqual(l, expected, accuracy: 200 * 200)
        XCTAssertLessThan(abs(PolygonBoolean.area(PolygonBoolean.apply(.intersect, [outlines[0]], [outlines[1]]))), 1)
    }

    // BIM-034 / BIM-035
    func testDoorAndWindowCutWallInPlanAnd3D() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 ")
        let wid = walls(ed)[0].0
        let full = volume(ed.doc.element(wid)!, ed.doc)
        await ed.run("DOOR Flip 2000,0 ")
        await ed.run("WINDOW Sill 1000 6000,0 ")
        let ctx = PlanRepresentation.context(ed.doc)
        XCTAssertEqual(ctx.pieces(ctx.frames[wid]!).count, 3)
        let cut = volume(ed.doc.element(wid)!, ed.doc)
        let expected67_1: Double = 900 * 200 * 2100 + 1200 * 200 * 1200
        XCTAssertEqual(full - cut, expected67_1, accuracy: 1000)
        let door = ed.doc.elements.first { if case .opening(let o) = $0.geometry { return o.kind == .door }; return false }!
        guard case .opening(let d) = door.geometry else { return XCTFail() }
        XCTAssertTrue(d.flipHand)
        XCTAssertEqual(d.mark, "D01")
        // Door swing arc in plan.
        XCTAssertTrue(PlanRepresentation.items(door, doc: ed.doc).contains { if case .stroke(let p, false, _) = $0 { return p.count > 20 }; return false })
        let win = ed.doc.elements.first { if case .opening(let o) = $0.geometry { return o.kind == .window }; return false }!
        let glass = MeshBuilder.groups(for: win, doc: ed.doc).filter { $0.material == "Glass" }.flatMap(\.mesh.positions).map(\.z)
        XCTAssertGreaterThanOrEqual(glass.min() ?? 0, 1000 - 1e-6)
        XCTAssertLessThanOrEqual(glass.max() ?? 0, 2200 + 1e-6)
    }

    // BIM-048
    func testSlabByPickingWallsMatchesOutline() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        ed.selection = []
        await ed.run("SLAB Walls Pick ALL ")
        guard case .slab(let s)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), 8200 * 5200, accuracy: 1)
        XCTAssertEqual(s.boundary.count, 4)
        // Point inside, mixed thicknesses: the outline follows each wall's outside face.
        let ed2 = Editor()
        await ed2.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        ed2.transaction("thick") { doc in if case .wall(var w) = doc.elements[0].geometry { w.thickness = 400; doc.elements[0].geometry = .wall(w) } }
        await ed2.run("SLAB Walls 4000,2500 ")
        guard case .slab(let s2)? = ed2.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(BBox2(points: s2.boundary).min.y, -200, accuracy: 1e-6)
        XCTAssertEqual(BBox2(points: s2.boundary).max.y, 5100, accuracy: 1e-6)
        // Holes cut through the slab.
        await ed2.run("SLABOPENING 3000,2000 4000,2000 4000,3000 3000,3000 ")
    }

    // BIM-076 / BIM-079
    func testColumnsAndBeamsBetweenColumns() async throws {
        let ed = Editor()
        await ed.run("COLUMN 0,0 6000,0 ")
        await ed.run("COLUMN Round Yes Width 400 6000,5000 ")
        let cols = ed.doc.elements.compactMap { el -> ColumnGeom? in if case .column(let c) = el.geometry { return c }; return nil }
        XCTAssertEqual(cols.count, 3)
        XCTAssertTrue(cols[2].round)
        XCTAssertEqual(MeshTools.signedVolume(MeshBuilder.groups(for: ed.doc.elements[2], doc: ed.doc)[0].mesh), Double.pi * 200 * 200 * 3000, accuracy: Double.pi * 200 * 200 * 3000 * 0.02)
        await ed.run("BEAM Columns 0,0 6000,0 6000,5000 ")
        let beams = ed.doc.elements.compactMap { el -> BeamGeom? in if case .beam(let b) = el.geometry { return b }; return nil }
        XCTAssertEqual(beams.count, 2)
        XCTAssertEqual(beams[0].start, Vec2(0, 0)); XCTAssertEqual(beams[0].end, Vec2(6000, 0))
        XCTAssertEqual(beams[0].topOffset, cols[0].height, accuracy: 1e-9)
        XCTAssertEqual(beams[1].end, Vec2(6000, 5000))
    }

    // BIM-072
    func testRailingsOnStairFollowFlights() async throws {
        let ed = Editor()
        let sid = ed.doc.addElement(.stair(StairGeom(start: Vec2(0, 0), direction: 0, width: 1200, totalRise: 2975, riserCount: 17, treadDepth: 280)))
        await ed.run("RAILING Height 900 Stair 2000,0 ")
        let rails = ed.doc.elements.filter { $0.props["hostStair"] == "\(sid)" }
        XCTAssertEqual(rails.count, 2)
        guard case .railing(let r) = rails[0].geometry else { return XCTFail() }
        XCTAssertEqual(r.path.count, 2)
        XCTAssertEqual(r.path[1].x - r.path[0].x, 16 * 280, accuracy: 1e-6)
        XCTAssertEqual(r.pathZ![1] - r.pathZ![0], 16 * 175, accuracy: 1e-6)
        XCTAssertEqual(abs(r.path[0].y), 550, accuracy: 1e-6)
        // 3D rises with the stair.
        let zs = MeshBuilder.groups(for: rails[0], doc: ed.doc).flatMap(\.mesh.positions).map(\.z)
        XCTAssertEqual(zs.max() ?? 0, 17 * 175 + 900, accuracy: 60)
        // Plan: solid below the cut plane, dashed above.
        let items = PlanRepresentation.items(rails[0], doc: ed.doc)
        XCTAssertTrue(items.contains { if case .stroke(_, _, let st) = $0 { return !st.dash.isEmpty }; return false })
        XCTAssertTrue(items.contains { if case .stroke(_, _, let st) = $0 { return st.dash.isEmpty }; return false })
        // Associative: a wider stair moves the railings.
        ed.transaction("w") { doc in if case .stair(var s) = doc.elements[doc.elementIndex(sid)!].geometry { s.width = 1600; doc.elements[doc.elementIndex(sid)!].geometry = .stair(s) } }
        guard case .railing(let r2)? = ed.doc.element(rails[0].id)?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(r2.path[0].y), 750, accuracy: 1e-6)
        // Typed railing types follow the slope too.
        ed.selection = [rails[0].id]
        await ed.run("RAILINGTYPE Glass")
        let gz = MeshBuilder.groups(for: ed.doc.element(rails[0].id)!, doc: ed.doc).filter { $0.material == "Glass" }.flatMap(\.mesh.positions).map(\.z)
        XCTAssertGreaterThan((gz.max() ?? 0) - (gz.min() ?? 0), 2000)
        // U-shaped stair: two flights → four railings.
        let u = ed.doc.addElement(.stair(StairGeom(start: Vec2(10000, 0), width: 1000, riserCount: 18, kind: .uShape)))
        XCTAssertEqual(StairRailings.create(on: u, height: 900, doc: &ed.doc).count, 4)
    }

    // BIM-014 / BIM-015
    func testWallTypeEditorAndPlies() async throws {
        let ed = Editor()
        await ed.run("WALL Type New \"Timber 250\" \"Plasterboard 12.5 Finish; Timber 150 Structure; Insulation 75 Thermal; Render 12.5 Finish\" 0,0 5000,0 ")
        let wt = try XCTUnwrap(ed.doc.wallTypes.first { $0.name == "Timber 250" })
        XCTAssertEqual(wt.thickness, 250, accuracy: 1e-9)
        XCTAssertEqual(wt.plies.map(\.function), ["Finish", "Structure", "Thermal", "Finish"])
        XCTAssertEqual(WallTypeEditor.core(wt).from, 12.5, accuracy: 1e-9); XCTAssertEqual(WallTypeEditor.core(wt).to, 162.5, accuracy: 1e-9)
        XCTAssertNotNil(ed.doc.material("Plasterboard"))
        let w = walls(ed)[0].1
        XCTAssertEqual(w.wallType, "Timber 250"); XCTAssertEqual(w.thickness, 250, accuracy: 1e-9)
        XCTAssertEqual(MeshBuilder.groups(for: ed.doc.elements[0], doc: ed.doc).filter { $0.kind == "wall" }.count, 4)
        // Editing the type re-thickens its walls.
        await ed.run("WALL Type Edit \"Timber 250\" \"Plasterboard 12.5 Finish; Timber 200 Structure; Render 12.5 Finish\" ")
        XCTAssertEqual(walls(ed)[0].1.thickness, 225, accuracy: 1e-9)
        await ed.run("WALL Type Delete \"Timber 250\" ")
        XCTAssertNotNil(ed.doc.wallTypes.first { $0.name == "Timber 250" }, "types in use are kept")
        XCTAssertNil(WallTypeEditor.parse("Brick", doc: ed.doc))
    }

    // DOC-001
    func testPlanPerLevelShowsNewWallImmediately() async throws {
        let ed = Editor()
        await ed.run("LEVEL Set 1")
        await ed.run("WALL 0,0 4000,0 ")
        let wid = walls(ed)[0].0
        let upper = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1))
        XCTAssertTrue(upper.contains { $0.id == wid })
        let ground = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertFalse(ground.contains { $0.id == wid })
    }
}
