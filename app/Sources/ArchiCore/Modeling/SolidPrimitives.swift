// Oanarina Archi Tool — GPL-3.0-or-later
// Extra solid primitives and solid utilities (all produce closed, outward-oriented `.mesh` solids):
// wedge, pyramid/frustum, torus, regular prism and tube, polyhedron, polysolid, 3D convex hull, thicken,
// planar surface, separate/clean and validation.
import Foundation

public typealias Tri3 = (Vec3, Vec3, Vec3)

public enum SolidPrimitives {
    /// Closed solid from triangles; flips the whole set if it is inside-out. nil when empty.
    public static func solid(_ tris: [Tri3]) -> SolidGeom? {
        guard !tris.isEmpty else { return nil }
        var t = tris
        if signedVolume(t) < 0 { t = t.map { ($0.0, $0.2, $0.1) } }
        return MeshTools.solid(from: t, tolerance: 1e-6)
    }

    public static func signedVolume(_ t: [Tri3]) -> Double { t.reduce(0) { $0 + $1.0.dot($1.1.cross($1.2)) } / 6 }

    /// Triangles of a planar polygon (any winding), oriented along `normal`.
    static func polygon(_ pts: [Vec3], normal n: Vec3) -> [Tri3] {
        guard pts.count >= 3 else { return [] }
        let (u, v) = Mesh.basis(n)
        let flat = pts.map { Vec2($0.dot(u), $0.dot(v)) }
        var out: [Tri3] = []
        for t in Triangulator.triangulate(flat, holes: []) {
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            let fn = (b - a).cross(c - a)
            guard fn.length > 1e-14 else { continue }
            out.append(fn.dot(n) >= 0 ? (a, b, c) : (a, c, b))
        }
        return out
    }

    /// Two rings (same count) joined side by side, oriented away from `inside`.
    static func band(_ a: [Vec3], _ b: [Vec3], closed: Bool = true) -> [Tri3] {
        let n = a.count
        var out: [Tri3] = []
        for i in 0..<(closed ? n : n - 1) {
            let j = (i + 1) % n
            out.append((a[i], a[j], b[j])); out.append((a[i], b[j], b[i]))
        }
        return out
    }

    static func rotate(_ p: Vec3, about c: Vec3, _ ang: Double) -> Vec3 {
        let cs = cos(ang), sn = sin(ang), d = p - c
        return Vec3(c.x + d.x * cs - d.y * sn, c.y + d.x * sn + d.y * cs, p.z)
    }

    /// AutoCAD WEDGE: rectangular base length (X) × width (Y) at `corner`; the top slopes from `height` at x = 0 down to
    /// the base at x = length.
    public static func wedge(corner c: Vec3, length l: Double, width w: Double, height h: Double, rotation: Double = 0) -> SolidGeom? {
        guard abs(l) > 1e-9, abs(w) > 1e-9, abs(h) > 1e-9 else { return nil }
        let p = [Vec3(0, 0, 0), Vec3(l, 0, 0), Vec3(l, w, 0), Vec3(0, w, 0), Vec3(0, 0, h), Vec3(0, w, h)]
            .map { rotate(c + $0, about: c, rotation) }
        let faces: [[Int]] = [[0, 3, 2, 1], [0, 1, 4], [3, 5, 2], [0, 4, 5, 3], [1, 2, 5, 4]]
        return polyhedron(points: p, faces: faces)
    }

    /// Pyramid (topRadius 0) or frustum with `sides` sides; radii are circumscribed.
    public static func pyramid(center c: Vec3, sides: Int, radius r: Double, topRadius rt: Double = 0, height h: Double, rotation: Double = 0) -> SolidGeom? {
        guard sides >= 3, sides <= 256, r > 1e-9, rt >= 0, abs(h) > 1e-9 else { return nil }
        let base = (0..<sides).map { k -> Vec3 in let a = rotation + 2 * .pi * Double(k) / Double(sides); return c + Vec3(r * cos(a), r * sin(a), 0) }
        var t = polygon(base, normal: Vec3(0, 0, h > 0 ? -1 : 1))
        if rt < 1e-9 {
            let apex = c + Vec3(0, 0, h)
            for k in 0..<sides { t.append((base[k], base[(k + 1) % sides], apex)) }
        } else {
            let top = (0..<sides).map { k -> Vec3 in let a = rotation + 2 * .pi * Double(k) / Double(sides); return c + Vec3(rt * cos(a), rt * sin(a), h) }
            t += polygon(top, normal: Vec3(0, 0, h > 0 ? 1 : -1))
            t += band(base, top)
        }
        return solid(t)
    }

