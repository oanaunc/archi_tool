// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 3D object snaps (PRC-022, 3DOSNAP): vertex, edge midpoint, face centre, knot, perpendicular to face and nearest to
/// face on 3D solids and meshes. Modes are the AutoCAD 3DOSMODE bits (1 = off, 2 vertex, 4 midpoint, 8 face centre,
/// 16 knot, 32 perpendicular, 64 nearest), stored as a document variable.
///
/// Two entry points: `find(rayOrigin:direction:…)` for a 3D view (aperture = distance from the pick ray) and the plan
/// snaps offered through `Snap.find` (projected, with `elevation(at:)` giving back the Z of the snapped point so 3D point
/// input keeps it).
public enum Snap3D {
    public enum Mode: Int, CaseIterable {
        case vertex = 2, midpoint = 4, faceCenter = 8, knot = 16, perpendicular = 32, nearest = 64
        public var keyword: String {
            switch self {
            case .vertex: return "ZVertex"; case .midpoint: return "ZMidpoint"; case .faceCenter: return "ZCenter"
            case .knot: return "ZKnot"; case .perpendicular: return "ZPerpendicular"; case .nearest: return "ZNearest"
            }
        }
    }
    public static let variable = "3DOSMODE"

    public static func modes(_ doc: ArchiDocument) -> Set<Mode> {
        guard let v = doc.variable(variable).flatMap(Int.init), v & 1 == 0 else { return [] }
        return Set(Mode.allCases.filter { v & $0.rawValue != 0 })
    }
    public static func setModes(_ m: Set<Mode>, doc: inout ArchiDocument) {
        let v = m.reduce(0) { $0 | $1.rawValue }
        doc.setVariable(variable, String(v == 0 ? 1 : v))
    }

    public struct Result: Equatable {
        public var point: Vec3
        public var mode: Mode
        public var entity: EntityID?
    }

    /// Snap features of one object.
    public struct Features {
        public var vertices: [Vec3] = []
        public var midpoints: [Vec3] = []
        public var faceCenters: [Vec3] = []
        public var knots: [Vec3] = []
        /// Triangles (a, b, c) for face hits.
        public var triangles: [(Vec3, Vec3, Vec3)] = []
        public var bounds = BBox2.empty
    }

    static let lock = NSLock()
    nonisolated(unsafe) static var cache: [Int: Features] = [:]

    static func key(_ v: Vec3) -> String { String(format: "%.6f,%.6f,%.6f", v.x, v.y, v.z) }

    /// Features of a drafting object (solids and meshes; 3D polylines/splines give their knots). Nil for flat objects.
    public static func features(_ e: Entity, doc: ArchiDocument) -> Features? {
        switch e.geometry {
        case .solid: break
        case .spline(let s):
            var f = Features()
            let z = e.props["elevation"].flatMap(Double.init) ?? 0
            f.knots = (s.fitPoints.isEmpty ? s.controlPoints : s.fitPoints).map { Vec3($0.x, $0.y, z) }
            f.bounds = BBox2(points: f.knots.map(\.xy))
            return f.knots.isEmpty ? nil : f
        default: return nil
        }
        var h = Hasher(); h.combine(e.geometry); h.combine(e.props["elevation"]); h.combine(e.props["z"])
        let k = h.finalize()
        lock.lock()
        if let c = cache[k] { lock.unlock(); return c }
        lock.unlock()
        let groups = MeshBuilder.groups(for: e, doc: doc)
        guard !groups.isEmpty else { return nil }
        var f = Features()
        var seenV = Set<String>(), seenM = Set<String>()
        for g in groups {
            let m = g.mesh
            var tris: [(Vec3, Vec3, Vec3)] = []
            var i = 0
            while i + 2 < m.indices.count {
                let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
                tris.append((a, b, c)); i += 3
            }
            f.triangles += tris
            var edges = g.edges
            if edges.isEmpty { edges = featureEdges(tris) }
            for pl in edges where pl.count >= 2 {
                for p in pl where seenV.insert(key(p)).inserted { f.vertices.append(p) }
                for j in 0..<(pl.count - 1) {
                    let mid = (pl[j] + pl[j + 1]) / 2
                    if seenM.insert(key(mid)).inserted { f.midpoints.append(mid) }
                }
            }
            f.faceCenters += faceCenters(tris)
        }
        f.bounds = BBox2(points: f.triangles.flatMap { [$0.0.xy, $0.1.xy, $0.2.xy] } + f.vertices.map(\.xy))
        lock.lock()
        if cache.count > 256 { cache.removeAll() }
        cache[k] = f
        lock.unlock()
        return f
    }

