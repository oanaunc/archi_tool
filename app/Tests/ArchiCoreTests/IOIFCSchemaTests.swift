// Oanarina Archi Tool — GPL-3.0-or-later
// IFC2x3 (IO-021), IFC4.3 (IO-022), class mapping (IO-024) and model view definitions (IO-027).
import XCTest
@testable import ArchiCore

final class IOIFCSchemaTests: XCTestCase {
    func model() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.latitude = 44.4268; d.info.longitude = 26.1025; d.info.elevation = 80; d.info.northAngle = 10
        let w1 = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 365, height: 3000, wallType: "Exterior Brick 365")))
        let w2 = d.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 4000), thickness: 200, height: 3000)))
        var door = OpeningGeom(kind: .door, hostWall: w1, offset: 1500, width: 900, height: 2100); door.typeName = d.openingTypes.first { $0.kind == .door }?.name
        d.addElement(.opening(door))
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w2, offset: 2000, width: 1200, height: 1400, sill: 900)))
        d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)], thickness: 250)))
        d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)], name: "Living", number: "101")))
        d.addElement(.column(ColumnGeom(position: Vec2(3000, 2000))))
        d.addElement(.beam(BeamGeom(start: Vec2(0, 2000), end: Vec2(6000, 2000))))
        d.addElement(.stair(StairGeom(start: Vec2(500, 500))), level: 0)
        d.addElement(.component(ComponentGeom(category: "Plumbing", position: Vec2(1000, 3000))), level: 0)
        let chair = d.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(2000, 3000))), level: 0)
        d.elements[d.elementIndex(chair)!].props["IfcExportAs"] = "IfcFurniture.CHAIR"
        let basin = d.addElement(.component(ComponentGeom(category: "Bath fixtures", position: Vec2(2500, 3000))), level: 0)
        d.elements[d.elementIndex(basin)!].props["IfcExportAs"] = "IfcSanitaryTerminal.FANCYBASIN"
        d.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(4000, 3000))), level: 0)
        return d
    }

    func export(_ d: ArchiDocument, _ o: IFCExportOptions) -> String {
        IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d), options: o)
    }
    func lines(_ ifc: String, _ type: String) -> [String] { ifc.components(separatedBy: "\n").filter { $0.contains("=\(type)(") } }
    func errors(_ ifc: String) -> [String] { IFCValidator.validate(ifc).filter { $0.severity == .error }.map(\.description) }

    func testIFC2x3CoordinationViewExport() throws {
        let ifc = export(model(), IFCExportOptions(schema: .ifc2x3, modelView: .referenceView))
        XCTAssertTrue(ifc.contains("FILE_SCHEMA(('IFC2X3'))"))
        XCTAssertTrue(ifc.contains("ViewDefinition [CoordinationView_V2.0]"))
        XCTAssertEqual(errors(ifc), [])
        for gone in ["IFCDOORTYPE", "IFCWINDOWTYPE", "IFCTRIANGULATEDFACESET", "IFCMAPCONVERSION", "IFCFURNITURE", "IFCSANITARYTERMINAL"] {
            XCTAssertTrue(lines(ifc, gone).isEmpty, gone)
        }
        XCTAssertEqual(lines(ifc, "IFCDOORSTYLE").count, 1)
        XCTAssertFalse(lines(ifc, "IFCPRESENTATIONSTYLEASSIGNMENT").isEmpty)
        XCTAssertEqual(lines(ifc, "IFCFLOWTERMINAL").count, 2, "plumbing + mapped basin")
        XCTAssertEqual(lines(ifc, "IFCFURNISHINGELEMENT").count, 2, "furniture + IfcFurniture chair")
        XCTAssertTrue(ifc.contains("IFCFACETEDBREP("), "IFC2x3 meshes are faceted B-reps")
        // IFC2x3 attribute layouts.
        let wall = try XCTUnwrap(lines(ifc, "IFCWALL").first)
        XCTAssertEqual(IFCSchemaConvert.parse(wall)?.args.count, 8)
        let door = try XCTUnwrap(lines(ifc, "IFCDOOR").first)
        XCTAssertEqual(IFCSchemaConvert.parse(door)?.args.count, 10)
        let space = try XCTUnwrap(lines(ifc, "IFCSPACE").first)
        XCTAssertEqual(IFCSchemaConvert.parse(space)?.args[9], ".INTERNAL.")
        XCTAssertTrue(lines(ifc, "IFCQUANTITYLENGTH").allSatisfy { IFCSchemaConvert.parse($0)?.args.count == 4 })
        // Readable back: native walls, openings and spaces.
        let back = try IFCImporter.importFile(ifc)
        XCTAssertEqual(back.doc.elements.filter { $0.typeName == "wall" }.count, 2)
        XCTAssertEqual(back.doc.elements.filter { $0.typeName == "door" }.count, 1)
        XCTAssertEqual(back.doc.elements.filter { $0.typeName == "window" }.count, 1)
        XCTAssertEqual(back.doc.elements.filter { $0.typeName == "space" }.count, 1)
    }

    func testReferenceViewIsTessellatedAndDTVUsesBreps() throws {
        let d = model()
        let rv = export(d, IFCExportOptions(schema: .ifc4, modelView: .referenceView))
        XCTAssertEqual(errors(rv), [])
        XCTAssertFalse(lines(rv, "IFCTRIANGULATEDFACESET").isEmpty)
        XCTAssertTrue(lines(rv, "IFCFACETEDBREP").isEmpty)
        XCTAssertTrue(rv.contains("'Body','Tessellation'"))
        XCTAssertFalse(IFCValidator.validate(rv).contains { $0.code == "MVD-REFERENCEVIEW" })
        let dtv = export(d, IFCExportOptions(schema: .ifc4, modelView: .designTransferView))
        XCTAssertTrue(dtv.contains("DesignTransferView_V1.0"))
        XCTAssertFalse(lines(dtv, "IFCFACETEDBREP").isEmpty)
        XCTAssertTrue(lines(dtv, "IFCTRIANGULATEDFACESET").isEmpty)
        XCTAssertEqual(errors(dtv), [])
        // Both import back with the same element counts (meshes as meshes).
        let a = try IFCImporter.importFile(rv).doc, b = try IFCImporter.importFile(dtv).doc
        XCTAssertEqual(a.elements.count, b.elements.count)
        let special: (BIMElement) -> Bool = { $0.typeName == "stair" || $0.typeName == "component" }
        let countA: Int = a.elements.filter(special).count + a.entities.count
        let countB: Int = b.elements.filter(special).count + b.entities.count
        XCTAssertEqual(countA, countB)
    }

    func testIFC4x3HeaderGeoreferenceAndLayouts() throws {
        let ifc = export(model(), IFCExportOptions(schema: .ifc4x3, modelView: .referenceView))
        XCTAssertTrue(ifc.contains("FILE_SCHEMA(('IFC4X3_ADD2'))"))
        XCTAssertEqual(errors(ifc), [])
        let pl = try XCTUnwrap(lines(ifc, "IFCCARTESIANPOINTLIST3D").first)
        XCTAssertEqual(IFCSchemaConvert.parse(pl)?.args.count, 2, "IFC4.3 point lists have a TagList")
        let mc = try XCTUnwrap(lines(ifc, "IFCMAPCONVERSION").first.flatMap(IFCSchemaConvert.parse))
        XCTAssertEqual(mc.args.count, 8)
        // Bucharest lies in UTM zone 35N: easting ≈ 428.6 km, northing ≈ 4 919 km.
        XCTAssertEqual(Double(mc.args[2]) ?? 0, 428_560, accuracy: 500)
        XCTAssertEqual(Double(mc.args[3]) ?? 0, 4_919_300, accuracy: 3_000)
        XCTAssertEqual(Double(mc.args[4]) ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(Double(mc.args[5]) ?? 0, cos(10 * .pi / 180), accuracy: 1e-6)
        XCTAssertTrue(ifc.contains("IFCPROJECTEDCRS('EPSG:32635'"))
        // Georeference round trip: the site location and north angle come back from IfcMapConversion.
        let back = try IFCImporter.importFile(ifc).doc
        XCTAssertEqual(back.info.latitude, 44.4268, accuracy: 1e-6)
        XCTAssertEqual(back.info.longitude, 26.1025, accuracy: 1e-6)
        XCTAssertEqual(back.info.northAngle, 10, accuracy: 1e-4)
        XCTAssertEqual(back.info.elevation, 80, accuracy: 1e-9)
        XCTAssertEqual(back.variable("GEOCRS"), "EPSG:32635")
        var d = model(); d.setVariable("IFCGEOREF", "0")
        XCTAssertTrue(lines(export(d, IFCExportOptions.from(d)), "IFCMAPCONVERSION").isEmpty)
        // A 4.3 file declaring a removed IFC4 entity is flagged.
        let bad = ifc.replacingOccurrences(of: "=IFCWALL(", with: "=IFCWALLSTANDARDCASE(")
        XCTAssertTrue(IFCValidator.validate(bad).contains { $0.code == "SCHEMA-ENTITY" })
    }

    func testClassMappingFromPropsTableAndDefaults() throws {
        var d = model()
        d.setVariable("IFCMAP:Furniture", "IfcFurniture.TABLE")
        let ifc = export(d, IFCExportOptions(schema: .ifc4, modelView: .referenceView))
        XCTAssertEqual(errors(ifc), [])
        let furn = lines(ifc, "IFCFURNITURE")
        XCTAssertEqual(furn.count, 2)
        XCTAssertTrue(furn.contains { $0.hasSuffix(".CHAIR.);") }, "IfcExportAs wins over the table")
        XCTAssertTrue(furn.contains { $0.hasSuffix(".TABLE.);") })
        let san = lines(ifc, "IFCSANITARYTERMINAL")
        XCTAssertEqual(san.count, 2, "Plumbing category default + IfcExportAs")
        XCTAssertTrue(san.contains { $0.contains("'FANCYBASIN'") && $0.hasSuffix(".USERDEFINED.);") }, "unknown predefined type → USERDEFINED + ObjectType")
        XCTAssertTrue(ifc.contains("'Pset_SanitaryTerminalTypeCommon'"))
        XCTAssertNil(IFCClassMap.parse("IfcWallOfDoom"))
        XCTAssertEqual(IFCClassMap.parse("sanitaryterminal/sink")?.description, "IfcSanitaryTerminal.SINK")
    }

    @MainActor func testIfcOptionsAndMapCommands() async {
        let ed = Editor()
        await ed.run("IFCOPTIONS IFC2X3 Y")
        XCTAssertEqual(IFCExportOptions.from(ed.doc).schema, .ifc2x3)
        XCTAssertEqual(IFCExportOptions.from(ed.doc).effectiveView, .coordinationView)
        await ed.run("IFCOPTIONS IFC4X3 D N N")
        let o = IFCExportOptions.from(ed.doc)
        XCTAssertEqual(o.schema, .ifc4x3); XCTAssertEqual(o.modelView, .designTransferView); XCTAssertFalse(o.quantities); XCTAssertFalse(o.georeference)
        await ed.run("IFCMAP Set Lighting IfcLightFixture.POINTSOURCE")
        XCTAssertEqual(ed.doc.variable("IFCMAP:LIGHTING"), "IfcLightFixture.POINTSOURCE")
        let out = await ed.run("IFCMAP Set Lighting IfcBogus")
        XCTAssertTrue(out.joined().contains("not a supported"), out.joined(separator: "\n"))
        await ed.run("IFCMAP Clear")
        XCTAssertNil(ed.doc.variable("IFCMAP:LIGHTING"))
        ed.undo()
        XCTAssertNotNil(ed.doc.variable("IFCMAP:LIGHTING"), "mapping edits are undoable")
    }
}
