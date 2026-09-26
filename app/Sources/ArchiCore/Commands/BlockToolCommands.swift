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
            let k = try await ed.getWord("Enter group name or [List/Add/Remove/Explode/REName/Selectable/Description]", keywords: ["List", "Add", "Remove", "Explode", "REName", "Selectable", "Description"]) ?? ""
            switch k {
            case "List":
                let g = BlockTools.groups(ed.doc)
                if g.isEmpty { ed.print("No groups.") }
                for (n, ids) in g.sorted(by: { $0.key < $1.key }) {
                    ed.print("  \(n): \(ids.count) object(s)\(BlockTools.isSelectable(n, ed.doc) ? "" : " (unselectable)")\(BlockTools.description(n, ed.doc).map { " — " + $0 } ?? "")")
                }
            case "Selectable", "Description":
                guard let n = try await ed.getWord("Enter group name"), let name = BlockTools.groups(ed.doc).keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Group not found.") }
                if k == "Selectable" {
                    let on = !BlockTools.isSelectable(name, ed.doc)
                    BlockTools.setSelectable(name, on, &ed.doc)
                    ed.print("Group \(name) is \(on ? "selectable" : "unselectable").")
                } else {
                    let d = try await ed.getString("Enter group description", defaultValue: BlockTools.description(name, ed.doc)) ?? ""
                    if d.isEmpty { ed.doc.variables["GROUPDESC:" + name.uppercased()] = nil } else { ed.doc.setVariable("GROUPDESC:" + name, d) }
                }
            case "Add", "Remove":
                guard let n = try await ed.getWord("Enter group name"), let name = BlockTools.groups(ed.doc).keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Group not found.") }
                ed.selection = []
                let saved = ed.doc.variable("PICKSTYLE")
                ed.doc.setVariable("PICKSTYLE", "0")
                let ids = try await ed.getSelection(k == "Add" ? "Select objects to add" : "Select objects to remove")
                if let s = saved { ed.doc.setVariable("PICKSTYLE", s) } else { ed.doc.variables.removeValue(forKey: "PICKSTYLE") }
                for id in ids {
                    let cur = BlockTools.group(of: id, ed.doc)
                    BlockTools.setGroup(id, k == "Add" ? name : (cur == name ? nil : cur), &ed.doc)
                }
            case "Explode":
                guard let n = try await ed.getWord("Enter group name") else { return }
                let c = BlockTools.dissolve(&ed.doc, groups: [n])
                guard c > 0 else { throw CommandError.invalid("Group not found.") }
                ed.print("Group \(n) exploded.")
            case "REName":
                guard let o = try await ed.getWord("Enter old group name"), let n = try await ed.getWord("Enter new group name"), BlockCommands.validName(n) else { return }
                var c = 0
                for i in ed.doc.entities.indices where ed.doc.entities[i].props["group"]?.caseInsensitiveCompare(o) == .orderedSame { ed.doc.entities[i].props["group"] = n; c += 1 }
                for i in ed.doc.elements.indices where ed.doc.elements[i].props["group"]?.caseInsensitiveCompare(o) == .orderedSame { ed.doc.elements[i].props["group"] = n; c += 1 }
                if c == 0 { throw CommandError.invalid("Group not found.") }
            default:
                var name = k
                if name.isEmpty || name == "*" { var j = 1; while BlockTools.groups(ed.doc)["*A\(j)"] != nil { j += 1 }; name = "*A\(j)" }
                guard name.hasPrefix("*") || BlockCommands.validName(name) else { throw CommandError.invalid("Invalid group name.") }
                guard BlockTools.groups(ed.doc)[name] == nil else { throw CommandError.invalid("Group \(name) already exists.") }
                ed.selection = pre
                let ids = try await ed.getSelection("Select objects")
                guard !ids.isEmpty else { return }
                for id in ids { BlockTools.setGroup(id, name, &ed.doc) }
                ed.print("Group \(name) created with \(ids.count) object(s).")
            }
            ed.selection = []
        }
    }
    static var ungroup: CommandDef {
        CommandDef("UNGROUP", aliases: ["UNG"], category: "Blocks", summary: "Dissolves the groups of the selected objects.") { ed in
            let ids = try await ed.getSelection("Select group")
            let names = Set(ids.compactMap { BlockTools.group(of: $0, ed.doc) })
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

    @MainActor static func outputExtraction(_ ed: Editor, _ rows: [[String]]) async throws {
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
            let k = try await ed.getKeyword("Extract", ["Attributes", "Counts", "Properties"], defaultValue: "Attributes") ?? "Attributes"
            var rows: [[String]]
            if k == "Properties" {
                // Object properties of drawing objects and building elements (ANN-061).
                let ids = ed.selection.isEmpty ? try await ed.getSelection("Select objects (Enter = all)") : Array(ed.selection)
                ed.selection = []
                rows = BlockTools.propertyRows(ids.isEmpty ? ed.doc.entities.map(\.id) + ed.doc.elements.map(\.id) : ids, doc: ed.doc)
                guard rows.count > 1 else { throw CommandError.invalid("Nothing to extract.") }
                return try await outputExtraction(ed, rows)
            }
            let ents = try await extractionTargets(ed)
            guard !ents.isEmpty else { throw CommandError.invalid("No block references found.") }
            if k == "Counts" {
                rows = [["Block", "Count"]] + BlockTools.count(ents, doc: ed.doc).sorted { $0.key < $1.key }.map { [$0.key, "\($0.value)"] }
            } else {
                rows = BlockTools.extractionRows(ents, doc: ed.doc)
            }
            try await outputExtraction(ed, rows)
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
    /// Groups (BLK-015): drafting entities and BIM elements sharing the prop "group" = name.
    /// Property table for data extraction (ANN-061): one row per object with id, type, layer, colour, length, area,
    /// level and name, followed by every custom property key found (sorted).
    public static func propertyRows(_ ids: [EntityID], doc: ArchiDocument) -> [[String]] {
        var keys = Set<String>()
        for id in ids {
            let props = doc.entity(id)?.props ?? doc.element(id)?.props ?? [:]
            for k in props.keys where !k.hasPrefix("_") && !k.hasPrefix("xdata:") && k != "group" { keys.insert(k) }
        }
        let extra = keys.sorted().prefix(40)
        var rows: [[String]] = [["Id", "Type", "Layer", "Color", "Length", "Area", "Level", "Name"] + extra]
        for id in ids.sorted() {
            if let e = doc.entity(id) {
                let len = GeometryOps.length(e.geometry, doc: doc)
                let area = GeometryOps.area(e.geometry, doc: doc)
                rows.append(["\(id)", e.typeName, e.layer, e.color.text, len > 0 ? fmt(len, 2) : "", area.map { fmt($0, 2) } ?? "", "", ""] + extra.map { e.props[$0] ?? "" })
            } else if let el = doc.element(id) {
                let f = CommandHelpers.footprint(el, doc: doc)
                let area = f.count >= 3 ? abs(GeometryOps.signedArea(f)) : 0
                var len = 0.0
                switch el.geometry {
                case .wall(let w): len = w.length
                case .beam(let b): len = b.start.distance(to: b.end)
                case .gridLine(let g): len = g.start.distance(to: g.end)
                case .curtainWall(let c): len = c.start.distance(to: c.end)
                default: break
                }
                rows.append(["\(id)", el.typeName, el.layer, "", len > 0 ? fmt(len, 2) : "", area > 0 ? fmt(area, 2) : "",
                             doc.level(el.level)?.name ?? "\(el.level)", el.name] + extra.map { el.props[$0] ?? "" })
            }
        }
        return rows
    }

    public static func groups(_ doc: ArchiDocument) -> [String: [EntityID]] {
        var out: [String: [EntityID]] = [:]
        for e in doc.entities { if let g = e.props["group"] { out[g, default: []].append(e.id) } }
        for el in doc.elements { if let g = el.props["group"] { out[g, default: []].append(el.id) } }
        return out
    }
    /// Group of an entity or element.
    public static func group(of id: EntityID, _ doc: ArchiDocument) -> String? { doc.entity(id)?.props["group"] ?? doc.element(id)?.props["group"] }
    /// Sets (or clears with nil) the group of an entity or element.
    public static func setGroup(_ id: EntityID, _ name: String?, _ doc: inout ArchiDocument) {
        if let i = doc.entityIndex(id) { doc.entities[i].props["group"] = name }
        else if let i = doc.elementIndex(id) { doc.elements[i].props["group"] = name }
    }
    /// Unselectable groups (GROUP Selectable off): picking a member selects only that member.
    public static func isSelectable(_ group: String, _ doc: ArchiDocument) -> Bool { doc.variable("GROUPUNSEL:" + group) == nil }
    public static func setSelectable(_ group: String, _ on: Bool, _ doc: inout ArchiDocument) {
        if on { doc.variables["GROUPUNSEL:" + group.uppercased()] = nil } else { doc.setVariable("GROUPUNSEL:" + group, "1") }
    }
    public static func description(_ group: String, _ doc: ArchiDocument) -> String? { doc.variable("GROUPDESC:" + group) }
    @discardableResult
    public static func dissolve(_ doc: inout ArchiDocument, groups names: Set<String>) -> Int {
        let lower = Set(names.map { $0.lowercased() })
        var c = 0
        for i in doc.entities.indices where doc.entities[i].props["group"].map({ lower.contains($0.lowercased()) }) == true { doc.entities[i].props["group"] = nil; c += 1 }
        for i in doc.elements.indices where doc.elements[i].props["group"].map({ lower.contains($0.lowercased()) }) == true { doc.elements[i].props["group"] = nil; c += 1 }
        for n in names { doc.variables["GROUPUNSEL:" + n.uppercased()] = nil; doc.variables["GROUPDESC:" + n.uppercased()] = nil }
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
