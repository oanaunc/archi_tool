// Oanarina Archi Tool — GPL-3.0-or-later
// Sub-object editing of solids: picking faces, edges and vertices and moving / extruding them (M3D-052), imprinting
// curves onto a face (M3D-040) and SketchUp-style offset of a face's edges (M3D-107). Imprinting splits the face's
// triangles (and the neighbours that share a split edge), so the solid stays a closed 2-manifold; the imprinted edges
// are stored with the solid (props "imprint") so they are drawn in 3D and bound face regions for later edits.
import Foundation

public enum SubObjects {
    public typealias IM = (vertices: [Vec3], triangles: [Int])
    public enum Kind: String, CaseIterable { case face, edge, vertex }
    public static let imprintKey = "imprint"

    // MARK: Basic queries

    static func corners(_ m: IM, _ f: Int) -> (Vec3, Vec3, Vec3) {
        (m.vertices[m.triangles[3 * f]], m.vertices[m.triangles[3 * f + 1]], m.vertices[m.triangles[3 * f + 2]])
    }
    public static func normal(_ m: IM, _ f: Int) -> Vec3 {
        let (a, b, c) = corners(m, f)
        return (b - a).cross(c - a).normalized
    }

    static func segmentDistance(_ p: Vec3, _ a: Vec3, _ b: Vec3) -> Double {
        let d = b - a, l2 = d.dot(d)
        guard l2 > 1e-24 else { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(d) / l2))
        return p.distance(to: a + d * t)
    }

    /// Distance from a point to a triangle.
    static func triangleDistance(_ p: Vec3, _ a: Vec3, _ b: Vec3, _ c: Vec3) -> Double {
        let n = (b - a).cross(c - a)
        let nl = n.length
        guard nl > 1e-18 else { return min(segmentDistance(p, a, b), segmentDistance(p, b, c), segmentDistance(p, c, a)) }
        let nn = n / nl
        let dist = (p - a).dot(nn)
        let q = p - nn * dist
        // Inside test: q on the inner side of every edge.
        let inside = (b - a).cross(q - a).dot(n) >= 0 && (c - b).cross(q - b).dot(n) >= 0 && (a - c).cross(q - c).dot(n) >= 0
        if inside { return abs(dist) }
        return min(segmentDistance(p, a, b), segmentDistance(p, b, c), segmentDistance(p, c, a))
    }

    /// Triangle nearest to a point.
    public static func nearestFace(_ m: IM, to p: Vec3) -> Int? {
        var best: (Int, Double)? = nil
        for f in 0..<(m.triangles.count / 3) {
            let (a, b, c) = corners(m, f)
            let d = triangleDistance(p, a, b, c)
            if best == nil || d < best!.1 - 1e-9 { best = (f, d) }
        }
        return best?.0
    }

    /// Sharp (feature) edge nearest to a point, as welded vertex indices.
    public static func nearestEdge(_ m: IM, to p: Vec3, angle: Double = 1) -> (Int, Int)? {
        let faces = edgeFaces(m)
        let cosA = cos(angle * .pi / 180)
        var best: ((Int, Int), Double)? = nil
        for (k, fs) in faces {
            let a = Int(k >> 32), b = Int(k & 0xffff_ffff)
            // Boundary edges and edges between faces that are not coplanar.
            if fs.count == 2, normal(m, fs[0]).dot(normal(m, fs[1])) > cosA { continue }
            let d = segmentDistance(p, m.vertices[a], m.vertices[b])
            if best == nil || d < best!.1 - 1e-9 { best = ((a, b), d) }
        }
        return best?.0
    }

    /// Vertex nearest to a point.
    public static func nearestVertex(_ m: IM, to p: Vec3) -> Int? {
        let used = Set(m.triangles)
        return used.min { m.vertices[$0].distance(to: p) < m.vertices[$1].distance(to: p) }
    }

    static func key(_ a: Int, _ b: Int) -> Int64 { Int64(min(a, b)) << 32 | Int64(max(a, b)) }

    static func edgeFaces(_ m: IM) -> [Int64: [Int]] {
        var out: [Int64: [Int]] = [:]
        for f in 0..<(m.triangles.count / 3) {
            for k in 0..<3 { out[key(m.triangles[3 * f + k], m.triangles[3 * f + (k + 1) % 3]), default: []].append(f) }
        }
        return out
    }

    /// Connected coplanar triangles around `seed` (one planar face of the solid), not crossing imprinted edges.
    public static func faceRegion(_ m: IM, seed: Int, barriers: [(Vec3, Vec3)] = [], tolerance tol: Double = 1e-6) -> Set<Int> {
        guard seed >= 0, seed < m.triangles.count / 3 else { return [] }
        let n0 = normal(m, seed), p0 = m.vertices[m.triangles[3 * seed]]
        let adj = edgeFaces(m)
        func blocked(_ a: Int, _ b: Int) -> Bool {
            let pa = m.vertices[a], pb = m.vertices[b]
            return barriers.contains { segmentDistance(pa, $0.0, $0.1) <= tol && segmentDistance(pb, $0.0, $0.1) <= tol }
        }
        var out: Set<Int> = [seed], stack = [seed]
        while let f = stack.popLast() {
            for k in 0..<3 {
                let a = m.triangles[3 * f + k], b = m.triangles[3 * f + (k + 1) % 3]
                for g in adj[key(a, b)] ?? [] where !out.contains(g) {
                    let ng = normal(m, g)
                    guard ng.dot(n0) > 1 - 1e-9, abs((m.vertices[m.triangles[3 * g]] - p0).dot(n0)) <= tol, !blocked(a, b) else { continue }
                    out.insert(g); stack.append(g)
                }
            }
        }
        return out
    }

    /// Boundary loops of a set of triangles (directed so the region lies on their left, seen along the face normal).
    public static func boundaryLoops(_ m: IM, faces: Set<Int>) -> [[Int]] {
        var directed = Set<Int64>()
        for f in faces { for k in 0..<3 { directed.insert(Int64(m.triangles[3 * f + k]) << 32 | Int64(m.triangles[3 * f + (k + 1) % 3])) } }
        var next: [Int: Int] = [:]
        for e in directed {
            let a = Int(e >> 32), b = Int(e & 0xffff_ffff)
            if !directed.contains(Int64(b) << 32 | Int64(a)) { next[a] = b }
        }
        var loops: [[Int]] = []
        var seen = Set<Int>()
        for start in next.keys.sorted() where !seen.contains(start) {
            var loop: [Int] = [], cur = start
            while !seen.contains(cur), let n = next[cur] { seen.insert(cur); loop.append(cur); cur = n }
            if loop.count >= 3 && cur == start { loops.append(loop) }
        }
        return loops
    }

    // MARK: Imprint

    /// Mutable indexed mesh with triangle splitting that keeps the mesh conforming (no T-junctions).
    struct Splitter {
        var v: [Vec3]
        var t: [Int]
        var inRegion: [Bool]
        init(_ m: IM, region: Set<Int>) {
            v = m.vertices; t = m.triangles
            inRegion = (0..<(m.triangles.count / 3)).map { region.contains($0) }
        }
        var faceCount: Int { t.count / 3 }

        /// Splits edge a–b at p in every triangle that uses it.
        mutating func splitEdge(_ a: Int, _ b: Int, at p: Vec3) {
            let k = v.count
            v.append(p)
            for f in 0..<faceCount {
                for j in 0..<3 {
                    let x = t[3 * f + j], y = t[3 * f + (j + 1) % 3], z = t[3 * f + (j + 2) % 3]
                    guard (x == a && y == b) || (x == b && y == a) else { continue }
                    t[3 * f] = x; t[3 * f + 1] = k; t[3 * f + 2] = z
                    t += [k, y, z]; inRegion.append(inRegion[f])
                    break
                }
            }
        }

        mutating func splitTriangle(_ f: Int, at p: Vec3) {
            let k = v.count
            v.append(p)
            let a = t[3 * f], b = t[3 * f + 1], c = t[3 * f + 2]
            t[3 * f + 2] = k
            t += [b, c, k, c, a, k]
            inRegion += [inRegion[f], inRegion[f]]
        }
    }

    /// Imprints segments (projected onto the plane of the region along its normal) onto a planar face region.
    /// Returns the new mesh and the imprinted mesh edges; nil when nothing crosses the face.
    public static func imprint(_ m: IM, region: Set<Int>, segments: [(Vec3, Vec3)], tolerance tol0: Double? = nil) -> (mesh: IM, edges: [(Vec3, Vec3)])? {
        guard let seed = region.min() else { return nil }
        var bb = BBox3.empty
        m.vertices.forEach { bb.add($0) }
        let size = bb.isEmpty ? 1 : max(bb.size.x, bb.size.y, bb.size.z, 1e-9)
        let tol = tol0 ?? size * 1e-7
        let n = normal(m, seed), p0 = m.vertices[m.triangles[3 * seed]]
        let (u, w) = Mesh.basis(n)
        func uv(_ p: Vec3) -> Vec2 { Vec2((p - p0).dot(u), (p - p0).dot(w)) }
        func onPlane(_ p: Vec3) -> Vec3 { p - n * (p - p0).dot(n) }
        var sp = Splitter(m, region: region)
        var imprinted: [(Vec3, Vec3)] = []

        for s in segments {
            let A = onPlane(s.0), B = onPlane(s.1)
            guard A.distance(to: B) > tol else { continue }
            let a2 = uv(A), b2 = uv(B)
            // 1. Endpoints inside the face become vertices.
            for P in [A, B] {
                let p2 = uv(P)
                var done = false
                for f in 0..<sp.faceCount where sp.inRegion[f] && !done {
                    let ids = [sp.t[3 * f], sp.t[3 * f + 1], sp.t[3 * f + 2]]
                    if ids.contains(where: { sp.v[$0].distance(to: P) <= tol }) { done = true; break }
                    let q = ids.map { uv(sp.v[$0]) }
                    // Point on an edge?
                    for j in 0..<3 where !done {
                        let e0 = sp.v[ids[j]], e1 = sp.v[ids[(j + 1) % 3]]
                        if segmentDistance(P, e0, e1) <= tol { sp.splitEdge(ids[j], ids[(j + 1) % 3], at: P); done = true }
                    }
                    if done { break }
                    let area = (q[1] - q[0]).cross(q[2] - q[0])
                    guard abs(area) > 1e-18 else { continue }
                    let l0 = (q[1] - p2).cross(q[2] - p2) / area, l1 = (q[2] - p2).cross(q[0] - p2) / area, l2 = 1 - l0 - l1
                    if l0 > 0, l1 > 0, l2 > 0 { sp.splitTriangle(f, at: P); done = true }
                }
            }
            // 2. Split every face edge the segment crosses until none is left.
            var guardN = 0
            var found = true
            while found && guardN < 20000 {
                found = false; guardN += 1
                outer: for f in 0..<sp.faceCount where sp.inRegion[f] {
                    for j in 0..<3 {
                        let ia = sp.t[3 * f + j], ib = sp.t[3 * f + (j + 1) % 3]
                        let e0 = uv(sp.v[ia]), e1 = uv(sp.v[ib])
                        let de = e1 - e0, ds = b2 - a2
                        let den = de.cross(ds)
                        guard abs(den) > 1e-12 * max(1, de.length * ds.length) else { continue }
                        let te = (a2 - e0).cross(ds) / den, ts = (a2 - e0).cross(de) / den
                        guard te > 0, te < 1, ts >= -1e-9, ts <= 1 + 1e-9 else { continue }
                        let P = sp.v[ia] + (sp.v[ib] - sp.v[ia]) * te
                        guard P.distance(to: sp.v[ia]) > tol, P.distance(to: sp.v[ib]) > tol else { continue }
                        sp.splitEdge(ia, ib, at: P)
                        found = true
                        break outer
                    }
                }
            }
            // 3. Mesh edges of the face lying on the segment are the imprint.
            var seen = Set<Int64>()
            for f in 0..<sp.faceCount where sp.inRegion[f] {
                for j in 0..<3 {
                    let ia = sp.t[3 * f + j], ib = sp.t[3 * f + (j + 1) % 3]
                    guard seen.insert(key(ia, ib)).inserted else { continue }
                    if segmentDistance(sp.v[ia], A, B) <= tol, segmentDistance(sp.v[ib], A, B) <= tol, sp.v[ia].distance(to: sp.v[ib]) > tol {
                        imprinted.append((sp.v[ia], sp.v[ib]))
                    }
                }
            }
        }
        guard !imprinted.isEmpty else { return nil }
        return ((sp.v, sp.t), imprinted)
    }

    // MARK: Offset face edges

    /// Loops of a face's edges offset into the face by `distance` (holes grow away from the hole). nil when the offset
    /// collapses the face.
    public static func offsetLoops(_ m: IM, region: Set<Int>, distance d: Double) -> [[Vec3]]? {
        guard let seed = region.min(), d > 0 else { return nil }
        let n = normal(m, seed), p0 = m.vertices[m.triangles[3 * seed]]
        let (u, w) = Mesh.basis(n)
        func uv(_ p: Vec3) -> Vec2 { Vec2((p - p0).dot(u), (p - p0).dot(w)) }
        func world(_ q: Vec2) -> Vec3 { p0 + u * q.x + w * q.y }
        let loops = boundaryLoops(m, faces: region).map { l -> [Vec2] in simplify(l.map { uv(m.vertices[$0]) }) }.filter { $0.count >= 3 }
        guard !loops.isEmpty else { return nil }
        var out: [[Vec2]] = []
        for l in loops {
            guard let o = offsetLeft(l, d) else { return nil }
            // Orientation must survive (a flipped loop means the face collapsed).
            guard GeometryOps.signedArea(o) * GeometryOps.signedArea(l) > 0 else { return nil }
            // Every edge must keep its direction (an offset past the medial axis reverses edges).
            for i in 0..<l.count {
                let e0 = l[(i + 1) % l.count] - l[i], e1 = o[(i + 1) % o.count] - o[i]
                guard e0.dot(e1) > 1e-9 * e0.lengthSquared else { return nil }
            }
            out.append(o)
        }
        // Every offset vertex must still lie on the face.
        let outerLoops = loops.filter { GeometryOps.signedArea($0) > 0 }, holes = loops.filter { GeometryOps.signedArea($0) < 0 }
        for o in out {
            for q in o {
                guard outerLoops.contains(where: { GeometryOps.pointInPolygon(q, $0) }), !holes.contains(where: { GeometryOps.pointInPolygon(q, $0) }) else { return nil }
            }
        }
        return out.map { $0.map(world) }
    }

    /// Drops collinear and duplicate vertices of a closed loop.
    static func simplify(_ p: [Vec2]) -> [Vec2] {
        var q = p
        var changed = true
        while changed && q.count > 3 {
            changed = false
            for i in 0..<q.count {
                let a = q[(i - 1 + q.count) % q.count], b = q[i], c = q[(i + 1) % q.count]
                let scale = max((c - a).length, 1e-12)
                if a.distance(to: b) < 1e-9 * scale || abs((b - a).cross(c - b)) < 1e-9 * scale * scale { q.remove(at: i); changed = true; break }
            }
        }
        return q
    }

    /// Mitred offset of a closed loop to the left of its direction.
    static func offsetLeft(_ p: [Vec2], _ d: Double) -> [Vec2]? {
        let n = p.count
        guard n >= 3 else { return nil }
        var out: [Vec2] = []
        for i in 0..<n {
            let a = p[(i - 1 + n) % n], b = p[i], c = p[(i + 1) % n]
            let d0 = (b - a).normalized, d1 = (c - b).normalized
            let l0 = d0.perp * d, l1 = d1.perp * d
            let den = d0.cross(d1)
            if abs(den) < 1e-12 { out.append(b + l0); continue }
            // Intersection of the two offset lines.
            let s = ((b + l1) - (a + l0)).cross(d1) / den
            out.append(a + l0 + d0 * s)
        }
        return out
    }

    // MARK: Moving sub-objects

    /// Moves the given vertices; nil when the result is degenerate or no longer a closed manifold with positive volume.
    public static func moved(_ m: IM, vertices ids: Set<Int>, by delta: Vec3) -> IM? {
        var v = m.vertices
        for i in ids where i >= 0 && i < v.count { v[i] = v[i] + delta }
        let r: IM = (v, m.triangles)
        for f in 0..<(m.triangles.count / 3) {
            let (a, b, c) = corners(r, f)
            if (b - a).cross(c - a).length < 1e-12 { return nil }
        }
        guard SolidOps.isClosedManifold(vertices: v, triangles: m.triangles), SolidOps.volume(vertices: v, triangles: m.triangles) > 0 else { return nil }
        return r
    }

    /// Vertices of a sub-object.
    public static func vertices(of kind: Kind, near p: Vec3, in m: IM, barriers: [(Vec3, Vec3)] = []) -> Set<Int> {
        switch kind {
        case .vertex: return nearestVertex(m, to: p).map { [$0] } ?? []
        case .edge: return nearestEdge(m, to: p).map { [$0.0, $0.1] } ?? []
        case .face:
            guard let f = nearestFace(m, to: p) else { return [] }
            return Set(faceRegion(m, seed: f, barriers: barriers).flatMap { [m.triangles[3 * $0], m.triangles[3 * $0 + 1], m.triangles[3 * $0 + 2]] })
        }
    }

    // MARK: Persistence of imprinted edges

    public static func encode(_ segs: [(Vec3, Vec3)]) -> String {
        segs.map { "\(fmt($0.0.x, 6)),\(fmt($0.0.y, 6)),\(fmt($0.0.z, 6)) \(fmt($0.1.x, 6)),\(fmt($0.1.y, 6)),\(fmt($0.1.z, 6))" }.joined(separator: ";")
    }
    public static func decode(_ s: String?) -> [(Vec3, Vec3)] {
        guard let s = s, !s.isEmpty else { return [] }
        return s.split(separator: ";").compactMap { part in
            let pts = part.split(separator: " ").map { $0.split(separator: ",").compactMap { Double($0) } }
            guard pts.count == 2, pts[0].count == 3, pts[1].count == 3 else { return nil }
            return (Vec3(pts[0][0], pts[0][1], pts[0][2]), Vec3(pts[1][0], pts[1][1], pts[1][2]))
        }
    }

    /// Welded mesh of a solid entity with its imprinted edges.
    public static func mesh(_ e: Entity) -> (IM, [(Vec3, Vec3)])? {
        guard case .solid(let s) = e.geometry else { return nil }
        let w = SolidOps.welded(s)
        guard !w.triangles.isEmpty else { return nil }
        return ((w.vertices, w.triangles), decode(e.props[imprintKey]))
    }

    static func solidGeom(_ m: IM) -> SolidGeom {
        var b = BBox3.empty
        m.vertices.forEach { b.add($0) }
        return SolidGeom(kind: .mesh, origin: b.isEmpty ? .zero : b.min, meshVertices: m.vertices, meshTriangles: m.triangles)
    }

    /// Segments of a curve entity (3D polylines keep their vertex heights).
    static func segments(_ doc: ArchiDocument, _ id: EntityID) -> [(Vec3, Vec3)] {
        guard let p = FeatureSources.path3(doc, id) else { return [] }
        var pts = p.points
        if p.closed, let f = pts.first { pts.append(f) }
        guard pts.count >= 2 else { return [] }
        return (0..<(pts.count - 1)).map { (pts[$0], pts[$0 + 1]) }.filter { $0.0.distance(to: $0.1) > 1e-9 }
    }
}

