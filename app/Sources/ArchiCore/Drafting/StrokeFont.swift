// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Built-in single-stroke CAD font (clean-room, drawn on a 9-unit cap-height grid: baseline y = 0, x-height 6,
/// descenders to −3). Covers printable ASCII, the degree/plus-minus/diameter signs and Latin letters with the common
/// accents (decomposed into base letter + accent strokes). Used by TXTEXP to turn any text into line geometry and by
/// anything else that needs text as vectors (plotter output, engraving).
public enum StrokeFont {
    /// Grid units per cap height.
    public static let capHeight = 9.0
    /// Gap between glyphs in grid units.
    public static let letterGap = 2.0
    /// Line spacing as a multiple of the text height (AutoCAD's 1.667 for single spacing).
    public static let lineSpacing = 5.0 / 3.0

    struct Glyph { let width: Double; let strokes: [[Vec2]] }

    /// Glyph table: character → (width, "x,y x,y|x,y …" strokes).
    static let table: [Character: (Double, String)] = [
        " ": (4, ""),
        "A": (6, "0,0 3,9 6,0|1,3 5,3"),
        "B": (6, "0,0 0,9 4.5,9 6,7.5 6,6 4.5,4.5 0,4.5|4.5,4.5 6,3 6,1.5 4.5,0 0,0"),
        "C": (6, "6,1.5 4.5,0 1.5,0 0,1.5 0,7.5 1.5,9 4.5,9 6,7.5"),
        "D": (6, "0,0 0,9 4,9 6,7 6,2 4,0 0,0"),
        "E": (6, "6,0 0,0 0,9 6,9|0,4.5 4,4.5"),
        "F": (6, "0,0 0,9 6,9|0,4.5 4,4.5"),
        "G": (6, "6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0 4.5,0 6,1.5 6,4 3.5,4"),
        "H": (6, "0,0 0,9|6,0 6,9|0,4.5 6,4.5"),
        "I": (3, "0,0 3,0|1.5,0 1.5,9|0,9 3,9"),
        "J": (5, "0,1.5 1.5,0 3.5,0 5,1.5 5,9"),
        "K": (6, "0,0 0,9|6,9 0,3|2,5 6,0"),
        "L": (5, "0,9 0,0 5,0"),
        "M": (7, "0,0 0,9 3.5,3 7,9 7,0"),
        "N": (6, "0,0 0,9 6,0 6,9"),
        "O": (6, "1.5,0 4.5,0 6,1.5 6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0"),
        "P": (6, "0,0 0,9 4.5,9 6,7.5 6,6 4.5,4.5 0,4.5"),
        "Q": (6, "1.5,0 4.5,0 6,1.5 6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0|3.5,2.5 6.5,-0.5"),
        "R": (6, "0,0 0,9 4.5,9 6,7.5 6,6 4.5,4.5 0,4.5|3,4.5 6,0"),
        "S": (6, "6,7.5 4.5,9 1.5,9 0,7.5 0,6 1.5,4.5 4.5,4.5 6,3 6,1.5 4.5,0 1.5,0 0,1.5"),
        "T": (6, "0,9 6,9|3,9 3,0"),
        "U": (6, "0,9 0,1.5 1.5,0 4.5,0 6,1.5 6,9"),
        "V": (6, "0,9 3,0 6,9"),
        "W": (7, "0,9 1.75,0 3.5,6 5.25,0 7,9"),
        "X": (6, "0,0 6,9|0,9 6,0"),
        "Y": (6, "0,9 3,4.5 6,9|3,4.5 3,0"),
        "Z": (6, "0,9 6,9 0,0 6,0"),
        "a": (5, "0.5,5.5 1.5,6 4,6 5,5 5,0|5,3.5 1.5,3.5 0,2.5 0,1 1,0 3.5,0 5,1"),
        "b": (5, "0,9 0,0|0,4.5 1.5,6 3.5,6 5,4.5 5,1.5 3.5,0 1.5,0 0,1.5"),
        "c": (5, "5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0 3.5,0 5,1.5"),
        "d": (5, "5,9 5,0|5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0 3.5,0 5,1.5"),
        "e": (5, "0,3 5,3 5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0 3.5,0 5,1"),
        "f": (4, "4,9 2.5,9 1.5,8 1.5,0|0,6 3.5,6"),
        "g": (5, "5,6 5,-1.5 3.5,-3 1.5,-3 0.5,-2.5|5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0 3.5,0 5,1.5"),
        "h": (5, "0,9 0,0|0,4.5 1.5,6 3.5,6 5,4.5 5,0"),
        "i": (2, "1,0 1,6|1,8 1,8.8"),
        "j": (3, "2,6 2,-2 1,-3 0,-3|2,8 2,8.8"),
        "k": (5, "0,9 0,0|4.5,6 0,2|1.5,3.2 5,0"),
        "l": (2, "1,9 1,0"),
        "m": (7, "0,6 0,0|0,4.5 1.2,6 2.3,6 3.5,4.5 3.5,0|3.5,4.5 4.7,6 5.8,6 7,4.5 7,0"),
        "n": (5, "0,6 0,0|0,4.5 1.5,6 3.5,6 5,4.5 5,0"),
        "o": (5, "1.5,0 3.5,0 5,1.5 5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0"),
        "p": (5, "0,6 0,-3|0,4.5 1.5,6 3.5,6 5,4.5 5,1.5 3.5,0 1.5,0 0,1.5"),
        "q": (5, "5,6 5,-3|5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0 3.5,0 5,1.5"),
        "r": (4, "0,6 0,0|0,3.5 2.5,6 4,6"),
        "s": (5, "5,5 4,6 1,6 0,5 0,4 1,3 4,3 5,2 5,1 4,0 1,0 0,1"),
        "t": (4, "1.5,9 1.5,1 2.5,0 4,0|0,6 3.5,6"),
        "u": (5, "0,6 0,1.5 1.5,0 3.5,0 5,1.5|5,6 5,0"),
        "v": (5, "0,6 2.5,0 5,6"),
        "w": (7, "0,6 1.5,0 3.5,4.5 5.5,0 7,6"),
        "x": (5, "0,6 5,0|0,0 5,6"),
        "y": (5, "0,6 2.5,0|5,6 1.5,-3 0.5,-3"),
        "z": (5, "0,6 5,6 0,0 5,0"),
        "0": (6, "1.5,0 4.5,0 6,1.5 6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0|1,1.5 5,7.5"),
        "1": (6, "1.5,7.5 3,9 3,0|1.5,0 4.5,0"),
        "2": (6, "0,7.5 1.5,9 4.5,9 6,7.5 6,6 0,0 6,0"),
        "3": (6, "0,7.5 1.5,9 4.5,9 6,7.5 6,6 4.5,4.5 2.5,4.5|4.5,4.5 6,3 6,1.5 4.5,0 1.5,0 0,1.5"),
        "4": (6, "4.5,0 4.5,9 0,3 6,3"),
        "5": (6, "6,9 0,9 0,5 4.5,5 6,3.5 6,1.5 4.5,0 1.5,0 0,1.5"),
        "6": (6, "5.5,8 4,9 2,9 0,7 0,1.5 1.5,0 4.5,0 6,1.5 6,3.5 4.5,5 1.5,5 0,3.5"),
        "7": (6, "0,9 6,9 2,0"),
        "8": (6, "1.5,4.5 0,6 0,7.5 1.5,9 4.5,9 6,7.5 6,6 4.5,4.5 1.5,4.5 0,3 0,1.5 1.5,0 4.5,0 6,1.5 6,3 4.5,4.5"),
        "9": (6, "0.5,1 2,0 4,0 6,2 6,7.5 4.5,9 1.5,9 0,7.5 0,5.5 1.5,4 4.5,4 6,5.5"),
        "!": (2, "1,9 1,2.5|1,0.8 1,0"),
        "\"": (4, "1,9 1,7|3,9 3,7"),
        "#": (6, "1.5,0 2.5,9|3.5,0 4.5,9|0,3 6,3|0,6 6,6"),
        "$": (6, "6,7.5 4.5,9 1.5,9 0,7.5 0,6 1.5,4.5 4.5,4.5 6,3 6,1.5 4.5,0 1.5,0 0,1.5|3,10 3,-1"),
        "%": (6, "0,0 6,9|0.5,9 1.5,9 1.5,7.5 0.5,7.5 0.5,9|4.5,1.5 5.5,1.5 5.5,0 4.5,0 4.5,1.5"),
        "&": (6, "6,0 1,6 1,8 2,9 3,9 4,8 4,7 0,3 0,1 1,0 3,0 6,3"),
        "'": (2, "1,9 1,7"),
        "(": (3, "2.5,10 1,8 0.5,4.5 1,1 2.5,-1"),
        ")": (3, "0.5,10 2,8 2.5,4.5 2,1 0.5,-1"),
        "*": (6, "3,7.5 3,1.5|0.5,6 5.5,3|0.5,3 5.5,6"),
        "+": (6, "3,7.5 3,1.5|0,4.5 6,4.5"),
        ",": (2, "1,0.8 1,0 0.3,-1.5"),
        "-": (5, "0,4.5 5,4.5"),
        ".": (2, "1,0.8 1,0"),
        "/": (5, "0,0 5,9"),
        ":": (2, "1,6 1,5.2|1,0.8 1,0"),
        ";": (2, "1,6 1,5.2|1,0.8 1,0 0.3,-1.5"),
        "<": (5, "5,7.5 0,4.5 5,1.5"),
        "=": (6, "0,6 6,6|0,3 6,3"),
        ">": (5, "0,7.5 5,4.5 0,1.5"),
        "?": (6, "0,7.5 1.5,9 4.5,9 6,7.5 6,6 3,4 3,2.5|3,0.8 3,0"),
        "@": (6, "4.5,3 4.5,6 2.5,6 1.5,5 1.5,4 2.5,3 4.5,3 6,4 6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0 5,0"),
        "[": (3, "2.5,10 0.5,10 0.5,-1 2.5,-1"),
        "\\": (5, "0,9 5,0"),
        "]": (3, "0.5,10 2.5,10 2.5,-1 0.5,-1"),
        "^": (6, "0,6 3,9 6,6"),
        "_": (6, "0,-1.5 6,-1.5"),
        "`": (2, "0,9 1.5,7.5"),
        "{": (3, "3,10 2,10 1,9 1,5.5 0,4.5 1,3.5 1,0 2,-1 3,-1"),
        "|": (2, "1,10 1,-2"),
        "}": (3, "0,10 1,10 2,9 2,5.5 3,4.5 2,3.5 2,0 1,-1 0,-1"),
        "~": (6, "0,4 1,5 2.5,5 3.5,4 5,4 6,5"),
        "•": (3, "0.8,4.5 2.2,4.5|1.5,3.8 1.5,5.2|0.9,4 2.1,5|0.9,5 2.1,4"),
        "°": (3, "1,9 2,9 2.5,8.5 2.5,7.5 2,7 1,7 0.5,7.5 0.5,8.5 1,9"),
        "±": (6, "3,7.5 3,2.5|0,5 6,5|0,0.5 6,0.5"),
        "Ø": (6, "1.5,0 4.5,0 6,1.5 6,7.5 4.5,9 1.5,9 0,7.5 0,1.5 1.5,0|-0.5,-0.5 6.5,9.5"),
        "ø": (5, "1.5,0 3.5,0 5,1.5 5,4.5 3.5,6 1.5,6 0,4.5 0,1.5 1.5,0|-0.5,-0.5 5.5,6.5"),
        "×": (5, "0.5,2 4.5,7|0.5,7 4.5,2"),
        "²": (3, "0,8.5 0.8,9.5 2.2,9.5 3,8.5 3,8 0,6 3,6"),
        "³": (3, "0,9 0.8,9.5 2.2,9.5 3,9 3,8.5 2,7.8 3,7 3,6.5 2.2,6 0.8,6 0,6.5|1,7.8 2,7.8"),
        "µ": (5, "0,6 0,-3|0,1.5 1.5,0 3.5,0 5,1.5|5,6 5,0"),
        "€": (6, "6,7.5 4.5,9 2.5,9 1,7.5 1,1.5 2.5,0 4.5,0 6,1.5|0,5.5 4,5.5|0,3.5 4,3.5"),
        "£": (6, "5.5,8 4.5,9 3,9 2,8 2,0|0,0 6,0|0,4.5 4,4.5"),
        "§": (5, "5,8.5 4,9 1,9 0,8 1,6.5 4,5.5 5,4 4,2.5 1,1.5|4,7.5 1,6.5 0,5 1,3.5 4,2.5|5,1 4,0 1,0 0,0.5"),
        "ß": (5, "0,0 0,7.5 1.5,9 3.5,9 4.5,8 4.5,6.5 3,5 4.5,4 5,2.5 5,1.5 3.5,0 2,0"),
        "Æ": (8, "0,0 4,9 8,9|2,4.5 7,4.5|4,9 4,0 8,0|1.3,3 4,3"),
        "æ": (8, "0.5,5.5 1.5,6 3,6 4,5 4,0|4,3.5 1.5,3.5 0,2.5 0,1 1,0 3,0 4,1|4,3 8,3 8,4.5 7,6 5,6 4,4.5|4,1.5 5,0 7,0 8,1"),
    ]

