// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// GDL-like scripted BIM objects (PAR-016).
@MainActor
final class BIMScriptedComponentTests: XCTestCase {
    let script = """
    // Width
    w = 1000; // [100:5000]
    d = 500;
    // Shelves
    n = 3; // [1:10]
    for (i = [0 : n - 1]) translate([0, 0, i * 400]) cube([w, d, 20]);
    """
    func volume(_ el: BIMElement, _ doc: ArchiDocument) -> Double { MeshBuilder.groups(for: el, doc: doc).map { MeshTools.signedVolume($0.mesh) }.reduce(0, +) }
    func bounds(_ el: BIMElement, _ doc: ArchiDocument) -> BBox3 { var b = BBox3.empty; for g in MeshBuilder.groups(for: el, doc: doc) { g.mesh.positions.forEach { b.add($0) } }; return b }

    func testPlaceFlexMoveAndPersist() async throws {
        let ed = Editor()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString).scad")
        try script.write(to: url, atomically: true, encoding: .utf8)
        await ed.run("SCRIPTCOMPONENT Place File \"\(url.path)\" 2000,0 0 Casework \"Shelf\"")
        guard let el = ed.doc.elements.last, el.props[ScriptedComponents.scriptKey] != nil, case .component(let g) = el.geometry else { return XCTFail("not placed") }
        XCTAssertEqual(g.category, "Casework"); XCTAssertEqual(el.name, "Shelf")
        XCTAssertEqual(volume(el, ed.doc), 3 * 1000 * 500 * 20, accuracy: 1)
        XCTAssertEqual(bounds(el, ed.doc).min.x, 2000, accuracy: 1e-6)
        XCTAssertEqual(ScriptedComponents.parameters(el).map(\.name), ["w", "d", "n"])
        // Flex: instance values regenerate the geometry.
        await ed.run("SCRIPTCOMPONENT Set #\(el.id) n 5")
        await ed.run("SCRIPTCOMPONENT Set #\(el.id) w 2000")
        let e2 = ed.doc.element(el.id)!
        XCTAssertEqual(e2.props["sp.n"], "5")
        XCTAssertEqual(volume(e2, ed.doc), 5 * 2000 * 500 * 20, accuracy: 1)
        // Out-of-range values are refused.
        await ed.run("SCRIPTCOMPONENT Set #\(el.id) w 99999")
        XCTAssertEqual(ed.doc.element(el.id)?.props["sp.w"], "2000")
        // Moving / rotating the instance keeps its parameters.
        if let i = ed.doc.elementIndex(el.id), case .component(var gg) = ed.doc.elements[i].geometry { gg.position = Vec2(5000, 1000); gg.rotation = .pi / 2; ed.doc.elements[i].geometry = .component(gg) }
        BIMUpdaters.run(&ed.doc)
        let e3 = ed.doc.element(el.id)!
        let b = bounds(e3, ed.doc)
        XCTAssertEqual(b.size.y, 2000, accuracy: 1e-6); XCTAssertEqual(b.size.x, 500, accuracy: 1e-6)
        XCTAssertEqual(volume(e3, ed.doc), 5 * 2000 * 500 * 20, accuracy: 1)
        let back = try JSONDecoder().decode(ArchiDocument.self, from: try JSONEncoder().encode(ed.doc))
        XCTAssertEqual(back.element(el.id)?.props["sp.w"], "2000")
        XCTAssertFalse(PlanRepresentation.items(e3, doc: ed.doc).isEmpty)
        try? FileManager.default.removeItem(at: url)
    }
}
