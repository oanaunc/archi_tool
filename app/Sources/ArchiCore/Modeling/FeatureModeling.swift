// Oanarina Archi Tool — GPL-3.0-or-later
// Parametric (PartDesign-style) feature modelling on top of the solid history:
// - sketch-driven sources: associative revolve (M3D-016), follow-me (M3D-020), sweeps along 3D paths such as helices
//   (M3D-021), pad/pocket (M3D-022), holes with counterbore/countersink (M3D-023), grooves (M3D-024);
// - linear/polar patterns and mirrors of features or of the whole body (M3D-026/027);
// - split and general fuse of solids (M3D-033);
// - planar face editing by plane re-intersection: move/offset/taper faces and offset solids (M3D-041/046);
// - BRL-CAD style combination trees ("u a - b + c", M3D-095).
import Foundation

// MARK: - Pattern and mirror instances

public enum FeatureInstances {
    /// Point maps of every instance (the identity first); `mirroring` reverses the triangle winding.
    public static func transforms(pattern: FeaturePattern?, mirror: FeatureMirror?) -> [(map: (Vec3) -> Vec3, mirroring: Bool)] {
        var base: [(Vec3) -> Vec3] = [{ $0 }]
        if let p = pattern {
            switch p.kind {
            case .linear:
                let n1 = max(1, min(p.count, 500)), n2 = max(1, min(p.count2 ?? 1, 500))
                let s1 = p.step, s2 = p.step2 ?? .zero
                base = []
                for j in 0..<n2 {
                    for i in 0..<n1 {
                        let d = s1 * Double(i) + s2 * Double(j)
                        base.append({ $0 + d })
                    }
                }
            case .polar:
                let n = max(1, min(p.count, 500))
                let full = abs(p.angle) >= 2 * .pi - 1e-9
                let step = n <= 1 ? 0 : (full ? (p.angle < 0 ? -1.0 : 1.0) * 2 * .pi / Double(n) : p.angle / Double(n - 1))
                let c = p.center
                base = (0..<n).map { k in
                    let a = step * Double(k)
                    return { q in let r = Vec2(q.x, q.y).rotated(by: a, around: c); return Vec3(r.x, r.y, q.z) }
                }
            }
        }
        var out = base.map { (map: $0, mirroring: false) }
        if let m = mirror {
            let mf: (Vec3) -> Vec3
            if let z = m.z { mf = { Vec3($0.x, $0.y, 2 * z - $0.z) } }
            else {
                guard m.a.distance(to: m.b) > 1e-12 else { return out }
                let t = Transform2D.mirror(m.a, m.b)
                mf = { let r = t.apply($0.xy); return Vec3(r.x, r.y, $0.z) }
            }
            out += base.map { f in (map: { mf(f($0)) }, mirroring: true) }
        }
        return out
    }

    /// The tool and its pattern / mirror copies.
    public static func instances(of s: SolidGeom, pattern: FeaturePattern?, mirror: FeatureMirror?) -> [SolidGeom] {
        guard pattern != nil || mirror != nil else { return [s] }
        return transforms(pattern: pattern, mirror: mirror).enumerated().map { k, t in k == 0 ? s : SolidOps.mapped(s, mirroring: t.mirroring, t.map) }
    }
}

// MARK: - Sketch-driven sources

public enum FeatureSources {
    /// 3D points of a path entity: per-vertex elevations ("vertexZ", e.g. helices and 3D polylines) or its elevation
    /// property, raised by `z`.
    public static func path3(_ doc: ArchiDocument, _ id: EntityID, z: Double = 0) -> (points: [Vec3], closed: Bool)? {
        guard let e = doc.entity(id), let p = ModelingCommands.path(doc, id) else { return nil }
        if let vz = e.props["vertexZ"]?.split(separator: ",").compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
           case .polyline(let pl) = e.geometry, vz.count == pl.vertices.count, pl.vertices.allSatisfy({ abs($0.bulge) < 1e-12 }) {
            var pts: [Vec3] = []
            for (v, h) in zip(pl.vertices, vz) {
                let q = Vec3(v.p.x, v.p.y, h + z)
                if let l = pts.last, l.distance(to: q) < 1e-9 { continue }
                pts.append(q)
            }
            return pts.count >= 2 ? (pts, pl.closed) : nil
        }
        let ez = e.props["elevation"].flatMap(Double.init) ?? 0
        return (p.points.map { Vec3($0.x, $0.y, ez + z) }, p.closed)
    }

