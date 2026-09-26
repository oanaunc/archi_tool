// Oanarina Archi Tool — GPL-3.0-or-later
// Sun study (ANL-019): the solar calculator against published reference results (NREL SPA, Meeus).
import XCTest
@testable import ArchiCore

final class AnalysisSolarValidationTests: XCTestCase {
    func testReferenceResults() {
        let lines = SolarCalculator.validate()
        XCTAssertEqual(lines.count, 7)
        for l in lines { XCTAssertTrue(l.passes, "\(l.reference) \(l.quantity): expected \(l.expected), got \(l.computed)") }
    }

    /// The shadow of a vertical pole has length h / tan(altitude) and points away from the sun.
    func testShadowGeometryFollowsTheSun() {
        let date = SolarCalculator.date("2003-10-17", "12:30:30", utcOffset: -7)!
        let p = SolarCalculator.position(date: date, latitude: 39.742476, longitude: -105.1786)
        let dir = SolarCalculator.direction(p)
        XCTAssertEqual(dir.length, 1, accuracy: 1e-12)
        XCTAssertEqual(asin(dir.z) * 180 / .pi, p.altitude, accuracy: 1e-9)
        let h = 10.0
        let tip = Vec2(-dir.x, -dir.y) * (h * cos(asin(dir.z)) / dir.z) / Vec2(dir.x, dir.y).length
        XCTAssertEqual(tip.length, h / tan(p.altitude * .pi / 180), accuracy: 1e-9)
        // Azimuth ≈ 194° (south-south-west): the shadow points north-north-east.
        XCTAssertGreaterThan(tip.y, 0); XCTAssertGreaterThan(tip.x, 0)
    }

    @MainActor func testValidateOption() async {
        let ed = Editor()
        let out = await ed.run("SUNPOSITION V ").joined(separator: "\n")
        XCTAssertTrue(out.contains("Solar position validation"), out)
        XCTAssertFalse(out.contains("FAIL"), out)
    }
}
