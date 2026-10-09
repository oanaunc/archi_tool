// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class SectionSheetStyleTests: XCTestCase {
    @MainActor func testCommandUndoPersistenceAndIsolation() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 5000,4000 0,4000 C")
        ed.doc.layouts[0].viewports = [Viewport(origin: Vec2(30, 70), size: Vec2(200, 150), viewCenter: Vec2(2500, 1500), scale: 50, view: .section)]
        let name = ed.doc.layouts[0].name
        ed.doc.layouts.append(Layout(name: "Other"))
        let before = ed.doc
        let log = await ed.run("SECSTYLE Set \"\(name)\" \"color:red;fill:0.2,0.4,0.6;cut:0.8;proj:0.3;shading:off\"")
        XCTAssertTrue(log.contains { $0.contains("saved") }, "\(log)")
        let style = try XCTUnwrap(SectionSheetStyle.load(ed.doc.layouts[0]))
        XCTAssertFalse(style.shaded)
        XCTAssertEqual(style.lines.cutLineweight, 0.8)
        let styled = ed.doc
        let decoded = try ArchiFile.decode(ArchiFile.encode(styled))
        XCTAssertEqual(SectionSheetStyle.load(decoded.layouts[0]), style)
        XCTAssertNil(SectionSheetStyle.load(decoded.layouts[1]))
        XCTAssertEqual(SectionSheetStyle.document(styled, layout: name, view: .plan), styled)
        XCTAssertEqual(SectionSheetStyle.document(styled, layout: "Other", view: .section), styled)
        XCTAssertNil(styled.variable(ObjectStyles.key))
        ed.undo(); XCTAssertEqual(ed.doc, before)
        ed.redo(); XCTAssertEqual(ed.doc, styled)
        await ed.run("SSTYLE Reset \"\(name)\"")
        XCTAssertNil(SectionSheetStyle.load(ed.doc.layouts[0]))
        ed.undo(); XCTAssertEqual(ed.doc, styled)
    }

    @MainActor func testSectionRenderingAndPDFUseSheetStyle() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 5000,0 5000,4000 0,4000 C")
        let name = ed.doc.layouts[0].name
        let vp = Viewport(origin: Vec2(30, 70), size: Vec2(200, 150), viewCenter: Vec2(2500, 1500), scale: 50, view: .section)
        ed.doc.layouts[0].viewports = [vp]
        let normal = EnginePlot.viewportEntries(doc: ed.doc, vp: vp, layout: name)
        let colour = RGBA(0.8, 0.1, 0.2), fill = RGBA(0.2, 0.4, 0.6)
        let style = SectionSheetStyle(lines: ObjectStyle(projectionLineweight: 0.3, cutLineweight: 0.8, color: colour, cutFill: fill), shaded: false)
        style.store(in: &ed.doc.layouts[0])
        let entries = EnginePlot.viewportEntries(doc: ed.doc, vp: vp, layout: name)
        let fills = entries.filter { $0.id != nil }.flatMap(\.items).compactMap { if case .fill(_, let c) = $0 { return c }; return nil }
        XCTAssertFalse(fills.isEmpty)
        XCTAssertTrue(fills.allSatisfy { $0 == fill }, "linework keeps cut fills and removes shaded faces")
        XCTAssertGreaterThan(normal.flatMap(\.items).filter { if case .fill = $0 { return true }; return false }.count, fills.count)
        let strokes = entries.flatMap(\.items).compactMap { if case .stroke(_, _, let st) = $0 { return st }; return nil }
        XCTAssertTrue(strokes.contains { $0.color == colour && $0.lineweight == 0.8 })
        XCTAssertTrue(strokes.contains { $0.color == colour && $0.lineweight == 0.3 })
        let page = try XCTUnwrap(EnginePlot.sheetPage(doc: ed.doc, layoutIndex: 0))
        let ops = EnginePDF.resolve(page, doc: ed.doc, layered: false).ops
        XCTAssertTrue(ops.contains { if case .fill(_, let c) = $0 { return c == fill }; return false })
        XCTAssertTrue(ops.contains { if case .stroke(_, _, let c, let w, _) = $0 { return c == colour && abs(w - 0.8 * EnginePlot.pointsPerMM) < 1e-6 }; return false })
    }

    func testMalformedStylesAndLegacyDefaults() {
        XCTAssertNil(SectionSheetStyle.load(Layout(name: "Legacy")))
        for spec in ["color:no-such-colour", "cut:-1", "proj:6", "shading:maybe", "unknown:1"] { XCTAssertNil(SectionSheetStyle.parse(spec), spec) }
    }
}