    /// Revolved solid of a closed plan profile about the axis a → b (in the XY plane at height z); the profile must lie
    /// on one side of the axis. `angle` in radians (2π = full).
    public static func revolveSolid(_ loop: [Vec2], axisA a: Vec2, axisB b: Vec2, angle: Double, z: Double) -> SolidGeom? {
        guard a.distance(to: b) > 1e-9, loop.count >= 3 else { return nil }
        let rot = (b - a).angle - .pi / 2
        let local = loop.map { ($0 - a).rotated(by: -rot) }
        let span = local.map { abs($0.x) }.max() ?? 0
        let tol = max(span, 1) * 1e-9
        guard local.allSatisfy({ $0.x >= -tol }) || local.allSatisfy({ $0.x <= tol }) else { return nil }
        var s = SolidGeom(kind: .revolve, origin: Vec3(a.x, a.y, z), profile: local, height: abs(angle) < 1e-9 ? 2 * .pi : min(abs(angle), 2 * .pi), rotation: rot)
        s.size = Vec3(1, 1, 1)
        return s
    }

    /// Straight or tapered extrusion of a closed loop from z by h (taper in radians: positive narrows towards the end).
    public static func extrudeSolid(_ loop0: [Vec2], z: Double, height h: Double, taper: Double = 0) -> SolidGeom? {
        var loop = RG.dedupe(loop0, closed: true)
        guard loop.count >= 3, abs(h) > 1e-9, abs(GeometryOps.signedArea(loop)) > 1e-12 else { return nil }
        if GeometryOps.signedArea(loop) < 0 { loop.reverse() }
        if abs(taper) < 1e-12 { return ModelingCommands.extrusion(loop, z: z, height: h) }
        guard abs(taper) < .pi / 2 - 1e-3 else { return nil }
        let top = SolidOps.inset(loop, abs(h) * tan(taper))
        guard SolidOps.sameOrientation(loop, top), abs(GeometryOps.signedArea(top)) > 1e-9, GeometryOps.signedArea(top) > 0 else { return nil }
        let rings = h > 0 ? [(pts: loop, z: z), (pts: top, z: z + h)] : [(pts: top, z: z + h), (pts: loop, z: z)]
        return try? SolidOps.closedLoft(rings)
    }

    /// Solid of revolution about a vertical axis through c from rings (radius, z) listed top → bottom (a closed mesh).
    public static func verticalRevolution(center c: Vec2, rings: [(r: Double, z: Double)], segments n0: Int = 0) -> SolidGeom? {
        guard rings.count >= 2 else { return nil }
        let rmax = rings.map(\.r).max() ?? 0
        guard rmax > 0 else { return nil }
        let n = n0 > 0 ? n0 : max(16, min(96, GeometryOps.segments(radius: rmax, sweep: 2 * .pi)))
        let ordered = Array(rings.reversed())   // bottom → top (rings are given top → bottom; equal heights keep their order)
        let rs = ordered.map { rr in (pts: (0..<n).map { k in c + Vec2.polar(max(rr.r, 1e-6), 2 * .pi * Double(k) / Double(n)) }, z: rr.z) }
        return try? SolidOps.closedLoft(rs)
    }

    public enum HoleType: Int, CaseIterable { case simple = 0, counterbore = 1, countersink = 2 }

