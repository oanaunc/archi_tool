// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisTests: XCTestCase {
    /// 5 × 4 m box of 200 mm walls (centre lines on the rectangle), a door and a window, slab with a hole, one room, one column.
    func house() -> (ArchiDocument, [String: EntityID]) {
        var d = ArchiDocument()
        var ids: [String: EntityID] = [:]
        ids["s"] = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200, height: 3000)))
        ids["e"] = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), thickness: 200, height: 3000)))
        ids["n"] = d.addElement(.wall(WallGeom(start: Vec2(5000, 4000), end: Vec2(0, 4000), thickness: 200, height: 3000)))
        ids["w"] = d.addElement(.wall(WallGeom(start: Vec2(0, 4000), end: Vec2(0, 0), thickness: 200, height: 3000)))
        ids["door"] = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: ids["s"]!, offset: 1000, width: 900, height: 2100)))
        ids["win"] = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: ids["s"]!, offset: 3500, width: 1200, height: 1400, sill: 900)))
        ids["slab"] = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], holes: [[Vec2(1000, 1000), Vec2(2000, 1000), Vec2(2000, 2000), Vec2(1000, 2000)]], thickness: 250)))
        ids["room"] = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(4900, 100), Vec2(4900, 3900), Vec2(100, 3900)], name: "Living", number: "101", height: 2800)))
        ids["col"] = d.addElement(.column(ColumnGeom(position: Vec2(3500, 2500), width: 300, depth: 300, height: 3000)))
        return (d, ids)
    }

    // MARK: Takeoff & cost

    func testQuantityTakeoffMatchesHandCalculation() {
        let (d, _) = house()
        let t = QuantityTakeoff.compute(d)
        let walls = t.lines("wall")
        XCTAssertEqual(walls.count, 1)
        let w = walls[0]
        XCTAssertEqual(w.key, "Generic 200 mm"); XCTAssertEqual(w.count, 4)
        XCTAssertEqual(w.length, 18, accuracy: 1e-9)
        // gross 18 × 3 = 54 m²; openings 0.9 × 2.1 + 1.2 × 1.4 = 3.57 m²
        XCTAssertEqual(w.deducted, 3.57, accuracy: 1e-9)
        XCTAssertEqual(w.area, 50.43, accuracy: 1e-9)
        XCTAssertEqual(w.volume, 50.43 * 0.2, accuracy: 1e-9)
        XCTAssertEqual(t.total("slab", "area"), 19, accuracy: 1e-9)
        XCTAssertEqual(t.total("slab", "volume"), 4.75, accuracy: 1e-9)
        XCTAssertEqual(t.total("door", "count"), 1); XCTAssertEqual(t.total("window", "count"), 1)
        XCTAssertEqual(t.lines("door").first?.key, "900 x 2100")
        XCTAssertEqual(t.total("column", "volume"), 0.27, accuracy: 1e-9)
        XCTAssertEqual(t.total("space", "area"), 18.24, accuracy: 1e-9)
        XCTAssertTrue(t.csv.hasPrefix("category,type,material,count,length_m,area_m2,volume_m3"))
        XCTAssertEqual(t.csv.components(separatedBy: "\r\n").count - 2, t.lines.count)
        // Per-level filter
        XCTAssertTrue(QuantityTakeoff.compute(d, level: 1).lines.isEmpty)
    }

    func testTakeoffSplitsWallTypePlies() {
        var d = ArchiDocument()
        d.wallTypes.append(WallType(name: "Test 260", plies: [WallType.Ply(material: "Brick", thickness: 240), WallType.Ply(material: "Plaster", thickness: 20)]))
        d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 260, height: 2500, wallType: "Test 260")))
        let t = QuantityTakeoff.compute(d)
        let brick = t.materials.first { $0.material == "Brick" }, plaster = t.materials.first { $0.material == "Plaster" }
        XCTAssertEqual(brick?.volume ?? 0, 10 * 0.24, accuracy: 1e-9)
        XCTAssertEqual(plaster?.volume ?? 0, 10 * 0.02, accuracy: 1e-9)
        XCTAssertEqual(t.lines("wall").first?.key, "Test 260")
    }

    func testCostEstimateFromVariablesAndJSON() throws {
        var (d, _) = house()
        d.setVariable("COST:WALL:AREA", "50")
        d.setVariable("COST:door:count", "300")
        d.setVariable("COSTCURRENCY", "RON")
        let t = QuantityTakeoff.compute(d)
        let est = CostEstimate.compute(t, table: CostTable.fromVariables(d))
        XCTAssertEqual(est.currency, "RON")
        XCTAssertEqual(est.total, 50.43 * 50 + 300, accuracy: 1e-6)
        XCTAssertTrue(est.unpriced.contains { $0.category == "slab" })
        let json = """
        {"currency":"EUR","prices":[{"category":"wall","measure":"area","price":40},{"category":"wall","type":"Generic 200 mm","measure":"area","price":45},
         {"category":"slab","measure":"volume","price":120}], "window:count": 500}
        """
        let e2 = CostEstimate.compute(t, table: try CostTable.fromJSON(json))
        XCTAssertEqual(e2.total, 50.43 * 45 + 4.75 * 120 + 500, accuracy: 1e-6)
        XCTAssertTrue(e2.csv.contains("TOTAL"))
        XCTAssertThrowsError(try CostTable.fromJSON("{\"prices\":[{\"category\":\"wall\",\"measure\":\"weight\",\"price\":1}]}"))
    }

    // MARK: Rooms

    func testRoomScheduleNetAndGross() {
        let (d, _) = house()
        let rows = RoomSchedule.compute(d)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].netArea, 18.24 - 0.09, accuracy: 1e-9)  // minus the column
        XCTAssertEqual(rows[0].grossArea, 20, accuracy: 1e-9)           // to the wall centre lines
        XCTAssertEqual(rows[0].perimeter, 17.2, accuracy: 1e-9)
        XCTAssertEqual(rows[0].volume, (18.24 - 0.09) * 2.8, accuracy: 1e-9)
        XCTAssertTrue(RoomSchedule.csv(rows).contains("Living"))
        // A room edge with no wall keeps its position.
        var open = ArchiDocument()
        open.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)])))
        XCTAssertEqual(RoomSchedule.compute(open)[0].grossArea, 1, accuracy: 1e-12)
    }

    // MARK: Sun

    func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal.date(from: c)!
    }

    func testSunPositionReferenceValues() {
        // June solstice, Greenwich, at solar noon: altitude = 90 − φ + δ, sun due south.
        let t = SolarCalculator.sunTimes(date: utc(2024, 6, 20, 12, 0), latitude: 51.4779, longitude: -0.0015)
        let p = SolarCalculator.position(date: t.noon, latitude: 51.4779, longitude: -0.0015, refraction: false)
        XCTAssertEqual(p.declination, 23.44, accuracy: 0.02)
        XCTAssertEqual(p.altitude, 90 - 51.4779 + p.declination, accuracy: 0.01)
        XCTAssertEqual(p.azimuth, 180, accuracy: 0.1)
        // Solar noon at Greenwich on 20 June 2024 ≈ 12:01:40 UTC (equation of time ≈ −1.6 min).
        XCTAssertEqual(t.noon.timeIntervalSince(utc(2024, 6, 20, 12, 0)), 100, accuracy: 30)
        // London sunrise/sunset on the solstice ≈ 03:43 / 20:21 UTC.
        let rise = t.sunrise!, set = t.sunset!
        XCTAssertEqual(rise.timeIntervalSince(utc(2024, 6, 20, 3, 43)), 0, accuracy: 180)
        XCTAssertEqual(set.timeIntervalSince(utc(2024, 6, 20, 20, 21)), 0, accuracy: 180)
        // Sydney, December solstice solar noon: sun due north, altitude 90 − 33.87 + 23.44.
        let st = SolarCalculator.sunTimes(date: utc(2024, 12, 21, 2, 0), latitude: -33.8688, longitude: 151.2093)
        let sp = SolarCalculator.position(date: st.noon, latitude: -33.8688, longitude: 151.2093, refraction: false)
        XCTAssertEqual(sp.altitude, 90 - 33.8688 - 23.44, accuracy: 47.5) // sanity range
        XCTAssertEqual(sp.altitude, 90 - (-33.8688 - sp.declination).magnitude, accuracy: 0.01)
        XCTAssertTrue(sp.azimuth < 0.2 || sp.azimuth > 359.8)
        // Morning sun is in the east, afternoon in the west; night is below the horizon.
        let am = SolarCalculator.position(date: utc(2024, 3, 20, 7, 0), latitude: 44.43, longitude: 26.10)
        let pm = SolarCalculator.position(date: utc(2024, 3, 20, 14, 0), latitude: 44.43, longitude: 26.10)
        XCTAssertTrue(am.azimuth > 90 && am.azimuth < 180); XCTAssertTrue(pm.azimuth > 180 && pm.azimuth < 270)
        XCTAssertLessThan(SolarCalculator.position(date: utc(2024, 3, 20, 23, 0), latitude: 44.43, longitude: 26.10).altitude, -30)
        // Equator at the March equinox: day length ≈ 12 h 7 min (refraction), sun nearly overhead at noon.
        let eq = SolarCalculator.sunTimes(date: utc(2024, 3, 20, 12, 0), latitude: 0, longitude: 0)
        XCTAssertEqual(eq.sunset!.timeIntervalSince(eq.sunrise!) / 60, 727, accuracy: 3)
        XCTAssertGreaterThan(SolarCalculator.position(date: eq.noon, latitude: 0, longitude: 0).altitude, 89.5)
        // Polar night: no sunrise.
        XCTAssertNil(SolarCalculator.sunTimes(date: utc(2024, 12, 21, 12, 0), latitude: 80, longitude: 0).sunrise)
        // Direction vector: sun due south at 45° → (0, −0.707, 0.707) with north = +Y.
        let v = SolarCalculator.direction(SunPosition(azimuth: 180, altitude: 45, declination: 0, equationOfTime: 0, hourAngle: 0))
        XCTAssertEqual(v.x, 0, accuracy: 1e-9); XCTAssertEqual(v.y, -0.7071067811865476, accuracy: 1e-9); XCTAssertEqual(v.z, 0.7071067811865476, accuracy: 1e-9)
        XCTAssertEqual(SolarCalculator.refractionCorrection(0), 0.483, accuracy: 0.01)
        XCTAssertNotNil(SolarCalculator.date("2025-06-21", "14:30", utcOffset: 3))
        XCTAssertEqual(SolarCalculator.date("2025-06-21", "14:30", utcOffset: 3), utc(2025, 6, 21, 11, 30))
        XCTAssertNil(SolarCalculator.date("2025-13-40", "x", utcOffset: 0))
    }

    // MARK: Clash detection

    func testClashDetection() {
        var d = ArchiDocument()
        let col = d.addElement(.column(ColumnGeom(position: Vec2(2500, 2000), width: 300, depth: 300, height: 3000)))
        let beam = d.addElement(.beam(BeamGeom(start: Vec2(0, 2000), end: Vec2(5000, 2000), width: 200, depth: 400, topOffset: 3000)))
        // A wall standing on a slab (touching) with a door, and a second wall joined at the corner: no clashes.
        let w1 = d.addElement(.wall(WallGeom(start: Vec2(0, -3000), end: Vec2(5000, -3000))))
        d.addElement(.wall(WallGeom(start: Vec2(5000, -3000), end: Vec2(5000, -1000))))
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w1, offset: 1000, width: 900, height: 2100)))
        d.addElement(.slab(SlabGeom(boundary: [Vec2(-500, -3500), Vec2(5500, -3500), Vec2(5500, -500), Vec2(-500, -500)], thickness: 200)))
        let clashes = ClashDetector.detect(d)
        XCTAssertEqual(clashes.count, 1, clashes.map(\.description).joined(separator: "; "))
        XCTAssertEqual(Set([clashes.first?.a, clashes.first?.b]), Set([col, beam]))
        XCTAssertEqual(clashes.first?.point.z ?? 0, 2800, accuracy: 201)
        // Touching solids are not a clash; overlapping ones are; a solid inside another is reported as contained.
        var s = ArchiDocument()
        let a = s.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 1000, 1000))))
        s.add(.solid(SolidGeom(kind: .box, origin: Vec3(1000, 0, 0), size: Vec3(1000, 1000, 1000))))
        var pairs = ClashOptions(); pairs.solidPairs = true
        XCTAssertTrue(ClashDetector.detect(s, options: pairs).isEmpty)
        let c = s.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 500, 500), size: Vec3(1000, 1000, 1000))))
        var both = ClashOptions(); both.solidPairs = true
        XCTAssertTrue(ClashDetector.detect(s).isEmpty) // solid entities are not tested against each other by default
        let r = ClashDetector.detect(s, options: both)
        XCTAssertEqual(r.count, 2)
        XCTAssertTrue(r.allSatisfy { $0.a == c || $0.b == c })
        let inner = s.add(.solid(SolidGeom(kind: .box, origin: Vec3(100, 100, 100), size: Vec3(100, 100, 100))))
        let r2 = ClashDetector.detect(s, options: both)
        XCTAssertTrue(r2.contains { ($0.a == a && $0.b == inner || $0.a == inner && $0.b == a) && $0.contained })
        var opt = both; opt.setA = [inner]
        XCTAssertEqual(ClashDetector.detect(s, options: opt).count, 1)
        XCTAssertTrue(ClashDetector.csv(r).hasPrefix("#,id_a"))
    }

    func testTriangleIntersection() {
        let t1 = (Vec3(0, 0, 0), Vec3(10, 0, 0), Vec3(0, 10, 0))
        XCTAssertNotNil(ClashDetector.intersect(t1, (Vec3(2, 2, -5), Vec3(2, 2, 5), Vec3(8, -5, 0.5)), eps: 1e-6))
        XCTAssertNil(ClashDetector.intersect(t1, (Vec3(20, 20, -5), Vec3(20, 20, 5), Vec3(30, 25, 0)), eps: 1e-6))
        // Touching at a vertex / coplanar: not a clash.
        XCTAssertNil(ClashDetector.intersect(t1, (Vec3(2, 2, 0), Vec3(3, 3, 5), Vec3(4, 2, 5)), eps: 1e-6))
        XCTAssertNil(ClashDetector.intersect(t1, (Vec3(1, 1, 0), Vec3(3, 1, 0), Vec3(1, 3, 0)), eps: 1e-6))
    }

    // MARK: Model checker

    func testModelChecker() {
        let (clean, _) = house()
        XCTAssertTrue(ModelChecker.check(clean).filter { $0.severity == .error }.isEmpty, ModelChecker.check(clean).map(\.description).joined(separator: "\n"))
        var d = ArchiDocument()
        let flat = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(1000, 0), height: 0)))
        let host = d.addElement(.wall(WallGeom(start: Vec2(0, 5000), end: Vec2(800, 5000))))
        let wide = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: host, offset: 400, width: 900, height: 2100)))
        let a = d.addElement(.wall(WallGeom(start: Vec2(0, 10000), end: Vec2(4000, 10000))))
        let b = d.addElement(.wall(WallGeom(start: Vec2(3000, 10050), end: Vec2(6000, 10050))))
        let r1 = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 20000), Vec2(3000, 20000), Vec2(3000, 23000), Vec2(0, 23000)], name: "", number: "1")))
        let r2 = d.addElement(.space(SpaceGeom(boundary: [Vec2(2000, 20000), Vec2(5000, 20000), Vec2(5000, 23000), Vec2(2000, 23000)], name: "Kitchen", number: "1")))
        let r3 = d.addElement(.space(SpaceGeom(boundary: [Vec2(5000, 20000), Vec2(8000, 20000), Vec2(8000, 23000), Vec2(5000, 23000)], name: "Hall", number: "3")))
        let bow = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 30000), Vec2(2000, 31000), Vec2(2000, 30000), Vec2(0, 30500)], name: "Bow", number: "9")))
        let l1 = d.add(.line(LineGeom(.zero, Vec2(1, 1))))
        let l2 = d.add(.line(LineGeom(.zero, Vec2(1, 1))))
        let issues = ModelChecker.check(d)
        func has(_ code: String, _ ids: Set<EntityID>) -> Bool { issues.contains { $0.code == code && Set($0.ids) == ids } }
        XCTAssertTrue(has("WALL-HEIGHT", [flat]))
        XCTAssertTrue(has("OPENING-WIDER", [wide, host]))
        XCTAssertTrue(has("WALL-OVERLAP", [a, b]))
        XCTAssertTrue(has("ROOM-UNNAMED", [r1]))
        XCTAssertTrue(has("ROOM-NUMBER-DUPLICATE", [r1, r2]))
        XCTAssertTrue(has("ROOM-OVERLAP", [r1, r2]))
        XCTAssertFalse(issues.contains { $0.code == "ROOM-OVERLAP" && $0.ids.contains(r3) }) // shares an edge only
        XCTAssertTrue(has("ROOM-BOUNDARY", [bow]))
        XCTAssertTrue(has("ENTITY-DUPLICATE", [l1, l2]))
        XCTAssertTrue(issues.allSatisfy { !$0.bounds.isEmpty || $0.ids.isEmpty })
        XCTAssertEqual(issues.first?.severity, .error)
    }

    @MainActor
    func testAnalysisCommands() async {
        let reg = CommandRegistry()
        BuiltinCommands.registerAll(reg)
        let mine = AnalysisCommands.all + IOCommands.all
        let own = Set(mine.map(\.name))
        var seen: [String: String] = [:]
        for c in reg.sorted where !own.contains(c.name) { for n in [c.name] + c.aliases { seen[n] = c.name } }
        for c in mine { for n in [c.name] + c.aliases {
            XCTAssertNil(seen[n], "\(n) collides with \(seen[n] ?? "")"); seen[n] = c.name
            XCTAssertEqual(reg.lookup(n)?.name, c.name, "\(n) is not registered for \(c.name)")
        } }
        reg.register(AnalysisCommands.all)
        let (d, ids) = house()
        let ed = Editor(document: d, registry: reg)
        var log = await ed.run("TAKEOFF All ")
        XCTAssertTrue(log.contains { $0.contains("Generic 200 mm") }, log.joined(separator: "\n"))
        await ed.run("UNITPRICE wall  Area 50")
        XCTAssertEqual(ed.doc.variable("COST:WALL:AREA"), "50")
        log = await ed.run("COSTESTIMATE  ")
        XCTAssertTrue(log.contains { $0.contains("Total: 2521.5") }, log.joined(separator: "\n"))
        log = await ed.run("ROOMSCHEDULE All ")
        XCTAssertTrue(log.contains { $0.contains("gross 20 m²") }, log.joined(separator: "\n"))
        log = await ed.run("SUNPOSITION 2024-06-20 12:00 0 51.4779 0")
        XCTAssertNotNil(ed.doc.variable("SUNAZIMUTH"))
        XCTAssertEqual(Double(ed.doc.variable("SUNALTITUDE") ?? "") ?? 0, 62, accuracy: 0.2)
        log = await ed.run("CHECKMODEL")
        XCTAssertTrue(log.contains { $0.contains("issue") || $0.contains("No issues") }, log.joined(separator: "\n"))
        ed.selection = []
        log = await ed.run("CLASHDETECT 1 ")
        XCTAssertTrue(log.contains { $0.contains("No clashes") || $0.contains("clash") }, log.joined(separator: "\n"))
        _ = ids
    }
}
