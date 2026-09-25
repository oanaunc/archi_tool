// Oanarina Archi Tool — GPL-3.0-or-later
// Section/elevation graphics: line weights by cut / projection / beyond, dashed hidden lines, depth cueing with far clip,
// and dimensions in elevations. Settings are view variables (and so part of view templates):
// ELEVLW (1 = weights by depth, default on), ELEVHIDDEN (1 = hidden lines dashed), DEPTHCUE (1 = fade with distance),
// ELEVFARCLIP (distance beyond which nothing is drawn), ELEVDIMS (1 = level and overall height dimensions).
import Foundation

public enum ViewGraphics {
    public struct Settings { public var lineWeights: Bool; public var hiddenLines: Bool; public var depthCue: Bool; public var farClip: Double?; public var dimensions: Bool; public var hiddenDash: [Double] }

    public static let hiddenColor = RGBA(0.35, 0.35, 0.38)

    public static func settings(_ doc: ArchiDocument) -> Settings {
        let u = 1 / doc.units.mm
        return Settings(lineWeights: doc.variable("ELEVLW") != "0", hiddenLines: doc.variable("ELEVHIDDEN") == "1", depthCue: doc.variable("DEPTHCUE") == "1",
                        farClip: doc.variable("ELEVFARCLIP").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }, dimensions: doc.variable("ELEVDIMS") == "1",
                        hiddenDash: [150 * u, -75 * u])
    }

    /// Projection line weight by depth: near edges heavier, edges beyond lighter (cut outlines are drawn at 0.5 separately).
    public static func lineweight(depthFraction t: Double, cut: Bool) -> Double {
        if cut { return t < 0.2 ? 0.35 : (t < 0.55 ? 0.25 : 0.13) }
        return t < 0.15 ? 0.35 : (t < 0.5 ? 0.25 : 0.18)
    }

    /// Depth cueing: fades a colour towards white with distance (up to 75 %).
    public static func cue(_ c: RGBA, _ t: Double) -> RGBA {
        let k = min(max(t, 0), 1) * 0.75
        return RGBA(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, c.a)
    }

    /// Occlusion test against projected faces (triangles with a depth key), accelerated by a uniform grid.
    struct Occluder {
        struct Tri { var a: Vec2, b: Vec2, c: Vec2; var depth: Double }
        var tris: [Tri] = []
        var grid: [Int: [Int]] = [:]
        var origin = Vec2.zero, cell = 1.0, cols = 1
        init(prims: [([Vec2], Double)], size: Double) {
            var box = BBox2.empty
            for (pts, d) in prims where pts.count >= 3 {
                for i in 1..<(pts.count - 1) { tris.append(Tri(a: pts[0], b: pts[i], c: pts[i + 1], depth: d)) }
                pts.forEach { box.add($0) }
            }
            guard !box.isEmpty else { return }
            origin = box.min
            cell = max(max(box.width, box.height) / 96, 1e-9)
            cols = Int(box.width / cell) + 2
            for (k, t) in tris.enumerated() {
                let b = BBox2(points: [t.a, t.b, t.c])
                let i0 = Int((b.min.x - origin.x) / cell), i1 = Int((b.max.x - origin.x) / cell)
                let j0 = Int((b.min.y - origin.y) / cell), j1 = Int((b.max.y - origin.y) / cell)
                for i in i0...max(i0, i1) { for j in j0...max(j0, j1) { grid[j * cols + i, default: []].append(k) } }
            }
        }
        /// True when a face nearer than `depth` covers point p (points on a face's own outline are not hidden).
        func isHidden(_ p: Vec2, depth: Double, tolerance: Double) -> Bool {
            let i = Int((p.x - origin.x) / cell), j = Int((p.y - origin.y) / cell)
            guard let ks = grid[j * cols + i] else { return false }
            for k in ks {
                let t = tris[k]
                guard t.depth < depth - tolerance else { continue }
                let d1 = (t.b - t.a).cross(p - t.a), d2 = (t.c - t.b).cross(p - t.b), d3 = (t.a - t.c).cross(p - t.c)
                let e = tolerance * 1e-3
                let inside = (d1 > e && d2 > e && d3 > e) || (d1 < -e && d2 < -e && d3 < -e)
                if inside { return true }
            }
            return false
        }
    }

    /// Vertical dimension chain at the left of an elevation/section: level to level within the drawing, and the overall height.
    static func elevationDimensions(doc: ArchiDocument, box: BBox2) -> [DrawEntry] {
        let u = 1 / doc.units.mm
        let styleName = doc.dimStyles.first { $0.name.hasPrefix("Architectural") }?.name ?? doc.currentDimStyle
        let x = box.min.x - 1500 * u
        var zs = doc.levels.map(\.elevation).filter { $0 >= box.min.y - 1e-6 && $0 <= box.max.y + 1e-6 }
        zs.append(box.max.y); zs.append(max(box.min.y, doc.levels.map(\.elevation).min() ?? box.min.y))
        zs = zs.sorted()
        var uniq: [Double] = []
        for z in zs where uniq.last.map({ z - $0 > 1e-6 }) ?? true { uniq.append(z) }
        guard uniq.count >= 2 else { return [] }
        var dims: [DimensionGeom] = []
        for i in 0..<(uniq.count - 1) {
            dims.append(DimensionGeom(kind: .linear, points: [Vec2(box.min.x, uniq[i]), Vec2(box.min.x, uniq[i + 1]), Vec2(x, (uniq[i] + uniq[i + 1]) / 2)], rotation: .pi / 2, style: styleName))
        }
        if uniq.count > 2 {
            dims.append(DimensionGeom(kind: .linear, points: [Vec2(box.min.x, uniq[0]), Vec2(box.min.x, uniq[uniq.count - 1]), Vec2(x - 700 * u, (uniq[0] + uniq[uniq.count - 1]) / 2)], rotation: .pi / 2, style: styleName))
        }
        var o = DrawOptions(level: nil)
        o.showAnnotations = true
        return dims.map { d in
            let e = Entity(layer: "A-ANNO-DIMS", color: .rgb(40, 90, 190), geometry: .dimension(d))
            return DrawEntry(id: nil, items: DrawListBuilder.items(for: e, doc: doc, options: o))
        }
    }
}
