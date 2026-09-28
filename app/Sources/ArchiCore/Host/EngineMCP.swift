// Oanarina Archi Tool — GPL-3.0-or-later
// Model Context Protocol server of archi-engine (`archi-engine <file.archi> --mcp`): the portable counterpart of
// `archi-cli --mcp` on the Mac, so Claude Desktop and Claude Code can edit drawings on Windows and Linux too.
// Newline-delimited JSON-RPC 2.0 on stdin/stdout: initialize, tools/list, tools/call, resources/*, prompts/*, ping,
// logging/setLevel. The tools are archi-cli's base tools plus AgentTools and AgentExtraTools.
import Foundation

@MainActor
public final class EngineMCPServer {
    public let session: EngineSession
    public var path: URL?
    let write: (String) -> Void
    var logLevel: String?
    var progressToken: EngineJSON?
    var progressCount = 0

    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public init(session: EngineSession, path: URL?, write: @escaping (String) -> Void) {
        self.session = session
        self.path = path
        self.write = write
    }

    // MARK: Tool definitions

    static func prop(_ type: String, _ description: String? = nil) -> EngineJSON {
        var o = EngineObject()
        o.set("type", type)
        if let d = description { o.set("description", d) }
        return o.json
    }
    static func anyProp(_ description: String) -> EngineJSON { ScriptJSON.object([("description", .string(description))]) }
    static func intArray() -> EngineJSON { ScriptJSON.object([("type", .string("array")), ("items", prop("integer"))]) }
    static func enumProp(_ values: [String]) -> EngineJSON { ScriptJSON.object([("type", .string("string")), ("enum", EngineJSON.strings(values))]) }

    static func schema(_ props: [(String, EngineJSON)], required: [String] = []) -> EngineJSON {
        var o = EngineObject()
        o.set("type", "object")
        o.set("properties", ScriptJSON.object(props))
        if !required.isEmpty { o.set("required", EngineJSON.strings(required)) }
        return o.json
    }

    static func tool(_ name: String, _ title: String, _ description: String, _ inputSchema: EngineJSON) -> EngineJSON {
        ScriptJSON.object([("name", .string(name)), ("title", .string(title)), ("description", .string(description)), ("inputSchema", inputSchema)])
    }

    static let exportFormats = ["dxf", "dxf12", "svg", "ifc", "ifczip", "obj", "stl", "glb", "3mf", "usda", "usdz", "step", "ply", "plt", "xlsx", "csv",
                                "geojson", "points", "analytical", "gbxml", "cobie", "dae", "dwg", "kml", "kmz", "bcf", "boq", "svglayers", "archi"]
    static let formatJSONCSV = ["json", "csv"]

