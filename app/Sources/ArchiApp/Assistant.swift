// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import Security
import ArchiCore

/// AI assistant (SCR-027) with a cloud provider (Anthropic Messages API) or a local model (SCR-035: Ollama or any
/// OpenAI-compatible server on this Mac, nothing leaves the machine). The model answers with command lines through a
/// `run_commands` tool (or an ```archi fenced block for models without tools). Commands are tried on a copy of the
/// drawing first; bulk changes need confirmation; then they run on the drawing as normal, undoable commands.
enum AssistantProvider: String, CaseIterable, Codable {
    case anthropic = "Claude (Anthropic API)", local = "Local model (Ollama / OpenAI-compatible)"
}

struct AssistantConfig: Equatable {
    var provider: AssistantProvider = .local
    var model = "llama3.1"
    var endpoint = "http://127.0.0.1:11434/v1/chat/completions"
    /// Bulk threshold: more changed objects than this (or more than `deleteLimit` deletions) asks for confirmation.
    var bulkLimit = 25
    var deleteLimit = 5

    static let defaultsKey = "assistant.config"
    static func load() -> AssistantConfig {
        var c = AssistantConfig()
        let d = UserDefaults.standard
        if let p = d.string(forKey: defaultsKey + ".provider").flatMap(AssistantProvider.init(rawValue:)) { c.provider = p }
        if let m = d.string(forKey: defaultsKey + ".model"), !m.isEmpty { c.model = m }
        if let e = d.string(forKey: defaultsKey + ".endpoint"), !e.isEmpty { c.endpoint = e }
        return c
    }
    func save() {
        let d = UserDefaults.standard
        d.set(provider.rawValue, forKey: AssistantConfig.defaultsKey + ".provider")
        d.set(model, forKey: AssistantConfig.defaultsKey + ".model")
        d.set(endpoint, forKey: AssistantConfig.defaultsKey + ".endpoint")
    }
    static let anthropicURL = "https://api.anthropic.com/v1/messages"
    static let defaultClaudeModel = "claude-sonnet-4-5"
}

/// API key in the login keychain (never in the drawing or preferences).
enum AssistantKeychain {
    static let service = "com.oanarina.architool.assistant"
    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "anthropic",
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func write(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "anthropic"]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base; add[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

struct AssistantMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, system }
    let id = UUID()
    var role: Role
    var text: String
    var commands: [String] = []
}

/// Request building, reply parsing and the document context (pure functions, tested by APPSELFTEST).
@MainActor
enum AssistantProtocol {
    static let toolName = "run_commands"
    static let toolDescription = "Runs Oanarina Archi Tool command lines on the open drawing, in order. Each string is one command line exactly as typed on the command line, e.g. \"LINE 0,0 1000,0 \", \"WALL 0,0 5000,0 \" or \"ERASE #12 \". Inputs are separated by spaces; a trailing space ends the command."

