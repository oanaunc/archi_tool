// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

// MARK: - Artificial lights (VIS-053) and IES profiles (VIS-054)

/// Placed lights: point entities on the LIGHTS layer whose props describe the light, plus BIM light fixtures
/// (`LightingFixtures.renderLights`). They light the 3D viewport and the renders (both use `Scene3DBuilder`).
@MainActor
enum SceneLights {
    static let layer = "LIGHTS"
    /// Document variable turning the artificial lights off in the viewport and renders ("0").
    static let variable = "ARTIFICIALLIGHTS"
    enum Kind: String, CaseIterable { case point = "Point", spot = "Spot", area = "Area", line = "Line", ies = "IES" }

    struct Light: Hashable {
        var id: EntityID
        var kind: Kind
        var position: Vec3
        var target: Vec3?
        var lumens: Double
        var cct: Double
        /// Full cone angle of spots (degrees).
        var beam: Double
        /// Area/line light size (mm).
        var size: Vec2
        var ies: String?
        var on: Bool
    }

    static func isLight(_ e: Entity) -> Bool { e.props["light"] != nil }

    static func light(_ e: Entity) -> Light? {
        guard let t = e.props["light"], let kind = Kind(rawValue: t.capitalized == "Ies" ? "IES" : t.capitalized), case .point(let p) = e.geometry else { return nil }
        func d(_ k: String, _ def: Double) -> Double { e.props[k].flatMap { Double($0) } ?? def }
        let z = d("z", 2400)
        var target: Vec3?
        if let tx = e.props["targetX"].flatMap(Double.init), let ty = e.props["targetY"].flatMap(Double.init) { target = Vec3(tx, ty, d("targetZ", 0)) }
        return Light(id: e.id, kind: kind, position: Vec3(p.x, p.y, z), target: target, lumens: max(0, d("lumens", 800)), cct: min(max(d("cct", 3000), 1000), 20000),
                     beam: min(max(d("beam", 60), 1), 170), size: Vec2(max(d("width", 600), 1), max(d("length", 600), 1)), ies: e.props["ies"], on: e.props["lightOn"] != "0")
    }

    /// A light entity (undoable through the command that adds it).
    static func entity(_ l: Light) -> Entity {
        var props: [String: String] = ["light": l.kind.rawValue.lowercased(), "z": fmt(l.position.z), "lumens": fmt(l.lumens), "cct": fmt(l.cct)]
        if l.kind == .spot || l.kind == .ies { props["beam"] = fmt(l.beam) }
        if let t = l.target { props["targetX"] = fmt(t.x); props["targetY"] = fmt(t.y); props["targetZ"] = fmt(t.z) }
        if l.kind == .area || l.kind == .line { props["width"] = fmt(l.size.x); props["length"] = fmt(l.size.y) }
        if let i = l.ies { props["ies"] = i }
        if !l.on { props["lightOn"] = "0" }
        return Entity(layer: layer, color: .aci(2), geometry: .point(Vec2(l.position.x, l.position.y)), props: props)
    }

    /// All lights of the model: placed lights and light fixtures (converted to spots or points).
    static func all(_ doc: ArchiDocument) -> [Light] {
        guard doc.variable(variable) != "0" else { return [] }
        var out = doc.entities.filter { isLight($0) && doc.isVisible(layer: $0.layer) }.compactMap(light).filter(\.on)
        for f in LightingFixtures.renderLights(doc: doc) {
            let spot = f.spotAngle < 170
            out.append(Light(id: f.id, kind: spot ? .spot : .point, position: f.position, target: spot ? f.position + f.direction * 1000 : nil,
                             lumens: f.lumens, cct: kelvin(f.color), beam: min(f.spotAngle, 170), size: Vec2(1, 1), ies: nil, on: true))
        }
        return out
    }

    /// Correlated colour temperature estimate of a light colour (warm ↔ cool), used for fixtures that carry a colour.
    static func kelvin(_ c: RGBA) -> Double {
        let ratio = c.b / max(c.r, 1e-6)
        return min(max(1800 + ratio * 4700, 1800), 12000)
    }

