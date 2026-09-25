// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IOTests: XCTestCase {

    func sampleDoc() -> ArchiDocument {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "Furniture", color: RGBA(0.2, 0.6, 0.3), linetype: "Dashed", lineweight: 0.35))
        d.blocks["Chair"] = Block(name: "Chair", basePoint: Vec2(0, 0), entities: [
            Entity(id: 900, layer: "0", geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(450, 0), Vec2(450, 450), Vec2(0, 450)], closed: true))),
            Entity(id: 901, layer: "0", geometry: .circle(CircleGeom(Vec2(225, 225), 100))),
        ])
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))), layer: "0")
        d.add(.circle(CircleGeom(Vec2(500, 500), 250)), layer: "Furniture", color: .aci(1))
        d.add(.arc(ArcGeom(Vec2(0, 0), 300, 0, .pi / 2)), layer: "A-WALL")
        d.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 0), bulge: 1), PolyVertex(Vec2(100, 0)), PolyVertex(Vec2(100, 100))], closed: true)), layer: "A-WALL", color: .rgb(10, 20, 30))
        d.add(.text(TextGeom(position: Vec2(10, 10), height: 250, content: "Hello", rotation: 0.5, halign: .center, valign: .middle)), layer: "A-ANNO-TEXT")
        d.add(.text(TextGeom(position: Vec2(10, 900), height: 200, content: "Line one\nLine two")), layer: "A-ANNO-TEXT")
        d.add(.ellipse(EllipseGeom(center: Vec2(2000, 0), majorAxis: Vec2(500, 0), ratio: 0.5)), layer: "0")
        d.add(.spline(SplineGeom(degree: 3, controlPoints: [Vec2(0, 0), Vec2(100, 200), Vec2(300, 200), Vec2(400, 0)])), layer: "0")
        d.add(.hatch(HatchGeom(loops: [[PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(100, 0)), PolyVertex(Vec2(100, 100))]], pattern: "SOLID")), layer: "0")
        d.add(.point(Vec2(5, 5)), layer: "0")
        d.add(.insert(InsertGeom(block: "Chair", position: Vec2(3000, 3000), scale: Vec2(1, 1), rotation: .pi / 4)), layer: "Furniture")
        d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(500, -500)], rotation: 0)), layer: "A-ANNO-DIMS")
        return d
    }

    func bimDoc() -> ArchiDocument {
        var d = ArchiDocument()
        let w1 = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200, height: 3000)))
        let w2 = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), thickness: 365, height: 3000, wallType: "Exterior Brick 365")))
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w1, offset: 1000, width: 900, height: 2100)))
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w2, offset: 2000, width: 1200, height: 1400, sill: 900)))
        d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], holes: [[Vec2(1000, 1000), Vec2(2000, 1000), Vec2(2000, 2000), Vec2(1000, 2000)]], thickness: 250)))
        d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Living", number: "101")))
        d.addElement(.column(ColumnGeom(position: Vec2(2500, 2000))))
        d.addElement(.beam(BeamGeom(start: Vec2(0, 2000), end: Vec2(5000, 2000))))
        d.addElement(.stair(StairGeom(start: Vec2(500, 500))), level: 0)
        d.addElement(.component(ComponentGeom(position: Vec2(3000, 3000))), level: 1)
        return d
    }

    // MARK: .archi

    func testArchiFileRoundTrip() throws {
        var doc = sampleDoc()
        let b = bimDoc()
        doc.elements = b.elements
        doc.nextID = max(doc.nextID, b.nextID)
        doc.info.name = "Test «Ünicode» house"
        let data = try ArchiFile.encode(doc)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"app\" : \"Oanarina Archi Tool\""))
        XCTAssertTrue(text.contains("\"formatVersion\" : \(ArchiDocument.currentFormatVersion)"))
        let back = try ArchiFile.decode(data)
        XCTAssertEqual(back, doc)
        XCTAssertEqual(ArchiFile.fileExtension, "archi")
    }

    func testArchiFileRejectsNewerVersion() throws {
        let data = try ArchiFile.encode(ArchiDocument())
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["formatVersion"] = ArchiDocument.currentFormatVersion + 5
        let newer = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertThrowsError(try ArchiFile.decode(newer)) { err in
            guard case ArchiFile.FileError.newerVersion = err else { return XCTFail("wrong error \(err)") }
            XCTAssertTrue((err as? LocalizedError)?.errorDescription?.contains("newer version") ?? false)
        }
        XCTAssertThrowsError(try ArchiFile.decode(Data("{\"hello\":1}".utf8)))
        XCTAssertThrowsError(try ArchiFile.decode(Data("not json".utf8)))
    }

    // MARK: DXF

    func testDXFWriteReadRoundTrip() throws {
        let doc = sampleDoc()
        let dxf = DXFWriter.write(doc)
        XCTAssertTrue(dxf.contains("AC1015"))
        XCTAssertTrue(dxf.hasSuffix("EOF\n"))
        // Handles must be unique.
        let lines = dxf.components(separatedBy: "\n")
        var handles: [String] = []
        var i = 0
        while i + 1 < lines.count {
            let c = lines[i].trimmingCharacters(in: .whitespaces)
            if c == "5" || c == "105" { handles.append(lines[i + 1]) }
            i += 2
        }
        XCTAssertEqual(Set(handles).count, handles.count, "duplicate handles")

        let back = try DXFReader.read(dxf)
        XCTAssertEqual(back.entities.count, doc.entities.count)
        XCTAssertEqual(back.entities.map(\.typeName), doc.entities.map(\.typeName))
        XCTAssertEqual(back.entities.map { $0.layer.uppercased() }, doc.entities.map { $0.layer.uppercased() })
        for l in doc.layers { XCTAssertNotNil(back.layer(named: l.name), "layer \(l.name)") }
        XCTAssertEqual(back.layer(named: "Furniture")?.lineweight ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(back.layer(named: "Furniture")?.linetype.lowercased(), "dashed")
        XCTAssertNotNil(back.blocks["Chair"])
        XCTAssertEqual(back.blocks["Chair"]?.entities.count, 2)
        XCTAssertEqual(back.units, .millimeters)
        // Geometry fidelity
        if case .arc(let a) = back.entities[2].geometry {
            XCTAssertEqual(a.radius, 300, accuracy: 1e-9); XCTAssertEqual(a.end, .pi / 2, accuracy: 1e-9)
        } else { XCTFail("arc expected") }
        if case .polyline(let p) = back.entities[3].geometry {
            XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3); XCTAssertEqual(p.vertices[0].bulge, 1, accuracy: 1e-12)
        } else { XCTFail("polyline expected") }
        XCTAssertEqual(back.entities[3].color, .rgb(10, 20, 30))
        XCTAssertEqual(back.entities[1].color, .aci(1))
        if case .text(let t) = back.entities[4].geometry {
            XCTAssertEqual(t.content, "Hello"); XCTAssertEqual(t.halign, .center); XCTAssertEqual(t.valign, .middle)
            XCTAssertEqual(t.rotation, 0.5, accuracy: 1e-9); XCTAssertEqual(t.position.x, 10, accuracy: 1e-9)
        } else { XCTFail("text expected") }
        if case .text(let t) = back.entities[5].geometry { XCTAssertEqual(t.content, "Line one\nLine two") } else { XCTFail("mtext expected") }
        if case .insert(let ins) = back.entities[10].geometry {
            XCTAssertEqual(ins.block, "Chair"); XCTAssertEqual(ins.rotation, .pi / 4, accuracy: 1e-9)
        } else { XCTFail("insert expected") }
        if case .dimension(let dm) = back.entities[11].geometry {
            XCTAssertEqual(dm.kind, .linear)
            XCTAssertTrue(dm.points[0].isClose(Vec2(0, 0), tol: 1e-6)); XCTAssertTrue(dm.points[1].isClose(Vec2(1000, 0), tol: 1e-6))
            XCTAssertEqual(dm.points[2].y, -500, accuracy: 1e-6)
        } else { XCTFail("dimension expected") }
    }

    func testDXFWritesBIMElementsOnTheirLayers() throws {
        let doc = bimDoc()
        let dxf = DXFWriter.write(doc)
        let back = try DXFReader.read(dxf)
        XCTAssertTrue(back.entities.contains { $0.layer == "A-WALL" })
        XCTAssertTrue(back.entities.contains { $0.layer == "A-DOOR" })
        XCTAssertTrue(back.entities.allSatisfy { !$0.layer.isEmpty })
        // Component on level 1 is not part of the current (ground) level plan.
        let all = try DXFReader.read(DXFWriter.write(doc, levels: nil))
        XCTAssertGreaterThan(all.entities.count, back.entities.count)
    }

    func testDXFReadHandWritten() throws {
        let src = """
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        6
        0
        ENDSEC
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        0
        LAYER
        2
        Walls
        70
        4
        62
        -3
        6
        CONTINUOUS
        370
        50
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LWPOLYLINE
        8
        Walls
        90
        3
        70
        1
        10
        0.0
        20
        0.0
        42
        0.41421356
        10
        10.0
        20
        0.0
        10
        10.0
        20
        10.0
        0
        ARC
        8
        0
        62
        5
        10
        1.0
        20
        2.0
        40
        3.0
        50
        90.0
        51
        180.0
        0
        TEXT
        8
        Notes
        10
        1.0
        20
        1.0
        40
        2.5
        1
        Size %%c20 \\U+00E9t\\U+00E9
        50
        30
        0
        MTEXT
        8
        Notes
        10
        0
        20
        0
        40
        2
        71
        5
        1
        {\\fArial|b1;Bold}\\Pnext\\~line
        0
        FOOBAR
        8
        0
        0
        ARC
        8
        0
        10
        0
        20
        0
        40
        1
        50
        0
        51
        90
        230
        -1.0
        0
        ENDSEC
        0
        EOF
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let doc = try DXFReader.read(src)
        XCTAssertEqual(doc.units, .meters)
        let walls = try XCTUnwrap(doc.layer(named: "Walls"))
        XCTAssertFalse(walls.visible); XCTAssertTrue(walls.locked); XCTAssertEqual(walls.lineweight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(walls.color, aciColor(3))
        XCTAssertEqual(doc.entities.count, 5)
        guard case .polyline(let p) = doc.entities[0].geometry else { return XCTFail("polyline") }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3)
        XCTAssertEqual(p.vertices[0].bulge, 0.41421356, accuracy: 1e-12)
        XCTAssertEqual(p.vertices[2].p, Vec2(10, 10))
        guard case .arc(let a) = doc.entities[1].geometry else { return XCTFail("arc") }
        XCTAssertEqual(a.center, Vec2(1, 2)); XCTAssertEqual(a.radius, 3)
        XCTAssertEqual(a.start, .pi / 2, accuracy: 1e-12); XCTAssertEqual(a.end, .pi, accuracy: 1e-12)
        XCTAssertEqual(doc.entities[1].color, .aci(5))
        guard case .text(let t) = doc.entities[2].geometry else { return XCTFail("text") }
        XCTAssertEqual(t.content, "Size ⌀20 été"); XCTAssertEqual(t.rotation, rad(30), accuracy: 1e-12)
        XCTAssertEqual(doc.entities[2].layer, "Notes")
        guard case .text(let m) = doc.entities[3].geometry else { return XCTFail("mtext") }
        XCTAssertEqual(m.content, "Bold\nnext line"); XCTAssertEqual(m.halign, .center); XCTAssertEqual(m.valign, .middle)
        // Mirrored OCS arc (extrusion -Z): quarter arc in +X+Y becomes the -X+Y quadrant.
        guard case .arc(let mirrored) = doc.entities[4].geometry else { return XCTFail("ocs arc") }
        XCTAssertTrue(mirrored.midPoint.x < 0 && mirrored.midPoint.y > 0)
    }

    func testDXFHatchEdgesAndPolylineVertices() throws {
        let src = [
            "0", "SECTION", "2", "ENTITIES",
            "0", "HATCH", "8", "0", "2", "ANSI31", "70", "0", "71", "0", "91", "1",
            "92", "1", "93", "2",
            "72", "1", "10", "-1", "20", "0", "11", "1", "21", "0",
            "72", "2", "10", "0", "20", "0", "40", "1", "50", "0", "51", "180", "73", "1",
            "97", "0", "75", "0", "76", "1", "52", "45", "41", "2", "77", "0", "78", "0", "98", "0",
            "0", "POLYLINE", "8", "0", "66", "1", "70", "1",
            "0", "VERTEX", "8", "0", "10", "0", "20", "0",
            "0", "VERTEX", "8", "0", "10", "5", "20", "0", "42", "1",
            "0", "VERTEX", "8", "0", "10", "5", "20", "5",
            "0", "SEQEND",
            "0", "INSERT", "8", "0", "2", "B", "10", "1", "20", "2", "41", "2", "42", "2", "50", "90", "66", "1",
            "0", "ATTRIB", "8", "0", "2", "TAG", "1", "Value",
            "0", "SEQEND",
            "0", "ENDSEC", "0", "EOF",
        ].joined(separator: "\n")
        let doc = try DXFReader.read(src)
        XCTAssertEqual(doc.entities.count, 3)
        guard case .hatch(let h) = doc.entities[0].geometry else { return XCTFail("hatch") }
        XCTAssertEqual(h.pattern, "ANSI31"); XCTAssertEqual(h.loops.count, 1); XCTAssertEqual(h.loops[0].count, 2)
        XCTAssertEqual(h.loops[0][1].bulge, 1, accuracy: 1e-9)
        XCTAssertEqual(h.angle, .pi / 4, accuracy: 1e-9); XCTAssertEqual(h.scale, 2)
        guard case .polyline(let p) = doc.entities[1].geometry else { return XCTFail("polyline") }
        XCTAssertTrue(p.closed); XCTAssertEqual(p.vertices.count, 3); XCTAssertEqual(p.vertices[1].bulge, 1)
        guard case .insert(let ins) = doc.entities[2].geometry else { return XCTFail("insert") }
        XCTAssertEqual(ins.attributes["TAG"], "Value"); XCTAssertEqual(ins.scale, Vec2(2, 2)); XCTAssertEqual(ins.rotation, .pi / 2, accuracy: 1e-12)
    }

    func testDXFRejectsGarbage() {
        XCTAssertThrowsError(try DXFReader.read("hello world"))
        XCTAssertEqual(DXFReader.stripMText("A\\PB{\\H2.5;C}\\S1^2;"), "A\nBC1/2")
    }

    // MARK: IFC

    func testIFCExportStructure() {
        let doc = bimDoc()
        let ifc = IFCExporter.export(doc: doc, meshes: [])
        XCTAssertTrue(ifc.hasPrefix("ISO-10303-21;"))
        XCTAssertTrue(ifc.contains("FILE_SCHEMA(('IFC4'));"))
        XCTAssertTrue(ifc.hasSuffix("END-ISO-10303-21;\n"))
        func count(_ type: String) -> Int { ifc.components(separatedBy: "\n").filter { $0.contains("=\(type)(") }.count }
        XCTAssertEqual(count("IFCWALL"), 2)
        XCTAssertEqual(count("IFCDOOR"), 1)
        XCTAssertEqual(count("IFCWINDOW"), 1)
        XCTAssertEqual(count("IFCOPENINGELEMENT"), 2)
        XCTAssertEqual(count("IFCRELVOIDSELEMENT"), 2)
        XCTAssertEqual(count("IFCRELFILLSELEMENT"), 2)
        XCTAssertEqual(count("IFCSLAB"), 1)
        XCTAssertEqual(count("IFCARBITRARYPROFILEDEFWITHVOIDS"), 1)
        XCTAssertEqual(count("IFCSPACE"), 1)
        XCTAssertEqual(count("IFCCOLUMN"), 1)
        XCTAssertEqual(count("IFCBEAM"), 1)
        XCTAssertEqual(count("IFCSTAIR"), 1)
        XCTAssertEqual(count("IFCFURNISHINGELEMENT"), 1)
        XCTAssertEqual(count("IFCBUILDINGSTOREY"), doc.levels.count)
        XCTAssertEqual(count("IFCPROJECT"), 1)
        XCTAssertTrue(ifc.contains("IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.)"))
        XCTAssertTrue(ifc.contains("'Pset_WallCommon'"))
        XCTAssertTrue(ifc.contains("IFCMATERIALLAYERSET("))
        // Every referenced entity exists.
        var defined = Set<Int>()
        for l in ifc.components(separatedBy: "\n") where l.hasPrefix("#") {
            if let eq = l.firstIndex(of: "="), let n = Int(l[l.index(after: l.startIndex)..<eq]) { defined.insert(n) }
        }
        let refs = ifc.components(separatedBy: "\n").filter { $0.hasPrefix("#") }.flatMap { line -> [Int] in
            let body = line[(line.firstIndex(of: "=") ?? line.startIndex)...]
            var out: [Int] = []; var cur = ""; var inRef = false; var inStr = false
            for ch in body {
                if ch == "'" { inStr.toggle() }
                if inStr { continue }
                if ch == "#" { inRef = true; cur = ""; continue }
                if inRef, ch.isNumber { cur.append(ch); continue }
                if inRef { if let v = Int(cur) { out.append(v) }; inRef = false }
            }
            return out
        }
        for r in refs { XCTAssertTrue(defined.contains(r), "dangling #\(r)") }
    }

    func testIFCWithModelMeshes() {
        let doc = bimDoc()
        let meshes = MeshBuilder.build(doc: doc)
        let ifc = IFCExporter.export(doc: doc, meshes: meshes)
        XCTAssertEqual(ifc.components(separatedBy: "\n").filter { $0.contains("=IFCWALL(") }.count, 2)
        if meshes.contains(where: { m in doc.elements.contains { $0.id == m.id && $0.typeName == "stair" } }) {
            XCTAssertTrue(ifc.contains("IFCTRIANGULATEDFACESET("), "Reference View (default) writes tessellated meshes")
        }
        let glb = GLTFExporter.exportGLB(meshes, materials: doc.materials)
        XCTAssertEqual(Array(glb.prefix(4)), Array("glTF".utf8))
        XCTAssertFalse(OBJExporter.export(meshes, materials: doc.materials).obj.isEmpty)
    }

    func testIFCGuids() {
        let a = IFCExporter.guid("element:1"), b = IFCExporter.guid("element:2")
        XCTAssertEqual(a.count, 22); XCTAssertEqual(b.count, 22)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, IFCExporter.guid("element:1"))
        XCTAssertTrue("0123".contains(a.first!))
        // Known vector: all-zero bytes compress to 22 zeros.
        XCTAssertEqual(IFCExporter.compress([UInt8](repeating: 0, count: 16)), String(repeating: "0", count: 22))
        XCTAssertEqual(IFCExporter.compress([UInt8](repeating: 255, count: 16)), "3" + String(repeating: "$", count: 21))
    }

    // MARK: Meshes

    func cubeGroup(id: EntityID = 7, material: String = "Glass") -> MeshGroup {
        var m = Mesh()
        let p = [Vec3(0, 0, 0), Vec3(1000, 0, 0), Vec3(1000, 1000, 0), Vec3(0, 1000, 0), Vec3(0, 0, 1000), Vec3(1000, 0, 1000), Vec3(1000, 1000, 1000), Vec3(0, 1000, 1000)]
        m.addQuad(p[3], p[2], p[1], p[0]); m.addQuad(p[4], p[5], p[6], p[7])
        m.addQuad(p[0], p[1], p[5], p[4]); m.addQuad(p[1], p[2], p[6], p[5])
        m.addQuad(p[2], p[3], p[7], p[6]); m.addQuad(p[3], p[0], p[4], p[7])
        return MeshGroup(id: id, kind: "wall", material: material, mesh: m)
    }

    func testGLBHeader() throws {
        let data = GLTFExporter.exportGLB([cubeGroup()], materials: Material.library)
        XCTAssertGreaterThan(data.count, 20)
        let bytes = [UInt8](data)
        func u32(_ o: Int) -> UInt32 { UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24 }
        XCTAssertEqual(Array(bytes[0..<4]), Array("glTF".utf8))
        XCTAssertEqual(u32(4), 2)
        XCTAssertEqual(Int(u32(8)), data.count)
        let jsonLen = Int(u32(12))
        XCTAssertEqual(u32(16), 0x4E4F534A)
        XCTAssertEqual(jsonLen % 4, 0)
        let json = try JSONSerialization.jsonObject(with: Data(bytes[20..<(20 + jsonLen)])) as! [String: Any]
        XCTAssertEqual((json["asset"] as? [String: Any])?["version"] as? String, "2.0")
        XCTAssertEqual((json["nodes"] as? [Any])?.count, 1)
        let mat = (json["materials"] as? [[String: Any]])?.first
        XCTAssertEqual(mat?["alphaMode"] as? String, "BLEND")
        XCTAssertEqual(u32(20 + jsonLen + 4), 0x004E4942)
        // Empty export is still a valid GLB.
        let empty = GLTFExporter.exportGLB([], materials: [])
        XCTAssertEqual(Array(empty.prefix(4)), Array("glTF".utf8))
    }

    func testOBJAndSTL() {
        let (obj, mtl) = OBJExporter.export([cubeGroup()], materials: Material.library)
        XCTAssertFalse(obj.contains("mtllib"))
        XCTAssertTrue(OBJExporter.export([cubeGroup()], materials: [], mtlFileName: "house.mtl").obj.contains("mtllib house.mtl"))
        XCTAssertEqual(obj.components(separatedBy: "\n").filter { $0.hasPrefix("f ") }.count, 12)
        XCTAssertTrue(obj.contains("usemtl Glass"))
        XCTAssertTrue(obj.contains("v 1 1 -1")) // (1000,1000,1000) mm Z-up → (1, 1, -1) m Y-up
        XCTAssertTrue(mtl.contains("newmtl Glass"))
        let stl = STLExporter.export([cubeGroup()], name: "cube")
        XCTAssertTrue(stl.hasPrefix("solid cube"))
        XCTAssertEqual(stl.components(separatedBy: "facet normal").count - 1, 12)
    }

    // MARK: SVG & CSV

    func testSVGExport() {
        let e = DrawEntry(id: 42, items: [
            .stroke(points: [Vec2(0, 0), Vec2(100, 0)], closed: false, style: StrokeStyle(color: .black, lineweight: 0.5, dash: [10, -5])),
            .fill(loops: [[Vec2(0, 0), Vec2(10, 0), Vec2(10, 10)]], color: RGBA(1, 0, 0)),
            .text(TextGeom(position: Vec2(0, 100), height: 10, content: "A&B"), font: "Helvetica", color: .black),
        ])
        let svg = SVGExporter.export(entries: [e], bounds: BBox2(min: Vec2(0, 0), max: Vec2(100, 100)), background: .white, pixelsPerUnit: 2)
        XCTAssertTrue(svg.contains("viewBox=\"0 0 200 200\""))
        XCTAssertTrue(svg.contains("data-id=\"42\""))
        XCTAssertTrue(svg.contains("M0 200L200 200")) // y flipped
        XCTAssertTrue(svg.contains("stroke-dasharray=\"20 10\""))
        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(svg.contains("A&amp;B"))
    }

    func testScheduleCSV() {
        let doc = bimDoc()
        let walls = ScheduleExporter.csv(doc: doc, kind: "walls").components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(walls.first, "id,type,length,height,thickness,area,volume,level,material")
        XCTAssertEqual(walls.count, 3)
        // 5 m × 3 m wall minus 0.9 × 2.1 door = 13.11 m²
        XCTAssertTrue(walls[1].contains(",13.11,"), walls[1])
        let doors = ScheduleExporter.csv(doc: doc, kind: "doors").components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(doors.first, "mark,width,height,sill,host wall,level")
        XCTAssertEqual(doors.count, 2)
        let rooms = ScheduleExporter.table(doc: doc, kind: "rooms")
        XCTAssertEqual(rooms[0], ["number", "name", "area", "perimeter", "level"])
        XCTAssertEqual(rooms[1][2], "20")
        XCTAssertEqual(rooms[1][3], "18000")
        let slabs = ScheduleExporter.table(doc: doc, kind: "slabs")
        XCTAssertEqual(slabs[1][1], "19")
        for k in ScheduleExporter.kinds { XCTAssertFalse(ScheduleExporter.csv(doc: doc, kind: k).isEmpty) }
        XCTAssertEqual(ScheduleExporter.escape("a,\"b\""), "\"a,\"\"b\"\"\"")
    }
}
