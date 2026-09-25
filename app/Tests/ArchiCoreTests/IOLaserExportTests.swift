// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IOLaserExportTests: XCTestCase {
    func plate() -> ArchiDocument {
        var d = ArchiDocument()
        // Outer 100 × 50 mm outline drawn as four separate lines, a Ø10 hole, an engraved label line (blue layer).
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0)))); d.add(.line(LineGeom(Vec2(100, 0), Vec2(100, 50))))
        d.add(.line(LineGeom(Vec2(100, 50), Vec2(0, 50)))); d.add(.line(LineGeom(Vec2(0, 50), Vec2(0, 0))))
        d.add(.circle(CircleGeom(Vec2(20, 25), 5)))
        d.add(.line(LineGeom(Vec2(40, 20), Vec2(80, 20))), layer: "ENGRAVE")
        d.add(.text(TextGeom(position: Vec2(40, 30), height: 5, content: "A")))
        return d
    }

    func testJoinedPathsOperationsAndTrueSize() {
        let r = LaserExporter.export(plate())
        XCTAssertEqual(r.cutPaths, 2, "four lines joined into one outline + the hole")
        XCTAssertEqual(r.engravePaths, 1)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertEqual(r.size.x, 104, accuracy: 1e-9); XCTAssertEqual(r.size.y, 54, accuracy: 1e-9)
        XCTAssertTrue(r.svg.contains("width=\"104mm\" height=\"54mm\" viewBox=\"0 0 104 54\""))
        XCTAssertTrue(r.svg.contains("<circle cx=\"22\" cy=\"27\" r=\"5\"/>"), r.svg)
        XCTAssertTrue(r.svg.contains("stroke=\"#FF0000\""))
        XCTAssertFalse(r.svg.contains("fill=\"#"), "no fills")
        XCTAssertNotNil(r.svg.range(of: "Z\"/>"), "the outline is a closed path")
    }

    func testKerfCompensationAndModelScale() {
        var d = plate()
        d.units = .meters   // 0.1 m plate = 100 mm
        for i in d.entities.indices { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, Transform2D.scale(0.001, 0.001)) }
        let r = LaserExporter.export(d, options: LaserOptions(scale: 1, kerf: 0.2))
        XCTAssertTrue(r.svg.contains("r=\"4.9\""), "hole shrinks by half the kerf: \(r.svg)")
        XCTAssertEqual(r.size.x, 104.2, accuracy: 1e-6, "outline grows by half the kerf on each side")
        let s = LaserExporter.export(plate(), options: LaserOptions(scale: 10))
        XCTAssertEqual(s.size.x, 14, accuracy: 1e-9, "1:10 model")
    }

    @MainActor func testCommandWritesFile() async throws {
        let ed = Editor()
        ed.doc = plate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plate-\(UUID().uuidString).svg")
        await ed.run("LASEREXPORT 1 0 \(url.path)")
        let s = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(s.contains("<g id=\"cut\""))
    }
}
