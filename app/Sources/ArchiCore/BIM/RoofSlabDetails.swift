// Oanarina Archi Tool — GPL-3.0-or-later
// Layered floors and roofs (SlabType build-ups), shafts and hosted openings cutting slabs and roofs, skylights,
// and roof edges (fascia, gutter, soffit).
import Foundation

// MARK: - Shafts and hosted openings

/// Shafts are closed polylines (props shaft = 1) that cut every slab and roof whose level lies between shaftBase and
/// shaftTop (level ids; default: all levels), or only the element shaftHost. Skylights (components with
/// props kind = skylight, host = roof id) cut their host roof. Cuts are associative: moving the shaft moves the hole.
public enum Shafts {
    public static func isShaft(_ e: Entity) -> Bool { e.props["shaft"] == "1" }

    public static func loop(_ e: Entity) -> [Vec2]? {
        guard isShaft(e), let l = CommandHelpers.closedLoop(e.geometry) else { return nil }
        var p = RG.dedupe(CommandHelpers.loopPoints(l), closed: true)
        guard p.count >= 3, abs(GeometryOps.signedArea(p)) > 1e-9 else { return nil }
        if GeometryOps.signedArea(p) > 0 { p.reverse() }   // holes clockwise
        return p
    }

    /// Hole loops (clockwise) cutting a slab or roof element.
    public static func holes(for el: BIMElement, doc: ArchiDocument) -> [[Vec2]] {
        var out: [[Vec2]] = []
        let elev = doc.level(el.level)?.elevation ?? 0
        for e in doc.entities where isShaft(e) {
            guard let l = loop(e) else { continue }
            if let h = e.props["shaftHost"].flatMap(Int.init) { if h == el.id { out.append(l) }; continue }
            let lo = e.props["shaftBase"].flatMap(Int.init).flatMap { doc.level($0)?.elevation } ?? -Double.infinity
            let hi = e.props["shaftTop"].flatMap(Int.init).flatMap { doc.level($0)?.elevation } ?? Double.infinity
            if elev >= lo - 1e-6 && elev <= hi + 1e-6 { out.append(l) }
        }
        for s in doc.elements where s.props["kind"] == "skylight" && s.props["host"].flatMap(Int.init) == el.id {
            guard case .component(let g) = s.geometry else { continue }
            out.append(Array(PlanRepresentation.componentPoly(g).reversed()))
        }
        return out
    }

    /// Creates a shaft entity.
    @discardableResult
    public static func add(_ boundary: [Vec2], base: Int?, top: Int?, host: EntityID? = nil, doc: inout ArchiDocument) -> EntityID {
        if doc.layer(named: "A-SHAFT") == nil { doc.layers.append(Layer(name: "A-SHAFT", color: RGBA(0.9, 0.5, 0.2), lineweight: 0.35, description: "Shafts and slab/roof openings")) }
        let id = doc.add(.polyline(PolylineGeom(points: boundary, closed: true)), layer: "A-SHAFT")
        if let i = doc.entityIndex(id) {
            doc.entities[i].props["shaft"] = "1"
            if let b = base { doc.entities[i].props["shaftBase"] = "\(b)" }
            if let t = top { doc.entities[i].props["shaftTop"] = "\(t)" }
            if let h = host { doc.entities[i].props["shaftHost"] = "\(h)" }
        }
        return id
    }

    /// Plan symbol of a shaft: diagonals across the opening.
    static func crossItems(_ e: Entity, color: RGBA) -> [DrawItem] {
        guard var l = loop(e) else { return [] }
        l.reverse()
        let b = BBox2(points: l)
        let d1 = RG.clipSegment(b.min, b.max, [l]), d2 = RG.clipSegment(Vec2(b.min.x, b.max.y), Vec2(b.max.x, b.min.y), [l])
        return (d1 + d2).map { .stroke(points: [$0.0, $0.1], closed: false, style: StrokeStyle(color: color, lineweight: 0.18)) }
    }
}

