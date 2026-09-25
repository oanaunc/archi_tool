// Oanarina Archi Tool — GPL-3.0-or-later
// Point cloud tools: ASPRS LAS 1.0–1.4 reader (IO-049; point formats 0–10, scale/offset, RGB, intensity, classification;
// LAZ needs decompressing to LAS first), an octree with level-of-detail sampling and section-box clipping (IO-051),
// nearest-point snapping and local plane fitting (IO-052), and RANSAC plane detection that turns vertical planes into
// walls and horizontal planes into floor slabs (IO-053).
import Foundation

// MARK: - LAS

public enum LASReader {
    public struct Header: Hashable {
        public var versionMajor: Int, versionMinor: Int
        public var pointFormat: Int, recordLength: Int
        public var pointCount: Int
        public var offsetToPoints: Int
        public var scale: Vec3, offset: Vec3
        public var min: Vec3, max: Vec3
    }

    static func u8(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) }
    static func u16(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
    static func u32(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
    static func i32(_ d: [UInt8], _ o: Int) -> Int { Int(Int32(bitPattern: UInt32(u32(d, o)))) }
    static func u64(_ d: [UInt8], _ o: Int) -> Int { u32(d, o) | u32(d, o + 4) << 32 }
    static func f64(_ d: [UInt8], _ o: Int) -> Double {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(d[o + k]) << (8 * UInt64(k)) }
        return Double(bitPattern: v)
    }

    public static func header(_ d: [UInt8]) throws -> Header {
        guard d.count >= 227, d[0] == 0x4C, d[1] == 0x41, d[2] == 0x53, d[3] == 0x46 else { throw PointCloud.CloudError.invalid("Not a LAS file (no LASF signature).") }
        let fmtByte = u8(d, 104)
        if fmtByte & 0x80 != 0 || fmtByte & 0x40 != 0 { throw PointCloud.CloudError.invalid("Compressed LAZ data: decompress to LAS first (e.g. laszip -i file.laz -o file.las).") }
        var h = Header(versionMajor: u8(d, 24), versionMinor: u8(d, 25), pointFormat: fmtByte & 0x3F, recordLength: u16(d, 105),
                       pointCount: u32(d, 107), offsetToPoints: u32(d, 96),
                       scale: Vec3(f64(d, 131), f64(d, 139), f64(d, 147)), offset: Vec3(f64(d, 155), f64(d, 163), f64(d, 171)),
                       min: Vec3(f64(d, 187), f64(d, 203), f64(d, 219)), max: Vec3(f64(d, 179), f64(d, 195), f64(d, 211)))
        if h.versionMinor >= 4, d.count >= 255, h.pointCount == 0 { h.pointCount = u64(d, 247) }
        guard (0...10).contains(h.pointFormat) else { throw PointCloud.CloudError.invalid("Unsupported LAS point format \(h.pointFormat).") }
        return h
    }

    /// Byte offset of RGB in a record (nil = no colour) and of the classification byte.
    static func layout(_ f: Int) -> (rgb: Int?, cls: Int) {
        switch f {
        case 2: return (20, 15)
        case 3, 5: return (28, 15)
        case 7, 8, 10: return (30, 16)
        case 0, 1, 4: return (nil, 15)
        default: return (nil, 16)   // 6, 9
        }
    }

    /// Reads up to `maxPoints` evenly spaced points (all when 0), in file units (usually metres). Props: classification.
    public static func read(_ data: Data, maxPoints: Int = 0) throws -> (header: Header, points: [CloudPoint], classes: [UInt8]) {
        let d = [UInt8](data)
        let h = try header(d)
        let rec = h.recordLength
        guard rec >= 20, h.offsetToPoints > 0 else { throw PointCloud.CloudError.invalid("Invalid LAS header.") }
        let available = max(0, (d.count - h.offsetToPoints) / rec)
        let n = min(h.pointCount, available)
        let step = maxPoints > 0 && n > maxPoints ? Double(n) / Double(maxPoints) : 1
        let count = maxPoints > 0 ? min(n, maxPoints) : n
        let lay = layout(h.pointFormat)
        var pts: [CloudPoint] = []; pts.reserveCapacity(count)
        var classes: [UInt8] = []; classes.reserveCapacity(count)
        // RGB may be 8- or 16-bit: detect over the sample.
        var raw: [(Vec3, Double, (Int, Int, Int)?, UInt8)] = []
        raw.reserveCapacity(count)
        var maxC = 0
        for i in 0..<count {
            let idx = min(n - 1, Int(Double(i) * step))
            let o = h.offsetToPoints + idx * rec
            let x = Double(i32(d, o)) * h.scale.x + h.offset.x
            let y = Double(i32(d, o + 4)) * h.scale.y + h.offset.y
            let z = Double(i32(d, o + 8)) * h.scale.z + h.offset.z
            let inten = Double(u16(d, o + 12))
            var rgb: (Int, Int, Int)?
            if let c = lay.rgb, c + 6 <= rec {
                rgb = (u16(d, o + c), u16(d, o + c + 2), u16(d, o + c + 4))
                maxC = max(maxC, rgb!.0, rgb!.1, rgb!.2)
            }
            let cls = lay.cls < rec ? d[o + lay.cls] & (h.pointFormat >= 6 ? 0xFF : 0x1F) : 0
            raw.append((Vec3(x, y, z), inten, rgb, cls))
        }
        let shift = maxC > 255 ? 8 : 0
        for r in raw {
            var cp = CloudPoint(r.0, intensity: r.1)
            if let c = r.2 { cp.color = (UInt8(truncatingIfNeeded: c.0 >> shift), UInt8(truncatingIfNeeded: c.1 >> shift), UInt8(truncatingIfNeeded: c.2 >> shift)) }
            pts.append(cp); classes.append(r.3)
        }
        return (h, pts, classes)
    }

    /// Point entities (millimetres × `scale`), with "class" props; points are shifted by `origin` (file units) first.
    public static func entities(_ data: Data, options: PointCloudOptions, origin: Vec3 = .zero) throws -> (entities: [Entity], total: Int) {
        let r = try read(data, maxPoints: options.maxPoints > 0 ? options.maxPoints * 4 : 0)
        var cps = r.points
        for i in cps.indices { cps[i].p = cps[i].p - origin }
        var ents = PointCloud.entities(cps, options: options)
        // Keep classification for the retained points (decimation keeps order; match by position).
        if ents.count == cps.count { for i in ents.indices where r.classes[i] != 0 { ents[i].props["class"] = "\(r.classes[i])" } }
        return (ents, r.header.pointCount)
    }

    /// Writes a LAS 1.2 point format 2 file (points in file units with colour) — for tests and exchange.
    public static func write(_ pts: [CloudPoint], scale: Double = 0.001) -> Data {
        var out = [UInt8](repeating: 0, count: 227)
        func put16(_ v: Int, _ o: Int) { out[o] = UInt8(v & 0xFF); out[o + 1] = UInt8((v >> 8) & 0xFF) }
        func put32(_ v: Int, _ o: Int) { for k in 0..<4 { out[o + k] = UInt8((v >> (8 * k)) & 0xFF) } }
        func putF(_ v: Double, _ o: Int) { let b = v.bitPattern; for k in 0..<8 { out[o + k] = UInt8((b >> (8 * UInt64(k))) & 0xFF) } }
        out[0] = 0x4C; out[1] = 0x41; out[2] = 0x53; out[3] = 0x46
        out[24] = 1; out[25] = 2
        put16(227, 94); put32(227, 96); put32(0, 100); out[104] = 2; put16(26, 105); put32(pts.count, 107)
        var b = BBox3.empty; for p in pts { b.add(p.p) }
        if b.isEmpty { b = BBox3(min: .zero, max: .zero) }
        putF(scale, 131); putF(scale, 139); putF(scale, 147); putF(b.min.x, 155); putF(b.min.y, 163); putF(b.min.z, 171)
        putF(b.max.x, 179); putF(b.min.x, 187); putF(b.max.y, 195); putF(b.min.y, 203); putF(b.max.z, 211); putF(b.min.z, 219)
        for p in pts {
            var r = [UInt8](repeating: 0, count: 26)
            func w32(_ v: Int, _ o: Int) { for k in 0..<4 { r[o + k] = UInt8((v >> (8 * k)) & 0xFF) } }
            func w16(_ v: Int, _ o: Int) { r[o] = UInt8(v & 0xFF); r[o + 1] = UInt8((v >> 8) & 0xFF) }
            w32(Int(((p.p.x - b.min.x) / scale).rounded()), 0); w32(Int(((p.p.y - b.min.y) / scale).rounded()), 4); w32(Int(((p.p.z - b.min.z) / scale).rounded()), 8)
            w16(Int(p.intensity ?? 0), 12)
            r[15] = 2
            if let c = p.color { w16(Int(c.0) << 8, 20); w16(Int(c.1) << 8, 22); w16(Int(c.2) << 8, 24) }
            out += r
        }
        return Data(out)
    }
}

