// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Real MTEXT inline codes for Archi multiline text (ANN-005 lists, ANN-006 columns, ANN-007 stacks), for DXF exchange.
///
/// Archi keeps text content as plain paragraphs ("\n" or "\P"), list markers written by TEXTLIST ("• ", "1. ", "a. ") and
/// MTEXT stacks ("\S1/2;", "\S3#4;", "\S+0.1^-0.1;"). `encode` turns that into an MTEXT string AutoCAD reads as a real
/// list (paragraph indents with a hanging tab), real stacks and escaped special characters; `decode` is the inverse for
/// MTEXT coming from other programs. Columns are not inline codes: `Columns` converts between the Archi "textColumns"
/// prop and the MTEXT column group codes (R2018 groups 75/76/78/79/48/49/50/46, or the R2007–R2013 ACAD XDATA block).
///
/// The strings are DXF group values before Unicode escaping: the writer still applies its \U+XXXX encoding. DXF caret
/// notation is used for control characters ("^I" tab, "^ " a literal caret).
public enum MTextCodes {
    /// Paragraph code of list items: first line hanging by `indent`, left indent and tab stop at `indent`.
    public static func listParagraphCode(indent: Double = 3) -> String {
        "\\pxi-\(num(indent)),l\(num(indent)),t\(num(indent));"
    }

    static let marker = try! NSRegularExpression(pattern: "^(•|[0-9]+\\.|[a-zA-Z]\\.)[ \\t]")

    /// Splits Archi content into paragraphs.
    public static func paragraphs(_ content: String) -> [String] {
        content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\\P", with: "\n").components(separatedBy: "\n")
    }

    /// List marker and body of a paragraph written by TEXTLIST, or nil.
    public static func listItem(_ paragraph: String) -> (marker: String, body: String)? {
        let r = NSRange(paragraph.startIndex..., in: paragraph)
        guard let m = marker.firstMatch(in: paragraph, range: r), let mr = Range(m.range(at: 1), in: paragraph),
              let all = Range(m.range, in: paragraph) else { return nil }
        return (String(paragraph[mr]), String(paragraph[all.upperBound...]))
    }

    // MARK: Encoding

