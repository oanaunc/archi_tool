// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac UI-layer commands for panels, views, windows and settings: NOTIFICATIONS and NAVIGATOR
// (AppCommandsStudio.swift), ADCENTER, TILEDVIEWS, DVIEW, PERSPECTIVE, IMPORTSETTINGS, EXPORTSETTINGS, FILETAB,
// FILETABCLOSE, WINDOWTABS and FULLSCREEN (AppCommandsNav.swift), FLOATPANEL (AppCommands.swift), OUTLINERPANEL and
// KEYBOARDNAV (AppCommandsRound11.swift), ASSISTANT and SYSWINDOWS (AppCommandsRound9.swift), LANGUAGE
// (Localization.swift), CMDLINEOPTIONS (CommandLineOptions.swift) and CRASHREPORTS (AppCommandsRound12.swift).
// Same names, aliases, prompts and messages; where the Mac shows a window or changes an app setting the engine asks
// the Windows shell with a `host` notification (docs/ENGINE-PROTOCOL.md "Panels and workspace"). The shell keeps the
// settings and sends their current values with ui.prefs, so the prompts show the same defaults as on the Mac.
// Registered by archi-engine only (EngineSession.registerToolCommands).
import Foundation

enum EngineWorkspaceCommands {
    static let panelTabs = ["Properties", "Layers", "Levels", "Browser", "Materials", "Tools", "Sheets", "History", "Selection", "Navigator", "Alerts",
                            "Quick Props", "Inspector", "Content"]
    static let languages: [(code: String, name: String)] = [("en", "English"), ("ro", "Română"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("it", "Italiano")]

    static var all: [CommandDef] {
        [notifications, navigator, designCenter, outlinerPanel, floatPanel, tiledViews, dview, perspective, keyboardNav, assistant, language,
         exportSettings, importSettings, cmdLineOptions, crashReports, fileTab, fileTabClose, windowTabs, sysWindows, fullScreen]
    }

    @MainActor static func host(_ ed: Editor, _ action: String, _ fields: [(String, EngineJSON)] = []) throws {
        try EngineUICommands.host(ed, action, fields)
    }
    @MainActor static func pref(_ key: String) -> String? { EngineSession.uiPreferences[key] }
    @MainActor static func setPref(_ key: String, _ value: String) { EngineSession.uiPreferences[key] = value }

    // MARK: Panels

    static var notifications: CommandDef {
        CommandDef("NOTIFICATIONS", aliases: ["WARNINGS", "NOTIFYCENTER"], category: "Inquiry",
                   summary: "Notifications centre: model warnings (overlaps, unhosted openings, family errors, missing blocks) — click one to zoom to it.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let n = EngineAlerts.items(ed.doc).filter { $0.severity != .info }.count
            ed.print(n == 0 ? "No warnings." : String(n) + " warning(s).")
            try host(ed, "showPanel", [("panel", .string("Alerts"))])
        }
    }

    static var navigator: CommandDef {
        CommandDef("NAVIGATOR", aliases: ["OVERVIEW", "MINIMAP"], category: "View",
                   summary: "Navigator: overview map of the whole drawing with the visible area; drag the rectangle to pan.", modifies: false) { ed in
            try host(ed, "showPanel", [("panel", .string("Navigator")), ("mode", .string("2D"))])
        }
    }

    static var designCenter: CommandDef {
        CommandDef("ADCENTER", aliases: ["DESIGNCENTER", "ADC"], category: "Insert",
                   summary: "Design Center: browses another drawing's blocks, layers, linetypes, styles and materials and adds them here.", modifies: false) { ed in
            try host(ed, "showPanel", [("panel", .string("Content"))])
        }
    }

    static var outlinerPanel: CommandDef {
        CommandDef("OUTLINERPANEL", aliases: ["OUTLINERWINDOW", "SHOWOUTLINER"], category: "3D",
                   summary: "Outliner window: the tree of groups, components, blocks and model groups; click selects, double-click zooms, filter by name.", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "outliner")
        }
    }

