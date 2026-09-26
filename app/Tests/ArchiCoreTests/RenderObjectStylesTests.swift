// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Object styles (LAY-033): project-wide category line weights, colours, cut fills and patterns.
@MainActor
final class RenderObjectStylesTests: XCTestCase {
    func weights(_ doc: ArchiDocument, level: Int, id: EntityID) -> [Double] {
        DrawListBuilder.entries(doc: doc, options: DrawOptions(level: level)).filter { $0.id == id }.flatMap(\.items)
            .compactMap { if case .stroke(_, _, let st) = $0 { return st.lineweight }; return nil }
    }

    func testWallCutLineweightUpdatesAllPlansAndSections() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        await ed.run("WALL 0,5000 6000,5000 ")
        let a = ed.doc.elements[0].id, b = ed.doc.elements[1].id
        ed.doc.elements[1].level = 1
        XCTAssertTrue(weights(ed.doc, level: 0, id: a).contains(0.5))
        XCTAssertTrue(weights(ed.doc, level: 1, id: b).contains(0.5))
        await ed.run("OBJECTSTYLES wall cut:0.7;color:red;fill:0.2,0.2,0.2")
        XCTAssertEqual(ObjectStyles.style("walls", doc: ed.doc)?.cutLineweight, 0.7)
        for (l, id) in [(0, a), (1, b)] {
            let w = weights(ed.doc, level: l, id: id)
            XCTAssertFalse(w.contains(0.5)); XCTAssertTrue(w.contains(0.7), "plan of level \(l) follows the object style")
        }
        let items = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).filter { $0.id == a }.flatMap(\.items)
        XCTAssertTrue(items.contains { if case .fill(_, let c) = $0 { return abs(c.r - 0.2) < 1e-9 }; return false })
        XCTAssertTrue(items.contains { if case .stroke(_, _, let st) = $0 { return abs(st.color.r - 0.9) < 1e-9 }; return false })
        // Sections use the category cut weight too.
        let sec = ElevationBuilder.entries(doc: ed.doc, view: .section, sectionLine: (Vec2(3000, -1000), Vec2(3000, 1000))).filter { $0.id == a }.flatMap(\.items)
        XCTAssertTrue(sec.contains { if case .stroke(_, _, let st) = $0 { return abs(st.lineweight - 0.7) < 1e-9 }; return false })
        // Doors keep the defaults; a view override (VG) still wins over the object style.
        VisibilityGraphics.setCategoryOverrides(["wall": GraphicOverride(lineweight: 1.0)], doc: &ed.doc)
        XCTAssertTrue(weights(ed.doc, level: 0, id: a).allSatisfy { $0 == 1.0 })
        VisibilityGraphics.setCategoryOverrides([:], doc: &ed.doc)
        // Merge, persistence, reset.
        await ed.run("OBJECTSTYLES wall proj:0.35;pattern:ANSI31")
        let st = try XCTUnwrap(ObjectStyles.style("wall", doc: ed.doc))
        XCTAssertEqual(st.cutLineweight, 0.7); XCTAssertEqual(st.projectionLineweight, 0.35); XCTAssertEqual(st.cutPattern, "ANSI31")
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(ObjectStyles.style("wall", doc: back), st)
        await ed.run("OBJECTSTYLES Reset")
        XCTAssertNil(ObjectStyles.style("wall", doc: ed.doc))
        XCTAssertTrue(weights(ed.doc, level: 0, id: a).contains(0.5))
        // Undo restores the style.
        ed.undo()
        XCTAssertNotNil(ObjectStyles.style("wall", doc: ed.doc))
    }

    func testParse() {
        XCTAssertEqual(ObjectStyles.parse("cut:0.7; proj:0.25")?.projectionLineweight, 0.25)
        XCTAssertNil(ObjectStyles.parse("cut:-1"))
        XCTAssertNil(ObjectStyles.parse("pattern:NOPE"))
        XCTAssertNil(ObjectStyles.parse("bogus:1"))
        XCTAssertEqual(ObjectStyles.parse("colour:blue")?.color, RGBA(0.2, 0.4, 0.95))
    }
}
