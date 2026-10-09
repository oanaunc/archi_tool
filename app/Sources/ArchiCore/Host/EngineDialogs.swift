// Oanarina Archi Tool — GPL-3.0-or-later
// Data and edits behind the Windows shell's dialogs, portable versions of the Mac sheets that edit the drawing:
// Drawing Units (UnitsSheet), Drafting Settings (DraftingSettingsSheet, Settings ▸ Drafting "Apply to Open Drawings"),
// Quick Select (QuickSelectSheet), Layer States Manager (LayerStatesSheet), Layers panel filters and layer tree,
// Page Setup (PageSetupSheet) and drawing templates (TemplateLibrary). Same labels, defaults, validation and undo
// steps as the Mac sheets (ArchiApp/MainWindow.swift, Dialogs.swift, PanelsView.swift, PlotExtras.swift, AppFeatures.swift).
import Foundation

public enum EngineDialogMethods {
    /// Protocol methods answered by `EngineSession.dialogCall` (listed in engine.hello "methods").
    public static let all: [String] = [
        "units.get", "units.set", "drafting.get", "drafting.set", "drafting.defaults",
        "qselect.options", "qselect.run",
        "layerstate.list", "layerstate.save", "layerstate.restore", "layerstate.delete", "layerstate.rename",
        "layerfilter.list", "layerfilter.save", "layerfilter.delete", "layers.group",
        "pagesetup.get", "pagesetup.set",
        "pagepresets.list", "pagepresets.apply", "pagepresets.delete", "pagepresets.import",
        "templates.list", "templates.new", "templates.save",
        "ui.prefs",
    ]
}

extension EngineSession {
    /// Runs one of `EngineDialogMethods.all`.
    func dialogCall(_ method: String, _ p: EngineJSON) async throws -> EngineJSON {
        switch method {
        case "units.get": return unitsGet(p)
        case "units.set": return try unitsSet(p)
        case "drafting.get": return draftingGet()
        case "drafting.set": return try draftingSet(p)
        case "drafting.defaults": return try draftingDefaults(p)
        case "qselect.options": return qselectOptions(p)
        case "qselect.run": return try qselectRun(p)
        case "layerstate.list": return layerStateList()
        case "layerstate.save": return try layerStateSave(p)
        case "layerstate.restore": return try layerStateRestore(p)
        case "layerstate.delete": return try layerStateDelete(p)
        case "layerstate.rename": return try layerStateRename(p)
        case "layerfilter.list": return layerFilterList()
        case "layerfilter.save": return try layerFilterSave(p)
        case "layerfilter.delete": return try layerFilterDelete(p)
        case "layers.group": return try layerGroupSet(p)
        case "pagesetup.get": return pageSetupGet(p)
        case "pagesetup.set": return try pageSetupSet(p)
        case "pagepresets.list": return pagePresetList()
        case "pagepresets.apply", "pagepresets.delete", "pagepresets.import": return try pagePresetEdit(method, p)
        case "templates.list": return templatesList(p)
        case "templates.new": return try await templatesNew(p)
        case "templates.save": return try templatesSave(p)
        case "ui.prefs": return uiPrefs(p)
        default: throw EngineError(EngineError.methodNotFound, "Method not found: " + method)
        }
    }

    // MARK: Drawing Units (UnitsSheet)

    static func unitTitle(_ u: Units) -> String { u.rawValue.capitalized + " (" + u.abbreviation + ")" }

    /// Current units; `units`, `lunits`, `luprec`, `aunits`, `auprec` in the params preview other values (sample text).
    func unitsGet(_ p: EngineJSON) -> EngineJSON {
        let d = editor.doc
        let units = p["units"]?.stringValue.flatMap { Units(rawValue: $0) } ?? d.units
        let lin = p["lunits"]?.intValue.flatMap { UnitFormat.Linear(rawValue: $0) } ?? UnitFormat.linearType(d)
        let ang = p["aunits"]?.intValue.flatMap { UnitFormat.Angular(rawValue: $0) } ?? UnitFormat.angularType(d)
        let lprec = min(max(p["luprec"]?.intValue ?? UnitFormat.linearPrecision(d), 0), 8)
        let aprec = min(max(p["auprec"]?.intValue ?? UnitFormat.angularPrecision(d), 0), 8)
        var o = EngineObject()
        o.set("units", units.rawValue)
        o.set("lunits", lin.rawValue)
        o.set("luprec", lprec)
        o.set("aunits", ang.rawValue)
        o.set("auprec", aprec)
        var ul: [EngineJSON] = []
        for u in Units.allCases {
            var uo = EngineObject()
            uo.set("value", u.rawValue)
            uo.set("title", EngineSession.unitTitle(u))
            uo.set("abbreviation", u.abbreviation)
            uo.set("mm", u.mm)
            ul.append(uo.json)
        }
        o.set("unitList", EngineJSON.array(ul))
        var lt: [EngineJSON] = []
        for t in UnitFormat.Linear.allCases { lt.append(.object([EngineJSONField("value", .int(t.rawValue)), EngineJSONField("title", .string(t.title))])) }
        o.set("linearTypes", EngineJSON.array(lt))
        var at: [EngineJSON] = []
        for t in UnitFormat.Angular.allCases { at.append(.object([EngineJSONField("value", .int(t.rawValue)), EngineJSONField("title", .string(t.title))])) }
        o.set("angularTypes", EngineJSON.array(at))
        let fractional = lin == .architectural || lin == .fractional
        let lprecText = fractional ? "1/" + String(1 << lprec) + "\"" : String(lprec) + " decimals"
        o.set("linearPrecisionLabel", "Precision: " + lprecText)
        o.set("angularPrecisionLabel", "Precision: " + String(aprec))
        let sampleLength = UnitFormat.linear(42.5 / UnitFormat.inchesPerUnit(units), units: units, type: lin, precision: lprec)
        let sampleAngle = UnitFormat.angle(0.7854, type: ang, precision: aprec)
        o.set("sample", "Sample: " + sampleLength + "  ·  " + sampleAngle)
        var note = "Coordinates are stored as drawing units. Changing the unit relabels the drawing and affects exports (1 "
        note += units.abbreviation + " = " + fmt(units.mm) + " mm); it does not rescale existing geometry. Use SCALE to resize objects."
        o.set("note", note)
        return o.json
    }

