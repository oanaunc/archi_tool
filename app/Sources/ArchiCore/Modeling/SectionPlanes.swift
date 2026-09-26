// Oanarina Archi Tool — GPL-3.0-or-later
// Section plane objects (M3D-038): named cutting planes stored in the drawing as plan-trace polylines, a watertight
// half-space clipper with cap faces (clipped solids stay closed manifolds), and associative 2D section blocks.
import Foundation

/// Clips triangle meshes by a plane, removing the side the normal points to, and closes the cut with cap faces.
public enum PlaneClipper {
    /// Returns the part of `tris` on the non-positive side of the plane (point, normal), capped when `cap` is true.
    /// For a closed, consistently oriented input the result is again a closed manifold.
    public static func clip(_ tris: [(Vec3, Vec3, Vec3)], point o: Vec3, normal n0: Vec3, cap: Bool = true, tolerance: Double = 1e-7) -> [(Vec3, Vec3, Vec3)] {
        let n = n0.normalized
        guard n.length > 0.5 else { return tris }
        var scale = 1.0
        for t in tris { scale = max(scale, abs(t.0.x), abs(t.0.y), abs(t.0.z)) }
        let eps = tolerance * scale
        func d(_ p: Vec3) -> Double { let v = (p - o).dot(n); return abs(v) <= eps ? 0 : v }
        func snap(_ p: Vec3) -> Vec3 { p - n * (p - o).dot(n) }
        // Deterministic edge/plane intersection (same point for both triangles sharing the edge).
        func cut(_ a: Vec3, _ da: Double, _ b: Vec3, _ db: Double) -> Vec3 {
            let swap = (a.x, a.y, a.z) > (b.x, b.y, b.z)
            let (p, dp, q, dq) = swap ? (b, db, a, da) : (a, da, b, db)
            return snap(p + (q - p) * (dp / (dp - dq)))
        }
        var out: [(Vec3, Vec3, Vec3)] = []
        var capEdges: [(Vec3, Vec3)] = []
        for t in tris {
            let v = [t.0, t.1, t.2], ds = v.map(d)
            if ds.allSatisfy({ $0 <= 0 }) && !ds.allSatisfy({ $0 == 0 }) {
                let vv = zip(v, ds).map { $0.1 == 0 ? snap($0.0) : $0.0 }
                out.append((vv[0], vv[1], vv[2]))
                for i in 0..<3 where ds[i] == 0 && ds[(i + 1) % 3] == 0 { capEdges.append((vv[i], vv[(i + 1) % 3])) }
                continue
            }
            if ds.allSatisfy({ $0 >= 0 }) { continue }
            // Mixed: Sutherland–Hodgman against the half-space d <= 0.
            var poly: [(Vec3, Bool)] = []   // point, on-plane flag
            for i in 0..<3 {
                let a = v[i], b = v[(i + 1) % 3], da = ds[i], db = ds[(i + 1) % 3]
                if da <= 0 { poly.append((da == 0 ? snap(a) : a, da == 0)) }
                if (da < 0 && db > 0) || (da > 0 && db < 0) { poly.append((cut(a, da, b, db), true)) }
            }
            guard poly.count >= 3 else { continue }
            for k in 1..<(poly.count - 1) { out.append((poly[0].0, poly[k].0, poly[k + 1].0)) }
            for i in 0..<poly.count where poly[i].1 && poly[(i + 1) % poly.count].1 { capEdges.append((poly[i].0, poly[(i + 1) % poly.count].0)) }
        }
        guard cap, !capEdges.isEmpty else { return out }
        return out + capFaces(capEdges, normal: n, tolerance: eps * 1e-3 + 1e-12)
    }

