// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// One grip of a selected object (a drafting entity or a BIM element), addressed by its index in the object's grip list.
public struct ObjectGrip: Hashable {
    public var id: EntityID
    public var index: Int
    public var point: Vec2
    /// Role of an entity grip (nil for BIM element grips).
    public var kind: GripKind?
    public init(id: EntityID, index: Int, point: Vec2, kind: GripKind? = nil) { self.id = id; self.index = index; self.point = point; self.kind = kind }
}

extension GripMode {
    /// Keywords typed while a grip is hot (SEL-034): ST, MO, RO, SC, MI and the full words.
    public static func keyword(_ s: String) -> GripMode? {
        switch s.trimmingCharacters(in: .whitespaces).uppercased() {
        case "ST", "STRETCH": return .stretch
        case "MO", "MOVE": return .move
        case "RO", "ROTATE": return .rotate
        case "SC", "SCALE": return .scale
        case "MI", "MIRROR": return .mirror
        default: return nil
        }
    }
}

/// Index-based grip editing of entities and BIM elements (SEL-032…SEL-038): everything the canvas needs to show grips,
/// hit-test them, preview a drag and commit it as one undo step, so the UI holds no editing logic of its own.
extension Editor {
    /// GRIPS system variable (0 hides grips).
    public var gripsEnabled: Bool { (doc.variable("GRIPS").flatMap(Int.init) ?? 1) != 0 }
    /// GRIPOBJLIMIT: grips are not shown when more objects are selected (default 300, 0 = no limit).
    public var gripObjectLimit: Int { max(0, doc.variable("GRIPOBJLIMIT").flatMap(Int.init) ?? 300) }

    /// Grip points of an entity or element (empty for unknown ids). Index = position in the list.
    public func objectGrips(_ id: EntityID) -> [Vec2] {
        if let e = doc.entity(id) { return Grips.grips(e.geometry).map(\.point) }
        if let el = doc.element(id) { return ElementGrips.points(el, doc: doc) }
        return []
    }

    /// Grips of the selected, selectable objects, honouring GRIPS and GRIPOBJLIMIT (only while no command runs).
    public func selectionGrips() -> [ObjectGrip] {
        guard isIdle, gripsEnabled, !selection.isEmpty else { return [] }
        let lim = gripObjectLimit
        if lim > 0 && selection.count > lim { return [] }
        var out: [ObjectGrip] = []
        for e in doc.entities where selection.contains(e.id) && isSelectable(e.id) {
            for (i, g) in Grips.grips(e.geometry).enumerated() { out.append(ObjectGrip(id: e.id, index: i, point: g.point, kind: g.kind)) }
        }
        for el in doc.elements where selection.contains(el.id) && isSelectable(el.id) {
            for (i, p) in ElementGrips.points(el, doc: doc).enumerated() { out.append(ObjectGrip(id: el.id, index: i, point: p)) }
        }
        return out
    }

    /// The selected-object grip nearest to `p` within `tolerance` (drawing units; default the pick tolerance).
    public func gripHit(at p: Vec2, tolerance: Double? = nil) -> ObjectGrip? {
        let tol = tolerance ?? pickTolerance
        return selectionGrips().filter { max(abs($0.point.x - p.x), abs($0.point.y - p.y)) <= tol }
            .min { $0.point.distance(to: p) < $1.point.distance(to: p) }
    }