    /// Hole tool (M3D-023): drilled down from `top` by `depth`, with an optional counterbore (diameter d2, depth2) or
    /// countersink (diameter d2, included angle). The tool extends slightly above the top so the cut is clean.
    public static func holeTool(center c: Vec2, top: Double, diameter d: Double, depth: Double, type: HoleType = .simple,
                                diameter2 d2: Double = 0, depth2: Double = 0, countersinkAngle: Double = .pi / 2) -> SolidGeom? {
        let r = d / 2
        guard r > 0, depth > 0 else { return nil }
        let over = max(1, depth * 0.01)
        var rings: [(r: Double, z: Double)] = []
        switch type {
        case .simple:
            rings = [(r, top + over), (r, top - depth)]
        case .counterbore:
            let r2 = d2 / 2
            guard r2 > r, depth2 > 0, depth2 < depth else { return holeTool(center: c, top: top, diameter: d, depth: depth) }
            rings = [(r2, top + over), (r2, top - depth2), (r, top - depth2), (r, top - depth)]
        case .countersink:
            let r2 = d2 / 2
            guard r2 > r, countersinkAngle > 0.05, countersinkAngle < .pi - 0.05 else { return holeTool(center: c, top: top, diameter: d, depth: depth) }
            let h = (r2 - r) / tan(countersinkAngle / 2)
            guard h < depth else { return holeTool(center: c, top: top, diameter: d, depth: depth) }
            rings = [(r2 + over * tan(countersinkAngle / 2), top + over), (r2, top), (r, top - h), (r, top - depth)]
        }
        return verticalRevolution(center: c, rings: rings)
    }

    /// Centre and diameter of a hole sketch entity (a point, or a circle whose diameter drives the hole).
    static func holeCentre(_ doc: ArchiDocument, _ id: EntityID) -> (Vec2, Double?)? {
        switch doc.entity(id)?.geometry {
        case .point(let p)?: return (p, nil)
        case .circle(let c)?: return (c.center, 2 * c.radius)
        case .arc(let a)?: return (a.center, 2 * a.radius)
        default: return nil
        }
    }

    /// Builds the solid of a feature source from the document's current sketch entities.
    public static func build(_ src: SolidSource, doc: ArchiDocument) -> SolidGeom? {
        let p = src.params ?? []
        switch src.kind {
        case .revolve:
            guard p.count >= 6, let pid = src.profiles.first, let l = ModelingCommands.loop(doc, pid) else { return nil }
            return revolveSolid(l, axisA: Vec2(p[0], p[1]), axisB: Vec2(p[2], p[3]), angle: p[4], z: p[5])
        case .sweep3D:
            guard let pid = src.profiles.first, let l = ModelingCommands.loop(doc, pid), let path = src.path, let pth = path3(doc, path, z: src.elevation) else { return nil }
            return ModelingCommands.sweepSolid(l, path: pth.points, closedPath: pth.closed)
        case .followMe:
            guard p.count >= 2, let pid = src.profiles.first, let l = ModelingCommands.loop(doc, pid), let path = src.path, let pth = path3(doc, path, z: src.elevation) else { return nil }
            return followMe(l, reference: Vec2(p[0], p[1]), path: pth.points, closed: pth.closed)
        case .extrude:
            guard p.count >= 2, let pid = src.profiles.first, let l = ModelingCommands.loop(doc, pid) else { return nil }
            return extrudeSolid(l, z: p[0], height: p[1], taper: p.count >= 3 ? p[2] : 0)
        case .hole:
            guard p.count >= 7, let pid = src.profiles.first, let (c, dd) = holeCentre(doc, pid) else { return nil }
            return holeTool(center: c, top: p[6], diameter: dd ?? p[0], depth: p[1], type: HoleType(rawValue: Int(p[2])) ?? .simple,
                            diameter2: p[3], depth2: p[4], countersinkAngle: p[5])
        case .csgTree:
            guard let ex = src.expression else { return nil }
            return CSGTrees.evaluate(ex) { ModelingCommands.solidOf(doc, $0) }
        case .script:
            guard let code = src.expression else { return nil }
            let r = SCAD.evaluate(code)
            guard !r.triangles.isEmpty else { return nil }
            let o = p.count >= 3 ? Vec3(p[0], p[1], p[2]) : .zero
            return SolidPrimitives.solid(r.triangles.map { ($0.0 + o, $0.1 + o, $0.2 + o) })
        case .binder:
            guard p.count >= 7, let sid = src.profiles.first, let s = ModelingCommands.solidOf(doc, sid) else { return nil }
            return ShapeBinders.build(s, mode: Int(p[0]), pick: Vec2(p[1], p[2]), faceMode: Int(p[3]), offset: Vec3(p[4], p[5], p[6]))
        case .sweep, .loft, .pipe:
            return AssociativeSolids.build(src, doc: doc)
        }
    }

