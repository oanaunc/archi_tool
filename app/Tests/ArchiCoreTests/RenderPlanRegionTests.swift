// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Plan regions: a local view range inside a boundary of the plan.
@MainActor
final class RenderPlanRegionTests: XCTestCase {
    func testPlanRegionOverridesViewRangeLocally() async throws {
        let ed = Editor()
        let inside = ed.doc.addElement(.component(ComponentGeom(position: Vec2(1000, 1000), size: Vec3(600, 300, 400), baseOffset: 2500)))
        let outside = ed.doc.addElement(.component(ComponentGeom(position: Vec2(8000, 1000), size: Vec3(600, 300, 400), baseOffset: 2500)))
        var es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertTrue(es.contains { $0.id == inside }); XCTAssertTrue(es.contains { $0.id == outside })
        await ed.run("VIEWRANGE Region 0,0 4000,0 4000,4000 0,4000  2000 1200 0 0")
        let reg = try XCTUnwrap(ed.doc.entities.last)
        XCTAssertEqual(reg.layer, PlanRegions.layer)
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertFalse(es.contains { $0.id == inside }, "above the region's top")
        XCTAssertTrue(es.contains { $0.id == outside }, "outside the region the view is unchanged")
        // Live: moving the element out of the region shows it again.
        ed.transaction("m") { doc in if case .component(var g) = doc.elements[0].geometry { g.position = Vec2(6000, 1000); doc.elements[0].geometry = .component(g) } }
        es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertTrue(es.contains { $0.id == inside })
        // Other levels are not affected.
        XCTAssertEqual(PlanRegions.regions(ed.doc, level: 1).count, 0)
        XCTAssertFalse(ed.doc.layer(named: PlanRegions.layer)!.plot)
    }
}
