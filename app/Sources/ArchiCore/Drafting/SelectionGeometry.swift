// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Polygon and fence selection (WP, CP, F).
public enum SelectionGeometry {
    public enum Mode { case windowPolygon, crossingPolygon, fence }

    static func segmentsCross(_ a: [Vec2], _ b: [Vec2], closedB: Bool) -> Bool {
        guard a.count >= 2, b.count >= 2 else { return false }
        let bn = closedB ? b.count : b.count - 1
        for i in 0..<(a.count - 1) {
            for j in 0..<bn where GeometryOps.segmentIntersection(a[i], a[i + 1], b[j], b[(j + 1) % b.count]) != nil { return true }
        }
        return false
    }

    /// Whether a set of polylines (an object's tessellation) is selected by the polygon / fence.
    public static func hits(_ pls: [[Vec2]], polygon: [Vec2], mode: Mode) -> Bool {
        let pts = pls.flatMap { $0 }
        guard !pts.isEmpty else { return false }
        switch mode {
        case .windowPolygon:
            guard polygon.count >= 3 else { return false }
            return pts.allSatisfy { GeometryOps.pointInPolygon($0, polygon) } && !pls.contains { segmentsCross($0, polygon, closedB: true) }
        case .crossingPolygon:
            guard polygon.count >= 3 else { return false }
            return pts.contains { GeometryOps.pointInPolygon($0, polygon) } || pls.contains { segmentsCross($0, polygon, closedB: true) }
                || pls.contains { $0.count >= 3 && GeometryOps.pointInPolygon(polygon[0], $0) && $0.first!.isClose($0.last!, tol: 1e-9) }
        case .fence:
            guard polygon.count >= 2 else { return false }
            return pls.contains { segmentsCross($0, polygon, closedB: false) }
        }
    }

    public static func select(doc: ArchiDocument, polygon: [Vec2], mode: Mode, level: Int) -> [EntityID] {
        var out: [EntityID] = []
        let f = PickFilter(doc)
        for e in doc.entities where f.pickable(e) {
            var pls = GeometryOps.tessellate(e.geometry, doc: doc)
            if pls.allSatisfy({ $0.count < 2 }), let p = pls.first?.first { pls = [[p, p]] }
            if hits(pls, polygon: polygon, mode: mode) { out.append(e.id) }
        }
        for el in doc.elements where f.pickable(el) && el.level == level {
            let f = CommandHelpers.footprint(el, doc: doc)
            guard f.count >= 2 else { continue }
            if hits([f + [f[0]]], polygon: polygon, mode: mode) { out.append(el.id) }
        }
        return out
    }

    // MARK: Lasso (SEL-007)

    /// Lasso drag direction: a counter-clockwise loop selects by crossing, a clockwise loop by window (as a window drawn
    /// left-to-right vs right-to-left). Nil for degenerate loops.
    public static func lassoMode(_ loop: [Vec2]) -> Mode? {
        guard loop.count >= 3 else { return nil }
        let a = GeometryOps.signedArea(loop)
        guard abs(a) > 1e-12 else { return nil }
        return a > 0 ? .crossingPolygon : .windowPolygon
    }
}

