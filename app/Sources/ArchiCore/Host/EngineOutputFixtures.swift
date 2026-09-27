// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the output methods (EngineOutput.swift) for the Windows shell's fixture engine and tests:
// files `output-*.json` next to the other fixtures (archi-engine --fixtures). Cedar House with the sheet "A-102 Plans"
// of tutorial 10 (three viewports, title block): the Plot dialog targets, the sheet and model previews (SVG pages and
// the preview PDF), plot style tables, the Render window data, camera path frames, sun frames and the host actions of
// PREVIEW, RENDERSAVE and RENDERQUEUE.
import Foundation

extension EngineSession {
    @discardableResult
    public static func writeOutputFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        registerOutputCommands()
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
        func command(_ line: String) async throws -> EngineJSON {
            let r = try await exchange("command.run", params([("line", .string(line))]))
            if r["response"]?["result"]?["active"]?.boolValue == true { _ = try await exchange("input.key", params([("key", .string("Escape"))])) }
            return r
        }

        _ = try await exchange("doc.open", params([("path", .string(sample.path))]))
        // Tutorial 10: sheet A-102 with two plans and the south elevation.
        _ = try await command("LAYOUT New \"A-102 Plans\"")
        _ = try await command("MVIEW 15,40 205,280 1:150 Plan \"Ground Floor\"")
        _ = try await command("LEVEL Set \"Upper Floor\"")
        _ = try await command("MVIEW 215,150 405,280 1:200 Plan \"Upper Floor\"")
        _ = try await command("LEVEL Set \"Ground Floor\"")
        _ = try await command("LAYOUT Titleblock Title \"Plans\" Number \"A-102\" ;")
        // The preview is recorded before the south elevation is placed: its lawn and foliage are hundreds of
        // thousands of small fills (tens of MB of SVG), too much for the fixture files.
        try save("output-preview-sheet.json", try await exchange("plot.preview", params([("what", .string("sheet:1"))])))
        _ = try await command("MVIEW 215,40 405,140 1:200 South \"South Elevation\"")
        try save("output-plot-info.json", try await exchange("plot.info", .object([])))
        try save("output-preview-model.json", try await exchange("plot.preview", params([("what", .string("model"))])))
        try save("output-plotstyle-list.json", try await exchange("plotstyle.list", .object([])))
        try save("output-render-window.json", try await exchange("render.window", params([("day", .int(172)), ("hour", .number(15))])))
        try save("output-camerapath-list.json", try await exchange("camerapath.list", .object([])))
        try save("output-camerapath-frames.json", try await exchange("camerapath.frames", params([("seconds", .number(1)), ("fps", .int(10))])))
        try save("output-sun-frames.json", try await exchange("render.sunFrames", params([("day", .int(172)), ("fromHour", .number(7)), ("toHour", .number(19)), ("seconds", .number(1)), ("fps", .int(6))])))
        try save("output-command-preview.json", try await command("PREVIEW"))
        try save("output-command-rendersave.json", try await command("RENDERSAVE Goldenhour Front 1920 1080 Front.png"))
        try save("output-command-renderqueue.json", try await command("RENDERQUEUE Cameras"))
        if let pdf = s.output.previewPDF { try? FileManager.default.removeItem(at: pdf) }
        return written
    }
}
