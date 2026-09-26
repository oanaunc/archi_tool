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
        let d = withoutBreaks(d)
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
        let d = withoutBreaks(d)
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

    /// Graphics of a dimension; dimension and extension lines are interrupted at its DIMBREAK gaps.
    public static func primitives(_ d: DimensionGeom, style: DimStyle) -> Primitives {
        let gaps = breaks(d)
        var prim = basePrimitives(withoutBreaks(d), style: style, jogs: jogs(d))
        if !gaps.isEmpty { prim.lines = clip(prim.lines, gaps: gaps) }
        return prim
    }

    static func basePrimitives(_ d: DimensionGeom, style: DimStyle, jogs: [Vec2] = []) -> Primitives {
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
            let jogH = style.textHeight * sc * jogHeightFactor
            /// The dimension line from a to b, with the DIMJOGLINE zig-zag inserted when a jog lies on it.
            func dimLine(_ a: Vec2, _ b: Vec2) -> [Vec2] {
                guard let j = jogs.first else { return [a, b] }
                return jogLine(a, b, at: j, height: jogH)
            }
            if isTick(style) {
                let ext = arr * 0.5
                prim.lines.append(dimLine(d1 - along * ext, d2 + along * ext))
                arrow(&prim, tip: d1, dir: -along, style: style, lineDir: along)
                arrow(&prim, tip: d2, dir: along, style: style, lineDir: along)
            } else if span < arr * 2.5 {
                // Arrows outside the extension lines.
                prim.lines.append(dimLine(d1 - along * (arr * 1.8), d2 + along * (arr * 1.8)))
                arrow(&prim, tip: d1, dir: along, style: style, lineDir: along)
                arrow(&prim, tip: d2, dir: -along, style: style, lineDir: along)
            } else {
                prim.lines.append(dimLine(d1, d2))
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
            if d.kind == .radius, jogs.count >= 2 {
                // DIMJOGGED: the dimension line starts at the overridden centre and has a jog.
                let anchor = jogged(&prim, tip: tip, w: w, radius: r, override: jogs[0], jog: jogs[1], location: loc, style: style)
                placeText(at: anchor, along: w.angle)
                return prim
            }
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

    // MARK: - Jogs (DIMJOGGED, DIMJOGLINE)

    /// Jog height as a multiple of the dimension text height (AutoCAD DIMJOGLINE default 1.5).
    public static var jogHeightFactor = 1.5
    /// Transverse angle of the jogged-radius jog (DIMJOGANG default 45°).
    public static var jogAngle = Double.pi / 4

    /// A polyline from a to b with a zig-zag jog symbol centred on the projection of `j` (clamped inside the line).
    public static func jogLine(_ a: Vec2, _ b: Vec2, at j: Vec2, height h: Double) -> [Vec2] {
        let len = a.distance(to: b)
        guard len > 1e-12, h > 1e-12 else { return [a, b] }
        let u = (b - a) / len, n = u.perp
        let half = min(h / 4, len / 2)
        let s = min(max((j - a).dot(u), half), len - half)
        let m = a + u * s
        return [a, m - u * half, m + n * (h / 2), m - n * (h / 2), m + u * half, b]
    }

    /// Jogged radius graphics: arrow at the curve, a line toward the centre down to the jog, the transverse jog
    /// segment, and a line to the overridden centre. Returns the text anchor.
    static func jogged(_ prim: inout Primitives, tip: Vec2, w: Vec2, radius r: Double, override co: Vec2, jog j: Vec2, location loc: Vec2?, style: DimStyle) -> Vec2 {
        let n = w.perp
        // Offset between the main line (through the tip along w) and the parallel line through the overridden centre.
        let off = (co - tip).dot(n)
        // Jog foot on the main line, between the tip and the overridden centre's projection.
        let coS = (co - tip).dot(w)             // negative: centre side
        var s = (j - tip).dot(w)
        let lo = min(coS, 0), hi = max(coS, 0)
        s = min(max(s, lo), hi)
        let a = tip + w * s
        let run = abs(off) / tan(jogAngle)
        let dirToCentre: Double = coS <= 0 ? -1 : 1
        let b = a + n * off + w * (dirToCentre * run)
        var mainStart = tip
        var anchor = (tip + a) / 2
        if let l = loc, (l - tip).dot(w) > 1e-9 {
            // Text location outside the arc: the line continues outward to it and the arrow points back in.
            mainStart = tip + w * (l - tip).dot(w)
            anchor = (tip + mainStart) / 2
            arrow(&prim, tip: tip, dir: -w, style: style, lineDir: w)
        } else {
            arrow(&prim, tip: tip, dir: w, style: style, lineDir: w)
        }
        prim.lines.append([mainStart, a, b, co])
        return anchor
    }

    /// Jog markers stored on a dimension: zero-radius point pairs after the definition points
    /// (jogged radius: overridden centre then jog location; linear/aligned: jog-line location).
    public static func jogs(_ d: DimensionGeom) -> [Vec2] {
        let n = definitionCount(d.kind)
        var out: [Vec2] = []
        var i = n
        while i + 1 < d.points.count {
            if d.points[i] == d.points[i + 1] { out.append(d.points[i]) }
            i += 2
        }
        return out
    }

    /// The dimension with exactly these jog markers (keeping its breaks).
    public static func withJogs(_ d: DimensionGeom, _ jogs: [Vec2], style: DimStyle) -> DimensionGeom {
        var x = padded(d, style: style)
        guard x.points.count == definitionCount(d.kind) else { return withoutBreaks(d) }
        for g in breaks(d) { x.points.append(g.center); x.points.append(g.center + Vec2(g.radius, 0)) }
        for j in jogs { x.points.append(j); x.points.append(j) }
        return x
    }

    /// Removes the breaks but keeps the jog markers.
    public static func withoutGaps(_ d: DimensionGeom) -> DimensionGeom {
        let js = jogs(d)
        var x = withoutBreaks(d)
        guard !js.isEmpty else { return x }
        while x.points.count < definitionCount(d.kind) { x.points.append(x.points.last ?? .zero) }
        for j in js { x.points.append(j); x.points.append(j) }
        return x
    }

    // MARK: - Dimension breaks (DIMBREAK)

    /// A gap cut out of the dimension and extension lines: everything inside the circle is not drawn.
    public struct DimBreak: Hashable {
        public var center: Vec2; public var radius: Double
        public init(center: Vec2, radius: Double) { self.center = center; self.radius = radius }
    }

    /// Number of definition points of a dimension kind. Points after them encode breaks as pairs
    /// (gap centre, a point on the gap circle), so breaks move, rotate and scale with the dimension.
    public static func definitionCount(_ k: DimKind) -> Int {
        switch k { case .angular, .arcLength: return 4; default: return 3 }
    }
    /// The definition points only (breaks stripped).
    public static func definitionPoints(_ d: DimensionGeom) -> [Vec2] { Array(d.points.prefix(definitionCount(d.kind))) }
    public static func withoutBreaks(_ d: DimensionGeom) -> DimensionGeom {
        guard d.points.count > definitionCount(d.kind) else { return d }
        var x = d; x.points = definitionPoints(d); return x
    }
    /// Break gaps stored on a dimension.
    public static func breaks(_ d: DimensionGeom) -> [DimBreak] {
        let n = definitionCount(d.kind)
        guard d.points.count >= n + 2 else { return [] }
        var out: [DimBreak] = []
        var i = n
        while i + 1 < d.points.count {
            let c = d.points[i], r = c.distance(to: d.points[i + 1])
            if r > 1e-12 { out.append(DimBreak(center: c, radius: r)) }
            i += 2
        }
        return out
    }
    /// Completes missing optional definition points with the values the renderer uses by default, so appending breaks
    /// never changes how the dimension looks.
    public static func padded(_ d: DimensionGeom, style: DimStyle) -> DimensionGeom {
        var x = withoutBreaks(d)
        let p = x.points
        guard p.count >= 2 else { return x }
        let n = definitionCount(d.kind)
        guard p.count < n else { return x }
        let sc = style.scale > 0 ? style.scale : 1
        switch d.kind {
        case .linear, .aligned, .radius, .diameter: x.points.append(p[1])
        case .ordinate: x.points.append(.zero)
        case .angular:
            guard p.count == 3, let s = angularSector(x) else { return x }
            var R = min(p[0].distance(to: p[1]), p[0].distance(to: p[2])) * 0.6
            if R < 1e-9 { R = style.arrowSize * sc * 4 }
            x.points.append(p[0] + Vec2.polar(R, s.start + s.sweep / 2))
        case .arcLength:
            guard p.count == 3 else { return x }
            let start = (p[1] - p[0]).angle, sweep = normAngle((p[2] - p[0]).angle - start)
            var R = p[0].distance(to: p[1]) + style.arrowSize * sc * 3
            if R < 1e-9 { R = style.arrowSize * sc * 4 }
            x.points.append(p[0] + Vec2.polar(R, start + sweep / 2))
        }
        while x.points.count < n { x.points.append(x.points[x.points.count - 1]) }
        return x
    }
    /// The dimension with exactly these break gaps (replacing any previous ones).
    public static func withBreaks(_ d: DimensionGeom, _ gaps: [DimBreak], style: DimStyle) -> DimensionGeom {
        guard !gaps.isEmpty else { return withoutGaps(d) }
        let js = jogs(d)
        var x = padded(d, style: style)
        guard x.points.count == definitionCount(d.kind) else { return withoutBreaks(d) }
        for g in gaps { x.points.append(g.center); x.points.append(g.center + Vec2(g.radius, 0)) }
        for j in js { x.points.append(j); x.points.append(j) }
        return x
    }

    /// Removes the parts of polylines inside any gap circle.
    public static func clip(_ lines: [[Vec2]], gaps: [DimBreak]) -> [[Vec2]] {
        guard !gaps.isEmpty else { return lines }
        var out: [[Vec2]] = []
        for pl in lines {
            guard pl.count >= 2 else { out.append(pl); continue }
            var cur: [Vec2] = []
            func flush() { if cur.count >= 2 { out.append(cur) }; cur = [] }
            for k in 0..<(pl.count - 1) {
                let a = pl[k], b = pl[k + 1], v = b - a
                let vv = v.dot(v)
                // Parameter intervals inside the gaps.
                var cut: [(Double, Double)] = []
                if vv > 1e-24 {
                    for g in gaps {
                        let w = a - g.center
                        let B = 2 * v.dot(w), C = w.dot(w) - g.radius * g.radius
                        let disc = B * B - 4 * vv * C
                        guard disc > 0 else { continue }
                        let sq = disc.squareRoot()
                        let t0 = max(0, (-B - sq) / (2 * vv)), t1 = min(1, (-B + sq) / (2 * vv))
                        if t1 > t0 { cut.append((t0, t1)) }
                    }
                }
                cut.sort { $0.0 < $1.0 }
                var merged: [(Double, Double)] = []
                for c in cut { if let l = merged.last, c.0 <= l.1 { merged[merged.count - 1].1 = max(l.1, c.1) } else { merged.append(c) } }
                var t = 0.0
                for (c0, c1) in merged {
                    if c0 > t + 1e-12 {
                        if cur.isEmpty { cur.append(a + v * t) }
                        cur.append(a + v * c0)
                    }
                    flush()
                    t = c1
                }
                if t < 1 - 1e-12 {
                    if cur.isEmpty { cur.append(a + v * t) }
                    cur.append(b)
                } else { flush() }
            }
            flush()
        }
        return out
    }
}

// MARK: - Fit and text placement (ANN-031)

/// Dimension style layout options beyond `DimStyle`: what moves outside the extension lines when there is not enough
/// room (DIMATFIT) and whether the text sits above the dimension line or centred in a break of it (DIMTAD).
public struct DimLayout: Hashable {
    /// "best" (default placement), "arrows" (move arrows out first), "text" (move text out first), "both".
    public var fit: String
    /// Text centred on the dimension line (the line is broken around it) instead of above it.
    public var textCentered: Bool
    public init(fit: String = "best", textCentered: Bool = false) { self.fit = fit; self.textCentered = textCentered }
    public var isDefault: Bool { fit.lowercased() == "best" && !textCentered }
}

extension DimensionRenderer {
    /// Approximate width of a dimension text (stroke-font metrics).
    public static func textWidth(_ s: String, height: Double) -> Double {
        let widest = s.components(separatedBy: "\n").map { StrokeFont.lineWidth($0) }.max() ?? 0
        return widest * height / StrokeFont.capHeight
    }

    /// Where the parts of a linear/aligned dimension go for a span, text width and arrow size.
    public static func fitPlacement(fit: String, span: Double, textWidth tw: Double, arrow arr: Double) -> (arrowsOutside: Bool, textOutside: Bool) {
        let both = tw + 2 * arr * 1.5
        switch fit.lowercased() {
        case "arrows":
            let ao = span < both
            return (ao, ao && span < tw)
        case "text":
            let to = span < both
            return (to && span < arr * 2.5, to)
        case "both":
            let out = span < both
            return (out, out)
        default:
            return (span < arr * 2.5, false)
        }
    }

    /// Dimension graphics with a layout; linear and aligned dimensions honour fit and centred text, other kinds use
    /// the default placement.
    public static func primitives(_ d: DimensionGeom, style: DimStyle, layout: DimLayout) -> Primitives {
        guard !layout.isDefault, d.kind == .linear || d.kind == .aligned else { return primitives(d, style: style) }
        let gaps = breaks(d)
        var prim = linearPrimitives(withoutBreaks(d), style: style, layout: layout, jogs: jogs(d))
        if !gaps.isEmpty { prim.lines = clip(prim.lines, gaps: gaps) }
        return prim
    }

    static func linearPrimitives(_ d: DimensionGeom, style: DimStyle, layout: DimLayout, jogs: [Vec2]) -> Primitives {
        var prim = Primitives()
        let p = d.points
        guard p.count >= 2 else { return prim }
        let sc = style.scale > 0 ? style.scale : 1
        let th = style.textHeight * sc, arr = style.arrowSize * sc
        let exo = style.extensionOffset * sc, exe = style.extensionExtend * sc, gap = style.textGap * sc
        let text = formatted(d, style: style)
        let p1 = p[0], p2 = p[1]
        let p3 = p.count > 2 ? p[2] : p2
        var u = d.kind == .linear ? linearDirection(d) : (p2 - p1).normalized
        if u.lengthSquared < 1e-18 { u = Vec2(1, 0) }
        let n = u.perp
        let d1 = p1 + n * (p3 - p1).dot(n), d2 = p2 + n * (p3 - p2).dot(n)
        for (pt, dp) in [(p1, d1), (p2, d2)] {
            let v = dp - pt
            let len = v.length
            if len > exo + 1e-9 { let dir = v / len; prim.lines.append([pt + dir * exo, dp + dir * exe]) }
            else if len > 1e-9 { let dir = v / len; prim.lines.append([dp, dp + dir * exe]) }
        }
        let span = d1.distance(to: d2)
        let along = span > 1e-12 ? (d2 - d1) / span : u
        let tw = textWidth(text, height: th) + 2 * gap
        let fit = fitPlacement(fit: layout.fit, span: span, textWidth: tw, arrow: arr)
        let arrowsOut = fit.arrowsOutside && !isTick(style)
        // Dimension line extent.
        var lineStart = d1, lineEnd = d2
        if isTick(style) { lineStart = d1 - along * (arr * 0.5); lineEnd = d2 + along * (arr * 0.5) }
        else if arrowsOut { lineStart = d1 - along * (arr * 1.8); lineEnd = d2 + along * (arr * 1.8) }
        // Text position along the line.
        let r = readable(along.angle)
        let up = Vec2.polar(1, r + .pi / 2)
        var mid = (d1 + d2) / 2
        if fit.textOutside {
            let beyond = (arrowsOut ? arr * 1.8 : arr * 0.5) + gap + tw / 2
            mid = d2 + along * beyond
            lineEnd = mid + along * (layout.textCentered ? tw / 2 : tw / 2)
        }
        let jogH = style.textHeight * sc * jogHeightFactor
        func dimLine(_ a: Vec2, _ b: Vec2) -> [Vec2] {
            guard let j = jogs.first else { return [a, b] }
            return jogLine(a, b, at: j, height: jogH)
        }
        if layout.textCentered {
            // Break the line around the text.
            let half = tw / 2
            let sA = (mid - lineStart).dot(along) - half, sB = (mid - lineStart).dot(along) + half
            let total = (lineEnd - lineStart).dot(along)
            if sA > 1e-9 { prim.lines.append(dimLine(lineStart, lineStart + along * min(sA, total))) }
            if sB < total - 1e-9 { prim.lines.append([lineStart + along * max(sB, 0), lineEnd]) }
            prim.text = TextGeom(position: mid, height: th, content: text, rotation: r, halign: .center, valign: .middle)
        } else {
            prim.lines.append(dimLine(lineStart, lineEnd))
            prim.text = TextGeom(position: mid + up * gap, height: th, content: text, rotation: r, halign: .center, valign: .baseline)
        }
        if isTick(style) || !arrowsOut {
            arrow(&prim, tip: d1, dir: -along, style: style, lineDir: along)
            arrow(&prim, tip: d2, dir: along, style: style, lineDir: along)
        } else {
            arrow(&prim, tip: d1, dir: along, style: style, lineDir: along)
            arrow(&prim, tip: d2, dir: -along, style: style, lineDir: along)
        }
        return prim
    }
}