    /// OK in the Units sheet: one "Units" undo step when anything changed.
    func unitsSet(_ p: EngineJSON) throws -> EngineJSON {
        let d = editor.doc
        var units = d.units
        if let s = p["units"]?.stringValue {
            guard let u = Units(rawValue: s.lowercased()) else { throw EngineError.params("unknown units '\(s)'") }
            units = u
        }
        var lin = UnitFormat.linearType(d)
        if let v = p["lunits"] {
            guard let i = v.intValue, let t = UnitFormat.Linear(rawValue: i) else { throw EngineError.params("lunits must be 1–5") }
            lin = t
        }
        var ang = UnitFormat.angularType(d)
        if let v = p["aunits"] {
            guard let i = v.intValue, let t = UnitFormat.Angular(rawValue: i) else { throw EngineError.params("aunits must be 0–4") }
            ang = t
        }
        let lprec = min(max(p["luprec"]?.intValue ?? UnitFormat.linearPrecision(d), 0), 8)
        let aprec = min(max(p["auprec"]?.intValue ?? UnitFormat.angularPrecision(d), 0), 8)
        var same = units == d.units && lin == UnitFormat.linearType(d) && lprec == UnitFormat.linearPrecision(d)
        same = same && ang == UnitFormat.angularType(d) && aprec == UnitFormat.angularPrecision(d)
        if !same {
            editor.transaction("Units") { doc in
                doc.units = units
                doc.setVariable("LUNITS", String(lin.rawValue))
                doc.setVariable("LUPREC", String(lprec))
                doc.setVariable("AUNITS", String(ang.rawValue))
                doc.setVariable("AUPREC", String(aprec))
            }
        }
        return unitsGet(.object([]))
    }

    // MARK: Drafting Settings (DraftingSettingsSheet)

    static let polarIncrements: [Double] = [5, 10, 15, 18, 22.5, 30, 45, 90]

    func draftingGet() -> EngineJSON {
        let s = editor.settings
        var o = EngineObject()
        o.set("showGrid", s.showGrid)
        o.set("gridSnap", s.gridSnap)
        o.set("gridSpacing", s.gridSpacing)
        o.set("ortho", s.ortho)
        o.set("polarTracking", s.polarTracking)
        o.set("polarIncrement", s.polarIncrement)
        o.set("dynamicInput", s.dynamicInput)
        o.set("lineweightDisplay", s.lineweightDisplay)
        o.set("textHeight", s.textHeight)
        o.set("wallThickness", s.wallThickness)
        o.set("wallHeight", s.wallHeight)
        o.set("objectSnap", s.objectSnap)
        let modes = SnapKind.allCases.filter { s.snapModes.contains($0) }.map(\.rawValue)
        o.set("snapModes", EngineJSON.strings(modes))
        o.set("snapKinds", EngineJSON.strings(SnapKind.allCases.map(\.rawValue)))
        o.set("polarIncrements", EngineJSON.numbers(EngineSession.polarIncrements))
        o.set("units", editor.doc.units.abbreviation)
        return o.json
    }

    static func snapModes(_ v: EngineJSON) throws -> Set<SnapKind> {
        guard let a = v.arrayValue else { throw EngineError.params("snapModes must be an array") }
        var out = Set<SnapKind>()
        for x in a {
            guard let s = x.stringValue, let k = SnapKind(rawValue: s.lowercased()) else { throw EngineError.params("unknown snap mode '\(x.stringValue ?? "")'") }
            out.insert(k)
        }
        return out
    }

    static func positive(_ p: EngineJSON, _ key: String) throws -> Double? {
        guard let v = p[key], !v.isNull else { return nil }
        guard let d = v.doubleValue, d.isFinite, d > 0 else { throw EngineError.params("\(key) must be a positive number") }
        return d
    }

    /// OK in the Drafting Settings sheet: the given fields replace the session's drafting settings.
    func draftingSet(_ p: EngineJSON) throws -> EngineJSON {
        var s = editor.settings
        if let b = p["showGrid"]?.boolValue { s.showGrid = b }
        if let b = p["gridSnap"]?.boolValue { s.gridSnap = b }
        if let g = try EngineSession.positive(p, "gridSpacing") { s.gridSpacing = g }
        if let b = p["ortho"]?.boolValue { s.ortho = b }
        if let b = p["polarTracking"]?.boolValue { s.polarTracking = b }
        if let a = try EngineSession.positive(p, "polarIncrement") { s.polarIncrement = a }
        if let b = p["dynamicInput"]?.boolValue { s.dynamicInput = b }
        if let b = p["lineweightDisplay"]?.boolValue { s.lineweightDisplay = b }
        if let v = try EngineSession.positive(p, "textHeight") { s.textHeight = v }
        if let v = try EngineSession.positive(p, "wallThickness") { s.wallThickness = v }
        if let v = try EngineSession.positive(p, "wallHeight") { s.wallHeight = v }
        if let b = p["objectSnap"]?.boolValue { s.objectSnap = b }
        if let m = p["snapModes"] { s.snapModes = try EngineSession.snapModes(m) }
        editor.settings = s
        markChanged("sysvars")
        return draftingGet()
    }

    /// Settings ▸ Drafting defaults applied to this drawing (AppPreferences.draftDefaults): grid spacing given in
    /// millimetres is converted for metric drawings; polar tracking is off when ortho is on. With `units` (a new blank
    /// metric drawing and Settings ▸ General ▸ Default units) the drawing takes those units first, like AppModel.newDocument.
    func draftingDefaults(_ p: EngineJSON) throws -> EngineJSON {
        var s = editor.settings
        if let us = p["units"]?.stringValue, !us.isEmpty {
            guard let u = Units(rawValue: us.lowercased()) else { throw EngineError.params("unknown units '\(us)'") }
            if u != editor.doc.units {
                var d = editor.doc
                d.units = u
                let wasDirty = editor.isDirty
                let url = editor.fileURL
                editor.replaceDocument(d, url: url)
                editor.isDirty = wasDirty
                drawCacheReset()
            }
            if u == .centimeters || u == .meters {
                let f = u.mm
                s.textHeight /= f; s.wallThickness /= f; s.wallHeight /= f; s.offsetDistance /= f
            } else if u == .feet {
                s.textHeight /= 12; s.wallThickness /= 12; s.wallHeight /= 12; s.offsetDistance /= 12; s.gridSpacing = 1
            }
        }
        let draft = p["draft"] ?? p
        if let b = draft["showGrid"]?.boolValue { s.showGrid = b }
        if let b = draft["gridSnap"]?.boolValue { s.gridSnap = b }
        let ortho = draft["ortho"]?.boolValue ?? s.ortho
        s.ortho = ortho
        if let b = draft["polarTracking"]?.boolValue { s.polarTracking = b && !ortho }
        if let a = try EngineSession.positive(draft, "polarIncrement") { s.polarIncrement = a }
        if let b = draft["objectSnap"]?.boolValue { s.objectSnap = b }
        if let m = draft["snapModes"] { s.snapModes = try EngineSession.snapModes(m) }
        if let b = draft["dynamicInput"]?.boolValue { s.dynamicInput = b }
        if let b = draft["lineweightDisplay"]?.boolValue { s.lineweightDisplay = b }
        let u = editor.doc.units
        if u == .millimeters || u == .centimeters || u == .meters, let g = try EngineSession.positive(draft, "gridSpacing") {
            s.gridSpacing = max(g / u.mm, 1e-6)
        }
        editor.settings = s
        markChanged("sysvars")
        return draftingGet()
    }

