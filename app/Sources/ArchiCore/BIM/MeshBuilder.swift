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
    public static func build(doc fullDoc: ArchiDocument) -> [MeshGroup] {
        let doc = ModelSets.visibleModel(BIMUpdaters.regenerated(fullDoc))
        let ctx = BIMContext(doc: doc)
        var out: [MeshGroup] = []
        let phased = Phasing.isActive(doc)
        let pf = Phasing.filter(doc)
        func shown(_ props: [String: String]) -> Bool {
            guard phased else { return true }
            let st = Phasing.status(props, doc: doc)
            if st == .demolished { return pf == .demolition }
            return Phasing.visible(st, pf)
        }
        for el in doc.elements where doc.isVisible(layer: el.layer) && shown(el.props) && el.props["hasParts"] != "1" && Assemblies.shown(el, doc: doc) { out += groups(el, ctx: ctx) }
        for e in doc.entities where doc.isVisible(layer: e.layer) && shown(e.props) { out += groups(for: e, doc: doc) }
        if doc.variable("DATUMS3D") == "1" { out += datumGroups(doc: doc) }
        return out
    }

    /// Levels and grids as 3D datum lines (edge-only groups, kind "datum"): a level outline around the model at every
    /// level elevation, and each grid line repeated at every level with vertical end lines and a head bubble on top.
    public static func datumGroups(doc: ArchiDocument) -> [MeshGroup] {
        let u = 1 / doc.units.mm
        var box = BBox2.empty
        for el in doc.elements {
            switch el.geometry {
            case .gridLine(let g): g.points.forEach { box.add($0) }
            case .opening: continue
            default: for p in CommandHelpers.footprint(el, doc: doc) { box.add(p) }
            }
        }
        guard !box.isEmpty, !doc.levels.isEmpty else { return [] }
        box = box.expanded(by: 1500 * u)
        let levels = doc.levels.sorted { $0.elevation < $1.elevation }
        let zLow = levels.first!.elevation, zTop = levels.last!.elevation + levels.last!.height
        var out: [MeshGroup] = []
        var lv: [[Vec3]] = []
        for l in levels {
            let c = box.corners.map { Vec3($0.x, $0.y, l.elevation) }
            lv.append(c + [c[0]])
            // Level head: a small triangle on the right-hand end of the front edge.
            let h = Vec3(box.max.x, box.min.y, l.elevation), s = 250 * u
            lv.append([h, h + Vec3(s, 0, s), h + Vec3(s, 0, -s), h])
        }
        out.append(MeshGroup(id: nil, kind: "datum", material: "Datum", mesh: Mesh(), edges: lv))
        for el in doc.elements {
            guard case .gridLine(let g) = el.geometry, g.start.distance(to: g.end) > 1e-9 else { continue }
            var e: [[Vec3]] = []
            let gp = g.points
            for l in levels { e.append(gp.map { Vec3($0.x, $0.y, l.elevation) }) }
            for p in [g.start, g.end] { e.append([Vec3(p.x, p.y, zLow), Vec3(p.x, p.y, zTop)]) }
            let d = (gp[1] - gp[0]).normalized, r = 400 * u
            let c = Vec3(g.start.x, g.start.y, zTop + r)
            e.append((0...32).map { k in let a = 2 * Double.pi * Double(k) / 32; return c + Vec3(d.x * cos(a) * r, d.y * cos(a) * r, sin(a) * r) })
            out.append(MeshGroup(id: el.id, kind: "datum", material: "Datum", mesh: Mesh(), edges: e))
        }
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
            let range = BIMConstraints.wallRange(el, doc: doc)
            let z0 = range.z0, z1 = range.z1
            let zb = BIMConstraints.wallNominalBase(el, doc: doc)
            guard z1 - z0 > 1e-9 else { return [] }
            // Compound wall types (BIM-014): each ply is its own solid with its own material, so 3D views, sections
            // (cut patterns per ply) and exports show the build-up.
            let plies = WallPlies.bands(g, doc: doc, halfThickness: f.h)
            var plyAcc = [MeshAcc](repeating: MeshAcc(), count: plies.count)
            func emit(_ poly: [Vec2], _ za: Double, _ zb2: Double) {
                guard plies.count > 1 else { acc.prism(poly, z0: za, z1: zb2, smooth: f.isCurved); return }
                for (k, band) in plies.enumerated() {
                    for part in WallPlies.clip(poly, f: f, tlo: band.tlo, thi: band.thi) { plyAcc[k].prism(part, z0: za, z1: zb2, smooth: f.isCurved) }
                }
            }
            for pc in ctx.pieces(f) { emit(pc.poly, z0, z1) }
            for c in ctx.cuts(f) {
                for part in wallCutBands(c, f: f, z0: z0, z1: z1, openingBase: zb) {
                    let poly = f.face(-f.h, part.s0, part.s1) + f.face(f.h, part.s0, part.s1).reversed()
                    for b in part.bands {
                        switch b.kind {
                        case .solid: emit(poly, b.z0, b.z1)
                        case .niche(let depth, let fromLeft):
                            guard depth < 2 * f.h - 1e-9 else { continue }
                            let t0 = fromLeft ? -f.h : -f.h + depth, t1 = fromLeft ? f.h - depth : f.h
                            let back = f.face(t0, part.s0, part.s1) + f.face(t1, part.s0, part.s1).reversed()
                            emit(back, b.z0, b.z1)
                        case .open: continue
                        }
                    }
                }
            }
            slabTopInfill(f, wall: el, z1: z1, doc: doc, into: &acc)
            roofInfill(f, wall: el, z1: z1, ctx: ctx, into: &acc)
            var mat = el.material ?? "Plaster"
            if let tn = g.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), let p = wt.plies.first { mat = p.material }
            // Elevation profile (BIM-020), then slant/taper (BIM-023).
            if let cutter = WallShapes.profileSolid(g, f: f, zBase: zb) {
                let pe = WallShapes.profileEdges(g, f: f, zBase: zb)
                acc = WallShapes.trim(acc, to: cutter); acc.edges = pe
                for k in plyAcc.indices { plyAcc[k] = WallShapes.trim(plyAcc[k], to: cutter); plyAcc[k].edges = pe }
            }
            if g.isSlantedOrTapered {
                WallShapes.shape(&acc, g, f: f, zBase: z0, height: z1 - z0)
                for k in plyAcc.indices { WallShapes.shape(&plyAcc[k], g, f: f, zBase: z0, height: z1 - z0) }
            }
            // Reveals (BIM-021) are grooves cut into the faces.
            let reveals = g.sweeps.filter(\.isReveal)
            if !reveals.isEmpty {
                var cutter = MeshAcc()
                var grooves: [[Vec3]] = []
                for sw in reveals { WallPlies.revealCutter(sw, f, z0: z0, ctx: ctx, into: &cutter, edges: &grooves) }
                acc = WallPlies.subtract(acc, cutter, extraEdges: plies.count > 1 ? [] : grooves)
                for k in plyAcc.indices { plyAcc[k] = WallPlies.subtract(plyAcc[k], cutter, extraEdges: k == 0 || k == plyAcc.count - 1 ? grooves : []) }
            }
            var out = [acc.group(el.id, kind, mat)].compactMap { $0 }
            for (k, band) in plies.enumerated() where plies.count > 1 {
                if let grp = plyAcc[k].group(el.id, kind, band.material ?? mat) { out.append(grp) }
            }
            for sw in g.sweeps where !sw.isReveal {
                var sa = MeshAcc()
                wallSweep(sw, f, z0: z0, ctx: ctx, into: &sa)
                if let grp = sa.group(el.id, "wallSweep", sw.material ?? mat) { out.append(grp) }
            }
            return out

        case .opening(let o):
            guard o.kind != .opening, o.width > 0, o.height > 0,
                  let host = doc.element(o.hostWall), let f = ctx.frames[host.id] ?? WallFrame(host),
                  case .wall(let hg) = host.geometry else { return [] }
            if let fn = el.props["family"], let def = doc.family(named: fn) {
                return FamilyEngine.openingGroups(def, el: el, o: o, f: f, zBase: ctx.levelElevation(host.level) + hg.baseOffset, doc: doc)
            }
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
                var ztop = zt - fw
                if o.transoms > 0 && fw > 0 {
                    // Fanlight (transom light) above the leaf: transom bar and glazing.
                    let fanH = min(400 * u, (zt - zb) * 0.2)
                    let zt2 = ztop - fanH
                    box(&frame, a, b, -h, h, zt2 - fw, zt2)
                    let gt = min(6 * u, h / 2)
                    box(&glass, a, b, -gt, gt, zt2, ztop)
                    ztop = zt2 - fw
                }
                if o.threshold {
                    box(&metal, s0, s1, -h - 10 * u, h + 10 * u, zb, zb + 15 * u)
                }
                if o.variant == .pocket {
                    // Pocket door: the leaf stands half open in the wall plane, its other half inside the pocket.
                    let lw2 = min(20 * u, h * 0.4), lf = b - a
                    let (p0, p1) = o.flipHand ? (a + lf * 0.5, b + lf * 0.5) : (a - lf * 0.5, b - lf * 0.5)
                    box(&frame, p0, p1, -lw2, lw2, zb, ztop)
                } else if o.variant == .biFold {
                    // Bi-fold: panels folded to the jambs as thin plates at the zig-zag angle (approximated by slabs).
                    let n = max(2, min(8, Int(((b - a) / (450 * u)).rounded())))
                    let panels = n % 2 == 0 ? n : n + 1
                    let q = (b - a) / Double(panels)
                    for k in 0..<panels {
                        let x0 = a + q * Double(k), off = (k % 2 == 0 ? 1.0 : -1.0) * 15 * u
                        box(&frame, x0 + 2 * u, x0 + q - 2 * u, side * off - 12 * u, side * off + 12 * u, zb, ztop)
                    }
                } else {
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
                }
                // Handle on the latch side, both faces.
                if o.doorStyle != .garage && o.doorStyle != .revolving {
                    let latch = o.doorStyle == .double ? (a + b) / 2 - 80 * u : (o.flipHand ? a + 70 * u : b - 70 * u)
                    let zh = zb + min(1000 * u, (ztop - zb) * 0.5)
                    let tf = max(t0, t1), tb2 = min(t0, t1)
                    box(&metal, latch - 60 * u, latch + 60 * u, tf, tf + 50 * u, zh - 10 * u, zh + 10 * u)
                    box(&metal, latch - 60 * u, latch + 60 * u, tb2 - 50 * u, tb2, zh - 10 * u, zh + 10 * u)
                }
                return [frame.group(el.id, kind, el.material ?? "Wood"), metal.group(el.id, kind, "Aluminium"), glass.group(el.id, kind, "Glass")].compactMap { $0 }
                    + OpeningTrim.meshGroups(el, o, f: f, zb: zb, zt: zt, unit: u)
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
            // Glazing bars: extra mullions and transoms dividing the lights.
            if o.mullions > 0 || o.transoms > 0 {
                let bw = max(fw * 0.6, 20 * u) / 2, bd = min(fd * 0.8, 30 * u)
                for k in 0..<o.mullions {
                    let x = a + (b - a) * Double(k + 1) / Double(o.mullions + 1)
                    box(&frame, x - bw, x + bw, -bd, bd, ia, ib)
                }
                for k in 0..<o.transoms {
                    let z = ia + (ib - ia) * Double(k + 1) / Double(o.transoms + 1)
                    box(&frame, a, b, -bd, bd, z - bw, z + bw)
                }
            }
            // Casement handles on the room side of opening sashes.
            if sashCount > 0 && o.windowStyle != .sliding {
                let side: Double = o.flipFacing ? -1 : 1
                let zh = ia + (ib - ia) * 0.45
                let hx = o.windowStyle == .doubleCasement ? (a + b) / 2 - 60 * u : (o.flipHand ? a + 60 * u : b - 60 * u)
                box(&frame, hx - 12 * u, hx + 12 * u, side > 0 ? fd : -fd - 40 * u, side > 0 ? fd + 40 * u : -fd, zh - 60 * u, zh + 60 * u)
            }
            let ext: Double = o.flipFacing ? 1 : -1
            let so = 40 * u
            box(&frame, s0 - so, s1 + so, min(ext * h * 0.5, ext * (h + so)), max(ext * h * 0.5, ext * (h + so)), zb - 30 * u, zb)
            let frameMat = el.props["frameMaterial"] ?? ((el.material ?? "Glass").caseInsensitiveCompare("Glass") == .orderedSame ? "Aluminium" : el.material!)
            return [frame.group(el.id, kind, frameMat), glass.group(el.id, kind, "Glass")].compactMap { $0 }
                + OpeningTrim.meshGroups(el, o, f: f, zb: zb, zt: zt, unit: u)

        case .slab(let g):
            let edges = Round7Shapes.slabEdgeGroups(el, g, elev: elev)
            if el.props["slabType"] != nil || doc.entities.contains(where: { Shafts.isShaft($0) }) {
                return SlabDetails.groups(el, g, elev: elev, doc: doc) + edges
            }
            var acc = MeshAcc()
            let top = elev + g.topOffset
            if g.isSloped { slopedSlab(g, elev: elev, into: &acc) }
            else { acc.prism(g.boundary, holes: g.holes, z0: top - g.thickness, z1: top) }
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 } + edges

        case .column(let g):
            var acc = MeshAcc()
            let z0 = elev + g.baseOffset
            if let sec = StructuralProfiles.section(g.profile) {
                let o = StructuralProfiles.outline(sec, unit: u)
                let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
                acc.prism(o.outer.map(t.apply), holes: o.holes.map { $0.map(t.apply) }, z0: z0, z1: z0 + g.height, smooth: sec.shape == .chs || sec.shape == .round)
                return [acc.group(el.id, kind, el.material ?? "Steel")].compactMap { $0 }
            }
            if g.round { acc.prism(RG.circle(g.position, g.width / 2), z0: z0, z1: z0 + g.height, smooth: true) }
            else { acc.prism(PlanRepresentation.columnPoly(g), z0: z0, z1: z0 + g.height) }
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .beam(let g):
            guard g.start.distance(to: g.end) > 1e-9 else { return [] }
            var acc = MeshAcc()
            let top = elev + g.topOffset
            if let sec = StructuralProfiles.section(g.profile) {
                let o = StructuralProfiles.outline(sec, unit: u)
                let hh = sec.h * u / 2
                acc.member(o.outer, holes: o.holes, from: Vec3(g.start.x, g.start.y, top - hh), to: Vec3(g.end.x, g.end.y, elev + g.endTop - hh),
                           smooth: sec.shape == .chs || sec.shape == .round)
                return [acc.group(el.id, kind, el.material ?? "Steel")].compactMap { $0 }
            }
            if g.isSloped {
                let w = g.width / 2, dd = g.depth / 2
                acc.member([Vec2(-w, -dd), Vec2(w, -dd), Vec2(w, dd), Vec2(-w, dd)], from: Vec3(g.start.x, g.start.y, top - dd), to: Vec3(g.end.x, g.end.y, elev + g.endTop - dd))
            } else {
                acc.prism(PlanRepresentation.beamPoly(g), z0: top - g.depth, z1: top)
            }
            return [acc.group(el.id, kind, el.material ?? "Concrete")].compactMap { $0 }

        case .roof(let g):
            return RoofDetails.groups(el, g, elev: elev, doc: doc)

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
            // Newel posts at winder pivots.
            for nw in l.newels {
                let s = max(50 * u, 1e-3)
                acc.prism([nw + Vec2(-s, -s), nw + Vec2(s, -s), nw + Vec2(s, s), nw + Vec2(-s, s)], z0: elev, z1: elev + g.totalRise + 900 * u)
            }
            var rail = MeshAcc()
            if g.kind == .spiral {
                let r0 = g.spiralInnerRadius
                acc.prism(RG.circle(g.start, max(40 * u, r0 * 0.6)), z0: elev, z1: elev + g.totalRise + 900 * u, smooth: true)
                // Helical handrail on the outer edge, 900 above the tread nosings.
                let rr = r0 + g.width - 40 * u, n = max(g.riserCount - 1, 1)
                let dt = (g.turnsRight ? -1.0 : 1.0) * g.treadDepth / (r0 + g.width / 2)
                let steps = max(8, n * 4)
                var helix: [Vec3] = []
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let a = g.direction + dt * Double(n) * t
                    let q = g.start + Vec2.polar(rr, a)
                    helix.append(Vec3(q.x, q.y, elev + rh * (1 + Double(n - 1) * t) + 900 * u))
                }
                let rp = (0..<12).map { Vec2.polar(20 * u, 2 * Double.pi * Double($0) / 12) }
                SweepMesh.sweep(rp, along: helix, into: &rail)
                for i in stride(from: 0, through: n - 1, by: 2) {
                    let a = g.direction + dt * (Double(i) + 0.5)
                    let q = g.start + Vec2.polar(rr, a)
                    let zt = elev + rh * Double(i + 1)
                    rail.prism(RG.circle(q, 10 * u, segments: 10), z0: zt, z1: zt + 900 * u, smooth: true)
                }
            }
            return [acc.group(el.id, kind, el.material ?? "Concrete"), rail.group(el.id, kind, "Steel")].compactMap { $0 }

        case .railing(let g):
            if g.isTyped { return RailingTypes.groups(el, g, elev: elev, doc: doc) }
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
                if !g.isSloped {
                    let d = (b - a).normalized.perp * rw
                    acc.prism([a - d, b - d, b + d, a + d], z0: zt - rd, z1: zt)
                }
            }
            if g.isSloped {
                // Railing on a stair or ramp: the top rail follows the path heights.
                let rail = path.map { Vec3($0.x, $0.y, zt - rd / 2 + g.z(at: $0)) }
                SweepMesh.sweep([Vec2(-rw, -rd / 2), Vec2(rw, -rd / 2), Vec2(rw, rd / 2), Vec2(-rw, rd / 2)], along: rail, into: &acc)
            }
            posts.append(path[path.count - 1])
            for p in posts {
                let dz = g.z(at: p)
                acc.prism([p + Vec2(-ps, -ps), p + Vec2(ps, -ps), p + Vec2(ps, ps), p + Vec2(-ps, ps)], z0: zb + dz, z1: zt - rd + dz)
            }
            return [acc.group(el.id, kind, el.material ?? "Steel")].compactMap { $0 }

        case .space:
            return []

        case .curtainWall(let g):
            let len = g.start.distance(to: g.end)
            guard len > 1e-9, g.height > 0 else { return [] }
            let d = (g.end - g.start) / len, n = d.perp
            let m = max(g.mullionSize, 1e-3) / 2, md = m * 1.5
            let zb = elev + g.baseOffset, zt = zb + g.height
            let xs: [Double] = [0] + g.uPositions + [len]
            let zs: [Double] = [0] + g.vPositions + [g.height]
            func P(_ x: Double, _ y: Double) -> Vec2 { g.start + d * x + n * y }
            var frame = MeshAcc(), glass = MeshAcc(), solid = MeshAcc(), spandrel = MeshAcc()
            for (xi, x) in xs.enumerated() {
                frame.prism(CurtainMullion.planSection(g, x: x, border: xi == 0 || xi == xs.count - 1), z0: zb, z1: zt)
            }
            let mdepth = CurtainMullion.depth(g)
            /// Horizontal member (transom/sill/head) of the grid type between x0 and x1 at height z (relative to the base).
            func transom(_ x0: Double, _ x1: Double, _ z: Double, border: Bool) {
                guard x1 - x0 > 1e-9 else { return }
                var sec = CurtainMullion.section(CurtainMullion.type(g, border: border), width: g.mullionSize, depth: mdepth)
                if border {
                    let lo = sec.map(\.x).min() ?? 0, hi = sec.map(\.x).max() ?? 0
                    let shift = z <= 1e-9 ? -lo : (z >= g.height - 1e-9 ? -hi : 0)
                    sec = sec.map { Vec2($0.x + shift, $0.y) }
                }
                // Section (a → up, b → normal) extruded along the wall; the frame's second axis is −normal.
                frame.extrudeSection(sec.map { Vec2($0.x, -$0.y) }, origin: Vec3(g.start.x + d.x * x0, g.start.y + d.y * x0, zb + z), axis: Vec3(d.x, d.y, 0), xAxis: .unitZ, length: x1 - x0)
            }
            for i in 0..<(xs.count - 1) {
                let x0 = xs[i] + m, x1 = xs[i + 1] - m
                guard x1 > x0 else { continue }
                let door = zs.count > 1 && ["door", "doubledoor"].contains(g.panels["\(i),0"] ?? "")
                for (zi, z) in zs.enumerated() {
                    if zi == 0 && door { continue }   // no sill mullion under a door
                    // Transoms are omitted between two empty panels.
                    if zi > 0 && zi < zs.count - 1, g.panels["\(i),\(zi - 1)"] == "empty", g.panels["\(i),\(zi)"] == "empty" { continue }
                    transom(x0, x1, z, border: zi == 0 || zi == zs.count - 1)
                }
                for j in 0..<(zs.count - 1) {
                    let za = zb + zs[j] + m, zc = zb + zs[j + 1] - m
                    guard zc > za else { continue }
                    switch g.panels["\(i),\(j)"] ?? "glass" {
                    case "empty": continue
                    case "door", "doubledoor":
                        let leaves = g.panels["\(i),\(j)"] == "doubledoor" ? 2 : 1
                        let lw = (x1 - x0) / Double(leaves), fw = min(60 * u, lw / 5), t = 20 * u
                        let zd = j == 0 ? zb : za
                        for k in 0..<leaves {
                            let a = x0 + lw * Double(k) + 2 * u, b = a + lw - 4 * u
                            func bx(_ acc: inout MeshAcc, _ s0: Double, _ s1: Double, _ z0: Double, _ z1: Double, _ y: Double) {
                                guard s1 - s0 > 1e-9, z1 - z0 > 1e-9 else { return }
                                acc.prism([P(s0, -y), P(s1, -y), P(s1, y), P(s0, y)], z0: z0, z1: z1)
                            }
                            bx(&frame, a, a + fw, zd, zc, t); bx(&frame, b - fw, b, zd, zc, t)
                            bx(&frame, a + fw, b - fw, zd, zd + fw * 1.5, t); bx(&frame, a + fw, b - fw, zc - fw, zc, t)
                            bx(&glass, a + fw, b - fw, zd + fw * 1.5, zc - fw, 5 * u)
                            // Pull handle on the latch stile, both faces.
                            let hx = leaves == 2 ? (k == 0 ? b - fw / 2 : a + fw / 2) : b - fw / 2
                            let hz = zd + min(1000 * u, (zc - zd) * 0.5)
                            frame.prism([P(hx - 12 * u, t), P(hx + 12 * u, t), P(hx + 12 * u, t + 60 * u), P(hx - 12 * u, t + 60 * u)], z0: hz - 300 * u, z1: hz + 300 * u)
                            frame.prism([P(hx - 12 * u, -t - 60 * u), P(hx + 12 * u, -t - 60 * u), P(hx + 12 * u, -t), P(hx - 12 * u, -t)], z0: hz - 300 * u, z1: hz + 300 * u)
                        }
                    case "solid": solid.prism([P(x0, -20 * u), P(x1, -20 * u), P(x1, 20 * u), P(x0, 20 * u)], z0: za, z1: zc)
                    case "spandrel":
                        // Opaque insulated panel: back-pan behind a spandrel glass skin.
                        spandrel.prism([P(x0, -10 * u), P(x1, -10 * u), P(x1, 50 * u), P(x0, 50 * u)], z0: za, z1: zc)
                        glass.prism([P(x0, -18 * u), P(x1, -18 * u), P(x1, -12 * u), P(x0, -12 * u)], z0: za, z1: zc)
                    case "louvre":
                        let bd = min(md, 60 * u)
                        for zc0 in CurtainMullion.louvreBlades(z0: za, z1: zc, pitch: 150 * u) {
                            let blade = [Vec2(-45 * u, bd), Vec2(-5 * u, -bd), Vec2(10 * u, -bd), Vec2(-30 * u, bd)]
                            frame.extrudeSection(blade, origin: Vec3(g.start.x + d.x * x0, g.start.y + d.y * x0, zc0), axis: Vec3(d.x, d.y, 0), xAxis: .unitZ, length: x1 - x0)
                        }
                    default: glass.prism([P(x0, -5 * u), P(x1, -5 * u), P(x1, 5 * u), P(x0, 5 * u)], z0: za, z1: zc)
                    }
                }
            }
            return [frame.group(el.id, kind, el.props["mullionMaterial"] ?? "Aluminium"), glass.group(el.id, kind, el.material ?? "Glass"),
                    solid.group(el.id, kind, el.props["panelMaterial"] ?? "Aluminium"), spandrel.group(el.id, kind, el.props["spandrelMaterial"] ?? "Steel")].compactMap { $0 }

        case .component(let g):
            if g.mesh != nil { return InPlaceModels.meshGroups(el, g, z0: elev + g.baseOffset) }
            if el.props["kind"] == "skylight" { return RoofDetails.skylightGroups(el, g, doc: doc) }
            if g.block == nil, g.path == nil, let def = doc.family(named: g.family) {
                return FamilyEngine.meshGroups(def, el: el, g: g, doc: doc, z0: elev + g.baseOffset)
            }
            if g.block == nil, let rf = ComponentLibrary.runFamily(g.family) {
                return RunFamilies.meshGroups(rf, g, id: el.id, z0: elev + g.baseOffset, unit: u, overrides: el.props)
            }
            if g.block == nil, let fam = ComponentLibrary.family(g.family) {
                return ComponentLibrary.meshGroups(fam, g, id: el.id, z0: elev + g.baseOffset, overrides: el.props)
            }
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

    enum BandKind: Equatable { case solid, open, niche(depth: Double, fromLeft: Bool) }
    struct Band: Equatable { var z0: Double; var z1: Double; var kind: BandKind }
    struct CutPart { var s0: Double; var s1: Double; var bands: [Band] }

    /// Splits a merged opening interval of a wall into runs along the wall with the vertical bands that stay solid,
    /// so openings that overlap along the wall but sit at different heights (a window above a door, stacked windows)
    /// each cut their own hole. Absolute Z; `openingBase` is the level from which opening sills are measured.
    static func wallCutBands(_ c: (s0: Double, s1: Double, els: [BIMElement]), f: WallFrame, z0: Double, z1: Double, openingBase: Double) -> [CutPart] {
        struct Op { var a: Double; var b: Double; var lo: Double; var hi: Double; var niche: OpeningGeom? }
        var ops: [Op] = []
        for oe in c.els {
            guard case .opening(let o) = oe.geometry, o.width > 0, o.height > 0 else { continue }
            let a = max(o.offset - o.width / 2, c.s0), b = min(o.offset + o.width / 2, c.s1)
            let lo = max(openingBase + o.sill, z0), hi = min(openingBase + o.sill + o.height, z1)
            guard b - a > 1e-9, hi - lo > 1e-9 else { continue }
            ops.append(Op(a: a, b: b, lo: lo, hi: hi, niche: o.isNiche ? o : nil))
        }
        var xs = [c.s0, c.s1] + ops.flatMap { [$0.a, $0.b] }
        xs = xs.map { min(max($0, c.s0), c.s1) }.sorted()
        var brk: [Double] = []
        for x in xs where brk.last.map({ x - $0 > 1e-7 }) ?? true { brk.append(x) }
        var parts: [CutPart] = []
        for i in 0..<max(brk.count - 1, 0) {
            let x0 = brk[i], x1 = brk[i + 1], xm = (x0 + x1) / 2
            let cover = ops.filter { $0.a <= xm && $0.b >= xm }
            var zs = [z0, z1] + cover.flatMap { [$0.lo, $0.hi] }
            zs = zs.map { min(max($0, z0), z1) }.sorted()
            var zb: [Double] = []
            for z in zs where zb.last.map({ z - $0 > 1e-7 }) ?? true { zb.append(z) }
            var bands: [Band] = []
            for k in 0..<max(zb.count - 1, 0) {
                let za = zb[k], zc = zb[k + 1], zm = (za + zc) / 2
                let here = cover.filter { $0.lo <= zm && $0.hi >= zm }
                let kind: BandKind
                if here.isEmpty { kind = .solid }
                else if here.contains(where: { $0.niche == nil }) { kind = .open }
                else {
                    let n = here.min { $0.niche!.depth < $1.niche!.depth }!.niche!
                    kind = .niche(depth: n.depth, fromLeft: n.flipFacing)
                }
                if var last = bands.last, last.kind == kind, abs(last.z1 - za) < 1e-7 { last.z1 = zc; bands[bands.count - 1] = last }
                else { bands.append(Band(z0: za, z1: zc, kind: kind)) }
            }
            if var last = parts.last, last.bands == bands, abs(last.s1 - x0) < 1e-7 { last.s1 = x1; parts[parts.count - 1] = last }
            else { parts.append(CutPart(s0: x0, s1: x1, bands: bands)) }
        }
        return parts
    }

    /// Wall attached to a sloped slab: the part of the wall between its lowest top and the slab soffit.
    static func slabTopInfill(_ f: WallFrame, wall: BIMElement, z1: Double, doc: ArchiDocument, into acc: inout MeshAcc) {
        guard !f.isCurved, f.L > 1e-9, let host = BIMConstraints.attached(wall, "attachTopTo", doc: doc), case .slab(let s) = host.geometry, s.isSloped else { return }
        guard let za = BIMConstraints.slabBottom(host, at: f.cs, doc: doc), let zc = BIMConstraints.slabBottom(host, at: f.ce, doc: doc) else { return }
        let a = max(za, z1), c = max(zc, z1)
        guard max(a, c) - z1 > 1e-6 else { return }
        var prof: [(x: Double, z: Double)] = [(0, z1), (f.L, z1)]
        if c - z1 > 1e-9 { prof.append((f.L, c)) }
        if a - z1 > 1e-9 { prof.append((0, a)) }
        guard prof.count >= 3 else { return }
        acc.verticalPlate(prof, origin: f.cs, ax: f.dir, ay: f.dir.perp, y0: -f.h, y1: f.h)
    }

    /// Gable/shed end infill: extends a perimeter wall under a sloped roof up to the roof underside
    /// (a triangle under gables, a rectangle or trapezoid under the high side of a shed roof).
    /// Walls with props["attachTop"] = "1" are attached wherever they stand under the roof; "0" disables it.
    static func roofInfill(_ f: WallFrame, wall: BIMElement, z1: Double, ctx: BIMContext, into acc: inout MeshAcc) {
        guard !f.isCurved, f.L > 1e-9, wall.props["attachTop"] != "0" else { return }
        let doc = ctx.doc
        let target = BIMConstraints.attached(wall, "attachTopTo", doc: doc)
        if let t = target, case .slab = t.geometry { return }
        let forced = wall.props["attachTop"] == "1" || target != nil
        let u = 1 / doc.units.mm
        for rel in doc.elements where doc.isVisible(layer: rel.layer) {
            if let t = target, rel.id != t.id { continue }
            guard case .roof(let rg) = rel.geometry, rg.kind != .flat, rg.pitch > 1e-6 else { continue }
            let zb = ctx.levelElevation(rel.level) + rg.baseOffset
            let r = RoofShapes.faces(rg)
            guard r.boundary.count >= 3, !r.faces.isEmpty else { continue }
            let tolZ = max(60 * u, 1e-6)
            if !forced && (z1 < zb - 400 * u || z1 > zb + tolZ) { continue }
            if forced && z1 > zb + 50_000 * u { continue }
            let ring = r.boundary + [r.boundary[0]]
            let near = f.h + max(20 * u, 1e-6)
            let samples = [f.cs, f.ce, (f.cs + f.ce) / 2]
            if forced {
                guard samples.allSatisfy({ GeometryOps.pointInPolygon($0, r.boundary) || GeometryOps.distance(from: $0, toPolyline: ring) <= near }) else { continue }
            } else {
                guard samples.allSatisfy({ GeometryOps.distance(from: $0, toPolyline: ring) <= near }) else { continue }
            }
            // Breakpoints where the centerline crosses face outlines (the underside is linear in between).
            var ss: [Double] = [0, f.L]
            for face in r.faces {
                let p = face.poly
                for i in 0..<p.count {
                    let a = p[i], b = p[(i + 1) % p.count]
                    if let x = GeometryOps.segmentIntersection(f.cs, f.ce, a, b) { ss.append((x - f.cs).dot(f.dir)) }
                }
            }
            ss = ss.map { min(max($0, 0), f.L) }.sorted()
            var uniq: [Double] = []
            for v in ss where uniq.last.map({ v - $0 > 1e-6 }) ?? true { uniq.append(v) }
            let fpTol = max(BBox2(points: r.footprint).width, 1) * 1e-6 + 1e-6
            func underside(_ q: Vec2) -> Double? {
                var best: Double? = nil
                for face in r.faces {
                    let inside = GeometryOps.pointInPolygon(q, face.poly) || GeometryOps.distance(from: q, toPolyline: face.poly + [face.poly[0]]) < fpTol * 10
                    if inside { let h = face.height(q); best = min(best ?? h, h) }
                }
                return best
            }
            var prof: [(x: Double, z: Double)] = []
            var any = false
            for sv in uniq {
                let h = underside(f.cs + f.dir * sv) ?? 0
                let z = max(zb + h, z1)
                if z - z1 > 1e-3 * max(u, 1e-9) { any = true }
                prof.append((sv, z))
            }
            guard any, prof.count >= 2 else { continue }
            // Polygon: base line at the wall top, then the underside profile back.
            var poly: [(x: Double, z: Double)] = [(prof[0].x, z1), (prof[prof.count - 1].x, z1)]
            for p in prof.reversed() { poly.append(p) }
            var clean: [(x: Double, z: Double)] = []
            for p in poly where !(clean.last.map { abs($0.x - p.x) < 1e-9 && abs($0.z - p.z) < 1e-9 } ?? false) { clean.append(p) }
            if let fst = clean.first, let lst = clean.last, abs(fst.x - lst.x) < 1e-9 && abs(fst.z - lst.z) < 1e-9 { clean.removeLast() }
            let area2 = (0..<clean.count).reduce(0.0) { s, i in let a = clean[i], b = clean[(i + 1) % clean.count]; return s + a.x * b.z - b.x * a.z }
            guard clean.count >= 3, abs(area2) > 1e-6 else { continue }
            acc.verticalPlate(clean, origin: f.cs, ax: f.dir, ay: f.dir.perp, y0: -f.h, y1: f.h)
            return
        }
    }

    /// Slab whose top follows an inclined plane (ramps, sloped floors); the soffit is parallel to the top.
    static func slopedSlab(_ g: SlabGeom, elev: Double, into acc: inout MeshAcc) {
        var outer = RG.dedupe(g.boundary, closed: true)
        guard outer.count >= 3, abs(GeometryOps.signedArea(outer)) > 1e-12 else { return }
        if GeometryOps.signedArea(outer) < 0 { outer.reverse() }
        var holes = g.holes.map { RG.dedupe($0, closed: true) }.filter { $0.count >= 3 && abs(GeometryOps.signedArea($0)) > 1e-12 }
        holes = holes.map { GeometryOps.signedArea($0) > 0 ? Array($0.reversed()) : $0 }
        let k = 1 / max(cos(g.slope * .pi / 180), 0.05)
        func zt(_ p: Vec2) -> Double { elev + g.topHeight(at: p) }
        func zbot(_ p: Vec2) -> Double { zt(p) - g.thickness * k }
        let (pts, tris) = Triangulator.triangulateWithPoints(outer, holes: holes)
        for t in tris {
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            let top = [Vec3(a.x, a.y, zt(a)), Vec3(b.x, b.y, zt(b)), Vec3(c.x, c.y, zt(c))]
            let bot = [Vec3(a.x, a.y, zbot(a)), Vec3(b.x, b.y, zbot(b)), Vec3(c.x, c.y, zbot(c))]
            acc.face(top, outward: .unitZ); acc.face(bot, outward: -.unitZ)
        }
        for loop in [outer] + holes {
            let n = loop.count
            for i in 0..<n {
                let a = loop[i], b = loop[(i + 1) % n]
                guard a.distance(to: b) > 1e-12 else { continue }
                let d = (b - a).normalized
                acc.face([Vec3(a.x, a.y, zbot(a)), Vec3(b.x, b.y, zbot(b)), Vec3(b.x, b.y, zt(b)), Vec3(a.x, a.y, zt(a))], outward: Vec3(d.y, -d.x, 0))
                acc.edges.append([Vec3(a.x, a.y, zt(a)), Vec3(b.x, b.y, zt(b))])
                acc.edges.append([Vec3(a.x, a.y, zbot(a)), Vec3(b.x, b.y, zbot(b))])
                acc.edges.append([Vec3(a.x, a.y, zbot(a)), Vec3(a.x, a.y, zt(a))])
            }
        }
    }

    /// Solid runs of a wall sweep along one face, interrupted by openings that cross its height band.
    static func wallSweep(_ sw: WallSweep, _ f: WallFrame, z0: Double, ctx: BIMContext, into acc: inout MeshAcc) {
        let side: Double = sw.side >= 0 ? 1 : -1
        let zLo = sw.elevation, zHi = sw.elevation + sw.height
        var runs: [(Double, Double)] = [(0, f.L)]
        for c in ctx.cuts(f) {
            var hits = false
            for oe in c.els { if case .opening(let o) = oe.geometry, o.sill < zHi, o.sill + o.height > zLo { if !(o.isNiche && o.flipFacing != (side > 0)) { hits = true } } }
            guard hits else { continue }
            var next: [(Double, Double)] = []
            for r in runs {
                if c.s1 <= r.0 || c.s0 >= r.1 { next.append(r); continue }
                if c.s0 > r.0 { next.append((r.0, c.s0)) }
                if c.s1 < r.1 { next.append((c.s1, r.1)) }
            }
            runs = next
        }
        let j = ctx.join(f)
        // Profile x = outward from the face; the frame's X axis points to the left of travel, so run right faces backwards.
        for r in runs where r.1 - r.0 > 1e-6 {
            var pts = f.face(side * f.h, r.0, r.1)
            if r.0 <= 1e-9 { pts[0] = side > 0 ? j.startL : j.startR }
            if r.1 >= f.L - 1e-9 { pts[pts.count - 1] = side > 0 ? j.endL : j.endR }
            if side < 0 { pts.reverse() }
            let path = pts.map { Vec3($0.x, $0.y, z0 + sw.elevation) }
            // Profile families of the document (PROFILE / FAMILY) flex to the sweep's depth × height; built-ins otherwise.
            var profile = sw.outline.map { Vec2($0.x, $0.z) }
            if !["rect", "cornice", "skirting", "baseboard", "cove"].contains(sw.profile.lowercased()),
               let p = ProfileLibrary.outline(sw.profile, width: max(sw.depth, 1e-6), height: max(sw.height, 1e-6), doc: ctx.doc) { profile = p }
            SweepMesh.sweep(profile, along: path, into: &acc)
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
            // Softened edges (M3D-101): smooth shading and hidden edges below the angle.
            if let a = props["softenAngle"].flatMap(Double.init), a > 0 { SoftEdges.apply(&acc, angle: a) }
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
            if s.meshTriangles.count <= 60_000 { acc.edges += MeshTools.featureEdges(vertices: v, triangles: s.meshTriangles, angle: 25) }
        }
    }
}
