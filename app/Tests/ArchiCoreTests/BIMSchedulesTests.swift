// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Stored schedules: fields, calculated fields, filters, sorting, grouping, totals, round-trip editing, CSV/XLSX,
/// material takeoff, key schedules, sheet/view lists, embedded rows and associative tables on sheets.
@MainActor
final class BIMSchedulesTests: XCTestCase {
    func house() async -> Editor {
        let ed = Editor()
        await ed.run("WALL 0,0 8000,0 8000,5000 0,5000 C")
        await ed.run("WALL 4000,0 4000,5000 ")
        await ed.run("DOOR 2000,0 ")
        await ed.run("DOOR T \"Double Door 1600x2100\" 6000,0 ")
        await ed.run("WINDOW 2000,5000 ")
        await ed.run("ROOM 2000,2500 ")
        await ed.run("ROOM Name Kitchen 6000,2500 ")
        return ed
    }

    func testDefineFieldsFiltersSortGroupTotals() async throws {
        let ed = await house()
        await ed.run("SCHEDULE Define New Doors doors")
        await ed.run("SCHEDULE Define Fields Doors \"mark, Type, width, height, Area=width*height/1e6, Share%Area\"")
        await ed.run("SCHEDULE Define Sort Doors \"width desc\"")
        await ed.run("SCHEDULE Define Totals Doors Yes")
        let def = try XCTUnwrap(ed.doc.schedules.first)
        XCTAssertEqual(def.fields.map(\.name), ["mark", "Type", "width", "height", "Area", "Share"])
        var t = Schedules.evaluate(def, doc: ed.doc)
        XCTAssertEqual(t.headings, ["mark", "Type", "width", "height", "Area", "Share"])
        let items = t.rows.filter { $0.kind == .item }
        XCTAssertEqual(items.map { $0.cells[2] }, ["1600", "900"], "sorted by width descending")
        XCTAssertEqual(Double(items[0].cells[4])!, 1.6 * 2.1, accuracy: 1e-6)
        XCTAssertEqual(items[0].cells[5], String(format: "%.1f%%", 3.36 / (3.36 + 1.89) * 100))
        let total = try XCTUnwrap(t.rows.last)
        XCTAssertEqual(total.kind, .grandTotal)
        XCTAssertEqual(Double(total.cells[4])!, 3.36 + 1.89, accuracy: 1e-6)
        // Filter.
        await ed.run("SCHEDULE Define Filter Doors \"width > 1000\"")
        t = Schedules.evaluate(ed.doc.schedules[0], doc: ed.doc)
        XCTAssertEqual(t.rows.filter { $0.kind == .item }.count, 1)
        // Grouping rooms by level with subtotals, and non-itemized counts.
        await ed.run("SCHEDULE Define New Rooms rooms")
        await ed.run("SCHEDULE Define Group Rooms Level")
        await ed.run("SCHEDULE Define Totals Rooms Yes")
        let rt = Schedules.evaluate(ed.doc.schedules[1], doc: ed.doc)
        XCTAssertEqual(rt.rows.first?.kind, .groupHeader)
        XCTAssertEqual(rt.rows.first?.cells.first, "Ground Floor")
        XCTAssertTrue(rt.rows.contains { $0.kind == .groupTotal })
        await ed.run("SCHEDULE Define Itemize Rooms No")
        let summary = Schedules.evaluate(ed.doc.schedules[1], doc: ed.doc)
        XCTAssertEqual(summary.rows.filter { $0.kind == .item }.count, 1)
        // Highlight rule.
        await ed.run("SCHEDULE Define Itemize Rooms Yes")
        await ed.run("SCHEDULE Define Highlight Rooms \"Name = Kitchen\" yellow")
        let hl = Schedules.evaluate(ed.doc.schedules[1], doc: ed.doc).rows.filter { $0.highlight != nil }
        XCTAssertEqual(hl.count, 1); XCTAssertTrue(hl[0].cells.contains("Kitchen"))
        // Persistence.
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        XCTAssertEqual(back.schedules, ed.doc.schedules)
    }

