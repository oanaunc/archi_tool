// Oanarina Archi Tool — GPL-3.0-or-later
// SketchUp-style components and groups with an outliner (M3D-102/103), reference geometry — datum planes, axes and
// points that follow their source objects (M3D-028) — and sandbox terrain tools (M3D-099): grid terrain, smoove,
// stamp, drape and conversion of a toposurface into a BIM element.
import Foundation

// MARK: - Components and groups

public enum SketchComponents {
    public static let componentKey = "skComponent", groupKey = "skGroup"

    /// Next free anonymous group block name ("*G1", "*G2", …).
    public static func groupName(_ doc: ArchiDocument) -> String {
        var n = 1
        while doc.blocks["*G\(n)"] != nil { n += 1 }
        return "*G\(n)"
    }

    /// Turns entities into a block definition and replaces them with one instance. Returns the insert id.
    @discardableResult
    public static func make(_ name: String, ids: [EntityID], base: Vec2, group: Bool, doc: inout ArchiDocument) -> EntityID? {
        let set = Set(ids)
        let ents = doc.entities.filter { set.contains($0.id) }
        guard !ents.isEmpty, doc.blocks[name] == nil else { return nil }
        doc.blocks[name] = Block(name: name, basePoint: base, entities: ents, description: group ? "Group" : "Component")
        let layer = ents[0].layer
        doc.remove(ids: set)
        var e = Entity(layer: layer, geometry: .insert(InsertGeom(block: name, position: base)))
        e.props[group ? groupKey : componentKey] = "1"
        return doc.add(e)
    }

    /// Copies an instance's definition to a new name so it can be edited alone (SketchUp "Make Unique").
    @discardableResult
    public static func makeUnique(_ id: EntityID, doc: inout ArchiDocument) -> String? {
        guard let i = doc.entityIndex(id), case .insert(var ins) = doc.entities[i].geometry, var b = doc.blocks[ins.block] else { return nil }
        var k = 2, name = ins.block.hasPrefix("*G") ? groupName(doc) : "\(ins.block) #2"
        while doc.blocks[name] != nil { k += 1; name = "\(ins.block) #\(k)" }
        b.name = name
        doc.blocks[name] = b
        ins.block = name
        doc.entities[i].geometry = .insert(ins)
        return name
    }

    /// World-space solids of an insert (nested inserts flattened) or of a solid entity.
    public static func solids(of g: Geometry, doc: ArchiDocument, depth: Int = 0) -> [SolidGeom] {
        switch g {
        case .solid(let s): return [s]
        case .insert(let ins):
            guard depth < 8, let b = doc.blocks[ins.block] else { return [] }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            return b.entities.flatMap { solids(of: GeometryOps.transform($0.geometry, t), doc: doc, depth: depth + 1) }
        default: return []
        }
    }

    /// Converts a component / group instance (or a solid) into a BIM component element. Returns the element id.
    @discardableResult
    public static func toBIM(_ id: EntityID, category: String, name: String?, doc: inout ArchiDocument) -> EntityID? {
        guard let e = doc.entity(id) else { return nil }
        let ss = solids(of: e.geometry, doc: doc)
        let elev = doc.level(doc.currentLevel)?.elevation ?? 0
        guard !ss.isEmpty, let g = InPlaceModels.component(from: ss, category: category, levelElevation: elev) else { return nil }
        var label = name ?? e.props["name"] ?? category
        if case .insert(let ins) = e.geometry, name == nil, e.props["name"] == nil, !ins.block.hasPrefix("*") { label = ins.block }
        let eid = doc.addElement(.component(g), material: e.props["material"] ?? "Concrete", name: label)
        if let i = doc.elementIndex(eid) {
            doc.elements[i].props["inPlace"] = "1"
            if case .insert(let ins) = e.geometry { doc.elements[i].props["fromComponent"] = ins.block }
        }
        doc.remove(ids: [id])
        return eid
    }
}

/// Hierarchy of groups and components (SketchUp Outliner) and BIM model groups.
public enum Outliner {
    public struct Node: Hashable {
        public var name: String
        public var kind: String
        public var id: EntityID?
        public var children: [Node]
    }

    static func kind(_ e: Entity) -> String {
        if e.props[SketchComponents.groupKey] == "1" { return "group" }
        if e.props[SketchComponents.componentKey] == "1" { return "component" }
        if case .insert(let ins) = e.geometry, ins.block.hasPrefix("*G") { return "group" }
        return e.typeName == "insert" ? "block" : e.typeName
    }

