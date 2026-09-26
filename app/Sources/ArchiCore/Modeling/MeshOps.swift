// Oanarina Archi Tool — GPL-3.0-or-later
// Mesh and solid operations for round 7: 3D align (M3D-049), face extrude (M3D-062), wireframe modifier (M3D-063),
// unfolding (M3D-064), cross-sections (M3D-061), Minkowski sum (M3D-044), springs (M3D-011), 3D text (M3D-012) and
// B-spline surfaces from control points (M3D-070).
import Foundation

public enum MeshOps {
    // MARK: 3D align

    /// Rigid (optionally uniformly scaled) map taking up to three source points onto destination points, AutoCAD
    /// 3DALIGN style: the first pair is matched exactly, the second fixes the direction, the third the plane.
    public static func alignment(source s: [Vec3], dest d: [Vec3], scale: Bool = false) -> ((Vec3) -> Vec3)? {
        guard !s.isEmpty, s.count == d.count, s.count <= 3 else { return nil }
        if s.count == 1 { let t = d[0] - s[0]; return { $0 + t } }
        let su = (s[1] - s[0]), du = (d[1] - d[0])
        guard su.length > 1e-12, du.length > 1e-12 else { return nil }
        let k = scale ? du.length / su.length : 1
        // Orthonormal frames from the points (the third point, or any vector not parallel to the first axis).
        func frame(_ p: [Vec3]) -> (Vec3, Vec3, Vec3)? {
            let x = (p[1] - p[0]).normalized
            var ref = p.count == 3 ? p[2] - p[0] : Vec3.unitZ
            if ref.cross(x).length < 1e-9 { ref = abs(x.z) < 0.9 ? Vec3.unitZ : Vec3(0, 1, 0) }
            let z = x.cross(ref).normalized
            guard z.length > 0.5 else { return nil }
            return (x, z.cross(x), z)
        }
        guard let fs = frame(s), let fd = frame(d) else { return nil }
        if s.count == 2 {
            // Two pairs: the smallest rotation taking one direction onto the other keeps "up" where possible.
            let a = su.normalized, b = du.normalized
            let axis = a.cross(b)
            let c = a.dot(b)
            if axis.length < 1e-12 {
                if c > 0 { return { d[0] + ($0 - s[0]) * k } }
                // Opposite directions: half turn about an axis perpendicular to a.
                var p = a.cross(Vec3.unitZ); if p.length < 1e-9 { p = a.cross(Vec3(1, 0, 0)) }
                let n = p.normalized
                return { q in let v = q - s[0]; return d[0] + (n * (2 * n.dot(v)) - v) * k }
            }
            let n = axis.normalized, sn = axis.length
            return { q in
                let v = q - s[0]
                // Rodrigues rotation.
                let r = v * c + n.cross(v) * sn + n * (n.dot(v) * (1 - c))
                return d[0] + r * k
            }
        }
        return { q in
            let v = q - s[0]
            let lx = v.dot(fs.0), ly = v.dot(fs.1), lz = v.dot(fs.2)
            return d[0] + (fd.0 * lx + fd.1 * ly + fd.2 * lz) * k
        }
    }

    // MARK: Face extrude

    static func welded(_ s: SolidGeom) -> (v: [Vec3], t: [Int]) { let w = SolidOps.welded(s); return (w.vertices, w.triangles) }

    /// Triangles of a solid whose normal is within `angle` degrees of `dir` (and, when given, whose plan projection
    /// contains `at`, grown to the connected coplanar region).
    public static func faces(_ s: SolidGeom, facing dir: Vec3, angle: Double = 1, at: Vec2? = nil) -> Set<Int> {
        let (v, t) = welded(s)
        let cosMax = cos(angle * .pi / 180), dn = dir.normalized
        var sel = Set<Int>()
        for f in 0..<(t.count / 3) {
            let a = v[t[3 * f]], b = v[t[3 * f + 1]], c = v[t[3 * f + 2]]
            let n = (b - a).cross(c - a).normalized
            if n.dot(dn) >= cosMax { sel.insert(f) }
        }
        guard let p = at else { return sel }
        // Seed: selected faces containing p in plan; flood over shared edges within the selection.
        func contains(_ f: Int) -> Bool {
            let a = v[t[3 * f]].xy, b = v[t[3 * f + 1]].xy, c = v[t[3 * f + 2]].xy
            return GeometryOps.pointInPolygon(p, [a, b, c])
        }
        let seeds = sel.filter(contains)
        guard !seeds.isEmpty else { return [] }
        // Keep the nearest seed plane (highest for upward faces).
        let best = seeds.max { v[t[3 * $0]].dot(dn) < v[t[3 * $1]].dot(dn) }!
        let plane = v[t[3 * best]].dot(dn)
        var edgeFaces: [[Int]: [Int]] = [:]
        for f in sel { for k in 0..<3 { let a = t[3 * f + k], b = t[3 * f + (k + 1) % 3]; edgeFaces[[min(a, b), max(a, b)], default: []].append(f) } }
        var out: Set<Int> = [best], stack = [best]
        while let f = stack.popLast() {
            for k in 0..<3 {
                let a = t[3 * f + k], b = t[3 * f + (k + 1) % 3]
                for g in edgeFaces[[min(a, b), max(a, b)]] ?? [] where !out.contains(g) && abs(v[t[3 * g]].dot(dn) - plane) < 1e-6 * max(1, abs(plane)) { out.insert(g); stack.append(g) }
            }
        }
        return out
    }

