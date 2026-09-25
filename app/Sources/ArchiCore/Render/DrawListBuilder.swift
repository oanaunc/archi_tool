// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Converts the document into resolved draw entries (colors, linetypes, lineweights, text, hatches, blocks, BIM plan symbols).
public enum DrawListBuilder {
    /// Inherited properties while expanding block references.
    struct Inherit {
        var color: RGBA?        // ByBlock color (insert's resolved color)
        var linetype: String?   // ByBlock linetype
        var lineweight: Double? // ByBlock lineweight
        var layer: String?      // layer "0" entities take the insert's layer
        var depth = 0
    }

    // MARK: Public API

    public static func entries(doc fullDoc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        // Worksets and design options not on display are left out entirely (also from wall joins and hosts).
        let doc = ModelSets.visibleModel(fullDoc)
        var options = options
        if doc.variable("RCP") == "1" { options.reflectedCeiling = true }
        if options.reflectedCeiling { options.showCeilings = true }
        var out: [DrawEntry] = []
        if options.showElements {
            let ctx = PlanRepresentation.context(doc)
            let walls: [EntityID: BIMElement] = options.level == nil ? [:] : Dictionary(doc.elements.compactMap { el -> (EntityID, BIMElement)? in
                if case .wall = el.geometry { return (el.id, el) }; return nil }, uniquingKeysWith: { a, _ in a })
            let els = doc.elements.enumerated().filter { _, el in
                guard layerShown(el.layer, doc, options) else { return false }
                if let l = options.level, el.level != l, !BIMConstraints.shown(el, onLevel: l, doc: doc, hosts: walls) { return false }
                if case .gridLine = el.geometry, !options.showAnnotations { return false }
                return true
            }.sorted { a, b in
                let pa = priority(a.element), pb = priority(b.element)
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            let phased = Phasing.isActive(doc)
            let pf = Phasing.filter(doc)
            for (_, el) in els {
                var st = Phasing.Status.new
                if phased { st = Phasing.status(el.props, doc: doc); if !Phasing.visible(st, pf) { continue } }
                if el.props["kind"] == "ceiling" && !(options.showCeilings ?? (doc.variable("CEILINGS") != "0")) { continue }
                if options.reflectedCeiling && !ReflectedCeiling.shows(el) { continue }
                var items = PlanRepresentation.items(el, ctx: ctx, options: options)
                if phased { items = phaseStyled(items, Phasing.style(st, pf), doc: doc, options: options) }
                items = items.map { paper($0, options) }
                if !items.isEmpty { out.append(DrawEntry(id: el.id, items: items)) }
            }
        }
        let phasedEntities = doc.entities.contains { $0.props["phaseCreated"] != nil || $0.props["phaseDemolished"] != nil }
        let pf = Phasing.filter(doc)
        for e in doc.entities where layerShown(e.layer, doc, options) {
            if !options.showAnnotations && isAnnotation(e.geometry) { continue }
            if let l = options.level, let el = e.props["level"].flatMap(Int.init), el != l { continue }
            var items = self.items(for: SiteAnnotations.live(e, doc: doc), doc: doc, options: options)
            items += SiteAnnotations.extraItems(e, doc: doc, options: options)
            if phasedEntities {
                let st = Phasing.status(e.props, doc: doc)
                if !Phasing.visible(st, pf) { continue }
                items = phaseStyled(items, Phasing.style(st, pf), doc: doc, options: options)
            }
            if !items.isEmpty { out.append(DrawEntry(id: e.id, items: items)) }
        }
        out += ConstraintGlyphs.entries(doc: doc, options: options)
        return out
    }

    /// Phase graphic overrides: halftone for existing work, dashed and tinted for demolished work.
    static func phaseStyled(_ items: [DrawItem], _ s: (halftone: Bool, dashed: Bool, tint: RGBA?), doc: ArchiDocument, options: DrawOptions) -> [DrawItem] {
        guard s.halftone || s.dashed || s.tint != nil else { return items }
        let gray = RGBA(0.5, 0.5, 0.5)
        func col(_ c: RGBA) -> RGBA {
            var r = c
            if let t = s.tint { r = RGBA(t.r, t.g, t.b, c.a) }
            if s.halftone { r = PlanRepresentation.blend(r, gray, 0.55) }
            return r
        }
        let dash = PlanRepresentation.hiddenDash(doc, options)
        return items.compactMap { it in
            switch it {
            case .stroke(let p, let c, var st):
                st.color = col(st.color)
                if s.dashed && st.dash.isEmpty { st.dash = dash }
                return .stroke(points: p, closed: c, style: st)
            case .fill(let l, let c):
                if s.dashed { return nil }
                let cc = col(c); return .fill(loops: l, color: RGBA(cc.r, cc.g, cc.b, c.a * (s.halftone ? 0.6 : 1)))
            case .text(let t, let f, let c): return .text(t, font: f, color: col(c))
            case .image: return it
            }
        }
    }

    public static func items(for e: Entity, doc: ArchiDocument, options: DrawOptions) -> [DrawItem] {
        items(e, doc: doc, options: options, inherit: Inherit()).map { paper($0, options) }
    }

    /// Rubber-band preview geometry drawn in a single color with hairlines.
    public static func previewItems(_ geoms: [Geometry], doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        var opts = DrawOptions(); opts.cutHatches = true
        var out: [DrawItem] = []
        for g in geoms {
            let e = Entity(id: 0, layer: doc.currentLayer, color: .byLayer, linetype: "Continuous", lineweight: 0, geometry: g)
            for it in items(e, doc: doc, options: opts, inherit: Inherit()) {
                switch it {
                case .stroke(let p, let c, var s): s.color = color; s.lineweight = 0; out.append(.stroke(points: p, closed: c, style: s))
                case .fill(let l, _): out.append(.fill(loops: l, color: RGBA(color.r, color.g, color.b, 0.35)))
                case .text(let t, let f, _): out.append(.text(t, font: f, color: color))
                case .image(let im): out.append(.image(im))
                }
            }
        }
        return out
    }

    // MARK: Resolution helpers

    static func priority(_ el: BIMElement) -> Int {
        switch el.geometry {
        case .space: return 0
        case .slab: return 1
        case .roof: return 2
        case .beam: return 3
        case .stair: return 4
        case .railing: return 5
        case .component: return 6
        case .wall: return 7
        case .curtainWall: return 8
        case .column: return 9
        case .opening: return 10
        case .gridLine: return 11
        }
    }

    static func isAnnotation(_ g: Geometry) -> Bool {
        switch g { case .text, .dimension, .leader, .table: return true; default: return false }
    }

    static func layerShown(_ name: String, _ doc: ArchiDocument, _ o: DrawOptions) -> Bool {
        guard let l = doc.layer(named: name) else { return true }
        if !l.visible || l.frozen { return false }
        if o.forPaper && !l.plot { return false }
        return true
    }

    /// ACI 7 / white prints black on paper.
    static func paperColor(_ c: RGBA, _ o: DrawOptions) -> RGBA {
        guard o.forPaper, c.r > 0.9, c.g > 0.9, c.b > 0.9 else { return c }
        return RGBA(0, 0, 0, c.a)
    }
    static func paper(_ it: DrawItem, _ o: DrawOptions) -> DrawItem {
        guard o.forPaper else { return it }
        switch it {
        case .stroke(let p, let c, var s): s.color = paperColor(s.color, o); return .stroke(points: p, closed: c, style: s)
        case .fill(let l, let c): return .fill(loops: l, color: paperColor(c, o))
        case .text(let t, let f, let c): return .text(t, font: f, color: paperColor(c, o))
        case .image: return it
        }
    }

    static func color(_ ref: ColorRef, layer: Layer?, inherit: Inherit) -> RGBA {
        switch ref {
        case .byLayer: return layer?.color ?? .white
        case .byBlock: return inherit.color ?? .white
        case .aci(let i): return i == 0 ? (inherit.color ?? .white) : (i == 256 ? (layer?.color ?? .white) : aciColor(i))
        case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        }
    }

    static func ltScale(_ doc: ArchiDocument, _ e: Entity, _ o: DrawOptions) -> Double {
        let g = doc.variable("LTSCALE").flatMap(Double.init) ?? 1
        let c = e.props["ltscale"].flatMap(Double.init) ?? 1
        return (g > 0 ? g : 1) * (c > 0 ? c : 1) * (o.linetypeScale > 0 ? o.linetypeScale : 1)
    }

    static func dash(_ e: Entity, layer: Layer?, doc: ArchiDocument, options: DrawOptions, inherit: Inherit) -> [Double] {
        var name = e.linetype ?? "ByLayer"
        if name.caseInsensitiveCompare("ByLayer") == .orderedSame { name = layer?.linetype ?? "Continuous" }
        else if name.caseInsensitiveCompare("ByBlock") == .orderedSame { name = inherit.linetype ?? "Continuous" }
        guard let lt = doc.linetype(name), !lt.pattern.isEmpty else { return [] }
        let s = ltScale(doc, e, options)
        return lt.pattern.map { $0 * s }
    }

    static func lineweight(_ e: Entity, layer: Layer?, inherit: Inherit) -> Double {
        if let w = e.lineweight {
            if w >= 0 { return w }
            if w == -2, let b = inherit.lineweight { return b } // ByBlock
        }
        return layer?.lineweight ?? 0.25
    }

    static func textFont(_ style: String, doc: ArchiDocument) -> (font: String, height: Double, width: Double) {
        let s = doc.textStyles.first { $0.name.caseInsensitiveCompare(style) == .orderedSame } ?? doc.textStyles.first
        return (s?.font ?? "Helvetica", s?.height ?? 0, s?.widthFactor ?? 1)
    }

    // MARK: Text

    /// Splits text into lines (explicit newlines / MText \P) and word-wraps to `width` (0 = no wrap).
    static func wrapLines(_ content: String, height: Double, width: Double, widthFactor: Double) -> [String] {
        let text = content.replacingOccurrences(of: "\\P", with: "\n")
        let paragraphs = text.components(separatedBy: "\n")
        guard width > 0 else { return paragraphs }
        let charW = max(height * 0.6 * widthFactor, 1e-9)
        let maxChars = max(1, Int(width / charW))
        var out: [String] = []
        for p in paragraphs {
            var line = ""
            for word in p.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let candidate = line.isEmpty ? word : line + " " + word
                if candidate.count <= maxChars || line.isEmpty {
                    if candidate.count > maxChars && line.isEmpty {
                        // Hard-break an over-long word.
                        var w = Substring(word)
                        while w.count > maxChars { out.append(String(w.prefix(maxChars))); w = w.dropFirst(maxChars) }
                        line = String(w)
                    } else { line = candidate }
                } else { out.append(line); line = word }
            }
            out.append(line)
        }
        return out
    }

