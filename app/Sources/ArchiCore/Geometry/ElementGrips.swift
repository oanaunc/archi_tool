// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Grip points and grip stretching of BIM elements in plan (SEL-032/033/036), shared by the canvas, scripts and tests.
/// Index = position in the list returned by `points`:
/// - linear elements (wall, curtain wall, beam, grid line): start, end, midpoint (moves the element);
/// - slabs / roofs / spaces: vertices, then edge midpoints (drag an edge); roofs add the slope grip last;
/// - point elements (column, component, stair): the insertion point; railings: path vertices; openings: centre on the host.
public enum ElementGrips {
    public static func edgeMidpoints(_ pts: [Vec2]) -> [Vec2] {
        guard pts.count >= 2 else { return [] }
        return pts.indices.map { (pts[$0] + pts[($0 + 1) % pts.count]) / 2 }
    }
    /// Boundary after dragging grip `i`: a vertex (i < n) or edge i − n (both of its vertices move).
    public static func moved(_ pts: [Vec2], grip i: Int, from o: Vec2, to p: Vec2) -> [Vec2] {
        var b = pts
        let n = pts.count
        if b.indices.contains(i) { b[i] = p }
        else if i >= n && i < 2 * n { let k = i - n, d = p - o; b[k] = b[k] + d; b[(k + 1) % n] = b[(k + 1) % n] + d }
        return b
    }
    /// Midpoint and inward unit normal of a roof's eave edge.
    public static func eave(_ r: RoofGeom) -> (Vec2, Vec2)? {
        let b = r.boundary
        guard b.count >= 3 else { return nil }
        let i = min(max(r.eaveEdge, 0), b.count - 1)
        let a = b[i], c = b[(i + 1) % b.count]
        let d = (c - a).normalized
        guard d != .zero else { return nil }
        var n = d.perp
        if GeometryOps.signedArea(b) < 0 { n = n * -1 }
        return ((a + c) / 2, n)
    }
    /// Roof slope grip: on the inward normal of the eave at the run where the roof rises `unit` (1 m).
    public static func slopeGrip(_ r: RoofGeom, unit: Double) -> Vec2? {
        guard let (m, n) = eave(r), r.pitch > 0.5 else { return nil }
        return m + n * (unit / tan(rad(r.pitch)))
    }
    /// Pitch (degrees, 5°–75°) set by dragging the slope grip to `p`.
    public static func pitch(_ r: RoofGeom, dragTo p: Vec2, unit: Double) -> Double {
        guard let (m, n) = eave(r) else { return r.pitch }
        let run = max((p - m).dot(n), 1e-9)
        return min(max(deg(atan(unit / run)), 5), 75)
    }

    /// Grip points of an element.
    public static func points(_ el: BIMElement, doc: ArchiDocument) -> [Vec2] {
        switch el.geometry {
        case .wall(let w): return [w.start, w.end, (w.start + w.end) / 2]
        case .curtainWall(let c): return [c.start, c.end, (c.start + c.end) / 2]
        case .beam(let b): return [b.start, b.end, (b.start + b.end) / 2]
        case .gridLine(let g): return [g.start, g.end, (g.start + g.end) / 2]
        case .column(let c): return [c.position]
        case .component(let c): return [c.position]
        case .stair(let s): return [s.start]
        case .slab(let s): return s.boundary + edgeMidpoints(s.boundary)
        case .roof(let r): return r.boundary + edgeMidpoints(r.boundary) + (slopeGrip(r, unit: 1000 / doc.units.mm).map { [$0] } ?? [])
        case .space(let s): return s.boundary + edgeMidpoints(s.boundary)
        case .railing(let r): return r.path
        case .opening(let o):
            guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { return [] }
            return [w.centerStart + w.direction * o.offset]
        }
    }

    /// Element geometry after dragging grip `i` from `o` to `p`.
    public static func moved(_ el: BIMElement, grip i: Int, from o: Vec2, to p: Vec2, doc: ArchiDocument) -> BIMGeometry {
        func lin(_ s: inout Vec2, _ e: inout Vec2) {
            if i == 0 { s = p } else if i == 1 { e = p } else { s += p - o; e += p - o }
        }
        switch el.geometry {
        case .wall(var w): lin(&w.start, &w.end); return .wall(w)
        case .curtainWall(var c): lin(&c.start, &c.end); return .curtainWall(c)
        case .beam(var b): lin(&b.start, &b.end); return .beam(b)
        case .gridLine(var g): lin(&g.start, &g.end); return .gridLine(g)
        case .column(var c): c.position = p; return .column(c)
        case .component(var c): c.position = p; return .component(c)
        case .stair(var s): s.start = p; return .stair(s)
        case .slab(var s): s.boundary = moved(s.boundary, grip: i, from: o, to: p); return .slab(s)
        case .roof(var r):
            if i == 2 * r.boundary.count { r.pitch = pitch(r, dragTo: p, unit: 1000 / doc.units.mm) } else { r.boundary = moved(r.boundary, grip: i, from: o, to: p) }
            return .roof(r)
        case .space(var s): s.boundary = moved(s.boundary, grip: i, from: o, to: p); return .space(s)
        case .railing(var r): if r.path.indices.contains(i) { r.path[i] = p }; return .railing(r)
        case .opening(var op):
            guard let host = doc.element(op.hostWall), case .wall(let w) = host.geometry else { return el.geometry }
            let t = (p - w.centerStart).dot(w.direction)
            op.offset = min(max(t, op.width / 2), max(op.width / 2, w.length - op.width / 2))
            return .opening(op)
        }
    }

    /// Rotation of `turns` quarter turns (counter-clockwise) about `p` — Space while dragging (MOD-029). Nil for 0 turns.
    public static func quarterTurn(_ turns: Int, about p: Vec2) -> Transform2D? {
        let t = ((turns % 4) + 4) % 4
        return t == 0 ? nil : .rotation(Double(t) * .pi / 2, around: p)
    }
}
