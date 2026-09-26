// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM import (IO-044): the parsed model becomes drawing objects in the target units. Meshes, B-reps, extrusions
// and surfaces become mesh solids (B-rep faces use Rhino's cached render meshes when the file has them, otherwise each
// trimmed face is tessellated here: its trim loops are sampled in the surface's parameter plane — scaled to the
// surface's true lengths — triangulated with a constrained Delaunay triangulation with interior points on curved
// surfaces, and mapped onto the surface). Planar curves parallel to the XY plane stay exact (lines, arcs, circles,
// polylines, NURBS splines at an elevation); other curves become 3D polylines. Blocks are exploded with their
// (nested) transforms. Layers keep names (full "Parent::Child" paths), colours, visibility and locking; object colours
// and render materials (V4/V5 material table) are kept.
import Foundation

public enum Rhino3DM {
    public struct ImportResult {
        public var entities: [Entity]
        public var layers: [Layer]
        public var materials: [Material]
        /// Millimetres per unit of the file.
        public var fileUnitMM: Double
        public var version: Int
        public var summary: String
    }

    public struct ImportOptions {
        /// Use the render meshes Rhino caches in B-reps (faster, matches Rhino's display); false tessellates every face.
        public var useRenderMeshes = true
        public var maxPoints = 200_000
        public init(useRenderMeshes: Bool = true, maxPoints: Int = 200_000) { self.useRenderMeshes = useRenderMeshes; self.maxPoints = maxPoints }
    }

    /// Reads a 3DM file into entities, in drawing units of `unitMM` millimetres.
    public static func read(_ data: Data, unitMM: Double = 1, options: ImportOptions = ImportOptions()) throws -> ImportResult {
        let m = try Rhino3DMParser.read(data)
        let k = m.unitMM / max(unitMM, 1e-12)
        var conv = R3Converter(model: m, scale: k, options: options)
        conv.run()
        var parts = ["3DM version \(m.version >= 50 ? m.version / 10 : m.version)", "\(conv.entities.count) objects"]
        if conv.brepFaces > 0 { parts.append("\(conv.brepFaces) B-rep faces (\(conv.tessellatedFaces) tessellated)") }
        if conv.instances > 0 { parts.append("\(conv.instances) block instances exploded") }
        let skipped = conv.skipped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        if !skipped.isEmpty { parts.append("skipped " + skipped.joined(separator: ", ")) }
        return ImportResult(entities: conv.entities, layers: conv.layers, materials: conv.materials, fileUnitMM: m.unitMM, version: m.version,
                            summary: parts.joined(separator: ", "))
    }

    /// A stand-alone document (in `reference`'s units) with the imported layers, materials and objects.
    public static func document(_ data: Data, reference: ArchiDocument = ArchiDocument(), options: ImportOptions = ImportOptions()) throws -> (ArchiDocument, String) {
        let r = try read(data, unitMM: reference.units.mm, options: options)
        var d = ArchiDocument()
        d.entities = []; d.elements = []
        d.units = reference.units
        d.levels = reference.levels
        for l in r.layers where d.layer(named: l.name) == nil { d.layers.append(l) }
        for mt in r.materials where d.material(mt.name) == nil { d.materials.append(mt) }
        for e in r.entities {
            if d.layer(named: e.layer) == nil { d.ensureLayer(e.layer) }
            d.add(e)
        }
        return (d, r.summary)
    }
}

struct R3Converter {
    let model: R3Model
    let scale: Double
    let options: Rhino3DM.ImportOptions
    var entities: [Entity] = []
    var layers: [Layer] = []
    var materials: [Material] = []
    var skipped: [String: Int] = [:]
    var brepFaces = 0, tessellatedFaces = 0, instances = 0
    var layerNames: [Int: String] = [:]
    var materialNames: [Int: String] = [:]
    var objectsByID: [String: R3Object] = [:]
    var idefsByID: [String: R3InstanceDefinition] = [:]

    init(model: R3Model, scale: Double, options: Rhino3DM.ImportOptions) {
        self.model = model; self.scale = scale; self.options = options
    }

    static func rgba(_ c: (UInt8, UInt8, UInt8)) -> RGBA { RGBA(Double(c.0) / 255, Double(c.1) / 255, Double(c.2) / 255) }

