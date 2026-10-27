// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor final class OpeningSizeTests: XCTestCase {
    func testBulkSizesPreserveMarksAreIdempotentLiveUndoableAndPersisted() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0")
        await ed.run("DOOR 2000,0 ")
        await ed.run("WINDOW 5000,0 ")
        await ed.run("TAGALL All")
        let marks = ed.doc.entities.filter { $0.props["tagField"] == "mark" }
        await ed.run("QUOTAINFISSI All Centimetres 180")
        func sizes() -> [Entity] { ed.doc.entities.filter { $0.props["tagField"] == "sizecm" } }
        XCTAssertEqual(sizes().count, 2)
        XCTAssertEqual(ed.doc.entities.filter { $0.props["tagField"] == "mark" }, marks)
        let before = sizes()
        await ed.run("OPENINGSIZES Doors Millimetres 220")
        XCTAssertEqual(sizes().count, 1)
        ed.undo()
        XCTAssertEqual(sizes(), before)
        await ed.run("DOORWINDOWSIZES All Centimetres 180")
        XCTAssertEqual(sizes().count, 2)
        let opening = ed.doc.elements.first { if case .opening(let o) = $0.geometry { return o.kind == .door }; return false }!
        let tag = sizes().first { $0.props["tagOf"] == String(opening.id) }!
        let index = ed.doc.elementIndex(opening.id)!
        if case .opening(var o) = ed.doc.elements[index].geometry { o.width = 950; o.height = 2150; ed.doc.elements[index].geometry = .opening(o) }
        let rendered = DrawListBuilder.items(for: tag, doc: ed.doc, options: DrawOptions())
        XCTAssertTrue(rendered.contains { if case .text(let t, _, _) = $0 { return t.content == "95×215 cm" }; return false })
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(restored.entity(tag.id), tag)
        XCTAssertEqual(Annotations.tagText(restored.element(opening.id)!, field: "sizecm", doc: restored), "95×215 cm")
    }
    func testAutomaticLabelsAndDisable() async {
        let ed = Editor()
        await ed.run("WALL 0,0 12000,0")
        await ed.run("OPENINGSIZES Automatic Metres 200")
        await ed.run("DOOR 2000,0 ")
        let tags = ed.doc.entities.filter { $0.props["tagField"] == "sizem" }
        XCTAssertEqual(tags.count, 1)
        if case .text(let t)? = tags.first?.geometry { XCTAssertEqual(t.height, 200) }
        ed.undo()
        XCTAssertFalse(ed.doc.entities.contains { $0.props["tagField"] == "sizem" })
        await ed.run("OPENINGSIZES Off")
        await ed.run("WINDOW 6000,0 ")
        XCTAssertFalse(ed.doc.entities.contains { $0.props["tagOf"] != nil })
    }
}
