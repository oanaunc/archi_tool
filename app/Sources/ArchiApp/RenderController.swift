// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import AVFoundation
import UniformTypeIdentifiers
import ArchiCore

// MARK: - Solar position

/// Sun altitude/azimuth from the NOAA general solar position equations (accuracy ≈ 0.5°).
enum SunPosition {
    /// - Returns: altitude above the horizon and azimuth clockwise from true north, both in radians.
    static func compute(dayOfYear n: Int, localHour h: Double, latitude: Double, longitude: Double, utcOffsetHours tz: Double) -> (altitude: Double, azimuth: Double) {
        let g = 2 * Double.pi / 365 * (Double(n - 1) + (h - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let timeOffset = eqTime + 4 * longitude - 60 * tz
        let tst = h * 60 + timeOffset
        let ha = (tst / 4 - 180) * .pi / 180
        let lat = latitude * .pi / 180
        let cosZen = max(-1, min(1, sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha)))
        let zenith = acos(cosZen)
        var az = atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat)) + .pi
        az = az.truncatingRemainder(dividingBy: 2 * .pi)
        return (.pi / 2 - zenith, az)
    }

    static func compute(date: Date, latitude: Double, longitude: Double) -> (altitude: Double, azimuth: Double) {
        let cal = Calendar.current
        let n = cal.ordinality(of: .day, in: .year, for: date) ?? 172
        let c = cal.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        return compute(dayOfYear: n, localHour: h, latitude: latitude, longitude: longitude, utcOffsetHours: (longitude / 15).rounded())
    }

    /// Unit vector towards the sun in model coordinates (X east, Y project north, Z up).
    static func direction(altitude: Double, azimuth: Double, northAngleDegrees: Double) -> Vec3 {
        let d = Vec2(sin(azimuth), cos(azimuth)).rotated(by: rad(northAngleDegrees)) * cos(altitude)
        return Vec3(d.x, d.y, sin(altitude))
    }
}

// MARK: - Render settings and engine

struct RenderSettings {
    enum Background: String, CaseIterable { case sky = "Sky", white = "White", transparent = "Transparent" }
    /// Image-based lighting: procedural skies, or an equirectangular HDRI/EXR/JPEG file.
    enum Environment: String, CaseIterable { case physicalSky = "Physical Sky", clearSky = "Clear Sky", overcast = "Overcast", sunset = "Sunset", studio = "Studio", night = "Night", hdri = "HDRI File" }
    enum ShadowQuality: String, CaseIterable { case off = "Off", low = "Low", medium = "Medium", high = "High", ultra = "Ultra"
        var mapSize: CGFloat { switch self { case .off, .low: return 2048; case .medium, .high: return 4096; case .ultra: return 8192 } }
        var samples: Int { switch self { case .off: return 1; case .low: return 4; case .medium: return 8; case .high: return 16; case .ultra: return 32 } }
        var cascades: Int { switch self { case .ultra: return 4; case .high: return 3; default: return 2 } }
    }
    var width = 1920
    var height = 1080
    var date = RenderSettings.defaultDate
    var exposure = 0.0
    var background: Background = .sky
    var antialias = true
    var environment: Environment = .clearSky
    var hdriPath = ""
    var environmentIntensity = 1.3
    var shadowQuality: ShadowQuality = .high
    /// Penumbra radius in shadow-map texels (soft shadows).
    var shadowSoftness = 4.0
    /// Soft-shadow samples per pixel (nil = the quality preset's count).
    var shadowSamples: Int?
    var ambientOcclusion = 1.0
    var depthOfField = false
    /// Focus distance in metres (0 = the model centre).
    var focusDistance = 0.0
    var fStop = 2.8
    var whiteBalance = 6500.0
    var bloom = 0.15
    /// Clay / white model: every surface uses one matte white material.
    var clay = false

