// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Vector SVG of a sheet (SHT-036): viewports mapped to paper millimetres and clipped to their frames, paper-space
/// annotation, title block and decorations, one SVG layer per drawing layer, true size at 96 px per inch.
enum SheetSVG {
    static let pxPerMM = 96.0 / 25.4

    /// Paper entries of a sheet (mm): what the plotted PDF shows.
    @MainActor static func entries(doc: ArchiDocument, layoutIndex li: Int) -> [DrawEntry] {
        guard doc.layouts.indices.contains(li) else { return [] }
        let layout = doc.layouts[li]
        var out: [DrawEntry] = []
        for (i, vp) in layout.viewports.enumerated() {
            let src = ViewportLayers.frozen(doc, layout: layout.name, viewport: i).isEmpty ? doc : ViewportLayers.document(for: doc, layout: layout.name, viewport: i)
            let clip = BBox2(points: SheetTools.clip(doc, layout: layout.name, viewport: i) ?? [vp.origin, vp.origin + vp.size])
            let s = 1 / max(vp.scale, 1e-12)
            func map(_ p: Vec2) -> Vec2 { SheetTools.paperPoint(p, in: vp) }
            for e in SheetComposer.viewportEntries(doc: src, vp: vp) {
                var items: [DrawItem] = []
                for it in e.items {
                    switch it {
                    case .stroke(let pts, let closed, var st):
                        st.dash = st.dash.map { $0 * s }
                        st.color = ink(st.color)
                        for run in clipPolyline((closed && pts.count > 2 ? pts + [pts[0]] : pts).map(map), clip) where run.count >= 2 {
                            items.append(.stroke(points: run, closed: false, style: st))
                        }
                    case .fill(let loops, let c):
                        let cl = loops.map { clipPolygon($0.map(map), clip) }.filter { $0.count >= 3 }
                        if !cl.isEmpty { items.append(.fill(loops: cl, color: ink(c))) }
                    case .text(var t, let font, let c):
                        t.position = map(t.position); t.height *= s; t.width *= s
                        if clip.contains(t.position) { items.append(.text(t, font: font, color: ink(c))) }
                    case .image(var im):
                        im.origin = map(im.origin); im.size = im.size * s
                        if clip.intersects(BBox2(points: [im.origin, im.origin + im.size])) { items.append(.image(im)) }
                    }
                }
                if !items.isEmpty { out.append(DrawEntry(id: e.id, items: items)) }
            }
        }
        out += SheetComposer.paperEntities(doc: doc, layout: layout)
        out += SheetComposer.decorations(doc: doc, layout: layout, layoutIndex: li)
        return out
    }

    /// Screen-white plots black on paper (as in the PDF plot).
    static func ink(_ c: RGBA) -> RGBA { (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.85 ? RGBA(0, 0, 0, c.a) : c }

    @MainActor static func svg(doc: ArchiDocument, layoutIndex li: Int) -> String? {
        guard doc.layouts.indices.contains(li) else { return nil }
        let p = doc.layouts[li].paper
        return SVGExporter.exportLayered(doc: doc, entries: entries(doc: doc, layoutIndex: li), bounds: BBox2(min: .zero, max: Vec2(p.width, p.height)),
                                         background: RGBA(1, 1, 1), pixelsPerUnit: pxPerMM)
    }

    // MARK: Clipping

    /// Liang–Barsky clipping of a polyline to a box; returns the visible runs.
    static func clipPolyline(_ pts: [Vec2], _ b: BBox2) -> [[Vec2]] {
        var runs: [[Vec2]] = [], cur: [Vec2] = []
        guard pts.count >= 2 else { return [] }
        for i in 0..<(pts.count - 1) {
            guard let (a, c) = clipSegment(pts[i], pts[i + 1], b) else { if cur.count >= 2 { runs.append(cur) }; cur = []; continue }
            if let last = cur.last, last.isClose(a, tol: 1e-9) { cur.append(c) } else { if cur.count >= 2 { runs.append(cur) }; cur = [a, c] }
            if !c.isClose(pts[i + 1], tol: 1e-9) { runs.append(cur); cur = [] }
        }
        if cur.count >= 2 { runs.append(cur) }
        return runs
    }
    static func clipSegment(_ p: Vec2, _ q: Vec2, _ b: BBox2) -> (Vec2, Vec2)? {
        var t0 = 0.0, t1 = 1.0
        let d = q - p
        for (pp, qq) in [(-d.x, p.x - b.min.x), (d.x, b.max.x - p.x), (-d.y, p.y - b.min.y), (d.y, b.max.y - p.y)] {
            if abs(pp) < 1e-15 { if qq < 0 { return nil }; continue }
            let r = qq / pp
            if pp < 0 { if r > t1 { return nil }; t0 = max(t0, r) } else { if r < t0 { return nil }; t1 = min(t1, r) }
        }
        return (p + d * t0, p + d * t1)
    }
    /// Sutherland–Hodgman clipping of a polygon to a box.
    static func clipPolygon(_ poly: [Vec2], _ b: BBox2) -> [Vec2] {
        var out = poly
        let edges: [(Vec2) -> Bool] = [{ $0.x >= b.min.x }, { $0.x <= b.max.x }, { $0.y >= b.min.y }, { $0.y <= b.max.y }]
        let cuts: [(Vec2, Vec2) -> Vec2] = [
            { a, c in a + (c - a) * ((b.min.x - a.x) / (c.x - a.x)) }, { a, c in a + (c - a) * ((b.max.x - a.x) / (c.x - a.x)) },
            { a, c in a + (c - a) * ((b.min.y - a.y) / (c.y - a.y)) }, { a, c in a + (c - a) * ((b.max.y - a.y) / (c.y - a.y)) },
        ]
        for k in 0..<4 {
            let input = out; out = []
            guard !input.isEmpty else { break }
            for i in input.indices {
                let cur = input[i], prev = input[(i + input.count - 1) % input.count]
                let ci = edges[k](cur), pi = edges[k](prev)
                if ci { if !pi { out.append(cuts[k](prev, cur)) }; out.append(cur) } else if pi { out.append(cuts[k](prev, cur)) }
            }
        }
        return out
    }
}
