// Oanarina Archi Tool — GPL-3.0-or-later
// BCF 2.1 export/import: topics, comments, status, viewpoint camera and selection round trip.
import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import ArchiCore

final class IOBCFTests: XCTestCase {
    func testBCFRoundTripRestoresCameraAndSelection() throws {
        var d = ArchiDocument()
        d.info.name = "House"
        let w1 = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let w2 = d.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000))))
        d.elements[d.elementIndex(w2)!].props["ifcGuid"] = "2O2Fr$t4X7Zf8NOew3FLOH"
        let plan = Markups.add(&d, rect: (Vec2(-500, -500), Vec2(5500, 500)), title: "Plinth", comment: "Check plinth height", author: "Oana",
                               date: "2026-03-01T09:00:00Z", elements: [w1, w2], level: 0)
        Markups.reply(&d, plan, text: "Raised to 300", author: "Ion", date: "2026-03-02T09:00:00Z")
        let cam = Camera(eye: Vec3(10000, -8000, 1700), target: Vec3(2500, 2000, 1500), fov: 55)
        let persp = Markups.add(&d, rect: (Vec2(4000, 3000), Vec2(6000, 5000)), comment: "Corner detail", author: "Ana", date: "2026-03-03T09:00:00Z",
                                elements: [w2], camera: cam, level: 0)
        Markups.setStatus(&d, persp, resolved: true, by: "Ana")

        let zip = BCF.export(d)
        let entries = try ZipArchive.read(zip)
        let names = Set(entries.map(\.name))
        XCTAssertTrue(names.contains("bcf.version"))
        XCTAssertEqual(names.filter { $0.hasSuffix("/markup.bcf") }.count, 2)
        XCTAssertEqual(names.filter { $0.hasSuffix("/viewpoint.bcfv") }.count, 2)
        for e in entries where e.name.hasSuffix(".bcf") || e.name.hasSuffix(".bcfv") || e.name == "bcf.version" {
            XCTAssertTrue(XMLParser(data: e.data).parse(), "\(e.name) is well-formed")
        }
        let version = String(decoding: entries.first { $0.name == "bcf.version" }!.data, as: UTF8.self)
        XCTAssertTrue(version.contains("VersionId=\"2.1\""))

        let topics = try BCF.read(zip)
        XCTAssertEqual(topics.count, 2)
        let tp = try XCTUnwrap(topics.first { $0.title == "Plinth" })
        XCTAssertEqual(tp.status, "Open"); XCTAssertEqual(tp.author, "Oana"); XCTAssertEqual(tp.comments.count, 2)
        XCTAssertEqual(tp.comments[1].text, "Raised to 300")
        XCTAssertEqual(Set(tp.viewpoint!.selection), [BCF.ifcGuid(w1, doc: d), "2O2Fr$t4X7Zf8NOew3FLOH"])
        XCTAssertTrue(tp.viewpoint!.orthogonal)
        XCTAssertEqual(tp.viewpoint!.direction.z, -1, accuracy: 1e-9)
        XCTAssertNotNil(UUID(uuidString: tp.guid))
        let tc = try XCTUnwrap(topics.first { $0.status == "Closed" })
        XCTAssertFalse(tc.viewpoint!.orthogonal)
        XCTAssertEqual(tc.viewpoint!.position.x, 10, accuracy: 1e-9)       // metres
        XCTAssertEqual(tc.viewpoint!.fieldOfView, 55, accuracy: 1e-9)

        // Import into the model without markups: same camera, view and selection.
        var e = d
        for m in Markups.list(e) { Markups.remove(&e, m.id) }
        let ids = BCF.importTopics(topics, into: &e)
        XCTAssertEqual(ids.count, 2)
        let mp = try XCTUnwrap(Markups.list(e).first { $0.title == "Plinth" })
        let orig = try XCTUnwrap(Markups.find(d, plan))
        XCTAssertEqual(Set(mp.elements), [w1, w2])
        XCTAssertEqual(mp.viewCenter.x, orig.viewCenter.x, accuracy: 1e-3); XCTAssertEqual(mp.viewCenter.y, orig.viewCenter.y, accuracy: 1e-3)
        XCTAssertEqual(mp.viewHeight, orig.viewHeight, accuracy: 1e-3)
        XCTAssertEqual(mp.replies.count, 1); XCTAssertEqual(mp.replies[0].author, "Ion")
        XCTAssertEqual(mp.author, "Oana"); XCTAssertEqual(mp.date, "2026-03-01T09:00:00Z"); XCTAssertEqual(mp.status, "open")
        let mc = try XCTUnwrap(Markups.list(e).first { $0.comment == "Corner detail" })
        XCTAssertTrue(mc.isResolved)
        XCTAssertEqual(mc.elements, [w2])
        let c2 = try XCTUnwrap(mc.camera)
        XCTAssertEqual(c2.eye.x, cam.eye.x, accuracy: 1e-3); XCTAssertEqual(c2.eye.y, cam.eye.y, accuracy: 1e-3); XCTAssertEqual(c2.eye.z, cam.eye.z, accuracy: 1e-3)
        let d0 = (cam.target - cam.eye) / (cam.target - cam.eye).length, d1 = (c2.target - c2.eye) / (c2.target - c2.eye).length
        XCTAssertEqual(d0.dot(d1), 1, accuracy: 1e-6)
        XCTAssertEqual(c2.fov, 55, accuracy: 1e-9)
        // Re-importing the same topics updates instead of duplicating.
        BCF.importTopics(topics, into: &e)
        XCTAssertEqual(Markups.list(e).count, 2)
        XCTAssertThrowsError(try BCF.read(ZipArchive.write([.init(name: "x.txt", data: Data("x".utf8))])))
    }
}
