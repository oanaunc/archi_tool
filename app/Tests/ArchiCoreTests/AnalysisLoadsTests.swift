// Oanarina Archi Tool — GPL-3.0-or-later
// Loads and boundary conditions (ANL-032): user loads/supports reach the analytical model, the frame solver balances
// them, and the OpenSees export carries the same model.
import XCTest
@testable import ArchiCore

final class AnalysisLoadsTests: XCTestCase {
    func frame() -> ArchiDocument {
        var d = ArchiDocument()
        for p in [Vec2(0, 0), Vec2(6000, 0), Vec2(6000, 4000), Vec2(0, 4000)] {
            d.addElement(.column(ColumnGeom(position: p, width: 300, depth: 300, height: 3000)), level: 0)
        }
        d.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(6000, 0), width: 250, depth: 400, topOffset: 3000)), level: 0)
        d.addElement(.beam(BeamGeom(start: Vec2(0, 4000), end: Vec2(6000, 4000), width: 250, depth: 400, topOffset: 3000)), level: 0)
        return d
    }

    @MainActor func testLoadsAndSupportsAttachAndBalance() async throws {
        let ed = Editor()
        ed.doc = frame()
        await ed.run("STRUCTLOAD P 3000,0 20 0 0 Q")         // mid-span of beam 1 → lever rule
        await ed.run("STRUCTLOAD P 6000,4000 10 2 0 G")      // on a column top node, with a horizontal component
        await ed.run("STRUCTLOAD L 0,0 6000,0 5 0 0 G")        // along beam 1
        await ed.run("STRUCTLOAD A 0,0 6000,0 6000,4000 0,4000 C 1.5 0 0 Q")
        await ed.run("STRUCTSUPPORT 0,0 Custom 111000")
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == StructuralLoads.layer }.count, 5)
        ed.undo()
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == StructuralLoads.layer }.count, 4, "undoable")
        await ed.run("STRUCTSUPPORT 0,0 P")

        var o = AnalyticalOptions(); o.deadLoad = 0; o.liveLoad = 0
        let m = StructuralAnalysis.model(ed.doc, options: o)
        XCTAssertTrue(m.warnings.isEmpty, m.warnings.joined(separator: "; "))
        XCTAssertEqual(m.members.count, 6)
        // Point load split 10/10 onto the beam ends; the other on its node.
        let point = m.nodeLoads.filter { $0.loadCase == "Q" && abs($0.force.z + 10) < 1e-9 }
        XCTAssertEqual(point.count, 2)
        XCTAssertTrue(m.nodeLoads.contains { abs($0.force.x - 2) < 1e-9 && abs($0.force.z + 10) < 1e-9 })
        // Area load 1.5 kN/m² × 24 m² = 36 kN over the four column tops.
        XCTAssertEqual(m.nodeLoads.filter { abs($0.force.z + 9) < 1e-9 }.count, 4)
        let beam1 = try XCTUnwrap(m.members.first { $0.kind == "beam" && m.nodes[$0.start - 1].p.y < 0.1 && m.nodes[$0.end - 1].p.y < 0.1 })
        let sw = beam1.material.weight * beam1.area
        XCTAssertEqual(m.memberLoads[beam1.id]?.z ?? 0, -sw - 5, accuracy: 1e-9)
        let total = StructuralLoads.totalLoad(m)
        XCTAssertEqual(total.x, 2, accuracy: 1e-9)
        // The solver accepts the model and the reactions balance the applied loads.
        let r = try StructuralAnalysis.solve(m)
        let reac = r.reactions.values.reduce(Vec3.zero) { $0 + $1.f }
        XCTAssertEqual(reac.z, -total.z, accuracy: 1e-6)
        XCTAssertEqual(reac.x, -total.x, accuracy: 1e-6)
        XCTAssertEqual(r.reactions.count, 4)
        // OpenSees input.
        let tcl = StructuralLoads.openSeesTcl(m, name: "Frame")
        let lines = tcl.components(separatedBy: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("node ") }.count, m.nodes.count)
        XCTAssertEqual(lines.filter { $0.hasPrefix("element elasticBeamColumn ") }.count, 6)
        XCTAssertEqual(lines.filter { $0.hasPrefix("geomTransf Linear ") }.count, 6)
        XCTAssertEqual(lines.filter { $0.hasPrefix("fix ") }.count, 4)
        XCTAssertEqual(lines.filter { $0.contains("eleLoad -ele") }.count, 6, "self weight on every member")
        XCTAssertTrue(tcl.contains("model BasicBuilder -ndm 3 -ndf 6"))
        XCTAssertTrue(tcl.contains("analyze 1"))
        XCTAssertEqual(tcl.filter { $0 == "{" }.count, tcl.filter { $0 == "}" }.count)
        // Elastic modulus in kPa (concrete 30 000 MPa).
        XCTAssertTrue(lines.contains { $0.hasPrefix("element elasticBeamColumn ") && $0.contains(" 30000000 ") })
    }

    func testSupportCodesAndWarnings() {
        XCTAssertEqual(StructuralLoads.supportFlags("pinned"), [true, true, true, false, false, false])
        XCTAssertEqual(StructuralLoads.supportFlags("001000"), [false, false, true, false, false, false])
        XCTAssertNil(StructuralLoads.supportFlags("12"))
        var d = frame()
        var e = Entity(layer: StructuralLoads.layer, geometry: .point(Vec2(50_000, 50_000)))
        e.props = ["structLoad": "point", "fz": "-5"]
        d.add(e)
        let m = StructuralAnalysis.model(d)
        XCTAssertTrue(m.warnings.contains { $0.contains("not on a node or beam") })
    }

    func testOpenSeesExportThroughFileExport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frame-\(UUID().uuidString).tcl")
        try DocumentIO.write(frame(), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("elasticBeamColumn"))
    }
}
