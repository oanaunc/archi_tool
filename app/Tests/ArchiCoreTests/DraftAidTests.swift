// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftAidTests: XCTestCase {
    func sq(_ x: Double, _ y: Double, _ s: Double) -> [Vec2] { [Vec2(x, y), Vec2(x + s, y), Vec2(x + s, y + s), Vec2(x, y + s)] }
    func polylines(_ ed: Editor) -> [PolylineGeom] { ed.doc.entities.compactMap { if case .polyline(let p) = $0.geometry { return p }; return nil } }

    func testPolygonBooleans() async {
        let a = [sq(0, 0, 10)], b = [sq(5, 5, 10)]
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.union, a, b)), 175, accuracy: 1e-9)
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.intersect, a, b)), 25, accuracy: 1e-9)
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.subtract, a, b)), 75, accuracy: 1e-9)
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.xor, a, b)), 150, accuracy: 1e-9)
        // Hole: subtracting an inner square leaves an outer loop and a hole.
        let holed = PolygonBoolean.apply(.subtract, a, [sq(3, 3, 4)])
        XCTAssertEqual(holed.count, 2)
        XCTAssertEqual(PolygonBoolean.area(holed), 84, accuracy: 1e-9)
        // Shared edge union merges into one rectangle with 4 vertices.
        let side = PolygonBoolean.apply(.union, a, [sq(10, 0, 10)])
        XCTAssertEqual(side.count, 1); XCTAssertEqual(side[0].count, 4)
        XCTAssertEqual(PolygonBoolean.area(side), 200, accuracy: 1e-9)
        // Disjoint intersection is empty; disjoint union keeps both.
        XCTAssertTrue(PolygonBoolean.apply(.intersect, a, [sq(50, 50, 1)]).isEmpty)
        XCTAssertEqual(PolygonBoolean.apply(.union, a, [sq(50, 50, 1)]).count, 2)
        // Identical operands.
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.union, a, a)), 100, accuracy: 1e-9)
        XCTAssertEqual(PolygonBoolean.area(PolygonBoolean.apply(.intersect, a, a)), 100, accuracy: 1e-9)
    }

    func testRegionCommands() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 1000,1000")
        let r = ed.doc.entities.last!.id
        await ed.run("CIRCLE 1000,500 300")
        let c = ed.doc.entities.last!.id
        await ed.run("REGIONUNION #\(r),#\(c) ")
        XCTAssertEqual(polylines(ed).count, 1)
        XCTAssertNil(ed.doc.entity(c))
        let area = abs(GeometryOps.signedArea(polylines(ed)[0].vertices.map(\.p)))
        XCTAssertEqual(area, 1e6 + .pi * 300 * 300 / 2, accuracy: 3000)
        ed.undo()
        XCTAssertNotNil(ed.doc.entity(c))
        await ed.run("REGIONSUBTRACT #\(r)  #\(c) ")
        XCTAssertEqual(abs(GeometryOps.signedArea(polylines(ed)[0].vertices.map(\.p))), 1e6 - .pi * 300 * 300 / 2, accuracy: 3000)
        ed.undo()
        await ed.run("REGIONINTERSECT #\(r),#\(c) ")
        XCTAssertEqual(abs(GeometryOps.signedArea(polylines(ed)[0].vertices.map(\.p))), .pi * 300 * 300 / 2, accuracy: 3000)
    }

    func testIsometricConstrain() async {
        var s = DraftSettings(); s.isometric = true; s.ortho = true; s.isoPlane = 1
        let p = Snap.constrain(base: .zero, cursor: Vec2(100, 40), settings: s)
        XCTAssertEqual(p.angle, rad(30), accuracy: 1e-9)
        s.isoPlane = 0
        XCTAssertEqual(Snap.constrain(base: .zero, cursor: Vec2(5, 100), settings: s).x, 0, accuracy: 1e-9)
        let q = Snap.constrain(base: .zero, cursor: Vec2(-100, 50), settings: s)
        XCTAssertEqual(normAngle(q.angle), rad(150), accuracy: 1e-9)
        // Grid snap on the isometric lattice.
        s.ortho = false; s.gridSnap = true; s.gridSpacing = 10
        let g = Snap.constrain(base: .zero, cursor: Vec2(9, 4), settings: s)
        XCTAssertTrue(g.isClose(Vec2.polar(10, rad(30)), tol: 1e-9))
        // Commands and variables.
        let ed = Editor()
        await ed.run("ISODRAFT T")
        XCTAssertTrue(ed.settings.isometric); XCTAssertEqual(ed.settings.isoPlane, 1)
        await ed.run("ISOPLANE")
        XCTAssertEqual(ed.settings.isoPlane, 2)
        XCTAssertEqual(SystemVariables.get("SNAPSTYL", ed), "1")
        await ed.run("ISODRAFT O")
        XCTAssertFalse(ed.settings.isometric)
        // Settings persist (Codable) with the new fields; old settings decode.
        var st = DraftSettings(); st.isometric = true; st.isoPlane = 2
        let back = try! JSONDecoder().decode(DraftSettings.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.isoPlane, 2); XCTAssertTrue(back.isometric)
        XCTAssertFalse(try! JSONDecoder().decode(DraftSettings.self, from: Data("{}".utf8)).isometric)
    }

    func testMultilineAndStyles() async {
        let ed = Editor()
        await ed.run("MLINE S 100 J Z 0,0 1000,0 1000,1000 ")
        let pls = polylines(ed)
        XCTAssertEqual(pls.count, 2)
        let ys = pls.map { $0.vertices[0].p.y }.sorted()
        XCTAssertEqual(ys, [-50, 50])
        // Mitered corner.
        XCTAssertTrue(pls.contains { $0.vertices[1].p.isClose(Vec2(1050, -50), tol: 1e-6) })
        XCTAssertEqual(Set(ed.doc.entities.compactMap { $0.props["group"] }).count, 1)
        await ed.run("MLSTYLE N WALL3 1,0,-1 B")
        XCTAssertEqual(Multiline.style("WALL3", ed.doc)?.elements.count, 3)
        await ed.run("MLINE ST WALL3 J T S 10 0,2000 1000,2000 ")
        let caps = ed.doc.entities.suffix(5)
        XCTAssertEqual(caps.filter { if case .line = $0.geometry { return true }; return false }.count, 2)
        XCTAssertEqual(Multiline.geometry([Vec2(0, 0), Vec2(10, 0)], style: .standard, scale: 2, justification: .top, closed: false).count, 2)
    }

    func testSymbolsConicsNudgeCycleTextFlip() async {
        let ed = Editor()
        await ed.run("NORTHARROW 0,0 1000 90")
        XCTAssertEqual(ed.doc.entities.count, 4)
        XCTAssertTrue(ed.doc.entities.contains { if case .text(let t) = $0.geometry { return t.content == "N" && t.position.y > 500 }; return false })
        await ed.run("SCALEBAR 0,-2000 4 1000 100 M")
        let labels = ed.doc.entities.compactMap { e -> String? in if case .text(let t) = e.geometry, e.props["group"]?.hasPrefix("SCALEBAR") == true { return t.content }; return nil }
        XCTAssertEqual(labels, ["0", "1", "2", "3", "4 m"])
        await ed.run("BREAKLINE 0,-5000 1000,-5000 ")
        guard case .polyline(let bl)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(bl.vertices.count, 6)
        let para = DraftSymbols.parabola(vertex: .zero, focus: Vec2(0, 1), halfWidth: 4)
        XCTAssertEqual(para.first!.y, 4, accuracy: 1e-9); XCTAssertEqual(abs(para.first!.x), 4, accuracy: 1e-9)
        XCTAssertEqual(para.first!.x, -para.last!.x, accuracy: 1e-9)
        for p in para { XCTAssertEqual(p.x * p.x, 4 * p.y, accuracy: 1e-9) }
        let hyp = DraftSymbols.hyperbola(center: .zero, vertex: Vec2(2, 0), b: 1, halfHeight: 3)
        for p in hyp { XCTAssertEqual(p.x * p.x / 4 - p.y * p.y, 1, accuracy: 1e-9) }
        // Nudge and cycling.
        let ed2 = Editor()
        let a = ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let b = ed2.doc.add(.line(LineGeom(Vec2(0, 1), Vec2(100, 1))))
        XCTAssertEqual(Set([ed2.cyclePick(at: Vec2(50, 0.4), tolerance: 5)!, ed2.cyclePick(at: Vec2(50, 0.4), tolerance: 5)!]), [a, b])
        XCTAssertEqual(ed2.pickCandidates(at: Vec2(50, 0.4), tolerance: 5).first, a)
        ed2.selection = [a]
        ed2.settings.gridSnap = true; ed2.settings.gridSpacing = 10
        await ed2.run("NUDGE U")
        guard case .line(let la)? = ed2.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(la.a.y, 10, accuracy: 1e-9)
        XCTAssertEqual(ed2.history.undoLabel, "Nudge")
        // Upside-down text is turned to read left to right.
        let ed3 = Editor()
        let t = ed3.doc.add(.text(TextGeom(position: Vec2(100, 0), height: 10, content: "ABC", rotation: .pi)))
        await ed3.run("TEXTREADABLE #\(t) ")
        guard case .text(let tt)? = ed3.doc.entity(t)?.geometry else { return XCTFail() }
        XCTAssertEqual(tt.rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(tt.halign, .right)
    }

    func testSketchAndArcText() async {
        XCTAssertEqual(Sketch.filter([Vec2(0, 0), Vec2(1, 0), Vec2(2, 0), Vec2(10, 0), Vec2(10.5, 0)], increment: 5), [Vec2(0, 0), Vec2(10.5, 0)])
        let ed = Editor()
        await ed.run("SKETCH I 5 0,0 1,0 2,1 6,1 12,3 20,3 ")
        guard case .polyline(let p)? = ed.doc.entities.last?.geometry else { return XCTFail("no sketch") }
        XCTAssertEqual(p.vertices.count, 4)
        await ed.run("ARC C 0,0 1000,0 A 180")
        let arc = ed.doc.entities.last!.id
        await ed.run("ARCTEXT #\(arc) 100 Convex 0 HELLO")
        let ts = ed.doc.entities.compactMap { e -> TextGeom? in if case .text(let t) = e.geometry { return t }; return nil }
        XCTAssertEqual(ts.map(\.content).joined(), "HELLO")
        for t in ts { XCTAssertEqual(t.position.length, 1000, accuracy: 1e-6) }
        // Reads left to right over the top of the arc, centred.
        XCTAssertLessThan(ts.first!.position.x, ts.last!.position.x)
        XCTAssertEqual(ts[2].position.x, 0, accuracy: 1e-6)
        XCTAssertEqual(ts[2].rotation, 0, accuracy: 1e-9)
    }
}
