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
    }

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
        // 2. Strokes batched per style.
        ctx.setLineJoin(.round)
        for si in styles.indices {
            var any = false
            for ci in vis { if let path = chunks[ci].strokes[si] { ctx.addPath(path); any = true } }
            guard any else { continue }
            applyStroke(styles[si], ctx: ctx, scale: scale, params: params, color: nil)
            ctx.strokePath()
        }
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
        ctx.setLineCap(.round)
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
        case .slab(let s): return s.boundary
        case .roof(let r): return r.boundary
        case .space(let s): return s.boundary
        case .railing(let r): return r.path
        case .opening(let o):
            guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { return [] }
            return [w.centerStart + w.direction * o.offset]
        }
    }

    static func grips(_ e: Entity) -> [Vec2] { GeometryOps.grips(e.geometry) }

    static func moved(_ g: Geometry, grip i: Int, from o: Vec2, to p: Vec2) -> Geometry {
        let d = p - o
        switch g {
        case .point: return .point(p)
        case .line(var l):
            if i == 0 { l.a = p } else if i == 2 { l.b = p } else { l.a += d; l.b += d }
            return .line(l)
        case .circle(var c):
            if i == 0 { c.center = p } else { c.radius = max(c.center.distance(to: p), 1e-9) }
            return .circle(c)
        case .arc(var a):
            switch i {
            case 3: a.center = p
            case 0: a.start = (p - a.center).angle; a.radius = max(a.center.distance(to: p), 1e-9)
            case 2: a.end = (p - a.center).angle; a.radius = max(a.center.distance(to: p), 1e-9)
            default: a.radius = max(a.center.distance(to: p), 1e-9)
            }
            return .arc(a)
        case .ellipse(var e):
            switch i {
            case 0: e.center = p
            case 1: if (p - e.center).length > 1e-9 { let r = e.ratio * e.majorAxis.length; e.majorAxis = p - e.center; e.ratio = r / e.majorAxis.length }
            case 2: if (e.center - p).length > 1e-9 { let r = e.ratio * e.majorAxis.length; e.majorAxis = e.center - p; e.ratio = r / e.majorAxis.length }
            default: e.ratio = max(1e-6, e.center.distance(to: p) / max(e.majorAxis.length, 1e-9))
            }
            return .ellipse(e)
        case .polyline(var pl):
            if pl.vertices.indices.contains(i) { pl.vertices[i].p = p }
            return .polyline(pl)
        case .spline(var s):
            if !s.fitPoints.isEmpty { if s.fitPoints.indices.contains(i) { s.fitPoints[i] = p } }
            else if s.controlPoints.indices.contains(i) { s.controlPoints[i] = p }
            return .spline(s)
        case .dimension(var dm):
            if dm.points.indices.contains(i) { dm.points[i] = p }
            return .dimension(dm)
        case .leader(var l):
            if l.points.indices.contains(i) { l.points[i] = p }
            return .leader(l)
        case .hatch: return g
        default:
            return GeometryOps.transform(g, .translation(d))
        }
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
        case .slab(var s): if s.boundary.indices.contains(i) { s.boundary[i] = p }; return .slab(s)
        case .roof(var r): if r.boundary.indices.contains(i) { r.boundary[i] = p }; return .roof(r)
        case .space(var s): if s.boundary.indices.contains(i) { s.boundary[i] = p }; return .space(s)
        case .railing(var r): if r.path.indices.contains(i) { r.path[i] = p }; return .railing(r)
        case .opening(var op):
            guard let host = doc.element(op.hostWall), case .wall(let w) = host.geometry else { return el.geometry }
            let len = w.length
            let t = (p - w.centerStart).dot(w.direction)
            op.offset = min(max(t, op.width / 2), max(op.width / 2, len - op.width / 2))
            return .opening(op)
        }
    }

    /// Applies a grip edit as one undoable transaction. Wall endpoints drag joined walls along.
    @MainActor static func apply(editor: Editor, id: EntityID, grip i: Int, from o: Vec2, to p: Vec2) {
        editor.transaction("Grip Edit") { d in
            if let k = d.entityIndex(id) {
                d.entities[k].geometry = moved(d.entities[k].geometry, grip: i, from: o, to: p)
            } else if let k = d.elementIndex(id) {
                let el = d.elements[k]
                d.elements[k].geometry = moved(el, grip: i, from: o, to: p, doc: d)
                if case .wall(let w) = el.geometry, i <= 1 {
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
        model.canvas = v
        return v
    }
    func updateNSView(_ v: PlanCanvasView, context: Context) {
        if model.canvas !== v { model.canvas = v }
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
    }
    private var windowSel: WindowSel?
    private struct HotGrip { var id: EntityID; var index: Int; var origin: Vec2; var startView: CGPoint; var moved = false; var dragging = true }
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
        model.$revision.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.modelChanged() }.store(in: &cancellables)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        if handledZoomRequest != model.zoomExtentsRequest { zoomExtents() }
        if let mv = mouseView { updateCursorPoint(mv) }
        content.needsDisplay = true
        overlay.needsDisplay = true
    }

    // MARK: Transform

    var worldTransform: CGAffineTransform {
        CGAffineTransform(translationX: bounds.midX, y: bounds.midY).scaledBy(x: scale, y: scale).translatedBy(x: -center.x, y: -center.y)
    }
    func toView(_ w: Vec2) -> CGPoint {
        CGPoint(x: (CGFloat(w.x) - center.x) * scale + bounds.midX, y: (CGFloat(w.y) - center.y) * scale + bounds.midY)
    }
    func toWorld(_ v: CGPoint) -> Vec2 {
        Vec2(Double((v.x - bounds.midX) / scale + center.x), Double((v.y - bounds.midY) / scale + center.y))
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
        let w = max(b.width, 1e-6), h = max(b.height, 1e-6)
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
        center = CGPoint(x: CGFloat(w.x) - (p.x - bounds.midX) / scale, y: CGFloat(w.y) - (p.y - bounds.midY) / scale)
        viewChanged()
    }
    func panView(dx: CGFloat, dy: CGFloat) {
        center.x -= dx / scale
        center.y -= dy / scale
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

    private var params: RenderParams {
        var p = RenderParams()
        p.lineweights = model?.editor.settings.lineweightDisplay ?? true
        p.minWidth = 1 / (window?.backingScaleFactor ?? 2)
        return p
    }

    // MARK: Drawing (content layer)

    private func drawContent(_ ctx: CGContext, _ dirty: NSRect) {
        ctx.setFillColor(Theme.nsCanvas.cgColor)
        ctx.fill(dirty)
        guard let model else { return }
        let s = ensureScene()
        if model.editor.settings.showGrid { drawGrid(ctx, dirty) } else { drawAxes(ctx) }
        ctx.saveGState()
        ctx.concatenate(worldTransform)
        let vis = visibleWorld(dirty)
        s.draw(in: ctx, visible: vis, scale: scale, params: params)
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

    private func drawUCSIcon(_ ctx: CGContext) {
        let o = CGPoint(x: 26, y: 26), len: CGFloat = 34
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.9))
        ctx.strokeLineSegments(between: [o, CGPoint(x: o.x + len, y: o.y)])
        ctx.move(to: CGPoint(x: o.x + len, y: o.y)); ctx.addLine(to: CGPoint(x: o.x + len - 6, y: o.y + 3)); ctx.addLine(to: CGPoint(x: o.x + len - 6, y: o.y - 3)); ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.35, blue: 0.35, alpha: 0.9)); ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.9))
        ctx.strokeLineSegments(between: [o, CGPoint(x: o.x, y: o.y + len)])
        ctx.move(to: CGPoint(x: o.x, y: o.y + len)); ctx.addLine(to: CGPoint(x: o.x - 3, y: o.y + len - 6)); ctx.addLine(to: CGPoint(x: o.x + 3, y: o.y + len - 6)); ctx.closePath()
        ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.9)); ctx.fillPath()
        ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 0.9)); ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: o.x - 3, y: o.y - 3, width: 6, height: 6))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor(white: 0.85, alpha: 0.9)]
        ("X" as NSString).draw(at: CGPoint(x: o.x + len + 3, y: o.y - 6), withAttributes: attrs)
        ("Y" as NSString).draw(at: CGPoint(x: o.x - 3, y: o.y + len + 2), withAttributes: attrs)
    }

    private func computeGrips() {
        currentGrips = []
        guard let model, model.editor.isIdle else { return }
        let sel = model.editor.selection
        guard !sel.isEmpty, sel.count <= 300 else { return }
        let doc = model.doc
        for e in doc.entities where sel.contains(e.id) {
            for (i, p) in GripEditor.grips(e).enumerated() { currentGrips.append((e.id, i, p)) }
        }
        for el in doc.elements where sel.contains(el.id) {
            for (i, p) in GripEditor.grips(el, doc: doc).enumerated() { currentGrips.append((el.id, i, p)) }
        }
    }

    private func drawGrips(_ ctx: CGContext) {
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
        // Command rubber-band preview.
        if let req = ed.request, req.kinds.contains(.point) || req.kinds.contains(.distance) || req.kinds.contains(.angle), let pv = req.preview, mouseView != nil {
            let geoms = pv(cursorPoint)
            if !geoms.isEmpty {
                var items = DrawListBuilder.previewItems(geoms, doc: ed.doc, color: previewColor)
                if items.isEmpty { items = fallbackItems(geoms, doc: ed.doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm)
            }
        }
        // Grip drag preview.
        if let g = hotGrip {
            let doc = ed.doc
            if let e = doc.entity(g.id) {
                let geo = GripEditor.moved(e.geometry, grip: g.index, from: g.origin, to: cursorPoint)
                var items = DrawListBuilder.previewItems([geo], doc: doc, color: previewColor)
                if items.isEmpty { items = fallbackItems([geo], doc: doc, color: previewColor) }
                RenderScene.drawItems(items, ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
            } else if var el = doc.element(g.id) {
                el.geometry = GripEditor.moved(el, grip: g.index, from: g.origin, to: cursorPoint, doc: doc)
                RenderScene.drawItems(elementPreview(el, doc: doc, color: previewColor), ctx: ctx, scale: scale, params: prm, colorOverride: Theme.nsAccent.cgColor)
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
        // Selection / zoom window.
        if let w = windowSel {
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
            lines.append("Stretch point")
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
    override func mouseMoved(with event: NSEvent) { track(event) }

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
        if wantsPoint {
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
        hoverID = wantsPick ? pick(at: rawWorld) : nil
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

    override func mouseDown(with e: NSEvent) {
        focus()
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
                if let id = pick(at: rawWorld) { ed.feed(.selection([id])) }
                else if req.kinds.contains(.selection) { windowSel = WindowSel(start: v, current: v, purpose: .request) }
            }
            return
        }
        guard ed.isIdle else { return }
        if e.clickCount == 2, let id = pick(at: rawWorld) { editObject(id); return }
        if let g = gripHit(v) {
            hotGrip = HotGrip(id: g.id, index: g.index, origin: g.point, startView: v)
            hoverGrip = nil
            updateCursorPoint(v)
            return
        }
        if let id = pick(at: rawWorld) {
            // Picking a group member selects the whole group (PICKSTYLE, see GROUP).
            let ids = Set(ed.expandGroups([id]))
            if e.modifierFlags.contains(.shift) {
                if ed.selection.contains(id) { ed.selection.subtract(ids) } else { ed.selection.formUnion(ids) }
            } else {
                ed.selection.formUnion(ids)
            }
            return
        }
        windowSel = WindowSel(start: v, current: v, purpose: .select)
    }

    override func mouseDragged(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        mouseView = v
        if let last = panLast { panView(dx: v.x - last.x, dy: v.y - last.y); panLast = v; return }
        if var w = windowSel {
            w.current = v
            if hypot(v.x - w.start.x, v.y - w.start.y) > 4 { w.moved = true }
            windowSel = w
        }
        if var g = hotGrip {
            if hypot(v.x - g.startView.x, v.y - g.startView.y) > 4 { g.moved = true }
            hotGrip = g
        }
        updateCursorPoint(v)
        overlay.needsDisplay = true
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
            model.editor.feed(.selection(selectIDs(in: box, crossing: w.current.x < w.start.x)))
        }
        overlay.needsDisplay = true
    }

    private func commitGrip() {
        guard let g = hotGrip, let model else { return }
        hotGrip = nil
        let p = cursorPoint
        guard p.distance(to: g.origin) > 1e-12 else { return }
        GripEditor.apply(editor: model.editor, id: g.id, grip: g.index, from: g.origin, to: p)
    }

    private func cancelLocalModes() -> Bool {
        var any = false
        if windowSel != nil { windowSel = nil; any = true }
        if hotGrip != nil { hotGrip = nil; any = true }
        if model?.zoomWindowPending == true { model?.zoomWindowPending = false; any = true }
        if any { overlay.needsDisplay = true }
        return any
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let model else { return }
        if cancelLocalModes() { return }
        if !model.editor.isIdle || !model.commandInput.isEmpty { model.enterPressed(); return }
        NSMenu.popUpContextMenu(contextMenu(), with: e, for: self)
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
        case 126, 125: // arrows up/down → command history
            model.focusCommandLine()
        case 48: // Tab
            break
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

    private func contextMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ title: String, _ sel: Selector, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: enabled ? sel : nil, keyEquivalent: "")
            i.target = self
            i.isEnabled = enabled
            m.addItem(i)
        }
        let ed = model?.editor
        item(ed?.lastCommand.map { "Repeat \($0)" } ?? "Repeat", #selector(ctxRepeat), enabled: ed?.lastCommand != nil)
        m.addItem(.separator())
        item(ed?.history.undoLabel.map { "Undo \($0)" } ?? "Undo", #selector(ctxUndo), enabled: ed?.history.canUndo ?? false)
        item(ed?.history.redoLabel.map { "Redo \($0)" } ?? "Redo", #selector(ctxRedo), enabled: ed?.history.canRedo ?? false)
        m.addItem(.separator())
        let hasSel = !(ed?.selection.isEmpty ?? true)
        item("Delete", #selector(ctxDelete), enabled: hasSel)
        item("Deselect All", #selector(ctxDeselect), enabled: hasSel)
        item("Select All", #selector(ctxSelectAll))
        m.addItem(.separator())
        item("Zoom Extents", #selector(ctxZoomExtents))
        item("Properties", #selector(ctxProperties))
        return m
    }
    @objc private func ctxRepeat() { if let l = model?.editor.lastCommand { model?.runCommand(l) } }
    @objc private func ctxUndo() { model?.editor.undo() }
    @objc private func ctxRedo() { model?.editor.redo() }
    @objc private func ctxDelete() { guard let model else { return }; if model.has("ERASE") { model.runCommand("ERASE") } else { model.deleteSelection() } }
    @objc private func ctxDeselect() { model?.editor.selection = [] }
    @objc private func ctxSelectAll() { model?.selectAll() }
    @objc private func ctxZoomExtents() { zoomExtents() }
    @objc private func ctxProperties() { model?.showPanels = true; model?.panelTab = .properties }

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