    // MARK: Quick Select (QuickSelectSheet)

    static let quickSelectProperties = ["*", "layer", "color", "linetype", "lineweight", "length", "area", "radius", "height", "contents", "name", "material", "level", "x", "y"]

    static func opTitle(_ o: ObjectQuery.Op) -> String {
        switch o {
        case .eq: return "= Equals"
        case .ne: return "≠ Not equal"
        case .gt: return "> Greater than"
        case .lt: return "< Less than"
        case .ge: return "≥ Greater or equal"
        case .le: return "≤ Less or equal"
        }
    }

    /// Candidates: the current selection (scope 1) or every selectable object of the drawing with the building
    /// elements of the current level (scope 0).
    func quickSelectCandidates(_ scope: Int) -> [EntityID] {
        let doc = editor.doc
        if scope == 1 { return Array(editor.selection) }
        var ids: [EntityID] = []
        for e in doc.entities where editor.isSelectable(e.id) { ids.append(e.id) }
        for el in doc.elements where el.level == doc.currentLevel && editor.isSelectable(el.id) { ids.append(el.id) }
        return ids
    }

    func qselectOptions(_ p: EngineJSON) -> EngineJSON {
        let d = editor.doc
        var names = Set<String>()
        for e in d.entities { if let t = ObjectQuery.typeName(e.id, doc: d) { names.insert(t) } }
        for el in d.elements where el.level == d.currentLevel { if let t = ObjectQuery.typeName(el.id, doc: d) { names.insert(t) } }
        var types: [EngineJSON] = [.object([EngineJSONField("value", .string("*")), EngineJSONField("title", .string("Multiple (all types)"))])]
        for t in names.sorted() { types.append(.object([EngineJSONField("value", .string(t)), EngineJSONField("title", .string(t.capitalized))])) }
        var props: [EngineJSON] = []
        for n in EngineSession.quickSelectProperties {
            let title = n == "*" ? "None (type only)" : n.capitalized
            props.append(.object([EngineJSONField("value", .string(n)), EngineJSONField("title", .string(title))]))
        }
        var ops: [EngineJSON] = []
        for o in ObjectQuery.Op.allCases { ops.append(.object([EngineJSONField("value", .string(o.rawValue)), EngineJSONField("title", .string(EngineSession.opTitle(o)))])) }
        var o = EngineObject()
        o.set("types", EngineJSON.array(types))
        o.set("properties", EngineJSON.array(props))
        o.set("operators", EngineJSON.array(ops))
        o.set("layers", EngineJSON.strings(d.layers.map(\.name)))
        o.set("selectionCount", editor.selection.count)
        o.set("scope", editor.selection.count > 1 ? 0 : (p["scope"]?.intValue ?? 0))
        return o.json
    }

    func quickSelectMatches(_ p: EngineJSON) throws -> [EntityID] {
        let d = editor.doc
        let scope = p["scope"]?.intValue ?? 0
        let type = p["type"]?.stringValue ?? "*"
        let property = p["property"]?.stringValue ?? "*"
        var ids = quickSelectCandidates(scope).filter { ObjectQuery.typeMatches($0, type, doc: d) }
        if property != "*" {
            let opText = p["op"]?.stringValue ?? "="
            guard let op = ObjectQuery.Op(rawValue: opText) else { throw EngineError.params("unknown operator '\(opText)'") }
            let c = ObjectQuery.Criterion(property, op, p["value"]?.stringValue ?? "")
            ids = ids.filter { c.matches($0, doc: d) }
        }
        return ids.sorted()
    }

    /// Live match count; with `apply` the Select button: mode New (replace) / Append / Exclude, one history line.
    func qselectRun(_ p: EngineJSON) throws -> EngineJSON {
        let ids = try quickSelectMatches(p)
        var o = EngineObject()
        o.set("count", ids.count)
        if p["apply"]?.boolValue == true {
            let mode = p["mode"]?.stringValue ?? "New"
            switch mode {
            case "Append": editor.selection.formUnion(ids)
            case "Exclude": editor.selection.subtract(ids)
            default: editor.selection = Set(ids)
            }
            editor.previousSelection = editor.selection
            let type = p["type"]?.stringValue ?? "*"
            let property = p["property"]?.stringValue ?? "*"
            let value = p["value"]?.stringValue ?? ""
            var crit = "*"
            if property != "*" {
                let v = value.contains(" ") ? "\"" + value + "\"" : value
                crit = property + " " + (p["op"]?.stringValue ?? "=") + " " + v
            }
            editor.print("QSELECT " + type + " " + crit + " → " + String(ids.count) + " matched; " + String(editor.selection.count) + " selected.")
            o.set("selected", editor.selection.count)
            o.set("ids", EngineJSON.ints(editor.selection.sorted()))
        }
        return o.json
    }

    // MARK: Layer States Manager (LayerStatesSheet)

    static func isoDate(_ d: Date?) -> EngineJSON {
        guard let d else { return .null }
        let f = ISO8601DateFormatter()
        return .string(f.string(from: d))
    }

