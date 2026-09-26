// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// SketchUp-style inference guides (PRC-027): while drawing from a base point, the cursor locks onto the UCS axes
/// ("on red / green axis"), onto directions parallel or perpendicular to a reference edge, and onto lines through
/// acquired points aligned with the axes ("from point"). Returns the exact aligned point and the guide lines to draw.
public enum AlignmentGuides {
    public enum Kind: String { case onAxisX, onAxisY, parallel, perpendicular, fromPoint }
    public struct Guide: Hashable { public var kind: Kind; public var from: Vec2; public var to: Vec2 }
    public struct Result { public var point: Vec2; public var guides: [Guide] }

    /// `tolerance` is the capture distance (drawing units) of the cursor from a guide line.
    public static func infer(cursor: Vec2, base: Vec2?, ucsAngle: Double = 0, reference: Vec2? = nil, points: [Vec2] = [], tolerance: Double) -> Result? {
        let ax = Vec2.polar(1, ucsAngle), ay = ax.perp
        var lines: [(Kind, Vec2, Vec2)] = []                  // (kind, origin, unit direction)
        if let b = base {
            lines.append((.onAxisX, b, ax)); lines.append((.onAxisY, b, ay))
            if let r = reference?.normalized, r != .zero {
                if abs(r.cross(ax)) > 1e-9 && abs(r.cross(ay)) > 1e-9 { lines.append((.parallel, b, r)); lines.append((.perpendicular, b, r.perp)) }
            }
        }
        for p in points where base.map({ !$0.isClose(p, tol: 1e-9) }) ?? true { lines.append((.fromPoint, p, ax)); lines.append((.fromPoint, p, ay)) }
        func foot(_ l: (Kind, Vec2, Vec2)) -> Vec2 { l.1 + l.2 * (cursor - l.1).dot(l.2) }
        let near = lines.map { ($0, foot($0)) }.filter { $0.1.distance(to: cursor) <= tolerance }
        guard !near.isEmpty else { return nil }
        // Two guides captured: their intersection; else the nearest guide's foot.
        let sorted = near.sorted { $0.1.distance(to: cursor) < $1.1.distance(to: cursor) }
        let a = sorted[0]
        for b in sorted.dropFirst() where abs(a.0.2.cross(b.0.2)) > 1e-9 {
            let d = b.0.1 - a.0.1
            let t = d.cross(b.0.2) / a.0.2.cross(b.0.2)
            let x = a.0.1 + a.0.2 * t
            if x.distance(to: cursor) <= tolerance * 1.5 {
                return Result(point: x, guides: [Guide(kind: a.0.0, from: a.0.1, to: x), Guide(kind: b.0.0, from: b.0.1, to: x)])
            }
        }
        return Result(point: a.1, guides: [Guide(kind: a.0.0, from: a.0.1, to: a.1)])
    }
}
