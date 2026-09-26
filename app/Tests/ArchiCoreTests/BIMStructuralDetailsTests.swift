// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Reinforcement (BIM-085) and steel connections (BIM-087).
@MainActor
final class BIMStructuralDetailsTests: XCTestCase {
    func bounds(_ el: BIMElement, _ doc: ArchiDocument) -> BBox3 {
        var b = BBox3.empty
        for g in MeshBuilder.groups(for: el, doc: doc) { g.mesh.positions.forEach { b.add($0) } }
        return b
    }

    func testBeamColumnSlabRebar() async {
        let ed = Editor()
        let beam = ed.doc.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(6000, 0), width: 300, depth: 600, topOffset: 3000)))
        await ed.run("REBAR Add #\(beam) Bottom 16 30 3 8 0")
        guard let bottom = ed.doc.elements.last, bottom.props["rebarHost"] == "\(beam)" else { return XCTFail("no bars") }
        XCTAssertEqual(bottom.props["shapeCode"], "00"); XCTAssertEqual(bottom.props["barCount"], "3")
        XCTAssertEqual(Double(bottom.props["barLength"]!)!, 5940, accuracy: 0.1)
        XCTAssertEqual(Double(bottom.props["weightKg"]!)!, 3 * 5940 * Double.pi * 64 * 7.85e-6, accuracy: 0.02)
        // Bars lie inside the beam: bottom at 3000 − 600 + 30 + 8.
        let bb = bounds(bottom, ed.doc)
        XCTAssertEqual(bb.min.z, 2400 + 38, accuracy: 0.5)
        XCTAssertEqual(bb.min.y, -(150 - 38), accuracy: 0.5)
        await ed.run("REBAR Add #\(beam) Links 8 30 200")
        guard let links = ed.doc.elements.last, links.props["rebarSet"] == "links" else { return XCTFail("no links") }
        XCTAssertEqual(links.props["shapeCode"], "51"); XCTAssertEqual(links.props["barCount"], "30")
        await ed.run("REBAR Add #\(beam) Top 16 30 2 8 300")
        XCTAssertEqual(ed.doc.elements.last?.props["shapeCode"], "11")
        XCTAssertEqual(Double(ed.doc.elements.last!.props["barLength"]!)!, 5940 + 600, accuracy: 0.1)

        let col = ed.doc.addElement(.column(ColumnGeom(position: Vec2(10000, 0), width: 400, depth: 400, height: 3000)))
        await ed.run("REBAR Add #\(col) Vertical 20 40 6 10")
        XCTAssertEqual(ed.doc.elements.last?.props["barCount"], "6")
        XCTAssertEqual(Double(ed.doc.elements.last!.props["barLength"]!)!, 2920, accuracy: 0.1)
        await ed.run("REBAR Add #\(col) Links 10 40 150")
        XCTAssertEqual(ed.doc.elements.last?.props["barCount"], "20")

        let slab = ed.doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 5000), Vec2(5000, 5000), Vec2(5000, 9000), Vec2(0, 9000)], holes: [], thickness: 200, topOffset: 0)))
        await ed.run("REBAR Add #\(slab) X 12 30 200")
        guard let sx = ed.doc.elements.last, sx.props["rebarSet"] == "x" else { return XCTFail("no slab bars") }
        XCTAssertEqual(sx.props["barCount"], "20")
        XCTAssertEqual(Double(sx.props["barLength"]!)!, 4940, accuracy: 0.1)
        // Too much cover: refused.
        let n = ed.doc.elements.count
        await ed.run("REBAR Add #\(beam) Bottom 16 200 3 8 0")
        XCTAssertEqual(ed.doc.elements.count, n)
        // Schedule listing.
        await ed.run("REBAR List")
        // The bars follow the beam and go away with it.
        if let i = ed.doc.elementIndex(beam), case .beam(var g) = ed.doc.elements[i].geometry { g.end = Vec2(8000, 0); ed.doc.elements[i].geometry = .beam(g) }
        BIMUpdaters.run(&ed.doc)
        XCTAssertEqual(Double(ed.doc.element(bottom.id)!.props["barLength"]!)!, 7940, accuracy: 0.1)
        ed.doc.elements.removeAll { $0.id == beam }
        BIMUpdaters.run(&ed.doc)
        XCTAssertNil(ed.doc.element(bottom.id)); XCTAssertNil(ed.doc.element(links.id))
        XCTAssertNotNil(ed.doc.element(sx.id))
    }

    func testSteelConnections() async {
        let ed = Editor()
        let col = ed.doc.addElement(.column(ColumnGeom(position: Vec2(0, 0), height: 3000, profile: "HEA200")))
        await ed.run("STEELCONNECTION BasePlate #\(col) 20 60 24")
        guard let bp = ed.doc.elements.last, bp.props["connHost"] == "\(col)" else { return XCTFail("no base plate") }
        let sec = StructuralProfiles.section("HEA200")!
        XCTAssertEqual(Double(bp.props["plateWidth"]!)!, sec.b + 120, accuracy: 0.1)
        XCTAssertEqual(Double(bp.props["plateHeight"]!)!, sec.h + 120, accuracy: 0.1)
        XCTAssertEqual(bp.props["boltCount"], "4")
        let b1 = bounds(bp, ed.doc)
        XCTAssertLessThan(b1.min.z, -300)   // anchor bolts below the plate
        let beam = ed.doc.addElement(.beam(BeamGeom(start: Vec2(0, 0), end: Vec2(5000, 0), topOffset: 3000, profile: "IPE300")))
        await ed.run("STEELCONNECTION EndPlate #\(beam) End 15 60 20")
        guard let ep = ed.doc.elements.last, ep.props["connection"] == "endPlate" else { return XCTFail("no end plate") }
        XCTAssertEqual(ep.props["boltCount"], "12")
        let b2 = bounds(ep, ed.doc)
        XCTAssertEqual(b2.max.x, 5000 + 15 + 30, accuracy: 0.5)
        XCTAssertGreaterThan(Double(ep.props["plateWeightKg"]!)!, 0)
        // Follows the beam.
        if let i = ed.doc.elementIndex(beam), case .beam(var g) = ed.doc.elements[i].geometry { g.end = Vec2(6000, 0); ed.doc.elements[i].geometry = .beam(g) }
        BIMUpdaters.run(&ed.doc)
        XCTAssertEqual(bounds(ed.doc.element(ep.id)!, ed.doc).max.x, 6000 + 45, accuracy: 0.5)
        // Wrong host type is refused.
        let n = ed.doc.elements.count
        await ed.run("STEELCONNECTION EndPlate #\(col)")
        XCTAssertEqual(ed.doc.elements.count, n)
    }
}
