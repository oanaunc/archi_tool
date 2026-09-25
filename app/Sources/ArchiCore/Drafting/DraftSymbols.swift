// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// MARK: - Multilines (MLINE / MLSTYLE)

/// A multiline style: parallel elements at offsets from the justification line, optional end caps.
public struct MLStyle: Codable, Hashable {
    public struct Element: Codable, Hashable {
        public var offset: Double; public var color: String; public var linetype: String
        public init(offset: Double, color: String = "ByLayer", linetype: String = "ByLayer") { self.offset = offset; self.color = color; self.linetype = linetype }
    }
    public var name: String
    public var description: String
    public var elements: [Element]
    public var startCap: Bool
    public var endCap: Bool
    public init(name: String, description: String = "", elements: [Element], startCap: Bool = false, endCap: Bool = false) {
        self.name = name; self.description = description; self.elements = elements; self.startCap = startCap; self.endCap = endCap
    }
    public static let standard = MLStyle(name: "STANDARD", elements: [Element(offset: 0.5), Element(offset: -0.5)])
    private enum K: String, CodingKey { case name, description, elements, startCap, endCap }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        elements = try c.decodeIfPresent([Element].self, forKey: .elements) ?? MLStyle.standard.elements
        startCap = try c.decodeIfPresent(Bool.self, forKey: .startCap) ?? false
        endCap = try c.decodeIfPresent(Bool.self, forKey: .endCap) ?? false
    }
}

public enum Multiline {
    public static let variable = "MLSTYLES"
    public enum Justification: String, CaseIterable { case top, zero, bottom }

