// Oanarina Archi Tool — GPL-3.0-or-later
// Grid system generators: rectangular grids from spacing lists (BIM-007) and radial grids (BIM-006).
import Foundation

public enum GridSystems {
    /// Parses a spacing list such as "3*6000, 4500 2*3000" (units as given). nil on a malformed entry.
    public static func spacings(_ s: String) -> [Double]? {
        var out: [Double] = []
        for tok in s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) where !tok.isEmpty {
            let parts = tok.split(separator: "*")
            if parts.count == 2, let n = Int(parts[0]), let d = Double(parts[1]), n >= 1, n <= 500, d > 0 { out += Array(repeating: d, count: n) }
            else if parts.count == 1, let d = Double(parts[0]), d > 0 { out.append(d) }
            else { return nil }
        }
        return out
    }

    /// Letter label sequence (A, B, … skipping I and O, then AA, AB…).
    public static func letter(_ n0: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ").map(String.init)
        var n = n0 + 1, s = ""
        while n > 0 { let r = (n - 1) % letters.count; s = letters[r] + s; n = (n - 1) / letters.count }
        return s
    }

    /// Rectangular grid: lines across X (numbered, perpendicular to X) at the cumulative `xs` spacings and lines across Y
    /// (lettered) at the `ys` spacings, both extended by `overhang` beyond the outermost grids; rotated about `origin`.
    public static func rectangular(origin o: Vec2, xs: [Double], ys: [Double], overhang: Double, rotation: Double = 0,
                                   firstNumber: Int = 1, firstLetter: Int = 0) -> [GridLineGeom] {
        let px = [0] + xs.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1) }
        let py = [0] + ys.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1) }
        let w = px.last!, h = py.last!
        let t = Transform2D.translation(o) * Transform2D.rotation(rotation)
        var out: [GridLineGeom] = []
        for (i, x) in px.enumerated() {
            out.append(GridLineGeom(start: t.apply(Vec2(x, -overhang)), end: t.apply(Vec2(x, h + overhang)), label: "\(firstNumber + i)"))
        }
        for (j, y) in py.enumerated() {
            out.append(GridLineGeom(start: t.apply(Vec2(-overhang, y)), end: t.apply(Vec2(w + overhang, y)), label: letter(firstLetter + j)))
        }
        return out
    }

    /// Radial grid about `center`: radial lines at `startAngle` + cumulative `angles` (radians) from `innerRadius` to the
    /// outermost arc + overhang (numbered), and arc grids at `innerRadius` + cumulative `radii` spanning the radial lines
    /// plus an angular overhang (lettered). The total sweep must stay below 360°.
    public static func radial(center c: Vec2, startAngle a0: Double, angles: [Double], innerRadius r0: Double, radii: [Double], overhang: Double,
                              firstNumber: Int = 1, firstLetter: Int = 0) -> [GridLineGeom]? {
        let ang = [0] + angles.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1) }
        let rs = ([r0] + radii.reduce(into: [Double]()) { $0.append(($0.last ?? r0) + $1) }).filter { $0 > 1e-9 }
        let sweep = ang.last!
        guard let rMax = rs.max(), rMax > 1e-9 else { return nil }
        let over = overhang / rMax
        guard sweep + 2 * over < 2 * .pi - 1e-6 else { return nil }
        var out: [GridLineGeom] = []
        for (i, a) in ang.enumerated() {
            let d = Vec2.polar(1, a0 + a)
            out.append(GridLineGeom(start: c + d * max(r0, 0), end: c + d * (rMax + overhang), label: "\(firstNumber + i)"))
        }
        for (j, r) in rs.enumerated() {
            let s = a0 - over, e = a0 + sweep + over
            out.append(GridLineGeom(start: c + Vec2.polar(r, s), end: c + Vec2.polar(r, e), label: letter(firstLetter + j), bulge: tan((e - s) / 4)))
        }
        return out
    }
}
