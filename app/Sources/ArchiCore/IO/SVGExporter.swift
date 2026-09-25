// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Exports resolved 2D draw entries as an SVG document (Y axis flipped, one `<g>` per entity).
public enum SVGExporter {
    /// - Parameters:
    ///   - bounds: model-space region to export.
    ///   - pixelsPerUnit: SVG user units (px) per drawing unit.
    public static func export(entries: [DrawEntry], bounds: BBox2, background: RGBA?, pixelsPerUnit: Double = 1) -> String {
        export(entries: entries, bounds: bounds, background: background, pixelsPerUnit: pixelsPerUnit, lineweightScale: 1)
    }

    /// Same as `export`, with plotted line weights (mm at 96 dpi) multiplied by `lineweightScale`.
    public static func export(entries: [DrawEntry], bounds: BBox2, background: RGBA?, pixelsPerUnit: Double, lineweightScale: Double) -> String {
        let ppu = pixelsPerUnit > 0 && pixelsPerUnit.isFinite ? pixelsPerUnit : 1
        let b = bounds.isEmpty ? BBox2(min: .zero, max: Vec2(1, 1)) : bounds
        let w = max(b.width * ppu, 1), h = max(b.height * ppu, 1)
        func X(_ p: Vec2) -> Double { (p.x - b.min.x) * ppu }
        func Y(_ p: Vec2) -> Double { (b.max.y - p.y) * ppu }
        func n(_ v: Double) -> String { fmt(v, 3) }

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" width=\"\(n(w))\" height=\"\(n(h))\" viewBox=\"0 0 \(n(w)) \(n(h))\">\n"
        out += "<!-- Oanarina Archi Tool -->\n"
        if let bg = background {
            out += "<rect x=\"0\" y=\"0\" width=\"\(n(w))\" height=\"\(n(h))\" fill=\"\(bg.hex)\"\(bg.a < 1 ? " fill-opacity=\"\(n(bg.a))\"" : "")/>\n"
        }
        out += "<g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n"
        for e in entries {
            if !e.bounds.isEmpty && !e.bounds.intersects(b) { continue }
            if e.items.isEmpty { continue }
            out += e.id.map { "<g data-id=\"\($0)\">\n" } ?? "<g>\n"
            for it in e.items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    guard pts.count >= 1 else { continue }
                    let sw = max(0.25, st.lineweight * 96 / 25.4 * lineweightScale)
                    var d = ""
                    if pts.count == 1 {
                        d = "M\(n(X(pts[0]))) \(n(Y(pts[0])))h0.01"
                    } else {
                        for (i, p) in pts.enumerated() { d += (i == 0 ? "M" : "L") + "\(n(X(p))) \(n(Y(p)))" }
                        if closed { d += "Z" }
                    }
                    var attrs = "d=\"\(d)\" stroke=\"\(st.color.hex)\" stroke-width=\"\(n(sw))\""
                    if st.color.a < 1 { attrs += " stroke-opacity=\"\(n(st.color.a))\"" }
                    if let dash = dashArray(st.dash, ppu: ppu, strokeWidth: sw) { attrs += " stroke-dasharray=\"\(dash)\"" }
                    out += "<path \(attrs)/>\n"
                case .fill(let loops, let color):
                    var d = ""
                    for l in loops where l.count >= 3 {
                        for (i, p) in l.enumerated() { d += (i == 0 ? "M" : "L") + "\(n(X(p))) \(n(Y(p)))" }
                        d += "Z"
                    }
                    guard !d.isEmpty else { continue }
                    out += "<path d=\"\(d)\" fill=\"\(color.hex)\"\(color.a < 1 ? " fill-opacity=\"\(n(color.a))\"" : "") fill-rule=\"evenodd\" stroke=\"none\"/>\n"
                case .text(let t, let font, let color):
                    out += text(t, font: font, color: color, x: X(t.position), y: Y(t.position), ppu: ppu)
                case .image(let im):
                    let tl = im.origin + Vec2(0, im.size.y).rotated(by: im.rotation)
                    out += "<image x=\"0\" y=\"0\" width=\"\(n(im.size.x * ppu))\" height=\"\(n(im.size.y * ppu))\" preserveAspectRatio=\"none\" transform=\"translate(\(n(X(tl))) \(n(Y(tl)))) rotate(\(n(-deg(im.rotation))))\" xlink:href=\"\(xml(im.path))\" href=\"\(xml(im.path))\"/>\n"
                }
            }
            out += "</g>\n"
        }
        out += "</g>\n</svg>\n"
        return out
    }

    static func dashArray(_ dash: [Double], ppu: Double, strokeWidth: Double) -> String? {
        guard !dash.isEmpty, dash.contains(where: { $0 != 0 }) else { return nil }
        var vals = dash.map { $0 == 0 ? max(0.01, strokeWidth * 0.01) : abs($0) * ppu }
        // SVG alternates dash/gap from a dash; a pattern starting with a gap is rotated.
        if let f = dash.first, f < 0 { vals = Array(vals.dropFirst()) + [vals[0]] }
        return vals.map { fmt($0, 3) }.joined(separator: " ")
    }

    static func text(_ t: TextGeom, font: String, color: RGBA, x: Double, y: Double, ppu: Double) -> String {
        let lines = t.content.components(separatedBy: "\n")
        guard !lines.allSatisfy({ $0.isEmpty }) else { return "" }
        let hgt = t.height * ppu
        let pitch = hgt * 1.5
        let count = Double(lines.count)
        let blockH = hgt + pitch * (count - 1)
        // Baseline of the first line, measured downward from the anchor (SVG y grows downward).
        let first: Double
        switch t.valign {
        case .baseline: first = 0
        case .top: first = hgt
        case .middle: first = hgt - blockH / 2
        case .bottom: first = -(0.2 * hgt + pitch * (count - 1))
        }
        let anchor: String = t.halign == .left ? "start" : (t.halign == .center ? "middle" : "end")
        let fontSize = hgt / 0.717
        var s = "<text transform=\"translate(\(fmt(x, 3)) \(fmt(y, 3)))\(t.rotation != 0 ? " rotate(\(fmt(-deg(t.rotation), 4)))" : "")\" font-family=\"\(xml(font)), Helvetica, Arial, sans-serif\" font-size=\"\(fmt(fontSize, 3))\" fill=\"\(color.hex)\"\(color.a < 1 ? " fill-opacity=\"\(fmt(color.a, 3))\"" : "") stroke=\"none\" text-anchor=\"\(anchor)\" xml:space=\"preserve\">"
        for (i, l) in lines.enumerated() {
            s += "<tspan x=\"0\" y=\"\(fmt(first + pitch * Double(i), 3))\">\(xml(l))</tspan>"
        }
        return s + "</text>\n"
    }

    static func xml(_ s: String) -> String {
        var o = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            case "'": o += "&apos;"
            default:
                if c.value < 0x20 && c.value != 9 && c.value != 10 && c.value != 13 { continue }
                o.unicodeScalars.append(c)
            }
        }
        return o
    }
}
