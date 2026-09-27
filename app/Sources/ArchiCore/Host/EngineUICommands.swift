// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of commands the Mac app defines in its UI layer (ArchiApp/AppCommands.swift, AppCommandsExtra.swift,
// AppCommandsRound10.swift): the same names, aliases, prompts, keywords, validation and messages; where the Mac opens a
// window or sheet the engine asks the Windows shell with a `host` notification ({"action":"dialog","dialog":…}), and
// application settings (crosshair size, autosave, theme, workspaces, ribbon customisation) go to the shell as
// {"action":"preference"|"workspace"|"workspaceSave"|"cui"|"layerFilter"|"newWindow"}. Registered by archi-engine only
// (EngineSession.registerPortableAppCommands); the Mac app registers its own versions.
import Foundation

enum EngineUICommands {
    static let settingsPages = ["General", "Drafting", "Display", "Shortcuts", "Toolbar", "Agents"]
    static let ribbonTabs = ["Home", "Insert", "Annotate", "Architecture", "Modeling", "Analyze", "Collaborate", "View", "Output", "Manage", "Script"]
    static let builtInWorkspaces = ["Drafting & Annotation", "Building Design", "3D Modeling", "Sheets & Plotting", "Scripting"]

    @MainActor static func session(_ ed: Editor) throws -> EngineSession {
        guard let s = (ed.host as? EngineHostBridge)?.session else { throw CommandError.invalid("This command needs a document window.") }
        return s
    }

    @MainActor static func host(_ ed: Editor, _ action: String, _ fields: [(String, EngineJSON)] = []) throws {
        let s = try session(ed)
        var o = EngineObject()
        for (k, v) in fields { o.set(k, v) }
        s.hostRequest(action, o)
    }

    @MainActor static func dialog(_ ed: Editor, _ name: String, _ fields: [(String, EngineJSON)] = []) throws {
        try host(ed, "dialog", [("dialog", .string(name))] + fields)
    }

    @MainActor static func pref(_ key: String) -> String? { EngineSession.uiPreferences[key] }

    @MainActor static func text(_ ed: Editor, _ msg: String, _ def: String) async throws -> String {
        let s = try await ed.getString(msg + " <" + def + ">", defaultValue: def) ?? def
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return t.isEmpty ? def : t
    }

    static func filePath(_ p: String, ext: String) -> URL {
        var path = (p as NSString).expandingTildeInPath
        if (path as NSString).pathExtension.isEmpty { path += "." + ext }
        return URL(fileURLWithPath: path)
    }

    static var all: [CommandDef] {
        [options, agentSettings, cursorSize, saveTime, theme, quickSelectDialog, layerFilter, wsCurrent, wsSave, cui, pageSetup,
         newFromTemplate, saveAsTemplate]
    }
    /// Commands that replace the core command-line versions in the engine process (the Mac app does the same).
    static var overrides: [CommandDef] { [layerState] }

    // MARK: Settings

    static var options: CommandDef {
        CommandDef("OPTIONS", aliases: ["OP", "PREFERENCES", "SETTINGS", "CONFIG"], category: "Settings",
                   summary: "Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents.", modifies: false) { ed in
            let k = try await ed.getKeyword("Settings page [General/Drafting/Display/Shortcuts/Toolbar/Agents]", settingsPages, defaultValue: "General")
            try dialog(ed, "options", [("tab", .string(k ?? "General"))])
        }
    }

    static var agentSettings: CommandDef {
        CommandDef("AGENTSETTINGS", aliases: ["AGENTS", "AGENTSERVER"], category: "Scripting",
                   summary: "Agent server settings: port, start/stop, token, auto-start.", modifies: false) { ed in
            try dialog(ed, "options", [("tab", .string("Agents"))])
        }
    }

