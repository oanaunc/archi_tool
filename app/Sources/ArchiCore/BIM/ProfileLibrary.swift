// Oanarina Archi Tool — GPL-3.0-or-later
// Profile families (PAR-013): named 2D profiles for sweeps, mullions, railings, gutters, fascias and sills, flexing to a
// width × height. Built-in profiles plus profiles defined in document families (category "Profile").
import Foundation

public enum ProfileLibrary {
    /// Built-in profile names with their use.
    public static let builtins: [(name: String, use: String)] = [
        ("rect", "generic"), ("round", "handrail / baluster"), ("oval", "handrail"), ("mushroom", "handrail"), ("handrail-rect", "handrail"),
        ("cornice", "wall sweep"), ("crown", "wall sweep"), ("skirting", "wall sweep"), ("cove", "wall sweep"), ("chair-rail", "wall sweep"),
        ("reveal", "wall reveal"), ("drip", "sill / string course"), ("sill", "window sill"),
        ("angle", "steel L"), ("tee", "steel T / mullion"), ("i-beam", "steel I"), ("channel", "steel C"), ("fin", "mullion"),
        ("gutter-half-round", "gutter"), ("gutter-ogee", "gutter"), ("gutter-box", "gutter"), ("fascia", "fascia board"), ("slab-edge", "slab edge"),
    ]

