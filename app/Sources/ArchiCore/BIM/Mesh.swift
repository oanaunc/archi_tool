// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Triangle mesh in millimetre model coordinates (Z up).
public struct Mesh: Hashable {
    public var positions: [Vec3] = []
    public var normals: [Vec3] = []
    public var uvs: [Vec2] = []
    public var indices: [UInt32] = []
    public init() {}
    public var isEmpty: Bool { indices.isEmpty }
    public var triangleCount: Int { indices.count / 3 }

    /// Adds a planar convex or concave polygon (flat-shaded, triangulated).
    public mutating func addPolygon(_ pts: [Vec3], normal: Vec3? = nil) {
        guard pts.count >= 3 else { return }
        let n = normal ?? Mesh.polygonNormal(pts)
        let base = UInt32(positions.count)
        positions += pts
        normals += Array(repeating: n, count: pts.count)
        uvs += Mesh.planarUV(pts, normal: n)
        // Project to 2D for triangulation.
        let (u, v) = Mesh.basis(n)
        let flat = pts.map { Vec2($0.dot(u), $0.dot(v)) }
        for t in Triangulator.triangulate(flat, holes: []) {
            indices += [base + UInt32(t.0), base + UInt32(t.1), base + UInt32(t.2)]
        }
    }
    public mutating func addQuad(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ d: Vec3) { addPolygon([a, b, c, d]) }
    public mutating func append(_ m: Mesh) {
        let base = UInt32(positions.count)
        positions += m.positions; normals += m.normals; uvs += m.uvs
        indices += m.indices.map { $0 + base }
    }
    public var bounds: BBox3 { var b = BBox3.empty; positions.forEach { b.add($0) }; return b }

    public static func polygonNormal(_ p: [Vec3]) -> Vec3 {
        var n = Vec3.zero
        for i in 0..<p.count { let a = p[i], b = p[(i + 1) % p.count]
            n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
        return n.normalized
    }
    public static func basis(_ n: Vec3) -> (Vec3, Vec3) {
        let a = abs(n.z) < 0.9 ? Vec3.unitZ : Vec3(1, 0, 0)
        let u = a.cross(n).normalized
        return (u, n.cross(u).normalized)
    }
    static func planarUV(_ pts: [Vec3], normal n: Vec3) -> [Vec2] {
        let (u, v) = basis(n)
        return pts.map { Vec2($0.dot(u) / 1000, $0.dot(v) / 1000) }
    }
}

/// A renderable piece of the building or model, with its material and feature edges.
public struct MeshGroup: Hashable {
    public var id: EntityID?
    public var kind: String
    public var material: String
    public var mesh: Mesh
    /// Sharp edges drawn as lines in hidden-line / shaded-with-edges styles.
    public var edges: [[Vec3]]
    public init(id: EntityID?, kind: String, material: String, mesh: Mesh, edges: [[Vec3]] = []) {
        self.id = id; self.kind = kind; self.material = material; self.mesh = mesh; self.edges = edges
    }
}

/// Ear-clipping triangulation of a simple polygon with optional holes (holes are bridged into the outer loop).
public enum Triangulator {
    public static func triangulate(_ outer: [Vec2], holes: [[Vec2]]) -> [(Int, Int, Int)] {
        triangulateWithPoints(outer, holes: holes).triangles
    }

    /// Triangulates and returns the combined point list the indices refer to (outer followed by the holes in bridging order).
    public static func triangulateWithPoints(_ outer: [Vec2], holes: [[Vec2]]) -> (points: [Vec2], triangles: [(Int, Int, Int)]) {
        guard outer.count >= 3 else { return (outer, []) }
        var idx: [Int] = GeometryOps.signedArea(outer) < 0 ? Array((0..<outer.count).reversed()) : Array(0..<outer.count)
        var all = outer
        // Bridge holes: connect each hole's rightmost vertex to the closest outer vertex.
        for hole0 in holes.sorted(by: { ($0.map(\.x).max() ?? 0) > ($1.map(\.x).max() ?? 0) }) where hole0.count >= 3 {
            var hole = hole0
            if GeometryOps.signedArea(hole) > 0 { hole.reverse() }
            let hStart = all.count
            all += hole
            let hi = hole.indices.max(by: { hole[$0].x < hole[$1].x })!
            let hp = hole[hi]
            var bestK = 0, bestD = Double.infinity
            for (k, oi) in idx.enumerated() {
                let d = all[oi].distance(to: hp)
                if d < bestD, visible(all, idx, from: hp, to: all[oi]) { bestD = d; bestK = k }
            }
            var bridge: [Int] = []
            for j in 0...hole.count { bridge.append(hStart + (hi + j) % hole.count) }
            bridge.append(idx[bestK])
            idx.insert(contentsOf: bridge, at: bestK + 1)
        }
        return (all, earClip(all, idx))
    }

    static func visible(_ pts: [Vec2], _ idx: [Int], from a: Vec2, to b: Vec2) -> Bool {
        for i in 0..<idx.count {
            let p = pts[idx[i]], q = pts[idx[(i + 1) % idx.count]]
            if p.isClose(b) || q.isClose(b) { continue }
            if GeometryOps.segmentIntersection(a, b, p, q) != nil { return false }
        }
        return true
    }

    static func earClip(_ pts: [Vec2], _ idx0: [Int]) -> [(Int, Int, Int)] {
        var idx = idx0
        var out: [(Int, Int, Int)] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < 100000 {
            guardCount += 1
            var clipped = false
            for i in 0..<idx.count {
                let i0 = idx[(i + idx.count - 1) % idx.count], i1 = idx[i], i2 = idx[(i + 1) % idx.count]
                let a = pts[i0], b = pts[i1], c = pts[i2]
                if (b - a).cross(c - b) <= 1e-12 { continue }
                var ear = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    let p = pts[j]
                    if p.isClose(a) || p.isClose(b) || p.isClose(c) { continue }
                    if inTriangle(p, a, b, c) { ear = false; break }
                }
                if ear { out.append((i0, i1, i2)); idx.remove(at: i); clipped = true; break }
            }
            if !clipped { // degenerate: fan the rest
                for i in 1..<(idx.count - 1) { out.append((idx[0], idx[i], idx[i + 1])) }
                return out
            }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }
    static func inTriangle(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> Bool {
        let d1 = (b - a).cross(p - a), d2 = (c - b).cross(p - b), d3 = (a - c).cross(p - c)
        return d1 >= 0 && d2 >= 0 && d3 >= 0
    }
}
