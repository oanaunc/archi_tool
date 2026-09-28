// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac UI-layer commands for the tool windows (ArchiApp/AppCommands.swift, AppCommandsReview.swift,
// AppCommandsStudio.swift, AppCommandsRound9/10.swift, TutorialCommands.swift): block library, material library and
// editor, sheet set manager, title block, markups / compare / revision clouds, family editor, customizer, node editor,
// graph player, script console and library, Connect Claude and tutorial videos. Same names, aliases, prompts and
// messages; where the Mac opens a window the engine asks the Windows shell with a `host` notification
// ({"action":"dialog","dialog":…} or {"action":"showPanel"|"scriptConsole"|"scriptLibrary"|"tutorials"}).
// Registered by archi-engine only (EngineSession.registerToolCommands); the Mac app registers its own versions.
import Foundation

enum EngineToolCommands {
    @MainActor static func session(_ ed: Editor) throws -> EngineSession {
        guard let s = (ed.host as? EngineHostBridge)?.session else { throw CommandError.invalid("This command needs a document window.") }
        return s
    }

    @MainActor static func host(_ ed: Editor, _ action: String, _ fields: [(String, EngineJSON)] = []) throws {
        let s = try session(ed)
        var o = EngineObject()
        for (k, v) in fields { o.set(k, v) }
        s.hostNotify(action, o)
    }

    @MainActor static func dialog(_ ed: Editor, _ name: String, _ fields: [(String, EngineJSON)] = []) throws {
        try host(ed, "dialog", [("dialog", .string(name))] + fields)
    }

