// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Roofs by extrusion, shape-edited flat roofs, stairs by sketch, slab edges and schedule images.
@MainActor
final class BIMRound7FormsTests: XCTestCase {
    func bounds(_ gs: [MeshGroup]) -> BBox3 { gs.reduce(BBox3.empty) { var b = $0; if !$1.mesh.isEmpty { b.add($1.mesh.bounds.min); b.add($1.mesh.bounds.max) }; return b } }
    func volume(_ gs: [MeshGroup]) -> Double { gs.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) } }

    // MARK: BIM-057

    func testRoofByExtrusion() async {
        let ed = Editor()
        // Gable profile 6000 wide, 1500 high, drawn in plan.
        ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 20000), Vec2(3000, 21500), Vec2(6000, 20000)])))
        await ed.run("ROOFEXTRUSION 3000,21500 0,0 6000,0 10000 3000 200 No")
        guard let el = ed.doc.elements.last, case .roof(let g) = el.geometry, let ex = g.extrusion else { return XCTFail("no roof") }
        XCTAssertEqual(ex.profile.count, 3)
        let faces = RoofShapes.faces(g).faces
        XCTAssertEqual(faces.count, 2)
        // Ridge at x = 3000 is 1500 above the eave, eaves at 0.
        XCTAssertEqual(faces[0].height(Vec2(3000, 5000)), 1500, accuracy: 1e-6)
        XCTAssertEqual(faces[1].height(Vec2(6000, 5000)), 0, accuracy: 1e-6)
        let b = bounds(MeshBuilder.groups(for: el, doc: ed.doc))
        XCTAssertEqual(b.min.x, 0, accuracy: 1); XCTAssertEqual(b.max.x, 6000, accuracy: 1)
        XCTAssertEqual(b.min.y, 0, accuracy: 1); XCTAssertEqual(b.max.y, 10000, accuracy: 1)
        XCTAssertEqual(b.max.z, 3000 + 1500, accuracy: 300)
        XCTAssertGreaterThan(volume(MeshBuilder.groups(for: el, doc: ed.doc)), 0)
        // Plan: footprint outline plus the ridge line.
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).first { $0.id == el.id }?.items ?? []
        let ridge = items.contains { if case .stroke(let p, _, _) = $0 { return p.count == 2 && abs(p[0].x - 3000) < 1e-6 && abs(p[1].x - 3000) < 1e-6 }; return false }
        XCTAssertTrue(ridge)
        // The gable wall under the roof edge is filled up to the roof (ridge higher than eaves).
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 200, height: 3000)))
        let wb = bounds(MeshBuilder.groups(for: ed.doc.element(w)!, doc: ed.doc))
        XCTAssertGreaterThan(wb.max.z, 3000 + 1000)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.element(el.id)?.geometry, el.geometry)
    }

    // MARK: BIM-063

    func testShapeEditedFlatRoof() async {
        let ed = Editor()
        var r = RoofGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)], kind: .flat, thickness: 300, overhang: 0, baseOffset: 3000)
        let id = ed.doc.addElement(.roof(r))
        ed.selection = [id]
        await ed.run("ROOFSHAPEPOINTS Add 5000,4000 -80 10000,8000 50")
        guard case .roof(let g)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.shapePoints?.count, 2)
        let faces = RoofShapes.faces(g).faces
        XCTAssertGreaterThanOrEqual(faces.count, 4)
        func h(_ p: Vec2) -> Double? { faces.first { GeometryOps.pointInPolygon(p, $0.poly) }.map { $0.height(p) } }
        XCTAssertEqual(h(Vec2(5000, 4000.001)) ?? 99, -80, accuracy: 1e-3, "drain point")
        XCTAssertEqual(h(Vec2(9999.9, 7999.8)) ?? 99, 50, accuracy: 1, "raised corner")
        XCTAssertEqual(h(Vec2(1, 1)) ?? 99, 0, accuracy: 1)
        let area = faces.reduce(0) { $0 + abs(GeometryOps.signedArea($1.poly)) }
        XCTAssertEqual(area, 8e7, accuracy: 1)
        XCTAssertGreaterThan(volume(MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc)), 0)
        // Plan shows the valley/ridge lines of the TIN.
        let lines = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).first { $0.id == id }?.items.count ?? 0
        XCTAssertGreaterThan(lines, 2)
        ed.selection = [id]
        await ed.run("ROOFSHAPEPOINTS Reset")
        guard case .roof(let g2)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertNil(g2.shapePoints)
        r.shapePoints = [Vec3(3, 3, 1)]
        XCTAssertEqual(try! ArchiFile.decode(ArchiFile.encode({ var d = ArchiDocument(); d.addElement(.roof(r)); return d }())).elements[0].geometry, .roof(r))
    }

    // MARK: BIM-066

    func testStairBySketch() async {
        let ed = Editor()
        // Eight risers on a gently curved flight: 1000 wide, goings ~280 on the walking line.
        var ids: [EntityID] = []
        for i in 0..<8 {
            let a = Double(i) * 0.05, x = Double(i) * 280
            let c = Vec2(x, 0), d = Vec2(-sin(a), cos(a)) * 500
            ids.append(ed.doc.add(.line(LineGeom(c - d, c + d))))
        }
        ed.selection = Set(ids)
        await ed.run("STAIRSKETCH Forward 1400 Yes")
        guard let el = ed.doc.elements.last, case .stair(let g) = el.geometry, let sk = g.sketchRisers else { return XCTFail("no stair") }
        XCTAssertEqual(sk.count, 8); XCTAssertEqual(g.riserCount, 8)
        XCTAssertEqual(g.riserHeight, 175, accuracy: 1e-9)
        XCTAssertTrue(ed.doc.entities.isEmpty, "sketch lines deleted")
        XCTAssertTrue(Round7Shapes.check(g, units: ed.doc.units).isEmpty, "\(Round7Shapes.check(g, units: ed.doc.units))")
        let l = StairShapes.layout(g)
        XCTAssertEqual(l.treads.count, 7)
        let b = bounds(MeshBuilder.groups(for: el, doc: ed.doc))
        XCTAssertEqual(b.max.z, 7 * 175, accuracy: 1e-6)
        XCTAssertFalse(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).filter { $0.id == el.id }.isEmpty)
        // Rules: too steep and too short goings are reported.
        var steep = g; steep.totalRise = 8 * 220
        XCTAssertTrue(Round7Shapes.check(steep, units: ed.doc.units).contains { $0.contains("Riser") })
        let dir = (((sk[1][0] + sk[1][1]) - (sk[0][0] + sk[0][1])) / 2).normalized
        var tight = g; tight.sketchRisers = sk.enumerated().map { i, r in r.map { $0 - dir * (Double(i) * 100) } }
        XCTAssertTrue(Round7Shapes.check(tight, units: ed.doc.units).contains { $0.contains("Going") })
    }

    // MARK: BIM-051

    func testSlabEdges() async {
        let ed = Editor()
        let s = ed.doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 2000), Vec2(0, 2000)], thickness: 200)))
        let v0 = volume(MeshBuilder.groups(for: ed.doc.element(s)!, doc: ed.doc))
        await ed.run("SLABEDGE 2000,0 Upstand Picked 150 1000 Concrete")
        guard case .slab(let g)? = ed.doc.element(s)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.edges?.count, 1); XCTAssertEqual(g.edges?[0].edge, 0)
        let gs = MeshBuilder.groups(for: ed.doc.element(s)!, doc: ed.doc)
        XCTAssertEqual(volume(gs) - v0, 4000 * 150 * 1000, accuracy: 1)
        XCTAssertEqual(bounds(gs.filter { $0.kind == "slabEdge" }).max.z, 1000, accuracy: 1e-6)
        await ed.run("SLABEDGE 4000,1000 Fascia All 50 400 Concrete")
        guard case .slab(let g2)? = ed.doc.element(s)?.geometry else { return XCTFail() }
        XCTAssertEqual(g2.edges?.count, 2)
        let fas = bounds(MeshBuilder.groups(for: ed.doc.element(s)!, doc: ed.doc).filter { $0.kind == "slabEdge" && $0.mesh.bounds.min.z < -1 })
        XCTAssertEqual(fas.min.z, -400, accuracy: 1e-6); XCTAssertEqual(fas.min.x, -50, accuracy: 1e-6)
        // Plan outlines and persistence.
        XCTAssertGreaterThanOrEqual(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).first { $0.id == s }?.items.count ?? 0, 6)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.element(s)?.geometry, ed.doc.element(s)?.geometry)
    }

    // MARK: DOC-048

    func testScheduleTypeImages() async {
        let ed = Editor()
        let wall = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 200, height: 3000)))
        ed.doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: wall, offset: 1000, width: 900, height: 2100, typeName: "D1")))
        await ed.run("TYPEIMAGE D1 /tmp/door-d1.png")
        var def = ScheduleDefinition(name: "Doors", category: "doors", fields: [ScheduleField(name: "Type"), ScheduleField(name: "Image")])
        ed.doc.schedules = [def]
        let t = Schedules.evaluate(def, doc: ed.doc)
        XCTAssertEqual(t.rows.first?.cells, ["D1", "img:/tmp/door-d1.png"])
        Schedules.place(def, doc: &ed.doc, layout: nil, at: .zero, maxRows: 10, textHeight: 250)
        let tab = ed.doc.entities.last!
        let imgs = DrawListBuilder.items(for: tab, doc: ed.doc, options: DrawOptions()).compactMap { if case .image(let im) = $0 { return im }; return nil }
        XCTAssertEqual(imgs.count, 1); XCTAssertEqual(imgs.first?.path, "/tmp/door-d1.png")
        // Editing the image cell edits the type's image.
        let did = ed.doc.elements.last!.id
        XCTAssertTrue(Schedules.setValue("Image", "/tmp/other.png", of: did, doc: &ed.doc))
        XCTAssertEqual(ed.doc.variable("TYPEIMAGE.D1"), "/tmp/other.png")
        def.fields.append(ScheduleField(name: "Count"))
        XCTAssertEqual(Schedules.evaluate(def, doc: ed.doc).rows.first?.cells[1], "img:/tmp/other.png")
    }
}
