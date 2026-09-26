// Oanarina Archi Tool — GPL-3.0-or-later
// Reinforcement (BIM-085) and steel connections (BIM-087). Rebar sets are generated inside concrete beams, columns and
// slabs from cover / diameter / count / spacing with BS 8666 shape codes (00 straight, 11 L-bar, 51 closed link);
// connections are base, cap and end plates with bolts sized from the member's section. Both are BIM component
// elements (schedulable, IFC-exportable as in-place geometry) that regenerate when their host member changes.
import Foundation

public enum Rebar {
    public static let category = "Structural Rebar"
    public static let steelDensity = 7.85e-6   // kg / mm³

    /// One bar: centreline and whether it is a closed link.
    public struct Bar { public var path: [Vec3]; public var closed: Bool }

    public struct Params {
        public var set: String            // bottom, top, links (beams); vertical, links (columns); x, y (slabs)
        public var diameter: Double
        public var cover: Double
        public var count: Int             // bars in the set (bottom / top / vertical)
        public var spacing: Double        // links and slab bars
        public var linkDiameter: Double
        public var hook: Double           // leg length of L-bars (shape 11); 0 = straight
        public init(set: String, diameter: Double, cover: Double = 30, count: Int = 3, spacing: Double = 200, linkDiameter: Double = 8, hook: Double = 0) {
            self.set = set; self.diameter = diameter; self.cover = cover; self.count = count; self.spacing = spacing; self.linkDiameter = linkDiameter; self.hook = hook
        }
        public var props: [String: String] {
            ["rebarSet": set, "barDiameter": fmt(diameter), "cover": fmt(cover), "barCount": "\(count)", "spacing": fmt(spacing), "linkDiameter": fmt(linkDiameter), "hook": fmt(hook)]
        }
        public init?(_ p: [String: String]) {
            guard let s = p["rebarSet"], let d = p["barDiameter"].flatMap(Double.init) else { return nil }
            self.init(set: s, diameter: d, cover: p["cover"].flatMap(Double.init) ?? 30, count: p["barCount"].flatMap(Int.init) ?? 3,
                      spacing: p["spacing"].flatMap(Double.init) ?? 200, linkDiameter: p["linkDiameter"].flatMap(Double.init) ?? 8, hook: p["hook"].flatMap(Double.init) ?? 0)
        }
        public var shapeCode: String { self.set == "links" ? "51" : (hook > 0 ? "11" : "00") }
    }

    /// Rounded closed rectangle (link centreline) in a local (u, v) frame, corner bend radius r.
    static func linkLoop(_ hu: Double, _ hv: Double, r: Double) -> [Vec2] {
        let r = min(r, hu * 0.9, hv * 0.9)
        var out: [Vec2] = []
        let corners = [(Vec2(hu - r, hv - r), 0.0), (Vec2(-hu + r, hv - r), Double.pi / 2), (Vec2(-hu + r, -hv + r), Double.pi), (Vec2(hu - r, -hv + r), 1.5 * Double.pi)]
        for (c, a0) in corners { for k in 0...4 { out.append(c + Vec2.polar(r, a0 + Double.pi / 2 * Double(k) / 4)) } }
        return out
    }

    static func distribute(_ n: Int, _ lo: Double, _ hi: Double) -> [Double] {
        guard n > 1 else { return [(lo + hi) / 2] }
        return (0..<n).map { lo + (hi - lo) * Double($0) / Double(n - 1) }
    }

