// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMSystemsTests: XCTestCase {
    func pipe(_ doc: inout ArchiDocument, _ a: Vec2, _ b: Vec2, system: String? = nil, z: Double = 2700) -> EntityID {
        let id = doc.addElement(.component(ComponentGeom(category: "Plumbing", position: a, size: Vec3(50, 50, 50), baseOffset: z, family: "pipe", path: [.zero, b - a])))
        if let s = system, let i = doc.elementIndex(id) { doc.elements[i].props["system"] = s }
        return id
    }

    func testConnectedNetworksAssignAndDisplayBySystem() async {
        let ed = Editor()
        let a = pipe(&ed.doc, Vec2(0, 0), Vec2(3000, 0), system: "DCW")
        let b = pipe(&ed.doc, Vec2(3000, 0), Vec2(3000, 2000))
        let c = pipe(&ed.doc, Vec2(1500, 0), Vec2(1500, -1500))          // tee into the middle of a
        let d = pipe(&ed.doc, Vec2(10000, 0), Vec2(12000, 0), system: "SAN")
        let nets = MEPNetworks.networks(doc: ed.doc)
        XCTAssertEqual(nets.count, 2)
        let n1 = nets.first { $0.runs.contains(a) }!
        XCTAssertEqual(Set(n1.runs), [a, b, c])
        XCTAssertEqual(n1.system, "DCW")
        XCTAssertEqual(n1.length, 6500, accuracy: 1e-6)
        XCTAssertEqual(n1.openEnds.count, 3)
        XCTAssertEqual(nets.first { $0.runs.contains(d) }?.system, "SAN")
        // Assign a system to the whole network from one member.
        await ed.run("MEPSYSTEM Assign #\(b) DHW")
        XCTAssertEqual(Set([a, b, c].compactMap { ed.doc.element($0)?.props["system"] }), ["DHW"])
        // Display by system: only SAN shown in plan and 3D; schedules follow the view by default.
        await ed.run("MEPSYSTEM Show SAN")
        let shown = Set(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).compactMap(\.id))
        XCTAssertTrue(shown.contains(d)); XCTAssertFalse(shown.contains(a))
        XCTAssertEqual(ModelSets.elements(ed.doc).filter { if case .component = $0.geometry { return true }; return false }.count, 1)
        XCTAssertEqual(ModelSets.elements(ed.doc, filter: .everything).count, 4)
        await ed.run("MEPSYSTEM All")
        XCTAssertEqual(ModelSets.elements(ed.doc).count, 4)
        XCTAssertEqual(MEPNetworks.scheduleRows(doc: ed.doc).count, 3)
    }

    func testLightingFixturesPhotometryScheduleAndRenderLights() async {
        let ed = Editor()
        let room = ed.doc.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Office", number: "101")))
        _ = room
        await ed.run("COMPONENT Light 1250,2000 R 90 3750,2000 ")
        let lights = ed.doc.elements.filter(LightingFixtures.isLight)
        XCTAssertEqual(lights.count, 2)
        ed.selection = Set(lights.map(\.id))
        await ed.run("LIGHTDATA 3000 25 4000 90")
        let ph = LightingFixtures.photometry(ed.doc.element(lights[0].id)!)
        XCTAssertEqual(ph.lumens, 3000); XCTAssertEqual(ph.efficacy, 120, accuracy: 1e-9)
        let rows = LightingFixtures.scheduleRows(doc: ed.doc)
        XCTAssertEqual(rows.count, 4)   // header, 2 fixtures, total
        XCTAssertEqual(rows[1][3], "101 Office")
        XCTAssertEqual(rows[2][6], "90")
        XCTAssertEqual(rows[3][7], "6000")
        // Lumen method: 2 × 3000 lm × 0.8 × 0.6 / 20 m² = 144 lx.
        XCTAssertEqual(LightingFixtures.roomIlluminance(doc: ed.doc).first!.lux, 144, accuracy: 1e-6)
        let rl = LightingFixtures.renderLights(doc: ed.doc)
        XCTAssertEqual(rl.count, 2)
        XCTAssertEqual(rl[0].direction.z, -1, accuracy: 1e-9)
        XCTAssertEqual(rl[0].color.r, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(rl[0].color.b, 0.55, "4000 K: neutral white")
        XCTAssertLessThan(rl[0].color.b, 0.8)
        // SCHEDULE Lighting prints the rows.
        let log = await ed.run("SCHEDULE Lighting ")
        XCTAssertTrue(log.contains { $0.contains("6000") }, log.joined(separator: "\n"))
    }

    func testAreaSchemesFollowWallChanges() async {
        let ed = Editor()
        await ed.run("WALL 0,0 10000,0 10000,8000 0,8000 C")
        await ed.run("WALL 5000,0 5000,8000 ")
        await ed.run("AREASCHEME Place GEA 2000,2000 ")
        await ed.run("AREASCHEME Place GIA 2000,2000 ")
        await ed.run("AREASCHEME Place NIA 2000,2000 7000,2000 ")
        func area(_ code: String) -> Double { AreaSchemes.totals(doc: ed.doc).first { $0.scheme == code }?.area ?? 0 }
        XCTAssertEqual(area("GEA"), 10200 * 8200, accuracy: 1)
        XCTAssertEqual(area("GIA"), 9800 * 7800, accuracy: 1)
        XCTAssertEqual(area("NIA"), (4800 + 4800) * 7800, accuracy: 1)
        // Move the east wall 1 m out: the boundaries follow (associative).
        for (i, el) in ed.doc.elements.enumerated() {
            guard case .wall(var w) = el.geometry else { continue }
            if w.start.x == 10000 { w.start.x = 11000 }
            if w.end.x == 10000 { w.end.x = 11000 }
            ed.doc.elements[i].geometry = .wall(w)
        }
        var d = ed.doc
        XCTAssertTrue(BIMUpdaters.run(&d))
        ed.doc = d
        XCTAssertEqual(area("GEA"), 11200 * 8200, accuracy: 1)
        XCTAssertEqual(area("GIA"), 10800 * 7800, accuracy: 1)
        XCTAssertEqual(area("NIA"), (4800 + 5800) * 7800, accuracy: 1)
        let log = await ed.run("AREASCHEME Report")
        XCTAssertTrue(log.contains { $0.hasPrefix("GEA") })
    }

    func testAutomaticDimensionsAreAssociative() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let w = ed.doc.elements[0].id
        ed.selection = [w]
        await ed.run("AUTODIMWALLS 800 No")
        let dims = ed.doc.entities.filter { $0.props["autoDimSet"] != nil }
        XCTAssertEqual(dims.count, 1)
        guard case .dimension(let d0) = dims[0].geometry else { return XCTFail() }
        XCTAssertEqual(d0.points[0].distance(to: d0.points[1]), 6000, accuracy: 1e-6)
        // Lengthen the wall: the dimension follows.
        if let i = ed.doc.elementIndex(w), case .wall(var g) = ed.doc.elements[i].geometry { g.end = Vec2(7500, 0); ed.doc.elements[i].geometry = .wall(g) }
        var doc = ed.doc
        XCTAssertTrue(AutoDimensions.updateAll(&doc))
        guard case .dimension(let d1) = doc.entity(dims[0].id)!.geometry else { return XCTFail() }
        XCTAssertEqual(d1.points[0].distance(to: d1.points[1]), 7500, accuracy: 1e-6)
        // Views show the regenerated dimension even before the update runs.
        XCTAssertEqual(BIMUpdaters.regenerated(ed.doc).entity(dims[0].id)?.geometry, doc.entity(dims[0].id)?.geometry)
        // Openings add segments.
        ed.doc = doc
        ed.selection = [w]
        await ed.run("AUTODIMWALLS 800 Yes")
        ed.doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 3000, width: 900, height: 2100)))
        doc = ed.doc
        AutoDimensions.updateAll(&doc)
        let withOpenings = doc.entities.filter { $0.props["autoDimOpenings"] == "1" }
        XCTAssertEqual(withOpenings.count, 4, "three segments and the overall")
        // Grid dimensions.
        await ed.run("GRID 0,-5000 0,5000 ")
        await ed.run("GRID 6000,-5000 6000,5000 ")
        await ed.run("GRID 13500,-5000 13500,5000 ")
        await ed.run("AUTODIMGRIDS  1500")
        let gd = ed.doc.entities.filter { $0.props["autoDimGrids"] != nil }
        XCTAssertEqual(gd.count, 3)
        let spans = gd.compactMap { e -> Double? in if case .dimension(let d) = e.geometry { return d.points[0].distance(to: d.points[1]) }; return nil }.sorted()
        XCTAssertEqual(spans, [6000, 7500, 13500])
    }

    func testModelFilterForSchedulesAndExports() async {
        var doc = ArchiDocument()
        let a = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        let b = doc.addElement(.wall(WallGeom(start: Vec2(0, 3000), end: Vec2(4000, 3000))))
        let c = doc.addElement(.wall(WallGeom(start: Vec2(0, 6000), end: Vec2(4000, 6000))))
        DesignOptions.save([DesignOptionSet(name: "Entry", options: ["A", "B"], primary: "A")], doc: &doc)
        doc.elements[1].props[DesignOptions.prop] = "Entry:A"
        doc.elements[2].props[DesignOptions.prop] = "Entry:B"
        doc.elements[0].props[Worksets.prop] = "Shell"
        Worksets.setHidden("Shell", true, doc: &doc)
        doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: a, offset: 1000, width: 900, height: 2100)))
        // Views/schedules (document filter): workset Shell hidden, option A shown; the door follows its hidden host.
        XCTAssertEqual(Set(ModelSets.scheduleModel(doc).elements.map(\.id)), [b])
        // Exports default to the primary model with every workset.
        XCTAssertEqual(ModelSets.exportModel(doc).elements.count, 3)
        XCTAssertEqual(Set(ModelSets.elements(doc, filter: ModelFilter(hiddenWorksets: [], designOptions: .options(["Entry": "B"]))).map(\.id)).intersection([a, b, c]), [a, c])
        XCTAssertEqual(ModelSets.elements(doc, filter: ModelFilter(worksets: ["Shell"], designOptions: .all)).map(\.id).first, a)
        doc.setVariable("SCHEDULEFILTER", "all")
        XCTAssertEqual(ModelSets.scheduleModel(doc).elements.count, 4)
    }
}
