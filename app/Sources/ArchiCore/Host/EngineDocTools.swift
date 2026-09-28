// Oanarina Archi Tool — GPL-3.0-or-later
// Document tools of the Windows shell (docs/ENGINE-PROTOCOL.md "Schedules, browser, text and selection tools"): the
// data behind the Mac Schedule sheet (MainWindow.swift ScheduleSheet), Project Browser (PanelsView.swift
// ProjectBrowserPanel, ProjectBrowserActions.swift), Selection panel (StudioPanels.swift SelectionInfo), Inspector
// (AppNavigation.swift ObjectInspector), History panel steps (MaterialHistoryPanels.swift HistoryPanel), Spelling
// dialog (OutputDialogs.swift SpellingSheet) and Text Styles dialog (AppRound12Panels.swift TextStylesPanel, TextStyleForm).
// Same values, validation and undo labels as the Mac; the Windows spell checker (Chromium / Windows) runs in the shell.
import Foundation

public enum EngineDocMethods {
    public static let all = [
        "schedule.get", "selection.info", "inspect.get", "browser.get", "browser.openView", "history.goto",
        "spell.words", "spell.replace", "spell.add", "textstyle.list", "textstyle.apply", "textstyle.current",
    ]
}

/// Selection summary (SelectionInfo.summarize on the Mac).
enum EngineSelectionInfo {
    struct Row { var type: String; var ids: [EntityID] }
    static func summarize(_ doc: ArchiDocument, _ ids: Set<EntityID>) -> (rows: [Row], layers: [String: Int], length: Double, area: Double, bounds: BBox2) {
        var byType: [String: [EntityID]] = [:], layers: [String: Int] = [:]
        var length = 0.0, area = 0.0
        var b = BBox2.empty
        for e in doc.entities where ids.contains(e.id) {
            byType[e.typeName, default: []].append(e.id)
            layers[e.layer, default: 0] += 1
            length += GeometryOps.length(e.geometry, doc: doc)
            area += GeometryOps.area(e.geometry, doc: doc) ?? 0
            b.add(GeometryOps.bounds(e.geometry, doc: doc))
        }
        for el in doc.elements where ids.contains(el.id) {
            byType[el.typeName, default: []].append(el.id)
            layers[el.layer, default: 0] += 1
            for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) }
        }
        var rows = byType.map { Row(type: $0.key, ids: $0.value.sorted()) }
        rows.sort { a, c in a.ids.count != c.ids.count ? a.ids.count > c.ids.count : a.type < c.type }
        return (rows, layers, length, area, b)
    }
}

/// Every stored value of an object (ObjectInspector on the Mac).
enum EngineInspector {
    static func report(_ id: EntityID, doc: ArchiDocument) -> [(String, String)] {
        var out: [(String, String)] = [("ID", "#\(id)")]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let e = doc.entity(id) {
            out.append(("GUID", IFCExporter.guid("entity:\(id)")))
            out.append(("Type", e.typeName))
            out.append(("Layer", e.layer))
            out.append(("Color", e.color.text))
            out.append(("Linetype", e.linetype ?? "ByLayer"))
            out.append(("Lineweight", e.lineweight.map { fmt($0) + " mm" } ?? "ByLayer"))
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            if !b.isEmpty {
                let lo = "(" + fmt(b.min.x, 2) + ", " + fmt(b.min.y, 2) + ")"
                let hi = "(" + fmt(b.max.x, 2) + ", " + fmt(b.max.y, 2) + ")"
                out.append(("Extents", lo + " – " + hi))
            }
            for (k, v) in e.props.sorted(by: { $0.key < $1.key }) { out.append(("prop." + k, v)) }
            if let d = try? enc.encode(e.geometry), let s = String(data: d, encoding: .utf8) { out.append(("Geometry", s)) }
        } else if let el = doc.element(id) {
            let stored = el.props["ifcGuid"].flatMap { IFCExporter.isValidGuid($0) ? $0 : nil }
            out.append(("GUID", stored ?? IFCExporter.guid("element:\(id)")))
            out.append(("Type", el.typeName))
            out.append(("Name", el.name))
            out.append(("Level", doc.level(el.level)?.name ?? "\(el.level)"))
            out.append(("Layer", el.layer))
            out.append(("Material", el.material ?? "—"))
            for (k, v) in el.props.sorted(by: { $0.key < $1.key }) { out.append(("prop." + k, v)) }
            if let d = try? enc.encode(el.geometry), let s = String(data: d, encoding: .utf8) { out.append(("Geometry", s)) }
        } else { return [] }
        return out
    }

