// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMRoofFormsTests: XCTestCase {
    func height(_ g: RoofGeom, _ p: Vec2) -> Double? {
        RoofShapes.faces(g).faces.first { GeometryOps.pointInPolygon(p, $0.poly) }?.height(p)
    }

    func testMansardGambrelDomeAndBarrel() async {
        let sq = [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)]
        var m = RoofGeom(boundary: sq, kind: .hip, pitch: 60, overhang: 0)
        m.profile = RoofProfile(form: .mansard, upperPitch: 20, breakDistance: 1500)
        // Steep up to the break, shallow beyond.
        XCTAssertEqual(height(m, Vec2(5000, 1000))!, 1000 * tan(Double.pi / 3), accuracy: 1e-6)
        XCTAssertEqual(height(m, Vec2(5000, 3000))!, 1500 * tan(Double.pi / 3) + 1500 * tan(Double.pi / 9), accuracy: 1e-6)
        XCTAssertEqual(height(m, Vec2(1000, 4000))!, 1000 * tan(Double.pi / 3), accuracy: 1e-6, "every eave is two-pitched")
        var gm = RoofGeom(boundary: sq, kind: .gable, pitch: 60, overhang: 0, eaveEdge: 0)
        gm.profile = RoofProfile(form: .gambrel, upperPitch: 25, breakDistance: 1000)
        XCTAssertEqual(height(gm, Vec2(5000, 500))!, height(gm, Vec2(5000, 7500))!, accuracy: 1e-6, "symmetric about the ridge")
        XCTAssertEqual(height(gm, Vec2(5000, 3900))!, 1000 * tan(Double.pi / 3) + 2900 * tan(25 * Double.pi / 180), accuracy: 1e-6)
        XCTAssertEqual(height(gm, Vec2(200, 2000)), height(gm, Vec2(9800, 2000)), "gable ends: no slope along the ridge")
        // Dome over a 24-gon of radius 5000 at 45°: a hemisphere (crown 5000, near-zero at the rim).
        let circle = RG.circle(Vec2(20000, 0), 5000, segments: 24)
        var d = RoofGeom(boundary: circle, kind: .hip, pitch: 45, overhang: 0)
        d.profile = RoofProfile(form: .dome)
        XCTAssertEqual(height(d, Vec2(20001, 1))!, 5000, accuracy: 1)
        let mid = height(d, Vec2(23000, 1))!
        XCTAssertEqual(mid, (5000.0 * 5000 - 3000 * 3000).squareRoot(), accuracy: 60)
        // Barrel vault across the 8000 span at 45°: half cylinder of radius 4000, level along the 10000 length.
        var bv = RoofGeom(boundary: sq, kind: .gable, pitch: 45, overhang: 0, eaveEdge: 0)
        bv.profile = RoofProfile(form: .barrel)
        XCTAssertEqual(height(bv, Vec2(3000, 4001))!, 4000, accuracy: 10)
        XCTAssertEqual(height(bv, Vec2(7000, 4001))!, 4000, accuracy: 10)
        XCTAssertEqual(height(bv, Vec2(5001, 1000))!, (4000.0 * 4000 - 3000 * 3000).squareRoot(), accuracy: 40)

        // Command, 3D, plan, persistence.
        let ed = Editor()
        await ed.run("ROOF 0,0 10000,0 10000,8000 0,8000 ")
        guard let roof = ed.doc.elements.first(where: { if case .roof = $0.geometry { return true }; return false }) else { return XCTFail("no roof") }
        ed.selection = [roof.id]
        await ed.run("ROOFSHAPE Mansard 60 20 1500")
        guard case .roof(let r1) = ed.doc.element(roof.id)!.geometry else { return XCTFail() }
        XCTAssertEqual(r1.profile?.form, .mansard); XCTAssertEqual(r1.pitch, 60); XCTAssertEqual(r1.kind, .hip)
        let mesh = MeshBuilder.build(doc: ed.doc).filter { $0.id == roof.id }
        XCTAssertFalse(mesh.isEmpty)
        ed.selection = [roof.id]
        await ed.run("ROOFSHAPE Barrel 45")
        let plan = PlanRepresentation.items(ed.doc.element(roof.id)!, doc: ed.doc)
        XCTAssertLessThan(plan.count, 8, "curved roofs show a crown, not facet lines")
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.element(roof.id)?.geometry, ed.doc.element(roof.id)?.geometry)
        ed.selection = [roof.id]
        await ed.run("ROOFSHAPE Plain")
        guard case .roof(let r3) = ed.doc.element(roof.id)!.geometry else { return XCTFail() }
        XCTAssertNil(r3.profile)
        // Old roofs without a profile decode.
        let old = try! JSONDecoder().decode(RoofGeom.self, from: Data(#"{"boundary":[{"x":0,"y":0},{"x":1,"y":0},{"x":1,"y":1}],"kind":"hip","pitch":30,"thickness":200,"overhang":0,"baseOffset":0,"eaveEdge":0}"#.utf8))
        XCTAssertNil(old.profile)
    }

    func testGeolocation() async {
        let ed = Editor()
        await ed.run("GEOLOCATION City London")
        XCTAssertEqual(ed.doc.info.latitude, 51.5074, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.info.timeZone, "Europe/London")
        XCTAssertEqual(ed.doc.info.elevation, 11)
        await ed.run("GEOLOCATION Set 44.43 26.10 80 Europe/Bucharest")
        XCTAssertEqual(ed.doc.info.longitude, 26.10, accuracy: 1e-9)
        XCTAssertEqual(ed.doc.info.elevation, 80)
        XCTAssertTrue([2.0, 3.0].contains(SiteLocation.utcOffset(ed.doc)))
        XCTAssertNotNil(SiteLocation.set(&ed.doc, latitude: 95, longitude: 0))
        XCTAssertNotNil(SiteLocation.set(&ed.doc, latitude: 10, longitude: 0, timeZone: "Mars/Olympus"))
        await ed.run("GEOLOCATION North 12.5")
        XCTAssertEqual(ed.doc.info.northAngle, 12.5)
        let back = try! ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.info, ed.doc.info)
        // Older project info without the new keys decodes with defaults.
        let old = try! JSONDecoder().decode(ProjectInfo.self, from: Data(#"{"name":"A","number":"","client":"","address":"","author":"","latitude":1,"longitude":2,"northAngle":0}"#.utf8))
        XCTAssertEqual(old.elevation, 0); XCTAssertNil(old.timeZone); XCTAssertEqual(old.latitude, 1)
    }
}
