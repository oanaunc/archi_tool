// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// FILLET / CHAMFER / EXTEND on polylines, ellipse arcs and splines (MOD-037, MOD-041, MOD-042).
@MainActor
final class DraftModifyCurvesTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    /// The fillet arc is tangent to both results: its ends lie on them and the radius is perpendicular to their direction.
    /// Ellipses and splines are handled on their tessellation: tangency within about half a degree.
    func assertTangent(_ r: FilletResult, radius: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard case .arc(let a)? = r.arc else { return XCTFail("no fillet arc", file: file, line: line) }
        XCTAssertEqual(a.radius, radius, accuracy: 1e-6, file: file, line: line)
        let ends = [a.startPoint, a.endPoint]
        for g in [r.first, r.second] {
            let d = ends.map { GeometryOps.distance(from: $0, to: g, doc: nil) }.min() ?? .infinity
            XCTAssertLessThan(d, 1e-2 * max(1, radius), file: file, line: line)
            guard let e = ends.min(by: { GeometryOps.distance(from: $0, to: g, doc: nil) < GeometryOps.distance(from: $1, to: g, doc: nil) }),
                  let t = Modify.tangent(on: g, near: e, doc: nil) else { continue }
            XCTAssertLessThan(abs(t.normalized.dot((e - a.center).normalized)), 1e-2, "not tangent", file: file, line: line)
        }
    }

    func testFilletLineWithPolylineEndSegment() async {
        let pl = Geometry.polyline(PolylineGeom(points: [Vec2(0, 1000), Vec2(0, -200)]))
        let ln = Geometry.line(LineGeom(Vec2(-300, 0), Vec2(1000, 0)))
        guard let r = Modify.fillet(pl, pickA: Vec2(0, 500), ln, pickB: Vec2(500, 0), radius: 100) else { return XCTFail("no fillet") }
        guard case .polyline(let p) = r.first, case .line(let l) = r.second, case .arc(let a)? = r.arc else { return XCTFail() }
        close(p.vertices.first!.p, Vec2(0, 1000)); close(p.vertices.last!.p, Vec2(0, 100), 1e-6)
        close(l.a, Vec2(100, 0), 1e-6); close(l.b, Vec2(1000, 0))
        close(a.center, Vec2(100, 100), 1e-6)
        XCTAssertEqual(a.sweep, .pi / 2, accuracy: 1e-6)
        // Radius 0: a sharp corner.
        guard let s = Modify.fillet(pl, pickA: Vec2(0, 500), ln, pickB: Vec2(500, 0), radius: 0), case .polyline(let p0) = s.first, case .line(let l0) = s.second else { return XCTFail() }
        close(p0.vertices.last!.p, .zero, 1e-6); close(l0.a, .zero, 1e-6); XCTAssertNil(s.arc)
    }

    func testFilletWithSplineAndEllipse() async {
        let sp = Geometry.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: [Vec2(0, 600), Vec2(200, 400), Vec2(350, 150), Vec2(400, -100)]))
        let ln = Geometry.line(LineGeom(Vec2(-100, 0), Vec2(1000, 0)))
        guard let r = Modify.fillet(sp, pickA: Vec2(200, 400), ln, pickB: Vec2(800, 0), radius: 50) else { return XCTFail("no spline fillet") }
        assertTangent(r, radius: 50)
        guard case .line(let l) = r.second else { return XCTFail() }
        close(l.b, Vec2(1000, 0))
        XCTAssertGreaterThan(l.a.x, 300)
        // Half ellipse (upper) with a vertical line through its right end region.
        let el = Geometry.ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(500, 0), ratio: 0.5, start: 0, end: .pi))
        let v = Geometry.line(LineGeom(Vec2(300, -100), Vec2(300, 600)))
        guard let re = Modify.fillet(el, pickA: Vec2(-200, 230), v, pickB: Vec2(300, 500), radius: 40) else { return XCTFail("no ellipse fillet") }
        assertTangent(re, radius: 40)
        guard case .ellipse = re.first else { return XCTFail("ellipse kept its type") }
    }

    func testFilletCommandOnPolylineAndLine() async {
        let ed = Editor()
        await ed.run("PLINE 0,1000 0,-200 ")
        await ed.run("LINE -300,0 1000,0 ")
        await ed.run("FILLET R 100 0,500 500,0")
        let arcs = ed.doc.entities.compactMap { e -> ArcGeom? in if case .arc(let a) = e.geometry { return a }; return nil }
        XCTAssertEqual(arcs.count, 1)
        close(arcs.first?.center ?? .zero, Vec2(100, 100), 1e-6)
        ed.undo()
        XCTAssertTrue(ed.doc.entities.allSatisfy { if case .arc = $0.geometry { return false }; return true })
    }

    func testChamferLineWithPolylineEndSegment() async {
        let pl = Geometry.polyline(PolylineGeom(points: [Vec2(500, 1000), Vec2(0, 1000), Vec2(0, -200)]))
        let ln = Geometry.line(LineGeom(Vec2(-300, 0), Vec2(1000, 0)))
        guard let r = Modify.chamfer(pl, pickA: Vec2(0, 500), ln, pickB: Vec2(500, 0), d1: 100, d2: 200) else { return XCTFail("no chamfer") }
        guard case .polyline(let p) = r.first, case .line(let l) = r.second, case .line(let c)? = r.arc else { return XCTFail() }
        XCTAssertEqual(p.vertices.count, 3)
        close(p.vertices[1].p, Vec2(0, 1000)); close(p.vertices[2].p, Vec2(0, 100), 1e-9)
        close(l.a, Vec2(200, 0), 1e-9)
        close(c.a, Vec2(0, 100), 1e-9); close(c.b, Vec2(200, 0), 1e-9)
        // Picking the polyline's far segment (an arc or not an end) is refused cleanly.
        let closedPl = Geometry.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)], closed: true))
        XCTAssertNil(Modify.chamfer(closedPl, pickA: Vec2(5, 0), ln, pickB: Vec2(500, 0), d1: 1, d2: 1))
    }

    func testExtendSplinesAndRefusesCircles() async {
        let wall = Geometry.line(LineGeom(Vec2(400, -500), Vec2(400, 500)))
        let fit = Geometry.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: [Vec2(0, 0), Vec2(100, 50), Vec2(200, 0)]))
        guard case .spline(let s)? = Modify.extend(fit, at: Vec2(190, 5), boundaries: [wall], doc: nil) else { return XCTFail("no extend") }
        XCTAssertEqual(s.fitPoints.count, 4)
        XCTAssertEqual(s.fitPoints.last!.x, 400, accuracy: 1e-6)
        XCTAssertEqual(GeometryOps.distance(from: s.fitPoints.last!, to: wall, doc: nil), 0, accuracy: 1e-6)
        // Control-point spline: the new clamped end control point lies on the boundary.
        let cp = Geometry.spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 0), Vec2(50, 100), Vec2(150, 100), Vec2(200, 50)]))
        guard case .spline(let s2)? = Modify.extend(cp, at: Vec2(199, 50), boundaries: [wall], doc: nil), let path = CurvePath.make(.spline(s2)) else { return XCTFail() }
        XCTAssertEqual(path.end.x, 400, accuracy: 1e-6)
        XCTAssertNil(Modify.extend(.circle(CircleGeom(.zero, 10)), at: Vec2(10, 0), boundaries: [wall], doc: nil))
        // Lines, arcs, open polylines and ellipse arcs keep working.
        guard case .line(let l)? = Modify.extend(.line(LineGeom(.zero, Vec2(100, 0))), at: Vec2(90, 0), boundaries: [wall], doc: nil) else { return XCTFail() }
        close(l.b, Vec2(400, 0))
        guard case .polyline(let p)? = Modify.extend(.polyline(PolylineGeom(points: [Vec2(0, 100), Vec2(100, 100)])), at: Vec2(90, 100), boundaries: [wall], doc: nil) else { return XCTFail() }
        close(p.vertices.last!.p, Vec2(400, 100))
    }
}
