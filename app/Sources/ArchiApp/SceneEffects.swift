// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

// MARK: - Weather and seasons (VIS-058)

/// Weather (clear, rain, snow, fog) with an intensity, snow cover and the season. Stored in the drawing as
/// WEATHER = "kind;intensity;season;snowCover". Rain and snow fall as particles in the viewport and renders,
/// wet surfaces get glossier and darker, snow covers up-facing faces, and the season tints vegetation materials.
struct WeatherSettings: Equatable, Hashable {
    enum Kind: String, CaseIterable { case clear = "Clear", rain = "Rain", snow = "Snow", fog = "Fog" }
    enum Season: String, CaseIterable { case spring = "Spring", summer = "Summer", autumn = "Autumn", winter = "Winter" }
    var kind: Kind = .clear
    var intensity = 0.5
    var season: Season = .summer
    /// Snow lying on up-facing faces (0…1); defaults to the intensity while snowing.
    var snowCover = 0.0

    static let variable = "WEATHER"
    var stored: String { "\(kind.rawValue);\(fmt(intensity, 3));\(season.rawValue);\(fmt(snowCover, 3))" }
    init() {}
    init(kind: Kind, intensity: Double = 0.5, season: Season = .summer, snowCover: Double = 0) {
        self.kind = kind; self.intensity = min(max(intensity, 0), 1); self.season = season; self.snowCover = min(max(snowCover, 0), 1)
    }
    init?(stored s: String) {
        let p = s.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        guard let k = Kind.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(p.first ?? "") == .orderedSame }) else { return nil }
        kind = k
        if p.count > 1, let v = Double(p[1]) { intensity = min(max(v, 0), 1) }
        if p.count > 2, let se = Season.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(p[2]) == .orderedSame }) { season = se }
        if p.count > 3, let v = Double(p[3]) { snowCover = min(max(v, 0), 1) }
    }
    static func load(_ doc: ArchiDocument) -> WeatherSettings { doc.variable(variable).flatMap(WeatherSettings.init(stored:)) ?? WeatherSettings() }
    func store(in doc: inout ArchiDocument) { if self == WeatherSettings() { doc.variables[WeatherSettings.variable] = nil } else { doc.setVariable(WeatherSettings.variable, stored) } }

    /// Surface wetness (rain) and snow cover used by materials.
    var wetness: Double { kind == .rain ? intensity : 0 }
    var snow: Double { snowCover > 0 ? snowCover : (kind == .snow ? intensity * 0.8 : 0) }

    static func isVegetation(_ material: String) -> Bool {
        let n = material.lowercased()
        return ["grass", "lawn", "leaf", "leaves", "foliage", "tree", "hedge", "shrub", "plant", "ivy", "moss"].contains { n.contains($0) }
    }

    /// Seasonal colour of vegetation: fresh light green in spring, unchanged in summer, orange-brown in autumn,
    /// dull brown-grey in winter.
    static func seasonTint(_ c: RGBA, _ s: Season) -> RGBA {
        func mix(_ t: RGBA, _ k: Double) -> RGBA { RGBA(c.r + (t.r - c.r) * k, c.g + (t.g - c.g) * k, c.b + (t.b - c.b) * k, c.a) }
        switch s {
        case .summer: return c
        case .spring: return mix(RGBA(0.55, 0.78, 0.30), 0.35)
        case .autumn: return mix(RGBA(0.78, 0.45, 0.14), 0.6)
        case .winter: return mix(RGBA(0.45, 0.40, 0.33), 0.7)
        }
    }

    /// Particle parameters: drops or flakes per second per square metre, fall speed (m/s), size (m), lifespan (s).
    struct Particles: Equatable { var birthRatePerM2: Double; var speed: Double; var size: Double; var life: Double; var stretch: Double }
    var particles: Particles? {
        switch kind {
        case .rain: return Particles(birthRatePerM2: 40 * intensity, speed: 6 + 3 * intensity, size: 0.006, life: 2.2, stretch: 12)
        case .snow: return Particles(birthRatePerM2: 12 * intensity, speed: 0.8 + 0.4 * intensity, size: 0.02 + 0.015 * intensity, life: 12, stretch: 0)
        default: return nil
        }
    }

    /// Visibility distance (m) for fog, rain and snow (feeds the scene fog).
    var fogDistance: Double? {
        switch kind {
        case .fog: return 30 + 400 * (1 - intensity)
        case .rain: return 300 + 1500 * (1 - intensity)
        case .snow: return 150 + 800 * (1 - intensity)
        case .clear: return nil
        }
    }

    /// Precipitation particles over the model (world metres; SceneKit Y up).
    @MainActor func node(center: SCNVector3, radius: CGFloat) -> SCNNode? {
        guard let p = particles, intensity > 0 else { return nil }
        let r = max(radius, 5)
        let ps = SCNParticleSystem()
        let area = Double(4 * r * r)
        ps.birthRate = CGFloat(min(p.birthRatePerM2 * area, 20000))
        ps.particleLifeSpan = CGFloat(p.life)
        ps.particleSize = CGFloat(p.size)
        ps.particleVelocity = CGFloat(p.speed)
        ps.particleVelocityVariation = CGFloat(p.speed * 0.15)
        ps.emittingDirection = SCNVector3(0, -1, 0)
        ps.spreadingAngle = kind == .snow ? 25 : 3
        ps.acceleration = SCNVector3(0, kind == .rain ? -9.8 : -0.3, 0)
        ps.particleColor = kind == .rain ? NSColor(white: 0.85, alpha: 0.55) : NSColor(white: 1, alpha: 0.95)
        ps.stretchFactor = CGFloat(p.stretch)
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        let box = SCNBox(width: r * 2, height: 0.1, length: r * 2, chamferRadius: 0)
        ps.emitterShape = box
        ps.birthLocation = .volume
        ps.warmupDuration = CGFloat(p.life)
        let n = SCNNode()
        n.name = "weather"
        n.position = SCNVector3(center.x, center.y + r * 1.2 + 10, center.z)
        n.addParticleSystem(ps)
        return n
    }

    /// Metal surface shader modifier: snow on faces whose world normal points up, rain darkening and gloss.
    var shaderModifier: String? {
        let s = snow, w = wetness
        guard s > 0 || w > 0 else { return nil }
        return """
        #pragma body
        float3 wn = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
        float cover = \(fmt(s, 3)) * smoothstep(0.45, 0.85, wn.y);
        _surface.diffuse.rgb = mix(_surface.diffuse.rgb * (1.0 - 0.3 * \(fmt(w, 3))), float3(0.93, 0.94, 0.96), cover);
        _surface.roughness = mix(_surface.roughness * (1.0 - 0.65 * \(fmt(w, 3))), 0.75, cover);
        """
    }

    /// Applies season tint, wetness and snow to a SceneKit material.
    @MainActor func apply(_ m: SCNMaterial, name: String, color: RGBA, style: String) {
        if WeatherSettings.isVegetation(name) && season != .summer, m.diffuse.contents is NSColor {
            let c = WeatherSettings.seasonTint(color, season)
            m.diffuse.contents = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        }
        guard style == "Realistic" || style == "Shaded" || style == "Shaded with Edges", let sm = shaderModifier else { return }
        var mods = m.shaderModifiers ?? [:]
        mods[.surface] = (mods[.surface].map { $0 + "\n" } ?? "") + sm
        m.shaderModifiers = mods
    }
}

