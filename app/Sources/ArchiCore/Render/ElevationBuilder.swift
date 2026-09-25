// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Orthographic elevations and sections from the 3D model, with painter's-algorithm hidden-line removal.
/// Output coordinates: x along the view (left → right as seen by the viewer), y = height (Z).
public enum ElevationBuilder {
    struct Projection {
        var viewDir: Vec3
        var xf: (Vec3) -> Double
        var depthf: (Vec3) -> Double
        /// Vertical drawing axis (default: Z).
        var yf: ((Vec3) -> Double)? = nil
        func xy(_ p: Vec3) -> Vec2 { Vec2(xf(p), yf?(p) ?? p.z) }
        func depth(_ p: Vec3) -> Double { depthf(p) }
    }

    static func projection(_ view: ViewKind, section: (Vec2, Vec2)?) -> Projection? {
        switch view {
        case .elevationNorth: return Projection(viewDir: Vec3(0, -1, 0), xf: { -$0.x }, depthf: { -$0.y })
        case .elevationSouth: return Projection(viewDir: Vec3(0, 1, 0), xf: { $0.x }, depthf: { $0.y })
        case .elevationEast: return Projection(viewDir: Vec3(-1, 0, 0), xf: { $0.y }, depthf: { -$0.x })
        case .elevationWest: return Projection(viewDir: Vec3(1, 0, 0), xf: { -$0.y }, depthf: { $0.x })
        case .section:
            guard let (a, b) = section, a.distance(to: b) > 1e-9 else { return nil }
            let u = (b - a).normalized, f = u.perp
            return Projection(viewDir: Vec3(f.x, f.y, 0), xf: { ($0.xy - a).dot(u) }, depthf: { ($0.xy - a).dot(f) })
        default: return nil
        }
    }

    enum Prim { case face([Vec2], RGBA), edge([Vec2]) }

    static let edgeColor = RGBA(0.08, 0.08, 0.08)
    static let pocheColor = RGBA(0.2, 0.2, 0.2)

    public static func entries(doc: ArchiDocument, view: ViewKind, sectionLine: (Vec2, Vec2)? = nil) -> [DrawEntry] {
        if view == .plan { return DrawListBuilder.entries(doc: doc, options: DrawOptions(level: nil)) }
        if view == .ceiling { var o = DrawOptions(level: doc.currentLevel); o.reflectedCeiling = true; return DrawListBuilder.entries(doc: doc, options: o) }
        let groups = MeshBuilder.build(doc: doc)
        var line = sectionLine
        if view == .section, let m = Annotations.sectionLine(doc) { line = m }
        if view == .section && line == nil {
            var b = BBox3.empty
            for g in groups { b = union(b, g.mesh.bounds) }
            guard !b.isEmpty else { return [] }
            let cy = (b.min.y + b.max.y) / 2
            line = (Vec2(b.min.x - 1, cy), Vec2(b.max.x + 1, cy))
        }
        guard let proj = projection(view, section: line) else { return [] }
        return entries(groups: groups, doc: doc, proj: proj, cut: view == .section)
    }

    static func union(_ a: BBox3, _ b: BBox3) -> BBox3 {
        if b.isEmpty { return a }
        var r = a; r.add(b.min); r.add(b.max); return r
    }

