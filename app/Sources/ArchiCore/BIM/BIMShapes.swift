// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

// Shared 2D shape logic for BIM elements, used by both the plan representation and the 3D mesh builder.

/// Parametric frame of a wall's centerline: `s` = distance along the centerline, `t` = offset to the left.
struct WallFrame {
    let id: EntityID
    let level: Int
    let g: WallGeom
    let h: Double
    let cs: Vec2, ce: Vec2
    let L: Double
    let arcC: Vec2?
    let arcR: Double, arcA0: Double, arcSweep: Double

    init?(_ el: BIMElement) {
        guard case .wall(let g) = el.geometry else { return nil }
        self.init(id: el.id, level: el.level, g)
    }
    init?(id: EntityID, level: Int, _ g: WallGeom) {
        self.id = id; self.level = level; self.g = g
        h = max(g.thickness, 0) / 2
        cs = g.centerStart; ce = g.centerEnd
        let chord = cs.distance(to: ce)
        guard chord > 1e-9 else { return nil }
        if abs(g.bulge) > 1e-9 {
            let a = GeometryOps.bulgeArc(cs, ce, g.bulge)
            arcC = a.center; arcR = a.radius; arcA0 = a.start; arcSweep = a.sweep
            L = a.radius * abs(a.sweep)
        } else {
            arcC = nil; arcR = 0; arcA0 = 0; arcSweep = 0
            L = chord
        }
    }
    var isCurved: Bool { arcC != nil }
    var dir: Vec2 { (ce - cs).normalized }

    func pos(_ s: Double) -> Vec2 {
        if let c = arcC { return c + Vec2.polar(arcR, arcA0 + arcSweep * s / L) }
        return cs + dir * s
    }
    func tangent(_ s: Double) -> Vec2 {
        if arcC != nil { return Vec2.polar(1, arcA0 + arcSweep * s / L + .pi / 2) * (arcSweep >= 0 ? 1 : -1) }
        return dir
    }
    func left(_ s: Double) -> Vec2 { tangent(s).perp }
    func pt(_ s: Double, _ t: Double) -> Vec2 { pos(s) + left(s) * t }

    /// Points along the face at offset `t` from s0 to s1 (sampled for curved walls).
    func face(_ t: Double, _ s0: Double, _ s1: Double) -> [Vec2] {
        guard isCurved else { return [pt(s0, t), pt(s1, t)] }
        let r = max(arcR - t * (arcSweep >= 0 ? 1 : -1), 1e-6)
        let sweep = abs(arcSweep) * abs(s1 - s0) / L
        let n = max(1, GeometryOps.segments(radius: r, sweep: sweep))
        return (0...n).map { pt(s0 + (s1 - s0) * Double($0) / Double(n), t) }
    }

    /// Local (s, t) of a world point.
    func project(_ p: Vec2) -> (s: Double, t: Double) {
        if let c = arcC {
            let a = (p - c).angle
            var da = a - arcA0
            if arcSweep >= 0 { da = normAngle(da); if da > abs(arcSweep) + (2 * .pi - abs(arcSweep)) / 2 { da -= 2 * .pi } }
            else { da = normAngle(-da); if da > abs(arcSweep) + (2 * .pi - abs(arcSweep)) / 2 { da -= 2 * .pi } }
            let s = da * arcR
            return (s, (p - pos(s)).dot(left(s)))
        }
        let q = p - cs
        return (q.dot(dir), q.dot(dir.perp))
    }

    /// Straight-wall helper: s of a world point.
    func sOf(_ p: Vec2) -> Double { project(p).s }
}

/// Resolved end conditions of a wall in plan.
struct WallJoinInfo {
    var startL: Vec2, startR: Vec2, endL: Vec2, endR: Vec2
    var startCap = true, endCap = true
    /// Parts of the faces covered by walls T-joining into this wall: side (+1 left, −1 right), s-range.
    var gaps: [(side: Double, s0: Double, s1: Double)] = []
}