    /// Unknown-character box.
    static let missing = Glyph(width: 5, strokes: [[Vec2(0, 0), Vec2(0, 9), Vec2(5, 9), Vec2(5, 0), Vec2(0, 0)]])

    static let parsed: [Character: Glyph] = {
        var out: [Character: Glyph] = [:]
        for (c, (w, s)) in table {
            let strokes: [[Vec2]] = s.split(separator: "|").map { part in
                part.split(separator: " ").compactMap { pt in
                    let xy = pt.split(separator: ",").compactMap { Double($0) }
                    return xy.count == 2 ? Vec2(xy[0], xy[1]) : nil
                }
            }.filter { $0.count >= 2 }
            out[c] = Glyph(width: w, strokes: strokes)
        }
        return out
    }()

    /// Accent strokes for combining marks (U+0300…), drawn over a glyph `w` wide whose top is at `top`.
    static func accent(_ scalar: Unicode.Scalar, width w: Double, top: Double) -> [[Vec2]]? {
        let m = w / 2, y = top + 1
        switch scalar.value {
        case 0x0301: return [[Vec2(m - 0.7, y), Vec2(m + 0.9, y + 1.6)]]                              // acute
        case 0x0300: return [[Vec2(m + 0.7, y), Vec2(m - 0.9, y + 1.6)]]                              // grave
        case 0x0302: return [[Vec2(m - 1.4, y), Vec2(m, y + 1.5), Vec2(m + 1.4, y)]]                  // circumflex
        case 0x030C: return [[Vec2(m - 1.4, y + 1.5), Vec2(m, y), Vec2(m + 1.4, y + 1.5)]]            // caron
        case 0x0308: return [[Vec2(m - 1.2, y + 0.4), Vec2(m - 1.2, y + 1.2)], [Vec2(m + 1.2, y + 0.4), Vec2(m + 1.2, y + 1.2)]] // diaeresis
        case 0x0303: return [[Vec2(m - 2, y + 0.5), Vec2(m - 1, y + 1.3), Vec2(m + 1, y + 0.5), Vec2(m + 2, y + 1.3)]] // tilde
        case 0x030A: return [[Vec2(m - 0.7, y), Vec2(m + 0.7, y), Vec2(m + 0.7, y + 1.4), Vec2(m - 0.7, y + 1.4), Vec2(m - 0.7, y)]] // ring
        case 0x0306: return [[Vec2(m - 1.4, y + 1.4), Vec2(m - 0.7, y), Vec2(m + 0.7, y), Vec2(m + 1.4, y + 1.4)]] // breve
        case 0x0304: return [[Vec2(m - 1.5, y + 0.8), Vec2(m + 1.5, y + 0.8)]]                        // macron
        case 0x0327, 0x0328: return [[Vec2(m, 0), Vec2(m + 1, -1), Vec2(m - 0.5, -2)]]                // cedilla / ogonek
        case 0x0307: return [[Vec2(m, y + 0.3), Vec2(m, y + 1.1)]]                                    // dot above
        case 0x0326: return [[Vec2(m, -0.8), Vec2(m - 0.5, -2)]]                                      // comma below
        default: return nil
        }
    }

