// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Block editor (BEDIT, BLK-004) and in-place reference editing (REFEDIT, BLK-005).
///
/// BEDIT shows a block definition alone in model space: its objects are copied into the drawing tagged with the
/// drafting-view marker "*BEDIT:name" (DRAFTINGEDIT / DRAFTINGSTART), so rendering and picking isolate them exactly as for
/// drafting views, and objects drawn while editing join the block. BCLOSE saves (or discards) them back into the
/// definition; every reference updates.
///
/// REFEDIT edits one reference in place: its objects are placed in world coordinates through the reference transform
/// (tagged "_refedit"), the reference itself is set aside (REFEDITINSERT), the rest of the drawing stays visible, and
/// REFCLOSE maps the edited objects back through the inverse transform. State lives in document variables, so undo, save
/// and reopen keep it consistent.
public enum BlockEditing {
    public static let beditVar = "BEDITBLOCK"
    public static let refeditVar = "REFEDITBLOCK"
    public static let refeditInsertVar = "REFEDITINSERT"
    public static let refeditStartVar = "REFEDITSTART"
    public static let refeditTag = "_refedit"
    public enum EditError: Error, Equatable, CustomStringConvertible {
        case busy, notFound(String), selfReference(String), notAReference
        public var description: String {
            switch self {
            case .busy: return "A block or reference is already being edited; close it first (BCLOSE / REFCLOSE)."
            case .notFound(let n): return "Block \(n) not found."
            case .selfReference(let n): return "Block \(n) would contain itself."
            case .notAReference: return "That is not a block reference."
            }
        }
    }

    static func marker(_ name: String) -> String { "*BEDIT:" + name }
    /// Name of the block open in the block editor.
    public static func editingBlock(_ doc: ArchiDocument) -> String? { doc.variable(beditVar) }
    /// Name of the block whose reference is edited in place.
    public static func refEditingBlock(_ doc: ArchiDocument) -> String? { doc.variable(refeditVar) }
    public static func isBusy(_ doc: ArchiDocument) -> Bool {
        doc.variable(beditVar) != nil || doc.variable(refeditVar) != nil || doc.variable(DraftingViews.editing) != nil
    }

    /// Whether `entities` reference block `name`, directly or through nested blocks (cycle guard for BLOCK / BEDIT).
    public static func references(_ entities: [Entity], block name: String, doc: ArchiDocument) -> Bool {
        var seen = Set<String>()
        var queue: [String] = entities.compactMap { if case .insert(let i) = $0.geometry { return i.block }; return nil }
        while let n = queue.popLast() {
            if n.caseInsensitiveCompare(name) == .orderedSame { return true }
            guard seen.insert(n.uppercased()).inserted, let b = doc.blocks[n] else { continue }
            for e in b.entities { if case .insert(let i) = e.geometry { queue.append(i.block) } }
        }
        return false
    }

    // MARK: BEDIT

    /// Opens block `name` (created empty when missing) in the block editor. Returns the number of objects shown.
    @discardableResult
    public static func beginBlockEdit(_ name: String, doc: inout ArchiDocument) throws -> Int {
        guard !isBusy(doc) else { throw EditError.busy }
        let key = doc.blocks.keys.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        if doc.blocks[key] == nil { doc.blocks[key] = Block(name: key) }
        let b = doc.blocks[key]!
        let m = marker(key)
        doc.setVariable("DRAFTINGSTART", "\(doc.nextID)")
        var map: [EntityID: EntityID] = [:]
        for var e in b.entities { let old = e.id; e.props["draftingView"] = m; map[old] = doc.add(e) }
        BlockConstraints.restore(key, map: map, doc: &doc)
        doc.setVariable(DraftingViews.editing, m)
        doc.setVariable(beditVar, key)
        return b.entities.count
    }

    /// Objects currently in the block editor.
    public static func blockEditContent(_ doc: ArchiDocument) -> [Entity] {
        guard let n = editingBlock(doc) else { return [] }
        let m = marker(n), start = doc.variable("DRAFTINGSTART").flatMap(Int.init) ?? Int.max
        return doc.entities.filter { $0.props["draftingView"] == m || $0.id >= start }
    }

    /// Writes the block editor content into the definition without closing (BSAVE). Returns the object count.
    @discardableResult
    public static func saveBlockEdit(doc: inout ArchiDocument) throws -> Int {
        guard let n = editingBlock(doc) else { return 0 }
        var ents = blockEditContent(doc)
        for i in ents.indices { ents[i].props["draftingView"] = nil }
        if references(ents, block: n, doc: doc) { throw EditError.selfReference(n) }
        doc.blocks[n]?.entities = ents
        // Constraints among the block's objects are saved with the definition (BLK-027); dynamic variants follow.
        BlockConstraints.capture(n, ids: Set(ents.map(\.id)), doc: &doc)
        DynamicBlocks.regenerate(n, &doc)
        return ents.count
    }

