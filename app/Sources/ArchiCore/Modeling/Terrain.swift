// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Topography: Delaunay triangulation of survey points (Bowyer–Watson), contour extraction and
/// conversion to a closed terrain solid with a flat base.
public enum Terrain {
    /// Delaunay triangulation of 2D points; returns index triples (CCW). Duplicate points are ignored.
    public static func delaunay(_ pts: [Vec2]) -> [(Int, Int, Int)] {
        guard pts.count >= 3 else { return [] }
        let box = BBox2(points: pts)
        let size = max(box.width, box.height, 1e-9)
        let c = box.center
        // Super triangle well outside the points.
        let s0 = c + Vec2(-20 * size, -10 * size), s1 = c + Vec2(20 * size, -10 * size), s2 = c + Vec2(0, 20 * size)
        var all = pts + [s0, s1, s2]
        let n = pts.count
        struct Tri { var a: Int, b: Int, c: Int; var cc: Vec2; var r2: Double }
        func make(_ a: Int, _ b: Int, _ c: Int) -> Tri? {
            var (a, b, c) = (a, b, c)
            let pa = all[a], pb = all[b], pc = all[c]
            let cr = (pb - pa).cross(pc - pa)
            if abs(cr) < 1e-18 * size * size { return nil }
            if cr < 0 { swap(&b, &c) }
            let A = all[a], B = all[b], C = all[c]
            let d = 2 * (A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y))
            let ux = (A.lengthSquared * (B.y - C.y) + B.lengthSquared * (C.y - A.y) + C.lengthSquared * (A.y - B.y)) / d
            let uy = (A.lengthSquared * (C.x - B.x) + B.lengthSquared * (A.x - C.x) + C.lengthSquared * (B.x - A.x)) / d
            let cc = Vec2(ux, uy)
            return Tri(a: a, b: b, c: c, cc: cc, r2: (A - cc).lengthSquared)
        }
        var tris: [Tri] = [make(n, n + 1, n + 2)!]
        let dupTol = size * 1e-9
        var seen: [Vec2] = []
        // Insert in a spatially coherent order (by x) for speed.
        for i in (0..<n).sorted(by: { pts[$0].x < pts[$1].x }) {
            let p = all[i]
            if seen.suffix(8).contains(where: { $0.distance(to: p) < dupTol }) { continue }
            seen.append(p)
            var bad: [Int] = []
            for (k, t) in tris.enumerated() where (p - t.cc).lengthSquared < t.r2 * (1 + 1e-12) { bad.append(k) }
            var edges: [(Int, Int)] = []
            var count: [[Int]: Int] = [:]
            for k in bad {
                let t = tris[k]
                for e in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] { count[[min(e.0, e.1), max(e.0, e.1)], default: 0] += 1; edges.append(e) }
            }
            for k in bad.sorted(by: >) { tris.remove(at: k) }
            for e in edges where count[[min(e.0, e.1), max(e.0, e.1)]] == 1 {
                if let t = make(e.0, e.1, i) { tris.append(t) }
            }
        }
        all.removeAll()
        return tris.filter { $0.a < n && $0.b < n && $0.c < n }.map { ($0.a, $0.b, $0.c) }
    }

    /// Triangulated terrain surface from 3D survey points.
    public static func surface(_ points: [Vec3]) -> (vertices: [Vec3], triangles: [Int]) {
        let tri = delaunay(points.map(\.xy))
        return (points, tri.flatMap { [$0.0, $0.1, $0.2] })
    }

    /// Closed terrain solid: the surface, a flat base at `baseZ` and vertical skirts along the hull.
    public static func solid(_ points: [Vec3], baseZ: Double? = nil) -> SolidGeom? {
        let surf = surface(points)
        guard !surf.triangles.isEmpty else { return nil }
        let zMin = points.map(\.z).min() ?? 0
        let z0 = baseZ ?? (zMin - max(1000, (points.map(\.z).max()! - zMin) * 0.2))
        var tris: [(Vec3, Vec3, Vec3)] = []
        var edgeCount: [[Int]: Int] = [:]
        var directed: [[Int]: (Int, Int)] = [:]
        var i = 0
        while i + 2 < surf.triangles.count {
            let a = surf.triangles[i], b = surf.triangles[i + 1], c = surf.triangles[i + 2]
            i += 3
            tris.append((points[a], points[b], points[c]))
            for (u, v) in [(a, b), (b, c), (c, a)] { let k = [min(u, v), max(u, v)]; edgeCount[k, default: 0] += 1; directed[k] = (u, v) }
        }
        // Boundary edges (used once) get skirts; the base is the hull polygon.
        var boundary: [(Int, Int)] = []
        for (k, n) in edgeCount where n == 1 { boundary.append(directed[k]!) }
        for (u, v) in boundary {
            let pu = points[u], pv = points[v]
            let bu = Vec3(pu.x, pu.y, z0), bv = Vec3(pv.x, pv.y, z0)
            // Surface edge u→v runs CCW around the outside; the skirt faces outward.
            tris.append((pv, pu, bu)); tris.append((pv, bu, bv))
        }
        // Base: the boundary loop of the surface (exactly matching the skirts).
        var nextOf: [Int: Int] = [:]
        for (u, v) in boundary { nextOf[u] = v }
        var hull: [Vec2] = []
        if let start = boundary.first?.0 {
            var cur = start
            for _ in 0...boundary.count {
                hull.append(points[cur].xy)
                guard let nx = nextOf[cur] else { hull = []; break }
                cur = nx
                if cur == start { break }
            }
        }
        if hull.count < 3 || hull.count != boundary.count { hull = RG.convexHull(points.map(\.xy)) }
        if hull.count >= 3 {
            for t in Triangulator.triangulate(hull, holes: []) {
                let a = hull[t.0], b = hull[t.1], c = hull[t.2]
                // Base faces down: reverse the CCW plan order.
                tris.append((Vec3(a.x, a.y, z0), Vec3(c.x, c.y, z0), Vec3(b.x, b.y, z0)))
            }
        }
        let size = max(BBox2(points: points.map(\.xy)).width, 1)
        var s = MeshTools.solid(from: tris, tolerance: size * 1e-9)
        s.origin = Vec3(s.origin.x, s.origin.y, z0)
        return s
    }

    /// Contour polylines of a triangulated surface at every multiple of `interval` (chained segments).
    public static func contours(vertices v: [Vec3], triangles t: [Int], interval: Double, minZ: Double? = nil) -> [(z: Double, lines: [[Vec2]])] {
        guard interval > 0, !v.isEmpty else { return [] }
        let zs = v.map(\.z)
        let lo = max(zs.min()!, minZ ?? -.infinity), hi = zs.max()!
        guard hi > lo else { return [] }
        var levels: [Double] = []
        var z = (lo / interval).rounded(.up) * interval
        if z <= lo { z += interval }
        while z < hi && levels.count < 2000 { levels.append(z); z += interval }
        var out: [(Double, [[Vec2]])] = []
        for lv in levels {
            var segs: [(Vec2, Vec2)] = []
            var i = 0
            while i + 2 < t.count {
                let ids = [t[i], t[i + 1], t[i + 2]]
                i += 3
                guard ids.allSatisfy({ $0 >= 0 && $0 < v.count }) else { continue }
                // Only the upward-facing surface (skip base and skirts of terrain solids).
                let a = v[ids[0]], b = v[ids[1]], c = v[ids[2]]
                let n = (b - a).cross(c - a)
                guard n.z > 1e-12 * n.length else { continue }
                var pts: [Vec2] = []
                for k in 0..<3 {
                    let p = v[ids[k]], q = v[ids[(k + 1) % 3]]
                    let dp = p.z - lv, dq = q.z - lv
                    if (dp < 0) != (dq < 0) { let s = dp / (dp - dq); pts.append((p + (q - p) * s).xy) }
                }
                if pts.count == 2, pts[0].distance(to: pts[1]) > 1e-12 { segs.append((pts[0], pts[1])) }
            }
            out.append((lv, chain(segs)))
        }
        return out.map { (z: $0.0, lines: $0.1) }
    }

    /// Chains unordered segments into polylines (closed loops repeat their first point).
    static func chain(_ segs: [(Vec2, Vec2)]) -> [[Vec2]] {
        guard !segs.isEmpty else { return [] }
        var b = BBox2.empty
        for s in segs { b.add(s.0); b.add(s.1) }
        let q = max(b.width, b.height, 1e-9) * 1e-9
        func key(_ p: Vec2) -> [Int64] { [Int64((p.x / q).rounded()), Int64((p.y / q).rounded())] }
        var adj: [[Int64]: [Int]] = [:]
        for (k, s) in segs.enumerated() { adj[key(s.0), default: []].append(k); adj[key(s.1), default: []].append(k) }
        var used = [Bool](repeating: false, count: segs.count)
        var out: [[Vec2]] = []
        for st in 0..<segs.count where !used[st] {
            used[st] = true
            var line = [segs[st].0, segs[st].1]
            for forward in [true, false] {
                var ext = true
                while ext {
                    ext = false
                    let end = forward ? line[line.count - 1] : line[0]
                    let k = key(end)
                    if let nx = adj[k]?.first(where: { !used[$0] }) {
                        used[nx] = true
                        let s = segs[nx]
                        let other = key(s.0) == k ? s.1 : s.0
                        if forward { line.append(other) } else { line.insert(other, at: 0) }
                        ext = true
                    }
                }
            }
            out.append(line)
        }
        return out
    }

    /// Elevation of the surface at a plan point (nil outside).
    public static func elevation(at p: Vec2, vertices v: [Vec3], triangles t: [Int]) -> Double? {
        var best: Double? = nil
        var i = 0
        while i + 2 < t.count {
            let a = v[t[i]], b = v[t[i + 1]], c = v[t[i + 2]]
            i += 3
            let n = (b - a).cross(c - a)
            guard abs(n.z) > 1e-12 else { continue }
            let d = (b.xy - a.xy).cross(c.xy - a.xy)
            let w1 = (b.xy - p).cross(c.xy - p) / d, w2 = (c.xy - p).cross(a.xy - p) / d, w3 = 1 - w1 - w2
            if w1 >= -1e-9, w2 >= -1e-9, w3 >= -1e-9 {
                let z = a.z * w1 + b.z * w2 + c.z * w3
                if n.z > 0 { best = max(best ?? z, z) }
            }
        }
        return best
    }
}

