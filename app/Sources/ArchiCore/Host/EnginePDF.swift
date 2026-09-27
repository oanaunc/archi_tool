// Oanarina Archi Tool — GPL-3.0-or-later
// Writers for the plotted pages of EnginePlot: vector PDF (ArchiApp/LayeredPDF.swift without Core Graphics: one
// optional content group per drawing layer when layered, standard Helvetica text that stays searchable, JPEG images,
// hyperlink annotations, bookmarks for published sheet sets, Flate-compressed content) and SVG (the Plot Preview and
// Windows printing show exactly these pages). Both serialise the same resolved page operations (`EnginePlotOp`).
import Foundation

/// One resolved drawing operation on a page, in PDF points (y up).
public enum EnginePlotOp {
    case stroke(points: [Vec2], closed: Bool, color: RGBA, width: Double, dash: [Double])
    case dot(center: Vec2, radius: Double, color: RGBA)
    case fill(loops: [[Vec2]], color: RGBA)
    /// Text lines: glyph matrix (a b c d) per line with its origin, font resource F1–F4 and size.
    case text(lines: [EngineTextLine], font: Int, size: Double, color: RGBA, underlines: [[Vec2]])
    /// Image placed by the matrix mapping the unit square to the page.
    case image(path: String, matrix: Transform2D)
    case clipBegin([Vec2])
    case clipEnd
    case layerBegin(String)
    case layerEnd
    case link(rect: BBox2, url: String)
}

public struct EngineTextLine {
    public var text: String
    public var matrix: Transform2D
}

/// A page ready to serialise.
public struct EngineResolvedPage {
    public var name: String
    public var width: Double    // points
    public var height: Double
    public var ops: [EnginePlotOp]
    public var bookmark: String?
}

