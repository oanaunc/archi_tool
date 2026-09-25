// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Utilities on triangle meshes: volume, orientation, welding, feature edges, conversion to/from solids.
public enum MeshTools {
    /// Signed volume (positive for outward-oriented closed meshes).
    public static func signedVolume(_ m: Mesh) -> Double {
        var v = 0.0
        var i = 0
        while i + 2 < m.indices.count {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            v += a.dot(b.cross(c)) / 6
            i += 3
        }
        return v
    }

    public static func surfaceArea(_ m: Mesh) -> Double {
        var s = 0.0
        var i = 0
        while i + 2 < m.indices.count {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            s += (b - a).cross(c - a).length / 2
            i += 3
        }
        return s
    }

    public static func flipped(_ m: Mesh) -> Mesh {
        var r = m
        r.normals = m.normals.map { -$0 }
        var i = 0
        while i + 2 < r.indices.count { r.indices.swapAt(i + 1, i + 2); i += 3 }
        return r
    }

    /// Triangles as vertex triples.
    public static func triangles(_ m: Mesh) -> [(Vec3, Vec3, Vec3)] {
        var out: [(Vec3, Vec3, Vec3)] = []
        var i = 0
        while i + 2 < m.indices.count {
            out.append((m.positions[Int(m.indices[i])], m.positions[Int(m.indices[i + 1])], m.positions[Int(m.indices[i + 2])]))
            i += 3
        }
        return out
    }

    /// Welds coincident vertices; returns unique positions and triangle indices (degenerate triangles dropped).
    public static func weld(_ tris: [(Vec3, Vec3, Vec3)], tolerance: Double) -> (vertices: [Vec3], triangles: [Int]) {
        var verts: [Vec3] = []
        var index: [[Int64]: Int] = [:]
        let q = max(tolerance, 1e-12)
        func vid(_ v: Vec3) -> Int {
            let k = [Int64((v.x / q).rounded()), Int64((v.y / q).rounded()), Int64((v.z / q).rounded())]
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                if let i = index[[k[0] + Int64(dx), k[1] + Int64(dy), k[2] + Int64(dz)]], verts[i].distance(to: v) <= q * 1.5 { return i }
            } } }
            verts.append(v); index[k] = verts.count - 1
            return verts.count - 1
        }
        var idx: [Int] = []
        for (a, b, c) in tris {
            let ia = vid(a), ib = vid(b), ic = vid(c)
            if ia == ib || ib == ic || ia == ic { continue }
            idx += [ia, ib, ic]
        }
        return (verts, idx)
    }

    /// Closed triangle mesh of a solid (primitive, extrusion, revolve or mesh) in model coordinates.
    public static func mesh(of s: SolidGeom) -> Mesh {
        var acc = MeshAcc()
        MeshBuilder.solid(s, into: &acc)
        return acc.mesh
    }

    /// Converts a triangle list into a `.mesh` solid (welded).
    public static func solid(from tris: [(Vec3, Vec3, Vec3)], tolerance: Double = 1e-6) -> SolidGeom {
        let w = weld(tris, tolerance: tolerance)
        var o = Vec3.zero
        if !w.vertices.isEmpty {
            var b = BBox3.empty
            w.vertices.forEach { b.add($0) }
            o = Vec3(b.min.x, b.min.y, b.min.z)
        }
        return SolidGeom(kind: .mesh, origin: o, meshVertices: w.vertices, meshTriangles: w.triangles)
    }

    /// Edges between faces meeting at more than `angle` degrees, plus boundary edges (for hidden-line views).
    public static func featureEdges(vertices v: [Vec3], triangles t: [Int], angle: Double = 25) -> [[Vec3]] {
        var map: [[Int]: [Vec3]] = [:]
        var i = 0
        while i + 2 < t.count {
            let ids = [t[i], t[i + 1], t[i + 2]]
            i += 3
            guard ids.allSatisfy({ $0 >= 0 && $0 < v.count }) else { continue }
            let n = (v[ids[1]] - v[ids[0]]).cross(v[ids[2]] - v[ids[0]]).normalized
            for k in 0..<3 {
                let a = ids[k], b = ids[(k + 1) % 3]
                map[[min(a, b), max(a, b)], default: []].append(n)
            }
        }
        let cosLimit = cos(angle * .pi / 180)
        var out: [[Vec3]] = []
        for (k, ns) in map {
            if ns.count == 2 && ns[0].dot(ns[1]) > cosLimit { continue }
            out.append([v[k[0]], v[k[1]]])
        }
        return out
    }

    /// Outline of a mesh seen from above: projected feature edges (used for plan display of mesh solids).
    public static func planEdges(vertices v: [Vec3], triangles t: [Int]) -> [[Vec2]] {
        featureEdges(vertices: v, triangles: t, angle: 30).map { $0.map(\.xy) }.filter { $0.count == 2 && $0[0].distance(to: $0[1]) > 1e-9 }
    }
}
