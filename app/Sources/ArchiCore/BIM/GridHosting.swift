// Oanarina Archi Tool — GPL-3.0-or-later
// Grid-hosted elements (BIM-005/006): columns placed at grid intersections remember the two grids (props gridHost =
// "idA,idB") and follow them when the grids move, rotate or change shape (straight, arc and multi-segment grids).
import Foundation

public enum GridHosting {
    public static let prop = "gridHost"

    /// A grid as drafting geometry (line, bulged arc or polyline) for exact intersections.
    public static func geometry(_ g: GridLineGeom) -> Geometry {
        if !g.bends.isEmpty { return .polyline(PolylineGeom(points: g.vertices)) }
        if abs(g.bulge) > 1e-12 { return .polyline(PolylineGeom([PolyVertex(g.start, bulge: g.bulge), PolyVertex(g.end)])) }
        return .line(LineGeom(g.start, g.end))
    }

    static func grids(_ doc: ArchiDocument) -> [(id: EntityID, g: GridLineGeom)] {
        doc.elements.compactMap { el in
            if case .gridLine(let g) = el.geometry, g.start.distance(to: g.end) > 1e-9 { return (el.id, g) }
            return nil
        }
    }

    /// Intersection points of two grids (empty when they do not cross within their extents).
    public static func intersections(_ a: GridLineGeom, _ b: GridLineGeom) -> [Vec2] {
        Intersections.of(geometry(a), geometry(b), doc: nil)
    }

    /// Every grid intersection of the document (optionally limited to some grids), each with the two grid ids.
    /// Points closer than `tolerance` are merged (the first pair wins).
    public static func allIntersections(_ doc: ArchiDocument, among ids: Set<EntityID>? = nil, tolerance: Double = 1e-6) -> [(point: Vec2, a: EntityID, b: EntityID)] {
        let gs = grids(doc).filter { ids == nil || ids!.contains($0.id) }
        var out: [(point: Vec2, a: EntityID, b: EntityID)] = []
        for i in 0..<gs.count {
            for j in (i + 1)..<max(gs.count, i + 1) {
                for p in intersections(gs[i].g, gs[j].g) where !out.contains(where: { $0.point.distance(to: p) <= tolerance }) {
                    out.append((p, gs[i].id, gs[j].id))
                }
            }
        }
        return out.sorted { ($0.point.y, $0.point.x) < ($1.point.y, $1.point.x) }
    }

    /// The grid pair whose intersection is within `tolerance` of a point (nil = not on an intersection).
    public static func hostPair(at p: Vec2, doc: ArchiDocument, tolerance: Double) -> (a: EntityID, b: EntityID)? {
        allIntersections(doc).filter { $0.point.distance(to: p) <= tolerance }.min { $0.point.distance(to: p) < $1.point.distance(to: p) }.map { ($0.a, $0.b) }
    }

    static func hosts(_ el: BIMElement) -> (EntityID, EntityID)? {
        guard let s = el.props[prop] else { return nil }
        let ids = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return ids.count == 2 ? (ids[0], ids[1]) : nil
    }

    /// True when some element is hosted on grids.
    public static func hasHosted(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props[prop] != nil } }

    /// Moves grid-hosted columns to the current intersection of their grids (the intersection nearest the column when
    /// curved grids cross twice). Columns whose grids no longer cross, or were deleted, keep their position.
    /// Returns true if anything moved.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices {
            guard let (ia, ib) = hosts(doc.elements[i]), case .column(var c) = doc.elements[i].geometry,
                  case .gridLine(let ga)? = doc.element(ia)?.geometry, case .gridLine(let gb)? = doc.element(ib)?.geometry else { continue }
            guard let p = intersections(ga, gb).min(by: { $0.distance(to: c.position) < $1.distance(to: c.position) }) else { continue }
            if !p.isClose(c.position, tol: 1e-9) { c.position = p; doc.elements[i].geometry = .column(c); changed = true }
        }
        return changed
    }
}
