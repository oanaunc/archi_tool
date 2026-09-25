// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Geometry builders for drafting commands (centre marks/lines, double lines, stars, 3-point rectangles, DIMSPACE).
public enum DraftGeometry {
    /// Offsets an open or closed point chain by a signed distance (left of travel direction = positive), mitred joins.
    public static func offsetChain(_ pts: [Vec2], _ d: Double, closed: Bool) -> [Vec2] {
        let n = pts.count
        guard n >= 2 else { return pts }
        var out: [Vec2] = []
        for i in 0..<n {
            let hasPrev = closed || i > 0, hasNext = closed || i < n - 1
            let p1 = pts[i]
            let nPrev = hasPrev ? (p1 - pts[(i - 1 + n) % n]).normalized.perp * d : nil
            let nNext = hasNext ? (pts[(i + 1) % n] - p1).normalized.perp * d : nil
            switch (nPrev, nNext) {
            case let (a?, b?):
                let p0 = pts[(i - 1 + n) % n], p2 = pts[(i + 1) % n]
                if let x = GeometryOps.lineIntersection(p0 + a, p1 + a, p1 + b, p2 + b) { out.append(x) } else { out.append(p1 + b) }
            case let (a?, nil): out.append(p1 + a)
            case let (nil, b?): out.append(p1 + b)
            default: out.append(p1)
            }
        }
        return out
    }

    /// Double line (DLINE): the two sides of a path of given width, and end caps for open paths.
    public static func doubleLine(_ pts: [Vec2], width: Double, justification: Double = 0, closed: Bool, caps: Bool = true) -> [Geometry] {
        guard pts.count >= 2, width > 0 else { return [] }
        // justification: -1 = right side on the path, 0 = centred, 1 = left side on the path
        let left = offsetChain(pts, width / 2 * (1 - justification), closed: closed)
        let right = offsetChain(pts, -width / 2 * (1 + justification), closed: closed)
        var out: [Geometry] = [.polyline(PolylineGeom(points: left, closed: closed)), .polyline(PolylineGeom(points: right, closed: closed))]
        if !closed && caps {
            out.append(.line(LineGeom(left[0], right[0])))
            out.append(.line(LineGeom(left[left.count - 1], right[right.count - 1])))
        }
        return out
    }

    /// Centre-mark cross for a circle/arc: horizontal and vertical lines extending `ext` past the curve.
    public static func centerMark(center c: Vec2, radius r: Double, extension ext: Double, rotation: Double = 0) -> [LineGeom] {
        let u = Vec2.polar(1, rotation), v = u.perp
        let L = r + ext
        return [LineGeom(c - u * L, c + u * L), LineGeom(c - v * L, c + v * L)]
    }

    /// Centre line between two lines: joins the midpoints of corresponding ends, extended by `ext` at both ends.
    public static func centerLine(_ a: LineGeom, _ b: LineGeom, extension ext: Double) -> LineGeom? {
        var b2 = b
        if (b.b - b.a).dot(a.b - a.a) < 0 { b2 = LineGeom(b.b, b.a) }
        let s = a.a.lerp(b2.a, 0.5), e = a.b.lerp(b2.b, 0.5)
        let d = (e - s).normalized
        guard d != .zero else { return nil }
        return LineGeom(s - d * ext, e + d * ext)
    }

    /// Star polygon with n points (outer radius R, inner radius r), first point at `angle`.
    public static func star(center c: Vec2, points n: Int, outer R: Double, inner r: Double, angle: Double = .pi / 2) -> [Vec2] {
        guard n >= 3 else { return [] }
        return (0..<(2 * n)).map { i in c + Vec2.polar(i % 2 == 0 ? R : r, angle + Double(i) * .pi / Double(n)) }
    }

    /// Rectangle from the first edge (p1→p2) and a point giving the other side.
    public static func rectangle3P(_ p1: Vec2, _ p2: Vec2, _ p3: Vec2) -> [Vec2]? {
        let u = (p2 - p1).normalized
        guard u != .zero else { return nil }
        let h = u.perp * (p3 - p2).dot(u.perp)
        guard h.length > 1e-9 else { return nil }
        var pts = [p1, p2, p2 + h, p1 + h]
        if GeometryOps.signedArea(pts) < 0 { pts.reverse() }
        return pts
    }

