// Oanarina Archi Tool — GPL-3.0-or-later
// Blend surfaces between two surface edges with G0 / G1 / G2 continuity (M3D-067) and surface analysis: zebra
// stripes, Gaussian / mean curvature, draft angle and edge continuity (M3D-074). Surfaces are open triangle meshes
// (solids of kind .mesh with props "surface"); curvature uses the angle-deficit and cotangent formulas.
import Foundation

public enum SurfaceBlend {
    public typealias IM = (vertices: [Vec3], triangles: [Int])
    public enum Continuity: Int, CaseIterable { case g0 = 0, g1 = 1, g2 = 2 }

    /// One boundary side of a surface: points, outward cross-boundary tangents and normal curvature across the edge.
    public struct Edge {
        public var points: [Vec3]
        public var outward: [Vec3]
        public var normals: [Vec3]
        public var curvature: [Double]
    }

    // MARK: Boundary sides

    /// Open boundary loops of a mesh, split into sides at corners sharper than `corner` degrees.
    public static func sides(_ m: IM, corner: Double = 30) -> [[Int]] {
        let all = Set(0..<(m.triangles.count / 3))
        var out: [[Int]] = []
        for loop in SubObjects.boundaryLoops(m, faces: all) {
            let n = loop.count
            let cosC = cos(corner * .pi / 180)
            var corners: [Int] = []
            for i in 0..<n {
                let a = m.vertices[loop[(i - 1 + n) % n]], b = m.vertices[loop[i]], c = m.vertices[loop[(i + 1) % n]]
                if (b - a).normalized.dot((c - b).normalized) < cosC { corners.append(i) }
            }
            if corners.isEmpty { out.append(loop + [loop[0]]); continue }
            for k in 0..<corners.count {
                let s = corners[k], e = corners[(k + 1) % corners.count]
                var side: [Int] = [loop[s]]
                var i = s
                repeat { i = (i + 1) % n; side.append(loop[i]) } while i != e
                out.append(side)
            }
        }
        return out
    }

    /// Cross-boundary data of a side (vertex indices along the boundary, surface on the left).
    public static func edge(_ m: IM, side: [Int]) -> Edge? {
        guard side.count >= 2 else { return nil }
        // Directed edge → triangle.
        var tri: [Int64: Int] = [:]
        for f in 0..<(m.triangles.count / 3) {
            for k in 0..<3 { tri[Int64(m.triangles[3 * f + k]) << 32 | Int64(m.triangles[3 * f + (k + 1) % 3])] = f }
        }
        let adj = SubObjects.edgeFaces(m)
        var segOut: [Vec3] = [], segN: [Vec3] = [], segK: [Double] = []
        for i in 0..<(side.count - 1) {
            let a = side[i], b = side[i + 1]
            let f = tri[Int64(a) << 32 | Int64(b)] ?? tri[Int64(b) << 32 | Int64(a)]
            guard let face = f else { return nil }
            let n = SubObjects.normal(m, face)
            let e = (m.vertices[b] - m.vertices[a]).normalized
            var o = e.cross(n).normalized
            // Make sure "outward" points away from the triangle's third vertex.
            let c = (0..<3).map { m.triangles[3 * face + $0] }.first { $0 != a && $0 != b } ?? a
            if (m.vertices[c] - m.vertices[a]).dot(o) > 0 { o = -o }
            segOut.append(o); segN.append(n)
            // Normal curvature across the edge from the neighbouring (inner) triangle.
            var k = 0.0
            let centroid = (m.vertices[m.triangles[3 * face]] + m.vertices[m.triangles[3 * face + 1]] + m.vertices[m.triangles[3 * face + 2]]) / 3
            var best: (Int, Double)? = nil
            for j in 0..<3 {
                let x = m.triangles[3 * face + j], y = m.triangles[3 * face + (j + 1) % 3]
                if SubObjects.key(x, y) == SubObjects.key(a, b) { continue }
                for g in adj[SubObjects.key(x, y)] ?? [] where g != face {
                    let cg = (m.vertices[m.triangles[3 * g]] + m.vertices[m.triangles[3 * g + 1]] + m.vertices[m.triangles[3 * g + 2]]) / 3
                    let d = (centroid - cg).dot(o)
                    if d > 1e-12, best == nil || d > best!.1 { best = (g, d) }
                }
            }
            if let (g, ds) = best {
                let n0 = SubObjects.normal(m, g)
                var nn0 = n0
                if nn0.dot(n) < 0 { nn0 = -nn0 }
                k = -((n - nn0).dot(o)) / ds
            }
            segK.append(k)
        }
        // Vertex values: averages of the adjacent segments.
        var outward: [Vec3] = [], normals: [Vec3] = [], curv: [Double] = []
        let closed = side.first == side.last
        for i in 0..<side.count {
            var idx: [Int] = []
            if i > 0 { idx.append(i - 1) }
            if i < side.count - 1 { idx.append(i) }
            if closed && (i == 0 || i == side.count - 1) { idx = [side.count - 2, 0] }
            outward.append(idx.reduce(Vec3.zero) { $0 + segOut[$1] }.normalized)
            normals.append(idx.reduce(Vec3.zero) { $0 + segN[$1] }.normalized)
            curv.append(idx.reduce(0.0) { $0 + segK[$1] } / Double(idx.count))
        }
        return Edge(points: side.map { m.vertices[$0] }, outward: outward, normals: normals, curvature: curv)
    }

