// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import UniformTypeIdentifiers
import ArchiCore

/// More app-level commands: constraint bar, spell checker, section plane, animation and panorama export, plot styles,
/// batch publish, templates, start screen and theme. All are registered like core commands (command line, scripts, agents).
@MainActor
enum AppCommandsExtra {
    static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppModels.model(for: ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }

    /// Installs the macOS spell checker for SPELL (core `SpellCheck` hooks).
    static func installSpellChecker() {
        SpellCheck.checker = { word in
            let r = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0)
            return r.location == NSNotFound
        }
        SpellCheck.suggester = { word in
            NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: nil, inSpellDocumentWithTag: 0) ?? []
        }
    }

    /// Output path from a typed answer or a save panel ("" or "?" asks).
    static func outputURL(_ typed: String?, types: [UTType], suggested: String) -> URL? {
        if let t = typed?.trimmingCharacters(in: .whitespaces), !t.isEmpty, t != "?" {
            return URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
        }
        let p = NSSavePanel()
        p.allowedContentTypes = types
        p.nameFieldStringValue = suggested
        if let d = FileLocations.exportFolder { p.directoryURL = d }
        return p.runModal() == .OK ? p.url : nil
    }

    static var all: [CommandDef] {
        [
            CommandDef("SPELLDIALOG", aliases: ["SPELLING", "CHECKSPELLING"], category: "Annotate",
                       summary: "Spelling dialog: lists misspelled words in text, leaders, tables and attributes with suggestions (Change / Ignore / Add).", modifies: false) { ed in
                let m = try ui(ed)
                m.sheet = .spelling
            },
            CommandDef("SECTIONPLANE", aliases: ["SPLANE", "CUTPLANE", "LIVESECTION"], category: "View",
                       summary: "Live section plane in 3D with cap faces: Horizontal at a height, Vertical through two plan points, Flip, Off.") { ed in
                let k = try await ed.getKeyword("Section plane [Horizontal/Vertical/Flip/Off]", ["Horizontal", "Vertical", "Flip", "Off"], defaultValue: "Horizontal") ?? "Horizontal"
                var plane: SectionPlane?
                switch k {
                case "Off":
                    if var p = SectionPlane.load(ed.doc) { p.on = false; p.store(in: &ed.doc) }
                    ed.print("Section plane off."); return
                case "Flip":
                    guard let p = SectionPlane.load(ed.doc) else { throw CommandError.invalid("No section plane yet.") }
                    plane = p.flipped
                case "Vertical":
                    let a = try await ed.requirePoint("First point of the cut line")
                    let b = try await ed.requirePoint("Second point (the left side is removed)", base: a, preview: { p in [.line(LineGeom(a, p))] })
                    guard let p = SectionPlane.vertical(a, b) else { throw CommandError.invalid("The two points coincide.") }
                    plane = p
                default:
                    let lvl = ed.doc.level(ed.doc.currentLevel)
                    let def = (lvl?.elevation ?? 0) + 1200 / max(ed.doc.units.mm, 1e-9)
                    guard let z = try await ed.getDistance("Cut height", defaultValue: def).value else { return }
                    plane = .horizontal(z: z)
                }
                plane?.store(in: &ed.doc)
                if let m = AppModels.model(for: ed), m.mode == .plan || m.mode == .sheet { m.mode = .model }
                ed.print("Section plane \(k == "Flip" ? "flipped" : "on"). SECTIONPLANE Off removes it.")
            },
            CommandDef("WALKTHROUGHVIDEO", aliases: ["WALKVIDEO", "ANIPATH", "CAMERAPATH"], category: "View",
                       summary: "Exports an MP4 walkthrough along a smooth path through the saved cameras (in order).", modifies: false) { ed in
                let m = try ui(ed)
                let cams = ed.doc.namedViews.compactMap(\.camera)
                guard cams.count >= 2 else { throw CommandError.invalid("Save at least two cameras with SAVECAMERA first.") }
                guard let secs = try await ed.getDistance("Duration in seconds", defaultValue: 10).value, secs > 0 else { return }
                let path = try await ed.getString("Output file (.mp4) <choose>", defaultValue: "")
                guard let url = outputURL(path, types: [.mpeg4Movie], suggested: "\(m.displayName) walkthrough.mp4") else { return }
                var s = RenderSettings(); s.width = 1280; s.height = 720
                ed.print("Rendering walkthrough (\(cams.count) cameras, \(fmt(CameraPath.length(cams) / 1000, 1)) m of path)…")
                try await RenderEngine.walkthrough(doc: ed.doc, settings: s, cameras: cams, seconds: min(secs, 600), to: url) { _ in }
                ed.print("Saved \(url.path)")
            },
            CommandDef("SUNSTUDYVIDEO", aliases: ["SUNVIDEO", "SHADOWSTUDY"], category: "View",
                       summary: "Exports an MP4 sun-study time-lapse (shadows through the day) from the current 3D camera.", modifies: false) { ed in
                let m = try ui(ed)
                guard let day = try await ed.getInteger("Day of year (172 = 21 June)", defaultValue: 172), (1...366).contains(day) else { return }
                guard let a = try await ed.getDistance("Start hour", defaultValue: 7).value, let b = try await ed.getDistance("End hour", defaultValue: 19).value else { return }
                guard b > a else { throw CommandError.invalid("The end hour must be after the start hour.") }
                let path = try await ed.getString("Output file (.mp4) <choose>", defaultValue: "")
                guard let url = outputURL(path, types: [.mpeg4Movie], suggested: "\(m.displayName) sun study.mp4") else { return }
                var s = RenderSettings(); s.width = 1280; s.height = 720
                try await RenderEngine.sunStudy(doc: ed.doc, settings: s, dayOfYear: day, fromHour: a, toHour: b, seconds: 10,
                                                camera: m.viewport3D?.currentCamera, to: url) { _ in }
                ed.print("Saved \(url.path)")
            },
            CommandDef("PANORAMA", aliases: ["360", "PANO", "RENDER360"], category: "View",
                       summary: "Renders a 360° equirectangular panorama (PNG/JPEG) from the 3D camera position or a picked plan point.", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Eye position [Camera/Point]", ["Camera", "Point"], defaultValue: m.viewport3D == nil ? "Point" : "Camera") ?? "Camera"
                var eye: Vec3
                if k == "Point" {
                    let p = try await ed.requirePoint("Eye position in plan")
                    let base = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
                    eye = Vec3(p.x, p.y, base + 1600 / max(ed.doc.units.mm, 1e-9))
                } else {
                    guard let c = m.viewport3D?.currentCamera else { throw CommandError.invalid("Open the 3D view first, or use Point.") }
                    eye = c.eye
                }
                guard let w = try await ed.getInteger("Width in pixels (height = width / 2)", defaultValue: 4096), w >= 256 else { return }
                let path = try await ed.getString("Output file (.jpg/.png) <choose>", defaultValue: "")
                guard let url = outputURL(path, types: [.jpeg, .png], suggested: "\(m.displayName) 360.jpg") else { return }
                guard let img = RenderEngine.panorama(doc: ed.doc, settings: RenderSettings(), eye: eye, width: min(w, 8192)) else { throw CommandError.invalid("Rendering failed (Metal unavailable).") }
                try RenderEngine.write(img, to: url)
                ed.print("Saved \(img.width)×\(img.height) panorama to \(url.path)")
            },
            CommandDef("PLOTSTYLE", aliases: ["CTB", "PLOTSTYLES", "STYLESMANAGER"], category: "Output",
                       summary: "Plot style tables (colour → pen colour, lineweight, screening): Edit, Set for the sheet/model, List.") { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Plot styles [Edit/Set/List]", ["Edit", "Set", "List"], defaultValue: "Edit") ?? "Edit"
                let tables = PlotStyleTable.all(ed.doc)
                switch k {
                case "List":
                    for t in tables { ed.print("  \(t.name) — \(t.pens.count) pen(s)") }
                case "Set":
                    let names = tables.map(\.name).joined(separator: ", ")
                    guard let n = try await ed.getString("Table name (\(names), or None)", defaultValue: "monochrome.ctb") else { return }
                    let li = m.mode == .sheet ? m.activeLayout : -1
                    var setup = PageSetup.load(ed.doc, layoutIndex: li >= 0 ? li : nil)
                    if n.lowercased() == "none" { setup.plotStyleTable = nil }
                    else {
                        guard let t = PlotStyleTable.named(n, in: ed.doc) else { throw CommandError.invalid("No plot style table \"\(n)\".") }
                        setup.plotStyleTable = t.name
                    }
                    setup.store(in: &ed.doc, layoutIndex: li >= 0 ? li : nil)
                    ed.print("Plot style of \(li >= 0 ? "sheet " + ed.doc.layouts[li].name : "model space"): \(setup.plotStyleTable ?? "none").")
                default:
                    m.sheet = .plotStyles
                }
            },
            CommandDef("BATCHPUBLISH", aliases: ["PUBLISHSET", "BATCHPLOTPDF"], category: "Output",
                       summary: "Publishes chosen sheets to one PDF with bookmarks (sheet number and name) and optional sheet index.", modifies: false) { ed in
                let m = try ui(ed)
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
                let k = try await ed.getKeyword("Publish [Dialog/All]", ["Dialog", "All"], defaultValue: "Dialog") ?? "Dialog"
                if k == "Dialog" { m.sheet = .batchPublish; return }
                let path = try await ed.getString("Output PDF <choose>", defaultValue: "")
                guard let url = outputURL(path, types: [.pdf], suggested: "\(m.displayName) — sheets.pdf") else { return }
                try Plotter.publishPDF(doc: ed.doc, layouts: Array(ed.doc.layouts.indices), to: url, bookmarks: true)
                ed.print("Published \(ed.doc.layouts.count) sheet(s) with bookmarks to \(url.path)")
            },
            CommandDef("STARTSCREEN", aliases: ["START", "WELCOME"], category: "File", summary: "Shows the start screen: templates, samples and recent drawings.", modifies: false) { ed in
                let m = try ui(ed)
                m.showStart = true
            },
            CommandDef("NEWFROMTEMPLATE", aliases: ["NEWTEMPLATE", "QNEW"], category: "File",
                       summary: "Starts a new drawing from a template (built-in or from the templates folder).", modifies: false) { ed in
                let m = try ui(ed)
                let list = TemplateLibrary.all()
                ed.print("Templates: " + list.map(\.name).joined(separator: ", "))
                guard let n = try await ed.getString("Template name", defaultValue: list.first?.name ?? "") else { return }
                guard let t = list.first(where: { $0.name.caseInsensitiveCompare(n.trimmingCharacters(in: .whitespaces)) == .orderedSame }) else { throw CommandError.invalid("No template \"\(n)\".") }
                if m.isDirty || !(ed.doc.entities.isEmpty && ed.doc.elements.isEmpty) { WindowRouter.open(DocumentRequest(kind: .template, path: t.id)) }
                else { TemplateLibrary.apply(t, to: m) }
            },
            CommandDef("SAVEASTEMPLATE", aliases: ["SAVETEMPLATE", "TEMPLATESAVE"], category: "File",
                       summary: "Saves the drawing's settings, layers, styles and content as a template in the templates folder.", modifies: false) { ed in
                let def = ed.doc.info.name == "Untitled Project" ? "My Template" : ed.doc.info.name
                guard let n = try await ed.getString("Template name <\(def)>", defaultValue: def), !n.isEmpty else { return }
                let url = try TemplateLibrary.save(ed.doc, name: n)
                ed.print("Template saved: \(url.path)")
            },
            CommandDef("EXPORTCOMMANDS", aliases: ["COMMANDREFEXPORT", "CMDEXPORT"], category: "Help",
                       summary: "Exports the command reference (every registered command: name, aliases, category, summary, where it is in the UI) as Markdown or CSV.", modifies: false) { ed in
                let path = try await ed.getString("Output file (.md or .csv) <choose>", defaultValue: "")
                guard let url = outputURL(path, types: [.plainText, .commaSeparatedText], suggested: "Oanarina Archi Tool commands.md") else { return }
                let text = CommandReferenceExport.text(ed.registry, csv: url.pathExtension.lowercased() == "csv")
                try text.write(to: url, atomically: true, encoding: .utf8)
                ed.print("Exported \(ed.registry.sorted.count) commands to \(url.path)")
            },
            CommandDef("PLOTLOG", aliases: ["PLOTHISTORY"], category: "Output", summary: "Shows the plot log (every plot, PDF export and publish with date, sheets and plot style) [List/Open/Clear].", modifies: false) { ed in
                let k = try await ed.getKeyword("Plot log [List/Open/Clear]", ["List", "Open", "Clear"], defaultValue: "List") ?? "List"
                switch k {
                case "Open": PlotLog.ensure(); NSWorkspace.shared.open(PlotLog.url)
                case "Clear": try? FileManager.default.removeItem(at: PlotLog.url); ed.print("Plot log cleared.")
                default:
                    let rows = PlotLog.entries()
                    if rows.isEmpty { ed.print("The plot log is empty.") }
                    for r in rows.suffix(20) { ed.print("  " + r.joined(separator: "  ·  ")) }
                }
            },
            CommandDef("THEME", aliases: ["COLORTHEME", "APPEARANCE"], category: "Settings", summary: "Switches the interface theme [Dark/Light].", modifies: false) { ed in
                let k = try await ed.getKeyword("Theme [Dark/Light]", ["Dark", "Light"], defaultValue: Theme.light ? "Dark" : "Light") ?? "Dark"
                AppPreferences.shared.theme = k.lowercased()
                ed.print("\(k) theme.")
            },
        ]
    }
}