    /// Axis-aligned bounding rectangle of objects.
    public static func boundingRectangle(_ b: BBox2) -> [Vec2]? {
        guard !b.isEmpty else { return nil }
        return [b.min, Vec2(b.max.x, b.min.y), b.max, Vec2(b.min.x, b.max.y)]
    }

    // MARK: DIMSPACE

    /// Direction of the dimension line of a linear/aligned dimension.
    public static func dimensionDirection(_ d: DimensionGeom) -> Vec2? {
        guard d.points.count >= 3 else { return nil }
        switch d.kind {
        case .linear: return DimensionRenderer.linearDirection(d)
        case .aligned: let v = (d.points[1] - d.points[0]).normalized; return v == .zero ? nil : v
        default: return nil
        }
    }

    /// Spaces parallel linear/aligned dimensions evenly from a base dimension (spacing 0 aligns them with it).
    /// Dimensions not parallel to the base are returned unchanged.
    public static func spaceDimensions(base: DimensionGeom, others: [DimensionGeom], spacing: Double) -> [DimensionGeom] {
        guard let u = dimensionDirection(base) else { return others }
        let n = u.perp
        let s0 = base.points[2].dot(n)
        var out = others
        let idx = others.indices.filter { i in
            guard let v = dimensionDirection(others[i]) else { return false }
            return abs(v.cross(u)) < 1e-6
        }
        let pos = idx.filter { others[$0].points[2].dot(n) >= s0 }.sorted { others[$0].points[2].dot(n) < others[$1].points[2].dot(n) }
        let neg = idx.filter { others[$0].points[2].dot(n) < s0 }.sorted { others[$0].points[2].dot(n) > others[$1].points[2].dot(n) }
        for (k, i) in pos.enumerated() {
            let s = out[i].points[2].dot(n), target = s0 + Double(k + 1) * spacing
            out[i].points[2] = out[i].points[2] + n * (target - s)
        }
        for (k, i) in neg.enumerated() {
            let s = out[i].points[2].dot(n), target = s0 - Double(k + 1) * spacing
            out[i].points[2] = out[i].points[2] + n * (target - s)
        }
        return out
    }
}

// MARK: - Polyline vertex editing

extension DraftGeometry {
    /// Distance from q to segment i of a polyline, and the parameter (0…1) of the closest point along it.
    static func segmentProjection(_ a: PolyVertex, _ b: Vec2, _ q: Vec2) -> (dist: Double, t: Double, point: Vec2) {
        if abs(a.bulge) < 1e-12 {
            let d = b - a.p
            let t = d.lengthSquared < 1e-24 ? 0 : max(0, min(1, (q - a.p).dot(d) / d.lengthSquared))
            let p = a.p + d * t
            return (p.distance(to: q), t, p)
        }
        let arc = GeometryOps.bulgeArc(a.p, b, a.bulge)
        let phi = (q - arc.center).angle
        let ang = arc.sweep >= 0 ? normAngle(phi - arc.start) : -normAngle(arc.start - phi)
        var t = ang / arc.sweep
        if t > 1 { t = q.distance(to: a.p) < q.distance(to: b) ? 0 : 1 }
        let p = arc.center + Vec2.polar(arc.radius, arc.start + arc.sweep * t)
        return (p.distance(to: q), t, p)
    }

    /// Inserts a vertex on the segment nearest to q (arcs are split into two arcs of the same circle).
    public static func insertVertex(_ pl: PolylineGeom, near q: Vec2) -> PolylineGeom? {
        let v = pl.vertices, n = v.count
        guard n >= 2 else { return nil }
        let segs = pl.closed ? n : n - 1
        var best: (Int, Double, Double, Vec2)?
        for i in 0..<segs {
            let r = segmentProjection(v[i], v[(i + 1) % n].p, q)
            if r.dist < (best?.1 ?? .infinity) { best = (i, r.dist, r.t, r.point) }
        }
        guard let (i, _, t, p) = best, t > 1e-9, t < 1 - 1e-9 else { return nil }
        var out = pl
        let theta = 4 * atan(v[i].bulge)
        out.vertices[i].bulge = tan(theta * t / 4)
        out.vertices.insert(PolyVertex(p, bulge: tan(theta * (1 - t) / 4)), at: i + 1)
        return out
    }

