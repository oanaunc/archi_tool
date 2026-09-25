// Oanarina Archi Tool — GPL-3.0-or-later
// IGES 5.3 (ANSI/US PRO/IPO-100) import and export of 2D/3D wireframe geometry (IO-041): lines (110), circular arcs and
// circles (100), copious data polylines (106 forms 11/12/63), rational B-spline curves (126, evaluated on import),
// points (116) and composite curves (102, their members). Fixed 80-column records with Start, Global, Directory Entry,
// Parameter Data and Terminate sections; units from the global section; colour numbers 1–8.
import Foundation

public enum IGES {
    public struct IGESError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    static func unitFlag(_ u: Units) -> (Int, String) {
        switch u { case .inches: return (1, "IN"); case .feet: return (4, "FT"); case .meters: return (6, "M"); case .centimeters: return (10, "CM"); case .millimeters: return (2, "MM") }
    }
    static func mmPerUnit(flag: Int) -> Double {
        switch flag { case 1: return 25.4; case 2: return 1; case 3: return 25.4 / 1000 * 1000 / 1000; case 4: return 304.8; case 5: return 1_609_344; case 6: return 1000; case 7: return 1_000_000; case 8: return 0.0254; case 9: return 0.001; case 10: return 10; case 11: return 0.0000254; default: return 1 }
    }
    /// IGES colour numbers: 1 black, 2 red, 3 green, 4 blue, 5 yellow, 6 magenta, 7 cyan, 8 white.
    static let colors: [(Int, RGBA)] = [(2, RGBA(1, 0, 0)), (3, RGBA(0, 1, 0)), (4, RGBA(0, 0, 1)), (5, RGBA(1, 1, 0)), (6, RGBA(1, 0, 1)), (7, RGBA(0, 1, 1)), (8, RGBA(1, 1, 1)), (1, RGBA(0, 0, 0))]

    static func hollerith(_ s: String) -> String { let a = s.unicodeScalars.filter { $0.isASCII }.map(String.init).joined(); return "\(a.count)H\(a)" }
    static func real(_ v: Double) -> String {
        guard v.isFinite else { return "0.0" }
        var s = fmt(v, 8)
        if s == "-0" { s = "0" }
        return s.contains(".") ? s : s + ".0"
    }

    // MARK: export

