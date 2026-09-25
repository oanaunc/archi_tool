// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Layer states (on/off, freeze, lock, plot, current, isolate, delete) reach display, plotting and the saved file.
@MainActor
final class DraftLayerStateTests: XCTestCase {
    func drawn(_ ed: Editor, paper: Bool = false) -> Set<EntityID> {
        var o = DrawOptions(); o.forPaper = paper
        return Set(DrawListBuilder.entries(doc: ed.doc, options: o).compactMap(\.id))
    }
    func layer(_ ed: Editor, _ n: String) -> Layer? { ed.doc.layer(named: n) }

    func testLayerStatesReachDisplayPlotAndFile() async throws {
        let ed = Editor()
        await ed.run("LAYER M A-WALL ")
        XCTAssertEqual(ed.doc.currentLayer, "A-WALL")
        await ed.run("LINE 0,0 100,0 ")
        guard let id = ed.doc.entities.last?.id else { return XCTFail() }
        XCTAssertEqual(ed.doc.entity(id)?.layer, "A-WALL")
        await ed.run("LAYER S 0 OFF A-WALL ")
        XCTAssertFalse(drawn(ed).contains(id))
        await ed.run("LAYER ON A-WALL F A-WALL ")
        XCTAssertTrue(layer(ed, "A-WALL")?.frozen == true)
        XCTAssertFalse(drawn(ed).contains(id))
        await ed.run("LAYER T A-WALL LO A-WALL ")
        XCTAssertTrue(drawn(ed).contains(id))
        XCTAssertFalse(ed.isSelectable(id))
        await ed.run("ERASE ALL ")
        XCTAssertNotNil(ed.doc.entity(id), "objects on locked layers are not erased")
        await ed.run("LAYER U A-WALL P A-WALL ")
        XCTAssertTrue(ed.isSelectable(id))
        XCTAssertTrue(drawn(ed).contains(id))
        XCTAssertFalse(drawn(ed, paper: true).contains(id), "no-plot layer is left out of the plot")
        // File round trip keeps every flag.
        await ed.run("LAYER OFF A-WALL LO A-WALL ")
        let back = try ArchiFile.decode(try ArchiFile.encode(ed.doc))
        let l = back.layer(named: "A-WALL")
        XCTAssertEqual(l?.visible, false); XCTAssertEqual(l?.locked, true); XCTAssertEqual(l?.plot, false)
    }

    func testCurrentIsolateAndDeleteWithContents() async {
        let ed = Editor()
        ed.doc.layers.append(Layer(name: "A"))
        ed.doc.layers.append(Layer(name: "B"))
        let a = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(100, 0))), layer: "A")
        let b = ed.doc.add(.line(LineGeom(Vec2(0, 50), Vec2(100, 50))), layer: "B")
        await ed.run("LAYMCUR #\(b)")
        XCTAssertEqual(ed.doc.currentLayer, "B")
        await ed.run("LAYISO #\(a)  Off")
        XCTAssertEqual(layer(ed, "B")?.visible, false)
        XCTAssertEqual(layer(ed, "A")?.visible, true)
        XCTAssertEqual(drawn(ed).intersection([a, b]), [a])
        await ed.run("LAYUNISO")
        XCTAssertEqual(layer(ed, "B")?.visible, true)
        await ed.run("LAYER S 0 ")
        await ed.run("LAYDEL B Y")
        XCTAssertNil(ed.doc.entity(b)); XCTAssertNil(layer(ed, "B")); XCTAssertNotNil(ed.doc.entity(a))
    }
}
