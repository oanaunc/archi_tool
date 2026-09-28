// Oanarina Archi Tool — GPL-3.0-or-later
// ANIMATE Frame on Windows: the portable path tracer places animated objects and swinging door leaves at the frame
// time, as ArchiApp/PathTracerUI.swift PTSceneBuilder.build (Host/EnginePathTraceAnimation.swift).
import XCTest
@testable import ArchiCore

final class EnginePathTraceAnimationTests: XCTestCase {
    static var cedarHouse: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../assets/demo/Cedar House.archi").standardized
    }

    func testProgressAndRotationMatchTheMac() {
        var a = EngineObjectAnimation()
        a.kind = "Rotate"; a.pivot = Vec3(1000, 0, 0); a.angle = 90; a.start = 1; a.duration = 2; a.pingPong = true
        XCTAssertEqual(a.progress(at: 0), 0)
        XCTAssertEqual(a.progress(at: 2), 0.5, accuracy: 1e-12)
        XCTAssertEqual(a.progress(at: 3), 1, accuracy: 1e-12)
        XCTAssertEqual(a.progress(at: 4), 0.5, accuracy: 1e-12)
        XCTAssertEqual(a.progress(at: 5.5), 0)
        let p = a.apply(Vec3(2000, 0, 300), at: 3)
        XCTAssertEqual(p.x, 1000, accuracy: 1e-9)
        XCTAssertEqual(p.y, 1000, accuracy: 1e-9)
        XCTAssertEqual(p.z, 300)
        a.pingPong = false; a.kind = "Move"; a.angle = 0; a.offset = Vec3(0, 0, 500)
        XCTAssertEqual(a.apply(Vec3(0, 0, 0), at: 10).z, 500, accuracy: 1e-9)
        var d = EngineDoorLeaves.Leaf(hinge: Vec2(0, 0), sign: 1, s0: 0, s1: 900, cs: Vec2(0, 0), dir: Vec2(1, 0), normal: Vec2(0, 1), wallHalf: 100)
        d.wallHalf = 100
        var m = Mesh()
        m.positions = [Vec3(10, 0, 0), Vec3(800, 0, 0), Vec3(10, 0, 2000), Vec3(10, 99.9, 0), Vec3(800, 99.9, 0), Vec3(10, 99.9, 2000)]
        m.indices = [0, 1, 2, 3, 4, 5]
        let s = EngineObjectAnimation.splitDoor(m, leaves: [d])
        XCTAssertEqual(s.leaves[0].indices.count, 3)   // the leaf between the wall faces
        XCTAssertEqual(s.rest.indices.count, 3)        // triangles touching a wall face stay with the frame
    }

    @MainActor func testAnimateFrameSwingsTheDoorInThePathTracer() async throws {
        guard FileManager.default.fileExists(atPath: Self.cedarHouse.path) else { throw XCTSkip("demo model not found") }
        let s = EngineSession()
        _ = try await s.call("doc.open", EngineJSON.object([EngineJSONField("path", .string(Self.cedarHouse.path))]))
        var doc = s.editor.doc
        // Every swing door of the sample opens (as ANIMATE Door on all of them).
        let doors = doc.elements.filter { !EngineDoorLeaves.leaves($0, doc: doc).isEmpty }
        if doors.isEmpty { throw XCTSkip("no swing door") }
        var items: [String] = []
        for (k, door) in doors.enumerated() {
            let leaf = EngineDoorLeaves.leaves(door, doc: doc)[0]
            let angle: Double = 90 * leaf.sign
            let hx = String(leaf.hinge.x), hy = String(leaf.hinge.y), target = String(door.id), ang = String(angle), id = String(k + 1)
            let parts: [String] = ["{\"id\":", id, ",\"target\":", target, ",\"kind\":\"Door\",\"pivot\":{\"x\":", hx, ",\"y\":", hy,
                                   ",\"z\":0},\"angle\":", ang, ",\"start\":0,\"duration\":2,\"pingPong\":false}"]
            items.append(parts.joined())
        }
        let json = "[" + items.joined(separator: ",") + "]"
        doc.setVariable("OBJANIM", json)
        // Diagnostics: the animations parse and each door has a mesh group of its own material that splits into leaves.
        let anims = EngineObjectAnimation.load(doc)
        XCTAssertEqual(anims.count, doors.count, json)
        var leafTriangles = 0
        var seen: [String] = []
        for g in MeshBuilder.build(doc: doc) where g.id != nil && doors.contains(where: { $0.id == g.id }) {
            let el = doc.element(g.id!)!
            seen.append(String(g.id!) + ":" + g.material + "/" + (el.material ?? "nil"))
            if let parts = EngineObjectAnimation.meshes(g.mesh, group: g, anims: anims, doc: doc, time: 2), parts.count > 1 {
                for p in parts.dropFirst() { leafTriangles += p.indices.count / 3 }
            }
        }
        XCTAssertGreaterThan(leafTriangles, 0, seen.joined(separator: ", "))
        func checksum(_ t: Double) -> (Int, Double) {
            var o = EPTSceneBuilder.Options()
            o.lod = 0   // full detail: the simplified levels do not keep the leaf apart from the frame
            o.time = t
            let (sc, _) = EPTSceneBuilder.build(doc: doc, camera: nil, options: o)
            var sum = 0.0
            // X alone: a quarter turn about the hinge moves x by the distance along the leaf (x + y would cancel).
            for tri in sc.tris { sum += Double(tri.p0.x) * 1e-3 }
            XCTAssertEqual(sc.time, Float(t))
            return (sc.tris.count, sum)
        }
        let closed = checksum(0), open = checksum(2), still = checksum(0)
        XCTAssertEqual(closed.0, open.0)                        // the same triangles …
        XCTAssertGreaterThan(abs(closed.1 - open.1), 1e-3)      // … with the leaf swung open at 2 s
        XCTAssertEqual(closed.1, still.1, accuracy: 1e-9)
    }
}
