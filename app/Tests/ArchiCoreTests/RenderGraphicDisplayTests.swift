// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Graphic display options (DOC-029): sketchy lines, silhouettes and plan shadows, kept per project view.
@MainActor
final class RenderGraphicDisplayTests: XCTestCase {
    func strokes(_ es: [DrawEntry]) -> [(points: [Vec2], lw: Double)] {
        es.flatMap { $0.items }.compactMap { if case .stroke(let p, _, let s) = $0 { return (p, s.lineweight) }; return nil }
    }

    func testSketchySilhouettesShadowsPerView() async {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 5000,4000 ")
        await ed.run("PROJECTVIEW New Plan A")
        await ed.run("PROJECTVIEW New Plan B")
        await ed.run("PROJECTVIEW Open A")
        let plain = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))
        await ed.run("GRAPHICDISPLAY 5 0.7 Yes")
        XCTAssertEqual(ed.doc.variable("SKETCHY"), "5")
        let styled = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))
        // Sketchy strokes overshoot the original extents; silhouettes are heavier; shadows add a fill first.
        let bx0 = BBox2(points: strokes(plain).flatMap(\.points)), bx1 = BBox2(points: strokes(styled).flatMap(\.points))
        XCTAssertGreaterThan(bx1.width, bx0.width)
        XCTAssertTrue(strokes(styled).contains { abs($0.lw - 0.7) < 1e-9 })
        guard case .fill(let loops, _)? = styled.first?.items.first else { return XCTFail("no shadow fill") }
        XCTAssertGreaterThan(PolygonBoolean.area(loops), 0)
        // Deterministic: the same drawing twice.
        XCTAssertEqual(styled, DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel)))
        // View B keeps its own (plain) graphics; A gets its options back when reopened.
        await ed.run("PROJECTVIEW Open B")
        XCTAssertNil(ed.doc.variable("SKETCHY"))
        XCTAssertEqual(strokes(DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))).count, strokes(plain).count)
        await ed.run("PROJECTVIEW Open A")
        XCTAssertEqual(ed.doc.variable("SILHOUETTES"), "0.7")
        XCTAssertEqual(GraphicDisplay.options(ed.doc), GraphicDisplay.Options(sketchy: 5, silhouette: 0.7, shadows: true))
    }
}
