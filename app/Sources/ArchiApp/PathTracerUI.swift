// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import simd
import ArchiCore

/// Builds the path tracer scene from a drawing: the same meshes, texture mapping, materials, PBR maps, lights, sun,
/// sky, weather and water as the Realistic viewport, seen from the viewport camera.
@MainActor
enum PTSceneBuilder {
    struct Options {
        var render = RenderSettings()
        var ground = true
        var clay = false
        var time: Float = 0
    }

    static func material(_ name: String, doc: ArchiDocument, scene: PTScene, textureCache: inout [String: Int], clay: Bool, weather: WeatherSettings) -> PTMaterial {
        let src = doc.material(name) ?? ArchiCore.Material(name: name, color: RGBA(0.8, 0.8, 0.8))
        var c = src.color
        if WeatherSettings.isVegetation(name) { c = WeatherSettings.seasonTint(c, weather.season) }
        func lin(_ v: Double) -> Float { PTTexture.srgbToLinear(Float(v)) }
        var m = PTMaterial()
        m.albedo = PTVec(lin(c.r), lin(c.g), lin(c.b))
        m.roughness = Float(min(max(src.roughness, 0.02), 1))
        m.metalness = Float(min(max(src.metalness, 0), 1))
        m.transmission = Float(min(max(src.transparency, 0), 0.98))
        m.uvScale = Float(1000 / max(src.textureScale, 1))
        if m.transmission > 0.3 { m.roughness = min(m.roughness, 0.08) }
        let water = WaterSurface.isWater(name, doc: doc)
        if water { m.water = true; m.ior = 1.33; m.transmission = max(m.transmission, 0.85); m.roughness = 0.02 }
        let k = Emissive.strength(name, doc: doc)
        if k > 0 { m.emission = m.albedo * Float(k) * 3000 }
        if clay && m.transmission < 0.3 { m = PTMaterial(); m.albedo = PTVec(repeating: 0.8); m.roughness = 0.85; return m }
        func tex(_ path: String?, linear: Bool) -> Int {
            guard let p = path, !p.isEmpty else { return -1 }
            let key = p + (linear ? "|L" : "|D")
            if let i = textureCache[key] { return i }
            guard let img = MaterialTextures.image(p), let t = PTTexture.from(image: img, maxSize: 1024, linearize: linear) else { textureCache[key] = -1; return -1 }
            scene.textures.append(t)
            textureCache[key] = scene.textures.count - 1
            return scene.textures.count - 1
        }
        m.albedoMap = tex(src.texture, linear: true)
        if m.albedoMap >= 0 { m.albedo = PTVec(lin(src.color.r * 0.25 + 0.75), lin(src.color.g * 0.25 + 0.75), lin(src.color.b * 0.25 + 0.75)) }
        let maps = MaterialMaps.load(name, doc: doc)
        m.normalMap = tex(maps.normal, linear: false); m.normalStrength = Float(maps.normalStrength)
        m.roughnessMap = tex(maps.roughness, linear: false)
        m.metalMap = tex(maps.metallic, linear: false)
        m.aoMap = tex(maps.ao, linear: false)
        m.bumpMap = tex(maps.displacement, linear: false); m.bumpStrength = Float(max(maps.displacementScale, 0) / 10)
        if m.normalMap < 0, m.bumpMap < 0, let t = src.texture, BumpMap.strength(name, doc: doc) > 0 {
            m.bumpMap = tex(t, linear: false); m.bumpStrength = Float(BumpMap.strength(name, doc: doc)) * 0.5
        }
        m.snow = Float(weather.snow); m.wet = Float(weather.wetness)
        return m
    }