    /// Cap triangles (facing `normal`) for boundary edges lying in the plane (given in the kept surface's winding).
    static func capFaces(_ edges: [(Vec3, Vec3)], normal n: Vec3, tolerance: Double) -> [(Vec3, Vec3, Vec3)] {
        let q = max(tolerance, 1e-12)
        var pts: [Vec3] = []
        var index: [[Int64]: Int] = [:]
        func vid(_ p: Vec3) -> Int {
            let k = [Int64((p.x / q).rounded()), Int64((p.y / q).rounded()), Int64((p.z / q).rounded())]
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                if let i = index[[k[0] + Int64(dx), k[1] + Int64(dy), k[2] + Int64(dz)]], pts[i].distance(to: p) <= q * 1.5 { return i }
            } } }
            pts.append(p); index[k] = pts.count - 1; return pts.count - 1
        }
        // Cap edges run opposite to the surface boundary; opposite pairs cancel (coplanar kept faces meeting at the plane).
        var directed: [Int: [Int]] = [:]
        var count: [[Int]: Int] = [:]
        for (a, b) in edges {
            let ia = vid(a), ib = vid(b)
            guard ia != ib else { continue }
            if let c = count[[ia, ib]], c > 0 { count[[ia, ib]] = c - 1; continue }
            count[[ib, ia], default: 0] += 1
        }
        // Sorted so the cap (loop starts, triangulation) is the same on every run.
        for (k, c) in count.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) where c > 0 { for _ in 0..<c { directed[k[0], default: []].append(k[1]) } }
        var loops: [[Int]] = []
        while let start = directed.filter({ !$0.value.isEmpty }).keys.min() {
            var loop = [start], cur = start
            var guardN = 0
            while guardN < 1_000_000 {
                guardN += 1
                guard var nx = directed[cur], !nx.isEmpty else { break }
                let nxt = nx.removeLast(); directed[cur] = nx
                if nxt == start { break }
                loop.append(nxt); cur = nxt
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        let (u, v) = Mesh.basis(n)
        func flat(_ l: [Int]) -> [Vec2] { l.map { Vec2(pts[$0].dot(u), pts[$0].dot(v)) } }
        // u × v = n, so loops wound counter-clockwise in (u, v) face along n: outers are CCW, holes CW.
        let outers = loops.filter { GeometryOps.signedArea(flat($0)) > 0 }
        let holes = loops.filter { GeometryOps.signedArea(flat($0)) < 0 }
        var holesOf: [[[Int]]] = Array(repeating: [], count: outers.count)
        for h in holes {
            let p = flat(h)[0]
            // Smallest containing outer.
            var best: Int?
            for (i, o) in outers.enumerated() where GeometryOps.pointInPolygon(p, flat(o)) {
                if best == nil || abs(GeometryOps.signedArea(flat(o))) < abs(GeometryOps.signedArea(flat(outers[best!]))) { best = i }
            }
            if let b = best { holesOf[b].append(h) }
        }
        var out: [(Vec3, Vec3, Vec3)] = []
        for (i, o) in outers.enumerated() {
            let r = Triangulator.triangulateWithPoints(flat(o), holes: holesOf[i].map(flat))
            // Map triangulator points back to 3D vertices (they are the input points, in bridging order).
            var lookup: [Vec2: Vec3] = [:]
            for l in [o] + holesOf[i] { for k in l { lookup[Vec2(pts[k].dot(u), pts[k].dot(v))] = pts[k] } }
            for t in r.triangles {
                guard let a = lookup[r.points[t.0]], let b = lookup[r.points[t.1]], let c = lookup[r.points[t.2]] else { continue }
                // Orientation from the flattened triangle; sliver triangles over collinear boundary points (edge/plane
                // hits on triangle diagonals) are kept, since dropping them would open the cap along those edges.
                let fn = (b - a).cross(c - a)
                let a2 = (r.points[t.1] - r.points[t.0]).cross(r.points[t.2] - r.points[t.0])
                let facing = fn.length > 1e-14 ? fn.dot(n) >= 0 : a2 >= 0
                out.append(facing ? (a, b, c) : (a, c, b))
            }
        }
        return out
    }

    /// Clips a mesh (flat-shaded result; cap faces use the plane normal).
    public static func clip(mesh: Mesh, point: Vec3, normal: Vec3, cap: Bool = true) -> Mesh {
        var acc = MeshAcc()
        for t in clip(MeshTools.triangles(mesh), point: point, normal: normal, cap: cap) {
            let fn = (t.1 - t.0).cross(t.2 - t.0).normalized
            acc.tri(t.0, t.1, t.2, fn, fn, fn)
        }
        return acc.mesh
    }

    /// Clips a solid; nil when nothing is left.
    public static func clip(_ s: SolidGeom, point: Vec3, normal: Vec3) -> SolidGeom? {
        let r = clip(MeshTools.triangles(MeshTools.mesh(of: s)), point: point, normal: normal)
        guard !r.isEmpty else { return nil }
        return MeshTools.solid(from: r, tolerance: 1e-6)
    }

    /// True when every edge of the welded triangle set is shared by exactly two triangles with opposite directions.
    public static func isClosedManifold(_ tris: [(Vec3, Vec3, Vec3)], tolerance: Double = 1e-6) -> Bool {
        let w = MeshTools.weld(tris, tolerance: tolerance)
        guard !w.triangles.isEmpty else { return false }
        var e: [[Int]: Int] = [:]
        var i = 0
        while i + 2 < w.triangles.count {
            let a = w.triangles[i], b = w.triangles[i + 1], c = w.triangles[i + 2]
            for (p, q) in [(a, b), (b, c), (c, a)] { e[[p, q], default: 0] += 1 }
            i += 3
        }
        for (k, c) in e { if c != 1 || e[[k[1], k[0]]] != 1 { return false } }
        return true
    }
}

