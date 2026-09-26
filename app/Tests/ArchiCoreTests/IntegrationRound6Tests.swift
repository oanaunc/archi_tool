// Oanarina Archi Tool — GPL-3.0-or-later
// Integration checks for APIs wired together across areas in round 6: the DXF MTEXT codec (stacked fractions and
// list paragraphs survive a DXF round trip, ANN-005/006).
import XCTest
@testable import ArchiCore

final class IntegrationRound6Tests: XCTestCase {
    func testDXFMTextKeepsStacksAndLists() throws {
        var d = ArchiDocument()
        let contents = ["Door \\S1/2; wide\nTolerance ±\\S+0.1^-0.05;", "1. Walls\n2. Doors", "a {brace} \\\\ back"]
        for (i, c) in contents.enumerated() {
            d.add(.text(TextGeom(position: Vec2(0, Double(i) * 500), height: 250, content: c, width: 4000)))
        }
        let dxf = DXFWriter.write(d)
        XCTAssertTrue(dxf.contains("\\S1/2;"), "stacks are written as \\S codes, not escaped")
        XCTAssertFalse(dxf.contains("\\\\S1/2"))
        let back = try DXFReader.read(dxf)
        let texts = back.entities.compactMap { e -> String? in if case .text(let t) = e.geometry { return t.content }; return nil }
        XCTAssertEqual(texts, contents)
    }

    func testDXFMTextColumnsUseACADXData() throws {
        var d = ArchiDocument()
        let id = d.add(.text(TextGeom(position: .zero, height: 10, content: String(repeating: "word ", count: 60), width: 420)))
        d.entities[d.entities.firstIndex { $0.id == id }!].props[DraftRendering.textColumnsProp] = "2,20,0"
        let dxf = DXFWriter.write(d)
        XCTAssertTrue(dxf.contains("ACAD_MTEXT_COLUMN_INFO_BEGIN"))
        // Without Archi's own XDATA (as written by another program) the columns come from the ACAD block.
        let foreign = dxf.replacingOccurrences(of: DXFXData.app, with: "OTHER_APP")
        let back = try DXFReader.read(foreign)
        guard let e = back.entities.first(where: { if case .text = $0.geometry { return true }; return false }) else { return XCTFail("no text") }
        XCTAssertEqual(e.props[DraftRendering.textColumnsProp], "2,20,0")
    }
}
