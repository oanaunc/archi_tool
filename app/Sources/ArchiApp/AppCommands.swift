// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// Commands implemented by the macOS app (windows, dialogs, 3D view, plotting). They are registered in the shared
/// registry, so they work from the command line, menus, ribbon, scripts and the agent server like core commands.
@MainActor
enum AppCommands {
    private static var registered = false

    static func model(_ ed: Editor) -> AppModel? { AppModel.all.first { $0.editor === ed } }

    static func registerAll(_ r: CommandRegistry = .shared) {
        guard !registered else { return }
        registered = true
        r.ensureBuiltins()
        r.register(all)
        r.register(AppCommandsExtra.all)
        r.register(AppCommandsReview.all)
        r.register(AppCommandsStudio.all)
        r.register(AppCommandsNav.all)
        r.register(AppCommandsRound9.all)
        r.register(AppCommandsRound10.all)
        r.register(AppCommandsRound11.all)
        r.register(AppCommandsRound12.all)
        r.register(TutorialCommands.all)
        r.register(BeautyCommands.all)
        AppCommandsRound10.startDevices()
        r.register(AppSelfTests.command)
        AppCommandsExtra.installSpellChecker()
    }

    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }

    static var all: [CommandDef] {
        [
            CommandDef("OPTIONS", aliases: ["OP", "PREFERENCES", "SETTINGS", "CONFIG"], category: "Settings", summary: "Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents.", modifies: false) { ed in
                let k = try await ed.getKeyword("Settings page [General/Drafting/Display/Shortcuts/Toolbar/Agents]", ["General", "Drafting", "Display", "Shortcuts", "Toolbar", "Agents"], defaultValue: "General")
                PreferencesWindow.show(PreferencesWindow.Tab(rawValue: k ?? "General") ?? .general)
            },
            CommandDef("CURSORSIZE", category: "Settings", summary: "Sets the crosshair size as a percentage of the view (1–100).", modifies: false) { ed in
                let cur = AppPreferences.shared.cursorSize
                guard let v = try await ed.getInteger("Enter new value for CURSORSIZE <\(cur)>", defaultValue: cur) else { return }
                guard (1...100).contains(v) else { throw CommandError.invalid("Requires an integer between 1 and 100.") }
                AppPreferences.shared.cursorSize = v
            },
            CommandDef("SAVETIME", aliases: ["AUTOSAVE"], category: "Settings", summary: "Sets the autosave interval in minutes (0 turns autosave off).", modifies: false) { ed in
                let cur = AppPreferences.shared.autosaveMinutes
                guard let v = try await ed.getInteger("Enter new value for SAVETIME (minutes) <\(cur)>", defaultValue: cur) else { return }
                guard (0...600).contains(v) else { throw CommandError.invalid("Requires 0–600 minutes.") }
                AppPreferences.shared.autosaveMinutes = v
                ed.print(v == 0 ? "Autosave is off." : "Autosave every \(v) minute(s).")
            },
            CommandDef("DRAWINGRECOVERY", aliases: ["DRM"], category: "File", summary: "Shows documents recovered from autosave after a crash.", modifies: false) { ed in
                let m = try ui(ed)
                let list = AutosaveManager.recoverable()
                if list.isEmpty { ed.print("No recovered documents."); return }
                for (i, r) in list.enumerated() { ed.print("  \(i + 1). \(r.name) — \(DateFormatter.localizedString(from: r.date, dateStyle: .short, timeStyle: .short))") }
                if m.isEmptyDocument && !m.isDirty, let n = try await ed.getInteger("Enter number to restore in this window or Enter to show the list", defaultValue: 0), n > 0, n <= list.count {
                    AutosaveManager.restore(list[n - 1], into: m)
                } else { m.showStart = true }
            },
            CommandDef("WSCURRENT", aliases: ["WS", "WORKSPACE"], category: "View", summary: "Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling.", modifies: false) { ed in
                let m = try ui(ed)
                ed.print("Workspaces: " + Workspaces.all.map(\.name).joined(separator: ", "))
                guard let n = try await ed.getString("Enter workspace name <\(Workspaces.currentName)>", defaultValue: Workspaces.currentName) else { return }
                guard let w = Workspaces.find(n) else { throw CommandError.invalid("Workspace \"\(n)\" not found.") }
                Workspaces.apply(w, to: m)
                ed.print("Workspace: \(w.name)")
            },
            CommandDef("WSSAVE", category: "View", summary: "Saves the current window arrangement as a named workspace.", modifies: false) { ed in
                let m = try ui(ed)
                guard let n = try await ed.getString("Save workspace as <\(Workspaces.currentName)>", defaultValue: Workspaces.currentName), !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                Workspaces.save(Workspaces.capture(m, name: n.trimmingCharacters(in: .whitespaces)))
                ed.print("Workspace \"\(n)\" saved.")
            },
            CommandDef("CLEANSCREENON", aliases: ["CLEANSCREEN"], category: "View", summary: "Clean screen: hides the ribbon and panels (Ctrl+0 toggles).", modifies: false) { ed in
                let m = try ui(ed); m.cleanScreen = true; ed.print("Clean screen on. CLEANSCREENOFF or ⌃0 restores the ribbon and panels.")
            },
            CommandDef("SCRIPTCONSOLE", aliases: ["JS", "JSCONSOLE", "CONSOLE"], category: "Scripting", summary: "Shows or hides the JavaScript console (⌥⌘J).", modifies: false) { ed in
                let m = try ui(ed); m.showScriptConsole.toggle()
            },
            CommandDef("CLEANSCREENOFF", category: "View", summary: "Restores the ribbon and panels after CLEANSCREENON.", modifies: false) { ed in
                let m = try ui(ed); m.cleanScreen = false
            },
            CommandDef("COMMANDSEARCH", aliases: ["CMDSEARCH", "SEARCHCOMMANDS"], category: "Help", summary: "Opens the command search palette (⌘K).", modifies: false) { ed in
                try ui(ed).showCommandSearch = true
            },
            CommandDef("HISTORYPANEL", aliases: ["UNDOHISTORY", "HISTORY"], category: "View", summary: "Shows the undo history and command history panel.", modifies: false) { ed in
                let m = try ui(ed); m.showPanels = true; m.panelTab = .history
            },
            CommandDef("TOOLPALETTES", aliases: ["TP", "TOOLPALETTE"], category: "View", summary: "Shows the tool palettes panel (grouped tools and My Tools).", modifies: false) { ed in
                let m = try ui(ed); m.showPanels = true; m.panelTab = .tools
            },
            CommandDef("TOOLPALETTESCLOSE", category: "View", summary: "Hides the tool palettes panel.", modifies: false) { ed in
                let m = try ui(ed); if m.panelTab == .tools { m.panelTab = .properties }
            },
            CommandDef("QSELECTDIALOG", aliases: ["QSD", "QUICKSELECT"], category: "Select", summary: "Quick Select dialog: type, property, operator and value with a live match count.", modifies: false) { ed in
                try ui(ed).sheet = .quickSelect
            },
            CommandDef("LAYERSTATE", aliases: ["LAS", "LMAN", "-LAYERSTATE"], category: "Layers", summary: "Layer states: Dialog, or ?/Save/Restore/Delete/Import/Export/Rename on the command line (saved in the drawing).") { ed in
                let k = try await ed.getKeyword("Enter an option", ["Dialog"] + LayerToolCommands.layerStateOptions, defaultValue: model(ed) == nil ? "?" : "Dialog") ?? "Dialog"
                if k == "Dialog" {
                    guard let m = model(ed) else { try await LayerToolCommands.runLayerState("?", ed); return }
                    m.sheet = .layerStates
                } else {
                    try await LayerToolCommands.runLayerState(k, ed)
                }
            },
            CommandDef("LAYERFILTER", aliases: ["LFILTER"], category: "Layers", summary: "Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing.") { ed in
                let k = try await ed.getKeyword("Enter an option [Apply/Save/Delete/List/Clear]", ["Apply", "Save", "Delete", "List", "Clear"], defaultValue: "Apply") ?? "Apply"
                let m = model(ed)
                switch k {
                case "List":
                    let names = LayerFilter.names(ed.doc)
                    if names.isEmpty { ed.print("No saved layer filters.") }
                    for n in names { ed.print("  \(n): \(ed.doc.variables[LayerFilter.prefix + n] ?? "")") }
                case "Clear":
                    m?.layerFilterRequest = LayerFilter(); m?.showPanels = true; m?.panelTab = .layers
                case "Delete":
                    guard let n = try await ed.getString("Enter filter name") else { return }
                    var d = ed.doc; d.variables[LayerFilter.prefix + n.uppercased()] = nil; ed.doc = d
                case "Save":
                    guard let n = try await ed.getString("Enter filter name"), !n.isEmpty else { return }
                    guard let p = try await ed.getString("Enter filter (name wildcards, #on #used #unlocked)"), !p.isEmpty else { return }
                    var d = ed.doc; d.variables[LayerFilter.prefix + n.trimmingCharacters(in: .whitespaces).uppercased()] = LayerFilter(stored: p).stored; ed.doc = d
                    ed.print("Layer filter \(n.uppercased()) saved.")
                default:
                    guard let p = try await ed.getString("Enter filter name or pattern") else { return }
                    let f = LayerFilter.saved(p, in: ed.doc) ?? LayerFilter(stored: p)
                    let usedNames = Set(ed.doc.entities.map { $0.layer.uppercased() } + ed.doc.elements.map { $0.layer.uppercased() })
                    let hits = ed.doc.layers.filter { f.matches($0, used: usedNames.contains($0.name.uppercased())) }
                    ed.print("\(hits.count) layer(s) match: " + hits.prefix(30).map(\.name).joined(separator: ", "))
                    if let m { m.layerFilterRequest = f; m.showPanels = true; m.panelTab = .layers }
                }
            },
            CommandDef("MATERIALS", aliases: ["MAT", "RMAT", "MATEDITOR", "MATBROWSEROPEN"], category: "View", summary: "Opens the material editor panel (color, roughness, metalness, transparency, texture).", modifies: false) { ed in
                let m = try ui(ed); m.showPanels = true; m.panelTab = .materials
            },
            CommandDef("SECTIONBOX", aliases: ["SBOX", "3DSECTIONBOX"], category: "View", summary: "Section box in 3D: On/Off/Selection/Level/Reset; the box is saved with the drawing.") { ed in
                let k = try await ed.getKeyword("Section box [On/Off/Selection/Level/Reset/Panel]", ["On", "Off", "Selection", "Level", "Reset", "Panel"], defaultValue: "Panel") ?? "Panel"
                let m = model(ed)
                if m?.mode == .plan || m?.mode == .sheet { m?.mode = .model }
                var extents = BBox3.empty
                for g in MeshBuilder.build(doc: ed.doc) { for p in g.mesh.positions { extents.add(p) } }
                guard !extents.isEmpty else { throw CommandError.invalid("The model has no 3D content.") }
                var box = SectionBox.load(ed.doc) ?? SectionBox.around(extents)
                switch k {
                case "On": box.on = true
                case "Off": box.on = false
                case "Reset": box = SectionBox.around(extents)
                case "Level":
                    guard let l = ed.doc.level(ed.doc.currentLevel) else { return }
                    box.on = true; box.min.z = max(extents.min.z - 100, l.elevation - 50); box.max.z = l.elevation + l.height * 0.9
                case "Selection":
                    var b = BBox3.empty
                    for g in MeshBuilder.build(doc: ed.doc) where g.id.map({ ed.selection.contains($0) }) ?? false { for p in g.mesh.positions { b.add(p) } }
                    guard !b.isEmpty else { throw CommandError.invalid("Select building elements first.") }
                    box = SectionBox.around(b)
                default:
                    m?.showSectionBoxPanel = true
                    return
                }
                var d = ed.doc; box.store(in: &d); ed.doc = d
                ed.print(box.on ? "Section box on." : "Section box off.")
            },
            CommandDef("SUNSTUDY", aliases: ["SUN", "SUNPROPERTIES"], category: "View", summary: "Sun study panel in the 3D view: date and time sliders with a day animation.", modifies: false) { ed in
                let m = try ui(ed)
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                m.showSunStudy = true
            },
            CommandDef("ORBITSELECTION", aliases: ["ORBITSEL", "3DORBITSEL", "ZOOMSELECTED3D"], category: "View", summary: "Orbits around (and zooms to) the selected elements in 3D.", modifies: false) { ed in
                let m = try ui(ed)
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                guard !ed.selection.isEmpty else { throw CommandError.invalid("Select objects first.") }
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let c = m.viewport3D, c.orbitSelection(ed.selection, frame: true) else { throw CommandError.invalid("The selection has no 3D geometry.") }
            },
            CommandDef("SAVECAMERA", aliases: ["CAMSAVE", "NEWCAMERA"], category: "View", summary: "Saves the current 3D camera by name (restored with CAMERA).") { ed in
                let m = try ui(ed)
                guard let c = m.viewport3D?.currentCamera else { throw CommandError.invalid("Open the 3D view first.") }
                let def = "Camera \(ed.doc.namedViews.filter { $0.camera != nil }.count + 1)"
                guard let n = try await ed.getString("Enter camera name <\(def)>", defaultValue: def), !n.isEmpty else { return }
                CameraStore.save(n.trimmingCharacters(in: .whitespaces), camera: c, model: m)
            },
            CommandDef("CAMERA", aliases: ["CAM", "RESTORECAMERA"], category: "View", summary: "Restores a saved 3D camera (or lists them).", modifies: false) { ed in
                let m = try ui(ed)
                let cams = ed.doc.namedViews.filter { $0.camera != nil }
                guard !cams.isEmpty else { throw CommandError.invalid("No saved cameras. Use SAVECAMERA.") }
                guard let n = try await ed.getString("Enter camera name [\(cams.map(\.name).joined(separator: "/"))]") else { return }
                guard let v = CameraStore.find(n.trimmingCharacters(in: .whitespaces), in: ed.doc), let cam = v.camera else { throw CommandError.invalid("Camera \"\(n)\" not found.") }
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                try? await Task.sleep(nanoseconds: 150_000_000)
                m.viewport3D?.apply(camera: cam)
            },
            CommandDef("PAGESETUP", aliases: ["PSETUP", "PAGESETUPMANAGER"], category: "Output", summary: "Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale.", modifies: false) { ed in
                let m = try ui(ed)
                m.sheet = .pageSetup(m.mode == .sheet ? m.activeLayout : -1)
            },
            CommandDef("PREVIEW", aliases: ["PRE", "PRINTPREVIEW", "PLOTPREVIEW", "PLOTDIALOG"], category: "Output", summary: "Plot dialog with a live preview: prints or saves exactly what is shown.", modifies: false) { ed in
                PlotPreviewWindow.show(model: try ui(ed))
            },
            CommandDef("PUBLISH", aliases: ["BATCHPLOT", "EXPORTSHEETS", "PUBLISHPDF"], category: "Output", summary: "Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog).", modifies: false) { ed in
                let m = try ui(ed)
                if LayerNotify.isOn(ed.doc), !LayerNotify.unreconciled(ed.doc).isEmpty { ed.print("⚠ Plotting with unreconciled layers: \(LayerNotify.unreconciled(ed.doc).joined(separator: ", ")).") }
                let p = try await ed.getString("Enter PDF file path or Enter to choose", defaultValue: "")
                Plotter.publish(model: m, path: p?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
            },
            CommandDef("TITLEBLOCK", aliases: ["TBEDIT", "TITLEBLOCKEDIT"], category: "Output", summary: "Edits the active sheet's title block and the project information shown on all sheets.", modifies: false) { ed in
                let m = try ui(ed)
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
                m.mode = .sheet
                m.sheet = .titleBlock(min(max(m.activeLayout, 0), ed.doc.layouts.count - 1))
            },
            CommandDef("VPLOCK", aliases: ["VPORTLOCK", "LOCKVIEWPORT"], category: "Output", summary: "Locks or unlocks sheet viewports so their scale and position cannot change.") { ed in
                let m = model(ed)
                let li = m.map { min(max($0.activeLayout, 0), max(ed.doc.layouts.count - 1, 0)) } ?? 0
                guard ed.doc.layouts.indices.contains(li), !ed.doc.layouts[li].viewports.isEmpty else { throw CommandError.invalid("The active sheet has no viewports.") }
                let n = ed.doc.layouts[li].viewports.count
                let k = try await ed.getKeyword("Viewport display locking [On/Off]", ["On", "Off"], defaultValue: "On") ?? "On"
                let which = try await ed.getString("Enter viewport number (1–\(n)) or All <All>", defaultValue: "All") ?? "All"
                let targets: [Int] = which.lowercased().hasPrefix("a") ? Array(0..<n) : which.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)).map { $0 - 1 } }.filter { (0..<n).contains($0) }
                guard !targets.isEmpty else { throw CommandError.invalid("No such viewport.") }
                var d = ed.doc
                for t in targets { ViewportLock.set(&d, layoutIndex: li, viewport: t, locked: k == "On") }
                ed.doc = d
                ed.print("\(targets.count) viewport(s) \(k == "On" ? "locked" : "unlocked") on \(d.layouts[li].name).")
            },
            CommandDef("AGENTSETTINGS", aliases: ["AGENTS", "AGENTSERVER"], category: "Scripting", summary: "Agent server settings: port, start/stop, token, auto-start.", modifies: false) { _ in
                PreferencesWindow.show(.agents)
            },
            CommandDef("CONNECTCLAUDE", aliases: ["MCPHELP", "CLAUDE"], category: "Scripting", summary: "Explains how to connect Claude (archi-cli --mcp or the local agent server).", modifies: false) { ed in
                try ui(ed).sheet = .connectClaude
            },
            CommandDef("SCRIPTLIBRARY", aliases: ["SCRIPTS"], category: "Scripting", summary: "Opens the script library folder (startup.js runs in every new window).", modifies: false) { _ in
                ScriptLibrary.revealFolder()
            },
            CommandDef("SHEETSET", aliases: ["SSM", "SHEETSETMANAGER", "SHEETS"], category: "Output", summary: "Sheet set manager: numbering, order, duplicate, revisions, sheet index.", modifies: false) { ed in
                let m = try ui(ed); m.showPanels = true; m.panelTab = .sheets
            },
            CommandDef("SHEETINDEX", aliases: ["SHEETLIST", "DRAWINGLIST"], category: "Output", summary: "Places or refreshes the sheet list table (number, title, paper, revision) on the active sheet.") { ed in
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
                let i = model(ed).map { min(max($0.activeLayout, 0), ed.doc.layouts.count - 1) } ?? 0
                SheetSet.placeIndex(&ed.doc, on: i)
                ed.print("Sheet index with \(ed.doc.layouts.count) sheet(s) on \(ed.doc.layouts[i].name).")
            },
            CommandDef("SHEETREVISION", aliases: ["REVISION", "REVTABLE", "ADDREVISION"], category: "Output", summary: "Adds a revision (next code, date, description, by) to the active sheet's revision table.") { ed in
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
                let i = model(ed).map { min(max($0.activeLayout, 0), ed.doc.layouts.count - 1) } ?? 0
                let next = SheetSet.nextCode(after: SheetSet.revisions(ed.doc.layouts[i]).last?.code)
                guard let d = try await ed.getString("Revision \(next) description"), !d.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let by = try await ed.getString("Revised by <\(ed.doc.info.author)>", defaultValue: ed.doc.info.author) ?? ed.doc.info.author
                SheetSet.addRevision(&ed.doc, i, description: d.trimmingCharacters(in: .whitespaces), by: by)
                SheetSet.refreshIndexes(&ed.doc)
                ed.print("Revision \(next) added to \(ed.doc.layouts[i].name).")
            },
            CommandDef("SHEETRENUMBER", aliases: ["RENUMBERSHEETS"], category: "Output", summary: "Numbers all sheets in order with a prefix and start number (e.g. A- 101).") { ed in
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
                let prefix = try await ed.getString("Enter number prefix <A->", defaultValue: "A-") ?? "A-"
                guard let start = try await ed.getInteger("Enter first number <101>", defaultValue: 101) else { return }
                SheetSet.renumber(&ed.doc, prefix: prefix, start: start)
                SheetSet.refreshIndexes(&ed.doc)
                ed.print("\(ed.doc.layouts.count) sheet(s) numbered \(SheetSet.number(ed.doc, 0))…")
            },
            CommandDef("SHEETVIEWTITLES", aliases: ["VPTITLES", "EDITABLEVIEWTITLES"], category: "Output", summary: "Editable view titles (number bubble, title, scale) under every viewport of the active sheet; keeps edited titles.") { ed in
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
                let i = model(ed).map { min(max($0.activeLayout, 0), ed.doc.layouts.count - 1) } ?? 0
                SheetSet.refreshViewTitles(&ed.doc, i)
                ed.print("\(ed.doc.layouts[i].viewports.count) view title(s) on \(ed.doc.layouts[i].name).")
            },
            CommandDef("MATBROWSER", aliases: ["MATLIB", "MATERIALLIBRARY"], category: "View", summary: "Material library browser with rendered thumbnails: add to the drawing or assign to the selection.", modifies: false) { ed in
                MaterialLibraryWindow.show(model: try ui(ed))
            },
            CommandDef("NODEEDITOR", aliases: ["NODES", "VISUALSCRIPT", "GRAPH"], category: "Scripting", summary: "Visual node editor (number, point, line, circle, extrude, array…) with live preview; bakes geometry into the drawing.", modifies: false) { ed in
                NodeEditorWindow.show(model: try ui(ed))
            },
            CommandDef("FLOATPANEL", aliases: ["UNDOCKPANEL", "PANELFLOAT"], category: "View", summary: "Floats a panel (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History) in its own window.", modifies: false) { ed in
                let m = try ui(ed)
                let names = PanelTab.allCases.map(\.rawValue)
                guard let k = try await ed.getKeyword("Panel [\(names.joined(separator: "/"))]", names, defaultValue: m.panelTab.rawValue), let t = PanelTab(rawValue: k) else { return }
                FloatingPanels.float(t, model: m)
            },
            CommandDef("ABOUT", category: "Help", summary: "About Oanarina Archi Tool: version, license and credits.", modifies: false) { _ in
                AboutWindow.show()
            },
        ]
    }
}
