// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import AVFoundation
import CoreVideo

/// Captures the app window (with its SceneKit viewports and any other app windows over it) as images, without the
/// screen-recording permission: `cacheDisplay` for AppKit/SwiftUI content plus `SCNView.snapshot()` for Metal views,
/// like `FileController.snapshotWindow`.
@MainActor
enum TutorialCapture {
    struct Layer { var image: CGImage; var rect: CGRect; var shadow: Bool }

    /// The window as layers in the main window's coordinate space (points, bottom-left origin): the window itself, its
    /// 3D views, then other visible app windows that overlap it (sheets, dialogs, the render window, floating panels).
    /// Set to redraw every view on the next capture (after a new document or a mode change).
    static var fullRedraw = true
    /// Capture with CALayer rendering instead of the views' drawing (`--tutorial-capture layer`).
    static var useLayerRendering = false

    static func layers(main: NSWindow, includeOthers: Bool = true) -> [Layer] {
        var out: [Layer] = []
        out += windowLayers(main, offset: .zero, shadow: false)
        defer { fullRedraw = false }
        guard includeOthers else { return out }
        for w in NSApp.orderedWindows.reversed() where w !== main && w.isVisible && !w.isMiniaturized && w.alphaValue > 0.01 {
            let cls = String(describing: type(of: w))
            if cls.contains("ToolTip") || cls.contains("StatusBar") || cls.contains("Menu") { continue }
            guard w.frame.intersects(main.frame) else { continue }
            let off = CGPoint(x: w.frame.minX - main.frame.minX, y: w.frame.minY - main.frame.minY)
            out += windowLayers(w, offset: off, shadow: true)
        }
        return out
    }

    private static func windowLayers(_ w: NSWindow, offset: CGPoint, shadow: Bool) -> [Layer] {
        guard let view = w.contentView?.superview ?? w.contentView, view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return [] }
        // Views are drawn by the window's display cycle, which does not run while the screen sleeps: draw pending
        // changes now (a full redraw when asked).
        // Views draw outside their bounds unless they clip (macOS 14); in a cached drawing of the whole window the plan
        // canvas would then paint over the ribbon.
        func clip(_ v: NSView) { if !v.clipsToBounds { v.clipsToBounds = true }; v.subviews.forEach(clip) }
        clip(view)
        view.layoutSubtreeIfNeeded()
        if fullRedraw { view.display() } else { w.displayIfNeeded() }
        // Layers marked for display (the plan canvas) are normally drawn by the display cycle, which stops while the
        // screen is locked or asleep.
        func displayLayers(_ l: CALayer) { if l.needsDisplay() { l.displayIfNeeded() }; l.sublayers?.forEach(displayLayers) }
        if let l = view.layer { displayLayers(l) }
        var cgImage: CGImage?
        if useLayerRendering, let layer = view.layer {
            // Renders the committed layer tree (what the window server would show), including content that the
            // view drawing path skips.
            let k = w.backingScaleFactor
            if let ctx = CGContext(data: nil, width: Int(view.bounds.width * k), height: Int(view.bounds.height * k), bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                ctx.scaleBy(x: k, y: k)
                if view.isFlipped { ctx.translateBy(x: 0, y: view.bounds.height); ctx.scaleBy(x: 1, y: -1) }
                layer.render(in: ctx)
                cgImage = ctx.makeImage()
            }
        }
        if cgImage == nil { view.cacheDisplay(in: view.bounds, to: rep); cgImage = rep.cgImage }
        guard let cg = cgImage else { return [] }
        var out = [Layer(image: cg, rect: CGRect(origin: offset, size: w.frame.size), shadow: shadow)]
        func scnViews(_ v: NSView) -> [SCNView] { (v as? SCNView).map { [$0] } ?? v.subviews.flatMap(scnViews) }
        for sv in scnViews(view) where !sv.isHiddenOrHasHiddenAncestor && sv.bounds.width > 2 && sv.bounds.height > 2 {
            var r = sv.convert(sv.bounds, to: nil)
            r.origin.x += offset.x; r.origin.y += offset.y
            let snap = sv.snapshot()
            if let c = snap.cgImage(forProposedRect: nil, context: nil, hints: nil) { out.append(Layer(image: c, rect: r, shadow: false)) }
        }
        return out
    }
}

