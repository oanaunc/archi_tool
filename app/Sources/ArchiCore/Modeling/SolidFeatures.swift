// Oanarina Archi Tool — GPL-3.0-or-later
// Solid history light (feature list per solid, regenerating booleans), associative sweeps/lofts, push/pull of solid
// faces, and 2D section blocks cut from solids by a plane.
import Foundation

// MARK: - Feature history

public enum SolidHistoryEngine {
    /// Evaluates a history: the base followed by every unsuppressed feature. nil when the result is empty.
    public static func evaluate(_ h: SolidHistory) -> SolidGeom? {
        guard !h.solids.isEmpty else { return nil }
        var acc: SolidGeom? = h.base
        for f in h.features where !f.suppressed {
            guard f.tool >= 0, f.tool < h.solids.count, let a = acc else { continue }
            let op: CSG.Operation = f.op == .union ? .union : (f.op == .subtract ? .subtract : .intersect)
            acc = CSG.apply(op, a, h.solids[f.tool])
            if acc == nil && f.op == .union { acc = a }
        }
        return acc
    }

    /// Records a boolean on `base` (starting a history when it has none) and returns the evaluated solid with its history.
    public static func record(_ op: SolidFeature.Op, base: SolidGeom, tool: SolidGeom, name: String? = nil) -> SolidGeom? {
        var h = base.history ?? SolidHistory(base: base)
        var t = tool; t.history = nil; t.source = nil
        h.solids.append(t)
        h.features.append(SolidFeature(op: op, tool: h.solids.count - 1, name: name ?? "\(op.rawValue.capitalized) \(h.features.count + 1)"))
        guard var r = evaluate(h) else { return nil }
        r.history = h
        return r
    }

    /// Re-evaluates a solid that carries a history (after editing features). nil when the result is empty.
    public static func regenerate(_ s: SolidGeom) -> SolidGeom? {
        guard let h = s.history, var r = evaluate(h) else { return s.history == nil ? s : nil }
        r.history = h
        return r
    }

    /// Moves a feature's tool solid.
    public static func moveTool(_ h: inout SolidHistory, feature i: Int, by d: Vec3) {
        guard i >= 0, i < h.features.count else { return }
        let t = h.features[i].tool
        guard t > 0, t < h.solids.count else { return }
        h.solids[t] = SolidOps.mapped(h.solids[t], mirroring: false) { $0 + d }
    }

    /// Human-readable feature list.
    public static func describe(_ h: SolidHistory) -> [String] {
        var out = ["0  Base: \(h.base.kind.rawValue)"]
        for (i, f) in h.features.enumerated() {
            out.append("\(i + 1)  \(f.name.isEmpty ? f.op.rawValue : f.name) [\(f.op.rawValue) \(h.solids[f.tool].kind.rawValue)]\(f.suppressed ? " (suppressed)" : "")")
        }
        return out
    }
}

// MARK: - Associative sweeps and lofts

public enum AssociativeSolids {
    /// Current geometries of a source's inputs (nil when one was deleted).
    static func inputs(_ src: SolidSource, doc: ArchiDocument) -> [Geometry]? {
        var ids = src.profiles
        if let p = src.path { ids.append(p) }
        var out: [Geometry] = []
        for id in ids { guard let e = doc.entity(id) else { return nil }; out.append(e.geometry) }
        return out
    }

