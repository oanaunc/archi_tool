// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

final class RenderTests: XCTestCase {
    func contains(_ pts: [Vec2], _ p: Vec2, tol: Double = 1e-6) -> Bool { pts.contains { $0.isClose(p, tol: tol) } }

    func testWallOutlineMiterAtLCorner() {
        var doc = ArchiDocument()
        let a = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200)))
        let b = doc.addElement(.wall(WallGeom(start: Vec2(4000, 0), end: Vec2(4000, 3000), thickness: 200)))
        let oa = PlanRepresentation.wallOutline(a, doc: doc)
        let ob = PlanRepresentation.wallOutline(b, doc: doc)
        XCTAssertEqual(oa.count, 4)
        XCTAssertTrue(contains(oa, Vec2(4100, -100)), "outer corner \(oa)")
        XCTAssertTrue(contains(oa, Vec2(3900, 100)), "inner corner \(oa)")
        XCTAssertTrue(contains(ob, Vec2(4100, -100)))
        XCTAssertTrue(contains(ob, Vec2(3900, 100)))
        // Free ends stay square.
        XCTAssertTrue(contains(oa, Vec2(0, -100)) && contains(oa, Vec2(0, 100)))
    }

    func testTJoinTrimsToHostFace() {
        var doc = ArchiDocument()
        _ = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 200)))
        let t = doc.addElement(.wall(WallGeom(start: Vec2(3000, 0), end: Vec2(3000, 2000), thickness: 100)))
        let o = PlanRepresentation.wallOutline(t, doc: doc)
        XCTAssertTrue(contains(o, Vec2(2950, 100)) && contains(o, Vec2(3050, 100)), "\(o)")
    }

    func testDoorCutsWallOutline() {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0), thickness: 200)))
        let wall0 = PlanRepresentation.items(doc.element(w)!, doc: doc)
        let fills0 = wall0.filter { if case .fill = $0 { return true }; return false }
        XCTAssertEqual(fills0.count, 1)
        let d = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: 2500, width: 900, height: 2100)))
        let el = doc.element(w)!
        let items = PlanRepresentation.items(el, doc: doc)
        let fills = items.compactMap { it -> [[Vec2]]? in if case .fill(let l, _) = it { return l }; return nil }
        XCTAssertEqual(fills.count, 2)
        XCTAssertGreaterThan(PlanRepresentation.distance(from: Vec2(2500, 0), to: el, doc: doc), 400)
        XCTAssertEqual(PlanRepresentation.distance(from: Vec2(1000, 0), to: el, doc: doc), 0, accuracy: 1e-9)
        // Door symbol: swing arc reaches the leaf length away from the wall face.
        let b = PlanRepresentation.bounds(doc.element(d)!, doc: doc)
        XCTAssertGreaterThan(b.max.y, 100 + 700)
    }

    func testLinearDimensionText() {
        let d = DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(1000, 0), Vec2(500, 300)])
        let st = DimStyle(name: "Standard")
        XCTAssertEqual(DimensionRenderer.measurement(d), 1000, accuracy: 1e-9)
        XCTAssertEqual(DimensionRenderer.formatted(d, style: st), "1000")
        let p = DimensionRenderer.primitives(d, style: st)
        XCTAssertEqual(p.text?.content, "1000")
        XCTAssertEqual(p.text!.position.x, 500, accuracy: 1e-9)
        XCTAssertGreaterThan(p.text!.position.y, 300)
        XCTAssertEqual(p.arrows.count, 2)
        var o = d; o.textOverride = "<> mm"
        XCTAssertEqual(DimensionRenderer.formatted(o, style: st), "1000 mm")
        let r = DimensionGeom(kind: .radius, points: [Vec2(0, 0), Vec2(250, 0)])
        XCTAssertEqual(DimensionRenderer.formatted(r, style: st), "R250")
        let ang = DimensionGeom(kind: .angular, points: [Vec2(0, 0), Vec2(100, 0), Vec2(0, 100), Vec2(50, 50)])
        XCTAssertEqual(DimensionRenderer.formatted(ang, style: st), "90°")
    }

    func testHatchANSI31InsideSquare() {
        let sq = [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]
        let lines = HatchPatterns.lines(loops: [sq], pattern: "ANSI31", scale: 1, angle: 0)
        XCTAssertFalse(lines.isEmpty)
        var total = 0.0
        for l in lines {
            for p in l { XCTAssertTrue(p.x >= -1e-6 && p.x <= 100 + 1e-6 && p.y >= -1e-6 && p.y <= 100 + 1e-6) }
            total += l[0].distance(to: l[l.count - 1])
        }
        XCTAssertEqual(total, 10000 / 3.175, accuracy: 10000 / 3.175 * 0.03)
        // A hole removes its share of the lines.
        let hole = [Vec2(25, 25), Vec2(75, 25), Vec2(75, 75), Vec2(25, 75)]
        let withHole = HatchPatterns.lines(loops: [sq, hole], pattern: "ANSI31", scale: 1, angle: 0)
        let t2 = withHole.reduce(0) { $0 + $1[0].distance(to: $1[$1.count - 1]) }
        XCTAssertEqual(t2, 7500 / 3.175, accuracy: 7500 / 3.175 * 0.04)
        XCTAssertTrue(HatchPatterns.lines(loops: [sq], pattern: "SOLID", scale: 1, angle: 0).isEmpty)
        for name in HatchPatterns.names where name != "SOLID" {
            XCTAssertFalse(HatchPatterns.lines(loops: [sq.map { $0 * 20 }], pattern: name, scale: 1, angle: 0.3).isEmpty, name)
        }
    }

    func testWallMeshWithWindow() {
        var doc = ArchiDocument()
        let w = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200, height: 3000)))
        let plain = MeshBuilder.groups(for: doc.element(w)!, doc: doc)
        XCTAssertEqual(plain.count, 1)
        _ = doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: 2000, width: 1200, height: 1200, sill: 900)))
        let cut = MeshBuilder.groups(for: doc.element(w)!, doc: doc)
        XCTAssertGreaterThan(cut[0].mesh.triangleCount, plain[0].mesh.triangleCount)
        let b = cut[0].mesh.bounds
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6); XCTAssertEqual(b.max.x, 4000, accuracy: 1e-6)
        XCTAssertEqual(b.min.y, -100, accuracy: 1e-6); XCTAssertEqual(b.max.y, 100, accuracy: 1e-6)
        XCTAssertEqual(b.min.z, 0, accuracy: 1e-6); XCTAssertEqual(b.max.z, 3000, accuracy: 1e-6)
        // Wall volume = full volume minus the window hole.
        let expected101_1: Double = 4000 * 200 * 3000 - 1200 * 200 * 1200
        XCTAssertEqual(volume(cut[0].mesh), expected101_1, accuracy: 1)
        let all = MeshBuilder.build(doc: doc)
        XCTAssertTrue(all.contains { $0.material == "Glass" })
    }

    func testSlabWithHoleArea() {
        var doc = ArchiDocument()
        let s = doc.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)],
                                              holes: [[Vec2(400, 400), Vec2(600, 400), Vec2(600, 600), Vec2(400, 600)]], thickness: 200)))
        let g = MeshBuilder.groups(for: doc.element(s)!, doc: doc)[0]
        var top = 0.0
        let m = g.mesh
        for i in stride(from: 0, to: m.indices.count, by: 3) {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            let n = (b - a).cross(c - a)
            if n.z > 0, abs(a.z) < 1e-9, abs(b.z) < 1e-9, abs(c.z) < 1e-9 { top += n.length / 2 }
        }
        XCTAssertEqual(top, 1_000_000 - 40_000, accuracy: 1e-3)
        XCTAssertEqual(volume(m), 960_000 * 200, accuracy: 1)
    }

    func testRoofAndElevation() {
        var doc = ArchiDocument()
        let rect = [Vec2(0, 0), Vec2(8000, 0), Vec2(8000, 6000), Vec2(0, 6000)]
        let r = doc.addElement(.roof(RoofGeom(boundary: rect, kind: .hip, pitch: 30, thickness: 200, overhang: 0, baseOffset: 3000)))
        let g = MeshBuilder.groups(for: doc.element(r)!, doc: doc)[0]
        // Hip roof over 8×6 m: ridge height = 3000 × tan 30° (+ vertical thickness).
        let tv = 200 / cos(rad(30))
        XCTAssertEqual(g.mesh.bounds.max.z, 3000 + 3000 * tan(rad(30)) + tv, accuracy: 1e-6)
        XCTAssertEqual(RoofShapes.faces(doc.element(r)!.geometry.roofGeom!).faces.count, 4)
        _ = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(8000, 0))))
        let south = ElevationBuilder.entries(doc: doc, view: .elevationSouth)
        XCTAssertGreaterThan(south.count, 1)
        let sec = ElevationBuilder.entries(doc: doc, view: .section, sectionLine: (Vec2(-100, 3000), Vec2(9000, 3000)))
        XCTAssertFalse(sec.isEmpty)
    }

    func testDrawListResolvesLayersAndBlocks() {
        var doc = ArchiDocument()
        doc.blocks["B"] = Block(name: "B", entities: [Entity(layer: "0", color: .byBlock, geometry: .line(LineGeom(Vec2(0, 0), Vec2(10, 0))))])
        _ = doc.add(Entity(layer: "0", color: .aci(1), geometry: .insert(InsertGeom(block: "B", position: Vec2(100, 0)))))
        _ = doc.add(Entity(layer: "0", color: .aci(7), geometry: .line(LineGeom(Vec2(0, 0), Vec2(1, 1)))))
        var opts = DrawOptions()
        opts.forPaper = true
        let e = DrawListBuilder.entries(doc: doc, options: opts)
        XCTAssertEqual(e.count, 2)
        if case .stroke(let pts, _, let st) = e[0].items[0] {
            XCTAssertEqual(pts[0], Vec2(100, 0)); XCTAssertEqual(st.color, RGBA(1, 0, 0))
        } else { XCTFail() }
        if case .stroke(_, _, let st) = e[1].items[0] { XCTAssertEqual(st.color, RGBA(0, 0, 0)) } else { XCTFail() }
        doc.layers[0].visible = false
        XCTAssertTrue(DrawListBuilder.entries(doc: doc, options: DrawOptions()).isEmpty)
    }

    func volume(_ m: Mesh) -> Double {
        var v = 0.0
        for i in stride(from: 0, to: m.indices.count, by: 3) {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            v += a.dot(b.cross(c)) / 6
        }
        return v
    }
}

private extension BIMGeometry {
    var roofGeom: RoofGeom? { if case .roof(let r) = self { return r }; return nil }
}
