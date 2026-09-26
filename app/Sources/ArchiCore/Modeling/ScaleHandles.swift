// Oanarina Archi Tool — GPL-3.0-or-later
// Scale tool with handles (M3D-106, SketchUp-style): the bounding box of the selection carries 26 handles — 8 corners,
// 12 edge midpoints and 6 face centres. Dragging a handle scales along the axes it sits on (non-uniformly) about the
// opposite handle, or about the box centre; the uniform variant keeps proportions. Pure maths here; the SCALE3D
// command drives it from the plan canvas (Handles option) and the 3D viewport can use the same functions.
import Foundation

public enum ScaleHandles {
    /// A handle: −1 / 0 / +1 per axis (min side, middle, max side).
    public struct Handle: Hashable, CustomStringConvertible {
        public var sx: Int, sy: Int, sz: Int
        public init(_ sx: Int, _ sy: Int, _ sz: Int) { self.sx = sx; self.sy = sy; self.sz = sz }
        public func point(_ b: BBox3) -> Vec3 {
            func c(_ s: Int, _ lo: Double, _ hi: Double) -> Double { s < 0 ? lo : s > 0 ? hi : (lo + hi) / 2 }
            return Vec3(c(sx, b.min.x, b.max.x), c(sy, b.min.y, b.max.y), c(sz, b.min.z, b.max.z))
        }
        /// Handle on the opposite side of the box (the fixed point of a drag).
        public var opposite: Handle { Handle(-sx, -sy, -sz) }
        public var axisCount: Int { [sx, sy, sz].filter { $0 != 0 }.count }
        public var kind: String { ["centre", "face", "edge", "corner"][axisCount] }
        public var description: String {
            func n(_ s: Int, _ lo: String, _ hi: String) -> String? { s < 0 ? lo : s > 0 ? hi : nil }
            let parts = [n(sz, "bottom", "top"), n(sy, "front", "back"), n(sx, "left", "right")].compactMap { $0 }
            return parts.joined(separator: "-") + " " + kind
        }
    }

    /// All 26 handles.
    public static var all: [Handle] {
        var out: [Handle] = []
        for x in -1...1 { for y in -1...1 { for z in -1...1 where !(x == 0 && y == 0 && z == 0) { out.append(Handle(x, y, z)) } } }
        return out
    }

    /// Handles seen in plan (on the box's vertical mid-plane): 4 corners and 4 edge midpoints of the footprint.
    public static var planHandles: [Handle] {
        [Handle(-1, -1, 0), Handle(0, -1, 0), Handle(1, -1, 0), Handle(1, 0, 0), Handle(1, 1, 0), Handle(0, 1, 0), Handle(-1, 1, 0), Handle(-1, 0, 0)]
    }

    /// Nearest plan handle to a picked point.
    public static func nearestPlan(_ p: Vec2, box: BBox3) -> Handle {
        planHandles.min { $0.point(box).xy.distance(to: p) < $1.point(box).xy.distance(to: p) }!
    }

    /// Scale of a handle drag: the handle moves to `target` (only its active axes count). The fixed point is the
    /// opposite handle, or the box centre with `aboutCenter`. `uniform` keeps proportions (one factor on all axes,
    /// from the projection of the drag onto the handle direction). nil when the drag collapses the box.
    public static func scale(box: BBox3, handle h: Handle, to target: Vec3, aboutCenter: Bool = false, uniform: Bool = false) -> (origin: Vec3, factors: Vec3)? {
        guard !box.isEmpty, h.axisCount > 0 else { return nil }
        let o = aboutCenter ? box.center : h.opposite.point(box)
        let hp = h.point(box)
        let signs = [h.sx, h.sy, h.sz]
        let hv = [hp.x - o.x, hp.y - o.y, hp.z - o.z], tv = [target.x - o.x, target.y - o.y, target.z - o.z]
        var f = [1.0, 1.0, 1.0]
        if uniform {
            var num = 0.0, den = 0.0
            for k in 0..<3 where signs[k] != 0 && abs(hv[k]) > 1e-12 { num += tv[k] * hv[k]; den += hv[k] * hv[k] }
            guard den > 1e-18 else { return nil }
            let u = num / den
            guard abs(u) > 1e-9 else { return nil }
            f = [u, u, u]
        } else {
            var any = false
            for k in 0..<3 where signs[k] != 0 {
                guard abs(hv[k]) > 1e-12 else { continue }   // flat along this axis: stays flat
                f[k] = tv[k] / hv[k]
                guard abs(f[k]) > 1e-9 else { return nil }
                any = true
            }
            guard any else { return nil }
        }
        return (o, Vec3(f[0], f[1], f[2]))
    }

    /// Point mapped by a scale about `origin`.
    public static func map(_ p: Vec3, origin o: Vec3, factors f: Vec3) -> Vec3 {
        Vec3(o.x + (p.x - o.x) * f.x, o.y + (p.y - o.y) * f.y, o.z + (p.z - o.z) * f.z)
    }

    /// Box after a scale.
    public static func scaled(_ b: BBox3, origin: Vec3, factors: Vec3) -> BBox3 {
        var r = BBox3.empty
        r.add(map(b.min, origin: origin, factors: factors)); r.add(map(b.max, origin: origin, factors: factors))
        return r
    }

    /// Plan preview of a box with its handles (footprint rectangle and small squares at the handles).
    public static func planPreview(_ b: BBox3, size: Double) -> [Geometry] {
        let c = [Vec2(b.min.x, b.min.y), Vec2(b.max.x, b.min.y), Vec2(b.max.x, b.max.y), Vec2(b.min.x, b.max.y)]
        var out: [Geometry] = [.polyline(PolylineGeom(points: c, closed: true))]
        let s = size / 2
        for h in planHandles {
            let p = h.point(b).xy
            out.append(.polyline(PolylineGeom(points: [p + Vec2(-s, -s), p + Vec2(s, -s), p + Vec2(s, s), p + Vec2(-s, s)], closed: true)))
        }
        return out
    }
}
