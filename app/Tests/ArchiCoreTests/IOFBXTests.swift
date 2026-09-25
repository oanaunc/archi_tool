// Oanarina Archi Tool — GPL-3.0-or-later
// FBX import/export (IO-039).
import XCTest
@testable import ArchiCore

final class IOFBXTests: XCTestCase {
    func testBinaryExportRoundTripKeepsScaleAndMaterials() throws {
        var d = ArchiDocument()
        d.add(.solid(SolidGeom(kind: .box, origin: Vec3(1000, 2000, 0), size: Vec3(3000, 1000, 500))))
        d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0), thickness: 200, height: 2800)), material: "Brick")
        let meshes = MeshBuilder.build(doc: d)
        let data = FBX.export(meshes, materials: d.materials, unitMM: 1, name: "Test")
        XCTAssertTrue(data.starts(with: Array("Kaydara FBX Binary  ".utf8)))
        let nodes = try FBX.readBinary(data)
        XCTAssertEqual(nodes.map(\.name), ["FBXHeaderExtension", "GlobalSettings", "Documents", "References", "Definitions", "Objects", "Connections"])
        let r = try FBX.entities(data)
        XCTAssertEqual(r.entities.count, meshes.filter { !$0.mesh.isEmpty }.count)
        var b = BBox3.empty
        for e in r.entities { if case .solid(let s) = e.geometry { s.meshVertices.forEach { b.add($0) } } }
        XCTAssertEqual(b.max.x, 4000, accuracy: 1e-6); XCTAssertEqual(b.max.z, 2800, accuracy: 1e-6); XCTAssertEqual(b.max.y, 3000, accuracy: 1e-6)
        let brick = try XCTUnwrap(r.materials.first { $0.name == "Brick" })
        XCTAssertEqual(brick.color, d.material("Brick")?.color)
        XCTAssertTrue(r.entities.contains { $0.props["material"] == "Brick" })
        // Through the file paths.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).fbx")
        try DocumentIO.write(d, to: url)
        XCTAssertEqual(try FileImport.load(url).0.entities.count, r.entities.count)
    }

    func testCompressedArraysAndWideHeaders() throws {
        // A 7.5 file (64-bit node headers) with a zlib-compressed vertex array, built by hand.
        func u32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
        func u64(_ v: UInt64) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 8) }
        var out = Data(Array("Kaydara FBX Binary  ".utf8) + [0, 0x1A, 0]) + u32(7500)
        func node(_ name: String, props: Data, nprops: Int, children: [Data] = []) -> (Int) -> Data {
            { start in
                var body = Data([UInt8(name.utf8.count)]) + Data(name.utf8) + props
                for c in children { body += c }
                if !children.isEmpty { body += Data(count: 25) }
                let end = start + 24 + body.count
                return u64(UInt64(end)) + u64(UInt64(nprops)) + u64(UInt64(props.count)) + body
            }
        }
        var raw = Data()
        for v in [0.0, 0, 0, 10, 0, 0, 0, 10, 0] { var x = v.bitPattern.littleEndian; raw += Data(bytes: &x, count: 8) }
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        let zlib = Data([0x78, 0x9C]) + deflated + Data([0, 0, 0, 0])
        let vertsProp = Data([UInt8(ascii: "d")]) + u32(9) + u32(1) + u32(UInt32(zlib.count)) + zlib
        var idx = Data([UInt8(ascii: "i")]) + u32(3) + u32(0) + u32(12)
        for v: Int32 in [0, 1, ~2] { var x = v.littleEndian; idx += Data(bytes: &x, count: 4) }
        // Objects { Geometry(1) { Vertices, PolygonVertexIndex } }
        let objectsStart = out.count
        let geomStart = objectsStart + 24 + 1 + 7
        let vStart = geomStart + 24 + 1 + 8 + 9
        let vNode = node("Vertices", props: vertsProp, nprops: 1)(vStart)
        let iNode = node("PolygonVertexIndex", props: idx, nprops: 1)(vStart + vNode.count)
        let gProps = Data([UInt8(ascii: "L")]) + u64(1)
        let gNode = node("Geometry", props: gProps, nprops: 1, children: [vNode, iNode])(geomStart)
        let oNode = node("Objects", props: Data(), nprops: 0, children: [gNode])(objectsStart)
        out += oNode + Data(count: 25)
        let r = try FBX.entities(out)
        guard case .solid(let s) = r.entities.first?.geometry else { return XCTFail() }
        // Default units cm → ×10 mm; default up axis Y → Z up.
        XCTAssertEqual(s.meshVertices[1], Vec3(100, 0, 0))
        XCTAssertEqual(s.meshVertices[2], Vec3(0, 0, 100))
    }

    func testASCIIFileWithTransformsYUpAndCentimetres() throws {
        let text = """
        ; FBX 7.3.0 project file
        FBXHeaderExtension:  {
            FBXHeaderVersion: 1003
            FBXVersion: 7300
        }
        GlobalSettings:  {
            Version: 1000
            Properties70:  {
                P: "UpAxis", "int", "Integer", "",1
                P: "UnitScaleFactor", "double", "Number", "",1
            }
        }
        Objects:  {
            Geometry: 100, "Geometry::Tri", "Mesh" {
                Vertices: *9 {
                    a: 0,0,0,100,0,0,0,50,0
                }
                PolygonVertexIndex: *3 {
                    a: 0,1,-3
                }
            }
            Model: 200, "Model::Tri", "Mesh" {
                Version: 232
                Properties70:  {
                    P: "Lcl Translation", "Lcl Translation", "", "A",10,0,0
                    P: "Lcl Rotation", "Lcl Rotation", "", "A",0,90,0
                }
            }
            Material: 300, "Material::Red", "" {
                Properties70:  {
                    P: "DiffuseColor", "Color", "", "A",1,0,0
                }
            }
        }
        Connections:  {
            C: "OO",200,0
            C: "OO",100,200
            C: "OO",300,200
        }
        """
        let r = try FBX.entities(Data(text.utf8))
        XCTAssertEqual(r.entities.count, 1)
        XCTAssertEqual(r.entities[0].props["name"], "Tri")
        XCTAssertEqual(r.entities[0].props["material"], "Red")
        XCTAssertEqual(r.materials.first?.color, RGBA(1, 0, 0))
        guard case .solid(let s) = r.entities[0].geometry else { return XCTFail() }
        // (100,0,0) rotated 90° about Y → (0,0,-100), + (10,0,0) → (10,0,-100) cm → mm, then Y up → Z up: (x, -z, y).
        XCTAssertEqual(s.meshVertices[1].x, 100, accuracy: 1e-6)
        XCTAssertEqual(s.meshVertices[1].y, 1000, accuracy: 1e-6)
        XCTAssertEqual(s.meshVertices[1].z, 0, accuracy: 1e-6)
        XCTAssertEqual(s.meshVertices[2].z, 500, accuracy: 1e-6)
        XCTAssertThrowsError(try FBX.entities(Data("hello".utf8)))
    }
}
