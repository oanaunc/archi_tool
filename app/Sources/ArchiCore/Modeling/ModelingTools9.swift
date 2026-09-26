// Oanarina Archi Tool — GPL-3.0-or-later
// SketchUp-style modelling aids: paint bucket (materials by click, with sampling; M3D-105), soften/smooth edges
// (M3D-101) and tape measure with guides and protractor (M3D-104).
import Foundation

// MARK: - Soft edges

public enum SoftEdges {
    /// Smooths shading across edges whose faces meet at less than `angle` degrees and hides those edges.
    static func apply(_ acc: inout MeshAcc, angle: Double) {
        let m = acc.mesh
        let nt = m.indices.count / 3
        guard nt > 0 else { return }
        let b = m.bounds
        let q = max(max(b.size.x, b.size.y, b.size.z), 1) * 1e-7
        func key(_ v: Vec3) -> [Int64] { [Int64((v.x / q).rounded()), Int64((v.y / q).rounded()), Int64((v.z / q).rounded())] }
        var pos: [Vec3] = [], fn: [Vec3] = [], uv: [Vec2] = []
        pos.reserveCapacity(nt * 3)
        for k in 0..<nt {
            let ids = (0..<3).map { Int(m.indices[3 * k + $0]) }
            let a = m.positions[ids[0]], bb = m.positions[ids[1]], c = m.positions[ids[2]]
            pos += [a, bb, c]
            fn.append((bb - a).cross(c - a))   // area-weighted
            for i in ids { uv.append(i < m.uvs.count ? m.uvs[i] : .zero) }
        }
        var byKey: [[Int64]: [Int]] = [:]
        for k in 0..<nt { for j in 0..<3 { byKey[key(pos[3 * k + j]), default: []].append(k) } }
        let cosA = cos(angle * .pi / 180)
        var out = Mesh()
        out.positions = pos; out.uvs = uv
        out.normals = (0..<(nt * 3)).map { c in
            let k = c / 3, own = fn[k].normalized
            var s = Vec3.zero
            for o in Set(byKey[key(pos[c])] ?? [k]) where fn[o].normalized.dot(own) >= cosA { s = s + fn[o] }
            let n = s.normalized
            return n.length > 0.5 ? n : own
        }
        out.indices = (0..<UInt32(nt * 3)).map { $0 }
        acc.mesh = out
        let w = MeshTools.weld(MeshTools.triangles(out), tolerance: q)
        acc.edges = MeshTools.featureEdges(vertices: w.vertices, triangles: w.triangles, angle: angle)
    }
}

// MARK: - Intersect faces (M3D-100)

public enum FaceIntersection {
    static func bbox(_ t: Tri3) -> BBox3 { var b = BBox3.empty; b.add(t.0); b.add(t.1); b.add(t.2); return b }

    /// Points where triangle `t` crosses the plane n·x = d (vertices on the plane included).
    static func crossing(_ t: Tri3, _ n: Vec3, _ d: Double, eps: Double) -> [Vec3] {
        let p = [t.0, t.1, t.2]
        let s = p.map { n.dot($0) - d }
        var out: [Vec3] = []
        for i in 0..<3 {
            let j = (i + 1) % 3
            if abs(s[i]) <= eps { out.append(p[i]) }
            if (s[i] > eps && s[j] < -eps) || (s[i] < -eps && s[j] > eps) { out.append(p[i] + (p[j] - p[i]) * (s[i] / (s[i] - s[j]))) }
        }
        return out
    }

    /// Intersection segment of two triangles (nil when they do not cross or are coplanar).
    public static func segment(_ a: Tri3, _ b: Tri3, eps: Double) -> (Vec3, Vec3)? {
        let na = (a.1 - a.0).cross(a.2 - a.0).normalized, nb = (b.1 - b.0).cross(b.2 - b.0).normalized
        guard na.length > 0.5, nb.length > 0.5 else { return nil }
        let dir = na.cross(nb)
        guard dir.length > 1e-9 else { return nil }   // parallel or coplanar
        let da = na.dot(a.0), db = nb.dot(b.0)
        let pa = crossing(a, nb, db, eps: eps), pb = crossing(b, na, da, eps: eps)
        guard pa.count >= 2, pb.count >= 2 else { return nil }
        let D = dir.normalized
        func span(_ ps: [Vec3]) -> (Vec3, Vec3, Double, Double) {
            let lo = ps.min { D.dot($0) < D.dot($1) }!, hi = ps.max { D.dot($0) < D.dot($1) }!
            return (lo, hi, D.dot(lo), D.dot(hi))
        }
        let (a0, a1, ta0, ta1) = span(pa), (b0, b1, tb0, tb1) = span(pb)
        let t0 = max(ta0, tb0), t1 = min(ta1, tb1)
        guard t1 - t0 > eps else { return nil }
        let p0 = ta0 >= tb0 ? a0 : b0, p1 = ta1 <= tb1 ? a1 : b1
        return (p0, p1)
    }