// MARK: - Octree with LOD and clipping

public final class PointOctree {
    public let points: [Vec3]
    final class Node {
        var box: BBox3
        var indices: [Int] = []          // leaf points
        var sample: [Int] = []           // LOD representatives (≤ capacity)
        var children: [Node] = []
        var count = 0
        init(box: BBox3) { self.box = box }
    }
    let root: Node
    public let capacity: Int
    public private(set) var depth = 0

    public init(points: [Vec3], capacity: Int = 256, maxDepth: Int = 12) {
        self.points = points
        self.capacity = max(8, capacity)
        var b = BBox3.empty
        for p in points { b.add(p) }
        if b.isEmpty { b = BBox3(min: .zero, max: .zero) }
        // Cube around the points.
        let s = max(b.size.x, b.size.y, b.size.z, 1e-9) / 2
        let c = b.center
        root = Node(box: BBox3(min: c - Vec3(s, s, s), max: c + Vec3(s, s, s)))
        root.indices = Array(points.indices)
        build(root, level: 0, maxDepth: maxDepth)
    }

    func build(_ n: Node, level: Int, maxDepth: Int) {
        n.count = n.indices.count
        depth = max(depth, level + 1)
        // Evenly spread representatives for coarse levels.
        let step = max(1, n.indices.count / capacity)
        n.sample = stride(from: 0, to: n.indices.count, by: step).prefix(capacity).map { n.indices[$0] }
        guard n.indices.count > capacity, level < maxDepth else { return }
        let c = n.box.center
        var parts = Array(repeating: [Int](), count: 8)
        for i in n.indices {
            let p = points[i]
            parts[(p.x >= c.x ? 1 : 0) | (p.y >= c.y ? 2 : 0) | (p.z >= c.z ? 4 : 0)].append(i)
        }
        for (k, idx) in parts.enumerated() where !idx.isEmpty {
            let mn = Vec3(k & 1 != 0 ? c.x : n.box.min.x, k & 2 != 0 ? c.y : n.box.min.y, k & 4 != 0 ? c.z : n.box.min.z)
            let mx = Vec3(k & 1 != 0 ? n.box.max.x : c.x, k & 2 != 0 ? n.box.max.y : c.y, k & 4 != 0 ? n.box.max.z : c.z)
            let ch = Node(box: BBox3(min: mn, max: mx))
            ch.indices = idx
            n.children.append(ch)
            build(ch, level: level + 1, maxDepth: maxDepth)
        }
        n.indices = []
    }

