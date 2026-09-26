// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Ambient occlusion baked on the model (VIS-033).
@MainActor
final class RenderAmbientOcclusionTests: XCTestCase {
    func quad(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ d: Vec3) -> MeshGroup {
        var m = Mesh(); m.addQuad(a, b, c, d)
        return MeshGroup(id: nil, kind: "test", material: "Concrete", mesh: m)
    }

    func testOcclusionInCornerAndOpen() {
        let ground = quad(Vec3(-5000, -5000, 0), Vec3(5000, -5000, 0), Vec3(5000, 5000, 0), Vec3(-5000, 5000, 0))
        let wall = quad(Vec3(0, -5000, 0), Vec3(0, 5000, 0), Vec3(0, 5000, 3000), Vec3(0, -5000, 3000))
        let sc = AmbientOcclusion.Scene(groups: [ground, wall])
        XCTAssertEqual(sc.triangleCount, 4)
        let s = AmbientOcclusion.Settings(radius: 1000, samples: 64)
        let open = sc.occlusion(at: Vec3(3000, 0, 0), normal: .unitZ, settings: s)
        let corner = sc.occlusion(at: Vec3(50, 0, 0), normal: .unitZ, settings: s)
        XCTAssertEqual(open, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(corner, 0.2); XCTAssertLessThan(corner, 0.7)
        // Deterministic.
        XCTAssertEqual(corner, sc.occlusion(at: Vec3(50, 0, 0), normal: .unitZ, settings: s))
        // Under a ceiling 200 above (rays up to 1000 long): cos θ > 0.2 hits, i.e. 96 % cosine-weighted.
        let ceiling = quad(Vec3(-5000, -5000, 200), Vec3(-5000, 5000, 200), Vec3(5000, 5000, 200), Vec3(5000, -5000, 200))
        let sc2 = AmbientOcclusion.Scene(groups: [ground, ceiling])
        XCTAssertGreaterThan(sc2.occlusion(at: Vec3(0, 0, 0), normal: .unitZ, settings: s), 0.9)
        // Per-vertex bake keeps the group layout.
        let baked = AmbientOcclusion.bake([ground, wall], settings: s)
        XCTAssertEqual(baked.map(\.count), [ground.mesh.positions.count, wall.mesh.positions.count])
        XCTAssertTrue(baked.flatMap { $0 }.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testShadedElevationDarkensWithOcclusion() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        await ed.run("WALL 6000,0 6000,4000 ")
        await ed.run("SLAB 0,-1000 7000,-1000 7000,5000 0,5000 C")
        func tones() -> [Double] {
            ElevationBuilder.entries(doc: ed.doc, view: .elevationSouth).flatMap(\.items).compactMap { if case .fill(_, let c) = $0 { return c.r + c.g + c.b }; return nil }
        }
        let plain = tones()
        await ed.run("AMBIENTOCCLUSION Intensity 1.5")
        XCTAssertNotNil(AmbientOcclusion.settings(ed.doc))
        let ao = tones()
        XCTAssertEqual(plain.count, ao.count)
        XCTAssertLessThan(ao.reduce(0, +), plain.reduce(0, +) - 1e-6)
        XCTAssertTrue(zip(plain, ao).allSatisfy { $1 <= $0 + 1e-9 })
        await ed.run("AMBIENTOCCLUSION Off")
        XCTAssertNil(AmbientOcclusion.settings(ed.doc))
        XCTAssertEqual(tones(), plain)
    }
}
