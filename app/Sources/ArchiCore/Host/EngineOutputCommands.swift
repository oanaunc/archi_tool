// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac output commands (ArchiApp/AppCommands.swift PREVIEW, PUBLISH; AppCommandsExtra.swift
// BATCHPUBLISH, PLOTSTYLE, PLOTLOG, WALKTHROUGHVIDEO, SUNSTUDYVIDEO; AppCommandsReview.swift RENDERQUEUE, PRINTSETUP,
// CAMERAPATHEDIT; AppCommandsNav.swift PLOTAREA, PLOTSTYLENAME, SHEETSVG; AppCommandsRound9.swift EXPORTPDF,
// SHADEPLOT, WEBVIEWEREXPORT, RENDERTOFILE; AppCommandsRound10.swift PATHTRACE, LIGHTMIX; BeautyRender.swift
// RENDERSAVE): same names, aliases, prompts, keywords and messages. Plotting, PDF, SVG, publishing, the path tracer
// and the data passes run in the engine; dialogs, photographic renders and videos are drawn by the Windows shell,
// which the engine asks with `host` notifications (docs/ENGINE-PROTOCOL.md "Output"). Registered by archi-engine only.
import Foundation

enum EngineOutputCommands {
    static var all: [CommandDef] {
        [preview, publish, batchPublish, plotStyle, plotLog, exportPDF, printSetup, plotArea, plotStyleName, shadePlot, sheetSVG,
         webViewerExport, renderSave, renderToFile, renderQueue, walkthroughVideo, sunStudyVideo, cameraPathEdit, pathTrace, lightMix]
    }

    // MARK: Helpers

    @MainActor static func session(_ ed: Editor) throws -> EngineSession { try EngineUICommands.session(ed) }
    @MainActor static func dialog(_ ed: Editor, _ name: String, _ fields: [(String, EngineJSON)] = []) throws {
        try EngineUICommands.host(ed, "dialog", [("dialog", .string(name))] + fields)
    }
    @MainActor static func outputHost(_ ed: Editor, _ op: String, _ fields: [(String, EngineJSON)] = []) throws {
        try EngineUICommands.host(ed, "output", [("op", .string(op))] + fields)
    }
    @MainActor static func displayName(_ ed: Editor) -> String {
        if let u = ed.fileURL { return u.deletingPathExtension().lastPathComponent }
        return ed.doc.info.name.isEmpty ? "Drawing" : ed.doc.info.name
    }
    /// The sheet shown (CTAB) or nil in model space (AppCommandsNav.sheetIndex without the window model).
    @MainActor static func sheetIndex(_ ed: Editor) -> Int? {
        let d = ed.doc
        guard !d.layouts.isEmpty else { return nil }
        if let t = d.variable("CTAB"), let i = d.layouts.firstIndex(where: { $0.name == t }) { return i }
        return 0
    }
    @MainActor static func inSheet(_ ed: Editor) -> Bool {
        guard let t = ed.doc.variable("CTAB") else { return false }
        return t.caseInsensitiveCompare("Model") != .orderedSame && ed.doc.layouts.contains { $0.name == t }
    }
    static func word(_ ed: Editor, _ msg: String) async throws -> String? {
        switch await ed.ask(InputRequest(msg, kinds: [.keyword, .string], keywords: [])) {
        case .keyword(let k): return k
        case .text(let t): let s = t.trimmingCharacters(in: .whitespaces); return s.isEmpty ? nil : s
        case .number(let d): return fmt(d)
        case .cancel: throw CommandError.cancelled
        default: return nil
        }
    }
    static func number(_ ed: Editor, _ msg: String, _ def: Double) async throws -> Double {
        try await ed.getDistance(msg + " <" + fmt(def) + ">", defaultValue: def).value ?? def
    }
    static func text(_ ed: Editor, _ msg: String, _ def: String) async throws -> String {
        let s = try await ed.getString(msg + " <" + def + ">", defaultValue: def) ?? def
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return t.isEmpty ? def : t
    }
    /// A typed output path, or nil for "choose" (empty answer or "?"), resolved against the session folder.
    @MainActor static func typedPath(_ ed: Editor, _ typed: String?) throws -> String? {
        guard let t = typed?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")), !t.isEmpty, t != "?" else { return nil }
        return try session(ed).url(t).path
    }
    static func cameraJSON(_ c: Camera?) -> EngineJSON { c.map { EngineOutputFormat.cameraJSON($0) } ?? .null }

    // MARK: Plot

    static var preview: CommandDef {
        CommandDef("PREVIEW", aliases: ["PRE", "PRINTPREVIEW", "PLOTPREVIEW", "PLOTDIALOG"], category: "Output", summary: "Plot dialog with a live preview: prints or saves exactly what is shown.", modifies: false) { ed in
            try dialog(ed, "plotPreview")
        }
    }