    static var defaultDate: Date {
        var c = Calendar.current.dateComponents([.year], from: Date())
        c.month = 6; c.day = 21; c.hour = 15; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}

/// Procedural equirectangular environment maps (sky dome + ground) used for image-based lighting.
@MainActor
enum EnvironmentMaps {
    private static var cache: [String: NSImage] = [:]
    static func image(_ e: RenderSettings.Environment, hdriPath: String, sun: Vec3? = nil) -> Any? {
        if e == .physicalSky { return PhysicalSky.image(sun: sun ?? Vec3(0.3, 0.3, 0.9).normalized) }
        if e == .hdri {
            let u = URL(fileURLWithPath: hdriPath)
            return FileManager.default.fileExists(atPath: u.path) ? u : image(.clearSky, hdriPath: "")
        }
        if let i = cache[e.rawValue] { return i }
        let (zenith, horizon, ground, glow): (NSColor, NSColor, NSColor, NSColor?) = {
            switch e {
            case .clearSky: return (NSColor(srgbRed: 0.24, green: 0.45, blue: 0.78, alpha: 1), NSColor(srgbRed: 0.78, green: 0.86, blue: 0.94, alpha: 1), NSColor(srgbRed: 0.36, green: 0.35, blue: 0.32, alpha: 1), nil)
            case .overcast: return (NSColor(white: 0.72, alpha: 1), NSColor(white: 0.88, alpha: 1), NSColor(white: 0.42, alpha: 1), nil)
            case .sunset: return (NSColor(srgbRed: 0.18, green: 0.22, blue: 0.45, alpha: 1), NSColor(srgbRed: 1.0, green: 0.62, blue: 0.35, alpha: 1), NSColor(srgbRed: 0.25, green: 0.2, blue: 0.18, alpha: 1), NSColor(srgbRed: 1, green: 0.8, blue: 0.5, alpha: 1))
            case .studio: return (NSColor(white: 0.95, alpha: 1), NSColor(white: 0.8, alpha: 1), NSColor(white: 0.55, alpha: 1), NSColor(white: 1, alpha: 1))
            case .night: return (NSColor(srgbRed: 0.02, green: 0.03, blue: 0.07, alpha: 1), NSColor(srgbRed: 0.08, green: 0.1, blue: 0.16, alpha: 1), NSColor(white: 0.03, alpha: 1), nil)
            case .hdri, .physicalSky: return (.gray, .gray, .gray, nil)
            }
        }()
        let w: CGFloat = 1024, h: CGFloat = 512
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSGradient(colors: [horizon, zenith], atLocations: [0, 1], colorSpace: .sRGB)?.draw(in: NSRect(x: 0, y: h / 2, width: w, height: h / 2), angle: 90)
        NSGradient(colors: [ground, horizon.blended(withFraction: 0.5, of: ground) ?? ground], atLocations: [0, 1], colorSpace: .sRGB)?.draw(in: NSRect(x: 0, y: 0, width: w, height: h / 2), angle: 90)
        if let g = glow {
            // Soft light source (sun glow or studio softbox) above the horizon.
            let c = NSPoint(x: w * 0.3, y: e == .studio ? h * 0.85 : h * 0.56)
            NSGradient(colors: [g.withAlphaComponent(0.95), g.withAlphaComponent(0)])?.draw(fromCenter: c, radius: 0, toCenter: c, radius: e == .studio ? 160 : 120, options: [])
        }
        img.unlockFocus()
        cache[e.rawValue] = img
        return img
    }
}

@MainActor
enum RenderEngine {
    /// Builds a realistic scene for the document with the given camera and sun.
    static func makeScene(doc: ArchiDocument, settings: RenderSettings) -> (Scene3DBuilder, SCNNode) {
        let b = Scene3DBuilder()
        b.update(doc: doc, style: "Realistic")
        let sun = SunPosition.compute(date: settings.date, latitude: doc.info.latitude, longitude: doc.info.longitude)
        b.setSun(direction: SunPosition.direction(altitude: sun.altitude, azimuth: sun.azimuth, northAngleDegrees: doc.info.northAngle))
        // Dusk/night: dim the sun and warm it up.
        let alt = sun.altitude
        b.sunNode.light?.intensity = alt <= 0 ? 0 : CGFloat(1800 * min(1, sin(alt) * 2.2 + 0.1))
        if alt < 0.25 { b.sunNode.light?.color = NSColor(srgbRed: 1, green: 0.78, blue: 0.55, alpha: 1) }
        b.ambientNode.light?.intensity = alt <= 0 ? 90 : 260
        // Image-based lighting and the visible background.
        let env = EnvironmentMaps.image(settings.environment, hdriPath: settings.hdriPath,
                                        sun: SunPosition.direction(altitude: sun.altitude, azimuth: sun.azimuth, northAngleDegrees: doc.info.northAngle))
        b.scene.lightingEnvironment.contents = env
        b.scene.lightingEnvironment.intensity = CGFloat(settings.environmentIntensity)
        switch settings.background {
        case .sky: b.scene.background.contents = env
        case .white: b.scene.background.contents = NSColor.white
        case .transparent: b.scene.background.contents = NSColor.clear
        }
        if settings.environment == .night { b.sunNode.light?.intensity = min(b.sunNode.light?.intensity ?? 0, 60) }
        // Shadow quality and softness.
        if let l = b.sunNode.light {
            l.castsShadow = settings.shadowQuality != .off
            l.shadowMapSize = CGSize(width: settings.shadowQuality.mapSize, height: settings.shadowQuality.mapSize)
            l.shadowSampleCount = max(1, min(64, settings.shadowSamples ?? settings.shadowQuality.samples))
            l.shadowRadius = CGFloat(max(0, settings.shadowSoftness))
            l.shadowCascadeCount = settings.shadowQuality.cascades
        }
        if settings.clay { RenderEngine.applyClay(b.modelRoot) }
        let cam = SCNNode()
        let c = SCNCamera()
        c.automaticallyAdjustsZRange = true
        c.wantsHDR = true
        c.exposureOffset = CGFloat(settings.exposure)
        c.wantsExposureAdaptation = false
        c.bloomIntensity = CGFloat(settings.bloom)
        c.bloomThreshold = 0.9
        c.whiteBalanceTemperature = CGFloat(settings.whiteBalance)
        c.screenSpaceAmbientOcclusionIntensity = CGFloat(settings.ambientOcclusion)
        c.screenSpaceAmbientOcclusionRadius = 0.45
        c.vignettingIntensity = 0.3
        c.vignettingPower = 0.6
        c.fieldOfView = 45
        cam.camera = c
        if let active = Viewport3DController.active, let src = active.cameraNode.presentation.camera {
            cam.transform = active.cameraNode.presentation.worldTransform
            c.fieldOfView = src.fieldOfView
            c.usesOrthographicProjection = src.usesOrthographicProjection
            c.orthographicScale = src.orthographicScale
        } else {
            let s = b.worldSphere
            let d = s.radius / sin(22.5 * .pi / 180) * 1.15
            let dir = Viewport3DController.norm(SCNVector3(-1, 0.8, 1))
            cam.position = SCNVector3(s.center.x + dir.x * d, s.center.y + dir.y * d, s.center.z + dir.z * d)
            cam.look(at: s.center)
        }
        if settings.depthOfField {
            c.wantsDepthOfField = true
            let s = b.worldSphere
            let p = cam.position
            let auto = sqrt(pow(p.x - s.center.x, 2) + pow(p.y - s.center.y, 2) + pow(p.z - s.center.z, 2))
            c.focusDistance = settings.focusDistance > 0 ? CGFloat(settings.focusDistance) : auto
            c.fStop = CGFloat(max(0.5, settings.fStop))
            c.apertureBladeCount = 6
            c.focalBlurSampleCount = 16
        }
        b.scene.rootNode.addChildNode(cam)
        return (b, cam)
    }