/// A solid run of wall between openings (or wall ends).
struct WallPiece {
    var poly: [Vec2]
    var faceR: [Vec2]
    var faceL: [Vec2]
    var s0: Double, s1: Double
    var startEdgeVisible: Bool, endEdgeVisible: Bool
}

/// Precomputed wall joins and hosted openings for a document (optionally one level).
final class BIMContext {
    let doc: ArchiDocument
    var frames: [EntityID: WallFrame] = [:]
    var joins: [EntityID: WallJoinInfo] = [:]
    var openings: [EntityID: [BIMElement]] = [:]
    let tol: Double

    init(doc: ArchiDocument, level: Int? = nil) {
        self.doc = doc
        tol = max(2.0 / doc.units.mm, 1e-6)
        var byLevel: [Int: [WallFrame]] = [:]
        for el in doc.elements {
            if let f = WallFrame(el), level == nil || el.level == level { frames[el.id] = f; byLevel[el.level, default: []].append(f) }
            if case .opening(let o) = el.geometry { openings[o.hostWall, default: []].append(el) }
        }
        for (_, walls) in byLevel { computeJoins(walls) }
    }

    func levelElevation(_ l: Int) -> Double { doc.level(l)?.elevation ?? 0 }

    private struct End { let f: WallFrame; let atStart: Bool
        var center: Vec2 { atStart ? f.cs : f.ce }
        var drawn: Vec2 { atStart ? f.g.start : f.g.end }
        var out: Vec2 { atStart ? f.tangent(0) : -f.tangent(f.L) }
    }