    /// Torus about a vertical axis through `center` (major radius R to the tube centre, tube radius r < R).
    public static func torus(center c: Vec3, radius R: Double, tube r: Double, segments: Int = 48, tubeSegments: Int = 24) -> SolidGeom? {
        guard R > 1e-9, r > 1e-9, r < R, segments >= 3, tubeSegments >= 3 else { return nil }
        let rings: [[Vec3]] = (0..<segments).map { i in
            let a = 2 * Double.pi * Double(i) / Double(segments)
            return (0..<tubeSegments).map { j in
                let b = 2 * Double.pi * Double(j) / Double(tubeSegments)
                let rr = R + r * cos(b)
                return c + Vec3(rr * cos(a), rr * sin(a), r * sin(b))
            }
        }
        var t: [Tri3] = []
        for i in 0..<segments { t += band(rings[i], rings[(i + 1) % segments]) }
        return solid(t)
    }

    /// Regular prism (circumradius `radius`, `sides` sides) of height h; with `innerRadius` > 0 a tube (hollow prism).
    public static func prism(center c: Vec3, sides: Int, radius r: Double, height h: Double, innerRadius ri: Double = 0, rotation: Double = 0) -> SolidGeom? {
        guard sides >= 3, sides <= 512, r > 1e-9, abs(h) > 1e-9, ri >= 0, ri < r - 1e-9 else { return nil }
        func ring(_ rad: Double, _ z: Double) -> [Vec3] {
            (0..<sides).map { k in let a = rotation + 2 * .pi * Double(k) / Double(sides); return c + Vec3(rad * cos(a), rad * sin(a), z) }
        }
        let o0 = ring(r, 0), o1 = ring(r, h)
        var t = band(o0, o1)
        if ri < 1e-9 {
            t += polygon(o0, normal: Vec3(0, 0, -1)) + polygon(o1, normal: Vec3(0, 0, 1))
        } else {
            let i0 = ring(ri, 0), i1 = ring(ri, h)
            t += band(i1, i0)                    // inner wall faces the axis
            t += band(i0, o0) + band(o1, i1)     // annular caps
        }
        return solid(t)
    }

    /// Solid from points and faces (vertex index lists, any winding; each face planar). Faces are re-oriented
    /// consistently and outward. nil when the faces do not close a volume.
    public static func polyhedron(points p: [Vec3], faces: [[Int]]) -> SolidGeom? {
        var tris: [Tri3] = []
        for f in faces {
            guard f.count >= 3, f.allSatisfy({ $0 >= 0 && $0 < p.count }) else { return nil }
            let pts = f.map { p[$0] }
            let n = Mesh.polygonNormal(pts)
            guard n.length > 0.5 else { continue }
            tris += polygon(pts, normal: n)
        }
        let cleaned = SolidCheck.clean(tris)
        guard SolidCheck.report(cleaned).closed else { return nil }
        return solid(cleaned)
    }

    /// POLYSOLID: a wall-like rectangle (width × height) swept along a 2D path at elevation z.
    /// justify: "Center", "Left" or "Right" of the direction of travel.
    public static func polysolid(path: [Vec2], z: Double, width w: Double, height h: Double, justify: String = "Center", closed: Bool = false) -> SolidGeom? {
        let pts = RG.dedupe(path, closed: closed)
        guard pts.count >= 2, w > 1e-9, h > 1e-9 else { return nil }
        let x0: Double, x1: Double
        switch justify.lowercased() {
        case "left": (x0, x1) = (0, w)
        case "right": (x0, x1) = (-w, 0)
        default: (x0, x1) = (-w / 2, w / 2)
        }
        var acc = MeshAcc()
        SweepMesh.sweep([Vec2(x0, 0), Vec2(x1, 0), Vec2(x1, h), Vec2(x0, h)], along: pts.map { Vec3($0.x, $0.y, z) }, closedPath: closed && pts.count >= 3, into: &acc)
        return solid(MeshTools.triangles(acc.mesh))
    }