    /// Clay render: one matte white material on every model surface (glass stays translucent).
    static func applyClay(_ root: SCNNode) {
        let clay = SCNMaterial()
        clay.lightingModel = .physicallyBased
        clay.diffuse.contents = NSColor(white: 0.92, alpha: 1)
        clay.roughness.contents = NSNumber(value: 0.85)
        clay.metalness.contents = NSNumber(value: 0)
        root.enumerateHierarchy { n, _ in
            guard let g = n.geometry, n.name != "ground" else { return }
            g.materials = g.materials.map { m in
                if m.transparency < 0.95 { let t = clay.copy() as! SCNMaterial; t.transparency = m.transparency; t.isDoubleSided = true; return t }
                if m.lightingModel == .constant { return m }   // edges and lines
                return clay
            }
        }
    }

    static func render(doc: ArchiDocument, settings: RenderSettings, camera override: SCNMatrix4? = nil) -> NSImage? {
        let (b, cam) = makeScene(doc: doc, settings: settings)
        if let t = override { cam.transform = t }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene
        r.pointOfView = cam
        r.autoenablesDefaultLighting = false
        r.isJitteringEnabled = settings.antialias
        return r.snapshot(atTime: 0, with: CGSize(width: settings.width, height: settings.height),
                          antialiasingMode: settings.antialias ? .multisampling4X : .none)
    }

