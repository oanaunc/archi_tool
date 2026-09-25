// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public struct SnapResult: Equatable {
    public var point: Vec2; public var kind: SnapKind; public var entity: EntityID?
    public init(point: Vec2, kind: SnapKind, entity: EntityID?) { self.point = point; self.kind = kind; self.entity = entity }
}

/// Points and directions acquired for object snap tracking (OTRACK): hovering an object snap acquires its point,
/// hovering a straight segment (with PAR on and a base point) acquires its direction for parallel snapping.
public final class SnapTracker {
    public private(set) var points: [Vec2] = []
    public private(set) var directions: [Vec2] = []
    /// Tracking vectors of the last successful tracking snap (for display: from → to).
    public var lines: [(from: Vec2, to: Vec2)] = []
    public var maxPoints = 7
    /// Tracking runs only while a command asks for a point (set by the Editor).
    public var active = false
    public init() {}
    public func acquire(_ p: Vec2) {
        if let i = points.firstIndex(where: { $0.isClose(p, tol: 1e-9) }) { if i == points.count - 1 { return }; points.remove(at: i) }
        points.append(p)
        if points.count > maxPoints { points.removeFirst(points.count - maxPoints) }
    }
    public func acquireDirection(_ v: Vec2) {
        let d = v.normalized
        guard d != .zero else { return }
        directions.removeAll { abs($0.cross(d)) < 1e-9 }
        directions.append(d)
        if directions.count > 3 { directions.removeFirst() }
    }
    public func clear() { points = []; directions = []; lines = [] }
}

/// Object snaps (OSNAP) and ortho/polar/grid constraints.
public enum Snap {
    /// Shared tracking state (the canvas has one cursor).
    public static let tracker = SnapTracker()

    /// Object snap tracking: aligns the cursor horizontally/vertically (or at polar angles when polar tracking is on) with acquired
    /// points, at the intersection of two such paths, or parallel to an acquired direction from `base`.
    /// Returns the tracked point, its kind (.extension for point tracking, .parallel) and the tracking vectors to display.
    public static func track(cursor: Vec2, base: Vec2?, points: [Vec2], directions: [Vec2], settings: DraftSettings, tolerance: Double)
        -> (point: Vec2, kind: SnapKind, lines: [(from: Vec2, to: Vec2)])? {
        let tol = Swift.max(tolerance, 1e-12)
        var angles: [Double] = [0, .pi / 2]
        if settings.polarTracking && settings.polarIncrement > 1e-9 && !settings.ortho {
            let inc = rad(settings.polarIncrement)
            let n = Swift.min(Int((Double.pi / inc).rounded(.up)), 72)
            angles = (0..<n).map { Double($0) * inc }.filter { $0 < .pi - 1e-9 }
        }
        struct Path { var origin: Vec2; var dir: Vec2; var kind: SnapKind; var fromBase: Bool }
        var paths: [Path] = []
        for p in points where !(base.map { $0.isClose(p, tol: 1e-9) } ?? false) {
            for a in angles { paths.append(Path(origin: p, dir: Vec2.polar(1, a), kind: .extension, fromBase: false)) }
        }
        if let b = base {
            for d in directions { paths.append(Path(origin: b, dir: d, kind: .parallel, fromBase: true)) }
            for a in angles { paths.append(Path(origin: b, dir: Vec2.polar(1, a), kind: .extension, fromBase: true)) }
        }
        guard !paths.isEmpty else { return nil }
        func foot(_ q: Path) -> Vec2 { q.origin + q.dir * (cursor - q.origin).dot(q.dir) }
        let near = paths.filter { foot($0).distance(to: cursor) <= tol }
        guard !near.isEmpty else { return nil }
        // Two paths from different origins: their intersection.
        var best: (Vec2, Double, Path, Path)?
        for i in 0..<near.count {
            for j in (i + 1)..<near.count {
                let a = near[i], b = near[j]
                guard !a.origin.isClose(b.origin, tol: 1e-9), abs(a.dir.cross(b.dir)) > 1e-9,
                      let x = GeometryOps.lineIntersection(a.origin, a.origin + a.dir, b.origin, b.origin + b.dir) else { continue }
                let d = x.distance(to: cursor)
                if d <= tol * 2, d < (best?.1 ?? .infinity) { best = (x, d, a, b) }
            }
        }
        if let (x, _, a, b) = best {
            return (x, a.kind == .parallel || b.kind == .parallel ? .parallel : .extension, [(a.origin, x), (b.origin, x)])
        }
        // A single path; a plain polar path from the base is left to polar tracking.
        let singles = near.filter { !$0.fromBase || $0.kind == .parallel }
        guard let q = singles.min(by: { foot($0).distance(to: cursor) < foot($1).distance(to: cursor) }) else { return nil }
        let f = foot(q)
        return (f, q.kind, [(q.origin, f)])
    }