    /// Builds the solid of a source from the document's current profile/path entities.
    public static func build(_ src: SolidSource, doc: ArchiDocument) -> SolidGeom? {
        switch src.kind {
        case .sweep:
            guard let pid = src.profiles.first, let p = ModelingCommands.loop(doc, pid), let path = src.path, let pth = ModelingCommands.path(doc, path) else { return nil }
            let path3 = pth.points.map { Vec3($0.x, $0.y, src.elevation) }
            if abs(src.twist) > 1e-12 || abs(src.endScale - 1) > 1e-12 {
                let c = GeometryOps.centroid(p)
                let m = SurfaceTools.twistedSweep(p.map { $0 - c }, along: path3, twist: src.twist, endScale: src.endScale, closedPath: pth.closed)
                return m.isEmpty ? nil : MeshTools.solid(from: MeshTools.triangles(m), tolerance: 1e-6)
            }
            return ModelingCommands.sweepSolid(p, path: path3, closedPath: pth.closed)
        case .pipe:
            guard let path = src.path, let pth = ModelingCommands.path(doc, path), src.heights.count >= 2 else { return nil }
            return ModelingCommands.pipeSolid(pth.points.map { Vec3($0.x, $0.y, src.elevation) }, closed: pth.closed, radius: src.heights[0], wall: src.heights[1])
        case .loft:
            let loops = src.profiles.compactMap { ModelingCommands.loop(doc, $0) }
            guard loops.count == src.profiles.count, loops.count >= 2, src.heights.count == loops.count else { return nil }
            let count = min(256, max(24, loops.map(\.count).max()! * 4))
            var rings = zip(loops, src.heights).map { l, h in SweepMesh.resample(l, count: count).map { Vec3($0.x, $0.y, h) } }
            if src.heights[1] < src.heights[0] { rings = rings.map { $0.reversed() } }
            var acc = MeshAcc()
            SweepMesh.loft(rings, into: &acc)
            return acc.mesh.isEmpty ? nil : MeshTools.solid(from: MeshTools.triangles(acc.mesh), tolerance: 1e-6)
        }
    }

    /// A solid with its source attached (and the input snapshot taken).
    public static func attach(_ s: SolidGeom, source: SolidSource, doc: ArchiDocument) -> SolidGeom {
        var src = source
        src.inputs = inputs(source, doc: doc) ?? []
        var r = s; r.source = src
        return r
    }

    /// Regenerates associative solids whose sources changed; feature histories are re-applied on the new base.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let snap = doc
        for (i, e) in snap.entities.enumerated() {
            guard case .solid(let s) = e.geometry, let src = s.source, let cur = inputs(src, doc: snap), cur != src.inputs else { continue }
            guard var n = build(src, doc: snap) else { continue }
            var ns = src; ns.inputs = cur
            if var h = s.history {
                var b = n; b.history = nil; b.source = nil
                h.solids[0] = b
                if var r = SolidHistoryEngine.evaluate(h) { r.history = h; n = r }
            }
            n.source = ns
            doc.entities[i].geometry = .solid(n)
            changed = true
        }
        return changed
    }
}

// MARK: - Push/pull faces of solids

public enum FacePushPull {
    public struct Face {
        /// Triangles of the (planar, connected) face.
        public var triangles: [(Vec3, Vec3, Vec3)]
        public var normal: Vec3
        public var area: Double
        /// Boundary edges (outer and holes) of the face.
        public var boundary: [(Vec3, Vec3)]
    }

    /// The planar face of a solid picked in plan at `p`: `top` = the highest face above p facing up (or the lowest facing
    /// down with `bottom`); `side` = the vertical face nearest to p in plan (within `tolerance`).
    public static func pick(_ s: SolidGeom, at p: Vec2, mode: String = "top", tolerance: Double = .infinity) -> Face? {
        let tris = MeshTools.triangles(MeshTools.mesh(of: s))
        guard !tris.isEmpty else { return nil }
        var best: Int? = nil, bestKey = -Double.infinity
        for (k, t) in tris.enumerated() {
            let n = (t.1 - t.0).cross(t.2 - t.0)
            guard n.length > 1e-12 else { continue }
            let nn = n.normalized
            switch mode {
            case "side":
                guard abs(nn.z) < 0.1 else { continue }
                let d = GeometryOps.distance(from: p, toPolyline: [t.0.xy, t.1.xy, t.2.xy, t.0.xy])
                // Prefer the face whose outward normal points towards the picked point.
                let c = (t.0 + t.1 + t.2) / 3
                let facing = Vec2(nn.x, nn.y).dot(p - c.xy) >= -1e-9 ? 0.0 : 1e-3
                let key = -(d + facing)
                if d <= tolerance, key > bestKey { bestKey = key; best = k }
            default:
                let up = mode != "bottom"
                guard up ? nn.z > 0.1 : nn.z < -0.1, Triangulator.inTriangle(p, t.0.xy, t.1.xy, t.2.xy) || Triangulator.inTriangle(p, t.0.xy, t.2.xy, t.1.xy) else { continue }
                // Height of the triangle's plane at p.
                let z = t.0.z - (nn.x * (p.x - t.0.x) + nn.y * (p.y - t.0.y)) / nn.z
                let key = up ? z : -z
                if key > bestKey { bestKey = key; best = k }
            }
        }
        guard let b = best else { return nil }
        return face(tris, seed: b)
    }

