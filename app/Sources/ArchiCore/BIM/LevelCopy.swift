// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Copying building elements between levels (Revit "Paste Aligned to Selected Levels").
public enum LevelCopy {
    /// Copies elements (and the doors/windows hosted in copied walls) to each target level, aligned in plan.
    /// When the selection spans several levels, the lowest selected level maps to each target and the others keep
    /// their relative storey. Level constraints move by the same number of storeys; room numbers move by 100 per storey.
    /// Returns the ids of the new elements.
    @discardableResult
    public static func copy(_ doc: inout ArchiDocument, ids: [EntityID], toLevels targets: [Int]) -> [EntityID] {
        let order = doc.levels.sorted { $0.elevation < $1.elevation }.map(\.id)
        func idx(_ l: Int) -> Int? { order.firstIndex(of: l) }
        let idSet = Set(ids)
        var src = doc.elements.filter { idSet.contains($0.id) }
        let walls = Set(src.compactMap { el -> EntityID? in if case .wall = el.geometry { return el.id }; return nil })
        for el in doc.elements where !idSet.contains(el.id) {
            if case .opening(let o) = el.geometry, walls.contains(o.hostWall) { src.append(el) }
        }
        guard let base = src.compactMap({ idx($0.level) }).min() else { return [] }
        var created: [EntityID] = []
        for t in targets {
            guard let ti = idx(t), ti != base else { continue }
            let shift = ti - base
            func moved(_ l: Int?) -> Int? { guard let l = l, let i = idx(l), i + shift >= 0, i + shift < order.count else { return nil }; return order[i + shift] }
            var map: [EntityID: EntityID] = [:]
            var pending: [BIMElement] = []
            // Non-hosted elements first, so openings can find their copied walls.
            func isOpening(_ e: BIMElement) -> Bool { if case .opening = e.geometry { return true }; return false }
            for el in src.filter({ !isOpening($0) }) + src.filter(isOpening) {
                guard let nl = moved(el.level) else { continue }
                var c = el
                c.level = nl
                switch c.geometry {
                case .opening(var o):
                    guard let h = map[o.hostWall] else { continue }
                    o.hostWall = h; o.mark = nil; c.geometry = .opening(o)
                case .wall(var w):
                    if let tl = w.topLevel { w.topLevel = moved(tl) }
                    c.geometry = .wall(w)
                case .stair(var s):
                    if let tl = s.topLevel { s.topLevel = moved(tl) }
                    c.geometry = .stair(s)
                case .space(var sp):
                    if let n = Int(sp.number) { sp.number = "\(n + 100 * shift)" }
                    c.geometry = .space(sp)
                default: break
                }
                c.id = doc.allocateID()
                map[el.id] = c.id
                pending.append(c)
            }
            // Remap references between copied elements; drop references to elements that were not copied.
            for i in pending.indices {
                for key in ["joinStart", "joinEnd", "attachTopTo", "attachBaseTo", "rampGroup"] {
                    guard let v = pending[i].props[key], let old = Int(v) else { continue }
                    pending[i].props[key] = map[old].map { "\($0)" }
                }
            }
            doc.elements += pending
            created += pending.map(\.id)
        }
        BIMConstraints.sync(&doc)
        return created
    }
}
