// Oanarina Archi Tool — GPL-3.0-or-later
// Wall shapes beyond the vertical prism: elevation profiles (BIM-020: gables, steps, cut-outs) trim the wall solid,
// slanted walls lean and tapered walls thin towards the top (BIM-023). The 3D solid (and so sections, exports and
// quantities) is shaped here; plans show the wall where the plan cut plane passes through it.
import Foundation

enum WallShapes {
    /// Local wall coordinates (s along, t across) are mapped at height z: t' = t · k(z) + shift(z).
    static func mapper(_ g: WallGeom, f: WallFrame, zBase: Double, height: Double) -> ((Vec2, Double) -> Vec2)? {
        guard g.isSlantedOrTapered, height > 1e-9 else { return nil }
        let tanA = tan((g.slant ?? 0) * .pi / 180)
        let t0 = max(g.thickness, 1e-9), t1 = max(g.topThickness ?? g.thickness, 1e-6)
        return { p, z in
            let dz = z - zBase
            let k = (t0 + (t1 - t0) * min(max(dz / height, 0), 1)) / t0
            let (s, t) = f.project(p)
            return f.pt(s, t * k + dz * tanA)
        }
    }

    /// Offset map of a wall's local t at absolute height z (identity for vertical, untapered walls).
    static func tMap(_ el: BIMElement, doc: ArchiDocument) -> (Double, Double) -> Double {
        guard case .wall(let g) = el.geometry, g.isSlantedOrTapered else { return { t, _ in t } }
        let r = BIMConstraints.wallRange(el, doc: doc)
        let height = max(r.z1 - r.z0, 1e-9)
        let tanA = tan((g.slant ?? 0) * .pi / 180)
        let t0 = max(g.thickness, 1e-9), t1 = max(g.topThickness ?? g.thickness, 1e-6)
        return { t, z in
            let dz = min(max(z - r.z0, 0), height)
            return t * (t0 + (t1 - t0) * dz / height) / t0 + dz * tanA
        }
    }

    /// Join-aware shape map of a wall (BIM-023 clean joins): body points shift across the wall by its own slant/taper;
    /// points in a joined end zone that lie inside a neighbouring wall's band go to the intersection of both walls'
    /// shifted lines, so mitres, butt and T-joins stay closed at every height — also for a vertical wall whose
    /// neighbour leans. nil when neither the wall nor any wall joined at its ends is slanted or tapered.
    static func jointMapper(_ f: WallFrame, el: BIMElement, ctx: BIMContext) -> ((Vec2, Double) -> Vec2)? {
        guard ctx.hasShapedWalls else { return nil }
        let doc = ctx.doc
        let tol = ctx.tol
        let own = tMap(el, doc: doc)
        var ends: [(P: Vec2, reach: Double, nb: [(WallFrame, (Double, Double) -> Double)])] = []
        var anyShaped = f.g.isSlantedOrTapered
        if !f.isCurved {
            for (P, D) in [(f.cs, f.g.start), (f.ce, f.g.end)] {
                var nb: [(WallFrame, (Double, Double) -> Double)] = []
                for (_, b) in ctx.frames where b.id != f.id && b.level == f.level && !b.isCurved {
                    let near = [b.cs, b.ce, b.g.start, b.g.end].contains { $0.distance(to: P) <= 2 * tol || $0.distance(to: D) <= 2 * tol }
                    let pr = b.project(P)
                    let host = pr.s > -tol && pr.s < b.L + tol && abs(pr.t) <= b.h + tol
                    guard near || host, let bel = doc.element(b.id) else { continue }
                    if b.g.isSlantedOrTapered { anyShaped = true }
                    nb.append((b, tMap(bel, doc: doc)))
                }
                let reach = 8 * max(f.h, nb.map { $0.0.h }.max() ?? 0) + tol
                ends.append((P, reach, nb))
            }
        }
        guard anyShaped else { return nil }
        return { p, z in
            let (s, t) = f.project(p)
            let tA = own(t, z)
            if !f.isCurved {
                var best: (score: Double, q: Vec2)? = nil
                for e in ends where p.distance(to: e.P) <= e.reach {
                    for (b, bm) in e.nb {
                        let pb = b.project(p)
                        guard abs(pb.t) <= b.h + tol, pb.s > -b.h * 8 - tol, pb.s < b.L + b.h * 8 + tol else { continue }
                        let score = abs(abs(pb.t) - b.h)
                        if let bs = best, bs.score <= score { continue }
                        let tB = bm(pb.t, z)
                        let a0 = f.cs + f.dir.perp * tA, b0 = b.cs + b.dir.perp * tB
                        guard let x = GeometryOps.lineIntersection(a0, a0 + f.dir, b0, b0 + b.dir) else { continue }
                        best = (score, x)
                    }
                }
                if let b = best { return b.q }
            }
            return f.pt(s, tA)
        }
    }

    /// Applies a shape map (see `jointMapper`) to a wall mesh (positions, feature edges; normals recomputed per face).
    static func shape(_ acc: inout MeshAcc, map m: (Vec2, Double) -> Vec2) {
        guard !acc.mesh.isEmpty || !acc.edges.isEmpty else { return }
        let old = acc.mesh
        var out = MeshAcc()
        var i = 0
        while i + 2 < old.indices.count {
            let v = [old.positions[Int(old.indices[i])], old.positions[Int(old.indices[i + 1])], old.positions[Int(old.indices[i + 2])]].map { p -> Vec3 in
                let q = m(p.xy, p.z); return Vec3(q.x, q.y, p.z) }
            i += 3
            let n = (v[1] - v[0]).cross(v[2] - v[0])
            guard n.length > 1e-14 else { continue }
            let nn = n.normalized
            out.tri(v[0], v[1], v[2], nn, nn, nn)
        }
        out.edges = acc.edges.map { $0.map { p in let q = m(p.xy, p.z); return Vec3(q.x, q.y, p.z) } }
        acc = out
    }

