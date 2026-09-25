// Oanarina Archi Tool — GPL-3.0-or-later
// Mesh exports carry the right scale (metres), up axis and materials whatever the drawing units (OBJ IO-031,
// glTF IO-035, USD IO-037, COLLADA IO-045); SVG export re-imports without missing entities, layers kept (IO-017);
// HEIC/AVIF image sizes.
import XCTest
@testable import ArchiCore

final class IOExportScaleTests: XCTestCase {
    /// A 4 × 0.3 × 2.5 m brick wall in a document whose unit is `units`.
    func doc(_ units: Units) -> ArchiDocument {
        var d = ArchiDocument()
        d.units = units
        let k = 1000 / units.mm
        d.levels = [Level(id: 0, name: "L0", elevation: 0, height: 3000 / units.mm)]
        _ = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(4 * k, 0), thickness: 0.3 * k, height: 2.5 * k)), material: "Brick")
        return d
    }
    let brick = Material.library.first { $0.name == "Brick" }!

    func testOBJScaleAndMaterials() {
        for u in [Units.millimeters, .meters, .inches] {
            let d = doc(u)
            let r = OBJExporter.export(MeshBuilder.build(doc: d), materials: d.materials, mtlFileName: "m.mtl", unitMM: d.units.mm)
            let vs = r.obj.split(separator: "\n").filter { $0.hasPrefix("v ") }.map { $0.split(separator: " ").dropFirst().compactMap { Double($0) } }
            XCTAssertEqual(vs.map { $0[0] }.max()! - vs.map { $0[0] }.min()!, 4, accuracy: 1e-3, "\(u)")
            XCTAssertEqual(vs.map { $0[1] }.max()! - vs.map { $0[1] }.min()!, 2.5, accuracy: 1e-3, "Y up, \(u)")
            XCTAssertTrue(r.obj.contains("usemtl Brick"))
            XCTAssertTrue(r.mtl.contains("newmtl Brick"))
            XCTAssertTrue(r.mtl.contains("Kd \(MeshExport.num(brick.color.r)) \(MeshExport.num(brick.color.g)) \(MeshExport.num(brick.color.b))"), r.mtl)
        }
    }

    func testGLBScaleAndMaterials() throws {
        let d = doc(.meters)
        let glb = GLTFExporter.exportGLB(MeshBuilder.build(doc: d), materials: d.materials, unitMM: d.units.mm)
        let len = Int(glb.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian })
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: glb.subdata(in: 20..<(20 + len))) as? [String: Any])
        let acc = try XCTUnwrap(json["accessors"] as? [[String: Any]])
        let pos = acc.compactMap { $0["max"] as? [Double] }.filter { $0.count == 3 }
        let mins = acc.compactMap { $0["min"] as? [Double] }.filter { $0.count == 3 }
        XCTAssertEqual(pos.map { $0[0] }.max()! - mins.map { $0[0] }.min()!, 4, accuracy: 1e-3)
        XCTAssertEqual(pos.map { $0[1] }.max()! - mins.map { $0[1] }.min()!, 2.5, accuracy: 1e-3)
        let mats = try XCTUnwrap(json["materials"] as? [[String: Any]])
        let m = try XCTUnwrap(mats.first { $0["name"] as? String == "Brick" })
        let f = try XCTUnwrap((m["pbrMetallicRoughness"] as? [String: Any])?["baseColorFactor"] as? [Double])
        XCTAssertEqual(f[0], brick.color.r, accuracy: 1e-6); XCTAssertEqual(f[1], brick.color.g, accuracy: 1e-6)
    }

    func testColladaAndUSDScaleAndMaterials() throws {
        let d = doc(.centimeters)
        let groups = MeshBuilder.build(doc: d)
        let dae = ColladaExporter.export(groups, materials: d.materials, unitMM: d.units.mm)
        XCTAssertTrue(dae.contains("<unit name=\"meter\" meter=\"1\"/>")); XCTAssertTrue(dae.contains("<up_axis>Z_UP</up_axis>"))
        XCTAssertTrue(dae.contains("<diffuse><color>\(fmt(brick.color.r, 4)) \(fmt(brick.color.g, 4)) \(fmt(brick.color.b, 4)) 1</color>"))
        let back = try ColladaImporter.entities(Data(dae.utf8), unitMM: 1)
        var b = BBox3.empty
        for e in back { if case .solid(let s) = e.geometry { s.meshVertices.forEach { b.add($0) } } }
        XCTAssertEqual(b.max.x - b.min.x, 4000, accuracy: 1); XCTAssertEqual(b.max.z - b.min.z, 2500, accuracy: 1)
        let usda = USDExporter.usda(groups, materials: d.materials, metersPerUnit: d.units.mm / 1000, name: "M")
        XCTAssertTrue(usda.contains("metersPerUnit = 0.01")); XCTAssertTrue(usda.contains("upAxis = \"Z\""))
        XCTAssertTrue(usda.contains("color3f inputs:diffuseColor = (\(MeshExport.num(brick.color.r)), \(MeshExport.num(brick.color.g)), \(MeshExport.num(brick.color.b)))"))
    }

    func testSVGExportReimportsAllEntitiesOnTheirLayers() throws {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "WALLS", color: RGBA(1, 0, 0)))
        d.layers.append(Layer(name: "FURN", color: RGBA(0, 0, 1)))
        _ = d.add(Entity(layer: "WALLS", geometry: .line(LineGeom(Vec2(0, 0), Vec2(5000, 0)))))
        _ = d.add(Entity(layer: "WALLS", geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(0, 3000), Vec2(5000, 3000)]))))
        _ = d.add(Entity(layer: "FURN", geometry: .circle(CircleGeom(Vec2(2500, 1500), 400))))
        _ = d.add(Entity(layer: "FURN", geometry: .arc(ArcGeom(Vec2(1000, 1000), 300, 0, .pi / 2))))
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: 0))
        let bounds = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
        let svg = SVGExporter.exportLayered(doc: d, entries: entries, bounds: bounds, background: nil)
        var o = SVGImportOptions(); o.scale = 1
        let ents = try SVGImporter.entities(svg, options: o)
        XCTAssertEqual(ents.filter { $0.layer == "WALLS" }.count, 2)
        XCTAssertEqual(ents.filter { $0.layer == "FURN" }.count, 2)
        var ib = BBox2.empty
        for e in ents { ib.add(GeometryOps.bounds(e.geometry, doc: nil)) }
        XCTAssertEqual(ib.width, bounds.width, accuracy: bounds.width * 0.01)
        XCTAssertEqual(ib.height, bounds.height, accuracy: bounds.height * 0.01)
    }

    func testHEICSize() {
        var b: [UInt8] = [0, 0, 0, 24] + Array("ftypheic".utf8) + Array(repeating: 0, count: 12)
        b += [0, 0, 0, 20] + Array("ispe".utf8) + [0, 0, 0, 0, 0, 0, 0x0F, 0xC0, 0, 0, 0x0B, 0xD0]   // 4032 × 3024
        XCTAssertEqual(ImageHeader.size(Data(b)).map { [$0.width, $0.height] }, [4032, 3024])
    }
}
