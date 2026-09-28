// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac render, material and environment commands (ArchiApp/AppCommandsRound9.swift LIGHT, FOG,
// MATEMISSIVE, MATMAPPING, BILLBOARD, RENDERPROMPT, PHASEANIMATION; AppCommandsRound10.swift MATMAPS, MATASSET,
// PROCMATERIAL, MATFROMIMAGE, WATER, SCATTER; AppCommandsRound11.swift MECHANISMPLAY; AppCommandsRound12.swift AODIALOG)
// with the same names, aliases, prompts, keywords, stored variables and messages, and the data the Windows shell needs
// for them (docs/ENGINE-PROTOCOL.md "Render, materials and environment"). Where the Mac opens a window, renders a video
// or generates images the engine asks the shell with a `host` notification. Registered by archi-engine only.
import Foundation

public enum EngineRenderExtrasMethods {
    public static let all: [String] = ["render.ao", "render.aoSet", "render.phaseFrames", "render.promptSettings", "render.iesProfile", "render.mechanismDone"]
}

// MARK: - Stored data (same variables and JSON as the Mac)

/// PBR maps of a material (ArchiApp MaterialMaps): MATMAPS:<NAME> as JSON with sorted keys.
struct EngineMaterialMaps: Codable, Equatable {
    var normal: String?
    var roughness: String?
    var metallic: String?
    var ao: String?
    var displacement: String?
    var normalStrength = 1.0
    var displacementScale = 0.0

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        normal = try c.decodeIfPresent(String.self, forKey: .normal)
        roughness = try c.decodeIfPresent(String.self, forKey: .roughness)
        metallic = try c.decodeIfPresent(String.self, forKey: .metallic)
        ao = try c.decodeIfPresent(String.self, forKey: .ao)
        displacement = try c.decodeIfPresent(String.self, forKey: .displacement)
        normalStrength = try c.decodeIfPresent(Double.self, forKey: .normalStrength) ?? 1
        displacementScale = try c.decodeIfPresent(Double.self, forKey: .displacementScale) ?? 0
    }

    var isEmpty: Bool { [normal, roughness, metallic, ao, displacement].allSatisfy { $0 == nil } }
    static let slots: [(title: String, key: WritableKeyPath<EngineMaterialMaps, String?>)] =
        [("Normal", \.normal), ("Roughness", \.roughness), ("Metallic", \.metallic), ("AO", \.ao), ("Displacement", \.displacement)]

    static func key(_ material: String) -> String { "MATMAPS:" + material.uppercased() }
    static func load(_ material: String, doc: ArchiDocument) -> EngineMaterialMaps {
        guard let s = doc.variable(key(material)), let m = try? JSONDecoder().decode(EngineMaterialMaps.self, from: Data(s.utf8)) else { return EngineMaterialMaps() }
        return m
    }
    static func store(_ m: EngineMaterialMaps, material: String, in doc: inout ArchiDocument) {
        if m.isEmpty && m.normalStrength == 1 && m.displacementScale == 0 { doc.variables[key(material)] = nil; return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(m) { doc.setVariable(key(material), String(decoding: d, as: UTF8.self)) }
    }
}

/// Material assets apart from the render appearance (ArchiApp MaterialAssetSet): MATASSET:<NAME> as JSON.
struct EngineMaterialAssets: Codable, Equatable {
    var description = ""
    var manufacturer = ""
    var model = ""
    var mark = ""
    var keynote = ""
    var url = ""
    var cost: Double?
    var useRenderAppearance = true
    var shadingColor: String?
    var surfacePattern: String?
    var cutColor: String?
    var density: Double?
    var conductivity: Double?
    var specificHeat: Double?
    var emissivity: Double?
    var compressiveStrength: Double?
    var youngsModulus: Double?

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: k) ?? "" }
        description = try s(.description); manufacturer = try s(.manufacturer); model = try s(.model); mark = try s(.mark)
        keynote = try s(.keynote); url = try s(.url)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        useRenderAppearance = try c.decodeIfPresent(Bool.self, forKey: .useRenderAppearance) ?? true
        shadingColor = try c.decodeIfPresent(String.self, forKey: .shadingColor)
        surfacePattern = try c.decodeIfPresent(String.self, forKey: .surfacePattern)
        cutColor = try c.decodeIfPresent(String.self, forKey: .cutColor)
        density = try c.decodeIfPresent(Double.self, forKey: .density)
        conductivity = try c.decodeIfPresent(Double.self, forKey: .conductivity)
        specificHeat = try c.decodeIfPresent(Double.self, forKey: .specificHeat)
        emissivity = try c.decodeIfPresent(Double.self, forKey: .emissivity)
        compressiveStrength = try c.decodeIfPresent(Double.self, forKey: .compressiveStrength)
        youngsModulus = try c.decodeIfPresent(Double.self, forKey: .youngsModulus)
    }

    static func key(_ material: String) -> String { "MATASSET:" + material.uppercased() }
    static func load(_ material: String, doc: ArchiDocument) -> EngineMaterialAssets {
        if let s = doc.variable(key(material)), let a = try? JSONDecoder().decode(EngineMaterialAssets.self, from: Data(s.utf8)) { return a }
        return defaults(for: material)
    }
    static func store(_ a: EngineMaterialAssets, material: String, in doc: inout ArchiDocument) {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(a) { doc.setVariable(key(material), String(decoding: d, as: UTF8.self)) }
    }
    /// Typical physical/thermal properties by material name (EN ISO 10456 order of magnitude).
    static func defaults(for name: String) -> EngineMaterialAssets {
        var a = EngineMaterialAssets()
        let n = name.lowercased()
        let table: [(String, Double, Double, Double, Double?)] = [
            ("concrete", 2400, 2.0, 1000, 30), ("brick", 1800, 0.77, 840, 20), ("plaster", 1200, 0.57, 1000, nil), ("gypsum", 900, 0.25, 1000, nil),
            ("wood", 500, 0.13, 1600, 24), ("timber", 500, 0.13, 1600, 24), ("glass", 2500, 1.0, 750, nil), ("steel", 7850, 50, 450, 355),
            ("aluminium", 2700, 160, 880, 200), ("stone", 2600, 2.3, 1000, 60), ("insulation", 30, 0.035, 1450, nil), ("tile", 2300, 1.3, 840, nil),
            ("water", 1000, 0.6, 4180, nil), ("grass", 1500, 1.5, 1800, nil), ("roof", 2000, 1.0, 800, nil),
        ]
        if let t = table.first(where: { n.contains($0.0) }) {
            a.density = t.1; a.conductivity = t.2; a.specificHeat = t.3; a.compressiveStrength = t.4
            a.emissivity = n.contains("aluminium") || n.contains("steel") ? 0.2 : 0.9
        }
        return a
    }
    func thermalResistance(thickness mm: Double) -> Double? {
        guard let k = conductivity, k > 0, mm > 0 else { return nil }
        return mm / 1000 / k
    }
}

/// Texture mapping of a material (ArchiApp TextureMapping.Settings): MATMAP:<NAME> = "mode;offsetX,offsetY;rotation;scale".
struct EngineTextureMapping: Equatable {
    static let modes = ["Box", "Planar", "Cylindrical", "Spherical", "UV"]
    var mode = "Box"
    var offset = Vec2.zero
    var rotation = 0.0
    var scale = 1.0
    var isDefault: Bool { self == EngineTextureMapping() }
    var stored: String { mode + ";" + fmt(offset.x) + "," + fmt(offset.y) + ";" + fmt(rotation) + ";" + fmt(scale) }
    init() {}
    init?(stored s: String) {
        let p = s.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let m = EngineTextureMapping.modes.first(where: { $0.caseInsensitiveCompare(p.first ?? "") == .orderedSame }) else { return nil }
        mode = m
        if p.count > 1 { let o = p[1].split(separator: ",").compactMap { Double($0) }; if o.count == 2 { offset = Vec2(o[0], o[1]) } }
        if p.count > 2, let r = Double(p[2]) { rotation = r }
        if p.count > 3, let k = Double(p[3]), k > 0 { scale = k }
    }
    static func key(_ material: String) -> String { "MATMAP:" + material.uppercased() }
    static func load(_ material: String, doc: ArchiDocument) -> EngineTextureMapping { doc.variable(key(material)).flatMap(EngineTextureMapping.init(stored:)) ?? EngineTextureMapping() }
    static func store(_ s: EngineTextureMapping, material: String, in doc: inout ArchiDocument) {
        if s.isDefault { doc.variables[key(material)] = nil } else { doc.setVariable(key(material), s.stored) }
    }
}

/// IESNA LM-63 photometric file (ArchiApp IESProfile): candela by vertical angle, flux and beam angle.
struct EngineIESProfile: Equatable {
    var lumensPerLamp: Double
    var lamps: Int
    var vertical: [Double]
    var horizontal: [Double]
    var candela: [[Double]]

    var maxCandela: Double { candela.flatMap { $0 }.max() ?? 0 }
    var declaredLumens: Double? { lumensPerLamp > 0 ? lumensPerLamp * Double(lamps) : nil }

