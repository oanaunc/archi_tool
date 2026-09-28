// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac UI-layer commands for text, selection and inspection: SPELLDIALOG
// (AppCommandsExtra.swift), TEXTSTYLEDIALOG and TEXTEDITINPLACE (AppCommandsRound12.swift), HYPERLINK
// (AppCommandsRound9.swift), SELECTIONINFO (AppCommandsStudio.swift), QUICKPROPS, INSPECT and SELECTWALLCHAIN
// (AppCommandsNav.swift). Same names, aliases, categories, prompts and messages; where the Mac opens a window the
// engine asks the Windows shell with a `host` notification (docs/ENGINE-PROTOCOL.md "Schedules, browser, text and
// selection tools"). Registered by archi-engine only (EngineSession.registerToolCommands).
import Foundation

enum EngineDocCommands {
    static var all: [CommandDef] {
        [spellDialog, textStyleDialog, textEditInPlace, hyperlink, selectionInfo, quickProps, inspect, selectWallChain]
    }

    static var spellDialog: CommandDef {
        CommandDef("SPELLDIALOG", aliases: ["SPELLING", "CHECKSPELLING"], category: "Annotate",
                   summary: "Spelling dialog: lists misspelled words in text, leaders, tables and attributes with suggestions (Change / Ignore / Add).", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "spelling")
        }
    }

    static var textStyleDialog: CommandDef {
        CommandDef("TEXTSTYLEDIALOG", aliases: ["TEXTSTYLEMANAGER", "STYLEDIALOG"], category: "Annotate",
                   summary: "Text Style manager: font, height, width factor and oblique angle with a live preview; renaming a style updates its text.", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "textStyles")
        }
    }

    static var textEditInPlace: CommandDef {
        CommandDef("TEXTEDITINPLACE", aliases: ["MTEDIT", "INPLACETEXT", "TEXTFORMAT"], category: "Annotate",
                   summary: "In-place text editor on the canvas: bold, italic, underline, font, height and colour (also opened by double-clicking text); exported to PDF and DXF MTEXT.", modifies: false) { ed in
            guard let id = try await ed.getEntity("Select text"), case .text? = ed.doc.entity(id)?.geometry else { throw CommandError.invalid("Select a text object.") }
            try EngineUICommands.host(ed, "textEditor", [("id", .int(id))])
        }
    }

    static var hyperlink: CommandDef {
        CommandDef("HYPERLINK", aliases: ["LINK", "URL", "-HYPERLINK"], category: "Annotate",
                   summary: "Attaches a URL (web page or file) to objects; exported PDFs make them clickable. Empty removes the link.") { ed in
            let ids = try await ed.getSelection("Select objects")
            guard !ids.isEmpty else { return }
            let cur = ids.lazy.compactMap { ed.doc.entity($0)?.props["hyperlink"] ?? ed.doc.element($0)?.props["hyperlink"] }.first ?? ""
            guard let u = try await ed.getString("Enter hyperlink (URL) <" + cur + ">", defaultValue: cur) else { return }
            let url = u.trimmingCharacters(in: .whitespaces)
            let value: String? = url.isEmpty ? nil : url
            for id in ids {
                if let i = ed.doc.entities.firstIndex(where: { $0.id == id }) { ed.doc.entities[i].props["hyperlink"] = value }
                if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["hyperlink"] = value }
            }
            ed.print(url.isEmpty ? "Hyperlink removed from \(ids.count) object(s)." : "\(ids.count) object(s) link to " + url + ".")
        }
    }

    static var selectionInfo: CommandDef {
        CommandDef("SELECTIONINFO", aliases: ["SELINFO", "SELECTIONPANEL"], category: "Inquiry",
                   summary: "Selection info panel: count and types of the selected objects, layers, total length/area, keep-only/remove filters.", modifies: false) { ed in
            try EngineUICommands.host(ed, "showPanel", [("panel", .string("Selection"))])
        }
    }

    static var quickProps: CommandDef {
        CommandDef("QUICKPROPS", aliases: ["QP", "QUICKPROPERTIES"], category: "View",
                   summary: "Quick Properties: a compact editor of the selection's key properties over the drawing.", modifies: false) { ed in
            guard let k = try await ed.getKeyword("Quick Properties [ON/OFF/Toggle]", ["ON", "OFF", "Toggle"], defaultValue: "Toggle") else { return }
            let mode = k == "ON" ? "on" : (k == "OFF" ? "off" : "toggle")
            try EngineUICommands.host(ed, "quickProps", [("mode", .string(mode))])
        }
    }

    static var inspect: CommandDef {
        CommandDef("INSPECT", aliases: ["OBJECTINFO", "LISTPANEL"], category: "Inquiry",
                   summary: "Opens the Inspector panel: every stored value of the selected objects, with ID and GUID.", modifies: false) { ed in
            if ed.selection.isEmpty { ed.selection = Set(try await ed.getSelection("Select objects to inspect")) }
            try EngineUICommands.host(ed, "showPanel", [("panel", .string("Inspector"))])
            for id in ed.selection.sorted().prefix(3) {
                let lines = EngineInspector.text(id, doc: ed.doc).split(separator: "\n").prefix(8)
                ed.print(lines.joined(separator: " · "))
            }
        }
    }

    static var selectWallChain: CommandDef {
        CommandDef("SELECTWALLCHAIN", aliases: ["WALLCHAIN"], category: "Select",
                   summary: "Selects the chain of walls joined to a picked wall (Tab over a wall does the same).", modifies: false) { ed in
            guard let id = try await ed.getEntity("Select a wall") else { return }
            let chain = EngineWallChain.ids(from: id, doc: ed.doc).filter { ed.isSelectable($0) }
            guard !chain.isEmpty else { throw CommandError.invalid("That is not a wall.") }
            ed.selection.formUnion(chain)
            ed.print("\(chain.count) joined wall(s) selected.")
        }
    }
}

extension EngineSession {
    /// Registers the text, selection and inspection commands (archi-engine only; the Mac app has its own).
    public static func registerDocCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineDocCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
    }
}
