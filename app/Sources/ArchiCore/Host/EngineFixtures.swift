// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded engine exchanges for the Windows shell's tests and mock engine (archi-engine --fixtures <dir>): each file
// holds a real request, the engine's response and the notifications sent while answering it.
import Foundation

extension EngineSession {
    /// Writes the fixture files for `sample` (the Cedar House demo) into `dir`. Returns the file names written.
    @discardableResult
    public static func writeFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sink = NotificationSink()
        let s = EngineSession(emit: { sink.lines.append($0) })
        s.baseDirectory = sample.deletingLastPathComponent()
        var written: [String] = []
        var nextID = 1

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

        try save("hello.json", try await exchange("engine.hello", .object([])))
        try save("doc-open.json", try await exchange("doc.open", params([("path", .string(sample.path))])))
        let info = try await exchange("doc.info", .object([]))
        try save("doc-info.json", info)
        // The plan of the current level framed on its extents at 0.05 px/mm (a 1:20 000-ish overview).
        let ext = info["response"]?["result"]?["extents"] ?? EngineJSON.numbers([0, 0, 10000, 10000])
        try save("drawlist-cedar.json", try await exchange("view.drawList", params([("rect", ext), ("pixelsPerUnit", .number(0.05))])))
        let doc = s.editor.doc
        for l in doc.levels where l.id != doc.currentLevel {
            let name = "drawlist-level-\(l.id).json"
            try save(name, try await exchange("view.drawList", params([("level", .int(l.id)), ("pixelsPerUnit", .number(0.05))])))
        }
        // A sheet with a plan viewport (added for the recording when the sample has none, then undone).
        var addedViewport = false
        if !doc.layouts.contains(where: { !$0.viewports.isEmpty }), !doc.layouts.isEmpty {
            let e = s.extents()
            let c = e.isEmpty ? Vec2(0, 0) : e.center
            let vp = Viewport(origin: Vec2(15, 25), size: Vec2(300, 257), viewCenter: c, scale: 200, view: .plan, level: doc.currentLevel, title: "Ground Floor Plan")
            s.editor.transaction("Fixture Viewport") { $0.layouts[0].viewports.append(vp) }
            addedViewport = true
        }
        if let first = s.editor.doc.layouts.first(where: { !$0.viewports.isEmpty }) ?? s.editor.doc.layouts.first {
            try save("drawlist-sheet.json", try await exchange("view.drawList", params([("layout", .string(first.name)), ("pixelsPerUnit", .number(2))])))
        }
        if addedViewport { s.editor.undo() }
        // All levels at LOD 2 (the full-detail trees alone are ~160 MB of base64), and the current level at full detail.
        try save("meshes-all-lod2.json", try await exchange("model.meshes", params([("level", .string("all")), ("lod", .int(2))])))
        try save("meshes-level-\(doc.currentLevel).json", try await exchange("model.meshes", params([("level", .int(doc.currentLevel))])))
        try save("render-settings.json", try await exchange("render.settings", .object([])))
        var presets: [EngineJSON] = []
        for k in EngineRenderPresets.keywords { presets.append(try await exchange("render.preset", params([("name", .string(k))]))) }
        presets.append(try await exchange("render.preset", params([("name", .string("Daylight"))])))
        try save("render-presets.json", .array(presets))
        for p in ["layers", "levels", "properties", "materials", "sheets", "history"] {
            try save("panel-\(p).json", try await exchange("panel." + p, .object([])))
        }
        // A wall selected: properties, grips and the selection summary.
        if let wall = doc.elements.first(where: { $0.typeName == "wall" && $0.level == doc.currentLevel }) {
            try save("select-set.json", try await exchange("select.set", params([("ids", .ints([wall.id]))])))
            try save("panel-properties-wall.json", try await exchange("panel.properties", .object([])))
            try save("grips-get.json", try await exchange("grips.get", .object([])))
            _ = try await exchange("select.set", params([("ids", .array([]))]))
        }
        try save("sysvar-get.json", try await exchange("sysvar.get", params([("name", .string("OSMODE"))])))
        // LINE: start, first point, cursor preview, second point, Enter (every prompt state the command line shows).
        let b = s.extents()
        let y = b.isEmpty ? -2000 : b.min.y - 2000
        let x0 = b.isEmpty ? 0 : b.min.x
        var seq: [EngineJSON] = []
        seq.append(try await exchange("command.run", params([("line", .string("LINE"))])))
        seq.append(try await exchange("input.cursor", params([("x", .number(x0)), ("y", .number(y)), ("pixelsPerUnit", .number(0.05))])))
        seq.append(try await exchange("input.point", params([("x", .number(x0)), ("y", .number(y)), ("snap", .bool(false))])))
        seq.append(try await exchange("input.cursor", params([("x", .number(x0 + 4000)), ("y", .number(y + 1500))])))
        seq.append(try await exchange("input.point", params([("x", .number(x0 + 4000)), ("y", .number(y)), ("snap", .bool(false))])))
        seq.append(try await exchange("input.text", params([("text", .string("@0,1500"))])))
        seq.append(try await exchange("input.key", params([("key", .string("Enter"))])))
        seq.append(try await exchange("edit.undo", .object([])))
        try save("line-sequence.json", .array(seq))
        // Keyboard helpers and errors.
        try save("command-complete.json", try await exchange("command.complete", params([("prefix", .string("WA"))])))
        try save("error-unknown-method.json", try await exchange("no.such.method", .object([])))
        try save("index.json", EngineJSON.strings(written))
        return written
    }
}

/// Collects notification lines while recording fixtures.
final class NotificationSink {
    var lines: [String] = []
}
