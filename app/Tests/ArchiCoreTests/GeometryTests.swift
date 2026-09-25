// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class GeometryTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(a.isClose(b, tol: tol), "\(a) != \(b)", file: file, line: line)
    }
    func line(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Geometry { .line(LineGeom(Vec2(ax, ay), Vec2(bx, by))) }
    func lineOf(_ g: Geometry?) -> LineGeom? { if case .line(let l)? = g { return l }; return nil }
    func arcOf(_ g: Geometry?) -> ArcGeom? { if case .arc(let a)? = g { return a }; return nil }
    func polyOf(_ g: Geometry?) -> PolylineGeom? { if case .polyline(let p)? = g { return p }; return nil }

    // MARK: Intersections

    func testLineLineIntersection() {
        let pts = Intersections.of(line(0, 0, 10, 10), line(0, 10, 10, 0), doc: nil)
        XCTAssertEqual(pts.count, 1); close(pts[0], Vec2(5, 5))
        XCTAssertTrue(Intersections.of(line(0, 0, 1, 0), line(5, -1, 5, 1), doc: nil).isEmpty)
        let ext = Intersections.of(line(0, 0, 1, 0), line(5, -1, 5, 1), doc: nil, extended: true)
        XCTAssertEqual(ext.count, 1); close(ext[0], Vec2(5, 0))
        XCTAssertTrue(Intersections.of(line(0, 0, 10, 0), line(0, 1, 10, 1), doc: nil).isEmpty)
    }

    func testCircleAndArcIntersections() {
        let c: Geometry = .circle(CircleGeom(.zero, 5))
        let pts = Intersections.of(line(-10, 3, 10, 3), c, doc: nil).sorted { $0.x < $1.x }
        XCTAssertEqual(pts.count, 2); close(pts[0], Vec2(-4, 3)); close(pts[1], Vec2(4, 3))
        // Tangent line.
        XCTAssertEqual(Intersections.of(line(-10, 5, 10, 5), c, doc: nil).count, 1)
        // Upper half arc only hits once with a line through the center at y = 3... both at y=3 are in the upper half.
        let arc: Geometry = .arc(ArcGeom(.zero, 5, 0, .pi))
        XCTAssertEqual(Intersections.of(line(-10, -3, 10, -3), arc, doc: nil).count, 0)
        XCTAssertEqual(Intersections.of(line(-10, -3, 10, -3), arc, doc: nil, extended: true).count, 2)
        let cc = Intersections.of(c, .circle(CircleGeom(Vec2(8, 0), 5)), doc: nil).sorted { $0.y < $1.y }
        XCTAssertEqual(cc.count, 2); close(cc[0], Vec2(4, -3)); close(cc[1], Vec2(4, 3))
        let aa = Intersections.of(arc, .arc(ArcGeom(Vec2(8, 0), 5, .pi / 2, .pi)), doc: nil)
        XCTAssertEqual(aa.count, 1); close(aa[0], Vec2(4, 3))
    }

    func testPolylineBulgeAndEllipseIntersections() {
        // Semicircle bulge from (0,0) to (10,0) (bulge -1 = clockwise → arc above? check both via count).
        let pl: Geometry = .polyline(PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 1), PolyVertex(Vec2(10, 0))]))
        let pts = Intersections.of(pl, line(5, -10, 5, 10), doc: nil)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(abs(pts[0].y), 5, accuracy: 1e-9)
        XCTAssertEqual(pts[0].y, -5, accuracy: 1e-9, "positive bulge = CCW from (0,0) to (10,0) passes below the chord")
        let e: Geometry = .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(10, 0), ratio: 0.5))
        let ep = Intersections.of(e, line(-20, 0, 20, 0), doc: nil).sorted { $0.x < $1.x }
        XCTAssertEqual(ep.count, 2); close(ep[0], Vec2(-10, 0), 1e-6); close(ep[1], Vec2(10, 0), 1e-6)
        let ep2 = Intersections.of(e, line(6, -20, 6, 20), doc: nil).sorted { $0.y < $1.y }
        XCTAssertEqual(ep2.count, 2); close(ep2[1], Vec2(6, 4), 1e-6)
    }

    // MARK: Trim / Extend

    func testTrimLineBetweenBoundaries() {
        let g = line(0, 0, 100, 0)
        let bounds = [line(30, -10, 30, 10), line(70, -10, 70, 10)]
        let r = Modify.trim(g, at: Vec2(50, 1), boundaries: bounds, doc: nil)!
        XCTAssertEqual(r.count, 2)
        close(lineOf(r[0])!.b, Vec2(30, 0)); close(lineOf(r[1])!.a, Vec2(70, 0))
        let r2 = Modify.trim(g, at: Vec2(10, 0), boundaries: bounds, doc: nil)!
        XCTAssertEqual(r2.count, 1); close(lineOf(r2[0])!.a, Vec2(30, 0)); close(lineOf(r2[0])!.b, Vec2(100, 0))
        XCTAssertNil(Modify.trim(g, at: Vec2(10, 0), boundaries: [line(0, 10, 100, 10)], doc: nil))
        // Boundary list containing the object itself is ignored for it.
        XCTAssertEqual(Modify.trim(g, at: Vec2(90, 0), boundaries: bounds + [g], doc: nil)?.count, 1)
    }

    func testTrimCircleAndPolyline() {
        let c: Geometry = .circle(CircleGeom(.zero, 10))
        let r = Modify.trim(c, at: Vec2(10, 0), boundaries: [line(0, -20, 0, 20)], doc: nil)!
        let a = arcOf(r.first)!
        close(a.startPoint, Vec2(0, 10)); close(a.endPoint, Vec2(0, -10)) // right half removed, left half kept
        XCTAssertEqual(a.sweep, .pi, accuracy: 1e-9)
        close(a.midPoint, Vec2(-10, 0))
        let pl: Geometry = .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)]))
        let t = Modify.trim(pl, at: Vec2(100, 80), boundaries: [line(90, 50, 110, 50)], doc: nil)!
        XCTAssertEqual(t.count, 1)
        let p = polyOf(t[0])!
        XCTAssertEqual(p.vertices.count, 3); close(p.vertices[2].p, Vec2(100, 50))
    }

    func testExtend() {
        let e = Modify.extend(line(0, 0, 50, 0), at: Vec2(45, 0), boundaries: [line(100, -10, 100, 10), line(200, -10, 200, 10)], doc: nil)
        close(lineOf(e)!.b, Vec2(100, 0)); close(lineOf(e)!.a, Vec2(0, 0))
        let s = Modify.extend(line(0, 0, 50, 0), at: Vec2(5, 0), boundaries: [line(-30, -10, -30, 10)], doc: nil)
        close(lineOf(s)!.a, Vec2(-30, 0))
        XCTAssertNil(Modify.extend(line(0, 0, 50, 0), at: Vec2(45, 0), boundaries: [line(-30, -10, -30, 10)], doc: nil))
        // Arc from 0° to 90° extended at its end to the x = -5 line: reaches 120°.
        let a = arcOf(Modify.extend(.arc(ArcGeom(.zero, 10, 0, .pi / 2)), at: Vec2(0, 10), boundaries: [line(-5, 0, -5, 20)], doc: nil))!
        close(a.endPoint, Vec2(-5, 10 * sin(rad(120))), 1e-9)
        let pl = polyOf(Modify.extend(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)])), at: Vec2(10, 9),
                                      boundaries: [line(0, 30, 20, 30)], doc: nil))!
        close(pl.vertices.last!.p, Vec2(10, 30))
    }

    // MARK: Offset

    func testOffsetBasics() {
        let o = lineOf(Modify.offset(line(0, 0, 10, 0), distance: 5, towards: Vec2(3, -1)))!
        close(o.a, Vec2(0, -5)); close(o.b, Vec2(10, -5))
        if case .circle(let c)? = Modify.offset(.circle(CircleGeom(.zero, 10)), distance: 3, towards: Vec2(1, 1)) { XCTAssertEqual(c.radius, 7, accuracy: 1e-12) } else { XCTFail() }
        XCTAssertNil(Modify.offset(.circle(CircleGeom(.zero, 2)), distance: 3, towards: Vec2(0.5, 0)))
        let a = arcOf(Modify.offset(.arc(ArcGeom(.zero, 10, 0, .pi)), distance: 2, towards: Vec2(0, 20)))!
        XCTAssertEqual(a.radius, 12, accuracy: 1e-12)
    }

    func testOffsetClosedPolylineOutwardAndInward() {
        let sq: Geometry = .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)], closed: true))
        let out = polyOf(Modify.offset(sq, distance: 10, towards: Vec2(200, 50)))!
        XCTAssertTrue(out.closed)
        XCTAssertEqual(out.vertices.count, 4)
        XCTAssertEqual(GeometryOps.area(.polyline(out), doc: nil)!, 120 * 120, accuracy: 1e-6)
        XCTAssertTrue(out.vertices.contains { $0.p.isClose(Vec2(-10, -10)) })
        let inn = polyOf(Modify.offset(sq, distance: 10, towards: Vec2(50, 50)))!
        XCTAssertEqual(GeometryOps.area(.polyline(inn), doc: nil)!, 80 * 80, accuracy: 1e-6)
        XCTAssertNil(Modify.offset(sq, distance: 60, towards: Vec2(50, 50)))
    }

    func testOffsetOpenPolylineWithBulge() {
        // L-shape, then a polyline with an arc segment.
        let l: Geometry = .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)]))
        let o = polyOf(Modify.offset(l, distance: 10, towards: Vec2(50, 50)))!
        XCTAssertEqual(o.vertices.count, 3)
        close(o.vertices[0].p, Vec2(0, 10)); close(o.vertices[1].p, Vec2(90, 10)); close(o.vertices[2].p, Vec2(90, 100))
        // Straight then a quarter arc (CCW) of radius 50 around (100,50): (0,0)->(100,0)->(150,50).
        let b: Geometry = .polyline(PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(100, 0), bulge: tan(.pi / 8)), PolyVertex(Vec2(150, 50))]))
        let ob = polyOf(Modify.offset(b, distance: 10, towards: Vec2(100, 20)))!
        XCTAssertEqual(ob.vertices.count, 3)
        close(ob.vertices[1].p, Vec2(100, 10)); close(ob.vertices[2].p, Vec2(140, 50))
        XCTAssertEqual(ob.vertices[1].bulge, tan(.pi / 8), accuracy: 1e-9)
        // Outward offset of an arc-bearing polyline has the larger radius.
        let ob2 = polyOf(Modify.offset(b, distance: 10, towards: Vec2(100, -20)))!
        close(ob2.vertices[2].p, Vec2(160, 50))
    }

    func testOffsetEllipseSampled() {
        let e: Geometry = .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(100, 0), ratio: 0.5))
        guard case .spline(let s)? = Modify.offset(e, distance: 10, towards: Vec2(200, 0)) else { return XCTFail() }
        XCTAssertTrue(s.closed)
        XCTAssertTrue(s.fitPoints.contains { $0.isClose(Vec2(110, 0), tol: 1e-6) })
    }

    // MARK: Fillet / Chamfer

    func testFilletLines() {
        let a = line(0, 0, 120, 0), b = line(100, -20, 100, 100)
        let r = Modify.fillet(a, pickA: Vec2(50, 0), b, pickB: Vec2(100, 50), radius: 10)!
        close(lineOf(r.first)!.a, Vec2(0, 0)); close(lineOf(r.first)!.b, Vec2(90, 0))
        close(lineOf(r.second)!.a, Vec2(100, 10)); close(lineOf(r.second)!.b, Vec2(100, 100))
        let arc = arcOf(r.arc)!
        close(arc.center, Vec2(90, 10)); XCTAssertEqual(arc.radius, 10, accuracy: 1e-9)
        XCTAssertEqual(arc.sweep, .pi / 2, accuracy: 1e-9)
        // Radius 0 joins non-touching lines into a corner.
        let z = Modify.fillet(line(0, 0, 80, 0), pickA: Vec2(10, 0), line(100, 20, 100, 100), pickB: Vec2(100, 90), radius: 0)!
        close(lineOf(z.first)!.b, Vec2(100, 0)); close(lineOf(z.second)!.a, Vec2(100, 0)); XCTAssertNil(z.arc)
    }

    func testFilletLineArc() {
        // Line y = 0 and a lower half arc centered (0, 30) radius 20; fillet radius 8 on the outside.
        let l = line(-100, 0, 100, 0)
        let a: Geometry = .arc(ArcGeom(Vec2(0, 30), 20, .pi, 2 * .pi))
        let r = Modify.fillet(l, pickA: Vec2(40, 0), a, pickB: Vec2(20, 30), radius: 8)!
        let arc = arcOf(r.arc)!
        XCTAssertEqual(arc.center.y, 8, accuracy: 1e-9)
        XCTAssertEqual(arc.center.distance(to: Vec2(0, 30)), 28, accuracy: 1e-9)
        XCTAssertGreaterThan(arc.center.x, 0)
        // Fillet arc end points lie on both curves.
        let pts = [arc.startPoint, arc.endPoint]
        XCTAssertTrue(pts.contains { abs($0.y) < 1e-9 })
        XCTAssertTrue(pts.contains { abs($0.distance(to: Vec2(0, 30)) - 20) < 1e-9 })
        XCTAssertNotNil(lineOf(r.first)); XCTAssertNotNil(arcOf(r.second))
    }

    func testChamferLinesAndPolylineCorner() {
        let r = Modify.chamfer(line(0, 0, 120, 0), pickA: Vec2(50, 0), line(100, -20, 100, 100), pickB: Vec2(100, 50), d1: 10, d2: 20)!
        close(lineOf(r.first)!.b, Vec2(90, 0)); close(lineOf(r.second)!.a, Vec2(100, 20))
        close(lineOf(r.arc)!.a, Vec2(90, 0)); close(lineOf(r.arc)!.b, Vec2(100, 20))
        let pl: Geometry = .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)]))
        let f = polyOf(Modify.fillet(pl, pickA: Vec2(50, 0), pl, pickB: Vec2(100, 50), radius: 10)?.first)!
        XCTAssertEqual(f.vertices.count, 4)
        close(f.vertices[1].p, Vec2(90, 0)); close(f.vertices[2].p, Vec2(100, 10))
        XCTAssertEqual(f.vertices[1].bulge, tan(.pi / 8), accuracy: 1e-9)
    }

    // MARK: Break / Join / Explode

    func testBreak() {
        let r = Modify.breakAt(line(0, 0, 100, 0), Vec2(30, 0), Vec2(60, 0))!
        XCTAssertEqual(r.count, 2); close(lineOf(r[0])!.b, Vec2(30, 0)); close(lineOf(r[1])!.a, Vec2(60, 0))
        let s = Modify.breakAt(line(0, 0, 100, 0), Vec2(40, 0), Vec2(40, 0))!
        XCTAssertEqual(s.count, 2)
        let c = Modify.breakAt(.circle(CircleGeom(.zero, 10)), Vec2(10, 0), Vec2(0, 10))!
        let a = arcOf(c.first)!
        close(a.startPoint, Vec2(0, 10)); close(a.endPoint, Vec2(10, 0)); XCTAssertEqual(a.sweep, 1.5 * .pi, accuracy: 1e-9)
        XCTAssertNil(Modify.breakAt(.circle(CircleGeom(.zero, 10)), Vec2(10, 0), Vec2(10, 0)))
    }

    func testJoin() {
        let j = Modify.join([line(0, 0, 10, 0), line(10, 10, 10, 0), line(10, 10, 0, 10)])
        XCTAssertEqual(j.count, 1)
        let p = polyOf(j[0])!
        XCTAssertEqual(p.vertices.count, 4); XCTAssertFalse(p.closed)
        let closed = Modify.join([line(0, 0, 10, 0), line(10, 0, 10, 10), line(10, 10, 0, 10), line(0, 10, 0, 0)])
        XCTAssertEqual(polyOf(closed.first)?.closed, true); XCTAssertEqual(polyOf(closed.first)?.vertices.count, 4)
        let col = Modify.join([line(0, 0, 10, 0), line(10, 0, 25, 0)])
        close(lineOf(col.first)!.a, Vec2(0, 0)); close(lineOf(col.first)!.b, Vec2(25, 0))
        let la = Modify.join([line(0, 0, 10, 0), .arc(ArcGeom(Vec2(10, 5), 5, -.pi / 2, .pi / 2))])
        let pa = polyOf(la.first)!
        XCTAssertEqual(pa.vertices.count, 3); XCTAssertEqual(pa.vertices[1].bulge, 1, accuracy: 1e-9)
        let arcs = Modify.join([.arc(ArcGeom(.zero, 5, 0, .pi)), .arc(ArcGeom(.zero, 5, .pi, 2 * .pi))])
        if case .circle? = arcs.first {} else { XCTFail("two half arcs join into a circle") }
        XCTAssertEqual(Modify.join([line(0, 0, 1, 0), line(5, 5, 6, 6)]).count, 2)
    }

    func testExplodePolylineAndInsert() {
        let pl: Geometry = .polyline(PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10, 0), bulge: 1), PolyVertex(Vec2(10, 10))]))
        let parts = Modify.explode(pl, doc: ArchiDocument())!
        XCTAssertEqual(parts.count, 2)
        XCTAssertNotNil(lineOf(parts[0]))
        let a = arcOf(parts[1])!
        close(a.center, Vec2(10, 5)); XCTAssertEqual(a.radius, 5, accuracy: 1e-9)
        var doc = ArchiDocument()
        doc.blocks["B"] = Block(name: "B", basePoint: Vec2(1, 0), entities: [Entity(geometry: line(1, 0, 2, 0))])
        let ex = Modify.explode(.insert(InsertGeom(block: "B", position: Vec2(100, 100), scale: Vec2(2, 2), rotation: .pi / 2)), doc: doc)!
        let l = lineOf(ex.first)!
        close(l.a, Vec2(100, 100)); close(l.b, Vec2(100, 102))
        XCTAssertNil(Modify.explode(line(0, 0, 1, 1), doc: doc))
    }

    // MARK: Divide / Measure / Lengthen / Reverse / Stretch

    func testDivideMeasure() {
        let d = Modify.divide(line(0, 0, 100, 0), count: 4, doc: nil)
        XCTAssertEqual(d.count, 3); close(d[0], Vec2(25, 0)); close(d[2], Vec2(75, 0))
        let c = Modify.divide(.circle(CircleGeom(.zero, 10)), count: 4, doc: nil)
        XCTAssertEqual(c.count, 4); close(c[1], Vec2(0, 10))
        let m = Modify.measure(line(0, 0, 100, 0), segmentLength: 30, doc: nil)
        XCTAssertEqual(m.count, 3); close(m[2], Vec2(90, 0))
        let pd = Modify.divide(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)])), count: 2, doc: nil)
        XCTAssertEqual(pd.count, 1); close(pd[0], Vec2(10, 0))
    }

    func testLengthenReverseStretch() {
        close(lineOf(Modify.lengthen(line(0, 0, 10, 0), at: Vec2(9, 0), delta: 5))!.b, Vec2(15, 0))
        close(lineOf(Modify.lengthen(line(0, 0, 10, 0), at: Vec2(1, 0), delta: -4))!.a, Vec2(4, 0))
        XCTAssertNil(Modify.lengthen(line(0, 0, 10, 0), at: Vec2(1, 0), delta: -20))
        let arc = arcOf(Modify.lengthen(.arc(ArcGeom(.zero, 10, 0, .pi / 2)), at: Vec2(0, 10), delta: 10 * .pi / 2))!
        XCTAssertEqual(arc.sweep, .pi, accuracy: 1e-9)
        let pl = PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 0.5), PolyVertex(Vec2(10, 0)), PolyVertex(Vec2(10, 10), bulge: -0.3)], closed: true)
        let r = polyOf(Modify.reverse(.polyline(pl)))!
        let rr = polyOf(Modify.reverse(.polyline(r)))!
        XCTAssertEqual(rr, pl)
        let pts = GeometryOps.polylinePoints(pl), rpts = GeometryOps.polylinePoints(r)
        XCTAssertEqual(GeometryOps.signedArea(pts), -GeometryOps.signedArea(rpts), accuracy: 1e-6)
        let st = lineOf(Modify.stretch(line(0, 0, 10, 0), window: BBox2(min: Vec2(8, -1), max: Vec2(12, 1)), by: Vec2(5, 0)))!
        close(st.a, Vec2(0, 0)); close(st.b, Vec2(15, 0))
    }

    func testClosestPoint() {
        close(Modify.closestPoint(on: .circle(CircleGeom(.zero, 10)), to: Vec2(20, 0), doc: nil)!, Vec2(10, 0))
        close(Modify.closestPoint(on: line(0, 0, 10, 0), to: Vec2(5, 5), doc: nil)!, Vec2(5, 0))
    }

    // MARK: Snaps

    func testObjectSnaps() {
        var doc = ArchiDocument()
        doc.add(line(0, 0, 100, 0))
        doc.add(line(50, -50, 50, 50))
        doc.add(.circle(CircleGeom(Vec2(200, 0), 20)))
        var s = DraftSettings()
        s.snapModes = [.endpoint, .midpoint, .center, .intersection, .perpendicular, .quadrant, .nearest]
        XCTAssertEqual(Snap.find(cursor: Vec2(98, 1), doc: doc, settings: s, tolerance: 5, base: nil)?.kind, .endpoint)
        let i = Snap.find(cursor: Vec2(51, 1), doc: doc, settings: s, tolerance: 5, base: nil)!
        XCTAssertEqual(i.kind, .intersection); close(i.point, Vec2(50, 0))
        doc.add(line(0, 100, 40, 100))
        let m = Snap.find(cursor: Vec2(22, 101), doc: doc, settings: s, tolerance: 5, base: nil)!
        XCTAssertEqual(m.kind, .midpoint); close(m.point, Vec2(20, 100))
        XCTAssertEqual(Snap.find(cursor: Vec2(201, 1), doc: doc, settings: s, tolerance: 5, base: nil)?.kind, .center)
        XCTAssertEqual(Snap.find(cursor: Vec2(219, 1), doc: doc, settings: s, tolerance: 5, base: nil)?.kind, .quadrant)
        let n = Snap.find(cursor: Vec2(80, 2), doc: doc, settings: s, tolerance: 5, base: nil)!
        XCTAssertEqual(n.kind, .nearest); close(n.point, Vec2(80, 0))
        let p = Snap.find(cursor: Vec2(72, 1), doc: doc, settings: s, tolerance: 5, base: Vec2(70, 40))!
        XCTAssertEqual(p.kind, .perpendicular); close(p.point, Vec2(70, 0))
        XCTAssertNil(Snap.find(cursor: Vec2(500, 500), doc: doc, settings: s, tolerance: 5, base: nil))
        // Hidden layers are skipped.
        doc.layers[0].visible = false
        XCTAssertNil(Snap.find(cursor: Vec2(98, 1), doc: doc, settings: s, tolerance: 5, base: nil))
    }

    func testTangentAndWallSnaps() {
        var doc = ArchiDocument()
        doc.add(.circle(CircleGeom(.zero, 10)))
        var s = DraftSettings(); s.snapModes = [.tangent]
        let base = Vec2(20, 0)
        let expected = Vec2(5, 10 * sin(acos(0.5)))
        let t = Snap.find(cursor: expected + Vec2(0.5, 0.5), doc: doc, settings: s, tolerance: 3, base: base)!
        XCTAssertEqual(t.kind, .tangent); close(t.point, expected, 1e-9)
        var d2 = ArchiDocument()
        d2.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(1000, 0), thickness: 200)))
        var s2 = DraftSettings(); s2.snapModes = [.endpoint, .midpoint]
        let w = Snap.find(cursor: Vec2(995, 96), doc: d2, settings: s2, tolerance: 20, base: nil)!
        XCTAssertEqual(w.kind, .endpoint); close(w.point, Vec2(1000, 100))
        d2.currentLevel = 1
        XCTAssertNil(Snap.find(cursor: Vec2(995, 96), doc: d2, settings: s2, tolerance: 20, base: nil))
    }

    func testGridSnapAndConstrain() {
        var s = DraftSettings()
        s.gridSnap = true; s.gridSpacing = 100; s.snapModes = []
        let g = Snap.find(cursor: Vec2(104, 196), doc: ArchiDocument(), settings: s, tolerance: 10, base: nil)!
        XCTAssertEqual(g.kind, .grid); close(g.point, Vec2(100, 200))
        var c = DraftSettings()
        c.ortho = true
        close(Snap.constrain(base: .zero, cursor: Vec2(100, 30), settings: c), Vec2(100, 0))
        close(Snap.constrain(base: .zero, cursor: Vec2(10, -90), settings: c), Vec2(0, -90))
        c.ortho = false; c.polarTracking = true; c.polarIncrement = 45
        let p = Snap.constrain(base: .zero, cursor: Vec2.polar(100, rad(46.5)), settings: c)
        XCTAssertEqual(deg(p.angle), 45, accuracy: 1e-9)
        close(Snap.constrain(base: .zero, cursor: Vec2.polar(100, rad(60)), settings: c), Vec2.polar(100, rad(60)))
        c.polarTracking = false; c.gridSnap = true; c.gridSpacing = 50
        close(Snap.constrain(base: .zero, cursor: Vec2(74, 26), settings: c), Vec2(50, 50))
    }
}