    static func build(doc: ArchiDocument, camera: Camera?, options o: Options) -> (PTScene, PTCamera) {
        let scene = PTScene()
        var cache: [String: Int] = [:]
        var matIndex: [String: Int] = [:]
        let weather = WeatherSettings.load(doc)
        let anims = ObjectAnimations.load(doc)
        for g in MeshBuilder.build(doc: doc) where !g.mesh.isEmpty {
            let mi: Int
            if let i = matIndex[g.material] { mi = i } else {
                scene.materials.append(material(g.material, doc: doc, scene: scene, textureCache: &cache, clay: o.clay, weather: weather))
                mi = scene.materials.count - 1; matIndex[g.material] = mi
            }
            var mesh = TextureMapping.apply(g.mesh, material: g.material, doc: doc)
            // Object animation at the render time (VIS-045): whole objects move; door leaves swing.
            if let id = g.id, !anims.isEmpty {
                let mine = anims.filter { $0.target == id }
                if let a = mine.first(where: { $0.kind != .door }) { mesh.positions = mesh.positions.map { a.apply($0, at: Double(o.time)) } }
                let doorAnims = mine.filter { $0.kind == .door }
                if !doorAnims.isEmpty, let el = doc.element(id), g.material == (el.material ?? "Wood") {
                    let split = ObjectAnimations.splitDoor(mesh, leaves: ObjectAnimations.doorLeaves(el, doc: doc))
                    scene.add(split.rest, material: mi)
                    for (k, var lm) in split.leaves.enumerated() where k < doorAnims.count {
                        lm.positions = lm.positions.map { doorAnims[k].apply($0, at: Double(o.time)) }
                        lm.normals = lm.normals.map { n in let s = doorAnims[k].state(at: Double(o.time)).angle; return Vec3(n.x * cos(s) - n.y * sin(s), n.x * sin(s) + n.y * cos(s), n.z) }
                        scene.add(lm, material: mi)
                    }
                    continue
                }
            }
            scene.add(mesh, material: mi)
        }
        if o.ground {
            var gm = PTMaterial(); gm.albedo = PTVec(0.32, 0.31, 0.29); gm.roughness = 0.95; gm.snow = Float(weather.snow); gm.wet = Float(weather.wetness)
            scene.materials.append(gm); scene.groundMaterial = scene.materials.count - 1
            let base = Float(doc.levels.map(\.elevation).min() ?? 0)
            scene.groundZ = scene.tris.isEmpty ? base : min(base, scene.boundsMin.z) - 1
        }
        scene.time = o.time
        scene.buildBVH()
        // Sun and sky from the project location and render date.
        let sun = SunPosition.compute(date: o.render.date, latitude: doc.info.latitude, longitude: doc.info.longitude)
        let dir = SunPosition.direction(altitude: sun.altitude, azimuth: sun.azimuth, northAngleDegrees: doc.info.northAngle)
        scene.environment = PTEnvironment.preset(o.render.environment, sun: dir, altitude: sun.altitude)
        let ei = Float(o.render.environmentIntensity / 1.3)
        scene.environment.zenith *= ei; scene.environment.horizon *= ei; scene.environment.ground *= ei
        if weather.kind == .rain || weather.kind == .fog || weather.kind == .snow {
            // Overcast weather: diffuse sky, weak sun.
            let k = Float(1 - 0.85 * weather.intensity)
            scene.environment.sunIrradiance *= k
            let grey = PTVec(repeating: ptLum(scene.environment.horizon))
            scene.environment.zenith = scene.environment.zenith * k + grey * (1 - k)
        }
        // Placed lights (lumens → candela, cone for spots).
        for l in SceneLights.all(doc) {
            let cd = Float(l.lumens / (4 * .pi))
            let col = kelvinRGB(l.cct)
            var pl = PTPointLight(position: PTVec(Float(l.position.x), Float(l.position.y), Float(l.position.z)), intensity: col * cd, direction: nil, cosOuter: -1, cosInner: -1)
            if let t = l.target, l.kind == .spot || l.kind == .ies {
                let d = t - l.position
                if d.length > 1e-6 {
                    pl.direction = simd_normalize(PTVec(Float(d.x), Float(d.y), Float(d.z)))
                    pl.cosOuter = cosf(Float(l.beam) * .pi / 360); pl.cosInner = cosf(Float(l.beam * 0.7) * .pi / 360)
                    pl.intensity *= 2 / max(1 - pl.cosOuter, 0.05) / 2
                }
            }
            scene.lights.append(pl)
        }
        // Camera: the viewport's, or a three-quarter view of the model.
        var cam: PTCamera
        if let c = camera { cam = PTCamera(c) } else {
            let c = (scene.boundsMin + scene.boundsMax) / 2, r = max(scene.sceneSize / 2, 1000)
            cam = PTCamera(eye: c + simd_normalize(PTVec(-1, -1.3, 0.8)) * r * 2.6, target: c, fovDegrees: 45)
        }
        return (scene, cam)
    }

