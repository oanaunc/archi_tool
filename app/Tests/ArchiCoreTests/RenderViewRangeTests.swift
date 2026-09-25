// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class RenderViewRangeTests: XCTestCase {
    func entry(_ es: [DrawEntry], _ id: EntityID) -> DrawEntry? { es.first { $0.id == id } }
    func strokeColors(_ e: DrawEntry?) -> [RGBA] { (e?.items ?? []).compactMap { if case .stroke(_, _, let s) = $0 { return s.color }; return nil } }

    func testViewRangeUnderlayRevealAndCategoryHide() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let wall = ed.doc.elements[0].id
        // A high wall cabinet (above 2300) and a sunken pool slab below the floor on level 0.
        let cab = ed.doc.addElement(.component(ComponentGeom(position: Vec2(2000, 1000), size: Vec3(1200, 350, 700), baseOffset: 2400, family: "kitchen-wall")))
        let pit = ed.doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 2000), Vec2(3000, 2000), Vec2(3000, 4000), Vec2(0, 4000)], thickness: 200, topOffset: -1500)))
        var es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertNotNil(entry(es, cab)); XCTAssertNotNil(entry(es, pit))
        await ed.run("VIEWRANGE 2300 1200 0 -1000")
        XCTAssertEqual(ViewRange.range(ed.doc), ViewRange.Range(top: 2300, cut: 1200, bottom: 0, depth: -1000))
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertNil(entry(es, cab), "above the top of the range")
        XCTAssertNil(entry(es, pit), "below the view depth")
        XCTAssertNotNil(entry(es, wall))
        await ed.run("VIEWRANGE 2300 1200 0 -2000")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertNotNil(entry(es, pit))
        XCTAssertTrue(strokeColors(entry(es, pit)).allSatisfy { $0.r > 0.3 && $0.r < 0.95 }, "beyond: halftone")
        // Level 1 plan: the level 0 wall top (3000) is at the bottom, so it is beyond with a deep view depth.
        await ed.run("VIEWRANGE 2300 1200 0 -500")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1))
        XCTAssertNotNil(entry(es, wall), "lower-level wall top within the view depth")
        await ed.run("VIEWRANGE Off")
        XCTAssertNil(ViewRange.range(ed.doc))
        // Underlay: level 0 drawn halftone (not selectable) under the level 1 plan.
        await ed.run("UNDERLAY \"Ground Floor\"")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 1))
        XCTAssertNil(entry(es, wall))
        XCTAssertTrue(es.contains { $0.id == nil && !$0.items.isEmpty })
        await ed.run("UNDERLAY None")
        XCTAssertNil(ed.doc.variable("UNDERLAY"))
        // Category hide + reveal hidden in magenta + unhide.
        await ed.run("TEMPHIDE Category wall")
        XCTAssertNil(ed.doc.element(wall))
        await ed.run("REVEALHIDDEN On")
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertTrue(es.contains { e in e.id == nil && e.items.contains { if case .stroke(_, _, let s) = $0 { return s.color == ViewRange.revealColor }; return false } })
        await ed.run("REVEALHIDDEN Unhide #\(wall)")
        XCTAssertNotNil(ed.doc.element(wall))
        // Isolate walls: the cabinet and slab are hidden.
        await ed.run("TEMPISOLATE wall")
        XCTAssertNil(ed.doc.element(cab)); XCTAssertNil(ed.doc.element(pit)); XCTAssertNotNil(ed.doc.element(wall))
        XCTAssertEqual(ViewRange.unhide(nil, in: &ed.doc), 2)
        XCTAssertNil(ed.doc.variable(HiddenObjects.variable))
    }
}
