// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 2D Boolean operations on closed regions (union, subtraction, intersection, exclusive or).
/// Regions are sets of loops (outer boundaries counter-clockwise, holes clockwise, as produced by `normalize`); arcs are
/// tessellated. Algorithm: split every edge of both operands at mutual intersections, keep the pieces whose midpoint lies
/// inside/outside the other operand according to the operation (coincident edges resolved by direction), then chain the
/// kept pieces into loops.
public enum PolygonBoolean {
    public enum Op: String, CaseIterable { case union, subtract, intersect, xor }

    /// Point-in-region by even-odd rule over all loops.
    public static func contains(_ loops: [[Vec2]], _ p: Vec2) -> Bool {
        var inside = false
        for l in loops where l.count >= 3 && GeometryOps.pointInPolygon(p, l) { inside.toggle() }
        return inside
    }

    /// Orients loops by nesting depth: even depth CCW (outer), odd depth CW (hole). Removes degenerate loops.
    public static func normalize(_ loops: [[Vec2]]) -> [[Vec2]] {
        let ls = loops.map { dedupe($0) }.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0)) > 1e-12 }
        return ls.enumerated().map { (i, l) in
            let probe = l[0]
            let depth = ls.indices.filter { $0 != i && abs(GeometryOps.signedArea(ls[$0])) > abs(GeometryOps.signedArea(l)) && GeometryOps.pointInPolygon(probe, ls[$0]) }.count
            let ccw = GeometryOps.signedArea(l) > 0
            return (depth % 2 == 0) == ccw ? l : l.reversed()
        }
    }
    static func dedupe(_ l: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in l where out.last.map({ !$0.isClose(p, tol: 1e-9) }) ?? true { out.append(p) }
        if out.count > 1, out[0].isClose(out[out.count - 1], tol: 1e-9) { out.removeLast() }
        return out
    }

    struct Edge { var a: Vec2; var b: Vec2 }

    static func edges(_ loops: [[Vec2]]) -> [Edge] {
        var out: [Edge] = []
        for l in loops where l.count >= 3 { for i in l.indices { out.append(Edge(a: l[i], b: l[(i + 1) % l.count])) } }
        return out
    }

    /// Splits the edges of `e` at all intersections with edges of `other`.
    static func split(_ e: [Edge], by other: [Edge], tol: Double) -> [Edge] {
        var out: [Edge] = []
        for s in e {
            let r = s.b - s.a
            let rr = r.dot(r)
            guard rr > tol * tol else { continue }
            var ts: [Double] = [0, 1]
            let sb = BBox2(points: [s.a, s.b]).expanded(by: tol)
            for o in other {
                guard sb.intersects(BBox2(points: [o.a, o.b])) else { continue }
                let q = o.b - o.a
                let den = r.cross(q)
                if abs(den) > 1e-12 * r.length * max(q.length, 1e-12) {
                    let t = (o.a - s.a).cross(q) / den, u = (o.a - s.a).cross(r) / den
                    if t > 1e-12 && t < 1 - 1e-12 && u >= -1e-9 && u <= 1 + 1e-9 { ts.append(t) }
                } else if abs((o.a - s.a).cross(r)) <= tol * r.length {
                    // Collinear: split at the other edge's endpoints lying inside this edge.
                    for p in [o.a, o.b] { let t = (p - s.a).dot(r) / rr; if t > 1e-12 && t < 1 - 1e-12 { ts.append(t) } }
                }
            }
            ts.sort()
            var prev = ts[0]
            for t in ts.dropFirst() where t - prev > 1e-12 {
                let a = s.a + r * prev, b = s.a + r * t
                if a.distance(to: b) > tol { out.append(Edge(a: a, b: b)) }
                prev = t
            }
        }
        return out
    }

    enum Side { case inside, outside, sameBoundary, oppositeBoundary }
    static func classify(_ e: Edge, against other: [[Vec2]], otherEdges: [Edge], tol: Double) -> Side {
        let m = (e.a + e.b) / 2
        let dir = (e.b - e.a).normalized
        for o in otherEdges where GeometryOps.distance(point: m, segA: o.a, segB: o.b) <= tol {
            let od = (o.b - o.a).normalized
            if abs(od.cross(dir)) < 1e-6 { return od.dot(dir) > 0 ? .sameBoundary : .oppositeBoundary }
        }
        return contains(other, m) ? .inside : .outside
    }

    /// Boolean of two regions. Returns normalized loops (outer CCW, holes CW).
    public static func apply(_ op: Op, _ a0: [[Vec2]], _ b0: [[Vec2]]) -> [[Vec2]] {
        if op == .xor { return apply(.union, apply(.subtract, a0, b0), apply(.subtract, b0, a0)) }
        let a = normalize(a0), b = normalize(b0)
        var box = BBox2.empty
        for l in a + b { l.forEach { box.add($0) } }
        guard !box.isEmpty else { return [] }
        let tol = max(box.width, box.height, 1) * 1e-9
        let ea = edges(a), eb = edges(b)
        let sa = split(ea, by: eb, tol: tol), sb = split(eb, by: ea, tol: tol)
        var kept: [Edge] = []
        for e in sa {
            switch (classify(e, against: b, otherEdges: eb, tol: tol * 10), op) {
            case (.outside, .union), (.sameBoundary, .union), (.inside, .intersect), (.sameBoundary, .intersect),
                 (.outside, .subtract), (.oppositeBoundary, .subtract): kept.append(e)
            default: break
            }
        }
        for e in sb {
            switch (classify(e, against: a, otherEdges: ea, tol: tol * 10), op) {
            case (.outside, .union), (.inside, .intersect): kept.append(e)
            case (.inside, .subtract): kept.append(Edge(a: e.b, b: e.a))
            default: break
            }
        }
        return normalize(chain(kept, tol: tol * 10))
    }

    /// Chains directed edges into closed loops (following, at a vertex with several exits, the rightmost turn).
    static func chain(_ edges: [Edge], tol: Double) -> [[Vec2]] {
        func key(_ p: Vec2) -> String { "\(Int((p.x / (tol * 100)).rounded())),\(Int((p.y / (tol * 100)).rounded()))" }
        var from: [String: [Int]] = [:]
        for (i, e) in edges.enumerated() { from[key(e.a), default: []].append(i) }
        var used = [Bool](repeating: false, count: edges.count)
        var loops: [[Vec2]] = []
        for start in edges.indices where !used[start] {
            var loop: [Vec2] = []
            var cur = start
            var guardN = 0
            while !used[cur] && guardN < edges.count + 1 {
                guardN += 1
                used[cur] = true
                loop.append(edges[cur].a)
                let endKey = key(edges[cur].b)
                if endKey == key(edges[start].a) { break }
                let d = edges[cur].b - edges[cur].a
                let cands = (from[endKey] ?? []).filter { !used[$0] }
                guard !cands.isEmpty else { loop = []; break }
                // Prefer the sharpest right turn to keep loops simple at touching vertices.
                cur = cands.min { x, y in
                    let dx = edges[x].b - edges[x].a, dy = edges[y].b - edges[y].a
                    return atan2(d.cross(dx), d.dot(dx)) < atan2(d.cross(dy), d.dot(dy))
                }!
            }
            if loop.count >= 3 { loops.append(simplify(loop)) }
        }
        return loops.filter { $0.count >= 3 }
    }

    /// Removes collinear intermediate vertices.
    static func simplify(_ l: [Vec2]) -> [Vec2] {
        var pts = l
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in pts.indices {
                let p = pts[(i - 1 + pts.count) % pts.count], q = pts[i], r = pts[(i + 1) % pts.count]
                let u = q - p, v = r - q
                if abs(u.cross(v)) <= 1e-9 * max(u.length * v.length, 1e-18) && u.dot(v) > 0 { pts.remove(at: i); changed = true; break }
            }
        }
        return pts
    }

    /// Region of closed curves (closed polylines, circles, ellipses, closed splines, hatches) as loops.
    public static func loops(of g: Geometry, doc: ArchiDocument?) -> [[Vec2]]? {
        switch g {
        case .hatch(let h): return h.loops.map(CommandHelpers.loopPoints)
        default:
            guard let l = CommandHelpers.closedLoop(g) else { return nil }
            return [CommandHelpers.loopPoints(l)]
        }
    }

    /// Area of a normalized region.
    public static func area(_ loops: [[Vec2]]) -> Double { normalize(loops).reduce(0) { $0 + GeometryOps.signedArea($1) } }
}
