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
        XCTAssertEqual(vol(ed, id), 200 * (6000 * 3000 + 0.5 * 6000 * 1500), accuracy: 1e6)
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
}
