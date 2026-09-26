// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import CoreText
import Combine
import ArchiCore

// MARK: - Render scene (cached Core Graphics paths built from DrawEntries)

/// Parameters controlling how strokes are drawn.
struct RenderParams {
    /// Show plotted lineweights.
    var lineweights = true
    /// Device points per millimetre of lineweight.
    var lwScale: CGFloat = 3.2
    /// Minimum line width in device points.
    var minWidth: CGFloat = 0.5
    /// Max display width (points).
    var maxWidth: CGFloat = 8
    func width(_ lw: Double) -> CGFloat {
        guard lineweights else { return minWidth }
        return min(maxWidth, max(minWidth, CGFloat(lw) * lwScale))
    }
}

@inline(__always) func cg(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }
@inline(__always) func vec(_ p: CGPoint) -> Vec2 { Vec2(Double(p.x), Double(p.y)) }

/// World-space geometry prepared once per document revision and drawn many times (pan/zoom).
final class RenderScene {
    struct TextRun {
        var lines: [(line: CTLine, origin: CGPoint)]
        var position: CGPoint
        var rotation: CGFloat
        var color: CGColor
        var height: CGFloat
        var localBox: CGRect
        var box: CGRect
    }
    struct Prepared {
        var id: EntityID?
        var bounds: CGRect = .null
        var strokes: [(path: CGPath, style: Int)] = []
        var fills: [(path: CGPath, color: CGColor)] = []
        var texts: [TextRun] = []
        var images: [ImageGeom] = []
        var dots: [(point: CGPoint, color: CGColor)] = []
        /// Raw stroke polylines for picking and crossing tests.
        var polylines: [[Vec2]] = []
        var fillLoops: [[Vec2]] = []
    }
    struct Chunk {
        var bounds: CGRect = .null
        var fills: [(path: CGPath, color: CGColor)] = []
        var strokes: [Int: CGMutablePath] = [:]
        var texts: [TextRun] = []
        var images: [ImageGeom] = []
        var dots: [(point: CGPoint, color: CGColor)] = []
        /// Objects in the chunk (adaptive degradation for very large views).
        var count = 0
    }

    /// Visible object count above which strokes are drawn as sub-pixel hairlines.
    static var degradeCount = 30_000
    /// Stroke paths of the whole scene per style (drawing everything, e.g. at extents).
    private var merged: [Int: CGPath]?
    private(set) var styles: [ArchiCore.StrokeStyle] = []
    private(set) var entries: [Prepared] = []
    private(set) var chunks: [Chunk] = []
    /// Entry indices per object id.
    private(set) var index: [EntityID: [Int]] = [:]
    private(set) var bounds: CGRect = .null

    init(_ drawEntries: [DrawEntry]) {
        var styleIndex: [ArchiCore.StrokeStyle: Int] = [:]
        entries.reserveCapacity(drawEntries.count)
        for e in drawEntries {
            var p = Prepared(id: e.id)
            for it in e.items { RenderScene.add(it, to: &p, styles: &styles, styleIndex: &styleIndex) }
            if p.bounds.isNull, !e.bounds.isEmpty {
                p.bounds = CGRect(x: e.bounds.min.x, y: e.bounds.min.y, width: e.bounds.width, height: e.bounds.height)
            }
            if p.bounds.isNull { continue }
            p.bounds = RenderScene.padded(p.bounds)
            if let id = p.id { index[id, default: []].append(entries.count) }
            bounds = bounds.union(p.bounds)
            entries.append(p)
        }
        buildChunks()
    }

    static func padded(_ r: CGRect) -> CGRect {
        let eps = max(max(r.width, r.height) * 1e-6, 1e-4)
        return r.insetBy(dx: -eps, dy: -eps)
    }

