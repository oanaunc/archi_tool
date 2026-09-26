// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Annotative text styles (ANN-017): text created in a style marked annotative gets its height as a paper height
/// (the style height when it is fixed, otherwise the height typed), and its model height follows the annotation scale
/// (CANNOSCALE) from then on. The flag is stored as TEXTSTYLEANNO:<style> = 1.
public enum AnnotativeText {
    public static func key(_ style: String) -> String { "TEXTSTYLEANNO:" + style.uppercased() }
    public static func isAnnotative(style: String, _ doc: ArchiDocument) -> Bool { doc.variable(key(style)) == "1" }
    public static func set(style: String, _ on: Bool, _ doc: inout ArchiDocument) {
        if on { doc.setVariable(key(style), "1") } else { doc.variables[key(style)] = nil }
    }
    public static func anyStyle(_ doc: ArchiDocument) -> Bool { doc.variables.keys.contains { $0.hasPrefix("TEXTSTYLEANNO:") } }

    /// Makes new text objects (ids not in `old`) in annotative styles annotative. Returns how many changed.
    @discardableResult
    public static func applyToNew(_ doc: inout ArchiDocument, old: Set<EntityID>) -> Int {
        guard anyStyle(doc) else { return 0 }
        var n = 0
        let mm = doc.units.mm
        for i in doc.entities.indices where !old.contains(doc.entities[i].id) && doc.entities[i].props["annotative"] == nil {
            guard case .text(let t) = doc.entities[i].geometry, isAnnotative(style: t.style, doc) else { continue }
            let st = doc.textStyles.first { $0.name.caseInsensitiveCompare(t.style) == .orderedSame }
            // Paper height in paper mm: the style's fixed height, else the typed height read as paper units.
            let paper = (st?.height ?? 0) > 0 ? st!.height : t.height
            doc.entities[i].props["annotative"] = "1"
            doc.entities[i].props["paperHeight"] = fmt(paper * mm, 8)
            n += 1
        }
        if n > 0 { Annotative.updateAll(&doc) }
        return n
    }
}