    /// Lower tier wins; within a tier the closest point wins.
    static func tier(_ k: SnapKind) -> Int {
        switch k {
        case .endpoint, .intersection, .center, .node, .insertion: return 0
        case .midpoint: return 1
        case .quadrant, .perpendicular, .tangent, .parallel: return 2
        case .nearest, .extension: return 3
        case .grid: return 4
        }
    }

    /// Collects candidate snap points and nearby curve pieces.
    struct Collector {
        let cursor: Vec2
        let tol: Double
        let box: BBox2
        let modes: Set<SnapKind>
        var best: (tier: Int, dist: Double, res: SnapResult)?
        var local: [(id: EntityID, piece: CurvePiece)] = []

        mutating func offer(_ p: Vec2, _ k: SnapKind, _ id: EntityID?) {
            guard modes.contains(k) else { return }
            let d = p.distance(to: cursor)
            guard d <= tol else { return }
            let t = Snap.tier(k)
            if let b = best, t > b.tier || (t == b.tier && d >= b.dist) { return }
            best = (t, d, SnapResult(point: p, kind: k, entity: id))
        }
        mutating func offer(_ ps: [Vec2], _ k: SnapKind, _ id: EntityID?) {
            guard modes.contains(k) else { return }
            for p in ps { offer(p, k, id) }
        }
        mutating func addPieces(_ pcs: [CurvePiece], _ id: EntityID) {
            for p in pcs where p.bounds.expanded(by: tol).contains(cursor) { local.append((id, p)) }
        }
        mutating func addPath(_ path: CurvePath, _ id: EntityID, vertices: Bool, mids: Bool) {
            if vertices {
                if path.kind == .polyline || path.kind == .other {
                    offer(path.pieces.map(\.p0), .endpoint, id)
                    if !path.closed { offer(path.end, .endpoint, id) }
                } else if !path.closed { offer([path.start, path.end], .endpoint, id) }
            }
            if mids && modes.contains(.midpoint) {
                if path.kind == .polyline || path.kind == .other || path.kind == .line || path.kind == .arc {
                    offer(path.pieces.map { $0.point(0.5) }, .midpoint, id)
                }
            }
            if modes.contains(.center) { for p in path.pieces where p.isArc { offer(p.center, .center, id) } }
            addPieces(path.pieces, id)
        }
    }

