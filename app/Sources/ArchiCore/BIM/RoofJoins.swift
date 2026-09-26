// Oanarina Archi Tool — GPL-3.0-or-later
// Roof join (BIM-059): one edge of a roof is extended until the roof runs into another roof, and everything of it
// below the other roof's top surface is cut away (Revit "Join/Unjoin Roof"), so a wing, porch or dormer roof meets the
// main roof along the true valley / intersection line. The join is associative (props roofJoin, roofJoinEdge) and is
// rebuilt from both roofs' current shapes; plan views draw the projected edges of the joined roof.
import Foundation

public enum RoofJoins {
    public static let key = "roofJoin", edgeKey = "roofJoinEdge"

    /// Outward unit normal and the two vertices of boundary edge k (boundary taken counter-clockwise).
    static func edge(_ b0: [Vec2], _ k: Int) -> (a: Int, b: Int, n: Vec2)? {
        guard b0.count >= 3 else { return nil }
        let ccw = GeometryOps.signedArea(b0) > 0
        let i = ((k % b0.count) + b0.count) % b0.count, j = (i + 1) % b0.count
        let d = (b0[j] - b0[i]).normalized
        guard d.length > 0.5 else { return nil }
        let n = ccw ? Vec2(d.y, -d.x) : Vec2(-d.y, d.x)
        return (i, j, n)
    }

    /// Index of the boundary edge nearest a point.
    public static func nearestEdge(_ b: [Vec2], to p: Vec2) -> Int? {
        guard b.count >= 3 else { return nil }
        func dist(_ i: Int) -> Double {
            let a = b[i], c = b[(i + 1) % b.count], d = c - a
            let t = max(0, min(1, (p - a).dot(d) / max(d.lengthSquared, 1e-18)))
            return p.distance(to: a + d * t)
        }
        return (0..<b.count).min { dist($0) < dist($1) }
    }

    /// Distance the edge must move out to pass right through the other roof's footprint (0 = it does not face it).
    static func reach(_ g: RoofGeom, edge k: Int, target: RoofGeom) -> Double {
        guard let e = edge(g.boundary, k) else { return 0 }
        let fp = RoofShapes.faces(target).footprint
        let base = g.boundary[e.a].dot(e.n)
        let far = fp.map { $0.dot(e.n) - base }.max() ?? 0
        return max(0, far)
    }

    /// Closed solids under the target roof's top surface: one prism per roof face, from far below up to the face.
    static func cutter(_ t: BIMElement, _ g: RoofGeom, doc: ArchiDocument) -> [MeshAcc] {
        let r = RoofShapes.faces(g)
        let elev = doc.level(t.level)?.elevation ?? 0
        let zb = elev + g.baseOffset
        let flat = g.kind == .flat || r.faces.allSatisfy { $0.grad.length < 1e-12 }
        let tv = flat ? max(g.thickness, 1e-3) : g.thickness / max(cos(rad(min(g.pitch, 85))), 0.05)
        let zLow = zb - 100_000
        var out: [MeshAcc] = []
        for f in r.faces where f.poly.count >= 3 {
            var acc = MeshAcc()
            var p = f.poly
            if GeometryOps.signedArea(p) < 0 { p.reverse() }
            let top = p.map { Vec3($0.x, $0.y, zb + f.height($0) + tv) }
            let bot = p.map { Vec3($0.x, $0.y, zLow) }
            acc.face(top, outward: .unitZ)
            acc.face(bot, outward: -Vec3.unitZ)
            for i in 0..<p.count {
                let j = (i + 1) % p.count
                let d = p[j] - p[i]
                acc.face([bot[i], bot[j], top[j], top[i]], outward: Vec3(d.y, -d.x, 0))
            }
            if !acc.mesh.isEmpty { out.append(acc) }
        }
        return out
    }

    /// Mesh groups of a roof joined to another: extended along the join edge, then trimmed by the other roof.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [MeshGroup]] = [:]

