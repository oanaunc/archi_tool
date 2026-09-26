// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// Commands of the navigation, selection and sheet additions (tabs, quick properties, inspector, design center, help,
/// view twist, projection, viewports). App-level: they need windows, panels or the sheet view.
@MainActor
enum AppCommandsNav {
    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    private static func onOff(_ ed: Editor, _ msg: String, current: Bool) async throws -> Bool? {
        guard let k = try await ed.getKeyword("\(msg) [ON/OFF/Toggle]", ["ON", "OFF", "Toggle"], defaultValue: "Toggle") else { return nil }
        return k == "ON" ? true : (k == "OFF" ? false : !current)
    }
    /// Sheet (layout) index a sheet command works on: the shown sheet, else the first.
    static func sheetIndex(_ ed: Editor) -> Int? {
        let d = ed.doc
        guard !d.layouts.isEmpty else { return nil }
        if let t = d.variable("CTAB"), let i = d.layouts.firstIndex(where: { $0.name == t }) { return i }
        if let m = AppCommands.model(ed), d.layouts.indices.contains(m.activeLayout) { return m.activeLayout }
        return 0
    }
    private static func viewportNumber(_ ed: Editor, _ li: Int) async throws -> Int? {
        let n = ed.doc.layouts[li].viewports.count
        guard n > 0 else { throw CommandError.invalid("The sheet has no viewports.") }
        let def = (AppCommands.model(ed)?.selectedSheetViewport).map { $0 + 1 } ?? 1
        guard let v = try await ed.getInteger("Viewport number (1–\(n))", defaultValue: min(def, n)) else { return nil }
        guard (1...n).contains(v) else { throw CommandError.invalid("No viewport \(v).") }
        return v - 1
    }

    /// One space-delimited word (keywords and plain text alike); nil on Enter.
    static func word(_ ed: Editor, _ msg: String) async throws -> String? {
        switch await ed.ask(InputRequest(msg, kinds: [.keyword, .string], keywords: [])) {
        case .keyword(let k): return k
        case .text(let t): let s = t.trimmingCharacters(in: .whitespaces); return s.isEmpty ? nil : s
        case .number(let d): return fmt(d)
        case .cancel: throw CommandError.cancelled
        default: return nil
        }
    }

