// Oanarina Archi Tool — GPL-3.0-or-later
// Plugin SDK (core side): plugins are folders with a plugin.json manifest and a JavaScript entry file. The registry loads
// manifests from the plugin folders, keeps the enabled/disabled state, and registers each declared command as a normal
// command (command line, scripts, agents; one undo step). Running a plugin command calls the host's script evaluator
// (`PluginRegistry.evaluator`), which the app sets from its JavaScriptCore engine and archi-cli sets from its own.
// Also: conversion of recorded command scripts (.scr / SCRIPTRECORD) to JavaScript and plugin scaffolding.
import Foundation

public struct PluginCommand: Codable, Hashable {
    public var name: String
    public var aliases: [String]
    public var summary: String
    /// JavaScript function (global, defined by the entry file) called when the command runs.
    public var function: String
    public var category: String
    /// Whether the command changes the document (records undo).
    public var modifies: Bool
    public init(name: String, aliases: [String] = [], summary: String = "", function: String, category: String = "Plugins", modifies: Bool = true) {
        self.name = name.uppercased(); self.aliases = aliases.map { $0.uppercased() }; self.summary = summary; self.function = function
        self.category = category; self.modifies = modifies
    }
    enum CodingKeys: String, CodingKey { case name, aliases, summary, function, category, modifies }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let n = try c.decode(String.self, forKey: .name)
        self.init(name: n, aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
                  summary: try c.decodeIfPresent(String.self, forKey: .summary) ?? "",
                  function: try c.decodeIfPresent(String.self, forKey: .function) ?? n.lowercased(),
                  category: try c.decodeIfPresent(String.self, forKey: .category) ?? "Plugins",
                  modifies: try c.decodeIfPresent(Bool.self, forKey: .modifies) ?? true)
    }
}

public struct PluginManifest: Codable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var author: String
    /// Entry script relative to the plugin folder (default main.js).
    public var main: String
    public var commands: [PluginCommand]
    /// Declared capabilities ("document", "files", "network"); informational, shown before enabling.
    public var permissions: [String]
    public init(id: String, name: String, version: String = "1.0", description: String = "", author: String = "", main: String = "main.js",
                commands: [PluginCommand] = [], permissions: [String] = ["document"]) {
        self.id = id; self.name = name; self.version = version; self.description = description; self.author = author; self.main = main
        self.commands = commands; self.permissions = permissions
    }
    enum CodingKeys: String, CodingKey { case id, name, version, description, author, main, commands, permissions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? name, name: name,
                  version: try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0",
                  description: try c.decodeIfPresent(String.self, forKey: .description) ?? "",
                  author: try c.decodeIfPresent(String.self, forKey: .author) ?? "",
                  main: try c.decodeIfPresent(String.self, forKey: .main) ?? "main.js",
                  commands: try c.decodeIfPresent([PluginCommand].self, forKey: .commands) ?? [],
                  permissions: try c.decodeIfPresent([String].self, forKey: .permissions) ?? ["document"])
    }
}

public struct LoadedPlugin: Hashable {
    public var manifest: PluginManifest
    public var directory: URL
    /// Entry script text.
    public var source: String
    public var enabled: Bool
    public var id: String { manifest.id }
}

public typealias PluginEvaluator = @MainActor (_ plugin: LoadedPlugin, _ function: String, _ editor: Editor) async throws -> Void

@MainActor
public final class PluginRegistry {
    public static let shared = PluginRegistry()
    /// Host hook: evaluates `function` of the plugin's script against the editor. Set by the app / archi-cli.
    public static var evaluator: PluginEvaluator?

