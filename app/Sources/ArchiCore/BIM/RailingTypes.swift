// Oanarina Archi Tool — GPL-3.0-or-later
// Railing types: handrail profiles swept along the path, posts, baluster patterns, glass panels, cable infill,
// bottom rails and handrail extensions.
import Foundation

public enum RailingTypes {
    public struct Preset { public var name: String; public var apply: (inout RailingGeom) -> Void }

    public static let presets: [(name: String, rail: String, railSize: Double, infill: String, baluster: String, balSize: Double, spacing: Double, post: Double, bottom: Bool)] = [
        ("Balusters", "round", 50, "balusters", "rect", 20, 120, 1200, true),
        ("Glass", "handrail-rect", 50, "glass", "rect", 0, 0, 1500, false),
        ("Cable", "round", 45, "cables", "round", 6, 100, 1200, false),
        ("Bars", "rect", 50, "bars", "rect", 20, 150, 1500, true),
        ("Wooden", "mushroom", 70, "balusters", "rect", 40, 110, 1000, true),
        ("Handrail", "oval", 45, "none", "rect", 0, 0, 900, false),
    ]

    public static func apply(preset name: String, to g: inout RailingGeom) -> Bool {
        guard let p = presets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        g.railProfile = p.rail; g.railSize = p.railSize; g.infill = p.infill; g.balusterProfile = p.baluster; g.balusterSize = p.balSize
        g.balusterSpacing = p.spacing; g.postSpacing = p.post; g.bottomRail = p.bottom
        return true
    }

    /// Points along a polyline every `step` (excluding the ends), with each point's segment direction.
    static func samples(_ path: [Vec2], step: Double, from start: Double = 0) -> [(Vec2, Vec2)] {
        guard step > 1e-9 else { return [] }
        var out: [(Vec2, Vec2)] = []
        var acc = 0.0
        var next = start > 0 ? start : step
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1], len = a.distance(to: b)
            guard len > 1e-12 else { continue }
            let d = (b - a) / len
            while next <= acc + len - 1e-9 { out.append((a + d * (next - acc), d)); next += step }
            acc += len
        }
        return out
    }

    /// Mesh groups of a typed railing (materials: handrail/posts "Steel" or element material, glass "Glass").
    static func groups(_ el: BIMElement, _ g: RailingGeom, elev: Double, doc: ArchiDocument) -> [MeshGroup] {
        let u = 1 / doc.units.mm
        var path = RG.dedupe(g.path, closed: false)
        guard path.count >= 2 else { return [] }
        let zb = elev + g.baseOffset, zt = zb + g.height
        let rs = (g.railSize ?? 50) * u
        var rail = MeshAcc(), posts = MeshAcc(), infill = MeshAcc(), glass = MeshAcc()
        // Handrail with extensions beyond the ends.
        var rpath = path
        if let ext = g.extensionLength, ext > 0 {
            let e = ext * u
            rpath[0] = rpath[0] - (rpath[1] - rpath[0]).normalized * e
            let n = rpath.count
            rpath[n - 1] = rpath[n - 1] + (rpath[n - 1] - rpath[n - 2]).normalized * e
        }
        let rprof = ProfileLibrary.outline(g.railProfile ?? "rect", width: rs, height: rs * (g.railProfile == "oval" ? 0.8 : 1), doc: doc) ?? ProfileLibrary.builtin("rect", width: rs, height: rs)!
        let rc = GeometryOps.centroid(rprof)
        let railTop = zt - (rprof.map(\.y).max()! - rc.y)
        SweepMesh.sweep(rprof.map { $0 - rc }, along: rpath.map { Vec3($0.x, $0.y, railTop) }, into: &rail)
        let railBottom = railTop - (rc.y - rprof.map(\.y).min()!)
        // Posts at the ends, the vertices and every postSpacing.
        let ps = max((g.postSpacing ?? 1200) * u, 100 * u)
        var postPts = path
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1], len = a.distance(to: b)
            let n = max(1, Int((len / ps).rounded(.up)))
            for k in 1..<n { postPts.append(a.lerp(b, Double(k) / Double(n))) }
        }
        let pw = max(rs * 0.8, 30 * u) / 2
        for p in postPts { posts.prism([p + Vec2(-pw, -pw), p + Vec2(pw, -pw), p + Vec2(pw, pw), p + Vec2(-pw, pw)], z0: zb, z1: railBottom) }
        let bottomZ = zb + 100 * u
        if g.bottomRail ?? false {
            for i in 0..<(path.count - 1) {
                let a = path[i], b = path[i + 1]
                let d = (b - a).normalized.perp * (pw * 0.8)
                posts.prism([a - d, b - d, b + d, a + d], z0: bottomZ - 40 * u, z1: bottomZ)
            }
        }
        let infillBottom = (g.bottomRail ?? false) ? bottomZ : zb + 50 * u
        switch (g.infill ?? "balusters").lowercased() {
        case "glass":
            for i in 0..<(path.count - 1) {
                let a = path[i], b = path[i + 1], len = a.distance(to: b)
                guard len > 2 * pw + 20 * u else { continue }
                let d = (b - a) / len, n = d.perp * (6 * u)
                let a2 = a + d * (pw + 10 * u), b2 = b - d * (pw + 10 * u)
                glass.prism([a2 - n, b2 - n, b2 + n, a2 + n], z0: infillBottom, z1: railBottom - 30 * u)
            }
        case "cables":
            let gap = max((g.balusterSpacing ?? 100) * u, 40 * u)
            var z = infillBottom
            let r = max((g.balusterSize ?? 6) * u / 2, 1 * u)
            while z < railBottom - gap * 0.5 {
                SweepMesh.sweep(RG.circle(.zero, r, segments: 8), along: path.map { Vec3($0.x, $0.y, z) }, into: &infill)
                z += gap
            }
        case "none": break
        default:
            // Balusters (or vertical bars) at the spacing along the path.
            let sp = max((g.balusterSpacing ?? 120) * u, 50 * u)
            let bs = max((g.balusterSize ?? 20) * u, 5 * u)
            let bprof = ProfileLibrary.outline(g.balusterProfile ?? "rect", width: bs, height: bs, doc: doc) ?? ProfileLibrary.builtin("rect", width: bs, height: bs)!
            let bc = GeometryOps.centroid(bprof)
            for (p, d) in samples(path, step: sp) where !postPts.contains(where: { $0.distance(to: p) < pw + bs }) {
                let t = Transform2D.translation(p) * Transform2D.rotation(d.angle)
                infill.prism(bprof.map { t.apply($0 - bc) }, z0: infillBottom, z1: railBottom, smooth: g.balusterProfile == "round")
            }
        }
        let mat = el.material ?? "Steel"
        return [rail.group(el.id, "railing", el.props["railMaterial"] ?? mat), posts.group(el.id, "railing", mat),
                infill.group(el.id, "railing", el.props["infillMaterial"] ?? mat), glass.group(el.id, "railing", "Glass")].compactMap { $0 }
    }
}