    static func parse(_ text: String) -> EngineIESProfile? {
        let lines = text.components(separatedBy: .newlines)
        guard let ti = lines.firstIndex(where: { $0.uppercased().hasPrefix("TILT=") }) else { return nil }
        var nums: [Double] = []
        for l in lines[(ti + 1)...] { nums += l.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\r" }).compactMap { Double($0) } }
        guard nums.count >= 13 else { return nil }
        let lamps = Int(nums[0]), lm = nums[1], mult = nums[2], nv = Int(nums[3]), nh = Int(nums[4])
        guard nv > 0, nh > 0, lamps > 0 else { return nil }
        var i = 13
        guard nums.count >= i + nv + nh + nv * nh else { return nil }
        let v = Array(nums[i..<(i + nv)]); i += nv
        let h = Array(nums[i..<(i + nh)]); i += nh
        var grid: [[Double]] = []
        for _ in 0..<nh { grid.append(nums[i..<(i + nv)].map { $0 * mult }); i += nv }
        return EngineIESProfile(lumensPerLamp: lm, lamps: lamps, vertical: v, horizontal: h, candela: grid)
    }
    static func load(_ path: String) -> EngineIESProfile? {
        let p = (path.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath
        guard let d = FileManager.default.contents(atPath: p) else { return nil }
        return parse(String(decoding: d, as: UTF8.self))
    }
    /// Candela averaged over the horizontal planes at each vertical angle.
    var averaged: [Double] {
        (0..<vertical.count).map { k in candela.map { $0[k] }.reduce(0, +) / Double(max(candela.count, 1)) }
    }
    func intensity(vertical a: Double) -> Double {
        let avg = averaged
        guard let first = vertical.first, let last = vertical.last, !avg.isEmpty else { return 0 }
        if a <= first { return avg[0] }
        if a >= last { return avg[avg.count - 1] }
        for k in 1..<vertical.count where a <= vertical[k] {
            let t = (a - vertical[k - 1]) / max(vertical[k] - vertical[k - 1], 1e-9)
            return avg[k - 1] + (avg[k] - avg[k - 1]) * t
        }
        return avg[avg.count - 1]
    }
    var integratedLumens: Double {
        guard vertical.count >= 2, let lo = vertical.first, let hi = vertical.last else { return 0 }
        var f = 0.0
        let steps = 720
        for k in 0..<steps {
            let a0 = lo + (hi - lo) * Double(k) / Double(steps), a1 = lo + (hi - lo) * Double(k + 1) / Double(steps)
            let c0 = cos(a0 * .pi / 180), c1 = cos(a1 * .pi / 180)
            f += intensity(vertical: (a0 + a1) / 2) * 2 * .pi * (c0 - c1)
        }
        return f
    }
    var beamAngle: Double {
        let peak = maxCandela
        guard peak > 0 else { return 0 }
        var a = 0.0
        while a <= 180 { if intensity(vertical: a) < peak / 2 { return min(2 * a, 360) }; a += 0.25 }
        return 360
    }
    /// The distribution for the shell's lights: vertical angles (degrees, 0 = down) and candela relative to the peak.
    var json: EngineJSON {
        var o = EngineObject()
        let peak = max(maxCandela, 1e-9)
        o.set("vertical", EngineJSON.numbers(vertical))
        o.set("relative", EngineJSON.numbers(averaged.map { $0 / peak }))
        o.set("maxCandela", maxCandela)
        o.set("lumens", declaredLumens ?? integratedLumens)
        o.set("beam", beamAngle)
        return o.json
    }
}

/// Water surfaces (ArchiApp WaterSurface).
enum EngineWater {
    static let materialName = "Water"
    static let layer = "WATER"
    static func ensureMaterial(in doc: inout ArchiDocument) {
        if doc.material(materialName) == nil {
            doc.materials.append(Material(name: materialName, color: RGBA(0.16, 0.38, 0.45), roughness: 0.03, metalness: 0, transparency: 0.6, cutPattern: "SOLID"))
        }
        doc.setVariable("MATWATER:" + materialName.uppercased(), "1")
    }
    static func entity(boundary: [Vec2], elevation: Double, depth: Double) -> Entity? {
        var pts = boundary
        if pts.count > 2, let f = pts.first, let l = pts.last, f.isClose(l, tol: 1e-9) { pts.removeLast() }
        guard pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-6 else { return nil }
        let d = max(depth, 1)
        let s = SolidGeom(kind: .extrusion, origin: Vec3(0, 0, elevation - d), profile: pts, height: d)
        return Entity(layer: layer, color: .aci(5), geometry: .solid(s), props: ["material": materialName, "water": "1"])
    }
}

/// Scattered planting (ArchiApp Scatter): Poisson-disk points and low-poly plants as mesh solids.
enum EngineScatter {
    static let kinds = ["Grass", "Flowers", "Shrubs", "Trees"]
    static let layer = "PLANTING"
    static func density(_ k: String) -> Double {
        switch k { case "Grass": return 60; case "Flowers": return 12; case "Shrubs": return 1.2; default: return 0.02 }
    }
    static func height(_ k: String) -> Double {
        switch k { case "Grass": return 120; case "Flowers": return 350; case "Shrubs": return 900; default: return 7000 }
    }
    static func materials(_ k: String) -> (String, String) {
        switch k {
        case "Grass": return ("Grass", "Grass")
        case "Flowers": return ("Foliage", "Flowers")
        case "Shrubs": return ("Shrub Foliage", "Shrub Foliage")
        default: return ("Bark", "Tree Foliage")
        }
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }

    static func inside(_ p: Vec2, _ poly: [Vec2]) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { c.toggle() }
            }
            j = i
        }
        return c
    }

    static func poissonDisk(in poly: [Vec2], holes: [[Vec2]] = [], minDistance r: Double, maxCount: Int, seed: UInt64) -> [Vec2] {
        guard poly.count >= 3, r > 0, maxCount > 0 else { return [] }
        let b = BBox2(points: poly)
        let cell = r / 2.squareRoot()
        let gw = max(1, Int(ceil(b.width / cell))), gh = max(1, Int(ceil(b.height / cell)))
        guard gw * gh < 40_000_000 else { return [] }
        var grid = [Int32](repeating: -1, count: gw * gh)
        var pts: [Vec2] = [], active: [Int] = []
        var rng = SplitMix(seed: seed)
        func ok(_ p: Vec2) -> Bool {
            guard p.x >= b.min.x, p.y >= b.min.y, p.x <= b.max.x, p.y <= b.max.y, inside(p, poly) else { return false }
            if holes.contains(where: { $0.count >= 3 && inside(p, $0) }) { return false }
            let gx = Int((p.x - b.min.x) / cell), gy = Int((p.y - b.min.y) / cell)
            for y in max(0, gy - 2)...min(gh - 1, gy + 2) {
                for x in max(0, gx - 2)...min(gw - 1, gx + 2) {
                    let k = grid[y * gw + x]
                    if k >= 0 && pts[Int(k)].distance(to: p) < r { return false }
                }
            }
            return true
        }
        func add(_ p: Vec2) {
            let gx = min(gw - 1, Int((p.x - b.min.x) / cell)), gy = min(gh - 1, Int((p.y - b.min.y) / cell))
            grid[gy * gw + gx] = Int32(pts.count); active.append(pts.count); pts.append(p)
        }
        var tries = 0
        while pts.isEmpty && tries < 10_000 {
            let x = b.min.x + rng.next() * b.width
            let y = b.min.y + rng.next() * b.height
            let p = Vec2(x, y)
            if ok(p) { add(p) }
            tries += 1
        }
        while !active.isEmpty && pts.count < maxCount {
            let ai = Int(rng.next() * Double(active.count)) % active.count
            let c = pts[active[ai]]
            var found = false
            for _ in 0..<30 {
                let a = rng.next() * 2 * .pi
                let d = r * (1 + rng.next())
                let p = Vec2(c.x + cos(a) * d, c.y + sin(a) * d)
                if ok(p) { add(p); found = true; if pts.count >= maxCount { break } }
            }
            if !found { active.remove(at: ai) }
        }
        return pts
    }

    static func spacing(density: Double) -> Double { (0.7 / max(density, 1e-6)).squareRoot() * 1000 }

    private static func tri(_ v: inout [Vec3], _ t: inout [Int], _ p: Vec3, _ q: Vec3, _ r: Vec3) {
        let b = v.count
        v += [p, q, r]
        t += [b, b + 1, b + 2, b, b + 2, b + 1]
    }
    private static func blob(_ v: inout [Vec3], _ t: inout [Int], _ c: Vec3, _ rx: Double, _ rz: Double, _ rng: inout SplitMix) {
        let rot = rng.next() * .pi
        var ring: [Vec3] = [], upper: [Vec3] = []
        for i in 0..<6 {
            let a = rot + Double(i) * .pi / 3
            ring.append(Vec3(c.x + cos(a) * rx, c.y + sin(a) * rx, c.z))
            let u = rot + (Double(i) + 0.5) * .pi / 3
            upper.append(Vec3(c.x + cos(u) * rx * 0.6, c.y + sin(u) * rx * 0.6, c.z + rz * 0.6))
        }
        let top = Vec3(c.x, c.y, c.z + rz), bot = Vec3(c.x, c.y, c.z - rz * 0.6)
        for i in 0..<6 {
            let j = (i + 1) % 6
            tri(&v, &t, ring[i], ring[j], upper[i]); tri(&v, &t, upper[i], ring[j], upper[j]); tri(&v, &t, upper[i], upper[j], top)
            tri(&v, &t, ring[j], ring[i], bot)
        }
    }

    static func meshes(_ kind: String, at points: [Vec2], z: Double, height h0: Double, seed: UInt64) -> (a: ([Vec3], [Int]), b: ([Vec3], [Int])) {
        var av: [Vec3] = [], at: [Int] = [], bv: [Vec3] = [], bt: [Int] = []
        var rng = SplitMix(seed: seed &+ 77)
        for p in points {
            let h = h0 * (0.75 + 0.5 * rng.next())
            switch kind {
            case "Grass":
                for k in 0..<3 {
                    let a = rng.next() * 2 * .pi + Double(k) * 2.1
                    let w = h * 0.12
                    let dx = cos(a) * w, dy = sin(a) * w
                    let lean = Vec3(cos(a + 1.3) * h * 0.2, sin(a + 1.3) * h * 0.2, 0)
                    tri(&bv, &bt, Vec3(p.x - dx, p.y - dy, z), Vec3(p.x + dx, p.y + dy, z), Vec3(p.x, p.y, z + h) + lean)
                }
            case "Flowers":
                tri(&av, &at, Vec3(p.x - 4, p.y, z), Vec3(p.x + 4, p.y, z), Vec3(p.x, p.y, z + h))
                blob(&bv, &bt, Vec3(p.x, p.y, z + h), h * 0.12, h * 0.08, &rng)
            case "Shrubs":
                blob(&bv, &bt, Vec3(p.x, p.y, z + h * 0.5), h * 0.6, h * 0.5, &rng)
            default:
                let r = h * 0.025
                var ring: [Vec2] = []
                for i in 0..<6 { let a = Double(i) * .pi / 3; ring.append(Vec2(cos(a) * r, sin(a) * r)) }
                let th = h * 0.45
                for i in 0..<6 {
                    let j = (i + 1) % 6
                    let a0 = Vec3(p.x + ring[i].x, p.y + ring[i].y, z), a1 = Vec3(p.x + ring[j].x, p.y + ring[j].y, z)
                    let b0 = Vec3(p.x + ring[i].x * 0.6, p.y + ring[i].y * 0.6, z + th)
                    let b1 = Vec3(p.x + ring[j].x * 0.6, p.y + ring[j].y * 0.6, z + th)
                    tri(&av, &at, a0, a1, b1); tri(&av, &at, a0, b1, b0)
                }
                blob(&bv, &bt, Vec3(p.x, p.y, z + h * 0.62), h * 0.3, h * 0.38, &rng)
            }
        }
        return ((av, at), (bv, bt))
    }

    static func entities(_ kind: String, boundary: [Vec2], holes: [[Vec2]] = [], density: Double, z: Double, height: Double, seed: UInt64, maxCount: Int = 200_000) -> (entities: [Entity], count: Int) {
        let area = abs(GeometryOps.signedArea(boundary)) / 1e6
        let target = min(maxCount, Int((area * density).rounded(.up)))
        let pts = poissonDisk(in: boundary, holes: holes, minDistance: spacing(density: density), maxCount: max(target, 1), seed: seed)
        guard !pts.isEmpty else { return ([], 0) }
        let (a, b) = meshes(kind, at: pts, z: z, height: height, seed: seed)
        var out: [Entity] = []
        let props = ["scatter": kind, "scatterCount": "\(pts.count)", "scatterSeed": "\(seed)"]
        let mats = materials(kind)
        if !a.1.isEmpty {
            var p = props; p["material"] = mats.0
            out.append(Entity(layer: layer, color: .aci(3), geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: a.0, meshTriangles: a.1)), props: p))
        }
        if !b.1.isEmpty {
            var p = props; p["material"] = mats.1
            out.append(Entity(layer: layer, color: .aci(3), geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: b.0, meshTriangles: b.1)), props: p))
        }
        return (out, pts.count)
    }

    static func ensureMaterials(_ kind: String, in doc: inout ArchiDocument) {
        let defs: [String: Material] = [
            "Grass": Material(name: "Grass", color: RGBA(0.35, 0.55, 0.25), roughness: 1),
            "Foliage": Material(name: "Foliage", color: RGBA(0.25, 0.48, 0.2), roughness: 0.9),
            "Flowers": Material(name: "Flowers", color: RGBA(0.86, 0.35, 0.45), roughness: 0.8),
            "Shrub Foliage": Material(name: "Shrub Foliage", color: RGBA(0.22, 0.42, 0.2), roughness: 0.95),
            "Tree Foliage": Material(name: "Tree Foliage", color: RGBA(0.26, 0.47, 0.22), roughness: 0.95),
            "Bark": Material(name: "Bark", color: RGBA(0.36, 0.27, 0.2), roughness: 0.95),
        ]
        let m = materials(kind)
        for n in [m.0, m.1] where doc.material(n) == nil { if let x = defs[n] { doc.materials.append(x) } }
    }
}

