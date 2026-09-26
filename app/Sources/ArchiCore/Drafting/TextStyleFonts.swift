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

    // MARK: Width factor and obliquing for TrueType text (ANN-004)

    /// Resolved appearance of a text object: font family, width factor and obliquing angle (radians) of its style.
    public struct Shape: Equatable {
        public var font: String; public var widthFactor: Double; public var oblique: Double
        public init(font: String, widthFactor: Double = 1, oblique: Double = 0) { self.font = font; self.widthFactor = widthFactor; self.oblique = oblique }
        /// Whether the text is drawn plainly (no horizontal scaling or slant).
        public var isPlain: Bool { abs(widthFactor - 1) < 1e-9 && abs(oblique) < 1e-9 }
        /// Glyph transform in the text's local frame (baseline along +x): x' = a·x + c·y, y' = b·x + d·y.
        /// Renderers concatenate it after rotating to the text direction (CGAffineTransform(a:b:c:d:tx:0,ty:0)).
        public var glyphMatrix: (a: Double, b: Double, c: Double, d: Double) { (widthFactor, 0, tan(oblique), 1) }
    }

    /// Shape of a text object by its style name (a text item keeps `TextGeom.style`, so renderers can look it up).
    public static func shape(_ t: TextGeom, doc: ArchiDocument) -> Shape {
        guard let s = style(t.style, doc: doc) else { return Shape(font: "Helvetica") }
        return Shape(font: s.font, widthFactor: widthFactor(s), oblique: obliqueRadians(s))
    }

    /// Maps a point given in the text's plain (unscaled, upright) layout into world coordinates, applying the style's
    /// width factor and slant about the insertion point. Used for boxes, grips and hit tests of styled text.
    public static func place(_ local: Vec2, text t: TextGeom, shape: Shape) -> Vec2 {
        let m = shape.glyphMatrix
        let q = Vec2(m.a * local.x + m.c * local.y, m.b * local.x + m.d * local.y)
        return t.position + q.rotated(by: t.rotation)
    }

    /// Box corners of a text object honouring its style's width factor and obliquing angle (a parallelogram for slanted text).
    public static func boxCorners(_ t: TextGeom, doc: ArchiDocument) -> [Vec2] {
        let sh = shape(t, doc: doc)
        let plain = GeometryOps.textBoxCorners(t)
        guard !sh.isPlain else { return plain }
        // Back to the local frame, scale only unwrapped text horizontally (wrapped text keeps its frame width), then slant.
        let inv = Transform2D.rotation(-t.rotation) * Transform2D.translation(-t.position)
        let wf = t.width > 0 ? 1 : sh.widthFactor
        return plain.map { p -> Vec2 in
            let l = inv.apply(p)
            return t.position + Vec2(l.x * wf + tan(sh.oblique) * l.y, l.y).rotated(by: t.rotation)
        }
    }
}
