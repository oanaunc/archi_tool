// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Drafting display extras stored in entity props, turned into ordinary draw items (so screen, PDF and SVG all show them):
/// gradient hatch fills (banded fills), hatch pattern origin, merged table cells, text background masks and text frames.
///
/// Integration: `DrawListBuilder.items` returns `DraftRendering.items(e, …)` when it is non-nil.
public enum DraftRendering {
    // MARK: Prop keys
    /// Gradient type: LINEAR, CYLINDER, INVCYLINDER, SPHERICAL, INVSPHERICAL, HEMISPHERICAL, INVHEMISPHERICAL, CURVED, INVCURVED.
    public static let gradientProp = "gradient"
    /// Gradient stops: "color1,color2" (ColorRef texts; one colour = tint towards white by `gradientTint`).
    public static let gradientColorsProp = "gradientColors"
    /// Gradient angle in degrees.
    public static let gradientAngleProp = "gradientAngle"
    /// "0" = not centred (the gradient is shifted up and to the left, as in AutoCAD); default centred.
    public static let gradientCenteredProp = "gradientCentered"
    /// Tint for one-colour gradients: 0 = dark (black) … 1 = light (white). Default 1.
    public static let gradientTintProp = "gradientTint"
    /// Hatch pattern origin "x,y" (HPORIGIN).
    public static let hatchOriginProp = "hatchOrigin"
    /// Merged table cell ranges "row,col,rowSpan,colSpan;…" (0-based).
    public static let tableMergeProp = "tableMerge"
    /// Background mask border offset factor (1 = tight; default 1.5 = half a text height around the text).
    public static let textMaskProp = "textMask"
    /// Mask colour: "background" (drawing background: white on paper) or a ColorRef text.
    public static let maskColorProp = "maskColor"
    /// "1" draws a frame around text.
    public static let textFrameProp = "textFrame"

    /// Number of colour bands used to draw a gradient.
    public static var gradientBands = 48
    /// Screen background used for "background" masks (the app sets this to its canvas colour).
    public static var screenBackground = RGBA(hex: "#1E1F22")

    public static let gradientTypes = ["LINEAR", "CYLINDER", "INVCYLINDER", "SPHERICAL", "INVSPHERICAL", "HEMISPHERICAL", "INVHEMISPHERICAL", "CURVED", "INVCURVED"]

    /// Annotation scales an annotative object supports ("1:50;1:100"). With ANNOALLVISIBLE = 0 it is shown only at those scales.
    public static let annoScalesProp = "annoScales"

    /// Whether an object with annotation scales is shown at the current annotation scale (CANNOSCALE / ANNOALLVISIBLE).
    public static func annotationVisible(_ e: Entity, doc: ArchiDocument) -> Bool {
        guard let list = e.props[annoScalesProp], doc.variable("ANNOALLVISIBLE") == "0" else { return true }
        let cur = Annotative.currentScale(doc)
        return list.split(separator: ";").contains { Annotative.factor(String($0)).map { abs($0 - cur) <= 1e-9 * max(1, cur) } ?? false }
    }

    /// Whether the entity carries any extra handled here.
    public static func handles(_ e: Entity) -> Bool {
        if e.props[annoScalesProp] != nil { return true }
        switch e.geometry {
        case .hatch: return e.props[gradientProp] != nil || e.props[hatchOriginProp] != nil
        case .table: return !(e.props[tableMergeProp] ?? "").isEmpty
        case .text: return e.props[textMaskProp] != nil || e.props[textFrameProp] == "1"
        case .leader: return e.props["mleaderstyle"] != nil
        case .point: return true
        default: return false
        }
    }

