// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import Network
import Security
import ArchiCore

/// Local agent server: JSON-RPC 2.0 over HTTP/1.1 on 127.0.0.1 only, bearer-token protected.
/// See docs/AGENT-API.md.
final class AgentServer {
    static let shared = AgentServer()

    private(set) var isRunning = false
    private(set) var port: UInt16 = 47800
    /// Random per-launch secret; clients send `Authorization: Bearer <token>`.
    let token: String = AgentServer.makeToken()
    /// Last listener error (e.g. port in use), for the UI.
    private(set) var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.oanarina.archi.agent-server")
    private weak var model: AppModel?
    private var engine: ScriptEngine?
    static let maxRequestBytes = 32 << 20

    static var infoFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Oanarina Archi Tool", isDirectory: true).appendingPathComponent("agent.json")
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var g = SystemRandomNumberGenerator()
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &g) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Lifecycle

    @MainActor func start(model: AppModel, port: UInt16 = 47800) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port), port != 0 else { throw ArchiJSON.fail("invalid port \(port)") }
        self.model = model
        engine = ScriptEngine(model: model)
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let e):
                self.lastError = "Agent server failed: \(e.localizedDescription)"
                self.isRunning = false
                let msg = self.lastError!
                DispatchQueue.main.async { MainActor.assumeIsolated { self.model?.editor.print(msg) } }
                l.cancel()
                try? FileManager.default.removeItem(at: AgentServer.infoFileURL)
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
        self.port = port
        isRunning = true
        lastError = nil
        writeInfoFile()
        model.editor.print("Agent server listening on http://127.0.0.1:\(port)/rpc (token in \(AgentServer.infoFileURL.path))")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if isRunning { try? FileManager.default.removeItem(at: AgentServer.infoFileURL) }
        isRunning = false
    }

    private func writeInfoFile() {
        let url = AgentServer.infoFileURL
        let info: [String: Any] = ["port": Int(port), "token": token, "url": "http://127.0.0.1:\(port)/rpc",
                                   "pid": Int(ProcessInfo.processInfo.processIdentifier), "started": ISO8601DateFormatter().string(from: Date())]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            lastError = "Could not write \(url.path): \(error.localizedDescription)"
        }
    }

    // MARK: HTTP

    struct HTTPRequest {
        var method: String; var path: String; var headers: [String: String]; var body: Data
        /// Parses a complete request, or returns nil when more bytes are needed.
        static func parse(_ buf: Data) throws -> HTTPRequest? {
            guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if buf.count > 64 * 1024 { throw ArchiJSON.fail("headers too large") }
                return nil
            }
            guard let head = String(data: buf[buf.startIndex..<sep.lowerBound], encoding: .utf8) else { throw ArchiJSON.fail("bad headers") }
            var lines = head.components(separatedBy: "\r\n")
            let reqLine = lines.removeFirst().split(separator: " ")
            guard reqLine.count >= 2 else { throw ArchiJSON.fail("bad request line") }
            var headers: [String: String] = [:]
            for l in lines {
                guard let c = l.firstIndex(of: ":") else { continue }
                headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "0") ?? -1
            guard length >= 0, length <= AgentServer.maxRequestBytes else { throw ArchiJSON.fail("bad content length") }
            if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { throw ArchiJSON.fail("chunked bodies are not supported") }
            let bodyStart = sep.upperBound
            guard buf.count - (bodyStart - buf.startIndex) >= length else { return nil }
            let body = buf[bodyStart..<(bodyStart + length)]
            var path = String(reqLine[1])
            if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
            return HTTPRequest(method: String(reqLine[0]).uppercased(), path: path, headers: headers, body: Data(body))
        }
    }

    private func accept(_ c: NWConnection) {
        if case .hostPort(let host, _) = c.endpoint {
            let h = "\(host)"
            if !(h == "127.0.0.1" || h == "::1" || h.hasPrefix("127.") || h == "localhost" || h.hasSuffix("::1")) { c.cancel(); return }
        }
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { c.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            do {
                if let req = try HTTPRequest.parse(buf) { self.handle(req, c) }
                else if complete || error != nil { c.cancel() }
                else { self.receive(c, buf) }
            } catch {
                self.send(c, 400, ["error": error.localizedDescription])
            }
        }
    }

    private func send(_ c: NWConnection, _ status: Int, _ json: Any?) {
        let body = json.map { (try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed])) ?? Data() } ?? Data()
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed", 413: "Payload Too Large", 500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nServer: OanarinaArchiTool\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if !body.isEmpty { head += "Content-Type: application/json; charset=utf-8\r\n" }
        if status == 401 { head += "WWW-Authenticate: Bearer\r\n" }
        head += "Content-Length: \(body.count)\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var d: UInt8 = 0
        for i in 0..<x.count { d |= x[i] ^ y[i] }
        return d == 0
    }

    private func handle(_ req: HTTPRequest, _ c: NWConnection) {
        // DNS-rebinding protection: only loopback host names.
        if let host = req.headers["host"] {
            let name = host.hasPrefix("[") ? String(host.prefix { $0 != "]" }.dropFirst()) : String(host.split(separator: ":").first ?? "")
            guard ["127.0.0.1", "localhost", "::1"].contains(name.lowercased()) else { send(c, 403, ["error": "forbidden host"]); return }
        }
        switch (req.method, req.path) {
        case ("GET", "/health"), ("GET", "/"):
            send(c, 200, ["status": "ok", "app": "Oanarina Archi Tool", "rpc": "/rpc"])
        case ("POST", "/rpc"):
            let auth = req.headers["authorization"] ?? ""
            guard constantTimeEqual(auth, "Bearer \(token)") else { send(c, 401, ["error": "missing or invalid bearer token"]); return }
            guard let obj = try? JSONSerialization.jsonObject(with: req.body, options: [.fragmentsAllowed]) else {
                send(c, 200, AgentServer.rpcError(nil, -32700, "Parse error")); return
            }
            Task { @MainActor in
                let response: Any?
                if let batch = obj as? [Any] {
                    if batch.isEmpty { response = AgentServer.rpcError(nil, -32600, "Invalid Request") }
                    else {
                        var out: [Any] = []
                        for item in batch { if let r = await self.rpc(item) { out.append(r) } }
                        response = out.isEmpty ? nil : out
                    }
                } else {
                    response = await self.rpc(obj)
                }
                self.queue.async { if let response { self.send(c, 200, response) } else { self.send(c, 204, nil) } }
            }
        case (_, "/rpc"), (_, "/health"):
            send(c, 405, ["error": "method not allowed"])
        default:
            send(c, 404, ["error": "not found"])
        }
    }

    // MARK: JSON-RPC

    struct RPCError: Error { let code: Int; let message: String }

    static func rpcError(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    @MainActor private func rpc(_ item: Any) async -> Any? {
        guard let req = item as? [String: Any], req["jsonrpc"] as? String == "2.0", let method = req["method"] as? String else {
            return AgentServer.rpcError((item as? [String: Any])?["id"], -32600, "Invalid Request")
        }
        let id = req["id"]
        let params = req["params"] as? [String: Any] ?? [:]
        do {
            let result = try await call(method, params)
            return id == nil ? nil : ["jsonrpc": "2.0", "id": id!, "result": result]
        } catch let e as RPCError {
            return id == nil ? nil : AgentServer.rpcError(id, e.code, e.message)
        } catch {
            return id == nil ? nil : AgentServer.rpcError(id, -32000, (error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    static let methods: [(String, String)] = [
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

    @MainActor private func call(_ method: String, _ p: [String: Any]) async throws -> Any {
        guard let model else { throw RPCError(code: -32001, message: "no document is open") }
        let ed = model.editor
        func need<T>(_ k: String, _ t: T.Type) throws -> T {
            guard let v = p[k] as? T else { throw RPCError(code: -32602, message: "missing or invalid parameter '\(k)'") }
            return v
        }
        switch method {
        case "list_methods":
            return AgentServer.methods.map { ["name": $0.0, "params": $0.1] }
        case "run_command":
            let text = try need("command", String.self)
            if !ed.isIdle { ed.cancel(); await ed.waitIdle() }
            var log: [String] = []
            for line in text.components(separatedBy: .newlines) { log += await ed.run(line) }
            return ["log": log]
        case "get_document":
            return ArchiJSON.documentJSON(ed.doc)
        case "get_document_summary":
            return ArchiJSON.summary(ed.doc)
        case "list_entities":
            var r = ArchiJSON.entities(ed.doc, type: p["type"] as? String, layer: p["layer"] as? String)
            if let lim = ArchiJSON.int(p["limit"]), lim >= 0, r.count > lim { r = Array(r.prefix(lim)) }
            return r
        case "list_elements":
            return ArchiJSON.elements(ed.doc, type: p["type"] as? String, level: ArchiJSON.int(p["level"]))
        case "add_entity", "add_entities":
            guard let e = p["entity"] ?? p["entities"] else { throw RPCError(code: -32602, message: "missing parameter 'entity'") }
            let list = (e as? [Any]) ?? [e]
            var ids: [EntityID] = []
            try ed.transaction("Agent Add") { d in for item in list { ids.append(d.add(try ArchiJSON.entity(from: item, doc: d))) } }
            return ["ids": ids]
        case "add_element", "add_elements":
            guard let e = p["element"] ?? p["elements"] else { throw RPCError(code: -32602, message: "missing parameter 'element'") }
            let list = (e as? [Any]) ?? [e]
            var ids: [EntityID] = []
            try ed.transaction("Agent Add Element") { d in for item in list { ids.append(ArchiJSON.add(try ArchiJSON.element(from: item, doc: d), to: &d)) } }
            return ["ids": ids]
        case "update_entity", "update_element", "update":
            guard let id = ArchiJSON.int(p["id"]) else { throw RPCError(code: -32602, message: "missing parameter 'id'") }
            let patch = try need("patch", [String: Any].self)
            try ed.transaction("Agent Update") { d in try ArchiJSON.patch(&d, id: id, patch) }
            return ed.doc.entity(id).map { ArchiJSON.object($0) } ?? ed.doc.element(id).map { ArchiJSON.object($0) } ?? NSNull()
        case "delete", "delete_entities":
            let ids = Set(ArchiJSON.ids(p["ids"]))
            guard !ids.isEmpty else { throw RPCError(code: -32602, message: "missing parameter 'ids'") }
            let before = ed.doc.entities.count + ed.doc.elements.count
            ed.transaction("Agent Delete") { $0.remove(ids: ids) }
            ed.selection.subtract(ids)
            return ["deleted": before - ed.doc.entities.count - ed.doc.elements.count]
        case "select":
            let ids = ArchiJSON.ids(p["ids"])
            ed.selection = Set(ids.filter { ed.doc.contains($0) })
            return ["selection": Array(ed.selection).sorted()]
        case "get_selection":
            return ["selection": Array(ed.selection).sorted()]
        case "export":
            let format = try need("format", String.self)
            let path = try need("path", String.self)
            let url = try AgentServer.export(model: model, format: format, path: path, options: p)
            return ["path": url.path]
        case "screenshot":
            let w = ArchiJSON.int(p["width"]) ?? 1600, h = ArchiJSON.int(p["height"]) ?? 1200
            let level = p["level"] is NSNull ? nil : (ArchiJSON.int(p["level"]) ?? ed.doc.currentLevel)
            guard let png = Plotter.planPNG(doc: ed.doc, level: level, width: w, height: h, paper: p["paper"] as? Bool ?? false, highlight: ed.selection) else {
                throw RPCError(code: -32000, message: "could not render")
            }
            return ["mimeType": "image/png", "width": min(max(w, 16), 8192), "height": min(max(h, 16), 8192), "image": png.base64EncodedString()]
        case "list_commands":
            return CommandRegistry.shared.sorted.map { ["name": $0.name, "aliases": $0.aliases, "category": $0.category, "summary": $0.summary] }
        case "eval_js":
            let code = try need("code", String.self)
            let eng = engine ?? ScriptEngine(model: model)
            engine = eng
            let r = await eng.evaluate(code)
            return ["output": r.output, "value": r.value.map { $0 as Any } ?? NSNull(), "error": r.error.map { $0 as Any } ?? NSNull()]
        // Resources, prompts and tools shared with archi-cli --mcp.
        case "list_resources": return AgentResources.list(ed.doc)
        case "read_resource":
            let c = try AgentResources.read(try need("uri", String.self), doc: ed.doc)
            return ["uri": c.uri, "mimeType": c.mimeType, "text": c.text]
        case "list_prompts": return AgentPrompts.definitions
        case "get_prompt":
            var args: [String: String] = [:]
            for (k, v) in (p["arguments"] as? [String: Any]) ?? [:] { args[k] = "\(v)" }
            return try AgentPrompts.get(try need("name", String.self), arguments: args, doc: ed.doc)
        case "list_tools": return AgentTools.definitions + AgentExtraTools.mutatingDefinitions
        case "call_tool":
            let name = try need("name", String.self)
            let a = p["arguments"] as? [String: Any] ?? [:]
            let expand: (String) -> URL = { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            if AgentExtraTools.mutatingNames.contains(name) {
                var result: Any = NSNull()
                try ed.transaction("Agent \(name)") { d in result = try AgentExtraTools.mutate(name, a, doc: &d, resolve: expand) }
                return result
            }
            guard AgentTools.names.contains(name) else { throw RPCError(code: -32602, message: "unknown tool \(name)") }
            return try AgentTools.call(name, a, doc: ed.doc, resolve: expand)
        case "undo": ed.undo(); return ["ok": true]
        case "redo": ed.redo(); return ["ok": true]
        default:
            throw RPCError(code: -32601, message: "Method not found: \(method)")
        }
    }

    /// Writes the document in the given format. Paths must be absolute (`~` is expanded).
    @MainActor static func export(model: AppModel, format: String, path: String, options p: [String: Any] = [:]) throws -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw ArchiJSON.fail("path must be absolute") }
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let doc = model.doc
        func text(_ s: String) throws { try s.write(to: url, atomically: true, encoding: .utf8) }
        switch format.lowercased() {
        case "pdf":
            let layout = ArchiJSON.int(p["layout"])
            try Plotter.writePDF(doc: doc, to: url, layoutIndex: layout, level: ArchiJSON.int(p["level"]) ?? doc.currentLevel)
        case "dxf": try text(DXFWriter.write(doc))
        case "svg":
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: ArchiJSON.int(p["level"]) ?? doc.currentLevel))
            var b = entries.unionBounds
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            try text(SVGExporter.export(entries: entries, bounds: b.expanded(by: max(b.width, b.height) * 0.02), background: nil,
                                        pixelsPerUnit: ArchiJSON.double(p["pixelsPerUnit"]) ?? 1))
        case "obj":
            let r = OBJExporter.export(MeshBuilder.build(doc: doc), materials: doc.materials, mtlFileName: url.deletingPathExtension().lastPathComponent + ".mtl", unitMM: doc.units.mm)
            try text(r.obj)
            try r.mtl.write(to: url.deletingPathExtension().appendingPathExtension("mtl"), atomically: true, encoding: .utf8)
        case "stl": try text(STLExporter.export(MeshBuilder.build(doc: doc), name: doc.info.name))
        case "glb", "gltf": try GLTFExporter.exportGLB(MeshBuilder.build(doc: doc), materials: doc.materials, unitMM: doc.units.mm).write(to: url)
        case "ifc": try text(IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc)))
        case "csv": try text(ScheduleExporter.csv(doc: doc, kind: p["kind"] as? String ?? "all"))
        case "archi": try ArchiFile.encode(doc).write(to: url)
        default: throw ArchiJSON.fail("unsupported format \(format)")
        }
        return url
    }
}
