// Oanarina Archi Tool — GPL-3.0-or-later
// Wall flip (BIM-025), wall split at a point or by levels (BIM-024) and opening flips (BIM-038).
import Foundation

public enum WallTools {
    /// Reverses a wall's direction (swaps its interior/exterior faces for layered types) while keeping its body, hosted
    /// openings, sweeps and door swings where they are.
    @discardableResult
    public static func flip(_ doc: inout ArchiDocument, wall id: EntityID) -> Bool {
        guard let i = doc.elementIndex(id), case .wall(var g) = doc.elements[i].geometry, let f = WallFrame(id: id, level: doc.elements[i].level, g) else { return false }
        swap(&g.start, &g.end)
        g.bulge = -g.bulge
        switch g.justification { case .left: g.justification = .right; case .right: g.justification = .left; case .center: break }
        g.sweeps = g.sweeps.map { var s = $0; s.side = -s.side; return s }
        doc.elements[i].geometry = .wall(g)
        doc.elements[i].props["flipped"] = doc.elements[i].props["flipped"] == "1" ? nil : "1"
        for k in doc.elements.indices {
            guard case .opening(var o) = doc.elements[k].geometry, o.hostWall == id else { continue }
            o.offset = f.L - o.offset
            o.flipFacing.toggle(); o.flipHand.toggle()
            doc.elements[k].geometry = .opening(o)
        }
        return true
    }

    /// Flips hosted openings: hand (hinge side), facing (swing/exterior side) or both.
    public static func flipOpening(_ doc: inout ArchiDocument, _ id: EntityID, hand: Bool, facing: Bool) -> Bool {
        guard let i = doc.elementIndex(id), case .opening(var o) = doc.elements[i].geometry else { return false }
        if hand { o.flipHand.toggle() }
        if facing { o.flipFacing.toggle() }
        doc.elements[i].geometry = .opening(o)
        return true
    }

    /// Splits a wall at the centreline position nearest to `p`. Returns the new wall's id (the second piece), or nil
    /// when the point is at an end or an opening straddles it.
    public static func split(_ doc: inout ArchiDocument, wall id: EntityID, at p: Vec2, minPiece: Double = 1) -> EntityID? {
        guard let i = doc.elementIndex(id), case .wall(let g) = doc.elements[i].geometry, let f = WallFrame(id: id, level: doc.elements[i].level, g) else { return nil }
        let s = min(max(f.project(p).s, 0), f.L)
        guard s > minPiece, s < f.L - minPiece else { return nil }
        for el in doc.elements { if case .opening(let o) = el.geometry, o.hostWall == id, abs(o.offset - s) < o.width / 2 + 1e-9 { return nil } }
        let q = f.pos(s) - f.left(s) * g.centerOffset
        var a = g, b = g
        a.end = q; b.start = q
        if abs(g.bulge) > 1e-12 {
            let sweep = 4 * atan(g.bulge), t = s / f.L
            a.bulge = tan(sweep * t / 4); b.bulge = tan(sweep * (1 - t) / 4)
        }
        doc.elements[i].geometry = .wall(a)
        var el2 = doc.elements[i]
        el2.geometry = .wall(b)
        let nid = doc.addElement(.wall(b), level: el2.level, layer: el2.layer, material: el2.material, name: el2.name)
        if let j = doc.elementIndex(nid) { doc.elements[j].props = el2.props }
        for k in doc.elements.indices {
            guard case .opening(var o) = doc.elements[k].geometry, o.hostWall == id, o.offset > s else { continue }
            o.hostWall = nid; o.offset -= s
            doc.elements[k].geometry = .opening(o)
        }
        return nid
    }

    /// Absolute base and top elevations of a wall.
    public static func span(_ g: WallGeom, level: Int, doc: ArchiDocument) -> (base: Double, top: Double) {
        let base = (doc.level(level)?.elevation ?? 0) + g.baseOffset
        if let t = g.topLevel, let tl = doc.level(t) { return (base, tl.elevation + g.topOffset) }
        return (base, base + g.height)
    }

    /// Splits a wall at every level elevation strictly inside its height: one wall per storey, each hosted on its level
    /// (openings and sweeps move to the piece that contains them). Returns the ids of all pieces (original first).
    public static func splitByLevels(_ doc: inout ArchiDocument, wall id: EntityID) -> [EntityID] {
        guard let i = doc.elementIndex(id), case .wall(let g) = doc.elements[i].geometry else { return [] }
        let lvl = doc.elements[i].level
        let (z0, z1) = span(g, level: lvl, doc: doc)
        let cuts = doc.levels.filter { $0.elevation > z0 + 1 && $0.elevation < z1 - 1 }.sorted { $0.elevation < $1.elevation }
        guard !cuts.isEmpty else { return [id] }
        let bounds = [z0] + cuts.map(\.elevation) + [z1]
        let src = doc.elements[i]
        var ids: [EntityID] = []
        for k in 0..<(bounds.count - 1) {
            let lo = bounds[k], hi = bounds[k + 1]
            let pieceLevel = k == 0 ? lvl : cuts[k - 1].id
            let lvElev = doc.level(pieceLevel)?.elevation ?? 0
            var w = g
            w.baseOffset = lo - lvElev
            w.height = hi - lo
            if k < bounds.count - 2 { w.topLevel = cuts[k].id; w.topOffset = 0 } else { w.topLevel = g.topLevel; w.topOffset = g.topOffset }
            w.sweeps = g.sweeps.filter { z0 + $0.elevation >= lo - 1e-9 && z0 + $0.elevation < hi - 1e-9 }.map { var s = $0; s.elevation = z0 + $0.elevation - lo; return s }
            if k == 0 {
                doc.elements[i].geometry = .wall(w); ids.append(id)
            } else {
                let nid = doc.addElement(.wall(w), level: pieceLevel, layer: src.layer, material: src.material, name: src.name)
                if let j = doc.elementIndex(nid) { doc.elements[j].props = src.props }
                ids.append(nid)
            }
        }
        for k in doc.elements.indices {
            guard case .opening(var o) = doc.elements[k].geometry, o.hostWall == id else { continue }
            let z = z0 + o.sill
            guard let piece = (0..<(bounds.count - 1)).last(where: { z >= bounds[$0] - 1e-6 }) else { continue }
            o.hostWall = ids[piece]; o.sill = z - bounds[piece]
            doc.elements[k].geometry = .opening(o)
            doc.elements[k].level = piece == 0 ? lvl : cuts[piece - 1].id
        }
        return ids
    }
}
