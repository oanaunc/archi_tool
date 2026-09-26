// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Components and groups (M3D-102), outliner (M3D-103), datum geometry (M3D-028) and sandbox terrain (M3D-099).
@MainActor
final class ModelingComponentsDatumsTests: XCTestCase {
    func box(_ ed: Editor, _ o: Vec3, _ s: Vec3) -> EntityID { ed.doc.add(.solid(SolidGeom(kind: .box, origin: o, size: s))) }
    func volume(_ gs: [MeshGroup]) -> Double { gs.map { MeshTools.signedVolume($0.mesh) }.reduce(0, +) }

    func testComponentsGroupsOutlinerAndBIM() async {
        let ed = Editor()
        let a = box(ed, .zero, Vec3(500, 500, 450)), b = box(ed, Vec3(0, 400, 450), Vec3(500, 100, 500))
        await ed.run("MAKECOMPONENT Chair 0,0 #\(a),#\(b) ")
        guard let i1 = ed.doc.entities.last, case .insert(let ins) = i1.geometry, ins.block == "Chair" else { return XCTFail("no component") }
        XCTAssertEqual(i1.props[SketchComponents.componentKey], "1")
        XCTAssertNil(ed.doc.entity(a))
        let v0 = 500.0 * 500 * 450 + 500.0 * 100 * 500
        XCTAssertEqual(volume(MeshBuilder.groups(for: i1, doc: ed.doc)), v0, accuracy: 1)
        // A second instance; editing the definition changes both.
        let i2 = ed.doc.add(.insert(InsertGeom(block: "Chair", position: Vec2(3000, 0), rotation: .pi / 2)))
        ed.doc.blocks["Chair"]!.entities[0].geometry = .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(500, 500, 900)))
        let v1 = 500.0 * 500 * 900 + 500.0 * 100 * 500
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.entity(i1.id)!, doc: ed.doc)), v1, accuracy: 1)
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.entity(i2)!, doc: ed.doc)), v1, accuracy: 1)
        // Make unique: the second instance gets its own definition.
        await ed.run("MAKEUNIQUE #\(i2)")
        guard case .insert(let u)? = ed.doc.entity(i2)?.geometry else { return XCTFail() }
        XCTAssertEqual(u.block, "Chair #2")
        ed.doc.blocks["Chair"]!.entities.removeLast()
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.entity(i2)!, doc: ed.doc)), v1, accuracy: 1)
        // Group.
        let c = box(ed, Vec3(0, 3000, 0), Vec3(1000, 1000, 750))
        ed.selection = []
        await ed.run("MAKEGROUP #\(c)  Table")
        guard let g = ed.doc.entities.last, case .insert(let gi) = g.geometry else { return XCTFail("no group") }
        XCTAssertTrue(gi.block.hasPrefix("*G")); XCTAssertEqual(g.props["name"], "Table")
        // Outliner.
        let tree = Outliner.tree(ed.doc)
        XCTAssertEqual(tree.count, 3)
        XCTAssertTrue(Outliner.lines(tree).contains { $0.contains("Table") && $0.contains("[group]") })
        XCTAssertEqual(tree.first { $0.id == i1.id }?.children.count, 1)
        await ed.run("OUTLINER Select Tab*")
        XCTAssertEqual(ed.selection, [g.id])
        // Convert to BIM.
        ed.selection = []
        await ed.run("COMPONENTTOBIM #\(g.id)  Furniture")
        guard let el = ed.doc.elements.last, case .component(let cg) = el.geometry else { return XCTFail("not converted") }
        XCTAssertEqual(cg.category, "Furniture"); XCTAssertEqual(el.name, "Table")
        XCTAssertNil(ed.doc.entity(g.id))
        XCTAssertEqual(volume(MeshBuilder.groups(for: el, doc: ed.doc)), 1000.0 * 1000 * 750, accuracy: 1)
    }

    func testDatumsFollowTheirSources() async {
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        await ed.run("DATUM Axis #\(l)")
        let axis = ed.doc.entities.last!.id
        await ed.run("DATUM Plane Line #\(l) 100 0 2500")
        let plane = ed.doc.entities.last!.id
        await ed.run("DATUM Point #\(l) Mid")
        let point = ed.doc.entities.last!.id
        let bx = box(ed, .zero, Vec3(1000, 1000, 1000))
        await ed.run("DATUM Plane Face #\(bx) 500,500,1000 50")
        let face = ed.doc.entities.last!.id
        await ed.run("DATUM Plane Level 1 200 0,0 5000")
        let lvl = ed.doc.entities.last!.id
        XCTAssertEqual(Set([axis, plane, point, face, lvl]).count, 5)
        XCTAssertEqual(Datums.vec3(ed.doc.entity(face)?.props["datumA"])?.z ?? 0, 1050, accuracy: 1e-6)
        XCTAssertEqual(Datums.vec3(ed.doc.entity(lvl)?.props["datumA"])?.z ?? 0, 3200, accuracy: 1e-6)
        XCTAssertEqual(ed.doc.entity(plane)?.props["thickness"], "2500")
        // Move / resize the sources: the datums regenerate.
        ed.doc.entities[ed.doc.entityIndex(l)!].geometry = .line(LineGeom(Vec2(0, 500), Vec2(1000, 500)))
        ed.doc.entities[ed.doc.entityIndex(bx)!].geometry = .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 2000)))
        ed.doc.levels[1].elevation = 3500
        BIMUpdaters.run(&ed.doc)
        guard case .polyline(let ap)? = ed.doc.entity(axis)?.geometry else { return XCTFail() }
        XCTAssertTrue(ap.vertices.allSatisfy { abs($0.p.y - 500) < 1e-9 })
        guard case .line(let pl)? = ed.doc.entity(plane)?.geometry else { return XCTFail() }
        XCTAssertEqual(pl.a.y, 600, accuracy: 1e-9); XCTAssertEqual(pl.b.y, 600, accuracy: 1e-9)
        guard case .point(let pp)? = ed.doc.entity(point)?.geometry else { return XCTFail() }
        XCTAssertEqual(pp.distance(to: Vec2(500, 500)), 0, accuracy: 1e-9)
        XCTAssertEqual(Datums.vec3(ed.doc.entity(face)?.props["datumA"])?.z ?? 0, 2050, accuracy: 1e-6)
        XCTAssertEqual(Datums.vec3(ed.doc.entity(lvl)?.props["datumA"])?.z ?? 0, 3700, accuracy: 1e-6)
        // The face datum is a plane patch drawn in 3D.
        XCTAssertFalse(MeshBuilder.groups(for: ed.doc.entity(face)!, doc: ed.doc).isEmpty)
        // Deleting the source orphans the datum (kept where it was).
        ed.doc.remove(ids: [l])
        BIMUpdaters.run(&ed.doc)
        XCTAssertEqual(ed.doc.entity(axis)?.props["datumOrphan"], "1")
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: try! JSONEncoder().encode(ed.doc))
        XCTAssertEqual(back.entity(face)?.props["datum"], "plane")
    }

    func testSandboxTools() async {
        let ed = Editor()
        await ed.run("SANDBOX Grid 0,0 10000 10000 1000")
        guard let topo = ed.doc.entities.last, topo.props["topo"] == "1", case .solid(let s0) = topo.geometry else { return XCTFail("no grid") }
        XCTAssertEqual(Sandbox.points(s0).points.count, 121)
        await ed.run("SANDBOX Smoove #\(topo.id) 5000,5000 3000 1000")
        guard case .solid(let s1)? = ed.doc.entity(topo.id)?.geometry else { return XCTFail() }
        let p1 = Sandbox.points(s1).points
        let surf = Terrain.surface(p1)
        XCTAssertEqual(Terrain.elevation(at: Vec2(5000, 5000), vertices: surf.vertices, triangles: surf.triangles) ?? 0, 1000, accuracy: 1e-6)
        XCTAssertEqual(Terrain.elevation(at: Vec2(9000, 9000), vertices: surf.vertices, triangles: surf.triangles) ?? -1, 0, accuracy: 1e-6)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: s1.meshVertices, triangles: s1.meshTriangles))
        // Stamp a pad at −200 over a square with a 1000 side slope.
        let sq = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(1000, 1000), Vec2(3000, 1000), Vec2(3000, 3000), Vec2(1000, 3000)], closed: true)))
        await ed.run("SANDBOX Stamp #\(topo.id) #\(sq) -200 1000")
        guard case .solid(let s2)? = ed.doc.entity(topo.id)?.geometry else { return XCTFail() }
        let p2 = Sandbox.points(s2).points, surf2 = Terrain.surface(p2)
        XCTAssertEqual(Terrain.elevation(at: Vec2(2000, 2000), vertices: surf2.vertices, triangles: surf2.triangles) ?? 0, -200, accuracy: 1e-6)
        XCTAssertEqual(Terrain.elevation(at: Vec2(9000, 1000), vertices: surf2.vertices, triangles: surf2.triangles) ?? 1, 0, accuracy: 1e-6)
        // Drape a path over the bump.
        let path = ed.doc.add(.line(LineGeom(Vec2(500, 5000), Vec2(9500, 5000))))
        await ed.run("SANDBOX Drape #\(topo.id) #\(path) ")
        guard let d = ed.doc.entities.last, d.props["drapedOn"] == "\(topo.id)", let zs = d.props["vertexZ"]?.split(separator: ",").compactMap({ Double($0) }) else { return XCTFail("no drape") }
        XCTAssertEqual(zs.max() ?? 0, 1000, accuracy: 1)
        // To BIM.
        await ed.run("SANDBOX ToBIM #\(topo.id) No")
        guard let el = ed.doc.elements.last, case .component(let g) = el.geometry else { return XCTFail("no element") }
        XCTAssertEqual(g.category, "Topography")
        XCTAssertNotNil(ed.doc.entity(topo.id))
    }
}