    static func node(_ e: Entity, id: EntityID?, doc: ArchiDocument, depth: Int) -> Node? {
        switch e.geometry {
        case .insert(let ins):
            let k = kind(e)
            let label = e.props["name"] ?? (k == "group" ? "Group" : ins.block)
            var kids: [Node] = []
            if depth < 8, let b = doc.blocks[ins.block] { kids = b.entities.compactMap { node($0, id: nil, doc: doc, depth: depth + 1) } }
            return Node(name: k == "component" || k == "block" ? "\(label) <\(ins.block)>" : label, kind: k, id: id, children: kids)
        case .solid:
            guard depth > 0 else { return nil }
            return Node(name: e.props["name"] ?? "Solid", kind: "solid", id: id, children: [])
        default: return nil
        }
    }

    public static func tree(_ doc: ArchiDocument) -> [Node] {
        var out = doc.entities.compactMap { node($0, id: $0.id, doc: doc, depth: 0) }
        for g in doc.modelGroups {
            let inst = ModelGroups.instances(g.name, doc: doc)
            let kids = inst.keys.sorted().map { k in Node(name: "Instance \(k) (\(inst[k]!.count) elements)", kind: "modelGroupInstance", id: inst[k]!.first, children: []) }
            out.append(Node(name: g.name, kind: "modelGroup", id: nil, children: kids))
        }
        return out
    }

    public static func lines(_ nodes: [Node], indent: Int = 0) -> [String] {
        nodes.flatMap { n -> [String] in
            [String(repeating: "  ", count: indent) + "\(n.kind == "group" ? "▸" : "◆") \(n.name)" + (n.id.map { " #\($0)" } ?? "") + " [\(n.kind)]"] + lines(n.children, indent: indent + 1)
        }
    }

    /// Top-level instance ids whose node (or a descendant) matches a name (case-insensitive, * wildcard).
    public static func find(_ pattern: String, in nodes: [Node]) -> [EntityID] {
        func matches(_ n: Node) -> Bool { TopoContours.wildcard(pattern, n.name) || n.children.contains(where: matches) }
        return nodes.filter(matches).compactMap(\.id)
    }
}

// MARK: - Datum planes, axes and points

public enum Datums {
    public static let key = "datum"

    static func vec3(_ s: String?) -> Vec3? {
        guard let p = s?.split(separator: ",").compactMap({ Double($0) }), p.count == 3 else { return nil }
        return Vec3(p[0], p[1], p[2])
    }
    static func str(_ v: Vec3) -> String { "\(fmt(v.x, 9)),\(fmt(v.y, 9)),\(fmt(v.z, 9))" }

