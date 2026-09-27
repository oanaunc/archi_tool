// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Round 8 annotation and blocks: revision clouds (ANN-051 / ANN-052), table styles (ANN-058), data extraction of object
/// properties (ANN-061), filled / masking regions (ANN-073), model / drafting patterns (ANN-071), section / elevation /
/// detail marks (ANN-053), multiline stacked fractions (ANN-007), new layer notification (LAY-020), bundled libraries
/// (BLK-037 / BLK-042), BIM arrays (MOD-035) and double-click editing (MOD-063).
@MainActor
final class DraftRound8AnnotationTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func items(_ e: Entity, _ doc: ArchiDocument) -> [DrawItem] {
        DraftRendering.items(e, doc: doc, options: DrawOptions(), color: RGBA(1, 1, 1), lineweight: 0.25) ?? []
    }
    func texts(_ its: [DrawItem]) -> [TextGeom] { its.compactMap { if case .text(let t, _, _) = $0 { return t }; return nil } }

    // MARK: Revision clouds

    func testFreehandResampling() async {
        let r = RevisionClouds.freehand([Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000), Vec2(0, 20)], arcLength: 500)
        XCTAssertTrue(r.closed)
        XCTAssertEqual(r.points.count, 8)
        for i in r.points.indices { XCTAssertEqual(r.points[i].distance(to: r.points[(i + 1) % r.points.count]), 500, accuracy: 30) }
        let open = RevisionClouds.freehand([Vec2(0, 0), Vec2(2000, 0)], arcLength: 500)
        XCTAssertFalse(open.closed); XCTAssertEqual(open.points.count, 5)
    }

    func testRevisionCloudsFreehandEncloseAndRevisionTable() async {
        let ed = Editor()
        var rt = Entity(id: 0, geometry: .table(RevisionSymbols.table(origin: Vec2(0, -5000), textHeight: 100, rows: [["A", "2026-09-01", "OA", "First issue"]])))
        rt.props["revisionTable"] = "1"
        ed.doc.add(rt)
        XCTAssertNotNil(ed.doc.entities.first { $0.props["revisionTable"] == "1" }, ed.log.suffix(8).joined(separator: " | "))
        await ed.run("REVCLOUD V B F 0,0 1000,0 1000,1000 0,1000 0,20  ")
        guard let fh = ed.doc.entities.last, case .polyline(let pl) = fh.geometry else { return XCTFail("no cloud") }
        XCTAssertTrue(pl.closed); XCTAssertEqual(fh.props["revision"], "B"); XCTAssertEqual(fh.props["revcloud"], "1")
        // The revision table gained row B.
        guard case .table(let t)? = ed.doc.entities.first(where: { $0.props["revisionTable"] == "1" })?.geometry else { return XCTFail() }
        XCTAssertEqual(t.cells.map { $0.first ?? "" }, ["REV", "A", "B"])
        // Enclosing cloud follows its object.
        let c = ed.doc.add(.circle(CircleGeom(Vec2(5000, 0), 300)))
        await ed.run("REVCLOUD E #\(c)  100")
        guard let cloud = ed.doc.entities.last, cloud.props[RevisionClouds.hostsProp] == "\(c)" else { return XCTFail("not attached") }
        let b0 = GeometryOps.bounds(cloud.geometry, doc: ed.doc)
        await ed.run("MOVE #\(c)  0,0 1000,500 ")
        let b1 = GeometryOps.bounds(ed.doc.entity(cloud.id)!.geometry, doc: ed.doc)
        close(b1.center - b0.center, Vec2(1000, 500), 1e-6)
        XCTAssertEqual(RevisionClouds.byRevision(ed.doc)["B"]?.count, 2)
        await ed.run("REVCLOUDLIST B")
        XCTAssertEqual(ed.selection.count, 2)
    }

    // MARK: Table styles

    func testTableStyleDrivesRendering() async {
        let ed = Editor()
        ed.settings.textHeight = 100
        await ed.run("TABLESTYLE N Fancy T 2 R red yellow X")
        XCTAssertEqual(ed.doc.variable("CTABLESTYLE"), "Fancy")
        let st = TableStyle.named("fancy", ed.doc)!
        XCTAssertEqual(st.title.height, 2); XCTAssertEqual(st.title.align, .right); XCTAssertEqual(st.title.fill, "yellow")
        XCTAssertEqual(TableStyle.names(ed.doc), ["Standard", "Fancy"])
        await ed.run("TABLE 3 2 1000 300 0,0 Schedule")
        guard let e = ed.doc.entities.last, case .table(let tb) = e.geometry else { return XCTFail("no table") }
        XCTAssertEqual(e.props[TableStyle.prop], "Fancy")
        let its = items(e, ed.doc)
        let title = texts(its).first { $0.content == "Schedule" }
        XCTAssertEqual(title?.height ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(title?.halign, .right)
        // Title row is merged across the table: its text sits at the right edge.
        XCTAssertEqual(title?.position.x ?? 0, tb.columnWidths.reduce(0, +) - 50, accuracy: 1e-6)
        XCTAssertTrue(its.contains { if case .fill = $0 { return true }; return false })
        // Round trip.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(TableStyle.named("Fancy", back), st)
        await ed.run("TABLESTYLE D Fancy")
        XCTAssertNotNil(TableStyle.named("Fancy", ed.doc), "in-use style must not be deleted")
    }

    func testDataExtractionOfProperties() async {
        let ed = Editor()
        ed.doc.add(.line(LineGeom(.zero, Vec2(3000, 4000))))
        ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let rows = BlockTools.propertyRows(ed.doc.entities.map(\.id) + ed.doc.elements.map(\.id), doc: ed.doc)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][4], "5000"); XCTAssertEqual(rows[2][1].lowercased(), "wall"); XCTAssertEqual(rows[2][4], "5000")
        await ed.run("DATAEXTRACTION P  T 0,-10000")
        guard case .table(let t)? = ed.doc.entities.last?.geometry else { return XCTFail("no table") }
        XCTAssertEqual(t.cells.count, 3); XCTAssertEqual(t.cells[0][1], "Type")
        XCTAssertTrue(TableFormulas.csv(t).contains("5000"))
    }

    // MARK: Filled / masking regions and pattern types

    func testFilledAndMaskingRegions() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 2000,1000")
        await ed.run("FILLEDREGION C #FF0000  500,500")
        guard let h = ed.doc.entities.last, case .hatch(let hg) = h.geometry else { return XCTFail("no region") }
        XCTAssertEqual(h.props["filledRegion"], "1"); XCTAssertEqual(h.props["level"], "\(ed.doc.currentLevel)")
        XCTAssertEqual(hg.pattern, "SOLID"); XCTAssertEqual(hg.fill, .rgb(255, 0, 0))
        XCTAssertTrue(AssociativeHatch.isAssociative(h))
        await ed.run("MASKINGREGION D 0,0 100,0 100,100  ")
        guard let m = ed.doc.entities.last, case .hatch = m.geometry else { return XCTFail() }
        XCTAssertEqual(m.props["wipeout"], "1"); XCTAssertEqual(m.props["maskingRegion"], "1")
        // Pattern fill with lines along the boundary, drafting type.
        await ed.run("FILLEDREGION P ANSI31 T Drafting L Y  1000,200")
        let last2 = ed.doc.entities.suffix(2)
        XCTAssertTrue(last2.contains { $0.props["regionEdgeOf"] != nil })
        XCTAssertTrue(last2.contains { $0.props[HatchPatterns.patternTypeProp] == "drafting" })
    }

    func testModelAndDraftingPatternScale() async {
        var doc = ArchiDocument()
        doc.setVariable("CANNOSCALE", "1:50")
        XCTAssertEqual(HatchPatterns.effectiveScale(2, props: ["patternType": "drafting"], doc: doc), 100, accuracy: 1e-9)
        XCTAssertEqual(HatchPatterns.effectiveScale(2, props: ["patternType": "model"], doc: doc), 2, accuracy: 1e-9)
        XCTAssertEqual(HatchPatterns.effectiveScale(2, props: [:], doc: doc), 2)
        // Drafting pattern lines get sparser as the annotation scale grows.
        let loop = [PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10000, 0)), PolyVertex(Vec2(10000, 10000)), PolyVertex(Vec2(0, 10000))]
        var e = Entity(id: 1, geometry: .hatch(HatchGeom(loops: [loop], pattern: "ANSI31", scale: 1)))
        e.props["patternType"] = "drafting"
        let n50 = items(e, doc).count
        doc.setVariable("CANNOSCALE", "1:100")
        let n100 = items(e, doc).count
        XCTAssertGreaterThan(n50, n100)
        let ed = Editor()
        await ed.run("HATCHTYPE M ")
        XCTAssertEqual(ed.doc.variable("HPTYPE"), "model")
    }

    // MARK: Symbols (ANN-053)

    func testSectionElevationDetailMarks() async {
        let ed = Editor()
        await ed.run("SECTIONSYMBOL 0,0 5000,0 2500,1000 1 A-301 1200")
        let ents = ed.doc.entities
        XCTAssertEqual(ents.count, 3)
        XCTAssertEqual(Set(ents.compactMap { $0.props["group"] }).count, 1)
        let heads = ents.compactMap { e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }
        XCTAssertEqual(heads.count, 2)
        XCTAssertEqual(heads[0].attributes["NUM"], "1"); XCTAssertEqual(heads[0].attributes["SHEET"], "A-301")
        XCTAssertEqual(heads[0].rotation, 0, accuracy: 1e-9)       // looking towards +Y
        close(heads[0].position, Vec2(-600, 0)); close(heads[1].position, Vec2(5600, 0))
        XCTAssertNotNil(ed.doc.blocks[AnnotationSymbols.sectionHead])
        // Attribute values render in the drawing.
        let entries = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))
        let allTexts = entries.flatMap { $0.items }.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        XCTAssertTrue(allTexts.contains("A-301")); XCTAssertTrue(allTexts.contains("1"))
        await ed.run("ELEVATIONMARK 10000,0 10000,1000 Y 2 A-401 1000")
        let marks = ed.doc.entities.suffix(4).compactMap { e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }
        XCTAssertEqual(marks.map { $0.attributes["NUM"] ?? "" }, ["2a", "2b", "2c", "2d"])
        await ed.run("DETAILMARK 0,5000 1000,4000 5 A-501 1000")
        XCTAssertEqual(ed.doc.entities.suffix(2).filter { $0.props[AnnotationSymbols.prop] == "detailLeader" }.count, 1)
        // Explode keeps the geometry.
        XCTAssertNotNil(Modify.explode(ed.doc.entities.first { if case .insert = $0.geometry { return true }; return false }!.geometry, doc: ed.doc))
    }

    // MARK: Stacked fractions in multiline text (ANN-007)

    func testMultilineStackedFractions() async {
        let doc = ArchiDocument()
        let t = TextGeom(position: Vec2(0, 0), height: 100, content: "Width 1\\S1/2;\\P3\\S3#4; in", valign: .top)
        let e = Entity(id: 1, geometry: .text(t))
        let its = items(e, doc)
        let ys = Set(texts(its).map { ($0.position.y / 10).rounded() })
        XCTAssertGreaterThanOrEqual(ys.count, 3)
        XCTAssertTrue(texts(its).contains { $0.content == "Width 1" })
        XCTAssertTrue(texts(its).allSatisfy { $0.position.y <= 100 && $0.position.y > -300 })
        XCTAssertTrue(its.contains { if case .stroke = $0 { return true }; return false })
    }

    // MARK: Layer notification (LAY-020)

    func testNewLayerNotification() async {
        let ed = Editor()
        XCTAssertTrue(LayerNotify.unreconciled(ed.doc).isEmpty)
        await ed.run("LAYERNOTIFY ON")
        await ed.run("RP 0,0 1000,0 A ")
        XCTAssertTrue(ed.log.contains { $0.contains("Unreconciled new layer: Reference Planes") }, ed.log.suffix(4).joined(separator: "|"))
        XCTAssertEqual(LayerNotify.unreconciled(ed.doc), ["Reference Planes"])
        await ed.run("LAYRECONCILE ")
        await ed.run("")
        XCTAssertTrue(LayerNotify.unreconciled(ed.doc).isEmpty)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertTrue(LayerNotify.isOn(back)); XCTAssertTrue(LayerNotify.unreconciled(back).isEmpty)
    }

    // MARK: Bundled libraries (BLK-037 / BLK-042)

    func testBundledLibraryInstallBrowseAndInsert() async throws {
        let cats = BundledLibrary.categories
        XCTAssertEqual(cats.map(\.name), ["Furniture", "Sanitary", "Kitchen", "Vehicles", "People", "Trees", "Annotation Symbols"])
        for c in cats { for b in c.blocks { XCTAssertFalse(b.entities.isEmpty, b.name) } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archilib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ed = Editor()
        await ed.run("LIBRARYINSTALL \(dir.path)")
        let items = BlockLibrary.scan(dir)
        XCTAssertEqual(items.filter { $0.block == nil }.count, 7)
        XCTAssertGreaterThanOrEqual(BlockLibrary.search(items, "bed").count, 2)
        XCTAssertFalse(BlockLibrary.search(items, "north arrow").isEmpty)
        XCTAssertFalse(BlockLibrary.search(items, "title block").isEmpty)
        var doc = ArchiDocument()
        let wc = BlockLibrary.search(items, "WC").first { $0.block != nil }!
        let name = try BlockLibrary.load(wc, into: &doc)
        doc.add(.insert(InsertGeom(block: name, position: Vec2(1000, 1000))))
        let b = GeometryOps.bounds(of: doc)
        XCTAssertEqual(b.width, 380, accuracy: 1)
        XCTAssertEqual(ed.doc.variable("BLOCKLIBRARYPATH"), dir.path)
    }

    // MARK: BIM array (MOD-035)

    func testBIMArrayGroupedAndEditable() async {
        let ed = Editor()
        let c = ed.doc.addElement(.column(ColumnGeom(position: .zero)))
        guard let n = ed.createBIMArray([c], rows: 1, columns: 4, rowSpacing: 0, columnSpacing: 3000) else { return XCTFail() }
        XCTAssertEqual(ed.doc.elements.count, 4)
        XCTAssertEqual(ed.bimArrayMembers(n).count, 4)
        XCTAssertEqual(Set(ed.expandGroups([c])).count, 4)
        await ed.run("ARRAYEDIT #\(c) C 6 X")
        XCTAssertEqual(ed.doc.elements.count, 6)
        let xs = ed.doc.elements.compactMap { el -> Double? in if case .column(let k) = el.geometry { return k.position.x }; return nil }.sorted()
        XCTAssertEqual(xs, [0, 3000, 6000, 9000, 12000, 15000])
        ed.undo()
        XCTAssertEqual(ed.doc.elements.count, 4)
        // Walls with a hosted opening: the opening is copied with each wall.
        let ed2 = Editor()
        let w = ed2.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        ed2.doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 2000, width: 900, height: 2100)))
        await ed2.run("ARRAY #\(w)  R 3 1 3000 ")
        XCTAssertEqual(ed2.doc.elements.count, 6)
        XCTAssertEqual(ed2.doc.elements.filter { if case .opening = $0.geometry { return true }; return false }.count, 3)
        guard let an = ed2.bimArrayName(of: w) else { return XCTFail("no BIM array") }
        XCTAssertEqual(ed2.bimArrayMembers(an).count, 6)
        ed2.updateBIMArray(an, rows: 2)
        XCTAssertEqual(ed2.doc.elements.count, 4)
    }

    // MARK: Double-click editing (MOD-063)

    func testDoubleClickCommands() async {
        let ed = Editor()
        let t = ed.doc.add(.text(TextGeom(position: .zero, height: 100, content: "A")))
        let p = ed.doc.add(.polyline(PolylineGeom(points: [.zero, Vec2(1, 0)])))
        ed.doc.blocks["DESK"] = Block(name: "DESK", entities: [Entity(id: 1, geometry: .circle(CircleGeom(.zero, 1)))])
        let i = ed.doc.add(.insert(InsertGeom(block: "DESK", position: .zero)))
        let a = ed.doc.add(.insert(InsertGeom(block: "DESK", position: .zero, attributes: ["TAG": "1"])))
        let w = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(1000, 0))))
        XCTAssertEqual(ed.doubleClickCommand(for: t), "TEXTEDIT #\(t)")
        XCTAssertEqual(ed.doubleClickCommand(for: p), "PEDIT #\(p)")
        XCTAssertEqual(ed.doubleClickCommand(for: i), "BEDIT DESK")
        XCTAssertEqual(ed.doubleClickCommand(for: a), "ATTEDIT #\(a)")
        XCTAssertEqual(ed.doubleClickCommand(for: w), "PROPERTIES")
        ed.doc.setVariable("DBLCLKEDIT", "OFF")
        XCTAssertNil(ed.doubleClickCommand(for: t))
    }

    // MARK: Annotative text styles (ANN-017)

    func testAnnotativeTextStyleUsesPaperHeight() async {
        let ed = Editor()
        await ed.run("SETVAR CANNOSCALE 1:100")
        await ed.run("ANNOTATIVE S Standard Y")
        XCTAssertTrue(AnnotativeText.isAnnotative(style: "Standard", ed.doc))
        await ed.run("TEXT 0,0 2.5 0 Hello  ")
        guard let e = ed.doc.entities.last, case .text(let t) = e.geometry else { return XCTFail("no text") }
        XCTAssertEqual(e.props["annotative"], "1")
        XCTAssertEqual(t.height, 250, accuracy: 1e-9)
        await ed.run("SETVAR CANNOSCALE 1:50")
        guard case .text(let t2)? = ed.doc.entity(e.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(t2.height, 125, accuracy: 1e-9)
    }
}