/// H.264 MP4 writer fed with frames drawn into Core Graphics contexts.
final class TutorialVideoWriter {
    let url: URL
    let width: Int, height: Int, fps: Int32
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private(set) var frames: Int64 = 0

    init(url: URL, width: Int, height: Int, fps: Int = TutorialTiming.fps) throws {
        self.url = url
        self.width = width - width % 2; self.height = height - height % 2; self.fps = Int32(fps)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let pixels = Double(self.width * self.height)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: self.width, AVVideoHeightKey: self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(min(24_000_000, max(4_000_000, pixels * 2.6))),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ] as [String: Any],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw NSError(domain: "Tutorial", code: 1, userInfo: [NSLocalizedDescriptionKey: "H.264 cannot encode \(self.width)×\(self.height)."])
        }
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: self.width, kCVPixelBufferHeightKey as String: self.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw NSError(domain: "Tutorial", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add the video track."]) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Tutorial", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot start writing."]) }
        writer.startSession(atSourceTime: .zero)
    }

    /// Appends one frame; `draw` paints into a context of `width`×`height` pixels (bottom-left origin).
    func append(_ draw: (CGContext) -> Void) throws {
        var waited = 0
        while !input.isReadyForMoreMediaData && waited < 2000 { usleep(2000); waited += 1 }
        guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? NSError(domain: "Tutorial", code: 4, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer pool."]) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buf = pb else { throw NSError(domain: "Tutorial", code: 5, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer."]) }
        CVPixelBufferLockBaseAddress(buf, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            draw(ctx)
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        guard adaptor.append(buf, withPresentationTime: CMTime(value: frames, timescale: fps)) else {
            throw writer.error ?? NSError(domain: "Tutorial", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot append frame \(frames)."])
        }
        frames += 1
    }

    func finish() async throws {
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Tutorial", code: 7, userInfo: [NSLocalizedDescriptionKey: "Writing failed."]) }
    }

    func cancel() { writer.cancelWriting() }
}

/// Everything drawn over the captured app window: cursor, click ripples, lower-third captions, keystroke pills, notes and
/// the title/end cards. Coordinates are points in the main window (bottom-left origin).
struct TutorialOverlay {
    struct Ripple { var point: CGPoint; var time: Double }
    struct Note { var text: String; var point: CGPoint?; var start: Double; var end: Double }

    var size = CGSize(width: 1440, height: 900)
    var time: Double = 0
    var cursor = CGPoint(x: 720, y: 450)
    var cursorVisible = false
    /// Over the plan canvas the app draws its own crosshair; the arrow is then only a small marker.
    var cursorOverCanvas = false
    var pressed = false
    var ripples: [Ripple] = []
    var captionTitle = "", captionSubtitle = ""
    var captionChanged: Double = -10
    var previousCaption: (String, String)?
    var pill = ""
    var pillTime: Double = -10
    var pillEnter: Double = -10
    var notes: [Note] = []
    var cardTitle = "", cardSubtitle = "", cardNumber = ""
    var introEnd: Double = TutorialTiming.intro
    var outroStart: Double = .infinity
    /// Bottom of the area where captions may go (above the command line and status bar).
    var captionBaseline: CGFloat = 120