    static var floatPanel: CommandDef {
        CommandDef("FLOATPANEL", aliases: ["UNDOCKPANEL", "PANELFLOAT"], category: "View",
                   summary: "Floats a panel (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History) in its own window.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let cur = pref("panelTab").flatMap { t in panelTabs.first { $0 == t } } ?? "Properties"
            guard let k = try await ed.getKeyword("Panel [" + panelTabs.joined(separator: "/") + "]", panelTabs, defaultValue: cur) else { return }
            try host(ed, "floatPanel", [("panel", .string(k))])
        }
    }

    // MARK: Views

    static var tiledViews: CommandDef {
        CommandDef("TILEDVIEWS", aliases: ["VPTILE", "TILEVIEWS"], category: "View",
                   summary: "Tiled model views: 2, 3 or 4 views (plan, 3D, section, elevations), each with its own zoom and pan.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            guard let k = try await ed.getKeyword("Arrangement [2/Stacked/3/4/Single]", ["2", "Stacked", "3", "4", "Single"], defaultValue: "4") else { return }
            try host(ed, "tiledViews", [("arrangement", .string(k))])
        }
    }

    static var dview: CommandDef {
        CommandDef("DVIEW", aliases: ["DV", "PLANTWIST"], category: "View",
                   summary: "Rotates (twists) the 2D plan display; model coordinates are unchanged. DVIEW TWist 30, DVIEW Off.", modifies: true) { ed in
            let cur = ed.doc.variable("VIEWTWIST").flatMap(Double.init) ?? 0
            guard let k = try await ed.getKeyword("Enter option [TWist/Off]", ["TWist", "Off"], defaultValue: "TWist") else { return }
            if k == "Off" { ed.doc.variables["VIEWTWIST"] = nil; ed.print("View twist off."); return }
            guard let a = try await ed.getAngle("Specify view twist angle", defaultValue: rad(cur)).value else { return }
            var d = deg(a).truncatingRemainder(dividingBy: 360)
            if d < 0 { d += 360 }
            if d < 1e-9 || d > 360 - 1e-9 { d = 0 }
            if d == 0 { ed.doc.variables["VIEWTWIST"] = nil } else { ed.doc.setVariable("VIEWTWIST", fmt(d, 6)) }
            ed.print("View twist " + fmt(d, 2) + "°.")
        }
    }

    static var perspective: CommandDef {
        CommandDef("PERSPECTIVE", aliases: ["PROJECTION"], category: "View", summary: "3D projection: 1 = perspective, 0 = parallel (orthographic).", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let cur = ed.doc.variable("PERSPECTIVE") ?? "1"
            guard let v = try await ed.getInteger("Enter new value for PERSPECTIVE <" + cur + ">", defaultValue: Int(cur) ?? 1) else { return }
            guard v == 0 || v == 1 else { throw CommandError.invalid("Requires 0 or 1.") }
            ed.doc.setVariable("PERSPECTIVE", String(v))
            try host(ed, "show3D")
            try host(ed, "setView", [("view", .string(v == 1 ? "perspective" : "ortho"))])
        }
    }

    static let keyboardHelp = [
        "Type a command name and Enter; answer prompts by typing (coordinates, @relative, distances, keyword letters).",
        "At a point prompt the arrow keys move the crosshair (Shift ×10, Alt ÷10); Enter picks the snapped point.",
        "With no command running, Alt+arrows move the crosshair and Tab selects the object under it (Tab also answers Select objects prompts).",
        "SPEAKDRAWING describes the drawing, selection and prompt (Narrator reads new prompts automatically).",
    ]

    static var keyboardNav: CommandDef {
        CommandDef("KEYBOARDNAV", aliases: ["KEYCURSOR", "KEYBOARDHELP"], category: "Help",
                   summary: "Keyboard-only drawing: arrow keys move the crosshair at prompts (Shift ×10, Alt ÷10; Alt+arrows when idle), Enter picks, Tab selects under the crosshair; sets the step.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let cur = Int(pref("keyboardCursorStep") ?? "") ?? 10
            guard let v = try await ed.getInteger("Crosshair step in screen pixels <" + String(cur) + ">", defaultValue: cur), (1...200).contains(v) else {
                throw CommandError.invalid("Enter 1–200 pixels.")
            }
            setPref("keyboardCursorStep", String(v))
            try host(ed, "preference", [("key", .string("keyboardCursorStep")), ("value", .int(v))])
            for l in keyboardHelp { ed.print("  " + l) }
        }
    }

    // MARK: Assistant and settings

