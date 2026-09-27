// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMCommandTests: XCTestCase {
    func els<T>(_ ed: Editor, _ f: (BIMGeometry) -> T?) -> [T] { ed.doc.elements.compactMap { f($0.geometry) } }
    func slabs(_ ed: Editor) -> [SlabGeom] { els(ed) { if case .slab(let s) = $0 { return s }; return nil } }
    func openings(_ ed: Editor) -> [OpeningGeom] { els(ed) { if case .opening(let o) = $0 { return o }; return nil } }
    func wallIDs(_ ed: Editor) -> [EntityID] { ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }.map(\.id) }

    func testRampIsSlopedSlab() async {
        let ed = Editor()
        let log = await ed.run("RAMP W 1500 R 600 0,0 7200,0")
        guard let s = slabs(ed).first else { return XCTFail(log.joined(separator: "\n")) }
        XCTAssertTrue(s.isSloped)
        XCTAssertEqual(s.topHeight(at: Vec2(7200, 0)), 600, accuracy: 1e-6)
        XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), 7200 * 1500, accuracy: 1e-6)
        XCTAssertEqual(ed.doc.elements[0].props["kind"], "ramp")
        XCTAssertTrue(log.contains { $0.contains("1:12") }, log.joined(separator: "\n"))
        // Too steep: warning.
        let steep = await ed.run("RAMP R 1000 0,5000 6000,5000")
        XCTAssertTrue(steep.contains { $0.contains("Warning") })
        ed.undo(); ed.undo()
        XCTAssertTrue(slabs(ed).isEmpty)
    }

    func testSlabSlopeArrow() async {
        let ed = Editor()
        await ed.run("SLAB 0,0 4000,0 4000,3000 0,3000")
        await ed.run("SLABSLOPE 2000,0 0,1500 4000,1500 100")
        guard let s = slabs(ed).first else { return XCTFail() }
        XCTAssertEqual(s.topHeight(at: Vec2(4000, 0)), 100, accuracy: 1e-6)
        XCTAssertEqual(s.topHeight(at: Vec2(0, 3000)), 0, accuracy: 1e-6)
        await ed.run("SLABSLOPE 2000,0 F")
        XCTAssertFalse(slabs(ed).first!.isSloped)
    }

    func testFoundationsUnderWallsAndColumns() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0")
        let w = wallIDs(ed)[0]
        ed.selection = [w]
        await ed.run("FOUNDATION Width 800 Depth 500 Wall")
        guard let f = slabs(ed).first else { return XCTFail("no footing") }
        XCTAssertEqual(f.thickness, 500)
        XCTAssertEqual(abs(GeometryOps.signedArea(f.boundary)), 6600 * 800, accuracy: 1)
        XCTAssertEqual(ed.doc.elements.last?.props["kind"], "foundation")
        await ed.run("COLUMN 10000,0 ")
        let c = ed.doc.elements.last!.id
        ed.selection = [c]
        await ed.run("FOUNDATION Width 1200 Column")
        XCTAssertEqual(abs(GeometryOps.signedArea(slabs(ed).last!.boundary)), 1200 * 1200, accuracy: 1)
    }

    func testNicheAndSweepCommands() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        await ed.run("NICHE D 120 2500,-50 ")
        guard let n = openings(ed).first else { return XCTFail() }
        XCTAssertTrue(n.isNiche); XCTAssertEqual(n.depth, 120); XCTAssertFalse(n.flipFacing)
        ed.selection = [wallIDs(ed)[0]]
        await ed.run("WALLSWEEP A Skirting 15 100 Left  ")
        guard case .wall(let w)? = ed.doc.element(wallIDs(ed)[0])?.geometry else { return XCTFail() }
        XCTAssertEqual(w.sweeps.count, 1)
        XCTAssertEqual(w.sweeps[0].elevation, 0); XCTAssertEqual(w.sweeps[0].side, 1)
    }

    func testCurtainGridEditing() async {
        let ed = Editor()
        await ed.run("CURTAINWALL 0,0 6000,0 ")
        await ed.run("CWGRID 3000,0 AddVertical 1000,0 AddHorizontal 1200 Panel 500,0 600 Solid X")
        guard case .curtainWall(let g)? = ed.doc.elements.first?.geometry else { return XCTFail() }
        XCTAssertTrue(g.uPositions.contains { abs($0 - 1000) < 1e-6 })
        XCTAssertEqual(g.vPositions.first ?? 0, 1200, accuracy: 1e-6)
        XCTAssertEqual(g.panels["0,0"], "solid")
    }

    func testRoomSeparatorAndUpdate() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,4000 0,4000 C")
        await ed.run("ROOMSEPARATOR 4000,0 4000,4000 ")
        await ed.run("ROOM 2000,2000 ")
        guard case .space(let r)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(r.boundary)), 3900 * 3800, accuracy: 3900 * 3800 * 0.01)
        // Move the separator: ROOMUPDATE follows.
        if let i = ed.doc.entities.firstIndex(where: { $0.layer == "A-AREA-SEPR" }) { ed.doc.entities[i].geometry = .line(LineGeom(Vec2(5000, 0), Vec2(5000, 4000))) }
        await ed.run("ROOMUPDATE")
        guard case .space(let r2)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(r2.boundary)), 4900 * 3800, accuracy: 4900 * 3800 * 0.01)
    }

    func testAreaPlanGross() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,4000 0,4000 C")
        await ed.run("AREAPLAN 4000,2000 ")
        guard let el = ed.doc.elements.last, case .space(let a) = el.geometry else { return XCTFail() }
        XCTAssertEqual(el.props["areaScheme"], "Gross")
        XCTAssertEqual(abs(GeometryOps.signedArea(a.boundary)), 8200 * 4200, accuracy: 8200 * 4200 * 0.01)
        // A room can still be placed inside the area boundary.
        await ed.run("ROOM 4000,2000 ")
        XCTAssertEqual(ed.doc.elements.filter { if case .space = $0.geometry { return true }; return false }.count, 2)
    }

    func testPhasesHideAndStyle() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        await ed.run("WALL 0,2000 5000,2000")
        let ids = wallIDs(ed)
        ed.selection = [ids[0]]
        await ed.run("PHASE Created Existing")
        ed.selection = [ids[0]]
        await ed.run("PHASE Demolish New")
        ed.selection = [ids[1]]
        await ed.run("PHASE Created New")
        XCTAssertEqual(ed.doc.element(ids[0])?.props["phaseDemolished"], "New Construction")
        // Existing phase: only wall 0 exists.
        await ed.run("PHASE Current Existing")
        var drawn = Set(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).compactMap(\.id))
        XCTAssertTrue(drawn.contains(ids[0])); XCTAssertFalse(drawn.contains(ids[1]))
        // New construction, complete: the demolished wall disappears (also in 3D).
        await ed.run("PHASE Current New")
        await ed.run("PHASE Filter Complete")
        drawn = Set(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).compactMap(\.id))
        XCTAssertFalse(drawn.contains(ids[0])); XCTAssertTrue(drawn.contains(ids[1]))
        XCTAssertFalse(MeshBuilder.build(doc: ed.doc).contains { $0.id == ids[0] })
        // Show all: demolished wall drawn dashed.
        await ed.run("PHASE Filter All")
        let e = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions()).first { $0.id == ids[0] }!
        XCTAssertTrue(e.items.contains { if case .stroke(_, _, let st) = $0 { return !st.dash.isEmpty }; return false })
    }

    func testOpeningTypesPropagate() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0")
        await ed.run("DOOR T \"Single Door 800x2100\" 2000,0 5000,0 ")
        var ds = openings(ed)
        XCTAssertEqual(ds.count, 2)
        XCTAssertEqual(ds[0].typeName, "Single Door 800x2100"); XCTAssertEqual(ds[0].width, 800)
        XCTAssertEqual(Set(ds.compactMap(\.mark)), ["D01", "D02"])
        await ed.run("OPENINGTYPE Set \"Single Door 800x2100\" Width 850")
        ds = openings(ed)
        XCTAssertEqual(ds.map(\.width), [850, 850])
        await ed.run("OPENINGTYPE Set \"Single Door 800x2100\" FireRating EI30")
        XCTAssertEqual(ed.doc.openingType("Single Door 800x2100")?.params["FireRating"], "EI30")
        var doc = ed.doc
        let r = ArchitectureCommands.importTypes("name,kind,width,height,sill,style\nSingle Door 800x2100,door,900,2200,0,single\nW-A,window,1000,1500,600,fixed,UValue=0.8\n", into: &doc)
        XCTAssertEqual(r.added, 1); XCTAssertEqual(r.updated, 1); XCTAssertEqual(r.instances, 2)
        XCTAssertEqual(doc.openingType("W-A")?.windowStyle, .fixed)
    }

    func testTagsFollowTheModel() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("DOOR 2000,0 ")
        await ed.run("WINDOW 5000,0 ")
        await ed.run("ROOM 4000,2500 ")
        await ed.run("TAGALL All")
        let tags = ed.doc.entities.filter { $0.props["tagOf"] != nil }
        XCTAssertEqual(tags.count, 3)
        let doorTag = tags.first { ed.doc.element(Int($0.props["tagOf"]!)!).map { if case .opening(let o) = $0.geometry { return o.kind == .door }; return false } ?? false }!
        func text(_ e: Entity) -> String? {
            DrawListBuilder.items(for: e, doc: ed.doc, options: DrawOptions()).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }.first
        }
        XCTAssertEqual(text(doorTag), "D01")
        // Renumber changes the tag text without touching the tag.
        await ed.run("MARKS Set 2000,0 D-7")
        XCTAssertEqual(text(doorTag), "D-7")
        // The room's own tag is hidden once it has a separate tag.
        let room = ed.doc.elements.first { if case .space = $0.geometry { return true }; return false }!
        XCTAssertEqual(room.props["tag"], "0")
    }

    func testKeynoteAndLegend() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        await ed.run("KEYNOTE Define 04.21 \"Brick veneer\"")
        await ed.run("KEYNOTE Tag 2500,0 04.21 2500,1000")
        XCTAssertEqual(ed.doc.elements[0].props["keynote"], "04.21")
        XCTAssertEqual(ed.doc.keynotes["04.21"], "Brick veneer")
        await ed.run("KEYNOTE Legend 0,-3000")
        guard case .table(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.cells.last?[0], "04.21")
    }

    func testSectionMarkerAndDrawingView() async {
        let ed = Editor()
        await ed.run("BUILDING 0,0 10000,8000")
        await ed.run("GRID 2000,-2000 2000,10000")
        await ed.run("SECTION -1000,4000 11000,4000 5000,9000 ")
        XCTAssertEqual(ed.doc.variable("SECTION"), "A")
        guard let line = Annotations.sectionLine(ed.doc) else { return XCTFail() }
        XCTAssertEqual(line.0.x, -1000, accuracy: 1e-9)
        let entries = ElevationBuilder.entries(doc: ed.doc, view: .section, sectionLine: nil)
        // Level heads and a grid bubble are part of the view.
        let texts = entries.flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        XCTAssertTrue(texts.contains("Ground Floor")); XCTAssertTrue(texts.contains("1"))
        await ed.run("VIEWDRAW Section A 20000,0")
        XCTAssertNotNil(ed.doc.blocks["VIEW-SECTION-A"])
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.block, "VIEW-SECTION-A")
        let n0 = ed.doc.blocks["VIEW-SECTION-A"]!.entities.count
        await ed.run("VIEWUPDATE")
        XCTAssertEqual(ed.doc.blocks["VIEW-SECTION-A"]!.entities.count, n0)
    }

    func testRoomTagAvoidsFurniture() async {
        var doc = ArchiDocument()
        let room = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        let r = doc.addElement(.space(SpaceGeom(boundary: room, name: "Bedroom", number: "101")))
        _ = doc.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(3000, 2000), size: Vec3(1600, 2000, 500))), name: "Bed")
        let items = PlanRepresentation.items(doc.element(r)!, doc: doc)
        let bed = [Vec2(2200, 1000), Vec2(3800, 1000), Vec2(3800, 3000), Vec2(2200, 3000)]
        for it in items { if case .text(let t, _, _) = it { XCTAssertFalse(GeometryOps.pointInPolygon(t.position, bed), "\(t.content) at \(t.position)") } }
        // Subtle fill.
        let fill = items.compactMap { if case .fill(_, let c) = $0 { return c }; return nil }.first!
        XCTAssertLessThanOrEqual(fill.a, 0.1)
    }

    func testSchedulesWithTypesVolumesAndAreas() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("DOOR T \"Double Door 1600x2100\" 4000,0 ")
        await ed.run("ROOM H 2500 4000,2500 ")
        await ed.run("AREAPLAN 4000,2500 ")
        let doors = ArchitectureCommands.parseCSV(ArchitectureCommands.scheduleCSV(ed.doc, "doors")!)
        XCTAssertEqual(doors[1][0], "D01"); XCTAssertEqual(doors[1][2], "Double Door 1600x2100")
        let rooms = ArchitectureCommands.parseCSV(ArchitectureCommands.scheduleCSV(ed.doc, "rooms")!)
        XCTAssertEqual(rooms.count, 2, "area boundaries are not rooms")
        XCTAssertEqual(Double(rooms[1][6])!, 7.8 * 4.8 * 2.5, accuracy: 0.05)
        let areas = ArchitectureCommands.parseCSV(ArchitectureCommands.scheduleCSV(ed.doc, "areas")!)
        XCTAssertEqual(areas.last?[1], "Total")
        await ed.run("SCHEDULE Types 0,-2000")
        guard case .table(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.cells[1][0], "Type")
    }

    func testDetailViewIsClippedAndScaled() async {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        let log = await ed.run("VIEWDRAW Detail -500,-500 1500,1500 5 20000,0")
        guard let b = ed.doc.blocks["VIEW-DETAIL-1"] else { return XCTFail(log.joined(separator: "\n")) }
        var box = BBox2.empty
        for e in b.entities { box.add(GeometryOps.bounds(e.geometry, doc: nil)) }
        XCTAssertGreaterThanOrEqual(box.min.x, -500 - 1e-6); XCTAssertLessThanOrEqual(box.max.x, 1500 + 1e-6)
        guard let ins = ed.doc.entities.compactMap({ e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }).first else { return XCTFail() }
        XCTAssertEqual(ins.scale.x, 5)
        // Model change + VIEWUPDATE regenerates the detail.
        let n0 = b.entities.count
        await ed.run("COLUMN 500,500 ")
        await ed.run("VIEWUPDATE")
        XCTAssertGreaterThan(ed.doc.blocks["VIEW-DETAIL-1"]!.entities.count, n0)
    }
}