    /// Open two-triangle plane patch (origin at its centre).
    static func quad(center c: Vec3, normal n: Vec3, halfU hu: Double, halfV hv: Double) -> SolidGeom {
        let (u, v) = Mesh.basis(n.normalized)
        let pts = [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
        return SolidGeom(kind: .mesh, origin: c, meshVertices: pts, meshTriangles: [0, 1, 2, 0, 2, 3])
    }

    /// Endpoints of a linear source (line, first polyline segment, 3D polyline).
    static func segment(_ doc: ArchiDocument, _ e: Entity) -> (Vec3, Vec3)? {
        let z = e.props["elevation"].flatMap(Double.init) ?? 0
        switch e.geometry {
        case .line(let l): return (Vec3(l.a.x, l.a.y, z), Vec3(l.b.x, l.b.y, z))
        default:
            guard let p = FeatureSources.path3(doc, e.id, z: z), p.points.count >= 2 else { return nil }
            return (p.points[0], p.points[1])
        }
    }

    static func center(_ e: Entity) -> Vec3? {
        let z = e.props["elevation"].flatMap(Double.init) ?? 0
        switch e.geometry {
        case .circle(let c): return Vec3(c.center.x, c.center.y, z)
        case .arc(let a): return Vec3(a.center.x, a.center.y, z)
        case .ellipse(let el): return Vec3(el.center.x, el.center.y, z)
        case .point(let p): return Vec3(p.x, p.y, z)
        case .polyline(let pl) where pl.closed && pl.vertices.count >= 3:
            let c = GeometryOps.centroid(pl.vertices.map(\.p)); return Vec3(c.x, c.y, z)
        case .solid(let s):
            let b = MeshTools.mesh(of: s).bounds
            return b.isEmpty ? nil : b.center
        default: return nil
        }
    }

    /// Recomputes a datum from its source: new geometry and 3D definition props; nil when the source is unusable.
    public static func evaluate(_ e: Entity, doc: ArchiDocument) -> (geometry: Geometry, props: [String: String])? {
        guard let kind = e.props[key], let src = e.props["datumOf"] else { return nil }
        let mode = e.props["datumMode"] ?? ""
        let off = e.props["datumOffset"].flatMap(Double.init) ?? 0
        var p: [String: String] = [:]
        if src.hasPrefix("L"), let lid = Int(src.dropFirst()) {
            // Horizontal plane at a level.
            guard kind == "plane", let lv = doc.level(lid) else { return nil }
            let c0 = vec3(e.props["datumCenter"]) ?? .zero
            let size = e.props["datumSize"].flatMap(Double.init) ?? 10000
            let c = Vec3(c0.x, c0.y, lv.elevation + off)
            p["datumA"] = str(c); p["datumN"] = "0,0,1"
            return (.solid(quad(center: c, normal: .unitZ, halfU: size / 2, halfV: size / 2)), p)
        }
        guard src.hasPrefix("#"), let sid = Int(src.dropFirst()), let s = doc.entity(sid) else { return nil }
        switch (kind, mode) {
        case ("plane", "Face"):
            guard case .solid(let so) = s.geometry, let n = vec3(e.props["datumN"])?.normalized, n.length > 0.5 else { return nil }
            let w = SolidOps.welded(so)
            var pts: [Vec3] = []
            for f in 0..<(w.triangles.count / 3) where SubObjects.normal((w.vertices, w.triangles), f).dot(n) > 0.999 {
                pts += (0..<3).map { w.vertices[w.triangles[3 * f + $0]] }
            }
            guard let far = pts.map({ $0.dot(n) }).max() else { return nil }
            let face = pts.filter { abs($0.dot(n) - far) < 1e-6 * max(1, abs(far)) }
            let (u, v) = Mesh.basis(n)
            let us = face.map { $0.dot(u) }, vs = face.map { $0.dot(v) }
            guard let u0 = us.min(), let u1 = us.max(), let v0 = vs.min(), let v1 = vs.max() else { return nil }
            let c = u * ((u0 + u1) / 2) + v * ((v0 + v1) / 2) + n * (far + off)
            p["datumA"] = str(c); p["datumN"] = str(n)
            return (.solid(quad(center: c, normal: n, halfU: (u1 - u0) * 0.55 + 1, halfV: (v1 - v0) * 0.55 + 1)), p)
        case ("plane", _):
            // Vertical plane through a line (offset to its left, rotated about the start by datumAngle).
            guard let (a, b) = segment(doc, s), a.xy.distance(to: b.xy) > 1e-9 else { return nil }
            let ang = (e.props["datumAngle"].flatMap(Double.init) ?? 0) * .pi / 180
            let d = (b.xy - a.xy).normalized.rotated(by: ang), len = a.xy.distance(to: b.xy)
            let o = a.xy + d.perp * off
            let ext = len * 0.1
            let p0 = o - d * ext, p1 = o + d * (len + ext)
            let h = e.props["datumHeight"].flatMap(Double.init) ?? 3000
            p["datumA"] = str(Vec3(o.x, o.y, a.z)); p["datumN"] = str(Vec3(-d.perp.x, -d.perp.y, 0) * -1)
            p["elevation"] = fmt(a.z, 9); p["thickness"] = fmt(h, 9)
            return (.line(LineGeom(p0, p1)), p)
        case ("axis", "Center"), ("axis", "Cylinder"):
            var base: Vec3, top: Vec3
            if case .solid(let so) = s.geometry {
                guard so.kind == .cylinder || so.kind == .cone else { return nil }
                base = so.origin; top = so.origin + Vec3(0, 0, so.size.z)
            } else {
                guard let c = center(s) else { return nil }
                let h = e.props["datumHeight"].flatMap(Double.init) ?? 3000
                base = c; top = c + Vec3(0, 0, h)
            }
            p["datumA"] = str(base); p["datumB"] = str(top)
            return (.point(base.xy), p)
        case ("axis", _):
            guard let (a, b) = segment(doc, s), a.distance(to: b) > 1e-9 else { return nil }
            let d = (b - a).normalized, ext = a.distance(to: b) * 0.1
            let a2 = a - d * ext, b2 = b + d * ext
            p["datumA"] = str(a2); p["datumB"] = str(b2)
            p["vertexZ"] = "\(fmt(a2.z, 9)),\(fmt(b2.z, 9))"
            return (.polyline(PolylineGeom(points: [a2.xy, b2.xy])), p)
        case ("point", _):
            var q: Vec3?
            switch mode {
            case "Start", "End", "Mid":
                if let (a, b) = segment(doc, s) {
                    var pts = [a, b]
                    if let path = FeatureSources.path3(doc, sid, z: a.z), case .polyline = s.geometry { pts = path.points }
                    q = mode == "Start" ? pts.first : (mode == "End" ? pts.last : (a + b) / 2)
                    if mode == "Mid", case .polyline = s.geometry, pts.count >= 2 {
                        // Midpoint by length along the polyline.
                        let total = zip(pts, pts.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
                        var acc = 0.0
                        for (x, y) in zip(pts, pts.dropFirst()) {
                            let l = x.distance(to: y)
                            if acc + l >= total / 2 { q = x + (y - x) * ((total / 2 - acc) / max(l, 1e-12)); break }
                            acc += l
                        }
                    }
                } else if case .arc(let ar) = s.geometry {
                    let z = s.props["elevation"].flatMap(Double.init) ?? 0
                    let ang = mode == "Start" ? ar.start : (mode == "End" ? ar.end : ar.start + ar.sweep / 2)
                    let pp = ar.center + Vec2.polar(ar.radius, ang)
                    q = Vec3(pp.x, pp.y, z)
                }
            default: q = center(s)
            }
            guard let pt = q else { return nil }
            p["datumA"] = str(pt); p["elevation"] = fmt(pt.z, 9)
            return (.point(pt.xy), p)
        default: return nil
        }
    }

    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.entities.contains { $0.props[key] != nil } }

    /// Regenerates every datum from its source. Returns true when something changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props[key] != nil {
            let e = doc.entities[i]
            guard let r = evaluate(e, doc: doc) else {
                if e.props["datumOrphan"] != "1" { doc.entities[i].props["datumOrphan"] = "1"; changed = true }
                continue
            }
            var np = e.props
            np["datumOrphan"] = nil
            for (k, v) in r.props { np[k] = v }
            if e.geometry != r.geometry || np != e.props {
                doc.entities[i].geometry = r.geometry; doc.entities[i].props = np; changed = true
            }
        }
        return changed
    }

    /// Creates a datum entity on the DATUM layer and evaluates it.
    @discardableResult
    public static func add(_ kind: String, source: String, mode: String, offset: Double = 0, extra: [String: String] = [:], doc: inout ArchiDocument) -> EntityID? {
        var e = Entity(layer: "DATUM", geometry: .point(.zero))
        e.props = extra
        e.props[key] = kind; e.props["datumOf"] = source; e.props["datumMode"] = mode
        if offset != 0 { e.props["datumOffset"] = fmt(offset, 9) }
        guard let r = evaluate(e, doc: doc) else { return nil }
        e.geometry = r.geometry
        for (k, v) in r.props { e.props[k] = v }
        if doc.layer(named: "DATUM") == nil { doc.layers.append(Layer(name: "DATUM", color: RGBA(0.35, 0.65, 0.95), linetype: "Center", lineweight: 0.13, plot: false, transparency: 0.5, description: "Reference geometry")) }
        return doc.add(e)
    }
}