    static var all: [CommandDef] {
        [
            CommandDef("FILETAB", category: "View", summary: "Shows the file tab bar with one tab per open drawing.", modifies: false) { ed in
                FileTabs.visible = true; ed.print("File tabs on.")
            },
            CommandDef("FILETABCLOSE", category: "View", summary: "Hides the file tab bar.", modifies: false) { ed in
                FileTabs.visible = false; ed.print("File tabs off.")
            },
            CommandDef("LAYOUTTABS", aliases: ["LAYOUTTAB", "MODELTAB"], category: "View", summary: "Shows or hides the Model / layout tabs under the drawing area.", modifies: false) { ed in
                let m = try ui(ed)
                guard let on = try await onOff(ed, "Model/layout tabs", current: m.showLayoutTabs) else { return }
                m.showLayoutTabs = on
            },
            CommandDef("QUICKPROPS", aliases: ["QP", "QUICKPROPERTIES"], category: "View", summary: "Quick Properties: a compact editor of the selection's key properties over the drawing.", modifies: false) { ed in
                let m = try ui(ed)
                guard let on = try await onOff(ed, "Quick Properties", current: m.showQuickProperties) else { return }
                m.showQuickProperties = on
            },
            CommandDef("INSPECT", aliases: ["OBJECTINFO", "LISTPANEL"], category: "Inquiry", summary: "Opens the Inspector panel: every stored value of the selected objects, with ID and GUID.", modifies: false) { ed in
                let m = try ui(ed)
                if ed.selection.isEmpty { ed.selection = Set(try await ed.getSelection("Select objects to inspect")) }
                m.showPanels = true; m.panelTab = .inspector
                for id in ed.selection.sorted().prefix(3) { ed.print(ObjectInspector.text(id, doc: ed.doc).split(separator: "\n").prefix(8).joined(separator: " · ")) }
            },
            CommandDef("ADCENTER", aliases: ["DC", "DESIGNCENTER"], category: "Insert", summary: "Design Center: browses another drawing's blocks, layers, linetypes, styles and materials and adds them here.", modifies: false) { ed in
                let m = try ui(ed); m.showPanels = true; m.panelTab = .content
            },
            CommandDef("HELPWINDOW", aliases: ["DOCS", "HELPBROWSER", "MANUAL"], category: "Help", summary: "Opens the offline help browser (command pages, tutorials, shortcuts); F1 opens the running command's page.", modifies: false) { ed in
                let t = try await ed.getString("Command or topic [Tutorials/Shortcuts/Scripting] (Enter = index)", defaultValue: "")
                let s = (t ?? "").trimmingCharacters(in: .whitespaces)
                if s.isEmpty { HelpBrowser.show("index") }
                else if ["tutorials", "shortcuts", "scripting"].contains(s.lowercased()) { HelpBrowser.show(s.lowercased()) }
                else if let d = ed.registry.lookup(s) { HelpBrowser.show("cmd/" + d.name) }
                else { throw CommandError.invalid("Unknown command \"\(s)\".") }
            },
            CommandDef("TUTORIALS", aliases: ["TUTORIAL", "LEARN"], category: "Help", summary: "Opens the step-by-step tutorials and the sample project in the help browser.", modifies: false) { _ in
                HelpBrowser.show("tutorials")
            },
            CommandDef("SAMPLEHOUSE", aliases: ["SAMPLE", "OPENSAMPLE"], category: "Help", summary: "Opens the bundled sample house project in a new window.", modifies: false) { ed in
                WindowRouter.open(DocumentRequest(kind: .sample)); ed.print("Opening the sample house…")
            },
            CommandDef("SELECTWALLCHAIN", aliases: ["WALLCHAIN"], category: "Select", summary: "Selects the chain of walls joined to a picked wall (Tab over a wall does the same).", modifies: false) { ed in
                guard let id = try await ed.getEntity("Select a wall") else { return }
                let chain = WallChain.ids(from: id, doc: ed.doc).filter { ed.isSelectable($0) }
                guard !chain.isEmpty else { throw CommandError.invalid("That is not a wall.") }
                ed.selection.formUnion(chain)
                ed.print("\(chain.count) joined wall(s) selected.")
            },
            CommandDef("DVIEW", aliases: ["DV", "PLANTWIST"], category: "View", summary: "Rotates (twists) the 2D plan display; model coordinates are unchanged. DVIEW TWist 30, DVIEW Off.", modifies: true) { ed in
                let cur = ViewTwist.degrees(ed.doc)
                guard let k = try await ed.getKeyword("Enter option [TWist/Off]", ["TWist", "Off"], defaultValue: "TWist") else { return }
                if k == "Off" { ed.doc.variables[ViewTwist.variable] = nil; ed.print("View twist off."); return }
                guard let a = try await ed.getAngle("Specify view twist angle", defaultValue: rad(cur)).value else { return }
                let d = ViewTwist.normalized(deg(a))
                if d == 0 { ed.doc.variables[ViewTwist.variable] = nil } else { ed.doc.setVariable(ViewTwist.variable, fmt(d, 6)) }
                ed.print("View twist \(fmt(d, 2))°.")
            },
            CommandDef("PERSPECTIVE", aliases: ["PROJECTION"], category: "View", summary: "3D projection: 1 = perspective, 0 = parallel (orthographic).", modifies: false) { ed in
                let m = try ui(ed)
                let cur = ed.doc.variable("PERSPECTIVE") ?? "1"
                guard let v = try await ed.getInteger("Enter new value for PERSPECTIVE <\(cur)>", defaultValue: Int(cur) ?? 1) else { return }
                guard v == 0 || v == 1 else { throw CommandError.invalid("Requires 0 or 1.") }
                ed.doc.setVariable("PERSPECTIVE", "\(v)")
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                m.pendingHostAction = .setView(v == 1 ? "perspective" : "ortho")
                m.revision &+= 1
            },
            CommandDef("VPMAX", aliases: ["VPMAXIMIZE"], category: "View", summary: "Maximises a sheet viewport: edits the model through it at full window size (VPMIN returns).", modifies: false) { ed in
                let m = try ui(ed)
                guard let li = sheetIndex(ed), let vi = try await viewportNumber(ed, li) else { throw CommandError.invalid("No sheet to maximise a viewport of.") }
                let vp = ed.doc.layouts[li].viewports[vi]
                guard vp.view == .plan || vp.view == .ceiling else { throw CommandError.invalid("Only plan viewports can be maximised.") }
                m.maximizedViewport = (li, vi)
                if let lv = vp.level, ed.doc.level(lv) != nil, ed.doc.currentLevel != lv { ed.doc.currentLevel = lv }
                m.mode = .plan
                let box = SheetTools.modelWindow(vp)
                DispatchQueue.main.async { m.canvas?.zoom(to: box) }
                ed.print("Viewport \(vi + 1) maximised. VPMIN returns to the sheet.")
                m.revision &+= 1
            },
            CommandDef("VPMIN", aliases: ["VPMINIMIZE"], category: "View", summary: "Returns from a maximised viewport to its sheet, keeping the new view centre (unless the viewport is locked).", modifies: true) { ed in
                let m = try ui(ed)
                guard let (li, vi) = m.maximizedViewport, ed.doc.layouts.indices.contains(li), ed.doc.layouts[li].viewports.indices.contains(vi) else {
                    throw CommandError.invalid("No viewport is maximised.")
                }
                if !ViewportLock.isLocked(ed.doc, layoutIndex: li, viewport: vi), let c = m.canvas?.viewCenterWorld {
                    SheetTools.restoreCenter(&ed.doc.layouts[li].viewports[vi], planCenter: c)
                }
                m.maximizedViewport = nil
                m.activeLayout = li; m.mode = .sheet
                m.revision &+= 1
            },
            CommandDef("VPCLIP", category: "View", summary: "Clips a sheet viewport to a polygon of paper points (x,y in mm), or Deletes the clip.", modifies: true) { ed in
                guard let li = sheetIndex(ed), let vi = try await viewportNumber(ed, li) else { throw CommandError.invalid("No sheet.") }
                var pts: [Vec2] = []
                while true {
                    let a = try await ed.getPoint(pts.isEmpty ? "Specify first paper point or [Delete]" : "Specify next paper point (Enter to close)", keywords: pts.isEmpty ? ["Delete"] : [])
                    if case .keyword("Delete") = a { SheetTools.setClip(&ed.doc, layoutIndex: li, viewport: vi, nil); ed.print("Clip removed."); return }
                    guard let p = a.point else { break }
                    pts.append(p)
                }
                guard pts.count >= 3 else { throw CommandError.invalid("A clip boundary needs at least 3 points.") }
                SheetTools.setClip(&ed.doc, layoutIndex: li, viewport: vi, pts)
                ed.print("Viewport \(vi + 1) clipped to \(pts.count) points.")
            },
            CommandDef("MVIEWPOLY", aliases: ["MVPOLY", "POLYVIEWPORT"], category: "View", summary: "Creates a polygonal sheet viewport from paper points (x,y in mm) showing the current level.", modifies: true) { ed in
                guard let li = sheetIndex(ed) else { throw CommandError.invalid("Create a sheet first (LAYOUT).") }
                var pts: [Vec2] = []
                while let p = try await ed.getPoint(pts.isEmpty ? "Specify first paper point" : "Specify next paper point (Enter to close)").point { pts.append(p) }
                guard pts.count >= 3 else { throw CommandError.invalid("A polygonal viewport needs at least 3 points.") }
                let ratio = try await ed.getInteger("Scale 1:n <100>", defaultValue: 100) ?? 100
                let center = GeometryOps.bounds(of: ed.doc).isEmpty ? .zero : GeometryOps.bounds(of: ed.doc).center
                let i = SheetTools.addPolygonal(&ed.doc, layoutIndex: li, pts, center: center, scale: SheetTools.scale(ratio: Double(max(ratio, 1)), units: ed.doc.units), level: ed.doc.currentLevel)
                ed.print("Polygonal viewport \((i ?? 0) + 1) at 1:\(ratio).")
            },
            CommandDef("MVSETUP", category: "View", summary: "Aligns sheet viewports: pans one viewport so a model point lines up horizontally or vertically with a point in another.", modifies: true) { ed in
                guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
                guard ed.doc.layouts[li].viewports.count >= 2 else { throw CommandError.invalid("Alignment needs two viewports.") }
                guard let k = try await ed.getKeyword("Align [Horizontal/Vertical]", ["Horizontal", "Vertical"], defaultValue: "Horizontal") else { return }
                ed.print("Base viewport:")
                guard let a = try await viewportNumber(ed, li) else { return }
                let pa = try await ed.requirePoint("Specify base point in model coordinates")
                ed.print("Viewport to pan:")
                guard let b = try await viewportNumber(ed, li) else { return }
                let pb = try await ed.requirePoint("Specify point to align in model coordinates")
                guard !ViewportLock.isLocked(ed.doc, layoutIndex: li, viewport: b) else { throw CommandError.invalid("Viewport \(b + 1) is locked.") }
                guard SheetTools.align(&ed.doc.layouts[li], base: a, basePoint: pa, other: b, otherPoint: pb, k == "Horizontal" ? .horizontal : .vertical) else { throw CommandError.invalid("Choose two different viewports.") }
                ed.print("Viewport \(b + 1) aligned \(k.lowercased())ly with viewport \(a + 1).")
            },
            CommandDef("SHEETGRID", aliases: ["LAYOUTGRID", "GUIDEGRID"], category: "Output", summary: "Guide grid on the current sheet (spacing in paper mm, 0 = off); viewports snap to it when moved.", modifies: true) { ed in
                guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
                let name = ed.doc.layouts[li].name
                let cur = SheetTools.gridSpacing(ed.doc, layout: name)
                guard let v = try await ed.getDistance("Guide grid spacing in paper mm (0 = off)", defaultValue: cur > 0 ? cur : 10).value else { return }
                ed.doc.variables[SheetTools.gridKey(name)] = v > 0 ? fmt(v, 4) : nil
                ed.print(v > 0 ? "Guide grid \(fmt(v, 2)) mm on \(name)." : "Guide grid off.")
            },
            CommandDef("SHEETPLACEHOLDER", aliases: ["PLACEHOLDERSHEET"], category: "Output", summary: "Adds a placeholder sheet (listed in the sheet set and index, never plotted) or toggles the current one.", modifies: true) { ed in
                guard let k = try await ed.getKeyword("Enter option [New/Toggle]", ["New", "Toggle"], defaultValue: "New") else { return }
                if k == "Toggle" {
                    guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
                    let on = !SheetTools.isPlaceholder(ed.doc.layouts[li])
                    SheetTools.setPlaceholder(&ed.doc, li, on)
                    ed.print("\(ed.doc.layouts[li].name) is \(on ? "a placeholder" : "a real sheet").")
                    return
                }
                guard let n = try await ed.getString("Sheet name", defaultValue: "Sheet \(ed.doc.layouts.count + 1)"), !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                ed.doc.layouts.append(ArchiCore.Layout(name: n.trimmingCharacters(in: .whitespaces)))
                SheetTools.setPlaceholder(&ed.doc, ed.doc.layouts.count - 1, true)
                ed.print("Placeholder sheet \(n) added.")
            },
            CommandDef("SHEETFIELD", aliases: ["PROJECTFIELD", "CUSTOMFIELD"], category: "Output", summary: "Custom title block fields: Project fields appear on every sheet, Sheet fields override them on one sheet.", modifies: true) { ed in
                guard let k = try await ed.getKeyword("Field scope [Project/Sheet/List]", ["Project", "Sheet", "List"], defaultValue: "Project") else { return }
                if k == "List" {
                    for (l, v) in SheetTools.projectFields(ed.doc) { ed.print("  Project \(l) = \(v)") }
                    if let li = sheetIndex(ed) { for (l, v) in SheetTools.fields(ed.doc, layout: ed.doc.layouts[li]) { ed.print("  \(ed.doc.layouts[li].name): \(l) = \(v)") } }
                    return
                }
                guard let label = try await word(ed, "Field label (one word, e.g. CLIENTREF)"), !label.isEmpty else { return }
                let value = try await ed.getString("Value for \(label) (empty removes it)", defaultValue: "") ?? ""
                if k == "Project" { SheetTools.setProjectField(&ed.doc, label, value) }
                else { guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }; SheetTools.setSheetField(&ed.doc, li, label, value) }
                ed.print(value.isEmpty ? "Field \(label.uppercased()) removed." : "\(label.uppercased()) = \(value)")
            },
            CommandDef("VISUALSTYLES", aliases: ["VSM", "VISUALSTYLEMANAGER"], category: "View", summary: "Visual styles manager: New/Edit a custom style from a base (edges, edge colour, face opacity, shadows, background), Delete, List, Current.", modifies: true) { ed in
                guard let k = try await ed.getKeyword("Enter option [New/Edit/Delete/List/Current]", ["New", "Edit", "Delete", "List", "Current"], defaultValue: "List") else { return }
                switch k {
                case "List":
                    ed.print("Built-in: " + Scene3DBuilder.visualStyles.joined(separator: ", "))
                    for v in VisualStyleDef.all(ed.doc) {
                        ed.print("  \(v.name) — base \(v.base)\(v.edges.map { $0 ? ", edges" : ", no edges" } ?? "")\(v.faceOpacity.map { ", faces \(Int($0 * 100))%" } ?? "")\(v.shadows.map { $0 ? ", shadows" : ", no shadows" } ?? "")")
                    }
                case "Delete":
                    guard let n = try await word(ed, "Style to delete") else { return }
                    guard VisualStyleDef.delete(n, in: &ed.doc) else { throw CommandError.invalid("No custom style \(n).") }
                    ed.print("Deleted \(n).")
                case "Current":
                    guard let n = try await word(ed, "Style name") else { return }
                    let m = try ui(ed)
                    guard VisualStyleDef.named(n, in: ed.doc) != nil || VisualStyleNames.resolve(n) != nil else { throw CommandError.invalid("Unknown style \(n).") }
                    m.files.handle(.setViewStyle(n))
                    if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                default:
                    guard let n = try await word(ed, "Style name") else { return }
                    var v = VisualStyleDef.named(n, in: ed.doc) ?? VisualStyleDef(name: n, base: "Shaded")
                    if k == "Edit" && VisualStyleDef.named(n, in: ed.doc) == nil { throw CommandError.invalid("No custom style \(n).") }
                    if let b = try await ed.getKeyword("Base [Wireframe/Hidden/Shaded/shadedwithEdges/Conceptual/Realistic/Xray]", ["Wireframe", "Hidden", "Shaded", "shadedwithEdges", "Conceptual", "Realistic", "Xray"], defaultValue: v.base.replacingOccurrences(of: " ", with: "")) { v.base = b }
                    if let e = try await ed.getKeyword("Edges [Yes/No/Base]", ["Yes", "No", "Base"], defaultValue: v.edges.map { $0 ? "Yes" : "No" } ?? "Base") { v.edges = e == "Base" ? nil : e == "Yes" }
                    if let o = try await ed.getInteger("Face opacity % (1–100)", defaultValue: Int(((v.faceOpacity ?? 1) * 100).rounded())) { v.faceOpacity = o >= 100 ? nil : Double(min(max(o, 1), 100)) / 100 }
                    if let s = try await ed.getKeyword("Shadows [Yes/No/Base]", ["Yes", "No", "Base"], defaultValue: v.shadows.map { $0 ? "Yes" : "No" } ?? "Base") { v.shadows = s == "Base" ? nil : s == "Yes" }
                    if let c = try await word(ed, "Edge colour #RRGGBB (Enter = base)"), let hex = UInt32(c.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) { v.edgeColor = hex }
                    guard VisualStyleDef.save(v, in: &ed.doc) else { throw CommandError.invalid("Invalid style (built-in names cannot be redefined).") }
                    ed.print("Visual style \(v.name) saved. VISUALSTYLES Current \(v.name) shows it.")
                }
            },
            CommandDef("TILEDVIEWS", aliases: ["VPTILE", "TILEVIEWS"], category: "View", summary: "Tiled model views: 2, 3 or 4 views (plan, 3D, section, elevations), each with its own zoom and pan.", modifies: false) { ed in
                let m = try ui(ed)
                guard let k = try await ed.getKeyword("Arrangement [2/Stacked/3/4/Single]", ["2", "Stacked", "3", "4", "Single"], defaultValue: "4") else { return }
                if k == "Single" { m.mode = .plan; return }
                TiledViewsState.arrangement = ["2": .two, "Stacked": .twoStacked, "3": .three][k] ?? .four
                NotificationCenter.default.post(name: .tilesChanged, object: nil)
                m.mode = .split
                ed.print("Tiled views: \(TiledViewsState.arrangement.rawValue) — " + TiledViewsState.kinds.prefix(TiledViewsState.arrangement.count).map(\.rawValue).joined(separator: ", "))
            },
            CommandDef("PLOTAREA", aliases: ["PLOTWINDOW"], category: "Output", summary: "Model-space plot area (Extents/Display/Limits/Window) and fit (Standard scale or Exact) for PLOT, PREVIEW and PDF export.", modifies: true) { ed in
                var ps = PageSetup.load(ed.doc, layoutIndex: nil)
                guard let k = try await ed.getKeyword("Plot area [Extents/Display/Limits/Window]", ["Extents", "Display", "Limits", "Window"], defaultValue: ps.plotArea.rawValue) else { return }
                ps.plotArea = PageSetup.PlotArea(rawValue: k) ?? .extents
                switch ps.plotArea {
                case .window:
                    let a = try await ed.requirePoint("Specify first corner of the plot window")
                    let b = try await ed.requirePoint("Specify opposite corner", base: a)
                    ps.setWindow(BBox2(points: [a, b]))
                case .display:
                    guard let box = AppCommands.model(ed)?.canvas?.visibleWorldBox, !box.isEmpty else { throw CommandError.invalid("No 2D view is shown.") }
                    ps.setWindow(box)
                default: break
                }
                if let f = try await ed.getKeyword("Fit [Standard/Exact]", ["Standard", "Exact"], defaultValue: ps.exactFit ? "Exact" : "Standard") { ps.exactFit = f == "Exact" }
                ps.store(in: &ed.doc, layoutIndex: nil)
                ed.print("Plot area \(ps.plotArea.rawValue), \(ps.exactFit ? "exact" : "standard-scale") fit.")
            },
            CommandDef("SHEETSVG", aliases: ["LAYOUTSVG", "EXPORTSHEETSVG"], category: "Output", summary: "Exports the current sheet (or All sheets) as true-size vector SVG with one layer per drawing layer.", modifies: false) { ed in
                guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
                let which = try await ed.getKeyword("Export [Current/All]", ["Current", "All"], defaultValue: "Current") ?? "Current"
                let list = which == "All" ? SheetTools.publishable(ed.doc) : [sheetIndex(ed) ?? 0]
                var path = try await ed.getString("Folder or file path (Enter = choose)", defaultValue: "") ?? ""
                if path.isEmpty {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.prompt = "Export"
                    guard p.runModal() == .OK, let u = p.url else { return }
                    path = u.path
                }
                var base = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                var isDir: ObjCBool = false
                let single = list.count == 1 && base.pathExtension.lowercased() == "svg"
                if !single && !(FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir) && isDir.boolValue) { base = base.deletingLastPathComponent() }
                for li in list {
                    guard let svg = SheetSVG.svg(doc: ed.doc, layoutIndex: li) else { continue }
                    let name = ed.doc.layouts[li].name.replacingOccurrences(of: "/", with: "-")
                    let url = single ? base : base.appendingPathComponent("\(SheetSet.number(ed.doc, li)) \(name).svg")
                    do { try svg.write(to: url, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(url.path).") }
                    ed.print("Wrote \(url.path)")
                }
            },
            CommandDef("PLOTSTYLENAME", aliases: ["NAMEDPLOTSTYLE", "STB"], category: "Output", summary: "Named plot styles (STB): assign a style to a Layer or to Objects, choose the Table used by the current sheet (or model), or List styles.", modifies: true) { ed in
                guard let k = try await ed.getKeyword("Option [Layer/Objects/Table/List]", ["Layer", "Objects", "Table", "List"], defaultValue: "List") else { return }
                switch k {
                case "List":
                    for t in NamedPlotStyles.tables(ed.doc) { ed.print("\(t): " + (NamedPlotStyles.table(t, in: ed.doc)?.keys.sorted().joined(separator: ", ") ?? "")) }
                    for l in ed.doc.layers where NamedPlotStyles.layerStyle(l.name, ed.doc) != "Normal" { ed.print("  layer \(l.name) → \(NamedPlotStyles.layerStyle(l.name, ed.doc))") }
                case "Table":
                    let li = AppCommands.model(ed).flatMap { $0.mode == .sheet ? sheetIndex(ed) : nil }
                    var ps = PageSetup.load(ed.doc, layoutIndex: li)
                    guard let t = try await word(ed, "Named plot style table (None = colour-dependent)") else { return }
                    if t.caseInsensitiveCompare("None") == .orderedSame { ps.namedStyleTable = nil }
                    else { guard NamedPlotStyles.table(t, in: ed.doc) != nil else { throw CommandError.invalid("No table \(t).") }; ps.namedStyleTable = NamedPlotStyles.tables(ed.doc).first { $0.caseInsensitiveCompare(t) == .orderedSame } ?? t }
                    ps.store(in: &ed.doc, layoutIndex: li)
                    ed.print("Plot style table: \(ps.namedStyleTable ?? "colour-dependent").")
                default:
                    let names = NamedPlotStyles.table(NamedPlotStyles.defaultName, in: ed.doc)?.keys.sorted() ?? []
                    if k == "Layer" {
                        guard let l = try await word(ed, "Layer name"), ed.doc.layer(named: l) != nil else { throw CommandError.invalid("No such layer.") }
                        guard let st = try await ed.getString("Plot style [\(names.joined(separator: "/"))]", defaultValue: "Normal") else { return }
                        NamedPlotStyles.setLayerStyle(ed.doc.layer(named: l)!.name, st.trimmingCharacters(in: .whitespaces), &ed.doc)
                        ed.print("Layer \(l) plots with \(st).")
                    } else {
                        let ids = try await ed.getSelection("Select objects")
                        guard let st = try await ed.getString("Plot style [ByLayer/\(names.joined(separator: "/"))]", defaultValue: "ByLayer") else { return }
                        let v = st.trimmingCharacters(in: .whitespaces)
                        for id in ids {
                            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[NamedPlotStyles.prop] = v == "ByLayer" ? nil : v }
                            else if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[NamedPlotStyles.prop] = v == "ByLayer" ? nil : v }
                        }
                        ed.print("\(ids.count) object(s) plot with \(v).")
                    }
                }
            },
            CommandDef("EXPORTSETTINGS", aliases: ["SETTINGSOUT"], category: "Settings", summary: "Exports all preferences (theme, shortcuts, toolbar, workspaces, snippets…) to a .plist file for another Mac.", modifies: false) { ed in
                let p = NSSavePanel(); p.nameFieldStringValue = "Oanarina Archi Tool Settings.plist"; p.allowedContentTypes = [.propertyList]
                guard p.runModal() == .OK, let u = p.url else { return }
                do { try SettingsTransfer.write(to: u) } catch { throw CommandError.invalid("Cannot write \(u.path).") }
                ed.print("Settings exported to \(u.path) (\(SettingsTransfer.export().count) values).")
            },
            CommandDef("IMPORTSETTINGS", aliases: ["SETTINGSIN"], category: "Settings", summary: "Imports preferences exported by EXPORTSETTINGS (restart to apply everything).", modifies: false) { ed in
                let p = NSOpenPanel(); p.allowedContentTypes = [.propertyList]
                guard p.runModal() == .OK, let u = p.url else { return }
                let n: Int
                do { n = try SettingsTransfer.read(from: u) } catch { throw CommandError.invalid("Cannot read \(u.lastPathComponent).") }
                ed.print("Imported \(n) setting(s). Restart the app to apply all of them.")
            },
            CommandDef("WINDOWTABS", aliases: ["DOCTABS"], category: "View", summary: "Native window tabs: Merge all drawing windows into tabs, or open new drawings in Tabs / Windows.", modifies: false) { ed in
                guard let k = try await ed.getKeyword("Option [Merge/Tabs/Windows]", ["Merge", "Tabs", "Windows"], defaultValue: "Merge") else { return }
                switch k {
                case "Merge": (AppCommands.model(ed)?.window ?? NSApp.keyWindow)?.mergeAllWindows(nil); ed.print("Drawing windows merged into tabs.")
                case "Tabs": WindowTabs.preferTabs = true; ed.print("New drawings open as tabs.")
                default: WindowTabs.preferTabs = false; ed.print("New drawings open in their own windows.")
                }
            },
            CommandDef("FULLSCREEN", aliases: ["FS"], category: "View", summary: "Enters or leaves full screen for this drawing window (⌃⌘F).", modifies: false) { ed in
                guard let w = AppCommands.model(ed)?.window else { throw CommandError.invalid("This command needs a document window.") }
                w.toggleFullScreen(nil)
            },
            CommandDef("LWDISPLAYSCALE", aliases: ["LWSCALE"], category: "Settings", summary: "Screen display scale of lineweights (0.1–5, default 1); plotted widths are never changed.", modifies: false) { ed in
                guard let v = try await ed.getDistance("Lineweight display scale <\(fmt(LineweightDisplay.scale, 2))>", defaultValue: LineweightDisplay.scale).value else { return }
                guard (0.1...5).contains(v) else { throw CommandError.invalid("Requires a value from 0.1 to 5.") }
                LineweightDisplay.scale = v
                for m in AppModel.all { m.canvas?.invalidateCache(); m.revision &+= 1 }
                ed.print("Lineweight display scale \(fmt(v, 2)).")
            },
            CommandDef("PSETUPIN", category: "Output", summary: "Imports a page setup (plot style, colour mode, lineweights, stamp, paper) from another drawing into the current sheet or all sheets.", modifies: true) { ed in
                var path = try await ed.getString("Drawing file (.archi) (Enter = choose)", defaultValue: "") ?? ""
                if path.isEmpty {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.init(filenameExtension: "archi") ?? .data]
                    guard p.runModal() == .OK, let u = p.url else { return }
                    path = u.path
                }
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)), let src = try? ArchiFile.decode(data) else { throw CommandError.invalid("Cannot read \(path).") }
                let setups = SheetTools.pageSetups(src)
                guard !setups.isEmpty else { throw CommandError.invalid("That drawing has no page setups.") }
                for (i, s) in setups.enumerated() { ed.print("  \(i + 1). \(s.0)") }
                guard let n = try await ed.getInteger("Page setup number", defaultValue: 1), setups.indices.contains(n - 1) else { return }
                let (name, ps) = setups[n - 1]
                let scope = try await ed.getKeyword("Apply to [Current/All/Model]", ["Current", "All", "Model"], defaultValue: "Current") ?? "Current"
                let targets: [Int?] = scope == "Model" ? [nil] : (scope == "All" ? ed.doc.layouts.indices.map { $0 } : [sheetIndex(ed)].compactMap { $0 })
                let paper = src.layouts.first { $0.name == name }?.paper
                SheetTools.applyPageSetup(ps, to: &ed.doc, layouts: targets, paper: paper)
                ed.print("Page setup \(name) applied to \(targets.count) \(scope == "Model" ? "model space" : "sheet(s)").")
            },
        ]
    }
}
