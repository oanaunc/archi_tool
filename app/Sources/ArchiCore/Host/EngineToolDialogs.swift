// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine methods behind the Windows dialogs and panels that the Mac app builds in its UI layer (ArchiApp):
// node editor / graph player (graph.*), block library (library.*), materials and material library (material.*,
// doc.edit, doc.variables), sheet set manager and title block (sheetset.*, titleblock.apply), markups (markup.*),
// family editor (family.*) and customizer (customizer.*). Each edit is one undo step with the Mac label.
// See docs/ENGINE-PROTOCOL.md, "Dialogs and tools".
import Foundation

/// Protocol methods of the tool windows and scripting (listed in engine.hello "methods").
public enum EngineToolMethods {
    public static let all: [String] = [
        "script.call", "agent.call", "agent.methods",
        "graph.get", "graph.evaluate", "graph.bake", "graph.save", "graph.load", "graph.delete", "graph.script",
        "library.scan", "library.preview", "library.insert", "blocks.list",
        "doc.edit", "doc.variables", "material.list", "sheetset.get", "sheetset.edit", "titleblock.get", "titleblock.apply",
        "markup.list", "markup.edit", "compare.run", "compare.save", "revcloud.list", "revcloud.add", "revcloud.remove",
        "family.list", "family.get", "family.template", "family.evaluate", "family.apply", "family.delete",
        "customizer.get", "customizer.set",
    ]
}

extension EngineSession {
    func callToolDialogs(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        do {
            switch method {
            case "graph.get": return graphGet()
            case "graph.evaluate": return try graphEvaluate(p)
            case "graph.bake": return try graphBake(p)
            case "graph.save": return try graphSave(p)
            case "graph.load": return try graphLoad(p)
            case "graph.delete": return try graphDelete(p)
            case "graph.script": return try graphScript(p)
            case "library.scan": return try libraryScan(p)
            case "library.preview": return try libraryPreview(p)
            case "library.insert": return try libraryInsert(p)
            case "blocks.list": return blocksList()
            case "doc.edit": return try docEdit(p)
            case "doc.variables": return docVariables(p)
            case "material.list": return materialList()
            case "sheetset.get": return sheetSetGet()
            case "sheetset.edit": return try sheetSetEdit(p)
            case "titleblock.get": return try titleBlockGet(p)
            case "titleblock.apply": return try titleBlockApply(p)
            case "markup.list": return markupList()
            case "markup.edit": return try markupEdit(p)
            case "family.list": return familyList()
            case "family.get": return try familyGet(p)
            case "family.template": return try familyTemplate(p)
            case "family.evaluate": return try familyEvaluate(p)
            case "family.apply": return try familyApply(p)
            case "family.delete": return try familyDelete(p)
            case "customizer.get": return customizerGet(p)
            case "customizer.set": return try customizerSet(p)
            case "compare.run": return try compareRun(p)
            case "compare.save": return try compareSave(p)
            case "revcloud.list": return revCloudList()
            case "revcloud.add": return try revCloudAdd(p)
            case "revcloud.remove": return try revCloudRemove(p)
            default: return nil
            }
        } catch let e as EngineError { throw e }
        catch { throw EngineError.failed(EngineSession.describe(error)) }
    }

    // MARK: Node graphs

    func graphGet() -> EngineJSON {
        let doc = editor.doc
        var o = EngineObject()
        o.set("graph", NodeGraph.load(doc).map { ScriptJSON.encode($0) } ?? .null)
        o.set("names", EngineJSON.strings(NodeGraph.names(doc)))
        var named: [EngineJSONField] = []
        for n in NodeGraph.names(doc) { if let g = NodeGraph.load(doc, name: n) { named.append(EngineJSONField(n, ScriptJSON.encode(g))) } }
        o.set("graphs", .object(named))
        o.set("sample", ScriptJSON.encode(NodeGraph.sample))
        o.set("baked", NodeGraphBake.bakedCount(doc))
        return o.json
    }

    func nodeKinds() -> EngineJSON {
        var out: [EngineJSON] = []
        for k in NodeKind.allCases {
            var o = EngineObject()
            o.set("kind", k.rawValue)
            o.set("title", k.title)
            o.set("category", k.category)
            o.set("output", k.output.rawValue)
            var ports: [EngineJSON] = []
            for pt in k.inputs {
                ports.append(ScriptJSON.object([("name", .string(pt.name)), ("type", .string(pt.type.rawValue)), ("default", .number(pt.defaultValue))]))
            }
            o.set("inputs", .array(ports))
            out.append(o.json)
        }
        return .array(out)
    }

    /// Temporary document holding graph output for the previews (at most 5000 objects and 2000 elements, as the Mac).
    func previewDocument(_ geometry: [Geometry], _ elements: [BIMGeometry]) -> ArchiDocument {
        var d = ArchiDocument()
        d.layers = [Layer(name: "0")]
        d.materials = editor.doc.materials
        for g in geometry.prefix(5000) { _ = d.add(g, layer: "0", color: .aci(2)) }
        for e in elements.prefix(2000) { _ = d.addElement(e) }
        return d
    }

    func planItems(_ d: ArchiDocument, level: Int?) -> (EngineJSON, BBox2) {
        var items: [EngineJSON] = []
        var b = BBox2.empty
        for e in DrawListBuilder.entries(doc: d, options: DrawOptions(level: level)) {
            b = b.union(e.bounds)
            for it in e.items { items.append(EngineDrawJSON.item(it, id: e.id)) }
        }
        return (.array(items), b)
    }

    func meshItems(_ d: ArchiDocument, only id: EntityID? = nil, zOffset: Double = 0) -> (EngineJSON, BBox3) {
        var out: [EngineJSON] = []
        var box = BBox3.empty
        for g0 in MeshBuilder.build(doc: d) {
            if let id, g0.id != id { continue }
            var g = g0
            if zOffset != 0 {
                g.mesh.positions = g.mesh.positions.map { Vec3($0.x, $0.y, $0.z - zOffset) }
                g.edges = g.edges.map { $0.map { Vec3($0.x, $0.y, $0.z - zOffset) } }
            }
            for q in g.mesh.positions { box.add(q) }
            out.append(EngineMeshJSON.group(g, mesh: g.mesh, doc: d))
        }
        return (.array(out), box)
    }