    /// Escapes plain text for MTEXT: backslash, braces, caret and tab.
    public static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "{": out += "\\{"
            case "}": out += "\\}"
            case "^": out += "^ "
            case "\t": out += "^I"
            default: out.append(ch)
            }
        }
        return out
    }
    static func escapeStackPart(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "/", "#", "^", ";", "\\": out += "\\" + String(ch)
            case "{": out += "\\{"
            case "}": out += "\\}"
            default: out.append(ch)
            }
        }
        return out
    }
    /// One paragraph's runs: plain text escaped, stacks as \S codes (the tolerance "^" as "^ " per DXF caret notation).
    static func encodeRuns(_ p: String) -> String {
        guard TextStacks.hasStack(p) else { return escape(p) }
        return TextStacks.runs(p).map { r -> String in
            switch r {
            case .plain(let s): return escape(s)
            case .stack(let a, let b, let k): return "\\S" + escapeStackPart(a) + (k == "^" ? "^ " : k) + escapeStackPart(b) + ";"
            }
        }.joined()
    }

    /// MTEXT string for Archi content: paragraphs joined by \P, runs of list paragraphs grouped with a hanging-indent
    /// paragraph code and the marker separated from the text by a tab, stacks as \S codes.
    public static func encode(_ content: String, listIndent: Double = 3) -> String {
        let paras = paragraphs(content)
        var segments: [String] = []
        var list: [String] = []
        func flush() {
            guard !list.isEmpty else { return }
            segments.append("{" + listParagraphCode(indent: listIndent) + list.joined(separator: "\\P") + "}")
            list = []
        }
        for p in paras {
            if let item = listItem(p) {
                list.append(escape(item.marker) + "^I" + encodeRuns(item.body))
            } else {
                flush()
                segments.append(encodeRuns(p))
            }
        }
        flush()
        return segments.joined(separator: "\\P")
    }

    // MARK: Decoding

    /// Archi content from an MTEXT string: paragraphs as "\n", stacks kept as \S codes, list paragraphs (a marker
    /// followed by a tab) as "marker body", every other formatting code removed and escapes resolved.
    public static func decode(_ raw: String) -> String {
        let c = Array(raw)
        var i = 0
        var out = ""
        func skipArg() { while i < c.count && c[i] != ";" { i += 1 }; i += 1 }
        func caret(_ into: inout String) -> Bool {
            // DXF caret notation: "^I" tab, "^J" newline, "^ " caret, "^@".."^_" control characters (dropped).
            guard c[i] == "^", i + 1 < c.count else { return false }
            let n = c[i + 1]
            i += 2
            switch n {
            case " ": into.append("^")
            case "I": into.append("\t")
            case "J", "M": into.append("\n")
            default: break
            }
            return true
        }
        while i < c.count {
            let ch = c[i]
            if ch == "^", caret(&out) { continue }
            if ch == "{" || ch == "}" { i += 1; continue }
            guard ch == "\\", i + 1 < c.count else { out.append(ch); i += 1; continue }
            let k = c[i + 1]
            i += 2
            switch k {
            case "P", "X": out.append("\n")
            case "~": out.append(" ")
            case "\\", "{", "}": out.append(k)
            case "L", "l", "O", "o", "K", "k", "N": break
            case "f", "F", "H", "W", "Q", "T", "A", "C", "c", "p": skipArg()
            case "U":
                if i + 5 <= c.count, c[i] == "+", let v = UInt32(String(c[(i + 1)..<(i + 5)]), radix: 16), let u = Unicode.Scalar(v) {
                    out.unicodeScalars.append(u); i += 5
                } else { out.append("U") }
            case "M": i = Swift.min(c.count, i + 6)
            case "S":
                var a = "", b = "", kind: Character?
                while i < c.count && c[i] != ";" {
                    let x = c[i]
                    if x == "\\", i + 1 < c.count {
                        if kind == nil { a.append(c[i + 1]) } else { b.append(c[i + 1]) }
                        i += 2; continue
                    }
                    i += 1
                    if kind == nil, "/#^".contains(x) {
                        kind = x
                        if x == "^", i < c.count, c[i] == " " { i += 1 }
                        continue
                    }
                    if kind == nil { a.append(x) } else { b.append(x) }
                }
                i += 1
                if let kd = kind { out += "\\S" + a + String(kd) + b + ";" } else { out += a }
            default: out.append(k)
            }
        }
        return paragraphs(out).map { p -> String in
            if let tab = p.firstIndex(of: "\t") {
                let m = String(p[..<tab])
                if m == "•" || m.range(of: "^([0-9]+|[a-zA-Z])[.)]$", options: .regularExpression) != nil {
                    let mk = m.hasSuffix(")") ? String(m.dropLast()) + "." : m
                    return mk + " " + String(p[p.index(after: tab)...])
                }
            }
            return p
        }.joined(separator: "\n")
    }

    // MARK: Columns

    public struct Columns: Equatable {
        public enum Kind: Int { case none = 0, `static` = 1, dynamic = 2 }
        public var kind: Kind
        public var count: Int
        /// Width of one column and the gap between columns.
        public var width: Double
        public var gutter: Double
        /// Column height: MTEXT defined height (group 46).
        public var height: Double
        public var autoHeight: Bool
        public var flowReversed: Bool
        /// Manual column heights of dynamic columns (empty = all `height`).
        public var heights: [Double]
        public init(kind: Kind, count: Int, width: Double, gutter: Double, height: Double, autoHeight: Bool = false, flowReversed: Bool = false, heights: [Double] = []) {
            self.kind = kind; self.count = count; self.width = width; self.gutter = gutter; self.height = height
            self.autoHeight = autoHeight; self.flowReversed = flowReversed; self.heights = heights
        }
        /// Total width of the text frame.
        public var totalWidth: Double { Double(count) * width + Double(Swift.max(0, count - 1)) * gutter }
    }

    /// Columns of a multiline text from its "textColumns" prop: balanced static columns get the height their longest
    /// column needs; dynamic columns keep their fixed height.
    public static func columns(spec: String, text t: TextGeom, widthFactor: Double = 1) -> Columns? {
        guard let s = DraftRendering.columnSpec(spec), t.width > 0 else { return nil }
        var th = t
        if th.height <= 0 { th.height = 2.5 }
        guard let lay = DraftRendering.columnLayout(th, spec: spec, widthFactor: widthFactor) else { return nil }
        if s.height > 0 {
            let used = Swift.max(1, (lay.lines.map(\.column).max() ?? 0) + 1)
            return Columns(kind: .dynamic, count: used, width: lay.columnWidth, gutter: lay.gutter, height: s.height)
        }
        let rows = (lay.lines.map(\.row).max() ?? 0) + 1
        let height = th.height + 1.5 * th.height * Double(rows - 1)
        return Columns(kind: .static, count: s.count, width: lay.columnWidth, gutter: lay.gutter, height: height)
    }

    /// The Archi "textColumns" prop value and frame width for columns read from a file.
    public static func spec(_ c: Columns) -> (prop: String, width: Double)? {
        guard c.kind != .none, c.count >= 1, c.width > 0 else { return nil }
        let h = c.kind == .dynamic ? c.height : 0
        return ("\(c.count),\(num(c.gutter)),\(num(h))", c.totalWidth)
    }

    /// R2018+ MTEXT column group codes (written after the AcDbMText content groups).
    public static func columnGroups(_ c: Columns) -> [(code: Int, value: String)] {
        var g: [(Int, String)] = [(75, "\(c.kind.rawValue)"), (79, c.autoHeight ? "1" : "0"), (76, "\(c.count)"), (78, c.flowReversed ? "1" : "0"),
                                  (48, num(c.width)), (49, num(c.gutter))]
        if c.kind == .dynamic && !c.autoHeight { for h in c.heights { g.append((50, num(h))) } }
        g.append((46, num(c.height)))
        return g.map { (code: $0.0, value: $0.1) }
    }

    /// R2007–R2013 form: ACAD XDATA with ACAD_MTEXT_COLUMN_INFO and ACAD_MTEXT_DEFINED_HEIGHT sections.
    public static func columnXData(_ c: Columns) -> [(code: Int, value: String)] {
        var g: [(Int, String)] = [(1001, "ACAD"), (1000, "ACAD_MTEXT_COLUMN_INFO_BEGIN"),
                                  (1070, "75"), (1070, "\(c.kind.rawValue)"), (1070, "79"), (1070, c.autoHeight ? "1" : "0"),
                                  (1070, "76"), (1070, "\(c.count)"), (1070, "78"), (1070, c.flowReversed ? "1" : "0"),
                                  (1070, "48"), (1040, num(c.width)), (1070, "49"), (1040, num(c.gutter))]
        if c.kind == .dynamic && !c.autoHeight && !c.heights.isEmpty {
            g.append((1070, "50")); g.append((1070, "\(c.heights.count)"))
            for h in c.heights { g.append((1040, num(h))) }
        }
        g += [(1000, "ACAD_MTEXT_COLUMN_INFO_END"), (1000, "ACAD_MTEXT_DEFINED_HEIGHT_BEGIN"), (1070, "46"), (1040, num(c.height)),
              (1000, "ACAD_MTEXT_DEFINED_HEIGHT_END")]
        return g.map { (code: $0.0, value: $0.1) }
    }

    /// Columns from an MTEXT record's groups: R2018 codes or the ACAD XDATA block (nil when the text has no columns).
    public static func columns(fromGroups groups: [(code: Int, value: String)]) -> Columns? {
        var v: [Int: Double] = [:]
        var heights: [Double] = []
        if let start = groups.firstIndex(where: { $0.code == 1000 && $0.value.trimmingCharacters(in: .whitespaces) == "ACAD_MTEXT_COLUMN_INFO_BEGIN" }) {
            var i = start + 1
            while i < groups.count, !(groups[i].code == 1000 && groups[i].value.hasPrefix("ACAD_MTEXT_COLUMN_INFO_END")) {
                if groups[i].code == 1070, let key = Int(groups[i].value.trimmingCharacters(in: .whitespaces)), i + 1 < groups.count {
                    if key == 50, let n = Int(groups[i + 1].value.trimmingCharacters(in: .whitespaces)) {
                        var j = i + 2
                        while j < groups.count && groups[j].code == 1040 && heights.count < n { heights.append(Double(groups[j].value.trimmingCharacters(in: .whitespaces)) ?? 0); j += 1 }
                        i = j; continue
                    }
                    v[key] = Double(groups[i + 1].value.trimmingCharacters(in: .whitespaces))
                    i += 2; continue
                }
                i += 1
            }
            if let hs = groups.firstIndex(where: { $0.code == 1000 && $0.value.hasPrefix("ACAD_MTEXT_DEFINED_HEIGHT_BEGIN") }), hs + 2 < groups.count,
               groups[hs + 1].value.trimmingCharacters(in: .whitespaces) == "46" { v[46] = Double(groups[hs + 2].value.trimmingCharacters(in: .whitespaces)) }
        } else {
            // Only the entity's own groups (before any XDATA).
            for g in groups {
                if g.code >= 1000 { break }
                guard [75, 76, 78, 79, 48, 49, 46, 50].contains(g.code), let d = Double(g.value.trimmingCharacters(in: .whitespaces)) else { continue }
                // Column heights follow the column type group; an earlier 50 is the text rotation.
                if g.code == 50 { if v[75] != nil { heights.append(d) } } else { v[g.code] = d }
            }
            // Group 50 is also the MTEXT rotation in older files: only trust heights when a column type is present.
            if v[75] == nil { return nil }
        }
        guard let t = v[75].flatMap({ Columns.Kind(rawValue: Int($0)) }), t != .none else { return nil }
        let count = Int(v[76] ?? Double(Swift.max(1, heights.count)))
        return Columns(kind: t, count: Swift.max(1, count), width: v[48] ?? 0, gutter: v[49] ?? 0, height: v[46] ?? (heights.max() ?? 0),
                       autoHeight: (v[79] ?? 0) != 0, flowReversed: (v[78] ?? 0) != 0, heights: heights)
    }

    static func num(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        var s = String(format: "%.6f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
