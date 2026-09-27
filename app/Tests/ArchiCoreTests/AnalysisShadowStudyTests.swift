// Oanarina Archi Tool — GPL-3.0-or-later
// Shadow studies (ANL-019): ground shadows against the analytic shadow of a box, time lists, frames, drawing output.
import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import ArchiCore

final class AnalysisShadowStudyTests: XCTestCase {
    func box(_ x0: Double, _ y0: Double, _ w: Double, _ d: Double, _ h: Double) -> [(Vec3, Vec3, Vec3)] {
        let s = SolidGeom(kind: .box, origin: Vec3(x0, y0, 0), size: Vec3(w, d, h))
        return MeshTools.triangles(MeshTools.mesh(of: s))
    }

    func testBoxShadowMatchesGeometry() {
        // Sun due south (from −Y) at 30° altitude: a 10 × 4 × 6 box casts a shadow 6 / tan 30° = 10.392 long to the north.
        let alt = 30.0 * .pi / 180
        let s = Vec3(0, -cos(alt), sin(alt))
        let r = ShadowStudy.shadow(box(0, 0, 10, 4, 6), toSun: s, groundZ: 0, cells: 800)
        let L = 6 / tan(alt)
        XCTAssertEqual(r.area, 10 * (4 + L), accuracy: 10 * (4 + L) * 0.01)
        var b = BBox2.empty
        for l in r.loops { l.forEach { b.add($0) } }
        XCTAssertEqual(b.max.y, 4 + L, accuracy: 0.05)
        XCTAssertEqual(b.min.x, 0, accuracy: 0.05); XCTAssertEqual(b.max.x, 10, accuracy: 0.05)
        XCTAssertEqual(r.loops.count, 1)
        XCTAssertEqual(r.loops[0].count, 4, "stair steps simplified to the rectangle")
        XCTAssertEqual(PolygonBoolean.area(r.loops), r.area, accuracy: r.area * 0.01)
        // Two boxes whose shadows overlap merge into one outline; the sun below the horizon casts none.
        let two = ShadowStudy.shadow(box(0, 0, 10, 4, 6) + box(3, 8, 4, 4, 2), toSun: s, groundZ: 0)
        XCTAssertEqual(two.loops.count, 1)
        XCTAssertTrue(ShadowStudy.shadow(box(0, 0, 1, 1, 1), toSun: Vec3(0, -1, -0.1), groundZ: 0).loops.isEmpty)
    }

    func testTimesAndFrames() {
        XCTAssertEqual(ShadowStudy.times("9:00,12:00, 15:30"), ["9:00", "12:00", "15:30"])
        XCTAssertEqual(ShadowStudy.times("8-12/2"), ["08:00", "10:00", "12:00"])
        XCTAssertEqual(ShadowStudy.times("10,14"), ["10:00", "14:00"])
        var d = ArchiDocument()
        d.info.latitude = 45; d.info.longitude = 0; d.info.northAngle = 0
        d.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(1000, 1000, 3000)))))
        // Equinox solar noon at 45° N: altitude ≈ 45°, shadow ≈ 3000 long to the north.
        let f = ShadowStudy.frames(d, day: "2025-03-20", times: ["12:07"], utcOffset: 0)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f[0].sun.altitude, 45, accuracy: 1)
        XCTAssertEqual(f[0].area, 1000 * (1000 + 3000 / tan(f[0].sun.altitude * .pi / 180)), accuracy: 1000 * 4000 * 0.03)
        let night = ShadowStudy.frames(d, day: "2025-03-20", times: ["23:00"], utcOffset: 0)
        XCTAssertEqual(night[0].area, 0)
        let svgs = ShadowStudy.svgs(d, frames: f + night, day: "2025-03-20")
        XCTAssertEqual(svgs.count, 2)
        for s in svgs { XCTAssertTrue(XMLParser(data: Data(s.utf8)).parse()) }
        XCTAssertTrue(ShadowStudy.html(svgs, frames: f + night, title: "x").contains("setInterval"))
    }

    @MainActor func testCommandDrawsShadowHatchesUndoably() async {
        let ed = Editor()
        ed.doc.info.latitude = 44.43; ed.doc.info.longitude = 26.1
        ed.doc.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(6000, 4000, 7000)))))
        let before = ed.doc.entities.count
        await ed.run("SHADOWDIAGRAM 2025-06-21 9:00,12:00,15:00 3 Draw")
        let hatches = ed.doc.entities.filter { $0.layer.hasPrefix("A-SHADOW-") }
        XCTAssertEqual(hatches.count, 3)
        XCTAssertNotNil(ed.doc.layer(named: "A-SHADOW-1200"))
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, before)
    }
}