// MARK: - Commands

enum SubObjectCommands {
    static var all: [CommandDef] { [imprint, offsetFace, subObject] }

    @MainActor static func pickSolid(_ ed: Editor, _ msg: String) async throws -> EntityID? {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { ModelingCommands.solidOf(ed.doc, $0) != nil }) else { return nil }
        return pk.id
    }

    /// Replaces the solid's geometry with an edited mesh (it stops being parametric) and stores the imprints.
    @MainActor static func store(_ ed: Editor, _ id: EntityID, _ m: SubObjects.IM, imprints: [(Vec3, Vec3)]) {
        guard let i = ed.doc.entityIndex(id) else { return }
        ed.doc.entities[i].geometry = .solid(SubObjects.solidGeom(m))
        ed.doc.entities[i].props[SubObjects.imprintKey] = imprints.isEmpty ? nil : SubObjects.encode(imprints)
    }

    static var imprint: CommandDef {
        CommandDef("IMPRINT", aliases: ["IMPRINTEDGES"], category: "3D", summary: "Imprints curves (lines, polylines, arcs, circles, 3D polylines) onto a planar face of a solid: the face is split along them, the solid stays closed.") { ed in
            guard let sid = try await pickSolid(ed, "Select a 3D solid") , let e = ed.doc.entity(sid), let (m, old) = SubObjects.mesh(e) else { return }
            let p = try await ed.requirePoint3("Specify a point on the face to imprint")
            guard let f = SubObjects.nearestFace(m, to: p) else { return }
            let region = SubObjects.faceRegion(m, seed: f, barriers: old)
            ed.selection = []
            let ids = try await ed.getEntitySelection("Select objects to imprint").filter { $0 != sid }
            let segs = ids.flatMap { SubObjects.segments(ed.doc, $0) }
            guard !segs.isEmpty else { throw CommandError.invalid("Select lines, arcs, circles or polylines.") }
            guard let r = SubObjects.imprint(m, region: region, segments: segs) else { throw CommandError.invalid("The objects do not cross the face.") }
            let del = try await ed.getYesNo("Delete the source objects?", defaultValue: false)
            store(ed, sid, r.mesh, imprints: old + r.edges)
            if del { ed.doc.remove(ids: Set(ids)) }
            ed.selection = [sid]
            ed.print("\(r.edges.count) edge(s) imprinted; the solid has \(r.mesh.triangles.count / 3) faces" + (SolidOps.isClosedManifold(vertices: r.mesh.vertices, triangles: r.mesh.triangles) ? " and is a closed manifold." : "."))
        }
    }

    static var offsetFace: CommandDef {
        CommandDef("OFFSETFACE", aliases: ["OFFSETEDGES", "FACEOFFSET", "INSETFACE"], category: "3D", summary: "SketchUp-style Offset: imprints a copy of a planar face's edges offset into the face (then SUBOBJECT Extrude pushes or pulls the inner face).") { ed in
            guard let sid = try await pickSolid(ed, "Select a 3D solid"), let e = ed.doc.entity(sid), let (m, old) = SubObjects.mesh(e) else { return }
            let p = try await ed.requirePoint3("Specify a point on the face")
            guard let f = SubObjects.nearestFace(m, to: p) else { return }
            let region = SubObjects.faceRegion(m, seed: f, barriers: old)
            let d = try await ed.getPositive("Specify offset distance", defaultValue: ed.variableDouble("OFFSETFACEDIST", 100))
            guard let loops = SubObjects.offsetLoops(m, region: region, distance: d) else { throw CommandError.invalid("The offset is too large for the face.") }
            var segs: [(Vec3, Vec3)] = []
            for l in loops { for i in 0..<l.count { segs.append((l[i], l[(i + 1) % l.count])) } }
            guard let r = SubObjects.imprint(m, region: region, segments: segs) else { throw CommandError.invalid("The offset could not be imprinted.") }
            ed.doc.setVariable("OFFSETFACEDIST", fmt(d))
            store(ed, sid, r.mesh, imprints: old + r.edges)
            ed.selection = [sid]
            ed.print("Face edges offset by \(fmt(d)): \(loops.count) loop(s) imprinted.")
        }
    }

    static var subObject: CommandDef {
        CommandDef("SUBOBJECT", aliases: ["SUBSELECT", "SOEDIT", "SUBOBJ"], category: "3D", summary: "Sub-object editing (Ctrl-click in the viewport): pick a Face, Edge or Vertex of a solid and Move it, Extrude a face, or list Info.") { ed in
            guard let sid = try await pickSolid(ed, "Select a 3D solid"), let e = ed.doc.entity(sid), let (m, old) = SubObjects.mesh(e) else { return }
            let k = try await ed.getKeyword("Sub-object [Face/Edge/Vertex]", ["Face", "Edge", "Vertex"], defaultValue: ed.doc.variable("SUBOBJECTMODE") ?? "Face") ?? "Face"
            ed.doc.setVariable("SUBOBJECTMODE", k)
            let kind = SubObjects.Kind(rawValue: k.lowercased()) ?? .face
            let p = try await ed.requirePoint3("Specify a point on the \(k.lowercased())")
            let vs = SubObjects.vertices(of: kind, near: p, in: m, barriers: old)
            guard !vs.isEmpty else { throw CommandError.invalid("Nothing found there.") }
            let actions = kind == .face ? ["Move", "Extrude", "Info"] : ["Move", "Info"]
            let a = try await ed.getKeyword("Action [" + actions.joined(separator: "/") + "]", actions, defaultValue: "Move") ?? "Move"
            switch a {
            case "Info":
                var b = BBox3.empty
                vs.forEach { b.add(m.vertices[$0]) }
                if kind == .face, let f = SubObjects.nearestFace(m, to: p) {
                    let region = SubObjects.faceRegion(m, seed: f, barriers: old)
                    let area = region.reduce(0.0) { acc, g in let (x, y, z) = SubObjects.corners(m, g); return acc + (y - x).cross(z - x).length / 2 }
                    let n = SubObjects.normal(m, f)
                    ed.print("Face: \(region.count) triangle(s), \(vs.count) vertices, area \(fmt(area)), normal \(fmt(n.x, 3)),\(fmt(n.y, 3)),\(fmt(n.z, 3)).")
                } else if kind == .edge, vs.count == 2 {
                    let arr = Array(vs)
                    ed.print("Edge: \(m.vertices[arr[0]]) to \(m.vertices[arr[1]]), length \(fmt(m.vertices[arr[0]].distance(to: m.vertices[arr[1]]))).")
                } else if let v = vs.first { ed.print("Vertex: \(m.vertices[v]).") }
                ed.selection = [sid]
            case "Extrude":
                guard let f = SubObjects.nearestFace(m, to: p) else { return }
                let region = SubObjects.faceRegion(m, seed: f, barriers: old)
                let d = try await ed.getDistance("Specify extrusion distance (negative pushes in)", defaultValue: 100).value ?? 0
                guard abs(d) > 1e-12, let s = MeshOps.extrudeFaces(SubObjects.solidGeom(m), faces: region, distance: d) else { throw CommandError.invalid("Nothing to extrude.") }
                let w = SolidOps.welded(s)
                store(ed, sid, (w.vertices, w.triangles), imprints: old)
                ed.selection = [sid]
                ed.print("Face extruded by \(fmt(d)); volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
            default:
                let base = try await ed.requirePoint3("Specify base point", defaultZ: p.z)
                let to = try await ed.requirePoint3("Specify second point", base: base, defaultZ: base.z)
                let delta = to - base
                guard delta.length > 1e-12 else { return }
                guard let r = SubObjects.moved(m, vertices: vs, by: delta) else { throw CommandError.invalid("The move would make the solid invalid (self-folding or inside out).") }
                // Imprinted edges on moved vertices follow them.
                let movedPts = vs.map { m.vertices[$0] }
                let tol = 1e-6 * max(1, delta.length)
                let imps = old.map { s -> (Vec3, Vec3) in
                    let a = movedPts.contains { $0.distance(to: s.0) <= tol } ? s.0 + delta : s.0
                    let b = movedPts.contains { $0.distance(to: s.1) <= tol } ? s.1 + delta : s.1
                    return (a, b)
                }
                store(ed, sid, r, imprints: imps)
                ed.selection = [sid]
                ed.print("\(k) moved by \(delta); volume " + ModelingCommands.volumeText(SolidOps.volume(vertices: r.vertices, triangles: r.triangles), units: ed.doc.units) + ".")
            }
        }
    }
}
