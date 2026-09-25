import XCTest
@testable import ArchiCore

final class InputParserTests: XCTestCase {
    func testCoordinates() {
        XCTAssertEqual(InputParser.parsePoint("10,20", last: nil), Vec2(10, 20))
        XCTAssertEqual(InputParser.parsePoint("@5,5", last: Vec2(10, 20)), Vec2(15, 25))
        let p = InputParser.parsePoint("@10<90", last: Vec2(0, 0))!
        XCTAssertEqual(p.x, 0, accuracy: 1e-9); XCTAssertEqual(p.y, 10, accuracy: 1e-9)
        XCTAssertEqual(InputParser.parseNumber("1000+250"), 1250)
        XCTAssertEqual(InputParser.parseNumber("3'6\"")!, 1066.8, accuracy: 1e-9)
    }

    @MainActor func testLineCommand() async {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 @0,100 C")
        XCTAssertEqual(ed.doc.entities.count, 3)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.count, 0)
    }
}