    /// Removes the vertex nearest to q; the merged segment becomes straight.
    public static func removeVertex(_ pl: PolylineGeom, near q: Vec2) -> PolylineGeom? {
        guard pl.vertices.count > (pl.closed ? 3 : 2) else { return nil }
        guard let i = pl.vertices.indices.min(by: { pl.vertices[$0].p.distance(to: q) < pl.vertices[$1].p.distance(to: q) }) else { return nil }
        var out = pl
        out.vertices.remove(at: i)
        let prev = i - 1
        if prev >= 0 { out.vertices[prev].bulge = 0 } else if pl.closed { out.vertices[out.vertices.count - 1].bulge = 0 }
        if !pl.closed { out.vertices[out.vertices.count - 1].bulge = 0 }
        return out
    }

    /// Replaces arc segments with chords (maxDeviation 0 = default tessellation).
    public static func linearize(_ pl: PolylineGeom, maxDeviation: Double = 0) -> PolylineGeom {
        var out: [PolyVertex] = []
        let v = pl.vertices, n = v.count
        for i in 0..<n {
            let hasNext = pl.closed || i < n - 1
            guard hasNext, abs(v[i].bulge) > 1e-12 else { out.append(PolyVertex(v[i].p)); continue }
            let arc = GeometryOps.bulgeArc(v[i].p, v[(i + 1) % n].p, v[i].bulge)
            var k: Int
            if maxDeviation > 0, arc.radius > maxDeviation {
                let step = 2 * acos(1 - maxDeviation / arc.radius)
                k = max(1, Int((abs(arc.sweep) / step).rounded(.up)))
            } else { k = max(2, GeometryOps.segments(radius: arc.radius, sweep: abs(arc.sweep))) }
            k = min(k, 4096)
            for j in 0..<k { out.append(PolyVertex(arc.center + Vec2.polar(arc.radius, arc.start + arc.sweep * Double(j) / Double(k)))) }
        }
        var r = pl
        r.vertices = out
        return r
    }
}

// MARK: - OVERKILL

/// Removes duplicate objects and merges overlapping collinear lines (OVERKILL).
public enum Overkill {
    public struct Options {
        public var tolerance = 1e-6
        /// Properties that may differ between duplicates: "color", "layer", "linetype", "lineweight".
        public var ignore: Set<String> = []
        /// Merge collinear lines that touch end to end (not only overlapping ones).
        public var combineEndToEnd = false
        /// Remove duplicate vertices / merge collinear segments inside polylines.
        public var optimizePolylines = true
        public init() {}
    }
    public struct Result { public var removed: Set<EntityID> = []; public var modified: [EntityID: Geometry] = [:] }

    static func propKey(_ e: Entity, _ o: Options) -> String {
        [o.ignore.contains("layer") ? "" : e.layer.lowercased(), o.ignore.contains("color") ? "" : e.color.text,
         o.ignore.contains("linetype") ? "" : (e.linetype ?? "ByLayer").lowercased(), o.ignore.contains("lineweight") ? "" : e.lineweight.map { fmt($0) } ?? "BL"].joined(separator: "|")
    }
    static func q(_ v: Double, _ tol: Double) -> Int64 { Int64((v / max(tol, 1e-12)).rounded()) }
    static func q(_ p: Vec2, _ tol: Double) -> String { "\(q(p.x, tol)),\(q(p.y, tol))" }

