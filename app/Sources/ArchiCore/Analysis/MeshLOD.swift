// Oanarina Archi Tool — GPL-3.0-or-later
// Level of detail for the 3D view (SYS-018): each mesh group gets coarser versions (vertex clustering that keeps closed
// solids closed, MeshTools.decimate), and a level is chosen per frame from the object's projected size in pixels, so
// distant objects draw few triangles and sub-pixel objects are skipped. Flat-shaded normals are rebuilt per level.
import Foundation

public struct LODGroup {
    public var group: MeshGroup
    /// Level 0 is the full mesh; later levels are coarser.
    public var levels: [Mesh]
    public var center: Vec3
    public var radius: Double
}

public enum MeshLOD {
    /// Triangle ratios of the coarser levels.
    public static let defaultRatios: [Double] = [0.3, 0.08]

    static func mesh(_ v: [Vec3], _ t: [Int]) -> Mesh {
        var m = Mesh()
        var i = 0
        while i + 2 < t.count {
            let a = v[t[i]], b = v[t[i + 1]], c = v[t[i + 2]]
            let n0 = (b - a).cross(c - a)
            let n = n0.length > 1e-300 ? n0 / n0.length : Vec3(0, 0, 1)
            let base = UInt32(m.positions.count)
            m.positions += [a, b, c]; m.normals += [n, n, n]
            m.indices += [base, base + 1, base + 2]
            i += 3
        }
        return m
    }

    /// Levels of a group (groups under `minTriangles` keep one level).
    public static func build(_ g: MeshGroup, ratios: [Double] = defaultRatios, minTriangles: Int = 200) -> LODGroup {
        let b = g.mesh.bounds
        let center = (b.min + b.max) * 0.5, radius = (b.max - b.min).length / 2
        var levels = [g.mesh]
        if g.mesh.triangleCount >= minTriangles {
            let w = MeshTools.weld(MeshTools.triangles(g.mesh), tolerance: max(radius * 1e-7, 1e-9))
            var last = g.mesh.triangleCount
            for r in ratios {
                let d = MeshTools.decimate(vertices: w.vertices, triangles: w.triangles, ratio: r)
                let n = d.triangles.count / 3
                guard n > 0, n < last * 9 / 10 else { continue }   // only levels that really reduce
                levels.append(mesh(d.vertices, d.triangles)); last = n
            }
        }
        return LODGroup(group: g, levels: levels, center: center, radius: radius)
    }

    /// Projected diameter in pixels of a bounding sphere seen from `distance` with a vertical field of view.
    public static func projectedSize(radius: Double, distance: Double, fovY: Double, viewportHeight: Double) -> Double {
        guard distance > radius else { return .infinity }
        return 2 * radius / (2 * distance * tan(fovY / 2)) * viewportHeight
    }

    /// Level to draw (nil: too small to draw): full detail above `fine` pixels, then one level per halving of the size
    /// down to `coarse` pixels, the coarsest below that; nothing under `cull` pixels.
    public static func level(for lod: LODGroup, eye: Vec3, fovY: Double, viewportHeight: Double, fine: Double = 300, cull: Double = 1.5) -> Int? {
        let px = projectedSize(radius: lod.radius, distance: (lod.center - eye).length, fovY: fovY, viewportHeight: viewportHeight)
        if px < cull { return nil }
        if px >= fine || lod.levels.count == 1 { return 0 }
        let steps = Int(log2(fine / px).rounded(.up))
        return min(lod.levels.count - 1, max(1, steps))
    }

    /// Triangles drawn for a scene from an eye point (for budgets and statistics).
    public static func drawnTriangles(_ lods: [LODGroup], eye: Vec3, fovY: Double, viewportHeight: Double) -> Int {
        lods.reduce(0) { acc, l in acc + (level(for: l, eye: eye, fovY: fovY, viewportHeight: viewportHeight).map { l.levels[$0].triangleCount } ?? 0) }
    }
}
