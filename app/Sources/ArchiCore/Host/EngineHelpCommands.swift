// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac app's help and window-chrome commands: ABOUT, COMMANDSEARCH, CLEANSCREENON,
// CLEANSCREENOFF and HISTORYPANEL (ArchiApp/AppCommands.swift), STARTSCREEN and EXPORTCOMMANDS (AppCommandsExtra.swift),
// SAMPLEHOUSE (AppCommandsNav.swift) and WHATSNEW (AppCommandsStudio.swift). Same names, aliases, categories, prompts
// and messages; where the Mac shows a window or changes the main window the engine asks the Windows shell with a
// `host` notification (docs/ENGINE-PROTOCOL.md "Help and window commands"). Registered by archi-engine only
// (EngineSession.registerPortableAppCommands); the Mac app registers its own versions.
import Foundation

enum EngineHelpCommands {
    static var all: [CommandDef] {
        [about, commandSearch, cleanScreenOn, cleanScreenOff, historyPanel, startScreen, sampleHouse, whatsNew, exportCommands]
    }

    static var about: CommandDef {
        CommandDef("ABOUT", category: "Help", summary: "About Oanarina Archi Tool: version, license and credits.", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "about")
        }
    }

    static var commandSearch: CommandDef {
        CommandDef("COMMANDSEARCH", aliases: ["CMDSEARCH", "SEARCHCOMMANDS"], category: "Help",
                   summary: "Opens the command search palette (Ctrl+K).", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "commandSearch")
        }
    }

    static var cleanScreenOn: CommandDef {
        CommandDef("CLEANSCREENON", aliases: ["CLEANSCREEN"], category: "View",
                   summary: "Clean screen: hides the ribbon and panels (Ctrl+0 toggles).", modifies: false) { ed in
            try EngineUICommands.host(ed, "cleanScreen", [("on", .bool(true))])
            ed.print("Clean screen on. CLEANSCREENOFF or Ctrl+0 restores the ribbon and panels.")
        }
    }

    static var cleanScreenOff: CommandDef {
        CommandDef("CLEANSCREENOFF", aliases: ["RIBBON", "RB"], category: "View", summary: "Restores the ribbon and panels after CLEANSCREENON.", modifies: false) { ed in
            try EngineUICommands.host(ed, "cleanScreen", [("on", .bool(false))])
            try EngineUICommands.host(ed, "ribbonExpand", [])
        }
    }

    static var historyPanel: CommandDef {
        CommandDef("HISTORYPANEL", aliases: ["UNDOHISTORY", "HISTORY"], category: "View",
                   summary: "Shows the undo history and command history panel.", modifies: false) { ed in
            try EngineUICommands.host(ed, "showPanel", [("panel", .string("History"))])
        }
    }

    static var startScreen: CommandDef {
        CommandDef("STARTSCREEN", aliases: ["START", "WELCOME"], category: "File",
                   summary: "Shows the start screen: templates, samples and recent drawings.", modifies: false) { ed in
            try EngineUICommands.host(ed, "startScreen")
        }
    }

    static var sampleHouse: CommandDef {
        CommandDef("SAMPLEHOUSE", aliases: ["SAMPLE", "OPENSAMPLE"], category: "Help",
                   summary: "Opens the bundled sample house project in a new window.", modifies: false) { ed in
            try EngineUICommands.host(ed, "newWindow", [("kind", .string("sample"))])
            ed.print("Opening the sample house…")
        }
    }

    static var whatsNew: CommandDef {
        CommandDef("WHATSNEW", aliases: ["RELEASENOTES"], category: "Help",
                   summary: "Shows what is new in this version (also shown once after an update).", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "whatsNew")
        }
    }

    /// The shell writes the file: it knows where each command is in the menus and the ribbon ("Where" column).
    static var exportCommands: CommandDef {
        CommandDef("EXPORTCOMMANDS", aliases: ["COMMANDREFEXPORT", "CMDEXPORT"], category: "Help",
                   summary: "Exports the command reference (every registered command: name, aliases, category, summary, where it is in the UI) as Markdown or CSV.",
                   modifies: false) { ed in
            let s = try await ed.getString("Output file (.md or .csv) <choose>", defaultValue: "") ?? ""
            let path = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            let csv = path.lowercased().hasSuffix(".csv")
            try EngineUICommands.host(ed, "exportCommands", [("path", .string(path)), ("csv", .bool(csv)), ("count", .number(Double(ed.registry.sorted.count)))])
        }
    }
}