/// Section plane objects: a polyline trace a → b on layer A-SECT-PLANE with props["sectionPlane"] = name. The plane is
/// vertical through the trace; the side to the right of a → b is removed and the view looks to the left (flip reverses).
public enum SectionPlaneObjects {
    public static let layer = "A-SECT-PLANE"

    public struct Plane: Hashable {
        public var id: EntityID
        public var name: String
        /// Trace in viewing order (flip already applied): the view looks to the left of a → b.
        public var a: Vec2, b: Vec2
        public var live: Bool
        public var includeModel: Bool
        public var block: String?
        /// A point on the plane and the normal of the removed side.
        public var point: Vec3 { Vec3(a.x, a.y, 0) }
        public var normal: Vec3 { let d = (b - a).normalized; return Vec3(d.y, -d.x, 0) }
        /// "on;x,y,z;nx,ny,nz" (the SECTIONPLANE variable format of the 3D viewport).
        public var viewportSpec: String {
            let p = point, n = normal
            return (live ? "on" : "off") + ";" + [p.x, p.y, p.z].map { fmt($0, 3) }.joined(separator: ",") + ";" + [n.x, n.y, n.z].map { fmt($0, 6) }.joined(separator: ",")
        }
        var traceSpec: String { "solidsection:\(fmt(a.x, 6)):\(fmt(a.y, 6)):\(fmt(b.x, 6)):\(fmt(b.y, 6)):\(includeModel ? 1 : 0)" }
    }

    public static func plane(_ e: Entity) -> Plane? {
        guard let name = e.props["sectionPlane"], case .polyline(let pl) = e.geometry, pl.vertices.count >= 2 else { return nil }
        var a = pl.vertices[0].p, b = pl.vertices[pl.vertices.count - 1].p
        guard a.distance(to: b) > 1e-9 else { return nil }
        if e.props["sectionFlip"] == "1" { swap(&a, &b) }
        return Plane(id: e.id, name: name, a: a, b: b, live: e.props["sectionLive"] == "1", includeModel: e.props["sectionModel"] == "1", block: e.props["sectionBlock"])
    }

    public static func all(_ doc: ArchiDocument) -> [Plane] { doc.entities.compactMap(plane) }
    public static func named(_ n: String, _ doc: ArchiDocument) -> Plane? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    /// Adds a section plane object through a → b. Returns its id.
    @discardableResult
    public static func add(_ doc: inout ArchiDocument, name: String? = nil, a: Vec2, b: Vec2, includeModel: Bool = false) -> EntityID? {
        guard a.distance(to: b) > 1e-9 else { return nil }
        doc.ensureLayer(layer)
        var k = all(doc).count + 1
        while named("SP\(k)", doc) != nil { k += 1 }
        let id = doc.add(.polyline(PolylineGeom(points: [a, b])), layer: layer)
        if let i = doc.entityIndex(id) {
            doc.entities[i].props["sectionPlane"] = name ?? "SP\(k)"
            doc.entities[i].props["sectionModel"] = includeModel ? "1" : "0"
        }
        return id
    }

    /// Makes one plane live (others off) and mirrors it into the 3D viewport's SECTIONPLANE variable; nil turns all off.
    public static func setLive(_ doc: inout ArchiDocument, _ id: EntityID?) {
        for i in doc.entities.indices where doc.entities[i].props["sectionPlane"] != nil {
            doc.entities[i].props["sectionLive"] = doc.entities[i].id == id ? "1" : nil
            doc.entities[i].props["sectionLiveSpec"] = nil
        }
        if let id = id, let i = doc.entityIndex(id), let p = plane(doc.entities[i]) {
            doc.variables["SECTIONPLANE"] = p.viewportSpec
            doc.entities[i].props["sectionLiveSpec"] = p.viewportSpec
        }
        else if let v = doc.variables["SECTIONPLANE"], v.hasPrefix("on") { doc.variables["SECTIONPLANE"] = "off" + v.dropFirst(2) }
    }