    /// Extrudes a set of faces (triangle indices of the welded mesh) by `distance` along their average normal; side
    /// walls join the boundary, so a closed solid stays closed.
    public static func extrudeFaces(_ s: SolidGeom, faces sel: Set<Int>, distance d: Double) -> SolidGeom? {
        let (v, t) = welded(s)
        guard !sel.isEmpty, abs(d) > 1e-12 else { return nil }
        var n = Vec3.zero
        for f in sel { n = n + (v[t[3 * f + 1]] - v[t[3 * f]]).cross(v[t[3 * f + 2]] - v[t[3 * f]]) }
        let dir = n.normalized
        guard dir.length > 0.5 else { return nil }
        var moved: [Int: Vec3] = [:]
        for f in sel { for k in 0..<3 { moved[t[3 * f + k]] = v[t[3 * f + k]] + dir * d } }
        var directed: [[Int]: Int] = [:]
        for f in sel { for k in 0..<3 { directed[[t[3 * f + k], t[3 * f + (k + 1) % 3]], default: 0] += 1 } }
        var tris: [Tri3] = []
        for f in 0..<(t.count / 3) {
            let a = t[3 * f], b = t[3 * f + 1], c = t[3 * f + 2]
            if sel.contains(f) { tris.append((moved[a]!, moved[b]!, moved[c]!)) } else { tris.append((v[a], v[b], v[c])) }
        }
        for (e, _) in directed where directed[[e[1], e[0]]] == nil {
            let a = e[0], b = e[1]
            tris.append((v[a], v[b], moved[b]!)); tris.append((v[a], moved[b]!, moved[a]!))
        }
        return SolidPrimitives.solid(tris)
    }

    // MARK: Wireframe

    /// Wireframe modifier: every feature edge becomes a square strut of the given thickness and every vertex a small
    /// cube, each a closed component (one solid with several shells).
    public static func wireframe(_ s: SolidGeom, thickness w: Double, angle: Double = 1) -> SolidGeom? {
        let (v, t) = welded(s)
        guard w > 0, !t.isEmpty else { return nil }
        let edges = MeshTools.featureEdges(vertices: v, triangles: t, angle: angle)
        var tris: [Tri3] = []
        var nodes: [Vec3] = []
        func box(_ a: Vec3, _ b: Vec3, _ r: Double) {
            let x = (b - a).normalized
            guard x.length > 0.5 else { return }
            var up = abs(x.z) < 0.9 ? Vec3.unitZ : Vec3(1, 0, 0)
            up = (up - x * up.dot(x)).normalized
            let y = x.cross(up).normalized
            let c = [up * (-r) + y * r, up * (-r) - y * r, up * r - y * r, up * r + y * r]
            let ra = c.map { a + $0 }, rb = c.map { b + $0 }
            var local = SolidPrimitives.band(ra, rb)
            local += SolidPrimitives.polygon(ra.reversed(), normal: -x)
            local += SolidPrimitives.polygon(rb, normal: x)
            if SolidPrimitives.signedVolume(local) < 0 { local = local.map { ($0.0, $0.2, $0.1) } }
            tris += local
        }
        for e in edges where e.count >= 2 {
            for k in 0..<(e.count - 1) {
                let a = e[k], b = e[k + 1], len = a.distance(to: b)
                guard len > w * 1.01 else { continue }
                let d = (b - a) / len
                // Struts end inside the (slightly larger) node cubes, so no two shells share vertices.
                guard len > w * 1.2 else { continue }
                box(a + d * (w * 0.55), b - d * (w * 0.55), w / 2)
                for p in [a, b] where !nodes.contains(where: { $0.distance(to: p) < 1e-9 }) { nodes.append(p) }
            }
        }
        for p in nodes { box(p - Vec3(w * 0.6, 0, 0), p + Vec3(w * 0.6, 0, 0), w * 0.6) }
        guard !tris.isEmpty else { return nil }
        // Orient each shell outward independently (solid() would flip all together).
        return MeshTools.solid(from: tris, tolerance: w * 1e-4)
    }

