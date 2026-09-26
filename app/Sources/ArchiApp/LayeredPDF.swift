// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import CoreText
import Compression
import ArchiCore

/// Vector PDF export with one optional content group (OCG) per drawing layer (SHT-024, SHT-025): true-scale sheets
/// or model space, standard Helvetica text (searchable), images, and link annotations for objects with a hyperlink.
/// Written directly (Core Graphics cannot emit OCGs); the drawing is the same `DrawEntry` list the plot uses.
@MainActor
enum LayeredPDF {
    /// Pseudo-layer of decorations that belong to no drawing layer (frame, title block, viewport titles).
    static let sheetLayer = "Sheet"

    struct Page {
        var name: String
        var widthMM: Double
        var heightMM: Double
        /// Entries in their own coordinates, the renderer mapping them to points, and an optional clip (points).
        var parts: [(entries: [DrawEntry], renderer: PlotRenderer, clip: CGRect?)]
    }

    struct Output {
        var data: Data
        /// Uncompressed content stream of each page (tests).
        var contents: [String]
        var layers: [String]
        var links: Int
    }

    // MARK: Page builders

    /// A sheet at true size: paper-space entries (viewports clipped to their frames).
    static func sheetPage(doc: ArchiDocument, layoutIndex li: Int) -> Page? {
        guard doc.layouts.indices.contains(li) else { return nil }
        let l = doc.layouts[li]
        var r = PlotRenderer(transform: CGAffineTransform(scaleX: Plotter.pointsPerMM, y: Plotter.pointsPerMM), devicePerMM: Plotter.pointsPerMM, paper: true, minLineWidth: 0.12)
        r.apply(PageSetup.load(doc, layoutIndex: li), doc: doc)
        return Page(name: l.name, widthMM: l.paper.width, heightMM: l.paper.height, parts: [(SheetSVG.entries(doc: doc, layoutIndex: li), r, nil)])
    }