/// Finds the window model of an editor.
@MainActor
enum AppModels {
    static func model(for ed: Editor) -> AppModel? { AppModel.all.first { $0.editor === ed } }
}

/// Command reference as Markdown or CSV (every registered command).
@MainActor
enum CommandReferenceExport {
    /// Where a command is in the UI: the first catalog that lists it.
    static func location(_ d: CommandDef, registry: CommandRegistry) -> String {
        let sections: [(String, [CmdItem])] = CommandCatalog.menus + CommandCatalog.extraMenus.flatMap { m in m.1.map { ("\(m.0) ▸ \($0.0)", $0.1) } }
            + [("Home ▸ Selection", CommandCatalog.selection), ("Home ▸ Groups", CommandCatalog.groups), ("Insert ▸ Import", CommandCatalog.importItems),
               ("Insert ▸ Block & Reference", CommandCatalog.referenceItems), ("Insert ▸ Export", CommandCatalog.exportItems),
               ("Architecture ▸ Build+", CommandCatalog.buildMore), ("Architecture ▸ Room & Area", CommandCatalog.roomsMore), ("Architecture ▸ Documentation", CommandCatalog.documentation)]
            + CommandCatalog.coverageMenus.map { ("Tools ▸ \($0.0)", $0.1) }
        for (name, items) in sections where items.contains(where: { i in i.names.contains { registry.lookup($0)?.name == d.name } }) { return name }
        if let why = CommandCatalog.intentional(d) { return why }
        return "Command line"
    }