/// Contour input for toposurfaces (BIM-111).
public enum TopoContours {
    /// Case-insensitive wildcard match (* and ?).
    public static func wildcard(_ pattern: String, _ s: String) -> Bool {
        let p = Array(pattern.uppercased()), t = Array(s.uppercased())
        var dp = Array(repeating: Array(repeating: false, count: t.count + 1), count: p.count + 1)
        dp[0][0] = true
        for i in 0..<p.count where p[i] == "*" { dp[i + 1][0] = dp[i][0] }
        if p.isEmpty { return t.isEmpty }
        for i in 1...p.count {
            for j in stride(from: 1, through: t.count, by: 1) {
                switch p[i - 1] {
                case "*": dp[i][j] = dp[i - 1][j] || dp[i][j - 1]
                case "?": dp[i][j] = dp[i - 1][j - 1]
                default: dp[i][j] = dp[i - 1][j - 1] && p[i - 1] == t[j - 1]
                }
            }
        }
        return dp[p.count][t.count]
    }

    /// 3D points along a contour entity: vertices at the contour's elevation (or per-vertex z of 3D polylines,
    /// props vertexZ), with long segments resampled every `step` so the triangulation follows the contour.
    public static func points(_ e: Entity, doc: ArchiDocument, elevation z0: Double, step: Double) -> [Vec3] {
        var out: [Vec3] = []
        let vz = e.props["vertexZ"]?.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if let vz = vz, case .polyline(let pl) = e.geometry, vz.count == pl.vertices.count {
            let n = pl.vertices.count
            for i in 0..<n {
                let a = pl.vertices[i].p, za = vz[i]
                out.append(Vec3(a.x, a.y, za))
                guard i + 1 < n || pl.closed else { continue }
                let j = (i + 1) % n, b = pl.vertices[j].p, zb = vz[j]
                let len = a.distance(to: b)
                if step > 0, len > step {
                    let m = Int(len / step)
                    for k in 1...m { let t = Double(k) / Double(m + 1); let q = a.lerp(b, t); out.append(Vec3(q.x, q.y, za + (zb - za) * t)) }
                }
            }
            return out
        }
        for l in GeometryOps.tessellate(e.geometry, doc: doc) where l.count >= 2 {
            for i in 0..<l.count {
                out.append(Vec3(l[i].x, l[i].y, z0))
                if i + 1 < l.count {
                    let len = l[i].distance(to: l[i + 1])
                    if step > 0, len > step { let m = Int(len / step); for j in 1...m { let q = l[i].lerp(l[i + 1], Double(j) / Double(m + 1)); out.append(Vec3(q.x, q.y, z0)) } }
                }
            }
        }
        return out
    }
}
