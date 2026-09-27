// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftDetailTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func dim(_ ed: Editor, _ id: EntityID) -> DimensionGeom? { if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d }; return nil }
    func square(_ ed: Editor, _ x0: Double = 0, _ y0: Double = 0, _ s: Double = 100) -> EntityID {
        ed.doc.add(.polyline(PolylineGeom(points: [Vec2(x0, y0), Vec2(x0 + s, y0), Vec2(x0 + s, y0 + s), Vec2(x0, y0 + s)], closed: true)))
    }
    /// Even-odd area of a fill item.
    func fillArea(_ loops: [[Vec2]]) -> Double {
        // Loops of one fill are nested (outer part and hole parts): outer minus the others.
        let a = loops.map { abs(GeometryOps.signedArea($0)) }.sorted(by: >)
        guard let first = a.first else { return 0 }
        return first - a.dropFirst().reduce(0, +)
    }

    // MARK: DIMJOGLINE / DIMJOGGED

    func testJogLineOnLinearDimension() async {
        let ed = Editor()
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        guard let id = ed.doc.entities.last?.id, let d0 = dim(ed, id) else { return XCTFail() }
        let st = ed.doc.dimStyle(d0.style)
        await ed.run("DIMJOGLINE #\(id) 300,300")
        guard let d = dim(ed, id) else { return XCTFail() }
        XCTAssertEqual(DimensionRenderer.jogs(d).count, 1)
        XCTAssertEqual(DimensionRenderer.measurement(d), 1000, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.breaks(d).count, 0)
        XCTAssertEqual(GeometryOps.grips(.dimension(d)).count, 3)
        // The dimension line gets the zig-zag: 6 points, two of them off the line by half the jog height.
        let prim = DimensionRenderer.primitives(d, style: st)
        guard let line = prim.lines.first(where: { $0.count == 6 }) else { return XCTFail("no jog line") }
        let h = st.textHeight * (st.scale > 0 ? st.scale : 1) * DimensionRenderer.jogHeightFactor
        XCTAssertEqual(line.map { abs($0.y - 300) }.max() ?? 0, h / 2, accuracy: 1e-9)
        XCTAssertEqual(line[2].x, 300, accuracy: 1e-9)
        // Breaks keep the jog; moving keeps it attached; Remove deletes it.
        let withGap = DimensionRenderer.withBreaks(d, [.init(center: Vec2(800, 300), radius: 10)], style: st)
        XCTAssertEqual(DimensionRenderer.jogs(withGap).count, 1)
        XCTAssertEqual(DimensionRenderer.breaks(withGap).count, 1)
        XCTAssertEqual(DimensionRenderer.jogs(DimensionRenderer.withBreaks(withGap, [], style: st)).count, 1)
        await ed.run("MOVE #\(id)  0,0 0,100")
        close(DimensionRenderer.jogs(dim(ed, id)!).first ?? .zero, Vec2(300, 400))
        await ed.run("DIMJOGLINE R #\(id)")
        XCTAssertEqual(DimensionRenderer.jogs(dim(ed, id)!).count, 0)
        XCTAssertEqual(DimensionRenderer.measurement(dim(ed, id)!), 1000, accuracy: 1e-9)
    }

    func testJoggedRadius() async {
        let ed = Editor()
        let cid = ed.doc.add(.arc(ArcGeom(Vec2(0, 0), 5000, 0, .pi / 2)))
        await ed.run("DIMJOGGED #\(cid) 4000,1000 3000,4500 3700,2800")
        guard let id = ed.doc.entities.last?.id, id != cid, let d = dim(ed, id) else { return XCTFail() }
        XCTAssertEqual(d.kind, .radius)
        XCTAssertEqual(DimensionRenderer.measurement(d), 5000, accuracy: 1e-9)
        let st = ed.doc.dimStyle(d.style)
        XCTAssertEqual(DimensionRenderer.formatted(d, style: st), "R5000")
        let js = DimensionRenderer.jogs(d)
        XCTAssertEqual(js.count, 2)
        close(js[0], Vec2(4000, 1000))
        let prim = DimensionRenderer.primitives(d, style: st)
        XCTAssertEqual(prim.arrows.count, 1)
        // The text location lies outside the arc: the line starts there, the arrow tip is on the arc pointing back in,
        // and the dimension line ends at the overridden centre.
        let w = Vec2(3000, 4500).normalized
        guard let path = prim.lines.first(where: { $0.count == 4 }) else { return XCTFail() }
        close(path[0], Vec2(3000, 4500), 1e-6)
        XCTAssertTrue(prim.arrows[0].contains { $0.isClose(w * 5000, tol: 1e-6) })
        close(path[3], Vec2(4000, 1000), 1e-9)
        // Segment a→b is the jog: its end lies on the line through the centre override parallel to the radius.
        let off = (path[2] - Vec2(4000, 1000)).cross(w)
        XCTAssertEqual(off, 0, accuracy: 1e-6)
        XCTAssertNotNil(prim.text)
    }

    // MARK: Gradient fills

    func testLinearGradientBandsCoverRegionExactly() async {
        let loops = [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)], [Vec2(40, 40), Vec2(60, 40), Vec2(60, 60), Vec2(40, 60)]]
        let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)
        let items = DraftRendering.gradientFills(loops: loops, type: "LINEAR", angle: 0, centered: true, stops: (red, blue), bands: 10)
        XCTAssertEqual(items.count, 10)
        var total = 0.0
        var colors: [RGBA] = []
        for it in items { if case .fill(let l, let c) = it { total += fillArea(l); colors.append(c) } }
        XCTAssertEqual(total, 10000 - 400, accuracy: 1e-6)
        XCTAssertEqual(colors.first?.r ?? 0, 0.95, accuracy: 1e-9)
        XCTAssertEqual(colors.last?.b ?? 0, 0.95, accuracy: 1e-9)
        // Band 0 lies in x ∈ [0, 10].
        if case .fill(let l, _) = items[0] { XCTAssertLessThanOrEqual(l.flatMap { $0 }.map(\.x).max() ?? 99, 10 + 1e-6) }
        // Rotated 90°: bands run along y.
        let v = DraftRendering.gradientFills(loops: [loops[0]], type: "LINEAR", angle: .pi / 2, centered: true, stops: (red, blue), bands: 4)
        if case .fill(let l, _) = v[0] { XCTAssertLessThanOrEqual(l.flatMap { $0 }.map(\.y).max() ?? 99, 25 + 1e-6) }
    }

    func testCylinderAndSphericalGradients() async {
        let sq = [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]]
        XCTAssertEqual(DraftRendering.gradientParameter("CYLINDER", 0.5), 1, accuracy: 1e-12)
        XCTAssertEqual(DraftRendering.gradientParameter("CYLINDER", 0), 0, accuracy: 1e-12)
        XCTAssertEqual(DraftRendering.gradientParameter("INVCYLINDER", 0), 1, accuracy: 1e-12)
        let cyl = DraftRendering.gradientFills(loops: sq, type: "CYLINDER", angle: 0, centered: true, stops: (.black, .white), bands: 8)
        var cs: [Double] = []
        for it in cyl { if case .fill(_, let c) = it { cs.append(c.r) } }
        XCTAssertEqual(cs.count, 8)
        for i in 0..<4 { XCTAssertEqual(cs[i], cs[7 - i], accuracy: 1e-9) }   // symmetric, lightest in the middle
        XCTAssertGreaterThan(cs[3], cs[0])
        // Spherical: concentric discs from the outside in; the first covers the whole square, the last is centred.
        let sph = DraftRendering.gradientFills(loops: sq, type: "SPHERICAL", angle: 0, centered: true, stops: (.black, .white), bands: 16)
        XCTAssertEqual(sph.count, 16)
        if case .fill(let l, let c) = sph[0] { XCTAssertEqual(fillArea(l), 10000, accuracy: 1e-6); XCTAssertLessThan(c.r, 0.1) }
        if case .fill(let l, let c) = sph[15] {
            close(GeometryOps.centroid(l[0]), Vec2(50, 50), 1e-6); XCTAssertGreaterThan(c.r, 0.9)
        }
        // A region far from convex: an L shape is filled exactly by the linear bands.
        let L = [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 20), Vec2(20, 20), Vec2(20, 100), Vec2(0, 100)]]
        var tot = 0.0
        for it in DraftRendering.gradientFills(loops: L, type: "LINEAR", angle: .pi / 4, centered: true, stops: (.black, .white), bands: 7) { if case .fill(let l, _) = it { tot += fillArea(l) } }
        XCTAssertEqual(tot, 100 * 20 + 20 * 80, accuracy: 1e-6)
    }

    func testGradientCommandAndStops() async {
        let ed = Editor()
        let sq = square(ed)
        await ed.run("GRADIENT T SPHERICAL C 1,#0000FF A 30 S #\(sq) ;")
        guard let e = ed.doc.entities.last, e.id != sq, case .hatch(let h) = e.geometry else { return XCTFail() }
        XCTAssertEqual(h.pattern, "SOLID")
        XCTAssertEqual(e.props[DraftRendering.gradientProp], "SPHERICAL")
        XCTAssertEqual(e.props[DraftRendering.gradientColorsProp], "1,#0000FF")
        XCTAssertEqual(Double(e.props[DraftRendering.gradientAngleProp] ?? "") ?? 0, 30, accuracy: 1e-9)
        let stops = DraftRendering.gradientStops(e.props, color: .white)
        XCTAssertEqual(stops.0, RGBA(1, 0, 0)); XCTAssertEqual(stops.1, RGBA(0, 0, 1))
        guard let items = DraftRendering.items(e, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        XCTAssertEqual(items.count, DraftRendering.gradientBands)
        // One-colour gradient tints towards white.
        let one = DraftRendering.gradientStops([DraftRendering.gradientColorsProp: "#000000", DraftRendering.gradientTintProp: "1"], color: .white)
        XCTAssertEqual(one.1, RGBA(1, 1, 1))
        // Rotating the gradient hatch rotates its angle; saving keeps the props.
        await ed.run("ROTATE #\(e.id)  0,0 90")
        XCTAssertEqual(Double(ed.doc.entity(e.id)?.props[DraftRendering.gradientAngleProp] ?? "") ?? 0, 120, accuracy: 1e-6)
        let back = try? ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(back?.entity(e.id)?.props[DraftRendering.gradientProp], "SPHERICAL")
    }

    // MARK: Hatch origin

    func testHatchOriginShiftsPattern() async {
        let loops = [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]]
        let a = HatchPatterns.lines(loops: loops, pattern: "LINE", scale: 10, angle: 0)
        let b = HatchPatterns.lines(loops: loops, pattern: "LINE", scale: 10, angle: 0, origin: Vec2(0, 7))
        XCTAssertFalse(a.isEmpty); XCTAssertFalse(b.isEmpty)
        let sp = 31.75
        for s in b { let r = (s[0].y - 7).truncatingRemainder(dividingBy: sp); XCTAssertTrue(abs(r) < 1e-6 || abs(abs(r) - sp) < 1e-6, "\(s[0].y)") }
        XCTAssertTrue(a.contains { abs($0[0].y) < 1e-9 || abs($0[0].y - sp) < 1e-9 })
        // Command: origin at the bottom-left corner of the hatch; moving the hatch moves the origin.
        let ed = Editor()
        let hid = ed.doc.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(10, 20)), PolyVertex(Vec2(110, 20)), PolyVertex(Vec2(110, 120)), PolyVertex(Vec2(10, 120))]], pattern: "ANSI31")))
        await ed.run("HATCHSETORIGIN #\(hid)  BottomLeft")
        close(DraftProps.point(ed.doc.entity(hid)?.props[DraftRendering.hatchOriginProp]) ?? .zero, Vec2(10, 20))
        await ed.run("MOVE #\(hid)  0,0 5,5")
        close(DraftProps.point(ed.doc.entity(hid)?.props[DraftRendering.hatchOriginProp]) ?? .zero, Vec2(15, 25))
        guard let e = ed.doc.entity(hid), let items = DraftRendering.items(e, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        XCTAssertFalse(items.isEmpty)
        await ed.run("HATCHSETORIGIN #\(hid)  Default")
        XCTAssertNil(ed.doc.entity(hid)?.props[DraftRendering.hatchOriginProp])
        // HPORIGIN applies to new hatches.
        let sq = square(ed, 200, 200)
        ed.doc.setVariable("HPORIGIN", "200,200")
        await ed.run("HATCH S #\(sq) ;")
        XCTAssertEqual(ed.doc.entities.last?.props[DraftRendering.hatchOriginProp].flatMap(DraftProps.point), Vec2(200, 200))
    }

    // MARK: Table merge

    func testTableMergeRenderingAndCommand() async {
        let ed = Editor()
        let t = TableGeom(origin: .zero, columnWidths: [100, 100, 100], rowHeight: 20, cells: [["Title", "", ""], ["a", "b", "c"], ["d", "e", "f"]], textHeight: 5)
        let tid = ed.doc.add(.table(t))
        await ed.run("TABLEEDIT #\(tid) Merge A1 C1 X")
        XCTAssertEqual(ed.doc.entity(tid)?.props[DraftRendering.tableMergeProp], "0,0,1,3")
        guard let e = ed.doc.entity(tid), let items = DraftRendering.items(e, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        // No vertical line crosses the merged first row (y from 0 to -20).
        let verticals = items.compactMap { it -> [Vec2]? in if case .stroke(let p, false, _) = it, p.count == 2, abs(p[0].x - p[1].x) < 1e-9 { return p }; return nil }
        XCTAssertEqual(verticals.count, 2)
        for v in verticals { XCTAssertLessThanOrEqual(max(v[0].y, v[1].y), -20 + 1e-9) }
        // The merged text is centred over the three columns.
        let texts = items.compactMap { it -> TextGeom? in if case .text(let tx, _, _) = it { return tx }; return nil }
        guard let title = texts.first(where: { $0.content == "Title" }) else { return XCTFail() }
        close(title.position, Vec2(150, -10)); XCTAssertEqual(title.halign, .center)
        XCTAssertEqual(texts.count, 7)
        // Overlapping merges absorb each other; Unmerge removes.
        let m = DraftRendering.merged(DraftRendering.merges("0,0,1,3"), adding: .init(row: 0, col: 2, rowSpan: 2, colSpan: 1), rows: 3, cols: 3)
        XCTAssertEqual(m, [.init(row: 0, col: 0, rowSpan: 2, colSpan: 3)])
        XCTAssertNil(DraftRendering.merged([], adding: .init(row: 2, col: 2, rowSpan: 2, colSpan: 1), rows: 3, cols: 3))
        await ed.run("TABLEEDIT #\(tid) Unmerge B1 X")
        XCTAssertNil(ed.doc.entity(tid)?.props[DraftRendering.tableMergeProp])
        XCTAssertNil(DraftRendering.items(ed.doc.entity(tid)!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25))
    }

    // MARK: Revision stamps

    func testRevisionStamps() async {
        XCTAssertEqual(RevisionSymbols.next(after: nil), "1")
        XCTAssertEqual(RevisionSymbols.next(after: "9"), "10")
        XCTAssertEqual(RevisionSymbols.next(after: "A"), "B")
        XCTAssertEqual(RevisionSymbols.next(after: "Z"), "AA")
        XCTAssertEqual(RevisionSymbols.next(after: "AZ"), "BA")
        let tri = RevisionSymbols.triangle(center: Vec2(10, 10), size: 30, label: "3")
        guard case .polyline(let p) = tri[0], case .text(let t) = tri[1] else { return XCTFail() }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3)
        for v in p.vertices { XCTAssertEqual(v.p.distance(to: Vec2(10, 10)), 30 / 3.0.squareRoot(), accuracy: 1e-9) }
        XCTAssertEqual(p.vertices[0].p.distance(to: p.vertices[1].p), 30, accuracy: 1e-9)
        XCTAssertEqual(t.content, "3")
        let ed = Editor()
        ed.doc.layouts = [Layout(name: "A-101")]
        ed.doc.setVariable("CTAB", "A-101")
        await ed.run("REVSTAMP Table 1 2026-09-01 OA \"Issued for tender\" 0,0")
        await ed.run("REVSTAMP Table  2026-09-20 OA \"Doors revised\"")
        let tables = ed.doc.entities.filter { $0.props["revisionTable"] == "1" }
        XCTAssertEqual(tables.count, 1)
        guard case .table(let tb)? = tables.first?.geometry else { return XCTFail() }
        XCTAssertEqual(tb.cells.count, 3)
        XCTAssertEqual(tb.cells[2][0], "2")
        XCTAssertEqual(tb.cells[2][3], "Doors revised")
        XCTAssertEqual(ed.doc.variable("REVNUMBER"), "2")
        XCTAssertEqual(ed.doc.layouts[0].titleBlock["revision"], "2")
        await ed.run("REVSTAMP Triangle  50 100,100 ;")
        let grouped = ed.doc.entities.filter { $0.props["group"]?.hasPrefix("REV") == true }
        XCTAssertEqual(grouped.count, 2)
        XCTAssertTrue(grouped.contains { if case .text(let t) = $0.geometry { return t.content == "2" }; return false })
    }

    // MARK: Text masks and frames

    func testTextMaskAndFrame() async {
        let ed = Editor()
        let id = ed.doc.add(.text(TextGeom(position: Vec2(0, 0), height: 10, content: "MASK")))
        await ed.run("TEXTMASK #\(id)  1.5 Background")
        XCTAssertEqual(ed.doc.entity(id)?.props[DraftRendering.textMaskProp], "1.5")
        guard let e = ed.doc.entity(id), let items = DraftRendering.items(e, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        guard case .fill(let loops, let c) = items[0] else { return XCTFail("mask first") }
        XCTAssertEqual(c, DraftRendering.screenBackground)
        let b = BBox2(points: loops[0])
        let tb = BBox2(points: GeometryOps.textBoxCorners(TextGeom(position: .zero, height: 10, content: "MASK")))
        XCTAssertEqual(b.min.x, tb.min.x - 5, accuracy: 1e-9); XCTAssertEqual(b.max.y, tb.max.y + 5, accuracy: 1e-9)
        var paper = DrawOptions(); paper.forPaper = true
        // End to end (with the paper colour mapping): the mask stays white on paper instead of printing black.
        if case .fill(_, let pc)? = DrawListBuilder.items(for: e, doc: ed.doc, options: paper).first { XCTAssertEqual(pc, .white) } else { XCTFail() }
        await ed.run("TEXTFRAME #\(id)  ON")
        let framed = DraftRendering.items(ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) ?? []
        XCTAssertTrue(framed.contains { if case .stroke(let p, true, _) = $0 { return p.count == 4 }; return false })
        await ed.run("TEXTUNMASK #\(id) ")
        await ed.run("TEXTFRAME #\(id)  OFF")
        XCTAssertNil(DraftRendering.items(ed.doc.entity(id)!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25))
    }

    // MARK: FLATTEN / CHSPACE

    func testFlatten() async {
        let ed = Editor()
        let box = ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 500), size: Vec3(200, 100, 300))))
        let line = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(10, 0))))
        if let i = ed.doc.entityIndex(line) { ed.doc.entities[i].props["elevation"] = "1200" }
        await ed.run("FLATTEN #\(box),#\(line) ")
        guard case .polyline(let p)? = ed.doc.entity(box)?.geometry else { return XCTFail("solid not flattened") }
        XCTAssertTrue(p.closed)
        XCTAssertEqual(abs(GeometryOps.signedArea(p.vertices.map(\.p))), 200 * 100, accuracy: 1e-6)
        XCTAssertNil(ed.doc.entity(line)?.props["elevation"])
        if case .line = ed.doc.entity(line)?.geometry {} else { XCTFail() }
    }

    func testChangeSpace() async {
        let ed = Editor()
        var l = Layout(name: "S1")
        l.viewports = [Viewport(origin: Vec2(10, 10), size: Vec2(200, 100), viewCenter: Vec2(5000, 5000), scale: 100)]
        ed.doc.layouts = [l]
        ed.doc.setVariable("CTAB", "S1")
        let id = ed.doc.add(.line(LineGeom(Vec2(5000, 5000), Vec2(6000, 5000))))
        await ed.run("CHSPACE Paper #\(id) ")
        XCTAssertNil(ed.doc.entity(id))
        guard let pe = ed.doc.layouts[0].entities.first, case .line(let pl) = pe.geometry else { return XCTFail() }
        close(pl.a, Vec2(110, 60)); close(pl.b, Vec2(120, 60))
        await ed.run("CHSPACE Model All 1")
        XCTAssertTrue(ed.doc.layouts[0].entities.isEmpty)
        guard case .line(let ml)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(ml.a, Vec2(5000, 5000), 1e-6); close(ml.b, Vec2(6000, 5000), 1e-6)
    }

    // MARK: Splines

    func testSplineControlFormMatchesFitCurve() async {
        for closed in [false, true] {
            let fit = [Vec2(0, 0), Vec2(100, 50), Vec2(200, -20), Vec2(260, 80), Vec2(300, 0)]
            let s = SplineGeom(controlPoints: [], fitPoints: fit, closed: closed)
            guard let c = SplineTools.controlForm(s) else { return XCTFail() }
            let segs = closed ? fit.count : fit.count - 1
            XCTAssertEqual(c.controlPoints.count, 3 * segs + 1)
            XCTAssertEqual(c.knots.count, c.controlPoints.count + 4)
            let samples = 8
            let ref = GeometryOps.catmullRom(fit, closed: closed, samples: samples)
            for i in 0..<segs {
                for k in 0..<samples {
                    let t = Double(i) + Double(k) / Double(samples)
                    guard let p = SplineTools.evaluate(c, t) else { return XCTFail() }
                    close(p, ref[i * samples + k], 1e-9)
                }
            }
            close(SplineTools.evaluate(c, Double(segs))!, closed ? fit[0] : fit.last!, 1e-9)
        }
    }

    func testSplineCommandsCVAndEdit() async {
        let ed = Editor()
        await ed.run("SPLINE M CV 0,0 100,100 200,0 300,100 ;")
        guard let id = ed.doc.entities.last?.id, case .spline(let s)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(s.controlPoints.count, 4); XCTAssertEqual(s.degree, 3)
        close(GeometryOps.splinePoints(s).first!, Vec2(0, 0), 1e-9); close(GeometryOps.splinePoints(s).last!, Vec2(300, 100), 1e-9)
        ed.doc.setVariable("SPLMETHOD", "0")
        await ed.run("SPLINE 0,0 100,100 200,0 ;")
        guard let fid = ed.doc.entities.last?.id else { return XCTFail() }
        await ed.run("SPLINEDIT #\(fid) Fit Add 150,80 Move 100,100 100,120 X Close X")
        guard case .spline(let f)? = ed.doc.entity(fid)?.geometry else { return XCTFail() }
        XCTAssertEqual(f.fitPoints.count, 4)
        XCTAssertTrue(f.fitPoints.contains(Vec2(150, 80)))
        XCTAssertTrue(f.fitPoints.contains(Vec2(100, 120)))
        XCTAssertTrue(f.closed)
        await ed.run("SPLINEDIT #\(fid) Cv X")
        guard case .spline(let cv)? = ed.doc.entity(fid)?.geometry else { return XCTFail() }
        XCTAssertTrue(cv.fitPoints.isEmpty); XCTAssertEqual(cv.controlPoints.count, 13)
        await ed.run("SPLINEDIT #\(fid) Edit Delete 0,0 X X")
        guard case .spline(let cv2)? = ed.doc.entity(fid)?.geometry else { return XCTFail() }
        XCTAssertEqual(cv2.controlPoints.count, 12)
        XCTAssertTrue(cv2.knots.isEmpty)
    }

    func testBlendIsTangent() async {
        let ed = Editor()
        ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        ed.doc.add(.line(LineGeom(Vec2(200, 100), Vec2(300, 100))))
        await ed.run("BLEND 95,0 205,100")
        guard case .spline(let s)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(s.controlPoints.count, 4)
        close(SplineTools.evaluate(s, 0)!, Vec2(100, 0), 1e-9)
        close(SplineTools.evaluate(s, 1)!, Vec2(200, 100), 1e-9)
        // G1: the first control leg continues the first line, the last leg arrives along the second line.
        XCTAssertEqual((s.controlPoints[1] - s.controlPoints[0]).cross(Vec2(1, 0)), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(s.controlPoints[1].x, 100)
        XCTAssertEqual((s.controlPoints[3] - s.controlPoints[2]).cross(Vec2(1, 0)), 0, accuracy: 1e-9)
        XCTAssertLessThan(s.controlPoints[2].x, 200)
        // Arc end tangents are exact.
        let arc = ArcGeom(Vec2(0, 0), 10, 0, .pi / 2)
        let e = SplineTools.endTangent(.arc(arc), atStart: false, doc: nil)!
        close(e.point, Vec2(0, 10), 1e-12); close(e.dir, Vec2(-1, 0), 1e-12)
        let st = SplineTools.endTangent(.arc(arc), atStart: true, doc: nil)!
        close(st.dir, Vec2(0, -1), 1e-12)
        let smooth = SplineTools.blend(Vec2(0, 0), Vec2(1, 0), Vec2(10, 10), Vec2(0, 1), smooth: true)
        XCTAssertEqual(smooth.degree, 5)
        close(SplineTools.evaluate(smooth, 1)!, Vec2(10, 10), 1e-9)
    }

    // MARK: Polylines, trace, lengthen, align, rotate, txtexp

    func testPolylineVertexEditing() async {
        let p = PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)])
        guard let arc = PolylineEdit.setSegment(p, 0, arcThrough: Vec2(50, -50)) else { return XCTFail() }
        XCTAssertEqual(abs(arc.vertices[0].bulge), 1, accuracy: 1e-9)
        XCTAssertEqual(PolylineEdit.setSegment(arc, 0, arcThrough: nil)?.vertices[0].bulge, 0)
        XCTAssertEqual(PolylineEdit.nearestSegment(p, to: Vec2(101, 50)), 1)
        XCTAssertEqual(PolylineEdit.straighten(p, 0, 3)?.vertices.count, 2)
        let pieces = PolylineEdit.breakBetween(p, 1, 2)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].vertices.map(\.p), [Vec2(0, 0), Vec2(100, 0)])
        XCTAssertEqual(pieces[1].vertices.map(\.p), [Vec2(100, 100), Vec2(0, 100)])
        var closedP = p; closedP.closed = true
        let opened = PolylineEdit.breakBetween(closedP, 1, 2)
        XCTAssertEqual(opened.count, 1); XCTAssertFalse(opened[0].closed)
        XCTAssertEqual(opened[0].vertices.map(\.p), [Vec2(100, 100), Vec2(0, 100), Vec2(0, 0), Vec2(100, 0)])
        XCTAssertEqual(PolylineEdit.append(p, points: [Vec2(-50, 100)], atStart: false).vertices.count, 5)
        XCTAssertEqual(PolylineEdit.append(p, points: [Vec2(-50, 0)], atStart: true).vertices.first?.p, Vec2(-50, 0))
        // PEDIT Edit vertex: move vertex 2, insert after it; SEgment to an arc; APpend.
        let ed = Editor()
        let id = ed.doc.add(.polyline(p))
        await ed.run("PEDIT #\(id) Edit Next Move 120,-10 Insert 110,50 eXit X")
        guard case .polyline(let q)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(q.vertices.map(\.p), [Vec2(0, 0), Vec2(120, -10), Vec2(110, 50), Vec2(100, 100), Vec2(0, 100)])
        await ed.run("PEDIT #\(id) SEgment 50,-2 Arc 60,-40 X")
        guard case .polyline(let q2)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertNotEqual(q2.vertices[0].bulge, 0)
        await ed.run("PEDIT #\(id) APpend 0,100 -100,100 -100,0 ; X")
        guard case .polyline(let q3)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(q3.vertices.count, 7); XCTAssertEqual(q3.vertices.last?.p, Vec2(-100, 0))
        await ed.run("PEDIT #\(id) Edit Next Break Next Next Go")
        let polys = ed.doc.entities.filter { if case .polyline = $0.geometry { return true }; return false }
        XCTAssertEqual(polys.count, 2)
    }

    func testTraceRotate90AndTextExplode() async {
        let ed = Editor()
        await ed.run("TRACE 20 0,0 100,0 100,100 ;")
        guard case .polyline(let t)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(t.width, 20); XCTAssertEqual(t.vertices.count, 3)
        let lid = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        await ed.run("ROTATE90 #\(lid) ;")
        guard case .line(let l)? = ed.doc.entity(lid)?.geometry else { return XCTFail() }
        close(l.a, Vec2(50, -50), 1e-9); close(l.b, Vec2(50, 50), 1e-9)
        await ed.run("ROTATE90 #\(lid)  C")
        guard case .line(let l2)? = ed.doc.entity(lid)?.geometry else { return XCTFail() }
        close(l2.a, Vec2(0, 0), 1e-9)
        let tid = ed.doc.add(.text(TextGeom(position: Vec2(0, 0), height: 10, content: "AB C", rotation: .pi / 2)))
        await ed.run("TXTEXP #\(tid)  Letters")
        let letters = ed.doc.entities.compactMap { e -> TextGeom? in if case .text(let t) = e.geometry { return t }; return nil }
        XCTAssertEqual(letters.map(\.content), ["A", "B", "C"])
        close(letters[0].position, .zero, 1e-9)
        close(letters[1].position, Vec2(0, 7.2), 1e-9)   // advance of "A" = 0.72 h along the text direction
        close(letters[2].position, Vec2(0, 7.2 * 2 + 4), 1e-9)
    }

    func testLengthenDynamicAndAlignMirror() async {
        let ed = Editor()
        let id = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        await ed.run("LENGTHEN DY 90,0 150,20 ;")
        guard case .line(let l)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        close(l.a, .zero); close(l.b, Vec2(150, 0))
        let aid = ed.doc.add(.arc(ArcGeom(Vec2(0, 0), 100, 0, .pi / 2)))
        await ed.run("LENGTHEN DY 0,99 -100,0 ;")
        guard case .arc(let a)? = ed.doc.entity(aid)?.geometry else { return XCTFail() }
        XCTAssertEqual(a.sweep, .pi, accuracy: 1e-9)
        // ALIGN with a third pair on the other side mirrors.
        let t = ModifyCommands.alignTransform(Vec2(0, 0), Vec2(10, 0), Vec2(100, 100), Vec2(100, 110), scale: false, mirror: true)
        close(t.apply(Vec2(0, 5)), Vec2(105, 100), 1e-9)
        close(t.apply(Vec2(10, 0)), Vec2(100, 110), 1e-9)
        let pid = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 5))))
        await ed.run("ALIGN #\(pid)  0,0 100,100 10,0 100,110 3,1 103,103 N")
        guard case .line(let pl)? = ed.doc.entity(pid)?.geometry else { return XCTFail() }
        close(pl.b, Vec2(105, 100), 1e-9)
    }

    // MARK: QDIM modes, ordinate re-base

    func testQuickDimensionModes() async {
        let q = QuickDim(points: [Vec2(0, 0), Vec2(100, 0), Vec2(300, 0), Vec2(600, 0)], curves: [(Vec2(50, 50), 20, true)], spacing: 10)
        let ord = q.build("Ordinate", at: Vec2(0, -100), datum: Vec2(-50, 0))
        XCTAssertEqual(ord.count, 4)
        XCTAssertEqual(ord.map { DimensionRenderer.measurement($0) }, [50, 150, 350, 650])
        let st = q.build("Staggered", at: Vec2(0, -100))
        XCTAssertEqual(st.map { DimensionRenderer.measurement($0) }, [200, 600])
        XCTAssertEqual(st[1].points[2].y, -110, accuracy: 1e-9)
        XCTAssertEqual(q.build("Baseline", at: Vec2(0, -100)).map { DimensionRenderer.measurement($0) }, [100, 300, 600])
        let r = q.build("Radius", at: Vec2(100, 50))
        XCTAssertEqual(r.count, 1); XCTAssertEqual(DimensionRenderer.measurement(r[0]), 20, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.measurement(q.build("Diameter", at: Vec2(100, 50))[0]), 40, accuracy: 1e-9)
        let ed = Editor()
        ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        ed.doc.add(.line(LineGeom(Vec2(100, 0), Vec2(250, 0))))
        await ed.run("QDIM All  Ordinate 0,-50")
        let dims = ed.doc.entities.compactMap { e -> DimensionGeom? in if case .dimension(let d) = e.geometry { return d }; return nil }
        XCTAssertEqual(dims.count, 3); XCTAssertTrue(dims.allSatisfy { $0.kind == .ordinate })
        let ids = ed.doc.entities.filter { if case .dimension = $0.geometry { return true }; return false }.map { "#\($0.id)" }.joined(separator: ",")
        await ed.run("DIMREBASE \(ids)  100,0")
        let rebased = ed.doc.entities.compactMap { e -> DimensionGeom? in if case .dimension(let d) = e.geometry { return d }; return nil }
        XCTAssertEqual(rebased.map { DimensionRenderer.measurement($0) }.sorted(), [-100, 0, 150])
    }

    // MARK: Fields

    func testFormulaAndSheetFields() async {
        var doc = ArchiDocument()
        doc.setVariable("USERR1", "3")
        let sq = doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(2000, 0), Vec2(2000, 1000), Vec2(0, 1000)], closed: true)))
        XCTAssertEqual(Fields.expression("{Var(USERR1)}*2+1", doc: doc) ?? 0, 7, accuracy: 1e-12)
        XCTAssertEqual(Fields.expression("USERR1^2 + sqrt(16)", doc: doc) ?? 0, 13, accuracy: 1e-12)
        XCTAssertEqual(Fields.expression("Area(\(sq))/1e6", doc: doc) ?? 0, 2, accuracy: 1e-12)
        XCTAssertNil(Fields.expression("NOSUCHVAR+1", doc: doc))
        XCTAssertEqual(Fields.evaluate("Expr({Area(\(sq))}/3e6):3", doc: doc), "0.667")
        var l1 = Layout(name: "Ground floor"); l1.titleBlock["sheetNumber"] = "A-101"
        let l2 = Layout(name: "Sections")
        doc.layouts = [l1, l2]
        var e = Entity(geometry: .text(TextGeom(position: .zero, height: 3, content: "")))
        e.props["field"] = "Sheet %<SheetNumber>% of %<SheetCount>% – %<SheetName>%"
        e.id = doc.allocateID()
        doc.layouts[1].entities.append(e)
        var e0 = e; e0.id = doc.allocateID(); doc.layouts[0].entities.append(e0)
        XCTAssertTrue(Fields.updateAll(&doc))
        guard case .text(let t1) = doc.layouts[1].entities[0].geometry, case .text(let t0) = doc.layouts[0].entities[0].geometry else { return XCTFail() }
        XCTAssertEqual(t1.content, "Sheet 2 of 2 – Sections")
        XCTAssertEqual(t0.content, "Sheet A-101 of 2 – Ground floor")
        // FIELD command with a formula.
        let ed = Editor()
        ed.doc.setVariable("USERR1", "2.5")
        await ed.run("FIELD Expression \"USERR1*4\" 1 \"#\" 0,0 10")
        guard case .text(let ft)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ft.content, "10.0")
        ed.doc.setVariable("USERR1", "3")
        var d = ed.doc; Fields.updateAll(&d)
        if case .text(let u)? = d.entities.last?.geometry { XCTAssertEqual(u.content, "12.0") } else { XCTFail() }
    }

    // MARK: Selection

    func testQueryAndSelectInstances() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0")
        await ed.run("WALL 0,3000 5000,3000")
        let walls = ed.doc.elements.filter { if case .wall = $0.geometry { return true }; return false }.map(\.id)
        XCTAssertEqual(walls.count, 2)
        if let i = ed.doc.elementIndex(walls[0]) { ed.doc.elements[i].material = "Brick" }
        if let i = ed.doc.elementIndex(walls[1]) { ed.doc.elements[i].material = "Concrete" }
        ed.doc.add(.line(LineGeom(.zero, Vec2(1, 1))))
        guard let f = ObjectQuery.Filter(parse: "IfcWall, material=Brick") else { return XCTFail() }
        let hits = ed.doc.allIDs.filter { f.matches($0, doc: ed.doc) }
        XCTAssertEqual(hits, [walls[0]])
        XCTAssertEqual(ed.doc.allIDs.filter { ObjectQuery.Filter(parse: "IfcWall")!.matches($0, doc: ed.doc) }.count, 2)
        await ed.run("FILTER \"IfcWall, material=Concrete\"")
        XCTAssertEqual(ed.selection, [walls[1]])
        ed.selection = []
        ed.doc.blocks["CHAIR"] = Block(name: "CHAIR", entities: [Entity(geometry: .circle(CircleGeom(.zero, 200)))])
        ed.doc.blocks["TABLE"] = Block(name: "TABLE", entities: [Entity(geometry: .circle(CircleGeom(.zero, 500)))])
        let c1 = ed.doc.add(.insert(InsertGeom(block: "CHAIR", position: Vec2(10000, 0))))
        let c2 = ed.doc.add(.insert(InsertGeom(block: "CHAIR", position: Vec2(12000, 0))))
        ed.doc.add(.insert(InsertGeom(block: "TABLE", position: Vec2(14000, 0))))
        await ed.run("SELECTINSTANCES #\(c1)")
        XCTAssertEqual(ed.selection, [c1, c2])
        await ed.run("SELECTINSTANCES #\(walls[0])")
        XCTAssertEqual(ed.selection, Set(walls))
    }

    // MARK: Attributes

    func testAttributeModes() async {
        let ed = Editor()
        await ed.run("ATTDEF C MAKER ACME 0,0 10 0")
        await ed.run("ATTDEF C P ROOM \"Room number\" 101 0,-20 10 0")
        let defs = ed.doc.entities.filter { $0.props["attdef"] != nil }
        XCTAssertEqual(defs.count, 2)
        XCTAssertEqual(defs[0].props[AttributeModes.prop], "C")
        XCTAssertEqual(defs[1].props[AttributeModes.prop], "P")      // C toggled off again, P on
        let ids = ed.doc.entities.map { "#\($0.id)" }.joined(separator: ",")
        await ed.run("BLOCK TAGB 0,0 \(ids) ")
        ed.doc.setVariable("ATTREQ", "1")
        await ed.run("INSERT TAGB 100,100 1 1 0")
        guard case .insert(let ins)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(ins.attributes["MAKER"], "ACME")
        XCTAssertEqual(ins.attributes["ROOM"], "101")
        // Verify asks twice; the second answer wins.
        await ed.run("ATTDEF P V CODE Code X 0,0 5 0")
        XCTAssertEqual(ed.doc.entities.last?.props[AttributeModes.prop], "V")
    }

    // MARK: Dynamic blocks

    func testDynamicBlockStretchAndArray() async throws {
        let ed = Editor()
        let desk = Entity(geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 600), Vec2(0, 600)], closed: true)))
        let chair = Entity(geometry: .circle(CircleGeom(Vec2(200, -200), 100)))
        ed.doc.blocks["DESK"] = Block(name: "DESK", entities: [desk, chair])
        await ed.run("BPARAMETER DESK Stretch Width 900,-50 1100,700 0,0 1000,0")
        await ed.run("BPARAMETER DESK Array Chairs 50,-350 350,-50 0,0 400,0")
        XCTAssertEqual(DynamicBlocks.params("DESK", ed.doc).map(\.name), ["Width", "Chairs"])
        let rid = ed.doc.add(.insert(InsertGeom(block: "DESK", position: Vec2(5000, 0))))
        await ed.run("DYNPROP #\(rid)  1600 3")
        guard let e = ed.doc.entity(rid), case .insert(let ins) = e.geometry else { return XCTFail() }
        XCTAssertEqual(e.props[DynamicBlocks.baseProp], "DESK")
        XCTAssertNotEqual(ins.block, "DESK")
        guard let v = ed.doc.blocks[ins.block] else { return XCTFail("variant missing") }
        let polys = v.entities.compactMap { x -> PolylineGeom? in if case .polyline(let p) = x.geometry { return p }; return nil }
        XCTAssertEqual(polys.first.map { BBox2(points: $0.vertices.map(\.p)).max.x } ?? 0, 1600, accuracy: 1e-9)
        let circles = v.entities.compactMap { x -> CircleGeom? in if case .circle(let c) = x.geometry { return c }; return nil }
        XCTAssertEqual(circles.map(\.center.x).sorted(), [200, 600, 1000])
        // Saved and reopened: the reference keeps its state.
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entity(rid)?.props[DynamicBlocks.valuesProp], "Chairs=3;Width=1600")
        XCTAssertNotNil(back.blocks[ins.block])
        XCTAssertEqual(DynamicBlocks.params("DESK", back).count, 2)
        // Explode keeps the dynamic shape; RESETBLOCK restores the definition.
        await ed.run("RESETBLOCK #\(rid) ")
        guard case .insert(let r)? = ed.doc.entity(rid)?.geometry else { return XCTFail() }
        XCTAssertEqual(r.block, "DESK")
        XCTAssertNil(ed.doc.entity(rid)?.props[DynamicBlocks.valuesProp])
    }

    // MARK: Macros and scripts

    func testMacroPauseWaitsForUser() async {
        let ed = Editor()
        ed.runMacro("^C^C_LINE \\ @100,0 ;")
        var n = 0
        while !ed.pausedForUser && n < 10000 { await Task.yield(); n += 1 }
        XCTAssertTrue(ed.pausedForUser)
        ed.submit("10,20")
        await ed.waitIdle()
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(l.a, Vec2(10, 20)); close(l.b, Vec2(110, 20))
        XCTAssertEqual(UserAliases.macroTokens("LINE \\ 0,0;"), ["LINE", MacroPause.mark, "0,0"])
        XCTAssertEqual(UserAliases.macroTokens("LINE;0,0;100,0;;"), ["LINE", "0,0", "100,0", ""])
    }

    func testScriptDelayInterruptAndResume() async {
        let ed = Editor()
        let t0 = Date()
        await ed.run("DELAY 30")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(t0), 0.025)
        let task = Task { @MainActor in await ed.runScriptLines(["DELAY 2000", "LINE 0,0 10,0 ", "LINE 0,0 0,10 "]) }
        var n = 0
        while ed.isIdle && n < 100000 { await Task.yield(); n += 1 }
        ed.cancel()                                     // Escape during DELAY
        await task.value
        XCTAssertEqual(ed.pendingScript?.count, 2)
        XCTAssertEqual(ed.doc.entities.count, 0)
        await ed.run("RESUME")
        n = 0
        while ed.doc.entities.count < 2 && n < 200000 { await Task.yield(); n += 1 }
        await ed.waitIdle()
        XCTAssertEqual(ed.doc.entities.count, 2)
        XCTAssertNil(ed.pendingScript)
    }

    func testNewCommandsRegistered() async {
        let r = CommandRegistry(); BuiltinCommands.registerAll(r)
        for n in ["DIMJOGGED", "DIMJOGLINE", "GRADIENT", "HATCHSETORIGIN", "REVSTAMP", "TEXTMASK", "TEXTUNMASK", "TEXTFRAME", "FLATTEN", "CHSPACE",
                  "SPLINEDIT", "BLEND", "TRACE", "ROTATE90", "TXTEXP", "DIMREBASE", "SELECTINSTANCES", "BPARAMETER", "DYNPROP", "RESETBLOCK",
                  "DELAY", "RESUME", "MACRO", "JOG", "DJL", "SPE"] {
            XCTAssertNotNil(r.lookup(n), n)
        }
    }

    // MARK: Patterns, inscribed ellipse, selection, spot coordinates

    func testCustomPatFileLoadsAndPersists() async throws {
        let pat = """
        ;; test patterns
        *DIAGBOX, Diagonal boxes
        45, 0,0, 0,10
        135, 0,0, 0,10, 5,-5
        *BROKEN, bad
        0, 0,0
        """
        let parsed = HatchPatterns.parsePat(pat)
        XCTAssertEqual(parsed.map(\.name), ["DIAGBOX"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-test-\(UUID().uuidString).pat")
        try pat.write(to: url, atomically: true, encoding: .utf8)
        let ed = Editor()
        await ed.run("PATLOAD \(url.path)")
        XCTAssertNotNil(ed.doc.variable("HPPAT:DIAGBOX"))
        let sq = [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]]
        let segs = HatchPatterns.lines(loops: sq, pattern: "DIAGBOX", scale: 1, angle: 0)
        XCTAssertFalse(segs.isEmpty)
        XCTAssertTrue(HatchPatterns.allNames.contains("DIAGBOX"))
        // Reopened drawings bring their patterns along.
        HatchPatterns.custom["DIAGBOX"] = nil; HatchPatterns.customSources["DIAGBOX"] = nil
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        _ = Editor(document: back)
        XCTAssertEqual(HatchPatterns.lines(loops: sq, pattern: "DIAGBOX", scale: 1, angle: 0).count, segs.count)
        for n in ["ANSI33", "ANSI34", "ANSI35", "ANSI36", "ANSI38", "SQUARE", "ZIGZAG", "AR-B816", "AR-HBONE"] {
            XCTAssertFalse(HatchPatterns.lines(loops: [sq[0].map { $0 * 20 }], pattern: n, scale: 1, angle: 0).isEmpty, n)
        }
    }

    func testEllipseInscribedInParallelogram() async {
        let p0 = Vec2(0, 0), p1 = Vec2(200, 50), p3 = Vec2(40, 120), p2 = p1 + p3 - p0
        guard let e = InscribedEllipse.inParallelogram(p0, p1, p2, p3) else { return XCTFail() }
        let u = (p1 - p0) / 2, v = (p3 - p0) / 2, c = p0 + u + v
        close(e.center, c, 1e-12)
        // Every point satisfies α² + β² = 1 in the conjugate frame, and the side midpoints are on the curve (tangency).
        let det = u.cross(v)
        for k in 0..<16 {
            let q = e.point(at: Double(k) * .pi / 8) - c
            let a = q.cross(v) / det, b = u.cross(q) / det
            XCTAssertEqual(a * a + b * b, 1, accuracy: 1e-9)
        }
        for m in [(p0 + p1) / 2, (p1 + p2) / 2, (p2 + p3) / 2, (p3 + p0) / 2] {
            let q = m - c; let a = q.cross(v) / det, b = u.cross(q) / det
            XCTAssertEqual(a * a + b * b, 1, accuracy: 1e-9)
        }
        XCTAssertLessThanOrEqual(e.ratio, 1)
        XCTAssertNil(InscribedEllipse.inParallelogram(p0, p1, p2 + Vec2(30, 0), p3))
        // A square gives its incircle; the command uses three corners.
        let ed = Editor()
        await ed.run("ELLIPSEQUAD 0,0 100,0 0,100")
        guard case .ellipse(let s)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        close(s.center, Vec2(50, 50), 1e-12); XCTAssertEqual(s.majorAxis.length, 50, accuracy: 1e-9); XCTAssertEqual(s.ratio, 1, accuracy: 1e-9)
    }

    func testSelectAllLastPreviousDeselect() async {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "LOCKED")); ed.doc.layers.append(Layer(name: "OFF"))
        if let i = ed.doc.layerIndex("LOCKED") { ed.doc.layers[i].locked = true }
        if let i = ed.doc.layerIndex("OFF") { ed.doc.layers[i].visible = false }
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(1, 0))))
        ed.doc.add(.line(LineGeom(.zero, Vec2(2, 0))), layer: "LOCKED")
        ed.doc.add(.line(LineGeom(.zero, Vec2(3, 0))), layer: "OFF")
        let d = ed.doc.add(.line(LineGeom(.zero, Vec2(4, 0))))
        await ed.run("SELECT ALL ")
        XCTAssertEqual(ed.selection, [a, d])
        await ed.run("DESELECT")
        XCTAssertTrue(ed.selection.isEmpty)
        await ed.run("SELECTPREVIOUS")
        XCTAssertEqual(ed.selection, [a, d])
        ed.selection = []
        await ed.run("SELECT L ")
        XCTAssertEqual(ed.selection, [d])
    }

    func testSpotCoordinateFollowsItsPoint() async {
        let ed = Editor()
        ed.doc.setVariable("NORTHING0", "5000000")
        await ed.run("SPOTCOORD 1200,3400 2000,4000")
        guard let e = ed.doc.entities.last, case .leader(let l) = e.geometry else { return XCTFail() }
        XCTAssertEqual(l.text, "N 5003400\nE 1200")
        await ed.run("MOVE #\(e.id)  0,0 100,-400")
        guard case .leader(let m)? = ed.doc.entity(e.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(m.text, "N 5003000\nE 1300")
    }

    func testLeaderStyleGraphicsAndObjectScales() async {
        let ed = Editor()
        await ed.run("MLEADERSTYLE N NOTES 3.5 N . Dot 2 10 Y")
        guard let st = AnnotationToolCommands.currentMLeaderStyle(ed) else { return XCTFail() }
        XCTAssertEqual(st.arrow, "dot"); XCTAssertEqual(st.arrowSize, 2); XCTAssertEqual(st.landing, 10); XCTAssertTrue(st.frame)
        await ed.run("MLEADER 0,0 50,20 Note")
        guard let e = ed.doc.entities.last, case .leader = e.geometry else { return XCTFail() }
        guard let items = DraftRendering.items(e, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        // Leader line with the landing, a dot arrowhead (filled circle), the text and its frame.
        guard case .stroke(let pts, false, _) = items[0] else { return XCTFail() }
        close(pts.last!, Vec2(60, 20))
        XCTAssertTrue(items.contains { if case .fill(let l, _) = $0 { return l[0].count == 16 }; return false })
        XCTAssertTrue(items.contains { if case .text(let t, _, _) = $0 { return t.content == "Note" && t.position.x > 60 }; return false })
        XCTAssertTrue(items.contains { if case .stroke(let p, true, _) = $0 { return p.count == 4 }; return false })
        // A plain style keeps the default leader drawing.
        await ed.run("MLEADERSTYLE N PLAIN 3.5 N . Closed 0 0 N")
        await ed.run("MLEADER 0,0 50,-20 Plain")
        XCTAssertNil(DraftRendering.items(ed.doc.entities.last!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25))
        // Object scales: shown only at listed scales when ANNOALLVISIBLE is 0.
        let tid = ed.doc.add(.text(TextGeom(position: .zero, height: 250, content: "A")))
        ed.doc.setVariable("CANNOSCALE", "1:100")
        await ed.run("OBJECTSCALE #\(tid)  Add 1:50 Add Current ")
        XCTAssertEqual(ed.doc.entity(tid)?.props[DraftRendering.annoScalesProp], "1:50;1:100")
        ed.doc.setVariable("ANNOALLVISIBLE", "0")
        XCTAssertGreaterThan(DraftRendering.items(ed.doc.entity(tid)!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25)?.count ?? 0, 0)
        ed.doc.setVariable("CANNOSCALE", "1:200")
        XCTAssertEqual(DraftRendering.items(ed.doc.entity(tid)!, doc: ed.doc, options: DrawOptions(), color: .white, lineweight: 0.25)?.count, 0)
        await ed.run("OBJECTSCALE #\(tid)  Delete 1:50 ")
        XCTAssertEqual(ed.doc.entity(tid)?.props[DraftRendering.annoScalesProp], "1:100")
    }

    func testAutocompleteRankingAndPickfirst() async {
        let r = CommandRegistry(); BuiltinCommands.registerAll(r)
        XCTAssertTrue(r.complete("LI").contains("LINE"))
        r.usage["LIST"] = 5
        XCTAssertEqual(r.complete("LI").first, "LIST")
        XCTAssertTrue(r.complete("ARC").contains("DIMARC"))
        XCTAssertLessThan(r.complete("ARC").firstIndex(of: "ARC") ?? 99, r.complete("ARC").firstIndex(of: "DIMARC") ?? 0)
        let ed = Editor()
        let a = ed.doc.add(.line(LineGeom(.zero, Vec2(10, 0))))
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 5), Vec2(10, 5))))
        ed.selection = [a]
        await ed.run("ERASE")                       // noun-verb: the pre-selection is used
        XCTAssertNil(ed.doc.entity(a))
        ed.doc.setVariable("PICKFIRST", "0")
        let c = ed.doc.add(.line(LineGeom(Vec2(0, 9), Vec2(10, 9))))
        ed.selection = [c]
        await ed.run("ERASE #\(b) ")               // verb-noun only: the prompt decides
        XCTAssertNil(ed.doc.entity(b)); XCTAssertNotNil(ed.doc.entity(c))
        XCTAssertGreaterThan(ed.registry.usage["ERASE"] ?? 0, 0)
    }

    func testPointStyleSymbols() async {
        var doc = ArchiDocument()
        let id = doc.add(.point(Vec2(10, 10)))
        let e = doc.entity(id)!
        XCTAssertNil(DraftRendering.items(e, doc: doc, options: DrawOptions(), color: .white, lineweight: 0.25))
        doc.setVariable("PDMODE", "35"); doc.setVariable("PDSIZE", "4")
        guard let items = DraftRendering.items(e, doc: doc, options: DrawOptions(), color: .white, lineweight: 0.25) else { return XCTFail() }
        XCTAssertEqual(items.count, 3)                                      // X + circle
        if case .stroke(let p, _, _) = items[0] { close(p[0], Vec2(8, 8)); close(p[1], Vec2(12, 12)) } else { XCTFail() }
        doc.setVariable("PDMODE", "1")
        XCTAssertEqual(DraftRendering.items(e, doc: doc, options: DrawOptions(), color: .white, lineweight: 0.25)?.count, 0)
        doc.setVariable("PDMODE", "66")
        XCTAssertEqual(DraftRendering.items(e, doc: doc, options: DrawOptions(), color: .white, lineweight: 0.25)?.count, 3)   // plus + square
    }

    func testBattmanReorderAndModes() async {
        let ed = Editor()
        let a = Entity(geometry: .text(TextGeom(position: .zero, height: 1, content: "A")), props: ["attdef": "A", "default": "1"])
        let b = Entity(geometry: .text(TextGeom(position: .zero, height: 1, content: "B")), props: ["attdef": "B", "default": "2"])
        ed.doc.blocks["T"] = Block(name: "T", entities: [Entity(geometry: .line(LineGeom(.zero, Vec2(1, 0)))), a, b])
        await ed.run("BATTMAN T B UP")
        XCTAssertEqual(ed.doc.blocks["T"]?.entities.compactMap { $0.props["attdef"] }, ["B", "A"])
        await ed.run("BATTMAN T A Mode C I ")
        let def = ed.doc.blocks["T"]!.entities.first { $0.props["attdef"] == "A" }!
        XCTAssertEqual(def.props[AttributeModes.prop], "IC"); XCTAssertEqual(def.props["invisible"], "1")
        await ed.run("INSERT T 0,0 1 1 0 9")
        guard case .insert(let i)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(i.attributes["B"], "9"); XCTAssertEqual(i.attributes["A"], "1")
    }
}
