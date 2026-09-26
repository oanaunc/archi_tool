// Oanarina Archi Tool — GPL-3.0-or-later
// Colour-blind safety (SYS-030): simulation of protanopia, deuteranopia and tritanopia (Machado, Oliveira & Fernandes
// 2009, severity 1, in linear sRGB), perceptual colour difference CIEDE2000 (Sharma, Wu & Dalal 2005) in CIELAB (D65),
// a check of the drawing's layer colours (pairs that normal vision tells apart but a colour-vision deficiency merges,
// and colours that vanish against the background), and a fix that re-colours the conflicting layers from the Okabe–Ito
// palette (Okabe & Ito 2002), choosing for each layer the colour that stays most distinct under every deficiency.
import Foundation

public enum ColourAccessibility {
    public enum Deficiency: String, CaseIterable { case protanopia, deuteranopia, tritanopia }

    /// Okabe–Ito colour-blind safe palette (without black and white, which depend on the background).
    public static let okabeIto: [(name: String, color: RGBA)] = [
        ("Orange", RGBA(hex: "E69F00")), ("Sky blue", RGBA(hex: "56B4E9")), ("Bluish green", RGBA(hex: "009E73")),
        ("Yellow", RGBA(hex: "F0E442")), ("Blue", RGBA(hex: "0072B2")), ("Vermillion", RGBA(hex: "D55E00")),
        ("Reddish purple", RGBA(hex: "CC79A7")), ("Grey", RGBA(hex: "999999")),
    ]

    static let machado: [Deficiency: [Double]] = [
        .protanopia: [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998],
        .deuteranopia: [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881],
        .tritanopia: [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900],
    ]

    static func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func toSRGB(_ c: Double) -> Double { let v = max(0, min(1, c)); return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    /// How the colour looks with the deficiency.
    public static func simulate(_ c: RGBA, _ d: Deficiency) -> RGBA {
        let m = machado[d]!
        let r = toLinear(c.r), g = toLinear(c.g), b = toLinear(c.b)
        return RGBA(toSRGB(m[0] * r + m[1] * g + m[2] * b), toSRGB(m[3] * r + m[4] * g + m[5] * b), toSRGB(m[6] * r + m[7] * g + m[8] * b), c.a)
    }

    /// CIELAB (D65) of an sRGB colour.
    public static func lab(_ c: RGBA) -> (L: Double, a: Double, b: Double) {
        let r = toLinear(c.r), g = toLinear(c.g), bl = toLinear(c.b)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * bl) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * bl
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * bl) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : t / (3 * pow(6.0 / 29, 2)) + 4.0 / 29 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    /// CIEDE2000 colour difference of two CIELAB colours.
    public static func deltaE2000(_ p: (L: Double, a: Double, b: Double), _ q: (L: Double, a: Double, b: Double)) -> Double {
        let rad = Double.pi / 180
        let c1 = (p.a * p.a + p.b * p.b).squareRoot(), c2 = (q.a * q.a + q.b * q.b).squareRoot()
        let cb = (c1 + c2) / 2
        let g = 0.5 * (1 - (pow(cb, 7) / (pow(cb, 7) + pow(25, 7))).squareRoot())
        let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
        let c1p = (a1 * a1 + p.b * p.b).squareRoot(), c2p = (a2 * a2 + q.b * q.b).squareRoot()
        func hue(_ b: Double, _ a: Double) -> Double { if a == 0 && b == 0 { return 0 }; let h = atan2(b, a) / rad; return h < 0 ? h + 360 : h }
        let h1 = hue(p.b, a1), h2 = hue(q.b, a2)
        let dL = q.L - p.L, dC = c2p - c1p
        var dh = 0.0
        if c1p * c2p != 0 { dh = h2 - h1; if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 } }
        let dH = 2 * (c1p * c2p).squareRoot() * sin(dh / 2 * rad)
        let lb = (p.L + q.L) / 2, cbp = (c1p + c2p) / 2
        var hb = h1 + h2
        if c1p * c2p != 0 {
            if abs(h1 - h2) <= 180 { hb = (h1 + h2) / 2 } else if h1 + h2 < 360 { hb = (h1 + h2 + 360) / 2 } else { hb = (h1 + h2 - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hb - 30) * rad) + 0.24 * cos(2 * hb * rad) + 0.32 * cos((3 * hb + 6) * rad) - 0.20 * cos((4 * hb - 63) * rad)
        let dTheta = 30 * exp(-pow((hb - 275) / 25, 2))
        let rc = 2 * (pow(cbp, 7) / (pow(cbp, 7) + pow(25, 7))).squareRoot()
        let sl = 1 + 0.015 * pow(lb - 50, 2) / (20 + pow(lb - 50, 2)).squareRoot()
        let sc = 1 + 0.045 * cbp, sh = 1 + 0.015 * cbp * t
        let rt = -sin(2 * dTheta * rad) * rc
        return (pow(dL / sl, 2) + pow(dC / sc, 2) + pow(dH / sh, 2) + rt * (dC / sc) * (dH / sh)).squareRoot()
    }

