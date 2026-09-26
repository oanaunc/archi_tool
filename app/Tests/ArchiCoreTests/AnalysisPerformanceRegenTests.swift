// Oanarina Archi Tool — GPL-3.0-or-later
// Multithreaded / background regeneration (SYS-017): identical results to the serial mesh builder, and coalescing.
import XCTest
@testable import ArchiCore

final class AnalysisPerformanceRegenTests: XCTestCase {
    func bigModel(_ n: Int) -> ArchiDocument {
        var d = ArchiDocument()
        for i in 0..<n {
            let x = Double(i % 20) * 7000, y = Double(i / 20) * 6000
            let pts = [Vec2(x, y), Vec2(x + 6000, y), Vec2(x + 6000, y + 5000), Vec2(x, y + 5000)]
            var first: EntityID = 0
            for k in 0..<4 {
                let w = d.addElement(.wall(WallGeom(start: pts[k], end: pts[(k + 1) % 4], thickness: 250, height: 3000)))
                if k == 0 { first = w }
            }
            d.addElement(.opening(OpeningGeom(kind: .window, hostWall: first, offset: 2000, width: 1200, height: 1200, sill: 900)))
            d.addElement(.slab(SlabGeom(boundary: pts, thickness: 200)))
            d.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .cylinder, origin: Vec3(x + 3000, y + 2500, 0), size: Vec3(300, 300, 3000)))))
        }
        return d
    }

    func testParallelBuildMatchesSerial() {
        let d = bigModel(120)
        var t = Date()
        let serial = MeshBuilder.build(doc: d)
        let ts = Date().timeIntervalSince(t)
        t = Date()
        let par = ParallelMesh.build(doc: d)
        let tp = Date().timeIntervalSince(t)
        XCTAssertEqual(par.count, serial.count)
        XCTAssertEqual(par, serial, "same groups in the same order")
        XCTAssertEqual(ParallelMesh.build(doc: d, threads: 1), serial)
        // Where the time goes (diagnostics).
        var t0 = Date()
        let prepared = ModelSets.visibleModel(BIMUpdaters.regenerated(d))
        let tPrep = Date().timeIntervalSince(t0); t0 = Date()
        let ctx = BIMContext(doc: prepared)
        let tCtx = Date().timeIntervalSince(t0); t0 = Date()
        var n = 0
        for el in prepared.elements { n += MeshBuilder.groups(el, ctx: ctx).count }
        let tEls = Date().timeIntervalSince(t0)
        print("Regeneration split: prepare \(fmt(tPrep, 3)) s, context \(fmt(tCtx, 3)) s, elements \(fmt(tEls, 3)) s (\(n) groups)")
        print("Mesh regeneration of \(d.elements.count) elements: serial \(fmt(ts, 3)) s, parallel \(fmt(tp, 3)) s on \(ProcessInfo.processInfo.activeProcessorCount) cores")
        _ = tp
    }

    func testBackgroundRegeneratorDeliversTheLatestState() {
        let r = BackgroundRegenerator(deliverOn: DispatchQueue(label: "test.deliver"))
        let docs = (1...5).map { bigModel($0 * 4) }
        let done = expectation(description: "latest delivered")
        let lock = NSLock()
        var delivered: [Int] = [], lastCount = 0
        var last = 0
        for d in docs {
            last = r.request(d) { groups, g in
                lock.lock(); delivered.append(g); if g == 5 { lastCount = groups.count }; lock.unlock()
                if g == 5 { done.fulfill() }
            }
        }
        XCTAssertEqual(last, 5)
        wait(for: [done], timeout: 60)
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(delivered.last, 5)
        XCTAssertEqual(delivered, delivered.sorted(), "never an older state after a newer one")
        XCTAssertEqual(lastCount, MeshBuilder.build(doc: docs[4]).count)
    }

    func testMemoryBudget() async {
        var d = ArchiDocument()
        for i in 0..<5000 { d.add(Entity(layer: "POINTCLOUD", geometry: .point(Vec2(Double(i), 0)), props: ["z": "1", "intensity": "3"])) }
        d.add(Entity(layer: "0", geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: Array(repeating: Vec3(0, 0, 0), count: 30000), meshTriangles: Array(repeating: 0, count: 90000)))))
        let e = MemoryBudget.estimate(d)
        XCTAssertEqual(e.counts["Point clouds"], 5000)
        XCTAssertGreaterThan(e.bytes["3D solids and meshes"] ?? 0, 30000 * 24 + 90000 * 8 - 1)
        XCTAssertGreaterThan(e.total, 0)
        #if os(macOS)
        XCTAssertGreaterThan(MemoryBudget.processFootprint() ?? 0, 1_000_000)
        #endif
        XCTAssertEqual(MemoryBudget.budget(d), Int(ProcessInfo.processInfo.physicalMemory / 4))
        d.setVariable("MEMORYBUDGET", "1")   // 1 MB: over budget
        XCTAssertEqual(MemoryBudget.budget(d), 1_048_576)
        XCTAssertFalse(MemoryBudget.advice(MemoryBudget.estimate(d), budget: MemoryBudget.budget(d)).isEmpty)
        XCTAssertEqual(MemoryBudget.pointLimit(d), 20_000, "no room left: the minimum")
        d.setVariable("POINTLIMIT", "1234")
        XCTAssertEqual(MemoryBudget.pointLimit(d), 1234)
        let ed = await Editor()
        await MainActor.run { ed.doc = d }
        await ed.run("MEMORYREPORT")
        let log = await MainActor.run { ed.log.joined(separator: "\n") }
        XCTAssertTrue(log.contains("Point clouds"), log)
    }

    func testLevelOfDetail() {
        // A finely tessellated sphere.
        let s = SolidGeom(kind: .sphere, origin: .zero, size: Vec3(1000, 1000, 1000))
        var m = MeshTools.mesh(of: s)
        if m.triangleCount < 1000 {
            // Refine by splitting every triangle in four (keeps the test independent of the sphere resolution).
            for _ in 0..<3 {
                var n = Mesh(); let p = m.positions, ix = m.indices
                var i = 0
                while i + 2 < ix.count {
                    let a = p[Int(ix[i])], b = p[Int(ix[i + 1])], c = p[Int(ix[i + 2])]
                    func mid(_ x: Vec3, _ y: Vec3) -> Vec3 { let q = (x + y) * 0.5; return q * (1000 / max(q.length, 1e-9)) }
                    let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
                    for t in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]] { let base = UInt32(n.positions.count); n.positions += t; n.indices += [base, base + 1, base + 2] }
                    i += 3
                }
                m = n
            }
        }
        let lod = MeshLOD.build(MeshGroup(id: 1, kind: "solid", material: "Concrete", mesh: m))
        XCTAssertGreaterThanOrEqual(lod.levels.count, 2)
        for i in 1..<lod.levels.count { XCTAssertLessThan(lod.levels[i].triangleCount, lod.levels[i - 1].triangleCount) }
        XCTAssertEqual(lod.radius, 1000 * 3.0.squareRoot(), accuracy: 60, "bounding sphere of the box around the sphere")
        let fov = 50.0 * .pi / 180
        XCTAssertEqual(MeshLOD.level(for: lod, eye: Vec3(0, -3000, 0), fovY: fov, viewportHeight: 1000), 0, "close: full detail")
        let far = MeshLOD.level(for: lod, eye: Vec3(0, -60_000, 0), fovY: fov, viewportHeight: 1000)
        XCTAssertEqual(far, lod.levels.count - 1, "far: coarsest")
        XCTAssertNil(MeshLOD.level(for: lod, eye: Vec3(0, -5_000_000, 0), fovY: fov, viewportHeight: 1000), "sub-pixel: culled")
        XCTAssertLessThan(MeshLOD.drawnTriangles([lod], eye: Vec3(0, -60_000, 0), fovY: fov, viewportHeight: 1000), m.triangleCount / 3)
        // Small groups keep one level.
        XCTAssertEqual(MeshLOD.build(MeshGroup(id: 2, kind: "solid", material: "x", mesh: MeshTools.mesh(of: SolidGeom(kind: .box, origin: .zero, size: Vec3(1, 1, 1))))).levels.count, 1)
    }
}
