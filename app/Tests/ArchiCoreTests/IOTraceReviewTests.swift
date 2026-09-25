// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class TraceTestHost: EditorHost {
    var actions: [HostAction] = []
    func perform(_ action: HostAction, editor: Editor) { actions.append(action) }
}

final class IOTraceReviewTests: XCTestCase {
    @MainActor func testTraceLinksViewAndElementsAndKeepsDrawingUnchanged() async throws {
        let ed = Editor()
        let host = TraceTestHost()
        ed.host = host
        ed.doc.setVariable("USERNAME", "Ana")
        let w = ed.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let other = ed.doc.add(.line(LineGeom(Vec2(0, 1000), Vec2(1000, 1000))))
        ed.doc.currentLayer = "A-WALL"; ed.doc.ensureLayer("A-WALL")
        ed.selection = [w]
        await ed.run("TRACEREVIEW New \"Check wall\" \"move the door\" -500,-500 5500,1500")
        let t = try XCTUnwrap(TraceReview.find(ed.doc, "Check wall"))
        XCTAssertEqual(t.author, "Ana"); XCTAssertEqual(t.elements, [w]); XCTAssertEqual(t.comment, "move the door")
        XCTAssertEqual(t.view, BBox2(min: Vec2(-500, -500), max: Vec2(5500, 1500)))
        XCTAssertEqual(ed.doc.currentLayer, "TRACE-CHECK_WALL")
        let before = ed.doc.entities.map(\.id)
        await ed.run("CIRCLE 2500,0 400")
        let sketch = try XCTUnwrap(ed.doc.entities.last)
        XCTAssertEqual(sketch.layer, "TRACE-CHECK_WALL", "sketches go on the overlay")
        XCTAssertFalse(ed.doc.layer(named: "TRACE-CHECK_WALL")?.plot ?? true, "overlays do not plot")
        await ed.run("TRACEREVIEW Exit")
        XCTAssertEqual(ed.doc.currentLayer, "A-WALL")
        // Zoom restores the view and selects the linked elements.
        ed.selection = [other]
        host.actions = []
        await ed.run("TRACEREVIEW Zoom \"Check wall\"")
        XCTAssertEqual(ed.selection, [w])
        guard case .zoomWindow(let box) = try XCTUnwrap(host.actions.last) else { return XCTFail("no zoom") }
        XCTAssertTrue(box.contains(t.view))
        await ed.run("TRACEREVIEW Hide \"Check wall\"")
        XCTAssertEqual(ed.doc.layer(named: t.layer)?.visible, false)
        await ed.run("TRACEREVIEW Close \"Check wall\"")
        XCTAssertEqual(TraceReview.find(ed.doc, "Check wall")?.status, "closed")
        await ed.run("TRACEREVIEW Import \"Check wall\" A-REVIEW")
        XCTAssertEqual(ed.doc.entity(sketch.id)?.layer, "A-REVIEW")
        XCTAssertEqual(ed.doc.entity(sketch.id)?.props["fromTrace"], "Check wall")
        ed.undo()
        XCTAssertEqual(ed.doc.entity(sketch.id)?.layer, "TRACE-CHECK_WALL", "undoable")
        await ed.run("TRACEREVIEW Delete \"Check wall\"")
        XCTAssertNil(TraceReview.find(ed.doc, "Check wall"))
        XCTAssertEqual(ed.doc.entities.map(\.id), before, "deleting the trace removes only its sketches")
        XCTAssertNil(ed.doc.layer(named: "TRACE-CHECK_WALL"))
    }

    func testTraceMetadataSurvivesSave() throws {
        var d = ArchiDocument()
        TraceReview.create(&d, name: "A", author: "B", comment: "c", view: BBox2(min: .zero, max: Vec2(10, 10)), level: 1, elements: [3, 4])
        XCTAssertNil(TraceReview.create(&d, name: "a", author: "B", comment: "", view: .empty, level: 0, elements: []), "names are unique")
        let back = try ArchiFile.decode(ArchiFile.encode(d))
        XCTAssertEqual(TraceReview.list(back), TraceReview.list(d))
        XCTAssertEqual(TraceReview.list(back).first?.elements, [3, 4])
    }
}
