// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import CoreText
import PDFKit
import ArchiCore

// MARK: - Core Graphics renderer for DrawEntry lists (PDF, print, sheet view, agent screenshots)

/// Draws resolved `DrawEntry` lists into any y-up Core Graphics context.
struct PlotRenderer {
    /// World (drawing units) → device transform. Must be y-up (no flip).
    var transform: CGAffineTransform
    /// Device units per plotted millimetre (line weights).
    var devicePerMM: CGFloat
    /// Paper output: white/near-white colors print black.
    var paper: Bool
    /// Thinnest stroke in device units.
    var minLineWidth: CGFloat = 0.1
    /// Multiplier applied to lineweights (1 = true plotted width).
    var lineweightScale: CGFloat = 1
    /// Overrides every color (e.g. selection highlight) when set.
    var overrideColor: CGColor?
    /// Plot style: full color, monochrome (all black) or grayscale.
    var colorMode: PlotColorMode = .color
    /// Colour-dependent plot style table (pen colour, lineweight, screening per ACI colour), applied before `colorMode`.
    var penTable: PlotStyleTable?

    /// Applies a page setup (colour mode, lineweight scale, plot style table of the document).
    mutating func apply(_ setup: PageSetup, doc: ArchiDocument) {
        colorMode = setup.colorMode
        lineweightScale = CGFloat(setup.lineweightScale)
        penTable = PlotStyleTable.named(setup.plotStyleTable, in: doc)
        // Named plot styles (STB, SHT-031) replace the colour-dependent table: pens come from each object's style.
        if let stb = setup.namedStyleTable, let table = NamedPlotStyles.table(stb, in: doc) {
            penTable = nil
            let map = NamedPlotStyles.styleMap(doc)
            entryPen = { id in map[id].flatMap { table[$0] } }
        }
    }
    /// Pen of an object from its named plot style (nil = plot as is).
    var entryPen: ((EntityID) -> PlotStyleTable.Pen?)?
    /// Pen of the entry being drawn (set per entry from `entryPen`).
    var activePen: PlotStyleTable.Pen?

    /// Plotted line width in device units for a stroke style (the plot style table may override the lineweight).
    func width(_ style: ArchiCore.StrokeStyle) -> CGFloat {
        let lw = activePen?.lineweight ?? penTable?.resolve(color: style.color, lineweight: style.lineweight).1 ?? style.lineweight
        return max(minLineWidth, CGFloat(lw) * devicePerMM * lineweightScale)
    }

    var scaleFactor: CGFloat { sqrt(abs(transform.a * transform.d - transform.b * transform.c)) }
    var rotation: CGFloat { atan2(transform.b, transform.a) }

    func point(_ p: Vec2) -> CGPoint { CGPoint(x: p.x, y: p.y).applying(transform) }