    /// Compact description of the drawing for the system prompt.
    static func context(_ doc: ArchiDocument, selection: Set<EntityID>) -> String {
        var byType: [String: Int] = [:]
        for e in doc.entities { byType[String(describing: e.geometry).split(separator: "(").first.map(String.init) ?? "entity", default: 0] += 1 }
        var byEl: [String: Int] = [:]
        for e in doc.elements { byEl[e.typeName, default: 0] += 1 }
        let levels = doc.levels.map { "\($0.name) (id \($0.id), elev \(fmt($0.elevation, 0)))" }.joined(separator: ", ")
        var s = "Drawing: \(doc.info.name). Units: \(doc.units) (\(fmt(doc.units.mm, 4)) mm per unit). Current layer: \(doc.currentLayer). Current level id: \(doc.currentLevel).\n"
        s += "Levels: \(levels.isEmpty ? "none" : levels).\n"
        s += "Layers: \(doc.layers.prefix(60).map(\.name).joined(separator: ", ")).\n"
        s += "Entities: \(byType.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")).\n"
        s += "Building elements: \(byEl.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")).\n"
        s += "Selection: \(selection.isEmpty ? "none" : selection.sorted().prefix(40).map { "#\($0)" }.joined(separator: " ")).\n"
        return s
    }

    static func systemPrompt(_ doc: ArchiDocument, selection: Set<EntityID>, registry: CommandRegistry = .shared) -> String {
        let cats = Dictionary(grouping: registry.sorted.filter { !$0.summary.hasPrefix("System variable") }, by: \.category)
        let list = cats.keys.sorted().map { k in "\(k): " + cats[k]!.map(\.name).joined(separator: " ") }.joined(separator: "\n")
        return """
        You are the assistant inside Oanarina Archi Tool, a macOS CAD/BIM application with an AutoCAD-style command line. \
        Make changes only by calling \(toolName) with command lines (or, if you cannot call tools, put them one per line in a ```archi fenced block). \
        Coordinates are x,y in drawing units; @dx,dy is relative; d<angle is polar; #ID picks an object by id. End each command with a space. \
        Answer questions about the drawing in plain text. Keep edits minimal and explain what you did.
        \(context(doc, selection: selection))
        Commands by category:
        \(list)
        """
    }

    /// Anthropic Messages API body.
    static func anthropicBody(model: String, system: String, messages: [AssistantMessage]) -> [String: Any] {
        [
            "model": model, "max_tokens": 2048, "system": system,
            "messages": messages.filter { $0.role != .system }.map { ["role": $0.role.rawValue, "content": $0.text] },
            "tools": [["name": toolName, "description": toolDescription,
                       "input_schema": ["type": "object", "properties": ["commands": ["type": "array", "items": ["type": "string"]]], "required": ["commands"]]]],
        ]
    }

    /// OpenAI-compatible chat completions body (Ollama, LM Studio, llama.cpp server…).
    static func openAIBody(model: String, system: String, messages: [AssistantMessage]) -> [String: Any] {
        [
            "model": model, "stream": false,
            "messages": [["role": "system", "content": system]] + messages.filter { $0.role != .system }.map { ["role": $0.role.rawValue, "content": $0.text] },
            "tools": [["type": "function", "function": ["name": toolName, "description": toolDescription,
                                                        "parameters": ["type": "object", "properties": ["commands": ["type": "array", "items": ["type": "string"]]], "required": ["commands"]]]]],
        ]
    }

    /// Text and command lines of a reply from either API; ```archi blocks count as commands too.
    static func parse(_ data: Data) -> (text: String, commands: [String])? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var text = "", cmds: [String] = []
        if let content = obj["content"] as? [[String: Any]] {           // Anthropic
            for b in content {
                if b["type"] as? String == "text", let t = b["text"] as? String { text += t }
                if b["type"] as? String == "tool_use", b["name"] as? String == toolName, let input = b["input"] as? [String: Any], let c = input["commands"] as? [String] { cmds += c }
            }
        } else if let choices = obj["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any] {   // OpenAI-compatible
            text = msg["content"] as? String ?? ""
            for call in msg["tool_calls"] as? [[String: Any]] ?? [] {
                guard let f = call["function"] as? [String: Any], f["name"] as? String == toolName else { continue }
                if let s = f["arguments"] as? String, let d = s.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = a["commands"] as? [String] { cmds += c }
                else if let a = f["arguments"] as? [String: Any], let c = a["commands"] as? [String] { cmds += c }
            }
        } else if let err = obj["error"] as? [String: Any] {
            return ("Error: \(err["message"] as? String ?? "unknown")", [])
        } else { return nil }
        let fenced = fencedCommands(text)
        if cmds.isEmpty { cmds = fenced }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), cmds.map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    static func fencedCommands(_ text: String) -> [String] {
        var out: [String] = [], inBlock = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { if inBlock { inBlock = false } else if t.lowercased().hasPrefix("```archi") || t.lowercased().hasPrefix("```commands") { inBlock = true }; continue }
            if inBlock, !t.isEmpty { out.append(line.hasSuffix(" ") ? line : line + " ") }
        }
        return out
    }
}

/// What a list of command lines would change, measured on a copy of the drawing.
struct AssistantImpact: Equatable {
    var added = 0, removed = 0, modified = 0
    var output: [String] = []
    var total: Int { added + removed + modified }
    func isBulk(_ c: AssistantConfig) -> Bool { total > c.bulkLimit || removed > c.deleteLimit }
    var summary: String { "\(added) added, \(modified) modified, \(removed) deleted" }

