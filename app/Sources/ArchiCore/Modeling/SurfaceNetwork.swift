// Oanarina Archi Tool — GPL-3.0-or-later
// Freeform surfaces: patch (Coons fill of a closed boundary, planar boundaries triangulated exactly, M3D-068), network
// (Gordon surface through a U/V curve network, M3D-066), offset / extend / trim (M3D-069) and sculpt (closed set of
// surfaces → solid, M3D-075).
import Foundation

public enum SurfaceNetwork {
    public typealias IndexedMesh = (vertices: [Vec3], triangles: [Int])

    // MARK: Curves

    /// Chains curves (in any order and direction) into one closed loop; nil when they do not close.
    public static func chainLoop(_ curves: [[Vec3]], tolerance tol: Double) -> [[Vec3]]? {
        guard var cur = curves.first, cur.count >= 2 else { return nil }
        if curves.count == 1 {
            guard cur.first!.distance(to: cur.last!) <= tol || cur.count >= 3 else { return nil }
            return [cur]
        }
        var rest = Array(curves.dropFirst())
        var loop = [cur]
        while !rest.isEmpty {
            let end = cur.last!
            guard let i = rest.firstIndex(where: { $0.first!.distance(to: end) <= tol || $0.last!.distance(to: end) <= tol }) else { return nil }
            var c = rest.remove(at: i)
            if c.first!.distance(to: end) > tol { c.reverse() }
            loop.append(c); cur = c
        }
        guard loop.last!.last!.distance(to: loop[0].first!) <= tol else { return nil }
        return loop
    }

    /// Best-fit plane (centroid, normal) and the largest distance of a point from it.
    static func plane(_ pts: [Vec3]) -> (c: Vec3, n: Vec3, dev: Double)? {
        guard pts.count >= 3 else { return nil }
        let c = pts.reduce(Vec3.zero, +) / Double(pts.count)
        var n = Vec3.zero
        for i in 0..<pts.count { let a = pts[i] - c, b = pts[(i + 1) % pts.count] - c; n = n + a.cross(b) }
        guard n.length > 1e-12 else { return nil }
        n = n.normalized
        return (c, n, pts.map { abs(($0 - c).dot(n)) }.max() ?? 0)
    }

    /// Indices of the (up to) four sharpest corners of a closed polyline, in order; nil when there are fewer than 4.
    static func corners(_ p: [Vec3]) -> [Int]? {
        let n = p.count
        guard n >= 4 else { return nil }
        var turn: [(Int, Double)] = []
        for i in 0..<n {
            let a = (p[i] - p[(i - 1 + n) % n]).normalized, b = (p[(i + 1) % n] - p[i]).normalized
            turn.append((i, acos(max(-1, min(1, a.dot(b))))))
        }
        let sharp = turn.filter { $0.1 > rad(30) }.sorted { $0.1 > $1.1 }.prefix(4).map(\.0).sorted()
        return sharp.count == 4 ? sharp : nil
    }

    static func arcLengthSplit(_ p: [Vec3]) -> [Int] {
        let n = p.count
        var cum = [0.0]
        for i in 0..<n { cum.append(cum[i] + p[i].distance(to: p[(i + 1) % n])) }
        let total = cum[n]
        return (0..<4).map { k in
            let target = total * Double(k) / 4
            return (0..<n).min { abs(cum[$0] - target) < abs(cum[$1] - target) } ?? 0
        }
    }

    // MARK: Patch (M3D-068)