    /// Geometry key for exact-duplicate detection (lines are direction-independent).
    static func geometryKey(_ g: Geometry, _ tol: Double) -> String? {
        switch g {
        case .point(let p): return "P" + q(p, tol)
        case .line(let l):
            let a = q(l.a, tol), b = q(l.b, tol)
            return "L" + (a < b ? a + ";" + b : b + ";" + a)
        case .circle(let c): return "C" + q(c.center, tol) + ";\(q(c.radius, tol))"
        case .arc(let a): return "A" + q(a.center, tol) + ";\(q(a.radius, tol));\(q(normAngle(a.start), 1e-9));\(q(normAngle(a.end), 1e-9))"
        case .polyline(let p):
            let fwd = p.vertices.map { q($0.p, tol) + "/\(q($0.bulge, 1e-9))" }.joined(separator: ";")
            return "PL\(p.closed)" + fwd
        default:
            guard let d = try? JSONEncoder().encode(g) else { return nil }
            return "X" + (String(data: d, encoding: .utf8) ?? "")
        }
    }

    public static func run(_ ents: [Entity], options o: Options = Options()) -> Result {
        var r = Result()
        let tol = max(o.tolerance, 1e-12)
        // 1. Exact duplicates (keep the oldest).
        var seen: [String: EntityID] = [:]
        for e in ents.sorted(by: { $0.id < $1.id }) {
            guard let k = geometryKey(e.geometry, tol) else { continue }
            let key = propKey(e, o) + "#" + k
            if seen[key] != nil { r.removed.insert(e.id) } else { seen[key] = e.id }
        }
        // 2. Collinear overlapping lines.
        struct L { var id: EntityID; var a: Vec2; var b: Vec2; var key: String }
        var lines: [L] = []
        for e in ents where !r.removed.contains(e.id) { if case .line(let l) = e.geometry, l.a.distance(to: l.b) > tol { lines.append(L(id: e.id, a: l.a, b: l.b, key: propKey(e, o))) } }
        var used = Set<EntityID>()
        for i in lines.indices where !used.contains(lines[i].id) {
            let base = lines[i]
            let u = (base.b - base.a).normalized
            var group = [base]
            for j in lines.indices where j != i && !used.contains(lines[j].id) && lines[j].key == base.key {
                let o2 = lines[j]
                if abs((o2.b - o2.a).normalized.cross(u)) < 1e-9 * 1000, abs((o2.a - base.a).cross(u)) <= tol, abs((o2.b - base.a).cross(u)) <= tol { group.append(o2) }
            }
            guard group.count > 1 else { continue }
            // Intervals along u.
            var iv = group.map { g -> (Double, Double, EntityID) in
                let t0 = (g.a - base.a).dot(u), t1 = (g.b - base.a).dot(u)
                return (min(t0, t1), max(t0, t1), g.id)
            }.sorted { $0.0 < $1.0 }
            var merged: [(Double, Double, [EntityID])] = []
            for x in iv {
                if var last = merged.last, x.0 < last.1 - tol || (o.combineEndToEnd && x.0 <= last.1 + tol) || (x.0 <= last.1 + tol && x.1 <= last.1 + tol) {
                    last.1 = max(last.1, x.1); last.2.append(x.2); merged[merged.count - 1] = last
                } else { merged.append((x.0, x.1, [x.2])) }
            }
            iv.removeAll()
            for m in merged where m.2.count > 1 {
                let keep = m.2.min()!
                for id in m.2 where id != keep { r.removed.insert(id) }
                r.modified[keep] = .line(LineGeom(base.a + u * m.0, base.a + u * m.1))
            }
            for g in group { used.insert(g.id) }
        }
        // 3. Polyline optimisation.
        if o.optimizePolylines {
            for e in ents where !r.removed.contains(e.id) {
                guard case .polyline(let p) = e.geometry else { continue }
                let opt = optimize(p, tol: tol)
                if opt != p { r.modified[e.id] = .polyline(opt) }
            }
        }
        return r
    }

