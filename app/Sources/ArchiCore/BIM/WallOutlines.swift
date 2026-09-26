// Oanarina Archi Tool — GPL-3.0-or-later
// Outlines of groups of walls (slabs/roofs by walls, BIM-048): the union of the mitred wall outlines as drawn in plan.
import Foundation

public enum WallOutlines {
    /// Union of the plan outlines of the given walls (outer loops CCW, holes CW).
    public static func union(ids: [EntityID], doc: ArchiDocument) -> [[Vec2]] {
        let ctx = PlanRepresentation.context(doc)
        var acc: [[Vec2]] = []
        for id in ids {
            guard let el = doc.element(id), let f = ctx.frames[el.id] ?? WallFrame(el) else { continue }
            var l = RG.dedupe(ctx.outline(f), closed: true)
            guard l.count >= 3, abs(GeometryOps.signedArea(l)) > 1e-9 else { continue }
            if GeometryOps.signedArea(l) < 0 { l.reverse() }
            acc = acc.isEmpty ? PolygonBoolean.normalize([l]) : PolygonBoolean.apply(.union, acc, [l])
        }
        return acc
    }

    /// Outer outline of a closed ring of walls (`inner` = the inside face loop instead). nil when the walls enclose nothing.
    public static func outer(ids: [EntityID], doc: ArchiDocument, inner: Bool = false) -> [Vec2]? {
        let u = union(ids: ids, doc: doc)
        let holes = u.filter { GeometryOps.signedArea($0) < 0 }
        guard !holes.isEmpty else { return nil }
        if inner {
            return holes.max { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }.map { CommandHelpers.simplify(Array($0.reversed())) }
        }
        // The outer loop that contains a hole (the ring's outside).
        let outers = u.filter { GeometryOps.signedArea($0) > 0 }
        let o = outers.first { o in holes.contains { GeometryOps.pointInPolygon($0[0], o) } }
        return o.map { CommandHelpers.simplify($0) }
    }

    /// Outside outline of the walls enclosing a point on a level.
    public static func outer(around p: Vec2, doc: ArchiDocument, level: Int) -> [Vec2]? {
        let ids = RoomBounding.boundingElements(doc: doc, level: level).filter { if case .wall = $0.geometry { return true }; return false }.map(\.id)
        let u = union(ids: ids, doc: doc)
        // Smallest outer loop containing the point whose hole (courtyard) does not contain it.
        let outers = u.filter { GeometryOps.signedArea($0) > 0 && GeometryOps.pointInPolygon(p, $0) }
        guard let o = outers.min(by: { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }) else { return nil }
        return CommandHelpers.simplify(o)
    }
}
