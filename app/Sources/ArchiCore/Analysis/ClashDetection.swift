// Oanarina Archi Tool — GPL-3.0-or-later
// Hard-clash detection between building elements and 3D solids: bounding-box broad phase, then exact
// triangle–triangle intersection (Möller 1997, "A fast triangle-triangle intersection test") with a
// penetration tolerance so touching faces are not reported, plus a containment test for enclosed parts.
import Foundation

public struct ClashOptions {
    /// Minimum penetration (drawing units) that counts as a clash; touching elements are ignored.
    public var tolerance: Double = 1
    /// Ignore doors/windows/openings against their host wall.
    public var ignoreHosted = true
    /// Ignore walls that meet at their ends (wall joins).
    public var ignoreJoinedWalls = true
    /// Include rooms/spaces (off: spaces are not physical).
    public var includeSpaces = false
    /// Include 3D solid entities (not only BIM elements).
    public var includeSolids = true
    /// Also test solid entities against each other (off: modelled objects made of several solids are not reported).
    public var solidPairs = false
    /// Only test pairs where one side is in `setA` and the other in `setB` (nil = all against all).
    public var setA: Set<EntityID>? = nil
    public var setB: Set<EntityID>? = nil
    public init() {}
}

public struct Clash: Hashable {
    public var a: EntityID
    public var b: EntityID
    public var kindA: String
    public var kindB: String
    /// A point on the intersection (or the contained part's centre).
    public var point: Vec3
    /// Overlap of the two bounding boxes.
    public var bounds: BBox3
    public var contained: Bool
    public var description: String {
        "\(kindA) #\(a) × \(kindB) #\(b)\(contained ? " (contained)" : "") at \(fmt(point.x, 1)),\(fmt(point.y, 1)),\(fmt(point.z, 1))"
    }
}

public enum ClashDetector {
    struct Body { var id: EntityID; var kind: String; var tris: [(Vec3, Vec3, Vec3)]; var box: BBox3 }

    public static func detect(_ doc: ArchiDocument, options: ClashOptions = ClashOptions()) -> [Clash] {
        var kinds: [EntityID: String] = [:]
        var isEntity = Set<EntityID>()
        var skip = Set<EntityID>()
        for el in doc.elements {
            kinds[el.id] = el.typeName
            if !options.includeSpaces, case .space = el.geometry { skip.insert(el.id) }
            if case .gridLine = el.geometry { skip.insert(el.id) }
        }
        for e in doc.entities { kinds[e.id] = e.typeName; isEntity.insert(e.id); if !options.includeSolids { skip.insert(e.id) } }
        var tris: [EntityID: [(Vec3, Vec3, Vec3)]] = [:]
        for g in MeshBuilder.build(doc: doc) {
            guard let id = g.id, !skip.contains(id), kinds[id] != nil else { continue }
            let m = g.mesh
            var i = 0
            while i + 2 < m.indices.count {
                let a = Int(m.indices[i]), b = Int(m.indices[i + 1]), c = Int(m.indices[i + 2])
                i += 3
                guard a < m.positions.count, b < m.positions.count, c < m.positions.count else { continue }
                tris[id, default: []].append((m.positions[a], m.positions[b], m.positions[c]))
            }
        }
        var bodies: [Body] = tris.compactMap { id, t in
            guard !t.isEmpty else { return nil }
            var b = BBox3.empty
            for x in t { b.add(x.0); b.add(x.1); b.add(x.2) }
            return Body(id: id, kind: kinds[id] ?? "object", tris: t, box: b)
        }
        bodies.sort { $0.box.min.x < $1.box.min.x }
        // Pairs that are allowed to touch/overlap.
        var exempt = Set<[EntityID]>()
        func key(_ a: EntityID, _ b: EntityID) -> [EntityID] { a < b ? [a, b] : [b, a] }
        if options.ignoreHosted {
            for el in doc.elements { if case .opening(let o) = el.geometry { exempt.insert(key(el.id, o.hostWall)) } }
        }
        if options.ignoreJoinedWalls {
            let walls = doc.elements.compactMap { el -> (EntityID, Int, WallGeom)? in if case .wall(let w) = el.geometry { return (el.id, el.level, w) }; return nil }
            for i in 0..<walls.count { for j in (i + 1)..<max(i + 1, walls.count) where walls[i].1 == walls[j].1 {
                let a = walls[i].2, b = walls[j].2
                let tol = max(a.thickness, b.thickness)
                let ends = [a.start, a.end], others = [b.start, b.end]
                let touch = ends.contains { p in GeometryOps.distance(point: p, segA: b.centerStart, segB: b.centerEnd) <= tol } ||
                    others.contains { p in GeometryOps.distance(point: p, segA: a.centerStart, segB: a.centerEnd) <= tol }
                if touch && abs(a.direction.cross(b.direction)) > 0.05 { exempt.insert(key(walls[i].0, walls[j].0)) }
            } }
        }
        let tol = max(options.tolerance, 0)
        var out: [Clash] = []
        for i in 0..<bodies.count {
            let A = bodies[i]
            for j in (i + 1)..<max(i + 1, bodies.count) {
                let B = bodies[j]
                if B.box.min.x > A.box.max.x - tol { break }
                if let sa = options.setA, let sb = options.setB {
                    guard (sa.contains(A.id) && sb.contains(B.id)) || (sa.contains(B.id) && sb.contains(A.id)) else { continue }
                } else if let sa = options.setA { guard sa.contains(A.id) || sa.contains(B.id) else { continue } }
                if exempt.contains(key(A.id, B.id)) { continue }
                if !options.solidPairs && isEntity.contains(A.id) && isEntity.contains(B.id) { continue }
                guard let ov = overlap(A.box, B.box, tol) else { continue }
                if let c = clash(A, B, ov, tol) { out.append(c) }
            }
        }
        return out.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
    }