// MARK: - Water surfaces (VIS-083)

/// Animated water: a thin solid with the Water material, whose normals move with travelling waves in the viewport
/// (surface shader) and in the path tracer (`PTShading.waterNormal`). Materials flagged MATWATER:<name> = 1
/// (and the material named "Water") are water.
enum WaterSurface {
    static let materialName = "Water"
    static let layer = "WATER"
    static func key(_ material: String) -> String { "MATWATER:" + material.uppercased() }
    static func isWater(_ material: String, doc: ArchiDocument) -> Bool {
        if let v = doc.variable(key(material)) { return v == "1" }
        return material.caseInsensitiveCompare(materialName) == .orderedSame
    }
    static func ensureMaterial(in doc: inout ArchiDocument) {
        if doc.material(materialName) == nil {
            doc.materials.append(ArchiCore.Material(name: materialName, color: RGBA(0.16, 0.38, 0.45), roughness: 0.03, metalness: 0, transparency: 0.6, cutPattern: "SOLID"))
        }
        doc.setVariable(key(materialName), "1")
    }
    /// Water body: a closed boundary at a surface elevation with a depth below it.
    static func entity(boundary: [Vec2], elevation: Double, depth: Double) -> Entity? {
        var pts = boundary
        if pts.count > 2, pts.first!.isClose(pts.last!, tol: 1e-9) { pts.removeLast() }
        guard pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-6 else { return nil }
        let d = max(depth, 1)
        let s = SolidGeom(kind: .extrusion, origin: Vec3(0, 0, elevation - d), profile: pts, height: d)
        return Entity(layer: layer, color: .aci(5), geometry: .solid(s), props: ["material": materialName, "water": "1"])
    }
    /// Wave amplitude of the viewport shader (slope scale).
    static let waveAmplitude = 0.12
    static let shaderModifier = """
    #pragma body
    float3 wn0 = normalize((scn_frame.inverseViewTransform * float4(_surface.normal, 0.0)).xyz);
    if (wn0.y > 0.5) {
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float t = scn_frame.time;
        float gx = cos(wp.x * 6.98 + wp.z * 2.09 + t * 1.1) * 0.5 + cos(wp.x * 7.2 - wp.z * 7.2 + t * 2.3) * 0.3 + cos(wp.x * 2.3 + wp.z * 10.3 + t * 3.1) * 0.2;
        float gz = cos(-wp.x * 4.1 + wp.z * 10.3 + t * 1.7) * 0.5 + cos(wp.x * 7.2 + wp.z * 7.2 + t * 2.3) * 0.3 + cos(wp.x * 9.9 - wp.z * 2.2 + t * 2.7) * 0.2;
        float3 wn = normalize(float3(-gx * 0.12, 1.0, -gz * 0.12));
        _surface.normal = normalize((scn_frame.viewTransform * float4(wn, 0.0)).xyz);
    }
    """
    @MainActor static func apply(_ m: SCNMaterial, style: String) {
        guard style == "Realistic" || style == "Shaded" || style == "Shaded with Edges" else { return }
        var mods = m.shaderModifiers ?? [:]
        mods[.surface] = WaterSurface.shaderModifier + (mods[.surface].map { "\n" + $0 } ?? "")
        m.shaderModifiers = mods
        m.isDoubleSided = true
    }
}