// MARK: - Sandbox terrain tools

public enum Sandbox {
    /// Survey points (top surface) and base elevation of a toposurface solid.
    public static func points(_ s: SolidGeom) -> (points: [Vec3], base: Double) {
        let w = SolidOps.welded(s)
        let z0 = s.origin.z
        var seen = Set<[Int64]>()
        var out: [Vec3] = []
        for v in w.vertices where v.z > z0 + 1e-6 {
            let k = [Int64((v.x * 1000).rounded()), Int64((v.y * 1000).rounded())]
            if seen.insert(k).inserted { out.append(v) }
        }
        return (out, z0)
    }

    /// Closed terrain solid from points, keeping the base below every point.
    public static func rebuild(_ pts: [Vec3], base: Double) -> SolidGeom? {
        var seen: [[Int64]: Int] = [:]
        var uniq: [Vec3] = []
        for p in pts {
            let k = [Int64((p.x * 1000).rounded()), Int64((p.y * 1000).rounded())]
            if let i = seen[k] { uniq[i] = p } else { seen[k] = uniq.count; uniq.append(p) }
        }
        let zMin = uniq.map(\.z).min() ?? base
        return Terrain.solid(uniq, baseZ: min(base, zMin - 100))
    }

    /// Grid terrain (SketchUp "From Scratch").
    public static func grid(origin o: Vec2, width w: Double, depth d: Double, spacing s: Double, z: Double = 0) -> [Vec3] {
        let nx = max(1, Int((w / s).rounded())), ny = max(1, Int((d / s).rounded()))
        return (0...nx).flatMap { i in (0...ny).map { j in Vec3(o.x + w * Double(i) / Double(nx), o.y + d * Double(j) / Double(ny), z) } }
    }