    /// Side of a surface nearest to a point.
    public static func nearestEdge(_ m: IM, to p: Vec3) -> Edge? {
        let ss = sides(m)
        guard let best = ss.min(by: { dist(m, $0, p) < dist(m, $1, p) }) else { return nil }
        return edge(m, side: best)
    }
    static func dist(_ m: IM, _ side: [Int], _ p: Vec3) -> Double {
        guard side.count >= 2 else { return .infinity }
        return (0..<(side.count - 1)).map { SubObjects.segmentDistance(p, m.vertices[side[$0]], m.vertices[side[$0 + 1]]) }.min() ?? .infinity
    }

    /// Edge resampled to `n` + 1 points evenly by arc length.
    public static func resample(_ e: Edge, _ n: Int) -> Edge {
        var s: [Double] = [0]
        for i in 1..<e.points.count { s.append(s[i - 1] + e.points[i].distance(to: e.points[i - 1])) }
        let total = max(s.last ?? 0, 1e-12)
        var out = Edge(points: [], outward: [], normals: [], curvature: [])
        var j = 0
        for k in 0...n {
            let target = total * Double(k) / Double(n)
            while j < s.count - 2 && s[j + 1] < target { j += 1 }
            let seg = max(s[j + 1] - s[j], 1e-12)
            let t = max(0, min(1, (target - s[j]) / seg))
            func lerp(_ a: Vec3, _ b: Vec3) -> Vec3 { a + (b - a) * t }
            out.points.append(lerp(e.points[j], e.points[j + 1]))
            out.outward.append(lerp(e.outward[j], e.outward[j + 1]).normalized)
            out.normals.append(lerp(e.normals[j], e.normals[j + 1]).normalized)
            out.curvature.append(e.curvature[j] + (e.curvature[j + 1] - e.curvature[j]) * t)
        }
        return out
    }

    // MARK: Blend

    /// Point of the blend curve between P0 (leaving along V0 with acceleration A0) and P1 (arriving with V1, A1).
    public static func hermite(_ t: Double, _ p0: Vec3, _ v0: Vec3, _ a0: Vec3, _ p1: Vec3, _ v1: Vec3, _ a1: Vec3, continuity: Continuity) -> Vec3 {
        switch continuity {
        case .g0: return p0 + (p1 - p0) * t
        case .g1:
            let t2 = t * t, t3 = t2 * t
            return p0 * (2 * t3 - 3 * t2 + 1) + v0 * (t3 - 2 * t2 + t) + p1 * (-2 * t3 + 3 * t2) + v1 * (t3 - t2)
        case .g2:
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
            let h0 = 1 - 10 * t3 + 15 * t4 - 6 * t5, h1 = t - 6 * t3 + 8 * t4 - 3 * t5, h2 = 0.5 * t2 - 1.5 * t3 + 1.5 * t4 - 0.5 * t5
            let h3 = 0.5 * t3 - t4 + 0.5 * t5, h4 = -4 * t3 + 7 * t4 - 3 * t5, h5 = 10 * t3 - 15 * t4 + 6 * t5
            return p0 * h0 + v0 * h1 + a0 * h2 + a1 * h3 + v1 * h4 + p1 * h5
        }
    }

