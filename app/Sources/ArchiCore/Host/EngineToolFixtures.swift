// Oanarina Archi Tool — GPL-3.0-or-later
// Recorded exchanges of the tool-window methods (EngineToolDialogs.swift, EngineScripting.swift) for the Windows shell's
// fixture engine and UI tests: files `tools-*.json` next to the other fixtures (archi-engine --fixtures).
import Foundation

extension EngineSession {
    /// Records the tool fixtures for `sample` into `dir`; returns the file names (added to index.json by writeFixtures).
    @discardableResult
    public static func writeToolFixtures(to dir: URL, sample: URL) async throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sink = NotificationSink()
        let s = EngineSession(emit: { sink.lines.append($0) })
        s.baseDirectory = sample.deletingLastPathComponent()
        var written: [String] = []
        var nextID = 1000

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
        let sampleGraph = ScriptJSON.encode(NodeGraph.sample)
        try save("tools-graph-get.json", try await exchange("graph.get", .object([])))
        try save("tools-graph-evaluate.json", try await exchange("graph.evaluate", params([("graph", sampleGraph), ("preview", .string("plan")), ("kinds", .bool(true))])))
        try save("tools-graph-evaluate-3d.json", try await exchange("graph.evaluate", params([("graph", sampleGraph), ("preview", .string("3D"))])))
        try save("tools-graph-script.json", try await exchange("graph.script", params([("graph", sampleGraph), ("name", .string("graph"))])))
        try save("tools-sheetset-get.json", try await exchange("sheetset.get", .object([])))
        if !s.editor.doc.layouts.isEmpty {
            try save("tools-titleblock-get.json", try await exchange("titleblock.get", params([("layout", .int(0))])))
        }
        try save("tools-material-list.json", try await exchange("material.list", .object([])))
        try save("tools-doc-variables.json", try await exchange("doc.variables", params([("prefixes", EngineJSON.strings(["MAT", "PROJFIELD:", "TITLEBLOCK", "NODEGRAPH"]))])))
        try save("tools-markup-list.json", try await exchange("markup.list", .object([])))
        try save("tools-revcloud-list.json", try await exchange("revcloud.list", .object([])))
        try save("tools-family-list.json", try await exchange("family.list", .object([])))
        let tmpl = try await exchange("family.template", params([("template", .string("Furniture"))]))
        try save("tools-family-template.json", tmpl)
        if let draft = tmpl["response"]?["result"] {
            try save("tools-family-evaluate.json", try await exchange("family.evaluate", params([("draft", draft)])))
        }
        try save("tools-blocks-list.json", try await exchange("blocks.list", .object([])))
        try save("tools-customizer-get.json", try await exchange("customizer.get", .object([])))
        try save("tools-agent-methods.json", try await exchange("agent.methods", .object([])))
        try save("tools-script-summary.json", try await exchange("script.call", params([("fn", .string("summary")), ("args", .array([]))])))
        let scan = try await exchange("library.scan", params([("folder", .string(sample.deletingLastPathComponent().path)), ("recursive", .bool(false))]))
        try save("tools-library-scan.json", scan)
        if let items = scan["response"]?["result"]?["items"]?.arrayValue, let first = items.first(where: { !($0["block"]?.isNull ?? true) }) ?? items.first {
            let p = params([("file", first["file"] ?? .null), ("block", first["block"] ?? .null)])
            try save("tools-library-preview.json", try await exchange("library.preview", p))
        }
        try save("tools-compare-run.json", try await exchange("compare.run", params([("path", .string(sample.path))])))
        return written
    }
}