    static let accent = NSColor(srgbRed: 0xF5 / 255.0, green: 0xC5 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    static let panel = NSColor(srgbRed: 0x1E / 255.0, green: 0x1F / 255.0, blue: 0x22 / 255.0, alpha: 1)

    mutating func click(at p: CGPoint) { ripples.append(Ripple(point: p, time: time)); ripples.removeAll { time - $0.time > 1 } }
    mutating func caption(_ t: String, _ s: String) {
        if t == captionTitle && s == captionSubtitle { return }
        previousCaption = captionTitle.isEmpty ? nil : (captionTitle, captionSubtitle)
        captionTitle = t; captionSubtitle = s; captionChanged = time
    }

    /// Draws the overlay into `ctx`, which is scaled so one unit is one window point.
    func draw(in ctx: CGContext) {
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        defer { NSGraphicsContext.restoreGraphicsState() }
        drawNotes(ctx)
        drawCaption(ctx)
        drawPill(ctx)
        drawRipples(ctx)
        if cursorVisible { drawCursor(ctx) }
        drawCards(ctx)
    }

    private static func ease(_ t: Double) -> Double { let x = max(0, min(1, t)); return x * x * (3 - 2 * x) }

    private func roundedPanel(_ ctx: CGContext, _ r: CGRect, radius: CGFloat, alpha: CGFloat, shadow: Bool = true) {
        ctx.saveGState()
        if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 14, color: NSColor.black.withAlphaComponent(0.55 * alpha).cgColor) }
        ctx.setFillColor(TutorialOverlay.panel.withAlphaComponent(0.94 * alpha).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.10 * alpha).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func attr(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, alpha: CGFloat, mono: Bool = false) -> NSAttributedString {
        let f = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; p.lineSpacing = 2
        return NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha), .paragraphStyle: p])
    }

    private func drawCaption(_ ctx: CGContext) {
        let fadeIn = TutorialOverlay.ease((time - captionChanged) / 0.35)
        func block(_ title: String, _ sub: String, alpha: CGFloat, slide: CGFloat) {
            guard !title.isEmpty, alpha > 0.01 else { return }
            let maxW: CGFloat = min(760, size.width * 0.55)
            let t = attr(title, size: 21, weight: .semibold, color: .white, alpha: alpha)
            let s = attr(sub, size: 14.5, color: NSColor(white: 0.82, alpha: 1), alpha: alpha)
            let tb = t.boundingRect(with: CGSize(width: maxW, height: 200), options: [.usesLineFragmentOrigin])
            let sb = sub.isEmpty ? .zero : s.boundingRect(with: CGSize(width: maxW, height: 200), options: [.usesLineFragmentOrigin])
            let w = max(tb.width, sb.width) + 44, h = tb.height + (sub.isEmpty ? 0 : sb.height + 6) + 30
            let r = CGRect(x: 28 - slide, y: captionBaseline + 14, width: w, height: h)
            roundedPanel(ctx, r, radius: 10, alpha: alpha)
            ctx.setFillColor(TutorialOverlay.accent.withAlphaComponent(alpha).cgColor)
            ctx.fill(CGRect(x: r.minX, y: r.minY + 10, width: 4, height: r.height - 20))
            t.draw(with: CGRect(x: r.minX + 22, y: r.maxY - 15 - tb.height, width: maxW, height: tb.height + 4), options: [.usesLineFragmentOrigin])
            if !sub.isEmpty { s.draw(with: CGRect(x: r.minX + 22, y: r.minY + 15, width: maxW, height: sb.height + 4), options: [.usesLineFragmentOrigin]) }
        }
        // The old caption leaves first, then the new one slides in (they never overlap).
        let out = TutorialOverlay.ease((time - captionChanged) / 0.22)
        let inn = TutorialOverlay.ease((time - captionChanged - 0.18) / 0.32)
        if let p = previousCaption, out < 1 { block(p.0, p.1, alpha: CGFloat(1 - out), slide: CGFloat(out) * 16) }
        block(captionTitle, captionSubtitle, alpha: CGFloat(inn), slide: CGFloat(1 - inn) * -24)
        _ = fadeIn
    }

    private func drawPill(_ ctx: CGContext) {
        guard !pill.isEmpty else { return }
        let age = time - pillTime
        let alpha = CGFloat(age < 2.2 ? 1 : max(0, 1 - (age - 2.2) / 0.5))
        guard alpha > 0.01 else { return }
        var text = pill
        if text.count > 46 { text = "…" + String(text.suffix(45)) }
        let a = attr(text, size: 17, weight: .medium, color: .white, alpha: alpha, mono: true)
        let b = a.size()
        let keyW: CGFloat = 46
        let enterFlash = max(0, 1 - (time - pillEnter) / 0.5)
        let w = b.width + 34 + keyW, h: CGFloat = 44
        let r = CGRect(x: size.width - w - 28, y: captionBaseline + 14, width: w, height: h)
        roundedPanel(ctx, r, radius: 22, alpha: alpha)
        a.draw(at: CGPoint(x: r.minX + 20, y: r.midY - b.height / 2))
        // Return key cap, lit in the accent colour for a moment after Enter.
        let k = CGRect(x: r.maxX - keyW - 8, y: r.minY + 8, width: keyW, height: h - 16)
        ctx.saveGState()
        ctx.setFillColor((enterFlash > 0 ? TutorialOverlay.accent.withAlphaComponent(alpha * CGFloat(0.35 + 0.65 * enterFlash)) : NSColor(white: 1, alpha: 0.12 * alpha)).cgColor)
        ctx.addPath(CGPath(roundedRect: k, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        ctx.restoreGState()
        let ka = attr("⏎", size: 15, weight: .semibold, color: enterFlash > 0.3 ? NSColor(white: 0.1, alpha: 1) : .white, alpha: alpha)
        let ks = ka.size()
        ka.draw(at: CGPoint(x: k.midX - ks.width / 2, y: k.midY - ks.height / 2))
    }

    private func drawNotes(_ ctx: CGContext) {
        for n in notes where time >= n.start && time <= n.end + 0.4 {
            let alpha = CGFloat(min(TutorialOverlay.ease((time - n.start) / 0.3), 1 - TutorialOverlay.ease((time - n.end) / 0.4)))
            guard alpha > 0.01 else { continue }
            let a = attr(n.text, size: 15, weight: .medium, color: .white, alpha: alpha)
            let b = a.boundingRect(with: CGSize(width: 380, height: 300), options: [.usesLineFragmentOrigin])
            let w = b.width + 32, h = b.height + 22
            var r: CGRect
            if let p = n.point {
                // Callout above-right of the point, kept inside the frame, with a leader line and a dot.
                r = CGRect(x: p.x + 40, y: p.y + 40, width: w, height: h)
                if r.maxX > size.width - 16 { r.origin.x = p.x - 40 - w }
                if r.maxY > size.height - 16 { r.origin.y = p.y - 40 - h }
                r.origin.x = max(16, r.origin.x); r.origin.y = max(16, r.origin.y)
                ctx.saveGState()
                ctx.setStrokeColor(TutorialOverlay.accent.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(2)
                let edge = CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
                ctx.move(to: p); ctx.addLine(to: edge); ctx.strokePath()
                ctx.setFillColor(TutorialOverlay.accent.withAlphaComponent(alpha).cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                ctx.restoreGState()
            } else {
                r = CGRect(x: (size.width - w) / 2, y: size.height - 150 - h, width: w, height: h)
            }
            roundedPanel(ctx, r, radius: 8, alpha: alpha)
            ctx.saveGState()
            ctx.setStrokeColor(TutorialOverlay.accent.withAlphaComponent(0.9 * alpha).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.strokePath()
            ctx.restoreGState()
            a.draw(with: CGRect(x: r.minX + 16, y: r.minY + 11, width: 380, height: b.height + 4), options: [.usesLineFragmentOrigin])
        }
    }

    private func drawRipples(_ ctx: CGContext) {
        for rp in ripples {
            let t = (time - rp.time) / 0.55
            guard t >= 0, t <= 1 else { continue }
            let e = CGFloat(TutorialOverlay.ease(t))
            let r = 6 + 26 * e
            ctx.saveGState()
            ctx.setStrokeColor(TutorialOverlay.accent.withAlphaComponent(1 - e).cgColor)
            ctx.setLineWidth(3 * (1 - e) + 1)
            ctx.strokeEllipse(in: CGRect(x: rp.point.x - r, y: rp.point.y - r, width: 2 * r, height: 2 * r))
            ctx.setFillColor(TutorialOverlay.accent.withAlphaComponent(0.35 * (1 - e)).cgColor)
            let r2 = 5 + 8 * e
            ctx.fillEllipse(in: CGRect(x: rp.point.x - r2, y: rp.point.y - r2, width: 2 * r2, height: 2 * r2))
            ctx.restoreGState()
        }
    }

    private func drawCursor(_ ctx: CGContext) {
        let p = cursor
        if cursorOverCanvas {
            // The canvas draws the crosshair; add a soft accent ring so viewers can follow it.
            ctx.saveGState()
            ctx.setStrokeColor(TutorialOverlay.accent.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
            ctx.restoreGState()
            return
        }
        // macOS-style arrow, tip at the cursor position (y grows upwards).
        let s: CGFloat = pressed ? 0.9 : 1
        let pts: [CGPoint] = [(0, 0), (0, -17), (4.2, -13.2), (7.2, -20), (10, -18.8), (7.1, -12.2), (12.4, -12.2)].map { CGPoint(x: p.x + $0.0 * s * 1.15, y: p.y + $0.1 * s * 1.15) }
        let path = CGMutablePath()
        path.addLines(between: pts); path.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(1.4); ctx.setLineJoin(.round)
        ctx.addPath(path); ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawCards(_ ctx: CGContext) {
        // Title card at the start, end card at the end.
        var alpha: CGFloat = 0, isEnd = false
        if time < introEnd { alpha = CGFloat(1 - TutorialOverlay.ease((time - (introEnd - 0.6)) / 0.6)) }
        else if time >= outroStart { alpha = CGFloat(TutorialOverlay.ease((time - outroStart) / 0.6)); isEnd = true }
        guard alpha > 0.01 else { return }
        ctx.saveGState()
        ctx.setFillColor(NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 0.86 * alpha).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.restoreGState()
        let cx = size.width / 2, cy = size.height / 2
        let num = attr(isEnd ? "OANARINA ARCHI TOOL" : "TUTORIAL \(cardNumber)", size: 15, weight: .semibold, color: TutorialOverlay.accent, alpha: alpha)
        let title = attr(isEnd ? "Thanks for watching" : cardTitle, size: 46, weight: .bold, color: .white, alpha: alpha)
        let sub = attr(isEnd ? "Free for macOS · www.oanarinaldi.com" : cardSubtitle, size: 19, color: NSColor(white: 0.8, alpha: 1), alpha: alpha)
        let nb = num.size(), tb = title.boundingRect(with: CGSize(width: size.width - 200, height: 300), options: [.usesLineFragmentOrigin])
        let sb = sub.boundingRect(with: CGSize(width: size.width - 300, height: 300), options: [.usesLineFragmentOrigin])
        num.draw(at: CGPoint(x: cx - nb.width / 2, y: cy + tb.height / 2 + 24))
        title.draw(with: CGRect(x: cx - tb.width / 2, y: cy - tb.height / 2, width: tb.width + 2, height: tb.height + 4), options: [.usesLineFragmentOrigin])
        ctx.saveGState()
        ctx.setFillColor(TutorialOverlay.accent.withAlphaComponent(alpha).cgColor)
        ctx.fill(CGRect(x: cx - 36, y: cy - tb.height / 2 - 22, width: 72, height: 4))
        ctx.restoreGState()
        sub.draw(with: CGRect(x: cx - sb.width / 2, y: cy - tb.height / 2 - 40 - sb.height, width: sb.width + 2, height: sb.height + 4), options: [.usesLineFragmentOrigin])
    }
}
