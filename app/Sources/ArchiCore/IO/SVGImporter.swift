// Oanarina Archi Tool — GPL-3.0-or-later
// SVG 1.1 importer: paths (all commands incl. elliptical arcs and Béziers), lines, polylines, polygons,
// circles, ellipses, rectangles (with rounded corners) and text, with nested transforms and style inheritance.
import Foundation

public struct SVGImportOptions {
    /// Drawing units per SVG user unit; nil = derive from the root width/height units (mm, cm, in, pt, pc) or 1.
    public var scale: Double?
    /// Layer for entities outside named (Inkscape) layers.
    public var layer = "SVG"
    /// Also create SOLID hatches for filled closed shapes.
    public var fillsAsHatches = false
    /// Keep SVG stroke colours as true colours (else ByLayer).
    public var keepColors = true
    /// Segments used to flatten each Bézier curve.
    public var curveSegments = 16
    public init() {}
}

public enum SVGImporter {
    /// Parses SVG text into entities (Y up, origin at the bottom-left of the viewBox).
    public static func entities(_ text: String, options: SVGImportOptions = SVGImportOptions()) throws -> [Entity] {
        guard let data = text.data(using: .utf8) else { throw SVGImportError.invalid("not UTF-8 text") }
        let d = SVGParseDelegate(options: options)
        let p = XMLParser(data: data)
        p.delegate = d
        p.shouldProcessNamespaces = false
        if !p.parse(), d.out.isEmpty {
            throw SVGImportError.invalid(p.parserError?.localizedDescription ?? "XML error")
        }
        guard d.sawSVG else { throw SVGImportError.invalid("no <svg> root element") }
        return d.out
    }

    /// Parses SVG into a new document.
    public static func read(_ text: String, options: SVGImportOptions = SVGImportOptions()) throws -> ArchiDocument {
        var doc = ArchiDocument()
        doc.elements = []; doc.entities = []
        for e in try entities(text, options: options) { doc.add(e) }
        return doc
    }

    // MARK: path data

    enum PathToken: Equatable { case cmd(Character), num(Double) }

    /// Numbers and command letters. When `arcFlags` is set, the large-arc and sweep flags of A/a commands are read
    /// as single digits, so compact forms like "a5 5 0 0110 0" parse correctly.
    static func tokenize(_ d: String, arcFlags: Bool = false) -> [PathToken] {
        var out: [PathToken] = []
        let c = Array(d.unicodeScalars)
        var i = 0
        var cmd: Character = " "
        var argIndex = 0
        while i < c.count {
            let ch = c[i]
            if CharacterSet.letters.contains(ch) && ch != "e" && ch != "E" {
                cmd = Character(ch); argIndex = 0
                out.append(.cmd(cmd)); i += 1; continue
            }
            if arcFlags && (cmd == "a" || cmd == "A") && (argIndex % 7 == 3 || argIndex % 7 == 4) && (ch == "0" || ch == "1") {
                out.append(.num(ch == "1" ? 1 : 0)); argIndex += 1; i += 1; continue
            }
            if ch == "-" || ch == "+" || ch == "." || (ch >= "0" && ch <= "9") {
                var s = String(ch); i += 1
                var seenDot = ch == ".", seenExp = false
                while i < c.count {
                    let x = c[i]
                    if x >= "0" && x <= "9" { s.unicodeScalars.append(x); i += 1 }
                    else if x == "." && !seenDot && !seenExp { seenDot = true; s.unicodeScalars.append(x); i += 1 }
                    else if (x == "e" || x == "E") && !seenExp { seenExp = true; s.unicodeScalars.append(x); i += 1
                        if i < c.count, c[i] == "-" || c[i] == "+" { s.unicodeScalars.append(c[i]); i += 1 } }
                    else { break }
                }
                if let v = Double(s) { out.append(.num(v)); argIndex += 1 }
                continue
            }
            i += 1
        }
        return out
    }

    static func tokenizeArcAware(_ d: String) -> [PathToken] { tokenize(d, arcFlags: true) }

    struct Sub { var verts: [PolyVertex] = []; var closed = false }