    public static func flip(_ doc: inout ArchiDocument, _ id: EntityID) {
        guard let i = doc.entityIndex(id) else { return }
        doc.entities[i].props["sectionFlip"] = doc.entities[i].props["sectionFlip"] == "1" ? nil : "1"
    }

    /// The building/solid meshes with the live plane applied (what the 3D view shows). Unchanged without a live plane.
    public static func clippedModel(_ doc: ArchiDocument, groups: [MeshGroup]? = nil) -> [MeshGroup] {
        let gs = groups ?? MeshBuilder.build(doc: doc)
        guard let p = all(doc).first(where: \.live) else { return gs }
        return gs.compactMap { g in
            var o = g
            o.mesh = PlaneClipper.clip(mesh: g.mesh, point: p.point, normal: p.normal)
            o.edges = g.edges.compactMap { line in
                let kept = line.filter { ($0 - p.point).dot(p.normal) <= 1e-6 }
                return kept.count >= 2 ? kept : nil
            }
            return o.mesh.isEmpty ? nil : o
        }
    }

    /// Cuts the given solids with the plane, keeping the viewed side (closed manifolds). Returns the ids changed.
    @discardableResult
    public static func slice(_ doc: inout ArchiDocument, _ planeID: EntityID, solids ids: [EntityID]) -> [EntityID] {
        guard let e = doc.entity(planeID), let p = plane(e) else { return [] }
        var out: [EntityID] = []
        for id in ids {
            guard let i = doc.entityIndex(id), case .solid(let s) = doc.entities[i].geometry else { continue }
            let b = MeshTools.mesh(of: s).bounds
            let side = [b.min.x, b.max.x].flatMap { x in [b.min.y, b.max.y].map { y in (Vec3(x, y, 0) - p.point).dot(p.normal) } }
            if side.allSatisfy({ $0 <= 1e-9 }) { continue }                       // entirely kept
            if side.allSatisfy({ $0 >= -1e-9 }) { doc.entities.remove(at: i); out.append(id); continue }   // entirely removed
            if let c = PlaneClipper.clip(s, point: p.point, normal: p.normal) { doc.entities[i].geometry = .solid(c); out.append(id) }
        }
        return out
    }

    /// Generates (or regenerates) the plane's 2D section block. Returns the block name.
    @discardableResult
    public static func generate(_ doc: inout ArchiDocument, _ planeID: EntityID) -> String? {
        guard let e = doc.entity(planeID), let p = plane(e) else { return nil }
        let name = p.block ?? "SECTION-\(p.name.uppercased())"
        guard let bn = SolidSections.makeBlock(&doc, a: p.a, b: p.b, name: name, includeModel: p.includeModel) else { return nil }
        if let i = doc.entityIndex(planeID) { doc.entities[i].props["sectionBlock"] = bn }
        return bn
    }

    /// Keeps generated section blocks and the live viewport plane in step with moved/flipped planes.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for p in all(doc) {
            if let bn = p.block, let blk = doc.blocks[bn], blk.description != "view:" + p.traceSpec {
                if SolidSections.makeBlock(&doc, a: p.a, b: p.b, name: bn, includeModel: p.includeModel) != nil { changed = true }
                else { doc.blocks[bn]?.description = "view:" + p.traceSpec; changed = true }
            }
            if p.live, let i = doc.entityIndex(p.id) {
                let applied = doc.entities[i].props["sectionLiveSpec"]
                if doc.variables["SECTIONPLANE"] != applied {
                    // The 3D view's plane was changed elsewhere (SECTIONPLANE command, clip panel): this object is no longer live.
                    doc.entities[i].props["sectionLive"] = nil; doc.entities[i].props["sectionLiveSpec"] = nil; changed = true
                } else if applied != p.viewportSpec {
                    doc.variables["SECTIONPLANE"] = p.viewportSpec; doc.entities[i].props["sectionLiveSpec"] = p.viewportSpec; changed = true
                }
            }
        }
        return changed
    }

    static func hasObjects(_ doc: ArchiDocument) -> Bool { doc.entities.contains { $0.props["sectionPlane"] != nil } }
}
