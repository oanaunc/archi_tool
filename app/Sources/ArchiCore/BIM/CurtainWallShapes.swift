// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Curtain wall mullion types (cross-sections) and panel types.
public enum CurtainMullion {
    /// Mullion types: rectangular box, round tube, box with an exterior fin, box with an exterior pressure cap, tee.
    public static let types = ["rect", "round", "fin", "capped", "tee"]
    /// Panel types understood by the 3D builder: glass (default), solid, spandrel, louvre, empty, door, doubledoor.
    public static let panelTypes = ["glass", "solid", "spandrel", "louvre", "empty", "door", "doubledoor"]

    public static func normalized(_ t: String?) -> String {
        let k = (t ?? "rect").lowercased()
        switch k {
        case "rectangular", "box", "rect": return "rect"
        case "circular", "round", "tube": return "round"
        case "fin": return "fin"
        case "cap", "capped", "pressurecap": return "capped"
        case "tee", "t": return "tee"
        default: return "rect"
        }
    }

    /// Closed cross-section, CCW, in (a = along the member's width, b = across the wall; +b = interior / +normal side).
    /// `width` is the face width seen in elevation, `depth` the depth through the wall.
    public static func section(_ type: String?, width w0: Double, depth d0: Double) -> [Vec2] {
        let w = max(w0, 1e-3), d = max(d0, 1e-3)
        let hw = w / 2, hd = d / 2
        switch normalized(type) {
        case "round":
            let r = min(w, d) / 2
            return (0..<20).map { Vec2.polar(r, 2 * Double.pi * Double($0) / 20) }
        case "fin":
            // Box plus a narrow fin projecting to the exterior (−b).
            let f = w * 0.2, fd = d * 1.5
            return [Vec2(-hw, -hd), Vec2(-f, -hd), Vec2(-f, -hd - fd), Vec2(f, -hd - fd), Vec2(f, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd)]
        case "capped":
            // Box plus a wider pressure cap on the exterior face.
            let cw = w * 0.75, ct = max(w * 0.25, 1e-3)
            return [Vec2(-cw, -hd - ct), Vec2(cw, -hd - ct), Vec2(cw, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd), Vec2(-hw, -hd), Vec2(-cw, -hd)]
        case "tee":
            // Flange on the exterior face, stem to the interior.
            let fl = w * 0.7, ft = max(d * 0.2, 1e-3), st = w * 0.2
            return [Vec2(-fl, -hd), Vec2(fl, -hd), Vec2(fl, -hd + ft), Vec2(st, -hd + ft), Vec2(st, hd), Vec2(-st, hd), Vec2(-st, -hd + ft), Vec2(-fl, -hd + ft)]
        default:
            return [Vec2(-hw, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd)]
        }
    }

    /// Type of the mullion at grid index `i` of `count` lines (0 and count−1 are the border).
    static func type(_ g: CurtainWallGeom, border: Bool) -> String { normalized(border ? (g.borderProfile ?? g.mullionProfile) : g.mullionProfile) }
    static func depth(_ g: CurtainWallGeom) -> Double { g.mullionDepth ?? max(g.mullionSize, 1e-3) * 1.5 }

    /// Plan section of the vertical mullion at distance `x` along the wall.
    static func planSection(_ g: CurtainWallGeom, x: Double, border: Bool) -> [Vec2] {
        let len = g.length
        guard len > 1e-9 else { return [] }
        let d = (g.end - g.start) / len, n = d.perp
        var sec = section(type(g, border: border), width: g.mullionSize, depth: depth(g))
        // Border mullions stay inside the wall ends.
        if border {
            let lo = sec.map(\.x).min() ?? 0, hi = sec.map(\.x).max() ?? 0
            let shift = x <= 1e-9 ? -lo : (x >= len - 1e-9 ? -hi : 0)
            sec = sec.map { Vec2($0.x + shift, $0.y) }
        }
        return sec.map { g.start + d * (x + $0.x) + n * $0.y }
    }

    /// Louvre blades for a panel (x0…x1 along the wall, z0…z1 heights): (z bottom, z top, b offsets) per blade.
    static func louvreBlades(z0: Double, z1: Double, pitch: Double) -> [Double] {
        guard z1 - z0 > pitch * 0.5, pitch > 1e-9 else { return [] }
        var out: [Double] = []
        var z = z0 + pitch / 2
        while z < z1 - pitch * 0.25 { out.append(z); z += pitch }
        return out
    }
}

/// Corner joins of curtain walls (BIM-028): where two curtain walls on a level meet end to end at an angle, their
/// border mullions are replaced by one corner post — the convex hull of both border sections centred on the corner —
/// drawn (plan) and built (3D) once, by the wall with the lower id.
enum CurtainCorners {
    struct End { var joined = false; var post: [Vec2]? = nil }
    struct Ends { var start = End(); var end = End() }

    /// Border section centred on the wall end (not pulled inside the wall).
    static func centredSection(_ g: CurtainWallGeom, atStart: Bool) -> [Vec2] {
        let len = g.length
        guard len > 1e-9 else { return [] }
        let d = (g.end - g.start) / len, n = d.perp
        let x = atStart ? 0 : len
        return CurtainMullion.section(CurtainMullion.type(g, border: true), width: g.mullionSize, depth: CurtainMullion.depth(g)).map { g.start + d * (x + $0.x) + n * $0.y }
    }

    static func compute(_ doc: ArchiDocument) -> [EntityID: Ends] {
        let cws = doc.elements.compactMap { el -> (BIMElement, CurtainWallGeom)? in
            if case .curtainWall(let g) = el.geometry, g.length > 1e-9, el.props["hostWall"] == nil { return (el, g) }; return nil
        }
        guard cws.count >= 2 else { return [:] }
        let tol = max(1.0 / doc.units.mm, 1e-6)
        var out: [EntityID: Ends] = [:]
        for i in 0..<cws.count {
            for j in (i + 1)..<cws.count {
                let (ea, a) = cws[i], (eb, b) = cws[j]
                guard ea.level == eb.level else { continue }
                for sa in [true, false] {
                    for sb in [true, false] {
                        let pa = sa ? a.start : a.end, pb = sb ? b.start : b.end
                        guard pa.distance(to: pb) <= tol else { continue }
                        if (sa ? out[ea.id]?.start.joined : out[ea.id]?.end.joined) == true { continue }
                        if (sb ? out[eb.id]?.start.joined : out[eb.id]?.end.joined) == true { continue }
                        let da = (a.end - a.start).normalized, db = (b.end - b.start).normalized
                        guard abs(da.cross(db)) > sin(10 * Double.pi / 180) else { continue }   // (near) collinear: no corner
                        let post = RG.convexHull(centredSection(a, atStart: sa) + centredSection(b, atStart: sb))
                        guard post.count >= 3 else { continue }
                        let owner = ea.id < eb.id ? ea.id : eb.id
                        var xa = out[ea.id] ?? Ends(), xb = out[eb.id] ?? Ends()
                        let endA = End(joined: true, post: owner == ea.id ? post : nil), endB = End(joined: true, post: owner == eb.id ? post : nil)
                        if sa { xa.start = endA } else { xa.end = endA }
                        if sb { xb.start = endB } else { xb.end = endB }
                        out[ea.id] = xa; out[eb.id] = xb
                    }
                }
            }
        }
        return out
    }
}