    /// The sheet the shell shows (CTAB), for the sheet commands.
    @MainActor static func activeSheet(_ ed: Editor) -> Int {
        let n = ed.doc.layouts.count
        guard n > 0 else { return 0 }
        if let c = ed.doc.variable("CTAB"), let i = ed.doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(c) == .orderedSame }) { return i }
        return 0
    }

    static var all: [CommandDef] {
        [blockPalette, matBrowser, materials, titleBlock, sheetSet, sheetIndex, sheetRevision, markupPanel, comparePanel, revCloudPanel,
         familyPanel, customizerPanel, nodeEditor, graphPlayer, scriptConsole, scriptLibrary, connectClaude, tutorialRecord, tutorials]
    }

    static var blockPalette: CommandDef {
        CommandDef("BLOCKPALETTE", aliases: ["BLOCKSPANEL", "CONTENTLIBRARY"], category: "Blocks",
                   summary: "Block library panel: library folders with thumbnails, search, favourites and recents; drag blocks onto the drawing.", modifies: false) { ed in
            try dialog(ed, "blockLibrary")
        }
    }

    static var matBrowser: CommandDef {
        CommandDef("MATBROWSER", aliases: ["MATLIB", "MATERIALLIBRARY"], category: "View",
                   summary: "Material library browser with rendered thumbnails: add to the drawing or assign to the selection.", modifies: false) { ed in
            try dialog(ed, "materialLibrary")
        }
    }

    static var materials: CommandDef {
        CommandDef("MATERIALS", aliases: ["MAT", "RMAT", "MATEDITOR", "MATBROWSEROPEN"], category: "View",
                   summary: "Opens the material editor panel (color, roughness, metalness, transparency, texture).", modifies: false) { ed in
            try host(ed, "showPanel", [("panel", .string("Materials"))])
        }
    }

    static var titleBlock: CommandDef {
        CommandDef("TITLEBLOCK", aliases: ["TBEDIT", "TITLEBLOCKEDIT"], category: "Output",
                   summary: "Edits the active sheet's title block and the project information shown on all sheets.", modifies: false) { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
            try dialog(ed, "titleBlock", [("layout", .int(activeSheet(ed)))])
        }
    }

    static var sheetSet: CommandDef {
        CommandDef("SHEETSET", aliases: ["SSM", "SHEETSETMANAGER", "SHEETS"], category: "Output",
                   summary: "Sheet set manager: numbering, order, duplicate, revisions, sheet index.", modifies: false) { ed in
            try host(ed, "showPanel", [("panel", .string("Sheets"))])
        }
    }

    static var sheetIndex: CommandDef {
        CommandDef("SHEETINDEX", aliases: ["SHEETLIST", "DRAWINGLIST"], category: "Output",
                   summary: "Places or refreshes the sheet list table (number, title, paper, revision) on the active sheet.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
            let i = activeSheet(ed)
            EngineSheets.placeIndex(&ed.doc, on: i)
            ed.print("Sheet index with \(ed.doc.layouts.count) sheet(s) on \(ed.doc.layouts[i].name).")
        }
    }

    static var sheetRevision: CommandDef {
        CommandDef("SHEETREVISION", aliases: ["REVISION", "REVTABLE", "ADDREVISION"], category: "Output",
                   summary: "Adds a revision (next code, date, description, by) to the active sheet's revision table.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
            let i = activeSheet(ed)
            let next = EngineSheets.nextCode(after: EngineSheets.revisions(ed.doc.layouts[i]).last?.code)
            guard let d = try await ed.getString("Revision \(next) description"), !d.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let author = ed.doc.info.author
            let by = try await ed.getString("Revised by <\(author)>", defaultValue: author) ?? author
            EngineSheets.addRevision(&ed.doc, i, description: d.trimmingCharacters(in: .whitespaces), by: by)
            EngineSheets.refreshIndexes(&ed.doc)
            ed.print("Revision \(next) added to \(ed.doc.layouts[i].name).")
        }
    }

    static var markupPanel: CommandDef {
        CommandDef("MARKUPPANEL", aliases: ["ISSUES", "MARKUPMANAGER"], category: "Collaborate",
                   summary: "Opens the markup/issue panel: filter open/resolved, reply, resolve, zoom to, link to the selection, BCF.", modifies: false) { ed in
            try dialog(ed, "markups")
        }
    }

    static var comparePanel: CommandDef {
        CommandDef("COMPAREPANEL", aliases: ["COMPAREOVERLAY"], category: "Collaborate",
                   summary: "Compares with another version and draws the differences over the plan (added green, removed red, modified yellow).", modifies: false) { ed in
            try dialog(ed, "compare")
        }
    }

    static var revCloudPanel: CommandDef {
        CommandDef("REVCLOUDPANEL", aliases: ["SHEETCLOUDS"], category: "Output",
                   summary: "Sheet revision clouds: add a cloud with a revision triangle around a viewport or an area of a sheet, list, open, delete.", modifies: false) { ed in
            try dialog(ed, "revisionClouds")
        }
    }

    static var familyPanel: CommandDef {
        CommandDef("FAMILYPANEL", aliases: ["FAMPANEL", "FAMILYWINDOW"], category: "Architecture",
                   summary: "Family Editor panel: families list, parameters and formulas, forms, types table, reference planes, profiles, live 3D preview and flex; Apply is one undo step.", modifies: false) { ed in
            let names = ed.doc.families.map(\.name)
            var fam = ""
            if !names.isEmpty { fam = try await ed.getString("Family to edit [\(names.joined(separator: "/"))] (Enter = current)", defaultValue: "") ?? "" }
            if !fam.isEmpty, ed.doc.family(named: fam) == nil { throw CommandError.invalid("Unknown family \(fam).") }
            try dialog(ed, "familyEditor", [("family", fam.isEmpty ? .null : .string(ed.doc.family(named: fam)?.name ?? fam))])
        }
    }

    static var customizerPanel: CommandDef {
        CommandDef("CUSTOMIZERPANEL", aliases: ["PARAMPANEL", "SCADPANEL"], category: "3D",
                   summary: "Customizer panel: sliders, check boxes and choices for the parameters of the selected scripted object (OpenSCAD customizer comments), regenerating it on change.", modifies: false) { ed in
            try dialog(ed, "customizer")
        }
    }

    static var nodeEditor: CommandDef {
        CommandDef("NODEEDITOR", aliases: ["NODES", "VISUALSCRIPT", "GRAPH"], category: "Scripting",
                   summary: "Visual node editor (number, point, line, circle, extrude, array…) with live preview; bakes geometry into the drawing.", modifies: false) { ed in
            try dialog(ed, "nodeEditor")
        }
    }

    /// Graphs available to play: the current one and the named ones (GraphPlayer.graphs).
    static func playableGraphs(_ doc: ArchiDocument) -> [(name: String, graph: NodeGraph)] {
        var out: [(String, NodeGraph)] = []
        if let g = NodeGraph.load(doc) { out.append(("Current", g)) }
        for n in NodeGraph.names(doc) { if let g = NodeGraph.load(doc, name: n) { out.append((n, g)) } }
        return out
    }

    static var graphPlayer: CommandDef {
        CommandDef("GRAPHPLAYER", aliases: ["PLAYER", "RUNGRAPH", "PLAYGRAPH"], category: "Scripting",
                   summary: "Graph player: runs a saved node graph with its exposed Number inputs (clamped to their ranges) and bakes the result; Window opens the player panel.") { ed in
            let all = playableGraphs(ed.doc)
            guard !all.isEmpty else { throw CommandError.invalid("No saved node graphs (NODEEDITOR).") }
            ed.print("Graphs: " + all.map(\.name).joined(separator: ", "))
            let n = (try await ed.getWord("Graph name or Window <\(all[0].name)>", defaultValue: all[0].name) ?? all[0].name).trimmingCharacters(in: .whitespaces)
            if n.caseInsensitiveCompare("Window") == .orderedSame || n.caseInsensitiveCompare("W") == .orderedSame { try dialog(ed, "graphPlayer"); return }
            guard var g = all.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame })?.graph else { throw CommandError.invalid("No graph \(n).") }
            for node in g.nodes where node.kind == .number {
                let lo0 = node.param("min", 0), hi0 = node.param("max", 10000)
                let lo = min(lo0, hi0), hi = max(lo0, hi0)
                let v0 = node.param("value", 0)
                let name = g.parameterName(node)
                let v = try await ed.getDistance("\(name) (\(fmt(lo)) – \(fmt(hi))) <\(fmt(v0))>", defaultValue: v0).value ?? v0
                if let i = g.nodes.firstIndex(where: { $0.id == node.id }) { g.nodes[i].params["value"] = min(max(v, lo), hi) }
            }
            let ev = g.evaluate()
            let ids = NodeGraphBake.bake(ev.output, elements: ev.elementOutput, into: &ed.doc)
            for (id, e) in ev.errors.sorted(by: { $0.key < $1.key }) { ed.print("  node \(id): \(e)") }
            ed.print("Baked \(ids.count) object(s).")
        }
    }

    static var scriptConsole: CommandDef {
        CommandDef("SCRIPTCONSOLE", aliases: ["JS", "JSCONSOLE", "CONSOLE"], category: "Scripting",
                   summary: "Shows or hides the JavaScript console (Ctrl+Alt+J).", modifies: false) { ed in
            try host(ed, "scriptConsole")
        }
    }

    static var scriptLibrary: CommandDef {
        CommandDef("SCRIPTLIBRARY", aliases: ["SCRIPTS"], category: "Scripting",
                   summary: "Opens the script library folder (startup.js runs in every new window).", modifies: false) { ed in
            try host(ed, "scriptLibrary")
        }
    }

    static var connectClaude: CommandDef {
        CommandDef("CONNECTCLAUDE", aliases: ["MCPHELP", "CLAUDE"], category: "Scripting",
                   summary: "Explains how to connect Claude (archi-engine --mcp or the local agent server).", modifies: false) { ed in
            try dialog(ed, "connectClaude")
        }
    }

    static var tutorialRecord: CommandDef {
        CommandDef("TUTORIALRECORD", aliases: ["RECORDTUTORIALS", "TUTORIALVIDEOS", "TUTREC"], category: "Tools",
                   summary: "Tutorial videos: List the scripted tutorials, Check them, or Record (the videos are recorded by the Mac app; on Windows Record opens the tutorial videos on the website).", modifies: false) { ed in
            let k = try await ed.getKeyword("Tutorials [List/Record/Check]", ["List", "Record", "Check"], defaultValue: "List") ?? "List"
            try host(ed, "tutorials", [("mode", .string(k))])
        }
    }

    static var tutorials: CommandDef {
        CommandDef("TUTORIALS", aliases: ["TUTORIAL", "LEARN"], category: "Help",
                   summary: "Opens the step-by-step tutorials and the sample project in the help browser.", modifies: false) { ed in
            try host(ed, "tutorials", [("mode", .string("Open"))])
        }
    }
}

extension EngineSession {
    /// Registers the portable tool-window commands (archi-engine only; the Mac app has its own).
    public static func registerToolCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineToolCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        registerCanvasCommands(registry)
        registerDocCommands(registry)
        registerWorkspaceCommands(registry)
    }
}