    /// 3D convex hull (incremental). nil when the points are coplanar or fewer than four.
    public static func hull(_ pts0: [Vec3]) -> SolidGeom? {
        // Unique points.
        var pts: [Vec3] = []
        var seen = Set<[Int64]>()
        var scale = 1.0
        for p in pts0 { scale = max(scale, abs(p.x), abs(p.y), abs(p.z)) }
        let q = 1e-9 * scale
        for p in pts0 {
            let k = [Int64((p.x / q).rounded()), Int64((p.y / q).rounded()), Int64((p.z / q).rounded())]
            if seen.insert(k).inserted { pts.append(p) }
        }
        guard pts.count >= 4 else { return nil }
        let eps = 1e-9 * scale
        // Initial tetrahedron.
        let i0 = 0
        guard let i1 = pts.indices.max(by: { pts[$0].distance(to: pts[i0]) < pts[$1].distance(to: pts[i0]) }), pts[i1].distance(to: pts[i0]) > eps else { return nil }
        let d01 = (pts[i1] - pts[i0]).normalized
        func lineDist(_ p: Vec3) -> Double { ((p - pts[i0]) - d01 * (p - pts[i0]).dot(d01)).length }
        guard let i2 = pts.indices.max(by: { lineDist(pts[$0]) < lineDist(pts[$1]) }), lineDist(pts[i2]) > eps else { return nil }
        let n012 = (pts[i1] - pts[i0]).cross(pts[i2] - pts[i0]).normalized
        guard let i3 = pts.indices.max(by: { abs((pts[$0] - pts[i0]).dot(n012)) < abs((pts[$1] - pts[i0]).dot(n012)) }),
              abs((pts[i3] - pts[i0]).dot(n012)) > eps else { return nil }
        var faces: [[Int]] = []
        let centroid = (pts[i0] + pts[i1] + pts[i2] + pts[i3]) / 4
        func normal(_ f: [Int]) -> Vec3 { (pts[f[1]] - pts[f[0]]).cross(pts[f[2]] - pts[f[0]]) }
        for f0 in [[i0, i1, i2], [i0, i1, i3], [i0, i2, i3], [i1, i2, i3]] {
            var f = f0
            if normal(f).dot(pts[f[0]] - centroid) < 0 { f = [f[0], f[2], f[1]] }
            faces.append(f)
        }
        let used: Set<Int> = [i0, i1, i2, i3]
        for (pi, p) in pts.enumerated() where !used.contains(pi) {
            var visible: [Bool] = faces.map { f in let n = normal(f); return n.dot(p - pts[f[0]]) > eps * max(1, n.length) }
            guard visible.contains(true) else { continue }
            // Horizon: directed edges of visible faces whose reverse is on a hidden face.
            var edgeOwner: [[Int]: Bool] = [:]
            for (k, f) in faces.enumerated() { for e in 0..<3 { edgeOwner[[f[e], f[(e + 1) % 3]]] = visible[k] } }
            var horizon: [[Int]] = []
            for (k, f) in faces.enumerated() where visible[k] {
                for e in 0..<3 { let a = f[e], b = f[(e + 1) % 3]; if edgeOwner[[b, a]] == false { horizon.append([a, b]) } }
            }
            faces = faces.enumerated().filter { !visible[$0.offset] }.map(\.element)
            for e in horizon { faces.append([e[0], e[1], pi]) }
            visible = []
        }
        return solid(faces.map { (pts[$0[0]], pts[$0[1]], pts[$0[2]]) })
    }