    static func add(_ it: DrawItem, to p: inout Prepared, styles: inout [ArchiCore.StrokeStyle], styleIndex: inout [ArchiCore.StrokeStyle: Int]) {
        switch it {
        case .stroke(let pts, let closed, let st):
            guard let first = pts.first else { return }
            if pts.count == 1 {
                p.dots.append((cg(first), st.color.cgColor))
                p.polylines.append(pts)
                p.bounds = p.bounds.union(CGRect(origin: cg(first), size: .zero))
                return
            }
            let path = CGMutablePath()
            path.addLines(between: pts.map(cg))
            if closed { path.closeSubpath() }
            let si: Int
            if let i = styleIndex[st] { si = i } else { styles.append(st); si = styles.count - 1; styleIndex[st] = si }
            p.strokes.append((path, si))
            p.polylines.append(closed ? pts + [first] : pts)
            p.bounds = p.bounds.union(path.boundingBoxOfPath)
        case .fill(let loops, let color):
            let path = CGMutablePath()
            for l in loops where l.count >= 3 { path.addLines(between: l.map(cg)); path.closeSubpath() }
            guard !path.isEmpty else { return }
            p.fills.append((path, color.cgColor))
            p.fillLoops.append(contentsOf: loops.filter { $0.count >= 3 })
            p.bounds = p.bounds.union(path.boundingBoxOfPath)
        case .text(let t, let font, let color):
            guard !t.content.isEmpty, t.height > 0 else { return }
            let run = RenderScene.layoutText(t, font: font, color: color)
            p.texts.append(run)
            p.bounds = p.bounds.union(run.box)
        case .image(let im):
            let tr = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
            let corners = [Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map(tr.apply)
            let b = BBox2(points: corners)
            p.images.append(im)
            p.polylines.append(corners + [corners[0]])
            p.bounds = p.bounds.union(CGRect(x: b.min.x, y: b.min.y, width: b.width, height: b.height))
        }
    }

    private func buildChunks() {
        guard !entries.isEmpty else { return }
        func put(_ e: Prepared, into c: inout Chunk) {
            c.bounds = c.bounds.union(e.bounds)
            c.count += 1
            c.fills += e.fills
            for s in e.strokes {
                if let m = c.strokes[s.style] { m.addPath(s.path) } else { let m = CGMutablePath(); m.addPath(s.path); c.strokes[s.style] = m }
            }
            c.texts += e.texts
            c.images += e.images
            c.dots += e.dots
        }
        if entries.count <= 1500 {
            var c = Chunk()
            for e in entries { put(e, into: &c) }
            chunks = [c]
            return
        }
        let n = min(64, max(2, Int((Double(entries.count) / 800).squareRoot().rounded(.up))))
        let cw = max(bounds.width / CGFloat(n), 1e-6), chh = max(bounds.height / CGFloat(n), 1e-6)
        var cells = Array(repeating: Chunk(), count: n * n)
        var big = Chunk()
        for e in entries {
            if e.bounds.width > cw * 2 || e.bounds.height > chh * 2 { put(e, into: &big); continue }
            let ix = min(n - 1, max(0, Int((e.bounds.midX - bounds.minX) / cw)))
            let iy = min(n - 1, max(0, Int((e.bounds.midY - bounds.minY) / chh)))
            put(e, into: &cells[iy * n + ix])
        }
        chunks = cells.filter { !$0.bounds.isNull }
        if !big.bounds.isNull { chunks.append(big) }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, visible: CGRect, scale: CGFloat, params: RenderParams) {
        let vis = chunks.indices.filter { chunks[$0].bounds.intersects(visible) }
        guard !vis.isEmpty else { return }
        // 1. Fills (hatches, wall poché) under everything.
        for ci in vis {
            for f in chunks[ci].fills where f.path.boundingBoxOfPath.intersects(visible) {
                ctx.addPath(f.path); ctx.setFillColor(f.color); ctx.fillPath(using: .evenOdd)
            }
        }
        // 2. Strokes batched per style. Views showing more than 30 000 objects draw sub-pixel strokes, which Core
        // Graphics rasterises on its fast path (AutoCAD-style adaptive degradation, VIS-001…010).
        ctx.setLineJoin(.round)
        let fast = vis.reduce(0) { $0 + chunks[$1].count } > RenderScene.degradeCount
        let devPerUnit = max(hypot(ctx.userSpaceToDeviceSpaceTransform.a, ctx.userSpaceToDeviceSpaceTransform.b), 1e-12)
        let whole = vis.count == chunks.count
        if whole && merged == nil {
            var m: [Int: CGPath] = [:]
            for si in styles.indices {
                let p = CGMutablePath()
                for c in chunks { if let q = c.strokes[si] { p.addPath(q) } }
                if !p.isEmpty { m[si] = p }
            }
            merged = m
        }
        for si in styles.indices {
            var any = false
            if whole { if let p = merged?[si] { ctx.addPath(p); any = true } }
            else { for ci in vis { if let path = chunks[ci].strokes[si] { ctx.addPath(path); any = true } } }
            guard any else { continue }
            applyStroke(styles[si], ctx: ctx, scale: scale, params: params, color: nil)
            if fast { ctx.setLineWidth(min(max(params.width(styles[si].lineweight), 0) / scale, 0.8 / devPerUnit)); ctx.setLineJoin(.miter) }
            ctx.strokePath()
        }
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        // 3. Points.
        let r = 1.6 / scale
        for ci in vis {
            for d in chunks[ci].dots where visible.contains(d.point) {
                ctx.setFillColor(d.color)
                ctx.fillEllipse(in: CGRect(x: d.point.x - r, y: d.point.y - r, width: 2 * r, height: 2 * r))
            }
        }
        // 4. Text.
        for ci in vis {
            for t in chunks[ci].texts where t.box.intersects(visible) { RenderScene.drawText(t, ctx: ctx, scale: scale, color: nil) }
        }
        // 5. Images.
        for ci in vis {
            for im in chunks[ci].images { RenderScene.drawImage(im, ctx: ctx, scale: scale) }
        }
    }

    func applyStroke(_ st: ArchiCore.StrokeStyle, ctx: CGContext, scale: CGFloat, params: RenderParams, color: CGColor?, extraWidth: CGFloat = 0) {
        let wPts = params.width(st.lineweight) + extraWidth
        let w = wPts / scale
        ctx.setLineWidth(w)
        ctx.setStrokeColor(color ?? st.color.cgColor)
        if !st.dash.isEmpty {
            let period = st.dash.reduce(0) { $0 + abs($1) }
            if CGFloat(period) * scale >= 4 {
                ctx.setLineCap(.butt)
                ctx.setLineDash(phase: 0, lengths: st.dash.map { $0 == 0 ? max(w, 1 / scale) : CGFloat(abs($0)) })
                return
            }
        }
        // Round caps cost Core Graphics ~15× more than butt caps; below 2 pt they look the same.
        ctx.setLineCap(wPts <= 2 ? .butt : .round)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// Draws selected / hovered entries with an override color.
    func drawHighlight(_ indices: [Int], ctx: CGContext, scale: CGFloat, params: RenderParams, color: CGColor, extraWidth: CGFloat, dashed: Bool, fillAlpha: CGFloat) {
        guard !indices.isEmpty else { return }
        ctx.setLineJoin(.round)
        if fillAlpha > 0 {
            ctx.setFillColor(color.copy(alpha: fillAlpha) ?? color)
            for i in indices { for f in entries[i].fills { ctx.addPath(f.path); ctx.fillPath(using: .evenOdd) } }
        }
        let path = CGMutablePath()
        for i in indices { for s in entries[i].strokes { path.addPath(s.path) } }
        if !path.isEmpty {
            ctx.addPath(path)
            ctx.setStrokeColor(color)
            let w = (params.width(0.25) + extraWidth) / scale
            ctx.setLineWidth(w)
            if dashed { ctx.setLineCap(.butt); ctx.setLineDash(phase: 0, lengths: [6 / scale, 3 / scale]) } else { ctx.setLineCap(.round); ctx.setLineDash(phase: 0, lengths: []) }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        let r = 2.5 / scale
        ctx.setFillColor(color)
        for i in indices {
            for d in entries[i].dots { ctx.fillEllipse(in: CGRect(x: d.point.x - r, y: d.point.y - r, width: 2 * r, height: 2 * r)) }
            for t in entries[i].texts { RenderScene.drawText(t, ctx: ctx, scale: scale, color: color) }
            for im in entries[i].images {
                let tr = Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation)
                let c = [Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map { cg(tr.apply($0)) }
                ctx.addLines(between: c + [c[0]]); ctx.setStrokeColor(color); ctx.setLineWidth(1.5 / scale); ctx.strokePath()
            }
        }
    }

    // MARK: Text

    private static var fontCache: [String: String] = [:]
    private static var capCache: [String: CGFloat] = [:]
    private static var ctFontCache: [String: CTFont] = [:]

    static func fontName(_ requested: String) -> String {
        if let c = fontCache[requested] { return c }
        var name = requested
        let lower = requested.lowercased()
        if lower.isEmpty || ["standard", "txt", "simplex", "romans", "arial.ttf", "txt.shx", "simplex.shx", "romans.shx", "isocp.shx"].contains(lower) { name = "Helvetica" }
        if lower.hasSuffix(".ttf") || lower.hasSuffix(".shx") { name = String(requested.dropLast(4)) }
        if NSFont(name: name, size: 12) == nil { name = "Helvetica" }
        fontCache[requested] = name
        return name
    }
    static func capRatio(_ name: String) -> CGFloat {
        if let c = capCache[name] { return c }
        let f = CTFontCreateWithName(name as CFString, 100, nil)
        var r = CTFontGetCapHeight(f) / 100
        if r <= 0.2 || r > 1.2 { r = 0.72 }
        capCache[name] = r
        return r
    }
    static func font(_ name: String, size: CGFloat) -> CTFont {
        let key = "\(name)|\(Double(size))"
        if let f = ctFontCache[key] { return f }
        let f = CTFontCreateWithName(name as CFString, size, nil)
        if ctFontCache.count > 4000 { ctFontCache.removeAll() }
        ctFontCache[key] = f
        return f
    }

    static func layoutText(_ t: TextGeom, font requested: String, color: RGBA) -> TextRun {
        let name = fontName(requested)
        let h = CGFloat(max(t.height, 1e-9))
        let size = h / capRatio(name)
        let ctFont = font(name, size: size)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let content = t.content.replacingOccurrences(of: "\\P", with: "\n").replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [CTLine] = []
        for para in content.components(separatedBy: "\n") {
            let ats = NSAttributedString(string: para.isEmpty ? " " : para, attributes: attrs)
            if t.width > 0 {
                let ts = CTTypesetterCreateWithAttributedString(ats)
                var start = 0
                let len = ats.length
                while start < len {
                    let cnt = max(1, CTTypesetterSuggestLineBreak(ts, start, Double(t.width)))
                    lines.append(CTTypesetterCreateLine(ts, CFRange(location: start, length: cnt)))
                    start += cnt
                }
            } else {
                lines.append(CTLineCreateWithAttributedString(ats))
            }
        }
        let spacing = h * 5 / 3
        let n = CGFloat(lines.count)
        let blockH = h + (n - 1) * spacing
        let firstBaseline: CGFloat
        switch t.valign {
        case .baseline: firstBaseline = 0
        case .top: firstBaseline = -h
        case .middle: firstBaseline = blockH / 2 - h
        case .bottom: firstBaseline = (n - 1) * spacing + h * 0.25
        }
        var out: [(CTLine, CGPoint)] = []
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for (i, l) in lines.enumerated() {
            let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
            let x: CGFloat
            switch t.halign { case .left: x = 0; case .center: x = -w / 2; case .right: x = -w }
            out.append((l, CGPoint(x: x, y: firstBaseline - CGFloat(i) * spacing)))
            minX = min(minX, x); maxX = max(maxX, x + w)
        }
        if !minX.isFinite { minX = 0; maxX = 0 }
        let lastBaseline = firstBaseline - (n - 1) * spacing
        let local = CGRect(x: minX, y: lastBaseline - h * 0.3, width: maxX - minX, height: firstBaseline + h * 1.05 - (lastBaseline - h * 0.3))
        let rot = CGFloat(t.rotation)
        let tr = CGAffineTransform(translationX: CGFloat(t.position.x), y: CGFloat(t.position.y)).rotated(by: rot)
        let box = local.applying(tr)
        return TextRun(lines: out, position: cg(t.position), rotation: rot, color: color.cgColor, height: h, localBox: local, box: box)
    }

    static func drawText(_ t: TextRun, ctx: CGContext, scale: CGFloat, color: CGColor?) {
        let screenH = t.height * scale
        if screenH < 1.2 { return }
        ctx.saveGState()
        ctx.translateBy(x: t.position.x, y: t.position.y)
        ctx.rotate(by: t.rotation)
        if screenH < 3.5 {
            // Greeking: tiny text becomes a faint bar.
            ctx.setFillColor((color ?? t.color).copy(alpha: 0.35) ?? t.color)
            for (l, o) in t.lines {
                let w = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
                ctx.fill(CGRect(x: o.x, y: o.y, width: w, height: t.height))
            }
        } else {
            ctx.setFillColor(color ?? t.color)
            ctx.textMatrix = .identity
            for (l, o) in t.lines { ctx.textPosition = o; CTLineDraw(l, ctx) }
        }
        ctx.restoreGState()
    }

    // MARK: Images

    private static var imageCache: [String: CGImage] = [:]
    private static var missingImages: Set<String> = []
    static func cgImage(_ path: String) -> CGImage? {
        if let i = imageCache[path] { return i }
        if missingImages.contains(path) { return nil }
        guard let ns = NSImage(contentsOfFile: path), let img = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { missingImages.insert(path); return nil }
        imageCache[path] = img
        return img
    }
    static func drawImage(_ im: ImageGeom, ctx: CGContext, scale: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: im.origin.x, y: im.origin.y)
        ctx.rotate(by: CGFloat(im.rotation))
        let r = CGRect(x: 0, y: 0, width: im.size.x, height: im.size.y)
        if let img = cgImage(im.path) {
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: r)
        } else {
            ctx.setStrokeColor(NSColor.systemRed.cgColor); ctx.setLineWidth(1 / scale)
            ctx.stroke(r)
            ctx.move(to: r.origin); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            ctx.move(to: CGPoint(x: r.minX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Draws transient items (previews) directly.
    static func drawItems(_ items: [DrawItem], ctx: CGContext, scale: CGFloat, params: RenderParams, colorOverride: CGColor? = nil) {
        var st: [ArchiCore.StrokeStyle] = []
        var idx: [ArchiCore.StrokeStyle: Int] = [:]
        var p = Prepared(id: nil)
        for it in items { add(it, to: &p, styles: &st, styleIndex: &idx) }
        for f in p.fills { ctx.addPath(f.path); ctx.setFillColor(colorOverride?.copy(alpha: 0.25) ?? f.color); ctx.fillPath(using: .evenOdd) }
        ctx.setLineJoin(.round)
        for s in p.strokes {
            let style = st[s.style]
            ctx.addPath(s.path)
            ctx.setLineWidth(params.width(style.lineweight) / scale)
            ctx.setStrokeColor(colorOverride ?? style.color.cgColor)
            if !style.dash.isEmpty, CGFloat(style.dash.reduce(0) { $0 + abs($1) }) * scale >= 4 {
                ctx.setLineDash(phase: 0, lengths: style.dash.map { $0 == 0 ? 1 / scale : CGFloat(abs($0)) })
            } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
        for t in p.texts { drawText(t, ctx: ctx, scale: scale, color: colorOverride) }
        for d in p.dots {
            let r = 2 / scale
            ctx.setFillColor(colorOverride ?? d.color)
            ctx.fillEllipse(in: CGRect(x: d.point.x - r, y: d.point.y - r, width: 2 * r, height: 2 * r))
        }
        for im in p.images { drawImage(im, ctx: ctx, scale: scale) }
    }

    // MARK: Hit testing

    /// Distance from a world point to the drawn geometry of an entry.
    func distance(from q: Vec2, entry i: Int) -> Double {
        let e = entries[i]
        var best = Double.infinity
        for pl in e.polylines {
            if pl.count == 1 { best = min(best, q.distance(to: pl[0])); continue }
            for k in 0..<(pl.count - 1) { best = min(best, GeometryOps.distance(point: q, segA: pl[k], segB: pl[k + 1])) }
        }
        for l in e.fillLoops where GeometryOps.pointInPolygon(q, l) { return 0 }
        for t in e.texts {
            let inv = CGAffineTransform(translationX: t.position.x, y: t.position.y).rotated(by: t.rotation).inverted()
            if t.localBox.contains(cg(q).applying(inv)) { return 0 }
        }
        return best
    }

    /// Whether an entry crosses (touches) a box.
    func crosses(entry i: Int, box: BBox2) -> Bool {
        let e = entries[i]
        for pl in e.polylines {
            if pl.contains(where: { box.contains($0) }) { return true }
            if pl.count > 1 { for k in 0..<(pl.count - 1) where GeometryOps.segmentIntersectsBox(pl[k], pl[k + 1], box) { return true } }
        }
        for l in e.fillLoops {
            if l.contains(where: { box.contains($0) }) || GeometryOps.pointInPolygon(box.center, l) { return true }
        }
        let r = CGRect(x: box.min.x, y: box.min.y, width: box.width, height: box.height)
        for t in e.texts where t.box.intersects(r) { return true }
        return false
    }
}

// MARK: - Grips

/// Grip points and grip editing for entities and BIM elements.
enum GripEditor {
    static func grips(_ el: BIMElement, doc: ArchiDocument) -> [Vec2] {
        switch el.geometry {
        case .wall(let w): return [w.start, w.end, (w.start + w.end) / 2]
        case .curtainWall(let c): return [c.start, c.end, (c.start + c.end) / 2]
        case .beam(let b): return [b.start, b.end, (b.start + b.end) / 2]
        case .gridLine(let g): return [g.start, g.end, (g.start + g.end) / 2]
        case .column(let c): return [c.position]
        case .component(let c): return [c.position]
        case .stair(let s): return [s.start]
        // Vertices, then edge midpoints (drag an edge), then for roofs the slope grip (SEL-036).
        case .slab(let s): return s.boundary + BIMGrips.edgeMidpoints(s.boundary)
        case .roof(let r): return r.boundary + BIMGrips.edgeMidpoints(r.boundary) + (BIMGrips.slopeGrip(r, unit: 1000 / doc.units.mm).map { [$0] } ?? [])
        case .space(let s): return s.boundary + BIMGrips.edgeMidpoints(s.boundary)
        case .railing(let r): return r.path
        case .opening(let o):
            guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { return [] }
            return [w.centerStart + w.direction * o.offset]
        }
    }

    /// Entity grips come from the core grip model (SEL-032/037): vertices, midpoints, centres, quadrants, text width,
    /// dimension text and extension-line origins. Index = position in the list.
    static func grips(_ e: Entity) -> [Vec2] { Grips.grips(e.geometry).map(\.point) }
    static func grip(_ g: Geometry, _ i: Int) -> Grip? { let gs = Grips.grips(g); return gs.indices.contains(i) ? gs[i] : nil }

    /// Stretch of grip `i` to `p` (SEL-033), through the core grip editor.
    static func moved(_ g: Geometry, grip i: Int, from o: Vec2, to p: Vec2) -> Geometry {
        guard let gr = grip(g, i) else { return GeometryOps.transform(g, .translation(p - o)) }
        return Grips.stretched(g, grip: gr, to: p)
    }

    static func translated(_ g: BIMGeometry, by d: Vec2) -> BIMGeometry {
        switch g {
        case .wall(var w): w.start += d; w.end += d; return .wall(w)
        case .curtainWall(var c): c.start += d; c.end += d; return .curtainWall(c)
        case .beam(var b): b.start += d; b.end += d; return .beam(b)
        case .gridLine(var gl): gl.start += d; gl.end += d; return .gridLine(gl)
        case .column(var c): c.position += d; return .column(c)
        case .component(var c): c.position += d; return .component(c)
        case .stair(var s): s.start += d; return .stair(s)
        case .slab(var s): s.boundary = s.boundary.map { $0 + d }; s.holes = s.holes.map { $0.map { $0 + d } }; return .slab(s)
        case .roof(var r): r.boundary = r.boundary.map { $0 + d }; return .roof(r)
        case .space(var s): s.boundary = s.boundary.map { $0 + d }; return .space(s)
        case .railing(var r): r.path = r.path.map { $0 + d }; return .railing(r)
        case .opening: return g
        }
    }

    static func moved(_ el: BIMElement, grip i: Int, from o: Vec2, to p: Vec2, doc: ArchiDocument) -> BIMGeometry {
        switch el.geometry {
        case .wall(var w):
            if i == 0 { w.start = p } else if i == 1 { w.end = p } else { w.start += p - o; w.end += p - o }
            return .wall(w)
        case .curtainWall(var c):
            if i == 0 { c.start = p } else if i == 1 { c.end = p } else { c.start += p - o; c.end += p - o }
            return .curtainWall(c)
        case .beam(var b):
            if i == 0 { b.start = p } else if i == 1 { b.end = p } else { b.start += p - o; b.end += p - o }
            return .beam(b)
        case .gridLine(var g):
            if i == 0 { g.start = p } else if i == 1 { g.end = p } else { g.start += p - o; g.end += p - o }
            return .gridLine(g)
        case .column(var c): c.position = p; return .column(c)
        case .component(var c): c.position = p; return .component(c)
        case .stair(var s): s.start = p; return .stair(s)
        case .slab(var s): s.boundary = BIMGrips.moved(s.boundary, grip: i, from: o, to: p); return .slab(s)
        case .roof(var r):
            if i == 2 * r.boundary.count { r.pitch = BIMGrips.pitch(r, dragTo: p, unit: 1000 / doc.units.mm) } else { r.boundary = BIMGrips.moved(r.boundary, grip: i, from: o, to: p) }
            return .roof(r)
        case .space(var s): s.boundary = BIMGrips.moved(s.boundary, grip: i, from: o, to: p); return .space(s)
        case .railing(var r): if r.path.indices.contains(i) { r.path[i] = p }; return .railing(r)
        case .opening(var op):
            guard let host = doc.element(op.hostWall), case .wall(let w) = host.geometry else { return el.geometry }
            let len = w.length
            let t = (p - w.centerStart).dot(w.direction)
            op.offset = min(max(t, op.width / 2), max(op.width / 2, len - op.width / 2))
            return .opening(op)
        }
    }

    /// Rotation of `turns` quarter turns (counter-clockwise) about the dragged grip point — Space while dragging (MOD-029).
    static func quarterTurn(_ turns: Int, about p: Vec2) -> Transform2D? {
        let t = ((turns % 4) + 4) % 4
        return t == 0 ? nil : .rotation(Double(t) * .pi / 2, around: p)
    }
    /// A grip drag of an entity followed by `turns` quarter turns about the new grip position.
    static func moved(_ g: Geometry, grip i: Int, from o: Vec2, to p: Vec2, turns: Int) -> Geometry {
        let m = moved(g, grip: i, from: o, to: p)
        return quarterTurn(turns, about: p).map { GeometryOps.transform(m, $0) } ?? m
    }
    static func moved(_ el: BIMElement, grip i: Int, from o: Vec2, to p: Vec2, doc: ArchiDocument, turns: Int) -> BIMGeometry {
        let m = moved(el, grip: i, from: o, to: p, doc: doc)
        return quarterTurn(turns, about: p).map { CommandHelpers.transform(m, $0) } ?? m
    }

    /// Applies a grip edit as one undoable transaction. Wall endpoints drag joined walls along.
    @MainActor static func apply(editor: Editor, id: EntityID, grip i: Int, from o: Vec2, to p: Vec2, turns: Int = 0) {
        editor.transaction(quarterTurn(turns, about: p) == nil ? "Grip Edit" : "Grip Edit + Rotate") { d in
            if let k = d.entityIndex(id) {
                d.entities[k].geometry = moved(d.entities[k].geometry, grip: i, from: o, to: p, turns: turns)
            } else if let k = d.elementIndex(id) {
                let el = d.elements[k]
                d.elements[k].geometry = moved(el, grip: i, from: o, to: p, doc: d, turns: turns)
                if case .wall(let w) = el.geometry, i <= 1, quarterTurn(turns, about: p) == nil {
                    let old = i == 0 ? w.start : w.end
                    let tol = max(w.thickness * 0.01, 1e-6)
                    for j in d.elements.indices where j != k && d.elements[j].level == el.level {
                        if case .wall(var o2) = d.elements[j].geometry {
                            var changed = false
                            if o2.start.distance(to: old) <= tol { o2.start = p; changed = true }
                            if o2.end.distance(to: old) <= tol { o2.end = p; changed = true }
                            if changed { d.elements[j].geometry = .wall(o2) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SwiftUI wrapper

struct PlanCanvas: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> PlanCanvasView {
        let v = PlanCanvasView(model: model)
        if model.canvas?.window == nil { model.canvas = v }
        return v
    }
    func updateNSView(_ v: PlanCanvasView, context: Context) {
        // With several plan tiles, the one last clicked stays the active canvas (commands zoom and pan it).
        if model.canvas == nil || model.canvas?.window == nil { model.canvas = v }
        v.syncFromModel()
    }
}

/// Non-interactive layer views drawn by the canvas.
final class CanvasLayerView: NSView {
    var drawer: ((CGContext, NSRect) -> Void)?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawer?(ctx, dirtyRect)
    }
}

// MARK: - Canvas view

/// The 2D drafting canvas: Core Graphics, world→view transform, AutoCAD-style mouse and keyboard handling.
final class PlanCanvasView: NSView {
    private weak var model: AppModel?
    private let content = CanvasLayerView()
    private let overlay = CanvasLayerView()
    private var cancellables: Set<AnyCancellable> = []

    /// View points per world unit.
    private(set) var scale: CGFloat = 0.04
    /// World point at the view center.
    private(set) var center = CGPoint(x: 12000, y: 7000)
    /// Display rotation of the plan in radians (DVIEW TWist / VIEWTWIST, VIS-011): model coordinates never change.
    private(set) var twist: CGFloat = 0
    /// World point at the centre of the view.
    var viewCenterWorld: Vec2 { Vec2(Double(center.x), Double(center.y)) }
    private var scene: RenderScene?
    private var sceneKey: [Int] = []
    private var handledZoomRequest = -1
    private var needsInitialZoom = true

    // Interaction state
    private var mouseView: CGPoint?
    private var cursorPoint: Vec2 = .zero
    private var rawWorld: Vec2 = .zero
    private var snap: SnapResult?
    private var hoverID: EntityID?
    private var panLast: CGPoint?
    private var spaceDown = false
    private var spacePanned = false
    private struct WindowSel {
        enum Purpose { case select, request, zoom }
        var start: CGPoint; var current: CGPoint; var moved = false; var purpose: Purpose
        /// Freehand lasso points (⌥-drag, SEL-007); nil for a rectangular window.
        var lasso: [CGPoint]? = nil
    }
    private var windowSel: WindowSel?
    /// A grip being edited. `solve` = live constraint drag (Editor.dragSolve keeps every constraint satisfied while moving).
    private struct HotGrip { var id: EntityID; var index: Int; var origin: Vec2; var startView: CGPoint; var moved = false; var dragging = true; var solve = false
        /// Quarter turns added with Space while dragging (MOD-029).
        var turns = 0
        /// Grip mode cycled with Space / keywords while the grip is hot (SEL-034) and Copy.
        var mode: GripMode = .stretch
        var copy = false
        /// Multi-functional grip option chosen from the grip menu (SEL-035).
        var action: GripAction? = nil
        /// Drag distance that scales by 1 in Scale mode (half the selection size).
        var reference: Double = 1 }
    private var hotGrip: HotGrip?
    private var hoverGrip: (id: EntityID, index: Int, point: Vec2)?
    private var currentGrips: [(id: EntityID, index: Int, point: Vec2)] = []
    private var trackingArea: NSTrackingArea?

    private static let blankCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: img, hotSpot: .zero)
    }()

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        for v in [content, overlay] {
            v.wantsLayer = true
            v.layerContentsRedrawPolicy = .onSetNeedsDisplay
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
        content.drawer = { [weak self] ctx, r in self?.drawContent(ctx, r) }
        overlay.drawer = { [weak self] ctx, r in self?.drawOverlay(ctx, r) }
        if let c = model.planViewCenter, let s = model.planViewScale {
            center = c; scale = s; handledZoomRequest = model.zoomExtentsRequest
            // Keep the user's zoom when the canvas is recreated (mode switch); otherwise re-fit to the new size on the first layout.
            needsInitialZoom = !model.planUserZoomed
        }
        twist = CGFloat(rad(ViewTwist.degrees(model.doc)))
        model.$revision.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.modelChanged() }.store(in: &cancellables)
        registerForDraggedTypes([.string])
        model.gripInput = { [weak self] line in self?.handleGripInput(line) ?? false }
        model.cancelLocalModes = { [weak self] in self?.cancelLocalModes() ?? false }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Drag and drop from tool palettes (blocks, components, commands) and the material library

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let s = sender.draggingPasteboard.string(forType: .string), ToolDrop.accepts(s) else { return [] }
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let s = sender.draggingPasteboard.string(forType: .string), ToolDrop.accepts(s) else { return [] }
        let v = convert(sender.draggingLocation, from: nil)
        model?.cursorWorld = toWorld(v)
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model, let s = sender.draggingPasteboard.string(forType: .string) else { return false }
        let v = convert(sender.draggingLocation, from: nil)
        let hit = pick(at: toWorld(v))
        let ok = ToolDrop.drop(s, at: toWorld(v), onto: hit, model: model)
        if ok { window?.makeKeyAndOrderFront(nil); focus() }
        return ok
    }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func focus() { if window?.firstResponder !== self { window?.makeFirstResponder(self) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in self?.focus() } }
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        overlay.frame = bounds
        if (needsInitialZoom || handledZoomRequest != (model?.zoomExtentsRequest ?? 0)), bounds.width > 10, bounds.height > 10 {
            needsInitialZoom = false
            handledZoomRequest = model?.zoomExtentsRequest ?? 0
            DispatchQueue.main.async { [weak self] in self?.zoomExtents() }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        content.needsDisplay = true
        overlay.needsDisplay = true
        // Split divider / window resize: a view the user never zoomed stays fitted to the drawing.
        if let model, !model.planUserZoomed, !needsInitialZoom, newSize.width > 10, newSize.height > 10,
           abs(old.width - newSize.width) > 1 || abs(old.height - newSize.height) > 1, !refitScheduled {
            refitScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refitScheduled = false
                if self.model?.planUserZoomed == false { self.zoomExtents(recordHistory: false) }
            }
        }
    }
    private var refitScheduled = false

    /// Called from SwiftUI updates.
    func syncFromModel() {
        guard let model else { return }
        if handledZoomRequest != model.zoomExtentsRequest {
            handledZoomRequest = model.zoomExtentsRequest
            DispatchQueue.main.async { [weak self] in self?.zoomExtents() }
        }
        content.needsDisplay = true
        overlay.needsDisplay = true
    }

    private func modelChanged() {
        guard let model else { return }
        let tw = CGFloat(rad(ViewTwist.degrees(model.doc)))
        if abs(tw - twist) > 1e-12 { twist = tw; viewChanged() }
        if handledZoomRequest != model.zoomExtentsRequest { zoomExtents() }
        if let mv = mouseView { updateCursorPoint(mv) }
        content.needsDisplay = true
        overlay.needsDisplay = true
    }

    // MARK: Transform

    var worldTransform: CGAffineTransform {
        CGAffineTransform(translationX: bounds.midX, y: bounds.midY).rotated(by: twist).scaledBy(x: scale, y: scale).translatedBy(x: -center.x, y: -center.y)
    }
    /// Screen offset (points) of a world offset, and back, including the view twist.
    private func screenOffset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        twist == 0 ? CGPoint(x: dx, y: dy) : CGPoint(x: dx * cos(twist) - dy * sin(twist), y: dx * sin(twist) + dy * cos(twist))
    }
    private func worldOffset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        twist == 0 ? CGPoint(x: dx, y: dy) : CGPoint(x: dx * cos(twist) + dy * sin(twist), y: -dx * sin(twist) + dy * cos(twist))
    }
    func toView(_ w: Vec2) -> CGPoint {
        let o = screenOffset((CGFloat(w.x) - center.x) * scale, (CGFloat(w.y) - center.y) * scale)
        return CGPoint(x: o.x + bounds.midX, y: o.y + bounds.midY)
    }
    func toWorld(_ v: CGPoint) -> Vec2 {
        let o = worldOffset(v.x - bounds.midX, v.y - bounds.midY)
        return Vec2(Double(o.x / scale + center.x), Double(o.y / scale + center.y))
    }
    /// Sets the plan display rotation (radians), keeping the view centre.
    func setTwist(_ a: CGFloat) {
        guard abs(a - twist) > 1e-12 else { return }
        twist = a
        viewChanged()
    }
    private func visibleWorld(_ r: CGRect) -> CGRect { r.applying(worldTransform.inverted()) }

    private func viewChanged() {
        scale = min(max(scale, 1e-7), 1e5)
        if let model {
            model.planViewCenter = center
            model.planViewScale = scale
            model.editor.pickTolerance = Double(6 / scale)
            let unitMM = model.doc.units.mm
            let screenMMPerUnit = Double(scale) * 25.4 / 72
            model.live.zoomPercent = 100 * screenMMPerUnit / unitMM
        }
        if let mv = mouseView { updateCursorPoint(mv) }
        content.needsDisplay = true
        overlay.needsDisplay = true
    }

    func zoomExtents(recordHistory: Bool = true) {
        handledZoomRequest = model?.zoomExtentsRequest ?? 0
        guard bounds.width > 10, bounds.height > 10 else { needsInitialZoom = true; return }
        needsInitialZoom = false
        let s = ensureScene()
        var b = s.bounds
        if b.isNull || (b.width <= 0 && b.height <= 0) || !b.width.isFinite {
            let u = model?.doc.units.mm ?? 1
            let w = 30000 / u, h = 18000 / u
            b = CGRect(x: -2000 / u, y: -2000 / u, width: w, height: h)
        }
        zoom(toRect: b, margin: 0.06, recordHistory: recordHistory)
        model?.planUserZoomed = false
    }

    private var zoomHistory: [(CGPoint, CGFloat)] = []
    func zoomPrevious() {
        guard let (c, sc) = zoomHistory.popLast() else { model?.editor.print("No previous view."); return }
        center = c; scale = sc; model?.planUserZoomed = true; viewChanged()
    }
    func zoom(toRect b: CGRect, margin: CGFloat = 0.02, recordHistory: Bool = true) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        if recordHistory { zoomHistory.append((center, scale)); if zoomHistory.count > 50 { zoomHistory.removeFirst() } }
        model?.planUserZoomed = true
        // A twisted view fits the rotated rectangle's screen bounds.
        let c = abs(cos(twist)), sn = abs(sin(twist))
        let w = max(b.width * c + b.height * sn, 1e-6), h = max(b.width * sn + b.height * c, 1e-6)
        scale = min(bounds.width * (1 - 2 * margin) / w, bounds.height * (1 - 2 * margin) / h)
        center = CGPoint(x: b.midX, y: b.midY)
        viewChanged()
    }
    func zoom(to box: BBox2) {
        guard !box.isEmpty else { return }
        zoom(toRect: CGRect(x: box.min.x, y: box.min.y, width: box.width, height: box.height))
    }
    func zoomBy(_ f: CGFloat, about v: CGPoint? = nil) {
        let p = v ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let w = toWorld(p)
        let newScale = min(max(scale * f, 1e-7), 1e5)
        scale = newScale
        model?.planUserZoomed = true
        let o = worldOffset(p.x - bounds.midX, p.y - bounds.midY)
        center = CGPoint(x: CGFloat(w.x) - o.x / scale, y: CGFloat(w.y) - o.y / scale)
        viewChanged()
    }
    /// World rectangle currently visible (navigator).
    var visibleWorldBox: BBox2 { BBox2(points: [toWorld(CGPoint(x: bounds.minX, y: bounds.minY)), toWorld(CGPoint(x: bounds.maxX, y: bounds.maxY)),
                                                toWorld(CGPoint(x: bounds.minX, y: bounds.maxY)), toWorld(CGPoint(x: bounds.maxX, y: bounds.minY))]) }
    /// Pans so that `w` is at the centre of the view, keeping the zoom (navigator).
    func centre(on w: Vec2) {
        center = CGPoint(x: w.x, y: w.y)
        model?.planUserZoomed = true
        viewChanged()
    }
    func panView(dx: CGFloat, dy: CGFloat) {
        let o = worldOffset(dx, dy)
        center.x -= o.x / scale
        center.y -= o.y / scale
        model?.planUserZoomed = true
        viewChanged()
    }
    func panWorld(_ d: Vec2) {
        center.x -= CGFloat(d.x)
        center.y -= CGFloat(d.y)
        viewChanged()
    }

    // MARK: Scene cache

    @discardableResult
    func ensureScene() -> RenderScene {
        guard let model else { return RenderScene([]) }
        let ed = model.editor
        let key = [ed.changeCount, ed.doc.currentLevel]
        if let s = scene, key == sceneKey { return s }
        let entries = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))
        let s = RenderScene(entries)
        scene = s
        sceneKey = key
        return s
    }
    func invalidateCache() { sceneKey = []; content.needsDisplay = true; overlay.needsDisplay = true }
    /// REDRAW: repaints from the display cache without rebuilding it (REGEN rebuilds).
    func redraw() { content.needsDisplay = true; overlay.needsDisplay = true }
    /// Whether the display cache is current (tests of REDRAW vs REGEN).
    var isSceneCached: Bool { scene != nil && !sceneKey.isEmpty }

    var params: RenderParams {
        var p = RenderParams()
        p.lineweights = model?.editor.settings.lineweightDisplay ?? true
        p.lwScale *= CGFloat(LineweightDisplay.scale)
        p.minWidth = 1 / (window?.backingScaleFactor ?? 2)
        return p
    }

    // MARK: Drawing (content layer)

    /// Draws the content layer into a context (self-tests measure frame times with it).
    func drawContentForTesting(_ ctx: CGContext) { drawContent(ctx, bounds) }

    private func drawContent(_ ctx: CGContext, _ dirty: NSRect) {
        ctx.setFillColor(Theme.nsCanvas.cgColor)
        ctx.fill(dirty)
        guard let model else { return }
        let s = ensureScene()
        if model.editor.settings.showGrid { drawGrid(ctx, dirty) } else { drawAxes(ctx) }
        ctx.saveGState()
        ctx.concatenate(worldTransform)
        s.draw(in: ctx, visible: visibleWorld(dirty), scale: scale, params: params)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.concatenate(worldTransform)
        let sel = model.editor.selection
        if !sel.isEmpty {
            let idx = sel.flatMap { s.index[$0] ?? [] }
            if idx.count < 800 { ctx.setShadow(offset: .zero, blur: 5, color: Theme.nsAccent.withAlphaComponent(0.7).cgColor) }
            s.drawHighlight(idx, ctx: ctx, scale: scale, params: params, color: Theme.nsAccent.cgColor, extraWidth: 1.0, dashed: true, fillAlpha: 0.10)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        ctx.restoreGState()
        computeGrips()
        drawGrips(ctx)
        drawUCSIcon(ctx)
    }

    private func drawAxes(_ ctx: CGContext) {
        let o = toView(.zero)
        ctx.setLineWidth(1)
        if twist != 0 {
            // Axes through the origin along the twisted directions, clipped by the view.
            let far = max(bounds.width, bounds.height) * 2
            let ux = screenOffset(1, 0), uy = screenOffset(0, 1)
            ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.3, blue: 0.3, alpha: 0.28))
            ctx.strokeLineSegments(between: [CGPoint(x: o.x - ux.x * far, y: o.y - ux.y * far), CGPoint(x: o.x + ux.x * far, y: o.y + ux.y * far)])
            ctx.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.8, blue: 0.4, alpha: 0.28))
            ctx.strokeLineSegments(between: [CGPoint(x: o.x - uy.x * far, y: o.y - uy.y * far), CGPoint(x: o.x + uy.x * far, y: o.y + uy.y * far)])
            return
        }
        if o.y >= 0 && o.y <= bounds.height {
            ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.3, blue: 0.3, alpha: 0.28))
            ctx.strokeLineSegments(between: [CGPoint(x: 0, y: o.y), CGPoint(x: bounds.width, y: o.y)])
        }
        if o.x >= 0 && o.x <= bounds.width {
            ctx.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.8, blue: 0.4, alpha: 0.28))
            ctx.strokeLineSegments(between: [CGPoint(x: o.x, y: 0), CGPoint(x: o.x, y: bounds.height)])
        }
    }

    private func drawGrid(_ ctx: CGContext, _ dirty: NSRect) {
        guard let model else { return }
        let base = max(model.editor.settings.gridSpacing, 1e-9)
        var minor = CGFloat(base)
        while minor * scale > 120 { minor /= 10 }
        let steps: [CGFloat] = [2, 2.5, 2]
        var k = 0
        while minor * scale < 10 { minor *= steps[k % 3]; k += 1 }
        let major = minor * 5
        let vis = visibleWorld(bounds)
        let x0 = Int((vis.minX / minor).rounded(.down)), x1 = Int((vis.maxX / minor).rounded(.up))
        let y0 = Int((vis.minY / minor).rounded(.down)), y1 = Int((vis.maxY / minor).rounded(.up))
        guard x1 - x0 < 2000, y1 - y0 < 2000 else { return }
        var minorSeg: [CGPoint] = [], majorSeg: [CGPoint] = []
        if twist != 0 {
            // Twisted view: grid lines are world lines, drawn through the view transform.
            for i in x0...x1 {
                let wx = CGFloat(i) * minor
                let isMajor = abs((wx / major) - (wx / major).rounded()) < 1e-6
                let seg = [toView(Vec2(Double(wx), Double(vis.minY))), toView(Vec2(Double(wx), Double(vis.maxY)))]
                if isMajor { majorSeg += seg } else { minorSeg += seg }
            }
            for j in y0...y1 {
                let wy = CGFloat(j) * minor
                let isMajor = abs((wy / major) - (wy / major).rounded()) < 1e-6
                let seg = [toView(Vec2(Double(vis.minX), Double(wy))), toView(Vec2(Double(vis.maxX), Double(wy)))]
                if isMajor { majorSeg += seg } else { minorSeg += seg }
            }
            ctx.setLineWidth(1)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.035)); ctx.strokeLineSegments(between: minorSeg)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.075)); ctx.strokeLineSegments(between: majorSeg)
            drawAxes(ctx)
            return
        }
        for i in x0...x1 {
            let wx = CGFloat(i) * minor
            let x = ((wx - center.x) * scale + bounds.midX).rounded() + 0.5
            let isMajor = abs((wx / major) - (wx / major).rounded()) < 1e-6
            if isMajor { majorSeg += [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height)] } else { minorSeg += [CGPoint(x: x, y: 0), CGPoint(x: x, y: bounds.height)] }
        }
        for j in y0...y1 {
            let wy = CGFloat(j) * minor
            let y = ((wy - center.y) * scale + bounds.midY).rounded() + 0.5
            let isMajor = abs((wy / major) - (wy / major).rounded()) < 1e-6
            if isMajor { majorSeg += [CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)] } else { minorSeg += [CGPoint(x: 0, y: y), CGPoint(x: bounds.width, y: y)] }
        }
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.035))
        ctx.strokeLineSegments(between: minorSeg)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.075))
        ctx.strokeLineSegments(between: majorSeg)
        drawAxes(ctx)
    }

    /// UCS icon (UCSICON ORigin): drawn at the UCS origin when it is on screen, else in the lower-left corner,
    /// with its axes rotated to the current UCS. A square at the origin marks the world coordinate system.
    private func drawUCSIcon(_ ctx: CGContext) {
        let ucs = model.map { UCSFrame.current($0.doc) } ?? .world
        let len: CGFloat = 34
        let corner = CGPoint(x: 26, y: 26)
        var o = corner
        let atOrigin = toView(ucs.origin)
        if !ucs.isWorld, bounds.insetBy(dx: 40, dy: 40).contains(atOrigin) { o = atOrigin }
        let a = CGFloat(ucs.angle) + twist
        let ux = CGPoint(x: cos(a), y: sin(a)), uy = CGPoint(x: -sin(a), y: cos(a))
        func pt(_ d: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: o.x + d.x * k, y: o.y + d.y * k) }
        func arrow(_ d: CGPoint, _ color: CGColor) {
            ctx.setStrokeColor(color)
            ctx.strokeLineSegments(between: [o, pt(d, len)])
            let tip = pt(d, len), back = pt(d, len - 6), n = CGPoint(x: -d.y, y: d.x)
            ctx.move(to: tip); ctx.addLine(to: CGPoint(x: back.x + n.x * 3, y: back.y + n.y * 3)); ctx.addLine(to: CGPoint(x: back.x - n.x * 3, y: back.y - n.y * 3)); ctx.closePath()
            ctx.setFillColor(color); ctx.fillPath()
        }
        ctx.setLineWidth(1.5)
        arrow(ux, CGColor(srgbRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.9))
        arrow(uy, CGColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.9))
        ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 0.9)); ctx.setLineWidth(1)
        if ucs.isWorld { ctx.stroke(CGRect(x: o.x - 3, y: o.y - 3, width: 6, height: 6)) }
        else { ctx.addEllipse(in: CGRect(x: o.x - 2.5, y: o.y - 2.5, width: 5, height: 5)); ctx.strokePath() }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor(white: 0.85, alpha: 0.9)]
        let xl = pt(ux, len + 8), yl = pt(uy, len + 8)
        ("X" as NSString).draw(at: CGPoint(x: xl.x - 3, y: xl.y - 6), withAttributes: attrs)
        ("Y" as NSString).draw(at: CGPoint(x: yl.x - 3, y: yl.y - 6), withAttributes: attrs)
        if ucs.isWorld { ("W" as NSString).draw(at: CGPoint(x: o.x + 6, y: o.y + 4), withAttributes: attrs) }
    }

    /// Flip arrows of selected doors and windows (SEL-036).
    private var currentFlips: [FlipControls.Control] = []

    private func computeGrips() {
        currentGrips = []
        currentFlips = []
        if let model, model.editor.isIdle, model.editor.selection.count <= 20 {
            for el in model.doc.elements where model.editor.selection.contains(el.id) && model.editor.isSelectable(el.id) {
                currentFlips += FlipControls.controls(el, doc: model.doc, gap: Double(16 / scale))
                if let w = FlipControls.wallControl(el, gap: Double(16 / scale)) { currentFlips.append(w) }
            }
        }
        guard let model, model.editor.isIdle else { return }
        let sel = model.editor.selection
        // GRIPS = 0 hides grips (SEL-032).
        guard !sel.isEmpty, sel.count <= 300, (model.doc.variable("GRIPS").flatMap(Int.init) ?? 1) != 0 else { return }
        let doc = model.doc
        for e in doc.entities where sel.contains(e.id) {
            for (i, p) in GripEditor.grips(e).enumerated() { currentGrips.append((e.id, i, p)) }
        }
        for el in doc.elements where sel.contains(el.id) {
            for (i, p) in GripEditor.grips(el, doc: doc).enumerated() { currentGrips.append((el.id, i, p)) }
        }
    }

    private func drawGrips(_ ctx: CGContext) {
        // Flip arrows: a double arrow across the swing side (facing) and along the wall (hand).
        for f in currentFlips {
            let v = toView(f.point)
            let d0 = screenOffset(CGFloat(f.direction.x), CGFloat(f.direction.y))
            let len = max(hypot(d0.x, d0.y), 1e-9)
            let d = CGPoint(x: d0.x / len, y: d0.y / len), n = CGPoint(x: -d.y, y: d.x)
            ctx.setFillColor(Theme.nsAccent.cgColor)
            for sgn: CGFloat in [1, -1] {
                let tip = CGPoint(x: v.x + d.x * 7 * sgn, y: v.y + d.y * 7 * sgn), base = CGPoint(x: v.x + d.x * 1.5 * sgn, y: v.y + d.y * 1.5 * sgn)
                ctx.move(to: tip); ctx.addLine(to: CGPoint(x: base.x + n.x * 4.5, y: base.y + n.y * 4.5)); ctx.addLine(to: CGPoint(x: base.x - n.x * 4.5, y: base.y - n.y * 4.5)); ctx.closePath()
                ctx.fillPath()
            }
        }
        guard !currentGrips.isEmpty else { return }
        let sz: CGFloat = 7
        ctx.setLineWidth(1)
        for g in currentGrips {
            let v = toView(g.point)
            guard bounds.insetBy(dx: -10, dy: -10).contains(v) else { continue }
            let r = CGRect(x: (v.x - sz / 2).rounded() + 0.5, y: (v.y - sz / 2).rounded() + 0.5, width: sz, height: sz)
            ctx.setFillColor(CGColor(srgbRed: 0.24, green: 0.48, blue: 1.0, alpha: 1))
            ctx.fill(r)
            ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.94, blue: 1, alpha: 0.9))
            ctx.stroke(r)
        }
    }

    /// Flip arrow under a view point (8 px).
    func flipHit(_ v: CGPoint) -> FlipControls.Control? {
        currentFlips.first { let p = toView($0.point); return hypot(p.x - v.x, p.y - v.y) <= 8 }
    }
    /// Recomputes grips and flip arrows for the current selection (self-tests; drawing does it every frame).
    func refreshGrips() { computeGrips() }

    private func gripHit(_ v: CGPoint) -> (id: EntityID, index: Int, point: Vec2)? {
        var best: ((id: EntityID, index: Int, point: Vec2), CGFloat)?
        for g in currentGrips {
            let p = toView(g.point)
            let d = max(abs(p.x - v.x), abs(p.y - v.y))
            if d <= 6, d < (best?.1 ?? .infinity) { best = (g, d) }
        }
        return best?.0
    }

    // MARK: Drawing (overlay layer)

    private func fallbackItems(_ geoms: [Geometry], doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        var items: [DrawItem] = []
        for g in geoms {
            if case .text(let t) = g { items.append(.text(t, font: "Helvetica", color: color)); continue }
            for pl in GeometryOps.tessellate(g, doc: doc) where !pl.isEmpty {
                items.append(.stroke(points: pl, closed: false, style: ArchiCore.StrokeStyle(color: color, lineweight: 0.25)))
            }
        }
        return items
    }

    private func elementPreview(_ el: BIMElement, doc: ArchiDocument, color: RGBA) -> [DrawItem] {
        let items = PlanRepresentation.items(el, doc: doc)
        if !items.isEmpty { return items }
        let st = ArchiCore.StrokeStyle(color: color, lineweight: 0.25)
        switch el.geometry {
        case .wall(let w):
            let n = w.direction.perp * (w.thickness / 2)
            let a = w.centerStart, b = w.centerEnd
            return [.stroke(points: [a + n, b + n, b - n, a - n], closed: true, style: st)]
        case .slab(let s): return [.stroke(points: s.boundary, closed: true, style: st)]
        case .roof(let r): return [.stroke(points: r.boundary, closed: true, style: st)]
        case .space(let s): return [.stroke(points: s.boundary, closed: true, style: st)]
        case .railing(let r): return [.stroke(points: r.path, closed: false, style: st)]
        case .beam(let b): return [.stroke(points: [b.start, b.end], closed: false, style: st)]
        case .curtainWall(let c): return [.stroke(points: [c.start, c.end], closed: false, style: st)]
        case .gridLine(let g): return [.stroke(points: [g.start, g.end], closed: false, style: st)]
        case .column(let c):
            let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
            let hw = c.width / 2, hd = c.depth / 2
            return [.stroke(points: [Vec2(-hw, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd)].map(t.apply), closed: true, style: st)]
        case .component(let c):
            let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
            let hw = c.size.x / 2, hd = c.size.y / 2
            return [.stroke(points: [Vec2(-hw, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd)].map(t.apply), closed: true, style: st)]
        default: return []
        }
    }

    private func drawOverlay(_ ctx: CGContext, _ dirty: NSRect) {
        guard let model else { return }
        let ed = model.editor
        let s = scene
        let prm = params
        let previewColor = RGBA(0.86, 0.88, 0.92)
        ctx.saveGState()
        ctx.concatenate(worldTransform)
        // Hover highlight.
        if let h = hoverID, !ed.selection.contains(h), let s, let idx = s.index[h] {
            s.drawHighlight(idx, ctx: ctx, scale: scale, params: prm, color: CGColor(gray: 1, alpha: 0.85), extraWidth: 1.6, dashed: false, fillAlpha: 0.06)
        }
        // Drawing compare overlay (Collaborate ▸ Compare).
        CompareOverlay.byModel[ObjectIdentifier(model)]?.draw(ctx, scale: scale)
        // Command rubber-band preview.
        if let req = ed.request, req.kinds.contains(.point) || req.kinds.contains(.distance) || req.kinds.contains(.angle), let pv = req.preview, mouseView != nil {
            let geoms = pv(cursorPoint)
            if !geoms.isEmpty {
                var items = DrawListBuilder.previewItems(geoms, doc: ed.doc, color: previewColor)
                if items.isEmpty { items = fallbackItems(geoms, doc: ed.doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm)
            }
        }
        // Grip drag preview (a constraint drag edits the drawing itself, live).
        if let g = hotGrip, !g.solve, g.mode != .stretch {
            // Grip modes preview the whole selection about the hot grip (SEL-034).
            let doc = ed.doc
            if let t = Grips.modeTransform(g.mode, base: g.origin, to: cursorPoint, reference: g.reference) {
                let ids = ed.selection.union([g.id])
                var geos: [Geometry] = []
                for e in doc.entities where ids.contains(e.id) { geos.append(GeometryOps.transform(e.geometry, t)) }
                var items = DrawListBuilder.previewItems(geos, doc: doc, color: previewColor)
                if items.isEmpty { items = fallbackItems(geos, doc: doc, color: previewColor) }
                for var el in doc.elements where ids.contains(el.id) { el.geometry = CommandHelpers.transform(el.geometry, t); items += elementPreview(el, doc: doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            }
        } else if let g = hotGrip, !g.solve {
            let doc = ed.doc
            if let e = doc.entity(g.id) {
                let geo = g.action.flatMap { a in GripEditor.grip(e.geometry, g.index).flatMap { Grips.apply(a, e.geometry, grip: $0, to: cursorPoint) } }
                    ?? GripEditor.moved(e.geometry, grip: g.index, from: g.origin, to: cursorPoint, turns: g.turns)
                var items = DrawListBuilder.previewItems([geo], doc: doc, color: previewColor)
                if items.isEmpty { items = fallbackItems([geo], doc: doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            } else if var el = doc.element(g.id) {
                el.geometry = GripEditor.moved(el, grip: g.index, from: g.origin, to: cursorPoint, doc: doc, turns: g.turns)
                RenderScene.drawItems(elementPreview(el, doc: doc, color: previewColor), ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            }
        }
        // Click-to-place preview from the tool palette, rotated by Space (MOD-029).
        if let pl = model.placement, let pv = Placement.preview(pl.item, at: cursorPoint, turns: pl.turns, doc: ed.doc) {
            switch pv {
            case .geometry(let geo):
                var items = DrawListBuilder.previewItems([geo], doc: ed.doc, color: previewColor)
                if items.isEmpty { items = fallbackItems([geo], doc: ed.doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            case .element(let el):
                RenderScene.drawItems(elementPreview(el, doc: ed.doc, color: previewColor), ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            }
        }
        ctx.restoreGState()

        // Rubber band from the base point.
        if let mv = mouseView, windowSel == nil {
            var base: Vec2?
            if let g = hotGrip { base = g.origin } else if let req = ed.request, req.kinds.contains(.point) || req.kinds.contains(.distance) || req.kinds.contains(.angle) { base = req.base }
            if let b = base {
                let bv = toView(b), cv = toView(cursorPoint)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45)); ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [5, 4])
                ctx.strokeLineSegments(between: [bv, cv])
                ctx.setLineDash(phase: 0, lengths: [])
                _ = mv
            }
        }
        // Lasso (SEL-007): counter-clockwise = crossing (green, dashed), clockwise = window (blue).
        if let w = windowSel, let pts = w.lasso, pts.count >= 2 {
            let world = pts.map(toWorld)
            let crossing = world.count >= 3 ? SelectionGeometry.lassoMode(world) == .crossingPolygon : false
            let c: NSColor = crossing ? NSColor(srgbRed: 0.25, green: 0.8, blue: 0.4, alpha: 1) : NSColor(srgbRed: 0.3, green: 0.5, blue: 1, alpha: 1)
            let path = CGMutablePath(); path.addLines(between: pts); path.closeSubpath()
            ctx.addPath(path); ctx.setFillColor(c.withAlphaComponent(0.13).cgColor); ctx.fillPath()
            ctx.addPath(path); ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(1)
            if crossing { ctx.setLineDash(phase: 0, lengths: [5, 3]) }
            ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
        } else if let w = windowSel {
            let r = CGRect(x: min(w.start.x, w.current.x), y: min(w.start.y, w.current.y), width: abs(w.current.x - w.start.x), height: abs(w.current.y - w.start.y))
            let crossing = w.current.x < w.start.x
            let c: NSColor = w.purpose == .zoom ? NSColor(white: 0.8, alpha: 1) : (crossing ? NSColor(srgbRed: 0.25, green: 0.8, blue: 0.4, alpha: 1) : NSColor(srgbRed: 0.3, green: 0.5, blue: 1, alpha: 1))
            ctx.setFillColor(c.withAlphaComponent(0.13).cgColor); ctx.fill(r)
            ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(1)
            if crossing && w.purpose != .zoom { ctx.setLineDash(phase: 0, lengths: [5, 3]) }
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // Hovered / hot grip.
        if let hg = hoverGrip, hotGrip == nil { drawGripMark(ctx, toView(hg.point), color: CGColor(srgbRed: 1, green: 0.45, blue: 0.55, alpha: 1)) }
        if let g = hotGrip { drawGripMark(ctx, toView(g.origin), color: CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1)) }
        // Object snap tracking: acquired points and alignment vectors (OTRACK).
        if mouseView != nil, !ed.isIdle { drawTracking(ctx) }
        // Snap marker.
        if let sn = snap, mouseView != nil { drawSnapMarker(ctx, sn) }
        // Crosshair.
        if let mv = mouseView, panLast == nil {
            drawCrosshair(ctx, mv, pickbox: ed.isIdle && hotGrip == nil || (ed.request.map { !$0.kinds.isDisjoint(with: [.selection, .entity]) && !$0.kinds.contains(.point) } ?? false))
            if ed.settings.dynamicInput { drawDynamicInput(ctx, mv) }
        }
    }

    private func drawGripMark(_ ctx: CGContext, _ v: CGPoint, color: CGColor) {
        let sz: CGFloat = 8
        let r = CGRect(x: (v.x - sz / 2).rounded() + 0.5, y: (v.y - sz / 2).rounded() + 0.5, width: sz, height: sz)
        ctx.setFillColor(color); ctx.fill(r)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9)); ctx.setLineWidth(1); ctx.stroke(r)
    }

    private func drawCrosshair(_ ctx: CGContext, _ v: CGPoint, pickbox: Bool) {
        let pct = CGFloat(min(max(AppPreferences.shared.cursorSize, 1), 100))
        let arm = pct >= 100 ? max(bounds.width, bounds.height) * 2 : max(8, pct / 200 * max(bounds.width, bounds.height))
        let x = v.x.rounded() + 0.5, y = v.y.rounded() + 0.5
        let gap: CGFloat = pickbox ? 5 : 0
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CGColor(gray: 0.95, alpha: 0.95))
        ctx.strokeLineSegments(between: [CGPoint(x: x - arm, y: y), CGPoint(x: x - gap, y: y), CGPoint(x: x + gap, y: y), CGPoint(x: x + arm, y: y),
                                         CGPoint(x: x, y: y - arm), CGPoint(x: x, y: y - gap), CGPoint(x: x, y: y + gap), CGPoint(x: x, y: y + arm)])
        if pickbox { ctx.stroke(CGRect(x: x - 5, y: y - 5, width: 10, height: 10)) }
    }

    /// Draws the acquired tracking points as small crosses and the active tracking vectors as dotted rays through them.
    private func drawTracking(_ ctx: CGContext) {
        let tr = Snap.tracker
        guard tr.active, !(tr.points.isEmpty && tr.lines.isEmpty) else { return }
        ctx.saveGState()
        let col = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.95)
        ctx.setStrokeColor(col); ctx.setLineWidth(1)
        for p in tr.points {
            let v = toView(p), s: CGFloat = 4
            ctx.strokeLineSegments(between: [CGPoint(x: v.x - s, y: v.y), CGPoint(x: v.x + s, y: v.y), CGPoint(x: v.x, y: v.y - s), CGPoint(x: v.x, y: v.y + s)])
        }
        let reach = hypot(bounds.width, bounds.height)
        ctx.setLineDash(phase: 0, lengths: [2, 4])
        for l in tr.lines {
            let a = toView(l.from), b = toView(l.to)
            let dx = b.x - a.x, dy = b.y - a.y, len = hypot(dx, dy)
            guard len > 0.5 else { continue }
            let ux = dx / len, uy = dy / len
            ctx.strokeLineSegments(between: [a, CGPoint(x: b.x + ux * reach, y: b.y + uy * reach)])
        }
        ctx.restoreGState()
        // Tracking readout: distance and angle from the acquired point along the active tracking vector.
        if let l = tr.lines.last, let sn = snap, sn.kind == .extension || sn.kind == .parallel {
            let d = sn.point - l.from
            guard d.length > 1e-9 else { return }
            var ang = atan2(d.y, d.x) * 180 / .pi
            if ang < 0 { ang += 360 }
            let v = toView(sn.point)
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)); ctx.setLineWidth(1.5)
            ctx.strokeLineSegments(between: [CGPoint(x: v.x - 5, y: v.y - 5), CGPoint(x: v.x + 5, y: v.y + 5), CGPoint(x: v.x - 5, y: v.y + 5), CGPoint(x: v.x + 5, y: v.y - 5)])
            ctx.restoreGState()
            let label = tr.lines.count > 1 ? "Intersection of tracking paths" : "Tracking: \(fmt(d.length, 2)) < \(fmt(ang, 1))°"
            drawTooltip(ctx, [label], at: CGPoint(x: v.x + 12, y: v.y - 32), accent: false)
        }
    }

    private func drawSnapMarker(_ ctx: CGContext, _ sn: SnapResult) {
        let c = toView(sn.point)
        let s: CGFloat = 6
        ctx.saveGState()
        ctx.setStrokeColor(Theme.nsAccent.cgColor)
        ctx.setLineWidth(2)
        let path = CGMutablePath()
        switch sn.kind {
        case .endpoint: path.addRect(CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s))
        case .midpoint: path.addLines(between: [CGPoint(x: c.x - s, y: c.y - s * 0.8), CGPoint(x: c.x + s, y: c.y - s * 0.8), CGPoint(x: c.x, y: c.y + s * 1.1)]); path.closeSubpath()
        case .center: path.addEllipse(in: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s))
        case .node:
            path.addEllipse(in: CGRect(x: c.x - s, y: c.y - s, width: 2 * s, height: 2 * s))
            path.move(to: CGPoint(x: c.x - s * 0.7, y: c.y - s * 0.7)); path.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y + s * 0.7))
            path.move(to: CGPoint(x: c.x - s * 0.7, y: c.y + s * 0.7)); path.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - s * 0.7))
        case .quadrant: path.addLines(between: [CGPoint(x: c.x, y: c.y - s), CGPoint(x: c.x + s, y: c.y), CGPoint(x: c.x, y: c.y + s), CGPoint(x: c.x - s, y: c.y)]); path.closeSubpath()
        case .intersection:
            path.move(to: CGPoint(x: c.x - s, y: c.y - s)); path.addLine(to: CGPoint(x: c.x + s, y: c.y + s))
            path.move(to: CGPoint(x: c.x - s, y: c.y + s)); path.addLine(to: CGPoint(x: c.x + s, y: c.y - s))
        case .extension:
            for dx in [-s, 0, s] { path.addEllipse(in: CGRect(x: c.x + dx - 1.2, y: c.y - 1.2, width: 2.4, height: 2.4)) }
        case .insertion:
            path.addRect(CGRect(x: c.x - s, y: c.y - s * 0.2, width: s * 1.2, height: s * 1.2))
            path.addRect(CGRect(x: c.x - s * 0.2, y: c.y - s, width: s * 1.2, height: s * 1.2))
        case .perpendicular:
            path.move(to: CGPoint(x: c.x - s, y: c.y + s)); path.addLine(to: CGPoint(x: c.x - s, y: c.y - s)); path.addLine(to: CGPoint(x: c.x + s, y: c.y - s))
            path.move(to: CGPoint(x: c.x - s, y: c.y)); path.addLine(to: CGPoint(x: c.x, y: c.y)); path.addLine(to: CGPoint(x: c.x, y: c.y - s))
        case .tangent:
            path.addEllipse(in: CGRect(x: c.x - s * 0.8, y: c.y - s * 0.8, width: 1.6 * s, height: 1.6 * s))
            path.move(to: CGPoint(x: c.x - s, y: c.y + s * 0.8)); path.addLine(to: CGPoint(x: c.x + s, y: c.y + s * 0.8))
        case .nearest:
            path.addLines(between: [CGPoint(x: c.x - s, y: c.y + s), CGPoint(x: c.x + s, y: c.y + s), CGPoint(x: c.x - s, y: c.y - s), CGPoint(x: c.x + s, y: c.y - s)]); path.closeSubpath()
        case .parallel:
            path.move(to: CGPoint(x: c.x - s, y: c.y - s * 0.3)); path.addLine(to: CGPoint(x: c.x - s * 0.1, y: c.y + s))
            path.move(to: CGPoint(x: c.x + s * 0.1, y: c.y - s)); path.addLine(to: CGPoint(x: c.x + s, y: c.y + s * 0.3))
        case .grid:
            path.move(to: CGPoint(x: c.x - s, y: c.y)); path.addLine(to: CGPoint(x: c.x + s, y: c.y))
            path.move(to: CGPoint(x: c.x, y: c.y - s)); path.addLine(to: CGPoint(x: c.x, y: c.y + s))
        }
        ctx.addPath(path); ctx.strokePath()
        ctx.restoreGState()
        drawTooltip(ctx, [snapLabel(sn.kind)], at: CGPoint(x: c.x + 10, y: c.y - 12), accent: true)
    }

    private func snapLabel(_ k: SnapKind) -> String {
        switch k {
        case .endpoint: return "Endpoint"
        case .midpoint: return "Midpoint"
        case .center: return "Center"
        case .node: return "Node"
        case .quadrant: return "Quadrant"
        case .intersection: return "Intersection"
        case .extension: return "Extension"
        case .insertion: return "Insertion"
        case .perpendicular: return "Perpendicular"
        case .tangent: return "Tangent"
        case .nearest: return "Nearest"
        case .parallel: return "Parallel"
        case .grid: return "Grid"
        }
    }

    /// Draws a small dark tooltip box; `at` is its top-left corner.
    private func drawTooltip(_ ctx: CGContext, _ lines: [String], at p: CGPoint, accent: Bool = false) {
        guard !lines.isEmpty else { return }
        let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accent ? Theme.nsAccent : Theme.nsText]
        let sizes = lines.map { ($0 as NSString).size(withAttributes: attrs) }
        let w = (sizes.map(\.width).max() ?? 0) + 12
        let lh: CGFloat = 14
        let h = CGFloat(lines.count) * lh + 6
        var o = CGPoint(x: p.x, y: p.y - h)
        if o.x + w > bounds.width - 4 { o.x = bounds.width - w - 4 }
        if o.y < 4 { o.y = p.y + 24 }
        let r = CGRect(x: o.x, y: o.y, width: w, height: h)
        let path = CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.addPath(path); ctx.setFillColor(NSColor(hex: 0x2B2C31, alpha: 0.96).cgColor); ctx.fillPath()
        ctx.addPath(path); ctx.setStrokeColor(accent ? Theme.nsAccent.withAlphaComponent(0.6).cgColor : NSColor(white: 1, alpha: 0.14).cgColor); ctx.setLineWidth(1); ctx.strokePath()
        for (i, l) in lines.enumerated() {
            (l as NSString).draw(at: CGPoint(x: r.minX + 6, y: r.maxY - 3 - CGFloat(i + 1) * lh + 1), withAttributes: attrs)
        }
    }

    private func drawDynamicInput(_ ctx: CGContext, _ v: CGPoint) {
        guard let model else { return }
        let ed = model.editor
        var lines: [String] = []
        if let req = ed.request {
            lines.append(req.message + (req.keywords.isEmpty ? "" : "  [" + req.keywords.joined(separator: "/") + "]"))
            if req.kinds.contains(.point) || req.kinds.contains(.distance) || req.kinds.contains(.angle) {
                let base = hotGrip?.origin ?? req.base
                if let b = base {
                    let d = cursorPoint - b
                    var a = deg(d.angle); if a < 0 { a += 360 }
                    lines.append("L \(fmt(d.length, 2))   ∠ \(fmt(a, 1))°")
                } else {
                    lines.append("X \(fmt(cursorPoint.x, 2))   Y \(fmt(cursorPoint.y, 2))")
                }
            }
        } else if let g = hotGrip {
            let d = cursorPoint - g.origin
            var a = deg(d.angle); if a < 0 { a += 360 }
            if let a = g.action { lines.append("\(a.title)  (Esc cancels)") }
            else if g.mode != .stretch || !g.dragging { lines.append("** \(g.mode.rawValue.uppercased())\(g.copy ? " (multiple)" : "") **  Space: next mode · type a value · C copy · MO RO SC MI ST") }
            else { lines.append(g.turns % 4 == 0 ? "Stretch point  (Space rotates 90°)" : "Stretch point, rotated \((g.turns % 4 + 4) % 4 * 90)°  (Space: +90°, Shift+Space: −90°)") }
            lines.append("L \(fmt(d.length, 2))   ∠ \(fmt(a, 1))°")
        }
        if !model.commandInput.isEmpty { lines.append("› " + model.commandInput) }
        drawTooltip(ctx, lines, at: CGPoint(x: v.x + 20, y: v.y - 18))
    }

    // MARK: Cursor, snapping, picking

    override func updateTrackingAreas() {
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
        super.updateTrackingAreas()
    }
    private var currentCursor: NSCursor {
        if model?.showStart == true || model?.sheet != nil { return .arrow }
        if panLast != nil { return .closedHand }
        if spaceDown { return .openHand }
        return PlanCanvasView.blankCursor
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: currentCursor) }
    override func cursorUpdate(with event: NSEvent) { currentCursor.set() }
    private func refreshCursor() { window?.invalidateCursorRects(for: self); currentCursor.set() }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) {
        mouseView = nil; hoverID = nil; hoverGrip = nil; snap = nil
        model?.live.snapHint = nil
        overlay.needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { track(event); if hotGrip?.solve == true { solveDrag() } }

    private func track(_ e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        mouseView = v
        updateCursorPoint(v)
        overlay.needsDisplay = true
    }

    private func updateCursorPoint(_ v: CGPoint) {
        guard let model else { return }
        let ed = model.editor
        rawWorld = toWorld(v)
        var p = rawWorld
        snap = nil
        let req = ed.request
        let wantsPoint = (req.map { $0.kinds.contains(.point) } ?? false) || hotGrip != nil
        if let g = hotGrip, !g.solve, g.mode == .stretch, g.action == nil, let e = ed.doc.entity(g.id), let gr = GripEditor.grip(e.geometry, g.index) {
            // Grip stretch: the core resolves snaps (never to the dragged grip itself) and ortho/polar from the grip (SEL-033).
            p = ed.gripDragPoint(g.id, grip: gr, cursor: rawWorld, tolerance: Double(10 / scale))
            if ed.settings.objectSnap, let r = Snap.find(cursor: rawWorld, doc: ed.doc, settings: ed.settings, tolerance: Double(10 / scale), base: gr.point), r.point.isClose(p, tol: 1e-9) { snap = r }
        } else if wantsPoint {
            let base = hotGrip?.origin ?? req?.base
            if ed.settings.objectSnap, let r = Snap.find(cursor: rawWorld, doc: ed.doc, settings: ed.settings, tolerance: Double(10 / scale), base: base) {
                snap = r
                p = r.point
            } else {
                if ed.settings.gridSnap, ed.settings.gridSpacing > 0 {
                    let g = ed.settings.gridSpacing
                    p = Vec2((p.x / g).rounded() * g, (p.y / g).rounded() * g)
                }
                if let b = base { p = Snap.constrain(base: b, cursor: p, settings: ed.settings) }
            }
        }
        cursorPoint = p
        ed.cursor = p
        if model.live.cursorWorld != p { model.live.cursorWorld = p }
        let hint = snap.map { snapLabel($0.kind) }
        if model.live.snapHint != hint { model.live.snapHint = hint }
        let wantsPick = hotGrip == nil && windowSel == nil && panLast == nil &&
            (ed.isIdle || (req.map { !$0.kinds.isDisjoint(with: [.selection, .entity]) && !$0.kinds.contains(.point) } ?? false))
        // SELECTIONPREVIEW: 1 = highlight when idle, 2 = during selection prompts, 3 = both (SEL-019).
        let sp = model.doc.variable("SELECTIONPREVIEW").flatMap(Int.init) ?? 3
        let preview = ed.isIdle ? sp & 1 != 0 : sp & 2 != 0
        hoverID = wantsPick && preview ? pick(at: rawWorld) : nil
        if ed.isIdle && hotGrip == nil, let g = gripHit(v) { hoverGrip = g } else { hoverGrip = nil }
    }

    /// Topmost selectable object near a world point (6 px tolerance); strokes win over area fills.
    func pick(at w: Vec2) -> EntityID? {
        guard let model else { return nil }
        let s = ensureScene()
        let tol = Double(6 / scale)
        let q = cg(w)
        let ct = CGFloat(tol)
        var best: (EntityID, Double)?
        for (i, e) in s.entries.enumerated() {
            guard let id = e.id, e.bounds.insetBy(dx: -ct, dy: -ct).contains(q) else { continue }
            var d = s.distance(from: w, entry: i)
            if d == 0 && e.texts.isEmpty { d = tol * 0.9 }
            if d <= tol, d < (best?.1 ?? .infinity), model.editor.isSelectable(id) { best = (id, d) }
        }
        return best?.0
    }

    // MARK: Selection cycling (SEL-018)

    /// Overlapping objects under the last pick: clicking again at the same spot swaps the selected one for the next.
    private var cycle: (point: Vec2, ids: [EntityID], index: Int)?

    /// Records the objects under a fresh pick: the canvas pick first, then the other candidates nearest first.
    private func startCycle(at w: Vec2, first: EntityID) {
        guard let model else { return }
        let ids = [first] + model.editor.pickCandidates(at: w, tolerance: Double(6 / scale)).filter { $0 != first && model.editor.isSelectable($0) }
        cycle = ids.count > 1 ? (w, ids, 0) : nil
        if ids.count > 1 { model.live.snapHint = "1 of \(ids.count) overlapping objects — click again to cycle" }
    }

    /// Clicking again (without Shift) where overlapping objects were picked selects the next one instead. Returns true
    /// when the click was consumed by cycling.
    private func cycleSelection(at w: Vec2) -> Bool {
        guard let model, var c = cycle else { return false }
        let ed = model.editor
        guard c.point.distance(to: w) <= Double(6 / scale), ed.selection.contains(c.ids[c.index]) else { cycle = nil; return false }
        ed.selection.subtract(ed.expandGroups([c.ids[c.index]]))
        c.index = (c.index + 1) % c.ids.count
        ed.selection.formUnion(ed.expandGroups([c.ids[c.index]]))
        cycle = c
        let kind = ObjectQuery.typeName(c.ids[c.index], doc: model.doc) ?? "object"
        model.live.snapHint = "\(c.index + 1) of \(c.ids.count): \(kind) #\(c.ids[c.index])"
        return true
    }

    /// Window (fully inside) or crossing selection over the drawn geometry.
    func selectIDs(in box: BBox2, crossing: Bool) -> [EntityID] {
        guard let model else { return [] }
        let s = ensureScene()
        let doc = model.doc
        let r = CGRect(x: box.min.x, y: box.min.y, width: box.width, height: box.height)
        var state: [EntityID: (inside: Bool, cross: Bool)] = [:]
        for (i, e) in s.entries.enumerated() {
            guard let id = e.id else { continue }
            var st = state[id] ?? (true, false)
            let inside = r.contains(e.bounds)
            st.inside = st.inside && inside
            if crossing && !st.cross && e.bounds.intersects(r) { st.cross = inside || s.crosses(entry: i, box: box) }
            state[id] = st
        }
        let editable = Set(doc.layers.filter(\.isEditable).map { $0.name.uppercased() })
        var layerOf: [EntityID: String] = [:]
        for e in doc.entities { layerOf[e.id] = e.layer }
        for el in doc.elements { layerOf[el.id] = el.layer }
        return state.filter { crossing ? ($0.value.inside || $0.value.cross) : $0.value.inside }
            .keys.filter { id in layerOf[id].map { editable.contains($0.uppercased()) || doc.layer(named: $0) == nil } ?? false }
            .sorted()
    }

    // MARK: Mouse

    /// Makes this canvas the one commands, zooms and typed grip input go to (tiled views, APP-007).
    func activate() {
        guard let model else { return }
        if model.canvas !== self { model.canvas = self }
        model.gripInput = { [weak self] line in self?.handleGripInput(line) ?? false }
        model.cancelLocalModes = { [weak self] in self?.cancelLocalModes() ?? false }
    }

    override func mouseDown(with e: NSEvent) {
        focus()
        activate()
        guard let model else { return }
        let v = convert(e.locationInWindow, from: nil)
        mouseView = v
        updateCursorPoint(v)
        let ed = model.editor
        defer { overlay.needsDisplay = true }
        if spaceDown { panLast = v; spacePanned = true; refreshCursor(); return }
        if windowSel != nil { windowSel?.current = v; finishWindow(shift: e.modifierFlags.contains(.shift)); return }
        if let g = hotGrip, !g.dragging { commitGrip(); return }
        if model.zoomWindowPending { windowSel = WindowSel(start: v, current: v, purpose: .zoom); return }
        if let req = ed.request {
            if req.kinds.contains(.point) { ed.feed(.point(cursorPoint)); return }
            if !req.kinds.isDisjoint(with: [.selection, .entity]) {
                // Selection prompts pick whole groups (PICKSTYLE); single-entity prompts pick the member itself.
                if let id = pick(at: rawWorld) { ed.feed(.selection(req.kinds.contains(.selection) ? ed.expandGroups([id]) : [id])) }
                else if req.kinds.contains(.selection) { windowSel = WindowSel(start: v, current: v, purpose: .request, lasso: e.modifierFlags.contains(.option) ? [v] : nil) }
            }
            return
        }
        guard ed.isIdle else { return }
        if let pl = model.placement {
            // Shift-click keeps placing copies; a plain click places one and ends.
            if ToolDrop.drop(pl.item, at: cursorPoint, onto: pick(at: rawWorld), model: model, rotation: Placement.angle(pl.turns)), !e.modifierFlags.contains(.shift) { model.placement = nil; model.live.snapHint = nil }
            return
        }
        if e.clickCount == 2, let id = pick(at: rawWorld) { editObject(id); return }
        if let f = flipHit(v) {
            ed.transaction(f.kind == .facing ? "Flip Facing" : f.kind == .hand ? "Flip Hand" : "Flip Wall") { FlipControls.apply(f, doc: &$0) }
            return
        }
        if let g = gripHit(v) {
            hotGrip = HotGrip(id: g.id, index: g.index, origin: g.point, startView: v, solve: beginConstraintDrag(g.id, at: g.point),
                              reference: GripModeEdit.reference(Array(ed.selection.union([g.id])), doc: ed.doc))
            hoverGrip = nil
            updateCursorPoint(v)
            return
        }
        if !e.modifierFlags.contains(.shift), cycleSelection(at: rawWorld) { return }
        if let id = pick(at: rawWorld) {
            // Picking a group member selects the whole group (PICKSTYLE, see GROUP).
            let ids = Set(ed.expandGroups([id]))
            startCycle(at: rawWorld, first: id)
            if e.modifierFlags.contains(.shift) {
                if ed.selection.contains(id) { ed.selection.subtract(ids) } else { ed.selection.formUnion(ids) }
            } else {
                ed.selection.formUnion(ids)
            }
            return
        }
        windowSel = WindowSel(start: v, current: v, purpose: .select, lasso: e.modifierFlags.contains(.option) ? [v] : nil)
    }

    override func mouseDragged(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        mouseView = v
        if let last = panLast { panView(dx: v.x - last.x, dy: v.y - last.y); panLast = v; return }
        if var w = windowSel {
            w.current = v
            if hypot(v.x - w.start.x, v.y - w.start.y) > 4 { w.moved = true }
            if let last = w.lasso?.last, hypot(v.x - last.x, v.y - last.y) > 3 { w.lasso?.append(v) }
            windowSel = w
        }
        if var g = hotGrip {
            if hypot(v.x - g.startView.x, v.y - g.startView.y) > 4 { g.moved = true }
            hotGrip = g
        }
        updateCursorPoint(v)
        solveDrag()
        overlay.needsDisplay = true
    }

    /// Starts a live constraint drag when the grip is a constrainable point of a constrained object.
    private func beginConstraintDrag(_ id: EntityID, at p: Vec2) -> Bool {
        guard let model, let e = model.doc.entity(id) else { return false }
        let set = ConstraintSet.load(model.doc)
        guard set.constraints.contains(where: { c in c.refs.contains { $0.entity == id } }) else { return false }
        let tol = Double(3 / scale) + 1e-9
        guard let part = Constraints.points(e.geometry).first(where: { $0.point.distance(to: p) <= tol })?.part else { return false }
        return model.editor.beginDragSolve(ref: CRef(id, part))
    }

    /// Moves the constraint-dragged point to the cursor and re-solves (the drawing updates live).
    private func solveDrag() {
        guard let g = hotGrip, g.solve, let model else { return }
        if let r = model.editor.dragSolve(point: cursorPoint) {
            let hint = r.converged ? "Constraints satisfied · \(r.dof) DOF" : "Over-constrained (residual \(fmt(r.residual, 4)))"
            if model.live.snapHint != hint { model.live.snapHint = hint }
        }
    }

    override func mouseUp(with e: NSEvent) {
        if panLast != nil { panLast = nil; refreshCursor(); return }
        if let w = windowSel, w.moved { finishWindow(shift: e.modifierFlags.contains(.shift)) }
        if let g = hotGrip, g.dragging {
            if g.moved { commitGrip() } else { hotGrip?.dragging = false }
        }
        overlay.needsDisplay = true
    }

    private func finishWindow(shift: Bool) {
        guard let w = windowSel, let model else { return }
        windowSel = nil
        if let pts = w.lasso {
            guard w.purpose != .zoom else { return }
            lassoSelect(pts, shift: shift, request: w.purpose == .request)
            return
        }
        let a = toWorld(w.start), b = toWorld(w.current)
        guard abs(w.current.x - w.start.x) > 2 || abs(w.current.y - w.start.y) > 2 else {
            if w.purpose == .zoom { model.zoomWindowPending = false }
            return
        }
        let box = BBox2(points: [a, b])
        switch w.purpose {
        case .zoom:
            model.zoomWindowPending = false
            zoom(to: box)
        case .select:
            let ids = Set(model.editor.expandGroups(Array(selectIDs(in: box, crossing: w.current.x < w.start.x))))
            if shift { model.editor.selection.subtract(ids) } else { model.editor.selection.formUnion(ids) }
        case .request:
            model.editor.feed(.selection(model.editor.expandGroups(selectIDs(in: box, crossing: w.current.x < w.start.x))))
        }
        overlay.needsDisplay = true
    }

    private func commitGrip() {
        guard let g = hotGrip, let model else { return }
        hotGrip = nil
        let ed = model.editor
        if !g.solve && g.mode != .stretch {
            // Grip modes act on the whole selection; with Copy the grip stays hot for more copies (SEL-034).
            guard let t = Grips.modeTransform(g.mode, base: g.origin, to: cursorPoint, reference: g.reference) else { return }
            GripModeEdit.apply(ed, ids: Array(ed.selection.union([g.id])), t, copy: g.copy, label: "Grip \(g.mode.rawValue.capitalized)\(g.copy ? " Copy" : "")")
            if g.copy { var h = g; h.dragging = false; h.moved = false; hotGrip = h }
            return
        }
        if !g.solve, let e = ed.doc.entity(g.id), let gr = GripEditor.grip(e.geometry, g.index) {
            if let a = g.action { ed.gripAction(g.id, grip: gr, action: a, to: cursorPoint, snap: false); return }
            if g.copy {
                ed.gripEdit(g.id, grip: gr, to: cursorPoint, mode: .stretch, copy: true, snap: false)
                var h = g; h.dragging = false; h.moved = false; hotGrip = h
                return
            }
        }
        if g.solve {
            _ = model.editor.dragSolve(point: cursorPoint)
            model.editor.endDragSolve(commit: cursorPoint.distance(to: g.origin) > 1e-12)
            return
        }
        let p = cursorPoint
        guard p.distance(to: g.origin) > 1e-12 || ((g.turns % 4) + 4) % 4 != 0 else { return }
        GripEditor.apply(editor: model.editor, id: g.id, grip: g.index, from: g.origin, to: p, turns: g.turns)
    }

    private func cancelLocalModes() -> Bool {
        var any = false
        if windowSel != nil { windowSel = nil; any = true }
        if let g = hotGrip { if g.solve { model?.editor.endDragSolve(commit: false) }; hotGrip = nil; any = true }
        if model?.zoomWindowPending == true { model?.zoomWindowPending = false; any = true }
        if model?.placement != nil { model?.placement = nil; model?.live.snapHint = nil; any = true }
        if any { overlay.needsDisplay = true }
        return any
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let model else { return }
        if cancelLocalModes() { return }
        // Shift+right-click at a point prompt: one-shot object snap override menu (PRC-019).
        if e.modifierFlags.contains(.shift), model.editor.request?.kinds.contains(.point) == true {
            NSMenu.popUpContextMenu(snapOverrideMenu(), with: e, for: self); return
        }
        if !model.editor.isIdle || !model.commandInput.isEmpty { model.enterPressed(); return }
        if let hg = hoverGrip, let menu = gripMenu(hg) { NSMenu.popUpContextMenu(menu, with: e, for: self); return }
        // Marking menu (APP-022): wait for a drag; a plain right-click still shows the shortcut menu on release.
        if RadialMenu.enabled { radialOrigin = convert(e.locationInWindow, from: nil); radialEvent = e; return }
        NSMenu.popUpContextMenu(contextMenu(), with: e, for: self)
    }
    private var radialOrigin: NSPoint?
    private var radialEvent: NSEvent?
    private var radialView: RadialMenuView?
    override func rightMouseDragged(with e: NSEvent) {
        guard let o = radialOrigin, let model else { return }
        let p = convert(e.locationInWindow, from: nil)
        let sector = RadialMenu.sector(dx: p.x - o.x, dy: p.y - o.y)
        if radialView == nil, sector != nil {
            let r = RadialMenu.radius + 34
            let v = RadialMenuView(frame: NSRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r))
            v.items = RadialMenu.items(RadialMenu.context(model.doc, selection: model.editor.selection))
            addSubview(v); radialView = v
        }
        radialView?.highlighted = sector
        if let s = sector, let v = radialView, v.items.indices.contains(s) { model.live.snapHint = RadialMenu.tooltip(v.items[s]) }
    }
    override func rightMouseUp(with e: NSEvent) {
        defer { radialOrigin = nil; radialEvent = nil }
        guard let o = radialOrigin, let model else { return }
        if let v = radialView {
            let chosen = v.highlighted.flatMap { v.items.indices.contains($0) ? v.items[$0] : nil }
            v.removeFromSuperview(); radialView = nil
            model.live.snapHint = nil
            if let c = chosen { model.runCommand(c.command) }
            return
        }
        _ = o
        NSMenu.popUpContextMenu(contextMenu(), with: radialEvent ?? e, for: self)
    }

    override func otherMouseDown(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        if e.clickCount == 2 { zoomExtents(); return }
        panLast = v
        refreshCursor()
    }
    override func otherMouseDragged(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        mouseView = v
        if let last = panLast { panView(dx: v.x - last.x, dy: v.y - last.y); panLast = v }
    }
    override func otherMouseUp(with e: NSEvent) { panLast = nil; refreshCursor() }

    override func scrollWheel(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        let zoomMods = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.option)
        if e.hasPreciseScrollingDeltas && !zoomMods {
            panView(dx: e.scrollingDeltaX, dy: -e.scrollingDeltaY)
        } else {
            let dy = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 40 : e.scrollingDeltaY
            guard dy != 0 else { return }
            zoomBy(pow(1.2, dy), about: v)
        }
    }

    override func magnify(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        zoomBy(max(0.2, 1 + e.magnification), about: v)
    }

    override func smartMagnify(with event: NSEvent) { zoomExtents() }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        guard let model else { super.keyDown(with: e); return }
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) { super.keyDown(with: e); return }
        let ed = model.editor
        switch e.keyCode {
        case 53: // Esc
            if !cancelLocalModes() { model.cancelCommand() }
        case 36, 76: // Return / Enter
            model.enterPressed()
        case 49: // Space
            if var pl = model.placement {
                pl.turns += flags.contains(.shift) ? -1 : 1
                model.placement = pl
                model.live.snapHint = "Rotation \(Placement.degrees(pl.turns))° · click to place · Esc cancels"
                overlay.needsDisplay = true
                return
            }
            if var g = hotGrip, !g.solve, !g.dragging, g.action == nil {
                // Space with a hot grip cycles Stretch → Move → Rotate → Scale → Mirror (SEL-034).
                g.mode = g.mode.next
                hotGrip = g
                model.live.snapHint = "Grip mode: \(g.mode.rawValue.capitalized)"
                overlay.needsDisplay = true
                return
            }
            if var g = hotGrip, !g.solve {
                // Space while dragging a grip rotates the object 90° about the grip (Shift = clockwise).
                g.turns += flags.contains(.shift) ? -1 : 1
                g.moved = true
                hotGrip = g
                model.live.snapHint = "Rotated \(((g.turns % 4) + 4) % 4 * 90)° about the grip"
                overlay.needsDisplay = true
                return
            }
            if e.isARepeat { return }
            if !model.commandInput.isEmpty {
                if let r = ed.request, r.kinds.contains(.string), !r.kinds.contains(.point) { model.commandInput += " "; model.focusCommandLine() }
                else { model.enterPressed() }
            } else {
                spaceDown = true
                spacePanned = false
                refreshCursor()
            }
        case 51, 117: // Backspace / Delete
            if !model.commandInput.isEmpty { model.commandInput.removeLast() }
            else if ed.isIdle && !ed.selection.isEmpty {
                if model.has("ERASE") { model.runCommand("ERASE") } else { model.deleteSelection() }
            }
        case 123, 124, 125, 126 where ed.isIdle && model.commandInput.isEmpty && !ed.selection.isEmpty:
            // Arrow keys nudge the selection (MOD-028): one pixel, the snap spacing with grid snap, ×10 with Shift.
            let step = ed.nudgeStep() * (flags.contains(.shift) ? 10 : 1)
            let d: Vec2 = e.keyCode == 123 ? Vec2(-step, 0) : e.keyCode == 124 ? Vec2(step, 0) : e.keyCode == 125 ? Vec2(0, -step) : Vec2(0, step)
            let n = ed.nudgeSelection(by: d)
            model.live.snapHint = n > 0 ? "Nudged \(n) object(s) by \(fmt(d.length, 4))" : "Nothing to nudge (locked layer?)"
        case 126, 125: // arrows up/down → command history
            model.focusCommandLine()
        case 48: // Tab: select the chain of joined walls under the cursor (SEL-022)
            if ed.isIdle, let h = hoverID, let el = model.doc.element(h), case .wall = el.geometry {
                let chain = WallChain.ids(from: h, doc: model.doc, tolerance: max(Double(2 / scale), 1)).filter { ed.isSelectable($0) }
                ed.selection.formUnion(chain)
                model.live.snapHint = "Selected \(chain.count) joined wall(s)"
            }
        default:
            if let chars = e.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 && !($0.value >= 0xF700 && $0.value <= 0xF8FF) }) {
                model.commandInput += chars
                model.focusCommandLine()
            } else {
                super.keyDown(with: e)
            }
        }
        overlay.needsDisplay = true
    }

    override func keyUp(with e: NSEvent) {
        if e.keyCode == 49, spaceDown {
            spaceDown = false
            panLast = nil
            refreshCursor()
            if !spacePanned { model?.enterPressed() }
            return
        }
        super.keyUp(with: e)
    }

    // MARK: Context menu

    /// Right-click menu (APP-023): Repeat, Recent Input, selection edits (Move, Copy, Rotate, Scale, Mirror, Erase), undo/redo, properties.
    private func contextMenu() -> NSMenu {
        let m = NSMenu()
        guard let model else { return m }
        let ed = model.editor
        let items = ShortcutMenu.items(hasSelection: !ed.selection.isEmpty, lastCommand: ed.lastCommand, recentInput: model.inputHistory,
                                       canUndo: ed.history.canUndo, canRedo: ed.history.canRedo, undoLabel: ed.history.undoLabel, redoLabel: ed.history.redoLabel)
        for it in items { add(it, to: m) }
        return m
    }
    private func add(_ it: ShortcutMenu.Item, to m: NSMenu) {
        switch it.action {
        case .separator: m.addItem(.separator())
        case .submenu(let title, let sub):
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sm = NSMenu(title: title)
            for x in sub { add(x, to: sm) }
            i.submenu = sm
            i.isEnabled = it.enabled
            m.addItem(i)
        default:
            let i = NSMenuItem(title: it.title, action: it.enabled ? #selector(ctxItem(_:)) : nil, keyEquivalent: "")
            i.target = self
            i.isEnabled = it.enabled
            i.representedObject = MenuAction(it.action)
            m.addItem(i)
        }
    }
    private final class MenuAction: NSObject { let a: ShortcutMenu.Action; init(_ a: ShortcutMenu.Action) { self.a = a } }
    /// Snap override menu entries (title, token typed at the point prompt); nil title = separator.
    static let snapOverrideItems: [(String?, String)] = [
        ("Temporary Track Point", "TT"), ("From", "FROM"), (nil, ""),
        ("Endpoint", "END"), ("Midpoint", "MID"), ("Intersection", "INT"), ("Extension", "EXT"), (nil, ""),
        ("Center", "CEN"), ("Geometric Center", "GCEN"), ("Quadrant", "QUA"), ("Tangent", "TAN"), (nil, ""),
        ("Perpendicular", "PER"), ("Parallel", "PAR"), ("Node", "NOD"), ("Insert", "INS"), ("Nearest", "NEA"), (nil, ""),
        ("None", "NON"), ("Osnap Settings…", "'OSNAP"),
    ]
    private func snapOverrideMenu() -> NSMenu {
        let m = NSMenu(title: "Snap Overrides")
        for (title, token) in Self.snapOverrideItems {
            guard let title else { m.addItem(.separator()); continue }
            let i = NSMenuItem(title: title, action: #selector(snapOverrideItem(_:)), keyEquivalent: "")
            i.representedObject = token; i.target = self
            m.addItem(i)
        }
        return m
    }
    @objc private func snapOverrideItem(_ sender: NSMenuItem) {
        guard let model, let token = sender.representedObject as? String else { return }
        model.submitLine(token)
    }

    @objc private func ctxItem(_ sender: NSMenuItem) {
        guard let model, let a = (sender.representedObject as? MenuAction)?.a else { return }
        switch a {
        case .run(let line): model.runCommand(line)
        case .repeatLast: if let l = model.editor.lastCommand { model.runCommand(l) }
        case .undo: model.editor.undo()
        case .redo: model.editor.redo()
        case .deselect: model.editor.selection = []
        case .selectAll: model.selectAll()
        case .zoomExtents: zoomExtents()
        case .properties: model.showPanels = true; model.panelTab = .properties
        case .quickProperties: model.showQuickProperties = true
        case .separator, .submenu: break
        }
    }

    /// Multi-functional grip menu (SEL-035): options of the hovered grip; the chosen one follows the cursor until the next click.
    private func gripMenu(_ hg: (id: EntityID, index: Int, point: Vec2)) -> NSMenu? {
        guard let model, let e = model.doc.entity(hg.id), let gr = GripEditor.grip(e.geometry, hg.index) else { return nil }
        let acts = Grips.actions(e.geometry, grip: gr)
        guard acts.count > 1 else { return nil }
        let m = NSMenu()
        for a in acts {
            let i = NSMenuItem(title: a.title, action: #selector(gripMenuItem(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = GripChoice(hg.id, hg.index, hg.point, a)
            m.addItem(i)
        }
        return m
    }
    private final class GripChoice: NSObject {
        let id: EntityID, index: Int, point: Vec2, action: GripAction
        init(_ id: EntityID, _ index: Int, _ point: Vec2, _ action: GripAction) { self.id = id; self.index = index; self.point = point; self.action = action }
    }
    @objc private func gripMenuItem(_ sender: NSMenuItem) {
        guard let model, let c = sender.representedObject as? GripChoice else { return }
        let ed = model.editor
        if c.action == .removeVertex || c.action == .convertToLine {
            if let e = ed.doc.entity(c.id), let gr = GripEditor.grip(e.geometry, c.index) { ed.gripAction(c.id, grip: gr, action: c.action, to: gr.point, snap: false) }
            return
        }
        ed.selection.insert(c.id)
        hotGrip = HotGrip(id: c.id, index: c.index, origin: c.point, startView: toView(c.point), dragging: false, action: c.action == .stretch ? nil : c.action)
        model.live.snapHint = "\(c.action.title): click the new location · Esc cancels"
        overlay.needsDisplay = true
    }

    /// Lasso selection from view points: window when drawn clockwise, crossing when counter-clockwise (core SEL-007).
    /// Returns the ids found.
    @discardableResult
    func lassoSelect(_ pts: [CGPoint], shift: Bool = false, request: Bool = false) -> Set<EntityID> {
        guard let model, pts.count >= 3 else { return [] }
        let ids = Set(model.editor.expandGroups(model.editor.select(lasso: pts.map(toWorld))))
        if request { model.editor.feed(.selection(Array(ids).sorted())) }
        else if shift { model.editor.selection.subtract(ids) } else { model.editor.selection.formUnion(ids) }
        overlay.needsDisplay = true
        return ids
    }

    /// Makes grip `index` of an object hot, as a click on it does (scripts and self-tests). False when it has no such grip.
    @discardableResult
    func makeGripHot(_ id: EntityID, index: Int) -> Bool {
        guard let model else { return false }
        let doc = model.doc
        let pts: [Vec2]
        if let e = doc.entity(id) { pts = GripEditor.grips(e) } else if let el = doc.element(id) { pts = GripEditor.grips(el, doc: doc) } else { return false }
        guard pts.indices.contains(index) else { return false }
        model.editor.selection.insert(id)
        hotGrip = HotGrip(id: id, index: index, origin: pts[index], startView: toView(pts[index]), dragging: false,
                          reference: GripModeEdit.reference(Array(model.editor.selection), doc: doc))
        cursorPoint = pts[index]
        return true
    }
    /// Current hot grip mode and copy flag (nil when no grip is hot).
    var hotGripState: (mode: GripMode, copy: Bool)? { hotGrip.map { ($0.mode, $0.copy) } }
    /// Moves the (snapped) cursor point without a mouse event (scripts and self-tests).
    func setCursorPoint(_ p: Vec2) { cursorPoint = p }

    // MARK: Hot-grip typed input (SEL-034 keywords, SEL-038 values)

    /// Handles a line typed while a grip is hot. Returns false when no grip is hot (the line goes to the command line).
    func handleGripInput(_ line: String) -> Bool {
        guard let model, var g = hotGrip, !g.solve else { return false }
        let ed = model.editor
        let t = line.trimmingCharacters(in: .whitespaces).uppercased()
        defer { overlay.needsDisplay = true }
        if t.isEmpty { g.mode = g.mode.next; hotGrip = g; model.live.snapHint = "Grip mode: \(g.mode.rawValue.capitalized)"; return true }
        if t == "C" || t == "COPY" { g.copy.toggle(); hotGrip = g; model.live.snapHint = g.copy ? "Copy on: each click places a copy" : "Copy off"; return true }
        if t == "X" || t == "EXIT" { hotGrip = nil; return true }
        if let m = GripModeEdit.keywords[t] { g.mode = m; hotGrip = g; model.live.snapHint = "Grip mode: \(m.rawValue.capitalized)"; return true }
        // A typed point: x,y (absolute) or @dx,dy (relative to the grip).
        let parts = t.replacingOccurrences(of: "@", with: "").split(separator: ",").compactMap { InputParser.parseNumber(String($0)) }
        if parts.count == 2 {
            let q = t.hasPrefix("@") ? g.origin + Vec2(parts[0], parts[1]) : Vec2(parts[0], parts[1])
            cursorPoint = q
            commitGrip()
            return true
        }
        guard let v = InputParser.parseNumber(t) else { model.live.snapHint = "Enter a distance, a point, or MO/RO/SC/MI/ST/C/X"; return true }
        let dirPoint = cursorPoint
        if g.mode == .stretch {
            if let e = ed.doc.entity(g.id), let gr = GripEditor.grip(e.geometry, g.index), g.action == nil, g.turns % 4 == 0 {
                ed.gripTyped(g.id, grip: gr, distance: v, toward: dirPoint)
            } else {
                let d = (dirPoint - g.origin).normalized
                cursorPoint = g.origin + (d == .zero ? Vec2(1, 0) : d) * v
                commitGrip(); return true
            }
            hotGrip = nil
        } else if let tr = GripModeEdit.typedTransform(g.mode, base: g.origin, cursor: dirPoint, value: v) {
            GripModeEdit.apply(ed, ids: Array(ed.selection.union([g.id])), tr, copy: g.copy, label: "Grip \(g.mode.rawValue.capitalized)")
            if !g.copy { hotGrip = nil }
        }
        return true
    }

    // MARK: Double-click editing

    private func editObject(_ id: EntityID) {
        guard let model, let e = model.doc.entity(id) else {
            model?.editor.selection = [id]; model?.showPanels = true; model?.panelTab = .properties
            return
        }
        let current: String
        let multiline: Bool
        switch e.geometry {
        case .text(let t): current = t.content; multiline = t.width > 0 || t.content.contains("\n")
        case .leader(let l): current = l.text; multiline = true
        case .dimension(let d): current = d.textOverride ?? ""; multiline = false
        default:
            model.editor.selection = [id]; model.showPanels = true; model.panelTab = .properties
            return
        }
        let alert = NSAlert()
        alert.messageText = "Edit Text"
        alert.informativeText = e.typeName == "dimension" ? "Override the measured value (leave empty for the measurement). Use <> for the measured value." : "Edit the text content."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let getValue: () -> String
        if multiline {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
            tv.string = current
            tv.font = .systemFont(ofSize: 12)
            tv.isRichText = false
            let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))
            sv.documentView = tv
            sv.hasVerticalScroller = true
            sv.borderType = .bezelBorder
            alert.accessoryView = sv
            getValue = { tv.string }
        } else {
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            tf.stringValue = current
            alert.accessoryView = tf
            getValue = { tf.stringValue }
            alert.window.initialFirstResponder = tf
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = getValue()
        guard value != current else { return }
        model.editor.transaction("Edit Text") { d in
            guard let k = d.entityIndex(id) else { return }
            switch d.entities[k].geometry {
            case .text(var t): t.content = value; d.entities[k].geometry = .text(t)
            case .leader(var l): l.text = value; d.entities[k].geometry = .leader(l)
            case .dimension(var dm): dm.textOverride = value.isEmpty ? nil : value; d.entities[k].geometry = .dimension(dm)
            default: break
            }
        }
    }
}
