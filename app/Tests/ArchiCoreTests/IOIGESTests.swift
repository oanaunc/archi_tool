// Oanarina Archi Tool — GPL-3.0-or-later
// IGES import/export (IO-041).
import XCTest
@testable import ArchiCore

final class IOIGESTests: XCTestCase {
    func testExportLayoutAndRoundTrip() throws {
        var d = ArchiDocument()
        d.units = .meters
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(2.5, 1))), color: .aci(1))
        d.add(.circle(CircleGeom(Vec2(1, 1), 0.5)))
        d.add(.arc(ArcGeom(Vec2(3, 0), 1, 0, .pi / 2)))
        d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: true)))
        d.add(.point(Vec2(7, 8)))
        let igs = IGES.export(d)
        let lines = igs.split(separator: "\n")
        XCTAssertTrue(lines.allSatisfy { $0.count == 80 }, "fixed 80-column records")
        XCTAssertEqual(lines.last?.suffix(8), "T      1")
        XCTAssertEqual(lines.filter { $0.dropFirst(72).hasPrefix("D") }.count, 10, "two DE lines per entity")
        XCTAssertTrue(igs.contains("1HM"), "units: metres")
        let back = try IGES.read(igs)
        XCTAssertEqual(back.count, 5)
        // Imported in millimetres.
        guard case .line(let l) = back[0].geometry else { return XCTFail() }
        XCTAssertEqual(l.b.x, 2500, accuracy: 1e-6)
        XCTAssertEqual(back[0].color, .rgb(255, 0, 0))
        guard case .circle(let c) = back[1].geometry else { return XCTFail() }
        XCTAssertEqual(c.radius, 500, accuracy: 1e-6)
        guard case .arc(let a) = back[2].geometry else { return XCTFail() }
        XCTAssertEqual(a.start, 0, accuracy: 1e-9); XCTAssertEqual(a.end, .pi / 2, accuracy: 1e-9)
        guard case .polyline(let p) = back[3].geometry else { return XCTFail() }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3)
        // Through the file import / export paths.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).igs")
        try DocumentIO.write(d, to: url)
        XCTAssertEqual(try FileImport.load(url).0.entities.count, 5)
    }

    /// A hand-made file as written by another CAD system: inch units, a rational B-spline (126) and a line.
    func testForeignFileWithBSplineAndInches() throws {
        func rec(_ s: String, _ c: Character, _ n: Int) -> String { s.padding(toLength: 72, withPad: " ", startingAt: 0) + String(c) + String(repeating: " ", count: 7 - "\(n)".count) + "\(n)" }
        func de(_ f: [String], _ n: Int) -> String { rec(f.map { String(repeating: " ", count: 8 - $0.count) + $0 }.joined(), "D", n) }
        func pl(_ s: String, _ de: Int, _ n: Int) -> String { s.padding(toLength: 64, withPad: " ", startingAt: 0) + String(repeating: " ", count: 8 - "\(de)".count) + "\(de)" + "P" + String(repeating: " ", count: 7 - "\(n)".count) + "\(n)" }
        let text = [
            rec("Sample from another system", "S", 1),
            rec("1H,,1H;,4HPART,8Hpart.igs,3HCAD,3H1.0,32,38,6,308,15,4HPART,1.,1,2HIN,1,0.01,", "G", 1),
            rec("15H20260101.120000,0.0001,10.,6HAuthor,3HOrg,11,0;", "G", 2),
            de(["110", "1", "0", "1", "0", "0", "0", "0", "00000000"], 1), de(["110", "0", "3", "1", "0", "", "", "", "0"], 2),
            de(["126", "2", "0", "1", "0", "0", "0", "0", "00000000"], 3), de(["126", "0", "0", "2", "0", "", "", "", "0"], 4),
            pl("110,0.,0.,0.,10.,0.,0.;", 1, 1),
            pl("126,2,2,1,0,1,0,0.,0.,0.,1.,1.,1.,1.,1.,1.,0.,0.,0.,1.,1.,0.,", 3, 2),
            pl("2.,0.,0.,0.,1.,0.,0.,1.;", 3, 3),
            rec("S      1G      2D      4P      3", "T", 1),
        ].joined(separator: "\n")
        let ents = try IGES.read(text)
        XCTAssertEqual(ents.count, 2)
        guard case .line(let l) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(l.b.x, 254, accuracy: 1e-9, "10 inches")
        XCTAssertEqual(ents[0].color, .rgb(0, 255, 0))
        guard case .spline(let s) = ents[1].geometry else { return XCTFail() }
        XCTAssertEqual(s.degree, 2); XCTAssertEqual(s.controlPoints.count, 3); XCTAssertNil(s.weights)
        XCTAssertEqual(s.controlPoints[1], Vec2(25.4, 25.4))
        XCTAssertThrowsError(try IGES.read("not iges"))
    }
}
