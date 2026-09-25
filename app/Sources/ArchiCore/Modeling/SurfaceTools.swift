// Oanarina Archi Tool — GPL-3.0-or-later
// Mesh surfaces from curves (AutoCAD REVSURF / TABSURF / RULESURF / EDGESURF), twisted sweeps, and mesh repair / decimation.
import Foundation

public enum SurfaceTools {
    /// Triangulates a grid of points (rows × columns); `closedU` wraps the columns.
    public static func grid(_ rows: [[Vec3]], closedU: Bool = false) -> (vertices: [Vec3], triangles: [Int]) {
        guard rows.count >= 2, let m = rows.first?.count, m >= 2, rows.allSatisfy({ $0.count == m }) else { return ([], []) }
        var v: [Vec3] = []
        for r in rows { v += r }
        var t: [Int] = []
        let cols = closedU ? m : m - 1
        for i in 0..<(rows.count - 1) {
            for j in 0..<cols {
                let a = i * m + j, b = i * m + (j + 1) % m, c = (i + 1) * m + (j + 1) % m, d = (i + 1) * m + j
                for tri in [[a, b, c], [a, c, d]] {
                    let n = (v[tri[1]] - v[tri[0]]).cross(v[tri[2]] - v[tri[0]])
                    if n.length > 1e-12 { t += tri }
                }
            }
        }
        return (v, t)
    }

    /// Resamples a polyline to `count` points evenly spaced by arc length.
    public static func resample(_ p0: [Vec3], count: Int, closed: Bool = false) -> [Vec3] {
        var p = p0
        if closed, let f = p.first { p.append(f) }
        guard p.count >= 2, count >= 2 else { return p0 }
        var cum: [Double] = [0]
        for i in 1..<p.count { cum.append(cum[i - 1] + p[i].distance(to: p[i - 1])) }
        let total = cum.last!
        guard total > 1e-12 else { return Array(repeating: p[0], count: count) }
        var out: [Vec3] = [], seg = 0
        let n = closed ? count : count - 1
        for k in 0..<count {
            let s = total * Double(k) / Double(n)
            while seg < p.count - 2 && cum[seg + 1] < s { seg += 1 }
            let l = cum[seg + 1] - cum[seg]
            let t = l > 1e-12 ? (s - cum[seg]) / l : 0
            out.append(p[seg] + (p[seg + 1] - p[seg]) * min(max(t, 0), 1))
        }
        return out
    }

    /// REVSURF: rotates a path curve about the axis a→b by `sweep` radians from `start`.
    public static func revolve(_ profile: [Vec3], axisFrom a: Vec3, to b: Vec3, start: Double = 0, sweep: Double = 2 * .pi, segments: Int = 32) -> (vertices: [Vec3], triangles: [Int]) {
        let k = (b - a).normalized
        guard k.length > 0.5, profile.count >= 2 else { return ([], []) }
        let full = abs(sweep) >= 2 * .pi - 1e-9
        let n = max(3, segments)
        var rows: [[Vec3]] = []
        for p in profile {
            var row: [Vec3] = []
            for i in 0..<(full ? n : n + 1) {
                let ang = start + sweep * Double(i) / Double(n)
                row.append(a + RunFamilies.rotate(p - a, k, ang))
            }
            rows.append(row)
        }
        return grid(rows, closedU: full)
    }

    /// TABSURF: sweeps a path curve along a direction vector.
    public static func tabulate(_ path: [Vec3], vector: Vec3) -> (vertices: [Vec3], triangles: [Int]) {
        guard vector.length > 1e-12 else { return ([], []) }
        return grid([path, path.map { $0 + vector }])
    }

    /// RULESURF: ruled surface between two curves (both resampled to the same count; the second is reversed when
    /// that gives the shorter rulings, as AutoCAD picks by the ends nearest to the pick points).
    public static func ruled(_ a0: [Vec3], _ b0: [Vec3], count: Int = 32, closed: Bool = false) -> (vertices: [Vec3], triangles: [Int]) {
        let a = resample(a0, count: count, closed: closed)
        var b = resample(b0, count: count, closed: closed)
        if !closed, let af = a.first, let bf = b.first, let bl = b.last, af.distance(to: bl) < af.distance(to: bf) { b.reverse() }
        return grid(closed ? [a, b].map { $0 } : [a, b], closedU: closed)
    }

