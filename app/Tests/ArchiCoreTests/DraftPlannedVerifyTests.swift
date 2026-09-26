// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Acceptance checks for drafting commands: construction lines (DRW-002/003), points (DRW-077), dimensions
/// (ANN-018…030), leaders (ANN-047/049), text (ANN-001/002), hatch and solid fill (ANN-062/064), blocks (BLK-002),
/// boundary / region (DRW-072/073), ortho / polar / snap / grid / running snaps (PRC-015, 020, 023, 024, 030, 031).
@MainActor
final class DraftPlannedVerifyTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func last(_ ed: Editor) -> Entity? { ed.doc.entities.last }
    func dim(_ ed: Editor, _ id: EntityID) -> DimensionGeom? { if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d }; return nil }

    // MARK: DRW-002 / DRW-003

    func testXlineRayConstructionLines() async {
        let ed = Editor()
        await ed.run("XLINE H 0,500 ")
        guard let h = last(ed), let hi = ConstructionLines.info(h) else { return XCTFail("no xline") }
        XCTAssertEqual(hi.kind, .xline); close(hi.base, Vec2(0, 500)); close(hi.direction, Vec2(1, 0))
        await ed.run("XLINE 0,0 1000,1000 0,1000 ")
        let two = ed.doc.entities.suffix(2).compactMap(ConstructionLines.info)
        XCTAssertEqual(two.count, 2)
        close(two[0].direction, Vec2(1, 1).normalized, 1e-12); close(two[1].direction, Vec2(0, 1), 1e-12)
        await ed.run("XLINE A 30 0,0 ")
        XCTAssertEqual(ConstructionLines.info(last(ed)!)!.direction.angle, .pi / 6, accuracy: 1e-12)
        await ed.run("XLINE B 0,0 1000,0 0,1000 ")
        XCTAssertEqual(ConstructionLines.info(last(ed)!)!.direction.angle, .pi / 4, accuracy: 1e-12)
        await ed.run("LINE 0,-2000 1000,-2000 ")
        await ed.run("XLINE O 200 500,-2000 500,-1000 ")
        guard let o = ConstructionLines.info(last(ed)!) else { return XCTFail("no offset xline") }
        XCTAssertEqual(o.base.y, -1800, accuracy: 1e-9); XCTAssertEqual(abs(o.direction.x), 1, accuracy: 1e-12)
        await ed.run("RAY 100,100 200,100 100,300 ")
        let rays = ed.doc.entities.suffix(2).compactMap(ConstructionLines.info)
        XCTAssertEqual(rays.map(\.kind), [.ray, .ray]); close(rays[0].base, Vec2(100, 100)); close(rays[1].direction, Vec2(0, 1))
        // Drawing extents ignore the far ends.
        let ext = GeometryOps.bounds(of: ed.doc)
        XCTAssertLessThan(ext.width, 3000); XCTAssertLessThan(ext.height, 3000)
        // Each XLINE command is one undo step.
        let n = ed.doc.entities.count
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, n - 2)
    }

    func testTrimTurnsXlineIntoRayAndRayIntoLine() async {
        let ed = Editor()
        await ed.run("XLINE H 0,0 ")
        let x = last(ed)!.id
        await ed.run("LINE 500,-500 500,500 ")
        await ed.run("TRIM 800,0 ")
        guard let r = ed.doc.entity(x), let ri = ConstructionLines.info(r) else { return XCTFail("xline lost") }
        XCTAssertEqual(ri.kind, .ray)
        close(ri.base, Vec2(500, 0), 1e-6); close(ri.direction, Vec2(-1, 0))
        await ed.run("LINE -500,-500 -500,500 ")
        await ed.run("TRIM -800,0 ")
        guard let l = ed.doc.entity(x), case .line(let lg) = l.geometry else { return XCTFail() }
        XCTAssertNil(l.props[ConstructionLines.prop])
        XCTAssertEqual(lg.a.distance(to: lg.b), 1000, accuracy: 1e-6)
    }

    // MARK: DRW-077

    func testPointsAndDivide() async {
        let ed = Editor()
        await ed.run("POINT 10,10 20,20 30,30 ")
        let pts = ed.doc.entities.compactMap { e -> Vec2? in if case .point(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(pts, [Vec2(10, 10), Vec2(20, 20), Vec2(30, 30)])
        await ed.run("PTYPE 3 5")
        XCTAssertEqual(ed.doc.variable("PDMODE"), "3")
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("DIVIDE 500,0 4")
        let divs = ed.doc.entities.compactMap { e -> Vec2? in if case .point(let p) = e.geometry, p.y == 0 { return p }; return nil }
        XCTAssertEqual(divs.map(\.x).sorted(), [250, 500, 750])
    }

    // MARK: Dimensions

    func testRadiusDiameterAngularArcOrdinateBaseline() async {
        let ed = Editor()
        await ed.run("CIRCLE 0,0 500")
        let c = last(ed)!.id
        await ed.run("DIMRADIUS 500,0 800,300")
        let r = last(ed)!.id
        XCTAssertEqual(dim(ed, r)?.kind, .radius)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, r)!), 500, accuracy: 1e-9)
        await ed.run("DIMDIAMETER 0,500 -300,800")
        let d = last(ed)!.id
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, d)!), 1000, accuracy: 1e-9)
        // Both follow the circle.
        ed.transaction("r") { doc in doc.entities[doc.entityIndex(c)!].geometry = .circle(CircleGeom(Vec2(100, 0), 700)) }
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, r)!), 700, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, d)!), 1400, accuracy: 1e-9)
        // Angular between two lines, associative.
        await ed.run("LINE 3000,0 5000,0 ")
        let l1 = last(ed)!.id
        await ed.run("LINE 3000,0 4000,1000 ")
        let l2 = last(ed)!.id
        await ed.run("DIMANGULAR 4500,0 3500,500 4200,300")
        let an = last(ed)!.id
        XCTAssertEqual(dim(ed, an)?.kind, .angular)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, an)!), .pi / 4, accuracy: 1e-9)
        ed.transaction("rot") { doc in doc.entities[doc.entityIndex(l2)!].geometry = .line(LineGeom(Vec2(3000, 0), Vec2(3000, 1000))) }
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, an)!), .pi / 2, accuracy: 1e-9)
        ed.transaction("mv") { doc in
            doc.entities[doc.entityIndex(l1)!].geometry = .line(LineGeom(Vec2(3000, 200), Vec2(5000, 200)))
            doc.entities[doc.entityIndex(l2)!].geometry = .line(LineGeom(Vec2(3000, 200), Vec2(3000, 1200)))
        }
        close(dim(ed, an)!.points[0], Vec2(3000, 200), 1e-6)
        // Arc length.
        await ed.run("ARC C 0,5000 1000,5000 A 90")
        await ed.run("DIMARC 707.1,5707.1 1500,6500")
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, last(ed)!.id)!), 1000 * .pi / 2, accuracy: 1e-6)
        // Ordinate X and Y from the origin.
        await ed.run("DIMORDINATE 1200,300 1200,900")
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, last(ed)!.id)!), 1200, accuracy: 1e-9)
        await ed.run("DIMORDINATE 1200,300 1800,300")
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, last(ed)!.id)!), 300, accuracy: 1e-9)
        // Baseline: all from the first origin, stacked.
        await ed.run("DIMLINEAR 0,-1000 1000,-1000 500,-1500")
        await ed.run("DIMBASELINE 2000,-1000 3000,-1000 ")
        let base = ed.doc.entities.suffix(2).compactMap { e -> DimensionGeom? in if case .dimension(let d) = e.geometry { return d }; return nil }
        XCTAssertEqual(base.map { DimensionRenderer.measurement($0) }, [2000, 3000])
        XCTAssertTrue(base.allSatisfy { $0.points[0] == Vec2(0, -1000) })
        XCTAssertLessThan(base[1].points[2].y, base[0].points[2].y)
    }

    func testSmartDimInfersType() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("CIRCLE 3000,0 400")
        await ed.run("ARC C 6000,0 6500,0 A 90")
        await ed.run("DIM 500,0 500,300 ")
        await ed.run("DIM 3400,0 3600,300 ")
        await ed.run("DIM 6353.6,353.6 6800,800 ")
        let ds = ed.doc.entities.compactMap { e -> DimensionGeom? in if case .dimension(let d) = e.geometry { return d }; return nil }
        XCTAssertEqual(ds.count, 3)
        XCTAssertEqual(ds.map(\.kind).map(\.rawValue).sorted(), ["diameter", "linear", "radius"].sorted())
        XCTAssertEqual(ds.map { (DimensionRenderer.measurement($0) * 1e6).rounded() / 1e6 }.sorted(), [500, 800, 1000])
    }

    // MARK: Leaders

    func testLeadersFollowTheirObjects() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        let l = last(ed)!.id
        await ed.run("LEADER 400,0 800,600 1200,600  Note")
        guard let ld = last(ed), case .leader(let g) = ld.geometry else { return XCTFail("no leader") }
        XCTAssertNotNil(ld.props[LeaderAssociation.prop])
        XCTAssertEqual(g.text, "Note")
        await ed.run("MOVE #\(l)  0,0 0,500")
        guard case .leader(let g2)? = ed.doc.entity(ld.id)?.geometry else { return XCTFail() }
        close(g2.points[0], Vec2(400, 500), 1e-6); close(g2.points[2], Vec2(1200, 1100), 1e-6)
        // A multileader on a circle's quadrant.
        await ed.run("CIRCLE 3000,0 200")
        let c = last(ed)!.id
        await ed.run("MLEADER 3200,0 3600,400 Door")
        let ml = last(ed)!.id
        XCTAssertNotNil(ed.doc.entity(ml)?.props[LeaderAssociation.prop])
        await ed.run("MOVE #\(c)  0,0 100,0")
        guard case .leader(let m2)? = ed.doc.entity(ml)?.geometry else { return XCTFail() }
        close(m2.points[0], Vec2(3300, 0), 1e-6)
        // Erasing the object keeps the leader and drops the link; free-standing leaders stay unattached.
        await ed.run("ERASE #\(c) ")
        XCTAssertNil(ed.doc.entity(ml)?.props[LeaderAssociation.prop])
        await ed.run("LEADER 9000,9000 9500,9500  Free")
        XCTAssertNil(last(ed)?.props[LeaderAssociation.prop])
    }

    // MARK: Text

    func testSingleAndMultilineText() async {
        let ed = Editor()
        await ed.run("TEXT J MC 500,500 250 30 Hello world")
        guard case .text(let t)? = last(ed)?.geometry else { return XCTFail("no text") }
        XCTAssertEqual(t.content, "Hello world"); XCTAssertEqual(t.height, 250); XCTAssertEqual(t.rotation, .pi / 6, accuracy: 1e-12)
        XCTAssertEqual(t.halign, .center); XCTAssertEqual(t.valign, .middle)
        await ed.run("MTEXT 0,0 3000,-1000 First paragraph that is long enough to wrap")
        guard case .text(let m)? = last(ed)?.geometry else { return XCTFail("no mtext") }
        XCTAssertEqual(m.width, 3000, accuracy: 1e-9)
        XCTAssertGreaterThan(DrawListBuilder.wrapLines(m.content, height: m.height, width: 1500, widthFactor: 1).count, 1)
    }

    // MARK: Hatch / fill

    func testHatchAndSolidFillAreas() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 2000,1000")
        await ed.run("CIRCLE 1000,500 200")
        await ed.run("HATCH P SOLID 300,300 ")
        guard case .hatch(let h)? = last(ed)?.geometry else { return XCTFail("no hatch") }
        XCTAssertEqual(h.pattern.uppercased(), "SOLID")
        XCTAssertEqual(GeometryOps.area(.hatch(h), doc: nil) ?? 0, 2e6 - .pi * 200 * 200, accuracy: 2000)
        await ed.run("HATCH P ANSI31 1000,500 ")
        guard case .hatch(let h2)? = last(ed)?.geometry else { return XCTFail("no island hatch") }
        XCTAssertEqual(GeometryOps.area(.hatch(h2), doc: nil) ?? 0, .pi * 200 * 200, accuracy: 2000)
    }

    // MARK: Blocks

    func testInsertWithScaleRotationAndExplode() async {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        await ed.run("BLOCK B1 0,0 ALL ")
        XCTAssertNotNil(ed.doc.blocks["B1"])
        await ed.run("INSERT B1 1000,1000 2 2 90")
        guard case .insert(let i)? = last(ed)?.geometry else { return XCTFail("no insert") }
        XCTAssertEqual(i.scale, Vec2(2, 2)); XCTAssertEqual(i.rotation, .pi / 2, accuracy: 1e-12)
        await ed.run("EXPLODE #\(last(ed)!.id) ")
        guard case .line(let l)? = last(ed)?.geometry else { return XCTFail("not exploded") }
        close(l.a, Vec2(1000, 1000), 1e-9); close(l.b, Vec2(1000, 1200), 1e-9)
    }

    // MARK: Boundary / region

    func testBoundaryAndRegionFromLines() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 1000,1000 0,1000 C")
        await ed.run("BOUNDARY 500,500 ")
        guard case .polyline(let p)? = last(ed)?.geometry else { return XCTFail("no boundary") }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 4)
        XCTAssertEqual(GeometryOps.area(.polyline(p), doc: nil) ?? 0, 1e6, accuracy: 1e-6)
        let ed2 = Editor()
        await ed2.run("LINE 0,0 1000,0 1000,1000 0,1000 C")
        await ed2.run("REGION ALL ")
        let polys = ed2.doc.entities.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(polys.count, 1)
        XCTAssertEqual(GeometryOps.area(.polyline(polys[0]), doc: nil) ?? 0, 1e6, accuracy: 1e-6)
    }

    // MARK: Precision settings

    func testOrthoPolarSnapGridAndRunningSnaps() async {
        let ed = Editor()
        await ed.run("ORTHO ON")
        XCTAssertTrue(ed.settings.ortho)
        close(Snap.constrain(base: .zero, cursor: Vec2(1000, 37), settings: ed.settings), Vec2(1000, 0))
        close(Snap.constrain(base: .zero, cursor: Vec2(37, -900), settings: ed.settings), Vec2(0, -900))
        await ed.run("ORTHO OFF")
        await ed.run("SETVAR POLARANG 30")
        ed.settings.polarTracking = true
        let p = Snap.constrain(base: .zero, cursor: Vec2.polar(1000, .pi / 6 + 0.02), settings: ed.settings)
        XCTAssertEqual(p.angle, .pi / 6, accuracy: 1e-12)
        await ed.run("SNAP 250")
        await ed.run("SNAP ON")
        XCTAssertTrue(ed.settings.gridSnap); XCTAssertEqual(ed.settings.gridSpacing, 250)
        ed.settings.polarTracking = false
        close(Snap.constrain(base: .zero, cursor: Vec2(630, 380), settings: ed.settings), Vec2(750, 500))
        await ed.run("GRIDDISPLAY 500")
        XCTAssertTrue(ed.settings.showGrid)
        await ed.run("OSNAP END,MID,CEN")
        XCTAssertEqual(ed.settings.snapModes, [.endpoint, .midpoint, .center])
        XCTAssertEqual(SystemVariables.osmode(ed.settings), 7)
        await ed.run("SETVAR OSMODE 4133")
        XCTAssertEqual(ed.settings.snapModes, [.endpoint, .center, .intersection, .extension])
        // Typed ortho direct distance: "LINE 0,0 1000" along the cursor with ortho on.
        ed.settings.gridSnap = false
        await ed.run("ORTHO ON")
        ed.cursor = Vec2(500, 40)
        await ed.run("LINE 0,0 1000 ")
        guard case .line(let l)? = last(ed)?.geometry else { return XCTFail() }
        close(l.b, Vec2(1000, 0))
    }

    // MARK: PRC-035, MOD-064, SEL-007, DRW-064, DRW-056

    func testNamedUCSManager() async {
        let ed = Editor()
        await ed.run("UCS 1000,0 1000,1000")
        await ed.run("UCSMAN S EAST ")
        await ed.run("UCS W")
        await ed.run("UCSMAN R EAST NORTH ")
        XCTAssertNil(ed.doc.variable("UCS:EAST")); XCTAssertNotNil(ed.doc.variable("UCS:NORTH"))
        await ed.run("UCSMAN NORTH")
        let f = UCSFrame.current(ed.doc)
        close(f.origin, Vec2(1000, 0)); XCTAssertEqual(deg(f.angle), 90, accuracy: 1e-9)
        // Coordinate input follows the restored UCS.
        await ed.run("LINE 0,0 100,0 ")
        guard case .line(let l)? = last(ed)?.geometry else { return XCTFail() }
        close(l.b, Vec2(1000, 100), 1e-9)
        await ed.run("UCSMAN W")
        XCTAssertTrue(UCSFrame.current(ed.doc).isWorld)
        await ed.run("UCSMAN P")
        close(UCSFrame.current(ed.doc).origin, Vec2(1000, 0))
        await ed.run("UCSMAN D NORTH ")
        XCTAssertNil(ed.doc.variable("UCS:NORTH"))
        await ed.run("UCS V")
        XCTAssertEqual(UCSFrame.current(ed.doc).angle, 0, accuracy: 1e-12)
    }

    func testMatchPropertiesSettingsApplyOnlyChosen() async {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "A-WALL"))
        let src = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "A-WALL", color: .aci(1))
        ed.doc.entities[ed.doc.entityIndex(src)!].lineweight = 0.5
        let dst = ed.doc.add(.line(LineGeom(Vec2(0, 500), Vec2(100, 500))))
        await ed.run("MATCHPROP S Color #\(src) #\(dst) ")
        guard let d = ed.doc.entity(dst) else { return XCTFail() }
        XCTAssertEqual(d.color, .aci(1)); XCTAssertEqual(d.layer, "0"); XCTAssertNil(d.lineweight)
        guard case .line(let g) = d.geometry else { return XCTFail() }
        close(g.a, Vec2(0, 500))
        await ed.run("MATCHPROP S All #\(src) #\(dst) ")
        XCTAssertEqual(ed.doc.entity(dst)?.layer, "A-WALL"); XCTAssertEqual(ed.doc.entity(dst)?.lineweight, 0.5)
    }

    func testLassoSelectionDirection() {
        let ed = Editor()
        let inside = ed.doc.add(.line(LineGeom(Vec2(10, 10), Vec2(20, 20))))
        let crossing = ed.doc.add(.line(LineGeom(Vec2(50, 50), Vec2(500, 50))))
        _ = ed.doc.add(.line(LineGeom(Vec2(1000, 1000), Vec2(1100, 1000))))
        ed.doc.layers.append(Layer(name: "L", locked: true))
        _ = ed.doc.add(.line(LineGeom(Vec2(30, 30), Vec2(40, 40))), layer: "L")
        // A rough freehand loop around (0,0)-(100,100).
        let ccw = (0..<24).map { i -> Vec2 in let a = Double(i) / 24 * 2 * .pi; return Vec2(50, 50) + Vec2.polar(i % 2 == 0 ? 70 : 68, a) }
        XCTAssertEqual(Set(ed.select(lasso: ccw)), [inside, crossing])
        XCTAssertEqual(ed.select(lasso: Array(ccw.reversed())), [inside])
        XCTAssertEqual(ed.select(lasso: ccw, crossing: false), [inside])
        XCTAssertEqual(ed.select(lasso: [Vec2(0, 0), Vec2(1, 1)]), [])
    }

    func testPolylineFromSegmentsAndWipeoutMasks() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 1000,1000 0,1000 C")
        await ed.run("JOIN ALL ")
        let polys = ed.doc.entities.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry { return p }; return nil }
        XCTAssertEqual(ed.doc.entities.count, 1); XCTAssertEqual(polys.count, 1)
        XCTAssertTrue(polys[0].closed); XCTAssertEqual(polys[0].vertices.count, 4)
        XCTAssertEqual(abs(GeometryOps.area(.polyline(polys[0]), doc: nil) ?? 0), 1e6, accuracy: 1e-6)
        // Open chain of a line and an arc.
        let ed2 = Editor()
        await ed2.run("LINE 0,0 1000,0 ")
        await ed2.run("ARC C 1000,500 1000,0 A 90")
        await ed2.run("JOIN ALL ")
        guard case .polyline(let p2)? = ed2.doc.entities.first?.geometry, ed2.doc.entities.count == 1 else { return XCTFail("not joined") }
        XCTAssertFalse(p2.closed); XCTAssertEqual(p2.vertices.count, 3)
        XCTAssertEqual(GeometryOps.length(.polyline(p2), doc: nil), 1000 + 250 * .pi, accuracy: 1)
        // Wipeout drawn above earlier objects with the background colour (screen) and white on paper.
        await ed.run("WIPEOUT 100,100 900,100 900,900 ")
        let wid = last(ed)!.id
        let entries = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions())
        guard let wi = entries.firstIndex(where: { $0.id == wid }), let pi = entries.firstIndex(where: { $0.id == polys.first.map { _ in ed.doc.entities[0].id } }) else { return XCTFail("no entries") }
        XCTAssertGreaterThan(wi, pi)
        XCTAssertTrue(entries[wi].items.contains { if case .fill(_, let c) = $0 { return c == DraftRendering.screenBackground }; return false })
        var paper = DrawOptions(); paper.forPaper = true
        let pe = DrawListBuilder.entries(doc: ed.doc, options: paper).first { $0.id == wid }
        XCTAssertTrue(pe?.items.contains { if case .fill(_, let c) = $0 { return c.r > 0.99 && c.g > 0.99 && c.b > 0.99 }; return false } ?? false)
    }

    // MARK: DRW-051

    func testSplineFitPointsWithTangencyControl() async {
        let ed = Editor()
        await ed.run("SPLINE T 90 0,0 1000,500 2000,0 3000,800 T 0")
        guard case .spline(let s)? = last(ed)?.geometry else { return XCTFail("no spline") }
        XCTAssertEqual(s.fitPoints, [Vec2(0, 0), Vec2(1000, 500), Vec2(2000, 0), Vec2(3000, 800)])
        XCTAssertEqual(s.controlPoints.count, 6); XCTAssertEqual(s.knots.count, 10)
        // Passes through every fit point exactly at its chord-length parameter.
        let u = SplineFit.parameters(s.fitPoints)
        for (q, t) in zip(s.fitPoints, u) {
            guard let c = SplineFit.point(s, at: t) else { return XCTFail() }
            XCTAssertLessThan(c.distance(to: q), 1e-9)
        }
        // End tangents: first leg vertical (90°), last leg horizontal (0°).
        XCTAssertEqual((s.controlPoints[1] - s.controlPoints[0]).normalized.y, 1, accuracy: 1e-12)
        XCTAssertEqual((s.controlPoints[5] - s.controlPoints[4]).normalized.x, 1, accuracy: 1e-12)
        // The renderer's evaluator agrees with the analytic curve.
        guard let path = CurvePath.make(.spline(s)), let ev = path.eval else { return XCTFail() }
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertLessThan(ev(t).distance(to: SplineFit.point(s, at: t)!), 1e-9)
        }
        XCTAssertLessThan(path.end.distance(to: Vec2(3000, 800)), 1e-9)
        // Without tangency the fit spline keeps its fit-point form and passes through the points.
        await ed.run("SPLINE 0,0 100,100 200,0 ")
        guard case .spline(let f)? = last(ed)?.geometry, let fp = CurvePath.make(.spline(f)) else { return XCTFail() }
        XCTAssertTrue(f.controlPoints.isEmpty)
        XCTAssertLessThan(fp.closest(Vec2(100, 100)).dist, 1e-9)
        // Two points with estimated tangents degenerate to a straight cubic.
        let two = SplineFit.interpolate([.zero, Vec2(10, 0)])!
        XCTAssertLessThan(abs(SplineFit.point(two, at: 0.5)!.y), 1e-12)
    }

    // MARK: Layers, linetypes, lineweights, transparency

    func entry(_ ed: Editor, _ id: EntityID, paper: Bool = false) -> DrawEntry? {
        var o = DrawOptions(); o.forPaper = paper
        return DrawListBuilder.entries(doc: ed.doc, options: o).first { $0.id == id }
    }
    func strokeStyle(_ e: DrawEntry?) -> StrokeStyle? {
        for it in e?.items ?? [] { if case .stroke(_, _, let s) = it { return s } }
        return nil
    }

    func testLayerManagerDisplayPlotAndFile() async throws {
        let ed = Editor()
        await ed.run("LAYER N Walls,Notes Ltype Hidden Walls LWeight 0.5 Walls TR 40 Notes Plot Notes ")
        await ed.run("LAYER S Walls ")
        await ed.run("LINE 0,0 1000,0 ")
        let w = last(ed)!.id
        let st = strokeStyle(entry(ed, w))
        XCTAssertEqual(st?.lineweight, 0.5); XCTAssertEqual(st?.dash, [6, -3])
        await ed.run("LAYER S Notes ")
        await ed.run("LINE 0,100 1000,100 ")
        let n = last(ed)!.id
        XCTAssertEqual(strokeStyle(entry(ed, n))?.color.a ?? 0, 0.6, accuracy: 1e-9, "layer transparency 40%")
        XCTAssertNil(entry(ed, n, paper: true), "non-plotting layer is left out of plots")
        await ed.run("LAYER S 0 OFF Walls ")
        XCTAssertNil(entry(ed, w))
        // Round trip through the .archi file.
        let back = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.layer(named: "Walls")?.linetype, "Hidden"); XCTAssertEqual(back.layer(named: "Walls")?.visible, false)
        XCTAssertEqual(back.layer(named: "Notes")?.plot, false); XCTAssertEqual(back.layer(named: "Notes")?.transparency ?? 0, 0.4, accuracy: 1e-12)
    }

    func testGlobalAndObjectLinetypeScaleAndLineweights() async {
        let ed = Editor()
        await ed.run("LINETYPE S Dashed ")
        await ed.run("LINE 0,0 1000,0 ")
        let a = last(ed)!.id
        XCTAssertEqual(strokeStyle(entry(ed, a))?.dash, [12, -6])
        await ed.run("LTSCALE 10")
        XCTAssertEqual(strokeStyle(entry(ed, a))?.dash, [120, -60])
        await ed.run("SETVAR CELTSCALE 0.5")
        await ed.run("LINE 0,100 1000,100 ")
        let b = last(ed)!.id
        XCTAssertEqual(ed.doc.entity(b)?.props["ltscale"], "0.5")
        XCTAssertEqual(strokeStyle(entry(ed, b))?.dash, [60, -30])
        await ed.run("CHPROP #\(a)  ltScale 2 ")
        XCTAssertEqual(strokeStyle(entry(ed, a))?.dash, [240, -120])
        // Lineweights: current, by layer, per object.
        await ed.run("LWEIGHT 0.7")
        await ed.run("LINE 0,200 1000,200 ")
        XCTAssertEqual(strokeStyle(entry(ed, last(ed)!.id))?.lineweight, 0.7)
        await ed.run("LWEIGHT ByLayer")
        await ed.run("LINE 0,300 1000,300 ")
        XCTAssertEqual(strokeStyle(entry(ed, last(ed)!.id))?.lineweight, 0.25)
    }

    func testObjectTransparencyByLayerByBlockAndDisplay() async {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "Glass", transparency: 0.5))
        let byLayer = ed.doc.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "Glass")
        XCTAssertEqual(strokeStyle(entry(ed, byLayer))?.color.a ?? 0, 0.5, accuracy: 1e-9)
        await ed.run("CHPROP #\(byLayer)  TR 20 ")
        XCTAssertEqual(ed.doc.entity(byLayer)?.props["transparency"], "20")
        XCTAssertEqual(strokeStyle(entry(ed, byLayer))?.color.a ?? 0, 0.8, accuracy: 1e-9)
        ed.selection = []
        let out = await ed.run("CHPROP #\(byLayer)  TR ByLayer ")
        XCTAssertNil(ed.doc.entity(byLayer)?.props["transparency"], out.joined(separator: " | "))
        // ByBlock children take the block reference's transparency; ByLayer children their own layer's.
        var blk = Block(name: "B", basePoint: .zero, entities: [])
        var c1 = Entity(id: 1, layer: "0", geometry: .line(LineGeom(.zero, Vec2(10, 0)))); c1.props["transparency"] = "ByBlock"
        let c2 = Entity(id: 2, layer: "0", geometry: .line(LineGeom(Vec2(0, 5), Vec2(10, 5))))
        blk.entities = [c1, c2]
        ed.doc.blocks["B"] = blk
        let ins = ed.doc.add(.insert(InsertGeom(block: "B", position: Vec2(500, 500))))
        ed.doc.entities[ed.doc.entityIndex(ins)!].props["transparency"] = "60"
        let alphas = (entry(ed, ins)?.items ?? []).compactMap { it -> Double? in if case .stroke(_, _, let s) = it { return s.color.a }; return nil }.sorted()
        XCTAssertEqual(alphas.count, 2)
        XCTAssertEqual(alphas[0], 0.4, accuracy: 1e-9); XCTAssertEqual(alphas[1], 1, accuracy: 1e-9)
        // New objects: CETRANSPARENCY; display switch; plots follow PLOTTRANSPARENCY.
        await ed.run("CETRANSPARENCY 30")
        await ed.run("LINE 0,900 100,900 ")
        let nw = last(ed)!.id
        XCTAssertEqual(ed.doc.entity(nw)?.props["transparency"], "30")
        XCTAssertEqual(strokeStyle(entry(ed, nw, paper: true))?.color.a ?? 0, 0.7, accuracy: 1e-9)
        ed.doc.setVariable("PLOTTRANSPARENCY", "0")
        XCTAssertEqual(strokeStyle(entry(ed, nw, paper: true))?.color.a ?? 0, 1, accuracy: 1e-9)
        await ed.run("TRANSPARENCYDISPLAY 0")
        XCTAssertEqual(strokeStyle(entry(ed, nw))?.color.a ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(Transparency.parse("95"), nil); XCTAssertEqual(Transparency.parse("byblock"), "ByBlock")
    }

    // MARK: LAY-021 / LAY-022

    func testLinFileParseWriteAndLibrary() {
        let text = """
        ;; test
        *MYDASH,My dash __ . __
        A,10,-5,0,-5
        *WATER,Water ---W---W---
        A,8,-2,["W",STANDARD,S=2,R=0.0,X=-1,Y=-1],-3
        *BAD,no pattern line
        *FENCE,Fence
        A,6.35,-2.54,[CIRC1,ltypeshp.shx,x=-2.54,s=2.54],-2.54,25.4
        """
        let defs = LinFile.parse(text)
        XCTAssertEqual(defs.map(\.name), ["MYDASH", "WATER", "FENCE"])
        XCTAssertEqual(defs[0].pattern, [10, -5, 0, -5]); XCTAssertFalse(defs[0].isComplex)
        XCTAssertEqual(defs[1].pattern, [8, -2, -3])
        XCTAssertEqual(defs[1].elements.first?.kind, .text("W", style: "STANDARD"))
        XCTAssertEqual(defs[1].elements.first?.after, 1); XCTAssertEqual(defs[1].elements.first?.x, -1)
        XCTAssertEqual(defs[2].elements.first?.kind, .shape("CIRC1", file: "ltypeshp.shx")); XCTAssertEqual(defs[2].elements.first?.scale, 2.54)
        XCTAssertEqual(LinFile.parse(LinFile.write(defs)), defs)
        XCTAssertGreaterThanOrEqual(LinFile.standard.count, 40)
        XCTAssertTrue(LinFile.standard.contains { $0.name == "ACAD_ISO04W100" && $0.pattern == [24, -3, 0.5, -3] })
        XCTAssertTrue(LinFile.standard.contains { $0.name == "GAS_LINE" && $0.isComplex })
    }

    func testLinetypeLoadFileExportAndComplexRendering() async throws {
        let ed = Editor()
        await ed.run("LINETYPE L GAS_LINE ")
        XCTAssertNotNil(ed.doc.linetype("GAS_LINE"))
        XCTAssertNotNil(ed.doc.variable(LinFile.complexVariable("GAS_LINE")))
        await ed.run("LINETYPE S GAS_LINE ")
        await ed.run("LINE 0,0 1000,0 ")
        let id = last(ed)!.id
        let items = entry(ed, id)?.items ?? []
        let texts = items.compactMap { it -> TextGeom? in if case .text(let t, _, _) = it { return t }; return nil }
        // Period 12.7 + 5.08 + 6.35 = 24.13 → 41 repetitions on 1000 units, each with "GAS".
        XCTAssertEqual(texts.count, 41)
        XCTAssertTrue(texts.allSatisfy { $0.content == "GAS" && abs($0.height - 2.54) < 1e-9 && abs($0.position.y + 1.27) < 1e-9 })
        XCTAssertEqual(texts[0].position.x, 12.7 + 5.08 - 2.54, accuracy: 1e-9)
        let strokes = items.filter { if case .stroke = $0 { return true }; return false }
        XCTAssertEqual(strokes.count, 42)
        // LTSCALE scales dashes and text.
        await ed.run("LTSCALE 2")
        let t2 = (entry(ed, id)?.items ?? []).compactMap { it -> TextGeom? in if case .text(let t, _, _) = it { return t }; return nil }
        XCTAssertEqual(t2.count, 20); XCTAssertEqual(t2[0].height, 5.08, accuracy: 1e-9)
        // Load from a .lin file and export.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-lin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("site.lin")
        try "*FENCEX,Fence x\nA,6,-2,[BOX,ltypeshp.shx,X=-2,S=2],-2,20\n*LONG,Long\nA,40,-10\n".write(to: src, atomically: true, encoding: .utf8)
        await ed.run("LINETYPE F \(src.path) ; ")
        XCTAssertNotNil(ed.doc.linetype("FENCEX")); XCTAssertEqual(ed.doc.linetype("LONG")?.pattern, [40, -10])
        let out = dir.appendingPathComponent("out.lin")
        await ed.run("LINETYPE E \(out.path) ; ")
        let back = LinFile.parse(try String(contentsOf: out, encoding: .utf8))
        XCTAssertTrue(back.contains { $0.name == "FENCEX" && $0.elements.count == 1 })
        XCTAssertTrue(back.contains { $0.name == "GAS_LINE" && $0.isComplex })
        // Round trip in the .archi file.
        let doc2 = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(LinFile.definition("FENCEX", doc: doc2)?.elements.count, 1)
    }

    // MARK: ANN-033, ANN-010, BLK-018, CMD-001

    func testApplyDimensionStyle() async {
        let ed = Editor()
        var big = ed.doc.dimStyle; big.name = "BIG"; big.textHeight = 10; big.decimals = 1
        ed.doc.dimStyles.append(big)
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        let a = last(ed)!.id
        await ed.run("DIMALIGNED 0,1000 300,1400 100,1300")
        let b = last(ed)!.id
        await ed.run("DIMSTYLE S BIG")
        XCTAssertEqual(ed.doc.currentDimStyle, "BIG")
        ed.selection = []
        await ed.run("DIMSTYLE A #\(a),#\(b) ")
        XCTAssertEqual(dim(ed, a)?.style, "BIG"); XCTAssertEqual(dim(ed, b)?.style, "BIG")
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, a)!), 1000, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, b)!), 500, accuracy: 1e-9)
        let texts = (entry(ed, a)?.items ?? []).compactMap { it -> TextGeom? in if case .text(let t, _, _) = it { return t }; return nil }
        XCTAssertTrue(texts.first?.content.hasPrefix("1000") ?? false)
        XCTAssertEqual(texts.first?.height ?? 0, 10 * big.scale, accuracy: 1e-9)
    }

    func testFindAndReplaceAcrossAnnotation() async {
        let ed = Editor()
        await ed.run("TEXT 0,0 250 0 Door D1")
        await ed.run("MTEXT 0,-1000 3000,-2000 Door schedule\\PDoor types ")
        await ed.run("LEADER 0,500 400,900  Door here")
        var blk = Block(name: "TAG")
        var att = Entity(layer: "0", geometry: .text(TextGeom(position: .zero, height: 100, content: "X"))); att.props["attdef"] = "NAME"
        blk.entities = [att]
        ed.doc.blocks["TAG"] = blk
        _ = ed.doc.add(.insert(InsertGeom(block: "TAG", position: Vec2(5000, 0), attributes: ["NAME": "Door 3"])))
        _ = ed.doc.add(.table(TableGeom(origin: Vec2(0, 5000), columnWidths: [1000], rowHeight: 300, cells: [["Door"], ["Window"]])))
        let before = ed.doc
        await ed.run("FIND Door Gate ")
        var n = 0
        for e in ed.doc.entities {
            switch e.geometry {
            case .text(let t): XCTAssertFalse(t.content.contains("Door")); n += t.content.components(separatedBy: "Gate").count - 1
            case .leader(let l): XCTAssertEqual(l.text, "Gate here"); n += 1
            case .insert(let i): XCTAssertEqual(i.attributes["NAME"], "Gate 3"); n += 1
            case .table(let tb): XCTAssertEqual(tb.cells[0][0], "Gate"); XCTAssertEqual(tb.cells[1][0], "Window"); n += 1
            default: break
            }
        }
        XCTAssertEqual(n, 6)
        ed.undo()
        XCTAssertEqual(ed.doc, before)
    }

    func testAttributeEditAndExtract() async throws {
        let ed = Editor()
        var blk = Block(name: "ROOMTAG")
        var a1 = Entity(layer: "0", geometry: .text(TextGeom(position: .zero, height: 100, content: "NAME"))); a1.props["attdef"] = "NAME"
        var a2 = Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(0, -150), height: 100, content: "NO"))); a2.props["attdef"] = "NO"
        blk.entities = [a1, a2]
        ed.doc.blocks["ROOMTAG"] = blk
        let ins = ed.doc.add(.insert(InsertGeom(block: "ROOMTAG", position: .zero, attributes: ["NAME": "Office", "NO": "101"])))
        await ed.run("ATTEDIT #\(ins) Kitchen 102")
        guard case .insert(let i)? = ed.doc.entity(ins)?.geometry else { return XCTFail() }
        XCTAssertEqual(i.attributes, ["NAME": "Kitchen", "NO": "102"])
        // The rendered block shows the new values.
        let texts = (entry(ed, ins)?.items ?? []).compactMap { it -> String? in if case .text(let t, _, _) = it { return t.content }; return nil }
        XCTAssertEqual(Set(texts), ["Kitchen", "102"])
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("attext-\(UUID().uuidString).csv").path
        ed.selection = []
        await ed.run("ATTEXT #\(ins)  \(path)")
        let csv = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(csv.contains("Kitchen")); XCTAssertTrue(csv.contains("102"))
    }

    func testCommandLineIdenticalTypedScriptedAndAPI() async {
        // Script / agent API: one line with all inputs.
        let a = Editor()
        await a.run("CIRCLE 2P 0,0 1000,0")
        // Interactive: the command starts, each prompt is answered separately as typed.
        let b = Editor()
        b.start("CIRCLE")
        await b.waitForInputOrIdle()
        XCTAssertEqual(b.request?.keywords.contains("2P"), true)
        b.feedToken("2P"); await b.waitForInputOrIdle()
        b.feedToken("0,0"); await b.waitForInputOrIdle()
        b.feedToken("1000,0"); await b.waitIdle()
        XCTAssertEqual(a.doc.entities.map(\.geometry), b.doc.entities.map(\.geometry))
        // Keyword by capital letters, default on Enter, invalid input re-prompts.
        let c = Editor()
        let out = await c.run("CIRCLE 0,0 abc 500")
        XCTAssertTrue(out.contains { $0.contains("Invalid input") })
        guard case .circle(let ci)? = c.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ci.radius, 500)
    }
}

