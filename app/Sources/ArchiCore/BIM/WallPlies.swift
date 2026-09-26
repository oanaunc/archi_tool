// Oanarina Archi Tool — GPL-3.0-or-later
// Compound walls in 3D (BIM-014): the wall type's plies become separate solids, each with its own material, by clipping
// the mitred wall pieces to the ply bands; reveals (BIM-021) are grooves subtracted from the wall faces.
import Foundation

enum WallPlies {
    /// Ply bands across the wall, left face (t = +h) to right face (t = −h). One band (nil material) for single-ply or
    /// untyped walls. The outer bands extend beyond the faces so clipping never leaves slivers along them.
    static func bands(_ g: WallGeom, doc: ArchiDocument, halfThickness h: Double) -> [(material: String?, thi: Double, tlo: Double)] {
        // Coarse detail level (DOC-023): one solid.
        guard FamilyVisibility.level(doc) != "coarse",
              let tn = g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), wt.thickness > 0, wt.plies.count > 1 else { return [(nil, h, -h)] }
        let k = 2 * h / wt.thickness
        var t = h
        var out: [(material: String?, thi: Double, tlo: Double)] = []
        for p in wt.plies where p.thickness > 0 {
            let nt = t - p.thickness * k
            out.append((p.material, t, nt)); t = nt
        }
        guard out.count > 1 else { return [(out.first?.material, h, -h)] }
        let pad = max(h, 1)
        out[0].thi = h + pad
        out[out.count - 1].tlo = -h - pad
        return out
    }

    /// Band polygon between offsets tlo…thi along the whole wall, extended past both ends.
    static func band(_ f: WallFrame, tlo: Double, thi: Double) -> [Vec2] {
        var ext = 20 * f.h + 1
        if f.isCurved {
            // Keep the extended arc well below a full turn.
            let circ = 2 * Double.pi * max(f.arcR, 1e-6)
            ext = max(0, min(ext, (circ - f.L) * 0.4))
        }
        return f.face(thi, -ext, f.L + ext) + f.face(tlo, -ext, f.L + ext).reversed()
    }

    /// Parts of a plan polygon inside the ply band (outer loops, CCW).
    static func clip(_ poly: [Vec2], f: WallFrame, tlo: Double, thi: Double) -> [[Vec2]] {
        guard poly.count >= 3, thi - tlo > 1e-9 else { return [] }
        var b = band(f, tlo: tlo, thi: thi)
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        var p = poly
        if GeometryOps.signedArea(p) < 0 { p.reverse() }
        return PolygonBoolean.apply(.intersect, [p], [b]).filter { GeometryOps.signedArea($0) > 1e-9 }
    }

    /// Groove solid of a reveal along one face: the profile mirrored into the wall, protruding slightly out of the face
    /// so the subtraction is clean; run over the whole wall length (and a little beyond) at the reveal's height.
    static func revealCutter(_ sw: WallSweep, _ f: WallFrame, z0: Double, ctx: BIMContext, into acc: inout MeshAcc, edges: inout [[Vec3]]) {
        let side: Double = sw.side >= 0 ? 1 : -1
        let e = max(min(5 / ctx.doc.units.mm, sw.depth), 1e-4)
        let depth = min(max(sw.depth, 1e-4), 2 * f.h * 0.9)
        let profile = sw.outline.map { (x: $0.x, z: $0.z) }.map { p -> Vec2 in
            let x = p.x <= 1e-9 ? -e : min(p.x, depth)
            return Vec2(-x, p.z)
        }
        let ext = f.isCurved ? 0 : 2 * f.h + 1
        var pts = f.face(side * f.h, -ext, f.L + ext)
        if side < 0 { pts.reverse() }
        let path = pts.map { Vec3($0.x, $0.y, z0 + sw.elevation) }
        SweepMesh.sweep(profile, along: path, into: &acc)
        // Groove lines on the face (drawn as feature edges of the wall).
        for z in [sw.elevation, sw.elevation + sw.height] {
            edges.append(f.face(side * f.h, 0, f.L).map { Vec3($0.x, $0.y, z0 + z) })
        }
    }

    /// Mesh of `a` minus `cutter` (BSP CSG); `a`'s feature edges plus `extraEdges` are kept.
    static func subtract(_ a: MeshAcc, _ cutter: MeshAcc, extraEdges: [[Vec3]] = []) -> MeshAcc {
        guard !a.mesh.isEmpty, !cutter.mesh.isEmpty else { return a }
        func tris(_ m: Mesh) -> [(Vec3, Vec3, Vec3)] {
            stride(from: 0, to: m.indices.count - 2, by: 3).map { (m.positions[Int(m.indices[$0])], m.positions[Int(m.indices[$0 + 1])], m.positions[Int(m.indices[$0 + 2])]) }
        }
        let res = CSG.apply(.subtract, tris(a.mesh), tris(cutter.mesh))
        guard !res.isEmpty else { return a }
        var out = MeshAcc()
        for t in res {
            let n = (t.1 - t.0).cross(t.2 - t.0)
            guard n.length > 1e-14 else { continue }
            let nn = n.normalized
            out.tri(t.0, t.1, t.2, nn, nn, nn)
        }
        out.edges = a.edges + extraEdges
        return out
    }
}
