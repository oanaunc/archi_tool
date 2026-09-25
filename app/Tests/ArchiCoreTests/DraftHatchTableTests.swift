// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class DraftHatchTableTests: XCTestCase {
    func hatch(_ ed: Editor) -> (EntityID, HatchGeom)? {
        for e in ed.doc.entities { if case .hatch(let h) = e.geometry { return (e.id, h) } }
        return nil
    }
    func area(_ h: HatchGeom) -> Double {
        let a = h.loops.map { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) }
        return (a.first ?? 0) - a.dropFirst().reduce(0, +)
    }

    func testAssociativeHatchFollowsPickedBoundary() async {
        let ed = Editor()
        await ed.run("LINE 0,0 1000,0 1000,1000 0,1000 C")
        await ed.run("HATCH 500,500 ")
        guard let (hid, h0) = hatch(ed) else { return XCTFail("no hatch") }
        XCTAssertEqual(area(h0), 1e6, accuracy: 1)
        let e = ed.doc.entity(hid)!
        XCTAssertEqual(e.props[AssociativeHatch.modeProp], "pick")
        XCTAssertEqual(AssociativeHatch.ids(e).count, 4)
        // Stretch the right edge: the hatch grows.
        await ed.run("STRETCH 900,-10 1100,1010 0,0 500,0")
        XCTAssertEqual(area(hatch(ed)!.1), 1.5e6, accuracy: 1)
        // Move the whole boundary: the hatch follows.
        let lineIDs = ed.doc.entities.filter { if case .line = $0.geometry { return true }; return false }.map(\.id)
        await ed.run("MOVE " + lineIDs.map { "#\($0)" }.joined(separator: ",") + "  0,0 5000,0")
        let moved = hatch(ed)!.1
        XCTAssertEqual(area(moved), 1.5e6, accuracy: 1)
        XCTAssertGreaterThan(CommandHelpers.loopPoints(moved.loops[0]).map(\.x).min()!, 4999)
        // Undo restores the previous hatch shape.
        ed.undo()
        XCTAssertLessThan(CommandHelpers.loopPoints(hatch(ed)!.1.loops[0]).map(\.x).min()!, 1)
        // Erasing a boundary line breaks the region: associativity is removed, the hatch stays.
        await ed.run("ERASE #\(lineIDs[0]) ")
        XCTAssertNotNil(hatch(ed))
        XCTAssertNil(ed.doc.entity(hid)?.props[AssociativeHatch.boundaryProp])
    }

    func testAssociativeSelectHatchAndSeparateAndBoundary() async {
        let ed = Editor()
        await ed.run("CIRCLE 0,0 500")
        let c = ed.doc.entities.last!.id
        await ed.run("RECTANG 2000,0 3000,1000")
        let r = ed.doc.entities.last!.id
        await ed.run("HATCH S #\(c),#\(r)  ")
        guard let (hid, h) = hatch(ed) else { return XCTFail() }
        XCTAssertEqual(h.loops.count, 2)
        XCTAssertEqual(ed.doc.entity(hid)?.props[AssociativeHatch.modeProp], "select")
        await ed.run("CHANGE #\(c)  P") // no-op safety
        // Scale the circle via its radius: hatch loop follows.
        ed.transaction("edit") { d in d.entities[d.entityIndex(c)!].geometry = .circle(CircleGeom(.zero, 250)) }
        let loops = hatch(ed)!.1.loops
        XCTAssertEqual(loops.map { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) }.max()!, 1e6, accuracy: 1)
        XCTAssertEqual(loops.map { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) }.min()!, .pi * 250 * 250, accuracy: 600)
        // Separate into two hatches.
        await ed.run("HATCHEDIT #\(hid) H")
        let hs = ed.doc.entities.filter { if case .hatch = $0.geometry { return true }; return false }
        XCTAssertEqual(hs.count, 2)
        // Separate keeps islands with their outer loop.
        let ring = HatchGeom(loops: [[Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)].map { PolyVertex($0) },
                                     [Vec2(40, 40), Vec2(60, 40), Vec2(60, 60), Vec2(40, 60)].map { PolyVertex($0) },
                                     [Vec2(200, 0), Vec2(300, 0), Vec2(300, 100), Vec2(200, 100)].map { PolyVertex($0) }])
        let parts = HatchTools.separate(ring)
        XCTAssertEqual(parts.map(\.loops.count).sorted(), [1, 2])
        // Recreate boundary.
        let ed2 = Editor()
        ed2.doc.add(.hatch(ring))
        let h2 = ed2.doc.entities.last!.id
        await ed2.run("HATCHGENERATEBOUNDARY #\(h2) ")
        XCTAssertEqual(ed2.doc.entities.filter { if case .polyline = $0.geometry { return true }; return false }.count, 3)
        XCTAssertEqual(AssociativeHatch.ids(ed2.doc.entity(h2)!).count, 3)
        // HATCHEDIT properties / color / disassociate.
        await ed2.run("HATCHEDIT #\(h2) P ANSI37 2 45 C 3 DI ")
        guard case .hatch(let e2)? = ed2.doc.entity(h2)?.geometry else { return XCTFail() }
        XCTAssertEqual(e2.pattern, "ANSI37"); XCTAssertEqual(e2.scale, 2); XCTAssertEqual(e2.angle, .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(e2.fill, .aci(3))
        XCTAssertFalse(AssociativeHatch.isAssociative(ed2.doc.entity(h2)!))
    }

    func testDimOverride() async throws {
        let ed = Editor()
        await ed.run("DIMLINEAR 0,0 1000,0 500,300")
        let a = ed.doc.entities.last!.id
        await ed.run("DIMLINEAR 0,0 0,1000 -300,500")
        let b = ed.doc.entities.last!.id
        await ed.run("DIMOVERRIDE DIMTXT 5 DIMDEC 2  #\(a) ")
        guard case .dimension(let da)? = ed.doc.entity(a)?.geometry, case .dimension(let db)? = ed.doc.entity(b)?.geometry else { return XCTFail() }
        XCTAssertNotEqual(da.style, "Standard"); XCTAssertEqual(db.style, "Standard")
        XCTAssertEqual(ed.doc.dimStyle(da.style).textHeight, 5)
        XCTAssertEqual(DimensionRenderer.formatted(da, style: ed.doc.dimStyle(da.style)), "1000.00")
        // Editing the base style propagates, the override stays.
        let si = ed.doc.dimStyles.firstIndex { $0.name == "Standard" }!
        ed.transaction("style") { d in d.dimStyles[si].arrowSize = 7 }
        XCTAssertEqual(ed.doc.dimStyle(da.style).arrowSize, 7)
        XCTAssertEqual(ed.doc.dimStyle(da.style).textHeight, 5)
        // Invalid variable.
        let out = await ed.run("DIMOVERRIDE DIMFOO 1")
        XCTAssertTrue(out.contains { $0.contains("cannot be overridden") })
        // Clear restores the base style and purges the derived one.
        await ed.run("DIMOVERRIDE C #\(a) ")
        guard case .dimension(let dc)? = ed.doc.entity(a)?.geometry else { return XCTFail() }
        XCTAssertEqual(dc.style, "Standard")
        XCTAssertFalse(ed.doc.dimStyles.contains { DimOverrides.isOverrideStyle($0.name) })
        // Round trip.
        await ed.run("DIMOVERRIDE DIMPOST mm  #\(b) ")
        let back = try JSONDecoder().decode(ArchiDocument.self, from: JSONEncoder().encode(ed.doc))
        guard case .dimension(let bb)? = back.entity(b)?.geometry else { return XCTFail() }
        XCTAssertEqual(DimensionRenderer.formatted(bb, style: back.dimStyle(bb.style)), "1000mm")
    }

    func testCSVLinkedTableAndSpell() async throws {
        XCTAssertEqual(TableDataLink.parseCSV("a,\"b,c\",\"d \"\"q\"\"\"\n1,2\n"), [["a", "b,c", "d \"q\""], ["1", "2", ""]])
        XCTAssertEqual(TableDataLink.parseCSV("x;y\n1;2"), [["x", "y"], ["1", "2"]])
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("archi-link-\(UUID().uuidString).csv")
        try "Room,Area\nKitchen,12\nBath,6\n".write(to: url, atomically: true, encoding: .utf8)
        let ed = Editor()
        await ed.run("TABLELINK \(url.path) 0,0")
        guard let t = ed.doc.entities.last, case .table(let tg) = t.geometry else { return XCTFail("no table") }
        XCTAssertEqual(tg.cells, [["Room", "Area"], ["Kitchen", "12"], ["Bath", "6"]])
        try "Room,Area\nKitchen,14\nBath,6\nHall,4\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        XCTAssertEqual(TableDataLink.stale(ed.doc, base: nil), [t.id])
        await ed.run("DATALINKUPDATE U All")
        guard case .table(let t2)? = ed.doc.entity(t.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(t2.cells.count, 4); XCTAssertEqual(t2.cells[1][1], "14")
        XCTAssertEqual(TableDataLink.stale(ed.doc, base: nil), [])
        // Write back.
        ed.transaction("cell") { d in if case .table(var x) = d.entities[d.entityIndex(t.id)!].geometry { x.cells[3][1] = "5"; d.entities[d.entityIndex(t.id)!].geometry = .table(x) } }
        await ed.run("DATALINKUPDATE W All")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("Hall,5"))
        try? FileManager.default.removeItem(at: url)

        // Spell check word extraction and replacement.
        XCTAssertEqual(SpellCheck.words(in: "\\fArial;Teh wall's 2x4 {\\C1;recieve} A-1 %<Area(3)>%"), ["Teh", "wall's", "recieve"])
        await ed.run("TEXT 0,-1000 250 0 Teh kitchen recieve NOTE")
        let known: Set<String> = ["kitchen", "room", "area", "bath", "hall"]
        let bad = SpellCheck.misspelled(ed.doc, isCorrect: { known.contains($0.lowercased()) })
        XCTAssertEqual(Set(bad.map(\.word)), ["Teh", "recieve"], "all-caps words are skipped")
        SpellCheck.checker = { known.contains($0.lowercased()) || $0 == "The" || $0 == "receive" }
        defer { SpellCheck.checker = nil }
        await ed.run("SPELL All The receive")
        guard case .text(let tx)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        XCTAssertEqual(tx.content, "The kitchen receive NOTE")
        await ed.run("TEXT 0,-2000 250 0 Oanarina")
        await ed.run("SPELL All Add")
        XCTAssertTrue(SpellCheck.customWords(ed.doc).contains("oanarina"))
        XCTAssertTrue(SpellCheck.misspelled(ed.doc, isCorrect: SpellCheck.checker!).isEmpty)
    }
}