    /// Blend surface grid between two edges: rows[i][j], i along the edges (n + 1), j across (m + 1; j = 0 on `a`).
    /// `bulge` scales the tangent magnitudes (1 = the distance between the edges).
    public static func blendGrid(_ a0: Edge, _ b0: Edge, continuity: Continuity, bulge: Double = 1, n: Int = 16, m: Int = 8) -> [[Vec3]]? {
        guard a0.points.count >= 2, b0.points.count >= 2, n >= 1, m >= 1 else { return nil }
        let a = resample(a0, n)
        var b = resample(b0, n)
        // Match directions.
        let same = a.points[0].distance(to: b.points[0]) + a.points[n].distance(to: b.points[n])
        let flip = a.points[0].distance(to: b.points[n]) + a.points[n].distance(to: b.points[0])
        if flip < same { b = Edge(points: b.points.reversed(), outward: b.outward.reversed(), normals: b.normals.reversed(), curvature: b.curvature.reversed()) }
        var rows: [[Vec3]] = []
        for i in 0...n {
            let p0 = a.points[i], p1 = b.points[i]
            let s = max(p0.distance(to: p1), 1e-9) * bulge
            let v0 = a.outward[i] * s, v1 = -b.outward[i] * s
            let acc0 = a.normals[i] * (a.curvature[i] * s * s), acc1 = b.normals[i] * (b.curvature[i] * s * s)
            rows.append((0...m).map { hermite(Double($0) / Double(m), p0, v0, acc0, p1, v1, acc1, continuity: continuity) })
        }
        return rows
    }

    /// Triangulated grid.
    public static func mesh(_ rows: [[Vec3]]) -> IM {
        var v: [Vec3] = [], t: [Int] = []
        let n = rows.count, m = rows.first?.count ?? 0
        for r in rows { v += r }
        guard n >= 2, m >= 2 else { return (v, t) }
        for i in 0..<(n - 1) {
            for j in 0..<(m - 1) {
                let a = i * m + j, b = (i + 1) * m + j, c = (i + 1) * m + j + 1, d = i * m + j + 1
                t += [a, b, c, a, c, d]
            }
        }
        return (v, t)
    }

    // MARK: Analysis

    /// Per-vertex Gaussian curvature (angle deficit) and mean curvature (cotangent Laplacian); nil on open boundaries.
    public static func vertexCurvature(_ m: IM) -> (gaussian: [Double?], mean: [Double?]) {
        let nv = m.vertices.count
        var angle = [Double](repeating: 0, count: nv), area = [Double](repeating: 0, count: nv)
        var lap = [Vec3](repeating: .zero, count: nv)
        for f in 0..<(m.triangles.count / 3) {
            let ids = (0..<3).map { m.triangles[3 * f + $0] }
            let p = ids.map { m.vertices[$0] }
            let ar = (p[1] - p[0]).cross(p[2] - p[0]).length / 2
            guard ar > 1e-18 else { continue }
            for k in 0..<3 {
                let i = ids[k], j = ids[(k + 1) % 3], o = ids[(k + 2) % 3]
                let e1 = p[(k + 1) % 3] - p[k], e2 = p[(k + 2) % 3] - p[k]
                angle[i] += acos(max(-1, min(1, e1.normalized.dot(e2.normalized))))
                area[i] += ar / 3
                // Cotangent of the angle opposite edge i–j (at o).
                let u = m.vertices[i] - m.vertices[o], w = m.vertices[j] - m.vertices[o]
                let cot = u.dot(w) / max(u.cross(w).length, 1e-18)
                lap[i] = lap[i] + (m.vertices[i] - m.vertices[j]) * cot
                lap[j] = lap[j] + (m.vertices[j] - m.vertices[i]) * cot
            }
        }
        let boundary = Set(SubObjects.boundaryLoops(m, faces: Set(0..<(m.triangles.count / 3))).flatMap { $0 })
        var g: [Double?] = [], h: [Double?] = []
        for i in 0..<nv {
            guard area[i] > 0, !boundary.contains(i) else { g.append(nil); h.append(nil); continue }
            g.append((2 * .pi - angle[i]) / area[i])
            h.append((lap[i] / (2 * area[i])).length / 2)
        }
        return (g, h)
    }

