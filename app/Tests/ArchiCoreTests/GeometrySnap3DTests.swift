// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// 3D object snaps (PRC-022) and apparent / extended intersection snap (PRC-008).
@MainActor
final class GeometrySnap3DTests: XCTestCase {
    func boxDoc() -> (ArchiDocument, EntityID) {
        var d = ArchiDocument()
        let id = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 2000, 3000))))
        return (d, id)
    }

    func testFeaturesOfABox() {
        let (d, id) = boxDoc()
        guard let f = Snap3D.features(d.entity(id)!, doc: d) else { return XCTFail("no features") }
        XCTAssertEqual(f.vertices.count, 8)
        XCTAssertEqual(f.midpoints.count, 12)
        XCTAssertEqual(f.faceCenters.count, 6)
        let zs = Set(f.vertices.map { ($0.z * 1000).rounded() / 1000 })
        XCTAssertEqual(zs.count, 2)
        let top = zs.max() ?? 0
        XCTAssertTrue(f.faceCenters.contains { $0.distance(to: Vec3(500, 1000, top)) < 1e-6 })
    }

    func testRaySnapsInA3DView() {
        var (d, _) = boxDoc()
        Snap3D.setModes(Set(Snap3D.Mode.allCases), doc: &d)
        let top = Snap3D.features(d.entities[0], doc: d)!.vertices.map(\.z).max()!
        // Looking straight down at the corner (1000, 2000).
        let r = Snap3D.find(rayOrigin: Vec3(1003, 2002, 10000), direction: Vec3(0, 0, -1), doc: d, tolerance: 10)
        XCTAssertEqual(r?.mode, .vertex)
        XCTAssertEqual(r?.point.distance(to: Vec3(1000, 2000, top)) ?? 1, 0, accuracy: 1e-6)
        // Oblique ray hitting the middle of the front face (y = 0): nearest on face.
        let n = Snap3D.find(rayOrigin: Vec3(300, -5000, 700), direction: Vec3(0, 1, 0), doc: d, tolerance: 1)
        XCTAssertEqual(n?.mode, .nearest)
        XCTAssertEqual(n?.point.y ?? 1, 0, accuracy: 1e-6)
        // Perpendicular from a base point onto the face hit.
        let p = Snap3D.find(rayOrigin: Vec3(300, -5000, 700), direction: Vec3(0, 1, 0), doc: d, tolerance: 1, base: Vec3(200, -800, 650), modes: [.perpendicular])
        XCTAssertEqual(p?.mode, .perpendicular)
        XCTAssertEqual(p?.point.distance(to: Vec3(200, 0, 650)) ?? 1, 0, accuracy: 1e-6)
        // Face centre.
        let c = Snap3D.find(rayOrigin: Vec3(501, 999, 10000), direction: Vec3(0, 0, -1), doc: d, tolerance: 5, modes: [.faceCenter])
        XCTAssertEqual(c?.mode, .faceCenter); XCTAssertEqual(c?.point.z ?? 0, top, accuracy: 1e-6)
        // Off by default.
        XCTAssertNil(Snap3D.find(rayOrigin: Vec3(1003, 2002, 10000), direction: Vec3(0, 0, -1), doc: boxDoc().0, tolerance: 10))
    }

    func testPlanSnapsKeepTheSnappedZ() async {
        let ed = Editor()
        ed.doc = boxDoc().0
        await ed.run("3DOSNAP ZVertex,ZCenter")
        XCTAssertEqual(Snap3D.modes(ed.doc), [.vertex, .faceCenter])
        var s = DraftSettings(); s.snapModes = []; s.objectSnap = true
        let hit = Snap.find(cursor: Vec2(1004, 1996), doc: ed.doc, settings: s, tolerance: 10, base: nil)
        XCTAssertEqual(hit?.point, Vec2(1000, 2000)); XCTAssertEqual(hit?.kind, .endpoint)
        let top = Snap3D.features(ed.doc.entities[0], doc: ed.doc)!.vertices.map(\.z).max()!
        XCTAssertEqual(Snap3D.elevation(at: Vec2(1000, 2000), doc: ed.doc) ?? 0, top, accuracy: 1e-9)
        XCTAssertEqual(Snap3D.elevation(at: Vec2(500, 1000), doc: ed.doc) ?? 0, top, accuracy: 1e-9)
        XCTAssertNil(Snap3D.elevation(at: Vec2(400, 400), doc: ed.doc))
        await ed.run("3DOSNAP NONE")
        XCTAssertTrue(Snap3D.modes(ed.doc).isEmpty)
        XCTAssertNil(Snap.find(cursor: Vec2(1004, 1996), doc: ed.doc, settings: s, tolerance: 10, base: nil))
    }

    func testApparentIntersectionOfExtensions() async {
        var d = ArchiDocument()
        d.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        d.add(.line(LineGeom(Vec2(200, 10), Vec2(200, 100))))
        var s = DraftSettings(); s.snapModes = [.intersection]; s.objectSnap = true; s.objectSnapTracking = false
        Snap.tracker.clear()
        // Ordinary intersection finds nothing: the lines do not meet.
        XCTAssertNil(Snap.find(cursor: Vec2(198, 12), doc: d, settings: s, tolerance: 15, base: nil))
        s.apparentIntersectionSnap = true
        // Near the end of the vertical line, with the horizontal line's end hovered earlier (acquired extension).
        _ = Snap.find(cursor: Vec2(99, 1), doc: d, settings: s, tolerance: 5, base: nil)
        let h = Snap.find(cursor: Vec2(198, 8), doc: d, settings: s, tolerance: 15, base: nil)
        XCTAssertEqual(h?.kind, .intersection)
        XCTAssertEqual(h?.point.distance(to: Vec2(200, 0)) ?? 1, 0, accuracy: 1e-9)
        Snap.tracker.clear()
        // Both lines near the cursor: the extended intersection is offered directly.
        var d2 = ArchiDocument()
        d2.add(.line(LineGeom(Vec2(0, 0), Vec2(95, 0))))
        d2.add(.line(LineGeom(Vec2(100, 5), Vec2(100, 100))))
        XCTAssertEqual(Snap.find(cursor: Vec2(99, 1), doc: d2, settings: s, tolerance: 8, base: nil)?.point, Vec2(100, 0))
        // OSNAP / OSMODE and the one-shot APP override.
        let ed = Editor()
        await ed.run("OSNAP END,APP")
        XCTAssertTrue(ed.settings.apparentIntersectionSnap)
        XCTAssertEqual(SystemVariables.osmode(ed.settings) & 2048, 2048)
        ed.doc = d2
        await ed.run("OSNAP END")
        XCTAssertFalse(ed.settings.apparentIntersectionSnap)
        await ed.run("LINE APP 99,1 0,500 ")
        guard case .line(let l)? = ed.doc.entities.last?.geometry else { return XCTFail("no line") }
        XCTAssertEqual(l.a, Vec2(100, 0))
        Snap.tracker.clear()
    }

    func testDynamicUCSPicksOnFaces() async {
        let ed = Editor()
        ed.doc = boxDoc().0
        let top = Snap3D.features(ed.doc.entities[0], doc: ed.doc)!.vertices.map(\.z).max()!
        XCTAssertNil(DynamicUCS.elevation(at: Vec2(500, 500), doc: ed.doc))
        await ed.run("DUCS ON")
        XCTAssertEqual(DynamicUCS.elevation(at: Vec2(500, 500), doc: ed.doc) ?? 0, top, accuracy: 1e-9)
        let f = DynamicUCS.face(at: Vec2(500, 500), doc: ed.doc)
        XCTAssertEqual(f?.normal.z ?? 0, 1, accuracy: 1e-9)
        XCTAssertNil(DynamicUCS.elevation(at: Vec2(5000, 500), doc: ed.doc))
        // A wedge-like sloped face: an extruded triangle profile lying on its side is not needed; a cone's top is flat,
        // so check the ID command reports the face elevation for a picked point.
        // A picked (not typed) point in the ID command reports the face elevation.
        ed.submit("ID")
        await ed.waitForInputOrIdle()
        ed.feed(.point(Vec2(500, 500)))
        await ed.waitIdle()
        XCTAssertTrue(ed.log.suffix(4).joined().contains("Z = " + fmt(top, 4)), ed.log.suffix(4).joined())
        await ed.run("DUCS OFF")
        XCTAssertFalse(DynamicUCS.isOn(ed.doc))
    }
}
