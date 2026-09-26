// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Wall-, floor- and ceiling-hosted components follow their hosts and schedule their host.
@MainActor
final class BIMHostedComponentsTests: XCTestCase {
    func comp(_ ed: Editor, _ id: EntityID) -> ComponentGeom? { if case .component(let g)? = ed.doc.element(id)?.geometry { return g }; return nil }

    func testWallFloorAndCeilingHosting() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let wall = ed.doc.elements[0].id
        await ed.run("COMPONENT Custom Casework 800 350 700 Host Wall 1400 2000,150 ")
        let cab = try XCTUnwrap(ed.doc.elements.last?.id)
        var g = try XCTUnwrap(comp(ed, cab))
        XCTAssertEqual(g.position.y, 100 + 175, accuracy: 1e-6, "back against the wall face")
        XCTAssertEqual(g.position.x, 2000, accuracy: 1e-6)
        XCTAssertEqual(g.baseOffset, 1400, accuracy: 1e-6)
        XCTAssertEqual(ed.doc.element(cab)?.props["hostKind"], "wall")
        // Rotate the wall 90° about its start: the cabinet follows and turns with it.
        ed.selection = [wall]
        await ed.run("ROTATE 0,0 90")
        g = try XCTUnwrap(comp(ed, cab))
        XCTAssertEqual(g.position.x, -275, accuracy: 1e-6); XCTAssertEqual(g.position.y, 2000, accuracy: 1e-6)
        XCTAssertEqual(normAngle(g.rotation), .pi / 2, accuracy: 1e-9)
        // Thicker wall: pushed out.
        ed.transaction("t") { doc in if case .wall(var w) = doc.elements[0].geometry { w.thickness = 400; doc.elements[0].geometry = .wall(w) } }
        XCTAssertEqual(comp(ed, cab)!.position.x, -375, accuracy: 1e-6)
        // Floor-hosted: sits on the slab top and follows its offset.
        await ed.run("SLAB 1000,1000 5000,1000 5000,4000 1000,4000 ")
        let slab = ed.doc.elements.last!.id
        await ed.run("COMPONENT Chair Host Floor 3000,2500 ")
        let chair = ed.doc.elements.last!.id
        ed.transaction("s") { doc in if case .slab(var s) = doc.elements[doc.elementIndex(slab)!].geometry { s.topOffset = 150; doc.elements[doc.elementIndex(slab)!].geometry = .slab(s) } }
        XCTAssertEqual(comp(ed, chair)!.baseOffset, 150, accuracy: 1e-6)
        // Ceiling-hosted light: hangs under the ceiling.
        await ed.run("CEILING Offset 2600 1000,1000 5000,1000 5000,4000 1000,4000 ")
        await ed.run("COMPONENT Custom Lighting 600 600 100 Host Ceiling 3000,2500 ")
        let light = ed.doc.elements.last!.id
        XCTAssertEqual(comp(ed, light)!.baseOffset + 100, 2600, accuracy: 1e-6)
        // Schedules show the host.
        var def = ScheduleDefinition(name: "C", category: "components")
        def.fields = [ScheduleField(name: "Category"), ScheduleField(name: "Host")]
        let t = Schedules.evaluate(def, doc: ed.doc)
        XCTAssertTrue(t.rows.contains { $0.cells[1] == "wall #\(wall)" })
        XCTAssertTrue(t.rows.contains { $0.cells[1].hasPrefix("ceiling #") })
    }
}