    /// Converts path data to polylines in SVG user space, then maps them with `t` (bulges follow the mapping's orientation).
    static func pathPolylines(_ d: String, _ t: Transform2D, segments: Int) -> [PolylineGeom] {
        let toks = tokenizeArcAware(d)
        var subs: [Sub] = []
        var cur = Sub()
        var p = Vec2.zero, start = Vec2.zero
        var lastCtrl: Vec2? = nil, lastQuad: Vec2? = nil
        var i = 0
        var cmd: Character = "M"
        let similar = isSimilarity(t)
        let sign: Double = t.determinant < 0 ? -1 : 1
        func add(_ q: Vec2, bulge: Double = 0) {
            if cur.verts.isEmpty { cur.verts.append(PolyVertex(t.apply(p))) }
            cur.verts[cur.verts.count - 1].bulge = bulge
            cur.verts.append(PolyVertex(t.apply(q)))
        }
        func flush() { if cur.verts.count >= 2 { subs.append(cur) }; cur = Sub() }
        func num() -> Double? {
            guard i < toks.count, case .num(let v) = toks[i] else { return nil }
            i += 1; return v
        }
        func hasNum() -> Bool { i < toks.count && { if case .num = toks[i] { return true }; return false }() }
        while i < toks.count {
            var fromCmd = false
            if case .cmd(let c) = toks[i] { cmd = c; i += 1; fromCmd = true }
            if (cmd == "Z" || cmd == "z") && !fromCmd { i += 1; continue } // stray numbers after Z
            let rel = cmd.isLowercase
            let base = rel ? p : Vec2.zero
            switch cmd {
            case "M", "m":
                guard let x = num(), let y = num() else { break }
                flush()
                p = Vec2(x, y) + base; start = p
                cur.verts = [PolyVertex(t.apply(p))]
                cmd = rel ? "l" : "L"
                lastCtrl = nil; lastQuad = nil
                continue
            case "L", "l":
                guard let x = num(), let y = num() else { break }
                let q = Vec2(x, y) + base; add(q); p = q
            case "H", "h":
                guard let x = num() else { break }
                let q = Vec2(rel ? p.x + x : x, p.y); add(q); p = q
            case "V", "v":
                guard let y = num() else { break }
                let q = Vec2(p.x, rel ? p.y + y : y); add(q); p = q
            case "C", "c", "S", "s":
                var c1: Vec2
                if cmd == "C" || cmd == "c" {
                    guard let x1 = num(), let y1 = num() else { break }
                    c1 = Vec2(x1, y1) + base
                } else { c1 = lastCtrl.map { p * 2 - $0 } ?? p }
                guard let x2 = num(), let y2 = num(), let x = num(), let y = num() else { break }
                let c2 = Vec2(x2, y2) + base, q = Vec2(x, y) + base
                for k in 1...segments {
                    let s = Double(k) / Double(segments), u = 1 - s
                    add(p * (u * u * u) + c1 * (3 * u * u * s) + c2 * (3 * u * s * s) + q * (s * s * s))
                }
                // `add` advanced from the path start each time; reset p only at the end.
                p = q; lastCtrl = c2; lastQuad = nil
                continue
            case "Q", "q", "T", "t":
                var c1: Vec2
                if cmd == "Q" || cmd == "q" {
                    guard let x1 = num(), let y1 = num() else { break }
                    c1 = Vec2(x1, y1) + base
                } else { c1 = lastQuad.map { p * 2 - $0 } ?? p }
                guard let x = num(), let y = num() else { break }
                let q = Vec2(x, y) + base
                for k in 1...segments {
                    let s = Double(k) / Double(segments), u = 1 - s
                    add(p * (u * u) + c1 * (2 * u * s) + q * (s * s))
                }
                p = q; lastQuad = c1; lastCtrl = nil
                continue
            case "A", "a":
                guard let rx0 = num(), let ry0 = num(), let rot = num(), let large = num(), let sweep = num(), let x = num(), let y = num() else { break }
                let q = Vec2(x, y) + base
                arc(from: p, to: q, rx: abs(rx0), ry: abs(ry0), phi: rad(rot), large: large != 0, sweep: sweep != 0,
                    similar: similar, sign: sign, segments: segments, add: add)
                p = q
            case "Z", "z":
                if let f = cur.verts.first, !p.isClose(start, tol: 1e-9) { add(start); _ = f }
                if cur.verts.count >= 2, cur.verts[0].p.isClose(cur.verts[cur.verts.count - 1].p, tol: 1e-9) {
                    let b = cur.verts[cur.verts.count - 2].bulge
                    cur.verts.removeLast()
                    cur.verts[cur.verts.count - 1].bulge = b
                }
                cur.closed = true
                p = start
                flush()
                cur.verts = [PolyVertex(t.apply(p))]
                lastCtrl = nil; lastQuad = nil
                continue
            default:
                if !fromCmd { i += 1 }
                continue
            }
            lastCtrl = nil; lastQuad = nil
        }
        flush()
        return subs.map { s -> PolylineGeom in
            var v = s.verts
            if !s.closed, !v.isEmpty { v[v.count - 1].bulge = 0 }
            if s.closed, v.count >= 2 { /* last bulge already set by the closing segment */ }
            return PolylineGeom(v, closed: s.closed)
        }
    }