// MARK: - Scatter vegetation (VIS-082)

/// Scatters grass tufts, flowers, shrubs or trees over closed boundaries with Poisson-disk spacing (no clumps, no
/// gaps) at a density per square metre. Each scatter becomes one or two mesh solids (instanced low-poly plants) on
/// the PLANTING layer, so thousands of plants stay light in the viewport and in renders.
enum Scatter {
    enum Kind: String, CaseIterable { case grass = "Grass", flowers = "Flowers", shrubs = "Shrubs", trees = "Trees"
        /// Default density (plants per m²) and plant height (mm).
        var density: Double { switch self { case .grass: return 60; case .flowers: return 12; case .shrubs: return 1.2; case .trees: return 0.02 } }
        var height: Double { switch self { case .grass: return 120; case .flowers: return 350; case .shrubs: return 900; case .trees: return 7000 } }
        var materials: (String, String) { switch self { case .grass: return ("Grass", "Grass"); case .flowers: return ("Foliage", "Flowers"); case .shrubs: return ("Shrub Foliage", "Shrub Foliage"); case .trees: return ("Bark", "Tree Foliage") } }
    }
    static let layer = "PLANTING"

    static func inside(_ p: Vec2, _ poly: [Vec2]) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }

    /// Bridson Poisson-disk sampling inside a polygon (minus holes): no two points closer than `r`.
    static func poissonDisk(in poly: [Vec2], holes: [[Vec2]] = [], minDistance r: Double, maxCount: Int, seed: UInt64) -> [Vec2] {
        guard poly.count >= 3, r > 0, maxCount > 0 else { return [] }
        let b = BBox2(points: poly)
        let cell = r / 2.squareRoot()
        let gw = max(1, Int(ceil(b.width / cell))), gh = max(1, Int(ceil(b.height / cell)))
        guard gw * gh < 40_000_000 else { return [] }
        var grid = [Int32](repeating: -1, count: gw * gh)
        var pts: [Vec2] = [], active: [Int] = []
        var rng = PatternTextures.SplitMix(seed: seed)
        func ok(_ p: Vec2) -> Bool {
            guard p.x >= b.min.x, p.y >= b.min.y, p.x <= b.max.x, p.y <= b.max.y, inside(p, poly), !holes.contains(where: { $0.count >= 3 && inside(p, $0) }) else { return false }
            let gx = Int((p.x - b.min.x) / cell), gy = Int((p.y - b.min.y) / cell)
            for y in max(0, gy - 2)...min(gh - 1, gy + 2) { for x in max(0, gx - 2)...min(gw - 1, gx + 2) {
                let k = grid[y * gw + x]
                if k >= 0 && pts[Int(k)].distance(to: p) < r { return false }
            } }
            return true
        }
        func add(_ p: Vec2) {
            let gx = min(gw - 1, Int((p.x - b.min.x) / cell)), gy = min(gh - 1, Int((p.y - b.min.y) / cell))
            grid[gy * gw + gx] = Int32(pts.count); active.append(pts.count); pts.append(p)
        }
        // Seed points: first random points that fall inside.
        var tries = 0
        while pts.isEmpty && tries < 10_000 {
            let p = Vec2(b.min.x + rng.next() * b.width, b.min.y + rng.next() * b.height)
            if ok(p) { add(p) }
            tries += 1
        }
        while !active.isEmpty && pts.count < maxCount {
            let ai = Int(rng.next() * Double(active.count)) % active.count
            let c = pts[active[ai]]
            var found = false
            for _ in 0..<30 {
                let a = rng.next() * 2 * .pi, d = r * (1 + rng.next())
                let p = Vec2(c.x + cos(a) * d, c.y + sin(a) * d)
                if ok(p) { add(p); found = true; if pts.count >= maxCount { break } }
            }
            if !found { active.remove(at: ai) }
        }
        return pts
    }

    /// Minimum spacing (mm) for a density in plants per m² (Poisson-disk packing ≈ 0.7 / r²).
    static func spacing(density: Double) -> Double { (0.7 / max(density, 1e-6)).squareRoot() * 1000 }

    /// Low-poly plant meshes at the points: (stem/trunk mesh, foliage mesh) as vertex and triangle lists.
    static func meshes(_ kind: Kind, at points: [Vec2], z: Double, height h0: Double, seed: UInt64) -> (a: ([Vec3], [Int]), b: ([Vec3], [Int])) {
        var av: [Vec3] = [], at: [Int] = [], bv: [Vec3] = [], bt: [Int] = []
        var rng = PatternTextures.SplitMix(seed: seed &+ 77)
        func tri(_ v: inout [Vec3], _ t: inout [Int], _ p: Vec3, _ q: Vec3, _ r: Vec3) { let b = v.count; v += [p, q, r]; t += [b, b + 1, b + 2, b, b + 2, b + 1] }
        func blob(_ v: inout [Vec3], _ t: inout [Int], _ c: Vec3, _ rx: Double, _ rz: Double) {
            // Octahedron refined once (18 faces is enough for foliage).
            let rot = rng.next() * .pi
            let ring = (0..<6).map { i -> Vec3 in let a = rot + Double(i) * .pi / 3; return Vec3(c.x + cos(a) * rx, c.y + sin(a) * rx, c.z) }
            let top = Vec3(c.x, c.y, c.z + rz), bot = Vec3(c.x, c.y, c.z - rz * 0.6)
            let upper = (0..<6).map { i -> Vec3 in let a = rot + (Double(i) + 0.5) * .pi / 3; return Vec3(c.x + cos(a) * rx * 0.6, c.y + sin(a) * rx * 0.6, c.z + rz * 0.6) }
            for i in 0..<6 {
                let j = (i + 1) % 6
                tri(&v, &t, ring[i], ring[j], upper[i]); tri(&v, &t, upper[i], ring[j], upper[j]); tri(&v, &t, upper[i], upper[j], top)
                tri(&v, &t, ring[j], ring[i], bot)
            }
        }
        for p in points {
            let h = h0 * (0.75 + 0.5 * rng.next())
            switch kind {
            case .grass:
                for k in 0..<3 {
                    let a = rng.next() * 2 * .pi + Double(k) * 2.1, w = h * 0.12
                    let dx = cos(a) * w, dy = sin(a) * w, lean = Vec3(cos(a + 1.3) * h * 0.2, sin(a + 1.3) * h * 0.2, 0)
                    tri(&bv, &bt, Vec3(p.x - dx, p.y - dy, z), Vec3(p.x + dx, p.y + dy, z), Vec3(p.x, p.y, z + h) + lean)
                }
            case .flowers:
                tri(&av, &at, Vec3(p.x - 4, p.y, z), Vec3(p.x + 4, p.y, z), Vec3(p.x, p.y, z + h))
                blob(&bv, &bt, Vec3(p.x, p.y, z + h), h * 0.12, h * 0.08)
            case .shrubs:
                blob(&bv, &bt, Vec3(p.x, p.y, z + h * 0.5), h * 0.6, h * 0.5)
            case .trees:
                let r = h * 0.025, ring = (0..<6).map { i -> Vec2 in let a = Double(i) * .pi / 3; return Vec2(cos(a) * r, sin(a) * r) }
                let th = h * 0.45
                for i in 0..<6 {
                    let j = (i + 1) % 6
                    let a0 = Vec3(p.x + ring[i].x, p.y + ring[i].y, z), a1 = Vec3(p.x + ring[j].x, p.y + ring[j].y, z)
                    let b0 = Vec3(p.x + ring[i].x * 0.6, p.y + ring[i].y * 0.6, z + th), b1 = Vec3(p.x + ring[j].x * 0.6, p.y + ring[j].y * 0.6, z + th)
                    tri(&av, &at, a0, a1, b1); tri(&av, &at, a0, b1, b0)
                }
                blob(&bv, &bt, Vec3(p.x, p.y, z + h * 0.62), h * 0.3, h * 0.38)
            }
        }
        return ((av, at), (bv, bt))
    }

    /// Scatter entities (mesh solids) for a boundary; `seed` makes the result reproducible.
    static func entities(_ kind: Kind, boundary: [Vec2], holes: [[Vec2]] = [], density: Double, z: Double, height: Double? = nil, seed: UInt64, maxCount: Int = 200_000) -> (entities: [Entity], count: Int) {
        let area = abs(GeometryOps.signedArea(boundary)) / 1e6
        let target = min(maxCount, Int((area * density).rounded(.up)))
        let pts = poissonDisk(in: boundary, holes: holes, minDistance: spacing(density: density), maxCount: max(target, 1), seed: seed)
        guard !pts.isEmpty else { return ([], 0) }
        let (a, b) = meshes(kind, at: pts, z: z, height: height ?? kind.height, seed: seed)
        var out: [Entity] = []
        let props = ["scatter": kind.rawValue, "scatterCount": "\(pts.count)", "scatterSeed": "\(seed)"]
        if !a.1.isEmpty { var p = props; p["material"] = kind.materials.0; out.append(Entity(layer: layer, color: .aci(3), geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: a.0, meshTriangles: a.1)), props: p)) }
        if !b.1.isEmpty { var p = props; p["material"] = kind.materials.1; out.append(Entity(layer: layer, color: .aci(3), geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: b.0, meshTriangles: b.1)), props: p)) }
        return (out, pts.count)
    }

    static func ensureMaterials(_ kind: Kind, in doc: inout ArchiDocument) {
        let defs: [String: ArchiCore.Material] = [
            "Grass": ArchiCore.Material(name: "Grass", color: RGBA(0.35, 0.55, 0.25), roughness: 1),
            "Foliage": ArchiCore.Material(name: "Foliage", color: RGBA(0.25, 0.48, 0.2), roughness: 0.9),
            "Flowers": ArchiCore.Material(name: "Flowers", color: RGBA(0.86, 0.35, 0.45), roughness: 0.8),
            "Shrub Foliage": ArchiCore.Material(name: "Shrub Foliage", color: RGBA(0.22, 0.42, 0.2), roughness: 0.95),
            "Tree Foliage": ArchiCore.Material(name: "Tree Foliage", color: RGBA(0.26, 0.47, 0.22), roughness: 0.95),
            "Bark": ArchiCore.Material(name: "Bark", color: RGBA(0.36, 0.27, 0.2), roughness: 0.95),
        ]
        for n in [kind.materials.0, kind.materials.1] where doc.material(n) == nil { if let m = defs[n] { doc.materials.append(m) } }
    }
}

