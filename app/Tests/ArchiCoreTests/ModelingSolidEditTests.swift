// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class ModelingSolidEditTests: XCTestCase {
    let box = SolidGeom(kind: .box, origin: Vec3(100, 200, 0), size: Vec3(1000, 800, 600))

    func check(_ s: SolidGeom, file: StaticString = #filePath, line: UInt = #line) -> Double {
        XCTAssertEqual(s.kind, .mesh, file: file, line: line)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: s.meshVertices, triangles: s.meshTriangles), "not a closed manifold", file: file, line: line)
        return SolidOps.volume(vertices: s.meshVertices, triangles: s.meshTriangles)
    }

    func testChamferAllEdgesExactVolume() throws {
        let r = 50.0
        let v = check(try SolidOps.filletEdges(box, radius: r, edges: .all, chamfer: true))
        let a = 1000 - 2 * r, b = 800 - 2 * r, c = 600 - 2 * r
        let t0: Double = a * b * c, t1: Double = 2 * r * (a * b + b * c + c * a), t2: Double = 2 * r * r * (a + b + c), t3: Double = 4.0 / 3 * r * r * r
        let exact = t0 + t1 + t2 + t3
        XCTAssertEqual(v, exact, accuracy: exact * 1e-9)
    }

    func testFilletAllEdgesApproachesRoundedBox() throws {
        let r = 80.0
        let s = try SolidOps.filletEdges(box, radius: r, edges: .all, chamfer: false, segments: 8)
        let v = check(s)
        let a = 1000 - 2 * r, b = 800 - 2 * r, c = 600 - 2 * r
        let t0: Double = a * b * c, t1: Double = 2 * r * (a * b + b * c + c * a), t2: Double = Double.pi * r * r * (a + b + c), t3: Double = 4.0 / 3 * Double.pi * r * r * r
        let exact = t0 + t1 + t2 + t3
        XCTAssertEqual(v, exact, accuracy: exact * 0.005)
        var bb = BBox3.empty; s.meshVertices.forEach { bb.add($0) }
        XCTAssertEqual(bb.min.x, 100, accuracy: 1e-6); XCTAssertEqual(bb.max.z, 600, accuracy: 1e-6)
    }

    func testFilletSubsetsAndLimits() throws {
        let vert = check(try SolidOps.filletEdges(box, radius: 100, edges: .vertical, chamfer: false, segments: 16))
        let full: Double = 1000 * 800 * 600, corners: Double = (4 - Double.pi) * 100 * 100 * 600
        XCTAssertEqual(vert, full - corners, accuracy: full * 0.001)
        _ = check(try SolidOps.filletEdges(box, radius: 100, edges: .top, chamfer: false))
        _ = check(try SolidOps.filletEdges(box, radius: 100, edges: [.top, .bottom], chamfer: true))
        // L-shaped extrusion with a concave corner.
        let l = SolidGeom(kind: .extrusion, origin: .zero, profile: [.zero, Vec2(2000, 0), Vec2(2000, 800), Vec2(800, 800), Vec2(800, 2000), Vec2(0, 2000)], height: 500)
        _ = check(try SolidOps.filletEdges(l, radius: 60, edges: .all, chamfer: false))
        XCTAssertThrowsError(try SolidOps.filletEdges(box, radius: 300, edges: .all, chamfer: false))
        XCTAssertThrowsError(try SolidOps.filletEdges(SolidGeom(kind: .sphere, origin: .zero, size: Vec3(100, 0, 0)), radius: 10, edges: .all, chamfer: false))
    }

    func testShell() throws {
        let t = 20.0
        let open = check(try SolidOps.shell(box, thickness: t, openTop: true))
        let full: Double = 1000 * 800 * 600, hole1: Double = (1000 - 2 * t) * (800 - 2 * t) * (600 - t), hole2: Double = (1000 - 2 * t) * (800 - 2 * t) * (600 - 2 * t)
        XCTAssertEqual(open, full - hole1, accuracy: 1e-3)
        let closed = check(try SolidOps.shell(box, thickness: t, openTop: false))
        XCTAssertEqual(closed, full - hole2, accuracy: 1e-3)
        XCTAssertThrowsError(try SolidOps.shell(box, thickness: 450, openTop: true))
    }

    func testLoopSubdivisionSmoothsClosedMesh() throws {
        let s = try SolidOps.smooth(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000)), levels: 2)
        let v = check(s)
        XCTAssertEqual(s.meshTriangles.count / 3, 12 * 16)
        XCTAssertLessThan(v, 1e9); XCTAssertGreaterThan(v, 0.25e9)
        // Smoothing shrinks towards a rounded shape: corners pulled in.
        let maxR = s.meshVertices.map { ($0 - Vec3(500, 500, 500)).length }.max()!
        XCTAssertLessThan(maxR, 866)
    }

    func testMirrorRotateAndTranslate() {
        let m = SolidOps.mapped(box, mirroring: true) { SolidOps.reflect($0, plane: .yz, origin: .zero) }
        let v = check(m)
        XCTAssertEqual(v, 480_000_000, accuracy: 1)
        var b = BBox3.empty; m.meshVertices.forEach { b.add($0) }
        XCTAssertEqual(b.min.x, -1100, accuracy: 1e-6); XCTAssertEqual(b.max.x, -100, accuracy: 1e-6)
        let r = SolidOps.mapped(box, mirroring: false) { SolidOps.rotate($0, axis: "x", angle: .pi / 2, origin: .zero) }
        XCTAssertEqual(check(r), 480_000_000, accuracy: 1)
        var rb = BBox3.empty; r.meshVertices.forEach { rb.add($0) }
        XCTAssertEqual(rb.max.z, 1000, accuracy: 1e-6)   // y 200…1000 becomes z
        let p = SolidOps.rotate(Vec3(1, 0, 0), axis: "y", angle: .pi / 2, origin: .zero)
        XCTAssertEqual(p.z, -1, accuracy: 1e-12)
        XCTAssertEqual(SolidOps.translated(box, by: Vec3(0, 0, 50)).origin.z, 50)
    }

    func testSolidEditCommands() async {
        let ed = Editor()
        let a = ed.doc.add(.solid(box))
        ed.selection = [a]
        await ed.run("FILLETEDGE 40 Vertical")
        guard case .solid(let f)? = ed.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(f.kind, .mesh)
        ed.undo()
        guard case .solid(let back)? = ed.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(back.kind, .box)
        ed.selection = [a]
        await ed.run("3DARRAY Rectangular 2 3 2 1500 1200 700")
        XCTAssertEqual(ed.doc.entities.count, 12)
        let zs = Set(ed.doc.entities.compactMap { e -> Double? in if case .solid(let s) = e.geometry { return s.origin.z }; return nil })
        XCTAssertEqual(zs, [0, 700])
        ed.selection = [a]
        await ed.run("MIRROR3D XY 0 No")
        XCTAssertEqual(ed.doc.entities.count, 13)
        ed.selection = [a]
        await ed.run("3DARRAY Polar 4 360 Yes 0,0 0")
        XCTAssertEqual(ed.doc.entities.count, 16)
        ed.selection = [a]
        await ed.run("SHELL 10 Yes")
        guard case .solid(let sh)? = ed.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: sh.meshVertices, triangles: sh.meshTriangles))
        ed.selection = [a]
        await ed.run("MESHSMOOTH 1")
        guard case .solid(let sm)? = ed.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(sm.meshTriangles.count, sh.meshTriangles.count * 4)
        ed.selection = [a]
        await ed.run("ROTATE3D Y 0,0 0 90")
        XCTAssertNotNil(ed.doc.entity(a))
    }
}
