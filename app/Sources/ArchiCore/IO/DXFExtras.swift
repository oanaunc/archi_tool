// Oanarina Archi Tool — GPL-3.0-or-later
// DXF fidelity helpers: the standard AutoCAD Color Index palette, true colour and transparency group codes, text style
// font mapping (SHX/TTF files ↔ macOS font families), MTEXT inline formatting, and XDATA (extended entity data) used to
// round-trip Archi properties and to preserve other applications' data.
//
// ACI palette values from libdxfrw (drw_objects.h), Copyright (C) 2011-2015 José F. Soriano, 2016-2022 A. Stebich,
// LibreCAD — GPL-2.0-or-later.
import Foundation

public enum DXFColors {
    /// RGB of ACI 0…255 (0 = ByBlock placeholder, 7 = white/black).
    public static let aci: [Int] = [
        0x000000, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF, 0xFFFFFF,
        0x808080, 0xC0C0C0, 0xFF0000, 0xFF7F7F, 0xCC0000, 0xCC6666, 0x990000, 0x994C4C,
        0x7F0000, 0x7F3F3F, 0x4C0000, 0x4C2626, 0xFF3F00, 0xFF9F7F, 0xCC3300, 0xCC7F66,
        0x992600, 0x995F4C, 0x7F1F00, 0x7F4F3F, 0x4C1300, 0x4C2F26, 0xFF7F00, 0xFFBF7F,
        0xCC6600, 0xCC9966, 0x994C00, 0x99724C, 0x7F3F00, 0x7F5F3F, 0x4C2600, 0x4C3926,
        0xFFBF00, 0xFFDF7F, 0xCC9900, 0xCCB266, 0x997200, 0x99854C, 0x7F5F00, 0x7F6F3F,
        0x4C3900, 0x4C4226, 0xFFFF00, 0xFFFF7F, 0xCCCC00, 0xCCCC66, 0x999900, 0x99994C,
        0x7F7F00, 0x7F7F3F, 0x4C4C00, 0x4C4C26, 0xBFFF00, 0xDFFF7F, 0x99CC00, 0xB2CC66,
        0x729900, 0x85994C, 0x5F7F00, 0x6F7F3F, 0x394C00, 0x424C26, 0x7FFF00, 0xBFFF7F,
        0x66CC00, 0x99CC66, 0x4C9900, 0x72994C, 0x3F7F00, 0x5F7F3F, 0x264C00, 0x394C26,
        0x3FFF00, 0x9FFF7F, 0x33CC00, 0x7FCC66, 0x269900, 0x5F994C, 0x1F7F00, 0x4F7F3F,
        0x134C00, 0x2F4C26, 0x00FF00, 0x7FFF7F, 0x00CC00, 0x66CC66, 0x009900, 0x4C994C,
        0x007F00, 0x3F7F3F, 0x004C00, 0x264C26, 0x00FF3F, 0x7FFF9F, 0x00CC33, 0x66CC7F,
        0x009926, 0x4C995F, 0x007F1F, 0x3F7F4F, 0x004C13, 0x264C2F, 0x00FF7F, 0x7FFFBF,
        0x00CC66, 0x66CC99, 0x00994C, 0x4C9972, 0x007F3F, 0x3F7F5F, 0x004C26, 0x264C39,
        0x00FFBF, 0x7FFFDF, 0x00CC99, 0x66CCB2, 0x009972, 0x4C9985, 0x007F5F, 0x3F7F6F,
        0x004C39, 0x264C42, 0x00FFFF, 0x7FFFFF, 0x00CCCC, 0x66CCCC, 0x009999, 0x4C9999,
        0x007F7F, 0x3F7F7F, 0x004C4C, 0x264C4C, 0x00BFFF, 0x7FDFFF, 0x0099CC, 0x66B2CC,
        0x007299, 0x4C8599, 0x005F7F, 0x3F6F7F, 0x00394C, 0x26424C, 0x007FFF, 0x7FBFFF,
        0x0066CC, 0x6699CC, 0x004C99, 0x4C7299, 0x003F7F, 0x3F5F7F, 0x00264C, 0x26394C,
        0x0042FF, 0x7F9FFF, 0x0033CC, 0x667FCC, 0x002699, 0x4C5F99, 0x001F7F, 0x3F4F7F,
        0x00134C, 0x262F4C, 0x0000FF, 0x7F7FFF, 0x0000CC, 0x6666CC, 0x000099, 0x4C4C99,
        0x00007F, 0x3F3F7F, 0x00004C, 0x26264C, 0x3F00FF, 0x9F7FFF, 0x3200CC, 0x7F66CC,
        0x260099, 0x5F4C99, 0x1F007F, 0x4F3F7F, 0x13004C, 0x2F264C, 0x7F00FF, 0xBF7FFF,
        0x6600CC, 0x9966CC, 0x4C0099, 0x724C99, 0x3F007F, 0x5F3F7F, 0x26004C, 0x39264C,
        0xBF00FF, 0xDF7FFF, 0x9900CC, 0xB266CC, 0x720099, 0x854C99, 0x5F007F, 0x6F3F7F,
        0x39004C, 0x42264C, 0xFF00FF, 0xFF7FFF, 0xCC00CC, 0xCC66CC, 0x990099, 0x994C99,
        0x7F007F, 0x7F3F7F, 0x4C004C, 0x4C264C, 0xFF00BF, 0xFF7FDF, 0xCC0099, 0xCC66B2,
        0x990072, 0x994C85, 0x7F005F, 0x7F3F0B, 0x4C0039, 0x4C2642, 0xFF007F, 0xFF7FBF,
        0xCC0066, 0xCC6699, 0x99004C, 0x994C72, 0x7F003F, 0x7F3F5F, 0x4C0026, 0x4C2639,
        0xFF003F, 0xFF7F9F, 0xCC0033, 0xCC667F, 0x990026, 0x994C5F, 0x7F001F, 0x7F3F4F,
        0x4C0013, 0x4C262F, 0x333333, 0x5B5B5B, 0x848484, 0xADADAD, 0xD6D6D6, 0xFFFFFF,
    ]

