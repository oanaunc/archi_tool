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