    mutating func buildTables() {
        // Layers: full path names through the parent ids.
        var byID: [String: R3Layer] = [:]
        for l in model.layers where !l.id.isEmpty { byID[l.id] = l }
        func path(_ l: R3Layer, depth: Int = 0) -> String {
            let nil16 = "00000000-0000-0000-0000-000000000000"
            let own = l.name.isEmpty ? "Layer \(l.index)" : l.name
            guard depth < 16, !l.parent.isEmpty, l.parent != nil16, let p = byID[l.parent] else { return own }
            return path(p, depth: depth + 1) + "::" + own
        }
        var used = Set<String>()
        for (i, l) in model.layers.enumerated() {
            var name = path(l)
            if used.contains(name.lowercased()) { name += " (\(i))" }
            used.insert(name.lowercased())
            if layerNames[l.index] == nil { layerNames[l.index] = name }
            if layerNames[i] == nil && l.index < 0 { layerNames[i] = name }
            var ly = Layer(name: name, color: Self.rgba(l.color))
            ly.visible = l.visible
            ly.locked = l.locked
            layers.append(ly)
        }
        for (i, mt) in model.materials.enumerated() {
            var name = mt.name.isEmpty ? "3DM material \(i + 1)" : mt.name
            if materials.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { name += " (\(i + 1))" }
            var mat = Material(name: name, color: Self.rgba(mt.diffuse), roughness: max(0.05, 1 - min(1, mt.shine / 255)), transparency: mt.transparency)
            if mt.transparency > 0.5 { mat.cutPattern = "SOLID" }
            materials.append(mat)
            materialNames[i] = name
        }
        for o in model.objects where !o.attributes.uuid.isEmpty { objectsByID[o.attributes.uuid] = o }
        for d in model.idefs where !d.id.isEmpty { idefsByID[d.id] = d }
    }

    mutating func run() {
        buildTables()
        let members = Set(model.idefs.flatMap { $0.members })
        let scaleX = R3Xform(m: [scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1])
        for o in model.objects where o.attributes.mode != 3 && !members.contains(o.attributes.uuid) {
            emit(o, xform: scaleX, parentAttrs: nil, depth: 0)
        }
    }

    func layerName(_ a: R3Attributes, parent: R3Attributes?) -> String {
        layerNames[a.layer] ?? parent.flatMap { layerNames[$0.layer] } ?? layers.first?.name ?? "0"
    }

