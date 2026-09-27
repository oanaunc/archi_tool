// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftToolsTests: XCTestCase {
    override func tearDown() { InputParser.context = ParseContext(); DraftClipboard.current = nil; super.tearDown() }

    func lines(_ ed: Editor) -> [LineGeom] { ed.doc.entities.compactMap { if case .line(let l) = $0.geometry { return l }; return nil } }
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func id(_ ed: Editor, _ g: Geometry) -> EntityID { ed.doc.add(g) }

    // MARK: Scripts and command line

    func testScriptSquareAndBlankLineEntersSelection() async {
        let ed = Editor()
        await ed.runScript("LINE\n0,0\n100,0\n100,100\n0,100\nC\n")
        XCTAssertEqual(lines(ed).count, 4, "a .scr drawing a square produces 4 lines")
        let ed2 = Editor()
        await ed2.runScript("""
        LINE 0,0 100,0

        LINE 0,10 100,10

        ERASE
        W
        -1,-1
        101,1
        ""
        CIRCLE 0,0 50
        """)
        XCTAssertEqual(lines(ed2).count, 1)
        XCTAssertEqual(lines(ed2).first?.a.y ?? -1, 10, accuracy: 1e-9)
        XCTAssertTrue(ed2.doc.entities.contains { if case .circle = $0.geometry { return true }; return false }, "a blank/\"\" line ends the selection and the script continues")
        // A blank line alone also ends a selection prompt.
        let ed3 = Editor()
        await ed3.runScript("LINE 0,0 10,0\n\nERASE\nL\n\nCIRCLE 0,0 5\n")
        XCTAssertEqual(lines(ed3).count, 0)
        XCTAssertEqual(ed3.doc.entities.count, 1)
    }

    func testUnitSuffixesAndAngles() async {
        InputParser.context = ParseContext(units: .millimeters)
        XCTAssertEqual(InputParser.parseNumber("2.5m")!, 2500, accuracy: 1e-9)
        XCTAssertEqual(InputParser.parseNumber("30cm")!, 300, accuracy: 1e-9)
        XCTAssertEqual(InputParser.parseNumber("1m+30cm")!, 1300, accuracy: 1e-9)
        XCTAssertEqual(InputParser.parseNumber("2ft")!, 609.6, accuracy: 1e-9)
        XCTAssertNil(InputParser.parseNumber("2xyz"))
        InputParser.context = ParseContext(units: .meters)
        XCTAssertEqual(InputParser.parseNumber("250mm")!, 0.25, accuracy: 1e-12)
        InputParser.context = ParseContext()
        XCTAssertEqual(InputParser.parseAngleDegrees("45d30'")!, 45.5, accuracy: 1e-12)
        XCTAssertEqual(InputParser.parseAngleDegrees("45d30'36\"")!, 45.51, accuracy: 1e-12)
        XCTAssertEqual(InputParser.parseAngleDegrees("100g")!, 90, accuracy: 1e-12)
        XCTAssertEqual(InputParser.parseAngleDegrees("0.5r")!, deg(0.5), accuracy: 1e-12)
        XCTAssertEqual(InputParser.parseAngleDegrees("N45dE")!, 45, accuracy: 1e-12)
        XCTAssertEqual(InputParser.parseAngleDegrees("S30dW")!, 240, accuracy: 1e-12)
        close(InputParser.parsePoint("@1m<90", last: .zero)!, Vec2(0, 1000))
    }

    func testUnitsInCommandInput() async {
        let ed = Editor()
        await ed.run("LINE 0,0 2.5m,0 ")
        close(lines(ed)[0].b, Vec2(2500, 0))
    }

    func testUCSInputAndCommands() async {
        let ed = Editor()
        await ed.run("UCS 1000,0 1000,1000")
        let f = UCSFrame.current(ed.doc)
        close(f.origin, Vec2(1000, 0))
        XCTAssertEqual(deg(f.angle), 90, accuracy: 1e-9)
        await ed.run("LINE 0,0 100,0 ")
        close(lines(ed)[0].a, Vec2(1000, 0)); close(lines(ed)[0].b, Vec2(1000, 100))
        await ed.run("LINE *0,0 @*10,0 ")
        close(lines(ed)[1].a, .zero); close(lines(ed)[1].b, Vec2(10, 0))
        await ed.run("UCS N S PLAN1")
        await ed.run("UCS W")
        XCTAssertTrue(UCSFrame.current(ed.doc).isWorld)
        await ed.run("UCS P")
        XCTAssertEqual(deg(UCSFrame.current(ed.doc).angle), 90, accuracy: 1e-9)
        await ed.run("UCS W")
        await ed.run("UCS N R PLAN1")
        close(UCSFrame.current(ed.doc).origin, Vec2(1000, 0))
        // Persisted in the file.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        close(UCSFrame.current(back).origin, Vec2(1000, 0))
    }

    func testPointModifiers() async {
        let ed = Editor()
        await ed.run("LINE FROM 100,100 @50,0 M2P 0,0 200,0 ")
        close(lines(ed)[0].a, Vec2(150, 100)); close(lines(ed)[0].b, Vec2(100, 0))
        await ed.run("LINE .X 10,20 30,40 50,50 ")
        close(lines(ed)[1].a, Vec2(10, 40))
        await ed.run("LINE 0,0 TT 500,500 @0,100 ")
        close(lines(ed)[2].b, Vec2(500, 600))
    }

    func testCalDistance() async {
        XCTAssertEqual(CalcFunctions.evaluate("dist(0,0;3,4)")!, 5, accuracy: 1e-12)
        XCTAssertEqual(CalcFunctions.evaluate("dist([0,0],[3,4])*2")!, 10, accuracy: 1e-12)
        XCTAssertEqual(CalcFunctions.evaluate("ang(0,0;1,1)")!, 45, accuracy: 1e-9)
        XCTAssertEqual(CalcFunctions.evaluate("2*(3+4)")!, 14, accuracy: 1e-12)
    }

    func testUserAliasesMacrosAndSuggestions() async {
        let ed = Editor()
        await ed.run("ALIAS D LL LINE")
        await ed.run("LL 0,0 10,0 ")
        XCTAssertEqual(lines(ed).count, 1)
        await ed.run("ALIAS D SQ \"RECTANG 0,0 100,100;\"")
        await ed.run("SQ")
        XCTAssertTrue(ed.doc.entities.contains { if case .polyline = $0.geometry { return true }; return false })
        XCTAssertEqual(ed.doc.variable("ALIAS:LL"), "LINE")
        let log = await ed.run("LNE")
        XCTAssertTrue(log.joined().contains("LINE"), log.joined())
        XCTAssertEqual(UserAliases.parsePGP("; comment\nLL,  *LINE\nSQ, RECTANG 0,0 1,1;\n"), ["LL": "LINE", "SQ": "RECTANG 0,0 1,1;"])
        XCTAssertEqual(UserAliases.macroTokens("^C^CCIRCLE 0,0 5;"), ["CIRCLE", "0,0", "5"])
    }

    func testScriptRecording() async {
        let ed = Editor()
        await ed.run("SCRIPTRECORD \"\"")
        XCTAssertNotNil(ed.recorder)
        await ed.run("LINE 0,0 10,0 ")
        ed.submit("LINE")
        await ed.waitForInputOrIdle()
        ed.feed(.point(Vec2(5, 5)))
        await ed.waitForInputOrIdle()
        ed.feed(.point(Vec2(15, 5)))
        await ed.waitForInputOrIdle()
        ed.feed(.enter)
        await ed.waitIdle()
        await ed.run("SCRIPTRECORD")
        XCTAssertNil(ed.recorder)
        let script = ed.lastRecordedScript ?? ""
        let ed2 = Editor()
        await ed2.runScript(script)
        XCTAssertEqual(lines(ed2).count, 2, script)
    }

    func testTransparentCommand() async {
        let ed = Editor()
        ed.submit("LINE 0,0")
        await ed.waitForInputOrIdle()
        ed.submit("'ORTHO ON")
        await ed.waitForInputOrIdle()
        XCTAssertTrue(ed.settings.ortho)
        XCTAssertEqual(ed.activeCommand?.name, "LINE")
        ed.submit("100,0")
        await ed.waitIdle()
        XCTAssertEqual(lines(ed).count, 1)
    }

    func testSetvarPersistsAndUndoMarks() async throws {
        let ed = Editor()
        await ed.run("SETVAR LTSCALE 2")
        await ed.run("SETVAR CANNOSCALE 1:50")
        let back = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.variable("LTSCALE"), "2")
        XCTAssertEqual(back.variable("CANNOSCALE"), "1:50")
        await ed.run("SETVAR CANNOSCALE abc")
        XCTAssertEqual(ed.doc.variable("CANNOSCALE"), "1:50")

        await ed.run("UNDO M")
        await ed.run("LINE 0,0 1,0 ")
        await ed.run("LINE 0,0 2,0 ")
        await ed.run("UNDO B")
        XCTAssertEqual(lines(ed).count, 0)
        await ed.run("UNDO BE")
        await ed.run("LINE 0,0 1,0 ")
        await ed.run("LINE 0,0 2,0 ")
        await ed.run("UNDO E")
        XCTAssertEqual(lines(ed).count, 2)
        ed.undo()
        XCTAssertEqual(lines(ed).count, 0, "the group is one undo step")
        await ed.run("LINE 0,0 1,0 ")
        await ed.run("LINE 0,0 2,0 ")
        await ed.run("UNDO 2")
        XCTAssertEqual(lines(ed).count, 0)
    }

    // MARK: Selection

    func testSelectionModes() async {
        let ed = Editor()
        let a = id(ed, .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let b = id(ed, .line(LineGeom(Vec2(0, 50), Vec2(100, 50))))
        let c = id(ed, .circle(CircleGeom(Vec2(500, 500), 20)))
        await ed.run("ERASE C 50,-10 60,10 ")
        XCTAssertFalse(ed.doc.contains(a)); XCTAssertTrue(ed.doc.contains(b))
        ed.undo()
        await ed.run("ERASE F -10,25 50,-5 50,60 \"\" ")
        XCTAssertFalse(ed.doc.contains(a)); XCTAssertFalse(ed.doc.contains(b)); XCTAssertTrue(ed.doc.contains(c))
        ed.undo()
        await ed.run("ERASE WP 400,400 600,400 600,600 400,600 \"\" ")
        XCTAssertFalse(ed.doc.contains(c)); XCTAssertTrue(ed.doc.contains(a))
        ed.undo()
        await ed.run("ERASE CP 90,-10 120,-10 120,10 90,10 \"\" ")
        XCTAssertFalse(ed.doc.contains(a)); XCTAssertTrue(ed.doc.contains(b))
        ed.undo()
        await ed.run("ERASE ALL R #\(a) ")
        XCTAssertTrue(ed.doc.contains(a)); XCTAssertFalse(ed.doc.contains(b)); XCTAssertFalse(ed.doc.contains(c))
        await ed.run("OOPS")
        XCTAssertTrue(ed.doc.contains(b)); XCTAssertTrue(ed.doc.contains(c))
    }

    func testQuickSelectFilterAndSimilar() async {
        let ed = Editor()
        ed.doc.ensureLayer("A"); ed.doc.ensureLayer("B")
        var ids: [EntityID] = []
        for (r, l) in [(30.0, "A"), (60, "A"), (80, "B")] { ids.append(ed.doc.add(.circle(CircleGeom(Vec2(r * 10, 0), r)), layer: l)) }
        let ln = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 1))), layer: "A")
        await ed.run("QSELECT Circle radius > 50")
        XCTAssertEqual(ed.selection, [ids[1], ids[2]])
        await ed.run("QSELECT * layer = A A")
        XCTAssertEqual(ed.selection, [ids[0], ids[1], ids[2], ln])
        ed.selection = []
        await ed.run("FILTER type=circle&radius>=60|type=line")
        XCTAssertEqual(ed.selection, [ids[1], ids[2], ln])
        ed.selection = []
        await ed.run("FILTER S BIG radius>70")
        ed.selection = []
        await ed.run("FILTER U BIG")
        XCTAssertEqual(ed.selection, [ids[2]])
        ed.selection = [ids[0]]
        await ed.run("SELECTSIMILAR")
        XCTAssertEqual(ed.selection, [ids[0], ids[1]], "same type and layer (SELECTSIMILARMODE 130)")
        ed.selection = [ids[0]]
        await ed.run("SETVAR SELECTSIMILARMODE 0")
        await ed.run("SELECTSIMILAR")
        XCTAssertEqual(ed.selection, Set(ids))
        ed.selection = [ln]
        await ed.run("SELECTINVERT")
        XCTAssertEqual(ed.selection, Set(ids))
        await ed.run("SELECTLAYER B")
        XCTAssertEqual(ed.selection, [ids[2]])
        ed.selection = []
        await ed.run("SELECTTYPE line")
        XCTAssertEqual(ed.selection, [ln])
        ed.selection = []
        await ed.run("SELSET S S1 #\(ids[0]),#\(ids[2]) ")
        ed.selection = []
        await ed.run("SELSET R S1")
        XCTAssertEqual(ed.selection, [ids[0], ids[2]])
    }

    func testSelectChainAndIntersecting() async {
        let ed = Editor()
        let a = id(ed, .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let b = id(ed, .line(LineGeom(Vec2(100, 0), Vec2(100, 100))))
        let c = id(ed, .arc(ArcGeom(Vec2(50, 100), 50, 0, .pi)))
        let d = id(ed, .line(LineGeom(Vec2(300, 0), Vec2(400, 0))))
        let x = id(ed, .line(LineGeom(Vec2(50, -50), Vec2(50, 50))))
        _ = x
        await ed.run("SELECTCHAIN #\(a)")
        XCTAssertEqual(ed.selection, [a, b, c])
        XCTAssertFalse(ed.selection.contains(d))
        await ed.run("SELECTINTERSECTING #\(a)")
        XCTAssertEqual(ed.selection, [a, b, x])
    }

    func testGroups() async {
        let ed = Editor()
        let a = id(ed, .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let b = id(ed, .line(LineGeom(Vec2(0, 50), Vec2(100, 50))))
        let c = id(ed, .line(LineGeom(Vec2(0, 90), Vec2(100, 90))))
        ed.selection = [a, b]
        await ed.run("GROUP G1")
        XCTAssertEqual(BlockTools.groups(ed.doc)["G1"]?.sorted(), [a, b])
        await ed.run("ERASE #\(a) ")
        XCTAssertFalse(ed.doc.contains(b), "picking a member selects the whole group")
        ed.undo()
        await ed.run("UNGROUP #\(a) ")
        XCTAssertTrue(BlockTools.groups(ed.doc).isEmpty)
        await ed.run("ERASE #\(a) ")
        XCTAssertTrue(ed.doc.contains(b)); XCTAssertTrue(ed.doc.contains(c))
    }

    // MARK: Modify

    func testClipboard() async {
        let ed = Editor()
        let a = id(ed, .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        ed.selection = [a]
        await ed.run("COPYCLIP")
        await ed.run("PASTECLIP 1000,1000")
        XCTAssertEqual(lines(ed).count, 2)
        close(lines(ed)[1].a, Vec2(1000, 1000))
        await ed.run("PASTEORIG")
        close(lines(ed)[2].a, .zero)
        await ed.run("PASTEBLOCK 0,500")
        XCTAssertEqual(ed.doc.blocks.count, 1)
        ed.selection = [a]
        await ed.run("CUTCLIP")
        XCTAssertFalse(ed.doc.contains(a))
        let other = Editor()
        await other.run("PASTECLIP 0,0")
        XCTAssertEqual(lines(other).count, 1)
        ed.undo()
        XCTAssertTrue(ed.doc.contains(a))
    }

    func testOverkill() async {
        let ed = Editor()
        _ = id(ed, .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        _ = id(ed, .line(LineGeom(Vec2(100, 0), Vec2(0, 0))))
        _ = id(ed, .line(LineGeom(Vec2(50, 0), Vec2(200, 0))))
        _ = id(ed, .line(LineGeom(Vec2(0, 10), Vec2(10, 10))))
        _ = id(ed, .polyline(PolylineGeom(points: [Vec2(0, 50), Vec2(50, 50), Vec2(100, 50), Vec2(100, 50), Vec2(100, 100)])))
        await ed.run("OVERKILL D ALL ")
        let ls = lines(ed)
        XCTAssertEqual(ls.count, 2)
        XCTAssertTrue(ls.contains { abs($0.a.distance(to: $0.b) - 200) < 1e-9 }, "two coincident lines become one; overlaps merge")
        guard case .polyline(let p)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(p.vertices.count, 3)
    }

    func testSetByLayer() async {
        let ed = Editor()
        var e = Entity(layer: "0", color: .aci(1), linetype: "Dashed", lineweight: 0.5, geometry: .line(LineGeom(.zero, Vec2(1, 0))))
        e = Entity(id: 0, layer: e.layer, color: e.color, linetype: e.linetype, lineweight: e.lineweight, geometry: e.geometry)
        let a = ed.doc.add(e)
        await ed.run("SETBYLAYER #\(a) \"\" Y")
        let r = ed.doc.entity(a)!
        XCTAssertEqual(r.color, .byLayer); XCTAssertNil(r.linetype); XCTAssertNil(r.lineweight)
    }

    // MARK: Draw

    func testDrawTools() async {
        let ed = Editor()
        await ed.run("RECTANG 3P 0,0 100,0 50,40")
        guard case .polyline(let r)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.polyline(r), doc: nil)!, 4000, accuracy: 1e-6)
        await ed.run("RECTANG CE 0,0 50,20")
        guard case .polyline(let rc)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.polyline(rc), doc: nil)!, 4000, accuracy: 1e-6)
        await ed.run("STAR 5 0,0 100 40")
        guard case .polyline(let st)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(st.vertices.count, 10)
        let n = ed.doc.entities.count
        await ed.run("DLINE W 20 0,0 100,0 100,100 ")
        XCTAssertEqual(ed.doc.entities.count, n + 4)
        guard case .polyline(let left) = ed.doc.entities[n].geometry else { return XCTFail() }
        close(left.vertices[1].p, Vec2(90, 10))
        await ed.run("SOLID 0,0 10,0 0,10 10,10 ")
        guard case .hatch(let h)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.hatch(h), doc: nil)!, 100, accuracy: 1e-6)
        ed.selection = [ed.doc.entities.last!.id]
        await ed.run("BOUNDINGBOX")
        guard case .polyline(let bb)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(GeometryOps.area(.polyline(bb), doc: nil)!, 100, accuracy: 1e-6)
    }

    func testCenterMarkAndCenterLineAreAssociative() async {
        let ed = Editor()
        let c = id(ed, .circle(CircleGeom(Vec2(0, 0), 100)))
        await ed.run("SETVAR CENTEREXE 10")
        await ed.run("CENTERMARK #\(c) ")
        let marks = ed.doc.entities.filter { $0.props["centermarkOf"] == "\(c)" }
        XCTAssertEqual(marks.count, 2)
        await ed.run("MOVE #\(c) \"\" 0,0 500,0")
        let moved = ed.doc.entities.filter { $0.props["centermarkOf"] == "\(c)" }.compactMap { e -> LineGeom? in if case .line(let l) = e.geometry { return l }; return nil }
        close(moved[0].a, Vec2(390, 0)); close(moved[0].b, Vec2(610, 0))
        let a = id(ed, .line(LineGeom(Vec2(0, 1000), Vec2(100, 1000))))
        let b = id(ed, .line(LineGeom(Vec2(100, 1200), Vec2(0, 1200))))
        await ed.run("CENTERLINE #\(a) #\(b)")
        guard case .line(let cl)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(cl.a, Vec2(-10, 1100)); close(cl.b, Vec2(110, 1100))
        await ed.run("MOVE #\(b) \"\" 0,0 0,200")
        guard case .line(let cl2)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(cl2.a.y, 1200, accuracy: 1e-9)
    }

    // MARK: Annotation

    func testTextToolsAndSymbols() async {
        let ed = Editor()
        await ed.run("TEXT 0,0 100 0 45%%d")
        guard case .text(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.content, "45°")
        let tid = ed.doc.entities.last!.id
        let before = GeometryOps.textBoxCorners(t)
        await ed.run("JUSTIFYTEXT #\(tid) \"\" MC")
        guard case .text(let j)? = ed.doc.entity(tid)?.geometry else { return XCTFail() }
        XCTAssertEqual(j.halign, .center); XCTAssertEqual(j.valign, .middle)
        for (p, q) in zip(before, GeometryOps.textBoxCorners(j)) { close(p, q, 1e-6) }
        await ed.run("SCALETEXT #\(tid) \"\" S 2")
        guard case .text(let s)? = ed.doc.entity(tid)?.geometry else { return XCTFail() }
        XCTAssertEqual(s.height, 200, accuracy: 1e-9)
        await ed.run("TEXT 0,-300 100 0 second")
        await ed.run("TXT2MTXT ALL ")
        let texts = ed.doc.entities.compactMap { e -> TextGeom? in if case .text(let t) = e.geometry { return t }; return nil }
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(texts[0].content, "45°\nsecond")
    }

    func testFieldsUpdateAutomatically() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 1000,1000")
        let r = ed.doc.entities.last!.id
        await ed.run("FIELD A #\(r) m2:2 \"Area: # m²\" 0,-500 100")
        guard case .text(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.content, "Area: 1.00 m²")
        await ed.run("SCALE #\(r) \"\" 0,0 2")
        guard case .text(let t2)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t2.content, "Area: 4.00 m²", "area field updates after the polyline changes")
        ed.doc.remove(ids: [r])
        Fields.updateAll(&ed.doc)
        guard case .text(let t3)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t3.content, "Area: #### m²")
        // Typed field codes become fields.
        await ed.run("TEXT 0,0 100 0 %<Var(CLAYER)>%")
        guard case .text(let t4)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t4.content, "0")
        XCTAssertEqual(Fields.evaluate("Count(text)", doc: ed.doc), "2")
    }

    func testAnnotativeScale() async {
        let ed = Editor()
        await ed.run("SETVAR CANNOSCALE 1:50")
        await ed.run("TEXT 0,0 125 0 hello")
        let t = ed.doc.entities.last!.id
        await ed.run("ANNOTATIVE Y #\(t) ")
        XCTAssertEqual(ed.doc.entity(t)?.props["paperHeight"], "2.5")
        await ed.run("SETVAR CANNOSCALE 1:100")
        guard case .text(let tx)? = ed.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tx.height, 250, accuracy: 1e-9, "switching 1:50 to 1:100 doubles model text height")
        await ed.run("SCALELISTEDIT A 1:75")
        XCTAssertTrue(Annotative.scaleList(ed.doc).contains("1:75"))
        XCTAssertEqual(Annotative.factor("2:1"), 0.5)
    }

    func testTableEditingAndFormulas() async throws {
        let ed = Editor()
        await ed.run("TABLE 2 3 1000 400 0,0 \"\"")
        let t = ed.doc.entities.last!.id
        await ed.run("TABLEEDIT #\(t) C A2 \"10\" C A3 \"20\" C A4 \"=SUM(A2:A3)\" X")
        guard case .table(let tb)? = ed.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tb.cells[3][0], "30")
        await ed.run("TABLEEDIT #\(t) C A2 \"15\" X")
        guard case .table(let tb2)? = ed.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tb2.cells[3][0], "35", "SUM formula updates when a cell changes")
        await ed.run("TABLEEDIT #\(t) InsertRow 2 X")
        guard case .table(let tb3)? = ed.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tb3.cells.count, 5)
        XCTAssertEqual(tb3.cells[4][0], "35")
        XCTAssertEqual(TableFormulas.formulas(ed.doc.entity(t)!)["A5"], "SUM(A3:A4)")
        XCTAssertEqual(TableFormulas.evaluate("=ROUND(AVERAGE(A1:A3)*2, 1)", cells: [["1"], ["2"], ["4"]])!, 4.7, accuracy: 1e-9)
        let path = NSTemporaryDirectory() + "archi_table_test.csv"
        await ed.run("TABLEEXPORT #\(t) \(path)")
        XCTAssertTrue(try String(contentsOfFile: path, encoding: .utf8).contains("35"))
    }

    func testDimensionEditing() async {
        let ed = Editor()
        let base = id(ed, .dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(100, 0), Vec2(50, -100)], rotation: 0)))
        let d2 = id(ed, .dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(200, 0), Vec2(50, -130)], rotation: 0)))
        let d3 = id(ed, .dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(300, 0), Vec2(50, -400)], rotation: 0)))
        await ed.run("DIMSPACE #\(base) #\(d2),#\(d3) \"\" 50")
        func p3(_ i: EntityID) -> Vec2 { if case .dimension(let d)? = ed.doc.entity(i)?.geometry { return d.points[2] }; return .zero }
        XCTAssertEqual(p3(d2).y, -150, accuracy: 1e-9); XCTAssertEqual(p3(d3).y, -200, accuracy: 1e-9)
        await ed.run("DIMSPACE #\(base) #\(d2) \"\" 0")
        XCTAssertEqual(p3(d2).y, -100, accuracy: 1e-9)
        await ed.run("DIMEDIT N \"<> mm\" #\(base) ")
        if case .dimension(let d)? = ed.doc.entity(base)?.geometry { XCTAssertEqual(d.textOverride, "<> mm") }
        await ed.run("DIMEDIT H #\(base) ")
        if case .dimension(let d)? = ed.doc.entity(base)?.geometry { XCTAssertNil(d.textOverride) }
        await ed.run("DIMTEDIT #\(base) 60,-300")
        close(p3(base), Vec2(60, -300))
    }

    func testMLeaderStyleAndAlign() async {
        let ed = Editor()
        await ed.run("MLEADERSTYLE N NOTES 3.5 Y .")
        await ed.run("SETVAR CANNOSCALE 1:100")
        await ed.run("MLEADER 0,0 100,100 hello")
        guard case .leader(let l)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(l.textHeight, 350, accuracy: 1e-9)
        let a = ed.doc.entities.last!.id
        await ed.run("MLEADER 0,-500 300,-400 world")
        let b = ed.doc.entities.last!.id
        await ed.run("MLEADERALIGN #\(a),#\(b) \"\" #\(a) V")
        guard case .leader(let lb)? = ed.doc.entity(b)?.geometry else { return XCTFail() }
        XCTAssertEqual(lb.points.last!.x, 100, accuracy: 1e-9)
    }

    // MARK: Blocks

    func testBlockTools() async throws {
        let ed = Editor()
        var tag = Entity(layer: "0", geometry: .text(TextGeom(position: .zero, height: 10, content: "NO")))
        tag.props = ["attdef": "NO", "default": "1"]
        ed.doc.blocks["DOORTAG"] = Block(name: "DOORTAG", entities: [Entity(layer: "0", geometry: .circle(CircleGeom(.zero, 50))), tag])
        ed.doc.blocks["PAIR"] = Block(name: "PAIR", entities: [Entity(layer: "0", geometry: .insert(InsertGeom(block: "DOORTAG", position: .zero))),
                                                               Entity(layer: "0", geometry: .insert(InsertGeom(block: "DOORTAG", position: Vec2(200, 0))))])
        ed.doc.blocks["ALT"] = Block(name: "ALT", entities: [Entity(layer: "0", geometry: .line(LineGeom(.zero, Vec2(10, 0))))])
        let i1 = id(ed, .insert(InsertGeom(block: "DOORTAG", position: Vec2(0, 0), attributes: ["NO": "D1"])))
        _ = id(ed, .insert(InsertGeom(block: "DOORTAG", position: Vec2(500, 0), attributes: ["NO": "D2", "OLD": "x"])))
        _ = id(ed, .insert(InsertGeom(block: "PAIR", position: Vec2(0, 1000))))
        XCTAssertEqual(BlockTools.count(ed.doc.entities, doc: ed.doc), ["DOORTAG": 4, "PAIR": 1], "nested references are counted")
        // Nested blocks render and explode one level at a time.
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions())
        XCTAssertFalse(items.isEmpty)
        await ed.run("ATTSYNC DOORTAG")
        if case .insert(let ins) = ed.doc.entities[1].geometry { XCTAssertEqual(ins.attributes, ["NO": "D2"]) }
        await ed.run("BATTMAN DOORTAG NO Tag MARK")
        if case .insert(let ins)? = ed.doc.entity(i1)?.geometry { XCTAssertEqual(ins.attributes, ["MARK": "D1"]) }
        let rows = BlockTools.extractionRows(ed.doc.entities, doc: ed.doc)
        XCTAssertEqual(rows[0].last, "MARK"); XCTAssertEqual(rows.count, 4)
        await ed.run("DATAEXTRACTION A ALL \"\" T 0,-1000")
        guard case .table(let tb)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(tb.cells.count, 4)
        XCTAssertEqual(tb.cells[1][1], "DOORTAG")
        await ed.run("BFLIP H #\(i1) ")
        if case .insert(let ins)? = ed.doc.entity(i1)?.geometry { XCTAssertEqual(ins.scale.x, -1) }
        XCTAssertEqual(ed.doc.entity(i1)?.props["flipH"], "1")
        // BLOCKBASE keeps references in place.
        let before = GeometryOps.bounds(ed.doc.entity(i1)!.geometry, doc: ed.doc)
        await ed.run("BLOCKBASE #\(i1) 20,30")
        let after = GeometryOps.bounds(ed.doc.entity(i1)!.geometry, doc: ed.doc)
        close(before.min, after.min, 1e-6); close(before.max, after.max, 1e-6)
        XCTAssertEqual(ed.doc.blocks["DOORTAG"]!.basePoint.x, -20, accuracy: 1e-9, "flipped reference: local x is mirrored")
        await ed.run("BLOCKREPLACE DOORTAG ALT N")
        XCTAssertEqual(BlockTools.count(ed.doc.entities, doc: ed.doc)["ALT"], 4)
        XCTAssertNotNil(ed.doc.blocks["DOORTAG"])
        await ed.run("BASE 100,200")
        XCTAssertEqual(ed.doc.variable("INSBASE"), "100,200")
    }

    func testInsertBlockFromFile() async throws {
        var src = ArchiDocument()
        src.add(.line(LineGeom(Vec2(100, 100), Vec2(200, 100))))
        src.setVariable("INSBASE", "100,100")
        let path = NSTemporaryDirectory() + "archi_block_src.archi"
        try ArchiFile.encode(src).write(to: URL(fileURLWithPath: path))
        let ed = Editor()
        await ed.run("INSERT \(path) 1000,0 1 1 0")
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.block, "archi_block_src")
        XCTAssertEqual(ed.doc.blocks["archi_block_src"]?.basePoint, Vec2(100, 100))
        // Redefine from file.
        src.add(.line(LineGeom(Vec2(0, 0), Vec2(1, 1))))
        try ArchiFile.encode(src).write(to: URL(fileURLWithPath: path))
        await ed.run("INSERT archi_block_src=\(path) 0,0 1 1 0")
        XCTAssertEqual(ed.doc.blocks["archi_block_src"]?.entities.count, 2)
    }

    func testOverkillAndSelectionGeometryUnits() async {
        let r = Overkill.run([Entity(id: 1, geometry: .circle(CircleGeom(.zero, 5))), Entity(id: 2, geometry: .circle(CircleGeom(.zero, 5)))])
        XCTAssertEqual(r.removed, [2])
        XCTAssertTrue(SelectionGeometry.hits([[Vec2(1, 1), Vec2(2, 2)]], polygon: [.zero, Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)], mode: .windowPolygon))
        XCTAssertFalse(SelectionGeometry.hits([[Vec2(1, 1), Vec2(20, 2)]], polygon: [.zero, Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)], mode: .windowPolygon))
        XCTAssertTrue(SelectionGeometry.hits([[Vec2(1, 1), Vec2(20, 2)]], polygon: [.zero, Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)], mode: .crossingPolygon))
        XCTAssertTrue(ObjectQuery.wildcard("a-wall", "a-*"))
        XCTAssertEqual(ObjectQuery.Criterion(parse: "radius>=50"), ObjectQuery.Criterion("radius", .ge, "50"))
        XCTAssertEqual(TableFormulas.cellIndex("AB12")!.col, 27)
        XCTAssertEqual(TableFormulas.cellName(row: 11, col: 27), "AB12")
    }
}