    func color(_ c0: RGBA) -> CGColor {
        if let o = overrideColor { return o }
        var c = penTable?.resolve(color: c0, lineweight: 0).0 ?? c0
        if let p = activePen { c = NamedPlotStyles.apply(p, to: c) }
        switch colorMode {
        case .monochrome: return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: c.a)
        case .grayscale:
            let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            let v = paper && lum > 0.82 ? 0 : (paper ? min(lum, 0.75) : lum)
            return CGColor(srgbRed: v, green: v, blue: v, alpha: c.a)
        case .color: break
        }
        var r = c.r, g = c.g, b = c.b
        if paper {
            if min(r, g, b) > 0.82 { r = 0; g = 0; b = 0 }
            else {
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                if lum > 0.75 { r *= 0.55; g *= 0.55; b *= 0.55 }
            }
        }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: c.a)
    }

    func draw(_ entries: [DrawEntry], in ctx: CGContext, visible: CGRect? = nil) {
        for e in entries {
            if let v = visible, !e.bounds.isEmpty {
                let a = point(e.bounds.min), b = point(e.bounds.max)
                let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)).insetBy(dx: -2, dy: -2)
                if !r.intersects(v) { continue }
            }
            if let ep = entryPen, let id = e.id, let pen = ep(id) {
                var r = self; r.activePen = pen
                for item in e.items { r.draw(item, in: ctx) }
            } else {
                for item in e.items { draw(item, in: ctx) }
            }
        }
    }

    func draw(_ item: DrawItem, in ctx: CGContext) {
        switch item {
        case .stroke(let pts, let closed, let style):
            guard pts.count >= 2 else {
                if let p = pts.first { // a point: tiny dot
                    let q = point(p); ctx.setFillColor(color(style.color))
                    let r = width(style)
                    ctx.fillEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
                }
                return
            }
            ctx.saveGState()
            let path = CGMutablePath()
            path.move(to: point(pts[0]))
            for p in pts.dropFirst() { path.addLine(to: point(p)) }
            if closed { path.closeSubpath() }
            ctx.addPath(path)
            ctx.setStrokeColor(color(style.color))
            ctx.setLineWidth(width(style))
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            if !style.dash.isEmpty {
                let s = scaleFactor
                let lengths = style.dash.map { v -> CGFloat in v == 0 ? 0.01 : CGFloat(abs(v)) * s }
                let total = lengths.reduce(0, +)
                if total > 1.5 { ctx.setLineCap(.butt); if style.dash.contains(0) { ctx.setLineCap(.round) }
                    ctx.setLineDash(phase: 0, lengths: lengths.count % 2 == 0 ? lengths : lengths + lengths) }
            }
            ctx.strokePath()
            ctx.restoreGState()
        case .fill(let loops, let c):
            let path = CGMutablePath()
            for l in loops where l.count >= 3 {
                path.move(to: point(l[0])); for p in l.dropFirst() { path.addLine(to: point(p)) }; path.closeSubpath()
            }
            guard !path.isEmpty else { return }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setFillColor(color(c))
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        case .text(let t, let font, let c):
            drawText(t, font: font, color: color(c), in: ctx)
        case .image(let im):
            drawImage(im, in: ctx)
        }
    }

    func drawText(_ t: TextGeom, font fontName: String, color: CGColor, in ctx: CGContext) {
        let h = CGFloat(t.height) * scaleFactor
        guard h > 0.4, h < 20000, !t.content.isEmpty else { return }
        let probe = CTFontCreateWithName(fontName as CFString, 100, nil)
        let capRatio = max(0.5, CTFontGetCapHeight(probe) / 100)
        let font = CTFontCreateWithName(fontName as CFString, h / capRatio, nil)
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                     NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
        func makeLine(_ s: String) -> CTLine { CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs)) }
        func width(_ l: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) }
        // Paragraphs: "\n" or MTEXT "\P".
        let paragraphs = t.content.replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
        var lines: [String] = []
        let wrap = CGFloat(t.width) * scaleFactor
        for para in paragraphs {
            guard wrap > 0 else { lines.append(para); continue }
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let cand = cur.isEmpty ? String(word) : cur + " " + word
                if !cur.isEmpty && width(makeLine(cand)) > wrap { lines.append(cur); cur = String(word) } else { cur = cand }
            }
            lines.append(cur)
        }
        let spacing = h * 1.6
        let n = CGFloat(lines.count)
        var firstBaseline: CGFloat
        switch t.valign {
        case .baseline: firstBaseline = lines.count > 1 && t.width > 0 ? -h : 0
        case .bottom: firstBaseline = (n - 1) * spacing + h * 0.3
        case .middle: firstBaseline = ((n - 1) * spacing) / 2 - h / 2
        case .top: firstBaseline = -h
        }
        ctx.saveGState()
        let origin = point(t.position)
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.rotate(by: CGFloat(t.rotation) + rotation)
        ctx.textMatrix = .identity
        for (i, s) in lines.enumerated() where !s.isEmpty {
            let line = makeLine(s)
            let w = width(line)
            let x: CGFloat = t.halign == .left ? 0 : (t.halign == .center ? -w / 2 : -w)
            ctx.textPosition = CGPoint(x: x, y: firstBaseline - CGFloat(i) * spacing)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    func drawImage(_ im: ImageGeom, in ctx: CGContext) {
        guard let img = NSImage(contentsOfFile: (im.path as NSString).expandingTildeInPath),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Missing image: draw a crossed frame.
            let corners = [im.origin, im.origin + Vec2(im.size.x, 0), im.origin + im.size, im.origin + Vec2(0, im.size.y)].map { $0.rotated(by: im.rotation, around: im.origin) }
            draw(.stroke(points: corners, closed: true, style: ArchiCore.StrokeStyle(color: RGBA(0.6, 0.6, 0.6), lineweight: 0.18)), in: ctx)
            draw(.stroke(points: [corners[0], corners[2]], closed: false, style: ArchiCore.StrokeStyle(color: RGBA(0.6, 0.6, 0.6), lineweight: 0.13)), in: ctx)
            return
        }
        ctx.saveGState()
        let o = point(im.origin)
        ctx.translateBy(x: o.x, y: o.y)
        ctx.rotate(by: CGFloat(im.rotation) + rotation)
        let s = scaleFactor
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(im.size.x) * s, height: CGFloat(im.size.y) * s))
        ctx.restoreGState()
    }
}

extension Array where Element == DrawEntry {
    var unionBounds: BBox2 { reduce(BBox2.empty) { $0.union($1.bounds) } }
}

// MARK: - Sheet composition (shared by SheetView and PDF plotting)

enum SheetComposer {
    static let margin = 10.0
    static let bindingMargin = 20.0
    static let titleBlockSize = Vec2(180, 42)
    static let bottomBand = 52.0

    /// Area on the paper available for viewports (mm).
    static func drawingArea(_ paper: PaperSize) -> BBox2 {
        BBox2(min: Vec2(bindingMargin + 4, margin + bottomBand), max: Vec2(paper.width - margin - 4, paper.height - margin - 4))
    }