/// Render styles from a description (ArchiApp RenderPrompt.apply): the Render window settings it changes.
enum EngineRenderPrompt {
    struct Settings: Equatable {
        var environment = "Clear Sky"
        var hour: Double?
        var whiteBalance = 6500.0
        var exposure = 0.0
        var shadowSoftness = 4.0
        var shadowQuality = "High"
        var clay = false
        var ambientOcclusion = 1.0
        var depthOfField = false
        var fStop = 2.8
        var background = "Sky"
        var width = 1920
        var height = 1080
        var antialias = true
    }

    static func apply(_ prompt: String, to s: inout Settings) -> [String] {
        let p = prompt.lowercased()
        var applied: [String] = []
        func has(_ words: String...) -> Bool { words.contains { p.contains($0) } }
        if has("sunset", "golden hour", "dusk", "evening") { s.environment = "Sunset"; s.whiteBalance = 5200; s.hour = 19.5; applied.append("sunset sky, 19:30, warm") }
        else if has("sunrise", "dawn", "morning") { s.environment = "Clear Sky"; s.hour = 8; s.whiteBalance = 5600; applied.append("morning sun 08:00") }
        else if has("noon", "midday") { s.environment = "Clear Sky"; s.hour = 12; applied.append("noon sun") }
        if has("night", "nighttime") { s.environment = "Night"; s.hour = 22; s.exposure += 0.6; applied.append("night") }
        if has("overcast", "cloudy", "grey sky", "gray sky") { s.environment = "Overcast"; s.shadowSoftness = 14; applied.append("overcast") }
        if has("clear sky", "sunny", "blue sky") { s.environment = "Clear Sky"; applied.append("clear sky") }
        if has("physical sky") { s.environment = "Physical Sky"; applied.append("physical sky") }
        if has("studio") { s.environment = "Studio"; applied.append("studio light") }
        if has("clay", "white model", "massing") { s.clay = true; s.environment = "Studio"; applied.append("clay model") }
        if has("soft shadow") { s.shadowSoftness = 10; applied.append("soft shadows") }
        if has("sharp shadow", "crisp shadow", "hard shadow") { s.shadowSoftness = 1; s.shadowQuality = "Ultra"; applied.append("sharp shadows") }
        if has("no shadow") { s.shadowQuality = "Off"; applied.append("no shadows") }
        if has("warm") && !applied.contains(where: { $0.contains("warm") }) { s.whiteBalance = 4800; applied.append("warm white balance") }
        if has("cool", "cold", "blue tone") { s.whiteBalance = 8000; applied.append("cool white balance") }
        if has("bright", "airy", "high key") { s.exposure += 0.5; applied.append("brighter") }
        if has("dark", "moody", "dramatic", "low key") { s.exposure -= 0.5; s.ambientOcclusion = 1.6; applied.append("moody") }
        if has("depth of field", "bokeh", "shallow focus") { s.depthOfField = true; s.fStop = 2.0; applied.append("depth of field") }
        if has("white background") { s.background = "White"; applied.append("white background") }
        if has("transparent") { s.background = "Transparent"; applied.append("transparent background") }
        if has("8k") { s.width = 7680; s.height = 4320; applied.append("8K") }
        else if has("4k", "uhd") { s.width = 3840; s.height = 2160; applied.append("4K") }
        else if has("square", "instagram") { s.width = 2048; s.height = 2048; applied.append("square") }
        else if has("portrait", "vertical") { s.width = 1440; s.height = 2160; applied.append("portrait") }
        if has("high quality", "final", "best quality") { s.shadowQuality = "Ultra"; s.antialias = true; applied.append("high quality") }
        if has("draft", "quick", "preview") { s.shadowQuality = "Low"; s.antialias = false; applied.append("draft") }
        return applied
    }

    /// The "Prompt: …" render preset (RenderPreset fields the Render window reads).
    static func preset(_ text: String, _ s: Settings) -> EngineJSON {
        var o = EngineObject()
        o.set("name", "Prompt: " + String(text.prefix(40)))
        o.set("width", s.width); o.set("height", s.height); o.set("antialias", s.antialias); o.set("exposure", s.exposure)
        o.set("background", s.background); o.set("environment", s.environment); o.set("shadowQuality", s.shadowQuality)
        o.set("shadowSoftness", s.shadowSoftness); o.set("ambientOcclusion", s.ambientOcclusion); o.set("depthOfField", s.depthOfField)
        o.set("fStop", s.fStop); o.set("whiteBalance", s.whiteBalance); o.set("clay", s.clay)
        o.set("hour", s.hour.map { EngineJSON.number($0) } ?? .null)
        return o.json
    }
}

