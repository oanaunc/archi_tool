// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Turns dimension definitions into lines, filled arrowheads and text (DIMSCALE-aware).
public enum DimensionRenderer {
    public struct Primitives {
        /// Open polylines (dimension/extension lines, ticks, open arrows).
        public var lines: [[Vec2]] = []
        /// Closed filled polygons (arrowheads, dots).
        public var arrows: [[Vec2]] = []
        public var text: TextGeom?
        public init(lines: [[Vec2]] = [], arrows: [[Vec2]] = [], text: TextGeom? = nil) { self.lines = lines; self.arrows = arrows; self.text = text }
    }

    // MARK: Measurement

    /// Direction of the dimension line for a linear dimension (fixed rotation or automatic horizontal/vertical).
    static func linearDirection(_ d: DimensionGeom) -> Vec2 {
        if let r = d.rotation { return Vec2.polar(1, r) }
        guard d.points.count >= 2 else { return Vec2(1, 0) }
        let p1 = d.points[0], p2 = d.points[1]
        let p3 = d.points.count > 2 ? d.points[2] : (p1 + p2) / 2
        let dx = abs(p2.x - p1.x), dy = abs(p2.y - p1.y)
        let inX = p3.x > min(p1.x, p2.x) && p3.x < max(p1.x, p2.x)
        let inY = p3.y > min(p1.y, p2.y) && p3.y < max(p1.y, p2.y)
        if inX && !inY { return Vec2(1, 0) }
        if inY && !inX { return Vec2(0, 1) }
        return dx >= dy ? Vec2(1, 0) : Vec2(0, 1)
    }

    /// Angular sector (start angle, ccw sweep) chosen by the arc location point.
    static func angularSector(_ d: DimensionGeom) -> (start: Double, sweep: Double)? {
        guard d.points.count >= 3 else { return nil }
        let c = d.points[0]
        let a2 = (d.points[1] - c).angle, a3 = (d.points[2] - c).angle
        var sweep = normAngle(a3 - a2)
        var start = a2
        if sweep > .pi { start = a3; sweep = 2 * .pi - sweep } // default: smaller angle
        if d.points.count > 3 {
            let a4 = (d.points[3] - c).angle
            if normAngle(a4 - start) > sweep + 1e-12 { start = normAngle(start + sweep); sweep = 2 * .pi - sweep }
        }
        return (start, sweep)
    }

    /// Raw measured value in drawing units (radians for angular).
    public static func measurement(_ d: DimensionGeom) -> Double {
        let p = d.points
        guard p.count >= 2 else { return 0 }
        switch d.kind {
        case .linear: return abs((p[1] - p[0]).dot(linearDirection(d)))
        case .aligned: return p[0].distance(to: p[1])
        case .radius: return p[0].distance(to: p[1])
        case .diameter: return 2 * p[0].distance(to: p[1])
        case .angular: return angularSector(d)?.sweep ?? 0
        case .ordinate:
            let datum = p.count > 2 ? p[2] : Vec2.zero
            let lead = p[1] - p[0]
            return abs(lead.x) > abs(lead.y) ? p[0].y - datum.y : p[0].x - datum.x
        case .arcLength:
            guard p.count >= 3 else { return 0 }
            let r = p[0].distance(to: p[1])
            return r * normAngle((p[2] - p[0]).angle - (p[1] - p[0]).angle)
        }
    }

    static func number(_ v: Double, decimals: Int) -> String {
        let dec = max(0, min(8, decimals))
        var s = String(format: "%.\(dec)f", v)
        if s.hasPrefix("-"), Double(s) == 0 { s.removeFirst() }
        return s
    }

    /// Displayed text: prefix/suffix, decimals, linear scale, symbols; honours textOverride with "<>".
    public static func formatted(_ d: DimensionGeom, style: DimStyle) -> String {
        let m = measurement(d)
        var core: String
        switch d.kind {
        case .angular: core = number(deg(m), decimals: style.decimals) + "°"
        default: core = number(m * style.linearScale, decimals: style.decimals)
        }
        switch d.kind {
        case .radius: core = "R" + core
        case .diameter: core = "Ø" + core
        case .arcLength: core = "⌒" + core
        default: break
        }
        let measured = style.prefix + core + style.suffix
        if let o = d.textOverride, !o.isEmpty {
            return o.replacingOccurrences(of: "<>", with: measured)
        }
        return measured
    }

    // MARK: Graphics

    /// Readable text angle (−90°, 90°].
    static func readable(_ a: Double) -> Double {
        let n = normAngle(a)
        return (n > .pi / 2 + 1e-9 && n <= 3 * .pi / 2 + 1e-9) ? normAngle(n - .pi) : n
    }

