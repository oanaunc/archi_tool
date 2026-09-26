// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Construction lines (XLINE, DRW-002) and rays (RAY, DRW-003). They are stored as line geometry reaching `reach` drawing
/// units beyond their base point (so every renderer, snap and modify tool works on them) and tagged with the prop
/// "construction" = "xline" | "ray". Drawing extents ignore their far ends; TRIM / BREAK turn a trimmed xline into a
/// ray and a ray into a line, as in AutoCAD; DXF exchange writes them as XLINE / RAY entities via `info`.
public enum ConstructionLines {
    public static let prop = "construction"
    /// Distance from the base point to a far ("infinite") end.
    public static let reach = 1e6

    public enum Kind: String { case xline, ray }

    /// Geometry and props of a new construction line through `base` with direction `dir`.
    public static func make(_ kind: Kind, base: Vec2, direction dir: Vec2) -> (geometry: Geometry, props: [String: String])? {
        let d = dir.normalized
        guard d != .zero else { return nil }
        let g: Geometry = kind == .xline ? .line(LineGeom(base - d * reach, base + d * reach)) : .line(LineGeom(base, base + d * reach))
        return (g, [prop: kind.rawValue])
    }

    /// Kind, base point and unit direction of a construction entity (nil for ordinary objects).
    public static func info(_ e: Entity) -> (kind: Kind, base: Vec2, direction: Vec2)? {
        guard let k = e.props[prop].flatMap(Kind.init(rawValue:)), case .line(let l) = e.geometry else { return nil }
        let d = (l.b - l.a).normalized
        guard d != .zero else { return nil }
        return k == .xline ? (k, (l.a + l.b) / 2, d) : (k, l.a, d)
    }

    /// The far (infinite) ends of a construction entity.
    public static func farEnds(_ e: Entity) -> [Vec2] {
        guard let k = e.props[prop].flatMap(Kind.init(rawValue:)), case .line(let l) = e.geometry else { return [] }
        return k == .xline ? [l.a, l.b] : [l.b]
    }

    /// Part of the drawing extents an entity contributes: the base point for construction lines, else its bounds.
    public static func extentsBounds(_ e: Entity, doc: ArchiDocument?) -> BBox2 {
        if let i = info(e) { return BBox2(min: i.base, max: i.base) }
        return GeometryOps.bounds(e.geometry, doc: doc)
    }

    /// Reclassifies a piece of a construction entity after TRIM / BREAK: both far ends kept → same kind; one far end →
    /// ray from the finite end; none → an ordinary line. Returns the geometry (reoriented for rays) and the prop value.
    public static func reclassify(_ piece: Geometry, farEnds: [Vec2]) -> (geometry: Geometry, kind: Kind?) {
        guard case .line(let l) = piece, !farEnds.isEmpty else { return (piece, nil) }
        let tol = reach * 1e-9
        let aFar = farEnds.contains { $0.isClose(l.a, tol: tol) }, bFar = farEnds.contains { $0.isClose(l.b, tol: tol) }
        switch (aFar, bFar) {
        case (true, true): return (piece, .xline)
        case (true, false): return (.line(LineGeom(l.b, l.a)), .ray)
        case (false, true): return (piece, .ray)
        default: return (piece, nil)
        }
    }
}