    static var cursorSize: CommandDef {
        CommandDef("CURSORSIZE", category: "Settings", summary: "Sets the crosshair size as a percentage of the view (1–100).", modifies: false) { ed in
            let cur = Int(pref("cursorSize") ?? "") ?? 10
            guard let v = try await ed.getInteger("Enter new value for CURSORSIZE <" + String(cur) + ">", defaultValue: cur) else { return }
            guard (1...100).contains(v) else { throw CommandError.invalid("Requires an integer between 1 and 100.") }
            EngineSession.uiPreferences["cursorSize"] = String(v)
            try host(ed, "preference", [("key", .string("cursorSize")), ("value", .int(v))])
        }
    }

    static var saveTime: CommandDef {
        CommandDef("SAVETIME", aliases: ["AUTOSAVE"], category: "Settings", summary: "Sets the autosave interval in minutes (0 turns autosave off).", modifies: false) { ed in
            let cur = Int(pref("autosaveMinutes") ?? "") ?? 5
            guard let v = try await ed.getInteger("Enter new value for SAVETIME (minutes) <" + String(cur) + ">", defaultValue: cur) else { return }
            guard (0...600).contains(v) else { throw CommandError.invalid("Requires 0–600 minutes.") }
            EngineSession.uiPreferences["autosaveMinutes"] = String(v)
            try host(ed, "preference", [("key", .string("autosaveMinutes")), ("value", .int(v))])
            ed.print(v == 0 ? "Autosave is off." : "Autosave every " + String(v) + " minute(s).")
        }
    }

    static var theme: CommandDef {
        CommandDef("THEME", aliases: ["COLORTHEME", "APPEARANCE"], category: "Settings", summary: "Switches the interface theme [Dark/Light].", modifies: false) { ed in
            let light = pref("theme") == "light"
            let k = try await ed.getKeyword("Theme [Dark/Light]", ["Dark", "Light"], defaultValue: light ? "Dark" : "Light") ?? "Dark"
            EngineSession.uiPreferences["theme"] = k.lowercased()
            try host(ed, "preference", [("key", .string("theme")), ("value", .string(k.lowercased()))])
            ed.print(k + " theme.")
        }
    }

    // MARK: Selection and layers

    static var quickSelectDialog: CommandDef {
        CommandDef("QSELECTDIALOG", aliases: ["QSD", "QUICKSELECT"], category: "Select",
                   summary: "Quick Select dialog: type, property, operator and value with a live match count.", modifies: false) { ed in
            try dialog(ed, "quickSelect")
        }
    }

    static var layerState: CommandDef {
        CommandDef("LAYERSTATE", aliases: ["LAS", "LMAN", "-LAYERSTATE"], category: "Layers",
                   summary: "Layer states: Dialog, or ?/Save/Restore/Delete/Import/Export/Rename on the command line (saved in the drawing).") { ed in
            let hasWindow = ed.host is EngineHostBridge
            let k = try await ed.getKeyword("Enter an option", ["Dialog"] + LayerToolCommands.layerStateOptions, defaultValue: hasWindow ? "Dialog" : "?") ?? "Dialog"
            if k == "Dialog" {
                guard hasWindow else { try await LayerToolCommands.runLayerState("?", ed); return }
                try dialog(ed, "layerStates")
            } else {
                try await LayerToolCommands.runLayerState(k, ed)
            }
        }
    }