// MARK: - Object animation (VIS-045)

/// Keyframe-free object animation: a rotation about a vertical axis through a pivot and/or a movement, over a time
/// window with easing, optionally there-and-back and looping. Door presets swing the leaf about its hinge (the
/// leaf is split from the frame in the viewport). Stored in the drawing (OBJANIM, JSON), so it plays the same way
/// every time and on every machine.
struct ObjectAnimation: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case rotate = "Rotate", move = "Move", door = "Door" }
    var id: Int
    var target: Int
    var kind: Kind
    var pivot: Vec3 = .zero
    /// Rotation angle (degrees) at the end of the motion.
    var angle = 90.0
    var offset: Vec3 = .zero
    var start = 0.0
    var duration = 2.0
    var pingPong = true
    var name = ""

    init(id: Int, target: Int, kind: Kind, pivot: Vec3 = .zero, angle: Double = 90, offset: Vec3 = .zero, start: Double = 0, duration: Double = 2, pingPong: Bool = true, name: String = "") {
        self.id = id; self.target = target; self.kind = kind; self.pivot = pivot; self.angle = angle; self.offset = offset
        self.start = start; self.duration = duration; self.pingPong = pingPong; self.name = name
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); target = try c.decode(Int.self, forKey: .target)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .rotate
        pivot = try c.decodeIfPresent(Vec3.self, forKey: .pivot) ?? .zero
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90
        offset = try c.decodeIfPresent(Vec3.self, forKey: .offset) ?? .zero
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 2
        pingPong = try c.decodeIfPresent(Bool.self, forKey: .pingPong) ?? true
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    /// End time of the motion (there and back when ping-pong).
    var end: Double { start + max(duration, 1e-6) * (pingPong ? 2 : 1) }

    /// Eased progress 0…1 at time t (smoothstep; back to 0 in the second half of a ping-pong).
    func progress(at t: Double) -> Double {
        let d = max(duration, 1e-6)
        var x = (t - start) / d
        if x <= 0 { return 0 }
        if pingPong { x = x >= 2 ? 0 : (x > 1 ? 2 - x : x) } else { x = min(x, 1) }
        return x * x * (3 - 2 * x)
    }

    /// Rotation (radians about +Z through the pivot) and translation at time t.
    func state(at t: Double) -> (angle: Double, offset: Vec3) {
        let f = progress(at: t)
        return (angle * .pi / 180 * f, offset * f)
    }

    /// Moves a model point to where it is at time t.
    func apply(_ p: Vec3, at t: Double) -> Vec3 {
        let s = state(at: t)
        let d = p - pivot, c = cos(s.angle), sn = sin(s.angle)
        return Vec3(pivot.x + d.x * c - d.y * sn, pivot.y + d.x * sn + d.y * c, p.z) + s.offset
    }

    /// SceneKit transform (model millimetres, Z up; the space of the model root's children).
    func matrix(at t: Double) -> SCNMatrix4 {
        let s = state(at: t)
        var m = SCNMatrix4MakeTranslation(CGFloat(-pivot.x), CGFloat(-pivot.y), CGFloat(-pivot.z))
        m = SCNMatrix4Mult(m, SCNMatrix4MakeRotation(CGFloat(s.angle), 0, 0, 1))
        m = SCNMatrix4Mult(m, SCNMatrix4MakeTranslation(CGFloat(pivot.x + s.offset.x), CGFloat(pivot.y + s.offset.y), CGFloat(pivot.z + s.offset.z)))
        return m
    }
}