// MARK: - Layered slabs

public enum SlabDetails {
    /// Ply bands (material, top depth, bottom depth below the slab top) of a slab, scaled to its thickness.
    public static func bands(_ el: BIMElement, thickness: Double, doc: ArchiDocument) -> [(material: String, top: Double, bottom: Double)] {
        let def = el.material ?? "Concrete"
        guard let t = doc.slabType(el.props["slabType"]), t.thickness > 0, thickness > 0 else { return [(def, 0, thickness)] }
        let k = thickness / t.thickness
        return t.bands().map { ($0.ply.material, -$0.top * k, -$0.bottom * k) }
    }

    static func groups(_ el: BIMElement, _ g: SlabGeom, elev: Double, doc: ArchiDocument) -> [MeshGroup] {
        let holes = g.holes + Shafts.holes(for: el, doc: doc)
        var byMat: [String: MeshAcc] = [:]
        var order: [String] = []
        for b in bands(el, thickness: g.thickness, doc: doc) where b.bottom - b.top > 1e-9 {
            var acc = byMat[b.material] ?? MeshAcc()
            if !order.contains(b.material) { order.append(b.material) }
            if g.isSloped {
                let k = 1 / max(cos(g.slope * .pi / 180), 0.05)
                var sg = g; sg.topOffset = g.topOffset - b.top * k; sg.thickness = b.bottom - b.top; sg.holes = holes
                MeshBuilder.slopedSlab(sg, elev: elev, into: &acc)
            } else {
                let top = elev + g.topOffset
                acc.prism(g.boundary, holes: holes, z0: top - b.bottom, z1: top - b.top)
            }
            byMat[b.material] = acc
        }
        return order.compactMap { byMat[$0]?.group(el.id, el.typeName, $0) }
    }
}

// MARK: - Roofs: layers, holes, edges, skylights

public enum RoofDetails {
    public struct EdgeSpec: Hashable {
        public var fasciaDepth: Double, fasciaThickness: Double, gutterSize: Double, gutterProfile: String, soffit: Bool
    }