    /// Bars of a set in a host member (world coordinates); nil when the host cannot take the set.
    public static func bars(host el: BIMElement, _ p: Params, doc: ArchiDocument) -> [Bar]? {
        let elev = doc.level(el.level)?.elevation ?? 0
        let c = p.cover, d = p.diameter, ds = p.linkDiameter
        switch el.geometry {
        case .beam(let g):
            let L = g.start.distance(to: g.end)
            guard L > 2 * c, !g.isSloped else { return nil }
            let sec = StructuralProfiles.section(g.profile)
            let w = sec.map { $0.b / doc.units.mm } ?? g.width, h = sec.map { $0.h / doc.units.mm } ?? g.depth
            let dir = (g.end - g.start) / L, n = dir.perp
            let top = elev + g.topOffset, bot = top - h
            func P(_ x: Double, _ y: Double, _ z: Double) -> Vec3 { let q = g.start + dir * x + n * y; return Vec3(q.x, q.y, z) }
            let hy = w / 2 - c - ds - d / 2
            guard hy > 0, h > 2 * (c + ds + d) else { return nil }
            switch p.set {
            case "bottom", "top":
                let z = p.set == "bottom" ? bot + c + ds + d / 2 : top - c - ds - d / 2
                let zh = p.set == "bottom" ? z + p.hook : z - p.hook
                return distribute(max(p.count, 2), -hy, hy).map { y in
                    var path = [P(c, y, z), P(L - c, y, z)]
                    if p.hook > 0 { path = [P(c, y, zh)] + path + [P(L - c, y, zh)] }
                    return Bar(path: path, closed: false)
                }
            case "links":
                let hu = w / 2 - c - ds / 2, hv = h / 2 - c - ds / 2
                guard hu > 0, hv > 0, p.spacing > 0 else { return nil }
                let loop = linkLoop(hu, hv, r: 2 * ds)
                let zc = (top + bot) / 2
                var out: [Bar] = []
                var x = c + ds / 2
                while x <= L - c - ds / 2 + 1e-9 { out.append(Bar(path: loop.map { P(x, $0.x, zc + $0.y) }, closed: true)); x += p.spacing }
                return out
            default: return nil
            }
        case .column(let g):
            guard StructuralProfiles.section(g.profile) == nil else { return nil }
            let z0 = elev + g.baseOffset, z1 = z0 + g.height
            let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
            switch p.set {
            case "vertical":
                var pts: [Vec2] = []
                if g.round {
                    let r = g.width / 2 - c - ds - d / 2
                    guard r > 0 else { return nil }
                    let n = max(p.count, 4)
                    pts = (0..<n).map { Vec2.polar(r, 2 * .pi * Double($0) / Double(n)) }
                } else {
                    let hx = g.width / 2 - c - ds - d / 2, hy = g.depth / 2 - c - ds - d / 2
                    guard hx > 0, hy > 0 else { return nil }
                    // Corner bars plus (count − 4) spread over the long faces.
                    pts = [Vec2(-hx, -hy), Vec2(hx, -hy), Vec2(hx, hy), Vec2(-hx, hy)]
                    let extra = max(p.count, 4) - 4
                    let perFace = extra / 2
                    for x in distribute(perFace + 2, -hx, hx).dropFirst().dropLast() { pts += [Vec2(x, -hy), Vec2(x, hy)] }
                    if extra % 2 == 1 { pts.append(Vec2(-hx, 0)) }
                }
                return pts.map { q in let w = t.apply(q); return Bar(path: [Vec3(w.x, w.y, z0 + c), Vec3(w.x, w.y, z1 - c)], closed: false) }
            case "links":
                guard p.spacing > 0 else { return nil }
                var loop: [Vec2]
                if g.round {
                    let r = g.width / 2 - c - ds / 2
                    guard r > 0 else { return nil }
                    loop = RG.circle(.zero, r, segments: 24)
                } else {
                    let hu = g.width / 2 - c - ds / 2, hv = g.depth / 2 - c - ds / 2
                    guard hu > 0, hv > 0 else { return nil }
                    loop = linkLoop(hu, hv, r: 2 * ds)
                }
                let wl = loop.map(t.apply)
                var out: [Bar] = []
                var z = z0 + c + ds / 2
                while z <= z1 - c - ds / 2 + 1e-9 { out.append(Bar(path: wl.map { Vec3($0.x, $0.y, z) }, closed: true)); z += p.spacing }
                return out
            default: return nil
            }
        case .slab(let g):
            guard abs(g.slope) < 1e-9, p.spacing > 0, g.boundary.count >= 3 else { return nil }
            let top = elev + g.topOffset, bot = top - g.thickness
            var poly = g.boundary
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            poly = CommandHelpers.offsetPolygon(poly, -c)
            guard poly.count >= 3, GeometryOps.signedArea(poly) > 0 else { return nil }
            let holes = g.holes.map { h -> [Vec2] in var q = h; if GeometryOps.signedArea(q) < 0 { q.reverse() }; return CommandHelpers.offsetPolygon(q, c) }
            let alongX = p.set == "x"
            let z = bot + c + d / 2 + (alongX ? 0 : d)
            guard z + d / 2 < top - c + 1e-9 else { return nil }
            let b = BBox2(points: poly)
            // Scanlines across the boundary (bars run along x for set "x").
            var out: [Bar] = []
            var s = (alongX ? b.min.y : b.min.x) + p.spacing / 2
            let sMax = alongX ? b.max.y : b.max.x
            while s < sMax {
                var xs: [Double] = []
                for loop in [poly] + holes {
                    for i in 0..<loop.count {
                        let a = loop[i], e = loop[(i + 1) % loop.count]
                        let (a1, a2, e1, e2) = alongX ? (a.y, a.x, e.y, e.x) : (a.x, a.y, e.x, e.y)
                        if (a1 <= s && e1 > s) || (e1 <= s && a1 > s) { xs.append(a2 + (s - a1) / (e1 - a1) * (e2 - a2)) }
                    }
                }
                xs.sort()
                var k = 0
                while k + 1 < xs.count {
                    let x0 = xs[k], x1 = xs[k + 1]
                    if x1 - x0 > 2 * d {
                        out.append(Bar(path: alongX ? [Vec3(x0, s, z), Vec3(x1, s, z)] : [Vec3(s, x0, z), Vec3(s, x1, z)], closed: false))
                    }
                    k += 2
                }
                s += p.spacing
            }
            return out.isEmpty ? nil : out
        default: return nil
        }
    }

