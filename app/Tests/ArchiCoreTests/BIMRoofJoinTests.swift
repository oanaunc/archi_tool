// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Roof join (BIM-059): a wing roof extended into the main roof and trimmed along the intersection.
@MainActor
final class BIMRoofJoinTests: XCTestCase {
    func bounds(_ el: BIMElement, _ doc: ArchiDocument) -> BBox3 {
        var b = BBox3.empty
        for g in MeshBuilder.groups(for: el, doc: doc) { g.mesh.positions.forEach { b.add($0) } }
        return b
    }

    func testWingRoofJoinsMainRoof() async {
        let ed = Editor()
        var main = RoofGeom(boundary: [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 8000), Vec2(0, 8000)], kind: .gable, pitch: 30, thickness: 200, overhang: 0, baseOffset: 3000, eaveEdge: 0)
        main.eaveEdge = 0
        let m = ed.doc.addElement(.roof(main))
        let wing = ed.doc.addElement(.roof(RoofGeom(boundary: [Vec2(3000, -6000), Vec2(7000, -6000), Vec2(7000, -1000), Vec2(3000, -1000)], kind: .gable, pitch: 30, thickness: 200, overhang: 0, baseOffset: 3000, eaveEdge: 1)))
        let before = bounds(ed.doc.element(wing)!, ed.doc)
        XCTAssertEqual(before.max.y, -1000, accuracy: 1)
        await ed.run("ROOFJOIN Join #\(wing) 5000,-1000 #\(m)")
        XCTAssertEqual(ed.doc.element(wing)?.props[RoofJoins.key], "\(m)")
        let after = bounds(ed.doc.element(wing)!, ed.doc)
        // The wing now runs into the main roof and stops where its ridge meets the main slope (y ≈ 2000).
        XCTAssertGreaterThan(after.max.y, 1500)
        XCTAssertLessThan(after.max.y, 2700)
        XCTAssertEqual(after.min.y, -6000, accuracy: 1)
        let vol = MeshBuilder.groups(for: ed.doc.element(wing)!, doc: ed.doc).map { MeshTools.signedVolume($0.mesh) }.reduce(0, +)
        XCTAssertGreaterThan(vol, 0)
        // Nothing of the wing is left above the main roof's top surface.
        let tv = 200 / cos(30 * Double.pi / 180)
        for g in MeshBuilder.groups(for: ed.doc.element(wing)!, doc: ed.doc) {
            for p in g.mesh.positions where p.y > 1 && p.y < 4000 && p.x > 0 && p.x < 10000 {
                XCTAssertLessThanOrEqual(p.z, 3000 + p.y * tan(30 * Double.pi / 180) + tv + 1)
            }
        }
        // Plan shows the intersection (lines inside the main roof's footprint).
        let items = PlanRepresentation.items(ed.doc.element(wing)!, doc: ed.doc)
        XCTAssertTrue(items.contains { if case .stroke(let pts, _, _) = $0 { return pts.contains { $0.y > 500 } }; return false })
        // Follows the main roof: raising it moves the intersection.
        if let i = ed.doc.elementIndex(m), case .roof(var g) = ed.doc.elements[i].geometry { g.baseOffset = 2500; ed.doc.elements[i].geometry = .roof(g) }
        XCTAssertGreaterThan(bounds(ed.doc.element(wing)!, ed.doc).max.y, after.max.y + 100)
        await ed.run("ROOFJOIN Unjoin #\(wing)")
        XCTAssertEqual(bounds(ed.doc.element(wing)!, ed.doc).max.y, -1000, accuracy: 1)
        // An edge facing away from the other roof is refused.
        await ed.run("ROOFJOIN Join #\(wing) 5000,-6000 #\(m)")
        XCTAssertNil(ed.doc.element(wing)?.props[RoofJoins.key])
    }
}