    static func intersects(_ a: BBox3, _ b: BBox3) -> Bool {
        !(a.min.x > b.max.x || a.max.x < b.min.x || a.min.y > b.max.y || a.max.y < b.min.y || a.min.z > b.max.z || a.max.z < b.min.z)
    }
    static func contains(_ b: BBox3, _ p: Vec3) -> Bool {
        p.x >= b.min.x && p.x <= b.max.x && p.y >= b.min.y && p.y <= b.max.y && p.z >= b.min.z && p.z <= b.max.z
    }

    /// Points to draw inside a section box within a budget: whole nodes are refined breadth-first (largest first) until the
    /// budget is reached; unrefined nodes contribute their representatives. Clipping is exact (every returned point lies
    /// in `clip`).
    public func lod(clip: BBox3? = nil, budget: Int) -> [Int] {
        var out: [Int] = []
        var frontier: [Node] = [root]
        var used = 0
        // Refine while the budget allows replacing a node's sample by its children's samples.
        var refined: [Node] = []
        while let n = frontier.first {
            frontier.removeFirst()
            if let c = clip, !PointOctree.intersects(n.box, c) { continue }
            let childCost = n.children.reduce(0) { $0 + $1.sample.count }
            if !n.children.isEmpty && used + childCost <= budget {
                frontier += n.children.sorted { $0.count > $1.count }
            } else if n.children.isEmpty && used + n.count <= budget {
                refined.append(n); used += n.count
            } else {
                out += n.sample; used += n.sample.count
            }
        }
        for n in refined { out += n.indices }
        if let c = clip { out = out.filter { PointOctree.contains(c, points[$0]) } }
        return Array(out.prefix(budget))
    }

    /// Points inside a box (exact).
    public func points(in box: BBox3) -> [Int] {
        var out: [Int] = []
        var stack = [root]
        while let n = stack.popLast() {
            guard PointOctree.intersects(n.box, box) else { continue }
            if n.children.isEmpty { out += n.indices.filter { PointOctree.contains(box, points[$0]) } } else { stack += n.children }
        }
        return out
    }

