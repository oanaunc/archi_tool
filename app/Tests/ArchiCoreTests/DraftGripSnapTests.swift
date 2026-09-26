// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Pick filtering (SEL-001), snap overrides / GCEN / extension / radial grid arcs (PRC-019, PRC-004, PRC-009, BIM-006),
/// grip editing (SEL-032…038) and MTEXT codes for lists, columns and stacks (ANN-005/006/007).
@MainActor
final class DraftGripSnapTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func geom(_ ed: Editor, _ id: EntityID) -> Geometry? { ed.doc.entity(id)?.geometry }

    // MARK: SEL-001

    func testPickSelectsOnlyDisplayedUnlockedObjects() {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "Locked", locked: true))
        ed.doc.layers.append(Layer(name: "Off", visible: false))
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let locked = ed.doc.add(.line(LineGeom(Vec2(0, 100), Vec2(1000, 100))), layer: "Locked")
        let off = ed.doc.add(.line(LineGeom(Vec2(0, 200), Vec2(1000, 200))), layer: "Off")
        let other = ed.doc.add(.line(LineGeom(Vec2(0, 300), Vec2(1000, 300))))
        ed.doc.entities[ed.doc.entityIndex(other)!].props["level"] = "1"
        XCTAssertEqual(ed.pick(at: Vec2(500, 3), tolerance: 10), a)
        XCTAssertNil(ed.pick(at: Vec2(500, 102), tolerance: 10))
        XCTAssertNil(ed.pick(at: Vec2(500, 202), tolerance: 10))
        XCTAssertNil(ed.pick(at: Vec2(500, 302), tolerance: 10), "entity of another level is not displayed on this plan")
        XCTAssertEqual(Set(ed.select(in: BBox2(min: Vec2(-10, -10), max: Vec2(1010, 400)), crossing: false)), [a])
        XCTAssertEqual(ed.pickCandidates(at: Vec2(500, 150), tolerance: 200), [a])
        _ = locked; _ = off
        // Switching to level 1 makes the level-tagged line pickable.
        ed.doc.currentLevel = 1
        XCTAssertEqual(ed.pick(at: Vec2(500, 302), tolerance: 10), other)
        // Equal distance: the object drawn on top (later in draw order) wins.
        let ed2 = Editor()
        _ = ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let top = ed2.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        XCTAssertEqual(ed2.pick(at: Vec2(500, 1), tolerance: 10), top)
    }

    // MARK: Snaps

    func testSnapOverridesInScriptsAndCommandLine() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("CIRCLE 2000,0 300")
        await ed.run("LINE MID 480,5 500,500 ")
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l.a, Vec2(500, 0))
        await ed.run("LINE CEN 2290,8 END 995,3 ")
        guard case .line(let l2)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l2.a, Vec2(2000, 0)); close(l2.b, Vec2(1000, 0))
        // PER from the last point onto the first line; QUA on the circle; NON keeps the typed point.
        await ed.run("LINE 300,400 PER 700,3 ")
        guard case .line(let l3)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l3.b, Vec2(300, 0))
        await ed.run("LINE QUA 2003,297 NON 2003,297 ")
        guard case .line(let l4)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l4.a, Vec2(2000, 300)); close(l4.b, Vec2(2003, 297))
        // The override is one-shot: running snaps are back afterwards.
        XCTAssertNil(ed.snapOverrideModes)
        XCTAssertTrue(ed.settings.snapModes.contains(.endpoint))
        // Nothing to snap to: message and the point is asked again.
        let out = await ed.run("LINE MID 5000,5000 10,10 20,20 ")
        XCTAssertTrue(out.contains { $0.contains("No midpoint found") })
        guard case .line(let l5)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        close(l5.a, Vec2(10, 10))
        // A keyword with the same letters wins over the override (ARC's Center option).
        XCTAssertNil(InputParser.snapOverride("CEN", keywords: ["Center", "End"]))
        XCTAssertEqual(InputParser.snapOverride("_mid"), "MID")
    }

    func testGeometricCenterSnapAndOsnapCommand() async {
        let ed = Editor()
        await ed.run("PLINE 0,0 1000,0 1000,600 0,600 C")
        await ed.run("OSNAP END,GCEN")
        XCTAssertTrue(ed.settings.geometricCenterSnap)
        let r = Snap.find(cursor: Vec2(505, 296), doc: ed.doc, settings: ed.settings, tolerance: 10, base: nil)
        XCTAssertEqual(r?.kind, .center); close(r?.point ?? .zero, Vec2(500, 300))
        // An L-shaped outline: area centroid, not the vertex average.
        let l = PolylineGeom(points: [Vec2(0, 0), Vec2(200, 0), Vec2(200, 100), Vec2(100, 100), Vec2(100, 200), Vec2(0, 200)], closed: true)
        close(Snap.geometricCenter(l)!, Vec2(250.0 / 3, 250.0 / 3), 1e-9)
        // Bulged (semicircular) side: centroid of square + half disc.
        let arcPl = PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(1000, 0), bulge: 1), PolyVertex(Vec2(1000, 1000)), PolyVertex(Vec2(0, 1000))], closed: true)
        let gc = Snap.geometricCenter(arcPl)!
        let sq = 1e6, half = Double.pi * 500 * 500 / 2
        XCTAssertEqual(gc.x, (sq * 500 + half * (1000 + 4 * 500 / (3 * Double.pi))) / (sq + half), accuracy: 2)
        await ed.run("OSNAP GCEN")
        let s = ed.settings
        XCTAssertTrue(s.snapModes.isEmpty && s.geometricCenterSnap && s.objectSnap)
        // Settings persist (and older settings without the key decode with GCEN off).
        let data = try! JSONEncoder().encode(s)
        XCTAssertTrue(try! JSONDecoder().decode(DraftSettings.self, from: data).geometricCenterSnap)
        XCTAssertFalse(try! JSONDecoder().decode(DraftSettings.self, from: Data("{}".utf8)).geometricCenterSnap)
    }

    func testExtensionSnapAlongLinesAndArcs() {
        var doc = ArchiDocument()
        _ = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        _ = doc.add(.arc(ArcGeom(Vec2(0, 1000), 100, 0, .pi / 2)))
        var s = DraftSettings()
        s.snapModes = [.extension]; s.objectSnapTracking = false
        Snap.tracker.clear()
        // Far along the line's extension nothing is acquired yet.
        XCTAssertNil(Snap.find(cursor: Vec2(400, 3), doc: doc, settings: s, tolerance: 5, base: nil))
        // Hovering the endpoint acquires it; then the extension snaps anywhere along the line.
        _ = Snap.find(cursor: Vec2(101, 1), doc: doc, settings: s, tolerance: 5, base: nil)
        XCTAssertEqual(Snap.tracker.extensionCount, 1)
        let e = Snap.find(cursor: Vec2(400, 3), doc: doc, settings: s, tolerance: 5, base: nil)
        XCTAssertEqual(e?.kind, .extension); close(e?.point ?? .zero, Vec2(400, 0))
        // Arc: acquired at its end (0,1100), then along its circle past the end (angle 135°).
        _ = Snap.find(cursor: Vec2(1, 1101), doc: doc, settings: s, tolerance: 5, base: nil)
        XCTAssertEqual(Snap.tracker.extensionCount, 2)
        let q = Vec2(0, 1000) + Vec2.polar(102, 3 * .pi / 4)
        let a = Snap.find(cursor: q, doc: doc, settings: s, tolerance: 5, base: nil)
        XCTAssertEqual(a?.kind, .extension); close(a?.point ?? .zero, Vec2(0, 1000) + Vec2.polar(100, 3 * .pi / 4), 1e-9)
        Snap.tracker.clear()
        XCTAssertEqual(Snap.tracker.extensionCount, 0)
    }

    func testRadialGridArcsSnapAsTrueArcs() {
        var doc = ArchiDocument()
        // Quarter-circle arc grid of radius 5000 about the origin and a radial grid line along 45°.
        let b = tan(Double.pi / 2 / 4)
        _ = doc.addElement(.gridLine(GridLineGeom(start: Vec2(5000, 0), end: Vec2(0, 5000), label: "A", bulge: b)))
        _ = doc.addElement(.gridLine(GridLineGeom(start: .zero, end: Vec2.polar(8000, .pi / 4), label: "1")))
        var s = DraftSettings(); s.objectSnapTracking = false
        s.snapModes = [.midpoint]
        let mid = Vec2.polar(5000, .pi / 4)
        let m = Snap.find(cursor: mid + Vec2(3, -2), doc: doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(m?.kind, .midpoint); close(m?.point ?? .zero, mid, 1e-9)
        s.snapModes = [.intersection]
        let x = Snap.find(cursor: mid + Vec2(4, 4), doc: doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(x?.kind, .intersection); close(x?.point ?? .zero, mid, 1e-9)
        s.snapModes = [.nearest]
        let onArc = Vec2.polar(5000, 0.3)
        let n = Snap.find(cursor: onArc * 1.0005, doc: doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(n?.kind, .nearest); XCTAssertEqual(n?.point.length ?? 0, 5000, accuracy: 1e-6)
        s.snapModes = [.center]
        XCTAssertEqual(Snap.find(cursor: Vec2(2, 2), doc: doc, settings: s, tolerance: 10, base: nil)?.point.length ?? 99, 0, accuracy: 1e-6)
    }

    // MARK: Grips

    func testGripPointsAndStretch() {
        let ln = Geometry.line(LineGeom(Vec2(0, 0), Vec2(100, 0)))
        let gl = Grips.grips(ln)
        XCTAssertEqual(gl.map(\.kind), [.vertex, .midpoint, .vertex])
        guard case .line(let l1) = Grips.stretched(ln, grip: gl[2], to: Vec2(100, 50)) else { return XCTFail() }
        close(l1.a, .zero); close(l1.b, Vec2(100, 50))
        guard case .line(let l2) = Grips.stretched(ln, grip: gl[1], to: Vec2(50, 10)) else { return XCTFail() }
        close(l2.a, Vec2(0, 10)); close(l2.b, Vec2(100, 10))
        // Polyline: vertex grips plus segment midpoints; a straight segment's midpoint moves the segment.
        let pl = Geometry.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)]))
        let gp = Grips.grips(pl)
        XCTAssertEqual(gp.count, 5)
        let segMid = gp.first { $0.kind == .midpoint && $0.index == 0 }!
        close(segMid.point, Vec2(50, 0))
        guard case .polyline(let p1) = Grips.stretched(pl, grip: segMid, to: Vec2(50, -20)) else { return XCTFail() }
        close(p1.vertices[0].p, Vec2(0, -20)); close(p1.vertices[1].p, Vec2(100, -20)); close(p1.vertices[2].p, Vec2(100, 100))
        // Arc: the midpoint grip keeps both ends (three-point arc); the end grip keeps the other end and the midpoint.
        let arc = Geometry.arc(ArcGeom(.zero, 100, 0, .pi))
        let ga = Grips.grips(arc)
        guard case .arc(let a1) = Grips.stretched(arc, grip: ga[1], to: Vec2(0, 50)) else { return XCTFail() }
        close(a1.startPoint, Vec2(100, 0), 1e-9); close(a1.endPoint, Vec2(-100, 0), 1e-9); close(a1.midPoint, Vec2(0, 50), 1e-9)
        guard case .arc(let a2) = Grips.stretched(arc, grip: ga[0], to: Vec2(0, -100)) else { return XCTFail() }
        XCTAssertEqual(a2.radius, 100, accuracy: 1e-9)
        close(a2.center, .zero, 1e-9)
        XCTAssertEqual(a2.sweep, 3 * .pi / 2, accuracy: 1e-9)
        // Circle quadrant changes the radius.
        let c = Geometry.circle(CircleGeom(.zero, 10))
        guard case .circle(let c1) = Grips.stretched(c, grip: Grips.grips(c)[1], to: Vec2(0, 25)) else { return XCTFail() }
        XCTAssertEqual(c1.radius, 25)
    }

    func testGripsOnTextAndDimensions() {
        // Multiline text: insertion grip moves, width grip changes the wrap width.
        let t = Geometry.text(TextGeom(position: Vec2(0, 0), height: 10, content: "abc def", width: 200))
        let gt = Grips.grips(t)
        XCTAssertEqual(gt.map(\.kind), [.insertion, .textWidth])
        close(gt[1].point, Vec2(200, 0))
        guard case .text(let t1) = Grips.stretched(t, grip: gt[1], to: Vec2(350, 40)) else { return XCTFail() }
        XCTAssertEqual(t1.width, 350); close(t1.position, .zero)
        guard case .text(let t2) = Grips.stretched(t, grip: gt[0], to: Vec2(5, 5)) else { return XCTFail() }
        close(t2.position, Vec2(5, 5)); XCTAssertEqual(t2.width, 200)
        // Linear dimension: extension line origins and the dimension line/text location.
        let d = Geometry.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(500, 300)], rotation: 0))
        let gd = Grips.grips(d)
        XCTAssertEqual(gd.map(\.kind), [.dimOrigin, .dimOrigin, .dimText])
        guard case .dimension(let d1) = Grips.stretched(d, grip: gd[2], to: Vec2(700, 500)) else { return XCTFail() }
        close(d1.points[2], Vec2(700, 500))
        guard case .dimension(let d2) = Grips.stretched(d, grip: gd[1], to: Vec2(1200, 0)) else { return XCTFail() }
        XCTAssertEqual(DimensionRenderer.measurement(d2), 1200, accuracy: 1e-9)
        XCTAssertEqual(Grips.dimTextSlot(.angular), 3)
    }

    func testMultiFunctionalGrips() {
        let pl = Geometry.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)]))
        let g = Grips.grips(pl)
        let v1 = g.first { $0.kind == .vertex && $0.index == 1 }!, m0 = g.first { $0.kind == .midpoint && $0.index == 0 }!
        XCTAssertEqual(Grips.actions(pl, grip: v1), [.stretch, .addVertex, .removeVertex])
        XCTAssertEqual(Grips.actions(pl, grip: m0), [.stretch, .addVertex, .convertToArc])
        guard case .polyline(let r)? = Grips.apply(.removeVertex, pl, grip: v1, to: .zero) else { return XCTFail() }
        XCTAssertEqual(r.vertices.map(\.p), [Vec2(0, 0), Vec2(100, 100)])
        guard case .polyline(let a)? = Grips.apply(.addVertex, pl, grip: m0, to: Vec2(50, -30)) else { return XCTFail() }
        XCTAssertEqual(a.vertices.count, 4); close(a.vertices[1].p, Vec2(50, -30))
        guard case .polyline(let arc)? = Grips.apply(.convertToArc, pl, grip: m0, to: Vec2(50, -50)) else { return XCTFail() }
        XCTAssertEqual(arc.vertices[0].bulge, 1, accuracy: 1e-12)
        XCTAssertEqual(GeometryOps.length(.polyline(arc), doc: nil), .pi * 50 + 100, accuracy: 1)
        let arcMid = Grips.grips(.polyline(arc)).first { $0.kind == .midpoint && $0.index == 0 }!
        close(arcMid.point, Vec2(50, -50), 1e-9)
        XCTAssertEqual(Grips.actions(.polyline(arc), grip: arcMid).last, .convertToLine)
        guard case .polyline(let back)? = Grips.apply(.convertToLine, .polyline(arc), grip: arcMid, to: .zero) else { return XCTFail() }
        XCTAssertEqual(back.vertices[0].bulge, 0)
        // Stretching an arc segment's midpoint re-bulges it through the new point.
        guard case .polyline(let rb) = Grips.stretched(.polyline(arc), grip: arcMid, to: Vec2(50, -25)) else { return XCTFail() }
        close(CurvePiece.bulge(rb.vertices[0].p, rb.vertices[1].p, rb.vertices[0].bulge).point(0.5), Vec2(50, -25), 1e-9)
        // Adding a vertex on an arc segment keeps both halves on arcs through the new vertex.
        guard case .polyline(let split)? = Grips.apply(.addVertex, .polyline(arc), grip: arcMid, to: Vec2(50, -50)) else { return XCTFail() }
        XCTAssertEqual(split.vertices.count, 4)
        XCTAssertEqual(GeometryOps.length(.polyline(split), doc: nil), .pi * 50 + 100, accuracy: 1)
        // Lengthen a line endpoint along its direction; arc radius.
        let ln = Geometry.line(LineGeom(.zero, Vec2(100, 0)))
        guard case .line(let ll)? = Grips.apply(.lengthen, ln, grip: Grips.grips(ln)[2], to: Vec2(250, 40)) else { return XCTFail() }
        close(ll.b, Vec2(250, 0))
        let ar = Geometry.arc(ArcGeom(.zero, 100, 0, .pi / 2))
        guard case .arc(let rr)? = Grips.apply(.radius, ar, grip: Grips.grips(ar)[1], to: Vec2(0, 150)) else { return XCTFail() }
        XCTAssertEqual(rr.radius, 150); XCTAssertEqual(rr.end, .pi / 2)
    }

    func testEditorGripEditSnapsModesCopyTypedAndUndo() {
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        _ = ed.doc.add(.line(LineGeom(Vec2(2000, 500), Vec2(3000, 500))))
        ed.settings.polarTracking = false
        ed.pickTolerance = 10
        let end = ed.grips(of: a)![2]
        // Dragging near another line's endpoint snaps onto it.
        XCTAssertEqual(ed.gripEdit(a, grip: end, to: Vec2(2004, 497)), a)
        guard case .line(let l)? = geom(ed, a) else { return XCTFail() }
        close(l.b, Vec2(2000, 500))
        ed.undo()
        guard case .line(let lu)? = geom(ed, a) else { return XCTFail() }
        close(lu.b, Vec2(1000, 0))
        // Ortho while dragging (no snap nearby).
        ed.settings.ortho = true
        ed.gripEdit(a, grip: end, to: Vec2(1500, 37))
        guard case .line(let lo)? = geom(ed, a) else { return XCTFail() }
        close(lo.b, Vec2(1500, 0))
        ed.settings.ortho = false
        // Rotate mode about the start grip with Copy: the original stays.
        let start = ed.grips(of: a)![0]
        let n0 = ed.doc.entities.count
        let cp = ed.gripEdit(a, grip: start, to: Vec2(0, 700), mode: .rotate, copy: true, snap: false)!
        XCTAssertNotEqual(cp, a); XCTAssertEqual(ed.doc.entities.count, n0 + 1)
        guard case .line(let lr)? = geom(ed, cp) else { return XCTFail() }
        close(lr.a, .zero, 1e-9); close(lr.b, Vec2(0, 1500), 1e-9)
        // Mirror about the vertical line through the start grip; scale with a reference length.
        ed.gripEdit(cp, grip: ed.grips(of: cp)![0], to: Vec2(0, 10), mode: .mirror, snap: false)
        guard case .line(let lm)? = geom(ed, cp) else { return XCTFail() }
        close(lm.b, Vec2(0, 1500), 1e-9)
        ed.gripEdit(a, grip: start, to: Vec2(200, 0), mode: .scale, snap: false, reference: 100)
        guard case .line(let ls)? = geom(ed, a) else { return XCTFail() }
        close(ls.b, Vec2(3000, 0), 1e-9)
        XCTAssertEqual(GripMode.stretch.next, .move); XCTAssertEqual(GripMode.mirror.next, .stretch)
        // Hot-grip typed value: 500 toward the cursor / at an angle.
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        XCTAssertTrue(ed.gripTyped(b, grip: ed.grips(of: b)![2], distance: 500, toward: Vec2(100, 300)))
        guard case .line(let lt)? = geom(ed, b) else { return XCTFail() }
        close(lt.b, Vec2(100, 500))
        XCTAssertTrue(ed.gripTyped(b, grip: ed.grips(of: b)![2], distance: 100, angle: .pi))
        guard case .line(let lt2)? = geom(ed, b) else { return XCTFail() }
        close(lt2.b, Vec2(0, 500), 1e-9)
        // Multi-functional option through the editor; locked layers are not grip-editable.
        let p = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 5000), Vec2(1000, 5000)])))
        XCTAssertTrue(ed.gripAction(p, grip: ed.grips(of: p)!.first { $0.kind == .midpoint }!, action: .convertToArc, to: Vec2(500, 4500), snap: false))
        guard case .polyline(let pa)? = geom(ed, p) else { return XCTFail() }
        XCTAssertEqual(pa.vertices[0].bulge, 1, accuracy: 1e-12)
        ed.doc.layers.append(Layer(name: "L", locked: true))
        let locked = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 1))), layer: "L")
        XCTAssertNil(ed.gripEdit(locked, grip: ed.grips(of: locked)![0], to: Vec2(5, 5), snap: false))
    }

    func testArcAndBulgeHelpers() {
        let a = Grips.arc3(Vec2(100, 0), Vec2(0, 100), Vec2(-100, 0))!
        close(a.center, .zero, 1e-9); XCTAssertEqual(a.radius, 100, accuracy: 1e-9); XCTAssertEqual(a.start, 0, accuracy: 1e-12)
        let cw = Grips.arc3(Vec2(-100, 0), Vec2(0, 100), Vec2(100, 0))!
        XCTAssertEqual(cw.start, 0, accuracy: 1e-12); XCTAssertEqual(cw.end, .pi, accuracy: 1e-12)
        XCTAssertNil(Grips.arc3(.zero, Vec2(1, 1), Vec2(2, 2)))
        XCTAssertEqual(Grips.bulgeThrough(.zero, Vec2(500, -500), Vec2(1000, 0)), 1, accuracy: 1e-12)
        XCTAssertEqual(Grips.bulgeThrough(.zero, Vec2(500, 500), Vec2(1000, 0)), -1, accuracy: 1e-12)
        XCTAssertEqual(Grips.bulgeThrough(.zero, Vec2(500, 0), Vec2(1000, 0)), 0)
    }

    // MARK: MTEXT codes (ANN-005/006/007)

    func testMTextListAndStackEncoding() {
        let content = TextLists.apply("Walls\nDoors\nWindows", style: .number) + "\nNote " + TextStacks.autoStack("1/2 and 3#4") + " {x}\\y"
        let m = MTextCodes.encode(content)
        XCTAssertEqual(m, "{\\pxi-3,l3,t3;1.^IWalls\\P2.^IDoors\\P3.^IWindows}\\PNote \\S1/2; and \\S3#4; \\{x\\}\\\\y")
        XCTAssertEqual(MTextCodes.decode(m), content)
        // Bullets and a tolerance stack (DXF caret notation "^ ").
        let b = TextLists.apply("One\nTwo", style: .bullet) + "\n±\\S+0.1^-0.05;"
        let mb = MTextCodes.encode(b)
        XCTAssertTrue(mb.hasPrefix("{\\pxi-3,l3,t3;•^IOne\\P•^ITwo}\\P"))
        XCTAssertTrue(mb.hasSuffix("\\S+0.1^ -0.05;"))
        XCTAssertEqual(MTextCodes.decode(mb), b)
        // MTEXT written by other programs: formatting removed, lists with "1)" markers, Unicode bullets.
        let foreign = "{\\fArial|b1|i0|c0|p34;\\pxi-3,l3,t3;\\U+2022^IFirst\\P\\U+2022^ISecond}\\P\\pi0,l0,t0;\\H2.5x;Plain \\S1^ 2;\\Pa)^Ione"
        XCTAssertEqual(MTextCodes.decode(foreign), "• First\n• Second\nPlain \\S1^2;\na. one")
        // Escaped delimiters inside a stack.
        XCTAssertEqual(MTextCodes.decode("\\Sa\\/b/c;"), "\\Sa/b/c;")
        XCTAssertEqual(MTextCodes.encode("x^y\tz"), "x^ y^Iz")
        XCTAssertEqual(MTextCodes.decode("x^ y^Iz"), "x^y\tz")
    }

    func testMTextColumnsGroupsAndXData() {
        let t = TextGeom(position: .zero, height: 10, content: String(repeating: "word ", count: 60), width: 420)
        guard let c = MTextCodes.columns(spec: "2,20,0", text: t) else { return XCTFail("no columns") }
        XCTAssertEqual(c.kind, .static); XCTAssertEqual(c.count, 2)
        XCTAssertEqual(c.width, 200, accuracy: 1e-9); XCTAssertEqual(c.gutter, 20); XCTAssertEqual(c.totalWidth, 420, accuracy: 1e-9)
        let lay = DraftRendering.columnLayout(t, spec: "2,20,0", widthFactor: 1)!
        let rows = (lay.lines.map(\.row).max() ?? 0) + 1
        XCTAssertEqual(c.height, 10 + 15 * Double(rows - 1), accuracy: 1e-9)
        let g = MTextCodes.columnGroups(c)
        XCTAssertEqual(g.map(\.code), [75, 79, 76, 78, 48, 49, 46])
        XCTAssertEqual(MTextCodes.columns(fromGroups: [(code: 1, value: "text"), (code: 50, value: "30")] + g), c)
        XCTAssertEqual(MTextCodes.columns(fromGroups: [(code: 1, value: "text")] + MTextCodes.columnXData(c)), c)
        // Group 50 alone is a rotation (older files), not a column height.
        XCTAssertNil(MTextCodes.columns(fromGroups: [(code: 50, value: "30")]))
        let sp = MTextCodes.spec(c)!
        XCTAssertEqual(sp.prop, "2,20,0"); XCTAssertEqual(sp.width, 420, accuracy: 1e-9)
        // Dynamic columns with manual heights.
        let d = MTextCodes.Columns(kind: .dynamic, count: 3, width: 100, gutter: 10, height: 300, heights: [300, 250, 120])
        XCTAssertEqual(MTextCodes.columns(fromGroups: MTextCodes.columnGroups(d)), d)
        XCTAssertEqual(MTextCodes.columns(fromGroups: MTextCodes.columnXData(d)), d)
        XCTAssertEqual(MTextCodes.spec(d)?.prop, "3,10,300")
        let dyn = MTextCodes.columns(spec: "3,10,60", text: t)!
        XCTAssertEqual(dyn.kind, .dynamic); XCTAssertEqual(dyn.height, 60)
    }
}