    /// EDGESURF: bilinear Coons patch bounded by four curves joined end to end (any order and direction).
    public static func coons(_ curves: [[Vec3]], m: Int = 16, n: Int = 16, tolerance: Double = 1e-3) -> (vertices: [Vec3], triangles: [Int])? {
        guard curves.count == 4, curves.allSatisfy({ $0.count >= 2 }) else { return nil }
        // Chain the curves into a loop.
        var rest = Array(curves.dropFirst())
        var loop = [curves[0]]
        for _ in 0..<3 {
            let end = loop.last!.last!
            guard let i = rest.firstIndex(where: { $0.first!.distance(to: end) <= tolerance || $0.last!.distance(to: end) <= tolerance }) else { return nil }
            var c = rest.remove(at: i)
            if c.first!.distance(to: end) > tolerance { c.reverse() }
            loop.append(c)
        }
        guard loop[3].last!.distance(to: loop[0].first!) <= tolerance else { return nil }
        let c0 = resample(loop[0], count: m + 1)                 // v = 0, u 0→1
        let d1 = resample(loop[1], count: n + 1)                 // u = 1, v 0→1
        let c1 = resample(Array(loop[2].reversed()), count: m + 1) // v = 1, u 0→1
        let d0 = resample(Array(loop[3].reversed()), count: n + 1) // u = 0, v 0→1
        let p00 = c0[0], p10 = c0[m], p01 = c1[0], p11 = c1[m]
        var rows: [[Vec3]] = []
        for j in 0...n {
            let v = Double(j) / Double(n)
            var row: [Vec3] = []
            for i in 0...m {
                let u = Double(i) / Double(m)
                let lc = c0[i] * (1 - v) + c1[i] * v
                let ld = d0[j] * (1 - u) + d1[j] * u
                let b = p00 * ((1 - u) * (1 - v)) + p10 * (u * (1 - v)) + p01 * ((1 - u) * v) + p11 * (u * v)
                row.append(lc + ld - b)
            }
            rows.append(row)
        }
        return grid(rows)
    }

    /// Sweep of a closed profile along a path with a total twist (radians) and an end scale factor.
    public static func twistedSweep(_ profile0: [Vec2], along path0: [Vec3], twist: Double, endScale: Double = 1, closedPath: Bool = false) -> Mesh {
        var profile = RG.dedupe(profile0, closed: true)
        guard profile.count >= 3, path0.count >= 2 else { return Mesh() }
        // Densify so each ring twists at most 5° (straight rulings between rings would pinch the section).
        var path = path0
        let steps = Int((abs(twist) / (Double.pi / 36)).rounded(.up))
        if steps > path0.count - 1 && !closedPath {
            var cum: [Double] = [0]
            for i in 1..<path0.count { cum.append(cum[i - 1] + path0[i].distance(to: path0[i - 1])) }
            let total = max(cum.last!, 1e-12)
            path = [path0[0]]
            for i in 1..<path0.count {
                let k = max(1, Int((Double(steps) * (cum[i] - cum[i - 1]) / total).rounded(.up)))
                for j in 1...k { path.append(path0[i - 1] + (path0[i] - path0[i - 1]) * (Double(j) / Double(k))) }
            }
        }
        if GeometryOps.signedArea(profile) < 0 { profile.reverse() }
        let fr = SweepMesh.frames(path, closed: closedPath)
        var cum: [Double] = [0]
        for i in 1..<path.count { cum.append(cum[i - 1] + path[i].distance(to: path[i - 1])) }
        let total = max(cum.last!, 1e-12)
        var rings: [[Vec3]] = []
        for (i, f) in fr.enumerated() {
            let t = cum[i] / total
            let ang = twist * t, sc = 1 + (endScale - 1) * t
            let c = cos(ang), s = sin(ang)
            rings.append(profile.map { q in
                let r = Vec2(q.x * c - q.y * s, q.x * s + q.y * c) * sc
                return f.o + f.x * r.x + f.y * r.y
            })
        }
        var acc = MeshAcc()
        SweepMesh.loft(rings, closed: closedPath, capped: !closedPath, into: &acc)
        return acc.mesh
    }
}

// MARK: - Mesh repair and decimation

public struct MeshRepairReport: Equatable {
    public var weldedVertices = 0
    public var degenerate = 0
    public var duplicates = 0
    public var flipped = 0
    public var holesFilled = 0
    public var openEdgesLeft = 0
    public var description: String {
        "\(weldedVertices) vertices welded, \(degenerate) degenerate and \(duplicates) duplicate faces removed, \(flipped) faces re-oriented, \(holesFilled) hole(s) filled" + (openEdgesLeft > 0 ? ", \(openEdgesLeft) open edge(s) left" : "")
    }
}

