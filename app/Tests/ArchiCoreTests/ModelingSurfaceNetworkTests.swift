// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Patch / network / offset / extend / trim / sculpt surfaces, paint bucket, soften edges and tape measure guides.
@MainActor
final class ModelingSurfaceNetworkTests: XCTestCase {
    func surface(_ ed: Editor, _ id: EntityID) -> SurfaceNetwork.IndexedMesh? {
        guard let s = ModelingCommands.solidOf(ed.doc, id) else { return nil }
        return (s.meshVertices, s.meshTriangles)
    }
    func lastSurface(_ ed: Editor) -> SurfaceNetwork.IndexedMesh? { surface(ed, ed.doc.entities.last!.id) }
    func poly3(_ ed: Editor, _ pts: [Vec3], closed: Bool = false) -> EntityID {
        var e = Entity(layer: "0", geometry: .polyline(PolylineGeom(points: pts.map(\.xy), closed: closed)))
        e.props["vertexZ"] = pts.map { fmt($0.z) }.joined(separator: ",")
        return ed.doc.add(e)
    }
    func squareSurface(_ ed: Editor, _ size: Double) -> EntityID {
        let v = [Vec3(0, 0, 0), Vec3(size, 0, 0), Vec3(size, size, 0), Vec3(0, size, 0)]
        let id = ed.doc.add(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: v, meshTriangles: [0, 1, 2, 0, 2, 3])))
        ed.doc.entities[ed.doc.entityIndex(id)!].props["surface"] = "test"
        return id
    }

    func testPatchPlanarAndCoons() async {
        let ed = Editor()
        let r = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)], closed: true)))
        await ed.run("SURFPATCH #\(r) ")
        XCTAssertEqual(SurfaceNetwork.area(lastSurface(ed)!), 1e6, accuracy: 1e-3)
        let q = poly3(ed, [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(1000, 1000, 500), Vec3(0, 1000, 0)], closed: true)
        await ed.run("SURFPATCH #\(q) ")
        let m = lastSurface(ed)!
        XCTAssertTrue(m.vertices.contains { $0.distance(to: Vec3(1000, 1000, 500)) < 1e-6 })
        XCTAssertGreaterThan(SurfaceNetwork.area(m), 1e6)
        // Four separate edges.
        let e1 = poly3(ed, [Vec3(0, 0, 0), Vec3(1000, 0, 0)]), e2 = poly3(ed, [Vec3(1000, 0, 0), Vec3(1000, 1000, 300)])
        let e3 = poly3(ed, [Vec3(0, 1000, 0), Vec3(1000, 1000, 300)]), e4 = poly3(ed, [Vec3(0, 0, 0), Vec3(0, 1000, 0)])
        await ed.run("SURFPATCH #\(e1),#\(e2),#\(e3),#\(e4) ")
        XCTAssertTrue(lastSurface(ed)!.vertices.contains { $0.distance(to: Vec3(1000, 1000, 300)) < 1e-6 })
    }

    func testNetworkSurfacePassesThroughCurves() async {
        let ed = Editor()
        let u0 = poly3(ed, [Vec3(0, 0, 0), Vec3(1000, 0, 0)])
        let u1 = poly3(ed, [Vec3(0, 500, 200), Vec3(500, 500, 250), Vec3(1000, 500, 200)])
        let u2 = poly3(ed, [Vec3(1000, 1000, 0), Vec3(0, 1000, 0)])     // reversed on purpose
        let v0 = poly3(ed, [Vec3(0, 0, 0), Vec3(0, 500, 200), Vec3(0, 1000, 0)])
        let v1 = poly3(ed, [Vec3(1000, 0, 0), Vec3(1000, 500, 200), Vec3(1000, 1000, 0)])
        await ed.run("SURFNETWORK #\(u2),#\(u0),#\(u1)  #\(v1),#\(v0) ")
        guard let m = lastSurface(ed), m.vertices.count > 20 else { return XCTFail("no network surface") }
        XCTAssertTrue(m.vertices.contains { $0.distance(to: Vec3(500, 500, 250)) < 1e-6 }, "passes through the middle U curve")
        XCTAssertTrue(m.vertices.contains { $0.distance(to: Vec3(0, 250, 100)) < 1e-6 }, "passes through the V curves")
        let flat = SurfaceNetwork.network(u: [[Vec3(0, 0, 0), Vec3(1000, 0, 0)], [Vec3(0, 1000, 0), Vec3(1000, 1000, 0)]],
                                          v: [[Vec3(0, 0, 0), Vec3(0, 1000, 0)], [Vec3(1000, 0, 0), Vec3(1000, 1000, 0)]], tolerance: 1)
        XCTAssertEqual(SurfaceNetwork.area(flat!), 1e6, accuracy: 1)
    }

    func testOffsetExtendTrim() async {
        let ed = Editor()
        let s = squareSurface(ed, 1000)
        ed.selection = [s]
        await ed.run("SURFOFFSET 100")
        XCTAssertTrue(lastSurface(ed)!.vertices.allSatisfy { abs($0.z - 100) < 1e-9 })
        ed.selection = [s]
        await ed.run("SURFEXTEND 100")
        XCTAssertEqual(SurfaceNetwork.area(surface(ed, s)!), 1200 * 1200, accuracy: 1e-3)
        let t = squareSurface(ed, 1000)
        let cut = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(250, 250), Vec2(750, 250), Vec2(750, 750), Vec2(250, 750)], closed: true)))
        ed.selection = [t]
        await ed.run("SURFTRIM #\(cut) Inside")
        XCTAssertEqual(SurfaceNetwork.area(surface(ed, t)!), 2.5e5, accuracy: 1e-3)
        let t2 = squareSurface(ed, 1000)
        ed.selection = [t2]
        await ed.run("SURFTRIM #\(cut) Outside")
        XCTAssertEqual(SurfaceNetwork.area(surface(ed, t2)!), 7.5e5, accuracy: 1e-3)
    }

    func testSculptClosedSurfacesIntoSolid() async {
        let ed = Editor()
        let c = [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(1000, 1000, 0), Vec3(0, 1000, 0),
                 Vec3(0, 0, 1000), Vec3(1000, 0, 1000), Vec3(1000, 1000, 1000), Vec3(0, 1000, 1000)]
        let quads = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        var ids: [EntityID] = []
        for (k, q) in quads.enumerated() {
            let v = q.map { c[$0] }
            // Mixed windings on purpose.
            let t = k % 2 == 0 ? [0, 1, 2, 0, 2, 3] : [0, 2, 1, 0, 3, 2]
            ids.append(ed.doc.add(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: v, meshTriangles: t))))
        }
        ed.selection = Set(ids)
        await ed.run("SURFSCULPT")
        let solids = ed.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry { return s }; return nil }
        XCTAssertEqual(solids.count, 1)
        XCTAssertEqual(CSG.volume(solids[0]), 1e9, accuracy: 1)
        // An open set is refused.
        let ed2 = Editor()
        let one = ed2.doc.add(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: Array(c[0..<4]), meshTriangles: [0, 1, 2, 0, 2, 3])))
        ed2.selection = [one]
        await ed2.run("SURFSCULPT")
        XCTAssertEqual(ed2.doc.entities.count, 1)
    }

    func testPaintSoftenTape() async {
        let ed = Editor()
        let b = ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(100, 100, 100))))
        await ed.run("PAINT Brick #\(b) ")
        XCTAssertEqual(ed.doc.entity(b)?.props["material"], "Brick")
        XCTAssertNotNil(ed.doc.material("Brick"))
        XCTAssertEqual(MeshBuilder.groups(for: ed.doc.entity(b)!, doc: ed.doc).first?.material, "Brick")
        let b2 = ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 0, 0), size: Vec3(100, 100, 100))))
        await ed.run("PAINT S #\(b)  #\(b2) ")
        XCTAssertEqual(ed.doc.entity(b2)?.props["material"], "Brick")
        let tor = ed.doc.add(.solid(SolidPrimitives.torus(center: Vec3(0, 0, 0), radius: 1000, tube: 200, segments: 8, tubeSegments: 6)!))
        let before = MeshBuilder.groups(for: ed.doc.entity(tor)!, doc: ed.doc)[0].edges.count
        ed.selection = [tor]
        await ed.run("SOFTEN 70")
        XCTAssertEqual(ed.doc.entity(tor)?.props["softenAngle"], "70")
        let g = MeshBuilder.groups(for: ed.doc.entity(tor)!, doc: ed.doc)[0]
        XCTAssertLessThan(g.edges.count, before)
        XCTAssertEqual(g.mesh.normals.count, g.mesh.positions.count)
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        await ed.run("TAPEMEASURE Guide #\(l) 500")
        guard let info = ConstructionLines.info(ed.doc.entities.last!) else { return XCTFail("no guide") }
        XCTAssertEqual(abs(info.base.y), 500, accuracy: 1e-9)
        XCTAssertEqual(abs(info.direction.x), 1, accuracy: 1e-9)
        await ed.run("TAPEMEASURE Protractor 0,0 1000,0 90")
        XCTAssertEqual(abs(ConstructionLines.info(ed.doc.entities.last!)!.direction.y), 1, accuracy: 1e-9)
    }

    func testIntersectFaces() async {
        let ed = Editor()
        let a = ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        let b = ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 500, 500), size: Vec3(1000, 1000, 1000))))
        ed.selection = [a, b]
        await ed.run("INTERSECTFACES Selection")
        let curves = ed.doc.entities.filter { $0.props["intersection"] != nil }
        XCTAssertFalse(curves.isEmpty)
        var total = 0.0
        for e in curves {
            guard case .polyline(let pl) = e.geometry else { continue }
            let z = e.props["vertexZ"]!.split(separator: ",").compactMap { Double($0) }
            var p = zip(pl.vertices, z).map { Vec3($0.p.x, $0.p.y, $1) }
            if pl.closed, let f = p.first { p.append(f) }
            total += zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        }
        XCTAssertEqual(total, 3000, accuracy: 1e-6)
        // Disjoint solids: nothing.
        let ed2 = Editor()
        let c = ed2.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(100, 100, 100))))
        let d = ed2.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 0, 0), size: Vec3(100, 100, 100))))
        ed2.selection = [c, d]
        await ed2.run("INTERSECTFACES Selection")
        XCTAssertEqual(ed2.doc.entities.count, 2)
    }

    func testScriptedObjectCustomizer() async {
        let script = "// Width of the block\nw = 10; // [5:50]\nh = 20; // [10:5:40]\nfinish = \"matt\"; // [matt, gloss]\nround = false;\n/* [Hidden] */\nk = 3;\ncube([w, w, h]);"
        let ps = SCADCustomizer.parameters(script)
        XCTAssertEqual(ps.map(\.name), ["w", "h", "finish", "round"])
        XCTAssertEqual(ps[0].min, 5); XCTAssertEqual(ps[0].max, 50); XCTAssertEqual(ps[0].description, "Width of the block")
        XCTAssertEqual(ps[1].step, 5); XCTAssertEqual(ps[2].options, ["matt", "gloss"]); XCTAssertEqual(ps[3].kind, .bool)
        XCTAssertThrowsError(try SCADCustomizer.set(script, "w", "80"))
        XCTAssertThrowsError(try SCADCustomizer.set(script, "finish", "shiny"))
        XCTAssertTrue(try SCADCustomizer.set(script, "finish", "gloss").contains("finish = \"gloss\"; // [matt, gloss]"))
        let ed = Editor()
        await ed.run("SCADOBJECT New \"w = 10; // [5:50]\\nh = 20;\\ncube([w, w, h]);\" 100,200")
        guard let id = ed.doc.entities.last?.id, let s = ModelingCommands.solidOf(ed.doc, id) else { return XCTFail("no scripted object") }
        XCTAssertEqual(s.source?.kind, .script)
        XCTAssertEqual(CSG.volume(s), 2000, accuracy: 1e-6)
        XCTAssertEqual(ModelingCommands.bounds(s).min.x, 100, accuracy: 1e-9)
        await ed.run("SCADOBJECT Set #\(id) \"w = 30\"")
        XCTAssertEqual(CSG.volume(ModelingCommands.solidOf(ed.doc, id)!), 18000, accuracy: 1e-6)
        await ed.run("SCADOBJECT Set #\(id) \"w = 80\"")
        XCTAssertEqual(CSG.volume(ModelingCommands.solidOf(ed.doc, id)!), 18000, accuracy: 1e-6, "out-of-range values are refused")
        XCTAssertTrue(ModelingCommands.solidOf(ed.doc, id)!.source!.expression!.contains("w = 30;"))
    }

    func testProjectedGeometryFollowsSolid() async {
        let ed = Editor()
        let b = ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 500, 300))))
        ed.selection = [b]
        await ed.run("PROJECTGEOMETRY 0")
        let proj = ed.doc.entities.filter { $0.props[ProjectedGeometry.prop] == "\(b)" }
        XCTAssertEqual(proj.count, 1)
        let pid = proj[0].id
        XCTAssertEqual(abs(GeometryOps.signedArea(ModelingCommands.loop(ed.doc, pid)!)), 5e5, accuracy: 1e-6)
        ed.doc.entities[ed.doc.entityIndex(b)!].geometry = .solid(SolidGeom(kind: .box, origin: Vec3(2000, 0, 0), size: Vec3(1000, 800, 300)))
        var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
        guard let loop = ModelingCommands.loop(ed.doc, pid) else { return XCTFail("projection lost its id") }
        XCTAssertEqual(abs(GeometryOps.signedArea(loop)), 8e5, accuracy: 1e-6)
        XCTAssertEqual(BBox2(points: loop).min.x, 2000, accuracy: 1e-9)
        // An L-shaped solid projects as one outline.
        let l = ed.doc.add(.solid(SolidGeom(kind: .extrusion, origin: Vec3(5000, 0, 0), profile: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 400), Vec2(400, 400), Vec2(400, 1000), Vec2(0, 1000)], height: 200)))
        XCTAssertEqual(ProjectedGeometry.outline(ModelingCommands.solidOf(ed.doc, l)!).count, 1)
    }
}
