// Oanarina Archi Tool — GPL-3.0-or-later
// Ambient occlusion baked on the model (VIS-033): for every point, the fraction of the hemisphere above its surface
// that is blocked by geometry within a radius, by ray casting against all triangles (bounding-volume hierarchy,
// Möller–Trumbore ray/triangle test). Deterministic samples (a Fibonacci hemisphere with cosine weighting), so the
// shaded elevations, axonometrics and perspectives exported to PDF/SVG match on every run, and the per-vertex values
// can be written by the model exporters and used by the viewport. Settings: AOINTENSITY (0 = off, up to 2),
// AORADIUS (model units), AOSAMPLES.
import Foundation

public enum AmbientOcclusion {
    public struct Settings: Hashable {
        public var intensity: Double
        public var radius: Double
        public var samples: Int
        public init(intensity: Double = 1, radius: Double = 1000, samples: Int = 24) {
            self.intensity = intensity; self.radius = radius; self.samples = samples
        }
    }

    /// Settings of the document (nil when ambient occlusion is off).
    public static func settings(_ doc: ArchiDocument) -> Settings? {
        guard let i = doc.variable("AOINTENSITY").flatMap(Double.init), i > 1e-9 else { return nil }
        let r = doc.variable("AORADIUS").flatMap(Double.init) ?? 1000 / doc.units.mm
        let n = doc.variable("AOSAMPLES").flatMap(Int.init) ?? 24
        return Settings(intensity: min(i, 2), radius: max(r, 1e-6), samples: min(max(n, 4), 256))
    }

    // MARK: BVH

    struct Tri { let a: Vec3, e1: Vec3, e2: Vec3 }
    struct Node { var box: BBox3; var left = -1, right = -1; var start = 0, count = 0 }

    public final class Scene {
        var tris: [Tri] = []
        var nodes: [Node] = []
        public var triangleCount: Int { tris.count }

        public init(groups: [MeshGroup]) {
            var raw: [(Vec3, Vec3, Vec3)] = []
            for g in groups {
                let m = g.mesh
                var i = 0
                while i + 2 < m.indices.count {
                    let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
                    i += 3
                    if (b - a).cross(c - a).length > 1e-12 { raw.append((a, b, c)) }
                }
            }
            var idx = Array(raw.indices)
            let cent = raw.map { ($0.0 + $0.1 + $0.2) / 3 }
            func bounds(_ lo: Int, _ hi: Int) -> BBox3 {
                var b = BBox3.empty
                for k in lo..<hi { let t = raw[idx[k]]; b.add(t.0); b.add(t.1); b.add(t.2) }
                return b
            }
            func build(_ lo: Int, _ hi: Int) -> Int {
                let n = nodes.count
                nodes.append(Node(box: bounds(lo, hi)))
                if hi - lo <= 4 { nodes[n].start = lo; nodes[n].count = hi - lo; return n }
                var cb = BBox3.empty
                for k in lo..<hi { cb.add(cent[idx[k]]) }
                let s = cb.size
                let axis = s.x >= s.y && s.x >= s.z ? 0 : (s.y >= s.z ? 1 : 2)
                func v(_ p: Vec3) -> Double { axis == 0 ? p.x : axis == 1 ? p.y : p.z }
                idx[lo..<hi].sort { v(cent[$0]) < v(cent[$1]) }
                let mid = (lo + hi) / 2
                let l = build(lo, mid), r = build(mid, hi)
                nodes[n].left = l; nodes[n].right = r
                return n
            }
            if !raw.isEmpty { _ = build(0, raw.count) }
            tris = idx.map { let t = raw[$0]; return Tri(a: t.0, e1: t.1 - t.0, e2: t.2 - t.0) }
        }

        static func hitsBox(_ b: BBox3, _ o: Vec3, _ inv: Vec3, _ tMax: Double) -> Bool {
            var t0 = 0.0, t1 = tMax
            for (lo, hi, oo, iv) in [(b.min.x, b.max.x, o.x, inv.x), (b.min.y, b.max.y, o.y, inv.y), (b.min.z, b.max.z, o.z, inv.z)] {
                var ta = (lo - oo) * iv, tb = (hi - oo) * iv
                if ta.isNaN || tb.isNaN { if oo < lo || oo > hi { return false }; continue }
                if ta > tb { swap(&ta, &tb) }
                t0 = max(t0, ta); t1 = min(t1, tb)
                if t0 > t1 { return false }
            }
            return true
        }

        /// Whether a ray from `o` along unit `d` hits a triangle closer than `tMax` (and farther than `tMin`).
        public func occluded(_ o: Vec3, _ d: Vec3, tMin: Double, tMax: Double) -> Bool {
            guard !nodes.isEmpty else { return false }
            let inv = Vec3(1 / d.x, 1 / d.y, 1 / d.z)
            var stack = [0]
            while let n = stack.popLast() {
                let node = nodes[n]
                guard Scene.hitsBox(node.box, o, inv, tMax) else { continue }
                if node.left < 0 {
                    for k in node.start..<(node.start + node.count) {
                        let t = tris[k]
                        let p = d.cross(t.e2)
                        let det = t.e1.dot(p)
                        if abs(det) < 1e-14 { continue }
                        let f = 1 / det
                        let s = o - t.a
                        let u = f * s.dot(p)
                        if u < 0 || u > 1 { continue }
                        let q = s.cross(t.e1)
                        let v = f * d.dot(q)
                        if v < 0 || u + v > 1 { continue }
                        let tt = f * t.e2.dot(q)
                        if tt > tMin && tt < tMax { return true }
                    }
                } else { stack.append(node.left); stack.append(node.right) }
            }
            return false
        }

        /// Occlusion (0 = open sky, 1 = fully enclosed) of a surface point with unit normal `n`.
        public func occlusion(at p: Vec3, normal n: Vec3, settings s: Settings) -> Double {
            let dirs = AmbientOcclusion.hemisphere(s.samples)
            let (u, v) = Mesh.basis(n)
            let eps = max(s.radius * 1e-4, 1e-6)
            let o = p + n * eps
            var hit = 0
            for d in dirs {
                let w = (u * d.x + v * d.y + n * d.z).normalized
                if occluded(o, w, tMin: eps * 0.5, tMax: s.radius) { hit += 1 }
            }
            return Double(hit) / Double(dirs.count)
        }
    }

    /// Cosine-weighted Fibonacci hemisphere directions in a local frame (z = normal).
    static func hemisphere(_ n: Int) -> [Vec3] {
        let ga = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let r = ((Double(i) + 0.5) / Double(n)).squareRoot()   // cosine weighting: uniform on the disc
            let a = Double(i) * ga
            let x = r * cos(a), y = r * sin(a)
            return Vec3(x, y, max(1 - x * x - y * y, 0).squareRoot())
        }
    }

    /// Per-vertex occlusion of every group (same order as positions), for exporters and the viewport.
    public static func bake(_ groups: [MeshGroup], settings s: Settings) -> [[Double]] {
        let scene = Scene(groups: groups)
        return groups.map { g in
            g.mesh.positions.indices.map { k in
                let n = k < g.mesh.normals.count ? g.mesh.normals[k] : .unitZ
                return n.length > 1e-9 ? scene.occlusion(at: g.mesh.positions[k], normal: n.normalized, settings: s) : 0
            }
        }
    }

    /// Brightness multiplier for an occlusion value.
    public static func factor(_ occlusion: Double, intensity: Double) -> Double { max(0.15, 1 - 0.6 * intensity * occlusion) }
}