    // MARK: Unfold

    public struct Net { public var faces: [[Vec2]]; public var cuts: [[Vec2]]; public var folds: [[Vec2]] }

    /// Unfolds a mesh into flat pieces for fabrication: coplanar triangles are merged into faces; faces are laid out
    /// breadth-first across shared edges keeping edge lengths; a face that would overlap starts a new island.
    public static func unfold(_ s: SolidGeom, gap: Double) -> Net? {
        let (v, t) = welded(s)
        let nf = t.count / 3
        guard nf > 0 else { return nil }
        var edgeFaces: [[Int]: [Int]] = [:]
        for f in 0..<nf { for k in 0..<3 { let a = t[3 * f + k], b = t[3 * f + (k + 1) % 3]; edgeFaces[[min(a, b), max(a, b)], default: []].append(f) } }
        var placed: [Int: [Vec2]] = [:]
        var island: [Int: Int] = [:]
        var folds: [[Vec2]] = []
        var offsetX = 0.0
        func overlaps(_ tri: [Vec2], _ isl: Int) -> Bool {
            let tb = BBox2(points: tri)
            for (f, q) in placed where island[f] == isl {
                guard BBox2(points: q).intersects(tb) else { continue }
                if trianglesOverlap(tri, q) { return true }
            }
            return false
        }
        var islandCount = 0
        for seed in 0..<nf where placed[seed] == nil {
            let isl = islandCount; islandCount += 1
            // Lay the seed flat in its own plane frame.
            let a = v[t[3 * seed]], b = v[t[3 * seed + 1]], c = v[t[3 * seed + 2]]
            let x = (b - a).normalized, n = (b - a).cross(c - a).normalized, y = n.cross(x)
            var tri = [Vec2(0, 0), Vec2((b - a).dot(x), (b - a).dot(y)), Vec2((c - a).dot(x), (c - a).dot(y))]
            let bb = BBox2(points: tri)
            tri = tri.map { $0 + Vec2(offsetX - bb.min.x, -bb.min.y) }
            placed[seed] = tri; island[seed] = isl
            var queue = [seed]
            func coplanar(_ f: Int, _ g: Int) -> Bool {
                let n1 = (v[t[3 * f + 1]] - v[t[3 * f]]).cross(v[t[3 * f + 2]] - v[t[3 * f]]).normalized
                let n2 = (v[t[3 * g + 1]] - v[t[3 * g]]).cross(v[t[3 * g + 2]] - v[t[3 * g]]).normalized
                return n1.dot(n2) > 1 - 1e-9
            }
            /// Places face g across the edge k of the placed face f (third vertex mirrored to the other side).
            func place(from f: Int, edge k: Int, to g: Int) -> Bool {
                guard let pf = placed[f], placed[g] == nil else { return false }
                let ia = t[3 * f + k], ib = t[3 * f + (k + 1) % 3]
                let pa = pf[k], pb = pf[(k + 1) % 3]
                guard let gi = (0..<3).first(where: { t[3 * g + $0] != ia && t[3 * g + $0] != ib }) else { return false }
                let P = v[t[3 * g + gi]], A = v[ia], B = v[ib]
                let e = B - A, el = e.length
                guard el > 1e-12 else { return false }
                let along = (P - A).dot(e) / el
                let h = ((P - A) - e * ((P - A).dot(e) / (el * el))).length
                let d2 = (pb - pa) / el
                // The placed face lies to the left of pa→pb (CCW); the new one goes to the right.
                let q = pa + d2 * along - d2.perp * h
                var gt = [Vec2](repeating: .zero, count: 3)
                for m in 0..<3 { let vid = t[3 * g + m]; gt[m] = vid == ia ? pa : (vid == ib ? pb : q) }
                if overlaps(gt, isl) { return false }
                placed[g] = gt; island[g] = isl
                if !coplanar(f, g) { folds.append([pa, pb]) }
                return true
            }
            /// Places the rest of g's flat face right away, so faces are never split across the net.
            func claimRegion(_ g: Int) {
                var stack = [g]
                while let x = stack.popLast() {
                    queue.append(x)
                    for k in 0..<3 {
                        let ia = t[3 * x + k], ib = t[3 * x + (k + 1) % 3]
                        for y in edgeFaces[[min(ia, ib), max(ia, ib)]] ?? [] where y != x && placed[y] == nil && coplanar(x, y) {
                            if place(from: x, edge: k, to: y) { stack.append(y) }
                        }
                    }
                }
            }
            queue = []
            claimRegion(seed)
            var qi = 0
            while qi < queue.count {
                let f = queue[qi]; qi += 1
                for k in 0..<3 {
                    let ia = t[3 * f + k], ib = t[3 * f + (k + 1) % 3]
                    for g in edgeFaces[[min(ia, ib), max(ia, ib)]] ?? [] where g != f && placed[g] == nil {
                        if place(from: f, edge: k, to: g) { claimRegion(g) }
                    }
                }
            }
            var ib2 = BBox2.empty
            for (f, q) in placed where island[f] == isl { q.forEach { ib2.add($0) } }
            offsetX = ib2.max.x + gap
        }
        // Cut lines: triangle edges not shared with a neighbour placed alongside (in the same flat position).
        var cuts: [[Vec2]] = []
        var seen = Set<[Int]>()
        for f in 0..<nf {
            guard let pf = placed[f] else { continue }
            for k in 0..<3 {
                let ia = t[3 * f + k], ib = t[3 * f + (k + 1) % 3]
                let key = [min(ia, ib), max(ia, ib)]
                let others = (edgeFaces[key] ?? []).filter { $0 != f }
                let joined = others.contains { g in
                    guard let pg = placed[g], island[g] == island[f] else { return false }
                    return pg.contains { $0.isClose(pf[k], tol: 1e-6) } && pg.contains { $0.isClose(pf[(k + 1) % 3], tol: 1e-6) }
                }
                if !joined { cuts.append([pf[k], pf[(k + 1) % 3]]) }
                else if !seen.contains(key) { seen.insert(key) }
            }
        }
        return Net(faces: (0..<nf).compactMap { placed[$0] }, cuts: cuts, folds: folds)
    }

