// Oanarina Archi Tool — GPL-3.0-or-later
// IFC import: material colours from surface styles, property sets (enumerated values) and quantities in props, spaces
// from B-rep bodies with their boundaries, curtain walls from plates and members, stairs as grouped meshes.
import XCTest
@testable import ArchiCore

final class IOIFCExtrasTests: XCTestCase {
    /// Triangulated box (metres) as #id…#id+3: face set, point list, shape representation, product shape.
    static func box(_ id: Int, _ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> (lines: [String], shape: Int) {
        let (x0, y0, z0) = a, (x1, y1, z1) = b
        let pts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        let p = pts.map { "(\($0.0),\($0.1),\($0.2))" }.joined(separator: ",")
        let t = "(1,3,2),(1,4,3),(5,6,7),(5,7,8),(1,2,6),(1,6,5),(2,3,7),(2,7,6),(3,4,8),(3,8,7),(4,1,5),(4,5,8)"
        return (["#\(id)=IFCTRIANGULATEDFACESET(#\(id + 1),$,.T.,(\(t)),$);", "#\(id + 1)=IFCCARTESIANPOINTLIST3D((\(p)));",
                 "#\(id + 2)=IFCSHAPEREPRESENTATION(#20,'Body','Tessellation',(#\(id)));", "#\(id + 3)=IFCPRODUCTDEFINITIONSHAPE($,$,(#\(id + 2)));"], id + 3)
    }

    static func file() -> String {
        var l: [String] = [
            "#1=IFCPROJECT('0YvctVUKr0kugbFTf53O9L',$,'Extras',$,$,$,$,(#20),#10);",
            "#10=IFCUNITASSIGNMENT((#11));", "#11=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);",
            "#20=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#21,$);", "#21=IFCAXIS2PLACEMENT3D(#22,$,$);", "#22=IFCCARTESIANPOINT((0.,0.,0.));",
            "#30=IFCBUILDINGSTOREY('1hOSvn6df7F8_7GcBWlRGQ',$,'Level 1',$,$,#31,$,$,.ELEMENT.,0.);", "#31=IFCLOCALPLACEMENT($,#21);",
            "#71=IFCLOCALPLACEMENT(#31,#21);",
            // Wall with material, colour, property set and quantities.
            "#40=IFCWALL('2O2Fr$t4X7Zf8NOew3FLOH',$,'W1',$,$,#41,#45,$,$);",
            "#41=IFCLOCALPLACEMENT(#31,#42);", "#42=IFCAXIS2PLACEMENT3D(#43,$,$);", "#43=IFCCARTESIANPOINT((0.,0.,0.));",
            "#45=IFCPRODUCTDEFINITIONSHAPE($,$,(#46));", "#46=IFCSHAPEREPRESENTATION(#20,'Body','SweptSolid',(#47));",
            "#47=IFCEXTRUDEDAREASOLID(#48,$,#50,3.);", "#48=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#49);", "#49=IFCPOLYLINE((#51,#52,#53,#54,#51));",
            "#50=IFCDIRECTION((0.,0.,1.));", "#51=IFCCARTESIANPOINT((0.,-0.1));", "#52=IFCCARTESIANPOINT((4.,-0.1));", "#53=IFCCARTESIANPOINT((4.,0.1));", "#54=IFCCARTESIANPOINT((0.,0.1));",
            "#100=IFCMATERIAL('Brick Red',$,$);", "#101=IFCRELASSOCIATESMATERIAL('3Mz6a7HAz3VRr5rUGH8t01',$,$,$,(#40),#100);",
            "#102=IFCMATERIALDEFINITIONREPRESENTATION($,$,(#103),#100);", "#103=IFCSTYLEDREPRESENTATION(#20,'Style','Material',(#104));",
            "#104=IFCSTYLEDITEM($,(#105),$);", "#105=IFCSURFACESTYLE('Brick',.BOTH.,(#106));",
            "#106=IFCSURFACESTYLERENDERING(#107,0.,$,$,$,$,$,$,.NOTDEFINED.);", "#107=IFCCOLOURRGB($,0.8,0.2,0.1);",
            "#110=IFCPROPERTYSET('3Mz6a7HAz3VRr5rUGH8t02',$,'Pset_WallCommon',$,(#111,#112));",
            "#111=IFCPROPERTYSINGLEVALUE('IsExternal',$,IFCBOOLEAN(.T.),$);",
            "#112=IFCPROPERTYENUMERATEDVALUE('Status',$,(IFCLABEL('NEW'),IFCLABEL('EXISTING')),$);",
            "#113=IFCRELDEFINESBYPROPERTIES('3Mz6a7HAz3VRr5rUGH8t03',$,$,$,(#40),#110);",
            "#114=IFCELEMENTQUANTITY('3Mz6a7HAz3VRr5rUGH8t04',$,'Qto_WallBaseQuantities',$,$,(#115,#116));",
            "#115=IFCQUANTITYLENGTH('Length',$,$,4.,$);", "#116=IFCQUANTITYAREA('NetSideArea',$,$,12.,$);",
            "#117=IFCRELDEFINESBYPROPERTIES('3Mz6a7HAz3VRr5rUGH8t05',$,$,$,(#40),#114);",
            // Space with a tessellated body; bounded by the wall.
            "#200=IFCSPACE('3Mz6a7HAz3VRr5rUGH8t06',$,'101',$,$,#71,#207,'Office',.ELEMENT.,.INTERNAL.,$);",
            "#210=IFCRELSPACEBOUNDARY('3Mz6a7HAz3VRr5rUGH8t07',$,$,$,#200,#40,$,.PHYSICAL.,.INTERNAL.);",
            // Curtain wall without a body: three mullions and two plates at y = 5 m.
            "#300=IFCCURTAINWALL('3Mz6a7HAz3VRr5rUGH8t08',$,'CW1',$,$,#71,$,$,$);",
            "#301=IFCRELAGGREGATES('3Mz6a7HAz3VRr5rUGH8t09',$,$,$,#300,(#310,#320,#330,#340,#350));",
            "#310=IFCMEMBER('3Mz6a7HAz3VRr5rUGH8t10',$,'M1',$,$,#71,#314,$,$);",
            "#320=IFCMEMBER('3Mz6a7HAz3VRr5rUGH8t11',$,'M2',$,$,#71,#324,$,$);",
            "#330=IFCMEMBER('3Mz6a7HAz3VRr5rUGH8t12',$,'M3',$,$,#71,#334,$,$);",
            "#340=IFCPLATE('3Mz6a7HAz3VRr5rUGH8t13',$,'P1',$,$,#71,#344,$,$);",
            "#350=IFCPLATE('3Mz6a7HAz3VRr5rUGH8t14',$,'P2',$,$,#71,#354,$,$);",
            // Stair without a body aggregating a flight.
            "#400=IFCSTAIR('3Mz6a7HAz3VRr5rUGH8t15',$,'Main stair',$,$,#71,$,$,$);",
            "#401=IFCRELAGGREGATES('3Mz6a7HAz3VRr5rUGH8t16',$,$,$,#400,(#410));",
            "#410=IFCSTAIRFLIGHT('3Mz6a7HAz3VRr5rUGH8t17',$,'Flight 1',$,$,#71,#414,$,$,$,$,$,$);",
            "#60=IFCRELCONTAINEDINSPATIALSTRUCTURE('3Mz6a7HAz3VRr5rUGH8t18',$,$,$,(#40,#200,#300,#400),#30);",
        ]
        l += box(204, (0, 0.1, 0), (4, 3.1, 2.5)).lines
        l += box(311, (-0.025, 5, 0), (0.025, 5.1, 3)).lines
        l += box(321, (1.975, 5, 0), (2.025, 5.1, 3)).lines
        l += box(331, (3.975, 5, 0), (4.025, 5.1, 3)).lines
        l += box(341, (0.025, 5.04, 0), (1.975, 5.06, 3)).lines
        l += box(351, (2.025, 5.04, 0), (3.975, 5.06, 3)).lines
        l += box(411, (0, 7, 0), (1, 10, 3)).lines
        return "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('x.ifc','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n" + l.joined(separator: "\n") + "\nENDSEC;\nEND-ISO-10303-21;\n"
    }

    func testIFCImportExtras() throws {
        let r = try IFCImporter.importFile(Self.file())
        let d = r.doc
        // Wall: material with its surface colour, property set values and quantities in props.
        let wall = try XCTUnwrap(d.elements.first { if case .wall = $0.geometry { return true }; return false })
        XCTAssertEqual(wall.material, "Brick Red")
        let mat = try XCTUnwrap(d.material("Brick Red"))
        XCTAssertEqual(mat.color.r, 0.8, accuracy: 1e-9); XCTAssertEqual(mat.color.g, 0.2, accuracy: 1e-9); XCTAssertEqual(mat.color.b, 0.1, accuracy: 1e-9)
        XCTAssertEqual(wall.props["Pset_WallCommon.IsExternal"], "true")
        XCTAssertEqual(wall.props["Pset_WallCommon.Status"], "NEW, EXISTING")
        XCTAssertEqual(wall.props["Qto_WallBaseQuantities.Length"], "4")
        XCTAssertEqual(wall.props["Qto_WallBaseQuantities.NetSideArea"], "12")
        // Space from a tessellated body: its footprint and height; bounded by the wall.
        let space = try XCTUnwrap(d.elements.first { if case .space = $0.geometry { return true }; return false })
        guard case .space(let sg) = space.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(sg.boundary)), 12e6, accuracy: 1)
        XCTAssertEqual(sg.height, 2500, accuracy: 1e-6)
        XCTAssertEqual(sg.name, "Office"); XCTAssertEqual(sg.number, "101")
        XCTAssertEqual(space.props["boundedBy"], "\(wall.id)")
        // Curtain wall along x at y ≈ 5.05 m with three mullions (2 m bays) and its parts consumed.
        let cw = try XCTUnwrap(d.elements.first { if case .curtainWall = $0.geometry { return true }; return false })
        guard case .curtainWall(let c) = cw.geometry else { return XCTFail() }
        XCTAssertEqual(c.length, 4050, accuracy: 1)
        XCTAssertEqual((c.start.y + c.end.y) / 2, 5050, accuracy: 1)
        XCTAssertEqual(c.height, 3000, accuracy: 1e-6)
        XCTAssertEqual(c.gridU, 2025, accuracy: 1)
        XCTAssertEqual(c.gridV, 3000, accuracy: 1)
        XCTAssertFalse(d.entities.contains { ($0.props["ifcType"] ?? "") == "IFCPLATE" || ($0.props["ifcType"] ?? "") == "IFCMEMBER" })
        // Stair flight as a mesh grouped under its stair.
        let flight = try XCTUnwrap(d.entities.first { $0.props["ifcType"] == "IFCSTAIRFLIGHT" })
        XCTAssertEqual(flight.layer, "IFC-Stair")
        XCTAssertEqual(flight.props["assemblyType"], "IFCSTAIR"); XCTAssertEqual(flight.props["assemblyName"], "Main stair")
        XCTAssertEqual(flight.props["assembly"], "3Mz6a7HAz3VRr5rUGH8t15")
        XCTAssertEqual(r.stats["curtainWall"], 1)
    }
}
