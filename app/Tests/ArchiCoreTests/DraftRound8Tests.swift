// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Round 8 drafting: index-based grip editing and lasso (SEL-007, SEL-032…038), 3D / shared / dynamic coordinate entry
/// (CMD-026, CMD-033, PRC-040), UCS Face / Plane and reference planes (PRC-033, PRC-038), PLAN, true north, base / survey
/// point (PRC-037, PRC-039, PRC-040), axis lock (PRC-028), BIM reference snaps (PRC-016), block editor and in-place
/// reference editing (BLK-004, BLK-005), nested-block cycles (BLK-006) and groups of BIM elements (BLK-015, BLK-016).
@MainActor
final class DraftRound8Tests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func line(_ ed: Editor, _ id: EntityID) -> LineGeom? { if case .line(let l)? = ed.doc.entity(id)?.geometry { return l }; return nil }
    func wall(_ ed: Editor, _ id: EntityID) -> WallGeom? { if case .wall(let w)? = ed.doc.element(id)?.geometry { return w }; return nil }

    // MARK: Grips (SEL-032…038)

    func testSelectionGripsAndStretch() async {
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 2000), end: Vec2(3000, 2000))))
        ed.selection = [l, w]
        let gs = ed.selectionGrips()
        XCTAssertEqual(gs.filter { $0.id == l }.count, 3)
        XCTAssertEqual(gs.filter { $0.id == w }.map(\.point), [Vec2(0, 2000), Vec2(3000, 2000), Vec2(1500, 2000)])
        XCTAssertEqual(ed.gripHit(at: Vec2(1002, 1), tolerance: 5)?.index, 2)
        // GRIPS = 0 hides grips; GRIPOBJLIMIT limits them.
        ed.doc.setVariable("GRIPS", "0"); XCTAssertTrue(ed.selectionGrips().isEmpty)
        ed.doc.setVariable("GRIPS", "1"); ed.doc.setVariable("GRIPOBJLIMIT", "1"); XCTAssertTrue(ed.selectionGrips().isEmpty)
        ed.doc.variables["GRIPOBJLIMIT"] = nil
        // Preview does not change the drawing.
        let pv = ed.gripPreview(l, index: 2, from: Vec2(1000, 0), to: Vec2(1000, 500))
        XCTAssertEqual(pv.geometry.count, 1); close(line(ed, l)!.b, Vec2(1000, 0))
        // Stretch endpoint: one undo step.
        let n = ed.history.undoStack.count
        XCTAssertEqual(ed.gripEdit(l, index: 2, from: Vec2(1000, 0), to: Vec2(1000, 500)), [l])
        close(line(ed, l)!.b, Vec2(1000, 500)); XCTAssertEqual(ed.history.undoStack.count, n + 1)
        ed.undo(); close(line(ed, l)!.b, Vec2(1000, 0))
        // Midpoint grip of a wall moves it; copy keeps the original.
        let ids = ed.gripEdit(w, index: 2, from: Vec2(1500, 2000), to: Vec2(1500, 2500), copy: true)
        XCTAssertEqual(ids.count, 1); XCTAssertNotEqual(ids[0], w)
        close(wall(ed, ids[0])!.start, Vec2(0, 2500)); close(wall(ed, w)!.start, Vec2(0, 2000))
    }

    func testWallEndGripDragsJoinedWall() async {
        let ed = Editor()
        let a = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        let b = ed.doc.addElement(.wall(WallGeom(start: Vec2(4000, 0), end: Vec2(4000, 3000))))
        ed.selection = [a]
        let out = ed.gripEdit(a, index: 1, from: Vec2(4000, 0), to: Vec2(5000, 0))
        XCTAssertEqual(Set(out), [a, b])
        close(wall(ed, a)!.end, Vec2(5000, 0)); close(wall(ed, b)!.start, Vec2(5000, 0))
    }

    func testGripModesActOnSelectionAndTypedValues() async {
        let ed = Editor()
        let l1 = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let l2 = ed.doc.add(.line(LineGeom(Vec2(0, 100), Vec2(1000, 100))))
        ed.selection = [l1, l2]
        XCTAssertEqual(GripMode.keyword("ro"), .rotate); XCTAssertEqual(GripMode.keyword("MI"), .mirror); XCTAssertNil(GripMode.keyword("zz"))
        // Rotate about grip 0 of l1 by dragging to 90°.
        ed.gripEdit(l1, index: 0, from: .zero, to: Vec2(0, 500), mode: .rotate)
        close(line(ed, l1)!.b, Vec2(0, 1000), 1e-9); close(line(ed, l2)!.a, Vec2(-100, 0), 1e-9)
        ed.undo()
        // Typed: move 250 toward the cursor, with Copy.
        let copies = ed.gripTypedValue(l1, index: 0, mode: .move, value: 250, cursor: Vec2(0, 1000), copy: true)
        XCTAssertEqual(copies.count, 2); XCTAssertEqual(ed.doc.entities.count, 4)
        close(line(ed, copies[0])!.a, Vec2(0, 250))
        // Typed stretch distance.
        ed.gripTypedValue(l2, index: 2, mode: .stretch, value: 500, cursor: Vec2(2000, 100))
        close(line(ed, l2)!.b, Vec2(1500, 100))
        // Multi-functional action through the index API.
        let pl = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000)])))
        ed.selection = [pl]
        let acts = ed.gripActions(pl, index: 0)
        XCTAssertFalse(acts.isEmpty)
        if let midIdx = Grips.grips(ed.doc.entity(pl)!.geometry).firstIndex(where: { $0.kind == .midpoint }),
           ed.gripActions(pl, index: midIdx).contains(.addVertex) {
            ed.gripEdit(pl, index: midIdx, from: Vec2(500, 0), to: Vec2(500, -200), action: .addVertex)
            if case .polyline(let p)? = ed.doc.entity(pl)?.geometry { XCTAssertEqual(p.vertices.count, 4) } else { XCTFail() }
        }
    }

    func testLassoApply() async {
        let ed = Editor()
        let a = ed.doc.add(.circle(CircleGeom(Vec2(0, 0), 100)))
        let b = ed.doc.add(.circle(CircleGeom(Vec2(5000, 0), 100)))
        // Clockwise loop around a only = window.
        let loop = [Vec2(-300, -300), Vec2(-300, 300), Vec2(300, 300), Vec2(300, -300)]
        XCTAssertEqual(ed.applyLasso(loop), [a]); XCTAssertEqual(ed.selection, [a])
        ed.selection = [a, b]
        ed.applyLasso(loop, remove: true); XCTAssertEqual(ed.selection, [b])
    }

    // MARK: Coordinate entry (CMD-026, CMD-033, PRC-040)

    func testThreeDCoordinateEntry() async {
        InputParser.context = ParseContext()
        XCTAssertEqual(InputParser.parsePoint3("1,2,3", last: nil), Vec3(1, 2, 3))
        let cyl = InputParser.parsePoint3("100<90,50", last: nil)!
        XCTAssertEqual(cyl.x, 0, accuracy: 1e-9); XCTAssertEqual(cyl.y, 100, accuracy: 1e-9); XCTAssertEqual(cyl.z, 50)
        let sph = InputParser.parsePoint3("100<0<90", last: nil)!
        XCTAssertEqual(sph.x, 0, accuracy: 1e-9); XCTAssertEqual(sph.z, 100, accuracy: 1e-9)
        let sph2 = InputParser.parsePoint3("200<90<30", last: nil)!
        XCTAssertEqual(sph2.y, 200 * cos(Double.pi / 6), accuracy: 1e-9); XCTAssertEqual(sph2.z, 100, accuracy: 1e-9)
        let rel = InputParser.parsePoint3("@10,0,5", last: Vec3(1, 1, 1))!
        XCTAssertEqual(rel, Vec3(11, 1, 6))
        XCTAssertNil(InputParser.parsePoint3("1,2,x", last: nil))
        // 2D parse still works and ignores z.
        close(InputParser.parsePoint("5,6,7", last: nil)!, Vec2(5, 6))
    }

    func testDynamicInputLengthTabAngle() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000\t30  ")
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        XCTAssertEqual(l.a.distance(to: l.b), 1000, accuracy: 1e-9)
        XCTAssertEqual(l.b.angle, Double.pi / 6, accuracy: 1e-9)
    }

    func testID3DAndSharedCoordinates() async {
        let ed = Editor()
        await ed.run("ID 10,20,30 ")
        XCTAssertTrue(ed.log.last?.contains("Z = 30") ?? false)
        await ed.run("PBP 1000,0 ")
        await ed.run("PBP S 500000,4000000 ")
        await ed.run("TRUENORTH 90 ")
        let s = SharedCoordinates.current(ed.doc)
        XCTAssertEqual(s.basePoint, Vec2(1000, 0)); XCTAssertEqual(s.easting, 500000); XCTAssertEqual(ed.doc.info.northAngle, 90)
        // True north points left in the plan: a point 100 to the left of the base point is 100 north.
        close(s.toShared(Vec2(900, 0)), Vec2(500000, 4000100), 1e-6)
        close(s.fromShared(s.toShared(Vec2(123, 456))), Vec2(123, 456), 1e-6)
        XCTAssertEqual(s.bearing(Vec2(-1, 0)), 0, accuracy: 1e-9); XCTAssertEqual(s.bearing(Vec2(0, 1)), 90, accuracy: 1e-9)
        // S:e,n input places the point at the matching internal location.
        await ed.run("LINE S:500000,4000100 S:500000,4000200  ")
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l.a, Vec2(900, 0), 1e-6); close(l.b, Vec2(800, 0), 1e-6)
        await ed.run("ID 900,0 ")
        XCTAssertTrue(ed.log.last?.contains("N = 4000100") ?? false, ed.log.last ?? "")
        // Survey point: the point given (e,n) = (0,0).
        await ed.run("SURVEYPOINT 0,0 0,0 ")
        let s2 = SharedCoordinates.current(ed.doc)
        close(s2.toShared(.zero), .zero, 1e-6); close(s2.surveyPoint, .zero, 1e-6)
        // Plan orientation to true north rotates the display only.
        await ed.run("PLANORIENT T ")
        XCTAssertEqual(ed.doc.variable("VIEWTWIST").flatMap(Double.init) ?? 0, 270, accuracy: 1e-9)
        XCTAssertEqual(SharedCoordinates.viewRotation(ed.doc), -Double.pi / 2, accuracy: 1e-12)
        await ed.run("PLANORIENT P ")
        XCTAssertNil(ed.doc.variable("VIEWTWIST"))
        // Persisted.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(SharedCoordinates.current(back), s2)
    }

    // MARK: UCS, reference planes, PLAN, UCSICON, axis lock

    func testUCSFaceAndReferencePlanes() async {
        let ed = Editor()
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200)))
        _ = w
        await ed.run("UCS F 2000,-90 ")
        let f = UCSFrame.current(ed.doc)
        // Bottom face (y = -100), object to its left (above): X along +x from its start.
        XCTAssertEqual(f.origin.y, -100, accuracy: 1e-9); XCTAssertEqual(normAngle(f.angle), 0, accuracy: 1e-9)
        await ed.run("UCS W ")
        await ed.run("RP 0,1000 1000,2000 Axis-A ")
        XCTAssertEqual(ReferencePlanes.all(ed.doc).map(\.name), ["Axis-A"])
        XCTAssertNotNil(ed.doc.layer(named: ReferencePlanes.layer))
        await ed.run("UCS PL Axis-A ")
        let g = UCSFrame.current(ed.doc)
        close(g.origin, Vec2(0, 1000)); XCTAssertEqual(g.angle, .pi / 4, accuracy: 1e-9)
        // Input follows the work plane: 100,0 lies along the plane.
        await ed.run("POINT 100,0 ")
        guard case .point(let p)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(p, Vec2(100 / 2.squareRoot(), 1000 + 100 / 2.squareRoot()), 1e-6)
        // PLAN makes the UCS X axis horizontal on screen.
        await ed.run("PLAN C ")
        XCTAssertEqual(ed.doc.variable("VIEWTWIST").flatMap(Double.init) ?? 0, 315, accuracy: 1e-6)
        await ed.run("PLAN W ")
        XCTAssertNil(ed.doc.variable("VIEWTWIST"))
        await ed.run("RP S Axis-A ")
        XCTAssertEqual(UCSFrame.current(ed.doc).angle, .pi / 4, accuracy: 1e-9)
        await ed.run("RP D Axis-A ")
        XCTAssertTrue(ReferencePlanes.all(ed.doc).isEmpty)
    }

    func testUCSIconAndAxisLock() async {
        let ed = Editor()
        XCTAssertEqual(UCSIcon.mode(ed.doc), UCSIcon.Mode(on: true, atOrigin: true))
        await ed.run("UCSICON N ")
        XCTAssertEqual(UCSIcon.mode(ed.doc), UCSIcon.Mode(on: true, atOrigin: false))
        let vis = BBox2(min: Vec2(-1000, -1000), max: Vec2(1000, 1000))
        close(UCSIcon.anchor(ed.doc, visible: vis, inset: 50)!, Vec2(-950, -950))
        await ed.run("UCSICON OR ")
        close(UCSIcon.anchor(ed.doc, visible: vis, inset: 50)!, .zero)
        XCTAssertFalse(UCSIcon.geometry(ed.doc, at: .zero, size: 100).isEmpty)
        await ed.run("UCSICON OFF ")
        XCTAssertNil(UCSIcon.anchor(ed.doc, visible: vis, inset: 50))
        // Axis lock projects on the axis through the base point; locking the same axis again unlocks.
        ed.lockAxis("X")
        close(Snap.constrain(base: Vec2(10, 10), cursor: Vec2(500, 300), settings: ed.settings), Vec2(500, 10))
        ed.lockAxis("X"); XCTAssertNil(ed.settings.axisLock)
        await ed.run("AXISLOCK Y ")
        close(Snap.constrain(base: .zero, cursor: Vec2(40, 700), settings: ed.settings), Vec2(0, 700), 1e-9)
        await ed.run("AXISLOCK O ")
        XCTAssertNil(ed.settings.axisLock)
    }

    // MARK: BIM reference snaps (PRC-016)

    func testWallCoreFaceAndCentrelineSnaps() async {
        let ed = Editor()
        // Exterior Brick 365: plaster 15 | brick 240 (structure) | insulation 100 | plaster 10 → core faces at +167.5 and -72.5.
        let w = WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 365, wallType: "Exterior Brick 365")
        let offs = Snap.coreFaceOffsets(w, doc: ed.doc).sorted()
        XCTAssertEqual(offs.count, 2)
        XCTAssertEqual(offs[0], -72.5, accuracy: 1e-9); XCTAssertEqual(offs[1], 167.5, accuracy: 1e-9)
        ed.doc.addElement(.wall(w))
        var s = DraftSettings(); s.snapModes = [.endpoint, .nearest, .intersection]; s.objectSnapTracking = false
        let hit = Snap.find(cursor: Vec2(3, 165), doc: ed.doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(hit?.kind, .endpoint); close(hit!.point, Vec2(0, 167.5))
        let near = Snap.find(cursor: Vec2(2000, 3), doc: ed.doc, settings: s, tolerance: 10, base: nil)
        close(near!.point, Vec2(2000, 0))
        // Centrelines of crossing walls intersect.
        ed.doc.addElement(.wall(WallGeom(start: Vec2(2000, -1000), end: Vec2(2000, 1000))))
        let x = Snap.find(cursor: Vec2(2004, 4), doc: ed.doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(x?.kind, .intersection); close(x!.point, Vec2(2000, 0))
    }

    // MARK: Block editor and REFEDIT (BLK-004 / BLK-005 / BLK-006)

    func testBlockEditorSavesIntoDefinition() async {
        let ed = Editor()
        ed.doc.blocks["DESK"] = Block(name: "DESK", basePoint: .zero, entities: [Entity(id: 1, layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(1200, 0))))])
        let r1 = ed.doc.add(.insert(InsertGeom(block: "DESK", position: Vec2(5000, 0))))
        await ed.run("BEDIT DESK ")
        XCTAssertEqual(BlockEditing.editingBlock(ed.doc), "DESK")
        // Only block content is pickable while editing.
        XCTAssertFalse(PickFilter(ed.doc).pickable(ed.doc.entity(r1)!))
        await ed.run("LINE 0,0 0,600  ")
        await ed.run("BEDIT OTHER ")
        XCTAssertTrue(ed.log.contains { $0.contains("already being edited") })
        await ed.run("BCLOSE S ")
        XCTAssertNil(BlockEditing.editingBlock(ed.doc))
        XCTAssertEqual(ed.doc.blocks["DESK"]?.entities.count, 2)
        XCTAssertEqual(ed.doc.entities.map(\.id), [r1])
        XCTAssertTrue(PickFilter(ed.doc).pickable(ed.doc.entity(r1)!))
        // Undo returns to the editor state.
        ed.undo()
        XCTAssertEqual(BlockEditing.editingBlock(ed.doc), "DESK")
        await ed.run("BCLOSE D ")
        XCTAssertEqual(ed.doc.blocks["DESK"]?.entities.count, 1)
        // New block from BEDIT.
        await ed.run("BEDIT NEWB ")
        await ed.run("CIRCLE 0,0 50 ")
        await ed.run("BSAVE ")
        XCTAssertEqual(ed.doc.blocks["NEWB"]?.entities.count, 1)
        // A block cannot contain itself through the editor.
        await ed.run("INSERT NEWB 100,0 1 0 ")
        await ed.run("BCLOSE S ")
        XCTAssertTrue(ed.log.contains { $0.contains("would contain itself") })
        await ed.run("BCLOSE D ")
        XCTAssertNil(BlockEditing.editingBlock(ed.doc))
    }

    func testRefEditInPlaceMapsBackToBlockCoordinates() async {
        let ed = Editor()
        ed.doc.blocks["B"] = Block(name: "B", basePoint: Vec2(100, 0), entities: [Entity(id: 1, layer: "0", geometry: .line(LineGeom(Vec2(100, 0), Vec2(600, 0))))])
        let r = ed.doc.add(.insert(InsertGeom(block: "B", position: Vec2(1000, 1000), rotation: .pi / 2)))
        let r2 = ed.doc.add(.insert(InsertGeom(block: "B", position: Vec2(0, 0))))
        await ed.run("REFEDIT #\(r) ")
        XCTAssertEqual(BlockEditing.refEditingBlock(ed.doc), "B")
        XCTAssertNil(ed.doc.entity(r))
        let placed = BlockEditing.refEditContent(ed.doc)
        XCTAssertEqual(placed.count, 1)
        guard case .line(let pl) = placed[0].geometry else { return XCTFail() }
        close(pl.a, Vec2(1000, 1000), 1e-9); close(pl.b, Vec2(1000, 1500), 1e-9)
        // Draw a line in world space next to the reference; add an existing drawing object via REFSET.
        await ed.run("LINE 1000,1000 900,1000  ")
        let extra = ed.doc.add(.circle(CircleGeom(Vec2(1000, 1200), 10)))
        await ed.run("REFSET A #\(extra) ")
        await ed.run("REFCLOSE S ")
        XCTAssertNotNil(ed.doc.entity(r)); XCTAssertNotNil(ed.doc.entity(r2))
        let b = ed.doc.blocks["B"]!
        XCTAssertEqual(b.entities.count, 3)
        // World (900,1000) through the inverse of rotation 90° about (1000,1000) with base (100,0) → block (100,100).
        let lines = b.entities.compactMap { e -> LineGeom? in if case .line(let l) = e.geometry { return l }; return nil }
        XCTAssertTrue(lines.contains { $0.b.isClose(Vec2(100, 100), tol: 1e-6) }, "\(lines)")
        XCTAssertNil(ed.doc.entity(extra))
        // Discard leaves the definition alone.
        await ed.run("REFEDIT #\(r2) ")
        await ed.run("ERASE ALL  ")
        await ed.run("REFCLOSE D ")
        XCTAssertEqual(ed.doc.blocks["B"]!.entities.count, 3)
        XCTAssertNotNil(ed.doc.entity(r2))
    }

    func testNestedBlockCycleRejected() async {
        let ed = Editor()
        ed.doc.blocks["A"] = Block(name: "A", entities: [Entity(id: 1, geometry: .circle(CircleGeom(.zero, 10)))])
        ed.doc.blocks["B"] = Block(name: "B", entities: [Entity(id: 2, geometry: .insert(InsertGeom(block: "A", position: .zero)))])
        let i = ed.doc.add(.insert(InsertGeom(block: "B", position: .zero)))
        XCTAssertTrue(BlockEditing.references([ed.doc.entity(i)!], block: "A", doc: ed.doc))
        XCTAssertFalse(BlockEditing.references([ed.doc.entity(i)!], block: "C", doc: ed.doc))
        await ed.run("BLOCK A Y 0,0 #\(i)  C ")
        XCTAssertTrue(ed.log.contains { $0.contains("cannot reference itself") }, ed.log.suffix(3).joined(separator: "|"))
        XCTAssertEqual(ed.doc.blocks["A"]?.entities.count, 1)
    }

    // MARK: Groups with BIM elements (BLK-015 / BLK-016)

    func testGroupsIncludeElementsAndSelectableFlag() async {
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 1000), end: Vec2(3000, 1000))))
        await ed.run("GROUP G1 #\(l),#\(w)  ")
        XCTAssertEqual(Set(BlockTools.groups(ed.doc)["G1"] ?? []), [l, w])
        XCTAssertEqual(Set(ed.expandGroups([w])), [l, w])
        await ed.run("GROUP S G1 ")
        XCTAssertFalse(BlockTools.isSelectable("G1", ed.doc))
        XCTAssertEqual(ed.expandGroups([w]), [w])
        await ed.run("GROUP S G1 ")
        XCTAssertEqual(Set(ed.expandGroups([l])), [l, w])
        await ed.run("GROUP D G1 Furniture set")
        XCTAssertEqual(BlockTools.description("G1", ed.doc), "Furniture set")
        // Moving one member moves the group, element included.
        ed.selection = []
        await ed.run("MOVE #\(l)  0,0 0,500 ")
        XCTAssertEqual(wall(ed, w)!.start.y, 1500, accuracy: 1e-9)
        await ed.run("UNGROUP #\(w)  ")
        XCTAssertTrue(BlockTools.groups(ed.doc).isEmpty)
        XCTAssertNil(ed.doc.variable("GROUPDESC:G1"))
    }

    // MARK: Heads-up input core (CMD-007 / CMD-032 / CMD-034)

    func testKeywordSpansAndDynamicInputFields() async {
        let r = InputRequest("Specify next point", kinds: [.point, .keyword], keywords: ["Close", "Undo"])
        let spans = r.keywordSpans
        XCTAssertEqual(spans.map(\.keyword), ["Close", "Undo"])
        XCTAssertEqual(String(r.promptText[spans[1].range]), "Undo")
        let ed = Editor()
        ed.submit("LINE 0,0")
        await ed.waitForInputOrIdle()
        // LINE is waiting for the next point with base 0,0.
        guard let f = ed.dynamicInputFields(cursor: Vec2(300, 400)) else { return XCTFail("no fields") }
        XCTAssertEqual(f.length ?? 0, 500, accuracy: 1e-9)
        XCTAssertEqual(f.angle ?? 0, 53.130102354, accuracy: 1e-6)
        XCTAssertTrue(f.relative); XCTAssertEqual(f.x, 300, accuracy: 1e-9)
        XCTAssertEqual(ed.dynamicInputToken(length: "1000", angle: "30"), "@1000<30")
        ed.submit(ed.dynamicInputToken(length: "1000", angle: "30")!)
        await ed.waitForInputOrIdle()
        ed.feed(.enter)
        await ed.waitIdle()
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        XCTAssertEqual(l.b.x, 1000 * cos(Double.pi / 6), accuracy: 1e-9)
        XCTAssertEqual(ed.dynamicInputToken(length: "250"), "250")
        XCTAssertNil(ed.dynamicInputToken(length: "abc"))
        ed.doc.setVariable("DYNMODE", "0"); ed.settings.dynamicInput = true
        XCTAssertNil(ed.dynamicInputFields(cursor: .zero))
    }

    // MARK: Temporary dimensions (CMD-035 core)

    func testTemporaryDimensionMovesWall() async {
        let ed = Editor()
        let a = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0))))
        let b = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 4000), end: Vec2(6000, 4000))))
        let c = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 9000), end: Vec2(6000, 9000))))
        _ = a; _ = c
        let tds = ed.temporaryDimensions(for: b)
        XCTAssertEqual(tds.count, 2)
        XCTAssertEqual(Set(tds.map { Int($0.value.rounded()) }), [4000, 5000])
        let below = tds.first { $0.reference == a }!
        XCTAssertTrue(ed.applyTemporaryDimension(below, value: 3000))
        guard case .wall(let w)? = ed.doc.element(b)?.geometry else { return XCTFail() }
        XCTAssertEqual(w.start.y, 3000, accuracy: 1e-9); XCTAssertEqual(w.end.y, 3000, accuracy: 1e-9)
        ed.undo()
        guard case .wall(let w2)? = ed.doc.element(b)?.geometry else { return XCTFail() }
        XCTAssertEqual(w2.start.y, 4000, accuracy: 1e-9)
        // A column measures along X and Y to the nearest walls.
        let col = ed.doc.addElement(.column(ColumnGeom(position: Vec2(3000, 2000))))
        XCTAssertEqual(ed.temporaryDimensions(for: col).count, 2)
    }

    // MARK: WBLOCK (BLK-003)

    func testWblockWritesSelectionAndBlock() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(1000, 1000), Vec2(2000, 1000))))
        ed.doc.blocks["INNER"] = Block(name: "INNER", entities: [Entity(id: 1, geometry: .circle(CircleGeom(.zero, 50)))])
        let i = ed.doc.add(.insert(InsertGeom(block: "INNER", position: Vec2(1500, 1500))))
        let f1 = dir.appendingPathComponent("part.archi").path
        await ed.run("WBLOCK \(f1) O 1000,1000 #\(l),#\(i)  ")
        let d1 = try ArchiFile.decode(Data(contentsOf: URL(fileURLWithPath: f1)))
        XCTAssertEqual(d1.entities.count, 2)
        guard case .line(let ll)? = d1.entities.first(where: { if case .line = $0.geometry { return true }; return false })?.geometry else { return XCTFail() }
        close(ll.a, .zero); close(ll.b, Vec2(1000, 0))
        XCTAssertNotNil(d1.blocks["INNER"], "nested blocks travel with the objects")
        // Inserting the written file back as a block renders and explodes.
        await ed.run("INSERT \(f1) 0,0 1 0 ")
        guard let ins = ed.doc.entities.last, case .insert(let ig) = ins.geometry else { return XCTFail("no insert") }
        XCTAssertEqual(ed.doc.blocks[ig.block]?.entities.count, 2)
        XCTAssertEqual(Modify.explode(ins.geometry, doc: ed.doc)?.count, 2)
        // Block source.
        let f2 = dir.appendingPathComponent("inner.archi").path
        await ed.run("WBLOCK \(f2) B INNER")
        let d2 = try ArchiFile.decode(Data(contentsOf: URL(fileURLWithPath: f2)))
        XCTAssertEqual(d2.entities.count, 1)
    }
}
