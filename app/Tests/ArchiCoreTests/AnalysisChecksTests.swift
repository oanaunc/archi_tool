// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisChecksTests: XCTestCase {
    func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] { [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)] }

    func testLoadTakedownMatchesHandCalculation() throws {
        var d = ArchiDocument()
        d.levels.append(Level(id: 2, name: "Roof", elevation: 6000))
        var lower: [EntityID] = [], upper: [EntityID] = []
        for p in [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 6000), Vec2(0, 6000)] {
            lower.append(d.addElement(.column(ColumnGeom(position: p, width: 300, depth: 300, height: 2800)), level: 0, material: "Concrete"))
            upper.append(d.addElement(.column(ColumnGeom(position: p, width: 300, depth: 300, height: 2800)), level: 1, material: "Concrete"))
        }
        _ = d.addElement(.slab(SlabGeom(boundary: rect(0, 0, 6000, 6000), thickness: 200)), level: 1, material: "Concrete")
        _ = d.addElement(.slab(SlabGeom(boundary: rect(0, 0, 6000, 6000), thickness: 200)), level: 2, material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: rect(0, 0, 6000, 6000), name: "Office")), level: 1)
        var o = TakedownOptions(); o.cell = 100
        let r = LoadTakedown.compute(d, options: o)
        XCTAssertEqual(r.rows.count, 8)
        let own = 25 * 0.3 * 0.3 * 2.8
        for id in upper {
            let row = try XCTUnwrap(r.rows.first { $0.column == id })
            XCTAssertEqual(row.area, 9, accuracy: 1e-6)
            XCTAssertEqual(row.dead, (25 * 0.2 + 1.5) * 9 + own, accuracy: 1e-6)
            XCTAssertEqual(row.live, 0.75 * 9, accuracy: 1e-6, "roof imposed load")
            XCTAssertNil(row.above)
        }
        for (i, id) in lower.enumerated() {
            let row = try XCTUnwrap(r.rows.first { $0.column == id })
            XCTAssertEqual(row.above, upper[i])
            XCTAssertEqual(row.live, 3.0 * 9, accuracy: 1e-6, "office imposed load")
            let td = 2 * ((25 * 0.2 + 1.5) * 9 + own), tl = 3.0 * 9 + 0.75 * 9
            XCTAssertEqual(row.totalDead, td, accuracy: 1e-6); XCTAssertEqual(row.totalLive, tl, accuracy: 1e-6)
            XCTAssertEqual(row.uls, 1.35 * td + 1.5 * tl, accuracy: 1e-6)
            XCTAssertEqual(row.sls, td + tl, accuracy: 1e-6)
            XCTAssertEqual(row.stress, (1.35 * td + 1.5 * tl) * 1000 / 90_000, accuracy: 1e-9)
        }
        // A bearing wall along one edge takes the floor strip nearest to it.
        _ = d.addElement(.wall(WallGeom(start: Vec2(3000, 0), end: Vec2(3000, 6000), thickness: 250, height: 2800)), level: 0)
        let r2 = LoadTakedown.compute(d, options: o)
        XCTAssertGreaterThan(r2.wallArea, 0)
        XCTAssertLessThan(r2.rows.first { $0.column == lower[0] }!.area, 9)
        XCTAssertEqual(TakedownOptions().liveLoad(BIMElement(id: 1, geometry: .space(SpaceGeom(boundary: rect(0, 0, 1, 1), name: "Archive")))), 7.5)
    }

    func testRainwaterFromRoofs() throws {
        var d = ArchiDocument()
        let roof = d.addElement(.roof(RoofGeom(boundary: rect(0, 0, 10000, 8000), kind: .gable, pitch: 30, overhang: 500)))
        var flat = d.addElement(.slab(SlabGeom(boundary: rect(20000, 0, 30000, 10000), thickness: 250)), level: 0)
        if let i = d.elementIndex(flat) { d.elements[i].props["roof"] = "1" }
        flat += 0
        let rows = Rainwater.compute(d)
        XCTAssertEqual(rows.count, 2)
        let r = try XCTUnwrap(rows.first { $0.element == roof })
        XCTAssertEqual(r.planArea, 80 + 36 * 0.5 + 4 * 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.coefficient, 1)
        XCTAssertEqual(r.flow, 0.03 * 99, accuracy: 1e-9)
        XCTAssertEqual(r.downpipes, 1); XCTAssertEqual(r.downpipeDN, 90)
        XCTAssertEqual(r.gutterLength, 22, accuracy: 1e-9)
        XCTAssertEqual(r.harvest, 99 * 0.6 * 0.8, accuracy: 1e-9)
        let f = try XCTUnwrap(rows.first { $0.element == flat })
        XCTAssertEqual(f.planArea, 100, accuracy: 1e-9); XCTAssertEqual(f.coefficient, 0.8)
        // A large roof needs several DN100 pipes.
        var big = ArchiDocument()
        _ = big.addElement(.roof(RoofGeom(boundary: rect(0, 0, 40000, 30000), kind: .flat, pitch: 0, overhang: 0)))
        let b = Rainwater.compute(big)[0]
        XCTAssertEqual(b.flow, 0.8 * 0.03 * 1200, accuracy: 1e-9)
        XCTAssertEqual(b.downpipes, Int((28.8 / 4.6).rounded(.up))); XCTAssertEqual(b.downpipeDN, 100)
    }

    func testParkingProvision() {
        var d = ArchiDocument()
        _ = d.addElement(.space(SpaceGeom(boundary: rect(0, 0, 35000, 20000), name: "Open Office")))
        _ = d.addElement(.space(SpaceGeom(boundary: rect(0, 30000, 8000, 38000), name: "Apartment 1")))
        _ = d.addElement(.space(SpaceGeom(boundary: rect(10000, 30000, 18000, 38000), name: "Apartment 2")))
        _ = d.addElement(.space(SpaceGeom(boundary: rect(20000, 30000, 22000, 32000), name: "Plant")))
        for i in 0..<21 {
            let id = d.addElement(.component(ComponentGeom(category: "Site", position: Vec2(Double(i) * 2500, -10000), rotation: 0, size: Vec3(2500, 5000, 5), family: "parking")), name: "Parking Space")
            if i == 0, let k = d.elementIndex(id) { d.elements[k].props["accessible"] = "1" }
        }
        let r = ParkingCheck.check(d)
        XCTAssertEqual(r.required, 22)
        XCTAssertEqual(r.provided, 21); XCTAssertEqual(r.accessibleProvided, 1); XCTAssertEqual(r.accessibleRequired, 1)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.lines.first { $0.usage == "office" }?.required ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(ParkingCheck.check(d, rules: ParkingRule.parse("office=50;apartment=unit:1")).required, 16)
        XCTAssertEqual(ParkingCheck.accessibleRequired(150), 5)
        XCTAssertEqual(ParkingRule.parse("x=unit:2;bad;y=0").count, 1)
    }

    func testFireCompartments() {
        var d = ArchiDocument()
        d.setVariable("FIREMAXAREA", "50")
        var a = d.addElement(.space(SpaceGeom(boundary: rect(0, 0, 6000, 10000), name: "Store")))
        let b = d.addElement(.space(SpaceGeom(boundary: rect(6200, 0, 10000, 10000), name: "Office")))
        if let i = d.elementIndex(a) { d.elements[i].props["fireCompartment"] = "FC1" }
        if let i = d.elementIndex(b) { d.elements[i].props["fireCompartment"] = "FC2" }
        a += 0
        let wall = d.addElement(.wall(WallGeom(start: Vec2(6100, 0), end: Vec2(6100, 10000), thickness: 200, height: 3000)))
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 200, height: 3000)))
        let r = FireCompartments.check(d)
        XCTAssertEqual(r.compartments.map(\.name), ["FC1", "FC2"])
        XCTAssertEqual(r.compartments[0].area, 60, accuracy: 1e-9); XCTAssertFalse(r.compartments[0].ok)
        XCTAssertEqual(r.compartments[1].area, 38, accuracy: 1e-9); XCTAssertTrue(r.compartments[1].ok)
        XCTAssertEqual(r.unratedWalls, [wall])
        if let i = d.elementIndex(wall) { d.elements[i].props["fireRating"] = "EI 90" }
        d.setVariable("FIRESPRINKLERS", "1")
        let r2 = FireCompartments.check(d)
        XCTAssertTrue(r2.unratedWalls.isEmpty)
        XCTAssertTrue(r2.compartments.allSatisfy(\.ok))
        XCTAssertEqual(FireCompartments.minutes("REI 120"), 120); XCTAssertEqual(FireCompartments.minutes("1h"), 60); XCTAssertNil(FireCompartments.minutes("none"))
    }

    func testIssueTrackerStoredInDocument() throws {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        let n1 = IssueTracker.add(&d, title: "Check wall height", description: "Level 1", priority: .high, assignee: "Ana", elements: [w, 999], author: "OR", date: "2026-01-01T00:00:00Z")
        let n2 = IssueTracker.add(&d, title: "Door schedule", author: "OR")
        XCTAssertEqual([n1, n2], [1, 2])
        var i1 = try XCTUnwrap(IssueTracker.issue(d, 1))
        XCTAssertEqual(i1.elements, [w], "missing objects are not linked")
        XCTAssertNotNil(i1.viewCenter)
        XCTAssertTrue(IssueTracker.update(&d, 1) { $0.status = .resolved })
        XCTAssertTrue(IssueTracker.comment(&d, 1, text: "Fixed at 3.1 m", author: "Ana", date: "2026-01-02T00:00:00Z"))
        XCTAssertFalse(IssueTracker.update(&d, 42) { $0.title = "x" })
        i1 = try XCTUnwrap(IssueTracker.issue(d, 1))
        XCTAssertEqual(i1.status, .resolved); XCTAssertEqual(i1.comments.map(\.text), ["Fixed at 3.1 m"])
        XCTAssertEqual(IssueTracker.filter(d, openOnly: true).map(\.id), [2])
        XCTAssertEqual(IssueTracker.filter(d, assignee: "ana").map(\.id), [1])
        // Stored in the .archi file.
        let back = try ArchiFile.decode(ArchiFile.encode(d))
        XCTAssertEqual(IssueTracker.all(back), IssueTracker.all(d))
        XCTAssertTrue(IssueTracker.csv(back).contains("Check wall height"))
        d.remove(ids: [w])
        XCTAssertEqual(IssueTracker.prune(&d), 1)
        XCTAssertTrue(IssueTracker.remove(&d, 2))
        XCTAssertEqual(IssueTracker.all(d).map(\.id), [1])
        XCTAssertEqual(Issue.parseStatus("in progress"), .inProgress); XCTAssertEqual(Issue.parsePriority("crit"), .critical)
    }

    @MainActor func testIssueTrackerCommand() async throws {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        ed.selection = Set(ed.doc.entities.map(\.id))
        await ed.run("ISSUETRACKER Add \"Beam clash\" \"\" High Dan")
        let list = IssueTracker.all(ed.doc)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.title, "Beam clash"); XCTAssertEqual(list.first?.priority, .high); XCTAssertEqual(list.first?.assignee, "Dan")
        XCTAssertEqual(list.first?.elements.count, 1)
        await ed.run("ISSUETRACKER Status 1 Closed")
        XCTAssertEqual(IssueTracker.issue(ed.doc, 1)?.status, .closed)
        ed.undo()
        XCTAssertEqual(IssueTracker.issue(ed.doc, 1)?.status, .open)
    }

    /// ANL-001…010 acceptance: inquiry commands report values matching hand calculations.
    @MainActor func testInquiryCommandsMatchHandCalculations() async throws {
        let ed = Editor()
        var out = await ed.run("DIST 0,0 3000,4000")
        XCTAssertTrue(out.joined().contains("Distance = 5000"), out.joined(separator: "\n"))
        out = await ed.run("AREA 0,0 2000,0 2000,3000 0,3000 ")
        XCTAssertTrue(out.joined().contains("Area = 6.00 m²"), out.joined(separator: "\n"))
        out = await ed.run("ID 12.5,-7")
        XCTAssertTrue(out.joined().contains("X = 12.5"), out.joined(separator: "\n"))
        out = await ed.run("MEASUREGEOM Angle 0,0 1000,0 0,1000")
        XCTAssertTrue(out.joined().contains("Angle = 90°"), out.joined(separator: "\n"))
        await ed.run("LINE 0,0 3000,0 ")
        await ed.run("LINE 0,0 0,4000 ")
        await ed.run("CIRCLE 10000,0 1000")
        let ids = ed.doc.entities.map(\.id)
        out = await ed.run("TLEN #\(ids[0]),#\(ids[1]),#\(ids[2]) ")
        XCTAssertTrue(out.joined().contains("total length = \(fmt(7000 + 2 * Double.pi * 1000, 4))"), out.joined(separator: "\n"))
        out = await ed.run("ANGLEBETWEEN Lines #\(ids[0]) #\(ids[1])")
        XCTAssertTrue(out.joined().contains("Angle = 90°"), out.joined(separator: "\n"))
        out = await ed.run("DISTTOOBJECT 1500,700 #\(ids[0])")
        XCTAssertTrue(out.joined().contains("Shortest distance = 700 at 1500,0"), out.joined(separator: "\n"))
        await ed.run("RECTANG 0,0 1000,1000")
        let r = ed.doc.entities.last!.id
        out = await ed.run("POINTINSIDE 500,500 #\(r)")
        XCTAssertTrue(out.joined().contains("INSIDE"), out.joined(separator: "\n"))
        out = await ed.run("POINTINSIDE 1500,500 #\(r)")
        XCTAssertTrue(out.joined().contains("OUTSIDE"), out.joined(separator: "\n"))
        out = await ed.run("POINTINSIDE 1000,500 #\(r)")
        XCTAssertTrue(out.joined().contains("ON the contour"), out.joined(separator: "\n"))
        out = await ed.run("STATUS")
        XCTAssertTrue(out.joined().contains("4 drawing objects"), out.joined(separator: "\n"))
        ed.selection = []
        out = await ed.run("MASSPROP #\(r) ")
        XCTAssertTrue(out.joined().contains("Area: 1000000"), out.joined(separator: "\n"))
        XCTAssertEqual(CheckCommands.angleBetweenDegrees(Vec2(1, 0), Vec2(-1, 1)), 135, accuracy: 1e-9)
    }
}
