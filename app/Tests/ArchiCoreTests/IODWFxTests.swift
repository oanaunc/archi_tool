// Oanarina Archi Tool — GPL-3.0-or-later
// DWFx import (IO-012).
import XCTest
@testable import ArchiCore

final class IODWFxTests: XCTestCase {
    static func sample() -> Data {
        let page1 = """
        <FixedPage Width="960" Height="480" xmlns="http://schemas.microsoft.com/xps/2005/06" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xml:lang="en">
          <Canvas.Resources><ResourceDictionary><PathGeometry x:Key="G1" Figures="M 0,0 L 48,0"/></ResourceDictionary></Canvas.Resources>
          <Canvas RenderTransform="1,0,0,1,96,0">
            <Path Data="F1 M 0,0 L 96,0 L 96,96 Z" Stroke="#FFFF0000" StrokeThickness="2"/>
            <Path Stroke="#FF0000FF"><Path.Data><PathGeometry><PathFigure StartPoint="0,192" IsClosed="false"><PolyLineSegment Points="192,192 192,288"/></PathFigure></PathGeometry></Path.Data></Path>
            <Canvas><Canvas.RenderTransform><MatrixTransform Matrix="2,0,0,2,0,0"/></Canvas.RenderTransform>
              <Path Data="{StaticResource G1}" Stroke="#FF00FF00"/>
            </Canvas>
            <Glyphs UnicodeString="ROOM 1" OriginX="10" OriginY="400" FontRenderingEmSize="20" Fill="#FF000000"/>
          </Canvas>
        </FixedPage>
        """
        let page2 = "<FixedPage Width=\"96\" Height=\"96\" xmlns=\"http://schemas.microsoft.com/xps/2005/06\"><Path Data=\"M 0,0 L 96,96\" Stroke=\"#FF000000\"/></FixedPage>"
        return ZipArchive.write([
            ZipArchive.Entry(name: "[Content_Types].xml", data: Data("<Types/>".utf8)),
            ZipArchive.Entry(name: "Documents/1/Pages/1.fpage", data: Data(page1.utf8)),
            ZipArchive.Entry(name: "Documents/1/Pages/2.fpage", data: Data(page2.utf8)),
        ], compress: true)
    }

    func testPathsTextTransformsAndPages() throws {
        let ents = try DWFxImporter.entities(Self.sample())
        let k = 25.4 / 96
        let sheet1 = ents.filter { $0.layer.hasPrefix("DWF-SHEET1") }
        guard case .polyline(let tri)? = sheet1.first(where: { $0.color == .rgb(255, 0, 0) })?.geometry else { return XCTFail("no red triangle") }
        XCTAssertTrue(tri.closed)
        XCTAssertEqual(tri.vertices[0].p.x, 96 * k, accuracy: 1e-9)
        XCTAssertEqual(tri.vertices[0].p.y, 480 * k, accuracy: 1e-9, "y flipped from the page top")
        XCTAssertEqual(tri.vertices[2].p.y, (480 - 96) * k, accuracy: 1e-9)
        XCTAssertEqual(sheet1.first { $0.color == .rgb(255, 0, 0) }?.lineweight ?? 0, 2 * k, accuracy: 1e-9)
        guard case .polyline(let blue)? = sheet1.first(where: { $0.color == .rgb(0, 0, 255) })?.geometry else { return XCTFail("no figure path") }
        XCTAssertEqual(blue.vertices.count, 3)
        guard case .line(let green)? = sheet1.first(where: { $0.color == .rgb(0, 255, 0) })?.geometry else { return XCTFail("no resource path") }
        XCTAssertEqual(green.b.x - green.a.x, 96 * k, accuracy: 1e-9, "48 units scaled ×2")
        let text = sheet1.compactMap { e -> TextGeom? in if case .text(let t) = e.geometry { return t }; return nil }.first
        XCTAssertEqual(text?.content, "ROOM 1")
        XCTAssertEqual(text?.position.x ?? 0, 106 * k, accuracy: 1e-9)
        // Sheet 2 lies to the right of sheet 1.
        let s2 = ents.filter { $0.layer == "DWF-SHEET2" }
        XCTAssertEqual(s2.count, 1)
        XCTAssertGreaterThan(GeometryOps.bounds(s2[0].geometry, doc: nil).min.x, 960 * k)
        XCTAssertThrowsError(try DWFxImporter.entities(Data("(DWF V06.00)".utf8)))
    }

    @MainActor func testCommand() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).dwfx")
        try Self.sample().write(to: url)
        let ed = Editor()
        await ed.run("DWFIMPORT \(url.path)")
        XCTAssertGreaterThan(ed.doc.entities.count, 4)
    }
}