    /// Applies slant/taper to a wall mesh (positions, feature edges; normals recomputed per face).
    static func shape(_ acc: inout MeshAcc, _ g: WallGeom, f: WallFrame, zBase: Double, height: Double) {
        guard let m = mapper(g, f: f, zBase: zBase, height: height), !acc.mesh.isEmpty else { return }
        let old = acc.mesh
        var out = MeshAcc()
        var i = 0
        while i + 2 < old.indices.count {
            let v = [old.positions[Int(old.indices[i])], old.positions[Int(old.indices[i + 1])], old.positions[Int(old.indices[i + 2])]].map { p -> Vec3 in
                let q = m(p.xy, p.z); return Vec3(q.x, q.y, p.z) }
            i += 3
            let n = (v[1] - v[0]).cross(v[2] - v[0])
            guard n.length > 1e-14 else { continue }
            let nn = n.normalized
            out.tri(v[0], v[1], v[2], nn, nn, nn)
        }
        out.edges = acc.edges.map { $0.map { p in let q = m(p.xy, p.z); return Vec3(q.x, q.y, p.z) } }
        acc = out
    }

    /// Solid of the elevation profile: the profile polygon in the wall's vertical plane, extruded through the wall.
    static func profileSolid(_ g: WallGeom, f: WallFrame, zBase: Double) -> MeshAcc? {
        guard let pr = g.profile, pr.count >= 3, !f.isCurved else { return nil }
        var poly = RG.dedupe(pr, closed: true)
        guard poly.count >= 3, abs(GeometryOps.signedArea(poly)) > 1e-9 else { return nil }
        if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
        var acc = MeshAcc()
        let pad = f.h * 4 + max(abs(g.slant ?? 0) > 0 ? g.height : 0, 1)
        let y0 = -f.h - pad, y1 = f.h + pad
        let d3 = Vec3(f.dir.x, f.dir.y, 0), n3 = Vec3(f.dir.perp.x, f.dir.perp.y, 0)
        func P(_ q: Vec2, _ y: Double) -> Vec3 { let b = f.cs + f.dir * q.x + f.dir.perp * y; return Vec3(b.x, b.y, zBase + q.y) }
        // Caps (any simple polygon, triangulated) and sides with outward normals (non-convex profiles included).
        let (pts, tris) = Triangulator.triangulateWithPoints(poly, holes: [])
        for t in tris {
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            acc.tri(P(a, y0), P(b, y0), P(c, y0), -n3, -n3, -n3)
            acc.tri(P(a, y1), P(b, y1), P(c, y1), n3, n3, n3)
        }
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let e = b - a
            guard e.length > 1e-12 else { continue }
            let out2 = Vec2(e.y, -e.x).normalized
            let n = d3 * out2.x + Vec3(0, 0, 1) * out2.y
            acc.tri(P(a, y0), P(b, y0), P(b, y1), n, n, n)
            acc.tri(P(a, y0), P(b, y1), P(a, y1), n, n, n)
        }
        return acc
    }

    /// Trims a wall mesh to its elevation profile.
    static func trim(_ acc: MeshAcc, to cutter: MeshAcc) -> MeshAcc {
        guard !acc.mesh.isEmpty else { return acc }
        func tris(_ m: Mesh) -> [(Vec3, Vec3, Vec3)] {
            stride(from: 0, to: m.indices.count - 2, by: 3).map { (m.positions[Int(m.indices[$0])], m.positions[Int(m.indices[$0 + 1])], m.positions[Int(m.indices[$0 + 2])]) }
        }
        let res = CSG.apply(.intersect, tris(acc.mesh), tris(cutter.mesh))
        var out = MeshAcc()
        for t in res {
            let n = (t.1 - t.0).cross(t.2 - t.0)
            guard n.length > 1e-14 else { continue }
            let nn = n.normalized
            out.tri(t.0, t.1, t.2, nn, nn, nn)
        }
        // Feature edges: the profile outline on both faces and the edges across the wall at its corners.
        return out
    }

    /// Outline edges of the profiled wall (both faces and the corner edges across).
    static func profileEdges(_ g: WallGeom, f: WallFrame, zBase: Double) -> [[Vec3]] {
        guard let pr = g.profile, pr.count >= 3 else { return [] }
        var out: [[Vec3]] = []
        for t in [f.h, -f.h] { out.append((pr + [pr[0]]).map { let q = f.pt(min(max($0.x, 0), f.L), t); return Vec3(q.x, q.y, zBase + $0.y) }) }
        for p in pr { let a = f.pt(min(max(p.x, 0), f.L), f.h), b = f.pt(min(max(p.x, 0), f.L), -f.h); out.append([Vec3(a.x, a.y, zBase + p.y), Vec3(b.x, b.y, zBase + p.y)]) }
        return out
    }

    /// Profile presets: a gable rising to `peak` at the middle, or steps.
    static func gable(length L: Double, eave: Double, peak: Double) -> [Vec2] {
        [Vec2(0, 0), Vec2(L, 0), Vec2(L, eave), Vec2(L / 2, peak), Vec2(0, eave)]
    }
}
