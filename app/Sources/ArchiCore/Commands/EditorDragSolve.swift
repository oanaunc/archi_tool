// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// State of a live constraint drag started by the canvas.
public struct ConstraintDragState {
    /// The dragged point (entity + part).
    public var ref: CRef
    /// Document before the drag (restored on cancel, recorded as one undo step on commit).
    public var before: ArchiDocument
    /// Last solve of the drag.
    public var lastReport: SolveReport?
}

/// Live solve-based dragging API for the canvas (M3D-087): the canvas calls `beginDragSolve` on mouse-down on a grip,
/// `dragSolve(point:)` on every mouse-move (the drawing updates with all constraints satisfied) and `endDragSolve` on mouse-up.
extension Editor {
    /// Starts dragging a specific constrainable point. Returns false when the point cannot be dragged (locked layer, not constrainable).
    @discardableResult
    public func beginDragSolve(ref: CRef) -> Bool {
        guard let e = doc.entity(ref.entity), doc.isEditable(layer: e.layer), Constraints.point(e.geometry, part: ref.part) != nil,
              Constraints.params(e.geometry) != nil else { return false }
        if constraintDrag != nil { endDragSolve(commit: true) }
        constraintDrag = ConstraintDragState(ref: ref, before: doc, lastReport: nil)
        return true
    }

    /// Starts dragging the constrainable point nearest to `point` (within `tolerance`, default the pick tolerance),
    /// preferring entities that carry constraints. Returns the grabbed reference.
    @discardableResult
    public func beginDragSolve(near point: Vec2, tolerance: Double? = nil) -> CRef? {
        let tol = tolerance ?? pickTolerance
        let constrained = Set(ConstraintSet.load(doc).constraints.flatMap { $0.refs.map(\.entity) })
        var best: (CRef, Double)?
        for e in doc.entities where doc.isEditable(layer: e.layer) && Constraints.params(e.geometry) != nil {
            for (part, q) in Constraints.points(e.geometry) {
                // Constrained entities win ties by a small margin.
                let d = q.distance(to: point) - (constrained.contains(e.id) ? tol * 1e-3 : 0)
                if q.distance(to: point) <= tol, d < (best?.1 ?? .infinity) { best = (CRef(e.id, part), d) }
            }
        }
        guard let r = best?.0, beginDragSolve(ref: r) else { return nil }
        return r
    }

    /// Moves the dragged point to `point` and re-solves the constraints live (no undo step until `endDragSolve`).
    /// Starts a drag at the nearest constrainable point when none is active. Returns the solve report, nil if nothing is dragged.
    @discardableResult
    public func dragSolve(point: Vec2) -> SolveReport? {
        if constraintDrag == nil { guard beginDragSolve(near: point) != nil else { return nil } }
        guard var st = constraintDrag else { return nil }
        var d = doc
        let r = Constraints.dragSolve(&d, ref: st.ref, to: point)
        if d != doc { doc = d }
        st.lastReport = r
        constraintDrag = st
        return r
    }

    /// Finishes the drag: commit records one undo step ("Drag"), otherwise the drawing returns to its state before the drag.
    public func endDragSolve(commit: Bool = true) {
        guard let st = constraintDrag else { return }
        constraintDrag = nil
        if !commit { if doc != st.before { doc = st.before }; return }
        guard doc != st.before else { return }
        var d = doc
        DocumentUpdaters.run(&d)
        history.record("Drag", before: st.before)
        doc = d
        isDirty = true
    }
}