    /// Approximate RGB (linear, max 1) of a black body at a colour temperature.
    static func kelvinRGB(_ k: Double) -> PTVec {
        let t = k / 100
        var r: Double, g: Double, b: Double
        if t <= 66 { r = 255; g = 99.47 * log(t) - 161.12 } else { r = 329.7 * pow(t - 60, -0.1332); g = 288.1 * pow(t - 60, -0.0755) }
        b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5 * log(t - 10) - 305.04)
        func c(_ v: Double) -> Float { PTTexture.srgbToLinear(Float(min(max(v, 0), 255) / 255)) }
        return PTVec(c(r), c(g), c(b))
    }
}

// MARK: - Window

@MainActor
final class PathTraceController: ObservableObject {
    @Published var image: NSImage?
    @Published var samples = 0
    @Published var target = 64
    @Published var running = false
    @Published var denoise = true
    @Published var ev: Double = 0
    @Published var mix = PTLightMix() { didSet { refresh() } }
    @Published var width = 960
    @Published var height = 540
    @Published var status = ""
    weak var model: AppModel?
    private var session: PTSession?
    private var task: Task<Void, Never>?
    private var started = Date()

    init(model: AppModel) { self.model = model }

    func start() {
        guard let m = model else { return }
        stop()
        var rs = RenderSettings()
        rs.width = width; rs.height = height
        let (scene, cam) = PTSceneBuilder.build(doc: m.doc, camera: Viewport3DController.active?.currentCamera, options: PTSceneBuilder.Options(render: rs))
        var s = PTSettings(); s.width = width; s.height = height; s.camera = cam; s.clampIndirect = 0
        let session = PTSession(scene: scene, settings: s)
        self.session = session
        samples = 0; running = true; started = Date()
        status = "\(scene.tris.count) triangles, \(scene.lights.count) lights"
        let target = self.target
        task = Task.detached(priority: .userInitiated) { [weak self] in
            for i in 0..<target {
                if Task.isCancelled { break }
                session.renderPass()
                if i < 4 || i % 4 == 3 || i == target - 1 {
                    await MainActor.run { self?.samples = session.samples; self?.refresh(final: i == target - 1) }
                }
            }
            await MainActor.run { self?.running = false; self?.refresh(final: true) }
        }
    }
    func stop() { task?.cancel(); task = nil; running = false }

    func hdr(final: Bool) -> [PTVec]? {
        guard let s = session, s.samples > 0 else { return nil }
        let c = s.compose(mix)
        if denoise && (final || !running) { return PTDenoiser.denoise(color: c, albedo: s.meanAlbedo, normal: s.meanNormal, depth: s.meanDepth, width: s.width, height: s.height) }
        return c
    }
    func refresh(final: Bool = false) {
        guard let s = session, let h = hdr(final: final), let cg = PTToneMap.cgImage(h, width: s.width, height: s.height, ev: Float(ev)) else { return }
        image = NSImage(cgImage: cg, size: NSSize(width: s.width, height: s.height))
        let secs = Date().timeIntervalSince(started)
        status = "\(s.samples) samples · \(String(format: "%.1f", secs)) s · \(s.scene.tris.count) triangles"
    }
    func save() {
        guard let img = image, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "Path Traced.png"
        if p.runModal() == .OK, let u = p.url { try? png.write(to: u) }
    }
}