    /// Fills a closed boundary: planar boundaries are triangulated exactly (trimmed planar patch); others get a Coons
    /// patch between four sides (the four given curves, the sharpest corners, or quarter points).
    public static func patch(_ curves: [[Vec3]], tolerance tol: Double = 1e-3, divisions: Int = 16) -> IndexedMesh? {
        guard let loop = chainLoop(curves, tolerance: tol) else { return nil }
        var pts: [Vec3] = []
        for c in loop { for q in c where !(pts.last.map { $0.distance(to: q) <= tol } ?? false) { pts.append(q) } }
        if pts.count > 2, pts.first!.distance(to: pts.last!) <= tol { pts.removeLast() }
        guard pts.count >= 3, let pl = plane(pts) else { return nil }
        let size = pts.reduce(0.0) { max($0, $1.distance(to: pl.c)) }
        if pl.dev <= max(tol, size * 1e-6) {
            let (u, v) = Mesh.basis(pl.n)
            let flat = pts.map { Vec2(($0 - pl.c).dot(u), ($0 - pl.c).dot(v)) }
            let tris = Triangulator.triangulate(flat, holes: [])
            guard !tris.isEmpty else { return nil }
            var t: [Int] = []
            for tr in tris {
                let ccw = (flat[tr.1] - flat[tr.0]).cross(flat[tr.2] - flat[tr.0]) > 0
                t += ccw ? [tr.0, tr.1, tr.2] : [tr.0, tr.2, tr.1]
            }
            return (pts, t)
        }
        if loop.count == 4, let r = SurfaceTools.coons(loop, m: divisions, n: divisions, tolerance: tol) { return r }
        let cs = corners(pts) ?? arcLengthSplit(pts)
        var sides: [[Vec3]] = []
        for k in 0..<4 {
            let a = cs[k], b = cs[(k + 1) % 4]
            var s: [Vec3] = []
            var i = a
            while true { s.append(pts[i]); if i == b { break }; i = (i + 1) % pts.count }
            guard s.count >= 2 else { return nil }
            sides.append(s)
        }
        return SurfaceTools.coons(sides, m: divisions, n: divisions, tolerance: max(tol, 1e-6))
    }

    // MARK: Network / Gordon surface (M3D-066)

    /// Closest points between two polylines: (point, arc length along a, arc length along b, distance).
    static func closest(_ a: [Vec3], _ b: [Vec3]) -> (p: Vec3, sa: Double, sb: Double, d: Double) {
        var best = (p: a[0], sa: 0.0, sb: 0.0, d: Double.infinity)
        var la = 0.0
        for i in 0..<(a.count - 1) {
            let p0 = a[i], p1 = a[i + 1], u = p1 - p0
            var lb = 0.0
            for j in 0..<(b.count - 1) {
                let q0 = b[j], q1 = b[j + 1], v = q1 - q0
                // Segment–segment closest points (clamped).
                let w = p0 - q0
                let aa = u.dot(u), bb = u.dot(v), cc = v.dot(v), dd = u.dot(w), ee = v.dot(w)
                let den = aa * cc - bb * bb
                var s = den > 1e-18 ? max(0, min(1, (bb * ee - cc * dd) / den)) : 0
                var t = cc > 1e-18 ? (bb * s + ee) / cc : 0
                if t < 0 { t = 0; s = aa > 1e-18 ? max(0, min(1, -dd / aa)) : 0 } else if t > 1 { t = 1; s = aa > 1e-18 ? max(0, min(1, (bb - dd) / aa)) : 0 }
                let pa = p0 + u * s, pb = q0 + v * t
                let d = pa.distance(to: pb)
                if d < best.d { best = ((pa + pb) / 2, la + u.length * s, lb + v.length * t, d) }
                lb += v.length
            }
            la += u.length
        }
        return best
    }

    static func point(_ c: [Vec3], at s: Double) -> Vec3 {
        var acc = 0.0
        for i in 0..<(c.count - 1) {
            let l = c[i].distance(to: c[i + 1])
            if s <= acc + l || i == c.count - 2 { let t = l > 1e-12 ? max(0, min(1, (s - acc) / l)) : 0; return c[i] + (c[i + 1] - c[i]) * t }
            acc += l
        }
        return c.last!
    }

