// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Raster image clipping (DRW-085, IMAGECLIP) and display adjustment (DRW-086, IMAGEADJUST).
///
/// Settings live in entity props, so they persist in .archi files, follow the image when it is moved, rotated or
/// scaled (the clip boundary is stored in image-local unit coordinates: 0,0 = lower-left, 1,1 = upper-right corner),
/// and travel with blocks. They are turned into ordinary draw items after the image — a background-coloured mask
/// outside the clip boundary and translucent veils for fade, brightness and reduced contrast — so the screen, PDF and
/// SVG output all show the same result.
public enum ImageDisplay {
    /// Clip boundary "u,v;u,v;…" in image-local unit coordinates (at least 3 points).
    public static let clipProp = "imageClip"
    /// "0" = clipping turned off (the boundary is kept).
    public static let clipOnProp = "imageClipOn"
    /// "1" = the inside of the boundary is hidden instead of the outside.
    public static let clipInvertProp = "imageClipInvert"
    public static let brightnessProp = "imageBrightness"
    public static let contrastProp = "imageContrast"
    public static let fadeProp = "imageFade"
    /// IMAGEFRAME: 0 frames hidden, 1 shown and plotted (default), 2 shown on screen but not plotted.
    public static let frameVariable = "IMAGEFRAME"

    public struct Adjustment: Equatable {
        public var brightness: Double = 50
        public var contrast: Double = 50
        public var fade: Double = 0
        public init(brightness: Double = 50, contrast: Double = 50, fade: Double = 0) { self.brightness = brightness; self.contrast = contrast; self.fade = fade }
        public var isDefault: Bool { abs(brightness - 50) < 1e-9 && abs(contrast - 50) < 1e-9 && abs(fade) < 1e-9 }
    }

    // MARK: Reading settings

    public static func adjustment(_ e: Entity) -> Adjustment {
        func v(_ k: String, _ d: Double) -> Double { e.props[k].flatMap(Double.init).map { max(0, min(100, $0)) } ?? d }
        return Adjustment(brightness: v(brightnessProp, 50), contrast: v(contrastProp, 50), fade: v(fadeProp, 0))
    }
    public static func setAdjustment(_ a: Adjustment, on e: inout Entity) {
        e.props[brightnessProp] = abs(a.brightness - 50) < 1e-9 ? nil : fmt(a.brightness, 4)
        e.props[contrastProp] = abs(a.contrast - 50) < 1e-9 ? nil : fmt(a.contrast, 4)
        e.props[fadeProp] = abs(a.fade) < 1e-9 ? nil : fmt(a.fade, 4)
    }

    /// Stored clip boundary in unit coordinates.
    public static func clipUV(_ e: Entity) -> [Vec2]? {
        guard let s = e.props[clipProp] else { return nil }
        let pts = s.split(separator: ";").compactMap { part -> Vec2? in
            let c = part.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return c.count == 2 ? Vec2(c[0], c[1]) : nil
        }
        return pts.count >= 3 ? pts : nil
    }
    public static func clipActive(_ e: Entity) -> Bool { clipUV(e) != nil && e.props[clipOnProp] != "0" }

    /// Whether the image has any display setting handled here.
    public static func active(_ e: Entity) -> Bool {
        guard case .image = e.geometry else { return false }
        return clipActive(e) || !adjustment(e).isDefault
    }

    // MARK: Coordinates

