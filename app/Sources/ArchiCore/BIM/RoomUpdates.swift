// Oanarina Archi Tool — GPL-3.0-or-later
// Associative rooms (BIM-090/091): rooms placed by picking inside walls keep their seed point (props seedX/seedY) and
// re-derive their boundary — and so their area, perimeter and tag values — whenever the room-bounding walls,
// curtain walls, columns or room separation lines of their level change. props roomAuto = "0" freezes a room.
import Foundation

public enum RoomUpdates {
    static func seed(_ el: BIMElement) -> Vec2? {
        guard el.props["areaScheme"] == nil, el.props["roomAuto"] != "0",
              let x = el.props["seedX"].flatMap(Double.init), let y = el.props["seedY"].flatMap(Double.init) else { return nil }
        return Vec2(x, y)
    }

    /// True when the document has associative rooms.
    public static func hasAuto(_ doc: ArchiDocument) -> Bool {
        doc.elements.contains { el in if case .space = el.geometry { return seed(el) != nil }; return false }
    }

    /// Fingerprint of everything that bounds rooms on a level (bounding elements, their levels and the separation lines).
    static func signature(_ doc: ArchiDocument, level: Int) -> Int {
        var h = Hasher()
        for el in RoomBounding.boundingElements(doc: doc, level: level) { h.combine(el.id); h.combine(el.geometry); h.combine(el.level); h.combine(el.props["roomBounding"]) }
        for g in ArchitectureCommands.separators(doc, level: level) { h.combine(g) }
        h.combine(doc.units.mm)
        return h.finalize()
    }

    private static let lock = NSLock()
    private static var cache: [String: [Vec2]?] = [:]

    /// Boundary of the room around a seed (memoised on the level's bounding fingerprint).
    static func boundary(seed p: Vec2, level: Int, doc: ArchiDocument, signature sig: Int) -> [Vec2]? {
        let key = "\(sig)|\(level)|\(p.x),\(p.y)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let b = RoomBounding.boundary(at: p, doc: doc, level: level, extraCurves: ArchitectureCommands.separators(doc, level: level)).map { pts -> [Vec2] in
            GeometryOps.signedArea(pts) < 0 ? Array(pts.reversed()) : pts
        }
        lock.lock()
        if cache.count > 4096 { cache.removeAll() }
        cache[key] = .some(b)
        lock.unlock()
        return b
    }

    /// Re-derives the boundaries of associative rooms. Rooms that are no longer enclosed keep their last boundary and
    /// are flagged props roomUnbounded = "1" (cleared again once enclosed). Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        let idx = doc.elements.indices.filter { i in if case .space = doc.elements[i].geometry { return seed(doc.elements[i]) != nil }; return false }
        guard !idx.isEmpty else { return false }
        let snapshot = doc
        var sigs: [Int: Int] = [:]
        var changed = false
        for i in idx {
            let el = snapshot.elements[i]
            guard case .space(var s) = el.geometry, let p = seed(el) else { continue }
            let sig = sigs[el.level] ?? signature(snapshot, level: el.level)
            sigs[el.level] = sig
            guard let b = boundary(seed: p, level: el.level, doc: snapshot, signature: sig), b.count >= 3 else {
                if doc.elements[i].props["roomUnbounded"] != "1" { doc.elements[i].props["roomUnbounded"] = "1"; changed = true }
                continue
            }
            if doc.elements[i].props["roomUnbounded"] != nil { doc.elements[i].props["roomUnbounded"] = nil; changed = true }
            if b.count != s.boundary.count || zip(b, s.boundary).contains(where: { !$0.0.isClose($0.1, tol: 1e-7) }) {
                s.boundary = b; doc.elements[i].geometry = .space(s); changed = true
            }
        }
        return changed
    }
}
