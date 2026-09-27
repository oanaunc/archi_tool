// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the canvas methods (EngineCanvas.swift) for the Windows shell's fixture engine and canvas tests:
// files `canvas-*.json` next to the other fixtures (archi-engine --fixtures).
import Foundation

extension EngineSession {
    /// Records the canvas fixtures for `sample` into `dir`; returns the file names (added to index.json by writeFixtures).
    @discardableResult
    public static func writeCanvasFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registerCanvasCommands()
        let sink = NotificationSink()
        let s = EngineSession(emit: { sink.lines.append($0) })
        s.baseDirectory = sample.deletingLastPathComponent()
        var written: [String] = []
        var nextID = 2000

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
        _ = try await exchange("canvas.view", params([("center", EngineJSON.point(Vec2(11000, 1000))), ("scale", .number(0.05))]))
        try save("canvas-state.json", try await exchange("canvas.state", .object([])))
        try save("canvas-palette-items.json", try await exchange("palette.items", .object([])))
        let doc = s.editor.doc
        // A wall: candidates under its midpoint, temporary dimensions, the chain of joined walls, double-click.
        if let wall = doc.elements.first(where: { $0.typeName == "wall" && $0.level == doc.currentLevel }), case .wall(let w) = wall.geometry {
            let mid = (w.start + w.end) / 2
            let pt = params([("x", .number(mid.x)), ("y", .number(mid.y)), ("pixelsPerUnit", .number(0.05))])
            try save("canvas-pick-candidates.json", try await exchange("pick.candidates", pt))
            _ = try await exchange("select.set", params([("ids", .ints([wall.id]))]))
            try save("canvas-tempdims-get.json", try await exchange("tempdims.get", .object([])))
            try save("canvas-flips-get.json", try await exchange("flips.get", params([("pixelsPerUnit", .number(0.05))])))
            try save("canvas-select-chain.json", try await exchange("select.chain", params([("id", .int(wall.id))])))
            try save("canvas-doubleclick-wall.json", try await exchange("canvas.doubleClick", params([("id", .int(wall.id))])))
            let box = BBox2(points: [w.start, w.end])
            let lo = box.min - Vec2(500, 500), hi = box.max + Vec2(500, 500)
            let loop: [Vec2] = [lo, Vec2(lo.x, hi.y), hi, Vec2(hi.x, lo.y)]
            _ = try await exchange("select.set", params([("ids", .array([]))]))
            try save("canvas-select-lasso.json", try await exchange("select.lasso", params([("points", EngineDrawJSON.points(loop))])))
            _ = try await exchange("select.set", params([("ids", .array([]))]))
        }
        // A door: its flip arrows.
        if let door = doc.elements.first(where: { $0.typeName == "door" && $0.level == doc.currentLevel }) ?? doc.elements.first(where: { $0.typeName == "opening" }) {
            _ = try await exchange("select.set", params([("ids", .ints([door.id]))]))
            try save("canvas-flips-door.json", try await exchange("flips.get", params([("pixelsPerUnit", .number(0.05))])))
            _ = try await exchange("select.set", params([("ids", .array([]))]))
        }
        // A polyline drawn for the recording: grips, the multi-functional grip menu, previews, a grip edit (then undone).
        let b = s.extents()
        let x0 = b.isEmpty ? 0 : b.min.x, y0 = b.isEmpty ? -3000 : b.min.y - 3000
        _ = try await exchange("command.run", params([("line", .string("PLINE \(fmt(x0, 3)),\(fmt(y0, 3)) \(fmt(x0 + 4000, 3)),\(fmt(y0, 3)) \(fmt(x0 + 4000, 3)),\(fmt(y0 + 2000, 3)) "))]))
        if !s.editor.isIdle { _ = try await exchange("input.key", params([("key", .string("Enter"))])) }
        if let pl = s.editor.doc.entities.last {
            _ = try await exchange("select.set", params([("ids", .ints([pl.id]))]))
            let grips = try await exchange("grips.get", .object([]))
            try save("canvas-grips-polyline.json", grips)
            let gp = grips["response"]?["result"]?.arrayValue ?? []
            let mid = gp.first(where: { $0["kind"]?.stringValue == "midpoint" }) ?? gp.first
            if let mid, let idx = mid["index"]?.intValue {
                try save("canvas-grips-actions.json", try await exchange("grips.actions", params([("id", .int(pl.id)), ("index", .int(idx))])))
                let at = params([("id", .int(pl.id)), ("index", .int(idx)), ("x", .number(x0 + 2000)), ("y", .number(y0 - 800)), ("pixelsPerUnit", .number(0.05))])
                try save("canvas-grips-preview.json", try await exchange("grips.preview", at))
                let mv = params([("id", .int(pl.id)), ("index", .int(0)), ("x", .number(x0 + 1000)), ("y", .number(y0 + 1000)), ("mode", .string("move")), ("pixelsPerUnit", .number(0.05))])
                try save("canvas-grips-preview-move.json", try await exchange("grips.preview", mv))
                try save("canvas-grips-edit.json", try await exchange("grips.edit", at))
                _ = try await exchange("edit.undo", .object([]))
            }
            _ = try await exchange("select.set", params([("ids", .array([]))]))
        }
        _ = try await exchange("edit.undo", .object([]))
        // Tool palette click-to-place: preview and drop of the first component (then undone).
        if let f = ComponentLibrary.families.first {
            let item = EngineToolDrop.componentPrefix + f.id
            try save("canvas-place-preview.json", try await exchange("place.preview", params([("item", .string(item)), ("x", .number(x0)), ("y", .number(y0)), ("turns", .int(1))])))
            try save("canvas-place-drop.json", try await exchange("place.drop", params([("item", .string(item)), ("x", .number(x0)), ("y", .number(y0)), ("turns", .int(1))])))
            _ = try await exchange("edit.undo", .object([]))
        }
        // Text: double-click opens the in-place editor.
        if let t = s.editor.doc.entities.first(where: { if case .text = $0.geometry { return true } else { return false } }) {
            try save("canvas-doubleclick-text.json", try await exchange("canvas.doubleClick", params([("id", .int(t.id))])))
        }
        // Sheet viewports.
        if !s.editor.doc.layouts.isEmpty {
            try save("canvas-sheet-viewports.json", try await exchange("sheet.viewports", params([("layout", .int(0))])))
        }
        // Cursor with tracking and dynamic-input fields during LINE.
        var seq: [EngineJSON] = []
        seq.append(try await exchange("command.run", params([("line", .string("LINE"))])))
        seq.append(try await exchange("input.point", params([("x", .number(x0)), ("y", .number(y0)), ("snap", .bool(false))])))
        seq.append(try await exchange("input.cursor", params([("x", .number(x0 + 3000)), ("y", .number(y0 + 40)), ("pixelsPerUnit", .number(0.05))])))
        seq.append(try await exchange("input.key", params([("key", .string("Escape"))])))
        try save("canvas-cursor-sequence.json", .array(seq))
        return written
    }
}
