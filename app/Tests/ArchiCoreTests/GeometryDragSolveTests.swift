// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class GeometryDragSolveTests: XCTestCase {
    func line(_ doc: ArchiDocument, _ id: EntityID) -> LineGeom { if case .line(let l)? = doc.entity(id)?.geometry { return l }; return LineGeom(.zero, .zero) }
    func len(_ l: LineGeom) -> Double { l.a.distance(to: l.b) }

    func testRatioConstraintSolvesAndPersists() async throws {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 500), Vec2(700, 500))))
        await ed.run("DCRATIO 500,0 350,500 2")
        let set = ConstraintSet.load(ed.doc)
        guard let c = set.constraints.first(where: { $0.kind == .ratio }) else { return XCTFail("no ratio constraint") }
        XCTAssertEqual(len(line(ed.doc, a)), 2 * len(line(ed.doc, b)), accuracy: 1e-6)
        XCTAssertEqual(len(line(ed.doc, b)), 700, accuracy: 1e-6, "the reference line is held")
        XCTAssertEqual(Constraints.measure(c, doc: ed.doc) ?? 0, 2, accuracy: 1e-9)
        // Changing the reference length drives the ratio'd line after the edit.
        ed.transaction("grip") { d in d.entities[d.entityIndex(b)!].geometry = .line(LineGeom(Vec2(0, 500), Vec2(400, 500))) }
        XCTAssertEqual(len(line(ed.doc, a)), 800, accuracy: 1e-5)
        // Named value usable in parameters; round trip keeps the constraint.
        let data = try JSONEncoder().encode(ed.doc)
        let back = try JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(ConstraintSet.load(back).constraints.first?.kind, .ratio)
        await ed.run("PARAMETERS E \(c.name ?? "ratio1") 3")
        XCTAssertEqual(len(line(ed.doc, a)), 3 * len(line(ed.doc, b)), accuracy: 1e-5)
    }

    func testLengthDifferenceConstraint() {
        var doc = ArchiDocument()
        let a = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = doc.add(.line(LineGeom(Vec2(0, 500), Vec2(700, 500))))
        var set = ConstraintSet()
        set.constraints = [GeoConstraint(id: 1, kind: .lengthDifference, refs: [CRef(a), CRef(b)], value: 100)]
        set.save(&doc)
        XCTAssertEqual(Constraints.solve(&doc, prefer: [b])?.converged, true)
        XCTAssertEqual(len(line(doc, a)) - len(line(doc, b)), 100, accuracy: 1e-6)
        XCTAssertEqual(len(line(doc, b)), 700, accuracy: 1e-6)
    }

    func testDragSolveKeepsConstraintsAndUndo() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = ed.doc.add(.line(LineGeom(Vec2(1000, 0), Vec2(1000, 800))))
        var set = ConstraintSet()
        set.constraints = [GeoConstraint(id: 1, kind: .coincident, refs: [CRef(a, 1), CRef(b, 0)]),
                           GeoConstraint(id: 2, kind: .perpendicular, refs: [CRef(a), CRef(b)]),
                           GeoConstraint(id: 3, kind: .length, refs: [CRef(b)], value: 800, name: "d1"),
                           GeoConstraint(id: 4, kind: .fixed, refs: [CRef(a, 0)], anchor: Vec2(0, 0))]
        set.nextID = 5
        set.save(&ed.doc)
        let before = ed.doc
        // Grab the shared corner and drag it.
        XCTAssertEqual(ed.beginDragSolve(near: Vec2(1002, 1), tolerance: 10).map { $0.entity == a || $0.entity == b }, true)
        for k in 1...5 {
            let r = ed.dragSolve(point: Vec2(1000 + Double(k) * 40, Double(k) * 60))
            XCTAssertEqual(r?.converged, true)
            let la = line(ed.doc, a), lb = line(ed.doc, b)
            XCTAssertTrue(la.b.isClose(lb.a, tol: 1e-6))
            XCTAssertEqual((la.b - la.a).normalized.dot((lb.b - lb.a).normalized), 0, accuracy: 1e-7)
            XCTAssertEqual(len(lb), 800, accuracy: 1e-6)
            XCTAssertTrue(la.a.isClose(.zero, tol: 1e-6))
        }
        XCTAssertTrue(line(ed.doc, a).b.isClose(Vec2(1200, 300), tol: 1e-5), "the dragged corner follows the cursor")
        XCTAssertFalse(ed.history.canUndo, "no undo steps while dragging")
        ed.endDragSolve()
        XCTAssertEqual(ed.history.undoLabel, "Drag")
        ed.undo()
        XCTAssertEqual(ed.doc.entities, before.entities)
        // Cancel restores the drawing.
        _ = ed.beginDragSolve(ref: CRef(b, 1))
        ed.dragSolve(point: Vec2(0, 5000))
        ed.endDragSolve(commit: false)
        XCTAssertEqual(ed.doc.entities, before.entities)
    }

    func testDragSolveUnreachableStopsAtLimitAndFreeEntityFollows() {
        var doc = ArchiDocument()
        let a = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        var set = ConstraintSet()
        set.constraints = [GeoConstraint(id: 1, kind: .fixed, refs: [CRef(a, 0)], anchor: .zero),
                           GeoConstraint(id: 2, kind: .length, refs: [CRef(a)], value: 1000),
                           GeoConstraint(id: 3, kind: .horizontal, refs: [CRef(a)])]
        set.save(&doc)
        // The free end can only move on the circle of radius 1000 on the horizontal: pulling it up leaves it in place.
        let r = Constraints.dragSolve(&doc, ref: CRef(a, 1), to: Vec2(1000, 500))
        XCTAssertNotNil(r)
        XCTAssertEqual(len(line(doc, a)), 1000, accuracy: 1e-6)
        XCTAssertEqual(line(doc, a).b.y, 0, accuracy: 1e-6)
        // An unconstrained line end simply follows.
        let f = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(10, 10))))
        Constraints.dragSolve(&doc, ref: CRef(f, 1), to: Vec2(50, 60))
        XCTAssertTrue(line(doc, f).b.isClose(Vec2(50, 60)))
    }
}
