// Oanarina Archi Tool — GPL-3.0-or-later
// Structural analytical model (nodes, members, panels, supports, loads) derived from columns, beams, structural
// walls and slabs; JSON export; and a linear-elastic 3D frame solver (direct stiffness method, Euler–Bernoulli members,
// 6 DOF per node) for quick checks of frames. Units in the model: metres, kN, kN/m², MPa.
import Foundation

public struct StructMaterial: Hashable {
    public var name: String
    /// Young's modulus (MPa), shear modulus (MPa), unit weight (kN/m³).
    public var e: Double, g: Double, weight: Double
    public static func of(_ name: String?) -> StructMaterial {
        let n = (name ?? "Concrete").lowercased()
        if n.contains("steel") { return StructMaterial(name: name ?? "Steel", e: 210_000, g: 81_000, weight: 78.5) }
        if n.contains("wood") || n.contains("timber") || n.contains("glulam") || n.contains("clt") { return StructMaterial(name: name ?? "Timber", e: 11_000, g: 690, weight: 5) }
        if n.contains("alumin") { return StructMaterial(name: name ?? "Aluminium", e: 70_000, g: 26_000, weight: 27) }
        if n.contains("brick") || n.contains("masonry") { return StructMaterial(name: name ?? "Masonry", e: 5_000, g: 2_000, weight: 18) }
        return StructMaterial(name: name ?? "Concrete", e: 30_000, g: 12_500, weight: 25)
    }
}

public struct AnalyticalNode: Hashable {
    public var id: Int
    public var p: Vec3            // metres
    /// Fixed DOFs (ux, uy, uz, rx, ry, rz).
    public var support: [Bool]
    public var isSupported: Bool { support.contains(true) }
}

public struct AnalyticalMember: Hashable {
    public var id: Int
    public var element: EntityID
    public var kind: String       // column, beam
    public var start: Int, end: Int
    /// Section width (local y) and depth (local z) in metres; round sections use width as diameter.
    public var width: Double, depth: Double
    public var round: Bool
    public var material: StructMaterial
    public var area: Double { round ? .pi * width * width / 4 : width * depth }
    /// Second moments about local y (strong, bending in the depth direction) and z, torsion constant (m⁴).
    public var iy: Double { round ? .pi * pow(width, 4) / 64 : width * pow(depth, 3) / 12 }
    public var iz: Double { round ? .pi * pow(width, 4) / 64 : depth * pow(width, 3) / 12 }
    public var j: Double {
        if round { return .pi * pow(width, 4) / 32 }
        let a = max(width, depth), b = min(width, depth)
        return a * pow(b, 3) * (1.0 / 3 - 0.21 * b / a * (1 - pow(b, 4) / (12 * pow(a, 4))))
    }
}

public struct AnalyticalPanel: Hashable {
    public var id: Int
    public var element: EntityID
    public var kind: String       // wall, slab
    public var outline: [Vec3]
    public var thickness: Double
    public var material: StructMaterial
    /// Area load (kN/m²): self weight + extra dead + live, for slabs.
    public var areaLoad: Double
}

public struct NodeLoad: Hashable {
    public var node: Int
    /// Force (kN) and moment (kNm) in global axes.
    public var force: Vec3, moment: Vec3
}

public struct AnalyticalModel {
    public var nodes: [AnalyticalNode] = []
    public var members: [AnalyticalMember] = []
    public var panels: [AnalyticalPanel] = []
    public var nodeLoads: [NodeLoad] = []
    /// Uniform member loads (kN/m, global) — self weight.
    public var memberLoads: [Int: Vec3] = [:]
    public var warnings: [String] = []

