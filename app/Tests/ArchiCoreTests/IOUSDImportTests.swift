// Oanarina Archi Tool — GPL-3.0-or-later
// USD import (IO-038): stage units (metersPerUnit), up axis, xformOp stacks (translate/rotate/orient/scale/transform in
// xformOpOrder), materials and displayColor.
import XCTest
@testable import ArchiCore

final class IOUSDImportTests: XCTestCase {
    func write(_ text: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("usd-\(UUID().uuidString).usda")
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    let tri = """
            point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
    """
    func verts(_ e: Entity) -> [Vec3] { if case .solid(let s) = e.geometry { return s.meshVertices }; return [] }

    func testUnitsUpAxisAndRotateTranslateOrder() throws {
        let url = try write("""
        #usda 1.0
        (
            metersPerUnit = 1
            upAxis = "Z"
        )
        def Xform "Root"
        {
            double3 xformOp:translate = (10, 0, 0)
            float xformOp:rotateZ = 90
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateZ"]
            def Mesh "Tri"
            {
        \(tri)
                color3f[] primvars:displayColor = [(1, 0, 0)]
            }
        }
        """)
        let r = try USDImporter.read(url)
        let v = try XCTUnwrap(r.entities.first.map(verts))
        // Rotate 90° about Z, then translate 10 m; metres → millimetres.
        XCTAssertEqual(v[1].x, 10_000, accuracy: 1e-6); XCTAssertEqual(v[1].y, 1000, accuracy: 1e-6)
        XCTAssertEqual(v[2].x, 9000, accuracy: 1e-6); XCTAssertEqual(v[2].y, 0, accuracy: 1e-6)
        let mat = try XCTUnwrap(r.entities.first?.props["material"])
        XCTAssertEqual(r.materials.first { $0.name == mat }?.color, RGBA(1, 0, 0))
    }

    func testYUpCentimetresScaleAndMatrix() throws {
        let url = try write("""
        #usda 1.0
        (
            metersPerUnit = 0.01
            upAxis = "Y"
        )
        def Xform "A"
        {
            matrix4d xformOp:transform = ( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (100, 200, 0, 1) )
            uniform token[] xformOpOrder = ["xformOp:transform"]
            def Mesh "M"
            {
                float3 xformOp:scale = (2, 2, 2)
                uniform token[] xformOpOrder = ["xformOp:scale"]
        \(tri)
            }
        }
        """)
        let v = try XCTUnwrap(try USDImporter.read(url).entities.first.map(verts))
        // (1,0,0) scaled ×2 → (2,0,0) + (100,200,0) = (102,200,0) cm = (1020, 2000, 0) mm, Y up → Z up: (x, -z, y).
        XCTAssertEqual(v[1].x, 1020, accuracy: 1e-6); XCTAssertEqual(v[1].y, 0, accuracy: 1e-6); XCTAssertEqual(v[1].z, 2000, accuracy: 1e-6)
    }

    func testOrientAndRotateXYZ() {
        let q = USDMatrix.op("xformOp:orient", [cos(.pi / 4), 0, 0, sin(.pi / 4)])!   // 90° about Z
        let p = q.apply(Vec3(1, 0, 0))
        XCTAssertEqual(p.x, 0, accuracy: 1e-12); XCTAssertEqual(p.y, 1, accuracy: 1e-12)
        let e = USDMatrix.op("xformOp:rotateXYZ", [90, 0, 90])!   // X first, then Z
        let r = e.apply(Vec3(0, 1, 0))   // X: (0,1,0)→(0,0,1); Z leaves it
        XCTAssertEqual(r.z, 1, accuracy: 1e-12)
        let inv = USDMatrix.op("xformOp:translate", [1, 2, 3])!.inverse!
        XCTAssertEqual(inv.apply(Vec3(1, 2, 3)), Vec3(0, 0, 0))
    }

    func testRoundTripOfExportedUSDKeepsScale() throws {
        var d = ArchiDocument()
        d.add(.solid(SolidGeom(kind: .box, origin: Vec3(1000, 2000, 0), size: Vec3(3000, 1000, 500))))
        let meshes = MeshBuilder.build(doc: d)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString).usda")
        try USDExporter.usda(meshes, materials: d.materials, metersPerUnit: 0.001, name: "RT").write(to: url, atomically: true, encoding: .utf8)
        let back = try USDImporter.read(url)
        var b = BBox3.empty
        for e in back.entities { for v in verts(e) { b.add(v) } }
        XCTAssertEqual(b.min.x, 1000, accuracy: 1e-3); XCTAssertEqual(b.max.x, 4000, accuracy: 1e-3)
        XCTAssertEqual(b.max.z, 500, accuracy: 1e-3)
    }
}
