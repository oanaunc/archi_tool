// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class ModelingFeatureTests: XCTestCase {
    func solid(_ ed: Editor, _ id: EntityID) -> SolidGeom? { if case .solid(let s)? = ed.doc.entity(id)?.geometry { return s }; return nil }

    func testSolidHistoryRegeneratesBooleans() async {
        let ed = Editor()
        await ed.run("SOLIDHIST On")
        var a = ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        let b = ed.doc.add(.solid(SolidGeom(kind: .cylinder, origin: Vec3(500, 500, -100), size: Vec3(200, 200, 1200))))
        let c = ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(900, 0, 0), size: Vec3(500, 1000, 1000))))
        ed.selection = [a]
        await ed.run("SUBTRACT #\(b) ")
        ed.selection = [a, c]
        await ed.run("UNION")
        // UNION keeps one of the two solids; continue with the survivor.
        a = ed.doc.entities.first { if case .solid = $0.geometry { return true }; return false }!.id
        guard let s = solid(ed, a), let h = s.history else { return XCTFail("no history") }
        XCTAssertEqual(h.features.map(\.op), [.subtract, .union])
        let hole = MeshTools.signedVolume(MeshTools.mesh(of: SolidGeom(kind: .cylinder, origin: .zero, size: Vec3(200, 200, 1000))))
        XCTAssertEqual(CSG.volume(s), 1e9 - hole + 0.4e9, accuracy: 1e5)
        // Suppress the hole: the solid regenerates without it.
        await ed.run("SOLIDHISTORY #\(a) Suppress 1")
        XCTAssertEqual(CSG.volume(solid(ed, a)!), 1.4e9, accuracy: 1e5)
        await ed.run("SOLIDHISTORY #\(a) Unsuppress 1")
        // Move the hole tool: still one hole, now nearer the corner (volume unchanged, shape changed).
        let before = solid(ed, a)!
        await ed.run("SOLIDHISTORY #\(a) Move 1 0,0 -200,-200 0")
        let moved = solid(ed, a)!
        XCTAssertNotEqual(moved.meshVertices, before.meshVertices)
        XCTAssertEqual(CSG.volume(moved), 1e9 - hole + 0.4e9, accuracy: 1e5)
        // Delete the union feature.
        await ed.run("SOLIDHISTORY #\(a) Delete 2")
        XCTAssertEqual(CSG.volume(solid(ed, a)!), 1e9 - hole, accuracy: 1e5)
        XCTAssertEqual(SolidHistoryEngine.describe(solid(ed, a)!.history!).count, 2)
        // History survives save/load.
        let back = try! ArchiFile.decode(try! ArchiFile.encode(ed.doc))
        XCTAssertEqual(back.entity(a)?.geometry, ed.doc.entity(a)?.geometry)
        await ed.run("SOLIDHISTORY #\(a) Flatten")
        XCTAssertNil(solid(ed, a)!.history)
    }

    func testAssociativeSweepFollowsItsPath() async {
        let ed = Editor()
        await ed.run("RECTANG -50,-50 50,50")
        await ed.run("PLINE 1000,0 3000,0 ")
        let prof = ed.doc.entities[0].id, path = ed.doc.entities[1].id
        ed.selection = [prof]
        await ed.run("SWEEP #\(path) 0")
        guard let sid = ed.doc.entities.last?.id, let s0 = solid(ed, sid), s0.source != nil else { return XCTFail("not associative") }
        XCTAssertEqual(CSG.volume(s0), 2000 * 100 * 100, accuracy: 10)
        // Lengthen the path: the sweep regenerates.
        if let i = ed.doc.entityIndex(path) { ed.doc.entities[i].geometry = .polyline(PolylineGeom(points: [Vec2(1000, 0), Vec2(4000, 0)])) }
        var d = ed.doc
        XCTAssertTrue(AssociativeSolids.updateAll(&d))
        guard case .solid(let s1)? = d.entity(sid)?.geometry else { return XCTFail() }
        XCTAssertEqual(CSG.volume(s1), 3000 * 100 * 100, accuracy: 10)
        XCTAssertFalse(AssociativeSolids.updateAll(&d), "up to date")
        // The 3D view shows the regenerated sweep without an explicit update.
        let g = MeshBuilder.build(doc: ed.doc).filter { $0.id == sid }
        XCTAssertEqual(g.reduce(0) { $0 + MeshTools.signedVolume($1.mesh) }, 3000 * 100 * 100, accuracy: 10)
        // Changing the profile also regenerates.
        if let i = ed.doc.entityIndex(prof) { ed.doc.entities[i].geometry = .polyline(PolylineGeom(points: [Vec2(-100, -50), Vec2(100, -50), Vec2(100, 50), Vec2(-100, 50)], closed: true)) }
        d = ed.doc
        AssociativeSolids.updateAll(&d)
        guard case .solid(let s2)? = d.entity(sid)?.geometry else { return XCTFail() }
        XCTAssertEqual(CSG.volume(s2), 3000 * 200 * 100, accuracy: 10)
    }

    func testPushPullFacesOfAnySolid() async {
        let ed = Editor()
        // A mesh solid (from a boolean) so PRESSPULL works on its faces rather than an extrusion height.
        let a = ed.doc.add(.solid(MeshTools.solid(from: MeshTools.triangles(MeshTools.mesh(of: SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000)))))))
        await ed.run("PRESSPULL 500,500 250")
        XCTAssertEqual(CSG.volume(solid(ed, a)!), 1.25e9, accuracy: 1e4)
        await ed.run("PRESSPULLFACE Side 1000,500 -200")
        XCTAssertEqual(CSG.volume(solid(ed, a)!), 1.25e9 - 0.2 * 1.25e9, accuracy: 1e4)
        let b = MeshTools.mesh(of: solid(ed, a)!).bounds
        XCTAssertEqual(b.max.x, 800, accuracy: 1e-6)
        XCTAssertEqual(b.max.z, 1250, accuracy: 1e-6)
        // Bottom face pulled down.
        await ed.run("PRESSPULLFACE Bottom 400,400 100")
        XCTAssertEqual(MeshTools.mesh(of: solid(ed, a)!).bounds.min.z, -100, accuracy: 1e-6)
        // Face detection details.
        let f = FacePushPull.pick(solid(ed, a)!, at: Vec2(400, 400), mode: "top")!
        XCTAssertEqual(f.area, 800 * 1000, accuracy: 1)
        XCTAssertEqual(f.normal.z, 1, accuracy: 1e-9)
    }

    func testSectionBlocksFromSolids() async {
        let ed = Editor()
        ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(2000, 1000, 1500))))
        ed.doc.add(.solid(SolidGeom(kind: .cylinder, origin: Vec3(3000, 500, 0), size: Vec3(400, 400, 1000))))
        await ed.run("SECTIONSOLIDS 0,500 5000,500 No 0,-5000")
        guard let ins = ed.doc.entities.last, case .insert(let i) = ins.geometry, let blk = ed.doc.blocks[i.block] else { return XCTFail("no section block") }
        XCTAssertTrue(blk.description.hasPrefix("view:solidsection:"))
        // Cut poché: two closed loops (box 2000 × 1500, cylinder 800 × 1000).
        let fills = blk.entities.filter { if case .hatch = $0.geometry { return true }; return false }
        XCTAssertGreaterThanOrEqual(fills.count, 2)
        let loops = SolidSections.horizontal(doc: ed.doc, z: 500)
        XCTAssertEqual(loops.count, 2)
        XCTAssertEqual(loops.map { abs(GeometryOps.signedArea($0)) }.max()!, 2000 * 1000, accuracy: 1)
        // VIEWUPDATE regenerates it after the solids change.
        ed.doc.entities[0].geometry = .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(2000, 1000, 3000)))
        await ed.run("VIEWUPDATE")
        let b2 = ed.doc.blocks[i.block]!
        var box = BBox2.empty
        for e in b2.entities { box.add(GeometryOps.bounds(e.geometry, doc: ed.doc)) }
        XCTAssertEqual(box.height, 3000, accuracy: 1)
        await ed.run("SECTIONSOLIDS Plan 500")
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == "A-SECT" }.count, 4)
    }
}
