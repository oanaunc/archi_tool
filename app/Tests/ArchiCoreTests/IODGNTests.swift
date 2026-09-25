// Oanarina Archi Tool — GPL-3.0-or-later
// DGN V7 import/export (IO-013).
import XCTest
@testable import ArchiCore

final class IODGNTests: XCTestCase {
    func testVaxDoubleRoundTrip() {
        for v in [0.0, 1.0, -1.0, 0.5, 1234.5678, 1e-5, 12_345_678.25, -987.125] {
            var b = [UInt8](); DGN.putVax(v, &b)
            XCTAssertEqual(DGN.vax(b, 0), v, accuracy: abs(v) * 1e-15 + 1e-300)
        }
        // Known VAX encoding of 1.0: 0x4080 in the first word.
        var one = [UInt8](); DGN.putVax(1.0, &one)
        XCTAssertEqual(Array(one.prefix(2)), [0x80, 0x40])
        var b = [UInt8](); DGN.putInt32(-123456, &b)
        XCTAssertEqual(DGN.int32(b, 0), -123456)
    }

    func testRoundTripOfElements() throws {
        var d = ArchiDocument()
        d.ensureLayer("A-WALL")
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(5000, 0))), layer: "A-WALL", color: .aci(1))
        d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)], closed: true)))
        d.add(.polyline(PolylineGeom(points: (0..<150).map { Vec2(Double($0) * 10, 0) })))
        d.add(.circle(CircleGeom(Vec2(2000, 2000), 350.5)))
        d.add(.arc(ArcGeom(Vec2(0, 0), 1000, 0, .pi / 2)))
        d.add(.text(TextGeom(position: Vec2(100, 200), height: 250, content: "Level 1", rotation: .pi / 6)))
        let data = DGN.write(d)
        XCTAssertEqual(data.count % 2, 0)
        XCTAssertEqual(Array(data.suffix(2)), [0xFF, 0xFF])
        let r = try DGN.read(data)
        XCTAssertFalse(r.is3D)
        let ents = r.entities
        guard case .line(let l) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(l.b.x, 5000, accuracy: 0.1)
        XCTAssertEqual(ents[0].color, .aci(1))
        XCTAssertNotEqual(ents[0].layer, ents[1].layer, "layers map to levels")
        guard case .polyline(let sh) = ents[1].geometry else { return XCTFail() }
        XCTAssertTrue(sh.closed); XCTAssertEqual(sh.vertices.count, 4)
        let longRuns = ents.filter { if case .polyline(let p) = $0.geometry { return !p.closed }; return false }
        XCTAssertEqual(longRuns.count, 2, "150 vertices split into line strings of ≤ 101")
        guard case .circle(let c) = ents.first(where: { $0.typeName == "circle" })?.geometry else { return XCTFail() }
        XCTAssertEqual(c.radius, 350.5, accuracy: 0.1); XCTAssertEqual(c.center.x, 2000, accuracy: 0.1)
        guard case .arc(let a) = ents.first(where: { $0.typeName == "arc" })?.geometry else { return XCTFail() }
        XCTAssertEqual(a.radius, 1000, accuracy: 0.1); XCTAssertEqual(a.end, .pi / 2, accuracy: 1e-6)
        guard case .text(let t) = ents.first(where: { $0.typeName == "text" })?.geometry else { return XCTFail() }
        XCTAssertEqual(t.content, "Level 1"); XCTAssertEqual(t.rotation, .pi / 6, accuracy: 1e-6)
        XCTAssertEqual(t.height, 250, accuracy: 0.5)
        XCTAssertThrowsError(try DGN.read(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0])))
    }

    @MainActor func testCommands() async throws {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("CIRCLE 0,0 200")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).dgn")
        await ed.run("DGNEXPORT \(url.path)")
        let ed2 = Editor()
        await ed2.run("DGNIMPORT \(url.path)")
        XCTAssertEqual(ed2.doc.entities.count, 2)
    }
}