    /// Elliptical arc (SVG implementation notes F.6). Circular arcs under a similarity become a bulge; others are sampled.
    static func arc(from p0: Vec2, to p1: Vec2, rx rx0: Double, ry ry0: Double, phi: Double, large: Bool, sweep: Bool,
                    similar: Bool, sign: Double, segments: Int, add: (Vec2, Double) -> Void) {
        if p0.isClose(p1, tol: 1e-12) { return }
        if rx0 < 1e-12 || ry0 < 1e-12 { add(p1, 0); return }
        var rx = rx0, ry = ry0
        let cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lam > 1 { let s = lam.squareRoot(); rx *= s; ry *= s }
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var co = den > 0 ? (num / den).squareRoot() : 0
        if large == sweep { co = -co }
        let cxp = co * rx * y1 / ry, cyp = -co * ry * x1 / rx
        let c = Vec2(cp * cxp - sp * cyp + (p0.x + p1.x) / 2, sp * cxp + cp * cyp + (p0.y + p1.y) / 2)
        func ang(_ u: Vec2, _ v: Vec2) -> Double { atan2(u.cross(v), u.dot(v)) }
        let u = Vec2((x1 - cxp) / rx, (y1 - cyp) / ry), v = Vec2((-x1 - cxp) / rx, (-y1 - cyp) / ry)
        let th1 = ang(Vec2(1, 0), u)
        var dth = ang(u, v)
        if !sweep && dth > 0 { dth -= 2 * .pi } else if sweep && dth < 0 { dth += 2 * .pi }
        if similar && abs(rx - ry) < 1e-9 * max(rx, 1) {
            // Split sweeps above 180° so bulges stay well-conditioned.
            let parts = abs(dth) > .pi * 1.0001 ? 2 : 1
            for k in 1...parts {
                let a = th1 + dth * Double(k) / Double(parts)
                let q = k == parts ? p1 : c + Vec2(rx * cos(a), rx * sin(a)).rotated(by: phi)
                add(q, sign * tan(dth / Double(parts) / 4))
            }
            return
        }
        let n = max(4, Int(abs(dth) / (.pi / 2) * Double(segments) / 2))
        for k in 1...n {
            let a = th1 + dth * Double(k) / Double(n)
            let q = k == n ? p1 : c + Vec2(rx * cos(a), ry * sin(a)).rotated(by: phi)
            add(q, 0)
        }
    }

    static func isSimilarity(_ t: Transform2D) -> Bool {
        let a = Vec2(t.a, t.b), b = Vec2(t.c, t.d)
        return abs(a.length - b.length) < 1e-9 * max(a.length, 1) && abs(a.dot(b)) < 1e-9 * max(a.lengthSquared, 1)
    }

    // MARK: transforms, colors, lengths