    /// Nearest point to `p` (3D), optionally ignoring z (plan snapping). Returns index and distance.
    public func nearest(to p: Vec3, planOnly: Bool = false, maxDistance: Double = .infinity) -> (index: Int, distance: Double)? {
        var best: (Int, Double)?
        func dist(_ q: Vec3) -> Double { planOnly ? Vec2(q.x - p.x, q.y - p.y).length : q.distance(to: p) }
        func boxDist(_ b: BBox3) -> Double {
            let dx = max(b.min.x - p.x, 0, p.x - b.max.x), dy = max(b.min.y - p.y, 0, p.y - b.max.y)
            let dz = planOnly ? 0 : max(b.min.z - p.z, 0, p.z - b.max.z)
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        var stack = [root]
        while let n = stack.popLast() {
            let bd = boxDist(n.box)
            if bd > min(best?.1 ?? .infinity, maxDistance) { continue }
            if n.children.isEmpty {
                for i in n.indices { let d = dist(points[i]); if d <= maxDistance, d < (best?.1 ?? .infinity) { best = (i, d) } }
            } else {
                stack += n.children.sorted { boxDist($0.box) > boxDist($1.box) }
            }
        }
        return best
    }

    /// Points within `radius` of `p`.
    public func neighbours(_ p: Vec3, radius: Double) -> [Int] {
        points(in: BBox3(min: p - Vec3(radius, radius, radius), max: p + Vec3(radius, radius, radius))).filter { points[$0].distance(to: p) <= radius }
    }
}

// MARK: - Planes

public struct FittedPlane: Hashable {
    public var normal: Vec3        // unit
    public var d: Double           // n·p + d = 0
    public var centroid: Vec3
    public var rms: Double
    public func distance(_ p: Vec3) -> Double { normal.dot(p) + d }
    public var isVertical: Bool { abs(normal.z) < 0.2 }
    public var isHorizontal: Bool { abs(normal.z) > 0.95 }
}

public enum PlaneFit {
    /// Least-squares plane (PCA: normal = eigenvector of the smallest eigenvalue of the covariance, Jacobi iteration).
    public static func fit(_ pts: [Vec3]) -> FittedPlane? {
        guard pts.count >= 3 else { return nil }
        let c = pts.reduce(Vec3.zero) { $0 + $1 } * (1 / Double(pts.count))
        var a = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in pts {
            let q = p - c, v = [q.x, q.y, q.z]
            for i in 0..<3 { for j in 0..<3 { a[i][j] += v[i] * v[j] } }
        }
        var vecs: [[Double]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<50 {
            var p = 0, q = 1, off = abs(a[0][1])
            if abs(a[0][2]) > off { p = 0; q = 2; off = abs(a[0][2]) }
            if abs(a[1][2]) > off { p = 1; q = 2; off = abs(a[1][2]) }
            if off < 1e-15 { break }
            let th = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p])
            let cs = cos(th), sn = sin(th)
            for k in 0..<3 {
                let akp = a[k][p], akq = a[k][q]
                a[k][p] = cs * akp - sn * akq; a[k][q] = sn * akp + cs * akq
            }
            for k in 0..<3 {
                let apk = a[p][k], aqk = a[q][k]
                a[p][k] = cs * apk - sn * aqk; a[q][k] = sn * apk + cs * aqk
            }
            for k in 0..<3 {
                let vkp = vecs[k][p], vkq = vecs[k][q]
                vecs[k][p] = cs * vkp - sn * vkq; vecs[k][q] = sn * vkp + cs * vkq
            }
        }
        let i = (0..<3).min { a[$0][$0] < a[$1][$1] }!
        var n = Vec3(vecs[0][i], vecs[1][i], vecs[2][i])
        let l = n.length
        guard l > 1e-12 else { return nil }
        n = n * (1 / l)
        if n.z < -1e-9 || (abs(n.z) <= 1e-9 && (n.y < 0 || (abs(n.y) <= 1e-9 && n.x < 0))) { n = n * -1 }
        let d = -n.dot(c)
        let rms = (pts.reduce(0) { $0 + pow(n.dot($1) + d, 2) } / Double(pts.count)).squareRoot()
        return FittedPlane(normal: n, d: d, centroid: c, rms: rms)
    }

