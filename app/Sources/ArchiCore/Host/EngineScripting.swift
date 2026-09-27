// Oanarina Archi Tool — GPL-3.0-or-later
// Scripting and agent methods of archi-engine (docs/ENGINE-PROTOCOL.md, "Scripting and agents"):
// - `script.call {fn, args}`: the Mac `archi` JavaScript API (ArchiApp/ScriptEngine.swift). On Windows the script runs in
//   the shell's JavaScript and every archi.* call arrives here, one call per request (mutating calls are one undo step).
// - `agent.call {method, params}`: the methods of the Mac local agent server (ArchiApp/AgentServer.swift); the Windows
//   shell hosts the HTTP listener and forwards to this method (eval_js and screenshot are answered by the shell).
// - Plugin commands registered by scripts ask the shell to run their function (`host` action `runScript`).
import Foundation

extension EngineSession {
    // MARK: Dispatch of the methods added for the Windows dialogs and tools

    /// Methods of this file and of EngineToolDialogs.swift; nil = not one of them.
    func callUI(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "script.call": return try await scriptCall(p)
        case "agent.call": return try await agentCall(p)
        case "agent.methods": return EngineAgent.methodList()
        default: return try await callToolDialogs(method, p)
        }
    }

    func args(_ p: EngineJSON) -> [EngineJSON] { p["args"]?.arrayValue ?? [] }

    func arg(_ a: [EngineJSON], _ i: Int) -> EngineJSON? {
        guard a.indices.contains(i) else { return nil }
        let v = a[i]
        return v.isNull ? nil : v
    }

    func scriptError(_ e: Error) -> EngineError {
        if let x = e as? EngineError { return x }
        return EngineError.failed(EngineSession.describe(e))
    }

    // MARK: script.call

    func scriptCall(_ p: EngineJSON) async throws -> EngineJSON {
        guard let fn = p["fn"]?.stringValue else { throw EngineError.params("missing 'fn'") }
        let a = args(p)
        do { return try await scriptFunction(fn, a) }
        catch let e as EngineError { throw e }
        catch { throw scriptError(error) }
    }

    func scriptFunction(_ fn: String, _ a: [EngineJSON]) async throws -> EngineJSON {
        switch fn {
        case "run":
            let text = arg(a, 0)?.stringValue ?? ""
            return EngineJSON.strings(await runLines(text))
        case "doc": return ScriptJSON.documentJSON(editor.doc)
        case "summary": return ScriptJSON.summary(editor.doc)
        case "entities":
            let f = arg(a, 0)
            return .array(ScriptJSON.entities(editor.doc, type: ScriptJSON.string(f?["type"]), layer: ScriptJSON.string(f?["layer"])))
        case "elements":
            let f = arg(a, 0)
            return .array(ScriptJSON.elements(editor.doc, type: ScriptJSON.string(f?["type"]), level: ScriptJSON.int(f?["level"])))
        case "get":
            let id = ScriptJSON.int(arg(a, 0)) ?? -1
            if let e = editor.doc.entity(id) { return ScriptJSON.encode(e) }
            if let e = editor.doc.element(id) { return ScriptJSON.encode(e) }
            return .null
        case "add": return try addEntities(arg(a, 0) ?? .null, label: "Script Add")
        case "addElement": return try addElements(arg(a, 0) ?? .null, label: "Script Add Element")
        case "update":
            let id = ScriptJSON.int(arg(a, 0)) ?? -1
            let patch = arg(a, 1) ?? .object([])
            try editor.transaction("Script Update") { d in try ScriptJSON.patch(&d, id: id, patch) }
            return objectJSON(id)
        case "remove":
            let ids = Set(ScriptJSON.ids(arg(a, 0)))
            return .int(removeObjects(ids, label: "Script Delete"))
        case "select":
            let ids = ScriptJSON.ids(arg(a, 0))
            let doc = editor.doc
            editor.selection = Set(ids.filter { doc.contains($0) })
            return EngineJSON.ints(editor.selection.sorted())
        case "selection": return EngineJSON.ints(editor.selection.sorted())
        case "setVar":
            let name = arg(a, 0)?.stringValue ?? ""
            let value = arg(a, 1)?.stringValue ?? ""
            editor.transaction("Set Variable") { $0.setVariable(name, value) }
            return .string(value)
        case "getVar":
            let name = arg(a, 0)?.stringValue ?? ""
            return EngineJSON.optString(editor.doc.variable(name))
        case "layers": return ScriptJSON.encode(editor.doc.layers)
        case "levels": return ScriptJSON.encode(editor.doc.levels)
        case "wall": return try scriptWall(a)
        case "door": return try scriptOpening(.door, a)
        case "window": return try scriptOpening(.window, a)
        case "opening": return try scriptOpening(.opening, a)
        case "slab": return try scriptSlab(a)
        case "room": return try scriptRoom(a)
        case "column": return try scriptColumn(a)
        case "undo": await cancelAndWait(); editor.undo(); return .bool(true)
        case "redo": await cancelAndWait(); editor.redo(); return .bool(true)
        case "commands": return commandList(category: nil)
        case "evaluateGraph":
            let g = try graph(from: arg(a, 0))
            let ev = g.evaluate()
            var errs: [EngineJSONField] = []
            for k in ev.errors.keys.sorted() { errs.append(EngineJSONField(String(k), .string(ev.errors[k] ?? ""))) }
            var o = EngineObject()
            o.set("objects", ev.output.count)
            o.set("elements", ev.elementOutput.count)
            o.set("errors", .object(errs))
            o.set("geometry", .array(ev.output.map { ScriptJSON.encode($0) }))
            return o.json
        case "bakeGraph":
            let g = try graph(from: arg(a, 0))
            let ev = g.evaluate()
            var ids: [EntityID] = []
            editor.transaction("Bake Node Graph") { d in ids = NodeGraphBake.bake(ev.output, elements: ev.elementOutput, into: &d) }
            return EngineJSON.ints(ids)
        case "registerCommand": return try registerScriptCommand(a)
        default:
            throw EngineError(EngineError.methodNotFound, "archi.\(fn) is not a function of the archi API")
        }
    }

    /// Runs command lines (newline-separated) to completion, as the Mac ScriptEngine.runCommands does.
    func runLines(_ text: String) async -> [String] {
        var all: [String] = []
        for line in text.components(separatedBy: .newlines) {
            await cancelAndWait()
            all += await editor.run(line)
            var n = 0
            while let t = editor.backgroundTask, n < 100 {
                let mark = editor.log.count
                await t.value
                if editor.backgroundTask == t { editor.backgroundTask = nil }
                if editor.log.count > mark { all += editor.log[mark...] }
                n += 1
            }
        }
        return all
    }

    func objectJSON(_ id: EntityID) -> EngineJSON {
        if let e = editor.doc.entity(id) { return ScriptJSON.encode(e) }
        if let e = editor.doc.element(id) { return ScriptJSON.encode(e) }
        return .null
    }

    func addEntities(_ obj: EngineJSON, label: String) throws -> EngineJSON {
        let list = obj.arrayValue ?? [obj]
        var ids: [EntityID] = []
        try editor.transaction(label) { d in
            for item in list { ids.append(d.add(try ScriptJSON.entity(from: item, doc: d))) }
        }
        if obj.arrayValue != nil { return EngineJSON.ints(ids) }
        return ids.first.map { EngineJSON.int($0) } ?? .null
    }

    func addElements(_ obj: EngineJSON, label: String) throws -> EngineJSON {
        let list = obj.arrayValue ?? [obj]
        var ids: [EntityID] = []
        try editor.transaction(label) { d in
            for item in list { ids.append(ScriptJSON.add(try ScriptJSON.element(from: item, doc: d), to: &d)) }
        }
        if obj.arrayValue != nil { return EngineJSON.ints(ids) }
        return ids.first.map { EngineJSON.int($0) } ?? .null
    }

    func removeObjects(_ ids: Set<EntityID>, label: String) -> Int {
        let before = editor.doc.entities.count + editor.doc.elements.count
        editor.transaction(label) { $0.remove(ids: ids) }
        editor.selection.subtract(ids)
        return before - editor.doc.entities.count - editor.doc.elements.count
    }

    func commandList(category: String?) -> EngineJSON {
        var out: [EngineJSON] = []
        let cat = category?.lowercased()
        for c in editor.registry.sorted {
            if let cat, c.category.lowercased() != cat { continue }
            var o = EngineObject()
            o.set("name", c.name)
            o.set("aliases", EngineJSON.strings(c.aliases))
            o.set("category", c.category)
            o.set("summary", c.summary)
            out.append(o.json)
        }
        return .array(out)
    }

    func graph(from v: EngineJSON?) throws -> NodeGraph {
        guard let v, v.fields != nil else { throw ScriptJSON.fail("expected a node graph object") }
        do { return try ScriptJSON.decode(NodeGraph.self, from: v) }
        catch { throw ScriptJSON.fail("not a node graph: " + EngineSession.describe(error)) }
    }

    // MARK: Building helpers (archi.wall, door, window, slab, room, column)

    func options(_ a: [EngineJSON], _ i: Int) -> EngineJSON { arg(a, i).flatMap { $0.fields != nil ? $0 : nil } ?? .object([]) }

    func addScriptElement(_ g: BIMGeometry, _ opts: EngineJSON, label: String) throws -> EngineJSON {
        let level = ScriptJSON.int(opts["level"])
        if let l = level, editor.doc.level(l) == nil { throw ScriptJSON.fail("level \(l) does not exist") }
        let spec = ScriptJSON.ElementSpec(geometry: g, level: level, layer: ScriptJSON.string(opts["layer"]), material: ScriptJSON.string(opts["material"]),
                                          name: ScriptJSON.string(opts["name"]) ?? "", props: ScriptJSON.stringDict(opts["props"]))
        var id = 0
        editor.transaction(label) { d in id = ScriptJSON.add(spec, to: &d) }
        return .int(id)
    }

    func scriptWall(_ a: [EngineJSON]) throws -> EngineJSON {
        let x1 = ScriptJSON.double(arg(a, 0)) ?? 0, y1 = ScriptJSON.double(arg(a, 1)) ?? 0
        let x2 = ScriptJSON.double(arg(a, 2)) ?? 0, y2 = ScriptJSON.double(arg(a, 3)) ?? 0
        let p0 = Vec2(x1, y1), p1 = Vec2(x2, y2)
        let opts = options(a, 4)
        guard p0.distance(to: p1) > 1e-6 else { throw ScriptJSON.fail("wall start and end coincide") }
        let s = editor.settings
        let just = WallJustification(rawValue: ScriptJSON.string(opts["justification"]) ?? "") ?? s.wallJustification
        let w = WallGeom(start: p0, end: p1, thickness: ScriptJSON.double(opts["thickness"]) ?? s.wallThickness,
                         height: ScriptJSON.double(opts["height"]) ?? s.wallHeight, baseOffset: ScriptJSON.double(opts["baseOffset"]) ?? 0,
                         justification: just, bulge: ScriptJSON.double(opts["bulge"]) ?? 0, wallType: ScriptJSON.string(opts["wallType"]))
        return try addScriptElement(.wall(w), opts, label: "Script Wall")
    }

    func scriptOpening(_ kind: OpeningKind, _ a: [EngineJSON]) throws -> EngineJSON {
        let wallID = ScriptJSON.int(arg(a, 0)) ?? -1
        let offset = ScriptJSON.double(arg(a, 1)) ?? 0
        var opts = options(a, 2)
        guard let host = editor.doc.element(wallID), case .wall(let wg) = host.geometry else { throw ScriptJSON.fail("\(wallID) is not a wall") }
        let isWin = kind == .window
        let width = ScriptJSON.double(opts["width"]) ?? (isWin ? 1200 : 900)
        guard offset - width / 2 >= -1e-6, offset + width / 2 <= wg.length + 1e-6 else {
            throw ScriptJSON.fail("opening does not fit in the wall (length \(fmt(wg.length)))")
        }
        var g = OpeningGeom(kind: kind, hostWall: wallID, offset: offset, width: width,
                            height: ScriptJSON.double(opts["height"]) ?? (isWin ? 1200 : 2100),
                            sill: ScriptJSON.double(opts["sill"]) ?? (isWin ? 900 : 0))
        g.flipHand = ScriptJSON.bool(opts["flipHand"]) ?? false
        g.flipFacing = ScriptJSON.bool(opts["flipFacing"]) ?? false
        if let s = ScriptJSON.string(opts["style"]) {
            if let d = DoorStyle(rawValue: s) { g.doorStyle = d }
            if let w = WindowStyle(rawValue: s) { g.windowStyle = w }
        }
        opts = ScriptJSON.setting(opts, "level", .int(host.level))
        let label = "Script " + kind.rawValue.capitalized
        return try addScriptElement(.opening(g), opts, label: label)
    }

    func scriptSlab(_ a: [EngineJSON]) throws -> EngineJSON {
        let pts = ScriptJSON.points(arg(a, 0))
        let opts = options(a, 1)
        guard pts.count >= 3 else { throw ScriptJSON.fail("a slab needs at least 3 points") }
        let holes = (opts["holes"]?.arrayValue ?? []).map { ScriptJSON.points($0) }
        let g = SlabGeom(boundary: pts, holes: holes, thickness: ScriptJSON.double(opts["thickness"]) ?? 200, topOffset: ScriptJSON.double(opts["topOffset"]) ?? 0)
        return try addScriptElement(.slab(g), opts, label: "Script Slab")
    }

    func scriptRoom(_ a: [EngineJSON]) throws -> EngineJSON {
        let pts = ScriptJSON.points(arg(a, 0))
        let name = arg(a, 1)?.stringValue ?? "Room"
        let opts = options(a, 2)
        guard pts.count >= 3 else { throw ScriptJSON.fail("a room needs at least 3 points") }
        let number = opts["number"].flatMap { $0.isNull ? nil : $0.stringValue } ?? ""
        let g = SpaceGeom(boundary: pts, name: name, number: number, height: ScriptJSON.double(opts["height"]) ?? 2700)
        return try addScriptElement(.space(g), opts, label: "Script Room")
    }

    func scriptColumn(_ a: [EngineJSON]) throws -> EngineJSON {
        let p = Vec2(ScriptJSON.double(arg(a, 0)) ?? 0, ScriptJSON.double(arg(a, 1)) ?? 0)
        let opts = options(a, 2)
        let size = ScriptJSON.double(opts["size"])
        let g = ColumnGeom(position: p, width: ScriptJSON.double(opts["width"]) ?? size ?? 300, depth: ScriptJSON.double(opts["depth"]) ?? size ?? 300,
                           height: ScriptJSON.double(opts["height"]) ?? 3000, rotation: rad(ScriptJSON.double(opts["rotation"]) ?? 0),
                           round: ScriptJSON.bool(opts["round"]) ?? false)
        return try addScriptElement(.column(g), opts, label: "Script Column")
    }

    /// archi.registerCommand(name, fnName, options, source, scriptName): the script becomes a run-time plugin
    /// (PluginRegistry, SCR-006); running the command asks the shell to evaluate the source and call the function.
    func registerScriptCommand(_ a: [EngineJSON]) throws -> EngineJSON {
        let name = (arg(a, 0)?.stringValue ?? "").uppercased()
        guard !name.isEmpty else { throw ScriptJSON.fail("registerCommand(name, function[, options]) needs a command name") }
        let fname = arg(a, 1)?.stringValue ?? ""
        guard !fname.isEmpty else { throw ScriptJSON.fail("registerCommand: pass a named global function (or its name) for \(name)") }
        let opts = options(a, 2)
        let aliases = (opts["aliases"]?.arrayValue ?? []).compactMap { $0.stringValue?.uppercased() }
        let cmd = PluginCommand(name: name, aliases: aliases, summary: ScriptJSON.string(opts["summary"]) ?? "", function: fname,
                                category: ScriptJSON.string(opts["category"]) ?? "Scripts", modifies: ScriptJSON.bool(opts["modifies"]) ?? true)
        let source = arg(a, 3)?.stringValue ?? ""
        let scriptName = arg(a, 4)?.stringValue ?? "console.js"
        EngineSession.installPluginEvaluator()
        let n = try PluginRegistry.shared.registerScriptCommand(cmd, source: source, sourceURL: URL(fileURLWithPath: scriptName), into: editor.registry)
        markChanged("commands")
        return .string(n)
    }

    /// Sessions by editor, for the plugin evaluator (the registry calls back with the editor running the command).
    static var sessions: [ObjectIdentifier: EngineSession] = [:]
    static var evaluatorInstalled = false

    /// Plugin commands (user plugins and script-registered commands) run their JavaScript in the shell.
    static func installPluginEvaluator() {
        guard !evaluatorInstalled else { return }
        evaluatorInstalled = true
        PluginRegistry.evaluator = { plugin, function, ed in
            guard let s = EngineSession.sessions[ObjectIdentifier(ed)] else { throw CommandError.invalid("No shell to run the plugin in.") }
            var o = EngineObject()
            o.set("source", plugin.source)
            o.set("function", function)
            o.set("plugin", plugin.manifest.name)
            o.set("script", plugin.manifest.main)
            s.hostNotify("runScript", o)
        }
    }

    /// Loads the user plugins (as the Mac app does at launch) and routes their commands to the shell.
    public func loadPlugins() {
        EngineSession.sessions[ObjectIdentifier(editor)] = self
        EngineSession.installPluginEvaluator()
        _ = PluginRegistry.shared.reload()
        _ = PluginRegistry.shared.register(into: editor.registry)
    }

    // MARK: agent.call (the Mac local agent server's methods)

    func agentCall(_ p: EngineJSON) async throws -> EngineJSON {
        guard let method = p["method"]?.stringValue else { throw EngineError.params("missing 'method'") }
        let a = p["params"] ?? .object([])
        do { return try await agentMethod(method, a) }
        catch let e as EngineError { throw e }
        catch { throw scriptError(error) }
    }

    func need(_ a: EngineJSON, _ k: String) throws -> EngineJSON {
        guard let v = a[k], !v.isNull else { throw EngineError(EngineError.invalidParams, "missing or invalid parameter '\(k)'") }
        return v
    }

    func expand(_ path: String) -> URL { url(path) }

    func agentMethod(_ method: String, _ a: EngineJSON) async throws -> EngineJSON {
        switch method {
        case "list_methods": return EngineAgent.methodList()
        case "run_command":
            guard let text = try need(a, "command").stringValue else { throw EngineError.params("missing 'command'") }
            return ScriptJSON.object([("log", EngineJSON.strings(await runLines(text)))])
        case "get_document": return ScriptJSON.documentJSON(editor.doc)
        case "get_document_summary": return ScriptJSON.summary(editor.doc)
        case "list_entities":
            var r = ScriptJSON.entities(editor.doc, type: ScriptJSON.string(a["type"]), layer: ScriptJSON.string(a["layer"]))
            if let lim = ScriptJSON.int(a["limit"]), lim >= 0, r.count > lim { r = Array(r.prefix(lim)) }
            return .array(r)
        case "list_elements":
            return .array(ScriptJSON.elements(editor.doc, type: ScriptJSON.string(a["type"]), level: ScriptJSON.int(a["level"])))
        case "add_entity", "add_entities":
            guard let e = a["entity"] ?? a["entities"] else { throw EngineError.params("missing parameter 'entity'") }
            let ids = try addEntities(.array(e.arrayValue ?? [e]), label: "Agent Add")
            return ScriptJSON.object([("ids", ids)])
        case "add_element", "add_elements":
            guard let e = a["element"] ?? a["elements"] else { throw EngineError.params("missing parameter 'element'") }
            let ids = try addElements(.array(e.arrayValue ?? [e]), label: "Agent Add Element")
            return ScriptJSON.object([("ids", ids)])
        case "update_entity", "update_element", "update":
            guard let id = ScriptJSON.int(a["id"]) else { throw EngineError.params("missing parameter 'id'") }
            let patch = try need(a, "patch")
            guard patch.fields != nil else { throw EngineError.params("missing or invalid parameter 'patch'") }
            try editor.transaction("Agent Update") { d in try ScriptJSON.patch(&d, id: id, patch) }
            return objectJSON(id)
        case "delete", "delete_entities":
            let ids = Set(ScriptJSON.ids(a["ids"]))
            guard !ids.isEmpty else { throw EngineError.params("missing parameter 'ids'") }
            return ScriptJSON.object([("deleted", .int(removeObjects(ids, label: "Agent Delete")))])
        case "select":
            let ids = ScriptJSON.ids(a["ids"])
            let doc = editor.doc
            editor.selection = Set(ids.filter { doc.contains($0) })
            return ScriptJSON.object([("selection", EngineJSON.ints(editor.selection.sorted()))])
        case "get_selection":
            return ScriptJSON.object([("selection", EngineJSON.ints(editor.selection.sorted()))])
        case "export":
            let format = try need(a, "format").stringValue ?? ""
            let path = try need(a, "path").stringValue ?? ""
            let u = try agentExport(format: format, path: path, a)
            return ScriptJSON.object([("path", .string(u.path))])
        case "list_commands": return commandList(category: ScriptJSON.string(a["category"]))
        case "undo": await cancelAndWait(); editor.undo(); return ScriptJSON.object([("ok", .bool(true))])
        case "redo": await cancelAndWait(); editor.redo(); return ScriptJSON.object([("ok", .bool(true))])
        case "list_resources": return ScriptJSON.fromAny(AgentResources.list(editor.doc))
        case "read_resource":
            let uri = try need(a, "uri").stringValue ?? ""
            let c = try AgentResources.read(uri, doc: editor.doc)
            return ScriptJSON.object([("uri", .string(c.uri)), ("mimeType", .string(c.mimeType)), ("text", .string(c.text))])
        case "list_prompts": return ScriptJSON.fromAny(AgentPrompts.definitions)
        case "get_prompt":
            let name = try need(a, "name").stringValue ?? ""
            let r = try AgentPrompts.get(name, arguments: ScriptJSON.stringDict(a["arguments"]), doc: editor.doc)
            return ScriptJSON.fromAny(r)
        case "list_tools":
            return ScriptJSON.fromAny(AgentTools.definitions + AgentExtraTools.mutatingDefinitions)
        case "call_tool":
            let name = try need(a, "name").stringValue ?? ""
            return try callAgentTool(name, a["arguments"] ?? .object([]))
        case "eval_js", "screenshot":
            throw EngineError(EngineError.methodNotFound, "\(method) is answered by the shell")
        default:
            throw EngineError(EngineError.methodNotFound, "Method not found: " + method)
        }
    }

    /// AgentTools (read-only) and AgentExtraTools (mutating: one undo step named "Agent <tool>").
    func callAgentTool(_ name: String, _ args: EngineJSON) throws -> EngineJSON {
        let dict = ScriptJSON.toDict(args)
        let base = baseDirectory
        let resolve: (String) -> URL = { p in
            let e = (p as NSString).expandingTildeInPath
            let chars = Array(e)
            let absolute = e.hasPrefix("/") || e.hasPrefix("\\") || (chars.count > 1 && chars[1] == ":")
            return absolute ? URL(fileURLWithPath: e) : base.appendingPathComponent(e)
        }
        if AgentExtraTools.mutatingNames.contains(name) {
            var result: Any = NSNull()
            try editor.transaction("Agent " + name) { d in result = try AgentExtraTools.mutate(name, dict, doc: &d, resolve: resolve) }
            return ScriptJSON.fromAny(result)
        }
        guard AgentTools.names.contains(name) else { throw EngineError.params("unknown tool " + name) }
        let r = try AgentTools.call(name, dict, doc: editor.doc, resolve: resolve)
        if name == "plan_svg", let svg = r as? String, let p = ScriptJSON.string(args["path"]) {
            let u = resolve(p)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try svg.write(to: u, atomically: true, encoding: .utf8)
        }
        return ScriptJSON.fromAny(r)
    }

    /// Writes the document in a format (agent `export`): paths are absolute or relative to the engine's folder.
    func agentExport(format: String, path: String, _ a: EngineJSON) throws -> URL {
        let u = url(path)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        let f = format.lowercased()
        if f == "csv" {
            let kind = ScriptJSON.string(a["kind"]) ?? "all"
            try ScheduleExporter.csv(doc: editor.doc, kind: kind).write(to: u, atomically: true, encoding: .utf8)
            return u
        }
        let level = ScriptJSON.int(a["level"]) ?? editor.doc.currentLevel
        try DocumentIO.write(editor.doc, to: u, format: f, level: level)
        return u
    }

}