    /// Default section line: horizontal through the model center.
    static func defaultSectionLine(_ doc: ArchiDocument) -> (Vec2, Vec2) {
        let b = GeometryOps.bounds(of: doc)
        if b.isEmpty { return (Vec2(-5000, 0), Vec2(5000, 0)) }
        return (Vec2(b.min.x - 1000, b.center.y), Vec2(b.max.x + 1000, b.center.y))
    }

    /// Model-space draw entries shown by a viewport, in that view's 2D coordinates.
    static func viewportEntries(doc: ArchiDocument, vp: Viewport) -> [DrawEntry] {
        // 3D viewports: shade plot of the model seen from the viewport's camera (always drawn on the main thread).
        if vp.view == .axonometric || vp.view == .perspective { return MainActor.assumeIsolated { ShadePlot.entries(doc: doc, vp: vp) } }
        switch vp.view {
        case .plan, .ceiling, .axonometric, .perspective:
            var o = DrawOptions(level: vp.level)
            o.forPaper = true
            o.linetypeScale = paperLinetypeScale(doc, vp)
            if vp.view == .ceiling { o.reflectedCeiling = true }
            return DrawListBuilder.entries(doc: doc, options: o)
        case .section:
            return ElevationBuilder.entries(doc: doc, view: .section, sectionLine: defaultSectionLine(doc))
        case .elevationNorth, .elevationSouth, .elevationEast, .elevationWest:
            return ElevationBuilder.entries(doc: doc, view: vp.view, sectionLine: nil)
        }
    }

    /// Linetype scale inside a viewport (LAY-025): with PSLTSCALE = 1 (default) dashes have the same length on paper in
    /// every viewport whatever its scale; with 0 they keep their model-space length (and shrink at smaller scales).
    static func paperLinetypeScale(_ doc: ArchiDocument, _ vp: Viewport) -> Double {
        doc.variable("PSLTSCALE") == "0" ? 1 : max(vp.scale, 1e-9) * 0.25
    }

    static func ratioText(_ scale: Double, units: Units) -> String {
        let r = scale * units.mm
        if r >= 1 { return "1:\(fmt(r, 1))" }
        return "\(fmt(1 / r, 1)):1"
    }

    static func viewTitle(_ vp: Viewport, doc: ArchiDocument) -> String {
        if !vp.title.isEmpty { return vp.title }
        switch vp.view {
        case .plan: return (vp.level.flatMap { doc.level($0)?.name } ?? "Plan") + " Plan"
        case .ceiling: return (vp.level.flatMap { doc.level($0)?.name } ?? "") + " Ceiling Plan"
        case .elevationNorth: return "North Elevation"
        case .elevationSouth: return "South Elevation"
        case .elevationEast: return "East Elevation"
        case .elevationWest: return "West Elevation"
        case .section: return "Section A-A"
        case .axonometric: return "Axonometric"
        case .perspective: return "Perspective"
        }
    }

