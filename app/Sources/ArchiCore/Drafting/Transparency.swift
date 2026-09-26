// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Layer and object transparency (LAY-017, LAY-032). Layers keep `Layer.transparency` (fraction 0–0.9; values above 1
/// are read as percent); objects keep prop "transparency" = "ByLayer" (default), "ByBlock" or a percent 0–90.
/// Display applies it as alpha (TRANSPARENCYDISPLAY 0 turns it off); plots apply it unless PLOTTRANSPARENCY is 0.
public enum Transparency {
    public static let prop = "transparency"
    static let guardProp = "\u{1}transparent"
    static let stackKey = "archi.transparencyStack"

    /// Layer transparency as a fraction 0…0.9.
    public static func fraction(layer l: Layer?) -> Double {
        guard let t = l?.transparency, t > 0 else { return 0 }
        return Swift.min(0.9, t > 1 ? t / 100 : t)
    }
    /// Parses a transparency value: "ByLayer", "ByBlock" or 0–90 (percent). Nil for invalid input.
    public static func parse(_ s: String) -> String? {
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.caseInsensitiveCompare("ByLayer") == .orderedSame { return "ByLayer" }
        if v.caseInsensitiveCompare("ByBlock") == .orderedSame { return "ByBlock" }
        guard let d = Double(v), d >= 0, d <= 90 else { return nil }
        return fmt(d)
    }

    /// Effective transparency of an entity as a fraction: explicit value, ByBlock (the enclosing block reference's) or
    /// ByLayer (its layer's).
    public static func fraction(_ e: Entity, doc: ArchiDocument, blockFraction: Double? = nil) -> Double {
        switch e.props[prop] {
        case nil: break
        case let v? where v.caseInsensitiveCompare("ByLayer") == .orderedSame: break
        case let v? where v.caseInsensitiveCompare("ByBlock") == .orderedSame:
            return blockFraction ?? (Thread.current.threadDictionary[stackKey] as? [Double])?.last ?? 0
        case let v?: return Swift.min(0.9, Swift.max(0, (Double(v) ?? 0) / 100))
        }
        return fraction(layer: doc.layer(named: e.layer))
    }

    /// Colours with alpha multiplied by (1 − t).
    public static func apply(_ items: [DrawItem], _ t: Double) -> [DrawItem] {
        guard t > 0 else { return items }
        let k = 1 - t
        func fade(_ c: RGBA) -> RGBA { RGBA(c.r, c.g, c.b, c.a * k) }
        return items.map { it in
            switch it {
            case .stroke(let p, let c, var s): s.color = fade(s.color); return .stroke(points: p, closed: c, style: s)
            case .fill(let l, let c): return .fill(loops: l, color: fade(c))
            case .text(let t, let f, let c): return .text(t, font: f, color: fade(c))
            case .image: return it
            }
        }
    }

    static func shown(_ doc: ArchiDocument, _ o: DrawOptions) -> Bool {
        o.forPaper ? doc.variable("PLOTTRANSPARENCY") != "0" : doc.variable("TRANSPARENCYDISPLAY") != "0"
    }

    /// Draw items of a transparent entity (nil when it is opaque or transparency is not displayed). Block references
    /// pass their own transparency to ByBlock children.
    static func items(_ e: Entity, doc: ArchiDocument, options: DrawOptions, color: RGBA, lineweight: Double) -> [DrawItem]? {
        guard e.props[guardProp] == nil, shown(doc, options) else { return nil }
        let isInsert: Bool
        if case .insert = e.geometry { isInsert = true } else { isInsert = false }
        let t = fraction(e, doc: doc)
        guard t > 0 else { return nil }
        var plain = e
        plain.props[guardProp] = "1"
        plain.color = .rgb(UInt8((color.r * 255).rounded()), UInt8((color.g * 255).rounded()), UInt8((color.b * 255).rounded()))
        plain.lineweight = lineweight
        if isInsert {
            var stack = Thread.current.threadDictionary[stackKey] as? [Double] ?? []
            stack.append(t)
            Thread.current.threadDictionary[stackKey] = stack
            defer { stack.removeLast(); Thread.current.threadDictionary[stackKey] = stack }
            return DrawListBuilder.items(plain, doc: doc, options: options, inherit: DrawListBuilder.Inherit())
        }
        return apply(DrawListBuilder.items(plain, doc: doc, options: options, inherit: DrawListBuilder.Inherit()), t)
    }
}
