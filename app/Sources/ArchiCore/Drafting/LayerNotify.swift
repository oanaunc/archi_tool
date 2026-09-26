// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// New-layer notification (LAYERNOTIFY / LAYEREVAL, LAY-020): layers that appear after the drawing's layer list was last
/// reconciled (added by insert, xref, paste, import or a script) are "unreconciled" until the user accepts them.
/// The reconciled list is saved in the drawing (LAYRECONCILED, names separated by U+001F).
public enum LayerNotify {
    public static let enabledVar = "LAYERNOTIFY"
    public static let listVar = "LAYRECONCILED"
    static let sep = "\u{1F}"

    public static func isOn(_ doc: ArchiDocument) -> Bool { (doc.variable(enabledVar).flatMap(Int.init) ?? 0) != 0 }
    public static func reconciled(_ doc: ArchiDocument) -> Set<String>? {
        doc.variable(listVar).map { Set($0.components(separatedBy: sep).filter { !$0.isEmpty }.map { $0.lowercased() }) }
    }
    /// Layers not yet reconciled (empty until a baseline exists).
    public static func unreconciled(_ doc: ArchiDocument) -> [String] {
        guard let r = reconciled(doc) else { return [] }
        return doc.layers.map(\.name).filter { !r.contains($0.lowercased()) }
    }
    /// Marks layers as reconciled (all when `names` is nil) and makes sure a baseline exists.
    public static func reconcile(_ names: [String]? = nil, _ doc: inout ArchiDocument) {
        var r = reconciled(doc) ?? []
        for n in names ?? doc.layers.map(\.name) { r.insert(n.lowercased()) }
        // Keep the stored list to existing layer names (original spelling).
        let keep = doc.layers.map(\.name).filter { r.contains($0.lowercased()) }
        doc.setVariable(listVar, keep.joined(separator: sep))
    }
    /// Turns notification on (taking the current layers as the baseline when none exists) or off.
    public static func setOn(_ on: Bool, _ doc: inout ArchiDocument) {
        doc.setVariable(enabledVar, on ? "1" : "0")
        if on && reconciled(doc) == nil { reconcile(nil, &doc) }
    }
    /// Message for layers that became unreconciled between two states of the drawing, or nil.
    public static func message(before: ArchiDocument, after: ArchiDocument) -> String? {
        guard isOn(after) else { return nil }
        let old = Set(unreconciled(before).map { $0.lowercased() })
        let new = unreconciled(after).filter { !old.contains($0.lowercased()) }
        guard !new.isEmpty else { return nil }
        return "Unreconciled new layer\(new.count == 1 ? "" : "s"): \(new.joined(separator: ", ")) (LAYRECONCILE to accept)."
    }
}