    /// 360° orbit around the model written as H.264 MP4.
    static func turntable(doc: ArchiDocument, settings: RenderSettings, seconds: Double, fps: Int = 30, to url: URL,
                          progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let w = settings.width - settings.width % 2, h = settings.height - settings.height % 2
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: w * h * 6],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        var s2 = settings; s2.width = w; s2.height = h
        let (b, cam) = makeScene(doc: doc, settings: s2)
        guard let device = MTLCreateSystemDefaultDevice() else { throw CocoaError(.featureUnsupported) }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene; r.pointOfView = cam
        let sphere = b.worldSphere
        let start = cam.position
        let rel = Viewport3DController.sub(start, sphere.center)
        let radius = max(sphere.radius * 1.2, hypot(rel.x, rel.z))
        let height = rel.y
        let a0 = atan2(rel.x, rel.z)
        let frames = max(2, Int(seconds * Double(fps)))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            let a = a0 + CGFloat(i) / CGFloat(frames) * 2 * .pi
            cam.position = SCNVector3(sphere.center.x + sin(a) * radius, sphere.center.y + height, sphere.center.z + cos(a) * radius)
            cam.look(at: sphere.center)
            let img = r.snapshot(atTime: Double(i) / Double(fps), with: CGSize(width: w, height: h), antialiasingMode: .multisampling4X)
            guard let pool = adaptor.pixelBufferPool else { break }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let buf = pb, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            CVPixelBufferLockBaseAddress(buf, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            progress(Double(i + 1) / Double(frames))
            await Task.yield()
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

// MARK: - Render presets

/// Saved render settings (resolution, antialiasing, exposure, background).
struct RenderPreset: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var width: Int
    var height: Int
    var antialias: Bool
    var exposure: Double
    var background: String
    // Added later: optional so presets saved by earlier versions still decode.
    var environment: String?
    var environmentIntensity: Double?
    var shadowQuality: String?
    var shadowSoftness: Double?
    var ambientOcclusion: Double?
    var depthOfField: Bool?
    var fStop: Double?
    var whiteBalance: Double?
    var clay: Bool?

    static let builtIn: [RenderPreset] = [
        RenderPreset(name: "Draft (720p, fast)", width: 1280, height: 720, antialias: false, exposure: 0, background: "Sky"),
        RenderPreset(name: "Standard (1080p)", width: 1920, height: 1080, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "High (1440p)", width: 2560, height: 1440, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "Print (4K)", width: 3840, height: 2160, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "Presentation (white)", width: 2560, height: 1440, antialias: true, exposure: 0.3, background: "White"),
        RenderPreset(name: "Square (1080×1080)", width: 1080, height: 1080, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "Clay Model (studio)", width: 1920, height: 1080, antialias: true, exposure: 0.2, background: "Sky",
                     environment: "Studio", environmentIntensity: 1.6, shadowQuality: "High", shadowSoftness: 8, ambientOcclusion: 1.5, clay: true),
        RenderPreset(name: "Golden Hour", width: 1920, height: 1080, antialias: true, exposure: 0.1, background: "Sky",
                     environment: "Sunset", environmentIntensity: 1.1, shadowQuality: "Ultra", shadowSoftness: 6, ambientOcclusion: 1.0, whiteBalance: 5200),
        RenderPreset(name: "Overcast Soft", width: 1920, height: 1080, antialias: true, exposure: 0.3, background: "Sky",
                     environment: "Overcast", environmentIntensity: 1.8, shadowQuality: "Medium", shadowSoftness: 14, ambientOcclusion: 1.4),
        RenderPreset(name: "Eye Level (depth of field)", width: 1920, height: 1080, antialias: true, exposure: 0, background: "Sky",
                     environment: "Clear Sky", shadowQuality: "High", depthOfField: true, fStop: 2.0),
    ]
    private static let key = "render.presets"
    static var custom: [RenderPreset] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([RenderPreset].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    static var all: [RenderPreset] { builtIn + custom }

    func apply(to s: inout RenderSettings) {
        let d = RenderSettings()
        s.width = width; s.height = height; s.antialias = antialias; s.exposure = exposure
        s.background = RenderSettings.Background(rawValue: background) ?? .sky
        s.environment = environment.flatMap(RenderSettings.Environment.init(rawValue:)) ?? d.environment
        s.environmentIntensity = environmentIntensity ?? d.environmentIntensity
        s.shadowQuality = shadowQuality.flatMap(RenderSettings.ShadowQuality.init(rawValue:)) ?? d.shadowQuality
        s.shadowSoftness = shadowSoftness ?? d.shadowSoftness
        s.ambientOcclusion = ambientOcclusion ?? d.ambientOcclusion
        s.depthOfField = depthOfField ?? false
        s.fStop = fStop ?? d.fStop
        s.whiteBalance = whiteBalance ?? d.whiteBalance
        s.clay = clay ?? false
    }
    static func from(_ s: RenderSettings, name: String) -> RenderPreset {
        RenderPreset(name: name, width: s.width, height: s.height, antialias: s.antialias, exposure: s.exposure, background: s.background.rawValue,
                     environment: s.environment.rawValue, environmentIntensity: s.environmentIntensity, shadowQuality: s.shadowQuality.rawValue,
                     shadowSoftness: s.shadowSoftness, ambientOcclusion: s.ambientOcclusion, depthOfField: s.depthOfField, fStop: s.fStop,
                     whiteBalance: s.whiteBalance, clay: s.clay)
    }
}

// MARK: - Window

enum RenderController {
    @MainActor private static var window: NSWindow?

    /// Opens (or brings forward) the render window for the model.
    @MainActor static func renderImage(model: AppModel) {
        if let w = window {
            w.contentViewController = NSHostingController(rootView: RenderPanel(model: model))
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Render — \(model.doc.info.name)"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: RenderPanel(model: model))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

private struct RenderPanel: View {
    @ObservedObject var model: AppModel
    @State private var settings = RenderSettings()
    @State private var image: NSImage?
    @State private var busy = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var resolution = "1920×1080"
    @State private var seconds = 8.0
    @State private var animSeconds = 10.0
    @State private var sunFrom = 7.0
    @State private var sunTo = 19.0
    @State private var presetName = UserDefaults.standard.string(forKey: "render.lastPreset") ?? "Standard (1080p)"
    @State private var presets = RenderPreset.all
    private let resolutions = ["1280×720", "1920×1080", "2560×1440", "3840×2160", "1080×1080"]

    var sunText: String {
        let s = SunPosition.compute(date: settings.date, latitude: model.doc.info.latitude, longitude: model.doc.info.longitude)
        return "Sun altitude \(fmt(deg(s.altitude), 1))°, azimuth \(fmt(deg(s.azimuth), 1))°"
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(white: 0.12)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(12)
                } else {
                    Text(busy ? "Rendering…" : "Press Render").foregroundStyle(.secondary)
                }
                if busy { ProgressView(value: progress > 0 ? progress : nil).frame(width: 220).padding().background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel)) }
            }
            Divider()
            Form {
                Section("Preset") {
                    Picker("Preset", selection: Binding(get: { presetName }, set: { applyPreset($0) })) {
                        ForEach(presets) { Text($0.name).tag($0.name) }
                        if !presets.contains(where: { $0.name == presetName }) { Text("Custom").tag(presetName) }
                    }
                    HStack {
                        Button("Save as Preset…") { savePreset() }
                        if RenderPreset.custom.contains(where: { $0.name == presetName }) {
                            Button("Delete") {
                                RenderPreset.custom = RenderPreset.custom.filter { $0.name != presetName }
                                presets = RenderPreset.all
                                presetName = "Standard (1080p)"
                            }
                        }
                    }
                }
                Section("Output") {
                    Picker("Resolution", selection: $resolution) { ForEach(resolutions, id: \.self) { Text($0) } }
                    Picker("Background", selection: $settings.background) { ForEach(RenderSettings.Background.allCases, id: \.self) { Text($0.rawValue) } }
                    Toggle("Antialiasing (4× MSAA + jitter)", isOn: $settings.antialias)
                }
                Section("Environment") {
                    Picker("Lighting", selection: $settings.environment) { ForEach(RenderSettings.Environment.allCases, id: \.self) { Text($0.rawValue) } }
                    if settings.environment == .hdri {
                        HStack {
                            Text(settings.hdriPath.isEmpty ? "No file" : URL(fileURLWithPath: settings.hdriPath).lastPathComponent).font(.caption).lineLimit(1)
                            Spacer()
                            Button("Choose…") { chooseHDRI() }
                        }
                    }
                    Slider(value: $settings.environmentIntensity, in: 0...3) { Text("Intensity \(fmt(settings.environmentIntensity, 1))") }
                    Toggle("Clay model (white)", isOn: $settings.clay)
                }
                Section("Shadows & Occlusion") {
                    Picker("Shadow quality", selection: $settings.shadowQuality) { ForEach(RenderSettings.ShadowQuality.allCases, id: \.self) { Text($0.rawValue) } }
                    Slider(value: $settings.shadowSoftness, in: 0...20) { Text("Softness \(fmt(settings.shadowSoftness, 0))") }
                        .disabled(settings.shadowQuality == .off)
                    Stepper("Soft shadow samples: \(settings.shadowSamples ?? settings.shadowQuality.samples)",
                            value: Binding(get: { settings.shadowSamples ?? settings.shadowQuality.samples }, set: { settings.shadowSamples = $0 }), in: 1...64, step: 1)
                        .disabled(settings.shadowQuality == .off)
                    Slider(value: $settings.ambientOcclusion, in: 0...2) { Text("Ambient occlusion \(fmt(settings.ambientOcclusion, 1))") }
                }
                Section("Sun") {
                    DatePicker("Date", selection: $settings.date, displayedComponents: .date)
                    Slider(value: Binding(get: { hourOfDay }, set: setHour), in: 5...21, step: 0.25) { Text("Time \(timeText)") }
                    Text(sunText).font(.caption).foregroundStyle(.secondary)
                    Text("Site \(fmt(model.doc.info.latitude, 3))°, \(fmt(model.doc.info.longitude, 3))°").font(.caption).foregroundStyle(.secondary)
                }
                Section("Camera") {
                    Slider(value: $settings.exposure, in: -2...2) { Text("Exposure \(fmt(settings.exposure, 1)) EV") }
                    Slider(value: $settings.whiteBalance, in: 3000...9000, step: 100) { Text("White balance \(Int(settings.whiteBalance)) K") }
                    Slider(value: $settings.bloom, in: 0...1) { Text("Bloom \(fmt(settings.bloom, 2))") }
                    Toggle("Depth of field", isOn: $settings.depthOfField)
                    if settings.depthOfField {
                        Slider(value: $settings.fStop, in: 0.8...16) { Text("f/\(fmt(settings.fStop, 1))") }
                        Slider(value: $settings.focusDistance, in: 0...200) { Text(settings.focusDistance == 0 ? "Focus: model centre" : "Focus \(fmt(settings.focusDistance, 1)) m") }
                    }
                    Text(Viewport3DController.active == nil ? "Default iso view (open the 3D view to set the camera)" : "Uses the current 3D view camera")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Button("Render") { render() }.keyboardShortcut(.return, modifiers: .command).disabled(busy)
                        Button("Save…") { save() }.disabled(image == nil || busy)
                        Button("Copy") { copy() }.disabled(image == nil)
                    }
                    HStack {
                        Stepper("Turntable \(Int(seconds)) s", value: $seconds, in: 5...10)
                        Button("Export Video…") { turntable() }.disabled(busy)
                    }
                    if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Animation & Panorama") {
                    let cams = model.doc.namedViews.filter { $0.camera != nil }
                    Stepper("Length \(Int(animSeconds)) s", value: $animSeconds, in: 3...120)
                    HStack {
                        Button("Walkthrough Video…") { walkthrough() }.disabled(busy || cams.count < 2)
                            .help(cams.count < 2 ? "Save at least two cameras (SAVECAMERA); the path runs through them in order." : "Smooth path through the \(cams.count) saved cameras, in order")
                        Text("\(cams.count) camera(s)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Stepper("From \(Int(sunFrom)):00", value: $sunFrom, in: 0...23)
                        Stepper("to \(Int(sunTo)):00", value: $sunTo, in: 1...24)
                    }
                    Button("Sun Study Video…") { sunStudyVideo() }.disabled(busy || sunTo <= sunFrom)
                    Button("360° Panorama…") { panorama() }.disabled(busy)
                        .help("Equirectangular 2:1 panorama from the current 3D camera position")
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { if let p = presets.first(where: { $0.name == presetName }) { applyPreset(p.name) } }
    }

    private func applyPreset(_ name: String) {
        presetName = name
        guard let p = presets.first(where: { $0.name == name }) else { return }
        p.apply(to: &settings)
        resolution = "\(p.width)×\(p.height)"
        UserDefaults.standard.set(name, forKey: "render.lastPreset")
    }

    private func savePreset() {
        applyResolution()
        let a = NSAlert()
        a.messageText = "Save Render Preset"
        a.informativeText = "Resolution \(settings.width)×\(settings.height), exposure \(fmt(settings.exposure, 1)) EV, \(settings.environment.rawValue) lighting, \(settings.shadowQuality.rawValue.lowercased()) shadows\(settings.depthOfField ? ", depth of field" : "")\(settings.clay ? ", clay" : "")."
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        tf.stringValue = "My Preset \(RenderPreset.custom.count + 1)"
        a.accessoryView = tf
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !RenderPreset.builtIn.contains(where: { $0.name == n }) else { return }
        var c = RenderPreset.custom.filter { $0.name != n }
        c.append(RenderPreset.from(settings, name: n))
        RenderPreset.custom = c
        presets = RenderPreset.all
        presetName = n
        UserDefaults.standard.set(n, forKey: "render.lastPreset")
    }

    private func chooseHDRI() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["hdr", "exr", "jpg", "jpeg", "png", "tif", "tiff"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Choose an equirectangular (2:1) environment image"
        if p.runModal() == .OK, let u = p.url { settings.hdriPath = u.path }
    }

    private var hourOfDay: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: settings.date)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }
    private var timeText: String { String(format: "%02d:%02d", Int(hourOfDay), Int((hourOfDay - floor(hourOfDay)) * 60 + 0.5) % 60) }
    private func setHour(_ h: Double) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: settings.date)
        c.hour = Int(h); c.minute = Int((h - floor(h)) * 60 + 0.5)
        if let d = Calendar.current.date(from: c) { settings.date = d }
    }