    static func dateText() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    /// Frame, title block, north arrow, scale bar and viewport captions in paper millimetres.
    static func decorations(doc: ArchiDocument, layout: Layout, layoutIndex: Int) -> [DrawEntry] {
        let W = layout.paper.width, H = layout.paper.height
        let ink = RGBA.black
        func s(_ w: Double) -> ArchiCore.StrokeStyle { ArchiCore.StrokeStyle(color: ink, lineweight: w) }
        func text(_ p: Vec2, _ h: Double, _ str: String, _ ha: HAlign = .left, _ va: VAlign = .baseline) -> DrawItem {
            .text(TextGeom(position: p, height: h, content: str, halign: ha, valign: va), font: "Helvetica", color: ink)
        }
        func rect(_ a: Vec2, _ b: Vec2, _ w: Double) -> DrawItem {
            .stroke(points: [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)], closed: true, style: s(w))
        }
        var out: [DrawEntry] = []
        // Drawing frame.
        out.append(DrawEntry(id: nil, items: [rect(Vec2(bindingMargin, margin), Vec2(W - margin, H - margin), 0.5)]))
        // Title block.
        let tb = titleBlockSize
        let x0 = W - margin - tb.x, y0 = margin, x1 = W - margin, y1 = margin + tb.y
        // Keys are lower camel case; files made by earlier templates used "Project"/"Sheet"/"Scale".
        var tbv = layout.titleBlock
        for (legacy, key) in [("Project", "project"), ("Sheet", "sheetNumber"), ("Scale", "scale")] where tbv[key] == nil {
            if let v = tbv[legacy] { tbv[key] = v }
        }
        let info = doc.info
        let scales = Array(Set(layout.viewports.map { ratioText($0.scale, units: doc.units) })).sorted()
        let scaleText = tbv["scale"] ?? (scales.isEmpty ? "—" : (scales.count == 1 ? scales[0] : "As indicated"))
        let sheetNo = tbv["sheetNumber"] ?? String(format: "A-%03d", layoutIndex + 101)
        // Custom title block (SHT-014): a block with {field} placeholders replaces the built-in one.
        var values: [String: String] = ["project": tbv["project"] ?? info.name, "sheetName": tbv["sheetName"] ?? layout.name, "sheetNumber": sheetNo,
                                        "scale": scaleText, "date": tbv["date"] ?? dateText(), "revision": tbv["revision"] ?? "—", "client": tbv["client"] ?? info.client,
                                        "author": tbv["author"] ?? info.author, "number": tbv["number"] ?? info.number, "paper": layout.paper.name, "address": info.address]
        for (k, v) in SheetTools.fields(doc, layout: layout) { values[k] = v }
        if let custom = MainActor.assumeIsolated({ CustomTitleBlock.entries(doc: doc, layout: layout, anchor: Vec2(x1, y0), values: values) }) {
            out += custom
        } else {
        var items: [DrawItem] = [rect(Vec2(x0, y0), Vec2(x1, y1), 0.5)]
        // Rows: header band 14 mm, then 3 rows of 9.33 mm.
        let colA = x0 + 70, colB = x0 + 125
        items.append(.stroke(points: [Vec2(x0, y1 - 14), Vec2(x1, y1 - 14)], closed: false, style: s(0.35)))
        items.append(.stroke(points: [Vec2(colA, y0), Vec2(colA, y1 - 14)], closed: false, style: s(0.25)))
        items.append(.stroke(points: [Vec2(colB, y0), Vec2(colB, y1 - 14)], closed: false, style: s(0.25)))
        let rowH = (tb.y - 14) / 3
        for i in 1..<3 { let y = y0 + Double(i) * rowH
            items.append(.stroke(points: [Vec2(x0, y), Vec2(x1, y)], closed: false, style: s(0.18))) }
        // Office logo (TITLEBLOCKLOGO, an image path) at the left of the header band; the project name moves right of it.
        var nameX = x0 + 3
        if let logo = doc.variable("TITLEBLOCKLOGO"), !logo.isEmpty {
            let lw = 26.0, lh = 11.0
            items.append(.image(ImageGeom(path: logo, origin: Vec2(x0 + 2, y1 - 12.5), size: Vec2(lw, lh))))
            nameX += lw + 2
        }
        items.append(text(Vec2(nameX, y1 - 7), 4.5, tbv["project"] ?? info.name, .left, .middle))
        items.append(text(Vec2(x1 - 3, y1 - 4.5), 2.2, "OANARINA ARCHI TOOL", .right, .middle))
        items.append(text(Vec2(x1 - 3, y1 - 10), 2, info.address, .right, .middle))
        func field(_ x: Double, _ row: Int, _ label: String, _ value: String, big: Bool = false) {
            let yb = y0 + Double(2 - row) * rowH
            items.append(text(Vec2(x + 2, yb + rowH - 2.6), 1.6, label.uppercased(), .left, .middle))
            items.append(text(Vec2(x + 2, yb + 2.4), big ? 3.2 : 2.5, value, .left, .baseline))
        }
        field(x0, 0, "Sheet", tbv["sheetName"] ?? layout.name)
        field(x0, 1, "Client", tbv["client"] ?? info.client)
        field(x0, 2, "Drawn by", tbv["author"] ?? info.author)
        field(colA, 0, "Project no.", tbv["number"] ?? info.number)
        field(colA, 1, "Scale", scaleText)
        field(colA, 2, "Date", tbv["date"] ?? dateText())
        field(colB, 0, "Sheet no.", sheetNo, big: true)
        field(colB, 1, "Paper", layout.paper.name)
        field(colB, 2, "Revision", tbv["revision"] ?? "—")
        out.append(DrawEntry(id: nil, items: items))

        // Custom project / sheet fields (SHT-021): one 5 mm row each, stacked on top of the title block.
        let custom = SheetTools.fields(doc, layout: layout)
        if !custom.isEmpty {
            var rows: [DrawItem] = []
            for (k, f) in custom.enumerated() {
                let ya = y1 + Double(k) * 5, yb = ya + 5
                rows.append(rect(Vec2(x0, ya), Vec2(x1, yb), 0.18))
                rows.append(text(Vec2(x0 + 2, ya + 1.6), 1.6, f.0.uppercased(), .left, .baseline))
                rows.append(text(Vec2(colA, ya + 1.4), 2.2, f.1, .left, .baseline))
            }
            out.append(DrawEntry(id: nil, items: rows))
        }
        }

