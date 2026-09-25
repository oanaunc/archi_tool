// Oanarina Archi Tool — GPL-3.0-or-later
// LAS import (IO-049), octree LOD / clipping (IO-051), snapping and plane fit (IO-052), scan to BIM (IO-053).
import XCTest
@testable import ArchiCore

final class IOPointCloudToolsTests: XCTestCase {
    /// A 5 × 4 m room scanned every 100 mm (metres): four walls 2.8 m high and the floor.
    static func room(step: Double = 0.1) -> [Vec3] {
        var p: [Vec3] = []
        var z = 0.05
        while z < 2.8 {
            var x = 0.0; while x <= 5.0 + 1e-9 { p.append(Vec3(x, 0, z)); p.append(Vec3(x, 4, z)); x += step }
            var y = step; while y < 4.0 - 1e-9 { p.append(Vec3(0, y, z)); p.append(Vec3(5, y, z)); y += step }
            z += step
        }
        var x = step; while x < 5 - 1e-9 { var y = step; while y < 4 - 1e-9 { p.append(Vec3(x, y, 0)); y += step }; x += step }
        return p
    }

    func testLASRoundTripWithColourIntensityAndScale() throws {
        let pts = [CloudPoint(Vec3(426_000.125, 4_919_000.5, 80.25), color: (255, 128, 0), intensity: 300), CloudPoint(Vec3(426_010, 4_919_002, 81), color: (0, 0, 255), intensity: 12)]
        let data = LASReader.write(pts)
        let r = try LASReader.read(data)
        XCTAssertEqual(r.header.pointFormat, 2); XCTAssertEqual(r.header.pointCount, 2)
        XCTAssertEqual(r.points[0].p.x, 426_000.125, accuracy: 1e-6); XCTAssertEqual(r.points[0].p.y, 4_919_000.5, accuracy: 1e-6)
        XCTAssertEqual(r.points[1].p.z, 81, accuracy: 1e-6)
        XCTAssertEqual(r.points[0].color?.0, 255); XCTAssertEqual(r.points[0].color?.1, 128)
        XCTAssertEqual(r.points[1].intensity, 12)
        XCTAssertEqual(r.classes, [2, 2])
        // Through the importer: millimetres.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).las")
        try data.write(to: url)
        let (doc, summary) = try FileImport.load(url)
        XCTAssertTrue(summary.contains("2 of 2 LAS points"), summary)
        guard case .point(let p) = doc.entities[0].geometry else { return XCTFail() }
        XCTAssertEqual(p.x, 426_000_125, accuracy: 1e-3)
        XCTAssertEqual(doc.entities[0].props["class"], "2")
        var laz = [UInt8](data); laz[104] |= 0x80
        XCTAssertThrowsError(try LASReader.read(Data(laz))) { XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("LAZ") ?? false) }
        XCTAssertThrowsError(try LASReader.read(Data("nope".utf8)))
    }

    func testOctreeLODClippingAndNearest() {
        let pts = Self.room()
        let oct = PointOctree(points: pts, capacity: 64)
        XCTAssertGreaterThan(oct.depth, 2)
        let lod = oct.lod(budget: 2000)
        XCTAssertLessThanOrEqual(lod.count, 2000); XCTAssertGreaterThan(lod.count, 1000)
        XCTAssertEqual(Set(lod).count, lod.count)
        // LOD points spread over the whole room.
        var b = BBox3.empty; for i in lod { b.add(pts[i]) }
        XCTAssertLessThan(b.min.x, 0.5); XCTAssertGreaterThan(b.max.x, 4.5)
        let box = BBox3(min: Vec3(1, -0.1, 1), max: Vec3(2, 0.1, 2))
        let inBox = Set(oct.points(in: box))
        XCTAssertEqual(inBox, Set(pts.indices.filter { PointOctree.contains(box, pts[$0]) }))
        XCTAssertTrue(oct.lod(clip: box, budget: 10_000).allSatisfy { PointOctree.contains(box, pts[$0]) })
        XCTAssertEqual(Set(oct.lod(clip: box, budget: 10_000)), inBox, "a large budget returns every clipped point")
        for q in [Vec3(2.53, 0.04, 1.2), Vec3(4.9, 2, 2.7), Vec3(-3, -3, 0)] {
            let best = pts.indices.min { pts[$0].distance(to: q) < pts[$1].distance(to: q) }!
            XCTAssertEqual(oct.nearest(to: q)?.distance ?? -1, pts[best].distance(to: q), accuracy: 1e-12)
        }
    }

    func testPlaneFitAndRansac() throws {
        let wall = (0..<200).map { i in Vec3(Double(i % 20) * 0.1, 0.002 * Double(i % 3), Double(i / 20) * 0.1) }
        let pl = try XCTUnwrap(PlaneFit.fit(wall))
        XCTAssertEqual(abs(pl.normal.y), 1, accuracy: 1e-3)
        XCTAssertTrue(pl.isVertical)
        XCTAssertLessThan(pl.rms, 0.002)
        let planes = PlaneFit.detect(Self.room(step: 0.2), tolerance: 0.02, minInliers: 50)
        XCTAssertEqual(planes.count, 5, "four walls and the floor")
    }

    @MainActor func testScanToBIMCreatesWallsAndFloor() async throws {
        let ed = Editor()
        var d = ArchiDocument()
        d.entities = PointCloud.entities(Self.room(step: 0.2).map { CloudPoint($0) }, options: PointCloudOptions(scale: 1000))
        d.nextID = d.entities.count + 10
        for i in d.entities.indices { d.entities[i].id = i + 1 }
        ed.doc = d
        await ed.run("SCANTOBIM 20 50 200")
        let walls = ed.doc.elements.compactMap { el -> WallGeom? in if case .wall(let w) = el.geometry { return w }; return nil }
        let slabs = ed.doc.elements.filter { $0.typeName == "slab" }
        XCTAssertEqual(walls.count, 4); XCTAssertEqual(slabs.count, 1)
        let lengths = walls.map(\.length).sorted()
        XCTAssertEqual(lengths[0], 3600, accuracy: 250); XCTAssertEqual(lengths[3], 5000, accuracy: 50)
        XCTAssertEqual(walls[0].height, 2600, accuracy: 250)
        if case .slab(let s) = slabs[0].geometry { XCTAssertEqual(abs(GeometryOps.signedArea(s.boundary)), 4.6e6 * 3.6, accuracy: 2e6) }
        ed.undo()
        XCTAssertTrue(ed.doc.elements.isEmpty)
        // Clip and density.
        await ed.run("POINTCLOUDVIEW Clip 0,0 5000,100 0 3000")
        let shown = ed.doc.entities.filter { $0.layer != PointCloudCommands.hiddenLayer }.count
        XCTAssertGreaterThan(shown, 100); XCTAssertLessThan(shown, ed.doc.entities.count / 2)
        XCTAssertEqual(ed.doc.layer(named: PointCloudCommands.hiddenLayer)?.visible, false)
        await ed.run("POINTCLOUDVIEW Density 500")
        XCTAssertLessThanOrEqual(ed.doc.entities.filter { $0.layer != PointCloudCommands.hiddenLayer }.count, 500)
        await ed.run("POINTCLOUDVIEW Reset")
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == PointCloudCommands.hiddenLayer }.count, 0)
        let out = await ed.run("PCPLANE 2500,30 300")
        XCTAssertTrue(out.joined().contains("from horizontal"), out.joined(separator: "\n"))
        XCTAssertEqual(ed.doc.entities.last?.layer, "PC-PLANES", "a vertical plane is traced")
    }
}
