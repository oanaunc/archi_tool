// Oanarina Archi Tool — GPL-3.0-or-later
// Evaluates document family definitions into 3D meshes and plan symbols, and keeps instances in step with them.
import Foundation

/// A rigid placement: rotate about Z by `angle`, then translate by `origin`.
struct FamilyPlacement {
    var origin: Vec3 = .zero
    var angle: Double = 0
    func apply(_ p: Vec3) -> Vec3 {
        let c = cos(angle), s = sin(angle)
        return Vec3(origin.x + p.x * c - p.y * s, origin.y + p.x * s + p.y * c, origin.z + p.z)
    }
    func applyVector(_ v: Vec3) -> Vec3 { let c = cos(angle), s = sin(angle); return Vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z) }
    /// self ∘ inner (inner applied first).
    func then(_ inner: FamilyPlacement) -> FamilyPlacement {
        FamilyPlacement(origin: apply(inner.origin), angle: angle + inner.angle)
    }
}

public enum FamilyEngine {
    public struct Result {
        /// Material → accumulated mesh (world coordinates of the placement).
        var parts: [String: MeshAcc] = [:]
        /// Plan outlines (world XY).
        public var outlines: [[Vec2]] = []
        /// Symbolic plan lines (world XY): points, closed, dashed.
        public var symbols: [(points: [Vec2], closed: Bool, dashed: Bool)] = []
        public var errors: [String] = []
        /// Reference plane positions (family coordinates of the top-level family): name → (axis, offset).
        public var planes: [String: (axis: String, offset: Double)] = [:]
        public var bounds: BBox3 {
            var b = BBox3.empty
            for (_, a) in parts { for p in a.mesh.positions { b.add(p) } }
            return b
        }
    }

    /// Profile vertices evaluated over parameter values (nil when fewer than 3 valid points).
    public static func profilePoints(_ prof: FamilyProfile, values: [String: Double]) -> [Vec2]? {
        var pts: [Vec2] = []
        if prof.points.isEmpty, let lib = prof.library {
            let w = prof.width.flatMap { FamilyExpr.evaluate($0, values) } ?? values["width"] ?? 100
            let h = prof.height.flatMap { FamilyExpr.evaluate($0, values) } ?? values["height"] ?? 100
            return ProfileLibrary.builtin(lib, width: w, height: h)
        }
        for p in prof.points where p.count >= 2 {
            guard let x = FamilyExpr.evaluate(p[0], values), let y = FamilyExpr.evaluate(p[1], values) else { continue }
            pts.append(Vec2(x, y))
        }
        pts = RG.dedupe(pts, closed: true)
        guard pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-12 else { return nil }
        if GeometryOps.signedArea(pts) < 0 { pts.reverse() }
        return pts
    }

    static func profile(_ name: String?, _ def: FamilyDefinition, values: [String: Double], doc: ArchiDocument, w: Double, h: Double) -> [Vec2]? {
        guard let n = name else { return nil }
        if let p = def.profile(n) { return profilePoints(p, values: values) }
        return ProfileLibrary.outline(n, width: w, height: h, doc: doc)
    }

    /// Instance parameter overrides stored on an element: props "fp.<Name>" (and "familyType").
    public static func overrides(_ props: [String: String]) -> [String: String] {
        var o: [String: String] = [:]
        for (k, v) in props where k.hasPrefix("fp.") { o[String(k.dropFirst(3))] = v }
        return o
    }

