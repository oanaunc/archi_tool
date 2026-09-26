// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Project and shared parameters in schedules, tags, filters and geometry; sheet/view/note lists.
@MainActor
final class BIMProjectParametersTests: XCTestCase {
    func testProjectParametersFlowToSchedulesTagsAndGeometry() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("DOOR 2000,0 ")
        await ed.run("WINDOW 6000,0 ")
        await ed.run("ROOM 4000,2500 ")
        await ed.run("GLOBALPARAM Project New FireRating Text \"door,window\" EI30")
        await ed.run("GLOBALPARAM Project New Cost Number rooms \"=Area*1200\"")
        await ed.run("GLOBALPARAM Project New SillH Length window 1100")
        let door = ed.doc.elements.first { $0.typeName == "door" }!, win = ed.doc.elements.first { $0.typeName == "window" }!
        let room = ed.doc.elements.first { $0.typeName == "space" }!
        XCTAssertEqual(ProjectParameters.value("FireRating", of: door, doc: ed.doc), "EI30")
        XCTAssertNil(ProjectParameters.value("FireRating", of: ed.doc.elements[0], doc: ed.doc), "walls do not have it")
        // Instance value overrides the default; schedules and tags read it.
        ed.selection = [door.id]
        await ed.run("GLOBALPARAM Project Value FireRating EI60")
        var def = ScheduleDefinition(name: "D", category: "openings")
        def.fields = [ScheduleField(name: "mark"), ScheduleField(name: "FireRating")]
        let t = Schedules.evaluate(def, doc: ed.doc)
        XCTAssertEqual(t.rows.map { $0.cells[1] }, ["EI60", "EI30"])
        XCTAssertEqual(Annotations.tagText(ed.doc.element(win.id)!, field: "FireRating", doc: ed.doc), "EI30")
        // Formula parameter: computed from the room area.
        let cost = Double(ProjectParameters.value("Cost", of: ed.doc.element(room.id)!, doc: ed.doc) ?? "") ?? 0
        XCTAssertEqual(cost, 7.8 * 4.8 * 1200, accuracy: 1)
        // A view filter on the project parameter.
        await ed.run("VG Filters New Rated \"door,window\" \"FireRating = EI60\" hide")
        let es = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: 0))
        XCTAssertFalse(es.contains { $0.id == door.id }); XCTAssertTrue(es.contains { $0.id == win.id })
        // Drives geometry: the window sill follows the parameter.
        ed.selection = [win.id]
        await ed.run("GLOBALPARAM Bind sill SillH")
        guard case .opening(let o1)? = ed.doc.element(win.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(o1.sill, 1100, accuracy: 1e-9)
        ed.transaction("p") { doc in doc.elements[doc.elementIndex(win.id)!].props["SillH"] = "800" }
        guard case .opening(let o2)? = ed.doc.element(win.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(o2.sill, 800, accuracy: 1e-9)
        // Persistence.
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(back.projectParameters.count, 3)
    }

    func testSharedParameterFileRoundTrip() async throws {
        let ed = Editor()
        await ed.run("GLOBALPARAM Project New AcousticRating Text walls \"\"")
        await ed.run("GLOBALPARAM Project New UValue Number \"walls,windows\" 0.3")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shared-\(UUID().uuidString).txt")
        await ed.run("GLOBALPARAM Shared Export \"\(url.path)\"")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("PARAM\t")); XCTAssertTrue(text.contains("\tUValue\tNUMBER\t"))
        let guid = try XCTUnwrap(ed.doc.projectParameters.first { $0.name == "UValue" }?.guid)
        let ed2 = Editor()
        await ed2.run("GLOBALPARAM Shared Import \"\(url.path)\" UValue windows")
        XCTAssertEqual(ed2.doc.projectParameters.count, 1)
        XCTAssertEqual(ed2.doc.projectParameters[0].guid, guid)
        XCTAssertEqual(ed2.doc.projectParameters[0].kind, .number)
        XCTAssertEqual(ed2.doc.projectParameters[0].categories, ["windows"])
        // Re-import binds by GUID (no duplicate).
        await ed2.run("GLOBALPARAM Shared Import \"\(url.path)\" All All")
        XCTAssertEqual(ed2.doc.projectParameters.count, 2)
    }

    func testSheetViewAndNoteBlockLists() async throws {
        let ed = Editor()
        ed.doc.layouts = [Layout(name: "A101", viewports: [Viewport(origin: .zero, size: Vec2(200, 150), viewCenter: .zero, title: "Ground plan")], titleBlock: ["sheetNumber": "A101", "revision": "B"]),
                          Layout(name: "A201")]
        ed.doc.namedViews = [NamedView(name: "Entrance", center: .zero, height: 5000)]
        ed.doc.blocks["NOTE"] = Block(name: "NOTE")
        for k in 0..<3 { ed.doc.add(.insert(InsertGeom(block: "NOTE", position: Vec2(Double(k) * 1000, 0), attributes: ["NUM": "\(k % 2 + 1)"]))) }
        await ed.run("SCHEDULE Define New Sheets sheets")
        let sheets = Schedules.evaluate(ed.doc.schedules[0], doc: ed.doc)
        XCTAssertEqual(sheets.rows.map { $0.cells[0] }, ["A101", "2"])
        XCTAssertEqual(sheets.rows[0].cells[3], "B")
        await ed.run("SCHEDULE Define New Views views")
        let views = Schedules.evaluate(ed.doc.schedules[1], doc: ed.doc)
        XCTAssertEqual(Set(views.rows.map { $0.cells[0] }), ["Entrance", "Ground plan"])
        // Note block schedule: count by attribute.
        var notes = ScheduleDefinition(name: "Notes", category: "annotations", fields: [ScheduleField(name: "NUM"), ScheduleField(name: "Count")], groupBy: "NUM", itemize: false)
        notes.sort = [ScheduleSort(field: "NUM")]
        let nt = Schedules.evaluate(notes, doc: ed.doc)
        XCTAssertEqual(nt.rows.map(\.cells), [["1", "2"], ["2", "1"]])
    }
}