    static func length(_ b: Bar) -> Double {
        var l = zip(b.path, b.path.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
        if b.closed, let f = b.path.first, let e = b.path.last { l += e.distance(to: f) }
        return l
    }

    /// Triangles of the bars swept with a round section.
    static func triangles(_ bars: [Bar], diameter d: Double) -> [Tri3] {
        var acc = MeshAcc()
        let prof = RG.circle(.zero, d / 2, segments: 8)
        for b in bars { SweepMesh.sweep(prof, along: b.path, closedPath: b.closed, into: &acc) }
        return MeshTools.triangles(acc.mesh)
    }

    /// Schedule values of a set: bar count, cutting length of one bar (the longest), total length and weight (kg).
    public static func quantities(_ bars: [Bar], diameter d: Double, units: Units) -> (count: Int, barLength: Double, total: Double, weight: Double) {
        let ls = bars.map(length)
        let total = ls.reduce(0, +)
        let mm = units.mm
        let w = total * mm * Double.pi * pow(d * mm, 2) / 4 * steelDensity
        return (bars.count, ls.max() ?? 0, total, w)
    }

    /// Component geometry and schedule props of a set in a host.
    static func build(host: BIMElement, _ p: Params, doc: ArchiDocument) -> (ComponentGeom, [String: String])? {
        guard let bars = bars(host: host, p, doc: doc), !bars.isEmpty else { return nil }
        let tris = triangles(bars, diameter: p.diameter)
        let elev = doc.level(host.level)?.elevation ?? 0
        guard !tris.isEmpty, let g = InPlaceModels.component(from: [MeshTools.solid(from: tris, tolerance: 1e-9)], category: category, levelElevation: elev) else { return nil }
        let q = quantities(bars, diameter: p.diameter, units: doc.units)
        var props = p.props
        props["shapeCode"] = p.shapeCode; props["barCount"] = "\(q.count)"
        props["barLength"] = fmt(q.barLength, 1); props["totalLength"] = fmt(q.total, 1); props["weightKg"] = fmt(q.weight, 2)
        props["rebarHost"] = "\(host.id)"; props["hostSig"] = signature(host)
        return (g, props)
    }

    static func signature(_ host: BIMElement) -> String { "\(host.level)|\(host.geometry)" }

    /// Adds a rebar set to a host member. Returns the element id.
    @discardableResult
    public static func add(host id: EntityID, _ p: Params, doc: inout ArchiDocument) -> EntityID? {
        guard let host = doc.element(id), let (g, props) = build(host: host, p, doc: doc) else { return nil }
        let n = doc.elements.filter { $0.props["rebarHost"] != nil }.count + 1
        let eid = doc.addElement(.component(g), level: host.level, material: "Reinforcement Steel", name: "\(p.shapeCode) Ø\(fmt(p.diameter)) × \(props["barCount"] ?? "")")
        if doc.material("Reinforcement Steel") == nil { doc.materials.append(Material(name: "Reinforcement Steel", color: RGBA(0.45, 0.3, 0.25), roughness: 0.6, metalness: 0.8, cutPattern: "SOLID")) }
        if let i = doc.elementIndex(eid) {
            for (k, v) in props { doc.elements[i].props[k] = v }
            doc.elements[i].props["mark"] = String(format: "R%02d", n)
        }
        return eid
    }
}

public enum SteelConnections {
    public static let category = "Structural Connections"
    public enum Kind: String, CaseIterable { case basePlate, capPlate, endPlate }