    /// Builds a family at a placement. `extra` supplies host-driven values (Width/Height of an opening).
    static func build(_ def: FamilyDefinition, doc: ArchiDocument, overrides: [String: String], type: String?, extra: [String: Double] = [:],
                      placement: FamilyPlacement, depth: Int = 0, into r: inout Result) {
        guard depth < 6 else { r.errors.append("\(def.name): nesting too deep"); return }
        var ext = GlobalParameters.values(doc)
        for (k, x) in extra { ext[k.lowercased()] = x }
        let res = FamilyExpr.resolve(def, overrides: overrides, type: type, extra: ext)
        r.errors += res.errors.map { "\(def.name).\($0)" }
        var v = res.values
        // Reference planes: evaluated in order; their names become values usable by forms and profiles.
        for rp in def.referencePlanes {
            if let x = FamilyExpr.evaluate(rp.offset, v) { v[rp.name.lowercased()] = x; r.planes[rp.name] = (rp.axis.lowercased(), x) }
            else { r.errors.append("\(def.name).\(rp.name): cannot evaluate \"\(rp.offset)\"") }
        }
        // Text-typed parameters with validation (URL, family type — PAR-020).
        for p in def.parameters where p.kind == .url || p.kind == .familyType {
            if let msg = p.kind.validate(res.text[p.name.lowercased()] ?? p.value, families: doc.families) { r.errors.append("\(def.name).\(p.name): \(msg)") }
        }
        func e(_ s: String?, _ d: Double) -> Double { guard let s = s, !s.isEmpty else { return d }; return FamilyExpr.evaluate(s, v) ?? d }
        var solids: [String: MeshAcc] = [:]
        var voids = MeshAcc()
        let detail = FamilyVisibility.level(doc)
        // Symbolic linework (PAR-007) at this detail level.
        for sy in def.symbolic where FamilyVisibility.includes(sy.detail, detail) {
            if let vis = sy.visible, !vis.isEmpty, e(vis, 1) == 0 { continue }
            let pts = sy.points.compactMap { q -> Vec2? in
                guard q.count >= 2, let x = FamilyExpr.evaluate(q[0], v), let y = FamilyExpr.evaluate(q[1], v) else { return nil }
                return placement.apply(Vec3(x, y, 0)).xy
            }
            if pts.count >= 2 { r.symbols.append((pts, sy.closed, sy.dashed)) }
        }
        for f in def.forms {
            if let vis = f.visible, !vis.isEmpty, e(vis, 1) == 0 { continue }
            // Visibility by detail level and view (PAR-008).
            if !f.shows(detail: detail) { continue }
            let count = max(1, min(500, Int(e(f.arrayCount, 1).rounded())))
            let step = Vec3(e(f.arrayDX, 0), e(f.arrayDY, 0), e(f.arrayDZ, 0))
            var mat = f.material ?? "Wood"
            if mat.hasPrefix("=") { mat = res.text[String(mat.dropFirst()).lowercased()] ?? "Wood" }
            for k in 0..<count {
                let local = FamilyPlacement(origin: Vec3(e(f.x, 0), e(f.y, 0), e(f.z, 0)) + step * Double(k), angle: e(f.rotation, 0) * .pi / 180)
                let pl = placement.then(local)
                if f.kind == .nested {
                    // family "=Param" reads a family-type parameter ("Family" or "Family:Type").
                    var fam = f.family, ftype = f.dims["type"]
                    if let n = fam, n.hasPrefix("=") {
                        let (a, b) = FamilyParameterKind.splitFamilyType(res.text[String(n.dropFirst()).lowercased()] ?? "")
                        fam = a.isEmpty ? nil : a
                        if let b = b { ftype = b }
                    }
                    guard let n = fam, let sub = doc.family(named: n), sub.name.caseInsensitiveCompare(def.name) != .orderedSame else {
                        r.errors.append("\(def.name): nested family \(fam ?? f.family ?? "?") not found"); continue
                    }
                    var ov: [String: String] = [:]
                    for (pk, ex) in f.dims where pk != "type" { if let x = FamilyExpr.evaluate(ex, v) { ov[pk] = fmt(x, 9) } else { ov[pk] = ex } }
                    var sr = Result()
                    build(sub, doc: doc, overrides: ov, type: ftype, placement: pl, depth: depth + 1, into: &sr)
                    for (m, a) in sr.parts { var t = solids[m] ?? MeshAcc(); append(&t, a); solids[m] = t }
                    r.outlines += sr.outlines; r.symbols += sr.symbols; r.errors += sr.errors
                    continue
                }
                var acc = MeshAcc()
                var outline: [Vec2] = []
                switch f.kind {
                case .box:
                    let w = e(f.dims["width"], 100), d = e(f.dims["depth"], 100), h = e(f.dims["height"], 100)
                    guard w > 1e-9, d > 1e-9, abs(h) > 1e-9 else { continue }
                    outline = [Vec2(0, 0), Vec2(w, 0), Vec2(w, d), Vec2(0, d)]
                    acc.prism(outline, z0: min(0, h), z1: max(0, h))
                case .cylinder:
                    let rad = e(f.dims["radius"], 50), h = e(f.dims["height"], 100)
                    guard rad > 1e-9, abs(h) > 1e-9 else { continue }
                    outline = RG.circle(.zero, rad, segments: 24)
                    acc.prism(outline, z0: min(0, h), z1: max(0, h), smooth: true)
                case .extrusion:
                    let h = e(f.dims["height"], 100)
                    guard abs(h) > 1e-9, let p = profile(f.profile, def, values: v, doc: doc, w: e(f.dims["width"], 100), h: e(f.dims["depth"], 100)) else {
                        r.errors.append("\(def.name).\(f.name): no profile"); continue
                    }
                    outline = p
                    acc.prism(p, z0: min(0, h), z1: max(0, h))
                case .sweep:
                    let path = f.path.compactMap { q -> Vec3? in
                        guard q.count >= 2, let x = FamilyExpr.evaluate(q[0], v), let y = FamilyExpr.evaluate(q[1], v) else { return nil }
                        return Vec3(x, y, q.count > 2 ? (FamilyExpr.evaluate(q[2], v) ?? 0) : 0)
                    }
                    let pw = e(f.dims["width"], 50), ph = e(f.dims["height"], 50)
                    guard path.count >= 2, var p = profile(f.profile, def, values: v, doc: doc, w: pw, h: ph) else {
                        r.errors.append("\(def.name).\(f.name): sweep needs a profile and a path"); continue
                    }
                    let c = f.dims["anchor"] == "corner" ? Vec2.zero : GeometryOps.centroid(p)
                    p = p.map { $0 - c }
                    SweepMesh.sweep(p, along: path, into: &acc)
                    let half = (p.map { abs($0.x) }.max() ?? 0)
                    let flat = path.map(\.xy)
                    if half > 1e-9, flat.count >= 2 {
                        let l = PlanRepresentation.offsetPolyline(flat, half), rr = PlanRepresentation.offsetPolyline(flat, -half)
                        outline = l + rr.reversed()
                    }
                case .revolve:
                    let ang = e(f.dims["angle"], 360) * .pi / 180
                    guard let p = profile(f.profile, def, values: v, doc: doc, w: e(f.dims["width"], 100), h: e(f.dims["height"], 100)) else {
                        r.errors.append("\(def.name).\(f.name): no profile"); continue
                    }
                    var s = SolidGeom(kind: .revolve, origin: .zero, profile: p, height: ang)
                    s.rotation = 0
                    // SolidGeom revolve: profile x = radius, y = height along Y; map to Z-up by swapping axes afterwards.
                    var tmp = MeshAcc()
                    MeshBuilder.solid(s, into: &tmp)
                    for i in tmp.mesh.positions.indices { let q = tmp.mesh.positions[i]; tmp.mesh.positions[i] = Vec3(q.x, -q.z, q.y) }
                    for i in tmp.mesh.normals.indices { let q = tmp.mesh.normals[i]; tmp.mesh.normals[i] = Vec3(q.x, -q.z, q.y) }
                    tmp.edges = tmp.edges.map { $0.map { Vec3($0.x, -$0.z, $0.y) } }
                    acc = tmp
                    let rmax = p.map { abs($0.x) }.max() ?? 0
                    if rmax > 1e-9 { outline = RG.circle(.zero, rmax, segments: 24) }
                case .blend:
                    let h = e(f.dims["height"], 100)
                    let w1 = e(f.dims["width"], 100), d1 = e(f.dims["depth"], 100)
                    guard abs(h) > 1e-9, let p1 = profile(f.profile, def, values: v, doc: doc, w: w1, h: d1),
                          let p2 = profile(f.profile2 ?? f.profile, def, values: v, doc: doc, w: e(f.dims["width2"], w1), h: e(f.dims["depth2"], d1)) else {
                        r.errors.append("\(def.name).\(f.name): blend needs a base and a top profile"); continue
                    }
                    FamilyEngine.blend(p1, p2, height: h, into: &acc)
                    outline = abs(GeometryOps.signedArea(p1)) >= abs(GeometryOps.signedArea(p2)) ? p1 : p2
                case .sweptBlend:
                    let path = f.path.compactMap { q -> Vec3? in
                        guard q.count >= 2, let x = FamilyExpr.evaluate(q[0], v), let y = FamilyExpr.evaluate(q[1], v) else { return nil }
                        return Vec3(x, y, q.count > 2 ? (FamilyExpr.evaluate(q[2], v) ?? 0) : 0)
                    }
                    let pw = e(f.dims["width"], 50), ph = e(f.dims["height"], 50)
                    guard path.count >= 2, let p1 = profile(f.profile, def, values: v, doc: doc, w: pw, h: ph),
                          let p2 = profile(f.profile2 ?? f.profile, def, values: v, doc: doc, w: e(f.dims["width2"], pw), h: e(f.dims["height2"], ph)) else {
                        r.errors.append("\(def.name).\(f.name): swept blend needs two profiles and a path"); continue
                    }
                    let corner = f.dims["anchor"] == "corner"
                    let a = corner ? p1 : p1.map { $0 - GeometryOps.centroid(p1) }, b = corner ? p2 : p2.map { $0 - GeometryOps.centroid(p2) }
                    FamilyEngine.sweptBlend(a, b, along: path, into: &acc)
                    let half = max(a.map { abs($0.x) }.max() ?? 0, b.map { abs($0.x) }.max() ?? 0)
                    let flat = path.map(\.xy)
                    if half > 1e-9, flat.count >= 2 {
                        let l = PlanRepresentation.offsetPolyline(flat, half), rr = PlanRepresentation.offsetPolyline(flat, -half)
                        outline = l + rr.reversed()
                    }
                case .nested: continue
                }
                let placed = transformed(acc, pl)
                if f.void {
                    // A void cuts the solid forms defined before it (form order is feature order).
                    let vt = MeshTools.triangles(placed.mesh)
                    for (m, a) in solids where !a.mesh.isEmpty { solids[m] = fromTriangles(CSG.apply(.subtract, MeshTools.triangles(a.mesh), vt)) }
                    append(&voids, placed)
                } else {
                    if f.inModel { var t = solids[mat] ?? MeshAcc(); append(&t, placed); solids[mat] = t }
                    if f.inPlan, outline.count >= 3 { r.outlines.append(outline.map { pl.apply(Vec3($0.x, $0.y, 0)).xy }) }
                }
            }
        }
        for (m, a) in solids { var t = r.parts[m] ?? MeshAcc(); append(&t, a); r.parts[m] = t }
    }