    static func diff(_ a: ArchiDocument, _ b: ArchiDocument) -> AssistantImpact {
        var r = AssistantImpact()
        let ea = Dictionary(a.entities.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x }), eb = Dictionary(b.entities.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let la = Dictionary(a.elements.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x }), lb = Dictionary(b.elements.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        for (k, v) in eb { if let o = ea[k] { if o != v { r.modified += 1 } } else { r.added += 1 } }
        for k in ea.keys where eb[k] == nil { r.removed += 1 }
        for (k, v) in lb { if let o = la[k] { if o != v { r.modified += 1 } } else { r.added += 1 } }
        for k in la.keys where lb[k] == nil { r.removed += 1 }
        return r
    }

    /// Runs the commands on a scratch editor holding a copy of the drawing.
    @MainActor static func assess(_ commands: [String], doc: ArchiDocument, selection: Set<EntityID> = []) async -> AssistantImpact {
        let scratch = Editor(document: doc)
        scratch.selection = selection
        var out: [String] = []
        for c in commands { out += await scratch.run(c) }
        var r = diff(doc, scratch.doc)
        r.output = out
        return r
    }
}

/// Chat state of one document window.
@MainActor
final class AssistantSession: ObservableObject {
    @Published var messages: [AssistantMessage] = []
    @Published var busy = false
    @Published var config = AssistantConfig.load()
    /// Commands waiting for confirmation (bulk change) and their measured impact.
    @Published var pending: (commands: [String], impact: AssistantImpact)?
    weak var model: AppModel?
    init(model: AppModel) { self.model = model }

    func send(_ text: String) {
        guard let model, !text.trimmingCharacters(in: .whitespaces).isEmpty, !busy else { return }
        messages.append(AssistantMessage(role: .user, text: text))
        busy = true
        let system = AssistantProtocol.systemPrompt(model.doc, selection: model.editor.selection)
        let cfg = config
        let history = messages
        Task { @MainActor in
            defer { self.busy = false }
            do {
                let data = try await AssistantSession.request(cfg, system: system, messages: history)
                guard let reply = AssistantProtocol.parse(data) else { self.messages.append(AssistantMessage(role: .system, text: "Unreadable reply from the model.")); return }
                self.messages.append(AssistantMessage(role: .assistant, text: reply.text.isEmpty ? "(commands only)" : reply.text, commands: reply.commands))
                if !reply.commands.isEmpty { await self.propose(reply.commands) }
            } catch {
                self.messages.append(AssistantMessage(role: .system, text: "Request failed: \(error.localizedDescription)"))
            }
        }
    }

    /// Local models must run on this Mac (the drawing never leaves it).
    nonisolated static func isLocalEndpoint(_ s: String) -> Bool {
        guard let u = URL(string: s), let host = u.host?.lowercased() else { return false }
        return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }

    static func request(_ c: AssistantConfig, system: String, messages: [AssistantMessage]) async throws -> Data {
        var req: URLRequest
        switch c.provider {
        case .anthropic:
            guard let key = AssistantKeychain.read(), !key.isEmpty else { throw CommandError.invalid("Add your Anthropic API key in the assistant settings.") }
            req = URLRequest(url: URL(string: AssistantConfig.anthropicURL)!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.httpBody = try JSONSerialization.data(withJSONObject: AssistantProtocol.anthropicBody(model: c.model, system: system, messages: messages))
        case .local:
            guard isLocalEndpoint(c.endpoint), let u = URL(string: c.endpoint) else {
                throw CommandError.invalid("The local model endpoint must be on this Mac (localhost).")
            }
            req = URLRequest(url: u)
            req.httpBody = try JSONSerialization.data(withJSONObject: AssistantProtocol.openAIBody(model: c.model, system: system, messages: messages))
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 120
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    /// Measures the change on a copy; runs it directly or waits for confirmation when it is a bulk change.
    func propose(_ commands: [String]) async {
        guard let model else { return }
        let impact = await AssistantImpact.assess(commands, doc: model.doc, selection: model.editor.selection)
        if impact.isBulk(config) {
            pending = (commands, impact)
            messages.append(AssistantMessage(role: .system, text: "This would change many objects (\(impact.summary)). Apply or discard?"))
        } else {
            await apply(commands)
        }
    }

    func apply(_ commands: [String]) async {
        guard let model else { return }
        pending = nil
        var out: [String] = []
        for c in commands { out += await model.editor.run(c) }
        messages.append(AssistantMessage(role: .system, text: "Ran \(commands.count) command(s) — undo with ⌘Z." + (out.isEmpty ? "" : "\n" + out.suffix(6).joined(separator: "\n"))))
    }

    func discard() { pending = nil; messages.append(AssistantMessage(role: .system, text: "Changes discarded.")) }
}

enum AssistantWindow {
    @MainActor private static var windows: [ObjectIdentifier: NSWindow] = [:]
    @MainActor static var sessions: [ObjectIdentifier: AssistantSession] = [:]
    @MainActor static func session(_ m: AppModel) -> AssistantSession {
        let k = ObjectIdentifier(m)
        if let s = sessions[k] { return s }
        let s = AssistantSession(model: m); sessions[k] = s; return s
    }
    @MainActor static func show(model: AppModel) {
        let key = ObjectIdentifier(model)
        if let w = windows[key] { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Assistant — \(model.displayName)"
        w.isReleasedWhenClosed = false
        w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: AssistantPanel(session: session(model)).preferredColorScheme(Theme.colorScheme))
        w.center(); w.makeKeyAndOrderFront(nil)
        windows[key] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = windows.removeValue(forKey: key) }
        }
    }
}

struct AssistantPanel: View {
    @ObservedObject var session: AssistantSession
    @State private var input = ""
    @State private var showSettings = false
    @State private var key = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text(session.config.provider == .local ? "Local: \(session.config.model)" : "Claude: \(session.config.model)").font(Theme.fontBold)
                Spacer()
                Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Provider, model and key")
            }.padding(8)
            if showSettings { settings.padding(.horizontal, 8).padding(.bottom, 8) }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.messages) { m in bubble(m).id(m.id) }
                        if session.busy { ProgressView().controlSize(.small) }
                    }.padding(10)
                }
                .onChange(of: session.messages.count) { if let l = session.messages.last { proxy.scrollTo(l.id, anchor: .bottom) } }
            }
            if let p = session.pending {
                HStack {
                    Text("Bulk change: \(p.impact.summary)").font(Theme.fontSmall)
                    Spacer()
                    Button("Discard") { session.discard() }
                    Button("Apply") { Task { await session.apply(p.commands) } }.keyboardShortcut(.defaultAction)
                }.padding(8).background(Theme.accent.opacity(0.18))
            }
            Divider()
            HStack {
                TextField("Ask or describe a change (e.g. “add a 5 m wall from 0,0 to the east”)", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    .onSubmit { let t = input; input = ""; session.send(t) }
                Button { let t = input; input = ""; session.send(t) } label: { Image(systemName: "paperplane.fill") }
                    .disabled(session.busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(8)
        }
        .font(Theme.font).foregroundStyle(Theme.text).background(Theme.panel)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Provider", selection: $session.config.provider) { ForEach(AssistantProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Model", text: $session.config.model)
            if session.config.provider == .local {
                TextField("Endpoint (localhost)", text: $session.config.endpoint)
                Text("Runs on this Mac: the drawing context never leaves it. Ollama: `ollama serve`, then pull a model with tool support.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            } else {
                SecureField("Anthropic API key (stored in the keychain)", text: $key)
                Text("The drawing summary and your messages are sent to Anthropic.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }
            HStack {
                Stepper("Confirm above \(session.config.bulkLimit) changes", value: $session.config.bulkLimit, in: 1...500)
                Spacer()
                Button("Save") {
                    if session.config.provider == .anthropic && session.config.model == "llama3.1" { session.config.model = AssistantConfig.defaultClaudeModel }
                    session.config.save(); if !key.isEmpty { AssistantKeychain.write(key); key = "" }; showSettings = false
                }
            }
        }
    }

    private func bubble(_ m: AssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(m.text).textSelection(.enabled)
            if !m.commands.isEmpty {
                Text(m.commands.joined(separator: "\n")).font(Theme.mono).foregroundStyle(Theme.textDim).textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(m.role == .user ? Theme.accent.opacity(0.16) : (m.role == .system ? Theme.hover : Theme.field)))
    }
}

// MARK: - Render prompts (SCR-032)

/// Prompt-based render styling: words of a description map to render settings (time of day, sky, shadows, colour,
/// exposure, lens, resolution, clay). An assistant reply in JSON (keys as in `RenderPreset`) is accepted too.
enum RenderPrompt {
    static func apply(_ prompt: String, to s: inout RenderSettings) -> [String] {
        let p = prompt.lowercased()
        var applied: [String] = []
        func has(_ words: String...) -> Bool { words.contains { p.contains($0) } }
        func hour(_ h: Int, _ m: Int = 0) {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: s.date); c.hour = h; c.minute = m
            if let d = Calendar.current.date(from: c) { s.date = d }
        }
        if has("sunset", "golden hour", "dusk", "evening") { s.environment = .sunset; s.whiteBalance = 5200; hour(19, 30); applied.append("sunset sky, 19:30, warm") }
        else if has("sunrise", "dawn", "morning") { s.environment = .clearSky; hour(8); s.whiteBalance = 5600; applied.append("morning sun 08:00") }
        else if has("noon", "midday") { s.environment = .clearSky; hour(12); applied.append("noon sun") }
        if has("night", "nighttime") { s.environment = .night; hour(22); s.exposure += 0.6; applied.append("night") }
        if has("overcast", "cloudy", "grey sky", "gray sky") { s.environment = .overcast; s.shadowSoftness = 14; applied.append("overcast") }
        if has("clear sky", "sunny", "blue sky") { s.environment = .clearSky; applied.append("clear sky") }
        if has("physical sky") { s.environment = .physicalSky; applied.append("physical sky") }
        if has("studio") { s.environment = .studio; applied.append("studio light") }
        if has("clay", "white model", "massing") { s.clay = true; s.environment = .studio; applied.append("clay model") }
        if has("soft shadow") { s.shadowSoftness = 10; applied.append("soft shadows") }
        if has("sharp shadow", "crisp shadow", "hard shadow") { s.shadowSoftness = 1; s.shadowQuality = .ultra; applied.append("sharp shadows") }
        if has("no shadow") { s.shadowQuality = .off; applied.append("no shadows") }
        if has("warm") && !applied.contains(where: { $0.contains("warm") }) { s.whiteBalance = 4800; applied.append("warm white balance") }
        if has("cool", "cold", "blue tone") { s.whiteBalance = 8000; applied.append("cool white balance") }
        if has("bright", "airy", "high key") { s.exposure += 0.5; applied.append("brighter") }
        if has("dark", "moody", "dramatic", "low key") { s.exposure -= 0.5; s.ambientOcclusion = 1.6; applied.append("moody") }
        if has("depth of field", "bokeh", "shallow focus") { s.depthOfField = true; s.fStop = 2.0; applied.append("depth of field") }
        if has("white background") { s.background = .white; applied.append("white background") }
        if has("transparent") { s.background = .transparent; applied.append("transparent background") }
        if has("8k") { s.width = 7680; s.height = 4320; applied.append("8K") }
        else if has("4k", "uhd") { s.width = 3840; s.height = 2160; applied.append("4K") }
        else if has("square", "instagram") { s.width = 2048; s.height = 2048; applied.append("square") }
        else if has("portrait", "vertical") { s.width = 1440; s.height = 2160; applied.append("portrait") }
        if has("high quality", "final", "best quality") { s.shadowQuality = .ultra; s.antialias = true; applied.append("high quality") }
        if has("draft", "quick", "preview") { s.shadowQuality = .low; s.antialias = false; applied.append("draft") }
        return applied
    }

    /// Settings from a JSON object (e.g. an assistant reply): the RenderPreset fields, all optional.
    static func apply(json: Data, to s: inout RenderSettings) -> Bool {
        guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return false }
        var p = RenderPreset.from(s, name: "prompt")
        if let v = o["width"] as? Int { p.width = min(max(v, 16), 7680) }
        if let v = o["height"] as? Int { p.height = min(max(v, 16), 4320) }
        if let v = o["exposure"] as? Double { p.exposure = min(max(v, -3), 3) }
        if let v = o["background"] as? String { p.background = v }
        if let v = o["environment"] as? String { p.environment = v }
        if let v = o["shadowSoftness"] as? Double { p.shadowSoftness = v }
        if let v = o["shadowQuality"] as? String { p.shadowQuality = v }
        if let v = o["whiteBalance"] as? Double { p.whiteBalance = v }
        if let v = o["depthOfField"] as? Bool { p.depthOfField = v }
        if let v = o["clay"] as? Bool { p.clay = v }
        let date = s.date
        p.apply(to: &s)
        s.date = date
        if let h = o["hour"] as? Double {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: s.date); c.hour = Int(h); c.minute = Int((h - floor(h)) * 60)
            if let d = Calendar.current.date(from: c) { s.date = d }
        }
        return true
    }
}