    mutating func emit(_ o: R3Object, xform: R3Xform, parentAttrs: R3Attributes?, depth: Int) {
        let a = o.attributes
        var props: [String: String] = [:]
        if !a.name.isEmpty { props["name"] = a.name }
        else if let p = parentAttrs, !p.name.isEmpty { props["name"] = p.name }
        if !a.uuid.isEmpty { props["rhinoId"] = a.uuid }
        let matIndex = a.materialSource == 1 ? a.material : (parentAttrs?.materialSource == 1 ? parentAttrs!.material : -1)
        if let mn = materialNames[matIndex] { props["material"] = mn }
        var color: ColorRef = .byLayer
        if let c = a.color { color = .rgb(c.0, c.1, c.2) }
        else if a.colorSource == 3, let c = parentAttrs?.color { color = .rgb(c.0, c.1, c.2) }
        else if a.colorSource == 2, matIndex >= 0, matIndex < model.materials.count {
            let c = model.materials[matIndex].diffuse; color = .rgb(c.0, c.1, c.2)
        }
        let layer = layerName(a, parent: parentAttrs)
        func add(_ g: Geometry, _ extra: [String: String] = [:]) {
            var e = Entity(layer: layer, color: color, geometry: g, props: props.merging(extra) { _, b in b })
            if !a.visible { e.props["hidden"] = "1" }
            entities.append(e)
        }
        func addMesh(_ m: R3Mesh, kind: String) {
            var mm = m
            mm.transform(xform)
            guard !mm.triangles.isEmpty else { skipped["empty " + kind, default: 0] += 1; return }
            let w = Self.weld(mm)
            add(.solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: w.vertices, meshTriangles: w.triangles)), ["rhinoType": kind])
        }
        switch o.geometry {
        case .mesh(let m): addMesh(m, kind: "mesh")
        case .brep(let b):
            var out = R3Mesh()
            for (fi, f) in b.faces.enumerated() {
                brepFaces += 1
                if options.useRenderMeshes, fi < b.renderMeshes.count, let rm = b.renderMeshes[fi], !rm.triangles.isEmpty { out.append(rm); continue }
                if let t = R3Tessellator.face(b, f) { out.append(t); tessellatedFaces += 1 } else { skipped["B-rep faces", default: 0] += 1 }
            }
            addMesh(out, kind: "brep")
        case .extrusion(let x): addMesh(R3Tessellator.extrusion(x), kind: "extrusion")
        case .surface(let s): addMesh(R3Tessellator.untrimmed(s), kind: "surface")
        case .curve(let c): for g in curveGeometry(c, xform) { add(g.0, g.1) }
        case .point(let p):
            let q = xform.apply(p)
            add(.point(q.xy), abs(q.z) > 1e-9 ? ["z": fmt(q.z, 6)] : [:])
        case .pointCloud(let pts):
            let cloud = pts.map { CloudPoint(xform.apply($0)) }
            var opt = PointCloudOptions(scale: 1, maxPoints: options.maxPoints)
            opt.layer = layer
            for var e in PointCloud.entities(cloud, options: opt) { e.props.merge(props) { a, _ in a }; entities.append(e) }
        case .instance(let id, let x):
            guard depth < 8, let d = idefsByID[id] else { skipped["block instances without definition", default: 0] += 1; return }
            instances += 1
            let xf = xform * x
            let inherited = R3Attributes(uuid: "", layer: a.layer, material: a.material, color: color == .byLayer ? nil : a.color,
                                         colorSource: a.colorSource, materialSource: a.materialSource,
                                         name: a.name.isEmpty ? d.name : a.name, visible: a.visible, mode: 0)
            for mid in d.members { if let mo = objectsByID[mid] { emit(mo, xform: xf, parentAttrs: inherited, depth: depth + 1) } }
        case .unsupported(let what): skipped[what, default: 0] += 1
        }
    }

    /// Merges coincident vertices (exact after float round-trip) and drops degenerate triangles.
    static func weld(_ m: R3Mesh) -> R3Mesh {
        var map: [Vec3: Int] = [:]
        var out = R3Mesh()
        var remap = [Int](repeating: 0, count: m.vertices.count)
        for (i, v) in m.vertices.enumerated() {
            if let j = map[v] { remap[i] = j } else { map[v] = out.vertices.count; remap[i] = out.vertices.count; out.vertices.append(v) }
        }
        var i = 0
        while i + 2 < m.triangles.count {
            let a = remap[m.triangles[i]], b = remap[m.triangles[i + 1]], c = remap[m.triangles[i + 2]]
            if a != b && b != c && a != c { out.triangles += [a, b, c] }
            i += 3
        }
        return out
    }

    /// Affine map restricted to the XY plane (rotation / uniform scale / mirror) with a z shift, when `x` keeps planes parallel to XY.
    struct PlanarMap { var s: Double; var rot: Double; var mirror: Bool; var zScale: Double; var x: R3Xform }
    func planar(_ x: R3Xform) -> PlanarMap? {
        let m = x.m
        guard abs(m[2]) < 1e-12, abs(m[6]) < 1e-12, abs(m[8]) < 1e-12, abs(m[9]) < 1e-12, abs(m[12]) < 1e-12, abs(m[13]) < 1e-12, abs(m[14]) < 1e-12, abs(m[15] - 1) < 1e-12 else { return nil }
        let a = m[0], b = m[1], c = m[4], d = m[5]
        let det = a * d - b * c
        let s = (abs(det)).squareRoot()
        guard s > 1e-12, abs(a * a + c * c - s * s) < 1e-9 * max(1, s * s), abs(a * b + c * d) < 1e-9 * max(1, s * s) else { return nil }
        return PlanarMap(s: s, rot: atan2(c, a), mirror: det < 0, zScale: m[10], x: x)
    }

    /// Drawing geometry of a curve: exact when planar and parallel to XY, else a 3D polyline.
    func curveGeometry(_ c: R3Curve, _ x: R3Xform) -> [(Geometry, [String: String])] {
        func elev(_ z: Double) -> [String: String] { abs(z) > 1e-9 ? ["elevation": fmt(z, 6)] : [:] }
        func poly3(_ pts: [Vec3]) -> [(Geometry, [String: String])] {
            var p = pts.map(x.apply)
            guard p.count >= 2 else { return [] }
            var closed = false
            if p.count > 2, (p[0] - p[p.count - 1]).length < 1e-9 * max(1, scale) { closed = true; p.removeLast() }
            let z0 = p[0].z
            let flat = p.allSatisfy { abs($0.z - z0) < 1e-9 * max(1, abs(z0)) }
            let g = Geometry.polyline(PolylineGeom(points: p.map(\.xy), closed: closed))
            if flat { return [(g, elev(z0))] }
            return [(g, ["vertexZ": p.map { fmt($0.z, 6) }.joined(separator: ",")])]
        }
        guard let pm = planar(x) else { return poly3(c.sample()) }
        switch c {
        case .line(let a, let b, _, _):
            let p = x.apply(a), q = x.apply(b)
            guard abs(p.z - q.z) < 1e-9 * max(1, abs(p.z)) else { return poly3([a, b]) }
            return [(.line(LineGeom(p.xy, q.xy)), elev(p.z))]
        case .arc(let o, let ax, let ay, let r, let ang, _):
            let n = ax.cross(ay)
            guard abs(abs(n.z) - 1) < 1e-9 else { return poly3(c.sample()) }
            let cc = x.apply(o)
            let rr = r * pm.s
            let sweep = ang.1 - ang.0
            // Angle of the plane's x axis in the drawing, direction of increasing angle (+1 CCW).
            var ccw = n.z > 0
            if pm.mirror { ccw.toggle() }
            let xd = x.apply(o + ax) - cc
            let th = atan2(xd.y, xd.x)
            if abs(sweep) >= 2 * Double.pi - 1e-9 { return [(.circle(CircleGeom(cc.xy, rr)), elev(cc.z))] }
            let s0 = ccw ? th + ang.0 : th - ang.1
            let s1 = ccw ? th + ang.1 : th - ang.0
            return [(.arc(ArcGeom(cc.xy, rr, normAngle(s0), normAngle(s1))), elev(cc.z))]
        case .polyline(let pts, _): return poly3(pts)
        case .nurbs(let b):
            let cps = b.points.map(x.apply)
            let z0 = cps.first?.z ?? 0
            guard b.degree >= 2, cps.allSatisfy({ abs($0.z - z0) < 1e-9 * max(1, abs(z0)) }) else { return poly3(c.sample()) }
            let closed = cps.count > 2 && (cps[0] - cps[cps.count - 1]).length < 1e-9 * max(1, scale)
            return [(.spline(SplineGeom(degree: b.degree, controlPoints: cps.map(\.xy), knots: b.knots, weights: b.weights, closed: closed)), elev(z0))]
        case .poly: return poly3(c.sample())
        }
    }
}

