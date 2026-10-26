// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class SheetCustomizationTests: XCTestCase {
    private func texts(_ entries: [DrawEntry]) -> [String] {
        entries.flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
    }
    func testLegacyDefaultsAndPerSheetDecorationPersistence() throws {
        var doc = ArchiDocument()
        doc.layouts[0].viewports = [Viewport(origin: Vec2(24, 62), size: Vec2(200, 140), viewCenter: .zero, scale: 100)]
        let original = doc.layouts[0]
        let normal = EnginePlot.decorations(doc: doc, layout: original, layoutIndex: 0)
        XCTAssertTrue(texts(normal).contains("N"))
        SheetCustomization.set(.north, visible: false, offset: .zero, in: &doc.layouts[0])
        let withoutNorth = EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0)
        XCTAssertFalse(texts(withoutNorth).contains("N"))
        XCTAssertEqual(withoutNorth.count, normal.count - 1)
        SheetCustomization.set(.titleBlock, visible: false, offset: Vec2(-20, 30), in: &doc.layouts[0])
        let hidden = EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0)
        XCTAssertFalse(texts(hidden).contains("OANARINA ARCHI TOOL"))
        XCTAssertTrue(texts(hidden).contains { $0.hasPrefix("SCALE ") })
        let roundTrip = try ArchiFile.decode(ArchiFile.encode(doc))
        XCTAssertEqual(roundTrip.layouts[0], doc.layouts[0])
        XCTAssertEqual(SheetCustomization.offset(.titleBlock, in: roundTrip.layouts[0]), Vec2(-20, 30))
        XCTAssertTrue(SheetCustomization.visible(.north, in: original))
        doc.layouts[0].titleBlock["office"] = "Studio Maglione"
        SheetCustomization.set(.titleBlock, visible: true, offset: .zero, in: &doc.layouts[0])
        XCTAssertTrue(texts(EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0)).contains("Studio Maglione"))
    }
    func testOffsetsMoveEveryPrimitiveAndBounds() {
        var layout = Layout(name: "Custom")
        let entries = [DrawEntry(id: nil, items: [
            .stroke(points: [.zero, Vec2(10, 10)], closed: false, style: StrokeStyle(color: .black)),
            .fill(loops: [[.zero, Vec2(5, 0), Vec2(5, 5)]], color: .black),
            .text(TextGeom(position: .zero, height: 3, content: "Office"), font: "Helvetica", color: .black),
            .image(ImageGeom(path: "logo.png", origin: .zero, size: Vec2(10, 5)))
        ])]
        SheetCustomization.set(.titleBlock, visible: true, offset: Vec2(-12, 25), in: &layout)
        let moved = SheetCustomization.apply(entries, part: .titleBlock, layout: layout)
        XCTAssertEqual(moved[0].bounds.min.x, entries[0].bounds.min.x - 12, accuracy: 1e-8)
        XCTAssertEqual(moved[0].bounds.max.y, entries[0].bounds.max.y + 25, accuracy: 1e-8)
        XCTAssertEqual(moved[0].items.count, 4)
    }
    @MainActor func testCommandsUndoAPIAndViewportLocks() async throws {
        let registry = CommandRegistry()
        EngineSession.registerPortableAppCommands(registry)
        EngineSession.registerToolCommands(registry)
        let session = EngineSession(editor: Editor(registry: registry), emit: { _ in })
        let ed = session.editor
        _ = ed.doc.add(.line(LineGeom(Vec2(1000, 2000), Vec2(9000, 6000))))
        ed.doc.layouts[0].viewports = [Viewport(origin: Vec2(10, 20), size: Vec2(180, 120), viewCenter: .zero, scale: 100)]
        func feed(_ line: String, _ answers: [String]) async throws {
            var p = EngineObject(); p.set("line", line)
            var state = try await session.call("command.run", p.json)
            for a in answers where state["active"]?.boolValue == true {
                var input = EngineObject(); input.set("text", a)
                state = try await session.call("input.text", input.json)
            }
            XCTAssertFalse(state["active"]?.boolValue ?? false, "Command still prompting: \(line)")
        }
        try await feed("SHTSTYLE", ["North", "Hide"])
        XCTAssertFalse(SheetCustomization.visible(.north, in: ed.doc.layouts[0]))
        ed.undo()
        XCTAssertTrue(SheetCustomization.visible(.north, in: ed.doc.layouts[0]))
        try await feed("SHEETSTYLE", ["TitleBlock", "Move", "-15,25"])
        XCTAssertEqual(SheetCustomization.offset(.titleBlock, in: ed.doc.layouts[0]), Vec2(-15, 25))
        try await feed("VPE", ["1", "CenterContent"])
        let centred = ed.doc.layouts[0].viewports[0]
        XCTAssertEqual(centred.viewCenter, Vec2(5000, 4000))
        XCTAssertEqual(centred.scale, 100)
        XCTAssertEqual(centred.origin, Vec2(10, 20))
        try await feed("VPEDIT", ["1", "Scale", "1:50"])
        XCTAssertEqual(ed.doc.layouts[0].viewports[0].scale, 50)
        XCTAssertEqual(ed.doc.layouts[0].viewports[0].size, centred.size)
        try await feed("VPEDIT", ["1", "Position", "45,80"])
        XCTAssertEqual(ed.doc.layouts[0].viewports[0].origin, Vec2(45, 80))
        try await feed("VPEDIT", ["1", "Size", "220,160"])
        XCTAssertEqual(ed.doc.layouts[0].viewports[0].size, Vec2(220, 160))
        try await feed("VPEDIT", ["1", "CenterOnSheet"])
        let final = ed.doc.layouts[0].viewports[0]
        XCTAssertEqual(final.origin, (Vec2(420, 297) - final.size) / 2)
        XCTAssertEqual(try ArchiFile.decode(ArchiFile.encode(ed.doc)).layouts[0].viewports[0], final)
        try await feed("SHEETTEXT", ["Add", "195,30", "3", "Testo libero al posto del Nord"])
        let text = SheetTextEditing.texts(ed.doc.layouts[0]).first!
        XCTAssertEqual(SheetTextEditing.texts(ed.doc.layouts[0]).count, 1)
        ed.undo()
        XCTAssertTrue(SheetTextEditing.texts(ed.doc.layouts[0]).isEmpty)
        try await feed("PAPERTEXT", ["Add", "195,30", "3", "Testo libero al posto del Nord"])
        try await feed("SHEETTEXT", ["Edit", "1", "180,35", "4", "Qualsiasi testo\nSeconda riga"])
        let savedText = SheetTextEditing.texts(ed.doc.layouts[0]).first!
        if case .text(let t) = savedText.geometry {
            XCTAssertEqual(t.content, "Qualsiasi testo\nSeconda riga")
            XCTAssertEqual(t.position, Vec2(180, 35)); XCTAssertEqual(t.height, 4)
        } else { XCTFail("Expected sheet text") }
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(SheetTextEditing.texts(restored.layouts[0]), [savedText])
        XCTAssertFalse(ed.doc.entities.contains { $0.id == savedText.id })
        try await feed("SHEETTEXT", ["Delete", "1"])
        XCTAssertTrue(SheetTextEditing.texts(ed.doc.layouts[0]).isEmpty)
        ed.undo()
        XCTAssertEqual(SheetTextEditing.texts(ed.doc.layouts[0]), [savedText])
        XCTAssertGreaterThanOrEqual(savedText.id, text.id)
        EngineViewports.setLocked(&ed.doc, 0, 0, true)
        try await feed("VPEDIT", ["1", "Position", "0,0"])
        XCTAssertEqual(ed.doc.layouts[0].viewports[0], final)
        XCTAssertThrowsError(try SheetViewportEditing.updated(final, property: "Size", point: Vec2(-1, 0), doc: ed.doc, layoutIndex: 0, index: 0))
    }
}
