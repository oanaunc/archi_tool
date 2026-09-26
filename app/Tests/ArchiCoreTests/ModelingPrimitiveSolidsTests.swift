// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Primitive solids from the command line are closed, watertight and have the requested dimensions.
@MainActor
final class ModelingPrimitiveSolidsTests: XCTestCase {
    func lastSolid(_ ed: Editor) -> SolidGeom? { if case .solid(let s)? = ed.doc.entities.last?.geometry { return s }; return nil }
    func check(_ s: SolidGeom?, volume v: Double, tol: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = s else { return XCTFail("no solid", file: file, line: line) }
        let m = MeshTools.mesh(of: s)
        XCTAssertTrue(PlaneClipper.isClosedManifold(MeshTools.triangles(m)), "watertight", file: file, line: line)
        XCTAssertEqual(MeshTools.signedVolume(m), v, accuracy: v * tol, file: file, line: line)
    }

    func testBoxCornerCenterCubeLength() async {
        let ed = Editor()
        await ed.run("BOX 0,0 2000,1000 500")
        check(lastSolid(ed), volume: 2000 * 1000 * 500, tol: 1e-9)
        await ed.run("BOX Center 5000,5000 5500,5250 300")
        let c = lastSolid(ed)!
        XCTAssertEqual(c.origin.x, 4500, accuracy: 1e-9); XCTAssertEqual(c.size.x, 1000, accuracy: 1e-9); XCTAssertEqual(c.size.y, 500, accuracy: 1e-9)
        check(c, volume: 1000 * 500 * 300, tol: 1e-9)
        await ed.run("BOX 0,0 Cube 800")
        check(lastSolid(ed), volume: 800 * 800 * 800, tol: 1e-9)
        await ed.run("BOX 0,0 Length 1000 2000 -300")
        let neg = lastSolid(ed)!
        XCTAssertEqual(neg.origin.z, -300, accuracy: 1e-9)
        check(neg, volume: 1000 * 2000 * 300, tol: 1e-9)
    }

    func testCylinderSphereConeFrustum() async {
        let ed = Editor()
        await ed.run("CYLINDER 0,0 500 1000")
        check(lastSolid(ed), volume: .pi * 500 * 500 * 1000, tol: 0.01)
        await ed.run("CYLINDER 0,0 Diameter 400 1000")
        check(lastSolid(ed), volume: .pi * 200 * 200 * 1000, tol: 0.01)
        await ed.run("SPHERE 0,0 1000")
        check(lastSolid(ed), volume: 4.0 / 3 * .pi * 1e9, tol: 0.02)
        await ed.run("CONE 0,0 600 1200")
        check(lastSolid(ed), volume: .pi * 600 * 600 * 1200 / 3, tol: 0.02)
        await ed.run("CONE 0,0 600 Top 300 1200")
        let r1 = 600.0, r2 = 300.0, h = 1200.0
        check(lastSolid(ed), volume: .pi * h / 3 * (r1 * r1 + r1 * r2 + r2 * r2), tol: 0.02)
    }

    func testExtrudeRectangle() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 1000,1000")
        await ed.run("EXTRUDE L  500")
        check(lastSolid(ed), volume: 0.5e9, tol: 1e-9)
    }
}