    /// Draft angle (degrees) of every triangle relative to the pull direction: asin(n · pull).
    public static func draftAngles(_ m: IM, pull: Vec3) -> [Double] {
        let d = pull.normalized
        return (0..<(m.triangles.count / 3)).map { asin(max(-1, min(1, SubObjects.normal(m, $0).dot(d)))) * 180 / .pi }
    }

    /// Zebra stripe index (0/1) of every triangle: bands of the normal's angle to `axis`, `width` degrees wide.
    public static func zebra(_ m: IM, axis: Vec3 = .unitZ, width: Double = 10) -> [Int] {
        let a = axis.normalized, w = max(width, 0.1)
        return (0..<(m.triangles.count / 3)).map { f in
            let ang = acos(max(-1, min(1, SubObjects.normal(m, f).dot(a)))) * 180 / .pi
            return Int((ang / w).rounded(.down)) % 2
        }
    }

    /// Continuity between two surfaces along the nearest sides: largest gap (G0), largest normal angle in degrees
    /// (G1) and largest difference of normal curvature across the edge (G2).
    public static func continuity(_ a: IM, _ b: IM, near p: Vec3) -> (gap: Double, angle: Double, curvature: Double)? {
        guard let ea = nearestEdge(a, to: p), let eb = nearestEdge(b, to: p) else { return nil }
        let rb = resample(eb, max(eb.points.count * 4, 32))
        var gap = 0.0, ang = 0.0, dk = 0.0
        for i in 0..<ea.points.count {
            guard let j = rb.points.indices.min(by: { rb.points[$0].distance(to: ea.points[i]) < rb.points[$1].distance(to: ea.points[i]) }) else { continue }
            gap = max(gap, rb.points[j].distance(to: ea.points[i]))
            let c = abs(ea.normals[i].dot(rb.normals[j]))
            ang = max(ang, acos(max(-1, min(1, c))) * 180 / .pi)
            dk = max(dk, abs(abs(ea.curvature[i]) - abs(rb.curvature[j])))
        }
        return (gap, ang, dk)
    }
}

// MARK: - Commands

enum SurfaceBlendCommands {
    static var all: [CommandDef] { [blend, analysis] }