    /// THICKEN: offsets an open surface along its vertex normals by `thickness` (negative = the other side) and closes
    /// the rim. nil for empty input.
    public static func thicken(vertices v0: [Vec3], triangles t0: [Int], thickness d: Double) -> SolidGeom? {
        guard abs(d) > 1e-9 else { return nil }
        let w = MeshTools.weld(stride(from: 0, to: t0.count - 2, by: 3).compactMap { i -> Tri3? in
            guard t0[i] < v0.count, t0[i + 1] < v0.count, t0[i + 2] < v0.count else { return nil }
            return (v0[t0[i]], v0[t0[i + 1]], v0[t0[i + 2]])
        }, tolerance: 1e-6)
        let v = w.vertices, t = w.triangles
        guard !t.isEmpty else { return nil }
        var nrm = Array(repeating: Vec3.zero, count: v.count)
        for i in stride(from: 0, to: t.count, by: 3) {
            let fn = (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]])   // area-weighted
            for k in 0..<3 { nrm[t[i + k]] = nrm[t[i + k]] + fn }
        }
        let off = v.indices.map { v[$0] + nrm[$0].normalized * d }
        var tris: [Tri3] = []
        var edges: [[Int]: Int] = [:]
        for i in stride(from: 0, to: t.count, by: 3) {
            let a = t[i], b = t[i + 1], c = t[i + 2]
            tris.append((v[a], v[b], v[c]))
            tris.append((off[a], off[c], off[b]))
            for (p, q) in [(a, b), (b, c), (c, a)] { edges[[p, q], default: 0] += 1 }
        }
        for (e, _) in edges where edges[[e[1], e[0]]] == nil {
            let a = e[0], b = e[1]
            tris.append((v[b], v[a], off[a])); tris.append((v[b], off[a], off[b]))
        }
        return solid(tris)
    }

    /// PLANESURF: triangulated planar surface (open) over a closed boundary at elevation z.
    public static func planarSurface(_ outer: [Vec2], holes: [[Vec2]] = [], z: Double) -> (vertices: [Vec3], triangles: [Int])? {
        let o = RG.dedupe(outer, closed: true)
        guard o.count >= 3, abs(GeometryOps.signedArea(o)) > 1e-12 else { return nil }
        let oc = GeometryOps.signedArea(o) < 0 ? o.reversed() : o
        let r = Triangulator.triangulateWithPoints(oc, holes: holes)
        var tris: [Int] = []
        for t in r.triangles {
            let a = r.points[t.0], b = r.points[t.1], c = r.points[t.2]
            if (b - a).cross(c - a) >= 0 { tris += [t.0, t.1, t.2] } else { tris += [t.0, t.2, t.1] }
        }
        return (r.points.map { Vec3($0.x, $0.y, z) }, tris)
    }
}

extension SolidPrimitives {
    /// OpenSCAD-style linear_extrude (M3D-091): extrudes a closed profile by `height` while twisting it by `twist` radians
    /// about its centroid and scaling it to `scale` at the top, in `slices` steps.
    public static func linearExtrude(_ profile0: [Vec2], z: Double, height h: Double, twist: Double = 0, scale: Double = 1, slices: Int = 0) -> SolidGeom? {
        var p = RG.dedupe(profile0, closed: true)
        guard p.count >= 3, abs(GeometryOps.signedArea(p)) > 1e-12, abs(h) > 1e-9, scale >= 0 else { return nil }
        if GeometryOps.signedArea(p) < 0 { p.reverse() }
        let c = GeometryOps.centroid(p)
        let n = slices > 0 ? min(slices, 512) : (abs(twist) > 1e-9 ? max(4, Int(abs(twist) / (.pi / 36))) : 1)
        var rings: [[Vec3]] = []
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = twist * t, sc = 1 + (scale - 1) * t
            let ca = cos(a), sa = sin(a)
            rings.append(p.map { q in let d = (q - c) * sc; return Vec3(c.x + d.x * ca - d.y * sa, c.y + d.x * sa + d.y * ca, z + h * t) })
        }
        if scale < 1e-9 {
            // Cone to a point: replace the last ring by the apex.
            var t = polygon(rings[0], normal: Vec3(0, 0, h > 0 ? -1 : 1))
            for r in 0..<(n - 1) { t += band(rings[r], rings[r + 1]) }
            let apex = Vec3(c.x, c.y, z + h)
            let last = rings[n - 1]
            for k in 0..<last.count { t.append((last[k], last[(k + 1) % last.count], apex)) }
            return solid(t)
        }
        var t = polygon(rings[0], normal: Vec3(0, 0, h > 0 ? -1 : 1)) + polygon(rings[n], normal: Vec3(0, 0, h > 0 ? 1 : -1))
        for r in 0..<n {
            if abs(twist) < 1e-9 { t += band(rings[r], rings[r + 1]); continue }
            // Non-planar quads: fan around the quad centre (no diagonal bias, so the volume is not lost to one side).
            let a = rings[r], b = rings[r + 1], m = a.count
            for i in 0..<m {
                let j = (i + 1) % m
                let ctr = (a[i] + a[j] + b[j] + b[i]) / 4
                t += [(a[i], a[j], ctr), (a[j], b[j], ctr), (b[j], b[i], ctr), (b[i], a[i], ctr)]
            }
        }
        return solid(t)
    }

    /// Faceted mesh primitives (M3D-055) with explicit divisions.
    public enum MeshKind: String, CaseIterable { case box, cylinder, cone, sphere, torus, wedge, pyramid }

    /// Box subdivided into `div` × `div` quads per face.
    public static func meshBox(origin o: Vec3, size s: Vec3, divisions div: Int) -> SolidGeom? {
        guard s.x > 1e-9, s.y > 1e-9, s.z > 1e-9 else { return nil }
        let n = max(1, min(div, 64))
        var t: [Tri3] = []
        func face(_ origin: Vec3, _ u: Vec3, _ v: Vec3) {
            for i in 0..<n { for j in 0..<n {
                let a = origin + u * (Double(i) / Double(n)) + v * (Double(j) / Double(n))
                let b = a + u / Double(n), d = a + v / Double(n), c = b + v / Double(n)
                t.append((a, b, c)); t.append((a, c, d))
            } }
        }
        let X = Vec3(s.x, 0, 0), Y = Vec3(0, s.y, 0), Z = Vec3(0, 0, s.z)
        face(o, Y, X); face(o + Z, X, Y)                 // bottom (−Z), top (+Z)
        face(o, X, Z); face(o + Y, Z, X)                 // front (−Y), back (+Y)
        face(o, Z, Y); face(o + X, Y, Z)                 // left (−X), right (+X)
        return solid(t)
    }

    /// UV sphere with `segments` around and `segments / 2` stacks.
    public static func meshSphere(center c: Vec3, radius r: Double, segments: Int) -> SolidGeom? {
        guard r > 1e-9 else { return nil }
        let m = max(6, min(segments, 256)), st = max(3, m / 2)
        var t: [Tri3] = []
        func P(_ i: Int, _ j: Int) -> Vec3 {
            let th = Double.pi * Double(j) / Double(st), ph = 2 * Double.pi * Double(i) / Double(m)
            return c + Vec3(r * sin(th) * cos(ph), r * sin(th) * sin(ph), r * cos(th))
        }
        for j in 0..<st { for i in 0..<m {
            let a = P(i, j), b = P(i + 1, j), cc = P(i + 1, j + 1), d = P(i, j + 1)
            if j > 0 { t.append((a, d, b)) }
            if j < st - 1 { t.append((b, d, cc)) }
        } }
        return solid(t)
    }
}

