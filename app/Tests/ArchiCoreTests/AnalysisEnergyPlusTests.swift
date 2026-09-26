// Oanarina Archi Tool — GPL-3.0-or-later
// EnergyPlus export (ANL-024).
import XCTest
@testable import ArchiCore

final class AnalysisEnergyPlusTests: XCTestCase {
    func house() -> ArchiDocument {
        var d = ArchiDocument()
        let pts = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 4000), Vec2(0, 4000)]
        var south: EntityID = 0
        for i in 0..<4 {
            let w = d.addElement(.wall(WallGeom(start: pts[i], end: pts[(i + 1) % 4], thickness: 300, height: 3000, wallType: "Exterior Brick 365")), level: 0)
            d.elements[d.elementIndex(w)!].props["isExternal"] = "1"
            if i == 0 { south = w }
        }
        d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), thickness: 100, height: 3000)), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .window, hostWall: south, offset: 2500, width: 1500, height: 1200, sill: 900)), level: 0)
        d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Living", number: "001", height: 2700)), level: 0)
        d.addElement(.space(SpaceGeom(boundary: [Vec2(5000, 4000), Vec2(8000, 4000), Vec2(8000, 0), Vec2(5000, 0)], name: "Bed", number: "002", height: 2700)), level: 0)
        return d
    }

    static func newell(_ v: [Vec3]) -> Vec3 {
        var n = Vec3(0, 0, 0)
        for i in v.indices { let a = v[i], b = v[(i + 1) % v.count]; n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
        return n
    }

    func testZonesSurfacesOrientationAndWindows() throws {
        let d = house()
        let m = try EnergyPlusExport.build(d)
        XCTAssertEqual(m.zones.count, 2)
        XCTAssertEqual(m.zones[0].volume, 5 * 4 * 2.7, accuracy: 1e-9)
        XCTAssertEqual(m.surfaces.count, 12)
        XCTAssertEqual(m.surfaces.filter { $0.type == "Wall" && $0.boundary == "Outdoors" }.count, 6)
        XCTAssertEqual(m.surfaces.filter { $0.type == "Wall" && $0.boundary == "Surface" }.count, 2, "the shared wall is an interzone pair")
        XCTAssertEqual(m.surfaces.filter { $0.boundary == "Ground" }.count, 2)
        XCTAssertEqual(m.surfaces.filter { $0.type == "Roof" }.count, 2)
        // Outward normals (Newell of the vertex order, counter-clockwise seen from outside).
        for s in m.surfaces {
            let zone = s.zone.hasSuffix("Living") ? Vec3(2.5, 2, 1.35) : Vec3(6.5, 2, 1.35)
            let c = s.vertices.reduce(Vec3(0, 0, 0), +) * (1 / Double(s.vertices.count))
            XCTAssertGreaterThan(Self.newell(s.vertices).dot(c - zone), 0, "\(s.name) faces outwards")
        }
        XCTAssertEqual(m.windows.count, 1)
        let w = m.windows[0]
        let host = try XCTUnwrap(m.surfaces.first { $0.name == w.host })
        XCTAssertEqual(host.zone, "001 Living")
        XCTAssertTrue(w.vertices.allSatisfy { abs($0.y) < 1e-9 && $0.x > 0 && $0.x < 5 && $0.z >= 0.9 - 1e-9 && $0.z <= 2.1 + 1e-9 })
        XCTAssertGreaterThan(Self.newell(w.vertices).dot(Self.newell(host.vertices)), 0, "window faces like its wall")
        // IDF text: every referenced construction and material exists.
        let idf = m.idf
        XCTAssertTrue(idf.hasPrefix("! "))
        XCTAssertEqual(idf.components(separatedBy: "BuildingSurface:Detailed,").count - 1, 12)
        XCTAssertEqual(idf.components(separatedBy: "HVACTemplate:Zone:IdealLoadsAirSystem,").count - 1, 2)
        let objects = idf.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.hasPrefix("!") }
        func fields(_ o: String) -> [String] { o.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ",")) } }
        let materialNames = Set(objects.filter { $0.hasPrefix("Material,") || $0.hasPrefix("WindowMaterial") }.map { fields($0)[1] })
        let constructions = objects.filter { $0.hasPrefix("Construction,") }.map(fields)
        for c in constructions { for layer in c.dropFirst(2) { XCTAssertTrue(materialNames.contains(layer), "material \(layer)") } }
        let consNames = Set(constructions.map { $0[1] })
        for s in m.surfaces { XCTAssertTrue(consNames.contains(s.construction), s.construction) }
        XCTAssertTrue(consNames.contains("WT Exterior Brick 365"), "wall type layers become the construction")
        XCTAssertThrowsError(try EnergyPlusExport.build(ArchiDocument()))
    }

    @MainActor func testCommandExports() async throws {
        let ed = Editor()
        ed.doc = house()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID().uuidString).idf")
        let out = await ed.run("ENERGYPLUS Export \(url.path)")
        XCTAssertTrue(out.joined().contains("2 zone(s)"), out.joined(separator: "\n"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("GlobalGeometryRules"))
    }
}