    /// JSON document (format "archi-analytical-1").
    public func json(name: String = "Model") -> [String: Any] {
        func v(_ p: Vec3) -> [Double] { [p.x, p.y, p.z].map { ($0 * 1e6).rounded() / 1e6 } }
        var mats: [String: StructMaterial] = [:]
        for m in members { mats[m.material.name] = m.material }
        for p in panels { mats[p.material.name] = p.material }
        return [
            "format": "archi-analytical-1", "name": name, "units": ["length": "m", "force": "kN", "stress": "MPa"],
            "materials": mats.values.sorted { $0.name < $1.name }.map { ["name": $0.name, "E_MPa": $0.e, "G_MPa": $0.g, "unitWeight_kN_m3": $0.weight] },
            "nodes": nodes.map { n -> [String: Any] in
                var o: [String: Any] = ["id": n.id, "xyz": v(n.p)]
                if n.isSupported { o["support"] = n.support.map { $0 ? 1 : 0 } }
                return o
            },
            "members": members.map { m -> [String: Any] in
                ["id": m.id, "element": m.element, "type": m.kind, "nodes": [m.start, m.end], "material": m.material.name,
                 "section": ["shape": m.round ? "circle" : "rectangle", "b": m.width, "h": m.depth, "A": m.area, "Iy": m.iy, "Iz": m.iz, "J": m.j]]
            },
            "panels": panels.map { ["id": $0.id, "element": $0.element, "type": $0.kind, "outline": $0.outline.map(v), "thickness": $0.thickness,
                                    "material": $0.material.name, "areaLoad_kN_m2": $0.areaLoad] },
            "loads": [
                "nodal": nodeLoads.map { ["node": $0.node, "F": v($0.force), "M": v($0.moment)] },
                "memberUniform": memberLoads.sorted { $0.key < $1.key }.map { ["member": $0.key, "w": v($0.value)] },
            ] as [String: Any],
            "warnings": warnings,
        ]
    }
}

public struct AnalyticalOptions {
    /// Snap distance for joining member ends (m).
    public var tolerance = 0.05
    /// Superimposed dead and live loads on slabs (kN/m²).
    public var deadLoad = 1.5
    public var liveLoad = 2.0
    public var includeSelfWeight = true
    public init() {}
    public static func from(_ doc: ArchiDocument) -> AnalyticalOptions {
        var o = AnalyticalOptions()
        if let v = doc.variable("DEADLOAD").flatMap(Double.init) { o.deadLoad = v }
        if let v = doc.variable("LIVELOAD").flatMap(Double.init) { o.liveLoad = v }
        return o
    }
}