    static func overlap(_ a: BBox3, _ b: BBox3, _ tol: Double) -> BBox3? {
        let mn = Vec3(max(a.min.x, b.min.x), max(a.min.y, b.min.y), max(a.min.z, b.min.z))
        let mx = Vec3(min(a.max.x, b.max.x), min(a.max.y, b.max.y), min(a.max.z, b.max.z))
        guard mx.x - mn.x > tol, mx.y - mn.y > tol, mx.z - mn.z > tol else { return nil }
        return BBox3(min: mn, max: mx)
    }

    static func triBox(_ t: (Vec3, Vec3, Vec3)) -> BBox3 { var b = BBox3.empty; b.add(t.0); b.add(t.1); b.add(t.2); return b }
    static func boxesTouch(_ a: BBox3, _ b: BBox3) -> Bool {
        !(a.max.x < b.min.x || b.max.x < a.min.x || a.max.y < b.min.y || b.max.y < a.min.y || a.max.z < b.min.z || b.max.z < a.min.z)
    }

    static func clash(_ A: Body, _ B: Body, _ ov: BBox3, _ tol: Double) -> Clash? {
        let region = BBox3(min: ov.min - Vec3(tol, tol, tol), max: ov.max + Vec3(tol, tol, tol))
        let ta = A.tris.filter { boxesTouch(triBox($0), region) }
        let tb = B.tris.filter { boxesTouch(triBox($0), region) }.map { ($0, triBox($0)) }
        for x in ta {
            let bx = triBox(x)
            for (y, by) in tb where boxesTouch(bx, by) {
                if let p = intersect(x, y, eps: tol) {
                    return Clash(a: A.id, b: B.id, kindA: A.kind, kindB: B.kind, point: p, bounds: ov, contained: false)
                }
            }
        }
        // Containment: one body entirely inside the other (no surface crossings).
        if contains(A, point: B.tris[0].0, box: A.box) && contains(A, point: B.box.center, box: A.box) {
            return Clash(a: A.id, b: B.id, kindA: A.kind, kindB: B.kind, point: B.box.center, bounds: ov, contained: true)
        }
        if contains(B, point: A.tris[0].0, box: B.box) && contains(B, point: A.box.center, box: B.box) {
            return Clash(a: A.id, b: B.id, kindA: A.kind, kindB: B.kind, point: A.box.center, bounds: ov, contained: true)
        }
        return nil
    }