    /// RANSAC plane detection: repeatedly finds the plane with most inliers (within `tolerance`), refits it, removes its
    /// inliers. Deterministic (seeded). Returns planes with their inlier indices, largest first.
    public static func detect(_ pts: [Vec3], tolerance: Double, minInliers: Int, maxPlanes: Int = 20, iterations: Int = 400, seed: UInt64 = 42) -> [(plane: FittedPlane, inliers: [Int])] {
        var remaining = Array(pts.indices)
        var out: [(FittedPlane, [Int])] = []
        var s = seed
        func rnd(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(max(n, 1))) }
        while out.count < maxPlanes && remaining.count >= max(minInliers, 3) {
            var best: [Int] = []
            for _ in 0..<iterations {
                let a = pts[remaining[rnd(remaining.count)]], b = pts[remaining[rnd(remaining.count)]], c = pts[remaining[rnd(remaining.count)]]
                var n = (b - a).cross(c - a)
                let l = n.length
                guard l > 1e-9 else { continue }
                n = n * (1 / l)
                let d = -n.dot(a)
                var inl: [Int] = []
                for i in remaining where abs(n.dot(pts[i]) + d) <= tolerance { inl.append(i) }
                if inl.count > best.count { best = inl }
            }
            guard best.count >= minInliers, let pl = fit(best.map { pts[$0] }) else { break }
            // Refit and gather final inliers.
            let final = remaining.filter { abs(pl.distance(pts[$0])) <= tolerance }
            guard let p2 = fit(final.map { pts[$0] }) else { break }
            out.append((p2, final))
            let set = Set(final)
            remaining.removeAll { set.contains($0) }
        }
        return out
    }
}

// MARK: - Scan to BIM

public enum ScanToBIM {
    public struct Result { public var walls: [WallGeom]; public var slabs: [(boundary: [Vec2], elevation: Double)]; public var planes: Int }

    /// Walls from vertical planes (their inliers projected on the plane's plan line give the extent and height) and floor
    /// slabs from horizontal planes (convex hull of the inliers). Units of the points (e.g. mm).
    public static func fit(_ pts: [Vec3], tolerance: Double, minInliers: Int, wallThickness: Double) -> Result {
        let planes = PlaneFit.detect(pts, tolerance: tolerance, minInliers: minInliers)
        var walls: [WallGeom] = [], slabs: [([Vec2], Double)] = []
        for (pl, inl) in planes {
            let ps = inl.map { pts[$0] }
            if pl.isVertical {
                // Plan direction along the plane.
                let dir = Vec2(-pl.normal.y, pl.normal.x).normalized
                let o = pl.centroid.xy
                let ts = ps.map { ($0.xy - o).dot(dir) }
                guard let t0 = ts.min(), let t1 = ts.max(), t1 - t0 > tolerance * 4 else { continue }
                let zs = ps.map(\.z)
                let z0 = zs.min() ?? 0, z1 = zs.max() ?? 0
                guard z1 - z0 > tolerance * 4 else { continue }
                // The scanned face is one side of the wall: move the axis half a thickness behind it (away from the
                // side the normal points to, which is where the scanner saw it from — unknown, so centre on the face).
                walls.append(WallGeom(start: o + dir * t0, end: o + dir * t1, thickness: wallThickness, height: z1 - z0, baseOffset: z0))
            } else if pl.isHorizontal {
                let hull = convexHull(ps.map(\.xy))
                guard hull.count >= 3, abs(GeometryOps.signedArea(hull)) > tolerance * tolerance * 100 else { continue }
                slabs.append((hull, pl.centroid.z))
            }
        }
        return Result(walls: walls, slabs: slabs.map { (boundary: $0.0, elevation: $0.1) }, planes: planes.count)
    }

    /// Andrew's monotone chain (counter-clockwise).
    public static func convexHull(_ p0: [Vec2]) -> [Vec2] {
        let p = p0.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard p.count >= 3 else { return p }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in p { while lower.count >= 2 && (lower[lower.count - 1] - lower[lower.count - 2]).cross(q - lower[lower.count - 2]) <= 0 { lower.removeLast() }; lower.append(q) }
        for q in p.reversed() { while upper.count >= 2 && (upper[upper.count - 1] - upper[upper.count - 2]).cross(q - upper[upper.count - 2]) <= 0 { upper.removeLast() }; upper.append(q) }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Point entities of the drawing as 3D points (z from the "z" prop), optionally one layer.
    public static func cloudPoints(_ doc: ArchiDocument, layer: String? = nil) -> (points: [Vec3], ids: [EntityID]) {
        var pts: [Vec3] = [], ids: [EntityID] = []
        for e in doc.entities {
            guard case .point(let p) = e.geometry else { continue }
            if let l = layer, e.layer.caseInsensitiveCompare(l) != .orderedSame { continue }
            pts.append(Vec3(p.x, p.y, Double(e.props["z"] ?? "") ?? 0)); ids.append(e.id)
        }
        return (pts, ids)
    }
}