    /// SceneKit node of a light (world metres). Intensity is in lumens (SceneKit's photometric unit).
    static func node(_ l: Light) -> SCNNode {
        let n = SCNNode()
        n.name = "light:\(l.id)"
        let s = SCNLight()
        s.intensity = CGFloat(l.lumens)
        s.temperature = CGFloat(l.cct)
        s.attenuationStartDistance = 0
        s.attenuationEndDistance = CGFloat(max(3, sqrt(max(l.lumens, 1)) / 4))
        s.attenuationFalloffExponent = 2
        n.position = Scene3DBuilder.world(l.position)
        switch l.kind {
        case .point: s.type = .omni
        case .spot, .ies:
            if l.kind == .ies, let p = l.ies, FileManager.default.fileExists(atPath: (p as NSString).expandingTildeInPath) {
                s.type = .IES
                s.iesProfileURL = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            } else {
                s.type = .spot
            }
            s.spotOuterAngle = CGFloat(l.beam)
            s.spotInnerAngle = CGFloat(l.beam * 0.7)
            s.castsShadow = true
            s.shadowMode = .deferred
            s.shadowSampleCount = 8
            s.shadowRadius = 3
            s.shadowColor = NSColor(white: 0, alpha: 0.5)
        case .area, .line:
            s.type = .area
            s.areaType = .rectangle
            let w = l.kind == .line ? 0.02 : l.size.x * 0.001
            s.areaExtents = simd_float3(Float(w), Float(l.size.y * 0.001), 1)
            s.intensity = CGFloat(l.lumens)
        }
        n.light = s
        let t = l.target ?? (l.kind == .point ? nil : l.position - Vec3(0, 0, 1000))
        if let t, t.distance(to: l.position) > 1e-6 {
            n.look(at: Scene3DBuilder.world(t), up: abs((t - l.position).normalized.z) > 0.99 ? SCNVector3(0, 0, -1) : SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }
        return n
    }
}

/// IESNA LM-63 photometric files: angles, candela grid, declared and integrated flux, beam angle.
struct IESProfile: Equatable {
    var lumensPerLamp: Double
    var lamps: Int
    var multiplier: Double
    var vertical: [Double]
    var horizontal: [Double]
    /// candela[h][v]
    var candela: [[Double]]

    var maxCandela: Double { candela.flatMap { $0 }.max() ?? 0 }
    /// Declared lamp flux (nil for absolute photometry, lumens = -1).
    var declaredLumens: Double? { lumensPerLamp > 0 ? lumensPerLamp * Double(lamps) : nil }

    static func parse(_ text: String) -> IESProfile? {
        let lines = text.components(separatedBy: .newlines)
        guard let ti = lines.firstIndex(where: { $0.uppercased().hasPrefix("TILT=") }) else { return nil }
        var nums: [Double] = []
        for l in lines[(ti + 1)...] { nums += l.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" }).compactMap { Double($0) } }
        guard nums.count >= 13 else { return nil }
        let lamps = Int(nums[0]), lm = nums[1], mult = nums[2], nv = Int(nums[3]), nh = Int(nums[4])
        guard nv > 0, nh > 0, lamps > 0 else { return nil }
        var i = 13
        guard nums.count >= i + nv + nh + nv * nh else { return nil }
        let v = Array(nums[i..<(i + nv)]); i += nv
        let h = Array(nums[i..<(i + nh)]); i += nh
        var grid: [[Double]] = []
        for _ in 0..<nh { grid.append(nums[i..<(i + nv)].map { $0 * mult }); i += nv }
        return IESProfile(lumensPerLamp: lm, lamps: lamps, multiplier: mult, vertical: v, horizontal: h, candela: grid)
    }

    /// Candela at a vertical angle, averaged over the horizontal planes (linear interpolation).
    func intensity(vertical a: Double) -> Double {
        guard !candela.isEmpty else { return 0 }
        let avg = (0..<vertical.count).map { k in candela.map { $0[k] }.reduce(0, +) / Double(candela.count) }
        if a <= vertical.first! { return avg.first! }
        if a >= vertical.last! { return avg.last! }
        for k in 1..<vertical.count where a <= vertical[k] {
            let t = (a - vertical[k - 1]) / max(vertical[k] - vertical[k - 1], 1e-9)
            return avg[k - 1] + (avg[k] - avg[k - 1]) * t
        }
        return avg.last!
    }

    /// Luminous flux by integrating the (horizontally averaged) distribution over the sphere: Σ I · 2π (cos θ₁ − cos θ₂).
    var integratedLumens: Double {
        guard vertical.count >= 2 else { return 0 }
        var f = 0.0
        let steps = 720
        let lo = vertical.first!, hi = vertical.last!
        for k in 0..<steps {
            let a0 = lo + (hi - lo) * Double(k) / Double(steps), a1 = lo + (hi - lo) * Double(k + 1) / Double(steps)
            f += intensity(vertical: (a0 + a1) / 2) * 2 * .pi * (cos(a0 * .pi / 180) - cos(a1 * .pi / 180))
        }
        return f
    }

    /// Full beam angle: twice the vertical angle where intensity falls to half the peak (0° = straight down).
    var beamAngle: Double {
        let peak = maxCandela
        guard peak > 0 else { return 0 }
        var a = 0.0
        while a <= 180 { if intensity(vertical: a) < peak / 2 { return min(2 * a, 360) }; a += 0.25 }
        return 360
    }
}

// MARK: - Fog (VIS-056), emissive materials (VIS-055), billboards (VIS-084)

struct FogSettings: Equatable {
    var on = false
    /// Distances from the camera in model millimetres.
    var start = 5000.0
    var end = 60000.0
    var color = RGBA(0.78, 0.8, 0.84)
    /// 1 = linear, 2 = quadratic falloff (SceneKit fogDensityExponent).
    var density = 1.0