    static var layerFilter: CommandDef {
        CommandDef("LAYERFILTER", aliases: ["LFILTER"], category: "Layers",
                   summary: "Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing.") { ed in
            let k = try await ed.getKeyword("Enter an option [Apply/Save/Delete/List/Clear]", ["Apply", "Save", "Delete", "List", "Clear"], defaultValue: "Apply") ?? "Apply"
            let prefix = EngineSession.layerFilterPrefix
            switch k {
            case "List":
                let names = ed.doc.variables.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
                if names.isEmpty { ed.print("No saved layer filters.") }
                for n in names { ed.print("  " + n + ": " + (ed.doc.variables[prefix + n] ?? "")) }
            case "Clear":
                try? host(ed, "layerFilter", [("filter", .string(""))])
            case "Delete":
                guard let n = try await ed.getString("Enter filter name") else { return }
                var d = ed.doc
                d.variables[prefix + n.uppercased()] = nil
                ed.doc = d
            case "Save":
                guard let n = try await ed.getString("Enter filter name"), !n.isEmpty else { return }
                guard let p = try await ed.getString("Enter filter (name wildcards, #on #used #unlocked)"), !p.isEmpty else { return }
                let name = n.trimmingCharacters(in: .whitespaces).uppercased()
                var d = ed.doc
                d.variables[prefix + name] = EngineLayerFilter(stored: p).stored
                ed.doc = d
                ed.print("Layer filter " + n.uppercased() + " saved.")
            default:
                guard let p = try await ed.getString("Enter filter name or pattern") else { return }
                let f = ed.doc.variables[prefix + p.uppercased()].map { EngineLayerFilter(stored: $0) } ?? EngineLayerFilter(stored: p)
                var used = Set<String>()
                for e in ed.doc.entities { used.insert(e.layer.uppercased()) }
                for e in ed.doc.elements { used.insert(e.layer.uppercased()) }
                let hits = ed.doc.layers.filter { f.matches($0, used: used.contains($0.name.uppercased())) }
                ed.print(String(hits.count) + " layer(s) match: " + hits.prefix(30).map(\.name).joined(separator: ", "))
                try? host(ed, "layerFilter", [("filter", .string(f.stored))])
            }
        }
    }

    // MARK: Workspaces

    @MainActor static func workspaceNames() -> [String] {
        let custom = (pref("workspaces") ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty }
        return custom.isEmpty ? builtInWorkspaces : custom
    }

    @MainActor static func findWorkspace(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        let all = workspaceNames()
        if let w = all.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { return w }
        guard !n.isEmpty else { return nil }
        return all.first { $0.lowercased().hasPrefix(n.lowercased()) }
    }

    static var wsCurrent: CommandDef {
        CommandDef("WSCURRENT", aliases: ["WS", "WORKSPACE"], category: "View",
                   summary: "Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling.", modifies: false) { ed in
            _ = try session(ed)
            ed.print("Workspaces: " + workspaceNames().joined(separator: ", "))
            let cur = pref("workspace") ?? builtInWorkspaces[0]
            guard let n = try await ed.getString("Enter workspace name <" + cur + ">", defaultValue: cur) else { return }
            guard let w = findWorkspace(n) else { throw CommandError.invalid("Workspace \"" + n + "\" not found.") }
            EngineSession.uiPreferences["workspace"] = w
            try host(ed, "workspace", [("name", .string(w))])
            ed.print("Workspace: " + w)
        }
    }

    static var wsSave: CommandDef {
        CommandDef("WSSAVE", category: "View", summary: "Saves the current window arrangement as a named workspace.", modifies: false) { ed in
            _ = try session(ed)
            let cur = pref("workspace") ?? builtInWorkspaces[0]
            guard let n = try await ed.getString("Save workspace as <" + cur + ">", defaultValue: cur), !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let name = n.trimmingCharacters(in: .whitespaces)
            var names = workspaceNames().filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            names.append(name)
            EngineSession.uiPreferences["workspaces"] = names.joined(separator: "|")
            EngineSession.uiPreferences["workspace"] = name
            try host(ed, "workspaceSave", [("name", .string(name))])
            ed.print("Workspace \"" + n + "\" saved.")
        }
    }

    // MARK: Ribbon customisation (CUI)

    /// The shell's ribbon customisation ({format, version, panels:[{id,title,tab,commands,symbols}], hiddenPanels, quickAccess}).
    @MainActor static func currentCUI() -> EngineCUI { EngineCUI(json: pref("cui").flatMap { try? EngineJSON.parse($0) }) }

