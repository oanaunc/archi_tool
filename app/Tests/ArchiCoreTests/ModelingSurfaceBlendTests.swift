// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Blend surfaces with G0/G1/G2 continuity (M3D-067) and surface analysis (M3D-074).
@MainActor
final class ModelingSurfaceBlendTests: XCTestCase {
    func plane(x0: Double, x1: Double, z: Double) -> SurfaceBlend.IM {
        let rows: [[Vec3]] = (0...4).map { (i: Int) -> [Vec3] in
            let x: Double = x0 + (x1 - x0) * Double(i) / 4
            return (0...4).map { (j: Int) -> Vec3 in Vec3(x, 1000 * Double(j) / 4, z) }
        }
        return SurfaceBlend.mesh(rows)
    }
    func add(_ ed: Editor, _ m: SurfaceBlend.IM) -> EntityID {
        var e = Entity(geometry: .solid(SubObjects.solidGeom(m))); e.props["surface"] = "Test"
        return ed.doc.add(e)
    }

    func testBlendContinuity() async {
        let a = plane(x0: 0, x1: 1000, z: 0), b = plane(x0: 2000, x1: 3000, z: 500)
        guard let ea = SurfaceBlend.nearestEdge(a, to: Vec3(1000, 500, 0)), let eb = SurfaceBlend.nearestEdge(b, to: Vec3(2000, 500, 500)) else { return XCTFail() }
        XCTAssertEqual(ea.outward[ea.outward.count / 2].x, 1, accuracy: 1e-9)
        XCTAssertEqual(eb.outward[eb.outward.count / 2].x, -1, accuracy: 1e-9)
        for c in SurfaceBlend.Continuity.allCases {
            let rows = SurfaceBlend.blendGrid(ea, eb, continuity: c, n: 8, m: 64)!
            for r in rows {
                // G0: the blend starts on edge A and ends on edge B.
                XCTAssertEqual(r[0].x, 1000, accuracy: 1e-9); XCTAssertEqual(r[0].z, 0, accuracy: 1e-9)
                XCTAssertEqual(r.last!.x, 2000, accuracy: 1e-9); XCTAssertEqual(r.last!.z, 500, accuracy: 1e-9)
                let t0 = (r[1] - r[0]).normalized, t1 = (r[r.count - 1] - r[r.count - 2]).normalized
                if c != .g0 {
                    // G1: leaves A and enters B along their tangent planes (horizontal, +x).
                    XCTAssertGreaterThan(t0.dot(Vec3(1, 0, 0)), cos(2.5 * .pi / 180))
                    XCTAssertGreaterThan(t1.dot(Vec3(1, 0, 0)), cos(2.5 * .pi / 180))
                }
            }
            let r = SurfaceBlend.blendGrid(ea, eb, continuity: c, n: 2, m: 512)![1]
            let second = (r[0] - r[1] * 2 + r[2]).length
            if c == .g2 { XCTAssertLessThan(second, 0.001) }   // zero curvature at the flat edge
            if c == .g1 { XCTAssertGreaterThan(second, 0.005) }
        }
        let g1 = SurfaceBlend.mesh(SurfaceBlend.blendGrid(ea, eb, continuity: .g1, n: 8, m: 64)!)
        let cont = SurfaceBlend.continuity(a, g1, near: Vec3(1000, 500, 0))!
        XCTAssertLessThan(cont.gap, 1e-6)
        XCTAssertLessThan(cont.angle, 3)
    }

    func testBlendCommand() async {
        let ed = Editor()
        let a = add(ed, plane(x0: 0, x1: 1000, z: 0)), b = add(ed, plane(x0: 2000, x1: 3000, z: 500))
        await ed.run("SURFBLEND #\(a) 1000,500,0 #\(b) 2000,500,500 G2 1")
        guard let e = ed.doc.entities.last, e.props["blendOf"] == "\(a),\(b)", case .solid(let s) = e.geometry else { return XCTFail("no blend") }
        XCTAssertEqual(s.meshVertices.count, 17 * 9)
        XCTAssertEqual(e.props["blendContinuity"], "G2")
    }

    func testCurvatureOfSphere() async {
        let r = 500.0
        guard let s = SolidPrimitives.meshSphere(center: .zero, radius: r, segments: 48) else { return XCTFail() }
        let w = SolidOps.welded(s)
        let c = SurfaceBlend.vertexCurvature((w.vertices, w.triangles))
        let mean = c.mean.compactMap { $0 }.sorted(), gauss = c.gaussian.compactMap { $0 }.sorted()
        XCTAssertFalse(mean.isEmpty)
        XCTAssertEqual(mean[mean.count / 2], 1 / r, accuracy: 0.05 / r)
        XCTAssertEqual(gauss[gauss.count / 2], 1 / (r * r), accuracy: 0.05 / (r * r))
        // Total Gaussian curvature of a closed sphere is 4π (Gauss–Bonnet).
        XCTAssertEqual(SurfaceBlend.draftAngles((w.vertices, w.triangles), pull: .unitZ).count, w.triangles.count / 3)
    }

    func testDraftZebraAndClear() async {
        let ed = Editor()
        let b = ed.doc.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))))
        await ed.run("SURFANALYSIS Draft #\(b) 0,0,1 3")
        let over = ed.doc.entities.filter { $0.props["analysisOf"] == "\(b)" }
        XCTAssertEqual(Set(over.compactMap { $0.props["material"] }), ["Analysis Draft OK", "Analysis Draft Low", "Analysis Undercut"])
        func area(_ mat: String) -> Double {
            over.filter { $0.props["material"] == mat }.reduce(0.0) { acc, e in
                guard case .solid(let s) = e.geometry else { return acc }
                return acc + (0..<(s.meshTriangles.count / 3)).reduce(0.0) { a2, f in
                    let p = (0..<3).map { s.meshVertices[s.meshTriangles[3 * f + $0]] }
                    return a2 + (p[1] - p[0]).cross(p[2] - p[0]).length / 2 }
            }
        }
        XCTAssertEqual(area("Analysis Draft OK"), 1e6, accuracy: 1)
        XCTAssertEqual(area("Analysis Draft Low"), 4e6, accuracy: 1)
        XCTAssertEqual(area("Analysis Undercut"), 1e6, accuracy: 1)
        XCTAssertNotNil(ed.doc.material("Analysis Undercut"))
        await ed.run("SURFANALYSIS Zebra #\(b) 30")
        XCTAssertFalse(ed.doc.entities.filter { $0.props["analysisOf"] == "\(b)" }.isEmpty)
        XCTAssertTrue(ed.doc.entities.filter { $0.props["analysisOf"] == "\(b)" }.allSatisfy { $0.props["material"]?.hasPrefix("Analysis Zebra") == true })
        XCTAssertFalse(MeshBuilder.build(doc: ed.doc).filter { $0.material.hasPrefix("Analysis Zebra") }.isEmpty)
        await ed.run("SURFANALYSIS Clear")
        XCTAssertTrue(ed.doc.entities.allSatisfy { $0.props["analysisOf"] == nil })
    }
}