    /// Cheap bounds of a geometry (block bounds cached per call).
    static func quickBounds(_ g: Geometry, doc: ArchiDocument, blockCache: inout [String: BBox2]) -> BBox2 {
        switch g {
        case .point(let p): return BBox2(min: p, max: p)
        case .line(let l): return BBox2(points: [l.a, l.b])
        case .circle(let c): return BBox2(min: c.center - Vec2(c.radius, c.radius), max: c.center + Vec2(c.radius, c.radius))
        case .arc(let a): var b = CurvePiece(arc: a.center, a.radius, a.start, a.sweep).bounds; b.add(a.center); return b
        case .ellipse(let e):
            let r = e.majorAxis.length
            return BBox2(min: e.center - Vec2(r, r), max: e.center + Vec2(r, r))
        case .polyline(let p):
            var b = BBox2.empty
            for (i, v) in p.vertices.enumerated() {
                b.add(v.p)
                if abs(v.bulge) > 1e-12, p.closed || i < p.vertices.count - 1 {
                    b.add(CurvePiece.bulge(v.p, p.vertices[(i + 1) % p.vertices.count].p, v.bulge).bounds)
                }
            }
            return b.expanded(by: p.width / 2)
        case .spline(let s): return BBox2(points: s.controlPoints + s.fitPoints)
        case .text(let t): var b = BBox2(points: GeometryOps.textBoxCorners(t)); b.add(t.position); return b
        case .insert(let ins):
            guard let blk = doc.blocks[ins.block] else { return BBox2(min: ins.position, max: ins.position) }
            let lb: BBox2
            if let c = blockCache[ins.block] { lb = c } else {
                var b = BBox2.empty
                for e in blk.entities { b.add(quickBounds(e.geometry, doc: doc, blockCache: &blockCache)) }
                blockCache[ins.block] = b; lb = b
            }
            guard !lb.isEmpty else { return BBox2(min: ins.position, max: ins.position) }
            let t = ins.transform * Transform2D.translation(-blk.basePoint)
            var b = BBox2(points: lb.corners.map(t.apply)); b.add(ins.position)
            return b
        case .dimension(let d): return BBox2(points: d.points)
        case .hatch: return .empty
        default: return GeometryOps.bounds(g, doc: doc)
        }
    }

    static func collect(_ g: Geometry, id: EntityID, doc: ArchiDocument, depth: Int, into c: inout Collector, blockCache: inout [String: BBox2]) {
        switch g {
        case .point(let p): c.offer(p, .node, id)
        case .line, .polyline:
            if let path = CurvePath.make(g) { c.addPath(path, id, vertices: true, mids: true) }
        case .arc(let a):
            c.offer([a.startPoint, a.endPoint], .endpoint, id)
            c.offer(a.midPoint, .midpoint, id)
            c.offer(a.center, .center, id)
            let pc = CurvePiece(arc: a.center, a.radius, a.start, a.sweep)
            if c.modes.contains(.quadrant) {
                for k in 0..<4 where normAngle(Double(k) * .pi / 2 - a.start) <= a.sweep { c.offer(a.center + Vec2.polar(a.radius, Double(k) * .pi / 2), .quadrant, id) }
            }
            c.addPieces([pc], id)
        case .circle(let ci):
            c.offer(ci.center, .center, id)
            c.offer((0..<4).map { ci.center + Vec2.polar(ci.radius, Double($0) * .pi / 2) }, .quadrant, id)
            c.addPieces([CurvePiece(arc: ci.center, ci.radius, 0, 2 * .pi)], id)
        case .ellipse(let e):
            c.offer(e.center, .center, id)
            let sweep = e.isFull ? 2 * .pi : normAngle(e.end - e.start)
            if c.modes.contains(.quadrant) {
                for k in 0..<4 {
                    let u = Double(k) * .pi / 2
                    if e.isFull || normAngle(u - e.start) <= sweep { c.offer(e.point(at: u), .quadrant, id) }
                }
            }
            if let path = CurvePath.make(g) { c.addPath(path, id, vertices: !e.isFull, mids: false) }
        case .spline:
            if let path = CurvePath.make(g) { c.addPath(path, id, vertices: true, mids: false) }
        case .text(let t): c.offer(t.position, .insertion, id)
        case .dimension(let d):
            c.offer(d.points, .node, id)
            for p in CurvePath.all(g, doc: doc) { c.addPieces(p.pieces, id) }
        case .leader(let l):
            c.offer(l.points, .endpoint, id)
            if let p = CurvePath.fromPoints(l.points) { c.addPieces(p.pieces, id) }
        case .insert(let ins):
            c.offer(ins.position, .insertion, id)
            guard depth < 4, let blk = doc.blocks[ins.block] else { return }
            let t = ins.transform * Transform2D.translation(-blk.basePoint)
            for e in blk.entities {
                let sg = GeometryTransform.apply(e.geometry, t)
                guard quickBounds(sg, doc: doc, blockCache: &blockCache).expanded(by: c.tol).contains(c.cursor) else { continue }
                collect(sg, id: id, doc: doc, depth: depth + 1, into: &c, blockCache: &blockCache)
            }
        case .image(let im):
            c.offer(im.origin, .insertion, id)
            for p in CurvePath.all(g, doc: doc) { c.offer(p.pieces.map(\.p0), .endpoint, id); c.addPieces(p.pieces, id) }
        case .table(let tb):
            c.offer(tb.origin, .insertion, id)
            for p in CurvePath.all(g, doc: doc) { c.offer(p.pieces.map(\.p0), .endpoint, id); c.addPieces(p.pieces, id) }
        case .solid(let s):
            c.offer(s.origin.xy, .insertion, id)
            if s.kind == .cylinder || s.kind == .cone || s.kind == .sphere {
                c.offer(s.origin.xy, .center, id)
                c.addPieces([CurvePiece(arc: s.origin.xy, s.size.x, 0, 2 * .pi)], id)
            } else {
                for p in CurvePath.all(g, doc: doc) { c.offer(p.pieces.map(\.p0), .endpoint, id); c.addPieces(p.pieces, id) }
            }
        case .hatch:
            break
        }
    }

