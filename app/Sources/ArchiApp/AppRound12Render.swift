// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import CoreText
import ArchiCore

/// Document-dependent drawing details the app renderers need beyond the draw items: the width factor and obliquing
/// angle of text styles (ANN-004) and exact per-pixel image adjustments (DRW-086: contrast above 50 cannot be drawn
/// with veils). The canvas, PDF plots, layered PDF and PNG exports register the document they are drawing.
enum AppRenderInfo {
    /// Document being drawn (a copy-on-write value: storing it is cheap).
    nonisolated(unsafe) private(set) static var doc: ArchiDocument?
    /// Whole-text formatting of text entities (bold, italic, underline, font — ANN-003), by entity id.
    nonisolated(unsafe) private(set) static var textFormats: [EntityID: TextFormat] = [:]
    /// Adjustments of images needing pixel processing, by image path.
    nonisolated(unsafe) private(set) static var pixelAdjust: [String: ImageDisplay.Adjustment] = [:]

    static func register(_ d: ArchiDocument) {
        doc = d
        var m: [String: ImageDisplay.Adjustment] = [:]
        for e in d.entities {
            guard case .image(let im) = e.geometry else { continue }
            let a = ImageDisplay.adjustment(e)
            if ImageDisplay.needsPixelProcessing(a), m[im.path] == nil { m[im.path] = a }
        }
        for l in d.layouts { for e in l.entities {
            guard case .image(let im) = e.geometry else { continue }
            let a = ImageDisplay.adjustment(e)
            if ImageDisplay.needsPixelProcessing(a), m[im.path] == nil { m[im.path] = a }
        } }
        pixelAdjust = m
        var tf: [EntityID: TextFormat] = [:]
        for e in d.entities { if case .text = e.geometry, let f = TextFormat(props: e.props) { tf[e.id] = f } }
        textFormats = tf
    }

    /// Whole-text formatting stored on a text entity (props "font", "bold", "italic", "underline", as read from MTEXT).
    struct TextFormat: Equatable {
        var font: String?
        var bold = false, italic = false, underline = false
        init(font: String? = nil, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
            self.font = font; self.bold = bold; self.italic = italic; self.underline = underline
        }
        init?(props: [String: String]) {
            let f = props["font"].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            self.init(font: f, bold: props["bold"] == "1", italic: props["italic"] == "1", underline: props["underline"] == "1")
            if isPlain { return nil }
        }
        var isPlain: Bool { font == nil && !bold && !italic && !underline }
        func write(to props: inout [String: String]) {
            props["font"] = font
            props["bold"] = bold ? "1" : nil
            props["italic"] = italic ? "1" : nil
            props["underline"] = underline ? "1" : nil
            // A stale MTEXT string from DXF would otherwise disagree with the edited formatting.
            props["mtext"] = nil
        }
    }

    /// Font (PostScript name) for a family with bold/italic traits, and whether italic had to be synthesised (slant).
    nonisolated(unsafe) private static var styledCache: [String: (String, Bool)] = [:]
    static func styledFont(_ family: String, bold: Bool, italic: Bool) -> (name: String, syntheticItalic: Bool) {
        guard bold || italic else { return (family, false) }
        let key = "\(family)|\(bold)|\(italic)"
        if let c = styledCache[key] { return c }
        var result = (family, italic)
        if var f = NSFont(name: family, size: 12) ?? NSFont(name: "Helvetica", size: 12) {
            let fm = NSFontManager.shared
            if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
            if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            let hasItalic = fm.traits(of: f).contains(.italicFontMask) || f.fontDescriptor.symbolicTraits.contains(.italic)
            result = (f.fontName, italic && !hasItalic)
        }
        styledCache[key] = result
        return result
    }
    /// Slant used when a family has no italic face.
    static let syntheticItalicSlant = tan(12 * Double.pi / 180)

    /// Runs a draw-list build with the renderer applying image pixels itself (the core then omits the veils of
    /// images that need pixel processing, so the adjustment is applied once).
    static func withPixels<T>(_ body: () throws -> T) rethrows -> T {
        let old = ImageDisplay.rendererAppliesPixels
        ImageDisplay.rendererAppliesPixels = true
        defer { ImageDisplay.rendererAppliesPixels = old }
        return try body()
    }

    /// Glyph shape of a text item (nil when plain or no document is registered).
    static func shape(_ t: TextGeom) -> TextStyleFonts.Shape? {
        guard let d = doc, !t.style.isEmpty else { return nil }
        let s = TextStyleFonts.shape(t, doc: d)
        return s.isPlain ? nil : s
    }

    /// Affine glyph transform (width factor and slant) in the text's local frame.
    static func glyphTransform(_ s: TextStyleFonts.Shape) -> CGAffineTransform {
        let m = s.glyphMatrix
        return CGAffineTransform(a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c), d: CGFloat(m.d), tx: 0, ty: 0)
    }

    // MARK: Image pixels

    nonisolated(unsafe) private static var adjusted: [String: CGImage] = [:]

    /// The image with an exact adjustment applied to its pixels (cached), or nil when none is needed.
    static func adjustedImage(_ img: CGImage, path: String, background: RGBA) -> CGImage? {
        guard let a = pixelAdjust[path] else { return nil }
        return adjust(img, a, background: background, key: "\(path)|\(a.brightness)|\(a.contrast)|\(a.fade)|\(background.r),\(background.g),\(background.b)")
    }

    static func adjust(_ img: CGImage, _ a: ImageDisplay.Adjustment, background: RGBA, key: String? = nil) -> CGImage? {
        if let k = key, let c = adjusted[k] { return c }
        let w = img.width, h = img.height
        guard w > 0, h > 0, w * h <= 80_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let n = w * h * 4
        var px = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: n))
        ImageDisplay.apply(a, background: background, to: &px, channels: 4, premultiplied: true)
        px.withUnsafeBytes { src in data.copyMemory(from: src.baseAddress!, byteCount: n) }
        guard let out = ctx.makeImage() else { return nil }
        if let k = key { if adjusted.count > 64 { adjusted.removeAll() }; adjusted[k] = out }
        return out
    }

    /// Average sRGB colour of an image (self-tests).
    static func meanColor(_ img: CGImage) -> RGBA? {
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let d = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let p = d.assumingMemoryBound(to: UInt8.self)
        return RGBA(Double(p[0]) / 255, Double(p[1]) / 255, Double(p[2]) / 255, Double(p[3]) / 255)
    }
}
