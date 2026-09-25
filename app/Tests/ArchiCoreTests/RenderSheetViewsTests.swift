// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class RenderSheetViewsTests: XCTestCase {
    func testInteriorElevationsOfRoom() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 6000,4000 0,4000 C")
        await ed.run("WINDOW 3000,0 ")
        await ed.run("ROOM 3000,2000 ")
        guard let room = ed.doc.elements.last, case .space = room.geometry else { return XCTFail() }
        let views = InteriorElevation.views(room: room, doc: ed.doc)
        XCTAssertEqual(views.count, 4)
        XCTAssertEqual(Set(views.map { ($0.width).rounded() }), [5800, 3800])
        for k in 0..<4 {
            let es = InteriorElevation.entries(doc: ed.doc, room: room, index: k)
            XCTAssertFalse(es.isEmpty)
            var b = BBox2.empty; for e in es { b.add(e.bounds) }
            XCTAssertGreaterThanOrEqual(b.min.x, -1e-3); XCTAssertLessThanOrEqual(b.max.x, views[k].width + 1e-3)
        }
        await ed.run("INTERIORELEV 3000,2000 20000,0")
        XCTAssertEqual(ed.doc.blocks.keys.filter { $0.hasPrefix("VIEW-INTERIOR-") }.count, 4)
        XCTAssertGreaterThanOrEqual(ed.doc.entities.filter { $0.props["interiorMarker"] != nil }.count, 9)
        XCTAssertEqual(ed.doc.entities.filter { $0.props["view"]?.hasPrefix("interior:") ?? false }.count, 4)
        let log = await ed.run("VIEWUPDATE")
        XCTAssertTrue(log.contains { $0.contains("updated") })
    }

    func testCalloutAndViewTitles() async {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 6000,4000 ")
        await ed.run("CALLOUT -500,-500 1500,1500 2500,2500 5 A-501 10000,0")
        XCTAssertNotNil(ed.doc.blocks["VIEW-DETAIL-1"])
        let sym = ed.doc.entities.filter { $0.props["callout"] == "1" }
        XCTAssertEqual(sym.count, 6)
        XCTAssertTrue(sym.contains { if case .text(let t) = $0.geometry { return t.content == "A-501" }; return false })
        guard let ins = ed.doc.entities.first(where: { $0.props["view"]?.hasPrefix("detail:") ?? false }), case .insert(let i) = ins.geometry else { return XCTFail() }
        XCTAssertEqual(i.scale.x, 5)

        ed.doc.layouts[0].viewports = [Viewport(origin: Vec2(20, 40), size: Vec2(180, 120), viewCenter: .zero, scale: 100, view: .plan, level: 0),
                                        Viewport(origin: Vec2(220, 40), size: Vec2(180, 120), viewCenter: .zero, scale: 50, view: .elevationSouth, title: "Front")]
        await ed.run("VIEWTITLE ")
        let titles = ed.doc.layouts[0].entities.filter { $0.props["viewTitle"] != nil }
        XCTAssertEqual(titles.count, 10)
        let texts = titles.compactMap { e -> String? in if case .text(let t) = e.geometry { return t.content }; return nil }
        XCTAssertTrue(texts.contains("GROUND FLOOR")); XCTAssertTrue(texts.contains("FRONT")); XCTAssertTrue(texts.contains("1 : 50"))
        await ed.run("VIEWTITLE ")
        XCTAssertEqual(ed.doc.layouts[0].entities.filter { $0.props["viewTitle"] != nil }.count, 10)
    }

    func testFamilyPlanSymbolsDrawn() {
        var doc = ArchiDocument()
        let id = doc.addElement(.component(ComponentGeom(position: .zero, size: Vec3(1600, 2000, 500), family: "bed-double")))
        let items = PlanRepresentation.items(doc.element(id)!, doc: doc)
        XCTAssertGreaterThan(items.count, 4)
        let kw = doc.addElement(.component(ComponentGeom(position: Vec2(5000, 0), size: Vec3(2400, 350, 700), baseOffset: 1450, family: "kitchen-wall")))
        let dashed = PlanRepresentation.items(doc.element(kw)!, doc: doc).allSatisfy { if case .stroke(_, _, let st) = $0 { return !st.dash.isEmpty }; return false }
        XCTAssertTrue(dashed)
    }
}
