// Oanarina Archi Tool — GPL-3.0-or-later
// Takeoff by phase and level, bill of quantities, energy balance, egress distances and accessibility checks.
import XCTest
@testable import ArchiCore

final class AnalysisPerformanceTests: XCTestCase {
    func box(_ d: inout ArchiDocument, _ w: Double, _ h: Double, origin: Vec2 = .zero, level: Int = 0) -> [EntityID] {
        let pts = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)].map { $0 + origin }
        return (0..<4).map { d.addElement(.wall(WallGeom(start: pts[$0], end: pts[($0 + 1) % 4], thickness: 200)), level: level, material: "Brick") }
    }

    func testTakeoffByPhaseAndLevel() throws {
        var d = ArchiDocument()
        d.phases = ["Existing", "New Construction"]
        let a = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 200, height: 3000)), material: "Brick")
        let b = d.addElement(.wall(WallGeom(start: Vec2(0, 5000), end: Vec2(6000, 5000), thickness: 200, height: 3000)), material: "Brick")
        let c = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200, height: 3000)), level: 1, material: "Brick")
        let door = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: b, offset: 3000, width: 1000, height: 2000)))
        d.elements[d.elementIndex(a)!].props = ["phaseCreated": "Existing", "phaseDemolished": "New Construction"]
        d.elements[d.elementIndex(b)!].props = ["phaseCreated": "New Construction"]
        d.elements[d.elementIndex(door)!].props = ["phaseCreated": "New Construction"]
        _ = c
        let t = PhaseLevelTakeoff.compute(d)
        XCTAssertEqual(t.groups.map { "\($0.phase)/\($0.work)/\($0.level)" }, ["Existing/new/0", "New Construction/demolished/0", "New Construction/new/0", "New Construction/new/1"])
        XCTAssertEqual(t.total("wall", "length", phase: "Existing", work: "new"), 4, accuracy: 1e-9)
        XCTAssertEqual(t.total("wall", "length", phase: "New Construction", work: "demolished"), 4, accuracy: 1e-9)
        XCTAssertEqual(t.total("wall", "length", phase: "New Construction", work: "new"), 11, accuracy: 1e-9)
        XCTAssertEqual(t.total("wall", "area", phase: "New Construction", work: "new", level: 0), 6 * 3 - 2, accuracy: 1e-9, "door deducted")
        XCTAssertEqual(t.total("door", "count", phase: "New Construction", work: "new"), 1)
        XCTAssertEqual(t.total("door", "count", phase: "Existing"), 0)
        XCTAssertEqual(t.table.count, 1 + t.groups.reduce(0) { $0 + $1.lines.count })
    }

    func testBillOfQuantities() throws {
        var d = ArchiDocument()
        let w = box(&d, 5000, 4000)
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[0], offset: 2500, width: 1000, height: 2100)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[2], offset: 2500, width: 1000, height: 2100)))
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], thickness: 200)), material: "Concrete")
        let t = QuantityTakeoff.compute(d)
        let table = try CostTable.fromJSON("{\"currency\":\"EUR\",\"wall:area\":50,\"door:count\":300,\"slab:volume\":120}")
        var o = BoQOptions(); o.vat = 19; o.contingency = 5
        let b = BillOfQuantities.build(t, table: table, options: o)
        XCTAssertEqual(b.sections.map(\.title), ["Substructure and concrete", "Walls", "Doors"])
        XCTAssertEqual(b.sections.map(\.number), [1, 2, 3])
        XCTAssertEqual(b.sections[1].items.first?.ref, "2.1")
        let wallArea = t.total("wall", "area"), slabVol = t.total("slab", "volume")
        XCTAssertEqual(slabVol, 4, accuracy: 1e-9)
        let net = ((wallArea * 50) * 100).rounded() / 100 + 600 + 480
        XCTAssertEqual(b.net, net, accuracy: 0.05)
        XCTAssertEqual(b.contingency, (b.net * 5).rounded() / 100, accuracy: 1e-9)
        XCTAssertEqual(b.total, b.net + b.contingency + b.vat, accuracy: 1e-9)
        XCTAssertEqual(b.vat, ((b.net + b.contingency) * 19).rounded() / 100, accuracy: 0.011)
        XCTAssertTrue(b.csv.contains("GRAND TOTAL"))
        XCTAssertEqual(try XLSX.read(b.xlsx).first?.rows.last?[1], "GRAND TOTAL")
        XCTAssertEqual(BillOfQuantities.money(12345.6, currency: "EUR"), "€ 12,345.60")
        XCTAssertEqual(BillOfQuantities.money(12345.6, currency: "RON"), "12.345,60 lei")
        XCTAssertEqual(BillOfQuantities.money(-3, currency: "USD"), "$ -3.00")
        XCTAssertEqual(BillOfQuantities.money(1234567, currency: "CHF"), "1,234,567.00 CHF")
        XCTAssertFalse(b.unpriced.contains { $0.category == "wall" })
    }

    func testClimateAndUtilisation() {
        let c45 = ClimateData.fromLatitude(45)
        XCTAssertEqual(c45.degreeDays, 2900); XCTAssertEqual(c45.heatingDays, 200)
        let c = ClimateData.fromLatitude(-47.5)
        XCTAssertEqual(c.degreeDays, 3150, accuracy: 1e-9); XCTAssertEqual(c.heatingDays, 210, accuracy: 1e-9)
        XCTAssertEqual(ClimateData.fromLatitude(5).degreeDays, 0)
        let months = c45.seasonMonths(latitude: 45)
        XCTAssertEqual(months.map(\.month), [1, 2, 3, 4, 10, 11, 12])
        XCTAssertEqual(months.reduce(0) { $0 + $1.days }, 200, accuracy: 1e-9)
        XCTAssertEqual(c45.seasonMonths(latitude: -45).first { $0.month == 7 }?.days, 31)
        XCTAssertEqual(EnergyBalance.utilisation(gamma: 1, timeConstant: 15), 2.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(EnergyBalance.utilisation(gamma: 0.5, timeConstant: 0), 0.5 / 0.75, accuracy: 1e-12)
        XCTAssertEqual(EnergyBalance.compass(180), "S"); XCTAssertEqual(EnergyBalance.compass(350), "N"); XCTAssertEqual(EnergyBalance.compass(100), "E")
    }

    func testEnergyBalanceWithSolarGainsPerOrientation() throws {
        var d = ArchiDocument()
        d.info.latitude = 45; d.info.longitude = 0
        let w = box(&d, 10000, 8000)
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w[0], offset: 5000, width: 3000, height: 1500, sill: 900)))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w[2], offset: 5000, width: 3000, height: 1500, sill: 900)))
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)], thickness: 250)), material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(9900, 100), Vec2(9900, 7900), Vec2(100, 7900)], name: "Hall", height: 2800)))
        let o = EnergyBalanceOptions()
        let eb = EnergyBalance.compute(d, options: o)
        var ho = HeatLossOptions(); ho.degreeDays = 2900
        let hl = HeatLoss.compute(d, options: ho)
        XCTAssertEqual(eb.losses, (hl.transmission + hl.ventilation) * 2900 * 24 / 1000, accuracy: 1e-6)
        let south = try XCTUnwrap(eb.solarRows.first { $0.orientation == "S" })
        let north = try XCTUnwrap(eb.solarRows.first { $0.orientation == "N" })
        XCTAssertEqual(south.area, 4.5, accuracy: 1e-9)
        XCTAssertGreaterThan(south.irradiation, 2 * north.irradiation)
        XCTAssertEqual(south.gain, south.irradiation * 4.5 * 0.6 * 0.7 * 0.9, accuracy: 1e-6)
        XCTAssertEqual(eb.internalGains, 4 * hl.floorArea * 200 * 24 / 1000, accuracy: 1e-6)
        XCTAssertGreaterThan(eb.utilisation, 0); XCTAssertLessThanOrEqual(eb.utilisation, 1)
        XCTAssertEqual(eb.heatingNeed, eb.losses - eb.utilisation * eb.gains, accuracy: 1e-6)
        XCTAssertEqual(eb.specificNeed, eb.heatingNeed / hl.floorArea, accuracy: 1e-9)
        // A project HDD overrides the latitude table.
        d.setVariable("HDD", "1000")
        XCTAssertEqual(EnergyBalance.compute(d).climate.degreeDays, 1000)
        XCTAssertTrue(eb.report.contains("Solar S"))
    }

    func testEgressDistances() throws {
        var d = ArchiDocument()
        let w = box(&d, 20000, 5000)
        let part = d.addElement(.wall(WallGeom(start: Vec2(10000, 0), end: Vec2(10000, 5000), thickness: 200)))
        let exit = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[3], offset: 2500, width: 1000, height: 2100)))   // west wall
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: part, offset: 2500, width: 1000, height: 2100)))
        let a = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(9900, 100), Vec2(9900, 4900), Vec2(100, 4900)], name: "Near", number: "1")))
        let b = d.addElement(.space(SpaceGeom(boundary: [Vec2(10100, 100), Vec2(19900, 100), Vec2(19900, 4900), Vec2(10100, 4900)], name: "Far", number: "2")))
        // A closed room with no door.
        _ = box(&d, 3000, 3000, origin: Vec2(30000, 0))
        let c = d.addElement(.space(SpaceGeom(boundary: [Vec2(30100, 100), Vec2(32900, 100), Vec2(32900, 2900), Vec2(30100, 2900)], name: "Closed", number: "3")))
        XCTAssertEqual(EgressAnalysis.exits(d, level: 0), [exit])
        var o = EgressOptions(); o.maxDistance = 15
        let r = EgressAnalysis.compute(d, level: 0, options: o)
        let near = try XCTUnwrap(r.rows.first { $0.id == a }), far = try XCTUnwrap(r.rows.first { $0.id == b }), closed = try XCTUnwrap(r.rows.first { $0.id == c })
        // Farthest corner of "Far": ≈ 19.9 m along the building from the west door (octile grid ≤ 8 % longer).
        XCTAssertGreaterThan(far.distance!, 19.0); XCTAssertLessThan(far.distance!, 21.6)
        XCTAssertGreaterThan(near.distance!, 9.0); XCTAssertLessThan(near.distance!, 11.2)
        XCTAssertTrue(near.ok); XCTAssertFalse(far.ok)
        XCTAssertNil(closed.distance); XCTAssertFalse(closed.ok)
        XCTAssertGreaterThan(far.path.first!.x, 19000, "route starts at the far end")
        XCTAssertLessThan(far.path.last!.x, 300, "and ends at the exit door")
        XCTAssertEqual(r.failures.count, 2)
        o.maxDistance = 25
        XCTAssertTrue(EgressAnalysis.compute(d, level: 0, options: o).rows.first { $0.id == b }!.ok)
        XCTAssertEqual(r.table.count, 4)
    }

    func testAccessibilityDoorsAndTurningCircles() throws {
        var d = ArchiDocument()
        let w = box(&d, 6000, 3000)
        let narrow = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[0], offset: 1000, width: 800, height: 2100, frameWidth: 50)))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[0], offset: 3000, width: 1000, height: 2100, frameWidth: 50)))
        let dbl = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[2], offset: 3000, width: 1500, height: 2100, doorStyle: .double, frameWidth: 50)))
        let bath = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(2100, 100), Vec2(2100, 2500), Vec2(100, 2500)], name: "Bathroom")))
        let wc = d.addElement(.space(SpaceGeom(boundary: [Vec2(3000, 100), Vec2(6000, 100), Vec2(6000, 2900), Vec2(3000, 2900)], name: "WC")))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(2200, 100), Vec2(2900, 100), Vec2(2900, 2900), Vec2(2200, 2900)], name: "Store")))
        // Fixtures fill the lower 1.6 m of the WC: 3.0 × 1.2 m free.
        _ = d.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(4500, 900), size: Vec3(3000, 1600, 800))))
        let res = Accessibility.check(d)
        XCTAssertEqual(Set(res.issues.filter { $0.code == "A11Y-DOOR-WIDTH" }.flatMap(\.ids)), [narrow, dbl], "700 mm clear and a 700 mm leaf fail; 900 mm passes")
        let b = try XCTUnwrap(res.turning.first { $0.id == bath })
        XCTAssertEqual(b.diameter, 2000, accuracy: 60); XCTAssertTrue(b.ok)
        let t = try XCTUnwrap(res.turning.first { $0.id == wc })
        XCTAssertEqual(t.diameter, 1200, accuracy: 60); XCTAssertFalse(t.ok)
        XCTAssertGreaterThan(t.center.y, 1700)
        XCTAssertEqual(res.turning.count, 2, "only bathrooms are checked")
        XCTAssertTrue(res.issues.contains { $0.code == "A11Y-TURNING" && $0.ids == [wc] })
        var o = AccessibilityOptions(); o.minDoorClear = 650; o.turningDiameter = 1100
        let relaxed = Accessibility.check(d, options: o)
        XCTAssertTrue(relaxed.issues.isEmpty, relaxed.issues.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(Accessibility.isBathroom("Grup sanitar", options: o))
    }

    @MainActor
    func testPerformanceCommandsHeadless() async throws {
        var d = ArchiDocument()
        let w = box(&d, 8000, 5000)
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w[3], offset: 2500, width: 1000, height: 2100)))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w[0], offset: 4000, width: 2000, height: 1500, sill: 900)))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(7900, 100), Vec2(7900, 4900), Vec2(100, 4900)], name: "Bath", number: "1")))
        d.setVariable("COST:wall:area", "50")
        let ed = Editor(document: d)
        var log = await ed.run("EGRESS 30 Y ")
        XCTAssertTrue(log.contains { $0.contains("1 Bath:") && $0.contains("OK") }, log.joined(separator: "\n"))
        XCTAssertTrue(ed.doc.entities.contains { $0.layer == "EGRESS-ROUTES" })
        ed.undo()
        XCTAssertFalse(ed.doc.entities.contains { $0.layer == "EGRESS-ROUTES" }, "one undo step")
        log = await ed.run("ACCESSIBILITY All ")
        XCTAssertTrue(log.contains { $0.contains("Bath: free turning circle") }, log.joined(separator: "\n"))
        log = await ed.run("ENERGYBALANCE  ")
        XCTAssertTrue(log.contains { $0.hasPrefix("Heating need:") }, log.joined(separator: "\n"))
        log = await ed.run("BOQ  19 ")
        XCTAssertTrue(log.contains { $0.hasPrefix("Grand total:") }, log.joined(separator: "\n"))
        log = await ed.run("TAKEOFFPHASE ")
        XCTAssertTrue(log.contains { $0.contains("— new —") }, log.joined(separator: "\n"))
    }
}