        // North arrow (left of the title block).
        let nc = Vec2(x0 - 16, margin + 20)
        let north = rad(info.northAngle)
        let tip = nc + Vec2(0, 11).rotated(by: north), left = nc + Vec2(-5, -8).rotated(by: north)
        let right = nc + Vec2(5, -8).rotated(by: north), mid = nc + Vec2(0, -4).rotated(by: north)
        out.append(DrawEntry(id: nil, items: [
            .stroke(points: GeometryOps.arcPoints(center: nc, radius: 9, start: 0, sweep: 2 * .pi), closed: true, style: s(0.25)),
            .fill(loops: [[tip, mid, right]], color: ink),
            .stroke(points: [tip, left, mid, right], closed: true, style: s(0.25)),
            text(nc + Vec2(0, 14).rotated(by: north), 3, "N", .center, .middle),
        ]))

        // Scale bar for the first viewport.
        if let vp = layout.viewports.first, vp.scale > 0 {
            let unitsPerMM = vp.scale * doc.units.mm           // real mm per paper mm
            let target = 60.0 * unitsPerMM                        // real mm for ~60 mm on paper
            let pow10 = pow(10, floor(log10(target)))
            let nice = [1.0, 2, 2.5, 5, 10].map { $0 * pow10 }.last { $0 <= target } ?? pow10
            let paperLen = nice / unitsPerMM
            let o = Vec2(bindingMargin + 6, margin + 12)
            var sb: [DrawItem] = []
            for i in 0..<5 {
                let a = o + Vec2(paperLen * Double(i) / 5, 0), b = o + Vec2(paperLen * Double(i + 1) / 5, 2.5)
                if i % 2 == 0 { sb.append(.fill(loops: [[a, Vec2(b.x, a.y), b, Vec2(a.x, b.y)]], color: ink)) }
            }
            sb.append(rect(o, o + Vec2(paperLen, 2.5), 0.25))
            func lbl(_ v: Double) -> String { v >= 1000 ? "\(fmt(v / 1000, 2)) m" : "\(fmt(v, 0)) mm" }
            sb.append(text(o + Vec2(0, 4.5), 2, "0", .center, .baseline))
            sb.append(text(o + Vec2(paperLen / 2, 4.5), 2, lbl(nice / 2), .center, .baseline))
            sb.append(text(o + Vec2(paperLen, 4.5), 2, lbl(nice), .center, .baseline))
            sb.append(text(o + Vec2(0, -4.5), 2, "SCALE " + ratioText(vp.scale, units: doc.units), .left, .baseline))
            out.append(DrawEntry(id: nil, items: sb))
        }

        // Revision table stacked on the title block (header row at the bottom, latest revision on top).
        let revs = SheetSet.revisions(layout)
        if !revs.isEmpty {
            let rh = 5.0, cols = [14.0, 24, tb.x - 14 - 24 - 24, 24]
            var ri: [DrawItem] = []
            let rows = revs.count + 1
            let top = y1 + Double(rows) * rh
            ri.append(rect(Vec2(x0, y1), Vec2(x1, top), 0.35))
            for r in 1..<rows { let y = y1 + Double(r) * rh
                ri.append(.stroke(points: [Vec2(x0, y), Vec2(x1, y)], closed: false, style: s(r == 1 ? 0.35 : 0.18))) }
            var cx = x0
            for w in cols.dropLast() { cx += w; ri.append(.stroke(points: [Vec2(cx, y1), Vec2(cx, top)], closed: false, style: s(0.18))) }
            func rowText(_ r: Int, _ vals: [String], _ h: Double) {
                var x = x0
                for (k, v) in vals.enumerated() {
                    let maxChars = max(1, Int(cols[k] / (h * 0.62)))
                    ri.append(text(Vec2(x + 1.5, y1 + Double(r) * rh + rh / 2), h, v.count > maxChars ? String(v.prefix(maxChars - 1)) + "…" : v, .left, .middle))
                    x += cols[k]
                }
            }
            rowText(0, ["REV", "DATE", "DESCRIPTION", "BY"], 1.8)
            for (k, r) in revs.enumerated() { rowText(k + 1, [r.code, r.date, r.description, r.by], 2.2) }
            out.append(DrawEntry(id: nil, items: ri))
        }

