// Oanarina Archi Tool — GPL-3.0-or-later
//
// Constructive solid geometry on triangle meshes with BSP trees. The algorithm follows csg.js by Evan Wallace
// (MIT licence, https://github.com/evanw/csg.js); this is an independent Swift reimplementation with
// iterative tree traversal (no deep recursion) and a tolerance scaled to the model size.
import Foundation

public enum CSG {
    public enum Operation: String, CaseIterable { case union, subtract, intersect }

    struct Poly {
        var v: [Vec3]
        var n: Vec3
        var w: Double
        init?(_ v: [Vec3]) {
            guard v.count >= 3 else { return nil }
            var nn = Vec3.zero
            for i in 0..<v.count { let a = v[i], b = v[(i + 1) % v.count]
                nn = nn + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
            guard nn.length > 1e-20 else { return nil }
            self.v = v; n = nn.normalized; w = n.dot(v[0])
        }
        init(v: [Vec3], n: Vec3, w: Double) { self.v = v; self.n = n; self.w = w }
        mutating func flip() { v.reverse(); n = -n; w = -w }
    }

    struct Plane { var n: Vec3; var w: Double }

    final class Node {
        var plane: Plane?
        var front: Node?
        var back: Node?
        var polys: [Poly] = []
    }

    /// Splits `p` by `plane` into the four buckets (coplanar polygons go to front/back by facing).
    static func split(_ p: Poly, _ plane: Plane, eps: Double, cf: inout [Poly], cb: inout [Poly], f: inout [Poly], b: inout [Poly]) {
        var types: [Int] = []
        var polyType = 0
        types.reserveCapacity(p.v.count)
        for q in p.v {
            let t = plane.n.dot(q) - plane.w
            let ty = t < -eps ? 2 : (t > eps ? 1 : 0)
            polyType |= ty; types.append(ty)
        }
        switch polyType {
        case 0: if plane.n.dot(p.n) > 0 { cf.append(p) } else { cb.append(p) }
        case 1: f.append(p)
        case 2: b.append(p)
        default:
            var fv: [Vec3] = [], bv: [Vec3] = []
            let n = p.v.count
            for i in 0..<n {
                let j = (i + 1) % n
                let ti = types[i], tj = types[j], vi = p.v[i], vj = p.v[j]
                if ti != 2 { fv.append(vi) }
                if ti != 1 { bv.append(vi) }
                if (ti | tj) == 3 {
                    let t = (plane.w - plane.n.dot(vi)) / plane.n.dot(vj - vi)
                    let x = vi + (vj - vi) * t
                    fv.append(x); bv.append(x)
                }
            }
            if fv.count >= 3 { f.append(Poly(v: fv, n: p.n, w: p.w)) }
            if bv.count >= 3 { b.append(Poly(v: bv, n: p.n, w: p.w)) }
        }
    }

    static func build(_ root: Node, _ polys: [Poly], eps: Double) {
        var stack: [(Node, [Poly])] = [(root, polys)]
        while let (node, ps) = stack.popLast() {
            guard !ps.isEmpty else { continue }
            if node.plane == nil { node.plane = Plane(n: ps[0].n, w: ps[0].w) }
            var f: [Poly] = [], b: [Poly] = []
            var cf: [Poly] = [], cb: [Poly] = []
            for p in ps { split(p, node.plane!, eps: eps, cf: &cf, cb: &cb, f: &f, b: &b) }
            node.polys += cf; node.polys += cb
            if !f.isEmpty { if node.front == nil { node.front = Node() }; stack.append((node.front!, f)) }
            if !b.isEmpty { if node.back == nil { node.back = Node() }; stack.append((node.back!, b)) }
        }
    }

    static func nodes(_ root: Node) -> [Node] {
        var out: [Node] = []
        var stack = [root]
        while let n = stack.popLast() { out.append(n); if let f = n.front { stack.append(f) }; if let b = n.back { stack.append(b) } }
        return out
    }

