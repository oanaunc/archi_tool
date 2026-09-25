// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Constraint bar (AutoCAD CONSTRAINTBAR): small icon boxes next to constrained drafting objects, shown in the plan
/// when the CONSTRAINTBAR variable is 1. Geometric constraints get a vector icon, dimensional ones a "name = value" label.
/// Glyphs are decoration (no id), never plotted.
public enum ConstraintGlyphs {
    public static let variable = "CONSTRAINTBAR"
    static let color = RGBA(0.42, 0.66, 1.0)

    public static func isOn(_ doc: ArchiDocument) -> Bool { doc.variable(variable) == "1" }

    enum Role { case point, segment, curve }

    static func role(_ c: GeoConstraint, index i: Int, geometry g: Geometry) -> Role {
        switch c.kind {
        case .horizontal, .vertical:
            return c.refs.count >= 2 ? .point : .segment
        case .parallel, .perpendicular, .collinear, .length, .angle: return .segment
        case .equal:
            if case .circle = g { return .curve }; if case .arc = g { return .curve }; return .segment
        case .concentric, .radius, .diameter: return .curve
        case .tangent:
            switch g { case .line, .polyline: return .segment; default: return .curve }
        case .pointOnCurve: return i == 0 ? .point : .curve
        case .midpoint: return i == 0 ? .point : .segment
        case .symmetric: return i < 2 ? .point : .segment
        default: return .point
        }
    }

    /// Where a glyph for a reference sits, with the direction of the referenced segment (nil for points/curves).
    static func anchor(_ r: CRef, role: Role, geometry g: Geometry) -> (p: Vec2, dir: Vec2?)? {
        switch (g, role) {
        case (.point(let p), _): return (p, nil)
        case (.line(let l), .point): return (r.part == 1 ? l.b : l.a, nil)
        case (.line(let l), _):
            guard l.a.distance(to: l.b) > 1e-12 else { return (l.a, nil) }
            return ((l.a + l.b) / 2, (l.b - l.a).normalized)
        case (.circle(let c), .point): return (c.center, nil)
        case (.circle(let c), _): return (c.center + Vec2.polar(c.radius, Double.pi / 4), nil)
        case (.arc(let a), .point):
            switch r.part { case 1: return (a.startPoint, nil); case 2: return (a.endPoint, nil); default: return (a.center, nil) }
        case (.arc(let a), _): return (a.midPoint, nil)
        case (.polyline(let pl), .point):
            guard r.part >= 0, r.part < pl.vertices.count else { return nil }
            return (pl.vertices[r.part].p, nil)
        case (.polyline(let pl), _):
            let n = pl.vertices.count
            guard n >= 2, r.part >= 0, r.part < (pl.closed ? n : n - 1) else { return pl.vertices.first.map { ($0.p, nil) } }
            let a = pl.vertices[r.part].p, b = pl.vertices[(r.part + 1) % n].p
            return ((a + b) / 2, a.distance(to: b) > 1e-12 ? (b - a).normalized : nil)
        default: return nil
        }
    }

    /// Icon strokes in a unit box centred at the origin (−0.5…0.5), plus filled dots.
    static func icon(_ k: ConstraintKind) -> (lines: [[Vec2]], dots: [Vec2]) {
        func V(_ x: Double, _ y: Double) -> Vec2 { Vec2(x, y) }
        switch k {
        case .horizontal: return ([[V(-0.32, 0), V(0.32, 0)]], [])
        case .vertical: return ([[V(0, -0.32), V(0, 0.32)]], [])
        case .parallel: return ([[V(-0.28, -0.3), V(-0.02, 0.3)], [V(0.02, -0.3), V(0.28, 0.3)]], [])
        case .perpendicular: return ([[V(0, -0.28), V(0, 0.3)], [V(-0.3, -0.28), V(0.3, -0.28)]], [])
        case .collinear: return ([[V(-0.35, -0.2), V(0.35, 0.2)]], [V(-0.18, -0.1), V(0.18, 0.1)])
        case .equal: return ([[V(-0.3, 0.1), V(0.3, 0.1)], [V(-0.3, -0.1), V(0.3, -0.1)]], [])
        case .fixed:
            let shackle = (0...8).map { i -> Vec2 in let a = Double.pi * Double(i) / 8; return V(0.15 * cos(a), 0.02 + 0.2 * sin(a)) }
            return ([[V(-0.24, -0.32), V(0.24, -0.32), V(0.24, 0.02), V(-0.24, 0.02), V(-0.24, -0.32)], shackle], [])
        case .concentric:
            return ([RG.circle(.zero, 0.3, segments: 20) + [V(0.3, 0)], RG.circle(.zero, 0.14, segments: 14) + [V(0.14, 0)]], [])
        case .tangent:
            return ([RG.circle(V(0, -0.1), 0.2, segments: 18) + [V(0.2, -0.1)], [V(-0.35, 0.1), V(0.35, 0.1)]], [])
        case .pointOnCurve:
            let arc = (0...10).map { i -> Vec2 in let a = Double.pi * (0.15 + 0.7 * Double(i) / 10); return V(0.36 * cos(a), -0.28 + 0.36 * sin(a)) }
            return ([arc], [V(0, 0.08)])
        case .midpoint: return ([[V(-0.3, -0.25), V(0.3, -0.25), V(0, 0.28), V(-0.3, -0.25)]], [])
        case .symmetric: return ([[V(-0.12, -0.3), V(-0.3, -0.3), V(-0.3, 0.3), V(-0.12, 0.3)], [V(0.12, -0.3), V(0.3, -0.3), V(0.3, 0.3), V(0.12, 0.3)], [V(0, -0.35), V(0, 0.35)]], [])
        case .coincident: return ([], [V(0, 0)])
        default: return ([], [])
        }
    }