        // Viewport captions (unless the sheet has editable view titles, see SheetSet.refreshViewTitles).
        for vp in layout.viewports where !SheetSet.hasViewTitleEntities(layout) {
            let p = vp.origin + Vec2(0, -6)
            let title = viewTitle(vp, doc: doc)
            out.append(DrawEntry(id: nil, items: [
                .fill(loops: [GeometryOps.arcPoints(center: p + Vec2(2.5, 1.2), radius: 2.2, start: 0, sweep: 2 * .pi)], color: ink),
                text(p + Vec2(7, 0), 3.2, title, .left, .baseline),
                .stroke(points: [p + Vec2(6, -1.4), p + Vec2(min(vp.size.x, 7 + Double(title.count) * 2.6), -1.4)], closed: false, style: s(0.35)),
                text(p + Vec2(7, -5), 2, ratioText(vp.scale, units: doc.units), .left, .baseline),
            ]))
        }
        return out
    }

    /// Paper-space entities of the layout (user annotations), drawn in mm.
    static func paperEntities(doc: ArchiDocument, layout: Layout) -> [DrawEntry] {
        var o = DrawOptions(level: nil); o.forPaper = true
        return layout.entities.filter { doc.isVisible(layer: $0.layer) }.map {
            DrawEntry(id: $0.id, items: DrawListBuilder.items(for: $0, doc: doc, options: o))
        }
    }

    static func modelToPaper(_ vp: Viewport) -> CGAffineTransform {
        let c = vp.origin + vp.size / 2
        let s = 1 / max(vp.scale, 1e-9)
        return CGAffineTransform(translationX: -vp.viewCenter.x, y: -vp.viewCenter.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
    }

    /// Draws a whole sheet. `paperToDevice` maps paper mm to device units (y-up).
    static func draw(doc: ArchiDocument, layoutIndex: Int, in ctx: CGContext, paperToDevice: CGAffineTransform,
                     devicePerMM: CGFloat, showViewportBorders: Bool, selectedViewport: Int? = nil,
                     entriesFor: ((Viewport) -> [DrawEntry])? = nil, visible: CGRect? = nil, setup: PageSetup? = nil) {
        guard doc.layouts.indices.contains(layoutIndex) else { return }
        let layout = doc.layouts[layoutIndex]
        for (i, vp) in layout.viewports.enumerated() {
            // Layers frozen in this viewport only (VPLAYER) bypass the caller's per-view cache.
            let entries: [DrawEntry]
            if ViewportLayers.frozen(doc, layout: layout.name, viewport: i).isEmpty {
                entries = entriesFor?(vp) ?? viewportEntries(doc: doc, vp: vp)
            } else {
                entries = viewportEntries(doc: ViewportLayers.document(for: doc, layout: layout.name, viewport: i), vp: vp)
            }
            var r = PlotRenderer(transform: modelToPaper(vp).concatenating(paperToDevice), devicePerMM: devicePerMM, paper: true, minLineWidth: 0.12)
            if let setup { r.apply(setup, doc: doc) }
            let a = CGPoint(x: vp.origin.x, y: vp.origin.y).applying(paperToDevice)
            let b = CGPoint(x: vp.origin.x + vp.size.x, y: vp.origin.y + vp.size.y).applying(paperToDevice)
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            // Polygonal / clipped viewports (SHT-004, SHT-008) clip to their boundary instead of the frame.
            let clipPath: CGPath? = SheetTools.clip(doc, layout: layout.name, viewport: i).map { pts in
                let pth = CGMutablePath(); pth.addLines(between: pts.map { CGPoint(x: $0.x, y: $0.y).applying(paperToDevice) }); pth.closeSubpath(); return pth
            }
            ctx.saveGState()
            if let cp = clipPath { ctx.addPath(cp); ctx.clip() } else { ctx.clip(to: rect) }
            r.draw(entries, in: ctx, visible: visible.map { $0.intersection(rect) } ?? rect)
            ctx.restoreGState()
            if showViewportBorders {
                ctx.saveGState()
                let sel = selectedViewport == i
                ctx.setStrokeColor(sel ? CGColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1) : CGColor(srgbRed: 0.3, green: 0.55, blue: 0.9, alpha: 0.8))
                ctx.setLineWidth(sel ? 2 : 1)
                if !sel { ctx.setLineDash(phase: 0, lengths: [4, 3]) }
                if let cp = clipPath { ctx.addPath(cp); ctx.strokePath() } else { ctx.stroke(rect) }
                ctx.restoreGState()
            }
        }
        var paperR = PlotRenderer(transform: paperToDevice, devicePerMM: devicePerMM, paper: true, minLineWidth: 0.12)
        if let setup { paperR.apply(setup, doc: doc) }
        paperR.draw(paperEntities(doc: doc, layout: layout), in: ctx)
        paperR.draw(decorations(doc: doc, layout: layout, layoutIndex: layoutIndex), in: ctx)
        if let setup, setup.plotStamp {
            paperR.draw([PlotStamp.entry(doc: doc, name: layout.name, paperWidth: layout.paper.width, setup: setup)], in: ctx)
        }
    }
}

// MARK: - Plotter

enum PlotError: Error, LocalizedError {
    case cannotCreate(String)
    var errorDescription: String? { if case .cannotCreate(let p) = self { return "Cannot create PDF at \(p)." }; return nil }
}

enum Plotter {
    static let pointsPerMM: CGFloat = 72 / 25.4
    static let standardRatios: [Double] = [1, 2, 5, 10, 20, 25, 50, 75, 100, 125, 200, 250, 500, 1000, 1250, 2000, 2500, 5000, 10000, 20000, 50000, 100000]

