// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Grip editing through the editor (SEL-032…SEL-038): grip lists, the snapped / constrained drag point, stretch and
/// grip modes with Copy, multi-functional options and typed distances — each edit is one undo step.
extension Editor {
    /// Grips of a drafting entity (nil for unknown ids and BIM elements, whose grips the canvas handles).
    public func grips(of id: EntityID) -> [Grip]? {
        guard let e = doc.entity(id) else { return nil }
        return Grips.grips(e.geometry)
    }

    /// Where a grip dragged to `cursor` lands: running object snaps (to other objects and to fixed points of the edited one),
    /// otherwise ortho / polar / grid from the grip's original location.
    public func gripDragPoint(_ id: EntityID, grip: Grip, cursor: Vec2, tolerance: Double? = nil) -> Vec2 {
        let tol = tolerance ?? pickTolerance
        var d = doc
        if let i = d.entityIndex(id) {
            let g = d.entities[i].geometry
            // The dragged grip itself must not attract the cursor: snap against the object without that point moving.
            d.entities[i].geometry = Grips.stretched(g, grip: grip, to: grip.point + Vec2(1e9, 1e9))
            if Grips.grips(g).count <= 1 { d.entities.remove(at: i) }
        }
        var s = settings
        s.objectSnapTracking = false
        if let hit = Snap.find(cursor: cursor, doc: d, settings: s, tolerance: tol, base: grip.point), hit.kind != .grid { return hit.point }
        return Snap.constrain(base: grip.point, cursor: cursor, settings: settings)
    }

    /// Drags a grip (stretch, or a grip mode about the grip) to `cursor`; with `snap` the point is resolved by
    /// `gripDragPoint`. `copy` keeps the original and adds the edited copy. Returns the id of the edited (or new) object.
    @discardableResult
    public func gripEdit(_ id: EntityID, grip: Grip, to cursor: Vec2, mode: GripMode = .stretch, copy: Bool = false, snap: Bool = true, reference: Double = 1) -> EntityID? {
        guard let e = doc.entity(id), isSelectable(id) else { return nil }
        let p = snap ? gripDragPoint(id, grip: grip, cursor: cursor) : cursor
        let ng: Geometry
        if mode == .stretch { ng = Grips.stretched(e.geometry, grip: grip, to: p) }
        else {
            guard let t = Grips.modeTransform(mode, base: grip.point, to: p, reference: reference) else { return nil }
            ng = GeometryOps.transform(e.geometry, t)
        }
        return commitGrip(id, ng, label: "Grip \(mode.rawValue.capitalized)", copy: copy)
    }

    /// Multi-functional grip option (add/remove vertex, convert to arc/line, lengthen, radius) as one undo step.
    @discardableResult
    public func gripAction(_ id: EntityID, grip: Grip, action: GripAction, to cursor: Vec2, snap: Bool = true) -> Bool {
        guard let e = doc.entity(id), isSelectable(id), Grips.actions(e.geometry, grip: grip).contains(action) else { return false }
        let p = snap ? gripDragPoint(id, grip: grip, cursor: cursor) : cursor
        guard let ng = Grips.apply(action, e.geometry, grip: grip, to: p) else { return false }
        return commitGrip(id, ng, label: action.title, copy: false) != nil
    }

    /// Hot-grip typed value (SEL-038): the grip moves `distance` from its location toward `cursor` (or at `angle` radians
    /// when given), exactly as a typed direct distance. Stretch mode only.
    @discardableResult
    public func gripTyped(_ id: EntityID, grip: Grip, distance: Double, toward cursor: Vec2? = nil, angle: Double? = nil) -> Bool {
        guard let e = doc.entity(id), isSelectable(id) else { return false }
        var dir = angle.map { Vec2.polar(1, $0) } ?? ((cursor ?? grip.point + Vec2(1, 0)) - grip.point).normalized
        if angle == nil && settings.ortho { dir = abs(dir.x) >= abs(dir.y) ? Vec2(dir.x >= 0 ? 1 : -1, 0) : Vec2(0, dir.y >= 0 ? 1 : -1) }
        guard dir != .zero else { return false }
        return commitGrip(id, Grips.stretched(e.geometry, grip: grip, to: grip.point + dir * distance), label: "Grip Stretch", copy: false) != nil
    }

    private func commitGrip(_ id: EntityID, _ g: Geometry, label: String, copy: Bool) -> EntityID? {
        var out: EntityID?
        transaction(label) { d in
            guard let i = d.entityIndex(id) else { return }
            if copy {
                var n = d.entities[i]
                n.geometry = g
                out = d.add(n)
            } else { d.entities[i].geometry = g; out = id }
        }
        return out
    }
}