    static func text(_ registry: CommandRegistry, csv: Bool) -> String {
        let cmds = registry.sorted
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        if csv {
            return (["Command,Aliases,Category,Summary,Location"] + cmds.map { d in
                [d.name, d.aliases.joined(separator: " "), d.category, d.summary, location(d, registry: registry)].map(q).joined(separator: ",")
            }).joined(separator: "\n") + "\n"
        }
        var out = "# Oanarina Archi Tool — command reference\n\n\(cmds.count) commands. Every command also runs from the command line, scripts (`archi.run`) and the agent server.\n"
        for (cat, list) in Dictionary(grouping: cmds, by: \.category).sorted(by: { $0.key < $1.key }) {
            out += "\n## \(cat)\n\n| Command | Aliases | Summary | Where |\n|---|---|---|---|\n"
            for d in list {
                out += "| `\(d.name)` | \(d.aliases.joined(separator: ", ")) | \(d.summary.replacingOccurrences(of: "|", with: "/")) | \(location(d, registry: registry)) |\n"
            }
        }
        return out
    }
}

/// Plot log: one CSV line per plot, PDF export or publish (Application Support/Oanarina Archi Tool/Plot Log.csv).
enum PlotLog {
    static var url: URL { FileLocations.appSupport.appendingPathComponent("Plot Log.csv") }
    static func ensure() {
        try? FileManager.default.createDirectory(at: FileLocations.appSupport, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try? "Date,Drawing,Output,Sheets,Plot style,File\n".write(to: url, atomically: true, encoding: .utf8) }
    }
    static func record(drawing: String, output: String, sheets: String, style: String, file: String) {
        ensure()
        let f = ISO8601DateFormatter()
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let line = [f.string(from: Date()), drawing, output, sheets, style, file].map(q).joined(separator: ",") + "\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    }
    static func entries() -> [[String]] {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return t.split(separator: "\n").dropFirst().map { line in
            var fields: [String] = [], cur = "", quoted = false
            for ch in line {
                if ch == "\"" { quoted.toggle(); continue }
                if ch == "," && !quoted { fields.append(cur); cur = ""; continue }
                cur.append(ch)
            }
            fields.append(cur)
            return fields
        }
    }
}
