// Oanarina Archi Tool — GPL-3.0-or-later
// Radiance daylight study (ANL-022): export of the scene / sensors / run script and sDA-ASE from Radiance results.
import XCTest
@testable import ArchiCore

final class AnalysisRadianceTests: XCTestCase {
    func testExportAndResults() throws {
        let d = AnalysisEnergyPlusTests().house()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rad-\(UUID().uuidString)")
        let r = try RadianceDaylight.write(d, to: dir, weather: nil)
        XCTAssertEqual(r.rooms, 2)
        XCTAssertGreaterThan(r.polygons, 20)
        let mats = try String(contentsOf: dir.appendingPathComponent("materials.rad"), encoding: .utf8)
        XCTAssertTrue(mats.contains("void glass "), mats)
        XCTAssertTrue(mats.contains("void plastic "))
        let pts = try String(contentsOf: dir.appendingPathComponent("sensors.pts"), encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(pts.count, r.sensors)
        XCTAssertTrue(pts.allSatisfy { $0.hasSuffix(" 0 0 1") })
        XCTAssertEqual(pts.first.map { Double($0.split(separator: " ")[2]) ?? 0 } ?? 0, 0.75, accuracy: 1e-9, "work plane at 0.75 m")
        let script = try String(contentsOf: dir.appendingPathComponent("run.sh"), encoding: .utf8)
        for tool in ["gendaymtx", "rfluxmtx", "dctimestep", "rmtxop -fa -c 47.4 119.9 11.6", "oconv"] { XCTAssertTrue(script.contains(tool), tool) }
        #if !os(Windows)   // Windows has no executable permission bit
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("run.sh").path))
        #endif
        XCTAssertEqual(RadianceDaylight.transmissivity(0.6), 0.6536, accuracy: 0.001)
        // Synthetic results: 3 hours (12 and 13 occupied, 20 not); every sensor of the first room lit ≥ 300 lx in one
        // occupied hour (50 %), the others dark; direct sun only in hour 12.
        var wea = "place x\nlatitude 44\nlongitude -26\ntime_zone -30\nsite_elevation 80\nweather_data_file_units 1\n"
        wea += "6 21 12.500 800 100\n6 21 13.500 700 100\n6 21 20.500 0 10\n"
        try wea.write(to: dir.appendingPathComponent("weather.wea"), atomically: true, encoding: .utf8)
        let rows = try String(contentsOf: dir.appendingPathComponent("sensors.csv"), encoding: .utf8).split(separator: "\n").dropFirst()
        let firstRoom = rows.first!.split(separator: ",")[1]
        var total = "#?RADIANCE\nNROWS=\(rows.count)\nNCOLS=3\nFORMAT=ascii\n\n", direct = ""
        for row in rows {
            let inFirst = row.split(separator: ",")[1] == firstRoom
            total += inFirst ? "500 100 900\n" : "50 20 900\n"
            direct += inFirst ? "1200 0 0\n" : "0 0 0\n"
        }
        try total.write(to: dir.appendingPathComponent("total.ill"), atomically: true, encoding: .utf8)
        try direct.write(to: dir.appendingPathComponent("direct.ill"), atomically: true, encoding: .utf8)
        let res = try RadianceDaylight.results(dir)
        XCTAssertEqual(res.count, 2)
        XCTAssertEqual(res[0].sDA, 100, accuracy: 1e-9)       // autonomy 1/2 ≥ 50 %
        XCTAssertEqual(res[0].meanAutonomy, 50, accuracy: 1e-9)
        XCTAssertEqual(res[1].sDA, 0, accuracy: 1e-9)
        XCTAssertEqual(res[0].ASE, 0, accuracy: 1e-9, "1 sun hour is far below 250")
        XCTAssertThrowsError(try RadianceDaylight.results(FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID().uuidString)")))
    }
}