    public static func rgba(aci i: Int) -> RGBA {
        let v = aci[max(0, min(255, abs(i)))]
        return RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// Nearest ACI 1…255 by squared RGB distance.
    public static func nearest(_ c: RGBA) -> Int {
        let r = Int((max(0, min(1, c.r)) * 255).rounded()), g = Int((max(0, min(1, c.g)) * 255).rounded()), b = Int((max(0, min(1, c.b)) * 255).rounded())
        var best = 7, bestD = Int.max
        for i in 1...255 {
            let v = aci[i]
            let dr = (v >> 16) & 255 - r, dg = (v >> 8) & 255 - g, db = v & 255 - b
            let d = dr * dr + dg * dg + db * db
            if d < bestD { bestD = d; best = i; if d == 0 { break } }
        }
        return best
    }

    /// Whether `c` is exactly representable by an ACI (no 420 true colour needed).
    public static func isExact(_ c: RGBA) -> Bool { rgba(aci: nearest(c)).isNear(c) }

    /// Group 440 value for a transparency in percent (0 = opaque … 90): 0x02000000 | alpha.
    public static func transparencyCode(percent: Double) -> Int {
        let p = max(0, min(90, percent))
        return 0x0200_0000 | Int(((1 - p / 100) * 255).rounded())
    }

    /// Transparency percent from a group 440 value; nil for ByLayer (0) and ByBlock (0x01000000).
    public static func transparencyPercent(code v: Int) -> Double? {
        guard v & 0x0200_0000 != 0 else { return nil }
        let alpha = Double(v & 0xFF)
        return ((1 - alpha / 255) * 100).rounded()
    }
}

// MARK: - Fonts

public enum DXFFonts {
    /// AutoCAD font files and the macOS family used to display them.
    public static let fileToFamily: [String: String] = [
        "txt": "Helvetica", "simplex": "Helvetica", "romans": "Helvetica", "romand": "Helvetica", "isocp": "Helvetica", "isocpeur": "Helvetica",
        "iso": "Helvetica", "monotxt": "Courier", "complex": "Times New Roman", "romanc": "Times New Roman", "romant": "Times New Roman",
        "italic": "Times New Roman Italic", "italicc": "Times New Roman Italic", "gothice": "Times New Roman", "scripts": "Snell Roundhand",
        "arial": "Arial", "arialbd": "Arial Bold", "ariali": "Arial Italic", "arialn": "Arial Narrow", "times": "Times New Roman",
        "timesbd": "Times New Roman Bold", "cour": "Courier New", "calibri": "Calibri", "verdana": "Verdana", "tahoma": "Tahoma",
        "georgia": "Georgia", "consola": "Menlo", "swiss": "Helvetica", "dutch": "Times New Roman", "archquik": "Chalkboard", "ltypeshp": "Helvetica",
    ]
    /// macOS families and the font file written to DXF STYLE records.
    public static let familyToFile: [String: String] = [
        "helvetica": "arial.ttf", "helvetica neue": "arial.ttf", "arial": "arial.ttf", "arial bold": "arialbd.ttf", "arial italic": "ariali.ttf",
        "arial narrow": "arialn.ttf", "times new roman": "times.ttf", "times": "times.ttf", "times new roman bold": "timesbd.ttf",
        "courier": "cour.ttf", "courier new": "cour.ttf", "menlo": "consola.ttf", "calibri": "calibri.ttf", "verdana": "verdana.ttf",
        "tahoma": "tahoma.ttf", "georgia": "georgia.ttf",
    ]