    /// Snap geometry of a BIM element in plan: characteristic points and outline pieces.
    static func elementSnaps(_ el: BIMElement, doc: ArchiDocument) -> (ends: [Vec2], mids: [Vec2], centers: [Vec2], inserts: [Vec2], pieces: [CurvePiece]) {
        var ends: [Vec2] = [], mids: [Vec2] = [], centers: [Vec2] = [], inserts: [Vec2] = [], pieces: [CurvePiece] = []
        func loop(_ pts: [Vec2], closed: Bool) {
            guard let p = CurvePath.fromPoints(pts, closed: closed) else { return }
            ends += p.pieces.map(\.p0); if !closed { ends.append(p.end) }
            mids += p.pieces.map { $0.point(0.5) }
            pieces += p.pieces
        }
        func rect(_ c: Vec2, _ w: Double, _ d: Double, _ rot: Double) -> [Vec2] {
            [Vec2(-w / 2, -d / 2), Vec2(w / 2, -d / 2), Vec2(w / 2, d / 2), Vec2(-w / 2, d / 2)].map { c + $0.rotated(by: rot) }
        }
        switch el.geometry {
        case .wall(let w):
            let c0 = w.centerStart, c1 = w.centerEnd, h = w.thickness / 2
            ends += [c0, c1]
            if w.justification != .center { ends += [w.start, w.end] }
            let center = CurvePiece.bulge(c0, c1, w.bulge)
            if center.isDegenerate { break }
            if center.isArc {
                let sg: Double = center.sweep >= 0 ? 1 : -1
                let left = CurvePiece(arc: center.center, center.radius - sg * h, center.a0, center.sweep)
                let right = CurvePiece(arc: center.center, center.radius + sg * h, center.a0, center.sweep)
                pieces += [left, right, CurvePiece(seg: left.p0, right.p0), CurvePiece(seg: left.p1, right.p1)]
                ends += [left.p0, left.p1, right.p0, right.p1]
                mids += [left.point(0.5), right.point(0.5), center.point(0.5)]
                centers.append(center.center)
            } else {
                let n = (c1 - c0).normalized.perp * h
                let l0 = c0 + n, l1 = c1 + n, r0 = c0 - n, r1 = c1 - n
                pieces += [CurvePiece(seg: l0, l1), CurvePiece(seg: r0, r1), CurvePiece(seg: l0, r0), CurvePiece(seg: l1, r1)]
                ends += [l0, l1, r0, r1]
                mids += [(l0 + l1) / 2, (r0 + r1) / 2, (c0 + c1) / 2]
            }
        case .column(let c):
            centers.append(c.position)
            if c.round {
                pieces.append(CurvePiece(arc: c.position, c.width / 2, 0, 2 * .pi))
            } else { loop(rect(c.position, c.width, c.depth, c.rotation), closed: true) }
        case .beam(let b):
            let n = (b.end - b.start).normalized.perp * (b.width / 2)
            loop([b.start + n, b.end + n, b.end - n, b.start - n], closed: true)
            ends += [b.start, b.end]
        case .slab(let s):
            loop(s.boundary, closed: true)
            for hole in s.holes { loop(hole, closed: true) }
        case .roof(let r): loop(r.boundary, closed: true)
        case .space(let s): loop(s.boundary, closed: true)
        case .railing(let r): loop(r.path, closed: false)
        case .curtainWall(let cw): loop([cw.start, cw.end], closed: false)
        case .gridLine(let g): loop([g.start, g.end], closed: false)
        case .component(let c):
            inserts.append(c.position)
            loop(rect(c.position, c.size.x, c.size.y, c.rotation), closed: true)
        case .stair(let s):
            inserts.append(s.start)
        case .opening(let o):
            guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry, abs(w.bulge) < 1e-9 else { break }
            let dir = (w.centerEnd - w.centerStart).normalized
            guard dir != .zero else { break }
            let n = dir.perp * (w.thickness / 2)
            let c = w.centerStart + dir * o.offset
            for s in [-1.0, 1.0] {
                let j = c + dir * (s * o.width / 2)
                ends += [j + n, j - n]
                pieces.append(CurvePiece(seg: j + n, j - n))
            }
            mids.append(c)
        }
        return (ends, mids, centers, inserts, pieces)
    }

