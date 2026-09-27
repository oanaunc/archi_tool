// Oanarina Archi Tool — GPL-3.0-or-later
// Side-panel data for the Windows shell (Layers, Levels, Properties, Materials, Sheets, History) and panel edits
// (panel.set), each edit one undo step with the same labels as the Mac panels (ArchiApp/PanelsView.swift).
import Foundation

extension EngineSession {
    // MARK: Read

    func layerUsage() -> [String: Int] {
        var u: [String: Int] = [:]
        let doc = editor.doc
        for e in doc.entities { u[e.layer.uppercased(), default: 0] += 1 }
        for e in doc.elements { u[e.layer.uppercased(), default: 0] += 1 }
        for b in doc.blocks.values { for e in b.entities { u[e.layer.uppercased(), default: 0] += 1 } }
        return u
    }

    func panelLayers() -> EngineJSON {
        let doc = editor.doc
        let usage = layerUsage()
        var rows: [EngineJSON] = []
        for l in doc.layers {
            var o = EngineObject()
            o.set("name", l.name)
            o.set("color", EngineDrawJSON.hex(l.color))
            o.set("linetype", l.linetype)
            o.set("lineweight", l.lineweight)
            o.set("visible", l.visible)
            o.set("frozen", l.frozen)
            o.set("locked", l.locked)
            o.set("plot", l.plot)
            o.set("transparency", l.transparency)
            o.set("description", l.description)
            let n = usage[l.name.uppercased()] ?? 0
            o.set("count", n)
            o.set("current", l.name == doc.currentLayer)
            o.set("canDelete", l.name != "0" && l.name.caseInsensitiveCompare(doc.currentLayer) != .orderedSame && n == 0)
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("current", doc.currentLayer)
        o.set("layers", EngineJSON.array(rows))
        o.set("linetypes", EngineJSON.strings(doc.linetypes.map(\.name)))
        return o.json
    }

    func panelLevels() -> EngineJSON {
        let doc = editor.doc
        var counts: [Int: Int] = [:]
        for el in doc.elements { counts[el.level, default: 0] += 1 }
        var rows: [EngineJSON] = []
        for l in doc.levels.sorted(by: { $0.elevation > $1.elevation }) {
            var o = EngineObject()
            o.set("id", l.id)
            o.set("name", l.name)
            o.set("elevation", l.elevation)
            o.set("height", l.height)
            o.set("elements", counts[l.id] ?? 0)
            o.set("current", l.id == doc.currentLevel)
            o.set("canDelete", doc.levels.count > 1 && (counts[l.id] ?? 0) == 0)
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("current", doc.level(doc.currentLevel)?.name ?? "")
        o.set("currentId", doc.currentLevel)
        o.set("units", doc.units.abbreviation)
        o.set("levels", EngineJSON.array(rows))
        return o.json
    }

    /// Properties common to the selection (*VARIES* where they differ), or the project/drawing info with no selection.
    func panelProperties() -> EngineJSON {
        let doc = editor.doc
        let ids = editor.selection.sorted()
        var o = EngineObject()
        o.set("ids", EngineJSON.ints(ids))
        let s = summary(ids)
        o.set("summary", s.text)
        o.set("types", s.types)
        if ids.isEmpty {
            var p = EngineObject()
            p.set("name", doc.info.name)
            p.set("number", doc.info.number)
            p.set("client", doc.info.client)
            p.set("address", doc.info.address)
            p.set("author", doc.info.author)
            o.set("project", p.json)
            var d = EngineObject()
            d.set("units", doc.units.rawValue)
            d.set("currentLayer", doc.currentLayer)
            d.set("currentLevel", doc.level(doc.currentLevel)?.name ?? "—")
            d.set("objects", doc.entities.count)
            d.set("elements", doc.elements.count)
            d.set("layers", doc.layers.count)
            d.set("blocks", doc.blocks.count)
            d.set("file", editor.fileURL?.lastPathComponent ?? "Not saved")
            o.set("drawing", d.json)
            o.set("rows", EngineJSON.array([]))
            return o.json
        }
        var rows: [(name: String, value: String, readOnly: Bool)] = []
        var first = true
        for id in ids.prefix(300) {
            let ps = PropertyAccess.properties(of: id, in: doc)
            if first { rows = ps; first = false; continue }
            let names = Set(ps.map(\.name))
            rows.removeAll { !names.contains($0.name) }
            for p in ps {
                guard let k = rows.firstIndex(where: { $0.name == p.name }) else { continue }
                if rows[k].value != p.value { rows[k].value = "*VARIES*" }
                if p.readOnly { rows[k].readOnly = true }
            }
        }
        if ids.count > 1 { rows.removeAll { $0.name == "id" } }
        var out: [EngineJSON] = []
        for r in rows {
            var ro = EngineObject()
            ro.set("name", r.name)
            ro.set("value", r.value)
            ro.set("readOnly", r.readOnly)
            out.append(ro.json)
        }
        o.set("rows", EngineJSON.array(out))
        return o.json
    }

    func panelMaterials() -> EngineJSON {
        let doc = editor.doc
        var used: [String: Int] = [:]
        for el in doc.elements { if let m = el.material { used[m, default: 0] += 1 } }
        var rows: [EngineJSON] = []
        for m in doc.materials {
            var o = EngineObject()
            o.set("name", m.name)
            o.set("color", EngineDrawJSON.hex(m.color))
            o.set("roughness", m.roughness)
            o.set("metalness", m.metalness)
            o.set("transparency", m.transparency)
            o.set("texture", EngineJSON.optString(m.texture))
            o.set("textureScale", m.textureScale)
            o.set("cutPattern", m.cutPattern)
            o.set("uses", used[m.name] ?? 0)
            rows.append(o.json)
        }
        return .object([EngineJSONField("materials", .array(rows))])
    }

    func panelSheets() -> EngineJSON {
        let doc = editor.doc
        var rows: [EngineJSON] = []
        for (i, l) in doc.layouts.enumerated() {
            var o = EngineObject()
            o.set("index", i)
            o.set("name", l.name)
            var p = EngineObject()
            p.set("name", l.paper.name)
            p.set("width", l.paper.width)
            p.set("height", l.paper.height)
            o.set("paper", p.json)
            o.set("viewports", l.viewports.count)
            var tb: [EngineJSONField] = []
            for (k, v) in l.titleBlock.sorted(by: { $0.key < $1.key }) { tb.append(EngineJSONField(k, .string(v))) }
            o.set("titleBlock", EngineJSON.object(tb))
            rows.append(o.json)
        }
        var o = EngineObject()
        o.set("current", doc.variable("CTAB") ?? "Model")
        o.set("sheets", EngineJSON.array(rows))
        o.set("papers", EngineJSON.strings(PaperSize.standard.map(\.name)))
        return o.json
    }

    func panelHistory(_ p: EngineJSON) -> EngineJSON {
        let h = editor.history
        var o = EngineObject()
        o.set("undo", EngineJSON.strings(h.undoStack.map(\.label)))
        o.set("redo", EngineJSON.strings(h.redoStack.map(\.label)))
        o.set("canUndo", h.canUndo)
        o.set("canRedo", h.canRedo)
        o.set("undoLabel", EngineJSON.optString(h.undoLabel))
        o.set("redoLabel", EngineJSON.optString(h.redoLabel))
        o.set("commands", EngineJSON.strings(Array(editor.commandHistory.suffix(max(1, p["limit"]?.intValue ?? 100)))))
        o.set("dirty", editor.isDirty)
        return o.json
    }

    // MARK: Write

    /// Edits one panel value. Keys: layers — "current", "new", "delete", "<layer>.<field>"; levels — "current", "new",
    /// "delete", "<level>.<name|elevation|height>"; properties — "<property>" (selection) or "project.<field>";
    /// materials — "<material>.<field>", "new"; sheets — "current", "new", "delete", "<sheet>.name|paper"; history — "undoTo".
    func panelSet(_ p: EngineJSON) throws -> EngineJSON {
        let panel = try string(p, "panel").lowercased()
        let key = try string(p, "key")
        let value = p["value"]?.stringValue ?? ""
        switch panel {
        case "layers": try setLayer(key, value); return panelLayers()
        case "levels": try setLevel(key, value); return panelLevels()
        case "properties": try setProperty(key, value); return panelProperties()
        case "materials": try setMaterial(key, value); return panelMaterials()
        case "sheets": try setSheet(key, value); return panelSheets()
        case "history":
            guard key == "undoTo", let n = Int(value), n >= 0 else { throw EngineError.params("history: key 'undoTo' with the number of steps to keep") }
            while editor.history.undoStack.count > n { editor.undo() }
            return panelHistory(.object([]))
        default: throw EngineError.params("unknown panel '\(panel)'")
        }
    }

    /// Splits "<name>.<field>" at the last dot (names may contain dots).
    func split(_ key: String) -> (String, String)? {
        guard let dot = key.lastIndex(of: ".") else { return nil }
        return (String(key[..<dot]), String(key[key.index(after: dot)...]).lowercased())
    }

    func setLayer(_ key: String, _ value: String) throws {
        let doc = editor.doc
        switch key.lowercased() {
        case "current":
            guard let l = doc.layer(named: value) else { throw EngineError.params("no layer '\(value)'") }
            editor.transaction("Current Layer") { $0.currentLayer = l.name }
            return
        case "new":
            var name = value.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { var i = 1; while doc.layer(named: "Layer\(i)") != nil { i += 1 }; name = "Layer\(i)" }
            guard doc.layer(named: name) == nil else { throw EngineError.failed("A layer named \"\(name)\" already exists.") }
            editor.transaction("New Layer") { $0.layers.append(Layer(name: name)) }
            return
        case "delete":
            let n = layerUsage()[value.uppercased()] ?? 0
            guard value != "0", value.caseInsensitiveCompare(doc.currentLayer) != .orderedSame, n == 0, doc.layer(named: value) != nil else {
                throw EngineError.failed("Layer \"\(value)\" cannot be deleted (layer 0, current or in use).")
            }
            editor.transaction("Delete Layer") { d in d.layers.removeAll { $0.name == value } }
            return
        default: break
        }
        guard let (name, field) = split(key), let layer = doc.layer(named: name) else { throw EngineError.params("unknown layer key '\(key)'") }
        let n = layer.name
        if field == "name" {
            let new = value.trimmingCharacters(in: .whitespaces)
            guard !new.isEmpty, new != n else { return }
            if doc.layer(named: new) != nil && new.caseInsensitiveCompare(n) != .orderedSame { throw EngineError.failed("A layer named \"\(new)\" already exists.") }
            editor.transaction("Rename Layer") { d in
                guard let i = d.layerIndex(n) else { return }
                d.layers[i].name = new
                for k in d.entities.indices where d.entities[k].layer == n { d.entities[k].layer = new }
                for k in d.elements.indices where d.elements[k].layer == n { d.elements[k].layer = new }
                for bk in d.blocks.keys {
                    guard var b = d.blocks[bk] else { continue }
                    for k in b.entities.indices where b.entities[k].layer == n { b.entities[k].layer = new }
                    d.blocks[bk] = b
                }
                if d.currentLayer == n { d.currentLayer = new }
            }
            return
        }
        var l = layer
        let flag = SystemVariables.parseFlag(value)
        switch field {
        case "visible", "on": guard let f = flag else { throw EngineError.params("\(field) needs true/false") }; l.visible = f
        case "frozen": guard let f = flag else { throw EngineError.params("frozen needs true/false") }; l.frozen = f
        case "locked": guard let f = flag else { throw EngineError.params("locked needs true/false") }; l.locked = f
        case "plot": guard let f = flag else { throw EngineError.params("plot needs true/false") }; l.plot = f
        case "color": l.color = RGBA(hex: value)
        case "linetype": l.linetype = value
        case "lineweight": guard let x = InputParser.parseNumber(value), x >= 0 else { throw EngineError.params("lineweight needs a number") }; l.lineweight = x
        case "transparency": guard let x = InputParser.parseNumber(value) else { throw EngineError.params("transparency needs a number") }; l.transparency = min(max(x, 0), 90)
        case "description": l.description = value
        default: throw EngineError.params("unknown layer field '\(field)'")
        }
        let updated = l
        editor.transaction("Layer \(n)") { d in if let i = d.layerIndex(n) { d.layers[i] = updated } }
        let sel = editor.selection
        if !sel.isEmpty { editor.selection = sel.filter { editor.isSelectable($0) } }
    }

    func levelID(_ s: String) -> Int? {
        let doc = editor.doc
        if let l = doc.levels.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return l.id }
        if let i = Int(s), doc.level(i) != nil { return i }
        return nil
    }

    func setLevel(_ key: String, _ value: String) throws {
        let doc = editor.doc
        switch key.lowercased() {
        case "current":
            guard let id = levelID(value) else { throw EngineError.params("no level '\(value)'") }
            guard doc.currentLevel != id else { return }
            editor.selection = []
            editor.transaction("Current Level") { $0.currentLevel = id }
            return
        case "new":
            editor.transaction("Add Level") { d in
                let top = d.levels.max { $0.elevation < $1.elevation }
                let id = (d.levels.map(\.id).max() ?? -1) + 1
                let elev = (top?.elevation ?? 0) + (top?.height ?? 3000)
                let name = value.trimmingCharacters(in: .whitespaces).isEmpty ? "Level \(id)" : value
                d.levels.append(Level(id: id, name: name, elevation: elev, height: top?.height ?? 3000))
            }
            return
        case "delete":
            guard let id = levelID(value) else { throw EngineError.params("no level '\(value)'") }
            guard doc.levels.count > 1, !doc.elements.contains(where: { $0.level == id }) else {
                throw EngineError.failed("Level has elements — move or delete them first.")
            }
            editor.transaction("Delete Level") { d in
                d.levels.removeAll { $0.id == id }
                if d.currentLevel == id { d.currentLevel = d.levels.min { $0.elevation < $1.elevation }?.id ?? 0 }
            }
            return
        default: break
        }
        guard let (name, field) = split(key), let id = levelID(name) else { throw EngineError.params("unknown level key '\(key)'") }
        switch field {
        case "name":
            editor.transaction("Edit Level") { d in if let i = d.levels.firstIndex(where: { $0.id == id }) { d.levels[i].name = value } }
        case "elevation":
            guard let x = InputParser.parseNumber(value) else { throw EngineError.params("elevation needs a number") }
            editor.transaction("Edit Level") { d in if let i = d.levels.firstIndex(where: { $0.id == id }) { d.levels[i].elevation = x } }
        case "height":
            guard let x = InputParser.parseNumber(value), x > 0 else { throw EngineError.params("height needs a positive number") }
            editor.transaction("Edit Level") { d in if let i = d.levels.firstIndex(where: { $0.id == id }) { d.levels[i].height = x } }
        default: throw EngineError.params("unknown level field '\(field)'")
        }
    }

    func setProperty(_ key: String, _ value: String) throws {
        if key.lowercased().hasPrefix("project.") {
            let f = String(key.dropFirst(8)).lowercased()
            let known: Set<String> = ["name", "number", "client", "address", "author"]
            guard known.contains(f) else { throw EngineError.params("unknown project field '\(f)'") }
            editor.transaction("Project Info") { d in
                switch f {
                case "name": d.info.name = value
                case "number": d.info.number = value
                case "client": d.info.client = value
                case "address": d.info.address = value
                default: d.info.author = value
                }
            }
            return
        }
        let ids = editor.selection.sorted()
        guard !ids.isEmpty else { throw EngineError.failed("Nothing selected.") }
        var failed = 0
        editor.transaction("Properties") { d in
            for id in ids where !PropertyAccess.set(key, value, of: id, in: &d) { failed += 1 }
        }
        if failed > 0 { editor.print("Invalid value \"\(value)\" for \(key) (\(failed) object(s) unchanged).") }
    }

    func setMaterial(_ key: String, _ value: String) throws {
        let doc = editor.doc
        if key.lowercased() == "new" {
            let name = value.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !doc.materials.contains(where: { $0.name == name }) else { throw EngineError.failed("Material name missing or in use.") }
            editor.transaction("New Material") { $0.materials.append(Material(name: name, color: RGBA(0.8, 0.8, 0.8))) }
            return
        }
        guard let (name, field) = split(key), let idx = doc.materials.firstIndex(where: { $0.name == name }) else {
            throw EngineError.params("unknown material key '\(key)'")
        }
        var m = doc.materials[idx]
        let x = InputParser.parseNumber(value)
        switch field {
        case "color": m.color = RGBA(hex: value)
        case "roughness": guard let x else { throw EngineError.params("number needed") }; m.roughness = min(max(x, 0), 1)
        case "metalness": guard let x else { throw EngineError.params("number needed") }; m.metalness = min(max(x, 0), 1)
        case "transparency": guard let x else { throw EngineError.params("number needed") }; m.transparency = min(max(x, 0), 1)
        case "texture": m.texture = value.isEmpty ? nil : value
        case "texturescale": guard let x, x > 0 else { throw EngineError.params("positive number needed") }; m.textureScale = x
        case "cutpattern": m.cutPattern = value
        default: throw EngineError.params("unknown material field '\(field)'")
        }
        let updated = m
        editor.transaction("Edit Material") { d in if let i = d.materials.firstIndex(where: { $0.name == name }) { d.materials[i] = updated } }
    }

    func setSheet(_ key: String, _ value: String) throws {
        let doc = editor.doc
        switch key.lowercased() {
        case "current":
            let name = value.isEmpty ? "Model" : value
            guard name == "Model" || doc.layouts.contains(where: { $0.name == name }) else { throw EngineError.params("no sheet '\(value)'") }
            if doc.variable("CTAB") != name { editor.doc.setVariable("CTAB", name) }
            return
        case "new":
            var name = value.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { var i = doc.layouts.count + 1; while doc.layouts.contains(where: { $0.name == "Sheet \(i)" }) { i += 1 }; name = "Sheet \(i)" }
            guard !doc.layouts.contains(where: { $0.name == name }) else { throw EngineError.failed("A sheet named \"\(name)\" already exists.") }
            editor.transaction("New Sheet") { $0.layouts.append(Layout(name: name)) }
            return
        case "delete":
            guard doc.layouts.count > 1, doc.layouts.contains(where: { $0.name == value }) else { throw EngineError.failed("Cannot delete the sheet.") }
            editor.transaction("Delete Sheet") { d in d.layouts.removeAll { $0.name == value } }
            return
        default: break
        }
        guard let (name, field) = split(key), let idx = doc.layouts.firstIndex(where: { $0.name == name }) else {
            throw EngineError.params("unknown sheet key '\(key)'")
        }
        switch field {
        case "name":
            let new = value.trimmingCharacters(in: .whitespaces)
            guard !new.isEmpty, !doc.layouts.contains(where: { $0.name == new }) else { throw EngineError.failed("Sheet name missing or in use.") }
            editor.transaction("Rename Sheet") { $0.layouts[idx].name = new }
        case "paper":
            guard let paper = PaperSize.standard.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { throw EngineError.params("unknown paper '\(value)'") }
            editor.transaction("Sheet Paper") { $0.layouts[idx].paper = paper }
        default: throw EngineError.params("unknown sheet field '\(field)'")
        }
    }
}