    static var assistant: CommandDef {
        CommandDef("ASSISTANT", aliases: ["AI", "AICHAT", "CHAT", "ASKAI"], category: "Scripting",
                   summary: "AI assistant panel: Claude or a local model (Ollama) edits the drawing with commands; bulk changes ask for confirmation; everything is undoable.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let k = try await ed.getKeyword("Assistant [Panel/Ask]", ["Panel", "Ask"], defaultValue: "Panel") ?? "Panel"
            try EngineUICommands.dialog(ed, "assistant")
            if k == "Ask", let q = try await ed.getString("Ask the assistant"), !q.isEmpty {
                try EngineUICommands.dialog(ed, "assistant", [("ask", .string(q))])
            }
        }
    }

    static var language: CommandDef {
        CommandDef("LANGUAGE", aliases: ["UILANGUAGE", "LIMBA", "SPRACHE", "LANGUE", "IDIOMA", "LINGUA"], category: "Settings",
                   summary: "Interface language of the ribbon: Auto (Windows), English, Română, Deutsch, Français, Español, Italiano. Commands stay English.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let names = ["Auto"] + languages.map(\.name)
            let setting = pref("uiLanguage") ?? "auto"
            let cur = setting == "auto" ? "Auto" : (languages.first { $0.code == setting }?.name ?? "Auto")
            let k = try await ed.getKeyword("Interface language [" + names.joined(separator: "/") + "] <" + cur + ">", names, defaultValue: cur) ?? cur
            let code = k == "Auto" ? "auto" : (languages.first { $0.name == k }?.code ?? "en")
            setPref("uiLanguage", code)
            try host(ed, "preference", [("key", .string("uiLanguage")), ("value", .string(code))])
            var msg = "Interface language: " + k
            if k == "Auto" {
                let sys = pref("systemLanguage") ?? "en"
                msg += " (" + (languages.first { $0.code == sys }?.name ?? "English") + ")"
            }
            ed.print(msg + ".")
        }
    }

    static var exportSettings: CommandDef {
        CommandDef("EXPORTSETTINGS", aliases: ["SETTINGSOUT"], category: "Settings",
                   summary: "Exports all preferences (theme, shortcuts, toolbar, workspaces, snippets…) to a settings file for another computer.", modifies: false) { ed in
            try host(ed, "exportSettings")
        }
    }

    static var importSettings: CommandDef {
        CommandDef("IMPORTSETTINGS", aliases: ["SETTINGSIN"], category: "Settings",
                   summary: "Imports preferences exported by EXPORTSETTINGS (restart to apply everything).", modifies: false) { ed in
            try host(ed, "importSettings")
        }
    }

    static var cmdLineOptions: CommandDef {
        CommandDef("CMDLINEOPTIONS", aliases: ["CLISETTINGS", "COMMANDLINEOPTIONS", "CLIFLOAT"], category: "Settings",
                   summary: "Command line appearance: text Size, history Lines shown, background Opacity; Float it over the canvas or Dock it at the bottom.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            var fontSize = Double(pref("cmdline.fontSize") ?? "") ?? 11
            var lines = Int(pref("cmdline.lines") ?? "") ?? 4
            var opacity = Double(pref("cmdline.opacity") ?? "") ?? 0.55
            var floating = pref("cmdline.floating") == "1" || pref("cmdline.floating") == "true"
            let k = try await ed.getKeyword("Command line [Size/Lines/Opacity/Float/Dock/Reset]", ["Size", "Lines", "Opacity", "Float", "Dock", "Reset"],
                                            defaultValue: floating ? "Dock" : "Float") ?? "Float"
            switch k {
            case "Size":
                guard let v = try await ed.getDistance("Text size in points (8–20) <" + fmt(fontSize, 1) + ">", defaultValue: fontSize).value, v >= 8, v <= 20 else {
                    throw CommandError.invalid("Enter 8 to 20.")
                }
                fontSize = v
            case "Lines":
                guard let v = try await ed.getInteger("History lines shown (1–40) <" + String(lines) + ">", defaultValue: lines), (1...40).contains(v) else {
                    throw CommandError.invalid("Enter 1 to 40.")
                }
                lines = v
            case "Opacity":
                guard let v = try await ed.getDistance("Background opacity (0.1–1) <" + fmt(opacity, 2) + ">", defaultValue: opacity).value, v >= 0.1, v <= 1 else {
                    throw CommandError.invalid("Enter 0.1 to 1.")
                }
                opacity = v
            case "Float": floating = true
            case "Dock": floating = false
            default:
                fontSize = 11; lines = 4; opacity = 0.55; floating = false
            }
            setPref("cmdline.fontSize", fmt(fontSize, 2))
            setPref("cmdline.lines", String(lines))
            setPref("cmdline.opacity", fmt(opacity, 2))
            setPref("cmdline.floating", floating ? "1" : "0")
            var v = EngineObject()
            v.set("fontSize", fontSize)
            v.set("lines", lines)
            v.set("opacity", opacity)
            v.set("floating", floating)
            v.set("reset", k == "Reset")
            try host(ed, "preference", [("key", .string("cmdline")), ("value", v.json)])
            ed.print("Command line: " + fmt(fontSize, 1) + " pt, " + String(lines) + " line(s), opacity " + fmt(opacity, 2) + ", " + (floating ? "floating" : "docked") + ".")
        }
    }

