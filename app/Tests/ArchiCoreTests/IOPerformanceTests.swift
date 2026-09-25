// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Large-file benchmarks: 20 000 drawing objects plus 1 000 building elements must save and load within fixed budgets
/// (debug build on the test Mac; release is several times faster).
final class IOPerformanceTests: XCTestCase {
    static func largeDocument() -> ArchiDocument {
        var d = ArchiDocument()
        for i in 0..<20_000 {
            let x = Double(i % 200) * 1000, y = Double(i / 200) * 1000
            let g: Geometry
            switch i % 5 {
            case 0: g = .line(LineGeom(Vec2(x, y), Vec2(x + 800, y + 300)))
            case 1: g = .circle(CircleGeom(Vec2(x, y), 250))
            case 2: g = .polyline(PolylineGeom([PolyVertex(Vec2(x, y)), PolyVertex(Vec2(x + 500, y), bulge: 0.4), PolyVertex(Vec2(x + 500, y + 500))], closed: true))
            case 3: g = .arc(ArcGeom(Vec2(x, y), 300, 0, 2))
            default: g = .text(TextGeom(position: Vec2(x, y), height: 150, content: "T\(i)"))
            }
            d.add(g, layer: i % 2 == 0 ? "A-WALL" : "0")
        }
        for i in 0..<1_000 {
            let y = Double(i) * 4000
            _ = d.addElement(.wall(WallGeom(start: Vec2(0, -y), end: Vec2(8000, -y), thickness: 200, height: 3000)))
        }
        return d
    }

    func time(_ body: () throws -> Void) rethrows -> Double {
        let t0 = Date()
        try body()
        return Date().timeIntervalSince(t0)
    }

    func testNativeFileWith20kEntitiesSavesAndLoadsQuickly() throws {
        let d = Self.largeDocument()
        var data = Data()
        let tSave = try time { data = try ArchiFile.encode(d) }
        var back = ArchiDocument()
        let tLoad = try time { back = try ArchiFile.decode(data) }
        XCTAssertEqual(back.entities.count, 20_000); XCTAssertEqual(back.elements.count, 1_000)
        XCTAssertEqual(back, d)
        XCTAssertLessThan(tSave, 3, "save took \(tSave) s")
        XCTAssertLessThan(tLoad, 3, "load took \(tLoad) s")
        print("20k entities: save \(fmt(tSave, 3)) s, load \(fmt(tLoad, 3)) s, \(data.count / 1024) KiB")
    }

    func testDXFWith20kEntitiesRoundTripsQuickly() throws {
        var d = Self.largeDocument()
        d.elements = []
        var text = ""
        let tWrite = time { text = DXFWriter.write(d) }
        var back = ArchiDocument()
        let tRead = try time { back = try DXFReader.read(text) }
        XCTAssertEqual(back.entities.count, 20_000)
        XCTAssertLessThan(tWrite, 5, "DXF write took \(tWrite) s")
        XCTAssertLessThan(tRead, 5, "DXF read took \(tRead) s")
        print("20k entities DXF: write \(fmt(tWrite, 3)) s, read \(fmt(tRead, 3)) s")
    }

