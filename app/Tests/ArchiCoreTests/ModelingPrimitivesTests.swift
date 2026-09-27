// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class ModelingPrimitivesTests: XCTestCase {
    func valid(_ s: SolidGeom?, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let s = s else { XCTFail("nil solid " + msg, file: file, line: line); return 0 }
        let r = SolidCheck.report(SolidCheck.triangles(s))
        XCTAssertTrue(r.valid, msg + " " + r.summary, file: file, line: line)
        return r.volume
    }

    func testPrimitiveVolumesAndValidity() async {
        XCTAssertEqual(valid(SolidPrimitives.wedge(corner: .zero, length: 1000, width: 500, height: 300), "wedge"), 1000 * 500 * 300 / 2, accuracy: 1e-3)
        XCTAssertEqual(valid(SolidPrimitives.wedge(corner: .zero, length: -1000, width: 500, height: 300, rotation: 0.3), "mirrored wedge"), 1000 * 500 * 300 / 2, accuracy: 1e-3)
        // Square pyramid: circumradius r → side r√2, V = side² h / 3.
        let r = 1000.0
        XCTAssertEqual(valid(SolidPrimitives.pyramid(center: .zero, sides: 4, radius: r, height: 900), "pyramid"), 2 * r * r * 900 / 3, accuracy: 1e-2)
        let fr = valid(SolidPrimitives.pyramid(center: .zero, sides: 4, radius: 1000, topRadius: 500, height: 900), "frustum")
        let frExact: Double = 300.0 * (2e6 + 5e5 + 1e6)
        XCTAssertEqual(fr, frExact, accuracy: 1)
        // Torus: 2π² R r² (polygonal approximation within 2 %).
        let tv = valid(SolidPrimitives.torus(center: .zero, radius: 1000, tube: 200), "torus")
        let exact: Double = 2 * Double.pi * Double.pi * 1000.0 * 40_000.0
        XCTAssertEqual(tv, exact, accuracy: exact * 0.02)
        // Hexagonal prism and tube.
        let hexArea: Double = 1.5 * 3.0.squareRoot() * 250_000.0
        XCTAssertEqual(valid(SolidPrimitives.prism(center: .zero, sides: 6, radius: 500, height: 1000), "prism"), hexArea * 1000, accuracy: 1)
        let hole: Double = 1.5 * 3.0.squareRoot() * 90_000.0
        XCTAssertEqual(valid(SolidPrimitives.prism(center: .zero, sides: 6, radius: 500, height: 1000, innerRadius: 300), "tube"), (hexArea - hole) * 1000, accuracy: 1)
        XCTAssertNil(SolidPrimitives.prism(center: .zero, sides: 6, radius: 500, height: 1000, innerRadius: 600))
        XCTAssertNil(SolidPrimitives.torus(center: .zero, radius: 100, tube: 200))
        // Polyhedron: a tetrahedron given with mixed face windings is oriented outward.
        let tet = SolidPrimitives.polyhedron(points: [.zero, Vec3(1000, 0, 0), Vec3(0, 1000, 0), Vec3(0, 0, 1000)], faces: [[0, 1, 2], [0, 1, 3], [0, 3, 2], [1, 2, 3]])
        XCTAssertEqual(valid(tet, "tetra"), 1e9 / 6, accuracy: 1e-3)
        XCTAssertNil(SolidPrimitives.polyhedron(points: [.zero, Vec3(1000, 0, 0), Vec3(0, 1000, 0), Vec3(0, 0, 1000)], faces: [[0, 1, 2], [0, 1, 3]]), "open")
        // Polysolid: L-shaped wall 200 thick, 2500 high, mitred corner.
        let ps = SolidPrimitives.polysolid(path: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000)], z: 0, width: 200, height: 2500)
        XCTAssertEqual(valid(ps, "polysolid"), (4000 + 3000) * 200 * 2500, accuracy: 1)
        let closed = SolidPrimitives.polysolid(path: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000), Vec2(0, 3000)], z: 0, width: 200, height: 2500, justify: "Left", closed: true)
        XCTAssertEqual(valid(closed, "closed polysolid"), (4000 * 3000 - 3600 * 2600) * 2500, accuracy: 1)
    }

    func testHullThickenSeparateAndCheck() async {
        // Hull of a cube's corners plus interior points = the cube.
        var pts: [Vec3] = []
        for x in [0.0, 1000] { for y in [0.0, 1000] { for z in [0.0, 1000] { pts.append(Vec3(x, y, z)) } } }
        pts += [Vec3(500, 500, 500), Vec3(200, 300, 400), Vec3(1000, 500, 500)]
        XCTAssertEqual(valid(SolidPrimitives.hull(pts), "hull"), 1e9, accuracy: 1e-3)
        XCTAssertNil(SolidPrimitives.hull([.zero, Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(1, 1, 0)]), "coplanar")
        // Thicken a planar surface with a hole.
        let s = SolidPrimitives.planarSurface([Vec2(0, 0), Vec2(2000, 0), Vec2(2000, 1000), Vec2(0, 1000)], holes: [[Vec2(500, 250), Vec2(500, 750), Vec2(1000, 750), Vec2(1000, 250)]], z: 0)!
        XCTAssertEqual(SurfaceTools.area(s), 2e6 - 250_000, accuracy: 1e-6)
        XCTAssertEqual(valid(SolidPrimitives.thicken(vertices: s.vertices, triangles: s.triangles, thickness: 100), "thicken"), (2e6 - 250_000) * 100, accuracy: 1)
        XCTAssertEqual(valid(SolidPrimitives.thicken(vertices: s.vertices, triangles: s.triangles, thickness: -100), "thicken down"), (2e6 - 250_000) * 100, accuracy: 1)
        // Separate: two disjoint boxes in one mesh solid → two bodies; report counts.
        let a = SolidCheck.triangles(SolidGeom(kind: .box, origin: .zero, size: Vec3(100, 100, 100)))
        let b = SolidCheck.triangles(SolidGeom(kind: .box, origin: Vec3(500, 0, 0), size: Vec3(100, 100, 100)))
        let two = MeshTools.solid(from: a + b)
        XCTAssertEqual(SolidCheck.report(SolidCheck.triangles(two)).components, 2)
        XCTAssertEqual(SolidCheck.separate(two).count, 2)
        // Check finds an open solid and a flipped face; clean repairs orientation.
        let open = Array(a.dropLast())
        XCTAssertGreaterThan(SolidCheck.report(open).openEdges, 0)
        var flipped = a
        flipped[0] = (a[0].0, a[0].2, a[0].1)
        XCTAssertFalse(SolidCheck.report(flipped).valid)
        XCTAssertTrue(SolidCheck.report(SolidCheck.clean(flipped)).valid)
    }

    func testMeshPrimitivesConversionAndLinearExtrude() async {
        XCTAssertEqual(valid(SolidPrimitives.meshBox(origin: .zero, size: Vec3(1000, 500, 200), divisions: 4), "mesh box"), 1e8, accuracy: 1e-3)
        XCTAssertEqual(SolidPrimitives.meshBox(origin: .zero, size: Vec3(1000, 500, 200), divisions: 4)!.meshTriangles.count / 3, 6 * 16 * 2)
        let sv = valid(SolidPrimitives.meshSphere(center: .zero, radius: 1000, segments: 48), "mesh sphere")
        XCTAssertEqual(sv, 4 / 3 * Double.pi * 1e9, accuracy: 4 / 3 * Double.pi * 1e9 * 0.02)
        // Linear extrude: a square twisted by 90° keeps its volume; scaled to 0.5 the volume is h/3 (A + A/4 + A/2).
        let sq = [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)]
        XCTAssertEqual(valid(SolidPrimitives.linearExtrude(sq, z: 0, height: 2000, twist: .pi / 2), "twist"), 2e9, accuracy: 2e9 * 0.01)
        let tapered: Double = 2000.0 / 3.0 * (1e6 + 250_000 + 500_000)
        XCTAssertEqual(valid(SolidPrimitives.linearExtrude(sq, z: 0, height: 2000, scale: 0.5), "taper"), tapered, accuracy: 1)
        XCTAssertEqual(valid(SolidPrimitives.linearExtrude(sq, z: 0, height: 3000, scale: 0), "cone"), 1e9, accuracy: 1)
        // Commands.
        let ed = Editor()
        await ed.run("MESH Box 2 0,0 1000,1000 500")
        await ed.run("MESH Sphere 3 3000,0 500")
        await ed.run("RECTANG 5000,0 6000,1000")
        let rect = ed.doc.entities.last!.id
        ed.selection = [rect]
        await ed.run("LINEAREXTRUDE 1000 45 1")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["mesh"] != nil }.count, 2)
        guard case .solid(let tw) = ed.doc.entities.last!.geometry else { return XCTFail("no extrude") }
        XCTAssertEqual(CSG.volume(tw), 1e9, accuracy: 1e7)
        await ed.run("CYLINDER 0,5000 300 1000")
        let cyl = ed.doc.entities.last!.id
        ed.selection = [cyl]
        await ed.run("CONVTOMESH")
        guard case .solid(let cm) = ed.doc.entity(cyl)!.geometry else { return XCTFail() }
        XCTAssertEqual(cm.kind, .mesh)
        XCTAssertTrue(SolidCheck.report(SolidCheck.triangles(cm)).valid)
        // An open mesh (a surface) is refused by CONVTOSOLID; a closed one converts.
        await ed.run("PLANESURF 0,9000 1000,10000")
        let surf = ed.doc.entities.last!.id
        ed.selection = [surf, cyl]
        await ed.run("CONVTOSOLID")
        XCTAssertNotNil(ed.doc.entity(surf)?.props["surface"])
        XCTAssertNil(ed.doc.entity(cyl)?.props["mesh"])
    }

    func testAssociativeLoftAndPipe() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 1000,1000")
        let a = ed.doc.entities.last!.id
        await ed.run("CIRCLE 500,500 300")
        let b = ed.doc.entities.last!.id
        await ed.run("LOFT #\(a) #\(b)  0 2000")
        guard case .solid(let l0) = ed.doc.entities.last!.geometry else { return XCTFail("no loft") }
        let loft = ed.doc.entities.last!.id
        XCTAssertEqual(l0.source?.kind, .loft)
        XCTAssertEqual(MeshTools.mesh(of: l0).bounds.max.z, 2000, accuracy: 1e-6)
        // Editing a section regenerates the loft.
        ed.selection = [b]
        await ed.run("MOVE 0,0 3000,0")
        guard case .solid(let l1) = ed.doc.entity(loft)!.geometry else { return XCTFail() }
        XCTAssertEqual(MeshTools.mesh(of: l1).bounds.max.x, 3800, accuracy: 1)
        // Pipe along a line follows the line when it is stretched.
        await ed.run("LINE 0,5000 2000,5000 ")
        let ln = ed.doc.entities.last!.id
        await ed.run("PIPE #\(ln) 50 10 0")
        let pipe = ed.doc.entities.last!.id
        guard case .solid(let p0) = ed.doc.entity(pipe)!.geometry else { return XCTFail("no pipe") }
        XCTAssertEqual(p0.source?.kind, .pipe)
        let v0 = CSG.volume(p0)
        XCTAssertEqual(v0, Double.pi * (50 * 50 - 40 * 40) * 2000, accuracy: v0 * 0.03)
        if let i = ed.doc.entityIndex(ln) { ed.doc.entities[i].geometry = .line(LineGeom(Vec2(0, 5000), Vec2(4000, 5000))) }
        var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
        guard case .solid(let p1) = ed.doc.entity(pipe)!.geometry else { return XCTFail() }
        XCTAssertEqual(CSG.volume(p1), 2 * v0, accuracy: v0 * 0.03)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entity(pipe)?.geometry, ed.doc.entity(pipe)?.geometry)
    }

    func testPrimitiveCommands() async {
        let ed = Editor()
        await ed.run("WEDGE 0,0 1000,500 300")
        await ed.run("PYRAMID 4 5000,0 1000 900")
        await ed.run("PYRAMID 6 9000,0 1000 T 400 900")
        await ed.run("TORUS 0,5000 1000 200")
        await ed.run("PRISM 8 5000,5000 500 200 1000")
        await ed.run("POLYSOLID H 3000 W 250 0,10000 5000,10000 5000,14000 ")
        let solids = ed.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry { return s }; return nil }
        XCTAssertEqual(solids.count, 6)
        for s in solids { _ = valid(s) }
        XCTAssertEqual(CSG.volume(solids[0]), 1000 * 500 * 300 / 2, accuracy: 1e-3)
        XCTAssertEqual(CSG.volume(solids[5]), (5000 + 4000) * 250 * 3000, accuracy: 1)
        // Planar surface, thicken, hull, check.
        await ed.run("PLANESURF 20000,0 22000,1000")
        guard let surf = ed.doc.entities.last, surf.props["surface"] != nil else { return XCTFail("no surface") }
        ed.selection = [surf.id]
        await ed.run("THICKEN 50")
        guard case .solid(let th)? = ed.doc.entity(surf.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(CSG.volume(th), 2e6 * 50, accuracy: 1)
        XCTAssertNil(ed.doc.entity(surf.id)?.props["surface"])
        ed.selection = Set(ed.doc.entities.prefix(2).map(\.id))
        await ed.run("HULL Yes")
        XCTAssertEqual(ed.doc.entities.count, 8)
        ed.selection = Set(ed.doc.entities.map(\.id))
        await ed.run("SOLIDCHECK")
        XCTAssertTrue(ed.history.undoStack.count >= 9)
        // Persistence.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entities.map(\.geometry), ed.doc.entities.map(\.geometry))
    }
}