    /// Follow-me (M3D-020): the profile keeps its position relative to the path start — profile x (from `reference`)
    /// becomes the offset to the left of the path, profile y the height above it — and is swept along the path.
    public static func followMe(_ loop: [Vec2], reference r: Vec2, path: [Vec3], closed: Bool) -> SolidGeom? {
        guard path.count >= 2, loop.count >= 3 else { return nil }
        // Profile x measured to the left of travel at the path start.
        let d0 = (path[1] - path[0]).xy.normalized
        let left = d0.perp
        let local = loop.map { q -> Vec2 in let v = q - r; return Vec2(v.dot(left), v.dot(d0)) }
        var acc = MeshAcc()
        SweepMesh.sweep(local, along: path, closedPath: closed, into: &acc)
        guard !acc.mesh.isEmpty else { return nil }
        return MeshTools.solid(from: MeshTools.triangles(acc.mesh), tolerance: 1e-6)
    }

    /// Rebuilds sketch-driven feature tools whose sketches changed. Returns true when a tool changed.
    @discardableResult
    public static func refreshTools(_ h: inout SolidHistory, doc: ArchiDocument) -> Bool {
        var changed = false
        for k in h.features.indices {
            guard let src = h.features[k].source, h.features[k].tool > 0, h.features[k].tool < h.solids.count,
                  let cur = AssociativeSolids.inputs(src, doc: doc), cur != src.inputs else { continue }
            var ns = src; ns.inputs = cur
            h.features[k].source = ns
            if var t = build(src, doc: doc) { t.history = nil; t.source = nil; h.solids[h.features[k].tool] = t }
            changed = true
        }
        return changed
    }

    /// Adds a sketch-driven feature to a solid (starting its history) and evaluates it.
    public static func addFeature(_ op: SolidFeature.Op, to base: SolidGeom, source: SolidSource, name: String, doc: ArchiDocument) -> SolidGeom? {
        guard var tool = build(source, doc: doc) else { return nil }
        tool.history = nil; tool.source = nil
        var h = base.history ?? SolidHistory(base: base)
        if base.history == nil { var b = base; b.history = nil; b.source = nil; h.solids[0] = b }
        h.solids.append(tool)
        var src = source; src.inputs = AssociativeSolids.inputs(source, doc: doc) ?? []
        h.features.append(SolidFeature(op: op, tool: h.solids.count - 1, name: name, source: src))
        guard var r = SolidHistoryEngine.evaluate(h) else { return nil }
        r.history = h; r.source = base.source
        return r
    }
}

// MARK: - Split / general fuse (M3D-033)

public enum SolidSplit {
    static func bounds(_ s: SolidGeom) -> BBox3 { var b = BBox3.empty; MeshTools.mesh(of: s).positions.forEach { b.add($0) }; return b }
    static func overlap(_ a: BBox3, _ b: BBox3) -> Bool {
        !(a.isEmpty || b.isEmpty || a.max.x < b.min.x || b.max.x < a.min.x || a.max.y < b.min.y || b.max.y < a.min.y || a.max.z < b.min.z || b.max.z < a.min.z)
    }
    static func tiny(_ s: SolidGeom, scale: Double) -> Bool { abs(CSG.volume(s)) <= max(scale, 1e-9) * 1e-9 }

    /// Splits `s` by the tool: the part inside the tool and the part outside, each separated into its bodies.
    public static func split(_ s: SolidGeom, by tool: SolidGeom) -> [SolidGeom] {
        let bs = bounds(s)
        guard overlap(bs, bounds(tool)) else { return [s] }
        let scale = pow(max(bs.size.x, bs.size.y, bs.size.z, 1), 3)
        var out: [SolidGeom] = []
        for op in [CSG.Operation.intersect, .subtract] {
            if let r = CSG.apply(op, s, tool) { out += SolidCheck.separate(r).filter { !tiny($0, scale: scale) } }
        }
        return out.isEmpty ? [s] : out
    }

