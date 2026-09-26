// Oanarina Archi Tool — GPL-3.0-or-later
// Headless vector PDF output (ISO 32000-1, PDF 1.4 subset) of plans and sheets, written from the resolved draw list
// (DrawEntry) without Core Graphics, so archi-cli, batch jobs, automation rules, MCP exports and Shortcuts shell
// actions can plot. Sheets are plotted at true scale on their paper (viewports clipped, paper-space annotation, title
// block); a plan without sheets is plotted on A3 at the largest standard scale that fits. Lines keep their plotted
// line weights and dash patterns, fills use the even-odd rule, text uses the standard Helvetica fonts (WinAnsi
// encoding; characters outside it print as "?"), JPEG images are embedded, other images are framed.
import Foundation

public enum PDFWriter {
    /// Points per millimetre.
    static let k = 72.0 / 25.4
    /// Standard plot scales (1:n) tried when fitting a plan.
    public static let standardScales: [Double] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 1250, 2000, 2500, 5000, 10000, 20000, 50000]

    /// One page: its size in millimetres and the drawing operations.
    public struct Page {
        public var width: Double, height: Double
        var ops = ""
        var images: [(name: String, data: Data, width: Int, height: Int)] = []
        public init(width: Double, height: Double) { self.width = width; self.height = height }
    }

    /// Maps drawing units to paper millimetres: paper = (model - center) / scale + paperCenter.
    struct Frame {
        var center: Vec2, scale: Double, paperCenter: Vec2
        func pt(_ p: Vec2) -> (Double, Double) {
            let q = (p - center) / scale + paperCenter
            return (q.x * PDFWriter.k, q.y * PDFWriter.k)
        }
    }

    static func n(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        var s = String(format: "%.3f", v)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) { s.removeLast() }
        return s == "-0" ? "0" : s
    }
    static func rgb(_ c: RGBA) -> String { "\(n(max(0, min(1, c.r)))) \(n(max(0, min(1, c.g)))) \(n(max(0, min(1, c.b))))" }

    /// Helvetica advance widths (1/1000 em) for ASCII 32…126 (Adobe AFM).
    static let helvetica: [Int] = [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
                                   556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
                                   1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
                                   667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
                                   333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
                                   556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584]
    /// Width of a string in em (Helvetica).
    public static func textWidth(_ s: String) -> Double {
        var w = 0
        for u in s.unicodeScalars { w += (32...126).contains(u.value) ? helvetica[Int(u.value) - 32] : 556 }
        return Double(w) / 1000
    }
    /// PDF literal string in WinAnsi encoding.
    static func literal(_ s: String) -> String {
        var out = "("
        for u in s.unicodeScalars {
            switch u.value {
            case 40, 41, 92: out += "\\" + String(Character(u))
            case 32...126: out.unicodeScalars.append(u)
            case 160...255: out += String(format: "\\%03o", u.value)
            case 0x20AC: out += "\\200"
            case 0x2013: out += "\\226"
            case 0x2014: out += "\\227"
            case 0x2018: out += "\\221"
            case 0x2019: out += "\\222"
            case 0x201C: out += "\\223"
            case 0x201D: out += "\\224"
            case 0x2022: out += "\\225"
            default: out += "?"
            }
        }
        return out + ")"
    }

    /// Adds draw entries to a page through `frame`.
    static func draw(_ entries: [DrawEntry], frame f: Frame, into page: inout Page, lineweightScale: Double = 1, clip: BBox2? = nil) {
        var o = ""
        for e in entries {
            if let c = clip, !e.bounds.isEmpty, !e.bounds.intersects(c) { continue }
            for it in e.items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    guard !pts.isEmpty else { continue }
                    o += "\(rgb(st.color)) RG \(n(max(0.1, st.lineweight * k * lineweightScale))) w "
                    if !st.dash.isEmpty, st.dash.contains(where: { $0 != 0 }) {
                        var vals = st.dash.map { $0 == 0 ? 0.1 : abs($0) / f.scale * k }
                        if let d0 = st.dash.first, d0 < 0 { vals = Array(vals.dropFirst()) + [vals[0]] }
                        o += "[" + vals.map(n).joined(separator: " ") + "] 0 d "
                    } else { o += "[] 0 d " }
                    let p0 = f.pt(pts[0])
                    o += "\(n(p0.0)) \(n(p0.1)) m "
                    if pts.count == 1 { o += "\(n(p0.0 + 0.01)) \(n(p0.1)) l " }
                    for p in pts.dropFirst() { let q = f.pt(p); o += "\(n(q.0)) \(n(q.1)) l " }
                    o += closed ? "s\n" : "S\n"
                case .fill(let loops, let color):
                    var path = ""
                    for l in loops where l.count >= 3 {
                        for (i, p) in l.enumerated() { let q = f.pt(p); path += "\(n(q.0)) \(n(q.1)) \(i == 0 ? "m" : "l") " }
                        path += "h "
                    }
                    guard !path.isEmpty else { continue }
                    o += "\(rgb(color)) rg " + path + "f*\n"
                case .text(let t, _, let color):
                    o += text(t, color: color, frame: f)
                case .image(let im):
                    let corners = [Vec2(0, 0), Vec2(im.size.x, 0), im.size, Vec2(0, im.size.y)].map { im.origin + $0.rotated(by: im.rotation) }
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: im.path)), let px = jpegSize(data) {
                        let name = "Im\(page.images.count + 1)"
                        page.images.append((name, data, px.0, px.1))
                        let a = f.pt(corners[0]), b = f.pt(corners[1]), d = f.pt(corners[3])
                        o += "q \(n(b.0 - a.0)) \(n(b.1 - a.1)) \(n(d.0 - a.0)) \(n(d.1 - a.1)) \(n(a.0)) \(n(a.1)) cm /\(name) Do Q\n"
                    } else {
                        o += "0.6 0.6 0.6 RG 0.3 w [] 0 d "
                        for (i, c) in corners.enumerated() { let q = f.pt(c); o += "\(n(q.0)) \(n(q.1)) \(i == 0 ? "m" : "l") " }
                        o += "s\n"
                    }
                }
            }
        }
        page.ops += o
    }

    /// Text in Helvetica: height is the cap height (as the screen and SVG), lines 1.5 heights apart.
    static func text(_ t: TextGeom, color: RGBA, frame f: Frame, bold: Bool = false) -> String {
        let lines = t.content.components(separatedBy: "\n")
        guard !lines.allSatisfy({ $0.isEmpty }) else { return "" }
        let h = t.height / f.scale * k            // cap height in points
        guard h > 0.05 else { return "" }
        let size = h / 0.717, pitch = h * 1.5
        let count = Double(lines.count)
        let blockH = h + pitch * (count - 1)
        // Baseline of the first line above (+) / below (−) the anchor.
        let first: Double
        switch t.valign {
        case .baseline: first = 0
        case .top: first = -h
        case .middle: first = -(h - blockH / 2)
        case .bottom: first = 0.2 * h + pitch * (count - 1)
        }
        let a = f.pt(t.position)
        let c = cos(t.rotation), s = sin(t.rotation)
        var o = "BT /\(bold ? "F2" : "F1") \(n(size)) Tf \(rgb(color)) rg\n"
        for (i, l) in lines.enumerated() where !l.isEmpty {
            let w = textWidth(l) * size
            let dx: Double = t.halign == .left ? 0 : (t.halign == .center ? -w / 2 : -w)
            let dy = first - pitch * Double(i)
            let x = a.0 + dx * c - dy * s, y = a.1 + dx * s + dy * c
            o += "\(n(c)) \(n(s)) \(n(-s)) \(n(c)) \(n(x)) \(n(y)) Tm \(literal(l)) Tj\n"
        }
        return o + "ET\n"
    }

    /// Pixel size of a baseline or progressive JPEG (nil for other data).
    static func jpegSize(_ d: Data) -> (Int, Int)? {
        let b = [UInt8](d)
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xD8 || m == 0x01 || (0xD0...0xD7).contains(m) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if (0xC0...0xCF).contains(m) && m != 0xC4 && m != 0xC8 && m != 0xCC {
                let hgt = Int(b[i + 5]) << 8 | Int(b[i + 6]), wid = Int(b[i + 7]) << 8 | Int(b[i + 8])
                return wid > 0 && hgt > 0 && b[i + 9] == 3 ? (wid, hgt) : nil
            }
            i += 2 + len
        }
        return nil
    }

    // MARK: - Documents

    /// The plan of a level on `paper` at 1:`scale` (drawing units per paper mm; nil = largest standard scale that fits
    /// inside 10 mm margins), centred, with a scale note.
    public static func planPage(_ doc: ArchiDocument, level: Int? = nil, paper: PaperSize = PaperSize.standard[1], scale: Double? = nil) -> Page {
        var o = DrawOptions(level: level ?? doc.currentLevel); o.forPaper = true
        let entries = DrawListBuilder.entries(doc: doc, options: o)
        var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
        if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
        let margin = 10.0, usable = Vec2(paper.width - 2 * margin, paper.height - 2 * margin - 8)
        let mmPerUnit = doc.units.mm
        let s: Double
        if let sc = scale, sc > 0 { s = sc }
        else {
            // Scale n (1:n) in drawing units per paper mm is n / mmPerUnit.
            let need = max(b.width / usable.x, b.height / usable.y) * mmPerUnit
            let n = standardScales.first { $0 >= need } ?? (need.rounded(.up))
            s = n / mmPerUnit
        }
        var page = Page(width: paper.width, height: paper.height)
        let f = Frame(center: Vec2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2), scale: s, paperCenter: Vec2(paper.width / 2, paper.height / 2 + 4))
        draw(entries, frame: f, into: &page)
        let note = TextGeom(position: Vec2(margin, margin), height: 2.5, content: "\(doc.info.name.isEmpty ? "Plan" : doc.info.name) — 1:\(fmt(s * mmPerUnit, 0))")
        page.ops += text(note, color: RGBA(0.13, 0.13, 0.13), frame: Frame(center: .zero, scale: 1, paperCenter: .zero))
        return page
    }

    /// A sheet (layout) at true scale on its paper.
    public static func sheetPage(_ doc: ArchiDocument, layout li: Int) -> Page? {
        guard doc.layouts.indices.contains(li) else { return nil }
        let l = doc.layouts[li]
        var page = Page(width: l.paper.width, height: l.paper.height)
        let ink = RGBA(0.13, 0.13, 0.13)
        let paperFrame = Frame(center: .zero, scale: 1, paperCenter: .zero)
        for vp in l.viewports where vp.size.x > 0 && vp.size.y > 0 && vp.scale > 0 {
            let f = Frame(center: vp.viewCenter, scale: vp.scale, paperCenter: vp.origin + vp.size / 2)
            let half = Vec2(vp.size.x * vp.scale / 2, vp.size.y * vp.scale / 2)
            let window = BBox2(min: vp.viewCenter - half, max: vp.viewCenter + half)
            page.ops += "q \(n(vp.origin.x * k)) \(n(vp.origin.y * k)) \(n(vp.size.x * k)) \(n(vp.size.y * k)) re W n\n"
            draw(Presentation.viewportEntries(doc, vp), frame: f, into: &page, clip: window)
            page.ops += "Q\n"
            if !vp.title.isEmpty {
                page.ops += text(TextGeom(position: vp.origin - Vec2(0, 5), height: 2.5, content: "\(vp.title) — 1:\(Int((vp.scale * doc.units.mm).rounded()))"), color: ink, frame: paperFrame)
            }
        }
        if !l.entities.isEmpty {
            var paper = doc
            paper.entities = l.entities
            paper.elements = []
            var o = DrawOptions(level: nil); o.forPaper = true
            draw(DrawListBuilder.entries(doc: paper, options: o), frame: paperFrame, into: &page)
        }
        // Title block (bottom right), as in the SVG sheet.
        var fields = [("Project", doc.info.name), ("Sheet", l.name)]
        for (key, v) in l.titleBlock.sorted(by: { $0.key < $1.key }) where key.lowercased() != "notes" && !v.isEmpty { fields.append((key, v)) }
        let bw = 90.0, lh = 5.0, bh = Double(fields.count) * lh + 4
        let x0 = l.paper.width - bw - 10, y0 = 10.0
        page.ops += "\(rgb(ink)) RG 1 w [] 0 d \(n(x0 * k)) \(n(y0 * k)) \(n(bw * k)) \(n(bh * k)) re S\n"
        for (i, fld) in fields.enumerated() {
            let y = y0 + bh - 5.5 - Double(i) * lh
            page.ops += text(TextGeom(position: Vec2(x0 + 3, y), height: 2.1, content: fld.0 + ":"), color: ink, frame: paperFrame, bold: true)
            page.ops += text(TextGeom(position: Vec2(x0 + 3 + textWidth(fld.0 + ": ") * 2.1 / 0.717, y), height: 2.1, content: fld.1), color: ink, frame: paperFrame)
        }
        return page
    }

    /// Selected objects on a page fitted around them (5 mm margin), at 1:`scale` or the smallest standard scale that keeps
    /// the page within A0 — for "Copy as PDF" to other applications.
    public static func objects(_ doc: ArchiDocument, ids: Set<EntityID>, scale: Double? = nil) -> Data? {
        var o = DrawOptions(level: doc.currentLevel); o.forPaper = true
        let entries = DrawListBuilder.entries(doc: doc, options: o).filter { $0.id.map(ids.contains) ?? false }
        let b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
        guard !b.isEmpty else { return nil }
        let mm = doc.units.mm, margin = 5.0
        let s: Double
        if let sc = scale, sc > 0 { s = sc / mm }
        else {
            let need = max(b.width * mm / 1189, b.height * mm / 841, 1)
            s = (standardScales.first { $0 >= need } ?? need.rounded(.up)) / mm
        }
        var page = Page(width: max(b.width / s, 1) + 2 * margin, height: max(b.height / s, 1) + 2 * margin)
        let f = Frame(center: Vec2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2), scale: s, paperCenter: Vec2(page.width / 2, page.height / 2))
        draw(entries, frame: f, into: &page)
        return write([page], title: doc.info.name)
    }

    /// Every sheet with content, or the plan of the current level when there is none.
    public static func document(_ doc: ArchiDocument, level: Int? = nil) -> Data {
        let sheets = doc.layouts.indices.filter { !doc.layouts[$0].viewports.isEmpty || !doc.layouts[$0].entities.isEmpty }
        let pages = level == nil && !sheets.isEmpty ? sheets.compactMap { sheetPage(doc, layout: $0) } : [planPage(doc, level: level)]
        return write(pages, title: doc.info.name)
    }

    /// Serialises pages into a PDF file.
    public static func write(_ pages: [Page], title: String = "") -> Data {
        var out = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        var objects: [Data] = []
        func reserve() -> Int { objects.append(Data()); return objects.count }
        func set(_ id: Int, _ s: String) { objects[id - 1] = Data(s.utf8) }
        let catalog = reserve(), pagesID = reserve(), f1 = reserve(), f2 = reserve(), info = reserve()
        set(f1, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        set(f2, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
        let date: String = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMddHHmmss"; return "D:" + f.string(from: Date()) + "Z" }()
        set(info, "<< /Producer (Oanarina Archi Tool) /Creator (Oanarina Archi Tool) /Title \(literal(title)) /CreationDate (\(date)) >>")
        var kids: [Int] = []
        for p in pages {
            let pageID = reserve(), contentID = reserve()
            var xobjects: [String] = []
            for im in p.images {
                let imgID = reserve()
                var d = Data("<< /Type /XObject /Subtype /Image /Width \(im.width) /Height \(im.height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length \(im.data.count) >>\nstream\n".utf8)
                d += im.data; d += Data("\nendstream".utf8)
                objects[imgID - 1] = d
                xobjects.append("/\(im.name) \(imgID) 0 R")
            }
            let content = Data(p.ops.utf8)
            var cd = Data("<< /Length \(content.count) >>\nstream\n".utf8); cd += content; cd += Data("\nendstream".utf8)
            objects[contentID - 1] = cd
            set(pageID, "<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [0 0 \(n(p.width * k)) \(n(p.height * k))] /Contents \(contentID) 0 R " +
                "/Resources << /Font << /F1 \(f1) 0 R /F2 \(f2) 0 R >>" + (xobjects.isEmpty ? "" : " /XObject << " + xobjects.joined(separator: " ") + " >>") + " >> >>")
            kids.append(pageID)
        }
        set(pagesID, "<< /Type /Pages /Kids [" + kids.map { "\($0) 0 R" }.joined(separator: " ") + "] /Count \(kids.count) >>")
        set(catalog, "<< /Type /Catalog /Pages \(pagesID) 0 R >>")
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out += Data("\(i + 1) 0 obj\n".utf8); out += o; out += Data("\nendobj\n".utf8)
        }
        let xref = out.count
        var x = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { x += String(format: "%010d 00000 n \n", o) }
        x += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R /Info \(info) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out += Data(x.utf8)
        return out
    }
}