/// Tessellation of trimmed B-rep faces, untrimmed surfaces and extrusions.
enum R3Tessellator {
    /// Trim loops of a face in the surface's parameter plane.
    static func loops(_ b: R3Brep, _ f: R3Brep.Face) -> [[Vec2]] {
        var out: [[Vec2]] = []
        for li in f.loops where li >= 0 && li < b.loops.count {
            let l = b.loops[li]
            guard l.type == 1 || l.type == 2 || l.type == 0 else { continue }
            var pts: [Vec2] = []
            for ti in l.trims where ti >= 0 && ti < b.trims.count {
                let t = b.trims[ti]
                guard t.c2 >= 0, t.c2 < b.c2.count, let c = b.c2[t.c2] else { continue }
                for q in c.sample(t.d.0, t.d.1, maxSegments: 128).map(\.xy) {
                    if let last = pts.last, (last - q).length < 1e-12 { continue }
                    pts.append(q)
                }
            }
            if pts.count > 2, (pts[0] - pts[pts.count - 1]).length < 1e-12 { pts.removeLast() }
            if pts.count >= 3 { out.append(pts) }
        }
        return out
    }

    static func face(_ b: R3Brep, _ f: R3Brep.Face) -> R3Mesh? {
        guard f.surface >= 0, f.surface < b.surfaces.count, let s = b.surfaces[f.surface] else { return nil }
        let ls = loops(b, f)
        guard !ls.isEmpty else { return nil }
        let m = tessellate(s, loops: ls, reversed: f.reversed)
        return m.triangles.isEmpty ? nil : m
    }

    static func untrimmed(_ s: R3Surface) -> R3Mesh {
        let (du, dv) = s.domain
        return tessellate(s, loops: [[Vec2(du.0, dv.0), Vec2(du.1, dv.0), Vec2(du.1, dv.1), Vec2(du.0, dv.1)]], reversed: false)
    }