    public static func styles(_ doc: ArchiDocument) -> [MLStyle] {
        var list = VarJSON.load(doc, variable, as: [MLStyle].self) ?? []
        if !list.contains(where: { $0.name.caseInsensitiveCompare("STANDARD") == .orderedSame }) { list.insert(.standard, at: 0) }
        return list
    }
    public static func style(_ n: String, _ doc: ArchiDocument) -> MLStyle? { styles(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    public static func save(_ s: MLStyle, _ doc: inout ArchiDocument) {
        var list = styles(doc).filter { $0.name.caseInsensitiveCompare(s.name) != .orderedSame }
        list.append(s)
        VarJSON.save(list.filter { $0 != .standard }, &doc, variable, empty: list.allSatisfy { $0 == .standard })
    }

    /// Miter offset of a polyline (positive = left of the direction of travel).
    public static func offset(_ pts: [Vec2], _ d: Double, closed: Bool) -> [Vec2] {
        let n = pts.count
        guard n >= 2 else { return pts }
        var out: [Vec2] = []
        for i in 0..<n {
            let hasPrev = closed || i > 0, hasNext = closed || i < n - 1
            let pPrev = pts[(i - 1 + n) % n], p = pts[i], pNext = pts[(i + 1) % n]
            if !hasPrev { out.append(p + (pNext - p).normalized.perp * d); continue }
            if !hasNext { out.append(p + (p - pPrev).normalized.perp * d); continue }
            let n0 = (p - pPrev).normalized.perp, n1 = (pNext - p).normalized.perp
            if let x = GeometryOps.lineIntersection(pPrev + n0 * d, p + n0 * d, p + n1 * d, pNext + n1 * d), x.distance(to: p) < abs(d) * 20 + 1e-9 { out.append(x) }
            else { out.append(p + n0 * d) }
        }
        return out
    }

    /// Element polylines and end caps of a multiline through `pts`.
    public static func geometry(_ pts: [Vec2], style: MLStyle, scale: Double, justification: Justification, closed: Bool) -> [Geometry] {
        guard pts.count >= 2, !style.elements.isEmpty else { return [] }
        let offs = style.elements.map(\.offset)
        let top = offs.max()!, bottom = offs.min()!
        let shift: Double
        switch justification { case .top: shift = -top; case .zero: shift = 0; case .bottom: shift = -bottom }
        var out: [Geometry] = []
        var lines: [[Vec2]] = []
        for e in style.elements {
            let o = offset(pts, (e.offset + shift) * scale, closed: closed)
            lines.append(o)
            out.append(.polyline(PolylineGeom(points: o, closed: closed)))
        }
        if !closed, lines.count >= 2 {
            let hi = lines[offs.firstIndex(of: top)!], lo = lines[offs.firstIndex(of: bottom)!]
            if style.startCap { out.append(.line(LineGeom(hi[0], lo[0]))) }
            if style.endCap { out.append(.line(LineGeom(hi[hi.count - 1], lo[lo.count - 1]))) }
        }
        return out
    }
}

// MARK: - Drafting symbols

public enum DraftSymbols {
    /// North arrow: circle, filled half-arrow and "N". `angle` = direction of north (radians, 90° = up).
    public static func northArrow(center c: Vec2, size: Double, angle: Double) -> [Geometry] {
        let r = size / 2
        let up = Vec2.polar(1, angle), side = up.perp
        let tip = c + up * (r * 0.95), tail = c - up * (r * 0.7)
        let left = tail + side * (r * 0.4), right = tail - side * (r * 0.4)
        let notch = c - up * (r * 0.35)
        let half: [Vec2] = [tip, notch, right]
        return [
            .circle(CircleGeom(c, r)),
            .polyline(PolylineGeom(points: [tip, left, notch, right], closed: true)),
            .hatch(HatchGeom(loops: [half.map { PolyVertex($0) }], pattern: "SOLID")),
            .text(TextGeom(position: c + up * (r * 1.25), height: size * 0.25, content: "N", rotation: angle - .pi / 2, halign: .center, valign: .bottom)),
        ]
    }

    /// Graphic scale bar: `count` segments of `segment` drawing units, alternately filled, with labels in `unitLabel`
    /// (label value = distance × `labelFactor`).
    public static func scaleBar(origin o: Vec2, segment: Double, count: Int, height: Double, labelFactor: Double = 1, unitLabel: String = "", angle: Double = 0) -> [Geometry] {
        guard count >= 1, segment > 0 else { return [] }
        let t = Transform2D.translation(o) * Transform2D.rotation(angle)
        var out: [Geometry] = []
        let w = segment * Double(count)
        out.append(.polyline(PolylineGeom(points: [Vec2(0, 0), Vec2(w, 0), Vec2(w, height), Vec2(0, height)].map(t.apply), closed: true)))
        for k in 0..<count {
            let x0 = segment * Double(k), x1 = x0 + segment
            let box = [Vec2(x0, 0), Vec2(x1, 0), Vec2(x1, height), Vec2(x0, height)].map(t.apply)
            if k % 2 == 0 { out.append(.hatch(HatchGeom(loops: [box.map { PolyVertex($0) }], pattern: "SOLID"))) }
            else { out.append(.line(LineGeom(box[0], box[3]))) }
        }
        let th = height * 0.8
        for k in 0...count {
            let x = segment * Double(k)
            var label = fmt(x * labelFactor, 3)
            if k == count && !unitLabel.isEmpty { label += " " + unitLabel }
            out.append(.text(TextGeom(position: t.apply(Vec2(x, height + th * 0.5)), height: th, content: label, rotation: angle, halign: .center, valign: .bottom)))
        }
        return out
    }

    /// Break line from a to b with a zig-zag symbol of the given size at `at` (fraction along the line), extended past the
    /// ends by `extension`.
    public static func breakLine(_ a: Vec2, _ b: Vec2, size: Double, at: Double = 0.5, extension ext: Double = 0) -> [Vec2] {
        let len = a.distance(to: b)
        guard len > 1e-9 else { return [a, b] }
        let u = (b - a) / len, n = u.perp
        let s = min(size, len * 0.9)
        let m = a + u * (len * min(max(at, 0), 1))
        return [a - u * ext, m - u * (s / 2), m - u * (s / 6) + n * (s / 2), m + u * (s / 6) - n * (s / 2), m + u * (s / 2), b + u * ext]
    }

    /// Parabola with vertex v, focus f (defines axis and focal length), from −halfWidth to +halfWidth across the axis.
    public static func parabola(vertex v: Vec2, focus f: Vec2, halfWidth w: Double, segments: Int = 64) -> [Vec2] {
        let fl = v.distance(to: f)
        guard fl > 1e-12, w > 0 else { return [] }
        let axis = (f - v) / fl, across = axis.perp
        return (0...segments).map { i in
            let t = -w + 2 * w * Double(i) / Double(segments)
            return v + across * t + axis * (t * t / (4 * fl))
        }
    }

    /// One branch of the hyperbola x²/a² − y²/b² = 1 (local axes: x towards the vertex), for |y| ≤ halfHeight.
    public static func hyperbola(center c: Vec2, vertex: Vec2, b: Double, halfHeight h: Double, segments: Int = 64) -> [Vec2] {
        let a = c.distance(to: vertex)
        guard a > 1e-12, b > 1e-12, h > 0 else { return [] }
        let ux = (vertex - c) / a, uy = ux.perp
        let tmax = asinh(h / b)
        return (0...segments).map { i in
            let t = -tmax + 2 * tmax * Double(i) / Double(segments)
            return c + ux * (a * cosh(t)) + uy * (b * sinh(t))
        }
    }
}

// MARK: - Freehand sketch and arc-aligned text

public enum Sketch {
    /// Keeps points at least `increment` apart (SKETCHINC); the last point is always kept.
    public static func filter(_ pts: [Vec2], increment: Double) -> [Vec2] {
        guard let first = pts.first else { return [] }
        var out = [first]
        for p in pts.dropFirst() where p.distance(to: out[out.count - 1]) >= increment { out.append(p) }
        if let l = pts.last, !l.isClose(out[out.count - 1], tol: 1e-12) {
            if out.count > 1 && l.distance(to: out[out.count - 1]) < increment * 0.5 { out[out.count - 1] = l } else { out.append(l) }
        }
        return out
    }
}

public enum ArcText {
    /// Approximate advance of a character as a fraction of the text height.
    public static func advance(_ c: Character) -> Double {
        switch c {
        case " ": return 0.4
        case "i", "l", "j", "1", ".", ",", "'", "!", "|", ":", ";", "I": return 0.35
        case "m", "w", "M", "W", "@": return 0.95
        default: return c.isUppercase || c.isNumber ? 0.72 : 0.6
        }
    }
    /// One text object per character along an arc, centred on the arc's midpoint; `outside` = reads along the convex side.
    public static func layout(_ text: String, arc: ArcGeom, height: Double, outside: Bool = true, offset: Double = 0, spacing: Double = 1) -> [TextGeom] {
        let chars = Array(text)
        guard !chars.isEmpty, arc.radius > 1e-9, height > 0 else { return [] }
        let r = arc.radius + (outside ? offset : -offset)
        guard r > 1e-9 else { return [] }
        let widths = chars.map { advance($0) * height * spacing }
        let total = widths.reduce(0, +)
        let mid = arc.start + arc.sweep / 2
        // Convex side reads clockwise (left to right over the top); concave reads counter-clockwise.
        let dir: Double = outside ? -1 : 1
        var s = -total / 2
        var out: [TextGeom] = []
        for (c, w) in zip(chars, widths) {
            let a = mid + dir * (s + w / 2) / r
            let p = arc.center + Vec2.polar(r, a)
            let rot = outside ? a - .pi / 2 : a + .pi / 2
            if c != " " { out.append(TextGeom(position: p, height: height, content: String(c), rotation: normAngle(rot), halign: .center, valign: outside ? .baseline : .top)) }
            s += w
        }
        return out
    }
}
