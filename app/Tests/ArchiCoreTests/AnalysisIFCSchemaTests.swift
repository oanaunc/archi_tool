// Oanarina Archi Tool — GPL-3.0-or-later
// IFC schema conformance checks (ANL-041) against the full IFC2X3 / IFC4 / IFC4X3 tables, zoom-to elements, and the
// structural analysis exports (ANL-034: SAF and the IFC4 structural analysis view).
import XCTest
@testable import ArchiCore

final class AnalysisIFCSchemaTests: XCTestCase {
    func report(_ issues: [IFCValidationIssue]) -> String { issues.map(\.description).joined(separator: "\n") }

    func testSchemaTables() {
        let t = IFCSchemaTable.ifc4
        XCTAssertEqual(t.attributeCount("IFCWALL"), 9)
        XCTAssertEqual(t.attributeCount("IFCPROJECT"), 9)
        XCTAssertEqual(t.attributeCount("IFCDOOR"), 13)
        XCTAssertEqual(t.attributeNames("IFCROOT"), ["GlobalId", "OwnerHistory", "Name", "Description"])
        XCTAssertTrue(t.isAbstract("IfcBuildingElement"))
        XCTAssertTrue(t.isSubtype("IFCWALLSTANDARDCASE", of: "IfcProduct"))
        XCTAssertEqual(IFCSchemaTable.ifc2x3.attributeCount("IFCWALL"), 8)
        XCTAssertEqual(IFCSchemaTable.ifc2x3.attributeCount("IFCDOOR"), 10)
        XCTAssertFalse(IFCSchemaTable.ifc2x3.contains("IFCALIGNMENT"))
        XCTAssertTrue(IFCSchemaTable.ifc4x3.contains("IFCALIGNMENT"))
        XCTAssertEqual(IFCSchemaTable.forSchema("IFC4X3_ADD2")?.name, "IFC4X3_ADD2")
        XCTAssertEqual(IFCSchemaTable.forSchema("IFC2X3")?.name, "IFC2X3")
    }