    /// General fuse: cuts overlapping solids into non-overlapping pieces (every overlap becomes its own piece).
    public static func generalFuse(_ solids: [SolidGeom]) -> [SolidGeom] {
        guard var pieces = solids.first.map({ [$0] }) else { return [] }
        var scale = 1.0
        for s in solids { let b = bounds(s); scale = max(scale, pow(max(b.size.x, b.size.y, b.size.z, 1), 3)) }
        for s in solids.dropFirst() {
            var next: [SolidGeom] = []
            var rest: [SolidGeom] = [s]
            let bsn = bounds(s)
            for p in pieces {
                guard overlap(bounds(p), bsn) else { next.append(p); continue }
                if let i = CSG.apply(.intersect, p, s), !tiny(i, scale: scale) { next.append(i) }
                if let d = CSG.apply(.subtract, p, s), !tiny(d, scale: scale) { next.append(d) }
                rest = rest.flatMap { r -> [SolidGeom] in
                    guard overlap(bounds(r), bounds(p)) else { return [r] }
                    if let x = CSG.apply(.subtract, r, p), !tiny(x, scale: scale) { return [x] }
                    return []
                }
            }
            pieces = next + rest
        }
        return pieces.flatMap { SolidCheck.separate($0) }.filter { !tiny($0, scale: scale) }
    }
}

// MARK: - Planar face editing (M3D-041, M3D-046)

public enum PlanarFaces {
    /// Welded mesh with its triangles grouped into planar faces (n · x = d per face).
    public struct Analysis {
        public var vertices: [Vec3]
        public var triangles: [Int]
        /// Face index of every triangle.
        public var faceOf: [Int]
        public var normals: [Vec3]
        public var offsets: [Double]
        public var faceCount: Int { normals.count }
        /// Vertex indices of a face.
        public func vertices(ofFace f: Int) -> [Int] {
            var s = Set<Int>()
            for k in faceOf.indices where faceOf[k] == f { for j in 0..<3 { s.insert(triangles[3 * k + j]) } }
            return s.sorted()
        }
        public func area(ofFace f: Int) -> Double {
            var a = 0.0
            for k in faceOf.indices where faceOf[k] == f {
                let p = vertices[triangles[3 * k]], q = vertices[triangles[3 * k + 1]], r = vertices[triangles[3 * k + 2]]
                a += (q - p).cross(r - p).length / 2
            }
            return a
        }
    }

    public static func analyse(_ s: SolidGeom) -> Analysis {
        let w = SolidOps.welded(s)
        let v = w.vertices, t = w.triangles
        let nt = t.count / 3
        var b = BBox3.empty
        v.forEach { b.add($0) }
        let tol = max(b.isEmpty ? 1 : max(b.size.x, b.size.y, b.size.z), 1) * 1e-7
        let tn: [Vec3] = (0..<nt).map { k in (v[t[3 * k + 1]] - v[t[3 * k]]).cross(v[t[3 * k + 2]] - v[t[3 * k]]).normalized }
        var edgeTris: [[Int]: [Int]] = [:]
        for k in 0..<nt { for j in 0..<3 { let a = t[3 * k + j], c = t[3 * k + (j + 1) % 3]; edgeTris[[min(a, c), max(a, c)], default: []].append(k) } }
        var faceOf = Array(repeating: -1, count: nt)
        var normals: [Vec3] = [], offsets: [Double] = []
        for seed in 0..<nt where faceOf[seed] < 0 {
            let f = normals.count
            let n = tn[seed], d = n.dot(v[t[3 * seed]])
            normals.append(n); offsets.append(d)
            faceOf[seed] = f
            var stack = [seed]
            while let k = stack.popLast() {
                for j in 0..<3 {
                    let a = t[3 * k + j], c = t[3 * k + (j + 1) % 3]
                    for o in edgeTris[[min(a, c), max(a, c)]] ?? [] where faceOf[o] < 0 {
                        guard tn[o].dot(n) > 1 - 1e-9, (0..<3).allSatisfy({ abs(n.dot(v[t[3 * o + $0]]) - d) < tol }) else { continue }
                        faceOf[o] = f; stack.append(o)
                    }
                }
            }
        }
        return Analysis(vertices: v, triangles: t, faceOf: faceOf, normals: normals, offsets: offsets)
    }