    public static func export(_ doc: ArchiDocument, author: String = "") -> String {
        struct Item { var type: Int; var form: Int; var params: [String]; var color: Int }
        var items: [Item] = []
        let visible = Set(doc.layers.filter { $0.visible && !$0.frozen }.map { $0.name.lowercased() })
        func color(_ e: Entity) -> Int {
            let c: RGBA? = { switch e.color { case .aci(let i): return aciColor(i); case .rgb(let r, let g, let b): return RGBA(Double(r) / 255, Double(g) / 255, Double(b) / 255); default: return doc.layer(named: e.layer)?.color } }()
            guard let c else { return 0 }
            return colors.min { a, b in pow(a.1.r - c.r, 2) + pow(a.1.g - c.g, 2) + pow(a.1.b - c.b, 2) < pow(b.1.r - c.r, 2) + pow(b.1.g - c.g, 2) + pow(b.1.b - c.b, 2) }?.0 ?? 0
        }
        func polyline(_ pts: [Vec2], z: Double, closed: Bool, col: Int) {
            var p = pts
            if closed, let f = pts.first { p.append(f) }
            guard p.count >= 2 else { return }
            items.append(Item(type: 106, form: 11, params: ["106", "1", "\(p.count)", real(z)] + p.flatMap { [real($0.x), real($0.y)] }, color: col))
        }
        for e in doc.entities where visible.contains(e.layer.lowercased()) {
            let col = color(e)
            let z = Double(e.props["z"] ?? "") ?? 0
            switch e.geometry {
            case .line(let l):
                items.append(Item(type: 110, form: 0, params: ["110", real(l.a.x), real(l.a.y), real(z), real(l.b.x), real(l.b.y), real(z)], color: col))
            case .circle(let c):
                let s = c.center + Vec2(c.radius, 0)
                items.append(Item(type: 100, form: 0, params: ["100", real(z), real(c.center.x), real(c.center.y), real(s.x), real(s.y), real(s.x), real(s.y)], color: col))
            case .arc(let a):
                items.append(Item(type: 100, form: 0, params: ["100", real(z), real(a.center.x), real(a.center.y), real(a.startPoint.x), real(a.startPoint.y), real(a.endPoint.x), real(a.endPoint.y)], color: col))
            case .point(let p):
                items.append(Item(type: 116, form: 0, params: ["116", real(p.x), real(p.y), real(z), "0"], color: col))
            case .polyline(let pl) where pl.vertices.allSatisfy({ abs($0.bulge) < 1e-12 }):
                polyline(pl.vertices.map(\.p), z: z, closed: pl.closed, col: col)
            case .polyline, .ellipse, .spline:
                for pts in GeometryOps.tessellate(e.geometry, doc: doc) { polyline(pts, z: z, closed: false, col: col) }
            default:
                continue
            }
        }
        // Records.
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
        func right(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.suffix(n)) : String(repeating: " ", count: n - s.count) + s }
        func seq(_ c: Character, _ n: Int) -> String { String(c) + right("\(n)", 7) }
        /// Splits free-format text into 72- (or 64-) column chunks at delimiters where possible.
        func chunks(_ text: String, width: Int) -> [String] {
            var out: [String] = [], cur = ""
            var tokens: [String] = []
            var t = ""
            for ch in text { t.append(ch); if ch == "," || ch == ";" { tokens.append(t); t = "" } }
            if !t.isEmpty { tokens.append(t) }
            for tok in tokens {
                if cur.count + tok.count > width && !cur.isEmpty { out.append(cur); cur = "" }
                var x = tok
                while x.count > width { out.append(String(x.prefix(width))); x = String(x.dropFirst(width)) }
                cur += x
            }
            if !cur.isEmpty { out.append(cur) }
            return out
        }
        let start = ["Oanarina Archi Tool IGES export: \(doc.info.name)"]
        let (uf, un) = unitFlag(doc.units)
        let iso = DateFormatter(); iso.dateFormat = "yyyyMMdd.HHmmss"; iso.locale = Locale(identifier: "en_US_POSIX"); iso.timeZone = TimeZone(identifier: "UTC")
        let date = iso.string(from: Date())
        var ext = BBox2.empty
        for e in doc.entities { ext.add(GeometryOps.bounds(e.geometry, doc: doc)) }
        let maxC = ext.isEmpty ? 0 : max(abs(ext.min.x), abs(ext.min.y), abs(ext.max.x), abs(ext.max.y))
        let global = [",", ";", hollerith(doc.info.name), hollerith(doc.info.name + ".igs"), hollerith("Oanarina Archi Tool"), hollerith("1.0"),
                      "32", "38", "6", "308", "15", hollerith(doc.info.name), "1.0", "\(uf)", hollerith(un), "1", "1.0", hollerith(date), real(0.001 * 1 / doc.units.mm),
                      real(maxC), hollerith(author.isEmpty ? doc.info.author : author), hollerith("Oanarina"), "11", "0", hollerith(date)]
        let globalText = "1H,,1H;," + global.dropFirst(2).joined(separator: ",") + ";"
        var S = start.enumerated().map { pad($0.element, 72) + seq("S", $0.offset + 1) }
        if S.isEmpty { S = [pad("", 72) + seq("S", 1)] }
        let G = chunks(globalText, width: 72).enumerated().map { pad($0.element, 72) + seq("G", $0.offset + 1) }
        var D: [String] = [], P: [String] = []
        for (i, it) in items.enumerated() {
            let deSeq = 2 * i + 1
            let text = it.params.joined(separator: ",") + ";"
            let lines = chunks(text, width: 64)
            let pStart = P.count + 1
            for l in lines { P.append(pad(l, 64) + right("\(deSeq)", 8) + seq("P", P.count + 1)) }
            let f1 = [right("\(it.type)", 8), right("\(pStart)", 8), right("0", 8), right("1", 8), right("0", 8), right("0", 8), right("0", 8), right("0", 8), "00000000"]
            let f2 = [right("\(it.type)", 8), right("0", 8), right("\(it.color)", 8), right("\(lines.count)", 8), right("\(it.form)", 8), pad("", 8), pad("", 8), pad("", 8), right("0", 8)]
            D.append(f1.joined() + seq("D", deSeq)); D.append(f2.joined() + seq("D", deSeq + 1))
        }
        let T = pad("S" + right("\(S.count)", 7) + "G" + right("\(G.count)", 7) + "D" + right("\(D.count)", 7) + "P" + right("\(P.count)", 7), 72) + seq("T", 1)
        return (S + G + D + P + [T]).joined(separator: "\n") + "\n"
    }

    // MARK: import

    /// Splits IGES free-format parameters (Hollerith strings aware).
    static func params(_ text: String, delim: Character = ",", end: Character = ";") -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == end { out.append(cur.trimmingCharacters(in: .whitespaces)); return out }
            if c == delim { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; i += 1; continue }
            // Hollerith: digits then H.
            if c.isNumber, cur.trimmingCharacters(in: .whitespaces).isEmpty {
                var j = i, n = 0
                while j < chars.count, chars[j].isNumber { n = n * 10 + Int(String(chars[j]))!; j += 1 }
                if j < chars.count, chars[j] == "H" {
                    let s = j + 1, e = min(chars.count, s + n)
                    cur = String(chars[s..<e]); i = e; continue
                }
            }
            cur.append(c); i += 1
        }
        if !cur.isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }
    static func dbl(_ s: String) -> Double { Double(s.replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")) ?? 0 }

    /// Reads an IGES file into entities in millimetres (layer IMPORT-IGES; z kept in props).
    public static func read(_ text: String) throws -> [Entity] {
        var sec: [Character: [String]] = [:]
        for raw in text.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: true) {
            let l = String(raw)
            guard l.count >= 73 else { continue }
            let c = l[l.index(l.startIndex, offsetBy: 72)]
            sec[c, default: []].append(l)
        }
        guard let d = sec["D"], !d.isEmpty, let p = sec["P"] else { throw IGESError(message: "Not an IGES file (no directory or parameter section).") }
        // Global: delimiters may be redefined in its first two parameters.
        let gText = (sec["G"] ?? []).map { String($0.prefix(72)) }.joined()
        var delim: Character = ",", end: Character = ";"
        if gText.hasPrefix("1H") { delim = gText[gText.index(gText.startIndex, offsetBy: 2)] }
        let g = params(gText, delim: delim, end: ";")
        if g.count > 1, g[1].count == 1 { end = Character(g[1]) }
        let scale = g.count > 12 ? (Double(g[12]) ?? 1) : 1
        let unitFlag = g.count > 13 ? (Int(g[13]) ?? 2) : 2
        let k = mmPerUnit(flag: unitFlag) / (scale == 0 ? 1 : scale)
        func field(_ line: String, _ n: Int) -> String {
            let s = line.index(line.startIndex, offsetBy: n * 8), e = line.index(s, offsetBy: 8)
            return String(line[s..<e]).trimmingCharacters(in: .whitespaces)
        }
        let pData = p.map { (String($0.prefix(64)), Int(String($0.dropFirst(64).prefix(8)).trimmingCharacters(in: .whitespaces)) ?? 0) }
        var out: [Entity] = []
        var i = 0
        var memberOfComposite = Set<Int>()
        struct DE { var seq: Int; var type: Int; var pStart: Int; var pCount: Int; var form: Int; var color: Int; var status: String }
        var des: [DE] = []
        while i + 1 < d.count {
            let a = d[i], b = d[i + 1]
            des.append(DE(seq: i + 1, type: Int(field(a, 0)) ?? 0, pStart: Int(field(a, 1)) ?? 0, pCount: Int(field(b, 3)) ?? 1, form: Int(field(b, 4)) ?? 0,
                          color: Int(field(b, 2)) ?? 0, status: field(a, 8)))
            i += 2
        }
        func paramsOf(_ de: DE) -> [String] {
            guard de.pStart >= 1, de.pStart - 1 < pData.count else { return [] }
            let lines = pData[(de.pStart - 1)..<min(pData.count, de.pStart - 1 + max(de.pCount, 1))].map(\.0).joined()
            return params(lines, delim: delim, end: end)
        }
        for de in des where de.type == 102 { let pr = paramsOf(de); if let n = Int(pr.count > 1 ? pr[1] : "") { for j in 0..<n where j + 2 < pr.count { if let ptr = Int(pr[j + 2]) { memberOfComposite.insert(ptr) } } } }
        for de in des {
            // Status digits 3–4 "01" = physically dependent (e.g. members of a composite): drawn through the composite… but
            // members carry the geometry, so they are read, the composite itself is skipped.
            let pr = paramsOf(de).map(dbl)
            func P3(_ o: Int) -> Vec3 { Vec3(pr[o] * k, pr[o + 1] * k, pr[o + 2] * k) }
            var e: Entity?
            switch de.type {
            case 110 where pr.count >= 7:
                let a = P3(1), b = P3(4)
                e = Entity(layer: "IMPORT-IGES", geometry: .line(LineGeom(a.xy, b.xy)), props: a.z != 0 ? ["z": fmt(a.z, 4)] : [:])
            case 100 where pr.count >= 8:
                let zt = pr[1] * k, c = Vec2(pr[2], pr[3]) * k, s = Vec2(pr[4], pr[5]) * k, t = Vec2(pr[6], pr[7]) * k
                let r = c.distance(to: s)
                guard r > 1e-12 else { continue }
                if s.distance(to: t) < 1e-9 * max(1, r) { e = Entity(layer: "IMPORT-IGES", geometry: .circle(CircleGeom(c, r))) }
                else { e = Entity(layer: "IMPORT-IGES", geometry: .arc(ArcGeom(c, r, (s - c).angle, (t - c).angle))) }
                if zt != 0 { e?.props["z"] = fmt(zt, 4) }
            case 116 where pr.count >= 4:
                e = Entity(layer: "IMPORT-IGES", geometry: .point(P3(1).xy))
            case 106 where pr.count >= 3:
                let ip = Int(pr[1]), n = Int(pr[2])
                var pts: [Vec2] = []
                if ip == 1 { for j in 0..<n where 4 + 2 * j + 1 < pr.count { pts.append(Vec2(pr[4 + 2 * j], pr[5 + 2 * j]) * k) } }
                else { let stride = ip == 3 ? 6 : 3; for j in 0..<n where 3 + stride * j + 2 < pr.count { pts.append(Vec2(pr[3 + stride * j], pr[4 + stride * j]) * k) } }
                guard pts.count >= 2 else { continue }
                let closed = pts.count > 2 && pts.first!.distance(to: pts.last!) < 1e-9 * max(1, k)
                if closed { pts.removeLast() }
                e = Entity(layer: "IMPORT-IGES", geometry: .polyline(PolylineGeom(points: pts, closed: closed)))
            case 126 where pr.count >= 7:
                let K = Int(pr[1]), M = Int(pr[2])
                let nKnots = K + M + 2
                let knotsStart = 7, wStart = knotsStart + nKnots, cpStart = wStart + K + 1
                guard cpStart + 3 * (K + 1) <= pr.count, K >= 1, M >= 1 else { continue }
                let knots = Array(pr[knotsStart..<wStart]), weights = Array(pr[wStart..<cpStart])
                let cps = (0...K).map { Vec2(pr[cpStart + 3 * $0], pr[cpStart + 3 * $0 + 1]) * k }
                let polynomial = Int(pr[5]) == 1 && weights.allSatisfy { abs($0 - 1) < 1e-12 }
                e = Entity(layer: "IMPORT-IGES", geometry: .spline(SplineGeom(degree: M, controlPoints: cps, knots: knots, weights: polynomial ? nil : weights)))
            default: continue
            }
            guard var ent = e else { continue }
            if de.color != 0, let c = colors.first(where: { $0.0 == de.color })?.1 {
                let r = UInt8((c.r * 255).rounded()), gg = UInt8((c.g * 255).rounded()), b = UInt8((c.b * 255).rounded())
                ent.color = .rgb(r, gg, b)
            }
            out.append(ent)
        }
        _ = memberOfComposite
        if out.isEmpty { throw IGESError(message: "The IGES file has no supported curves (lines, arcs, polylines, splines, points).") }
        return out
    }
}
