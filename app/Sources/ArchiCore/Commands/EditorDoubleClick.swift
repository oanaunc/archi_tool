// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Double-click editing (MOD-063, DBLCLKEDIT): the editor command a double click on an object starts, with the object
/// passed by id so only that object is edited. Nil when DBLCLKEDIT is off or the object is unknown.
extension Editor {
    public var doubleClickEditing: Bool { (doc.variable("DBLCLKEDIT") ?? "ON").uppercased() != "OFF" && doc.variable("DBLCLKEDIT") != "0" }

    /// Command line for a double click on object `id` (e.g. "TEXTEDIT #12", "PEDIT #7", "BEDIT DESK").
    public func doubleClickCommand(for id: EntityID) -> String? {
        guard doubleClickEditing else { return nil }
        if doc.element(id) != nil { return "PROPERTIES" }
        guard let e = doc.entity(id) else { return nil }
        if BlockEditing.refEditingBlock(doc) != nil || BlockEditing.editingBlock(doc) != nil {
            // Inside the block editor / reference edit, objects are edited as ordinary objects.
            if case .insert = e.geometry { return "PROPERTIES" }
        }
        if AssocArray.isArray(e) { return "ARRAYEDIT #\(id)" }
        if bimArrayName(of: id) != nil { return "ARRAYEDIT #\(id)" }
        switch e.geometry {
        case .text, .leader: return "TEXTEDIT #\(id)"
        case .dimension: return "TEXTEDIT #\(id)"
        case .table: return "TABLEEDIT #\(id)"
        case .hatch: return "HATCHEDIT #\(id)"
        case .polyline: return "PEDIT #\(id)"
        case .spline: return "SPLINEDIT #\(id)"
        case .insert(let i):
            if Xrefs.isXref(i.block, doc) { return "REFEDIT #\(id)" }
            if !i.attributes.isEmpty { return "ATTEDIT #\(id)" }
            return "BEDIT \(i.block.contains(" ") ? "\"\(i.block)\"" : i.block)"
        default: return "PROPERTIES"
        }
    }
}
