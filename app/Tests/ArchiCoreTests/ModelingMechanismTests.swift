// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Linkages and mechanism simulation (M3D-088): a slider-crank driven by its crank angle.
@MainActor
final class ModelingMechanismTests: XCTestCase {
    func sliderCrank(_ doc: inout ArchiDocument, coupler: Double) -> (g: EntityID, crank: EntityID, rod: EntityID) {
        let g = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let c = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        let r = doc.add(.line(LineGeom(Vec2(100, 0), Vec2(100 + coupler, 0))))
        var s = ConstraintSet()
        func add(_ k: ConstraintKind, _ refs: [CRef], value: Double? = nil, name: String? = nil, anchor: Vec2? = nil, reference: Bool = false) {
            s.constraints.append(GeoConstraint(id: s.nextID, kind: k, refs: refs, value: value, name: name, reference: reference, anchor: anchor)); s.nextID += 1
        }
        add(.fixed, [CRef(g, 0)], anchor: Vec2(0, 0)); add(.fixed, [CRef(g, 1)], anchor: Vec2(1000, 0))
        add(.fixed, [CRef(c, 0)], anchor: Vec2(0, 0))
        add(.length, [CRef(c, 0)], value: 100)
        add(.angle, [CRef(g, 0), CRef(c, 0)], value: 0, name: "crank")
        add(.coincident, [CRef(c, 1), CRef(r, 0)])
        add(.length, [CRef(r, 0)], value: coupler)
        add(.pointOnCurve, [CRef(r, 1), CRef(g, 0)])
        add(.horizontalDistance, [CRef(g, 0), CRef(r, 1)], name: "slide", reference: true)
        s.save(&doc)
        return (g, c, r)
    }

    func testSliderCrankFollowsKinematics() async {
        var doc = ArchiDocument()
        let (_, _, rod) = sliderCrank(&doc, coupler: 300)
        guard let r = Mechanisms.simulate(doc, driver: "crank", from: 0, to: 2 * .pi, steps: 72, trace: CRef(rod, 1), measure: ["slide"]) else { return XCTFail() }
        XCTAssertEqual(r.frames.count, 73)
        XCTAssertTrue(r.frames.allSatisfy(\.converged))
        for f in r.frames {
            let x = 100 * cos(f.value) + (300 * 300 - pow(100 * sin(f.value), 2)).squareRoot()
            XCTAssertEqual(f.point!.x, x, accuracy: 1e-4)
            XCTAssertEqual(f.point!.y, 0, accuracy: 1e-6)
            XCTAssertEqual(f.measures["slide"]!, x, accuracy: 1e-4)
        }
        // Stroke of the slider = 2 × crank radius.
        let xs = r.frames.compactMap { $0.point?.x }
        XCTAssertEqual(xs.max()! - xs.min()!, 200, accuracy: 1e-3)
    }

    func testLockUpIsReported() async {
        var doc = ArchiDocument()
        let (_, _, rod) = sliderCrank(&doc, coupler: 50)
        guard let r = Mechanisms.simulate(doc, driver: "crank", from: 0, to: .pi / 2, steps: 90, trace: CRef(rod, 1)) else { return XCTFail() }
        // The coupler (50) cannot reach the line once 100·sin θ > 50: θ > 30°.
        XCTAssertFalse(r.frames.last!.converged)
        let lastOK = r.frames.filter(\.converged).last!.value
        XCTAssertEqual(lastOK * 180 / .pi, 30, accuracy: 1.01)
    }

    func testMechanismCommandDrawsTrace() async {
        let ed = Editor()
        let (_, crank, _) = sliderCrank(&ed.doc, coupler: 300)
        let before = ed.doc.entity(crank)
        await ed.run("MECHANISM crank 0 360 36 #\(crank) 1 4 No")
        guard let t = ed.doc.entities.first(where: { $0.props["mechanismTrace"] == "crank" }), case .polyline(let pl) = t.geometry else { return XCTFail("no trace") }
        XCTAssertEqual(pl.vertices.count, 37)
        XCTAssertTrue(pl.vertices.allSatisfy { abs($0.p.distance(to: .zero) - 100) < 1e-4 })   // the crank pin moves on a circle
        XCTAssertGreaterThanOrEqual(ed.doc.entities.filter { $0.props["mechanismFrame"] != nil }.count, 4 * 3)
        XCTAssertEqual(ed.doc.entity(crank), before)   // the pose is restored
    }
}