    static func baseTools() -> [EngineJSON] {
        var t: [EngineJSON] = []
        t.append(tool("run_command", "Run command",
                      "Runs one or more AutoCAD-style command lines (newline-separated) against the document, e.g. \"LINE 0,0 1000,0 \" or \"WALL 0,0 5000,0 \". Unanswered prompts get Enter. Returns the command log (the last `maxLines` lines when long). With a progressToken in _meta, every log line is also streamed as a notifications/progress message while the commands run (and as notifications/message when logging is enabled).",
                      schema([("command", prop("string", "Command line(s)")), ("maxLines", prop("integer", "Return at most this many (last) log lines; default 500"))], required: ["command"])))
        t.append(tool("get_document_summary", "Document summary", "Project info, units, layers, levels, entity/element counts by type and model bounds.", schema([])))
        t.append(tool("get_document", "Full document", "The whole document as .archi JSON (can be large).", schema([])))
        t.append(tool("list_entities", "List entities", "2D/3D drafting entities (line, circle, arc, polyline, text, dimension, hatch, insert, solid…) with geometry.",
                      schema([("type", prop("string")), ("layer", prop("string")), ("limit", prop("integer"))])))
        t.append(tool("list_elements", "List BIM elements", "Building elements (wall, slab, column, beam, door, window, roof, stair, railing, space, curtainWall, component, grid).",
                      schema([("type", prop("string")), ("level", prop("integer"))])))
        t.append(tool("add_entity", "Add entity",
                      "Adds drafting entities. Geometry uses the .archi JSON format with a \"type\"; points may be [x,y]. Example: {\"type\":\"line\",\"a\":[0,0],\"b\":[1000,0],\"layer\":\"0\"}. Pass an array to add several. Units are millimetres, angles radians.",
                      schema([("entity", anyProp("Entity object or array of objects"))], required: ["entity"])))
        t.append(tool("add_element", "Add BIM element",
                      "Adds building elements, e.g. {\"type\":\"wall\",\"start\":[0,0],\"end\":[5000,0],\"thickness\":200,\"height\":3000} or {\"type\":\"door\",\"hostWall\":12,\"offset\":1500,\"width\":900}. Optional level, layer, material, name, props.",
                      schema([("element", anyProp("Element object or array of objects"))], required: ["element"])))
        t.append(tool("update_entity", "Update entity or element",
                      "Patches an entity/element by id. Keys: layer, color, linetype, lineweight, props, level, name, material, geometry, or any geometry field directly.",
                      schema([("id", prop("integer")), ("patch", prop("object"))], required: ["id", "patch"])))
        t.append(tool("delete", "Delete", "Deletes entities/elements by id (hosted doors/windows go with their wall).", schema([("ids", intArray())], required: ["ids"])))
        t.append(tool("save", "Save", "Saves the document as .archi (to `path`, or to the file it was opened from).", schema([("path", prop("string"))])))
        t.append(tool("export", "Export",
                      "Exports to dxf, dxf12, svg (2D plan of a level), ifc, ifczip, obj (+mtl), stl, glb, 3mf, usda, usdz, step, ply, plt, xlsx, csv (schedules), geojson, points, analytical, gbxml, cobie, dae, kml/kmz, bcf, boq, svglayers, dwg (needs an installed converter) or archi.",
                      schema([("path", prop("string")), ("format", enumProp(exportFormats)), ("level", prop("integer"))], required: ["path"])))
        t.append(tool("list_commands", "List commands", "All command names, aliases, categories and summaries.", schema([("category", prop("string"))])))
        t.append(tool("undo", "Undo", "Undoes the last change.", schema([])))
        t.append(tool("import_file", "Import file",
                      "Imports a file into the document (merged with new ids): .archi, .dxf, .dwg (via an installed converter), .ifc/.ifczip, .svg, .obj, .stl, .3mf, .gltf/.glb, .ply, .off, .amf, .dae, .step, .cityjson, .geojson, .shp, .osm, .asc, .xlsx, .csv/.txt survey points, .xyz/.pts point clouds. Returns the new ids and a summary.",
                      schema([("path", prop("string")), ("format", prop("string", "Override the format detected from the extension")),
                              ("offset", ScriptJSON.object([("type", .string("array")), ("items", prop("number")), ("description", .string("[dx, dy] move in drawing units"))]))], required: ["path"])))
        t.append(tool("takeoff", "Quantity takeoff",
                      "Quantities of BIM elements (SI units): wall length/net area/volume per type and material (openings deducted), slabs, roofs, columns, beams, door/window/opening counts, spaces; plus material volumes. format=csv returns CSV text.",
                      schema([("level", prop("integer")), ("format", enumProp(formatJSONCSV))])))
        t.append(tool("room_schedule", "Room schedule", "Rooms with net area (minus columns), gross area (to wall centre lines), perimeter, height and volume.",
                      schema([("level", prop("integer")), ("format", enumProp(formatJSONCSV))])))
        t.append(tool("check_model", "Check model",
                      "Model audit: walls without height/length, openings wider than or outside their host, overlapping or duplicate walls, room problems (unnamed, duplicate numbers, overlapping, self-intersecting), duplicate entities, missing levels. Each issue has ids and a zoom box.",
                      schema([])))
        return t
    }

    public lazy var tools: [EngineJSON] = {
        var t = EngineMCPServer.baseTools()
        if let extra = ScriptJSON.fromAny(AgentTools.definitions + AgentExtraTools.mutatingDefinitions).arrayValue { t += extra }
        t += EngineMCPServer.extraTools()
        return t
    }()

    // MARK: Serving

    func response(_ id: EngineJSON, _ result: EngineJSON) -> EngineJSON {
        ScriptJSON.object([("jsonrpc", .string("2.0")), ("id", id), ("result", result)])
    }
    func error(_ id: EngineJSON?, _ code: Int, _ msg: String) -> EngineJSON {
        let e = ScriptJSON.object([("code", .int(code)), ("message", .string(msg))])
        return ScriptJSON.object([("jsonrpc", .string("2.0")), ("id", id ?? .null), ("error", e)])
    }