    /// Family for a DXF STYLE font file (group 3) or TrueType face name (XDATA ACAD 1000).
    public static func family(fromFile file: String, face: String? = nil) -> String {
        if let f = face?.trimmingCharacters(in: .whitespaces), !f.isEmpty { return f }
        let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        if base.isEmpty { return "Helvetica" }
        return fileToFamily[base.lowercased()] ?? base
    }

    /// Font file for a family; `original` (props or style "fontFile") wins so imported SHX fonts round-trip.
    public static func file(forFamily family: String, original: String? = nil) -> String {
        if let o = original, !o.isEmpty { return o }
        let f = family.trimmingCharacters(in: .whitespaces)
        if f.isEmpty { return "arial.ttf" }
        if f.contains(".") { return f }
        return familyToFile[f.lowercased()] ?? (f.replacingOccurrences(of: " ", with: "").lowercased() + ".ttf")
    }
}

// MARK: - MTEXT formatting

public struct MTextFormat: Hashable {
    public var font: String?
    public var bold = false
    public var italic = false
    public var underline = false
    public var overline = false
    public var strike = false
    /// Relative (x suffix) or absolute height from \H.
    public var height: Double?
    public var heightRelative = false
    public var widthFactor: Double?
    public var oblique: Double?
    public var tracking: Double?
    public var color: ColorRef?
    /// Whether the string uses formatting beyond plain text and paragraph breaks.
    public var hasFormatting = false
}

public enum MTextFormatting {
    /// Formatting that applies from the start of the text (leading codes, possibly inside the first brace group).
    public static func leading(_ raw: String) -> MTextFormat {
        var f = MTextFormat()
        let chars = Array(raw)
        var i = 0
        func arg() -> String {
            var s = ""
            while i < chars.count && chars[i] != ";" { s.append(chars[i]); i += 1 }
            i += 1
            return s
        }
        var leadingDone = false
        while i < chars.count {
            let c = chars[i]
            if c == "{" { f.hasFormatting = true; i += 1; continue }
            if c == "}" { f.hasFormatting = true; i += 1; leadingDone = true; continue }
            guard c == "\\", i + 1 < chars.count else { i += 1; leadingDone = true; continue }
            let k = chars[i + 1]
            i += 2
            if "PX~\\{}U".contains(k) { leadingDone = true; if k == "U" { i += 5 }; continue }
            f.hasFormatting = true
            let apply = !leadingDone
            switch k {
            case "f", "F":
                let a = arg()
                guard apply else { continue }
                let parts = a.split(separator: "|").map(String.init)
                if let name = parts.first, !name.isEmpty { f.font = k == "F" ? DXFFonts.family(fromFile: name) : name }
                for p in parts.dropFirst() {
                    if p == "b1" { f.bold = true }
                    if p == "i1" { f.italic = true }
                }
            case "H":
                let a = arg()
                guard apply else { continue }
                if a.hasSuffix("x") || a.hasSuffix("X") { f.heightRelative = true; f.height = Double(a.dropLast()) } else { f.height = Double(a) }
            case "W": let a = arg(); if apply { f.widthFactor = Double(a.hasSuffix("x") ? String(a.dropLast()) : a) }
            case "Q": let a = arg(); if apply { f.oblique = Double(a) }
            case "T": let a = arg(); if apply { f.tracking = Double(a.hasSuffix("x") ? String(a.dropLast()) : a) }
            case "C": let a = arg(); if apply, let v = Int(a) { f.color = v == 256 ? .byLayer : (v == 0 ? .byBlock : .aci(v)) }
            case "c": let a = arg(); if apply, let v = Int(a) { f.color = .rgb(UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255)) } // BGR
            case "A", "p": _ = arg()
            case "S": _ = arg(); leadingDone = true
            case "L": if apply { f.underline = true }
            case "O": if apply { f.overline = true }
            case "K": if apply { f.strike = true }
            case "l", "o", "k": break
            default: break
            }
        }
        return f
    }

    /// MTEXT string for plain `content` with whole-text formatting (inverse of `leading`).
    public static func encode(_ content: String, font: String? = nil, bold: Bool = false, italic: Bool = false, underline: Bool = false, color: ColorRef? = nil, strike: Bool = false) -> String {
        var codes = ""
        if font != nil || bold || italic { codes += "\\f\(font ?? "Arial")|b\(bold ? 1 : 0)|i\(italic ? 1 : 0)|c0|p34;" }
        if let c = color {
            switch c {
            case .aci(let i): codes += "\\C\(i);"
            case .rgb(let r, let g, let b): codes += "\\c\(Int(b) << 16 | Int(g) << 8 | Int(r));"
            default: break
            }
        }
        if underline { codes += "\\L" }
        if strike { codes += "\\K" }
        let body = DXFWriter.Writer.mtextEscape(content)
        return codes.isEmpty ? body : "{" + codes + body + "}"
    }
}