    static func surfaceZ(_ pts: [Vec3], at p: Vec2) -> Double? {
        let s = Terrain.surface(pts)
        return Terrain.elevation(at: p, vertices: s.vertices, triangles: s.triangles)
    }

    /// Smoove: raises (or lowers) the terrain around `center` by `height` with a smooth cosine falloff over `radius`.
    public static func smoove(_ pts0: [Vec3], center c: Vec2, radius r: Double, height h: Double) -> [Vec3] {
        var pts = pts0
        // Densify when the circle holds too few survey points to show the bump.
        if pts.filter({ $0.xy.distance(to: c) < r }).count < 7 {
            let step = r / 4
            var extra: [Vec3] = []
            for i in -4...4 { for j in -4...4 {
                let q = c + Vec2(Double(i) * step, Double(j) * step)
                if q.distance(to: c) < r * 0.999, let z = surfaceZ(pts0, at: q) { extra.append(Vec3(q.x, q.y, z)) }
            } }
            pts += extra
        }
        return pts.map { p in
            let d = p.xy.distance(to: c)
            guard d < r else { return p }
            return Vec3(p.x, p.y, p.z + h * 0.5 * (1 + cos(.pi * d / r)))
        }
    }

    /// Stamp: a flat pad at `z` over a closed footprint, blending linearly back to the terrain over `offset`.
    public static func stamp(_ pts0: [Vec3], footprint fp: [Vec2], z: Double, offset: Double) -> [Vec3] {
        guard fp.count >= 3 else { return pts0 }
        var ring: [Vec3] = []
        let outer = offset > 0 ? CommandHelpers.offsetPolygon(GeometryOps.signedArea(fp) < 0 ? fp.reversed() : fp, offset) : []
        for q in outer { if let tz = surfaceZ(pts0, at: q) { ring.append(Vec3(q.x, q.y, tz)) } }
        func edgeDist(_ p: Vec2) -> Double {
            (0..<fp.count).map { i -> Double in
                let a = fp[i], b = fp[(i + 1) % fp.count], d = b - a
                let t = max(0, min(1, (p - a).dot(d) / max(d.lengthSquared, 1e-18)))
                return p.distance(to: a + d * t)
            }.min() ?? 0
        }
        var pts = pts0.map { p -> Vec3 in
            if GeometryOps.pointInPolygon(p.xy, fp) { return Vec3(p.x, p.y, z) }
            let d = edgeDist(p.xy)
            guard offset > 0, d < offset else { return p }
            let t = d / offset
            return Vec3(p.x, p.y, z + (p.z - z) * t)
        }
        pts += fp.map { Vec3($0.x, $0.y, z) } + ring
        return pts
    }

    /// Drape: a curve projected vertically onto the terrain as a 3D polyline (sampled every `step`).
    public static func drape(_ path: [Vec2], on pts: [Vec3], step: Double) -> [Vec3] {
        let s = Terrain.surface(pts)
        var out: [Vec3] = []
        for i in 0..<max(path.count - 1, 0) {
            let a = path[i], b = path[i + 1]
            let n = max(1, Int((a.distance(to: b) / max(step, 1e-9)).rounded(.up)))
            for k in 0..<n {
                let q = a + (b - a) * (Double(k) / Double(n))
                if let z = Terrain.elevation(at: q, vertices: s.vertices, triangles: s.triangles) { out.append(Vec3(q.x, q.y, z)) }
            }
        }
        if let l = path.last, let z = Terrain.elevation(at: l, vertices: s.vertices, triangles: s.triangles) { out.append(Vec3(l.x, l.y, z)) }
        return out
    }
}

// MARK: - Commands

enum ComponentDatumCommands {
    static var all: [CommandDef] { [makeComponent, makeGroup, makeUnique, toBIM, outliner, datum, sandbox] }

