// Oanarina Archi Tool — GPL-3.0-or-later
// Base direction of text (SYS-027): the Unicode Bidirectional Algorithm's paragraph-level rule (P2/P3 — the first
// strong character decides), with strong right-to-left ranges for Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan,
// Mandaic and their presentation forms, and the historic RTL scripts of the supplementary planes. Exporters use it to
// mark right-to-left runs (SVG direction="rtl").
import Foundation

public enum TextDirection: String {
    case leftToRight, rightToLeft, neutral

    static func isRTL(_ v: UInt32) -> Bool {
        (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) ||
            (0x10800...0x10FFF).contains(v) || (0x1E800...0x1EFFF).contains(v)
    }

    /// Strong direction of one scalar (nil for neutral/weak: digits, punctuation, spaces, symbols, marks).
    public static func strong(_ u: Unicode.Scalar) -> TextDirection? {
        if isRTL(u.value) {
            // Arabic-Indic digits and combining marks inside the RTL blocks are weak/non-spacing.
            if (0x0660...0x0669).contains(u.value) || (0x06F0...0x06F9).contains(u.value) || u.properties.generalCategory == .nonspacingMark { return nil }
            return .rightToLeft
        }
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .spacingMark, .letterNumber: return .leftToRight
        default: return nil
        }
    }

    /// Paragraph direction: the first strong character; `.neutral` when there is none.
    public static func base(of s: String) -> TextDirection {
        for u in s.unicodeScalars { if let d = strong(u) { return d } }
        return .neutral
    }

    /// Whether the text contains any right-to-left character.
    public static func containsRTL(_ s: String) -> Bool { s.unicodeScalars.contains { isRTL($0.value) } }
}
