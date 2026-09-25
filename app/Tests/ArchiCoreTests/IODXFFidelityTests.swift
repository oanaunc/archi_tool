// Oanarina Archi Tool — GPL-3.0-or-later
// DXF colour (ACI/true colour/transparency), text style fonts, MTEXT formatting, dimension styles and XDATA round trips.
import XCTest
@testable import ArchiCore

final class IODXFFidelityTests: XCTestCase {
    func testACIPaletteAndTransparencyCodes() {
        XCTAssertEqual(DXFColors.aci.count, 256)
        XCTAssertEqual(DXFColors.rgba(aci: 1), RGBA(1, 0, 0))
        XCTAssertEqual(DXFColors.aci[8], 0x808080)
        XCTAssertEqual(DXFColors.aci[30], 0xFF7F00)      // orange
        XCTAssertEqual(DXFColors.aci[250], 0x333333)
        for i in [1, 5, 7, 30, 94, 171, 250, 254] { XCTAssertEqual(DXFColors.nearest(DXFColors.rgba(aci: i)), i, "ACI \(i) maps to itself") }
        XCTAssertTrue(DXFColors.isExact(RGBA(1, 0, 0)))
        XCTAssertFalse(DXFColors.isExact(RGBA(0.1, 0.2, 0.3)))
        XCTAssertEqual(DXFColors.transparencyCode(percent: 0), 0x020000FF)
        XCTAssertEqual(DXFColors.transparencyCode(percent: 50), 0x02000080)
        XCTAssertEqual(DXFColors.transparencyPercent(code: 0x02000080), 50)
        XCTAssertEqual(DXFColors.transparencyPercent(code: 0x020000FF), 0)
        XCTAssertNil(DXFColors.transparencyPercent(code: 0))           // ByLayer
        XCTAssertNil(DXFColors.transparencyPercent(code: 0x01000000))  // ByBlock
    }