/// Solid validation, cleaning and separation (M3D-042 / M3D-054).
public enum SolidCheck {
    public struct Report: Hashable {
        public var triangles = 0, vertices = 0, degenerate = 0, openEdges = 0, nonManifoldEdges = 0, flippedEdges = 0, components = 0
        public var volume = 0.0
        public var closed: Bool { triangles > 0 && openEdges == 0 && nonManifoldEdges == 0 && flippedEdges == 0 }
        public var valid: Bool { closed && degenerate == 0 && volume > 0 }
        public var summary: String {
            valid ? "Valid closed solid: \(triangles) faces, \(components) body(ies)."
                : "Problems: " + [degenerate > 0 ? "\(degenerate) degenerate face(s)" : nil, openEdges > 0 ? "\(openEdges) open edge(s)" : nil,
                                  nonManifoldEdges > 0 ? "\(nonManifoldEdges) non-manifold edge(s)" : nil, flippedEdges > 0 ? "\(flippedEdges) inconsistently oriented edge(s)" : nil,
                                  volume <= 0 ? "non-positive volume" : nil, triangles == 0 ? "no faces" : nil].compactMap { $0 }.joined(separator: ", ") + "."
        }
    }

    public static func triangles(_ s: SolidGeom) -> [Tri3] { MeshTools.triangles(MeshTools.mesh(of: s)) }

