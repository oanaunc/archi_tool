// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Scale tool with handles (M3D-106).
@MainActor
final class ModelingScaleHandlesTests: XCTestCase {
    let box = BBox3(min: Vec3(0, 0, 0), max: Vec3(1000, 2000, 3000))

    func testHandleMaths() async throws {
        XCTAssertEqual(ScaleHandles.all.count, 26)
        XCTAssertEqual(Set(ScaleHandles.all.map(\.kind)), ["face", "edge", "corner"])
        XCTAssertEqual(ScaleHandles.Handle(1, 0, 1).description, "top-right edge")
        // Face handle: one axis, about the opposite face.
        let a = try XCTUnwrap(ScaleHandles.scale(box: box, handle: .init(1, 0, 0), to: Vec3(2000, 777, 5)))
        XCTAssertEqual(a.factors, Vec3(2, 1, 1)); XCTAssertEqual(a.origin.x, 0)
        // About the centre.
        let c = try XCTUnwrap(ScaleHandles.scale(box: box, handle: .init(1, 0, 0), to: Vec3(1500, 0, 0), aboutCenter: true))
        XCTAssertEqual(c.factors.x, 2, accuracy: 1e-12)
        XCTAssertEqual(ScaleHandles.scaled(box, origin: c.origin, factors: c.factors).min.x, -500, accuracy: 1e-9)
        // Corner handle, non-uniform and uniform.
        let d = try XCTUnwrap(ScaleHandles.scale(box: box, handle: .init(-1, -1, 0), to: Vec3(-1000, 1000, 0)))
        XCTAssertEqual(d.factors.x, 2, accuracy: 1e-12); XCTAssertEqual(d.factors.y, 0.5, accuracy: 1e-12); XCTAssertEqual(d.factors.z, 1)
        let u = try XCTUnwrap(ScaleHandles.scale(box: box, handle: .init(1, 1, 1), to: Vec3(2000, 4000, 6000), uniform: true))
        XCTAssertEqual(u.factors.x, 2, accuracy: 1e-12); XCTAssertEqual(u.factors.z, 2, accuracy: 1e-12)
        // Dragging onto the fixed side collapses the box: refused. Past it mirrors.
        XCTAssertNil(ScaleHandles.scale(box: box, handle: .init(0, 0, 1), to: Vec3(0, 0, 0)))
        XCTAssertEqual(ScaleHandles.scale(box: box, handle: .init(0, 0, 1), to: Vec3(0, 0, -3000))?.factors.z, -1)
        XCTAssertEqual(ScaleHandles.nearestPlan(Vec2(990, 1000), box: box), .init(1, 0, 0))
        XCTAssertEqual(ScaleHandles.planPreview(box, size: 10).count, 9)
    }

    func testScaleWithHandlesThenConvertToBIM() async throws {
        let ed = Editor()
        await ed.run("BOX 0,0 10000,8000 6000")
        let id = try XCTUnwrap(ed.doc.entities.last?.id)
        ed.selection = [id]
        await ed.run("SCALE3D Handles 10000,4000 15000,4000")
        guard case .solid(let s)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        let b = MeshTools.mesh(of: s).bounds
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6); XCTAssertEqual(b.max.x, 15000, accuracy: 1e-6)
        XCTAssertEqual(b.size.y, 8000, accuracy: 1e-6); XCTAssertEqual(b.size.z, 6000, accuracy: 1e-6)
        // Top handle about the centre: 6000 → 9000 tall keeps the middle at 3000.
        ed.selection = [id]
        await ed.run("SCALE3D Handles Center Top 7500")
        guard case .solid(let s2)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        let b2 = MeshTools.mesh(of: s2).bounds
        XCTAssertEqual(b2.min.z, -1500, accuracy: 1e-6); XCTAssertEqual(b2.max.z, 7500, accuracy: 1e-6)
        ed.undo()
        guard case .solid(let s3)? = ed.doc.entity(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(MeshTools.mesh(of: s3).bounds.max.z, 6000, accuracy: 1e-6)
        // The scaled mass converts into building elements.
        ed.selection = [id]
        await ed.run("BUILDING Mass Elements")
        let walls = ed.doc.elements.compactMap { el -> WallGeom? in if case .wall(let w) = el.geometry { return w }; return nil }
        XCTAssertEqual(walls.count, 8)
        XCTAssertEqual(walls.map(\.length).max() ?? 0, 15000, accuracy: 1)
    }
}