    /// Adds an arrowhead with its tip at `tip`, pointing along `dir`.
    static func arrow(_ prim: inout Primitives, tip: Vec2, dir: Vec2, style: DimStyle, lineDir: Vec2) {
        let a = style.arrowSize * style.scale
        let w = dir.normalized
        guard a > 0, w.lengthSquared > 0 else { return }
        switch style.arrow {
        case .closedFilled: prim.arrows.append(RG.triangleArrow(tip: tip, dir: w, size: a))
        case .open:
            let n = w.perp * (a * 0.27)
            prim.lines.append([tip - w * a + n, tip, tip - w * a - n])
        case .tick, .architecturalTick:
            let s = lineDir.normalized.rotated(by: .pi / 4) * (a / 2)
            prim.lines.append([tip - s, tip + s])
        case .dot: prim.arrows.append(RG.circle(tip, a / 4, segments: 16))
        case .none: break
        }
    }

    static func isTick(_ s: DimStyle) -> Bool { s.arrow == .tick || s.arrow == .architecturalTick }

    public static func primitives(_ d: DimensionGeom, style: DimStyle) -> Primitives {
        var prim = Primitives()
        let p = d.points
        guard p.count >= 2 else { return prim }
        let sc = style.scale > 0 ? style.scale : 1
        let th = style.textHeight * sc, arr = style.arrowSize * sc
        let exo = style.extensionOffset * sc, exe = style.extensionExtend * sc, gap = style.textGap * sc
        let text = formatted(d, style: style)

        func placeText(at mid: Vec2, along dirAngle: Double) {
            let r = readable(dirAngle)
            let up = Vec2.polar(1, r + .pi / 2)
            prim.text = TextGeom(position: mid + up * gap, height: th, content: text, rotation: r, halign: .center, valign: .baseline)
        }

        switch d.kind {
        case .linear, .aligned:
            let p1 = p[0], p2 = p[1]
            let p3 = p.count > 2 ? p[2] : p2
            var u = d.kind == .linear ? linearDirection(d) : (p2 - p1).normalized
            if u.lengthSquared < 1e-18 { u = Vec2(1, 0) }
            let n = u.perp
            let d1 = p1 + n * (p3 - p1).dot(n), d2 = p2 + n * (p3 - p2).dot(n)
            for (pt, dp) in [(p1, d1), (p2, d2)] {
                let v = dp - pt
                let len = v.length
                if len > exo + 1e-9 {
                    let dir = v / len
                    prim.lines.append([pt + dir * exo, dp + dir * exe])
                } else if len > 1e-9 {
                    let dir = v / len
                    prim.lines.append([dp, dp + dir * exe])
                }
            }
            let span = d1.distance(to: d2)
            let along = span > 1e-12 ? (d2 - d1) / span : u
            if isTick(style) {
                let ext = arr * 0.5
                prim.lines.append([d1 - along * ext, d2 + along * ext])
                arrow(&prim, tip: d1, dir: -along, style: style, lineDir: along)
                arrow(&prim, tip: d2, dir: along, style: style, lineDir: along)
            } else if span < arr * 2.5 {
                // Arrows outside the extension lines.
                prim.lines.append([d1 - along * (arr * 1.8), d2 + along * (arr * 1.8)])
                arrow(&prim, tip: d1, dir: along, style: style, lineDir: along)
                arrow(&prim, tip: d2, dir: -along, style: style, lineDir: along)
            } else {
                prim.lines.append([d1, d2])
                arrow(&prim, tip: d1, dir: -along, style: style, lineDir: along)
                arrow(&prim, tip: d2, dir: along, style: style, lineDir: along)
            }
            placeText(at: (d1 + d2) / 2, along: along.angle)

        case .radius, .diameter:
            let c = p[0], onCurve = p[1]
            let r = c.distance(to: onCurve)
            guard r > 1e-12 else { return prim }
            var w = (onCurve - c) / r
            let loc = p.count > 2 ? p[2] : nil
            if let l = loc, l.distance(to: c) > 1e-12 { w = (l - c).normalized }
            let tip = c + w * r
            if d.kind == .diameter {
                let other = c - w * r
                if let l = loc, l.distance(to: c) > r {
                    prim.lines.append([other, l])
                    arrow(&prim, tip: tip, dir: -w, style: style, lineDir: w)
                    arrow(&prim, tip: other, dir: w, style: style, lineDir: w)
                    placeText(at: (tip + l) / 2, along: w.angle)
                } else {
                    prim.lines.append([other, tip])
                    arrow(&prim, tip: tip, dir: w, style: style, lineDir: w)
                    arrow(&prim, tip: other, dir: -w, style: style, lineDir: w)
                    placeText(at: c, along: w.angle)
                }
            } else {
                if let l = loc, l.distance(to: c) > r + 1e-9 {
                    prim.lines.append([tip, l])
                    arrow(&prim, tip: tip, dir: -w, style: style, lineDir: w)
                    placeText(at: (tip + l) / 2, along: w.angle)
                } else {
                    prim.lines.append([c, tip])
                    arrow(&prim, tip: tip, dir: w, style: style, lineDir: w)
                    placeText(at: (c + tip) / 2, along: w.angle)
                }
            }

        case .angular, .arcLength:
            let c = p[0]
            var start: Double, sweep: Double
            var legs: [Vec2]
            if d.kind == .angular {
                guard let s = angularSector(d) else { return prim }
                start = s.start; sweep = s.sweep; legs = [p[1], p[2]]
            } else {
                guard p.count >= 3 else { return prim }
                start = (p[1] - c).angle; sweep = normAngle((p[2] - c).angle - start); legs = [p[1], p[2]]
            }
            guard sweep > 1e-9 else { return prim }
            var R: Double
            if p.count > 3 { R = p[3].distance(to: c) }
            else if d.kind == .arcLength { R = c.distance(to: p[1]) + arr * 3 }
            else { R = min(c.distance(to: p[1]), c.distance(to: p[2])) * 0.6 }
            if R < 1e-9 { R = arr * 4 }
            // Extension lines along each leg / radial direction.
            for (k, ang) in [start, start + sweep].enumerated() {
                let dir = Vec2.polar(1, ang)
                let legPt = legs.min(by: { abs(normAngle(($0 - c).angle - ang + .pi) - .pi) < abs(normAngle(($1 - c).angle - ang + .pi) - .pi) }) ?? legs[k]
                let legLen = legPt.distance(to: c)
                if R > legLen + exo { prim.lines.append([c + dir * (legLen + exo), c + dir * (R + exe)]) }
                else if R < legLen - exo && d.kind == .arcLength { prim.lines.append([c + dir * (legLen - exo), c + dir * (R - exe)]) }
            }
            prim.lines.append(GeometryOps.arcPoints(center: c, radius: R, start: start, sweep: sweep))
            let a0 = c + Vec2.polar(R, start), a1 = c + Vec2.polar(R, start + sweep)
            let t0 = Vec2.polar(1, start - .pi / 2), t1 = Vec2.polar(1, start + sweep + .pi / 2)
            arrow(&prim, tip: a0, dir: t0, style: style, lineDir: t0)
            arrow(&prim, tip: a1, dir: t1, style: style, lineDir: t1)
            let mid = start + sweep / 2
            let tp = c + Vec2.polar(R, mid)
            let r = readable(mid - .pi / 2)
            let outward = Vec2.polar(1, mid)
            let up = Vec2.polar(1, r + .pi / 2)
            let pos = up.dot(outward) >= 0 ? tp + up * gap : tp - up * (th + gap)
            prim.text = TextGeom(position: pos, height: th, content: text, rotation: r, halign: .center, valign: .baseline)

        case .ordinate:
            let f = p[0], end = p[1]
            let lead = end - f
            let horizontalLeader = abs(lead.x) > abs(lead.y)
            let dirSign: Double = horizontalLeader ? (lead.x >= 0 ? 1 : -1) : (lead.y >= 0 ? 1 : -1)
            let axis = horizontalLeader ? Vec2(dirSign, 0) : Vec2(0, dirSign)
            let startPt = f + axis * exo
            // Jogged leader: out along the axis, then to the end point.
            let elbow = horizontalLeader ? Vec2(f.x + lead.x * 0.5, f.y) : Vec2(f.x, f.y + lead.y * 0.5)
            let elbow2 = horizontalLeader ? Vec2(f.x + lead.x * 0.75, end.y) : Vec2(end.x, f.y + lead.y * 0.75)
            prim.lines.append(abs((elbow2 - elbow).cross(axis)) > 1e-9 ? [startPt, elbow, elbow2, end] : [startPt, end])
            let rot = horizontalLeader ? 0.0 : Double.pi / 2
            let pointsForward = dirSign > 0
            prim.text = TextGeom(position: end + axis * gap, height: th, content: text, rotation: rot,
                                 halign: pointsForward ? .left : .right, valign: .middle)
        }
        return prim
    }
}
