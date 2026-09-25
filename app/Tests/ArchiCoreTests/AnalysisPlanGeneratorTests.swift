// Oanarina Archi Tool — GPL-3.0-or-later
// Plan generation from a brief (SCR-028).
import XCTest
@testable import ArchiCore

final class AnalysisPlanGeneratorTests: XCTestCase {
    let brief = "Living 26, Kitchen 12, Bedroom 14 x2, Bath 6, Hall 8"

    func testBriefParsing() {
        let b = PlanGenerator.parseBrief(brief + "; WC 2m2")
        XCTAssertEqual(b.map(\.name), ["Living", "Kitchen", "Bedroom", "Bedroom", "Bath", "Hall", "WC"])
        XCTAssertEqual(b.reduce(0) { $0 + $1.area }, 82)
    }

    func testOptionsMatchAreasAndAreConnected() {
        let rooms = PlanGenerator.parseBrief(brief)   // 80 m² into 10 × 8 m
        let opts = PlanGenerator.options(rooms, width: 10_000, depth: 8000, unitsPerM2: 1_000_000)
        XCTAssertGreaterThanOrEqual(opts.count, 3)
        XCTAssertTrue(zip(opts, opts.dropFirst()).allSatisfy { $0.score >= $1.score }, "best first")
        for o in opts {
            XCTAssertEqual(o.rooms.count, 6)
            XCTAssertEqual(o.cuts.count, 5, "n − 1 slicing cuts")
            let total = o.rooms.reduce(0) { $0 + $1.area }
            XCTAssertEqual(total, 80_000_000, accuracy: 1)
            for r in o.rooms {
                let target = rooms.first { $0.name == r.name }!.area * 1_000_000
                XCTAssertEqual(r.area, target, accuracy: target * 0.01, "\(r.name) area within 1 %")
            }
        }
        var d = ArchiDocument()
        let res = PlanGenerator.build(opts[0], into: &d, level: 0, exterior: 300, interior: 100, height: 3000, unitMM: 1)
        XCTAssertEqual(res.rooms.count, 6); XCTAssertEqual(res.walls.count, 9)
        XCTAssertEqual(res.windows.count, 4, "living, kitchen and two bedrooms")
        // Every room reachable from the entrance through doors.
        let spaces = res.rooms.compactMap { id -> (EntityID, [Vec2])? in if case .space(let s) = d.element(id)?.geometry { return (id, s.boundary) }; return nil }
        var graph: [EntityID: Set<EntityID>] = [:]
        var entrance: EntityID?
        for id in res.doors {
            guard case .opening(let o) = d.element(id)?.geometry, case .wall(let w) = d.element(o.hostWall)?.geometry else { continue }
            let p = w.centerStart + w.direction * o.offset
            let n = w.direction.perp * 200
            let a = spaces.first { GeometryOps.pointInPolygon(p + n, $0.1) }?.0, b = spaces.first { GeometryOps.pointInPolygon(p - n, $0.1) }?.0
            if let a, let b { graph[a, default: []].insert(b); graph[b, default: []].insert(a) } else { entrance = a ?? b }
        }
        let start = try! XCTUnwrap(entrance)
        var seen: Set<EntityID> = [start], q = [start]
        while let x = q.popLast() { for y in graph[x] ?? [] where !seen.contains(y) { seen.insert(y); q.append(y) } }
        XCTAssertEqual(seen.count, 6, "all rooms connected")
        XCTAssertTrue(ModelChecker.check(d).filter { $0.severity == .error }.isEmpty, ModelChecker.check(d).map(\.description).joined(separator: "\n"))
    }

    @MainActor func testCommandBuildsAfterConfirmation() async {
        let ed = Editor()
        await ed.run("PLANGEN \"\(brief)\" 10000 8000 0,0 1 N")
        XCTAssertTrue(ed.doc.elements.isEmpty, "declined")
        await ed.run("PLANGEN \"\(brief)\" 10000 8000 0,0 2 Y")
        XCTAssertEqual(ed.doc.elements.filter { $0.typeName == "space" }.count, 6)
        ed.undo()
        XCTAssertTrue(ed.doc.elements.isEmpty)
    }
}
