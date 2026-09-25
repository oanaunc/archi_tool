// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Automatic dimension strings for walls (AUTODIMWALLS): per straight wall, a chain along its outer face through the
/// face ends and every opening edge, plus an overall dimension further out.
public enum AutoDimension {
    public struct Chain { public var wall: EntityID; public var dims: [DimensionGeom] }

    /// `outsideFrom`: point the chains face away from (default: the centroid of the walls' midpoints).
    public static func wallChains(doc: ArchiDocument, walls ids: [EntityID], offset: Double, outsideFrom: Vec2? = nil,
                                  openings: Bool = true, overall: Bool = true) -> [Chain] {
        let ctx = PlanRepresentation.context(doc)
        let frames = ids.compactMap { id -> WallFrame? in ctx.frames[id] ?? doc.element(id).flatMap { WallFrame($0) } }.filter { !$0.isCurved && $0.L > 1e-9 }
        guard !frames.isEmpty else { return [] }
        let centre = outsideFrom ?? frames.map { ($0.cs + $0.ce) / 2 }.reduce(Vec2.zero, +) / Double(frames.count)
        var out: [Chain] = []
        for f in frames {
            let d = f.dir, nL = d.perp
            let mid = (f.cs + f.ce) / 2
            // Outer side: the face farther from the centre (left when the wall passes through the centre).
            let side: Double = (mid - centre).dot(nL) >= 0 ? 1 : -1
            let nOut = nL * side
            let outline = ctx.outline(f)
            let facePts = outline.filter { ($0 - mid).dot(nOut) > f.h * 0.5 }
            let sVals = (facePts.isEmpty ? [f.cs + nOut * f.h, f.ce + nOut * f.h] : facePts).map { ($0 - f.cs).dot(d) }
            guard let sMin = sVals.min(), let sMax = sVals.max(), sMax - sMin > 1e-6 else { continue }
            var stops = [sMin, sMax]
            if openings {
                for o in ctx.openings[f.id] ?? [] {
                    guard case .opening(let og) = o.geometry else { continue }
                    stops += [og.offset - og.width / 2, og.offset + og.width / 2].filter { $0 > sMin + 1e-6 && $0 < sMax - 1e-6 }
                }
            }
            stops.sort()
            var uniq: [Double] = []
            for s in stops where uniq.last.map({ s - $0 > 1e-6 }) ?? true { uniq.append(s) }
            let faceOff = f.h                     // face of a centre-justified frame
            func P(_ s: Double, _ t: Double) -> Vec2 { f.cs + d * s + nOut * t }
            var dims: [DimensionGeom] = []
            for i in 0..<(uniq.count - 1) {
                dims.append(DimensionGeom(kind: .aligned, points: [P(uniq[i], faceOff), P(uniq[i + 1], faceOff), P((uniq[i] + uniq[i + 1]) / 2, faceOff + offset)]))
            }
            if overall && uniq.count > 2 {
                dims.append(DimensionGeom(kind: .aligned, points: [P(sMin, faceOff), P(sMax, faceOff), P((sMin + sMax) / 2, faceOff + offset * 2)]))
            }
            out.append(Chain(wall: f.id, dims: dims))
        }
        return out
    }
}