    /// Interiors of two triangles overlap (touching edges do not count).
    static func trianglesOverlap(_ a: [Vec2], _ b: [Vec2]) -> Bool {
        let tol = 1e-7 * max(BBox2(points: a + b).width, BBox2(points: a + b).height, 1)
        func sepAxis(_ p: [Vec2], _ q: [Vec2]) -> Bool {
            for i in 0..<3 {
                let e = p[(i + 1) % 3] - p[i], n = e.perp
                let pr = p.map { $0.dot(n) }, qr = q.map { $0.dot(n) }
                let nl = n.length
                if pr.max()! <= qr.min()! + tol * nl || qr.max()! <= pr.min()! + tol * nl { return true }
            }
            return false
        }
        return !(sepAxis(a, b) || sepAxis(b, a))
    }

    // MARK: Cross-sections

    /// Closed and open section polylines of a mesh with the horizontal plane z = h (plan coordinates).
    public static func section(_ s: SolidGeom, z h: Double) -> [[Vec2]] {
        let (v, t) = welded(s)
        var segs: [(Vec2, Vec2)] = []
        for f in 0..<(t.count / 3) {
            let p = [v[t[3 * f]], v[t[3 * f + 1]], v[t[3 * f + 2]]]
            var pts: [Vec2] = []
            for k in 0..<3 {
                let a = p[k], b = p[(k + 1) % 3]
                let da = a.z - h, db = b.z - h
                if (da < 0) != (db < 0) { let u = da / (da - db); pts.append((a + (b - a) * u).xy) }
            }
            if pts.count == 2, pts[0].distance(to: pts[1]) > 1e-12 { segs.append((pts[0], pts[1])) }
        }
        return chain(segs)
    }

    static func chain(_ segs0: [(Vec2, Vec2)]) -> [[Vec2]] {
        var segs = segs0
        var out: [[Vec2]] = []
        let tol = 1e-7
        while let first = segs.popLast() {
            var line = [first.0, first.1]
            var grown = true
            while grown {
                grown = false
                if let i = segs.firstIndex(where: { $0.0.isClose(line.last!, tol: tol) || $0.1.isClose(line.last!, tol: tol) }) {
                    let s = segs.remove(at: i); line.append(s.0.isClose(line.last!, tol: tol) ? s.1 : s.0); grown = true
                } else if let i = segs.firstIndex(where: { $0.0.isClose(line[0], tol: tol) || $0.1.isClose(line[0], tol: tol) }) {
                    let s = segs.remove(at: i); line.insert(s.0.isClose(line[0], tol: tol) ? s.1 : s.0, at: 0); grown = true
                }
            }
            out.append(line)
        }
        return out
    }