    public struct Params {
        public var kind: Kind
        public var thickness: Double
        public var edge: Double          // plate projection beyond the section
        public var boltDiameter: Double
        public var atEnd: Bool           // end plates: at the beam end (else the start)
        public init(kind: Kind, thickness: Double = 20, edge: Double = 60, boltDiameter: Double = 20, atEnd: Bool = true) {
            self.kind = kind; self.thickness = thickness; self.edge = edge; self.boltDiameter = boltDiameter; self.atEnd = atEnd
        }
        public var props: [String: String] {
            ["connection": kind.rawValue, "plateThickness": fmt(thickness), "plateEdge": fmt(edge), "boltDiameter": fmt(boltDiameter), "connectionEnd": atEnd ? "end" : "start"]
        }
        public init?(_ p: [String: String]) {
            guard let k = p["connection"].flatMap(Kind.init) else { return nil }
            self.init(kind: k, thickness: p["plateThickness"].flatMap(Double.init) ?? 20, edge: p["plateEdge"].flatMap(Double.init) ?? 60,
                      boltDiameter: p["boltDiameter"].flatMap(Double.init) ?? 20, atEnd: p["connectionEnd"] != "start")
        }
    }

    /// Plate size, bolt positions (plate-local) and triangles of a connection on a host.
    public static func geometry(host el: BIMElement, _ p: Params, doc: ArchiDocument) -> (tris: [Tri3], plate: (w: Double, h: Double), bolts: Int)? {
        let elev = doc.level(el.level)?.elevation ?? 0
        let mm = doc.units.mm
        var acc = MeshAcc()
        let t = p.thickness, e = p.edge, bd = p.boltDiameter
        let boltRing = RG.circle(.zero, bd / 2, segments: 12)
        switch (el.geometry, p.kind) {
        case (.column(let g), .basePlate), (.column(let g), .capPlate):
            let sec = StructuralProfiles.section(g.profile)
            let sw = sec.map { $0.b / mm } ?? g.width, sd = sec.map { $0.h / mm } ?? (g.round ? g.width : g.depth)
            let pw = sw + 2 * e, ph = sd + 2 * e
            let tr = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
            let rect = [Vec2(-pw / 2, -ph / 2), Vec2(pw / 2, -ph / 2), Vec2(pw / 2, ph / 2), Vec2(-pw / 2, ph / 2)].map(tr.apply)
            let base = elev + g.baseOffset, topZ = base + g.height
            let z0 = p.kind == .basePlate ? base - t : topZ, z1 = z0 + t
            acc.prism(rect, z0: z0, z1: z1)
            // Four bolts inset from the plate corners (anchor bolts below a base plate, through bolts on a cap).
            let inset = min(e / 2 + bd / 2, pw / 4, ph / 4)
            let bolts = [Vec2(-pw / 2 + inset, -ph / 2 + inset), Vec2(pw / 2 - inset, -ph / 2 + inset), Vec2(pw / 2 - inset, ph / 2 - inset), Vec2(-pw / 2 + inset, ph / 2 - inset)]
            for b in bolts {
                let c = tr.apply(b)
                let (za, zb) = p.kind == .basePlate ? (z0 - 15 * bd, z1 + 1.5 * bd) : (z0 - 1.5 * bd, z1 + 1.5 * bd)
                acc.prism(boltRing.map { $0 + c }, z0: za, z1: zb, smooth: true)
                // Nut and washer.
                acc.prism(RG.circle(c, bd, segments: 6), z0: z1, z1: z1 + 0.8 * bd)
            }
            return (MeshTools.triangles(acc.mesh), (pw, ph), bolts.count)
        case (.beam(let g), .endPlate):
            let L = g.start.distance(to: g.end)
            guard L > 1e-9 else { return nil }
            let sec = StructuralProfiles.section(g.profile)
            let bw = sec.map { $0.b / mm } ?? g.width, bh = sec.map { $0.h / mm } ?? g.depth
            let dir = (g.end - g.start) / L
            let endPt = p.atEnd ? g.end : g.start, outward = p.atEnd ? dir : -dir
            let topZ = elev + (p.atEnd ? g.endTop : g.topOffset)
            let pw = bw + 20, ph = bh + 2 * e
            let zc = topZ - bh / 2
            // The plate sits against the member end, outside it.
            let a = Vec3(endPt.x, endPt.y, zc), b = a + Vec3(outward.x, outward.y, 0) * t
            acc.member([Vec2(-pw / 2, -ph / 2), Vec2(pw / 2, -ph / 2), Vec2(pw / 2, ph / 2), Vec2(-pw / 2, ph / 2)], from: a, to: b)
            let rows = max(2, Int(((ph - 2 * e) / (3 * bd)).rounded(.down)) + 1)
            let zs = distribute(rows, -ph / 2 + e / 2 + bd, ph / 2 - e / 2 - bd)
            let side = Vec3(-outward.y, outward.x, 0), gauge = min(pw / 2 - bd, max(bw / 2 - bd, 2 * bd))
            var n = 0
            for z in zs {
                for s in [-gauge, gauge] {
                    let c = a + side * s + Vec3(0, 0, z)
                    acc.member(boltRing, from: c - Vec3(outward.x, outward.y, 0) * (1.5 * bd), to: c + Vec3(outward.x, outward.y, 0) * (t + 1.5 * bd), smooth: true)
                    n += 1
                }
            }
            return (MeshTools.triangles(acc.mesh), (pw, ph), n)
        default: return nil
        }
    }