    private func applyResolution() {
        let parts = resolution.split(separator: "×").compactMap { Int($0) }
        if parts.count == 2 { settings.width = parts[0]; settings.height = parts[1] }
    }

    private func render() {
        applyResolution()
        busy = true; progress = 0; status = ""
        let s = settings, doc = model.doc
        Task { @MainActor in
            await Task.yield()
            let t0 = Date()
            image = RenderEngine.render(doc: doc, settings: s)
            busy = false
            status = image == nil ? "Rendering failed (Metal unavailable)." : "Rendered \(s.width)×\(s.height) in \(fmt(Date().timeIntervalSince(t0), 1)) s"
        }
    }

    private func save() {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "\(model.doc.info.name) render.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) : rep.representation(using: .png, properties: [:])
        do { try data?.write(to: url); status = "Saved \(url.lastPathComponent)" } catch { status = error.localizedDescription }
    }

    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        status = "Copied to the clipboard."
    }

    private func videoURL(_ suffix: String) -> URL? {
        applyResolution()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(model.doc.info.name) \(suffix).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func walkthrough() {
        guard let url = videoURL("walkthrough") else { return }
        busy = true; progress = 0
        var s = settings
        if s.width > 1920 { s.width = 1920; s.height = 1080 }
        let doc = model.doc, secs = animSeconds
        let cams = doc.namedViews.compactMap(\.camera)
        Task { @MainActor in
            do {
                try await RenderEngine.walkthrough(doc: doc, settings: s, cameras: cams, seconds: secs, to: url) { p in progress = p }
                status = "Saved \(url.lastPathComponent)"
            } catch { status = "Video export failed: \(error.localizedDescription)" }
            busy = false
        }
    }

    private func sunStudyVideo() {
        guard let url = videoURL("sun study") else { return }
        busy = true; progress = 0
        var s = settings
        if s.width > 1920 { s.width = 1920; s.height = 1080 }
        let doc = model.doc, secs = animSeconds, a = sunFrom, b = sunTo
        let day = Calendar.current.ordinality(of: .day, in: .year, for: settings.date) ?? 172
        let cam = Viewport3DController.active?.currentCamera
        Task { @MainActor in
            do {
                try await RenderEngine.sunStudy(doc: doc, settings: s, dayOfYear: day, fromHour: a, toHour: b, seconds: secs, camera: cam, to: url) { p in progress = p }
                status = "Saved \(url.lastPathComponent)"
            } catch { status = "Video export failed: \(error.localizedDescription)" }
            busy = false
        }
    }

    private func panorama() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "\(model.doc.info.name) 360.jpg"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; progress = 0
        let doc = model.doc, s = settings
        let eye = Viewport3DController.active?.currentCamera.eye ?? PanoramaDefaults.eye(doc)
        Task { @MainActor in
            await Task.yield()
            if let img = RenderEngine.panorama(doc: doc, settings: s, eye: eye, width: max(2048, s.width * 2)) {
                do { try RenderEngine.write(img, to: url); image = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)); status = "Saved \(url.lastPathComponent) (\(img.width)×\(img.height))" }
                catch { status = error.localizedDescription }
            } else { status = "Panorama failed (Metal unavailable)." }
            busy = false
        }
    }

    private func turntable() {
        applyResolution()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(model.doc.info.name) turntable.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; progress = 0
        var s = settings
        if s.width > 1920 { s.width = 1920; s.height = 1080 }
        let doc = model.doc, secs = seconds
        Task { @MainActor in
            do {
                try await RenderEngine.turntable(doc: doc, settings: s, seconds: secs, to: url) { p in progress = p }
                status = "Saved \(url.lastPathComponent)"
            } catch { status = "Video export failed: \(error.localizedDescription)" }
            busy = false
        }
    }
}