    static func load(_ doc: ArchiDocument) -> FogSettings {
        var f = FogSettings()
        f.on = doc.variable("FOG") == "1"
        if let v = doc.variable("FOGSTART").flatMap(Double.init) { f.start = max(0, v) }
        if let v = doc.variable("FOGEND").flatMap(Double.init) { f.end = max(f.start + 1, v) }
        if let v = doc.variable("FOGCOLOR"), v.hasPrefix("#") { f.color = RGBA(hex: v) }
        if let v = doc.variable("FOGDENSITY").flatMap(Double.init) { f.density = min(max(v, 0.1), 4) }
        return f
    }
    func store(_ doc: inout ArchiDocument) {
        doc.setVariable("FOG", on ? "1" : "0"); doc.setVariable("FOGSTART", fmt(start)); doc.setVariable("FOGEND", fmt(end))
        doc.setVariable("FOGCOLOR", color.hex); doc.setVariable("FOGDENSITY", fmt(density))
    }
    func apply(to scene: SCNScene) {
        scene.fogStartDistance = on ? CGFloat(start * 0.001) : 0
        scene.fogEndDistance = on ? CGFloat(end * 0.001) : 0
        scene.fogDensityExponent = CGFloat(density)
        scene.fogColor = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
    }
}

/// Self-illuminated materials: luminance factor per material in MATEMIT:<name> (0 = off).
enum Emissive {
    static func key(_ material: String) -> String { "MATEMIT:" + material.uppercased() }
    static func strength(_ material: String, doc: ArchiDocument) -> Double { doc.variable(key(material)).flatMap(Double.init).map { min(max($0, 0), 20) } ?? 0 }
    static func apply(_ m: SCNMaterial, name: String, color: RGBA, doc: ArchiDocument) {
        let k = strength(name, doc: doc)
        guard k > 0 else { return }
        m.emission.contents = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
        m.emission.intensity = CGFloat(k)
    }
}

/// 2D cutouts that always face the camera (people, trees, image files).
@MainActor
enum Billboards {
    static let layer = "BILLBOARDS"
    static let builtins = ["person", "tree", "shrub"]

    struct Item: Hashable { var id: EntityID; var position: Vec3; var height: Double; var source: String }

    static func items(_ doc: ArchiDocument) -> [Item] {
        doc.entities.compactMap { e in
            guard let src = e.props["billboard"], case .point(let p) = e.geometry, doc.isVisible(layer: e.layer) else { return nil }
            return Item(id: e.id, position: Vec3(p.x, p.y, e.props["z"].flatMap(Double.init) ?? 0), height: max(e.props["height"].flatMap(Double.init) ?? 1750, 10), source: src)
        }
    }

    static func entity(source: String, at p: Vec3, height: Double) -> Entity {
        Entity(layer: layer, color: .aci(3), geometry: .point(p.xy), props: ["billboard": source, "z": fmt(p.z), "height": fmt(height)])
    }