    @MainActor static func surface(_ ed: Editor, _ msg: String) async throws -> (EntityID, SurfaceBlend.IM)? {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { ModelingCommands.solidOf(ed.doc, $0) != nil }), let s = ModelingCommands.solidOf(ed.doc, pk.id) else { return nil }
        let w = SolidOps.welded(s)
        return (pk.id, (w.vertices, w.triangles))
    }

    static var blend: CommandDef {
        CommandDef("SURFBLEND", aliases: ["BLENDSURFACE", "BLENDSRF"], category: "3D", summary: "Blend surface between the edges of two surfaces with G0 (position), G1 (tangent) or G2 (curvature) continuity and a bulge factor.") { ed in
            guard let (ia, ma) = try await surface(ed, "Select the first surface") else { return }
            let pa = try await ed.requirePoint3("Specify a point near its edge")
            guard let (ib, mb) = try await surface(ed, "Select the second surface") else { return }
            let pb = try await ed.requirePoint3("Specify a point near its edge")
            guard let ea = SurfaceBlend.nearestEdge(ma, to: pa), let eb = SurfaceBlend.nearestEdge(mb, to: pb) else { throw CommandError.invalid("The surfaces have no open edges.") }
            let c = try await ed.getKeyword("Continuity [G0/G1/G2]", ["G0", "G1", "G2"], defaultValue: ed.doc.variable("SURFBLENDCONT") ?? "G1") ?? "G1"
            let bulge = try await ed.getReal("Bulge (tangent magnitude factor)", defaultValue: ed.variableDouble("SURFBLENDBULGE", 1)).value ?? 1
            guard bulge > 0, bulge <= 10 else { throw CommandError.invalid("Enter a bulge between 0 and 10.") }
            ed.doc.setVariable("SURFBLENDCONT", c); ed.doc.setVariable("SURFBLENDBULGE", fmt(bulge))
            let cont = SurfaceBlend.Continuity(rawValue: Int(c.dropFirst()) ?? 1) ?? .g1
            let n = max(2, Int(ed.variableDouble("SURFTAB1", 16))), m = max(2, Int(ed.variableDouble("SURFTAB2", 8)))
            guard let rows = SurfaceBlend.blendGrid(ea, eb, continuity: cont, bulge: bulge, n: n, m: m) else { throw CommandError.invalid("The edges cannot be blended.") }
            try SurfaceCommands.addSurface(ed, SurfaceBlend.mesh(rows), what: "Blend surface")
            if let id = ed.doc.entities.last?.id, let i = ed.doc.entityIndex(id) {
                ed.doc.entities[i].props["blendOf"] = "\(ia),\(ib)"; ed.doc.entities[i].props["blendContinuity"] = c
            }
        }
    }

    static let analysisLayer = "ANALYSIS"

    /// Materials used to colour analysis results.
    @MainActor static func material(_ ed: Editor, _ name: String, _ c: RGBA) -> String {
        if ed.doc.material(name) == nil { ed.doc.materials.append(Material(name: name, color: c, roughness: 0.6)) }
        return name
    }

    /// Adds one coloured copy of the triangles of each class.
    @MainActor static func addClasses(_ ed: Editor, of id: EntityID, _ m: SurfaceBlend.IM, classes: [Int], materials: [String]) -> Int {
        ed.doc.remove(ids: Set(ed.doc.entities.filter { $0.props["analysisOf"] == "\(id)" }.map(\.id)))
        ed.doc.ensureLayer(analysisLayer)
        var n = 0
        for (k, mat) in materials.enumerated() {
            var tris: [Int] = []
            for f in classes.indices where classes[f] == k { tris += [m.triangles[3 * f], m.triangles[3 * f + 1], m.triangles[3 * f + 2]] }
            guard !tris.isEmpty else { continue }
            var e = Entity(layer: analysisLayer, geometry: .solid(SubObjects.solidGeom((m.vertices, tris))))
            e.props["material"] = mat; e.props["analysisOf"] = "\(id)"; e.props["surface"] = "Analysis"
            ed.doc.add(e); n += 1
        }
        return n
    }

    static var analysis: CommandDef {
        CommandDef("SURFANALYSIS", aliases: ["ANALYSISZEBRA", "ANALYSISCURVATURE", "ANALYSISDRAFT", "SURFACEANALYSIS", "ZEBRA"], category: "3D", summary: "Surface analysis: Zebra stripes, Curvature (Gaussian or mean, colour bands), Draft angle against a pull direction, Continuity between two surfaces, or Clear the analysis overlays.") { ed in
            let mode = try await ed.getKeyword("Analysis [Zebra/Curvature/Draft/Continuity/Clear]", ["Zebra", "Curvature", "Draft", "Continuity", "Clear"], defaultValue: "Zebra") ?? "Zebra"
            if mode == "Clear" {
                let ids = ed.doc.entities.filter { $0.props["analysisOf"] != nil }.map(\.id)
                ed.doc.remove(ids: Set(ids)); ed.print("\(ids.count) analysis overlay(s) removed."); return
            }
            guard let (id, m) = try await surface(ed, mode == "Continuity" ? "Select the first surface" : "Select a surface or solid") else { return }
            switch mode {
            case "Continuity":
                guard let (_, mb) = try await surface(ed, "Select the second surface") else { return }
                let p = try await ed.requirePoint3("Specify a point near the common edge")
                guard let r = SurfaceBlend.continuity(m, mb, near: p) else { throw CommandError.invalid("No open edges to compare.") }
                let tol = max(1e-3, 0.5 / ed.doc.units.mm)
                let level = r.gap > tol ? "none (gap)" : (r.angle > 1 ? "G0" : (r.curvature > 1e-4 ? "G1" : "G2"))
                ed.print("Continuity: gap \(fmt(r.gap)), tangent angle \(fmt(r.angle, 2))°, curvature difference \(fmt(r.curvature, 6)) → \(level).")
            case "Draft":
                let dz = try await ed.getPoint3("Pull direction x,y,z", defaultZ: 1).point ?? Vec3(0, 0, 1)
                let pull = dz.length > 1e-12 ? dz : Vec3(0, 0, 1)
                let thr = try await ed.getReal("Minimum draft angle in degrees", defaultValue: ed.variableDouble("DRAFTANGLE", 3)).value ?? 3
                ed.doc.setVariable("DRAFTANGLE", fmt(thr))
                let a = SurfaceBlend.draftAngles(m, pull: pull)
                let cls = a.map { $0 >= thr ? 0 : ($0 <= -thr ? 2 : 1) }
                let mats = [material(ed, "Analysis Draft OK", RGBA(0.2, 0.75, 0.3)), material(ed, "Analysis Draft Low", RGBA(0.95, 0.8, 0.2)), material(ed, "Analysis Undercut", RGBA(0.85, 0.2, 0.2))]
                _ = addClasses(ed, of: id, m, classes: cls, materials: mats)
                ed.print("Draft: \(cls.filter { $0 == 0 }.count) face(s) ≥ \(fmt(thr))°, \(cls.filter { $0 == 1 }.count) below, \(cls.filter { $0 == 2 }.count) undercut.")
            case "Curvature":
                let k = try await ed.getKeyword("Curvature [Gaussian/Mean]", ["Gaussian", "Mean"], defaultValue: "Mean") ?? "Mean"
                let c = SurfaceBlend.vertexCurvature(m)
                let vals = k == "Gaussian" ? c.gaussian : c.mean
                let faceVals: [Double?] = (0..<(m.triangles.count / 3)).map { f in
                    let vs = (0..<3).compactMap { vals[m.triangles[3 * f + $0]] }
                    return vs.isEmpty ? nil : vs.reduce(0, +) / Double(vs.count)
                }
                let known = faceVals.compactMap { $0 }
                guard let lo = known.min(), let hi = known.max() else { throw CommandError.invalid("The surface has no interior vertices.") }
                let colors = [RGBA(0.15, 0.3, 0.9), RGBA(0.2, 0.75, 0.85), RGBA(0.3, 0.8, 0.3), RGBA(0.95, 0.8, 0.2), RGBA(0.9, 0.25, 0.2)]
                let mats = colors.enumerated().map { material(ed, "Analysis Curvature \($0.offset + 1)", $0.element) }
                let span = hi - lo
                let cls = faceVals.map { v -> Int in guard let v = v else { return 0 }; return span < 1e-15 ? 2 : min(4, Int((v - lo) / span * 5)) }
                _ = addClasses(ed, of: id, m, classes: cls, materials: mats)
                ed.print("\(k) curvature from \(fmt(lo, 8)) to \(fmt(hi, 8)) per unit (radius " + (hi > 1e-15 ? fmt(k == "Gaussian" ? 1 / sqrt(max(hi, 1e-30)) : 1 / hi) : "∞") + " at the maximum).")
            default:
                let w = try await ed.getReal("Stripe width in degrees", defaultValue: ed.variableDouble("ZEBRAWIDTH", 10)).value ?? 10
                guard w > 0 else { throw CommandError.invalid("Enter a positive stripe width.") }
                ed.doc.setVariable("ZEBRAWIDTH", fmt(w))
                let cls = SurfaceBlend.zebra(m, width: w)
                _ = addClasses(ed, of: id, m, classes: cls, materials: [material(ed, "Analysis Zebra Black", RGBA(0.05, 0.05, 0.05)), material(ed, "Analysis Zebra White", RGBA(0.97, 0.97, 0.97))])
                ed.print("Zebra stripes every \(fmt(w))°: breaks in the stripes show tangent discontinuities.")
            }
        }
    }
}