    static func label(_ c: GeoConstraint, set: ConstraintSet, doc: ArchiDocument) -> String {
        let n = c.name ?? c.kind.rawValue
        guard let v = Constraints.displayValue(c, set: set, doc: doc) else { return n }
        let txt = c.kind == .angle ? fmt(v * 180 / .pi, 2) + "°" : fmt(v, 2)
        return (c.reference ? "(" : "") + n + "=" + txt + (c.reference ? ")" : "")
    }

    /// Glyph size in drawing units: CONSTRAINTBARSIZE, or scaled to the constrained geometry.
    static func size(_ doc: ArchiDocument, _ box: BBox2) -> Double {
        if let v = doc.variable("CONSTRAINTBARSIZE").flatMap(Double.init), v > 0 { return v }
        let ds = doc.dimStyle
        let dim = ds.textHeight * max(ds.scale, 1e-9) * 1.8
        let diag = box.isEmpty ? 0 : (box.max - box.min).length
        return max(dim, diag / 70, 1e-6)
    }

    public static func entries(doc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        guard isOn(doc), !options.forPaper, options.showAnnotations else { return [] }
        let set = ConstraintSet.load(doc)
        guard !set.constraints.isEmpty else { return [] }
        var geo: [EntityID: Geometry] = [:]
        var box = BBox2.empty
        let refIDs = Set(set.constraints.flatMap { $0.refs.map(\.entity) })
        for e in doc.entities {
            guard refIDs.contains(e.id) else { continue }
            guard doc.isVisible(layer: e.layer) else { continue }
            if let l = options.level, let el = e.props["level"].flatMap(Int.init), el != l { continue }
            geo[e.id] = e.geometry
            for pl in GeometryOps.tessellate(e.geometry, doc: doc) { for p in pl { box.add(p) } }
        }
        guard !geo.isEmpty else { return [] }
        let s = size(doc, box)
        // Glyphs stacked per anchor location.
        var slots: [String: Int] = [:]
        var items: [DrawItem] = []
        for c in set.constraints {
            for (i, r) in c.refs.enumerated() {
                guard let g = geo[r.entity] else { continue }
                let ro = role(c, index: i, geometry: g)
                guard let a = anchor(r, role: ro, geometry: g) else { continue }
                // Offset: to the left of a segment, or up-right of a point.
                let off = a.dir.map { $0.perp * (s * 0.9) } ?? Vec2(s * 0.75, s * 0.75)
                let key = "\(Int((a.p.x / s).rounded())),\(Int((a.p.y / s).rounded()))"
                let k = slots[key, default: 0]
                slots[key] = k + 1
                let along = a.dir ?? Vec2(1, 0)
                let dimensional = c.kind.isDimensional
                if dimensional && i > 0 { continue }   // one label per dimensional constraint
                let text = dimensional ? label(c, set: set, doc: doc) : ""
                let w = dimensional ? max(s, Double(text.count) * s * 0.42 + s * 0.3) : s
                let center = a.p + off + along * (Double(k) * s * 1.1 + (dimensional ? w / 2 - s / 2 : 0))
                let hw = w / 2, hs = s / 2
                let boxPts = [center + Vec2(-hw, -hs), center + Vec2(hw, -hs), center + Vec2(hw, hs), center + Vec2(-hw, hs)]
                items.append(.fill(loops: [boxPts], color: RGBA(color.r, color.g, color.b, 0.16)))
                items.append(.stroke(points: boxPts, closed: true, style: StrokeStyle(color: color, lineweight: 0)))
                if dimensional {
                    items.append(.text(TextGeom(position: center, height: s * 0.55, content: text, halign: .center, valign: .middle),
                                       font: DrawListBuilder.textFont("Standard", doc: doc).font, color: color))
                    continue
                }
                let ic = icon(c.kind)
                let sc = s * 0.9
                for l in ic.lines where l.count >= 2 {
                    items.append(.stroke(points: l.map { center + $0 * sc }, closed: false, style: StrokeStyle(color: color, lineweight: 0.25)))
                }
                for d in ic.dots { items.append(.fill(loops: [RG.circle(center + d * sc, s * 0.09, segments: 10)], color: color)) }
            }
        }
        return items.isEmpty ? [] : [DrawEntry(id: nil, items: items)]
    }
}