    static func groups(_ el: BIMElement, _ g: RoofGeom, elev: Double, doc: ArchiDocument) -> [MeshGroup]? {
        guard let ts = el.props[key], let tid = Int(ts.trimmingCharacters(in: CharacterSet(charactersIn: "#"))), tid != el.id,
              let t = doc.element(tid), case .roof = t.geometry else { return nil }
        // The CSG trim is costly: memoise on both roofs, their levels and the roof types / edges they use.
        let ck = "\(el)|\(t)|\(elev)|\(doc.level(t.level)?.elevation ?? 0)|\(doc.slabTypes.hashValue)|\(doc.entities.filter { Shafts.isShaft($0) }.hashValue)"
        lock.lock()
        if let c = cache[ck] { lock.unlock(); return c }
        lock.unlock()
        let r = computeGroups(el, g, elev: elev, doc: doc)
        lock.lock()
        if cache.count > 64 { cache.removeAll() }
        if let r = r { cache[ck] = r }
        lock.unlock()
        return r
    }

    static func computeGroups(_ el: BIMElement, _ g: RoofGeom, elev: Double, doc: ArchiDocument) -> [MeshGroup]? {
        guard let ts = el.props[key], let tid = Int(ts.trimmingCharacters(in: CharacterSet(charactersIn: "#"))), tid != el.id,
              let t = doc.element(tid), case .roof(let tg) = t.geometry,
              let k = el.props[edgeKey].flatMap(Int.init), let e = edge(g.boundary, k) else { return nil }
        let dist = reach(g, edge: k, target: tg)
        guard dist > 1e-9 else { return nil }
        var ext = g
        ext.boundary[e.a] = ext.boundary[e.a] + e.n * dist
        ext.boundary[e.b] = ext.boundary[e.b] + e.n * dist
        var eel = el; eel.geometry = .roof(ext); eel.props[key] = nil
        let cuts = cutter(t, tg, doc: doc)
        guard !cuts.isEmpty else { return nil }
        var out: [MeshGroup] = []
        for grp in RoofDetails.groups(eel, ext, elev: elev, doc: doc) {
            var a = MeshAcc(); a.mesh = grp.mesh
            var r = a
            for c in cuts { r = WallPlies.subtract(r, c) }
            // Keep only the pieces connected to the original roof: an edge run right through the other roof would
            // otherwise come out again beyond its ridge.
            let tris = connected(MeshTools.triangles(r.mesh), touching: g.boundary)
            guard !tris.isEmpty else { continue }
            r = MeshAcc()
            for t in tris { let n = (t.1 - t.0).cross(t.2 - t.0).normalized; r.tri(t.0, t.1, t.2, n, n, n) }
            let w = MeshTools.weld(tris, tolerance: 1e-6)
            r.edges = MeshTools.featureEdges(vertices: w.vertices, triangles: w.triangles, angle: 20)
            out.append(MeshGroup(id: el.id, kind: grp.kind, material: grp.material, mesh: r.mesh, edges: r.edges))
        }
        return out
    }

