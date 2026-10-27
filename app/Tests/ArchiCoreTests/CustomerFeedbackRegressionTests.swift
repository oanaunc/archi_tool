// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor final class CustomerFeedbackRegressionTests: XCTestCase {
    private func square(_ x: Double, _ y: Double, _ side: Double) -> [PolyVertex] {
        [Vec2(x, y), Vec2(x + side, y), Vec2(x + side, y + side), Vec2(x, y + side)].map { PolyVertex($0) }
    }
    private func items(_ doc: ArchiDocument, _ id: EntityID) -> [DrawItem] {
        DrawListBuilder.items(for: doc.entity(id)!, doc: doc, options: DrawOptions())
    }
    func testMatchHatchLiveClicksRemovalUndoAndPersistence() async throws {
        let ed = Editor()
        let src = ed.doc.add(.hatch(HatchGeom(loops: [square(0, 0, 100)], pattern: "ANSI37", scale: 2, angle: 0.4)))
        let dst = ed.doc.add(.hatch(HatchGeom(loops: [square(200, 0, 100)], pattern: "ANSI31")))
        let i = ed.doc.entityIndex(src)!
        ed.doc.entities[i].color = .aci(1)
        ed.doc.entities[i].props[DraftRendering.hatchOriginProp] = "12,13"
        ed.doc.entities[i].props[DraftRendering.gradientProp] = "LINEAR"
        ed.doc.entities[i].props[DraftRendering.gradientColorsProp] = "1,3"
        let before = ed.doc
        ed.start("MA")
        await ed.waitForInputOrIdle()
        ed.feed(.selection([src]))
        await ed.waitForInputOrIdle()
        ed.feed(.selection([dst]))
        await ed.waitForInputOrIdle()
        XCTAssertEqual(ed.doc.entity(dst)?.color, .aci(1), "Changes appear before Enter")
        XCTAssertEqual(ed.doc.entity(dst)?.props[DraftRendering.gradientColorsProp], "1,3")
        ed.feed(.keyword("Remove")); await ed.waitForInputOrIdle()
        ed.feed(.selection([dst])); await ed.waitForInputOrIdle()
        XCTAssertEqual(ed.doc.entity(dst), before.entity(dst))
        ed.feed(.keyword("Add")); await ed.waitForInputOrIdle()
        ed.feed(.selection([dst])); await ed.waitForInputOrIdle()
        ed.feed(.enter); await ed.waitIdle()
        guard case .hatch(let h)? = ed.doc.entity(dst)?.geometry else { return XCTFail() }
        XCTAssertEqual(h.loops, [square(200, 0, 100)])
        XCTAssertEqual(h.pattern, "ANSI37"); XCTAssertEqual(h.scale, 2)
        XCTAssertEqual(ed.doc.entity(dst)?.props[DraftRendering.hatchOriginProp], "12,13")
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(restored.entity(dst), ed.doc.entity(dst))
        ed.undo(); XCTAssertEqual(ed.doc, before)
        // Matching a plain hatch clears a target's old gradient, but retains its own boundary association.
        ed.doc.entities[ed.doc.entityIndex(src)!].props[DraftRendering.gradientProp] = nil
        ed.doc.entities[ed.doc.entityIndex(dst)!].props[DraftRendering.gradientProp] = "SPHERICAL"
        ed.doc.entities[ed.doc.entityIndex(dst)!].props[AssociativeHatch.boundaryProp] = "999"
        var target = ed.doc.entity(dst)!
        ModifyCommands.matchEntity(ed.doc.entity(src)!, &target)
        XCTAssertNil(target.props[DraftRendering.gradientProp])
        XCTAssertEqual(target.props[AssociativeHatch.boundaryProp], "999")
    }
    func testScaleAboutRemoteBaseKeepsVisiblePatternAndCopyAssociativity() async throws {
        let ed = Editor()
        // A single horizontal stroke at y=0. Scaling about y=1000 used to move the region away from all pattern lines.
        let loop = square(90, -1, 2)
        let boundary = ed.doc.add(.polyline(PolylineGeom(loop, closed: true)))
        let hatch = ed.doc.add(.hatch(HatchGeom(loops: [loop], pattern: "LINE", scale: 100)))
        AssociativeHatch.attach(&ed.doc, hatch: hatch, boundary: [boundary], seed: nil)
        let before = ed.doc
        XCTAssertFalse(items(ed.doc, hatch).isEmpty)
        await ed.run("SCALE #\(boundary),#\(hatch)  0,1000 0.5")
        XCTAssertFalse(items(ed.doc, hatch).isEmpty, "Scaling must carry the implicit pattern origin")
        XCTAssertEqual(DraftProps.point(ed.doc.entity(hatch)?.props[DraftRendering.hatchOriginProp]), Vec2(0, 500))
        XCTAssertEqual(GeometryOps.area(ed.doc.entity(hatch)!.geometry, doc: ed.doc)!, 1, accuracy: 1e-8)
        XCTAssertEqual(try ArchiFile.decode(ArchiFile.encode(ed.doc)).entity(hatch), ed.doc.entity(hatch))
        ed.undo(); XCTAssertEqual(ed.doc, before)
        await ed.run("SCALE #\(boundary),#\(hatch)  0,1000 Copy 0.5")
        let copies = ed.doc.entities.filter { $0.id != hatch && $0.id != boundary }
        let copiedHatch = try XCTUnwrap(copies.first { if case .hatch = $0.geometry { return true }; return false }).id
        let copiedBoundary = try XCTUnwrap(copies.first { if case .polyline = $0.geometry { return true }; return false }).id
        XCTAssertEqual(AssociativeHatch.ids(ed.doc.entity(copiedHatch)!), [copiedBoundary])
        XCTAssertFalse(items(ed.doc, copiedHatch).isEmpty)
        XCTAssertEqual(ed.doc.entity(hatch), before.entity(hatch))
        ed.undo()
        await ed.run("SCALE #\(hatch)  0,1000 0.5")
        XCTAssertFalse(AssociativeHatch.isAssociative(ed.doc.entity(hatch)!))
        XCTAssertFalse(items(ed.doc, hatch).isEmpty)
    }
    func testDensePatternDoesNotVanishWhenBoundaryAloneIsEnlarged() {
        let loops = [square(0, 0, 100).map(\.p)]
        let lines = HatchPatterns.lines(loops: loops, pattern: "LINE", scale: 0.001, angle: 0)
        XCTAssertFalse(lines.isEmpty)
        XCTAssertLessThanOrEqual(lines.count, HatchPatterns.maxSegments)
    }
    func testWindowsGripAPIKeepsHatchOriginAndCopiedBoundary() async throws {
        let session = EngineSession(emit: { _ in })
        let ed = session.editor
        let loop = square(90, -1, 2)
        let boundary = ed.doc.add(.polyline(PolylineGeom(loop, closed: true)))
        let hatch = ed.doc.add(.hatch(HatchGeom(loops: [loop], pattern: "LINE", scale: 100)))
        AssociativeHatch.attach(&ed.doc, hatch: hatch, boundary: [boundary], seed: nil)
        ed.selection = [boundary, hatch]
        let before = ed.doc
        var p = EngineObject(); p.set("id", boundary); p.set("index", 0); p.set("mode", "SC"); p.set("value", 0.5)
        p.set("x", 100); p.set("y", 0); p.set("copy", true)
        _ = try await session.call("grips.typed", p.json)
        let copies = ed.doc.entities.filter { $0.id != boundary && $0.id != hatch }
        let h = try XCTUnwrap(copies.first { if case .hatch = $0.geometry { return true }; return false })
        let b = try XCTUnwrap(copies.first { if case .polyline = $0.geometry { return true }; return false })
        XCTAssertEqual(AssociativeHatch.ids(h), [b.id])
        XCTAssertEqual(DraftProps.point(h.props[DraftRendering.hatchOriginProp]), Vec2(45, -0.5))
        XCTAssertFalse(items(ed.doc, h.id).isEmpty)
        XCTAssertEqual(ed.doc.entity(hatch), before.entity(hatch))
        XCTAssertEqual(try ArchiFile.decode(ArchiFile.encode(ed.doc)).entity(h.id), h)
        ed.undo(); XCTAssertEqual(ed.doc, before)
    }
    func testStoredViewTitlesHideMoveUndoAndRoundTrip() async throws {
        let session = EngineSession(emit: { _ in })
        let ed = session.editor
        ed.doc.layouts[0].viewports = [Viewport(origin: Vec2(20, 70), size: Vec2(180, 120), viewCenter: .zero, title: "Pianta piano primo")]
        EngineSheets.refreshViewTitles(&ed.doc, 0)
        let free = try SheetTextEditing.set(&ed.doc, layoutIndex: 0, position: Vec2(100, 180), height: 3, content: "PIANTA PIANO PRIMO")
        let original = SheetCustomization.paperEntities(doc: ed.doc, layout: ed.doc.layouts[0])
        var p = EngineObject(); p.set("line", "SHTSTYLE Captions Hide")
        _ = try await session.call("command.run", p.json)
        XCTAssertEqual(SheetCustomization.paperEntities(doc: ed.doc, layout: ed.doc.layouts[0]).map(\.id), [free])
        XCTAssertFalse(EnginePlot.decorations(doc: ed.doc, layout: ed.doc.layouts[0], layoutIndex: 0).flatMap(\.items).contains { if case .text(let t, _, _) = $0 { return t.content == "Pianta piano primo" }; return false })
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(SheetCustomization.paperEntities(doc: restored, layout: restored.layouts[0]).map(\.id), [free])
        ed.undo(); XCTAssertEqual(SheetCustomization.paperEntities(doc: ed.doc, layout: ed.doc.layouts[0]), original)
        await ed.run("SHEETSTYLE Captions Move 5,10")
        let moved = SheetCustomization.paperEntities(doc: ed.doc, layout: ed.doc.layouts[0])
        XCTAssertEqual(moved.first!.bounds.min.x, original.first!.bounds.min.x + 5, accuracy: 1e-8)
        XCTAssertEqual(moved.last, original.last, "Free sheet text remains independent")
    }
    func testModelTitleHiddenOnOneSheetOnlyViaAPI() async throws {
        let session = EngineSession(emit: { _ in })
        let ed = session.editor
        let title = ed.doc.add(.text(TextGeom(position: .zero, height: 10, content: "PIANTA PIANO PRIMO")))
        let vp = Viewport(origin: .zero, size: Vec2(200, 150), viewCenter: .zero)
        ed.doc.layouts[0].viewports = [vp]
        ed.doc.layouts.append(Layout(name: "Other", viewports: [vp]))
        var p = EngineObject(); p.set("line", "PAPERTEXT HideModel #\(title)")
        _ = try await session.call("command.run", p.json)
        XCTAssertNotNil(ed.doc.entity(title))
        XCTAssertFalse(EnginePlot.viewportEntries(doc: ed.doc, vp: vp, layout: ed.doc.layouts[0].name).contains { $0.id == title })
        XCTAssertTrue(EnginePlot.viewportEntries(doc: ed.doc, vp: vp, layout: "Other").contains { $0.id == title })
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertTrue(SheetModelText.isHidden(title, in: restored.layouts[0]))
        ed.undo(); XCTAssertFalse(SheetModelText.isHidden(title, in: ed.doc.layouts[0]))
        XCTAssertTrue(EnginePlot.viewportEntries(doc: ed.doc, vp: vp, layout: ed.doc.layouts[0].name).contains { $0.id == title })
        XCTAssertThrowsError(try SheetModelText.set(&ed.doc, layoutIndex: 0, id: -1, hidden: true))
    }
    func testNestedCartiglioRevisionBindingCommandAPIUndoAndPersistence() async throws {
        let session = EngineSession(emit: { _ in })
        let ed = session.editor
        EngineSession.registerSheetCommands(ed.registry)
        let text = Entity(layer: "0", geometry: .text(TextGeom(position: .zero, height: 3, content: "Static revision")))
        ed.doc.blocks["Nested"] = Block(name: "Nested", entities: [text])
        let insert = Entity(layer: "0", geometry: .insert(InsertGeom(block: "Nested", position: Vec2(-80, 10))))
        ed.doc.blocks["Cartiglio"] = Block(name: "Cartiglio", entities: [insert])
        ed.doc.setVariable("TITLEBLOCKBLOCK", "Cartiglio")
        XCTAssertEqual(TitleBlockFields.texts(ed.doc, block: "Cartiglio").map(\.path), ["1/1"])
        var p = EngineObject(); p.set("line", "TBDESIGN Bind Cartiglio 1/1 revision")
        _ = try await session.call("command.run", p.json)
        XCTAssertEqual(TitleBlockFields.texts(ed.doc, block: "Cartiglio").first?.text, "{revision}", ed.log.suffix(12).joined(separator: " | "))
        ed.undo(); XCTAssertEqual(TitleBlockFields.texts(ed.doc, block: "Cartiglio").first?.text, "Static revision")
        _ = try await session.call("command.run", p.json)
        EngineSheets.addRevision(&ed.doc, 0, description: "Issue", by: "NM")
        EngineSheets.addRevision(&ed.doc, 0, description: "Fix", by: "OA")
        ed.doc.layouts[0].titleBlock["revision"] = " "
        let values = SheetRevisionPresentation.fields(ed.doc.layouts[0])
        XCTAssertEqual(values["revision"], "B"); XCTAssertEqual(values["revisionCount"], "2")
        func rendered(_ doc: ArchiDocument) -> [String] {
            EnginePlot.decorations(doc: doc, layout: doc.layouts[0], layoutIndex: 0).flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        }
        XCTAssertTrue(rendered(ed.doc).contains("B"))
        XCTAssertEqual(rendered(try ArchiFile.decode(ArchiFile.encode(ed.doc))), rendered(ed.doc))
        try TitleBlockFields.bind(&ed.doc, block: "Cartiglio", path: "1/1", field: "revisionCount")
        XCTAssertTrue(rendered(ed.doc).contains("2"))
        EngineSheets.setRevisions(&ed.doc, 0, [])
        XCTAssertTrue(rendered(ed.doc).contains("0"))
        XCTAssertThrowsError(try TitleBlockFields.bind(&ed.doc, block: "Cartiglio", path: "1/99", field: "revision"))
        XCTAssertThrowsError(try TitleBlockFields.bind(&ed.doc, block: "Cartiglio", path: "1/1", field: "unknown"))
    }
}
