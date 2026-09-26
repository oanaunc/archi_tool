// Oanarina Archi Tool — GPL-3.0-or-later
// Hosted components (BIM-099): components placed on a wall face, on a floor or under a ceiling keep their host
// (props host = id, hostKind = wall/floor/ceiling, hostS/hostSide/hostZ for walls) and follow it when it moves,
// rotates, changes thickness or height.
import Foundation

public enum HostedComponents {
    public enum Kind: String { case wall, floor, ceiling }

    /// The host candidate for a point: nearest wall (within `reach` of its centreline), or the floor/ceiling slab containing it.
    public static func host(_ kind: Kind, at p: Vec2, doc: ArchiDocument, level: Int, reach: Double) -> BIMElement? {
        switch kind {
        case .wall:
            return doc.elements.filter { $0.level == level }.compactMap { el -> (BIMElement, Double)? in
                guard let f = WallFrame(el) else { return nil }
                let pr = f.project(p)
                guard pr.s >= -1e-6, pr.s <= f.L + 1e-6, abs(pr.t) <= f.h + reach else { return nil }
                return (el, abs(pr.t))
            }.min { $0.1 < $1.1 }?.0
        case .floor, .ceiling:
            return doc.elements.first { el in
                guard el.level == level, case .slab(let s) = el.geometry, (el.props["kind"] == "ceiling") == (kind == .ceiling) else { return false }
                return GeometryOps.pointInPolygon(p, s.boundary)
            }
        }
    }

    /// Records the host of a component from its current placement (wall: side and position along the wall, height).
    public static func attach(_ id: EntityID, to hostID: EntityID, kind: Kind, doc: inout ArchiDocument) {
        guard let i = doc.elementIndex(id), case .component(let g) = doc.elements[i].geometry, let host = doc.element(hostID) else { return }
        doc.elements[i].props["host"] = "\(hostID)"
        doc.elements[i].props["hostKind"] = kind.rawValue
        if kind == .wall, let f = WallFrame(host) {
            let pr = f.project(g.position)
            doc.elements[i].props["hostS"] = fmt(pr.s, 6)
            doc.elements[i].props["hostSide"] = pr.t >= 0 ? "1" : "-1"
            doc.elements[i].props["hostZ"] = fmt(g.baseOffset, 6)
        }
        _ = updateAll(&doc)
    }

    public static func hasHosted(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props["hostKind"] != nil } }

    /// Moves hosted components with their hosts. Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices {
            guard let k = doc.elements[i].props["hostKind"].flatMap(Kind.init), let hid = doc.elements[i].props["host"].flatMap(Int.init),
                  case .component(var g) = doc.elements[i].geometry, let host = doc.element(hid) else { continue }
            let old = g
            switch k {
            case .wall:
                guard let f = WallFrame(host), let s0 = doc.elements[i].props["hostS"].flatMap(Double.init) else { continue }
                let side = doc.elements[i].props["hostSide"] == "-1" ? -1.0 : 1.0
                let s = min(max(s0, 0), f.L)
                // Back of the component against the wall face, facing away from the wall.
                g.position = f.pt(s, side * (f.h + g.size.y / 2))
                g.rotation = f.tangent(s).angle + (side > 0 ? 0 : .pi)
                g.baseOffset = (doc.elements[i].props["hostZ"].flatMap(Double.init) ?? g.baseOffset) + (BIMConstraints.wallNominalBase(host, doc: doc) - (doc.level(doc.elements[i].level)?.elevation ?? 0))
                doc.elements[i].level = host.level
            case .floor:
                guard case .slab(let sl) = host.geometry else { continue }
                g.baseOffset = sl.topHeight(at: g.position) + (doc.level(host.level)?.elevation ?? 0) - (doc.level(doc.elements[i].level)?.elevation ?? 0)
            case .ceiling:
                guard case .slab(let sl) = host.geometry else { continue }
                let under = sl.topHeight(at: g.position) - sl.thickness
                g.baseOffset = under - g.size.z + (doc.level(host.level)?.elevation ?? 0) - (doc.level(doc.elements[i].level)?.elevation ?? 0)
            }
            if g != old { doc.elements[i].geometry = .component(g); changed = true }
        }
        return changed
    }
}