    static func entries(groups: [MeshGroup], doc: ArchiDocument, proj: Proj, cut: Bool) -> [DrawEntry] {
        var box = BBox2.empty
        var dmin = Double.infinity, dmax = -Double.infinity
        for g in groups { for p in g.mesh.positions { box.add(proj.xy(p)); let d = proj.depth(p); dmin = min(dmin, d); dmax = max(dmax, d) } }
        guard !box.isEmpty else { return [] }
        let size = max(box.width, box.height, dmax - dmin, 1e-6)
        let bias = size * 1e-4
        let splitLen = size / 40
        let light = (Vec3(0, 0, 1) * 0.6 - proj.viewDir + Vec3(0.3, 0.2, 0)).normalized

        var prims: [(key: Double, id: EntityID?, prim: Prim)] = []
        var poche: [DrawEntry] = []
        for g in groups {
            let mat = doc.material(g.material)
            let base = mat?.color ?? RGBA(0.8, 0.8, 0.8)
            let isGlass = (mat?.transparency ?? 0) > 0.3
            let m = g.mesh
            var i = 0
            while i + 2 < m.indices.count {
                let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
                i += 3
                let n = (b - a).cross(c - a)
                guard n.length > 1e-12 else { continue }
                let nn = n.normalized
                if nn.dot(proj.viewDir) >= -1e-6 { continue } // back-facing or edge-on
                var poly = [a, b, c]
                if cut { poly = clip(poly, proj) ; if poly.count < 3 { continue } }
                let pts = poly.map(proj.xy)
                guard abs(GeometryOps.signedArea(pts)) > 1e-12 else { continue }
                let key = poly.map(proj.depth).reduce(0, +) / Double(poly.count)
                let shade = 0.78 + 0.22 * abs(nn.dot(light))
                let tone = RGBA(min(1, (0.55 + base.r * 0.45) * shade), min(1, (0.55 + base.g * 0.45) * shade), min(1, (0.55 + base.b * 0.45) * shade), isGlass ? 0.45 : 1)
                prims.append((key, g.id, .face(pts, tone)))
            }
            for e in g.edges where e.count >= 2 {
                for k in 0..<(e.count - 1) {
                    var p = e[k], q = e[k + 1]
                    if cut {
                        let dp = proj.depth(p), dq = proj.depth(q)
                        if dp < 0 && dq < 0 { continue }
                        if dp < 0 { p = p + (q - p) * (dp / (dp - dq)) } else if dq < 0 { q = p + (q - p) * (dp / (dp - dq)) }
                    }
                    let len = proj.xy(p).distance(to: proj.xy(q))
                    if len < 1e-9 { continue }
                    let n = max(1, Int((len / splitLen).rounded(.up)))
                    for s in 0..<n {
                        let p0 = p + (q - p) * (Double(s) / Double(n)), p1 = p + (q - p) * (Double(s + 1) / Double(n))
                        let key = min(proj.depth(p0), proj.depth(p1)) - bias
                        prims.append((key, g.id, .edge([proj.xy(p0), proj.xy(p1)])))
                    }
                }
            }
            if cut {
                let loops = sectionLoops(m, proj)
                if !loops.closed.isEmpty || !loops.open.isEmpty {
                    var items: [DrawItem] = []
                    if !loops.closed.isEmpty { items.append(.fill(loops: loops.closed, color: pocheColor)) }
                    for l in loops.closed { items.append(.stroke(points: l, closed: true, style: StrokeStyle(color: edgeColor, lineweight: 0.5))) }
                    for l in loops.open { items.append(.stroke(points: l, closed: false, style: StrokeStyle(color: edgeColor, lineweight: 0.5))) }
                    poche.append(DrawEntry(id: g.id, items: items))
                }
            }
        }
        prims.sort { $0.key > $1.key }
        // View graphics: line weights by depth (projection near / beyond), depth cueing, far clip, hidden lines.
        let gfx = ViewGraphics.settings(doc)
        let d0 = cut ? 0 : dmin, span = max(dmax - d0, 1e-9)
        if let far = gfx.farClip { prims.removeAll { $0.key > d0 + far } }
        let hiddenMode = gfx.hiddenLines
        var occluder: ViewGraphics.Occluder? = nil
        if hiddenMode { occluder = ViewGraphics.Occluder(prims: prims.compactMap { p in if case .face(let pts, _) = p.prim { return (pts, p.key) }; return nil }, size: size) }
        var out: [DrawEntry] = []
        var hidden: [DrawItem] = []
        var visibleEdges: [(EntityID?, DrawItem)] = []
        var curID: EntityID?? = nil
        var cur: [DrawItem] = []
        func flush() { if let id = curID, !cur.isEmpty { out.append(DrawEntry(id: id, items: cur)) }; cur = [] }
        for p in prims {
            let t = min(max((p.key - d0) / span, 0), 1)
            switch p.prim {
            case .face(let pts, let c):
                if curID == nil || curID! != p.id { flush(); curID = .some(p.id) }
                cur.append(.fill(loops: [pts], color: gfx.depthCue ? ViewGraphics.cue(c, t) : c))
            case .edge(let pts):
                let lw = gfx.lineWeights ? ViewGraphics.lineweight(depthFraction: t, cut: cut) : 0.25
                let col = gfx.depthCue ? ViewGraphics.cue(edgeColor, t) : edgeColor
                if let occ = occluder {
                    let m = (pts[0] + pts[1]) / 2
                    if occ.isHidden(m, depth: p.key + bias, tolerance: bias * 20) {
                        hidden.append(.stroke(points: pts, closed: false, style: StrokeStyle(color: ViewGraphics.hiddenColor, lineweight: 0.13, dash: gfx.hiddenDash)))
                    } else { visibleEdges.append((p.id, .stroke(points: pts, closed: false, style: StrokeStyle(color: col, lineweight: lw)))) }
                    continue
                }
                if curID == nil || curID! != p.id { flush(); curID = .some(p.id) }
                cur.append(.stroke(points: pts, closed: false, style: StrokeStyle(color: col, lineweight: lw)))
            }
        }
        flush()
        if hiddenMode {
            // Visible edges over all faces; hidden edges dashed (ELEVHIDDEN = 1).
            var byID: [EntityID?: [DrawItem]] = [:]
            for (id, it) in visibleEdges { byID[id, default: []].append(it) }
            for (id, items) in byID.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) { out.append(DrawEntry(id: id, items: items)) }
            if !hidden.isEmpty { out.append(DrawEntry(id: nil, items: hidden)) }
        }
        out += poche
        // Ground line.
        let gz = doc.levels.map(\.elevation).min() ?? 0
        let ext = box.width * 0.05
        out.append(DrawEntry(id: nil, items: [.stroke(points: [Vec2(box.min.x - ext, gz), Vec2(box.max.x + ext, gz)], closed: false, style: StrokeStyle(color: edgeColor, lineweight: 0.5))]))
        if doc.variable("VIEWANNOTATIONS") != "0" { out += annotations(doc: doc, proj: proj, box: box) }
        if gfx.dimensions { out += ViewGraphics.elevationDimensions(doc: doc, box: box) }
        return out
    }

    static let annoColor = RGBA(0.15, 0.35, 0.75)

    /// Level lines with level heads (name and elevation) at the right, and grid lines with bubbles at the top,
    /// for grids that cross the view (perpendicular to it).
    static func annotations(doc: ArchiDocument, proj: Proj, box: BBox2) -> [DrawEntry] {
        let u = 1 / doc.units.mm
        let th = 250 * u
        let ext = max(box.width * 0.04, 800 * u)
        let x0 = box.min.x - ext, x1 = box.max.x + ext
        let dash = [600 * u, -150 * u, 100 * u, -150 * u]
        var out: [DrawEntry] = []
        var gridTop = box.max.y + 600 * u
        for l in doc.levels {
            let y = l.elevation
            let st = StrokeStyle(color: annoColor, lineweight: 0.18, dash: dash)
            let r = th * 0.6
            let head = [Vec2(x1, y), Vec2(x1 + r, y + r), Vec2(x1 + 2 * r, y), Vec2(x1 + r, y - r)]
            let meters = l.elevation * doc.units.mm / 1000
            let label = (meters >= 0 ? "+" : "") + String(format: "%.3f", meters)
            out.append(DrawEntry(id: nil, items: [
                .stroke(points: [Vec2(x0, y), Vec2(x1, y)], closed: false, style: st),
                .fill(loops: [[head[0], head[1], head[2]]], color: annoColor),
                .stroke(points: head, closed: true, style: StrokeStyle(color: annoColor, lineweight: 0.18)),
                .text(TextGeom(position: Vec2(x1 + 2.6 * r, y + th * 0.15), height: th, content: l.name, valign: .bottom), font: "Helvetica", color: annoColor),
                .text(TextGeom(position: Vec2(x1 + 2.6 * r, y - th * 0.15), height: th * 0.8, content: label, valign: .top), font: "Helvetica", color: annoColor),
            ]))
            gridTop = max(gridTop, y + 600 * u)
        }
        let r = 400 * u
        for el in doc.elements {
            guard case .gridLine(let g) = el.geometry, g.start.distance(to: g.end) > 1e-9, abs(g.bulge) < 1e-12 else { continue }
            let a = Vec3(g.start.x, g.start.y, 0), b = Vec3(g.end.x, g.end.y, 0)
            let xa = proj.xf(a), xb = proj.xf(b)
            guard abs(xa - xb) < g.start.distance(to: g.end) * 0.02 else { continue }
            let x = (xa + xb) / 2
            guard x >= x0 - 1e-6, x <= x1 + 1e-6 else { continue }
            let yb = box.min.y - 300 * u, yt = gridTop
            let c = Vec2(x, yt + r)
            out.append(DrawEntry(id: nil, items: [
                .stroke(points: [Vec2(x, yb), Vec2(x, yt)], closed: false, style: StrokeStyle(color: annoColor, lineweight: 0.13, dash: dash)),
                .stroke(points: RG.circle(c, r, segments: 40), closed: true, style: StrokeStyle(color: annoColor, lineweight: 0.18)),
                .text(TextGeom(position: c, height: 350 * u, content: g.label, halign: .center, valign: .middle), font: "Helvetica", color: annoColor),
            ]))
        }
        return out
    }

    typealias Proj = Projection

    /// Clips a 3D polygon to the half-space in front of the section plane (depth ≥ 0).
    static func clip(_ poly: [Vec3], _ proj: Proj) -> [Vec3] {
        var out: [Vec3] = []
        for i in 0..<poly.count {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let dp = proj.depth(p), dq = proj.depth(q)
            if dp >= 0 { out.append(p) }
            if (dp >= 0) != (dq >= 0) { out.append(p + (q - p) * (dp / (dp - dq))) }
        }
        return out
    }

    /// Cross-section of a mesh with the plane depth = 0, chained into loops (projected 2D).
    static func sectionLoops(_ m: Mesh, _ proj: Proj) -> (closed: [[Vec2]], open: [[Vec2]]) {
        var segs: [(Vec2, Vec2)] = []
        var i = 0
        while i + 2 < m.indices.count {
            let v = [m.positions[Int(m.indices[i])], m.positions[Int(m.indices[i + 1])], m.positions[Int(m.indices[i + 2])]]
            i += 3
            let d = v.map(proj.depth)
            var pts: [Vec2] = []
            for k in 0..<3 {
                let a = k, b = (k + 1) % 3
                if (d[a] >= 0) != (d[b] >= 0) { pts.append(proj.xy(v[a] + (v[b] - v[a]) * (d[a] / (d[a] - d[b])))) }
            }
            if pts.count == 2, pts[0].distance(to: pts[1]) > 1e-9 { segs.append((pts[0], pts[1])) }
        }
        guard !segs.isEmpty else { return ([], []) }
        var b = BBox2.empty
        for s in segs { b.add(s.0); b.add(s.1) }
        let q = max(b.width, b.height, 1e-6) * 1e-7
        func key(_ p: Vec2) -> [Int64] { [Int64((p.x / q).rounded()), Int64((p.y / q).rounded())] }
        var adj: [[Int64]: [Int]] = [:]
        for (k, s) in segs.enumerated() { adj[key(s.0), default: []].append(k); adj[key(s.1), default: []].append(k) }
        var used = [Bool](repeating: false, count: segs.count)
        var closed: [[Vec2]] = [], open: [[Vec2]] = []
        for start in 0..<segs.count where !used[start] {
            used[start] = true
            var chain = [segs[start].0, segs[start].1]
            var extended = true
            while extended {
                extended = false
                let endK = key(chain[chain.count - 1])
                if let next = adj[endK]?.first(where: { !used[$0] }) {
                    used[next] = true
                    let s = segs[next]
                    chain.append(key(s.0) == endK ? s.1 : s.0)
                    extended = true
                }
            }
            if chain.count >= 4, key(chain[0]) == key(chain[chain.count - 1]) { chain.removeLast(); closed.append(chain) }
            else { open.append(chain) }
        }
        return (closed, open)
    }
}