    static var makeComponent: CommandDef {
        CommandDef("MAKECOMPONENT", aliases: ["COMPONENTMAKE", "SKCOMPONENT", "MAKECOMP"], category: "3D", summary: "SketchUp-style component: the selected objects become a named definition and are replaced by an instance; every instance updates when the definition is edited (BEDIT/REFEDIT).") { ed in
            let pre = ed.selection
            guard let name = try await ed.getWord("Enter component name") , !name.isEmpty, !name.hasPrefix("*") else { throw CommandError.invalid("Enter a name.") }
            guard ed.doc.blocks[name] == nil else { throw CommandError.invalid("A component or block named \(name) already exists.") }
            let base = try await ed.requirePoint("Specify insertion base point")
            ed.selection = pre
            let ids = try await ed.getEntitySelection("Select objects")
            guard let id = SketchComponents.make(name, ids: ids, base: base, group: false, doc: &ed.doc) else { throw CommandError.invalid("Nothing selected.") }
            ed.selection = [id]
            ed.print("Component \"\(name)\" created from \(ids.count) object(s): instance #\(id).")
        }
    }

    static var makeGroup: CommandDef {
        CommandDef("MAKEGROUP", aliases: ["SKGROUP", "GROUP3D", "GROUPSOLIDS"], category: "3D", summary: "SketchUp-style group: the selected objects become one unique (unnamed) object that moves and copies as a whole.") { ed in
            let ids = try await ed.getEntitySelection("Select objects to group")
            guard !ids.isEmpty else { return }
            var b = BBox2.empty
            for id in ids { if let e = ed.doc.entity(id) { b = b.union(GeometryOps.bounds(e.geometry, doc: ed.doc)) } }
            let name = SketchComponents.groupName(ed.doc)
            guard let id = SketchComponents.make(name, ids: ids, base: b.isEmpty ? .zero : b.min, group: true, doc: &ed.doc) else { return }
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["name"] = try await ed.getString("Group name", defaultValue: "Group \(name.dropFirst(2))") }
            ed.selection = [id]
            ed.print("Group #\(id) of \(ids.count) object(s).")
        }
    }

    static var makeUnique: CommandDef {
        CommandDef("MAKEUNIQUE", aliases: ["UNIQUECOMPONENT"], category: "3D", summary: "Gives a component or group instance its own copy of the definition so it can be edited without changing the other instances.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select a component or group instance", filter: { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }) else { return }
            guard let n = SketchComponents.makeUnique(pk.id, doc: &ed.doc) else { return }
            ed.print("Instance #\(pk.id) now uses definition \"\(n)\".")
        }
    }

    static var toBIM: CommandDef {
        CommandDef("COMPONENTTOBIM", aliases: ["GROUPTOBIM", "TOBIM", "CONVERTTOBIM"], category: "3D", summary: "Converts component / group instances or solids into schedulable BIM component elements (category and name).") { ed in
            let ids = try await ed.getEntitySelection("Select components, groups or solids")
            guard !ids.isEmpty else { return }
            let cat = try await ed.getWord("Category", defaultValue: "Generic Models") ?? "Generic Models"
            var made: [EntityID] = []
            for id in ids { if let e = SketchComponents.toBIM(id, category: cat, name: nil, doc: &ed.doc) { made.append(e) } }
            ed.selection = Set(made)
            ed.print("\(made.count) BIM element(s) created (\(cat)).")
        }
    }

    static var outliner: CommandDef {
        CommandDef("OUTLINER", aliases: ["OUTLINE", "HIERARCHY"], category: "3D", summary: "Outliner: lists the hierarchy of groups, components and model groups; Select instances by name (wildcards), Rename an instance, or Convert it to a BIM element.", modifies: true) { ed in
            let k = try await ed.getKeyword("Outliner [List/Select/Rename/Convert]", ["List", "Select", "Rename", "Convert"], defaultValue: "List") ?? "List"
            let tree = Outliner.tree(ed.doc)
            switch k {
            case "Select":
                let pat = try await ed.getWord("Name to find (wildcards * ?)", defaultValue: "*") ?? "*"
                let ids = Outliner.find(pat, in: tree)
                ed.selection = Set(ids)
                ed.print("\(ids.count) instance(s) selected.")
            case "Rename", "Convert":
                guard case .pick(let pk) = try await ed.pickObject("Select an instance", filter: { ed.doc.entity($0) != nil }) else { return }
                if k == "Rename" {
                    let n = try await ed.getString("New name", defaultValue: ed.doc.entity(pk.id)?.props["name"]) ?? ""
                    if let i = ed.doc.entityIndex(pk.id) { ed.doc.entities[i].props["name"] = n.isEmpty ? nil : n }
                    ed.print("Renamed.")
                } else if let e = SketchComponents.toBIM(pk.id, category: "Generic Models", name: nil, doc: &ed.doc) {
                    ed.selection = [e]; ed.print("Converted to BIM element #\(e).")
                }
            default:
                let l = Outliner.lines(tree)
                if l.isEmpty { ed.print("No groups or components.") } else { l.forEach { ed.print($0) } }
            }
        }
    }

    static var datum: CommandDef {
        CommandDef("DATUM", aliases: ["DATUMPLANE", "DATUMAXIS", "DATUMPOINT", "REFGEOMETRY", "WORKPLANEREF"], category: "3D", summary: "Reference geometry that follows its source: datum Plane (through a line, offset from a solid Face, or at a Level), Axis (along a line, through a circle centre or a cylinder) or Point (centre, start, end or midpoint).") { ed in
            let kind = try await ed.getKeyword("Datum [Plane/Axis/Point]", ["Plane", "Axis", "Point"], defaultValue: "Plane") ?? "Plane"
            var id: EntityID?
            switch kind {
            case "Plane":
                let mode = try await ed.getKeyword("Plane [Line/Face/Level]", ["Line", "Face", "Level"], defaultValue: "Line") ?? "Line"
                if mode == "Level" {
                    let lv = try await ed.getInteger("Level number", defaultValue: ed.doc.currentLevel) ?? ed.doc.currentLevel
                    guard ed.doc.level(lv) != nil else { throw CommandError.invalid("No such level.") }
                    let off = try await ed.getDistance("Offset above the level", defaultValue: 0).value ?? 0
                    let c = try await ed.getPoint("Specify plane centre", keywords: []).point ?? .zero
                    let size = try await ed.getPositive("Plane size", defaultValue: 10000)
                    id = Datums.add("plane", source: "L\(lv)", mode: "Level", offset: off, extra: ["datumCenter": "\(fmt(c.x, 9)),\(fmt(c.y, 9)),0", "datumSize": fmt(size)], doc: &ed.doc)
                } else if mode == "Face" {
                    guard case .pick(let pk) = try await ed.pickObject("Select a solid", filter: { ModelingCommands.solidOf(ed.doc, $0) != nil }), let s = ModelingCommands.solidOf(ed.doc, pk.id) else { return }
                    let p = try await ed.requirePoint3("Specify a point on the face")
                    let w = SolidOps.welded(s)
                    guard let f = SubObjects.nearestFace((w.vertices, w.triangles), to: p) else { return }
                    let n = SubObjects.normal((w.vertices, w.triangles), f)
                    let off = try await ed.getDistance("Offset along the face normal", defaultValue: 0).value ?? 0
                    id = Datums.add("plane", source: "#\(pk.id)", mode: "Face", offset: off, extra: ["datumN": Datums.str(n)], doc: &ed.doc)
                } else {
                    guard case .pick(let pk) = try await ed.pickObject("Select a line or polyline", filter: { ed.doc.entity($0).flatMap { Datums.segment(ed.doc, $0) } != nil }) else { return }
                    let off = try await ed.getDistance("Offset to the left", defaultValue: 0).value ?? 0
                    let ang = try await ed.getReal("Rotation about the start point in degrees", defaultValue: 0).value ?? 0
                    let h = try await ed.getPositive("Plane height", defaultValue: 3000)
                    id = Datums.add("plane", source: "#\(pk.id)", mode: "Line", offset: off, extra: ["datumAngle": fmt(ang), "datumHeight": fmt(h)], doc: &ed.doc)
                }
            case "Axis":
                guard case .pick(let pk) = try await ed.pickObject("Select a line, circle, arc or cylinder", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
                var mode = "Line"
                switch e.geometry {
                case .circle, .arc, .ellipse, .point: mode = "Center"
                case .solid: mode = "Cylinder"
                default: break
                }
                id = Datums.add("axis", source: "#\(pk.id)", mode: mode, extra: mode == "Center" ? ["datumHeight": "3000"] : [:], doc: &ed.doc)
            default:
                guard case .pick(let pk) = try await ed.pickObject("Select the source object", filter: { ed.doc.entity($0) != nil }) else { return }
                let m = try await ed.getKeyword("Point at [Center/Start/End/Mid]", ["Center", "Start", "End", "Mid"], defaultValue: "Center") ?? "Center"
                id = Datums.add("point", source: "#\(pk.id)", mode: m, doc: &ed.doc)
            }
            guard let did = id else { throw CommandError.invalid("The datum cannot be built from that object.") }
            ed.selection = [did]
            ed.print("Datum \(kind.lowercased()) #\(did) created; it follows its source.")
        }
    }

    static var sandbox: CommandDef {
        CommandDef("SANDBOX", aliases: ["SMOOVE", "STAMP", "DRAPE", "TERRAINGRID", "SANDBOXTOOLS"], category: "Site", summary: "Sandbox terrain tools: Grid (terrain from scratch), Smoove (raise/lower with falloff), Stamp (flat pad with side slopes), Drape (project curves onto the terrain), ToBIM (toposurface → BIM topography element).") { ed in
            let k = try await ed.getKeyword("Sandbox [Grid/Smoove/Stamp/Drape/ToBIM]", ["Grid", "Smoove", "Stamp", "Drape", "ToBIM"], defaultValue: "Smoove") ?? "Smoove"
            if k == "Grid" {
                let o = try await ed.requirePoint("Specify first corner")
                let w = try await ed.getPositive("Width", defaultValue: 20000), d = try await ed.getPositive("Depth", defaultValue: 20000)
                let s = try await ed.getPositive("Grid spacing", defaultValue: 1000)
                guard w / s * d / s <= 40000 else { throw CommandError.invalid("Too many grid points; use a larger spacing.") }
                let id = try ModelingCommands.addTopo(ed, Sandbox.grid(origin: o, width: w, depth: d, spacing: s), interval: ed.variableDouble("CONTOURINTERVAL", 500))
                ed.selection = [id]; ed.print("Grid terrain #\(id)."); return
            }
            guard case .pick(let pk) = try await ed.pickObject("Select a toposurface", filter: { ed.doc.entity($0)?.props["topo"] == "1" }), let topo = ModelingCommands.solidOf(ed.doc, pk.id) else { return }
            let (pts, base) = Sandbox.points(topo)
            @MainActor func replace(_ np: [Vec3]) throws {
                guard let s = Sandbox.rebuild(np, base: base) else { throw CommandError.invalid("The terrain could not be rebuilt.") }
                ModelingCommands.replace(ed, pk.id, with: s)
            }
            switch k {
            case "Smoove":
                let c = try await ed.requirePoint("Specify centre")
                let r = try await ed.getPositive("Radius", base: c, defaultValue: ed.variableDouble("SMOOVERADIUS", 3000))
                let h = try await ed.getDistance("Height (negative lowers)", defaultValue: 1000).value ?? 0
                ed.doc.setVariable("SMOOVERADIUS", fmt(r))
                try replace(Sandbox.smoove(pts, center: c, radius: r, height: h))
                ed.print("Terrain smooved by \(fmt(h)) over radius \(fmt(r)).")
            case "Stamp":
                guard let fp = try await ArchitectureCommands.selectBoundary(ed) else { return }
                let z = try await ed.getDistance("Pad elevation", defaultValue: Sandbox.surfaceZ(pts, at: GeometryOps.centroid(fp)) ?? 0).value ?? 0
                let off = try await ed.getPositive("Offset (side slope width)", defaultValue: 2000, allowZero: true)
                try replace(Sandbox.stamp(pts, footprint: fp, z: z, offset: off))
                ed.print("Pad stamped at \(fmt(z)).")
            case "Drape":
                ed.selection = []
                let ids = try await ed.getEntitySelection("Select curves to drape")
                var n = 0
                for id in ids where id != pk.id {
                    guard let e = ed.doc.entity(id), let path = ModelingCommands.path(ed.doc, id) else { continue }
                    let p3 = Sandbox.drape(path.closed ? path.points + [path.points[0]] : path.points, on: pts, step: max(100, BBox2(points: pts.map(\.xy)).width / 100))
                    guard p3.count >= 2 else { continue }
                    var ne = Entity(layer: e.layer, geometry: .polyline(PolylineGeom(points: p3.map(\.xy))))
                    ne.props["vertexZ"] = p3.map { fmt($0.z, 6) }.joined(separator: ",")
                    ne.props["drapedOn"] = "\(pk.id)"
                    ed.doc.add(ne); n += 1
                }
                ed.print("\(n) curve(s) draped on the terrain.")
            default:
                let del = try await ed.getYesNo("Delete the toposurface?", defaultValue: false)
                let ss = [topo]
                let elev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
                guard let g = InPlaceModels.component(from: ss, category: "Topography", levelElevation: elev) else { return }
                let id = ed.doc.addElement(.component(g), material: "Grass", name: "Topography")
                if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["inPlace"] = "1"; ed.doc.elements[i].props["fromTopo"] = "\(pk.id)" }
                if del { ed.doc.remove(ids: [pk.id]) }
                ed.selection = [id]
                ed.print("Topography element #\(id) created.")
            }
        }
    }
}
