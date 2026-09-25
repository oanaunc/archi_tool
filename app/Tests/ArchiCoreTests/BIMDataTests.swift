// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMDataTests: XCTestCase {
    func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vec2] { [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)] }

    func testZonesAssignListAndOutline() async {
        let ed = Editor()
        let a = ed.doc.addElement(.space(SpaceGeom(boundary: rect(0, 0, 4000, 3000), name: "Office 1")))
        let b = ed.doc.addElement(.space(SpaceGeom(boundary: rect(4200, 0, 8000, 3000), name: "Office 2")))
        let c = ed.doc.addElement(.space(SpaceGeom(boundary: rect(0, 5000, 3000, 8000), name: "Store")))
        ed.selection = [a, b]
        await ed.run("ZONE Assign Fire FC1")
        ed.selection = [c]
        await ed.run("ZONE Assign Fire FC2")
        ed.selection = [a, c]
        await ed.run("ZONE Assign HVAC North")
        let fire = Zones.all(ed.doc, type: "Fire")
        XCTAssertEqual(fire.map(\.name), ["FC1", "FC2"])
        XCTAssertEqual(fire[0].area, 4000 * 3000 + 3800 * 3000, accuracy: 1e-6)
        XCTAssertEqual(Zones.all(ed.doc).count, 3)
        // Outline bridges the 200 mm wall between the two offices.
        let o = Zones.outline(fire[0], doc: ed.doc, gap: 400)
        XCTAssertEqual(o.count, 1)
        XCTAssertEqual(abs(GeometryOps.signedArea(o[0])), 8000 * 3000, accuracy: 1)
        await ed.run("ZONE Outline Fire 400")
        let outlines = ed.doc.entities.filter { $0.props["zoneOutline"]?.hasPrefix("Fire:") ?? false }
        XCTAssertEqual(outlines.filter { if case .polyline = $0.geometry { return true }; return false }.count, 2)
        XCTAssertEqual(outlines.filter { if case .text = $0.geometry { return true }; return false }.count, 2)
        // Re-running replaces the previous outlines.
        await ed.run("ZONE Outline Fire 400")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["zoneOutline"]?.hasPrefix("Fire:") ?? false }.count, 4)
        ed.selection = [c]
        await ed.run("ZONE Remove Fire")
        XCTAssertEqual(Zones.all(ed.doc, type: "Fire").map(\.name), ["FC1"])
    }

    func testPropertySetsTemplatesAndClassification() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let w = ed.doc.elements[0].id
        if let i = ed.doc.elementIndex(w), case .wall(var g) = ed.doc.elements[i].geometry { g.thickness = 300; ed.doc.elements[i].geometry = .wall(g) }
        await ed.run("WALL 0,3000 6000,3000 ")
        let inner = ed.doc.elements.last!.id
        if let i = ed.doc.elementIndex(inner), case .wall(var g) = ed.doc.elements[i].geometry { g.thickness = 100; ed.doc.elements[i].geometry = .wall(g) }
        // Typed standard property.
        ed.selection = [w]
        await ed.run("PSET Set Pset_WallCommon.LoadBearing yes")
        XCTAssertEqual(ed.doc.element(w)?.props["Pset_WallCommon.LoadBearing"], "true")
        ed.selection = [w]
        await ed.run("PSET Set Pset_WallCommon.ThermalTransmittance abc")
        XCTAssertNil(ed.doc.element(w)?.props["Pset_WallCommon.ThermalTransmittance"])
        XCTAssertNotNil(PropertySets.set(&ed.doc, w, pset: "Pset_DoorCommon", property: "FireRating", value: "EI30"), "door set on a wall")
        // Apply fills Reference and IsExternal from the model.
        ed.selection = []
        await ed.run("PSET Apply Pset_WallCommon ")
        XCTAssertEqual(ed.doc.element(w)?.props["Pset_WallCommon.IsExternal"], "true")
        XCTAssertEqual(ed.doc.element(inner)?.props["Pset_WallCommon.IsExternal"], "false")
        XCTAssertNotNil(ed.doc.element(inner)?.props["Pset_WallCommon.Reference"])
        // Custom template with a typed property and default.
        await ed.run("PSET Template New CPset_Acoustics wall")
        await ed.run("PSET Template Add CPset_Acoustics Rw Integer 45")
        XCTAssertEqual(ed.doc.psetTemplate("CPset_Acoustics")?.properties.first, PsetProperty("Rw", .integer, defaultValue: "45"))
        ed.selection = [inner]
        await ed.run("PSET Apply CPset_Acoustics")
        XCTAssertEqual(ed.doc.element(inner)?.props["CPset_Acoustics.Rw"], "45")
        XCTAssertNotNil(PropertySets.set(&ed.doc, inner, pset: "CPset_Acoustics", property: "Colour", value: "red"), "not in the custom template")
        ed.doc.elements[ed.doc.elementIndex(inner)!].props["CPset_Acoustics.Rw"] = "loud"
        XCTAssertEqual(PropertySets.check(ed.doc).count, 1)
        XCTAssertEqual(PropertySets.sets(ed.doc.element(w)!)["Pset_WallCommon"]?.count, 3)
        // Classification.
        ed.selection = []
        await ed.run("CLASSIFY Auto Uniformat  No")
        XCTAssertEqual(ed.doc.element(w)?.props["Classification.Uniformat"], "B2010")
        XCTAssertEqual(ed.doc.element(inner)?.props["Classification.Uniformat"], "C1010")
        await ed.run("CLASSIFY Auto NLSfB  No")
        XCTAssertEqual(ed.doc.element(w)?.props["Classification.NLSfB"], "21")
        ed.selection = [inner]
        await ed.run("CLASSIFY Set Uniclass Ss_25_10_30 Brick wall systems")
        XCTAssertEqual(ed.doc.element(inner)?.props["Classification.Uniclass"], "Ss_25_10_30")
        XCTAssertEqual(ed.doc.element(inner)?.props["Classification.UniclassTitle"], "Brick wall systems")
        // Persistence of templates; IFC export carries the sets.
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.psetTemplates, ed.doc.psetTemplates)
        let ifc = IFCExporter.export(doc: ed.doc, meshes: MeshBuilder.build(doc: ed.doc))
        XCTAssertTrue(ifc.contains("'CPset_Acoustics'"))
        XCTAssertTrue(ifc.contains("'Classification'"))
    }
}
