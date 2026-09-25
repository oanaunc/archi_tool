// Oanarina Archi Tool — GPL-3.0-or-later
// Connector-based MEP systems (connected run networks) and lighting fixtures with photometric data and schedules.
import Foundation

// MARK: - Connection networks

/// Connected MEP networks: runs (pipes, ducts, conduits, trays) whose ends meet, plus the fixture connectors they reach.
public enum MEPNetworks {
    public struct Network: Hashable {
        /// System code of the network (the most common system among its runs; "" when none is assigned).
        public var system: String
        public var runs: [EntityID]
        /// Fixtures (point components) with a connector on the network.
        public var fixtures: [EntityID]
        /// Total centreline length of the runs.
        public var length: Double
        /// Run ends not connected to another run or a fixture.
        public var openEnds: [Vec3]
        /// Runs whose system differs from the network's system.
        public var mismatched: [EntityID]
    }

    struct Node { var p: Vec3; var el: EntityID; var isFixture: Bool; var system: String? }

    /// Ends of a run in world 3D (level elevation + base offset + vertex heights).
    static func runEnds(_ el: BIMElement, doc: ArchiDocument) -> [Vec3] {
        guard case .component(let g) = el.geometry, RunFamilies.isRun(g.family), g.family != "retaining-wall" else { return [] }
        let p = RunFamilies.path3(g, z0: (doc.level(el.level)?.elevation ?? 0) + g.baseOffset)
        guard let a = p.first, let b = p.last, p.count >= 2 else { return [] }
        return [a, b]
    }

