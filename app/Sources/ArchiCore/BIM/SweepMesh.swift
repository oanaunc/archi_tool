// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Sweeps and lofts of closed 2D profiles along 3D paths (mitred joints, capped ends).
enum SweepMesh {
    /// Local frame at each path vertex: tangent-averaged, with mitre scaling at joints.
    /// Profile x runs along `X` (to the left of travel when `up` is Z), profile y along the projected `up`.
    static func frames(_ path: [Vec3], up: Vec3 = .unitZ, closed: Bool = false) -> [(o: Vec3, x: Vec3, y: Vec3)] {
        let n = path.count
        guard n >= 2 else { return [] }
        func seg(_ i: Int) -> Vec3 { (path[(i + 1) % n] - path[i]).normalized }
        func axes(_ t: Vec3) -> (Vec3, Vec3) {
            var y = up - t * up.dot(t)
            if y.length < 1e-9 { let alt = abs(t.x) < 0.9 ? Vec3(1, 0, 0) : Vec3(0, 1, 0); y = alt - t * alt.dot(t) }
            y = y.normalized
            return (y.cross(t).normalized, y)
        }
        var out: [(Vec3, Vec3, Vec3)] = []
        for i in 0..<n {
            let tin: Vec3? = (i > 0 || closed) ? seg((i - 1 + n) % n) : nil
            let tout: Vec3? = (i < n - 1 || closed) ? seg(i) : nil
            switch (tin, tout) {
            case let (a?, b?):
                let (xa, ya) = axes(a), (xb, yb) = axes(b)
                let dx = 1 + xa.dot(xb), dy = 1 + ya.dot(yb)
                let x = dx > 0.2 ? (xa + xb) / dx : xb
                let y = dy > 0.2 ? (ya + yb) / dy : yb
                out.append((path[i], x, y))
            case let (a?, nil): let (x, y) = axes(a); out.append((path[i], x, y))
            case let (nil, b?): let (x, y) = axes(b); out.append((path[i], x, y))
            default: break
            }
        }
        return out
    }

    /// Adds the swept solid of `profile` (closed, local 2D) along `path` into `acc`.
    static func sweep(_ profile0: [Vec2], along path0: [Vec3], up: Vec3 = .unitZ, closedPath: Bool = false, into acc: inout MeshAcc) {
        var profile = RG.dedupe(profile0, closed: true)
        var path: [Vec3] = []
        for p in path0 where !(path.last.map { $0.distance(to: p) < 1e-9 } ?? false) { path.append(p) }
        if closedPath, path.count > 2, path[0].distance(to: path[path.count - 1]) < 1e-9 { path.removeLast() }
        guard profile.count >= 3, path.count >= 2, abs(GeometryOps.signedArea(profile)) > 1e-12 else { return }
        if GeometryOps.signedArea(profile) < 0 { profile.reverse() }
        let fr = frames(path, up: up, closed: closedPath)
        let rings: [[Vec3]] = fr.map { f in profile.map { f.o + f.x * $0.x + f.y * $0.y } }
        loft(rings, closed: closedPath, capped: !closedPath, into: &acc)
    }

    /// Skins consecutive rings with equal vertex counts; optionally caps the first and last ring.
    /// Rings are expected counter-clockwise about the direction of travel; the result is flipped if it comes out inside-out.
    static func loft(_ rings: [[Vec3]], closed: Bool = false, capped: Bool = true, into acc: inout MeshAcc) {
        guard rings.count >= 2, let m = rings.first?.count, m >= 3, rings.allSatisfy({ $0.count == m }) else { return }
        var part = MeshAcc()
        func tri(_ a: Vec3, _ b: Vec3, _ c: Vec3) {
            let n = (b - a).cross(c - a)
            guard n.length > 1e-14 else { return }
            let nn = n.normalized
            part.tri(a, b, c, nn, nn, nn)
        }
        let segs = closed ? rings.count : rings.count - 1
        for r in 0..<segs {
            let a = rings[r], b = rings[(r + 1) % rings.count]
            for i in 0..<m {
                let j = (i + 1) % m
                tri(a[i], a[j], b[j]); tri(a[i], b[j], b[i])
            }
            part.edges.append(a + [a[0]])
        }
        if !closed { part.edges.append(rings[rings.count - 1] + [rings[rings.count - 1][0]]) }
        if capped && !closed {
            let first = rings[0], last = rings[rings.count - 1]
            let n0 = Mesh.polygonNormal(first), n1 = Mesh.polygonNormal(last)
            if n0.length > 0.5 { part.mesh.addPolygon(first.reversed(), normal: -n0) }
            if n1.length > 0.5 { part.mesh.addPolygon(last, normal: n1) }
        }
        if MeshTools.signedVolume(part.mesh) < 0 { part.mesh = MeshTools.flipped(part.mesh) }
        acc.mesh.append(part.mesh)
        acc.edges += part.edges
    }

    /// Resamples a closed 2D profile to `count` points spaced evenly by arc length, starting at the vertex
    /// nearest to the profile's lowest-leftmost point (so lofted rings line up).
    static func resample(_ poly0: [Vec2], count: Int) -> [Vec2] {
        var poly = RG.dedupe(poly0, closed: true)
        guard poly.count >= 3, count >= 3 else { return poly }
        if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
        let box = BBox2(points: poly)
        let k = poly.indices.min { poly[$0].distance(to: box.min) < poly[$1].distance(to: box.min) }!
        poly = Array(poly[k...] + poly[..<k])
        let ring = poly + [poly[0]]
        var cum: [Double] = [0]
        for i in 0..<(ring.count - 1) { cum.append(cum[i] + ring[i].distance(to: ring[i + 1])) }
        let total = cum[cum.count - 1]
        guard total > 1e-12 else { return poly }
        var out: [Vec2] = []
        var seg = 0
        for i in 0..<count {
            let d = total * Double(i) / Double(count)
            while seg < ring.count - 2 && cum[seg + 1] < d { seg += 1 }
            let l = cum[seg + 1] - cum[seg]
            let t = l > 1e-12 ? (d - cum[seg]) / l : 0
            out.append(ring[seg].lerp(ring[seg + 1], t))
        }
        return out
    }
}
