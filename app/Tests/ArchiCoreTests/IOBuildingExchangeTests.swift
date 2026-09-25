// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// gbXML, COBie, COLLADA and CityJSON.
final class IOBuildingExchangeTests: XCTestCase {
    func house() -> ArchiDocument {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)]
        var walls: [EntityID] = []
        for i in 0..<4 { walls.append(d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300)), material: "Brick")) }
        _ = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: walls[0], offset: 3000, width: 1200, height: 1200, sill: 900, mark: "W1")))
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: walls[2], offset: 2000, width: 900, height: 2100, typeName: "D90")))
        _ = d.addElement(.slab(SlabGeom(boundary: pts, thickness: 250)), material: "Concrete")
        _ = d.addElement(.roof(RoofGeom(boundary: pts, kind: .flat, thickness: 300, overhang: 0, baseOffset: 3000)), material: "Concrete")
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(150, 150), Vec2(5850, 150), Vec2(5850, 3850), Vec2(150, 3850)], name: "Living", number: "101")))
        _ = d.addElement(.component(ComponentGeom(category: "Furniture", position: Vec2(3000, 2000), family: "sofa")))
        return d
    }

    func testGBXMLExport() throws {
        let x = GBXMLExporter.export(house())
        let p = GBXMLCounter()
        let parser = XMLParser(data: Data(x.utf8)); parser.delegate = p
        XCTAssertTrue(parser.parse(), "well-formed XML")
        XCTAssertEqual(p.count["Space"], 1)
        XCTAssertEqual(p.surfaceTypes.filter { $0 == "ExteriorWall" }.count, 4)
        XCTAssertEqual(p.surfaceTypes.filter { $0 == "SlabOnGrade" }.count, 1)
        XCTAssertEqual(p.surfaceTypes.filter { $0 == "Roof" }.count, 1)
        XCTAssertEqual(p.count["Opening"], 2)
        XCTAssertGreaterThanOrEqual(p.count["Construction"] ?? 0, 3)
        XCTAssertTrue(x.contains("<U-value unit=\"WPerSquareMeterK\">1.3</U-value>"))
        XCTAssertTrue(x.contains("spaceIdRef=\"sp-"))
        // Exterior wall along y = 0 faces south (azimuth 180).
        XCTAssertTrue(x.contains("<Azimuth>180</Azimuth>"))
    }

    func testCOBieWorkbook() throws {
        let sheets = try XLSX.read(COBieExporter.export(house()))
        let names = sheets.map(\.name)
        for n in ["Contact", "Facility", "Floor", "Space", "Type", "Component", "Attribute"] { XCTAssertTrue(names.contains(n), n) }
        let comp = try XCTUnwrap(sheets.first { $0.name == "Component" })
        XCTAssertEqual(comp.rows.count, 4) // header + window + door + sofa
        XCTAssertEqual(comp.rows[0][0], "Name"); XCTAssertEqual(comp.rows[0][4], "Space")
        XCTAssertTrue(comp.rows.contains { $0.first == "W1" && $0[4] == "101" })
        XCTAssertTrue(comp.rows.contains { $0[3] == "sofa" && $0[4] == "101" })
        let type = try XCTUnwrap(sheets.first { $0.name == "Type" })
        XCTAssertTrue(type.rows.contains { $0.first == "D90" })
        let space = try XCTUnwrap(sheets.first { $0.name == "Space" })
        XCTAssertEqual(space.rows[1][0], "101")
        XCTAssertEqual(Double(space.rows[1][12]) ?? 0, 5.7 * 3.7, accuracy: 0.01)
    }

    func testColladaRoundTrip() throws {
        var d = ArchiDocument()
        _ = d.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 2000, 3000))))
        let dae = ColladaExporter.export(MeshBuilder.build(doc: d), materials: d.materials)
        XCTAssertTrue(dae.contains("<up_axis>Z_UP</up_axis>"))
        let ents = try ColladaImporter.entities(Data(dae.utf8))
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        var b = BBox3.empty; s.meshVertices.forEach { b.add($0) }
        XCTAssertEqual(b.max.z - b.min.z, 3000, accuracy: 1e-3)
        XCTAssertEqual(s.meshTriangles.count, 36)
        // Y-up file in centimetres with a polylist, a translate and a rotation.
        let y = """
        <?xml version="1.0"?><COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1"><asset><unit name="centimeter" meter="0.01"/><up_axis>Y_UP</up_axis></asset>
        <library_geometries><geometry id="q"><mesh><source id="q-p"><float_array id="q-pa" count="12">0 0 0 100 0 0 100 100 0 0 100 0</float_array>
        <technique_common><accessor source="#q-pa" count="4" stride="3"/></technique_common></source><vertices id="q-v"><input semantic="POSITION" source="#q-p"/></vertices>
        <polylist count="1"><input semantic="VERTEX" source="#q-v" offset="0"/><input semantic="NORMAL" source="#q-n" offset="1"/><vcount>4</vcount><p>0 0 1 0 2 0 3 0</p></polylist></mesh></geometry></library_geometries>
        <library_visual_scenes><visual_scene id="s"><node name="quad"><translate>0 0 50</translate><instance_geometry url="#q"/></node></visual_scene></library_visual_scenes><scene><instance_visual_scene url="#s"/></scene></COLLADA>
        """
        let q = try ColladaImporter.entities(Data(y.utf8), unitMM: 1)
        guard case .solid(let qs) = q[0].geometry else { return XCTFail() }
        XCTAssertEqual(qs.meshTriangles.count, 6)
        // (100,100,50) cm Y-up → (1000, -500, 1000) mm Z-up.
        XCTAssertTrue(qs.meshVertices.contains { $0.distance(to: Vec3(1000, -500, 1000)) < 1e-6 }, "\(qs.meshVertices)")
    }

    func testCityJSONImport() throws {
        let cj: [String: Any] = [
            "type": "CityJSON", "version": "1.1",
            "transform": ["scale": [0.001, 0.001, 0.001], "translate": [1000, 2000, 0]],
            "vertices": [[0, 0, 0], [10000, 0, 0], [10000, 10000, 0], [0, 10000, 0], [0, 0, 6000], [10000, 0, 6000], [10000, 10000, 6000], [0, 10000, 6000]],
            "CityObjects": ["b1": ["type": "Building", "attributes": ["measuredHeight": 6.0, "roofType": "flat"],
                                   "geometry": [["type": "Solid", "lod": "1", "boundaries": [[[[0, 3, 2, 1]], [[4, 5, 6, 7]], [[0, 1, 5, 4]], [[1, 2, 6, 5]], [[2, 3, 7, 6]], [[3, 0, 4, 7]]]]]]]],
        ]
        let ents = try CityJSONImporter.entities(try JSONSerialization.data(withJSONObject: cj), doc: ArchiDocument())
        XCTAssertEqual(ents.count, 1)
        XCTAssertEqual(ents[0].layer, "CITY-BUILDING")
        XCTAssertEqual(ents[0].props["roofType"], "flat")
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshTriangles.count, 36)
        var b = BBox3.empty; s.meshVertices.forEach { b.add($0) }
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6); XCTAssertEqual(b.max.x, 10000, accuracy: 1e-6); XCTAssertEqual(b.max.z, 6000, accuracy: 1e-6)
        // Closed, outward-facing: signed volume positive.
        var vol = 0.0
        var i = 0
        while i + 2 < s.meshTriangles.count { let a = s.meshVertices[s.meshTriangles[i]], bb = s.meshVertices[s.meshTriangles[i + 1]], c = s.meshVertices[s.meshTriangles[i + 2]]; vol += a.dot(bb.cross(c)) / 6; i += 3 }
        XCTAssertEqual(vol, 10000 * 10000 * 6000, accuracy: 1)
        XCTAssertThrowsError(try CityJSONImporter.entities(Data("{\"type\":\"FeatureCollection\"}".utf8), doc: ArchiDocument()))
    }
}