    static var cui: CommandDef {
        CommandDef("CUI", aliases: ["CUSTOMIZE", "RIBBONCUSTOMIZE", "-CUI"], category: "Settings",
                   summary: "Customizes the ribbon: Dialog, Add a panel of commands to a tab, Remove, Hide/Show a built-in panel, List, Export/Import a customisation file, Reset.", modifies: false) { ed in
            var c = currentCUI()
            let keys = ["Dialog", "Add", "Remove", "Hide", "Show", "List", "Export", "Import", "Reset"]
            let k = try await ed.getKeyword("CUI [Dialog/Add/Remove/Hide/Show/List/Export/Import/Reset]", keys, defaultValue: "Dialog") ?? "Dialog"
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").appendingPathComponent("Ribbon.archicui.json").path
            switch k {
            case "Dialog":
                try dialog(ed, "cui")
                return
            case "Add":
                let tab = try await ed.getKeyword("Tab [" + ribbonTabs.joined(separator: "/") + "]", ribbonTabs, defaultValue: "Home") ?? "Home"
                let title = try await text(ed, "Panel title", "My Tools")
                let list = try await text(ed, "Commands (comma separated)", "LINE, CIRCLE")
                let cmds = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
                let bad = cmds.filter { ed.registry.lookup(String($0.split(separator: " ").first ?? "")) == nil }
                guard bad.isEmpty else { throw CommandError.invalid("Unknown command(s): " + bad.joined(separator: ", ")) }
                guard !cmds.isEmpty else { return }
                c.panels.removeAll { $0.tab == tab && $0.title == title }
                c.panels.append(EngineCUI.Panel(id: UUID().uuidString, title: title, tab: tab, commands: cmds, symbols: [:]))
            case "Remove":
                let title = try await text(ed, "Panel title", c.panels.last?.title ?? "")
                guard c.panels.contains(where: { $0.title == title }) else { throw CommandError.invalid("No custom panel " + title + ".") }
                c.panels.removeAll { $0.title == title }
            case "Hide", "Show":
                let title = try await text(ed, "Built-in panel title", "Selection")
                if k == "Hide" { if !c.hiddenPanels.contains(title) { c.hiddenPanels.append(title) } } else { c.hiddenPanels.removeAll { $0 == title } }
            case "Export":
                let url = filePath(try await text(ed, "Customisation file", desktop), ext: "json")
                var out = c
                out.quickAccess = pref("quickAccess").map { $0.split(separator: ",").map(String.init) }
                do { try Data(out.json.serialized.utf8).write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write " + url.path + ".") }
                ed.print("Ribbon customisation exported to " + url.path + ".")
                return
            case "Import":
                let url = filePath(try await text(ed, "Customisation file", desktop), ext: "json")
                guard let data = try? Data(contentsOf: url), let j = try? EngineJSON.parse(String(decoding: data, as: UTF8.self)) else { throw CommandError.invalid("Cannot read " + url.path + ".") }
                guard (j["format"]?.stringValue ?? "oanarina-archi-cui") == "oanarina-archi-cui" else { throw CommandError.invalid("Not an Oanarina Archi Tool ribbon customisation file.") }
                let imported = EngineCUI(json: j)
                let unknown = imported.panels.flatMap(\.commands).filter { ed.registry.lookup(String($0.split(separator: " ").first ?? "")) == nil }
                EngineSession.uiPreferences["cui"] = imported.json.serialized
                var fields: [(String, EngineJSON)] = [("op", .string("set")), ("data", imported.json)]
                if let q = imported.quickAccess, !q.isEmpty {
                    let known = q.filter { ed.registry.lookup($0) != nil }
                    fields.append(("quickAccess", EngineJSON.strings(known)))
                }
                try host(ed, "cui", fields)
                ed.print("Imported " + String(imported.panels.count) + " panel(s)" + (unknown.isEmpty ? "" : "; unknown commands: " + unknown.joined(separator: ", ")) + ".")
                return
            case "Reset":
                c = EngineCUI(json: nil)
            default:
                if c.panels.isEmpty && c.hiddenPanels.isEmpty { ed.print("Ribbon not customised.") }
                for p in c.panels { ed.print("  " + p.tab + " ▸ " + p.title + ": " + p.commands.joined(separator: ", ")) }
                if !c.hiddenPanels.isEmpty { ed.print("  Hidden: " + c.hiddenPanels.joined(separator: ", ")) }
                return
            }
            EngineSession.uiPreferences["cui"] = c.json.serialized
            try host(ed, "cui", [("op", .string("set")), ("data", c.json)])
            ed.print("Ribbon: " + String(c.panels.count) + " custom panel(s), " + String(c.hiddenPanels.count) + " hidden.")
        }
    }

    // MARK: Output and files

    static var pageSetup: CommandDef {
        CommandDef("PAGESETUP", aliases: ["PSETUP", "PAGESETUPMANAGER"], category: "Output",
                   summary: "Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale.", modifies: false) { ed in
            try dialog(ed, "pageSetup")
        }
    }

    static var newFromTemplate: CommandDef {
        CommandDef("NEWFROMTEMPLATE", aliases: ["NEWTEMPLATE", "QNEW"], category: "File",
                   summary: "Starts a new drawing from a template (built-in or from the templates folder).", modifies: false) { ed in
            let s = try session(ed)
            let list = s.templatesList(.object([]))["templates"]?.arrayValue ?? []
            let names = list.compactMap { $0["name"]?.stringValue }
            ed.print("Templates: " + names.joined(separator: ", "))
            guard let n = try await ed.getString("Template name", defaultValue: names.first ?? "") else { return }
            let want = n.trimmingCharacters(in: .whitespaces)
            guard let t = list.first(where: { ($0["name"]?.stringValue ?? "").caseInsensitiveCompare(want) == .orderedSame }), let id = t["id"]?.stringValue else {
                throw CommandError.invalid("No template \"" + n + "\".")
            }
            if s.editor.isDirty || !(ed.doc.entities.isEmpty && ed.doc.elements.isEmpty) {
                try host(ed, "newWindow", [("kind", .string("template")), ("path", .string(id))])
            } else {
                try await s.applyTemplate(id, cancelRunning: false)
                s.hostRequest("zoomExtents")
            }
        }
    }

    static var saveAsTemplate: CommandDef {
        CommandDef("SAVEASTEMPLATE", aliases: ["SAVETEMPLATE", "TEMPLATESAVE"], category: "File",
                   summary: "Saves the drawing's settings, layers, styles and content as a template in the templates folder.", modifies: false) { ed in
            let s = try session(ed)
            let def = ed.doc.info.name == "Untitled Project" ? "My Template" : ed.doc.info.name
            guard let n = try await ed.getString("Template name <" + def + ">", defaultValue: def), !n.isEmpty else { return }
            let path = try s.saveTemplate(n, folder: nil)
            ed.print("Template saved: " + path)
        }
    }
}

// MARK: - Ribbon customisation data (RibbonCustomization in ArchiApp/RibbonCustomization.swift, same JSON)

struct EngineCUI {
    struct Panel {
        var id: String
        var title: String
        var tab: String
        var commands: [String]
        var symbols: [String: String]
    }
    var panels: [Panel] = []
    var hiddenPanels: [String] = []
    var quickAccess: [String]? = nil

