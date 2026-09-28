// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac sheet commands that lived in the UI layer (ArchiApp/AppCommandsNav.swift MVIEWPOLY,
// MVSETUP, SHEETGRID, SHEETPLACEHOLDER, SHEETFIELD, PSETUPIN, LAYOUTTABS; AppCommands.swift SHEETRENUMBER,
// SHEETVIEWTITLES; AppCommandsStudio.swift SHEETIMAGE; AppCommandsRound9.swift TITLEBLOCKDESIGN; AppCommandsRound11.swift
// ZOOMXP). Same names, aliases, prompts and messages; the sheet is CTAB (the one the shell shows). Where the Mac drives
// its own window the engine asks the Windows shell with `host` notifications:
// {"action":"layoutTabs","on":true|false|null}, {"action":"paperZoom","factor","ratio","ratioText","pixelsPerUnit"},
// {"action":"chooseFile","purpose":"PSETUPIN","extensions":["archi"]} (the shell answers the pending prompt with the path),
// {"action":"sheetImage","layout","dpi","format","path"?,"suggested"}.
// Registered by archi-engine only (EngineSession.registerPortableAppCommands); the Mac app registers its own versions.
import Foundation

enum EngineSheetCommands {
    static var all: [CommandDef] {
        [mviewPoly, mvSetup, sheetGrid, sheetPlaceholder, sheetField, pSetupIn, layoutTabs, sheetRenumber, sheetViewTitles,
         sheetImage, titleBlockDesign, zoomXP]
    }

    // MARK: Helpers (AppCommandsNav)

    /// Sheet index a sheet command works on: the shown sheet (CTAB), else the first; nil without sheets.
    @MainActor static func sheetIndex(_ ed: Editor) -> Int? {
        guard !ed.doc.layouts.isEmpty else { return nil }
        return EngineToolCommands.activeSheet(ed)
    }

    @MainActor static func viewportNumber(_ ed: Editor, _ li: Int) async throws -> Int? {
        let n = ed.doc.layouts[li].viewports.count
        guard n > 0 else { throw CommandError.invalid("The sheet has no viewports.") }
        guard let v = try await ed.getInteger("Viewport number (1–\(n))", defaultValue: 1) else { return nil }
        guard (1...n).contains(v) else { throw CommandError.invalid("No viewport \(v).") }
        return v - 1
    }

    /// One space-delimited word (keywords and plain text alike); nil on Enter.
    @MainActor static func word(_ ed: Editor, _ msg: String) async throws -> String? {
        switch await ed.ask(InputRequest(msg, kinds: [.keyword, .string], keywords: [])) {
        case .keyword(let k): return k
        case .text(let t):
            let s = t.trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        case .number(let d): return fmt(d)
        case .cancel: throw CommandError.cancelled
        default: return nil
        }
    }

    @MainActor static func onOff(_ ed: Editor, _ msg: String) async throws -> String? {
        try await ed.getKeyword(msg + " [ON/OFF/Toggle]", ["ON", "OFF", "Toggle"], defaultValue: "Toggle")
    }

    // MARK: Viewport maths (SheetTools)

    static func paperPoint(_ p: Vec2, in vp: Viewport) -> Vec2 { vp.origin + vp.size / 2 + (p - vp.viewCenter) / max(vp.scale, 1e-12) }
    static func viewportScale(ratio n: Double, units: Units) -> Double { n / units.mm }

    /// MVSETUP Align: pans viewport `j` so that model point `pj` lines up with model point `pi` of viewport `i` on paper.
    static func align(_ layout: inout Layout, base i: Int, basePoint pi: Vec2, other j: Int, otherPoint pj: Vec2, horizontal: Bool) -> Bool {
        guard layout.viewports.indices.contains(i), layout.viewports.indices.contains(j), i != j else { return false }
        let target = paperPoint(pi, in: layout.viewports[i])
        var vj = layout.viewports[j]
        let delta = target - paperPoint(pj, in: vj)
        let shift = horizontal ? Vec2(0, delta.y) : Vec2(delta.x, 0)
        vj.viewCenter = vj.viewCenter - shift * vj.scale
        layout.viewports[j] = vj
        return true
    }

