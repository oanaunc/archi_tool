// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Verifies the core modify commands: exact transforms, associativity, one undo step per command, trim/extend/offset/
/// fillet/chamfer/break/join/explode results, match properties, draw order, purge and rename.
@MainActor
final class DraftModifyVerifyTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func line(_ ed: Editor, _ id: EntityID) -> LineGeom? { if case .line(let l)? = ed.doc.entity(id)?.geometry { return l }; return nil }
    func lines(_ ed: Editor) -> [LineGeom] { ed.doc.entities.compactMap { if case .line(let l) = $0.geometry { return l }; return nil } }

    func testEraseMixedSelectionIsOneUndoStep() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(10, 0))))
        let b = ed.doc.add(.circle(CircleGeom(.zero, 5)))
        await ed.run("WALL 0,100 1000,100")
        guard let w = ed.doc.elements.last?.id else { return XCTFail() }
        await ed.run("ERASE #\(a),#\(b),#\(w) ")
        XCTAssertNil(ed.doc.entity(a)); XCTAssertNil(ed.doc.entity(b)); XCTAssertNil(ed.doc.element(w))
        ed.undo()
        XCTAssertNotNil(ed.doc.entity(a)); XCTAssertNotNil(ed.doc.entity(b)); XCTAssertNotNil(ed.doc.element(w))
    }

    func testTransformsAreExactAndKeepAssociativity() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        guard let lid = ed.doc.entities.last?.id else { return XCTFail() }
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        guard let did = ed.doc.entities.last?.id else { return XCTFail() }
        await ed.run("MOVE #\(lid)  0,0 0,500")
        close(line(ed, lid)!.a, Vec2(0, 500))
        if case .dimension(let d)? = ed.doc.entity(did)?.geometry {
            close(d.points[0], Vec2(0, 500)); close(d.points[1], Vec2(1000, 500))
            XCTAssertEqual(DimensionRenderer.measurement(d), 1000, accuracy: 1e-9)
        } else { XCTFail() }
        await ed.run("ROTATE #\(lid)  0,500 90")
        close(line(ed, lid)!.b, Vec2(0, 1500))
        await ed.run("SCALE #\(lid)  0,500 2")
        close(line(ed, lid)!.b, Vec2(0, 2500))
        await ed.run("MIRROR #\(lid)  -100,0 -100,10 N")
        close(line(ed, lid)!.a, Vec2(0, 500))                                   // source kept
        close(lines(ed).last!.a, Vec2(-200, 500)); close(lines(ed).last!.b, Vec2(-200, 2500))
        let before = ed.doc.entities.count
        await ed.run("COPY #\(lid)  0,0 50,0 ")
        XCTAssertEqual(ed.doc.entities.count, before + 1)
        close(lines(ed).last!.a, Vec2(50, 500))
    }

    func testStretchKeepsRectangleClosedAndOrthogonal() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 100,50")
        guard let id = ed.doc.entities.last?.id else { return XCTFail() }
        await ed.run("STRETCH 90,-10 110,60 0,0 50,0")
        guard case .polyline(let p)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertTrue(p.closed)
        let xs = Set(p.vertices.map { $0.p.x }), ys = Set(p.vertices.map { $0.p.y })
        XCTAssertEqual(xs, [0, 150]); XCTAssertEqual(ys, [0, 50])
        XCTAssertEqual(abs(GeometryOps.signedArea(p.vertices.map(\.p))), 7500, accuracy: 1e-9)
    }

    func testTrimExtendOffset() async {
        let ed = Editor()
        let h = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(300, 0))))
        ed.doc.add(.line(LineGeom(Vec2(100, -50), Vec2(100, 50))))
        ed.doc.add(.line(LineGeom(Vec2(200, -50), Vec2(200, 50))))
        await ed.run("TRIM 150,0 ")
        let horizontal = lines(ed).filter { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }
        XCTAssertEqual(horizontal.count, 2)
        XCTAssertEqual(horizontal.map { abs($0.b.x - $0.a.x) }.reduce(0, +), 200, accuracy: 1e-9)
        _ = h
        let ed2 = Editor()
        let s = ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(50, 0))))
        ed2.doc.add(.line(LineGeom(Vec2(100, -50), Vec2(100, 50))))
        await ed2.run("EXTEND 45,0 ")
        close(line(ed2, s)!.b, Vec2(100, 0))
        let ed3 = Editor()
        let sq = ed3.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)], closed: true)))
        await ed3.run("OFFSET 100 #\(sq) 2000,500 ")
        guard case .polyline(let o)? = ed3.doc.entities.last?.geometry, ed3.doc.entities.last?.id != sq else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(GeometryOps.polylinePoints(o))), 1200 * 1200, accuracy: 1e-6)
    }

    func testFilletChamferBreakJoin() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 100))))
        await ed.run("FILLET R 20 60,0 0,60")
        guard let arc = ed.doc.entities.compactMap({ e -> ArcGeom? in if case .arc(let x) = e.geometry { return x }; return nil }).first else { return XCTFail() }
        close(arc.center, Vec2(20, 20)); XCTAssertEqual(arc.radius, 20, accuracy: 1e-9)
        close(line(ed, a)!.a, Vec2(20, 0)); close(line(ed, b)!.a, Vec2(0, 20))
        let ed2 = Editor()
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 100))))
        await ed2.run("CHAMFER D 10 30 60,0 0,60")
        let ls = lines(ed2)
        XCTAssertTrue(ls.contains { ($0.a.isClose(Vec2(10, 0)) && $0.b.isClose(Vec2(0, 30))) || ($0.b.isClose(Vec2(10, 0)) && $0.a.isClose(Vec2(0, 30))) })
        let ed3 = Editor()
        ed3.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        await ed3.run("BREAK 20,0 60,0")
        XCTAssertEqual(lines(ed3).map { abs($0.b.x - $0.a.x) }.sorted(), [20, 40])
        await ed3.run("BREAKATPOINT 90,0 90,0")
        XCTAssertEqual(lines(ed3).count, 3)
        let ed4 = Editor()
        let j1 = ed4.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(50, 0))))
        let j2 = ed4.doc.add(.line(LineGeom(Vec2(50, 0), Vec2(100, 0))))
        await ed4.run("JOIN #\(j1),#\(j2) ")
        XCTAssertEqual(ed4.doc.entities.count, 1)
        XCTAssertEqual(GeometryOps.length(ed4.doc.entities[0].geometry, doc: nil), 100, accuracy: 1e-9)
    }

    func testExplodeReverseMatchpropDraworder() async {
        let ed = Editor()
        let sq = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)], closed: true)))
        await ed.run("EXPLODE #\(sq) ")
        XCTAssertEqual(lines(ed).count, 4)
        ed.doc.blocks["B"] = Block(name: "B", entities: [Entity(geometry: .line(LineGeom(.zero, Vec2(1, 0)))), Entity(geometry: .circle(CircleGeom(.zero, 1)))])
        let ins = ed.doc.add(.insert(InsertGeom(block: "B", position: Vec2(100, 100), scale: Vec2(10, 10))))
        await ed.run("EXPLODE #\(ins) ")
        XCTAssertNil(ed.doc.entity(ins))
        XCTAssertTrue(ed.doc.entities.contains { if case .circle(let c) = $0.geometry { return c.center == Vec2(100, 100) && abs(c.radius - 10) < 1e-9 }; return false })
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(5, 0))))
        await ed.run("REVERSE #\(l) ")
        close(line(ed, l)!.a, Vec2(5, 0))
        ed.doc.layers.append(Layer(name: "RED"))
        let src = ed.doc.add(.line(LineGeom(Vec2(0, 50), Vec2(5, 50))), layer: "RED", color: .aci(1))
        await ed.run("MATCHPROP #\(src) #\(l) ")
        XCTAssertEqual(ed.doc.entity(l)?.layer, "RED"); XCTAssertEqual(ed.doc.entity(l)?.color, .aci(1))
        await ed.run("DRAWORDER #\(l)  Back")
        XCTAssertEqual(ed.doc.entities.first?.id, l)
    }

    func testPurgeAndRenameBlocks() async {
        let ed = Editor()
        ed.doc.blocks["USED"] = Block(name: "USED", entities: [Entity(geometry: .point(.zero))])
        ed.doc.blocks["UNUSED"] = Block(name: "UNUSED", entities: [Entity(geometry: .point(.zero))])
        ed.doc.add(.insert(InsertGeom(block: "USED", position: .zero)))
        await ed.run("PURGE Blocks")
        XCTAssertNil(ed.doc.blocks["UNUSED"]); XCTAssertNotNil(ed.doc.blocks["USED"])
        await ed.run("RENAME Block USED KEPT")
        XCTAssertNil(ed.doc.blocks["USED"]); XCTAssertNotNil(ed.doc.blocks["KEPT"])
        if case .insert(let i)? = ed.doc.entities.last?.geometry { XCTAssertEqual(i.block, "KEPT") } else { XCTFail() }
        // A dynamic reference keeps its base block through PURGE.
        ed.doc.blocks["BASE"] = Block(name: "BASE", entities: [Entity(geometry: .line(LineGeom(.zero, Vec2(100, 0))))])
        DynamicBlocks.setParams("BASE", [.init(name: "L", kind: .stretch, window: BBox2(points: [Vec2(90, -1), Vec2(110, 1)]), vector: Vec2(1, 0), base: 100)], &ed.doc)
        ed.doc.add(.insert(InsertGeom(block: "BASE", position: .zero)))
        XCTAssertTrue(DynamicBlocks.apply(["L": 150], toInsert: ed.doc.entities.count - 1, &ed.doc))
        await ed.run("PURGE Blocks")
        XCTAssertNotNil(ed.doc.blocks["BASE"])
    }

    func testEditTextPropertiesAndAttributes() async {
        let ed = Editor()
        let t = ed.doc.add(.text(TextGeom(position: Vec2(5, 5), height: 2.5, content: "OLD", rotation: 0.3)))
        await ed.run("TEXTEDIT #\(t) NEW TEXT")
        guard case .text(let tx)? = ed.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tx.content, "NEW TEXT"); XCTAssertEqual(tx.height, 2.5); XCTAssertEqual(tx.rotation, 0.3); XCTAssertEqual(tx.position, Vec2(5, 5))
        let l = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))))
        await ed.run("CHPROP #\(l)  Color 3 LAyer NEWLAYER ")
        XCTAssertEqual(ed.doc.entity(l)?.color, .aci(3)); XCTAssertEqual(ed.doc.entity(l)?.layer, "NEWLAYER")
        if case .line(let g)? = ed.doc.entity(l)?.geometry { XCTAssertEqual(g.b, Vec2(1, 0)) } else { XCTFail() }
        var constant = Entity(geometry: .text(TextGeom(position: .zero, height: 1, content: "C")), props: ["attdef": "MAKER", "default": "ACME"])
        constant.props[AttributeModes.prop] = "C"
        let room = Entity(geometry: .text(TextGeom(position: .zero, height: 1, content: "R")), props: ["attdef": "ROOM", "default": "1"])
        ed.doc.blocks["TAG"] = Block(name: "TAG", entities: [constant, room])
        let ins = ed.doc.add(.insert(InsertGeom(block: "TAG", position: .zero, attributes: ["MAKER": "ACME", "ROOM": "1"])))
        await ed.run("ATTEDIT #\(ins) 204")
        guard case .insert(let i)? = ed.doc.entity(ins)?.geometry else { return XCTFail() }
        XCTAssertEqual(i.attributes["ROOM"], "204"); XCTAssertEqual(i.attributes["MAKER"], "ACME")
    }
}
