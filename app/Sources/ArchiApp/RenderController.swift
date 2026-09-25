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
    var width = 1920
    var height = 1080
    var date = RenderSettings.defaultDate
    var exposure = 0.0
    var background: Background = .sky
    var antialias = true

    static var defaultDate: Date {
        var c = Calendar.current.dateComponents([.year], from: Date())
        c.month = 6; c.day = 21; c.hour = 15; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
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
        switch settings.background {
        case .sky: break
        case .white: b.scene.background.contents = NSColor.white
        case .transparent: b.scene.background.contents = NSColor.clear
        }
        let cam = SCNNode()
        let c = SCNCamera()
        c.automaticallyAdjustsZRange = true
        c.wantsHDR = true
        c.exposureOffset = CGFloat(settings.exposure)
        c.wantsExposureAdaptation = false
        c.bloomIntensity = 0.15
        c.bloomThreshold = 0.9
        c.screenSpaceAmbientOcclusionIntensity = 1.0
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
        b.scene.rootNode.addChildNode(cam)
        return (b, cam)
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

    static let builtIn: [RenderPreset] = [
        RenderPreset(name: "Draft (720p, fast)", width: 1280, height: 720, antialias: false, exposure: 0, background: "Sky"),
        RenderPreset(name: "Standard (1080p)", width: 1920, height: 1080, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "High (1440p)", width: 2560, height: 1440, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "Print (4K)", width: 3840, height: 2160, antialias: true, exposure: 0, background: "Sky"),
        RenderPreset(name: "Presentation (white)", width: 2560, height: 1440, antialias: true, exposure: 0.3, background: "White"),
        RenderPreset(name: "Square (1080×1080)", width: 1080, height: 1080, antialias: true, exposure: 0, background: "Sky"),
    ]
    private static let key = "render.presets"
    static var custom: [RenderPreset] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([RenderPreset].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    static var all: [RenderPreset] { builtIn + custom }

    func apply(to s: inout RenderSettings) {
        s.width = width; s.height = height; s.antialias = antialias; s.exposure = exposure
        s.background = RenderSettings.Background(rawValue: background) ?? .sky
    }
    static func from(_ s: RenderSettings, name: String) -> RenderPreset {
        RenderPreset(name: name, width: s.width, height: s.height, antialias: s.antialias, exposure: s.exposure, background: s.background.rawValue)
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
                Section("Sun") {
                    DatePicker("Date", selection: $settings.date, displayedComponents: .date)
                    Slider(value: Binding(get: { hourOfDay }, set: setHour), in: 5...21, step: 0.25) { Text("Time \(timeText)") }
                    Text(sunText).font(.caption).foregroundStyle(.secondary)
                    Text("Site \(fmt(model.doc.info.latitude, 3))°, \(fmt(model.doc.info.longitude, 3))°").font(.caption).foregroundStyle(.secondary)
                }
                Section("Camera") {
                    Slider(value: $settings.exposure, in: -2...2) { Text("Exposure \(fmt(settings.exposure, 1)) EV") }
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
        a.informativeText = "Resolution \(settings.width)×\(settings.height), exposure \(fmt(settings.exposure, 1)) EV, \(settings.background.rawValue) background."
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