    /// Adds a polygonal viewport (clip boundary = the polygon) showing `center` at `scale`.
    @discardableResult
    static func addPolygonal(_ doc: inout ArchiDocument, layoutIndex li: Int, _ pts: [Vec2], center: Vec2, scale: Double, level: Int?) -> Int? {
        guard doc.layouts.indices.contains(li), pts.count >= 3 else { return nil }
        let b = BBox2(points: pts)
        doc.layouts[li].viewports.append(Viewport(origin: b.min, size: Vec2(b.width, b.height), viewCenter: center, scale: scale, level: level))
        let i = doc.layouts[li].viewports.count - 1
        EngineViewports.setClip(&doc, li, i, pts)
        return i
    }

    static func gridKey(_ layout: String) -> String { "SHEETGRID:" + layout.uppercased() }
    static let placeholderKey = "placeholder"
    static func isPlaceholder(_ l: Layout) -> Bool { l.titleBlock[placeholderKey] == "1" }
    static func setPlaceholder(_ doc: inout ArchiDocument, _ i: Int, _ on: Bool) {
        guard doc.layouts.indices.contains(i) else { return }
        doc.layouts[i].titleBlock[placeholderKey] = on ? "1" : nil
    }
    /// Fields shown on a sheet: project fields overridden by the sheet's own, sorted by label.
    static func fields(_ doc: ArchiDocument, layout: Layout) -> [(String, String)] {
        var d: [String: String] = [:]
        for (k, v) in EngineSheets.projectFields(doc) { d[k] = v }
        for (k, v) in layout.titleBlock where k.hasPrefix(EngineSheets.sheetPrefix) { d[String(k.dropFirst(EngineSheets.sheetPrefix.count))] = v }
        return d.keys.sorted().map { ($0, d[$0] ?? "") }
    }

    /// Named page setups of a drawing: "*Model*" and one per sheet that has its own settings.
    static func pageSetups(_ doc: ArchiDocument) -> [(String, EnginePageSetup)] {
        var out: [(String, EnginePageSetup)] = []
        if doc.variables[EnginePageSetup.modelKey] != nil { out.append(("*Model*", EnginePageSetup.load(doc, layoutIndex: nil))) }
        for (i, l) in doc.layouts.enumerated() where doc.variables[EnginePageSetup.key(doc, layoutIndex: i)] != nil {
            out.append((l.name, EnginePageSetup.load(doc, layoutIndex: i)))
        }
        return out
    }

    // MARK: Commands

    static var mviewPoly: CommandDef {
        CommandDef("MVIEWPOLY", aliases: ["MVPOLY", "POLYVIEWPORT"], category: "View", summary: "Creates a polygonal sheet viewport from paper points (x,y in mm) showing the current level.", modifies: true) { ed in
            guard let li = sheetIndex(ed) else { throw CommandError.invalid("Create a sheet first (LAYOUT).") }
            var pts: [Vec2] = []
            while let p = try await ed.getPoint(pts.isEmpty ? "Specify first paper point" : "Specify next paper point (Enter to close)").point { pts.append(p) }
            guard pts.count >= 3 else { throw CommandError.invalid("A polygonal viewport needs at least 3 points.") }
            let ratio = try await ed.getInteger("Scale 1:n <100>", defaultValue: 100) ?? 100
            let bounds = GeometryOps.bounds(of: ed.doc)
            let center = bounds.isEmpty ? Vec2.zero : bounds.center
            let scale = viewportScale(ratio: Double(max(ratio, 1)), units: ed.doc.units)
            let i = addPolygonal(&ed.doc, layoutIndex: li, pts, center: center, scale: scale, level: ed.doc.currentLevel)
            ed.print("Polygonal viewport \((i ?? 0) + 1) at 1:\(ratio).")
        }
    }

