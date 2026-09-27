// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Wall type layer wrapping at inserts and at free ends, in plan and 3D (BIM-015).
@MainActor
final class BIMWallWrapTests: XCTestCase {
    func volumes(_ el: BIMElement, _ doc: ArchiDocument) -> [String: Double] {
        var out: [String: Double] = [:]
        for g in MeshBuilder.groups(for: el, doc: doc) { out[g.material, default: 0] += MeshTools.signedVolume(g.mesh) }
        return out
    }

    func testWrapAtInsertsAndEnds() async {
        let ed = Editor()
        let w = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 365, height: 3000)))
        if let i = ed.doc.elementIndex(w), case .wall(var g) = ed.doc.elements[i].geometry { g.wallType = "Exterior Brick 365"; ed.doc.elements[i].geometry = .wall(g) }
        let o = ed.doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2500, width: 1000, height: 1500, sill: 900)))
        _ = o
        let v0 = volumes(ed.doc.element(w)!, ed.doc)
        XCTAssertNotNil(v0["Plaster"]); XCTAssertNotNil(v0["Brick"])
        await ed.run("WALLWRAP On")
        let v1 = volumes(ed.doc.element(w)!, ed.doc)
        let strip = 2 * 15.0 * (365 - 25) * 1500
        XCTAssertEqual(v1["Plaster"]! - v0["Plaster"]!, strip, accuracy: 1)
        XCTAssertEqual((v0["Brick"]! + v0["Insulation"]!) - (v1["Brick"]! + v1["Insulation"]!), strip, accuracy: 1)
        let total0 = v0.values.reduce(0, +), total1 = v1.values.reduce(0, +)
        XCTAssertEqual(total0, total1, accuracy: 1)
        // Plan: the core lines stop at the wrap and a return line crosses the core at the jamb.
        let items = PlanRepresentation.items(ed.doc.element(w)!, doc: ed.doc)
        XCTAssertTrue(items.contains { if case .stroke(let p, _, _) = $0, p.count == 2 { return abs(p[0].x - 1985) < 1e-6 && abs(p[1].x - 1985) < 1e-6 }; return false })
        // Ends.
        await ed.run("WALLWRAP Ends Yes")
        let v2 = volumes(ed.doc.element(w)!, ed.doc)
        let expected35_1: Double = 2 * 15.0 * (365 - 25) * 3000
        XCTAssertEqual(v2["Plaster"]! - v1["Plaster"]!, expected35_1, accuracy: 1)
        let items2 = PlanRepresentation.items(ed.doc.element(w)!, doc: ed.doc)
        XCTAssertTrue(items2.contains { if case .stroke(let p, _, _) = $0, p.count == 2 { return abs(p[0].x - 15) < 1e-6 && abs(p[1].x - 15) < 1e-6 }; return false })
        // Only inserts off, ends still on.
        await ed.run("WALLWRAP Off")
        let v3 = volumes(ed.doc.element(w)!, ed.doc)
        let expected41_1: Double = 2 * 15.0 * (365 - 25) * 3000
        XCTAssertEqual(v3["Plaster"]! - v0["Plaster"]!, expected41_1, accuracy: 1)
    }
}