    static var publish: CommandDef {
        CommandDef("PUBLISH", aliases: ["BATCHPLOT", "EXPORTSHEETS", "PUBLISHPDF"], category: "Output", summary: "Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog).", modifies: false) { ed in
            let s = try session(ed)
            let p = try await ed.getString("Enter PDF file path or Enter to choose", defaultValue: "")
            if let path = try typedPath(ed, p) {
                var o = EngineObject()
                o.set("path", path)
                _ = try s.plotPublish(o.json)
            } else {
                try outputHost(ed, "publish", [("suggested", .string(displayName(ed) + " — sheets.pdf")), ("bookmarks", .bool(true))])
            }
        }
    }

    static var batchPublish: CommandDef {
        CommandDef("BATCHPUBLISH", aliases: ["PUBLISHSET", "BATCHPLOTPDF"], category: "Output",
                   summary: "Publishes chosen sheets to one PDF with bookmarks (sheet number and name) and optional sheet index.", modifies: false) { ed in
            let s = try session(ed)
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
            let k = try await ed.getKeyword("Publish [Dialog/All]", ["Dialog", "All"], defaultValue: "Dialog") ?? "Dialog"
            if k == "Dialog" { try dialog(ed, "batchPublish"); return }
            let typed = try await ed.getString("Output PDF <choose>", defaultValue: "")
            let all = EngineJSON.ints(Array(ed.doc.layouts.indices))
            if let path = try typedPath(ed, typed) {
                var o = EngineObject()
                o.set("path", path)
                o.set("layouts", all)
                o.set("bookmarks", true)
                o.set("quiet", true)
                _ = try s.plotPublish(o.json)
                ed.print("Published " + String(ed.doc.layouts.count) + " sheet(s) with bookmarks to " + path)
            } else {
                try outputHost(ed, "publish", [("suggested", .string(displayName(ed) + " — sheets.pdf")), ("bookmarks", .bool(true)), ("layouts", all)])
            }
        }
    }

    static var plotStyle: CommandDef {
        CommandDef("PLOTSTYLE", aliases: ["CTB", "PLOTSTYLES", "STYLESMANAGER"], category: "Output",
                   summary: "Plot style tables (colour → pen colour, lineweight, screening): Edit, Set for the sheet/model, List.") { ed in
            _ = try session(ed)
            let k = try await ed.getKeyword("Plot styles [Edit/Set/List]", ["Edit", "Set", "List"], defaultValue: "Edit") ?? "Edit"
            let tables = EnginePlotStyleTable.all(ed.doc)
            switch k {
            case "List":
                for t in tables { ed.print("  " + t.name + " — " + String(t.pens.count) + " pen(s)") }
            case "Set":
                let names = tables.map(\.name).joined(separator: ", ")
                guard let n = try await ed.getString("Table name (" + names + ", or None)", defaultValue: "monochrome.ctb") else { return }
                let li: Int? = inSheet(ed) ? sheetIndex(ed) : nil
                var setup = EnginePageSetup.load(ed.doc, layoutIndex: li)
                if n.lowercased() == "none" { setup.plotStyleTable = nil }
                else {
                    guard let t = EnginePlotStyleTable.named(n, in: ed.doc) else { throw CommandError.invalid("No plot style table \"" + n + "\".") }
                    setup.plotStyleTable = t.name
                }
                setup.store(in: &ed.doc, layoutIndex: li)
                let target = li.map { "sheet " + ed.doc.layouts[$0].name } ?? "model space"
                ed.print("Plot style of " + target + ": " + (setup.plotStyleTable ?? "none") + ".")
            default:
                try dialog(ed, "plotStyles")
            }
        }
    }

    static var plotLog: CommandDef {
        CommandDef("PLOTLOG", aliases: ["PLOTHISTORY"], category: "Output", summary: "Shows the plot log (every plot, PDF export and publish with date, sheets and plot style) [List/Open/Clear].", modifies: false) { ed in
            let k = try await ed.getKeyword("Plot log [List/Open/Clear]", ["List", "Open", "Clear"], defaultValue: "List") ?? "List"
            switch k {
            case "Open":
                EnginePlotLog.ensure()
                try outputHost(ed, "openFile", [("path", .string(EnginePlotLog.url.path))])
            case "Clear":
                EnginePlotLog.clear()
                ed.print("Plot log cleared.")
            default:
                let rows = EnginePlotLog.entries()
                if rows.isEmpty { ed.print("The plot log is empty.") }
                for r in rows.suffix(20) { ed.print("  " + r.joined(separator: "  ·  ")) }
            }
        }
    }

