// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Which objects pick, window and crossing selection may return (SEL-001): only objects displayed in the current plan view
/// (entities tagged with another level, objects hidden by worksets / design options / MEP filters, and everything outside
/// a drafting view being edited are skipped) that lie on visible, thawed and unlocked layers.
public struct PickFilter {
    let doc: ArchiDocument
    let blocked: Set<String>
    let modelSets: Bool
    let draftingView: String?
    let draftingStart: Int
    public init(_ doc: ArchiDocument) {
        self.doc = doc
        var b = Set<String>()
        for l in doc.layers where !l.isEditable { b.insert(l.name.lowercased()) }
        blocked = b
        modelSets = ModelSets.active(doc)
        draftingView = doc.variable(DraftingViews.editing)
        draftingStart = doc.variable("DRAFTINGSTART").flatMap(Int.init) ?? Int.max
    }
    func layerOK(_ n: String) -> Bool { blocked.isEmpty || !blocked.contains(n.lowercased()) }

    public func pickable(_ e: Entity) -> Bool { layerOK(e.layer) && displayed(e) }
    /// Whether the entity is displayed in the current plan view (layer state aside); object snaps use this, so locked
    /// objects can still be snapped to.
    public func displayed(_ e: Entity) -> Bool {
        if let v = draftingView, e.props["draftingView"] != v && e.id < draftingStart { return false }
        if let l = e.props["level"].flatMap(Int.init), l != doc.currentLevel { return false }
        if modelSets && !ModelSets.isShown(e.props, doc: doc) { return false }
        return true
    }
    public func pickable(_ el: BIMElement) -> Bool {
        guard layerOK(el.layer), el.level == doc.currentLevel, draftingView == nil else { return false }
        if modelSets && !ModelSets.isShown(el.props, doc: doc) { return false }
        return true
    }
}
