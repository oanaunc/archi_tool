// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Acceptance checks for block definitions (BLK-001), nested blocks (BLK-006), groups (BLK-015/016),
/// ByLayer/ByBlock resolution (LAY-031), text styles (ANN-004) and dimension styles (ANN-031).
@MainActor
final class DraftPartialsVerifyTests: XCTestCase {
    func strokes(_ doc: ArchiDocument, _ id: EntityID) -> [(pts: [Vec2], style: StrokeStyle)] {
        let es = DrawListBuilder.entries(doc: doc, options: DrawOptions()).filter { $0.id == id }
        return es.flatMap(\.items).compactMap { if case .stroke(let p, _, let s) = $0 { return (p, s) }; return nil }
    }
    func roundTrip(_ d: ArchiDocument) throws -> ArchiDocument { try DXFReader.read(DXFWriter.write(d)) }

    func testNestedBlocksRenderExplodeAndRoundTrip() async throws {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        await ed.run("BLOCK INNER 0,0 ALL ")
        await ed.run("CIRCLE 300,0 50 ")
        await ed.run("BLOCK OUTER 0,0 ALL ")
        XCTAssertEqual(ed.doc.blocks["OUTER"]?.entities.count, 2)
        await ed.run("ERASE ALL ")
        await ed.run("INSERT OUTER 1000,0 2 2 90")
        guard let ins = ed.doc.entities.last, case .insert = ins.geometry else { return XCTFail("no insert") }
        let st = strokes(ed.doc, ins.id)
        XCTAssertEqual(st.count, 2)
        let all = st.flatMap(\.pts)
        XCTAssertTrue(all.contains { $0.distance(to: Vec2(1000, 200)) < 1e-6 }, "inner line end transformed through both inserts")
        // Round-trip keeps the nesting and the rendered geometry.
        let rt = try roundTrip(ed.doc)
        XCTAssertNotNil(rt.blocks["INNER"]); XCTAssertNotNil(rt.blocks["OUTER"])
        XCTAssertTrue(rt.blocks["OUTER"]!.entities.contains { if case .insert(let i) = $0.geometry { return i.block == "INNER" }; return false })
        guard let rins = rt.entities.first(where: { if case .insert = $0.geometry { return true }; return false }) else { return XCTFail("insert lost") }
        let rst = strokes(rt, rins.id).flatMap(\.pts)
        XCTAssertTrue(rst.contains { $0.distance(to: Vec2(1000, 200)) < 1e-6 })
        // Explode one level: an INNER insert and a circle remain.
        await ed.run("EXPLODE #\(ins.id) ")
        let inner = ed.doc.entities.compactMap { e -> InsertGeom? in if case .insert(let i) = e.geometry { return i }; return nil }
        XCTAssertEqual(inner.count, 1); XCTAssertEqual(inner.first?.block, "INNER")
        XCTAssertEqual(inner.first?.scale, Vec2(2, 2)); XCTAssertEqual(inner.first?.rotation ?? 0, .pi / 2, accuracy: 1e-9)
        XCTAssertTrue(ed.doc.entities.contains { if case .circle(let c) = $0.geometry { return abs(c.radius - 100) < 1e-6 && c.center.distance(to: Vec2(1000, 600)) < 1e-6 }; return false })
    }

    func testGroupsRoundTripAndUngroup() async throws {
        let ed = Editor()
        await ed.run("LINE 0,0 100,0 ")
        await ed.run("LINE 0,50 100,50 ")
        await ed.run("GROUP G1 ALL ")
        XCTAssertEqual(BlockTools.groups(ed.doc)["G1"]?.count, 2)
        let rt = try roundTrip(ed.doc)
        XCTAssertEqual(BlockTools.groups(rt)["G1"]?.count, 2)
        await ed.run("UNGROUP ALL ")
        XCTAssertTrue(BlockTools.groups(ed.doc).isEmpty)
    }