    private func computeJoins(_ walls: [WallFrame]) {
        for f in walls {
            var info = WallJoinInfo(startL: f.pt(0, f.h), startR: f.pt(0, -f.h), endL: f.pt(f.L, f.h), endR: f.pt(f.L, -f.h))
            for atStart in [true, false] {
                let me = End(f: f, atStart: atStart)
                var node = [me]
                for g in walls where g.id != f.id {
                    for gs in [true, false] {
                        let e = End(f: g, atStart: gs)
                        let d = min(e.center.distance(to: me.center), e.drawn.distance(to: me.drawn), e.center.distance(to: me.drawn), e.drawn.distance(to: me.center))
                        if d <= tol { node.append(e) }
                    }
                }
                if node.count >= 2 {
                    let sorted = node.sorted { $0.out.angle < $1.out.angle }
                    let i = sorted.firstIndex { $0.f.id == f.id && $0.atStart == atStart } ?? 0
                    let n = sorted.count
                    let j = sorted[(i + 1) % n], k = sorted[(i - 1 + n) % n]
                    let o = me.out, lo = o.perp, P = me.center
                    func corner(_ base: Vec2, _ other: End, _ otherSide: Double) -> Vec2 {
                        let ob = other.center + other.out.perp * (otherSide * other.f.h)
                        if abs(o.cross(other.out)) < 1e-6 { return base }
                        guard let x = GeometryOps.lineIntersection(base, base + o, ob, ob + other.out) else { return base }
                        if x.distance(to: P) > 8 * max(f.h, other.f.h) + tol { return base }
                        return x
                    }
                    let leftOut = corner(P + lo * f.h, j, -1)
                    let rightOut = corner(P - lo * f.h, k, 1)
                    if atStart { info.startL = leftOut; info.startR = rightOut; info.startCap = false }
                    else { info.endL = rightOut; info.endR = leftOut; info.endCap = false }
                    continue
                }
                // T-join into the side of a straight wall.
                let P = me.center, o = me.out
                var joinedCurved = false
                for b in walls where b.id != f.id && b.isCurved {
                    guard let c = b.arcC else { continue }
                    let pr = b.project(P)
                    guard pr.s > -tol, pr.s < b.L + tol, abs(pr.t) <= b.h + tol else { continue }
                    let lft = b.left(min(max(pr.s, 0), b.L))
                    guard abs(o.dot(b.tangent(min(max(pr.s, 0), b.L)))) < 0.985 else { continue }
                    var side: Double = o.dot(lft) >= 0 ? 1 : -1
                    if abs(o.dot(lft)) < 1e-9 { side = pr.t >= 0 ? 1 : -1 }
                    let r = max(b.arcR - side * b.h * (b.arcSweep >= 0 ? 1 : -1), 1e-6)
                    let sEnd = atStart ? 0 : f.L
                    let tan = f.tangent(sEnd)
                    func hit(_ q: Vec2) -> Vec2? {
                        // Line q + λ·tan against the face circle; the intersection nearest to the join point.
                        let d = q - c
                        let bq = d.dot(tan), cq = d.lengthSquared - r * r
                        let disc = bq * bq - cq
                        guard disc >= 0 else { return nil }
                        let s1 = -bq - disc.squareRoot(), s2 = -bq + disc.squareRoot()
                        let p1 = q + tan * s1, p2 = q + tan * s2
                        return p1.distance(to: P) <= p2.distance(to: P) ? p1 : p2
                    }
                    guard let cl = hit(f.pt(sEnd, f.h)), let cr = hit(f.pt(sEnd, -f.h)),
                          cl.distance(to: P) < 8 * max(f.h, b.h) + tol, cr.distance(to: P) < 8 * max(f.h, b.h) + tol else { continue }
                    if atStart { info.startL = cl; info.startR = cr; info.startCap = false }
                    else { info.endL = cl; info.endR = cr; info.endCap = false }
                    let s0 = b.project(cl).s, s1 = b.project(cr).s
                    var bi = joins[b.id] ?? WallJoinInfo(startL: b.pt(0, b.h), startR: b.pt(0, -b.h), endL: b.pt(b.L, b.h), endR: b.pt(b.L, -b.h))
                    bi.gaps.append((side, min(s0, s1), max(s0, s1)))
                    joins[b.id] = bi
                    joinedCurved = true
                    break
                }
                if joinedCurved { continue }
                for b in walls where b.id != f.id && !b.isCurved {
                    let q = P - b.cs
                    let u = q.dot(b.dir), tp = q.dot(b.dir.perp)
                    guard u > -tol, u < b.L + tol, abs(tp) <= b.h + tol, abs(o.dot(b.dir)) < 0.985 else { continue }
                    var side: Double = o.dot(b.dir.perp) >= 0 ? 1 : -1
                    if abs(o.dot(b.dir.perp)) < 1e-9 { side = tp >= 0 ? 1 : -1 }
                    let fq = b.cs + b.dir.perp * (side * b.h)
                    let sEnd = atStart ? 0 : f.L
                    let tan = f.tangent(sEnd)
                    guard let cl = GeometryOps.lineIntersection(f.pt(sEnd, f.h), f.pt(sEnd, f.h) + tan, fq, fq + b.dir),
                          let cr = GeometryOps.lineIntersection(f.pt(sEnd, -f.h), f.pt(sEnd, -f.h) + tan, fq, fq + b.dir),
                          cl.distance(to: P) < 8 * max(f.h, b.h) + tol, cr.distance(to: P) < 8 * max(f.h, b.h) + tol else { continue }
                    if atStart { info.startL = cl; info.startR = cr; info.startCap = false }
                    else { info.endL = cl; info.endR = cr; info.endCap = false }
                    let s0 = (cl - b.cs).dot(b.dir), s1 = (cr - b.cs).dot(b.dir)
                    var bi = joins[b.id] ?? WallJoinInfo(startL: b.pt(0, b.h), startR: b.pt(0, -b.h), endL: b.pt(b.L, b.h), endR: b.pt(b.L, -b.h))
                    bi.gaps.append((side, min(s0, s1), max(s0, s1)))
                    joins[b.id] = bi
                    break
                }
            }
            // Keep gaps that other walls may already have registered.
            if let existing = joins[f.id] { info.gaps = existing.gaps }
            joins[f.id] = info
        }
    }

    func join(_ f: WallFrame) -> WallJoinInfo {
        joins[f.id] ?? WallJoinInfo(startL: f.pt(0, f.h), startR: f.pt(0, -f.h), endL: f.pt(f.L, f.h), endR: f.pt(f.L, -f.h))
    }