extension MeshTools {
    /// Welds, removes degenerate/duplicate faces, makes face orientation consistent (outward for closed shells),
    /// and fills boundary holes. Returns the repaired indexed mesh.
    public static func repair(vertices v0: [Vec3], triangles t0: [Int], tolerance: Double = 1e-6, fillHoles: Bool = true) -> (vertices: [Vec3], triangles: [Int], report: MeshRepairReport) {
        var rep = MeshRepairReport()
        var tris: [(Vec3, Vec3, Vec3)] = []
        var i = 0
        while i + 2 < t0.count {
            let a = t0[i], b = t0[i + 1], c = t0[i + 2]; i += 3
            guard a >= 0, b >= 0, c >= 0, a < v0.count, b < v0.count, c < v0.count else { rep.degenerate += 1; continue }
            tris.append((v0[a], v0[b], v0[c]))
        }
        let w = weld(tris, tolerance: tolerance)
        rep.weldedVertices = max(0, Set(v0.map { [$0.x, $0.y, $0.z] }).count - w.vertices.count)
        let v = w.vertices
        var faces: [[Int]] = []
        var seen = Set<[Int]>()
        rep.degenerate += tris.count - w.triangles.count / 3
        var k = 0
        while k + 2 < w.triangles.count {
            let f = [w.triangles[k], w.triangles[k + 1], w.triangles[k + 2]]; k += 3
            let area = (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]]).length
            if area <= tolerance * tolerance * 1e-3 { rep.degenerate += 1; continue }
            if !seen.insert(f.sorted()).inserted { rep.duplicates += 1; continue }
            faces.append(f)
        }
        // Consistent orientation by flood fill over shared edges.
        var edgeFaces: [[Int]: [Int]] = [:]
        for (fi, f) in faces.enumerated() { for e in 0..<3 { let a = f[e], b = f[(e + 1) % 3]; edgeFaces[[min(a, b), max(a, b)], default: []].append(fi) } }
        var visited = Array(repeating: false, count: faces.count)
        func hasDirected(_ f: [Int], _ a: Int, _ b: Int) -> Bool { (0..<3).contains { f[$0] == a && f[($0 + 1) % 3] == b } }
        for seed in faces.indices where !visited[seed] {
            var comp: [Int] = [seed]
            visited[seed] = true
            var q = [seed], qi = 0
            while qi < q.count {
                let fi = q[qi]; qi += 1
                let f = faces[fi]
                for e in 0..<3 {
                    let a = f[e], b = f[(e + 1) % 3]
                    for nb in edgeFaces[[min(a, b), max(a, b)]] ?? [] where nb != fi && !visited[nb] {
                        // A consistent neighbour traverses the shared edge b→a.
                        if hasDirected(faces[nb], a, b) { faces[nb].swapAt(1, 2); rep.flipped += 1 }
                        visited[nb] = true; q.append(nb); comp.append(nb)
                    }
                }
            }
            // Closed shells point outward (positive volume).
            var vol = 0.0
            for fi in comp { let f = faces[fi]; vol += v[f[0]].dot(v[f[1]].cross(v[f[2]])) / 6 }
            if vol < 0 { for fi in comp { faces[fi].swapAt(1, 2) }; rep.flipped += comp.count }
        }
        var verts = v
        if fillHoles {
            // Directed boundary edges (no twin) chained into loops, then closed with ear-clipped caps.
            var directed = Set<[Int]>()
            for f in faces { for e in 0..<3 { directed.insert([f[e], f[(e + 1) % 3]]) } }
            var next: [Int: Int] = [:]
            for d in directed where !directed.contains([d[1], d[0]]) { next[d[1]] = d[0] }   // hole loop runs opposite to the faces
            var used = Set<Int>()
            for s in next.keys.sorted() where !used.contains(s) {
                var loop = [s]; used.insert(s)
                var cur = s, ok = false
                for _ in 0..<next.count {
                    guard let n = next[cur] else { break }
                    if n == s { ok = true; break }
                    if used.contains(n) { break }
                    loop.append(n); used.insert(n); cur = n
                }
                guard ok, loop.count >= 3 else { continue }
                let pts = loop.map { verts[$0] }
                let nrm = Mesh.polygonNormal(pts)
                guard nrm.length > 0.5 else {
                    // Degenerate projection: fan from the centroid.
                    let c = pts.reduce(Vec3.zero, +) / Double(pts.count)
                    verts.append(c)
                    for j in 0..<loop.count { faces.append([verts.count - 1, loop[j], loop[(j + 1) % loop.count]]) }
                    rep.holesFilled += 1; continue
                }
                let (bu, bv) = Mesh.basis(nrm)
                let flat = pts.map { Vec2($0.dot(bu), $0.dot(bv)) }
                var tris = Triangulator.triangulate(flat, holes: [])
                if tris.isEmpty { continue }
                // Match the loop direction (Triangulator may reverse a clockwise loop).
                for t in tris.indices {
                    let (a, b, c) = tris[t]
                    let fnorm = (pts[b] - pts[a]).cross(pts[c] - pts[a])
                    if fnorm.dot(nrm) < 0 { tris[t] = (a, c, b) }
                }
                for (a, b, c) in tris { faces.append([loop[a], loop[b], loop[c]]) }
                rep.holesFilled += 1
            }
        }
        var directed = [[Int]: Int]()
        for f in faces { for e in 0..<3 { directed[[f[e], f[(e + 1) % 3]], default: 0] += 1 } }
        rep.openEdgesLeft = directed.keys.filter { directed[[$0[1], $0[0]]] == nil }.count
        return (verts, faces.flatMap { $0 }, rep)
    }

    /// Decimates by vertex clustering to at most about `ratio` × the triangle count (0 < ratio < 1).
    public static func decimate(vertices v: [Vec3], triangles t: [Int], ratio: Double) -> (vertices: [Vec3], triangles: [Int]) {
        let target = max(4, Int(Double(t.count / 3) * min(max(ratio, 0.01), 1)))
        guard t.count / 3 > target, !v.isEmpty else { return (v, t) }
        var b = BBox3.empty
        v.forEach { b.add($0) }
        let diag = max((b.max - b.min).length, 1e-9)
        func cluster(_ cell: Double) -> (vertices: [Vec3], triangles: [Int]) {
            var key: [[Int64]: Int] = [:], sums: [Vec3] = [], counts: [Double] = []
            var map = [Int](repeating: 0, count: v.count)
            for (i, p) in v.enumerated() {
                let k = [Int64(((p.x - b.min.x) / cell).rounded(.down)), Int64(((p.y - b.min.y) / cell).rounded(.down)), Int64(((p.z - b.min.z) / cell).rounded(.down))]
                if let c = key[k] { map[i] = c; sums[c] = sums[c] + p; counts[c] += 1 }
                else { key[k] = sums.count; map[i] = sums.count; sums.append(p); counts.append(1) }
            }
            let nv = zip(sums, counts).map { $0 / $1 }
            var out: [Int] = [], seen = Set<[Int]>()
            var i = 0
            while i + 2 < t.count {
                let a = map[t[i]], bb = map[t[i + 1]], c = map[t[i + 2]]; i += 3
                if a == bb || bb == c || a == c { continue }
                if !seen.insert([a, bb, c].sorted()).inserted { continue }
                out += [a, bb, c]
            }
            // Drop unused vertices.
            var remap: [Int: Int] = [:], fv: [Vec3] = []
            let ft = out.map { idx -> Int in if let r = remap[idx] { return r }; remap[idx] = fv.count; fv.append(nv[idx]); return fv.count - 1 }
            return (fv, ft)
        }
        // A closed manifold input stays closed and manifold: candidates that break it are rejected.
        let keepManifold = SolidOps.isClosedManifold(vertices: v, triangles: t)
        func valid(_ r: (vertices: [Vec3], triangles: [Int])) -> Bool {
            r.triangles.count >= 12 && (!keepManifold || SolidOps.isClosedManifold(vertices: r.vertices, triangles: r.triangles))
        }
        var lo = diag / 1e5, hi = diag / 2
        var best: (vertices: [Vec3], triangles: [Int])? = nil      // valid and within the target
        var fallback: (vertices: [Vec3], triangles: [Int]) = (v, t) // valid, fewest triangles so far
        for _ in 0..<40 {
            let mid = sqrt(lo * hi)
            let r = cluster(mid)
            let ok = valid(r)
            if ok && r.triangles.count < fallback.triangles.count { fallback = r }
            if r.triangles.count / 3 <= target {
                if ok { best = r; hi = mid } else { hi = mid }
            } else { lo = mid }
            if hi / lo < 1.02 { break }
        }
        return best ?? fallback
    }
}
