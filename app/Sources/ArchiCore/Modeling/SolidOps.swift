// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Solid editing on prismatic solids and triangle meshes: 3D edge fillets and chamfers, shells,
/// Loop subdivision smoothing, 3D mirror/rotate/array transforms and manifold checks.
public enum SolidOps {
    public struct EdgeSet: OptionSet, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let vertical = EdgeSet(rawValue: 1)
        public static let top = EdgeSet(rawValue: 2)
        public static let bottom = EdgeSet(rawValue: 4)
        public static let all: EdgeSet = [.vertical, .top, .bottom]
    }

    public enum OpError: Error, Equatable, CustomStringConvertible {
        case unsupported, radiusTooLarge, invalidProfile, tooLarge
        public var description: String {
            switch self {
            case .unsupported: return "Only boxes, extrusions and mesh solids can be edited this way."
            case .radiusTooLarge: return "The radius or distance is too large for this solid."
            case .invalidProfile: return "The solid's profile is degenerate or self-intersecting."
            case .tooLarge: return "The result would have too many triangles."
            }
        }
    }

    // MARK: Prism description of a solid

    /// Plan profile (CCW, world coordinates) and Z range of a box or extrusion.
    public static func prism(of s: SolidGeom) -> (profile: [Vec2], z0: Double, z1: Double)? {
        let rot = Transform2D.translation(s.origin.xy) * Transform2D.rotation(s.rotation)
        var prof: [Vec2]
        var za: Double, zb: Double
        switch s.kind {
        case .box:
            prof = [Vec2(0, 0), Vec2(s.size.x, 0), Vec2(s.size.x, s.size.y), Vec2(0, s.size.y)].map(rot.apply)
            za = s.origin.z; zb = s.origin.z + s.size.z
        case .extrusion:
            prof = s.profile.map(rot.apply)
            za = s.origin.z; zb = s.origin.z + s.height
        default: return nil
        }
        prof = RG.dedupe(prof, closed: true)
        guard prof.count >= 3, abs(GeometryOps.signedArea(prof)) > 1e-9, abs(zb - za) > 1e-9 else { return nil }
        if GeometryOps.signedArea(prof) < 0 { prof.reverse() }
        return (prof, min(za, zb), max(za, zb))
    }

    // MARK: 2D helpers

    /// Inward miter offset of a CCW polygon keeping the vertex count (d > 0 shrinks).
    static func inset(_ p: [Vec2], _ d: Double) -> [Vec2] {
        let n = p.count
        guard abs(d) > 1e-15 else { return p }
        return (0..<n).map { i in
            let a = p[(i - 1 + n) % n], v = p[i], b = p[(i + 1) % n]
            let n1 = (v - a).normalized.perp, n2 = (b - v).normalized.perp
            let den = max(1 + n1.dot(n2), 0.05)
            return v + (n1 + n2) * (d / den)
        }
    }

    /// Whether every edge of `q` keeps the direction of the corresponding edge of `p` (no inversion after an inset).
    static func sameOrientation(_ p: [Vec2], _ q: [Vec2]) -> Bool {
        guard p.count == q.count else { return false }
        for i in 0..<p.count {
            let e0 = p[(i + 1) % p.count] - p[i], e1 = q[(i + 1) % q.count] - q[i]
            if e1.length > 1e-9 && e0.dot(e1) <= 0 { return false }
        }
        return GeometryOps.signedArea(q) > 1e-12
    }

    /// Rounds (or chamfers) every corner of a CCW polygon with `radius`, `segs` segments per corner; convex corners
    /// get `radius - shrink` and concave ones `radius + shrink` (the exact inward offset of a filleted outline).
    /// Every corner contributes `segs + 1` points so offsets keep the vertex count.
    static func filleted(_ p: [Vec2], radius: Double, shrink: Double, segs: Int, chamfer: Bool) -> [Vec2]? {
        let n = p.count
        var out: [Vec2] = []
        for i in 0..<n {
            let a = p[(i - 1 + n) % n], v = p[i], b = p[(i + 1) % n]
            let d1 = (a - v).normalized, d2 = (b - v).normalized
            let convex = (v - a).cross(b - v) > 0
            let r = max(convex ? radius - shrink : radius + shrink, 0)
            let cosT = max(-1, min(1, d1.dot(d2)))
            let theta = acos(cosT)               // interior angle between the edges
            if r < 1e-12 || theta < 1e-6 || abs(theta - .pi) < 1e-9 {
                out += Array(repeating: v, count: segs + 1); continue
            }
            let t = r / tan(theta / 2)
            if t > v.distance(to: a) / 2 + 1e-9 || t > v.distance(to: b) / 2 + 1e-9 { return nil }
            let p1 = v + d1 * t, p2 = v + d2 * t
            if chamfer || segs <= 1 {
                for k in 0...segs { out.append(p1.lerp(p2, Double(k) / Double(max(segs, 1)))) }
                continue
            }
            let bis = (d1 + d2).normalized
            let c = v + bis * (r / sin(theta / 2))
            let a0 = (p1 - c).angle, a1 = (p2 - c).angle
            let sweep = normAngle(a1 - a0 + .pi) - .pi
            for k in 0...segs { out.append(c + Vec2.polar(r, a0 + sweep * Double(k) / Double(segs))) }
        }
        return out
    }

    // MARK: Fillet / chamfer

    /// Rounds or chamfers the chosen edges of a prism (box or extrusion) and returns a welded mesh solid.
    public static func filletEdges(_ s: SolidGeom, radius: Double, edges: EdgeSet, chamfer: Bool, segments: Int = 6) throws -> SolidGeom {
        guard let pr = prism(of: s) else { throw OpError.unsupported }
        return try filletPrism(pr.profile, z0: pr.z0, z1: pr.z1, radius: radius, edges: edges, chamfer: chamfer, segments: segments)
    }

    public static func filletPrism(_ profile: [Vec2], z0: Double, z1: Double, radius r: Double, edges: EdgeSet, chamfer: Bool, segments: Int = 6) throws -> SolidGeom {
        guard r > 1e-9, !edges.isEmpty else { throw OpError.radiusTooLarge }
        let h = z1 - z0
        let both = edges.contains(.top) && edges.contains(.bottom)
        if (both && r >= h / 2 - 1e-9) || (!both && r >= h - 1e-9) { throw OpError.radiusTooLarge }
        let segs = chamfer ? 1 : max(2, segments)
        let vr = edges.contains(.vertical) ? r : 0
        // Profile at inset d (vertical fillet radius shrinks with the inset at convex corners).
        func ring(_ d: Double) throws -> [Vec2] {
            let base = inset(profile, d)
            guard d < 1e-12 || sameOrientation(profile, base) else { throw OpError.radiusTooLarge }
            if vr <= 0 { return base }
            guard let f = filleted(base, radius: vr, shrink: d, segs: segs, chamfer: chamfer) else { throw OpError.radiusTooLarge }
            return f
        }
        var rings: [(pts: [Vec2], z: Double)] = []
        let steps = chamfer ? 1 : segs
        if edges.contains(.bottom) {
            for k in 0...steps {
                let a = Double.pi / 2 * Double(steps - k) / Double(steps)   // from the bottom face up to the vertical wall
                let d = chamfer ? r * Double(steps - k) : r * (1 - cos(a))
                let z = chamfer ? z0 + r * Double(k) : z0 + r - r * sin(a)
                rings.append((try ring(d), z))
            }
        } else { rings.append((try ring(0), z0)) }
        if edges.contains(.top) {
            for k in 0...steps {
                let a = Double.pi / 2 * Double(k) / Double(steps)
                let d = chamfer ? r * Double(k) : r * (1 - cos(a))
                let z = chamfer ? z1 - r + r * Double(k) : z1 - r + r * sin(a)
                if k == 0, let last = rings.last, abs(last.z - z) < 1e-9 { continue }
                rings.append((try ring(d), z))
            }
        } else { rings.append((try ring(0), z1)) }
        return try closedLoft(rings)
    }

    /// Closed solid through horizontal rings of equal vertex count (bottom → top), capped at both ends.
    static func closedLoft(_ rings: [(pts: [Vec2], z: Double)]) throws -> SolidGeom {
        guard rings.count >= 2, let n = rings.first?.pts.count, n >= 3, rings.allSatisfy({ $0.pts.count == n }) else { throw OpError.invalidProfile }
        var tris: [(Vec3, Vec3, Vec3)] = []
        for k in 0..<(rings.count - 1) {
            let A = rings[k].pts.map { Vec3($0.x, $0.y, rings[k].z) }, B = rings[k + 1].pts.map { Vec3($0.x, $0.y, rings[k + 1].z) }
            for i in 0..<n {
                let j = (i + 1) % n
                tris.append((A[i], A[j], B[j])); tris.append((A[i], B[j], B[i]))
            }
        }
        func cap(_ r: (pts: [Vec2], z: Double), up: Bool) {
            let loop = RG.dedupe(r.pts, closed: true, tol: 1e-9)
            guard loop.count >= 3, abs(GeometryOps.signedArea(loop)) > 1e-12 else { return }
            for t in Triangulator.triangulate(loop, holes: []) {
                let a = Vec3(loop[t.0].x, loop[t.0].y, r.z), b = Vec3(loop[t.1].x, loop[t.1].y, r.z), c = Vec3(loop[t.2].x, loop[t.2].y, r.z)
                let ccw = (loop[t.1] - loop[t.0]).cross(loop[t.2] - loop[t.0]) > 0
                tris.append(ccw == up ? (a, b, c) : (a, c, b))
            }
        }
        cap(rings[0], up: false)
        cap(rings[rings.count - 1], up: true)
        let scale = rings.flatMap(\.pts).reduce(0.0) { max($0, abs($1.x), abs($1.y)) } + abs(rings.last!.z)
        return MeshTools.solid(from: tris, tolerance: max(scale, 1) * 1e-9)
    }

    // MARK: Shell

    /// Hollows a box or extrusion with walls of `thickness`; `openTop` removes the top face (a tray or planter).
    public static func shell(_ s: SolidGeom, thickness t: Double, openTop: Bool) throws -> SolidGeom {
        guard let pr = prism(of: s) else { throw OpError.unsupported }
        guard t > 1e-9, t < (pr.z1 - pr.z0) / (openTop ? 1 : 2) - 1e-9 else { throw OpError.radiusTooLarge }
        let outer = pr.profile, inner = inset(outer, t)
        guard sameOrientation(outer, inner) else { throw OpError.radiusTooLarge }
        let n = outer.count
        func P(_ p: Vec2, _ z: Double) -> Vec3 { Vec3(p.x, p.y, z) }
        var tris: [(Vec3, Vec3, Vec3)] = []
        func walls(_ l: [Vec2], _ za: Double, _ zb: Double, outward: Bool) {
            for i in 0..<n {
                let j = (i + 1) % n
                let a0 = P(l[i], za), b0 = P(l[j], za), b1 = P(l[j], zb), a1 = P(l[i], zb)
                if outward { tris.append((a0, b0, b1)); tris.append((a0, b1, a1)) } else { tris.append((a0, b1, b0)); tris.append((a0, a1, b1)) }
            }
        }
        func capTris(_ l: [Vec2], _ z: Double, up: Bool) {
            for tr in Triangulator.triangulate(l, holes: []) {
                let a = P(l[tr.0], z), b = P(l[tr.1], z), c = P(l[tr.2], z)
                let ccw = (l[tr.1] - l[tr.0]).cross(l[tr.2] - l[tr.0]) > 0
                tris.append(ccw == up ? (a, b, c) : (a, c, b))
            }
        }
        walls(outer, pr.z0, pr.z1, outward: true)
        capTris(outer, pr.z0, up: false)
        let zi0 = pr.z0 + t
        if openTop {
            walls(inner, zi0, pr.z1, outward: false)
            capTris(inner, zi0, up: true)
            // Rim between the outer and inner top edges.
            for i in 0..<n {
                let j = (i + 1) % n
                let o0 = P(outer[i], pr.z1), o1 = P(outer[j], pr.z1), i0 = P(inner[i], pr.z1), i1 = P(inner[j], pr.z1)
                tris.append((o0, o1, i1)); tris.append((o0, i1, i0))
            }
        } else {
            capTris(outer, pr.z1, up: true)
            let zi1 = pr.z1 - t
            walls(inner, zi0, zi1, outward: false)
            capTris(inner, zi0, up: true)
            capTris(inner, zi1, up: false)
        }
        return MeshTools.solid(from: tris, tolerance: 1e-9 * max(1, BBox2(points: outer).width))
    }

    // MARK: Meshes

    /// Welded triangle mesh of any solid.
    public static func welded(_ s: SolidGeom) -> (vertices: [Vec3], triangles: [Int]) {
        if s.kind == .mesh { return (s.meshVertices, s.meshTriangles) }
        let m = MeshTools.mesh(of: s)
        let b = m.bounds
        let size = b.isEmpty ? 1 : max(b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z, 1)
        return MeshTools.weld(MeshTools.triangles(m), tolerance: size * 1e-9)
    }

    /// Edge-use counts: a closed 2-manifold has every undirected edge used by exactly two triangles, once in each direction.
    public static func isClosedManifold(vertices v: [Vec3], triangles t: [Int]) -> Bool {
        guard t.count >= 12, t.count % 3 == 0 else { return false }
        var directed: [Int: Int] = [:]
        let n = v.count
        var i = 0
        while i + 2 < t.count {
            for k in 0..<3 {
                let a = t[i + k], b = t[i + (k + 1) % 3]
                guard a >= 0, a < n, b >= 0, b < n, a != b else { return false }
                directed[a * n + b, default: 0] += 1
            }
            i += 3
        }
        for (key, c) in directed {
            if c != 1 { return false }
            let a = key / n, b = key % n
            if directed[b * n + a] != 1 { return false }
        }
        return true
    }

    /// Signed volume of an indexed mesh.
    public static func volume(vertices v: [Vec3], triangles t: [Int]) -> Double {
        var s = 0.0
        var i = 0
        while i + 2 < t.count { s += v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]])) / 6; i += 3 }
        return s
    }

    /// One level of Loop subdivision (smooth limit surface; boundaries use the crease rules).
    public static func loopSubdivide(vertices v: [Vec3], triangles t: [Int]) -> (vertices: [Vec3], triangles: [Int]) {
        let nv = v.count
        var edgeOpp: [Int: [Int]] = [:]
        var neighbors = Array(repeating: Set<Int>(), count: nv)
        func key(_ a: Int, _ b: Int) -> Int { min(a, b) * nv + max(a, b) }
        var i = 0
        while i + 2 < t.count {
            let f = [t[i], t[i + 1], t[i + 2]]
            for k in 0..<3 {
                let a = f[k], b = f[(k + 1) % 3], c = f[(k + 2) % 3]
                edgeOpp[key(a, b), default: []].append(c)
                neighbors[a].insert(b); neighbors[b].insert(a)
            }
            i += 3
        }
        var boundaryNbr = Array(repeating: [Int](), count: nv)
        for (k, opp) in edgeOpp where opp.count == 1 {
            let a = k / nv, b = k % nv
            boundaryNbr[a].append(b); boundaryNbr[b].append(a)
        }
        var out: [Vec3] = []
        out.reserveCapacity(nv + edgeOpp.count)
        for idx in 0..<nv {
            let p = v[idx]
            if boundaryNbr[idx].count == 2 {
                out.append(p * 0.75 + (v[boundaryNbr[idx][0]] + v[boundaryNbr[idx][1]]) * 0.125)
                continue
            }
            if !boundaryNbr[idx].isEmpty { out.append(p); continue }
            let n = neighbors[idx].count
            guard n >= 3 else { out.append(p); continue }
            let beta = n == 3 ? 3.0 / 16 : 3.0 / (8 * Double(n))
            let sum = neighbors[idx].reduce(Vec3.zero) { $0 + v[$1] }
            out.append(p * (1 - Double(n) * beta) + sum * beta)
        }
        var edgeVertex: [Int: Int] = [:]
        for (k, opp) in edgeOpp {
            let a = k / nv, b = k % nv
            let p = opp.count == 2 ? (v[a] + v[b]) * 0.375 + (v[opp[0]] + v[opp[1]]) * 0.125 : (v[a] + v[b]) * 0.5
            edgeVertex[k] = out.count
            out.append(p)
        }
        var tris: [Int] = []
        tris.reserveCapacity(t.count * 4)
        i = 0
        while i + 2 < t.count {
            let a = t[i], b = t[i + 1], c = t[i + 2]
            let ab = edgeVertex[key(a, b)]!, bc = edgeVertex[key(b, c)]!, ca = edgeVertex[key(c, a)]!
            tris += [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]
            i += 3
        }
        return (out, tris)
    }

    /// Smooths a solid by `levels` of Loop subdivision (result: a mesh solid).
    public static func smooth(_ s: SolidGeom, levels: Int, maxTriangles: Int = 400_000) throws -> SolidGeom {
        var m = welded(s)
        guard m.triangles.count >= 3 else { throw OpError.unsupported }
        for _ in 0..<max(0, min(levels, 5)) {
            if m.triangles.count / 3 * 4 > maxTriangles { throw OpError.tooLarge }
            m = loopSubdivide(vertices: m.vertices, triangles: m.triangles)
        }
        var r = SolidGeom(kind: .mesh, origin: s.origin, meshVertices: m.vertices, meshTriangles: m.triangles)
        var b = BBox3.empty
        m.vertices.forEach { b.add($0) }
        if !b.isEmpty { r.origin = b.min }
        return r
    }

    // MARK: 3D transforms

    /// Applies an affine map to a solid (as a mesh); `mirroring` reverses the triangle winding.
    public static func mapped(_ s: SolidGeom, mirroring: Bool, _ f: (Vec3) -> Vec3) -> SolidGeom {
        let m = welded(s)
        let v = m.vertices.map(f)
        var t = m.triangles
        if mirroring { var i = 0; while i + 2 < t.count { t.swapAt(i + 1, i + 2); i += 3 } }
        var b = BBox3.empty
        v.forEach { b.add($0) }
        return SolidGeom(kind: .mesh, origin: b.isEmpty ? s.origin : b.min, meshVertices: v, meshTriangles: t)
    }

    public enum Plane: String, CaseIterable { case xy, yz, zx }

    /// Reflection of a point in an axis plane through `origin`, or in the vertical plane through a plan line.
    public static func reflect(_ p: Vec3, plane: Plane, origin: Vec3) -> Vec3 {
        switch plane {
        case .xy: return Vec3(p.x, p.y, 2 * origin.z - p.z)
        case .yz: return Vec3(2 * origin.x - p.x, p.y, p.z)
        case .zx: return Vec3(p.x, 2 * origin.y - p.y, p.z)
        }
    }
    public static func reflect(_ p: Vec3, lineA a: Vec2, lineB b: Vec2) -> Vec3 {
        let q = Transform2D.mirror(a, b).apply(p.xy)
        return Vec3(q.x, q.y, p.z)
    }

    /// Rotation of a point about an axis parallel to X, Y or Z through `origin` (angle in radians, right-hand rule).
    public static func rotate(_ p: Vec3, axis: Character, angle: Double, origin o: Vec3) -> Vec3 {
        let c = cos(angle), s = sin(angle)
        let q = p - o
        let r: Vec3
        switch axis {
        case "x", "X": r = Vec3(q.x, q.y * c - q.z * s, q.y * s + q.z * c)
        case "y", "Y": r = Vec3(q.x * c + q.z * s, q.y, -q.x * s + q.z * c)
        default: r = Vec3(q.x * c - q.y * s, q.x * s + q.y * c, q.z)
        }
        return r + o
    }

    /// Moves a solid in 3D keeping it parametric where possible.
    public static func translated(_ s: SolidGeom, by d: Vec3) -> SolidGeom {
        var r = s
        r.origin = s.origin + d
        r.meshVertices = s.meshVertices.map { $0 + d }
        return r
    }
}