    /// Face picked in plan: "top" (highest face above p facing up), "bottom", or "side" (nearest steep face).
    public static func pick(_ a: Analysis, at p: Vec2, mode: String = "top") -> Int? {
        var best: Int? = nil, bestKey = -Double.infinity
        for k in a.faceOf.indices {
            let t0 = a.vertices[a.triangles[3 * k]], t1 = a.vertices[a.triangles[3 * k + 1]], t2 = a.vertices[a.triangles[3 * k + 2]]
            let nn = a.normals[a.faceOf[k]]
            if mode == "side" {
                guard abs(nn.z) < 0.9 else { continue }
                let d = GeometryOps.distance(from: p, toPolyline: [t0.xy, t1.xy, t2.xy, t0.xy])
                let c = (t0 + t1 + t2) / 3
                let facing = Vec2(nn.x, nn.y).dot(p - c.xy) >= -1e-9 ? 0.0 : 1e-3
                let key = -(d + facing)
                if key > bestKey { bestKey = key; best = a.faceOf[k] }
            } else {
                let up = mode != "bottom"
                guard up ? nn.z > 0.1 : nn.z < -0.1, GeometryOps.pointInPolygon(p, [t0.xy, t1.xy, t2.xy]) else { continue }
                let z = t0.z - (nn.x * (p.x - t0.x) + nn.y * (p.y - t0.y)) / nn.z
                let key = up ? z : -z
                if key > bestKey { bestKey = key; best = a.faceOf[k] }
            }
        }
        return best
    }

    /// New vertex positions for new face planes: each vertex moves the least distance that puts it on all the planes of
    /// its faces (exact where three independent planes meet). nil when a triangle would flip or collapse.
    public static func solve(_ a: Analysis, normals: [Vec3], offsets: [Double]) -> [Vec3]? {
        let nv = a.vertices.count
        var incident = Array(repeating: Set<Int>(), count: nv)
        for k in a.faceOf.indices { for j in 0..<3 { incident[a.triangles[3 * k + j]].insert(a.faceOf[k]) } }
        let eps = 1e-7
        var out = a.vertices
        for i in 0..<nv {
            let v = a.vertices[i]
            var m = [[eps, 0, 0], [0, eps, 0], [0, 0, eps]]
            var r = [eps * v.x, eps * v.y, eps * v.z]
            for f in incident[i] {
                let n = normals[f], d = offsets[f]
                let nn = [n.x, n.y, n.z]
                for p in 0..<3 { for q in 0..<3 { m[p][q] += nn[p] * nn[q] }; r[p] += nn[p] * d }
            }
            guard let x = solve3(m, r) else { return nil }
            out[i] = Vec3(x[0], x[1], x[2])
        }
        // Validity: no triangle flips or collapses.
        var b = BBox3.empty
        out.forEach { b.add($0) }
        let areaTol = pow(max(b.isEmpty ? 1 : max(b.size.x, b.size.y, b.size.z), 1), 2) * 1e-12
        for k in a.faceOf.indices {
            let i0 = a.triangles[3 * k], i1 = a.triangles[3 * k + 1], i2 = a.triangles[3 * k + 2]
            let n0 = (a.vertices[i1] - a.vertices[i0]).cross(a.vertices[i2] - a.vertices[i0])
            let n1 = (out[i1] - out[i0]).cross(out[i2] - out[i0])
            if n0.length > areaTol && (n1.length <= areaTol || n1.dot(n0) <= 0) { return nil }
        }
        return out
    }

