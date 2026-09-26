// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Project views: view-specific annotations, duplicate with/without detailing, crop regions and annotation crop,
/// dependent views and matchlines, scope boxes, linework overrides, axonometric and camera views, schedule cell
/// highlights.
@MainActor
final class RenderProjectViewsTests: XCTestCase {
    func house(_ ed: Editor) -> [EntityID] {
        [(Vec2(0, 0), Vec2(20000, 0)), (Vec2(20000, 0), Vec2(20000, 8000)), (Vec2(20000, 8000), Vec2(0, 8000)), (Vec2(0, 8000), Vec2(0, 0))].map {
            ed.doc.addElement(.wall(WallGeom(start: $0.0, end: $0.1, thickness: 200, height: 3000)), level: 0)
        }
    }
    func plan(_ ed: Editor) -> [DrawEntry] { DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)) }
    func texts(_ es: [DrawEntry]) -> [String] { es.flatMap { $0.items.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil } } }
    func bounds(_ es: [DrawEntry]) -> BBox2 { es.reduce(BBox2.empty) { $0.union($1.bounds) } }

    // MARK: DOC-015 / DOC-016

    func testViewAnnotationsDuplicateAndCrop() async {
        let ed = Editor()
        _ = house(ed)
        ed.transaction("shared note") { d in d.add(.text(TextGeom(position: Vec2(1000, -1000), height: 250, content: "SHARED"))) }
        await ed.run("PROJECTVIEW New Plan L0")
        XCTAssertEqual(ed.doc.variable(ProjectViews.currentKey), "L0")
        ed.transaction("note") { d in d.add(.text(TextGeom(position: Vec2(5000, 4000), height: 250, content: "LIVING"))) }
        XCTAssertEqual(ed.doc.entities.last?.props[ProjectViews.ownerProp], "L0", "new annotations belong to the current view")
        XCTAssertTrue(texts(plan(ed)).contains("LIVING")); XCTAssertTrue(texts(plan(ed)).contains("SHARED"))
        // Duplicate plain: settings, no annotations. With detailing: copies of the annotations.
        await ed.run("PROJECTVIEW Duplicate L0 Plain L0-plain")
        await ed.run("PROJECTVIEW Duplicate L0 Detailing L0-detail")
        XCTAssertEqual(ed.doc.entities.filter { $0.props[ProjectViews.ownerProp] == "L0-detail" }.count, 1)
        await ed.run("PROJECTVIEW Open L0-plain")
        XCTAssertFalse(texts(plan(ed)).contains("LIVING")); XCTAssertTrue(texts(plan(ed)).contains("SHARED"))
        await ed.run("PROJECTVIEW Open L0-detail")
        XCTAssertTrue(texts(plan(ed)).contains("LIVING"))
        // Crop region clips model graphics; annotation crop keeps annotations near the crop.
        await ed.run("VIEWCROP Window 0,0 10000,8000")
        let b = bounds(plan(ed).filter { $0.id.map { ed.doc.element($0) != nil } ?? false })
        XCTAssertLessThanOrEqual(b.max.x, 10000 + 1e-6); XCTAssertGreaterThanOrEqual(b.min.y, -1e-6)
        XCTAssertTrue(texts(plan(ed)).contains("SHARED"), "annotation crop off: annotations are not clipped")
        await ed.run("VIEWCROP Annotation 500")
        XCTAssertFalse(texts(plan(ed)).contains("SHARED"), "the note 1000 below the crop is outside a 500 annotation crop")
        await ed.run("VIEWCROP Annotation 1500")
        XCTAssertTrue(texts(plan(ed)).contains("SHARED"))
        await ed.run("VIEWCROP Off")
        XCTAssertGreaterThan(bounds(plan(ed)).max.x, 19000)
        // Leaving project views shows shared annotations only; files keep everything.
        await ed.run("PROJECTVIEW Close")
        XCTAssertFalse(texts(plan(ed)).contains("LIVING"))
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.views, ed.doc.views)
        XCTAssertEqual(back.formatVersion, ArchiDocument.currentFormatVersion)
    }

    // MARK: DOC-013 / DOC-014

    func testDependentViewsAndMatchlines() async {
        let ed = Editor()
        _ = house(ed)
        await ed.run("PROJECTVIEW New Plan Ground")
        ed.transaction("note") { d in d.add(.text(TextGeom(position: Vec2(15000, 4000), height: 250, content: "KITCHEN"))) }
        await ed.run("PROJECTVIEW Split Ground 2 1 1000")
        let deps = ed.doc.views.filter { $0.parent == "Ground" }
        XCTAssertEqual(deps.count, 2)
        let ms = ProjectViews.matchlines(ed.doc, family: "Ground")
        XCTAssertEqual(ms.count, 1)
        XCTAssertEqual(ms[0].a.x, (ms[0].a.x + ms[0].b.x) / 2, accuracy: 1e-6, "vertical matchline")
        await ed.run("PROJECTVIEW Open \"\(deps[0].name)\"")
        let es = plan(ed)
        XCTAssertTrue(texts(es).contains { $0.hasPrefix("MATCH LINE - SEE") })
        XCTAssertLessThan(bounds(es.filter { $0.id.map { ed.doc.element($0) != nil } ?? false }).max.x, 12000, "left half only")
        // Dependent views share the parent's annotations.
        await ed.run("PROJECTVIEW Open \"\(deps[1].name)\"")
        XCTAssertTrue(texts(plan(ed)).contains("KITCHEN"))
        await ed.run("MATCHLINE Off")
        XCTAssertFalse(texts(plan(ed)).contains { $0.hasPrefix("MATCH LINE") })
    }

    // MARK: BIM-008

    func testScopeBoxTrimsGridsAndCropsViews() async {
        let ed = Editor()
        let g = ed.doc.addElement(.gridLine(GridLineGeom(start: Vec2(-20000, 1000), end: Vec2(20000, 1000), label: "A")))
        await ed.run("SCOPEBOX New Core -4000,-3000 4000,3000 0")
        ed.selection = [g]
        await ed.run("SCOPEBOX Grids Core")
        guard case .gridLine(let gl)? = ed.doc.element(g)?.geometry else { return XCTFail() }
        XCTAssertEqual(gl.start.x, -4000, accuracy: 1e-6); XCTAssertEqual(gl.end.x, 4000, accuracy: 1e-6); XCTAssertEqual(gl.start.y, 1000, accuracy: 1e-9)
        // Moving the box re-trims the grid.
        ed.transaction("grow") { d in d.scopeBoxes[0].width = 12000 }
        guard case .gridLine(let gl2)? = ed.doc.element(g)?.geometry else { return XCTFail() }
        XCTAssertEqual(gl2.end.x, 6000, accuracy: 1e-6)
        // A view assigned to the box is cropped by it.
        _ = house(ed)
        await ed.run("PROJECTVIEW New Plan Core-plan")
        await ed.run("SCOPEBOX View Core-plan Core")
        let b = bounds(plan(ed).filter { $0.id.map { ed.doc.element($0).map { if case .wall = $0.geometry { return true }; return false } ?? false } ?? false })
        XCTAssertLessThanOrEqual(b.max.x, 6000 + 1e-6)
        XCTAssertTrue(texts(plan(ed)).contains("Core"), "scope boxes are drawn in plan views")
    }

    // MARK: DOC-027

    func testLineworkOverrideHidesOneEdgeInOneView() async {
        let ed = Editor()
        let w = house(ed)[0]
        await ed.run("PROJECTVIEW New Plan A")
        func strokesOnFace(_ es: [DrawEntry], y: Double) -> Int {
            es.filter { $0.id == w }.flatMap(\.items).reduce(0) { n, it in
                guard case .stroke(let p, let c, _) = it else { return n }
                let path = c ? p + [p[0]] : p
                return n + (0..<(path.count - 1)).filter { abs(path[$0].y - y) < 1e-6 && abs(path[$0 + 1].y - y) < 1e-6 && path[$0].distance(to: path[$0 + 1]) > 1000 }.count
            }
        }
        XCTAssertGreaterThan(strokesOnFace(plan(ed), y: -100), 0)
        await ed.run("LINEWORK Invisible 10000,-100")
        XCTAssertEqual(ed.doc.view(named: "A")?.linework.count, 1)
        XCTAssertEqual(strokesOnFace(plan(ed), y: -100), 0)
        XCTAssertGreaterThan(strokesOnFace(plan(ed), y: 100), 0, "the other face is untouched")
        await ed.run("PROJECTVIEW Duplicate A Plain B")
        await ed.run("PROJECTVIEW Open B")
        XCTAssertGreaterThan(strokesOnFace(plan(ed), y: -100), 0, "overrides belong to one view")
    }

    // MARK: DOC-009 / DOC-010 / VIS-039

    func testAxonometricAndCameraViews() async {
        let ed = Editor()
        _ = house(ed)
        await ed.run("AXONVIEW SW Iso")
        let nv = ed.doc.namedViews.first { $0.name == "Iso" }!
        XCTAssertEqual(nv.camera?.orthographic, true)
        let dir = (nv.camera!.eye - nv.camera!.target).normalized
        XCTAssertEqual(dir.x, dir.y, accuracy: 1e-9); XCTAssertLessThan(dir.x, 0)
        XCTAssertEqual(asin(dir.z) * 180 / .pi, 35.264, accuracy: 0.01)
        // Live: the view refits when the model grows.
        let t0 = nv.camera!.target
        ed.transaction("extend") { d in d.addElement(.wall(WallGeom(start: Vec2(40000, 0), end: Vec2(40000, 5000), thickness: 200, height: 3000))) }
        XCTAssertGreaterThan(ed.doc.namedViews.first { $0.name == "Iso" }!.camera!.target.x, t0.x + 5000)
        // Axonometric drawing placed from the model.
        await ed.run("VIEWDRAW Camera Iso 0,-20000")
        let blk = ed.doc.blocks.first { $0.value.description == "view:camera:Iso" }
        XCTAssertNotNil(blk); XCTAssertGreaterThan(blk?.value.entities.count ?? 0, 10)
        // Perspective camera object: lens → field of view, glyph in plan, perspective drawing.
        await ed.run("CAMERAVIEW 10000,-15000 10000,4000 1600 1600 35 Cam1")
        let cam = ed.doc.view(named: "Cam1")!.camera!
        XCTAssertEqual(cam.fov, 2 * atan(18.0 / 35) * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(CameraObjects.lens(fov: cam.fov), 35, accuracy: 1e-9)
        XCTAssertFalse(cam.orthographic)
        XCTAssertTrue(texts(plan(ed)).contains("Cam1"))
        let persp = ElevationBuilder.entries(doc: ed.doc, camera: cam)
        XCTAssertFalse(persp.isEmpty)
        // The near wall (y = 0) looks longer than the far one (y = 8000) in perspective.
        func width(_ id: EntityID) -> Double { bounds(persp.filter { $0.id == id }).width }
        let ws = ed.doc.elements.filter { if case .wall(let g) = $0.geometry { return abs(g.start.y - g.end.y) < 1e-9 && g.length > 10000 }; return false }
        let near = ws.first { if case .wall(let g) = $0.geometry { return g.start.y == 0 }; return false }!, far = ws.first { if case .wall(let g) = $0.geometry { return g.start.y == 8000 }; return false }!
        XCTAssertGreaterThan(width(near.id), width(far.id) * 1.2)
    }

    // MARK: DOC-052

    func testScheduleCellHighlightsInPlacedTables() async {
        let ed = Editor()
        _ = house(ed)
        ed.doc.schedules = [ScheduleDefinition(name: "Walls", category: "walls", fields: [ScheduleField(name: "ID"), ScheduleField(name: "Length")])]
        await ed.run("SCHEDULECELLS Walls Cell \"Length > 10000\" #FF0000")
        let t = Schedules.evaluate(ed.doc.schedules[0], doc: ed.doc)
        XCTAssertEqual(t.rows.filter { !$0.cellHighlights.isEmpty }.count, 2)
        XCTAssertTrue(t.rows.allSatisfy { $0.highlight == nil })
        XCTAssertEqual(t.rows.first { !$0.cellHighlights.isEmpty }?.cellHighlights.keys.sorted(), [1])
        Schedules.place(ed.doc.schedules[0], doc: &ed.doc, layout: nil, at: Vec2(0, -5000), maxRows: 30, textHeight: 250)
        guard let e = ed.doc.entities.last, case .table(let g) = e.geometry else { return XCTFail() }
        XCTAssertEqual(g.fills?.count, 2)
        let fills = DrawListBuilder.items(for: e, doc: ed.doc, options: DrawOptions()).filter { if case .fill = $0 { return true }; return false }
        XCTAssertEqual(fills.count, 2)
        // Row highlights colour every cell of the row.
        await ed.run("SCHEDULECELLS Walls Row \"Length < 10000\" #00FF00")
        let t2 = Schedules.evaluate(ed.doc.schedules[0], doc: ed.doc)
        XCTAssertEqual(t2.rows.filter { $0.highlight != nil }.count, 2)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.schedules, ed.doc.schedules)
    }

    // MARK: DOC-017

    func testSectionBoxPerThreeDView() async {
        let ed = Editor()
        _ = house(ed)
        await ed.run("AXONVIEW SE Full")
        await ed.run("AXONVIEW SE Cut")
        await ed.run("PROJECTVIEW Open Cut")
        await ed.run("VIEWSECTIONBOX Box 0,0 10000,8000 0 1500")
        XCTAssertNotNil(SectionBoxes.active(ed.doc))
        await ed.run("PROJECTVIEW Open Full")
        XCTAssertNil(SectionBoxes.active(ed.doc), "each 3D view has its own section box")
        await ed.run("PROJECTVIEW Open Cut")
        XCTAssertEqual(SectionBoxes.active(ed.doc)?.max.z ?? 0, 1500, accuracy: 1e-6)
        // Drawings of the view are cut by the box; the other view is complete.
        await ed.run("PROJECTVIEW Close")
        let cut = ElevationBuilder.entries(doc: { var d = ed.doc; ProjectViews.open("Cut", doc: &d); return d }(), camera: ed.doc.view(named: "Cut")!.camera!)
        let full = ElevationBuilder.entries(doc: ed.doc, camera: ed.doc.view(named: "Full")!.camera!)
        XCTAssertLessThan(bounds(cut).height, bounds(full).height * 0.8)
        // Clipping keeps closed solids closed and trims edges to the box.
        let g = MeshBuilder.build(doc: ed.doc)
        let box = BBox3(min: Vec3(-500, -500, 0), max: Vec3(5000, 5000, 1000))
        let c = SectionBoxes.clip(g, box: box)
        for grp in c where !grp.mesh.isEmpty {
            XCTAssertLessThanOrEqual(grp.mesh.bounds.max.z, 1000 + 1e-6); XCTAssertLessThanOrEqual(grp.mesh.bounds.max.x, 5000 + 1e-6)
            XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(grp.mesh)))
            for e in grp.edges { for p in e { XCTAssertLessThanOrEqual(p.z, 1000 + 1e-6) } }
        }
        await ed.run("VIEWDRAW Camera Cut 0,-30000")
        XCTAssertNotNil(ed.doc.blocks.first { $0.value.description == "view:camera:Cut" })
    }
}
