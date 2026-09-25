// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Accumulates triangles and feature edges for one mesh group.
struct MeshAcc {
    var mesh = Mesh()
    var edges: [[Vec3]] = []

    static func up(_ p: Vec2, _ z: Double) -> Vec3 { Vec3(p.x, p.y, z) }

    /// Adds a triangle whose winding is corrected to match the average of the given vertex normals.
    mutating func tri(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ na: Vec3, _ nb: Vec3, _ nc: Vec3) {
        let fn = (b - a).cross(c - a)
        guard fn.length > 1e-14 else { return }
        let base = UInt32(mesh.positions.count)
        let flip = fn.dot(na + nb + nc) < 0
        mesh.positions += flip ? [a, c, b] : [a, b, c]
        mesh.normals += flip ? [na, nc, nb] : [na, nb, nc]
        let n = (na + nb + nc).normalized
        let (u, v) = Mesh.basis(n.length > 0 ? n : Vec3.unitZ)
        mesh.uvs += (flip ? [a, c, b] : [a, b, c]).map { Vec2($0.dot(u) / 1000, $0.dot(v) / 1000) }
        mesh.indices += [base, base + 1, base + 2]
    }

    /// Adds a planar polygon, oriented so its normal points to `outward` (if given).
    mutating func face(_ pts: [Vec3], outward: Vec3? = nil) {
        guard pts.count >= 3 else { return }
        var p = pts
        var n = Mesh.polygonNormal(p)
        guard n.length > 0.5 else { return }
        if let o = outward, n.dot(o) < 0 { p.reverse(); n = -n }
        mesh.addPolygon(p, normal: n)
    }