    private static var cache: [String: NSImage] = [:]
    static func image(_ source: String) -> NSImage? {
        if let i = cache[source] { return i }
        let img: NSImage?
        switch source.lowercased() {
        case "person": img = drawn(CGSize(width: 120, height: 400)) { r in
            NSColor(white: 0.25, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: 42, y: 330, width: 36, height: 44)).fill()
            NSBezierPath(roundedRect: CGRect(x: 26, y: 190, width: 68, height: 140), xRadius: 22, yRadius: 22).fill()
            NSBezierPath(roundedRect: CGRect(x: 32, y: 0, width: 24, height: 200), xRadius: 10, yRadius: 10).fill()
            NSBezierPath(roundedRect: CGRect(x: 64, y: 0, width: 24, height: 200), xRadius: 10, yRadius: 10).fill()
            _ = r }
        case "tree": img = drawn(CGSize(width: 300, height: 400)) { _ in
            NSColor(srgbRed: 0.4, green: 0.28, blue: 0.18, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(x: 138, y: 0, width: 24, height: 190)).fill()
            NSColor(srgbRed: 0.26, green: 0.48, blue: 0.22, alpha: 0.95).setFill()
            for (x, y, s) in [(150.0, 270.0, 170.0), (95.0, 230.0, 120.0), (205.0, 235.0, 120.0), (150.0, 330.0, 120.0)] {
                NSBezierPath(ovalIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)).fill()
            } }
        case "shrub": img = drawn(CGSize(width: 300, height: 180)) { _ in
            NSColor(srgbRed: 0.3, green: 0.52, blue: 0.25, alpha: 0.95).setFill()
            for (x, y, s) in [(80.0, 70.0, 130.0), (150.0, 95.0, 160.0), (220.0, 70.0, 130.0)] {
                NSBezierPath(ovalIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)).fill()
            } }
        default: img = NSImage(contentsOfFile: (source as NSString).expandingTildeInPath)
        }
        if let img { cache[source] = img }
        return img
    }
    private static func drawn(_ size: CGSize, _ body: @escaping (CGRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: false) { r in body(r); return true }
    }

    static func node(_ it: Item) -> SCNNode {
        let img = image(it.source)
        let aspect = img.map { $0.size.width / max($0.size.height, 1) } ?? 0.5
        let h = CGFloat(it.height * 0.001), w = h * aspect
        let plane = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.diffuse.contents = img ?? NSColor(white: 0.5, alpha: 1)
        m.lightingModel = .lambert
        m.isDoubleSided = true
        m.transparencyMode = .aOne
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.name = "billboard:\(it.id)"
        let base = Scene3DBuilder.world(it.position)
        n.position = SCNVector3(base.x, base.y + h / 2, base.z)
        let c = SCNBillboardConstraint(); c.freeAxes = .Y
        n.constraints = [c]
        n.castsShadow = true
        return n
    }
}

extension Scene3DBuilder {
    /// Rebuilds lights, billboards and fog when their inputs change (called at the end of `update`).
    func syncExtras(doc: ArchiDocument) {
        let lights = style == "Hidden Line" || style == "Wireframe" ? [] : SceneLights.all(doc)
        let boards = Billboards.items(doc)
        let fog = FogSettings.load(doc)
        let weather = WeatherSettings.load(doc)
        var h = Hasher(); h.combine(lights); h.combine(boards); h.combine(fog.on); h.combine(fog.start); h.combine(fog.end); h.combine(fog.color); h.combine(fog.density)
        h.combine(weather); h.combine(style == "Hidden Line" || style == "Wireframe")
        let hash = h.finalize()
        fog.apply(to: scene)
        // Weather haze when no explicit fog is set (VIS-058).
        if !fog.on, let d = weather.fogDistance, style != "Hidden Line", style != "Wireframe" {
            scene.fogStartDistance = CGFloat(d * 0.1); scene.fogEndDistance = CGFloat(d)
            scene.fogColor = weather.kind == .snow ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.75, alpha: 1)
            scene.fogDensityExponent = 1
        }
        guard hash != extrasHash else { return }
        extrasHash = hash
        extrasRoot.childNodes.forEach { $0.removeFromParentNode() }
        for l in lights { extrasRoot.addChildNode(SceneLights.node(l)) }
        for b in boards { extrasRoot.addChildNode(Billboards.node(b)) }
        if style != "Hidden Line", style != "Wireframe", let s = Optional(worldSphere), let w = weather.node(center: s.center, radius: s.radius) { extrasRoot.addChildNode(w) }
    }
    var lightNodes: [SCNNode] { extrasRoot.childNodes.filter { $0.light != nil } }
    var billboardNodes: [SCNNode] { extrasRoot.childNodes.filter { $0.name?.hasPrefix("billboard:") == true } }
}
