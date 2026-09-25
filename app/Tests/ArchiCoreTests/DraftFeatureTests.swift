// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftFeatureTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func line(_ ed: Editor, _ id: EntityID) -> LineGeom? { if case .line(let l)? = ed.doc.entity(id)?.geometry { return l }; return nil }

    // MARK: MOD-029 rotate 90° while dragging

    func testQuarterTurnDragTransformIsExact() {
        XCTAssertEqual(Editor.quarterTurn(-.pi / 2), 3 * .pi / 2, accuracy: 1e-15)
        XCTAssertEqual(Editor.quarterTurn(4 * .pi), 0)
        let t = Editor.dragTransform(from: Vec2(10, 0), to: Vec2(100, 100), rotation: .pi / 2)
        XCTAssertEqual(t.apply(Vec2(10, 0)), Vec2(100, 100))
        XCTAssertEqual(t.apply(Vec2(20, 0)), Vec2(100, 110))   // exact, no cos(π/2) residue
        XCTAssertEqual(t.a, 0); XCTAssertEqual(t.b, 1)
    }

    func testMoveCopyInsertTurn90() async {
        let ed = Editor()
        let id = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        await ed.run("MOVE #\(id) ; 0,0 Turn90 500,500")
        guard let l = line(ed, id) else { return XCTFail() }
        XCTAssertEqual(l.a, Vec2(500, 500)); XCTAssertEqual(l.b, Vec2(500, 600))
        XCTAssertFalse(ed.canRotateDrag)
        XCTAssertFalse(ed.rotateDrag90())
        await ed.run("COPY #\(id) ; 500,500 T T 0,0 ;")
        guard let c = ed.doc.entities.last.flatMap({ e -> LineGeom? in if case .line(let g) = e.geometry { return g }; return nil }), ed.doc.entities.count == 2 else { return XCTFail() }
        XCTAssertEqual(c.a, Vec2(0, 0)); XCTAssertEqual(c.b, Vec2(0, -100))
        ed.doc.blocks["B"] = Block(name: "B", entities: [Entity(geometry: .line(LineGeom(.zero, Vec2(10, 0))))])
        await ed.run("INSERT B T 100,100 ; ;")
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.position, Vec2(100, 100)); XCTAssertEqual(ins.rotation, .pi / 2, accuracy: 1e-12)
    }

    // MARK: MOD-049 TXTEXP with the stroke font

    func testStrokeFontCoversAsciiAndAccents() {
        for v in 32...126 {
            let c = Character(UnicodeScalar(UInt8(v)))
            XCTAssertNotNil(StrokeFont.parsed[c], "missing glyph \(c)")
        }
        let t = TextGeom(position: Vec2(10, 20), height: 9, content: "H")
        let s = StrokeFont.strokes(t)
        let b = BBox2(points: s.flatMap { $0 })
        close(b.min, Vec2(10, 20), 1e-12); close(b.max, Vec2(16, 29), 1e-12)
        XCTAssertGreaterThan(StrokeFont.strokes(TextGeom(position: .zero, height: 9, content: "é")).count,
                             StrokeFont.strokes(TextGeom(position: .zero, height: 9, content: "e")).count)
        // Centred, rotated, two lines.
        let r = TextGeom(position: .zero, height: 9, content: "AB\\PC", rotation: .pi / 2, halign: .center)
        let rb = BBox2(points: StrokeFont.strokes(r).flatMap { $0 })
        XCTAssertEqual(rb.min.y, -rb.max.y, accuracy: 1e-9)                         // centred along the text direction
        XCTAssertEqual(rb.min.x, -9, accuracy: 1e-9); XCTAssertEqual(rb.max.x, 15, accuracy: 1e-9)  // second line one pitch below
        XCTAssertEqual(StrokeFont.lines(TextGeom(position: .zero, height: 9, content: "{\\fArial;x}%%d \\S1/2;")), ["x° 1/2"])
    }

    func testTxtexpToGeometry() async {
        let ed = Editor()
        let id = ed.doc.add(.text(TextGeom(position: Vec2(0, 0), height: 90, content: "A1!,")))
        ed.doc.entities[0].props[DraftRendering.textMaskProp] = "1.5"
        await ed.run("TXTEXP #\(id)  Geometry")
        XCTAssertFalse(ed.doc.entities.contains { if case .text = $0.geometry { return true }; return false })
        XCTAssertGreaterThanOrEqual(ed.doc.entities.count, 6)
        XCTAssertTrue(ed.doc.entities.allSatisfy { $0.props[DraftRendering.textMaskProp] == nil })
        let b = ed.doc.entities.reduce(BBox2.empty) { var x = $0; x.add(GeometryOps.bounds($1.geometry, doc: nil)); return x }
        XCTAssertEqual(b.max.y, 90, accuracy: 1e-9)
        XCTAssertEqual(b.min.y, -15, accuracy: 1e-9)  // comma descender
    }

    // MARK: DRW-048 ellipse tangent to four lines

    func testEllipseInscribedInGeneralQuadrilateral() async {
        let q = [Vec2(0, 0), Vec2(400, 0), Vec2(300, 200), Vec2(50, 250)]
        guard let e = InscribedEllipse.inQuadrilateral(q[0], q[1], q[2], q[3]) else { return XCTFail() }
        for i in 0..<4 { XCTAssertLessThan(InscribedEllipse.tangencyResidual(e, q[i], q[(i + 1) % 4]), 1e-9) }
        XCTAssertTrue(InscribedEllipse.pointInConvex(e.center, q))
        // Parallelogram: equals the midpoint-tangent ellipse.
        let p = [Vec2(0, 0), Vec2(300, 0), Vec2(400, 200), Vec2(100, 200)]
        guard let g = InscribedEllipse.inQuadrilateral(p[0], p[1], p[2], p[3]), let m = InscribedEllipse.inParallelogram(p[0], p[1], p[2], p[3]) else { return XCTFail() }
        close(g.center, m.center, 1e-6)
        XCTAssertEqual(g.majorAxis.length, m.majorAxis.length, accuracy: 1e-5)
        XCTAssertEqual(g.ratio, m.ratio, accuracy: 1e-7)
        XCTAssertNil(InscribedEllipse.inQuadrilateral(Vec2(0, 0), Vec2(100, 0), Vec2(10, 10), Vec2(0, 100)))  // not convex
        // Maximality: nearby members of the family are smaller.
        let area = e.majorAxis.length * e.majorAxis.length * e.ratio
        let ed = Editor()
        await ed.run("ELLIPSEQUAD 0,0 400,0 50,250 300,200")
        guard case .ellipse(let c)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(c.majorAxis.length * c.majorAxis.length * c.ratio, area, accuracy: 1e-6 * area)
        // Four lines, picked in order.
        let ids = (0..<4).map { i in ed.doc.add(.line(LineGeom(q[i] + (q[i] - q[(i + 1) % 4]) * 0.2, q[(i + 1) % 4]))) }
        await ed.run("ELLIPSEQUAD Lines " + ids.map { "#\($0)" }.joined(separator: " "))
        guard case .ellipse(let f)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(f.center, e.center, 1e-6)
    }

    // MARK: ANN-013 text mask exchange

    func testTextMaskMTextGroupsAndWipeoutRoundTrip() {
        let bg = TextMaskExchange.mtextGroups([DraftRendering.textMaskProp: "1.5"])
        XCTAssertEqual(bg.first { $0.code == 90 }?.value, "3")
        XCTAssertEqual(TextMaskExchange.props(fromMTextGroups: bg)[DraftRendering.maskColorProp], "background")
        let rgb = TextMaskExchange.mtextGroups([DraftRendering.textMaskProp: "1.2", DraftRendering.maskColorProp: "#102030"])
        let back = TextMaskExchange.props(fromMTextGroups: rgb)
        XCTAssertEqual(back[DraftRendering.maskColorProp], "#102030"); XCTAssertEqual(back[DraftRendering.textMaskProp], "1.2")
        XCTAssertTrue(TextMaskExchange.props(fromMTextGroups: [(90, "0")]).isEmpty)
        var doc = ArchiDocument()
        let tid = doc.add(.text(TextGeom(position: Vec2(100, 100), height: 25, content: "MASKED", rotation: 0.3)))
        doc.entities[0].props[DraftRendering.textMaskProp] = "1.5"
        let ws = TextMaskExchange.wipeouts(for: doc)
        XCTAssertEqual(ws.count, 1)
        // As a DXF reader would deliver it: wipeout first, then the plain text.
        var imported = ArchiDocument()
        imported.add(ws[0].wipeout)
        var t = doc.entities[0]; t.props = [:]; t.id = 0
        let nid = imported.add(t)
        XCTAssertEqual(TextMaskExchange.absorbWipeouts(&imported), 1)
        XCTAssertEqual(imported.entities.count, 1)
        XCTAssertEqual(Double(imported.entity(nid)?.props[DraftRendering.textMaskProp] ?? "") ?? 0, 1.5, accuracy: 1e-6)
        _ = tid
    }

    // MARK: ANN-065 pattern library

    func testPatternLibraryFillsInsideBoundary() {
        let sq = [[Vec2(0, 0), Vec2(2000, 0), Vec2(2000, 2000), Vec2(0, 2000)]]
        for n in ["ANGLE", "BOX", "BRASS", "BRSTONE", "CLAY", "CORK", "DASH", "DOLMIT", "ESCHER", "FLEX", "GRATE", "HEX", "HOUND", "MUDST", "NET3",
                  "PLAST", "PLASTI", "SACNCR", "STARS", "STEEL", "SWAMP", "TRANS", "TRIANG", "AR-B816C", "AR-B88", "AR-BRELM", "AR-PARQ1",
                  "AR-RROOF", "AR-RSHKE", "GOST_GLASS", "GOST_WOOD", "GOST_GROUND", "ACAD_ISO02W100", "ACAD_ISO15W100"] {
            XCTAssertTrue(HatchPatterns.names.contains(n), n)
            XCTAssertNotNil(HatchPatterns.descriptions[n], n)
            let scale = HatchPatterns.isRealWorld(n) ? 1.0 : 10.0
            let ls = HatchPatterns.lines(loops: sq, pattern: n, scale: scale, angle: 0)
            XCTAssertFalse(ls.isEmpty, n)
            for s in ls { for p in s { XCTAssertTrue(p.x > -1e-6 && p.x < 2000 + 1e-6 && p.y > -1e-6 && p.y < 2000 + 1e-6, n) } }
        }
        for n in HatchPatterns.names { XCTAssertNotNil(HatchPatterns.descriptions[n], n) }
    }

    // MARK: CMD-041 macro buttons

    func testMacroButtonsPersistAndRun() async throws {
        MacroButtons.userFile = nil
        let ed = Editor()
        await ed.run("MACROBUTTON New \"Box\" \"^C^CRECTANG;0,0;100,50;\" \"square\" \"Draw a box\" \"Draw\" X")
        let list = MacroButtons.document(ed.doc)
        XCTAssertEqual(list, [MacroButton(name: "Box", macro: "^C^CRECTANG;0,0;100,50;", icon: "square", tooltip: "Draw a box", group: "Draw")])
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(MacroButtons.document(back), list)
        XCTAssertNil(MacroButtons.validate("^C^C_LINE;\\;", doc: ed.doc))
        XCTAssertNotNil(MacroButtons.validate("NOSUCHCMD;", doc: ed.doc))
        ed.runMacro(list[0].macro)
        await ed.waitIdle()
        guard case .polyline(let p)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(BBox2(points: p.vertices.map(\.p)).max, Vec2(100, 50))
        await ed.run("MACROBUTTON Delete \"Box\" X")
        XCTAssertTrue(MacroButtons.document(ed.doc).isEmpty)
    }

    // MARK: DRW-055 helix

    func testHelix() async {
        let ed = Editor()
        await ed.run("HELIX 0,0 1000 500 Turns 2 3000")
        guard let e = ed.doc.entities.last, case .polyline(let p) = e.geometry else { return XCTFail() }
        XCTAssertEqual(p.vertices.count, 145)
        close(p.vertices[0].p, Vec2(1000, 0), 1e-9); close(p.vertices.last!.p, Vec2(500, 0), 1e-6)
        let z = (e.props["vertexZ"] ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(z.count, 145); XCTAssertEqual(z.last ?? 0, 3000, accuracy: 1e-9)
        // A cylindrical helix is longer than its height and than its plan.
        let (plan, zz) = Helix.points(center: .zero, baseRadius: 100, topRadius: 100, turns: 1, height: 100, segmentsPerTurn: 720)
        let circ: Double = 2 * Double.pi * 100
        let expected: Double = (circ * circ + 10000).squareRoot()
        XCTAssertEqual(Helix.length(plan: plan, z: zz), expected, accuracy: 0.1)
        await ed.run("HELIX 0,0 100 100 tWist CW 50")
        guard case .polyline(let cw)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertLessThan(cw.vertices[1].p.y, 0)
    }

    // MARK: CMD-037 system variable monitor, PRC-029 relative zero, PRC-017/021 modifiers, PRC-018 M2P

    func testSysVarMonitor() async {
        let ed = Editor()
        var seen: [String] = []
        ed.onSysVarChange = { seen += $0 }
        await ed.run("SYSVARMONITOR Add LTSCALE X")
        XCTAssertEqual(SysVarMonitor.watched(ed.doc), ["LTSCALE"])
        await ed.run("SETVAR LTSCALE 2")
        XCTAssertEqual(seen, ["LTSCALE"])
        XCTAssertTrue(ed.log.contains { $0.contains("LTSCALE changed") })
        await ed.run("SYSVARMONITOR Notify No X")
        seen = []
        await ed.run("SETVAR LTSCALE 3")
        XCTAssertTrue(seen.isEmpty)
    }

    func testRelativeZeroAndPointModifiers() async {
        let ed = Editor()
        await ed.run("RELZERO Lock 100,100")
        await ed.run("LINE @10,0 @0,10 ;")
        guard let l = line(ed, ed.doc.entities.last!.id) else { return XCTFail() }
        XCTAssertEqual(l.a, Vec2(110, 100)); XCTAssertEqual(l.b, Vec2(100, 110))
        await ed.run("RELZERO Unlock")
        XCTAssertNil(ed.relativeZeroLock)
        let ed2 = Editor()
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        ed2.doc.add(.line(LineGeom(Vec2(50, -50), Vec2(50, 50))))
        await ed2.run("LINE INTOF 10,0 50,20 @0,100 ;")
        guard let m = line(ed2, ed2.doc.entities.last!.id) else { return XCTFail() }
        XCTAssertEqual(m.a, Vec2(50, 0))
        await ed2.run("LINE 0,0 RH 70,33 RV 5,80 ;")
        let ls = ed2.doc.entities.suffix(2).compactMap { e -> LineGeom? in if case .line(let g) = e.geometry { return g }; return nil }
        XCTAssertEqual(ls.map(\.b), [Vec2(70, 0), Vec2(70, 80)])
        await ed2.run("LINE M2P 0,0 100,40 @0,10 ;")
        guard let mm = line(ed2, ed2.doc.entities.last!.id) else { return XCTFail() }
        XCTAssertEqual(mm.a, Vec2(50, 20))
    }

    // MARK: BLK-031 XCLIP

    func testXclipClipsAndFollowsReference() async {
        let ed = Editor()
        ed.doc.blocks["TWO"] = Block(name: "TWO", entities: [Entity(geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0)))),
                                                             Entity(geometry: .circle(CircleGeom(Vec2(500, 0), 20)))])
        let id = ed.doc.add(.insert(InsertGeom(block: "TWO", position: .zero)))
        await ed.run("XCLIP #\(id) ; New Rectangular -10,-10 60,10")
        func extent() -> BBox2 {
            DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions()).reduce(BBox2.empty) { b, it in
                var b = b; if case .stroke(let p, _, _) = it { p.forEach { b.add($0) } }; return b }
        }
        close(extent().min, Vec2(0, 0), 1e-9); close(extent().max, Vec2(60, 0), 1e-9)
        await ed.run("MOVE #\(id) ; 0,0 1000,0")
        close(extent().max, Vec2(1060, 0), 1e-9)
        await ed.run("XCLIP #\(id) ; OFF")
        XCTAssertEqual(extent().max.x, 1520, accuracy: 0.5)
        await ed.run("XCLIP #\(id) ; Delete")
        XCTAssertNil(ed.doc.entity(id)?.props[BlockClip.prop])
    }

    // MARK: BLK-025 / BLK-026 block tables

    func testBlockTableRows() async {
        let ed = Editor()
        let desk = Entity(geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 600), Vec2(0, 600)], closed: true)))
        ed.doc.blocks["DESK"] = Block(name: "DESK", entities: [desk])
        await ed.run("BPARAMETER DESK Stretch Width 900,-50 1100,700 0,0 1000,0")
        let rid = ed.doc.add(.insert(InsertGeom(block: "DESK", position: .zero)))
        await ed.run("BTABLE DESK Add Large 1800 Add Small 800 List Apply Large #\(rid) ; X")
        XCTAssertEqual(BlockTables.rows("DESK", ed.doc).map(\.name), ["Large", "Small"])
        guard let e = ed.doc.entity(rid), case .insert(let ins) = e.geometry, let v = ed.doc.blocks[ins.block] else { return XCTFail() }
        XCTAssertEqual(e.props[BlockTables.configProp], "Large")
        guard case .polyline(let p)? = v.entities.first?.geometry else { return XCTFail() }
        XCTAssertEqual(BBox2(points: p.vertices.map(\.p)).max.x, 1800, accuracy: 1e-9)
    }

    // MARK: ANN-005 lists, LAY-030 colour books, LAY-018 layer descriptions

    func testListsColourBooksLayerDescriptions() async {
        XCTAssertEqual(TextLists.apply("Alpha\\PBeta\\P\\PGamma", style: .number), "1. Alpha\\P2. Beta\\P\\P3. Gamma")
        XCTAssertEqual(TextLists.apply("1. Alpha\nBeta", style: .upperLetter, start: 27), "AA. Alpha\nAB. Beta")
        XCTAssertEqual(TextLists.apply("• a\n2. b", style: .off), "a\nb")
        let ed = Editor()
        let t = ed.doc.add(.text(TextGeom(position: .zero, height: 10, content: "one\\Ptwo", width: 500)))
        await ed.run("TEXTLIST #\(t)  Bullet")
        if case .text(let g)? = ed.doc.entity(t)?.geometry { XCTAssertEqual(g.content, "• one\\P• two") } else { XCTFail() }
        let l = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))))
        await ed.run("COLORBOOK Apply \"archi materials$brick\" #\(l) ;")
        XCTAssertEqual(ed.doc.entity(l)?.color, .rgb(0xA0, 0x52, 0x2D))
        XCTAssertEqual(ed.doc.entity(l)?.props[ColorBooks.prop], "Archi Materials$Brick")
        XCTAssertEqual(ColorBooks.books["Greyscale"]?.count, 11)
        await ed.run("LAYDESC 0 \"Base layer\"")
        XCTAssertEqual(ed.doc.layers.first?.description, "Base layer")
    }

    // MARK: ANN-040 / ANN-039 / ANN-036 dimension extras

    func testDimensionToleranceAlternateInspection() async {
        let ed = Editor()
        let id = ed.doc.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(100, 0), Vec2(50, 20)], rotation: 0)))
        await ed.run("DIMTOLERANCE #\(id) ; Symmetrical 0.1")
        let ds = ed.doc.dimStyle("Standard")
        guard case .dimension(let d)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(DimExtras.text(d, style: ds, props: ed.doc.entity(id)!.props), "100±0.1")
        await ed.run("DIMALTUNITS #\(id) ; Inches 2 \"in\"")
        XCTAssertEqual(DimExtras.text(d, style: ds, props: ed.doc.entity(id)!.props), "100±0.1 [3.94in]")
        await ed.run("DIMTOLERANCE #\(id) ; Limits 0.2 0.1")
        XCTAssertEqual(DimExtras.text(d, style: ds, props: ed.doc.entity(id)!.props), "100\n100 [3.94in]")
        await ed.run("DIMTOLERANCE #\(id) ; Deviation 0.2 0.1")
        await ed.run("DIMALTUNITS #\(id) ; Off")
        await ed.run("DIMINSPECT #\(id) ; Angular \"A\" \"50%\"")
        let items = DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions())
        let texts = items.compactMap { it -> String? in if case .text(let t, _, _) = it { return t.content }; return nil }
        XCTAssertEqual(texts, ["A | 100 +0.2/-0.1 | 50%"])
        XCTAssertGreaterThanOrEqual(items.filter { if case .stroke(let p, _, _) = $0 { return p.count == 7 }; return false }.count, 1) // angular frame
        await ed.run("DIMINSPECT #\(id) ; Remove")
        await ed.run("DIMTOLERANCE #\(id) ; Basic")
        XCTAssertEqual(DimExtras.frame(ed.doc.entity(id)!.props), "box")
    }

    // MARK: MOD-030/031/032/033/034 associative arrays

    func testAssociativeArrays() async throws {
        let ed = Editor()
        let c = ed.doc.add(.circle(CircleGeom(Vec2(0, 0), 10)))
        await ed.run("ARRAYRECT #\(c) ; 2 3 100 50")
        XCTAssertEqual(ed.doc.entities.count, 1)
        guard let arr = ed.doc.entities.first, case .insert(let ins) = arr.geometry, let p = AssocArray.params(arr) else { return XCTFail() }
        XCTAssertEqual(p.rows, 2); XCTAssertEqual(p.columns, 3)
        XCTAssertEqual(ed.doc.blocks[ins.block]?.entities.count, 6)
        await ed.run("ARRAYEDIT #\(arr.id) Rows 4 200 eXit")
        XCTAssertEqual(ed.doc.blocks[ins.block]?.entities.count, 12)
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(AssocArray.params(back.entity(arr.id)!)?.rows, 4)
        await ed.run("EXPLODE #\(arr.id) ;")
        XCTAssertEqual(ed.doc.entities.count, 12)
        let ys = Set(ed.doc.entities.compactMap { e -> Double? in if case .circle(let g) = e.geometry { return g.center.y }; return nil })
        XCTAssertEqual(ys, [0, 200, 400, 600])
        XCTAssertTrue(ed.doc.entities.allSatisfy { $0.props["arrItem"] == nil && $0.props[AssocArray.paramsProp] == nil })
        // Polar: items and fill editable.
        let ed2 = Editor()
        let pc = ed2.doc.add(.circle(CircleGeom(Vec2(100, 0), 5)))
        await ed2.run("ARRAYPOLAR #\(pc) ; 0,0 4")
        guard let pa = ed2.doc.entities.first, case .insert(let pins) = pa.geometry else { return XCTFail() }
        await ed2.run("ARRAYEDIT #\(pa.id) Items 8 X")
        XCTAssertEqual(ed2.doc.blocks[pins.block]?.entities.count, 8)
        // Path: follows its path.
        let ed3 = Editor()
        let path = ed3.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let it = ed3.doc.add(.circle(CircleGeom(Vec2(0, 0), 5)))
        await ed3.run("ARRAYPATH #\(it) ; #\(path) 5 0,0 Yes")
        guard let pp = ed3.doc.entities.first(where: { AssocArray.isArray($0) }), case .insert(let pins3) = pp.geometry else { return XCTFail() }
        func xs() -> [Double] { (ed3.doc.blocks[pins3.block]?.entities ?? []).compactMap { e -> Double? in if case .circle(let g) = e.geometry { return g.center.x }; return nil }.sorted() }
        XCTAssertEqual(xs(), [0, 250, 500, 750, 1000])
        ed3.transaction("stretch path") { d in if let i = d.entityIndex(path) { d.entities[i].geometry = .line(LineGeom(Vec2(0, 0), Vec2(2000, 0))) } }
        XCTAssertEqual(xs(), [0, 500, 1000, 1500, 2000])
        // Classic arrays make copies whatever ARRAYASSOCIATIVITY says.
        let ed4 = Editor()
        let k = ed4.doc.add(.circle(CircleGeom(Vec2(0, 0), 10)))
        await ed4.run("ARRAYCLASSIC #\(k) ; Rectangular 1 3 100")
        XCTAssertEqual(ed4.doc.entities.count, 3)
        XCTAssertFalse(ed4.forceClassicArray)
    }

    func testFeatureCommandsRegistered() {
        let r = CommandRegistry.shared
        r.ensureBuiltins()
        for n in ["ARRAYEDIT", "ARRAYCLASSIC", "MACROBUTTON", "HELIX", "SYSVARMONITOR", "RELZERO", "XCLIP", "BTABLE", "TEXTLIST",
                  "COLORBOOK", "DIMTOLERANCE", "DIMALTUNITS", "DIMINSPECT", "LAYDESC", "MTEXTCOLUMNS", "AUTOSTACK"] { XCTAssertNotNil(r.lookup(n), n) }
    }

    // MARK: ANN-006 columns, ANN-007 stacked fractions

    func testTextColumnsAndStacks() async {
        let ed = Editor()
        let words = (1...40).map { "w\($0)" }.joined(separator: " ")
        let id = ed.doc.add(.text(TextGeom(position: Vec2(0, 0), height: 10, content: words, width: 420)))
        await ed.run("MTEXTCOLUMNS #\(id)  Static 2 20")
        XCTAssertEqual(ed.doc.entity(id)?.props[DraftRendering.textColumnsProp], "2,20,0")
        let items = DrawListBuilder.items(for: ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions())
        let pos = items.compactMap { it -> Vec2? in if case .text(let t, _, _) = it { return Vec2((t.position.x * 1e6).rounded() / 1e6, (t.position.y * 1e6).rounded() / 1e6) }; return nil }
        let xs = Set(pos.map(\.x))
        XCTAssertEqual(xs, [0, 220])                                  // (420 - 20) / 2 + 20
        let left = pos.filter { $0.x == 0 }.count, right = pos.filter { $0.x == 220 }.count
        XCTAssertTrue(left - right == 0 || left - right == 1)       // balanced
        XCTAssertEqual(pos.map(\.y).max(), -10)                     // first baseline one height below the top
        // Dynamic: fixed height of three lines.
        guard let lay = DraftRendering.columnLayout(TextGeom(position: .zero, height: 10, content: words, width: 420), spec: "2,20,40", widthFactor: 1) else { return XCTFail() }
        XCTAssertEqual(lay.lines.map(\.row).max(), 2)
        // Stacks.
        XCTAssertEqual(TextStacks.autoStack("Door 3/4 x 1^2 v1/2x"), "Door \\S3/4; x \\S1^2; v1/2x")
        XCTAssertEqual(TextStacks.runs("a\\S1/2;b"), [.plain("a"), .stack("1", "2", "/"), .plain("b")])
        let s = ed.doc.add(.text(TextGeom(position: .zero, height: 10, content: "1 1/2 in")))
        await ed.run("AUTOSTACK #\(s)  Stack")
        let si = DrawListBuilder.items(for: ed.doc.entity(s)!, doc: ed.doc, options: DrawOptions())
        let parts = si.compactMap { it -> String? in if case .text(let t, _, _) = it { return t.content }; return nil }
        XCTAssertEqual(parts, ["1 ", "1", "2", " in"])
        XCTAssertEqual(si.filter { if case .stroke = $0 { return true }; return false }.count, 1)   // fraction bar
        await ed.run("AUTOSTACK #\(s)  Unstack")
        if case .text(let t)? = ed.doc.entity(s)?.geometry { XCTAssertEqual(t.content, "1 1/2 in") } else { XCTFail() }
    }

    // MARK: Verified existing: MOD-017 text to front, PRC-041 unit conversion with scaling, SEL-027 select by property

    func testTextToFrontUnitsScaleAndFilter() async {
        let ed = Editor()
        let t = ed.doc.add(.text(TextGeom(position: .zero, height: 10, content: "T")))
        let d = ed.doc.add(.dimension(DimensionGeom(kind: .linear, points: [.zero, Vec2(100, 0), Vec2(50, 10)])))
        let l = ed.doc.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        await ed.run("TEXTTOFRONT Dimensions")
        XCTAssertEqual(ed.doc.entities.map(\.id), [t, l, d])
        await ed.run("TEXTTOFRONT")
        XCTAssertEqual(ed.doc.entities.map(\.id), [l, t, d])
        await ed.run("FILTER \"type=line & length>500\"")
        XCTAssertEqual(ed.selection, [l])
        ed.selection = []
        await ed.run("UNITS MEters 3 Yes")
        XCTAssertEqual(ed.doc.units, .meters)
        if case .line(let g)? = ed.doc.entity(l)?.geometry { XCTAssertEqual(g.b.x, 1, accuracy: 1e-12) } else { XCTFail() }
    }

    // ANN-013 through the DXF reader and writer: MTEXT background-fill codes and WIPEOUT entities.
    func testTextMaskDXFRoundTrip() throws {
        var doc = ArchiDocument()
        let id = doc.add(.text(TextGeom(position: Vec2(10, 20), height: 5, content: "MASK")))
        doc.entities[0].props[DraftRendering.textMaskProp] = "1.25"
        doc.entities[0].props[DraftRendering.maskColorProp] = "#102030"
        let dxf = DXFWriter.write(doc)
        XCTAssertTrue(dxf.contains("MTEXT"))
        let back = try DXFReader.read(dxf)
        let t = back.entities.first { if case .text = $0.geometry { return true }; return false }
        XCTAssertEqual(t?.props[DraftRendering.maskColorProp], "#102030")
        XCTAssertEqual(Double(t?.props[DraftRendering.textMaskProp] ?? "") ?? 0, 1.25, accuracy: 1e-9)
        _ = id
        // A hand-written MTEXT with only the background-fill codes (no Archi XDATA).
        let mt = "0\nSECTION\n2\nENTITIES\n0\nMTEXT\n8\n0\n10\n0\n20\n0\n40\n2.5\n1\nHello\n90\n3\n63\n256\n45\n1.4\n0\nENDSEC\n0\nEOF\n"
        let m = try DXFReader.read(mt)
        XCTAssertEqual(m.entities.first?.props[DraftRendering.maskColorProp], "background")
        XCTAssertEqual(Double(m.entities.first?.props[DraftRendering.textMaskProp] ?? "") ?? 0, 1.4, accuracy: 1e-9)
        // A WIPEOUT drawn just before a text, matching its mask box, becomes the text's mask on import.
        var src = ArchiDocument()
        _ = src.add(.text(TextGeom(position: Vec2(0, 0), height: 10, content: "WIPE")))
        src.entities[0].props[DraftRendering.textMaskProp] = "1.5"
        let box = TextMaskExchange.boundary(src.entities[0], doc: src)!
        let xs = box.map(\.x), ys = box.map(\.y)
        let o = Vec2(xs.min()!, ys.min()!), w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
        let wip = "0\nSECTION\n2\nENTITIES\n0\nWIPEOUT\n8\n0\n10\n\(o.x)\n20\n\(o.y)\n11\n\(w)\n21\n0\n12\n0\n22\n\(h)\n13\n1\n23\n1\n71\n1\n91\n2\n14\n-0.5\n24\n-0.5\n14\n0.5\n24\n0.5\n0\nTEXT\n8\n0\n10\n0\n20\n0\n40\n10\n1\nWIPE\n0\nENDSEC\n0\nEOF\n"
        let wd = try DXFReader.read(wip)
        XCTAssertEqual(wd.entities.count, 1)
        XCTAssertEqual(Double(wd.entities.first?.props[DraftRendering.textMaskProp] ?? "") ?? 0, 1.5, accuracy: 0.05)
    }
}