    func testJournalDeltaOnLargeDocumentIsSmallAndFast() throws {
        var d = Self.largeDocument()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString).archijournal")
        defer { try? FileManager.default.removeItem(at: url) }
        let j = try DocumentJournal(url: url, base: d)
        let baseSize = try Data(contentsOf: url).count
        d.add(.point(Vec2(1, 2)))
        let t = try time { XCTAssertTrue(try j.record(d)) }
        let delta = try Data(contentsOf: url).count - baseSize
        XCTAssertLessThan(delta, baseSize / 20, "a one-object change writes a small delta")
        XCTAssertLessThan(t, 5, "recording took \(t) s")
        let tr = try time { XCTAssertEqual(try DocumentJournal.recover(url).doc, d) }
        XCTAssertLessThan(tr, 15, "replay took \(tr) s")
    }

    /// SYS-020: a ~50 MB .archi file opens in under 3 s (debug build; release is faster).
    func testFiftyMegabyteFileOpensUnderThreeSeconds() throws {
        var d = ArchiDocument()
        var i = 0
        while i < 110_000 {
            let x = Double(i % 400) * 500, y = Double(i / 400) * 500
            switch i % 4 {
            case 0: d.add(.line(LineGeom(Vec2(x, y), Vec2(x + 400, y + 100))), layer: "A-WALL")
            case 1: d.add(.polyline(PolylineGeom(points: [Vec2(x, y), Vec2(x + 200, y), Vec2(x + 200, y + 200), Vec2(x, y + 200)], closed: true)), layer: "A-FURN")
            case 2: d.add(.text(TextGeom(position: Vec2(x, y), height: 100, content: "Label \(i)")), layer: "A-ANNO")
            default: d.add(.arc(ArcGeom(Vec2(x, y), 150, 0, 1.5)), layer: "0")
            }
            i += 1
        }
        let data = try ArchiFile.encode(d)
        XCTAssertGreaterThan(data.count, 40_000_000, "file is \(data.count / 1_000_000) MB")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-\(UUID().uuidString).archi")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var back = ArchiDocument()
        let t = try time { back = try ArchiFile.decode(Data(contentsOf: url)) }
        XCTAssertEqual(back.entities.count, 110_000)
        XCTAssertEqual(back.entities.last, d.entities.last)
        XCTAssertLessThan(t, 3, "opening \(data.count / 1_000_000) MB took \(t) s")
        print("\(data.count / 1_000_000) MB file: open \(fmt(t, 3)) s")
    }

    /// An older-format file still goes through the migrating decoder and upgrades.
    func testOlderFormatTakesMigratingPath() throws {
        var d = ArchiDocument()
        d.add(.circle(CircleGeom(Vec2(1, 2), 3)))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: ArchiFile.encode(d)) as? [String: Any])
        obj["formatVersion"] = 1
        var inner = try XCTUnwrap(obj["document"] as? [String: Any]); inner["formatVersion"] = 1; obj["document"] = inner
        let back = try ArchiFile.decode(JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(back.formatVersion, ArchiDocument.currentFormatVersion)
        XCTAssertEqual(back.entities.count, 1)
        XCTAssertThrowsError(try ArchiFile.decode(Data("{\"app\":\"x\",\"formatVersion\":99,\"document\":{}}".utf8)))
    }

    /// SYS-014 (core part): with 100 000 objects, building the spatial index and culling a viewport stay far below one
    /// 60 fps frame per query.
    func testHundredThousandEntityViewportQueries() throws {
        var d = ArchiDocument()
        for i in 0..<100_000 {
            let x = Double(i % 316) * 1000, y = Double(i / 316) * 1000
            d.add(i % 2 == 0 ? .line(LineGeom(Vec2(x, y), Vec2(x + 700, y + 400))) : .circle(CircleGeom(Vec2(x + 500, y + 500), 200)))
        }
        var idx = SpatialIndex(items: [])
        let tb = time { idx = SpatialIndex(doc: d) }
        XCTAssertEqual(idx.count, 100_000)
        XCTAssertLessThan(tb, 5, "index build took \(tb) s")
        var rng = SystemRandomNumberGenerator()
        var total = 0
        let tq = time {
            for _ in 0..<600 {
                let cx = Double.random(in: 0...316_000, using: &rng), cy = Double.random(in: 0...316_000, using: &rng)
                total += idx.query(BBox2(min: Vec2(cx - 10_000, cy - 6_000), max: Vec2(cx + 10_000, cy + 6_000))).count
            }
        }
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(tq / 600, 1.0 / 60, "a viewport query took \(tq / 600 * 1000) ms")
        print("100k entities: index \(fmt(tb, 3)) s, viewport query \(fmt(tq / 600 * 1000, 3)) ms")
    }
}