    /// Connected coplanar triangles around a seed triangle.
    static func face(_ tris: [(Vec3, Vec3, Vec3)], seed: Int) -> Face {
        let t0 = tris[seed]
        let n = (t0.1 - t0.0).cross(t0.2 - t0.0).normalized
        let d0 = n.dot(t0.0)
        var b = BBox3.empty
        for t in tris { b.add(t.0); b.add(t.1); b.add(t.2) }
        let tol = max(b.size.x, b.size.y, b.size.z, 1) * 1e-7
        func key(_ v: Vec3) -> [Int64] { [Int64((v.x / tol).rounded()), Int64((v.y / tol).rounded()), Int64((v.z / tol).rounded())] }
        let coplanar = tris.indices.filter { i in
            let t = tris[i]
            let m = (t.1 - t.0).cross(t.2 - t.0)
            guard m.length > 1e-14, m.normalized.dot(n) > 1 - 1e-6 else { return false }
            return abs(n.dot(t.0) - d0) < tol * 10 && abs(n.dot(t.1) - d0) < tol * 10 && abs(n.dot(t.2) - d0) < tol * 10
        }
        // Flood fill across shared edges.
        var byEdge: [[[Int64]]: [Int]] = [:]
        func ek(_ a: Vec3, _ b: Vec3) -> [[Int64]] { let ka = key(a), kb = key(b); return ka.lexicographicallyPrecedes(kb) ? [ka, kb] : [kb, ka] }
        for i in coplanar { let t = tris[i]; for (a, c) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] { byEdge[ek(a, c), default: []].append(i) } }
        var inFace = Set([seed]), stack = [seed]
        while let i = stack.popLast() {
            let t = tris[i]
            for (a, c) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] { for j in byEdge[ek(a, c)] ?? [] where !inFace.contains(j) { inFace.insert(j); stack.append(j) } }
        }
        var count: [[[Int64]]: Int] = [:]
        var area = 0.0
        for i in inFace {
            let t = tris[i]
            area += (t.1 - t.0).cross(t.2 - t.0).length / 2
            for (a, c) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] { count[ek(a, c), default: 0] += 1 }
        }
        var boundary: [(Vec3, Vec3)] = []
        for i in inFace.sorted() {
            let t = tris[i]
            for (a, c) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] where count[ek(a, c)] == 1 { boundary.append((a, c)) }
        }
        return Face(triangles: inFace.sorted().map { tris[$0] }, normal: n, area: area, boundary: boundary)
    }

    /// Prism swept from a face along its normal by `distance` (outward positive).
    public static func prism(_ f: Face, distance d: Double) -> [(Vec3, Vec3, Vec3)] {
        let off = f.normal * d
        var out: [(Vec3, Vec3, Vec3)] = []
        // Outward orientation for d > 0: base (the face) points inwards (−n), the moved cap outwards (+n).
        for t in f.triangles {
            out.append((t.0, t.2, t.1))
            out.append((t.0 + off, t.1 + off, t.2 + off))
        }
        // Face triangles are CCW about +n, so boundary edges (a→b) run CCW; side quads a, b, b', a' face outwards.
        for (a, b) in f.boundary {
            out.append((a, b, b + off)); out.append((a, b + off, a + off))
        }
        if d < 0 { return out.map { ($0.0, $0.2, $0.1) } }
        return out
    }

    /// Pushes (negative) or pulls (positive) a face of a solid; returns the new solid (history recorded when the solid has one).
    public static func apply(_ s: SolidGeom, face f: Face, distance d: Double) -> SolidGeom? {
        guard abs(d) > 1e-9 else { return s }
        let tool = MeshTools.solid(from: prism(f, distance: d), tolerance: 1e-6)
        if s.history != nil { return SolidHistoryEngine.record(d > 0 ? .union : .subtract, base: s, tool: tool, name: d > 0 ? "Pull face" : "Push face") }
        return CSG.apply(d > 0 ? .union : .subtract, s, tool)
    }
}

