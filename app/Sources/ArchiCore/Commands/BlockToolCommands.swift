// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Groups, block counting/replacement, base points, attribute management and extraction, flip parameter.
enum BlockToolCommands {
    static var all: [CommandDef] { [group, ungroup, bcount, blockReplace, base, blockBase, attsync, battman, attext, dataExtraction, bflip] }

    static func isInsert(_ g: Geometry?) -> Bool { if case .insert? = g { return true }; return false }

    // MARK: Groups
    static var group: CommandDef {
        CommandDef("GROUP", aliases: ["G", "-GROUP"], category: "Blocks", summary: "Creates and manages named groups (Create/Add/Remove/Explode/REName/List); picking a member selects the group (PICKSTYLE).") { ed in
            let pre = ed.selection
            let k = try await ed.getWord("Enter group name or [List/Add/Remove/Explode/REName]", keywords: ["List", "Add", "Remove", "Explode", "REName"]) ?? ""
            switch k {
            case "List":
                let g = BlockTools.groups(ed.doc)
                if g.isEmpty { ed.print("No groups.") }
                for (n, ids) in g.sorted(by: { $0.key < $1.key }) { ed.print("  \(n): \(ids.count) object(s)") }
            case "Add", "Remove":
                guard let n = try await ed.getWord("Enter group name"), let name = BlockTools.groups(ed.doc).keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Group not found.") }
                ed.selection = []
                let saved = ed.doc.variable("PICKSTYLE")
                ed.doc.setVariable("PICKSTYLE", "0")
                let ids = try await ed.getEntitySelection(k == "Add" ? "Select objects to add" : "Select objects to remove")
                if let s = saved { ed.doc.setVariable("PICKSTYLE", s) } else { ed.doc.variables.removeValue(forKey: "PICKSTYLE") }
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["group"] = k == "Add" ? name : (ed.doc.entities[i].props["group"] == name ? nil : ed.doc.entities[i].props["group"]) } }
            case "Explode":
                guard let n = try await ed.getWord("Enter group name") else { return }
                let c = BlockTools.dissolve(&ed.doc, groups: [n])
                guard c > 0 else { throw CommandError.invalid("Group not found.") }
                ed.print("Group \(n) exploded.")
            case "REName":
                guard let o = try await ed.getWord("Enter old group name"), let n = try await ed.getWord("Enter new group name"), BlockCommands.validName(n) else { return }
                var c = 0
                for i in ed.doc.entities.indices where ed.doc.entities[i].props["group"]?.caseInsensitiveCompare(o) == .orderedSame { ed.doc.entities[i].props["group"] = n; c += 1 }
                if c == 0 { throw CommandError.invalid("Group not found.") }
            default:
                var name = k
                if name.isEmpty || name == "*" { var j = 1; while BlockTools.groups(ed.doc)["*A\(j)"] != nil { j += 1 }; name = "*A\(j)" }
                guard name.hasPrefix("*") || BlockCommands.validName(name) else { throw CommandError.invalid("Invalid group name.") }
                guard BlockTools.groups(ed.doc)[name] == nil else { throw CommandError.invalid("Group \(name) already exists.") }
                ed.selection = pre
                let ids = try await ed.getEntitySelection("Select objects")
                guard !ids.isEmpty else { return }
                for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["group"] = name } }
                ed.print("Group \(name) created with \(ids.count) object(s).")
            }
            ed.selection = []
        }
    }
    static var ungroup: CommandDef {
        CommandDef("UNGROUP", aliases: ["UNG"], category: "Blocks", summary: "Dissolves the groups of the selected objects.") { ed in
            let ids = try await ed.getEntitySelection("Select group")
            let names = Set(ids.compactMap { ed.doc.entity($0)?.props["group"] })
            guard !names.isEmpty else { throw CommandError.invalid("No groups selected.") }
            BlockTools.dissolve(&ed.doc, groups: names)
            ed.selection = []
            ed.print("\(names.count) group(s) exploded.")
        }
    }

    // MARK: Blocks
    static var bcount: CommandDef {
        CommandDef("BCOUNT", aliases: ["BLOCKCOUNT"], category: "Blocks", summary: "Counts block references (including nested ones) in the drawing or a selection.", modifies: false) { ed in
            let ids = ed.selection.isEmpty ? ed.doc.entities.map(\.id) : Array(ed.selection)
            let counts = BlockTools.count(ids.compactMap { ed.doc.entity($0) }, doc: ed.doc)
            if counts.isEmpty { ed.print("No block references."); return }
            ed.print("Block                     Count")
            for (n, c) in counts.sorted(by: { $0.key < $1.key }) { ed.print("\(n.padding(toLength: max(25, n.count), withPad: " ", startingAt: 0)) \(c)") }
        }
    }
    static var blockReplace: CommandDef {
        CommandDef("BLOCKREPLACE", aliases: ["BREPLACE"], category: "Blocks", summary: "Replaces all references of one block with another (keeps attributes with matching tags).") { ed in
            guard let o = try await ed.getWord("Enter name of block to be replaced"), let old = BlockTools.blockName(o, ed.doc) else { throw CommandError.invalid("Block not found.") }
            guard let n = try await ed.getWord("Enter name of replacement block"), let new = BlockTools.blockName(n, ed.doc) else { throw CommandError.invalid("Block not found.") }
            guard old != new else { return }
            if BlockTools.nestedNames(new, doc: ed.doc).contains(old) { throw CommandError.invalid("\(new) contains \(old); replacing would create a cycle.") }
            let c = BlockTools.replace(&ed.doc, old: old, with: new)
            if try await ed.getYesNo("Purge unreferenced block \(old)?", defaultValue: true), BlockTools.isUnreferenced(old, doc: ed.doc) { ed.doc.blocks[old] = nil }
            ed.print("\(c) reference(s) replaced.")
        }
    }
    static var base: CommandDef {
        CommandDef("BASE", category: "Blocks", summary: "Sets the drawing's insertion base point (INSBASE), used when it is inserted as a block.") { ed in
            let cur = ed.doc.variable("INSBASE") ?? "0,0"
            let p = try await ed.getPoint("Enter base point <\(cur)>")
            guard let q = p.point else { return }
            ed.doc.setVariable("INSBASE", "\(fmt(q.x, 8)),\(fmt(q.y, 8))")
        }
    }
    static var blockBase: CommandDef {
        CommandDef("BLOCKBASE", aliases: ["BBASE", "BASEPOINT"], category: "Blocks", summary: "Changes a block definition's base point; references stay where they are.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select block reference", filter: { isInsert(ed.doc.entity($0)?.geometry) }), case .insert(let ins)? = ed.doc.entity(pk.id)?.geometry else { return }
            let p = try await ed.requirePoint("Specify new base point")
            // New base in block coordinates.
            let inv = ins.transform * Transform2D.translation(-(ed.doc.blocks[ins.block]?.basePoint ?? .zero))
            guard let local = BlockTools.invert(inv)?.apply(p) else { throw CommandError.invalid("Degenerate block reference.") }
            BlockTools.setBase(&ed.doc, block: ins.block, base: local)
            ed.print("Base point of \(ins.block) changed.")
        }
    }

    // MARK: Attributes
    static var attsync: CommandDef {
        CommandDef("ATTSYNC", category: "Blocks", summary: "Updates block references with the current attribute definitions of their block.") { ed in
            let a = try await ed.getWord("Enter block name or [Select]", defaultValue: "Select", keywords: ["Select"]) ?? "Select"
            var name: String
            if a == "Select" {
                guard case .pick(let pk) = try await ed.pickObject("Select a block", filter: { isInsert(ed.doc.entity($0)?.geometry) }), case .insert(let i)? = ed.doc.entity(pk.id)?.geometry else { return }
                name = i.block
            } else { guard let n = BlockTools.blockName(a, ed.doc) else { throw CommandError.invalid("Block not found.") }; name = n }
            let c = BlockTools.syncAttributes(&ed.doc, block: name)
            ed.print("ATTSYNC block \(name): \(c) reference(s) updated.")
        }
    }
    static var battman: CommandDef {
        CommandDef("BATTMAN", aliases: ["-BATTMAN"], category: "Blocks", summary: "Edits the attribute definitions of a block (prompt, default, tag, modes, order, delete) and syncs references.") { ed in
            guard let n = try await ed.getWord("Enter block name"), let name = BlockTools.blockName(n, ed.doc), var blk = ed.doc.blocks[name] else { throw CommandError.invalid("Block not found.") }
            let tags = blk.entities.compactMap { $0.props["attdef"] }
            guard !tags.isEmpty else { throw CommandError.invalid("Block \(name) has no attributes.") }
            ed.print("Attributes: " + tags.joined(separator: ", "))
            guard let t = try await ed.getWord("Enter attribute tag"), let idx = blk.entities.firstIndex(where: { $0.props["attdef"]?.caseInsensitiveCompare(t) == .orderedSame }) else { throw CommandError.invalid("Tag not found.") }
            let tag = blk.entities[idx].props["attdef"]!
            let k = try await ed.getKeyword("Enter option", ["Prompt", "Default", "Tag", "Mode", "UP", "DOwn", "Delete"], defaultValue: "Default") ?? "Default"
            var renamed: (String, String)? = nil
            switch k {
            case "UP", "DOwn":
                // Prompt order = order of the attribute definitions in the block.
                let attIdx = blk.entities.indices.filter { blk.entities[$0].props["attdef"] != nil }
                guard let pos = attIdx.firstIndex(of: idx) else { break }
                let other = k == "UP" ? pos - 1 : pos + 1
                guard attIdx.indices.contains(other) else { ed.print("Already \(k == "UP" ? "first" : "last")."); break }
                blk.entities.swapAt(idx, attIdx[other])
            case "Mode":
                var flags = Set((blk.entities[idx].props[AttributeModes.prop] ?? "").map { String($0) })
                while let m = try await ed.getKeyword("Toggle mode [Invisible/Constant/Verify/Preset/Lock] (current: \(AttributeModes.text(flags).isEmpty ? "none" : AttributeModes.text(flags)))", AttributeModes.all) {
                    let f = String(m.prefix(1)); if flags.contains(f) { flags.remove(f) } else { flags.insert(f) }
                }
                let t = AttributeModes.text(flags)
                blk.entities[idx].props[AttributeModes.prop] = t.isEmpty ? nil : t
                blk.entities[idx].props["invisible"] = flags.contains("I") ? "1" : nil
            case "Prompt": blk.entities[idx].props["prompt"] = try await ed.getString("Enter new prompt", defaultValue: blk.entities[idx].props["prompt"] ?? tag) ?? tag
            case "Default": blk.entities[idx].props["default"] = try await ed.getString("Enter new default value", defaultValue: blk.entities[idx].props["default"] ?? "") ?? ""
            case "Tag":
                guard let nt = try await ed.getWord("Enter new tag")?.uppercased(), !nt.contains(" "), !tags.contains(nt) else { throw CommandError.invalid("Invalid or duplicate tag.") }
                blk.entities[idx].props["attdef"] = nt
                if case .text(var tx) = blk.entities[idx].geometry, tx.content == tag { tx.content = nt; blk.entities[idx].geometry = .text(tx) }
                renamed = (tag, nt)
            default: blk.entities.remove(at: idx)
            }
            ed.doc.blocks[name] = blk
            if let (o, n) = renamed {
                for i in ed.doc.entities.indices {
                    guard case .insert(var ins) = ed.doc.entities[i].geometry, ins.block == name, let v = ins.attributes.removeValue(forKey: o) else { continue }
                    ins.attributes[n] = v; ed.doc.entities[i].geometry = .insert(ins)
                }
            }
            BlockTools.syncAttributes(&ed.doc, block: name)
        }
    }

    @MainActor static func extractionTargets(_ ed: Editor) async throws -> [Entity] {
        let ids = ed.selection.isEmpty ? try await ed.getEntitySelection("Select block references (Enter = all)") : Array(ed.selection)
        let pool = ids.isEmpty ? ed.doc.entities : ed.doc.entities.filter { Set(ids).contains($0.id) }
        ed.selection = []
        return pool.filter { isInsert($0.geometry) }
    }

    static var attext: CommandDef {
        CommandDef("ATTEXT", aliases: ["-ATTEXT", "ATTEXTRACT"], category: "Blocks", summary: "Extracts block reference attributes to a CSV file (or the command line).", modifies: false) { ed in
            let ents = try await extractionTargets(ed)
            guard !ents.isEmpty else { throw CommandError.invalid("No block references found.") }
            let rows = BlockTools.extractionRows(ents, doc: ed.doc)
            let csv = rows.map { $0.map(BlockTools.csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
            let p = try await ed.getWord("Enter output file (Enter = show)", defaultValue: "") ?? ""
            if p.isEmpty { for r in rows { ed.print(r.joined(separator: " | ")) }; return }
            var path = (p as NSString).expandingTildeInPath
            if (path as NSString).pathExtension.isEmpty { path += ".csv" }
            do { try csv.write(toFile: path, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(path).") }
            ed.print("\(rows.count - 1) record(s) extracted to \(path).")
        }
    }
    static var dataExtraction: CommandDef {
        CommandDef("DATAEXTRACTION", aliases: ["DX", "EATTEXT"], category: "Blocks", summary: "Extracts block counts or attributes into a table in the drawing (or a CSV file).") { ed in
            let k = try await ed.getKeyword("Extract", ["Attributes", "Counts"], defaultValue: "Attributes") ?? "Attributes"
            let ents = try await extractionTargets(ed)
            guard !ents.isEmpty else { throw CommandError.invalid("No block references found.") }
            var rows: [[String]]
            if k == "Counts" {
                rows = [["Block", "Count"]] + BlockTools.count(ents, doc: ed.doc).sorted { $0.key < $1.key }.map { [$0.key, "\($0.value)"] }
            } else {
                rows = BlockTools.extractionRows(ents, doc: ed.doc)
            }
            let out = try await ed.getKeyword("Output", ["Table", "File"], defaultValue: "Table") ?? "Table"
            if out == "File" {
                guard let p = try await ed.getWord("Enter CSV file path") else { return }
                var path = (p as NSString).expandingTildeInPath
                if (path as NSString).pathExtension.isEmpty { path += ".csv" }
                let csv = rows.map { $0.map(BlockTools.csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
                do { try csv.write(toFile: path, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(path).") }
                ed.print("\(rows.count - 1) record(s) written to \(path)."); return
            }
            let th = ed.settings.textHeight
            let cols = rows.map(\.count).max() ?? 1
            let widths = (0..<cols).map { c in max(th * 4, Double(rows.map { c < $0.count ? $0[c].count : 0 }.max() ?? 0) * th * 0.7 + th) }
            let p = try await ed.requirePoint("Specify insertion point") { c in [.table(TableGeom(origin: c, columnWidths: widths, rowHeight: th * 2, cells: rows, textHeight: th))] }
            ed.addEntity(.table(TableGeom(origin: p, columnWidths: widths, rowHeight: th * 2, cells: rows.map { $0 + Array(repeating: "", count: cols - $0.count) }, textHeight: th)))
            ed.print("Extraction table with \(rows.count - 1) row(s) inserted.")
        }
    }

    // MARK: Dynamic flip parameter
    static var bflip: CommandDef {
        CommandDef("BFLIP", aliases: ["FLIP", "BLOCKFLIP"], category: "Blocks", summary: "Flips block references about their insertion point (dynamic flip parameter, state kept in the reference).") { ed in
            let k = try await ed.getKeyword("Flip direction", ["Horizontal", "Vertical"], defaultValue: "Horizontal") ?? "Horizontal"
            let ids = try await ed.getEntitySelection("Select block references").filter { isInsert(ed.doc.entity($0)?.geometry) }
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                BlockTools.flip(&ed.doc.entities[i], vertical: k == "Vertical")
            }
            ed.selection = []
            ed.print("\(ids.count) reference(s) flipped.")
        }
    }
}

/// Block and group helpers (pure functions, used by commands and tests).
public enum BlockTools {
    public static func groups(_ doc: ArchiDocument) -> [String: [EntityID]] {
        var out: [String: [EntityID]] = [:]
        for e in doc.entities { if let g = e.props["group"] { out[g, default: []].append(e.id) } }
        return out
    }
    @discardableResult
    public static func dissolve(_ doc: inout ArchiDocument, groups names: Set<String>) -> Int {
        let lower = Set(names.map { $0.lowercased() })
        var c = 0
        for i in doc.entities.indices where doc.entities[i].props["group"].map({ lower.contains($0.lowercased()) }) == true { doc.entities[i].props["group"] = nil; c += 1 }
        return c
    }

    static func blockName(_ n: String, _ doc: ArchiDocument) -> String? {
        doc.blocks[n] != nil ? n : doc.blocks.keys.first { $0.caseInsensitiveCompare(n) == .orderedSame }
    }

    /// Block reference counts, nested references multiplied by their parents.
    public static func count(_ ents: [Entity], doc: ArchiDocument) -> [String: Int] {
        var out: [String: Int] = [:]
        func visit(_ e: Entity, _ mult: Int, _ depth: Int) {
            guard depth < 16, case .insert(let i) = e.geometry else { return }
            out[i.block, default: 0] += mult
            for c in doc.blocks[i.block]?.entities ?? [] { visit(c, mult, depth + 1) }
        }
        for e in ents { visit(e, 1, 0) }
        return out
    }
    /// Names of blocks referenced directly by a block.
    public static func references(_ name: String, doc: ArchiDocument) -> Set<String> {
        Set((doc.blocks[name]?.entities ?? []).compactMap { if case .insert(let i) = $0.geometry { return i.block }; return nil })
    }
    /// All blocks nested (at any depth) in a block, including itself.
    public static func nestedNames(_ name: String, doc: ArchiDocument) -> Set<String> {
        var seen: Set<String> = [name], queue = [name]
        while let n = queue.popLast() { for r in references(n, doc: doc) where !seen.contains(r) { seen.insert(r); queue.append(r) } }
        return seen
    }
    public static func isUnreferenced(_ name: String, doc: ArchiDocument) -> Bool {
        !doc.entities.contains { if case .insert(let i) = $0.geometry { return i.block == name }; return false }
            && !doc.blocks.values.contains { $0.entities.contains { if case .insert(let i) = $0.geometry { return i.block == name }; return false } }
    }

    /// Replaces references (in the drawing and inside other blocks). Returns the count replaced.
    @discardableResult
    public static func replace(_ doc: inout ArchiDocument, old: String, with new: String) -> Int {
        let newTags = Set((doc.blocks[new]?.entities ?? []).compactMap { $0.props["attdef"] })
        var c = 0
        func swap(_ e: inout Entity) {
            guard case .insert(var i) = e.geometry, i.block == old else { return }
            i.block = new
            i.attributes = i.attributes.filter { newTags.contains($0.key) }
            e.geometry = .insert(i); c += 1
        }
        for k in doc.entities.indices { swap(&doc.entities[k]) }
        for n in Array(doc.blocks.keys) where n != new {
            guard var b = doc.blocks[n] else { continue }
            for k in b.entities.indices { swap(&b.entities[k]) }
            doc.blocks[n] = b
        }
        return c
    }

    public static func invert(_ t: Transform2D) -> Transform2D? {
        let det = t.a * t.d - t.b * t.c
        guard abs(det) > 1e-15 else { return nil }
        var r = Transform2D.translation(.zero)
        r.a = t.d / det; r.b = -t.b / det; r.c = -t.c / det; r.d = t.a / det
        r.tx = -(r.a * t.tx + r.c * t.ty); r.ty = -(r.b * t.tx + r.d * t.ty)
        return r
    }

    /// Moves a block's base point to `base` (block coordinates) and compensates every reference so nothing moves.
    public static func setBase(_ doc: inout ArchiDocument, block: String, base: Vec2) {
        guard var b = doc.blocks[block] else { return }
        let delta = base - b.basePoint
        b.basePoint = base
        doc.blocks[block] = b
        func fix(_ e: inout Entity) {
            guard case .insert(var i) = e.geometry, i.block == block else { return }
            // Reference maps base → position; keep the same world placement.
            let v = Transform2D.rotation(i.rotation).applyVector(Vec2(delta.x * i.scale.x, delta.y * i.scale.y))
            i.position = i.position + v
            e.geometry = .insert(i)
        }
        for k in doc.entities.indices { fix(&doc.entities[k]) }
        for n in Array(doc.blocks.keys) {
            guard var bb = doc.blocks[n] else { continue }
            for k in bb.entities.indices { fix(&bb.entities[k]) }
            doc.blocks[n] = bb
        }
    }

    /// Adds missing attributes (with defaults) and removes attributes whose definition no longer exists.
    @discardableResult
    public static func syncAttributes(_ doc: inout ArchiDocument, block: String) -> Int {
        guard let b = doc.blocks[block] else { return 0 }
        let defs = b.entities.compactMap { e -> (String, String)? in e.props["attdef"].map { ($0, e.props["default"] ?? "") } }
        let tags = Set(defs.map(\.0))
        var c = 0
        for i in doc.entities.indices {
            guard case .insert(var ins) = doc.entities[i].geometry, ins.block == block else { continue }
            var a = ins.attributes.filter { tags.contains($0.key) }
            for (t, d) in defs where a[t] == nil { a[t] = d }
            if a != ins.attributes { ins.attributes = a; doc.entities[i].geometry = .insert(ins) }
            c += 1
        }
        return c
    }

    /// Rows for attribute extraction: header then one row per reference.
    public static func extractionRows(_ ents: [Entity], doc: ArchiDocument) -> [[String]] {
        var tags: [String] = []
        for e in ents {
            guard case .insert(let i) = e.geometry else { continue }
            for t in (doc.blocks[i.block]?.entities.compactMap { $0.props["attdef"] } ?? []) + i.attributes.keys.sorted() where !tags.contains(t) { tags.append(t) }
        }
        var rows = [["ID", "Block", "X", "Y", "Layer", "Rotation", "ScaleX", "ScaleY"] + tags]
        for e in ents {
            guard case .insert(let i) = e.geometry else { continue }
            rows.append(["\(e.id)", i.block, fmt(i.position.x), fmt(i.position.y), e.layer, fmt(deg(i.rotation)), fmt(i.scale.x), fmt(i.scale.y)] + tags.map { i.attributes[$0] ?? "" })
        }
        return rows
    }
    public static func csvField(_ v: String) -> String {
        v.contains(",") || v.contains("\"") || v.contains("\n") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    /// Flip parameter: mirrors the reference about its insertion point along its local X (horizontal) or Y (vertical) axis.
    public static func flip(_ e: inout Entity, vertical: Bool) {
        guard case .insert(var i) = e.geometry else { return }
        if vertical { i.scale.y = -i.scale.y } else { i.scale.x = -i.scale.x }
        e.geometry = .insert(i)
        let key = vertical ? "flipV" : "flipH"
        e.props[key] = e.props[key] == "1" ? nil : "1"
    }
}
