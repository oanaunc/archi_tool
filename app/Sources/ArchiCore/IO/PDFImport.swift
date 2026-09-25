// Oanarina Archi Tool — GPL-3.0-or-later
// PDF vector import (IO-014) and PDF markup import (COL-008) on top of PDFFile (PDFReader.swift).
import Foundation

public struct PDFImportOptions {
    /// Drawing units per PDF point (1 pt = 25.4/72 mm). Default: millimetres at 1:1.
    public var unitsPerPoint: Double = 25.4 / 72
    /// Where the page's lower-left corner lands in the drawing.
    public var origin: Vec2 = .zero
    public var importText = true
    public var importFills = true
    /// Curve segments per Bézier.
    public var curveSegments = 8
    public init() {}
    public func map(_ p: Vec2, page: BBox2) -> Vec2 { origin + (p - page.min) * unitsPerPoint }
}

public enum PDFImport {
    struct Matrix { var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
        static func * (m: Matrix, n: Matrix) -> Matrix {   // m then n (row vectors)
            Matrix(a: m.a * n.a + m.b * n.c, b: m.a * n.b + m.b * n.d, c: m.c * n.a + m.d * n.c, d: m.c * n.b + m.d * n.d, e: m.e * n.a + m.f * n.c + n.e, f: m.e * n.b + m.f * n.d + n.f)
        }
        func apply(_ p: Vec2) -> Vec2 { Vec2(a * p.x + c * p.y + e, b * p.x + d * p.y + f) }
        var scale: Double { sqrt(abs(a * d - b * c)) }
    }
    struct GState { var ctm = Matrix(); var stroke = RGBA(0, 0, 0); var fill = RGBA(0, 0, 0); var lineWidth = 1.0 }

