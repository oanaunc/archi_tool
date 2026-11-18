// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor final class OpeningSizeTests: XCTestCase {
    func testCentimeterDoorDefaultsResizeAndCompactTags() async throws {
        var doc = ArchiDocument()
        doc.units = .centimeters
        let wall = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(800, 0), thickness: 20, height: 300)))
        let ed = Editor(document: doc)
        await ed.run("SETVAR AUTOTAG 1")
        await ed.run("OPENINGSIZES Automatic Centimetres ")
        let log = await ed.run("DOORS 200,0 ")
        XCTAssertTrue(log.contains { $0.contains("Door (cm): Width = 90, Height = 210") })
        let door = try XCTUnwrap(ed.doc.elements.first { $0.id != wall })
        guard case .opening(let opening) = door.geometry else { return XCTFail("Missing door") }
        XCTAssertEqual(opening.hostWall, wall)
        XCTAssertEqual(opening.width, 90)
        XCTAssertEqual(opening.height, 210)
        XCTAssertEqual(opening.frameWidth, 5)
        let tags = ed.doc.entities.filter { $0.props["tagOf"] == String(door.id) }
        XCTAssertEqual(tags.count, 2)
        let size = try XCTUnwrap(tags.first { $0.props["tagField"] == "sizecm" })
        for tag in tags {
            guard case .text(let t) = tag.geometry else { return XCTFail("Missing tag text") }
            XCTAssertEqual(t.height, 10)
        }
        await ed.run("SETPROP #\(door.id) Width 85.5")
        let rendered = DrawListBuilder.items(for: size, doc: ed.doc, options: DrawOptions())
        XCTAssertTrue(rendered.contains { if case .text(let t, _, _) = $0 { return t.content == "85.5×210 cm" && t.height == 10 }; return false })
        ed.undo()
        XCTAssertEqual(Annotations.text(size, doc: ed.doc), "90×210 cm")
        ed.redo()
        let reopened = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(reopened.entity(size.id), size)
        XCTAssertEqual(Annotations.text(size, doc: reopened), "85.5×210 cm")
    }

    func testCentimeterStockTypesExplicitDimensionsAndLegacyReset() async throws {
        var doc = ArchiDocument()
        doc.units = .centimeters
        doc.openingTypes = OpeningType.library // Old non-mm files stored the raw millimeter catalog.
        doc.setVariable("DOORWIDTH", "900")
        doc.setVariable("DOORHEIGHT", "2100")
        doc.openingTypes.append(OpeningType(name: "Custom", kind: .door, width: 85, height: 205, frameWidth: 4))
        _ = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(1000, 0), thickness: 20, height: 300)))
        let ed = Editor(document: try ArchiFile.decode(ArchiFile.encode(doc)))
        XCTAssertEqual(ed.doc.openingType("Custom")?.width, 85)
        await ed.run("DOOR Reset 100,0 ")
        await ed.run("DOOR Type \"Single Door 800x2100\" 300,0 ")
        await ed.run("DOOR Width 875mm Height 205 500,0 ")
        await ed.run("DOOR 700,0 ")
        await ed.run("WIN 900,0 ")
        let openings = ed.doc.elements.compactMap { if case .opening(let o) = $0.geometry { return o }; return nil }
        XCTAssertEqual(openings.map(\.width), [90, 80, 87.5, 87.5, 120])
        XCTAssertEqual(openings.map(\.height), [210, 210, 205, 205, 120])
        XCTAssertEqual(openings.map(\.frameWidth), [5, 5, 5, 5, 5])
        XCTAssertEqual(openings.last?.sill, 90)
        XCTAssertNil(ed.doc.variable("DOORTYPE"))
    }

    func testChangingUnitsScalesRememberedSizesAndFutureAutomaticTagHeight() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 ")
        await ed.run("OPENINGSIZES Automatic Centimetres 120")
        await ed.run("DOOR Width 850 2000,0 ")
        await ed.run("UNITS Centimeters 2 Yes")
        await ed.run("DOOR 500,0 ")
        let openings = ed.doc.elements.compactMap { if case .opening(let o) = $0.geometry { return o }; return nil }
        XCTAssertEqual(openings.map(\.width), [85, 85])
        XCTAssertEqual(openings.map(\.height), [210, 210])
        XCTAssertEqual(ed.doc.entities.compactMap { if case .text(let t) = $0.geometry { return t.height }; return nil }, [12, 12])
        ed.undo()
        ed.undo()
        XCTAssertEqual(ed.doc.units, .millimeters)
        XCTAssertEqual(ed.doc.variable("OPENINGSIZETAGHEIGHT"), "120.0")
    }

    func testPortableUnitsDialogAndScriptingUseCentimeterDefaults() async throws {
        let session = EngineSession()
        _ = try await session.call("units.set", try EngineJSON.parse(#"{"units":"centimeters"}"#))
        let wall = session.editor.doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(800, 0), thickness: 20, height: 300)))
        let reply = try await session.call("script.call", try EngineJSON.parse(#"{"fn":"door","args":[\#(wall),200,{"width":85}]}"#))
        let door = try XCTUnwrap(reply.intValue)
        guard case .opening(let o)? = session.editor.doc.element(door)?.geometry else { return XCTFail("Missing scripted door") }
        XCTAssertEqual(o.width, 85)
        XCTAssertEqual(o.height, 210)
        XCTAssertEqual(o.frameWidth, 5)
        session.editor.selection = [door]
        _ = try await session.call("panel.set", try EngineJSON.parse(#"{"panel":"properties","key":"width","value":"90"}"#))
        XCTAssertEqual(PropertyAccess.getProperty(try XCTUnwrap(session.editor.doc.element(door)), "width"), "90")
        session.editor.undo()
        XCTAssertEqual(PropertyAccess.getProperty(try XCTUnwrap(session.editor.doc.element(door)), "width"), "85")
    }

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

    func testVisibleSpanningWallOpeningsGetPerPlanSizesAndReposition() async throws {
        var doc = ArchiDocument()
        let wall = doc.addElement(.wall(WallGeom(start: .zero, end: Vec2(8000, 0), thickness: 200, height: 6000)), level: 0)
        let door = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: wall, offset: 2000, width: 900, height: 5000)), level: 0)
        let window = doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: wall, offset: 5000, width: 1200, height: 5000)), level: 0)
        let ed = Editor(document: doc)
        await ed.run("OPENINGSIZES All Drawing 100")
        let groundTags = ed.doc.entities
        ed.doc.currentLevel = 1
        await ed.run("QUOTAINFISSI All Centimetres 100")
        let upperTags = ed.doc.entities.filter { $0.props["level"] == "1" }
        XCTAssertEqual(upperTags.count, 2)
        XCTAssertEqual(Set(upperTags.compactMap { $0.props["tagOf"].flatMap(Int.init) }), [door, window])
        XCTAssertTrue(groundTags.allSatisfy { ed.doc.entity($0.id) == $0 })
        var options = DrawOptions(); options.level = 1
        let entries = DrawListBuilder.entries(doc: ed.doc, options: options)
        XCTAssertTrue(upperTags.allSatisfy { tag in entries.contains { $0.id == tag.id } })
        let tag = try XCTUnwrap(upperTags.first)
        let i = try XCTUnwrap(ed.doc.entityIndex(tag.id))
        if case .text(var text) = ed.doc.entities[i].geometry { text.position = Vec2(99999, 99999); ed.doc.entities[i].geometry = .text(text) }
        let displaced = ed.doc.entities[i]
        await ed.run("OPENINGSIZES Reposition Drawing 100")
        XCTAssertNotEqual(ed.doc.entity(tag.id)?.geometry, displaced.geometry)
        XCTAssertEqual(ed.doc.entities.count, 4)
        ed.undo(); XCTAssertEqual(ed.doc.entity(tag.id), displaced)
        ed.redo()
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(restored.entities, ed.doc.entities)
        let copied = ed.transformObjects([wall, tag.id], .translation(Vec2(10000, 0)), copy: true)
        let copiedTag = try XCTUnwrap(copied.compactMap(ed.doc.entity).first)
        XCTAssertEqual(copiedTag.props["level"], "1")
        XCTAssertTrue(DrawListBuilder.entries(doc: ed.doc, options: options).contains { $0.id == copiedTag.id })
    }

    func testCopiedOpeningTagsFollowCopiedDoorAndImplicitWallOpenings() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 10000,0 ")
        await ed.run("DOOR 2000,0 ")
        await ed.run("OPENINGSIZES Doors Drawing 100")
        let door = try XCTUnwrap(ed.doc.elements.first { if case .opening = $0.geometry { return true }; return false })
        let tag = try XCTUnwrap(ed.doc.entities.first)
        await ed.run("COPY #\(door.id),#\(tag.id)  0,0 3000,0 ")
        let copiedDoor = try XCTUnwrap(ed.doc.elements.last)
        let copiedTag = try XCTUnwrap(ed.doc.entities.last)
        XCTAssertNotEqual(copiedDoor.id, door.id)
        XCTAssertEqual(copiedTag.props["tagOf"], String(copiedDoor.id))
        XCTAssertTrue(PropertyAccess.set("width", "800", of: copiedDoor.id, in: &ed.doc))
        XCTAssertEqual(Annotations.text(copiedTag, doc: ed.doc), "800×2100")
        XCTAssertEqual(Annotations.text(tag, doc: ed.doc), "900×2100")
        ed.undo(); XCTAssertNil(ed.doc.entity(copiedTag.id))
        ed.redo(); XCTAssertEqual(ed.doc.entity(copiedTag.id)?.props["tagOf"], String(copiedDoor.id))
        let wall = try XCTUnwrap(ed.doc.elements.first)
        let results = ed.transformObjects([wall.id, tag.id], .translation(Vec2(0, 3000)), copy: true)
        let wallTag = try XCTUnwrap(results.compactMap(ed.doc.entity).first)
        let linked = try XCTUnwrap(wallTag.props["tagOf"].flatMap(Int.init).flatMap(ed.doc.element))
        XCTAssertNotEqual(linked.id, door.id)
        guard case .opening(let o) = linked.geometry else { return XCTFail("Missing copied opening") }
        XCTAssertNotEqual(o.hostWall, wall.id)
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(restored.entity(wallTag.id)?.props["tagOf"], String(linked.id))
    }

    func testTagOnlyCopyAndExplicitRehostThroughPortableAPI() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 10000,0 ")
        await ed.run("DOOR 2000,0 ")
        await ed.run("DOOR Width 800 5000,0 ")
        await ed.run("OPENINGSIZES Doors Drawing 100")
        let sourceTag = try XCTUnwrap(ed.doc.entities.first)
        let target = try XCTUnwrap(ed.doc.elements.last)
        let result = ed.transformObjects([sourceTag.id], .translation(Vec2(3000, 0)), copy: true)
        let copy = try XCTUnwrap(result.first.flatMap(ed.doc.entity))
        XCTAssertEqual(copy.props["tagOf"], String(target.id))
        XCTAssertEqual(Annotations.text(copy, doc: ed.doc), "800×2100")
        let clip = DraftClipboard.capture([sourceTag.id], from: ed.doc, base: .zero)
        let pasted = clip.paste(into: &ed.doc, offset: Vec2(3000, 0))
        XCTAssertEqual(pasted.first.flatMap(ed.doc.entity)?.props["tagOf"], String(target.id))
        // An unmatched displacement must not guess a remote target.
        let unmatched = ed.transformObjects([sourceTag.id], .translation(Vec2(0, 3000)), copy: true)
        let stale = try XCTUnwrap(unmatched.first.flatMap(ed.doc.entity))
        XCTAssertEqual(stale.props["tagOf"], sourceTag.props["tagOf"])
        ed.selection = [stale.id]
        let session = EngineSession(editor: ed)
        _ = try await session.call("command.run", try EngineJSON.parse(#"{"line":"TAGFORMAT Rehost #\#(target.id)"}"#))
        XCTAssertEqual(ed.doc.entity(stale.id)?.props["tagOf"], String(target.id))
        XCTAssertEqual(Annotations.text(ed.doc.entity(stale.id)!, doc: ed.doc), "800×2100")
        ed.undo(); XCTAssertEqual(ed.doc.entity(stale.id), stale)
        ed.redo()
        let restored = try ArchiFile.decode(ArchiFile.encode(ed.doc))
        XCTAssertEqual(Annotations.text(restored.entity(stale.id)!, doc: restored), "800×2100")
        _ = ed.doc.addElement(target.geometry)
        let ambiguous = ed.transformObjects([sourceTag.id], .translation(Vec2(3000, 0)), copy: true)
        XCTAssertEqual(ambiguous.first.flatMap(ed.doc.entity)?.props["tagOf"], sourceTag.props["tagOf"])
        ed.doc.currentLevel = 1
        let otherLevel = ed.transformObjects([sourceTag.id], .translation(Vec2(3000, 0)), copy: true)
        XCTAssertEqual(otherLevel.first.flatMap(ed.doc.entity)?.props["tagOf"], sourceTag.props["tagOf"])
    }

    func testClipboardWallAndTagRemapAcrossLevels() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 ")
        await ed.run("DOOR 2000,0 ")
        await ed.run("OPENINGSIZES All Drawing 100")
        let wall = try XCTUnwrap(ed.doc.elements.first)
        let tag = try XCTUnwrap(ed.doc.entities.first)
        let clip = DraftClipboard.capture([wall.id, tag.id], from: ed.doc, base: .zero)
        let ids = clip.paste(into: &ed.doc, offset: Vec2(0, 4000), level: 1)
        let copied = try XCTUnwrap(ids.compactMap(ed.doc.entity).first)
        let target = try XCTUnwrap(copied.props["tagOf"].flatMap(Int.init).flatMap(ed.doc.element))
        XCTAssertNotEqual(target.id, tag.props["tagOf"].flatMap(Int.init))
        XCTAssertEqual(target.level, 1)
        XCTAssertEqual(copied.props["level"], "1")
        XCTAssertTrue(PropertyAccess.set("width", "750", of: target.id, in: &ed.doc))
        XCTAssertEqual(Annotations.text(copied, doc: ed.doc), "750×2100")
    }

}