    static func normal(_ t: (Vec3, Vec3, Vec3)) -> Vec3 { (t.1 - t.0).cross(t.2 - t.0) }

    /// Edges between triangles that are not coplanar, plus boundary edges.
    static func featureEdges(_ tris: [(Vec3, Vec3, Vec3)]) -> [[Vec3]] {
        var map: [String: (Vec3, Vec3, [Vec3])] = [:]
        for t in tris {
            let n = normal(t).normalized
            for (a, b) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] {
                let ka = key(a), kb = key(b)
                let k = ka < kb ? ka + "|" + kb : kb + "|" + ka
                map[k, default: (a, b, [])].2.append(n)
            }
        }
        return map.values.compactMap { e in
            if e.2.count == 1 { return [e.0, e.1] }
            if e.2.count == 2, e.2[0].dot(e.2[1]) < cos(1 * .pi / 180) { return [e.0, e.1] }
            return nil
        }
    }

    /// Area centroids of the planar faces (coplanar triangles connected by shared vertices).
    static func faceCenters(_ tris: [(Vec3, Vec3, Vec3)]) -> [Vec3] {
        guard !tris.isEmpty else { return [] }
        var parent = Array(0..<tris.count)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let normals = tris.map { normal($0).normalized }
        var byVertex: [String: [Int]] = [:]
        for (i, t) in tris.enumerated() { for p in [t.0, t.1, t.2] { byVertex[key(p), default: []].append(i) } }
        for (_, list) in byVertex {
            for a in 0..<list.count {
                for b in (a + 1)..<max(a + 1, list.count) {
                    let i = list[a], j = list[b]
                    guard normals[i].dot(normals[j]) > 1 - 1e-6, abs((tris[j].0 - tris[i].0).dot(normals[i])) < 1e-6 * max(1, tris[i].0.length) else { continue }
                    let ri = find(i), rj = find(j)
                    if ri != rj { parent[ri] = rj }
                }
            }
        }
        var acc: [Int: (Vec3, Double)] = [:]
        for (i, t) in tris.enumerated() {
            let area = normal(t).length / 2
            guard area > 1e-12 else { continue }
            let c = (t.0 + t.1 + t.2) / 3
            let r = find(i)
            let cur = acc[r] ?? (.zero, 0)
            acc[r] = (cur.0 + c * area, cur.1 + area)
        }
        return acc.values.filter { $0.1 > 1e-12 }.map { $0.0 / $0.1 }
    }

    /// Ray–triangle intersection (Möller–Trumbore): distance along the ray, or nil.
    public static func hit(_ o: Vec3, _ d: Vec3, _ t: (Vec3, Vec3, Vec3)) -> Double? {
        let e1 = t.1 - t.0, e2 = t.2 - t.0
        let p = d.cross(e2)
        let det = e1.dot(p)
        guard abs(det) > 1e-12 else { return nil }
        let inv = 1 / det
        let s = o - t.0
        let u = s.dot(p) * inv
        guard u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        let q = s.cross(e1)
        let v = d.dot(q) * inv
        guard v >= -1e-9, u + v <= 1 + 1e-9 else { return nil }
        let dist = e2.dot(q) * inv
        return dist >= 0 ? dist : nil
    }

    static func distanceToRay(_ p: Vec3, _ o: Vec3, _ d: Vec3) -> Double {
        let t = max(0, (p - o).dot(d))
        return p.distance(to: o + d * t)
    }

    /// 3D snap along a pick ray (3D views). `tolerance` is the aperture in world units at the picked depth.
    public static func find(rayOrigin o: Vec3, direction d0: Vec3, doc: ArchiDocument, tolerance: Double, base: Vec3? = nil, modes ms: Set<Mode>? = nil) -> Result? {
        let modes = ms ?? self.modes(doc)
        guard !modes.isEmpty else { return nil }
        let d = d0.normalized
        guard d.length > 0.5 else { return nil }
        var best: (tier: Int, dist: Double, depth: Double, res: Result)?
        func offer(_ p: Vec3, _ m: Mode, _ id: EntityID, tier: Int) {
            guard modes.contains(m) else { return }
            let dist = distanceToRay(p, o, d)
            guard dist <= tolerance else { return }
            let depth = (p - o).dot(d)
            if let b = best {
                if tier > b.tier { return }
                // Equal distance from the ray (points behind each other): the one nearer the eye wins.
                if tier == b.tier && (dist > b.dist + 1e-9 || (abs(dist - b.dist) <= 1e-9 && depth >= b.depth)) { return }
            }
            best = (tier, dist, depth, Result(point: p, mode: m, entity: id))
        }
        var nearestHit: (Double, Vec3, (Vec3, Vec3, Vec3), EntityID)?
        var hitTriangles: [EntityID: [(Vec3, Vec3, Vec3)]] = [:]
        for e in doc.entities where doc.isVisible(layer: e.layer) {
            guard let f = features(e, doc: doc) else { continue }
            for p in f.vertices { offer(p, .vertex, e.id, tier: 0) }
            for p in f.knots { offer(p, .knot, e.id, tier: 0) }
            for p in f.midpoints { offer(p, .midpoint, e.id, tier: 1) }
            for p in f.faceCenters { offer(p, .faceCenter, e.id, tier: 1) }
            if modes.contains(.nearest) || modes.contains(.perpendicular) {
                for t in f.triangles { if let h = hit(o, d, t), h < (nearestHit?.0 ?? .infinity) { nearestHit = (h, o + d * h, t, e.id) } }
                hitTriangles[e.id] = f.triangles
            }
        }
        if best == nil, let h = nearestHit {
            if modes.contains(.perpendicular), let b = base {
                let n = normal(h.2).normalized
                let foot = b - n * (b - h.2.0).dot(n)
                // Only when the foot lies inside the planar face that was hit.
                let face = (hitTriangles[h.3] ?? []).filter { t in
                    let tn = normal(t).normalized
                    return tn.dot(n) > 1 - 1e-6 && abs((t.0 - h.2.0).dot(n)) < 1e-6 * max(1, h.2.0.length)
                }
                if face.contains(where: { hit(foot + n, -n, $0) != nil }) { return Result(point: foot, mode: .perpendicular, entity: h.3) }
            }
            if modes.contains(.nearest) { return Result(point: h.1, mode: .nearest, entity: h.3) }
        }
        return best?.res
    }

    /// Plan snap candidates of the solids near a cursor (projected) for `Snap.find`: (point, 2D snap kind, entity).
    public static func planCandidates(cursor: Vec2, tolerance: Double, doc: ArchiDocument) -> [(Vec2, SnapKind, EntityID)] {
        let modes = self.modes(doc)
        guard !modes.isEmpty else { return [] }
        var out: [(Vec2, SnapKind, EntityID)] = []
        for e in doc.entities where doc.isVisible(layer: e.layer) {
            guard let f = features(e, doc: doc), f.bounds.expanded(by: tolerance).contains(cursor) else { continue }
            if modes.contains(.vertex) { out += f.vertices.map { ($0.xy, .endpoint, e.id) } }
            if modes.contains(.knot) { out += f.knots.map { ($0.xy, .node, e.id) } }
            if modes.contains(.midpoint) { out += f.midpoints.map { ($0.xy, .midpoint, e.id) } }
            if modes.contains(.faceCenter) { out += f.faceCenters.map { ($0.xy, .center, e.id) } }
            if modes.contains(.nearest), topHit(cursor, f) != nil { out.append((cursor, .nearest, e.id)) }
        }
        return out.filter { $0.0.distance(to: cursor) <= tolerance }
    }

    static func topHit(_ p: Vec2, _ f: Features) -> Double? {
        var top: Double?
        let o = Vec3(p.x, p.y, 1e12)
        for t in f.triangles {
            if let h = hit(o, Vec3(0, 0, -1), t) { let z = 1e12 - h; if z > (top ?? -.infinity) { top = z } }
        }
        return top
    }

    /// Elevation of a snapped plan point: the highest vertex / edge midpoint / face centre / knot at that location, or
    /// (nearest mode) the top face under it. Nil when no 3D snap feature is there.
    public static func elevation(at p: Vec2, doc: ArchiDocument, tolerance: Double = 1e-6) -> Double? {
        let modes = self.modes(doc)
        guard !modes.isEmpty else { return nil }
        var z: Double?
        for e in doc.entities where doc.isVisible(layer: e.layer) {
            guard let f = features(e, doc: doc), f.bounds.expanded(by: tolerance).contains(p) else { continue }
            var pts: [Vec3] = []
            if modes.contains(.vertex) { pts += f.vertices }
            if modes.contains(.knot) { pts += f.knots }
            if modes.contains(.midpoint) { pts += f.midpoints }
            if modes.contains(.faceCenter) { pts += f.faceCenters }
            for q in pts where q.xy.distance(to: p) <= tolerance { z = max(z ?? -.infinity, q.z) }
            if z == nil, modes.contains(.nearest), let h = topHit(p, f) { z = h }
        }
        return z
    }
}