    init(json: EngineJSON?) {
        guard let j = json else { return }
        for p in j["panels"]?.arrayValue ?? [] {
            var symbols: [String: String] = [:]
            for f in p["symbols"]?.fields ?? [] { symbols[f.key] = f.value.stringValue ?? "" }
            let cmds = (p["commands"]?.arrayValue ?? []).compactMap(\.stringValue)
            panels.append(Panel(id: p["id"]?.stringValue ?? UUID().uuidString, title: p["title"]?.stringValue ?? "Custom",
                                tab: p["tab"]?.stringValue ?? "Home", commands: cmds, symbols: symbols))
        }
        hiddenPanels = (j["hiddenPanels"]?.arrayValue ?? []).compactMap(\.stringValue)
        quickAccess = j["quickAccess"]?.arrayValue?.compactMap(\.stringValue)
    }

    var json: EngineJSON {
        var ps: [EngineJSON] = []
        for p in panels {
            var o = EngineObject()
            o.set("commands", EngineJSON.strings(p.commands))
            o.set("id", p.id)
            var sym: [EngineJSONField] = []
            for k in p.symbols.keys.sorted() { sym.append(EngineJSONField(k, .string(p.symbols[k] ?? ""))) }
            o.set("symbols", EngineJSON.object(sym))
            o.set("tab", p.tab)
            o.set("title", p.title)
            ps.append(o.json)
        }
        var o = EngineObject()
        o.set("format", "oanarina-archi-cui")
        o.set("hiddenPanels", EngineJSON.strings(hiddenPanels))
        o.set("panels", EngineJSON.array(ps))
        if let q = quickAccess { o.set("quickAccess", EngineJSON.strings(q)) }
        o.set("version", 1)
        return o.json
    }
}

// MARK: - Layer filters (LayerFilter in ArchiApp/LayerTools.swift; keep the two in step)

/// Layers panel filter: name wildcards (*, ?, #, @; comma-separated, ~ excludes, a bare word matches as a substring)
/// plus #on, #used and #unlocked flags. Stored as "#on #used A-*".
struct EngineLayerFilter {
    var pattern = ""
    var onlyVisible = false
    var onlyUsed = false
    var onlyUnlocked = false