    /// Segments where the surfaces of two solids cross.
    public static func segments(_ a: [Tri3], _ b: [Tri3]) -> [(Vec3, Vec3)] {
        var box = BBox3.empty
        for t in a + b { box.add(t.0); box.add(t.1); box.add(t.2) }
        guard !box.isEmpty else { return [] }
        let eps = max(box.size.x, box.size.y, box.size.z, 1) * 1e-9
        let bb = b.map(bbox)
        var out: [(Vec3, Vec3)] = []
        for ta in a {
            let ba = bbox(ta)
            for (k, tb) in b.enumerated() {
                let q = bb[k]
                guard !(ba.max.x < q.min.x - eps || q.max.x < ba.min.x - eps || ba.max.y < q.min.y - eps || q.max.y < ba.min.y - eps || ba.max.z < q.min.z - eps || q.max.z < ba.min.z - eps) else { continue }
                if let s = segment(ta, tb, eps: eps) { out.append(s) }
            }
        }
        return out
    }

    /// Chains segments into polylines (closed loops repeat their first point).
    public static func chain(_ segs: [(Vec3, Vec3)], tolerance tol: Double) -> [[Vec3]] {
        let q = max(tol, 1e-12)
        func key(_ v: Vec3) -> [Int64] { [Int64((v.x / q).rounded()), Int64((v.y / q).rounded()), Int64((v.z / q).rounded())] }
        var adj: [[Int64]: [Int]] = [:]
        var pts: [[Int64]: Vec3] = [:]
        for (i, s) in segs.enumerated() {
            let ka = key(s.0), kb = key(s.1)
            guard ka != kb else { continue }
            adj[ka, default: []].append(i); adj[kb, default: []].append(i)
            pts[ka] = s.0; pts[kb] = s.1
        }
        var used = Set<Int>()
        var out: [[Vec3]] = []
        func walk(from start: [Int64]) {
            var line = [pts[start]!], cur = start
            while let e = adj[cur]?.first(where: { !used.contains($0) }) {
                used.insert(e)
                let ka = key(segs[e].0), kb = key(segs[e].1)
                cur = ka == cur ? kb : ka
                line.append(pts[cur]!)
            }
            if line.count >= 2 { out.append(line) }
        }
        // Open chains first (from their ends), then closed loops.
        for (k, es) in adj where es.count == 1 && !used.contains(es[0]) { walk(from: k) }
        for (i, s) in segs.enumerated() where !used.contains(i) && key(s.0) != key(s.1) { walk(from: key(s.0)) }
        return out
    }

    public static func curves(_ a: SolidGeom, _ b: SolidGeom) -> [[Vec3]] {
        let ta = SolidCheck.triangles(a), tb = SolidCheck.triangles(b)
        var box = BBox3.empty
        for t in ta { box.add(t.0) }
        return chain(segments(ta, tb), tolerance: max(box.size.x, box.size.y, box.size.z, 1) * 1e-7)
    }
}

// MARK: - Projection of external geometry (M3D-086)

public enum ProjectedGeometry {
    public static let prop = "projectedFrom"
    static let stampProp = "projectedStamp"

    /// Plan outline (outer loops and holes) of a solid: the union of its upward-facing triangles projected on XY.
    public static func outline(_ s: SolidGeom) -> [[Vec2]] {
        var tris: [[Vec2]] = []
        for t in SolidCheck.triangles(s) {
            let n = (t.1 - t.0).cross(t.2 - t.0)
            guard n.z > 1e-12 else { continue }
            tris.append([t.0.xy, t.1.xy, t.2.xy])
        }
        guard !tris.isEmpty, tris.count <= 20_000 else { return [] }
        // Balanced pairwise union keeps the intermediate regions small.
        var parts: [[[Vec2]]] = tris.map { [$0] }
        while parts.count > 1 {
            var next: [[[Vec2]]] = []
            var i = 0
            while i < parts.count {
                if i + 1 < parts.count { next.append(PolygonBoolean.apply(.union, parts[i], parts[i + 1])) } else { next.append(parts[i]) }
                i += 2
            }
            parts = next
        }
        return PolygonBoolean.normalize(parts[0]).map { CommandHelpers.simplify($0) }.filter { $0.count >= 3 }
    }