    func graphEvaluate(_ p: EngineJSON) throws -> EngineJSON {
        let g = try graph(from: p["graph"])
        let ev = g.evaluate()
        var nodes: [EngineJSONField] = []
        for n in g.nodes {
            var o = EngineObject()
            if let v = ev.values[n.id] { o.set("summary", v.summary); o.set("count", v.count) }
            if let e = ev.errors[n.id] { o.set("error", e) }
            nodes.append(EngineJSONField(String(n.id), o.json))
        }
        var o = EngineObject()
        o.set("nodes", .object(nodes))
        o.set("outputNodes", EngineJSON.ints(g.outputNodes))
        o.set("order", EngineJSON.ints(g.order))
        o.set("objects", ev.output.count)
        o.set("elements", ev.elementOutput.count)
        o.set("errors", ev.errors.count)
        let preview = p["preview"]?.stringValue ?? "none"
        if preview != "none" {
            let d = previewDocument(ev.output, ev.elementOutput)
            if preview.lowercased() == "plan" {
                let (items, b) = planItems(d, level: nil)
                o.set("items", items)
                o.set("bounds", b.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(b))
            } else {
                let (meshes, box) = meshItems(d)
                o.set("meshes", meshes)
                o.set("bounds", box.isEmpty ? EngineJSON.null : EngineJSON.array([EngineJSON.point3(box.min), EngineJSON.point3(box.max)]))
            }
        }
        if p["kinds"]?.boolValue == true { o.set("kinds", nodeKinds()) }
        if p["script"]?.boolValue == true { o.set("script", NodeGraphScript.javascript(g, name: p["name"]?.stringValue ?? "graph")) }
        return o.json
    }

    /// Bakes the graph output (replacing the previous bake); `store` also keeps the graph as the drawing's current graph.
    func graphBake(_ p: EngineJSON) throws -> EngineJSON {
        let g = try graph(from: p["graph"])
        let ev = g.evaluate()
        let store = p["store"]?.boolValue ?? true
        let label = p["label"]?.stringValue ?? "Node Graph"
        var ids: [EntityID] = []
        editor.transaction(label) { d in
            ids = NodeGraphBake.bake(ev.output, elements: ev.elementOutput, into: &d)
            if store { g.store(in: &d) }
        }
        var o = EngineObject()
        o.set("ids", EngineJSON.ints(ids))
        var errs: [EngineJSONField] = []
        for k in ev.errors.keys.sorted() { errs.append(EngineJSONField(String(k), .string(ev.errors[k] ?? ""))) }
        o.set("errors", .object(errs))
        return o.json
    }