    /// Horizontal cap with holes at height z.
    mutating func cap(_ outer0: [Vec2], holes: [[Vec2]] = [], z: Double, up: Bool) {
        var outer = RG.dedupe(outer0, closed: true)
        guard outer.count >= 3, abs(GeometryOps.signedArea(outer)) > 1e-12 else { return }
        if GeometryOps.signedArea(outer) < 0 { outer.reverse() }
        let hs = holes.map { RG.dedupe($0, closed: true) }.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0)) > 1e-12 }
        let (pts, tris) = Triangulator.triangulateWithPoints(outer, holes: hs)
        let n = up ? Vec3.unitZ : -Vec3.unitZ
        let base = UInt32(mesh.positions.count)
        mesh.positions += pts.map { MeshAcc.up($0, z) }
        mesh.normals += Array(repeating: n, count: pts.count)
        mesh.uvs += pts.map { $0 / 1000 }
        for t in tris {
            // Triangles are CCW in plan; flip for downward caps.
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            let ccw = (b - a).cross(c - a) >= 0
            let (i0, i1, i2) = (base + UInt32(t.0), base + UInt32(t.1), base + UInt32(t.2))
            mesh.indices += (ccw == up) ? [i0, i1, i2] : [i0, i2, i1]
        }
    }

    /// Vertical extrusion of a plan polygon with holes between z0 and z1.
    mutating func prism(_ loop: [Vec2], holes: [[Vec2]] = [], z0: Double, z1: Double, smooth: Bool = false, featureEdges: Bool = true) {
        var outer = RG.dedupe(loop, closed: true)
        guard outer.count >= 3, abs(GeometryOps.signedArea(outer)) > 1e-12, z1 - z0 > 1e-9 else { return }
        if GeometryOps.signedArea(outer) < 0 { outer.reverse() }
        var hs = holes.map { RG.dedupe($0, closed: true) }.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0)) > 1e-12 }
        hs = hs.map { GeometryOps.signedArea($0) > 0 ? Array($0.reversed()) : $0 }
        cap(outer, holes: hs, z: z0, up: false)
        cap(outer, holes: hs, z: z1, up: true)
        for l in [outer] + hs { sides(l, z0: z0, z1: z1, smooth: smooth, featureEdges: featureEdges) }
    }

    /// Side walls of a closed loop (outward = right of the edge direction for CCW outer / CW holes).
    mutating func sides(_ l: [Vec2], z0: Double, z1: Double, smooth: Bool, featureEdges: Bool) {
        let n = l.count
        guard n >= 2 else { return }
        let en: [Vec3] = (0..<n).map { i in let d = (l[(i + 1) % n] - l[i]).normalized; return Vec3(d.y, -d.x, 0) }
        let cosSharp = cos(rad(40))
        for i in 0..<n {
            let a = l[i], b = l[(i + 1) % n]
            guard a.distance(to: b) > 1e-12 else { continue }
            var na = en[i], nb = en[i]
            if smooth {
                let prev = en[(i - 1 + n) % n], next = en[(i + 1) % n]
                if prev.dot(en[i]) > cosSharp { na = (prev + en[i]).normalized }
                if next.dot(en[i]) > cosSharp { nb = (next + en[i]).normalized }
            }
            let a0 = MeshAcc.up(a, z0), b0 = MeshAcc.up(b, z0), b1 = MeshAcc.up(b, z1), a1 = MeshAcc.up(a, z1)
            tri(a0, b0, b1, na, nb, nb)
            tri(a0, b1, a1, na, nb, na)
        }
        guard featureEdges else { return }
        edges.append((l + [l[0]]).map { MeshAcc.up($0, z0) })
        edges.append((l + [l[0]]).map { MeshAcc.up($0, z1) })
        for i in 0..<n {
            let prev = en[(i - 1 + n) % n], cur = en[i]
            let sharp = smooth ? prev.dot(cur) <= cosSharp : prev.dot(cur) < 0.9998
            if sharp { edges.append([MeshAcc.up(l[i], z0), MeshAcc.up(l[i], z1)]) }
        }
    }

    /// Extrudes a profile given in a vertical plane: x along `ax`, z up, thickness from y0 to y1 along `ay`.
    mutating func verticalPlate(_ profile: [(x: Double, z: Double)], origin: Vec2, ax: Vec2, ay: Vec2, y0: Double, y1: Double) {
        guard profile.count >= 3 else { return }
        func P(_ x: Double, _ z: Double, _ y: Double) -> Vec3 { let q = origin + ax * x + ay * y; return Vec3(q.x, q.y, z) }
        let ay3 = Vec3(ay.x, ay.y, 0)
        let f0 = profile.map { P($0.x, $0.z, y0) }, f1 = profile.map { P($0.x, $0.z, y1) }
        face(f0, outward: -ay3); face(f1, outward: ay3)
        let c = (f0 + f1).reduce(Vec3.zero, +) / Double(f0.count * 2)
        let n = profile.count
        for i in 0..<n {
            let q = [f0[i], f0[(i + 1) % n], f1[(i + 1) % n], f1[i]]
            let m = q.reduce(Vec3.zero, +) / 4
            face(q, outward: m - c)
        }
        edges.append(f0 + [f0[0]]); edges.append(f1 + [f1[0]])
        for i in 0..<n { edges.append([f0[i], f1[i]]) }
    }

    func group(_ id: EntityID?, _ kind: String, _ material: String) -> MeshGroup? {
        mesh.isEmpty ? nil : MeshGroup(id: id, kind: kind, material: material, mesh: mesh, edges: edges)
    }
}

/// Builds 3D triangle meshes (Z up, drawing units) from BIM elements and 3D solids.
public enum MeshBuilder {
    public static func build(doc: ArchiDocument) -> [MeshGroup] {
        let ctx = BIMContext(doc: doc)
        var out: [MeshGroup] = []
        for el in doc.elements where doc.isVisible(layer: el.layer) { out += groups(el, ctx: ctx) }
        for e in doc.entities where doc.isVisible(layer: e.layer) { out += groups(for: e, doc: doc) }
        return out
    }

    public static func groups(for el: BIMElement, doc: ArchiDocument) -> [MeshGroup] {
        groups(el, ctx: PlanRepresentation.context(doc))
    }

    public static func groups(for e: Entity, doc: ArchiDocument) -> [MeshGroup] {
        entityGroups(e.geometry, id: e.id, layer: e.layer, props: e.props, doc: doc, depth: 0)
    }

