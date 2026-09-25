// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum FileViewCommands {
    static var all: [CommandDef] { files + views + sheets + help }

    /// Performs a host action, or explains that it needs the application.
    @MainActor static func host(_ ed: Editor, _ a: HostAction) {
        if let h = ed.host { h.perform(a, editor: ed) } else { ed.print("This command needs the application window (no host attached).") }
    }

    // MARK: - Files
    static var files: [CommandDef] { [
        CommandDef("NEW", aliases: ["QNEW"], category: "File", summary: "Creates a new drawing.", modifies: false) { ed in
            if ed.host == nil { ed.replaceDocument(ArchiDocument(), url: nil); ed.print("New drawing."); return }
            host(ed, .newDocument)
        },
        CommandDef("OPEN", category: "File", summary: "Opens a drawing (.archi, .dxf).", modifies: false) { ed in
            let path = try await ed.getWord("Enter file name (Enter = choose)")
            if ed.host == nil, let p = path {
                let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
                do { let d = try ArchiFile.decode(try Data(contentsOf: url)); ed.replaceDocument(d, url: url); ed.print("Opened \(url.lastPathComponent).") }
                catch { throw CommandError.invalid("Cannot open \(url.path): \(error.localizedDescription)") }
                return
            }
            host(ed, .open(path))
        },
        CommandDef("SAVE", aliases: ["QSAVE"], category: "File", summary: "Saves the drawing.", modifies: false) { ed in
            if ed.host == nil {
                guard let url = ed.fileURL else { throw CommandError.invalid("The drawing has no file name yet; use SAVEAS.") }
                try save(ed, url); return
            }
            host(ed, .save(ed.fileURL?.path))
        },
        CommandDef("SAVEAS", aliases: ["SA"], category: "File", summary: "Saves the drawing under a new name.", modifies: false) { ed in
            let path = try await ed.getWord("Enter file name (Enter = choose)")
            if ed.host == nil {
                guard let p = path else { throw CommandError.invalid("Enter a file name.") }
                try save(ed, BlockCommands.expand(p)); return
            }
            host(ed, .saveAs(path))
        },
        CommandDef("EXPORT", aliases: ["EXP"], category: "File", summary: "Exports the drawing (PDF, DXF, SVG, OBJ, STL, GLB, IFC, CSV, PNG).", modifies: false) { ed in
            let f = try await ed.getKeyword("Enter format", ["PDF", "DXF", "SVG", "OBJ", "STL", "GLB", "IFC", "CSV", "PNG", "Window"], defaultValue: ed.doc.variable("EXPORTFORMAT") ?? "PDF") ?? "PDF"
            let path = try await ed.getWord("Enter file name (Enter = choose)")
            host(ed, .export(format: f.lowercased(), path: path))
        },
        CommandDef("IMPORT", aliases: ["IMP"], category: "File", summary: "Imports a DXF, SVG or .archi file into the drawing.", modifies: false) { ed in
            let path = try await ed.getWord("Enter file name (Enter = choose)")
            host(ed, .importFile(path))
        },
        CommandDef("PLOT", aliases: ["PRINT"], category: "File", summary: "Plots the current sheet or view to PDF or a printer.", modifies: false) { ed in
            let path = try await ed.getWord("Enter PDF file name (Enter = print dialog)")
            host(ed, .plot(path: path))
        },
        CommandDef("CLOSE", category: "File", summary: "Closes the current drawing.", modifies: false) { ed in host(ed, .message("close")) },
        CommandDef("QUIT", aliases: ["EXIT"], category: "File", summary: "Quits the application.", modifies: false) { ed in host(ed, .message("quit")) },
        CommandDef("SCRIPT", aliases: ["SCR"], category: "File", summary: "Runs a script file of command lines.", modifies: false) { ed in
            guard let path = try await ed.getWord("Enter script file name") else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(url.path).") }
            ed.print("Running script \(url.lastPathComponent) (\(CommandHelpers.scriptLines(text).count) lines).")
            Task { @MainActor in await ed.runScript(text) }
        },
        CommandDef("SCRIPTTEXT", aliases: ["RUNSCRIPT"], category: "File", summary: "Runs command lines given as text (lines separated by newlines, \\n or |).", modifies: false) { ed in
            guard let t = try await ed.getString("Enter script text") else { return }
            let text = t.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "|", with: "\n")
            Task { @MainActor in await ed.runScript(text) }
        },
    ] }

    @MainActor static func save(_ ed: Editor, _ url: URL) throws {
        do { try ArchiFile.encode(ed.doc).write(to: url, options: .atomic); ed.fileURL = url; ed.isDirty = false; ed.print("Saved \(url.path).") }
        catch { throw CommandError.invalid("Cannot save \(url.path): \(error.localizedDescription)") }
    }

    static let viewNames: [(String, [String], String)] = [
        ("TOPVIEW", ["TOP", "PLANVIEW"], "top"), ("BOTTOMVIEW", ["BOTTOM"], "bottom"), ("FRONTVIEW", ["FRONT"], "front"), ("BACKVIEW", ["BACK"], "back"),
        ("LEFTVIEW", ["LEFT"], "left"), ("RIGHTVIEW", ["RIGHT", "SIDE"], "right"), ("ISOVIEW", ["ISO", "SWISO"], "swiso"),
        ("SEISO", [], "seiso"), ("NEISO", [], "neiso"), ("NWISO", [], "nwiso"),
    ]

    // MARK: - Views
    static var views: [CommandDef] {
        var out: [CommandDef] = [
            CommandDef("ZOOM", aliases: ["Z"], category: "View", summary: "Zooms: All/Extents, Window, Previous, Center, Object, or a scale (2, 0.5x).", modifies: false) { ed in
                let r = await ed.ask(InputRequest("Specify corner of window, enter a scale factor (nX), or", kinds: [.point, .keyword, .distance, .string],
                                                  keywords: ["All", "Center", "Extents", "Previous", "Scale", "Window", "Object"]))
                @MainActor func window(_ a: Vec2) async throws { let b = try await ed.requirePoint("Specify opposite corner", base: a); host(ed, .zoomWindow(BBox2(points: [a, b]))) }
                switch r {
                case .point(let p): try await window(p)
                case .number(let d): if d > 0 { host(ed, .zoomScale(d)) }
                case .text(let t):
                    let s = t.lowercased().replacingOccurrences(of: "xp", with: "").replacingOccurrences(of: "x", with: "")
                    if let d = InputParser.parseNumber(s), d > 0 { host(ed, .zoomScale(d)) } else { ed.print("Invalid zoom input.") }
                case .keyword("All"), .keyword("Extents"): host(ed, .zoomExtents)
                case .keyword("Previous"): host(ed, .setView("zoomPrevious"))
                case .keyword("Window"): try await window(try await ed.requirePoint("Specify first corner"))
                case .keyword("Scale"): if let d = try await ed.getReal("Enter a scale factor", defaultValue: 1).value, d > 0 { host(ed, .zoomScale(d)) }
                case .keyword("Center"):
                    let c = try await ed.requirePoint("Specify center point")
                    let h = try await ed.getPositive("Enter magnification or height", defaultValue: 10000)
                    host(ed, .zoomWindow(BBox2(min: c - Vec2(h * 0.8, h / 2), max: c + Vec2(h * 0.8, h / 2))))
                case .keyword("Object"):
                    let ids = try await ed.getSelection()
                    let b = ed.selectionBounds(ids)
                    if !ids.isEmpty { host(ed, .zoomWindow(b.expanded(by: max(b.width, b.height) * 0.05 + 1))) }
                case .cancel: throw CommandError.cancelled
                default: break
                }
            },
            CommandDef("PAN", aliases: ["P", "-PAN"], category: "View", summary: "Moves the view by a displacement.", modifies: false) { ed in
                guard let a = try await ed.getPoint("Specify base point or displacement").point else { return }
                let b = try await ed.getPoint("Specify second point", base: a).point
                host(ed, .pan(b.map { $0 - a } ?? a))
            },
            CommandDef("REGEN", aliases: ["RE", "REGENALL", "REA", "REDRAW", "R"], category: "View", summary: "Regenerates the display.", modifies: false) { ed in host(ed, .regen) },
            CommandDef("VIEW", aliases: ["V", "-VIEW"], category: "View", summary: "Saves, restores, lists and deletes named views.") { ed in
                let k = try await ed.getKeyword("Enter an option", ["?", "Save", "Restore", "Delete"], defaultValue: "?") ?? "?"
                switch k {
                case "Save":
                    guard let n = try await ed.getWord("Enter view name to save"), !n.isEmpty else { return }
                    var box = GeometryOps.bounds(of: ed.doc)
                    if let a = try await ed.getPoint("Specify first corner of view (Enter = drawing extents)").point {
                        box = BBox2(points: [a, try await ed.requirePoint("Specify opposite corner", base: a)])
                    }
                    if box.isEmpty { box = BBox2(min: .zero, max: Vec2(10000, 10000)) }
                    ed.doc.namedViews.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                    ed.doc.namedViews.append(NamedView(name: n, center: box.center, height: max(box.height, box.width / 1.6)))
                    ed.print("View \"\(n)\" saved.")
                case "Restore":
                    guard let n = try await ed.getWord("Enter view name to restore"), let v = ed.doc.namedViews.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("View not found.") }
                    host(ed, .zoomWindow(BBox2(min: v.center - Vec2(v.height * 0.8, v.height / 2), max: v.center + Vec2(v.height * 0.8, v.height / 2))))
                    if v.camera != nil { host(ed, .setView("named:" + v.name)) }
                case "Delete":
                    guard let n = try await ed.getWord("Enter view name to delete") else { return }
                    let c = ed.doc.namedViews.count
                    ed.doc.namedViews.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                    ed.print(c == ed.doc.namedViews.count ? "View not found." : "View \"\(n)\" deleted.")
                default:
                    if ed.doc.namedViews.isEmpty { ed.print("No named views.") }
                    for v in ed.doc.namedViews { ed.print("  \(v.name): center \(v.center), height \(fmt(v.height))\(v.camera != nil ? " (3D)" : "")") }
                }
            },
            CommandDef("SHOW3D", aliases: ["3D", "3DVIEW", "MODEL3D"], category: "View", summary: "Shows the 3D model view.", modifies: false) { ed in host(ed, .show3D) },
            CommandDef("SHOW2D", aliases: ["2D", "PLAN"], category: "View", summary: "Shows the 2D plan view.", modifies: false) { ed in host(ed, .show2D) },
            CommandDef("SPLIT", aliases: ["SPLITVIEW", "VPORTS"], category: "View", summary: "Shows the plan and 3D views side by side.", modifies: false) { ed in host(ed, .showSplit) },
            CommandDef("VSCURRENT", aliases: ["VS", "SHADEMODE"], category: "View", summary: "Sets the visual style of the 3D view.", modifies: false) { ed in
                let styles = ["2dwireframe", "Wireframe", "Hidden", "Realistic", "Conceptual", "Shaded", "shadedwithEdges", "Xray", "Sketchy"]
                guard let k = try await ed.getKeyword("Enter an option", styles, defaultValue: "Shaded") else { return }
                host(ed, .setViewStyle(k))
            },
            CommandDef("RENDER", aliases: ["RR"], category: "View", summary: "Renders the 3D model.", modifies: false) { ed in host(ed, .render) },
            CommandDef("WALK", aliases: ["3DWALK", "WALKTHROUGH", "3DFLY"], category: "View", summary: "Starts a first-person walkthrough of the 3D model.", modifies: false) { ed in host(ed, .walkthrough) },
            CommandDef("NAVVCUBE", aliases: ["VIEWCUBE"], category: "View", summary: "Shows or hides the view cube in 3D.", modifies: false) { ed in host(ed, .showPanel("ViewCube")) },
        ]
        for (n, a, v) in viewNames {
            out.append(CommandDef(n, aliases: a, category: "View", summary: "Sets the 3D view to \(v).", modifies: false) { ed in host(ed, .setView(v)) })
        }
        return out
    }

    // MARK: - Sheets
    @MainActor static func currentLayoutIndex(_ ed: Editor) -> Int? {
        if let n = ed.doc.variable("CTAB"), let i = ed.doc.layouts.firstIndex(where: { $0.name == n }) { return i }
        return ed.doc.layouts.isEmpty ? nil : 0
    }

    static func parseScale(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: " ", with: "")
        for sep in [":", "/"] where t.contains(sep) {
            let p = t.split(separator: Character(sep)).compactMap { Double($0) }
            if p.count == 2, p[0] > 0, p[1] > 0 { return p[1] / p[0] }
        }
        return Double(t).flatMap { $0 > 0 ? $0 : nil }
    }

    static var sheets: [CommandDef] { [
        CommandDef("LAYOUT", aliases: ["LO", "-LAYOUT", "SHEET"], category: "View", summary: "Creates, sets, renames and deletes sheets (layouts); sets paper size and title block.") { ed in
            let k = try await ed.getKeyword("Enter layout option", ["?", "New", "Set", "Delete", "Rename", "Paper", "Titleblock"], defaultValue: "Set") ?? "Set"
            switch k {
            case "New":
                let n = try await ed.getWord("Enter new layout name", defaultValue: "Sheet \(ed.doc.layouts.count + 1)") ?? "Sheet"
                guard !ed.doc.layouts.contains(where: { $0.name == n }) else { throw CommandError.invalid("Layout \(n) already exists.") }
                ed.doc.layouts.append(Layout(name: n))
                ed.doc.setVariable("CTAB", n); host(ed, .setView("layout:" + n))
            case "Set":
                guard let n = try await ed.getWord("Enter layout to make current (Model = model space)", defaultValue: ed.doc.variable("CTAB") ?? "Model") else { return }
                if n.lowercased() == "model" { ed.doc.setVariable("CTAB", "Model"); host(ed, .setView("model")); return }
                guard let l = ed.doc.layouts.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Layout \(n) not found.") }
                ed.doc.setVariable("CTAB", l.name); host(ed, .setView("layout:" + l.name))
            case "Delete":
                guard let n = try await ed.getWord("Enter layout to delete"), let i = ed.doc.layouts.firstIndex(where: { $0.name == n }) else { throw CommandError.invalid("Layout not found.") }
                ed.doc.layouts.remove(at: i)
                if ed.doc.variable("CTAB") == n { ed.doc.setVariable("CTAB", "Model") }
            case "Rename":
                guard let n = try await ed.getWord("Enter layout to rename"), let i = ed.doc.layouts.firstIndex(where: { $0.name == n }),
                      let nn = try await ed.getWord("Enter new layout name"), !nn.isEmpty else { throw CommandError.invalid("Layout not found.") }
                ed.doc.layouts[i].name = nn
                if ed.doc.variable("CTAB") == n { ed.doc.setVariable("CTAB", nn) }
            case "Paper":
                guard let i = currentLayoutIndex(ed) else { throw CommandError.invalid("No layout.") }
                let names = PaperSize.standard.map(\.name)
                guard let p = try await ed.getWord("Enter paper size [\(names.joined(separator: "/"))]", defaultValue: ed.doc.layouts[i].paper.name),
                      let ps = PaperSize.standard.first(where: { $0.name.caseInsensitiveCompare(p) == .orderedSame }) else { throw CommandError.invalid("Unknown paper size.") }
                ed.doc.layouts[i].paper = ps
                if try await ed.getKeyword("Orientation", ["Landscape", "Portrait"], defaultValue: "Landscape") == "Portrait" { ed.doc.layouts[i].paper = PaperSize(name: ps.name, width: ps.height, height: ps.width) }
            case "Titleblock":
                guard let i = currentLayoutIndex(ed) else { throw CommandError.invalid("No layout.") }
                while let key = try await ed.getWord("Enter title block field (e.g. Title, Drawn, Scale, Date, Number) or Enter to finish") {
                    let v = try await ed.getString("Enter value for \(key)", defaultValue: ed.doc.layouts[i].titleBlock[key] ?? "") ?? ""
                    ed.doc.layouts[i].titleBlock[key] = v
                }
            default:
                for l in ed.doc.layouts { ed.print("\(l.name == ed.doc.variable("CTAB") ? "*" : " ") \(l.name): \(l.paper.name) \(fmt(l.paper.width))×\(fmt(l.paper.height)) mm, \(l.viewports.count) viewport(s)") }
            }
        },
        CommandDef("MVIEW", aliases: ["MV", "VIEWPORT"], category: "View", summary: "Places a viewport on the current sheet (corners in paper mm, scale 1:n, view kind, level).") { ed in
            if currentLayoutIndex(ed) == nil { ed.doc.layouts.append(Layout(name: "Sheet 1")) }
            guard let li = currentLayoutIndex(ed) else { return }
            let paper = ed.doc.layouts[li].paper
            ed.print("Sheet \"\(ed.doc.layouts[li].name)\" (\(paper.name), \(fmt(paper.width))×\(fmt(paper.height)) mm)")
            let a = try await ed.getPoint("Specify first corner of viewport on paper (mm)", keywords: ["Fit"])
            var box: BBox2
            switch a {
            case .keyword: box = BBox2(min: Vec2(10, 10), max: Vec2(paper.width - 10, paper.height - 10))
            case .point(let p): box = BBox2(points: [p, try await ed.requirePoint("Specify opposite corner", base: p)])
            default: return
            }
            guard box.width > 1, box.height > 1 else { throw CommandError.invalid("Viewport is too small.") }
            let s = try await ed.getWord("Enter scale (1:100)", defaultValue: "1:100") ?? "1:100"
            guard var scale = parseScale(s) else { throw CommandError.invalid("Invalid scale.") }
            scale /= ed.doc.units.mm // model units per paper mm
            let kinds = ["Plan", "Ceiling", "North", "South", "East", "West", "SEction", "Axonometric", "PErspective"]
            let k = try await ed.getKeyword("View", kinds, defaultValue: "Plan") ?? "Plan"
            let view: ViewKind = ["Plan": .plan, "Ceiling": .ceiling, "North": .elevationNorth, "South": .elevationSouth, "East": .elevationEast, "West": .elevationWest,
                                  "SEction": .section, "Axonometric": .axonometric, "PErspective": .perspective][k] ?? .plan
            let ext = GeometryOps.bounds(of: ed.doc)
            let center = ext.isEmpty ? Vec2.zero : ext.center
            let title = try await ed.getString("Enter viewport title", defaultValue: ed.doc.level(ed.doc.currentLevel)?.name ?? "") ?? ""
            ed.doc.layouts[li].viewports.append(Viewport(origin: box.min, size: Vec2(box.width, box.height), viewCenter: center, scale: scale, view: view, level: ed.doc.currentLevel, title: title))
            ed.print("Viewport added at 1:\(fmt(scale * ed.doc.units.mm)).")
        },
    ] }

    // MARK: - Help
    static var help: [CommandDef] { [
        CommandDef("HELP", aliases: ["?", "F1"], category: "Help", summary: "Lists commands by category, or describes one command.", modifies: false) { ed in
            if let n = try await ed.getWord("Enter command name (Enter = list all)"), let c = ed.registry.lookup(n) {
                ed.print("\(c.name)\(c.aliases.isEmpty ? "" : " (" + c.aliases.joined(separator: ", ") + ")") [\(c.category)]: \(c.summary)")
                return
            }
            let groups = Dictionary(grouping: ed.registry.sorted.filter { $0.category != "Settings" || !$0.summary.hasPrefix("System variable") }, by: \.category)
            for cat in groups.keys.sorted() {
                ed.print("\(cat): " + groups[cat]!.map { c in c.aliases.first.map { "\(c.name) (\($0))" } ?? c.name }.joined(separator: ", "))
            }
            ed.print("Type HELP <command> for details. Coordinates: x,y  @dx,dy  @dist<angle; keywords by capital letters.")
        },
        CommandDef("COMMANDS", aliases: ["CMDLIST"], category: "Help", summary: "Lists every command with its aliases and summary.", modifies: false) { ed in
            for c in ed.registry.sorted { ed.print("\(c.name)\(c.aliases.isEmpty ? "" : " [" + c.aliases.joined(separator: ",") + "]") — \(c.summary)") }
        },
    ] }
}
