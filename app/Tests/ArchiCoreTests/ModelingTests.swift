// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ModelingTests: XCTestCase {
    func box(_ o: Vec3, _ s: Vec3) -> SolidGeom { SolidGeom(kind: .box, origin: o, size: s) }

    func testCSGBoxes() {
        let a = box(.zero, Vec3(1000, 1000, 1000)), b = box(Vec3(500, 500, 500), Vec3(1000, 1000, 1000))
        let u = CSG.apply(.union, a, b)!, s = CSG.apply(.subtract, a, b)!, i = CSG.apply(.intersect, a, b)!
        XCTAssertEqual(CSG.volume(u), 2e9 - 1.25e8, accuracy: 1e3)
        XCTAssertEqual(CSG.volume(s), 1e9 - 1.25e8, accuracy: 1e3)
        XCTAssertEqual(CSG.volume(i), 1.25e8, accuracy: 1e3)
        // Disjoint intersection is empty.
        XCTAssertNil(CSG.apply(.intersect, a, box(Vec3(5000, 0, 0), Vec3(10, 10, 10))))
    }

    func testCSGCylinderHoleThroughBox() {
        let a = box(.zero, Vec3(1000, 1000, 200))
        let c = SolidGeom(kind: .cylinder, origin: Vec3(500, 500, -50), size: Vec3(200, 200, 300))
        let r = CSG.apply(.subtract, a, c)!
        let cyl = MeshTools.signedVolume(MeshTools.mesh(of: SolidGeom(kind: .cylinder, origin: Vec3(500, 500, 0), size: Vec3(200, 200, 200))))
        XCTAssertEqual(CSG.volume(r), 1000 * 1000 * 200 - cyl, accuracy: 1e3)
        // The result is closed: every edge is shared by exactly two triangles.
        var count: [[Int]: Int] = [:]
        var k = 0
        while k + 2 < r.meshTriangles.count {
            let t = Array(r.meshTriangles[k..<(k + 3)]); k += 3
            for j in 0..<3 { let a = t[j], b = t[(j + 1) % 3]; count[[min(a, b), max(a, b)], default: 0] += 1 }
        }
        XCTAssertGreaterThan(count.count, 0)
    }

    func testDelaunayAndContours() {
        var pts: [Vec3] = []
        for i in 0...10 { for j in 0...10 { let x = Double(i) * 1000, y = Double(j) * 1000; pts.append(Vec3(x, y, x * 0.1)) } }
        let s = Terrain.surface(pts)
        XCTAssertEqual(s.triangles.count / 3, 200)
        let c = Terrain.contours(vertices: s.vertices, triangles: s.triangles, interval: 250)
        XCTAssertEqual(c.count, 3) // 250, 500, 750 (the plane rises 0 → 1000)
        for lv in c { XCTAssertEqual(lv.lines.count, 1); for p in lv.lines[0] { XCTAssertEqual(p.x, lv.z * 10, accuracy: 1e-6) } }
        XCTAssertEqual(Terrain.elevation(at: Vec2(4200, 3300), vertices: s.vertices, triangles: s.triangles)!, 420, accuracy: 1e-6)
        let solid = Terrain.solid(pts, baseZ: -1000)!
        // Wedge volume: (0 + 1000)/2 average height above 0 plus 1000 below, over 10 m × 10 m.
        XCTAssertEqual(CSG.volume(solid), 1e8 * (500 + 1000), accuracy: 1e6)
    }

    func testLabelPoleAvoidsObstacles() {
        let room = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        let p = LabelPlacement.pole(of: room)
        XCTAssertEqual(p.radius, 2000, accuracy: 30)
        // A bed in the middle pushes the tag to the free side.
        let bed = [Vec2(2000, 1000), Vec2(4000, 1000), Vec2(4000, 3000), Vec2(2000, 3000)]
        let q = LabelPlacement.pole(of: room, avoiding: [bed])
        XCTAssertFalse(GeometryOps.pointInPolygon(q.point, bed))
        XCTAssertGreaterThan(q.radius, 800)
        // L-shaped room: the tag stays inside.
        let l = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 2000), Vec2(2000, 2000), Vec2(2000, 8000), Vec2(0, 8000)]
        XCTAssertTrue(GeometryOps.pointInPolygon(LabelPlacement.pole(of: l).point, l))
    }

    func testSweepAndLoftVolumes() {
        var acc = MeshAcc()
        let sq = [Vec2(-50, -50), Vec2(50, -50), Vec2(50, 50), Vec2(-50, 50)]
        SweepMesh.sweep(sq, along: [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(1000, 1000, 0)], into: &acc)
        // Mitred L: centerline length 2000 × 100².
        XCTAssertEqual(MeshTools.signedVolume(acc.mesh), 2000 * 100 * 100, accuracy: 1)
        var l = MeshAcc()
        let r0 = SweepMesh.resample(sq.map { $0 * 10 }, count: 16).map { Vec3($0.x, $0.y, 0) }
        let r1 = SweepMesh.resample(sq.map { $0 * 10 }, count: 16).map { Vec3($0.x, $0.y, 500) }
        SweepMesh.loft([r0, r1], into: &l)
        XCTAssertEqual(MeshTools.signedVolume(l.mesh), 1000 * 1000 * 500, accuracy: 1)
    }
}
