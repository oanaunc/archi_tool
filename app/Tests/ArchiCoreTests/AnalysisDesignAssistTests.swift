// Oanarina Archi Tool — GPL-3.0-or-later
// Auto-dimensioning (SCR-029), room naming (SCR-030), model QA assistant (SCR-033).
import XCTest
@testable import ArchiCore

final class AnalysisDesignAssistTests: XCTestCase {
    func flat() -> (ArchiDocument, [String: EntityID]) {
        var d = ArchiDocument()
        var ids: [String: EntityID] = [:]
        let pts = [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)]
        var walls: [EntityID] = []
        for i in 0..<4 {
            let w = d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300, height: 3000)), level: 0)
            d.elements[d.elementIndex(w)!].props["isExternal"] = "1"
            walls.append(w)
        }
        d.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 8000), thickness: 100, height: 3000)), level: 0)
        d.addElement(.wall(WallGeom(start: Vec2(6000, 4000), end: Vec2(10_000, 4000), thickness: 100, height: 3000)), level: 0)
        // South facade: two windows; the entrance door on the west wall.
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 2000, width: 1200, height: 1400, sill: 900)), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 8000, width: 1000, height: 1400, sill: 900)), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[1], offset: 6000, width: 1000, height: 1400, sill: 900)), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: walls[3], offset: 4000, width: 1000, height: 2100)), level: 0)
        ids["living"] = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 8000), Vec2(0, 8000)], name: "Room")), level: 0)
        ids["bed"] = d.addElement(.space(SpaceGeom(boundary: [Vec2(6000, 0), Vec2(10_000, 0), Vec2(10_000, 4000), Vec2(6000, 4000)], name: "")), level: 0)
        ids["bath"] = d.addElement(.space(SpaceGeom(boundary: [Vec2(6000, 4000), Vec2(10_000, 4000), Vec2(10_000, 8000), Vec2(6000, 8000)], name: "Room")), level: 0)
        d.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(7000, 6000), block: "Toilet")), level: 0)
        d.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(8000, 7000), block: "Shower tray")), level: 0)
        return (d, ids)
    }

    func testPlanDimensionChains() {
        let (d, _) = flat()
        let dims = PlanDimensions.dimensions(d, level: 0, offset: 1000, spacing: 600, style: "Standard")
        func side(_ y: Double) -> [DimensionGeom] { dims.filter { $0.rotation == 0 && abs($0.points[2].y - y) < 1 } }
        // South: outline −150 … 10 150 → openings row: 5 segments (wall end, 2 × window edges, wall end).
        let south0 = side(-150 - 1000), south1 = side(-150 - 1600)
        XCTAssertEqual(south0.count, 5)
        XCTAssertEqual(south1.count, 1, "overall")
        XCTAssertEqual(abs(south1[0].points[1].x - south1[0].points[0].x), 10_300, accuracy: 1e-6)
        let total = south0.reduce(0.0) { $0 + abs($1.points[1].x - $1.points[0].x) }
        XCTAssertEqual(total, 10_300, accuracy: 1e-6, "the chain adds up to the overall dimension")
        // The west side has the door row, the vertical dims are rotated 90°.
        XCTAssertTrue(dims.contains { $0.rotation == .pi / 2 && abs($0.points[2].x - (-150 - 1000)) < 1 })
        XCTAssertEqual(dims.filter { $0.rotation == .pi / 2 && abs($0.points[2].x - (10_150 + 1000)) < 1 }.count, 3, "east: window row (3) then overall")
    }

    @MainActor func testAutoDimCommandIsOneUndoStep() async {
        let ed = Editor()
        ed.doc = flat().0
        await ed.run("AUTODIMPLAN 1000 600 Y")
        let n = ed.doc.entities.filter { $0.layer == "A-ANNO-DIMS" }.count
        XCTAssertGreaterThan(n, 10)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 0)
        await ed.run("AUTODIMPLAN 1000 600 N")
        XCTAssertEqual(ed.doc.entities.count, 0, "declined")
    }

    func testRoomClassificationAndNumbering() {
        let (d, ids) = flat()
        XCTAssertEqual(RoomNaming.classify(d.element(ids["bath"]!)!, doc: d).name, "Bathroom")
        XCTAssertEqual(RoomNaming.classify(d.element(ids["living"]!)!, doc: d).name, "Living room")
        XCTAssertEqual(RoomNaming.classify(d.element(ids["bed"]!)!, doc: d).name, "Bedroom")
        let sug = RoomNaming.suggest(d, level: 0, onlyUnnamed: true)
        XCTAssertEqual(Set(sug.map(\.number)).count, 3)
        XCTAssertEqual(sug.first { $0.id == ids["bath"] }?.number, "001", "top-left room first")
    }

    @MainActor func testRoomNamingCommandAndQAFixes() async throws {
        let ed = Editor()
        var (d, ids) = flat()
        // Problems: zero-length wall, window wider than its wall, duplicate line, a room without height.
        d.addElement(.wall(WallGeom(start: Vec2(20_000, 0), end: Vec2(20_000, 0))), level: 0)
        let short = d.addElement(.wall(WallGeom(start: Vec2(0, 20_000), end: Vec2(1000, 20_000))), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: short, offset: 500, width: 1500, height: 1000, sill: 900)), level: 0)
        d.add(.line(LineGeom(.zero, Vec2(5, 5)))); d.add(.line(LineGeom(.zero, Vec2(5, 5))))
        if let i = d.elementIndex(ids["living"]!), case .space(var s) = d.elements[i].geometry { s.height = 0; d.elements[i].geometry = .space(s) }
        ed.doc = d
        let adv = ModelQA.advise(ed.doc)
        XCTAssertTrue(adv.allSatisfy { !$0.explanation.isEmpty && !$0.suggestion.isEmpty })
        XCTAssertTrue(adv.contains { $0.issue.code == "WALL-LENGTH" && $0.fixable })
        let out = await ed.run("QAASSIST FixAll Y")
        XCTAssertTrue(out.joined(separator: "\n").contains("Applied"), out.joined(separator: "\n"))
        let left = ModelChecker.check(ed.doc).map(\.code)
        for c in ["WALL-LENGTH", "OPENING-WIDER", "ENTITY-DUPLICATE", "ROOM-HEIGHT", "ROOM-UNNAMED", "ROOM-UNNUMBERED"] { XCTAssertFalse(left.contains(c), c) }
        XCTAssertEqual(ed.doc.entities.count, 1)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 2, "all fixes are one undo step")
        await ed.run("AUTONAMEROOMS All Y")
        let names = ed.doc.elements.compactMap { el -> String? in if case .space(let s) = el.geometry { return s.name }; return nil }.sorted()
        XCTAssertEqual(names, ["Bathroom", "Bedroom", "Living room"])
    }
}
