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
    /// Multiline text columns "count,gutter[,height]" (height 0 = balanced static columns, > 0 = dynamic: fill each column
    /// to that height). The text position is the top-left corner of the first column.
    public static let textColumnsProp = "textColumns"

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
        case .hatch: return e.props[gradientProp] != nil || e.props[hatchOriginProp] != nil || e.props[HatchPatterns.patternTypeProp] != nil
        case .table: return !(e.props[tableMergeProp] ?? "").isEmpty || e.props[TableStyle.prop] != nil
        case .text(let t): return e.props[textMaskProp] != nil || e.props[textFrameProp] == "1" || e.props[textColumnsProp] != nil || TextStacks.hasStack(t.content)
        case .leader: return e.props["mleaderstyle"] != nil
        case .point: return true
        case .insert: return BlockClip.active(e)
        case .dimension: return DimExtras.has(e)
        case .image: return ImageDisplay.active(e)
        default: return false
        }
    }

    /// Draw items for an entity with drafting extras; nil when the default representation applies.
    public static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem]? {
        if let g = GraphicStyles.items(e, doc: doc, options: options, color: color, lineweight: lineweight) { return g }
        if let t = Transparency.items(e, doc: doc, options: options, color: color, lineweight: lineweight) { return t }
        if let c = ComplexLinetypes.items(e, doc: doc, options: options, color: color, lineweight: lineweight) { return c }
        var custom = false
        if case .text(let t) = e.geometry, e.props["tagOf"] == nil, TextStyleFonts.drawsStrokes(t, doc: doc) { custom = true }
        if case .dimension(let d) = e.geometry, DimStyleExtras.needsCustomRendering(e, d, doc: doc) { custom = true }
        guard custom || handles(e) else { return nil }
        if !annotationVisible(e, doc: doc) { return [] }
        let solid = StrokeStyle(color: color, lineweight: lineweight)
        switch e.geometry {
        case .hatch(let h): return hatchItems(h, props: e.props, color: color, lineweight: lineweight, options: options, doc: doc)
        case .table(let t):
            let ts = TableStyle.of(e, doc)
            var m = merges(e.props[tableMergeProp])
            if let tm = ts?.titleMerge(columns: t.columnWidths.count), !m.contains(where: { $0.row == 0 }) { m.append(tm) }
            return tableItems(t, merges: m, doc: doc, style: solid, tableStyle: ts)
        case .text(let t): return textItems(t, props: e.props, doc: doc, options: options, color: color, lineweight: lineweight)
        case .point(let p):
            let mode = doc.variable("PDMODE").flatMap(Int.init) ?? 0
            guard mode != 0 else { return nil }
            return pointItems(p, mode: mode, size: pointSize(doc), style: solid)
        case .insert:
            guard let b = BlockClip.boundary(e) else { return nil }
            var plain = e; plain.props[BlockClip.prop] = nil
            return clipItems(DrawListBuilder.items(plain, doc: doc, options: options, inherit: DrawListBuilder.Inherit()), to: b)
        case .dimension(let d):
            return dimensionItems(d, props: e.props, doc: doc, color: color, lineweight: lineweight)
        case .leader(let l):
            guard let n = e.props["mleaderstyle"], let txt = doc.variable("MLSTYLE:" + n),
                  let st = AnnotationToolCommands.MLeaderStyle(name: n, text: txt), st.isCustomGraphics else { return nil }
            return leaderItems(l, style: st, doc: doc, color: color, lineweight: lineweight)
        case .image(let im): return ImageDisplay.items(e, im, doc: doc, options: options, color: color)
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

    public static func hatchItems(_ h: HatchGeom, props: [String: String], color: RGBA, lineweight: Double, options: DrawOptions, doc: ArchiDocument? = nil) -> [DrawItem] {
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
        let lines = HatchPatterns.lines(loops: loops, pattern: h.pattern, scale: HatchPatterns.effectiveScale(h.scale, props: props, doc: doc), angle: h.angle, origin: origin(props) ?? .zero)
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

    public static func tableItems(_ tb: TableGeom, merges m: [Merge], doc: ArchiDocument, style: StrokeStyle, tableStyle ts: TableStyle? = nil) -> [DrawItem] {
        let rows = tb.cells.count, cols = tb.columnWidths.count
        let w = tb.columnWidths.reduce(0, +)
        guard w > 0, rows > 0, cols > 0, tb.rowHeight > 0 else { return [] }
        let o = tb.origin, rh = tb.rowHeight, h = rh * Double(rows)
        var xs = [0.0]; for cw in tb.columnWidths { xs.append(xs[xs.count - 1] + cw) }
        var out: [DrawItem] = []
        // Cell fills of a table style (title / header / data), drawn below the grid.
        if let ts {
            for r in 0..<rows {
                guard let f = ts.cell(ts.role(row: r)).fill else { continue }
                let c = rgba(f, fallback: style.color)
                let y0 = -rh * Double(r), y1 = y0 - rh
                out.append(.fill(loops: [[o + Vec2(0, y0), o + Vec2(w, y0), o + Vec2(w, y1), o + Vec2(0, y1)]], color: c))
            }
        }
        out.append(.stroke(points: [o, o + Vec2(w, 0), o + Vec2(w, -h), o + Vec2(0, -h)], closed: true, style: style))
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
                if let ts {
                    // Styled cell: role height factor, alignment and text colour.
                    let cell = ts.cell(ts.role(row: ri))
                    let th = tb.textHeight * cell.height
                    let pad = min(tb.textHeight * 0.5, (x1 - x0) * 0.1)
                    let x = cell.align == .left ? x0 + pad : cell.align == .right ? x1 - pad : (x0 + x1) / 2
                    t = TextGeom(position: o + Vec2(x, yMid), height: th, content: row[ci], halign: cell.align, valign: .middle)
                    t.style = "Standard"
                    out += DrawListBuilder.textItems(t, doc: doc, color: cell.color.map { rgba($0, fallback: style.color) } ?? style.color)
                    continue
                }
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
        let text = props[textColumnsProp].flatMap { columnTextItems(t, spec: $0, doc: doc, color: color) }
            ?? stackedTextItems(t, doc: doc, color: color, lineweight: lineweight)
            ?? TextStyleFonts.strokeItems(t, doc: doc, color: color, lineweight: lineweight)
            ?? DrawListBuilder.textItems(t, doc: doc, color: color)
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

// MARK: - Text masks in DXF (ANN-013)

/// Exchange helpers for text background masks: MTEXT background-fill group codes (90/63/421/45/441) and the WIPEOUT
/// polygon fallback, plus the reverse mapping so a mask written by `wipeouts(for:)` comes back as a mask on import.
public enum TextMaskExchange {
    /// Mask polygon of a masked text entity in world coordinates (nil when the entity has no mask).
    public static func boundary(_ e: Entity, doc: ArchiDocument) -> [Vec2]? {
        guard case .text(let t) = e.geometry, let f = e.props[DraftRendering.textMaskProp] else { return nil }
        let factor = Double(f).map { $0 > 0 ? $0 : 1.5 } ?? 1.5
        return DraftRendering.textBox(t, doc: doc, factor: factor)
    }

    /// MTEXT group codes for a mask: 90 = 1 (colour) or 3 (drawing background), 63 = ACI colour, 421 = true colour,
    /// 45 = border offset factor, 441 = fill transparency (0). Empty when there is no mask.
    public static func mtextGroups(_ props: [String: String]) -> [(code: Int, value: String)] {
        guard let f = props[DraftRendering.textMaskProp] else { return [] }
        let factor = Double(f).map { $0 > 0 ? $0 : 1.5 } ?? 1.5
        let mc = props[DraftRendering.maskColorProp] ?? "background"
        var out: [(Int, String)] = []
        if mc.lowercased() == "background" {
            out = [(90, "3"), (63, "256")]
        } else {
            out = [(90, "1")]
            switch ColorRef.parse(mc) {
            case .aci(let i)?: out.append((63, "\(i)"))
            case .rgb(let r, let g, let b)?: out.append((63, "7")); out.append((421, "\(Int(r) << 16 | Int(g) << 8 | Int(b))"))
            default: out.append((63, "7"))
            }
        }
        out.append((45, fmt(factor, 6)))
        out.append((441, "0"))
        return out
    }

    /// Mask props from MTEXT group codes (inverse of `mtextGroups`); empty when the flags ask for no fill.
    public static func props(fromMTextGroups g: [(code: Int, value: String)]) -> [String: String] {
        func v(_ c: Int) -> String? { g.last { $0.code == c }?.value.trimmingCharacters(in: .whitespaces) }
        guard let flags = v(90).flatMap(Int.init), flags & 1 != 0 || flags & 2 != 0 else { return [:] }
        var p: [String: String] = [DraftRendering.textMaskProp: v(45).flatMap(Double.init).map { fmt($0, 6) } ?? "1.5"]
        if flags & 2 != 0 { p[DraftRendering.maskColorProp] = "background" }
        else if let tc = v(421).flatMap(Int.init) {
            p[DraftRendering.maskColorProp] = ColorRef.rgb(UInt8((tc >> 16) & 255), UInt8((tc >> 8) & 255), UInt8(tc & 255)).text
        } else if let a = v(63).flatMap(Int.init), a > 0, a < 256 { p[DraftRendering.maskColorProp] = "\(a)" }
        else { p[DraftRendering.maskColorProp] = "background" }
        return p
    }

    /// WIPEOUT polygons for every masked text (for writers without MTEXT background fill, e.g. R12, SVG): each wipeout
    /// carries props wipeout = 1 and maskFor = <text id> and must be drawn just before its text.
    public static func wipeouts(for doc: ArchiDocument) -> [(before: EntityID, wipeout: Entity)] {
        doc.entities.compactMap { e in
            guard let b = boundary(e, doc: doc), b.count >= 3 else { return nil }
            var w = Entity(id: 0, layer: e.layer, geometry: .polyline(PolylineGeom(points: b, closed: true)))
            w.props = ["wipeout": "1", "maskFor": "\(e.id)"]
            if let mc = e.props[DraftRendering.maskColorProp] { w.props[DraftRendering.maskColorProp] = mc }
            return (e.id, w)
        }
    }

    /// After import: a WIPEOUT polygon that matches the mask box of a text drawn right after it (within `tolerance` times the
    /// text height) becomes that text's mask again; the wipeout is removed. Returns the number of masks restored.
    @discardableResult
    public static func absorbWipeouts(_ doc: inout ArchiDocument, tolerance: Double = 0.05) -> Int {
        var remove = Set<EntityID>()
        var n = 0
        for i in doc.entities.indices where doc.entities[i].props["wipeout"] == "1" {
            guard case .polyline(let pl) = doc.entities[i].geometry, pl.vertices.count >= 4 else { continue }
            let pts = pl.vertices.map(\.p)
            // The text drawn next (skipping other wipeouts) whose box, at some factor, matches the polygon.
            var j = i + 1
            while j < doc.entities.count, doc.entities[j].props["wipeout"] == "1" { j += 1 }
            guard j < doc.entities.count, case .text(let t) = doc.entities[j].geometry, doc.entities[j].props[DraftRendering.textMaskProp] == nil else { continue }
            let tight = DraftRendering.textBox(t, doc: doc, factor: 1)
            guard tight.count >= 4 else { continue }
            // Factor from the polygon's extent across the text height direction.
            let up = Vec2.polar(1, t.rotation + .pi / 2)
            func span(_ ps: [Vec2]) -> Double { let d = ps.map { $0.dot(up) }; return (d.max() ?? 0) - (d.min() ?? 0) }
            let h0 = span(tight)
            guard h0 > 1e-12 else { continue }
            // textBox grows by (factor − 1) · height on each side.
            let factor = 1 + (span(pts) - h0) / (2 * t.height)
            guard factor >= 1 - 1e-9 else { continue }
            let expect = DraftRendering.textBox(t, doc: doc, factor: factor)
            let tol = tolerance * t.height
            guard pts.allSatisfy({ p in expect.contains { $0.distance(to: p) <= tol } }) else { continue }
            doc.entities[j].props[DraftRendering.textMaskProp] = fmt(factor, 6)
            doc.entities[j].props[DraftRendering.maskColorProp] = doc.entities[i].props[DraftRendering.maskColorProp] ?? "background"
            remove.insert(doc.entities[i].id); n += 1
        }
        if !remove.isEmpty { doc.remove(ids: remove) }
        return n
    }
}

// MARK: - Block clipping and dimension extras

extension DraftRendering {
    /// Draw items clipped to a closed boundary: strokes are cut, fills intersected, text and images kept when their
    /// insertion point is inside.
    static func clipItems(_ items: [DrawItem], to boundary: [Vec2]) -> [DrawItem] {
        let loops = [boundary]
        var out: [DrawItem] = []
        for it in items {
            switch it {
            case .stroke(let pts, let closed, let st):
                let path = closed && pts.count > 2 ? pts + [pts[0]] : pts
                out += RG.clipPolyline(path, loops).filter { $0.count >= 2 }.map { .stroke(points: $0, closed: false, style: st) }
            case .fill(let ls, let c):
                let r = PolygonBoolean.apply(.intersect, ls, loops)
                if !r.isEmpty { out.append(.fill(loops: r, color: c)) }
            case .text(let t, _, _):
                if PolygonBoolean.contains(loops, t.position) { out.append(it) }
            case .image(let im):
                if PolygonBoolean.contains(loops, im.origin + im.size / 2) { out.append(it) }
            }
        }
        return out
    }

    /// Dimension with tolerance / alternate units / inspection text and its frame.
    static func dimensionItems(_ d: DimensionGeom, props: [String: String], doc: ArchiDocument, color: RGBA, lineweight: Double) -> [DrawItem] {
        let ds = doc.dimStyle(d.style)
        let x = DimStyleExtras.get(ds.name, doc: doc)
        let merged = x.mergedProps(props)
        var dd = d
        dd.textOverride = DimStyleExtras.text(d, props: props, doc: doc)
        let prim = DimensionRenderer.primitives(dd, style: ds, layout: x.layout)
        let st = StrokeStyle(color: color, lineweight: lineweight)
        var out: [DrawItem] = prim.lines.filter { $0.count >= 2 }.map { .stroke(points: $0, closed: false, style: st) }
        out += prim.arrows.filter { $0.count >= 3 }.map { .fill(loops: [$0], color: color) }
        if var t = prim.text {
            if let ts = x.textStyle { t.style = ts }
            out += TextStyleFonts.strokeItems(t, doc: doc, color: color, lineweight: lineweight)
                ?? [.text(t, font: DrawListBuilder.textFont(t.style, doc: doc).font, color: color)]
            if let shape = DimExtras.frame(merged) { out += frameItems(t, shape: shape, doc: doc, style: st) }
        }
        return out
    }

    /// Frame around a dimension text: box (basic), round-ended or angular-ended (inspection) with separators.
    static func frameItems(_ t: TextGeom, shape: String, doc: ArchiDocument, style: StrokeStyle) -> [DrawItem] {
        let box = textBox(t, doc: doc, factor: 1.2)
        guard box.count == 4 else { return [] }
        let back = Transform2D.translation(t.position) * Transform2D.rotation(t.rotation)
        let fwd = back.inverted
        let lb = box.map(fwd.apply)
        let x0 = lb[0].x, x1 = lb[1].x, y0 = lb[0].y, y1 = lb[2].y
        let h = (y1 - y0) / 2, ym = (y0 + y1) / 2
        var out: [[Vec2]] = []
        switch shape {
        case "box": out.append([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1), Vec2(x0, y0)])
        case "angular":
            out.append([Vec2(x0, ym), Vec2(x0 + h, y0), Vec2(x1 - h, y0), Vec2(x1, ym), Vec2(x1 - h, y1), Vec2(x0 + h, y1), Vec2(x0, ym)])
        default:
            var pts: [Vec2] = []
            for k in 0...12 { let a = -Double.pi / 2 + Double.pi * Double(k) / 12; pts.append(Vec2(x1 - h + h * cos(a), ym + h * sin(a))) }
            for k in 0...12 { let a = Double.pi / 2 + Double.pi * Double(k) / 12; pts.append(Vec2(x0 + h + h * cos(a), ym + h * sin(a))) }
            pts.append(pts[0])
            out.append(pts)
        }
        // Separators between label | value | rate, at the " | " positions.
        if shape != "box", t.content.contains(" | ") {
            let parts = t.content.components(separatedBy: " | ")
            let total = StrokeFont.lineWidth(t.content)
            if total > 0 {
                var acc = 0.0
                for p in parts.dropLast() {
                    acc += StrokeFont.lineWidth(p + " |") - StrokeFont.lineWidth("|") / 2
                    let x = x0 + h + (x1 - x0 - 2 * h) * (acc / total)
                    out.append([Vec2(x, y0), Vec2(x, y1)])
                    acc += StrokeFont.lineWidth("| ") - StrokeFont.lineWidth("|") / 2 + StrokeFont.letterGap
                }
            }
        }
        return out.map { .stroke(points: $0.map(back.apply), closed: false, style: style) }
    }
}

// MARK: - Text columns (ANN-006) and stacked fractions (ANN-007)

extension DraftRendering {
    /// Parsed column spec: count, gutter, height (0 = balanced).
    public static func columnSpec(_ s: String) -> (count: Int, gutter: Double, height: Double)? {
        let v = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let n = v.first, n >= 1, n <= 100 else { return nil }
        return (Int(n), v.count > 1 ? max(0, v[1]) : 0, v.count > 2 ? max(0, v[2]) : 0)
    }

    /// Wrapped lines laid out in columns: (line, column, row).
    public static func columnLayout(_ t: TextGeom, spec: String, widthFactor: Double) -> (lines: [(text: String, column: Int, row: Int)], columnWidth: Double, gutter: Double)? {
        guard let c = columnSpec(spec), t.width > 0, t.height > 0 else { return nil }
        let colW = (t.width - c.gutter * Double(c.count - 1)) / Double(c.count)
        guard colW > 0 else { return nil }
        let lines = DrawListBuilder.wrapLines(t.content, height: t.height, width: colW, widthFactor: widthFactor)
        let spacing = 1.5 * t.height
        let perCol: Int
        if c.height > 0 { perCol = max(1, Int(((c.height - t.height) / spacing + 1e-9).rounded(.down)) + 1) }
        else { perCol = max(1, Int((Double(lines.count) / Double(c.count)).rounded(.up))) }
        return (lines.enumerated().map { (i, l) in (l, i / perCol, i % perCol) }, colW, c.gutter)
    }

    static func columnTextItems(_ t0: TextGeom, spec: String, doc: ArchiDocument, color: RGBA) -> [DrawItem]? {
        var t = t0
        let st = DrawListBuilder.textFont(t.style, doc: doc)
        if t.height <= 0 { t.height = st.height > 0 ? st.height : 2.5 }
        guard let lay = columnLayout(t, spec: spec, widthFactor: st.width) else { return nil }
        let right = Vec2.polar(1, t.rotation), down = Vec2.polar(1, t.rotation - .pi / 2)
        let spacing = 1.5 * t.height
        return lay.lines.filter { !$0.text.isEmpty }.map { l in
            var lt = t
            lt.content = l.text; lt.width = 0; lt.halign = .left; lt.valign = .baseline
            lt.position = t.position + right * (Double(l.column) * (lay.columnWidth + lay.gutter)) + down * (t.height + spacing * Double(l.row))
            return .text(lt, font: st.font, color: color)
        }
    }

    /// Single-line text with \S stacks: plain runs as text, stacks as two small texts with a bar (a/b), a diagonal (a#b)
    /// or none (a^b, tolerance style).
    static func stackedTextItems(_ t0: TextGeom, doc: ArchiDocument, color: RGBA, lineweight: Double) -> [DrawItem]? {
        guard TextStacks.hasStack(t0.content) else { return nil }
        if t0.content.contains("\\P") || t0.content.contains("\n") {
            // Multiline text (no wrap width): each line is laid out on its own, lines 1.667 × height apart (ANN-007).
            guard t0.width <= 0 else { return nil }
            let lines = t0.content.replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
            var h = t0.height
            if h <= 0 { let st = DrawListBuilder.textFont(t0.style, doc: doc); h = st.height > 0 ? st.height : 2.5 }
            let ls = h * 5 / 3, n = Double(lines.count - 1)
            let shift: Double
            switch t0.valign { case .middle: shift = n * ls / 2; case .bottom, .baseline: shift = n * ls; case .top: shift = 0 }
            var out: [DrawItem] = []
            for (i, l) in lines.enumerated() where !l.isEmpty {
                var t = t0
                t.content = l
                t.position = t0.position + Vec2(0, shift - Double(i) * ls).rotated(by: t0.rotation)
                if TextStacks.hasStack(l), let it = stackedTextItems(t, doc: doc, color: color, lineweight: lineweight) { out += it }
                else { out += DrawListBuilder.textItems(t, doc: doc, color: color) }
            }
            return out
        }
        var t = t0
        let st = DrawListBuilder.textFont(t.style, doc: doc)
        if t.height <= 0 { t.height = st.height > 0 ? st.height : 2.5 }
        let h = t.height, cw = 0.6 * h * st.width, small = 0.5
        let runs = TextStacks.runs(t.content)
        func width(_ r: TextStacks.Run) -> Double {
            switch r {
            case .plain(let s): return Double(s.count) * cw
            case .stack(let a, let b, _): return Double(max(a.count, b.count)) * cw * small + 0.2 * cw
            }
        }
        let total = runs.reduce(0) { $0 + width($1) }
        var x: Double
        switch t.halign { case .left: x = 0; case .center: x = -total / 2; case .right: x = -total }
        let by: Double
        switch t.valign { case .baseline: by = 0; case .bottom: by = 0.2 * h; case .middle: by = -h / 2; case .top: by = -h }
        let tr = Transform2D.translation(t.position) * Transform2D.rotation(t.rotation)
        func text(_ s: String, _ px: Double, _ py: Double, _ size: Double) -> DrawItem {
            .text(TextGeom(position: tr.apply(Vec2(px, py)), height: size, content: s, rotation: t.rotation, style: t.style, halign: .left, valign: .baseline), font: st.font, color: color)
        }
        let style = StrokeStyle(color: color, lineweight: lineweight)
        var out: [DrawItem] = []
        for r in runs {
            let w = width(r)
            switch r {
            case .plain(let s): if !s.isEmpty { out.append(text(s, x, by, h)) }
            case .stack(let a, let b, let kind):
                let sh = h * small, inner = w - 0.2 * cw, x0 = x + 0.1 * cw
                let wa = Double(a.count) * cw * small, wb = Double(b.count) * cw * small
                switch kind {
                case "#":
                    out.append(text(a, x0, by + 0.55 * h, sh))
                    out.append(text(b, x0 + inner - wb, by - 0.05 * h, sh))
                    out.append(.stroke(points: [tr.apply(Vec2(x0, by - 0.05 * h)), tr.apply(Vec2(x0 + inner, by + 1.05 * h))], closed: false, style: style))
                case "^":
                    out.append(text(a, x0, by + 0.55 * h, sh))
                    out.append(text(b, x0, by - 0.05 * h, sh))
                default:
                    out.append(text(a, x0 + (inner - wa) / 2, by + 0.6 * h, sh))
                    out.append(text(b, x0 + (inner - wb) / 2, by - 0.05 * h, sh))
                    out.append(.stroke(points: [tr.apply(Vec2(x0, by + 0.5 * h)), tr.apply(Vec2(x0 + inner, by + 0.5 * h))], closed: false, style: style))
                }
            }
            x += w
        }
        return out
    }
}

/// MTEXT stacks "\\Sa/b;" (fraction), "\\Sa#b;" (diagonal), "\\Sa^b;" (tolerance) and AutoStack of typed fractions.
public enum TextStacks {
    public enum Run: Equatable { case plain(String), stack(String, String, String) }

    public static func hasStack(_ s: String) -> Bool { s.contains("\\S") }

    /// Splits text into plain runs and stacks.
    public static func runs(_ s: String) -> [Run] {
        var out: [Run] = [], cur = "", i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "S", let semi = s[i...].firstIndex(of: ";") {
                let body = String(s[s.index(i, offsetBy: 2)..<semi])
                if let k = body.firstIndex(where: { "/#^".contains($0) }) {
                    if !cur.isEmpty { out.append(.plain(cur)); cur = "" }
                    out.append(.stack(String(body[..<k]), String(body[body.index(after: k)...]), String(body[k])))
                    i = s.index(after: semi); continue
                }
            }
            cur.append(s[i]); i = s.index(after: i)
        }
        if !cur.isEmpty { out.append(.plain(cur)) }
        return out
    }

    static let fraction = try! NSRegularExpression(pattern: "(?<![\\\\\\w/.#^])([0-9]+)([/#^])([0-9]+)(?![\\w/#^])")

    /// AutoStack: numeric fractions typed as 1/2, 3#4 or 1^2 become stacks.
    public static func autoStack(_ s: String) -> String {
        fraction.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\\\\S$1$2$3;")
    }
    /// Stacks back to plain a/b text.
    public static func unstack(_ s: String) -> String {
        runs(s).map { r -> String in if case .stack(let a, let b, let k) = r { return a + k + b }; if case .plain(let p) = r { return p }; return "" }.joined()
    }
}

// MARK: - Complex linetypes (LAY-022)

/// Curves drawn with a complex linetype: the dash pattern as solid strokes plus the text and shape elements placed along
/// the curve (scaled by LTSCALE × object scale, rotated with the curve unless absolute, text kept upright with U=).
public enum ComplexLinetypes {
    static func resolvedName(_ e: Entity, doc: ArchiDocument) -> String? {
        let n = e.linetype ?? "ByLayer"
        if n.caseInsensitiveCompare("ByBlock") == .orderedSame { return nil }
        if n.caseInsensitiveCompare("ByLayer") == .orderedSame { return doc.layer(named: e.layer)?.linetype }
        return n
    }

    static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem]? {
        switch e.geometry { case .line, .arc, .circle, .polyline, .ellipse, .spline: break; default: return nil }
        guard let name = resolvedName(e, doc: doc), let v = doc.variable(LinFile.complexVariable(name)),
              let def = LinFile.parse(v).first, def.isComplex else { return nil }
        let scale = DrawListBuilder.ltScale(doc, e, options)
        let style = StrokeStyle(color: color, lineweight: lineweight)
        let font = DrawListBuilder.textFont("Standard", doc: doc).font
        var out: [DrawItem] = []
        for pts in GeometryOps.tessellate(e.geometry, doc: doc) where pts.count >= 2 {
            out += along(pts, def: def, scale: scale, style: style, font: font)
        }
        return out
    }

    /// Dashes, dots and elements along one polyline.
    public static func along(_ pts: [Vec2], def: LinFile.Definition, scale s: Double, style: StrokeStyle, font: String) -> [DrawItem] {
        var cum = [0.0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + pts[i].distance(to: pts[i - 1])) }
        let total = cum.last ?? 0
        let period = def.pattern.reduce(0) { $0 + abs($1) } * s
        guard total > 1e-12, period > 1e-12 else { return [.stroke(points: pts, closed: false, style: style)] }
        func at(_ d: Double) -> (p: Vec2, dir: Vec2) {
            let dd = Swift.min(Swift.max(d, 0), total)
            var i = 1
            while i < pts.count - 1 && cum[i] < dd { i += 1 }
            let seg = cum[i] - cum[i - 1]
            let t = seg > 0 ? (dd - cum[i - 1]) / seg : 0
            let dir = (pts[i] - pts[i - 1]).normalized
            return (pts[i - 1] + (pts[i] - pts[i - 1]) * t, dir == .zero ? Vec2(1, 0) : dir)
        }
        func piece(_ d0: Double, _ d1: Double) -> [Vec2] {
            var r = [at(d0).p]
            for i in 1..<(pts.count - 1) where cum[i] > d0 && cum[i] < d1 { r.append(pts[i]) }
            r.append(at(d1).p)
            return r
        }
        var out: [DrawItem] = []
        var d = 0.0, idx = 0, guardCount = 0
        while d < total && guardCount < 200_000 {
            guardCount += 1
            let v = def.pattern[idx] * s
            if v > 0 { out.append(.stroke(points: piece(d, Swift.min(d + v, total)), closed: false, style: style)) }
            else if v == 0 { let q = at(d); out.append(.stroke(points: [q.p, q.p + q.dir * (1e-3 * Swift.max(s, 1e-9))], closed: false, style: style)) }
            d += abs(v)
            for el in def.elements where el.after == idx && d <= total + 1e-9 {
                out += element(el, at: at(d), scale: s, style: style, font: font)
            }
            idx = (idx + 1) % def.pattern.count
        }
        return out
    }

    static func element(_ el: LinFile.Element, at a: (p: Vec2, dir: Vec2), scale s: Double, style: StrokeStyle, font: String) -> [DrawItem] {
        let k = Swift.max(el.scale, 1e-9) * s
        var rot = el.absolute ? rad(el.rotation) : a.dir.angle + rad(el.rotation)
        let u = a.dir, n = a.dir.perp
        let origin = a.p + u * (el.x * s) + n * (el.y * s)
        switch el.kind {
        case .text(let t, _):
            var pos = origin
            if el.upright {
                let nr = normAngle(rot)
                if nr > .pi / 2 && nr <= 3 * .pi / 2 {
                    // Flip to read upright: rotate by π about the text's middle.
                    let w = 0.6 * k * Double(t.count), c = pos + Vec2.polar(w / 2, rot) + Vec2.polar(k / 2, rot + .pi / 2)
                    rot += .pi
                    pos = c - Vec2.polar(w / 2, rot) - Vec2.polar(k / 2, rot + .pi / 2)
                }
            }
            return [.text(TextGeom(position: pos, height: k, content: t, rotation: rot), font: font, color: style.color)]
        case .shape(let name, _):
            let r = Transform2D.translation(origin) * Transform2D.rotation(rot)
            let local: [[Vec2]]
            switch name {
            case "BOX": local = [[Vec2(k / 2, -k / 2), Vec2(3 * k / 2, -k / 2), Vec2(3 * k / 2, k / 2), Vec2(k / 2, k / 2), Vec2(k / 2, -k / 2)]]
            case "TRACK1": local = [[Vec2(0, -k / 2), Vec2(0, k / 2)]]
            case "ZIG": local = [[Vec2(0, 0), Vec2(k / 2, k / 2), Vec2(k, 0)]]
            default: // CIRC1 and unknown shapes: a circle of diameter k.
                local = [(0...24).map { Vec2(k, 0) + Vec2.polar(k / 2, Double($0) / 24 * 2 * .pi) }]
            }
            return local.map { .stroke(points: $0.map(r.apply), closed: false, style: style) }
        }
    }
}