    /// Closes the block editor, saving the content into the definition (or discarding the changes).
    @discardableResult
    public static func endBlockEdit(save: Bool, doc: inout ArchiDocument) throws -> Int {
        guard editingBlock(doc) != nil else { return 0 }
        let n = save ? try saveBlockEdit(doc: &doc) : 0
        let content = Set(blockEditContent(doc).map(\.id))
        doc.remove(ids: content)
        BlockConstraints.prune(ids: content, doc: &doc)
        doc.variables[DraftingViews.editing] = nil
        doc.variables["DRAFTINGSTART"] = nil
        doc.variables[beditVar] = nil
        return n
    }

    // MARK: REFEDIT

    /// Transform from block coordinates to the drawing for a reference.
    public static func transform(_ ins: InsertGeom, doc: ArchiDocument) -> Transform2D? {
        guard let b = doc.blocks[ins.block] else { return nil }
        return ins.transform * .translation(-b.basePoint)
    }

    /// Starts editing reference `id` in place. Returns the ids of the objects placed for editing.
    @discardableResult
    public static func beginRefEdit(_ id: EntityID, doc: inout ArchiDocument) throws -> [EntityID] {
        guard !isBusy(doc) else { throw EditError.busy }
        guard let idx = doc.entityIndex(id), case .insert(let ins) = doc.entities[idx].geometry else { throw EditError.notAReference }
        guard let b = doc.blocks[ins.block], let t = transform(ins, doc: doc) else { throw EditError.notFound(ins.block) }
        let ref = doc.entities[idx]
        guard let data = try? JSONEncoder().encode(ref), let json = String(data: data, encoding: .utf8) else { throw EditError.notAReference }
        doc.setVariable(refeditInsertVar, "\(idx)|" + json)
        doc.setVariable(refeditVar, ins.block)
        doc.entities.remove(at: idx)
        doc.setVariable(refeditStartVar, "\(doc.nextID)")
        var out: [EntityID] = []
        for var e in b.entities {
            e.geometry = GeometryOps.transform(e.geometry, t)
            // Attribute definitions show the reference's values while editing only as their tags.
            e.props[refeditTag] = "1"
            if e.layer == "0" { e.props["_refeditLayer0"] = "1"; e.layer = ref.layer }
            out.append(doc.add(e))
        }
        return out
    }

    /// The reference set aside while editing in place.
    public static func refEditReference(_ doc: ArchiDocument) -> (index: Int, entity: Entity)? {
        guard let s = doc.variable(refeditInsertVar), let bar = s.firstIndex(of: "|"), let i = Int(s[..<bar]),
              let e = try? JSONDecoder().decode(Entity.self, from: Data(s[s.index(after: bar)...].utf8)) else { return nil }
        return (i, e)
    }

    /// Objects in the reference-edit working set: the placed block objects and anything drawn since REFEDIT started.
    public static func refEditContent(_ doc: ArchiDocument) -> [Entity] {
        guard refEditingBlock(doc) != nil else { return [] }
        let start = doc.variable(refeditStartVar).flatMap(Int.init) ?? Int.max
        return doc.entities.filter { $0.props[refeditTag] != nil || $0.id >= start }
    }

    /// Adds existing drawing objects to the working set (REFSET Add): they move into the block on save.
    public static func addToWorkingSet(_ ids: [EntityID], doc: inout ArchiDocument) -> Int {
        guard refEditingBlock(doc) != nil else { return 0 }
        var n = 0
        for id in ids { if let i = doc.entityIndex(id), doc.entities[i].props[refeditTag] == nil { doc.entities[i].props[refeditTag] = "added"; n += 1 } }
        return n
    }

    /// Ends in-place editing: with `save` the working set is mapped back into block coordinates and becomes the block
    /// definition; the reference is restored either way. Returns the number of objects saved.
    @discardableResult
    public static func endRefEdit(save: Bool, doc: inout ArchiDocument) throws -> Int {
        guard let name = refEditingBlock(doc) else { return 0 }
        let work = refEditContent(doc)
        var saved = 0
        if save, let ref = refEditReference(doc), case .insert(let ins) = ref.entity.geometry, let t = transform(ins, doc: doc) {
            let inv = t.inverted
            var ents: [Entity] = []
            for var e in work {
                e.geometry = GeometryOps.transform(e.geometry, inv)
                if e.props.removeValue(forKey: "_refeditLayer0") != nil { e.layer = "0" }
                e.props[refeditTag] = nil
                ents.append(e)
            }
            if references(ents, block: name, doc: doc) { throw EditError.selfReference(name) }
            doc.blocks[name]?.entities = ents
            saved = ents.count
        }
        if save { doc.remove(ids: Set(work.map(\.id))) }
        else {
            // Discard: placed and new objects go; objects added from the drawing stay where they were.
            let start = doc.variable(refeditStartVar).flatMap(Int.init) ?? Int.max
            doc.remove(ids: Set(work.filter { $0.props[refeditTag] == "1" || ($0.id >= start && $0.props[refeditTag] != "added") }.map(\.id)))
            for i in doc.entities.indices where doc.entities[i].props[refeditTag] == "added" { doc.entities[i].props[refeditTag] = nil }
        }
        if let ref = refEditReference(doc) { doc.entities.insert(ref.entity, at: min(max(ref.index, 0), doc.entities.count)) }
        doc.variables[refeditVar] = nil
        doc.variables[refeditInsertVar] = nil
        doc.variables[refeditStartVar] = nil
        return saved
    }
}