    static var exportPDF: CommandDef {
        CommandDef("EXPORTPDF", aliases: ["PDFEXPORT", "PDFOUT", "LAYEREDPDF"], category: "Output", summary: "Vector PDF with one PDF layer (OCG) per drawing layer, searchable text and hyperlinks: current sheet, model or all sheets, at true scale.", modifies: false) { ed in
            let s = try session(ed)
            let hasSheets = !ed.doc.layouts.isEmpty
            let def = inSheet(ed) && hasSheets ? "Current" : "Model"
            let k = try await ed.getKeyword("Export [Current/Model/All]", ["Current", "Model", "All"], defaultValue: def) ?? def
            var o = EngineObject()
            switch k {
            case "All":
                guard hasSheets else { throw CommandError.invalid("The drawing has no sheets.") }
                o.set("what", "all")
            case "Current":
                guard hasSheets else { throw CommandError.invalid("The drawing has no sheets.") }
                o.set("layout", sheetIndex(ed) ?? 0)
            default:
                o.set("what", "model")
            }
            guard let path = try await EngineView3DCommands.path(ed, "PDF file", ext: "pdf", def: EngineView3DCommands.defaultPath(ed, "pdf")) else { return }
            o.set("path", path)
            o.set("layered", true)
            _ = try s.plotPDF(o.json)
        }
    }

    static var printSetup: CommandDef {
        CommandDef("PRINTSETUP", aliases: ["PRINTOPTIONS", "QUICKPRINT"], category: "Output", summary: "Prints with printer, paper, tray (input slot), media, scaling (fit, 1:1, percent) and copies.", modifies: false) { ed in
            try dialog(ed, "printSetup")
        }
    }

    static var plotArea: CommandDef {
        CommandDef("PLOTAREA", aliases: ["PLOTWINDOW"], category: "Output", summary: "Model-space plot area (Extents/Display/Limits/Window) and fit (Standard scale or Exact) for PLOT, PREVIEW and PDF export.", modifies: true) { ed in
            let s = try session(ed)
            var ps = EnginePageSetup.load(ed.doc, layoutIndex: nil)
            guard let k = try await ed.getKeyword("Plot area [Extents/Display/Limits/Window]", ["Extents", "Display", "Limits", "Window"], defaultValue: ps.plotArea) else { return }
            ps.plotArea = k
            switch k {
            case "Window":
                let a = try await ed.requirePoint("Specify first corner of the plot window")
                let b = try await ed.requirePoint("Specify opposite corner", base: a)
                let box = BBox2(points: [a, b])
                ps.plotWindow = [box.min.x, box.min.y, box.max.x, box.max.y]
            case "Display":
                guard let box = s.displayBox, !box.isEmpty else { throw CommandError.invalid("No 2D view is shown.") }
                ps.plotWindow = [box.min.x, box.min.y, box.max.x, box.max.y]
            default: break
            }
            if let f = try await ed.getKeyword("Fit [Standard/Exact]", ["Standard", "Exact"], defaultValue: ps.exactFit ? "Exact" : "Standard") { ps.exactFit = f == "Exact" }
            ps.store(in: &ed.doc, layoutIndex: nil)
            ed.print("Plot area " + ps.plotArea + ", " + (ps.exactFit ? "exact" : "standard-scale") + " fit.")
        }
    }

