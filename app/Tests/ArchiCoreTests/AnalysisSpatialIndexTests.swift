// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisSpatialIndexTests: XCTestCase {
    func randomBoxes(_ n: Int, seed: UInt64) -> [SpatialIndex.Item] {
        var s = seed
        func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        return (0..<n).map { i in
            let x = r() * 10_000, y = r() * 10_000, w = r() * 300, h = r() * 300
            return SpatialIndex.Item(id: i + 1, box: BBox2(min: Vec2(x, y), max: Vec2(x + w, y + h)))
        }
    }

    func testWindowQueriesMatchBruteForce() {
        let items = randomBoxes(5000, seed: 7)
        let idx = SpatialIndex(items: items, nodeCapacity: 8)
        XCTAssertEqual(idx.count, 5000)
        XCTAssertGreaterThan(idx.depth, 2)
        for q in 0..<50 {
            let x = Double(q) * 190, y = Double(q * 37 % 50) * 190
            let box = BBox2(min: Vec2(x, y), max: Vec2(x + 800, y + 500))
            XCTAssertEqual(Set(idx.query(box)), Set(items.filter { $0.box.intersects(box) }.map(\.id)))
            XCTAssertEqual(Set(idx.contained(in: box)), Set(items.filter { box.contains($0.box) }.map(\.id)))
        }
    }

    func testNearestMatchesBruteForce() {
        let items = randomBoxes(2000, seed: 3)
        let idx = SpatialIndex(items: items)
        for q in 0..<30 {
            let p = Vec2(Double(q) * 333, Double(q * 13 % 30) * 333)
            let best = items.map { ($0.id, SpatialIndex.boxDistance(p, $0.box)) }.min { $0.1 < $1.1 }!
            let got = idx.nearest(to: p, k: 3)
            XCTAssertEqual(got.count, 3)
            XCTAssertEqual(got[0].distance, best.1, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(got[0].distance, got[1].distance)
        }
        XCTAssertTrue(idx.nearest(to: Vec2(-1e6, -1e6), maxDistance: 10).isEmpty)
    }

    func testDocumentIndexUsesTrueGeometryForNearest() {
        var d = ArchiDocument()
        // A long diagonal line whose box covers the point, and a small circle a bit away: the circle is truly nearer.
        _ = d.add(.line(LineGeom(Vec2(0, 0), Vec2(10_000, 10_000))))
        let c = d.add(.circle(CircleGeom(Vec2(8000, 1500), 100)))
        let w = d.addElement(.wall(WallGeom(start: Vec2(0, -5000), end: Vec2(5000, -5000))), level: 0)
        let idx = SpatialIndex(doc: d)
        XCTAssertEqual(idx.count, 3)
        XCTAssertEqual(SpatialIndex.nearestObject(in: d, index: idx, to: Vec2(8000, 1800)), c)
        XCTAssertEqual(Set(idx.query(point: Vec2(2500, -5000), tolerance: 10)), [w])
        XCTAssertEqual(SpatialIndex(doc: d, level: 1).count, 2, "elements of other levels are left out")
        XCTAssertTrue(SpatialIndex(items: []).query(BBox2(min: .zero, max: Vec2(1, 1))).isEmpty)
    }

    /// SYS-015 benchmark: 100 000 objects index in well under a second and a pick (point query) or a viewport window
    /// query costs microseconds, so picking and snapping stay interactive (limits are for unoptimised debug builds).
    func testHundredThousandObjectsBenchmark() {
        let items = randomBoxes(100_000, seed: 11).map { var i = $0; i.box = BBox2(min: i.box.min * 10, max: i.box.min * 10 + (i.box.max - i.box.min)); return i }
        var t = Date()
        let idx = SpatialIndex(items: items)
        let build = Date().timeIntervalSince(t)
        XCTAssertLessThan(build, 5, "build \(build) s")
        t = Date()
        var hits = 0
        for q in 0..<10_000 {
            let p = Vec2(Double(q * 7919 % 100_000), Double(q * 104_729 % 100_000))
            hits += idx.query(point: p, tolerance: 50).count
        }
        let picks = Date().timeIntervalSince(t)
        XCTAssertLessThan(picks / 10_000, 0.0005, "per pick \(picks / 10_000) s")
        t = Date()
        for q in 0..<1000 {
            let c = Vec2(Double(q * 97 % 100_000), Double(q * 61 % 100_000))
            hits += idx.query(BBox2(min: c, max: c + Vec2(5000, 3000))).count
        }
        XCTAssertLessThan(Date().timeIntervalSince(t) / 1000, 0.002)
        XCTAssertGreaterThan(hits, 0)
    }
}
