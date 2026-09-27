// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Sub-object selection and editing (M3D-052), imprint (M3D-040) and offset of face edges (M3D-107).
@MainActor
final class ModelingSubObjectTests: XCTestCase {
    func box(_ ed: Editor) -> EntityID { ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000)))) }
    func welded(_ ed: Editor, _ id: EntityID) -> SubObjects.IM {
        guard case .solid(let s)? = ed.doc.entity(id)?.geometry else { XCTFail(); return ([], []) }
        let w = SolidOps.welded(s); return (w.vertices, w.triangles)
    }

    func testImprintSplitsFaceAndStaysManifold() async {
        let ed = Editor()
        let b = box(ed)
        let l = ed.doc.add(.line(LineGeom(Vec2(-200, 400), Vec2(1200, 400))))
        await ed.run("IMPRINT #\(b) 500,500,1000 #\(l)  No")
        let m = welded(ed, b)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        XCTAssertEqual(SolidOps.volume(vertices: m.vertices, triangles: m.triangles), 1e9, accuracy: 1)
        let imps = SubObjects.decode(ed.doc.entity(b)?.props[SubObjects.imprintKey])
        XCTAssertFalse(imps.isEmpty)
        // Imprinted edges run across the top face at y = 400, z = 1000, for the full width.
        XCTAssertTrue(imps.allSatisfy { abs($0.0.y - 400) < 1e-6 && abs($0.1.y - 400) < 1e-6 && abs($0.0.z - 1000) < 1e-6 })
        XCTAssertEqual(imps.map { $0.0.distance(to: $0.1) }.reduce(0, +), 1000, accuracy: 1e-6)
        // The imprint divides the top face into two regions (400 × 1000 and 600 × 1000).
        let f = SubObjects.nearestFace(m, to: Vec3(500, 200, 1000))!
        let region = SubObjects.faceRegion(m, seed: f, barriers: imps)
        let area = region.reduce(0.0) { acc, g in let (x, y, z) = SubObjects.corners(m, g); return acc + (y - x).cross(z - x).length / 2 }
        XCTAssertEqual(area, 400_000, accuracy: 1e-3)
        // Drawn in 3D.
        XCTAssertTrue(MeshBuilder.groups(for: ed.doc.entity(b)!, doc: ed.doc).contains { g in g.edges.contains { $0.count == 2 && abs($0[0].y - 400) < 1e-6 && abs($0[1].y - 400) < 1e-6 } })
        // Persists.
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: try! JSONEncoder().encode(ed.doc))
        XCTAssertEqual(SubObjects.decode(back.entity(b)?.props[SubObjects.imprintKey]).count, imps.count)
    }

    func testImprintInteriorCircleAndMissedFace() async {
        let ed = Editor()
        let b = box(ed)
        let c = ed.doc.add(.circle(CircleGeom(Vec2(500, 500), 200)))
        await ed.run("IMPRINT #\(b) 500,500,1000 #\(c)  Yes")
        let m = welded(ed, b)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        XCTAssertNil(ed.doc.entity(c))
        let imps = SubObjects.decode(ed.doc.entity(b)?.props[SubObjects.imprintKey])
        XCTAssertFalse(imps.isEmpty)
        let centre = Vec3(500, 500, 1000)
        let onFaceRing: (Vec3) -> Bool = { p in
            let d: Double = p.distance(to: centre)
            return abs(p.z - 1000) < 1e-6 && d > 190 && d < 200 + 1e-6
        }
        XCTAssertTrue(imps.allSatisfy { onFaceRing($0.0) && onFaceRing($0.1) })
        // Curve far away from the face: nothing imprinted, solid unchanged.
        let far = ed.doc.add(.line(LineGeom(Vec2(5000, 0), Vec2(6000, 0))))
        let before = ed.doc.entity(b)
        await ed.run("IMPRINT #\(b) 500,500,1000 #\(far)  No")
        XCTAssertEqual(ed.doc.entity(b), before)
    }

    func testOffsetFaceThenExtrudeInnerFace() async {
        let ed = Editor()
        let b = box(ed)
        await ed.run("OFFSETFACE #\(b) 500,500,1000 100")
        var m = welded(ed, b)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        let imps = SubObjects.decode(ed.doc.entity(b)?.props[SubObjects.imprintKey])
        XCTAssertEqual(imps.map { $0.0.distance(to: $0.1) }.reduce(0, +), 3200, accuracy: 1e-6)
        // Push the inner 800 × 800 face down by 300: volume drops by 800·800·300.
        await ed.run("SUBOBJECT #\(b) Face 500,500,1000 Extrude -300")
        m = welded(ed, b)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        XCTAssertEqual(SolidOps.volume(vertices: m.vertices, triangles: m.triangles), 1e9 - 800 * 800 * 300, accuracy: 10)
        // Too large an offset collapses the face and is refused.
        let b2 = box(ed)
        await ed.run("OFFSETFACE #\(b2) 500,500,1000 600")
        XCTAssertNil(ed.doc.entity(b2)?.props[SubObjects.imprintKey])
    }

    func testSubObjectMoveFaceEdgeVertex() async {
        let ed = Editor()
        let b = box(ed)
        await ed.run("SUBOBJECT #\(b) Face 500,500,1000 Move 0,0,0 0,0,500")
        var m = welded(ed, b)
        XCTAssertEqual(SolidOps.volume(vertices: m.vertices, triangles: m.triangles), 1.5e9, accuracy: 1)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        // Edge: the top edge at y = 0 moves out by 200 in y… a ramp-like prism (volume + ½·200·1500·1000).
        await ed.run("SUBOBJECT #\(b) Edge 500,0,1500 Move 0,0,0 0,-200,0")
        m = welded(ed, b)
        XCTAssertTrue(SolidOps.isClosedManifold(vertices: m.vertices, triangles: m.triangles))
        XCTAssertEqual(SolidOps.volume(vertices: m.vertices, triangles: m.triangles), 1.5e9 + 0.5 * 200 * 1500 * 1000, accuracy: 10)
        // Vertex pick finds the nearest corner.
        let v = SubObjects.nearestVertex(m, to: Vec3(1010, 1010, 1490))!
        XCTAssertEqual(m.vertices[v].distance(to: Vec3(1000, 1000, 1500)), 0, accuracy: 1e-9)
        // A move that turns the solid inside out is refused.
        let before = ed.doc.entity(b)
        await ed.run("SUBOBJECT #\(b) Face 500,500,1500 Move 0,0,0 0,0,-3000")
        XCTAssertEqual(ed.doc.entity(b), before)
    }
}
