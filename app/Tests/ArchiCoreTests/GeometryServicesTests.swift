// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// SYS-006: geometry services — tessellation, bounds, pick / crossing tests, area, length, centroid, transform and
/// grips for every drafting geometry kind.
final class GeometryServicesTests: XCTestCase {
    func close(_ a: Vec2?, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("nil point", file: file, line: line) }
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }

    var samples: [Geometry] {
        [.point(Vec2(5, 5)), .line(LineGeom(Vec2(0, 0), Vec2(100, 0))), .circle(CircleGeom(Vec2(0, 0), 50)),
         .arc(ArcGeom(Vec2(0, 0), 50, 0, .pi / 2)), .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(100, 0), ratio: 0.5)),
         .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 50)])),
         .spline(SplineGeom(controlPoints: [Vec2(0, 0), Vec2(30, 60), Vec2(60, -60), Vec2(100, 0)])),
         .text(TextGeom(position: Vec2(0, 0), height: 10, content: "ABC")),
         .hatch(HatchGeom(loops: [[PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10, 0)), PolyVertex(Vec2(10, 10)), PolyVertex(Vec2(0, 10))]])),
         .dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(100, 0), Vec2(50, 20)])),
         .leader(LeaderGeom(points: [Vec2(0, 0), Vec2(50, 50)], text: "x")),
         .image(ImageGeom(path: "/tmp/x.png", origin: Vec2(0, 0), size: Vec2(40, 30))),
         .table(TableGeom(origin: Vec2(0, 0), columnWidths: [20, 30], rowHeight: 8, cells: [["a", "b"], ["c", "d"]]))]
    }

    func testEveryKindTessellatesBoundsAndPicks() {
        for g in samples {
            let pl = GeometryOps.tessellate(g, doc: nil)
            XCTAssertFalse(pl.isEmpty, "tessellation of \(g)")
            let b = GeometryOps.bounds(g, doc: nil)
            XCTAssertFalse(b.isEmpty, "bounds of \(g)")
            for p in pl.joined() { XCTAssertTrue(p.x >= b.min.x - 1e-6 && p.x <= b.max.x + 1e-6 && p.y >= b.min.y - 1e-6 && p.y <= b.max.y + 1e-6) }
            // A point of the tessellation picks the object; a big crossing box around it crosses it; a far box does not.
            if case .dimension = g {} else if let p = pl.first?.first { XCTAssertLessThan(GeometryOps.distance(from: p, to: g, doc: nil), 1e-6, "pick \(g)") }
            var big = b; big.add(b.min - Vec2(1, 1)); big.add(b.max + Vec2(1, 1))
            XCTAssertTrue(GeometryOps.crosses(g, box: big, doc: nil), "crossing \(g)")
            XCTAssertFalse(GeometryOps.crosses(g, box: BBox2(min: Vec2(1e6, 1e6), max: Vec2(1e6 + 1, 1e6 + 1)), doc: nil))
            XCTAssertFalse(GeometryOps.grips(g).isEmpty && { if case .hatch = g { return false }; return true }(), "grips \(g)")
        }
    }

    func testExactLengths() {
        XCTAssertEqual(GeometryOps.length(.line(LineGeom(.zero, Vec2(3, 4))), doc: nil), 5, accuracy: 1e-12)
        XCTAssertEqual(GeometryOps.length(.circle(CircleGeom(.zero, 10)), doc: nil), 20 * .pi, accuracy: 1e-12)
        XCTAssertEqual(GeometryOps.length(.arc(ArcGeom(.zero, 10, 0, .pi)), doc: nil), 10 * .pi, accuracy: 1e-12)
        // Polyline with a semicircular bulge: 100 straight + π·50 arc, exactly.
        let pl = PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(100, 0), bulge: 1), PolyVertex(Vec2(100, 100))])
        XCTAssertEqual(GeometryOps.length(.polyline(pl), doc: nil), 100 + 50 * .pi, accuracy: 1e-9)
        // Ellipse: circle case is exact; a 2:1 ellipse matches the known perimeter 9.688448220547676·a/2 … (a=2,b=1).
        XCTAssertEqual(GeometryOps.length(.ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(5, 0), ratio: 1)), doc: nil), 10 * .pi, accuracy: 1e-9)
        XCTAssertEqual(GeometryOps.length(.ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(2, 0), ratio: 0.5)), doc: nil), 9.688448220547676, accuracy: 1e-6)
        // Quarter elliptical arc of a circle = quarter circumference.
        XCTAssertEqual(GeometryOps.ellipseLength(EllipseGeom(center: .zero, majorAxis: Vec2(4, 0), ratio: 1, start: 0, end: .pi / 2)), 2 * .pi, accuracy: 1e-9)
    }

    func testExactAreas() {
        XCTAssertEqual(GeometryOps.area(.circle(CircleGeom(.zero, 10)), doc: nil)!, 100 * .pi, accuracy: 1e-9)
        XCTAssertEqual(GeometryOps.area(.ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(10, 0), ratio: 0.5)), doc: nil)!, 50 * .pi, accuracy: 1e-9)
        // Two semicircular bulges make a full circle of radius 1.
        let disc = PolylineGeom([PolyVertex(Vec2(1, 0), bulge: 1), PolyVertex(Vec2(-1, 0), bulge: 1)], closed: true)
        XCTAssertEqual(GeometryOps.area(.polyline(disc), doc: nil)!, .pi, accuracy: 1e-12)
        // Square 10×10 with an inward semicircular bite on the right side (bulge negative on a CCW loop).
        let bite = PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10, 0), bulge: -1), PolyVertex(Vec2(10, 10)), PolyVertex(Vec2(0, 10))], closed: true)
        XCTAssertEqual(GeometryOps.area(.polyline(bite), doc: nil)!, 100 - .pi * 25 / 2, accuracy: 1e-9)
        // Clockwise loop gives the same absolute area.
        let cw = PolylineGeom(points: [Vec2(0, 0), Vec2(0, 10), Vec2(10, 10), Vec2(10, 0)], closed: true)
        XCTAssertEqual(GeometryOps.area(.polyline(cw), doc: nil)!, 100, accuracy: 1e-12)
        // Hatch with a hole.
        let sq = { (o: Double, s: Double) in [Vec2(o, o), Vec2(o + s, o), Vec2(o + s, o + s), Vec2(o, o + s)].map { PolyVertex($0) } }
        XCTAssertEqual(GeometryOps.area(.hatch(HatchGeom(loops: [sq(0, 10), sq(2, 4)])), doc: nil)!, 84, accuracy: 1e-12)
        // Two separate islands add up (floor patterns split by a wall).
        XCTAssertEqual(GeometryOps.area(.hatch(HatchGeom(loops: [sq(0, 10), sq(20, 10)])), doc: nil)!, 200, accuracy: 1e-12)
        // Island inside a hole counts again.
        XCTAssertEqual(GeometryOps.area(.hatch(HatchGeom(loops: [sq(0, 10), sq(2, 6), sq(4, 2)])), doc: nil)!, 100 - 36 + 4, accuracy: 1e-12)
        XCTAssertNil(GeometryOps.area(.line(LineGeom(.zero, Vec2(1, 1))), doc: nil))
    }

    func testCentroids() {
        close(GeometryOps.centroid(.circle(CircleGeom(Vec2(3, 4), 2)), doc: nil), Vec2(3, 4))
        close(GeometryOps.centroid(.line(LineGeom(Vec2(0, 0), Vec2(10, 0))), doc: nil), Vec2(5, 0))
        // Semicircular arc (curve) centroid: 2r/π from the centre.
        close(GeometryOps.centroid(.arc(ArcGeom(.zero, 10, 0, .pi)), doc: nil), Vec2(0, 20 / .pi), 1e-9)
        // L-shape region.
        let l = PolylineGeom(points: [Vec2(0, 0), Vec2(20, 0), Vec2(20, 10), Vec2(10, 10), Vec2(10, 20), Vec2(0, 20)], closed: true)
        close(GeometryOps.centroid(.polyline(l), doc: nil), Vec2(25.0 / 3, 25.0 / 3), 1e-9)
        // Hatch square with an off-centre hole shifts the centroid away from the hole.
        let sq = { (x: Double, y: Double, s: Double) in [Vec2(x, y), Vec2(x + s, y), Vec2(x + s, y + s), Vec2(x, y + s)].map { PolyVertex($0) } }
        let c = GeometryOps.centroid(.hatch(HatchGeom(loops: [sq(0, 0, 10), sq(6, 4, 2)])), doc: nil)!
        close(c, Vec2((500 - 4 * 7) / 96.0, (500 - 4 * 5) / 96.0), 1e-9)
        XCTAssertNil(GeometryOps.centroid(.hatch(HatchGeom(loops: [])), doc: nil))
    }

    func testTransformsPreserveMeasures() {
        let t = Transform2D.translation(Vec2(100, -50)) * Transform2D.rotation(0.7) * Transform2D.scale(2, 2)
        let pl = PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(10, 0), bulge: 0.4), PolyVertex(Vec2(10, 10)), PolyVertex(Vec2(0, 10))], closed: true)
        let g = Geometry.polyline(pl)
        let moved = GeometryOps.transform(g, t)
        XCTAssertEqual(GeometryOps.area(moved, doc: nil)!, 4 * GeometryOps.area(g, doc: nil)!, accuracy: 1e-9)
        XCTAssertEqual(GeometryOps.length(moved, doc: nil), 2 * GeometryOps.length(g, doc: nil), accuracy: 1e-9)
        close(GeometryOps.centroid(moved, doc: nil), t.apply(GeometryOps.centroid(g, doc: nil)!), 1e-9)
        // Mirroring flips bulges so the area stays the same.
        let m = GeometryOps.transform(g, Transform2D.mirror(Vec2(0, 0), Vec2(0, 1)))
        XCTAssertEqual(GeometryOps.area(m, doc: nil)!, GeometryOps.area(g, doc: nil)!, accuracy: 1e-9)
        // Grips follow the transform.
        let line = Geometry.line(LineGeom(Vec2(0, 0), Vec2(10, 0)))
        zip(GeometryOps.grips(GeometryOps.transform(line, t)), GeometryOps.grips(line).map(t.apply)).forEach { close($0, $1, 1e-9) }
    }

    func testStyledTextBoxUsesWidthFactorAndOblique() {
        var doc = ArchiDocument()
        doc.textStyles.append(TextStyle(name: "Wide", font: "Helvetica", widthFactor: 2, oblique: .pi / 12))
        let plain = TextGeom(position: .zero, height: 10, content: "ABCD")
        var wide = plain; wide.style = "Wide"
        let bp = BBox2(points: GeometryOps.tessellate(.text(plain), doc: doc).joined().map { $0 })
        let bw = BBox2(points: GeometryOps.tessellate(.text(wide), doc: doc).joined().map { $0 })
        XCTAssertEqual(bw.width, 2 * bp.width + 10 * tan(.pi / 12), accuracy: 1e-6)
        // Slant: the top edge is shifted by h·tan(oblique).
        let c = TextStyleFonts.boxCorners(wide, doc: doc)
        XCTAssertEqual(c[3].x - c[0].x, (c[3].y - c[0].y) * tan(.pi / 12), accuracy: 1e-9)
        // Picking inside the widened part hits only the wide text.
        let p = Vec2(bp.max.x + 5, 3)
        XCTAssertEqual(GeometryOps.distance(from: p, to: .text(wide), doc: doc), 0)
        XCTAssertGreaterThan(GeometryOps.distance(from: p, to: .text(plain), doc: doc), 0)
        let sh = TextStyleFonts.shape(wide, doc: doc)
        XCTAssertEqual(sh.glyphMatrix.a, 2); XCTAssertEqual(sh.glyphMatrix.c, tan(.pi / 12), accuracy: 1e-12)
        XCTAssertTrue(TextStyleFonts.shape(plain, doc: doc).isPlain)
        close(TextStyleFonts.place(Vec2(1, 1), text: wide, shape: sh), Vec2(2 + tan(.pi / 12), 1), 1e-12)
    }
}