    // MARK: Minkowski

    /// Minkowski sum as the convex hull of all vertex sums: exact for convex operands (the usual rounding-by-sphere
    /// and chamfer uses), a convex envelope otherwise.
    public static func minkowski(_ a: SolidGeom, _ b: SolidGeom) -> SolidGeom? {
        let va = welded(a).v, vb = welded(b).v
        guard !va.isEmpty, !vb.isEmpty, va.count * vb.count <= 400_000 else { return nil }
        var pts: [Vec3] = []
        pts.reserveCapacity(va.count * vb.count)
        for p in va { for q in vb { pts.append(p + q) } }
        return SolidPrimitives.hull(pts)
    }

    // MARK: Spring

    /// Coil spring: a round wire (radius r) swept along a helix (coil radius R, pitch, turns) with flat caps.
    public static func spring(center c: Vec3, coilRadius R: Double, wireRadius r: Double, pitch p: Double, turns: Double, segments: Int = 16) -> SolidGeom? {
        guard R > r, r > 0, turns > 0, p >= 2 * r * 1.0001 || p == 0 else { return nil }
        let steps = max(8, Int(turns * 36))
        let path = (0...steps).map { i -> Vec3 in
            let a = 2 * .pi * turns * Double(i) / Double(steps)
            return c + Vec3(R * cos(a), R * sin(a), p * turns * Double(i) / Double(steps))
        }
        var rings: [[Vec3]] = []
        for i in 0...steps {
            let tng = (i < steps ? path[i + 1] - path[i] : path[i] - path[i - 1]).normalized
            let radial = Vec3(path[i].x - c.x, path[i].y - c.y, 0).normalized
            let bn = tng.cross(radial).normalized, nn = bn.cross(tng).normalized
            rings.append((0..<segments).map { k in let a = 2 * .pi * Double(k) / Double(segments); return path[i] + nn * (r * cos(a)) + bn * (r * sin(a)) })
        }
        var tris: [Tri3] = []
        for i in 0..<steps { tris += SolidPrimitives.band(rings[i], rings[i + 1]) }
        tris += SolidPrimitives.polygon(rings[0], normal: -(path[1] - path[0]).normalized)
        tris += SolidPrimitives.polygon(rings[steps], normal: (path[steps] - path[steps - 1]).normalized)
        return SolidPrimitives.solid(tris)
    }

    // MARK: 3D text

    /// Extruded text: each stroke of the single-line font becomes a closed bar of the stroke width, `depth` high.
    public static func text3D(_ t: TextGeom, z: Double, depth: Double, stroke w: Double) -> SolidGeom? {
        guard depth > 0, w > 0 else { return nil }
        var tris: [Tri3] = []
        for pl in StrokeFont.strokes(t) where pl.count >= 2 {
            for k in 0..<(pl.count - 1) {
                let a = pl[k], b = pl[k + 1], len = a.distance(to: b)
                guard len > 1e-9 else { continue }
                let d = (b - a) / len, n = d.perp * (w / 2)
                let e = d * (w / 2)
                let quad = [a - e - n, b + e - n, b + e + n, a - e + n]
                tris += SolidPrimitives.band(quad.map { Vec3($0.x, $0.y, z) }, quad.map { Vec3($0.x, $0.y, z + depth) })
                tris += SolidPrimitives.polygon(quad.map { Vec3($0.x, $0.y, z) }, normal: Vec3(0, 0, -1))
                tris += SolidPrimitives.polygon(quad.map { Vec3($0.x, $0.y, z + depth) }, normal: Vec3.unitZ)
            }
        }
        guard !tris.isEmpty else { return nil }
        return MeshTools.solid(from: tris, tolerance: w * 1e-5)
    }

    // MARK: B-spline surface from control points

