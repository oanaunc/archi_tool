// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Room-bounding rules: which elements close rooms, including walls from lower levels that rise through the level.
public enum RoomBounding {
    /// Walls and curtain walls bound rooms unless props["roomBounding"] = "0"; columns only when it is "1".
    public static func isBounding(_ el: BIMElement) -> Bool {
        switch el.geometry {
        case .wall, .curtainWall: return el.props["roomBounding"] != "0"
        case .column: return el.props["roomBounding"] == "1"
        default: return false
        }
    }

    /// Elements that bound rooms on a level (own level plus elements spanning it).
    public static func boundingElements(doc: ArchiDocument, level: Int) -> [BIMElement] {
        doc.elements.filter { el in
            guard isBounding(el) else { return false }
            return el.level == level || BIMConstraints.extraLevels(el, doc: doc).contains(level)
        }
    }

    /// Room boundary (outer loop) around a point, honouring the room-bounding rules; `extraCurves` are separation lines.
    public static func boundary(at p: Vec2, doc: ArchiDocument, level: Int, extraCurves: [Geometry] = []) -> [Vec2]? {
        var pls: [[Vec2]] = []
        for el in boundingElements(doc: doc, level: level) {
            let f = CommandHelpers.footprint(el, doc: doc)
            if f.count >= 3 { pls.append(f + [f[0]]) }
        }
        for g in extraCurves { pls.append(contentsOf: GeometryOps.tessellate(g, doc: doc).filter { $0.count > 1 }) }
        guard let f = RegionFinder.planarFace(containing: p, polylines: pls) else { return nil }
        let s = CommandHelpers.simplify(f.outer)
        return s.count >= 3 ? s : nil
    }
}

/// Ramp flights and landings along a path.
public enum RampLayout {
    public struct Piece: Hashable {
        public var slab: SlabGeom
        public var landing: Bool
    }

    /// Splits a ramp route into sloped flights (each rising at most `maxRise`) and flat landings: corner landings
    /// (width × width) at every turn and straight landings of `landingLength` between flights on long runs.
    /// Heights are relative to the level (0 at the start, `rise` at the end).
    public static func build(path path0: [Vec2], width: Double, rise: Double, thickness: Double, maxRise: Double, landingLength: Double) -> [Piece]? {
        let path = RG.dedupe(path0, closed: false)
        guard path.count >= 2, width > 0, rise > 0 else { return nil }
        let k = path.count - 1
        var runs: [(a: Double, b: Double, dir: Vec2, origin: Vec2)] = []
        for i in 0..<k {
            let a = path[i], b = path[i + 1], len = a.distance(to: b)
            guard len > 1e-9 else { return nil }
            let s0 = i == 0 ? 0 : width / 2, s1 = i == k - 1 ? len : len - width / 2
            guard s1 - s0 > 1e-6 else { return nil }
            runs.append((s0, s1, (b - a) / len, a))
        }
        let mr = maxRise > 0 ? maxRise : rise
        var n = Array(repeating: 1, count: k)
        var gradient = 0.0
        for _ in 0..<200 {
            let sloped = (0..<k).map { (runs[$0].b - runs[$0].a) - Double(n[$0] - 1) * landingLength }
            guard sloped.allSatisfy({ $0 > 1e-6 }) else { return nil }
            gradient = rise / sloped.reduce(0, +)
            var changed = false
            for i in 0..<k where gradient * sloped[i] / Double(n[i]) > mr + 1e-9 { n[i] += 1; changed = true }
            if !changed { break }
        }
        var out: [Piece] = []
        var z = 0.0
        func rect(_ o: Vec2, _ d: Vec2, _ s0: Double, _ s1: Double) -> [Vec2] {
            let w = d.perp * (width / 2)
            return [o + d * s0 - w, o + d * s1 - w, o + d * s1 + w, o + d * s0 + w]
        }
        for i in 0..<k {
            let r = runs[i]
            let flightRun = ((r.b - r.a) - Double(n[i] - 1) * landingLength) / Double(n[i])
            var s = r.a
            for f in 0..<n[i] {
                let dz = gradient * flightRun
                let o = r.origin + r.dir * s
                out.append(Piece(slab: SlabGeom(boundary: rect(r.origin, r.dir, s, s + flightRun), thickness: thickness, topOffset: z,
                                                slope: deg(atan(gradient)), slopeDirection: r.dir.angle, slopeOrigin: o), landing: false))
                z += dz; s += flightRun
                if f < n[i] - 1 {
                    out.append(Piece(slab: SlabGeom(boundary: rect(r.origin, r.dir, s, s + landingLength), thickness: thickness, topOffset: z), landing: true))
                    s += landingLength
                }
            }
            if i < k - 1 {
                // Corner landing centred on the turn, aligned with the incoming run.
                let c = path[i + 1]
                out.append(Piece(slab: SlabGeom(boundary: rect(c - r.dir * (width / 2), r.dir, 0, width), thickness: thickness, topOffset: z), landing: true))
            }
        }
        return out
    }
}