    nonisolated public static var defaultFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Oanarina Archi Tool/Plugins", isDirectory: true)
    }

    public var folders: [URL]
    public private(set) var plugins: [LoadedPlugin] = []
    /// Problems found while loading (bad manifest, missing entry file, command name clashes).
    public private(set) var problems: [String] = []
    /// Command name → plugin id, for the commands this registry registered.
    public private(set) var commandOwner: [String: String] = [:]

    public init(folders: [URL] = [PluginRegistry.defaultFolder]) { self.folders = folders }

    nonisolated static let manifestName = "plugin.json"
    nonisolated static let stateName = "plugins-state.json"

    func stateURL(_ folder: URL) -> URL { folder.appendingPathComponent(PluginRegistry.stateName) }
    func disabledIDs(_ folder: URL) -> Set<String> {
        guard let d = try? Data(contentsOf: stateURL(folder)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return Set(o["disabled"] as? [String] ?? [])
    }

    /// Validates and parses a manifest. Command names must be letters/digits/underscore.
    nonisolated public static func parseManifest(_ data: Data) throws -> PluginManifest {
        let m: PluginManifest
        do { m = try JSONDecoder().decode(PluginManifest.self, from: data) } catch { throw DocumentIO.IOError(message: "invalid plugin.json (\(error.localizedDescription))") }
        guard !m.id.isEmpty, !m.name.isEmpty else { throw DocumentIO.IOError(message: "plugin.json needs an id and a name") }
        let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        for c in m.commands {
            guard !c.name.isEmpty, c.name.unicodeScalars.allSatisfy({ ok.contains($0) }) else { throw DocumentIO.IOError(message: "invalid command name '\(c.name)'") }
            guard !c.function.isEmpty else { throw DocumentIO.IOError(message: "command \(c.name) has no function") }
        }
        return m
    }

    /// Scans the plugin folders (one sub-folder per plugin). Replaces the loaded list.
    @discardableResult
    public func reload() -> [LoadedPlugin] {
        plugins = []; problems = []
        let fm = FileManager.default
        for folder in folders {
            let disabled = disabledIDs(folder)
            for dir in ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let mf = dir.appendingPathComponent(PluginRegistry.manifestName)
                guard let data = try? Data(contentsOf: mf) else { continue }
                do {
                    let m = try PluginRegistry.parseManifest(data)
                    guard !plugins.contains(where: { $0.id == m.id }) else { problems.append("\(dir.lastPathComponent): duplicate plugin id \(m.id)"); continue }
                    let entry = dir.appendingPathComponent(m.main)
                    guard let src = try? String(contentsOf: entry, encoding: .utf8) else { problems.append("\(m.name): entry file \(m.main) not found"); continue }
                    plugins.append(LoadedPlugin(manifest: m, directory: dir, source: src, enabled: !disabled.contains(m.id)))
                } catch { problems.append("\(dir.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            }
        }
        return plugins
    }

    public func plugin(_ key: String) -> LoadedPlugin? {
        plugins.first { $0.id.caseInsensitiveCompare(key) == .orderedSame || $0.manifest.name.caseInsensitiveCompare(key) == .orderedSame }
    }

    /// Enables or disables a plugin; the state is saved in plugins-state.json of its folder.
    public func setEnabled(_ key: String, _ on: Bool) throws {
        guard let i = plugins.firstIndex(where: { $0.id.caseInsensitiveCompare(key) == .orderedSame || $0.manifest.name.caseInsensitiveCompare(key) == .orderedSame }) else {
            throw DocumentIO.IOError(message: "no plugin \(key)")
        }
        plugins[i].enabled = on
        let folder = plugins[i].directory.deletingLastPathComponent()
        var disabled = disabledIDs(folder)
        if on { disabled.remove(plugins[i].id) } else { disabled.insert(plugins[i].id) }
        let d = try JSONSerialization.data(withJSONObject: ["disabled": disabled.sorted()], options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try d.write(to: stateURL(folder), options: .atomic)
    }

    /// Command definitions of the enabled plugins. A command checks at run time that its plugin is still enabled.
    public func commandDefinitions() -> [CommandDef] {
        var out: [CommandDef] = []
        for p in plugins where p.enabled {
            for c in p.manifest.commands {
                let pid = p.id, fn = c.function
                out.append(CommandDef(c.name, aliases: c.aliases, category: c.category, summary: c.summary.isEmpty ? "\(p.manifest.name) plugin command." : c.summary,
                                      modifies: c.modifies) { [weak self] ed in
                    guard let reg = self, let plug = reg.plugins.first(where: { $0.id == pid }) else { throw CommandError.invalid("The plugin is not loaded.") }
                    guard plug.enabled else { throw CommandError.invalid("The plugin \(plug.manifest.name) is disabled (PLUGINS Enable).") }
                    guard let run = PluginRegistry.evaluator else { throw CommandError.invalid("No script engine is available to run plugin commands.") }
                    do { try await run(plug, fn, ed) }
                    catch let e as CommandError { throw e }
                    catch { throw CommandError.invalid("\(plug.manifest.name): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
                })
            }
        }
        return out
    }

    /// Registers the enabled plugins' commands. Names taken by other commands (built-ins or other plugins) are skipped
    /// and reported. Returns the registered command names.
    @discardableResult
    public func register(into registry: CommandRegistry) -> [String] {
        var names: [String] = []
        for c in commandDefinitions() {
            if let existing = registry.lookup(c.name), commandOwner[existing.name] == nil {
                problems.append("Command \(c.name) is already defined; the plugin command was not registered.")
                continue
            }
            let aliases = c.aliases.filter { a in registry.lookup(a).map { commandOwner[$0.name] != nil } ?? true }
            var def = c
            def.aliases = aliases
            registry.register(def)
            commandOwner[c.name] = plugins.first { $0.enabled && $0.manifest.commands.contains { $0.name == c.name } }?.id
            names.append(c.name)
        }
        return names
    }

    /// Creates a plugin skeleton (manifest + main.js). With `script` (command-line script lines), the command replays it.
    @discardableResult
    public static func scaffold(in folder: URL, name: String, command: String, script: [String]? = nil, registry: CommandRegistry? = nil) throws -> URL {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce("") { $0 + String($1) }
        let dir = folder.appendingPathComponent(slug.isEmpty ? "plugin" : slug, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fn = "run" + command.prefix(1).uppercased() + command.dropFirst().lowercased()
        let m = PluginManifest(id: "local." + (slug.isEmpty ? "plugin" : slug), name: name, description: "Created by PLUGINS New.",
                               author: NSUserName(), commands: [PluginCommand(name: command, summary: "\(name) (plugin).", function: fn)])
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(m).write(to: dir.appendingPathComponent(manifestName), options: .atomic)
        let body = script.map { ScriptConverter.javaScript(fromScriptLines: $0, registry: registry ?? .shared, indent: "    ") } ?? "    archi.print(\"Hello from \(name)\");\n"
        let js = "// \(name) — plugin for Oanarina Archi Tool\n// archi.run(\"COMMAND inputs \") runs command lines; archi.print(text) writes to the command history.\n\nfunction \(fn)() {\n\(body)}\n"
        try js.write(to: dir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        return dir
    }
}

// MARK: - Recorded scripts → JavaScript

public enum ScriptConverter {
    /// Groups script lines (one input per line, as SCRIPTRECORD writes them; ";" comments) into command invocations: a new
    /// command starts on a line whose first word is a registered command or alias and does not look like an input.
    public static func commands(fromScriptLines lines: [String], registry: CommandRegistry = .shared) -> [String] {
        registry.ensureBuiltins()
        var out: [String] = []
        var cur: [String] = []
        func isInput(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            if let f = t.first, "0123456789.-+@#*<\"'(".contains(f) { return true }
            return false
        }
        for raw in lines {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix(";") { continue }
            let line = raw.replacingOccurrences(of: "\r", with: "")
            let first = line.split(separator: " ").first.map(String.init) ?? ""
            if !isInput(line), registry.lookup(first) != nil {
                if !cur.isEmpty { out.append(cur.joined(separator: " ")) }
                cur = [line]
            } else if cur.isEmpty {
                cur = [line]
            } else { cur.append(line) }
        }
        if !cur.isEmpty { out.append(cur.joined(separator: " ")) }
        // A command whose inputs end without Enter gets one, so it finishes when run on its own.
        return out.map { $0.hasSuffix(" ") ? $0 : $0 + " " }
    }

    static func jsString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }

    /// JavaScript calling archi.run(...) once per command of the script.
    public static func javaScript(fromScriptLines lines: [String], registry: CommandRegistry = .shared, indent: String = "") -> String {
        commands(fromScriptLines: lines, registry: registry).map { "\(indent)archi.run(\(jsString($0)));\n" }.joined()
    }

    /// Whole .js file for a script (header comment + calls).
    public static func javaScriptFile(fromScript text: String, name: String, registry: CommandRegistry = .shared) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let trimmed = lines.last == "" ? Array(lines.dropLast()) : lines
        return "// \(name) — converted from a command script by Oanarina Archi Tool (SCRIPT2JS)\n// Run in the Script console, or as the body of a plugin command.\n\n"
            + javaScript(fromScriptLines: trimmed, registry: registry)
    }
}
