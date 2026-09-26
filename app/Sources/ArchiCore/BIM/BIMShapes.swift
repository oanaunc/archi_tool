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
    /// Curtain wall corner joins (BIM-028).
    let curtainCorners: [EntityID: CurtainCorners.Ends]

    /// Join overrides per wall end (props "joinStart"/"joinEnd"): miter (default), butt, square, none.
    var joinModes: [EntityID: (start: String, end: String)] = [:]

    init(doc: ArchiDocument, level: Int? = nil) {
        self.doc = doc
        tol = max(2.0 / doc.units.mm, 1e-6)
        curtainCorners = CurtainCorners.compute(doc)
        var byLevel: [Int: [WallFrame]] = [:]
        for el in doc.elements {
            if let f = WallFrame(el), level == nil || el.level == level {
                frames[el.id] = f; byLevel[el.level, default: []].append(f)
                let a = el.props["joinStart"]?.lowercased() ?? "", b = el.props["joinEnd"]?.lowercased() ?? ""
                if !a.isEmpty || !b.isEmpty { joinModes[el.id] = (a, b) }
            }
            if case .opening(let o) = el.geometry { openings[o.hostWall, default: []].append(el) }
        }
        // Curtain walls embedded in a host wall (props hostWall, BIM-028) cut it like a full-size opening.
        for el in doc.elements {
            guard case .curtainWall(let cw) = el.geometry, let hs = el.props["hostWall"], let hid = Int(hs), let f = frames[hid],
                  let host = doc.element(hid), cw.length > 1e-9 else { continue }
            let a = f.project(cw.start).s, b = f.project(cw.end).s
            let lo = max(min(a, b), 0), hi = min(max(a, b), f.L)
            guard hi - lo > 1e-6 else { continue }
            let sill = (doc.level(el.level)?.elevation ?? 0) + cw.baseOffset - BIMConstraints.wallNominalBase(host, doc: doc)
            let o = OpeningGeom(kind: .opening, hostWall: hid, offset: (lo + hi) / 2, width: hi - lo, height: cw.height, sill: sill)
            openings[hid, default: []].append(BIMElement(id: el.id, level: host.level, name: el.name, layer: el.layer, geometry: .opening(o), props: ["embeddedCurtainWall": "1"]))
        }
        // Parts of a divided wall (BIM-127) are cut by the host's openings (as plain openings; the host draws the doors).
        for el in doc.elements {
            guard let hs = el.props["partOf"], let hid = Int(hs), frames[el.id] != nil, let hostOpenings = openings[hid] else { continue }
            for o in hostOpenings {
                guard case .opening(var og) = o.geometry else { continue }
                og.kind = .opening; og.depth = 0; og.hostWall = el.id
                openings[el.id, default: []].append(BIMElement(id: o.id, level: el.level, name: o.name, layer: o.layer, geometry: .opening(og), props: ["partCut": "1"]))
            }
        }
        for (_, walls) in byLevel { computeJoins(walls.filter { doc.element($0.id)?.props["hasParts"] != "1" }) }
    }

    func levelElevation(_ l: Int) -> Double { doc.level(l)?.elevation ?? 0 }

    func joinMode(_ id: EntityID, atStart: Bool) -> String {
        guard let m = joinModes[id] else { return "" }
        return atStart ? m.start : m.end
    }

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
                let myMode = joinMode(f.id, atStart: atStart)
                var node = [me]
                for g in walls where g.id != f.id {
                    for gs in [true, false] {
                        let e = End(f: g, atStart: gs)
                        let d = min(e.center.distance(to: me.center), e.drawn.distance(to: me.drawn), e.center.distance(to: me.drawn), e.drawn.distance(to: me.center))
                        if d <= tol && joinMode(g.id, atStart: gs) != "none" { node.append(e) }
                    }
                }
                // Disallowed join: the end stays square and uncleaned.
                if myMode == "none" { continue }
                if node.count >= 2 && myMode == "square" {
                    // Square-off: a square end extended to cover the other walls at the corner.
                    let ext = node.dropFirst().map { $0.f.h }.max() ?? 0
                    let s0 = atStart ? -ext : f.L + ext
                    if atStart { info.startL = f.pt(s0, f.h); info.startR = f.pt(s0, -f.h) } else { info.endL = f.pt(s0, f.h); info.endR = f.pt(s0, -f.h) }
                    continue
                }
                if node.count == 2 {
                    let other = node[1]
                    let otherMode = joinMode(other.f.id, atStart: other.atStart)
                    if otherMode == "square" { continue }   // the other wall squares off over this end: keep it square
                    if myMode == "butt" || otherMode == "butt", abs(me.out.cross(other.out)) > 1e-6 {
                        let P = me.center, o = me.out
                        let sEnd = atStart ? 0 : f.L
                        func hit(_ t: Double, _ lineP: Vec2, _ lineD: Vec2) -> Vec2 {
                            GeometryOps.lineIntersection(f.pt(sEnd, t), f.pt(sEnd, t) + o, lineP, lineP + lineD) ?? f.pt(sEnd, t)
                        }
                        // Near face of the other wall (on this wall's side) or its far face (when the other wall butts into this one).
                        let side: Double = o.dot(other.out.perp) >= 0 ? 1 : -1
                        let s = myMode == "butt" ? side : -side
                        let face = other.center + other.out.perp * (s * other.f.h)
                        let L = hit(f.h, face, other.out), R = hit(-f.h, face, other.out)
                        if L.distance(to: P) < 8 * max(f.h, other.f.h) + tol && R.distance(to: P) < 8 * max(f.h, other.f.h) + tol {
                            let cap = myMode != "butt"
                            if myMode == "butt" {
                                // The butting end covers part of the other wall's face: no face line there.
                                let gs = other.atStart ? s : -s
                                let a = other.f.project(L).s, b = other.f.project(R).s
                                var bi = joins[other.f.id] ?? WallJoinInfo(startL: other.f.pt(0, other.f.h), startR: other.f.pt(0, -other.f.h), endL: other.f.pt(other.f.L, other.f.h), endR: other.f.pt(other.f.L, -other.f.h))
                                bi.gaps.append((gs, min(a, b), max(a, b)))
                                joins[other.f.id] = bi
                            }
                            if atStart { info.startL = L; info.startR = R; info.startCap = cap }
                            else { info.endL = L; info.endR = R; info.endCap = cap }
                            continue
                        }
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
                func disallowed(_ b: WallFrame) -> Bool {
                    (b.cs.distance(to: P) <= tol && joinMode(b.id, atStart: true) == "none") || (b.ce.distance(to: P) <= tol && joinMode(b.id, atStart: false) == "none")
                }
                for b in walls where b.id != f.id && b.isCurved && !disallowed(b) {
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
                for b in walls where b.id != f.id && !b.isCurved && !disallowed(b) {
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
            // Corner windows (BIM-041) cut through the wall end, mitre zone included.
            let (ra, rb) = CornerWindows.range(el, o, f)
            let a = max(ra, ra < -1e-9 ? ra : sMin), b = min(rb, rb > f.L + 1e-9 ? rb : sMax)
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
            // A corner window cutting through the wall end leaves no end piece.
            if s.aCut && !s.bCut && s.a >= f.L - 1e-6 { continue }
            if !s.aCut && s.bCut && s.b <= 1e-6 { continue }
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

struct StairTread { var poly: [Vec2]; var step: Int; var landing: Bool; var winder: Bool = false }
struct StairLayout {
    var treads: [StairTread]
    var walk: [Vec2]
    /// Flights as (start point, direction, tread count, width) for stringers.
    var flights: [(origin: Vec2, dir: Vec2, count: Int, firstStep: Int)]
    /// Newel posts (winder pivots) in plan.
    var newels: [Vec2] = []
}

enum StairShapes {
    /// `start` is the midpoint of the first (bottom) riser; `direction` is the walking direction.
    static func layout(_ g: StairGeom) -> StairLayout {
        if let sk = g.sketchRisers, let l = Round7Shapes.sketchLayout(sk) { return l }
        let n = max(g.riserCount - 1, 1)
        let td = max(g.treadDepth, 1e-3), w = max(g.width, 1e-3)
        let d = Vec2.polar(1, g.direction), p = g.turnsRight ? -d.perp : d.perp
        let o = g.start
        func rect(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> [Vec2] {
            [o + d * x0 + p * y0, o + d * x1 + p * y0, o + d * x1 + p * y1, o + d * x0 + p * y1]
        }
        func L(_ x: Double, _ y: Double) -> Vec2 { o + d * x + p * y }
        let turn: Double = g.turnsRight ? -1 : 1
        var treads: [StairTread] = []
        var walk: [Vec2] = []
        var flights: [(Vec2, Vec2, Int, Int)] = []
        var newels: [Vec2] = []
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
            let k = min(g.winderCount, n)
            let n1: Int
            if k > 0 { n1 = min(max((g.landingAt.map { $0 - 1 }) ?? (n - k) / 2, 0), max(n - k, 0)) }
            else { n1 = min(max((g.landingAt.map { $0 - 1 }) ?? n / 2, 0), max(n - 1, 0)) }
            let n2 = k > 0 ? max(n - n1 - k, 0) : max(n - n1 - 1, 0)
            let x1 = Double(n1) * td
            for i in 0..<n1 { treads.append(StairTread(poly: rect(Double(i) * td, Double(i + 1) * td, -w / 2, w / 2), step: i + 1, landing: false)) }
            flights.append((o, d, n1, 1))
            let afterTurn = k > 0 ? n1 + k + 1 : n1 + 2
            if g.kind == .lShape {
                if k > 0 {
                    let pivot = L(x1, w / 2)
                    let outer = [L(x1, -w / 2), L(x1 + w, -w / 2), L(x1 + w, w / 2)]
                    let a0 = (-p).angle, sweep = turn * Double.pi / 2
                    for (j, poly) in fan(pivot: pivot, outer: outer, count: k, a0: a0, sweep: sweep).enumerated() {
                        treads.append(StairTread(poly: poly, step: n1 + 1 + j, landing: false, winder: true))
                    }
                    newels.append(pivot)
                    walk = [o, L(x1, 0)] + Array(GeometryOps.arcPoints(center: pivot, radius: w / 2, start: a0, sweep: sweep).dropFirst())
                } else {
                    treads.append(StairTread(poly: rect(x1, x1 + w, -w / 2, w / 2), step: n1 + 1, landing: true))
                    walk = [o, L(x1 + w / 2, 0)]
                }
                let xc = x1 + w / 2
                for jx in 0..<n2 {
                    let y0 = w / 2 + Double(jx) * td
                    treads.append(StairTread(poly: rect(xc - w / 2, xc + w / 2, y0, y0 + td), step: afterTurn + jx, landing: false))
                }
                walk.append(L(xc, w / 2 + Double(n2) * td))
                flights.append((L(xc, w / 2), p, n2, afterTurn))
            } else {
                let gap = min(100, w * 0.1)
                let ld = max(g.landingDepth ?? w, td)
                let yc = w + gap
                if k > 0 {
                    let pivot = L(x1, w / 2 + gap / 2)
                    let outer = [L(x1, -w / 2), L(x1 + ld, -w / 2), L(x1 + ld, 1.5 * w + gap), L(x1, 1.5 * w + gap)]
                    let a0 = (-p).angle, sweep = turn * Double.pi
                    for (j, poly) in fan(pivot: pivot, outer: outer, count: k, a0: a0, sweep: sweep).enumerated() {
                        treads.append(StairTread(poly: poly, step: n1 + 1 + j, landing: false, winder: true))
                    }
                    newels.append(pivot)
                    walk = [o, L(x1, 0)] + Array(GeometryOps.arcPoints(center: pivot, radius: w / 2 + gap / 2, start: a0, sweep: sweep).dropFirst())
                } else {
                    treads.append(StairTread(poly: rect(x1, x1 + ld, -w / 2, 1.5 * w + gap), step: n1 + 1, landing: true))
                    walk = [o, L(x1 + ld / 2, 0), L(x1 + ld / 2, yc)]
                }
                for jx in 0..<n2 {
                    let xa = x1 - Double(jx) * td
                    treads.append(StairTread(poly: rect(xa - td, xa, w / 2 + gap, 1.5 * w + gap), step: afterTurn + jx, landing: false))
                }
                walk.append(L(x1 - Double(n2) * td, yc))
                flights.append((L(x1, yc), -d, n2, afterTurn))
            }
        case .spiral:
            let r0 = g.spiralInnerRadius, r1 = r0 + w, rw = r0 + w / 2
            let dt = turn * td / rw
            for i in 0..<n {
                let a0 = g.direction + Double(i) * dt
                var poly = [o + Vec2.polar(r0, a0)]
                poly += GeometryOps.arcPoints(center: o, radius: r1, start: a0, sweep: dt)
                poly.append(o + Vec2.polar(r0, a0 + dt))
                treads.append(StairTread(poly: poly, step: i + 1, landing: false))
            }
            walk = GeometryOps.arcPoints(center: o, radius: rw, start: g.direction, sweep: dt * Double(n))
        }
        var l = StairLayout(treads: treads, walk: walk, flights: flights.map { (origin: $0.0, dir: $0.1, count: $0.2, firstStep: $0.3) })
        l.newels = newels
        return l
    }

    /// Winder treads fanning from `pivot`: rays at equal angles from `a0` over `sweep` cut the outer boundary path;
    /// each tread is the pivot, its two ray hits and the outer corners between them.
    static func fan(pivot: Vec2, outer: [Vec2], count k: Int, a0: Double, sweep: Double) -> [[Vec2]] {
        guard k >= 1, outer.count >= 2 else { return [] }
        // Parametric hit of a ray on the outer path: (segment index + fraction).
        func hit(_ a: Double) -> Double? {
            let dir = Vec2.polar(1, a)
            var best: (t: Double, r: Double)? = nil
            for i in 0..<(outer.count - 1) {
                let p0 = outer[i], p1 = outer[i + 1], e = p1 - p0
                let den = dir.cross(e)
                guard abs(den) > 1e-12 else { continue }
                let w0 = p0 - pivot
                let r = w0.cross(e) / den, s = w0.cross(dir) / den
                guard r > 1e-9, s >= -1e-9, s <= 1 + 1e-9 else { continue }
                if best == nil || r < best!.r { best = (Double(i) + min(max(s, 0), 1), r) }
            }
            return best?.t
        }
        func point(_ t: Double) -> Vec2 {
            let i = min(Int(t), outer.count - 2)
            return outer[i].lerp(outer[i + 1], t - Double(i))
        }
        var ts: [Double] = []
        for j in 0...k {
            if j == 0 { ts.append(0); continue }
            if j == k { ts.append(Double(outer.count - 1)); continue }
            guard let t = hit(a0 + sweep * Double(j) / Double(k)) else { return [] }
            ts.append(t)
        }
        var out: [[Vec2]] = []
        for j in 0..<k {
            let ta = ts[j], tb = ts[j + 1]
            var poly = [pivot, point(ta)]
            var v = Int(ta.rounded(.down)) + 1
            while Double(v) < tb - 1e-9 { if Double(v) > ta + 1e-9 { poly.append(outer[v]) }; v += 1 }
            poly.append(point(tb))
            out.append(RG.dedupe(poly, closed: true))
        }
        return out
    }

    /// Going of winder treads measured on the walk line (centre of the flight width).
    static func winderWalkGoing(_ g: StairGeom) -> Double? {
        let k = g.winderCount
        guard k > 0 else { return nil }
        switch g.kind {
        case .lShape: return g.width / 2 * (Double.pi / 2) / Double(k)
        case .uShape: let gap = min(100, g.width * 0.1); return (g.width / 2 + gap / 2) * Double.pi / Double(k)
        default: return nil
        }
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
        if let ex = g.extrusion, let r = Round7Shapes.extrusionFaces(ex) { return r }
        var b = RG.dedupe(g.boundary, closed: true)
        guard b.count >= 3, abs(GeometryOps.signedArea(b)) > 1e-9 else { return (b, b, []) }
        if GeometryOps.signedArea(b) < 0 { b.reverse() }
        var eave = g.eaveEdge
        if GeometryOps.signedArea(g.boundary) < 0 { eave = b.count - 2 - eave } // edge index after reversal
        eave = ((eave % b.count) + b.count) % b.count
        var fp = g.overhang > 0 ? RG.offsetPolygon(b, g.overhang) : b
        let k = tan(rad(max(0, min(g.pitch, 89))))
        if g.kind == .hip && g.profile == nil && !RG.isConvex(b) {
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
        var fns: [RoofFace] = []
        if let pr = g.profile, let special = profileFaces(g, pr, b: RG.isConvex(b) ? b : RG.convexHull(b), eave: eave, k: k) {
            fns = special
        } else {
        switch g.kind {
        case .flat:
            if let sp = g.shapePoints, !sp.isEmpty {
                let tin = Round7Shapes.tinFaces(fp, points: sp)
                if !tin.isEmpty { return (b, fp, tin) }
            }
            return (b, fp, [RoofFace(poly: fp, grad: .zero, c: 0)])
        case .shed: fns = [edgeFn(eave)]
        case .gable:
            let e = edgeFn(eave)
            let depth = b.map { e.height($0) }.max() ?? 0
            fns = [e, RoofFace(poly: [], grad: -e.grad, c: depth - e.c)]
        case .hip: fns = (0..<b.count).map(edgeFn)
        }
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

    /// Planes whose lower envelope is the special roof form (heights above the eave line).
    static func profileFaces(_ g: RoofGeom, _ pr: RoofProfile, b: [Vec2], eave: Int, k: Double) -> [RoofFace]? {
        guard b.count >= 3 else { return nil }
        let k2 = tan(rad(max(0, min(pr.upperPitch, 89))))
        let br = max(pr.breakDistance, 0)
        func inward(_ i: Int) -> (n: Vec2, a: Vec2) { let a = b[i], c = b[(i + 1) % b.count]; return ((c - a).normalized.perp, a) }
        // Two-pitch eave: steep k up to the break, then k2 (concave, so the minimum of the two planes).
        func twoPitch(_ i: Int) -> [RoofFace] {
            let (n, a) = inward(i)
            return [RoofFace(poly: [], grad: n * k, c: -k * a.dot(n)), RoofFace(poly: [], grad: n * k2, c: -k2 * a.dot(n) + (k - k2) * br)]
        }
        switch pr.form {
        case .mansard:
            return (0..<b.count).flatMap(twoPitch)
        case .gambrel:
            let (n, a) = inward(eave)
            let depth = b.map { n.dot($0 - a) }.max() ?? 0
            guard depth > 1e-9 else { return nil }
            // Opposite side mirrors the eave side about the ridge.
            let mirrored = [RoofFace(poly: [], grad: -n * k, c: k * (a.dot(n) + depth)),
                            RoofFace(poly: [], grad: -n * k2, c: k2 * (a.dot(n) + depth) + (k - k2) * br)]
            return twoPitch(eave) + mirrored
        case .dome:
            let c = GeometryOps.centroid(b)
            let R = b.map { $0.distance(to: c) }.max() ?? 0
            guard R > 1e-9 else { return nil }
            let H = min(R * max(k, 1e-3), R)
            let rho = (R * R + H * H) / (2 * H), zc = H - rho
            func z(_ r: Double) -> Double { zc + (rho * rho - r * r).squareRoot() }
            var out = [RoofFace(poly: [], grad: .zero, c: H)]
            let rings = 8, seg = 32
            for j in 1...rings {
                let r = R * min(Double(j) / Double(rings), 0.985)
                for s in 0..<seg {
                    let q = c + Vec2.polar(r, 2 * .pi * (Double(s) + (j % 2 == 0 ? 0.5 : 0)) / Double(seg))
                    let gr = (q - c) * (-1 / (rho * rho - r * r).squareRoot())
                    out.append(RoofFace(poly: [], grad: gr, c: z(r) - gr.dot(q)))
                }
            }
            return out
        case .barrel:
            let (n, a) = inward(eave)
            let s = b.map { n.dot($0 - a) }
            let W = ((s.max() ?? 0) - (s.min() ?? 0)) / 2
            guard W > 1e-9 else { return nil }
            let H = min(W * max(k, 1e-3), W)
            let rho = (W * W + H * H) / (2 * H), zc = H - rho, mid = (s.min() ?? 0) + W
            var out: [RoofFace] = []
            let steps = 24
            for i in 0...steps {
                let t = -W * 0.985 + 2 * W * 0.985 * Double(i) / Double(steps)
                let slope = -t / (rho * rho - t * t).squareRoot()
                let zt = zc + (rho * rho - t * t).squareRoot()
                // Height = zt + slope · (n·(p − a) − mid − t).
                out.append(RoofFace(poly: [], grad: n * slope, c: zt - slope * (n.dot(a) + mid + t)))
            }
            return out
        }
    }

    /// Whether segment a–b lies on the polygon outline.
    static func onOutline(_ a: Vec2, _ b: Vec2, _ poly: [Vec2], tol: Double) -> Bool {
        let m = (a + b) / 2
        return GeometryOps.distance(from: m, toPolyline: poly + [poly[0]]) < tol
            && GeometryOps.distance(from: a, toPolyline: poly + [poly[0]]) < tol
            && GeometryOps.distance(from: b, toPolyline: poly + [poly[0]]) < tol
    }
}