    static var mvSetup: CommandDef {
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
            guard !EngineViewports.isLocked(ed.doc, li, b) else { throw CommandError.invalid("Viewport \(b + 1) is locked.") }
            guard align(&ed.doc.layouts[li], base: a, basePoint: pa, other: b, otherPoint: pb, horizontal: k == "Horizontal") else {
                throw CommandError.invalid("Choose two different viewports.")
            }
            ed.print("Viewport \(b + 1) aligned \(k.lowercased())ly with viewport \(a + 1).")
        }
    }

    static var sheetGrid: CommandDef {
        CommandDef("SHEETGRID", aliases: ["LAYOUTGRID", "GUIDEGRID"], category: "Output", summary: "Guide grid on the current sheet (spacing in paper mm, 0 = off); viewports snap to it when moved.", modifies: true) { ed in
            guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
            let name = ed.doc.layouts[li].name
            let cur = EngineViewports.gridSpacing(ed.doc, name)
            guard let v = try await ed.getDistance("Guide grid spacing in paper mm (0 = off)", defaultValue: cur > 0 ? cur : 10).value else { return }
            ed.doc.variables[gridKey(name)] = v > 0 ? fmt(v, 4) : nil
            ed.print(v > 0 ? "Guide grid \(fmt(v, 2)) mm on \(name)." : "Guide grid off.")
        }
    }

    static var sheetPlaceholder: CommandDef {
        CommandDef("SHEETPLACEHOLDER", aliases: ["PLACEHOLDERSHEET"], category: "Output", summary: "Adds a placeholder sheet (listed in the sheet set and index, never plotted) or toggles the current one.", modifies: true) { ed in
            guard let k = try await ed.getKeyword("Enter option [New/Toggle]", ["New", "Toggle"], defaultValue: "New") else { return }
            if k == "Toggle" {
                guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
                let on = !isPlaceholder(ed.doc.layouts[li])
                setPlaceholder(&ed.doc, li, on)
                ed.print("\(ed.doc.layouts[li].name) is \(on ? "a placeholder" : "a real sheet").")
                return
            }
            guard let n = try await ed.getString("Sheet name", defaultValue: "Sheet \(ed.doc.layouts.count + 1)"), !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            ed.doc.layouts.append(Layout(name: n.trimmingCharacters(in: .whitespaces)))
            setPlaceholder(&ed.doc, ed.doc.layouts.count - 1, true)
            ed.print("Placeholder sheet \(n) added.")
        }
    }

    static var sheetField: CommandDef {
        CommandDef("SHEETFIELD", aliases: ["PROJECTFIELD", "CUSTOMFIELD"], category: "Output", summary: "Custom title block fields: Project fields appear on every sheet, Sheet fields override them on one sheet.", modifies: true) { ed in
            guard let k = try await ed.getKeyword("Field scope [Project/Sheet/List]", ["Project", "Sheet", "List"], defaultValue: "Project") else { return }
            if k == "List" {
                for (l, v) in EngineSheets.projectFields(ed.doc) { ed.print("  Project \(l) = \(v)") }
                if let li = sheetIndex(ed) {
                    let name = ed.doc.layouts[li].name
                    for (l, v) in fields(ed.doc, layout: ed.doc.layouts[li]) { ed.print("  \(name): \(l) = \(v)") }
                }
                return
            }
            guard let label = try await word(ed, "Field label (one word, e.g. CLIENTREF)"), !label.isEmpty else { return }
            let value = try await ed.getString("Value for \(label) (empty removes it)", defaultValue: "") ?? ""
            if k == "Project" { EngineSheets.setProjectField(&ed.doc, label, value) }
            else {
                guard let li = sheetIndex(ed) else { throw CommandError.invalid("No sheet.") }
                EngineSheets.setSheetField(&ed.doc, li, label, value)
            }
            ed.print(value.isEmpty ? "Field \(label.uppercased()) removed." : "\(label.uppercased()) = \(value)")
        }
    }

    static var pSetupIn: CommandDef {
        CommandDef("PSETUPIN", category: "Output", summary: "Imports a page setup (plot style, colour mode, lineweights, stamp, paper) from another drawing into the current sheet or all sheets.", modifies: true) { ed in
            var path = try await ed.getString("Drawing file (.archi) (Enter = choose)", defaultValue: "") ?? ""
            path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if path.isEmpty {
                // The shell shows its Open dialog and answers this prompt with the chosen file (Escape cancels).
                try EngineToolCommands.host(ed, "chooseFile", [("purpose", .string("PSETUPIN")), ("title", .string("Import Page Setup")),
                                                               ("extensions", EngineJSON.strings([ArchiFile.fileExtension]))])
                path = (try await ed.getString("Drawing file (.archi)", defaultValue: "") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                if path.isEmpty { return }
            }
            let u = try EngineToolCommands.session(ed).url(path)
            guard let data = try? Data(contentsOf: u), let src = try? ArchiFile.decode(data) else { throw CommandError.invalid("Cannot read \(path).") }
            let setups = pageSetups(src)
            guard !setups.isEmpty else { throw CommandError.invalid("That drawing has no page setups.") }
            for (i, s) in setups.enumerated() { ed.print("  \(i + 1). \(s.0)") }
            guard let n = try await ed.getInteger("Page setup number", defaultValue: 1), setups.indices.contains(n - 1) else { return }
            let (name, ps) = setups[n - 1]
            let scope = try await ed.getKeyword("Apply to [Current/All/Model]", ["Current", "All", "Model"], defaultValue: "Current") ?? "Current"
            var targets: [Int?] = []
            if scope == "Model" { targets = [nil] }
            else if scope == "All" { targets = ed.doc.layouts.indices.map { Optional($0) } }
            else if let li = sheetIndex(ed) { targets = [li] }
            let paper = src.layouts.first { $0.name == name }?.paper
            for li in targets {
                ps.store(in: &ed.doc, layoutIndex: li)
                if let li, let paper, ed.doc.layouts.indices.contains(li) { ed.doc.layouts[li].paper = paper }
            }
            ed.print("Page setup \(name) applied to \(targets.count) \(scope == "Model" ? "model space" : "sheet(s)").")
        }
    }

    static var layoutTabs: CommandDef {
        CommandDef("LAYOUTTABS", aliases: ["LAYOUTTAB", "MODELTAB"], category: "View", summary: "Shows or hides the Model / layout tabs under the drawing area.", modifies: false) { ed in
            guard let k = try await onOff(ed, "Model/layout tabs") else { return }
            let on: EngineJSON = k == "ON" ? .bool(true) : (k == "OFF" ? .bool(false) : .null)
            try EngineToolCommands.host(ed, "layoutTabs", [("on", on)])
        }
    }

    static var sheetRenumber: CommandDef {
        CommandDef("SHEETRENUMBER", aliases: ["RENUMBERSHEETS"], category: "Output", summary: "Numbers all sheets in order with a prefix and start number (e.g. A- 101).") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
            let prefix = try await ed.getString("Enter number prefix <A->", defaultValue: "A-") ?? "A-"
            guard let start = try await ed.getInteger("Enter first number <101>", defaultValue: 101) else { return }
            EngineSheets.renumber(&ed.doc, prefix: prefix, start: start)
            EngineSheets.refreshIndexes(&ed.doc)
            ed.print("\(ed.doc.layouts.count) sheet(s) numbered \(EngineSheets.number(ed.doc, 0))…")
        }
    }

    static var sheetViewTitles: CommandDef {
        CommandDef("SHEETVIEWTITLES", aliases: ["VPTITLES", "EDITABLEVIEWTITLES"], category: "Output", summary: "Editable view titles (number bubble, title, scale) under every viewport of the active sheet; keeps edited titles.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
            let i = EngineToolCommands.activeSheet(ed)
            EngineSheets.refreshViewTitles(&ed.doc, i)
            ed.print("\(ed.doc.layouts[i].viewports.count) view title(s) on \(ed.doc.layouts[i].name).")
        }
    }

    static var sheetImage: CommandDef {
        CommandDef("SHEETIMAGE", aliases: ["LAYOUTIMAGE", "SHEETPNG"], category: "Output", summary: "Exports a sheet (layout) or the Model view of the current level as a PNG, JPEG or TIFF image at a chosen resolution (dpi).", modifies: false) { ed in
            let s = try EngineToolCommands.session(ed)
            let names = ed.doc.layouts.map(\.name)
            let cur = s.activeSheetIndex.map { names[$0] } ?? "Model"
            let n = try await ed.getString("Sheet [\((names + ["Model"]).joined(separator: "/"))]", defaultValue: cur) ?? cur
            let li = names.firstIndex { $0.caseInsensitiveCompare(n) == .orderedSame }
            guard li != nil || n.caseInsensitiveCompare("Model") == .orderedSame else { throw CommandError.invalid("Unknown sheet \(n).") }
            let dpi = try await ed.getInteger("Resolution in dpi", defaultValue: 150) ?? 150
            guard (36...1200).contains(dpi) else { throw CommandError.invalid("Resolution must be 36–1200 dpi.") }
            let fk = try await ed.getKeyword("Format [Png/Jpeg/Tiff]", ["Png", "Jpeg", "Tiff"], defaultValue: "Png") ?? "Png"
            let ext = EngineSheetImage.ext(fk)
            let title = li.map { names[$0] } ?? "Model"
            let typed = (try await ed.getString("File name (Enter = choose)", defaultValue: "") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            var path: String? = nil
            if !typed.isEmpty {
                var u = s.url(typed)
                if u.pathExtension.isEmpty { u.appendPathExtension(ext) }
                path = u.path
            }
            if let p = path, fk != "Jpeg" {
                var o = EngineObject()
                o.set("layout", li.map { EngineJSON.int($0) } ?? .string("Model"))
                o.set("dpi", dpi)
                o.set("format", fk.lowercased())
                o.set("path", p)
                _ = try s.sheetImage(o.json)
                return
            }
            // Save dialog (and JPEG encoding) in the shell, which then calls sheet.image.
            let base = title == "Model" ? (s.editor.fileURL?.deletingPathExtension().lastPathComponent ?? ed.doc.info.name) : title
            try EngineToolCommands.host(ed, "sheetImage", [("layout", li.map { EngineJSON.int($0) } ?? .string("Model")), ("dpi", .int(dpi)),
                                                           ("format", .string(fk.lowercased())), ("path", path.map { EngineJSON.string($0) } ?? .null),
                                                           ("suggested", .string((base.isEmpty ? "Drawing" : base) + "." + ext))])
        }
    }

    static var titleBlockDesign: CommandDef {
        CommandDef("TITLEBLOCKDESIGN", aliases: ["TBDESIGN", "CUSTOMTITLEBLOCK", "TITLEBLOCKBLOCK"], category: "Output", summary: "Custom title blocks: Create a starter block (edit it with BEDIT: lines, logo images, {field} texts or attributes), Use a block on all or the current sheet, or go back to the Builtin one.") { ed in
            let k = try await ed.getKeyword("Title block [Create/Use/Builtin/Fields]", ["Create", "Use", "Builtin", "Fields"], defaultValue: "Create") ?? "Create"
            let variable = EngineCustomTitleBlock.variable
            switch k {
            case "Fields":
                ed.print("Fields: " + EngineSheetCommands.titleFieldNames.map { "{" + $0 + "}" }.joined(separator: " ") + " and custom fields (SHEETFIELD). Attribute tags with these names work too.")
            case "Builtin":
                for key in ed.doc.variables.keys where key.hasPrefix(variable) { ed.doc.variables[key] = nil }
                ed.print("Built-in title block on all sheets.")
            case "Create":
                let starter = EngineSheetCommands.starterName
                if ed.doc.blocks[starter] == nil { ed.doc.blocks[starter] = EngineSheetCommands.starterBlock() }
                ed.doc.setVariable(variable, starter)
                ed.print("Block \(starter) is the title block of all sheets. Edit it with BEDIT \(starter).")
            default:
                guard let n = try await word(ed, "Block name"), let name = ed.doc.blocks.keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else {
                    throw CommandError.invalid("No such block.")
                }
                let scope = try await ed.getKeyword("Apply to [All/Current]", ["All", "Current"], defaultValue: "All") ?? "All"
                if scope == "Current", let li = sheetIndex(ed) {
                    ed.doc.setVariable(variable + ":" + ed.doc.layouts[li].name.uppercased(), name)
                    ed.print("\(name) is the title block of \(ed.doc.layouts[li].name).")
                } else {
                    ed.doc.setVariable(variable, name)
                    ed.print("\(name) is the title block of all sheets.")
                }
            }
        }
    }

    static let starterName = "TB-CUSTOM"
    static let titleFieldNames = ["project", "sheetName", "sheetNumber", "scale", "date", "revision", "client", "author", "number", "paper", "address"]

    /// A starter block like the built-in title block, with placeholders, drawn left of and above its base point.
    static func starterBlock() -> Block {
        func line(_ a: Vec2, _ b: Vec2) -> Entity { Entity(layer: "0", geometry: .line(LineGeom(a, b))) }
        func text(_ p: Vec2, _ h: Double, _ s: String) -> Entity { Entity(layer: "0", geometry: .text(TextGeom(position: p, height: h, content: s))) }
        let w = 180.0, h = 42.0
        var es: [Entity] = [line(Vec2(-w, 0), Vec2(0, 0)), line(Vec2(0, 0), Vec2(0, h)), line(Vec2(0, h), Vec2(-w, h)), line(Vec2(-w, h), Vec2(-w, 0))]
        es += [line(Vec2(-w, 28), Vec2(0, 28)), line(Vec2(-w, 14), Vec2(0, 14)), line(Vec2(-90, 0), Vec2(-90, 28))]
        es += [text(Vec2(-w + 3, 32), 5, "{project}"), text(Vec2(-w + 3, 18), 2.5, "{sheetName}"), text(Vec2(-87, 18), 2.5, "Scale {scale}")]
        es += [text(Vec2(-w + 3, 4), 2.5, "{client}  ·  {date}"), text(Vec2(-87, 4), 4, "{sheetNumber}  rev {revision}")]
        return Block(name: starterName, basePoint: .zero, entities: es, description: "Custom title block (edit with BEDIT)")
    }

    // MARK: ZOOM nXP (PaperZoom)

    /// "1/100XP", "0.01xp", "1:100", "1/50" → paper/model factor (0.01).
    static func paperFactor(_ s0: String) -> Double? {
        var s = s0.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("xp") { s.removeLast(2) } else if s.hasSuffix("x") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        var v: Double?
        for sep in [":", "/"] where s.contains(sep) {
            let p = s.split(separator: Character(sep)).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count == 2, let a = p[0], let b = p[1], b != 0 { v = a / b }
            break
        }
        if v == nil, !s.contains(":"), !s.contains("/") { v = Double(s) }
        guard let f = v, f.isFinite, f > 0, f <= 1000 else { return nil }
        return f
    }

    /// CSS pixels per millimetre of a Windows display at 100 % (96 dpi logical).
    static let screenPixelsPerMM = 96.0 / 25.4

    @MainActor static func paperZoom(_ ed: Editor, _ s: String) throws {
        guard let f = paperFactor(s) else { throw CommandError.invalid("Enter a scale such as 1/100XP, 0.01XP or 1:100.") }
        let ppu = screenPixelsPerMM * ed.doc.units.mm * f
        let ratio = 1 / f
        try EngineToolCommands.host(ed, "paperZoom", [("factor", .number(f)), ("ratio", .number(ratio)), ("ratioText", .string(fmt(ratio, 2))),
                                                      ("pixelsPerUnit", .number(ppu)), ("viewportScale", .number(ratio / ed.doc.units.mm))])
    }

    static var zoomXP: CommandDef {
        CommandDef("ZOOMXP", aliases: ["ZXP", "ZOOMPAPER", "ZOOMSCALEXP"], category: "View", summary: "ZOOM nXP: in a sheet sets the selected viewport to 1:n (1/100XP); on the plan shows the drawing at that paper scale at true size on the screen.", modifies: false) { ed in
            guard let s = try await ed.getString("Enter scale relative to paper space (nXP, e.g. 1/100XP or 1:50) <1/100XP>", defaultValue: "1/100XP") else { return }
            try paperZoom(ed, s)
        }
    }
}

extension EngineSession {
    /// Registers the portable sheet, recovery and versions commands and the ZOOM nXP hook (archi-engine only).
    public static func registerSheetCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineSheetCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        for c in EngineRecovery.commands where registry.lookup(c.name) == nil { registry.register(c) }
        ZoomHooks.paperZoom = { ed, s in
            guard EngineSheetCommands.paperFactor(s) != nil, ed.host is EngineHostBridge else { return false }
            try EngineSheetCommands.paperZoom(ed, s)
            return true
        }
    }

    func callSheets(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "ribbon.context": return ribbonContext(p)
        case "sheet.image": return try sheetImage(p)
        default: return try await callRecovery(method, p)
        }
    }
}