    func layerStateList() -> EngineJSON {
        var rows: [EngineJSON] = []
        for n in LayerStates.names(editor.doc) {
            let st = LayerStates.named(n, editor.doc)
            var o = EngineObject()
            o.set("name", n)
            o.set("layers", st?.layers.count ?? 0)
            o.set("date", EngineSession.isoDate(st?.date))
            o.set("description", st?.description ?? "")
            o.set("currentLayer", EngineJSON.optString(st?.currentLayer))
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("states", EngineJSON.array(rows))
        return o.json
    }

    func stateName(_ p: EngineJSON, _ key: String = "name") throws -> String {
        let n = (p[key]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { throw EngineError.params("missing '\(key)'") }
        return n
    }

    /// Save Current Layers / Update: one "Save Layer State" undo step.
    func layerStateSave(_ p: EngineJSON) throws -> EngineJSON {
        let n = try stateName(p)
        let desc = p["description"]?.stringValue ?? LayerStates.named(n, editor.doc)?.description ?? ""
        editor.transaction("Save Layer State") { _ = LayerStates.save(&$0, name: n.uppercased(), description: desc) }
        editor.print("Layer state " + n.uppercased() + " saved.")
        var o = EngineObject()
        o.set("selected", n.uppercased())
        o.set("states", layerStateList()["states"] ?? .array([]))
        return o.json
    }

    func layerStateRestore(_ p: EngineJSON) throws -> EngineJSON {
        let n = try stateName(p)
        guard let st = LayerStates.named(n, editor.doc) else { throw EngineError.failed("Layer state " + n.uppercased() + " not found.") }
        var changed = 0
        editor.transaction("Restore Layer State") { changed = LayerStates.restore(st, into: &$0) }
        editor.print("Layer state " + n + " restored (" + String(changed) + " layer(s) changed).")
        drawCacheReset()
        var o = EngineObject()
        o.set("changed", changed)
        o.set("states", layerStateList()["states"] ?? .array([]))
        return o.json
    }

    func layerStateDelete(_ p: EngineJSON) throws -> EngineJSON {
        let n = try stateName(p)
        editor.transaction("Delete Layer State") { _ = LayerStates.delete(&$0, name: n) }
        return layerStateList()
    }

    /// Rename field: upper-cased; ignored when empty, unchanged or taken (as the Mac sheet).
    func layerStateRename(_ p: EngineJSON) throws -> EngineJSON {
        let old = try stateName(p)
        let new = (p["newName"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        var o = EngineObject()
        if !new.isEmpty, new != old.uppercased(), !LayerStates.names(editor.doc).contains(new) {
            editor.transaction("Rename Layer State") { _ = LayerStates.rename(&$0, from: old, to: new) }
            o.set("selected", new)
        } else {
            o.set("selected", old.uppercased())
        }
        o.set("states", layerStateList()["states"] ?? .array([]))
        return o.json
    }

    // MARK: Layers panel: saved filters and the layer tree

    static let layerFilterPrefix = "LAYERFILTER:"

    func layerFilterList() -> EngineJSON {
        var rows: [EngineJSON] = []
        let keys = editor.doc.variables.keys.filter { $0.hasPrefix(EngineSession.layerFilterPrefix) }.sorted()
        for k in keys {
            let name = String(k.dropFirst(EngineSession.layerFilterPrefix.count))
            rows.append(.object([EngineJSONField("name", .string(name)), EngineJSONField("filter", .string(editor.doc.variables[k] ?? ""))]))
        }
        return .object([EngineJSONField("filters", .array(rows))])
    }

    func layerFilterSave(_ p: EngineJSON) throws -> EngineJSON {
        let n = try stateName(p).uppercased()
        let f = (p["filter"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { throw EngineError.params("missing 'filter'") }
        editor.transaction("Save Layer Filter") { $0.variables[EngineSession.layerFilterPrefix + n] = f }
        return layerFilterList()
    }

    func layerFilterDelete(_ p: EngineJSON) throws -> EngineJSON {
        let n = try stateName(p).uppercased()
        editor.transaction("Delete Layer Filter") { $0.variables[EngineSession.layerFilterPrefix + n] = nil }
        return layerFilterList()
    }

    /// Layer tree group of a layer name (LayerTree.key in the Mac app): "xref|", the prefix before -, _ or space.
    public static func layerGroupKey(_ layer: String) -> String {
        if let bar = layer.firstIndex(of: "|") { return String(layer[...bar]) }
        if let dash = layer.firstIndex(where: { $0 == "-" || $0 == "_" || $0 == " " }), dash != layer.startIndex { return String(layer[..<dash]) }
        return layer == "0" || layer.uppercased() == "DEFPOINTS" ? "(Standard)" : layer
    }

    /// Bulk on/off, freeze/thaw, lock/unlock of a layer tree group (one "Layer Group <name>" undo step). The current
    /// layer is never frozen.
    func layerGroupSet(_ p: EngineJSON) throws -> EngineJSON {
        let group = try string(p, "group")
        let key = try string(p, "key")
        guard let value = p["value"]?.boolValue else { throw EngineError.params("missing 'value'") }
        guard ["visible", "frozen", "locked"].contains(key) else { throw EngineError.params("key must be visible, frozen or locked") }
        var n = 0
        editor.transaction("Layer Group " + group) { d in
            for i in d.layers.indices where EngineSession.layerGroupKey(d.layers[i].name) == group {
                var l = d.layers[i]
                switch key {
                case "visible": l.visible = value
                case "frozen":
                    if value && l.name.caseInsensitiveCompare(d.currentLayer) == .orderedSame { continue }
                    l.frozen = value
                default: l.locked = value
                }
                if l != d.layers[i] { d.layers[i] = l; n += 1 }
            }
        }
        drawCacheReset()
        return .object([EngineJSONField("changed", .int(n))])
    }

    // MARK: Page Setup (PageSetupSheet)

    func layoutArg(_ p: EngineJSON) -> Int? {
        guard let v = p["layout"], !v.isNull else { return nil }
        let ls = editor.doc.layouts
        if case .number = v, let i = v.intValue { return ls.indices.contains(i) ? i : nil }
        let s = v.stringValue ?? ""
        return ls.firstIndex { $0.name.caseInsensitiveCompare(s) == .orderedSame }
    }

    func pageSetupGet(_ p: EngineJSON) -> EngineJSON {
        let doc = editor.doc
        let li = layoutArg(p)
        let setup = EnginePageSetup.load(doc, layoutIndex: li)
        var o = EngineObject()
        o.set("isSheet", li != nil)
        o.set("layout", li.map { EngineJSON.int($0) } ?? .null)
        o.set("title", li.map { "Page Setup — " + doc.layouts[$0].name } ?? "Page Setup — Model")
        if let i = li {
            let paper = doc.layouts[i].paper
            o.set("portrait", paper.height > paper.width)
            let baseName = paper.name.hasSuffix(" portrait") ? String(paper.name.dropLast(" portrait".count)) : paper.name
            let name = EnginePaperCatalog.all(doc).first { $0.name == baseName }?.name ?? EnginePaperCatalog.builtIn.first { paper.name.hasPrefix($0.name) }?.name ?? baseName
            o.set("paper", name)
            o.set("hasSection", doc.layouts[i].viewports.contains { $0.view == .section })
            o.set("sectionStyle", doc.layouts[i].titleBlock[SectionSheetStyle.key].flatMap { try? EngineJSON.parse($0) } ?? .null)
        }
        var papers: [EngineJSON] = []
        for s in EnginePaperCatalog.all(doc) {
            var po = EngineObject()
            po.set("name", s.name)
            po.set("width", s.width)
            po.set("height", s.height)
            po.set("label", s.name + " (" + fmt(s.width, 0) + "×" + fmt(s.height, 0) + " mm)")
            po.set("modelLabel", s.name + " (" + fmt(s.width, 0) + "×" + fmt(s.height, 0) + ")")
            papers.append(po.json)
        }
        o.set("papers", EngineJSON.array(papers))
        o.set("setup", setup.json)
        o.set("scaleText", setup.modelScale.map { "1:" + fmt($0, 0) } ?? "Fit")
        o.set("colorModes", EngineJSON.strings(EnginePageSetup.colorModes))
        o.set("plotAreas", EngineJSON.strings(EnginePageSetup.plotAreas))
        o.set("tables", EngineJSON.strings(EnginePageSetup.plotStyleTables(doc)))
        o.set("namedTables", EngineJSON.strings(EnginePageSetup.namedStyleTables(doc)))
        var scales: [EngineJSON] = [.object([EngineJSONField("value", .string("Fit")), EngineJSONField("title", .string("Fit to paper"))])]
        for r in EnginePageSetup.scaleRatios {
            let t = "1:" + fmt(r, 0)
            scales.append(.object([EngineJSONField("value", .string(t)), EngineJSONField("title", .string(t))]))
        }
        o.set("scales", EngineJSON.array(scales))
        o.set("stampTemplate", EnginePageSetup.stampTemplate)
        o.set("stampFields", EngineJSON.strings(EnginePageSetup.stampFields))
        o.set("presets", pagePresetList()["presets"] ?? .array([]))
        o.set("layouts", .array(doc.layouts.enumerated().map { .object([EngineJSONField("index", .int($0.offset)), EngineJSONField("name", .string($0.element.name))]) }))
        return o.json
    }

    func pagePresetList() -> EngineJSON {
        let presets = NamedPageSetups.all(editor.doc)
        let values = presets.keys.sorted().compactMap { name -> EngineJSON? in
            guard let value = presets[name], let data = try? JSONEncoder().encode(value), let json = try? EngineJSON.parse(String(decoding: data, as: UTF8.self)) else { return nil }
            return .object([EngineJSONField("name", .string(name)), EngineJSONField("preset", json)])
        }
        return .object([EngineJSONField("presets", .array(values))])
    }

    func pagePresetEdit(_ method: String, _ p: EngineJSON) throws -> EngineJSON {
        var updated = editor.doc
        if method == "pagepresets.import" {
            guard let path = p["path"]?.stringValue else { throw EngineError.params("path required") }
            let source = try DocumentIO.read(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            NamedPageSetups.importFrom(source, doc: &updated)
        } else {
            guard let name = p["name"]?.stringValue, let preset = NamedPageSetups.find(name, doc: updated) else { throw EngineError.params("page setup not found") }
            if method == "pagepresets.delete" { NamedPageSetups.delete(name, doc: &updated) }
            else {
                let targets = p["all"]?.boolValue == true ? Array(updated.layouts.indices) : p["layouts"]?.arrayValue?.compactMap(\.intValue) ?? []
                try NamedPageSetups.apply(preset, to: targets, doc: &updated)
            }
        }
        let result = updated
        editor.transaction("Named Page Setup") { $0 = result }
        return pagePresetList()
    }

    /// OK in the Page Setup sheet: stores the setup (removed when default) and, for a sheet, its paper — one
    /// "Page Setup" undo step.
    func pageSetupSet(_ p: EngineJSON) throws -> EngineJSON {
        let li = layoutArg(p)
        if p["layout"] != nil && !(p["layout"]?.isNull ?? true) && li == nil { throw EngineError.params("no such layout") }
        var s = EnginePageSetup.load(editor.doc, layoutIndex: li)
        if let v = p["setup"] { try s.apply(v) }
        if let t = p["scaleText"]?.stringValue { s.modelScale = t == "Fit" ? nil : Double(t.dropFirst(2)) }
        var baseDocument = editor.doc
        if let source = p["presetSource"]?.stringValue, let i = li {
            guard let preset = NamedPageSetups.find(source, doc: baseDocument) else { throw EngineError.params("page setup not found") }
            try NamedPageSetups.apply(preset, to: [i], doc: &baseDocument)
            let resolved = EnginePageSetup.load(baseDocument, layoutIndex: i)
            var original = EnginePageSetup(); try original.apply(EngineJSON.parse(preset.settings))
            if s.plotStyleTable == original.plotStyleTable { s.plotStyleTable = resolved.plotStyleTable }
            if s.namedStyleTable == original.namedStyleTable { s.namedStyleTable = resolved.namedStyleTable }
        }
        var paper: PaperSize? = nil
        if let i = li, let name = p["paper"]?.stringValue {
            guard let base = EnginePaperCatalog.all(baseDocument).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw EngineError.params("unknown paper '\(name)'") }
            let portrait = p["portrait"]?.boolValue ?? (baseDocument.layouts[i].paper.height > baseDocument.layouts[i].paper.width)
            let w = portrait ? min(base.width, base.height) : max(base.width, base.height)
            let h = portrait ? max(base.width, base.height) : min(base.width, base.height)
            let n = name.replacingOccurrences(of: " portrait", with: "") + (portrait ? " portrait" : "")
            paper = PaperSize(name: n, width: w, height: h)
        }
        let setup = s, base = baseDocument, originalDocument = editor.doc
        let section = p["sectionStyle"]
        var sectionStyle: SectionSheetStyle?
        if let section, !section.isNull {
            guard let value = try? JSONDecoder().decode(SectionSheetStyle.self, from: Data(section.serialized.utf8)),
                  [value.lines.cutLineweight, value.lines.projectionLineweight].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 5 }),
                  [value.lines.color, value.lines.cutFill].compactMap({ $0 }).allSatisfy({ [$0.r, $0.g, $0.b, $0.a].allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { throw EngineError.params("invalid section style") }
            sectionStyle = value
        }
        let presetName = p["presetName"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        if p["presetOnly"]?.boolValue == true && presetName == nil { throw EngineError.params("preset name required") }
        if presetName != nil && (li == nil || presetName!.isEmpty) { throw EngineError.params("preset requires a name and sheet") }
        editor.transaction("Page Setup") { d in
            d = base
            setup.store(in: &d, layoutIndex: li)
            if let i = li, let pp = paper, d.layouts[i].paper != pp { d.layouts[i].paper = pp }
            if let i = li, section != nil {
                if let style = sectionStyle { style.store(in: &d.layouts[i]) }
                else { d.layouts[i].titleBlock[SectionSheetStyle.key] = nil }
            }
            if let name = presetName, let i = li, let preset = NamedPageSetups.capture(d, layoutIndex: i) {
                if p["presetOnly"]?.boolValue == true { d = originalDocument }
                NamedPageSetups.save(preset, name: name, doc: &d)
            }
        }
        return pageSetupGet(p)
    }

    // MARK: Templates (TemplateLibrary)

    static let templateExtension = "architemplate"

    static func builtInTemplates() -> [EngineJSON] {
        let rows: [(String, String, String, String)] = [
            ("builtin:metric", "Metric", "Millimetres, standard layers", "square.and.pencil"),
            ("builtin:metricArchitectural", "Metric Architectural", "AIA-style layers, 1:20–1:200 dimension styles", "ruler"),
            ("builtin:imperial", "Imperial", "Inches, architectural dimensions", "ruler.fill"),
            ("builtin:building", "Building", "Levels, structural grid and sheets", "building.2"),
        ]
        var out: [EngineJSON] = []
        for r in rows {
            var o = EngineObject()
            o.set("id", r.0); o.set("name", r.1); o.set("subtitle", r.2); o.set("symbol", r.3)
            out.append(o.json)
        }
        return out
    }

    /// Built-in templates followed by the .archi / .architemplate files of `folder` (sorted by name).
    func templatesList(_ p: EngineJSON) -> EngineJSON {
        var out = EngineSession.builtInTemplates()
        let folder = p["folder"]?.stringValue ?? uiPreference("templatesFolder")
        if let f = folder, !f.isEmpty {
            let dir = url(f)
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let picked = files.filter { ["archi", EngineSession.templateExtension].contains($0.pathExtension.lowercased()) }
            let sorted = picked.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            for u in sorted {
                var o = EngineObject()
                o.set("id", u.path); o.set("name", u.deletingPathExtension().lastPathComponent)
                o.set("subtitle", "Templates folder"); o.set("symbol", "doc.badge.gearshape")
                out.append(o.json)
            }
        }
        // Recently used template files that still exist and are not in the folder list ("Recent · <folder>").
        let listed = Set(out.compactMap { $0["id"]?.stringValue })
        for r in p["recent"]?.arrayValue ?? [] {
            guard let path = r.stringValue, !listed.contains(path), FileManager.default.fileExists(atPath: path) else { continue }
            let u = URL(fileURLWithPath: path)
            var o = EngineObject()
            o.set("id", path); o.set("name", u.deletingPathExtension().lastPathComponent)
            o.set("subtitle", "Recent · " + u.deletingLastPathComponent().lastPathComponent); o.set("symbol", "doc.badge.gearshape")
            o.set("recent", true)
            out.append(o.json)
        }
        return .object([EngineJSONField("folder", EngineJSON.optString(folder)), EngineJSONField("templates", .array(out))])
    }

    /// A template as a new untitled drawing in this session (TemplateLibrary.apply): built-in kinds or a file.
    func templatesNew(_ p: EngineJSON) async throws -> EngineJSON {
        let id = try string(p, "id")
        try await applyTemplate(id)
        return docInfo()
    }

    func applyTemplate(_ id: String, cancelRunning: Bool = true) async throws {
        if cancelRunning { await cancelAndWait() }
        var d: ArchiDocument
        var s = DraftSettings()
        var message: String? = nil
        switch id {
        case "builtin:metric", "builtin:imperial", "builtin:building":
            let kind = String(id.dropFirst("builtin:".count))
            guard let t = EngineTemplates.make(kind) else { throw EngineError.params("no template \(id)") }
            d = t.0; s = t.1
        case "builtin:metricArchitectural":
            d = EngineSession.metricArchitectural()
            message = "New drawing from the Metric Architectural template (" + String(d.layers.count) + " layers, " + String(d.dimStyles.count) + " dimension styles)."
        default:
            let u = url(id)
            guard FileManager.default.fileExists(atPath: u.path) else { throw EngineError.failed("Template not found: " + u.path) }
            if u.pathExtension.lowercased() == EngineSession.templateExtension || u.pathExtension.lowercased() == "archi" {
                d = try ArchiFile.decode(Data(contentsOf: u))
            } else {
                d = try DocumentIO.read(u)
            }
            d.info.name = "Untitled Project"
            if d.units == .inches || d.units == .feet, let t = EngineTemplates.make("imperial") { s = t.1 }
            message = "New drawing from template " + u.deletingPathExtension().lastPathComponent + "."
        }
        editor.replaceDocument(d, url: nil)
        editor.settings = s
        drawCacheReset()
        if let m = message { editor.print(m) }
    }

    /// Writes the drawing into the templates folder as <name>.architemplate. Returns the file path.
    func templatesSave(_ p: EngineJSON) throws -> EngineJSON {
        let name = try stateName(p)
        let path = try saveTemplate(name, folder: p["folder"]?.stringValue)
        return .object([EngineJSONField("path", .string(path))])
    }

    func saveTemplate(_ name: String, folder: String?) throws -> String {
        guard let f = folder ?? uiPreference("templatesFolder"), !f.isEmpty else { throw EngineError.failed("No templates folder.") }
        let dir = url(f)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "\\", with: "-")
        let u = dir.appendingPathComponent(safe).appendingPathExtension(EngineSession.templateExtension)
        try ArchiFile.encode(editor.doc).write(to: u, options: .atomic)
        return u.path
    }

    /// Metric architectural template (TemplateLibrary.metricArchitectural in the Mac app; keep the two in step).
    static func metricArchitectural() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Untitled Project"
        var extra: [Layer] = []
        extra.append(Layer(name: "A-COLS", color: RGBA(0.8, 0.8, 0.8), lineweight: 0.5))
        extra.append(Layer(name: "A-FLOR", color: RGBA(0.7, 0.7, 0.7), lineweight: 0.25))
        extra.append(Layer(name: "A-ROOF", color: RGBA(0.85, 0.6, 0.4), lineweight: 0.35))
        extra.append(Layer(name: "A-STRS", color: RGBA(0.6, 0.8, 0.6), lineweight: 0.25))
        extra.append(Layer(name: "A-CLNG", color: RGBA(0.6, 0.6, 0.9), lineweight: 0.18))
        extra.append(Layer(name: "A-FURN", color: RGBA(0.75, 0.65, 0.95), lineweight: 0.18))
        extra.append(Layer(name: "A-EQPM", color: RGBA(0.9, 0.7, 0.9), lineweight: 0.18))
        extra.append(Layer(name: "A-DETL", color: RGBA(0.9, 0.9, 0.6), lineweight: 0.25))
        extra.append(Layer(name: "A-PATT", color: RGBA(0.5, 0.5, 0.5), lineweight: 0.09))
        extra.append(Layer(name: "A-ANNO-SYMB", color: RGBA(1, 0.85, 0.3), lineweight: 0.18))
        extra.append(Layer(name: "A-ANNO-NPLT", color: RGBA(0.5, 0.7, 1), lineweight: 0.13, plot: false, description: "Construction lines (not plotted)"))
        extra.append(Layer(name: "C-PROP", color: RGBA(0.4, 0.9, 0.4), linetype: "Phantom", lineweight: 0.35))
        extra.append(Layer(name: "L-PLNT", color: RGBA(0.3, 0.75, 0.35), lineweight: 0.18))
        for l in extra where d.layer(named: l.name) == nil { d.layers.append(l) }
        var dims: [DimStyle] = [DimStyle(name: "Standard")]
        for s in [20.0, 50, 100, 200] {
            let name = "Architectural 1:" + String(Int(s))
            dims.append(DimStyle(name: name, textHeight: 2.5 * s, arrowSize: 1.5 * s, arrow: .architecturalTick,
                                 extensionOffset: 1 * s, extensionExtend: 1.5 * s, textGap: 0.8 * s))
        }
        d.dimStyles = dims
        d.currentDimStyle = "Architectural 1:100"
        var styles: [TextStyle] = [TextStyle(name: "Standard")]
        styles.append(TextStyle(name: "Notes 1:100", font: "Helvetica", height: 250))
        styles.append(TextStyle(name: "Titles 1:100", font: "Helvetica-Bold", height: 500))
        styles.append(TextStyle(name: "Notes 1:50", font: "Helvetica", height: 125))
        d.textStyles = styles
        d.setVariable("LTSCALE", "10")
        d.setVariable("DIMSCALE", "1")
        d.units = .millimeters
        return d
    }

    // MARK: Shell preferences the portable UI commands read (prompt defaults, workspace names …)

    /// Stores the shell's application preferences (Settings) that the portable UI commands use as prompt defaults:
    /// cursorSize, autosaveMinutes, theme, templatesFolder, workspaces (names, "|" separated), workspace, cui (JSON),
    /// quickAccess (comma separated). Returns every stored value.
    func uiPrefs(_ p: EngineJSON) -> EngineJSON {
        if let vals = p["values"]?.fields ?? p.fields?.filter({ $0.key != "values" }) {
            for f in vals { EngineSession.uiPreferences[f.key] = f.value.stringValue ?? f.value.serialized }
        }
        var o = EngineObject()
        for k in EngineSession.uiPreferences.keys.sorted() { o.set(k, EngineSession.uiPreferences[k] ?? "") }
        return o.json
    }

    static var uiPreferences: [String: String] = [:]
    func uiPreference(_ key: String) -> String? { EngineSession.uiPreferences[key] }

    /// Drops the cached plan draw list (layer visibility or the document changed outside a transaction).
    func drawCacheReset() { drawCache = nil }

    /// Asks the shell for a dialog or another UI action (host notification with `action` and extra fields).
    func hostRequest(_ action: String, _ extra: EngineObject = EngineObject()) {
        var o = EngineObject()
        o.set("action", action)
        for f in extra.fields { o.set(f.key, f.value) }
        emit(EngineProtocol.notification("host", o.json))
    }
}

// MARK: - Page setup data (PageSetup in ArchiApp/PlotExtras.swift; same JSON in "PAGESETUP:<SHEET>" / "PAGESETUP:*MODEL*")

struct EnginePageSetup: Equatable {
    var colorMode = "Color"
    var lineweightScale = 1.0
    var plotStamp = false
    var modelPaper = "A3"
    var modelPortrait = false
    var modelScale: Double? = nil
    var plotStyleTable: String? = nil
    var stampText: String? = nil
    var plotArea = "Extents"
    var plotWindow: [Double]? = nil
    var exactFit = false
    var namedStyleTable: String? = nil

    static let colorModes = ["Color", "Monochrome", "Grayscale"]
    static let plotAreas = ["Extents", "Display", "Limits", "Window"]
    static let scaleRatios: [Double] = [1, 5, 10, 20, 25, 50, 75, 100, 200, 250, 500, 1000]
    static let stampTemplate = "{project}  ·  {sheet}  ·  plotted {date} {time}  ·  Oanarina Archi Tool"
    static let stampFields = ["{project}", "{number}", "{sheet}", "{date}", "{time}", "{user}", "{file}", "{style}"]
    static let modelKey = "PAGESETUP:*MODEL*"

    static func key(_ doc: ArchiDocument, layoutIndex: Int?) -> String {
        guard let i = layoutIndex, doc.layouts.indices.contains(i) else { return modelKey }
        return "PAGESETUP:" + doc.layouts[i].name.uppercased()
    }

    static func load(_ doc: ArchiDocument, layoutIndex: Int?) -> EnginePageSetup {
        var s = EnginePageSetup()
        guard let text = doc.variables[key(doc, layoutIndex: layoutIndex)], let j = try? EngineJSON.parse(text) else { return s }
        try? s.apply(j)
        return s
    }

    static func optText(_ v: EngineJSON?) -> String? {
        guard let v, !v.isNull, let s = v.stringValue, !s.isEmpty else { return nil }
        return s
    }

    /// Applies the fields present in a JSON object (the shell's form or the stored JSON).
    mutating func apply(_ j: EngineJSON) throws {
        if let v = j["colorMode"]?.stringValue {
            guard EnginePageSetup.colorModes.contains(v) else { throw EngineError.params("unknown plot style '\(v)'") }
            colorMode = v
        }
        if let v = j["lineweightScale"]?.doubleValue { lineweightScale = min(max(v, 0.25), 3) }
        if let v = j["plotStamp"]?.boolValue { plotStamp = v }
        if let v = j["modelPaper"]?.stringValue { modelPaper = v }
        if let v = j["modelPortrait"]?.boolValue { modelPortrait = v }
        if let v = j["modelScale"] { modelScale = v.isNull ? nil : v.doubleValue }
        if let v = j["plotStyleTable"] { plotStyleTable = EnginePageSetup.optText(v) }
        if let v = j["stampText"] { stampText = EnginePageSetup.optText(v) }
        if let v = j["plotArea"]?.stringValue {
            guard EnginePageSetup.plotAreas.contains(v) else { throw EngineError.params("unknown plot area '\(v)'") }
            plotArea = v
        }
        if let v = j["plotWindow"] {
            let n = v.arrayValue?.compactMap(\.doubleValue) ?? []
            plotWindow = n.count == 4 ? n : nil
        }
        if let v = j["exactFit"]?.boolValue { exactFit = v }
        if let v = j["namedStyleTable"] { namedStyleTable = EnginePageSetup.optText(v) }
    }

    /// The JSON the Mac PageSetup encoder writes (sorted keys, optionals left out).
    var json: EngineJSON {
        var f: [EngineJSONField] = []
        f.append(EngineJSONField("colorMode", .string(colorMode)))
        f.append(EngineJSONField("exactFit", .bool(exactFit)))
        f.append(EngineJSONField("lineweightScale", .number(lineweightScale)))
        f.append(EngineJSONField("modelPaper", .string(modelPaper)))
        f.append(EngineJSONField("modelPortrait", .bool(modelPortrait)))
        if let v = modelScale { f.append(EngineJSONField("modelScale", .number(v))) }
        if let v = namedStyleTable { f.append(EngineJSONField("namedStyleTable", .string(v))) }
        f.append(EngineJSONField("plotArea", .string(plotArea)))
        f.append(EngineJSONField("plotStamp", .bool(plotStamp)))
        if let v = plotStyleTable { f.append(EngineJSONField("plotStyleTable", .string(v))) }
        if let v = plotWindow { f.append(EngineJSONField("plotWindow", EngineJSON.numbers(v))) }
        if let v = stampText { f.append(EngineJSONField("stampText", .string(v))) }
        return .object(f)
    }

    func store(in doc: inout ArchiDocument, layoutIndex: Int?) {
        let k = EnginePageSetup.key(doc, layoutIndex: layoutIndex)
        if self == EnginePageSetup() { doc.variables[k] = nil; return }
        doc.variables[k] = json.serialized
    }

    /// Colour-dependent plot style tables: built-in (PlotStyleTable.builtIn) then the drawing's ("PLOTSTYLE:" variables).
    static func plotStyleTables(_ doc: ArchiDocument) -> [String] {
        var custom: [String] = []
        for k in doc.variables.keys.sorted() where k.hasPrefix("PLOTSTYLE:") {
            if let j = try? EngineJSON.parse(doc.variables[k] ?? ""), let n = j["name"]?.stringValue { custom.append(n) }
        }
        let builtIn = ["monochrome.ctb", "grayscale.ctb", "archi pens.ctb"].filter { b in !custom.contains { $0.lowercased() == b } }
        return builtIn + custom
    }

    /// Named plot style tables (NamedPlotStyles.tables): the default table then the drawing's ("STB:" variables).
    static func namedStyleTables(_ doc: ArchiDocument) -> [String] {
        var out: [String] = ["archi named.stb"]
        for k in doc.variables.keys.sorted() where k.hasPrefix("STB:") {
            let n = String(k.dropFirst(4))
            if !out.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { out.append(n) }
        }
        return out
    }
}

/// ISO A, ANSI and ARCH paper sizes after the core list (PaperCatalog.builtIn in the Mac app).
enum EnginePaperCatalog {
    static var builtIn: [PaperSize] {
        var out = PaperSize.standard
        let extra: [(String, Double, Double)] = [
            ("A4", 297, 210), ("A3", 420, 297), ("A2", 594, 420), ("A1", 841, 594), ("A0", 1189, 841),
            ("ANSI A", 279.4, 215.9), ("ANSI B", 431.8, 279.4), ("ANSI C", 558.8, 431.8), ("ANSI D", 863.6, 558.8), ("ANSI E", 1117.6, 863.6),
            ("ARCH A", 304.8, 228.6), ("ARCH B", 457.2, 304.8), ("ARCH C", 609.6, 457.2), ("ARCH D", 914.4, 609.6), ("ARCH E1", 1066.8, 762), ("ARCH E", 1219.2, 914.4),
        ]
        for e in extra where !out.contains(where: { $0.name == e.0 }) { out.append(PaperSize(name: e.0, width: e.1, height: e.2)) }
        return out
    }
    static func all(_ doc: ArchiDocument) -> [PaperSize] {
        var values = builtIn
        let custom = doc.variables.filter { $0.key.hasPrefix("CUSTOMPAPER:") }.compactMap { k, v -> PaperSize? in
            let a = v.split(separator: ",").compactMap { Double($0) }
            guard a.count == 2, a.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
            return PaperSize(name: String(k.dropFirst("CUSTOMPAPER:".count)), width: a[0], height: a[1])
        }
        for p in custom.sorted(by: { $0.name < $1.name }) + doc.layouts.map(\.paper) {
            let name = p.name.hasSuffix(" portrait") ? String(p.name.dropLast(" portrait".count)) : p.name
            if !values.contains(where: { $0.name == name }) { values.append(PaperSize(name: name, width: max(p.width, p.height), height: min(p.width, p.height))) }
        }
        return values
    }
    static func find(_ name: String) -> PaperSize? {
        builtIn.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