public enum EnginePDF {
    /// Pseudo-layer of decorations that belong to no drawing layer (frame, title block, viewport captions).
    public static let sheetLayer = "Sheet"
    public static let fontNames = ["Helvetica", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica-BoldOblique"]

    // MARK: Fonts (Adobe Helvetica AFM widths, 1/1000 em, ASCII 32…126)

    static let helveticaBold: [Int] = [278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
                                       556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
                                       975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
                                       667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
                                       333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
                                       611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584]
    static func charWidth(_ u: UInt32, bold: Bool) -> Int {
        if (32...126).contains(u) { return bold ? helveticaBold[Int(u) - 32] : PDFWriter.helvetica[Int(u) - 32] }
        switch u {
        case 0x2014, 0x2026, 0x2030: return 1000
        case 0x2013, 0x20AC: return 556
        case 0x00B7, 0x2022: return bold ? 350 : 278
        case 0x00B0: return 400
        case 0x00D7, 0x00B1: return 584
        case 0x00A0: return 278
        case 0x2018, 0x2019: return bold ? 278 : 222
        case 0x201C, 0x201D: return bold ? 500 : 333
        default: return 556
        }
    }
    /// Width of a string in points at a font size.
    public static func width(_ s: String, size: Double, bold: Bool) -> Double {
        var w = 0
        for u in s.unicodeScalars { w += charWidth(u.value, bold: bold) }
        return Double(w) * size / 1000
    }

    /// WinAnsi (CP1252) bytes of a string; characters outside it become "?".
    static func winAnsi(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        for u in s.unicodeScalars {
            let v = u.value
            if (32...126).contains(v) || (160...255).contains(v) { out.append(UInt8(v)); continue }
            switch v {
            case 0x20AC: out.append(0x80)
            case 0x201A: out.append(0x82)
            case 0x201E: out.append(0x84)
            case 0x2026: out.append(0x85)
            case 0x2030: out.append(0x89)
            case 0x2018: out.append(0x91)
            case 0x2019: out.append(0x92)
            case 0x201C: out.append(0x93)
            case 0x201D: out.append(0x94)
            case 0x2022: out.append(0x95)
            case 0x2013: out.append(0x96)
            case 0x2014: out.append(0x97)
            case 0x2122: out.append(0x99)
            case 9: out.append(32)
            default: out.append(63)
            }
        }
        return out
    }

    // MARK: Resolving pages

    /// Resolves a plotted page into operations; `layered` groups them by drawing layer (optional content).
    public static func resolve(_ page: EnginePlotPage, doc: ArchiDocument, layered: Bool, layerOrder: [String]? = nil) -> EngineResolvedPage {
        let formats = EnginePlot.textFormats(doc)
        let layerOf = layerMap(doc)
        let links = hyperlinks(doc)
        var ops: [EnginePlotOp] = []
        var linked = Set<EntityID>()
        func emitPart(_ part: EnginePlotPart, _ filter: ((DrawEntry) -> Bool)?) {
            var body: [EnginePlotOp] = []
            // Entries outside the viewport are skipped, as PlotRenderer.draw(visible:) does on the Mac.
            let visible = part.clip.map { BBox2(points: $0) }
            for e in part.entries {
                if let f = filter, !f(e) { continue }
                if let v = visible, !e.bounds.isEmpty {
                    let a = part.renderer.point(e.bounds.min), b = part.renderer.point(e.bounds.max)
                    let c = part.renderer.point(Vec2(e.bounds.min.x, e.bounds.max.y)), d = part.renderer.point(Vec2(e.bounds.max.x, e.bounds.min.y))
                    let box = BBox2(points: [a, b, c, d])
                    let grown = BBox2(min: box.min - Vec2(2, 2), max: box.max + Vec2(2, 2))
                    if !grown.intersects(v) { continue }
                }
                var r = part.renderer.forEntry(e, formats: formats)
                r.document = doc
                for it in e.items { resolveItem(it, r, into: &body) }
                if let id = e.id, let url = links[id], !e.bounds.isEmpty, linked.insert(id).inserted {
                    let a = part.renderer.point(e.bounds.min), b = part.renderer.point(e.bounds.max)
                    body.append(.link(rect: BBox2(points: [a, b]), url: url))
                }
            }
            if body.isEmpty { return }
            if let c = part.clip { ops.append(.clipBegin(c)); ops += body; ops.append(.clipEnd) } else { ops += body }
        }
        if layered {
            let order = layerOrder ?? layers(of: [page], doc: doc)
            for layer in order {
                let start = ops.count
                ops.append(.layerBegin(layer))
                for part in page.parts { emitPart(part) { e in (e.id.flatMap { layerOf[$0] } ?? sheetLayer) == layer } }
                if ops.count == start + 1 { ops.removeLast() } else { ops.append(.layerEnd) }
            }
        } else {
            for part in page.parts { emitPart(part, nil) }
        }
        let k = EnginePlot.pointsPerMM
        return EngineResolvedPage(name: page.name, width: page.widthMM * k, height: page.heightMM * k, ops: ops, bookmark: page.bookmark)
    }

    /// Layers used by the pages: document order, then the others sorted (the sheet pseudo-layer among them).
    public static func layers(of pages: [EnginePlotPage], doc: ArchiDocument) -> [String] {
        let layerOf = layerMap(doc)
        var used = Set<String>()
        for p in pages { for part in p.parts { for e in part.entries { used.insert(e.id.flatMap { layerOf[$0] } ?? sheetLayer) } } }
        var order: [String] = []
        for l in doc.layers.map(\.name) where used.contains(l) && !order.contains(l) { order.append(l) }
        for u in used.sorted() where !order.contains(u) { order.append(u) }
        return order
    }

    static func layerMap(_ doc: ArchiDocument) -> [EntityID: String] {
        var m: [EntityID: String] = [:]
        for e in doc.entities { m[e.id] = e.layer }
        for e in doc.elements { m[e.id] = e.layer }
        for l in doc.layouts { for e in l.entities { m[e.id] = e.layer } }
        return m
    }
    static func hyperlinks(_ doc: ArchiDocument) -> [EntityID: String] {
        var m: [EntityID: String] = [:]
        for e in doc.entities { if let u = e.props["hyperlink"], !u.isEmpty { m[e.id] = u } }
        for e in doc.elements { if let u = e.props["hyperlink"], !u.isEmpty { m[e.id] = u } }
        for l in doc.layouts { for e in l.entities { if let u = e.props["hyperlink"], !u.isEmpty { m[e.id] = u } } }
        return m
    }

    static func resolveItem(_ item: DrawItem, _ r: EnginePlotRenderer, into ops: inout [EnginePlotOp]) {
        switch item {
        case .stroke(let pts, let closed, let style):
            guard let first = pts.first else { return }
            let c = r.color(style.color), w = r.width(style)
            if pts.count == 1 { ops.append(.dot(center: r.point(first), radius: w, color: c)); return }
            var dash: [Double] = []
            if !style.dash.isEmpty {
                let k = r.scaleFactor
                let lens = style.dash.map { $0 == 0 ? 0.01 : abs($0) * k }
                if lens.reduce(0, +) > 1.5 { dash = lens.count % 2 == 0 ? lens : lens + lens }
            }
            ops.append(.stroke(points: pts.map { r.point($0) }, closed: closed, color: c, width: w, dash: dash))
        case .fill(let loops, let color):
            let ls = loops.filter { $0.count >= 3 }.map { $0.map { r.point($0) } }
            if !ls.isEmpty { ops.append(.fill(loops: ls, color: r.color(color))) }
        case .text(let t, _, let color):
            if let op = textOp(t, r, color: r.color(color)) { ops.append(op) }
        case .image(let im):
            let o = r.point(im.origin), s = r.scaleFactor, a = im.rotation + r.rotation
            let w = im.size.x * s, h = im.size.y * s
            ops.append(.image(path: im.path, matrix: Transform2D(a: cos(a) * w, b: sin(a) * w, c: -sin(a) * h, d: cos(a) * h, tx: o.x, ty: o.y)))
        }
    }

    /// Helvetica text with the plot's cap-height sizing (0.718 em), alignment, wrapping, rotation, the text style's
    /// width factor and obliquing, and underlines (LayeredPDF.text).
    static func textOp(_ t: TextGeom, _ r: EnginePlotRenderer, color: RGBA) -> EnginePlotOp? {
        let h = t.height * r.scaleFactor
        guard h > 0.2, h < 20000, !t.content.isEmpty else { return nil }
        let size = h / 0.718
        let bold = r.textFormat?.bold ?? false, italic = r.textFormat?.italic ?? false
        let font = bold && italic ? 4 : (bold ? 2 : (italic ? 3 : 1))
        let paragraphs = t.content.replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
        var shape: TextStyleFonts.Shape? = nil
        if let d = r.document, !t.style.isEmpty {
            let s = TextStyleFonts.shape(t, doc: d)
            if !s.isPlain { shape = s }
        }
        let wf = shape?.widthFactor ?? 1, sl = tan(shape?.oblique ?? 0)
        let wrap = t.width * r.scaleFactor / max(wf, 0.01)
        var lines: [String] = []
        for para in paragraphs {
            guard wrap > 0 else { lines.append(para); continue }
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let cand = cur.isEmpty ? String(word) : cur + " " + word
                if !cur.isEmpty && width(cand, size: size, bold: bold) > wrap { lines.append(cur); cur = String(word) } else { cur = cand }
            }
            lines.append(cur)
        }
        let spacing = h * 1.6, n = Double(lines.count)
        let first: Double
        switch t.valign {
        case .baseline: first = lines.count > 1 && t.width > 0 ? -h : 0
        case .bottom: first = (n - 1) * spacing + h * 0.3
        case .middle: first = ((n - 1) * spacing) / 2 - h / 2
        case .top: first = -h
        }
        let o = r.point(t.position), a = t.rotation + r.rotation
        let ca = cos(a), sa = sin(a)
        var out: [EngineTextLine] = []
        var underlines: [[Vec2]] = []
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let w = width(line, size: size, bold: bold)
            let x: Double = t.halign == .left ? 0 : (t.halign == .center ? -w / 2 : -w)
            let y = first - Double(i) * spacing
            let lx = wf * x + sl * y
            let m = Transform2D(a: ca * wf, b: sa * wf, c: ca * sl - sa, d: sa * sl + ca, tx: o.x + ca * lx - sa * y, ty: o.y + sa * lx + ca * y)
            out.append(EngineTextLine(text: line, matrix: m))
            if r.textFormat?.underline == true {
                let uy = y - h * 0.2, uh = max(h * 0.07, 0.1)
                let corners = [Vec2(x, uy), Vec2(x + w, uy), Vec2(x + w, uy + uh), Vec2(x, uy + uh)]
                underlines.append(corners.map { p in
                    let gx = wf * p.x + sl * p.y
                    return Vec2(o.x + ca * gx - sa * p.y, o.y + sa * gx + ca * p.y)
                })
            }
        }
        if out.isEmpty { return nil }
        return .text(lines: out, font: font, size: size, color: color, underlines: underlines)
    }

    // MARK: PDF

    public struct Output {
        public var data: Data
        /// Uncompressed content stream of each page (tests).
        public var contents: [String]
        public var layers: [String]
        public var links: Int
        public var pages: Int
    }

    public static func num(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let m = Int64((v * 1000).rounded())
        if m % 1000 == 0 { return String(m / 1000) }
        let neg = m < 0
        let a = neg ? -m : m
        var f = String(a % 1000)
        while f.count < 3 { f = "0" + f }
        while f.hasSuffix("0") { f.removeLast() }
        return (neg ? "-" : "") + String(a / 1000) + "." + f
    }
    static func rgb(_ c: RGBA) -> String {
        num(max(0, min(1, c.r))) + " " + num(max(0, min(1, c.g))) + " " + num(max(0, min(1, c.b)))
    }
    static func hex(_ s: String) -> String {
        let digits = Array("0123456789ABCDEF")
        var out = ""
        for b in winAnsi(s) { out.append(digits[Int(b >> 4)]); out.append(digits[Int(b & 15)]) }
        return out
    }
    /// UTF-16BE text string with BOM (titles, layer names, bookmarks).
    static func pdfString(_ s: String) -> String {
        let digits = Array("0123456789ABCDEF")
        var out = "<FEFF"
        for u in s.utf16 {
            out.append(digits[Int(u >> 12 & 15)]); out.append(digits[Int(u >> 8 & 15)])
            out.append(digits[Int(u >> 4 & 15)]); out.append(digits[Int(u & 15)])
        }
        return out + ">"
    }
    /// ASCII literal (URIs): non-ASCII percent-encoded, delimiters escaped.
    static func asciiString(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "!#$&'()*+,/:;=?@[]~-._%").union(.alphanumerics)
        let a = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        let e = a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        return "(" + e + ")"
    }

    /// zlib stream (RFC 1950) around raw DEFLATE.
    static func zlib(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let z = RawDeflate.compress(data)
        guard !z.isEmpty else { return nil }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        var out = Data([0x78, 0x9C])
        out.append(z)
        out.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
        return out
    }

    /// Serialises resolved pages. `layers` names the optional content groups (layered PDF), `hidden` the ones off by
    /// default; `outline` adds bookmarks from the pages' bookmark titles.
    public static func write(_ pages: [EngineResolvedPage], title: String, author: String, layers: [String] = [], hidden: Set<String> = [],
                             outline: Bool = false, compress: Bool = true) -> Output {
        var objects: [Data] = []
        func reserve() -> Int { objects.append(Data()); return objects.count }
        func set(_ n: Int, _ s: String) { objects[n - 1] = Data(s.utf8) }
        func setData(_ n: Int, _ d: Data) { objects[n - 1] = d }
        let catalog = reserve(), pagesObj = reserve(), info = reserve()
        var fonts: [Int] = []
        for name in fontNames {
            let n = reserve()
            set(n, "<< /Type /Font /Subtype /Type1 /BaseFont /" + name + " /Encoding /WinAnsiEncoding >>")
            fonts.append(n)
        }
        var ocg: [String: Int] = [:]
        for l in layers {
            let n = reserve()
            ocg[l] = n
            set(n, "<< /Type /OCG /Name " + pdfString(l) + " >>")
        }
        var imageCache: [String: (Int, Bool)] = [:]
        func imageObject(_ path: String) -> Int? {
            if let c = imageCache[path] { return c.1 ? c.0 : nil }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let d = try? Data(contentsOf: url) else { imageCache[path] = (0, false); return nil }
            let n: Int
            if let (w, h) = PDFWriter.jpegSize(d) {
                n = reserve()
                var o = Data(("<< /Type /XObject /Subtype /Image /Width " + String(w) + " /Height " + String(h) + " /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " + String(d.count) + " >>\nstream\n").utf8)
                o.append(d); o.append(Data("\nendstream".utf8))
                setData(n, o)
            } else if let img = try? RasterImage.decode(d), img.width > 0, img.height > 0 {
                let raw = Data(img.gray)
                let z = zlib(raw) ?? raw
                n = reserve()
                let filter = z.count == raw.count ? "" : " /Filter /FlateDecode"
                var o = Data(("<< /Type /XObject /Subtype /Image /Width " + String(img.width) + " /Height " + String(img.height) + " /ColorSpace /DeviceGray /BitsPerComponent 8" + filter + " /Length " + String(z.count) + " >>\nstream\n").utf8)
                o.append(z); o.append(Data("\nendstream".utf8))
                setData(n, o)
            } else { imageCache[path] = (0, false); return nil }
            imageCache[path] = (n, true)
            return n
        }

        var pageRefs: [Int] = []
        var contents: [String] = []
        var linkCount = 0
        for page in pages {
            var gs: [Double: String] = [:]
            var images: [(String, Int)] = []
            var annots: [Int] = []
            var body = ""
            func alpha(_ a: Double) -> String {
                guard a < 0.999 else { return "" }
                let k = (a * 100).rounded() / 100
                if gs[k] == nil { gs[k] = "GS" + String(gs.count) }
                return "/" + (gs[k] ?? "GS0") + " gs "
            }
            for op in page.ops {
                switch op {
                case .stroke(let pts, let closed, let c, let w, let dash):
                    var s = "q " + alpha(c.a) + rgb(c) + " RG " + num(w) + " w 1 J 1 j "
                    if !dash.isEmpty { s += "[" + dash.map(num).joined(separator: " ") + "] 0 d 0 J " }
                    s += num(pts[0].x) + " " + num(pts[0].y) + " m"
                    for p in pts.dropFirst() { s += " " + num(p.x) + " " + num(p.y) + " l" }
                    s += closed ? " h S Q\n" : " S Q\n"
                    body += s
                case .dot(let q, let w, let c):
                    body += "q " + alpha(c.a) + rgb(c) + " rg " + num(q.x - w) + " " + num(q.y - w) + " " + num(2 * w) + " " + num(2 * w) + " re f Q\n"
                case .fill(let loops, let c):
                    var s = "q " + alpha(c.a) + rgb(c) + " rg"
                    for l in loops {
                        s += " " + num(l[0].x) + " " + num(l[0].y) + " m"
                        for p in l.dropFirst() { s += " " + num(p.x) + " " + num(p.y) + " l" }
                        s += " h"
                    }
                    body += s + " f* Q\n"
                case .text(let lines, let font, let size, let c, let unders):
                    var s = "q BT /F" + String(font) + " " + num(size) + " Tf " + rgb(c) + " rg\n"
                    for l in lines {
                        let m = l.matrix
                        s += num(m.a) + " " + num(m.b) + " " + num(m.c) + " " + num(m.d) + " " + num(m.tx) + " " + num(m.ty) + " Tm <" + hex(l.text) + "> Tj\n"
                    }
                    s += "ET\n"
                    if !unders.isEmpty {
                        s += rgb(c) + " rg\n"
                        for u in unders {
                            s += num(u[0].x) + " " + num(u[0].y) + " m " + u.dropFirst().map { num($0.x) + " " + num($0.y) + " l" }.joined(separator: " ") + " h f\n"
                        }
                    }
                    body += s + "Q\n"
                case .image(let path, let m):
                    guard let obj = imageObject(path) else { continue }
                    var name = ""
                    if let i = images.firstIndex(where: { $0.1 == obj }) { name = images[i].0 } else { name = "Im" + String(images.count); images.append((name, obj)) }
                    body += "q " + num(m.a) + " " + num(m.b) + " " + num(m.c) + " " + num(m.d) + " " + num(m.tx) + " " + num(m.ty) + " cm /" + name + " Do Q\n"
                case .clipBegin(let poly):
                    var s = "q " + num(poly[0].x) + " " + num(poly[0].y) + " m"
                    for p in poly.dropFirst() { s += " " + num(p.x) + " " + num(p.y) + " l" }
                    body += s + " h W n\n"
                case .clipEnd: body += "Q\n"
                case .layerBegin(let l):
                    let i = layers.firstIndex(of: l) ?? 0
                    body += "/OC /L" + String(i) + " BDC\n"
                case .layerEnd: body += "EMC\n"
                case .link(let rect, let url):
                    let n = reserve()
                    set(n, "<< /Type /Annot /Subtype /Link /Border [0 0 0] /Rect [" + num(rect.min.x) + " " + num(rect.min.y) + " " + num(rect.max.x) + " " + num(rect.max.y) + "] /A << /S /URI /URI " + asciiString(url) + " >> >>")
                    annots.append(n)
                    linkCount += 1
                }
            }
            contents.append(body)
            let stream = reserve()
            let raw = Data(body.utf8)
            if compress, let z = zlib(raw) {
                var d = Data(("<< /Length " + String(z.count) + " /Filter /FlateDecode >>\nstream\n").utf8); d.append(z); d.append(Data("\nendstream".utf8)); setData(stream, d)
            } else {
                var d = Data(("<< /Length " + String(raw.count) + " >>\nstream\n").utf8); d.append(raw); d.append(Data("\nendstream".utf8)); setData(stream, d)
            }
            var res = "/Font << /F1 " + String(fonts[0]) + " 0 R /F2 " + String(fonts[1]) + " 0 R /F3 " + String(fonts[2]) + " 0 R /F4 " + String(fonts[3]) + " 0 R >>"
            if !layers.isEmpty {
                var props: [String] = []
                for (i, l) in layers.enumerated() { props.append("/L" + String(i) + " " + String(ocg[l] ?? 0) + " 0 R") }
                res += " /Properties << " + props.joined(separator: " ") + " >>"
            }
            if !gs.isEmpty {
                let ext = gs.keys.sorted().map { "/" + (gs[$0] ?? "") + " << /Type /ExtGState /CA " + num($0) + " /ca " + num($0) + " >>" }
                res += " /ExtGState << " + ext.joined(separator: " ") + " >>"
            }
            if !images.isEmpty { res += " /XObject << " + images.map { "/" + $0.0 + " " + String($0.1) + " 0 R" }.joined(separator: " ") + " >>" }
            let p = reserve()
            var pageDict: String = "<< /Type /Page /Parent " + String(pagesObj) + " 0 R"
            pageDict += " /MediaBox [0 0 " + num(page.width) + " " + num(page.height) + "]"
            pageDict += " /Contents " + String(stream) + " 0 R"
            pageDict += " /Resources << " + res + " >>"
            if !annots.isEmpty { pageDict += " /Annots [" + annots.map { String($0) + " 0 R" }.joined(separator: " ") + "]" }
            set(p, pageDict + " >>")
            pageRefs.append(p)
        }
        set(pagesObj, "<< /Type /Pages /Kids [" + pageRefs.map { String($0) + " 0 R" }.joined(separator: " ") + "] /Count " + String(pageRefs.count) + " >>")
        var cat = "<< /Type /Catalog /Pages " + String(pagesObj) + " 0 R"
        if outline && !pages.isEmpty {
            let root = reserve()
            var items: [Int] = []
            for _ in pages { items.append(reserve()) }
            for (k, page) in pages.enumerated() {
                var d = "<< /Title " + pdfString(page.bookmark ?? page.name) + " /Parent " + String(root) + " 0 R /Dest [" + String(pageRefs[k]) + " 0 R /XYZ 0 " + num(page.height) + " null]"
                if k > 0 { d += " /Prev " + String(items[k - 1]) + " 0 R" }
                if k + 1 < items.count { d += " /Next " + String(items[k + 1]) + " 0 R" }
                set(items[k], d + " >>")
            }
            set(root, "<< /Type /Outlines /First " + String(items[0]) + " 0 R /Last " + String(items[items.count - 1]) + " 0 R /Count " + String(items.count) + " >>")
            cat += " /Outlines " + String(root) + " 0 R /PageMode /UseOutlines"
        }
        if !layers.isEmpty {
            let all = layers.map { String(ocg[$0] ?? 0) + " 0 R" }.joined(separator: " ")
            let on = layers.filter { !hidden.contains($0) }.map { String(ocg[$0] ?? 0) + " 0 R" }.joined(separator: " ")
            let off = layers.filter { hidden.contains($0) }.map { String(ocg[$0] ?? 0) + " 0 R" }.joined(separator: " ")
            if !outline { cat += " /PageMode /UseOC" }
            cat += " /OCProperties << /OCGs [" + all + "] /D << /Name (Layers) /Order [" + all + "] /ON [" + on + "] /OFF [" + off + "] >> >>"
        }
        set(catalog, cat + " >>")
        let producer = layers.isEmpty ? "Oanarina Archi Tool" : "Oanarina Archi Tool layered PDF"
        set(info, "<< /Title " + pdfString(title) + " /Creator (Oanarina Archi Tool) /Producer (" + producer + ") /Author " + pdfString(author) + " >>")

        var out = Data((layers.isEmpty ? "%PDF-1.4\n" : "%PDF-1.6\n").utf8)
        out.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data((String(i + 1) + " 0 obj\n").utf8)); out.append(o); out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var x = "xref\n0 " + String(objects.count + 1) + "\n0000000000 65535 f \n"
        for o in offsets {
            var s = String(o)
            while s.count < 10 { s = "0" + s }
            x += s + " 00000 n \n"
        }
        x += "trailer\n<< /Size " + String(objects.count + 1) + " /Root " + String(catalog) + " 0 R /Info " + String(info) + " 0 R >>\nstartxref\n" + String(xref) + "\n%%EOF\n"
        out.append(Data(x.utf8))
        return Output(data: out, contents: contents, layers: layers, links: linkCount, pages: pages.count)
    }

    /// Plotted pages as a PDF: plain (the Mac PLOT / PUBLISH) or layered (EXPORTPDF: one PDF layer per drawing layer).
    public static func document(_ pages: [EnginePlotPage], doc: ArchiDocument, title: String, layered: Bool, outline: Bool = false) -> Output {
        let order = layered ? layers(of: pages, doc: doc) : []
        let resolved = pages.map { resolve($0, doc: doc, layered: layered, layerOrder: order) }
        let hidden = Set(doc.layers.filter { !$0.visible }.map(\.name))
        return write(resolved, title: title, author: doc.info.author, layers: order, hidden: hidden, outline: outline)
    }
}

