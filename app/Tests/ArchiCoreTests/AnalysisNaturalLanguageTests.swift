// Oanarina Archi Tool — GPL-3.0-or-later
// Natural-language commands (SCR-026).
import XCTest
@testable import ArchiCore

final class AnalysisNaturalLanguageTests: XCTestCase {
    func grid() -> ArchiDocument {
        var d = ArchiDocument()
        d.addElement(.gridLine(GridLineGeom(start: Vec2(0, 0), end: Vec2(12_000, 0), label: "A")))
        d.addElement(.gridLine(GridLineGeom(start: Vec2(0, -1000), end: Vec2(0, 9000), label: "1")))
        return d
    }
    func parse(_ s: String, _ d: ArchiDocument, sel: Set<EntityID> = []) throws -> NLAction? { try NaturalLanguage.parse(s, doc: d, selection: sel).actions.first }

    func testParsing() throws {
        let d = grid()
        XCTAssertEqual(try parse("Draw a 4 m wall north of grid A", d), .wall(Vec2(0, 100), Vec2(4000, 100), thickness: nil, height: nil))
        XCTAssertEqual(try parse("draw a 3.5m wall north of grid 1, 300 mm thick", d), .wall(Vec2(0, -1000), Vec2(0, 2500), thickness: 300, height: nil))
        XCTAssertEqual(try parse("draw a wall from 0,0 to 5000,0", d), .wall(.zero, Vec2(5000, 0), thickness: nil, height: nil))
        XCTAssertEqual(try parse("please draw a 6 metre wall from 1000,0 going west", d), .wall(Vec2(1000, 0), Vec2(-5000, 0), thickness: nil, height: nil))
        XCTAssertEqual(try parse("draw a circle radius 500 at 2000,2000", d), .circle(Vec2(2000, 2000), 500))
        XCTAssertEqual(try parse("draw a circle with a diameter of 1 m", d), .circle(.zero, 500))
        XCTAssertEqual(try parse("draw a room 4 by 3 m at 0,0 named Master Bedroom", d), .room(.zero, 4000, 3000, name: "Master Bedroom"))
        XCTAssertEqual(try parse("draw a rectangle 2 x 1 m at 100,100", d), .rectangle(Vec2(100, 100), 2000, 1000))
        XCTAssertEqual(try parse("draw a line 2 m east from 0,0", d), .line(.zero, Vec2(2000, 0)))
        XCTAssertEqual(try parse("move the selection 2 m east", d, sel: [1]), .move(Vec2(2000, 0)))
        XCTAssertEqual(try parse("copy it 500 north", d, sel: [1]), .copy(Vec2(0, 500)))
        XCTAssertEqual(try parse("rotate the selection 90 degrees clockwise", d, sel: [1]), .rotate(-.pi / 2, nil))
        XCTAssertEqual(try parse("set layer A-WALL", d), .layer("A-WALL"))
        XCTAssertEqual(try parse("zoom extents", d), .zoomExtents)
        XCTAssertThrowsError(try parse("delete it", d), "needs a selection")
        XCTAssertThrowsError(try parse("draw a 4 m wall north of grid Z", d))
        XCTAssertThrowsError(try parse("sing a song", d))
    }

    @MainActor func testAskAppliesAfterConfirmationAsOneUndoStep() async throws {
        let ed = Editor()
        ed.doc = grid()
        await ed.run("ASK \"draw a 5 m wall from 0,0 going east\" N")
        XCTAssertEqual(ed.doc.elements.filter { $0.typeName == "wall" }.count, 0, "declined")
        await ed.run("ASK \"draw a 5 m wall from 0,0 going east\" Y")
        let wall = try XCTUnwrap(ed.doc.elements.last)
        XCTAssertEqual(wall.typeName, "wall")
        let out = await ed.run("ASK \"add a door 900 wide in the middle of the last wall\" Y")
        XCTAssertTrue(out.joined().contains("Understood: Add a door 900 wide in wall #\(wall.id)"), out.joined(separator: "\n"))
        guard case .opening(let o) = ed.doc.elements.last?.geometry else { return XCTFail("no door") }
        XCTAssertEqual(o.offset, 2500); XCTAssertEqual(o.width, 900); XCTAssertEqual(o.hostWall, wall.id)
        let bad = await ed.run("ASK \"add a window 6 m wide in wall \(wall.id)\" Y")
        XCTAssertTrue(bad.joined().contains("does not fit"), bad.joined(separator: "\n"))
        ed.selection = [wall.id]
        await ed.run("ASK \"move the selection 1 m north\" Y")
        guard case .wall(let w) = ed.doc.element(wall.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(w.start, Vec2(0, 1000))
        ed.undo()
        guard case .wall(let w0) = ed.doc.element(wall.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(w0.start, .zero)
    }
}
