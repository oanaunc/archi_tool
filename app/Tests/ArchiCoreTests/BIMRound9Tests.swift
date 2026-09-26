// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// In-place models, curtain systems by face, graded regions, MEP terminals, electrical circuits and room data sheets.
@MainActor
final class BIMRound9Tests: XCTestCase {
    func box(_ ed: Editor, _ o: Vec3, _ s: Vec3) -> EntityID { ed.doc.add(.solid(SolidGeom(kind: .box, origin: o, size: s))) }
    func meshVolume(_ gs: [MeshGroup]) -> Double { gs.map { MeshTools.signedVolume($0.mesh) }.reduce(0, +) }

    func testInPlaceModelCreateRotateEdit() async {
        let ed = Editor()
        let a = box(ed, Vec3(0, 0, 0), Vec3(2000, 400, 450)), b = box(ed, Vec3(0, 0, 450), Vec3(2000, 100, 400))
        ed.selection = [a, b]
        await ed.run("INPLACE Create Furniture \"Bench 1\"")
        guard let el = ed.doc.elements.last, case .component(let g) = el.geometry, g.mesh != nil else { return XCTFail("no in-place component") }
        XCTAssertEqual(el.name, "Bench 1"); XCTAssertEqual(g.category, "Furniture"); XCTAssertEqual(el.props["inPlace"], "1")
        XCTAssertTrue(ed.doc.entities.isEmpty)
        let vol = 2000.0 * 400 * 450 + 2000.0 * 100 * 400
        XCTAssertEqual(meshVolume(MeshBuilder.groups(for: el, doc: ed.doc)), vol, accuracy: 1)
        // Rotating the component rotates its geometry.
        var r = el; var rg = g; rg.rotation = .pi / 2; r.geometry = .component(rg)
        ed.doc.elements[ed.doc.elementIndex(el.id)!] = r
        var bb = BBox3.empty
        for grp in MeshBuilder.groups(for: r, doc: ed.doc) { grp.mesh.positions.forEach { bb.add($0) } }
        XCTAssertEqual(bb.size.x, 400, accuracy: 1e-6); XCTAssertEqual(bb.size.y, 2000, accuracy: 1e-6)
        XCTAssertFalse(PlanRepresentation.items(r, doc: ed.doc).isEmpty)
        // Persists through the file format.
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: try! JSONEncoder().encode(ed.doc))
        if case .component(let bg)? = back.element(el.id)?.geometry { XCTAssertEqual(bg.mesh?.meshTriangles.count, g.mesh?.meshTriangles.count) } else { XCTFail() }
        await ed.run("INPLACE Edit #\(el.id)")
        XCTAssertTrue(ed.doc.elements.isEmpty)
        guard case .solid(let s)? = ed.doc.entities.last?.geometry else { return XCTFail("not reopened") }
        XCTAssertEqual(CSG.volume(s), vol, accuracy: 1)
    }

    func testCurtainSystemOnMassFaces() async {
        let ed = Editor()
        let m = box(ed, .zero, Vec3(10000, 5000, 6000))
        ed.selection = [m]
        await ed.run("CURTAINSYSTEM 1500 1500 60 No")
        let cws = ed.doc.elements.compactMap { el -> CurtainWallGeom? in if case .curtainWall(let g) = el.geometry { return g }; return nil }
        XCTAssertEqual(cws.count, 4)
        XCTAssertEqual(cws.map(\.length).sorted(), [5000, 5000, 10000, 10000].map(Double.init))
        XCTAssertTrue(cws.allSatisfy { abs($0.height - 6000) < 1e-6 })
        XCTAssertTrue(cws.contains { $0.start.distance(to: Vec2(0, 0)) < 1e-6 && $0.end.distance(to: Vec2(10000, 0)) < 1e-6 })
        XCTAssertFalse(MeshBuilder.build(doc: ed.doc).filter { $0.kind == "curtainWall" }.isEmpty)
    }

    func testGradedRegionCutFill() async {
        let ed = Editor()
        var pts: [Vec3] = []
        for i in 0...4 { for j in 0...4 { pts.append(Vec3(Double(i) * 5000, Double(j) * 5000, 0)) } }
        let topo = try! ModelingCommands.addTopo(ed, pts, interval: 1000)
        await ed.run("GRADEDREGION #\(topo) 5000,5000 15000,5000 15000,15000 5000,15000 C 1000 0")
        guard let g = ed.doc.entities.last, g.props["gradedFrom"] == "\(topo)" else { return XCTFail("no graded region") }
        XCTAssertEqual(Double(g.props["fill"]!)!, 100, accuracy: 3)
        XCTAssertEqual(Double(g.props["cut"]!)!, 0, accuracy: 0.5)
        XCTAssertEqual(ed.doc.entity(topo)?.layer, ModelingCommands.topoLayer + "-EXIST")
        guard case .solid(let s) = g.geometry else { return XCTFail() }
        let surf = Grading.surfacePoints(s)
        let sv = Terrain.surface(surf)
        XCTAssertEqual(Terrain.elevation(at: Vec2(10000, 10000), vertices: sv.vertices, triangles: sv.triangles)!, 1000, accuracy: 1e-6)
        XCTAssertEqual(Terrain.elevation(at: Vec2(1000, 1000), vertices: sv.vertices, triangles: sv.triangles)!, 0, accuracy: 1e-6)
        // Sloped sides fill more.
        let slopePts = Grading.graded(points: pts, boundary: [Vec2(5000, 5000), Vec2(15000, 5000), Vec2(15000, 15000), Vec2(5000, 15000)], pad: 1000, slope: 2)
        XCTAssertGreaterThan(Grading.cutFill(existing: pts, proposed: slopePts).fill, 1.3e11)
    }

    func testMEPTerminalsConnectAndDisplayBySystem() async {
        let ed = Editor()
        let fam = ComponentLibrary.family("air-supply")!
        let g = ComponentGeom(category: fam.category, position: Vec2(1000, 1000), size: fam.size, baseOffset: fam.baseOffset, family: "air-supply")
        let id = ed.doc.addElement(.component(g))
        XCTAssertFalse(MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc).isEmpty)
        XCTAssertEqual(ComponentLibrary.connectors(fam, size: fam.size).map(\.system), ["SA"])
        XCTAssertEqual(ComponentLibrary.systemDisplayColor(fam, g, props: [:]), RunFamilies.systemColor("SA"))
        let rad = ComponentLibrary.family("Radiator")!
        XCTAssertEqual(Set(ComponentLibrary.connectors(rad, size: rad.size).map(\.system)), ["HWS", "HWR"])
        XCTAssertFalse(ComponentLibrary.symbol(ComponentLibrary.family("data-outlet")!, size: Vec3(80, 45, 80)).isEmpty)
        // A duct run ending at the diffuser neck joins its network.
        let z0 = fam.baseOffset + fam.size.z
        let duct = ComponentGeom(category: "Mechanical", position: Vec2(1000, 1000), size: Vec3(200, 200, 200), baseOffset: z0, family: "duct", path: [Vec2(0, 0), Vec2(3000, 0)])
        let did = ed.doc.addElement(.component(duct))
        let nets = MEPNetworks.networks(doc: ed.doc)
        XCTAssertTrue(nets.contains { $0.runs.contains(did) && $0.fixtures.contains(id) }, "\(nets)")
    }

    func testCircuitsAndPanelSchedule() async {
        let ed = Editor()
        func place(_ f: String, _ p: Vec2) -> EntityID {
            let fam = ComponentLibrary.family(f)!
            return ed.doc.addElement(.component(ComponentGeom(category: fam.category, position: p, size: fam.size, baseOffset: fam.baseOffset, family: f)))
        }
        let panel = place("panel", Vec2(0, 0))
        let o = [place("outlet", Vec2(2000, 0)), place("outlet", Vec2(4000, 0)), place("outlet", Vec2(6000, 0))]
        let l = place("light-ceiling", Vec2(3000, 3000))
        ed.selection = Set(o)
        await ed.run("CIRCUIT Create #\(panel) 1 \"Sockets\" 16")
        ed.selection = [l]
        await ed.run("CIRCUIT Create #\(panel) 3 \"Lighting\" 10")
        let cs = Circuits.circuits(ed.doc, panel: panel)
        XCTAssertEqual(cs.map(\.number), [1, 3])
        XCTAssertEqual(cs[0].load, 540, accuracy: 1e-9)
        XCTAssertEqual(cs[0].description, "Sockets"); XCTAssertEqual(cs[1].breaker, 10)
        XCTAssertEqual(cs[0].phase, "L1"); XCTAssertEqual(cs[1].phase, "L2")
        let rows = Circuits.schedule(ed.doc, panel: panel)
        XCTAssertEqual(rows.first(where: { $0[0] == "Total" })?[3], "640")
        await ed.run("CIRCUIT Show #\(panel)")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["circuitWire"] != nil }.count, 2)
        await ed.run("CIRCUIT Show #\(panel)")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["circuitWire"] != nil }.count, 2, "wiring is replaced, not duplicated")
        let fam = ComponentLibrary.family("outlet")!
        if case .component(let g)? = ed.doc.element(o[0])?.geometry { XCTAssertEqual(ComponentLibrary.systemDisplayColor(fam, g, props: ed.doc.element(o[0])!.props), RunFamilies.systemColor("POWER")) }
        ed.selection = [o[2]]
        await ed.run("CIRCUIT Remove")
        XCTAssertEqual(Circuits.circuits(ed.doc, panel: panel)[0].devices.count, 2)
    }

    func testRoomDataSheetsRoundTrip() async throws {
        let ed = Editor()
        let rid = ed.doc.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Office", number: "101", height: 2700)))
        let fam = ComponentLibrary.family("desk")!
        _ = ed.doc.addElement(.component(ComponentGeom(category: fam.category, position: Vec2(2000, 2000), size: fam.size, family: "desk")))
        let s = RoomDataSheets.sheet(ed.doc, room: rid)!
        let dict = Dictionary(uniqueKeysWithValues: s)
        XCTAssertEqual(dict["Area (m²)"], "20")
        XCTAssertEqual(dict["Volume (m³)"], "54")
        XCTAssertEqual(dict["Furniture & equipment"], "Desk")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rds-\(UUID().uuidString).csv")
        await ed.run("ROOMDATASHEET Export \"\(url.path)\"")
        var text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Office"))
        text = text.replacingOccurrences(of: "Office", with: "Meeting Room")
        var rows = Schedules.parseCSV(text)
        let fc = rows[0].firstIndex(of: "Floor finish")!
        rows[1][fc] = "Oak parquet"
        try CSVText.make(rows).write(to: url, atomically: true, encoding: .utf8)
        await ed.run("ROOMDATASHEET Import \"\(url.path)\"")
        guard case .space(let g)? = ed.doc.element(rid)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.name, "Meeting Room")
        XCTAssertEqual(ed.doc.element(rid)?.props[RoomFinishes.keys[0]], "Oak parquet")
        ed.selection = [rid]
        await ed.run("ROOMDATASHEET Set Department Finance")
        XCTAssertEqual(ed.doc.element(rid)?.props["department"], "Finance")
        let html = RoomDataSheets.html(ed.doc, rooms: [rid])
        XCTAssertTrue(html.contains("Meeting Room") && html.contains("Finance"))
        try? FileManager.default.removeItem(at: url)
    }
}
