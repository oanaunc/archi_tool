// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class SheetRevisionPresentationTests: XCTestCase {
    func testRevisionLayoutFieldsCustomBlockAndPersistence() throws {
        var doc = ArchiDocument()
        EngineSheets.addRevision(&doc, 0, description: "First issue", by: "NM", date: "2026-10-27")
        EngineSheets.addRevision(&doc, 0, description: "Window sizes", by: "OA", date: "2026-10-28")
        let original = doc.layouts[0]
        let legacy = SheetRevisionPresentation.entries(original, titleOrigin: Vec2(230, 10), titleSize: Vec2(180, 42))
        XCTAssertEqual(legacy.count, 1)
        XCTAssertEqual(legacy[0].bounds.min.y, 52, accuracy: 0.01)
        try SheetRevisionPresentation.set(.inside, width: 180, rowHeight: 6, in: &doc.layouts[0])
        let inside = SheetRevisionPresentation.entries(doc.layouts[0], titleOrigin: Vec2(230, 10), titleSize: Vec2(180, 42))
        XCTAssertEqual(inside[0].bounds.min.y, 10, accuracy: 0.01)
        XCTAssertEqual(inside[0].bounds.max.y, 28, accuracy: 0.01)
        let decorations = EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0)
        let titleField = decorations.flatMap(\.items).compactMap { item -> TextGeom? in if case .text(let t, _, _) = item, t.content == "REVISION" { return t }; return nil }.first!
        XCTAssertGreaterThan(titleField.position.y, 28, "Builtin fields move above the revision band")
        SheetCustomization.set(.revisions, visible: true, offset: Vec2(-20, 8), in: &doc.layouts[0])
        SheetCustomization.set(.titleBlock, visible: true, offset: Vec2(5, 3), in: &doc.layouts[0])
        let moved = SheetRevisionPresentation.entries(doc.layouts[0], titleOrigin: Vec2(230, 10), titleSize: Vec2(180, 42))
        XCTAssertEqual(moved[0].bounds.min.x, 215, accuracy: 0.01)
        XCTAssertEqual(moved[0].bounds.min.y, 21, accuracy: 0.01)
        let values = SheetRevisionPresentation.fields(doc.layouts[0])
        XCTAssertEqual(values["revision"], "B")
        XCTAssertEqual(values["revisionDescription"], "Window sizes")
        XCTAssertEqual(values["revision.1.by"], "NM")
        let text = Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(-150, 20), height: 3, content: "{revision} {revisionDescription} {revision.1.by} {revision.3.code}")))
        doc.blocks["My cartiglio"] = Block(name: "My cartiglio", basePoint: .zero, entities: [text])
        doc.setVariable("TITLEBLOCKBLOCK", "My cartiglio")
        try SheetRevisionPresentation.set(.fields, width: 120, rowHeight: 4, in: &doc.layouts[0])
        XCTAssertTrue(SheetRevisionPresentation.entries(doc.layouts[0], titleOrigin: .zero, titleSize: Vec2(180, 42)).isEmpty)
        let custom = EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0)
        XCTAssertTrue(custom.flatMap(\.items).contains { if case .text(let t, _, _) = $0 { return t.content == "B Window sizes NM " }; return false })
        let restored = try ArchiFile.decode(ArchiFile.encode(doc))
        XCTAssertEqual(restored.layouts[0], doc.layouts[0])
        XCTAssertEqual(restored.blocks, doc.blocks)
        XCTAssertThrowsError(try SheetRevisionPresentation.set(.above, width: .infinity, rowHeight: 4, in: &doc.layouts[0]))
    }
    @MainActor func testCommandAliasAgentAPIUndoAndHide() async throws {
        let session = EngineSession(emit: { _ in })
        let ed = session.editor
        EngineSheets.addRevision(&ed.doc, 0, description: "Issue", by: "NM")
        var p = EngineObject(); p.set("line", "REVSTYLE Fields 140 6")
        let state = try await session.call("command.run", p.json)
        XCTAssertFalse(state["active"]?.boolValue ?? false)
        XCTAssertEqual(SheetRevisionPresentation.placement(ed.doc.layouts[0]), .fields)
        ed.undo()
        XCTAssertEqual(SheetRevisionPresentation.placement(ed.doc.layouts[0]), .above)
        await ed.run("SHEETSTYLE Revisions Hide")
        XCTAssertTrue(SheetRevisionPresentation.entries(ed.doc.layouts[0], titleOrigin: .zero, titleSize: Vec2(180, 42)).isEmpty)
        XCTAssertEqual(ed.doc.layouts[0].titleBlock["revision"], "A")
        ed.undo()
        XCTAssertTrue(SheetCustomization.visible(.revisions, in: ed.doc.layouts[0]))
    }
}