    static func textItems(_ t0: TextGeom, doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        var t = t0
        let st = textFont(t.style, doc: doc)
        if t.height <= 0 { t.height = st.height > 0 ? st.height : 2.5 }
        let lines = wrapLines(t.content, height: t.height, width: t.width, widthFactor: st.width)
        if lines.count <= 1 {
            t.content = lines.first ?? ""; t.width = 0
            return t.content.isEmpty ? [] : [.text(t, font: st.font, color: color)]
        }
        let h = t.height, spacing = 1.5 * h
        let blockH = h + spacing * Double(lines.count - 1)
        let firstBaseline: Double
        switch t.valign {
        case .top: firstBaseline = -h
        case .middle: firstBaseline = blockH / 2 - h
        case .bottom, .baseline: firstBaseline = spacing * Double(lines.count - 1)
        }
        let down = Vec2.polar(1, t.rotation - .pi / 2)
        var out: [DrawItem] = []
        for (i, line) in lines.enumerated() where !line.isEmpty {
            var lt = t
            lt.content = line; lt.width = 0; lt.valign = .baseline
            lt.position = t.position - down * firstBaseline + down * (spacing * Double(i))
            out.append(.text(lt, font: st.font, color: color))
        }
        return out
    }

    // MARK: Entities

    static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, inherit: Inherit) -> [DrawItem] {
        let layerName = (e.layer == "0" && inherit.layer != nil) ? inherit.layer! : e.layer
        let layer = doc.layer(named: layerName)
        let col = color(e.color, layer: layer, inherit: inherit)
        if e.props["tagOf"] != nil, case .text(let t) = e.geometry { return Annotations.tagItems(e, t, doc: doc, color: col) }
        if e.props["sectionMark"] != nil { return Annotations.sectionItems(e, doc: doc, color: col, lineweight: lineweight(e, layer: layer, inherit: inherit)) }
        let lw = lineweight(e, layer: layer, inherit: inherit)
        let style = StrokeStyle(color: col, lineweight: lw, dash: dash(e, layer: layer, doc: doc, options: options, inherit: inherit))
        let solidStyle = StrokeStyle(color: col, lineweight: lw)
        func strokes(_ g: Geometry, closed: Bool = false) -> [DrawItem] {
            GeometryOps.tessellate(g, doc: doc).filter { $0.count >= 2 }.map { .stroke(points: $0, closed: closed, style: style) }
        }
        switch e.geometry {
        case .point(let p):
            return [.stroke(points: [p, p + Vec2(1e-3, 0)], closed: false, style: solidStyle)]
        case .line, .arc, .spline:
            return strokes(e.geometry)
        case .circle(let c):
            guard c.radius > 0 else { return [] }
            var pts = GeometryOps.arcPoints(center: c.center, radius: c.radius, start: 0, sweep: 2 * .pi); pts.removeLast()
            return [.stroke(points: pts, closed: true, style: style)]
        case .ellipse(let el):
            var pts = GeometryOps.ellipsePoints(el)
            if el.isFull { pts.removeLast(); return [.stroke(points: pts, closed: true, style: style)] }
            return [.stroke(points: pts, closed: false, style: style)]
        case .polyline(let pl):
            let pts = GeometryOps.polylinePoints(pl)
            guard pts.count >= 2 else { return pts.isEmpty ? [] : [.stroke(points: [pts[0], pts[0] + Vec2(1e-3, 0)], closed: false, style: solidStyle)] }
            if pl.width > 0 {
                let hw = pl.width / 2
                if pl.closed {
                    var ring = RG.dedupe(pts, closed: true)
                    if GeometryOps.signedArea(ring) < 0 { ring.reverse() }
                    return [.fill(loops: [RG.offsetPolygon(ring, hw), RG.offsetPolygon(ring, -hw)], color: col)]
                }
                let l = PlanRepresentation.offsetPolyline(pts, hw), r = PlanRepresentation.offsetPolyline(pts, -hw)
                return [.fill(loops: [l + r.reversed()], color: col)]
            }
            if pl.closed { return [.stroke(points: RG.dedupe(pts, closed: true), closed: true, style: style)] }
            return [.stroke(points: pts, closed: false, style: style)]
        case .text(let t):
            return textItems(t, doc: doc, color: col)
        case .dimension(let d):
            let ds = doc.dimStyle(d.style)
            let prim = DimensionRenderer.primitives(d, style: ds)
            var out: [DrawItem] = prim.lines.filter { $0.count >= 2 }.map { .stroke(points: $0, closed: false, style: solidStyle) }
            out += prim.arrows.filter { $0.count >= 3 }.map { .fill(loops: [$0], color: col) }
            if let t = prim.text { out.append(.text(t, font: textFont(t.style, doc: doc).font, color: col)) }
            return out
        case .hatch(let h):
            let loops = h.loops.map { RG.dedupe(GeometryOps.polylinePoints($0, closed: true), closed: true) }.filter { $0.count >= 3 }
            guard !loops.isEmpty else { return [] }
            if h.pattern.uppercased() == "SOLID" {
                let fc = h.fill.map { color($0, layer: layer, inherit: inherit) } ?? col
                return [.fill(loops: loops, color: fc)]
            }
            var out: [DrawItem] = []
            if let bg = h.fill { out.append(.fill(loops: loops, color: color(bg, layer: layer, inherit: inherit))) }
            let lines = HatchPatterns.lines(loops: loops, pattern: h.pattern, scale: h.scale, angle: h.angle)
            out += lines.map { .stroke(points: $0, closed: false, style: StrokeStyle(color: col, lineweight: min(lw, 0.18))) }
            return out
        case .leader(let l):
            guard l.points.count >= 2 else { return [] }
            var out: [DrawItem] = [.stroke(points: l.points, closed: false, style: solidStyle)]
            let ds = doc.dimStyle
            let a = ds.arrowSize * ds.scale > 0 ? ds.arrowSize * ds.scale : l.textHeight
            out.append(.fill(loops: [RG.triangleArrow(tip: l.points[0], dir: l.points[0] - l.points[1], size: a)], color: col))
            if !l.text.isEmpty {
                let last = l.points[l.points.count - 1], prev = l.points[l.points.count - 2]
                let right = last.x >= prev.x
                var t = TextGeom(position: last + Vec2(right ? l.textHeight * 0.5 : -l.textHeight * 0.5, 0), height: l.textHeight, content: l.text,
                                 halign: right ? .left : .right, valign: .middle)
                t.style = "Standard"
                out += textItems(t, doc: doc, color: col)
            }
            return out
        case .table(let tb):
            let w = tb.columnWidths.reduce(0, +)
            let rows = tb.cells.count
            guard w > 0, rows > 0, tb.rowHeight > 0 else { return [] }
            let o = tb.origin, h = tb.rowHeight * Double(rows)
            var out: [DrawItem] = [.stroke(points: [o, o + Vec2(w, 0), o + Vec2(w, -h), o + Vec2(0, -h)], closed: true, style: solidStyle)]
            for r in 1..<max(rows, 1) { let y = -tb.rowHeight * Double(r); out.append(.stroke(points: [o + Vec2(0, y), o + Vec2(w, y)], closed: false, style: solidStyle)) }
            var x = 0.0
            for (ci, cw) in tb.columnWidths.enumerated() {
                if ci > 0 { out.append(.stroke(points: [o + Vec2(x, 0), o + Vec2(x, -h)], closed: false, style: solidStyle)) }
                for (ri, row) in tb.cells.enumerated() where ci < row.count && !row[ci].isEmpty {
                    let pos = o + Vec2(x + min(tb.textHeight * 0.5, cw * 0.1), -tb.rowHeight * (Double(ri) + 0.5))
                    out += textItems(TextGeom(position: pos, height: tb.textHeight, content: row[ci], valign: .middle), doc: doc, color: col)
                }
                x += cw
            }
            return out
        case .insert(let ins):
            guard inherit.depth < 8, let b = doc.blocks[ins.block] else {
                return [.stroke(points: [ins.position - Vec2(1, 0), ins.position + Vec2(1, 0)], closed: false, style: solidStyle)]
            }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            var sub = Inherit(color: col, linetype: e.linetype.flatMap { $0.caseInsensitiveCompare("ByLayer") == .orderedSame ? layer?.linetype : $0 } ?? layer?.linetype,
                              lineweight: lw, layer: layerName, depth: inherit.depth + 1)
            if e.linetype?.caseInsensitiveCompare("ByBlock") == .orderedSame { sub.linetype = inherit.linetype }
            var out: [DrawItem] = []
            for be in b.entities where layerShown(be.layer == "0" ? layerName : be.layer, doc, options) {
                var child = be
                child.geometry = GeometryOps.transform(be.geometry, t)
                if case .text(var tx) = child.geometry, let tag = be.props["attdef"] ?? be.props["tag"], let v = ins.attributes[tag] {
                    tx.content = v; child.geometry = .text(tx)
                }
                out += items(child, doc: doc, options: options, inherit: sub)
            }
            return out
        case .image(let im):
            return [.image(im)]
        case .solid(let s):
            if s.kind == .mesh && !s.meshTriangles.isEmpty {
                if let iv = e.props["contourInterval"].flatMap(Double.init), iv > 0 {
                    return Annotations.terrainItems(s, interval: iv, major: e.props["contourMajor"].flatMap(Int.init) ?? 5, doc: doc, color: col, lineweight: lw, showLabels: options.showAnnotations)
                }
                if s.meshTriangles.count <= 60_000 {
                    return MeshTools.planEdges(vertices: s.meshVertices, triangles: s.meshTriangles).map { .stroke(points: $0, closed: false, style: style) }
                }
            }
            let fp = GeometryOps.solidFootprint(s)
            return fp.count >= 2 ? [.stroke(points: fp, closed: false, style: style)] : []
        }
    }
}
