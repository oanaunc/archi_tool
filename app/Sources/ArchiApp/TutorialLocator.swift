// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import Vision

/// Finds UI elements by the text they show: the window is captured (as for the video) and read with Vision text
/// recognition, in process and without any permission. SwiftUI controls are not exposed to in-process accessibility
/// queries, so reading the rendered labels is the reliable way to aim the tutorial cursor at "Wall", "Layers" or "3D".
@MainActor
enum TutorialLocator {
    struct Word: Equatable {
        var text: String
        /// Window coordinates (points, bottom-left origin).
        var rect: CGRect
        /// A whole recognised line (not one word of a longer line).
        var line = true
    }

    /// Recognised text lines of a window (the window alone, without other windows over it).
    static func words(in window: NSWindow) -> [Word] {
        let layers = TutorialCapture.layers(main: window, includeOthers: false)
        guard !layers.isEmpty else { return [] }
        let size = window.frame.size
        // Read at 2 pixels per point at least: small panel labels (8.5 pt) need it.
        let k: CGFloat = max(2, window.backingScaleFactor)
        let w = Int(size.width * k), h = Int(size.height * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: k, y: k)
        for l in layers { ctx.draw(l.image, in: l.rect) }
        guard let img = ctx.makeImage() else { return [] }
        return recognize(img, size: size)
    }

    static func recognize(_ img: CGImage, size: CGSize) -> [Word] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.minimumTextHeight = 0.006
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        do { try handler.perform([req]) } catch { return [] }
        var out: [Word] = []
        for obs in req.results ?? [] {
            guard let cand = obs.topCandidates(1).first else { continue }
            let s = cand.string
            // Whole line, plus each word with its own box (lines often hold several ribbon labels).
            out.append(Word(text: s, rect: rect(obs.boundingBox, size)))
            var idx = s.startIndex
            for part in s.split(separator: " ", omittingEmptySubsequences: true) {
                guard let r = s.range(of: part, range: idx..<s.endIndex) else { continue }
                idx = r.upperBound
                if part.count < s.count, let bb = try? cand.boundingBox(for: r)?.boundingBox { out.append(Word(text: String(part), rect: rect(bb, size), line: false)) }
            }
        }
        return out
    }

    private static func rect(_ bb: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: bb.minX * size.width, y: bb.minY * size.height, width: bb.width * size.width, height: bb.height * size.height)
    }

    /// The best match for a label inside a region (window coordinates): exact line or word first, then a line starting
    /// with the label (two-line ribbon titles), then any line containing it.
    static func find(_ label: String, in words: [Word], region: CGRect? = nil, prefer: ((Word, Word) -> Bool)? = nil) -> Word? {
        let l = norm(label)
        guard !l.isEmpty else { return nil }
        let inRegion = words.filter { region == nil || region!.intersects($0.rect) }
        let exact = inRegion.filter { norm($0.text) == l }
        let exactLines = exact.filter(\.line)
        if !exactLines.isEmpty { return prefer.map { exactLines.sorted(by: $0).first } ?? exactLines.first }
        if !exact.isEmpty { return prefer.map { exact.sorted(by: $0).first } ?? exact.first }
        // Multi-word labels split into lines or words ("Curtain Wall" → "Curtain" / "Wall").
        let first = l.split(separator: " ").first.map(String.init) ?? l
        let starts = inRegion.filter { norm($0.text).hasPrefix(l) || (first != l && norm($0.text) == first) }
        if !starts.isEmpty { return prefer.map { starts.sorted(by: $0).first } ?? starts.min { $0.text.count < $1.text.count } }
        let contains = inRegion.filter { norm($0.text).contains(l) }
        return prefer.map { contains.sorted(by: $0).first } ?? contains.min { $0.text.count < $1.text.count }
    }

    /// Case-insensitive, and forgiving about OCR look-alikes and trailing punctuation ("Open…").
    static func norm(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".…:")))
        t = t.replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "|", with: "l")
        return t
    }

    /// Frames of the window's focusable controls (SwiftUI gives each button a focus ring view), in window coordinates.
    static func buttonRects(in window: NSWindow) -> [CGRect] {
        guard let root = window.contentView else { return [] }
        let bounds = CGRect(origin: .zero, size: window.frame.size)
        var out: [CGRect] = []
        func walk(_ v: NSView) {
            if v.isHidden { return }
            if String(describing: type(of: v)) == "_FocusRingView" {
                let r = v.convert(v.bounds, to: nil)
                if r.width > 4, r.height > 4, bounds.contains(CGPoint(x: r.midX, y: r.midY)) { out.append(r) }
                return
            }
            for sv in v.subviews { walk(sv) }
        }
        walk(root)
        // One rect per control (nested focus views repeat the same frame).
        var unique: [CGRect] = []
        for r in out where !unique.contains(where: { abs($0.minX - r.minX) < 1 && abs($0.minY - r.minY) < 1 && abs($0.width - r.width) < 1 }) { unique.append(r) }
        return unique
    }

    /// Controls in a region, in reading order (top row first, then left to right).
    static func controls(in window: NSWindow, region: CGRect, width: ClosedRange<CGFloat> = 4...400, height: ClosedRange<CGFloat> = 4...200) -> [CGRect] {
        buttonRects(in: window).filter { region.contains(CGPoint(x: $0.midX, y: $0.midY)) && width.contains($0.width) && height.contains($0.height) }
            .sorted { abs($0.midY - $1.midY) > 4 ? $0.midY > $1.midY : $0.midX < $1.midX }
    }

    /// The control containing (or nearest to) a recognised label.
    static func control(for word: Word, in window: NSWindow, maxDistance: CGFloat = 30) -> CGRect? {
        let c = CGPoint(x: word.rect.midX, y: word.rect.midY)
        let rects = buttonRects(in: window)
        if let r = rects.filter({ $0.contains(c) }).min(by: { $0.width * $0.height < $1.width * $1.height }) { return r }
        let near = rects.map { r -> (CGRect, CGFloat) in
            let dx = max(r.minX - c.x, 0, c.x - r.maxX), dy = max(r.minY - c.y, 0, c.y - r.maxY)
            return (r, hypot(dx, dy))
        }.filter { $0.1 <= maxDistance }.min { $0.1 < $1.1 }
        return near?.0
    }

    /// Clicks a point of the window with real mouse events (delivered in process through the window, with a run-loop
    /// turn between press and release as with a real click). `direct` sends them to the view under the point instead.
    static func click(_ p: CGPoint, in window: NSWindow, direct: Bool = false) async {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: Int.random(in: 1...1_000_000), clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        let target = direct ? (window.contentView?.superview ?? window.contentView)?.hitTest(p) : nil
        if let e = event(.leftMouseDown) { if let v = target { v.mouseDown(with: e) } else { window.sendEvent(e) } }
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let e = event(.leftMouseUp) { if let v = target { v.mouseUp(with: e) } else { window.sendEvent(e) } }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}
