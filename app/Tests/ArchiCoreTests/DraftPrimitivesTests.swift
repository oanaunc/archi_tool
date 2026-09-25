// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Verifies the circle, arc, ellipse, polyline and marker-placement commands against their analytic definitions.
@MainActor
final class DraftPrimitivesTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func last(_ ed: Editor) -> Geometry? { ed.doc.entities.last?.geometry }

    func testCircleVariants() async {
        let ed = Editor()
        await ed.run("CIRCLE 100,100 50")
        guard case .circle(let c1)? = last(ed) else { return XCTFail() }
        close(c1.center, Vec2(100, 100)); XCTAssertEqual(c1.radius, 50, accuracy: 1e-12)
        await ed.run("CIRCLE 0,0 D 80")
        guard case .circle(let c2)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(c2.radius, 40, accuracy: 1e-12)
        await ed.run("CIRCLE 2P 0,0 100,0")
        guard case .circle(let c3)? = last(ed) else { return XCTFail() }
        close(c3.center, Vec2(50, 0)); XCTAssertEqual(c3.radius, 50, accuracy: 1e-12)
        await ed.run("CIRCLE 3P 0,0 100,0 50,50")
        guard case .circle(let c4)? = last(ed) else { return XCTFail() }
        close(c4.center, Vec2(50, 0)); XCTAssertEqual(c4.radius, 50, accuracy: 1e-9)
        // Tangent-tangent-radius between two perpendicular lines.
        let ed2 = Editor()
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 1000))))
        await ed2.run("CIRCLE T 500,0 0,500 100")
        guard case .circle(let t)? = last(ed2) else { return XCTFail() }
        close(t.center, Vec2(100, 100), 1e-6); XCTAssertEqual(t.radius, 100, accuracy: 1e-9)
        // Snaps work on the result: quadrant and centre.
        let q = Snap.find(cursor: Vec2(201, 99), doc: ed2.doc, settings: ed2.settings, tolerance: 5, base: nil)
        XCTAssertNotNil(q)
        if let q { close(q.point, Vec2(200, 100), 1e-6) }
    }

    func testArcVariants() async {
        let ed = Editor()
        await ed.run("ARC 100,0 0,100 -100,0")                     // 3 points
        guard case .arc(let a1)? = last(ed) else { return XCTFail() }
        close(a1.center, .zero); XCTAssertEqual(a1.radius, 100, accuracy: 1e-9); XCTAssertEqual(a1.sweep, .pi, accuracy: 1e-9)
        await ed.run("ARC 100,0 C 0,0 0,100")                      // start-centre-end
        guard case .arc(let a2)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(a2.sweep, .pi / 2, accuracy: 1e-9)
        await ed.run("ARC 100,0 C 0,0 A 45")                       // start-centre-angle
        guard case .arc(let a3)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(a3.sweep, .pi / 4, accuracy: 1e-9)
        await ed.run("ARC 100,0 C 0,0 L 100")                      // start-centre-chord length
        guard case .arc(let a4)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(a4.startPoint.distance(to: a4.endPoint), 100, accuracy: 1e-9)
        await ed.run("ARC 100,0 E -100,0 A 180")                   // start-end-angle
        guard case .arc(let a5)? = last(ed) else { return XCTFail() }
        close(a5.center, .zero, 1e-9); XCTAssertEqual(a5.sweep, .pi, accuracy: 1e-9)
        await ed.run("ARC 100,0 E -100,0 R 100")                   // start-end-radius
        guard case .arc(let a6)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(a6.radius, 100, accuracy: 1e-9)
        await ed.run("ARC 100,0 E 0,100 D 90")                     // start-end-direction (tangent up at the start)
        guard case .arc(let a7)? = last(ed) else { return XCTFail() }
        close(a7.center, .zero, 1e-9); XCTAssertEqual(a7.radius, 100, accuracy: 1e-9)
        // Tangential continuation from a line.
        let ed2 = Editor()
        await ed2.run("LINE 0,0 100,0 ")
        await ed2.run("ARC  100,200")
        guard case .arc(let t)? = last(ed2) else { return XCTFail() }
        close(t.center, Vec2(100, 100), 1e-9); XCTAssertEqual(t.radius, 100, accuracy: 1e-9)
    }

    func testEllipseVariants() async {
        let ed = Editor()
        await ed.run("ELLIPSE 0,0 200,0 50")                       // axis endpoints + half other axis
        guard case .ellipse(let e1)? = last(ed) else { return XCTFail() }
        close(e1.center, Vec2(100, 0)); XCTAssertEqual(e1.majorAxis.length, 100, accuracy: 1e-12); XCTAssertEqual(e1.ratio, 0.5, accuracy: 1e-12)
        for k in 0..<8 {
            let t = Double(k) * .pi / 4, p = e1.point(at: t)
            XCTAssertEqual(pow((p.x - 100) / 100, 2) + pow(p.y / 50, 2), 1, accuracy: 1e-9)
        }
        await ed.run("ELLIPSE C 0,0 0,300 100")                     // centre
        guard case .ellipse(let e2)? = last(ed) else { return XCTFail() }
        close(e2.majorAxis, Vec2(0, 300)); XCTAssertEqual(e2.ratio, 1.0 / 3, accuracy: 1e-12)
        await ed.run("ELLIPSE A C 0,0 100,0 50 0 90")              // elliptical arc, quarter
        guard case .ellipse(let e3)? = last(ed) else { return XCTFail() }
        XCTAssertFalse(e3.isFull)
        close(e3.point(at: e3.start), Vec2(100, 0), 1e-9); close(e3.point(at: e3.end), Vec2(0, 50), 1e-9)
    }

    func testPolylineRectanglePolygonArea() async {
        let ed = Editor()
        await ed.run("PLINE 0,0 1000,0 1000,500 0,500 C")
        guard case .polyline(let p)? = last(ed) else { return XCTFail() }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 4)
        XCTAssertEqual(GeometryOps.area(.polyline(p), doc: nil) ?? 0, 500_000, accuracy: 1e-6)
        await ed.run("RECTANG 0,0 300,200")
        guard case .polyline(let r)? = last(ed) else { return XCTFail() }
        XCTAssertTrue(r.closed); XCTAssertEqual(r.vertices.count, 4)
        XCTAssertEqual(abs(GeometryOps.area(.polyline(r), doc: nil) ?? 0), 60_000, accuracy: 1e-6)
        await ed.run("POLYGON 6 0,0 I 100")
        guard case .polyline(let h)? = last(ed) else { return XCTFail() }
        XCTAssertTrue(h.closed); XCTAssertEqual(h.vertices.count, 6)
        XCTAssertEqual(abs(GeometryOps.area(.polyline(h), doc: nil) ?? 0), 3 * 3.0.squareRoot() / 2 * 100 * 100, accuracy: 1e-6)
        await ed.run("DONUT 50 100 0,0 ")
        guard case .polyline(let d)? = last(ed) else { return XCTFail() }
        XCTAssertEqual(d.width, 25, accuracy: 1e-12)
    }

    func testDivideAndMeasureWithBlocks() async {
        let ed = Editor()
        ed.doc.blocks["TICK"] = Block(name: "TICK", entities: [Entity(geometry: .line(LineGeom(Vec2(0, -5), Vec2(0, 5))))])
        let lid = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        await ed.run("DIVIDE #\(lid) 5")
        let pts = ed.doc.entities.compactMap { e -> Vec2? in if case .point(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(pts.map(\.x), [200, 400, 600, 800])
        await ed.run("DIVIDE #\(lid) B TICK Y 4")
        let ins = ed.doc.entities.compactMap { e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }
        XCTAssertEqual(ins.map(\.position.x), [250, 500, 750])
        let cid = ed.doc.add(.circle(CircleGeom(.zero, 100)))
        await ed.run("MEASURE #\(cid) B TICK Y \(2 * Double.pi * 100 / 8)")
        let ins2 = ed.doc.entities.compactMap { e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }
        XCTAssertEqual(ins2.count - ins.count, 7)
        for i in ins2.dropFirst(ins.count) { XCTAssertEqual(i.position.length, 100, accuracy: 1e-6) }
    }
}
