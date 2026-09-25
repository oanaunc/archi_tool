// Oanarina Archi Tool — GPL-3.0-or-later
// Drawing/model compare (report and overlay) and markups stored in the document.
import XCTest
@testable import ArchiCore

final class AnalysisReviewTests: XCTestCase {
    struct Sample { var doc: ArchiDocument; var line: EntityID; var circle: EntityID; var w1: EntityID; var w2: EntityID; var door: EntityID }
    func sample() -> Sample {
        var d = ArchiDocument()
        let l = d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let c = d.add(.circle(CircleGeom(Vec2(500, 500), 100)))
        let w1 = d.addElement(.wall(WallGeom(start: Vec2(0, 2000), end: Vec2(5000, 2000))), material: "Brick")
        let w2 = d.addElement(.wall(WallGeom(start: Vec2(0, 6000), end: Vec2(5000, 6000))), material: "Brick")
        let door = d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w1, offset: 2000, width: 900, height: 2100)))
        return Sample(doc: d, line: l, circle: c, w1: w1, w2: w2, door: door)
    }

    func testCompareByIdAndGeometry() throws {
        let s = sample()
        var new = s.doc
        new.entities[new.entityIndex(s.circle)!].geometry = .circle(CircleGeom(Vec2(500, 500), 150))
        new.remove(ids: [s.w2])
        let added = new.add(.line(LineGeom(Vec2(0, 100), Vec2(1000, 100))))
        new.elements[new.elementIndex(s.w1)!].material = "Concrete"
        new.layers.append(Layer(name: "NEW-LAYER"))
        let d = DocumentCompare.compare(s.doc, new)
        XCTAssertEqual(d.count(.added), 1); XCTAssertEqual(d.count(.removed), 1); XCTAssertEqual(d.count(.modified), 2); XCTAssertEqual(d.count(.unchanged), 2)
        XCTAssertEqual(d.changes.first { $0.kind == .added }?.id, added)
        XCTAssertEqual(d.changes.first { $0.kind == .removed }?.id, s.w2)
        XCTAssertEqual(d.changes.first { $0.id == s.circle }?.fields, ["geometry"])
        XCTAssertEqual(d.changes.first { $0.id == s.w1 }?.fields, ["material"])
        XCTAssertEqual(d.layersAdded, ["NEW-LAYER"])
        XCTAssertFalse(d.isIdentical)
        XCTAssertTrue(DocumentCompare.compare(s.doc, s.doc).isIdentical)
        XCTAssertEqual(d.table.count, 1 + 4)
        XCTAssertTrue(d.report.hasPrefix("Compare: 1 added, 1 removed, 2 modified, 2 unchanged"))

        // Overlay: every object on a DIFF-* layer, plus the removed wall and the old circle with fresh ids.
        let o = DocumentCompare.overlay(s.doc, new, diff: d)
        XCTAssertEqual(o.entity(added)?.layer, "DIFF-ADDED")
        XCTAssertEqual(o.entity(s.circle)?.layer, "DIFF-MODIFIED")
        XCTAssertEqual(o.entity(s.line)?.layer, "DIFF-UNCHANGED")
        XCTAssertEqual(o.element(s.w1)?.layer, "DIFF-MODIFIED")
        XCTAssertEqual(o.element(s.door)?.props["sourceLayer"], s.doc.element(s.door)?.layer)
        let removed = try XCTUnwrap(o.elements.first { $0.layer == "DIFF-REMOVED" })
        XCTAssertNotEqual(removed.id, s.w2)
        XCTAssertEqual(removed.geometry, s.doc.element(s.w2)?.geometry)
        let prev = try XCTUnwrap(o.entities.first { $0.layer == "DIFF-PREVIOUS" })
        XCTAssertEqual(prev.geometry, .circle(CircleGeom(Vec2(500, 500), 100)))
        XCTAssertEqual(o.layer(named: "DIFF-ADDED")?.color, DocumentCompare.layerColors[.added])
        XCTAssertEqual(Set(o.entities.map(\.id)).count, o.entities.count)
        XCTAssertNoThrow(try ArchiFile.decode(ArchiFile.encode(o)))
    }

    func testCompareMatchesRenumberedObjects() {
        let s = sample()
        var renumbered = ArchiDocument(); renumbered.entities = []; renumbered.elements = []; renumbered.nextID = 100
        DocumentMerge.merge(s.doc, into: &renumbered)
        let d = DocumentCompare.compare(s.doc, renumbered)
        XCTAssertEqual(d.count(.added), 0); XCTAssertEqual(d.count(.removed), 0)
        XCTAssertTrue(d.changes.allSatisfy { $0.kind == .unchanged || $0.fields == ["id"] || $0.fields.first == "id" })
        let strict = DocumentCompare.compare(s.doc, renumbered, matchGeometry: false)
        XCTAssertGreaterThan(strict.count(.added) + strict.count(.removed) + strict.count(.modified), 0)
    }

    func testMarkupsLifecycleAndPersistence() throws {
        var d = sample().doc
        d.info.author = "Oana"
        let id = Markups.add(&d, rect: (Vec2(0, 1500), Vec2(5000, 2500)), title: "Door", comment: "Door too narrow", elements: [5], level: 0)
        XCTAssertNotNil(d.layer(named: "MARKUP"))
        var m = try XCTUnwrap(Markups.find(d, id))
        XCTAssertEqual(m.author, "Oana"); XCTAssertEqual(m.status, "open"); XCTAssertEqual(m.elements, [5]); XCTAssertEqual(m.entityIDs.count, 2)
        XCTAssertEqual(m.viewCenter, Vec2(2500, 2000))
        XCTAssertNotNil(ISO8601DateFormatter().date(from: m.date))
        XCTAssertTrue(Markups.reply(&d, id, text: "Widened to 1000", author: "Ion", date: "2026-01-02T10:00:00Z"))
        XCTAssertTrue(Markups.setStatus(&d, id, resolved: true, by: "Oana"))
        let back = try ArchiFile.decode(ArchiFile.encode(d))
        m = try XCTUnwrap(Markups.find(back, "1"))
        XCTAssertTrue(m.isResolved)
        XCTAssertEqual(m.replies.count, 1); XCTAssertEqual(m.replies[0].author, "Ion"); XCTAssertEqual(m.replies[0].text, "Widened to 1000")
        let note = try XCTUnwrap(back.entities.first { $0.props["markupNote"] == id })
        if case .text(let t) = note.geometry { XCTAssertTrue(t.content.hasPrefix("✓ Door: Door too narrow")); XCTAssertTrue(t.content.contains("↳ Ion: Widened")) } else { XCTFail() }
        XCTAssertEqual(Markups.table(back).count, 2)
        var e = back
        XCTAssertTrue(Markups.setStatus(&e, id, resolved: false))
        XCTAssertEqual(Markups.find(e, id)?.status, "open")
        XCTAssertTrue(Markups.remove(&e, id))
        XCTAssertTrue(Markups.list(e).isEmpty)
        XCTAssertFalse(e.entities.contains { $0.props["markupNote"] != nil })
        XCTAssertFalse(Markups.remove(&e, id))
    }

    @MainActor
    func testReviewCommandsHeadless() async throws {
        let s = sample()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let oldURL = dir.appendingPathComponent("old.archi")
        try ArchiFile.encode(s.doc).write(to: oldURL)
        var cur = s.doc
        cur.remove(ids: [s.w2])
        let ed = Editor(document: cur)
        let overlay = dir.appendingPathComponent("ov.archi")
        var log = await ed.run("COMPARE \(oldURL.path) O \(overlay.path)")
        XCTAssertTrue(log.contains { $0.hasPrefix("Compare: 0 added, 1 removed") }, log.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: overlay.path))
        log = await ed.run("MARKUP A 0,1500 5000,2500 Please check this")
        XCTAssertEqual(Markups.list(ed.doc).count, 1, log.joined(separator: "\n"))
        XCTAssertEqual(Markups.list(ed.doc).first?.comment, "Please check this")
        XCTAssertTrue(Markups.list(ed.doc).first!.elements.contains(s.w1), "elements inside the cloud are linked")
        ed.undo()
        XCTAssertTrue(Markups.list(ed.doc).isEmpty, "adding a markup is one undo step")
        _ = await ed.run("MARKUP A 0,1500 5000,2500 Again")
        log = await ed.run("MARKUP R 1")
        XCTAssertEqual(Markups.list(ed.doc).first?.status, "resolved", log.joined(separator: "\n"))
        log = await ed.run("MARKUP L")
        XCTAssertTrue(log.contains { $0.contains("[resolved]") }, log.joined(separator: "\n"))
        let bcf = dir.appendingPathComponent("issues.bcfzip")
        log = await ed.run("BCFOUT \(bcf.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bcf.path), log.joined(separator: "\n"))
        _ = await ed.run("MARKUP D 1")
        XCTAssertTrue(Markups.list(ed.doc).isEmpty)
        log = await ed.run("BCFIN \(bcf.path)")
        XCTAssertEqual(Markups.list(ed.doc).count, 1, log.joined(separator: "\n"))
        XCTAssertEqual(Markups.list(ed.doc).first?.status, "resolved")
    }
}