    func testOwnExportsConformToTheirSchemas() {
        let d = IOIFCSchemaTests().model()
        for (schema, view) in [(IFCExportOptions.Schema.ifc4, IFCExportOptions.ModelView.referenceView), (.ifc4, .designTransferView),
                               (.ifc2x3, .referenceView), (.ifc4x3, .referenceView), (.ifc4x3, .designTransferView)] {
            let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d), options: IFCExportOptions(schema: schema, modelView: view))
            let issues = IFCValidator.validate(text).filter { $0.severity == .error }
            XCTAssertTrue(issues.isEmpty, "\(schema) \(view):\n" + report(issues))
        }
    }

    func testDetectsSchemaViolationsAndMapsThemToElements() throws {
        var d = IOIFCSchemaTests().model()
        d.info.name = "Check"
        var text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        // Break a wall: drop its PredefinedType → attribute count; make a door's OverallHeight a string.
        let f0 = try STEPParser.parse(text)
        let wall = try XCTUnwrap(f0.all("IFCWALL").first ?? f0.all("IFCWALLSTANDARDCASE").first)
        let door = try XCTUnwrap(f0.all("IFCDOOR").first)
        func line(_ id: Int) -> String { text.split(separator: "\n").first { $0.hasPrefix("#\(id)=") }.map(String.init) ?? "" }
        let wl = line(wall.id), dl = line(door.id)
        let brokenWall = wl.replacingOccurrences(of: ",.STANDARD.);", with: ");").replacingOccurrences(of: ",.NOTDEFINED.);", with: ");").replacingOccurrences(of: ",$);", with: ");")
        XCTAssertNotEqual(brokenWall, wl)
        text = text.replacingOccurrences(of: wl, with: brokenWall)
        var parts = dl.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        parts[8] = "'tall'"   // OverallHeight
        text = text.replacingOccurrences(of: dl, with: parts.joined(separator: ","))
        text = text.replacingOccurrences(of: "DATA;\n", with: "DATA;\n#999999=IFCBUILDINGELEMENT('0YvctVUKr0kugbFTf53O9L',$,$,$,$,$,$,$);\n#999998=IFCWALLTYPO($);\n")
        let issues = IFCValidator.validate(text)
        let codes = Set(issues.map(\.code))
        XCTAssertTrue(codes.contains("ATTRIBUTE-COUNT"), report(issues))
        XCTAssertTrue(codes.contains("ATTRIBUTE-TYPE"), report(issues))
        XCTAssertTrue(codes.contains("ABSTRACT-INSTANCE"), report(issues))
        XCTAssertTrue(codes.contains("SCHEMA-ENTITY"), report(issues))
        // Zoom-to: the broken wall and door issues lead to their elements.
        let f = try STEPParser.parse(text)
        let countIssue = try XCTUnwrap(issues.first { $0.code == "ATTRIBUTE-COUNT" })
        let els = IFCValidator.elements(for: countIssue, in: f, doc: d)
        XCTAssertEqual(els.count, 1)
        XCTAssertTrue(d.element(els[0]).map { if case .wall = $0.geometry { return true }; return false } ?? false)
        let typeIssue = try XCTUnwrap(issues.first { $0.code == "ATTRIBUTE-TYPE" })
        XCTAssertTrue(IFCValidator.elements(for: typeIssue, in: f, doc: d).contains { id in d.element(id).map { if case .opening = $0.geometry { return true }; return false } ?? false })
        // A geometry item leads to its product.
        let rep = try XCTUnwrap(f.all("IFCSHAPEREPRESENTATION").first)
        let viaGeometry = IFCValidator.elements(for: IFCValidationIssue(severity: .error, code: "X", message: "", instances: [rep.id]), in: f, doc: d)
        XCTAssertEqual(viaGeometry.count, 1)
    }

    func frame() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Frame"
        for p in [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)] { d.addElement(.column(ColumnGeom(position: p))) }
        d.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(6000, 0))))
        d.addElement(.beam(BeamGeom(start: Vec2(6000, 0), end: Vec2(6000, 4000))))
        d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)], thickness: 200)))
        return d
    }

    func testSAFExport() throws {
        let d = frame()
        let m = StructuralAnalysis.model(d)
        XCTAssertFalse(m.members.isEmpty)
        let sheets = StructuralExchange.safSheets(m, name: "Frame")
        let names = sheets.map(\.name)
        for n in ["Project", "StructuralMaterial", "StructuralCrossSection", "StructuralPointConnection", "StructuralCurveMember", "StructuralSurfaceMember",
                  "StructuralPointSupport", "StructuralLoadGroup", "StructuralLoadCase", "StructuralSurfaceAction"] { XCTAssertTrue(names.contains(n), n) }
        let members = try XCTUnwrap(sheets.first { $0.name == "StructuralCurveMember" })
        XCTAssertEqual(members.rows.count - 1, m.members.count)
        let points = try XCTUnwrap(sheets.first { $0.name == "StructuralPointConnection" })
        let pointNames = Set(points.rows.dropFirst().map { $0[0] })
        // Every member end and panel corner is a defined point connection.
        let begin = members.rows[0].firstIndex(of: "Begin node")!, end = members.rows[0].firstIndex(of: "End node")!
        for r in members.rows.dropFirst() { XCTAssertTrue(pointNames.contains(r[begin]) && pointNames.contains(r[end])) }
        let surf = try XCTUnwrap(sheets.first { $0.name == "StructuralSurfaceMember" })
        let nodesCol = surf.rows[0].firstIndex(of: "Nodes")!
        for r in surf.rows.dropFirst() { for n in r[nodesCol].split(separator: ";") { XCTAssertTrue(pointNames.contains(String(n)), String(n)) } }
        let sup = try XCTUnwrap(sheets.first { $0.name == "StructuralPointSupport" })
        XCTAssertEqual(sup.rows.count - 1, 4, "four column bases")
        XCTAssertEqual(sup.rows[1][1], "Fixed")
        let loads = try XCTUnwrap(sheets.first { $0.name == "StructuralSurfaceAction" })
        XCTAssertEqual(loads.rows.count - 1, 2, "dead and live load on the slab")
        // Workbook round trip.
        let back = try XLSX.read(StructuralExchange.saf(m, name: "Frame"))
        XCTAssertEqual(back.first { $0.name == "StructuralCurveMember" }?.rows.count, members.rows.count)
    }

    func testIFCStructuralAnalysisView() throws {
        let d = frame()
        let m = StructuralAnalysis.model(d)
        let text = StructuralExchange.ifc(m, name: "Frame")
        let issues = IFCValidator.validate(text).filter { $0.severity == .error }
        XCTAssertTrue(issues.isEmpty, report(issues))
        let f = try STEPParser.parse(text)
        XCTAssertEqual(f.all("IFCSTRUCTURALANALYSISMODEL").count, 1)
        XCTAssertEqual(f.all("IFCSTRUCTURALCURVEMEMBER").count, m.members.count)
        XCTAssertEqual(f.all("IFCSTRUCTURALPOINTCONNECTION").count, m.nodes.count)
        XCTAssertEqual(f.all("IFCSTRUCTURALSURFACEMEMBER").count, m.panels.count)
        XCTAssertEqual(f.all("IFCBOUNDARYNODECONDITION").count, 4)
        XCTAssertEqual(f.all("IFCRELCONNECTSSTRUCTURALMEMBER").count, 2 * m.members.count)
        XCTAssertEqual(f.all("IFCSTRUCTURALLOADGROUP").count, 2)
        XCTAssertEqual(f.all("IFCSTRUCTURALPLANARACTION").count, 2)
        // The planar dead load is −1.5 kN/m² in N/m².
        let dead = try XCTUnwrap(f.all("IFCSTRUCTURALLOADPLANARFORCE").first { $0[0].string == "Dead" })
        XCTAssertEqual(dead[3].double ?? 0, -1500, accuracy: 1e-6)
        // Also valid as ifcXML.
        XCTAssertNoThrow(try IFCXML.fromSTEP(text))
    }

    @MainActor func testAnalyticalModelCommandWritesSAFAndIFC() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("anl-saf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ed = Editor()
        ed.doc = frame()
        let x = dir.appendingPathComponent("frame.xlsx").path, i = dir.appendingPathComponent("frame.ifc").path
        await ed.run("ANALYTICALMODEL 1.5 2 \(x)")
        await ed.run("ANALYTICALMODEL 1.5 2 \(i)")
        XCTAssertFalse(try XLSX.read(Data(contentsOf: URL(fileURLWithPath: x))).isEmpty)
        XCTAssertTrue(try String(contentsOfFile: i, encoding: .utf8).contains("IFCSTRUCTURALANALYSISMODEL"))
    }

    func testNormativeRulesAndStandardPropertySets() throws {
        XCTAssertNotNil(IFCPsetTable.ifc4.sets["Pset_WallCommon"]?.props["IsExternal"])
        XCTAssertEqual(IFCPsetTable.ifc4.sets["Pset_WallCommon"]?.props["IsExternal"]?.type, "IfcBoolean")
        XCTAssertEqual(IFCPsetTable.ifc4.sets["Pset_WallCommon"]?.applicable, ["IfcWall"])
        XCTAssertNotNil(IFCPsetTable.ifc4.sets["Qto_WallBaseQuantities"]?.props["Length"])
        XCTAssertNotNil(IFCPsetTable.ifc2x3.sets["Pset_WallCommon"])
        let d = IOIFCSchemaTests().model()
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        let clean = IFCValidator.validate(text)
        XCTAssertFalse(clean.contains { $0.severity == .error }, report(clean))
        XCTAssertFalse(clean.contains { $0.code.hasPrefix("PSET") || $0.code == "SPATIAL-STRUCTURE" || $0.code == "SHELL-NOT-CLOSED" || $0.code == "RESOURCE-UNUSED" }, report(clean))
        // Violations: a made-up Pset_ name, a wrong value type, an unknown property, an unused point, a loose storey.
        let f = try STEPParser.parse(text)
        let pset = try XCTUnwrap(f.all("IFCPROPERTYSET").first { $0[2].string == "Pset_WallCommon" })
        let psetLine = text.split(separator: "\n").first { $0.hasPrefix("#\(pset.id)=") }.map(String.init) ?? ""
        var bad = text.replacingOccurrences(of: psetLine, with: psetLine.replacingOccurrences(of: "'Pset_WallCommon'", with: "'Pset_WallCommonX'"))
        bad = bad.replacingOccurrences(of: "DATA;\n", with: "DATA;\n#999990=IFCCARTESIANPOINT((1.,2.,3.));\n#999991=IFCPROPERTYSINGLEVALUE('IsExternal',$,IFCLABEL('yes'),$);\n#999992=IFCPROPERTYSINGLEVALUE('Colour',$,IFCLABEL('red'),$);\n#999993=IFCPROPERTYSET('0YvctVUKr0kugbFTf53O9L',$,'Pset_DoorCommon',$,(#999991,#999992));\n#999994=IFCBUILDINGSTOREY('1YvctVUKr0kugbFTf53O9L',$,'Loose',$,$,$,$,$,.ELEMENT.,0.);\n")
        let issues = IFCValidator.validate(bad)
        let codes = Set(issues.map(\.code))
        for c in ["PSET-UNKNOWN", "PSET-PROPERTY", "PSET-VALUE-TYPE", "RESOURCE-UNUSED", "SPATIAL-STRUCTURE"] { XCTAssertTrue(codes.contains(c), c + "\n" + report(issues)) }
        // An open shell declared closed.
        let tri = "#999995=IFCCARTESIANPOINTLIST3D(((0.,0.,0.),(1.,0.,0.),(0.,1.,0.),(0.,0.,1.)));\n#999996=IFCTRIANGULATEDFACESET(#999995,$,.T.,((1,3,2),(1,2,4),(1,4,3)),$);\n"
        XCTAssertTrue(IFCValidator.validate(text.replacingOccurrences(of: "DATA;\n", with: "DATA;\n" + tri)).contains { $0.code == "SHELL-NOT-CLOSED" })
        let closedTri = tri.replacingOccurrences(of: "(1,4,3)),$", with: "(1,4,3),(2,3,4)),$")
        XCTAssertFalse(IFCValidator.validate(text.replacingOccurrences(of: "DATA;\n", with: "DATA;\n" + closedTri)).contains { $0.code == "SHELL-NOT-CLOSED" })
    }
}
