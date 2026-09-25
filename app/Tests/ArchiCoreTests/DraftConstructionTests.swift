// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftConstructionTests: XCTestCase {
    func lines(_ ed: Editor) -> [LineGeom] { ed.doc.entities.compactMap { if case .line(let l) = $0.geometry { return l }; return nil } }
    func circles(_ ed: Editor) -> [CircleGeom] { ed.doc.entities.compactMap { if case .circle(let c) = $0.geometry { return c }; return nil } }
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }

    func testLineVariants() async {
        let ed = Editor()
        await ed.run("LINEANG 0,0 30 1000 ")
        close(lines(ed)[0].b, Vec2(1000 * cos(rad(30)), 1000 * sin(rad(30))))
        let ed2 = Editor()
        ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        await ed2.run("LINEREL 500,0 90 200,100 300 ")
        close(lines(ed2)[1].b, Vec2(200, 400))
        await ed2.run("LINEPAR 500,0 0,500 700 ")
        close(lines(ed2)[2].b, Vec2(700, 500))
        await ed2.run("LINEPERP 500,0 300,800 ")
        close(lines(ed2)[3].b, Vec2(300, 0))
        let ed3 = Editor()
        await ed3.run("LINEHV 0,0 500,37 V 480,300  ")
        XCTAssertEqual(lines(ed3).count, 2)
        close(lines(ed3)[0].b, Vec2(500, 0)); close(lines(ed3)[1].b, Vec2(500, 300))
        // Bisector of the x axis and the diagonal.
        let ed4 = Editor()
        ed4.doc.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        ed4.doc.add(.line(LineGeom(.zero, Vec2(1000, 1000))))
        await ed4.run("LINEBISECT 900,0 700,700 100 ")
        let b = lines(ed4)[2]
        close(b.a, .zero); XCTAssertEqual(deg(b.b.angle), 22.5, accuracy: 1e-9); XCTAssertEqual(b.b.length, 100, accuracy: 1e-9)
    }

    func testTangentLines() async {
        let ed = Editor()
        ed.doc.add(.circle(CircleGeom(.zero, 100)))
        await ed.run("LINETAN 0,200 86,50 ")
        let t = lines(ed)[0]
        XCTAssertEqual((t.b - .zero).dot(t.b - Vec2(0, 200)), 0, accuracy: 1e-6, "tangent is perpendicular to the radius")
        XCTAssertGreaterThan(t.b.x, 0)
        ed.doc.add(.circle(CircleGeom(Vec2(500, 0), 50)))
        await ed.run("LINETAN2 0,100 500,50 Outer")
        let o = lines(ed)[1]
        XCTAssertEqual(o.a.length, 100, accuracy: 1e-9); XCTAssertEqual(o.b.distance(to: Vec2(500, 0)), 50, accuracy: 1e-9)
        XCTAssertEqual((o.b - o.a).dot(o.a), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(o.a.y, 0)
        let inner = Construct.commonTangents(.zero, 100, Vec2(500, 0), 50, kind: .inner)
        XCTAssertEqual(inner.count, 2)
        for (p, q) in inner { XCTAssertEqual((q - p).dot(p), 0, accuracy: 1e-6); XCTAssertEqual((q - p).dot(q - Vec2(500, 0)), 0, accuracy: 1e-6) }
        // Orthogonal tangent: circle and a horizontal line below it.
        let ed2 = Editor()
        ed2.doc.add(.circle(CircleGeom(Vec2(0, 500), 100)))
        ed2.doc.add(.line(LineGeom(Vec2(-1000, 0), Vec2(1000, 0))))
        await ed2.run("LINETANORTHO 100,500 0,0 ")
        let g = lines(ed2)[1]
        close(g.a, Vec2(100, 500)); close(g.b, Vec2(100, 0))
    }

    func testApolloniusCircles() async {
        // Incircle of the 3-4-5 triangle: r = 1 at (1,1).
        let l1 = LineGeom(.zero, Vec2(4, 0)), l2 = LineGeom(.zero, Vec2(0, 3)), l3 = LineGeom(Vec2(4, 0), Vec2(0, 3))
        let ic = Construct.incircle(l1, l2, l3)!
        close(ic.center, Vec2(1, 1), 1e-12); XCTAssertEqual(ic.radius, 1, accuracy: 1e-12)
        let ed = Editor()
        for l in [l1, l2, l3] { ed.doc.add(.line(LineGeom(l.a * 100, l.b * 100))) }
        await ed.run("CIRCLETTT 200,0 0,150 200,150 ")
        guard let c = circles(ed).first else { return XCTFail("no TTT circle") }
        close(c.center, Vec2(100, 100), 1e-6); XCTAssertEqual(c.radius, 100, accuracy: 1e-6)
        await ed.run("INCIRCLE 200,0 0,150 200,150 ")
        XCTAssertEqual(circles(ed).count, 2)
        // Circle tangent to the x axis through two points.
        let sols = Construct.apollonius([.line(.zero, Vec2(10, 0)), .point(Vec2(0, 2)), .point(Vec2(2, 2))])
        XCTAssertFalse(sols.isEmpty)
        for s in sols { XCTAssertEqual(abs(s.center.y), s.radius, accuracy: 1e-8); XCTAssertEqual(s.center.distance(to: Vec2(0, 2)), s.radius, accuracy: 1e-8) }
        // Tangent to two circles through a point.
        let s2 = Construct.apollonius([.circle(.zero, 1), .circle(Vec2(6, 0), 1), .point(Vec2(3, 3))])
        XCTAssertTrue(s2.contains { abs($0.center.distance(to: .zero) - ($0.radius + 1)) < 1e-8 && abs($0.center.distance(to: Vec2(6, 0)) - ($0.radius + 1)) < 1e-8 })
        // Two points and radius, side chosen by a point.
        let c2 = Construct.circle2PR(.zero, Vec2(10, 0), radius: 13, side: Vec2(5, -100))!
        close(c2.center, Vec2(5, -12), 1e-9)
        await ed.run("ARCTOCIRCLE #\(ed.doc.add(.arc(ArcGeom(Vec2(9, 9), 5, 0, 1))))  ")
        XCTAssertTrue(circles(ed).contains { $0.center == Vec2(9, 9) && $0.radius == 5 })
    }

    func testArcsAndEllipses() async {
        let a = Construct.arcByHeight(.zero, Vec2(10, 0), height: 5)!
        close(a.center, Vec2(5, 0), 1e-9); XCTAssertEqual(a.radius, 5, accuracy: 1e-9)
        close(a.midPoint, Vec2(5, 5), 1e-9)
        let b = Construct.arcByLength(.zero, Vec2(10, 0), length: 5 * .pi, left: true)!
        XCTAssertEqual(b.radius * b.sweep, 5 * .pi, accuracy: 1e-8)
        close(b.center, Vec2(5, 0), 1e-6)
        XCTAssertNil(Construct.arcByLength(.zero, Vec2(10, 0), length: 9, left: true))
        // Foci: a=5, c=3 → b=4.
        let e = Construct.ellipseFoci(Vec2(-3, 0), Vec2(3, 0), through: Vec2(0, 4))!
        XCTAssertEqual(e.majorAxis.length, 5, accuracy: 1e-12); XCTAssertEqual(e.ratio, 0.8, accuracy: 1e-12)
        // Centre + 3 points of a rotated ellipse.
        let ref = EllipseGeom(center: Vec2(10, 20), majorAxis: Vec2.polar(8, rad(30)), ratio: 0.5)
        let e3 = Construct.ellipseCenter3(ref.center, [0.3, 1.9, 4.0].map { ref.point(at: $0) })!
        XCTAssertEqual(e3.majorAxis.length, 8, accuracy: 1e-9); XCTAssertEqual(e3.ratio, 0.5, accuracy: 1e-9)
        XCTAssertEqual(abs(e3.majorAxis.normalized.cross(ref.majorAxis.normalized)), 0, accuracy: 1e-9)
        // Four points, axis-aligned.
        let ref4 = EllipseGeom(center: Vec2(3, -2), majorAxis: Vec2(6, 0), ratio: 0.5)
        let e4 = Construct.ellipse4([0.2, 1.3, 2.9, 4.4].map { ref4.point(at: $0) })!
        close(e4.center, ref4.center, 1e-9); XCTAssertEqual(e4.majorAxis.length, 6, accuracy: 1e-9); XCTAssertEqual(e4.ratio, 0.5, accuracy: 1e-9)
        let ed = Editor()
        await ed.run("ARC2PH 0,0 1000,0 250 ")
        await ed.run("ELLIPSEFOCI -300,0 300,0 0,400 ")
        XCTAssertEqual(ed.doc.entities.count, 2)
    }

    func testPolygonPointsSnakeAndGDT() async {
        let hex = Construct.polygonSideSide(sides: 6, Vec2(0, -50), Vec2(0, 50))!
        XCTAssertEqual(hex.count, 6)
        let area = abs(GeometryOps.signedArea(hex))
        XCTAssertEqual(area, 2 * sqrt(3) * 50 * 50, accuracy: 1e-6, "regular hexagon with apothem 50")
        let tri = Construct.polygonSideSide(sides: 3, Vec2(0, 0), Vec2(0, 300))!
        XCTAssertTrue(tri.contains { $0.isClose(Vec2(0, 300), tol: 1e-9) }, "odd polygon: opposite vertex")
        let ed = Editor()
        await ed.run("POINTSLINE 0,0 1000,0 5")
        await ed.run("POINTLATTICE 0,500 3 2 100 200 0")
        let pts = ed.doc.entities.compactMap { e -> Vec2? in if case .point(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(pts.count, 11)
        XCTAssertTrue(pts.contains(Vec2(250, 0))); XCTAssertTrue(pts.contains(Vec2(200, 700)))
        let ed2 = Editor()
        await ed2.run("SNAKE 0,0 R500 U300 L500 Close")
        guard case .polyline(let pl)? = ed2.doc.entities.first?.geometry else { return XCTFail() }
        XCTAssertTrue(pl.closed); XCTAssertEqual(pl.vertices.map(\.p), [.zero, Vec2(500, 0), Vec2(500, 300), Vec2(0, 300)])
        let ed3 = Editor()
        await ed3.run("TOLERANCE Position %%c0.05 \"A B\" 0,0")
        XCTAssertEqual(ed3.doc.entities.filter { $0.props["gdt"] == "1" }.count, 8)
        XCTAssertTrue(ed3.doc.entities.contains { if case .text(let t) = $0.geometry { return t.content == "Ø0.05" }; return false })
    }

    func testModifyTools() async {
        // Break all: a cross becomes four lines.
        let ed = Editor()
        ed.doc.add(.line(LineGeom(Vec2(-100, 0), Vec2(100, 0)))); ed.doc.add(.line(LineGeom(Vec2(0, -100), Vec2(0, 100))))
        await ed.run("BREAKALL ALL  ")
        XCTAssertEqual(lines(ed).count, 4)
        // Line gap: the horizontal line gets a 20-wide gap at the crossing.
        let ed2 = Editor()
        let h = ed2.doc.add(.line(LineGeom(Vec2(-100, 0), Vec2(100, 0)))); ed2.doc.add(.line(LineGeom(Vec2(0, -100), Vec2(0, 100))))
        await ed2.run("LINEGAP #\(h)  20")
        let hs = lines(ed2).filter { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }
        XCTAssertEqual(hs.count, 2)
        XCTAssertEqual(hs.map { $0.a.distance(to: $0.b) }.reduce(0, +), 180, accuracy: 1e-6)
        // Clip: keep the part of a line inside a square.
        let ed3 = Editor()
        let sq = ed3.doc.add(.polyline(PolylineGeom(points: [.zero, Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)], closed: true)))
        let ln = ed3.doc.add(.line(LineGeom(Vec2(-50, 50), Vec2(150, 50))))
        await ed3.run("CLIPPOLY #\(sq) #\(ln)  Inside")
        let inside = lines(ed3)
        XCTAssertEqual(inside.count, 1); close(inside[0].a, Vec2(0, 50)); close(inside[0].b, Vec2(100, 50))
        // Weld: an L of two lines plus an arc → one polyline.
        let ed4 = Editor()
        ed4.doc.add(.line(LineGeom(.zero, Vec2(100, 0)))); ed4.doc.add(.line(LineGeom(Vec2(100, 0), Vec2(100, 100))))
        ed4.doc.add(.spline(SplineGeom(controlPoints: [], fitPoints: [Vec2(100, 100), Vec2(50, 150), Vec2(0, 100)])))
        await ed4.run("WELD ALL  0.01")
        XCTAssertEqual(ed4.doc.entities.count, 1)
        guard case .polyline(let w)? = ed4.doc.entities.first?.geometry else { return XCTFail() }
        close(w.vertices.first!.p, .zero); close(w.vertices.last!.p, Vec2(0, 100), 1e-6)
        // Conversions.
        let ed5 = Editor()
        let s = ed5.doc.add(.spline(SplineGeom(controlPoints: [], fitPoints: [.zero, Vec2(100, 50), Vec2(200, 0)])))
        await ed5.run("CONVERTTOPLINE #\(s)  0.5")
        guard case .polyline(let cp)? = ed5.doc.entity(s)?.geometry else { return XCTFail() }
        XCTAssertGreaterThan(cp.vertices.count, 4)
        await ed5.run("PLINETOSPLINE #\(s) ")
        if case .spline = ed5.doc.entity(s)!.geometry {} else { XCTFail("converted back to a spline") }
        // Extend by amount: line, ellipse arc.
        let ed6 = Editor()
        let l = ed6.doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        let el = ed6.doc.add(.ellipse(EllipseGeom(center: Vec2(0, 500), majorAxis: Vec2(200, 0), ratio: 0.5, start: 0, end: .pi / 2)))
        await ed6.run("EXTENDBY 50 95,0 ")
        close(lines(ed6)[0].b, Vec2(150, 0))
        let before = GeometryOps.length(ed6.doc.entity(el)!.geometry, doc: nil)
        let g = ModifyToolCommands.extendBy(ed6.doc.entity(el)!.geometry, at: Vec2(0, 600), delta: 30, doc: nil)!
        XCTAssertEqual(GeometryOps.length(g, doc: nil), before + 30, accuracy: 1e-6)
        let sp = Geometry.spline(SplineGeom(controlPoints: [], fitPoints: [.zero, Vec2(100, 30), Vec2(200, 0)]))
        let sg = ModifyToolCommands.extendBy(sp, at: Vec2(200, 0), delta: 40, doc: nil)!
        XCTAssertEqual(GeometryOps.length(sg, doc: nil), GeometryOps.length(sp, doc: nil) + 40, accuracy: 1e-5)
        // Cut by line and equidistant offsets.
        let ed7 = Editor()
        let c = ed7.doc.add(.circle(CircleGeom(.zero, 100)))
        await ed7.run("CUTBYLINE #\(c)  -200,0 200,0")
        XCTAssertEqual(ed7.doc.entities.count, 2)
        let ed8 = Editor()
        ed8.doc.add(.line(LineGeom(.zero, Vec2(1000, 0))))
        await ed8.run("OFFSETMULTI 500,0 100 3 500,50")
        XCTAssertEqual(lines(ed8).map { $0.a.y }.sorted(), [0, 100, 200, 300])
    }

    func testMoveRotateAndAlignRef() async {
        let ed = Editor()
        let id = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        await ed.run("MOVEROTATE #\(id)  0,0 500,500 90")
        close(lines(ed)[0].a, Vec2(500, 500)); close(lines(ed)[0].b, Vec2(500, 600))
        await ed.run("ROTATE2 #\(id)  500,500 -90 0,0 180")
        close(lines(ed)[0].a, Vec2(-500, -500)); close(lines(ed)[0].b, Vec2(-600, -500))
        let ed2 = Editor()
        let obj = ed2.doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        ed2.doc.add(.line(LineGeom(Vec2(1000, 0), Vec2(1000 + 300, 300))))
        await ed2.run("ALIGNREF #\(obj)  0,0 #\(obj) #\(obj + 1)")
        XCTAssertEqual(deg(lines(ed2)[0].b.angle), 45, accuracy: 1e-6)
    }

    func testIsolationVisibilityStatesMacrosAndHistory() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))))
        let b = ed.doc.add(.circle(CircleGeom(.zero, 50)))
        await ed.run("ISOLATEOBJECTS #\(a) ")
        XCTAssertEqual(ed.doc.entities.map(\.id), [a])
        let saved = try! JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(HiddenObjects.load(saved).entities.map(\.id), [b], "hidden objects persist in the file")
        await ed.run("UNISOLATEOBJECTS")
        XCTAssertEqual(Set(ed.doc.entities.map(\.id)), [a, b])
        await ed.run("HIDEOBJECTS #\(b) ")
        XCTAssertNil(ed.doc.entity(b))
        await ed.run("UNISOLATEOBJECTS")
        XCTAssertNotNil(ed.doc.entity(b))

        // Visibility states: a block with a door leaf (line) and a swing (arc).
        let ed2 = Editor()
        ed2.doc.blocks["DOOR"] = Block(name: "DOOR", entities: [Entity(geometry: .line(LineGeom(.zero, Vec2(0, 900)))),
                                                                  Entity(geometry: .arc(ArcGeom(.zero, 900, 0, .pi / 2)))])
        let ref = ed2.doc.add(.insert(InsertGeom(block: "DOOR", position: Vec2(1000, 0))))
        await ed2.run("BVSTATE 1000,450 New Closed")
        await ed2.run("BVSTATE 1000,450 Hide Closed 1636,636 ")
        guard case .insert(let ins)? = ed2.doc.entity(ref)?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.block, "DOOR$Closed")
        XCTAssertEqual(ed2.doc.blocks["DOOR$Closed"]?.entities.count, 1, "the swing is hidden in Closed")
        await ed2.run("BVSTATE 1000,450 Set Default")
        guard case .insert(let ins2)? = ed2.doc.entity(ref)?.geometry else { return XCTFail() }
        XCTAssertEqual(ed2.doc.blocks[ins2.block]?.entities.count, 2)
        XCTAssertEqual(BlockVisibility.states("DOOR", ed2.doc), ["Default", "Closed"])

        // Action macro.
        let ed3 = Editor()
        await ed3.run("ACTRECORD")
        await ed3.run("LINE 0,0 100,0 ")
        await ed3.run("CIRCLE 0,0 25")
        await ed3.run("ACTSTOP Two")
        XCTAssertEqual(ed3.doc.entities.count, 2)
        await ed3.run("ACTPLAY Two")
        await ed3.backgroundTask?.value
        XCTAssertEqual(ed3.doc.entities.count, 4)
        // History.
        XCTAssertEqual(ed3.historyEntry(back: 1, prefix: "ACT"), "ACTPLAY Two")
        XCTAssertEqual(ed3.historyEntry(back: 2, prefix: "LINE"), "LINE 0,0 100,0", "the macro's lines are in the history too")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-history-\(UUID().uuidString).txt")
        Editor.historyFile = url
        await ed3.run("REGEN")
        Editor.historyFile = nil
        XCTAssertEqual(CommandHistoryFile.load(url), ["REGEN"])
        try? FileManager.default.removeItem(at: url)
    }

    func testMleaderCollect() async {
        let ed = Editor()
        ed.doc.add(.leader(LeaderGeom(points: [.zero, Vec2(100, 100)], text: "A")))
        ed.doc.add(.leader(LeaderGeom(points: [Vec2(50, 0), Vec2(150, 60)], text: "B")))
        await ed.run("MLEADERCOLLECT ALL  Vertical 200,200")
        XCTAssertEqual(ed.doc.entities.count, 1)
        guard case .leader(let l)? = ed.doc.entities.first?.geometry else { return XCTFail() }
        XCTAssertEqual(l.text, "A\nB"); XCTAssertEqual(l.points.last, Vec2(200, 200))
    }
}
