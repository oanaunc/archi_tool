// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class ModelFormatV2Tests: XCTestCase {
    func testVersion1FileMigratesToCurrentVersion() throws {
        XCTAssertEqual(ArchiDocument.currentFormatVersion, 6)
        XCTAssertNotNil(ArchiFile.migrations[1], "1 → 2 migration hook")
        let json = """
        {"app":"Oanarina Archi Tool","formatVersion":1,"document":{"formatVersion":1,"nextID":3,"elements":[
          {"id":1,"level":0,"name":"","layer":"A-WALL","props":{},"geometry":{"type":"wall","start":{"x":0,"y":0},"end":{"x":4000,"y":0},"thickness":200,"height":3000}},
          {"id":2,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"stair","start":{"x":0,"y":0},"direction":0,"width":1000,"totalRise":3000,"riserCount":17,"treadDepth":280,"kind":"straight"}},
          {"id":3,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"component","category":"Furniture","position":{"x":0,"y":0},"rotation":0,"size":{"x":600,"y":600,"z":750},"baseOffset":0}}
        ]}}
        """
        let doc = try ArchiFile.decode(Data(json.utf8))
        XCTAssertEqual(doc.formatVersion, ArchiDocument.currentFormatVersion)
        guard case .wall(let w) = doc.elements[0].geometry, case .stair(let s) = doc.elements[1].geometry, case .component(let c) = doc.elements[2].geometry else { return XCTFail() }
        XCTAssertNil(w.topLevel); XCTAssertEqual(w.topOffset, 0)
        XCTAssertNil(s.landingAt); XCTAssertNil(s.landingDepth); XCTAssertNil(s.topLevel)
        XCTAssertNil(c.family)
        // Saved again as the current version.
        let text = String(decoding: try ArchiFile.encode(doc), as: UTF8.self)
        XCTAssertTrue(text.contains("\"formatVersion\" : \(ArchiDocument.currentFormatVersion)"))
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

extension ModelFormatV2Tests {
    /// Version 2 files open unchanged in version 3; the version 3 fields round-trip.
    func testVersion2FileOpensAndV3FieldsRoundTrip() throws {
        let v2 = """
        {"app":"Oanarina Archi Tool","formatVersion":2,"document":{"formatVersion":2,"nextID":3,"elements":[
          {"id":1,"level":0,"name":"","layer":"A-WALL","props":{},"geometry":{"type":"curtainWall","start":{"x":0,"y":0},"end":{"x":4000,"y":0}}},
          {"id":2,"level":0,"name":"","layer":"A-ELEMENTS","props":{},"geometry":{"type":"beam","start":{"x":0,"y":0},"end":{"x":4000,"y":0},"width":200,"depth":400,"topOffset":3000}}
        ]}}
        """
        let doc = try ArchiFile.decode(Data(v2.utf8))
        guard case .curtainWall(let cw) = doc.elements[0].geometry, case .beam(let b) = doc.elements[1].geometry else { return XCTFail() }
        XCTAssertNil(cw.mullionProfile); XCTAssertNil(b.profile); XCTAssertFalse(b.isSloped)
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2000, width: 1500, height: 1200, sill: 900, mullions: 2, transoms: 1)))
        d.addElement(.beam(BeamGeom(start: .zero, end: Vec2(3000, 0), profile: "IPE200", endTopOffset: 3500)))
        d.addElement(.column(ColumnGeom(position: .zero, profile: "HEB200")))
        d.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(10, 20), size: Vec3(50, 50, 50), baseOffset: 2700, family: "pipe",
                                              path: [.zero, Vec2(1000, 0)], pathZ: [0, -10])))
        d.addElement(.stair(StairGeom(start: .zero, kind: .uShape, winders: 6, clockwise: true)))
        d.addElement(.curtainWall(CurtainWallGeom(start: .zero, end: Vec2(3000, 0), mullionProfile: "fin", borderProfile: "capped", mullionDepth: 150)))
        d.openingTypes[0].formulas = ["height": "width + 1200"]; d.openingTypes[0].threshold = true
        let back = try ArchiFile.decode(try ArchiFile.encode(d))
        XCTAssertEqual(back.elements, d.elements)
        XCTAssertEqual(back.openingTypes, d.openingTypes)
    }
}