    /// Finds the best object snap near `cursor` (within `tolerance` drawing units).
    /// `base` enables perpendicular and tangent snaps from the previous point.
    public static func find(cursor: Vec2, doc: ArchiDocument, settings: DraftSettings, tolerance: Double, base: Vec2?) -> SnapResult? {
        let tol = Swift.max(tolerance, 1e-12)
        let modes: Set<SnapKind> = settings.objectSnap ? settings.snapModes : []
        var c = Collector(cursor: cursor, tol: tol, box: BBox2(min: cursor - Vec2(tol, tol), max: cursor + Vec2(tol, tol)), modes: modes)
        if !modes.isEmpty {
            var hidden = Set<String>()
            for l in doc.layers where !l.visible || l.frozen { hidden.insert(l.name); hidden.insert(l.name.lowercased()) }
            func isHidden(_ n: String) -> Bool { !hidden.isEmpty && (hidden.contains(n) || hidden.contains(n.lowercased())) }
            var blockCache: [String: BBox2] = [:]
            for e in doc.entities {
                if isHidden(e.layer) { continue }
                let bb = quickBounds(e.geometry, doc: doc, blockCache: &blockCache)
                guard !bb.isEmpty, bb.expanded(by: tol).contains(cursor) else { continue }
                collect(e.geometry, id: e.id, doc: doc, depth: 0, into: &c, blockCache: &blockCache)
            }
            for el in doc.elements where el.level == doc.currentLevel && !isHidden(el.layer) {
                let s = elementSnaps(el, doc: doc)
                var bb = BBox2(points: s.ends + s.mids + s.centers + s.inserts)
                for p in s.pieces { bb.add(p.bounds) }
                guard !bb.isEmpty, bb.expanded(by: tol).contains(cursor) else { continue }
                c.offer(s.ends, .endpoint, el.id)
                c.offer(s.mids, .midpoint, el.id)
                c.offer(s.centers, .center, el.id)
                c.offer(s.inserts, .insertion, el.id)
                c.addPieces(s.pieces, el.id)
            }
            let local = c.local
            for (id, pc) in local {
                if modes.contains(.nearest) { c.offer(pc.closestPoint(cursor), .nearest, id) }
                if let b = base {
                    if modes.contains(.perpendicular) {
                        if pc.isArc {
                            let d = b - pc.center
                            if d.length > 1e-12 {
                                for s in [1.0, -1.0] {
                                    let p = pc.center + d.normalized * (pc.radius * s)
                                    let t = pc.param(p)
                                    if t >= -1e-9 && t <= 1 + 1e-9 { c.offer(p, .perpendicular, id) }
                                }
                            }
                        } else {
                            let t = pc.param(b)
                            if t >= -1e-9 && t <= 1 + 1e-9 { c.offer(pc.point(t), .perpendicular, id) }
                        }
                    }
                    if modes.contains(.tangent), pc.isArc, !pc.approx {
                        let d = b - pc.center, dl = d.length
                        if dl > pc.radius + 1e-9 {
                            let al = acos(pc.radius / dl)
                            for s in [1.0, -1.0] {
                                let p = pc.center + Vec2.polar(pc.radius, d.angle + s * al)
                                let t = pc.param(p)
                                if t >= -1e-9 && t <= 1 + 1e-9 { c.offer(p, .tangent, id) }
                            }
                        }
                    }
                }
            }
            if modes.contains(.intersection) {
                let cand = local.count > 300 ? Array(local.sorted { $0.piece.closestPoint(cursor).distance(to: cursor) < $1.piece.closestPoint(cursor).distance(to: cursor) }.prefix(300)) : local
                for i in 0..<cand.count {
                    for j in (i + 1)..<Swift.max(i + 1, cand.count) where cand[i].id != cand[j].id {
                        for r in CurveMath.intersect(cand[i].piece, cand[j].piece) { c.offer(r.p, .intersection, cand[i].id) }
                    }
                }
            }
            if modes.contains(.extension) {
                for (id, pc) in local where !pc.isArc && !pc.approx {
                    let t = pc.param(cursor)
                    if t < 0 || t > 1 { c.offer(pc.point(t), .extension, id) }
                }
            }
        }
        if settings.objectSnapTracking && tracker.active {
            if let b = c.best, b.res.kind != .nearest, b.res.kind != .grid, b.res.kind != .extension {
                tracker.acquire(b.res.point)
            } else if modes.contains(.parallel), base != nil,
                      let near = c.local.filter({ !$0.piece.isArc && !$0.piece.approx }).min(by: { $0.piece.closestPoint(cursor).distance(to: cursor) < $1.piece.closestPoint(cursor).distance(to: cursor) }),
                      near.piece.closestPoint(cursor).distance(to: cursor) <= tol {
                tracker.acquireDirection(near.piece.p1 - near.piece.p0)
            }
            if c.best == nil || c.best!.res.kind == .nearest {
                if let t = track(cursor: cursor, base: base, points: tracker.points, directions: modes.contains(.parallel) ? tracker.directions : [],
                                 settings: settings, tolerance: tol) {
                    tracker.lines = t.lines
                    return SnapResult(point: t.point, kind: t.kind, entity: nil)
                }
            }
            tracker.lines = []
        }
        if settings.gridSnap && settings.gridSpacing > 0 {
            let g = settings.gridSpacing
            let p = Vec2((cursor.x / g).rounded() * g, (cursor.y / g).rounded() * g)
            var gc = Collector(cursor: cursor, tol: tol, box: c.box, modes: [.grid])
            gc.offer(p, .grid, nil)
            if let gr = gc.best, c.best == nil { return gr.res }
        }
        return c.best?.res
    }

