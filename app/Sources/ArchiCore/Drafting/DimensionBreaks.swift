// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Associative dimension breaks (DIMBREAK). A dimension entity with prop "dimbreak" keeps gaps in its dimension and extension
/// lines where other objects cross them:
/// - "*" (Auto): every crossing drafting object; "12,15": only those objects; "manual": fixed gaps (never recomputed).
/// - prop "dimbreakSize": gap length in drawing units (default 1.5 × arrow size × DIMSCALE of the dimension's style).
/// Gaps are stored after the definition points of the dimension (see `DimensionRenderer.breaks`) and are recomputed after
/// every edit, so they follow the dimension and the crossing objects.
public enum DimBreaks {
    public static let prop = "dimbreak", sizeProp = "dimbreakSize"

    public static func defaultSize(_ style: DimStyle) -> Double {
        let sc = style.scale > 0 ? style.scale : 1
        return max(style.arrowSize * sc * 1.5, 1e-6)
    }
    public static func size(_ e: Entity, doc: ArchiDocument) -> Double {
        if let s = e.props[sizeProp].flatMap(Double.init), s > 0 { return s }
        guard case .dimension(let d) = e.geometry else { return 1 }
        return defaultSize(doc.dimStyle(d.style))
    }

    /// Geometry kinds that can break a dimension.
    static func breaks(_ g: Geometry) -> Bool {
        switch g {
        case .line, .circle, .arc, .ellipse, .polyline, .spline, .leader, .dimension, .insert: return true
        default: return false
        }
    }

    /// Points where the dimension's own lines (dimension and extension lines, before breaking) cross the given objects.
    public static func crossings(_ d: DimensionGeom, style: DimStyle, with others: [Geometry], doc: ArchiDocument?) -> [Vec2] {
        let base = DimensionRenderer.withoutBreaks(d)
        let lines = DimensionRenderer.primitives(base, style: style).lines
        var box = BBox2.empty
        for l in lines { for p in l { box.add(p) } }
        guard !box.isEmpty else { return [] }
        var pts: [Vec2] = []
        let tol = max(style.arrowSize * (style.scale > 0 ? style.scale : 1) * 0.01, 1e-9)
        for g in others {
            let gb = GeometryOps.bounds(g, doc: doc)
            guard !gb.isEmpty, gb.min.x <= box.max.x + tol, gb.max.x >= box.min.x - tol, gb.min.y <= box.max.y + tol, gb.max.y >= box.min.y - tol else { continue }
            for l in lines where l.count >= 2 {
                for k in 0..<(l.count - 1) where l[k].distance(to: l[k + 1]) > 1e-12 {
                    for p in Intersections.of(.line(LineGeom(l[k], l[k + 1])), g, doc: doc) where !pts.contains(where: { $0.isClose(p, tol: tol) }) {
                        pts.append(p)
                    }
                }
            }
        }
        return pts
    }

    /// Recomputes the breaks of one dimension entity. Returns the new geometry (nil when unchanged or not applicable).
    public static func recompute(_ e: Entity, doc: ArchiDocument) -> Geometry? {
        guard case .dimension(let d) = e.geometry, let mode = e.props[prop], mode.lowercased() != "manual" else { return nil }
        let style = doc.dimStyle(d.style)
        var others: [Geometry] = []
        if mode == "*" || mode.lowercased() == "auto" {
            for o in doc.entities where o.id != e.id && breaks(o.geometry) && doc.isVisible(layer: o.layer) { others.append(o.geometry) }
        } else {
            let ids = Set(mode.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: " #"))) })
            for o in doc.entities where ids.contains(o.id) && o.id != e.id { others.append(o.geometry) }
        }
        // Other dimensions break against their unbroken lines, so two crossing breaking dimensions stay stable.
        others = others.map { if case .dimension(let od) = $0 { return .dimension(DimensionRenderer.withoutBreaks(od)) }; return $0 }
        let r = size(e, doc: doc) / 2
        let gaps = crossings(d, style: style, with: others, doc: doc).map { DimensionRenderer.DimBreak(center: $0, radius: r) }
        let nd = DimensionRenderer.withBreaks(d, gaps, style: style)
        return nd == d ? nil : .dimension(nd)
    }

    /// Keeps every breaking dimension current (DocumentUpdaters). Returns true if the document changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props[prop] != nil {
            if let g = recompute(doc.entities[i], doc: doc) { doc.entities[i].geometry = g; changed = true }
        }
        return changed
    }

    /// Adds a manual gap between two points picked on the dimension (the gap is the circle through both).
    public static func addManual(_ d: DimensionGeom, from a: Vec2, to b: Vec2, style: DimStyle) -> DimensionGeom {
        let gap = DimensionRenderer.DimBreak(center: (a + b) / 2, radius: max(a.distance(to: b) / 2, 1e-9))
        return DimensionRenderer.withBreaks(d, DimensionRenderer.breaks(d) + [gap], style: style)
    }

    /// Removes all breaks from a dimension entity.
    public static func remove(_ e: inout Entity) {
        e.props[prop] = nil; e.props[sizeProp] = nil
        if case .dimension(let d) = e.geometry { e.geometry = .dimension(DimensionRenderer.withoutGaps(d)) }
    }
}