// MARK: - SVG pages (Plot Preview and Windows printing)

public enum EnginePlotSVG {
    static func esc(_ s: String) -> String {
        var o = ""
        for ch in s {
            switch ch {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default: o.append(ch)
            }
        }
        return o
    }
    static func color(_ c: RGBA) -> String {
        func h(_ v: Double) -> String {
            let n = Int((max(0, min(1, v)) * 255).rounded())
            let d = Array("0123456789abcdef")
            return String([d[n >> 4], d[n & 15]])
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    /// Coordinates in points to 0.01 pt (3.5 µm on paper).
    static func n(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let m = Int64((v * 100).rounded())
        if m % 100 == 0 { return String(m / 100) }
        let neg = m < 0
        let a = neg ? -m : m
        var f = String(a % 100)
        if f.count < 2 { f = "0" + f }
        if f.hasSuffix("0") { f.removeLast() }
        return (neg ? "-" : "") + String(a / 100) + "." + f
    }
    static func pathData(_ pts: [Vec2], closed: Bool) -> String {
        var s = "M" + n(pts[0].x) + " " + n(pts[0].y)
        for p in pts.dropFirst() { s += "L" + n(p.x) + " " + n(p.y) }
        return closed ? s + "Z" : s
    }
    /// File URL of an image path for the page (file:///C:/… on Windows).
    static func fileURL(_ path: String) -> String {
        let p = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: p).absoluteString
    }

    /// One page as a standalone SVG document, true size (millimetres), coordinates in points.
    public static func svg(_ page: EngineResolvedPage, background: Bool = true) -> String {
        let W = page.width, H = page.height
        let k = EnginePlot.pointsPerMM
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"" + n(W / k) + "mm\" height=\"" + n(H / k) + "mm\" viewBox=\"0 0 " + n(W) + " " + n(H) + "\">\n"
        if background { out += "<rect width=\"" + n(W) + "\" height=\"" + n(H) + "\" fill=\"#ffffff\"/>\n" }
        out += "<g transform=\"matrix(1 0 0 -1 0 " + n(H) + ")\">\n"
        var clipID = 0
        // Consecutive opaque single-outline fills of one colour share a path (grass, foliage and hatch dots of
        // elevations number in the hundreds of thousands); outlines of one item with holes keep the even-odd rule.
        var pendingFill = ""
        var pendingColor = ""
        func flushFill() {
            if !pendingFill.isEmpty { out += "<path d=\"" + pendingFill + "\" fill=\"" + pendingColor + "\"/>\n" }
            pendingFill = ""
        }
        for op in page.ops {
            if case .fill(let loops, let c) = op, loops.count == 1, c.a >= 0.999 {
                let col = color(c)
                if col != pendingColor { flushFill(); pendingColor = col }
                pendingFill += pathData(loops[0], closed: true)
                continue
            }
            flushFill()
            switch op {
            case .stroke(let pts, let closed, let c, let w, let dash):
                var s = "<path d=\"" + pathData(pts, closed: closed) + "\" fill=\"none\" stroke=\"" + color(c) + "\" stroke-width=\"" + n(w) + "\" stroke-linejoin=\"round\""
                if dash.isEmpty { s += " stroke-linecap=\"round\"" } else { s += " stroke-linecap=\"butt\" stroke-dasharray=\"" + dash.map(n).joined(separator: " ") + "\"" }
                if c.a < 0.999 { s += " stroke-opacity=\"" + n(c.a) + "\"" }
                out += s + "/>\n"
            case .dot(let q, let w, let c):
                out += "<rect x=\"" + n(q.x - w) + "\" y=\"" + n(q.y - w) + "\" width=\"" + n(2 * w) + "\" height=\"" + n(2 * w) + "\" fill=\"" + color(c) + "\"/>\n"
            case .fill(let loops, let c):
                var d = ""
                for l in loops { d += pathData(l, closed: true) }
                var s = "<path d=\"" + d + "\" fill=\"" + color(c) + "\" fill-rule=\"evenodd\""
                if c.a < 0.999 { s += " fill-opacity=\"" + n(c.a) + "\"" }
                out += s + "/>\n"
            case .text(let lines, let font, let size, let c, let unders):
                let weight = font == 2 || font == 4 ? " font-weight=\"bold\"" : ""
                let style = font == 3 || font == 4 ? " font-style=\"oblique\"" : ""
                for l in lines {
                    let m = l.matrix
                    out += "<text transform=\"matrix(" + n(m.a) + " " + n(m.b) + " " + n(-m.c) + " " + n(-m.d) + " " + n(m.tx) + " " + n(m.ty) + ")\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"" + n(size) + "\"" + weight + style + " fill=\"" + color(c) + "\" xml:space=\"preserve\">" + esc(l.text) + "</text>\n"
                }
                for u in unders { out += "<path d=\"" + pathData(u, closed: true) + "\" fill=\"" + color(c) + "\"/>\n" }
            case .image(let path, let m):
                out += "<image xlink:href=\"" + esc(fileURL(path)) + "\" href=\"" + esc(fileURL(path)) + "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" preserveAspectRatio=\"none\" transform=\"matrix(" + n(m.a) + " " + n(m.b) + " " + n(-m.c) + " " + n(-m.d) + " " + n(m.c + m.tx) + " " + n(m.d + m.ty) + ")\"/>\n"
            case .clipBegin(let poly):
                clipID += 1
                out += "<clipPath id=\"c" + String(clipID) + "\"><path d=\"" + pathData(poly, closed: true) + "\"/></clipPath><g clip-path=\"url(#c" + String(clipID) + ")\">\n"
            case .clipEnd: out += "</g>\n"
            case .layerBegin(let l): out += "<g data-layer=\"" + esc(l) + "\">\n"
            case .layerEnd: out += "</g>\n"
            case .link: break
            }
        }
        flushFill()
        return out + "</g>\n</svg>\n"
    }
}