// MARK: - XDATA

public enum DXFXData {
    /// Application name under which entity props are written.
    public static let app = "OANARINA_ARCHI"
    /// Props that are rebuilt from the file itself and not written as XDATA.
    static let skip: Set<String> = ["dxfHandle", "elevation", "z", "vertexZ", "transparency", "mtext", "_paper", "_viewport", "vpCenter", "vpScale"]

    /// Reads XDATA groups (1001 and following 1000–1071 codes) of a record: Archi props from our application, other
    /// applications as "xdata:<APP>" = encoded group list (code=value lines joined by \u{1E}).
    static func read(_ pairs: [DXFPair]) -> [String: String] {
        var out: [String: String] = [:]
        var i = pairs.firstIndex { $0.code == 1001 } ?? pairs.count
        while i < pairs.count {
            guard pairs[i].code == 1001 else { i += 1; continue }
            let name = pairs[i].value.trimmingCharacters(in: .whitespaces)
            var j = i + 1
            var groups: [DXFPair] = []
            while j < pairs.count && pairs[j].code != 1001 && pairs[j].code >= 1000 { groups.append(pairs[j]); j += 1 }
            if name.uppercased() == app {
                // Strings "key=value"; long values continue in following 1000 groups prefixed with "+".
                var lastKey: String?
                for g in groups where g.code == 1000 {
                    if g.value.hasPrefix("+"), let k = lastKey { out[k, default: ""] += DXFReader.decodeSpecial(String(g.value.dropFirst())); continue }
                    guard let eq = g.value.firstIndex(of: "=") else { continue }
                    let k = String(g.value[..<eq]), v = String(g.value[g.value.index(after: eq)...])
                    out[k] = DXFReader.decodeSpecial(v); lastKey = k
                }
            } else if !name.isEmpty && name.uppercased() != "ACAD" && name.uppercased() != "ACCMTRANSPARENCY" {
                out["xdata:" + name] = groups.map { "\($0.code)=\($0.value)" }.joined(separator: "\u{1E}")
            }
            i = j
        }
        return out
    }

    /// XDATA groups for entity props (Archi props and preserved foreign applications). `enc` encodes strings for the file.
    public static func groups(_ props: [String: String], enc: (String) -> String) -> [(Int, String)] {
        var out: [(Int, String)] = []
        let mine = props.filter { !skip.contains($0.key) && !$0.key.hasPrefix("xdata:") && !$0.key.hasPrefix("_") }.sorted { $0.key < $1.key }
        if !mine.isEmpty {
            out.append((1001, app))
            for (k, v) in mine {
                // 1000 strings hold at most 255 bytes: long values continue in "+" groups, each encoded on its own.
                var pieces: [String] = []
                var cur = ""
                for ch in k + "=" + v {
                    if enc(cur + String(ch)).count > 240 { pieces.append(cur); cur = "" }
                    cur.append(ch)
                }
                pieces.append(cur)
                for (i, piece) in pieces.enumerated() { out.append((1000, (i == 0 ? "" : "+") + enc(piece))) }
            }
        }
        for (k, v) in props.filter({ $0.key.hasPrefix("xdata:") }).sorted(by: { $0.key < $1.key }) {
            let name = String(k.dropFirst(6))
            guard !name.isEmpty else { continue }
            out.append((1001, name))
            for item in v.components(separatedBy: "\u{1E}") {
                guard let eq = item.firstIndex(of: "="), let code = Int(item[..<eq]), code >= 1000, code <= 1071, code != 1001 else { continue }
                out.append((code, String(item[item.index(after: eq)...])))
            }
        }
        return out
    }

    /// Application names used by a document's entity props (for the APPID table).
    public static func appNames(_ doc: ArchiDocument) -> [String] {
        var names = Set<String>()
        func scan(_ props: [String: String]) {
            for k in props.keys {
                if k.hasPrefix("xdata:") { names.insert(String(k.dropFirst(6))) }
                else if !skip.contains(k) && !k.hasPrefix("_") { names.insert(app) }
            }
        }
        doc.entities.forEach { scan($0.props) }
        doc.blocks.values.forEach { $0.entities.forEach { scan($0.props) } }
        doc.layouts.forEach { $0.entities.forEach { scan($0.props) } }
        return names.sorted()
    }
}