    public static func difference(_ a: RGBA, _ b: RGBA, _ d: Deficiency? = nil) -> Double {
        let x = d.map { simulate(a, $0) } ?? a, y = d.map { simulate(b, $0) } ?? b
        return deltaE2000(lab(x), lab(y))
    }
    /// Smallest difference over normal vision and the three deficiencies.
    public static func worstDifference(_ a: RGBA, _ b: RGBA) -> Double {
        ([nil] + Deficiency.allCases.map { Optional($0) }).map { difference(a, b, $0) }.min() ?? 0
    }

    public struct Issue: Hashable {
        public var layers: [String]
        public var deficiency: Deficiency?
        public var difference: Double
        public var message: String
    }

    /// Layer colour conflicts: distinct colours that merge for a deficiency, and colours too close to the background.
    public static func check(_ doc: ArchiDocument, background: RGBA, threshold: Double = 10) -> [Issue] {
        let layers = doc.layers.filter { $0.visible && !$0.frozen }
        var out: [Issue] = []
        for (i, a) in layers.enumerated() {
            for b in layers[(i + 1)...] {
                let normal = difference(a.color, b.color)
                guard normal >= threshold else { continue }
                if let (d, v) = Deficiency.allCases.map({ ($0, difference(a.color, b.color, $0)) }).min(by: { $0.1 < $1.1 }), v < threshold {
                    out.append(Issue(layers: [a.name, b.name], deficiency: d, difference: v,
                                     message: "Layers \(a.name) (\(a.color.hex)) and \(b.name) (\(b.color.hex)) look alike with \(d.rawValue) (ΔE00 \(fmt(v, 1)), normal \(fmt(normal, 1)))"))
                }
            }
            let bg = worstDifference(a.color, background)
            if bg < threshold {
                out.append(Issue(layers: [a.name], deficiency: nil, difference: bg, message: "Layer \(a.name) (\(a.color.hex)) is hard to see on the \(background.hex) background (ΔE00 \(fmt(bg, 1)))"))
            }
        }
        return out
    }

    /// Re-colours the layers involved in conflicts with Okabe–Ito colours (plus black or white for contrast), keeping
    /// the others. Returns the changes (layer, old, new).
    @discardableResult
    public static func fix(_ doc: inout ArchiDocument, background: RGBA, threshold: Double = 10) -> [(layer: String, from: RGBA, to: RGBA)] {
        let issues = check(doc, background: background, threshold: threshold)
        let conflicted = Set(issues.flatMap(\.layers))
        guard !conflicted.isEmpty else { return [] }
        let dark = lab(background).L < 50
        let palette = okabeIto.map(\.color) + [dark ? RGBA(1, 1, 1) : RGBA(0, 0, 0)]
        var fixed: [String: RGBA] = [:]
        for l in doc.layers where !conflicted.contains(l.name) { fixed[l.name] = l.color }
        var changes: [(String, RGBA, RGBA)] = []
        // Most used palette colours are reused only when every colour is taken.
        for i in doc.layers.indices where conflicted.contains(doc.layers[i].name) {
            let others = Array(fixed.values)
            let best = palette.max { a, b in
                func score(_ c: RGBA) -> Double { ([background] + others).map { worstDifference(c, $0) }.min() ?? 100 }
                return score(a) < score(b)
            }!
            changes.append((doc.layers[i].name, doc.layers[i].color, best))
            doc.layers[i].color = best
            fixed[doc.layers[i].name] = best
        }
        return changes
    }

    static var command: CommandDef {
        CommandDef("COLORBLINDCHECK", aliases: ["CVDCHECK", "COLOURBLINDCHECK", "ACCESSIBLECOLORS"], category: "Analysis",
                   summary: "Checks layer colours for colour-blind safety (protanopia, deuteranopia, tritanopia; CIEDE2000) against the background; Fix re-colours the conflicting layers from the Okabe–Ito palette.") { ed in
            let bgk = try await ed.getKeyword("Background [Dark/Light]", ["Dark", "Light"], defaultValue: "Dark") ?? "Dark"
            let bg = bgk == "Light" ? RGBA(1, 1, 1) : RGBA(0.12, 0.12, 0.13)
            let issues = check(ed.doc, background: bg)
            guard !issues.isEmpty else { ed.print("Layer colours are colour-blind safe on the \(bgk.lowercased()) background."); return }
            for (i, it) in issues.enumerated() { ed.print("\(i + 1). " + it.message) }
            guard try await ed.getKeyword("Fix with the Okabe–Ito palette? [Yes/No]", ["Yes", "No"], defaultValue: "No") == "Yes" else { return }
            var d = ed.doc
            let ch = fix(&d, background: bg)
            ed.doc = d
            for c in ch { ed.print("\(c.layer): \(c.from.hex) → \(c.to.hex)") }
            ed.print("\(ch.count) layer colour(s) changed; \(check(d, background: bg).count) issue(s) remain.")
        }
    }
}
