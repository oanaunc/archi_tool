// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the 3D view methods (EngineView3D.swift) for the Windows shell's fixture engine and 3D tests:
// files `view3d-*.json` next to the other fixtures (archi-engine --fixtures). The Cedar House saved cameras (Front,
// Aerial, Corner …), material maps, a section plane with its caps, a door animation and a gizmo move (undone).
import Foundation

extension EngineSession {
    @discardableResult
    public static func writeView3DFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sink = NotificationSink()
        let s = EngineSession(emit: { sink.lines.append($0) })
        s.baseDirectory = sample.deletingLastPathComponent()
        var written: [String] = []
        var nextID = 3000

        func exchange(_ method: String, _ params: EngineJSON) async throws -> EngineJSON {
            var req = EngineObject()
            req.set("jsonrpc", "2.0")
            req.set("id", nextID)
            req.set("method", method)
            req.set("params", params)
            nextID += 1
            sink.lines = []
            let line = await s.handle(line: req.json.serialized) ?? "null"
            s.flushNotifications()
            var o = EngineObject()
            o.set("request", req.json)
            o.set("response", try EngineJSON.parse(line))
            o.set("notifications", EngineJSON.array(try sink.lines.map { try EngineJSON.parse($0) }))
            return o.json
        }
        func save(_ name: String, _ value: EngineJSON) throws {
            try Data((value.serialized + "\n").utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
            written.append(name)
        }
        func params(_ pairs: [(String, EngineJSON)]) -> EngineJSON {
            var o = EngineObject()
            for (k, v) in pairs { o.set(k, v) }
            return o.json
        }

        _ = try await exchange("doc.open", params([("path", .string(sample.path))]))
        try save("view3d-info.json", try await exchange("view3d.info", .object([])))
        let doc = s.editor.doc
        var ext = BBox3.empty
        for g in MeshBuilder.build(doc: doc) { for p in g.mesh.positions { ext.add(p) } }
        let z = ext.isEmpty ? 1200 : ext.min.z + 1200
        let plane = "on;0,0," + fmt(z, 3) + ";0,0,1"
        try save("view3d-setvariable.json", try await exchange("view3d.setVariable", params([("name", .string("SECTIONPLANE")), ("value", .string(plane))])))
        try save("view3d-caps.json", try await exchange("view3d.sectionCaps", .object([])))
        try save("view3d-camera.json", try await exchange("view3d.setCamera", params([("eye", EngineJSON.point3(Vec3(-12000, -18000, 9000))), ("target", EngineJSON.point3(ext.isEmpty ? .zero : ext.center)), ("fov", .number(45))])))
        try save("view3d-sun.json", try await exchange("view3d.sun", params([("day", .int(172)), ("hour", .number(15))])))
        // Render extras (EngineRenderExtras.swift): the AO dialog's settings and a render prompt's preset.
        try save("render-ao.json", try await exchange("render.ao", .object([])))
        try save("render-prompt-settings.json", try await exchange("render.promptSettings", params([("text", .string("golden hour, soft shadows, warm, 4K"))])))
        // A door animation (ANIMATE Door) so the info carries door leaves; a gizmo move of the door, undone.
        if let door = doc.elements.first(where: { e in if case .opening(let o) = e.geometry { return o.kind == .door && (o.doorStyle == .single || o.doorStyle == .double) }; return false }) {
            var anims: [EngineAnimation] = []
            for (i, l) in EngineDoorLeaves.leaves(door, doc: doc).enumerated() {
                anims.append(EngineAnimation(id: i + 1, target: door.id, kind: "Door", pivot: Vec3(l.hinge.x, l.hinge.y, 0), angle: 90 * l.sign,
                                             offset: .zero, start: 0, duration: 2, pingPong: true, name: "Door " + String(door.id) + (i > 0 ? " leaf 2" : "")))
            }
            s.editor.transaction("ANIMATE") { EngineAnimations.store(anims, in: &$0) }
            try save("view3d-info-animated.json", try await exchange("view3d.info", .object([])))
            try save("view3d-transform.json", try await exchange("view3d.transform", params([("op", .string("move")), ("axis", .int(0)), ("amount", .number(250)), ("ids", .ints([door.id]))])))
            _ = try await exchange("edit.undo", .object([]))
            _ = try await exchange("edit.undo", .object([]))
            _ = try await exchange("select.set", params([("ids", .array([]))]))
        }
        _ = try await exchange("view3d.setVariable", params([("name", .string("SECTIONPLANE")), ("value", .null)]))
        // Binary mesh transfer: one temporary buffer file (the path and layout; the file itself is not kept).
        let bin = try await exchange("model.meshes", params([("level", .string("all")), ("lod", .int(2)), ("binary", .bool(true))]))
        if let p = bin["response"]?["result"]?["binary"]?.stringValue { try? FileManager.default.removeItem(atPath: p) }
        var slim = EngineObject()
        slim.set("request", bin["request"] ?? .null)
        var r = EngineObject()
        for key in ["binary", "binaryLength", "layout", "units", "bounds"] { r.set(key, bin["response"]?["result"]?[key] ?? .null) }
        r.set("meshCount", bin["response"]?["result"]?["meshes"]?.arrayValue?.count ?? 0)
        r.set("firstMesh", bin["response"]?["result"]?["meshes"]?[0] ?? .null)
        var resp = EngineObject()
        resp.set("jsonrpc", "2.0")
        resp.set("id", bin["response"]?["id"] ?? .null)
        resp.set("result", r.json)
        slim.set("response", resp.json)
        slim.set("notifications", .array([]))
        try save("view3d-meshes-binary.json", slim.json)
        // Full detail (the Cedar House trees are ~1.1 M triangles) as one buffer file beside the fixtures, for the 3D
        // render comparisons with the Mac (windows/test/view3d/run.mjs --full); the .bin is not listed in index.json.
        let full = try await exchange("model.meshes", params([("level", .string("all")), ("lod", .int(0)), ("binary", .string(dir.appendingPathComponent("view3d-meshes-lod0.bin").path))]))
        try Data((full.serialized + "\n").utf8).write(to: dir.appendingPathComponent("view3d-meshes-lod0.json"), options: .atomic)
        return written
    }
}
