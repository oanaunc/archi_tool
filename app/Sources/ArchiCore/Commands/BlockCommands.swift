// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum BlockCommands {
    static var all: [CommandDef] { [block, insert, attdef, attedit, wblock, xref, xattach, xbind, blockLibrary, imageAttach] }

    static func validName(_ n: String) -> Bool {
        !n.isEmpty && n.count <= 255 && n.rangeOfCharacter(from: CharacterSet(charactersIn: "<>/\\\":;?*|=`")) == nil
    }
    static func expand(_ path: String) -> URL {
        var p = (path as NSString).expandingTildeInPath
        if (p as NSString).pathExtension.isEmpty { p += "." + ArchiFile.fileExtension }
        return URL(fileURLWithPath: p)
    }
    @MainActor static func listBlocks(_ ed: Editor) {
        if ed.doc.blocks.isEmpty { ed.print("No blocks defined."); return }
        for (k, b) in ed.doc.blocks.sorted(by: { $0.key < $1.key }) {
            let n = ed.doc.entities.filter { if case .insert(let i) = $0.geometry { return i.block == k }; return false }.count
            ed.print("  \(k): \(b.entities.count) object(s), base \(b.basePoint), \(n) insert(s)")
        }
    }

    static var block: CommandDef {
        CommandDef("BLOCK", aliases: ["B", "-BLOCK", "BMAKE"], category: "Blocks", summary: "Creates a block definition from selected objects.") { ed in
            let pre = ed.selection
            guard let name = try await ed.getWord("Enter block name or [?]") else { return }
            if name == "?" { listBlocks(ed); return }
            guard validName(name) else { throw CommandError.invalid("Invalid block name.") }
            if ed.doc.blocks[name] != nil {
                guard try await ed.getYesNo("Block \"\(name)\" already exists. Redefine it?", defaultValue: false) else { return }
            }
            let base = try await ed.requirePoint("Specify insertion base point")
            ed.selection = pre
            let ids = try await ed.getEntitySelection("Select objects")
            let ents = ids.compactMap { ed.doc.entity($0) }
            guard !ents.isEmpty else { throw CommandError.invalid("No objects selected; block not created.") }
            // Prevent a block from containing itself.
            if ents.contains(where: { if case .insert(let i) = $0.geometry { return i.block == name }; return false }) { throw CommandError.invalid("A block cannot reference itself.") }
            let mode = try await ed.getKeyword("Objects after creating the block", ["Retain", "Convert", "Delete"], defaultValue: "Convert") ?? "Convert"
            let order = ed.doc.entities.filter { Set(ids).contains($0.id) }
            ed.doc.blocks[name] = Block(name: name, basePoint: base, entities: order)
            if mode != "Retain" {
                ed.doc.remove(ids: Set(ids))
                if mode == "Convert" { ed.addEntity(.insert(InsertGeom(block: name, position: base))) }
            }
            ed.selection = []
            ed.print("Block \"\(name)\" defined with \(ents.count) object(s).")
        }
    }

    static var insert: CommandDef {
        CommandDef("INSERT", aliases: ["I", "-INSERT", "DDINSERT"], category: "Blocks", summary: "Inserts a block reference (scale, rotation, attributes).") { ed in
            guard let n = try await ed.getWord("Enter block name or [?]", defaultValue: ed.doc.variable("INSNAME")) else { return }
            if n == "?" { listBlocks(ed); return }
            // "name=path" redefines a block from a drawing file; a path inserts the file as a block.
            if n.contains("=") || n.lowercased().hasSuffix("." + ArchiFile.fileExtension) || n.contains("/") {
                try loadBlockFromFile(ed, n)
                return try await continueInsert(ed, blockFileName(n))
            }
            try await continueInsert(ed, n)
        }
    }

    static func blockFileName(_ spec: String) -> String {
        if let eq = spec.firstIndex(of: "="), eq > spec.startIndex { return String(spec[..<eq]) }
        let p = spec.split(separator: "=").last.map(String.init) ?? spec
        return ((p as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Loads a drawing file as a block definition (its INSBASE is the base point); nested blocks and layers come along.
    @MainActor static func loadBlockFromFile(_ ed: Editor, _ spec: String) throws {
        let path = spec.contains("=") ? String(spec[spec.index(after: spec.firstIndex(of: "=")!)...]) : spec
        let name = blockFileName(spec)
        guard validName(name) else { throw CommandError.invalid("Invalid block name \(name).") }
        let url = expand(path.isEmpty ? name : path)
        guard let data = try? Data(contentsOf: url), let src = try? ArchiFile.decode(data) else { throw CommandError.invalid("Cannot read \(url.path).") }
        var base = Vec2.zero
        if let b = src.variable("INSBASE") {
            let p = b.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count >= 2 { base = Vec2(p[0], p[1]) }
        }
        for l in src.layers where ed.doc.layer(named: l.name) == nil { ed.doc.layers.append(l) }
        for (k, b) in src.blocks where ed.doc.blocks[k] == nil && k != name { ed.doc.blocks[k] = b }
        let existed = ed.doc.blocks[name] != nil
        ed.doc.blocks[name] = Block(name: name, basePoint: base, entities: src.entities)
        if BlockTools.references(name, doc: ed.doc).contains(where: { BlockTools.nestedNames($0, doc: ed.doc).contains(name) }) { throw CommandError.invalid("The file references block \(name) itself.") }
        ed.print(existed ? "Block \(name) redefined from \(url.lastPathComponent)." : "Block \(name) loaded from \(url.lastPathComponent).")
    }

    @MainActor static func continueInsert(_ ed: Editor, _ n: String) async throws {
        do {
            guard let blk = ed.doc.blocks[n] ?? ed.doc.blocks.first(where: { $0.key.caseInsensitiveCompare(n) == .orderedSame })?.value else { throw CommandError.invalid("Block \"\(n)\" not found.") }
            let name = blk.name
            ed.doc.setVariable("INSNAME", name)
            var scale: Double? = nil, rot: Double? = nil
            var pos: Vec2
            while true {
                let s = scale ?? 1, r = rot ?? 0
                let a = try await ed.getPoint("Specify insertion point", keywords: ["Scale", "Rotate"]) { c in [.insert(InsertGeom(block: name, position: c, scale: Vec2(s, s), rotation: r))] }
                switch a {
                case .point(let p): pos = p
                case .keyword("Scale"):
                    if let v = try await ed.getReal("Specify scale factor for XYZ axes", defaultValue: 1).value, v != 0 { scale = v }; continue
                case .keyword("Rotate"): rot = try await ed.getAngle("Specify rotation angle", defaultValue: 0).value; continue
                default: return
                }
                break
            }
            var sx = scale ?? 1, sy = scale ?? 1
            if scale == nil {
                if let v = try await ed.getReal("Enter X scale factor", defaultValue: 1).value, v != 0 { sx = v }
                if let v = try await ed.getReal("Enter Y scale factor <use X scale factor>", defaultValue: sx).value, v != 0 { sy = v } else { sy = sx }
            }
            let (px, py) = (sx, sy)
            var angle = rot ?? 0
            if rot == nil {
                angle = try await ed.getAngle("Specify rotation angle", base: pos, defaultValue: 0, preview: { c in [.insert(InsertGeom(block: name, position: pos, scale: Vec2(px, py), rotation: (c - pos).angle))] }).value ?? 0
            }
            var attrs: [String: String] = [:]
            let ask = ed.doc.variable("ATTREQ") != "0"
            for e in blk.entities {
                guard let tag = e.props["attdef"] else { continue }
                let def = e.props["default"] ?? ""
                // Constant and preset attributes (and ATTREQ 0) take their default without prompting.
                guard ask, !AttributeModes.has(e, "C"), !AttributeModes.has(e, "P") else { attrs[tag] = def; continue }
                let msg = e.props["prompt"].flatMap { $0.isEmpty ? nil : $0 } ?? "Enter \(tag)"
                var v = try await ed.getString(msg, defaultValue: def) ?? def
                if AttributeModes.has(e, "V") { v = try await ed.getString("Verify " + msg, defaultValue: v) ?? v }
                attrs[tag] = v
            }
            ed.addEntity(.insert(InsertGeom(block: name, position: pos, scale: Vec2(sx, sy), rotation: angle, attributes: attrs)))
        }
    }

    static var attdef: CommandDef {
        CommandDef("ATTDEF", aliases: ["ATT", "-ATTDEF"], category: "Blocks", summary: "Defines an attribute (modes Invisible/Constant/Verify/Preset/Lock, tag, prompt, default) to include in a block.") { ed in
            var modes = Set((ed.doc.variable("AFLAGS") ?? "").map { String($0) })
            while true {
                let cur = AttributeModes.all.filter { modes.contains($0.prefix(1).uppercased()) }.joined(separator: ",")
                let w = try await ed.getWord("Current attribute modes: \(cur.isEmpty ? "none" : cur). Enter an option to change [Invisible/Constant/Verify/Preset/Lock] or tag name",
                                             keywords: AttributeModes.all)
                guard let t = w else { throw CommandError.invalid("The tag must be one word.") }
                if AttributeModes.all.contains(t) { let f = String(t.prefix(1)); if modes.contains(f) { modes.remove(f) } else { modes.insert(f) }; continue }
                guard !t.isEmpty, !t.contains(" ") else { throw CommandError.invalid("The tag must be one word.") }
                let tag = t
                let flags = AttributeModes.text(modes)
                ed.doc.setVariable("AFLAGS", flags)
                let constant = modes.contains("C")
                let prompt = constant ? tag : (try await ed.getWord("Enter attribute prompt", defaultValue: tag) ?? tag)
                let def = try await ed.getWord(constant ? "Enter attribute value" : "Enter default attribute value", defaultValue: "") ?? ""
                let p = try await ed.requirePoint("Specify start point of text")
                let h = try await ed.getPositive("Specify height", base: p, defaultValue: ed.settings.textHeight)
                let rot = try await ed.getAngle("Specify rotation angle of text", base: p, defaultValue: 0).value ?? 0
                let id = ed.addEntity(.text(TextGeom(position: p, height: h, content: tag.uppercased(), rotation: rot)))
                if let i = ed.doc.entityIndex(id) {
                    ed.doc.entities[i].props = ["attdef": tag.uppercased(), "prompt": prompt, "default": def]
                    if !flags.isEmpty { ed.doc.entities[i].props[AttributeModes.prop] = flags }
                    if modes.contains("I") { ed.doc.entities[i].props["invisible"] = "1" }
                }
                return
            }
        }
    }

    static var attedit: CommandDef {
        CommandDef("ATTEDIT", aliases: ["ATE", "-ATTEDIT", "EATTEDIT"], category: "Blocks", summary: "Changes attribute values of a block reference.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select block reference", filter: { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  let i = ed.doc.entityIndex(pk.id), case .insert(var ins) = ed.doc.entities[i].geometry else { return }
            let defs = ed.doc.blocks[ins.block]?.entities ?? []
            // Constant attributes cannot be edited.
            let constant = Set(defs.filter { AttributeModes.has($0, "C") }.compactMap { $0.props["attdef"] })
            let tags = (defs.compactMap { $0.props["attdef"] } + ins.attributes.keys.sorted()).filter { !constant.contains($0) }
            var seen = Set<String>()
            let unique = tags.filter { seen.insert($0).inserted }
            guard !unique.isEmpty else { throw CommandError.invalid("That block has no attributes.") }
            for t in unique {
                if let v = try await ed.getWord("Enter value for \(t)", defaultValue: ins.attributes[t] ?? "") { ins.attributes[t] = v }
            }
            ed.doc.entities[i].geometry = .insert(ins)
        }
    }

    static var wblock: CommandDef {
        CommandDef("WBLOCK", aliases: ["W", "-WBLOCK"], category: "Blocks", summary: "Writes a block, selected objects or the whole drawing to a new .archi file.", modifies: false) { ed in
            guard let path = try await ed.getWord("Enter file name") else { return }
            let src = try await ed.getKeyword("Specify source", ["Block", "Entire", "Objects"], defaultValue: "Objects") ?? "Objects"
            var out = ArchiDocument()
            out.units = ed.doc.units; out.layers = ed.doc.layers; out.linetypes = ed.doc.linetypes; out.textStyles = ed.doc.textStyles; out.dimStyles = ed.doc.dimStyles
            out.materials = ed.doc.materials; out.wallTypes = ed.doc.wallTypes
            var ents: [Entity] = []
            switch src {
            case "Entire": out = ed.doc
            case "Block":
                guard let n = try await ed.getWord("Enter name of existing block"), let b = ed.doc.blocks[n] else { throw CommandError.invalid("Block not found.") }
                ents = b.entities.map { var e = $0; e.geometry = GeometryOps.transform(e.geometry, .translation(-b.basePoint)); return e }
            default:
                let base = try await ed.requirePoint("Specify base point")
                let ids = Set(try await ed.getEntitySelection())
                ents = ed.doc.entities.filter { ids.contains($0.id) }.map { var e = $0; e.geometry = GeometryOps.transform(e.geometry, .translation(-base)); return e }
                ed.selection = []
            }
            if src != "Entire" {
                guard !ents.isEmpty else { throw CommandError.invalid("Nothing to write.") }
                for e in ents { out.add(e) }
                // Blocks referenced by the written objects travel with them.
                var queue = ents
                while let e = queue.popLast() {
                    if case .insert(let i) = e.geometry, out.blocks[i.block] == nil, let b = ed.doc.blocks[i.block] { out.blocks[i.block] = b; queue += b.entities }
                }
            }
            let url = expand(path)
            do { try ArchiFile.encode(out).write(to: url, options: .atomic); ed.print("Written \(url.path).") }
            catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
        }
    }

    static var xref: CommandDef {
        CommandDef("XREF", aliases: ["XR", "-XREF", "EXTERNALREFERENCES", "ERHIGHLIGHT"], category: "Blocks", summary: "External references: list, Attach/Overlay a drawing (.archi/.dxf), Reload, Unload, Detach, Bind, Path, Notify (changed files).") { ed in
            let kws = ["?", "Attach", "Overlay", "Reload", "Unload", "Detach", "Bind", "Path", "Notify"]
            let w = try await ed.getWord("Enter an option", defaultValue: "?", keywords: kws)
            guard let k = w else {
                guard let h = ed.host else { return }
                h.perform(.importFile(nil), editor: ed); return
            }
            let base = ed.fileURL?.deletingLastPathComponent()
            @MainActor func names(_ msg: String) async throws -> [String] {
                let pat = try await ed.getWord(msg, defaultValue: "*") ?? "*"
                return Xrefs.all(ed.doc).map(\.name).filter { n in pat.split(separator: ",").contains { SettingsCommands.glob(String($0).trimmingCharacters(in: .whitespaces), n) } }
            }
            do {
                switch k {
                case "?":
                    let list = Xrefs.all(ed.doc)
                    if list.isEmpty { ed.print("No external references."); return }
                    let changed = Set(Xrefs.changed(ed.doc, base: base)), missing = Set(Xrefs.missing(ed.doc, base: base))
                    for x in list {
                        let n = ed.doc.entities.filter { if case .insert(let i) = $0.geometry { return i.block == x.name }; return false }.count
                        let status = missing.contains(x.name) ? "Not found" : !x.loaded ? "Unloaded" : changed.contains(x.name) ? "Needs reloading" : "Loaded"
                        ed.print("  \(x.name)  \(x.overlay ? "Overlay" : "Attach")  \(status)  \(n) reference(s)  \(x.path)")
                    }
                case "Attach", "Overlay":
                    guard let path = try await ed.getWord("Enter file name (.archi or .dxf)") else { return }
                    try await attachXref(ed, path: path, overlay: k == "Overlay")
                case "Reload":
                    let ns = try await names("Enter xref name(s) to reload")
                    let r = try Xrefs.reload(&ed.doc, names: ns, base: base)
                    ed.print("\(r.count) xref(s) reloaded.")
                case "Unload":
                    for n in try await names("Enter xref name(s) to unload") { try Xrefs.unload(&ed.doc, name: n) }
                case "Detach":
                    let ns = try await names("Enter xref name(s) to detach")
                    for n in ns { try Xrefs.detach(&ed.doc, name: n) }
                    ed.print("\(ns.count) xref(s) detached.")
                case "Bind":
                    let ns = try await names("Enter xref name(s) to bind")
                    let t = try await ed.getKeyword("Bind type", ["Bind", "Insert"], defaultValue: "Bind") ?? "Bind"
                    for n in ns { try Xrefs.bind(&ed.doc, name: n, insert: t == "Insert") }
                    ed.print("\(ns.count) xref(s) bound.")
                case "Path":
                    guard let n = try await ed.getWord("Enter xref name"), var info = Xrefs.named(n, ed.doc) else { throw CommandError.invalid("Xref not found.") }
                    ed.print("Old path: \(info.path)")
                    guard let p = try await ed.getWord("Enter new path", defaultValue: info.path) else { return }
                    info.path = p
                    Xrefs.store(Xrefs.all(ed.doc).filter { $0.name != info.name } + [info], &ed.doc)
                    try Xrefs.reload(&ed.doc, names: [info.name], base: base)
                case "Notify":
                    let c = Xrefs.changed(ed.doc, base: base), m = Xrefs.missing(ed.doc, base: base)
                    if c.isEmpty && m.isEmpty { ed.print("All external references are up to date.") }
                    if !c.isEmpty { ed.print("Changed since loaded: \(c.joined(separator: ", ")) — use XREF Reload.") }
                    if !m.isEmpty { ed.print("Not found: \(m.joined(separator: ", ")).") }
                default:
                    // A file name typed directly attaches it.
                    try await attachXref(ed, path: k, overlay: false)
                }
            } catch let e as Xrefs.XrefError { throw CommandError.invalid(e.localizedDescription) }
        }
    }

    @MainActor static func attachXref(_ ed: Editor, path: String, overlay: Bool) async throws {
        do {
            let n = try Xrefs.attach(&ed.doc, path: path, overlay: overlay, base: ed.fileURL?.deletingLastPathComponent(), host: ed.fileURL)
            ed.print("Attach Xref \"\(n)\": \(path)")
            try await continueInsert(ed, n)
        } catch let e as Xrefs.XrefError { throw CommandError.invalid(e.localizedDescription) }
    }

    static var xattach: CommandDef {
        CommandDef("XATTACH", aliases: ["ATTACH", "XA"], category: "Blocks", summary: "Attaches a drawing (.archi/.dxf) as an external reference and places it.") { ed in
            guard let path = try await ed.getWord("Enter file name (.archi or .dxf)") else {
                if let h = ed.host { h.perform(.importFile(nil), editor: ed) }
                return
            }
            let t = try await ed.getKeyword("Reference type", ["Attach", "Overlay"], defaultValue: "Attach") ?? "Attach"
            try await attachXref(ed, path: path, overlay: t == "Overlay")
        }
    }

    static var xbind: CommandDef {
        CommandDef("XBIND", aliases: ["-XBIND"], category: "Blocks", summary: "Binds external references into the drawing as ordinary blocks (Bind: X$0$name, Insert: merged names).") { ed in
            guard let n = try await ed.getWord("Enter xref name(s) to bind", defaultValue: "*") else { return }
            let t = try await ed.getKeyword("Bind type", ["Bind", "Insert"], defaultValue: "Bind") ?? "Bind"
            let ns = Xrefs.all(ed.doc).map(\.name).filter { SettingsCommands.glob(n, $0) }
            guard !ns.isEmpty else { throw CommandError.invalid("No matching xref.") }
            do { for x in ns { try Xrefs.bind(&ed.doc, name: x, insert: t == "Insert") } }
            catch let e as Xrefs.XrefError { throw CommandError.invalid(e.localizedDescription) }
            ed.print("\(ns.count) xref(s) bound.")
        }
    }

    static var blockLibrary: CommandDef {
        CommandDef("BLOCKLIBRARY", aliases: ["BLIB", "CONTENTBROWSER"], category: "Blocks", summary: "Browses a folder of drawings as a block library: List, Search, Insert (files and the blocks inside them).") { ed in
            let def = ed.doc.variable("BLOCKLIBRARYPATH") ?? "~/Documents"
            guard let folder = try await ed.getWord("Enter library folder", defaultValue: def) else { return }
            let url = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { throw CommandError.invalid("Folder not found: \(url.path)") }
            ed.doc.setVariable("BLOCKLIBRARYPATH", folder)
            var items = BlockLibrary.scan(url)
            while true {
                let k = try await ed.getWord("Enter item name to insert or [List/Search]", defaultValue: "List", keywords: ["List", "Search"]) ?? "List"
                switch k {
                case "List":
                    if items.isEmpty { ed.print("No drawings in \(url.path).") }
                    for i in items.prefix(500) { ed.print("  \(i.folder.isEmpty ? "" : i.folder + "/")\(i.file.lastPathComponent)\(i.block.map { " : " + $0 } ?? "")") }
                    return
                case "Search":
                    let q = try await ed.getString("Enter search words") ?? ""
                    items = BlockLibrary.search(items, q)
                    for i in items.prefix(200) { ed.print("  \(i.name)  (\(i.file.lastPathComponent))") }
                    if items.isEmpty { ed.print("Nothing found."); return }
                default:
                    guard let item = items.first(where: { $0.name.caseInsensitiveCompare(k) == .orderedSame }) ?? BlockLibrary.search(items, k).first else { throw CommandError.invalid("No library item \(k).") }
                    do { let n = try BlockLibrary.load(item, into: &ed.doc); try await continueInsert(ed, n) }
                    catch let e as Xrefs.XrefError { throw CommandError.invalid(e.localizedDescription) }
                    return
                }
            }
        }
    }

    static var imageAttach: CommandDef {
        CommandDef("IMAGEATTACH", aliases: ["IAT", "IMAGE"], category: "Blocks", summary: "Places a raster image reference (path, insertion point, width, rotation).") { ed in
            guard let path = try await ed.getWord("Enter image file path") else { return }
            let p = try await ed.requirePoint("Specify insertion point")
            let w = try await ed.getPositive("Specify width", base: p, defaultValue: 1000)
            let h = try await ed.getPositive("Specify height", base: p, defaultValue: w * 0.75)
            let rot = try await ed.getAngle("Specify rotation angle", base: p, defaultValue: 0).value ?? 0
            ed.addEntity(.image(ImageGeom(path: path, origin: p, size: Vec2(w, h), rotation: rot)))
        }
    }
}
