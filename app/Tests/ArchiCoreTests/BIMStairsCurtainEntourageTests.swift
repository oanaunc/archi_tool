// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

@MainActor
final class BIMStairsCurtainEntourageTests: XCTestCase {
    func area(_ p: [Vec2]) -> Double { abs(GeometryOps.signedArea(p)) }

    func testLShapeWindersFillTheCornerSquare() {
        let g = StairGeom(start: .zero, direction: 0, width: 1000, totalRise: 3000, riserCount: 17, treadDepth: 280, kind: .lShape, winders: 3)
        let l = StairShapes.layout(g)
        XCTAssertEqual(l.treads.count, 16)
        let w = l.treads.filter(\.winder)
        XCTAssertEqual(w.count, 3)
        XCTAssertFalse(l.treads.contains { $0.landing })
        XCTAssertEqual(w.map { area($0.poly) }.reduce(0, +), 1000 * 1000, accuracy: 1e-6)
        XCTAssertEqual(Set(l.treads.map(\.step)), Set(1...16))
        XCTAssertEqual(l.newels.count, 1)
        // Pivot at the inner corner (x1, +w/2) of a left turn.
        let n1 = (16 - 3) / 2
        XCTAssertTrue(l.newels[0].isClose(Vec2(Double(n1) * 280, 500), tol: 1e-6))
        // Walk line ends at the top of the second flight.
        let n2 = 16 - n1 - 3
        XCTAssertTrue(l.walk.last!.isClose(Vec2(Double(n1) * 280 + 500, 500 + Double(n2) * 280), tol: 1e-6))
    }

    func testUShapeWindersAndRightHand() {
        let g = StairGeom(start: .zero, direction: 0, width: 1000, totalRise: 3200, riserCount: 18, treadDepth: 280, kind: .uShape, winders: 6, clockwise: true)
        let l = StairShapes.layout(g)
        let w = l.treads.filter(\.winder)
        XCTAssertEqual(w.count, 6)
        XCTAssertEqual(w.map { area($0.poly) }.reduce(0, +), 1000 * 2100, accuracy: 1e-6)   // landing 1000 deep × (2w + gap)
        // Turning right: the second flight lies on the −Y side.
        let last = l.treads.max { $0.step < $1.step }!
        XCTAssertLessThan(GeometryOps.centroid(last.poly).y, 0)
        XCTAssertEqual(l.treads.count, 17)
    }

    func testWinderRulesAndSpiralHeadroom() {
        let narrow = StairGeom(start: .zero, width: 1000, totalRise: 3000, riserCount: 17, treadDepth: 280, kind: .lShape, winders: 3)
        XCTAssertTrue(BIMConstraints.stairIssues(narrow).contains { $0.contains("Winder going") })
        let wide = StairGeom(start: .zero, width: 1200, totalRise: 3000, riserCount: 17, treadDepth: 280, kind: .lShape, winders: 2)
        XCTAssertFalse(BIMConstraints.stairIssues(wide).contains { $0.contains("Winder going") }, "\(BIMConstraints.stairIssues(wide))")
        let tight = StairGeom(start: .zero, width: 800, totalRise: 3000, riserCount: 17, treadDepth: 220, kind: .spiral, innerRadius: 20)
        let issues = BIMConstraints.stairIssues(tight)
        XCTAssertTrue(issues.contains { $0.contains("headroom") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.contains("column") }, "\(issues)")
        // Clockwise spiral winds the other way.
        let ccw = StairShapes.layout(StairGeom(start: .zero, width: 800, riserCount: 5, treadDepth: 250, kind: .spiral))
        let cw = StairShapes.layout(StairGeom(start: .zero, width: 800, riserCount: 5, treadDepth: 250, kind: .spiral, clockwise: true))
        XCTAssertGreaterThan(GeometryOps.centroid(ccw.treads[3].poly).y, 0)
        XCTAssertLessThan(GeometryOps.centroid(cw.treads[3].poly).y, 0)
    }

    func testStairCommandWindersPlanAnd3D() async {
        let ed = Editor()
        let log = await ed.run("STAIR Kind LShape Winders 3 Hand Right 0,0 0")
        guard case .stair(let s)? = ed.doc.elements.last?.geometry else { return XCTFail(log.joined(separator: "\n")) }
        XCTAssertEqual(s.winders, 3); XCTAssertEqual(s.clockwise, true); XCTAssertEqual(s.kind, .lShape)
        let el = ed.doc.elements.last!
        let items = PlanRepresentation.items(el, doc: ed.doc)
        XCTAssertGreaterThan(items.count, 16)
        let groups = MeshBuilder.groups(for: el, doc: ed.doc)
        XCTAssertFalse(groups.isEmpty)
        let top = groups.map { $0.mesh.bounds.max.z }.max()!
        XCTAssertGreaterThan(top, 2500)
        // Round-trip through JSON keeps the new fields; old files without them still decode.
        let data = try! JSONEncoder().encode(ed.doc)
        let back = try! JSONDecoder().decode(ArchiDocument.self, from: data)
        XCTAssertEqual(back.elements.last, el)
        let old = #"{"type":"stair","start":{"x":0,"y":0},"direction":0,"width":1000,"totalRise":3000,"riserCount":17,"treadDepth":280,"kind":"lShape"}"#
        guard case .stair(let o) = try! JSONDecoder().decode(BIMGeometry.self, from: Data(old.utf8)) else { return XCTFail() }
        XCTAssertNil(o.winders); XCTAssertEqual(o.winderCount, 0)
    }

