// Oanarina Archi Tool — GPL-3.0-or-later
// gbXML (IO-029) and COBie (IO-028) exports checked against the required elements of their schemas.
import XCTest
@testable import ArchiCore

final class IOSchemaValidationTests: XCTestCase {
    func house() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.author = "Ana Pop"
        let pts = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300)), material: "Brick")) }
        let mid = d.addElement(.wall(WallGeom(start: Vec2(3000, 0), end: Vec2(3000, 4000), thickness: 100)))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 1500, width: 1200, height: 1200, sill: 900, mark: "W1")))
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 4500, width: 1200, height: 1200, sill: 900, mark: "W1")))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: walls[2], offset: 2000, width: 900, height: 2100, typeName: "D90")))
        let inner = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: mid, offset: 2000, width: 800, height: 2100)))
        d.elements[d.elementIndex(inner)!].props["fireRating"] = "EI30"
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), material: "Concrete")
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 200)), level: 1, material: "Concrete")
        _ = d.addElement(.roof(RoofGeom(boundary: pts, kind: .gable, pitch: 35, thickness: 300, overhang: 0, baseOffset: 3000)), level: 1, material: "Tile")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(2950, 150), Vec2(2950, 3850), Vec2(150, 3850)], name: "Living", number: "101")))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(3050, 150), Vec2(5850, 150), Vec2(5850, 3850), Vec2(3050, 3850)], name: "Kitchen", number: "102")))
        _ = d.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(1500, 2000), family: "sofa")))
        return d
    }

    func testGBXMLMeetsSchemaRequirements() {
        let x = GBXMLExporter.export(house())
        let issues = GBXMLValidator.validate(x)
        XCTAssertTrue(issues.isEmpty, issues.map(\.description).joined(separator: "\n"))
        XCTAssertTrue(x.contains("surfaceType=\"InteriorWall\""))
        // The validator catches broken files.
        var bad = x.replacingOccurrences(of: "surfaceType=\"Roof\"", with: "surfaceType=\"Rooof\"")
        bad = bad.replacingOccurrences(of: "constructionIdRef=\"cons-", with: "constructionIdRef=\"nope-")
        bad = bad.replacingOccurrences(of: " buildingType=\"Unknown\"", with: "")
        let codes = Set(GBXMLValidator.validate(bad).map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["ENUM", "DANGLING-REFERENCE", "ATTRIBUTE-MISSING"]), "\(codes)")
        XCTAssertEqual(GBXMLValidator.validate("<gbXML>").first?.code, "XML-SYNTAX")
        let noCampus = "<gbXML xmlns=\"http://www.gbxml.org/schema\" version=\"0.37\" temperatureUnit=\"C\" lengthUnit=\"Meters\" areaUnit=\"SquareMeters\" volumeUnit=\"CubicMeters\" useSIUnitsForResults=\"true\"/>"
        XCTAssertEqual(GBXMLValidator.validate(noCampus).map(\.code), ["CHILD-MISSING"])
    }

    func testCOBieMeetsSpreadsheetRequirements() throws {
        let sheets = try XLSX.read(COBieExporter.export(house()))
        let issues = COBieValidator.validate(sheets)
        XCTAssertTrue(issues.isEmpty, issues.map(\.description).joined(separator: "\n"))
        let comp = try XCTUnwrap(sheets.first { $0.name == "Component" })
        let names = comp.rows.dropFirst().map { $0[0] }
        XCTAssertEqual(Set(names).count, names.count, "component names are unique even with repeated marks")
        XCTAssertTrue(comp.rows.contains { $0[3] == "Door 800x2100" && $0[4] == "101,102" || $0[4] == "102,101" })
        let att = try XCTUnwrap(sheets.first { $0.name == "Attribute" })
        let fire = try XCTUnwrap(att.rows.first { $0[0] == "fireRating" })
        XCTAssertEqual(fire[6], "EI30")
        XCTAssertTrue(names.contains(fire[5]), "attribute row names its own component")
        // Broken workbooks are reported.
        var broken = sheets
        let si = broken.firstIndex { $0.name == "Space" }!
        broken[si].rows[1][4] = "Mezzanine"
        let ci = broken.firstIndex { $0.name == "Component" }!
        broken[ci].rows[1][3] = "NoSuchType"
        broken[ci].rows[2][0] = broken[ci].rows[1][0]
        broken.removeAll { $0.name == "Contact" }
        let codes = Set(COBieValidator.validate(broken).map(\.code))
        XCTAssertTrue(codes.isSuperset(of: ["FOREIGN-KEY", "NAME-DUPLICATE", "SHEET-MISSING"]), "\(codes)")
    }
}
