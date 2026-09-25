// Oanarina Archi Tool — GPL-3.0-or-later
// Read-only viewer export (COL-014).
import XCTest
@testable import ArchiCore

final class IOViewerExportTests: XCTestCase {
    func testSelfContainedViewer() throws {
        var d = ArchiDocument()
        d.info.name = "Viewer <House>"
        let w = d.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))), level: 0)
        d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 1000, width: 900, height: 2100)), level: 0)
        d.addElement(.space(SpaceGeom(boundary: [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 4000), Vec2(0, 4000)], name: "Living", number: "101")), level: 0)
        d.addElement(.wall(WallGeom(start: .zero, end: Vec2(0, 4000))), level: 1)
        let html = ViewerExport.html(d)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>Viewer &lt;House&gt; — viewer</title>"))
        XCTAssertEqual(html.components(separatedBy: "<section class=\"level").count - 1, d.levels.count)
        XCTAssertEqual(html.components(separatedBy: "class=\"plan\"").count - 1, d.levels.count)
        XCTAssertFalse(html.contains("<?xml"), "SVGs are inlined")
        XCTAssertFalse(html.contains("http://") && html.contains("src=\"http"), "no external resources")
        XCTAssertFalse(html.contains("<script src"))
        // Element data: every element with plan bounds, with its info.
        let start = try XCTUnwrap(html.range(of: "const ELEMENTS = ")), end = try XCTUnwrap(html.range(of: ";\n", range: start.upperBound..<html.endIndex))
        let json = try JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)) as? [[String: Any]]
        let ids = Set(json?.compactMap { $0["id"] as? Int } ?? [])
        XCTAssertTrue(ids.contains(w))
        let room = json?.first { ($0["info"] as? [String: String])?["type"] == "space" }?["info"] as? [String: String]
        XCTAssertEqual(room?["area"], "20 m²")
        XCTAssertTrue(html.contains("<td>101</td><td>Living</td>"))
        // A copy for manual / script checks of the page (build/ is git-ignored).
        let buildDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../build", isDirectory: true).standardizedFileURL
        try? html.write(to: buildDir.appendingPathComponent("viewer-sample.html"), atomically: true, encoding: .utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(UUID().uuidString).html")
        try DocumentIO.write(d, to: url)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("ELEMENTS"))
    }
}