    /// Ring vertex count for morphing two profiles.
    static func blendCount(_ a: [Vec2], _ b: [Vec2]) -> Int { min(256, max(24, max(a.count, b.count) * 4)) }

    /// Blend (PAR-004): lofts profile `a` at z = 0 to profile `b` at z = `height` (both resampled to equal counts).
    static func blend(_ a: [Vec2], _ b: [Vec2], height: Double, into acc: inout MeshAcc) {
        let n = blendCount(a, b)
        let ra = SweepMesh.resample(a, count: n), rb = SweepMesh.resample(b, count: n)
        guard ra.count == n, rb.count == n else { return }
        var rings = [ra.map { Vec3($0.x, $0.y, 0) }, rb.map { Vec3($0.x, $0.y, height) }]
        if height < 0 { rings = rings.map { $0.reversed() } }
        SweepMesh.loft(rings, into: &acc)
    }

    /// Swept blend (PAR-004): sweeps along `path`, morphing from `a` to `b` by arc length.
    static func sweptBlend(_ a: [Vec2], _ b: [Vec2], along path0: [Vec3], into acc: inout MeshAcc) {
        var path: [Vec3] = []
        for p in path0 where !(path.last.map { $0.distance(to: p) < 1e-9 } ?? false) { path.append(p) }
        guard path.count >= 2 else { return }
        let n = blendCount(a, b)
        let ra = SweepMesh.resample(a, count: n), rb = SweepMesh.resample(b, count: n)
        guard ra.count == n, rb.count == n else { return }
        var cum: [Double] = [0]
        for i in 1..<path.count { cum.append(cum[i - 1] + path[i - 1].distance(to: path[i])) }
        let total = max(cum.last!, 1e-12)
        let fr = SweepMesh.frames(path)
        let rings: [[Vec3]] = fr.enumerated().map { i, f in
            let t = cum[i] / total
            return (0..<n).map { k in let q = ra[k].lerp(rb[k], t); return f.o + f.x * q.x + f.y * q.y }
        }
        SweepMesh.loft(rings, into: &acc)
    }