    static func parseTransform(_ s: String) -> Transform2D {
        var t = Transform2D.identity
        let scanner = s.replacingOccurrences(of: ",", with: " ")
        var rest = Substring(scanner)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: .whitespaces).lowercased()
            let args = rest[rest.index(after: open)..<close].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).compactMap { Double($0) }
            var m = Transform2D.identity
            switch name {
            case "matrix" where args.count == 6: m = Transform2D(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
            case "translate" where !args.isEmpty: m = .translation(Vec2(args[0], args.count > 1 ? args[1] : 0))
            case "scale" where !args.isEmpty: m = .scale(args[0], args.count > 1 ? args[1] : args[0])
            case "rotate" where !args.isEmpty: m = .rotation(rad(args[0]), around: args.count >= 3 ? Vec2(args[1], args[2]) : .zero)
            case "skewx" where !args.isEmpty: m = Transform2D(c: tan(rad(args[0])))
            case "skewy" where !args.isEmpty: m = Transform2D(b: tan(rad(args[0])))
            default: break
            }
            t = t * m
            rest = rest[rest.index(after: close)...]
        }
        return t
    }

    static let namedColors: [String: (UInt8, UInt8, UInt8)] = [
        "black": (0, 0, 0), "white": (255, 255, 255), "red": (255, 0, 0), "lime": (0, 255, 0), "green": (0, 128, 0), "blue": (0, 0, 255),
        "yellow": (255, 255, 0), "cyan": (0, 255, 255), "aqua": (0, 255, 255), "magenta": (255, 0, 255), "fuchsia": (255, 0, 255),
        "gray": (128, 128, 128), "grey": (128, 128, 128), "silver": (192, 192, 192), "maroon": (128, 0, 0), "olive": (128, 128, 0),
        "navy": (0, 0, 128), "purple": (128, 0, 128), "teal": (0, 128, 128), "orange": (255, 165, 0), "brown": (165, 42, 42),
        "pink": (255, 192, 203), "darkgray": (169, 169, 169), "darkgrey": (169, 169, 169), "lightgray": (211, 211, 211), "lightgrey": (211, 211, 211),
    ]

    /// Parses an SVG paint; nil for "none"/unparseable.
    static func parseColor(_ s: String?) -> ColorRef? {
        guard var t = s?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty, t != "none", t != "transparent" else { return nil }
        if t.hasPrefix("url(") { return nil }
        if t.hasPrefix("#") {
            t.removeFirst()
            if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
            guard t.count >= 6, let v = UInt32(t.prefix(6), radix: 16) else { return nil }
            return .rgb(UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255))
        }
        if t.hasPrefix("rgb") {
            let inner = t.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            func comp(_ p: String) -> UInt8 {
                if p.hasSuffix("%") { return UInt8(max(0, min(255, (Double(p.dropLast()) ?? 0) * 2.55)).rounded()) }
                return UInt8(max(0, min(255, Double(p) ?? 0)))
            }
            return .rgb(comp(parts[0]), comp(parts[1]), comp(parts[2]))
        }
        if let c = namedColors[t] { return .rgb(c.0, c.1, c.2) }
        return nil
    }

    /// Length with optional unit, in millimetres when `physical` (nil when unit-less or px).
    static func physicalLength(_ s: String?) -> Double? {
        guard let t = s?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        let units: [(String, Double)] = [("mm", 1), ("cm", 10), ("in", 25.4), ("pt", 25.4 / 72), ("pc", 25.4 / 6), ("m", 1000)]
        for (u, k) in units where t.hasSuffix(u) {
            if let v = Double(t.dropLast(u.count).trimmingCharacters(in: .whitespaces)) { return v * k }
        }
        return nil
    }
    static func number(_ s: String?) -> Double? {
        guard var t = s?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        for u in ["px", "mm", "cm", "in", "pt", "pc", "em", "%"] where t.hasSuffix(u) { t = String(t.dropLast(u.count)); break }
        return Double(t.trimmingCharacters(in: .whitespaces))
    }
    static func numbers(_ s: String?) -> [Double] {
        guard let s = s else { return [] }
        return tokenize(s).compactMap { if case .num(let v) = $0 { return v }; return nil }
    }
}

public enum SVGImportError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid SVG: \(m)" }; return nil }
}

final class SVGParseDelegate: NSObject, XMLParserDelegate {
    struct Style {
        var transform = Transform2D.identity
        var stroke: String? = nil
        var fill: String? = "black"
        var fontSize = 16.0
        var anchor = "start"
        var hidden = false
        var layer: String
    }
    let options: SVGImportOptions
    var out: [Entity] = []
    var stack: [Style] = []
    var skipDepth = 0
    var sawSVG = false
    var root = Transform2D.identity
    var unit = 1.0
    // text
    var textStyle: Style?
    var textPos: Vec2 = .zero
    var textLines: [(String, Double?)] = []
    var textBuffer = ""
    var tspanY: Double? = nil

    init(options: SVGImportOptions) {
        self.options = options
        super.init()
    }

    func styleAttrs(_ a: [String: String]) -> [String: String] {
        var m = a
        if let st = a["style"] {
            for decl in st.split(separator: ";") {
                let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { m[kv[0]] = kv[1] }
            }
        }
        return m
    }