    func testColorsTransparencyAndXDataRoundTrip() throws {
        var d = ArchiDocument()
        d.layers.append(Layer(name: "Glass", color: RGBA(0.2, 0.4, 0.6), transparency: 0.4))
        d.layers.append(Layer(name: "Red", color: RGBA(1, 0, 0)))
        var e1 = Entity(layer: "Glass", color: .rgb(12, 34, 56), geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0))))
        e1.props = ["transparency": "30", "status": "approved", "note": "multi = sign; ü ok", "long": String(repeating: "abc\\", count: 120)]
        let id1 = d.add(e1)
        let id2 = d.add(Entity(layer: "Red", color: .aci(94), geometry: .circle(CircleGeom(Vec2(50, 50), 20)), props: ["xdata:OTHERAPP": "1000=hello\u{1E}1040=2.5\u{1E}1070=3"]))
        let text = DXFWriter.write(d)
        XCTAssertTrue(text.contains("AcCmTransparency"))
        XCTAssertTrue(text.contains("OANARINA_ARCHI"))
        let back = try DXFReader.read(text)
        let glass = try XCTUnwrap(back.layer(named: "Glass"))
        XCTAssertTrue(glass.color.isNear(RGBA(0.2, 0.4, 0.6)))
        XCTAssertEqual(glass.transparency, 0.4, accuracy: 0.005)
        XCTAssertEqual(back.layer(named: "Red")?.color, RGBA(1, 0, 0))
        let line = try XCTUnwrap(back.entities.first { if case .line = $0.geometry { return true }; return false })
        XCTAssertEqual(line.color, .rgb(12, 34, 56))
        XCTAssertEqual(line.props["transparency"], "30")
        XCTAssertEqual(line.props["status"], "approved")
        XCTAssertEqual(line.props["note"], "multi = sign; ü ok")
        XCTAssertEqual(line.props["long"], d.entity(id1)!.props["long"])
        let circle = try XCTUnwrap(back.entities.first { if case .circle = $0.geometry { return true }; return false })
        XCTAssertEqual(circle.color, .aci(94))
        XCTAssertEqual(circle.props["xdata:OTHERAPP"], d.entity(id2)!.props["xdata:OTHERAPP"])
        // Every XDATA application is registered in the APPID table.
        let appIDs = text.components(separatedBy: "\n  0\nAPPID\n").count - 1
        XCTAssertEqual(appIDs, 4, "ACAD, AcCmTransparency, OANARINA_ARCHI, OTHERAPP")
    }

    func testForeignXDataAndTransparencyAreRead() throws {
        let dxf = """
          0
        SECTION
          2
        ENTITIES
          0
        LINE
          5
        2A
          8
        0
         62
        3
        440
        33554585
          10
        0
         20
        0
         11
        10
         21
        0
        1001
        MYAPP
        1000
        tag
        1070
        7
          0
        ENDSEC
          0
        EOF
        """   // 440: 0x02000099 → alpha 153 = 40 %
        let d = try DXFReader.read(dxf)
        let e = try XCTUnwrap(d.entities.first)
        XCTAssertEqual(e.props["transparency"], "40")
        XCTAssertEqual(e.props["xdata:MYAPP"], "1000=tag\u{1E}1070=7")
        XCTAssertEqual(e.color, .aci(3))
    }

    func testTextStyleFontMapping() throws {
        XCTAssertEqual(DXFFonts.family(fromFile: "romans.shx"), "Helvetica")
        XCTAssertEqual(DXFFonts.family(fromFile: "times.ttf"), "Times New Roman")
        XCTAssertEqual(DXFFonts.family(fromFile: "unknownfont.shx"), "unknownfont")
        XCTAssertEqual(DXFFonts.family(fromFile: "arial.ttf", face: "Arial Black"), "Arial Black")
        XCTAssertEqual(DXFFonts.file(forFamily: "Times New Roman"), "times.ttf")
        XCTAssertEqual(DXFFonts.file(forFamily: "Helvetica"), "arial.ttf")
        XCTAssertEqual(DXFFonts.file(forFamily: "Futura"), "futura.ttf")
        var d = ArchiDocument()
        d.textStyles = [TextStyle(name: "Standard"), TextStyle(name: "Notes", font: "Times New Roman", height: 250, widthFactor: 0.9, oblique: 0.2),
                        TextStyle(name: "Heads", font: "Arial Bold", height: 350)]
        let back = try DXFReader.read(DXFWriter.write(d))
        let notes = try XCTUnwrap(back.textStyles.first { $0.name == "Notes" })
        XCTAssertEqual(notes.font, "Times New Roman"); XCTAssertEqual(notes.height, 250); XCTAssertEqual(notes.widthFactor, 0.9, accuracy: 1e-9)
        XCTAssertEqual(notes.oblique, 0.2, accuracy: 1e-9)
        XCTAssertEqual(back.textStyles.first { $0.name == "Heads" }?.font, "Arial Bold")
        // An SHX font keeps its file through a round trip.
        let shx = """
          0
        SECTION
          2
        TABLES
          0
        TABLE
          2
        STYLE
          0
        STYLE
          2
        Tech
         70
        0
         40
        0
         41
        1
          3
        romans.shx
          0
        ENDTAB
          0
        ENDSEC
          0
        EOF
        """
        let s1 = try DXFReader.read(shx)
        XCTAssertEqual(s1.textStyles.first { $0.name == "Tech" }?.font, "Helvetica")
        let again = DXFWriter.write(s1)
        XCTAssertTrue(again.contains("romans.shx"))
        XCTAssertEqual(try DXFReader.read(again).textStyles.first { $0.name == "Tech" }?.font, "Helvetica")
    }

    func testMTextFormattingRoundTrip() throws {
        let raw = "{\\fArial|b1|i0|c0|p34;\\C1;Title} \\H2x;big\\Pnext line"
        let f = MTextFormatting.leading(raw)
        XCTAssertTrue(f.hasFormatting)
        XCTAssertEqual(f.font, "Arial"); XCTAssertTrue(f.bold); XCTAssertFalse(f.italic)
        XCTAssertEqual(f.color, .aci(1))
        XCTAssertFalse(MTextFormatting.leading("plain\\Ptext").hasFormatting)
        XCTAssertEqual(MTextFormatting.leading("\\H3.5;\\W0.8;\\Q15;x").height, 3.5)
        XCTAssertEqual(MTextFormatting.leading("\\c255;red").color, .rgb(255, 0, 0))   // BGR
        let enc = MTextFormatting.encode("Hi {there}\nline", font: "Arial", bold: true, color: .aci(5))
        XCTAssertEqual(DXFReader.stripMText(enc), "Hi {there}\nline")
        let fe = MTextFormatting.leading(enc)
        XCTAssertTrue(fe.bold); XCTAssertEqual(fe.color, .aci(5))

        var d = ArchiDocument()
        let id = d.add(Entity(geometry: .text(TextGeom(position: Vec2(10, 20), height: 2.5, content: DXFReader.stripMText(raw), width: 80)), props: ["mtext": raw]))
        let out = DXFWriter.write(d)
        XCTAssertTrue(out.contains("\\fArial|b1"), "formatting codes are written back")
        let back = try DXFReader.read(out)
        let t = try XCTUnwrap(back.entities.first)
        XCTAssertEqual(t.props["mtext"], raw)
        XCTAssertEqual(t.props["bold"], "1"); XCTAssertEqual(t.props["font"], "Arial")
        if case .text(let tg) = t.geometry { XCTAssertEqual(tg.content, "Title big\nnext line") } else { XCTFail() }
        // Edited text drops the stale formatting.
        d.entities[d.entities.firstIndex { $0.id == id }!].geometry = .text(TextGeom(position: .zero, height: 2.5, content: "changed", width: 80))
        XCTAssertFalse(DXFWriter.write(d).contains("\\fArial|b1"))
    }

    func testDimensionStylesRoundTrip() throws {
        var d = ArchiDocument()
        d.dimStyles = [DimStyle(name: "Standard"),
                       DimStyle(name: "Arch", textHeight: 250, arrowSize: 150, arrow: .architecturalTick, extensionOffset: 100, extensionExtend: 150, textGap: 80, decimals: 0, prefix: "", suffix: " mm", linearScale: 1, scale: 1),
                       DimStyle(name: "Metric", textHeight: 3, arrowSize: 2, arrow: .open, extensionOffset: 0.6, extensionExtend: 1.5, textGap: 0.5, decimals: 2, prefix: "L=", suffix: "", linearScale: 0.001, scale: 50),
                       DimStyle(name: "Dots", arrow: .dot), DimStyle(name: "Oblique", arrow: .tick), DimStyle(name: "Bare", arrow: .none)]
        let back = try DXFReader.read(DXFWriter.write(d))
        for ds in d.dimStyles {
            let b = try XCTUnwrap(back.dimStyles.first { $0.name == ds.name }, ds.name)
            XCTAssertEqual(b, ds, ds.name)
        }
        // DIMBLK by name (R12 group 5) from other programs.
        XCTAssertEqual(DXFReader.arrow(blockName: "_ARCHTICK"), .architecturalTick)
        XCTAssertEqual(DXFReader.arrow(blockName: "_DOTSMALL"), .dot)
        XCTAssertEqual(DXFReader.arrow(blockName: "_Oblique"), .tick)
        XCTAssertNil(DXFReader.arrow(blockName: "MyArrow"))
    }
}