    static func append(_ a: inout MeshAcc, _ b: MeshAcc) { a.mesh.append(b.mesh); a.edges += b.edges }

    static func transformed(_ acc: MeshAcc, _ pl: FamilyPlacement) -> MeshAcc {
        var o = acc
        o.mesh.positions = acc.mesh.positions.map(pl.apply)
        o.mesh.normals = acc.mesh.normals.map(pl.applyVector)
        o.edges = acc.edges.map { $0.map(pl.apply) }
        return o
    }

    static func fromTriangles(_ tris: [(Vec3, Vec3, Vec3)]) -> MeshAcc {
        var acc = MeshAcc()
        for t in tris {
            let n = (t.1 - t.0).cross(t.2 - t.0).normalized
            acc.tri(t.0, t.1, t.2, n, n, n)
        }
        let s = MeshTools.solid(from: tris, tolerance: 1e-6)
        if s.meshTriangles.count <= 60_000 { acc.edges = MeshTools.featureEdges(vertices: s.meshVertices, triangles: s.meshTriangles, angle: 25) }
        return acc
    }

    /// Evaluates a family at a placement.
    public static func evaluate(_ def: FamilyDefinition, doc: ArchiDocument, props: [String: String] = [:], extra: [String: Double] = [:],
                                origin: Vec3 = .zero, rotation: Double = 0) -> Result {
        var r = Result()
        build(def, doc: doc, overrides: overrides(props), type: props["familyType"], extra: extra,
              placement: FamilyPlacement(origin: origin, angle: rotation), into: &r)
        return r
    }