/// Dynamic UCS (PRC-036, DUCS / UCSDETECT = 1): while picking points, the face of a 3D solid under the cursor acts as a
/// temporary work plane — picked points land on that face (its elevation, sloped faces included), and `face(at:)` gives
/// the plane (origin, normal, X axis along the face's horizontal edge direction) for the UCS icon.
public enum DynamicUCS {
    public static let variable = "UCSDETECT"
    public static func isOn(_ doc: ArchiDocument) -> Bool { doc.variable(variable) == "1" }

    public struct Face: Equatable {
        public var origin: Vec3
        public var normal: Vec3
        public var xAxis: Vec3
        public var entity: EntityID
    }

    /// The topmost solid face under a plan point.
    public static func face(at p: Vec2, doc: ArchiDocument) -> Face? {
        var best: (z: Double, t: (Vec3, Vec3, Vec3), id: EntityID)?
        for e in doc.entities where doc.isVisible(layer: e.layer) {
            guard case .solid = e.geometry, let f = Snap3D.features(e, doc: doc), f.bounds.contains(p) else { continue }
            // Ray from just above the solid (a far start point would lose precision in the elevation).
            let top = (f.triangles.map { max($0.0.z, $0.1.z, $0.2.z) }.max() ?? 0) + 1
            let o = Vec3(p.x, p.y, top)
            for t in f.triangles {
                guard let h = Snap3D.hit(o, Vec3(0, 0, -1), t) else { continue }
                let z = top - h
                if z > (best?.z ?? -.infinity) { best = (z, t, e.id) }
            }
        }
        guard let b = best else { return nil }
        var n = Snap3D.normal(b.t).normalized
        if n.z < 0 { n = -n }
        // X axis: horizontal direction in the face (world X for horizontal faces).
        var x = Vec3.unitZ.cross(n)
        if x.length < 1e-9 { x = Vec3(1, 0, 0) } else { x = x.normalized }
        return Face(origin: Vec3(p.x, p.y, b.z), normal: n, xAxis: x, entity: b.id)
    }