    /// Maps character codes to Unicode from a font's ToUnicode CMap (bfchar / bfrange); nil = single-byte Latin-1.
    struct FontMap { var codeBytes = 1; var map: [UInt32: String] = [:] }
    static func fontMap(_ font: [String: PDFObj]?, pdf: PDFFile) -> FontMap? {
        guard let font else { return nil }
        var fm = FontMap()
        if font["Subtype"]?.name == "Type0" { fm.codeBytes = 2 }
        guard let tu = pdf.resolve(font["ToUnicode"]), let data = pdf.decode(tu) else { return fm.codeBytes == 1 ? nil : fm }
        var lx = PDFLexer(b: [UInt8](data), i: 0)
        var stack: [PDFObj] = []
        func hexVal(_ d: Data) -> UInt32 { d.reduce(0) { $0 << 8 | UInt32($1) } }
        func uni(_ d: Data) -> String { String(data: d, encoding: .utf16BigEndian) ?? "" }
        while let o = lx.object() {
            switch o {
            case .op("endbfchar"):
                var k = 0
                while k + 1 < stack.count { if let s = stack[k].data, let t = stack[k + 1].data { fm.map[hexVal(s)] = uni(t); fm.codeBytes = max(1, s.count) }; k += 2 }
                stack = []
            case .op("endbfrange"):
                var k = 0
                while k + 2 < stack.count {
                    if let lo = stack[k].data, let hi = stack[k + 1].data {
                        let l = hexVal(lo), h = hexVal(hi)
                        fm.codeBytes = max(1, lo.count)
                        if let dst = stack[k + 2].data, h >= l, h - l < 65536 {
                            let base = [UInt8](dst)
                            for c in l...h {
                                var u = base
                                let off = c - l
                                if let lastIdx = u.indices.last { let v = UInt32(u[lastIdx]) + off; u[lastIdx] = UInt8(v & 0xFF); if lastIdx > 0 { u[lastIdx - 1] = u[lastIdx - 1] &+ UInt8((v >> 8) & 0xFF) } }
                                fm.map[c] = uni(Data(u))
                            }
                        } else if let arr = stack[k + 2].array {
                            for (j, a) in arr.enumerated() where UInt32(j) <= h - l { if let t = a.data { fm.map[l + UInt32(j)] = uni(t) } }
                        }
                    }
                    k += 3
                }
                stack = []
            case .op("beginbfchar"), .op("beginbfrange"): stack = []
            case .op: break
            default: stack.append(o)
            }
        }
        return fm
    }
    static func decodeText(_ d: Data, _ fm: FontMap?) -> String {
        guard let fm else { return String(data: d, encoding: .isoLatin1) ?? "" }
        let b = [UInt8](d)
        var out = "", i = 0
        while i < b.count {
            let n = min(fm.codeBytes, b.count - i)
            let code = b[i..<(i + n)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if let s = fm.map[code] { out += s } else if n == 1 { out += String(UnicodeScalar(UInt8(code))) }
            i += n
        }
        return out
    }

    /// Entities of one page (1-based), in drawing units.
    public static func entities(_ pdf: PDFFile, page n: Int, options o: PDFImportOptions = PDFImportOptions()) throws -> [Entity] {
        let pages = pdf.pages
        guard n >= 1, n <= pages.count else { throw PDFFile.PDFError(message: "The PDF has \(pages.count) page(s).") }
        let page = pages[n - 1]
        var out: [Entity] = []
        var contents: [Data] = []
        if let c = pdf.resolve(page.dict["Contents"]) {
            if case .array(let a) = c { for x in a { if let s = pdf.resolve(x), let d = pdf.decode(s) { contents.append(d) } } }
            else if let d = pdf.decode(c) { contents.append(d) }
        }
        var data = Data()
        for c in contents { data.append(c); data.append(10) }
        run(data, resources: page.resources, pdf: pdf, gs: GState(), page: page.mediaBox, options: o, out: &out, depth: 0)
        return out
    }

    static func run(_ data: Data, resources: [String: PDFObj], pdf: PDFFile, gs gs0: GState, page: BBox2, options o: PDFImportOptions, out: inout [Entity], depth: Int) {
        guard depth < 12 else { return }
        var lx = PDFLexer(b: [UInt8](data), i: 0)
        var ops: [PDFObj] = []
        var gs = gs0
        var stack: [GState] = []
        var subpaths: [[Vec2]] = [], closed: [Bool] = [], cur: [Vec2] = []
        var layers: [String] = []
        // Text state.
        var tm = Matrix(), tlm = Matrix(), fontSize = 12.0, leading = 0.0, font: FontMap?
        var fontCache: [String: FontMap?] = [:]
        func num(_ k: Int) -> Double { k < ops.count ? (ops[k].num ?? 0) : 0 }
        func P(_ x: Double, _ y: Double) -> Vec2 { gs.ctm.apply(Vec2(x, y)) }
        func flush() { if cur.count > 1 { subpaths.append(cur); closed.append(false) }; cur = [] }
        func rgb(_ c: RGBA) -> ColorRef { .rgb(UInt8(max(0, min(255, (c.r * 255).rounded()))), UInt8(max(0, min(255, (c.g * 255).rounded()))), UInt8(max(0, min(255, (c.b * 255).rounded())))) }
        func layerName() -> String { layers.last ?? "PDF" }
        func emit(stroke: Bool, fill: Bool) {
            flush()
            defer { subpaths = []; closed = []; cur = [] }
            guard stroke || (fill && o.importFills) else { return }
            for (k, sp) in subpaths.enumerated() {
                let pts = sp.map { o.map($0, page: page) }
                guard pts.count >= 2 else { continue }
                let isClosed = closed[k] || (fill && pts.count > 2)
                let g: Geometry = pts.count == 2 && !isClosed ? .line(LineGeom(pts[0], pts[1])) : .polyline(PolylineGeom(points: isClosed && pts.first!.distance(to: pts.last!) < 1e-9 ? Array(pts.dropLast()) : pts, closed: isClosed))
                var e = Entity(layer: stroke ? layerName() : layerName() + "-FILL", color: rgb(stroke ? gs.stroke : gs.fill), geometry: g)
                if stroke { e.lineweight = max(0, gs.lineWidth * gs.ctm.scale * 25.4 / 72) }
                out.append(e)
                if fill && !stroke, o.importFills, pts.count >= 3 {
                    out.append(Entity(layer: layerName() + "-FILL", color: rgb(gs.fill), geometry: .hatch(HatchGeom(loops: [pts.map { PolyVertex($0) }], pattern: "SOLID"))))
                }
            }
        }
        func color(_ k: Int) -> RGBA {
            let v = ops.compactMap(\.num)
            switch v.count {
            case 1: return RGBA(v[0], v[0], v[0])
            case 3: return RGBA(v[0], v[1], v[2])
            case 4: return RGBA((1 - v[0]) * (1 - v[3]), (1 - v[1]) * (1 - v[3]), (1 - v[2]) * (1 - v[3]))
            default: return RGBA(0, 0, 0)
            }
        }
        func showText(_ s: String) {
            guard o.importText, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let m = tm * gs.ctm
            let pos = o.map(m.apply(.zero), page: page)
            let h = fontSize * Matrix(a: m.a, b: m.b, c: m.c, d: m.d).scale * o.unitsPerPoint
            let rot = atan2(m.b, m.a)
            out.append(Entity(layer: layerName() + "-TEXT", color: rgb(gs.fill), geometry: .text(TextGeom(position: pos, height: max(h * 0.7, 1e-6), content: s, rotation: rot))))
            // Advance roughly by the string width (0.5 em per glyph) so following strings do not overlap.
            tm = Matrix(e: Double(s.count) * fontSize * 0.5) * tm
        }
        while let obj = lx.object() {
            guard case .op(let op) = obj else { ops.append(obj); continue }
            switch op {
            case "q": stack.append(gs)
            case "Q": if let g = stack.popLast() { gs = g }
            case "cm": gs.ctm = Matrix(a: num(0), b: num(1), c: num(2), d: num(3), e: num(4), f: num(5)) * gs.ctm
            case "w": gs.lineWidth = num(0)
            case "RG", "K", "G", "SC", "SCN": gs.stroke = color(0)
            case "rg", "k", "g", "sc", "scn": gs.fill = color(0)
            case "m": flush(); cur = [P(num(0), num(1))]
            case "l": cur.append(P(num(0), num(1)))
            case "c", "v", "y":
                guard let p0 = cur.last else { break }
                let pts: (Vec2, Vec2, Vec2)
                if op == "c" { pts = (P(num(0), num(1)), P(num(2), num(3)), P(num(4), num(5))) }
                else if op == "v" { pts = (p0, P(num(0), num(1)), P(num(2), num(3))) }
                else { let e = P(num(2), num(3)); pts = (P(num(0), num(1)), e, e) }
                let segs = max(2, o.curveSegments)
                for s in 1...segs {
                    let t = Double(s) / Double(segs), u = 1 - t
                    cur.append(p0 * (u * u * u) + pts.0 * (3 * u * u * t) + pts.1 * (3 * u * t * t) + pts.2 * (t * t * t))
                }
            case "h": if cur.count > 1 { subpaths.append(cur); closed.append(true) }; cur = cur.first.map { [$0] } ?? []; if cur.count == 1 { cur = [] }
            case "re":
                flush()
                let x = num(0), y = num(1), w = num(2), hh = num(3)
                subpaths.append([P(x, y), P(x + w, y), P(x + w, y + hh), P(x, y + hh)]); closed.append(true)
            case "S": emit(stroke: true, fill: false)
            case "s": if cur.count > 1 { subpaths.append(cur); closed.append(true); cur = [] }; emit(stroke: true, fill: false)
            case "f", "F", "f*": emit(stroke: false, fill: true)
            case "B", "B*", "b", "b*":
                if op.hasPrefix("b"), cur.count > 1 { subpaths.append(cur); closed.append(true); cur = [] }
                emit(stroke: true, fill: true)
            case "n": subpaths = []; closed = []; cur = []
            case "BDC":
                // Optional content: /OC /name → the OCG's /Name becomes the layer.
                var lname: String?
                if ops.count >= 2, ops[0].name == "OC" {
                    if let pn = ops[1].name, let props = pdf.dict(resources["Properties"]), let ocg = pdf.dict(props[pn]), let nm = pdf.resolve(ocg["Name"])?.data { lname = PDFFile.text(nm) }
                    else if let ocg = pdf.dict(ops[1]), let nm = pdf.resolve(ocg["Name"])?.data { lname = PDFFile.text(nm) }
                }
                layers.append(lname.map { $0.uppercased().map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.reduce("") { $0 + String($1) } } ?? layerName())
            case "BMC": layers.append(layerName())
            case "EMC": _ = layers.popLast()
            case "BT": tm = Matrix(); tlm = Matrix()
            case "Tf":
                fontSize = num(1)
                if let fn = ops.first?.name {
                    if let cached = fontCache[fn] { font = cached } else {
                        let f = pdf.dict(pdf.dict(resources["Font"])?[fn])
                        let m = fontMap(f, pdf: pdf)
                        fontCache[fn] = m; font = m
                    }
                }
            case "TL": leading = num(0)
            case "Td": tlm = Matrix(e: num(0), f: num(1)) * tlm; tm = tlm
            case "TD": leading = -num(1); tlm = Matrix(e: num(0), f: num(1)) * tlm; tm = tlm
            case "Tm": tlm = Matrix(a: num(0), b: num(1), c: num(2), d: num(3), e: num(4), f: num(5)); tm = tlm
            case "T*": tlm = Matrix(f: -leading) * tlm; tm = tlm
            case "Tj": if let d = ops.first?.data { showText(decodeText(d, font)) }
            case "'": tlm = Matrix(f: -leading) * tlm; tm = tlm; if let d = ops.first?.data { showText(decodeText(d, font)) }
            case "\"": tlm = Matrix(f: -leading) * tlm; tm = tlm; if let d = ops.last?.data { showText(decodeText(d, font)) }
            case "TJ":
                let s = (ops.first?.array ?? []).compactMap { $0.data.map { decodeText($0, font) } }.joined()
                showText(s)
            case "Do":
                if let nm = ops.first?.name, let xo = pdf.resolve(pdf.dict(resources["XObject"])?[nm]), case .stream(let d, _) = xo, d["Subtype"]?.name == "Form", let body = pdf.decode(xo) {
                    var g2 = gs
                    if let m = pdf.resolve(d["Matrix"])?.array?.compactMap({ pdf.resolve($0)?.num }), m.count == 6 { g2.ctm = Matrix(a: m[0], b: m[1], c: m[2], d: m[3], e: m[4], f: m[5]) * gs.ctm }
                    run(body, resources: pdf.dict(d["Resources"]) ?? resources, pdf: pdf, gs: g2, page: page, options: o, out: &out, depth: depth + 1)
                }
            case "BI":
                // Inline image: skip to EI.
                let ei = Array("EI".utf8)
                while lx.i + 2 <= lx.b.count, !(Array(lx.b[lx.i..<(lx.i + 2)]) == ei && (lx.i == 0 || PDFLexer.isWS(lx.b[lx.i - 1]))) { lx.i += 1 }
                lx.i += 2
            default: break
            }
            ops = []
        }
    }

    // MARK: annotations → markups

    public struct Annotation { public var subtype: String; public var rect: BBox2; public var contents: String; public var author: String; public var date: String; public var shapes: [[Vec2]] }

    public static func annotations(_ pdf: PDFFile, page n: Int) -> [Annotation] {
        guard n >= 1, n <= pdf.pages.count else { return [] }
        var out: [Annotation] = []
        for a in pdf.resolve(pdf.pages[n - 1].dict["Annots"])?.array ?? [] {
            guard let d = pdf.dict(a), let st = d["Subtype"]?.name, !["Popup", "Link", "Widget"].contains(st) else { continue }
            let r = pdf.resolve(d["Rect"])?.array?.compactMap { pdf.resolve($0)?.num } ?? []
            guard r.count == 4 else { continue }
            func str(_ k: String) -> String { pdf.resolve(d[k])?.data.map(PDFFile.text) ?? "" }
            func nums(_ o: PDFObj?) -> [Double] { pdf.resolve(o)?.array?.compactMap { pdf.resolve($0)?.num } ?? [] }
            func pts(_ v: [Double]) -> [Vec2] { stride(from: 0, to: v.count - 1, by: 2).map { Vec2(v[$0], v[$0 + 1]) } }
            var shapes: [[Vec2]] = []
            switch st {
            case "Ink": shapes = (pdf.resolve(d["InkList"])?.array ?? []).map { pts(nums($0)) }
            case "Line": shapes = [pts(nums(d["L"]))]
            case "Polygon", "PolyLine": shapes = [pts(nums(d["Vertices"]))]
            case "Highlight", "Underline", "StrikeOut", "Squiggly":
                let q = pts(nums(d["QuadPoints"]))
                var k = 0
                while k + 3 < q.count { shapes.append([q[k], q[k + 1], q[k + 3], q[k + 2], q[k]]); k += 4 }
            default: break
            }
            // Date "D:20260315103000+01'00'" → ISO 8601.
            var date = str("M").isEmpty ? str("CreationDate") : str("M")
            if date.hasPrefix("D:"), date.count >= 16 {
                let s = Array(date.dropFirst(2))
                date = "\(String(s[0..<4]))-\(String(s[4..<6]))-\(String(s[6..<8]))T\(String(s[8..<10])):\(String(s[10..<12])):\(String(s[12..<14]))Z"
            }
            out.append(Annotation(subtype: st, rect: BBox2(min: Vec2(min(r[0], r[2]), min(r[1], r[3])), max: Vec2(max(r[0], r[2]), max(r[1], r[3]))),
                                  contents: str("Contents"), author: str("T"), date: date, shapes: shapes))
        }
        return out
    }

    /// Adds the annotations of a page as markups (cloud + comment, author, date), linked to the elements under each one;
    /// ink / line / polygon shapes are kept as sketches on the markup layer. Returns the markup ids.
    @discardableResult
    public static func importMarkups(_ pdf: PDFFile, page n: Int, into doc: inout ArchiDocument, options o: PDFImportOptions, level: Int? = nil) -> [String] {
        let pageBox = pdf.pages.indices.contains(n - 1) ? pdf.pages[n - 1].mediaBox : BBox2(min: .zero, max: Vec2(612, 792))
        var ids: [String] = []
        for a in annotations(pdf, page: n) {
            let lo = o.map(a.rect.min, page: pageBox), hi = o.map(a.rect.max, page: pageBox)
            let box = BBox2(points: [lo, hi])
            let lv = level ?? doc.currentLevel
            let linked = doc.elements.filter { $0.level == lv && $0.typeName != "space" && PlanRepresentation.bounds($0, doc: doc).intersects(box) }.map(\.id)
                + doc.entities.filter { $0.layer != Markups.layer && GeometryOps.bounds($0.geometry, doc: doc).intersects(box) && box.contains(GeometryOps.bounds($0.geometry, doc: doc).center) }.map(\.id)
            let title = a.subtype == "Text" || a.subtype == "FreeText" ? "PDF note" : "PDF \(a.subtype.lowercased())"
            let id = Markups.add(&doc, rect: (lo, hi), title: title, comment: a.contents.isEmpty ? "(\(a.subtype))" : a.contents, author: a.author.isEmpty ? nil : a.author,
                                 date: a.date.isEmpty ? nil : a.date, elements: linked, level: lv)
            for s in a.shapes where s.count >= 2 {
                var e = Entity(layer: Markups.layer, geometry: .polyline(PolylineGeom(points: s.map { o.map($0, page: pageBox) })))
                e.props["markupSketch"] = id
                doc.add(e)
            }
            ids.append(id)
        }
        return ids
    }

    static var commands: [CommandDef] { [
        CommandDef("PDFIMPORT", aliases: ["IMPORTPDF", "PDFIN"], category: "Insert",
                   summary: "Imports the vectors and text of a PDF page as drawing objects: paths with their colours and line widths, fills as solid hatches, text (ToUnicode aware), PDF layers (optional content) as layers; at a drawing scale and insertion point.") { ed in
            let url = try await IOCommands.path(ed, "Enter PDF file name")
            let pdf: PDFFile
            do { pdf = try PDFFile(Data(contentsOf: url)) } catch { throw CommandError.invalid("Cannot read \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            let n = try await ed.getInteger("Page number (1–\(pdf.pages.count)) <1>", defaultValue: 1) ?? 1
            var o = PDFImportOptions()
            let scale = try await ed.getReal("Drawing scale 1: <1>", defaultValue: 1).value ?? 1
            o.unitsPerPoint = 25.4 / 72 * scale / ed.doc.units.mm
            o.origin = try await ed.getPoint("Insertion point (page lower-left) <0,0>").point ?? .zero
            let ents: [Entity]
            do { ents = try PDFImport.entities(pdf, page: n, options: o) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            guard !ents.isEmpty else { throw CommandError.invalid("Page \(n) has no vector content (a scanned page? use IMAGEATTACH).") }
            var ids: [EntityID] = []
            for e in ents { ids.append(ed.doc.add(e)) }
            ed.selection = Set(ids)
            ed.print("Imported \(ents.count) object(s) from page \(n): \(Set(ents.map(\.layer)).sorted().joined(separator: ", ")).")
        },
        CommandDef("PDFMARKUPS", aliases: ["MARKUPIMPORT", "PDFCOMMENTS"], category: "Collaborate",
                   summary: "Imports the comments of a PDF page (notes, clouds/rectangles, ink, lines, highlights) as review markups with author and date, placed with the plot scale and origin and linked to the elements under them.") { ed in
            let url = try await IOCommands.path(ed, "Enter PDF file name")
            let pdf: PDFFile
            do { pdf = try PDFFile(Data(contentsOf: url)) } catch { throw CommandError.invalid("Cannot read \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            let n = try await ed.getInteger("Page number (1–\(pdf.pages.count)) <1>", defaultValue: 1) ?? 1
            var o = PDFImportOptions()
            let scale = try await ed.getReal("Plot scale 1: <100>", defaultValue: 100).value ?? 100
            o.unitsPerPoint = 25.4 / 72 * scale / ed.doc.units.mm
            o.origin = try await ed.getPoint("Drawing point at the page's lower-left corner <0,0>").point ?? .zero
            var d = ed.doc
            let ids = importMarkups(pdf, page: n, into: &d, options: o)
            guard !ids.isEmpty else { ed.print("Page \(n) has no comments."); return }
            ed.doc = d
            ed.print("Imported \(ids.count) markup(s) (MARKUP List to review them).")
        },
    ] }
}
