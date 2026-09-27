// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class GeometryConstraintTests: XCTestCase {
    func line(_ ed: Editor, _ id: EntityID) -> LineGeom { if case .line(let l)? = ed.doc.entity(id)?.geometry { return l }; return LineGeom(.zero, .zero) }

    func testHorizontalAndCoincidentAndDOF() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 30))))
        let b = ed.doc.add(.line(LineGeom(Vec2(1003, 32), Vec2(1100, 800))))
        await ed.run("GCHORIZONTAL 500,15 ")
        XCTAssertEqual(line(ed, a).a.y, line(ed, a).b.y, accuracy: 1e-7)
        await ed.run("GCCOINCIDENT 1000,15 1003,32 ")
        XCTAssertTrue(line(ed, a).b.isClose(line(ed, b).a, tol: 1e-6))
        await ed.run("GCVERTICAL 1050,400 ")
        XCTAssertEqual(line(ed, b).a.x, line(ed, b).b.x, accuracy: 1e-7)
        let f = Constraints.freedom(doc: ed.doc)
        XCTAssertEqual(f.parameters, 8)
        XCTAssertEqual(f.dof, 8 - 4)
        // Constraints persist in the document (file round trip).
        let data = try! JSONEncoder().encode(ed.doc)
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(ConstraintSet.load(back).constraints.count, 3)
    }

    func testParallelStaysSatisfiedWhenEndpointDragged() async {
        var doc = ArchiDocument()
        let a = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = doc.add(.line(LineGeom(Vec2(0, 500), Vec2(1000, 600))))
        var set = ConstraintSet()
        set.constraints = [GeoConstraint(id: 1, kind: .parallel, refs: [CRef(a), CRef(b)])]
        set.nextID = 2
        set.save(&doc)
        XCTAssertEqual(Constraints.solve(&doc, prefer: [a])?.converged, true)
        // Drag an endpoint of line a (grip edit), then the updater re-solves.
        let i = doc.entityIndex(a)!
        doc.entities[i].geometry = .line(LineGeom(Vec2(0, 0), Vec2(1000, 400)))
        DocumentUpdaters.run(&doc)
        guard case .line(let la) = doc.entity(a)!.geometry, case .line(let lb) = doc.entity(b)!.geometry else { return XCTFail() }
        XCTAssertTrue(la.b.isClose(Vec2(1000, 400), tol: 1e-3), "the dragged line keeps the new position")
        let u = (la.b - la.a).normalized, v = (lb.b - lb.a).normalized
        XCTAssertEqual(u.cross(v), 0, accuracy: 1e-8)
    }

    func testDimensionalConstraintsAndParameters() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let c = ed.doc.add(.circle(CircleGeom(Vec2(3000, 0), 200)))
        await ed.run("DCALIGNED O 500,0 1500 ")
        XCTAssertEqual(line(ed, a).a.distance(to: line(ed, a).b), 1500, accuracy: 1e-6)
        await ed.run("DCRADIUS 3200,0 d1/5 ")
        guard case .circle(let ci)? = ed.doc.entity(c)?.geometry else { return XCTFail() }
        XCTAssertEqual(ci.radius, 300, accuracy: 1e-6, "radius follows the expression d1/5")
        // Change d1 through the parameters manager: both update.
        await ed.run("PARAMETERS Edit d1 2000 ")
        XCTAssertEqual(line(ed, a).a.distance(to: line(ed, a).b), 2000, accuracy: 1e-6)
        guard case .circle(let ci2)? = ed.doc.entity(c)?.geometry else { return XCTFail() }
        XCTAssertEqual(ci2.radius, 400, accuracy: 1e-6)
        // User parameter.
        await ed.run("PARAMETERS New w 250 ")
        let set = ConstraintSet.load(ed.doc)
        XCTAssertEqual(Constraints.evaluate("w*2+d1", set: set, doc: ed.doc) ?? 0, 2500, accuracy: 1e-9)
    }

    func testAngleAndPerpendicular() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(700, 800))))
        await ed.run("GCFIX 0,0 ")
        await ed.run("DCANGULAR 500,0 350,400 30 ")
        let la = line(ed, a), lb = line(ed, b)
        XCTAssertEqual(deg(Constraints.angleBetween((la.a, la.b), (lb.a, lb.b))), 30, accuracy: 1e-6)
        XCTAssertTrue(la.a.isClose(.zero, tol: 1e-9), "fixed point stays")
        let ed2 = Editor()
        let p = ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let q = ed2.doc.add(.line(LineGeom(Vec2(500, -300), Vec2(600, 500))))
        await ed2.run("GCPERPENDICULAR 200,0 550,100 ")
        let l1 = line(ed2, p), l2 = line(ed2, q)
        XCTAssertEqual((l1.b - l1.a).normalized.dot((l2.b - l2.a).normalized), 0, accuracy: 1e-8)
        XCTAssertTrue(l1.b.isClose(Vec2(1000, 0), tol: 1e-9), "the first object picked stays put")
    }

    func testOverConstrainedIsReported() async {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 5))))
        await ed.run("GCHORIZONTAL 500,2 ")
        let log = await ed.run("GCHORIZONTAL 500,2 ")
        XCTAssertTrue(log.contains { $0.contains("over-constrain") }, "a redundant constraint is rejected: \(log)")
        XCTAssertEqual(ConstraintSet.load(ed.doc).constraints.count, 1)
        // Redundancy analysis on a hand-built set names the redundant constraint.
        var doc = ed.doc
        var set = ConstraintSet.load(doc)
        set.constraints.append(GeoConstraint(id: 99, kind: .horizontal, refs: [CRef(a)]))
        set.save(&doc)
        let rep = Constraints.solve(&doc)
        XCTAssertEqual(rep?.redundant, [99])
    }

    func testTangentConcentricEqualAndAutoConstrain() async {
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let c = ed.doc.add(.circle(CircleGeom(Vec2(500, 300), 250)))
        await ed.run("GCTANGENT 100,0 750,300 ")
        guard case .circle(let ci)? = ed.doc.entity(c)?.geometry else { return XCTFail() }
        let ln = line(ed, l)
        XCTAssertEqual(abs((ln.b - ln.a).normalized.cross(ci.center - ln.a)), ci.radius, accuracy: 1e-6)
        // AUTOCONSTRAIN: a nearly closed, nearly rectangular chain.
        let ed2 = Editor()
        let ids = [ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0.2)))), ed2.doc.add(.line(LineGeom(Vec2(1000, 0.2), Vec2(1000.1, 500)))),
                   ed2.doc.add(.line(LineGeom(Vec2(1000.1, 500), Vec2(0, 500)))), ed2.doc.add(.line(LineGeom(Vec2(0, 500), Vec2(0, 0))))]
        await ed2.run("AUTOCONSTRAIN ALL  ")
        let set = ConstraintSet.load(ed2.doc)
        XCTAssertGreaterThanOrEqual(set.constraints.filter { $0.kind == .coincident }.count, 3)
        XCTAssertEqual(set.constraints.filter { $0.kind == .horizontal || $0.kind == .vertical }.count, 4)
        for id in ids { let g = line(ed2, id); XCTAssertTrue(abs(g.a.x - g.b.x) < 1e-7 || abs(g.a.y - g.b.y) < 1e-7) }
        // Deleting constraints.
        await ed2.run("DELCONSTRAINT ALL  ")
        XCTAssertEqual(ConstraintSet.load(ed2.doc).constraints.count, 0)
    }

    func testObjectSnapTracking() async {
        var s = DraftSettings()
        s.polarTracking = false
        // Aligned vertically below an acquired point and horizontally with another: intersection of the two paths.
        let t = Snap.track(cursor: Vec2(101, 198), base: nil, points: [Vec2(100, 500), Vec2(-300, 200)], directions: [], settings: s, tolerance: 5)
        XCTAssertNotNil(t)
        XCTAssertTrue(t!.point.isClose(Vec2(100, 200), tol: 1e-9))
        XCTAssertEqual(t!.lines.count, 2)
        // Single path.
        let u = Snap.track(cursor: Vec2(102, 900), base: nil, points: [Vec2(100, 500)], directions: [], settings: s, tolerance: 5)
        XCTAssertTrue(u!.point.isClose(Vec2(100, 900), tol: 1e-9))
        XCTAssertNil(Snap.track(cursor: Vec2(150, 900), base: nil, points: [Vec2(100, 500)], directions: [], settings: s, tolerance: 5))
        // Parallel from the base point.
        let p = Snap.track(cursor: Vec2(1000, 1003), base: .zero, points: [], directions: [Vec2(1, 1).normalized], settings: s, tolerance: 5)
        XCTAssertEqual(p?.kind, .parallel)
        XCTAssertEqual(p!.point.x, p!.point.y, accuracy: 1e-9)
        // Settings saved by older builds still decode.
        let old = #"{"ortho":true,"gridSnap":false,"gridSpacing":50}"#.data(using: .utf8)!
        let d = try! JSONDecoder().decode(DraftSettings.self, from: old)
        XCTAssertTrue(d.ortho); XCTAssertEqual(d.gridSpacing, 50); XCTAssertTrue(d.objectSnapTracking)
    }

    func testNewModelFieldsThroughPropertyAccess() async {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let s = doc.addElement(.slab(SlabGeom(boundary: [.zero, Vec2(4000, 0), Vec2(4000, 1000), Vec2(0, 1000)])))
        let o = doc.addElement(.opening(OpeningGeom(kind: .opening, hostWall: w, offset: 1000, width: 800, height: 1000)))
        let r = doc.addElement(.space(SpaceGeom(boundary: [.zero, Vec2(10, 0), Vec2(10, 10)])))
        XCTAssertTrue(PropertyAccess.set("slope", "5", of: s, in: &doc))
        XCTAssertTrue(PropertyAccess.set("gradient", "1:12", of: s, in: &doc))
        if case .slab(let g)? = doc.element(s)?.geometry { XCTAssertEqual(tan(rad(g.slope)), 1.0 / 12, accuracy: 1e-12) }
        XCTAssertTrue(PropertyAccess.set("kind", "ramp", of: s, in: &doc))
        XCTAssertTrue(PropertyAccess.properties(of: s, in: doc).contains { $0.name == "rise" })
        XCTAssertTrue(PropertyAccess.set("depth", "150", of: o, in: &doc))
        XCTAssertTrue(PropertyAccess.set("mark", "N01", of: o, in: &doc))
        XCTAssertEqual(PropertyAccess.properties(of: o, in: doc).first { $0.name == "isNiche" }?.value, "true")
        XCTAssertTrue(PropertyAccess.set("phaseCreated", "Existing", of: w, in: &doc))
        XCTAssertTrue(PropertyAccess.set("phaseDemolished", "New Construction", of: w, in: &doc))
        XCTAssertFalse(PropertyAccess.set("phaseCreated", "Nonexistent", of: w, in: &doc))
        XCTAssertEqual(doc.element(w)?.props["phaseDemolished"], "New Construction")
        XCTAssertTrue(PropertyAccess.set("attachTop", "no", of: w, in: &doc))
        XCTAssertEqual(doc.element(w)?.props["attachTop"], "0")
        XCTAssertEqual(PropertyAccess.properties(of: w, in: doc).first { $0.name == "sweeps" }?.value, "0")
        XCTAssertTrue(PropertyAccess.set("tagX", "12.5", of: r, in: &doc))
        XCTAssertEqual(doc.element(r)?.props["tagX"], "12.5")
        XCTAssertTrue(PropertyAccess.set("tagX", "", of: r, in: &doc))
        XCTAssertNil(doc.element(r)?.props["tagX"])
        XCTAssertTrue(PropertyAccess.set("typeName", "Opening 1000x2100", of: o, in: &doc))
        if case .opening(let g)? = doc.element(o)?.geometry { XCTAssertEqual(g.width, 1000) }
    }

    func testConstraintInferenceWhileDrawing() async {
        let ed = Editor()
        await ed.run("CONSTRAINTINFER 1")
        await ed.run("LINE 0,0 1000,0 1000,500 ")
        let set = ConstraintSet.load(ed.doc)
        XCTAssertEqual(set.constraints.filter { $0.kind == .coincident }.count, 1)
        XCTAssertEqual(set.constraints.filter { $0.kind == .horizontal }.count, 1)
        XCTAssertEqual(set.constraints.filter { $0.kind == .vertical }.count, 1)
        // Moving the corner drags the other segment along (coincidence is kept).
        let ids = ed.doc.entities.map(\.id)
        ed.transaction("grip") { d in
            if let i = d.entityIndex(ids[0]), case .line(var l) = d.entities[i].geometry { l.b = Vec2(1200, 0); d.entities[i].geometry = .line(l) }
        }
        guard case .line(let l2)? = ed.doc.entity(ids[1])?.geometry else { return XCTFail() }
        XCTAssertTrue(l2.a.isClose(Vec2(1200, 0), tol: 1e-6))
        XCTAssertEqual(l2.a.x, l2.b.x, accuracy: 1e-7, "still vertical")
    }
}
