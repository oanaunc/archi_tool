// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Corner windows (BIM-041): both walls cut through the corner, glazing to the corner, plan symbol on the mitre.
@MainActor
final class BIMCornerWindowTests: XCTestCase {
    func volume(_ gs: [MeshGroup]) -> Double { gs.map { MeshTools.signedVolume($0.mesh) }.reduce(0, +) }

    func testCornerWindowCutsBothWalls() async {
        let ed = Editor()
        let a = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200, height: 3000)))
        let b = ed.doc.addElement(.wall(WallGeom(start: Vec2(5000, 0), end: Vec2(5000, 4000), thickness: 200, height: 3000)))
        let ctx0 = BIMContext(doc: ed.doc)
        let outA = ctx0.outline(ctx0.frames[a]!), outB = ctx0.outline(ctx0.frames[b]!)
        let fullA = abs(GeometryOps.signedArea(outA)) * 3000, fullB = abs(GeometryOps.signedArea(outB)) * 3000
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.element(a)!, doc: ed.doc)), fullA, accuracy: 10)

        await ed.run("CORNERWINDOW #\(a) #\(b) 1200 1500 1500 900")
        let ws = ed.doc.elements.filter { $0.props[CornerWindows.endKey] != nil }
        XCTAssertEqual(ws.count, 2)
        guard let wa = ws.first(where: { if case .opening(let o) = $0.geometry { return o.hostWall == a }; return false }) else { return XCTFail() }
        XCTAssertEqual(wa.props[CornerWindows.endKey], "end")
        let ctx = BIMContext(doc: ed.doc)
        let fa = ctx.frames[a]!
        // The cut runs through the wall end; no end piece is left.
        XCTAssertGreaterThan(ctx.cuts(fa).last!.s1, fa.L)
        XCTAssertEqual(ctx.pieces(fa).map(\.s1).max()!, 5000 - 1200, accuracy: 1e-6)
        // 3D: the wall loses exactly the part of its mitred outline beyond the jamb, over the window height.
        func cutArea(_ outline: [Vec2], _ keep: [Vec2]) -> Double {
            PolygonBoolean.apply(.intersect, [outline], [keep]).map { abs(GeometryOps.signedArea($0)) }.reduce(0, +)
        }
        let ccwA = GeometryOps.signedArea(outA) < 0 ? Array(outA.reversed()) : outA
        let ccwB = GeometryOps.signedArea(outB) < 0 ? Array(outB.reversed()) : outB
        let zoneA = cutArea(ccwA, [Vec2(3800, -500), Vec2(6000, -500), Vec2(6000, 500), Vec2(3800, 500)])
        let zoneB = cutArea(ccwB, [Vec2(4500, -500), Vec2(5500, -500), Vec2(5500, 1500), Vec2(4500, 1500)])
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.element(a)!, doc: ed.doc)), fullA - zoneA * 1500, accuracy: 10)
        XCTAssertEqual(volume(MeshBuilder.groups(for: ed.doc.element(b)!, doc: ed.doc)), fullB - zoneB * 1500, accuracy: 10)
        // Glass reaches the corner point.
        var glass = BBox3.empty
        for g in MeshBuilder.groups(for: wa, doc: ed.doc) where g.material == "Glass" { g.mesh.positions.forEach { glass.add($0) } }
        XCTAssertEqual(glass.max.x, 5000, accuracy: 1e-6)
        XCTAssertEqual(glass.min.z, 900 + 50, accuracy: 1e-6)
        // Plan: the symbol stays inside the wall outline (sill lines end on the mitre).
        let items = PlanRepresentation.items(wa, doc: ed.doc)
        XCTAssertFalse(items.isEmpty)
        for it in items { if case .stroke(let pts, _, _) = it { for p in pts { XCTAssertLessThanOrEqual(p.x, 5100 + 1e-6); XCTAssertGreaterThanOrEqual(p.y, -100 - 1e-6) } } }
        // Deleting one window leaves an ordinary window.
        ed.doc.elements.removeAll { $0.id == wa.id }
        BIMUpdaters.run(&ed.doc)
        XCTAssertFalse(CornerWindows.hasContent(ed.doc))
        // Walls that do not meet: refused.
        let c = ed.doc.addElement(.wall(WallGeom(start: Vec2(0, 8000), end: Vec2(3000, 8000))))
        let n = ed.doc.elements.count
        await ed.run("CORNERWINDOW #\(a) #\(c) 1000 1000 1500 900")
        XCTAssertEqual(ed.doc.elements.count, n)
    }
}
