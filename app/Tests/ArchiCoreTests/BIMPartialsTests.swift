// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Levels, grids, compound walls, reveals, curtain walls, door/window variants, associative rooms and areas.
@MainActor
final class BIMPartialsTests: XCTestCase {
    func texts(_ es: [DrawEntry]) -> [TextGeom] { es.flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t }; return nil } }
    func grids(_ ed: Editor) -> [(EntityID, GridLineGeom)] { ed.doc.elements.compactMap { if case .gridLine(let g) = $0.geometry { return ($0.id, g) }; return nil } }
    func columns(_ ed: Editor) -> [(EntityID, ColumnGeom)] { ed.doc.elements.compactMap { if case .column(let c) = $0.geometry { return ($0.id, c) }; return nil } }

    // MARK: BIM-002 / BIM-004 levels

    func testLevelOffsetCopyExtentsAndHeads() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 6000,4000 0,4000 C")
        await ed.run("LEVEL Offset 0 1500 Mezzanine")
        let mez = try XCTUnwrap(ed.doc.levels.first { $0.name == "Mezzanine" })
        XCTAssertEqual(mez.elevation, 1500, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.currentLevel, mez.id)
        // Copy level 0 with its walls 6000 up.
        await ed.run("LEVEL Copy 0 6000 Upper")
        let up = try XCTUnwrap(ed.doc.levels.first { $0.name == "Upper" })
        XCTAssertEqual(up.elevation, 6000, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.elements.filter { $0.level == up.id }.count, 4)
        // Moving the level moves its hosted elements in 3D.
        await ed.run("LEVEL Elevation Upper 7000")
        let wallUp = try XCTUnwrap(ed.doc.elements.first { $0.level == up.id })
        let z0 = MeshBuilder.groups(for: wallUp, doc: ed.doc).flatMap(\.mesh.positions).map(\.z).min() ?? 0
        XCTAssertEqual(z0, 7000, accuracy: 1e-6)
        // Heads at both ends in a south elevation: two name labels.
        await ed.run("LEVEL Heads 0 Both")
        var south = ElevationBuilder.entries(doc: ed.doc, view: .elevationSouth)
        XCTAssertEqual(texts(south).filter { $0.content == "Ground Floor" }.count, 2)
        // Extents along X: the datum spans them; seen end-on (east elevation) the level is hidden.
        await ed.run("LEVEL Extents Upper -1000,0 3000,0")
        XCTAssertTrue(ed.doc.level(up.id)!.hasExtents)
        south = ElevationBuilder.entries(doc: ed.doc, view: .elevationSouth)
        let line = south.flatMap(\.items).compactMap { item -> [Vec2]? in
            if case .stroke(let p, _, let st) = item, st.color == ElevationBuilder.annoColor, !st.dash.isEmpty, p.count == 2, abs(p[0].y - 7000) < 1e-6, abs(p[1].y - 7000) < 1e-6 { return p }; return nil }.first
        XCTAssertEqual(line.map { min($0[0].x, $0[1].x) } ?? 0, -1000, accuracy: 1e-6)
        XCTAssertEqual(line.map { max($0[0].x, $0[1].x) } ?? 0, 3000, accuracy: 1e-6)
        let east = ElevationBuilder.entries(doc: ed.doc, view: .elevationEast)
        XCTAssertFalse(texts(east).contains { $0.content == "Upper" })
        XCTAssertTrue(texts(east).contains { $0.content == "Ground Floor" })
        // Round trip.
        let data = try JSONEncoder().encode(ed.doc)
        let back = try JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(back.level(up.id)?.extentEnd, Vec2(3000, 0))
        XCTAssertEqual(back.level(0)?.heads, "both")
        // Old files without the new keys still decode.
        let old = try JSONDecoder().decode(Level.self, from: Data(#"{"id":3,"name":"L3","elevation":9000,"height":3000}"#.utf8))
        XCTAssertFalse(old.hasExtents); XCTAssertTrue(old.headEnds.end)
    }

    // MARK: BIM-005 / BIM-006 grids

    func testGridNumberingArcMultiAndHostedColumns() async throws {
        let ed = Editor()
        await ed.run("GRID 0,-1000 0,9000 ")
        await ed.run("GRID 6000,-1000 6000,9000 ")
        await ed.run("GRID 12000,-1000 12000,9000 ")
        XCTAssertEqual(grids(ed).map(\.1.label), ["1", "2", "3"])
        await ed.run("GRID -1000,0 13000,0 ")
        await ed.run("GRID M -1000,8000 6000,8000 13000,9000  ")
        let g = grids(ed)
        XCTAssertEqual(g.map(\.1.label), ["1", "2", "3", "A", "B"])
        XCTAssertEqual(g[4].1.vertices.count, 3)
        XCTAssertEqual(g[4].1.vertices[1].x, 6000, accuracy: 1e-6); XCTAssertEqual(g[4].1.vertices[1].y, 8000, accuracy: 1e-6)
        // Arc grid through three points.
        await ed.run("GRID A -1000,4000 6000,5000 13000,4000 ")
        let arc = grids(ed).last!.1
        XCTAssertEqual(arc.label, "C")
        XCTAssertGreaterThan(abs(arc.bulge), 0)
        let mid = arc.points[arc.points.count / 2]
        XCTAssertEqual(mid.y, 5000, accuracy: 30)
        // Columns at every intersection, hosted by their grids.
        await ed.run("COLUMN G ")
        XCTAssertEqual(columns(ed).count, 9)
        XCTAssertTrue(ed.doc.elements.filter { if case .column = $0.geometry { return true }; return false }.allSatisfy { $0.props[GridHosting.prop] != nil })
        // Move grid 2: its three columns follow (straight, arc and multi-segment crossings).
        let g2 = g[1].0
        ed.selection = [g2]
        await ed.run("MOVE 0,0 500,0")
        let onG2 = columns(ed).filter { abs($0.1.position.x - 6500) < 1e-6 }
        XCTAssertEqual(onG2.count, 3)
        XCTAssertFalse(columns(ed).contains { abs($0.1.position.x - 6000) < 1e-6 })
        // A column typed exactly on an intersection is hosted too.
        await ed.run("ERASE ALL ")
        await ed.run("GRID 0,-1000 0,5000 ")
        await ed.run("GRID -1000,0 5000,0 ")
        await ed.run("COLUMN 0,0 ")
        XCTAssertNotNil(ed.doc.elements.last?.props[GridHosting.prop])
        // Persistence of multi-segment grids.
        let multi = GridLineGeom(through: [Vec2(0, 0), Vec2(1000, 500), Vec2(2000, 0)], label: "Z")!
        let back = try JSONDecoder().decode(GridLineGeom.self, from: try JSONEncoder().encode(multi))
        XCTAssertEqual(back.vertices[1].x, 1000, accuracy: 1e-9); XCTAssertEqual(back.vertices[1].y, 500, accuracy: 1e-9)
    }

    func testRadialGridHostingAndSectionBubbles() async throws {
        var doc = ArchiDocument()
        let gs = try XCTUnwrap(GridSystems.radial(center: .zero, startAngle: 0, angles: [.pi / 4, .pi / 4], innerRadius: 5000, radii: [3000], overhang: 1000))
        for g in gs { doc.addElement(.gridLine(g)) }
        let xs = GridHosting.allIntersections(doc)
        XCTAssertEqual(xs.count, 6, "3 radial lines × 2 arcs")
        for x in xs { XCTAssertTrue(abs(x.point.length - 5000) < 1e-6 || abs(x.point.length - 8000) < 1e-6) }
        // Hosted column follows when the arc grid radius changes.
        let p = xs.first { abs($0.point.length - 8000) < 1e-6 && abs($0.point.y) < 1e-6 }!
        let cid = doc.addElement(.column(ColumnGeom(position: p.point)))
        doc.elements[doc.elementIndex(cid)!].props[GridHosting.prop] = "\(p.a),\(p.b)"
        let arcID = [p.a, p.b].first { if case .gridLine(let g)? = doc.element($0)?.geometry { return abs(g.bulge) > 0 }; return false }!
        let ai = doc.elementIndex(arcID)!
        guard case .gridLine(var ag) = doc.elements[ai].geometry else { return XCTFail() }
        let k = 9000.0 / 8000
        ag.start = ag.start * k; ag.end = ag.end * k
        doc.elements[ai].geometry = .gridLine(ag)
        XCTAssertTrue(GridHosting.updateAll(&doc))
        guard case .column(let c)? = doc.element(cid)?.geometry else { return XCTFail() }
        XCTAssertEqual(c.position.length, 9000, accuracy: 1e-6)
        // A section along the X axis shows the two arc grids crossing it.
        doc.addElement(.wall(WallGeom(start: Vec2(0, -500), end: Vec2(10000, -500))))
        let sec = ElevationBuilder.entries(doc: doc, view: .section, sectionLine: (Vec2(-1000, 100), Vec2(12000, 100)))
        let labels = texts(sec).map(\.content)
        XCTAssertTrue(labels.contains("A")); XCTAssertTrue(labels.contains("B"))
    }

    // MARK: BIM-014 compound walls / DOC-024 cut patterns

    func testCompoundWallPliesIn3DAndSection() throws {
        var doc = ArchiDocument()
        let id = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 365, wallType: "Exterior Brick 365")))
        let gs = MeshBuilder.groups(for: doc.element(id)!, doc: doc).filter { $0.kind == "wall" }
        XCTAssertEqual(gs.map(\.material), ["Plaster", "Brick", "Insulation", "Plaster"])
        // Each ply's volume ≈ its thickness × length × height.
        let vols = gs.map { MeshTools.signedVolume($0.mesh) }
        XCTAssertEqual(vols[1], 240 * 5000 * 3000, accuracy: 240 * 5000 * 3000 * 0.01)
        XCTAssertEqual(vols.reduce(0, +), 365 * 5000 * 3000, accuracy: 365 * 5000 * 3000 * 0.01)
        // Curved compound wall.
        var d2 = ArchiDocument()
        let cid = d2.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 365, bulge: 0.4, wallType: "Exterior Brick 365")))
        XCTAssertEqual(MeshBuilder.groups(for: d2.element(cid)!, doc: d2).filter { $0.kind == "wall" }.count, 4)
        // Section across the wall: brick hatched (ANSI31), insulation with the batt pattern, strokes present.
        let sec = ElevationBuilder.entries(doc: doc, view: .section, sectionLine: (Vec2(2500, -2000), Vec2(2500, 2000)))
        let hatchStrokes = sec.filter { $0.id == id }.flatMap(\.items).filter { if case .stroke(_, false, let st) = $0 { return st.lineweight == 0.13 }; return false }
        XCTAssertGreaterThan(hatchStrokes.count, 10)
        // SECTIONPOCHE = solid restores the dark poché.
        doc.setVariable("SECTIONPOCHE", "solid")
        let solid = ElevationBuilder.entries(doc: doc, view: .section, sectionLine: (Vec2(2500, -2000), Vec2(2500, 2000)))
        XCTAssertTrue(solid.flatMap(\.items).contains { if case .fill(_, let c) = $0 { return c == ElevationBuilder.pocheColor }; return false })
    }

    // MARK: BIM-021 reveals

    func testWallRevealCutsGroove() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 4000,0 ")
        let id = ed.doc.elements[0].id
        let before = MeshTools.signedVolume(MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc)[0].mesh)
        ed.selection = [id]
        await ed.run("WALLSWEEP Reveal Rect 20 30 Left 1500")
        guard case .wall(let w)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(w.sweeps.count, 1); XCTAssertTrue(w.sweeps[0].isReveal)
        let gs = MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc)
        XCTAssertFalse(gs.contains { $0.kind == "wallSweep" }, "reveals add no sweep solid")
        let after = MeshTools.signedVolume(gs[0].mesh)
        XCTAssertEqual(before - after, 20 * 30 * 4000, accuracy: 20 * 30 * 4000 * 0.05)
        let back = try JSONDecoder().decode(WallSweep.self, from: try JSONEncoder().encode(w.sweeps[0]))
        XCTAssertTrue(back.isReveal)
        XCTAssertFalse(try JSONDecoder().decode(WallSweep.self, from: Data(#"{"profile":"rect","depth":50,"height":150,"elevation":0,"side":1}"#.utf8)).isReveal)
    }

    // MARK: BIM-028 embedded curtain wall

    func testCurtainWallEmbeddedInWallCutsIt() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 ")
        let wid = ed.doc.elements[0].id
        let full = MeshTools.signedVolume(MeshBuilder.groups(for: ed.doc.element(wid)!, doc: ed.doc)[0].mesh)
        await ed.run("CURTAINWALL E 4000,0 2000,0 6000,0")
        guard let cw = ed.doc.elements.last, case .curtainWall(let g) = cw.geometry else { return XCTFail() }
        XCTAssertEqual(cw.props["hostWall"], "\(wid)")
        XCTAssertEqual(g.length, 4000, accuracy: 1e-6)
        let cut = MeshTools.signedVolume(MeshBuilder.groups(for: ed.doc.element(wid)!, doc: ed.doc)[0].mesh)
        XCTAssertEqual(full - cut, 4000 * 200 * 3000, accuracy: 1000)
        // Plan: the wall is split into two cut pieces.
        let ctx = PlanRepresentation.context(ed.doc)
        let f = try XCTUnwrap(ctx.frames[wid])
        XCTAssertEqual(ctx.pieces(f).count, 2)
    }

    // MARK: BIM-036 / BIM-037 variants

    func testDoorAndWindowVariants() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 10000,0 ")
        await ed.run("DOOR Style pocket 2000,0 ")
        await ed.run("DOOR Style bifold 5000,0 ")
        await ed.run("WINDOW Style tiltturn 7000,0 ")
        await ed.run("WINDOW Style pivot 9000,0 ")
        let ops = ed.doc.elements.compactMap { el -> OpeningGeom? in if case .opening(let o) = el.geometry { return o }; return nil }
        XCTAssertEqual(ops.map(\.variant), [.pocket, .biFold, .tiltTurn, .pivot])
        XCTAssertEqual(ops[0].doorStyle, .sliding); XCTAssertEqual(ops[1].doorStyle, .folding)
        // Distinct plan symbols and 3D for each.
        for el in ed.doc.elements where el.typeName != "wall" {
            let items = PlanRepresentation.items(el, doc: ed.doc)
            XCTAssertFalse(items.isEmpty)
            XCTAssertFalse(MeshBuilder.groups(for: el, doc: ed.doc).isEmpty)
        }
        let pocket = ed.doc.elements[1]
        var plain = pocket; if case .opening(var o) = plain.geometry { o.variant = nil; plain.geometry = .opening(o) }
        XCTAssertNotEqual(PlanRepresentation.items(pocket, doc: ed.doc), PlanRepresentation.items(plain, doc: ed.doc))
        let data = try JSONEncoder().encode(ed.doc)
        let back = try JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(back.elements.compactMap { el -> OpeningVariant? in if case .opening(let o) = el.geometry { return o.variant }; return nil }, [OpeningVariant.pocket, .biFold, .tiltTurn, .pivot])
        // Types carry the variant.
        XCTAssertEqual(ed.doc.openingType("Pocket Door 900x2100")?.variant, .pocket)
        await ed.run("DOOR T \"Bi-fold Door 1600x2100\" 3500,0 ")
        if case .opening(let o)? = ed.doc.elements.last?.geometry { XCTAssertEqual(o.variant, .biFold) } else { XCTFail() }
    }

    // MARK: BIM-090 / BIM-091 / BIM-093 associative rooms and areas

    func testRoomsAndAreasFollowWalls() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,4000 0,4000 C")
        await ed.run("ROOM 2000,2000 ")
        let rid = try XCTUnwrap(ed.doc.elements.last?.id)
        await ed.run("AREAPLAN 2000,2000 ")
        let aid = try XCTUnwrap(ed.doc.elements.last?.id)
        func area(_ id: EntityID) -> Double { if case .space(let s)? = ed.doc.element(id)?.geometry { return abs(GeometryOps.signedArea(s.boundary)) }; return 0 }
        XCTAssertEqual(area(rid), 7800 * 3800, accuracy: 1)
        XCTAssertEqual(area(aid), 8200 * 4200, accuracy: 1)
        // Stretch the east wall 2 m: room and gross area update without ROOMUPDATE.
        ed.transaction("Stretch") { doc in
            for i in doc.elements.indices {
                guard case .wall(var w) = doc.elements[i].geometry else { continue }
                if abs(w.start.x - 8000) < 1e-6 { w.start.x = 10000 }
                if abs(w.end.x - 8000) < 1e-6 { w.end.x = 10000 }
                doc.elements[i].geometry = .wall(w)
            }
        }
        XCTAssertEqual(area(rid), 9800 * 3800, accuracy: 9800 * 3800 * 0.01)
        XCTAssertEqual(area(aid), 10200 * 4200, accuracy: 10200 * 4200 * 0.01)
        // Separation line splits the room at x = 5000 (room keeps its seed side).
        await ed.run("ROOMSEPARATOR 5000,0 5000,4000 ")
        XCTAssertEqual(area(rid), 4900 * 3800, accuracy: 4900 * 3800 * 0.01)
        // Undo restores.
        ed.undo()
        XCTAssertEqual(area(rid), 9800 * 3800, accuracy: 9800 * 3800 * 0.01)
        // Room tags read the updated area.
        let tagText = PlanRepresentation.items(ed.doc.element(rid)!, doc: ed.doc).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }.joined(separator: " ")
        XCTAssertTrue(tagText.contains("37.24") || tagText.contains("37.2"), tagText)
    }

    // MARK: BIM-013 walls along splines and ellipses

    func testWallsFromSplineAndEllipse() async throws {
        let ed = Editor()
        let sid = ed.doc.add(.spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 0), Vec2(3000, 4000), Vec2(7000, -3000), Vec2(10000, 1000)])))
        ed.selection = [sid]
        await ed.run("WALLBYLINES 200 3000 Center No")
        let walls = ed.doc.elements.compactMap { el -> WallGeom? in if case .wall(let w) = el.geometry { return w }; return nil }
        XCTAssertGreaterThan(walls.count, 1)
        XCTAssertTrue(walls.contains { abs($0.bulge) > 1e-6 }, "curved segments are arc walls")
        for k in 1..<walls.count { XCTAssertTrue(walls[k].start.isClose(walls[k - 1].end, tol: 1e-6), "chain is continuous") }
        // Every point of the spline lies on the wall chain within the fitting tolerance.
        let chain = walls.flatMap { w -> [Vec2] in
            guard abs(w.bulge) > 1e-12 else { return [w.start, w.end] }
            let a = GeometryOps.bulgeArc(w.start, w.end, w.bulge)
            return (0...32).map { a.center + Vec2.polar(a.radius, a.start + a.sweep * Double($0) / 32) }
        }
        let pts = GeometryOps.tessellate(ed.doc.entity(sid)!.geometry, doc: ed.doc).flatMap { $0 }
        for p in pts { XCTAssertLessThan(GeometryOps.distance(from: p, toPolyline: chain), 5) }
        // 3D: arc walls mesh as curved solids.
        let el = ed.doc.elements.first { if case .wall(let w) = $0.geometry { return abs(w.bulge) > 1e-6 }; return false }!
        XCTAssertFalse(MeshBuilder.groups(for: el, doc: ed.doc).isEmpty)
        // A closed ellipse becomes a closed ring of arc walls.
        let ed2 = Editor()
        let eid = ed2.doc.add(.ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(6000, 0), ratio: 0.5)))
        ed2.selection = [eid]
        await ed2.run("WALLBYLINES 200 3000 Center No")
        let ring = ed2.doc.elements.compactMap { el -> WallGeom? in if case .wall(let w) = el.geometry { return w }; return nil }
        XCTAssertGreaterThanOrEqual(ring.count, 4)
        XCTAssertTrue(ring.last!.end.isClose(ring.first!.start, tol: 1e-6))
        // The ring bounds a room.
        await ed2.run("ROOM 0,0 ")
        guard case .space(let s)? = ed2.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), Double.pi * 5900 * 2900, accuracy: Double.pi * 6000 * 3000 * 0.03)
    }

    // MARK: BIM-111 toposurface from DXF contours

    func testTopoFromContourLayers() async throws {
        let ed = Editor()
        for (k, r) in [8000.0, 6000, 4000].enumerated() {
            var e = Entity(id: 0, layer: "C-TOPO-CONT", geometry: .circle(CircleGeom(.zero, r)))
            e.props["elevation"] = "\(k * 1000)"
            ed.doc.add(e)
        }
        // A 3D polyline contour with per-vertex z (as read from DXF POLYLINE flag 8).
        var p3 = Entity(id: 0, layer: "C-TOPO-CONT", geometry: .polyline(PolylineGeom(points: [Vec2(-9000, -9000), Vec2(9000, -9000)])))
        p3.props["vertexZ"] = "-500,-300"
        ed.doc.add(p3)
        ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 100))), layer: "A-WALL")
        await ed.run("TOPO Layer *CONT* 500")
        let topo = try XCTUnwrap(ed.doc.entities.last { $0.props["topo"] == "1" })
        guard case .solid(let s) = topo.geometry else { return XCTFail() }
        let zs = MeshTools.mesh(of: s).positions.map(\.z)
        XCTAssertEqual(zs.max() ?? 0, 2000, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(zs.min() ?? 0, -500 + 1e-6)
        XCTAssertTrue(TopoContours.wildcard("*cont*", "C-TOPO-CONT"))
        XCTAssertFalse(TopoContours.wildcard("C-?", "C-TOPO"))
    }
}
