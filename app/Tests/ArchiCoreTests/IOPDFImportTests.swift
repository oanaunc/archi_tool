// Oanarina Archi Tool — GPL-3.0-or-later
// PDF vector import (IO-014) and PDF markup import (COL-008).
import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
import CoreText
#endif
@testable import ArchiCore

final class IOPDFImportTests: XCTestCase {
    static func zlib(_ d: Data) throws -> Data {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in d { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        return Data([0x78, 0x9C]) + (RawDeflate.compress(d)) + Data([UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
    }

    static func samplePDF() throws -> Data {
        let content = """
        /OC /MC0 BDC
        1 0 0 RG 2 w
        10 10 m 100 10 l S
        EMC
        0 0 1 rg
        50 50 20 30 re f
        q 2 0 0 2 0 0 cm 0 0 m 10 0 l 10 10 l h S Q
        0 0 0 rg BT /F1 12 Tf 100 200 Td (Hello) Tj ET
        BT /F2 10 Tf 1 0 0 1 300 400 Tm <00010002> Tj ET
        /X1 Do
        """
        let packed = try zlib(Data(content.utf8))
        let form = "0 0 m 50 0 l S"
        let cmap = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap 2 beginbfchar <0001> <0057> <0002> <00E4> endbfchar endcmap end end"
        var out = Data("%PDF-1.7\n%\u{E2}\u{E3}\n".utf8)
        func obj(_ n: Int, _ body: Data) { out += Data("\(n) 0 obj\n".utf8) + body + Data("\nendobj\n".utf8) }
        func obj(_ n: Int, _ s: String) { obj(n, Data(s.utf8)) }
        obj(1, "<< /Type /Catalog /Pages 2 0 R >>")
        obj(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 595 842] >>")
        obj(3, "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R /F2 10 0 R >> /XObject << /X1 6 0 R >> /Properties << /MC0 7 0 R >> >> /Contents 4 0 R /Annots [8 0 R 9 0 R 12 0 R] >>")
        obj(4, Data("<< /Length \(packed.count) /Filter /FlateDecode >>\nstream\n".utf8) + packed + Data("\nendstream".utf8))
        obj(5, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        obj(6, "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 200 300] /Length \(form.utf8.count) >>\nstream\n\(form)\nendstream")
        obj(7, "<< /Type /OCG /Name (Walls) >>")
        obj(8, "<< /Type /Annot /Subtype /Square /Rect [72 72 144 144] /Contents (Check this wall) /T (Ana) /M (D:20260315103000Z) >>")
        obj(9, "<< /Type /Annot /Subtype /Ink /Rect [80 80 120 100] /InkList [[80 80 100 100 120 80]] /Contents (sketch) /T <FEFF0042006F> >>")
        obj(10, "<< /Type /Font /Subtype /Type0 /BaseFont /ABC /ToUnicode 11 0 R >>")
        obj(11, "<< /Length \(cmap.utf8.count) >>\nstream\n\(cmap)\nendstream")
        obj(12, "<< /Type /Annot /Subtype /Popup /Rect [0 0 1 1] >>")
        out += Data("trailer\n<< /Root 1 0 R >>\n%%EOF\n".utf8)
        return out
    }

    func testVectorsTextLayersAndForms() throws {
        let pdf = try PDFFile(Self.samplePDF())
        XCTAssertEqual(pdf.pages.count, 1)
        XCTAssertEqual(pdf.pages[0].mediaBox.max, Vec2(595, 842))
        let k = 25.4 / 72
        let ents = try PDFImport.entities(pdf, page: 1)
        let walls = ents.filter { $0.layer == "WALLS" }
        XCTAssertEqual(walls.count, 1, "optional content group → layer")
        guard case .line(let l) = walls[0].geometry else { return XCTFail() }
        XCTAssertEqual(l.a.x, 10 * k, accuracy: 1e-9); XCTAssertEqual(l.b.x, 100 * k, accuracy: 1e-9)
        XCTAssertEqual(walls[0].color, .rgb(255, 0, 0))
        XCTAssertEqual(walls[0].lineweight ?? 0, 2 * k, accuracy: 1e-9)
        XCTAssertEqual(ents.filter { $0.typeName == "hatch" }.count, 1, "filled rectangle → solid hatch")
        // The cm-scaled triangle is closed and twice the size.
        let tri = ents.first { if case .polyline(let p) = $0.geometry { return p.closed && p.vertices.count == 3 }; return false }
        guard case .polyline(let p)? = tri?.geometry else { return XCTFail("no triangle") }
        XCTAssertEqual(p.vertices[1].p.x, 20 * k, accuracy: 1e-9)
        let texts = ents.compactMap { e -> (String, Vec2)? in if case .text(let t) = e.geometry { return (t.content, t.position) }; return nil }
        XCTAssertEqual(texts.map(\.0), ["Hello", "Wä"], "Type0 text through ToUnicode")
        XCTAssertEqual(texts[0].1.x, 100 * k, accuracy: 1e-9)
        // Form XObject at its matrix.
        XCTAssertTrue(ents.contains { if case .line(let l) = $0.geometry { return abs(l.a.x - 200 * k) < 1e-9 && abs(l.a.y - 300 * k) < 1e-9 }; return false })
    }

    func testAnnotationsBecomeLinkedMarkups() throws {
        let pdf = try PDFFile(Self.samplePDF())
        let ann = PDFImport.annotations(pdf, page: 1)
        XCTAssertEqual(ann.map(\.subtype), ["Square", "Ink"], "popups are skipped")
        XCTAssertEqual(ann[1].author, "Bo", "UTF-16 text strings")
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: Vec2(2000, 4000), end: Vec2(6000, 4000))), level: 0)
        d.addElement(.wall(WallGeom(start: Vec2(50_000, 0), end: Vec2(60_000, 0))), level: 0)
        var o = PDFImportOptions(); o.unitsPerPoint = 25.4 / 72 * 100   // plotted at 1:100 in mm
        let ids = PDFImport.importMarkups(pdf, page: 1, into: &d, options: o)
        XCTAssertEqual(ids.count, 2)
        let m = Markups.list(d)
        let square = try XCTUnwrap(m.first { $0.comment == "Check this wall" })
        XCTAssertEqual(square.author, "Ana")
        XCTAssertEqual(square.date, "2026-03-15T10:30:00Z")
        XCTAssertEqual(square.elements, [w], "linked to the wall under the cloud only")
        XCTAssertEqual(square.viewCenter.x, 108 * 25.4 / 72 * 100, accuracy: 1e-6)
        XCTAssertEqual(d.entities.filter { $0.props["markupSketch"] != nil }.count, 1, "ink kept as a sketch")
    }

    @MainActor func testCommandsAndFileImport() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).pdf")
        try Self.samplePDF().write(to: url)
        let ed = Editor()
        await ed.run("PDFIMPORT \(url.path) 1 100 0,0")
        XCTAssertGreaterThan(ed.doc.entities.count, 5)
        XCTAssertNotNil(ed.doc.layer(named: "WALLS"))
        ed.undo()
        XCTAssertTrue(ed.doc.entities.isEmpty)
        await ed.run("PDFMARKUPS \(url.path) 1 100 0,0")
        XCTAssertEqual(Markups.list(ed.doc).count, 2)
        XCTAssertGreaterThan(try FileImport.load(url).0.entities.count, 5)
        XCTAssertThrowsError(try PDFFile(Data("hello".utf8)))
    }

    #if canImport(CoreGraphics)
    /// A PDF written by Quartz (Core Graphics) — the macOS PDF writer — reads back with the same geometry and text.
    func testQuartzWrittenPDF() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 420, height: 297)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw XCTSkip("no CoreGraphics PDF context") }
        ctx.beginPDFPage(nil)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 20, y: 20)); ctx.addLine(to: CGPoint(x: 400, y: 20)); ctx.addLine(to: CGPoint(x: 400, y: 280)); ctx.strokePath()
        ctx.addEllipse(in: CGRect(x: 100, y: 100, width: 50, height: 50)); ctx.strokePath()
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Plan A-101", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        ctx.textPosition = CGPoint(x: 30, y: 250)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        let pdf = try PDFFile(data as Data)
        XCTAssertEqual(pdf.pages.count, 1)
        XCTAssertEqual(pdf.pages[0].mediaBox.max, Vec2(420, 297))
        let ents = try PDFImport.entities(pdf, page: 1)
        let k = 25.4 / 72
        let poly = ents.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry, !p.closed, p.vertices.count == 3 { return p }; return nil }
        XCTAssertEqual(poly.count, 1)
        XCTAssertEqual(poly.first?.vertices[1].p.x ?? 0, 400 * k, accuracy: 1e-6)
        XCTAssertEqual(poly.first?.vertices[2].p.y ?? 0, 280 * k, accuracy: 1e-6)
        // The circle (4 Béziers) closes on itself with points on radius 25 pt.
        let circle = ents.compactMap { e -> PolylineGeom? in if case .polyline(let p) = e.geometry, p.vertices.count > 12 { return p }; return nil }.first
        let c = Vec2(125, 125) * k
        XCTAssertTrue(circle?.vertices.allSatisfy { abs($0.p.distance(to: c) - 25 * k) < 0.05 } ?? false)
        let text = ents.compactMap { e -> String? in if case .text(let t) = e.geometry { return t.content }; return nil }.joined()
        XCTAssertTrue(text.replacingOccurrences(of: " ", with: "").contains("PlanA-101"), text)
    }
    #endif
}
