// Oanarina Archi Tool — GPL-3.0-or-later
// Railings hosted on stairs (BIM-072): both sides of every flight (outer edge of spirals), sloped through the tread
// nosings, and kept associative (props hostStair / stairRail) so they follow edits of the stair.
import Foundation

public enum StairRailings {
    /// Railing paths (plan points with heights above the stair's level): two per flight, inset from the stair edges.
    public static func paths(_ g: StairGeom, inset: Double) -> [(path: [Vec2], z: [Double])] {
        let l = StairShapes.layout(g)
        let r = g.riserHeight, td = max(g.treadDepth, 1e-3)
        let half = max(g.width / 2 - inset, 1e-3)
        var out: [(path: [Vec2], z: [Double])] = []
        if g.kind == .spiral {
            let n = max(g.riserCount - 1, 1)
            let rw = g.spiralInnerRadius + g.width / 2, ro = g.spiralInnerRadius + g.width - inset
            let dt = (g.turnsRight ? -1.0 : 1.0) * td / rw
            let pts = (0...n).map { g.start + Vec2.polar(ro, g.direction + Double($0) * dt) }
            out.append((pts, (0...n).map { Double($0 + 1) * r }))
            return out
        }
        for f in l.flights where f.count > 0 {
            let side = f.dir.perp
            let len = Double(f.count) * td
            for s in [1.0, -1.0] {
                let a = f.origin + side * (s * half)
                out.append(([a, a + f.dir * len], [Double(f.firstStep) * r, Double(f.firstStep + f.count) * r]))
            }
        }
        return out
    }

    /// Creates the railings of a stair; returns their ids.
    @discardableResult
    public static func create(on stairID: EntityID, height: Double, doc: inout ArchiDocument) -> [EntityID] {
        guard let st = doc.element(stairID), case .stair(let g) = st.geometry else { return [] }
        let inset = 50 / doc.units.mm
        var ids: [EntityID] = []
        for (k, p) in paths(g, inset: inset).enumerated() {
            let id = doc.addElement(.railing(RailingGeom(path: p.path, height: height, pathZ: p.z)), level: st.level, name: "Stair Railing")
            if let i = doc.elementIndex(id) { doc.elements[i].props["hostStair"] = "\(stairID)"; doc.elements[i].props["stairRail"] = "\(k)" }
            ids.append(id)
        }
        return ids
    }

    public static func hasHosted(_ doc: ArchiDocument) -> Bool { doc.elements.contains { $0.props["hostStair"] != nil } }

    /// Regenerates stair-hosted railing paths from their stairs (railings whose stair or flight is gone keep their shape).
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        var cache: [EntityID: [(path: [Vec2], z: [Double])]] = [:]
        for i in doc.elements.indices {
            guard let sid = doc.elements[i].props["hostStair"].flatMap(Int.init), let k = doc.elements[i].props["stairRail"].flatMap(Int.init),
                  case .railing(var rg) = doc.elements[i].geometry, let st = doc.element(sid), case .stair(let g) = st.geometry else { continue }
            let ps = cache[sid] ?? paths(g, inset: 50 / doc.units.mm)
            cache[sid] = ps
            guard k < ps.count else { continue }
            if rg.path != ps[k].path || rg.pathZ != ps[k].z || doc.elements[i].level != st.level {
                rg.path = ps[k].path; rg.pathZ = ps[k].z
                doc.elements[i].geometry = .railing(rg); doc.elements[i].level = st.level; changed = true
            }
        }
        return changed
    }
}