    /// Run length (3D centreline).
    static func runLength(_ el: BIMElement, doc: ArchiDocument) -> Double {
        guard case .component(let g) = el.geometry else { return 0 }
        let p = RunFamilies.path3(g, z0: 0)
        return zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Runs whose ends meet (within `tolerance`, default 5 mm plus half the larger diameter) are one network;
    /// a fixture joins the network of a run end touching one of its connectors.
    public static func networks(doc: ArchiDocument, tolerance: Double? = nil) -> [Network] {
        let u = 1 / doc.units.mm
        let els = ModelSets.visibleModel(doc).elements
        var runIDs: [EntityID] = [], ends: [[Vec3]] = [], radius: [Double] = [], sys: [String?] = [], paths: [[Vec3]] = [], lens: [Double] = []
        var fixtures: [(id: EntityID, cons: [MEPConnector])] = []
        for el in els {
            guard case .component(let g) = el.geometry else { continue }
            if RunFamilies.isRun(g.family) {
                let e = runEnds(el, doc: doc)
                guard e.count == 2 else { continue }
                let p3 = RunFamilies.path3(g, z0: (doc.level(el.level)?.elevation ?? 0) + g.baseOffset)
                paths.append(p3); lens.append(zip(p3, p3.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) })
                runIDs.append(el.id); ends.append(e); radius.append(max(g.size.x, 0) / 2); sys.append(el.props["system"].flatMap { $0.isEmpty ? nil : $0.uppercased() })
            } else if let f = ComponentLibrary.family(g.family) {
                let cons = ComponentLibrary.worldConnectors(f, g, z0: (doc.level(el.level)?.elevation ?? 0) + g.baseOffset)
                if !cons.isEmpty { fixtures.append((el.id, cons)) }
            }
        }
        let n = runIDs.count
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        func unite(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }
        let baseTol = tolerance ?? 5 * u
        var connected = Array(repeating: [false, false], count: n)
        for i in 0..<n {
            for j in (i + 1)..<max(n, i + 1) {
                let tol = baseTol + max(radius[i], radius[j])
                for a in 0..<2 { for b in 0..<2 where ends[i][a].distance(to: ends[j][b]) <= tol {
                    unite(i, j); connected[i][a] = true; connected[j][b] = true
                } }
                // A run end landing on the middle of another run (tee).
                for a in 0..<2 {
                    if distance(ends[i][a], toPolyline: paths[j]) <= tol { unite(i, j); connected[i][a] = true }
                    if distance(ends[j][a], toPolyline: paths[i]) <= tol { unite(i, j); connected[j][a] = true }
                }
            }
        }
        var fixtureOf: [Int: Set<EntityID>] = [:]
        for fx in fixtures {
            for c in fx.cons {
                for i in 0..<n {
                    let tol = baseTol + max(radius[i], c.diameter / 2 * u)
                    for a in 0..<2 where ends[i][a].distance(to: c.position) <= tol {
                        fixtureOf[find(i), default: []].insert(fx.id); connected[i][a] = true
                    }
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(i) }
        var out: [Network] = []
        for (root, members) in groups {
            var counts: [String: Int] = [:]
            for m in members { if let s = sys[m] { counts[s, default: 0] += 1 } }
            let system = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? ""
            var open: [Vec3] = []
            for m in members { for a in 0..<2 where !connected[m][a] { open.append(ends[m][a]) } }
            let len = members.reduce(0.0) { $0 + lens[$1] }
            let mism = members.filter { sys[$0] != nil && sys[$0] != system }.map { runIDs[$0] }
            out.append(Network(system: system, runs: members.map { runIDs[$0] }.sorted(), fixtures: (fixtureOf[root] ?? []).sorted(),
                               length: len, openEnds: open, mismatched: mism.sorted()))
        }
        return out.sorted { ($0.system, $0.runs.first ?? 0) < ($1.system, $1.runs.first ?? 0) }
    }

    static func distance(_ p: Vec3, toPolyline pts: [Vec3]) -> Double {
        var best = Double.infinity
        for (a, b) in zip(pts, pts.dropFirst()) {
            let d = b - a, l2 = d.dot(d)
            let t = l2 < 1e-18 ? 0 : max(0, min(1, (p - a).dot(d) / l2))
            best = min(best, (a + d * t).distance(to: p))
        }
        return best
    }

    /// The network containing an element (run or fixture).
    public static func network(containing id: EntityID, doc: ArchiDocument) -> Network? {
        networks(doc: doc).first { $0.runs.contains(id) || $0.fixtures.contains(id) }
    }

    /// Assigns a system to every run of the network containing `id`. Returns the number of runs changed.
    @discardableResult
    public static func assign(_ system: String, toNetworkOf id: EntityID, doc: inout ArchiDocument) -> Int {
        guard let net = network(containing: id, doc: doc) else { return 0 }
        var n = 0
        for r in net.runs { if let i = doc.elementIndex(r), doc.elements[i].props["system"] != system.uppercased() { doc.elements[i].props["system"] = system.uppercased(); n += 1 } }
        return n
    }

    /// Schedule rows: Network, System, Runs, Fixtures, Length (m), Open ends.
    public static func scheduleRows(doc: ArchiDocument) -> [[String]] {
        let m = doc.units.mm / 1000
        var rows = [["Network", "System", "System Name", "Runs", "Fixtures", "Length (m)", "Open Ends"]]
        for (i, n) in networks(doc: doc).enumerated() {
            let name = RunFamilies.systems.first { $0.code == n.system }?.name ?? ""
            rows.append(["N\(i + 1)", n.system.isEmpty ? "—" : n.system, name, "\(n.runs.count)", "\(n.fixtures.count)", String(format: "%.2f", n.length * m), "\(n.openEnds.count)"])
        }
        return rows
    }
}

// MARK: - Lighting fixtures

/// Photometric data of a luminaire (element props override the family defaults):
/// props "lumens", "watts", "cct" (K), "beamAngle" (degrees), "lightLoss" (maintenance factor), "dimming" (0–1).
public struct Photometry: Hashable {
    public var lumens: Double
    public var watts: Double
    public var cct: Double
    public var beamAngle: Double
    public var maintenanceFactor: Double
    public var dimming: Double
    public var efficacy: Double { watts > 0 ? lumens / watts : 0 }
    /// Peak luminous intensity (cd) for a uniform cone of `beamAngle`.
    public var candela: Double {
        let half = min(max(beamAngle, 1), 360) / 2 * .pi / 180
        let sr = 2 * Double.pi * (1 - cos(half))
        return lumens * dimming / max(sr, 1e-6)
    }
    /// Approximate RGB of a black body at `cct` (Tanner Helland fit), 0…1.
    public var color: RGBA {
        let t = min(max(cct, 1000), 40000) / 100
        var r: Double, g: Double, b: Double
        if t <= 66 { r = 255; g = 99.4708025861 * log(t) - 161.1195681661 } else { r = 329.698727446 * pow(t - 60, -0.1332047592); g = 288.1221695283 * pow(t - 60, -0.0755148492) }
        if t >= 66 { b = 255 } else if t <= 19 { b = 0 } else { b = 138.5177312231 * log(t - 10) - 305.0447927307 }
        func c(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGBA(c(r), c(g), c(b))
    }
}

/// A light source for renderers (world position/direction in drawing units).
public struct RenderLight: Hashable {
    public var id: EntityID
    public var position: Vec3
    public var direction: Vec3
    public var color: RGBA
    public var lumens: Double
    public var candela: Double
    /// Full cone angle in degrees (360 = omnidirectional).
    public var spotAngle: Double
}

public enum LightingFixtures {
    /// Family defaults (lm, W, K, beam°).
    static let defaults: [String: (Double, Double, Double, Double)] = [
        "light-ceiling": (2500, 22, 3000, 110),
        "light-wall": (800, 9, 2700, 160),
    ]

    public static func isLight(_ el: BIMElement) -> Bool {
        guard case .component(let g) = el.geometry else { return false }
        if el.props["lumens"] != nil { return true }
        if let f = ComponentLibrary.family(g.family) { return f.category == "Lighting" }
        return g.category.caseInsensitiveCompare("Lighting") == .orderedSame
    }

    public static func photometry(_ el: BIMElement) -> Photometry {
        var fam = ""
        if case .component(let g) = el.geometry { fam = ComponentLibrary.family(g.family)?.id ?? "" }
        let d = defaults[fam] ?? (1500, 15, 3000, 120)
        func v(_ k: String, _ def: Double) -> Double { el.props[k].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? def }
        return Photometry(lumens: max(v("lumens", d.0), 0), watts: max(v("watts", d.1), 0), cct: v("cct", d.2), beamAngle: v("beamAngle", d.3),
                          maintenanceFactor: min(max(v("lightLoss", 0.8), 0.1), 1), dimming: min(max(v("dimming", 1), 0), 1))
    }

    /// Lights for rendering: ceiling lights point down from their underside, wall lights outwards (+Y is the back).
    public static func renderLights(doc: ArchiDocument) -> [RenderLight] {
        var out: [RenderLight] = []
        for el in ModelSets.visibleModel(doc).elements where isLight(el) && doc.isVisible(layer: el.layer) {
            guard case .component(let g) = el.geometry else { continue }
            let ph = photometry(el)
            let z = (doc.level(el.level)?.elevation ?? 0) + g.baseOffset
            let wall = ComponentLibrary.family(g.family)?.id == "light-wall"
            let front = Vec2(sin(g.rotation), -cos(g.rotation))   // local −Y
            let dir = wall ? Vec3(front.x, front.y, -0.3).normalized : Vec3(0, 0, -1)
            let pos = wall ? Vec3(g.position.x + front.x * g.size.y / 2, g.position.y + front.y * g.size.y / 2, z + g.size.z / 2) : Vec3(g.position.x, g.position.y, z)
            out.append(RenderLight(id: el.id, position: pos, direction: dir, color: ph.color, lumens: ph.lumens * ph.dimming, candela: ph.candela, spotAngle: ph.beamAngle))
        }
        return out
    }

    /// Room containing a plan point on a level.
    static func room(at p: Vec2, level: Int, doc: ArchiDocument) -> BIMElement? {
        doc.elements.first { el in
            guard el.level == level, el.props["areaScheme"] == nil, case .space(let s) = el.geometry, s.boundary.count >= 3 else { return false }
            return GeometryOps.pointInPolygon(p, s.boundary)
        }
    }

    /// Fixture schedule: Mark, Family/Type, Level, Room, X, Y, Rotation (°), lm, W, lm/W, K. Totals row at the end.
    public static func scheduleRows(doc d0: ArchiDocument) -> [[String]] {
        let doc = ModelSets.scheduleModel(d0)
        let m = doc.units.mm
        var rows = [["Mark", "Type", "Level", "Room", "X", "Y", "Rotation", "Lumens", "Watts", "lm/W", "CCT"]]
        var tl = 0.0, tw = 0.0, n = 0
        let lights = doc.elements.filter(isLight).sorted { (doc.level($0.level)?.elevation ?? 0, $0.id) < (doc.level($1.level)?.elevation ?? 0, $1.id) }
        for el in lights {
            guard case .component(let g) = el.geometry else { continue }
            let ph = photometry(el)
            let type = el.props["type"] ?? ComponentLibrary.family(g.family)?.name ?? (el.name.isEmpty ? g.category : el.name)
            let rm = room(at: g.position, level: el.level, doc: doc).map { r -> String in
                if case .space(let s) = r.geometry { return [s.number, s.name].filter { !$0.isEmpty }.joined(separator: " ") }; return ""
            } ?? ""
            n += 1
            rows.append([el.props["mark"] ?? "L\(n)", type, doc.level(el.level)?.name ?? "\(el.level)", rm, fmt(g.position.x * m / 1000, 3), fmt(g.position.y * m / 1000, 3),
                         fmt(normAngle(g.rotation) * 180 / .pi, 1), fmt(ph.lumens, 0), fmt(ph.watts, 1), fmt(ph.efficacy, 1), fmt(ph.cct, 0)])
            tl += ph.lumens; tw += ph.watts
        }
        rows.append(["Total", "\(n) fixtures", "", "", "", "", "", fmt(tl, 0), fmt(tw, 1), tw > 0 ? fmt(tl / tw, 1) : "", ""])
        return rows
    }

    /// Average maintained illuminance (lux) per room by the lumen method: E = Σ(lm · MF · UF) / A (UF default 0.6).
    public static func roomIlluminance(doc: ArchiDocument, utilisation uf: Double = 0.6) -> [(room: EntityID, name: String, lux: Double, fixtures: Int, wattsPerM2: Double)] {
        let d = ModelSets.scheduleModel(doc)
        let m2 = pow(d.units.mm, 2) / 1e6
        var out: [(room: EntityID, name: String, lux: Double, fixtures: Int, wattsPerM2: Double)] = []
        for r in d.elements {
            guard r.props["areaScheme"] == nil, case .space(let s) = r.geometry, s.boundary.count >= 3 else { continue }
            let a = abs(GeometryOps.signedArea(s.boundary)) * m2
            guard a > 1e-9 else { continue }
            var lm = 0.0, w = 0.0, k = 0
            for el in d.elements where el.level == r.level && isLight(el) {
                guard case .component(let g) = el.geometry, GeometryOps.pointInPolygon(g.position, s.boundary) else { continue }
                let ph = photometry(el)
                lm += ph.lumens * ph.dimming * ph.maintenanceFactor * uf; w += ph.watts; k += 1
            }
            out.append((r.id, s.name.isEmpty ? r.name : s.name, lm / a, k, w / a))
        }
        return out
    }
}