    static func stamp(_ s: SolidGeom) -> String {
        let b = ModelingCommands.bounds(s)
        return [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z, CSG.volume(s)].map { fmt($0, 3) }.joined(separator: ",")
    }

    /// Projected entities for a solid (closed polylines at the given elevation, tagged with their source).
    public static func entities(of id: EntityID, _ s: SolidGeom, layer: String, elevation z: Double) -> [Entity] {
        outline(s).map { loop in
            var e = Entity(layer: layer, geometry: .polyline(PolylineGeom(points: loop, closed: true)))
            e.props[prop] = "\(id)"; e.props[stampProp] = stamp(s); e.props["elevation"] = fmt(z)
            return e
        }
    }

    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.entities.contains { $0.props[prop] != nil } }

    /// Re-projects the outlines of solids that changed (projections of deleted solids stay as plain geometry).
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        let groups = Dictionary(grouping: doc.entities.filter { $0.props[prop] != nil }, by: { $0.props[prop]! })
        var changed = false
        for (src, ents) in groups {
            guard let sid = EntityID(src), let s = ModelingCommands.solidOf(doc, sid) else { continue }
            let st = stamp(s)
            guard ents.contains(where: { $0.props[stampProp] != st }) else { continue }
            let first = ents[0]
            let z = first.props["elevation"].flatMap(Double.init) ?? 0
            var fresh = entities(of: sid, s, layer: first.layer, elevation: z)
            let ids = Set(ents.map(\.id))
            // Keep the ids of the existing projections (sketch features refer to them).
            for k in fresh.indices { fresh[k].id = k < ents.count ? ents[k].id : 0; fresh[k].color = first.color }
            let at = doc.entities.firstIndex { ids.contains($0.id) } ?? doc.entities.count
            doc.entities.removeAll { ids.contains($0.id) }
            var insert = at
            for e in fresh {
                if e.id == 0 { _ = doc.add(e) } else { doc.entities.insert(e, at: min(insert, doc.entities.count)); insert += 1 }
            }
            changed = true
        }
        return changed
    }
}

// MARK: - Commands

enum ModelingTools9 {
    static var all: [CommandDef] { [paint, soften, tape, intersectFaces, projectGeometry] }

