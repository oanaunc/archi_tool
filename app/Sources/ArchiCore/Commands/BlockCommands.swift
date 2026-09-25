// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum BlockCommands {
    static var all: [CommandDef] { [block, insert, attdef, attedit, wblock, xref, imageAttach] }

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
            for e in blk.entities {
                guard let tag = e.props["attdef"] else { continue }
                let v = try await ed.getString(e.props["prompt"].flatMap { $0.isEmpty ? nil : $0 } ?? "Enter \(tag)", defaultValue: e.props["default"] ?? "")
                attrs[tag] = v ?? e.props["default"] ?? ""
            }
            ed.addEntity(.insert(InsertGeom(block: name, position: pos, scale: Vec2(sx, sy), rotation: angle, attributes: attrs)))
        }
    }

    static var attdef: CommandDef {
        CommandDef("ATTDEF", aliases: ["ATT", "-ATTDEF"], category: "Blocks", summary: "Defines an attribute (tag, prompt, default) to include in a block.") { ed in
            guard let tag = try await ed.getWord("Enter attribute tag name"), !tag.isEmpty, !tag.contains(" ") else { throw CommandError.invalid("The tag must be one word.") }
            let prompt = try await ed.getWord("Enter attribute prompt", defaultValue: tag) ?? tag
            let def = try await ed.getWord("Enter default attribute value", defaultValue: "") ?? ""
            let p = try await ed.requirePoint("Specify start point of text")
            let h = try await ed.getPositive("Specify height", base: p, defaultValue: ed.settings.textHeight)
            let rot = try await ed.getAngle("Specify rotation angle of text", base: p, defaultValue: 0).value ?? 0
            let id = ed.addEntity(.text(TextGeom(position: p, height: h, content: tag.uppercased(), rotation: rot)))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props = ["attdef": tag.uppercased(), "prompt": prompt, "default": def] }
        }
    }

    static var attedit: CommandDef {
        CommandDef("ATTEDIT", aliases: ["ATE", "-ATTEDIT", "EATTEDIT"], category: "Blocks", summary: "Changes attribute values of a block reference.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select block reference", filter: { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  let i = ed.doc.entityIndex(pk.id), case .insert(var ins) = ed.doc.entities[i].geometry else { return }
            let tags = (ed.doc.blocks[ins.block]?.entities.compactMap { $0.props["attdef"] } ?? []) + ins.attributes.keys.sorted()
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
        CommandDef("XREF", aliases: ["XR", "ATTACH", "XATTACH"], category: "Blocks", summary: "Attaches an external drawing (the host imports it).", modifies: false) { ed in
            let path = try await ed.getWord("Enter file name (Enter = choose)")
            guard let h = ed.host else { throw CommandError.invalid("Attaching files requires the application window.") }
            h.perform(.importFile(path), editor: ed)
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