/// Ambient occlusion settings (ArchiApp AOForm, ArchiCore AmbientOcclusion): AOINTENSITY, AORADIUS, AOSAMPLES.
enum EngineAOSettings {
    static func json(_ doc: ArchiDocument) -> EngineJSON {
        let s = AmbientOcclusion.settings(doc)
        var o = EngineObject()
        o.set("intensity", s?.intensity ?? 0)
        o.set("radius", s?.radius ?? 1000 / max(doc.units.mm, 1e-9))
        o.set("samples", s?.samples ?? 24)
        o.set("units", doc.units.rawValue)
        o.set("unitMM", doc.units.mm)
        o.set("on", s != nil)
        // SceneKit screen-space occlusion of the viewport (AOForm.viewport): intensity and radius in metres.
        if let s {
            var v = EngineObject()
            v.set("intensity", 0.9 * s.intensity)
            v.set("radius", max(0.02, s.radius * doc.units.mm * 0.001))
            o.set("viewport", v.json)
        } else { o.set("viewport", EngineJSON.null) }
        return o.json
    }
    static func apply(intensity: Double, radius: Double, samples: Int, to d: inout ArchiDocument) {
        if intensity < 1e-9 { d.variables["AOINTENSITY"] = nil } else { d.setVariable("AOINTENSITY", fmt(min(intensity, 2), 4)) }
        d.setVariable("AORADIUS", fmt(max(radius, 1e-6), 6))
        d.setVariable("AOSAMPLES", "\(min(max(samples, 4), 256))")
    }
}

/// Construction sequence (ArchiApp PhasingAnimation): the elements shown in each frame of the 4D video and its caption.
@MainActor
enum EnginePhaseFrames {
    static func buildOrder(_ ids: [EntityID], doc: ArchiDocument) -> [EntityID] {
        let keep = Set(ids)
        var d = doc
        d.elements = doc.elements.filter { keep.contains($0.id) }.map { e in
            var x = e
            x.props["phaseCreated"] = nil; x.props["phaseDemolished"] = nil
            return x
        }
        d.variables["PHASE"] = nil; d.variables["PHASEFILTER"] = nil
        var z: [EntityID: Double] = [:]
        for g in MeshBuilder.build(doc: d) { if let id = g.id { z[id] = Swift.min(z[id] ?? .infinity, g.mesh.bounds.min.z) } }
        func zOf(_ id: EntityID) -> Double {
            if let v = z[id] { return v }
            return doc.element(id).flatMap { doc.level($0.level)?.elevation } ?? 0
        }
        return ids.sorted { a, b in
            let za = zOf(a), zb = zOf(b)
            return za != zb ? za < zb : a < b
        }
    }

    /// Element ids of every phase step: `per` frames per phase, each frame one entry (ids, caption).
    static func phases(_ doc: ArchiDocument, framesPerPhase per0: Int) -> [(ids: [EntityID], caption: String?)] {
        let phases = max(doc.phases.count, 1), per = max(per0, 1)
        var created: [[EntityID]] = [], demolished: [[EntityID]] = [], existing: [[EntityID]] = []
        for p in 0..<phases {
            var ex: [EntityID] = [], cr: [EntityID] = [], dm: [EntityID] = []
            for e in doc.elements {
                switch Phasing.status(e.props, doc: doc, phase: p) {
                case .existing: ex.append(e.id)
                case .new: cr.append(e.id)
                case .demolished: dm.append(e.id)
                default: break
                }
            }
            existing.append(ex); created.append(buildOrder(cr, doc: doc)); demolished.append(buildOrder(dm, doc: doc))
        }
        var out: [(ids: [EntityID], caption: String?)] = []
        for f in 0..<(per * phases) {
            let p = Swift.min(f / per, phases - 1)
            let t = Double(Swift.min(f - p * per, per - 1) + 1) / Double(per)
            var ids = existing[p]
            let c = created[p], dm = demolished[p]
            ids += c.prefix(Int((Double(c.count) * t).rounded(.up)))
            ids += dm.prefix(Int((Double(dm.count) * (1 - t)).rounded(.down)))
            let caption: String? = doc.phases.indices.contains(p) ? "Phase \(p + 1) of \(doc.phases.count): \(doc.phases[p])" : nil
            out.append((ids.sorted(), caption))
        }
        return out
    }

    /// Work-schedule 4D: elements of tasks started by the end of each working day (plus unscheduled ones).
    static func schedule(_ doc: ArchiDocument, framesPerDay per0: Int) throws -> [(ids: [EntityID], caption: String?)] {
        guard let s = Scheduler.load(doc) else { throw CommandError.invalid("No work schedule (WORKSCHEDULE Generate).") }
        let timing = try Scheduler.cpm(s)
        let days = Swift.max(1, timing.values.map(\.ef).max() ?? 1)
        let per = Swift.max(1, per0)
        let fmtr = DateFormatter(); fmtr.dateStyle = .medium
        var out: [(ids: [EntityID], caption: String?)] = []
        for day in 0..<days {
            let st = Scheduler.states(s, timing: timing, day: day)
            let ids = doc.elements.filter { e in st[e.id].map { $0 != .notStarted } ?? true }.map(\.id).sorted()
            let when = fmtr.string(from: Scheduler.date(s, workday: day))
            let caption = "Day \(day + 1) of \(days) — " + when
            for _ in 0..<per { out.append((ids, caption)) }
        }
        return out
    }

    /// Frames as JSON: distinct id sets once (`sets`), each frame an index into them and a caption.
    static func json(_ frames: [(ids: [EntityID], caption: String?)], fps: Int, all: [EntityID]) -> EngineJSON {
        var sets: [[EntityID]] = [], index: [[EntityID]: Int] = [:]
        var fr: [EngineJSON] = []
        for f in frames {
            let k: Int
            if let i = index[f.ids] { k = i } else { k = sets.count; index[f.ids] = k; sets.append(f.ids) }
            var o = EngineObject()
            o.set("set", k)
            o.set("caption", EngineJSON.optString(f.caption))
            fr.append(o.json)
        }
        var o = EngineObject()
        o.set("fps", fps)
        o.set("elements", EngineJSON.array(all.map { EngineJSON.int($0) }))
        o.set("sets", EngineJSON.array(sets.map { s in EngineJSON.array(s.map { EngineJSON.int($0) }) }))
        o.set("frames", EngineJSON.array(fr))
        return o.json
    }
}

// MARK: - Methods

extension EngineSession {
    func callRenderExtras(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "render.ao": return EngineAOSettings.json(editor.doc)
        case "render.aoSet":
            let cur = AmbientOcclusion.settings(editor.doc)
            let intensity = p["intensity"]?.doubleValue ?? cur?.intensity ?? 0
            let radius = p["radius"]?.doubleValue ?? cur?.radius ?? 1000 / max(editor.doc.units.mm, 1e-9)
            let samples = p["samples"]?.intValue ?? cur?.samples ?? 24
            guard intensity.isFinite, intensity >= 0, radius.isFinite, radius > 0 else { throw EngineError.params("intensity ≥ 0 and radius > 0") }
            editor.transaction("Ambient Occlusion") { d in EngineAOSettings.apply(intensity: intensity, radius: radius, samples: samples, to: &d) }
            var o = EngineObject()
            o.set("settings", EngineAOSettings.json(editor.doc))
            o.set("message", intensity < 1e-9 ? "Ambient occlusion off." : "Ambient occlusion \(fmt(min(intensity, 2), 2)).")
            return o.json
        case "render.phaseFrames":
            let src = p["source"]?.stringValue ?? "Phases"
            let fps = max(1, min(60, p["fps"]?.intValue ?? 30))
            let secs = p["seconds"]?.doubleValue ?? (src == "Schedule" ? 0.5 : 4)
            let doc = editor.doc
            let frames: [(ids: [EntityID], caption: String?)]
            if src == "Schedule" {
                frames = try EnginePhaseFrames.schedule(doc, framesPerDay: max(1, Int(secs * Double(fps))))
            } else {
                guard Phasing.isActive(doc), !doc.phases.isEmpty else { throw EngineError.params("No phased elements.") }
                frames = EnginePhaseFrames.phases(doc, framesPerPhase: max(2, Int(secs * Double(fps))))
            }
            return EnginePhaseFrames.json(frames, fps: fps, all: doc.elements.map(\.id))
        case "render.promptSettings":
            let text = try string(p, "text")
            var s = EngineRenderPrompt.Settings()
            let applied = EngineRenderPrompt.apply(text, to: &s)
            var o = EngineObject()
            o.set("applied", EngineJSON.strings(applied))
            o.set("preset", EngineRenderPrompt.preset(text, s))
            return o.json
        case "render.mechanismDone":
            mechanismPlaying = false
            return .object([])
        case "render.iesProfile":
            let path = try string(p, "path")
            guard let prof = EngineIESProfile.load(path) else { throw EngineError.params("Not an IES (LM-63) file: " + path) }
            return prof.json
        default: return nil
        }
    }
}

// MARK: - Commands

@MainActor
enum EngineRenderCommands {
    static var all: [CommandDef] {
        [light, fog, matEmissive, matMapping, billboard, renderPrompt, phaseAnimation, matMaps, matAsset, procMaterial, matFromImage,
         water, scatter, mechanismPlay, aoDialog]
    }