    /// Cells needed along each parameter direction over [lo, hi]: the turning of iso-curves (sampled at three
    /// positions across) divided by π/16, so a chord never cuts more than about 11° of arc. Planes need none.
    static func cells(_ s: R3Surface, _ lo: Vec2, _ hi: Vec2) -> (Int, Int) {
        if case .plane = s { return (1, 1) }
        func turning(_ alongU: Bool, _ c: Double) -> Double {
            var pts: [Vec3] = []
            for i in 0...32 {
                let t = Double(i) / 32
                pts.append(alongU ? s.eval(lo.x + (hi.x - lo.x) * t, c) : s.eval(c, lo.y + (hi.y - lo.y) * t))
            }
            var total = 0.0
            for i in 1..<32 {
                let a = pts[i] - pts[i - 1], b = pts[i + 1] - pts[i]
                let la = a.length, lb = b.length
                guard la > 1e-15, lb > 1e-15 else { continue }
                total += acos(max(-1, min(1, a.dot(b) / (la * lb))))
            }
            return total
        }
        let tu = [lo.y, (lo.y + hi.y) / 2, hi.y].map { turning(true, $0) }.max() ?? 0
        let tv = [lo.x, (lo.x + hi.x) / 2, hi.x].map { turning(false, $0) }.max() ?? 0
        func n(_ t: Double) -> Int { max(1, min(64, Int((t / (Double.pi / 16)).rounded(.up)))) }
        return (n(tu), n(tv))
    }

    /// Triangulates the region inside `loops` (parameter plane) and maps it onto the surface. The parameters are
    /// normalised so each grid cell is a unit square — one cell per ~11° of turning in each direction — and the
    /// constrained Delaunay triangulation gets the cell centres inside the loops (away from their edges) as interior
    /// points, with the loop edges split to cell length: no triangle then spans more than about a cell in a curved
    /// direction, so the chords stay on the surface.
    static func tessellate(_ s: R3Surface, loops: [[Vec2]], reversed: Bool) -> R3Mesh {
        var lo = Vec2(Double.infinity, Double.infinity), hi = Vec2(-Double.infinity, -Double.infinity)
        for l in loops { for q in l { lo = Vec2(min(lo.x, q.x), min(lo.y, q.y)); hi = Vec2(max(hi.x, q.x), max(hi.y, q.y)) } }
        guard hi.x > lo.x, hi.y > lo.y else { return R3Mesh() }
        let (cu, cv) = cells(s, lo, hi)
        let su = Double(cu) / (hi.x - lo.x), sv = Double(cv) / (hi.y - lo.y)
        var scaled = loops.map { $0.map { Vec2(($0.x - lo.x) * su, ($0.y - lo.y) * sv) } }
        var steiner: [Vec2] = []
        if cu > 1 || cv > 1 {
            // Loop edges no longer than a cell: a long straight parameter edge would be a chord cutting across the
            // curved surface, with slivers fanning from it to the interior points.
            scaled = scaled.map { l in
                var out: [Vec2] = []
                for i in 0..<l.count {
                    let a = l[i], b = l[(i + 1) % l.count]
                    out.append(a)
                    let n = min(512, Int((b - a).length.rounded(.up)))
                    if n > 1 { for k in 1..<n { out.append(a + (b - a) * (Double(k) / Double(n))) } }
                }
                return out
            }
            let minD = 0.45
            let segs: [(Vec2, Vec2)] = scaled.flatMap { l in (0..<l.count).map { (l[$0], l[($0 + 1) % l.count]) } }
            // Segment buckets per cell (segment box grown by minD).
            var buckets = [[Int]](repeating: [], count: cu * cv)
            for (k, sg) in segs.enumerated() {
                let x0 = Int((min(sg.0.x, sg.1.x) - minD).rounded(.down)), x1 = Int((max(sg.0.x, sg.1.x) + minD).rounded(.down))
                let y0 = Int((min(sg.0.y, sg.1.y) - minD).rounded(.down)), y1 = Int((max(sg.0.y, sg.1.y) + minD).rounded(.down))
                guard x1 >= 0, y1 >= 0, x0 < cu, y0 < cv else { continue }
                for i in max(0, x0)...min(cu - 1, x1) { for j in max(0, y0)...min(cv - 1, y1) { buckets[j * cu + i].append(k) } }
            }
            func dist(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
                let d = b - a, l2 = d.dot(d)
                let t = l2 > 0 ? max(0, min(1, (p - a).dot(d) / l2)) : 0
                return (a + d * t - p).length
            }
            for j in 0..<cv {
                // Row crossings for the even–odd inside test (centres jittered so none is collinear with loop vertices).
                let y = Double(j) + 0.5137
                var xs: [Double] = []
                for sg in segs where (sg.0.y > y) != (sg.1.y > y) {
                    xs.append(sg.0.x + (y - sg.0.y) / (sg.1.y - sg.0.y) * (sg.1.x - sg.0.x))
                }
                for i in 0..<cu {
                    let x = Double(i) + 0.5 + 0.0071 * Double((i * 7 + j * 3) % 5)
                    guard xs.reduce(0, { $0 + ($1 < x ? 1 : 0) }) % 2 == 1 else { continue }
                    let p = Vec2(x, y)
                    if buckets[j * cu + i].contains(where: { dist(p, segs[$0].0, segs[$0].1) < minD }) { continue }
                    steiner.append(p)
                }
            }
        }
        let (pts, tris) = StepCDT.triangulate(loops: scaled, steiner: steiner)
        var m = R3Mesh()
        var index: [Int: Int] = [:]
        for (a, b, c) in tris {
            var t = [a, b, c]
            if StepCDT.orient(pts[a], pts[b], pts[c]) < 0 { t = [a, c, b] }
            if reversed { t = [t[0], t[2], t[1]] }
            for i in t {
                if let j = index[i] { m.triangles.append(j); continue }
                let q = pts[i]
                index[i] = m.vertices.count
                m.triangles.append(m.vertices.count)
                m.vertices.append(s.eval(lo.x + q.x / su, lo.y + q.y / sv))
            }
        }
        return m
    }

