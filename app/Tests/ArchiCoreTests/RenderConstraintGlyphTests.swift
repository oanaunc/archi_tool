// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class RenderConstraintGlyphTests: XCTestCase {
    func testGlyphsFollowConstraintBarVariable() {
        var doc = ArchiDocument()
        let a = doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        let b = doc.add(.line(LineGeom(Vec2(1000, 0), Vec2(1000, 800))))
        var set = ConstraintSet()
        set.constraints = [GeoConstraint(id: 1, kind: .horizontal, refs: [CRef(a)]),
                           GeoConstraint(id: 2, kind: .perpendicular, refs: [CRef(a), CRef(b)]),
                           GeoConstraint(id: 3, kind: .coincident, refs: [CRef(a, 1), CRef(b, 0)]),
                           GeoConstraint(id: 4, kind: .length, refs: [CRef(b)], value: 800, name: "d1")]
        set.nextID = 5
        set.save(&doc)
        let off = DrawListBuilder.entries(doc: doc, options: DrawOptions())
        XCTAssertFalse(off.contains { $0.id == nil })
        doc.setVariable("CONSTRAINTBAR", "1")
        let on = DrawListBuilder.entries(doc: doc, options: DrawOptions())
        guard let g = on.first(where: { $0.id == nil }) else { return XCTFail("no glyphs") }
        // 1 + 2 + 2 geometric glyph boxes and one dimensional label.
        let boxes = g.items.filter { if case .stroke(_, true, _) = $0 { return true }; return false }
        XCTAssertEqual(boxes.count, 6)
        XCTAssertTrue(g.items.contains { if case .text(let t, _, _) = $0 { return t.content == "d1=800" }; return false })
        // Glyphs sit near their objects and are not plotted.
        XCTAssertLessThan(g.bounds.max.y, 1200); XCTAssertGreaterThan(g.bounds.min.x, -200)
        var paper = DrawOptions(); paper.forPaper = true
        XCTAssertFalse(DrawListBuilder.entries(doc: doc, options: paper).contains { $0.id == nil })
    }
}