    /// Opening cut intervals along the wall, clamped and merged, with the openings they contain.
    func cuts(_ f: WallFrame, only: Set<EntityID>? = nil) -> [(s0: Double, s1: Double, els: [BIMElement])] {
        let j = join(f)
        let sMin = f.isCurved ? 0 : max(f.sOf(j.startL), f.sOf(j.startR), 0) + 1e-6
        let sMax = f.isCurved ? f.L : min(f.sOf(j.endL), f.sOf(j.endR), f.L) - 1e-6
        var raw: [(Double, Double, BIMElement)] = []
        for el in openings[f.id] ?? [] {
            if let only = only, !only.contains(el.id) { continue }
            guard case .opening(let o) = el.geometry, o.width > 0 else { continue }
            let a = max(o.offset - o.width / 2, sMin), b = min(o.offset + o.width / 2, sMax)
            if b - a > 1e-6 { raw.append((a, b, el)) }
        }
        raw.sort { $0.0 < $1.0 }
        var out: [(s0: Double, s1: Double, els: [BIMElement])] = []
        for r in raw {
            if let last = out.last, r.0 <= last.s1 + 1e-9 {
                out[out.count - 1].s1 = max(last.s1, r.1); out[out.count - 1].els.append(r.2)
            } else { out.append((r.0, r.1, [r.2])) }
        }
        return out
    }

    /// Solid pieces of the wall between openings, with mitred/trimmed ends.
    func pieces(_ f: WallFrame, only: Set<EntityID>? = nil) -> [WallPiece] {
        let j = join(f)
        let c = cuts(f, only: only)
        var segs: [(a: Double, aCut: Bool, b: Double, bCut: Bool)] = []
        var cur: (Double, Bool) = (0, false)
        for k in c { segs.append((cur.0, cur.1, k.s0, true)); cur = (k.s1, true) }
        segs.append((cur.0, cur.1, f.L, false))
        var out: [WallPiece] = []
        for s in segs {
            if s.aCut && s.bCut && s.b - s.a < 1e-6 { continue }
            var fr = f.face(-f.h, s.a, s.b), fl = f.face(f.h, s.a, s.b)
            if !s.aCut { fr[0] = j.startR; fl[0] = j.startL }
            if !s.bCut { fr[fr.count - 1] = j.endR; fl[fl.count - 1] = j.endL }
            if s.aCut != s.bCut || s.aCut {
                // Skip slivers produced when an opening reaches into the mitre zone.
                if fr.first!.distance(to: fr.last!) < 1e-6 && fl.first!.distance(to: fl.last!) < 1e-6 { continue }
            }
            let poly = RG.dedupe(fr + fl.reversed(), closed: true)
            guard poly.count >= 3 else { continue }
            out.append(WallPiece(poly: poly, faceR: fr, faceL: fl, s0: s.a, s1: s.b,
                                 startEdgeVisible: s.aCut || j.startCap, endEdgeVisible: s.bCut || j.endCap))
        }
        return out
    }

    /// Full mitred outline (ignoring openings).
    func outline(_ f: WallFrame) -> [Vec2] {
        let j = join(f)
        var fr = f.face(-f.h, 0, f.L), fl = f.face(f.h, 0, f.L)
        fr[0] = j.startR; fl[0] = j.startL; fr[fr.count - 1] = j.endR; fl[fl.count - 1] = j.endL
        return RG.dedupe(fr + fl.reversed(), closed: true)
    }
}

// MARK: - Stairs

struct StairTread { var poly: [Vec2]; var step: Int; var landing: Bool }
struct StairLayout {
    var treads: [StairTread]
    var walk: [Vec2]
    /// Flights as (start point, direction, tread count, width) for stringers.
    var flights: [(origin: Vec2, dir: Vec2, count: Int, firstStep: Int)]
}

