// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Text style resolution (ANN-004) and single-stroke CAD fonts (ANN-016).
///
/// A text style whose font is one of the bundled single-stroke fonts ("Archi Stroke", or the AutoCAD SHX names txt,
/// simplex, romans, isocp … that it stands in for) is drawn as vector strokes with `StrokeFont`, honouring the style's
/// width factor and obliquing angle. Strokes are ordinary draw items, so the text looks identical on screen, in PDF,
/// SVG and plots, and a DXF round-trip keeps the SHX font file name in the STYLE table. TrueType/OpenType styles
/// (all macOS fonts) keep being drawn as text by the platform.
public enum TextStyleFonts {
    /// Name of the bundled single-stroke font.
    public static let strokeFontName = "Archi Stroke"
    /// SHX font names drawn with the bundled stroke font.
    public static let shxNames: Set<String> = ["txt", "simplex", "romans", "romand", "romanc", "romant", "isocp", "isocpeur", "iso",
                                                "isoct", "iso3098", "monotxt", "complex", "italic", "gothice", "scripts", "archquik", "archstroke", "archi stroke", "stroke"]
    /// Variable: "truetype" draws SHX fonts from imported drawings with the substitute TrueType font instead of strokes.
    public static let shxModeVariable = "SHXFONTS"

    /// Whether a font name is a single-stroke font.
    public static func isStrokeFont(_ font: String) -> Bool {
        let f = font.trimmingCharacters(in: .whitespaces).lowercased()
        if f.hasSuffix(".shx") { return true }
        return shxNames.contains(f)
    }

    /// The text style used by a text object (case-insensitive; the first style when not found).
    public static func style(_ name: String, doc: ArchiDocument) -> TextStyle? {
        doc.textStyles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? doc.textStyles.first
    }

    /// Obliquing angle of a style in radians. Styles saved by older builds stored degrees; an angle beyond the valid
    /// ±85° range in radians is read as degrees.
    public static func obliqueRadians(_ s: TextStyle) -> Double {
        let v = s.oblique
        if abs(v) > 85 * .pi / 180 + 1e-9 { return v * .pi / 180 }
        return v
    }

    /// Width factor of a style (0 or negative = 1).
    public static func widthFactor(_ s: TextStyle) -> Double { s.widthFactor > 0 ? s.widthFactor : 1 }

    /// Whether text in this style is drawn with the stroke font: the style names a stroke font, or it came from a DXF
    /// SHX font and still shows the substitute family (SHXFONTS ≠ truetype).
    public static func usesStrokes(_ s: TextStyle, doc: ArchiDocument) -> Bool {
        if isStrokeFont(s.font) { return true }
        guard (doc.variable(shxModeVariable) ?? "").lowercased() != "truetype",
              let file = doc.variable("DXFFONT:" + s.name), file.lowercased().hasSuffix(".shx") else { return false }
        return DXFFonts.family(fromFile: file).caseInsensitiveCompare(s.font) == .orderedSame
    }

    /// Stroke draw items for a text object when its style uses a stroke font; nil otherwise.
    public static func strokeItems(_ t0: TextGeom, doc: ArchiDocument, color: RGBA, lineweight: Double) -> [DrawItem]? {
        guard let s = style(t0.style, doc: doc), usesStrokes(s, doc: doc) else { return nil }
        var t = t0
        if t.height <= 0 { t.height = s.height > 0 ? s.height : 2.5 }
        let st = StrokeStyle(color: color, lineweight: lineweight)
        return StrokeFont.strokes(t, widthFactor: widthFactor(s), oblique: obliqueRadians(s)).filter { $0.count >= 2 }.map { .stroke(points: $0, closed: false, style: st) }
    }

    /// Whether a text entity is drawn with strokes.
    public static func drawsStrokes(_ t: TextGeom, doc: ArchiDocument) -> Bool {
        guard let s = style(t.style, doc: doc) else { return false }
        return usesStrokes(s, doc: doc)
    }

    /// One-line description of a style for listings.
    public static func describe(_ s: TextStyle, doc: ArchiDocument) -> String {
        let kind = usesStrokes(s, doc: doc) ? "stroke font" : "TrueType"
        return "\(s.name): \(s.font) (\(kind)), height \(fmt(s.height)), width factor \(fmt(widthFactor(s))), oblique \(fmt(obliqueRadians(s) * 180 / .pi))°"
    }
}