    static func solve3(_ m0: [[Double]], _ r0: [Double]) -> [Double]? {
        var m = m0, r = r0
        for c in 0..<3 {
            var piv = c
            for k in (c + 1)..<3 where abs(m[k][c]) > abs(m[piv][c]) { piv = k }
            guard abs(m[piv][c]) > 1e-300 else { return nil }
            m.swapAt(c, piv); r.swapAt(c, piv)
            for k in 0..<3 where k != c {
                let f = m[k][c] / m[c][c]
                if f == 0 { continue }
                for j in c..<3 { m[k][j] -= f * m[c][j] }
                r[k] -= f * r[c]
            }
        }
        return (0..<3).map { r[$0] / m[$0][$0] }
    }

    static func rebuilt(_ a: Analysis, _ v: [Vec3]) -> SolidGeom? {
        guard !v.isEmpty else { return nil }
        var b = BBox3.empty
        v.forEach { b.add($0) }
        let s = SolidGeom(kind: .mesh, origin: b.min, meshVertices: v, meshTriangles: a.triangles)
        return CSG.volume(s) > 0 ? s : nil
    }

    /// Offsets every face outwards by `distance` (negative shrinks). nil when the offset changes the topology.
    public static func offsetSolid(_ s: SolidGeom, distance d: Double) -> SolidGeom? {
        let a = analyse(s)
        guard a.faceCount >= 4, SolidOps.isClosedManifold(vertices: a.vertices, triangles: a.triangles) else { return nil }
        guard let v = solve(a, normals: a.normals, offsets: a.offsets.map { $0 + d }) else { return nil }
        return rebuilt(a, v)
    }

    /// Moves one face along its normal by `distance` (outwards positive); the neighbouring faces stretch.
    public static func offsetFace(_ s: SolidGeom, analysis a: Analysis, face f: Int, distance d: Double) -> SolidGeom? {
        guard f >= 0, f < a.faceCount else { return nil }
        var o = a.offsets
        o[f] += d
        guard let v = solve(a, normals: a.normals, offsets: o) else { return nil }
        return rebuilt(a, v)
    }

    /// Moves several faces by a vector (their planes translate; the rest of the solid stretches to follow).
    public static func moveFaces(_ s: SolidGeom, analysis a: Analysis, faces: Set<Int>, by dv: Vec3) -> SolidGeom? {
        var o = a.offsets
        for f in faces where f >= 0 && f < a.faceCount { o[f] += a.normals[f].dot(dv) }
        guard let v = solve(a, normals: a.normals, offsets: o) else { return nil }
        return rebuilt(a, v)
    }

    /// Tapers a non-horizontal face by `angle` about its lowest horizontal line (positive leans it inwards).
    public static func taperFace(_ s: SolidGeom, analysis a: Analysis, face f: Int, angle: Double) -> SolidGeom? {
        guard f >= 0, f < a.faceCount, abs(angle) < .pi / 2 - 1e-3 else { return nil }
        let n = a.normals[f]
        let k = n.cross(Vec3(0, 0, 1))
        guard k.length > 1e-6 else { return nil }
        let axis = k.normalized
        let c = cos(angle), sn = sin(angle)
        let nr = (n * c + axis.cross(n) * sn + axis * (axis.dot(n) * (1 - c))).normalized
        guard let pivot = a.vertices(ofFace: f).map({ a.vertices[$0] }).min(by: { $0.z < $1.z }) else { return nil }
        var ns = a.normals, o = a.offsets
        ns[f] = nr; o[f] = nr.dot(pivot)
        guard let v = solve(a, normals: ns, offsets: o) else { return nil }
        return rebuilt(a, v)
    }
}

// MARK: - BRL-CAD style combination trees (M3D-095)

public enum CSGTrees {
    public struct Member: Hashable { public var op: Character; public var id: EntityID }