/// The agent method table (list_methods), shared with the Windows shell's HTTP agent server.
public enum EngineAgent {
    public static let methods: [(String, String)] = [
        ("run_command", "{command} — run AutoCAD-style command line(s); returns {log}"),
        ("get_document", "full document as .archi JSON"),
        ("get_document_summary", "counts, layers, levels, bounds"),
        ("list_entities", "{type?, layer?} — 2D/3D drafting entities"),
        ("list_elements", "{type?, level?} — BIM elements"),
        ("add_entity", "{entity} (object or array) — returns {ids}"),
        ("add_element", "{element} (object or array) — returns {ids}"),
        ("update_entity", "{id, patch} — also works for elements"),
        ("delete", "{ids} — delete entities/elements"),
        ("select", "{ids}"), ("get_selection", ""),
        ("export", "{format: pdf|dxf|svg|obj|stl|glb|ifc|csv|archi, path, layout?, kind?}"),
        ("screenshot", "{width?, height?, level?, paper?} — base64 PNG of the 2D plan"),
        ("list_commands", "command names, aliases, summaries"),
        ("eval_js", "{code} — run JavaScript with the archi API"),
        ("undo", ""), ("redo", ""), ("list_methods", ""),
        ("list_resources", "document resources (summary, .archi JSON, takeoff, schedules, markups, plan SVG)"), ("read_resource", "{uri}"),
        ("list_prompts", "prompt templates"), ("get_prompt", "{name, arguments?}"),
        ("list_tools", "analysis and editing tools with input schemas (same as archi-cli --mcp)"), ("call_tool", "{name, arguments?} — editing tools are one undo step"),
    ]

    public static func methodList() -> EngineJSON {
        .array(methods.map { m in ScriptJSON.object([("name", .string(m.0)), ("params", .string(m.1))]) })
    }
}
