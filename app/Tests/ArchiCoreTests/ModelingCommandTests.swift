// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class ModelingCommandTests: XCTestCase {
    func solids(_ ed: Editor) -> [SolidGeom] { ed.doc.entities.compactMap { if case .solid(let s) = $0.geometry { return s }; return nil } }

    func testBooleanCommands() async {
        let ed = Editor()
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(500, 0, 0), size: Vec3(1000, 1000, 1000))))
        let ids = ed.doc.entities.map(\.id)
        ed.selection = Set(ids)
        await ed.run("UNION")
        XCTAssertEqual(solids(ed).count, 1)
        XCTAssertEqual(CSG.volume(solids(ed)[0]), 1.5e9, accuracy: 1e3)
        ed.undo()
        ed.selection = [ids[0]]
        await ed.run("SUBTRACT #\(ids[1]) ")
        XCTAssertEqual(solids(ed).count, 1)
        XCTAssertEqual(CSG.volume(solids(ed)[0]), 0.5e9, accuracy: 1e3)
        ed.undo()
        ed.selection = Set(ids)
        await ed.run("INTERSECT")
        XCTAssertEqual(CSG.volume(solids(ed)[0]), 0.5e9, accuracy: 1e3)
    }

    func testSliceAndInterfere() async {
        let ed = Editor()
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        ed.selection = [ed.doc.entities[0].id]
        await ed.run("SLICE XY 250 Below")
        XCTAssertEqual(CSG.volume(solids(ed)[0]), 0.25e9, accuracy: 1e3)
        ed.undo()
        ed.selection = [ed.doc.entities[0].id]
        await ed.run("SLICE 300,-10 300,10 ")
        XCTAssertEqual(solids(ed).count, 2)
        XCTAssertEqual(solids(ed).map(CSG.volume).reduce(0, +), 1e9, accuracy: 1e3)
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(900, 900, 900), size: Vec3(200, 200, 200))))
        ed.selection = Set(ed.doc.entities.map(\.id))
        let log = await ed.run("INTERFERE  Yes")
        XCTAssertTrue(ed.doc.entities.contains { $0.layer == "INTERFERENCE" }, log.joined(separator: "\n"))
    }

    func testPressPullLoftSweepPipe() async {
        let ed = Editor()
        await ed.run("RECTANG 0,0 1000,1000")
        await ed.run("CIRCLE 500,500 200")
        await ed.run("PRESSPULL 100,100 300")
        guard let s = solids(ed).last else { return XCTFail() }
        XCTAssertEqual(CSG.volume(s), (1e6 - MeshTools.signedVolume(MeshTools.mesh(of: SolidGeom(kind: .cylinder, origin: .zero, size: Vec3(200, 200, 1))))) * 300, accuracy: 1e5)
        let ed2 = Editor()
        await ed2.run("RECTANG 0,0 1000,1000")
        await ed2.run("RECTANG 100,100 900,900")
        let ll = await ed2.run("LOFT 0,500 100,500  0 500")
        guard let loft = solids(ed2).last else { return XCTFail(ll.joined(separator: "\n")) }
        XCTAssertEqual(CSG.volume(loft), 500.0 / 3 * (1e6 + 0.64e6 + 0.8e6), accuracy: 1e5, ll.joined(separator: "\n"))
        let ed3 = Editor()
        await ed3.run("RECTANG -50,-50 50,50")
        await ed3.run("PLINE 1000,0 3000,0 3000,2000 ")
        let prof = ed3.doc.entities[0].id
        ed3.selection = [prof]
        let sl = await ed3.run("SWEEP 2000,0 0")
        guard let sw = solids(ed3).last else { return XCTFail(sl.joined(separator: "\n")) }
        XCTAssertEqual(CSG.volume(sw), 4000 * 100 * 100, accuracy: 10)
        await ed3.run("PIPE 2000,0 50 10 0")
        guard let pipe = solids(ed3).last, solids(ed3).count == 2 else { return XCTFail("no pipe") }
        XCTAssertGreaterThan(CSG.volume(pipe), 0)
        XCTAssertLessThan(CSG.volume(pipe), 4000 * .pi * 50 * 50)
    }

    func testTopoFromTypedPointsAndPad() async {
        let ed = Editor()
        let tl = await ed.run("TOPO Enter 0,0,0 10000,0,1000 10000,10000,1000 0,10000,0 5000,5000,500")
        let tl2 = await ed.run("TOPO Enter \"0,0,0 10000,0,1000 10000,10000,1000 0,10000,0 5000,5000,500\"  250")
        guard let e = ed.doc.entities.last, case .solid(let s) = e.geometry else { return XCTFail((tl + tl2).joined(separator: "\n")) }
        XCTAssertEqual(e.props["topo"], "1")
        let items = DrawListBuilder.items(for: e, doc: ed.doc, options: DrawOptions())
        XCTAssertGreaterThan(items.count, 3)
        let before = CSG.volume(s)
        await ed.run("BUILDINGPAD 5000,5000 2000,2000 8000,2000 8000,8000 2000,8000  500")
        guard case .solid(let s2)? = ed.doc.entities.last?.geometry else { return XCTFail() }
        // Pad at mid height over a planar slope: cut and fill balance.
        XCTAssertEqual(CSG.volume(s2), before, accuracy: before * 0.01)
        XCTAssertEqual(Terrain.elevation(at: Vec2(5000, 5000), vertices: s2.meshVertices, triangles: s2.meshTriangles) ?? -1, 500, accuracy: 1)
    }
}
