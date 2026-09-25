// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Reflected ceiling plans (RCP): ceilings with grids and heights, ceiling/wall-mounted lighting and electrical fixtures.
public enum ReflectedCeiling {
    /// Elements drawn in a reflected ceiling plan.
    static func shows(_ el: BIMElement) -> Bool {
        switch el.geometry {
        case .slab: return el.props["kind"] == "ceiling"
        case .component(let c):
            if c.path != nil { return false }
            let cat = c.category.lowercased()
            return cat == "lighting" || ((cat == "electrical" || cat == "mechanical") && c.baseOffset >= 1800)
        case .railing: return false
        default: return true
        }
    }

    /// Grid module (x, y) of a ceiling from props["ceilingGrid"] ("600x600", "600x1200", "none"); default 600 × 600 mm.
    public static func grid(_ el: BIMElement, unit u: Double) -> (Double, Double)? {
        let s = (el.props["ceilingGrid"] ?? "600x600").lowercased().replacingOccurrences(of: " ", with: "")
        if s == "none" || s == "0" || s == "plaster" { return nil }
        let p = s.split(separator: "x").compactMap { Double($0) }
        guard let a = p.first, a > 0 else { return nil }
        let b = p.count > 1 && p[1] > 0 ? p[1] : a
        return (a * u, b * u)
    }

    /// Grid lines of a ceiling clipped to its boundary (holes respected); the grid is centred on the ceiling.
    public static func gridLines(_ el: BIMElement, _ g: SlabGeom, unit u: Double) -> [[Vec2]] {
        guard let (gx, gy) = grid(el, unit: u), g.boundary.count >= 3 else { return [] }
        let ang = (el.props["gridAngle"].flatMap(Double.init) ?? 0) * .pi / 180
        let d = Vec2.polar(1, ang), n = d.perp
        let loops = [g.boundary] + g.holes
        let c = LabelPlacement.pole(of: g.boundary).point
        let ss = g.boundary.map { ($0 - c).dot(d) }, ts = g.boundary.map { ($0 - c).dot(n) }
        guard let s0 = ss.min(), let s1 = ss.max(), let t0 = ts.min(), let t1 = ts.max() else { return [] }
        var out: [[Vec2]] = []
        guard (s1 - s0) / gx < 2000, (t1 - t0) / gy < 2000 else { return [] }
        // Lines half a module off the centre so tiles are symmetric about the ceiling centre.
        var s = (s0 / gx).rounded(.down) * gx + gx / 2
        while s < s1 { for seg in RG.clipSegment(c + d * s + n * (t0 - 1), c + d * s + n * (t1 + 1), loops) { out.append([seg.0, seg.1]) }; s += gx }
        var t = (t0 / gy).rounded(.down) * gy + gy / 2
        while t < t1 { for seg in RG.clipSegment(c + n * t + d * (s0 - 1), c + n * t + d * (s1 + 1), loops) { out.append([seg.0, seg.1]) }; t += gy }
        return out
    }

    static func ceilingItems(_ el: BIMElement, _ g: SlabGeom, doc: ArchiDocument, color: RGBA, options: DrawOptions) -> [DrawItem] {
        let u = PlanRepresentation.unit(doc)
        var out: [DrawItem] = ([g.boundary] + g.holes).filter { $0.count >= 3 }.map { PlanRepresentation.stroke($0, closed: true, color, PlanRepresentation.lwProj) }
        for l in gridLines(el, g, unit: u) { out.append(PlanRepresentation.stroke(l, color, PlanRepresentation.lwFine)) }
        if options.showAnnotations, g.boundary.count >= 3 {
            let h = g.topOffset - g.thickness
            let pole = LabelPlacement.pole(of: g.boundary)
            let th = min(180 * u, max(pole.radius * 0.3, 60 * u))
            let label = "CLG " + SpotElevation.text(h, units: doc.units)
            let box = [pole.point + Vec2(-th * 3.2, -th * 0.9), pole.point + Vec2(th * 3.2, -th * 0.9), pole.point + Vec2(th * 3.2, th * 0.9), pole.point + Vec2(-th * 3.2, th * 0.9)]
            out.append(.fill(loops: [box], color: RGBA(0, 0, 0, 0.0001)))
            out.append(PlanRepresentation.stroke(box, closed: true, color, PlanRepresentation.lwAnno))
            out.append(.text(TextGeom(position: pole.point, height: th, content: label, halign: .center, valign: .middle), font: PlanRepresentation.font(doc), color: color))
        }
        return out
    }
}

/// Live annotation on drafting entities: property line bearings/distances/area, spot elevation values.
enum SiteAnnotations {
    /// Spot elevation leaders (props spotElevation = 1) show the current elevation under their first point.
    static func live(_ e: Entity, doc: ArchiDocument) -> Entity {
        if e.props["spotSlope"] == "1", case .leader(var l) = e.geometry, l.points.count >= 2 {
            let mid = (l.points[0] + l.points[1]) / 2
            let lvl = e.props["level"].flatMap(Int.init)
            l.text = SpotElevation.slope(at: mid, doc: doc, level: lvl).map { SpotElevation.slopeText($0.grade) } ?? "0%"
            var c = e; c.geometry = .leader(l); return c
        }
        guard e.props["spotElevation"] == "1", case .leader(var l) = e.geometry, let p = l.points.first else { return e }
        let lvl = e.props["level"].flatMap(Int.init)
        let prefix = e.props["spotPrefix"] ?? ""
        l.text = prefix + SpotElevation.text(SpotElevation.value(at: p, doc: doc, level: lvl), units: doc.units)
        var c = e; c.geometry = .leader(l); return c
    }
    static func extraItems(_ e: Entity, doc: ArchiDocument, options: DrawOptions) -> [DrawItem] {
        guard options.showAnnotations else { return [] }
        let u = 1 / doc.units.mm
        if e.props["propertyLine"] == "1", case .polyline(let pl) = e.geometry {
            let th = doc.variable("PROPERTYTEXT").flatMap(Double.init) ?? 250 * u
            let col = doc.resolvedColor(e)
            return Bearings.labels(pl.vertices.map(\.p), closed: pl.closed, doc: doc, height: th).map {
                .text($0, font: DrawListBuilder.textFont("Standard", doc: doc).font, color: col)
            }
        }
        return []
    }
}