private struct PathTraceView: View {
    @ObservedObject var c: PathTraceController
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                if let i = c.image { Image(nsImage: i).resizable().aspectRatio(contentMode: .fit) }
                else { Text("Press Render to path trace the 3D view").foregroundStyle(Theme.textDim) }
            }
            .frame(minWidth: 480, minHeight: 300)
            VStack(alignment: .leading, spacing: 8) {
                Text("Path Tracer").font(Theme.fontBold)
                HStack {
                    Button(c.running ? "Stop" : "Render") { c.running ? c.stop() : c.start() }.buttonStyle(FlatButtonStyle(compact: true))
                    Button("Save…") { c.save() }.buttonStyle(FlatButtonStyle(compact: true)).disabled(c.image == nil)
                }
                Picker("Size", selection: Binding(get: { "\(c.width)x\(c.height)" }, set: { v in let p = v.split(separator: "x").compactMap { Int($0) }; if p.count == 2 { c.width = p[0]; c.height = p[1] } })) {
                    ForEach(["640x360", "960x540", "1280x720", "1920x1080", "800x800"], id: \.self) { Text($0).tag($0) }
                }
                Stepper("Samples: \(c.target)", value: $c.target, in: 4...4096, step: 16)
                Toggle("Denoise", isOn: Binding(get: { c.denoise }, set: { c.denoise = $0; c.refresh(final: true) }))
                HStack { Text("Exposure"); Slider(value: Binding(get: { c.ev }, set: { c.ev = $0; c.refresh(final: !c.running) }), in: -3...3) }
                Divider()
                Text("Light Mix").font(Theme.fontBold)
                mixSlider("Sun", \.sun)
                mixSlider("Sky", \.sky)
                mixSlider("Artificial", \.artificial)
                Button("Reset Mix") { c.mix = PTLightMix() }.buttonStyle(FlatButtonStyle(compact: true))
                Spacer()
                Text(c.status).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(3)
            }
            .font(Theme.font)
            .padding(10)
            .frame(width: 230)
            .background(Theme.panel)
        }
    }
    private func mixSlider(_ t: String, _ kp: WritableKeyPath<PTLightMix, Float>) -> some View {
        HStack {
            Text(t).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { Double(c.mix[keyPath: kp]) }, set: { c.mix[keyPath: kp] = Float($0) }), in: 0...4)
            Text(String(format: "%.2f", c.mix[keyPath: kp])).font(Theme.mono).frame(width: 34)
        }
    }
}

@MainActor
enum PathTraceWindow {
    private static var window: NSWindow?
    private(set) static var controller: PathTraceController?
    static func show(model: AppModel, start: Bool = true) {
        let c = controller?.model === model ? controller! : PathTraceController(model: model)
        controller = c
        let view = PathTraceView(c: c).preferredColorScheme(Theme.colorScheme)
        if let w = window { w.contentViewController = NSHostingController(rootView: view); w.makeKeyAndOrderFront(nil) }
        else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Path Tracer"; w.isReleasedWhenClosed = false; w.appearance = Theme.appearance
            w.contentViewController = NSHostingController(rootView: view)
            w.center(); w.makeKeyAndOrderFront(nil)
            window = w
        }
        if start && !c.running { c.start() }
    }
}

/// Offline path-traced render to a file (command line and scripts).
enum PathTraceFile {
    @MainActor static func render(doc: ArchiDocument, camera: Camera?, width: Int, height: Int, samples: Int, denoise: Bool, mix: PTLightMix = PTLightMix(), time: Float = 0, to url: URL) async throws -> (samples: Int, seconds: Double) {
        var rs = RenderSettings(); rs.width = width; rs.height = height
        var o = PTSceneBuilder.Options(render: rs); o.time = time
        let (scene, cam) = PTSceneBuilder.build(doc: doc, camera: camera, options: o)
        var s = PTSettings(); s.width = width; s.height = height; s.camera = cam
        let session = PTSession(scene: scene, settings: s)
        let t0 = Date()
        let n = max(1, samples)
        await Task.detached(priority: .userInitiated) { for _ in 0..<n { session.renderPass() } }.value
        var hdr = session.compose(mix)
        if denoise { hdr = PTDenoiser.denoise(color: hdr, albedo: session.meanAlbedo, normal: session.meanNormal, depth: session.meanDepth, width: width, height: height) }
        guard let cg = PTToneMap.cgImage(hdr, width: width, height: height) else { throw CommandError.invalid("Could not make the image.") }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) : rep.representation(using: .png, properties: [:])
        guard let d = data else { throw CommandError.invalid("Could not encode the image.") }
        try d.write(to: url)
        return (session.samples, Date().timeIntervalSince(t0))
    }
}