    /// Elevation of a picked plan point on the face under it (nil when DUCS is off or there is no face).
    public static func elevation(at p: Vec2, doc: ArchiDocument) -> Double? {
        guard isOn(doc) else { return nil }
        return face(at: p, doc: doc)?.origin.z
    }

    /// The face under a plan point when DUCS is on (nil otherwise).
    public static func activeFace(at p: Vec2, doc: ArchiDocument) -> Face? { isOn(doc) ? face(at: p, doc: doc) : nil }
}

extension DynamicUCS.Face {
    /// Face Y axis (normal × X).
    public var yAxis: Vec3 { normal.cross(xAxis).normalized }
    public var isHorizontal: Bool { normal.z > 1 - 1e-9 }
    /// Face-local coordinates (x along `xAxis`, y along `yAxis`, z along the normal) → world.
    public func toWorld(_ l: Vec3) -> Vec3 { origin + xAxis * l.x + yAxis * l.y + normal * l.z }
    public func vectorToWorld(_ l: Vec3) -> Vec3 { xAxis * l.x + yAxis * l.y + normal * l.z }
    /// World → face-local coordinates.
    public func fromWorld(_ w: Vec3) -> Vec3 { let d = w - origin; return Vec3(d.dot(xAxis), d.dot(yAxis), d.dot(normal)) }
    /// Point of the face plane above or below a plan point (nil for a vertical plane).
    public func planePoint(_ p: Vec2) -> Vec3? {
        guard abs(normal.z) > 1e-9 else { return nil }
        let z = origin.z - ((p.x - origin.x) * normal.x + (p.y - origin.y) * normal.y) / normal.z
        return Vec3(p.x, p.y, z)
    }
    /// The face frame with its X axis turned to a plan angle (used on horizontal faces to follow the current UCS).
    public func rotatedX(to angle: Double) -> DynamicUCS.Face {
        guard isHorizontal else { return self }
        var f = self; f.xAxis = Vec3(cos(angle), sin(angle), 0); return f
    }
}
