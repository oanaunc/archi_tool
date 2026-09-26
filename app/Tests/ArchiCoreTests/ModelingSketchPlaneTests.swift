// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Sketch environment on work planes (M3D-076, M3D-084): constrained sketches and associative pads.
@MainActor
final class ModelingSketchPlaneTests: XCTestCase {
    func bounds(_ s: SolidGeom) -> BBox3 { MeshTools.mesh(of: s).bounds }

    func testPlanSketchConstrainedPad() async {
        let ed = Editor()
        await ed.run("SKETCHPLANE New S1 XY 0")
        XCTAssertNotNil(Sketches.plane("S1", doc: ed.doc))
        let pl = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 500), Vec2(0, 500)], closed: true)))
        await ed.run("SKETCHPLANE Add S1 #\(pl) ")
        XCTAssertEqual(ed.doc.entity(pl)?.props["sketch"], "S1")
        XCTAssertEqual(Sketches.freedom("S1", doc: ed.doc), 8)
        await ed.run("SKETCHPAD S1 300")
        guard let pad = ed.doc.entities.last, pad.props["sketchPad"] == "S1", case .solid(let s) = pad.geometry else { return XCTFail("no pad") }
        XCTAssertEqual(CSG.volume(s), 1000 * 500 * 300, accuracy: 1)
        // Constrain: fix the first corner, keep the edges horizontal/vertical, drive the width to 1500.
        var set = ConstraintSet.load(ed.doc)
        func add(_ k: ConstraintKind, _ refs: [CRef], value: Double? = nil, anchor: Vec2? = nil, name: String? = nil) {
            set.constraints.append(GeoConstraint(id: set.nextID, kind: k, refs: refs, value: value, name: name, anchor: anchor)); set.nextID += 1
        }
        add(.fixed, [CRef(pl, 0)], anchor: .zero)
        add(.horizontal, [CRef(pl, 0)]); add(.vertical, [CRef(pl, 1)]); add(.horizontal, [CRef(pl, 2)]); add(.vertical, [CRef(pl, 3)])
        add(.distance, [CRef(pl, 0), CRef(pl, 1)], value: 1500, name: "w")
        add(.distance, [CRef(pl, 1), CRef(pl, 2)], value: 500, name: "d")
        set.save(&ed.doc)
        XCTAssertEqual(Constraints.solve(&ed.doc)?.converged, true)
        XCTAssertEqual(Sketches.freedom("S1", doc: ed.doc), 0)
        BIMUpdaters.run(&ed.doc)
        guard case .solid(let s2)? = ed.doc.entity(pad.id)?.geometry else { return XCTFail() }
        XCTAssertEqual(bounds(s2).size.x, 1500, accuracy: 1e-6)
        XCTAssertEqual(CSG.volume(s2), 1500 * 500 * 300, accuracy: 1)
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: try! JSONEncoder().encode(ed.doc))
        XCTAssertEqual(Sketches.all(back).map(\.name), ["S1"])
    }

    func testVerticalSketchOnLineAndFace() async {
        let ed = Editor()
        let l = ed.doc.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))))
        await ed.run("SKETCHPLANE New V1 Line #\(l)")
        guard let p = Sketches.plane("V1", doc: ed.doc) else { return XCTFail() }
        XCTAssertEqual(p.world(Vec2(0, 2000)).z, 2000, accuracy: 1e-9)
        let r = ed.doc.add(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(1000, 0), Vec2(1000, 2000), Vec2(0, 2000)], closed: true)))
        // Hole: a window-like circle in the panel.
        let c = ed.doc.add(.circle(CircleGeom(Vec2(500, 1000), 200)))
        await ed.run("SKETCHPLANE Add V1 #\(r),#\(c) ")
        await ed.run("SKETCHPAD V1 200")
        guard case .solid(let s)? = ed.doc.entities.last?.geometry else { return XCTFail("no pad") }
        let b = bounds(s)
        XCTAssertEqual(b.min.x, 0, accuracy: 1e-6); XCTAssertEqual(b.max.x, 1000, accuracy: 1e-6)
        XCTAssertEqual(b.max.z, 2000, accuracy: 1e-6)
        XCTAssertEqual(b.size.y, 200, accuracy: 1e-6)
        XCTAssertLessThan(CSG.volume(s), 1000 * 2000 * 200 - 3.0 * 200 * 200 * 200)
        // Sketch on a face of a box: the top face at z = 1000.
        let bx = ed.doc.add(.solid(SolidGeom(kind: .box, origin: Vec3(5000, 0, 0), size: Vec3(1000, 1000, 1000))))
        await ed.run("SKETCHPLANE New T1 Face #\(bx) 5500,500,1000")
        let t = Sketches.plane("T1", doc: ed.doc)!
        XCTAssertEqual(t.origin.z, 1000, accuracy: 1e-6); XCTAssertEqual(t.normal.z, 1, accuracy: 1e-9)
    }
}
