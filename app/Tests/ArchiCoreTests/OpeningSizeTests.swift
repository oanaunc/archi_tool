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
    func testEditedLabelRendersPersistsUndoesAndRestoresAutomaticValue() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0")
        await ed.run("DOOR 2000,0 ")
        await ed.run("QUOTAINFISSI Doors Drawing 100")
        let tag = try XCTUnwrap(ed.doc.entities.first { $0.props["tagField"] == "size" })
        let openingID = try XCTUnwrap(tag.props["tagOf"].flatMap(Int.init))
        XCTAssertTrue(PropertyAccess.set("width", "1000", of: openingID, in: &ed.doc))
        XCTAssertEqual(PropertyAccess.properties(of: tag.id, in: ed.doc).first { $0.name == "content" }?.value, "1000×2100")
        func rendered(_ doc: ArchiDocument) -> [String] {
            DrawListBuilder.items(for: doc.entity(tag.id)!, doc: doc, options: DrawOptions()).compactMap {
                if case .text(let t, _, _) = $0 { return t.content }; return nil
            }
        }
        await ed.run("SETPROP #\(tag.id) Content 900x2100")
        XCTAssertEqual(rendered(ed.doc), ["900x2100"])
        XCTAssertEqual(PropertyAccess.properties(of: tag.id, in: ed.doc).first { $0.name == "labelMode" }?.value, "Manual")
        // Annotation edits retain the bubble/leader and do not resize the actual door.
        XCTAssertEqual(PropertyAccess.getProperty(ed.doc.element(openingID)!, "width"), "1000")
        XCTAssertEqual(ed.doc.entity(tag.id)?.props["tagOf"], String(openingID))
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(rendered(restored), ["900x2100"])
        ed.undo()
        XCTAssertEqual(rendered(ed.doc), ["1000×2100"])
        ed.redo()
        XCTAssertEqual(rendered(ed.doc), ["900x2100"])
        ed.selection = []
        await ed.run("TAGFORMAT #\(tag.id)  Automatic")
        XCTAssertEqual(rendered(ed.doc), ["1000×2100"])
        ed.undo()
        XCTAssertEqual(rendered(ed.doc), ["900x2100"])
        XCTAssertTrue(PropertyAccess.set("labelMode", "Automatic", of: tag.id, in: &ed.doc))
        XCTAssertTrue(PropertyAccess.set("width", "850", of: openingID, in: &ed.doc))
        XCTAssertEqual(rendered(ed.doc), ["850×2100"])
        ed.selection = []
        await ed.run("DDEDIT #\(tag.id) 800x2100 ")
        XCTAssertEqual(rendered(ed.doc), ["800x2100"])
        ed.selection = []
        await ed.run("QUOTAINFISSI Doors Drawing 100")
        XCTAssertEqual(rendered(ed.doc), ["850×2100"])
    }

    func testMarkLabelsCanBeAddedAfterSizeLabelsAndConvertedWithoutDuplicates() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0")
        await ed.run("DOOR 2000,0 ")
        await ed.run("OPENINGSIZES Doors Drawing 100")
        let sizeTag = try XCTUnwrap(ed.doc.entities.first { $0.props["tagField"] == "size" })
        await ed.run("TAGALL Doors")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["tagField"] == "mark" }.count, 1)
        await ed.run("TAGALLNOTTAGGED Doors")
        XCTAssertEqual(ed.doc.entities.filter { $0.props["tagField"] == "mark" }.count, 1)
        ed.undo()
        ed.selection = []
        await ed.run("EDITLABEL #\(sizeTag.id)  Field mark")
        let openingID = try XCTUnwrap(sizeTag.props["tagOf"].flatMap(Int.init))
        XCTAssertTrue(PropertyAccess.set("mark", "D1", of: openingID, in: &ed.doc))
        XCTAssertEqual(Annotations.text(ed.doc.entity(sizeTag.id)!, doc: ed.doc), "D1")
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(Annotations.text(restored.entity(sizeTag.id)!, doc: restored), "D1")
    }

    func testWindowsPropertyPanelUsesTheSameManualAndAutomaticLabels() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0")
        await ed.run("DOOR 2000,0 ")
        await ed.run("OPENINGSIZES Doors Drawing 100")
        let tag = try XCTUnwrap(ed.doc.entities.first { $0.props["tagField"] == "size" })
        ed.selection = [tag.id]
        let session = EngineSession(editor: ed)
        _ = try await session.call("panel.set", .object([EngineJSONField("panel", .string("properties")), EngineJSONField("key", .string("content")), EngineJSONField("value", .string("900x2100"))]))
        XCTAssertEqual(Annotations.text(ed.doc.entity(tag.id)!, doc: ed.doc), "900x2100")
        ed.undo()
        XCTAssertNil(ed.doc.entity(tag.id)?.props["tagTextOverride"])
    }

}