@MainActor
final class DraftPolylineEditTests: XCTestCase {
    func testAddRemoveVertexAndLinearize() async {
        let ed = Editor()
        await ed.run("PLINE 0,0 100,0 100,100 ")
        let id = ed.doc.entities.last!.id
        await ed.run("PEDIT #\(id) A 50,1 X")
        guard case .polyline(let p)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(p.vertices.count, 4)
        XCTAssertEqual(p.vertices[1].p, Vec2(50, 0))
        await ed.run("PEDIT #\(id) V 99,99 X")
        guard case .polyline(let q)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(q.vertices.count, 3)
        // Arc split keeps the curve; linearize replaces arcs by chords.
        let semi = PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 1), PolyVertex(Vec2(200, 0))])
        let split = DraftGeometry.insertVertex(semi, near: Vec2(100, -100))!
        XCTAssertEqual(split.vertices.count, 3)
        XCTAssertEqual(split.vertices[1].p.x, 100, accuracy: 1e-9); XCTAssertEqual(split.vertices[1].p.y, -100, accuracy: 1e-9)
        XCTAssertEqual(GeometryOps.length(.polyline(split), doc: nil), GeometryOps.length(.polyline(semi), doc: nil), accuracy: 1)
        let lin = DraftGeometry.linearize(semi, maxDeviation: 1)
        XCTAssertGreaterThan(lin.vertices.count, 5)
        XCTAssertTrue(lin.vertices.allSatisfy { $0.bulge == 0 })
        XCTAssertEqual(GeometryOps.length(.polyline(lin), doc: nil), .pi * 100, accuracy: 3)
        XCTAssertNil(DraftGeometry.removeVertex(PolylineGeom(points: [.zero, Vec2(1, 0)]), near: .zero))
    }
}
