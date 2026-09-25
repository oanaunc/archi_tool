// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IOImportExportTests: XCTestCase {
    func close(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tol, file: file, line: line); XCTAssertEqual(a.y, b.y, accuracy: tol, file: file, line: line)
    }
    func tmp(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("archi-io-\(UUID().uuidString)-\(name)") }

    // MARK: STEP / IFC

    func testSTEPParserValues() throws {
        let f = try STEPParser.parse("ISO-10303-21;\nHEADER;FILE_SCHEMA(('IFC4'));ENDSEC;\nDATA;\n#1=IFCLABELTEST('It''s \\X2\\00E9\\X0\\',$,*,.T.,(1,2.5,-3.E-2),#7,IFCLABEL('x'));\n/* c */ #2=(A(1)B('b'));\nENDSEC;END-ISO-10303-21;")
        XCTAssertEqual(f.schema, "IFC4")
        let e = try XCTUnwrap(f.entities[1])
        XCTAssertEqual(e.type, "IFCLABELTEST")
        XCTAssertEqual(e[0].string, "It's é")
        XCTAssertTrue(e[1].isNull)
        XCTAssertEqual(e[3].enumValue, "T")
        XCTAssertEqual(e[4].list?.compactMap { $0.double }, [1, 2.5, -0.03])
        XCTAssertEqual(e[5].ref, 7)
        XCTAssertEqual(e[6].string, "x")
        XCTAssertEqual(f.entities[2]?.parts["B"]?.first?.string, "b")
        XCTAssertThrowsError(try STEPParser.parse("hello"))
    }

    func bimModel() -> (ArchiDocument, [String: EntityID]) {
        var d = ArchiDocument()
        var ids: [String: EntityID] = [:]
        ids["w1"] = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200, height: 3000)))
        ids["w2"] = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), thickness: 365, height: 2800, baseOffset: 100, wallType: "Exterior Brick 365")))
        ids["door"] = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: ids["w1"]!, offset: 1000, width: 900, height: 2100, flipHand: true)))
        ids["win"] = d.addElement(.opening(OpeningGeom(kind: .window, hostWall: ids["w2"]!, offset: 2000, width: 1200, height: 1400, sill: 900)))
        ids["slab"] = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], holes: [[Vec2(1000, 1000), Vec2(2000, 1000), Vec2(2000, 2000), Vec2(1000, 2000)]], thickness: 250)))
        ids["space"] = d.addElement(.space(SpaceGeom(boundary: [Vec2(100, 100), Vec2(4900, 100), Vec2(4900, 3900), Vec2(100, 3900)], name: "Living", number: "101", height: 2700)))
        ids["col"] = d.addElement(.column(ColumnGeom(position: Vec2(2500, 2000), width: 300, depth: 400, rotation: 0.5)))
        ids["round"] = d.addElement(.column(ColumnGeom(position: Vec2(4000, 3000), width: 350, round: true)))
        ids["beam"] = d.addElement(.beam(BeamGeom(start: Vec2(0, 2000), end: Vec2(5000, 2000), width: 200, depth: 400, topOffset: 3000)))
        ids["upper"] = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(3000, 0), thickness: 150, height: 2500)), level: 1)
        ids["comp"] = d.addElement(.component(ComponentGeom(position: Vec2(3000, 3000))))
        if let i = d.elementIndex(ids["w1"]!) { d.elements[i].name = "North wall"; d.elements[i].props["fireRating"] = "EI60" }
        return (d, ids)
    }

    func testIFCRoundTripWithOwnExporter() throws {
        let (d, ids) = bimModel()
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        let r = try IFCImporter.importFile(text)
        let b = r.doc
        XCTAssertEqual(r.schema, "IFC4")
        XCTAssertEqual(b.levels.map(\.name), d.levels.map(\.name))
        XCTAssertEqual(b.levels.map(\.elevation), [0, 3000])
        func imported(_ key: String) throws -> BIMElement {
            let guid = IFCExporter.guid("element:\(ids[key]!)")
            return try XCTUnwrap(b.elements.first { $0.props["ifcGuid"] == guid }, key)
        }
        // Walls
        let w1e = try imported("w1")
        guard case .wall(let w1) = w1e.geometry else { return XCTFail("w1 not a wall") }
        close(w1.centerStart, Vec2(0, 0)); close(w1.centerEnd, Vec2(5000, 0))
        XCTAssertEqual(w1.thickness, 200, accuracy: 1e-6); XCTAssertEqual(w1.height, 3000, accuracy: 1e-6)
        XCTAssertEqual(w1e.name, "North wall"); XCTAssertEqual(w1e.props["fireRating"], "EI60")
        let w2e = try imported("w2")
        guard case .wall(let w2) = w2e.geometry else { return XCTFail("w2") }
        close(w2.centerStart, Vec2(5000, 0)); close(w2.centerEnd, Vec2(5000, 4000))
        XCTAssertEqual(w2.thickness, 365, accuracy: 1e-6); XCTAssertEqual(w2.height, 2800, accuracy: 1e-6); XCTAssertEqual(w2.baseOffset, 100, accuracy: 1e-6)
        XCTAssertEqual(w2.wallType, "Exterior Brick 365")
        let up = try imported("upper")
        XCTAssertEqual(up.level, 1)
        guard case .wall(let uw) = up.geometry else { return XCTFail("upper") }
        XCTAssertEqual(uw.baseOffset, 0, accuracy: 1e-6); XCTAssertEqual(uw.thickness, 150, accuracy: 1e-6)
        // Openings
        guard case .opening(let door) = try imported("door").geometry, case .opening(let win) = try imported("win").geometry else { return XCTFail("openings") }
        XCTAssertEqual(door.kind, .door); XCTAssertEqual(door.hostWall, w1e.id)
        XCTAssertEqual(door.offset, 1000, accuracy: 1e-3); XCTAssertEqual(door.width, 900, accuracy: 1e-6); XCTAssertEqual(door.height, 2100, accuracy: 1e-6)
        XCTAssertEqual(door.sill, 0, accuracy: 1e-3); XCTAssertTrue(door.flipHand)
        XCTAssertEqual(win.kind, .window); XCTAssertEqual(win.hostWall, w2e.id)
        XCTAssertEqual(win.offset, 2000, accuracy: 1e-3); XCTAssertEqual(win.sill, 900, accuracy: 1e-3)
        XCTAssertEqual(win.width, 1200, accuracy: 1e-6); XCTAssertEqual(win.height, 1400, accuracy: 1e-6)
        // Slab, space, columns, beam
        guard case .slab(let s) = try imported("slab").geometry else { return XCTFail("slab") }
        XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), 20_000_000, accuracy: 1)
        XCTAssertEqual(s.holes.count, 1); XCTAssertEqual(s.thickness, 250, accuracy: 1e-6); XCTAssertEqual(s.topOffset, 0, accuracy: 1e-6)
        guard case .space(let sp) = try imported("space").geometry else { return XCTFail("space") }
        XCTAssertEqual(sp.name, "Living"); XCTAssertEqual(sp.number, "101"); XCTAssertEqual(sp.height, 2700, accuracy: 1e-6)
        XCTAssertEqual(abs(GeometryOps.signedArea(sp.boundary)), 4800 * 3800, accuracy: 1)
        guard case .column(let c) = try imported("col").geometry else { return XCTFail("col") }
        close(c.position, Vec2(2500, 2000)); XCTAssertEqual(c.width, 300, accuracy: 1e-6); XCTAssertEqual(c.depth, 400, accuracy: 1e-6)
        XCTAssertEqual(c.rotation, 0.5, accuracy: 1e-6); XCTAssertEqual(c.height, 3000, accuracy: 1e-6)
        guard case .column(let rc) = try imported("round").geometry else { return XCTFail("round") }
        XCTAssertTrue(rc.round); XCTAssertEqual(rc.width, 350, accuracy: 1e-6)
        guard case .beam(let bm) = try imported("beam").geometry else { return XCTFail("beam") }
        close(bm.start, Vec2(0, 2000)); close(bm.end, Vec2(5000, 2000))
        XCTAssertEqual(bm.width, 200, accuracy: 1e-6); XCTAssertEqual(bm.depth, 400, accuracy: 1e-6); XCTAssertEqual(bm.topOffset, 3000, accuracy: 1e-6)
        // Unsupported element → mesh solid
        let mesh = try XCTUnwrap(b.entities.first { $0.props["ifcType"] == "IFCFURNISHINGELEMENT" })
        guard case .solid(let so) = mesh.geometry else { return XCTFail("mesh") }
        XCTAssertEqual(so.kind, .mesh); XCTAssertGreaterThan(so.meshTriangles.count, 0)
        XCTAssertEqual(r.stats["wall"], 3); XCTAssertEqual(r.stats["door"], 1); XCTAssertEqual(r.stats["window"], 1)
        // GUIDs survive a second export.
        let again = IFCExporter.export(doc: b, meshes: MeshBuilder.build(doc: b))
        XCTAssertTrue(again.contains(IFCExporter.guid("element:\(ids["w1"]!)")))
        XCTAssertTrue(IFCExporter.isValidGuid(IFCExporter.guid("x")))
        XCTAssertFalse(IFCExporter.isValidGuid("not-a-guid"))
    }

    static let foreignIFC = """
    ISO-10303-21;
    HEADER;
    FILE_DESCRIPTION((''),'2;1');
    FILE_NAME('t.ifc','',(''),(''),'','','');
    FILE_SCHEMA(('IFC4'));
    ENDSEC;
    DATA;
    #1=IFCPROJECT('0YvctVUKr0kugbFTf53O9L',$,'Foreign',$,$,$,$,(#20),#10);
    #10=IFCUNITASSIGNMENT((#11));
    #11=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);
    #20=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#21,$);
    #21=IFCAXIS2PLACEMENT3D(#22,$,$);
    #22=IFCCARTESIANPOINT((0.,0.,0.));
    #30=IFCBUILDINGSTOREY('1hOSvn6df7F8_7GcBWlRGQ',$,'Level 1',$,$,#31,$,$,.ELEMENT.,3.);
    #31=IFCLOCALPLACEMENT($,#32);
    #32=IFCAXIS2PLACEMENT3D(#33,$,$);
    #33=IFCCARTESIANPOINT((0.,0.,3.));
    #40=IFCWALLSTANDARDCASE('2O2Fr$t4X7Zf8NOew3FLOH',$,'W1',$,$,#41,#45,$,$);
    #41=IFCLOCALPLACEMENT(#31,#42);
    #42=IFCAXIS2PLACEMENT3D(#43,$,#44);
    #43=IFCCARTESIANPOINT((1.,2.,0.));
    #44=IFCDIRECTION((0.,1.,0.));
    #45=IFCPRODUCTDEFINITIONSHAPE($,$,(#46));
    #46=IFCSHAPEREPRESENTATION(#20,'Body','SweptSolid',(#47));
    #47=IFCEXTRUDEDAREASOLID(#48,$,#50,2.5);
    #48=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,$,#49);
    #49=IFCPOLYLINE((#51,#52,#53,#54,#51));
    #50=IFCDIRECTION((0.,0.,1.));
    #51=IFCCARTESIANPOINT((0.,-0.1));
    #52=IFCCARTESIANPOINT((4.,-0.1));
    #53=IFCCARTESIANPOINT((4.,0.1));
    #54=IFCCARTESIANPOINT((0.,0.1));
    #60=IFCRELCONTAINEDINSPATIALSTRUCTURE('3Mz6a7HAz3VRr5rUGH8tHH',$,$,$,(#40,#70,#80),#30);
    #70=IFCFURNISHINGELEMENT('1kTvXnbbzCWw8lcMd1dR4o',$,'Table',$,$,#71,#72,$);
    #71=IFCLOCALPLACEMENT(#31,#21);
    #72=IFCPRODUCTDEFINITIONSHAPE($,$,(#73));
    #73=IFCSHAPEREPRESENTATION(#20,'Body','Tessellation',(#74));
    #74=IFCTRIANGULATEDFACESET(#75,$,.T.,((1,2,3),(1,3,4),(1,2,4),(2,3,4)),$);
    #75=IFCCARTESIANPOINTLIST3D(((0.,0.,0.),(1.,0.,0.),(0.,1.,0.),(0.,0.,1.)));
    #80=IFCBUILDINGELEMENTPROXY('0kTvXnbbzCWw8lcMd1dR4p',$,'Block',$,$,#71,#81,$,$);
    #81=IFCPRODUCTDEFINITIONSHAPE($,$,(#82));
    #82=IFCSHAPEREPRESENTATION(#20,'Body','MappedRepresentation',(#83));
    #83=IFCMAPPEDITEM(#84,#88);
    #84=IFCREPRESENTATIONMAP(#21,#85);
    #85=IFCSHAPEREPRESENTATION(#20,'Body','Brep',(#86));
    #86=IFCFACETEDBREP(#87);
    #87=IFCCLOSEDSHELL((#90,#91));
    #88=IFCCARTESIANTRANSFORMATIONOPERATOR3D($,$,#89,2.,$);
    #89=IFCCARTESIANPOINT((10.,0.,0.));
    #90=IFCFACE((#92));
    #91=IFCFACE((#93));
    #92=IFCFACEOUTERBOUND(#94,.T.);
    #93=IFCFACEOUTERBOUND(#95,.T.);
    #94=IFCPOLYLOOP((#96,#97,#98,#99));
    #95=IFCPOLYLOOP((#96,#99,#98));
    #96=IFCCARTESIANPOINT((0.,0.,0.));
    #97=IFCCARTESIANPOINT((1.,0.,0.));
    #98=IFCCARTESIANPOINT((1.,1.,0.));
    #99=IFCCARTESIANPOINT((0.,1.,0.));
    ENDSEC;
    END-ISO-10303-21;
    """

    func testIFCImportForeignFileInMetres() throws {
        let r = try IFCImporter.importFile(Self.foreignIFC)
        let d = r.doc
        XCTAssertEqual(d.info.name, "Foreign")
        XCTAssertEqual(d.levels.count, 1); XCTAssertEqual(d.levels[0].name, "Level 1"); XCTAssertEqual(d.levels[0].elevation, 3000, accuracy: 1e-6)
        guard let el = d.elements.first, case .wall(let w) = el.geometry else { return XCTFail("no wall") }
        close(w.centerStart, Vec2(1000, 2000)); close(w.centerEnd, Vec2(1000, 6000))
        XCTAssertEqual(w.thickness, 200, accuracy: 1e-6); XCTAssertEqual(w.height, 2500, accuracy: 1e-6); XCTAssertEqual(w.baseOffset, 0, accuracy: 1e-6)
        XCTAssertEqual(el.name, "W1"); XCTAssertEqual(el.level, 0)
        let table = try XCTUnwrap(d.entities.first { $0.props["name"] == "Table" })
        guard case .solid(let t) = table.geometry else { return XCTFail() }
        XCTAssertEqual(t.meshTriangles.count, 12)
        XCTAssertEqual(t.meshVertices.map(\.z).max() ?? 0, 4000, accuracy: 1e-6)
        let block = try XCTUnwrap(d.entities.first { $0.props["name"] == "Block" })
        guard case .solid(let bl) = block.geometry else { return XCTFail() }
        // Mapped item scaled ×2 and moved 10 m along X (then placed on the storey at z = 3 m).
        XCTAssertEqual(bl.meshVertices.map(\.x).min() ?? 0, 10_000, accuracy: 1e-6)
        XCTAssertEqual(bl.meshVertices.map(\.x).max() ?? 0, 12_000, accuracy: 1e-6)
        XCTAssertEqual(bl.meshTriangles.count, 9)
    }

    // MARK: SVG

    static let svg = """
    <?xml version="1.0"?>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="100mm" height="50mm" viewBox="0 0 100 50">
     <defs><rect width="1" height="1" stroke="black"/></defs>
     <g transform="translate(10,0)"><line x1="0" y1="0" x2="10" y2="0" stroke="#ff0000"/></g>
     <g inkscape:groupmode="layer" inkscape:label="Shapes" style="stroke:black;fill:none">
      <rect x="0" y="0" width="20" height="10"/>
      <circle cx="50" cy="25" r="5"/>
      <ellipse cx="50" cy="25" rx="10" ry="5"/>
      <polyline points="0,0 10,10 20,0"/>
      <polygon points="0,0 10,0 10,10"/>
     </g>
     <path d="M0,50 L10,50 A5,5 0 0 1 20,50 C20,40 30,40 30,50 Z" stroke="blue" fill="none"/>
     <path d="m 60 10 h 10 v 10 h -10 z" stroke="black"/>
     <text x="5" y="45" font-size="10" fill="#000">Hello<tspan x="5" y="57">World</tspan></text>
     <line x1="0" y1="0" x2="1" y2="1" stroke="none"/>
    </svg>
    """

    func testSVGImport() throws {
        let ents = try SVGImporter.entities(Self.svg)
        XCTAssertEqual(ents.count, 9)
        guard case .line(let l) = ents[0].geometry else { return XCTFail("line") }
        close(l.a, Vec2(10, 50)); close(l.b, Vec2(20, 50))
        XCTAssertEqual(ents[0].color, .rgb(255, 0, 0))
        XCTAssertEqual(ents[1].layer, "Shapes")
        guard case .polyline(let rect) = ents[1].geometry else { return XCTFail("rect") }
        XCTAssertTrue(rect.closed); XCTAssertEqual(rect.vertices.count, 4)
        XCTAssertEqual(abs(GeometryOps.signedArea(rect.vertices.map(\.p))), 200, accuracy: 1e-9)
        guard case .circle(let c) = ents[2].geometry else { return XCTFail("circle") }
        close(c.center, Vec2(50, 25)); XCTAssertEqual(c.radius, 5, accuracy: 1e-9)
        guard case .ellipse(let e) = ents[3].geometry else { return XCTFail("ellipse") }
        XCTAssertEqual(e.majorAxis.length, 10, accuracy: 1e-9); XCTAssertEqual(e.ratio, 0.5, accuracy: 1e-9)
        guard case .polyline(let pl) = ents[4].geometry, case .polyline(let pg) = ents[5].geometry else { return XCTFail("polys") }
        XCTAssertFalse(pl.closed); XCTAssertTrue(pg.closed)
        guard case .polyline(let path) = ents[6].geometry else { return XCTFail("path") }
        XCTAssertTrue(path.closed)
        close(path.vertices[0].p, Vec2(0, 0)); close(path.vertices[1].p, Vec2(10, 0)); close(path.vertices[2].p, Vec2(20, 0))
        XCTAssertEqual(path.vertices[1].bulge, -1, accuracy: 1e-9) // semicircle bulging up after the Y flip
        XCTAssertEqual(path.vertices.count, 19)
        guard case .polyline(let rel) = ents[7].geometry else { return XCTFail("relative path") }
        XCTAssertTrue(rel.closed); XCTAssertEqual(rel.vertices.count, 4)
        close(rel.vertices[2].p, Vec2(70, 30))
        guard case .text(let t) = ents[8].geometry else { return XCTFail("text") }
        XCTAssertEqual(t.content, "Hello\nWorld"); close(t.position, Vec2(5, 5)); XCTAssertEqual(t.height, 7.17, accuracy: 1e-9)
    }

    func testSVGRoundTripThroughExporter() throws {
        var d = ArchiDocument()
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        d.add(.circle(CircleGeom(Vec2(500, 500), 250)))
        d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)], closed: true)))
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0))
        let svg = SVGExporter.export(entries: entries, bounds: BBox2(min: Vec2(0, 0), max: Vec2(1000, 1000)), background: nil)
        var o = SVGImportOptions(); o.scale = 1
        let ents = try SVGImporter.entities(svg, options: o)
        XCTAssertEqual(ents.count, 3)
        var b = BBox2.empty
        for e in ents { b.add(GeometryOps.bounds(e.geometry, doc: nil)) }
        close(b.min, Vec2(0, 0), 1); close(b.max, Vec2(1000, 750), 1)
    }

    func testSVGPathTokenizerCompactArcFlags() {
        let pls = SVGImporter.pathPolylines("M0 0a5 5 0 0110 0", .identity, segments: 4)
        XCTAssertEqual(pls.count, 1)
        close(pls[0].vertices.last!.p, Vec2(10, 0))
        XCTAssertEqual(abs(pls[0].vertices[0].bulge), 1, accuracy: 1e-9)
        XCTAssertEqual(SVGImporter.parseColor("#0f0"), .rgb(0, 255, 0))
        XCTAssertEqual(SVGImporter.parseColor("rgb(10, 20, 30)"), .rgb(10, 20, 30))
        XCTAssertNil(SVGImporter.parseColor("none"))
        let t = SVGImporter.parseTransform("translate(10 20) scale(2)")
        close(t.apply(Vec2(1, 1)), Vec2(12, 22))
    }

    // MARK: Meshes and packages

    func boxGroups() -> [MeshGroup] {
        var d = ArchiDocument()
        d.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))))
        return MeshBuilder.build(doc: d)
    }

    func testOBJImportRoundTrip() throws {
        let g = boxGroups()
        let obj = OBJExporter.export(g, materials: Material.library).obj
        let ents = try MeshImporter.obj(obj)
        XCTAssertEqual(ents.count, 1)
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        var b = BBox3.empty; s.meshVertices.forEach { b.add($0) }
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6); XCTAssertEqual(b.max.x, 1000, accuracy: 1e-6)
        XCTAssertEqual(b.max.y, 2000, accuracy: 1e-6); XCTAssertEqual(b.max.z, 3000, accuracy: 1e-6)
        XCTAssertEqual(s.meshTriangles.count / 3, g[0].mesh.indices.count / 3)
        XCTAssertNotNil(ents[0].props["material"])
        // Negative indices, quads, groups
        let q = try MeshImporter.obj("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\no A\nf -4 -3 -2 -1\no B\nf 1/1/1 2/2/2 3/3/3\n", options: MeshImportOptions(scale: 1, yUp: false))
        XCTAssertEqual(q.count, 2); XCTAssertEqual(q[0].props["name"], "A")
        if case .solid(let a) = q[0].geometry { XCTAssertEqual(a.meshTriangles.count, 6) }
        XCTAssertThrowsError(try MeshImporter.obj("# nothing"))
    }

    func testSTLImportASCIIAndBinary() throws {
        let ascii = STLExporter.export(boxGroups(), name: "box")
        let a = try MeshImporter.stl(Data(ascii.utf8))
        guard case .solid(let s) = a[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshVertices.count, 8)   // welded box corners
        XCTAssertEqual(s.meshTriangles.count, 36)
        // Binary: one triangle.
        var d = Data(count: 80)
        d.append(contentsOf: [1, 0, 0, 0])
        func f(_ v: Float) { var x = v.bitPattern.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        for v: Float in [0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 10, 0] { f(v) }
        d.append(contentsOf: [0, 0])
        let b = try MeshImporter.stl(d)
        guard case .solid(let t) = b[0].geometry else { return XCTFail() }
        XCTAssertEqual(t.meshTriangles, [0, 1, 2]); XCTAssertEqual(t.meshVertices[1].x, 10, accuracy: 1e-6)
    }

    func testZipRoundTripAndAlignment() throws {
        let entries = [ZipArchive.Entry(name: "a.txt", data: Data(String(repeating: "hello ", count: 200).utf8)), ZipArchive.Entry(name: "dir/b.bin", data: Data([1, 2, 3]))]
        for compress in [false, true] {
            let z = ZipArchive.write(entries, compress: compress)
            let back = try ZipArchive.read(z)
            XCTAssertEqual(back.map(\.name), ["a.txt", "dir/b.bin"])
            XCTAssertEqual(back.map(\.data), entries.map(\.data))
        }
        XCTAssertEqual(ZipArchive.crc32(Data("123456789".utf8)), 0xCBF43926)
        let usdz = USDExporter.usdz(boxGroups(), materials: Material.library)
        let bytes = [UInt8](usdz)
        let nameLen = Int(bytes[26]) | Int(bytes[27]) << 8, extraLen = Int(bytes[28]) | Int(bytes[29]) << 8
        XCTAssertEqual((30 + nameLen + extraLen) % 64, 0)
        let files = try ZipArchive.read(usdz)
        XCTAssertEqual(files.first?.name, "model.usda")
        XCTAssertTrue(String(decoding: files[0].data, as: UTF8.self).hasPrefix("#usda 1.0"))
    }

    func test3MFRoundTrip() throws {
        let g = boxGroups()
        let data = ThreeMFExporter.export(g, materials: Material.library, name: "Box")
        let files = try ZipArchive.read(data)
        XCTAssertEqual(Set(files.map(\.name)), ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model"])
        let model = String(decoding: files.first { $0.name == "3D/3dmodel.model" }!.data, as: UTF8.self)
        XCTAssertTrue(model.contains("unit=\"millimeter\"")); XCTAssertTrue(model.contains("<basematerials"))
        let ents = try ThreeMFImporter.entities(data)
        XCTAssertEqual(ents.count, 1)
        guard case .solid(let s) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshVertices.count, 8); XCTAssertEqual(s.meshTriangles.count, 36)
        XCTAssertEqual(s.meshVertices.map(\.z).max() ?? 0, 3000, accuracy: 1e-6)
    }

    func testUSDAExport() {
        let s = USDExporter.usda(boxGroups(), materials: Material.library, metersPerUnit: 0.001, name: "My House")
        XCTAssertTrue(s.hasPrefix("#usda 1.0"))
        XCTAssertTrue(s.contains("metersPerUnit = 0.001")); XCTAssertTrue(s.contains("upAxis = \"Z\""))
        XCTAssertTrue(s.contains("defaultPrim = \"My_House\"")); XCTAssertTrue(s.contains("def Mesh"))
        XCTAssertTrue(s.contains("UsdPreviewSurface")); XCTAssertTrue(s.contains("rel material:binding = </My_House/Materials/"))
        XCTAssertEqual(s.components(separatedBy: "faceVertexCounts = [").count - 1, 1)
        // Balanced braces
        XCTAssertEqual(s.filter { $0 == "{" }.count, s.filter { $0 == "}" }.count)
    }

    // MARK: DXF

    func dxf(_ body: String) -> String { body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }

    func testDXFPaperSpaceImageAttdefMLeader() throws {
        let text = dxf("""
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        8
        0
        2
        TAG
        70
        2
        10
        0
        20
        0
        0
        ATTDEF
        8
        0
        10
        1
        20
        2
        40
        2.5
        1
        101
        3
        Room number
        2
        ROOMNO
        70
        0
        0
        ENDBLK
        8
        0
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0
        20
        0
        11
        10
        21
        0
        0
        LINE
        8
        0
        67
        1
        10
        0
        20
        0
        11
        100
        21
        0
        0
        VIEWPORT
        8
        0
        67
        1
        10
        150
        20
        100
        40
        200
        41
        100
        12
        5000
        22
        2500
        45
        10000
        69
        2
        0
        IMAGE
        8
        0
        10
        0
        20
        0
        11
        0.5
        21
        0
        12
        0
        22
        0.5
        13
        200
        23
        100
        340
        2A
        0
        MULTILEADER
        8
        0
        300
        CONTEXT_DATA{
        40
        1
        10
        60
        20
        50
        41
        3.5
        304
        Note text
        12
        60
        22
        52
        302
        LEADER{
        290
        1
        10
        50
        20
        50
        304
        LEADER_LINE{
        10
        0
        20
        0
        91
        0
        305
        }
        303
        }
        301
        }
        0
        ENDSEC
        0
        SECTION
        2
        OBJECTS
        0
        IMAGEDEF
        5
        2A
        1
        photo.png
        0
        ENDSEC
        0
        EOF
        """)
        let d = try DXFReader.read(text)
        let tag = try XCTUnwrap(d.blocks["TAG"])
        XCTAssertEqual(tag.entities.count, 1)
        XCTAssertEqual(tag.entities[0].props["attdef"], "ROOMNO"); XCTAssertEqual(tag.entities[0].props["default"], "101")
        XCTAssertEqual(tag.entities[0].props["prompt"], "Room number")
        XCTAssertEqual(d.layouts.count, 1); XCTAssertEqual(d.layouts[0].name, "Layout1")
        XCTAssertEqual(d.layouts[0].entities.count, 1)
        XCTAssertEqual(d.layouts[0].viewports.count, 1)
        XCTAssertEqual(d.layouts[0].viewports[0].scale, 100, accuracy: 1e-9)
        close(d.layouts[0].viewports[0].origin, Vec2(50, 50)); close(d.layouts[0].viewports[0].viewCenter, Vec2(5000, 2500))
        let img = d.entities.compactMap { if case .image(let i) = $0.geometry { return i }; return nil }
        XCTAssertEqual(img.first?.path, "photo.png"); close(img.first?.size ?? .zero, Vec2(100, 50))
        let lead = d.entities.compactMap { if case .leader(let l) = $0.geometry { return l }; return nil }
        XCTAssertEqual(lead.count, 1)
        XCTAssertEqual(lead.first?.text, "Note text"); XCTAssertEqual(lead.first?.points.count, 2)
        close(lead.first?.points.last ?? .zero, Vec2(50, 50)); XCTAssertEqual(lead.first?.textHeight ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(d.entities.filter { if case .line = $0.geometry { return true }; return false }.count, 1)
    }

    func testDXFR12ExportReadsBack() throws {
        var d = ArchiDocument()
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        d.add(.circle(CircleGeom(Vec2(500, 500), 250)), color: .rgb(255, 0, 0))
        d.add(.arc(ArcGeom(Vec2(0, 0), 300, 0, .pi / 2)))
        d.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 1), PolyVertex(Vec2(100, 0)), PolyVertex(Vec2(100, 100))], closed: true)))
        d.add(.ellipse(EllipseGeom(center: Vec2(2000, 0), majorAxis: Vec2(500, 0), ratio: 0.5)))
        d.add(.spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 0), Vec2(100, 200), Vec2(300, 200), Vec2(400, 0)])))
        d.add(.text(TextGeom(position: Vec2(10, 900), height: 200, content: "Line one\nLine two")))
        d.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(100, 0)), PolyVertex(Vec2(100, 100)), PolyVertex(Vec2(0, 100))]], pattern: "SOLID")))
        d.blocks["B"] = Block(name: "B", entities: [Entity(id: 900, geometry: .line(LineGeom(Vec2(0, 0), Vec2(1, 1))))])
        d.add(.insert(InsertGeom(block: "B", position: Vec2(5, 5), rotation: .pi / 2)))
        d.addElement(.wall(WallGeom(start: Vec2(0, -1000), end: Vec2(3000, -1000))))
        let out = DXFWriter.write(d, version: .r12)
        XCTAssertTrue(out.contains("AC1009"))
        for banned in ["LWPOLYLINE", "ELLIPSE", "SPLINE", "MTEXT", "HATCH", "AcDb"] { XCTAssertFalse(out.contains("\n\(banned)\n"), banned) }
        let back = try DXFReader.read(out)
        func count(_ t: String) -> Int { back.entities.filter { $0.typeName == t }.count }
        XCTAssertEqual(count("circle"), 1); XCTAssertEqual(count("arc"), 1); XCTAssertEqual(count("insert"), 1)
        XCTAssertEqual(Set(back.entities.compactMap { if case .text(let t) = $0.geometry { return t.content }; return nil }), ["Line one", "Line two"])
        XCTAssertNotNil(back.blocks["B"])
        let bulged = back.entities.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry, p.vertices.first?.bulge == 1 { return p }; return nil }
        XCTAssertEqual(bulged.count, 1)
        XCTAssertGreaterThanOrEqual(count("polyline"), 5) // polyline, ellipse, spline, 2 SOLID triangles, wall outline
        if case .circle = back.entities.first(where: { $0.typeName == "circle" })?.geometry {
            XCTAssertEqual(back.entities.first { $0.typeName == "circle" }?.color, .aci(1))
        }
    }

    // MARK: GeoJSON / points

    func testGeoJSONRoundTrip() throws {
        var d = ArchiDocument()
        d.info.latitude = 44.43; d.info.longitude = 26.10
        d.add(.point(Vec2(1000, 2000)), layer: "Survey")
        d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 5000)], closed: true)), layer: "Plot")
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(1_000_000, 0))), layer: "Road")
        d.add(.text(TextGeom(position: Vec2(500, 500), height: 250, content: "Tree")), layer: "Labels")
        for geo in [true, false] {
            let s = GeoJSON.export(d, options: GeoJSONOptions(geographic: geo))
            let ents = try GeoJSON.entities(s, doc: d, options: GeoJSONOptions(geographic: geo))
            XCTAssertEqual(ents.count, 4)
            let byLayer = Dictionary(uniqueKeysWithValues: ents.map { ($0.layer, $0) })
            guard case .point(let p) = byLayer["Survey"]?.geometry else { return XCTFail() }
            close(p, Vec2(1000, 2000), 2)
            guard case .polyline(let pl) = byLayer["Plot"]?.geometry else { return XCTFail() }
            XCTAssertTrue(pl.closed); XCTAssertEqual(abs(GeometryOps.signedArea(pl.vertices.map(\.p))), 25_000_000, accuracy: 25_000_000 * 1e-5)
            guard case .text(let t) = byLayer["Labels"]?.geometry else { return XCTFail() }
            XCTAssertEqual(t.content, "Tree"); XCTAssertEqual(t.height, 250, accuracy: 1e-6)
            guard case .polyline(let road) = byLayer["Road"]?.geometry else { return XCTFail() }
            close(road.vertices[1].p, Vec2(1_000_000, 0), 5)
        }
        // 1 km east at 44.43°N: longitude difference matches the local radius of the parallel.
        let ll = GeoJSON.toLonLat(Vec2(1_000_000, 0), origin: (44.43, 26.10), unitMM: 1)
        XCTAssertEqual(ll.lon - 26.10, deg(1000 / (6_378_137 * cos(rad(44.43)))), accuracy: 1e-12)
        XCTAssertEqual(ll.lon - 26.10, 0.01258, accuracy: 1e-5); XCTAssertEqual(ll.lat, 44.43, accuracy: 1e-12)
        // Auto-detect: coordinates outside lon/lat range are metres.
        let m = try GeoJSON.entities(#"{"type":"Feature","geometry":{"type":"Point","coordinates":[500,300]},"properties":{"name":"A"}}"#, doc: d)
        guard case .point(let mp) = m.first?.geometry else { return XCTFail() }
        close(mp, Vec2(500_000, 300_000)); XCTAssertEqual(m.first?.props["name"], "A")
    }

    func testPointTableImportExport() {
        let hdr = PointTable.importPoints("Name,X,Y,Z,Code\nP1,100.5,200,10,TREE\n\"P,2\",300,400,12.5,\nbad,row\n")
        XCTAssertEqual(hdr.entities.count, 2); XCTAssertEqual(hdr.skipped, 1)
        XCTAssertEqual(hdr.entities[0].props["name"], "P1"); XCTAssertEqual(hdr.entities[0].props["code"], "TREE"); XCTAssertEqual(hdr.entities[0].props["z"], "10")
        XCTAssertEqual(hdr.entities[1].props["name"], "P,2")
        if case .point(let p) = hdr.entities[0].geometry { close(p, Vec2(100.5, 200)) } else { XCTFail() }
        var o = PointImportOptions(); o.layout = "PNEZD"
        let pnezd = PointTable.importPoints("1 5000 3000 100 CP\n2 5010 3020 101 CP\n", options: o)
        if case .point(let p) = pnezd.entities[0].geometry { close(p, Vec2(3000, 5000)) } else { XCTFail() }
        let tsv = PointTable.importPoints("1.0\t2.0\t3.0\n4\t5\t6\n")
        XCTAssertEqual(tsv.entities.count, 2); XCTAssertEqual(tsv.entities[1].props["z"], "6")
        let auto = PointTable.importPoints("A;1;2;3\nB;4;5;6\n")
        XCTAssertEqual(auto.entities.first?.props["name"], "A")
        var d = ArchiDocument()
        for e in hdr.entities { d.add(e) }
        let csv = PointTable.exportPoints(d)
        let back = PointTable.importPoints(csv)
        XCTAssertEqual(back.entities.count, 2); XCTAssertEqual(back.entities[1].props["name"], "P,2")
    }

    // MARK: Merge / file import / commands

    func testDocumentMergeRemapsIDsAndHosts() {
        let (src, _) = bimModel()
        var dst = ArchiDocument()
        dst.add(.line(LineGeom(.zero, Vec2(1, 1))))
        dst.addElement(.wall(WallGeom(start: .zero, end: Vec2(1000, 0))))
        let r = DocumentMerge.merge(src, into: &dst, offset: Vec2(10000, 0))
        XCTAssertEqual(r.elementIDs.count, src.elements.count)
        XCTAssertEqual(Set(dst.allIDs).count, dst.allIDs.count)
        for el in dst.elements { if case .opening(let o) = el.geometry { XCTAssertTrue(r.elementIDs.contains(o.hostWall)) } }
        let moved = dst.elements.compactMap { el -> WallGeom? in if case .wall(let w) = el.geometry, r.elementIDs.contains(el.id) { return w }; return nil }
        XCTAssertEqual(moved.first?.start.x ?? 0, 10000, accuracy: 1e-9)
        XCTAssertEqual(dst.levels.count, 2)
    }

    func testFileImportAndExportByExtension() throws {
        let (src, _) = bimModel()
        let ifc = tmp("m.ifc")
        try IFCExporter.export(doc: src, meshes: MeshBuilder.build(doc: src)).write(to: ifc, atomically: true, encoding: .utf8)
        var d = ArchiDocument()
        let (r, summary) = try FileImport.importFile(ifc, into: &d)
        XCTAssertTrue(summary.contains("3 wall"))
        XCTAssertEqual(r.elementIDs.count, d.elements.count)
        for f in ["3mf", "usda", "usdz", "geojson", "dxf12", "points"] {
            let url = tmp("out.\(f)")
            XCTAssertTrue(try FileImport.export(d, to: url, format: f), f)
            XCTAssertGreaterThan((try Data(contentsOf: url)).count, 20, f)
        }
        XCTAssertFalse(try FileImport.export(d, to: tmp("x.pdf"), format: "pdf"))
        XCTAssertThrowsError(try FileImport.load(tmp("x.xyzzy")))
    }

    /// The bundled demo house survives IFC export → import with the same BIM content.
    func testIFCRoundTripDemoModel() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../assets/demo/Cedar House.archi").standardized
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("demo model not found") }
        let d = try ArchiFile.decode(data)
        let r = try IFCImporter.importFile(IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d)))
        func count(_ doc: ArchiDocument, _ t: String) -> Int { doc.elements.filter { $0.typeName == t }.count }
        let straightWalls = d.elements.filter { if case .wall(let w) = $0.geometry { return abs(w.bulge) < 1e-9 && w.length > 1e-6 }; return false }.count
        XCTAssertEqual(count(r.doc, "wall"), straightWalls, r.summary)
        XCTAssertEqual(count(r.doc, "door"), count(d, "door"), r.summary)
        XCTAssertEqual(count(r.doc, "window"), count(d, "window"), r.summary)
        XCTAssertEqual(count(r.doc, "slab"), count(d, "slab"), r.summary)
        XCTAssertEqual(count(r.doc, "space"), count(d, "space"), r.summary)
        XCTAssertEqual(r.doc.levels.count, d.levels.count)
        // Wall areas survive: takeoff totals match within 0.5 %.
        let a = QuantityTakeoff.compute(d).total("wall", "area"), b = QuantityTakeoff.compute(r.doc).total("wall", "area")
        XCTAssertEqual(b, a, accuracy: max(a * 0.005, 0.01))
        // The audit tools run on a real model.
        XCTAssertFalse(ModelChecker.check(d).contains { $0.severity == .error })
        let clashes = ClashDetector.detect(d)
        XCTAssertTrue(clashes.allSatisfy { d.element($0.a) != nil || d.element($0.b) != nil })
    }

    @MainActor
    func testIOCommandsRunHeadless() async throws {
        let reg = CommandRegistry()
        BuiltinCommands.registerAll(reg)
        // IOCommands are part of the built-ins: no other command may claim their names or aliases.
        let own = Set(IOCommands.all.map(\.name))
        var seen: [String: String] = [:]
        for c in reg.sorted where !own.contains(c.name) { for n in [c.name] + c.aliases { seen[n] = c.name } }
        for c in IOCommands.all {
            for n in [c.name] + c.aliases {
                XCTAssertNil(seen[n], "\(n) collides with \(seen[n] ?? "")")
                XCTAssertEqual(reg.lookup(n)?.name, c.name, "\(n) is not registered for \(c.name)")
            }
        }
        let ed = Editor(registry: reg)
        let svg = tmp("a.svg")
        try Self.svg.write(to: svg, atomically: true, encoding: .utf8)
        await ed.run("SVGIMPORT \(svg.path) 2 N")
        XCTAssertEqual(ed.doc.entities.count, 9)
        guard case .circle(let c) = ed.doc.entities.first(where: { $0.typeName == "circle" })?.geometry else { return XCTFail() }
        XCTAssertEqual(c.radius, 10, accuracy: 1e-9)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 0)
        let pts = tmp("p.csv")
        try "x,y,z\n1,2,3\n4,5,6\n".write(to: pts, atomically: true, encoding: .utf8)
        await ed.run("POINTSIMPORT \(pts.path) Auto N")
        XCTAssertEqual(ed.doc.entities.count, 2)
        let out = tmp("o.3mf")
        await ed.run("BOX 0,0 1000,1000 1000")
        await ed.run("EXPORT3MF \(out.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let r12 = tmp("o.dxf")
        await ed.run("DXFR12OUT \(r12.path)")
        XCTAssertTrue((try String(contentsOf: r12)).contains("AC1009"))
    }
}
