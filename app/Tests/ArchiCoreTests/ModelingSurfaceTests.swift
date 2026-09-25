// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class ModelingSurfaceTests: XCTestCase {
    func testRevolvedTabulatedRuledAndCoonsSurfaces() {
        let rev = SurfaceTools.revolve([Vec3(100, 0, 0), Vec3(100, 0, 1000)], axisFrom: .zero, to: Vec3(0, 0, 1), segments: 64)
        XCTAssertEqual(SurfaceTools.area(rev), 2 * Double.pi * 100 * 1000, accuracy: 2 * Double.pi * 100 * 1000 * 0.002)
        let half = SurfaceTools.revolve([Vec3(100, 0, 0), Vec3(100, 0, 1000)], axisFrom: .zero, to: Vec3(0, 0, 1), sweep: .pi, segments: 32)
        XCTAssertEqual(half.vertices.count, 2 * 33)
        let tab = SurfaceTools.tabulate([Vec3(0, 0, 0), Vec3(1000, 0, 0)], vector: Vec3(0, 0, 500))
        XCTAssertEqual(SurfaceTools.area(tab), 500_000, accuracy: 1e-6)
        let ruled = SurfaceTools.ruled([Vec3(0, 0, 0), Vec3(1000, 0, 0)], [Vec3(1000, 800, 0), Vec3(0, 800, 0)], count: 10)
        XCTAssertEqual(SurfaceTools.area(ruled), 800_000, accuracy: 1e-6)   // second curve reversed to avoid a bow tie
        let sq = [[Vec3(0, 0, 0), Vec3(1000, 0, 0)], [Vec3(1000, 1000, 0), Vec3(1000, 0, 0)], [Vec3(0, 1000, 0), Vec3(1000, 1000, 0)], [Vec3(0, 0, 0), Vec3(0, 1000, 0)]]
        let patch = SurfaceTools.coons(sq, m: 8, n: 8)!
        XCTAssertEqual(SurfaceTools.area(patch), 1_000_000, accuracy: 1e-3)
        // A lifted edge makes a warped patch through the boundary.
        let arch = (0...10).map { i -> Vec3 in let x = Double(i) * 100; return Vec3(x, 1000, 300 * sin(Double.pi * x / 1000)) }
        let warped = SurfaceTools.coons([sq[0], sq[1], arch, sq[3]], m: 10, n: 10)!
        XCTAssertEqual(warped.vertices.map(\.z).max()!, 300, accuracy: 1e-6)
        XCTAssertNil(SurfaceTools.coons([sq[0], sq[1], sq[2]]))
    }

    func testTwistedSweepVolume() {
        let sq = [Vec2(-50, -50), Vec2(50, -50), Vec2(50, 50), Vec2(-50, 50)]
        let path = (0...20).map { Vec3(Double($0) * 50, 0, 0) }
        let m = SurfaceTools.twistedSweep(sq, along: path, twist: .pi / 2)
        XCTAssertEqual(MeshTools.signedVolume(m), 100 * 100 * 1000, accuracy: 100 * 100 * 1000 * 0.03)
        let tapered = SurfaceTools.twistedSweep(sq, along: [Vec3(0, 0, 0), Vec3(1000, 0, 0)], twist: 0, endScale: 0.5)
        // Frustum of squares 100 → 50 over 1000: V = h/3 (A1 + A2 + √(A1A2)).
        XCTAssertEqual(MeshTools.signedVolume(tapered), 1000.0 / 3 * (10000 + 2500 + 5000), accuracy: 1)
    }

    func testMeshRepairAndDecimate() {
        // A cube with duplicated vertices, one flipped face and a missing face.
        let c = [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(1000, 1000, 0), Vec3(0, 1000, 0), Vec3(0, 0, 1000), Vec3(1000, 0, 1000), Vec3(1000, 1000, 1000), Vec3(0, 1000, 1000)]
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6] /* [3,0,4,7] missing */]
        var verts: [Vec3] = [], tris: [Int] = []
        for (qi, q) in quads.enumerated() {
            let base = verts.count
            verts += q.map { c[$0] + Vec3(0.001, 0, 0) * Double(qi % 2) }  // near-coincident copies to weld
            var f = [base, base + 1, base + 2, base, base + 2, base + 3]
            if qi == 2 { f.swapAt(1, 2) }                                   // one flipped triangle
            tris += f
        }
        tris += [0, 0, 1]                                                   // degenerate
        let r = MeshTools.repair(vertices: verts, triangles: tris, tolerance: 0.01)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: r.vertices, triangles: r.triangles), r.report.description)
        XCTAssertEqual(r.report.holesFilled, 1)
        XCTAssertGreaterThanOrEqual(r.report.degenerate, 1)
        XCTAssertGreaterThan(r.report.flipped, 0)
        XCTAssertEqual(r.vertices.count, 8)
        XCTAssertEqual(SolidOps.volume(vertices: r.vertices, triangles: r.triangles), 1e9, accuracy: 1e5)
        // Decimation of a finely tessellated sphere.
        let sphere = MeshTools.weld(MeshTools.triangles(MeshTools.mesh(of: SolidGeom(kind: .sphere, origin: .zero, size: Vec3(1000, 0, 0)))), tolerance: 1e-6)
        let n0 = sphere.triangles.count / 3
        let d = MeshTools.decimate(vertices: sphere.vertices, triangles: sphere.triangles, ratio: 0.25)
        XCTAssertLessThanOrEqual(d.triangles.count / 3, n0 / 4 + 1)
        XCTAssertGreaterThan(d.triangles.count / 3, n0 / 20)
        var b = BBox3.empty; d.vertices.forEach { b.add($0) }
        XCTAssertEqual(b.max.x, 1000, accuracy: 150)
        XCTAssertGreaterThan(SolidOps.volume(vertices: d.vertices, triangles: d.triangles), 4.0 / 3 * Double.pi * 1e9 * 0.6)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: d.vertices, triangles: d.triangles))
    }

    func testSurfaceAndMeshCommands() async {
        let ed = Editor()
        let prof = ed.doc.add(.line(LineGeom(Vec2(300, 0), Vec2(500, 2000))))
        let axis = ed.doc.add(.line(LineGeom(Vec2(0, -100), Vec2(0, 3000))))
        await ed.run("REVSURF #\(prof) #\(axis) 0 360")
        guard case .solid(let s)? = ed.doc.entities.last?.geometry, s.kind == .mesh else { return XCTFail() }
        XCTAssertEqual(ed.doc.entities.last?.props["surface"], "Revolved surface")
        XCTAssertFalse(s.meshTriangles.isEmpty)
        let l = [ed.doc.add(.line(LineGeom(Vec2(0, 5000), Vec2(1000, 5000)))), ed.doc.add(.line(LineGeom(Vec2(1000, 5000), Vec2(1000, 6000)))),
                 ed.doc.add(.line(LineGeom(Vec2(1000, 6000), Vec2(0, 6000)))), ed.doc.add(.line(LineGeom(Vec2(0, 6000), Vec2(0, 5000))))]
        await ed.run("EDGESURF " + l.map { "#\($0)" }.joined(separator: " "))
        guard case .solid(let e)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(SurfaceTools.area((e.meshVertices, e.meshTriangles)), 1_000_000, accuracy: 1)
        // Twisted sweep through the SWEEP command.
        let square = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(-50, -50), Vec2(50, -50), Vec2(50, 50), Vec2(-50, 50)], closed: true)))
        let path = ed.doc.add(.line(LineGeom(Vec2(0, 10000), Vec2(1000, 10000))))
        ed.selection = [square]
        await ed.run("SWEEP #\(path) Twist 90 0")
        guard case .solid(let tw)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(SolidOps.volume(vertices: tw.meshVertices, triangles: tw.meshTriangles), 1e7, accuracy: 1e7 * 0.1)
        // MESHDECIMATE on a sphere solid.
        let sp = ed.doc.add(.solid(SolidGeom(kind: .sphere, origin: Vec3(0, 20000, 0), size: Vec3(500, 0, 0))))
        ed.selection = [sp]
        await ed.run("MESHDECIMATE 30")
        guard case .solid(let dm)? = ed.doc.entity(sp)?.geometry else { return XCTFail() }
        XCTAssertEqual(dm.kind, .mesh); XCTAssertGreaterThan(dm.meshTriangles.count, 0)
        ed.selection = [sp]
        let log = await ed.run("MESHREPAIR 0.01 Yes")
        XCTAssertTrue(log.contains { $0.contains("welded") }, log.joined(separator: "\n"))
    }
}
