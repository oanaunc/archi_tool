// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// glTF, PLY, OFF, AMF, point clouds, STEP, GeoJSON CRS, shapefiles, OSM, ASCII grids, XLSX, HP-GL, IfcZIP, DWG hook.
final class IOFormatsTests: XCTestCase {
    func tmpDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archi-fmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func boxDoc() -> ArchiDocument {
        var d = ArchiDocument()
        _ = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))))
        return d
    }
    func bounds(_ ents: [Entity]) -> BBox3 {
        var b = BBox3.empty
        for e in ents { if case .solid(let s) = e.geometry { for v in s.meshVertices { b.add(v) } } }
        return b
    }

    func testGLTFRoundTripGLBAndEmbedded() throws {
        let d = boxDoc()
        let glb = GLTFExporter.exportGLB(MeshBuilder.build(doc: d), materials: d.materials)
        let ents = try GLTFImporter.entities(glb)
        XCTAssertEqual(ents.count, 1)
        let b = bounds(ents)
        XCTAssertEqual(b.max.x - b.min.x, 1000, accuracy: 0.01)
        XCTAssertEqual(b.max.y - b.min.y, 2000, accuracy: 0.01)
        XCTAssertEqual(b.max.z - b.min.z, 3000, accuracy: 0.01)
        XCTAssertEqual(b.min.z, 0, accuracy: 0.01)
        // Hand-written .gltf: one triangle with a node translation, rotation (90° about Y) and a data-URI buffer.
        var bin = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] { var le = f.bitPattern.littleEndian; withUnsafeBytes(of: &le) { bin.append(contentsOf: $0) } }
        for i: UInt16 in [0, 1, 2] { var le = i.littleEndian; withUnsafeBytes(of: &le) { bin.append(contentsOf: $0) } }
        let json: [String: Any] = [
            "asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["name": "parent", "translation": [10, 0, 0], "children": [1]], ["name": "tri", "mesh": 0, "rotation": [0, sin(Double.pi / 4), 0, cos(Double.pi / 4)]]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "indices": 1, "material": 0]]]],
            "materials": [["name": "Red", "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1]]]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"], ["bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 36], ["buffer": 0, "byteOffset": 36, "byteLength": 6]],
            "buffers": [["byteLength": bin.count, "uri": "data:application/octet-stream;base64," + bin.base64EncodedString()]],
        ]
        let e2 = try GLTFImporter.entities(try JSONSerialization.data(withJSONObject: json), scale: 1)
        XCTAssertEqual(e2.count, 1)
        XCTAssertEqual(e2[0].props["material"], "Red")
        XCTAssertEqual(e2[0].color, .rgb(255, 0, 0))
        guard case .solid(let s) = e2[0].geometry else { return XCTFail() }
        // Vertex (1,0,0) rotated 90° about +Y → (0,0,-1), translated → (10,0,-1); Y-up → Z-up: (x, -z, y) = (10, 1, 0).
        XCTAssertTrue(s.meshVertices.contains { $0.distance(to: Vec3(10, 1, 0)) < 1e-6 }, "\(s.meshVertices)")
        XCTAssertTrue(s.meshVertices.contains { $0.distance(to: Vec3(10, 0, 1)) < 1e-6 })
        XCTAssertThrowsError(try GLTFImporter.entities(Data("{\"asset\":{\"version\":\"1.0\"}}".utf8)))
    }

    func testPLYAsciiBinaryAndExport() throws {
        let d = boxDoc()
        let text = PointCloud.exportPLY(MeshBuilder.build(doc: d), materials: d.materials)
        let ply = try PointCloud.parsePLY(Data(text.utf8))
        XCTAssertEqual(ply.faces.count, 12)
        let mesh = try XCTUnwrap(PointCloud.mesh(fromPLY: ply, scale: 1))
        XCTAssertEqual(bounds([mesh]).max.z, 3000, accuracy: 1e-3)
        // Binary little-endian point cloud with colours.
        var data = Data("ply\nformat binary_little_endian 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n".utf8)
        for (p, c) in [((1.5, 2.0, 3.0), (255, 0, 0)), ((4.0, 5.0, 6.25), (0, 128, 255))] as [((Float, Float, Float), (UInt8, UInt8, UInt8))] {
            for f in [p.0, p.1, p.2] { var le = f.bitPattern.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
            data.append(contentsOf: [c.0, c.1, c.2])
        }
        let b = try PointCloud.parsePLY(data)
        XCTAssertEqual(b.points.count, 2)
        XCTAssertEqual(b.points[1].p, Vec3(4, 5, 6.25))
        XCTAssertEqual(b.points[1].color?.2, 255)
        let ents = PointCloud.entities(b.points, options: PointCloudOptions(scale: 1000))
        XCTAssertEqual(ents.count, 2)
        XCTAssertEqual(ents[0].props["z"], "3000")
        XCTAssertEqual(ents[0].color, .rgb(255, 0, 0))
    }

    func testPointCloudTextAndDecimation() throws {
        let pts = PointCloud.parseText("3\n0 0 0 10 255 0 0\n1 0 0 11 0 255 0\n0.01 0 0 12 0 0 255\n")
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts[0].intensity, 10)
        XCTAssertEqual(pts[1].color?.1, 255)
        let xyz = PointCloud.parseText("# x y z r g b\n1,2,3,10,20,30\n4;5;6\n")
        XCTAssertEqual(xyz.count, 2); XCTAssertEqual(xyz[0].color?.2, 30); XCTAssertNil(xyz[1].color)
        // Voxel filter keeps one point per 100-unit cell; the budget samples evenly.
        let grid: [CloudPoint] = (0..<1000).map { (i: Int) -> CloudPoint in CloudPoint(Vec3(Double(i % 100) * 10, Double(i / 100) * 10, 0)) }
        XCTAssertEqual(PointCloud.decimate(grid, voxel: 100, maxPoints: 0).count, 10)
        XCTAssertEqual(PointCloud.decimate(grid, voxel: 0, maxPoints: 250).count, 250)
        XCTAssertEqual(PointCloud.decimate(grid, voxel: 0, maxPoints: 0).count, 1000)
    }

    func testOFFAndAMF() throws {
        let off = try PointCloud.off("OFF\n# cube face\n4 1 0\n0 0 0\n1 0 0\n1 1 0\n0 1 0\n4 0 1 2 3\n", scale: 10)
        guard case .solid(let s) = off.geometry else { return XCTFail() }
        XCTAssertEqual(s.meshTriangles.count, 6)
        XCTAssertEqual(s.meshVertices[2], Vec3(10, 10, 0))
        let amf = """
        <?xml version="1.0"?><amf unit="meter"><object id="1"><metadata type="name">Part</metadata><mesh><vertices>
        <vertex><coordinates><x>0</x><y>0</y><z>0</z></coordinates></vertex><vertex><coordinates><x>1</x><y>0</y><z>0</z></coordinates></vertex>
        <vertex><coordinates><x>0</x><y>1</y><z>0</z></coordinates></vertex></vertices><volume><triangle><v1>0</v1><v2>1</v2><v3>2</v3></triangle></volume></mesh></object></amf>
        """
        let ents = try PointCloud.amf(Data(amf.utf8), unitMM: 1)
        XCTAssertEqual(ents.count, 1); XCTAssertEqual(ents[0].props["name"], "Part")
        guard case .solid(let a) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(a.meshVertices[1].x, 1000)
        // Zipped AMF
        let z = ZipArchive.write([ZipArchive.Entry(name: "part.amf", data: Data(amf.utf8))], compress: true)
        XCTAssertEqual(try PointCloud.amf(z).count, 1)
    }

    func testSTEPExportImportRoundTrip() throws {
        let d = boxDoc()
        let text = STEPExporter.export(MeshBuilder.build(doc: d), materials: d.materials, name: "Box")
        XCTAssertTrue(text.contains("FILE_SCHEMA(('AUTOMOTIVE_DESIGN"))
        XCTAssertTrue(text.contains("FACETED_BREP("))
        XCTAssertTrue(text.contains("COLOUR_RGB("))
        let f = try STEPParser.parse(text)
        XCTAssertEqual(f.all("FACETED_BREP").count, 1)
        XCTAssertEqual(f.all("FACE").count, 12)
        XCTAssertEqual(f.all("CARTESIAN_POINT").count, 8 + 1) // welded box corners + origin
        let back = try STEPImporter.entities(text)
        XCTAssertEqual(back.count, 1)
        let b = bounds(back)
        XCTAssertEqual(b.max.y - b.min.y, 2000, accuracy: 1e-6)
        // Planar B-rep with an edge loop (square face in metres).
        let brep = """
        ISO-10303-21;HEADER;FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));ENDSEC;DATA;
        #1=(LENGTH_UNIT()NAMED_UNIT(*)SI_UNIT($,.METRE.));
        #2=CARTESIAN_POINT('',(0.,0.,0.));#3=CARTESIAN_POINT('',(1.,0.,0.));#4=CARTESIAN_POINT('',(1.,1.,0.));#5=CARTESIAN_POINT('',(0.,1.,0.));
        #6=VERTEX_POINT('',#2);#7=VERTEX_POINT('',#3);#8=VERTEX_POINT('',#4);#9=VERTEX_POINT('',#5);
        #10=EDGE_CURVE('',#6,#7,#30,.T.);#11=EDGE_CURVE('',#7,#8,#30,.T.);#12=EDGE_CURVE('',#8,#9,#30,.T.);#13=EDGE_CURVE('',#9,#6,#30,.T.);
        #30=LINE('',#2,#31);#31=VECTOR('',#32,1.);#32=DIRECTION('',(1.,0.,0.));
        #14=ORIENTED_EDGE('',*,*,#10,.T.);#15=ORIENTED_EDGE('',*,*,#11,.T.);#16=ORIENTED_EDGE('',*,*,#12,.T.);#17=ORIENTED_EDGE('',*,*,#13,.T.);
        #18=EDGE_LOOP('',(#14,#15,#16,#17));#19=FACE_OUTER_BOUND('',#18,.T.);
        #20=AXIS2_PLACEMENT_3D('',#2,#33,#32);#33=DIRECTION('',(0.,0.,1.));#21=PLANE('',#20);
        #22=ADVANCED_FACE('',(#19),#21,.T.);#23=OPEN_SHELL('',(#22));
        ENDSEC;END-ISO-10303-21;
        """
        let sq = try STEPImporter.entities(brep, unitMM: 1)
        guard case .solid(let s) = sq[0].geometry else { return XCTFail() }
        XCTAssertEqual(s.meshTriangles.count, 6)
        XCTAssertTrue(s.meshVertices.contains(Vec3(1000, 1000, 0)))
    }

    func testGeoCRSUTMAndGeoJSONCRS() throws {
        // Known point: Bucharest 44.4268 N, 26.1025 E → UTM 35N 428 561.49 E, 4 919 670.03 N (Krüger series reference).
        let utm = GeoCRS.utmZone(lon: 26.1025, lat: 44.4268)
        XCTAssertEqual(utm, .utm(zone: 35, north: true))
        let xy = utm.fromLonLat(26.1025, 44.4268)
        XCTAssertEqual(xy.x, 428_561.49, accuracy: 0.05)
        XCTAssertEqual(xy.y, 4_919_670.03, accuracy: 0.05)
        let back = utm.toLonLat(xy.x, xy.y)
        XCTAssertEqual(back.lon, 26.1025, accuracy: 1e-7); XCTAssertEqual(back.lat, 44.4268, accuracy: 1e-7)
        let wm = GeoCRS.webMercator.fromLonLat(26.1025, 44.4268)
        let wb = GeoCRS.webMercator.toLonLat(wm.x, wm.y)
        XCTAssertEqual(wb.lat, 44.4268, accuracy: 1e-9)
        XCTAssertEqual(GeoCRS.parse("urn:ogc:def:crs:EPSG::32735"), .utm(zone: 35, north: false))
        XCTAssertEqual(GeoCRS.parse("http://www.opengis.net/def/crs/OGC/1.3/CRS84"), .wgs84)
        XCTAssertEqual(GeoCRS.parse("EPSG:3857"), .webMercator)
        // GeoJSON export in UTM and import back through its crs member.
        var d = ArchiDocument()
        d.info.latitude = 44.4268; d.info.longitude = 26.1025
        _ = d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 5000)])))
        let text = GeoJSON.export(d, options: GeoJSONOptions(geographic: true, crs: .utm(zone: 35, north: true)))
        XCTAssertTrue(text.contains("EPSG::32635"))
        let ents = try GeoJSON.entities(text, doc: d)
        guard case .polyline(let pl) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(pl.vertices[1].p.x, 10000, accuracy: 5)
        XCTAssertEqual(pl.vertices[2].p.y, 5000, accuracy: 5)
    }

    func testShapefilePolylineZWithDBF() throws {
        // One PolyLineZ (type 13) record with 2 points at z = 250 m, local metres, and a dbf with ELEV.
        var shp = Data()
        func be(_ v: Int32) { var x = v.bigEndian; withUnsafeBytes(of: &x) { shp.append(contentsOf: $0) } }
        func le(_ v: Int32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { shp.append(contentsOf: $0) } }
        func dbl(_ v: Double) { var x = v.bitPattern.littleEndian; withUnsafeBytes(of: &x) { shp.append(contentsOf: $0) } }
        let content = 4 + 32 + 4 + 4 + 4 + 2 * 16 + 16 + 2 * 8
        be(9994); for _ in 0..<5 { be(0) }; be(Int32((100 + 8 + content) / 2)); le(1000); le(13)
        for v in [1000.0, 2000, 1010, 2000, 250, 250, 0, 0] { dbl(v) }
        be(1); be(Int32(content / 2))
        le(13); for v in [1000.0, 2000, 1010, 2000] { dbl(v) }; le(1); le(2); le(0)
        dbl(1000); dbl(2000); dbl(1010); dbl(2000)
        dbl(250); dbl(250); dbl(250); dbl(250)
        var dbf = Data([3, 124, 1, 1]); var n = UInt32(1).littleEndian; withUnsafeBytes(of: &n) { dbf.append(contentsOf: $0) }
        var hl = UInt16(32 + 32 + 1).littleEndian, rl = UInt16(1 + 8).littleEndian
        withUnsafeBytes(of: &hl) { dbf.append(contentsOf: $0) }; withUnsafeBytes(of: &rl) { dbf.append(contentsOf: $0) }
        dbf.append(Data(count: 20))
        var field = Data("ELEV".utf8); field.append(Data(count: 7)); field.append(UInt8(ascii: "N")); field.append(Data(count: 4)); field.append(8); field.append(0); field.append(Data(count: 14))
        dbf.append(field); dbf.append(0x0D); dbf.append(0x20); dbf.append(Data("   250.0".utf8))
        var o = GISImportOptions(); o.shift = Vec2(1000, 2000)
        let ents = try Shapefile.entities(shp: shp, dbf: dbf, prj: "PROJCS[\"Local\"]", doc: ArchiDocument(), options: o)
        XCTAssertEqual(ents.count, 1)
        guard case .polyline(let pl) = ents[0].geometry else { return XCTFail() }
        XCTAssertEqual(pl.vertices[1].p, Vec2(10000, 0))
        XCTAssertEqual(ents[0].props["ELEV"], "250.0")
        XCTAssertEqual(ents[0].props["elevation"], "250000")
        XCTAssertEqual(Shapefile.crs(fromPRJ: "PROJCS[\"WGS_1984_UTM_Zone_34N\",GEOGCS[\"GCS_WGS_1984\"]]"), .utm(zone: 34, north: true))
        XCTAssertEqual(Shapefile.crs(fromPRJ: "GEOGCS[\"GCS_WGS_1984\"]"), .wgs84)
    }

    func testOSMBuildingsAndGrid() throws {
        let osm = """
        <osm version="0.6"><node id="1" lat="44.4300" lon="26.1000"/><node id="2" lat="44.4300" lon="26.1002"/><node id="3" lat="44.4301" lon="26.1002"/>
        <node id="4" lat="44.4301" lon="26.1000"/><node id="5" lat="44.4302" lon="26.1003"/>
        <way id="10"><nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/><tag k="building" v="yes"/><tag k="building:levels" v="4"/><tag k="name" v="A"/></way>
        <way id="11"><nd ref="4"/><nd ref="5"/><tag k="highway" v="residential"/></way></osm>
        """
        var d = ArchiDocument(); d.info.latitude = 44.43; d.info.longitude = 26.10
        var o = GISImportOptions(); o.masses = true
        let ents = try OSMImporter.entities(Data(osm.utf8), doc: d, options: o)
        XCTAssertEqual(ents.filter { $0.layer == "OSM-BUILDINGS" }.count, 1)
        XCTAssertEqual(ents.filter { $0.layer == "OSM-ROADS" }.count, 1)
        let mass = try XCTUnwrap(ents.first { $0.layer == "OSM-MASSES" })
        guard case .solid(let s) = mass.geometry else { return XCTFail() }
        XCTAssertEqual(s.height, 12000, accuracy: 1e-6)
        let b = try XCTUnwrap(ents.first { $0.layer == "OSM-BUILDINGS" })
        guard case .polyline(let pl) = b.geometry else { return XCTFail() }
        XCTAssertTrue(pl.closed)
        XCTAssertEqual(pl.vertices[0].p.x, 0, accuracy: 1); XCTAssertEqual(pl.vertices[0].p.y, 0, accuracy: 1)
        let expectedX: Double = 0.0002 * Double.pi / 180 * 6_378_137 * cos(44.43 * Double.pi / 180) * 1000
        XCTAssertEqual(pl.vertices[1].p.x, expectedX, accuracy: 1)
        XCTAssertEqual(OSMImporter.height(["height": "30 ft"]) ?? 0, 9.144, accuracy: 1e-6)
        // ESRI ASCII grid → toposurface
        let asc = "ncols 3\nnrows 2\nxllcorner 500000\nyllcorner 4900000\ncellsize 10\nNODATA_value -9999\n1 2 3\n4 5 -9999\n"
        let g = try ElevationGrid.parse(asc)
        XCTAssertEqual(g.value(col: 2, row: 0), 3); XCTAssertNil(g.value(col: 2, row: 1))
        let pts = ElevationGrid.points(g, unitMM: 1)
        XCTAssertEqual(pts.count, 5)
        XCTAssertTrue(pts.contains(Vec3(5000, 15000, 1000)))  // top-left cell centre, z 1 m
        let topo = try ElevationGrid.topo(g, unitMM: 1)
        XCTAssertEqual(topo.props["topo"], "1")
        XCTAssertThrowsError(try ElevationGrid.parse("hello"))
    }

    func testXLSXRoundTripAndSchedules() throws {
        let sheets = [XLSX.Sheet(name: "Rooms", rows: [["Name", "Area"], ["Living & dining", "32.5"], ["Bed <1>", "12"]]), XLSX.Sheet(name: "Rooms", rows: [["x"]])]
        let data = XLSX.write(sheets)
        let back = try XLSX.read(data)
        XCTAssertEqual(back.map(\.name), ["Rooms", "Rooms 2"])
        XCTAssertEqual(back[0].rows[1], ["Living & dining", "32.5"])
        XCTAssertEqual(back[0].rows[2][0], "Bed <1>")
        XCTAssertEqual(XLSX.column(0), "A"); XCTAssertEqual(XLSX.column(27), "AB"); XCTAssertEqual(XLSX.columnIndex("AB12"), 27)
        var d = ArchiDocument()
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        _ = d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000), Vec2(0, 3000)], name: "Office", number: "1")))
        let wb = try XLSX.read(XLSX.schedules(d))
        XCTAssertTrue(wb.map(\.name).contains("Walls")); XCTAssertTrue(wb.map(\.name).contains("Areas by level"))
        let tables = XLSXTables.entities(back, unitMM: 1)
        XCTAssertEqual(tables.count, 2)
        guard case .table(let t) = tables[0].geometry else { return XCTFail() }
        XCTAssertEqual(t.cells.count, 3)
    }

    func testHPGLAndIFCZip() throws {
        var d = ArchiDocument()
        _ = d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0))
        let plt = HPGLExporter.export(entries, bounds: BBox2(min: .zero, max: Vec2(1000, 1000)), scale: 100)
        XCTAssertTrue(plt.hasPrefix("IN;"))
        XCTAssertTrue(plt.contains("PU0,0;PD400,0;"), plt)   // 1000 mm at 1:100 = 10 mm = 400 plotter units
        var bd = ArchiDocument()
        _ = bd.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let ifc = IFCExporter.export(doc: bd, meshes: [])
        let z = IFCZip.write(ifc, name: "m")
        XCTAssertEqual(try IFCZip.read(z), ifc)
        let dir = try tmpDir()
        let url = dir.appendingPathComponent("m.ifczip")
        try z.write(to: url)
        let (doc, _) = try FileImport.load(url)
        XCTAssertFalse(doc.elements.isEmpty)
    }

    func testDWGConverterHook() throws {
        #if os(Windows)
        throw XCTSkip("the stand-in converter is a Unix shell script; Windows uses the real .exe converters")
        #endif
        let dir = try tmpDir()
        // No converter → guidance.
        XCTAssertTrue(DWGConverter.guidance.contains("ODA File Converter"))
        XCTAssertNil(DWGConverter.tool(at: dir.appendingPathComponent("missing").path))
        // Arguments for both converter kinds.
        let oda = DWGConverter.Tool(kind: .oda, path: "/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter")
        let a = DWGConverter.arguments(oda, input: URL(fileURLWithPath: "/tmp/in/a.dwg"), outputDir: URL(fileURLWithPath: "/tmp/out"), toDWG: false)
        XCTAssertEqual(a.args, ["/tmp/in", "/tmp/out", "ACAD2018", "DXF", "0", "1", "a.dwg"])
        XCTAssertEqual(a.output.path, "/tmp/out/a.dxf")
        let lib = DWGConverter.Tool(kind: .libredwg, path: "/opt/homebrew/bin/dwg2dxf")
        let b = DWGConverter.arguments(lib, input: URL(fileURLWithPath: "/tmp/a.dxf"), outputDir: URL(fileURLWithPath: "/tmp/o"), toDWG: true)
        XCTAssertEqual(b.executable, "/opt/homebrew/bin/dxf2dwg")
        XCTAssertEqual(b.args, ["-y", "-o", "/tmp/o/a.dwg", "/tmp/a.dxf"])
        // A fake ODA converter (shell script) that writes a DXF: the whole pipeline runs through Process.
        var d = ArchiDocument(); _ = d.add(.line(LineGeom(.zero, Vec2(10, 0))))
        let dxfPath = dir.appendingPathComponent("payload.dxf")
        try DXFWriter.write(d).write(to: dxfPath, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("ODAFileConverter")
        try "#!/bin/sh\ncp \"\(dxfPath.path)\" \"$2/$(basename \"$7\" .dwg).dxf\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let dwg = dir.appendingPathComponent("drawing.dwg")
        try Data([0x41, 0x43, 0x31, 0x30]).write(to: dwg)
        let tool = try XCTUnwrap(DWGConverter.tool(at: script.path))
        XCTAssertEqual(tool.kind, .oda)
        XCTAssertEqual(DWGConverter.find(override: script.path), tool)
        let doc = try DWGConverter.read(dwg, converter: script.path)
        XCTAssertEqual(doc.entities.count, 1)
    }
}