    /// Ray-parity point-in-mesh test (closed meshes).
    static func contains(_ b: Body, point p: Vec3, box: BBox3) -> Bool {
        guard p.x > box.min.x, p.x < box.max.x, p.y > box.min.y, p.y < box.max.y, p.z > box.min.z, p.z < box.max.z else { return false }
        let dir = Vec3(1, 0.0137, 0.0071).normalized
        var hits = 0
        for t in b.tris {
            let e1 = t.1 - t.0, e2 = t.2 - t.0
            let h = dir.cross(e2)
            let a = e1.dot(h)
            if abs(a) < 1e-12 { continue }
            let f = 1 / a
            let s = p - t.0
            let u = f * s.dot(h)
            if u < 0 || u > 1 { continue }
            let q = s.cross(e1)
            let v = f * dir.dot(q)
            if v < 0 || u + v > 1 { continue }
            if f * e2.dot(q) > 1e-9 { hits += 1 }
        }
        return hits % 2 == 1
    }

    /// Strict triangle–triangle intersection: both triangles must cross each other's plane by more than `eps`
    /// and their intersection intervals must overlap by more than `eps`. Returns a point on the shared segment.
    public static func intersect(_ t1: (Vec3, Vec3, Vec3), _ t2: (Vec3, Vec3, Vec3), eps: Double) -> Vec3? {
        let n2raw = (t2.1 - t2.0).cross(t2.2 - t2.0)
        let n1raw = (t1.1 - t1.0).cross(t1.2 - t1.0)
        guard n1raw.length > 1e-12, n2raw.length > 1e-12 else { return nil }
        let n1 = n1raw.normalized, n2 = n2raw.normalized
        let d1 = [t1.0, t1.1, t1.2].map { n2.dot($0 - t2.0) }
        guard d1.contains(where: { $0 > eps }) && d1.contains(where: { $0 < -eps }) else { return nil }
        let d2 = [t2.0, t2.1, t2.2].map { n1.dot($0 - t1.0) }
        guard d2.contains(where: { $0 > eps }) && d2.contains(where: { $0 < -eps }) else { return nil }
        let D = n1.cross(n2)
        guard D.length > 1e-12 else { return nil }
        func segment(_ v: [Vec3], _ d: [Double]) -> (Vec3, Vec3)? {
            var pts: [Vec3] = []
            for i in 0..<3 {
                let j = (i + 1) % 3
                if abs(d[i]) <= eps * 1e-3 { pts.append(v[i]) }
                if (d[i] > 0 && d[j] < 0) || (d[i] < 0 && d[j] > 0) {
                    let t = d[i] / (d[i] - d[j])
                    pts.append(v[i] + (v[j] - v[i]) * t)
                }
            }
            guard pts.count >= 2 else { return nil }
            var lo = pts[0], hi = pts[0]
            for p in pts { if p.dot(D) < lo.dot(D) { lo = p }; if p.dot(D) > hi.dot(D) { hi = p } }
            return (lo, hi)
        }
        guard let s1 = segment([t1.0, t1.1, t1.2], d1), let s2 = segment([t2.0, t2.1, t2.2], d2) else { return nil }
        let Dn = D.normalized
        let a0 = s1.0.dot(Dn), a1 = s1.1.dot(Dn), b0 = s2.0.dot(Dn), b1 = s2.1.dot(Dn)
        let lo = max(a0, b0), hi = min(a1, b1)
        guard hi - lo > eps else { return nil }
        let mid = (lo + hi) / 2
        let span = a1 - a0
        return span > 1e-12 ? s1.0 + (s1.1 - s1.0) * ((mid - a0) / span) : s1.0
    }

    public static func csv(_ clashes: [Clash]) -> String {
        var rows = [["#", "id_a", "kind_a", "id_b", "kind_b", "x", "y", "z", "contained"]]
        for (i, c) in clashes.enumerated() {
            rows.append(["\(i + 1)", "\(c.a)", c.kindA, "\(c.b)", c.kindB, fmt(c.point.x, 1), fmt(c.point.y, 1), fmt(c.point.z, 1), c.contained ? "yes" : "no"])
        }
        return CSVText.make(rows)
    }
}
