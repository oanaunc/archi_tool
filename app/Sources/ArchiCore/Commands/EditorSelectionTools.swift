// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Selection cycling and nudging (core side of SEL-018 / MOD-028).
extension Editor {
    /// Every selectable object within `tolerance` of a point, nearest first (entities and elements of the current level).
    public func pickCandidates(at p: Vec2, tolerance: Double? = nil) -> [EntityID] {
        let tol = tolerance ?? pickTolerance
        var c: [(EntityID, Double)] = []
        let f = PickFilter(doc)
        for e in doc.entities where f.pickable(e) {
            let d = GeometryOps.distance(from: p, to: e.geometry, doc: doc)
            if d <= tol { c.append((e.id, d)) }
        }
        for el in doc.elements where f.pickable(el) {
            let d = PlanRepresentation.distance(from: p, to: el, doc: doc)
            if d <= tol { c.append((el.id, d)) }
        }
        return c.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }.map(\.0)
    }

    /// Selection cycling: repeated picks at (nearly) the same point step through the overlapping objects.
    /// Returns the object to highlight/select, or nil when nothing is there.
    @discardableResult
    public func cyclePick(at p: Vec2, tolerance: Double? = nil) -> EntityID? {
        let cands = pickCandidates(at: p, tolerance: tolerance)
        guard !cands.isEmpty else { pickCycle = nil; return nil }
        let tol = tolerance ?? pickTolerance
        var idx = 0
        if let pc = pickCycle, pc.point.distance(to: p) <= tol { idx = (pc.index + 1) % cands.count }
        pickCycle = (p, idx)
        return cands[idx]
    }

    /// Moves the selected objects by `delta` as one undo step ("Nudge"). Locked objects are skipped. Returns objects moved.
    @discardableResult
    public func nudgeSelection(by delta: Vec2) -> Int {
        let ids = expandGroups(Array(selection)).filter { isSelectable($0) }
        guard !ids.isEmpty, delta.length > 0 else { return 0 }
        var n = 0
        transaction("Nudge") { d in
            let t = Transform2D.translation(delta)
            for id in ids {
                if let i = d.entityIndex(id) { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, t); n += 1 }
                else if let i = d.elementIndex(id) { d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, t); n += 1 }
            }
        }
        return n
    }

    /// Nudge step for arrow keys: the snap spacing when grid snap is on, otherwise `pixels` × the size of one screen pixel
    /// (the pick tolerance corresponds to about 6 px).
    public func nudgeStep(pixels: Double = 1) -> Double {
        settings.gridSnap && settings.gridSpacing > 0 ? settings.gridSpacing : pickTolerance / 6 * pixels
    }

    /// Freehand lasso selection (SEL-007): the dragged loop selects by window (clockwise) or crossing (counter-clockwise)
    /// unless `crossing` forces a mode. Returns the selected ids (not applied to the selection set).
    public func select(lasso loop: [Vec2], crossing: Bool? = nil) -> [EntityID] {
        var pts: [Vec2] = []
        for p in loop where pts.last.map({ !$0.isClose(p, tol: 1e-9) }) ?? true { pts.append(p) }
        guard let inferred = SelectionGeometry.lassoMode(pts) else { return [] }
        let mode: SelectionGeometry.Mode = crossing.map { $0 ? .crossingPolygon : .windowPolygon } ?? inferred
        return SelectionGeometry.select(doc: doc, polygon: pts, mode: mode, level: doc.currentLevel)
    }
}