    func testSpiralStairHasColumnAndHandrail() {
        var doc = ArchiDocument()
        doc.addElement(.stair(StairGeom(start: .zero, width: 900, totalRise: 2800, riserCount: 16, treadDepth: 230, kind: .spiral, innerRadius: 150)))
        let groups = MeshBuilder.build(doc: doc)
        XCTAssertTrue(groups.contains { $0.material == "Steel" })
        let b = groups.reduce(BBox3.empty) { var r = $0; r.add($1.mesh.bounds.min); r.add($1.mesh.bounds.max); return r }
        XCTAssertEqual(b.max.x, 150 + 900, accuracy: 30)
    }

    func testCurtainWallMullionTypes() {
        var doc = ArchiDocument()
        let g = CurtainWallGeom(start: .zero, end: Vec2(3600, 0), height: 3000, gridU: 1200, gridV: 1500, mullionSize: 60, mullionProfile: "fin", borderProfile: "capped")
        let id = doc.addElement(.curtainWall(g))
        XCTAssertEqual(CurtainMullion.section("fin", width: 60, depth: 90).count, 8)
        XCTAssertEqual(CurtainMullion.section("round", width: 60, depth: 90).count, 20)
        let el = doc.element(id)!
        let fills = PlanRepresentation.items(el, doc: doc).compactMap { it -> [Vec2]? in if case .fill(let l, _) = it { return l[0] }; return nil }
        XCTAssertEqual(fills.count, 4)
        // Interior fin projects 1.5 × depth beyond the exterior (−Y) face; border caps stay within the wall length.
        XCTAssertEqual(fills[1].map(\.y).min()!, -45 - 135, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(fills[0].map(\.x).min()!, -1e-6)
        XCTAssertLessThanOrEqual(fills[3].map(\.x).max()!, 3600 + 1e-6)
        var cw = g; cw.panels = ["0,0": "spandrel", "1,1": "louvre"]
        doc.elements[0].geometry = .curtainWall(cw)
        let groups = MeshBuilder.build(doc: doc)
        XCTAssertTrue(groups.contains { $0.material == "Steel" })            // spandrel back-pan
        let frame = groups.first { $0.material == "Aluminium" }!
        XCTAssertLessThan(frame.mesh.bounds.min.y, -150)
        XCTAssertGreaterThan(MeshTools.signedVolume(frame.mesh), 0)
        // Codable round trip.
        let back = try! JSONDecoder().decode(BIMGeometry.self, from: try! JSONEncoder().encode(BIMGeometry.curtainWall(cw)))
        XCTAssertEqual(back, .curtainWall(cw))
    }

    func testEntouragePeopleAndBicycle() {
        XCTAssertEqual(ComponentLibrary.family("Person")?.id, "person-standing")
        XCTAssertEqual(ComponentLibrary.family("bike")?.id, "bicycle")
        for id in ["person-standing", "person-walking", "person-child", "bicycle"] {
            let f = ComponentLibrary.family(id)!
            let g = ComponentGeom(category: f.category, position: Vec2(1000, 2000), size: f.size, family: f.id)
            let groups = ComponentLibrary.meshGroups(f, g, id: 1, z0: 0, overrides: [:])
            XCTAssertFalse(groups.isEmpty, id)
            var b = BBox3.empty
            for gr in groups { b.add(gr.mesh.bounds.min); b.add(gr.mesh.bounds.max) }
            XCTAssertEqual(b.max.z, f.size.z, accuracy: f.size.z * 0.06, id)
            XCTAssertGreaterThan(b.min.z, -1, id)
            XCTAssertEqual((b.min.x + b.max.x) / 2, 1000, accuracy: f.size.x * 0.25, id)
            XCTAssertFalse(ComponentLibrary.symbol(f, size: f.size).isEmpty, id)
        }
        let walk = ComponentLibrary.family("person-walking")!
        XCTAssertEqual(ComponentLibrary.symbol(walk, size: walk.size).count, 5)
    }
}
