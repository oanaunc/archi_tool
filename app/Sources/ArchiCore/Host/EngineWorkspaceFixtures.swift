// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the panels and workspace methods (EngineWorkspace.swift) for the Windows shell's fixture engine
// and tests: files `ws-*.json` next to the other fixtures (archi-engine --fixtures).
import Foundation

extension EngineSession {
    /// Records the Alerts, Navigator, Outliner, Content, projection tile and assistant context fixtures of `sample`.
    @discardableResult
    public static func writeWorkspaceFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registerWorkspaceCommands()
        let sink = NotificationSink()
        let s = EngineSession(emit: { sink.lines.append($0) })
        s.baseDirectory = sample.deletingLastPathComponent()
        var written: [String] = []
        var nextID = 5000

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
        try save("ws-alerts.json", try await exchange("alerts.get", params([("showInfo", .bool(true))])))
        try save("ws-navigator.json", try await exchange("navigator.get", params([("limit", .int(4000))])))
        try save("ws-outliner.json", try await exchange("outliner.get", .object([])))
        try save("ws-content-scan.json", try await exchange("content.scan", params([("path", .string(sample.path))])))
        var tiles: [EngineJSON] = []
        for v in ["South", "Section"] { tiles.append(try await exchange("view.projection", params([("view", .string(v)), ("width", .int(640)), ("height", .int(360))]))) }
        try save("ws-projection.json", .array(tiles))
        try save("ws-macro-buttons.json", try await exchange("macro.buttons", .object([])))
        try save("ws-assistant-context.json", try await exchange("assistant.context", .object([])))
        return written
    }
}