    /// Removes zero-length segments and merges collinear straight segments of a polyline.
    public static func optimize(_ p: PolylineGeom, tol: Double) -> PolylineGeom {
        var v: [PolyVertex] = []
        for x in p.vertices {
            if let last = v.last, last.p.distance(to: x.p) <= tol { continue }
            v.append(x)
        }
        if p.closed, v.count > 1, v[0].p.distance(to: v[v.count - 1].p) <= tol { v.removeLast() }
        var changed = true
        while changed && v.count > 2 {
            changed = false
            let n = v.count
            for i in 0..<n {
                if !p.closed && (i == 0 || i == n - 1) { continue }
                let prev = v[(i - 1 + n) % n], cur = v[i], next = v[(i + 1) % n]
                guard abs(prev.bulge) < 1e-12, abs(cur.bulge) < 1e-12 else { continue }
                let d1 = cur.p - prev.p, d2 = next.p - cur.p
                if abs(d1.normalized.cross(d2.normalized)) < 1e-9 && d1.dot(d2) > 0 {
                    v.remove(at: i); changed = true; break
                }
            }
        }
        var out = p
        out.vertices = v
        return out
    }
}

// MARK: - Clipboard

/// Objects copied with COPYCLIP/CUTCLIP/COPYBASE, shared by all open drawings.
public struct DraftClipboard {
    public var entities: [Entity]
    public var elements: [BIMElement]
    public var blocks: [String: Block]
    public var layers: [Layer]
    public var base: Vec2
    public init(entities: [Entity], elements: [BIMElement] = [], blocks: [String: Block] = [:], layers: [Layer] = [], base: Vec2) {
        self.entities = entities; self.elements = elements; self.blocks = blocks; self.layers = layers; self.base = base
    }
    public static var current: DraftClipboard?
    /// Called when the clipboard changes (the app mirrors it to the system pasteboard).
    public static var onChange: ((DraftClipboard) -> Void)?

    public var isEmpty: Bool { entities.isEmpty && elements.isEmpty }

    /// Captures objects of a document (with the block definitions they reference).
    public static func capture(_ ids: [EntityID], from doc: ArchiDocument, base: Vec2) -> DraftClipboard {
        let set = Set(ids)
        let ents = doc.entities.filter { set.contains($0.id) }
        var els = doc.elements.filter { set.contains($0.id) }
        // Openings travel with their host walls.
        let hosts = Set(els.map(\.id))
        for el in doc.elements where !set.contains(el.id) { if case .opening(let o) = el.geometry, hosts.contains(o.hostWall) { els.append(el) } }
        var blocks: [String: Block] = [:]
        var queue = ents
        while let e = queue.popLast() {
            if case .insert(let i) = e.geometry, blocks[i.block] == nil, let b = doc.blocks[i.block] { blocks[i.block] = b; queue += b.entities }
        }
        let layerNames = Set(ents.map { $0.layer.lowercased() } + els.map { $0.layer.lowercased() })
        return DraftClipboard(entities: ents, elements: els, blocks: blocks, layers: doc.layers.filter { layerNames.contains($0.name.lowercased()) }, base: base)
    }

    /// Pastes into a document moved by `offset`; returns the new IDs.
    @discardableResult
    public func paste(into doc: inout ArchiDocument, offset: Vec2, level: Int? = nil) -> [EntityID] {
        for l in layers where doc.layer(named: l.name) == nil { doc.layers.append(l) }
        for (k, b) in blocks where doc.blocks[k] == nil { doc.blocks[k] = b }
        let t = Transform2D.translation(offset)
        var out: [EntityID] = []
        for e in entities { var n = e; n.geometry = GeometryOps.transform(e.geometry, t); out.append(doc.add(n)) }
        var map: [EntityID: EntityID] = [:]
        for el in elements { if case .opening = el.geometry { continue }
            var n = el; n.geometry = CommandHelpers.transform(el.geometry, t); n.id = doc.allocateID(); n.level = level ?? el.level
            doc.ensureLayer(n.layer); doc.elements.append(n); map[el.id] = n.id; out.append(n.id)
        }
        for el in elements {
            guard case .opening(var o) = el.geometry, let h = map[o.hostWall] else { continue }
            o.hostWall = h
            var n = el; n.geometry = .opening(o); n.id = doc.allocateID(); n.level = level ?? el.level
            doc.elements.append(n); out.append(n.id)
        }
        return out
    }

    /// The clipboard as a small .archi document (for the system pasteboard / other applications).
    public func asDocument(units: Units) -> ArchiDocument {
        var d = ArchiDocument()
        d.units = units
        paste(into: &d, offset: -base)
        return d
    }
}
