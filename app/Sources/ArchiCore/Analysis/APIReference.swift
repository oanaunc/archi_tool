// Oanarina Archi Tool — GPL-3.0-or-later
// Generated scripting / agent API reference (SCR-009): every command (name, aliases, category, summary), every agent
// tool with its input schema, the import/export formats and runnable sample scripts. `archi-cli --api-reference`
// writes it as Markdown; the samples are executed by the test suite so the documentation cannot drift.
import Foundation

public enum APIReference {
    public struct Sample { public var title: String; public var script: [String]; public var expect: String }

    /// Command-line samples (each line is one command line, as in a .scr script or `archi.run(…)` / `run_command`).
    public static let samples: [Sample] = [
        Sample(title: "Draw a line and a circle", script: ["LINE 0,0 1000,0 ", "CIRCLE 500,500 200"], expect: "2 entities"),
        Sample(title: "Walls, a door and a room", script: ["WALL 0,0 6000,0 6000,4000 0,4000 C", "ROOM 3000,2000"], expect: "4 walls and a room"),
        Sample(title: "Layer and polyline", script: ["-LAYER M NOTES ", "PLINE 0,0 1000,0 1000,1000 C"], expect: "a closed polyline on NOTES"),
        Sample(title: "Save a copy and verify the round trip", script: ["LINE 0,0 100,100 ", "SAVECHECK"], expect: "Round trip OK"),
        Sample(title: "Editing time", script: ["TIME Display"], expect: "Total editing time"),
    ]

    static func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }

    /// Markdown reference. `tools` are agent tool definitions (MCP: name, description, inputSchema).
    public static func markdown(registry: CommandRegistry = .shared, tools: [[String: Any]] = AgentTools.definitions, version: String = "") -> String {
        registry.ensureBuiltins()
        let cmds = registry.sorted
        var s = "# Oanarina Archi Tool — API reference\n\n"
        s += "Generated\(version.isEmpty ? "" : " by archi-cli \(version)"): \(cmds.count) commands, \(tools.count) agent tools, file format \(ArchiDocument.currentFormatVersion).\n"
        s += "Every command runs from the command line, scripts (`archi.run`), the agent server (`run_command`) and `archi-cli`.\n\n"
        s += "## Contents\n\n- [Sample scripts](#sample-scripts)\n- [Commands](#commands)\n- [Agent tools](#agent-tools)\n- [File formats](#file-formats)\n\n"
        s += "## Sample scripts\n\n"
        for x in samples {
            s += "### \(x.title)\n\n```\n" + x.script.joined(separator: "\n") + "\n```\n\nResult: \(x.expect).\n\n"
        }
        s += "## Commands\n\n"
        let byCat = Dictionary(grouping: cmds, by: \.category)
        for cat in byCat.keys.sorted() {
            s += "### \(cat)\n\n| Command | Aliases | Description |\n| --- | --- | --- |\n"
            for c in byCat[cat]!.sorted(by: { $0.name < $1.name }) {
                s += "| `\(c.name)` | \(c.aliases.map { "`\($0)`" }.joined(separator: ", ")) | \(cell(c.summary)) |\n"
            }
            s += "\n"
        }
        s += "## Agent tools\n\n"
        for t in tools.sorted(by: { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }) {
            guard let name = t["name"] as? String else { continue }
            s += "### `\(name)`\n\n\(t["description"] as? String ?? "")\n\n"
            let schema = t["inputSchema"] as? [String: Any]
            let props = schema?["properties"] as? [String: Any] ?? [:]
            let req = Set(schema?["required"] as? [String] ?? [])
            if props.isEmpty { s += "No parameters.\n\n"; continue }
            s += "| Parameter | Type | Required | Description |\n| --- | --- | --- | --- |\n"
            for k in props.keys.sorted() {
                let p = props[k] as? [String: Any] ?? [:]
                var type = p["type"] as? String ?? "any"
                if let e = p["enum"] as? [Any] { type += " (" + e.map { "\($0)" }.joined(separator: ", ") + ")" }
                s += "| `\(k)` | \(cell(type)) | \(req.contains(k) ? "yes" : "") | \(cell(p["description"] as? String ?? "")) |\n"
            }
            s += "\n"
        }
        s += "## File formats\n\nImport: " + FileImport.importFormats.map { "`.\($0)`" }.joined(separator: ", ") + "\n\n"
        s += "Export: `.archi`, `.architemplate`, `.dxf`, `.svg`, `.ifc`, `.obj`, `.stl`, `.glb`, `.csv`, " + FileImport.exportFormats.map { "`\($0)`" }.joined(separator: ", ") + "\n"
        return s
    }

    /// Runs the sample scripts on fresh editors; returns (title, passed, log) per sample.
    @MainActor public static func runSamples() async -> [(title: String, passed: Bool, log: [String])] {
        var out: [(String, Bool, [String])] = []
        for x in samples {
            let ed = Editor()
            var log: [String] = []
            for line in x.script { log += await ed.run(line) }
            let text = log.joined(separator: "\n")
            let failed = text.contains("Unknown command") || text.lowercased().contains("error")
            out.append((x.title, !failed, log))
        }
        return out
    }
}
