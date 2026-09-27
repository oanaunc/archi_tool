// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Wall elevation profiles (gables, cut-outs), slanted and tapered walls.
@MainActor
final class BIMWallShapesTests: XCTestCase {
    func vol(_ ed: Editor, _ id: EntityID) -> Double {
        MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc).filter { $0.kind == "wall" }.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) }
    }

    func testGableAndCustomProfile() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let id = ed.doc.elements[0].id
        ed.selection = [id]
        await ed.run("WALLTOP Gable 4500")
        guard case .wall(let g)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.height, 4500, accuracy: 1e-9); XCTAssertEqual(g.profile?.count, 5)
        let expected20_1: Double = 200 * (6000 * 3000 + 0.5 * 6000 * 1500)
        XCTAssertEqual(vol(ed, id), expected20_1, accuracy: 1e6)
        let zs = MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc)[0].mesh.positions.map(\.z)
        XCTAssertEqual(zs.max() ?? 0, 4500, accuracy: 1e-6)
        // Section through the ridge: the cut is 4500 high.
        let sec = ElevationBuilder.entries(doc: ed.doc, view: .section, sectionLine: (Vec2(3000, -2000), Vec2(3000, 2000)))
        let ys = sec.filter { $0.id == id }.flatMap(\.items).compactMap { if case .fill(let l, _) = $0 { return l.flatMap { $0.map(\.y) } }; return nil }.flatMap { $0 }
        XCTAssertEqual(ys.max() ?? 0, 4500, accuracy: 1)
        // Custom profile with a cut-out at the bottom (a passage 1000 wide, 2000 high).
        ed.selection = [id]
        await ed.run("WALLTOP Profile \"0,0; 2000,0; 2000,2000; 3000,2000; 3000,0; 6000,0; 6000,3000; 0,3000\"")
        XCTAssertEqual(vol(ed, id), 200 * (6000 * 3000 - 1000 * 2000), accuracy: 1e6)
        // Round trip and reset.
        let back = try JSONDecoder().decode(WallGeom.self, from: JSONEncoder().encode({ () -> WallGeom in if case .wall(let w)? = ed.doc.element(id)?.geometry { return w }; return WallGeom(start: .zero, end: .zero) }()))
        XCTAssertEqual(back.profile?.count, 8)
        ed.selection = [id]
        await ed.run("WALLTOP Reset")
        XCTAssertEqual(vol(ed, id), 200 * 6000 * 4500, accuracy: 1e6, "the wall keeps the gable height")
    }

    func testSlantedAndTaperedWalls() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        let id = ed.doc.elements[0].id
        ed.selection = [id]
        await ed.run("WALLTOP Slant 10")
        guard case .wall(let g)? = ed.doc.element(id)?.geometry else { return XCTFail() }
        XCTAssertEqual(g.slant ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(vol(ed, id), 200 * 6000 * 3000, accuracy: 1e6, "shear keeps the volume")
        let top = MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc)[0].mesh.positions.filter { abs($0.z - 3000) < 1e-6 }.map(\.y)
        XCTAssertEqual(top.max() ?? 0, 100 + 3000 * tan(10 * Double.pi / 180), accuracy: 1e-6)
        // Plan at the cut plane (1200) shows the wall shifted by 1200·tan 10°.
        let plan = PlanRepresentation.items(ed.doc.element(id)!, doc: ed.doc).compactMap { if case .fill(let l, _) = $0 { return l.flatMap { $0 } }; return nil }.flatMap { $0 }
        XCTAssertEqual(plan.map(\.y).max() ?? 0, 100 + 1200 * tan(10 * Double.pi / 180), accuracy: 1e-6)
        // Taper to 100 at the top.
        ed.selection = [id]
        await ed.run("WALLTOP Reset")
        ed.selection = [id]
        await ed.run("WALLTOP Taper 100")
        XCTAssertEqual(vol(ed, id), 6000 * 3000 * 150, accuracy: 1e6)
        // Openings still cut a slanted wall.
        ed.selection = [id]
        await ed.run("WALLTOP Slant 5")
        await ed.run("WINDOW 3000,0 ")
        XCTAssertLessThan(vol(ed, id), 6000 * 3000 * 150 - 1e8)
    }

    /// BIM-023 clean joins: walls joined to a slanted wall follow it, so corners stay closed at every height.
    func testSlantedWallJoinsStayClean() async throws {
        let ed = Editor()
        await ed.run("WALL 0,0 6000,0 ")
        await ed.run("WALL 6000,0 9000,3000 ")
        let a = ed.doc.elements[0].id, b = ed.doc.elements[1].id
        ed.selection = [a]
        await ed.run("WALLTOP Slant 10")
        func top(_ id: EntityID) -> [Vec3] {
            MeshBuilder.groups(for: ed.doc.element(id)!, doc: ed.doc).filter { $0.kind == "wall" }.flatMap(\.mesh.positions)
                .filter { abs($0.z - 3000) < 1e-6 && $0.xy.distance(to: Vec2(6000, 0)) < 1500 }
        }
        let ta = top(a), tb = top(b)
        XCTAssertFalse(ta.isEmpty); XCTAssertFalse(tb.isEmpty)
        // Every corner vertex of the slanted wall at the top has a matching vertex on the joined wall.
        for p in ta where p.x > 5000 {
            XCTAssertLessThan(tb.map { $0.distance(to: p) }.min() ?? .infinity, 1e-6, "corner vertex \(p) is matched")
        }
        // The joined (vertical) wall's corner moved with the lean at the top but not at the base.
        let shift = 3000 * tan(10 * Double.pi / 180)
        XCTAssertGreaterThan(tb.map(\.y).min() ?? 0, -100 + shift - 150)
        let base = MeshBuilder.groups(for: ed.doc.element(b)!, doc: ed.doc)[0].mesh.positions.filter { abs($0.z) < 1e-6 }
        XCTAssertLessThan(base.map(\.y).min() ?? 0, 1e-6)
        // Plan at the cut plane: both walls meet at the same corner points.
        func planPts(_ id: EntityID) -> [Vec2] {
            PlanRepresentation.items(ed.doc.element(id)!, doc: ed.doc).compactMap { if case .fill(let l, _) = $0 { return l.flatMap { $0 } }; return nil }.flatMap { $0 }
        }
        let pa = planPts(a).filter { $0.x > 5500 }, pb = planPts(b)
        XCTAssertFalse(pa.isEmpty)
        for p in pa { XCTAssertLessThan(pb.map { $0.distance(to: p) }.min() ?? .infinity, 1e-6) }
        // A T-join into a tapered wall: the butting wall ends on the thinner face at the top.
        let ed2 = Editor()
        await ed2.run("WALL 0,0 6000,0 ")
        await ed2.run("WALL 3000,3000 3000,0 ")
        let host = ed2.doc.elements[0].id, stem = ed2.doc.elements[1].id
        ed2.selection = [host]
        await ed2.run("WALLTOP Taper 100")
        let stemTop = MeshBuilder.groups(for: ed2.doc.element(stem)!, doc: ed2.doc)[0].mesh.positions.filter { abs($0.z - 3000) < 1e-6 }
        XCTAssertEqual(stemTop.map(\.y).min() ?? 0, 50, accuracy: 1e-6)
        let stemBase = MeshBuilder.groups(for: ed2.doc.element(stem)!, doc: ed2.doc)[0].mesh.positions.filter { abs($0.z) < 1e-6 }
        XCTAssertEqual(stemBase.map(\.y).min() ?? 0, 100, accuracy: 1e-6)
    }
}