enum ObjectAnimations {
    static let variable = "OBJANIM"
    static func load(_ doc: ArchiDocument) -> [ObjectAnimation] {
        guard let s = doc.variable(variable), let a = try? JSONDecoder().decode([ObjectAnimation].self, from: Data(s.utf8)) else { return [] }
        return a
    }
    static func store(_ a: [ObjectAnimation], in doc: inout ArchiDocument) {
        if a.isEmpty { doc.variables[variable] = nil; return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(a) { doc.setVariable(variable, String(decoding: d, as: UTF8.self)) }
    }
    static func duration(_ a: [ObjectAnimation]) -> Double { a.map(\.end).max() ?? 0 }
    static func nextID(_ a: [ObjectAnimation]) -> Int { (a.map(\.id).max() ?? 0) + 1 }

    /// Door hinge geometry: hinge point (model mm, at the leaf's mid thickness), swing sign and leaf span along the
    /// wall. Only straight walls and single/double swing doors.
    struct DoorLeaf { var hinge: Vec2; var sign: Double; var s0: Double; var s1: Double; var cs: Vec2; var dir: Vec2; var normal: Vec2; var wallHalf: Double }
    static func doorLeaves(_ el: BIMElement, doc: ArchiDocument) -> [DoorLeaf] {
        guard case .opening(let o) = el.geometry, o.kind == .door, o.doorStyle == .single || o.doorStyle == .double,
              let host = doc.element(o.hostWall), case .wall(let w) = host.geometry, abs(w.bulge) < 1e-9 else { return [] }
        let cs = w.centerStart, ce = w.centerEnd
        let len = cs.distance(to: ce)
        guard len > 1e-6 else { return [] }
        let dir = (ce - cs) / len, nrm = Vec2(-dir.y, dir.x)
        let fw = min(max(o.frameWidth, 0), o.width / 4, o.height / 4)
        let a = o.offset - o.width / 2 + fw, b = o.offset + o.width / 2 - fw
        let side: Double = o.flipFacing ? -1 : 1
        let h = max(w.thickness, 0) / 2
        let tmid = side * (h - 25 * (doc.units.mm > 0 ? 1 / doc.units.mm : 1))
        func leaf(_ s0: Double, _ s1: Double, hingeAtStart: Bool) -> DoorLeaf {
            let hs = hingeAtStart ? s0 : s1
            let hinge = cs + dir * hs + nrm * tmid
            return DoorLeaf(hinge: hinge, sign: (hingeAtStart ? 1 : -1) * side, s0: s0, s1: s1, cs: cs, dir: dir, normal: nrm, wallHalf: h)
        }
        if o.doorStyle == .double { let mid = (a + b) / 2; return [leaf(a, mid, hingeAtStart: true), leaf(mid, b, hingeAtStart: false)] }
        return [leaf(a, b, hingeAtStart: !o.flipHand)]
    }

    /// Splits a door's mesh into the frame (static) and one mesh per leaf: triangles inside the leaf span whose
    /// vertices stay clear of the wall faces.
    static func splitDoor(_ mesh: Mesh, leaves: [DoorLeaf], tolerance e: Double = 0.5) -> (rest: Mesh, leaves: [Mesh]) {
        var rest = Mesh(), out = [Mesh](repeating: Mesh(), count: leaves.count)
        func append(_ m: inout Mesh, _ ids: [Int]) {
            let base = UInt32(m.positions.count)
            for i in ids {
                m.positions.append(mesh.positions[i])
                if mesh.normals.count == mesh.positions.count { m.normals.append(mesh.normals[i]) }
                if mesh.uvs.count == mesh.positions.count { m.uvs.append(mesh.uvs[i]) }
            }
            m.indices += [base, base + 1, base + 2]
        }
        var i = 0
        while i + 2 < mesh.indices.count {
            let ids = [Int(mesh.indices[i]), Int(mesh.indices[i + 1]), Int(mesh.indices[i + 2])]
            i += 3
            guard ids.allSatisfy({ $0 < mesh.positions.count }) else { continue }
            var placed = false
            for (k, l) in leaves.enumerated() {
                let inLeaf = ids.allSatisfy { j in
                    let p = mesh.positions[j].xy - l.cs
                    let s = p.dot(l.dir), t = p.dot(l.normal)
                    return s >= l.s0 - e && s <= l.s1 + e && abs(t) < l.wallHalf - e
                }
                if inLeaf { append(&out[k], ids); placed = true; break }
            }
            if !placed { append(&rest, ids) }
        }
        return (rest, out)
    }

    /// Door swing animation for an element (hinge at the leaf edge; angle signed towards the swing side).
    static func door(_ el: BIMElement, doc: ArchiDocument, id: Int, angle: Double, start: Double, duration: Double) -> [ObjectAnimation] {
        doorLeaves(el, doc: doc).enumerated().map { k, l in
            ObjectAnimation(id: id + k, target: el.id, kind: .door, pivot: Vec3(l.hinge.x, l.hinge.y, 0), angle: angle * l.sign, start: start, duration: duration, pingPong: true, name: "Door \(el.id)" + (k > 0 ? " leaf 2" : ""))
        }
    }

    /// Applies the animations at time t to the viewport nodes ("el:<id>" objects, "leaf:<id>:<k>" door leaves).
    @MainActor static func apply(_ anims: [ObjectAnimation], to root: SCNNode, at t: Double) {
        var leafIndex: [Int: Int] = [:]
        for a in anims {
            if a.kind == .door {
                let k = leafIndex[a.target, default: 0]; leafIndex[a.target] = k + 1
                root.childNode(withName: "leaf:\(a.target):\(k)", recursively: true)?.transform = a.matrix(at: t)
            } else {
                root.childNode(withName: "el:\(a.target)", recursively: false)?.transform = a.matrix(at: t)
            }
        }
    }
    @MainActor static func reset(_ anims: [ObjectAnimation], root: SCNNode) { apply(anims, to: root, at: -1) }
}

/// Plays the drawing's object animations in the active 3D viewport (loops until stopped).
@MainActor
enum AnimationPlayer {
    private static var timer: Timer?
    private static var started = Date()
    static var isPlaying: Bool { timer != nil }
    static func play(model: AppModel, loop: Bool = true) {
        stop()
        started = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let c = Viewport3DController.active else { return }
                let anims = ObjectAnimations.load(model.doc)
                let total = ObjectAnimations.duration(anims)
                var t = Date().timeIntervalSince(started)
                if total > 0 && t > total + 0.5 { if loop { started = Date(); t = 0 } else { stop(); return } }
                ObjectAnimations.apply(anims, to: c.builder.modelRoot, at: t)
            }
        }
    }
    static func stop() {
        timer?.invalidate(); timer = nil
        if let c = Viewport3DController.active, let m = c.model { ObjectAnimations.reset(ObjectAnimations.load(m.doc), root: c.builder.modelRoot) }
    }
}
