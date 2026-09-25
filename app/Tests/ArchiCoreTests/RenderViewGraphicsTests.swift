// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class RenderViewGraphicsTests: XCTestCase {
    func strokes(_ entries: [DrawEntry]) -> [(pts: [Vec2], style: StrokeStyle)] {
        entries.flatMap { $0.items.compactMap { if case .stroke(let p, _, let s) = $0 { return (p, s) }; return nil } }
    }
    func fills(_ entries: [DrawEntry]) -> [RGBA] { entries.flatMap { $0.items.compactMap { if case .fill(_, let c) = $0 { return c }; return nil } } }

    func twoBoxes() -> ArchiDocument {
        var doc = ArchiDocument()
        doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(2000, 1000, 1000))))          // front
        doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 5000, 0), size: Vec3(3000, 1000, 2500))))     // behind, taller
        doc.setVariable("VIEWANNOTATIONS", "0")
        return doc
    }

    func testHiddenLinesLineWeightsDepthCueAndFarClip() {
        var doc = twoBoxes()
        let plain = ElevationBuilder.entries(doc: doc, view: .elevationSouth)
        let weights = Set(strokes(plain).map(\.style.lineweight))
        XCTAssertTrue(weights.contains(0.35) && weights.contains(0.18), "near edges heavy, far edges light: \(weights)")
        XCTAssertTrue(strokes(plain).allSatisfy { $0.style.dash.isEmpty })
        doc.setVariable("ELEVHIDDEN", "1")
        let hidden = strokes(ElevationBuilder.entries(doc: doc, view: .elevationSouth)).filter { !$0.style.dash.isEmpty }
        XCTAssertFalse(hidden.isEmpty, "the rear box's edges behind the front box are dashed")
        // Hidden segments lie inside the front box's silhouette (x 0…2000, z 0…1000 seen from the south).
        for h in hidden { let m = (h.pts[0] + h.pts[1]) / 2; XCTAssertTrue(m.x >= -1 && m.x <= 2001 && m.y >= -1 && m.y <= 1001, "\(m)") }
        doc.setVariable("ELEVHIDDEN", "0")
        doc.setVariable("DEPTHCUE", "1")
        let cued = fills(ElevationBuilder.entries(doc: doc, view: .elevationSouth))
        let flat = fills(plain)
        XCTAssertGreaterThan(cued.map { $0.r + $0.g + $0.b }.max()!, flat.map { $0.r + $0.g + $0.b }.max()! - 1e-9)
        XCTAssertNotEqual(cued.map(\.r), flat.map(\.r))
        doc.setVariable("DEPTHCUE", "0")
        doc.setVariable("ELEVFARCLIP", "2000")
        let clipped = ElevationBuilder.entries(doc: doc, view: .elevationSouth)
        var box = BBox2.empty
        for e in clipped { box.add(e.bounds) }
        XCTAssertLessThanOrEqual(box.max.y, 1000 + 1e-6, "the taller rear box is beyond the far clip")
    }

    func testDimensionsInElevations() {
        var doc = ArchiDocument()
        doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0), height: 6000)))
        doc.setVariable("ELEVDIMS", "1")
        let e = ElevationBuilder.entries(doc: doc, view: .elevationSouth)
        let texts = e.flatMap { $0.items.compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil } }
        XCTAssertTrue(texts.contains("3000"), "\(texts)")
        XCTAssertTrue(texts.contains("6000"))
    }

    func testLegendsDraftingViewsAndTemplates() async {
        let ed = Editor()
        for k in Legends.kinds where k != "components" {
            XCTAssertNotNil(Legends.makeBlock(&ed.doc, kind: k), k)
        }
        XCTAssertGreaterThan(ed.doc.blocks["LEGEND-WALLS"]!.entities.count, ed.doc.wallTypes.count * 3)
        await ed.run("LEGEND Slabs 0,-20000")
        XCTAssertEqual(ed.doc.entities.last?.props["view"], "legend:slabs")
        // Drafting view: edit in isolation, store in a block, place.
        await ed.run("WALL 0,0 5000,0 ")
        await ed.run("DRAFTINGVIEW New Detail1")
        await ed.run("LINE 0,0 1000,0 ")
        await ed.run("CIRCLE 500,500 100")
        let iso = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertEqual(iso.count, 2, "only the drafting content is shown while editing")
        await ed.run("DRAFTINGVIEW Close")
        XCTAssertEqual(ed.doc.blocks[DraftingViews.blockName("Detail1")]?.entities.count, 2)
        XCTAssertFalse(ed.doc.entities.contains { if case .circle = $0.geometry { return true }; return false })
        await ed.run("DRAFTINGVIEW Place Detail1 20000,0 1")
        XCTAssertEqual(ed.doc.entities.last?.props["view"], "drafting:Detail1")
        await ed.run("DRAFTINGVIEW Edit Detail1")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["draftingView"] == "Detail1" }.count, 2)
        await ed.run("DRAFTINGVIEW Close")
        // View templates: the presentation plan hides grids; capture and apply to a placed drawing view.
        await ed.run("GRID 0,-2000 0,2000 ")
        let grid = ed.doc.elements.last!.id
        XCTAssertTrue(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).contains { $0.id == grid })
        await ed.run("VIEWTEMPLATE Apply \"Presentation Plan\"")
        XCTAssertFalse(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0)).contains { $0.id == grid })
        await ed.run("VIEWTEMPLATE None")
        ed.doc.setVariable("ELEVHIDDEN", "1")
        await ed.run("VIEWTEMPLATE Capture Mine")
        XCTAssertEqual(ed.doc.viewTemplate("Mine")?.settings["ELEVHIDDEN"], "1")
        await ed.run("VIEWDRAW South 0,-40000")
        let view = ed.doc.entities.last!.id
        await ed.run("VIEWTEMPLATE View #\(view) \"Presentation Elevation\"")
        XCTAssertEqual(ed.doc.entity(view)?.props["view"], "south|template=Presentation Elevation")
        XCTAssertTrue(ed.doc.blocks["VIEW-SOUTH-ELEVATION"]!.description.hasSuffix("|template=Presentation Elevation"))
        // Templates persist.
        let back = try! ArchiFile.decode(try! ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.viewTemplates, ed.doc.viewTemplates)
    }
}