    /// Triangles of the connected pieces that reach inside the original footprint.
    static func connected(_ tris: [Tri3], touching boundary: [Vec2]) -> [Tri3] {
        guard !tris.isEmpty else { return [] }
        let w = MeshTools.weld(tris, tolerance: 1e-6)
        let n = w.triangles.count / 3
        var parent = Array(0..<w.vertices.count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for f in 0..<n { let a = find(w.triangles[3 * f]); parent[find(w.triangles[3 * f + 1])] = a; parent[find(w.triangles[3 * f + 2])] = a }
        var inner = boundary
        if GeometryOps.signedArea(inner) < 0 { inner.reverse() }
        inner = RG.offsetPolygon(inner, -1)
        var keep = Set<Int>()
        for (i, v) in w.vertices.enumerated() where inner.count >= 3 && GeometryOps.pointInPolygon(v.xy, inner) { keep.insert(find(i)) }
        guard !keep.isEmpty else { return tris }
        return (0..<n).filter { keep.contains(find(w.triangles[3 * $0])) }.map { (w.vertices[w.triangles[3 * $0]], w.vertices[w.triangles[3 * $0 + 1]], w.vertices[w.triangles[3 * $0 + 2]]) }
    }

    /// Plan projection of a joined roof: its projected (deduplicated) feature edges.
    static func planItems(_ el: BIMElement, _ g: RoofGeom, doc: ArchiDocument, color: RGBA) -> [DrawItem]? {
        let elev = doc.level(el.level)?.elevation ?? 0
        guard let gs = groups(el, g, elev: elev, doc: doc) else { return nil }
        var seen = Set<[Double]>()
        var out: [DrawItem] = []
        for grp in gs {
            for e in grp.edges where e.count >= 2 {
                for i in 0..<(e.count - 1) {
                    let a = e[i].xy, b = e[i + 1].xy
                    guard a.distance(to: b) > 1e-6 else { continue }
                    let key = (a.x < b.x || (a.x == b.x && a.y < b.y) ? [a.x, a.y, b.x, b.y] : [b.x, b.y, a.x, a.y]).map { ($0 * 100).rounded() / 100 }
                    if seen.insert(key).inserted { out.append(PlanRepresentation.stroke([a, b], color, PlanRepresentation.lwProj)) }
                }
            }
        }
        return out
    }

    public static func join(_ id: EntityID, edgeNear p: Vec2, to target: EntityID, doc: inout ArchiDocument) -> Bool {
        guard id != target, let i = doc.elementIndex(id), case .roof(let g) = doc.elements[i].geometry,
              case .roof(let tg)? = doc.element(target)?.geometry, let k = nearestEdge(g.boundary, to: p), reach(g, edge: k, target: tg) > 1e-9 else { return false }
        doc.elements[i].props[key] = "\(target)"; doc.elements[i].props[edgeKey] = "\(k)"
        return true
    }
    public static func unjoin(_ id: EntityID, doc: inout ArchiDocument) {
        guard let i = doc.elementIndex(id) else { return }
        doc.elements[i].props[key] = nil; doc.elements[i].props[edgeKey] = nil
    }
}

enum RoofJoinCommands {
    static var all: [CommandDef] { [roofJoin] }
    static var roofJoin: CommandDef {
        CommandDef("ROOFJOIN", aliases: ["JOINROOF", "UNJOINROOF", "ROOFJOINS"], category: "Architecture", summary: "Joins a roof to another: the picked edge is extended until the roof meets the other roof and the part below it is cut away (Unjoin restores it).") { ed in
            let k = try await ed.getKeyword("Roof join [Join/Unjoin]", ["Join", "Unjoin"], defaultValue: "Join") ?? "Join"
            let isRoof: (EntityID) -> Bool = { id in if case .roof? = ed.doc.element(id)?.geometry { return true }; return false }
            guard case .pick(let a) = try await ed.pickObject(k == "Join" ? "Select the roof edge to extend" : "Select a joined roof", filter: isRoof) else { return }
            if k == "Unjoin" { RoofJoins.unjoin(a.id, doc: &ed.doc); ed.print("Roof #\(a.id) unjoined."); return }
            let edgePoint = try await ed.getPoint("Specify a point on the edge to extend (Enter = the picked point)").point ?? a.point
            guard case .pick(let b) = try await ed.pickObject("Select the roof to join to", filter: { isRoof($0) && $0 != a.id }) else { return }
            guard RoofJoins.join(a.id, edgeNear: edgePoint, to: b.id, doc: &ed.doc) else { throw CommandError.invalid("That edge does not face the other roof.") }
            ed.print("Roof #\(a.id) joined to roof #\(b.id).")
        }
    }
}