    static var plotStyleName: CommandDef {
        CommandDef("PLOTSTYLENAME", aliases: ["NAMEDPLOTSTYLE", "STB"], category: "Output", summary: "Named plot styles (STB): assign a style to a Layer or to Objects, choose the Table used by the current sheet (or model), or List styles.", modifies: true) { ed in
            guard let k = try await ed.getKeyword("Option [Layer/Objects/Table/List]", ["Layer", "Objects", "Table", "List"], defaultValue: "List") else { return }
            switch k {
            case "List":
                for t in EngineNamedPlotStyles.tables(ed.doc) {
                    let keys = EngineNamedPlotStyles.table(t, in: ed.doc)?.keys.sorted().joined(separator: ", ") ?? ""
                    ed.print(t + ": " + keys)
                }
                for l in ed.doc.layers where EngineNamedPlotStyles.layerStyle(l.name, ed.doc) != "Normal" {
                    ed.print("  layer " + l.name + " → " + EngineNamedPlotStyles.layerStyle(l.name, ed.doc))
                }
            case "Table":
                let li: Int? = inSheet(ed) ? sheetIndex(ed) : nil
                var ps = EnginePageSetup.load(ed.doc, layoutIndex: li)
                guard let t = try await word(ed, "Named plot style table (None = colour-dependent)") else { return }
                if t.caseInsensitiveCompare("None") == .orderedSame { ps.namedStyleTable = nil }
                else {
                    guard EngineNamedPlotStyles.table(t, in: ed.doc) != nil else { throw CommandError.invalid("No table " + t + ".") }
                    ps.namedStyleTable = EngineNamedPlotStyles.tables(ed.doc).first { $0.caseInsensitiveCompare(t) == .orderedSame } ?? t
                }
                ps.store(in: &ed.doc, layoutIndex: li)
                ed.print("Plot style table: " + (ps.namedStyleTable ?? "colour-dependent") + ".")
            default:
                let names = EngineNamedPlotStyles.table(EngineNamedPlotStyles.defaultName, in: ed.doc)?.keys.sorted() ?? []
                if k == "Layer" {
                    guard let l = try await word(ed, "Layer name"), let layer = ed.doc.layer(named: l) else { throw CommandError.invalid("No such layer.") }
                    guard let st = try await ed.getString("Plot style [" + names.joined(separator: "/") + "]", defaultValue: "Normal") else { return }
                    EngineNamedPlotStyles.setLayerStyle(layer.name, st.trimmingCharacters(in: .whitespaces), &ed.doc)
                    ed.print("Layer " + l + " plots with " + st + ".")
                } else {
                    let ids = try await ed.getSelection("Select objects")
                    guard let st = try await ed.getString("Plot style [ByLayer/" + names.joined(separator: "/") + "]", defaultValue: "ByLayer") else { return }
                    let v = st.trimmingCharacters(in: .whitespaces)
                    let value: String? = v == "ByLayer" ? nil : v
                    for id in ids {
                        if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[EngineNamedPlotStyles.prop] = value }
                        else if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[EngineNamedPlotStyles.prop] = value }
                    }
                    ed.print(String(ids.count) + " object(s) plot with " + v + ".")
                }
            }
        }
    }

    static var shadePlot: CommandDef {
        CommandDef("SHADEPLOT", aliases: ["VPSHADEPLOT", "VIEWPORTSHADE"], category: "Output", summary: "Shade plot of a 3D (axonometric / perspective) sheet viewport: As Displayed, Wireframe, Hidden or Rendered, and the saved 3D view it shows.") { ed in
            guard let li = sheetIndex(ed) else { throw CommandError.invalid("The drawing has no sheets.") }
            let layout = ed.doc.layouts[li]
            let threeD = layout.viewports.indices.filter { EngineShadePlot.is3D(layout.viewports[$0]) }
            guard let first = threeD.first else { throw CommandError.invalid(layout.name + " has no axonometric or perspective viewport (MVIEW, then set its view).") }
            let list = threeD.map { String($0 + 1) }.joined(separator: ", ")
            guard let n = try await ed.getInteger("Viewport number (" + list + ")", defaultValue: first + 1), threeD.contains(n - 1) else { throw CommandError.invalid("Not a 3D viewport.") }
            let cur = EngineShadePlot.mode(ed.doc, layout: layout.name, index: n - 1)
            let names = EngineShadePlot.modes.map { $0.replacingOccurrences(of: " ", with: "") }
            let k = try await ed.getKeyword("Shade plot [" + names.joined(separator: "/") + "/Camera]", names + ["Camera"], defaultValue: cur.replacingOccurrences(of: " ", with: "")) ?? "Hidden"
            if k == "Camera" {
                var views = ed.doc.views.filter { $0.kind == "3d" && $0.camera != nil }.map(\.name)
                views += ed.doc.namedViews.filter { $0.camera != nil }.map(\.name)
                ed.print("3D views: " + (views.isEmpty ? "none (CAMERAVIEW, AXONVIEW or SAVECAMERA)" : views.joined(separator: ", ")))
                guard let v = try await ed.getString("3D view name (Enter for the default isometric)", defaultValue: ""), !v.isEmpty else {
                    ed.doc.variables[EngineShadePlot.cameraKey(layout.name, n - 1)] = nil
                    return
                }
                guard views.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else { throw CommandError.invalid("No 3D view " + v + ".") }
                ed.doc.setVariable(EngineShadePlot.cameraKey(layout.name, n - 1), v)
                ed.print("Viewport " + String(n) + " shows " + v + ".")
                return
            }
            let mode = EngineShadePlot.modes.first { $0.replacingOccurrences(of: " ", with: "") == k } ?? "Hidden"
            ed.doc.setVariable(EngineShadePlot.key(layout.name, n - 1), mode)
            ed.print("Viewport " + String(n) + " of " + layout.name + ": shade plot " + mode + ".")
            if mode == "Rendered" {
                // The Windows shell renders the viewport's camera and stores the image (SHADEPLOTIMAGE:<sheet>:<n>).
                let vp = layout.viewports[n - 1]
                let cam = EngineShadePlot.camera(ed.doc, vp, layout: layout.name, index: n - 1)
                try outputHost(ed, "shadePlotRender", [("layout", .string(layout.name)), ("index", .int(n - 1)), ("camera", cameraJSON(cam)),
                                                        ("aspect", .number(max(vp.size.x, 1) / max(vp.size.y, 1)))])
            }
        }
    }

    static var sheetSVG: CommandDef {
        CommandDef("SHEETSVG", aliases: ["LAYOUTSVG", "EXPORTSHEETSVG"], category: "Output", summary: "Exports the current sheet (or All sheets) as true-size vector SVG with one layer per drawing layer.", modifies: false) { ed in
            let s = try session(ed)
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no sheets.") }
            let which = try await ed.getKeyword("Export [Current/All]", ["Current", "All"], defaultValue: "Current") ?? "Current"
            let path = try await ed.getString("Folder or file path (Enter = choose)", defaultValue: "") ?? ""
            var o = EngineObject()
            o.set("all", which == "All")
            o.set("layout", sheetIndex(ed) ?? 0)
            if let p = try typedPath(ed, path) {
                o.set("path", p)
                _ = try s.plotSheetSVG(o.json)
            } else {
                try outputHost(ed, "sheetSVG", [("all", .bool(which == "All")), ("layout", .int(sheetIndex(ed) ?? 0))])
            }
        }
    }

    static var webViewerExport: CommandDef {
        CommandDef("WEBVIEWEREXPORT", aliases: ["WEBEXPORT", "EXPORTWEB", "WEBVIEWER"], category: "Output", summary: "Exports the 3D model as one standalone HTML file with a WebGL viewer (orbit, pan, zoom, views) that opens in any browser.", modifies: false) { ed in
            let s = try session(ed)
            let sc = EngineWebViewer.scene(doc: ed.doc)
            guard sc.triangles > 0 else { throw CommandError.invalid("The model has no 3D content.") }
            guard let path = try await EngineView3DCommands.path(ed, "HTML file", ext: "html", def: EngineView3DCommands.defaultPath(ed, "html", suffix: "-3D")) else { return }
            var o = EngineObject()
            o.set("path", path)
            _ = try s.webViewerExport(o.json)
        }
    }

    // MARK: Render

    static var renderSave: CommandDef {
        CommandDef("RENDERSAVE", aliases: ["RENDERPNG", "RSAVE"], category: "Output",
                   summary: "Renders offscreen to a PNG without the render window: RENDERSAVE <preset> <camera|Current> <width> <height> <path> (4× MSAA + supersampling, vertical correction for eye-level cameras).", modifies: false) { ed in
            let s = try session(ed)
            let cur = EngineRenderPresets.keywords[EngineRenderPresets.names.firstIndex(of: EngineRenderPresets.current(ed.doc)) ?? 0]
            guard let k = try await ed.getKeyword("Preset [Daylight/Goldenhour/Overcast/Night]", EngineRenderPresets.keywords, defaultValue: cur), let preset = EngineRenderPresets.named(k) else { return }
            let cams = ed.doc.namedViews.filter { $0.camera != nil }.map(\.name)
            let answer = (try await ed.getString("Camera [" + (cams + ["Current"]).joined(separator: "/") + "]", defaultValue: "Current") ?? "Current").trimmingCharacters(in: .whitespaces)
            let parsed = splitCameraAnswer(answer, cameras: cams)
            let camName = parsed.0
            var rest = parsed.1
            var camera: Camera?
            if camName.caseInsensitiveCompare("Current") != .orderedSame {
                guard let c = ed.doc.namedViews.first(where: { $0.camera != nil && $0.name.caseInsensitiveCompare(camName) == .orderedSame })?.camera else {
                    throw CommandError.invalid("No saved camera named " + camName + ". Saved cameras: " + (cams.isEmpty ? "none (SAVECAMERA)" : cams.joined(separator: ", ")) + ".")
                }
                camera = c
            }
            func nextInt(_ prompt: String, _ def: Int) async throws -> Int {
                if !rest.isEmpty {
                    let t = rest.removeFirst()
                    guard let v = Int(t) else { throw CommandError.invalid(t + " is not a whole number of pixels.") }
                    return v
                }
                return try await ed.getInteger(prompt, defaultValue: def) ?? def
            }
            let w = try await nextInt("Width in pixels", 1920)
            let h = try await nextInt("Height in pixels", 1080)
            guard w >= 16, h >= 16, w <= 7680, h <= 4320 else { throw CommandError.invalid("Use a size from 16×16 to 7680×4320.") }
            let base = ed.fileURL?.deletingPathExtension().lastPathComponent ?? "Render"
            let defPath = base + " " + preset + " " + camName + ".png"
            var path: String
            if !rest.isEmpty { path = rest.joined(separator: " ") }
            else {
                guard let p = try await ed.getString("PNG file", defaultValue: defPath), !p.isEmpty else { return }
                path = p
            }
            path = resolvePNG(path, base: ed.fileURL?.deletingLastPathComponent(), session: s)
            try outputHost(ed, "renderSave", [("preset", .string(preset)), ("keyword", .string(k)), ("camera", .string(camName)), ("cameraData", cameraJSON(camera)),
                                              ("width", .int(w)), ("height", .int(h)), ("supersample", .int(w * h <= 1920 * 1080 ? 3 : 2)), ("path", .string(path))])
        }
    }

    /// "Front 1920 1080 out.png" → camera "Front" and the rest (BeautyRenderer.splitCameraAnswer).
    static func splitCameraAnswer(_ answer: String, cameras: [String]) -> (String, [String]) {
        let words = answer.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return ("Current", []) }
        let names = cameras + ["Current"]
        for k in stride(from: words.count, through: 1, by: -1) {
            let cand = words[0..<k].joined(separator: " ")
            if let n = names.first(where: { $0.caseInsensitiveCompare(cand) == .orderedSame }) { return (n, Array(words[k...])) }
        }
        return (words[0], Array(words.dropFirst()))
    }
    /// `~`, absolute, or relative to the drawing folder (else the home folder); ".png" added (BeautyRenderer.resolve).
    @MainActor static func resolvePNG(_ path: String, base: URL?, session: EngineSession) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.count >= 2, (p.hasPrefix("\"") && p.hasSuffix("\"")) || (p.hasPrefix("'") && p.hasSuffix("'")) { p = String(p.dropFirst().dropLast()) }
        p = (p as NSString).expandingTildeInPath
        if !p.lowercased().hasSuffix(".png") { p += ".png" }
        let chars = Array(p)
        let absolute = p.hasPrefix("/") || p.hasPrefix("\\") || (chars.count > 1 && chars[1] == ":")
        if absolute { return URL(fileURLWithPath: p).path }
        return (base ?? URL(fileURLWithPath: NSHomeDirectory())).appendingPathComponent(p).path
    }

    static var renderToFile: CommandDef {
        CommandDef("RENDERTOFILE", aliases: ["RENDERFILE", "RENDEROUT", "RENDERPASS"], category: "View", summary: "Renders to an image file: any size up to 7680×4320 (tiled), a pass (Beauty, Alpha, Depth, Normal, Material ID), a style (Photographic, Sketch, Watercolour) and an optional region of the frame.", modifies: false) { ed in
            let s = try session(ed)
            let res = try await word(ed, "Resolution WxH (up to 7680x4320) <1920x1080>") ?? "1920x1080"
            let wh = res.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard wh.count == 2, wh[0] >= 16, wh[1] >= 16, wh[0] <= 7680, wh[1] <= 4320 else { throw CommandError.invalid("Use a size from 16x16 to 7680x4320.") }
            let passNames = ["Beauty", "Alpha", "Depth", "Normal", "Material ID"]
            let passes = passNames.map { $0.replacingOccurrences(of: " ", with: "") }
            let k = try await ed.getKeyword("Pass [" + passes.joined(separator: "/") + "]", passes, defaultValue: "Beauty") ?? "Beauty"
            let pass = passNames.first { $0.replacingOccurrences(of: " ", with: "") == k } ?? "Beauty"
            var style = "Photographic"
            if pass == "Beauty" { style = try await ed.getKeyword("Style [Photographic/Sketch/Watercolour]", ["Photographic", "Sketch", "Watercolour"], defaultValue: "Photographic") ?? "Photographic" }
            let rg = try await word(ed, "Region x0,y0,x1,y1 as fractions of the frame (top-left origin) or Enter for all") ?? ""
            var region: [Double]? = nil
            let r = rg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if r.count == 4 {
                guard r[2] > r[0], r[3] > r[1], r.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { throw CommandError.invalid("Region fractions must be 0–1 with x1 > x0 and y1 > y0.") }
                region = r
            }
            let suffix = pass == "Beauty" ? "-render" : "-" + k.lowercased()
            guard let path = try await EngineView3DCommands.path(ed, "PNG file", ext: "png", def: EngineView3DCommands.defaultPath(ed, "png", suffix: suffix)) else { return }
            let regionNote = region == nil ? "" : " (region of " + String(wh[0]) + "×" + String(wh[1]) + ")"
            if pass == "Beauty" || pass == "Alpha" {
                try outputHost(ed, "renderToFile", [("width", .int(wh[0])), ("height", .int(wh[1])), ("pass", .string(pass)), ("style", .string(style)),
                                                    ("region", region.map { EngineJSON.numbers($0) } ?? .null), ("path", .string(path)), ("camera", cameraJSON(s.view3d.camera))])
                return
            }
            var o = EngineObject()
            o.set("pass", pass); o.set("width", wh[0]); o.set("height", wh[1]); o.set("path", path)
            if let region { o.set("region", EngineJSON.numbers(region)) }
            let out = try s.renderPass(o.json)
            let pw = out["width"]?.intValue ?? wh[0], ph = out["height"]?.intValue ?? wh[1]
            ed.print(pass + " " + String(pw) + "×" + String(ph) + regionNote + " → " + path)
            for m in out["materials"]?.arrayValue ?? [] { ed.print("  " + (m["color"]?.stringValue ?? "") + "  " + (m["name"]?.stringValue ?? "")) }
        }
    }

    static var renderQueue: CommandDef {
        CommandDef("RENDERQUEUE", aliases: ["BATCHRENDER", "RENDERHISTORY"], category: "View", summary: "Render queue: add the current view or saved cameras, render them in turn to PNG files; render history with thumbnails.", modifies: false) { ed in
            let s = try session(ed)
            let k = try await ed.getKeyword("Render queue [Show/Current/Cameras/Run]", ["Show", "Current", "Cameras", "Run"], defaultValue: "Show") ?? "Show"
            var add: [EngineJSON] = []
            let name = ed.doc.info.name
            switch k {
            case "Current":
                add.append(.object([EngineJSONField("name", .string(name + " – view")), EngineJSONField("camera", cameraJSON(s.view3d.camera)), EngineJSONField("numbered", .bool(true))]))
            case "Cameras":
                let cams = ed.doc.namedViews.filter { $0.camera != nil }
                for v in cams { add.append(.object([EngineJSONField("name", .string(name + " – " + v.name)), EngineJSONField("camera", cameraJSON(v.camera))])) }
                ed.print("Queued " + String(cams.count) + " saved camera(s).")
            default: break
            }
            try dialog(ed, "renderQueue", [("add", .array(add)), ("run", .bool(k == "Run"))])
        }
    }

    static var walkthroughVideo: CommandDef {
        CommandDef("WALKTHROUGHVIDEO", aliases: ["WALKVIDEO", "ANIPATH", "CAMERAPATH"], category: "View",
                   summary: "Exports an MP4 walkthrough along a smooth path through the saved cameras (in order).", modifies: false) { ed in
            _ = try session(ed)
            let cams = ed.doc.namedViews.compactMap(\.camera)
            guard cams.count >= 2 else { throw CommandError.invalid("Save at least two cameras with SAVECAMERA first.") }
            guard let secs = try await ed.getDistance("Duration in seconds", defaultValue: 10).value, secs > 0 else { return }
            let typed = try await ed.getString("Output file (.mp4) <choose>", defaultValue: "")
            let path = try typedPath(ed, typed)
            ed.print("Rendering walkthrough (" + String(cams.count) + " cameras, " + fmt(EngineCameraPaths.length(cams) / 1000, 1) + " m of path)…")
            try outputHost(ed, "video", [("kind", .string("walkthrough")), ("seconds", .number(min(secs, 600))), ("fps", .int(30)), ("width", .int(1280)), ("height", .int(720)),
                                         ("path", path.map { EngineJSON.string($0) } ?? .null), ("suggested", .string(displayName(ed) + " walkthrough.mp4"))])
        }
    }

    static var sunStudyVideo: CommandDef {
        CommandDef("SUNSTUDYVIDEO", aliases: ["SUNVIDEO", "SHADOWSTUDY"], category: "View",
                   summary: "Exports an MP4 sun-study time-lapse (shadows through the day) from the current 3D camera.", modifies: false) { ed in
            let s = try session(ed)
            guard let day = try await ed.getInteger("Day of year (172 = 21 June)", defaultValue: 172), (1...366).contains(day) else { return }
            guard let a = try await ed.getDistance("Start hour", defaultValue: 7).value, let b = try await ed.getDistance("End hour", defaultValue: 19).value else { return }
            guard b > a else { throw CommandError.invalid("The end hour must be after the start hour.") }
            let typed = try await ed.getString("Output file (.mp4) <choose>", defaultValue: "")
            let path = try typedPath(ed, typed)
            try outputHost(ed, "video", [("kind", .string("sunStudy")), ("day", .int(day)), ("fromHour", .number(a)), ("toHour", .number(b)), ("seconds", .number(10)),
                                         ("fps", .int(30)), ("width", .int(1280)), ("height", .int(720)), ("camera", cameraJSON(s.view3d.camera)),
                                         ("path", path.map { EngineJSON.string($0) } ?? .null), ("suggested", .string(displayName(ed) + " sun study.mp4"))])
        }
    }

    static var cameraPathEdit: CommandDef {
        CommandDef("CAMERAPATHEDIT", aliases: ["ANIMPATH", "CAMPATHS"], category: "View", summary: "Camera path editor: keys from the 3D view or saved cameras at times, timeline scrubbing and playback, video export.", modifies: false) { ed in
            _ = try session(ed)
            EngineView3DCommands.show3D(ed)
            try dialog(ed, "cameraPaths")
        }
    }

    static var pathTrace: CommandDef {
        CommandDef("PATHTRACE", aliases: ["PTRENDER", "RENDERPT", "PATHTRACER", "RAYTRACE"], category: "View", summary: "Progressive path-traced render of the 3D view (GGX materials, glass refraction, PBR maps, sun, sky, lights): Window, or File with size, samples and denoising.", modifies: false) { ed in
            let s = try session(ed)
            let k = try await ed.getKeyword("Path trace [Window/File]", ["Window", "File"], defaultValue: "Window") ?? "Window"
            if k == "Window" { try dialog(ed, "pathTrace", [("start", .bool(true))]); return }
            let docName: String = ed.doc.info.name.isEmpty ? "Drawing" : ed.doc.info.name
            let desktopBase: String = NSHomeDirectory() + "/Desktop/" + docName
            let base: String = ed.fileURL?.deletingPathExtension().path ?? desktopBase
            let def: String = base + " path traced.png"
            var p = (try await text(ed, "Image file", def) as NSString).expandingTildeInPath
            if (p as NSString).pathExtension.isEmpty { p += ".png" }
            let w = Int(try await number(ed, "Width (px)", 1280)), h = Int(try await number(ed, "Height (px)", 720))
            let spp = Int(try await number(ed, "Samples per pixel", 64))
            let dn = (try await ed.getKeyword("Denoise [Yes/No]", ["Yes", "No"], defaultValue: "Yes") ?? "Yes") == "Yes"
            guard w >= 8, h >= 8, w <= 8192, h <= 8192, spp >= 1, spp <= 100_000 else { throw CommandError.invalid("Size 8–8192 px and 1+ samples.") }
            var o = EngineObject()
            o.set("width", w); o.set("height", h); o.set("samples", spp); o.set("denoise", dn)
            _ = try s.pathTraceStart(o.json)
            guard let job = s.output.tracer else { return }
            while !job.finished && !job.isCancelled { try await Task.sleep(nanoseconds: 50_000_000) }
            let px = job.image(final: true)
            let dest = s.url(p)
            do { try EnginePNG.rgb(px, width: w, height: h).write(to: dest) } catch { throw CommandError.invalid("Could not encode the image.") }
            let secs = Date().timeIntervalSince(job.started)
            var msg: String = "Path traced " + String(w) + "×" + String(h)
            msg += ", " + String(job.session.samples) + " samples"
            if dn { msg += ", denoised" }
            msg += " in " + fmt(secs, 1) + " s → " + dest.path
            ed.print(msg)
        }
    }

    static var lightMix: CommandDef {
        CommandDef("LIGHTMIX", aliases: ["LIGHTGROUPS", "RENDERLIGHTMIX"], category: "View", summary: "Light mix of path-traced renders: weights of the Sun, Sky and Artificial light groups, changeable after rendering (saved in the drawing).") { ed in
            let s = try session(ed)
            var mix = s.storedLightMix()
            mix.sun = Float(try await number(ed, "Sun weight", Double(mix.sun)))
            mix.sky = Float(try await number(ed, "Sky weight", Double(mix.sky)))
            mix.artificial = Float(try await number(ed, "Artificial lights weight", Double(mix.artificial)))
            guard [mix.sun, mix.sky, mix.artificial].allSatisfy({ $0 >= 0 && $0 <= 100 }) else { throw CommandError.invalid("Weights 0–100.") }
            ed.doc.setVariable("LIGHTMIX", fmt(Double(mix.sun), 3) + "," + fmt(Double(mix.sky), 3) + "," + fmt(Double(mix.artificial), 3))
            s.output.tracer?.mix = mix
            ed.print("Light mix: sun " + fmt(Double(mix.sun), 2) + ", sky " + fmt(Double(mix.sky), 2) + ", artificial " + fmt(Double(mix.artificial), 2) + ".")
            try outputHost(ed, "lightMix", [("sun", .number(Double(mix.sun))), ("sky", .number(Double(mix.sky))), ("artificial", .number(Double(mix.artificial)))])
        }
    }
}

extension EngineSession {
    /// Registers the portable output commands (archi-engine only; the Mac app has its own).
    public static func registerOutputCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineOutputCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
    }

    /// The 2D view rectangle the shell last drew (view.drawList `rect`), for PLOTAREA Display.
    var displayBox: BBox2? { EngineSession.lastDisplayBoxes[ObjectIdentifier(self)] }
    static var lastDisplayBoxes: [ObjectIdentifier: BBox2] = [:]
}