    /// Mesh groups of a family instance (component element whose `family` names a document family).
    static func meshGroups(_ def: FamilyDefinition, el: BIMElement, g: ComponentGeom, doc: ArchiDocument, z0: Double) -> [MeshGroup] {
        let r = evaluate(def, doc: doc, props: el.props, origin: Vec3(g.position.x, g.position.y, z0), rotation: g.rotation)
        return r.parts.sorted { $0.key < $1.key }.compactMap { $0.value.group(el.id, "component", $0.key) }
    }

    /// Plan outlines of a family instance.
    static func planOutlines(_ def: FamilyDefinition, el: BIMElement, g: ComponentGeom, doc: ArchiDocument) -> [[Vec2]] {
        evaluate(def, doc: doc, props: el.props, origin: Vec3(g.position.x, g.position.y, 0), rotation: g.rotation).outlines
    }

    /// Family geometry hosted in a door/window opening (props["family"]): origin at the opening centre on the wall
    /// centreline at sill level, X along the wall, Y across it; Width/Height/WallThickness come from the host.
    static func openingGroups(_ def: FamilyDefinition, el: BIMElement, o: OpeningGeom, f: WallFrame, zBase: Double, doc: ArchiDocument) -> [MeshGroup] {
        let c = f.pos(o.offset), t = f.tangent(o.offset)
        let extra: [String: Double] = ["width": o.width, "height": o.height, "sill": o.sill, "wallthickness": 2 * f.h, "framewidth": o.frameWidth]
        var ov = overrides(el.props)
        for k in ["width", "height"] where ov.keys.contains(where: { $0.lowercased() == k }) { ov = ov.filter { $0.key.lowercased() != k } }
        var r = Result()
        let flip = o.flipFacing ? Double.pi : 0
        // Host-driven values replace the family's own Width/Height defaults.
        var d2 = def
        for i in d2.parameters.indices { let k = d2.parameters[i].name.lowercased(); if let x = extra[k], d2.parameters[i].formula == nil { d2.parameters[i].value = fmt(x, 9) } }
        build(d2, doc: doc, overrides: ov, type: el.props["familyType"], extra: extra.filter { k, _ in def.parameter(k) == nil },
              placement: FamilyPlacement(origin: Vec3(c.x, c.y, zBase + o.sill), angle: t.angle + flip), into: &r)
        return r.parts.sorted { $0.key < $1.key }.compactMap { $0.value.group(el.id, o.kind.rawValue, $0.key) }
    }
}

/// Keeps family instances in step with their definitions: the instance size follows the evaluated geometry.
public enum FamilyInstances {
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard !doc.families.isEmpty else { return false }
        var changed = false
        let snap = doc
        for (i, el) in snap.elements.enumerated() {
            guard case .component(var g) = el.geometry, g.block == nil, g.path == nil, let def = snap.family(named: g.family) else { continue }
            let r = FamilyEngine.evaluate(def, doc: snap, props: el.props)
            let b = r.bounds
            guard !b.isEmpty else { continue }
            let size = Vec3(b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z)
            if !(abs(size.x - g.size.x) < 1e-6 && abs(size.y - g.size.y) < 1e-6 && abs(size.z - g.size.z) < 1e-6) {
                g.size = size; doc.elements[i].geometry = .component(g); changed = true
            }
            if doc.elements[i].props["familyErrors"] != (r.errors.isEmpty ? nil : r.errors.joined(separator: "; ")) {
                doc.elements[i].props["familyErrors"] = r.errors.isEmpty ? nil : r.errors.joined(separator: "; "); changed = true
            }
        }
        return changed
    }

    /// Number of instances of a family (components and openings).
    public static func count(_ name: String, doc: ArchiDocument) -> Int {
        doc.elements.filter { el in
            if case .component(let g) = el.geometry, g.family?.caseInsensitiveCompare(name) == .orderedSame { return true }
            return el.props["family"]?.caseInsensitiveCompare(name) == .orderedSame
        }.count
    }
}