    static var crashReports: CommandDef {
        CommandDef("CRASHREPORTS", aliases: ["CRASHREPORT", "CRASHLOG"], category: "Settings",
                   summary: "Opt-in crash reports: On, Off, Status, Show the saved reports (reviewed and sent only by you), Clear.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let k = try await ed.getKeyword("Crash reports [On/Off/Status/Show/Clear]", ["On", "Off", "Status", "Show", "Clear"], defaultValue: "Status") ?? "Status"
            if k == "On" || k == "Off" { setPref("crashReports", k == "On" ? "1" : "0") }
            try host(ed, "crashReports", [("op", .string(k))])
        }
    }

    // MARK: Windows and tabs

    static var fileTab: CommandDef {
        CommandDef("FILETAB", category: "View", summary: "Shows the file tab bar with one tab per open drawing.", modifies: false) { ed in
            setPref("fileTabs", "1")
            try host(ed, "fileTabs", [("on", .bool(true))])
            ed.print("File tabs on.")
        }
    }

    static var fileTabClose: CommandDef {
        CommandDef("FILETABCLOSE", category: "View", summary: "Hides the file tab bar.", modifies: false) { ed in
            setPref("fileTabs", "0")
            try host(ed, "fileTabs", [("on", .bool(false))])
            ed.print("File tabs off.")
        }
    }

    static var windowTabs: CommandDef {
        CommandDef("WINDOWTABS", aliases: ["DOCTABS"], category: "View",
                   summary: "Window tabs: Merge all drawing windows into tabs, or open new drawings in Tabs / Windows.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            guard let k = try await ed.getKeyword("Option [Merge/Tabs/Windows]", ["Merge", "Tabs", "Windows"], defaultValue: "Merge") else { return }
            try host(ed, "windowTabs", [("op", .string(k))])
            switch k {
            case "Merge": ed.print("Drawing windows merged into tabs.")
            case "Tabs": ed.print("New drawings open as tabs.")
            default: ed.print("New drawings open in their own windows.")
            }
        }
    }

    static var sysWindows: CommandDef {
        CommandDef("SYSWINDOWS", aliases: ["ARRANGEWINDOWS", "TILEWINDOWS", "WINDOWS"], category: "View",
                   summary: "Arranges the open drawing windows: Vertical (side by side), Horizontal, Cascade, Tabs or Separate windows.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let k = try await ed.getKeyword("Arrange [Vertical/Horizontal/Cascade/Tabs/Separate]", ["Vertical", "Horizontal", "Cascade", "Tabs", "Separate"],
                                            defaultValue: "Vertical") ?? "Vertical"
            try host(ed, "arrangeWindows", [("mode", .string(k))])
        }
    }

    static var fullScreen: CommandDef {
        CommandDef("FULLSCREEN", aliases: ["FS"], category: "View", summary: "Enters or leaves full screen for this drawing window.", modifies: false) { ed in
            try host(ed, "fullScreen")
        }
    }
}

extension EngineSession {
    /// Panels, views, windows and settings commands (EngineWorkspaceCommands).
    public static func registerWorkspaceCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineWorkspaceCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
    }
}