    /// Handles one line; returns the reply line (nil for notifications and client responses).
    public func handle(line: String) async -> String? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        guard let obj = try? EngineJSON.parse(t) else { return error(nil, -32700, "Parse error").serialized }
        if let batch = obj.arrayValue {
            var out: [EngineJSON] = []
            for item in batch { if let r = await handle(item) { out.append(r) } }
            return out.isEmpty ? nil : EngineJSON.array(out).serialized
        }
        return await handle(obj)?.serialized
    }

    func handle(_ req: EngineJSON) async -> EngineJSON? {
        guard req.fields != nil, let method = req["method"]?.stringValue else {
            if req["result"] != nil || req["error"] != nil { return nil }
            return error(req["id"], -32600, "Invalid Request")
        }
        guard let id = req["id"], !id.isNull else { return nil }
        let params = req["params"] ?? .object([])
        switch method {
        case "initialize":
            let asked = params["protocolVersion"]?.stringValue ?? ""
            let version = EngineMCPServer.supportedVersions.contains(asked) ? asked : EngineMCPServer.supportedVersions[0]
            let caps = ScriptJSON.object([("tools", ScriptJSON.object([("listChanged", .bool(false))])), ("logging", .object([])),
                                          ("resources", ScriptJSON.object([("listChanged", .bool(false)), ("subscribe", .bool(false))])),
                                          ("prompts", ScriptJSON.object([("listChanged", .bool(false))]))])
            let info = ScriptJSON.object([("name", .string("archi")), ("title", .string("Oanarina Archi Tool")), ("version", .string(EngineSession.engineVersion))])
            let text = "Edits an Oanarina Archi Tool (.archi) CAD/BIM document. Units are millimetres (see get_document_summary). Use run_command for AutoCAD-style commands (list_commands), add_entity/add_element for precise JSON edits, and save to write the file."
            return response(id, ScriptJSON.object([("protocolVersion", .string(version)), ("capabilities", caps), ("serverInfo", info), ("instructions", .string(text))]))
        case "ping":
            return response(id, .object([]))
        case "logging/setLevel":
            logLevel = params["level"]?.stringValue?.lowercased()
            return response(id, .object([]))
        case "tools/list":
            return response(id, ScriptJSON.object([("tools", .array(tools))]))
        case "resources/list":
            return response(id, ScriptJSON.object([("resources", ScriptJSON.fromAny(AgentResources.list(session.editor.doc)))]))
        case "resources/templates/list":
            return response(id, ScriptJSON.object([("resourceTemplates", ScriptJSON.fromAny(AgentResources.templates))]))
        case "resources/read":
            guard let uri = params["uri"]?.stringValue else { return error(id, -32602, "missing uri") }
            do {
                let c = try AgentResources.read(uri, doc: session.editor.doc)
                let content = ScriptJSON.object([("uri", .string(c.uri)), ("mimeType", .string(c.mimeType)), ("text", .string(c.text))])
                return response(id, ScriptJSON.object([("contents", .array([content]))]))
            } catch {
                return self.error(id, -32002, EngineSession.describe(error))
            }
        case "prompts/list":
            return response(id, ScriptJSON.object([("prompts", ScriptJSON.fromAny(AgentPrompts.definitions))]))
        case "prompts/get":
            guard let name = params["name"]?.stringValue else { return error(id, -32602, "missing name") }
            do { return response(id, ScriptJSON.fromAny(try AgentPrompts.get(name, arguments: ScriptJSON.stringDict(params["arguments"]), doc: session.editor.doc))) }
            catch { return self.error(id, -32602, EngineSession.describe(error)) }
        case "tools/call":
            guard let name = params["name"]?.stringValue, tools.contains(where: { $0["name"]?.stringValue == name }) else {
                return error(id, -32602, "Unknown tool: " + (params["name"]?.stringValue ?? ""))
            }
            progressToken = params["_meta"]?["progressToken"]
            progressCount = 0
            defer { progressToken = nil }
            do {
                let result = try await call(name, params["arguments"] ?? .object([]))
                var text: String
                if case .string(let s) = result { text = s } else { text = EngineMCPServer.pretty(result) }
                if text.isEmpty { text = "{}" }
                var r = EngineObject()
                r.set("content", .array([ScriptJSON.object([("type", .string("text")), ("text", .string(text))])]))
                r.set("isError", false)
                if result.fields != nil { r.set("structuredContent", result) }
                return response(id, r.json)
            } catch {
                let msg = (error as? EngineError)?.message ?? EngineSession.describe(error)
                let content = ScriptJSON.object([("type", .string("text")), ("text", .string("Error: " + msg))])
                return response(id, ScriptJSON.object([("content", .array([content])), ("isError", .bool(true))]))
            }
        default:
            return error(id, -32601, "Method not found: " + method)
        }
    }

    /// Indented JSON for the text content of a tool result.
    static func pretty(_ j: EngineJSON, indent: String = "") -> String {
        let next = indent + "  "
        switch j {
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { next + pretty($0, indent: next) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let f):
            if f.isEmpty { return "{}" }
            var parts: [String] = []
            for e in f { parts.append(next + EngineJSON.string(e.key).serialized + ": " + pretty(e.value, indent: next)) }
            return "{\n" + parts.joined(separator: ",\n") + "\n" + indent + "}"
        default:
            return j.serialized
        }
    }

    func stream(_ line: String) {
        if let t = progressToken {
            progressCount += 1
            let p = ScriptJSON.object([("progressToken", t), ("progress", .int(progressCount)), ("message", .string(line))])
            write(ScriptJSON.object([("jsonrpc", .string("2.0")), ("method", .string("notifications/progress")), ("params", p)]).serialized)
        }
        if let l = logLevel, l == "debug" || l == "info" {
            let p = ScriptJSON.object([("level", .string("info")), ("logger", .string("archi")), ("data", .string(line))])
            write(ScriptJSON.object([("jsonrpc", .string("2.0")), ("method", .string("notifications/message")), ("params", p)]).serialized)
        }
    }

    func call(_ name: String, _ a: EngineJSON) async throws -> EngineJSON {
        let ed = session.editor
        switch name {
        case "run_command":
            guard let text = a["command"]?.stringValue else { throw EngineError.params("missing 'command'") }
            let streaming = progressToken != nil || logLevel != nil
            let previous = ed.onLog
            if streaming { ed.onLog = { [weak self] s in self?.stream(s) } }
            defer { ed.onLog = previous }
            var log: [String] = []
            for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                log += await session.runLines(line)
            }
            let maxLines = max(ScriptJSON.int(a["maxLines"]) ?? 500, 1)
            if log.count > maxLines {
                let tail = Array(log.suffix(maxLines))
                return ScriptJSON.object([("log", EngineJSON.strings(tail)), ("truncated", .int(log.count - maxLines)), ("totalLines", .int(log.count))])
            }
            return ScriptJSON.object([("log", EngineJSON.strings(log))])
        case "get_document_summary":
            var s = ScriptJSON.summary(ed.doc)
            s = ScriptJSON.setting(s, "file", EngineJSON.optString(path?.path))
            s = ScriptJSON.setting(s, "unsavedChanges", .bool(ed.isDirty))
            return s
        case "get_document": return ScriptJSON.documentJSON(ed.doc)
        case "list_entities":
            var r = ScriptJSON.entities(ed.doc, type: ScriptJSON.string(a["type"]), layer: ScriptJSON.string(a["layer"]))
            if let lim = ScriptJSON.int(a["limit"]), lim >= 0, r.count > lim { r = Array(r.prefix(lim)) }
            return ScriptJSON.object([("entities", .array(r)), ("count", .int(r.count))])
        case "list_elements":
            let r = ScriptJSON.elements(ed.doc, type: ScriptJSON.string(a["type"]), level: ScriptJSON.int(a["level"]))
            return ScriptJSON.object([("elements", .array(r)), ("count", .int(r.count))])
        case "add_entity":
            guard let e = a["entity"] else { throw EngineError.params("missing 'entity'") }
            return ScriptJSON.object([("ids", try session.addEntities(.array(e.arrayValue ?? [e]), label: "Agent Add"))])
        case "add_element":
            guard let e = a["element"] else { throw EngineError.params("missing 'element'") }
            return ScriptJSON.object([("ids", try session.addElements(.array(e.arrayValue ?? [e]), label: "Agent Add Element"))])
        case "update_entity":
            guard let id = ScriptJSON.int(a["id"]), let patch = a["patch"], patch.fields != nil else { throw EngineError.params("needs 'id' and 'patch'") }
            try ed.transaction("Agent Update") { d in try ScriptJSON.patch(&d, id: id, patch) }
            return session.objectJSON(id)
        case "delete":
            let ids = Set(ScriptJSON.ids(a["ids"]))
            guard !ids.isEmpty else { throw EngineError.params("missing 'ids'") }
            return ScriptJSON.object([("deleted", .int(session.removeObjects(ids, label: "Agent Delete")))])
        case "save":
            guard let u = ScriptJSON.string(a["path"]).map({ session.url($0) }) ?? path else { throw EngineError.params("no path: pass 'path'") }
            try DocumentIO.write(ed.doc, to: u, format: "archi")
            path = u
            ed.fileURL = u
            ed.isDirty = false
            return ScriptJSON.object([("path", .string(u.path))])
        case "export":
            guard let p = ScriptJSON.string(a["path"]) else { throw EngineError.params("missing 'path'") }
            let u = session.url(p)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DocumentIO.write(ed.doc, to: u, format: ScriptJSON.string(a["format"]), level: ScriptJSON.int(a["level"]))
            return ScriptJSON.object([("path", .string(u.path))])
        case "list_commands":
            return ScriptJSON.object([("commands", session.commandList(category: ScriptJSON.string(a["category"])))])
        case "undo":
            ed.undo()
            return ScriptJSON.object([("ok", .bool(true))])
        case "import_file":
            guard let p = ScriptJSON.string(a["path"]) else { throw EngineError.params("missing 'path'") }
            let u = session.url(p)
            let off = ScriptJSON.point(a["offset"]) ?? .zero
            let fmtName = ScriptJSON.string(a["format"])
            var result: (DocumentMerge.Result, String)?
            try ed.transaction("Agent Import") { d in result = try FileImport.importFile(u, into: &d, format: fmtName, offset: off) }
            guard let r = result else { throw EngineError.failed("import failed") }
            return ScriptJSON.object([("summary", .string(r.1)), ("entityIds", EngineJSON.ints(r.0.entityIDs)), ("elementIds", EngineJSON.ints(r.0.elementIDs)),
                                      ("addedLevels", ScriptJSON.fromAny(r.0.addedLevels))])
        case "takeoff":
            let t = QuantityTakeoff.compute(ed.doc, level: ScriptJSON.int(a["level"]))
            if ScriptJSON.string(a["format"]) == "csv" { return .string(t.csv) }
            var lines: [EngineJSON] = []
            for l in t.lines {
                var o = EngineObject()
                o.set("category", l.category); o.set("type", l.key); o.set("material", l.material); o.set("count", l.count)
                o.set("length_m", l.length); o.set("area_m2", l.area); o.set("volume_m3", l.volume); o.set("deducted_m2", l.deducted)
                o.set("ids", EngineJSON.ints(l.ids))
                lines.append(o.json)
            }
            var mats: [EngineJSON] = []
            for m in t.materials { mats.append(ScriptJSON.object([("material", .string(m.material)), ("area_m2", .number(m.area)), ("volume_m3", .number(m.volume))])) }
            return ScriptJSON.object([("lines", .array(lines)), ("materials", .array(mats))])
        case "room_schedule":
            let rows = RoomSchedule.compute(ed.doc, level: ScriptJSON.int(a["level"]))
            if ScriptJSON.string(a["format"]) == "csv" { return .string(RoomSchedule.csv(rows)) }
            var out: [EngineJSON] = []
            for r in rows {
                var o = EngineObject()
                o.set("id", r.id); o.set("number", r.number); o.set("name", r.name); o.set("level", r.level)
                o.set("netArea_m2", r.netArea); o.set("grossArea_m2", r.grossArea); o.set("perimeter_m", r.perimeter)
                o.set("height_m", r.height); o.set("volume_m3", r.volume)
                out.append(o.json)
            }
            return ScriptJSON.object([("rooms", .array(out))])
        case "check_model":
            let issues = ModelChecker.check(ed.doc)
            var out: [EngineJSON] = []
            for i in issues {
                var o = EngineObject()
                o.set("severity", i.severity.rawValue); o.set("code", i.code); o.set("message", i.message); o.set("ids", EngineJSON.ints(i.ids))
                if !i.bounds.isEmpty { o.set("zoom", ScriptJSON.object([("min", .point(i.bounds.min)), ("max", .point(i.bounds.max))])) }
                out.append(o.json)
            }
            return ScriptJSON.object([("count", .int(issues.count)), ("issues", .array(out))])
        default:
            if let r = try await callExtraTool(name, a) { return r }
            if AgentExtraTools.mutatingNames.contains(name) || AgentTools.names.contains(name) { return try session.callAgentTool(name, a) }
            throw EngineError.params("unknown tool " + name)
        }
    }

    /// Reads requests from stdin until it closes.
    public func serve(lines: AsyncStream<String>) async {
        for await line in lines {
            if let r = await handle(line: line) { write(r) }
        }
    }
}