    static func text(_ id: EntityID, doc: ArchiDocument) -> String {
        report(id, doc: doc).map { $0.0 + ": " + $0.1 }.joined(separator: "\n")
    }
}

/// Text Styles dialog form (TextStyleForm on the Mac): validation and apply.
struct EngineTextStyleForm {
    var name: String
    var font: String
    var height: String
    var widthFactor: String
    var obliqueDegrees: String

    static func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }

    var errors: [String] {
        var e: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { e.append("name") }
        if (EngineTextStyleForm.num(height) ?? -1) < 0 { e.append("height ≥ 0") }
        let wf = EngineTextStyleForm.num(widthFactor) ?? 0
        if !(wf >= 0.01 && wf <= 100) { e.append("width factor 0.01–100") }
        if abs(EngineTextStyleForm.num(obliqueDegrees) ?? 999) > 85 { e.append("oblique −85…85°") }
        return e
    }

    var style: TextStyle? {
        guard errors.isEmpty else { return nil }
        let ob = (EngineTextStyleForm.num(obliqueDegrees) ?? 0) * Double.pi / 180
        return TextStyle(name: name.trimmingCharacters(in: .whitespaces), font: font, height: EngineTextStyleForm.num(height) ?? 0,
                         widthFactor: EngineTextStyleForm.num(widthFactor) ?? 1, oblique: ob)
    }

    /// Replaces the style `original` (or adds a new one); text using the old name follows a rename.
    func apply(original: String?, to doc: inout ArchiDocument) -> Bool {
        guard let s = style else { return false }
        if let o = original, let i = doc.textStyles.firstIndex(where: { $0.name == o }) {
            if doc.textStyles.contains(where: { $0.name.caseInsensitiveCompare(s.name) == .orderedSame && $0.name != o }) { return false }
            doc.textStyles[i] = s
            if o != s.name {
                for k in doc.entities.indices {
                    if case .text(var t) = doc.entities[k].geometry, t.style == o {
                        t.style = s.name
                        doc.entities[k].geometry = .text(t)
                    }
                }
            }
        } else {
            guard !doc.textStyles.contains(where: { $0.name.caseInsensitiveCompare(s.name) == .orderedSame }) else { return false }
            doc.textStyles.append(s)
        }
        return true
    }

    /// Fonts offered by the Mac dialog (the shell adds the installed Windows fonts).
    static let fonts = ["Helvetica", "Helvetica Neue", "Arial", "Arial Narrow", "Avenir Next", "Futura", "Gill Sans", "Menlo", "Times New Roman", "Georgia",
                        TextStyleFonts.strokeFontName, "romans.shx", "simplex.shx", "isocp.shx"]
}

