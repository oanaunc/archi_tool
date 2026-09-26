// Oanarina Archi Tool — GPL-3.0-or-later
// Walls along free curves (BIM-013): splines and ellipses are approximated by tangent-continuous chains of circular
// arcs (recursive three-point arc fitting within a tolerance), since walls are straight or circular segments.
import Foundation

public enum CurveWalls {
    /// Bulge of the arc from `a` through `m` to `b` (0 when collinear).
    public static func bulge(_ a: Vec2, _ m: Vec2, _ b: Vec2) -> Double {
        guard let arc = CommandHelpers.arcFrom3(a, m, b) else { return 0 }
        let c = arc.center
        let ccw = (m - a).cross(b - m) > 0
        let a1 = (a - c).angle, a3 = (b - c).angle
        let sweep = ccw ? normAngle(a3 - a1) : normAngle(a1 - a3)
        return (ccw ? 1 : -1) * tan(sweep / 4)
    }

    /// Fits circular arcs (and straight runs) to a dense point chain so every input point lies within `tolerance` of
    /// the result. Returns bulged polyline vertices (the last vertex has bulge 0; closed chains end on the first point).
    public static func fitArcs(_ pts0: [Vec2], tolerance: Double, maxSweep: Double = .pi / 2) -> [PolyVertex] {
        var pts: [Vec2] = []
        for p in pts0 where !(pts.last.map { $0.distance(to: p) < 1e-9 } ?? false) { pts.append(p) }
        guard pts.count >= 2 else { return pts.map { PolyVertex($0) } }
        var out: [PolyVertex] = []
        func fits(_ i: Int, _ j: Int) -> Double? {
            let a = pts[i], b = pts[j]
            if j - i == 1 { return 0 }
            let m = pts[(i + j) / 2]
            if let arc = CommandHelpers.arcFrom3(a, m, b) {
                let bl = bulge(a, m, b)
                guard 4 * atan(abs(bl)) <= maxSweep + 1e-9 else { return nil }
                for k in (i + 1)..<j where abs(pts[k].distance(to: arc.center) - arc.radius) > tolerance { return nil }
                // Points must also lie on the arc's side of the chord (not on the complementary arc).
                let side = (b - a).cross(m - a)
                for k in (i + 1)..<j where (b - a).cross(pts[k] - a) * side < -tolerance * a.distance(to: b) { return nil }
                return bl
            }
            // Collinear: a straight run if every point is near the chord.
            for k in (i + 1)..<j where GeometryOps.distance(from: pts[k], toPolyline: [a, b]) > tolerance { return nil }
            return 0
        }
        func fit(_ i: Int, _ j: Int) {
            if let bl = fits(i, j) { out.append(PolyVertex(pts[i], bulge: abs(bl) < 1e-9 ? 0 : bl)); return }
            let m = (i + j) / 2
            fit(i, m); fit(m, j)
        }
        fit(0, pts.count - 1)
        out.append(PolyVertex(pts[pts.count - 1]))
        return out
    }

    /// Wall centre chain for a spline or ellipse entity (nil for other geometry).
    public static func chain(for g: Geometry, doc: ArchiDocument, tolerance: Double) -> [PolyVertex]? {
        switch g {
        case .spline, .ellipse:
            let polys = GeometryOps.tessellate(g, doc: doc).filter { $0.count >= 2 }
            guard let p = polys.max(by: { $0.count < $1.count }) else { return nil }
            let v = fitArcs(p, tolerance: tolerance)
            return v.count >= 2 ? v : nil
        default: return nil
        }
    }
}
