// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Straight skeleton of a simple polygon by wavefront simulation (edge and split events), used for hip roofs
/// on non-convex footprints. Every edge moves inward at unit speed; the region an edge sweeps is its roof face.
public enum StraightSkeleton {
    public struct Face { public var edge: Int; public var poly: [Vec2] }

    private struct WV { var p: Vec2; var e: Int }

    /// Faces of the skeleton of `poly0` (any orientation). `edge` indexes the edges of the CCW-ordered input
    /// (if the input is clockwise it is reversed first: edge i of the reversed polygon).
    public static func faces(_ poly0: [Vec2]) -> [Face] {
        var poly = RG.dedupe(poly0, closed: true)
        guard poly.count >= 3, abs(GeometryOps.signedArea(poly)) > 1e-12 else { return [] }
        if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
        let n0 = poly.count
        var normals: [Vec2] = []
        for i in 0..<n0 { normals.append((poly[(i + 1) % n0] - poly[i]).normalized.perp) }
        let box = BBox2(points: poly)
        let size = max(box.width, box.height, 1e-9)
        let eps = size * 1e-9
        let mergeTol = size * 1e-7
        var fronts: [[WV]] = [poly.enumerated().map { WV(p: $0.element, e: $0.offset) }]
        var pieces: [Int: [[Vec2]]] = [:]

        func velocity(_ f: [WV], _ i: Int) -> Vec2 {
            let n = f.count
            let n1 = normals[f[(i - 1 + n) % n].e], n2 = normals[f[i].e]
            let det = n1.x * n2.y - n1.y * n2.x
            if abs(det) < 1e-10 {
                if n1.dot(n2) > 0 { return (n1 + n2).normalized }
                return .zero
            }
            return Vec2((n2.y - n1.y) / det, (n1.x - n2.x) / det)
        }
        func dirOf(_ e: Int) -> Vec2 { let n = normals[e]; return Vec2(n.y, -n.x) }

        var iterations = 0
        while !fronts.isEmpty && iterations < 20000 {
            iterations += 1
            fronts = fronts.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0.map(\.p))) > eps * eps }
            if fronts.isEmpty { break }
            let vels = fronts.map { f in (0..<f.count).map { velocity(f, $0) } }
            // Next event time.
            var dt = Double.infinity
            for (fi, f) in fronts.enumerated() {
                let n = f.count, v = vels[fi]
                for i in 0..<n {
                    let j = (i + 1) % n
                    let d = dirOf(f[i].e)
                    let l0 = (f[j].p - f[i].p).dot(d)
                    let rate = (v[j] - v[i]).dot(d)
                    if rate < -1e-12 { let t = -l0 / rate; if t > -eps { dt = min(dt, max(t, 0)) } }
                }
                for i in 0..<n {
                    let dIn = dirOf(f[(i - 1 + n) % n].e), dOut = dirOf(f[i].e)
                    guard dIn.cross(dOut) < -1e-9 else { continue } // reflex vertices only
                    for j in 0..<n where j != i && (j + 1) % n != i && j != (i - 1 + n) % n {
                        let nj = normals[f[j].e]
                        let den = 1 - nj.dot(v[i])
                        guard den > 1e-12 else { continue }
                        let dist = nj.dot(f[i].p - f[j].p)
                        guard dist > -mergeTol else { continue }
                        let t = max(dist, 0) / den
                        guard t < dt else { continue }
                        let q = f[i].p + v[i] * t
                        let a = f[j].p + v[j] * t, b = f[(j + 1) % n].p + v[(j + 1) % n] * t
                        let ab = b - a
                        let l2 = ab.lengthSquared
                        guard l2 > 1e-24 else { continue }
                        let s = (q - a).dot(ab) / l2
                        if s >= -1e-7, s <= 1 + 1e-7 { dt = t }
                    }
                }
            }
            guard dt.isFinite else { break }
            // Advance, recording the swept quads per original edge.
            for fi in 0..<fronts.count {
                let n = fronts[fi].count
                let moved = (0..<n).map { fronts[fi][$0].p + vels[fi][$0] * dt }
                for i in 0..<n {
                    let j = (i + 1) % n
                    let q = RG.dedupe([fronts[fi][i].p, fronts[fi][j].p, moved[j], moved[i]], closed: true, tol: mergeTol * 0.1)
                    if q.count >= 3, abs(GeometryOps.signedArea(q)) > eps * eps { pieces[fronts[fi][i].e, default: []].append(q) }
                }
                for i in 0..<n { fronts[fi][i].p = moved[i] }
            }
            // Topology: collapse zero-length edges, then split at reflex vertices touching opposite edges.
            var out: [[WV]] = []
            var queue = fronts
            var guardCount = 0
            while var f = queue.popLast() {
                guardCount += 1
                if guardCount > 10000 { break }
                var changed = true
                while changed && f.count >= 3 {
                    changed = false
                    for i in 0..<f.count {
                        let j = (i + 1) % f.count
                        if f[i].p.distance(to: f[j].p) < mergeTol {
                            let mid = (f[i].p + f[j].p) / 2
                            f[j].p = mid
                            f.remove(at: i)
                            changed = true
                            break
                        }
                    }
                }
                guard f.count >= 3 else { continue }
                var didSplit = false
                let n = f.count
                outer: for i in 0..<n {
                    let dIn = dirOf(f[(i - 1 + n) % n].e), dOut = dirOf(f[i].e)
                    guard dIn.cross(dOut) < -1e-9 else { continue }
                    for j in 0..<n where j != i && (j + 1) % n != i {
                        let a = f[j].p, b = f[(j + 1) % n].p
                        guard GeometryOps.distance(from: f[i].p, toPolyline: [a, b]) < mergeTol * 10 else { continue }
                        var A: [WV] = [], B: [WV] = []
                        var k = i
                        repeat { A.append(f[k]); k = (k + 1) % n } while k != (j + 1) % n
                        B.append(WV(p: f[i].p, e: f[j].e))
                        k = (j + 1) % n
                        while k != i { B.append(f[k]); k = (k + 1) % n }
                        queue.append(A); queue.append(B)
                        didSplit = true
                        break outer
                    }
                }
                if !didSplit { out.append(f) }
            }
            fronts = out
        }
        var result: [Face] = []
        for e in pieces.keys.sorted() {
            let ps = pieces[e]!
            if let merged = merge(ps, tol: mergeTol * 10) { result.append(Face(edge: e, poly: merged)) }
            else { for p in ps { result.append(Face(edge: e, poly: p)) } }
        }
        return result
    }

    /// Unions edge-adjacent CCW polygons into one outline by cancelling shared (opposite) edges.
    static func merge(_ polys: [[Vec2]], tol: Double) -> [Vec2]? {
        if polys.count == 1 { return polys[0] }
        var segs: [(Vec2, Vec2)] = []
        for p in polys {
            var q = p
            if GeometryOps.signedArea(q) < 0 { q.reverse() }
            for i in 0..<q.count { segs.append((q[i], q[(i + 1) % q.count])) }
        }
        // Split at T-junctions.
        let pts = segs.map(\.0)
        var split: [(Vec2, Vec2)] = []
        for s in segs {
            let d = s.1 - s.0
            let l2 = d.lengthSquared
            guard l2 > tol * tol else { continue }
            var ts: [Double] = []
            for p in pts {
                let t = (p - s.0).dot(d) / l2
                guard t > 1e-9, t < 1 - 1e-9 else { continue }
                if (s.0 + d * t).distance(to: p) < tol { ts.append(t) }
            }
            ts.sort()
            var prev = s.0
            for t in ts { let m = s.0 + d * t; if m.distance(to: prev) > tol { split.append((prev, m)); prev = m } }
            if s.1.distance(to: prev) > tol { split.append((prev, s.1)) }
        }
        // Cancel opposite pairs.
        var alive = [Bool](repeating: true, count: split.count)
        for i in 0..<split.count where alive[i] {
            for j in (i + 1)..<max(split.count, i + 1) where alive[j] {
                if split[i].0.distance(to: split[j].1) < tol && split[i].1.distance(to: split[j].0) < tol { alive[i] = false; alive[j] = false; break }
            }
        }
        let rest = split.enumerated().filter { alive[$0.offset] }.map(\.element)
        guard rest.count >= 3 else { return nil }
        var used = [Bool](repeating: false, count: rest.count)
        var loops: [[Vec2]] = []
        for s in 0..<rest.count where !used[s] {
            used[s] = true
            var loop = [rest[s].0]
            var cur = rest[s].1
            var ok = false
            for _ in 0..<rest.count {
                if cur.distance(to: loop[0]) < tol { ok = true; break }
                loop.append(cur)
                guard let nx = (0..<rest.count).first(where: { !used[$0] && rest[$0].0.distance(to: cur) < tol }) else { break }
                used[nx] = true
                cur = rest[nx].1
            }
            if ok { loops.append(loop) }
        }
        guard let best = loops.max(by: { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }) else { return nil }
        // The merged outline must account for (almost) all of the pieces' area.
        let total = polys.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }
        guard abs(abs(GeometryOps.signedArea(best)) - total) <= max(total * 1e-6, tol * tol) else { return nil }
        return removeCollinear(best, tol: tol)
    }

    static func removeCollinear(_ p: [Vec2], tol: Double) -> [Vec2] {
        var q = p
        var i = 0
        while q.count > 3 && i < q.count {
            let a = q[(i - 1 + q.count) % q.count], b = q[i], c = q[(i + 1) % q.count]
            if GeometryOps.distance(from: b, toPolyline: [a, c]) < tol { q.remove(at: i); i = max(i - 1, 0) } else { i += 1 }
        }
        return q
    }
}