    static func distribute(_ n: Int, _ lo: Double, _ hi: Double) -> [Double] { Rebar.distribute(n, lo, hi) }

    static func build(host: BIMElement, _ p: Params, doc: ArchiDocument) -> (ComponentGeom, [String: String])? {
        guard let r = geometry(host: host, p, doc: doc), !r.tris.isEmpty else { return nil }
        let elev = doc.level(host.level)?.elevation ?? 0
        guard let g = InPlaceModels.component(from: [MeshTools.solid(from: r.tris, tolerance: 1e-9)], category: category, levelElevation: elev) else { return nil }
        var props = p.props
        props["plateWidth"] = fmt(r.plate.w, 1); props["plateHeight"] = fmt(r.plate.h, 1); props["boltCount"] = "\(r.bolts)"
        props["connHost"] = "\(host.id)"; props["hostSig"] = Rebar.signature(host)
        props["plateWeightKg"] = fmt(r.plate.w * r.plate.h * p.thickness * pow(doc.units.mm, 3) * Rebar.steelDensity, 2)
        return (g, props)
    }

    @discardableResult
    public static func add(host id: EntityID, _ p: Params, doc: inout ArchiDocument) -> EntityID? {
        guard let host = doc.element(id), let (g, props) = build(host: host, p, doc: doc) else { return nil }
        let names: [Kind: String] = [.basePlate: "Base plate", .capPlate: "Cap plate", .endPlate: "End plate"]
        let eid = doc.addElement(.component(g), level: host.level, material: "Steel", name: "\(names[p.kind]!) \(fmt(props["plateWidth"].flatMap(Double.init) ?? 0, 0))×\(fmt(props["plateHeight"].flatMap(Double.init) ?? 0, 0))×\(fmt(p.thickness))")
        if let i = doc.elementIndex(eid) { for (k, v) in props { doc.elements[i].props[k] = v } }
        return eid
    }
}

/// Keeps rebar sets and connections in step with their host members (deleted with them, rebuilt when they change).
public enum StructuralDetails {
    public static func hasContent(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props["rebarHost"] != nil || $0.props["connHost"] != nil } }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        var remove = Set<EntityID>()
        for i in doc.elements.indices {
            let el = doc.elements[i]
            guard let hs = el.props["rebarHost"] ?? el.props["connHost"], let hid = Int(hs) else { continue }
            guard let host = doc.element(hid) else { remove.insert(el.id); continue }
            if el.props["hostSig"] == Rebar.signature(host) { continue }
            let built: (ComponentGeom, [String: String])?
            if el.props["rebarHost"] != nil, let p = Rebar.Params(el.props) { built = Rebar.build(host: host, p, doc: doc) }
            else if let p = SteelConnections.Params(el.props) { built = SteelConnections.build(host: host, p, doc: doc) }
            else { built = nil }
            guard let (g, props) = built else { remove.insert(el.id); continue }
            doc.elements[i].geometry = .component(g)
            doc.elements[i].level = host.level
            for (k, v) in props { doc.elements[i].props[k] = v }
            changed = true
        }
        if !remove.isEmpty { doc.elements.removeAll { remove.contains($0.id) }; changed = true }
        return changed
    }
}