    static func transform(_ im: ImageGeom) -> Transform2D { Transform2D.translation(im.origin) * Transform2D.rotation(im.rotation) }
    /// World point of an image-local unit coordinate.
    public static func world(_ im: ImageGeom, _ uv: Vec2) -> Vec2 { transform(im).apply(Vec2(uv.x * im.size.x, uv.y * im.size.y)) }
    /// Image-local unit coordinate of a world point.
    public static func uv(_ im: ImageGeom, _ p: Vec2) -> Vec2 {
        let l = (p - im.origin).rotated(by: -im.rotation)
        return Vec2(im.size.x != 0 ? l.x / im.size.x : 0, im.size.y != 0 ? l.y / im.size.y : 0)
    }
    /// Image frame corners in world coordinates (counter-clockwise for positive sizes).
    public static func frame(_ im: ImageGeom) -> [Vec2] { [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)].map { world(im, $0) } }
    /// Active clip boundary in world coordinates.
    public static func clipBoundary(_ e: Entity) -> [Vec2]? {
        guard case .image(let im) = e.geometry, clipActive(e), let c = clipUV(e) else { return nil }
        return c.map { world(im, $0) }
    }

    /// Sets a clip boundary given in world coordinates: the polygon is intersected with the image frame; returns false
    /// when nothing of the image would remain.
    @discardableResult
    public static func setClip(_ e: inout Entity, boundary: [Vec2]) -> Bool {
        guard case .image(let im) = e.geometry, boundary.count >= 3 else { return false }
        var poly = boundary
        if poly.count > 3, poly.first!.isClose(poly.last!, tol: 1e-9) { poly.removeLast() }
        let parts = PolygonBoolean.apply(.intersect, [poly], [frame(im)]).filter { $0.count >= 3 }
        guard let best = parts.max(by: { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }),
              abs(GeometryOps.signedArea(best)) > 1e-9 * max(1, abs(im.size.x * im.size.y)) else { return false }
        e.props[clipProp] = best.map { uv(im, $0) }.map { "\(fmt($0.x, 9)),\(fmt($0.y, 9))" }.joined(separator: ";")
        e.props[clipOnProp] = nil
        return true
    }
    public static func removeClip(_ e: inout Entity) {
        e.props[clipProp] = nil; e.props[clipOnProp] = nil; e.props[clipInvertProp] = nil
    }

    // MARK: Adjustment model

    /// Veils composited over the image (in order) that realise an adjustment: (colour, alpha).
    /// Brightness above 50 veils towards white, below 50 towards black; contrast below 50 veils towards mid grey; fade
    /// veils towards the drawing background. Contrast above 50 cannot be produced by veils and is left to renderers
    /// that read `adjusted(_:_:background:)` per pixel.
    public static func veils(_ a: Adjustment, background: RGBA) -> [(RGBA, Double)] {
        var out: [(RGBA, Double)] = []
        if a.contrast < 50 - 1e-9 { out.append((RGBA(0.5, 0.5, 0.5), (50 - a.contrast) / 50)) }
        if a.brightness > 50 + 1e-9 { out.append((RGBA(1, 1, 1), (a.brightness - 50) / 50)) }
        if a.brightness < 50 - 1e-9 { out.append((RGBA(0, 0, 0), (50 - a.brightness) / 50)) }
        if a.fade > 1e-9 { out.append((RGBA(background.r, background.g, background.b), a.fade / 100)) }
        return out.filter { $0.1 > 1e-9 }
    }

    /// Adjusted colour of one pixel (the reference model the veils reproduce; contrast above 50 stretches around mid grey).
    public static func adjusted(_ c: RGBA, _ a: Adjustment, background: RGBA) -> RGBA {
        func ch(_ v: Double, _ bg: Double) -> Double {
            var x = v
            if a.contrast >= 50 { x = 0.5 + (x - 0.5) * (a.contrast >= 100 ? 50 : 50 / (100 - a.contrast)) } else { x = x + (0.5 - x) * (50 - a.contrast) / 50 }
            x = max(0, min(1, x))
            if a.brightness > 50 { x = x + (1 - x) * (a.brightness - 50) / 50 } else if a.brightness < 50 { x = x * (1 - (50 - a.brightness) / 50) }
            x = x + (bg - x) * a.fade / 100
            return max(0, min(1, x))
        }
        return RGBA(ch(c.r, background.r), ch(c.g, background.g), ch(c.b, background.b), c.a)
    }

    /// Composites veils over a colour the way the renderers do (source-over).
    public static func composite(_ c: RGBA, veils: [(RGBA, Double)]) -> RGBA {
        var r = c
        for (v, a) in veils { r = RGBA(r.r + (v.r - r.r) * a, r.g + (v.g - r.g) * a, r.b + (v.b - r.b) * a, r.a) }
        return r
    }

    // MARK: Drawing

    /// Lightest grey that paper output keeps (lighter colours print black).
    public static let paperWhite = 0.9
    public static func background(_ options: DrawOptions) -> RGBA { options.forPaper ? RGBA(1, 1, 1) : DraftRendering.screenBackground }

    /// Draw items of an image with clipping / adjustment.
    public static func items(_ e: Entity, _ im: ImageGeom, doc: ArchiDocument, options: DrawOptions, color: RGBA) -> [DrawItem] {
        let bg = background(options)
        let rect = frame(im)
        var out: [DrawItem] = [.image(im)]
        for (c, a) in veils(adjustment(e), background: bg) {
            // Paper output prints near-white colours black (ACI 7); white veils are drawn in the lightest printable grey.
            let v = options.forPaper && c.r > 0.9 && c.g > 0.9 && c.b > 0.9 ? RGBA(paperWhite, paperWhite, paperWhite) : c
            out.append(.fill(loops: [rect], color: RGBA(v.r, v.g, v.b, a)))
        }
        let frameMode = doc.variable(frameVariable).flatMap(Int.init) ?? 1
        if let clip = clipBoundary(e) {
            let mask = options.forPaper ? DrawListBuilder.maskWhite : RGBA(bg.r, bg.g, bg.b, 0.99999)
            if e.props[clipInvertProp] == "1" { out.append(.fill(loops: [clip], color: mask)) }
            else { out.append(.fill(loops: [rect, clip], color: mask)) }
            if frameMode == 1 || (frameMode == 2 && !options.forPaper) {
                out.append(.stroke(points: clip, closed: true, style: StrokeStyle(color: color, lineweight: 0.13)))
            }
        }
        return out
    }
}