public enum StructuralAnalysis {
    /// Builds the analytical model. Column bases on the lowest structural level get fixed supports; slab loads are
    /// lumped to the column-top nodes inside each slab (equal shares).
    public static func model(_ doc: ArchiDocument, options o: AnalyticalOptions = AnalyticalOptions()) -> AnalyticalModel {
        var m = AnalyticalModel()
        let u = doc.units.mm / 1000
        func elev(_ l: Int) -> Double { (doc.level(l)?.elevation ?? 0) * u }
        func node(_ p: Vec3) -> Int {
            if let n = m.nodes.first(where: { $0.p.distance(to: p) <= o.tolerance }) { return n.id }
            let id = m.nodes.count + 1
            m.nodes.append(AnalyticalNode(id: id, p: p, support: Array(repeating: false, count: 6)))
            return id
        }
        // Columns first so beams snap onto their axes.
        var columnTops: [(xy: Vec2, z: Double, half: Double, node: Int, level: Int)] = []
        var baseZ: [Int: Double] = [:]
        for el in doc.elements {
            guard case .column(let c) = el.geometry, c.height > 0 else { continue }
            let z0 = elev(el.level) + c.baseOffset * u, z1 = z0 + c.height * u
            let xy = c.position * u
            let a = node(Vec3(xy.x, xy.y, z0)), b = node(Vec3(xy.x, xy.y, z1))
            guard a != b else { continue }
            m.members.append(AnalyticalMember(id: m.members.count + 1, element: el.id, kind: "column", start: a, end: b,
                                              width: c.width * u, depth: (c.round ? c.width : c.depth) * u, round: c.round, material: StructMaterial.of(el.material)))
            columnTops.append((xy, z1, max(c.width, c.depth) * u / 2, b, el.level))
            baseZ[a] = z0
        }
        for el in doc.elements {
            guard case .beam(let b) = el.geometry, b.start.distance(to: b.end) > 1e-9 else { continue }
            let z = elev(el.level) + (b.topOffset - b.depth / 2) * u
            func end(_ p: Vec2) -> Int {
                let q = p * u
                if let c = columnTops.first(where: { $0.xy.distance(to: q) <= $0.half + o.tolerance && abs($0.z - z) <= b.depth * u / 2 + o.tolerance + 1e-9 }) { return c.node }
                return node(Vec3(q.x, q.y, z))
            }
            let s = end(b.start), e = end(b.end)
            guard s != e else { m.warnings.append("Beam #\(el.id) collapses to one node."); continue }
            m.members.append(AnalyticalMember(id: m.members.count + 1, element: el.id, kind: "beam", start: s, end: e,
                                              width: b.width * u, depth: b.depth * u, round: false, material: StructMaterial.of(el.material)))
        }
        // Supports: lowest node(s) of vertical members.
        if let zmin = baseZ.values.min() {
            for (n, z) in baseZ where abs(z - zmin) <= o.tolerance { m.nodes[n - 1].support = Array(repeating: true, count: 6) }
        }
        // Panels: load-bearing walls and floor slabs.
        for el in doc.elements {
            switch el.geometry {
            case .wall(let w):
                let loadBearing = el.props["loadBearing"].map { ["1", "true", "yes"].contains($0.lowercased()) } ?? (w.thickness * u >= 0.15 && !(w.wallType ?? "").lowercased().contains("partition"))
                guard loadBearing, w.length > 1e-9 else { continue }
                let z0 = elev(el.level) + w.baseOffset * u, z1 = z0 + w.height * u
                let a = w.centerStart * u, b = w.centerEnd * u
                m.panels.append(AnalyticalPanel(id: m.panels.count + 1, element: el.id, kind: "wall",
                                                outline: [Vec3(a.x, a.y, z0), Vec3(b.x, b.y, z0), Vec3(b.x, b.y, z1), Vec3(a.x, a.y, z1)],
                                                thickness: w.thickness * u, material: StructMaterial.of(el.material), areaLoad: 0))
            case .slab(let s):
                let kind = el.props["kind"] ?? ""
                guard kind.isEmpty || kind == "floor" || kind == "ramp" || kind == "landing", s.boundary.count >= 3 else { continue }
                let mat = StructMaterial.of(el.material)
                let q = (o.includeSelfWeight ? mat.weight * s.thickness * u : 0) + o.deadLoad + o.liveLoad
                let outline = s.boundary.map { p in Vec3(p.x * u, p.y * u, elev(el.level) + (s.topHeight(at: p) - s.thickness / 2) * u) }
                m.panels.append(AnalyticalPanel(id: m.panels.count + 1, element: el.id, kind: "slab", outline: outline, thickness: s.thickness * u, material: mat, areaLoad: q))
                // Lump the slab load onto column tops inside the slab near its elevation.
                let inside = columnTops.filter { GeometryOps.pointInPolygon($0.xy / u, s.boundary) && abs($0.z - (elev(el.level) + s.topOffset * u)) <= 0.5 }
                let area = ScheduleExporter.slabArea(s) * u * u
                if !inside.isEmpty {
                    let share = q * area / Double(inside.count)
                    for c in inside { m.nodeLoads.append(NodeLoad(node: c.node, force: Vec3(0, 0, -share), moment: .zero)) }
                } else if area > 0 { m.warnings.append("Slab #\(el.id): no columns under it; its load (\(fmt(q * area, 1)) kN) is not transferred to the frame.") }
            default: continue
            }
        }
        if o.includeSelfWeight {
            for mem in m.members { m.memberLoads[mem.id] = Vec3(0, 0, -mem.material.weight * mem.area) }
        }
        if m.members.isEmpty { m.warnings.append("No columns or beams: the frame is empty.") }
        return m
    }

    public struct Result {
        /// Node displacements (m) and rotations (rad), by node id.
        public var displacements: [Int: (u: Vec3, r: Vec3)]
        /// Support reactions (kN, kNm) by node id.
        public var reactions: [Int: (f: Vec3, m: Vec3)]
        public var maxDisplacement: (node: Int, value: Double)
    }

    public enum SolveError: Error, LocalizedError {
        case unstable(String), tooLarge(Int)
        public var errorDescription: String? {
            switch self {
            case .unstable(let m): return "The frame is unstable (mechanism or unsupported): \(m)"
            case .tooLarge(let n): return "The frame has \(n) degrees of freedom; the built-in solver handles up to 1800 — export the model instead."
            }
        }
    }

