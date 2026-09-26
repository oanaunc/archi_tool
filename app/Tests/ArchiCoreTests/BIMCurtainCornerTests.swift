// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Curtain wall corner joins (BIM-028): one corner post instead of two overlapping border mullions.
final class BIMCurtainCornerTests: XCTestCase {
    func fills(_ items: [DrawItem]) -> [[Vec2]] { items.compactMap { if case .fill(let l, _) = $0 { return l.first }; return nil } }

    func testCornerPostInPlanAnd3D() {
        var doc = ArchiDocument()
        let a = doc.addElement(.curtainWall(CurtainWallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), height: 3000, gridU: 1200, gridV: 1500, mullionSize: 60)))
        let b = doc.addElement(.curtainWall(CurtainWallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), height: 3000, gridU: 1200, gridV: 1500, mullionSize: 60)))
        let ctx = BIMContext(doc: doc)
        XCTAssertEqual(ctx.curtainCorners[a]?.end.joined, true); XCTAssertNotNil(ctx.curtainCorners[a]?.end.post)
        XCTAssertEqual(ctx.curtainCorners[b]?.start.joined, true); XCTAssertNil(ctx.curtainCorners[b]?.start.post)
        XCTAssertEqual(ctx.curtainCorners[a]?.start.joined ?? false, false)
        // Plan: the post (drawn once, by A) fills the outer corner; B draws no border mullion at the corner.
        let fa = fills(PlanRepresentation.items(doc.element(a)!, doc: doc)), fb = fills(PlanRepresentation.items(doc.element(b)!, doc: doc))
        XCTAssertTrue(fa.contains { GeometryOps.pointInPolygon(Vec2(5036, -36), $0) })
        XCTAssertTrue(fa.contains { GeometryOps.pointInPolygon(Vec2(5000, 0), $0) })
        XCTAssertFalse(fb.contains { GeometryOps.pointInPolygon(Vec2(5000, 10), $0) })
        // 3D: A's frame reaches the outer corner, B's frame starts after the post.
        func frameBounds(_ id: EntityID) -> BBox3 {
            var bb = BBox3.empty
            for g in MeshBuilder.groups(for: doc.element(id)!, doc: doc) where g.material == "Aluminium" { g.mesh.positions.forEach { bb.add($0) } }
            return bb
        }
        XCTAssertEqual(frameBounds(a).max.x, 5045, accuracy: 1)
        XCTAssertGreaterThan(frameBounds(b).min.y, 0)
        // Collinear continuation: no corner post.
        var d2 = ArchiDocument()
        let c1 = d2.addElement(.curtainWall(CurtainWallGeom(start: Vec2(0, 0), end: Vec2(3000, 0))))
        _ = d2.addElement(.curtainWall(CurtainWallGeom(start: Vec2(3000, 0), end: Vec2(6000, 0))))
        XCTAssertNil(BIMContext(doc: d2).curtainCorners[c1])
    }
}