enum StairShapes {
    /// `start` is the midpoint of the first (bottom) riser; `direction` is the walking direction.
    static func layout(_ g: StairGeom) -> StairLayout {
        let n = max(g.riserCount - 1, 1)
        let td = max(g.treadDepth, 1e-3), w = max(g.width, 1e-3)
        let d = Vec2.polar(1, g.direction), p = d.perp
        let o = g.start
        func rect(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> [Vec2] {
            [o + d * x0 + p * y0, o + d * x1 + p * y0, o + d * x1 + p * y1, o + d * x0 + p * y1]
        }
        var treads: [StairTread] = []
        var walk: [Vec2] = []
        var flights: [(Vec2, Vec2, Int, Int)] = []
        switch g.kind {
        case .straight:
            if let k = g.landingAt, k >= 2, k <= n {
                // Two flights with an intermediate landing (the landing is step k).
                let ld = max(g.landingDepth ?? w, td)
                let n1 = k - 1, n2 = max(n - k, 0)
                let x1 = Double(n1) * td
                for i in 0..<n1 { treads.append(StairTread(poly: rect(Double(i) * td, Double(i + 1) * td, -w / 2, w / 2), step: i + 1, landing: false)) }
                treads.append(StairTread(poly: rect(x1, x1 + ld, -w / 2, w / 2), step: k, landing: true))
                for i in 0..<n2 { let x = x1 + ld + Double(i) * td; treads.append(StairTread(poly: rect(x, x + td, -w / 2, w / 2), step: k + 1 + i, landing: false)) }
                walk = [o, o + d * (x1 + ld + Double(n2) * td)]
                flights = [(o, d, n1, 1), (o + d * (x1 + ld), d, n2, k + 1)]
                break
            }
            for i in 0..<n { treads.append(StairTread(poly: rect(Double(i) * td, Double(i + 1) * td, -w / 2, w / 2), step: i + 1, landing: false)) }
            walk = [o, o + d * (Double(n) * td)]
            flights = [(o, d, n, 1)]
        case .lShape, .uShape:
            let n1 = min(max((g.landingAt.map { $0 - 1 }) ?? n / 2, 0), max(n - 1, 0)), n2 = max(n - n1 - 1, 0)
            let x1 = Double(n1) * td
            for i in 0..<n1 { treads.append(StairTread(poly: rect(Double(i) * td, Double(i + 1) * td, -w / 2, w / 2), step: i + 1, landing: false)) }
            flights.append((o, d, n1, 1))
            if g.kind == .lShape {
                treads.append(StairTread(poly: rect(x1, x1 + w, -w / 2, w / 2), step: n1 + 1, landing: true))
                let xc = x1 + w / 2
                for jx in 0..<n2 {
                    let y0 = w / 2 + Double(jx) * td
                    treads.append(StairTread(poly: rect(xc - w / 2, xc + w / 2, y0, y0 + td), step: n1 + 2 + jx, landing: false))
                }
                walk = [o, o + d * xc, o + d * xc + p * (w / 2 + Double(n2) * td)]
                flights.append((o + d * xc + p * (w / 2), p, n2, n1 + 2))
            } else {
                let gap = min(100, w * 0.1)
                let ld = max(g.landingDepth ?? w, td)
                treads.append(StairTread(poly: rect(x1, x1 + ld, -w / 2, 1.5 * w + gap), step: n1 + 1, landing: true))
                for jx in 0..<n2 {
                    let xa = x1 - Double(jx) * td
                    treads.append(StairTread(poly: rect(xa - td, xa, w / 2 + gap, 1.5 * w + gap), step: n1 + 2 + jx, landing: false))
                }
                let yc = w + gap
                walk = [o, o + d * (x1 + ld / 2), o + d * (x1 + ld / 2) + p * yc, o + d * (x1 - Double(n2) * td) + p * yc]
                flights.append((o + d * x1 + p * yc, -d, n2, n1 + 2))
            }
        case .spiral:
            let r0 = max(100, w * 0.15), r1 = r0 + w, rw = r0 + w / 2
            let dt = td / rw
            for i in 0..<n {
                let a0 = g.direction + Double(i) * dt
                var poly = [o + Vec2.polar(r0, a0)]
                poly += GeometryOps.arcPoints(center: o, radius: r1, start: a0, sweep: dt)
                poly.append(o + Vec2.polar(r0, a0 + dt))
                treads.append(StairTread(poly: poly, step: i + 1, landing: false))
            }
            walk = GeometryOps.arcPoints(center: o, radius: rw, start: g.direction, sweep: dt * Double(n))
        }
        return StairLayout(treads: treads, walk: walk, flights: flights.map { (origin: $0.0, dir: $0.1, count: $0.2, firstStep: $0.3) })
    }
}

// MARK: - Roofs

struct RoofFace { var poly: [Vec2]; var grad: Vec2; var c: Double
    /// Height of the roof underside above the eave level at a plan point.
    func height(_ p: Vec2) -> Double { grad.dot(p) + c }
}

enum RoofShapes {
    /// Eave-line footprint (CCW), overhang footprint and roof faces as planar height functions.
    static func faces(_ g: RoofGeom) -> (boundary: [Vec2], footprint: [Vec2], faces: [RoofFace]) {
        var b = RG.dedupe(g.boundary, closed: true)
        guard b.count >= 3, abs(GeometryOps.signedArea(b)) > 1e-9 else { return (b, b, []) }
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        var eave = g.eaveEdge
        if GeometryOps.signedArea(g.boundary) < 0 { eave = b.count - 2 - eave } // edge index after reversal
        eave = ((eave % b.count) + b.count) % b.count
        var fp = g.overhang > 0 ? RG.offsetPolygon(b, g.overhang) : b
        let k = tan(rad(max(0, min(g.pitch, 89))))
        if g.kind == .hip && !RG.isConvex(b) {
            // Non-convex footprint: straight-skeleton faces of the overhang outline, heights measured from the eave line.
            var out: [RoofFace] = []
            var f = RG.dedupe(fp, closed: true)
            if GeometryOps.signedArea(f) < 0 { f.reverse() }
            for face in StraightSkeleton.faces(f) {
                let a = f[face.edge], c = f[(face.edge + 1) % f.count]
                let n = (c - a).normalized.perp
                out.append(RoofFace(poly: face.poly, grad: n * k, c: -k * a.dot(n) - k * max(g.overhang, 0)))
            }
            if !out.isEmpty { return (b, fp, out) }
            b = RG.convexHull(b); eave = eave % b.count
            fp = g.overhang > 0 ? RG.offsetPolygon(b, g.overhang) : b
        }
        func edgeFn(_ i: Int) -> RoofFace {
            let a = b[i], c = b[(i + 1) % b.count]
            let n = (c - a).normalized.perp
            return RoofFace(poly: [], grad: n * k, c: -k * a.dot(n))
        }
        var fns: [RoofFace]
        switch g.kind {
        case .flat: return (b, fp, [RoofFace(poly: fp, grad: .zero, c: 0)])
        case .shed: fns = [edgeFn(eave)]
        case .gable:
            let e = edgeFn(eave)
            let depth = b.map { e.height($0) }.max() ?? 0
            fns = [e, RoofFace(poly: [], grad: -e.grad, c: depth - e.c)]
        case .hip: fns = (0..<b.count).map(edgeFn)
        }
        var out: [RoofFace] = []
        for (i, f) in fns.enumerated() {
            var poly = fp
            for (j, o) in fns.enumerated() where j != i {
                let n = f.grad - o.grad
                if n.length < 1e-12 { if j < i { poly = [] }; continue }
                poly = RG.clipHalfPlane(poly, normal: n, o.c - f.c)
                if poly.count < 3 { break }
            }
            if poly.count >= 3, abs(GeometryOps.signedArea(poly)) > 1e-6 { out.append(RoofFace(poly: poly, grad: f.grad, c: f.c)) }
        }
        return (b, fp, out)
    }

    /// Whether segment a–b lies on the polygon outline.
    static func onOutline(_ a: Vec2, _ b: Vec2, _ poly: [Vec2], tol: Double) -> Bool {
        let m = (a + b) / 2
        return GeometryOps.distance(from: m, toPolyline: poly + [poly[0]]) < tol
            && GeometryOps.distance(from: a, toPolyline: poly + [poly[0]]) < tol
            && GeometryOps.distance(from: b, toPolyline: poly + [poly[0]]) < tol
    }
}