    /// Local stiffness of a 3D Euler–Bernoulli frame element (12×12), units kN and m (E, G in kN/m²).
    static func localStiffness(_ mem: AnalyticalMember, length L: Double) -> [[Double]] {
        let E = mem.material.e * 1000, G = mem.material.g * 1000
        let A = mem.area, Iy = mem.iy, Iz = mem.iz, J = mem.j
        var k = Array(repeating: Array(repeating: 0.0, count: 12), count: 12)
        let ea = E * A / L, gj = G * J / L
        let z12 = 12 * E * Iz / pow(L, 3), z6 = 6 * E * Iz / (L * L), z4 = 4 * E * Iz / L, z2 = 2 * E * Iz / L
        let y12 = 12 * E * Iy / pow(L, 3), y6 = 6 * E * Iy / (L * L), y4 = 4 * E * Iy / L, y2 = 2 * E * Iy / L
        k[0][0] = ea; k[0][6] = -ea; k[6][0] = -ea; k[6][6] = ea
        k[3][3] = gj; k[3][9] = -gj; k[9][3] = -gj; k[9][9] = gj
        // Bending in the local x-y plane (about z): v, θz.
        k[1][1] = z12; k[1][5] = z6; k[1][7] = -z12; k[1][11] = z6
        k[5][1] = z6; k[5][5] = z4; k[5][7] = -z6; k[5][11] = z2
        k[7][1] = -z12; k[7][5] = -z6; k[7][7] = z12; k[7][11] = -z6
        k[11][1] = z6; k[11][5] = z2; k[11][7] = -z6; k[11][11] = z4
        // Bending in the local x-z plane (about y): w, θy.
        k[2][2] = y12; k[2][4] = -y6; k[2][8] = -y12; k[2][10] = -y6
        k[4][2] = -y6; k[4][4] = y4; k[4][8] = y6; k[4][10] = y2
        k[8][2] = -y12; k[8][4] = y6; k[8][8] = y12; k[8][10] = y6
        k[10][2] = -y6; k[10][4] = y2; k[10][8] = y6; k[10][10] = y4
        return k
    }

    /// Rotation matrix rows = local axes (x along the member; z = global up projected for beams, global X for columns).
    static func axes(_ a: Vec3, _ b: Vec3) -> [Vec3] {
        let d = b - a
        let x = d * (1 / d.length)
        let ref = abs(x.z) > 0.999 ? Vec3(1, 0, 0) : Vec3(0, 0, 1)
        var y = ref.cross(x); y = y * (1 / y.length)
        let z = x.cross(y)
        return [x, y, z]
    }

