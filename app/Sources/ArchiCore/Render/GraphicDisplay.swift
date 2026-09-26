// Oanarina Archi Tool — GPL-3.0-or-later
// Graphic display options of a view (DOC-029): sketchy lines (overshooting, slightly wavering strokes), silhouettes
// (heavier outlines) and cast shadows in plan. Stored as view variables (SKETCHY, SILHOUETTES, VIEWSHADOWS), so each
// project view and view template keeps its own.
import Foundation

public enum GraphicDisplay {
    public static let sketchyKey = "SKETCHY", silhouetteKey = "SILHOUETTES", shadowKey = "VIEWSHADOWS"

    public struct Options: Equatable {
        /// Sketchy strength 0…10 (0 = off).
        public var sketchy: Double
        /// Silhouette line weight in mm (0 = off).
        public var silhouette: Double
        public var shadows: Bool
        public var isOff: Bool { sketchy <= 0 && silhouette <= 0 && !shadows }
    }

    public static func options(_ doc: ArchiDocument) -> Options {
        Options(sketchy: min(10, max(0, doc.variable(sketchyKey).flatMap(Double.init) ?? 0)),
                silhouette: max(0, doc.variable(silhouetteKey).flatMap(Double.init) ?? 0),
                shadows: doc.variable(shadowKey) == "1")
    }

    /// Deterministic pseudo-random value in [0, 1) from a point (stable between redraws).
    static func hash(_ p: Vec2, _ salt: Int) -> Double {
        var h = UInt64(bitPattern: Int64((p.x * 7.13).rounded())) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64((p.y * 3.71).rounded())) &* 0xC2B2AE3D27D4EB4F
        h ^= UInt64(salt) &* 0x165667B19E3779F9
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        return Double(h % 1_000_000) / 1_000_000
    }

    /// Sketchy version of a stroke: every segment overshoots its ends and wavers slightly.
    static func sketch(_ pts: [Vec2], closed: Bool, style: StrokeStyle, strength s: Double, unit u: Double) -> [DrawItem] {
        let path = closed && pts.count > 2 ? pts + [pts[0]] : pts
        guard path.count >= 2 else { return [] }
        let ext = s * 12 * u, wob = s * 2.5 * u
        var out: [DrawItem] = []
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let len = a.distance(to: b)
            guard len > 1e-9 else { continue }
            let d = (b - a) / len, n = d.perp
            let e = min(ext, len * 0.3)
            let a2 = a - d * (e * (0.4 + hash(a, 1))) + n * (wob * (hash(a, 2) - 0.5))
            let b2 = b + d * (e * (0.4 + hash(b, 3))) + n * (wob * (hash(b, 4) - 0.5))
            let m = a.lerp(b, 0.5) + n * (wob * (hash(a + b, 5) - 0.5))
            out.append(.stroke(points: [a2, m, b2], closed: false, style: style))
        }
        return out
    }

    /// Applies sketchy lines and silhouettes to draw entries (fills and text are unchanged).
    public static func apply(_ entries: [DrawEntry], doc: ArchiDocument) -> [DrawEntry] {
        let o = options(doc)
        guard o.sketchy > 0 || o.silhouette > 0 else { return entries }
        let u = 1 / doc.units.mm
        return entries.map { e in
            var items: [DrawItem] = []
            for it in e.items {
                guard case .stroke(let pts, let closed, var style) = it else { items.append(it); continue }
                // Silhouettes: closed outlines and cut / heavy lines get the silhouette weight.
                if o.silhouette > 0 && (closed || style.lineweight >= 0.35) { style.lineweight = max(style.lineweight, o.silhouette) }
                if o.sketchy > 0 && style.dash.isEmpty { items += sketch(pts, closed: closed, style: style, strength: o.sketchy, unit: u) }
                else { items.append(.stroke(points: pts, closed: closed, style: style)) }
            }
            return DrawEntry(id: e.id, items: items)
        }
    }

    /// Plan shadow direction and length per unit height (light from the upper left at SHADOWALTITUDE degrees, default 50).
    static func shadowOffset(_ doc: ArchiDocument) -> Vec2 {
        let alt = rad(min(85, max(10, doc.variable("SHADOWALTITUDE").flatMap(Double.init) ?? 50)))
        let az = rad(doc.variable("SHADOWAZIMUTH").flatMap(Double.init) ?? 135)   // direction the light comes from
        return Vec2.polar(1 / tan(alt), az + .pi)
    }

    /// Cast shadows of the elements drawn in a plan: the footprint swept along the shadow direction by its height.
    public static func shadowEntries(_ doc: ArchiDocument, level: Int) -> [DrawEntry] {
        guard options(doc).shadows else { return [] }
        let off = shadowOffset(doc)
        let elev = doc.level(level)?.elevation ?? 0
        var loops: [[Vec2]] = []
        for el in doc.elements where el.level == level && doc.isVisible(layer: el.layer) {
            switch el.geometry { case .space, .gridLine, .opening, .slab: continue; default: break }
            var fp = CommandHelpers.footprint(el, doc: doc)
            guard fp.count >= 3, abs(GeometryOps.signedArea(fp)) > 1e-9 else { continue }
            var top = -Double.infinity
            for g in MeshBuilder.groups(for: el, doc: doc) { let b = g.mesh.bounds; if !b.isEmpty { top = max(top, b.max.z) } }
            guard top.isFinite, top - elev > 1e-6 else { continue }
            if GeometryOps.signedArea(fp) < 0 { fp.reverse() }
            let d = off * (top - elev)
            var parts: [[Vec2]] = [fp.map { $0 + d }]
            for i in 0..<fp.count {
                let a = fp[i], b = fp[(i + 1) % fp.count]
                var q = [a, b, b + d, a + d]
                if GeometryOps.signedArea(q) < 0 { q.reverse() }
                if abs(GeometryOps.signedArea(q)) > 1e-9 { parts.append(q) }
            }
            var region: [[Vec2]] = [fp]
            for p in parts { region = PolygonBoolean.apply(.union, region, [p]) }
            // The element itself covers its own footprint.
            region = PolygonBoolean.apply(.subtract, region, [fp])
            loops += region
        }
        guard !loops.isEmpty else { return [] }
        return [DrawEntry(id: nil, items: [.fill(loops: loops, color: RGBA(0, 0, 0, 0.18))])]
    }
}