    init(stored: String) {
        var rest: [String] = []
        for t in stored.split(separator: " ").map(String.init) {
            switch t.lowercased() {
            case "#on": onlyVisible = true
            case "#used": onlyUsed = true
            case "#unlocked": onlyUnlocked = true
            default: rest.append(t)
            }
        }
        pattern = rest.joined(separator: " ")
    }

    var stored: String {
        var p: [String] = []
        if onlyVisible { p.append("#on") }
        if onlyUsed { p.append("#used") }
        if onlyUnlocked { p.append("#unlocked") }
        p.append(pattern)
        return p.joined(separator: " ")
    }

    static func wildcard(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        if p.isEmpty { return t.isEmpty }
        var dp = Array(repeating: Array(repeating: false, count: t.count + 1), count: p.count + 1)
        dp[0][0] = true
        for i in 1...p.count where p[i - 1] == "*" { dp[i][0] = dp[i - 1][0] }
        for i in 1...p.count {
            for j in 0...t.count {
                let c = p[i - 1]
                var v = false
                if c == "*" { v = dp[i - 1][j] || (j > 0 && dp[i][j - 1]) }
                else if j > 0 {
                    let ch = t[j - 1]
                    var ok = false
                    if c == "?" { ok = true } else if c == "#" { ok = ch.isNumber } else if c == "@" { ok = ch.isLetter } else { ok = ch == c }
                    v = ok && dp[i - 1][j - 1]
                }
                dp[i][j] = v
            }
        }
        return dp[p.count][t.count]
    }

    static func matchesPattern(_ pattern: String, _ name: String) -> Bool {
        let items = pattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return true }
        func m(_ item: String) -> Bool {
            if item.contains(where: { "*?#@".contains($0) }) { return wildcard(item, name) }
            return name.lowercased().contains(item.lowercased())
        }
        let neg = items.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
        let pos = items.filter { !$0.hasPrefix("~") }
        if neg.contains(where: m) { return false }
        return pos.isEmpty || pos.contains(where: m)
    }

    func matches(_ l: Layer, used: Bool) -> Bool {
        if onlyVisible && (!l.visible || l.frozen) { return false }
        if onlyUnlocked && l.locked { return false }
        if onlyUsed && !used { return false }
        return EngineLayerFilter.matchesPattern(pattern, l.name)
    }
}