    /// Clamped uniform B-spline basis values for `n` control points of degree p at parameter u ∈ [0, 1].
    static func basis(_ n: Int, _ p0: Int, _ u: Double) -> [Double] {
        let p = min(p0, n - 1)
        let m = n + p + 1
        var knots = [Double](repeating: 0, count: m)
        let inner = n - p
        for i in 0..<m { knots[i] = i <= p ? 0 : (i >= n ? 1 : Double(i - p) / Double(inner)) }
        let uu = min(max(u, 0), 1 - 1e-12)
        var N = (0..<(m - 1)).map { i in (uu >= knots[i] && uu < knots[i + 1]) ? 1.0 : 0.0 }
        if p > 0 {
            for d in 1...p {
                for i in 0..<(m - 1 - d) {
                    var a = 0.0, b = 0.0
                    let d1 = knots[i + d] - knots[i], d2 = knots[i + d + 1] - knots[i + 1]
                    if d1 > 1e-12 { a = (uu - knots[i]) / d1 * N[i] }
                    if d2 > 1e-12 { b = (knots[i + d + 1] - uu) / d2 * N[i + 1] }
                    N[i] = a + b
                }
            }
        }
        return Array(N.prefix(n))
    }

    /// Point on a tensor-product B-spline surface (control grid rows × columns, degree ≤ 3).
    public static func surfacePoint(_ cv: [[Vec3]], u: Double, v: Double, degree: Int = 3) -> Vec3 {
        let nu = cv.count, nv = cv.first?.count ?? 0
        let bu = basis(nu, degree, u), bv = basis(nv, degree, v)
        var p = Vec3.zero
        for i in 0..<nu where bu[i] != 0 { for j in 0..<nv where bv[j] != 0 { p = p + cv[i][j] * (bu[i] * bv[j]) } }
        return p
    }

    /// Open triangulated surface through a control grid (the corners are interpolated, interior CVs pull the surface).
    public static func surface(_ cv: [[Vec3]], divisions: Int = 16, degree: Int = 3) -> (vertices: [Vec3], triangles: [Int])? {
        guard cv.count >= 2, let nv = cv.first?.count, nv >= 2, cv.allSatisfy({ $0.count == nv }) else { return nil }
        let n = max(2, divisions)
        var vs: [Vec3] = []
        for i in 0...n { for j in 0...n { vs.append(surfacePoint(cv, u: Double(i) / Double(n), v: Double(j) / Double(n), degree: degree)) } }
        var ts: [Int] = []
        for i in 0..<n { for j in 0..<n {
            let a = i * (n + 1) + j, b = a + 1, c = a + n + 1, d = c + 1
            ts += [a, c, d, a, d, b]
        } }
        return (vs, ts)
    }

    /// Flat control grid over a rectangle (rows along Y, columns along X) at elevation z.
    public static func grid(from a: Vec2, to b: Vec2, rows: Int, cols: Int, z: Double) -> [[Vec3]] {
        let box = BBox2(points: [a, b])
        return (0..<max(rows, 2)).map { i in (0..<max(cols, 2)).map { j in
            Vec3(box.min.x + box.width * Double(j) / Double(max(cols, 2) - 1), box.min.y + box.height * Double(i) / Double(max(rows, 2) - 1), z) } }
    }

    static func encode(_ cv: [[Vec3]]) -> String { cv.map { $0.map { "\(fmt($0.x, 6)),\(fmt($0.y, 6)),\(fmt($0.z, 6))" }.joined(separator: " ") }.joined(separator: ";") }
    static func decode(_ s: String) -> [[Vec3]]? {
        let rows = s.split(separator: ";").map { r in r.split(separator: " ").compactMap { p -> Vec3? in
            let c = p.split(separator: ",").compactMap { Double($0) }; return c.count == 3 ? Vec3(c[0], c[1], c[2]) : nil } }
        guard rows.count >= 2, let n = rows.first?.count, n >= 2, rows.allSatisfy({ $0.count == n }) else { return nil }
        return rows
    }

    /// CV surfaces (props cvGrid) regenerate their mesh when their control points change. True if anything changed.
    @discardableResult
    public static func updateSurfaces(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            guard let g = doc.entities[i].props["cvGrid"], let cv = decode(g), case .solid(let s) = doc.entities[i].geometry else { continue }
            let div = doc.entities[i].props["cvDivisions"].flatMap(Int.init) ?? 16
            guard let m = surface(cv, divisions: div) else { continue }
            if s.meshVertices != m.vertices || s.meshTriangles != m.triangles {
                var b = BBox3.empty; m.vertices.forEach { b.add($0) }
                doc.entities[i].geometry = .solid(SolidGeom(kind: .mesh, origin: b.min, meshVertices: m.vertices, meshTriangles: m.triangles)); changed = true
            }
        }
        return changed
    }
}