    func graphSave(_ p: EngineJSON) throws -> EngineJSON {
        let g = try graph(from: p["graph"])
        let name = (p["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        editor.transaction("Save Node Graph") { d in
            if name.isEmpty { g.store(in: &d) } else { g.store(in: &d, name: name) }
        }
        return graphGet()
    }

    func graphLoad(_ p: EngineJSON) throws -> EngineJSON {
        let name = p["name"]?.stringValue ?? ""
        guard let g = NodeGraph.load(editor.doc, name: name) else { throw EngineError.failed("No graph named \(name)") }
        return ScriptJSON.encode(g)
    }

    func graphDelete(_ p: EngineJSON) throws -> EngineJSON {
        let name = p["name"]?.stringValue ?? ""
        editor.transaction("Delete Node Graph") { NodeGraph.delete(name, in: &$0) }
        return graphGet()
    }

    func graphScript(_ p: EngineJSON) throws -> EngineJSON {
        let g = try graph(from: p["graph"])
        return .string(NodeGraphScript.javascript(g, name: p["name"]?.stringValue ?? "graph"))
    }

    // MARK: Block library

    func libraryItemJSON(_ i: BlockLibrary.Item) -> EngineJSON {
        var o = EngineObject()
        o.set("file", i.file.path)
        o.set("block", EngineJSON.optString(i.block))
        o.set("name", i.name)
        o.set("folder", i.folder)
        o.set("key", i.file.path + "\u{1F}" + (i.block ?? ""))
        return o.json
    }

    func libraryScan(_ p: EngineJSON) throws -> EngineJSON {
        let folder = try string(p, "folder")
        let root = url(folder)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { throw EngineError.failed("Folder not found: " + root.path) }
        let recursive = p["recursive"]?.boolValue ?? true
        let items = BlockLibrary.scan(root, recursive: recursive)
        return ScriptJSON.object([("folder", .string(root.path)), ("items", .array(items.map { libraryItemJSON($0) }))])
    }

    func libraryItem(_ p: EngineJSON) throws -> BlockLibrary.Item {
        let file = url(try string(p, "file"))
        guard FileManager.default.fileExists(atPath: file.path) else { throw EngineError.failed("File not found: " + file.path) }
        var block = p["block"]?.stringValue
        if block?.isEmpty == true { block = nil }
        return BlockLibrary.Item(file: file, block: block, folder: p["folder"]?.stringValue ?? "")
    }

    /// Draw items of a library item (the whole drawing, or one reference of the block at its base point) for thumbnails.
    func libraryPreview(_ p: EngineJSON) throws -> EngineJSON {
        let i = try libraryItem(p)
        let src = try FileImport.load(i.file).0
        var d = src
        if let b = i.block, let blk = src.blocks[b] {
            d.entities = []
            d.elements = []
            _ = d.add(.insert(InsertGeom(block: b, position: blk.basePoint)), layer: src.layers.first?.name ?? "0")
        }
        let (items, b) = planItems(d, level: d.currentLevel)
        return ScriptJSON.object([("items", items), ("bounds", b.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(b))])
    }

    func libraryInsert(_ p: EngineJSON) throws -> EngineJSON {
        let i = try libraryItem(p)
        let at = Vec2(p["x"]?.doubleValue ?? 0, p["y"]?.doubleValue ?? 0)
        var id: EntityID?
        var failure: String?
        editor.transaction("Insert " + i.name) { d in
            do {
                let name = try BlockLibrary.load(i, into: &d)
                id = d.add(.insert(InsertGeom(block: name, position: at)), layer: d.currentLayer)
            } catch { failure = EngineSession.describe(error) }
        }
        if let failure {
            editor.print("Could not load \(i.name): \(failure)")
            throw EngineError.failed("Could not load \(i.name): \(failure)")
        }
        guard let id else { throw EngineError.failed("Nothing inserted") }
        editor.selection = [id]
        editor.print("Inserted \(i.name) from the block library at \(fmt(at.x, 2)),\(fmt(at.y, 2)).")
        return ScriptJSON.object([("id", .int(id)), ("name", .string(i.name))])
    }

    func blocksList() -> EngineJSON {
        var out: [EngineJSON] = []
        let doc = editor.doc
        var uses: [String: Int] = [:]
        for e in doc.entities { if case .insert(let g) = e.geometry { uses[g.block, default: 0] += 1 } }
        for k in doc.blocks.keys.sorted() where !k.hasPrefix("*") {
            guard let b = doc.blocks[k] else { continue }
            var o = EngineObject()
            o.set("name", k)
            o.set("description", b.description)
            o.set("basePoint", EngineJSON.point(b.basePoint))
            o.set("entities", b.entities.count)
            o.set("uses", uses[k] ?? 0)
            out.append(o.json)
        }
        return .array(out)
    }

    // MARK: Generic document edits (materials, variables, project info, title blocks)

    /// `doc.edit {label, ops:[…], merge?}`: applies the operations as one undo step. With `merge` and the same label
    /// as the last step the change joins it (slider drags), as the Mac material editor does.
    func docEdit(_ p: EngineJSON) throws -> EngineJSON {
        let label = try string(p, "label")
        let ops = p["ops"]?.arrayValue ?? []
        let merge = p["merge"]?.boolValue ?? false
        var d = editor.doc
        var messages: [String] = []
        for op in ops { try applyOp(op, &d, &messages) }
        if merge && editor.history.undoLabel == label {
            if d != editor.doc { editor.doc = d; editor.isDirty = true }
        } else {
            let result = d
            editor.transaction(label) { $0 = result }
        }
        return ScriptJSON.object([("ok", .bool(true)), ("messages", EngineJSON.strings(messages))])
    }

    func applyOp(_ op: EngineJSON, _ d: inout ArchiDocument, _ messages: inout [String]) throws {
        let kind = op["op"]?.stringValue ?? ""
        switch kind {
        case "setVariable":
            let name = try string(op, "name")
            if let v = op["value"], !v.isNull { d.variables[name] = v.stringValue ?? "" } else { d.variables[name] = nil }
        case "setInfo":
            var info = ScriptJSON.encode(d.info)
            for f in op["info"]?.fields ?? [] { info = ScriptJSON.setting(info, f.key, f.value) }
            d.info = try ScriptJSON.decode(ProjectInfo.self, from: info)
        case "setTitleBlock":
            let li = op["layout"]?.intValue ?? -1
            guard d.layouts.indices.contains(li) else { throw EngineError.params("no sheet \(li)") }
            let key = try string(op, "key")
            if let v = op["value"], !v.isNull, let s = v.stringValue, !s.isEmpty { d.layouts[li].titleBlock[key] = s } else { d.layouts[li].titleBlock[key] = nil }
        case "setMaterial":
            let name = try string(op, "name")
            let m = try ScriptJSON.decode(Material.self, from: op["material"] ?? .null)
            if let i = d.materials.firstIndex(where: { $0.name == name }) { d.materials[i] = m } else { d.materials.append(m) }
        case "addMaterial":
            let m = try ScriptJSON.decode(Material.self, from: op["material"] ?? .null)
            if d.material(m.name) == nil { d.materials.append(m); messages.append("Added " + m.name + ".") }
            else { messages.append(m.name + " is already in the drawing.") }
        case "removeMaterial":
            let name = try string(op, "name")
            d.materials.removeAll { $0.name == name }
        case "renameMaterial":
            let old = try string(op, "from"), new = try string(op, "to")
            if let i = d.materials.firstIndex(where: { $0.name == old }) { d.materials[i].name = new }
            for i in d.elements.indices where d.elements[i].material?.caseInsensitiveCompare(old) == .orderedSame { d.elements[i].material = new }
            for suffix in ["MATMAPS:", "MATASSET:", "MATBUMP:", "MATPROC:", "MATEMIT:"] {
                if let v = d.variables[suffix + old.uppercased()] { d.variables[suffix + old.uppercased()] = nil; d.variables[suffix + new.uppercased()] = v }
            }
        case "assignMaterial":
            let name = try string(op, "name")
            let ids = Set(ScriptJSON.ids(op["ids"]))
            var n = 0
            for i in d.elements.indices where ids.contains(d.elements[i].id) { d.elements[i].material = name; n += 1 }
            messages.append("\(name) assigned to \(n) element(s).")
        default:
            throw EngineError.params("unknown doc.edit op '\(kind)'")
        }
    }

    func docVariables(_ p: EngineJSON) -> EngineJSON {
        let prefixes = (p["prefixes"]?.arrayValue ?? []).compactMap { $0.stringValue }
        let prefix = p["prefix"]?.stringValue
        var out: [EngineJSONField] = []
        for k in editor.doc.variables.keys.sorted() {
            if let prefix, !k.hasPrefix(prefix) { continue }
            if !prefixes.isEmpty && !prefixes.contains(where: { k.hasPrefix($0) }) { continue }
            out.append(EngineJSONField(k, .string(editor.doc.variables[k] ?? "")))
        }
        return .object(out)
    }

    /// Materials as stored (full Material JSON) with element usage, the maps/assets variables and the hatch names.
    func materialList() -> EngineJSON {
        let doc = editor.doc
        var usage: [String: Int] = [:]
        for el in doc.elements { if let m = el.material { usage[m.lowercased(), default: 0] += 1 } }
        var list: [EngineJSON] = []
        for m in doc.materials {
            var o = EngineObject()
            o.set("material", ScriptJSON.encode(m))
            o.set("uses", usage[m.name.lowercased()] ?? 0)
            let key = m.name.uppercased()
            o.set("maps", EngineJSON.optString(doc.variables["MATMAPS:" + key]))
            o.set("assets", EngineJSON.optString(doc.variables["MATASSET:" + key]))
            o.set("bump", EngineJSON.optString(doc.variables["MATBUMP:" + key]))
            list.append(o.json)
        }
        var o = EngineObject()
        o.set("materials", .array(list))
        o.set("patterns", EngineJSON.strings(HatchPatterns.names))
        o.set("library", ScriptJSON.encode(Material.library))
        o.set("folder", EngineJSON.optString(editor.fileURL?.deletingLastPathComponent().path))
        return o.json
    }

    // MARK: Sheet set manager

    func sheetJSON(_ i: Int) -> EngineJSON {
        let doc = editor.doc
        let l = doc.layouts[i]
        var o = EngineObject()
        o.set("index", i)
        o.set("name", l.name)
        o.set("number", EngineSheets.number(doc, i))
        o.set("title", EngineSheets.title(doc, i))
        o.set("paper", EngineSession.paperJSON(l.paper))
        o.set("viewports", l.viewports.count)
        var revs: [EngineJSON] = []
        for r in EngineSheets.revisions(l) {
            revs.append(ScriptJSON.object([("code", .string(r.code)), ("date", .string(r.date)), ("description", .string(r.description)), ("by", .string(r.by))]))
        }
        o.set("revisions", .array(revs))
        var tb: [EngineJSONField] = []
        for k in l.titleBlock.keys.sorted() { tb.append(EngineJSONField(k, .string(l.titleBlock[k] ?? ""))) }
        o.set("titleBlock", .object(tb))
        o.set("viewTitles", EngineSheets.hasViewTitleEntities(l))
        o.set("hasIndex", l.entities.contains { $0.props["sheetIndex"] != nil })
        return o.json
    }

    static func paperJSON(_ p: PaperSize) -> EngineJSON {
        var o = EngineObject()
        o.set("name", p.name)
        o.set("width", p.width)
        o.set("height", p.height)
        return o.json
    }

    func sheetSetGet() -> EngineJSON {
        let doc = editor.doc
        var o = EngineObject()
        o.set("sheets", .array(doc.layouts.indices.map { sheetJSON($0) }))
        o.set("papers", .array(PaperSize.standard.map { EngineSession.paperJSON($0) }))
        o.set("author", doc.info.author)
        o.set("current", doc.variable("CTAB") ?? "Model")
        return o.json
    }

    func sheetIndex(_ p: EngineJSON) throws -> Int {
        let i = p["index"]?.intValue ?? -1
        guard editor.doc.layouts.indices.contains(i) else { throw EngineError.params("no sheet \(i)") }
        return i
    }

    func sheetSetEdit(_ p: EngineJSON) throws -> EngineJSON {
        let op = try string(p, "op")
        var result = EngineObject()
        switch op {
        case "new":
            let pname = p["paper"]?.stringValue ?? "A3"
            let paper = PaperSize.standard.first { $0.name == pname } ?? PaperSize.standard[1]
            editor.transaction("New Sheet") { d in
                var n = d.layouts.count + 1
                while d.layouts.contains(where: { $0.name == "Sheet \(n)" }) { n += 1 }
                d.layouts.append(Layout(name: "Sheet \(n)", paper: paper))
                EngineSheets.refreshIndexes(&d)
            }
            result.set("index", editor.doc.layouts.count - 1)
        case "duplicate":
            let i = try sheetIndex(p)
            var ni: Int?
            editor.transaction("Duplicate Sheet") { d in ni = EngineSheets.duplicate(&d, i); EngineSheets.refreshIndexes(&d) }
            result.set("index", ni ?? i)
        case "move":
            let i = try sheetIndex(p)
            let to = p["to"]?.intValue ?? i
            editor.transaction("Reorder Sheets") { d in EngineSheets.move(&d, from: i, to: to); EngineSheets.refreshIndexes(&d) }
            result.set("index", max(0, min(to, editor.doc.layouts.count - 1)))
        case "delete":
            let i = try sheetIndex(p)
            guard editor.doc.layouts.count > 1 else { throw EngineError.failed("A drawing keeps at least one sheet.") }
            editor.transaction("Delete Sheet") { d in d.layouts.remove(at: i); EngineSheets.refreshIndexes(&d) }
            result.set("index", max(0, i - 1))
        case "rename":
            let i = try sheetIndex(p)
            let n = (p["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            let old = editor.doc.layouts[i].name
            if !n.isEmpty && n != old {
                if editor.doc.layouts.contains(where: { $0.name == n }) {
                    editor.print("A sheet named \(n) exists.")
                    throw EngineError.failed("A sheet named \(n) exists.")
                }
                editor.transaction("Rename Sheet") { d in
                    d.layouts[i].name = n
                    let ok = "VPLOCK:" + old.uppercased(), nk = "VPLOCK:" + n.uppercased()
                    if let v = d.variables[ok] { d.variables[ok] = nil; d.variables[nk] = v }
                    EngineSheets.refreshIndexes(&d)
                }
            }
            result.set("index", i)
        case "renumber":
            let prefix = p["prefix"]?.stringValue ?? "A-"
            let start = p["start"]?.intValue ?? 101
            editor.transaction("Renumber Sheets") { d in EngineSheets.renumber(&d, prefix: prefix, start: start); EngineSheets.refreshIndexes(&d) }
        case "index":
            let i = try sheetIndex(p)
            editor.transaction("Sheet Index") { d in _ = EngineSheets.placeIndex(&d, on: i) }
            result.set("index", i)
        case "viewTitles":
            let i = try sheetIndex(p)
            editor.transaction("View Titles") { d in EngineSheets.refreshViewTitles(&d, i) }
            result.set("index", i)
        case "addRevision":
            let i = try sheetIndex(p)
            let desc = (p["description"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else { throw EngineError.params("A revision needs a description.") }
            let byText = p["by"]?.stringValue ?? ""
            let by = byText.isEmpty ? editor.doc.info.author : byText
            editor.transaction("Add Revision") { d in EngineSheets.addRevision(&d, i, description: desc, by: by); EngineSheets.refreshIndexes(&d) }
            result.set("index", i)
        case "deleteRevision":
            let i = try sheetIndex(p)
            var revs = EngineSheets.revisions(editor.doc.layouts[i])
            let k = p["revision"]?.intValue ?? -1
            guard revs.indices.contains(k) else { throw EngineError.params("no revision \(k)") }
            revs.remove(at: k)
            let list = revs
            editor.transaction("Delete Revision") { d in EngineSheets.setRevisions(&d, i, list); EngineSheets.refreshIndexes(&d) }
            result.set("index", i)
        default:
            throw EngineError.params("unknown sheet set op '\(op)'")
        }
        result.set("sheets", sheetSetGet())
        return result.json
    }

    // MARK: Title block (TITLEBLOCK dialog)

    func titleBlockGet(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let li = p["layout"]?.intValue ?? 0
        guard doc.layouts.indices.contains(li) else { throw EngineError.params("no sheet \(li)") }
        var o = EngineObject()
        o.set("layout", li)
        o.set("name", doc.layouts[li].name)
        o.set("info", ScriptJSON.encode(doc.info))
        o.set("logo", doc.variables["TITLEBLOCKLOGO"] ?? "")
        var pc: [EngineJSONField] = []
        for (k, v) in EngineSheets.projectFields(doc) { pc.append(EngineJSONField(k, .string(v))) }
        o.set("projectCustom", .object(pc))
        var sc: [EngineJSONField] = []
        for k in doc.layouts[li].titleBlock.keys.sorted() where k.hasPrefix(EngineSheets.sheetPrefix) {
            sc.append(EngineJSONField(String(k.dropFirst(EngineSheets.sheetPrefix.count)), .string(doc.layouts[li].titleBlock[k] ?? "")))
        }
        o.set("sheetCustom", .object(sc))
        var fields: [EngineJSONField] = []
        var defaults: [EngineJSONField] = []
        for (k, _) in EngineSheets.sheetKeys + EngineSheets.projectOverrideKeys {
            if let v = doc.layouts[li].titleBlock[k] { fields.append(EngineJSONField(k, .string(v))) }
            defaults.append(EngineJSONField(k, .string(EngineSheets.defaultValue(doc, li, k))))
        }
        o.set("fields", .object(fields))
        o.set("defaults", .object(defaults))
        return o.json
    }

    /// Mirrors TitleBlockSheet.apply: project info, logo, custom fields, this sheet's fields and "apply to all sheets".
    func titleBlockApply(_ p: EngineJSON) throws -> EngineJSON {
        let li = p["layout"]?.intValue ?? 0
        guard editor.doc.layouts.indices.contains(li) else { throw EngineError.params("no sheet \(li)") }
        var info = ScriptJSON.encode(editor.doc.info)
        for f in p["info"]?.fields ?? [] { info = ScriptJSON.setting(info, f.key, f.value) }
        let newInfo = try ScriptJSON.decode(ProjectInfo.self, from: info)
        let logo = p["logo"]?.stringValue ?? ""
        let pc = ScriptJSON.stringDict(p["projectCustom"])
        let sc = ScriptJSON.stringDict(p["sheetCustom"])
        let f = ScriptJSON.stringDict(p["fields"])
        let all = Set((p["applyToAll"]?.arrayValue ?? []).compactMap { $0.stringValue })
        let keys = EngineSheets.sheetKeys + EngineSheets.projectOverrideKeys
        editor.transaction("Title Block") { d in
            d.info = newInfo
            d.variables["TITLEBLOCKLOGO"] = logo.isEmpty ? nil : logo
            for (k, _) in EngineSheets.projectFields(d) where pc[k] == nil { EngineSheets.setProjectField(&d, k, nil) }
            for (k, v) in pc { EngineSheets.setProjectField(&d, k, v.trimmingCharacters(in: .whitespaces)) }
            for (k, v) in sc { EngineSheets.setSheetField(&d, li, k, v.trimmingCharacters(in: .whitespaces)) }
            var tb = d.layouts[li].titleBlock
            for (k, _) in keys {
                let v = (f[k] ?? "").trimmingCharacters(in: .whitespaces)
                tb[k] = v.isEmpty ? nil : v
            }
            d.layouts[li].titleBlock = tb
            for k in all {
                let v = (f[k] ?? "").trimmingCharacters(in: .whitespaces)
                for j in d.layouts.indices where j != li { d.layouts[j].titleBlock[k] = v.isEmpty ? nil : v }
            }
        }
        return try titleBlockGet(p)
    }

    // MARK: Markups

    func markupList() -> EngineJSON {
        var out: [EngineJSON] = []
        for m in Markups.list(editor.doc) {
            var j = ScriptJSON.fromAny(AgentExtraTools.markupJSON(m))
            j = ScriptJSON.setting(j, "level", m.level.map { EngineJSON.int($0) } ?? .null)
            j = ScriptJSON.setting(j, "bounds", m.bounds.isEmpty ? .null : EngineDrawJSON.rect(m.bounds))
            j = ScriptJSON.setting(j, "resolved", .bool(m.isResolved))
            out.append(j)
        }
        return ScriptJSON.object([("markups", .array(out)), ("author", .string(Markups.author(editor.doc)))])
    }

    func markupEdit(_ p: EngineJSON) throws -> EngineJSON {
        let op = try string(p, "op")
        var result = EngineObject()
        switch op {
        case "reply":
            let id = try string(p, "id"), text = (p["text"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { throw EngineError.params("empty reply") }
            editor.transaction("Reply to Markup") { d in _ = Markups.reply(&d, id, text: text) }
        case "status":
            let id = try string(p, "id")
            let resolved = p["resolved"]?.boolValue ?? true
            editor.transaction(resolved ? "Resolve Markup" : "Reopen Markup") { d in _ = Markups.setStatus(&d, id, resolved: resolved) }
        case "remove":
            let id = try string(p, "id")
            editor.transaction("Delete Markup") { d in _ = Markups.remove(&d, id) }
        case "addAroundSelection":
            let doc = editor.doc
            var b = BBox2.empty
            for id in editor.selection {
                if let e = doc.entity(id) { b = b.union(GeometryOps.bounds(e.geometry, doc: doc)) }
                if let el = doc.element(id) { b = b.union(PlanRepresentation.bounds(el, doc: doc)) }
            }
            guard !b.isEmpty else { throw EngineError.failed("Select the objects to cloud first.") }
            let m = max(b.width, b.height, 100) * 0.1
            let ids = editor.selection.sorted()
            let comment = p["comment"]?.stringValue ?? "", title = p["title"]?.stringValue ?? ""
            var mid = ""
            let rect = (b.min - Vec2(m, m), b.max + Vec2(m, m))
            let level = doc.currentLevel
            editor.transaction("Add Markup") { d in mid = Markups.add(&d, rect: rect, title: title, comment: comment, elements: ids, level: level) }
            result.set("id", mid)
        default:
            throw EngineError.params("unknown markup op '\(op)'")
        }
        result.set("list", markupList())
        return result.json
    }

    // MARK: Family editor

    func familyList() -> EngineJSON {
        var out: [EngineJSON] = []
        for f in editor.doc.families {
            var o = EngineObject()
            o.set("name", f.name)
            o.set("category", f.category)
            o.set("instances", FamilyInstances.count(f.name, doc: editor.doc))
            o.set("types", f.types.count)
            out.append(o.json)
        }
        var o = EngineObject()
        o.set("families", .array(out))
        o.set("parameterKinds", EngineJSON.strings(FamilyParameterKind.allCases.map { $0.rawValue }))
        o.set("formKinds", EngineJSON.strings(FamilyFormKind.allCases.map { $0.rawValue }))
        o.set("materials", EngineJSON.strings(editor.doc.materials.map { $0.name }))
        o.set("current", EngineJSON.optString(editor.doc.variable("CURRENTFAMILY")))
        return o.json
    }

    func familyGet(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard let d = editor.doc.family(named: name) else { throw EngineError.failed("No family named \(name)") }
        return ScriptJSON.encode(d)
    }

    static func uniqueFamilyName(_ base: String, in doc: ArchiDocument) -> String {
        func taken(_ n: String) -> Bool { doc.families.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
        if !taken(base) { return base }
        var k = 2
        while taken("\(base) \(k)") { k += 1 }
        return "\(base) \(k)"
    }

    /// New family drafts from the editor's templates (Generic Model, Door, Window, Furniture), as FamilyEditorModel.newFamily.
    func familyTemplate(_ p: EngineJSON) throws -> EngineJSON {
        let t = p["template"]?.stringValue ?? "Generic Model"
        let name = EngineSession.uniqueFamilyName(t == "Generic Model" ? "Family" : t, in: editor.doc)
        var d: FamilyDefinition
        switch t {
        case "Door": d = FamilyTemplates.door(name: name)
        case "Window": d = FamilyTemplates.window(name: name)
        case "Furniture": d = EngineSession.furnitureTemplate(name)
        default: d = EngineSession.genericTemplate(name)
        }
        d.name = name
        return ScriptJSON.encode(d)
    }

    static func genericTemplate(_ name: String) -> FamilyDefinition {
        let params = [FamilyParameter("Width", value: "600"), FamilyParameter("Depth", value: "600"), FamilyParameter("Height", value: "900")]
        let dims: [String: String] = ["width": "Width", "depth": "Depth", "height": "Height"]
        let body = FamilyForm(.box, name: "Body", x: "-Width/2", y: "-Depth/2", dims: dims)
        return FamilyDefinition(name: name, category: "Generic Model", parameters: params, forms: [body])
    }

    static func furnitureTemplate(_ name: String) -> FamilyDefinition {
        var params: [FamilyParameter] = [FamilyParameter("Width", value: "1600"), FamilyParameter("Depth", value: "900"), FamilyParameter("Height", value: "750")]
        params.append(FamilyParameter("Top", value: "40", instance: false))
        params.append(FamilyParameter("Leg", value: "60", instance: false))
        params.append(FamilyParameter("Inset", value: "50", instance: false))
        let topDims: [String: String] = ["width": "Width", "depth": "Depth", "height": "Top"]
        let legDims: [String: String] = ["width": "Leg", "depth": "Leg", "height": "Height - Top"]
        let top = FamilyForm(.box, name: "Top", x: "-Width/2", y: "-Depth/2", z: "Height - Top", dims: topDims)
        let legs = FamilyForm(.box, name: "Legs", x: "-Width/2 + Inset", y: "-Depth/2 + Inset", dims: legDims, arrayCount: "2", arrayDX: "Width - 2*Inset - Leg")
        let back = FamilyForm(.box, name: "Legs back", x: "-Width/2 + Inset", y: "Depth/2 - Inset - Leg", dims: legDims, arrayCount: "2", arrayDX: "Width - 2*Inset - Leg")
        var types: [String: [String: String]] = [:]
        types["1600 x 900"] = ["Width": "1600", "Depth": "900"]
        types["1200 x 800"] = ["Width": "1200", "Depth": "800"]
        return FamilyDefinition(name: name, category: "Furniture", parameters: params, forms: [top, legs, back], types: types)
    }

    /// Validation, resolved values and preview meshes of a family draft (FamilyEditorModel.problems / previewGroups).
    func familyEvaluate(_ p: EngineJSON) throws -> EngineJSON {
        let draft = try ScriptJSON.decode(FamilyDefinition.self, from: p["draft"] ?? .null)
        let original = p["original"]?.stringValue
        let previewType = p["type"]?.stringValue
        var props: [String: String] = [:]
        if let t = previewType, !t.isEmpty { props["familyType"] = t }
        for (k, v) in ScriptJSON.stringDict(p["flex"]) where !v.trimmingCharacters(in: .whitespaces).isEmpty { props["fp." + k] = v }
        let doc = editor.doc
        var pd = doc
        pd.families.removeAll { $0.name.caseInsensitiveCompare(original ?? draft.name) == .orderedSame || $0.name.caseInsensitiveCompare(draft.name) == .orderedSame }
        pd.families.append(draft)
        let resolved = FamilyExpr.resolve(draft, overrides: FamilyEngine.overrides(props), type: previewType)
        var problems: [String] = []
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("The family needs a name.") }
        if doc.families.contains(where: { $0.name.caseInsensitiveCompare(draft.name) == .orderedSame && $0.name.caseInsensitiveCompare(original ?? "") != .orderedSame }) {
            problems.append("Another family is already called \(draft.name).")
        }
        var seen = Set<String>()
        for prm in draft.parameters {
            let k = prm.name.lowercased()
            if prm.name.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("A parameter has no name.") }
            else if seen.contains(k) { problems.append("Duplicate parameter \(prm.name).") }
            seen.insert(k)
            if !prm.kind.isNumeric, let e = prm.kind.validate(prm.value, families: doc.families) { problems.append("\(prm.name): \(e)") }
        }
        problems += resolved.errors
        let r = FamilyEngine.evaluate(draft, doc: pd, props: props)
        for e in r.errors where !problems.contains(e) { problems.append(e) }
        var values: [EngineJSONField] = []
        for k in resolved.values.keys.sorted() { values.append(EngineJSONField(k, .number(resolved.values[k] ?? 0))) }
        var texts: [EngineJSONField] = []
        for k in resolved.text.keys.sorted() { texts.append(EngineJSONField(k, .string(resolved.text[k] ?? ""))) }
        var o = EngineObject()
        o.set("problems", EngineJSON.strings(problems))
        o.set("values", .object(values))
        o.set("text", .object(texts))
        o.set("dirty", original.map { doc.family(named: $0) != draft } ?? true)
        if p["preview"]?.boolValue ?? true {
            pd.entities = []
            pd.elements = []
            let lv = pd.levels.first?.id ?? 0
            pd.currentLevel = lv
            let comp = ComponentGeom(category: draft.category, position: .zero, size: Vec3(1, 1, 1), family: draft.name)
            let id = pd.addElement(.component(comp), level: lv, name: draft.name)
            if let j = pd.elementIndex(id) { for (k, v) in props { pd.elements[j].props[k] = v } }
            let z0 = pd.level(lv)?.elevation ?? 0
            let (meshes, box) = meshItems(pd, only: id, zOffset: z0)
            o.set("meshes", meshes)
            o.set("bounds", box.isEmpty ? EngineJSON.null : EngineJSON.array([EngineJSON.point3(box.min), EngineJSON.point3(box.max)]))
        }
        return o.json
    }

    func familyApply(_ p: EngineJSON) throws -> EngineJSON {
        var def = try ScriptJSON.decode(FamilyDefinition.self, from: p["draft"] ?? .null)
        let old = p["original"]?.stringValue
        let name = def.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw EngineError.failed("The family needs a name.") }
        if editor.doc.families.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.name.caseInsensitiveCompare(old ?? "") != .orderedSame }) {
            throw EngineError.failed("Another family is already called \(name).")
        }
        def.name = name
        let newDef = def
        editor.transaction(old == nil ? "New Family \(name)" : "Edit Family \(name)") { doc in
            if let o = old, let i = doc.familyIndex(o) { doc.families[i] = newDef } else { doc.families.append(newDef) }
            if let o = old, o != name {
                for j in doc.elements.indices {
                    if case .component(var g) = doc.elements[j].geometry, g.family?.caseInsensitiveCompare(o) == .orderedSame {
                        g.family = name
                        doc.elements[j].geometry = .component(g)
                    }
                    if doc.elements[j].props["family"]?.caseInsensitiveCompare(o) == .orderedSame { doc.elements[j].props["family"] = name }
                }
                for k in doc.families.indices {
                    for f in doc.families[k].forms.indices where doc.families[k].forms[f].family?.caseInsensitiveCompare(o) == .orderedSame {
                        doc.families[k].forms[f].family = name
                    }
                }
            }
            FamilyInstances.updateAll(&doc)
            doc.setVariable("CURRENTFAMILY", name)
        }
        let n = FamilyInstances.count(name, doc: editor.doc)
        return ScriptJSON.object([("name", .string(name)), ("instances", .int(n)), ("message", .string("Applied \(name): \(n) instance(s) updated."))])
    }

    func familyDelete(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        let n = FamilyInstances.count(name, doc: editor.doc)
        guard n == 0 else { throw EngineError.failed("\(name) has \(n) instance(s); delete them first.") }
        editor.transaction("Delete Family \(name)") { doc in doc.families.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
        return ScriptJSON.object([("message", .string("Deleted \(name)."))])
    }

    // MARK: Customizer (scripted objects)

    func customizerTarget() -> (id: EntityID, script: String)? {
        let doc = editor.doc
        for id in editor.selection.sorted() {
            if let e = doc.entity(id), case .solid(let s) = e.geometry, let src = s.source, src.kind == .script, let code = src.expression { return (id, code) }
            if let el = doc.element(id), let code = ScriptedComponents.effectiveScript(el.props) { return (id, code) }
        }
        return nil
    }

    func customizerGet(_ p: EngineJSON) -> EngineJSON {
        guard let t = customizerTarget() else { return ScriptJSON.object([("target", .null)]) }
        var params: [EngineJSON] = []
        for prm in SCADCustomizer.parameters(t.script) {
            var o = EngineObject()
            o.set("name", prm.name)
            o.set("value", prm.value)
            o.set("kind", prm.kind.rawValue)
            o.set("min", prm.min.map { EngineJSON.number($0) } ?? .null)
            o.set("max", prm.max.map { EngineJSON.number($0) } ?? .null)
            o.set("step", prm.step.map { EngineJSON.number($0) } ?? .null)
            o.set("options", EngineJSON.strings(prm.options))
            o.set("description", prm.description)
            o.set("group", prm.group)
            params.append(o.json)
        }
        return ScriptJSON.object([("target", .int(t.id)), ("parameters", .array(params))])
    }

    /// Sets one parameter and regenerates the object (Customizer.set): one undo step "Customize <name>".
    func customizerSet(_ p: EngineJSON) throws -> EngineJSON {
        let id = p["id"]?.intValue ?? -1
        let name = try string(p, "name")
        let value = p["value"]?.stringValue ?? ""
        if editor.doc.element(id)?.props[ScriptedComponents.scriptKey] != nil {
            var d = editor.doc
            try ScriptedComponents.setParameter(id, name, value, doc: &d)
            let result = d
            editor.transaction("Customize \(name)") { $0 = result }
            return customizerGet(p)
        }
        guard let e = editor.doc.entity(id), case .solid(let s) = e.geometry, var src = s.source, let code = src.expression else {
            throw EngineError.failed("Not a scripted object.")
        }
        do { src.expression = try SCADCustomizer.set(code, name, value) }
        catch let err as SCADCustomizer.SetError { throw EngineError.failed(err.description) }
        guard var n = FeatureSources.build(src, doc: editor.doc) else { throw EngineError.failed("The script produces no solid with \(name) = \(value).") }
        n.source = src
        let solid = n
        editor.transaction("Customize \(name)") { d in
            if let i = d.entities.firstIndex(where: { $0.id == id }) { d.entities[i].geometry = .solid(solid) }
        }
        return customizerGet(p)
    }

    // MARK: Compare drawings (ComparePanel / CompareOverlay)

    static func boxLoop(_ b: BBox2) -> [Vec2] { [b.min, Vec2(b.max.x, b.min.y), b.max, Vec2(b.min.x, b.max.y), b.min] }

    /// Differences with another version: counts, layers, and per change the plan outlines to draw over the plan
    /// (removed objects come from the other file), as CompareOverlay.shapes.
    func compareRun(_ p: EngineJSON) throws -> EngineJSON {
        let u = url(try string(p, "path"))
        let old = try FileImport.load(u, reference: editor.doc).0
        let d = DocumentCompare.compare(old, editor.doc)
        var shapes: [EngineJSON] = []
        for c in d.differences {
            let doc = c.kind == .removed ? old : editor.doc
            var polys: [[Vec2]] = []
            if c.object == "entity", let e = doc.entity(c.id) { polys = Array(GeometryOps.tessellate(e.geometry, doc: doc).prefix(200)) }
            else if c.object == "element", let el = doc.element(c.id) {
                let b = PlanRepresentation.bounds(el, doc: doc)
                if !b.isEmpty { polys = [EngineSession.boxLoop(b)] }
            }
            if polys.isEmpty, !c.bounds.isEmpty { polys = [EngineSession.boxLoop(c.bounds)] }
            var o = EngineObject()
            o.set("kind", c.kind.rawValue)
            o.set("id", c.id)
            o.set("object", c.object)
            o.set("type", c.type)
            o.set("layer", c.layer)
            o.set("level", c.level.map { EngineJSON.int($0) } ?? .null)
            o.set("fields", EngineJSON.strings(c.fields))
            o.set("bounds", c.bounds.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(c.bounds))
            o.set("polylines", EngineJSON.array(polys.map { pl -> EngineJSON in EngineJSON.array(pl.map { EngineJSON.point($0) }) }))
            shapes.append(o.json)
        }
        var counts = EngineObject()
        for k in ChangeKind.allCases { counts.set(k.rawValue, d.count(k)) }
        var colors = EngineObject()
        for k in ChangeKind.allCases { colors.set(k.rawValue, EngineDrawJSON.hex(DocumentCompare.layerColors[k] ?? RGBA(1, 1, 1))) }
        var o = EngineObject()
        o.set("path", u.path)
        o.set("name", u.lastPathComponent)
        o.set("counts", counts.json)
        o.set("colors", colors.json)
        o.set("identical", d.isIdentical)
        o.set("layersAdded", EngineJSON.strings(d.layersAdded))
        o.set("layersRemoved", EngineJSON.strings(d.layersRemoved))
        o.set("report", d.report)
        o.set("csv", d.csv)
        o.set("shapes", .array(shapes))
        return o.json
    }

    /// Writes the overlay drawing (Save Overlay Drawing…) or the CSV (Export CSV…).
    func compareSave(_ p: EngineJSON) throws -> EngineJSON {
        let u = url(try string(p, "path"))
        let out = url(try string(p, "out"))
        let old = try FileImport.load(u, reference: editor.doc).0
        let d = DocumentCompare.compare(old, editor.doc)
        if (p["format"]?.stringValue ?? out.pathExtension).lowercased() == "csv" {
            try d.csv.write(to: out, atomically: true, encoding: .utf8)
        } else {
            try ArchiFile.encode(DocumentCompare.overlay(old, editor.doc, diff: d)).write(to: out, options: .atomic)
            editor.print("Wrote overlay \(out.path).")
        }
        return ScriptJSON.object([("path", .string(out.path))])
    }

    // MARK: Sheet revision clouds (SheetRevisionClouds / RevisionCloudPanel)

    static let revCloudLayer = "REVISION CLOUDS"

    func revCloudList() -> EngineJSON {
        let doc = editor.doc
        var clouds: [EngineJSON] = []
        var by: [String: (Set<String>, Int)] = [:]
        for (li, l) in doc.layouts.enumerated() {
            for e in l.entities {
                guard let code = e.props["revCloud"] else { continue }
                var o = EngineObject()
                o.set("layout", li)
                o.set("sheet", l.name)
                o.set("id", e.id)
                o.set("code", code)
                o.set("note", e.props["revNote"] ?? "")
                let b = GeometryOps.bounds(e.geometry, doc: doc)
                o.set("bounds", b.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(b))
                clouds.append(o.json)
                var v = by[code] ?? ([], 0)
                v.0.insert(l.name)
                v.1 += 1
                by[code] = v
            }
        }
        let codes = by.keys.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }
        var counts: [EngineJSON] = []
        for c in codes {
            let v = by[c] ?? ([], 0)
            counts.append(ScriptJSON.object([("code", .string(c)), ("sheets", EngineJSON.strings(v.0.sorted())), ("clouds", .int(v.1))]))
        }
        var sheets: [EngineJSON] = []
        for (li, l) in doc.layouts.enumerated() {
            var o = EngineObject()
            o.set("index", li)
            o.set("name", l.name)
            o.set("viewports", l.viewports.count)
            o.set("revisions", EngineJSON.strings(EngineSheets.revisions(l).map(\.code)))
            sheets.append(o.json)
        }
        return ScriptJSON.object([("clouds", .array(clouds)), ("counts", .array(counts)), ("sheets", .array(sheets))])
    }

    /// Adds a cloud (paper mm) with its revision triangle, around a viewport (`viewport`) or a rectangle (`rect`).
    func revCloudAdd(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let li = p["layout"]?.intValue ?? -1
        guard doc.layouts.indices.contains(li) else { throw EngineError.params("no sheet \(li)") }
        let revs = EngineSheets.revisions(doc.layouts[li]).map(\.code)
        let typed = (p["code"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        let code = typed.isEmpty ? (revs.last ?? "A") : typed
        var rect: BBox2
        if let v = p["viewport"]?.intValue, v >= 0, doc.layouts[li].viewports.indices.contains(v) {
            let vp = doc.layouts[li].viewports[v]
            rect = BBox2(min: vp.origin, max: vp.origin + vp.size).expanded(by: 3)
        } else {
            let r = (p["rect"]?.arrayValue ?? []).compactMap { $0.doubleValue }
            guard r.count == 4, r[2] > 0, r[3] > 0 else { throw EngineError.params("rect must be [x, y, w, h] with a positive size") }
            rect = BBox2(min: Vec2(r[0], r[1]), max: Vec2(r[0] + r[2], r[1] + r[3]))
        }
        let note = p["note"]?.stringValue ?? ""
        var cid: EntityID?
        editor.transaction("Revision Cloud") { d in cid = EngineSession.addRevCloud(&d, layout: li, rect: rect, code: code, note: note) }
        return ScriptJSON.object([("id", cid.map { EngineJSON.int($0) } ?? .null), ("list", revCloudList())])
    }

    static func addRevCloud(_ doc: inout ArchiDocument, layout li: Int, rect: BBox2, code: String, note: String, arc: Double = 8) -> EntityID? {
        guard doc.layouts.indices.contains(li), rect.width > 0, rect.height > 0, !code.isEmpty else { return nil }
        if doc.layerIndex(revCloudLayer) == nil { doc.layers.append(Layer(name: revCloudLayer, color: RGBA(0.9, 0.15, 0.1), lineweight: 0.35)) }
        let cloud = Markups.cloud(rect.min, rect.max, arc: arc)
        let id = doc.allocateID()
        var props = ["revCloud": code]
        if !note.isEmpty { props["revNote"] = note }
        doc.layouts[li].entities.append(Entity(id: id, layer: revCloudLayer, geometry: .polyline(cloud), props: props))
        let s = 6.0
        let c = Vec2(rect.max.x + s * 0.8, rect.max.y + s * 0.5)
        let v0 = PolyVertex(c + Vec2(-s / 2, -s * 0.29)), v1 = PolyVertex(c + Vec2(s / 2, -s * 0.29)), v2 = PolyVertex(c + Vec2(0, s * 0.58))
        let tri = PolylineGeom([v0, v1, v2], closed: true)
        let tag = String(id)
        doc.layouts[li].entities.append(Entity(id: doc.allocateID(), layer: revCloudLayer, geometry: .polyline(tri), props: ["revTag": tag]))
        let label = TextGeom(position: c - Vec2(0, s * 0.1), height: s * 0.4, content: code, halign: .center, valign: .middle)
        doc.layouts[li].entities.append(Entity(id: doc.allocateID(), layer: revCloudLayer, geometry: .text(label), props: ["revTag": tag]))
        return id
    }

    func revCloudRemove(_ p: EngineJSON) throws -> EngineJSON {
        let id = p["id"]?.intValue ?? -1
        let tag = String(id)
        editor.transaction("Delete Revision Cloud") { d in
            for li in d.layouts.indices { d.layouts[li].entities.removeAll { $0.id == id || $0.props["revTag"] == tag } }
        }
        return revCloudList()
    }
}
