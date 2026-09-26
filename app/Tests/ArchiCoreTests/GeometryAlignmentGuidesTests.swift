// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Inference guides (PRC-027 core).
final class GeometryAlignmentGuidesTests: XCTestCase {
    func testAxisParallelAndFromPointInference() {
        let r = AlignmentGuides.infer(cursor: Vec2(1000, 7), base: .zero, tolerance: 10)!
        XCTAssertEqual(r.point, Vec2(1000, 0)); XCTAssertEqual(r.guides.first?.kind, .onAxisX)
        XCTAssertNil(AlignmentGuides.infer(cursor: Vec2(1000, 500), base: .zero, tolerance: 10))
        let d = Vec2(1, 1).normalized
        let p = AlignmentGuides.infer(cursor: Vec2(503, 497), base: .zero, reference: d, tolerance: 10)!
        XCTAssertEqual(p.guides.first?.kind, .parallel)
        XCTAssertEqual(p.point.x, 500, accuracy: 1e-9); XCTAssertEqual(p.point.y, 500, accuracy: 1e-9)
        // On the X axis from the base and aligned (vertically) with an acquired point: the intersection.
        let q = AlignmentGuides.infer(cursor: Vec2(2004, 5), base: .zero, points: [Vec2(2000, 3000)], tolerance: 10)!
        XCTAssertEqual(q.point.x, 2000, accuracy: 1e-9); XCTAssertEqual(q.point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(q.guides.count, 2)
    }
}
