// Oanarina Archi Tool — GPL-3.0-or-later
// Portable raster output (Foundation only): an RGBA image with a PNG encoder (RawDeflate), and a software rasteriser
// of the resolved 2D draw list — antialiased even-odd fills, polylines with plotted lineweights, round joins and
// dashes, text drawn with the stroke font (bold, italic, underline, strike-through), grayscale images.
// EXPORT PNG and file.export png use it in archi-engine (Windows, Linux); the Mac app draws the same draw list with
// Core Graphics (FileController.renderPNG). Both use its framing: the current level on white paper with a 3 % margin,
// 300 dpi at 1:100 for millimetre drawings, 1600-9000 pixels on the long side, lineweights at 300/25.4 px per mm.
import Foundation

/// 8-bit RGBA image, top row first.
public struct RGBAImage: Hashable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]
    /// Resolution written to the PNG (pHYs), dots per inch.
    public var dpi: Double = 72

    public init(width: Int, height: Int, background: RGBA = .white) {
        self.width = max(1, width)
        self.height = max(1, height)
        let r = RGBAImage.byte(background.r), g = RGBAImage.byte(background.g)
        let b = RGBAImage.byte(background.b), a = RGBAImage.byte(background.a)
        var p = [UInt8](repeating: 0, count: self.width * self.height * 4)
        var i = 0
        while i < p.count {
            p[i] = r; p[i + 1] = g; p[i + 2] = b; p[i + 3] = a
            i += 4
        }
        pixels = p
    }

    static func byte(_ v: Double) -> UInt8 {
        let s = (max(0, min(1, v)) * 255).rounded()
        return UInt8(s)
    }

    /// Colour of a pixel (0…1 channels).
    public func pixel(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return RGBA(0, 0, 0, 0) }
        let i = (y * width + x) * 4
        let k = 1.0 / 255
        return RGBA(Double(pixels[i]) * k, Double(pixels[i + 1]) * k, Double(pixels[i + 2]) * k, Double(pixels[i + 3]) * k)
    }

    /// Source-over blend of colour `c` with coverage `cov` (0…1) at pixel index `idx` (x + y·width).
    @inline(__always) mutating func blend(_ idx: Int, _ c: RGBA, _ cov: Double) {
        let a = max(0, min(1, cov * c.a))
        if a <= 0.001 { return }
        let i = idx * 4
        let inv = 1 - a
        let r = Double(pixels[i]) * inv + c.r * 255 * a
        let g = Double(pixels[i + 1]) * inv + c.g * 255 * a
        let b = Double(pixels[i + 2]) * inv + c.b * 255 * a
        let al = Double(pixels[i + 3]) * inv + 255 * a
        pixels[i] = UInt8(max(0, min(255, r.rounded())))
        pixels[i + 1] = UInt8(max(0, min(255, g.rounded())))
        pixels[i + 2] = UInt8(max(0, min(255, b.rounded())))
        pixels[i + 3] = UInt8(max(0, min(255, al.rounded())))
    }

    /// Whether every pixel is opaque (the PNG is then written as RGB).
    public var isOpaque: Bool {
        var i = 3
        while i < pixels.count {
            if pixels[i] != 255 { return false }
            i += 4
        }
        return true
    }

    /// PNG file: 8-bit RGB when opaque (or `alpha` false), RGBA otherwise; pHYs carries `dpi`.
    public func pngData(alpha: Bool? = nil) -> Data {
        let withAlpha = alpha ?? !isOpaque
        let channels = withAlpha ? 4 : 3
        var raw: [UInt8] = []
        raw.reserveCapacity((width * channels + 1) * height)
        for y in 0..<height {
            raw.append(0)
            let row = y * width * 4
            if withAlpha {
                raw.append(contentsOf: pixels[row..<(row + width * 4)])
            } else {
                var i = row
                for _ in 0..<width {
                    raw.append(pixels[i]); raw.append(pixels[i + 1]); raw.append(pixels[i + 2])
                    i += 4
                }
            }
        }
        var a: UInt32 = 1, bb: UInt32 = 0
        for x in raw {
            a = (a + UInt32(x)) % 65521
            bb = (bb + a) % 65521
        }
        let deflated = [UInt8](RawDeflate.compress(Data(raw)))
        let adler: [UInt8] = [UInt8(bb >> 8), UInt8(bb & 0xFF), UInt8(a >> 8), UInt8(a & 0xFF)]
        let z: [UInt8] = [0x78, 0x9C] + deflated + adler
        func be(_ v: Int) -> [UInt8] {
            [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }
        func chunk(_ t: String, _ d: [UInt8]) -> [UInt8] {
            let td = Array(t.utf8) + d
            let c = RasterImage.crc(td)
            return be(d.count) + td + be(Int(c))
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let colorType: UInt8 = withAlpha ? 6 : 2
        out += chunk("IHDR", be(width) + be(height) + [8, colorType, 0, 0, 0])
        if dpi > 0 {
            let ppm = Int((dpi / 0.0254).rounded())
            out += chunk("pHYs", be(ppm) + be(ppm) + [1])
        }
        out += chunk("IDAT", z)
        out += chunk("IEND", [])
        return Data(out)
    }

    /// Reads back an 8-bit RGB / RGBA / gray PNG written without interlacing (tests, round trips).
    public static func decodePNG(_ data: Data) throws -> RGBAImage {
        let b = [UInt8](data)
        struct Bad: Error {}
        guard b.count > 33, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 else { throw Bad() }
        func u32(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
        var i = 8, w = 0, h = 0, ct = 0
        var idat: [UInt8] = []
        while i + 8 <= b.count {
            let n = u32(i)
            let t = String(bytes: b[(i + 4)..<(i + 8)], encoding: .ascii) ?? ""
            let d = i + 8
            guard d + n <= b.count else { break }
            if t == "IHDR" { w = u32(d); h = u32(d + 4); ct = Int(b[d + 9]); guard b[d + 8] == 8 else { throw Bad() } }
            if t == "IDAT" { idat += b[d..<(d + n)] }
            i = d + n + 4
        }
        guard w > 0, h > 0, idat.count > 6 else { throw Bad() }
        let raw = [UInt8](try RawDeflate.decompress(Data(idat[2...])))
        let ch = ct == 6 ? 4 : ct == 2 ? 3 : ct == 4 ? 2 : 1
        let stride = w * ch
        guard raw.count >= (stride + 1) * h else { throw Bad() }
        var img = RGBAImage(width: w, height: h)
        var prev = [UInt8](repeating: 0, count: stride)
        for y in 0..<h {
            let f = raw[y * (stride + 1)]
            var line = Array(raw[(y * (stride + 1) + 1)..<((y + 1) * (stride + 1))])
            for x in 0..<stride {
                let left = x >= ch ? Int(line[x - ch]) : 0
                let up = Int(prev[x])
                let ul = x >= ch ? Int(prev[x - ch]) : 0
                var v = Int(line[x])
                switch f {
                case 1: v += left
                case 2: v += up
                case 3: v += (left + up) / 2
                case 4:
                    let p = left + up - ul
                    let pa = abs(p - left), pb = abs(p - up), pc = abs(p - ul)
                    v += pa <= pb && pa <= pc ? left : (pb <= pc ? up : ul)
                default: break
                }
                line[x] = UInt8(v & 0xFF)
            }
            prev = line
            for x in 0..<w {
                let o = (y * w + x) * 4
                let s = x * ch
                if ch >= 3 {
                    img.pixels[o] = line[s]; img.pixels[o + 1] = line[s + 1]; img.pixels[o + 2] = line[s + 2]
                    img.pixels[o + 3] = ch == 4 ? line[s + 3] : 255
                } else {
                    img.pixels[o] = line[s]; img.pixels[o + 1] = line[s]; img.pixels[o + 2] = line[s]
                    img.pixels[o + 3] = ch == 2 ? line[s + 1] : 255
                }
            }
        }
        return img
    }
}

/// Whole-text formatting used by the rasteriser (entity props, as the canvas and the PDF writer read them).
public struct RasterTextFormat: Hashable {
    public var bold = false, italic = false, underline = false, strike = false
    public init(bold: Bool = false, italic: Bool = false, underline: Bool = false, strike: Bool = false) {
        self.bold = bold; self.italic = italic; self.underline = underline; self.strike = strike
    }
}

/// Software rasteriser of draw items into an RGBAImage. World → pixel: px = (x − origin.x)·scale, py = (origin.y − y)·scale.
public struct DrawRaster {
    public var image: RGBAImage
    /// World point at the top-left corner of the image.
    public var origin: Vec2
    /// Pixels per drawing unit.
    public var scale: Double
    /// Pixels per plotted millimetre of lineweight, and the width limits in pixels (RenderParams on the Mac).
    public var lineweightScale = 300 / 25.4
    public var minWidth = 1.0
    public var maxWidth = 80.0
    /// Vertical samples per pixel row (antialiasing).
    public var subsamples = 4
    /// Text styles of the drawing (width factor and oblique angle) and per-object text formatting.
    public var textStyles: [TextStyle] = []
    public var textFormats: [EntityID: RasterTextFormat] = [:]
    /// Folder relative image paths resolve against.
    public var imageBase: URL?

    public init(image: RGBAImage, origin: Vec2, scale: Double) {
        self.image = image; self.origin = origin; self.scale = scale
    }

    @inline(__always) func px(_ p: Vec2) -> Vec2 { Vec2((p.x - origin.x) * scale, (origin.y - p.y) * scale) }

    // MARK: Fills

    struct Edge { var x0: Double; var y0: Double; var x1: Double; var y1: Double; var dir: Int }

    /// Fills pixel-space loops (even-odd, or non-zero winding) with antialiased coverage.
    public mutating func fillPixels(_ loops: [[Vec2]], _ c: RGBA, evenOdd: Bool = true) {
        var edges: [Edge] = []
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for l in loops where l.count > 2 {
            for k in 0..<l.count {
                let a = l[k], b = l[(k + 1) % l.count]
                minX = min(minX, a.x); maxX = max(maxX, a.x); minY = min(minY, a.y); maxY = max(maxY, a.y)
                if a.y == b.y || !a.y.isFinite || !b.y.isFinite || !a.x.isFinite || !b.x.isFinite { continue }
                if a.y < b.y { edges.append(Edge(x0: a.x, y0: a.y, x1: b.x, y1: b.y, dir: 1)) }
                else { edges.append(Edge(x0: b.x, y0: b.y, x1: a.x, y1: a.y, dir: -1)) }
            }
        }
        guard !edges.isEmpty else { return }
        let w = image.width, h = image.height
        let x0 = max(0, Int(minX.rounded(.down))), x1 = min(w - 1, Int(maxX.rounded(.up)))
        let y0 = max(0, Int(minY.rounded(.down))), y1 = min(h - 1, Int(maxY.rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return }
        edges.sort { $0.y0 < $1.y0 }
        let span = x1 - x0 + 1
        var cover = [Double](repeating: 0, count: span + 1)
        var active: [Int] = []
        var next = 0
        let n = max(1, subsamples)
        let weight = 1.0 / Double(n)
        var xs: [(Double, Int)] = []
        for row in y0...y1 {
            var lo = Int.max, hi = -1
            for s in 0..<n {
                let sy = Double(row) + (Double(s) + 0.5) * weight
                while next < edges.count && edges[next].y0 <= sy { active.append(next); next += 1 }
                active.removeAll { edges[$0].y1 <= sy }
                xs.removeAll(keepingCapacity: true)
                for ei in active {
                    let e = edges[ei]
                    if sy < e.y0 { continue }
                    let t = (sy - e.y0) / (e.y1 - e.y0)
                    xs.append((e.x0 + (e.x1 - e.x0) * t, e.dir))
                }
                if xs.count < 2 { continue }
                xs.sort { $0.0 < $1.0 }
                var wind = 0
                for k in 0..<(xs.count - 1) {
                    wind += evenOdd ? 1 : xs[k].1
                    let inside = evenOdd ? (wind % 2 != 0) : (wind != 0)
                    if !inside { continue }
                    let a = max(Double(x0), xs[k].0) - Double(x0)
                    let b = min(Double(x1 + 1), xs[k + 1].0) - Double(x0)
                    if b <= a { continue }
                    let ia = Int(a), ib = Int(b)
                    lo = min(lo, ia); hi = max(hi, min(ib, span - 1))
                    if ia == ib { cover[ia] += (b - a) * weight; continue }
                    cover[ia] += (Double(ia + 1) - a) * weight
                    if ib > ia + 1 { for q in (ia + 1)..<ib { cover[q] += weight } }
                    if ib < cover.count { cover[ib] += (b - Double(ib)) * weight }
                }
            }
            if hi < lo { continue }
            let base = row * w + x0
            for k in lo...hi {
                if cover[k] > 0.002 { image.blend(base + k, c, min(1, cover[k])) }
                cover[k] = 0
            }
            if hi + 1 < cover.count { cover[hi + 1] = 0 }
        }
    }

    /// Fills world-space loops (even-odd rule, as the draw list and the Mac canvas).
    public mutating func fill(_ loops: [[Vec2]], _ c: RGBA) {
        fillPixels(loops.map { $0.map(px) }, c)
    }

    // MARK: Strokes

    /// Line width in pixels of a plotted lineweight (0 = hairline = the minimum width).
    public func width(_ lineweight: Double) -> Double { min(maxWidth, max(minWidth, lineweight * lineweightScale)) }

    /// Strokes a pixel-space polyline of width `w` (butt ends, round joins) as one non-zero fill.
    public mutating func strokePixels(_ pts: [Vec2], closed: Bool, width w: Double, _ c: RGBA) {
        guard pts.count > 1 else {
            if let p = pts.first { fillPixels([circle(p, max(w, 1.5) / 2)], c, evenOdd: false) }
            return
        }
        let hw = max(w, 0.5) / 2
        var loops: [[Vec2]] = []
        let segs = closed ? pts.count : pts.count - 1
        for k in 0..<segs {
            let a = pts[k], b = pts[(k + 1) % pts.count]
            let d = b - a
            let len = (d.x * d.x + d.y * d.y).squareRoot()
            if len < 1e-9 { continue }
            let nx = -d.y / len * hw, ny = d.x / len * hw
            loops.append([Vec2(a.x + nx, a.y + ny), Vec2(a.x - nx, a.y - ny), Vec2(b.x - nx, b.y - ny), Vec2(b.x + nx, b.y + ny)])
        }
        if w > 2.5 {
            let joins = closed ? pts : Array(pts.dropFirst().dropLast())
            for p in joins { loops.append(circle(p, hw)) }
        }
        // Consistent orientation so overlapping pieces add up under the non-zero rule.
        loops = loops.map { GeometryOps.signedArea($0) < 0 ? Array($0.reversed()) : $0 }
        fillPixels(loops, c, evenOdd: false)
    }

    func circle(_ p: Vec2, _ r: Double) -> [Vec2] {
        let n = max(8, min(48, Int(r * 2)))
        return (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * Double.pi
            return Vec2(p.x + cos(a) * r, p.y + sin(a) * r)
        }
    }

    /// Dash pieces of a world polyline (positive dash, negative gap, 0 dot), in world units.
    static func dashed(_ pts: [Vec2], closed: Bool, pattern: [Double], dot: Double) -> [[Vec2]] {
        let total = pattern.reduce(0) { $0 + abs($1) }
        guard total > 0 else { return [pts] }
        var path = pts
        if closed, let f = pts.first { path.append(f) }
        var out: [[Vec2]] = []
        var pi = 0
        var left = pattern[0] == 0 ? dot : abs(pattern[0])
        var on = pattern[0] >= 0
        var cur: [Vec2] = []
        for k in 0..<max(0, path.count - 1) {
            var a = path[k]
            let b = path[k + 1]
            var segLen = a.distance(to: b)
            if segLen < 1e-12 { continue }
            let dir = (b - a) / segLen
            if on && cur.isEmpty { cur = [a] }
            while segLen > 1e-12 {
                if left > segLen {
                    left -= segLen
                    if on { cur.append(b) }
                    break
                }
                let p = a + dir * left
                segLen -= left
                a = p
                if on {
                    cur.append(p)
                    out.append(cur)
                    cur = []
                    if out.count > 200_000 { return out }
                }
                pi = (pi + 1) % pattern.count
                let v = pattern[pi]
                on = v >= 0
                left = v == 0 ? dot : abs(v)
                if on { cur = [a] }
            }
        }
        if on && cur.count > 1 { out.append(cur) }
        return out
    }

    public mutating func stroke(_ pts: [Vec2], closed: Bool, style: StrokeStyle) {
        let w = width(style.lineweight)
        let total = style.dash.reduce(0) { $0 + abs($1) }
        // Patterns shorter than ~3 px draw continuous (as the canvas does when zoomed out).
        if style.dash.isEmpty || total * scale < 3 {
            strokePixels(pts.map(px), closed: closed, width: w, style.color)
            return
        }
        let dot = max(w / scale, 1 / scale)
        for piece in DrawRaster.dashed(pts, closed: closed, pattern: style.dash, dot: dot) {
            strokePixels(piece.map(px), closed: false, width: w, style.color)
        }
    }

    // MARK: Text

    /// Draws text with the stroke font: style width factor and oblique angle, bold (heavier strokes), italic (12° slant),
    /// underline and strike-through lines per text line.
    public mutating func text(_ t: TextGeom, color: RGBA, format: RasterTextFormat? = nil) {
        guard t.height > 0, !t.content.isEmpty else { return }
        let f = format ?? RasterTextFormat()
        let st = textStyles.first { $0.name.caseInsensitiveCompare(t.style) == .orderedSame }
        let wf = st.map(TextStyleFonts.widthFactor) ?? 1
        var ob = st.map(TextStyleFonts.obliqueRadians) ?? 0
        if f.italic { ob += 12 * Double.pi / 180 }
        let hPx = t.height * scale
        if hPx < 1.5 {
            // Greeked like the canvas: a faint bar.
            let c = RGBA(color.r, color.g, color.b, color.a * 0.35)
            strokePixels([px(t.position), px(t.position + Vec2(cos(t.rotation), sin(t.rotation)) * t.height * 3)], closed: false, width: max(1, hPx), c)
            return
        }
        let factor = f.bold ? 0.15 : 0.09
        let w = max(1, hPx * factor)
        for s in StrokeFont.strokes(t, widthFactor: wf, oblique: ob) { strokePixels(s.map(px), closed: false, width: w, color) }
        if f.underline || f.strike {
            for l in DrawRaster.decorationLines(t, widthFactor: wf, underline: f.underline, strike: f.strike) {
                strokePixels(l.map(px), closed: false, width: max(1, hPx * 0.07), color)
            }
        }
    }

    /// Underline / strike-through segments of each line of a text object (the StrokeFont layout).
    public static func decorationLines(_ t: TextGeom, widthFactor: Double, underline: Bool, strike: Bool) -> [[Vec2]] {
        let k = t.height / StrokeFont.capHeight
        let wf = widthFactor > 0 ? widthFactor : 1
        let ls = StrokeFont.lines(t, widthFactor: wf)
        let n = Double(ls.count)
        let pitch = t.height * StrokeFont.lineSpacing
        let block = t.height + (n - 1) * pitch
        let y0: Double
        switch t.valign {
        case .baseline: y0 = 0
        case .bottom: y0 = (n - 1) * pitch + 3 * k
        case .middle: y0 = block / 2 - t.height
        case .top: y0 = -t.height
        }
        let rot = Transform2D.rotation(t.rotation)
        var out: [[Vec2]] = []
        for (li, line) in ls.enumerated() where !line.isEmpty {
            let w = StrokeFont.lineWidth(line) * k * wf
            var x: Double
            switch t.halign { case .left: x = 0; case .center: x = -w / 2; case .right: x = -w }
            let by = y0 - Double(li) * pitch
            var ys: [Double] = []
            if underline { ys.append(by - t.height * 0.2) }
            if strike { ys.append(by + t.height * 0.45) }
            for y in ys {
                let a = t.position + rot.applyVector(Vec2(x, y))
                let b = t.position + rot.applyVector(Vec2(x + w, y))
                out.append([a, b])
            }
        }
        return out
    }

    // MARK: Images

    /// Grayscale raster images (PNG, BMP, PNM: RasterImage), nearest sample, rotated about their origin.
    public mutating func image(_ im: ImageGeom) {
        let path = (im.path as NSString).expandingTildeInPath
        let url = PathSupport.isAbsolute(path) ? URL(fileURLWithPath: path) : (imageBase?.appendingPathComponent(path) ?? URL(fileURLWithPath: path))
        guard let d = try? Data(contentsOf: url), let r = try? RasterImage.decode(d), r.width > 0, r.height > 0 else { return }
        let ca = cos(im.rotation), sa = sin(im.rotation)
        let corners = [Vec2(0, 0), Vec2(im.size.x, 0), Vec2(im.size.x, im.size.y), Vec2(0, im.size.y)].map { v in
            px(im.origin + Vec2(v.x * ca - v.y * sa, v.x * sa + v.y * ca))
        }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let x0 = max(0, Int((xs.min() ?? 0).rounded(.down))), x1 = min(image.width - 1, Int((xs.max() ?? 0).rounded(.up)))
        let y0 = max(0, Int((ys.min() ?? 0).rounded(.down))), y1 = min(image.height - 1, Int((ys.max() ?? 0).rounded(.up)))
        guard x0 <= x1, y0 <= y1, im.size.x > 0, im.size.y > 0 else { return }
        for y in y0...y1 {
            for x in x0...x1 {
                let wx = origin.x + (Double(x) + 0.5) / scale - im.origin.x
                let wy = origin.y - (Double(y) + 0.5) / scale - im.origin.y
                let u = (wx * ca + wy * sa) / im.size.x
                let v = (-wx * sa + wy * ca) / im.size.y
                if u < 0 || u >= 1 || v < 0 || v >= 1 { continue }
                let sx = min(r.width - 1, Int(u * Double(r.width)))
                let sy = min(r.height - 1, Int((1 - v) * Double(r.height)))
                let g = Double(r.gray[sy * r.width + sx]) / 255
                image.blend(y * image.width + x, RGBA(g, g, g), 1)
            }
        }
    }

    // MARK: Draw list

    /// Paints entries in the Mac order per entry (fills, strokes, text, images).
    public mutating func draw(_ entries: [DrawEntry]) {
        for e in entries {
            for it in e.items { if case .fill(let loops, let c) = it { fill(loops, c) } }
            for it in e.items { if case .stroke(let p, let closed, let st) = it { stroke(p, closed: closed, style: st) } }
            for it in e.items {
                if case .text(let t, _, let c) = it { text(t, color: c, format: e.id.flatMap { textFormats[$0] }) }
            }
            for it in e.items { if case .image(let im) = it { image(im) } }
        }
    }
}

/// Plan image export (EXPORT PNG, file.export png): FileController.renderPNG of the Mac app without Core Graphics.
public enum PlanImageExport {
    public struct Empty: Error, LocalizedError { public var errorDescription: String? { "The drawing is empty." } }

    /// Per-object text formatting from entity props (bold / italic / underline / strike, or the MTEXT codes).
    public static func textFormats(_ doc: ArchiDocument) -> [EntityID: RasterTextFormat] {
        var m: [EntityID: RasterTextFormat] = [:]
        for e in doc.entities {
            guard case .text = e.geometry else { continue }
            if let f = format(e.props) { m[e.id] = f }
        }
        return m
    }

    public static func format(_ props: [String: String]) -> RasterTextFormat? {
        var f = RasterTextFormat(bold: props["bold"] == "1", italic: props["italic"] == "1", underline: props["underline"] == "1", strike: props["strike"] == "1")
        if let raw = props["mtext"], !f.strike { f.strike = MTextFormatting.leading(raw).strike }
        return f == RasterTextFormat() ? nil : f
    }

    /// Bounds of the entries including text extents.
    static func bounds(_ entries: [DrawEntry]) -> BBox2 {
        var b = BBox2.empty
        for e in entries {
            b = b.union(e.bounds)
            for it in e.items {
                guard case .text(let t, _, _) = it else { continue }
                for s in StrokeFont.strokes(t) { for p in s { b.add(p) } }
            }
        }
        return b
    }

    /// Renders a level (default the current one) on white paper at `dpi` for a 1:100 plot of a millimetre drawing.
    public static func render(doc: ArchiDocument, level: Int? = nil, dpi: Double = 300, imageBase: URL? = nil) throws -> RGBAImage {
        var opts = DrawOptions(level: level ?? doc.currentLevel)
        opts.forPaper = true
        let entries = DrawListBuilder.entries(doc: doc, options: opts)
        let raw = bounds(entries)
        guard !raw.isEmpty, raw.width.isFinite, raw.height.isFinite else { throw Empty() }
        let margin = max(raw.width, raw.height) * 0.03
        let b = raw.expanded(by: margin)
        let extent = max(b.width, b.height, 1e-9)
        let paperMM = extent * doc.units.mm / 100
        let longPx = min(9000, max(1600, paperMM / 25.4 * dpi))
        let ppu = longPx / extent
        let w = max(1, Int((b.width * ppu).rounded(.up)))
        let h = max(1, Int((b.height * ppu).rounded(.up)))
        var img = RGBAImage(width: w, height: h)
        img.dpi = dpi
        var r = DrawRaster(image: img, origin: Vec2(b.min.x, b.max.y), scale: ppu)
        r.lineweightScale = dpi / 25.4
        r.textStyles = doc.textStyles
        r.textFormats = textFormats(doc)
        r.imageBase = imageBase
        r.draw(entries)
        return r.image
    }

    /// Writes the PNG; returns its pixel size.
    @discardableResult
    public static func write(doc: ArchiDocument, level: Int? = nil, to url: URL, dpi: Double = 300, imageBase: URL? = nil) throws -> (width: Int, height: Int) {
        let img = try render(doc: doc, level: level, dpi: dpi, imageBase: imageBase)
        try img.pngData(alpha: false).write(to: url, options: .atomic)
        return (img.width, img.height)
    }
}
