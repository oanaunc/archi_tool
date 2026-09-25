// Oanarina Archi Tool — GPL-3.0-or-later
// 4D sequencing (ANL-017) and resources (ANL-018).
import XCTest
@testable import ArchiCore

final class AnalysisWorkScheduleTests: XCTestCase {
    func building() -> ArchiDocument {
        var d = ArchiDocument()
        d.levels = [Level(id: 0, name: "GF", elevation: 0), Level(id: 1, name: "1F", elevation: 3000)]
        let fnd = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)], thickness: 500)), level: 0)
        d.elements[d.elementIndex(fnd)!].props["kind"] = "foundation"
        for lv in [0, 1] {
            let pts = [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)]
            var first: EntityID = 0
            for i in 0..<4 { let w = d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300, height: 3000)), level: lv); if i == 0 { first = w } }
            d.addElement(.opening(OpeningGeom(kind: .window, hostWall: first, offset: 3000, width: 1200, height: 1400, sill: 900)), level: lv)
            d.addElement(.column(ColumnGeom(position: Vec2(5000, 4000), width: 400, depth: 400, height: 3000)), level: lv)
        }
        d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)], thickness: 250)), level: 1)
        d.addElement(.roof(RoofGeom(boundary: [Vec2(0, 0), Vec2(10_000, 0), Vec2(10_000, 8000), Vec2(0, 8000)], kind: .flat)), level: 1)
        return d
    }

    func testGenerateDurationsFromQuantitiesAndCPM() throws {
        let d = building()
        let s = Scheduler.generate(d, start: "2026-03-02")   // a Monday
        let names = s.tasks.map(\.name)
        XCTAssertEqual(names.first, "GF — Foundations")
        XCTAssertTrue(names.contains("1F — Floor slabs"))
        // Foundation 10 × 8 × 0.5 = 40 m³ at 8 m³/day → 5 days; walls GF 36 × 3 = 108 m² at 20 m²/day → 6 days.
        XCTAssertEqual(s.tasks.first { $0.name == "GF — Foundations" }?.duration, 5)
        let walls = try XCTUnwrap(s.tasks.first { $0.name == "GF — Walls" })
        XCTAssertEqual(walls.quantity, 108, accuracy: 1e-9)
        XCTAssertEqual(walls.duration, 6)
        XCTAssertEqual(walls.elements.count, 4)
        // Every element with a trade is scheduled exactly once.
        let scheduled = s.tasks.flatMap(\.elements)
        XCTAssertEqual(scheduled.count, Set(scheduled).count)
        XCTAssertEqual(Set(scheduled).count, d.elements.count)
        let tm = try Scheduler.cpm(s)
        let critical = s.tasks.filter { tm[$0.id]!.critical }.map(\.name)
        XCTAssertTrue(critical.contains("GF — Walls")); XCTAssertTrue(critical.contains("1F — Roof"))
        XCTAssertFalse(critical.contains("GF — Doors and windows"), "windows have float")
        // Calendar: 5 working days from Monday 2 March end on Friday 6 March; the next task starts Monday 9 March.
        let f = Scheduler.dayFormatter()
        XCTAssertEqual(f.string(from: Scheduler.date(s, workday: 4)), "2026-03-06")
        XCTAssertEqual(f.string(from: Scheduler.date(s, workday: 5)), "2026-03-09")
        XCTAssertEqual(Scheduler.workday(s, of: f.date(from: "2026-03-07")!), 4, "Saturday counts as the Friday before")
        // Cycle detection.
        var bad = s; bad.tasks[0].predecessors = [s.tasks.last!.id]
        XCTAssertThrowsError(try Scheduler.cpm(bad))
    }

    func testFourDStatesResourcesAndLevelling() throws {
        let s = Scheduler.generate(building(), start: "2026-03-02")
        let tm = try Scheduler.cpm(s)
        let fnd = s.tasks[0]
        let st0 = Scheduler.states(s, timing: tm, day: 0)
        XCTAssertEqual(st0[fnd.elements[0]], .inProgress)
        let st5 = Scheduler.states(s, timing: tm, day: tm[fnd.id]!.ef - 1)
        XCTAssertEqual(st5[fnd.elements[0]], .complete)
        let end = tm.values.map(\.ef).max()!
        XCTAssertTrue(Scheduler.states(s, timing: tm, day: end).values.allSatisfy { $0 == .complete })
        // Resources: histogram peaks and cost = Σ units × days × rate.
        let h = Scheduler.histogram(s, timing: tm)
        XCTAssertEqual(h["Concrete crew"]?.max(), 5)
        var expected = 0.0
        for t in s.tasks { for (name, u) in t.resources { expected += u * Double(t.duration) * (s.resources.first { $0.name == name }?.costPerDay ?? 0) } }
        XCTAssertEqual(Scheduler.cost(s).total, expected, accuracy: 1e-6)
        // Two parallel tasks sharing one crane are over-allocated; levelling runs them one after the other.
        var p = WorkSchedule(name: "P", start: "2026-03-02", tasks: [
            ScheduleTask(id: 1, name: "A", duration: 3, resources: ["Crane": 1]),
            ScheduleTask(id: 2, name: "B", duration: 2, resources: ["Crane": 1, "Masonry crew": 2]),
            ScheduleTask(id: 3, name: "C", duration: 1, predecessors: [1, 2], resources: ["Masonry crew": 9]),
        ], resources: Scheduler.defaultResources)
        XCTAssertEqual(Scheduler.overallocations(p, timing: try Scheduler.cpm(p))["Crane"]?.count, 2)
        let lv = try Scheduler.level(p)
        let lt = try Scheduler.cpm(lv)
        XCTAssertNil(Scheduler.overallocations(lv, timing: lt)["Crane"])
        XCTAssertEqual(lt.values.map(\.ef).max(), 6, "3 + 2 in sequence, then C")
        p.tasks[2].duration = 0
        XCTAssertNoThrow(try Scheduler.level(p))
    }

    @MainActor func testCommandsAndIFCExport() async throws {
        let ed = Editor()
        ed.doc = building()
        await ed.run("WORKSCHEDULE Generate 2026-03-02")
        XCTAssertNotNil(Scheduler.load(ed.doc))
        let sim = await ed.run("WORKSCHEDULE Simulate 2026-03-10")
        XCTAssertTrue(sim.joined().contains("complete"), sim.joined(separator: "\n"))
        XCTAssertFalse(ed.selection.isEmpty)
        await ed.run("WORKSCHEDULE Duration 1 7")
        XCTAssertEqual(Scheduler.load(ed.doc)?.tasks[0].duration, 7)
        ed.undo()
        XCTAssertEqual(Scheduler.load(ed.doc)?.tasks[0].duration, 5, "schedule edits are undoable")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gantt-\(UUID().uuidString).svg")
        await ed.run("WORKSCHEDULE Gantt \(url.path)")
        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(svg.components(separatedBy: "class=\"task\"").count - 1, Scheduler.load(ed.doc)!.tasks.count)
        let ifc = IFCExporter.export(doc: ed.doc, meshes: MeshBuilder.build(doc: ed.doc), options: IFCExportOptions(schema: .ifc4))
        XCTAssertEqual(IFCValidator.validate(ifc).filter { $0.severity == .error }.map(\.description), [])
        let n = Scheduler.load(ed.doc)!.tasks.count
        XCTAssertEqual(ifc.components(separatedBy: "=IFCTASK(").count - 1, n)
        XCTAssertEqual(ifc.components(separatedBy: "=IFCWORKSCHEDULE(").count - 1, 1)
        XCTAssertGreaterThan(ifc.components(separatedBy: "=IFCRELSEQUENCE(").count - 1, 5)
        XCTAssertTrue(ifc.contains("'2026-03-02T08:00:00'"))
    }
}
