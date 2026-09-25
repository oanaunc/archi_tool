// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Colour fill schemes for rooms and areas (Revit colour schemes): rooms are filled by the value of a parameter
/// (name, number, department, occupancy, area scheme, any property) or by area range, with a legend.
/// COLORFILL = parameter ("" = off), COLORFILLBIN = area range width in m² (area schemes), COLORFILLMAP = "value=#RRGGBB|…" overrides.
public enum AreaColors {
    public static let variable = "COLORFILL"
    public static let palette: [RGBA] = [
        RGBA(0.95, 0.55, 0.45), RGBA(0.50, 0.75, 0.95), RGBA(0.60, 0.85, 0.50), RGBA(0.98, 0.80, 0.35), RGBA(0.75, 0.60, 0.90),
        RGBA(0.45, 0.85, 0.80), RGBA(0.95, 0.65, 0.80), RGBA(0.70, 0.70, 0.50), RGBA(0.55, 0.60, 0.85), RGBA(0.90, 0.70, 0.55),
        RGBA(0.65, 0.90, 0.70), RGBA(0.85, 0.50, 0.60),
    ]

    public static func scheme(_ doc: ArchiDocument) -> String? {
        guard let v = doc.variable(variable)?.trimmingCharacters(in: .whitespaces), !v.isEmpty, v.lowercased() != "off", v != "0" else { return nil }
        return v
    }

    /// Value of the scheme parameter for a room (nil = not coloured).
    public static func value(_ el: BIMElement, scheme s: String, doc: ArchiDocument) -> String? {
        guard case .space(let g) = el.geometry else { return nil }
        switch s.lowercased() {
        case "name": return g.name.isEmpty ? el.name : g.name
        case "number": return g.number.isEmpty ? nil : g.number
        case "area":
            let m2 = abs(GeometryOps.signedArea(g.boundary)) * doc.units.mm * doc.units.mm / 1e6
            let bin = doc.variable("COLORFILLBIN").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? 10
            let lo = (m2 / bin).rounded(.down) * bin
            return "\(fmt(lo, 1))–\(fmt(lo + bin, 1)) m²"
        case "level": return doc.level(el.level)?.name
        default:
            let key = el.props.keys.first { $0.caseInsensitiveCompare(s) == .orderedSame }
            return key.flatMap { el.props[$0] }.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    static func parseHex(_ s: String) -> RGBA? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
        return RGBA(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    static func overrides(_ doc: ArchiDocument) -> [String: RGBA] {
        var out: [String: RGBA] = [:]
        for part in (doc.variable("COLORFILLMAP") ?? "").split(separator: "|") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, let c = parseHex(kv[1]) { out[kv[0].lowercased()] = c }
        }
        return out
    }

    /// Legend entries (value, colour, room count, total area in drawing units²) in sorted order.
    public static func legend(_ doc: ArchiDocument, level: Int? = nil) -> [(value: String, color: RGBA, count: Int, area: Double)] {
        guard let s = scheme(doc) else { return [] }
        var stats: [String: (Int, Double)] = [:]
        for el in doc.elements {
            if let l = level, el.level != l { continue }
            guard case .space(let g) = el.geometry, let v = value(el, scheme: s, doc: doc) else { continue }
            let a = abs(GeometryOps.signedArea(g.boundary))
            stats[v, default: (0, 0)].0 += 1; stats[v, default: (0, 0)].1 += a
        }
        let keys = stats.keys.sorted { a, b in
            if s.lowercased() == "area", let x = Double(a.split(separator: "–").first ?? ""), let y = Double(b.split(separator: "–").first ?? "") { return x < y }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        let ov = overrides(doc)
        // Colours follow the sorted order over the whole model so they stay stable between levels.
        let allKeys: [String] = {
            var all = Set<String>()
            for el in doc.elements { if let v = value(el, scheme: s, doc: doc) { all.insert(v) } }
            return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }()
        return keys.map { k in
            let idx = allKeys.firstIndex(of: k) ?? 0
            return (k, ov[k.lowercased()] ?? palette[idx % palette.count], stats[k]!.0, stats[k]!.1)
        }
    }

    /// Fill colour of a room under the active scheme.
    public static func color(_ el: BIMElement, doc: ArchiDocument) -> RGBA? {
        guard let s = scheme(doc), let v = value(el, scheme: s, doc: doc) else { return nil }
        if let o = overrides(doc)[v.lowercased()] { return o }
        var all = Set<String>()
        for e in doc.elements { if let x = value(e, scheme: s, doc: doc) { all.insert(x) } }
        let keys = all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return palette[(keys.firstIndex(of: v) ?? 0) % palette.count]
    }

    /// Legend geometry (paper-independent, in drawing units): title, swatches and labels from `origin` downwards.
    public static func legendGeometry(_ doc: ArchiDocument, at origin: Vec2, level: Int?, textHeight th: Double) -> [(Geometry, ColorRef?)] {
        guard let s = scheme(doc) else { return [] }
        var out: [(Geometry, ColorRef?)] = [(.text(TextGeom(position: origin, height: th * 1.3, content: "COLOUR SCHEME: " + s.uppercased(), valign: .bottom)), nil)]
        var y = origin.y - th * 1.2
        for e in legend(doc, level: level) {
            let box = [Vec2(origin.x, y - th * 1.2), Vec2(origin.x + th * 2, y - th * 1.2), Vec2(origin.x + th * 2, y), Vec2(origin.x, y)]
            let c = ColorRef.rgb(UInt8(max(0, min(255, (e.color.r * 255).rounded()))), UInt8(max(0, min(255, (e.color.g * 255).rounded()))), UInt8(max(0, min(255, (e.color.b * 255).rounded()))))
            out.append((.hatch(HatchGeom(loops: [box.map { PolyVertex($0) }], pattern: "SOLID")), c))
            out.append((.polyline(PolylineGeom(points: box, closed: true)), nil))
            let area = PlanRepresentation.formatArea(e.area, doc)
            out.append((.text(TextGeom(position: Vec2(origin.x + th * 2.6, y - th * 0.6), height: th, content: "\(e.value)  (\(e.count), \(area))", valign: .middle)), nil))
            y -= th * 1.8
        }
        return out
    }
}