    static func invert(_ root: Node) {
        for n in nodes(root) {
            for i in 0..<n.polys.count { n.polys[i].flip() }
            if let p = n.plane { n.plane = Plane(n: -p.n, w: -p.w) }
            swap(&n.front, &n.back)
        }
    }

    /// Removes the parts of `polys` inside the solid represented by `root`.
    static func clip(_ polys: [Poly], by root: Node, eps: Double) -> [Poly] {
        var out: [Poly] = []
        var stack: [(Node, [Poly])] = [(root, polys)]
        while let (node, ps) = stack.popLast() {
            guard let plane = node.plane else { out += ps; continue }
            var f: [Poly] = [], b: [Poly] = [], cf: [Poly] = [], cb: [Poly] = []
            for p in ps { split(p, plane, eps: eps, cf: &cf, cb: &cb, f: &f, b: &b) }
            f += cf; b += cb
            if let nf = node.front { if !f.isEmpty { stack.append((nf, f)) } } else { out += f }
            if let nb = node.back { if !b.isEmpty { stack.append((nb, b)) } }
        }
        return out
    }

    static func clipTo(_ a: Node, _ b: Node, eps: Double) {
        for n in nodes(a) { n.polys = clip(n.polys, by: b, eps: eps) }
    }

    static func all(_ root: Node) -> [Poly] { nodes(root).flatMap(\.polys) }

    static func polys(_ tris: [(Vec3, Vec3, Vec3)]) -> [Poly] { tris.compactMap { Poly([$0.0, $0.1, $0.2]) } }

    /// Boolean of two closed, outward-oriented triangle soups. Returns triangles of the result.
    public static func apply(_ op: Operation, _ ta: [(Vec3, Vec3, Vec3)], _ tb: [(Vec3, Vec3, Vec3)]) -> [(Vec3, Vec3, Vec3)] {
        var box = BBox3.empty
        for t in ta + tb { box.add(t.0); box.add(t.1); box.add(t.2) }
        guard !box.isEmpty else { return [] }
        let size = max(box.size.x, box.size.y, box.size.z, 1e-9)
        let eps = size * 1e-7
        let a = Node(), b = Node()
        build(a, polys(ta), eps: eps); build(b, polys(tb), eps: eps)
        switch op {
        case .union:
            clipTo(a, b, eps: eps); clipTo(b, a, eps: eps)
            invert(b); clipTo(b, a, eps: eps); invert(b)
            build(a, all(b), eps: eps)
        case .subtract:
            invert(a); clipTo(a, b, eps: eps); clipTo(b, a, eps: eps)
            invert(b); clipTo(b, a, eps: eps); invert(b)
            build(a, all(b), eps: eps); invert(a)
        case .intersect:
            invert(a); clipTo(b, a, eps: eps); invert(b)
            clipTo(a, b, eps: eps); clipTo(b, a, eps: eps)
            build(a, all(b), eps: eps); invert(a)
        }
        var out: [(Vec3, Vec3, Vec3)] = []
        for p in all(a) where p.v.count >= 3 {
            for i in 1..<(p.v.count - 1) {
                let t = (p.v[0], p.v[i], p.v[i + 1])
                if (t.1 - t.0).cross(t.2 - t.0).length > eps * eps { out.append(t) }
            }
        }
        return out
    }

    /// Boolean of two solids; nil if the result is empty.
    public static func apply(_ op: Operation, _ a: SolidGeom, _ b: SolidGeom) -> SolidGeom? {
        let ta = MeshTools.triangles(MeshTools.mesh(of: a)), tb = MeshTools.triangles(MeshTools.mesh(of: b))
        let r = apply(op, ta, tb)
        guard !r.isEmpty else { return nil }
        var box = BBox3.empty
        for t in r { box.add(t.0); box.add(t.1); box.add(t.2) }
        return MeshTools.solid(from: r, tolerance: max(box.size.x, box.size.y, box.size.z, 1e-9) * 1e-8)
    }

    /// Volume of a solid (from its closed mesh).
    public static func volume(_ s: SolidGeom) -> Double { MeshTools.signedVolume(MeshTools.mesh(of: s)) }
}
