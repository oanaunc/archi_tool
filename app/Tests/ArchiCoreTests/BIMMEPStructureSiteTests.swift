// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMMEPStructureSiteTests: XCTestCase {
    func bounds(_ groups: [MeshGroup]) -> BBox3 { var b = BBox3.empty; for g in groups { b.add(g.mesh.bounds.min); b.add(g.mesh.bounds.max) }; return b }
    func components(_ ed: Editor) -> [ComponentGeom] { ed.doc.elements.compactMap { if case .component(let c) = $0.geometry { return c }; return nil } }

    func testStructuralProfiles() async {
        let ipe = StructuralProfiles.section("IPE300")!
        XCTAssertEqual(ipe.h, 300); XCTAssertEqual(ipe.b, 150); XCTAssertEqual(ipe.outline().outer.count, 12)
        XCTAssertEqual(StructuralProfiles.section("rhs 200x100x8")!.area, 200 * 100 - 184 * 84, accuracy: 1e-6)
        XCTAssertEqual(StructuralProfiles.section("CHS 168x6")!.area, Double.pi * (84 * 84 - 78 * 78), accuracy: 60)
        XCTAssertEqual(StructuralProfiles.section("L 100x10")!.area, 100 * 10 + 90 * 10, accuracy: 1e-6)
        let expected16_1: Double = 2 * 150 * 10 + 280 * 7
        XCTAssertEqual(StructuralProfiles.section("I 300x150x7x10")!.area, expected16_1, accuracy: 1e-6)
        XCTAssertEqual(StructuralProfiles.section("T 100x100x10")!.shape, .t)
        XCTAssertEqual(StructuralProfiles.section("SHS 100x5")!.b, 100)
        XCTAssertNil(StructuralProfiles.section("RHS 100x100x60"))
        XCTAssertNil(StructuralProfiles.section("XYZ"))
        XCTAssertNil(StructuralProfiles.section(""))
    }

    func testProfiledBeamColumnAndBrace() async {
        var doc = ArchiDocument()
        doc.addElement(.beam(BeamGeom(start: .zero, end: Vec2(4000, 0), width: 150, depth: 300, topOffset: 3000, profile: "IPE300")))
        doc.addElement(.column(ColumnGeom(position: Vec2(0, 5000), width: 200, depth: 100, height: 3000, profile: "RHS 200x100x8")))
        let groups = MeshBuilder.build(doc: doc)
        XCTAssertEqual(groups.count, 2)
        let ipe = StructuralProfiles.section("IPE300")!
        XCTAssertEqual(MeshTools.signedVolume(groups[0].mesh), ipe.area * 4000, accuracy: ipe.area * 4000 * 1e-6)
        XCTAssertEqual(groups[0].mesh.bounds.max.z, 3000, accuracy: 1e-6); XCTAssertEqual(groups[0].mesh.bounds.min.z, 2700, accuracy: 1e-6)
        XCTAssertEqual(MeshTools.signedVolume(groups[1].mesh), (200 * 100 - 184 * 84) * 3000, accuracy: 1)
        // Plan: hollow column drawn with its hole.
        let col = doc.elements[1]
        XCTAssertTrue(PlanRepresentation.items(col, doc: doc).contains { if case .fill(let l, _) = $0 { return l.count == 2 }; return false })
        // Brace from the floor to 3 m.
        let ed = Editor()
        let log = await ed.run("BRACE 0,0 3000,0 0 3000")
        guard case .beam(let b)? = ed.doc.elements.last?.geometry else { return XCTFail(log.joined(separator: "\n")) }
        XCTAssertTrue(b.isSloped); XCTAssertEqual(ed.doc.elements.last?.props["kind"], "brace")
        let bb = bounds(MeshBuilder.build(doc: ed.doc))
        XCTAssertEqual(bb.min.z, -57, accuracy: 20); XCTAssertEqual(bb.max.z, 3057, accuracy: 20)
        // STEELPROFILE sets the profile and the plan size.
        await ed.run("BEAM 0,5000 5000,5000 ;")
        let beamID = ed.doc.elements.last!.id
        ed.selection = [beamID]
        await ed.run("STEELPROFILE \"HEB200\"")
        guard case .beam(let hb)? = ed.doc.element(beamID)?.geometry else { return XCTFail() }
        XCTAssertEqual(hb.profile, "HEB200"); XCTAssertEqual(hb.width, 200); XCTAssertEqual(hb.depth, 200)
    }

    func testBeamSystemAndTruss() async {
        let lines = BeamSystemLayout.lines(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)], angle: 0, spacing: 1000)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map { $0.0.y }.sorted(), [1000, 2000, 3000])
        XCTAssertEqual(lines[0].0.distance(to: lines[0].1), 6000, accuracy: 1e-6)
        let ed = Editor()
        await ed.run("BEAMSYSTEM Spacing 1000 0,0 6000,0 6000,4000 0,4000 ; 0")
        let beams = ed.doc.elements.filter { $0.props["beamSystem"] != nil }
        XCTAssertEqual(beams.count, 3)
        XCTAssertEqual(Set(beams.map { $0.props["beamSystem"]! }).count, 1)
        // Pratt truss: 2 chords, n+1 verticals, n diagonals.
        XCTAssertEqual(Trusses.members(kind: "pratt", span: 12000, height: 1500).count, 2 + 9 + 8)
        XCTAssertEqual(Trusses.members(kind: "warren", span: 12000, height: 1500, panels: 6).count, 4 + 6)
        XCTAssertEqual(Trusses.members(kind: "fink", span: 9000, height: 2600).count, 7)
        let log = await ed.run("TRUSS Height 1500 0,10000 12000,10000")
        guard let tg = components(ed).last, tg.family == "truss-pratt" else { return XCTFail(log.joined(separator: "\n")) }
        XCTAssertEqual(tg.size.x, 12000, accuracy: 1e-6)
        let tb = bounds(MeshBuilder.groups(for: ed.doc.elements.last!, doc: ed.doc))
        XCTAssertGreaterThanOrEqual(tb.min.x, -1e-6); XCTAssertLessThanOrEqual(tb.max.x, 12000 + 1e-6)
        XCTAssertEqual(tb.min.z, 3000, accuracy: 1); XCTAssertEqual(tb.max.z, 4500, accuracy: 1)
    }

    func testPipesDuctsTraysAndFixtureConnectors() async {
        let ed = Editor()
        await ed.run("MEPPIPE Size 100 Elevation 2500 0,0 5000,0 5000,4000 ;")
        guard let p = components(ed).last, p.family == "pipe" else { return XCTFail() }
        XCTAssertEqual(p.path?.count, 3); XCTAssertEqual(RunFamilies.length(p), 9000, accuracy: 1e-6)
        let groups = MeshBuilder.groups(for: ed.doc.elements.last!, doc: ed.doc)
        XCTAssertEqual(groups.count, 2)                                  // pipe body + elbow sleeves
        let b = bounds(groups)
        XCTAssertEqual(b.min.z, 2442, accuracy: 10); XCTAssertEqual(b.max.z, 2558, accuracy: 10)
        XCTAssertGreaterThan(MeshTools.signedVolume(groups[0].mesh), 0)
        let fl = RunFamilies.filleted([Vec3(0, 0, 0), Vec3(5000, 0, 0), Vec3(5000, 4000, 0)], radius: 150)
        XCTAssertEqual(fl.ends.count, 2); XCTAssertGreaterThan(fl.line.count, 3)
        XCTAssertEqual(fl.ends[0].0.x, 4850, accuracy: 1e-6)
        // Plan: double line, hidden centreline, fitting ticks.
        XCTAssertGreaterThanOrEqual(PlanRepresentation.items(ed.doc.elements.last!, doc: ed.doc).count, 5)
        // MOVE carries the run along (path is local to the position).
        let id = ed.doc.elements.last!.id
        ed.selection = [id]
        await ed.run("MOVE 0,0 1000,0")
        guard case .component(let moved)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(moved.worldPath.last!.x, 6000, accuracy: 1e-6)
        // Duct with flanges; cable tray.
        await ed.run("DUCT Size 400 250 0,10000 6000,10000 6000,14000 ;")
        let duct = MeshBuilder.groups(for: ed.doc.elements.last!, doc: ed.doc)
        XCTAssertEqual(duct.count, 2); XCTAssertGreaterThan(MeshTools.signedVolume(duct[0].mesh), 400 * 250 * 9000 * 0.95)
        await ed.run("CABLETRAY 0,20000 5000,20000 ;")
        XCTAssertEqual(components(ed).last?.family, "cabletray")
        // Pipe starting at a WC waste connector.
        let wc = ed.doc.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(0, 30000), rotation: .pi / 2, size: Vec3(380, 700, 800), family: "wc")))
        let fam = ComponentLibrary.family("wc")!
        let cons = ComponentLibrary.worldConnectors(fam, ComponentGeom(position: Vec2(0, 30000), rotation: .pi / 2, size: Vec3(380, 700, 800), family: "wc"), z0: 0)
        XCTAssertEqual(Set(cons.map(\.system)), ["SAN", "DCW"])
        let san = cons.first { $0.system == "SAN" }!
        XCTAssertEqual(san.position.x, -(350 - 40 - 60), accuracy: 1e-6)          // rotated 90°: local +Y → world −X
        await ed.run("MEPPIPE Fixture #\(wc) SAN -2000,30000 ;")
        guard let fp = components(ed).last, fp.family == "pipe" else { return XCTFail() }
        XCTAssertTrue(fp.worldPath[0].isClose(san.position.xy, tol: 1e-6))
        XCTAssertEqual(fp.baseOffset, 180, accuracy: 1e-6); XCTAssertEqual(fp.size.x, 100, accuracy: 1e-6)
        XCTAssertEqual(ed.doc.elements.last?.props["system"], "SAN")
        // Displayed in the system colour.
        let strokeColor = PlanRepresentation.items(ed.doc.elements.last!, doc: ed.doc).compactMap { if case .stroke(_, _, let s) = $0 { return s.color }; return nil }.first
        XCTAssertEqual(strokeColor, RunFamilies.systemColor("SAN"))
        // Undo removes the run.
        ed.undo()
        XCTAssertNotEqual(components(ed).last?.family, "pipe")
    }

    func testRetainingWallAndSite() async {
        let ed = Editor()
        await ed.run("RETAININGWALL Size 300 2000 0,0 10000,0 ;")
        guard let rw = components(ed).last, rw.family == "retaining-wall" else { return XCTFail() }
        let sec = RunFamilies.section("retaining-wall", rw, unit: 1)
        let area = abs(GeometryOps.signedArea(sec))
        let v = MeshTools.signedVolume(MeshBuilder.groups(for: ed.doc.elements.last!, doc: ed.doc)[0].mesh)
        XCTAssertEqual(v, area * 10000, accuracy: area * 10)
        // Parking layouts.
        XCTAssertEqual(ParkingLayout.stalls(from: .zero, to: Vec2(25000, 0), width: 2500, depth: 5000).count, 10)
        XCTAssertEqual(ParkingLayout.stalls(from: .zero, to: Vec2(25000, 0), width: 2500, depth: 5000, angle: 45).count, 6)
        XCTAssertEqual(ParkingLayout.stalls(from: .zero, to: Vec2(25000, 0), width: 2500, depth: 5000, double: true).count, 20)
        let st = ParkingLayout.stalls(from: .zero, to: Vec2(25000, 0), width: 2500, depth: 5000)[0]
        XCTAssertTrue(st.center.isClose(Vec2(1250, 2500), tol: 1e-6))
        await ed.run("PARKINGLOT 0,20000 25000,20000")
        XCTAssertEqual(components(ed).filter { $0.family == "parking" }.count, 10)
        XCTAssertEqual(ed.doc.elements.last?.props["kind"], "paving")
        await ed.run("SITEPATH Width 1000 0,40000 10000,40000 ;")
        guard case .slab(let path)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(path.boundary)), 10000 * 1000, accuracy: 1e-3)
        await ed.run("SUBREGION 0,50000 5000,50000 5000,55000 0,55000 ;")
        XCTAssertEqual(ed.doc.elements.last?.props["kind"], "subregion")
        XCTAssertEqual(ed.doc.elements.last?.material, "Grass")
    }

    func testBearingsAndPropertyLines() async {
        XCTAssertEqual(Bearings.format(Vec2(1, 1)), "N 45°00'00\" E")
        XCTAssertEqual(Bearings.format(Vec2(-1, -1)), "S 45°00'00\" W")
        XCTAssertEqual(Bearings.format(Vec2(1, -0.0000001)), "S 90°00'00\" E")
        XCTAssertEqual(Bearings.format(Vec2(0, 1), northAngle: 90), "N 90°00'00\" E")
        let d = Bearings.parse("N45d30'00\"E")!
        XCTAssertEqual(Bearings.azimuth(d), 45.5, accuracy: 1e-9)
        for v in [Vec2(3, 4), Vec2(-2, 7), Vec2(5, -1), Vec2(-3, -3)] {
            let back = Bearings.parse(Bearings.format(v))!
            XCTAssertEqual(back.angle, v.normalized.angle, accuracy: 1e-4)
        }
        XCTAssertNil(Bearings.parse("E45N")); XCTAssertNil(Bearings.parse("N95E"))
        let ed = Editor()
        let log = await ed.run("PROPERTYLINE 0,0 Bearing N90dE 10000 Bearing S0dW 10000 0,-10000 Close")
        guard let e = ed.doc.entities.last, case .polyline(let pl) = e.geometry else { return XCTFail(log.joined(separator: "\n")) }
        XCTAssertTrue(pl.closed); XCTAssertEqual(pl.vertices.count, 4)
        XCTAssertTrue(pl.vertices[2].p.isClose(Vec2(10000, -10000), tol: 1e-6))
        XCTAssertTrue(log.contains { $0.contains("100.00 m²") }, log.joined(separator: "\n"))
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).first { $0.id == e.id }!.items
        let texts = items.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        XCTAssertEqual(texts.count, 9)
        XCTAssertTrue(texts.contains("N 90°00'00\" E")); XCTAssertTrue(texts.contains("10.000 m"))
    }

    func testSpotElevationIsLive() async {
        let ed = Editor()
        let s = ed.doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 5000), Vec2(0, 5000)], thickness: 200, topOffset: 150)))
        XCTAssertEqual(SpotElevation.value(at: Vec2(2500, 2500), doc: ed.doc, level: 0), 150, accuracy: 1e-9)
        XCTAssertEqual(SpotElevation.text(150, units: .millimeters), "+0.150")
        await ed.run("SPOTELEV 2500,2500 3500,3500 ;")
        guard let e = ed.doc.entities.last, case .leader(let l) = e.geometry else { return XCTFail() }
        XCTAssertEqual(l.text, "+0.150")
        if let i = ed.doc.elementIndex(s), case .slab(var g) = ed.doc.elements[i].geometry { g.topOffset = 300; ed.doc.elements[i].geometry = .slab(g) }
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).first { $0.id == e.id }!.items
        XCTAssertTrue(items.contains { if case .text(let t, _, _) = $0 { return t.content == "+0.300" }; return false })
        // Spot slope on a 1:12 ramp, pointing downhill, live.
        await ed.run("RAMP W 1500 R 600 0,10000 7200,10000")
        let s12 = SpotElevation.slope(at: Vec2(3600, 10000), doc: ed.doc, level: 0)!
        XCTAssertEqual(s12.grade, 600.0 / 7200, accuracy: 1e-9); XCTAssertEqual(s12.uphill.x, 1, accuracy: 1e-9)
        await ed.run("SPOTSLOPE 3600,10000 ;")
        guard case .leader(let sl)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(sl.text, "8.3% (1:12)")
        XCTAssertLessThan(sl.points[0].x, sl.points[1].x)       // arrow tip downhill (towards −X)
        XCTAssertNil(SpotElevation.slope(at: Vec2(2500, 2500), doc: ed.doc, level: 0))
    }

    func testRoomFinishesAndOpeningParts() async {
        let ed = Editor()
        let r1 = ed.doc.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000), Vec2(0, 3000)], name: "Kitchen", number: "102")))
        ed.doc.addElement(.space(SpaceGeom(boundary: [Vec2(5000, 0), Vec2(8000, 0), Vec2(8000, 3000), Vec2(5000, 3000)], name: "Hall", number: "101")))
        ed.selection = [r1]
        await ed.run("ROOMFINISH Set \"Oak\" \"MDF\" \"Paint\" \"Gypsum\"")
        let rows = RoomFinishes.rows(ed.doc)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][0], "101"); XCTAssertEqual(rows[2][3...].map { $0 }, ["Oak", "MDF", "Paint", "Gypsum"])
        XCTAssertEqual(rows[2][2], "12.00 m²")
        await ed.run("ROOMFINISH Schedule 0,-2000")
        guard case .table(let tb)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(tb.cells.count, 4)
        // Window mullions/transoms and door fanlight + threshold add sub-parts.
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0), thickness: 200, height: 3000)))
        let win = doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 1500, width: 1800, height: 1200, sill: 900, windowStyle: .fixed)))
        let door = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 4500, width: 900, height: 2400)))
        func tris(_ id: EntityID) -> Int { MeshBuilder.groups(for: doc.element(id)!, doc: doc).reduce(0) { $0 + $1.mesh.triangleCount } }
        let plainWin = tris(win), plainDoor = tris(door)
        let ted = Editor(); ted.doc = doc; ted.selection = [win, door]
        await ted.run("OPENINGPARTS 2 1 Yes")
        doc = ted.doc
        guard case .opening(let o)? = doc.element(win)?.geometry, case .opening(let d)? = doc.element(door)?.geometry else { return XCTFail() }
        XCTAssertEqual(o.mullions, 2); XCTAssertEqual(o.transoms, 1); XCTAssertEqual(d.transoms, 1); XCTAssertTrue(d.threshold)
        XCTAssertGreaterThan(tris(win), plainWin); XCTAssertGreaterThan(tris(door), plainDoor)
        XCTAssertTrue(MeshBuilder.groups(for: doc.element(door)!, doc: doc).contains { $0.material == "Glass" })
        // Opening types with formulas drive the sub-parts.
        await ted.run("OPENINGTYPE Formula \"Casement 1200x1200\" mullions \"floor(width / 500)\"")
        XCTAssertEqual(ted.doc.openingType("Casement 1200x1200")?.resolved().type.mullions, 2)
    }
}