    public static func edgeSpec(_ el: BIMElement, unit u: Double) -> EdgeSpec {
        func d(_ k: String) -> Double { el.props[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 0 }
        return EdgeSpec(fasciaDepth: max(d("fascia"), 0) * u, fasciaThickness: (d("fasciaThickness") > 0 ? d("fasciaThickness") : 25) * u,
                        gutterSize: max(d("gutter"), 0) * u, gutterProfile: el.props["gutterProfile"] ?? "gutter-half-round", soffit: el.props["soffit"] == "1")
    }

    /// Vertical ply bands of a roof (material, offset above the underside from/to), scaled to the roof thickness.
    static func bands(_ el: BIMElement, thickness tv: Double, doc: ArchiDocument) -> [(material: String, lo: Double, hi: Double)] {
        let def = el.material ?? "Roof Tiles"
        let tn = el.props["slabType"] ?? el.props["roofType"]
        guard let t = doc.slabType(tn), t.thickness > 0 else { return [(def, 0, tv)] }
        let k = tv / t.thickness
        return t.bands().map { ($0.ply.material, tv + $0.bottom * k, tv + $0.top * k) }
    }

    /// Eave edges of the overhang footprint: (a, b, underside height at the edge) for edges running level at the lowest point.
    static func eaveEdges(_ r: (boundary: [Vec2], footprint: [Vec2], faces: [RoofFace]), flat: Bool) -> [(Vec2, Vec2, Double)] {
        let fp = r.footprint
        guard fp.count >= 3 else { return [] }
        if flat { return (0..<fp.count).map { (fp[$0], fp[($0 + 1) % fp.count], 0) } }
        let tol = 1e-6 * max(1, BBox2(points: fp).width) * 10 + 1e-6
        var out: [(Vec2, Vec2, Double)] = []
        for f in r.faces where f.grad.length > 1e-12 {
            let hmin = f.poly.map { f.height($0) }.min() ?? 0
            for i in 0..<f.poly.count {
                let a = f.poly[i], b = f.poly[(i + 1) % f.poly.count]
                guard a.distance(to: b) > tol, RoofShapes.onOutline(a, b, fp, tol: tol) else { continue }
                let ha = f.height(a), hb = f.height(b)
                if abs(ha - hb) < 1e-6 * max(1, abs(ha)) + 1e-6, abs(ha - hmin) < 1e-6 * max(1, abs(ha)) + 1e-6 {
                    // Orient CCW along the footprint (outward = right side).
                    let m = (a + b) / 2
                    let d = (b - a).normalized
                    let inward = GeometryOps.pointInPolygon(m + d.perp * tol * 50, fp)
                    out.append(inward ? (a, b, ha) : (b, a, ha))
                }
            }
        }
        return out
    }

    /// A roof shell band (lo…hi above the underside, vertical) with holes; `sides` adds the eave/verge and hole faces.
    static func shell(_ r: (boundary: [Vec2], footprint: [Vec2], faces: [RoofFace]), zb: Double, lo: Double, hi: Double, holes: [[Vec2]], into acc: inout MeshAcc) {
        let tol = 1e-6 * max(1, BBox2(points: r.footprint).width) * 10 + 1e-6
        for f in r.faces {
            var poly = f.poly
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            let regions: [(outer: [Vec2], holes: [[Vec2]])]
            if holes.isEmpty { regions = [(poly, [])] }
            else {
                let loops = PolygonBoolean.apply(.subtract, [poly], holes)
                let outers = loops.filter { GeometryOps.signedArea($0) > 0 }
                let inner = loops.filter { GeometryOps.signedArea($0) < 0 }
                regions = outers.map { o in (o, inner.filter { h in GeometryOps.pointInPolygon(h[0], o) }) }
            }
            for reg in regions {
                let (pts, tris) = Triangulator.triangulateWithPoints(reg.outer, holes: reg.holes)
                func Z(_ p: Vec2, _ o: Double) -> Vec3 { Vec3(p.x, p.y, zb + f.height(p) + o) }
                for t in tris {
                    let a = pts[t.0], b = pts[t.1], c = pts[t.2]
                    acc.face([Z(a, hi), Z(b, hi), Z(c, hi)], outward: .unitZ)
                    acc.face([Z(a, lo), Z(b, lo), Z(c, lo)], outward: -.unitZ)
                }
                for loop in [reg.outer] + reg.holes {
                    acc.edges.append((loop + [loop[0]]).map { Z($0, hi) })
                    for i in 0..<loop.count {
                        let a = loop[i], b = loop[(i + 1) % loop.count]
                        guard a.distance(to: b) > tol else { continue }
                        let onFp = RoofShapes.onOutline(a, b, r.footprint, tol: tol)
                        let onHole = holes.contains { h in RoofShapes.onOutline(a, b, h, tol: tol) }
                        guard onFp || onHole else { continue }
                        var d = (b - a).normalized
                        // Outward: away from the face region.
                        let m = (a + b) / 2
                        if GeometryOps.pointInPolygon(m + Vec2(d.y, -d.x) * tol * 50, reg.outer) && !reg.holes.contains(where: { GeometryOps.pointInPolygon(m + Vec2(d.y, -d.x) * tol * 50, $0) }) { d = -d }
                        acc.face([Z(a, lo), Z(b, lo), Z(b, hi), Z(a, hi)], outward: Vec3(d.y, -d.x, 0))
                        acc.edges.append([Z(a, lo), Z(b, lo)])
                    }
                }
            }
        }
    }

    static func groups(_ el: BIMElement, _ g: RoofGeom, elev: Double, doc: ArchiDocument) -> [MeshGroup] {
        let holes = Shafts.holes(for: el, doc: doc)
        let hasType = doc.slabType(el.props["slabType"] ?? el.props["roofType"]) != nil
        let edges = edgeSpec(el, unit: 1 / doc.units.mm)
        let plain = !hasType && holes.isEmpty && edges.fasciaDepth <= 0 && edges.gutterSize <= 0 && !edges.soffit
        if plain { return MeshBuilder.roofGroups(el, g, elev: elev).compactMap { $0 } }
        let r = RoofShapes.faces(g)
        guard r.footprint.count >= 3 else { return [] }
        let zb = elev + g.baseOffset
        let flat = g.kind == .flat || r.faces.allSatisfy { $0.grad.length < 1e-12 }
        let tv = flat ? max(g.thickness, 1e-3) : g.thickness / max(cos(rad(min(g.pitch, 85))), 0.05)
        var byMat: [String: MeshAcc] = [:], order: [String] = []
        for b in bands(el, thickness: tv, doc: doc) where b.hi - b.lo > 1e-9 {
            var acc = byMat[b.material] ?? MeshAcc()
            if !order.contains(b.material) { order.append(b.material) }
            if flat { acc.prism(r.footprint, holes: holes, z0: zb + b.lo, z1: zb + b.hi) }
            else { shell(r, zb: zb, lo: b.lo, hi: b.hi, holes: holes, into: &acc) }
            byMat[b.material] = acc
        }
        var out = order.compactMap { byMat[$0]?.group(el.id, el.typeName, $0) }
        out += edgeGroups(el, r, zb: zb, tv: tv, flat: flat, spec: edges, overhang: g.overhang)
        return out
    }

    /// Fascia boards, gutters and soffits along the eaves.
    static func edgeGroups(_ el: BIMElement, _ r: (boundary: [Vec2], footprint: [Vec2], faces: [RoofFace]), zb: Double, tv: Double, flat: Bool,
                           spec: EdgeSpec, overhang: Double) -> [MeshGroup] {
        guard spec.fasciaDepth > 0 || spec.gutterSize > 0 || spec.soffit else { return [] }
        var fascia = MeshAcc(), gutter = MeshAcc(), soffit = MeshAcc()
        let eaves = eaveEdges(r, flat: flat)
        for (a, b, h) in eaves {
            let d = (b - a).normalized, out = Vec2(d.y, -d.x)
            let top = zb + h + tv
            if spec.fasciaDepth > 0 {
                let t = spec.fasciaThickness
                fascia.prism([a, b, b + out * t, a + out * t], z0: top - max(spec.fasciaDepth, tv), z1: top)
            }
            if spec.gutterSize > 0, let prof = ProfileLibrary.builtin(spec.gutterProfile, width: spec.gutterSize, height: spec.gutterSize * 0.75) {
                let c = GeometryOps.centroid(prof)
                let maxY = prof.map(\.y).max() ?? 0
                // Profile x runs to the left of travel (inward): place the gutter outside the fascia.
                let off = (spec.fasciaDepth > 0 ? spec.fasciaThickness : 0) + spec.gutterSize / 2
                let local = prof.map { Vec2(-($0.x - c.x), $0.y - maxY) }
                let z = top - spec.gutterSize * 0.1
                let path = [Vec3(a.x + out.x * off, a.y + out.y * off, z), Vec3(b.x + out.x * off, b.y + out.y * off, z)]
                SweepMesh.sweep(local, along: path, into: &gutter)
            }
        }
        if spec.soffit && overhang > 1e-9 {
            // Horizontal soffit board under the overhang, at the underside height of the eave.
            let hmin = eaves.map { $0.2 }.min() ?? 0
            let ring = RG.dedupe(r.boundary, closed: true)
            if ring.count >= 3 {
                let hole = GeometryOps.signedArea(ring) > 0 ? Array(ring.reversed()) : ring
                soffit.prism(r.footprint, holes: [hole], z0: zb + hmin - 18, z1: zb + hmin)
            }
        }
        return [fascia.group(el.id, "fascia", el.props["fasciaMaterial"] ?? "Wood"), gutter.group(el.id, "gutter", el.props["gutterMaterial"] ?? "Aluminium"),
                soffit.group(el.id, "soffit", el.props["soffitMaterial"] ?? "Wood")].compactMap { $0 }
    }

    // MARK: Skylights

    /// Roof face under a plan point: (roof element, face, absolute underside z, vertical roof thickness).
    public static func face(at p: Vec2, roof el: BIMElement, doc: ArchiDocument) -> (grad: Vec2, zUnder: Double, tv: Double)? {
        guard case .roof(let g) = el.geometry else { return nil }
        let r = RoofShapes.faces(g)
        let flat = g.kind == .flat || r.faces.allSatisfy { $0.grad.length < 1e-12 }
        let zb = (doc.level(el.level)?.elevation ?? 0) + g.baseOffset
        let tv = flat ? g.thickness : g.thickness / max(cos(rad(min(g.pitch, 85))), 0.05)
        guard let f = r.faces.first(where: { GeometryOps.pointInPolygon(p, $0.poly) }) else { return nil }
        return (f.grad, zb + f.height(p), tv)
    }

    static func skylightGroups(_ el: BIMElement, _ g: ComponentGeom, doc: ArchiDocument) -> [MeshGroup] {
        guard let hid = el.props["host"].flatMap(Int.init), let host = doc.element(hid), let fc = face(at: g.position, roof: host, doc: doc) else { return [] }
        let u = 1 / doc.units.mm
        let slope = atan(fc.grad.length) * 180 / .pi
        let dir = fc.grad.length > 1e-12 ? fc.grad.angle : 0
        let elev = doc.level(el.level)?.elevation ?? 0
        let outer = PlanRepresentation.componentPoly(g)
        let fw = min(80 * u, min(g.size.x, g.size.y) / 4)
        let inner = RG.offsetPolygon(GeometryOps.signedArea(outer) > 0 ? outer : outer.reversed(), -fw)
        let cosS = cos(slope * .pi / 180)
        let curb = 120 * u
        let topAt = fc.zUnder + fc.tv + curb - elev
        var frame = MeshAcc(), glass = MeshAcc()
        let fg = SlabGeom(boundary: outer, holes: [inner.reversed()], thickness: (fc.tv + curb) * cosS, topOffset: topAt, slope: slope, slopeDirection: dir, slopeOrigin: g.position)
        MeshBuilder.slopedSlab(fg, elev: elev, into: &frame)
        let gg = SlabGeom(boundary: inner, thickness: 12 * u * cosS, topOffset: topAt - 20 * u, slope: slope, slopeDirection: dir, slopeOrigin: g.position)
        MeshBuilder.slopedSlab(gg, elev: elev, into: &glass)
        return [frame.group(el.id, "skylight", el.material ?? "Aluminium"), glass.group(el.id, "skylight", "Glass")].compactMap { $0 }
    }

    static func skylightPlan(_ g: ComponentGeom, color: RGBA, unit u: Double) -> [DrawItem] {
        let o = PlanRepresentation.componentPoly(g)
        let fw = min(80 * u, min(g.size.x, g.size.y) / 4)
        let i = RG.offsetPolygon(GeometryOps.signedArea(o) > 0 ? o : o.reversed(), -fw)
        var out: [DrawItem] = [PlanRepresentation.stroke(o, closed: true, color, PlanRepresentation.lwProj)]
        if i.count == 4 {
            out.append(PlanRepresentation.stroke(i, closed: true, color, PlanRepresentation.lwFine))
            out.append(PlanRepresentation.stroke([i[0], i[2]], color, PlanRepresentation.lwFine))
        }
        return out
    }
}
