// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Temporary dimensions on selection (CMD-035): a selected wall, grid line, column or component shows its distance to
/// the nearest parallel walls / grid lines on each side; typing a new value moves the element (one undo step).
public struct TemporaryDimension: Hashable {
    /// The selected element and the reference it is measured from.
    public var id: EntityID
    public var reference: EntityID
    /// Dimension line end points (on the reference, on the element).
    public var from: Vec2
    public var to: Vec2
    public var value: Double { from.distance(to: to) }
    /// Unit direction from the reference towards the element (the element moves along it).
    public var direction: Vec2
}

extension Editor {
    /// Location line (point + unit direction) of linear elements; nil for others.
    func locationLine(_ el: BIMElement) -> (Vec2, Vec2)? {
        switch el.geometry {
        case .wall(let w) where abs(w.bulge) < 1e-9: let d = (w.end - w.start).normalized; return d == .zero ? nil : (w.start, d)
        case .gridLine(let g) where abs(g.bulge) < 1e-9: let d = (g.end - g.start).normalized; return d == .zero ? nil : (g.start, d)
        case .beam(let b): let d = (b.end - b.start).normalized; return d == .zero ? nil : (b.start, d)
        case .curtainWall(let c): let d = (c.end - c.start).normalized; return d == .zero ? nil : (c.start, d)
        default: return nil
        }
    }

    /// Temporary dimensions of an element to its nearest parallel references (at most one per side and axis).
    public func temporaryDimensions(for id: EntityID) -> [TemporaryDimension] {
        guard let el = doc.element(id) else { return [] }
        let refs = doc.elements.filter { $0.id != id && $0.level == el.level }.compactMap { r -> (EntityID, Vec2, Vec2)? in
            guard let (p, d) = locationLine(r) else { return nil }
            return (r.id, p, d)
        }
        // Anchor point and the normals to measure along.
        var anchor: Vec2
        var normals: [Vec2]
        if let (p, d) = locationLine(el) {
            let pts = ElementGrips.points(el, doc: doc)
            anchor = pts.count >= 3 ? pts[2] : p
            normals = [d.perp]
        } else {
            guard let p = ElementGrips.points(el, doc: doc).first else { return [] }
            anchor = p
            normals = [Vec2(1, 0), Vec2(0, 1)]
        }
        var out: [TemporaryDimension] = []
        for n in normals {
            var best: [Double: (Double, EntityID, Vec2)] = [:]   // side (±1) → (distance, ref, foot)
            for (rid, p, d) in refs where abs(d.cross(n)) > 1 - 1e-6 {   // reference parallel to the element (perpendicular to n)
                // Foot of the anchor on the reference line.
                let foot = p + d * (anchor - p).dot(d)
                let s = (anchor - foot).dot(n)
                guard abs(s) > 1e-9 else { continue }
                let side: Double = s > 0 ? 1 : -1
                if best[side] == nil || abs(s) < best[side]!.0 { best[side] = (abs(s), rid, foot) }
            }
            for side in [-1.0, 1.0] {
                guard let (_, rid, foot) = best[side] else { continue }
                out.append(TemporaryDimension(id: id, reference: rid, from: foot, to: anchor, direction: (anchor - foot).normalized))
            }
        }
        return out
    }

    /// Sets a temporary dimension to `value` by moving its element along the dimension (one undo step).
    @discardableResult
    public func applyTemporaryDimension(_ td: TemporaryDimension, value: Double) -> Bool {
        guard value > 0, isSelectable(td.id), doc.element(td.id) != nil else { return false }
        let delta = td.direction * (value - td.value)
        guard delta.length > 1e-12 else { return false }
        var ok = false
        transaction("Temporary Dimension") { d in
            guard let i = d.elementIndex(td.id) else { return }
            d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, .translation(delta))
            ok = true
        }
        return ok
    }
}
