// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Exact measurement services (SYS-006): bulge-aware polyline length and area, analytic ellipse perimeter and
/// region / curve centroids for every geometry kind. `GeometryOps.length` and `GeometryOps.area` use these, so
/// LIST, AREA, MEASUREGEOM, fields and schedules report exact values instead of tessellation approximations.
extension GeometryOps {
    /// Exact length of a polyline including bulge (arc) segments.
    public static func polylineLength(_ pl: PolylineGeom) -> Double {
        let v = pl.vertices
        guard v.count > 1 else { return 0 }
        let n = pl.closed ? v.count : v.count - 1
        var total = 0.0
        for i in 0..<n {
            let a = v[i], b = v[(i + 1) % v.count]
            let chord = a.p.distance(to: b.p)
            if abs(a.bulge) > 1e-12, chord > geomEpsilon {
                let theta = 4 * atan(abs(a.bulge))
                total += chord / (2 * sin(theta / 2)) * theta
            } else { total += chord }
        }
        return total
    }

    /// Exact signed area (counter-clockwise positive) of a closed vertex loop with bulges: the straight-chord polygon
    /// plus the circular segment of every arc (a positive bulge turns counter-clockwise and adds area to a CCW loop).
    public static func signedArea(_ v: [PolyVertex]) -> Double {
        guard v.count >= 2 else { return 0 }
        var a = 0.0
        for i in 0..<v.count {
            let p = v[i], q = v[(i + 1) % v.count]
            a += p.p.cross(q.p) / 2
            if abs(p.bulge) > 1e-12 {
                let chord = p.p.distance(to: q.p)
                guard chord > geomEpsilon else { continue }
                let theta = 4 * atan(abs(p.bulge))
                let r = chord / (2 * sin(theta / 2))
                a += (p.bulge > 0 ? 1 : -1) * r * r / 2 * (theta - sin(theta))
            }
        }
        return a
    }

    /// Perimeter of an ellipse (Ramanujan's second approximation; relative error < 1e-9 for ratio ≥ 0.1) or,
    /// for elliptical arcs, the numerically integrated arc length.
    public static func ellipseLength(_ e: EllipseGeom) -> Double {
        let a = e.majorAxis.length, b = a * abs(e.ratio)
        guard a > geomEpsilon else { return 0 }
        if e.isFull {
            let h = pow(a - b, 2) / pow(a + b, 2)
            return .pi * (a + b) * (1 + 3 * h / (10 + (4 - 3 * h).squareRoot()))
        }
        var sweep = e.end - e.start
        while sweep <= 0 { sweep += 2 * .pi }
        // Composite Simpson on |r'(t)| = sqrt(a² sin² t + b² cos² t).
        let n = 512
        let hstep = sweep / Double(n)
        func f(_ t: Double) -> Double { (a * a * sin(t) * sin(t) + b * b * cos(t) * cos(t)).squareRoot() }
        var s = f(e.start) + f(e.start + sweep)
        for i in 1..<n { s += f(e.start + Double(i) * hstep) * (i % 2 == 1 ? 4 : 2) }
        return s * hstep / 3
    }

    /// Loops of a hatch classified by even-odd nesting (islands inside holes count again), with exact areas.
    public static func hatchRegions(_ h: HatchGeom) -> [(area: Double, centroid: Vec2, hole: Bool)] {
        let pts = h.loops.map { polylinePoints($0, closed: true) }
        return h.loops.indices.compactMap { i -> (Double, Vec2, Bool)? in
            guard pts[i].count >= 3 else { return nil }
            let a = abs(signedArea(h.loops[i]))
            guard a > geomEpsilon else { return nil }
            // Test point: a vertex of the loop nudged inside it is unnecessary for even-odd depth — use the first vertex
            // and count the other loops strictly containing it.
            let probe = pts[i][0]
            let depth = pts.indices.filter { $0 != i && pts[$0].count >= 3 && pointInPolygon(probe, pts[$0]) }.count
            return (a, centroid(pts[i]), depth % 2 == 1)
        }
    }

    /// Centroid of a region loop given by tessellated points (area-weighted), with holes subtracted.
    public static func regionCentroid(outer: [Vec2], holes: [[Vec2]] = []) -> Vec2 {
        func part(_ l: [Vec2]) -> (Double, Vec2) { let a = abs(signedArea(l)); return (a, centroid(l)) }
        let o = part(outer)
        var area = o.0, moment = o.1 * o.0
        for h in holes { let p = part(h); area -= p.0; moment = moment - p.1 * p.0 }
        guard area > geomEpsilon else { return o.1 }
        return moment / area
    }

    /// Length-weighted centroid of open curves.
    public static func curveCentroid(_ polylines: [[Vec2]]) -> Vec2? {
        var total = 0.0, m = Vec2.zero
        var pts: [Vec2] = []
        for pl in polylines {
            pts += pl
            for (p, q) in zip(pl, pl.dropFirst()) { let l = p.distance(to: q); total += l; m += (p + q) / 2 * l }
        }
        if total > geomEpsilon { return m / total }
        return pts.isEmpty ? nil : pts.reduce(.zero, +) / Double(pts.count)
    }

    /// Centroid of a geometry: the area centroid of closed shapes (circle, full ellipse, closed polyline / spline,
    /// hatch with holes), the arc-length centroid of open curves, the insertion point of point-like objects.
    public static func centroid(_ g: Geometry, doc: ArchiDocument?) -> Vec2? {
        switch g {
        case .point(let p): return p
        case .circle(let c): return c.center
        case .ellipse(let e) where e.isFull: return e.center
        case .arc(let a):
            // Centroid of a circular arc (curve): distance 2 r sin(φ/2) / φ from the centre along the bisector.
            let phi = a.sweep
            let d = phi > 1e-12 ? 2 * a.radius * sin(phi / 2) / phi : a.radius
            return a.center + Vec2.polar(d, a.start + phi / 2)
        case .polyline(let p) where p.closed && p.vertices.count >= 3:
            return regionCentroid(outer: polylinePoints(p))
        case .spline(let s) where s.closed:
            return regionCentroid(outer: splinePoints(s))
        case .hatch(let h):
            let parts = hatchRegions(h)
            var area = 0.0, m = Vec2.zero
            for p in parts { let w = p.hole ? -p.area : p.area; area += w; m += p.centroid * w }
            guard !parts.isEmpty else { return nil }
            return abs(area) > geomEpsilon ? m / area : parts[0].centroid
        case .text, .insert, .image, .table, .solid:
            let b = bounds(g, doc: doc)
            return b.isEmpty ? nil : (b.min + b.max) / 2
        default:
            return curveCentroid(tessellate(g, doc: doc))
        }
    }
}