    static func extrusion(_ x: R3Extrusion) -> R3Mesh {
        let a = x.from + (x.to - x.from) * x.t.0, b = x.from + (x.to - x.from) * x.t.1
        let z = (b - a).normalized
        guard z.length > 0 else { return R3Mesh() }
        var y = (x.up - z * x.up.dot(z)).normalized
        if y.length == 0 { y = abs(z.z) < 0.9 ? Vec3(0, 0, 1).cross(z).normalized : Vec3(0, 1, 0) }
        let xa = y.cross(z)
        let h = b - a
        func at(_ p: Vec2, _ top: Bool) -> Vec3 { a + xa * p.x + y * p.y + (top ? h : .zero) }
        var m = R3Mesh()
        var closedLoops: [[Vec2]] = []
        for c in x.profiles {
            var p = c.sample().map(\.xy)
            guard p.count >= 2 else { continue }
            let closed = p.count > 3 && (p[0] - p[p.count - 1]).length < 1e-9 * max(1, (p[0]).length)
            if closed { p.removeLast(); closedLoops.append(p) }
            let n = p.count
            let o = m.vertices.count
            for q in p { m.vertices.append(at(q, false)) }
            for q in p { m.vertices.append(at(q, true)) }
            for i in 0..<(closed ? n : n - 1) {
                let j = (i + 1) % n
                m.triangles += [o + i, o + j, o + n + j, o + i, o + n + j, o + n + i]
            }
        }
        if let outer = closedLoops.first, x.caps.0 || x.caps.1 {
            let (pts, tris) = Triangulator.triangulateWithPoints(outer, holes: Array(closedLoops.dropFirst()))
            for (top, on) in [(false, x.caps.0), (true, x.caps.1)] where on {
                let o = m.vertices.count
                for q in pts { m.vertices.append(at(q, top)) }
                for (i, j, k) in tris { m.triangles += top ? [o + i, o + j, o + k] : [o + i, o + k, o + j] }
            }
        }
        // Outward normals for closed solids (positive signed volume).
        var vol = 0.0
        var i = 0
        while i + 2 < m.triangles.count {
            let p = m.vertices[m.triangles[i]], q = m.vertices[m.triangles[i + 1]], r = m.vertices[m.triangles[i + 2]]
            vol += p.dot(q.cross(r))
            i += 3
        }
        if vol < 0 && !closedLoops.isEmpty {
            var j = 0
            while j + 2 < m.triangles.count { m.triangles.swapAt(j + 1, j + 2); j += 3 }
        }
        return m
    }
}