    func parser(_ parser: XMLParser, didStartElement name0: String, namespaceURI: String?, qualifiedName qName: String?, attributes a0: [String: String] = [:]) {
        let name = (name0.split(separator: ":").last.map(String.init) ?? name0).lowercased()
        if skipDepth > 0 { skipDepth += 1; return }
        if ["defs", "symbol", "clippath", "mask", "pattern", "marker", "style", "metadata", "title", "desc", "lineargradient", "radialgradient", "filter"].contains(name) {
            skipDepth = 1; return
        }
        let a = styleAttrs(a0)
        var st = stack.last ?? Style(layer: options.layer)
        if name == "svg" && !sawSVG {
            sawSVG = true
            let vb = SVGImporter.numbers(a["viewBox"] ?? a["viewbox"])
            let wPhys = SVGImporter.physicalLength(a["width"])
            var s = options.scale
            if s == nil, let wp = wPhys, vb.count == 4, vb[2] > 0 { s = wp / vb[2] }
            else if s == nil, let wp = wPhys, let wn = SVGImporter.number(a["width"]), wn > 0 { s = wp / wn }
            unit = s ?? 1
            let h = vb.count == 4 ? vb[3] : (SVGImporter.number(a["height"]) ?? 0)
            let ox = vb.count == 4 ? vb[0] : 0, oy = vb.count == 4 ? vb[1] : 0
            // user (x, y) → (x - ox, (oy + h) - y) × unit
            root = Transform2D(a: unit, b: 0, c: 0, d: -unit, tx: -ox * unit, ty: (oy + h) * unit)
            st.transform = root
        }
        if let t = a["transform"] { st.transform = st.transform * SVGImporter.parseTransform(t) }
        if let v = a["stroke"] { st.stroke = v == "inherit" ? st.stroke : v }
        if let v = a["fill"] { st.fill = v == "inherit" ? st.fill : v }
        if let v = a["font-size"], let n = SVGImporter.number(v) { st.fontSize = n }
        if let v = a["text-anchor"] { st.anchor = v }
        if a["display"] == "none" || a["visibility"] == "hidden" { st.hidden = true }
        if name == "g", (a["inkscape:groupmode"] ?? a["groupmode"]) == "layer", let l = a["inkscape:label"] ?? a["label"] ?? a["id"], !l.isEmpty { st.layer = l }
        stack.append(st)
        guard !st.hidden else { return }
        let t = st.transform
        func n(_ k: String) -> Double { SVGImporter.number(a[k]) ?? 0 }
        switch name {
        case "path":
            if let d = a["d"] { for pl in SVGImporter.pathPolylines(d, t, segments: max(2, options.curveSegments)) { emit(.polyline(pl), st) } }
        case "line":
            emit(.line(LineGeom(t.apply(Vec2(n("x1"), n("y1"))), t.apply(Vec2(n("x2"), n("y2"))))), st)
        case "polyline", "polygon":
            let v = SVGImporter.numbers(a["points"])
            var pts: [Vec2] = []
            var k = 0
            while k + 1 < v.count { pts.append(t.apply(Vec2(v[k], v[k + 1]))); k += 2 }
            if pts.count >= 2 { emit(.polyline(PolylineGeom(points: pts, closed: name == "polygon")), st) }
        case "circle":
            let r = n("r")
            guard r > 0 else { break }
            emit(ellipse(Vec2(n("cx"), n("cy")), r, r, t), st)
        case "ellipse":
            let rx = n("rx"), ry = n("ry")
            guard rx > 0, ry > 0 else { break }
            emit(ellipse(Vec2(n("cx"), n("cy")), rx, ry, t), st)
        case "rect":
            let x = n("x"), y = n("y"), w = n("width"), h = n("height")
            guard w > 0, h > 0 else { break }
            var rx = SVGImporter.number(a["rx"]) ?? SVGImporter.number(a["ry"]) ?? 0
            var ry = SVGImporter.number(a["ry"]) ?? rx
            rx = min(rx, w / 2); ry = min(ry, h / 2)
            if rx > 1e-9 && ry > 1e-9 {
                let d = "M\(x + rx),\(y) H\(x + w - rx) A\(rx),\(ry) 0 0 1 \(x + w),\(y + ry) V\(y + h - ry) A\(rx),\(ry) 0 0 1 \(x + w - rx),\(y + h) H\(x + rx) A\(rx),\(ry) 0 0 1 \(x),\(y + h - ry) V\(y + ry) A\(rx),\(ry) 0 0 1 \(x + rx),\(y) Z"
                for pl in SVGImporter.pathPolylines(d, t, segments: max(2, options.curveSegments)) { emit(.polyline(pl), st) }
            } else {
                emit(.polyline(PolylineGeom(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)].map(t.apply), closed: true)), st)
            }
        case "text":
            textStyle = st
            textPos = Vec2(SVGImporter.numbers(a["x"]).first ?? 0, SVGImporter.numbers(a["y"]).first ?? 0)
            textLines = []; textBuffer = ""; tspanY = nil
        case "tspan":
            if textStyle != nil {
                if !textBuffer.isEmpty { textLines.append((textBuffer, tspanY)); textBuffer = "" }
                tspanY = SVGImporter.numbers(a["y"]).first ?? SVGImporter.numbers(a["dy"]).first.map { (tspanY ?? textPos.y) + $0 }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0, textStyle != nil { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name0: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = (name0.split(separator: ":").last.map(String.init) ?? name0).lowercased()
        if skipDepth > 0 { skipDepth -= 1; return }
        if name == "tspan", textStyle != nil {
            if !textBuffer.isEmpty { textLines.append((textBuffer, tspanY)); textBuffer = "" }
        }
        if name == "text", let st = textStyle {
            if !textBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { textLines.append((textBuffer, tspanY)) }
            let lines = textLines.map { $0.0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !lines.isEmpty, !st.hidden {
                let t = st.transform
                let firstY = textLines.first?.1 ?? textPos.y
                let pos = t.apply(Vec2(textPos.x, firstY))
                let xAxis = t.applyVector(Vec2(1, 0))
                let yLen = t.applyVector(Vec2(0, 1)).length
                let rot = normAngle(xAxis.angle)
                let h = st.fontSize * 0.717 * yLen
                let ha: HAlign = st.anchor == "middle" ? .center : (st.anchor == "end" ? .right : .left)
                var e = Entity(layer: st.layer, color: colorRef(st, preferFill: true), geometry: .text(TextGeom(position: pos, height: max(h, 1e-6), content: lines.joined(separator: "\n"), rotation: rot < 1e-9 || abs(rot - 2 * .pi) < 1e-9 ? 0 : rot, halign: ha)))
                e.props = [:]
                out.append(e)
            }
            textStyle = nil
        }
        if !stack.isEmpty { stack.removeLast() }
    }

    func ellipse(_ c: Vec2, _ rx: Double, _ ry: Double, _ t: Transform2D) -> Geometry {
        let ax = t.applyVector(Vec2(rx, 0)), ay = t.applyVector(Vec2(0, ry))
        let center = t.apply(c)
        if abs(ax.dot(ay)) < 1e-9 * max(ax.lengthSquared, ay.lengthSquared, 1) {
            if abs(ax.length - ay.length) < 1e-9 * max(ax.length, 1) { return .circle(CircleGeom(center, ax.length)) }
            let (major, minor) = ax.length >= ay.length ? (ax, ay) : (ay, ax)
            return .ellipse(EllipseGeom(center: center, majorAxis: major, ratio: minor.length / major.length))
        }
        // Skewed: sample as a closed polyline.
        let pts = (0..<64).map { i -> Vec2 in let a = 2 * Double.pi * Double(i) / 64; return center + ax * cos(a) + ay * sin(a) }
        return .polyline(PolylineGeom(points: pts, closed: true))
    }

    func colorRef(_ st: Style, preferFill: Bool = false) -> ColorRef {
        guard options.keepColors else { return .byLayer }
        let c = preferFill ? (SVGImporter.parseColor(st.fill) ?? SVGImporter.parseColor(st.stroke)) : (SVGImporter.parseColor(st.stroke) ?? SVGImporter.parseColor(st.fill))
        return c ?? .byLayer
    }

    func emit(_ g: Geometry, _ st: Style) {
        let hasStroke = SVGImporter.parseColor(st.stroke) != nil
        let fill = SVGImporter.parseColor(st.fill)
        let area: Bool
        switch g {
        case .polyline(let pl): area = pl.closed
        case .circle, .ellipse: area = true
        default: area = false
        }
        guard hasStroke || (area && fill != nil) else { return } // invisible
        out.append(Entity(layer: st.layer, color: colorRef(st), geometry: g))
        if options.fillsAsHatches, let fc = fill {
            var loop: [PolyVertex]?
            switch g {
            case .polyline(let pl) where pl.closed && pl.vertices.count >= 3: loop = pl.vertices
            case .circle(let c): loop = [PolyVertex(c.center + Vec2(c.radius, 0), bulge: 1), PolyVertex(c.center - Vec2(c.radius, 0), bulge: 1)]
            case .ellipse(let e): loop = GeometryOps.ellipsePoints(e).map { PolyVertex($0) }
            default: break
            }
            if let l = loop { out.append(Entity(layer: st.layer, color: options.keepColors ? fc : .byLayer, geometry: .hatch(HatchGeom(loops: [l], pattern: "SOLID")))) }
        }
    }
}
