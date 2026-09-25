// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Small 2D polygon utilities shared by the plan, hatch and elevation renderers.
enum RG {
    /// Even-odd containment test against several loops.
    static func inside(_ p: Vec2, _ loops: [[Vec2]]) -> Bool {
        var inside = false
        for l in loops where l.count >= 3 && GeometryOps.pointInPolygon(p, l) { inside.toggle() }
        return inside
    }

    /// Parts of segment a→b inside the even-odd region of `loops`.
    static func clipSegment(_ a: Vec2, _ b: Vec2, _ loops: [[Vec2]]) -> [(Vec2, Vec2)] {
        let d = b - a
        guard d.lengthSquared > 1e-18 else { return [] }
        var ts: [Double] = [0, 1]
        for l in loops where l.count >= 2 {
            for i in 0..<l.count {
                let p = l[i], q = l[(i + 1) % l.count]
                let e = q - p
                let den = d.cross(e)
                if abs(den) < 1e-14 { continue }
                let t = (p - a).cross(e) / den, u = (p - a).cross(d) / den
                if t > 0, t < 1, u >= -1e-12, u <= 1 + 1e-12 { ts.append(t) }
            }
        }
        ts.sort()
        var out: [(Vec2, Vec2)] = []
        for i in 0..<(ts.count - 1) {
            let t0 = ts[i], t1 = ts[i + 1]
            if t1 - t0 < 1e-12 { continue }
            if inside(a + d * ((t0 + t1) / 2), loops) {
                if let last = out.last, last.1.isClose(a + d * t0, tol: 1e-9) { out[out.count - 1].1 = a + d * t1 }
                else { out.append((a + d * t0, a + d * t1)) }
            }
        }
        return out
    }

    /// Clips a polyline to the region, returning the inside pieces.
    static func clipPolyline(_ pts: [Vec2], _ loops: [[Vec2]]) -> [[Vec2]] {
        var out: [[Vec2]] = []
        guard pts.count >= 2 else { return out }
        for i in 0..<(pts.count - 1) {
            for (p, q) in clipSegment(pts[i], pts[i + 1], loops) {
                if var last = out.last, let lp = last.last, lp.isClose(p, tol: 1e-9) { last.append(q); out[out.count - 1] = last }
                else { out.append([p, q]) }
            }
        }
        return out
    }

    /// Keeps the part of a convex/concave polygon where n·p <= c (Sutherland–Hodgman).
    static func clipHalfPlane(_ poly: [Vec2], normal n: Vec2, _ c: Double) -> [Vec2] {
        guard poly.count >= 3 else { return [] }
        var out: [Vec2] = []
        for i in 0..<poly.count {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let dp = n.dot(p) - c, dq = n.dot(q) - c
            if dp <= 1e-12 { out.append(p) }
            if (dp < -1e-12 && dq > 1e-12) || (dp > 1e-12 && dq < -1e-12) {
                let t = dp / (dp - dq)
                out.append(p + (q - p) * t)
            }
        }
        return dedupe(out, closed: true)
    }

    static func dedupe(_ pts: [Vec2], closed: Bool, tol: Double = 1e-9) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where !(out.last?.isClose(p, tol: tol) ?? false) { out.append(p) }
        if closed, out.count > 1, out[0].isClose(out[out.count - 1], tol: tol) { out.removeLast() }
        return out
    }

    /// Offsets a closed polygon outward by `d` (negative = inward) with mitred corners.
    static func offsetPolygon(_ poly0: [Vec2], _ d: Double) -> [Vec2] {
        var poly = dedupe(poly0, closed: true)
        guard poly.count >= 3, abs(d) > 0 else { return poly }
        if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
        let n = poly.count
        var out: [Vec2] = []
        for i in 0..<n {
            let p0 = poly[(i - 1 + n) % n], p1 = poly[i], p2 = poly[(i + 1) % n]
            let n0 = -(p1 - p0).normalized.perp, n1 = -(p2 - p1).normalized.perp
            let a0 = p0 + n0 * d, a1 = p1 + n0 * d, b0 = p1 + n1 * d, b1 = p2 + n1 * d
            if let x = GeometryOps.lineIntersection(a0, a1, b0, b1), x.distance(to: p1) < abs(d) * 6 { out.append(x) }
            else { out.append(p1 + (n0 + n1).normalized * d) }
        }
        return out
    }

    static func circle(_ c: Vec2, _ r: Double, segments: Int = 0) -> [Vec2] {
        var pts = GeometryOps.arcPoints(center: c, radius: r, start: 0, sweep: 2 * .pi)
        if segments > 0 { pts = (0..<segments).map { c + Vec2.polar(r, 2 * .pi * Double($0) / Double(segments)) } }
        else { pts.removeLast() }
        return pts
    }

    static func convexHull(_ pts0: [Vec2]) -> [Vec2] {
        let pts = pts0.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count >= 3 else { return pts }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for p in pts {
            while lower.count >= 2 && (lower[lower.count - 1] - lower[lower.count - 2]).cross(p - lower[lower.count - 2]) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in pts.reversed() {
            while upper.count >= 2 && (upper[upper.count - 1] - upper[upper.count - 2]).cross(p - upper[upper.count - 2]) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    static func isConvex(_ poly: [Vec2]) -> Bool {
        let n = poly.count
        guard n >= 3 else { return false }
        var sign = 0
        for i in 0..<n {
            let c = (poly[(i + 1) % n] - poly[i]).cross(poly[(i + 2) % n] - poly[(i + 1) % n])
            if abs(c) < 1e-9 { continue }
            let s = c > 0 ? 1 : -1
            if sign == 0 { sign = s } else if s != sign { return false }
        }
        return true
    }

    /// Distance from a point to a draw item (0 inside fills).
    static func distance(_ p: Vec2, _ item: DrawItem) -> Double {
        switch item {
        case .stroke(let pts, let closed, _):
            return GeometryOps.distance(from: p, toPolyline: closed && pts.count > 2 ? pts + [pts[0]] : pts)
        case .fill(let loops, _):
            if inside(p, loops) { return 0 }
            return loops.map { GeometryOps.distance(from: p, toPolyline: $0 + ($0.first.map { [$0] } ?? [])) }.min() ?? .infinity
        case .text(let t, _, _):
            let box = GeometryOps.textBoxCorners(t)
            if GeometryOps.pointInPolygon(p, box) { return 0 }
            return GeometryOps.distance(from: p, toPolyline: box + [box[0]])
        case .image(let im):
            let t = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
            let box = [Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map(t.apply)
            if GeometryOps.pointInPolygon(p, box) { return 0 }
            return GeometryOps.distance(from: p, toPolyline: box + [box[0]])
        }
    }

    /// Filled arrowhead / symbol helpers.
    static func triangleArrow(tip: Vec2, dir: Vec2, size: Double) -> [Vec2] {
        let w = dir.normalized, n = w.perp
        return [tip, tip - w * size + n * (size / 6), tip - w * size - n * (size / 6)]
    }
}
