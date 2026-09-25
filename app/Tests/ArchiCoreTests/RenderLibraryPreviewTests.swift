// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Draws every library family in plan and in a shaded elevation; writes SVG previews to build/previews when that folder exists.
final class RenderLibraryPreviewTests: XCTestCase {
    func libraryDoc() -> ArchiDocument {
        var doc = ArchiDocument()
        ComponentLibrary.ensureMaterials(&doc)
        var x = 0.0
        for f in ComponentLibrary.families {
            _ = doc.addElement(.component(ComponentGeom(category: f.category, position: Vec2(x + f.size.x / 2, 0), size: f.size, baseOffset: f.baseOffset, family: f.id)))
            x += f.size.x + 600
        }
        return doc
    }

    func testLibraryPreviews() throws {
        let doc = libraryDoc()
        let plan = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: 0))
        XCTAssertEqual(plan.count, ComponentLibrary.families.count)
        let south = ElevationBuilder.entries(doc: doc, view: .elevationSouth)
        XCTAssertFalse(south.isEmpty)
        var east = doc
        var y = 0.0
        for i in east.elements.indices { if case .component(var g) = east.elements[i].geometry { g.position = Vec2(0, y + g.size.y / 2); y += g.size.y + 600; east.elements[i].geometry = .component(g) } }
        let side = ElevationBuilder.entries(doc: east, view: .elevationEast)
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../build/previews").standardized
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        for (name, es) in [("library-plan", plan), ("library-south", south), ("library-east", side)] {
            var b = BBox2.empty
            for e in es { b.add(e.bounds) }
            let svg = SVGExporter.export(entries: es, bounds: b.expanded(by: 200), background: RGBA(1, 1, 1), pixelsPerUnit: 0.06)
            try svg.write(to: dir.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
        }
    }
}