    /// Linear static analysis. Member self weight becomes equivalent nodal loads (fixed-end forces).
    public static func solve(_ m: AnalyticalModel) throws -> Result {
        let n = m.nodes.count
        let ndof = n * 6
        guard ndof <= 1800 else { throw SolveError.tooLarge(ndof) }
        var K = Array(repeating: Array(repeating: 0.0, count: ndof), count: ndof)
        var F = Array(repeating: 0.0, count: ndof)
        func idx(_ node: Int) -> Int { (node - 1) * 6 }
        for mem in m.members {
            let a = m.nodes[mem.start - 1].p, b = m.nodes[mem.end - 1].p
            let L = a.distance(to: b)
            guard L > 1e-9 else { continue }
            let kl = localStiffness(mem, length: L)
            let ax = axes(a, b)
            // T (12x12) block-diagonal with R (rows = local axes).
            var T = Array(repeating: Array(repeating: 0.0, count: 12), count: 12)
            for blk in 0..<4 { for r in 0..<3 { let v = ax[r]; T[blk * 3 + r][blk * 3] = v.x; T[blk * 3 + r][blk * 3 + 1] = v.y; T[blk * 3 + r][blk * 3 + 2] = v.z } }
            // Kg = Tᵀ kl T
            var kt = Array(repeating: Array(repeating: 0.0, count: 12), count: 12)
            for i in 0..<12 { for j in 0..<12 { var s = 0.0; for p in 0..<12 where kl[i][p] != 0 { s += kl[i][p] * T[p][j] }; kt[i][j] = s } }
            let dofs = (0..<6).map { idx(mem.start) + $0 } + (0..<6).map { idx(mem.end) + $0 }
            for i in 0..<12 { for j in 0..<12 { var s = 0.0; for p in 0..<12 where T[p][i] != 0 { s += T[p][i] * kt[p][j] }; K[dofs[i]][dofs[j]] += s } }
            // Uniform load → fixed-end forces (global): wL/2 at each end, moments ±wL²/12 about the local axes.
            if let w = m.memberLoads[mem.id], w.length > 0 {
                let wl = [w.dot(ax[0]), w.dot(ax[1]), w.dot(ax[2])]
                var fl = Array(repeating: 0.0, count: 12)
                fl[0] = wl[0] * L / 2; fl[6] = wl[0] * L / 2
                fl[1] = wl[1] * L / 2; fl[7] = wl[1] * L / 2; fl[5] = wl[1] * L * L / 12; fl[11] = -wl[1] * L * L / 12
                fl[2] = wl[2] * L / 2; fl[8] = wl[2] * L / 2; fl[4] = -wl[2] * L * L / 12; fl[10] = wl[2] * L * L / 12
                for i in 0..<12 { var s = 0.0; for p in 0..<12 { s += T[p][i] * fl[p] }; F[dofs[i]] += s }
            }
        }
        for l in m.nodeLoads where l.node >= 1 && l.node <= n {
            let i = idx(l.node)
            F[i] += l.force.x; F[i + 1] += l.force.y; F[i + 2] += l.force.z
            F[i + 3] += l.moment.x; F[i + 4] += l.moment.y; F[i + 5] += l.moment.z
        }
        let Kfull = K, Ffull = F
        // Free DOFs: unsupported and connected to at least one member (else drop the DOF).
        var free: [Int] = []
        for node in m.nodes {
            for d in 0..<6 where !node.support[d] {
                let i = idx(node.id) + d
                if K[i][i] > 1e-9 { free.append(i) }
            }
        }
        guard !free.isEmpty else { throw SolveError.unstable("no free degrees of freedom") }
        let nf = free.count
        var A = free.map { r in free.map { c in K[r][c] } }
        var b = free.map { F[$0] }
        K = []
        // Gaussian elimination with partial pivoting.
        let scale = A.enumerated().map { abs($0.element[$0.offset]) }.max() ?? 1
        for col in 0..<nf {
            var piv = col
            for r in (col + 1)..<max(col + 1, nf) where abs(A[r][col]) > abs(A[piv][col]) { piv = r }
            guard abs(A[piv][col]) > 1e-10 * scale else { throw SolveError.unstable("singular at DOF \(free[col] % 6) of node \(free[col] / 6 + 1)") }
            if piv != col { A.swapAt(piv, col); b.swapAt(piv, col) }
            let p = A[col][col]
            for r in (col + 1)..<max(col + 1, nf) {
                let f = A[r][col] / p
                if f == 0 { continue }
                for c in col..<nf { A[r][c] -= f * A[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = Array(repeating: 0.0, count: nf)
        for r in stride(from: nf - 1, through: 0, by: -1) {
            var s = b[r]
            for c in (r + 1)..<max(r + 1, nf) { s -= A[r][c] * x[c] }
            x[r] = s / A[r][r]
        }
        var U = Array(repeating: 0.0, count: ndof)
        for (k, i) in free.enumerated() { U[i] = x[k] }
        var disp: [Int: (Vec3, Vec3)] = [:]
        var best = (0, 0.0)
        for node in m.nodes {
            let i = idx(node.id)
            let d = Vec3(U[i], U[i + 1], U[i + 2])
            disp[node.id] = (d, Vec3(U[i + 3], U[i + 4], U[i + 5]))
            if d.length > best.1 { best = (node.id, d.length) }
        }
        var reactions: [Int: (Vec3, Vec3)] = [:]
        for node in m.nodes where node.isSupported {
            let i = idx(node.id)
            var r = [Double](repeating: 0, count: 6)
            for d in 0..<6 { var s = 0.0; for j in 0..<ndof where Kfull[i + d][j] != 0 { s += Kfull[i + d][j] * U[j] }; r[d] = s - Ffull[i + d] }
            reactions[node.id] = (Vec3(r[0], r[1], r[2]), Vec3(r[3], r[4], r[5]))
        }
        return Result(displacements: disp.mapValues { (u: $0.0, r: $0.1) }, reactions: reactions.mapValues { (f: $0.0, m: $0.1) }, maxDisplacement: (best.0, best.1))
    }
}
