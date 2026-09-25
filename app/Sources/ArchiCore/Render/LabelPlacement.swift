// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Label placement inside polygons: the pole of inaccessibility (the interior point farthest from the outline,
/// found by a best-first quadtree search as in Mapbox's "polylabel"; algorithm reimplemented), optionally
/// keeping away from obstacle footprints such as furniture.
public enum LabelPlacement {
    /// Signed distance from `p` to the polygon outline: positive inside, negative outside.
    public static func signedDistance(_ p: Vec2, _ poly: [Vec2]) -> Double {
        guard poly.count >= 2 else { return -.infinity }
        let d = GeometryOps.distance(from: p, toPolyline: poly + [poly[0]])
        return GeometryOps.pointInPolygon(p, poly) ? d : -d
    }

    /// Clearance of `p`: distance to the room outline, reduced by obstacles (negative inside an obstacle).
    static func clearance(_ p: Vec2, _ poly: [Vec2], _ obstacles: [[Vec2]]) -> Double {
        var d = signedDistance(p, poly)
        for o in obstacles where o.count >= 3 { d = min(d, -signedDistance(p, o)) }
        return d
    }

    /// Best label point and its clearance radius. `precision` defaults to 1/200 of the polygon size.
    public static func pole(of poly0: [Vec2], avoiding obstacles: [[Vec2]] = [], precision: Double? = nil) -> (point: Vec2, radius: Double) {
        let poly = RG.dedupe(poly0, closed: true)
        guard poly.count >= 3 else { return (poly.first ?? .zero, 0) }
        let box = BBox2(points: poly)
        let size = min(box.width, box.height)
        guard size > 0 else { return (box.center, 0) }
        let prec = precision ?? max(size / 200, 1e-9)
        struct Cell { var c: Vec2; var h: Double; var d: Double; var max: Double }
        func cell(_ c: Vec2, _ h: Double) -> Cell {
            let d = clearance(c, poly, obstacles)
            return Cell(c: c, h: h, d: d, max: d + h * 2.squareRoot())
        }
        var queue: [Cell] = []
        let h0 = size / 2
        var x = box.min.x
        while x < box.max.x {
            var y = box.min.y
            while y < box.max.y { queue.append(cell(Vec2(x + h0, y + h0), h0)); y += size }
            x += size
        }
        // Start from the area centroid and the bounding box center.
        var best = cell(GeometryOps.centroid(poly), 0)
        let bc = cell(box.center, 0)
        if bc.d > best.d { best = bc }
        var iterations = 0
        while !queue.isEmpty && iterations < 20000 {
            iterations += 1
            var bi = 0
            for i in 1..<queue.count where queue[i].max > queue[bi].max { bi = i }
            queue.swapAt(bi, queue.count - 1)
            let c = queue.removeLast()
            if c.d > best.d { best = c }
            if c.max - best.d <= prec { continue }
            let h = c.h / 2
            for dx in [-h, h] { for dy in [-h, h] { queue.append(cell(c.c + Vec2(dx, dy), h)) } }
        }
        return (best.c, max(best.d, 0))
    }

    /// Text height that fits `lines` (character counts) into a circle of radius `r`, capped at `maxHeight`.
    public static func fittedTextHeight(lines: [Int], lineSpacing: Double = 1.4, radius r: Double, maxHeight: Double, minHeight: Double) -> Double {
        let longest = Double(max(lines.max() ?? 1, 1))
        let rows = Double(max(lines.count, 1))
        // Box of width 0.62·h·chars and height h·(1 + spacing·(rows−1)) must fit in the inscribed square-ish region.
        let byWidth = (1.8 * r) / (0.62 * longest)
        let byHeight = (1.6 * r) / (1 + lineSpacing * (rows - 1))
        return max(min(maxHeight, byWidth, byHeight), minHeight)
    }
}
