// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Orthographic elevations and sections from the 3D model, with painter's-algorithm hidden-line removal.
/// Output coordinates: x along the view (left → right as seen by the viewer), y = height (Z).
public enum ElevationBuilder {
    struct Projection {
        var viewDir: Vec3
        var xf: (Vec3) -> Double
        var depthf: (Vec3) -> Double
        func xy(_ p: Vec3) -> Vec2 { Vec2(xf(p), p.z) }
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
        if view == .plan || view == .ceiling { return DrawListBuilder.entries(doc: doc, options: DrawOptions(level: nil)) }
        let groups = MeshBuilder.build(doc: doc)
        var line = sectionLine
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
        var out: [DrawEntry] = []
        var curID: EntityID?? = nil
        var cur: [DrawItem] = []
        func flush() { if let id = curID, !cur.isEmpty { out.append(DrawEntry(id: id, items: cur)) }; cur = [] }
        for p in prims {
            if curID == nil || curID! != p.id { flush(); curID = .some(p.id) }
            switch p.prim {
            case .face(let pts, let c): cur.append(.fill(loops: [pts], color: c))
            case .edge(let pts): cur.append(.stroke(points: pts, closed: false, style: StrokeStyle(color: edgeColor, lineweight: 0.25)))
            }
        }
        flush()
        out += poche
        // Ground line.
        let gz = doc.levels.map(\.elevation).min() ?? 0
        let ext = box.width * 0.05
        out.append(DrawEntry(id: nil, items: [.stroke(points: [Vec2(box.min.x - ext, gz), Vec2(box.max.x + ext, gz)], closed: false, style: StrokeStyle(color: edgeColor, lineweight: 0.5))]))
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
