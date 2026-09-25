// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ModelFormatV2Tests: XCTestCase {
    func testVersion1FileMigratesToCurrentVersion() throws {
        XCTAssertEqual(ArchiDocument.currentFormatVersion, 2)
        XCTAssertNotNil(ArchiFile.migrations[1], "1 → 2 migration hook")
        let json = """
        {"app":"Oanarina Archi Tool","formatVersion":1,"document":{"formatVersion":1,"nextID":3,"elements":[
          {"id":1,"level":0,"name":"","layer":"A-WALL","props":{},"geometry":{"type":"wall","start":{"x":0,"y":0},"end":{"x":4000,"y":0},"thickness":200,"height":3000}},
          {"id":2,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"stair","start":{"x":0,"y":0},"direction":0,"width":1000,"totalRise":3000,"riserCount":17,"treadDepth":280,"kind":"straight"}},
          {"id":3,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"component","category":"Furniture","position":{"x":0,"y":0},"rotation":0,"size":{"x":600,"y":600,"z":750},"baseOffset":0}}
        ]}}
        """
        let doc = try ArchiFile.decode(Data(json.utf8))
        XCTAssertEqual(doc.formatVersion, 2)
        guard case .wall(let w) = doc.elements[0].geometry, case .stair(let s) = doc.elements[1].geometry, case .component(let c) = doc.elements[2].geometry else { return XCTFail() }
        XCTAssertNil(w.topLevel); XCTAssertEqual(w.topOffset, 0)
        XCTAssertNil(s.landingAt); XCTAssertNil(s.landingDepth); XCTAssertNil(s.topLevel)
        XCTAssertNil(c.family)
        // Saved again as the current version.
        let text = String(decoding: try ArchiFile.encode(doc), as: UTF8.self)
        XCTAssertTrue(text.contains("\"formatVersion\" : 2"))
    }

    func testMultiStoreyFieldsRoundTrip() throws {
        var doc = ArchiDocument()
        _ = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(3000, 0), topLevel: 1, topOffset: -200)))
        _ = doc.addElement(.stair(StairGeom(start: .zero, riserCount: 18, landingDepth: 1200, landingAt: 9, topLevel: 1)))
        _ = doc.addElement(.component(ComponentGeom(position: .zero, size: Vec3(1600, 2000, 500), family: "bed-double")))
        let back = try ArchiFile.decode(try ArchiFile.encode(doc))
        XCTAssertEqual(back.elements, doc.elements)
        // Unconstrained walls do not write the new keys.
        var plain = ArchiDocument()
        _ = plain.addElement(.wall(WallGeom(start: .zero, end: Vec2(1, 0))))
        XCTAssertFalse(String(decoding: try ArchiFile.encode(plain), as: UTF8.self).contains("topLevel"))
    }
}
