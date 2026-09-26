// Oanarina Archi Tool — GPL-3.0-or-later
// EXPRESS WHERE-rule checks of the IFC validator (ANL-041) and conformance of our own IFC2X3 / IFC4 / IFC4X3 exports.
import XCTest
@testable import ArchiCore

final class AnalysisIFCWhereRulesTests: XCTestCase {
    func report(_ issues: [IFCValidationIssue]) -> String { issues.map(\.description).joined(separator: "\n") }

    func testOwnExportsSatisfyWhereRules() throws {
        var docs = [IOIFCSchemaTests().model()]
        let url = IOInteropCorpusTests.repoRoot.appendingPathComponent("assets/demo/Nordic House.archi")
        if let data = try? Data(contentsOf: url), let d = try? ArchiFile.decode(data) { docs.append(d) }
        for d in docs {
            let meshes = MeshBuilder.build(doc: d)
            for schema in IFCExportOptions.Schema.allCases {
                for view in [IFCExportOptions.ModelView.referenceView, .designTransferView] {
                    let text = IFCExporter.export(doc: d, meshes: meshes, options: IFCExportOptions(schema: schema, modelView: view))
                    let wr = IFCValidator.validate(text).filter { $0.code.hasPrefix("WR-") && $0.severity == .error }
                    XCTAssertTrue(wr.isEmpty, "\(schema) \(view):\n" + report(wr))
                }
            }
        }
    }

    func testAgentToolValidatesEachSchemaWithZoomToElements() throws {
        let d = IOIFCSchemaTests().model()
        for sc in ["IFC2X3", "IFC4", "IFC4X3"] {
            let r = try XCTUnwrap(AgentTools.call("ifc_validate", ["schema": sc, "modelView": "DesignTransferView"], doc: d) as? [String: Any])
            XCTAssertEqual(r["valid"] as? Bool, true, "\(sc): \(r["issues"] ?? "")")
        }
        XCTAssertThrowsError(try AgentTools.call("ifc_validate", ["schema": "IFC9"], doc: d))
        let r = try XCTUnwrap(AgentTools.call("ifc_validate", [:], doc: d) as? [String: Any])
        for i in (r["issues"] as? [[String: Any]]) ?? [] { XCTAssertNotNil(i["elements"], "own-export issues carry zoom-to elements") }
    }

    static let broken = """
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION(('ViewDefinition [ReferenceView]'),'2;1');
    FILE_NAME('t.ifc','2026-01-01T00:00:00',(''),(''),'','','');
    FILE_SCHEMA(('IFC4'));
    ENDSEC;
    DATA;
    #1=IFCPROJECT('2O2Fr$t4X7Zf8NOew3FLOH',$,$,$,$,$,$,(#20,#21),#30);
    #2=IFCSITE('2O2Fr$t4X7Zf8NOew3FLOI',$,'Site',$,$,#40,$,$,.ELEMENT.,$,$,$,$,$);
    #3=IFCRELAGGREGATES('2O2Fr$t4X7Zf8NOew3FLOJ',$,$,$,#1,(#2,#1));
    #10=IFCCARTESIANPOINT((0.,0.,0.));
    #11=IFCDIRECTION((0.,0.,1.));
    #12=IFCDIRECTION((0.,0.,2.));
    #13=IFCDIRECTION((0.,0.,0.));
    #14=IFCCARTESIANPOINT((0.,0.));
    #15=IFCAXIS2PLACEMENT3D(#10,#11,#12);
    #16=IFCAXIS2PLACEMENT3D(#14,#11,$);
    #20=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#15,$);
    #21=IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#20,$,.MODEL_VIEW.,$);
    #30=IFCUNITASSIGNMENT((#31,#32));
    #31=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);
    #32=IFCSIUNIT(*,.LENGTHUNIT.,$,.SQUARE_METRE.);
    #40=IFCLOCALPLACEMENT(#41,#15);
    #41=IFCLOCALPLACEMENT(#40,#16);
    #50=IFCRECTANGLEPROFILEDEF(.AREA.,$,$,0.,100.);
    #51=IFCEXTRUDEDAREASOLID(#50,#15,#52,-5.);
    #52=IFCDIRECTION((1.,0.,0.));
    #53=IFCSHAPEREPRESENTATION(#21,'Body','SweptSolid',(#54));
    #54=IFCTRIANGULATEDFACESET(#55,$,.T.,((1,2,9)),$);
    #55=IFCCARTESIANPOINTLIST3D(((0.,0.,0.),(1.,0.,0.),(0.,1.)));
    #56=IFCPOLYLINE((#10,#14));
    #60=IFCPROPERTYSET('2O2Fr$t4X7Zf8NOew3FLOK',$,'Pset_Test',$,(#61,#62));
    #61=IFCPROPERTYSINGLEVALUE('A',$,IFCLABEL('x'),$);
    #62=IFCPROPERTYSINGLEVALUE('A',$,IFCLABEL('y'),$);
    #63=IFCQUANTITYLENGTH('Length',$,$,-1.,$);
    ENDSEC;
    END-ISO-10303-21;
    """

    func testDetectsWhereRuleViolations() {
        let issues = IFCValidator.validate(Self.broken)
        let codes = Set(issues.map(\.code))
        for rule in ["IfcAxis2Placement3D.AxisToRefDirPosition", "IfcAxis2Placement3D.AxisAndRefDirProvision", "IfcAxis2Placement3D.LocationIs3D",
                     "IfcDirection.MagnitudeGreaterZero", "IfcRelAggregates.NoSelfReference", "IfcProject.HasName", "IfcProject.CorrectContext",
                     "IfcProject.NoDecomposition", "IfcSIUnit.WR1", "IfcUnitAssignment.WR01", "IfcLocalPlacement.Acyclic",
                     "IfcRectangleProfileDef.PositiveDims", "IfcExtrudedAreaSolid.PositiveDepth", "IfcExtrudedAreaSolid.ValidExtrusionDirection",
                     "IfcShapeRepresentation.CorrectItemsForType", "IfcTriangulatedFaceSet.CoordIndex", "IfcCartesianPointList3D.CoordList",
                     "IfcPolyline.SameDim", "IfcPropertySet.UniquePropertyNames", "IfcQuantityLength.WR21"] {
            XCTAssertTrue(codes.contains("WR-" + rule), "missing \(rule)\n" + report(issues))
        }
        let axis = issues.first { $0.code == "WR-IfcAxis2Placement3D.AxisToRefDirPosition" }
        XCTAssertEqual(axis?.instances, [15])
        XCTAssertEqual(issues.first { $0.code == "WR-IfcRelAggregates.NoSelfReference" }?.instances, [3])
    }

    func testValidFileHasNoWhereRuleIssues() {
        let ok = Self.broken
            .replacingOccurrences(of: "#1=IFCPROJECT('2O2Fr$t4X7Zf8NOew3FLOH',$,$,", with: "#1=IFCPROJECT('2O2Fr$t4X7Zf8NOew3FLOH',$,'P',")
        let issues = IFCValidator.validate(ok)
        XCTAssertFalse(issues.contains { $0.code == "WR-IfcProject.HasName" })
        XCTAssertTrue(issues.contains { $0.code == "WR-IfcProject.CorrectContext" })
    }
}