    func testByBlockNestedResolution() async throws {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "A", color: RGBA(0, 1, 0), linetype: "Dashed", lineweight: 0.7))
        d.blocks["IN"] = Block(name: "IN", entities: [Entity(layer: "0", color: .byBlock, linetype: "ByBlock", lineweight: -2, geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))])
        d.blocks["OUT"] = Block(name: "OUT", entities: [Entity(layer: "0", color: .byBlock, linetype: "ByBlock", lineweight: -2, geometry: .insert(InsertGeom(block: "IN", position: .zero)))])
        let red = d.add(Entity(layer: "A", color: .aci(1), linetype: "Hidden", lineweight: 0.5, geometry: .insert(InsertGeom(block: "OUT", position: .zero))))
        let byl = d.add(Entity(layer: "A", geometry: .insert(InsertGeom(block: "OUT", position: Vec2(0, 500)))))
        let s1 = strokes(d, red)
        XCTAssertEqual(s1.count, 1)
        XCTAssertEqual(s1[0].style.color, aciColor(1)); XCTAssertEqual(s1[0].style.lineweight, 0.5)
        XCTAssertEqual(s1[0].style.dash, d.linetype("Hidden")!.pattern)
        let s2 = strokes(d, byl)
        XCTAssertEqual(s2[0].style.color, RGBA(0, 1, 0)); XCTAssertEqual(s2[0].style.lineweight, 0.7)
        XCTAssertEqual(s2[0].style.dash, d.linetype("Dashed")!.pattern)
        // Survives DXF.
        let rt = try roundTrip(d)
        let rid = rt.entities.first { if case .insert(let i) = $0.geometry { return i.position == .zero }; return false }!.id
        let r1 = strokes(rt, rid)
        XCTAssertEqual(r1.first?.style.color, aciColor(1))
        // ByBlock lineweight (370 = -2) and linetype survive the round trip.
        XCTAssertEqual(rt.blocks["IN"]?.entities.first?.lineweight, -2)
        XCTAssertEqual(rt.blocks["IN"]?.entities.first?.linetype, "ByBlock")
        XCTAssertEqual(r1.first?.style.lineweight, 0.5)
        XCTAssertEqual(r1.first?.style.dash, rt.linetype("Hidden")?.pattern)
    }

    func testTextStyleRoundTrip() async throws {
        var d = ArchiDocument()
        d.textStyles.append(TextStyle(name: "Narrow", font: "Helvetica", height: 3.5, widthFactor: 0.8, oblique: 15 * .pi / 180))
        let rt = try roundTrip(d)
        let s = rt.textStyles.first { $0.name == "Narrow" }
        XCTAssertEqual(s?.widthFactor ?? 0, 0.8, accuracy: 1e-9); XCTAssertEqual(s?.oblique ?? 0, 15 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(s?.height ?? 0, 3.5, accuracy: 1e-9)
    }

    func items(_ doc: ArchiDocument, _ id: EntityID) -> [DrawItem] {
        DrawListBuilder.entries(doc: doc, options: DrawOptions()).filter { $0.id == id }.flatMap(\.items)
    }

    func testStrokeFontStylesRenderWithWidthAndOblique() async throws {
        let ed = Editor()
        await ed.run("STYLE Plot simplex 0 0.5 20")
        guard let st = ed.doc.textStyles.first(where: { $0.name == "Plot" }) else { return XCTFail("no style") }
        XCTAssertEqual(st.oblique, 20 * .pi / 180, accuracy: 1e-12, "oblique stored in radians")
        XCTAssertEqual(st.widthFactor, 0.5)
        let id = ed.doc.add(.text(TextGeom(position: .zero, height: 9, content: "H", style: "Plot")))
        let its = items(ed.doc, id)
        XCTAssertFalse(its.contains { if case .text = $0 { return true }; return false }, "stroke fonts are drawn as vectors")
        let pts = its.flatMap { i -> [Vec2] in if case .stroke(let p, _, _) = i { return p }; return [] }
        XCTAssertFalse(pts.isEmpty)
        // H is 6 units wide at width factor 0.5 → 3; the top is sheared right by 9·tan 20°.
        let top = pts.filter { abs($0.y - 9) < 1e-9 }.map(\.x)
        XCTAssertEqual(top.min() ?? 0, 9 * tan(20 * .pi / 180), accuracy: 1e-9)
        XCTAssertEqual((top.max() ?? 0) - (top.min() ?? 0), 3, accuracy: 1e-9)
        // TrueType styles stay text; the bundled stroke font name works too.
        await ed.run("STYLE Body Helvetica 0 1 0")
        let t2 = ed.doc.add(.text(TextGeom(position: .zero, height: 5, content: "A", style: "Body")))
        XCTAssertTrue(items(ed.doc, t2).contains { if case .text = $0 { return true }; return false })
        XCTAssertTrue(TextStyleFonts.isStrokeFont("Archi Stroke")); XCTAssertTrue(TextStyleFonts.isStrokeFont("romans.shx"))
        // Legacy styles saved in degrees read back as radians.
        XCTAssertEqual(TextStyleFonts.obliqueRadians(TextStyle(name: "Old", oblique: 15)), 15 * .pi / 180, accuracy: 1e-12)
        // DXF round-trip keeps the SHX file, so the text is still drawn with strokes.
        ed.doc.textStyles[ed.doc.textStyles.firstIndex { $0.name == "Plot" }!].font = "simplex.shx"
        let rt = try roundTrip(ed.doc)
        let rs = rt.textStyles.first { $0.name == "Plot" }!
        XCTAssertTrue(TextStyleFonts.usesStrokes(rs, doc: rt))
        XCTAssertEqual(TextStyleFonts.obliqueRadians(rs), 20 * .pi / 180, accuracy: 1e-9)
        let rid = rt.entities.first { if case .text(let t) = $0.geometry { return t.style == "Plot" }; return false }!.id
        let rpts = items(rt, rid).flatMap { i -> [Vec2] in if case .stroke(let p, _, _) = i { return p }; return [] }
        XCTAssertEqual(rpts.count, pts.count)
        for (a, b) in zip(rpts, pts) { XCTAssertEqual(a.distance(to: b), 0, accuracy: 1e-6) }
    }

    func testDimensionStyleUnitsToleranceAlternateFit() async {
        let ed = Editor()
        await ed.run("DIMSTYLE N ARCH U A D 4 X")
        XCTAssertEqual(ed.doc.currentDimStyle, "ARCH")
        XCTAssertEqual(DimStyleExtras.get("ARCH", doc: ed.doc).units, .architectural)
        // 1676.4 mm = 66 in = 5'-6"; 1689.1 mm = 5'-6 1/2".
        let d = DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(1689.1, 0), Vec2(0, 500)], style: "ARCH")
        XCTAssertEqual(DimStyleExtras.text(d, props: [:], doc: ed.doc), "5'-6 1/2\"")
        var x = DimStyleExtras.get("ARCH", doc: ed.doc)
        x.units = .decimal; x.suppressTrailingZeros = true
        XCTAssertEqual(x.format(12.500, decimals: 3, unitMM: 1), "12.5")
        x.units = .fractional
        XCTAssertEqual(x.format(25.4 * 2.75, decimals: 3, unitMM: 1), "2 3/4")
        x.units = .engineering; x.suppressTrailingZeros = false
        XCTAssertEqual(x.format(25.4 * 30.25, decimals: 2, unitMM: 1), "2'-6.25\"")
        x.units = .decimal; x.roundOff = 5
        XCTAssertEqual(x.format(1232, decimals: 0, unitMM: 1), "1230")
        // Tolerance and alternate units from the style; objects can override.
        let base = ed.doc.dimStyles[0].name
        await ed.run("DIMSTYLE S \(base)")
        await ed.run("DIMSTYLE N TOL TO S 0.5 AL Y 0.1 1 . X")
        XCTAssertEqual(DimStyleExtras.get("TOL", doc: ed.doc).units, .decimal, "new styles start from the current style")
        let d2 = DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(0, 500)], style: "TOL")
        XCTAssertEqual(DimStyleExtras.text(d2, props: [:], doc: ed.doc), "1000±0.5 [100.0]")
        XCTAssertEqual(DimStyleExtras.text(d2, props: [DimExtras.toleranceProp: "sym:2"], doc: ed.doc), "1000±2.0 [100.0]")
        // The displayed text follows the style after a style edit (associative update through the renderer).
        let id = ed.doc.add(.dimension(d2))
        func shownText() -> String? { items(ed.doc, id).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }.first }
        XCTAssertEqual(shownText(), "1000±0.5 [100.0]")
        await ed.run("DIMSTYLE E TO N AL N X")
        XCTAssertEqual(shownText(), "1000")
        // Fit: a 10-unit dimension with 2.5 text moves the text outside (fit = text), beyond the second extension line.
        await ed.run("DIMSTYLE E F T X")
        let small = ed.doc.add(.dimension(DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(10, 0), Vec2(0, 20)], style: "TOL")))
        guard let tt = items(ed.doc, small).compactMap({ i -> TextGeom? in if case .text(let t, _, _) = i { return t }; return nil }).first else { return XCTFail("no text") }
        XCTAssertGreaterThan(tt.position.x, 10)
        // Centred text breaks the dimension line.
        await ed.run("DIMSTYLE E F B PL C X")
        let wide = ed.doc.add(.dimension(DimensionGeom(kind: .aligned, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(0, 20)], style: "TOL")))
        let dimLines = items(ed.doc, wide).compactMap { i -> [Vec2]? in if case .stroke(let p, _, _) = i, p.allSatisfy({ abs($0.y - 20) < 1e-9 }) { return p }; return nil }
        XCTAssertEqual(dimLines.count, 2)
        guard let ct = items(ed.doc, wide).compactMap({ i -> TextGeom? in if case .text(let t, _, _) = i { return t }; return nil }).first else { return XCTFail() }
        XCTAssertEqual(ct.position.y, 20, accuracy: 1e-9); XCTAssertEqual(ct.valign, .middle)
        // Undo restores the style settings (one step per command).
        ed.undo()
        XCTAssertFalse(DimStyleExtras.get("TOL", doc: ed.doc).textCentered)
    }

    func testTableLinkedToSpreadsheet() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-xlsx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let book = dir.appendingPathComponent("rooms.xlsx")
        try XLSX.write([XLSX.Sheet(name: "Notes", rows: [["x"]]), XLSX.Sheet(name: "Rooms", rows: [["Room", "Area"], ["Kitchen", "12.5"], ["Bath", "6"]])]).write(to: book)
        let ed = Editor()
        await ed.run("TABLELINK \(book.path)!Rooms 0,0")
        guard let e = ed.doc.entities.last, case .table(let t) = e.geometry else { return XCTFail("no table") }
        XCTAssertEqual(t.cells, [["Room", "Area"], ["Kitchen", "12.5"], ["Bath", "6"]])
        XCTAssertEqual(e.props[TableDataLink.sheetProp], "Rooms")
        // The spreadsheet changes: update pulls the new cells.
        try XLSX.write([XLSX.Sheet(name: "Notes", rows: [["x"]]), XLSX.Sheet(name: "Rooms", rows: [["Room", "Area"], ["Kitchen", "14"]])]).write(to: book)
        await ed.run("DATALINKUPDATE U All")
        guard case .table(let t2)? = ed.doc.entity(e.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(t2.cells, [["Room", "Area"], ["Kitchen", "14"]])
        // Edits write back into the linked sheet only.
        var tt = t2; tt.cells[1][1] = "15"
        ed.doc.entities[ed.doc.entityIndex(e.id)!].geometry = .table(tt)
        await ed.run("DATALINKUPDATE W All")
        let sheets = try XLSX.read(Data(contentsOf: book))
        XCTAssertEqual(sheets.first { $0.name == "Rooms" }?.rows[1][1], "15")
        XCTAssertEqual(sheets.first { $0.name == "Notes" }?.rows, [["x"]])
        // Export to CSV.
        let csv = dir.appendingPathComponent("rooms.csv")
        await ed.run("TABLEEXPORT #\(e.id) \(csv.path)")
        XCTAssertEqual(TableDataLink.parseCSV(try String(contentsOf: csv, encoding: .utf8)), [["Room", "Area"], ["Kitchen", "15"]])
    }
}
