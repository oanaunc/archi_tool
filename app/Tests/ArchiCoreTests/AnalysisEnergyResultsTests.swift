// Oanarina Archi Tool — GPL-3.0-or-later
// EnergyPlus results (ANL-024): error log, tabular report and hourly ideal-loads output read back onto the rooms.
import XCTest
@testable import ArchiCore

final class AnalysisEnergyResultsTests: XCTestCase {
    func testResultsAreReadAndWrittenToRooms() throws {
        var d = AnalysisEnergyPlusTests().house()
        let model = try EnergyPlusExport.build(d)
        let zones = model.zones.map { $0.name.uppercased() }
        XCTAssertEqual(zones.count, 2)
        XCTAssertEqual(Set(model.zoneRooms.keys), Set(zones))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("eplus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        Program Version,EnergyPlus, Version 9.4.0
           ** Warning ** Weather file location will be used rather than entered Location object.
           ************* EnergyPlus Completed Successfully-- 1 Warning; 0 Severe Errors; Elapsed Time=00hr 00min  2.10sec
        """.write(to: dir.appendingPathComponent("eplusout.err"), atomically: true, encoding: .utf8)
        try """
        REPORT:,Annual Building Utility Performance Summary
        FOR:,Entire Facility

        Site and Source Energy

        ,,Total Energy [GJ],Energy Per Total Building Area [MJ/m2],Energy Per Conditioned Building Area [MJ/m2]
        ,Total Site Energy,36.00,1125.00,1125.00
        ,Net Site Energy,36.00,1125.00,1125.00

        End Uses

        ,,Electricity [GJ],Natural Gas [GJ],District Cooling [GJ],District Heating [GJ],Water [m3]
        ,Heating,0.00,0.00,0.00,27.00,0.00
        ,Cooling,0.00,0.00,9.00,0.00,0.00
        ,Total End Uses,0.00,0.00,9.00,27.00,0.00

        Comfort and Setpoint Not Met Summary

        ,,Facility [Hours]
        ,Time Setpoint Not Met During Occupied Heating,12.50
        ,Time Setpoint Not Met During Occupied Cooling,3.00
        """.write(to: dir.appendingPathComponent("eplustbl.csv"), atomically: true, encoding: .utf8)
        let z0 = zones[0], z1 = zones[1]
        try """
        Date/Time,\(z0) IDEAL LOADS AIR SYSTEM:Zone Ideal Loads Supply Air Total Heating Energy [J](Hourly),\(z0) IDEAL LOADS AIR SYSTEM:Zone Ideal Loads Supply Air Total Cooling Energy [J](Hourly),\(z1) IDEAL LOADS AIR SYSTEM:Zone Ideal Loads Supply Air Total Heating Energy [J](Hourly)
         01/01  01:00:00,7200000,0,3600000
         01/01  02:00:00,3600000,0,3600000
         07/01  14:00:00,0,10800000,0
        """.write(to: dir.appendingPathComponent("eplusout.csv"), atomically: true, encoding: .utf8)
        let r = EnergyPlusExport.results(dir)
        XCTAssertTrue(r.completed)
        XCTAssertEqual(r.warnings, 1); XCTAssertEqual(r.severe, 0)
        XCTAssertEqual(r.siteEnergyKWh ?? 0, 10_000, accuracy: 1)
        XCTAssertEqual(r.euiKWhPerM2 ?? 0, 312.5, accuracy: 0.1)
        XCTAssertEqual(r.endUses["Heating"] ?? 0, 7500, accuracy: 1)
        XCTAssertEqual(r.endUses["Cooling"] ?? 0, 2500, accuracy: 1)
        XCTAssertEqual(r.unmetHeatingHours, 12.5); XCTAssertEqual(r.unmetCoolingHours, 3)
        XCTAssertEqual(r.zones[z0]?.heatKWh ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(r.zones[z0]?.peakHeatKW ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(r.zones[z0]?.coolKWh ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(r.zones[z1]?.heatKWh ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(EnergyPlusExport.applyResults(r, model: model, to: &d), 2)
        let room = try XCTUnwrap(d.elements.first { $0.id == model.zoneRooms[z0] })
        XCTAssertEqual(room.props["energyHeating_kWh"], "3")
        XCTAssertEqual(room.props["peakHeating_kW"], "2")
        XCTAssertNotNil(room.props["energyHeating_kWh_m2"])
        // A run that stopped reports it.
        try "   **  Fatal  ** Something\n".write(to: dir.appendingPathComponent("eplusout.err"), atomically: true, encoding: .utf8)
        let bad = EnergyPlusExport.results(dir)
        XCTAssertFalse(bad.completed); XCTAssertEqual(bad.fatal, 1)
    }

    func testInterzoneSurfacesArePaired() throws {
        var d = AnalysisEnergyPlusTests().house()
        // A room above the living room with the same outline (ceiling ↔ floor pair), on a second level.
        let upper: Int
        if let l = d.levels.sorted(by: { $0.elevation < $1.elevation }).first(where: { $0.elevation > 0 }) { upper = l.id } else {
            d.levels.append(Level(id: 99, name: "Level 1", elevation: 3000, height: 3000)); upper = 99
        }
        d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Study", number: "101", height: 2700)), level: upper)
        let m = try EnergyPlusExport.build(d)
        let paired = m.surfaces.filter { $0.boundary == "Surface" }
        XCTAssertFalse(paired.isEmpty)
        let byName = Dictionary(uniqueKeysWithValues: m.surfaces.map { ($0.name, $0) })
        for s in paired {
            let o = try XCTUnwrap(byName[s.boundaryObject], "partner of \(s.name)")
            XCTAssertEqual(o.boundaryObject, s.name)
            XCTAssertNotEqual(o.zone, s.zone)
            // Same area, opposite normals.
            let n1 = AnalysisEnergyPlusTests.newell(s.vertices), n2 = AnalysisEnergyPlusTests.newell(o.vertices)
            XCTAssertEqual(n1.length, n2.length, accuracy: n1.length * 0.01 + 1e-9, s.name)
            XCTAssertLessThan(n1.dot(n2), 0, s.name)
        }
        // The shared wall between Living and Bed (x = 5 m) and the Living ceiling / Study floor.
        XCTAssertTrue(paired.contains { $0.type == "Wall" })
        XCTAssertTrue(paired.contains { $0.type == "Ceiling" } && paired.contains { $0.type == "Floor" })
        XCTAssertTrue(m.idf.contains(",\n    Surface,\n"))
        XCTAssertTrue(m.idf.contains("Intermediate Floor Reversed"))
    }
}
