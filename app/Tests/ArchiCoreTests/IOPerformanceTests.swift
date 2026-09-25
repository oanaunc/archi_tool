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
}
