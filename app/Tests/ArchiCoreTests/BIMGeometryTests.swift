// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class BIMGeometryTests: XCTestCase {
    func area(_ p: [Vec2]) -> Double { abs(GeometryOps.signedArea(p)) }

    func testSkeletonRectangleHasFourFaces() {
        let rect = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 6), Vec2(0, 6)]
        let f = StraightSkeleton.faces(rect)
        XCTAssertEqual(f.count, 4)
        XCTAssertEqual(f.reduce(0) { $0 + area($1.poly) }, 60, accuracy: 1e-6)
        // Long edges become trapezoids, short edges triangles.
        let counts = f.sorted { $0.edge < $1.edge }.map { $0.poly.count }
        XCTAssertEqual(counts, [4, 3, 4, 3])
    }

    func testSkeletonLShapeCoversFootprint() {
        let l = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(4000, 4000), Vec2(4000, 9000), Vec2(0, 9000)]
        let f = StraightSkeleton.faces(l)
        XCTAssertEqual(f.count, 6, "\(f.map { ($0.edge, $0.poly.count) })")
        XCTAssertEqual(f.reduce(0) { $0 + area($1.poly) }, area(l), accuracy: 1)
        // The reflex corner's valley reaches the ridge: both inner edges touch the reflex vertex.
        for e in [2, 3] { XCTAssertTrue(f.first { $0.edge == e }!.poly.contains { $0.isClose(Vec2(4000, 4000), tol: 1e-3) }) }
    }

    func testHipRoofOnLShapeHeightsAreContinuous() {
        let l = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(4000, 4000), Vec2(4000, 9000), Vec2(0, 9000)]
        let g = RoofGeom(boundary: l, kind: .hip, pitch: 30, overhang: 0)
        let r = RoofShapes.faces(g)
        XCTAssertEqual(r.faces.count, 6)
        let k = tan(30 * Double.pi / 180)
        // The ridge of the 4 m wide wing sits 2 m in from the eaves.
        let p = Vec2(2000, 7000)
        let hs = r.faces.filter { GeometryOps.pointInPolygon(p, $0.poly) || GeometryOps.distance(from: p, toPolyline: $0.poly + [$0.poly[0]]) < 1e-6 }.map { $0.height(p) }
        XCTAssertFalse(hs.isEmpty)
        for h in hs { XCTAssertEqual(h, 2000 * k, accuracy: 1e-3) }
        // Every face vertex has the same height on all faces that share it (no steps between faces).
        for f in r.faces { for v in f.poly {
            for o in r.faces where o.poly.contains(where: { $0.isClose(v, tol: 1e-6) }) { XCTAssertEqual(o.height(v), f.height(v), accuracy: 1e-3) }
        } }
    }

    func testGableEndWallsAreFilledToTheRoof() {
        var doc = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)]
        var ids: [EntityID] = []
        for i in 0..<4 { ids.append(doc.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 200, height: 3000)))) }
        _ = doc.addElement(.roof(RoofGeom(boundary: pts, kind: .gable, pitch: 30, overhang: 300, baseOffset: 3000, eaveEdge: 0)))
        let groups = MeshBuilder.build(doc: doc)
        func top(_ id: EntityID) -> Double { groups.filter { $0.id == id }.map { $0.mesh.bounds.max.z }.max() ?? 0 }
        // Eave walls stay at 3000; gable walls (x = 0 and x = 8000) reach the ridge: 3000 + 3000·tan30.
        XCTAssertEqual(top(ids[0]), 3000, accuracy: 1e-6)
        XCTAssertEqual(top(ids[2]), 3000, accuracy: 1e-6)
        XCTAssertEqual(top(ids[1]), 3000 + 3000 * tan(Double.pi / 6), accuracy: 1)
        XCTAssertEqual(top(ids[3]), 3000 + 3000 * tan(Double.pi / 6), accuracy: 1)
        // Gable infill volume = triangle (6000 × 1732 / 2) × 200 per end, on top of the 3000 m wall.
        let vol = MeshTools.signedVolume(groups.first { $0.id == ids[1] }!.mesh)
        XCTAssertEqual(vol, 6000 * 3000 * 200 + 6000 * 3000 * tan(Double.pi / 6) / 2 * 200, accuracy: 6000 * 3000 * 200 * 0.03)
    }

    func testTJoinIntoCurvedWallTrimsToArcFace() {
        var doc = ArchiDocument()
        // Semicircular wall of radius 5000 around the origin (bulge 1 from (5000,0) to (-5000,0)), thickness 200.
        _ = doc.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(-5000, 0), thickness: 200, bulge: 1)))
        let t = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(0, 5000), thickness: 100)))
        let o = PlanRepresentation.wallOutline(t, doc: doc)
        // The joining wall stops at the inner face (radius 4900), not the centerline.
        let maxY = o.map(\.y).max()!
        XCTAssertEqual(maxY, (4900 * 4900 - 50 * 50).squareRoot(), accuracy: 1)
    }

    func testNicheKeepsBackOfWall() {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 300, height: 3000)))
        let full = MeshTools.signedVolume(MeshBuilder.build(doc: doc).first { $0.id == w }!.mesh)
        _ = doc.addElement(.opening(OpeningGeom(kind: .opening, hostWall: w, offset: 2000, width: 1000, height: 1000, sill: 1000, depth: 100)))
        let v = MeshTools.signedVolume(MeshBuilder.build(doc: doc).first { $0.id == w }!.mesh)
        XCTAssertEqual(full - v, 1000 * 1000 * 100, accuracy: 1)
    }

    func testSlopedSlabVolumeAndHeight() {
        var doc = ArchiDocument()
        let s = SlabGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 1500), Vec2(0, 1500)], thickness: 200, topOffset: 0,
                         slope: atan(1.0 / 12) * 180 / .pi, slopeDirection: 0, slopeOrigin: Vec2(0, 0))
        XCTAssertEqual(s.topHeight(at: Vec2(6000, 700)), 500, accuracy: 1e-6)
        let id = doc.addElement(.slab(s))
        let g = MeshBuilder.build(doc: doc).first { $0.id == id }!
        XCTAssertEqual(g.mesh.bounds.max.z, 500, accuracy: 1e-6)
        let vol = MeshTools.signedVolume(g.mesh)
        XCTAssertEqual(vol, 6000 * 1500 * 200 / cos(atan(1.0 / 12)), accuracy: 10)
    }

    func testWallSweepAddsProfileVolume() {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200, height: 3000,
                                              sweeps: [WallSweep(profile: "rect", depth: 50, height: 100, elevation: 2900, side: 1)])))
        let sweep = MeshBuilder.build(doc: doc).filter { $0.id == w && $0.kind == "wallSweep" }
        XCTAssertEqual(sweep.count, 1)
        XCTAssertEqual(MeshTools.signedVolume(sweep[0].mesh), 5000 * 50 * 100, accuracy: 1)
        XCTAssertEqual(sweep[0].mesh.bounds.max.y, 150, accuracy: 1e-6)
    }

    func testCurtainWallCustomGrid() {
        var g = CurtainWallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), height: 3000)
        XCTAssertEqual(g.uPositions.count, 4)
        g.uLines = [1500, 4500]; g.vLines = [1000]
        XCTAssertEqual(g.uPositions, [1500, 4500]); XCTAssertEqual(g.vPositions, [1000])
        g.panels["1,0"] = "solid"
        var doc = ArchiDocument()
        let id = doc.addElement(.curtainWall(g))
        let groups = MeshBuilder.build(doc: doc).filter { $0.id == id }
        XCTAssertEqual(groups.count, 3)
    }

    func testSkeletonRobustShapes() {
        let shapes: [[Vec2]] = [
            // T
            [Vec2(0, 0), Vec2(3000, 0), Vec2(3000, 6000), Vec2(7000, 6000), Vec2(7000, 9000), Vec2(-4000, 9000), Vec2(-4000, 6000), Vec2(0, 6000)],
            // U
            [Vec2(0, 0), Vec2(12000, 0), Vec2(12000, 9000), Vec2(8000, 9000), Vec2(8000, 4000), Vec2(4000, 4000), Vec2(4000, 9000), Vec2(0, 9000)],
            // Collinear vertex and a skewed edge
            [Vec2(0, 0), Vec2(5000, 0), Vec2(10000, 0), Vec2(11000, 6000), Vec2(6000, 6000), Vec2(6000, 3000), Vec2(0, 3000)],
            // Rotated L (clockwise input)
            [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(4000, 4000), Vec2(4000, 9000), Vec2(0, 9000)].map { $0.rotated(by: 0.3) }.reversed(),
        ]
        for poly in shapes {
            let f = StraightSkeleton.faces(poly)
            XCTAssertGreaterThanOrEqual(f.count, RG.dedupe(poly, closed: true).count - 1)
            XCTAssertEqual(f.reduce(0) { $0 + area($1.poly) }, area(poly), accuracy: area(poly) * 1e-6)
            let r = RoofShapes.faces(RoofGeom(boundary: poly, kind: .hip, pitch: 35, overhang: 400))
            XCTAssertFalse(r.faces.isEmpty)
            let fpArea = area(r.footprint)
            XCTAssertEqual(r.faces.reduce(0) { $0 + area($1.poly) }, fpArea, accuracy: fpArea * 1e-6)
            // Eave line (the original outline) is at height 0 on the face that covers it.
            let e0 = RG.dedupe(poly, closed: true)
            let mid = (e0[0] + e0[1]) / 2
            let h = r.faces.filter { GeometryOps.pointInPolygon(mid, $0.poly) }.map { $0.height(mid) }
            for v in h { XCTAssertEqual(v, 0, accuracy: 1e-6) }
        }
    }
}