    /// Applies ortho (horizontal/vertical from base), polar tracking (within ~3° of a multiple of
    /// `polarIncrement`) and grid snap (rounding to `gridSpacing`, or the distance along an ortho/polar ray).
    public static func constrain(base: Vec2, cursor: Vec2, settings: DraftSettings) -> Vec2 {
        let d = cursor - base
        let g = settings.gridSpacing
        let grid = settings.gridSnap && g > 0
        func roundG(_ v: Double) -> Double { (v / g).rounded() * g }
        if d.length < 1e-12 { return grid ? Vec2(roundG(cursor.x), roundG(cursor.y)) : cursor }
        if settings.ortho {
            if abs(d.x) >= abs(d.y) {
                let x = grid ? base.x + roundG(d.x) : cursor.x
                return Vec2(x, base.y)
            }
            let y = grid ? base.y + roundG(d.y) : cursor.y
            return Vec2(base.x, y)
        }
        if settings.polarTracking && settings.polarIncrement > 1e-9 {
            let inc = rad(settings.polarIncrement)
            let a = d.angle
            let k = (a / inc).rounded()
            let snapped = k * inc
            if abs(a - snapped) <= rad(3) {
                let dir = Vec2.polar(1, snapped)
                var dist = d.dot(dir)
                if grid { dist = roundG(dist) }
                return base + dir * dist
            }
        }
        return grid ? Vec2(roundG(cursor.x), roundG(cursor.y)) : cursor
    }
}