    /// Clamped Catmull-Rom interpolation weights for knots 0…count−1 at parameter x (sum 1, δ at the knots).
    static func weights(_ count: Int, _ x: Double) -> [Double] {
        var w = Array(repeating: 0.0, count: count)
        guard count > 1 else { return [1] }
        let k = min(max(Int(x.rounded(.down)), 0), count - 2)
        let t = min(max(x - Double(k), 0), 1)
        let t2 = t * t, t3 = t2 * t
        let c = [(-t3 + 2 * t2 - t) / 2, (3 * t3 - 5 * t2 + 2) / 2, (-3 * t3 + 4 * t2 + t) / 2, (t3 - t2) / 2]
        for (o, cw) in zip(-1...2, c) { w[min(max(k + o, 0), count - 1)] += cw }
        return w
    }

    /// Gordon surface interpolating every curve of a U/V network (curves in any order and direction; each U curve must
    /// cross each V curve within `tolerance`). `span` samples per network cell.
    public static func network(u uIn: [[Vec3]], v vIn: [[Vec3]], tolerance tol: Double, span: Int = 8) -> IndexedMesh? {
        guard uIn.count >= 2, vIn.count >= 2, (uIn + vIn).allSatisfy({ $0.count >= 2 }) else { return nil }
        var u = uIn, v = vIn
        // Order the V curves along the first U curve and the U curves along the first V curve, then orient every curve
        // so the crossings run forwards.
        v.sort { closest(u[0], $0).sa < closest(u[0], $1).sa }
        u.sort { closest(v[0], $0).sa < closest(v[0], $1).sa }
        for i in u.indices where closest(u[i], v[v.count - 1]).sa < closest(u[i], v[0]).sa { u[i].reverse() }
        for j in v.indices where closest(v[j], u[u.count - 1]).sa < closest(v[j], u[0]).sa { v[j].reverse() }
        let m = u.count, n = v.count
        var P = Array(repeating: Array(repeating: Vec3.zero, count: n), count: m)
        var su = Array(repeating: Array(repeating: 0.0, count: n), count: m)   // arc length along U curve i at crossing j
        var sv = Array(repeating: Array(repeating: 0.0, count: m), count: n)   // arc length along V curve j at crossing i
        for i in 0..<m {
            for j in 0..<n {
                let c = closest(u[i], v[j])
                guard c.d <= tol else { return nil }
                P[i][j] = c.p; su[i][j] = c.sa; sv[j][i] = c.sb
            }
        }
        for i in 0..<m { guard zip(su[i], su[i].dropFirst()).allSatisfy({ $0.1 > $0.0 }) else { return nil } }
        for j in 0..<n { guard zip(sv[j], sv[j].dropFirst()).allSatisfy({ $0.1 > $0.0 }) else { return nil } }
        func uPoint(_ i: Int, _ U: Double) -> Vec3 {
            let k = min(max(Int(U.rounded(.down)), 0), n - 2), f = U - Double(k)
            return point(u[i], at: su[i][k] + (su[i][k + 1] - su[i][k]) * f)
        }
        func vPoint(_ j: Int, _ V: Double) -> Vec3 {
            let k = min(max(Int(V.rounded(.down)), 0), m - 2), f = V - Double(k)
            return point(v[j], at: sv[j][k] + (sv[j][k + 1] - sv[j][k]) * f)
        }
        let K = max(2, span)
        let nu = (n - 1) * K, nv = (m - 1) * K
        var rows: [[Vec3]] = []
        for b in 0...nv {
            let V = Double(b) / Double(K)
            let wv = weights(m, V)
            var row: [Vec3] = []
            for a in 0...nu {
                let U = Double(a) / Double(K)
                let wu = weights(n, U)
                var p = Vec3.zero
                for i in 0..<m where wv[i] != 0 { p = p + uPoint(i, U) * wv[i] }
                for j in 0..<n where wu[j] != 0 { p = p + vPoint(j, V) * wu[j] }
                for i in 0..<m where wv[i] != 0 { for j in 0..<n where wu[j] != 0 { p = p - P[i][j] * (wv[i] * wu[j]) } }
                row.append(p)
            }
            rows.append(row)
        }
        let g = SurfaceTools.grid(rows)
        return g.triangles.isEmpty ? nil : g
    }