@MainActor
extension EngineSession {
    func callDocTools(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "schedule.get": return scheduleGet(p)
        case "selection.info": return selectionInfo()
        case "inspect.get": return try inspectGet(p)
        case "browser.get": return browserGet()
        case "browser.openView": return try browserOpenView(p)
        case "history.goto": return try await historyGoto(p)
        case "spell.words": return spellWords(p)
        case "spell.replace": return try spellReplace(p)
        case "spell.add": return try spellAdd(p)
        case "textstyle.list": return textStyleList()
        case "textstyle.apply": return try textStyleApply(p)
        case "textstyle.current": return try textStyleCurrent(p)
        default: return nil
        }
    }

    // MARK: Schedules

    /// Rows of a schedule (header first) as the Schedule sheet shows them.
    func scheduleGet(_ p: EngineJSON) -> EngineJSON {
        let kind = (p["kind"]?.stringValue ?? "all").lowercased()
        let rows = ScheduleExporter.table(doc: editor.doc, kind: kind).filter { !$0.allSatisfy { $0.isEmpty } }
        var o = EngineObject()
        o.set("kind", kind)
        o.set("kinds", EngineJSON.strings(ScheduleExporter.kinds))
        o.set("rows", EngineJSON.array(rows.map { EngineJSON.strings($0) }))
        o.set("count", max(0, rows.count - 1))
        return o.json
    }

    // MARK: Selection and inspector

    func selectionInfo() -> EngineJSON {
        let doc = editor.doc
        let s = EngineSelectionInfo.summarize(doc, editor.selection)
        var rows: [EngineJSON] = []
        var total = 0
        for r in s.rows {
            var ro = EngineObject()
            ro.set("type", r.type)
            ro.set("count", r.ids.count)
            ro.set("ids", EngineJSON.ints(r.ids))
            rows.append(ro.json)
            total += r.ids.count
        }
        var layers: [EngineJSON] = []
        for (k, v) in s.layers.sorted(by: { $0.key < $1.key }) {
            var lo = EngineObject()
            lo.set("name", k)
            lo.set("count", v)
            layers.append(lo.json)
        }
        var o = EngineObject()
        o.set("total", total)
        o.set("rows", EngineJSON.array(rows))
        o.set("layers", EngineJSON.array(layers))
        o.set("length", s.length)
        o.set("area", s.area)
        o.set("lengthText", fmt(s.length, 2))
        o.set("areaText", fmt(s.area, 2))
        o.set("bounds", s.bounds.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(s.bounds))
        return o.json
    }

    func inspectGet(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        var ids = editor.selection.sorted()
        if let a = p["ids"]?.arrayValue { ids = a.compactMap(\.intValue) }
        let limit = max(1, min(p["limit"]?.intValue ?? 20, 200))
        var objs: [EngineJSON] = []
        for id in ids.prefix(limit) {
            let rep = EngineInspector.report(id, doc: doc)
            if rep.isEmpty { continue }
            var oo = EngineObject()
            oo.set("id", id)
            oo.set("rows", EngineJSON.array(rep.map { EngineJSON.strings([$0.0, $0.1]) }))
            oo.set("text", EngineInspector.text(id, doc: doc))
            objs.append(oo.json)
        }
        var o = EngineObject()
        o.set("objects", EngineJSON.array(objs))
        o.set("count", ids.count)
        o.set("more", max(0, ids.count - limit))
        return o.json
    }

    // MARK: Project Browser

    func browserGet() -> EngineJSON {
        let doc = editor.doc
        var levels: [EngineJSON] = []
        for l in doc.levels.sorted(by: { $0.elevation > $1.elevation }) {
            var lo = EngineObject()
            lo.set("id", l.id)
            lo.set("name", l.name)
            lo.set("elevation", l.elevation)
            lo.set("current", l.id == doc.currentLevel)
            levels.append(lo.json)
        }
        var named: [EngineJSON] = []
        for v in doc.namedViews where doc.view(named: v.name) == nil {
            var no = EngineObject()
            no.set("name", v.name)
            no.set("camera", v.camera != nil)
            if let c = v.camera { no.set("cameraData", EngineSession.cameraJSON(v.name, c)) }
            no.set("center", EngineJSON.point(v.center))
            no.set("height", v.height)
            named.append(no.json)
        }
        let current = doc.variable(ProjectViews.currentKey)
        var views: [EngineJSON] = []
        for v in doc.views {
            var vo = EngineObject()
            vo.set("name", v.name)
            vo.set("label", v.parent.map { v.name + " (dependent on " + $0 + ")" } ?? v.name)
            vo.set("kind", v.kind)
            let symbol: String
            switch v.kind {
            case "3d": symbol = v.camera?.orthographic == false ? "camera" : "cube"
            case "ceiling": symbol = "square.3.layers.3d.top.filled"
            default: symbol = "square.split.bottomrightquarter"
            }
            vo.set("symbol", symbol)
            vo.set("current", current == v.name)
            views.append(vo.json)
        }
        var sheets: [EngineJSON] = []
        for (i, l) in doc.layouts.enumerated() {
            var so = EngineObject()
            so.set("index", i)
            so.set("name", l.name)
            sheets.append(so.json)
        }
        var families: [EngineJSON] = []
        for f in doc.families {
            var fo = EngineObject()
            fo.set("name", f.name)
            fo.set("category", f.category)
            families.append(fo.json)
        }
        var groups: [EngineJSON] = []
        for g in doc.modelGroups {
            var go = EngineObject()
            go.set("name", g.name)
            go.set("elements", g.elements.count)
            groups.append(go.json)
        }
        var links: [EngineJSON] = []
        for x in Xrefs.all(doc) {
            var xo = EngineObject()
            xo.set("name", x.name)
            xo.set("path", x.path)
            xo.set("overlay", x.overlay)
            xo.set("loaded", x.loaded)
            links.append(xo.json)
        }
        var o = EngineObject()
        o.set("levels", EngineJSON.array(levels))
        o.set("currentLevel", doc.currentLevel)
        o.set("views3d", EngineJSON.strings(["Iso", "Top", "Front", "Right", "Back", "Left"]))
        o.set("namedViews", EngineJSON.array(named))
        o.set("projectViews", EngineJSON.array(views))
        o.set("currentView", EngineJSON.optString(current))
        var elev: [EngineJSON] = []
        let elevations: [(String, String, String, String)] = [
            ("elevationNorth", "North Elevation", "back", "building"), ("elevationSouth", "South Elevation", "front", "building"),
            ("elevationEast", "East Elevation", "right", "building"), ("elevationWest", "West Elevation", "left", "building"),
            ("section", "Section A-A", "front", "square.split.diagonal"),
        ]
        for (k, title, dir, sym) in elevations {
            var eo = EngineObject()
            eo.set("kind", k)
            eo.set("title", title)
            eo.set("view", dir)
            eo.set("symbol", sym)
            elev.append(eo.json)
        }
        o.set("elevations", EngineJSON.array(elev))
        o.set("sheets", EngineJSON.array(sheets))
        o.set("schedules", EngineJSON.strings(ScheduleExporter.kinds))
        o.set("families", EngineJSON.array(families))
        o.set("groups", EngineJSON.array(groups))
        o.set("links", EngineJSON.array(links))
        return o.json
    }

    /// ProjectBrowser.openView: applies the view's settings and level ("Open View"); plans return their crop to zoom to,
    /// 3D views their camera.
    func browserOpenView(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard let v = editor.doc.view(named: name) else { throw EngineError.failed("No project view named \"" + name + "\".") }
        editor.transaction("Open View") { _ = ProjectViews.open(v.name, doc: &$0) }
        var o = EngineObject()
        o.set("name", v.name)
        o.set("kind", v.kind)
        o.set("level", editor.doc.currentLevel)
        if v.kind == "3d" {
            o.set("camera", v.camera.map { EngineSession.cameraJSON(v.name, $0) } ?? .null)
        } else if let c = ProjectViews.effectiveCrop(v, doc: editor.doc) {
            let pad = 500 / max(editor.doc.units.mm, 1e-9)
            o.set("crop", EngineDrawJSON.rect(BBox2(points: c).expanded(by: pad)))
        }
        return o.json
    }

    // MARK: History

    /// HistoryPanel.goTo: step `index` (0 = the opened document) — undoes or redoes the steps in between.
    func historyGoto(_ p: EngineJSON) async throws -> EngineJSON {
        guard let index = p["index"]?.intValue, index >= 0 else { throw EngineError.params("missing 'index'") }
        guard editor.isIdle else { throw EngineError.failed("Finish the current command first.") }
        let current = editor.history.undoStack.count
        if index < current { for _ in 0..<(current - index) { editor.undo() } }
        else if index > current { for _ in 0..<(index - current) { editor.redo() } }
        return panelHistory(.object([]))
    }

    // MARK: Spelling

    /// Every word of text, leaders, tables, dimension overrides and attributes (the selection, or all) with the
    /// drawing dictionary; the shell asks the Windows spell checker which ones are misspelled.
    func spellWords(_ p: EngineJSON) -> EngineJSON {
        var ids: Set<EntityID>? = editor.selection.isEmpty ? nil : editor.selection
        if let a = p["ids"]?.arrayValue { ids = Set(a.compactMap(\.intValue)) }
        if p["all"]?.boolValue == true { ids = nil }
        var words: [EngineJSON] = []
        for w in SpellCheck.words(editor.doc, ids: ids) {
            var wo = EngineObject()
            wo.set("entity", w.entity)
            wo.set("word", w.word)
            wo.set("field", w.field)
            words.append(wo.json)
        }
        var o = EngineObject()
        o.set("words", EngineJSON.array(words))
        o.set("custom", EngineJSON.strings(SpellCheck.customWords(editor.doc).sorted()))
        o.set("scope", ids == nil ? "all" : "selection")
        return o.json
    }

    /// Change / Change All ("Spelling", one undo step).
    func spellReplace(_ p: EngineJSON) throws -> EngineJSON {
        let word = try string(p, "word")
        let rep = try string(p, "replacement")
        let ids = (p["ids"]?.arrayValue ?? []).compactMap(\.intValue)
        guard !rep.isEmpty, rep != word else { throw EngineError.params("replacement must differ from the word") }
        var n = 0
        editor.transaction("Spelling") { d in
            for id in Set(ids) { if SpellCheck.replace(word, with: rep, in: id, doc: &d) { n += 1 } }
        }
        var o = EngineObject()
        o.set("changed", n)
        return o.json
    }

    func spellAdd(_ p: EngineJSON) throws -> EngineJSON {
        let word = try string(p, "word")
        editor.transaction("Add to Dictionary") { SpellCheck.addWord(word, &$0) }
        var o = EngineObject()
        o.set("custom", EngineJSON.strings(SpellCheck.customWords(editor.doc).sorted()))
        return o.json
    }

    // MARK: Text styles

    func textStyleList() -> EngineJSON {
        let doc = editor.doc
        var uses: [String: Int] = [:]
        for e in doc.entities { if case .text(let t) = e.geometry { uses[t.style, default: 0] += 1 } }
        var styles: [EngineJSON] = []
        for s in doc.textStyles {
            var so = EngineObject()
            so.set("name", s.name)
            so.set("font", s.font)
            so.set("height", fmt(s.height, 4))
            so.set("widthFactor", fmt(TextStyleFonts.widthFactor(s), 3))
            so.set("obliqueDegrees", fmt(TextStyleFonts.obliqueRadians(s) * 180 / Double.pi, 2))
            so.set("strokeFont", TextStyleFonts.isStrokeFont(s.font))
            so.set("uses", uses[s.name] ?? 0)
            styles.append(so.json)
        }
        var i = 1
        while doc.textStyles.contains(where: { $0.name == "Style \(i)" }) { i += 1 }
        var o = EngineObject()
        o.set("styles", EngineJSON.array(styles))
        o.set("current", doc.variable("TEXTSTYLE") ?? doc.textStyles.first?.name ?? "Standard")
        o.set("fonts", EngineJSON.strings(EngineTextStyleForm.fonts))
        o.set("newName", "Style \(i)")
        return o.json
    }

    /// Apply in the Text Styles dialog ("Text Style"): validation errors or the saved style.
    func textStyleApply(_ p: EngineJSON) throws -> EngineJSON {
        let form = EngineTextStyleForm(name: p["name"]?.stringValue ?? "", font: p["font"]?.stringValue ?? "Helvetica",
                                       height: p["height"]?.stringValue ?? "0", widthFactor: p["widthFactor"]?.stringValue ?? "1",
                                       obliqueDegrees: p["obliqueDegrees"]?.stringValue ?? "0")
        var o = EngineObject()
        let errs = form.errors
        if !errs.isEmpty {
            o.set("ok", false)
            o.set("message", "Check: " + errs.joined(separator: ", "))
            return o.json
        }
        let orig = p["original"]?.stringValue
        var ok = false
        var probe = editor.doc
        ok = form.apply(original: orig, to: &probe)
        if ok { editor.transaction("Text Style") { d in _ = form.apply(original: orig, to: &d) } }
        let saved = form.name.trimmingCharacters(in: .whitespaces)
        o.set("ok", ok)
        o.set("name", saved)
        o.set("message", ok ? "Saved " + saved + "." : "A style with that name exists.")
        return o.json
    }

    func textStyleCurrent(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard editor.doc.textStyles.contains(where: { $0.name == name }) else { throw EngineError.failed("No text style named \"" + name + "\".") }
        editor.transaction("Current text style") { $0.setVariable("TEXTSTYLE", name) }
        var o = EngineObject()
        o.set("current", name)
        o.set("message", name + " is current.")
        return o.json
    }
}