final class GBXMLCounter: NSObject, XMLParserDelegate {
    var count: [String: Int] = [:]
    var surfaceTypes: [String] = []
    func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        count[n, default: 0] += 1
        if n == "Surface", let t = a["surfaceType"] { surfaceTypes.append(t) }
    }
}

final class IOIDSTests: XCTestCase {
    func testIDSValidation() throws {
        var d = ArchiDocument()
        let w1 = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))), material: "Concrete", name: "North")
        _ = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000))), material: "Brick")
        d.elements[d.elementIndex(w1)!].props["FireRating"] = "EI60"
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w1, offset: 1000, width: 900, height: 2100)))
        let ifc = IFCExporter.export(doc: d, meshes: [])
        let ids = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ids xmlns="http://standards.buildingsmart.org/IDS" xmlns:xs="http://www.w3.org/2001/XMLSchema"><info><title>Test</title></info><specifications>
          <specification name="Walls have IsExternal" ifcVersion="IFC4"><applicability minOccurs="1" maxOccurs="unbounded"><entity><name><simpleValue>IFCWALL</simpleValue></name></entity></applicability>
            <requirements><property dataType="IFCBOOLEAN"><propertySet><simpleValue>Pset_WallCommon</simpleValue></propertySet><baseName><simpleValue>IsExternal</simpleValue></baseName></property></requirements></specification>
          <specification name="Walls have a fire rating" ifcVersion="IFC4"><applicability><entity><name><simpleValue>IFCWALL</simpleValue></name></entity></applicability>
            <requirements><property><propertySet><simpleValue>Archi_Properties</simpleValue></propertySet><baseName><simpleValue>FireRating</simpleValue></baseName>
              <value><xs:restriction base="xs:string"><xs:pattern value="EI[0-9]+"/></xs:restriction></value></property></requirements></specification>
          <specification name="Wall materials" ifcVersion="IFC4"><applicability><entity><name><simpleValue>IFCWALL</simpleValue></name></entity></applicability>
            <requirements><material><value><xs:restriction base="xs:string"><xs:enumeration value="Concrete"/><xs:enumeration value="Brick"/></xs:restriction></value></material></requirements></specification>
          <specification name="Doors are wide" ifcVersion="IFC4"><applicability><entity><name><simpleValue>IFCDOOR</simpleValue></name></entity></applicability>
            <requirements><attribute><name><simpleValue>OverallWidth</simpleValue></name><value><xs:restriction base="xs:double"><xs:minInclusive value="1000"/></xs:restriction></value></attribute></requirements></specification>
          <specification name="No proxies" ifcVersion="IFC4" minOccurs="0" maxOccurs="0"><applicability><entity><name><simpleValue>IFCBUILDINGELEMENTPROXY</simpleValue></name></entity></applicability><requirements/></specification>
        </specifications></ids>
        """
        let specs = try IDSValidator.parse(Data(ids.utf8))
        XCTAssertEqual(specs.count, 5)
        XCTAssertEqual(specs[1].requirements.first?.value.pattern, "EI[0-9]+")
        let r = try IDSValidator.validate(ids: specs, ifc: ifc)
        XCTAssertTrue(r[0].passed); XCTAssertEqual(r[0].applicable, 2)
        XCTAssertFalse(r[1].passed); XCTAssertEqual(r[1].failed.count, 1, "the Brick wall has no fire rating")
        XCTAssertTrue(r[2].passed, "\(r[2].failed)")
        XCTAssertFalse(r[3].passed, "900 mm door < 1000")
        XCTAssertTrue(r[4].passed)
        var v = IDSValue(); v.simple = "3.0"
        XCTAssertTrue(v.matches("3")); XCTAssertFalse(v.matches("3.1"))
    }
}
