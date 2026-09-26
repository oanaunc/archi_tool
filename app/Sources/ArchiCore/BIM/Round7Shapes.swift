// Oanarina Archi Tool — GPL-3.0-or-later
// Geometry of round 7 element forms: roofs by extrusion (BIM-057), shape-edited flat roofs (BIM-063), stairs by sketch
// (BIM-066) and slab edges (BIM-051). Roof forms plug into RoofShapes.faces and stairs into StairShapes.layout, so
// plans, 3D, sections, wall attachment and schedules all use them.
import Foundation

enum Round7Shapes {
    // MARK: Roof by extrusion

    /// Planar roof faces (heights above the eave) for an extrusion profile: one strip per profile segment.
    static func extrusionFaces(_ ex: RoofExtrusion) -> (boundary: [Vec2], footprint: [Vec2], faces: [RoofFace])? {
        let fp = ex.footprint
        guard fp.count == 4 else { return nil }
        let pts = ex.profile.sorted { $0.x < $1.x }
        let u = Vec2.polar(1, ex.direction), n = u.perp
        var faces: [RoofFace] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            guard b.x - a.x > 1e-9 else { continue }
            let s = (b.y - a.y) / (b.x - a.x)
            let poly = [ex.origin + u * a.x, ex.origin + u * b.x, ex.origin + u * b.x + n * ex.depth, ex.origin + u * a.x + n * ex.depth]
            faces.append(RoofFace(poly: poly, grad: u * s, c: a.y - s * (ex.origin.dot(u) + a.x)))
        }
        return faces.isEmpty ? nil : (fp, fp, faces)
    }

    // MARK: Shape-edited flat roofs (TIN)

    /// Triangulated surface over a polygon with interior points: plane faces through the vertex heights.
    static func tinFaces(_ outer0: [Vec2], points: [Vec3]) -> [RoofFace] {
        var outer = RG.dedupe(outer0, closed: true)
        guard outer.count >= 3 else { return [] }
        if GeometryOps.signedArea(outer) < 0 { outer.reverse() }
        let tol = max(BBox2(points: outer).width, BBox2(points: outer).height) * 1e-7
        var verts = outer
        var h = [Double](repeating: 0, count: outer.count)
        var tris = Triangulator.triangulate(outer, holes: []).map { [$0.0, $0.1, $0.2] }
        for sp in points {
            let p = sp.xy
            if let k = verts.firstIndex(where: { $0.distance(to: p) <= tol * 10 }) { h[k] = sp.z; continue }
            // Every triangle containing the point (two when it lies on a shared edge) is split, so the surface stays
            // continuous; zero-area pieces are dropped.
            func onOrIn(_ t: [Int]) -> Bool {
                let q = t.map { verts[$0] }
                return GeometryOps.pointInPolygon(p, q) || (0..<3).contains { GeometryOps.distance(from: p, toPolyline: [q[$0], q[($0 + 1) % 3]]) <= tol * 10 }
            }
            let hit = tris.indices.filter { onOrIn(tris[$0]) }
            guard !hit.isEmpty else { continue }
            verts.append(p); h.append(sp.z)
            let k = verts.count - 1
            var keep: [[Int]] = []
            for (ti, t) in tris.enumerated() {
                guard hit.contains(ti) else { keep.append(t); continue }
                for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] where abs((verts[b] - verts[a]).cross(p - verts[a])) > tol * max((verts[b] - verts[a]).length, 1) {
                    keep.append([a, b, k])
                }
            }
            tris = keep
        }
        return tris.compactMap { t in
            let P = t.map { Vec3(verts[$0].x, verts[$0].y, h[$0]) }
            let nrm = (P[1] - P[0]).cross(P[2] - P[0])
            guard abs(nrm.z) > 1e-12 else { return nil }
            // Plane z = gx x + gy y + c.
            let g = Vec2(-nrm.x / nrm.z, -nrm.y / nrm.z)
            let c = P[0].z - g.dot(P[0].xy)
            var poly = t.map { verts[$0] }
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            return RoofFace(poly: poly, grad: g, c: c)
        }
    }

    // MARK: Stair by sketch

    /// Layout of a sketched stair: one tread between consecutive risers, the walking line through riser midpoints.
    static func sketchLayout(_ risers: [[Vec2]]) -> StairLayout? {
        let rs = risers.filter { $0.count >= 2 && $0[0].distance(to: $0[1]) > 1e-9 }
        guard rs.count >= 2 else { return nil }
        var treads: [StairTread] = []
        for i in 0..<(rs.count - 1) {
            let a = rs[i]
            var b = rs[i + 1]
            // Keep both risers pointing the same way.
            if (a[1] - a[0]).dot(b[1] - b[0]) < 0 { b.reverse() }
            var poly = [a[0], a[1], b[1], b[0]]
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            treads.append(StairTread(poly: poly, step: i + 1, landing: false))
        }
        let walk = rs.map { ($0[0] + $0[1]) / 2 }
        return StairLayout(treads: treads, walk: walk, flights: [])
    }

    /// Going of each tread on the walking line (between riser midpoints).
    static func goings(_ risers: [[Vec2]]) -> [Double] {
        let m = risers.map { ($0[0] + $0[1]) / 2 }
        return (0..<max(m.count - 1, 0)).map { m[$0].distance(to: m[$0 + 1]) }
    }

    /// Rule check of a sketched stair: riser height, going, 2R + G (550–700 mm) and uneven goings.
    public static func check(_ g: StairGeom, units: Units, maxRiser: Double = 190, minGoing: Double = 250) -> [String] {
        guard let rs = g.sketchRisers, rs.count >= 2 else { return ["The sketch needs at least two risers."] }
        let mm = units.mm
        let r = g.totalRise / Double(rs.count) * mm
        let gs = goings(rs).map { $0 * mm }
        var out: [String] = []
        if r > maxRiser + 1e-9 { out.append("Riser \(fmt(r, 1)) mm exceeds \(fmt(maxRiser)) mm.") }
        if let gmin = gs.min(), gmin < minGoing - 1e-9 { out.append("Going \(fmt(gmin, 1)) mm is below \(fmt(minGoing)) mm.") }
        for gg in gs where 2 * r + gg < 550 || 2 * r + gg > 700 { out.append("2R+G = \(fmt(2 * r + gg, 1)) mm is outside 550–700 mm."); break }
        if let a = gs.min(), let b = gs.max(), b - a > 5 { out.append("Goings vary by \(fmt(b - a, 1)) mm on the walking line.") }
        return out
    }

    // MARK: Slab edges

    /// Solid of each slab edge profile (upstand inside the edge on top, fascia outside hanging down).
    static func slabEdgeGroups(_ el: BIMElement, _ g: SlabGeom, elev: Double) -> [MeshGroup] {
        guard let es = g.edges, !es.isEmpty else { return [] }
        var b = RG.dedupe(g.boundary, closed: true)
        guard b.count >= 3 else { return [] }
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        var out: [MeshGroup] = []
        for e in es {
            var acc = MeshAcc()
            for (a, c, inward) in edgeStrips(b, e) {
                let top = elev + g.topHeight(at: (a + c) / 2)
                let z0 = e.kind == "fascia" ? top - e.height : top, z1 = e.kind == "fascia" ? top : top + e.height
                acc.prism([a, c, c + inward * e.width * (e.kind == "fascia" ? -1 : 1), a + inward * e.width * (e.kind == "fascia" ? -1 : 1)], z0: z0, z1: z1)
            }
            if let grp = acc.group(el.id, "slabEdge", e.material ?? el.material ?? "Concrete") { out.append(grp) }
        }
        return out
    }

    /// Edge segments (a, b, inward normal) an edge definition applies to (CCW boundary).
    static func edgeStrips(_ b: [Vec2], _ e: SlabEdge) -> [(Vec2, Vec2, Vec2)] {
        let idx = e.edge < 0 ? Array(b.indices) : [((e.edge % b.count) + b.count) % b.count]
        return idx.map { i in let a = b[i], c = b[(i + 1) % b.count]; return (a, c, (c - a).normalized.perp) }
    }

    /// Plan outlines of the slab edges.
    static func slabEdgePlan(_ g: SlabGeom) -> [[Vec2]] {
        guard let es = g.edges, !es.isEmpty else { return [] }
        var b = RG.dedupe(g.boundary, closed: true)
        guard b.count >= 3 else { return [] }
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        return es.flatMap { e in edgeStrips(b, e).map { (a, c, n) in
            let s = e.kind == "fascia" ? -1.0 : 1.0
            return [a, c, c + n * e.width * s, a + n * e.width * s]
        } }
    }
}