    func testRoundTripEditingAndCSVXLSX() async throws {
        let ed = await house()
        await ed.run("SCHEDULE Define New Doors doors")
        // Edit a cell: row 1 is the first door (D01).
        await ed.run("SCHEDULE Edit Doors 1 width 1000")
        let d1 = ed.doc.elements.first { if case .opening(let o) = $0.geometry { return o.mark == "D01" }; return false }!
        if case .opening(let o) = d1.geometry { XCTAssertEqual(o.width, 1000, accuracy: 1e-9) }
        // Read-only fields are refused.
        var d = ed.doc
        XCTAssertFalse(Schedules.edit(ed.doc.schedules[0], row: 0, field: "Count", value: "5", doc: &d))
        // Export CSV, edit it, read it back.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sched-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let csvURL = dir.appendingPathComponent("doors.csv")
        await ed.run("SCHEDULE Export Doors \"\(csvURL.path)\"")
        var rows = Schedules.parseCSV(try String(contentsOf: csvURL, encoding: .utf8))
        XCTAssertEqual(rows[0].first, "ElementID")
        let hCol = rows[0].firstIndex(of: "height")!
        rows[1][hCol] = "2200"
        let lvl = rows[0].firstIndex(of: "Level")!
        rows[2][lvl] = "First Floor"
        let edited = rows.map { $0.joined(separator: ",") }.joined(separator: "\n")
        try edited.write(to: csvURL, atomically: true, encoding: .utf8)
        await ed.run("SCHEDULE Import Doors \"\(csvURL.path)\"")
        let ops = ed.doc.elements.filter { if case .opening(let o) = $0.geometry { return o.kind == .door }; return false }
        if case .opening(let o) = ops[0].geometry { XCTAssertEqual(o.height, 2200, accuracy: 1e-9) }
        XCTAssertEqual(ops[1].level, 1)
        // XLSX export → read back → apply.
        let xURL = dir.appendingPathComponent("doors.xlsx")
        await ed.run("SCHEDULE Export Doors \"\(xURL.path)\"")
        var sheet = try XCTUnwrap(try XLSX.read(Data(contentsOf: xURL)).first)
        XCTAssertEqual(sheet.rows.first?.first, "ElementID")
        let wCol = sheet.rows[0].firstIndex(of: "width")!
        sheet.rows[1][wCol] = "950"
        var doc = ed.doc
        let r = Schedules.applyEdits(ed.doc.schedules[0], rows: sheet.rows, doc: &doc)
        XCTAssertEqual(r.changed, 1)
        if case .opening(let o)? = doc.element(Int(sheet.rows[1][0])!)?.geometry { XCTAssertEqual(o.width, 950, accuracy: 1e-9) }
        // Changing a computed column is rejected.
        sheet.rows[1][sheet.rows[0].firstIndex(of: "Count")!] = "7"
        XCTAssertFalse(Schedules.applyEdits(ed.doc.schedules[0], rows: sheet.rows, doc: &doc).rejected.isEmpty)
        // Custom parameter columns write instance parameters.
        doc.schedules[0].fields.append(ScheduleField(name: "FireRating"))
        var rows2 = Schedules.evaluate(doc.schedules[0], doc: doc).rows.filter { $0.kind == .item }.map { ["\($0.elementID!)"] + $0.cells }
        rows2.insert(["ElementID"] + doc.schedules[0].fields.map(\.title), at: 0)
        rows2[1][rows2[0].count - 1] = "EI30"
        _ = Schedules.applyEdits(doc.schedules[0], rows: rows2, doc: &doc)
        XCTAssertEqual(doc.element(Int(rows2[1][0])!)?.props["FireRating"], "EI30")
    }

