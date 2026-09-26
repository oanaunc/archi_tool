// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Parametric feature modelling: cylinder/extrude options, associative revolve, follow-me, helical sweep, pad/pocket,
/// holes, patterns, mirrors, split/fuse, face editing, offset solids and CSG trees.
@MainActor
final class ModelingParametricFeatureTests: XCTestCase {
    func solid(_ ed: Editor, _ id: EntityID) -> SolidGeom? { ModelingCommands.solidOf(ed.doc, id) }
    func lastSolid(_ ed: Editor) -> SolidGeom? { if case .solid(let s)? = ed.doc.entities.last?.geometry { return s }; return nil }
    func lastID(_ ed: Editor) -> EntityID { ed.doc.entities.last!.id }
    func watertight(_ s: SolidGeom?, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = s else { return XCTFail("no solid", file: file, line: line) }
        XCTAssertTrue(SolidCheck.report(SolidCheck.triangles(s)).valid, "watertight", file: file, line: line)
    }
    func vol(_ s: SolidGeom?) -> Double { s.map(CSG.volume) ?? 0 }
    func box(_ ed: Editor, _ o: Vec3, _ size: Vec3) -> EntityID { ed.doc.add(.solid(SolidGeom(kind: .box, origin: o, size: size))) }
    func rect(_ ed: Editor, _ a: Vec2, _ b: Vec2) -> EntityID {
        ed.doc.add(.polyline(PolylineGeom(points: [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true)))
    }
    /// Editor whose registry has the full CYLINDER / EXTRUDE / REVOLVE.
    func editor() -> Editor {
        let reg = CommandRegistry()
        reg.ensureBuiltins()
        reg.register(FeatureCommands9.drawOverrides)
        return Editor(registry: reg)
    }
    func regen(_ ed: Editor) { var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d }

    func testCylinderOptions() async {
        let ed = editor()
        await ed.run("CYLINDER 0,0 500 1000")
        let cv: Double = Double.pi * 2.5e8
        XCTAssertEqual(vol(lastSolid(ed)), cv, accuracy: cv * 0.01)
        await ed.run("CYLINDER E -500,0 500,0 250 1000")
        XCTAssertEqual(ed.doc.entities.last?.props["primitive"], "ellipticalCylinder")
        let ev: Double = Double.pi * 1.25e8
        XCTAssertEqual(vol(lastSolid(ed)), ev, accuracy: 1)
        watertight(lastSolid(ed))
        await ed.run("CYLINDER 2P 0,0 1000,0 1000")
        XCTAssertEqual(lastSolid(ed)?.size.x ?? 0, 500, accuracy: 1e-9)
        XCTAssertEqual(lastSolid(ed)?.origin.x ?? 0, 500, accuracy: 1e-9)
        await ed.run("CYLINDER 3P 0,0 1000,0 500,500 100")
        XCTAssertEqual(lastSolid(ed)?.size.x ?? 0, 500, accuracy: 1e-6)
        await ed.run("CYLINDER 0,0 100 A 1000,0 0")
        let ax = lastSolid(ed)
        let av: Double = Double.pi * 1e7
        XCTAssertEqual(vol(ax), av, accuracy: 10)
        watertight(ax)
        XCTAssertEqual(ModelingCommands.bounds(ax!).size.x, 1000, accuracy: 1e-6)
    }

    func testExtrudeTaperBothDirection() async {
        let ed = editor()
        _ = rect(ed, Vec2(0, 0), Vec2(1000, 1000))
        await ed.run("EXTRUDE L  T 10 500")
        let top = 1000 - 2 * 500 * tan(rad(10))
        let a1 = 1e6, a2 = top * top
        XCTAssertEqual(vol(lastSolid(ed)), 500.0 / 3 * (a1 + a2 + (a1 * a2).squareRoot()), accuracy: 1e3)
        watertight(lastSolid(ed))
        _ = rect(ed, Vec2(0, 0), Vec2(1000, 1000))
        await ed.run("EXTRUDE L  B 500")
        XCTAssertEqual(vol(lastSolid(ed)), 1e9, accuracy: 1)
        XCTAssertEqual(ModelingCommands.bounds(lastSolid(ed)!).min.z, -500, accuracy: 1e-9)
        _ = rect(ed, Vec2(0, 0), Vec2(1000, 1000))
        await ed.run("EXTRUDE L  D 0,0 300,0 500")
        XCTAssertEqual(vol(lastSolid(ed)), 0.5e9, accuracy: 1)
        XCTAssertEqual(ModelingCommands.bounds(lastSolid(ed)!).max.x, 1300, accuracy: 1e-9)
        watertight(lastSolid(ed))
    }

    func testAssociativeRevolveRegenerates() async {
        let ed = editor()
        let r = rect(ed, Vec2(100, 0), Vec2(200, 100))
        await ed.run("REVOLVE #\(r)  0,0 0,100 360")
        let sid = lastID(ed)
        XCTAssertEqual(solid(ed, sid)?.source?.kind, .revolve)
        let v1: Double = Double.pi * 30000.0 * 100.0
        XCTAssertEqual(vol(solid(ed, sid)), v1, accuracy: v1 * 0.02)
        ed.doc.entities[ed.doc.entityIndex(r)!].geometry = .polyline(PolylineGeom(points: [Vec2(100, 0), Vec2(300, 0), Vec2(300, 100), Vec2(100, 100)], closed: true))
        regen(ed)
        let v2: Double = Double.pi * 80000.0 * 100.0
        XCTAssertEqual(vol(solid(ed, sid)), v2, accuracy: v2 * 0.02)
        watertight(solid(ed, sid))
        // Round trip through the file format keeps the source.
        let data = try! JSONEncoder().encode(ed.doc)
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(ModelingCommands.solidOf(back, sid)?.source?.params?.count, 6)
    }

    func testFollowMeAndHelicalSweep() async {
        let ed = Editor()
        let path = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)], closed: true)))
        let prof = rect(ed, Vec2(0, 0), Vec2(100, 50))
        await ed.run("FOLLOWME #\(prof) #\(path) ")
        let fm = lastSolid(ed)
        XCTAssertEqual(fm?.source?.kind, .followMe)
        XCTAssertEqual(vol(fm), 5000 * 3800, accuracy: 5000 * 3800 * 0.02)
        XCTAssertEqual(ModelingCommands.bounds(fm!).max.z, 100, accuracy: 1e-6)
        let c = ed.doc.add(.circle(CircleGeom(Vec2(5000, 0), 20)))
        await ed.run("SWEEP3D #\(c) H 0,0 500 200 2 CCW 0")
        let hs = lastSolid(ed)
        XCTAssertEqual(hs?.source?.kind, .sweep3D)
        let circ: Double = 2 * Double.pi * 500
        let len: Double = 2 * (circ * circ + 40000.0).squareRoot()
        let hv: Double = Double.pi * 400 * len
        XCTAssertEqual(vol(hs), hv, accuracy: hv * 0.04)
        XCTAssertEqual(ModelingCommands.bounds(hs!).max.z, 400, accuracy: 30)
        // Editing the profile regenerates the sweep.
        ed.doc.entities[ed.doc.entityIndex(c)!].geometry = .circle(CircleGeom(Vec2(5000, 0), 30))
        regen(ed)
        let hv2: Double = Double.pi * 900 * len
        XCTAssertEqual(vol(lastSolid(ed)), hv2, accuracy: hv2 * 0.04)
    }

    func testPadPocketFollowSketch() async {
        let ed = Editor()
        let r = rect(ed, Vec2(0, 0), Vec2(1000, 1000))
        await ed.run("PAD #\(r) N 500")
        let sid = lastID(ed)
        XCTAssertEqual(vol(solid(ed, sid)), 0.5e9, accuracy: 1)
        var circ = Entity(layer: "0", geometry: .circle(CircleGeom(Vec2(500, 500), 100)))
        circ.props["elevation"] = "500"
        let c = ed.doc.add(circ)
        await ed.run("POCKET #\(c) #\(sid) 200")
        let cyl = MeshTools.signedVolume(MeshTools.mesh(of: SolidGeom(kind: .extrusion, origin: .zero, profile: ModelingCommands.loop(ed.doc, c)!, height: 200)))
        XCTAssertEqual(vol(solid(ed, sid)), 0.5e9 - cyl, accuracy: 1e4)
        XCTAssertEqual(solid(ed, sid)?.history?.features.first?.source?.kind, .extrude)
        // Larger sketch circle → larger pocket after regeneration.
        ed.doc.entities[ed.doc.entityIndex(c)!].geometry = .circle(CircleGeom(Vec2(500, 500), 150))
        regen(ed)
        let cyl2 = MeshTools.signedVolume(MeshTools.mesh(of: SolidGeom(kind: .extrusion, origin: .zero, profile: ModelingCommands.loop(ed.doc, c)!, height: 200)))
        XCTAssertEqual(vol(solid(ed, sid)), 0.5e9 - cyl2, accuracy: 1e4)
        // Pad on top of the body.
        var r2 = Entity(layer: "0", geometry: .polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)], closed: true)))
        r2.props["elevation"] = "500"
        let p2 = ed.doc.add(r2)
        await ed.run("PAD #\(p2) #\(sid) 100")
        XCTAssertEqual(vol(solid(ed, sid)), 0.5e9 - cyl2 + 1e6, accuracy: 1e4)
    }

    func testHoles() async {
        let ed = Editor()
        let b = box(ed, .zero, Vec3(1000, 1000, 100))
        let p = ed.doc.add(.point(Vec2(500, 500)))
        await ed.run("HOLE #\(b) #\(p)  20 T Simple .")
        let simple = vol(solid(ed, b))
        let hole = 1e8 - simple
        let hv: Double = Double.pi * 10000.0
        XCTAssertEqual(hole, hv, accuracy: hv * 0.03)
        let b2 = box(ed, Vec3(2000, 0, 0), Vec3(1000, 1000, 100))
        let p2 = ed.doc.add(.point(Vec2(2500, 500)))
        await ed.run("HOLE #\(b2) #\(p2)  20 T Counterbore 40 30 M20")
        let cb = 1e8 - vol(solid(ed, b2))
        let cbv: Double = Double.pi * 19000.0
        XCTAssertEqual(cb, cbv, accuracy: cbv * 0.03)
        XCTAssertEqual(ed.doc.entity(b2)?.props["thread"], "M20")
        // Moving the sketch point moves the hole (volume unchanged, hole relocated).
        ed.doc.entities[ed.doc.entityIndex(p2)!].geometry = .point(Vec2(2200, 300))
        regen(ed)
        XCTAssertEqual(1e8 - vol(solid(ed, b2)), cb, accuracy: cb * 0.01)
        let mesh = MeshTools.mesh(of: solid(ed, b2)!)
        XCTAssertTrue(mesh.positions.contains { abs($0.x - 2200) < 21 && abs($0.y - 300) < 21 && $0.z > 1 && $0.z < 99 })
    }

    func testPatternAndMirrorFeatures() async {
        let ed = Editor()
        let b = box(ed, .zero, Vec3(1000, 1000, 100))
        var sq = Entity(layer: "0", geometry: .polyline(PolylineGeom(points: [Vec2(100, 100), Vec2(200, 100), Vec2(200, 200), Vec2(100, 200)], closed: true)))
        sq.props["elevation"] = "100"
        let s = ed.doc.add(sq)
        await ed.run("POCKET #\(s) #\(b) 50")
        XCTAssertEqual(vol(solid(ed, b)), 1e8 - 1e4 * 50, accuracy: 1e3)
        await ed.run("PATTERNFEATURE #\(b) 1 Linear 3 250 2 300 0")
        XCTAssertEqual(vol(solid(ed, b)), 1e8 - 6 * 1e4 * 50, accuracy: 1e3)
        // Mirror the whole body about x = 0.
        await ed.run("MIRRORFEATURE #\(b) Body 0,0 0,100")
        XCTAssertEqual(vol(solid(ed, b)), 2 * (1e8 - 6 * 1e4 * 50), accuracy: 1e4)
        XCTAssertEqual(ModelingCommands.bounds(solid(ed, b)!).min.x, -1000, accuracy: 1e-6)
        // Polar pattern of a cylinder-like pocket.
        let b2 = box(ed, Vec3(5000, 0, 0), Vec3(1000, 1000, 100))
        var sq2 = Entity(layer: "0", geometry: .polyline(PolylineGeom(points: [Vec2(5400, 100), Vec2(5600, 100), Vec2(5600, 200), Vec2(5400, 200)], closed: true)))
        sq2.props["elevation"] = "100"
        let s2 = ed.doc.add(sq2)
        await ed.run("POCKET #\(s2) #\(b2) 50")
        await ed.run("PATTERNFEATURE #\(b2) 1 Polar 5500,500 4 360")
        XCTAssertEqual(vol(solid(ed, b2)), 1e8 - 4 * 2e4 * 50, accuracy: 1e3)
    }

    func testSplitAndGeneralFuse() async {
        let ed = Editor()
        let a = box(ed, .zero, Vec3(1000, 1000, 1000))
        let t = box(ed, Vec3(500, -100, -100), Vec3(1000, 1200, 1200))
        ed.selection = [a]
        await ed.run("SPLITSOLID #\(t)  Yes")
        let solids = ed.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry, e.id != t { return s }; return nil }
        XCTAssertEqual(solids.count, 2)
        for s in solids { XCTAssertEqual(vol(s), 0.5e9, accuracy: 1e3) }
        let ed2 = Editor()
        let x = box(ed2, .zero, Vec3(1000, 1000, 1000)), y = box(ed2, Vec3(500, 0, 0), Vec3(1000, 1000, 1000))
        ed2.selection = [x, y]
        await ed2.run("GFUSE")
        let pieces = ed2.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry { return s }; return nil }
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.map(vol).reduce(0, +), 1.5e9, accuracy: 1e4)
        for p in pieces { XCTAssertEqual(vol(p), 0.5e9, accuracy: 1e3) }
    }

    func testFaceEditsAndOffsetSolid() async {
        let ed = Editor()
        let b = box(ed, .zero, Vec3(1000, 1000, 1000))
        await ed.run("SOLIDEDIT Face Offset #\(b) 500,500 200")
        XCTAssertEqual(vol(solid(ed, b)), 1.2e9, accuracy: 1e3)
        watertight(solid(ed, b))
        await ed.run("SOLIDEDIT Face Move #\(b) 500,500 0,0 0,0 -200")
        XCTAssertEqual(vol(solid(ed, b)), 1e9, accuracy: 1e3)
        await ed.run("SOLIDEDIT Face Taper #\(b) Side 1000,500 10")
        XCTAssertEqual(vol(solid(ed, b)), 1e9 - 0.5 * 1000 * 1000 * tan(rad(10)) * 1000, accuracy: 1e4)
        watertight(solid(ed, b))
        let c = box(ed, Vec3(5000, 0, 0), Vec3(1000, 1000, 1000))
        ed.selection = [c]
        await ed.run("OFFSETSOLID 100")
        XCTAssertEqual(vol(solid(ed, c)), 1200 * 1200 * 1200, accuracy: 1e3)
        ed.selection = [c]
        await ed.run("OFFSETSOLID -700")
        XCTAssertEqual(vol(solid(ed, c)), 1200 * 1200 * 1200, accuracy: 1e3, "an offset that inverts the solid is refused")
    }

    func testCSGTreeRegenerates() async {
        let ed = Editor()
        let a = box(ed, .zero, Vec3(1000, 1000, 1000))
        let b = box(ed, Vec3(500, 0, 0), Vec3(1000, 1000, 1000))
        let c = box(ed, Vec3(3000, 0, 0), Vec3(100, 100, 100))
        XCTAssertEqual(CSGTrees.parse("#1 - #2 + #3 u #4")?.count, 2)
        XCTAssertNil(CSGTrees.parse("u #1 - - #2"))
        await ed.run("CSGTREE \"u #\(a) - #\(b) u #\(c)\" Yes")
        let t = lastID(ed)
        XCTAssertEqual(solid(ed, t)?.source?.kind, .csgTree)
        XCTAssertEqual(vol(solid(ed, t)), 0.5e9 + 1e6, accuracy: 1e3)
        XCTAssertEqual(ed.doc.entity(a)?.layer, FeatureCommands9.csgLayer)
        ed.doc.entities[ed.doc.entityIndex(b)!].geometry = .solid(SolidGeom(kind: .box, origin: Vec3(750, 0, 0), size: Vec3(1000, 1000, 1000)))
        regen(ed)
        XCTAssertEqual(vol(solid(ed, t)), 0.75e9 + 1e6, accuracy: 1e3)
    }

    func testNonUniformScale3D() async {
        let ed = Editor()
        let b = box(ed, .zero, Vec3(1000, 1000, 1000))
        ed.selection = [b]
        await ed.run("SCALE3D 0,0 0 2 3 0.5")
        XCTAssertEqual(vol(solid(ed, b)), 3e9, accuracy: 1)
        let bb = ModelingCommands.bounds(solid(ed, b)!)
        XCTAssertEqual(bb.max.x, 2000, accuracy: 1e-9); XCTAssertEqual(bb.max.y, 3000, accuracy: 1e-9); XCTAssertEqual(bb.max.z, 500, accuracy: 1e-9)
        ed.selection = [b]
        await ed.run("SCALE3D 0,0 0 -1 1 1")
        XCTAssertEqual(vol(solid(ed, b)), 3e9, accuracy: 1, "mirroring keeps the solid outward-facing")
    }

    func testShapeBinderFollowsSource() async {
        let ed = Editor()
        let b = box(ed, .zero, Vec3(1000, 1000, 500))
        await ed.run("SHAPEBINDER #\(b) Solid 0,0 3000,0 0")
        let s1 = lastID(ed)
        XCTAssertEqual(solid(ed, s1)?.source?.kind, .binder)
        XCTAssertEqual(ModelingCommands.bounds(solid(ed, s1)!).min.x, 3000, accuracy: 1e-9)
        await ed.run("SHAPEBINDER #\(b) Face 500,500  200")
        let f1 = lastID(ed)
        XCTAssertEqual(SurfaceNetwork.area((solid(ed, f1)!.meshVertices, solid(ed, f1)!.meshTriangles)), 1e6, accuracy: 1e-6)
        XCTAssertEqual(ModelingCommands.bounds(solid(ed, f1)!).min.z, 700, accuracy: 1e-9)
        ed.doc.entities[ed.doc.entityIndex(b)!].geometry = .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(2000, 1000, 800)))
        regen(ed)
        XCTAssertEqual(vol(solid(ed, s1)), 1.6e9, accuracy: 1)
        XCTAssertEqual(ModelingCommands.bounds(solid(ed, f1)!).min.z, 1000, accuracy: 1e-9)
        XCTAssertEqual(SurfaceNetwork.area((solid(ed, f1)!.meshVertices, solid(ed, f1)!.meshTriangles)), 2e6, accuracy: 1e-6)
    }
}
