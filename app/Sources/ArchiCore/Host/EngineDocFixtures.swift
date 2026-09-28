// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the document tools (EngineDocTools.swift) for the Windows shell's fixture engine and tests:
// files `doc-*.json` next to the other fixtures (archi-engine --fixtures).
import Foundation

extension EngineSession {
    /// Records the schedule, browser, selection, inspector, spelling and text style fixtures of `sample` into `dir`.
    @discardableResult
    public static func writeDocToolFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registerDocCommands()
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
        var sched: [EngineJSON] = []
        for k in ScheduleExporter.kinds { sched.append(try await exchange("schedule.get", params([("kind", .string(k))]))) }
        try save("doc-schedules.json", .array(sched))
        try save("doc-browser.json", try await exchange("browser.get", .object([])))
        try save("doc-textstyles.json", try await exchange("textstyle.list", .object([])))
        try save("doc-spell-words.json", try await exchange("spell.words", params([("all", .bool(true))])))
        let doc = s.editor.doc
        let walls = doc.elements.filter { $0.typeName == "wall" && $0.level == doc.currentLevel }.prefix(2).map(\.id)
        let text = doc.entities.first { if case .text = $0.geometry { return true }; return false }.map(\.id)
        var ids = Array(walls)
        if let t = text { ids.append(t) }
        _ = try await exchange("select.set", params([("ids", .ints(ids))]))
        try save("doc-selection-info.json", try await exchange("selection.info", .object([])))
        try save("doc-inspect.json", try await exchange("inspect.get", .object([])))
        _ = try await exchange("select.set", params([("ids", .array([]))]))
        try save("doc-history.json", try await exchange("panel.history", .object([])))
        // EXPORT PNG of the current level (the portable rasteriser): the image goes next to the fixtures.
        let png = dir.appendingPathComponent("doc-plan.png")
        let t0 = Date()
        try save("doc-export-png.json", try await exchange("file.export", params([("path", .string(png.path)), ("format", .string("png")), ("dpi", .number(100))])))
        print("doc-plan.png: " + fmt(Date().timeIntervalSince(t0), 1) + " s")
        return written
    }
}