    public static func report(_ tris: [Tri3], tolerance: Double = 1e-6) -> Report {
        var r = Report()
        var scale = 1.0
        for t in tris { scale = max(scale, abs(t.0.x), abs(t.0.y), abs(t.0.z)) }
        r.degenerate = tris.filter { ($0.1 - $0.0).cross($0.2 - $0.0).length <= 1e-12 * scale * scale }.count
        let w = MeshTools.weld(tris, tolerance: tolerance)
        r.triangles = w.triangles.count / 3; r.vertices = w.vertices.count
        var directed: [[Int]: Int] = [:]
        for i in stride(from: 0, to: w.triangles.count, by: 3) {
            let a = w.triangles[i], b = w.triangles[i + 1], c = w.triangles[i + 2]
            for (p, q) in [(a, b), (b, c), (c, a)] { directed[[p, q], default: 0] += 1 }
        }
        var done = Set<[Int]>()
        for (e, _) in directed {
            let k = e[0] < e[1] ? e : [e[1], e[0]]
            guard done.insert(k).inserted else { continue }
            let f = directed[[k[0], k[1]]] ?? 0, b = directed[[k[1], k[0]]] ?? 0
            if f + b == 1 { r.openEdges += 1 }
            else if f + b > 2 { r.nonManifoldEdges += 1 }
            else if f == 2 || b == 2 { r.flippedEdges += 1 }
        }
        r.components = components(w.vertices, w.triangles).count
        r.volume = SolidPrimitives.signedVolume(tris)
        return r
    }

    /// Triangle index groups of edge-connected components.
    static func components(_ v: [Vec3], _ t: [Int]) -> [[Int]] {
        var parent = Array(0..<v.count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for i in stride(from: 0, to: t.count, by: 3) { let a = find(t[i]); parent[find(t[i + 1])] = a; parent[find(t[i + 2])] = a }
        var groups: [Int: [Int]] = [:]
        for i in stride(from: 0, to: t.count, by: 3) { groups[find(t[i]), default: []].append(i / 3) }
        return groups.values.sorted { $0[0] < $1[0] }
    }

    /// Removes degenerate and duplicate faces and orients every edge-connected shell consistently and outward.
    public static func clean(_ tris: [Tri3], tolerance: Double = 1e-6) -> [Tri3] {
        let w = MeshTools.weld(tris, tolerance: tolerance)
        let v = w.vertices
        var faces: [[Int]] = []
        var seen = Set<[Int]>()
        for i in stride(from: 0, to: w.triangles.count, by: 3) {
            let f = [w.triangles[i], w.triangles[i + 1], w.triangles[i + 2]]
            guard (v[f[1]] - v[f[0]]).cross(v[f[2]] - v[f[0]]).length > 1e-14 else { continue }
            if seen.insert(f.sorted()).inserted { faces.append(f) }
        }
        // Edge → faces adjacency; BFS flipping neighbours to make shared edges opposite.
        var adj: [[Int]: [Int]] = [:]
        for (k, f) in faces.enumerated() { for e in 0..<3 { let a = f[e], b = f[(e + 1) % 3]; adj[[min(a, b), max(a, b)], default: []].append(k) } }
        var state = Array(repeating: 0, count: faces.count)   // 0 unvisited, 1 visited
        var shells: [[Int]] = []
        for s in faces.indices where state[s] == 0 {
            var queue = [s], shell: [Int] = []
            state[s] = 1
            while let k = queue.popLast() {
                shell.append(k)
                let f = faces[k]
                for e in 0..<3 {
                    let a = f[e], b = f[(e + 1) % 3]
                    for m in adj[[min(a, b), max(a, b)]] ?? [] where m != k && state[m] == 0 {
                        // Neighbour must traverse the edge as b → a.
                        let g = faces[m]
                        let same = (0..<3).contains { g[$0] == a && g[($0 + 1) % 3] == b }
                        if same { faces[m] = [g[0], g[2], g[1]] }
                        state[m] = 1; queue.append(m)
                    }
                }
            }
            shells.append(shell)
        }
        var out: [Tri3] = []
        for shell in shells {
            var t = shell.map { (v[faces[$0][0]], v[faces[$0][1]], v[faces[$0][2]]) }
            if SolidPrimitives.signedVolume(t) < 0 { t = t.map { ($0.0, $0.2, $0.1) } }
            out += t
        }
        return out
    }

    /// Splits a solid into its separate bodies (edge-connected shells).
    public static func separate(_ s: SolidGeom) -> [SolidGeom] {
        let w = MeshTools.weld(triangles(s), tolerance: 1e-6)
        return components(w.vertices, w.triangles).compactMap { grp in
            SolidPrimitives.solid(grp.map { k in (w.vertices[w.triangles[3 * k]], w.vertices[w.triangles[3 * k + 1]], w.vertices[w.triangles[3 * k + 2]]) })
        }
    }
}