    // MARK: Offset / extend / trim (M3D-069)

    static func welded(_ m: IndexedMesh) -> IndexedMesh {
        var tris: [Tri3] = []
        var i = 0
        while i + 2 < m.triangles.count { tris.append((m.vertices[m.triangles[i]], m.vertices[m.triangles[i + 1]], m.vertices[m.triangles[i + 2]])); i += 3 }
        return MeshTools.weld(tris, tolerance: 1e-6)
    }

    /// Offset copy of a surface along its (area-weighted) vertex normals.
    public static func offset(_ m0: IndexedMesh, distance d: Double) -> IndexedMesh? {
        let m = welded(m0)
        guard !m.triangles.isEmpty else { return nil }
        var nrm = Array(repeating: Vec3.zero, count: m.vertices.count)
        var i = 0
        while i + 2 < m.triangles.count {
            let a = m.triangles[i], b = m.triangles[i + 1], c = m.triangles[i + 2]
            let fn = (m.vertices[b] - m.vertices[a]).cross(m.vertices[c] - m.vertices[a])
            for k in [a, b, c] { nrm[k] = nrm[k] + fn }
            i += 3
        }
        return (m.vertices.indices.map { m.vertices[$0] + nrm[$0].normalized * d }, m.triangles)
    }

    /// Boundary loops of a surface (vertex index chains, following the triangle winding).
    static func boundaryLoops(_ m: IndexedMesh) -> [[Int]] {
        var directed = Set<[Int]>()
        var i = 0
        while i + 2 < m.triangles.count { for k in 0..<3 { directed.insert([m.triangles[i + k], m.triangles[i + (k + 1) % 3]]) }; i += 3 }
        var next: [Int: Int] = [:]
        for e in directed where !directed.contains([e[1], e[0]]) { next[e[0]] = e[1] }
        var loops: [[Int]] = []
        var used = Set<Int>()
        for start in next.keys.sorted() where !used.contains(start) {
            var loop: [Int] = [], cur = start
            while !used.contains(cur), let nx = next[cur] { used.insert(cur); loop.append(cur); cur = nx }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Extends the outer boundary of a surface tangentially by `distance` (a strip is added along every edge).
    public static func extend(_ m0: IndexedMesh, distance d: Double) -> IndexedMesh? {
        let m = welded(m0)
        let loops = boundaryLoops(m)
        func len(_ l: [Int]) -> Double { l.indices.reduce(0) { $0 + m.vertices[l[$1]].distance(to: m.vertices[l[($1 + 1) % l.count]]) } }
        guard d > 0, let outer = loops.max(by: { len($0) < len($1) }) else { return nil }
        // Face normal at each boundary vertex (average of incident triangles).
        var nrm = Array(repeating: Vec3.zero, count: m.vertices.count)
        var i = 0
        while i + 2 < m.triangles.count {
            let a = m.triangles[i], b = m.triangles[i + 1], c = m.triangles[i + 2]
            let fn = (m.vertices[b] - m.vertices[a]).cross(m.vertices[c] - m.vertices[a]).normalized
            for k in [a, b, c] { nrm[k] = nrm[k] + fn }
            i += 3
        }
        let n = outer.count
        var out: [Vec3] = []
        for k in 0..<n {
            let prev = outer[(k - 1 + n) % n], cur = outer[k], nx = outer[(k + 1) % n]
            let nn = nrm[cur].normalized
            // Outward (right of travel) directions of the two boundary edges at this vertex.
            let e1 = (m.vertices[cur] - m.vertices[prev]).cross(nn).normalized
            let e2 = (m.vertices[nx] - m.vertices[cur]).cross(nn).normalized
            let dir = (e1 + e2).normalized
            let cosH = max(0.3, dir.dot(e1))
            out.append(m.vertices[cur] + dir * (d / cosH))
        }
        var v = m.vertices
        let base = v.count
        v += out
        var t = m.triangles
        for k in 0..<n {
            let a = outer[k], b = outer[(k + 1) % n], a2 = base + k, b2 = base + (k + 1) % n
            // Boundary edge a→b has the surface on its left: the strip a, a2, b2, b keeps the winding.
            t += [a, a2, b2, a, b2, b]
        }
        return (v, t)
    }

    /// Trims a surface by a closed plan curve (vertical cutting prism), keeping the part inside or outside it.
    public static func trim(_ m: IndexedMesh, by loop0: [Vec2], keepInside: Bool) -> IndexedMesh? {
        var loop = RG.dedupe(loop0, closed: true)
        guard loop.count >= 3, abs(GeometryOps.signedArea(loop)) > 1e-12, !m.triangles.isEmpty else { return nil }
        if GeometryOps.signedArea(loop) < 0 { loop.reverse() }
        var b = BBox3.empty
        m.vertices.forEach { b.add($0) }
        let pad = max(1, max(b.size.x, b.size.y, b.size.z))
        let prism = ModelingCommands.extrusion(loop, z: b.min.z - pad, height: b.size.z + 2 * pad)
        let size = max(b.size.x, b.size.y, b.size.z, 1)
        let eps = size * 1e-7
        let node = CSG.Node()
        CSG.build(node, CSG.polys(MeshTools.triangles(MeshTools.mesh(of: prism))), eps: eps)
        if keepInside { CSG.invert(node) }
        var tris: [Tri3] = []
        var i = 0
        while i + 2 < m.triangles.count { tris.append((m.vertices[m.triangles[i]], m.vertices[m.triangles[i + 1]], m.vertices[m.triangles[i + 2]])); i += 3 }
        let kept = CSG.clip(CSG.polys(tris), by: node, eps: eps)
        var out: [Tri3] = []
        for p in kept where p.v.count >= 3 { for k in 1..<(p.v.count - 1) { out.append((p.v[0], p.v[k], p.v[k + 1])) } }
        guard !out.isEmpty else { return nil }
        let w = MeshTools.weld(out, tolerance: size * 1e-9)
        return w.triangles.isEmpty ? nil : w
    }

    // MARK: Sculpt (M3D-075)

    /// Makes the winding of an edge-connected mesh consistent (flood fill); nil when it is not orientable or an edge
    /// has more than two triangles.
    static func orient(_ t0: [Int]) -> [Int]? {
        var t = t0
        let nt = t.count / 3
        var edgeTris: [[Int]: [Int]] = [:]
        for k in 0..<nt { for j in 0..<3 { let a = t[3 * k + j], b = t[3 * k + (j + 1) % 3]; edgeTris[[min(a, b), max(a, b)], default: []].append(k) } }
        guard edgeTris.values.allSatisfy({ $0.count <= 2 }) else { return nil }
        var done = Array(repeating: false, count: nt)
        func hasDirected(_ k: Int, _ a: Int, _ b: Int) -> Bool { (0..<3).contains { t[3 * k + $0] == a && t[3 * k + ($0 + 1) % 3] == b } }
        for seed in 0..<nt where !done[seed] {
            done[seed] = true
            var stack = [seed]
            while let k = stack.popLast() {
                for j in 0..<3 {
                    let a = t[3 * k + j], b = t[3 * k + (j + 1) % 3]
                    for o in edgeTris[[min(a, b), max(a, b)]] ?? [] where o != k {
                        // Consistent neighbours traverse the shared edge in opposite directions.
                        let clash = hasDirected(o, a, b)
                        if done[o] { if clash { return nil }; continue }
                        if clash { t.swapAt(3 * o + 1, 3 * o + 2) }
                        done[o] = true; stack.append(o)
                    }
                }
            }
        }
        return t
    }

    /// Joins surfaces that together enclose a volume into one closed, outward-oriented solid; nil when they leave gaps.
    public static func sculpt(_ parts: [IndexedMesh], tolerance tol: Double) -> SolidGeom? {
        var tris: [Tri3] = []
        for m in parts { var i = 0; while i + 2 < m.triangles.count { tris.append((m.vertices[m.triangles[i]], m.vertices[m.triangles[i + 1]], m.vertices[m.triangles[i + 2]])); i += 3 } }
        let w = MeshTools.weld(tris, tolerance: tol)
        guard let t = orient(w.triangles), SolidOps.isClosedManifold(vertices: w.vertices, triangles: t) else { return nil }
        var tt = t
        if SolidOps.volume(vertices: w.vertices, triangles: t) < 0 { var i = 0; while i + 2 < tt.count { tt.swapAt(i + 1, i + 2); i += 3 } }
        var b = BBox3.empty
        w.vertices.forEach { b.add($0) }
        return SolidGeom(kind: .mesh, origin: b.min, meshVertices: w.vertices, meshTriangles: tt)
    }

    public static func area(_ m: IndexedMesh) -> Double { SurfaceTools.area(m) }
}

// MARK: - Commands

enum SurfaceCommands9 {
    static var all: [CommandDef] { [patch, network, sculpt, offset, extend, trim] }

    @MainActor static func curves(_ ed: Editor, _ msg: String) async throws -> [(EntityID, [Vec3], Bool)] {
        let ids = try await ed.getEntitySelection(msg)
        ed.selection = []
        return ids.compactMap { id in FeatureSources.path3(ed.doc, id).map { (id, $0.closed ? $0.points + [$0.points[0]] : $0.points, $0.closed) } }
    }

    @MainActor static func surfaces(_ ed: Editor, _ msg: String) async throws -> [(EntityID, SurfaceNetwork.IndexedMesh)] {
        let ids = try await ModelingCommands.selectSolids(ed, msg)
        ed.selection = []
        return ids.compactMap { id in
            guard let s = ModelingCommands.solidOf(ed.doc, id) else { return nil }
            let w = SolidOps.welded(s)
            return (id, (w.vertices, w.triangles))
        }
    }

    @MainActor static func tol(_ ed: Editor) -> Double { max(1e-3, 0.5 / ed.doc.units.mm) }

    static var patch: CommandDef {
        CommandDef("SURFPATCH", aliases: ["PATCHSURFACE", "FILLSURFACE"], category: "3D", summary: "Patch surface filling a closed boundary (one closed curve or curves meeting end to end; 3D polylines with vertexZ or elevations): planar boundaries exactly, others as a Coons patch.") { ed in
            let cs = try await curves(ed, "Select boundary curves")
            guard !cs.isEmpty else { return }
            let n = Int(ed.variableDouble("SURFTAB1", 16))
            guard let r = SurfaceNetwork.patch(cs.map(\.1), tolerance: tol(ed), divisions: max(2, n)) else { throw CommandError.invalid("The boundary must be closed (curves meeting end to end).") }
            try SurfaceCommands.addSurface(ed, r, what: "Patch surface")
        }
    }

    static var network: CommandDef {
        CommandDef("SURFNETWORK", aliases: ["NETWORKSURFACE", "GORDON"], category: "3D", summary: "Network surface through curves in the U and V directions (Gordon surface: passes through every curve).") { ed in
            let u = try await curves(ed, "Select curves in the first direction (U)")
            let v = try await curves(ed, "Select curves in the second direction (V)").filter { c in !u.contains { $0.0 == c.0 } }
            guard u.count >= 2, v.count >= 2 else { throw CommandError.invalid("Select at least two curves in each direction.") }
            let k = Int(ed.variableDouble("SURFTAB1", 8))
            guard let r = SurfaceNetwork.network(u: u.map(\.1), v: v.map(\.1), tolerance: tol(ed) * 10, span: max(2, k)) else {
                throw CommandError.invalid("Every U curve must cross every V curve once.")
            }
            try SurfaceCommands.addSurface(ed, r, what: "Network surface")
        }
    }

    static var sculpt: CommandDef {
        CommandDef("SURFSCULPT", aliases: ["SCULPT", "SURFTOSOLID"], category: "3D", summary: "Joins surfaces that enclose a watertight volume into a solid (the surfaces are replaced).") { ed in
            let parts = try await surfaces(ed, "Select surfaces that enclose a volume")
            guard parts.count >= 1 else { return }
            guard let s = SurfaceNetwork.sculpt(parts.map(\.1), tolerance: tol(ed)) else { throw CommandError.invalid("The surfaces do not enclose a watertight volume (gaps or overlaps).") }
            let first = ed.doc.entity(parts[0].0)
            ed.doc.remove(ids: Set(parts.map(\.0)))
            var e = first ?? Entity(layer: ed.doc.currentLayer, geometry: .solid(s))
            e.id = 0; e.geometry = .solid(s); e.props["surface"] = nil
            ed.doc.add(e)
            ed.print("Solid created: volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        }
    }

    static var offset: CommandDef {
        CommandDef("SURFOFFSET", aliases: ["OFFSETSURFACE"], category: "3D", summary: "Offset copy of surfaces along their normals.") { ed in
            let parts = try await surfaces(ed, "Select surfaces to offset")
            guard !parts.isEmpty else { return }
            let d = try await ed.getDistance("Specify offset distance", defaultValue: ed.variableDouble("SURFOFFSETDIST", 100)).value ?? 100
            ed.doc.setVariable("SURFOFFSETDIST", fmt(d))
            for (_, m) in parts { if let r = SurfaceNetwork.offset(m, distance: d) { try SurfaceCommands.addSurface(ed, r, what: "Offset surface") } }
        }
    }

    static var extend: CommandDef {
        CommandDef("SURFEXTEND", aliases: ["EXTENDSURFACE"], category: "3D", summary: "Extends the outer edges of surfaces tangentially by a distance.") { ed in
            let parts = try await surfaces(ed, "Select surfaces to extend")
            guard !parts.isEmpty else { return }
            let d = try await ed.getPositive("Specify extension distance", defaultValue: 100)
            for (id, m) in parts {
                guard let r = SurfaceNetwork.extend(m, distance: d) else { ed.print("#\(id) has no open edge to extend."); continue }
                var b = BBox3.empty; r.vertices.forEach { b.add($0) }
                ModelingCommands.replace(ed, id, with: SolidGeom(kind: .mesh, origin: b.min, meshVertices: r.vertices, meshTriangles: r.triangles))
            }
            ed.print("\(parts.count) surface(s) extended by \(fmt(d)).")
        }
    }

    static var trim: CommandDef {
        CommandDef("SURFTRIM", aliases: ["TRIMSURFACE"], category: "3D", summary: "Trims surfaces with a closed plan curve (projected vertically), keeping the part Inside or Outside.") { ed in
            let parts = try await surfaces(ed, "Select surfaces to trim")
            guard !parts.isEmpty else { return }
            guard case .pick(let pk) = try await ed.pickObject("Select closed cutting curve", filter: { ModelingCommands.loop(ed.doc, $0) != nil }), let loop = ModelingCommands.loop(ed.doc, pk.id) else { return }
            let keep = try await ed.getKeyword("Keep the part [Inside/Outside]", ["Inside", "Outside"], defaultValue: "Outside") ?? "Outside"
            var n = 0
            for (id, m) in parts {
                guard let r = SurfaceNetwork.trim(m, by: loop, keepInside: keep == "Inside") else { ed.print("#\(id): nothing is left."); continue }
                var b = BBox3.empty; r.vertices.forEach { b.add($0) }
                ModelingCommands.replace(ed, id, with: SolidGeom(kind: .mesh, origin: b.min, meshVertices: r.vertices, meshTriangles: r.triangles))
                n += 1
            }
            ed.print("\(n) surface(s) trimmed.")
        }
    }
}
