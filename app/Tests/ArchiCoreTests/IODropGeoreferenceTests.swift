// Oanarina Archi Tool — GPL-3.0-or-later
// Drag and drop import (IO-065): georeferenced files keep their map position; other files land at the drop point.
import XCTest
@testable import ArchiCore

final class IODropGeoreferenceTests: XCTestCase {
    func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func png(width: Int, height: Int) -> Data {
        var d = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]) + Data("IHDR".utf8)
        for v in [width, height] { d += Data([UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)]) }
        d += Data([8, 6, 0, 0, 0, 0, 0, 0, 0])
        return d
    }
    func bounds(_ doc: ArchiDocument, _ ids: [EntityID]) -> BBox2 {
        ids.compactMap { doc.entity($0) }.reduce(BBox2.empty) { $0.union(GeometryOps.bounds($1.geometry, doc: doc)) }
    }

    func testGeoreferencedDropsKeepTheirPlace() throws {
        let dir = try tmp()
        var base = ArchiDocument()
        base.info.latitude = 52.3702; base.info.longitude = 4.8952
        let geo = dir.appendingPathComponent("site.geojson")
        try """
        {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"name":"tree"},"geometry":{"type":"Point","coordinates":[4.8962,52.3712]}},
        {"type":"Feature","properties":{},"geometry":{"type":"LineString","coordinates":[[4.8952,52.3702],[4.8972,52.3702]]}}]}
        """.write(to: geo, atomically: true, encoding: .utf8)
        let img = dir.appendingPathComponent("ortho.png")
        try Self.png(width: 200, height: 100).write(to: img)
        try "0.5\n0\n0\n-0.5\n120.25\n340.75\n".write(to: dir.appendingPathComponent("ortho.pgw"), atomically: true, encoding: .utf8)
        let svg = dir.appendingPathComponent("logo.svg")
        try "<svg xmlns='http://www.w3.org/2000/svg' width='100' height='50'><rect x='0' y='0' width='100' height='50'/></svg>".write(to: svg, atomically: true, encoding: .utf8)

        XCTAssertTrue(ExternalContent.isGeoreferenced(geo))
        XCTAssertTrue(ExternalContent.isGeoreferenced(img))
        XCTAssertFalse(ExternalContent.isGeoreferenced(svg))

        // Reference placements: a plain import at the map position.
        var ref = base
        let (rg, _) = try FileImport.importFile(geo, into: &ref)
        let (ri, _) = try FileImport.importFile(img, into: &ref)
        let (rs, _) = try FileImport.importFile(svg, into: &ref)
        let expectGeo = bounds(ref, rg.allIDs), expectImg = bounds(ref, ri.allIDs), expectSvg = bounds(ref, rs.allIDs)
        XCTAssertFalse(expectGeo.isEmpty)

        var d = base
        let drop = Vec2(90_000, -40_000)
        let r = ExternalContent.drop([geo, img, svg], into: &d, at: drop)
        XCTAssertTrue(r.allSatisfy { $0.error == nil }, r.map { $0.error ?? "" }.joined())
        let g = bounds(d, r[0].result?.ids ?? []), i = bounds(d, r[1].result?.ids ?? []), s = bounds(d, r[2].result?.ids ?? [])
        XCTAssertTrue(g.min.isClose(expectGeo.min, tol: 1e-6) && g.max.isClose(expectGeo.max, tol: 1e-6), "GeoJSON stays at its map position")
        XCTAssertTrue(i.min.isClose(expectImg.min, tol: 1e-6), "world-file image stays georeferenced")
        XCTAssertEqual(i.max.x - i.min.x, 100_000, accuracy: 1e-6, "200 px × 0.5 m = 100 m")
        XCTAssertTrue(r[0].result?.summary.contains("georeferenced") ?? false)
        // The non-georeferenced SVG lands at the drop point.
        XCTAssertEqual(s.min.x, expectSvg.min.x + drop.x, accuracy: 1e-6)
        XCTAssertEqual(s.min.y, expectSvg.min.y + drop.y, accuracy: 1e-6)
    }

    func testPastedGeoJSONIsGeoreferenced() throws {
        var base = ArchiDocument()
        base.info.latitude = 44.43; base.info.longitude = 26.10
        let text = #"{"type":"Feature","properties":{},"geometry":{"type":"LineString","coordinates":[[26.10,44.43],[26.101,44.43]]}}"#
        XCTAssertEqual(ExternalContent.kind(of: Data(text.utf8), type: "public.utf8-plain-text"), .geojson)
        var ref = base
        let expected = try GeoJSON.entities(text, doc: ref)
        var d = base
        let r = try ExternalContent.insert(Data(text.utf8), type: "public.utf8-plain-text", into: &d, at: Vec2(777, 888))
        XCTAssertEqual(r.kind, .geojson)
        let b = bounds(d, r.ids)
        ref.entities = []
        for e in expected { ref.add(e) }
        let eb = bounds(ref, ref.entities.map(\.id))
        XCTAssertTrue(b.min.isClose(eb.min, tol: 1e-6) && b.max.isClose(eb.max, tol: 1e-6), "pasted at its map position, not at the paste point")
        XCTAssertEqual(b.width, 79_400, accuracy: 1_000, "0.001° of longitude at 44.43° N ≈ 79.5 m")
        // Plain text still pastes as text.
        XCTAssertEqual(ExternalContent.kind(of: Data("Hello".utf8), type: "public.utf8-plain-text"), .text)
    }
}