    /// Glyph for a character (with accents composed from the decomposed form); nil for a zero-width character.
    static func glyph(_ c: Character) -> Glyph {
        if let g = parsed[c] { return g }
        let scalars = Array(String(c).decomposedStringWithCanonicalMapping.unicodeScalars)
        if let first = scalars.first, let base = parsed[Character(first)], scalars.count > 1 {
            var strokes = base.strokes
            let top = base.strokes.flatMap { $0 }.map(\.y).max() ?? 6
            for s in scalars.dropFirst() {
                // Dotless base for i/j with accents above.
                if (first == "i" || first == "j"), s.value >= 0x0300 && s.value < 0x0315 { strokes = strokes.filter { !($0.allSatisfy { $0.y > 7 }) } }
                if let a = accent(s, width: base.width, top: (first == "i" || first == "j") ? 6 : top) { strokes += a }
            }
            return Glyph(width: base.width, strokes: strokes)
        }
        return missing
    }

    /// Advance of a character in grid units (glyph width + letter gap; a space is a word gap).
    public static func advance(_ c: Character) -> Double { glyph(c).width + letterGap }

    /// Width of a line of text in grid units (no trailing gap).
    public static func lineWidth(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        return s.reduce(0) { $0 + advance($1) } - letterGap
    }

    /// Plain lines of a text object: MTEXT paragraph codes (\P) and newlines split lines, other inline codes are removed,
    /// and multiline text with a width is word-wrapped.
    public static func lines(_ t: TextGeom, widthFactor: Double = 1) -> [String] {
        var s = t.content.replacingOccurrences(of: "\\P", with: "\n")
        s = s.replacingOccurrences(of: "%%d", with: "°", options: .caseInsensitive)
            .replacingOccurrences(of: "%%p", with: "±", options: .caseInsensitive)
            .replacingOccurrences(of: "%%c", with: "Ø", options: .caseInsensitive)
            .replacingOccurrences(of: "%%%", with: "%")
        s = stripFormatting(s)
        let raw = s.components(separatedBy: "\n")
        guard t.width > 0, t.height > 0 else { return raw }
        let maxUnits = t.width / (t.height / capHeight * widthFactor)
        var out: [String] = []
        for para in raw {
            var cur = ""
            for w in para.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let cand = cur.isEmpty ? w : cur + " " + w
                if !cur.isEmpty && lineWidth(cand) > maxUnits { out.append(cur); cur = w } else { cur = cand }
            }
            out.append(cur)
        }
        return out
    }

    /// Removes MTEXT inline codes ({\fArial;…}, \L, \O, \Hn;, \Cn; …), keeping the literal text.
    static func stripFormatting(_ s: String) -> String {
        var out = "", i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "{" || c == "}" { i = s.index(after: i); continue }
            if c == "\\", s.index(after: i) < s.endIndex {
                let n = s[s.index(after: i)]
                if "\\{}".contains(n) { out.append(n); i = s.index(i, offsetBy: 2); continue }
                if "LlOoKk".contains(n) { i = s.index(i, offsetBy: 2); continue }
                if "fFHhCcTtQqWwAap".contains(n) {
                    if let semi = s[i...].firstIndex(of: ";") { i = s.index(after: semi); continue }
                }
                if n == "S", let semi = s[i...].firstIndex(of: ";") {
                    // Stacked text a^b / a/b / a#b → "a/b".
                    let body = s[s.index(i, offsetBy: 2)..<semi]
                    out += body.replacingOccurrences(of: "^", with: "/").replacingOccurrences(of: "#", with: "/")
                    i = s.index(after: semi); continue
                }
            }
            out.append(c); i = s.index(after: i)
        }
        return out
    }

    /// Strokes (open polylines in world coordinates) that draw a text object with the stroke font, honouring height,
    /// rotation, justification, line breaks, wrap width, width factor and oblique angle (radians).
    public static func strokes(_ t: TextGeom, widthFactor: Double = 1, oblique: Double = 0) -> [[Vec2]] {
        guard t.height > 0 else { return [] }
        let k = t.height / capHeight
        let wf = widthFactor > 0 ? widthFactor : 1
        let ls = lines(t, widthFactor: wf)
        let n = Double(ls.count)
        let pitch = t.height * lineSpacing
        // Vertical offset of the first baseline relative to the insertion point.
        let block = t.height + (n - 1) * pitch
        let y0: Double
        switch t.valign {
        case .baseline: y0 = 0
        case .bottom: y0 = (n - 1) * pitch + 3 * k
        case .middle: y0 = block / 2 - t.height
        case .top: y0 = -t.height
        }
        let shear = tan(oblique)
        let rot = Transform2D.rotation(t.rotation) * Transform2D.translation(.zero)
        var out: [[Vec2]] = []
        for (li, line) in ls.enumerated() {
            let w = lineWidth(line) * k * wf
            var x: Double
            switch t.halign { case .left: x = 0; case .center: x = -w / 2; case .right: x = -w }
            let by = y0 - Double(li) * pitch
            for c in line {
                let g = glyph(c)
                for s in g.strokes {
                    out.append(s.map { p in
                        let lx = x + (p.x * wf + p.y * shear) * k, ly = by + p.y * k
                        return t.position + rot.applyVector(Vec2(lx, ly))
                    })
                }
                x += (g.width + letterGap) * k * wf
            }
        }
        return out
    }

    /// Stroke geometry for a text entity: lines for two-point strokes, open polylines otherwise.
    public static func geometry(_ t: TextGeom, widthFactor: Double = 1, oblique: Double = 0) -> [Geometry] {
        strokes(t, widthFactor: widthFactor, oblique: oblique).map { s in
            s.count == 2 ? .line(LineGeom(s[0], s[1])) : .polyline(PolylineGeom(points: s, closed: false))
        }
    }

    /// Geometry for a text entity using the drawing's text style (width factor, oblique angle).
    public static func geometry(_ t: TextGeom, doc: ArchiDocument) -> [Geometry] {
        let st = doc.textStyles.first { $0.name.caseInsensitiveCompare(t.style) == .orderedSame }
        return geometry(t, widthFactor: st.map(TextStyleFonts.widthFactor) ?? 1, oblique: st.map(TextStyleFonts.obliqueRadians) ?? 0)
    }
}