    static func number(_ ed: Editor, _ msg: String, _ def: Double) async throws -> Double {
        try await ed.getDistance(msg + " <" + fmt(def) + ">", defaultValue: def).value ?? def
    }
    static func text(_ ed: Editor, _ msg: String, _ def: String) async throws -> String {
        let s = try await ed.getString(msg + " <" + def + ">", defaultValue: def) ?? def
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return t.isEmpty ? def : t
    }
    /// A word or name typed at the prompt (AppCommandsNav.word).
    static func word(_ ed: Editor, _ msg: String) async throws -> String? {
        switch await ed.ask(InputRequest(msg, kinds: [.keyword, .string], keywords: [])) {
        case .keyword(let k): return k
        case .text(let t):
            let s = t.trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        case .number(let d): return fmt(d)
        case .cancel: throw CommandError.cancelled
        default: return nil
        }
    }
    static func materialName(_ ed: Editor, _ msg: String = "Material name") async throws -> String {
        let def = ed.doc.materials.first?.name ?? "Concrete"
        let n = try await text(ed, msg, def)
        guard let m = ed.doc.materials.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("No material named \(n).") }
        return m.name
    }
    static func expand(_ p: String) -> String { (p.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath }
    static func hexColor(_ s: String) -> RGBA? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return RGBA(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    static func hexRGB(_ c: RGBA) -> String {
        let r = Int((c.r * 255).rounded()), g = Int((c.g * 255).rounded()), b = Int((c.b * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    @MainActor static func host(_ ed: Editor, _ action: String, _ fields: [(String, EngineJSON)]) throws {
        try EngineUICommands.host(ed, action, fields)
    }
    static func boundaries(_ ed: Editor, _ ids: [EntityID]) -> [[Vec2]] {
        let ents: [Entity] = ids.compactMap { ed.doc.entity($0) }
        var out: [[Vec2]] = []
        for e in ents {
            switch e.geometry {
            case .polyline(let p):
                let n = p.vertices.count
                let closedByPoints = n > 3 && p.vertices[0].p.isClose(p.vertices[n - 1].p, tol: 1e-6)
                if p.closed || closedByPoints, let t = GeometryOps.tessellate(e.geometry, doc: ed.doc).first { out.append(t) }
            case .circle, .ellipse:
                if let t = GeometryOps.tessellate(e.geometry, doc: ed.doc).first { out.append(t) }
            default: break
            }
        }
        return out.filter { $0.count >= 3 }
    }

    // MARK: Lights, fog, emissive, mapping, billboards (AppCommandsRound9)

    static var light: CommandDef {
        CommandDef("LIGHT", aliases: ["LIGHTS", "POINTLIGHT", "SPOTLIGHT", "ARTIFICIALLIGHT"], category: "View", summary: "Places point, spot, area, line or IES lights (lumens, colour temperature, beam) that light the 3D view and renders; List, On/Off.") { ed in
            let k = try await ed.getKeyword("Light [Point/Spot/Area/Line/IES/List/On/Off]", ["Point", "Spot", "Area", "Line", "IES", "List", "On", "Off"], defaultValue: "Point") ?? "Point"
            switch k {
            case "List":
                let ls = EngineMeshJSON.lights(ed.doc).arrayValue ?? []
                if ls.isEmpty { ed.print(ed.doc.variable("ARTIFICIALLIGHTS") == "0" ? "Artificial lights are off." : "No lights."); return }
                for l in ls {
                    let kind = l["kind"]?.stringValue ?? "point"
                    let title = kind == "ies" ? "IES" : kind.capitalized
                    let pos = l["position"]?.arrayValue?.compactMap { $0.doubleValue } ?? [0, 0, 0]
                    let px = pos.count > 0 ? pos[0] : 0, py = pos.count > 1 ? pos[1] : 0, pz = pos.count > 2 ? pos[2] : 0
                    let lm = l["lumens"]?.doubleValue ?? 0, cct = l["cct"]?.doubleValue ?? 3000, beam = l["beam"]?.doubleValue ?? 60
                    let id = l["id"]?.intValue ?? 0
                    let beamText = kind == "spot" || kind == "ies" ? ", beam " + fmt(beam, 0) + "°" : ""
                    ed.print("  #\(id) \(title) at \(fmt(px, 0)),\(fmt(py, 0)),\(fmt(pz, 0)) — \(fmt(lm, 0)) lm, \(fmt(cct, 0)) K" + beamText)
                }
                return
            case "On", "Off":
                ed.doc.setVariable("ARTIFICIALLIGHTS", k == "On" ? "1" : "0"); ed.print("Artificial lights \(k.lowercased()).")
                return
            default: break
            }
            let mm = ed.doc.units.mm
            let p = try await ed.requirePoint(k == "Area" || k == "Line" ? "Specify light centre" : "Specify light location")
            var target: Vec2?
            if k == "Spot" || k == "IES" { target = try await ed.requirePoint("Specify target", base: p) { q in [.line(LineGeom(p, q))] } }
            let lz = (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) / mm
            let h = try await number(ed, "Height above level", 2400 / mm)
            var profile: EngineIESProfile?, iesPath: String?
            if k == "IES" {
                guard let f = try await ed.getString("IES file path"), !f.isEmpty else { return }
                let pth = expand(f)
                guard let pr = EngineIESProfile.load(pth) else { throw CommandError.invalid("Not an IES (LM-63) file: \(pth)") }
                profile = pr; iesPath = pth
                ed.print("IES: \(fmt(pr.maxCandela, 0)) cd peak, \(fmt(pr.declaredLumens ?? pr.integratedLumens, 0)) lm, beam \(fmt(pr.beamAngle, 0))°.")
            }
            let lmDefault = profile.map { $0.declaredLumens ?? $0.integratedLumens } ?? (k == "Area" ? 3000 : 800)
            let lm = try await number(ed, "Luminous flux (lm)", lmDefault)
            let cct = try await number(ed, "Colour temperature (K)", 3000)
            var beam = profile?.beamAngle ?? 60, size = Vec2(600, 600)
            if k == "Spot" { beam = try await number(ed, "Beam angle (degrees)", 45) }
            if k == "Area" {
                let w = try await number(ed, "Width", 600 / mm) * mm
                let l = try await number(ed, "Length", 600 / mm) * mm
                size = Vec2(w, l)
            }
            if k == "Line" { size = Vec2(20, try await number(ed, "Length", 1200 / mm) * mm) }
            guard lm >= 0, cct >= 1000, cct <= 20000, beam > 0, beam <= 179 else { throw CommandError.invalid("Values out of range.") }
            let z = (lz + h) * mm
            var props: [String: String] = ["light": k.lowercased(), "z": fmt(z), "lumens": fmt(lm), "cct": fmt(cct)]
            if k == "Spot" || k == "IES" { props["beam"] = fmt(min(max(beam, 1), 170)) }
            if let t = target { props["targetX"] = fmt(t.x); props["targetY"] = fmt(t.y); props["targetZ"] = fmt(lz * mm) }
            if k == "Area" || k == "Line" { props["width"] = fmt(size.x); props["length"] = fmt(size.y) }
            if let i = iesPath { props["ies"] = i }
            ed.doc.ensureLayer("LIGHTS")
            let id = ed.doc.add(Entity(layer: "LIGHTS", color: .aci(2), geometry: .point(p), props: props))
            ed.print("\(k) light #\(id): \(fmt(lm, 0)) lm, \(fmt(cct, 0)) K.")
        }
    }

    static var fog: CommandDef {
        CommandDef("FOG", aliases: ["ATMOSPHERE", "HAZE", "RENDERENVIRONMENT"], category: "View", summary: "Fog / atmospheric haze in the 3D view and renders: On/Off, start and end distance, colour and falloff (saved in the drawing).") { ed in
            let on = ed.doc.variable("FOG") == "1"
            let k = try await ed.getKeyword("Fog [On/Off/Settings]", ["On", "Off", "Settings"], defaultValue: on ? "Settings" : "On") ?? "On"
            var start = max(0, ed.doc.variable("FOGSTART").flatMap(Double.init) ?? 5000)
            var end = max(start + 1, ed.doc.variable("FOGEND").flatMap(Double.init) ?? 60000)
            var color = ed.doc.variable("FOGCOLOR").flatMap { $0.hasPrefix("#") ? RGBA(hex: $0) : nil } ?? RGBA(0.78, 0.8, 0.84)
            var density = min(max(ed.doc.variable("FOGDENSITY").flatMap(Double.init) ?? 1, 0.1), 4)
            @MainActor func store(_ on: Bool) {
                ed.doc.setVariable("FOG", on ? "1" : "0"); ed.doc.setVariable("FOGSTART", fmt(start)); ed.doc.setVariable("FOGEND", fmt(end))
                ed.doc.setVariable("FOGCOLOR", color.hex); ed.doc.setVariable("FOGDENSITY", fmt(density))
            }
            if k == "Off" { store(false); ed.print("Fog off."); return }
            let mm = ed.doc.units.mm
            start = try await number(ed, "Fog starts at distance", start / mm) * mm
            end = max(start + 1, try await number(ed, "Fully opaque at distance", end / mm) * mm)
            if let c = try await word(ed, "Colour (#RRGGBB) <\(color.hex)>"), c.hasPrefix("#"), c.count == 7 { color = RGBA(hex: c) }
            density = min(max(try await number(ed, "Falloff exponent (1 linear, 2 quadratic)", density), 0.1), 4)
            store(true)
            ed.print("Fog from \(fmt(start / mm, 0)) to \(fmt(end / mm, 0)), \(color.hex).")
        }
    }

    static var matEmissive: CommandDef {
        CommandDef("MATEMISSIVE", aliases: ["EMISSIVE", "SELFILLUM", "MATEMIT"], category: "View", summary: "Makes a material self-illuminated (luminance factor 0–20; 0 turns it off): screens, lamps, signs glow in 3D and renders.") { ed in
            let names = ed.doc.materials.map(\.name)
            guard !names.isEmpty else { throw CommandError.invalid("The drawing has no materials.") }
            ed.print("Materials: " + names.joined(separator: ", "))
            guard let n = try await word(ed, "Material name"), let mat = ed.doc.material(n.trimmingCharacters(in: .whitespaces)) else { throw CommandError.invalid("No such material.") }
            let key = "MATEMIT:" + mat.name.uppercased()
            let cur = ed.doc.variable(key).flatMap(Double.init).map { min(max($0, 0), 20) } ?? 0
            let v = try await number(ed, "Luminance factor", cur > 0 ? cur : 2)
            guard v >= 0, v <= 20 else { throw CommandError.invalid("Use 0–20.") }
            if v == 0 { ed.doc.variables[key] = nil } else { ed.doc.setVariable(key, fmt(v)) }
            ed.print(v == 0 ? "\(mat.name) is no longer emissive." : "\(mat.name) glows with factor \(fmt(v)).")
        }
    }

    static var matMapping: CommandDef {
        CommandDef("MATMAPPING", aliases: ["TEXTUREMAPPING", "UVMAPPING", "MATERIALMAPPING", "POSITIONTEXTURE"], category: "View", summary: "Texture mapping of a material: Box, Planar, Cylindrical, Spherical or UV, and texture positioning (offset, rotation, scale) on its faces; Reset.") { ed in
            guard !ed.doc.materials.isEmpty else { throw CommandError.invalid("The drawing has no materials.") }
            guard let n = try await word(ed, "Material name"), let mat = ed.doc.material(n) else { throw CommandError.invalid("No such material.") }
            var st = EngineTextureMapping.load(mat.name, doc: ed.doc)
            let modes = EngineTextureMapping.modes
            let k = try await ed.getKeyword("Mapping [\(modes.joined(separator: "/"))/Reset]", modes + ["Reset"], defaultValue: st.mode) ?? st.mode
            if k == "Reset" { EngineTextureMapping.store(EngineTextureMapping(), material: mat.name, in: &ed.doc); ed.print("\(mat.name): default box mapping."); return }
            st.mode = k
            let mm = ed.doc.units.mm
            let ox = try await number(ed, "Offset X", st.offset.x / mm) * mm
            let oy = try await number(ed, "Offset Y", st.offset.y / mm) * mm
            st.offset = Vec2(ox, oy)
            st.rotation = try await number(ed, "Rotation (degrees)", st.rotation)
            st.scale = try await number(ed, "Scale factor", st.scale)
            guard st.scale > 0 else { throw CommandError.invalid("The scale must be positive.") }
            EngineTextureMapping.store(st, material: mat.name, in: &ed.doc)
            let off = fmt(st.offset.x / mm) + "," + fmt(st.offset.y / mm)
            ed.print("\(mat.name): \(st.mode) mapping, offset \(off), rotation \(fmt(st.rotation))°, scale \(fmt(st.scale)).")
        }
    }

    static var billboard: CommandDef {
        CommandDef("BILLBOARD", aliases: ["CUTOUT", "IMAGECUTOUT", "ENTOURAGE"], category: "View", summary: "Places a 2D cutout that always faces the camera in 3D and renders: Person, Tree, Shrub or an image file (PNG with transparency).") { ed in
            let k = try await ed.getKeyword("Cutout [Person/Tree/Shrub/File]", ["Person", "Tree", "Shrub", "File"], defaultValue: "Person") ?? "Person"
            var src = k.lowercased()
            if k == "File" {
                guard let f = try await ed.getString("Image file path"), !f.isEmpty else { return }
                src = expand(f)
                guard FileManager.default.fileExists(atPath: src) else { throw CommandError.invalid("Cannot read image \(src).") }
            }
            let p = try await ed.requirePoint("Specify base point")
            let mm = ed.doc.units.mm
            let def = (k == "Tree" ? 6000 : k == "Shrub" ? 1200 : 1750) / mm
            let h = try await number(ed, "Height", def)
            guard h > 0 else { throw CommandError.invalid("Height must be positive.") }
            let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            ed.doc.ensureLayer("BILLBOARDS")
            let e = Entity(layer: "BILLBOARDS", color: .aci(3), geometry: .point(p), props: ["billboard": src, "z": fmt(lz), "height": fmt(h * mm)])
            let id = ed.doc.add(e)
            ed.print("Billboard #\(id) (\(k.lowercased()), \(fmt(h, 0)) high).")
        }
    }

    static var renderPrompt: CommandDef {
        CommandDef("RENDERPROMPT", aliases: ["AIRENDER", "RENDERSTYLE", "PROMPTRENDER"], category: "View", summary: "Styles the render from a description (e.g. “golden hour, soft shadows, warm, 4K”): saves it as the “Prompt” render preset and opens the render window.", modifies: false) { ed in
            guard let t = try await ed.getString("Describe the render"), !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            var s = EngineRenderPrompt.Settings()
            let applied = EngineRenderPrompt.apply(t, to: &s)
            guard !applied.isEmpty else { throw CommandError.invalid("No render style recognised (try: sunset, overcast, night, clay, soft shadows, warm, moody, depth of field, 4K).") }
            ed.print("Render style: " + applied.joined(separator: ", ") + ".")
            try host(ed, "output", [("op", .string("renderPrompt")), ("preset", EngineRenderPrompt.preset(t, s))])
        }
    }

    static var phaseAnimation: CommandDef {
        CommandDef("PHASEANIMATION", aliases: ["PHASEVIDEO", "4DVIDEO", "4DANIMATION"], category: "View", summary: "Construction sequence (4D) video from the phases (new elements appear bottom-up, demolished ones disappear) or from the work schedule (day by day), captioned (MP4).", modifies: false) { ed in
            let hasSchedule = Scheduler.load(ed.doc) != nil, hasPhases = Phasing.isActive(ed.doc) && !ed.doc.phases.isEmpty
            guard hasSchedule || hasPhases else { throw CommandError.invalid("No phased elements and no work schedule (PHASE / WORKSCHEDULE Generate).") }
            let src = try await ed.getKeyword("Sequence from [Phases/Schedule]", ["Phases", "Schedule"], defaultValue: hasSchedule ? "Schedule" : "Phases") ?? "Phases"
            let secs = try await number(ed, src == "Schedule" ? "Seconds per working day" : "Seconds per phase", src == "Schedule" ? 0.5 : 4)
            guard secs > 0, secs <= 120 else { throw CommandError.invalid("Use 0–120 s.") }
            let def = EngineView3DCommands.defaultPath(ed, "mp4", suffix: "-4D")
            guard let s = try await ed.getString("Video file <" + def + ">", defaultValue: def) else { return }
            var path = expand(s)
            if path.isEmpty { return }
            if !path.lowercased().hasSuffix(".mp4") { path += ".mp4" }
            if src == "Phases" && !hasPhases { throw CommandError.invalid("No phased elements.") }
            try host(ed, "output", [("op", .string("phaseVideo")), ("source", .string(src)), ("seconds", .number(secs)), ("fps", .int(30)),
                                    ("width", .int(1280)), ("height", .int(720)), ("path", .string(path))])
            ed.print("4D video (\(src.lowercased())) → \(path)")
        }
    }

    // MARK: Materials (AppCommandsRound10)

    static var matMaps: CommandDef {
        CommandDef("MATMAPS", aliases: ["PBRMAPS", "MATERIALMAPS"], category: "View", summary: "PBR texture maps of a material: Normal, Roughness, Metallic, AO and Displacement images, normal strength and displacement height; List/Clear.") { ed in
            let name = try await materialName(ed)
            var maps = EngineMaterialMaps.load(name, doc: ed.doc)
            let k = try await ed.getKeyword("Map [Normal/Roughness/Metallic/AO/Displacement/Strength/Height/List/Clear]", ["Normal", "Roughness", "Metallic", "AO", "Displacement", "Strength", "Height", "List", "Clear"], defaultValue: "List") ?? "List"
            switch k {
            case "List":
                ed.print("\(name): albedo \(ed.doc.material(name)?.texture ?? "—")")
                for s in EngineMaterialMaps.slots { ed.print("  \(s.title): \(maps[keyPath: s.key] ?? "—")") }
                ed.print("  Normal strength \(fmt(maps.normalStrength, 2)), displacement \(fmt(maps.displacementScale, 1)) mm")
                return
            case "Clear": maps = EngineMaterialMaps()
            case "Strength": maps.normalStrength = max(0, try await number(ed, "Normal strength", maps.normalStrength))
            case "Height": maps.displacementScale = max(0, try await number(ed, "Displacement height (mm)", maps.displacementScale))
            default:
                guard let slot = EngineMaterialMaps.slots.first(where: { $0.title == k }) else { return }
                let p = try await text(ed, "\(k) image path (. = none)", maps[keyPath: slot.key] ?? ".")
                if p == "." { maps[keyPath: slot.key] = nil } else {
                    let full = (p as NSString).expandingTildeInPath
                    var found = FileManager.default.fileExists(atPath: full)
                    if !found, let base = ed.fileURL?.deletingLastPathComponent() { found = FileManager.default.fileExists(atPath: base.appendingPathComponent(full).path) }
                    guard found else { throw CommandError.invalid("File not found: \(full)") }
                    maps[keyPath: slot.key] = full
                    if k == "Displacement" && maps.displacementScale == 0 { maps.displacementScale = 5 }
                }
            }
            EngineMaterialMaps.store(maps, material: name, in: &ed.doc)
            ed.print("\(name): PBR maps updated.")
        }
    }

    static var matAsset: CommandDef {
        CommandDef("MATASSET", aliases: ["MATERIALASSETS", "MATIDENTITY", "MATPHYSICAL"], category: "View", summary: "Material assets kept apart from the render appearance: Identity (description, manufacturer, mark, cost), Graphics (shading colour, surface pattern) and Physical/thermal (density, conductivity, specific heat); List.") { ed in
            let name = try await materialName(ed)
            var a = EngineMaterialAssets.load(name, doc: ed.doc)
            let k = try await ed.getKeyword("Asset [Identity/Graphics/Physical/List]", ["Identity", "Graphics", "Physical", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "Identity":
                a.description = try await text(ed, "Description", a.description.isEmpty ? name : a.description)
                a.manufacturer = try await text(ed, "Manufacturer (. = none)", a.manufacturer.isEmpty ? "." : a.manufacturer); if a.manufacturer == "." { a.manufacturer = "" }
                a.mark = try await text(ed, "Mark (. = none)", a.mark.isEmpty ? "." : a.mark); if a.mark == "." { a.mark = "" }
                let c = try await number(ed, "Cost per unit (0 = none)", a.cost ?? 0); a.cost = c > 0 ? c : nil
            case "Graphics":
                let own = try await ed.getKeyword("Shaded views use [Render/Own] colour", ["Render", "Own"], defaultValue: a.useRenderAppearance ? "Render" : "Own") ?? "Render"
                a.useRenderAppearance = own == "Render"
                if !a.useRenderAppearance {
                    let cur = a.shadingColor ?? (ed.doc.material(name).map { hexRGB($0.color) } ?? "#CCCCCC")
                    let h = try await text(ed, "Shading colour (#RRGGBB)", cur)
                    guard hexColor(h) != nil else { throw CommandError.invalid("Use a colour like #A0B0C0.") }
                    a.shadingColor = h.hasPrefix("#") ? h.uppercased() : "#" + h.uppercased()
                }
                let pat = try await text(ed, "Surface pattern (. = none)", a.surfacePattern ?? ".")
                a.surfacePattern = pat == "." ? nil : pat.uppercased()
            case "Physical":
                a.density = try await number(ed, "Density (kg/m³)", a.density ?? 1000)
                a.conductivity = try await number(ed, "Thermal conductivity (W/m·K)", a.conductivity ?? 1)
                a.specificHeat = try await number(ed, "Specific heat (J/kg·K)", a.specificHeat ?? 1000)
                guard (a.density ?? 0) > 0, (a.conductivity ?? 0) > 0, (a.specificHeat ?? 0) > 0 else { throw CommandError.invalid("Values must be positive.") }
            default:
                let desc = a.description.isEmpty ? "—" : a.description
                let manu = a.manufacturer.isEmpty ? "" : ", " + a.manufacturer
                let mark = a.mark.isEmpty ? "" : ", mark " + a.mark
                let cost = a.cost.map { ", cost " + fmt($0, 2) } ?? ""
                ed.print("\(name) — identity: " + desc + manu + mark + cost)
                let gr = a.useRenderAppearance ? "render appearance" : "shading " + (a.shadingColor ?? "?")
                let pat = a.surfacePattern.map { ", pattern " + $0 } ?? ""
                ed.print("  graphics: " + gr + pat)
                let rho = a.density.map { fmt($0, 0) } ?? "—"
                let lam = a.conductivity.map { fmt($0, 3) } ?? "—"
                let cap = a.specificHeat.map { fmt($0, 0) } ?? "—"
                let r100 = a.thermalResistance(thickness: 100).map { ", R(100 mm) " + fmt($0, 3) + " m²K/W" } ?? ""
                ed.print("  physical: ρ " + rho + " kg/m³, λ " + lam + " W/mK, c " + cap + " J/kgK" + r100)
                return
            }
            EngineMaterialAssets.store(a, material: name, in: &ed.doc)
            ed.print("\(name): \(k.lowercased()) asset saved.")
        }
    }

    static let procKinds = ["Wood", "Brick", "Tile", "Marble", "Stone", "Concrete", "Terrazzo"]
    /// ProceduralMaterial.Params(kind:) defaults: colours, tile size (mm), rows, columns, joint.
    static func procDefaults(_ k: String) -> (c1: RGBA, c2: RGBA, tile: Double, rows: Int, cols: Int, joint: Double) {
        switch k {
        case "Wood": return (RGBA(0.62, 0.43, 0.26), RGBA(0.45, 0.29, 0.16), 1000, 6, 1, 0.003)
        case "Tile": return (RGBA(0.90, 0.90, 0.88), RGBA(0.62, 0.62, 0.60), 1200, 4, 4, 0.008)
        case "Marble": return (RGBA(0.93, 0.92, 0.90), RGBA(0.45, 0.45, 0.48), 1000, 1, 1, 0)
        case "Stone": return (RGBA(0.62, 0.59, 0.53), RGBA(0.40, 0.38, 0.35), 1000, 5, 5, 0.015)
        case "Concrete": return (RGBA(0.70, 0.70, 0.68), RGBA(0.55, 0.55, 0.53), 1000, 1, 1, 0)
        case "Terrazzo": return (RGBA(0.88, 0.87, 0.84), RGBA(0.35, 0.33, 0.32), 1000, 1, 1, 0)
        default: return (RGBA(0.62, 0.30, 0.22), RGBA(0.80, 0.78, 0.74), 1000, 8, 4, 0.012)
        }
    }

    static var procMaterial: CommandDef {
        CommandDef("PROCMATERIAL", aliases: ["PROCEDURALMATERIAL", "PROCTEXTURE", "MATPROCEDURAL"], category: "View", summary: "Procedural seamless material (Wood, Brick, Tile, Marble, Stone, Concrete, Terrazzo) with albedo, normal and roughness maps from colours, courses, joint width and a seed.", modifies: false) { ed in
            let ks = try await ed.getKeyword("Pattern [\(procKinds.joined(separator: "/"))]", procKinds, defaultValue: "Brick") ?? "Brick"
            let d = procDefaults(ks)
            let name = try await text(ed, "Material name", "Procedural " + ks)
            let c1 = try await text(ed, "Main colour (#RRGGBB)", hexRGB(d.c1))
            let c2 = try await text(ed, "Second colour / joints (#RRGGBB)", hexRGB(d.c2))
            guard let a = hexColor(c1), let b = hexColor(c2) else { throw CommandError.invalid("Use colours like #A0522D.") }
            let tile = max(10, try await number(ed, "Tile size (mm)", d.tile))
            var rows = d.rows, cols = d.cols, joint = d.joint
            if ["Brick", "Tile", "Stone", "Wood"].contains(ks) {
                rows = max(1, min(64, Int(try await number(ed, "Rows / courses per tile", Double(rows)))))
                if ks != "Wood" { cols = max(1, min(64, Int(try await number(ed, "Columns per tile", Double(cols))))) }
                joint = max(0, min(0.2, try await number(ed, "Joint width (fraction of tile)", joint)))
            }
            let seed = max(0, try await number(ed, "Seed", 1))
            var p = EngineObject()
            p.set("kind", ks); p.set("color1", hexRGB(a)); p.set("color2", hexRGB(b)); p.set("tileSize", tile)
            p.set("rows", rows); p.set("columns", cols); p.set("joint", joint); p.set("seed", Int(seed))
            try host(ed, "materials", [("op", .string("procedural")), ("name", .string(name)), ("params", p.json)])
            ed.print("Material \(name): \(ks.lowercased()) \(rows)×\(cols), tile \(fmt(tile, 0)) mm, seed \(Int(seed)) (albedo, normal and roughness maps).")
        }
    }

    static var matFromImage: CommandDef {
        CommandDef("MATFROMIMAGE", aliases: ["MATPHOTO", "PHOTOMATERIAL", "IMAGETOMATERIAL"], category: "View", summary: "Creates a seamless PBR material from a photo: de-lit albedo, normal, roughness and AO maps derived from the image, at a real-world tile size.", modifies: false) { ed in
            let path = expand(try await text(ed, "Photo file", "~/Desktop/texture.jpg"))
            guard FileManager.default.fileExists(atPath: path) else { throw CommandError.invalid("File not found: \(path)") }
            let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.capitalized
            let name = try await text(ed, "Material name", base)
            let tile = max(10, try await number(ed, "Real-world size of the photo (mm)", 1000))
            try host(ed, "materials", [("op", .string("fromImage")), ("path", .string(path)), ("name", .string(name)), ("tileSize", .number(tile))])
        }
    }

    // MARK: Environment (AppCommandsRound10)

    static var water: CommandDef {
        CommandDef("WATER", aliases: ["WATERSURFACE", "POND", "POOLWATER"], category: "Architecture", summary: "Water surface with animated waves (viewport and renders) inside a closed polyline or picked points, at a surface elevation and depth.") { ed in
            let mm = ed.doc.units.mm
            let k = try await ed.getKeyword("Boundary [Select/Points]", ["Select", "Points"], defaultValue: "Select") ?? "Select"
            var pts: [Vec2] = []
            if k == "Select" {
                let ids = try await ed.getSelection("Select closed polylines or circles")
                pts = boundaries(ed, ids).first ?? []
            } else {
                let p0 = try await ed.requirePoint("First point")
                pts = [p0]
                while true {
                    let last = pts[pts.count - 1]
                    let cur = pts
                    guard let p = try await ed.getPoint("Next point (Enter to close)", base: last, preview: { q in [.polyline(PolylineGeom(points: cur + [q], closed: true))] }).point else { break }
                    pts.append(p)
                }
            }
            guard pts.count >= 3 else { throw CommandError.invalid("Needs a closed boundary with 3+ points.") }
            let lz = (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) / mm
            let z = try await number(ed, "Water surface elevation", lz - 100 / mm)
            let d = max(1, try await number(ed, "Depth", 1500 / mm))
            EngineWater.ensureMaterial(in: &ed.doc)
            ed.doc.ensureLayer(EngineWater.layer)
            guard let e = EngineWater.entity(boundary: pts, elevation: z, depth: d) else { throw CommandError.invalid("The boundary has no area.") }
            let id = ed.doc.add(e)
            let area = abs(GeometryOps.signedArea(pts)) * mm * mm / 1e6
            ed.print("Water #\(id): \(fmt(area, 2)) m² at elevation \(fmt(z, 0)).")
        }
    }

    static var scatter: CommandDef {
        CommandDef("SCATTER", aliases: ["SCATTERPLANTS", "VEGETATION", "GRASSSCATTER"], category: "Architecture", summary: "Scatters Grass, Flowers, Shrubs or Trees over closed boundaries with Poisson-disk spacing at a density per m² (reproducible seed); shown in the viewport and renders.") { ed in
            let mm = ed.doc.units.mm
            let kinds = EngineScatter.kinds
            let ks = try await ed.getKeyword("Scatter [\(kinds.joined(separator: "/"))]", kinds, defaultValue: "Grass") ?? "Grass"
            let ids = try await ed.getSelection("Select closed boundaries")
            let bs = boundaries(ed, ids).map { $0.map { $0 * mm } }
            guard !bs.isEmpty else { throw CommandError.invalid("Select closed polylines or circles.") }
            let dens = try await number(ed, "Density (plants per m²)", EngineScatter.density(ks))
            guard dens > 0, dens <= 2000 else { throw CommandError.invalid("Density 0–2000 per m².") }
            let h = try await number(ed, "Plant height", EngineScatter.height(ks) / mm) * mm
            let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            let z = try await number(ed, "Base elevation", lz / mm) * mm
            let seed = UInt64(max(0, try await number(ed, "Seed", 1)))
            let outers = bs.filter { b in !bs.contains { o in o != b && EngineScatter.inside(b[0], o) } }
            EngineScatter.ensureMaterials(ks, in: &ed.doc)
            ed.doc.ensureLayer(EngineScatter.layer)
            var total = 0
            for (i, o) in outers.enumerated() {
                let holes = bs.filter { b in b != o && EngineScatter.inside(b[0], o) }
                let r = EngineScatter.entities(ks, boundary: o, holes: holes, density: dens, z: z, height: h, seed: seed &+ UInt64(i))
                for var e in r.entities {
                    if mm != 1, case .solid(var s) = e.geometry { s.meshVertices = s.meshVertices.map { $0 / mm }; e.geometry = .solid(s) }
                    _ = ed.doc.add(e)
                }
                total += r.count
            }
            ed.print("Scattered \(total) \(ks.lowercased()) over \(outers.count) area(s).")
        }
    }

    // MARK: Mechanism playback (AppCommandsRound11) and the AO dialog (AppCommandsRound12)

    static let playbackModes = ["Once", "Loop", "Bounce"]

    static var mechanismPlay: CommandDef {
        CommandDef("MECHANISMPLAY", aliases: ["ANIMATEMECHANISM", "PLAYMECHANISM", "MECHANISMANIMATE"], category: "Parametric", summary: "Animates a mechanism on the plan: steps a named driving dimension through a range (re-solving the constraints) and plays the poses Once, in a Loop or Bounce; Stop ends it. The drawing is not changed.", modifies: false) { ed in
            let session = try EngineUICommands.session(ed)
            if session.mechanismPlaying {
                let k = try await ed.getKeyword("Mechanism is playing [Stop/Restart] <Stop>", ["Stop", "Restart"], defaultValue: "Stop") ?? "Stop"
                session.mechanismPlaying = false
                try host(ed, "canvas", [("op", .string("mechanismStop"))])
                if k == "Stop" { ed.print("Mechanism playback stopped."); return }
            }
            let set = ConstraintSet.load(ed.doc)
            let first = set.constraints.first { $0.name != nil && $0.kind.isDimensional }?.name
            guard let name = try await ed.getString("Driving dimension name", defaultValue: first)?.trimmingCharacters(in: .whitespaces),
                  let c = set.named(name), c.kind.isDimensional else { throw CommandError.invalid("No dimensional constraint with that name.") }
            let isAngle = c.kind == .angle
            let cur = Constraints.displayValue(c, set: set, doc: ed.doc) ?? c.value ?? 0
            let k = isAngle ? 180 / Double.pi : 1
            func real(_ msg: String, _ def: Double) async throws -> Double {
                let t = (try await ed.getString("\(msg) <\(fmt(def))>", defaultValue: fmt(def)) ?? "").trimmingCharacters(in: .whitespaces)
                if t.isEmpty { return def }
                guard let v = Double(t), v.isFinite else { throw CommandError.invalid("Enter a number.") }
                return v
            }
            let unit = isAngle ? " (degrees)" : ""
            let a = try await real("From value" + unit, cur * k)
            let b = try await real("To value" + unit, cur * k + (isAngle ? 360 : 100))
            let n = max(1, min(1440, try await ed.getInteger("Number of frames", defaultValue: 72) ?? 72))
            let fps = Double(max(1, min(120, try await ed.getInteger("Frames per second", defaultValue: 24) ?? 24)))
            let mode = try await ed.getKeyword("Playback [Once/Loop/Bounce]", playbackModes, defaultValue: "Loop") ?? "Loop"
            guard let r = Mechanisms.simulate(ed.doc, driver: name, from: a / k, to: b / k, steps: n, keepPoses: true), !r.poses.isEmpty else { throw CommandError.invalid("The mechanism cannot move from its current pose.") }
            let locked = r.frames.count > r.poses.count
            let accent = RGBA(0.961, 0.773, 0.094)
            var poses: [EngineJSON] = []
            for pose in r.poses {
                let items = DrawListBuilder.previewItems(pose.map(\.geometry), doc: ed.doc, color: accent)
                poses.append(EngineDrawJSON.items(items))
            }
            session.mechanismPlaying = true
            try host(ed, "canvas", [("op", .string("mechanismPlay")), ("poses", .array(poses)), ("fps", .number(fps)), ("mode", .string(mode)),
                                    ("maxLoops", .int(20))])
            let lockText = locked ? "; lock-up at \(fmt((r.frames.last?.value ?? 0) * k))." : "."
            ed.print("Playing \(r.poses.count) pose(s) at \(fmt(fps, 0)) fps (\(mode.lowercased()))" + lockText + " MECHANISMPLAY again stops.")
        }
    }

    static var aoDialog: CommandDef {
        CommandDef("AODIALOG", aliases: ["AMBIENTOCCLUSIONDIALOG", "AOPANEL"], category: "View", summary: "Ambient Occlusion dialog: intensity, radius and rays per point for the 3D viewport, renders and shaded views.", modifies: false) { ed in
            try EngineUICommands.dialog(ed, "ambientOcclusion", [("settings", EngineAOSettings.json(ed.doc))])
        }
    }
}

/// Whether MECHANISMPLAY is playing in the shell (per session; the shell stops it after its loops).
@MainActor
final class EngineMechanismState {
    final class Entry { weak var session: EngineSession?; var playing = false; init(_ s: EngineSession) { session = s } }
    static var bySession: [ObjectIdentifier: Entry] = [:]
}

extension EngineSession {
    var mechanismPlaying: Bool {
        get {
            let k = ObjectIdentifier(self)
            guard let e = EngineMechanismState.bySession[k], e.session === self else { return false }
            return e.playing
        }
        set {
            let k = ObjectIdentifier(self)
            EngineMechanismState.bySession = EngineMechanismState.bySession.filter { $0.value.session != nil }
            if let e = EngineMechanismState.bySession[k], e.session === self { e.playing = newValue; return }
            let e = EngineMechanismState.Entry(self)
            e.playing = newValue
            EngineMechanismState.bySession[k] = e
        }
    }
}