    // MARK: Elements

    static func groups(_ el: BIMElement, ctx: BIMContext) -> [MeshGroup] {
        let doc = ctx.doc
        let u = 1 / doc.units.mm
        let elev = ctx.levelElevation(el.level)
        let kind = el.typeName
        switch el.geometry {
        case .wall(let g):
            guard let f = ctx.frames[el.id] ?? WallFrame(el) else { return [] }
            var acc = MeshAcc()
            let z0 = elev + g.baseOffset, z1 = z0 + g.height
            for pc in ctx.pieces(f) { acc.prism(pc.poly, z0: z0, z1: z1, smooth: f.isCurved) }
            for c in ctx.cuts(f) {
                let poly = f.face(-f.h, c.s0, c.s1) + f.face(f.h, c.s0, c.s1).reversed()
                var sill = Double.infinity, head = -Double.infinity
                for oe in c.els { if case .opening(let o) = oe.geometry { sill = min(sill, o.sill); head = max(head, o.sill + o.height) } }
                if !sill.isFinite { continue }
                if sill > 1e-9 { acc.prism(poly, z0: z0, z1: min(z0 + sill, z1), smooth: f.isCurved) }
                if head < g.height - 1e-9 { acc.prism(poly, z0: z0 + max(head, 0), z1: z1, smooth: f.isCurved) }
            }
            var mat = el.material ?? "Plaster"
            if let tn = g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), let p = wt.plies.first { mat = p.material }
            return [acc.group(el.id, kind, mat)].compactMap { $0 }

        case .opening(let o):
            guard o.kind != .opening, o.width > 0, o.height > 0,
                  let host = doc.element(o.hostWall), let f = ctx.frames[host.id] ?? WallFrame(host),
                  case .wall(let hg) = host.geometry else { return [] }
            let zb = ctx.levelElevation(host.level) + hg.baseOffset + o.sill, zt = zb + o.height
            let s0 = o.offset - o.width / 2, s1 = o.offset + o.width / 2
            let fw = min(max(o.frameWidth, 0), o.width / 4, o.height / 4)
            let a = s0 + fw, b = s1 - fw, h = f.h
            func box(_ acc: inout MeshAcc, _ sa: Double, _ sb: Double, _ ta: Double, _ tb: Double, _ za: Double, _ zb2: Double) {
                guard sb - sa > 1e-9, abs(tb - ta) > 1e-9, zb2 - za > 1e-9 else { return }
                acc.prism([f.pt(sa, ta), f.pt(sb, ta), f.pt(sb, tb), f.pt(sa, tb)], z0: za, z1: zb2)
            }
            var frame = MeshAcc(), glass = MeshAcc(), metal = MeshAcc()
            if o.kind == .door {
                let side: Double = o.flipFacing ? -1 : 1
                if fw > 0 {
                    box(&frame, s0, a, -h, h, zb, zt); box(&frame, b, s1, -h, h, zb, zt); box(&frame, a, b, -h, h, zt - fw, zt)
                }
                let lt = min(40 * u, h)
                let t0 = side * (h - 5 * u - lt), t1 = side * (h - 5 * u)
                let ztop = zt - fw
                switch o.doorStyle {
                case .double:
                    let mid = (a + b) / 2
                    box(&frame, a, mid - 1 * u, min(t0, t1), max(t0, t1), zb, ztop); box(&frame, mid + 1 * u, b, min(t0, t1), max(t0, t1), zb, ztop)
                case .sliding:
                    let mid = (a + b) / 2, ov = 50 * u
                    box(&frame, a, mid + ov, 5 * u, 35 * u, zb, ztop); box(&frame, mid - ov, b, -35 * u, -5 * u, zb, ztop)
                case .garage:
                    box(&frame, a, b, -20 * u, 20 * u, zb, ztop)
                default:
                    box(&frame, a, b, min(t0, t1), max(t0, t1), zb, ztop)
                }
                // Handle on the latch side, both faces.
                if o.doorStyle != .garage && o.doorStyle != .revolving {
                    let latch = o.doorStyle == .double ? (a + b) / 2 - 80 * u : (o.flipHand ? a + 70 * u : b - 70 * u)
                    let zh = zb + min(1000 * u, (ztop - zb) * 0.5)
                    let tf = max(t0, t1), tb2 = min(t0, t1)
                    box(&metal, latch - 60 * u, latch + 60 * u, tf, tf + 50 * u, zh - 10 * u, zh + 10 * u)
                    box(&metal, latch - 60 * u, latch + 60 * u, tb2 - 50 * u, tb2, zh - 10 * u, zh + 10 * u)
                }
                return [frame.group(el.id, kind, el.material ?? "Wood"), metal.group(el.id, kind, "Aluminium")].compactMap { $0 }
            }
            // Window.
            let fd = min(h, 35 * u)
            if fw > 0 {
                box(&frame, s0, a, -fd, fd, zb, zt); box(&frame, b, s1, -fd, fd, zb, zt)
                box(&frame, a, b, -fd, fd, zb, zb + fw); box(&frame, a, b, -fd, fd, zt - fw, zt)
            }
            let ia = zb + fw, ib = zt - fw
            let sashCount: Int
            switch o.windowStyle { case .fixed: sashCount = 0; case .doubleCasement, .sliding: sashCount = 2; default: sashCount = 1 }
            let gt = min(6 * u, fd / 2)
            if sashCount == 0 { box(&glass, a, b, -gt, gt, ia, ib) }
            else {
                let sw = max(fw * 0.6, 1e-3), sd = min(25 * u, fd)
                let w = (b - a) / Double(sashCount)
                for k in 0..<sashCount {
                    var sa = a + w * Double(k), sb = sa + w
                    var off = 0.0
                    if o.windowStyle == .sliding { off = (k == 0 ? 1 : -1) * min(20 * u, fd / 2); if k == 0 { sb += 20 * u } else { sa -= 20 * u } }
                    let ta = off - sd / 2, tb = off + sd / 2
                    box(&frame, sa, sa + sw, ta, tb, ia, ib); box(&frame, sb - sw, sb, ta, tb, ia, ib)
                    box(&frame, sa + sw, sb - sw, ta, tb, ia, ia + sw); box(&frame, sa + sw, sb - sw, ta, tb, ib - sw, ib)
                    box(&glass, sa + sw, sb - sw, off - gt, off + gt, ia + sw, ib - sw)
                }
            }
            let ext: Double = o.flipFacing ? 1 : -1
            let so = 40 * u
            box(&frame, s0 - so, s1 + so, min(ext * h * 0.5, ext * (h + so)), max(ext * h * 0.5, ext * (h + so)), zb - 30 * u, zb)
            let frameMat = el.props["frameMaterial"] ?? ((el.material ?? "Glass").caseInsensitiveCompare("Glass") == .orderedSame ? "Aluminium" : el.material!)
            return [frame.group(el.id, kind, frameMat), glass.group(el.id, kind, "Glass")].compactMap { $0 }

        case .slab(let g):
            var acc = MeshAcc()
            let top = elev + g.topOffset
            acc.prism(g.boundary, holes: g.holes, z0: top - g.thickness, z1: top)
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .column(let g):
            var acc = MeshAcc()
            let z0 = elev + g.baseOffset
            if g.round { acc.prism(RG.circle(g.position, g.width / 2), z0: z0, z1: z0 + g.height, smooth: true) }
            else { acc.prism(PlanRepresentation.columnPoly(g), z0: z0, z1: z0 + g.height) }
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .beam(let g):
            guard g.start.distance(to: g.end) > 1e-9 else { return [] }
            var acc = MeshAcc()
            let top = elev + g.topOffset
            acc.prism(PlanRepresentation.beamPoly(g), z0: top - g.depth, z1: top)
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .roof(let g):
            return roofGroups(el, g, elev: elev).compactMap { $0 }

        case .stair(let g):
            var acc = MeshAcc()
            let l = StairShapes.layout(g)
            let rh = g.riserHeight
            for t in l.treads {
                let top = elev + Double(t.step) * rh
                let bottom = t.landing ? top - max(rh, 200 * u) : top - rh
                acc.prism(t.poly, z0: max(bottom, elev), z1: top, smooth: false)
            }
            let st = 40 * u
            for fl in l.flights where fl.count > 0 {
                let len = Double(fl.count) * g.treadDepth
                let zBot = elev + Double(fl.firstStep - 1) * rh
                let top0 = zBot + rh + 50 * u, topN = zBot + Double(fl.count) * rh + 50 * u
                let prof: [(x: Double, z: Double)] = [(0, max(elev, top0 - 300 * u)), (len, topN - 300 * u), (len, topN), (0, top0)]
                let ay = fl.dir.perp
                acc.verticalPlate(prof, origin: fl.origin, ax: fl.dir, ay: ay, y0: g.width / 2, y1: g.width / 2 + st)
                acc.verticalPlate(prof, origin: fl.origin, ax: fl.dir, ay: ay, y0: -g.width / 2 - st, y1: -g.width / 2)
            }
            if g.kind == .spiral { acc.prism(RG.circle(g.start, max(60 * u, min(100, g.width * 0.15) * 0.6)), z0: elev, z1: elev + g.totalRise, smooth: true) }
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .railing(let g):
            let path = RG.dedupe(g.path, closed: false)
            guard path.count >= 2 else { return [] }
            var acc = MeshAcc()
            let zb = elev + g.baseOffset, zt = zb + g.height
            let ps = 20 * u, rw = 25 * u, rd = 40 * u
            var posts: [Vec2] = []
            for i in 0..<(path.count - 1) {
                let a = path[i], b = path[i + 1]
                let len = a.distance(to: b)
                let n = max(1, Int((len / (1200 * u)).rounded(.up)))
                for k in 0..<n { posts.append(a.lerp(b, Double(k) / Double(n))) }
                let d = (b - a).normalized.perp * rw
                acc.prism([a - d, b - d, b + d, a + d], z0: zt - rd, z1: zt)
            }
            posts.append(path[path.count - 1])
            for p in posts { acc.prism([p + Vec2(-ps, -ps), p + Vec2(ps, -ps), p + Vec2(ps, ps), p + Vec2(-ps, ps)], z0: zb, z1: zt - rd) }
            return [acc.group(el.id, kind, el.material ?? "Steel")].compactMap { $0 }

        case .space:
            return []

        case .curtainWall(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9, g.height > 0 else { return [] }
            let d = (g.end - g.start) / len, n = d.perp
            let m = max(g.mullionSize, 1e-3) / 2, md = m * 1.5
            let zb = elev + g.baseOffset, zt = zb + g.height
            var xs: [Double] = [0]
            if g.gridU > 1e-9 { var x = g.gridU; while x < len - m * 2 { xs.append(x); x += g.gridU } }
            xs.append(len)
            var zs: [Double] = [0]
            if g.gridV > 1e-9 { var z = g.gridV; while z < g.height - m * 2 { zs.append(z); z += g.gridV } }
            zs.append(g.height)
            func P(_ x: Double, _ y: Double) -> Vec2 { g.start + d * x + n * y }
            var frame = MeshAcc(), glass = MeshAcc()
            for x in xs {
                let x0 = max(0, x - m), x1 = min(len, x + m)
                frame.prism([P(x0, -md), P(x1, -md), P(x1, md), P(x0, md)], z0: zb, z1: zt)
            }
            for i in 0..<(xs.count - 1) {
                let x0 = xs[i] + m, x1 = xs[i + 1] - m
                guard x1 > x0 else { continue }
                for z in zs {
                    frame.prism([P(x0, -md), P(x1, -md), P(x1, md), P(x0, md)], z0: zb + max(0, z - m), z1: zb + min(g.height, z + m))
                }
                for j in 0..<(zs.count - 1) {
                    let za = zb + zs[j] + m, zc = zb + zs[j + 1] - m
                    if zc > za { glass.prism([P(x0, -5 * u), P(x1, -5 * u), P(x1, 5 * u), P(x0, 5 * u)], z0: za, z1: zc) }
                }
            }
            return [frame.group(el.id, kind, "Aluminium"), glass.group(el.id, kind, el.material ?? "Glass")].compactMap { $0 }

        case .component(let g):
            var acc = MeshAcc()
            let z0 = elev + g.baseOffset
            let hgt = g.size.z > 0 ? g.size.z : 1
            var usedBlock = false
            if let bn = g.block, let blk = doc.blocks[bn] {
                let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation) * Transform2D.translation(-blk.basePoint)
                for be in blk.entities {
                    let geo = GeometryOps.transform(be.geometry, t)
                    let closed: Bool
                    switch geo {
                    case .circle: closed = true
                    case .polyline(let p): closed = p.closed
                    case .ellipse(let e): closed = e.isFull
                    case .spline(let s): closed = s.closed
                    default: closed = false
                    }
                    guard closed else { continue }
                    for loop in GeometryOps.tessellate(geo, doc: doc) where loop.count >= 3 {
                        acc.prism(loop, z0: z0, z1: z0 + hgt, smooth: { if case .circle = geo { return true }; return false }())
                        usedBlock = true
                    }
                }
            }
            if !usedBlock { acc.prism(PlanRepresentation.componentPoly(g), z0: z0, z1: z0 + hgt) }
            return [acc.group(el.id, kind, el.material ?? "Wood")].compactMap { $0 }

        case .gridLine:
            return []
        }
    }

    static func roofGroups(_ el: BIMElement, _ g: RoofGeom, elev: Double) -> [MeshGroup?] {
        let r = RoofShapes.faces(g)
        guard r.footprint.count >= 3 else { return [] }
        var acc = MeshAcc()
        let zb = elev + g.baseOffset
        if g.kind == .flat || r.faces.allSatisfy({ $0.grad.length < 1e-12 }) {
            acc.prism(r.footprint, z0: zb, z1: zb + max(g.thickness, 1e-3))
            return [acc.group(el.id, el.typeName, el.material ?? "Roof Tiles")]
        }
        let tv = g.thickness / max(cos(rad(min(g.pitch, 85))), 0.05)
        let tol = 1e-6 * max(1, BBox2(points: r.footprint).width) * 10 + 1e-6
        for f in r.faces {
            var poly = f.poly
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            let bottom = poly.map { Vec3($0.x, $0.y, zb + f.height($0)) }
            let top = poly.map { Vec3($0.x, $0.y, zb + f.height($0) + tv) }
            acc.face(top, outward: Vec3.unitZ)
            acc.face(bottom, outward: -Vec3.unitZ)
            acc.edges.append(top + [top[0]])
            for i in 0..<poly.count {
                let j = (i + 1) % poly.count
                guard RoofShapes.onOutline(poly[i], poly[j], r.footprint, tol: tol) else { continue }
                let d = (poly[j] - poly[i]).normalized
                acc.face([bottom[i], bottom[j], top[j], top[i]], outward: Vec3(d.y, -d.x, 0))
                acc.edges.append([bottom[i], bottom[j]])
                acc.edges.append([bottom[i], top[i]])
            }
        }
        return [acc.group(el.id, el.typeName, el.material ?? "Roof Tiles")]
    }

    // MARK: Entities

    static func entityGroups(_ geo: Geometry, id: EntityID, layer: String, props: [String: String], doc: ArchiDocument, depth: Int) -> [MeshGroup] {
        let material = props["material"] ?? "Concrete"
        switch geo {
        case .solid(let s):
            var acc = MeshAcc()
            solid(s, into: &acc)
            return [acc.group(id, "solid", props["material"] ?? "Concrete")].compactMap { $0 }
        case .insert(let ins):
            guard depth < 8, let b = doc.blocks[ins.block] else { return [] }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            return b.entities.flatMap { be -> [MeshGroup] in
                let g = GeometryOps.transform(be.geometry, t)
                return entityGroups(g, id: id, layer: layer, props: be.props.merging(props) { a, _ in a }, doc: doc, depth: depth + 1)
            }
        default:
            guard let th = props["thickness"].flatMap(Double.init), abs(th) > 1e-9 else { return [] }
            let z0 = props["elevation"].flatMap(Double.init) ?? 0
            let za = min(z0, z0 + th), zb = max(z0, z0 + th)
            var acc = MeshAcc()
            var closed = false
            switch geo {
            case .circle: closed = true
            case .polyline(let p): closed = p.closed
            case .ellipse(let e): closed = e.isFull
            case .spline(let s): closed = s.closed
            default: break
            }
            for pl in GeometryOps.tessellate(geo, doc: doc) where pl.count >= 2 {
                if closed && pl.count >= 3 { acc.prism(pl, z0: za, z1: zb, smooth: { if case .circle = geo { return true }; return false }()) }
                else {
                    for i in 0..<(pl.count - 1) {
                        let a = pl[i], b = pl[i + 1]
                        guard a.distance(to: b) > 1e-12 else { continue }
                        let q = [MeshAcc.up(a, za), MeshAcc.up(b, za), MeshAcc.up(b, zb), MeshAcc.up(a, zb)]
                        acc.face(q); acc.face(q.reversed())
                    }
                    acc.edges.append(pl.map { MeshAcc.up($0, za) }); acc.edges.append(pl.map { MeshAcc.up($0, zb) })
                }
            }
            return [acc.group(id, "extrusion", material)].compactMap { $0 }
        }
    }

    static func solid(_ s: SolidGeom, into acc: inout MeshAcc) {
        let o2 = s.origin.xy
        let rot = Transform2D.translation(o2) * Transform2D.rotation(s.rotation)
        switch s.kind {
        case .box:
            let pts = [Vec2(0, 0), Vec2(s.size.x, 0), Vec2(s.size.x, s.size.y), Vec2(0, s.size.y)].map(rot.apply)
            acc.prism(pts, z0: min(s.origin.z, s.origin.z + s.size.z), z1: max(s.origin.z, s.origin.z + s.size.z))
        case .cylinder:
            guard s.size.x > 0, s.size.z != 0 else { return }
            acc.prism(RG.circle(o2, s.size.x), z0: min(s.origin.z, s.origin.z + s.size.z), z1: max(s.origin.z, s.origin.z + s.size.z), smooth: true)
        case .cone:
            let r0 = max(s.size.x, 0), r1 = max(s.size.y, 0), h = s.size.z
            guard h > 0, r0 + r1 > 0 else { return }
            let n = max(12, GeometryOps.segments(radius: max(r0, r1), sweep: 2 * .pi))
            let z0 = s.origin.z, z1 = z0 + h
            let slope = (r0 - r1) / h
            for i in 0..<n {
                let a0 = 2 * .pi * Double(i) / Double(n), a1 = 2 * .pi * Double(i + 1) / Double(n)
                let na = Vec3(cos(a0), sin(a0), slope).normalized, nb = Vec3(cos(a1), sin(a1), slope).normalized
                let p0 = o2 + Vec2.polar(r0, a0), p1 = o2 + Vec2.polar(r0, a1), q0 = o2 + Vec2.polar(r1, a0), q1 = o2 + Vec2.polar(r1, a1)
                acc.tri(MeshAcc.up(p0, z0), MeshAcc.up(p1, z0), MeshAcc.up(q1, z1), na, nb, nb)
                if r1 > 1e-12 { acc.tri(MeshAcc.up(p0, z0), MeshAcc.up(q1, z1), MeshAcc.up(q0, z1), na, nb, na) }
            }
            if r0 > 1e-12 { acc.cap(RG.circle(o2, r0, segments: n), z: z0, up: false) }
            if r1 > 1e-12 { acc.cap(RG.circle(o2, r1, segments: n), z: z1, up: true) }
            acc.edges.append((RG.circle(o2, max(r0, 1e-9), segments: n) + [o2 + Vec2(max(r0, 1e-9), 0)]).map { MeshAcc.up($0, z0) })
            if r1 > 1e-12 { acc.edges.append((RG.circle(o2, r1, segments: n) + [o2 + Vec2(r1, 0)]).map { MeshAcc.up($0, z1) }) }
        case .sphere:
            let r = s.size.x
            guard r > 0 else { return }
            let c = s.origin
            let slices = max(16, min(96, GeometryOps.segments(radius: r, sweep: 2 * .pi))), stacks = max(8, slices / 2)
            func P(_ i: Int, _ j: Int) -> Vec3 {
                let th = Double.pi * Double(j) / Double(stacks) - .pi / 2, ph = 2 * .pi * Double(i) / Double(slices)
                return Vec3(cos(th) * cos(ph), cos(th) * sin(ph), sin(th))
            }
            for j in 0..<stacks {
                for i in 0..<slices {
                    let a = P(i, j), b = P(i + 1, j), cc = P(i + 1, j + 1), d = P(i, j + 1)
                    if j > 0 { acc.tri(c + a * r, c + b * r, c + cc * r, a, b, cc) }
                    if j < stacks - 1 { acc.tri(c + a * r, c + cc * r, c + d * r, a, cc, d) }
                }
            }
            acc.edges.append((0...slices).map { i in c + P(i, stacks / 2) * r })
        case .extrusion:
            let prof = s.profile.map(rot.apply)
            guard prof.count >= 3, s.height != 0 else { return }
            acc.prism(prof, z0: min(s.origin.z, s.origin.z + s.height), z1: max(s.origin.z, s.origin.z + s.height))
        case .revolve:
            var prof = RG.dedupe(s.profile, closed: true)
            guard prof.count >= 2 else { return }
            if prof.count >= 3, GeometryOps.signedArea(prof) < 0 { prof.reverse() }
            let total = abs(s.height) < 1e-9 ? 2 * .pi : min(abs(s.height), 2 * .pi)
            let full = total >= 2 * .pi - 1e-9
            let maxR = prof.map { abs($0.x) }.max() ?? 1
            let n = max(8, Int(Double(GeometryOps.segments(radius: max(maxR, 1e-6), sweep: total))))
            func W(_ p: Vec2, _ phi: Double) -> Vec3 {
                let local = Vec3(p.x * cos(phi), p.y, p.x * sin(phi))
                let q = rot.apply(Vec2(local.x, local.y))
                return Vec3(q.x, q.y, s.origin.z + local.z)
            }
            func N(_ n2: Vec2, _ phi: Double) -> Vec3 {
                let v = Vec2(n2.x * cos(phi), n2.y)
                let q = rot.applyVector(v)
                return Vec3(q.x, q.y, n2.x * sin(phi)).normalized
            }
            let m = prof.count >= 3 ? prof.count : prof.count - 1
            for k in 0..<m {
                let a = prof[k], b = prof[(k + 1) % prof.count]
                let e = (b - a).normalized
                let n2 = Vec2(e.y, -e.x)
                for i in 0..<n {
                    let p0 = total * Double(i) / Double(n), p1 = total * Double(i + 1) / Double(n)
                    acc.tri(W(a, p0), W(b, p0), W(b, p1), N(n2, p0), N(n2, p0), N(n2, p1))
                    acc.tri(W(a, p0), W(b, p1), W(a, p1), N(n2, p0), N(n2, p1), N(n2, p1))
                }
            }
            if !full && prof.count >= 3 {
                acc.face(prof.map { W($0, 0) }); acc.face(prof.map { W($0, total) })
            }
            for p in prof { acc.edges.append((0...n).map { W(p, total * Double($0) / Double(n)) }) }
        case .mesh:
            let v = s.meshVertices
            var i = 0
            while i + 2 < s.meshTriangles.count {
                let ia = s.meshTriangles[i], ib = s.meshTriangles[i + 1], ic = s.meshTriangles[i + 2]
                i += 3
                guard ia >= 0, ib >= 0, ic >= 0, ia < v.count, ib < v.count, ic < v.count else { continue }
                let n = (v[ib] - v[ia]).cross(v[ic] - v[ia]).normalized
                acc.tri(v[ia], v[ib], v[ic], n, n, n)
            }
        }
    }
}
