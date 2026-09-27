// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class IOInteropTests: XCTestCase {
    func tmpDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-interop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    func wallDoc() -> (ArchiDocument, EntityID) {
        var d = ArchiDocument()
        var w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0), thickness: 300, height: 3000, wallType: "Exterior Brick 365")))
        if let i = d.elementIndex(w) { d.elements[i].props = ["Pset_WallCommon.FireRating": "EI 60", "Custom_Acoustics.Rw": "52", "note": "check"] }
        _ = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1500, width: 1000, height: 2000)))
        var op = OpeningGeom(kind: .window, hostWall: w, offset: 3500, width: 1200, height: 1200, sill: 900)
        op.typeName = "Casement 1200x1200"
        _ = d.addElement(.opening(op))
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], holes: [[Vec2(100, 100), Vec2(1100, 100), Vec2(1100, 1100), Vec2(100, 1100)]], thickness: 200)))
        w += 0
        return (d, w)
    }

    func testIFCPropertySetsQuantitiesAndTypes() throws {
        let (d, _) = wallDoc()
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        XCTAssertTrue(text.contains("FILE_SCHEMA(('IFC4'))"))
        XCTAssertTrue(text.contains("ReferenceView_V1.2"))
        XCTAssertTrue(text.contains("'Qto_WallBaseQuantities'")); XCTAssertTrue(text.contains("'Qto_SlabBaseQuantities'"))
        XCTAssertTrue(text.contains("IFCQUANTITYLENGTH('Length',$,$,5000.,$)"))
        XCTAssertTrue(text.contains("'Custom_Acoustics'")); XCTAssertTrue(text.contains("IFCPROPERTYSINGLEVALUE('Rw',$,IFCREAL(52.),$)"))
        XCTAssertTrue(text.contains("IFCPROPERTYSINGLEVALUE('FireRating',$,IFCLABEL('EI 60'),$)"))
        XCTAssertTrue(text.contains("IFCWALLTYPE(")); XCTAssertTrue(text.contains("IFCWINDOWTYPE(")); XCTAssertTrue(text.contains("IFCRELDEFINESBYTYPE("))
        // The FireRating belongs to Pset_WallCommon (one set, not two).
        XCTAssertEqual(text.components(separatedBy: "'Pset_WallCommon'").count - 1, 1)

        let r = try IFCImporter.importFile(text)
        let wall = try XCTUnwrap(r.doc.elements.first { if case .wall = $0.geometry { return true }; return false })
        XCTAssertEqual(wall.props["Pset_WallCommon.FireRating"], "EI 60")
        XCTAssertEqual(wall.props["Custom_Acoustics.Rw"].flatMap(Double.init) ?? 0, 52, accuracy: 1e-9)
        XCTAssertEqual(wall.props["note"], "check")
        XCTAssertEqual(Double(wall.props["Qto_WallBaseQuantities.Length"] ?? "") ?? 0, 5, accuracy: 1e-6)
        let net: Double = 5 * 3 - 1 * 2 - 1.2 * 1.2
        XCTAssertEqual(Double(wall.props["Qto_WallBaseQuantities.NetSideArea"] ?? "") ?? 0, net, accuracy: 1e-6)
        XCTAssertEqual(Double(wall.props["Qto_WallBaseQuantities.NetVolume"] ?? "") ?? 0, net * 0.3, accuracy: 1e-6)
        let slab = try XCTUnwrap(r.doc.elements.first { if case .slab = $0.geometry { return true }; return false })
        XCTAssertEqual(Double(slab.props["Qto_SlabBaseQuantities.NetArea"] ?? "") ?? 0, 19, accuracy: 1e-6)
        XCTAssertEqual(wall.props["ifcTypeClass"], "IFCWALLTYPE")
        if case .wall(let wg) = wall.geometry { XCTAssertEqual(wg.wallType, "Exterior Brick 365") }
        let win = try XCTUnwrap(r.doc.elements.first { if case .opening(let o) = $0.geometry { return o.kind == .window }; return false })
        if case .opening(let o) = win.geometry { XCTAssertEqual(o.typeName, "Casement 1200x1200") }
        XCTAssertNotNil(r.doc.openingType("Casement 1200x1200"))
        // Re-export does not duplicate the imported quantities as properties.
        let again = IFCExporter.export(doc: r.doc, meshes: MeshBuilder.build(doc: r.doc))
        XCTAssertFalse(again.contains("'Qto_WallBaseQuantities.Length'"))
        XCTAssertEqual(again.components(separatedBy: "'Qto_WallBaseQuantities'").count - 1, 1)
    }

    func testIFCSchemaAndViewOptions() {
        var (d, _) = wallDoc()
        let t43 = IFCExporter.export(doc: d, meshes: [], options: IFCExportOptions(schema: .ifc4x3, modelView: .designTransferView, quantities: false))
        XCTAssertTrue(t43.contains("FILE_SCHEMA(('IFC4X3_ADD2'))"))
        XCTAssertTrue(t43.contains("DesignTransferView_V1.0"))
        XCTAssertFalse(t43.contains("IFCELEMENTQUANTITY"))
        XCTAssertFalse(t43.contains("STANDARDCASE"))
        // Document variables drive the default export (IFCOPTIONS).
        d.setVariable("IFCSCHEMA", "IFC4X3"); d.setVariable("IFCQUANTITIES", "0")
        let t = IFCExporter.export(doc: d, meshes: [])
        XCTAssertTrue(t.contains("IFC4X3_ADD2")); XCTAssertFalse(t.contains("IFCELEMENTQUANTITY"))
        XCTAssertEqual(IFCExportOptions.parseSchema("ifc4.3"), .ifc4x3); XCTAssertEqual(IFCExportOptions.parseView("dtv"), .designTransferView)
        // The importer reads IFC4X3 files written this way.
        XCTAssertNoThrow(try IFCImporter.importFile(t43))
    }

    func testOBJImportWithMTLMaterialsAndTextures() throws {
        let dir = try tmpDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("tex"), withIntermediateDirectories: true)
        try Self.png.write(to: dir.appendingPathComponent("tex/brick.png"))
        let mtl = """
        # materials
        newmtl Brick Red
        Kd 0.8 0.2 0.1
        Ns 250
        map_Kd -s 2 2 1 tex/brick.png
        newmtl Glass
        Kd 0.6 0.8 0.9
        d 0.25
        newmtl Unused
        Kd 1 1 1
        """
        try mtl.write(to: dir.appendingPathComponent("model.mtl"), atomically: true, encoding: .utf8)
        let obj = "mtllib model.mtl\no wall\nv 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nusemtl Brick Red\nf 1 2 3 4\no pane\nusemtl Glass\nf 1 2 3\n"
        let url = dir.appendingPathComponent("model.obj")
        try obj.write(to: url, atomically: true, encoding: .utf8)
        let (d, summary) = try FileImport.load(url)
        XCTAssertTrue(summary.contains("2 materials"), summary)
        let brick = try XCTUnwrap(d.material("Brick Red"))
        XCTAssertEqual(brick.color.r, 0.8, accuracy: 1e-9); XCTAssertEqual(brick.color.g, 0.2, accuracy: 1e-9)
        XCTAssertEqual(brick.texture, dir.appendingPathComponent("tex/brick.png").standardizedFileURL.path)
        XCTAssertEqual(brick.textureScale, 500, accuracy: 1e-9)
        XCTAssertEqual(brick.roughness, 1 - sqrt(0.25), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.material("Glass")).transparency, 0.75, accuracy: 1e-9)
        XCTAssertNil(d.material("Unused"))
        XCTAssertEqual(Set(d.entities.compactMap { $0.props["material"] }), ["Brick Red", "Glass"])
        // Merged into a drawing, the materials come along.
        var host = ArchiDocument()
        try FileImport.importFile(url, into: &host)
        XCTAssertNotNil(host.material("Brick Red")?.texture)
    }

    func testGLBEmbedsTexturesAndUVs() throws {
        let dir = try tmpDir()
        let tex = dir.appendingPathComponent("wood.png")
        try Self.png.write(to: tex)
        var m = Material(name: "Oak", color: RGBA(0.6, 0.4, 0.2)); m.texture = tex.path; m.textureScale = 1000
        var mesh = Mesh()
        mesh.addPolygon([Vec3(0, 0, 0), Vec3(2000, 0, 0), Vec3(2000, 1000, 0), Vec3(0, 1000, 0)])
        let glb = GLTFExporter.exportGLB([MeshGroup(id: 1, kind: "slab", material: "Oak", mesh: mesh), MeshGroup(id: 2, kind: "slab", material: "Plain", mesh: mesh)],
                                         materials: [m, Material(name: "Plain", color: RGBA(1, 1, 1))], unitMM: 1)
        let jsonLen = Int(glb[12]) | Int(glb[13]) << 8 | Int(glb[14]) << 16 | Int(glb[15]) << 24
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: glb.subdata(in: 20..<(20 + jsonLen))) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1); XCTAssertEqual(images[0]["mimeType"] as? String, "image/png")
        XCTAssertEqual((json["textures"] as? [Any])?.count, 1)
        let mats = try XCTUnwrap(json["materials"] as? [[String: Any]])
        let oak = try XCTUnwrap(mats.first { $0["name"] as? String == "Oak" })
        XCTAssertNotNil((oak["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"])
        let plain = try XCTUnwrap(mats.first { $0["name"] as? String == "Plain" })
        XCTAssertNil((plain["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"])
        let meshes = try XCTUnwrap(json["meshes"] as? [[String: Any]])
        let attrs = ((meshes[0]["primitives"] as? [[String: Any]])?.first?["attributes"] as? [String: Any]) ?? [:]
        XCTAssertNotNil(attrs["TEXCOORD_0"], "textured mesh gets UVs")
        // The image bytes are in the binary chunk at the image's buffer view.
        let views = try XCTUnwrap(json["bufferViews"] as? [[String: Any]])
        let v = views[images[0]["bufferView"] as! Int]
        let binStart = 20 + jsonLen + 8
        let off = v["byteOffset"] as! Int, len = v["byteLength"] as! Int
        XCTAssertEqual(glb.subdata(in: (binStart + off)..<(binStart + off + len)), Self.png)
    }

    func testUSDARoundTripWithMaterials() throws {
        let dir = try tmpDir()
        var d = ArchiDocument()
        d.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))), props: ["material": "Brick"]))
        let url = dir.appendingPathComponent("box.usda")
        _ = try FileImport.export(d, to: url, format: "usda")
        let (back, summary) = try FileImport.load(url)
        XCTAssertTrue(summary.contains("USD"), summary)
        XCTAssertFalse(back.entities.isEmpty)
        var b = BBox3.empty
        for e in back.entities { if case .solid(let s) = e.geometry { for p in s.meshVertices { b.add(p) } } }
        XCTAssertEqual(b.max.x - b.min.x, 1000, accuracy: 1e-3)
        XCTAssertEqual(b.max.y - b.min.y, 2000, accuracy: 1e-3)
        XCTAssertEqual(b.max.z - b.min.z, 3000, accuracy: 1e-3)
        let brick = try XCTUnwrap(back.material("Brick"))
        XCTAssertEqual(brick.color.r, Material.library.first { $0.name == "Brick" }!.color.r, accuracy: 1e-4)
        XCTAssertTrue(back.entities.allSatisfy { $0.props["material"] == "Brick" })
        // USDZ packages: textures are extracted next to the file.
        let tex = dir.appendingPathComponent("brick.png")
        try Self.png.write(to: tex)
        var mats = d.materials
        if let i = mats.firstIndex(where: { $0.name == "Brick" }) { mats[i].texture = tex.path }
        let z = USDExporter.usdz(MeshBuilder.build(doc: d), materials: mats, metersPerUnit: 0.001, name: "Box", textureRoot: dir)
        let zurl = dir.appendingPathComponent("box.usdz")
        try z.write(to: zurl)
        let r = try USDImporter.read(zurl)
        let t = try XCTUnwrap(r.materials.first { $0.name == "Brick" }?.texture)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: t)), Self.png)
        XCTAssertThrowsError(try USDImporter.parse("#usda 1.0\n", assets: { $0 }))
    }
}
