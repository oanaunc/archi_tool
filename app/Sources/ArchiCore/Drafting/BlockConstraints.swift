// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Parametric block constraints (BLK-027): geometric and dimensional constraints applied to a block's objects in the
/// block editor are stored with the block definition (`BCONSTRAINTS:<block>`, a `ConstraintSet` in block entity ids),
/// restored when the block is edited again, and every named, driving length constraint (distance, horizontal/vertical
/// distance, length, radius, diameter) becomes a dynamic parameter of the block: DYNPROP sets its value per reference,
/// which solves the block's constraints into a variant definition (see `DynamicBlocks`).
public enum BlockConstraints {
    public static func key(_ block: String) -> String { "BCONSTRAINTS:" + block }

    public static func load(_ block: String, doc: ArchiDocument) -> ConstraintSet? {
        guard let s = doc.variable(key(block)), let d = s.data(using: .utf8), let cs = try? JSONDecoder().decode(ConstraintSet.self, from: d), !cs.constraints.isEmpty else { return nil }
        return cs
    }
    public static func store(_ cs: ConstraintSet?, block: String, doc: inout ArchiDocument) {
        guard let cs = cs, !cs.constraints.isEmpty else { doc.variables[key(block).uppercased()] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(cs), let s = String(data: d, encoding: .utf8) { doc.setVariable(key(block), s) }
    }

    static let parameterKinds: Set<ConstraintKind> = [.distance, .horizontalDistance, .verticalDistance, .length, .radius, .diameter]

    /// Named driving length constraints of a block, usable as dynamic parameters (name, current value).
    public static func parameters(_ block: String, doc: ArchiDocument) -> [(name: String, value: Double)] {
        guard let cs = load(block, doc: doc) else { return [] }
        return cs.constraints.compactMap { c in
            guard !c.reference, parameterKinds.contains(c.kind), let n = c.name, let v = c.value ?? Constraints.displayValue(c, set: cs, doc: blockDoc(doc.blocks[block]?.entities ?? [], cs)) else { return nil }
            return (n, v)
        }
    }

    /// A scratch document holding a block's objects and constraints.
    static func blockDoc(_ ents: [Entity], _ cs: ConstraintSet) -> ArchiDocument {
        var t = ArchiDocument()
        t.entities = ents
        t.nextID = (ents.map(\.id).max() ?? 0) + 1
        cs.save(&t)
        return t
    }

    /// The block objects re-solved with new values for named dimensional constraints.
    public static func solved(_ ents: [Entity], set cs0: ConstraintSet, values: [String: Double]) -> [Entity] {
        var cs = cs0
        var any = false
        for i in cs.constraints.indices {
            guard let n = cs.constraints[i].name, let v = values.first(where: { $0.key.caseInsensitiveCompare(n) == .orderedSame })?.value else { continue }
            cs.constraints[i].value = v; cs.constraints[i].expression = nil; any = true
        }
        guard any else { return ents }
        cs.snapshot = [:]
        var t = blockDoc(ents, cs)
        _ = Constraints.solve(&t)
        return t.entities
    }

    /// Moves the constraints among `ids` (block editor content) from the drawing's set into the block's set.
    public static func capture(_ block: String, ids: Set<EntityID>, doc: inout ArchiDocument) {
        var set = ConstraintSet.load(doc)
        let mine = set.constraints.filter { c in !c.refs.isEmpty && c.refs.allSatisfy { ids.contains($0.entity) } }
        var bs = ConstraintSet()
        bs.constraints = mine
        bs.nextID = (mine.map(\.id).max() ?? 0) + 1
        // User parameters used by the block's expressions travel with it.
        bs.parameters = set.parameters.filter { p in mine.contains { $0.expression?.range(of: p.key, options: .caseInsensitive) != nil } }
        store(bs, block: block, doc: &doc)
        _ = set
    }

    /// Removes the drawing constraints that reference any of `ids`.
    public static func prune(ids: Set<EntityID>, doc: inout ArchiDocument) {
        var set = ConstraintSet.load(doc)
        let n = set.constraints.count
        set.constraints.removeAll { c in c.refs.contains { ids.contains($0.entity) } }
        for id in ids { set.snapshot["\(id)"] = nil }
        if set.constraints.count != n || doc.variable(ConstraintSet.variable) != nil { set.save(&doc) }
    }

    /// Restores a block's constraints into the drawing for the block editor (`map`: block entity id → editor id).
    public static func restore(_ block: String, map: [EntityID: EntityID], doc: inout ArchiDocument) {
        guard let bs = load(block, doc: doc) else { return }
        var set = ConstraintSet.load(doc)
        for var c in bs.constraints {
            guard c.refs.allSatisfy({ map[$0.entity] != nil }) else { continue }
            c.refs = c.refs.map { CRef(map[$0.entity]!, $0.part) }
            c.id = set.nextID; set.nextID += 1
            if let n = c.name, set.named(n) != nil { c.name = set.freshName(String(n.prefix { $0.isLetter })) }
            set.constraints.append(c)
        }
        for (k, v) in bs.parameters where set.parameters[k] == nil { set.parameters[k] = v }
        set.save(&doc)
    }
}
