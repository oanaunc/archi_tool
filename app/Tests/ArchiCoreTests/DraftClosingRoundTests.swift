// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Image clip / adjust (DRW-085/086), dynamic UCS (PRC-036), tag label templates (ANN-080), linked BIM models (BLK-035)
/// and copy/monitor (BLK-036).
@MainActor
final class DraftClosingRoundTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func close3(_ a: Vec3, _ b: Vec3, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: tol, file: file, line: line)
    }
    func tmp(_ name: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archi-closing-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(name)
    }

    // MARK: DRW-085 image clip

    func imageEditor() -> (Editor, EntityID) {
        let ed = Editor()
        let id = ed.doc.add(.image(ImageGeom(path: "/tmp/none.png", origin: Vec2(100, 50), size: Vec2(200, 100))))
        return (ed, id)
    }
    func fills(_ items: [DrawItem]) -> [[[Vec2]]] { items.compactMap { if case .fill(let l, _) = $0 { return l }; return nil } }

    func testImageClipRectangularAndPolygonal() async throws {
        let (ed, id) = imageEditor()
        await ed.run("IMAGECLIP #\(id) New Rectangular 150,75 400,125 ")
        let e = try XCTUnwrap(ed.doc.entity(id))
        let uv = try XCTUnwrap(ImageDisplay.clipUV(e))
        // The boundary is cut to the image frame: u 0.25…1, v 0.25…0.75.
        XCTAssertEqual(uv.map(\.x).min()!, 0.25, accuracy: 1e-9); XCTAssertEqual(uv.map(\.x).max()!, 1, accuracy: 1e-9)
        XCTAssertEqual(uv.map(\.y).min()!, 0.25, accuracy: 1e-9); XCTAssertEqual(uv.map(\.y).max()!, 0.75, accuracy: 1e-9)
        // Drawn as the image plus a mask covering the frame outside the boundary (even-odd: frame + boundary).
        var items = DrawListBuilder.items(for: e, doc: ed.doc, options: DrawOptions())
        XCTAssertTrue(items.contains { if case .image = $0 { return true }; return false })
        let mask = try XCTUnwrap(fills(items).first { $0.count == 2 })
        XCTAssertEqual(abs(GeometryOps.signedArea(mask[0])) - abs(GeometryOps.signedArea(mask[1])), 200 * 100 - 150 * 50, accuracy: 1e-6)
        // Paper output masks with white; the frame is plotted (IMAGEFRAME 1) and hidden with IMAGEFRAME 0.
        var paper = DrawOptions(); paper.forPaper = true
        XCTAssertTrue(DrawListBuilder.items(for: e, doc: ed.doc, options: paper).contains { if case .fill(_, let c) = $0 { return c.r > 0.99 && c.g > 0.99 }; return false })
        XCTAssertTrue(items.contains { if case .stroke = $0 { return true }; return false })
        await ed.run("IMAGEFRAME 0")
        items = DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions())
        XCTAssertFalse(items.contains { if case .stroke = $0 { return true }; return false })
        // The boundary follows the image when it is moved and rotated.
        await ed.run("MOVE #\(id)  0,0 1000,0")
        close(ImageDisplay.clipBoundary(ed.doc.entity(id)!)!.min { $0.x + $0.y < $1.x + $1.y }!, Vec2(1150, 75))
        await ed.run("ROTATE #\(id)  1100,50 90")
        let rb = BBox2(points: ImageDisplay.clipBoundary(ed.doc.entity(id)!)!)
        XCTAssertEqual(rb.width, 50, accuracy: 1e-6); XCTAssertEqual(rb.height, 150, accuracy: 1e-6)
        // Invert, off / on, delete — each one undoable step.
        await ed.run("IMAGECLIP #\(id) Invert")
        XCTAssertEqual(ed.doc.entity(id)?.props[ImageDisplay.clipInvertProp], "1")
        XCTAssertTrue(fills(DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions())).contains { $0.count == 1 })
        await ed.run("IMAGECLIP #\(id) OFF")
        XCTAssertFalse(ImageDisplay.active(ed.doc.entity(id)!))
        XCTAssertEqual(DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions()).count, 1)
        await ed.run("IMAGECLIP #\(id) ON")
        XCTAssertTrue(ImageDisplay.clipActive(ed.doc.entity(id)!))
        await ed.run("IMAGECLIP #\(id) Delete")
        XCTAssertNil(ImageDisplay.clipUV(ed.doc.entity(id)!))
        ed.undo()
        XCTAssertNotNil(ImageDisplay.clipUV(ed.doc.entity(id)!))
        // Polygonal boundary; a boundary off the image is refused.
        let (ed2, id2) = imageEditor()
        await ed2.run("IMAGECLIP #\(id2) New Polygonal 100,50 300,50 200,150 ")
        XCTAssertEqual(ImageDisplay.clipUV(ed2.doc.entity(id2)!)?.count, 3)
        await ed2.run("IMAGECLIP #\(id2) New Rectangular 5000,5000 6000,6000 ")
        XCTAssertTrue(ed2.log.suffix(3).joined().contains("does not overlap"))
        XCTAssertEqual(ImageDisplay.clipUV(ed2.doc.entity(id2)!)?.count, 3)
        // Persistence in .archi files.
        let back = try ArchiFile.decode(ArchiFile.encode(ed2.doc))
        XCTAssertEqual(ImageDisplay.clipUV(back.entity(id2)!)?.count, 3)
    }

    // MARK: DRW-086 image adjust

    func testImageAdjustVeilsMatchThePixelModel() async throws {
        let (ed, id) = imageEditor()
        ed.selection = []; await ed.run("IMAGEADJUST #\(id)  Brightness 70 Fade 20 Contrast 30 ")
        let a = ImageDisplay.adjustment(ed.doc.entity(id)!)
        XCTAssertEqual(a, ImageDisplay.Adjustment(brightness: 70, contrast: 30, fade: 20))
        let bg = DraftRendering.screenBackground
        let v = ImageDisplay.veils(a, background: bg)
        XCTAssertEqual(v.count, 3)
        // Compositing the veils over any pixel gives the reference adjustment.
        for c in [RGBA(0, 0, 0), RGBA(1, 1, 1), RGBA(0.2, 0.6, 0.9), RGBA(0.5, 0.5, 0.5)] {
            let x = ImageDisplay.composite(c, veils: v), y = ImageDisplay.adjusted(c, a, background: bg)
            XCTAssertEqual(x.r, y.r, accuracy: 1e-12); XCTAssertEqual(x.g, y.g, accuracy: 1e-12); XCTAssertEqual(x.b, y.b, accuracy: 1e-12)
        }
        // The draw list carries the veils over the image frame (translucent fills), on paper they fade to white.
        let items = DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions())
        let alphas = items.compactMap { if case .fill(_, let c) = $0 { return c.a }; return nil }
        XCTAssertEqual(alphas.count, 3)
        XCTAssertEqual(alphas[2], 0.2, accuracy: 1e-12)
        var paper = DrawOptions(); paper.forPaper = true
        let pf = DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: paper).compactMap { if case .fill(_, let c) = $0 { return c }; return nil }
        XCTAssertEqual(pf.last?.r ?? 0, ImageDisplay.paperWhite, accuracy: 1e-12)
        // Out-of-range values are refused; Reset restores the defaults; it is stored in the file.
        ed.selection = []; await ed.run("IMAGEADJUST #\(id)  Fade 140 ")
        XCTAssertEqual(ImageDisplay.adjustment(ed.doc.entity(id)!).fade, 20)
        let back = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(ImageDisplay.adjustment(back.entity(id)!), a)
        ed.selection = []; await ed.run("IMAGEADJUST #\(id)  Reset ")
        XCTAssertTrue(ImageDisplay.adjustment(ed.doc.entity(id)!).isDefault)
        XCTAssertFalse(ImageDisplay.active(ed.doc.entity(id)!))
    }

    // MARK: PRC-036 dynamic UCS

    /// A 45° sloped surface rising along +X: z = x over 0…1000 × 0…1000.
    func slopeDoc() -> ArchiDocument {
        var d = ArchiDocument()
        let v = [Vec3(0, 0, 0), Vec3(1000, 0, 1000), Vec3(1000, 1000, 1000), Vec3(0, 1000, 0)]
        d.add(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: v, meshTriangles: [0, 1, 2, 0, 2, 3])))
        return d
    }

    func testDynamicUCSReadsTypedInputInTheFacePlane() async throws {
        let ed = Editor()
        ed.doc = slopeDoc()
        await ed.run("DUCS ON")
        let f = try XCTUnwrap(DynamicUCS.face(at: Vec2(500, 500), doc: ed.doc))
        XCTAssertEqual(f.origin.z, 500, accuracy: 1e-9)
        let s = 1 / 2.0.squareRoot()
        close3(f.normal, Vec3(-s, 0, s), 1e-9)
        close3(f.yAxis, Vec3(s, 0, s), 1e-9)
        close3(f.fromWorld(f.toWorld(Vec3(12, -34, 56))), Vec3(12, -34, 56), 1e-9)
        ed.dynamicFace = f
        // Typed relative input "@0,1414.2…" runs up the slope: +1000 in X and +1000 in Z.
        let base = f.origin
        InputParser.context.ucs = .world
        let p = try XCTUnwrap(InputParser.parsePoint("@0,\(fmt(1000 * 2.0.squareRoot(), 12))", last: Vec2(base.x, base.y)))
        let r = ed.resolvePoint3(p, typedZ: InputParser.lastParsedZ, typed: InputParser.lastTypedLocal, base: base, defaultZ: 0)
        close3(r, Vec3(1500, 500, 1500), 1e-6)
        // Along the face X (horizontal edge direction: -Y here) nothing rises.
        _ = InputParser.parsePoint("@300,0", last: Vec2(base.x, base.y))
        close3(ed.resolvePoint3(Vec2(0, 0), typedZ: 0, typed: InputParser.lastTypedLocal, base: base, defaultZ: 0), Vec3(500, 200, 500), 1e-9)
        // Picked points beyond the surface stay on the dynamic face plane; the face under the cursor wins over it.
        close3(ed.resolvePoint3(Vec2(1500, 500), typedZ: nil, typed: nil, base: base, defaultZ: 0), Vec3(1500, 500, 1500), 1e-9)
        close3(ed.resolvePoint3(Vec2(250, 800), typedZ: nil, typed: nil, base: base, defaultZ: 0), Vec3(250, 800, 250), 1e-9)
        // The dynamic-input tooltip shows the same face coordinates.
        ed.submit("ID")
        await ed.waitForInputOrIdle()
        ed.dynamicFace = f
        let fields = try XCTUnwrap(ed.dynamicInputFields(cursor: Vec2(600, 500)))
        XCTAssertTrue(fields.onFace)
        XCTAssertEqual(fields.x, 0, accuracy: 1e-9); XCTAssertEqual(fields.y, 100 * 2.0.squareRoot(), accuracy: 1e-9)
        ed.cancel(); await ed.waitIdle()
        // The face is dropped when the command ends.
        XCTAssertNil(ed.dynamicFace)
    }

    func testDynamicUCSPlacesSolidsOnFaces() async throws {
        let ed = Editor()
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))))
        await ed.run("DUCS ON")
        ed.submit("BOX")
        await ed.waitForInputOrIdle()
        ed.feed(.point(Vec2(200, 200)))
        await ed.waitForInputOrIdle()
        XCTAssertNotNil(ed.dynamicFace, "picking over the solid activates the face")
        ed.feedToken("600,700")
        await ed.waitForInputOrIdle()
        ed.feedToken("500")
        await ed.waitIdle()
        guard case .solid(let b)? = ed.doc.entities.last?.geometry else { return XCTFail("no box") }
        XCTAssertEqual(b.origin.z, 3000, accuracy: 1e-9)
        XCTAssertNil(ed.dynamicFace)
        // Off the solid, or with DUCS off, the box sits on the level.
        await ed.run("DUCS OFF")
        await ed.run("BOX 200,200 600,700 500")
        guard case .solid(let c)? = ed.doc.entities.last?.geometry else { return XCTFail("no box") }
        XCTAssertEqual(c.origin.z, 0, accuracy: 1e-9)
        await ed.run("DUCS ON")
        // The sphere lands on the topmost face: the box placed on the first box (3000 + 500).
        await ed.run("SPHERE 500,500 100")
        guard case .solid(let s)? = ed.doc.entities.last?.geometry else { return XCTFail("no sphere") }
        XCTAssertEqual(s.origin.z, 3500, accuracy: 1e-9)
    }

    // MARK: ANN-080 text-linked parameters in tags

    func tagText(_ ed: Editor, _ id: EntityID) -> [String] {
        DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions()).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
    }

    func testTagLabelTemplatesAndAnnotativeTags() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("ROOM 4000,2500 ")
        await ed.run("TAGALL All")
        let tag = try XCTUnwrap(ed.doc.entities.first { $0.props["tagOf"] != nil }).id
        let roomIdx = try XCTUnwrap(ed.doc.elements.firstIndex { if case .space = $0.geometry { return true }; return false })
        ed.doc.elements[roomIdx].props["Finish"] = "Oak"
        ed.selection = []; await ed.run("TAGLABEL #\(tag)  Label {Name}/{Finish}\\n{Area}")
        let field = try XCTUnwrap(ed.doc.entity(tag)?.props["tagField"])
        XCTAssertTrue(field.hasPrefix("family:"))
        var lines = tagText(ed, tag)
        XCTAssertEqual(lines.count, 2)
        guard case .space(let sp) = ed.doc.elements[roomIdx].geometry else { return XCTFail() }
        XCTAssertEqual(lines.first, sp.name + "/Oak")
        XCTAssertTrue(lines.last!.contains(PlanRepresentation.formatArea(abs(GeometryOps.signedArea(sp.boundary)), ed.doc)))
        // Source data changes update the label.
        ed.doc.elements[roomIdx].props["Finish"] = "Tile"
        lines = tagText(ed, tag)
        XCTAssertEqual(lines.first, sp.name + "/Tile")
        // A second tag with the same template shares the label family.
        ed.selection = []; await ed.run("TAGLABEL #\(tag)  Label {Name}/{Finish}\\n{Area}")
        XCTAssertEqual(ed.doc.families.filter { $0.name.hasPrefix("Label ") }.count, 1)
        // A single parameter field.
        ed.selection = []; await ed.run("TAGLABEL #\(tag)  Field Finish")
        XCTAssertEqual(tagText(ed, tag), ["Tile"])
        // Annotative tags follow the annotation scale.
        ed.selection = []; await ed.run("TAGLABEL #\(tag)  Annotative 2.5")
        ed.doc.setVariable("CANNOSCALE", "1:50")
        var d = ed.doc; DocumentUpdaters.run(&d); ed.doc = d
        guard case .text(let t)? = ed.doc.entity(tag)?.geometry else { return XCTFail() }
        XCTAssertEqual(t.height, 125, accuracy: 1e-9)
        ed.doc.setVariable("CANNOSCALE", "1:100")
        d = ed.doc; DocumentUpdaters.run(&d); ed.doc = d
        guard case .text(let t2)? = ed.doc.entity(tag)?.geometry else { return XCTFail() }
        XCTAssertEqual(t2.height, 250, accuracy: 1e-9)
        ed.selection = []; await ed.run("TAGLABEL #\(tag)  List")
        XCTAssertTrue(ed.log.suffix(3).joined().contains("{Finish} = \"Tile\""), ed.log.suffix(3).joined())
    }

    // MARK: BLK-035 / BLK-036 linked models

    func sourceModel() -> ArchiDocument {
        var d = ArchiDocument()
        d.levels.append(Level(id: 2, name: "Roof", elevation: 6000))
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 200, height: 3000)), level: 0)
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(0, 4000), thickness: 200, height: 3000)), level: 1)
        _ = d.addElement(.gridLine(GridLineGeom(start: Vec2(0, -1000), end: Vec2(0, 5000), label: "A")), level: 0)
        return d
    }

    func testLinkedModelLoadsDisplaysAndReloads() async throws {
        let url = tmp("Structure.archi")
        var src = sourceModel()
        try ArchiFile.encode(src).write(to: url)
        let ed = Editor()
        await ed.run("RVTLINK Attach \(url.path) Point 10000,0 0")
        let link = try XCTUnwrap(LinkedModels.named("Structure", ed.doc))
        XCTAssertEqual(link.placement, .point)
        let n0 = LinkedModels.objectCount(ed.doc, name: "Structure")
        XCTAssertGreaterThan(n0, 0)
        // Generated objects are on locked link layers; the elements themselves are not copied into the host.
        XCTAssertTrue(ed.doc.elements.isEmpty)
        XCTAssertTrue(ed.doc.layers.filter { $0.name.hasPrefix("Structure|") }.allSatisfy(\.locked))
        // Plan of the host ground floor shows the link's ground-floor wall at x ≥ 10000; the first floor shows its wall.
        let walls = Set(src.elements.filter { if case .wall = $0.geometry { return true }; return false }.map { "\($0.id)" })
        func planBounds(_ level: Int) -> BBox2 {
            DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: level)).filter { en in
                en.id.flatMap { ed.doc.entity($0)?.props[LinkedModels.sourceProp] }.map(walls.contains) ?? false
            }.reduce(BBox2.empty) { $0.union($1.bounds) }
        }
        let g = planBounds(0), f1 = planBounds(1)
        XCTAssertGreaterThanOrEqual(g.min.x, 10000 - 200); XCTAssertGreaterThan(g.width, 5800)
        XCTAssertLessThan(f1.width, 1000); XCTAssertGreaterThan(f1.height, 3800)
        // 3D: link meshes in the model, not drawn in plans.
        let meshes = MeshBuilder.build(doc: ed.doc)
        XCTAssertFalse(meshes.isEmpty)
        XCTAssertGreaterThanOrEqual(meshes.flatMap(\.mesh.positions).map(\.x).min() ?? 0, 10000 - 200)
        // Reload after the source changed.
        _ = src.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 4000), thickness: 200, height: 3000)), level: 0)
        try ArchiFile.encode(src).write(to: url)
        await ed.run("RVTLINK Reload Structure")
        XCTAssertGreaterThan(LinkedModels.objectCount(ed.doc, name: "Structure"), n0)
        // Stored in the .archi file; unload, reload, detach.
        let back = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(LinkedModels.all(back).first?.name, "Structure")
        await ed.run("RVTLINK Unload Structure")
        XCTAssertEqual(LinkedModels.objectCount(ed.doc, name: "Structure"), 0)
        XCTAssertEqual(LinkedModels.named("Structure", ed.doc)?.loaded, false)
        await ed.run("RVTLINK Reload *")
        XCTAssertGreaterThan(LinkedModels.objectCount(ed.doc, name: "Structure"), 0)
        await ed.run("RVTLINK Detach Structure")
        XCTAssertTrue(LinkedModels.all(ed.doc).isEmpty)
        XCTAssertEqual(LinkedModels.objectCount(ed.doc, name: "Structure"), 0)
        XCTAssertFalse(ed.doc.layers.contains { $0.name.hasPrefix("Structure|") })
        ed.undo()
        XCTAssertEqual(LinkedModels.all(ed.doc).count, 1)
        // Errors: missing file, duplicate name.
        await ed.run("RVTLINK Attach /nonexistent/model.archi Origin")
        XCTAssertTrue(ed.log.suffix(3).joined().contains("Cannot read"))
        await ed.run("RVTLINK Attach \(url.path) Origin")
        XCTAssertTrue(ed.log.suffix(3).joined().contains("already exists"))
    }

    func testLinkPlacementUnitsAndSharedCoordinates() {
        var src = ArchiDocument(); src.units = .meters
        let host = ArchiDocument()
        let p = LinkedModels.placement(ModelLink(name: "M", path: "m.archi"), source: src, host: host)
        close(p.transform.apply(Vec2(2, 3)), Vec2(2000, 3000))
        XCTAssertEqual(p.elevation(3), 3000, accuracy: 1e-9)
        // Shared coordinates: the same survey point lands on the same host point.
        var s2 = ArchiDocument()
        SharedCoordinates(basePoint: .zero, easting: 1000, northing: 0, northAngle: 0, elevation: 100).apply(to: &s2)
        var h2 = ArchiDocument()
        SharedCoordinates(basePoint: .zero, easting: 0, northing: 0, northAngle: 90, elevation: 0).apply(to: &h2)
        let q = LinkedModels.placement(ModelLink(name: "S", path: "s.archi", placement: .shared), source: s2, host: h2)
        let sp = SharedCoordinates.current(s2), hp = SharedCoordinates.current(h2)
        for v in [Vec2(0, 0), Vec2(500, 250), Vec2(-300, 900)] { close(q.transform.apply(v), hp.fromShared(sp.toShared(v)), 1e-6) }
        XCTAssertEqual(q.elevation(0), 100, accuracy: 1e-9)
    }

    func testCopyMonitorLevelsAndGrids() async throws {
        let url = tmp("Arch.archi")
        var src = sourceModel()
        try ArchiFile.encode(src).write(to: url)
        let ed = Editor()
        await ed.run("RVTLINK Attach \(url.path) Origin")
        await ed.run("COPYMONITOR Copy Arch All")
        // Levels at 0 and 3000 already exist and are monitored; "Roof" is copied; grid A is copied.
        XCTAssertEqual(ed.doc.levels.count, 3)
        XCTAssertEqual(ed.doc.levels.last?.name, "Roof")
        let grid = try XCTUnwrap(ed.doc.elements.first { if case .gridLine = $0.geometry { return true }; return false })
        XCTAssertEqual(MonitorLinks.pairs(ed.doc).count, 4)
        await ed.run("COPYMONITOR Check Arch")
        XCTAssertTrue(ed.log.suffix(2).joined().contains("in step"))
        // The link moves grid A and raises the roof.
        let gi = src.elements.firstIndex { if case .gridLine = $0.geometry { return true }; return false }!
        src.elements[gi].geometry = .gridLine(GridLineGeom(start: Vec2(500, -1000), end: Vec2(500, 5000), label: "A"))
        src.levels[2].elevation = 6500
        try ArchiFile.encode(src).write(to: url)
        await ed.run("RVTLINK Reload Arch")
        let review = ed.log.suffix(4).joined(separator: "\n")
        XCTAssertTrue(review.contains("Grid A moved"), review)
        XCTAssertTrue(review.contains("Level Roof: elevation"), review)
        await ed.run("COPYMONITOR Update Arch")
        guard case .gridLine(let g)? = ed.doc.element(grid.id)?.geometry else { return XCTFail() }
        close(g.start, Vec2(500, -1000))
        XCTAssertEqual(ed.doc.levels.first { $0.name == "Roof" }?.elevation ?? 0, 6500, accuracy: 1e-9)
        XCTAssertTrue(MonitorLinks.check(ed.doc, link: LinkedModels.named("Arch", ed.doc)!, source: src).isEmpty)
        await ed.run("COPYMONITOR Release Arch")
        XCTAssertTrue(MonitorLinks.pairs(ed.doc).isEmpty)
    }

    // MARK: ANN-072 fill patterns bound to materials

    func testMaterialBoundHatchesFollowTheirMaterial() async throws {
        let ed = Editor()
        let sq = [Vec2(0, 0), Vec2(2000, 0), Vec2(2000, 1000), Vec2(0, 1000)]
        let h = ed.doc.add(.hatch(HatchGeom(loops: [sq.map { PolyVertex($0) }], pattern: "SOLID")))
        await ed.run("MATHATCH #\(h)  Brick Cut No")
        guard case .hatch(let g)? = ed.doc.entity(h)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.pattern, ed.doc.material("Brick")!.cutPattern)
        XCTAssertNil(g.fill)
        let strokes = DrawListBuilder.items(for: ed.doc.entity(h)!, doc: ed.doc, options: DrawOptions()).filter { if case .stroke = $0 { return true }; return false }
        XCTAssertFalse(strokes.isEmpty)
        // All pattern lines lie inside the boundary.
        for case .stroke(let pts, _, _) in strokes { for p in pts { XCTAssertTrue(p.x > -1e-6 && p.x < 2000 + 1e-6 && p.y > -1e-6 && p.y < 1000 + 1e-6) } }
        // Changing the material's cut pattern updates the bound hatch (one undo step).
        await ed.run("MATPATTERN Brick Cut ANSI37")
        guard case .hatch(let g2)? = ed.doc.entity(h)?.geometry else { return XCTFail() }
        XCTAssertEqual(g2.pattern, "ANSI37")
        ed.undo()
        guard case .hatch(let g3)? = ed.doc.entity(h)?.geometry else { return XCTFail() }
        XCTAssertEqual(g3.pattern, "ANSI31")
        // Surface patterns: set on the material, shown by surface-bound hatches with the material colour behind.
        await ed.run("MATPATTERN Concrete Surface AR-CONC")
        XCTAssertEqual(MaterialPatterns.surfacePattern("Concrete", doc: ed.doc), "AR-CONC")
        ed.selection = []
        await ed.run("MATHATCH #\(h)  Concrete Surface Yes")
        guard case .hatch(let g4)? = ed.doc.entity(h)?.geometry else { return XCTFail() }
        XCTAssertEqual(g4.pattern, "AR-CONC"); XCTAssertNotNil(g4.fill)
        XCTAssertEqual(g4.scale, PlanRepresentation.patternScale("AR-CONC", ed.doc), accuracy: 1e-12)
        var paper = DrawOptions(); paper.forPaper = true
        XCTAssertTrue(DrawListBuilder.items(for: ed.doc.entity(h)!, doc: ed.doc, options: paper).contains { if case .fill = $0 { return true }; return false })
        // Unknown patterns are refused; the binding survives a save and the DXF writer sees the material pattern.
        await ed.run("MATPATTERN Concrete Surface NOPE")
        XCTAssertTrue(ed.log.suffix(2).joined().contains("Unknown pattern"))
        let back = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entity(h)?.props[MaterialPatterns.prop], "Concrete")
        XCTAssertEqual(MaterialPatterns.surfacePattern("Concrete", doc: back), "AR-CONC")
        XCTAssertTrue(DXFWriter.write(ed.doc).contains("AR-CONC"))
        // Removing the surface pattern turns the hatch into a solid fill of the material colour.
        await ed.run("MATPATTERN Concrete Surface None")
        guard case .hatch(let g5)? = ed.doc.entity(h)?.geometry else { return XCTFail() }
        XCTAssertEqual(g5.pattern, "SOLID")
    }
}