    /// Draw items for an entity with drafting extras; nil when the default representation applies.
    public static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem]? {
        guard handles(e) else { return nil }
        if !annotationVisible(e, doc: doc) { return [] }
        let solid = StrokeStyle(color: color, lineweight: lineweight)
        switch e.geometry {
        case .hatch(let h): return hatchItems(h, props: e.props, color: color, lineweight: lineweight, options: options)
        case .table(let t): return tableItems(t, merges: merges(e.props[tableMergeProp]), doc: doc, style: solid)
        case .text(let t): return textItems(t, props: e.props, doc: doc, options: options, color: color, lineweight: lineweight)
        case .point(let p):
            let mode = doc.variable("PDMODE").flatMap(Int.init) ?? 0
            guard mode != 0 else { return nil }
            return pointItems(p, mode: mode, size: pointSize(doc), style: solid)
        case .leader(let l):
            guard let n = e.props["mleaderstyle"], let txt = doc.variable("MLSTYLE:" + n),
                  let st = AnnotationToolCommands.MLeaderStyle(name: n, text: txt), st.isCustomGraphics else { return nil }
            return leaderItems(l, style: st, doc: doc, color: color, lineweight: lineweight)
        default: return nil
        }
    }

    // MARK: - Colours

    static func rgba(_ s: String, fallback: RGBA) -> RGBA {
        guard let c = ColorRef.parse(s) else { return fallback }
        switch c {
        case .byLayer, .byBlock: return fallback
        case .aci(let i): return (i == 0 || i == 256) ? fallback : aciColor(i)
        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        }
    }

    public static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        return RGBA(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    /// The two gradient stops of a hatch.
    public static func gradientStops(_ props: [String: String], color: RGBA) -> (RGBA, RGBA) {
        let parts = (props[gradientColorsProp] ?? "").split(separator: ",", omittingEmptySubsequences: true).map { String($0).trimmingCharacters(in: .whitespaces) }
        // "r,g,b" triples are not supported inside the list; colours are names, ACI numbers or #RRGGBB.
        let c1 = parts.first.map { rgba($0, fallback: color) } ?? color
        if parts.count >= 2 { return (c1, rgba(parts[1], fallback: color)) }
        let tint = props[gradientTintProp].flatMap(Double.init) ?? 1
        return (c1, tint >= 0.5 ? mix(c1, .white, (tint - 0.5) * 2) : mix(c1, .black, (0.5 - tint) * 2))
    }

    // MARK: - Gradient

    /// Colour parameter (0 = first stop, 1 = second stop) of a gradient type at linear position t ∈ [0,1] across the fill
    /// (or radial position for spherical types, 0 = centre).
    public static func gradientParameter(_ type: String, _ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch type.uppercased() {
        case "CYLINDER": return 1 - abs(2 * t - 1)
        case "INVCYLINDER": return abs(2 * t - 1)
        case "SPHERICAL", "HEMISPHERICAL": return 1 - t
        case "INVSPHERICAL", "INVHEMISPHERICAL": return t
        case "CURVED": return 1 - (1 - t) * (1 - t)
        case "INVCURVED": return t * t
        default: return t
        }
    }

    static func isRadial(_ type: String) -> Bool {
        let t = type.uppercased(); return t.hasSuffix("SPHERICAL")
    }

    /// Clips a (possibly non-convex) polygon to a convex polygon (Sutherland–Hodgman). Degenerate bridges have no area,
    /// so filling the results of all loops with the even-odd rule gives the exact intersection.
    public static func clip(_ subject: [Vec2], convex: [Vec2]) -> [Vec2] {
        guard subject.count >= 3, convex.count >= 3 else { return [] }
        var clipPoly = convex
        if GeometryOps.signedArea(clipPoly) < 0 { clipPoly.reverse() }
        var out = subject
        for i in 0..<clipPoly.count {
            let a = clipPoly[i], b = clipPoly[(i + 1) % clipPoly.count]
            let input = out
            out = []
            guard !input.isEmpty else { break }
            func inside(_ p: Vec2) -> Bool { (b - a).cross(p - a) >= -1e-12 }
            func cut(_ p: Vec2, _ q: Vec2) -> Vec2 {
                let d1 = (b - a).cross(p - a), d2 = (b - a).cross(q - a)
                let t = d1 / (d1 - d2)
                return p + (q - p) * t
            }
            var prev = input[input.count - 1]
            for cur in input {
                if inside(cur) {
                    if !inside(prev) { out.append(cut(prev, cur)) }
                    out.append(cur)
                } else if inside(prev) { out.append(cut(prev, cur)) }
                prev = cur
            }
        }
        return out.count >= 3 && abs(GeometryOps.signedArea(out)) > 1e-12 ? out : []
    }

    /// Gradient fill as bands of solid colour. Linear types: strips across the gradient direction; spherical types:
    /// concentric discs drawn from the outside in. Every band is clipped to the hatch region.
    public static func gradientFills(loops: [[Vec2]], type: String, angle: Double, centered: Bool, stops: (RGBA, RGBA), bands: Int? = nil) -> [DrawItem] {
        let loops = loops.filter { $0.count >= 3 }
        guard !loops.isEmpty else { return [] }
        let n = max(2, min(bands ?? gradientBands, 512))
        let u = Vec2.polar(1, angle), v = u.perp
        var umin = Double.infinity, umax = -Double.infinity, vmin = Double.infinity, vmax = -Double.infinity
        for l in loops { for p in l { umin = min(umin, p.dot(u)); umax = max(umax, p.dot(u)); vmin = min(vmin, p.dot(v)); vmax = max(vmax, p.dot(v)) } }
        let len = umax - umin, wid = vmax - vmin
        guard len > 1e-12 || wid > 1e-12 else { return [] }
        var out: [DrawItem] = []
        func emit(_ region: [Vec2], _ c: RGBA) {
            let parts = loops.map { clip($0, convex: region) }.filter { !$0.isEmpty }
            if !parts.isEmpty { out.append(.fill(loops: parts, color: c)) }
        }
        let pad = max(len, wid) * 1e-6 + 1e-9
        if isRadial(type) {
            // Centre: middle of the extents (hemispherical: middle of the lower edge); not centred shifts it up-left.
            var cu = (umin + umax) / 2, cv = type.uppercased().hasSuffix("HEMISPHERICAL") ? vmin : (vmin + vmax) / 2
            if !centered { cu -= len / 4; cv += wid / 4 }
            let c = u * cu + v * cv
            var R = 0.0
            for l in loops { for p in l { R = max(R, p.distance(to: c)) } }
            guard R > 1e-12 else { return [] }
            for k in 0..<n {
                let r = R * (1 - Double(k) / Double(n)) + (k == 0 ? pad : 0)
                let tMid = (1 - (Double(k) + 0.5) / Double(n))
                let segs = 96
                let disc = (0..<segs).map { c + Vec2.polar(r / cos(.pi / Double(segs)), 2 * .pi * Double($0) / Double(segs)) }
                emit(disc, mix(stops.0, stops.1, gradientParameter(type, tMid)))
            }
        } else {
            for k in 0..<n {
                let a = umin + len * Double(k) / Double(n) - (k == 0 ? pad : 0)
                let b = umin + len * Double(k + 1) / Double(n) + (k == n - 1 ? pad : 0)
                let tMid = (Double(k) + 0.5) / Double(n)
                // Not centred: the colour transition is shifted towards the start (reaches the second stop at 75 %).
                let tt = centered ? tMid : min(tMid / 0.75, 1)
                let strip = [u * a + v * (vmin - pad), u * b + v * (vmin - pad), u * b + v * (vmax + pad), u * a + v * (vmax + pad)]
                emit(strip, mix(stops.0, stops.1, gradientParameter(type, tt)))
            }
        }
        return out
    }

    // MARK: - Hatch

    public static func origin(_ props: [String: String]) -> Vec2? {
        guard let s = props[hatchOriginProp] else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return p.count == 2 ? Vec2(p[0], p[1]) : nil
    }

    public static func hatchItems(_ h: HatchGeom, props: [String: String], color: RGBA, lineweight: Double, options: DrawOptions) -> [DrawItem] {
        let loops = h.loops.map { RG.dedupe(GeometryOps.polylinePoints($0, closed: true), closed: true) }.filter { $0.count >= 3 }
        guard !loops.isEmpty else { return [] }
        if let type = props[gradientProp] {
            let ang = rad(props[gradientAngleProp].flatMap(Double.init) ?? 0)
            return gradientFills(loops: loops, type: type, angle: ang, centered: props[gradientCenteredProp] != "0", stops: gradientStops(props, color: color))
        }
        if h.pattern.uppercased() == "SOLID" {
            let fc = h.fill.map { rgba($0.text, fallback: color) } ?? color
            return [.fill(loops: loops, color: fc)]
        }
        var out: [DrawItem] = []
        if let bg = h.fill { out.append(.fill(loops: loops, color: rgba(bg.text, fallback: color))) }
        let lines = HatchPatterns.lines(loops: loops, pattern: h.pattern, scale: h.scale, angle: h.angle, origin: origin(props) ?? .zero)
        out += lines.map { .stroke(points: $0, closed: false, style: StrokeStyle(color: color, lineweight: min(lineweight, 0.18))) }
        return out
    }

    // MARK: - Tables with merged cells

    public struct Merge: Hashable {
        public var row: Int, col: Int, rowSpan: Int, colSpan: Int
        public init(row: Int, col: Int, rowSpan: Int, colSpan: Int) { self.row = row; self.col = col; self.rowSpan = rowSpan; self.colSpan = colSpan }
        public func contains(_ r: Int, _ c: Int) -> Bool { r >= row && r < row + rowSpan && c >= col && c < col + colSpan }
        public var text: String { "\(row),\(col),\(rowSpan),\(colSpan)" }
    }

    public static func merges(_ s: String?) -> [Merge] {
        (s ?? "").split(separator: ";").compactMap { part in
            let v = part.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count == 4, v[0] >= 0, v[1] >= 0, v[2] >= 1, v[3] >= 1, v[2] * v[3] > 1 else { return nil }
            return Merge(row: v[0], col: v[1], rowSpan: v[2], colSpan: v[3])
        }
    }
    public static func mergeText(_ m: [Merge]) -> String { m.map(\.text).joined(separator: ";") }

    /// Adds a merge of the given range, absorbing merges it overlaps. Returns nil if the range is outside the table.
    public static func merged(_ existing: [Merge], adding m: Merge, rows: Int, cols: Int) -> [Merge]? {
        guard m.row >= 0, m.col >= 0, m.rowSpan >= 1, m.colSpan >= 1, m.row + m.rowSpan <= rows, m.col + m.colSpan <= cols, m.rowSpan * m.colSpan > 1 else { return nil }
        var r0 = m.row, c0 = m.col, r1 = m.row + m.rowSpan, c1 = m.col + m.colSpan
        var keep = existing
        var changed = true
        while changed {
            changed = false
            for (i, x) in keep.enumerated() where x.row < r1 && x.row + x.rowSpan > r0 && x.col < c1 && x.col + x.colSpan > c0 {
                r0 = min(r0, x.row); c0 = min(c0, x.col); r1 = max(r1, x.row + x.rowSpan); c1 = max(c1, x.col + x.colSpan)
                keep.remove(at: i); changed = true; break
            }
        }
        return keep + [Merge(row: r0, col: c0, rowSpan: r1 - r0, colSpan: c1 - c0)]
    }

    /// The merge containing a cell, if any.
    public static func merge(at r: Int, _ c: Int, in m: [Merge]) -> Merge? { m.first { $0.contains(r, c) } }

    public static func tableItems(_ tb: TableGeom, merges m: [Merge], doc: ArchiDocument, style: StrokeStyle) -> [DrawItem] {
        let rows = tb.cells.count, cols = tb.columnWidths.count
        let w = tb.columnWidths.reduce(0, +)
        guard w > 0, rows > 0, cols > 0, tb.rowHeight > 0 else { return [] }
        let o = tb.origin, rh = tb.rowHeight, h = rh * Double(rows)
        var xs = [0.0]; for cw in tb.columnWidths { xs.append(xs[xs.count - 1] + cw) }
        var out: [DrawItem] = [.stroke(points: [o, o + Vec2(w, 0), o + Vec2(w, -h), o + Vec2(0, -h)], closed: true, style: style)]
        // Horizontal lines between rows r-1 and r, broken where a merge spans across them.
        for r in 1..<max(rows, 1) {
            let y = -rh * Double(r)
            var start: Double? = nil
            for c in 0..<cols {
                let hidden = m.contains { $0.row < r && $0.row + $0.rowSpan > r && c >= $0.col && c < $0.col + $0.colSpan }
                if hidden { if let s = start { out.append(.stroke(points: [o + Vec2(s, y), o + Vec2(xs[c], y)], closed: false, style: style)); start = nil } }
                else if start == nil { start = xs[c] }
            }
            if let s = start { out.append(.stroke(points: [o + Vec2(s, y), o + Vec2(w, y)], closed: false, style: style)) }
        }
        // Vertical lines between columns c-1 and c.
        for c in 1..<max(cols, 1) {
            let x = xs[c]
            var start: Int? = nil
            for r in 0..<rows {
                let hidden = m.contains { $0.col < c && $0.col + $0.colSpan > c && r >= $0.row && r < $0.row + $0.rowSpan }
                if hidden { if let s = start { out.append(.stroke(points: [o + Vec2(x, -rh * Double(s)), o + Vec2(x, -rh * Double(r))], closed: false, style: style)); start = nil } }
                else if start == nil { start = r }
            }
            if let s = start { out.append(.stroke(points: [o + Vec2(x, -rh * Double(s)), o + Vec2(x, -h)], closed: false, style: style)) }
        }
        // Cell text: covered cells are skipped; a merged cell's text is centred vertically (and horizontally when it spans columns).
        for (ri, row) in tb.cells.enumerated() {
            for ci in 0..<min(cols, row.count) where !row[ci].isEmpty {
                let mg = merge(at: ri, ci, in: m)
                if let g = mg, g.row != ri || g.col != ci { continue }
                let rs = mg?.rowSpan ?? 1, cs = mg?.colSpan ?? 1
                let x0 = xs[ci], x1 = xs[min(ci + cs, cols)]
                let yMid = -rh * (Double(ri) + Double(rs) / 2)
                var t: TextGeom
                if cs > 1 {
                    t = TextGeom(position: o + Vec2((x0 + x1) / 2, yMid), height: tb.textHeight, content: row[ci], halign: .center, valign: .middle)
                } else {
                    t = TextGeom(position: o + Vec2(x0 + min(tb.textHeight * 0.5, (x1 - x0) * 0.1), yMid), height: tb.textHeight, content: row[ci], valign: .middle)
                }
                t.style = "Standard"
                out += DrawListBuilder.textItems(t, doc: doc, color: style.color)
            }
        }
        return out
    }

    // MARK: - Point style (PDMODE / PDSIZE)

    /// Point symbol size in drawing units: PDSIZE > 0 is absolute; 0 or negative uses a size relative to the text height
    /// (|PDSIZE| % of 20 text heights, 5 % by default).
    public static func pointSize(_ doc: ArchiDocument) -> Double {
        let v = doc.variable("PDSIZE").flatMap(Double.init) ?? 0
        if v > 0 { return v }
        let th = doc.variable("TEXTSIZE").flatMap(Double.init) ?? 250 / doc.units.mm
        let pct = v < 0 ? -v : 5
        return th * 20 * pct / 100
    }

    /// PDMODE symbols: 0 dot, 1 nothing, 2 plus, 3 cross, 4 tick up; +32 circle, +64 square.
    public static func pointItems(_ p: Vec2, mode: Int, size: Double, style: StrokeStyle) -> [DrawItem] {
        let h = size / 2
        var out: [DrawItem] = []
        switch mode % 32 {
        case 0: out.append(.stroke(points: [p, p + Vec2(1e-3, 0)], closed: false, style: style))
        case 1: break
        case 2:
            out.append(.stroke(points: [p - Vec2(h, 0), p + Vec2(h, 0)], closed: false, style: style))
            out.append(.stroke(points: [p - Vec2(0, h), p + Vec2(0, h)], closed: false, style: style))
        case 3:
            out.append(.stroke(points: [p - Vec2(h, h), p + Vec2(h, h)], closed: false, style: style))
            out.append(.stroke(points: [p + Vec2(-h, h), p + Vec2(h, -h)], closed: false, style: style))
        default: out.append(.stroke(points: [p, p + Vec2(0, h)], closed: false, style: style))
        }
        if mode & 32 != 0 { out.append(.stroke(points: RG.circle(p, h, segments: 32), closed: true, style: style)) }
        if mode & 64 != 0 { out.append(.stroke(points: [p + Vec2(-h, -h), p + Vec2(h, -h), p + Vec2(h, h), p + Vec2(-h, h)], closed: true, style: style)) }
        return out
    }

    // MARK: - Styled multileaders

    static func leaderItems(_ l: LeaderGeom, style st: AnnotationToolCommands.MLeaderStyle, doc: ArchiDocument, color: RGBA, lineweight: Double) -> [DrawItem] {
        guard l.points.count >= 2 else { return [] }
        let solid = StrokeStyle(color: color, lineweight: lineweight)
        var pts = l.points
        let last = pts[pts.count - 1], prev = pts[pts.count - 2]
        let right = last.x >= prev.x
        if st.landing > 0 { pts.append(last + Vec2(right ? st.landing : -st.landing, 0)) }
        var out: [DrawItem] = [.stroke(points: pts, closed: false, style: solid)]
        let ds = doc.dimStyle
        let a = st.arrowSize > 0 ? st.arrowSize : (ds.arrowSize * ds.scale > 0 ? ds.arrowSize * ds.scale : l.textHeight)
        let tip = pts[0], w = (pts[0] - pts[1]).normalized
        switch st.arrow {
        case "open":
            let n = w.perp * (a * 0.27)
            out.append(.stroke(points: [tip - w * a + n, tip, tip - w * a - n], closed: false, style: solid))
        case "dot": out.append(.fill(loops: [RG.circle(tip, a / 4, segments: 16)], color: color))
        case "tick":
            let s = w.rotated(by: .pi / 4) * (a / 2)
            out.append(.stroke(points: [tip - s, tip + s], closed: false, style: solid))
        case "none": break
        default: out.append(.fill(loops: [RG.triangleArrow(tip: tip, dir: w, size: a)], color: color))
        }
        guard !l.text.isEmpty else { return out }
        let end = pts[pts.count - 1]
        var t = TextGeom(position: end + Vec2(right ? l.textHeight * 0.5 : -l.textHeight * 0.5, 0), height: l.textHeight, content: l.text,
                         halign: right ? .left : .right, valign: .middle)
        t.style = "Standard"
        out += DrawListBuilder.textItems(t, doc: doc, color: color)
        if st.frame { out.append(.stroke(points: textBox(t, doc: doc, factor: 1.35), closed: true, style: solid)) }
        return out
    }

    // MARK: - Text masks and frames

    /// The rectangle around the rendered text, grown by the mask border offset (factor 1 = tight, 1.5 = +0.5 h).
    public static func textBox(_ t: TextGeom, doc: ArchiDocument, factor: Double) -> [Vec2] {
        let items = DrawListBuilder.textItems(t, doc: doc, color: .white)
        let rot = Transform2D.rotation(-t.rotation) * Transform2D.translation(-t.position)
        var b = BBox2.empty
        for it in items { if case .text(let lt, _, _) = it { GeometryOps.textBoxCorners(lt).forEach { b.add(rot.apply($0)) } } }
        if b.isEmpty { GeometryOps.textBoxCorners(t).forEach { b.add(rot.apply($0)) } }
        let h = t.height > 0 ? t.height : 2.5
        let m = max(factor - 1, 0) * h
        let back = Transform2D.translation(t.position) * Transform2D.rotation(t.rotation)
        return [Vec2(b.min.x - m, b.min.y - m), Vec2(b.max.x + m, b.min.y - m), Vec2(b.max.x + m, b.max.y + m), Vec2(b.min.x - m, b.max.y + m)].map(back.apply)
    }

    public static func textItems(_ t: TextGeom, props: [String: String], doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem] {
        var out: [DrawItem] = []
        let text = DrawListBuilder.textItems(t, doc: doc, color: color)
        if let f = props[textMaskProp] {
            let factor = Double(f).map { $0 > 0 ? $0 : 1.5 } ?? 1.5
            let mc = props[maskColorProp] ?? "background"
            let fill: RGBA = mc.lowercased() == "background" ? (options.forPaper ? DrawListBuilder.maskWhite : screenBackground) : rgba(mc, fallback: color)
            out.append(.fill(loops: [textBox(t, doc: doc, factor: factor)], color: fill))
        }
        out += text
        if props[textFrameProp] == "1" {
            let factor = props[textMaskProp].flatMap(Double.init) ?? 1.35
            out.append(.stroke(points: textBox(t, doc: doc, factor: max(factor, 1)), closed: true, style: StrokeStyle(color: color, lineweight: lineweight)))
        }
        return out
    }
}