    /// Parses "u #1 - #2 + #3 u #4" (ids with or without '#'; the leading 'u' is optional) into union groups:
    /// within a group '-' subtracts and '+' intersects, left to right; groups are unioned (BRL-CAD precedence).
    public static func parse(_ expr: String) -> [[Member]]? {
        var toks: [String] = []
        var cur = ""
        for ch in expr {
            if ch == " " || ch == "," || ch == "\t" || ch == "\n" { if !cur.isEmpty { toks.append(cur); cur = "" }; continue }
            if ch == "-" || ch == "+" { if !cur.isEmpty { toks.append(cur); cur = "" }; toks.append(String(ch)); continue }
            cur.append(ch)
        }
        if !cur.isEmpty { toks.append(cur) }
        var groups: [[Member]] = []
        var op: Character = "u"
        var expectOperand = true
        for tk in toks {
            let low = tk.lowercased()
            if low == "u" || low == "-" || low == "+" {
                guard expectOperand == false || (groups.isEmpty && low == "u") else { return nil }
                op = low == "u" ? "u" : Character(low); expectOperand = true
                continue
            }
            let digits = tk.hasPrefix("#") ? String(tk.dropFirst()) : tk
            guard expectOperand, let id = EntityID(digits) else { return nil }
            if op == "u" || groups.isEmpty { groups.append([Member(op: "u", id: id)]) } else { groups[groups.count - 1].append(Member(op: op, id: id)) }
            expectOperand = false
        }
        return groups.isEmpty || expectOperand ? nil : groups
    }

    public static func ids(_ expr: String) -> [EntityID] {
        var seen = Set<EntityID>()
        return (parse(expr) ?? []).flatMap { $0 }.map(\.id).filter { seen.insert($0).inserted }
    }

    /// Normalised text of a parsed tree ("u #1 - #2 u #3").
    public static func format(_ groups: [[Member]]) -> String {
        groups.map { g in g.map { "\($0.op) #\($0.id)" }.joined(separator: " ") }.joined(separator: " ")
    }

    /// Evaluates the tree with the given member solids. nil when empty or a member is missing.
    public static func evaluate(_ expr: String, solid: (EntityID) -> SolidGeom?) -> SolidGeom? {
        guard let groups = parse(expr) else { return nil }
        var result: SolidGeom? = nil
        for g in groups {
            guard let first = g.first, let s0 = solid(first.id) else { return nil }
            var acc: SolidGeom? = s0
            for m in g.dropFirst() {
                guard let s = solid(m.id) else { return nil }
                guard let a = acc else { break }
                acc = CSG.apply(m.op == "-" ? .subtract : .intersect, a, s)
            }
            guard let r = acc else { continue }
            if let cur = result { result = CSG.apply(.union, cur, r) ?? cur } else { result = r }
        }
        return result
    }

    /// Indented tree listing.
    public static func describe(_ expr: String, name: (EntityID) -> String) -> [String] {
        guard let groups = parse(expr) else { return ["(invalid combination)"] }
        var out: [String] = []
        for g in groups {
            for (k, m) in g.enumerated() { out.append((k == 0 ? "u " : "   \(m.op) ") + name(m.id)) }
        }
        return out
    }
}

// MARK: - Sub-shape binders (M3D-029)

public enum ShapeBinders {
    public static let faceModes = ["top", "bottom", "side"]

    /// Copy of a solid (mode 0) or of the face picked at `pick` (mode 1, face mode top/bottom/side), moved by `offset`.
    public static func build(_ s: SolidGeom, mode: Int, pick: Vec2, faceMode: Int, offset o: Vec3) -> SolidGeom? {
        if mode == 0 {
            var c = s; c.history = nil; c.source = nil
            return o == .zero ? SolidOps.mapped(c, mirroring: false) { $0 } : SolidOps.translated(c, by: o)
        }
        let a = PlanarFaces.analyse(s)
        guard let f = PlanarFaces.pick(a, at: pick, mode: faceModes[min(max(faceMode, 0), 2)]) else { return nil }
        var tris: [Tri3] = []
        for k in a.faceOf.indices where a.faceOf[k] == f {
            tris.append((a.vertices[a.triangles[3 * k]] + o, a.vertices[a.triangles[3 * k + 1]] + o, a.vertices[a.triangles[3 * k + 2]] + o))
        }
        let w = MeshTools.weld(tris, tolerance: 1e-6)
        guard !w.triangles.isEmpty else { return nil }
        var b = BBox3.empty; w.vertices.forEach { b.add($0) }
        return SolidGeom(kind: .mesh, origin: b.min, meshVertices: w.vertices, meshTriangles: w.triangles)
    }
}