    /// Vector PDF of a sheet (true scale on its paper) or of model space fitted to A3 landscape.
    @MainActor static func exportPDF(model: AppModel, to url: URL, layoutIndex: Int?) throws {
        try writePDF(doc: model.doc, to: url, layoutIndex: layoutIndex, level: model.doc.currentLevel)
    }

    @MainActor static func writePDF(doc: ArchiDocument, to url: URL, layoutIndex: Int?, level: Int?) throws {
        if let li = layoutIndex, doc.layouts.indices.contains(li) {
            let layout = doc.layouts[li]
            var box = CGRect(x: 0, y: 0, width: layout.paper.width * pointsPerMM, height: layout.paper.height * pointsPerMM)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, pdfInfo(doc, title: layout.name)) else { throw PlotError.cannotCreate(url.path) }
            ctx.beginPDFPage(nil)
            ctx.setFillColor(.white); ctx.fill(box)
            SheetComposer.draw(doc: doc, layoutIndex: li, in: ctx, paperToDevice: CGAffineTransform(scaleX: pointsPerMM, y: pointsPerMM),
                               devicePerMM: pointsPerMM, showViewportBorders: false, setup: PageSetup.load(doc, layoutIndex: li))
            ctx.endPDFPage()
            ctx.closePDF()
        } else {
            try writeModelPDF(doc: doc, to: url, level: level)
        }
    }

    /// What a model-space plot shows (SHT-028) and at which ratio 1:n (SHT-029): the plot area's box, then the fixed
    /// scale, the exact fit, or the largest standard scale that fits the printable area (paper mm).
    static func modelFrame(doc: ArchiDocument, setup: PageSetup, extents: BBox2, area: BBox2) -> (box: BBox2, ratio: Double) {
        var b = extents.isEmpty ? GeometryOps.bounds(of: doc) : extents
        switch setup.plotArea {
        case .extents: break
        case .display, .window: if let w = setup.windowBox { b = w }
        case .limits:
            func pt(_ k: String) -> Vec2? {
                guard let s = doc.variable(k) else { return nil }
                let c = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                return c.count >= 2 ? Vec2(c[0], c[1]) : nil
            }
            let lb = BBox2(points: [pt("LIMMIN") ?? .zero, pt("LIMMAX") ?? Vec2(420, 297)])
            if lb.width > 0 && lb.height > 0 { b = lb }
        }
        var ratio = 100.0
        if let fixed = setup.modelScale, fixed > 0 { ratio = fixed }
        else if !b.isEmpty && b.width + b.height > 0 {
            let needed = max(b.width / area.width, b.height / area.height) * doc.units.mm
            ratio = setup.exactFit ? max(needed, 1e-9) : (standardRatios.first { $0 >= needed } ?? (ceil(needed / 1000) * 1000))
        }
        return (b, ratio)
    }

    /// Model space of one level, plotted at the largest standard scale that fits A3 landscape.
    @MainActor static func writeModelPDF(doc: ArchiDocument, to url: URL, level: Int?) throws {
        let setup = PageSetup.load(doc, layoutIndex: nil)
        let paperSize = setup.modelPaperSize
        let paperW = paperSize.width, paperH = paperSize.height, margin = 10.0, strip = 18.0
        var box = CGRect(x: 0, y: 0, width: paperW * pointsPerMM, height: paperH * pointsPerMM)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, pdfInfo(doc, title: doc.info.name)) else { throw PlotError.cannotCreate(url.path) }
        var opts = DrawOptions(level: level)
        opts.forPaper = true
        var entries = DrawListBuilder.entries(doc: doc, options: opts)
        let area = BBox2(min: Vec2(margin + 3, margin + strip + 3), max: Vec2(paperW - margin - 3, paperH - margin - 3))
        let (b, ratio) = modelFrame(doc: doc, setup: setup, extents: entries.unionBounds, area: area)
        let scale = ratio / doc.units.mm  // model units per paper mm
        if opts.linetypeScale != max(1, scale * 0.25) {
            opts.linetypeScale = max(1, scale * 0.25)
            entries = DrawListBuilder.entries(doc: doc, options: opts)
        }
        let center = b.isEmpty ? Vec2.zero : b.center
        let s = pointsPerMM / CGFloat(scale)
        let t = CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: area.center.x * pointsPerMM, y: area.center.y * pointsPerMM))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(.white); ctx.fill(box)
        let clip = CGRect(x: area.min.x * pointsPerMM, y: area.min.y * pointsPerMM, width: area.width * pointsPerMM, height: area.height * pointsPerMM)
        ctx.saveGState(); ctx.clip(to: clip.insetBy(dx: -3 * pointsPerMM, dy: -3 * pointsPerMM))
        var modelR = PlotRenderer(transform: t, devicePerMM: pointsPerMM, paper: true, minLineWidth: 0.12)
        modelR.apply(setup, doc: doc)
        modelR.draw(entries, in: ctx)
        ctx.restoreGState()
        // Frame and title strip.
        let ink = RGBA.black
        let st = ArchiCore.StrokeStyle(color: ink, lineweight: 0.5)
        let levelName = level.flatMap { doc.level($0)?.name } ?? "All levels"
        let deco: [DrawItem] = [
            .stroke(points: [Vec2(margin, margin), Vec2(paperW - margin, margin), Vec2(paperW - margin, paperH - margin), Vec2(margin, paperH - margin)], closed: true, style: st),
            .stroke(points: [Vec2(margin, margin + strip), Vec2(paperW - margin, margin + strip)], closed: false, style: ArchiCore.StrokeStyle(color: ink, lineweight: 0.35)),
            .text(TextGeom(position: Vec2(margin + 4, margin + strip / 2), height: 4, content: doc.info.name, valign: .middle), font: "Helvetica", color: ink),
            .text(TextGeom(position: Vec2(paperW / 2, margin + strip / 2), height: 2.8, content: "\(levelName)   ·   Scale \(SheetComposer.ratioText(scale, units: doc.units)) (\(paperSize.name))   ·   \(SheetComposer.dateText())", halign: .center, valign: .middle), font: "Helvetica", color: ink),
            .text(TextGeom(position: Vec2(paperW - margin - 4, margin + strip / 2), height: 2.4, content: "OANARINA ARCHI TOOL", halign: .right, valign: .middle), font: "Helvetica", color: ink),
        ]
        var decoR = PlotRenderer(transform: CGAffineTransform(scaleX: pointsPerMM, y: pointsPerMM), devicePerMM: pointsPerMM, paper: true)
        decoR.colorMode = setup.colorMode
        decoR.penTable = PlotStyleTable.named(setup.plotStyleTable, in: doc)
        decoR.draw([DrawEntry(id: nil, items: deco)], in: ctx)
        if setup.plotStamp { decoR.draw([PlotStamp.entry(doc: doc, name: levelName, paperWidth: paperW, setup: setup)], in: ctx) }
        ctx.endPDFPage()
        ctx.closePDF()
        PlotLog.record(drawing: doc.info.name, output: "PDF (model, \(paperSize.name), 1:\(fmt(ratio, 0)))", sheets: levelName,
                       style: setup.plotStyleTable ?? setup.colorMode.rawValue, file: url.path)
    }

    static func pdfInfo(_ doc: ArchiDocument, title: String) -> CFDictionary {
        [kCGPDFContextTitle: title, kCGPDFContextCreator: "Oanarina Archi Tool", kCGPDFContextAuthor: doc.info.author] as CFDictionary
    }

    /// Prints the active sheet (in Sheet mode) or the current level's model space.
    @MainActor static func printDrawing(model: AppModel) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiPrint-\(UUID().uuidString).pdf")
        let layout: Int? = model.mode == .sheet && model.doc.layouts.indices.contains(model.activeLayout) ? model.activeLayout : nil
        do {
            try exportPDF(model: model, to: url, layoutIndex: layout)
            guard let pdf = PDFDocument(url: url) else { return }
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            if let page = pdf.page(at: 0) {
                let r = page.bounds(for: .mediaBox)
                info.orientation = r.width > r.height ? .landscape : .portrait
            }
            info.horizontalPagination = .fit; info.verticalPagination = .fit
            guard let op = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { return }
            op.jobTitle = model.doc.info.name
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            if let w = NSApp.keyWindow ?? NSApp.mainWindow {
                op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil)
            } else { op.run() }
        } catch {
            model.editor.print("Plot failed: \(error.localizedDescription)")
        }
    }

    /// PNG of the plan (agent screenshots): dark screen colors or white paper.
    @MainActor static func planPNG(doc: ArchiDocument, level: Int?, width: Int, height: Int, paper: Bool, highlight: Set<EntityID> = []) -> Data? {
        let w = max(16, min(width, 8192)), h = max(16, min(height, 8192))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(paper ? .white : CGColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var o = DrawOptions(level: level); o.forPaper = paper
        let entries = DrawListBuilder.entries(doc: doc, options: o)
        var b = entries.unionBounds
        if b.isEmpty { b = BBox2(min: Vec2(-5000, -5000), max: Vec2(5000, 5000)) }
        let pad = 0.05
        let s = min(Double(w) / (b.width * (1 + 2 * pad) + 1e-9), Double(h) / (b.height * (1 + 2 * pad) + 1e-9))
        let t = CGAffineTransform(translationX: -b.center.x, y: -b.center.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: Double(w) / 2, y: Double(h) / 2))
        ctx.setShouldAntialias(true)
        var r = PlotRenderer(transform: t, devicePerMM: 2.5, paper: paper, minLineWidth: 1)
        r.draw(entries.filter { $0.id.map { !highlight.contains($0) } ?? true }, in: ctx)
        r.overrideColor = CGColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1)
        r.draw(entries.filter { $0.id.map { highlight.contains($0) } ?? false }, in: ctx)
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
    }
}
