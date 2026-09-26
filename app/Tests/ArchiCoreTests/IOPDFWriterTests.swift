// Oanarina Archi Tool — GPL-3.0-or-later
// Headless PDF plotting (PDFWriter): true-scale sheets and plans measured back with the PDF reader.
import XCTest
@testable import ArchiCore

final class IOPDFWriterTests: XCTestCase {
    func lines(_ ents: [Entity]) -> [(Vec2, Vec2)] {
        ents.flatMap { e -> [(Vec2, Vec2)] in
            switch e.geometry {
            case .line(let l): return [(l.a, l.b)]
            case .polyline(let p): return zip(p.vertices, p.vertices.dropFirst()).map { ($0.p, $1.p) }
            default: return []
            }
        }
    }
    func texts(_ ents: [Entity]) -> [String] { ents.compactMap { if case .text(let t) = $0.geometry { return t.content }; return nil } }

    func testSheetPlotsAtTrueScale() throws {
        var d = ArchiDocument()
        d.info.name = "Scale test"
        _ = d.add(.line(LineGeom(Vec2(0, 0), Vec2(5000, 0))))          // 5 m
        _ = d.add(.text(TextGeom(position: Vec2(0, 500), height: 250, content: "North façade")))
        d.layouts = [Layout(name: "A-101", paper: PaperSize.standard[1],
                            viewports: [Viewport(origin: Vec2(20, 20), size: Vec2(300, 200), viewCenter: Vec2(2500, 0), scale: 100, title: "Plan")])]
        let data = PDFWriter.document(d)
        XCTAssertTrue(data.starts(with: Array("%PDF-1.4".utf8)))
        let pdf = try PDFFile(data)
        XCTAssertEqual(pdf.pages.count, 1)
        let ents = try PDFImport.entities(pdf, page: 1)      // millimetres on paper
        // 5000 mm at 1:100 = 50 mm on paper.
        let horizontal = lines(ents).filter { abs($0.0.y - $0.1.y) < 1e-3 }.map { abs($0.1.x - $0.0.x) }
        XCTAssertTrue(horizontal.contains { abs($0 - 50) < 0.01 }, "\(horizontal)")
        // Its centre lands on the viewport centre (20 + 150, 20 + 100).
        let l = try XCTUnwrap(lines(ents).first { abs(abs($0.1.x - $0.0.x) - 50) < 0.01 })
        XCTAssertEqual((l.0.x + l.1.x) / 2, 170, accuracy: 0.01)
        XCTAssertEqual(l.0.y, 120, accuracy: 0.01)
        let t = texts(ents)
        XCTAssertTrue(t.contains { $0.contains("North fa") }, "\(t)")
        XCTAssertTrue(t.contains { $0.contains("1:100") })
        XCTAssertTrue(t.contains { $0.contains("A-101") }, "title block")
    }

    func testPlanFitsAStandardScaleAndDocumentIOWritesPDF() throws {
        var d = ArchiDocument()
        _ = d.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(20_000, 0), Vec2(20_000, 10_000), Vec2(0, 10_000)], closed: true)))
        let page = PDFWriter.planPage(d)
        XCTAssertEqual(page.width, 420); XCTAssertEqual(page.height, 297)
        let pdf = try PDFFile(PDFWriter.write([page]))
        let ents = try PDFImport.entities(pdf, page: 1)
        // A3 usable 400 × 269 mm → 1:50 → 400 mm × 200 mm.
        let lens = lines(ents).map { $0.0.distance(to: $0.1) }
        XCTAssertTrue(lens.contains { abs($0 - 400) < 0.01 }, "\(lens)")
        XCTAssertTrue(lens.contains { abs($0 - 200) < 0.01 })
        XCTAssertTrue(texts(ents).contains { $0.contains("1:50") })
        // Headless export through DocumentIO (archi-cli --out, batch jobs, MCP export).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plot-\(UUID().uuidString).pdf")
        try DocumentIO.write(d, to: url)
        XCTAssertNoThrow(try PDFFile(Data(contentsOf: url)))
        // Escaping and widths.
        XCTAssertEqual(PDFWriter.literal("a(b)\\c"), "(a\\(b\\)\\\\c)")
        XCTAssertEqual(PDFWriter.literal("é€"), "(\\351\\200)")
        XCTAssertEqual(PDFWriter.textWidth("AB"), 1.334, accuracy: 1e-9)
    }

    func testCopySelectionAsPDF() throws {
        var d = ArchiDocument()
        let a = d.add(.line(LineGeom(Vec2(0, 0), Vec2(200, 0))))
        _ = d.add(.circle(CircleGeom(Vec2(5000, 5000), 100)))
        let data = try XCTUnwrap(PDFWriter.objects(d, ids: [a]))
        let pdf = try PDFFile(data)
        let ents = try PDFImport.entities(pdf, page: 1)
        XCTAssertEqual(ents.count, 1, "only the selection is drawn")
        let l = try XCTUnwrap(lines(ents).first)
        XCTAssertEqual(l.0.distance(to: l.1), 200, accuracy: 0.01, "1:1")
        XCTAssertEqual(min(l.0.x, l.1.x), 5, accuracy: 0.01, "5 mm margin")
        XCTAssertNil(PDFWriter.objects(d, ids: [999]))
        let big = try XCTUnwrap(PDFWriter.objects(d, ids: [a], scale: 50))
        let l2 = try XCTUnwrap(lines(try PDFImport.entities(try PDFFile(big), page: 1)).first)
        XCTAssertEqual(l2.0.distance(to: l2.1), 4, accuracy: 0.01, "1:50")
    }
}