    public static func isBuiltin(_ n: String) -> Bool { builtins.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame } }

    static func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int = 12) -> [Vec2] {
        (0...n).map { k in let a = a0 + (a1 - a0) * Double(k) / Double(n); return Vec2(cx + rx * cos(a), cy + ry * sin(a)) }
    }

    /// Built-in profile scaled to w × h: x from 0 (attachment face / left) to w, y from 0 (bottom) to h. CCW, closed.
    public static func builtin(_ name: String, width w0: Double, height h0: Double) -> [Vec2]? {
        let w = max(w0, 1e-6), h = max(h0, 1e-6)
        var p: [Vec2]
        switch name.lowercased() {
        case "rect", "handrail-rect", "reveal", "fascia", "slab-edge":
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)]
        case "round":
            p = arc(w / 2, h / 2, w / 2, h / 2, 0, 2 * .pi, 24); p.removeLast()
        case "oval":
            p = arc(w / 2, h / 2, w / 2, h / 2 * 0.75, 0, 2 * .pi, 24).map { Vec2($0.x, $0.y + h * 0.125) }; p.removeLast()
        case "mushroom":
            p = [Vec2(w * 0.3, 0), Vec2(w * 0.7, 0), Vec2(w * 0.7, h * 0.45), Vec2(w, h * 0.55)] + Array(arc(w / 2, h * 0.55, w / 2, h * 0.45, 0, .pi, 14).dropFirst().dropLast()) + [Vec2(0, h * 0.55), Vec2(w * 0.3, h * 0.45)]
        case "cornice":
            p = [Vec2(0, 0), Vec2(w * 0.3, 0), Vec2(w * 0.3, h * 0.35), Vec2(w * 0.75, h * 0.55), Vec2(w, h * 0.8), Vec2(w, h), Vec2(0, h)]
        case "crown":
            p = [Vec2(0, 0), Vec2(w * 0.15, 0)] + (1..<10).map { k -> Vec2 in let t = Double(k) / 10; return Vec2(w * 0.15 + w * 0.85 * sin(t * .pi / 2), h * (1 - cos(t * .pi / 2))) } + [Vec2(w, h), Vec2(0, h)]
        case "skirting", "baseboard":
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h * 0.8), Vec2(w * 0.5, h), Vec2(0, h)]
        case "cove":
            p = [Vec2(0, 0), Vec2(w, 0)] + (1..<8).map { k -> Vec2 in let a = Double.pi / 2 * Double(k) / 8; return Vec2(w - w * sin(a), h - h * cos(a)) } + [Vec2(0, h)]
        case "chair-rail":
            p = [Vec2(0, 0), Vec2(w * 0.6, 0), Vec2(w, h * 0.3), Vec2(w, h * 0.7), Vec2(w * 0.6, h), Vec2(0, h)]
        case "drip", "sill":
            p = [Vec2(0, h * 0.3), Vec2(w * 0.9, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)]
            if name.lowercased() == "drip" { p = [Vec2(0, 0), Vec2(w * 0.85, 0), Vec2(w * 0.85, h * 0.25), Vec2(w, h * 0.25), Vec2(w, h), Vec2(0, h)] }
        case "angle":
            let t = min(w, h) * 0.12
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, t), Vec2(t, t), Vec2(t, h), Vec2(0, h)]
        case "tee":
            let t = min(w, h) * 0.12
            p = [Vec2(w / 2 - t / 2, 0), Vec2(w / 2 + t / 2, 0), Vec2(w / 2 + t / 2, h - t), Vec2(w, h - t), Vec2(w, h), Vec2(0, h), Vec2(0, h - t), Vec2(w / 2 - t / 2, h - t)]
        case "i-beam":
            let tf = h * 0.08, tw = w * 0.1
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, tf), Vec2(w / 2 + tw / 2, tf), Vec2(w / 2 + tw / 2, h - tf), Vec2(w, h - tf), Vec2(w, h),
                 Vec2(0, h), Vec2(0, h - tf), Vec2(w / 2 - tw / 2, h - tf), Vec2(w / 2 - tw / 2, tf), Vec2(0, tf)]
        case "channel":
            let tf = h * 0.1, tw = w * 0.15
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, tf), Vec2(tw, tf), Vec2(tw, h - tf), Vec2(w, h - tf), Vec2(w, h), Vec2(0, h)]
        case "fin":
            p = [Vec2(0, 0), Vec2(w, h * 0.45), Vec2(w, h * 0.55), Vec2(0, h)]
        case "gutter-half-round":
            let t = min(w, h) * 0.06
            let outer = arc(w / 2, h, w / 2, h, .pi, 2 * .pi, 16)
            let inner = arc(w / 2, h, w / 2 - t, h - t, 2 * .pi, .pi, 16)
            p = outer + inner
        case "gutter-ogee":
            let t = min(w, h) * 0.06
            let front = (0...10).map { k -> Vec2 in let s = Double(k) / 10; return Vec2(w * (0.55 + 0.45 * s), h * (0.5 - 0.5 * cos(s * .pi))) }
            let inner: [Vec2] = front.reversed().dropFirst().dropLast().map { Vec2($0.x - t, max($0.y, t)) }
            var q: [Vec2] = [Vec2(0, h), Vec2(0, 0)]
            q.append(contentsOf: front.dropFirst())
            q.append(Vec2(w - t, h))
            q.append(contentsOf: inner)
            q.append(contentsOf: [Vec2(t, t), Vec2(t, h)])
            p = q
        case "gutter-box":
            let t = min(w, h) * 0.06
            p = [Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(w - t, h), Vec2(w - t, t), Vec2(t, t), Vec2(t, h), Vec2(0, h)]
        default: return nil
        }
        p = RG.dedupe(p, closed: true)
        if GeometryOps.signedArea(p) < 0 { p.reverse() }
        return p.count >= 3 ? p : nil
    }

    /// A profile by name: a document profile family (category "Profile", parameters Width/Height bound to w/h), a profile
    /// defined inside any family, or a built-in.
    public static func outline(_ name: String, width w: Double, height h: Double, doc: ArchiDocument?) -> [Vec2]? {
        if let d = doc {
            if let fam = d.family(named: name), let prof = fam.profiles.first {
                let r = FamilyExpr.resolve(fam, overrides: ["width": fmt(w, 6), "height": fmt(h, 6)])
                return FamilyEngine.profilePoints(prof, values: r.values)
            }
            for fam in d.families {
                if let prof = fam.profile(name) {
                    let r = FamilyExpr.resolve(fam, overrides: ["width": fmt(w, 6), "height": fmt(h, 6)])
                    return FamilyEngine.profilePoints(prof, values: r.values)
                }
            }
        }
        return builtin(name, width: w, height: h)
    }

    /// All profile names available in a document (families first, then built-ins).
    public static func names(_ doc: ArchiDocument) -> [String] {
        var out: [String] = []
        for f in doc.families where f.category.caseInsensitiveCompare("Profile") == .orderedSame { out.append(f.name) }
        for f in doc.families { for p in f.profiles where !out.contains(p.name) { out.append(p.name) } }
        return out + builtins.map(\.name)
    }
}
