// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Round 7 building elements and parameters: wall loops, storefronts, stacked walls, parts, assemblies, storeys,
/// structural columns and usage, stair/railing types, expressions, spreadsheet and reporting parameters, family locks,
/// project standards, detail components, repeating details, insulation and material tags.
@MainActor
final class BIMRound7Tests: XCTestCase {
    func walls(_ doc: ArchiDocument) -> [(BIMElement, WallGeom)] { doc.elements.compactMap { el in if case .wall(let w) = el.geometry { return (el, w) }; return nil } }
    func volume(_ gs: [MeshGroup]) -> Double { gs.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) } }
    func run(_ doc: inout ArchiDocument) { BIMUpdaters.run(&doc) }

    // MARK: BIM-012

    func testRectangleAndPolygonWalls() async {
        let ed = Editor()
        await ed.run("WALLRECT Center 0,0 6000,4000")
        XCTAssertEqual(walls(ed.doc).count, 4)
        for (el, _) in walls(ed.doc) { XCTAssertNotNil(el.props["joinStart"]); XCTAssertNotNil(el.props["joinEnd"]) }
        let inner = RoomBounding.boundary(at: Vec2(3000, 2000), doc: ed.doc, level: 0)!
        XCTAssertEqual(abs(GeometryOps.signedArea(inner)), 5800 * 3800, accuracy: 1)
        let ed2 = Editor()
        await ed2.run("WALLRECT Inside 0,0 6000,4000")
        let in2 = RoomBounding.boundary(at: Vec2(3000, 2000), doc: ed2.doc, level: 0)!
        XCTAssertEqual(abs(GeometryOps.signedArea(in2)), 6000 * 4000, accuracy: 1)
        // Clean mitred corners: the 3D walls do not overlap (volume = footprint ring × height).
        let v = volume(MeshBuilder.build(doc: ed2.doc))
        XCTAssertEqual(v, (6400 * 4400 - 6000 * 4000) * ed2.settings.wallHeight, accuracy: 1e3)
        let ed3 = Editor()
        await ed3.run("WALLPOLYGON Regular 6 0,0 Inscribed 3000,0")
        XCTAssertEqual(walls(ed3.doc).count, 6)
        for (_, w) in walls(ed3.doc) { XCTAssertEqual(w.length, 3000, accuracy: 1e-6) }
    }

    // MARK: BIM-032

    func testStorefrontPreset() async {
        let ed = Editor()
        await ed.run("STOREFRONT Storefront 0,0 6000,0 3000 1500 2250 Single 0")
        guard case .curtainWall(let g)? = ed.doc.elements.last?.geometry else { return XCTFail("no curtain wall") }
        XCTAssertEqual(g.uLines?.count, 3)
        XCTAssertEqual(g.vLines, [2250])
        XCTAssertEqual(g.panels["2,0"], "door")
        XCTAssertFalse(MeshBuilder.groups(for: ed.doc.elements.last!, doc: ed.doc).isEmpty)
        await ed.run("STOREFRONT Partition 0,2000 4000,2000 2700 1000 Double 1")
        guard case .curtainWall(let p)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(p.vLines, []); XCTAssertEqual(p.panels["0,0"], "doubledoor"); XCTAssertEqual(p.mullionSize, 40)
    }

    // MARK: BIM-022

    func testStackedWalls() async {
        let ed = Editor()
        let id = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200, height: 3000)))
        ed.selection = [id]
        await ed.run("STACKEDWALL \"Concrete 250:1000; Generic 200:*\"")
        var ws = walls(ed.doc)
        XCTAssertEqual(ws.count, 2)
        let base = ws.first { $0.0.id == id }!.1, top = ws.first { $0.0.id != id }!.1
        XCTAssertEqual(base.height, 1000, accuracy: 1e-9); XCTAssertEqual(base.thickness, 250, accuracy: 1e-9)
        XCTAssertEqual(top.baseOffset, 1000, accuracy: 1e-9); XCTAssertEqual(top.height, 2000, accuracy: 1e-9); XCTAssertEqual(top.thickness, 200, accuracy: 1e-9)
        // Plan shows the segment cut by the 1200 cut plane only.
        let shown = Set(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).compactMap(\.id))
        XCTAssertFalse(shown.contains(id)); XCTAssertTrue(shown.contains(ws.first { $0.0.id != id }!.0.id))
        // 3D: both segments, total height 3000.
        let b = MeshBuilder.build(doc: ed.doc).reduce(BBox3.empty) { var x = $0; if !$1.mesh.isEmpty { x.add($1.mesh.bounds.min); x.add($1.mesh.bounds.max) }; return x }
        XCTAssertEqual(b.max.z, 3000, accuracy: 1e-6)
        // Editing the base moves the upper segment.
        ed.transaction("move") { d in if let i = d.elementIndex(id), case .wall(var w) = d.elements[i].geometry { w.end = Vec2(8000, 0); d.elements[i].geometry = .wall(w) } }
        ws = walls(ed.doc)
        XCTAssertEqual(ws.first { $0.0.id != id }!.1.end.x, 8000, accuracy: 1e-9)
        // Removing the base removes the stack.
        ed.transaction("del") { d in d.remove(ids: [id]) }
        XCTAssertTrue(walls(ed.doc).isEmpty)
    }

    // MARK: BIM-127

    func testPartsFromCompoundWall() async {
        let ed = Editor()
        var w = WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 365, height: 3000)
        w.wallType = "Exterior Brick 365"
        let id = ed.doc.addElement(.wall(w))
        ed.doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: id, offset: 2500, width: 1000, height: 2100)))
        let before = volume(MeshBuilder.build(doc: ed.doc).filter { $0.id == id })
        ed.selection = [id]
        await ed.run("PARTS Create")
        let parts = ed.doc.elements.filter { $0.props["partOf"] == "\(id)" }
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(Set(parts.compactMap(\.material)), ["Plaster", "Brick", "Insulation"])
        let groups = MeshBuilder.build(doc: ed.doc)
        XCTAssertTrue(groups.filter { $0.id == id && $0.kind == "wall" }.isEmpty, "the host is replaced by its parts")
        let partVol = volume(groups.filter { g in parts.contains { $0.id == g.id } })
        XCTAssertEqual(partVol, before, accuracy: before * 1e-6, "parts are cut by the host's door")
        let plan = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertFalse(plan.contains { $0.id == id }); XCTAssertEqual(plan.filter { e in parts.contains { $0.id == e.id } }.count, 4)
        // Parts schedule and visibility category.
        let t = Schedules.evaluate(ScheduleDefinition(name: "P", category: "parts", fields: Schedules.defaultFields("parts")), doc: ed.doc)
        XCTAssertEqual(t.rows.count, 4)
        XCTAssertEqual(VisibilityGraphics.category(parts[0]), "part")
        // Parts follow the host; merge restores it.
        ed.transaction("thicker") { d in if let i = d.elementIndex(id), case .wall(var g) = d.elements[i].geometry { g.end = Vec2(6000, 0); d.elements[i].geometry = .wall(g) } }
        for p in ed.doc.elements where p.props["partOf"] == "\(id)" { if case .wall(let g) = p.geometry { XCTAssertEqual(g.length, 6000, accuracy: 1e-6) } }
        ed.selection = [id]
        await ed.run("PARTS Merge")
        XCTAssertTrue(ed.doc.elements.filter { $0.props["partOf"] != nil }.isEmpty)
        XCTAssertNil(ed.doc.element(id)?.props["hasParts"])
    }

    // MARK: BIM-124 / BIM-126

    func testAssembliesViewsAndSchedule() async {
        let ed = Editor()
        let a = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(3000, 0), thickness: 200, height: 3000)))
        let b = ed.doc.addElement(.column(ColumnGeom(position: Vec2(1500, 1500))))
        let other = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 5000), end: Vec2(3000, 5000), thickness: 200, height: 3000)))
        ed.selection = [a, b]
        await ed.run("ASSEMBLY Create Frame1 Precast")
        XCTAssertEqual(Assemblies.members("Frame1", doc: ed.doc).count, 2)
        let t = Schedules.evaluate(ScheduleDefinition(name: "A", category: "assemblies", fields: Schedules.defaultFields("assemblies")), doc: ed.doc)
        XCTAssertEqual(t.rows.count, 1)
        XCTAssertEqual(t.rows[0].cells, ["Frame1", "Precast", "2", "column, wall", "1"])
        await ed.run("ASSEMBLY Views Frame1")
        XCTAssertNotNil(ed.doc.view(named: "Assembly Frame1 - Plan"))
        await ed.run("PROJECTVIEW Open \"Assembly Frame1 - Plan\"")
        let ids = Set(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).compactMap(\.id))
        XCTAssertTrue(ids.contains(a)); XCTAssertTrue(ids.contains(b)); XCTAssertFalse(ids.contains(other))
        XCTAssertFalse(MeshBuilder.build(doc: ed.doc).contains { $0.id == other })
        await ed.run("PROJECTVIEW Close")
        XCTAssertTrue(MeshBuilder.build(doc: ed.doc).contains { $0.id == other })
        await ed.run("ASSEMBLY Disassemble Frame1")
        XCTAssertTrue(Assemblies.names(ed.doc).isEmpty)
    }

    // MARK: BIM-003

    func testStoreySettings() async {
        let ed = Editor()
        await ed.run("STORY Height 3500 Yes")
        XCTAssertEqual(ed.doc.level(1)?.elevation ?? 0, 3500, accuracy: 1e-9)
        await ed.run("STORY Insert Above 3200 Mezzanine")
        let mz = ed.doc.levels.first { $0.name == "Mezzanine" }!
        XCTAssertEqual(mz.elevation, 3500, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.level(1)?.elevation ?? 0, 6700, accuracy: 1e-9)
        // Computation height: a 1000 high parapet no longer bounds rooms at 1200.
        ed.doc.currentLevel = 0
        for (a, b) in [(Vec2(0, 0), Vec2(4000, 0)), (Vec2(4000, 0), Vec2(4000, 4000)), (Vec2(4000, 4000), Vec2(0, 4000)), (Vec2(0, 4000), Vec2(0, 0))] {
            ed.doc.addElement(.wall(WallGeom(start: a, end: b, thickness: 200, height: 3000)), level: 0)
        }
        ed.doc.addElement(.wall(WallGeom(start: Vec2(2000, 0), end: Vec2(2000, 4000), thickness: 100, height: 1000)), level: 0)
        XCTAssertLessThan(abs(GeometryOps.signedArea(RoomBounding.boundary(at: Vec2(1000, 2000), doc: ed.doc, level: 0)!)), 8e6)
        await ed.run("STORY Computation 1200")
        XCTAssertEqual(ed.doc.level(0)?.computationHeight ?? 0, 1200, accuracy: 1e-9)
        XCTAssertGreaterThan(abs(GeometryOps.signedArea(RoomBounding.boundary(at: Vec2(1000, 2000), doc: ed.doc, level: 0)!)), 14e6)
        // Elevation display.
        ed.doc.info.elevation = 100
        await ed.run("STORY Elevation Survey")
        XCTAssertEqual(StoreySettings.displayElevation(ed.doc.level(1)!, doc: ed.doc), 6800, accuracy: 1e-9)
        await ed.run("STORY Elevation Relative Mezzanine")
        XCTAssertEqual(StoreySettings.displayElevation(ed.doc.level(1)!, doc: ed.doc), 3200, accuracy: 1e-9)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.level(0)?.computationHeight, 1200)
    }

    // MARK: BIM-077 / BIM-086

    func testStructuralColumnsAndUsage() async {
        let ed = Editor()
        ed.doc.addElement(.gridLine(GridLineGeom(start: Vec2(0, -1000), end: Vec2(0, 7000), label: "1")))
        ed.doc.addElement(.gridLine(GridLineGeom(start: Vec2(6000, -1000), end: Vec2(6000, 7000), label: "2")))
        ed.doc.addElement(.gridLine(GridLineGeom(start: Vec2(-1000, 0), end: Vec2(7000, 0), label: "A")))
        await ed.run("STRUCTCOLUMN \"HEA200\" 3000 Steel Grids")
        let cols = ed.doc.elements.filter { if case .column = $0.geometry { return true }; return false }
        XCTAssertEqual(cols.count, 2)
        for c in cols {
            guard case .column(let g) = c.geometry else { continue }
            XCTAssertEqual(g.profile, "HEA200"); XCTAssertEqual(g.width, 200, accuracy: 1e-6); XCTAssertEqual(g.depth, 190, accuracy: 1e-6)
            XCTAssertEqual(c.props["loadBearing"], "1"); XCTAssertNotNil(c.props[GridHosting.prop]); XCTAssertEqual(c.material, "Steel")
        }
        // Profiles in 3D: the H section has less area than its bounding box.
        let v = volume(MeshBuilder.groups(for: cols[0], doc: ed.doc))
        XCTAssertLessThan(v, 200 * 190 * 3000 * 0.6); XCTAssertGreaterThan(v, 0)
        // Hosted columns follow their grid.
        ed.transaction("move grid") { d in
            if let i = d.elements.firstIndex(where: { if case .gridLine(let g) = $0.geometry { return g.label == "2" }; return false }), case .gridLine(var g) = d.elements[i].geometry {
                g.start.x = 6500; g.end.x = 6500; d.elements[i].geometry = .gridLine(g)
            }
        }
        XCTAssertTrue(ed.doc.elements.contains { if case .column(let g) = $0.geometry { return abs(g.position.x - 6500) < 1e-6 }; return false })
        let w = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0), thickness: 200, height: 3000)))
        ed.selection = [w]
        await ed.run("STRUCTURAL Shear")
        XCTAssertEqual(ed.doc.element(w)?.props["structuralUsage"], "shear")
        XCTAssertEqual(ed.doc.element(w)?.props["loadBearing"], "0")
        XCTAssertEqual(Schedules.value("structuralUsage", Schedules.Obj(id: w, element: ed.doc.element(w)), doc: ed.doc), "shear")
    }

    // MARK: PAR-018

    func testStairAndRailingTypeBuilders() async {
        let ed = Editor()
        let s = ed.doc.addElement(.stair(StairGeom(start: .zero, width: 900, totalRise: 3000, riserCount: 17, treadDepth: 280)))
        await ed.run("STAIRTYPE New Main 175 290 1200 0 Concrete None")
        ed.selection = [s]
        await ed.run("STAIRTYPE Assign Main")
        guard case .stair(let g)? = ed.doc.element(s)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.riserCount, 18); XCTAssertEqual(g.treadDepth, 290, accuracy: 1e-9); XCTAssertEqual(g.width, 1200, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(g.riserHeight, 175)
        // Flex: editing the type updates every stair of the type.
        await ed.run("STAIRTYPE Edit Main 150 300 1000 0 Concrete None")
        guard case .stair(let g2)? = ed.doc.element(s)?.geometry else { return XCTFail() }
        XCTAssertEqual(g2.riserCount, 20); XCTAssertEqual(g2.width, 1000, accuracy: 1e-9)
        // Railing types.
        let r = ed.doc.addElement(.railing(RailingGeom(path: [.zero, Vec2(3000, 0)], height: 900)))
        await ed.run("RAILTYPEDEF New Glassy 1100 round 50 glass 0 0 1500 No 300")
        ed.selection = [r]
        await ed.run("RAILTYPEDEF Assign Glassy")
        guard case .railing(let rg)? = ed.doc.element(r)?.geometry else { return XCTFail() }
        XCTAssertEqual(rg.height, 1100, accuracy: 1e-9); XCTAssertEqual(rg.infill, "glass"); XCTAssertEqual(rg.extensionLength ?? 0, 300, accuracy: 1e-9)
        await ed.run("RAILTYPEDEF Edit Glassy 1200 round 50 glass 0 0 1500 No 300")
        guard case .railing(let rg2)? = ed.doc.element(r)?.geometry else { return XCTFail() }
        XCTAssertEqual(rg2.height, 1200, accuracy: 1e-9)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.railingTypes, ed.doc.railingTypes); XCTAssertEqual(back.stairTypes, ed.doc.stairTypes)
    }

    // MARK: PAR-030

    func testExpressionsOnProperties() async {
        let ed = Editor()
        let a = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 200, height: 3000)))
        let b = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 3000), end: Vec2(4000, 3000), thickness: 200, height: 3000)), name: "North Wall")
        ed.doc.globalParameters = [FamilyParameter("Parapet", value: "900")]
        ed.selection = [a]
        await ed.run("EXPRESSION Set height North_Wall.height + Parapet")
        guard case .wall(let wa)? = ed.doc.element(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(wa.height, 3900, accuracy: 1e-9)
        ed.selection = [b]
        await ed.run("EXPRESSION Set thickness id\(a).length / 20")
        ed.transaction("taller") { d in if let i = d.elementIndex(b), case .wall(var w) = d.elements[i].geometry { w.height = 3500; d.elements[i].geometry = .wall(w) } }
        guard case .wall(let wa2)? = ed.doc.element(a)?.geometry, case .wall(let wb)? = ed.doc.element(b)?.geometry else { return XCTFail() }
        XCTAssertEqual(wa2.height, 4400, accuracy: 1e-9)
        XCTAssertEqual(wb.thickness, 200, accuracy: 1e-9)
        ed.selection = [a]
        await ed.run("EXPRESSION Set width nosuch.width")
        XCTAssertNil(ed.doc.element(a)?.props["expr.width"], "unresolvable expressions are rejected")
        ed.selection = [a]
        await ed.run("EXPRESSION Clear height")
        XCTAssertNil(ed.doc.element(a)?.props["expr.height"])
    }

    // MARK: PAR-029 / PAR-025

    func testSpreadsheetAndReportingParameters() async {
        let ed = Editor()
        var e = Entity(layer: "0", geometry: .table(TableGeom(origin: .zero, columnWidths: [1000, 1000], rowHeight: 300, cells: [["Name", "Value"], ["Height", "2750"]])))
        e.props["name"] = "Params"
        let tid = ed.doc.add(e)
        ed.doc.globalParameters = [FamilyParameter("H", value: "3000")]
        let w = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 300, height: 3000)))
        ed.doc.elements[ed.doc.elementIndex(w)!].props["gp.height"] = "H"
        await ed.run("PARAMCELL H Params!B2")
        guard case .wall(let g)? = ed.doc.element(w)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.height, 2750, accuracy: 1e-9)
        ed.transaction("edit cell") { d in if let i = d.entityIndex(tid), case .table(var t) = d.entities[i].geometry { t.cells[1][1] = "3100"; d.entities[i].geometry = .table(t) } }
        guard case .wall(let g2)? = ed.doc.element(w)?.geometry else { return XCTFail() }
        XCTAssertEqual(g2.height, 3100, accuracy: 1e-9)
        XCTAssertEqual(SpreadsheetParameters.parseCell("AA10")?.col, 26)
        // Reporting parameter: a wall-hosted shelf as deep as its host wall is thick.
        ed.doc.families.append(FamilyDefinition(name: "Shelf", parameters: [FamilyParameter("Depth", value: "100")],
                                                forms: [FamilyForm(.box, dims: ["width": "600", "depth": "Depth", "height": "40"], material: "Wood")]))
        let c = ed.doc.addElement(.component(ComponentGeom(position: Vec2(1000, 0), family: "Shelf")))
        ed.doc.elements[ed.doc.elementIndex(c)!].props["host"] = "\(w)"
        await ed.run("REPORTPARAM Shelf Depth host.thickness")
        XCTAssertEqual(ed.doc.element(c)?.props["fp.Depth"], "300")
        guard case .component(let cg)? = ed.doc.element(c)?.geometry else { return XCTFail() }
        XCTAssertEqual(cg.size.y, 300, accuracy: 1e-6)
        ed.transaction("thicker") { d in if let i = d.elementIndex(w), case .wall(var x) = d.elements[i].geometry { x.thickness = 450; d.elements[i].geometry = .wall(x) } }
        XCTAssertEqual(ed.doc.element(c)?.props["fp.Depth"], "450")
    }

    // MARK: PAR-026

    func testFamilyLockAndEqualSpacing() async {
        let ed = Editor()
        var f = FamilyDefinition(name: "Rack", parameters: [FamilyParameter("Width", value: "900")],
                                 referencePlanes: [FamilyReferencePlane("Left", axis: "x", offset: "0"), FamilyReferencePlane("Right", axis: "x", offset: "1000"),
                                                   FamilyReferencePlane("M1", axis: "x", offset: "10"), FamilyReferencePlane("M2", axis: "x", offset: "20")])
        f.forms = [FamilyForm(.box, dims: ["width": "Right - Left", "depth": "300", "height": "50"], material: "Steel")]
        ed.doc.families.append(f)
        await ed.run("FAMILYLOCK Rack Lock Right Width Left")
        await ed.run("FAMILYLOCK Rack EQ Left,M1,M2,Right")
        let fam = ed.doc.family(named: "Rack")!
        var r = FamilyEngine.evaluate(fam, doc: ed.doc)
        XCTAssertTrue(r.errors.isEmpty, "\(r.errors)")
        XCTAssertEqual(r.planes["Right"]?.offset ?? 0, 900, accuracy: 1e-9)
        XCTAssertEqual(r.planes["M1"]?.offset ?? 0, 300, accuracy: 1e-9)
        XCTAssertEqual(r.planes["M2"]?.offset ?? 0, 600, accuracy: 1e-9)
        // Flex: the constraints hold for another width.
        r = FamilyEngine.evaluate(fam, doc: ed.doc, props: ["fp.Width": "1500"])
        XCTAssertEqual(r.planes["M2"]?.offset ?? 0, 1000, accuracy: 1e-9)
        XCTAssertEqual(r.bounds.max.x - r.bounds.min.x, 1500, accuracy: 1e-6)
        XCTAssertFalse(FamilyConstraints.equalize(["Left", "M1"], family: &f))
    }

    // MARK: PAR-032

    func testTransferProjectStandards() async throws {
        var src = ArchiDocument()
        src.materials.append(Material(name: "Cork", color: RGBA(0.7, 0.5, 0.3)))
        src.wallTypes.append(WallType(name: "Cork Wall", plies: [WallType.Ply(material: "Cork", thickness: 80), WallType.Ply(material: "Brick", thickness: 240)]))
        src.dimStyles.append(DimStyle(name: "Metric 1:50"))
        src.wallTypes[0].plies[0].thickness = 180  // changed Generic 200
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("std-\(UUID().uuidString).archi")
        try ArchiFile.encode(src).write(to: url)
        let ed = Editor()
        await ed.run("TRANSFERSTANDARDS \"\(url.path)\" \"wallTypes, dimStyles\" New")
        XCTAssertNotNil(ed.doc.wallTypes.first { $0.name == "Cork Wall" })
        XCTAssertNotNil(ed.doc.material("Cork"), "materials used by copied types come along")
        XCTAssertNotNil(ed.doc.dimStyles.first { $0.name == "Metric 1:50" })
        XCTAssertEqual(ed.doc.wallTypes.first { $0.name == "Generic 200" }?.plies[0].thickness, 200, "New only keeps existing types")
        var d = ArchiDocument()
        let counts = ProjectStandards.transfer(from: src, into: &d, categories: ["wallTypes"], overwrite: true)
        XCTAssertEqual(d.wallTypes.first { $0.name == "Generic 200" }?.plies[0].thickness, 180)
        XCTAssertEqual(counts["wallTypes"], src.wallTypes.count)
    }

    // MARK: DOC-037 / DOC-038 / DOC-039 / DOC-032

    func testDetailComponentsRepeatingDetailsInsulationAndMaterialTags() async {
        let ed = Editor()
        await ed.run("DETAILCOMPONENT \"Lumber 38x89\" 0,0 0")
        XCTAssertNotNil(ed.doc.blocks["DC-Lumber-38x89"])
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.block, "DC-Lumber-38x89")
        await ed.run("REPEATDETAIL \"Brick 215x65\" 0,1000 2250,1000 225")
        let path = ed.doc.entities.first { $0.props["repeatDetail"] != nil }!
        XCTAssertEqual(ed.doc.entities.filter { $0.props["repeatOf"] == "\(path.id)" }.count, 10)
        ed.transaction("stretch") { d in if let i = d.entityIndex(path.id) { d.entities[i].geometry = .line(LineGeom(Vec2(0, 1000), Vec2(4500, 1000))) } }
        XCTAssertEqual(ed.doc.entities.filter { $0.props["repeatOf"] == "\(path.id)" }.count, 20)
        await ed.run("INSULATION 100 0,2000 1000,2000")
        let ins2 = ed.doc.entities.last!
        let items = DrawListBuilder.items(for: ins2, doc: ed.doc, options: DrawOptions())
        guard case .stroke(let pts, _, _)? = items.first else { return XCTFail("no batt symbol") }
        let b = BBox2(points: pts)
        XCTAssertEqual(b.min.y, 1950, accuracy: 1); XCTAssertEqual(b.max.y, 2050, accuracy: 1)
        XCTAssertEqual(b.max.x, 1000, accuracy: 1)
        // Material tag on the brick layer of a compound wall.
        var w = WallGeom(start: Vec2(0, 5000), end: Vec2(5000, 5000), thickness: 365, height: 3000)
        w.wallType = "Exterior Brick 365"
        let wid = ed.doc.addElement(.wall(w))
        // Left face at y = 5000 + 182.5; plaster 15, then brick 240 → y ≈ 5000 + 182.5 - 100.
        await ed.run("MATERIALTAG 2000,5082 2500,6000")
        guard case .leader(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no tag") }
        XCTAssertEqual(l.text, "Brick")
        ed.transaction("retype") { d in if let i = d.elementIndex(wid), case .wall(var g) = d.elements[i].geometry { g.wallType = "Concrete 250"; g.thickness = 250; d.elements[i].geometry = .wall(g) } }
        guard case .leader(let l2)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(l2.text, "Concrete")
    }
}