// MARK: - Section blocks from solids

public enum SolidSections {
    /// 2D section of the solids (and optionally the BIM model) cut by the vertical plane through a → b, looking to the
    /// left of a → b: cut faces hatched (poche) with heavy outlines, geometry beyond in projection. Drawing coordinates:
    /// x along a → b, y = Z.
    public static func vertical(doc: ArchiDocument, a: Vec2, b: Vec2, ids: Set<EntityID>? = nil, includeModel: Bool = false) -> [DrawEntry] {
        guard a.distance(to: b) > 1e-9, let proj = ElevationBuilder.projection(.section, section: (a, b)) else { return [] }
        var groups: [MeshGroup] = []
        for e in doc.entities {
            guard case .solid = e.geometry, ids?.contains(e.id) ?? true, doc.isVisible(layer: e.layer) else { continue }
            groups += MeshBuilder.groups(for: e, doc: doc)
        }
        if includeModel { groups += MeshBuilder.build(doc: doc).filter { $0.kind != "solid" } }
        guard !groups.isEmpty else { return [] }
        var d = doc; d.setVariable("VIEWANNOTATIONS", "0")
        return ElevationBuilder.entries(groups: groups, doc: d, proj: proj, cut: true).filter { e in
            // Drop the ground line: a section block of solids stands alone.
            !(e.id == nil && e.items.count == 1)
        }
    }

    /// Horizontal section (plan cut) of solids at height z: closed cut loops (world XY).
    public static func horizontal(doc: ArchiDocument, z: Double, ids: Set<EntityID>? = nil) -> [[Vec2]] {
        var out: [[Vec2]] = []
        let proj = ElevationBuilder.Projection(viewDir: Vec3(0, 0, -1), xf: { $0.x }, depthf: { $0.z - z }, yf: { $0.y })
        for e in doc.entities {
            guard case .solid(let s) = e.geometry, ids?.contains(e.id) ?? true else { continue }
            let loops = ElevationBuilder.sectionLoops(MeshTools.mesh(of: s), proj)
            out += loops.closed
        }
        return out
    }

    /// Stores a section as a block (description "view:solidsection:…" so VIEWUPDATE regenerates it). Returns the block name.
    @discardableResult
    public static func makeBlock(_ doc: inout ArchiDocument, a: Vec2, b: Vec2, name: String? = nil, includeModel: Bool = false) -> String? {
        let entries = vertical(doc: doc, a: a, b: b, includeModel: includeModel)
        guard !entries.isEmpty else { return nil }
        var box = BBox2.empty
        for e in entries { box.add(e.bounds) }
        var n = 1
        while doc.blocks["SECTION-SOLID-\(n)"] != nil { n += 1 }
        let bn = name ?? "SECTION-SOLID-\(n)"
        let spec = "solidsection:\(fmt(a.x, 6)):\(fmt(a.y, 6)):\(fmt(b.x, 6)):\(fmt(b.y, 6)):\(includeModel ? 1 : 0)"
        doc.blocks[bn] = Block(name: bn, basePoint: box.min, entities: ArchitectureCommands.entities(from: entries), description: "view:" + spec)
        return bn
    }
}
