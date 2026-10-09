// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class NamedPageSetupTests: XCTestCase {
    @MainActor func testSaveApplySelectedAllUndoAndPersistence() async throws {
        let ed = Editor()
        ed.doc.layouts = [Layout(name: "Source", paper: PaperSize(name: "Custom", width: 700, height: 500)), Layout(name: "Section"), Layout(name: "Plan")]
        var setup = EnginePageSetup(); setup.colorMode = "Grayscale"; setup.lineweightScale = 1.5
        setup.store(in: &ed.doc, layoutIndex: 0)
        let style = SectionSheetStyle(lines: ObjectStyle(cutLineweight: 0.8, cutFill: RGBA(0.4, 0.2, 0.1)), shaded: false)
        style.store(in: &ed.doc.layouts[0])
        await ed.run("PSPRESET Save \"Presentation\" \"Source\"")
        let preset = try XCTUnwrap(NamedPageSetups.find("presentation", doc: ed.doc))
        let before = ed.doc
        await ed.run("PAGEPRESET Apply \"Presentation\" \"Source|Section\"")
        XCTAssertEqual(ed.doc.layouts[1].paper, preset.paper)
        XCTAssertEqual(EnginePageSetup.load(ed.doc, layoutIndex: 1), setup)
        XCTAssertEqual(SectionSheetStyle.load(ed.doc.layouts[1]), style)
        XCTAssertNil(SectionSheetStyle.load(ed.doc.layouts[2]))
        ed.undo(); XCTAssertEqual(ed.doc, before)
        ed.redo(); XCTAssertEqual(ed.doc.layouts[1].paper, preset.paper)
        await ed.run("NAMEDPAGESETUP Apply \"Presentation\" All")
        XCTAssertEqual(ed.doc.layouts[2].paper, preset.paper)
        let decoded = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(NamedPageSetups.all(decoded), NamedPageSetups.all(ed.doc))
        let previous = ed.doc
        await ed.run("PAGEPRESET Apply \"Presentation\" \"Section|Missing\"")
        XCTAssertEqual(ed.doc, previous, "invalid target cannot partially apply")
        await ed.run("PAGEPRESET Delete \"Presentation\"")
        XCTAssertTrue(NamedPageSetups.names(ed.doc).isEmpty)
        ed.undo(); XCTAssertEqual(ed.doc, previous)
    }

    @MainActor func testImportPreservesConflictingPlotTables() async throws {
        var source = ArchiDocument(), dest = ArchiDocument()
        source.layouts[0].paper = PaperSize(name: "A2", width: 594, height: 420)
        let red = EnginePlotStyleTable(name: "Shared", pens: [7: EnginePen(color: 0xFF0000)])
        let blue = EnginePlotStyleTable(name: "Shared", pens: [7: EnginePen(color: 0x0000FF)])
        source.setVariable("PLOTSTYLE:SHARED", String(decoding: try JSONEncoder().encode(red), as: UTF8.self))
        dest.setVariable("PLOTSTYLE:SHARED", String(decoding: try JSONEncoder().encode(blue), as: UTF8.self))
        var setup = EnginePageSetup(); setup.plotStyleTable = "Shared"; setup.store(in: &source, layoutIndex: 0)
        NamedPageSetups.save(try XCTUnwrap(NamedPageSetups.capture(source, layoutIndex: 0)), name: "Print", doc: &source)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("archi-presets-\(UUID().uuidString).archi")
        try ArchiFile.encode(source).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let ed = Editor(document: dest)
        await ed.run("PAGEPRESET Import \"\(file.path)\"")
        XCTAssertEqual(NamedPageSetups.names(ed.doc), ["Print"])
        let before = ed.doc
        await ed.run("PAGEPRESET Apply \"Print\" All")
        XCTAssertEqual(ed.doc.variable("PLOTSTYLE:SHARED"), dest.variable("PLOTSTYLE:SHARED"))
        XCTAssertEqual(EnginePageSetup.load(ed.doc, layoutIndex: 0).plotStyleTable, "Shared (2)")
        XCTAssertEqual(ed.doc.variable("PLOTSTYLE:SHARED (2)"), source.variable("PLOTSTYLE:SHARED"))
        ed.undo(); XCTAssertEqual(ed.doc, before)
    }

    @MainActor func testWindowsDialogAPISectionStylePresetsAndUndo() async throws {
        let s = EngineSession(editor: Editor(), emit: { _ in })
        s.editor.doc.layouts.append(Layout(name: "Second"))
        s.editor.doc.layouts[0].viewports = [Viewport(origin: Vec2(30, 70), size: Vec2(200, 150), viewCenter: .zero, scale: 50, view: .section)]
        let style = SectionSheetStyle(lines: ObjectStyle(cutLineweight: 0.7), shaded: false)
        let json = try EngineJSON.parse(String(decoding: JSONEncoder().encode(style), as: UTF8.self))
        let before = s.editor.doc
        let response = try await s.call("pagesetup.set", .object([EngineJSONField("layout", .int(0)), EngineJSONField("sectionStyle", json), EngineJSONField("presetName", .string("Print"))]))
        XCTAssertEqual(response["hasSection"]?.boolValue, true)
        XCTAssertEqual(response["presets"]?.arrayValue?.count, 1)
        XCTAssertEqual(SectionSheetStyle.load(s.editor.doc.layouts[0]), style)
        s.editor.undo(); XCTAssertEqual(s.editor.doc, before)
        s.editor.redo()
        let source = s.editor.doc
        _ = try await s.call("pagepresets.apply", .object([EngineJSONField("name", .string("Print")), EngineJSONField("layouts", .array([.int(1)]))]))
        XCTAssertEqual(SectionSheetStyle.load(s.editor.doc.layouts[1]), style)
        s.editor.undo(); XCTAssertEqual(s.editor.doc, source)
        _ = try await s.call("pagepresets.delete", .object([EngineJSONField("name", .string("Print"))]))
        XCTAssertTrue(NamedPageSetups.names(s.editor.doc).isEmpty)
        s.editor.undo(); XCTAssertEqual(s.editor.doc, source)
    }
    @MainActor func testImportedCustomPaperLoadsThroughDialogAndInvalidStyleIsAtomic() async throws {
        let s = EngineSession(editor: Editor(), emit: { _ in })
        var source = ArchiDocument()
        source.layouts[0].paper = PaperSize(name: "Presentation 700", width: 700, height: 500)
        NamedPageSetups.save(try XCTUnwrap(NamedPageSetups.capture(source, layoutIndex: 0)), name: "Imported", doc: &source)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("archi-setup-\(UUID().uuidString).archi")
        try ArchiFile.encode(source).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await s.call("pagepresets.import", .object([EngineJSONField("path", .string(file.path))]))
        let before = s.editor.doc
        let result = try await s.call("pagesetup.set", .object([
            EngineJSONField("layout", .int(0)), EngineJSONField("presetSource", .string("Imported")),
            EngineJSONField("paper", .string("Presentation 700")), EngineJSONField("portrait", .bool(true))]))
        XCTAssertEqual(s.editor.doc.layouts[0].paper.width, 500)
        XCTAssertEqual(s.editor.doc.layouts[0].paper.height, 700)
        XCTAssertEqual(result["paper"]?.stringValue, "Presentation 700")
        s.editor.undo(); XCTAssertEqual(s.editor.doc, before)
        let invalid = SectionSheetStyle(lines: ObjectStyle(cutLineweight: -1), shaded: false)
        let json = try EngineJSON.parse(String(decoding: JSONEncoder().encode(invalid), as: UTF8.self))
        do {
            _ = try await s.call("pagesetup.set", .object([EngineJSONField("layout", .int(0)), EngineJSONField("sectionStyle", json)]))
            XCTFail("invalid weight must be rejected")
        } catch {}
        XCTAssertEqual(s.editor.doc, before)
    }

    @MainActor func testSaveDraftPresetKeepsSourceSheetUntilApply() async throws {
        let s = EngineSession(editor: Editor(), emit: { _ in })
        let before = s.editor.doc
        _ = try await s.call("pagesetup.set", .object([
            EngineJSONField("layout", .int(0)), EngineJSONField("paper", .string("A1")),
            EngineJSONField("setup", .object([EngineJSONField("colorMode", .string("Grayscale"))])),
            EngineJSONField("presetName", .string("Presentation")), EngineJSONField("presetOnly", .bool(true))]))
        XCTAssertEqual(s.editor.doc.layouts, before.layouts)
        XCTAssertEqual(EnginePageSetup.load(s.editor.doc, layoutIndex: 0), EnginePageSetup())
        let preset = try XCTUnwrap(NamedPageSetups.find("Presentation", doc: s.editor.doc))
        XCTAssertEqual(preset.paper.name, "A1")
        XCTAssertEqual(try EngineJSON.parse(preset.settings)["colorMode"]?.stringValue, "Grayscale")
        s.editor.undo(); XCTAssertEqual(s.editor.doc, before)
    }

}