    static var projectGeometry: CommandDef {
        CommandDef("PROJECTGEOMETRY", aliases: ["PROJECTEDGES", "EXTERNALGEOMETRY", "FLATOUTLINE"], category: "3D", summary: "Projects the outline of solids onto the sketch plane as closed polylines that follow the solids when they change (use them as sketch profiles).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to project")
            guard !ids.isEmpty else { return }
            let z = try await ed.getDistance("Specify sketch plane elevation", defaultValue: ed.variableDouble("ELEVATION", 0)).value ?? 0
            var n = 0
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                for e in ProjectedGeometry.entities(of: id, s, layer: ed.doc.currentLayer, elevation: z) { ed.doc.add(e); n += 1 }
            }
            ed.selection = []
            ed.print("\(n) projected outline(s).")
        }
    }

    static var intersectFaces: CommandDef {
        CommandDef("INTERSECTFACES", aliases: ["INTERSECTWITHMODEL", "INTERSECTEDGES"], category: "3D", summary: "SketchUp intersect faces: draws 3D edges (polylines) where the selected solids cut each other, or cut the rest of the Model.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids")
            guard !ids.isEmpty else { return }
            let with = try await ed.getKeyword("Intersect with [Selection/Model]", ["Selection", "Model"], defaultValue: ids.count >= 2 ? "Selection" : "Model") ?? "Selection"
            let others: [EntityID] = with == "Model" ? ed.doc.entities.compactMap { e in if case .solid = e.geometry, !ids.contains(e.id) { return e.id }; return nil } : []
            var pairs: [(EntityID, EntityID)] = []
            if with == "Model" { for a in ids { for b in others { pairs.append((a, b)) } } }
            else { for i in 0..<ids.count { for j in (i + 1)..<ids.count { pairs.append((ids[i], ids[j])) } } }
            var n = 0, total = 0.0
            for (a, b) in pairs {
                guard let sa = ModelingCommands.solidOf(ed.doc, a), let sb = ModelingCommands.solidOf(ed.doc, b) else { continue }
                for c in FaceIntersection.curves(sa, sb) {
                    let closed = c.count > 3 && c.first!.distance(to: c.last!) < 1e-6
                    let pts = closed ? Array(c.dropLast()) : c
                    var e = Entity(layer: ed.doc.currentLayer, geometry: .polyline(PolylineGeom(points: pts.map(\.xy), closed: closed)))
                    e.props["vertexZ"] = pts.map { fmt($0.z, 6) }.joined(separator: ",")
                    e.props["intersection"] = "\(a),\(b)"
                    ed.doc.add(e)
                    n += 1
                    total += zip(c, c.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                }
            }
            ed.selection = []
            ed.print(n == 0 ? "The solids do not intersect." : "\(n) intersection edge(s), total length \(fmt(total)).")
        }
    }

    /// Material of an entity or element (entities: "material" property).
    @MainActor static func material(of id: EntityID, _ doc: ArchiDocument) -> String? {
        if let e = doc.entity(id) { return e.props["material"] }
        return doc.element(id)?.material
    }

    /// Makes sure a material exists in the document (from the built-in library, or a neutral new one).
    static func ensureMaterial(_ name: String, _ doc: inout ArchiDocument) -> String {
        if let m = doc.material(name) { return m.name }
        if let lib = Material.library.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.materials.append(lib); return lib.name }
        doc.materials.append(Material(name: name, color: RGBA(0.75, 0.75, 0.75)))
        return name
    }

    /// Applies a material to an entity (solid/object) or building element. Returns false when the object is unknown.
    @discardableResult
    static func paint(_ id: EntityID, material: String, doc: inout ArchiDocument) -> Bool {
        let name = ensureMaterial(material, &doc)
        if let i = doc.entityIndex(id) { doc.entities[i].props["material"] = name; return true }
        if let i = doc.elementIndex(id) { doc.elements[i].material = name; return true }
        return false
    }

    static var paint: CommandDef {
        CommandDef("PAINT", aliases: ["PAINTBUCKET", "APPLYMATERIAL"], category: "3D", summary: "Paint bucket: applies a material to objects and building elements by clicking them; Sample picks up an object's material; List shows the materials.") { ed in
            var mat = ed.doc.variable("CMATERIAL") ?? ed.doc.materials.first?.name ?? "Concrete"
            while true {
                let r = try await ed.getWord("Enter material name <\(mat)> or [Sample/List]", defaultValue: mat, keywords: ["Sample", "List"])
                if r == "List" { ed.print(ed.doc.materials.map(\.name).joined(separator: ", ")); continue }
                if r == "Sample" {
                    guard case .pick(let pk) = try await ed.pickObject("Select object to sample"), let m = material(of: pk.id, ed.doc) else { ed.print("That object has no material."); continue }
                    mat = m; ed.print("Material: \(m)"); continue
                }
                mat = r ?? mat
                break
            }
            mat = ensureMaterial(mat, &ed.doc)
            ed.doc.setVariable("CMATERIAL", mat)
            var n = 0
            // Pre-selected objects are painted at once; then click more objects (Enter ends).
            if !ed.selection.isEmpty {
                for id in ed.selection where paint(id, material: mat, doc: &ed.doc) { n += 1 }
                ed.selection = []
            }
            while true {
                let r = try await ed.pickObject("Select object to paint with \(mat) or [Sample]", keywords: ["Sample"])
                switch r {
                case .pick(let pk): if paint(pk.id, material: mat, doc: &ed.doc) { n += 1 }
                case .keyword:
                    if case .pick(let pk) = try await ed.pickObject("Select object to sample"), let m = material(of: pk.id, ed.doc) { mat = m; ed.doc.setVariable("CMATERIAL", m); ed.print("Material: \(m)") }
                default:
                    ed.print("\(n) object(s) painted with \(mat).")
                    return
                }
            }
        }
    }

    static var soften: CommandDef {
        CommandDef("SOFTEN", aliases: ["SOFTENEDGES", "SMOOTHEDGES"], category: "3D", summary: "Softens and smooths the edges of solids/meshes whose faces meet at less than an angle (0 = sharp again); display only.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids or meshes")
            guard !ids.isEmpty else { return }
            let a = try await ed.getReal("Soften edges between faces meeting at less than (degrees)", defaultValue: ed.variableDouble("SOFTENANGLE", 30)).value ?? 30
            guard a >= 0, a < 180 else { throw CommandError.invalid("Enter an angle between 0 and 180 degrees.") }
            ed.doc.setVariable("SOFTENANGLE", fmt(a))
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["softenAngle"] = a > 0 ? fmt(a) : nil } }
            ed.selection = []
            ed.print(a > 0 ? "\(ids.count) object(s) softened below \(fmt(a))°." : "Edges of \(ids.count) object(s) are sharp again.")
        }
    }

    /// Nearest straight segment of a line or polyline to a point.
    static func segment(_ g: Geometry, near p: Vec2) -> (Vec2, Vec2)? {
        switch g {
        case .line(let l): return (l.a, l.b)
        case .polyline(let pl):
            let pts = pl.vertices.map(\.p) + (pl.closed ? [pl.vertices[0].p] : [])
            guard pts.count >= 2 else { return nil }
            return zip(pts, pts.dropFirst()).min { GeometryOps.distance(from: p, toPolyline: [$0.0, $0.1]) < GeometryOps.distance(from: p, toPolyline: [$1.0, $1.1]) }
        default: return nil
        }
    }

    @MainActor static func addGuide(_ ed: Editor, base: Vec2, direction: Vec2) -> EntityID? {
        guard let cl = ConstructionLines.make(.xline, base: base, direction: direction) else { return nil }
        var e = Entity(layer: ed.doc.currentLayer, geometry: cl.geometry)
        e.props = cl.props
        e.props["guide"] = "1"
        return ed.doc.add(e)
    }

    static var tape: CommandDef {
        CommandDef("TAPEMEASURE", aliases: ["TAPE", "GUIDE", "PROTRACTOR"], category: "3D", summary: "Tape measure: Measure between two points, create a Guide parallel to an edge at a distance or through a point, or a Protractor guide at an angle.") { ed in
            let k = try await ed.getKeyword("Tape measure option [Measure/Guide/Protractor]", ["Measure", "Guide", "Protractor"], defaultValue: "Measure") ?? "Measure"
            switch k {
            case "Guide":
                guard case .pick(let pk) = try await ed.pickObject("Select the edge to measure from", filter: { id in
                    guard let g = ed.doc.entity(id)?.geometry else { return false }
                    return segment(g, near: .zero) != nil }),
                      let g = ed.doc.entity(pk.id)?.geometry, let (a, b) = segment(g, near: pk.point) else { return }
                let dir = (b - a).normalized
                guard dir != .zero else { return }
                let foot = a + dir * (pk.point - a).dot(dir)
                let r = try await ed.getDistanceOrPoint("Specify guide distance or through point", base: foot, defaultValue: ed.variableDouble("TAPEDIST", 1000))
                var through: Vec2
                if let p = r.point { through = p }
                else {
                    let d = r.value ?? 1000
                    ed.doc.setVariable("TAPEDIST", fmt(abs(d)))
                    var side = dir.perp
                    if side.dot(pk.point - a) < 0 { side = -side }
                    // A pick exactly on the edge offsets to the left; a negative distance flips the side.
                    through = foot + side * d
                }
                let off = abs((through - a).cross(dir))
                _ = addGuide(ed, base: through, direction: dir)
                ed.print("Guide created at \(fmt(off)) from the edge.")
            case "Protractor":
                let c = try await ed.requirePoint("Specify protractor centre")
                let ref = try await ed.requirePoint("Specify reference direction point", base: c) { p in [.line(LineGeom(c, p))] }
                let ang = try await ed.getAngle("Specify angle from the reference", defaultValue: rad(45)).value ?? rad(45)
                _ = addGuide(ed, base: c, direction: (ref - c).normalized.rotated(by: ang))
                ed.print("Angle guide at \(fmt(deg(ang)))°.")
            default:
                let a = try await ed.requirePoint("Specify first point")
                let b = try await ed.requirePoint("Specify second point", base: a) { p in [.line(LineGeom(a, p))] }
                let d = b - a
                ed.print("Length = \(fmt(d.length)), ΔX = \(fmt(d.x)), ΔY = \(fmt(d.y)), angle = \(fmt(deg(d.angle)))°")
                ed.doc.setVariable("TAPEDIST", fmt(d.length))
            }
        }
    }
}
