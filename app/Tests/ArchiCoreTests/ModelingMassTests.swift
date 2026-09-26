// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Conceptual masses: mass floors per level and walls/floors/roofs by face.
@MainActor
final class ModelingMassTests: XCTestCase {
    func testBoxMassFloorsAndElements() async throws {
        let ed = Editor()
        await ed.run("BOX 0,0 10000,8000 6000")
        let mid = try XCTUnwrap(ed.doc.entities.last?.id)
        guard case .solid(let s)? = ed.doc.entity(mid)?.geometry else { return XCTFail() }
        let fl = MassTools.floors(s, levels: ed.doc.levels)
        XCTAssertEqual(fl.count, 2)
        for f in fl { XCTAssertEqual(f.area, 80e6, accuracy: 1) }
        ed.selection = [mid]
        await ed.run("BUILDING Mass Elements")
        let walls = ed.doc.elements.compactMap { el -> (Int, WallGeom)? in if case .wall(let w) = el.geometry { return (el.level, w) }; return nil }
        XCTAssertEqual(walls.count, 8)
        XCTAssertTrue(walls.allSatisfy { abs($0.1.height - 3000) < 1e-6 && $0.1.justification == .right })
        XCTAssertEqual(Set(walls.map(\.0)), [0, 1])
        // Outer wall faces lie on the mass faces: a room inside spans the inner faces.
        await ed.run("ROOM 5000,4000 ")
        guard case .space(let room)? = ed.doc.elements.last?.geometry else { return XCTFail() }
        XCTAssertEqual(abs(GeometryOps.signedArea(room.boundary)), 9600 * 7600, accuracy: 1)
        XCTAssertEqual(ed.doc.elements.filter { if case .slab = $0.geometry { return true }; return false }.count, 2)
        guard let roof = ed.doc.elements.first(where: { if case .roof = $0.geometry { return true }; return false }), case .roof(let rg) = roof.geometry else { return XCTFail() }
        XCTAssertEqual(roof.level, 1); XCTAssertEqual(rg.kind, .flat)
        XCTAssertEqual(abs(GeometryOps.signedArea(rg.boundary)), 80e6, accuracy: 1)
        XCTAssertEqual(roof.props["fromMass"], "\(mid)")
    }

    func testTaperedAndCourtyardMassFloors() {
        var doc = ArchiDocument()
        doc.levels = [Level(id: 0, name: "L0", elevation: 0), Level(id: 1, name: "L1", elevation: 3000), Level(id: 2, name: "L2", elevation: 6000)]
        // Pyramid-like frustum (cone with top radius): floors shrink with height.
        let cone = SolidGeom(kind: .cone, origin: .zero, size: Vec3(6000, 3000, 9000))
        let f = MassTools.floors(cone, levels: doc.levels)
        XCTAssertEqual(f.count, 3)
        XCTAssertGreaterThan(f[0].area, f[1].area); XCTAssertGreaterThan(f[1].area, f[2].area)
        XCTAssertEqual(f[1].area, .pi * 5000 * 5000, accuracy: .pi * 5000 * 5000 * 0.02)
        // Courtyard: box minus box → floors with a hole, slabs with a hole.
        let outer = SolidGeom(kind: .box, origin: .zero, size: Vec3(20000, 20000, 6000))
        let inner = SolidGeom(kind: .box, origin: Vec3(5000, 5000, -10), size: Vec3(10000, 10000, 6020))
        let court = try! XCTUnwrap(CSG.apply(.subtract, outer, inner))
        let cf = MassTools.floors(court, levels: doc.levels)
        XCTAssertEqual(cf.count, 2)
        XCTAssertEqual(cf[0].area, 400e6 - 100e6, accuracy: 10)
        XCTAssertEqual(cf[0].regions.first?.holes.count, 1)
        let r = MassTools.convert(court, massID: nil, doc: &doc, wallThickness: 200, slabThickness: 200, walls: true, slabs: true, roof: false)
        XCTAssertEqual(r.walls.count, 16, "outer and courtyard walls on two storeys")
        guard case .slab(let sl)? = doc.element(r.slabs[0])?.geometry else { return XCTFail() }
        XCTAssertEqual(sl.holes.count, 1)
    }
}