    /// Reference length for drag scaling in grip Scale mode: half the larger side of the objects' bounds.
    public func gripReference(_ ids: [EntityID]) -> Double {
        var b = BBox2.empty
        for id in ids {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            else if let el = doc.element(id) { for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) } }
        }
        return b.isEmpty ? 1 : max(max(b.width, b.height) / 2, 1e-6)
    }

    /// Transform of a value typed while a grip is hot: Move = distance toward the cursor, Rotate = degrees, Scale = factor.
    public static func gripTypedTransform(_ mode: GripMode, base: Vec2, cursor: Vec2, value: Double) -> Transform2D? {
        switch mode {
        case .move:
            let d = (cursor - base).normalized
            return .translation((d == .zero ? Vec2(1, 0) : d) * value)
        case .rotate: return .rotation(rad(value), around: base)
        case .scale: return value > 1e-12 ? .translation(base) * .scale(value, value) * .translation(-base) : nil
        case .mirror, .stretch: return nil
        }
    }

    /// Objects a grip mode acts on: the selection plus the hot object, groups expanded, locked objects skipped.
    public func gripTargets(_ id: EntityID) -> [EntityID] {
        expandGroups(Array(selection.union([id])).sorted()).filter { isSelectable($0) }
    }

    /// Geometry of object `id` after dragging grip `index` from `o` to `p` (stretch, optional action and quarter turns).
    func gripStretched(_ id: EntityID, index: Int, from o: Vec2, to p: Vec2, action: GripAction?, turns: Int, in d: ArchiDocument) -> (Geometry?, BIMGeometry?) {
        let q = ElementGrips.quarterTurn(turns, about: p)
        if let e = d.entity(id) {
            let gs = Grips.grips(e.geometry)
            var g: Geometry
            if gs.indices.contains(index) {
                if let a = action, a != .stretch { guard let r = Grips.apply(a, e.geometry, grip: gs[index], to: p) else { return (nil, nil) }; g = r }
                else { g = Grips.stretched(e.geometry, grip: gs[index], to: p) }
            } else { g = GeometryOps.transform(e.geometry, .translation(p - o)) }
            if let q { g = GeometryOps.transform(g, q) }
            return (g, nil)
        }
        if let el = d.element(id) {
            var g = ElementGrips.moved(el, grip: index, from: o, to: p, doc: d)
            if let q { g = CommandHelpers.transform(g, q) }
            return (nil, g)
        }
        return (nil, nil)
    }

    /// Live preview of a grip drag: drafting geometry and moved element copies to draw as rubber-band. Nothing is changed.
    public func gripPreview(_ id: EntityID, index: Int, from o: Vec2, to p: Vec2, mode: GripMode = .stretch, action: GripAction? = nil,
                            turns: Int = 0, reference: Double? = nil) -> (geometry: [Geometry], elements: [BIMElement]) {
        if mode != .stretch {
            guard let t = Grips.modeTransform(mode, base: o, to: p, reference: reference ?? gripReference(gripTargets(id))) else { return ([], []) }
            var gs: [Geometry] = [], els: [BIMElement] = []
            for tid in gripTargets(id) {
                if let e = doc.entity(tid) { gs.append(GeometryOps.transform(e.geometry, t)) }
                else if var el = doc.element(tid) { el.geometry = CommandHelpers.transform(el.geometry, t); els.append(el) }
            }
            return (gs, els)
        }
        let (g, bg) = gripStretched(id, index: index, from: o, to: p, action: action, turns: turns, in: doc)
        if let g { return ([g], []) }
        if let bg, var el = doc.element(id) { el.geometry = bg; return ([], [el]) }
        return ([], [])
    }

    /// Applies a transform to objects (copies with `copy`) as one undo step. Locked objects are skipped. Returns the ids
    /// changed or created.
    @discardableResult
    public func gripApply(_ ids: [EntityID], _ t: Transform2D, copy: Bool, label: String) -> [EntityID] {
        let targets = expandGroups(ids).filter { isSelectable($0) }
        guard !targets.isEmpty else { return [] }
        var out: [EntityID] = []
        transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) {
                    let g = GeometryOps.transform(d.entities[i].geometry, t)
                    if copy { var n = d.entities[i]; n.geometry = g; out.append(d.add(n)) } else { d.entities[i].geometry = g; out.append(id) }
                } else if let i = d.elementIndex(id) {
                    let g = CommandHelpers.transform(d.elements[i].geometry, t)
                    if copy { var n = d.elements[i]; n.id = d.allocateID(); n.geometry = g; d.elements.append(n); out.append(n.id) }
                    else { d.elements[i].geometry = g; out.append(id) }
                }
            }
        }
        return out
    }

    /// Commits a grip drag of grip `index` of object `id` from `o` to `p` as one undo step:
    /// - `.stretch`: the grip moves (with a multi-functional `action`, and `turns` quarter turns about the new point);
    ///   dragging a wall end also drags the ends of walls joined there; `copy` adds an edited copy instead;
    /// - other modes: move / rotate / scale / mirror the selection (plus `id`) about the grip, copies with `copy`.
    /// With `snap` the point is resolved with running object snaps / ortho / polar first. Returns the ids changed or created.
    @discardableResult
    public func gripEdit(_ id: EntityID, index: Int, from o: Vec2, to cursor: Vec2, mode: GripMode = .stretch, action: GripAction? = nil,
                         copy: Bool = false, turns: Int = 0, snap: Bool = false, reference: Double? = nil) -> [EntityID] {
        guard isSelectable(id), doc.entity(id) != nil || doc.element(id) != nil else { return [] }
        var p = cursor
        if snap {
            if let e = doc.entity(id), case let g = Grips.grips(e.geometry), g.indices.contains(index) {
                p = gripDragPoint(id, grip: g[index], cursor: cursor)
            } else {
                var s = settings; s.objectSnapTracking = false
                if let hit = Snap.find(cursor: cursor, doc: doc, settings: s, tolerance: pickTolerance, base: o), hit.kind != .grid, hit.entity != id { p = hit.point }
                else { p = Snap.constrain(base: o, cursor: cursor, settings: settings) }
            }
        }
        if mode != .stretch {
            let targets = gripTargets(id)
            guard let t = Grips.modeTransform(mode, base: o, to: p, reference: reference ?? gripReference(targets)) else { return [] }
            return gripApply(targets, t, copy: copy, label: "Grip \(mode.rawValue.capitalized)\(copy ? " Copy" : "")")
        }
        let rotated = ElementGrips.quarterTurn(turns, about: p) != nil
        guard p.distance(to: o) > 1e-12 || rotated || (action != nil && action != .stretch) else { return [] }
        let (g, bg) = gripStretched(id, index: index, from: o, to: p, action: action, turns: turns, in: doc)
        guard g != nil || bg != nil else { return [] }
        var out: [EntityID] = []
        let label = action.map { $0 == .stretch ? "Grip Edit" : $0.title } ?? (rotated ? "Grip Edit + Rotate" : "Grip Edit")
        transaction(copy ? "Grip Copy" : label) { d in
            if let g, let i = d.entityIndex(id) {
                if copy { var n = d.entities[i]; n.geometry = g; out.append(d.add(n)) } else { d.entities[i].geometry = g; out.append(id) }
            } else if let bg, let k = d.elementIndex(id) {
                let el = d.elements[k]
                if copy { var n = el; n.id = d.allocateID(); n.geometry = bg; d.elements.append(n); out.append(n.id); return }
                d.elements[k].geometry = bg
                out.append(id)
                // Joined walls follow a dragged wall end.
                if case .wall(let w) = el.geometry, index <= 1, !rotated {
                    let old = index == 0 ? w.start : w.end
                    let tol = max(w.thickness * 0.01, 1e-6)
                    for j in d.elements.indices where j != k && d.elements[j].level == el.level {
                        guard case .wall(var o2) = d.elements[j].geometry else { continue }
                        var changed = false
                        if o2.start.distance(to: old) <= tol { o2.start = p; changed = true }
                        if o2.end.distance(to: old) <= tol { o2.end = p; changed = true }
                        if changed { d.elements[j].geometry = .wall(o2); out.append(d.elements[j].id) }
                    }
                }
            }
        }
        return out
    }

    /// A value typed while grip `index` of `id` is hot (SEL-038): Stretch moves the grip `value` toward `cursor`;
    /// Move / Rotate / Scale apply `gripTypedTransform` to the selection. Returns the ids changed or created.
    @discardableResult
    public func gripTypedValue(_ id: EntityID, index: Int, mode: GripMode, value: Double, cursor: Vec2, copy: Bool = false) -> [EntityID] {
        let pts = objectGrips(id)
        guard pts.indices.contains(index) else { return [] }
        let o = pts[index]
        if mode == .stretch {
            var dir = (cursor - o).normalized
            if settings.ortho { dir = abs(dir.x) >= abs(dir.y) ? Vec2(dir.x >= 0 ? 1 : -1, 0) : Vec2(0, dir.y >= 0 ? 1 : -1) }
            if dir == .zero { dir = Vec2(1, 0) }
            return gripEdit(id, index: index, from: o, to: o + dir * value, copy: copy)
        }
        guard let t = Editor.gripTypedTransform(mode, base: o, cursor: cursor, value: value) else { return [] }
        return gripApply(gripTargets(id), t, copy: copy, label: "Grip \(mode.rawValue.capitalized)\(copy ? " Copy" : "")")
    }

    /// Multi-functional grip options (SEL-035) available on grip `index` of an entity (empty for elements).
    public func gripActions(_ id: EntityID, index: Int) -> [GripAction] {
        guard let e = doc.entity(id) else { return [] }
        let gs = Grips.grips(e.geometry)
        return gs.indices.contains(index) ? Grips.actions(e.geometry, grip: gs[index]) : []
    }

    // MARK: Lasso (SEL-007)

    /// Applies a freehand lasso to the selection: adds the objects found (groups expanded), or removes them with `remove`
    /// (Shift). Returns the ids found.
    @discardableResult
    public func applyLasso(_ loop: [Vec2], remove: Bool = false, crossing: Bool? = nil) -> Set<EntityID> {
        let ids = Set(expandGroups(select(lasso: loop, crossing: crossing)))
        if remove { selection.subtract(ids) } else { selection.formUnion(ids) }
        return ids
    }
}