    /// Model space of a level on the model page setup's paper, at the setup's scale (or the largest standard scale that fits).
    static func modelPage(doc: ArchiDocument, level: Int?, ratio fixed: Double? = nil) -> (page: Page, ratio: Double) {
        var setup = PageSetup.load(doc, layoutIndex: nil)
        if let fixed { setup.modelScale = fixed }
        let paper = setup.modelPaperSize
        let margin = 10.0
        var opts = DrawOptions(level: level)
        opts.forPaper = true
        var entries = DrawListBuilder.entries(doc: doc, options: opts)
        let area = BBox2(min: Vec2(margin, margin), max: Vec2(paper.width - margin, paper.height - margin))
        let (b, ratio) = Plotter.modelFrame(doc: doc, setup: setup, extents: entries.unionBounds, area: area)
        let scale = ratio / doc.units.mm
        if opts.linetypeScale != max(1, scale * 0.25) { opts.linetypeScale = max(1, scale * 0.25); entries = DrawListBuilder.entries(doc: doc, options: opts) }
        let center = b.isEmpty ? Vec2.zero : b.center
        let s = Plotter.pointsPerMM / CGFloat(scale)
        let t = CGAffineTransform(translationX: -center.x, y: -center.y).concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: area.center.x * Plotter.pointsPerMM, y: area.center.y * Plotter.pointsPerMM))
        var r = PlotRenderer(transform: t, devicePerMM: Plotter.pointsPerMM, paper: true, minLineWidth: 0.12)
        r.apply(setup, doc: doc)
        let clip = CGRect(x: area.min.x * Plotter.pointsPerMM, y: area.min.y * Plotter.pointsPerMM, width: area.width * Plotter.pointsPerMM, height: area.height * Plotter.pointsPerMM)
        let name = level.flatMap { doc.level($0)?.name } ?? "Model"
        return (Page(name: name, widthMM: paper.width, heightMM: paper.height, parts: [(entries, r, clip)]), ratio)
    }

    // MARK: Writer

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

    static func build(doc: ArchiDocument, pages: [Page], title: String, compress: Bool = true) -> Output {
        let layerOf = layerMap(doc), links = hyperlinks(doc)
        // Layer order: document order of the layers used, then the sheet pseudo-layer.
        var used = Set<String>()
        for p in pages { for part in p.parts { for e in part.entries { used.insert(e.id.flatMap { layerOf[$0] } ?? sheetLayer) } } }
        var order: [String] = []
        for l in doc.layers.map(\.name) where used.contains(l) && !order.contains(l) { order.append(l) }
        for u in used.sorted() where !order.contains(u) { order.append(u) }
        let hidden = Set(doc.layers.filter { !$0.visible }.map(\.name))

        var objects: [Data] = []   // 1-based numbering: objects[i] is object i+1
        func reserve() -> Int { objects.append(Data()); return objects.count }
        func set(_ n: Int, _ s: String) { objects[n - 1] = Data(s.utf8) }
        func setData(_ n: Int, _ d: Data) { objects[n - 1] = d }

        let catalog = reserve(), pagesObj = reserve(), font = reserve(), info = reserve()
        set(font, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        var ocg: [String: Int] = [:]
        for (i, l) in order.enumerated() { let n = reserve(); ocg[l] = n; set(n, "<< /Type /OCG /Name \(pdfString(l)) >>"); _ = i }
        let ocRef = { (l: String) in "/L\(order.firstIndex(of: l) ?? 0)" }

        var pageRefs: [Int] = [], contents: [String] = [], linkCount = 0
        for page in pages {
            var gs: [Double: String] = [:]
            var images: [(name: String, obj: Int)] = []
            var annots: [Int] = []
            var linked = Set<EntityID>()
            var body = ""
            // Group items by layer, keeping draw order inside each layer.
            for layer in order {
                var chunk = ""
                for part in page.parts {
                    var partChunk = ""
                    for e in part.entries where (e.id.flatMap { layerOf[$0] } ?? sheetLayer) == layer {
                        var r = part.renderer
                        if let ep = r.entryPen, let id = e.id, let pen = ep(id) { r.activePen = pen }
                        for it in e.items { partChunk += emit(it, r, gs: &gs, images: &images, reserve: reserve, setData: setData) }
                        if let id = e.id, let url = links[id], !e.bounds.isEmpty, linked.insert(id).inserted {
                            let a = part.renderer.point(e.bounds.min), b = part.renderer.point(e.bounds.max)
                            let n = reserve()
                            set(n, "<< /Type /Annot /Subtype /Link /Border [0 0 0] /Rect [\(num(min(a.x, b.x))) \(num(min(a.y, b.y))) \(num(max(a.x, b.x))) \(num(max(a.y, b.y)))] /A << /S /URI /URI \(asciiString(url)) >> >>")
                            annots.append(n); linkCount += 1
                        }
                    }
                    if partChunk.isEmpty { continue }
                    if let c = part.clip { chunk += "q \(num(c.minX)) \(num(c.minY)) \(num(c.width)) \(num(c.height)) re W n\n" + partChunk + "Q\n" } else { chunk += partChunk }
                }
                if !chunk.isEmpty { body += "/OC \(ocRef(layer)) BDC\n" + chunk + "EMC\n" }
            }
            contents.append(body)
            let stream = reserve()
            let raw = Data(body.utf8)
            if compress, let z = zlib(raw) {
                var d = Data("<< /Length \(z.count) /Filter /FlateDecode >>\nstream\n".utf8); d.append(z); d.append(Data("\nendstream".utf8)); setData(stream, d)
            } else {
                var d = Data("<< /Length \(raw.count) >>\nstream\n".utf8); d.append(raw); d.append(Data("\nendstream".utf8)); setData(stream, d)
            }
            let props = order.enumerated().map { "/L\($0.offset) \(ocg[$0.element]!) 0 R" }.joined(separator: " ")
            let ext = gs.map { "/\($0.value) << /Type /ExtGState /CA \(num($0.key)) /ca \(num($0.key)) >>" }.joined(separator: " ")
            let xo = images.map { "/\($0.name) \($0.obj) 0 R" }.joined(separator: " ")
            let w = page.widthMM * Plotter.pointsPerMM, h = page.heightMM * Plotter.pointsPerMM
            let p = reserve()
            set(p, "<< /Type /Page /Parent \(pagesObj) 0 R /MediaBox [0 0 \(num(w)) \(num(h))] /Contents \(stream) 0 R"
                + " /Resources << /Font << /F1 \(font) 0 R >> /Properties << \(props) >>" + (ext.isEmpty ? "" : " /ExtGState << \(ext) >>") + (xo.isEmpty ? "" : " /XObject << \(xo) >>") + " >>"
                + (annots.isEmpty ? "" : " /Annots [\(annots.map { "\($0) 0 R" }.joined(separator: " "))]") + " >>")
            pageRefs.append(p)
        }
        set(pagesObj, "<< /Type /Pages /Kids [\(pageRefs.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pageRefs.count) >>")
        let all = order.map { "\(ocg[$0]!) 0 R" }.joined(separator: " ")
        let off = order.filter { hidden.contains($0) }.map { "\(ocg[$0]!) 0 R" }.joined(separator: " ")
        set(catalog, "<< /Type /Catalog /Pages \(pagesObj) 0 R /PageMode /UseOC /OCProperties << /OCGs [\(all)] /D << /Name (Layers) /Order [\(all)] /ON [\(order.filter { !hidden.contains($0) }.map { "\(ocg[$0]!) 0 R" }.joined(separator: " "))] /OFF [\(off)] >> >> >>")
        set(info, "<< /Title \(pdfString(title)) /Creator (Oanarina Archi Tool) /Producer (Oanarina Archi Tool layered PDF) /Author \(pdfString(doc.info.author)) >>")

        var out = Data("%PDF-1.6\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n".utf8)); out.append(o); out.append(Data("\nendobj\n".utf8))
        }
        let xref = out.count
        var x = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { x += String(format: "%010d 00000 n \n", o) }
        x += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R /Info \(info) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(x.utf8))
        return Output(data: out, contents: contents, layers: order, links: linkCount)
    }

    static func write(doc: ArchiDocument, pages: [Page], title: String, to url: URL) throws -> Output {
        let o = build(doc: doc, pages: pages, title: title)
        try o.data.write(to: url)
        return o
    }

    // MARK: Items

    private static func emit(_ item: DrawItem, _ r: PlotRenderer, gs: inout [Double: String], images: inout [(name: String, obj: Int)],
                             reserve: () -> Int, setData: (Int, Data) -> Void) -> String {
        func rgb(_ c: CGColor) -> (String, Double) {
            let comps = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? c.components ?? [0, 0, 0, 1]
            let v = comps.count >= 3 ? comps : [comps[0], comps[0], comps[0], comps.last ?? 1]
            return ("\(num(v[0])) \(num(v[1])) \(num(v[2]))", Double(v.count > 3 ? v[3] : 1))
        }
        func alpha(_ a: Double) -> String {
            guard a < 0.999 else { return "" }
            let k = (a * 100).rounded() / 100
            if gs[k] == nil { gs[k] = "GS\(gs.count)" }
            return "/\(gs[k]!) gs "
        }
        switch item {
        case .stroke(let pts, let closed, let style):
            guard let first = pts.first else { return "" }
            let (c, a) = rgb(r.color(style.color))
            if pts.count == 1 {
                let q = r.point(first), w = r.width(style)
                return "q \(alpha(a))\(c) rg \(num(q.x - w)) \(num(q.y - w)) \(num(2 * w)) \(num(2 * w)) re f Q\n"
            }
            var s = "q \(alpha(a))\(c) RG \(num(r.width(style))) w 1 J 1 j "
            if !style.dash.isEmpty {
                let k = r.scaleFactor
                let lens = style.dash.map { $0 == 0 ? 0.01 : abs($0) * Double(k) }
                if lens.reduce(0, +) > 1.5 { s += "[\((lens.count % 2 == 0 ? lens : lens + lens).map(num).joined(separator: " "))] 0 d 0 J " }
            }
            let p0 = r.point(first)
            s += "\(num(p0.x)) \(num(p0.y)) m"
            for p in pts.dropFirst() { let q = r.point(p); s += " \(num(q.x)) \(num(q.y)) l" }
            s += closed ? " h S Q\n" : " S Q\n"
            return s
        case .fill(let loops, let color):
            let (c, a) = rgb(r.color(color))
            var s = "q \(alpha(a))\(c) rg"
            var any = false
            for l in loops where l.count >= 3 {
                let p0 = r.point(l[0]); s += " \(num(p0.x)) \(num(p0.y)) m"
                for p in l.dropFirst() { let q = r.point(p); s += " \(num(q.x)) \(num(q.y)) l" }
                s += " h"; any = true
            }
            return any ? s + " f* Q\n" : ""
        case .text(let t, _, let color):
            return text(t, r, color: rgb(r.color(color)).0)
        case .image(let im):
            guard let img = NSImage(contentsOfFile: (im.path as NSString).expandingTildeInPath), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let jpg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return "" }
            let n = reserve()
            var d = Data("<< /Type /XObject /Subtype /Image /Width \(cg.width) /Height \(cg.height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length \(jpg.count) >>\nstream\n".utf8)
            d.append(jpg); d.append(Data("\nendstream".utf8)); setData(n, d)
            let name = "Im\(images.count)"; images.append((name, n))
            let o = r.point(im.origin), s = r.scaleFactor, a = CGFloat(im.rotation) + r.rotation
            let w = CGFloat(im.size.x) * s, h = CGFloat(im.size.y) * s
            return "q \(num(cos(a) * w)) \(num(sin(a) * w)) \(num(-sin(a) * h)) \(num(cos(a) * h)) \(num(o.x)) \(num(o.y)) cm /\(name) Do Q\n"
        }
    }

    /// Helvetica text with the plot's cap-height sizing, alignment, wrapping and rotation.
    private static func text(_ t: TextGeom, _ r: PlotRenderer, color: String) -> String {
        let h = CGFloat(t.height) * r.scaleFactor
        guard h > 0.2, h < 20000, !t.content.isEmpty else { return "" }
        let capRatio: CGFloat = 0.718
        let size = h / capRatio
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        func width(_ s: String) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), nil, nil, nil))
        }
        let paragraphs = t.content.replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
        var lines: [String] = []
        let wrap = CGFloat(t.width) * r.scaleFactor
        for para in paragraphs {
            guard wrap > 0 else { lines.append(para); continue }
            var cur = ""
            for word in para.split(separator: " ", omittingEmptySubsequences: false) {
                let cand = cur.isEmpty ? String(word) : cur + " " + word
                if !cur.isEmpty && width(cand) > wrap { lines.append(cur); cur = String(word) } else { cur = cand }
            }
            lines.append(cur)
        }
        let spacing = h * 1.6, n = CGFloat(lines.count)
        let first: CGFloat
        switch t.valign {
        case .baseline: first = lines.count > 1 && t.width > 0 ? -h : 0
        case .bottom: first = (n - 1) * spacing + h * 0.3
        case .middle: first = ((n - 1) * spacing) / 2 - h / 2
        case .top: first = -h
        }
        let o = r.point(t.position), a = CGFloat(t.rotation) + r.rotation
        let ca = cos(a), sa = sin(a)
        var s = "q BT /F1 \(num(size)) Tf \(color) rg\n"
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let w = width(line)
            let x: CGFloat = t.halign == .left ? 0 : (t.halign == .center ? -w / 2 : -w)
            let y = first - CGFloat(i) * spacing
            s += "\(num(ca)) \(num(sa)) \(num(-sa)) \(num(ca)) \(num(o.x + ca * x - sa * y)) \(num(o.y + sa * x + ca * y)) Tm <\(hex(line))> Tj\n"
        }
        return s + "ET Q\n"
    }

    // MARK: Encoding

    static func num(_ v: CGFloat) -> String { num(Double(v)) }
    static func num(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(format: "%.3f", r)
    }
    static func hex(_ s: String) -> String {
        let d = s.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data(s.utf8)
        return d.map { String(format: "%02X", $0) }.joined()
    }
    /// ASCII literal string (URIs): non-ASCII percent-encoded, delimiters escaped.
    static func asciiString(_ s: String) -> String {
        let a = s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "!#$&'()*+,/:;=?@[]~-._%").union(.alphanumerics)) ?? s
        return "(" + a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)") + ")"
    }
    static func pdfString(_ s: String) -> String { "<FEFF" + s.utf16.map { String(format: "%04X", $0) }.joined() + ">" }

    /// zlib stream (RFC 1950): header, raw DEFLATE from the Compression framework, Adler-32.
    static func zlib(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let cap = data.count + 1024
        var dst = [UInt8](repeating: 0, count: cap)
        let n = data.withUnsafeBytes { src in compression_encode_buffer(&dst, cap, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB) }
        guard n > 0 else { return nil }
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let adler = (b << 16) | a
        var out = Data([0x78, 0x9C]); out.append(contentsOf: dst[0..<n])
        out.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
        return out
    }
}