    func testMaterialTakeoffKeysListsAndEmbedded() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 ")
        ed.transaction("Type") { doc in
            if case .wall(var w) = doc.elements[0].geometry { w.wallType = "Exterior Brick 365"; w.thickness = 365; doc.elements[0].geometry = .wall(w) }
        }
        await ed.run("SCHEDULE Define New Takeoff materials")
        await ed.run("SCHEDULE Define Group Takeoff Material")
        await ed.run("SCHEDULE Define Itemize Takeoff No")
        let t = Schedules.evaluate(ed.doc.schedules[0], doc: ed.doc)
        let brick = try XCTUnwrap(t.rows.first { $0.cells.first == "Brick" })
        let vi = t.headings.firstIndex(of: "Volume")!, ai = t.headings.firstIndex(of: "Area")!
        XCTAssertEqual(Double(brick.cells[vi])!, 0.24 * 5 * 3, accuracy: 0.05)
        XCTAssertEqual(Double(brick.cells[ai])!, 5 * 3, accuracy: 0.2)
        let plaster = try XCTUnwrap(t.rows.first { $0.cells.first == "Plaster" })
        XCTAssertEqual(Double(plaster.cells[vi])!, 0.025 * 5 * 3, accuracy: 0.01)
        // Key schedule: room style keys push finishes onto rooms.
        await ed.run("WALL 0,1000 4000,1000 4000,4000 0,4000 C")
        await ed.run("ROOM 2000,2500 ")
        await ed.run("SCHEDULE Define New Styles keys")
        await ed.run("SCHEDULE Define Key Styles \"Room Style\" Office \"Floor=Carpet; Ceiling=Tile\"")
        let rid = ed.doc.elements.last { if case .space = $0.geometry { return true }; return false }!.id
        ed.transaction("Key") { doc in doc.elements[doc.elementIndex(rid)!].props["Room Style"] = "Office" }
        XCTAssertEqual(ed.doc.element(rid)?.props["Floor"], "Carpet")
        let keys = Schedules.evaluate(ed.doc.schedules[1], doc: ed.doc)
        XCTAssertEqual(keys.headings, ["Key", "Ceiling", "Floor"])
        XCTAssertEqual(keys.rows.first?.cells, ["Office", "Tile", "Carpet"])
        // Sheet and view lists.
        await ed.run("SCHEDULE Define New Sheets sheets")
        XCTAssertEqual(Schedules.evaluate(ed.doc.schedules[2], doc: ed.doc).rows.count, ed.doc.layouts.count)
        // Embedded: doors listed under their room.
        await ed.run("DOOR 2000,1000 ")
        var rooms = ScheduleDefinition(name: "R", category: "rooms", embedded: "doors")
        rooms.fields = [ScheduleField(name: "number"), ScheduleField(name: "Name")]
        let er = Schedules.evaluate(rooms, doc: ed.doc).rows
        XCTAssertEqual(er.filter { $0.kind == .embedded }.count, 1)
    }

    func testPlacedScheduleSplitsAndFollowsModel() async throws {
        let ed = await house()
        await ed.run("SCHEDULE Define New Doors doors")
        await ed.run("SCHEDULE Place Doors \"Sheet 1\" 20,20 1")
        var tables = ed.doc.layouts[0].entities.filter { $0.props[Schedules.placedProp] == "Doors" }
        XCTAssertEqual(tables.count, 2, "two doors, one row per column")
        // Adding a door re-evaluates the placed schedule into three columns.
        await ed.run("DOOR 6000,5000 ")
        tables = ed.doc.layouts[0].entities.filter { $0.props[Schedules.placedProp] == "Doors" }
        XCTAssertEqual(tables.count, 3)
        guard case .table(let g) = tables[0].geometry else { return XCTFail() }
        XCTAssertEqual(g.cells[0][0], "Doors"); XCTAssertEqual(g.cells.count, 3)
        // Editing the model updates the cell text.
        let door = ed.doc.elements.first { if case .opening(let o) = $0.geometry { return o.mark == "D01" }; return false }!
        ed.transaction("w") { doc in if case .opening(var o) = doc.elements[doc.elementIndex(door.id)!].geometry { o.width = 1111; doc.elements[doc.elementIndex(door.id)!].geometry = .opening(o) } }
        let texts = ed.doc.layouts[0].entities.compactMap { e -> [[String]]? in if case .table(let g) = e.geometry { return g.cells }; return nil }.flatMap { $0 }.flatMap { $0 }
        XCTAssertTrue(texts.contains("1111"))
    }
}
