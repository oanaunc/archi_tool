// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class AnalysisBuildingTests: XCTestCase {
    func box(_ w: Double = 10000, _ d: Double = 10000, thickness: Double = 300) -> (ArchiDocument, [EntityID]) {
        var doc = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(w, 0), Vec2(w, d), Vec2(0, d)]
        var ids: [EntityID] = []
        for i in 0..<4 { ids.append(doc.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: thickness, height: 3000)), material: "Concrete")) }
        return (doc, ids)
    }

    func testUValueOfLayeredWallMatchesHandCalculation() throws {
        var d = ArchiDocument()
        if !d.wallTypes.contains(where: { $0.name == "Exterior Brick 365" }) { d.wallTypes.append(WallType.library[1]) }
        let id = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 365, wallType: "Exterior Brick 365")))
        let cu = try XCTUnwrap(Thermal.uValue(d.element(id)!, doc: d))
        let r = 0.13 + 0.04 + 0.015 / 0.57 + 0.24 / 0.77 + 0.1 / 0.035 + 0.01 / 0.57
        XCTAssertEqual(cu.u, 1 / r, accuracy: 1 / r * 0.01)
        XCTAssertEqual(cu.layers.count, 4)
        XCTAssertTrue(cu.assumed.isEmpty)
        // Overrides: material λ and type U-value.
        d.setVariable("LAMBDA:Insulation", "0.022")
        let r2 = r - 0.1 / 0.035 + 0.1 / 0.022
        XCTAssertEqual(Thermal.uValue(d.element(id)!, doc: d)!.u, 1 / r2, accuracy: 1e-9)
        d.setVariable("UVALUE:Exterior Brick 365", "0.2")
        XCTAssertEqual(Thermal.uValue(d.element(id)!, doc: d)!.u, 0.2)
        XCTAssertEqual(ThermalLibrary.uValue([ThermalLibrary.Layer(material: "x", thickness: 0.2, lambda: 2.0)], component: "floor"), 1 / (0.21 + 0.1), accuracy: 1e-12)
    }

    func testHeatLossOfSimpleBox() throws {
        var (d, walls) = box()
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 5000, width: 1000, height: 1000, sill: 900)))
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 10000), Vec2(0, 10000)], thickness: 200)), material: "Concrete")
        var o = HeatLossOptions(); o.thermalBridge = 0; o.indoor = 20; o.outdoor = -10; o.airChanges = 0.5
        let r = HeatLoss.compute(d, options: o)
        XCTAssertTrue(walls.allSatisfy { Thermal.isExterior(d.element($0)!, doc: d) })
        XCTAssertEqual(r.total("wall"), 119 * (1 / (0.17 + 0.3 / 2.0)), accuracy: 1e-6)
        XCTAssertEqual(r.total("window"), 1.3, accuracy: 1e-9)
        XCTAssertEqual(r.total("floor"), 100 * (1 / (0.21 + 0.2 / 2.0)) * 0.5, accuracy: 1e-6)
        let h = (d.level(0)?.height ?? 3000) / 1000
        XCTAssertEqual(r.ventilation, 0.34 * 0.5 * 100 * h, accuracy: 1e-6)
        XCTAssertEqual(r.designLoad, (r.transmission + r.ventilation) * 30, accuracy: 1e-6)
        XCTAssertEqual(r.floorArea, 100, accuracy: 1e-9)
        // An interior partition (rooms on both sides) is not part of the envelope.
        let mid = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 10000), thickness: 100)))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(4950, 150), Vec2(4950, 9850), Vec2(150, 9850)], name: "A")))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(5050, 150), Vec2(9850, 150), Vec2(9850, 9850), Vec2(5050, 9850)], name: "B")))
        XCTAssertFalse(Thermal.isExterior(d.element(mid)!, doc: d))
        XCTAssertTrue(Thermal.isExterior(d.element(walls[1])!, doc: d))
    }

    func testDaylightFactorAndWindowRatio() throws {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 200)))
        let win = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2500, width: 1500, height: 1200, sill: 900, frameWidth: 50)))
        let room = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 100), Vec2(5000, 100), Vec2(5000, 4100), Vec2(0, 4100)], name: "Office", number: "1", height: 2700)))
        let rows = Daylight.compute(d)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, room); XCTAssertEqual(rows[0].windows, [win])
        XCTAssertEqual(rows[0].glazedArea, 1.4 * 1.1, accuracy: 1e-9)
        let gain: Double = 0.7 * 1.54 * 65 * 0.9
        let span: Double = 2.0 * 20.0 + 18.0 * 2.7
        let expected: Double = gain / (span * 0.75)
        XCTAssertEqual(rows[0].daylightFactor, expected, accuracy: 1e-9)
        XCTAssertEqual(rows[0].windowToFloor, 1.54 / 20, accuracy: 1e-9)
        XCTAssertEqual(rows[0].rating, "poor")
    }

    func testSunPathDiagram() throws {
        var o = SunPathOptions()
        o.latitude = 44.43; o.longitude = 26.10; o.utcOffset = 3; o.radius = 1000
        let ents = SunPathDiagram.entities(day: "2025-06-21", options: o)
        let path = try XCTUnwrap(ents.first { $0.props["sunpath"] == "path" })
        guard case .polyline(let pl) = path.geometry else { return XCTFail() }
        XCTAssertGreaterThan(pl.vertices.count, 100)
        XCTAssertTrue(pl.vertices.allSatisfy { $0.p.length <= 1000 + 1e-6 })
        let hours = ents.filter { $0.props["sunpath"] == "hour" }
        XCTAssertGreaterThanOrEqual(hours.count, 14)
        let maxAlt = hours.compactMap { $0.props["altitude"].flatMap(Double.init) }.max() ?? 0
        XCTAssertEqual(maxAlt, 90 - 44.43 + 23.44, accuracy: 2.5)
        XCTAssertEqual(ents.filter { $0.props["sunpath"] == "reference" }.count, 2)
        // South at the bottom, east to the right with north up.
        let s = SunPathDiagram.point(azimuth: 180, altitude: 0, options: o), e = SunPathDiagram.point(azimuth: 90, altitude: 45, options: o)
        XCTAssertEqual(s.y, -1000, accuracy: 1e-9); XCTAssertEqual(e.x, 500, accuracy: 1e-9); XCTAssertEqual(e.y, 0, accuracy: 1e-9)
    }

    func testAreaScheduleByLevel() {
        var d = ArchiDocument()
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)], holes: [[Vec2(1000, 1000), Vec2(2000, 1000), Vec2(2000, 2000), Vec2(1000, 2000)]])))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 8000), Vec2(0, 8000)], name: "A")))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 5000), Vec2(0, 5000)], name: "B")), level: 1)
        let rows = AreaSchedule.compute(d)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].grossArea, 79, accuracy: 1e-9); XCTAssertEqual(rows[0].grossSource, "slabs")
        XCTAssertEqual(rows[0].netArea, 40, accuracy: 1e-9)
        XCTAssertEqual(rows[1].grossArea, 20, accuracy: 1e-9); XCTAssertEqual(rows[1].grossSource, "rooms")
        XCTAssertEqual(AreaSchedule.table(rows).last?[2], "99")
    }

    func testCodeCheckRules() throws {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0))))
        let door = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 800, height: 2100, frameWidth: 50)))
        let bed = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 100), Vec2(2500, 100), Vec2(2500, 2600), Vec2(0, 2600)], name: "Bedroom 1", height: 2700)))
        let stair = d.addElement(.stair(StairGeom(start: Vec2(8000, 0), totalRise: 3000, riserCount: 15, treadDepth: 250)))
        let ramp = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 5000), Vec2(4000, 5000), Vec2(4000, 6200), Vec2(0, 6200)], slope: atan(0.1) * 180 / .pi)))
        d.elements[d.elementIndex(ramp)!].props["kind"] = "ramp"
        let issues = CodeCheck.check(d)
        func has(_ code: String, _ id: EntityID) -> Bool { issues.contains { $0.code == code && $0.ids.contains(id) } }
        XCTAssertTrue(has("CODE-ROOM-AREA", bed))
        XCTAssertTrue(has("CODE-DAYLIGHT", bed))
        XCTAssertTrue(has("CODE-STAIR-RISER", stair))
        XCTAssertFalse(has("CODE-STAIR-FORMULA", stair))   // 2·200 + 250 = 650 mm is inside 590–660 mm
        XCTAssertTrue(has("CODE-RAMP-GRADIENT", ramp))
        XCTAssertTrue(has("CODE-DOOR-WIDTH", door))
        XCTAssertFalse(issues.contains { $0.bounds.isEmpty })
        // Custom JSON rules: only what is listed is checked.
        let rules = try CodeRules.fromJSON("{\"name\":\"Strict\",\"minRoomArea\":10,\"stair\":{\"maxRiser\":175,\"minTread\":260}}")
        let j = CodeCheck.check(d, rules: rules)
        XCTAssertEqual(Set(j.map(\.code)), ["CODE-ROOM-AREA", "CODE-STAIR-RISER", "CODE-STAIR-TREAD"])
        XCTAssertThrowsError(try CodeRules.fromJSON("{\"minRoomArea\":\"big\"}"))
        // Rules stored in the drawing round-trip through JSON.
        d.setVariable("CODERULES", rules.json)
        XCTAssertEqual(CodeRules.from(d), rules)
        XCTAssertEqual(CodeCheck.minWidth([Vec2(0, 0), Vec2(4, 0), Vec2(4, 2), Vec2(0, 2)]), 2, accuracy: 1e-12)
    }

    func testFrameSolverCantileverAndEquilibrium() throws {
        var d = ArchiDocument()
        _ = d.addElement(.column(ColumnGeom(position: .zero, width: 300, depth: 300, height: 3000)), material: "Concrete")
        var o = AnalyticalOptions(); o.includeSelfWeight = false; o.deadLoad = 0; o.liveLoad = 0
        var m = StructuralAnalysis.model(d, options: o)
        XCTAssertEqual(m.nodes.count, 2); XCTAssertEqual(m.members.count, 1)
        XCTAssertTrue(m.nodes[0].isSupported); XCTAssertFalse(m.nodes[1].isSupported)
        m.nodeLoads = [NodeLoad(node: 2, force: Vec3(10, 0, 0), moment: .zero)]
        let r = try StructuralAnalysis.solve(m)
        let I = 0.3 * 0.3 * 0.3 * 0.3 / 12, E = 30_000_000.0
        XCTAssertEqual(r.displacements[2]!.u.x, 10 * 27 / (3 * E * I), accuracy: 1e-9)
        XCTAssertEqual(r.reactions[1]!.f.x, -10, accuracy: 1e-6)
        XCTAssertEqual(abs(r.reactions[1]!.m.y), 30, accuracy: 1e-6)
        // Axial: δ = PL/EA.
        m.nodeLoads = [NodeLoad(node: 2, force: Vec3(0, 0, -100), moment: .zero)]
        XCTAssertEqual(try StructuralAnalysis.solve(m).displacements[2]!.u.z, -100 * 3 / (E * 0.09), accuracy: 1e-12)
        // Portal frame with self weight and a slab: vertical reactions balance all loads.
        var p = ArchiDocument()
        _ = p.addElement(.column(ColumnGeom(position: Vec2(0, 0), height: 3000)), material: "Concrete")
        _ = p.addElement(.column(ColumnGeom(position: Vec2(6000, 0), height: 3000)), material: "Concrete")
        _ = p.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(6000, 0), width: 300, depth: 500, topOffset: 3000)), material: "Concrete")
        _ = p.addElement(.slab(SlabGeom(boundary: [Vec2(-500, -500), Vec2(6500, -500), Vec2(6500, 500), Vec2(-500, 500)], thickness: 200, topOffset: 3000)), material: "Concrete")
        let pm = StructuralAnalysis.model(p)
        XCTAssertEqual(pm.members.filter { $0.kind == "beam" }.count, 1)
        XCTAssertEqual(pm.nodes.count, 4, "beam ends snap to the column tops")
        let json = pm.json()
        XCTAssertEqual(json["format"] as? String, "archi-analytical-1")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(json))
        let pr = try StructuralAnalysis.solve(pm)
        let weight = pm.members.reduce(0) { $0 + $1.material.weight * $1.area * m3len(pm, $1) } + pm.nodeLoads.reduce(0) { $0 - $1.force.z }
        XCTAssertEqual(pr.reactions.values.reduce(0) { $0 + $1.f.z }, weight, accuracy: 1e-6)
        XCTAssertThrowsError(try StructuralAnalysis.solve(AnalyticalModel()))
    }
    func m3len(_ m: AnalyticalModel, _ mem: AnalyticalMember) -> Double { m.nodes[mem.start - 1].p.distance(to: m.nodes[mem.end - 1].p) }

    func testReverbCarbonIsovist() throws {
        var (d, _) = box(5000, 4000, thickness: 200)
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(4900, 100), Vec2(4900, 3900), Vec2(100, 3900)], name: "Room", height: 2700)))
        let rv = Acoustics.reverberation(d)
        let a = 4.8 * 3.8, per = 2 * (4.8 + 3.8)
        let A = a * 0.05 * 2 + per * 2.7 * 0.04
        XCTAssertEqual(rv[0].rt60, 0.161 * a * 2.7 / A, accuracy: 1e-9)
        let c = EmbodiedCarbon.compute(d)
        let concrete = try XCTUnwrap(c.first { $0.material == "Concrete" })
        XCTAssertEqual(concrete.carbon, concrete.volume * 2400 * 0.13, accuracy: 1e-6)
        XCTAssertFalse(concrete.assumed)
        // Isovist from the room centre sees the inner face square (4.8 × 3.8 m).
        let obs = Isovist.obstacles(d, level: 0, eyeHeight: 1600)
        let poly = Isovist.polygon(from: Vec2(2500, 2000), obstacles: obs, maxDistance: 50000, rays: 1440)
        XCTAssertEqual(abs(GeometryOps.signedArea(poly)) / 1e6, 4.8 * 3.8, accuracy: 4.8 * 3.8 * 0.005)
        XCTAssertLessThanOrEqual(poly.map { $0.distance(to: Vec2(2500, 2000)) }.max()!, hypot(2400, 1900) + 1e-6)
    }

    func testIFCValidator() throws {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)))
        let good = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        XCTAssertTrue(IFCValidator.validate(good).filter { $0.severity == .error }.isEmpty, IFCValidator.validate(good).map(\.description).joined(separator: "\n"))
        var bad = good.replacingOccurrences(of: "IFCWALL('", with: "IFCWALL('bad")
        bad = bad.replacingOccurrences(of: "IFCRELAGGREGATES(", with: "IFCRELAGGREGATES('x',#99999,")
        let issues = IFCValidator.validate(bad)
        XCTAssertTrue(issues.contains { $0.code == "GLOBALID-FORMAT" })
        XCTAssertTrue(issues.contains { $0.code == "DANGLING-REFERENCE" })
        XCTAssertTrue(issues.contains { $0.code == "ATTRIBUTE-COUNT" })
        XCTAssertEqual(IFCValidator.validate("nonsense").first?.code, "STEP-SYNTAX")
    }
}
