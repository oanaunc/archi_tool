// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ImageIO
import simd
import ArchiCore

/// Checks of the photographic render pass: presets, the procedural HDR sky and its .hdr files, the meadow ground,
/// Realistic materials (glass, glowing windows), lens-shift vertical correction, supersampling and the
/// RENDERPRESET / RENDERSAVE commands with their menu entries.
@MainActor
extension AppSelfTests {
    static func beautyChecks(_ check: (Bool, String) -> Void) {
        // Presets and parsing.
        check(BeautyPreset.named("golden hour") == .goldenHour && BeautyPreset.named("Goldenhour") == .goldenHour && BeautyPreset.named("OVERCAST") == .overcast
              && BeautyPreset.named("night") == .night && BeautyPreset.named("Daylight") == .daylight && BeautyPreset.named("xyz") == nil, "render presets parse leniently")
        check(BeautyPreset.allCases.allSatisfy { BeautyPreset.named($0.keyword) == $0 && BeautyPreset.named($0.rawValue) == $0 }, "every preset round-trips through its keyword")
        let day = BeautyPreset.daylight.look, gold = BeautyPreset.goldenHour.look, over = BeautyPreset.overcast.look, night = BeautyPreset.night.look
        check(gold.sunAltitude < 15 && day.sunAltitude > 30 && gold.sunColor.z < gold.sunColor.x * 0.5, "golden hour: low, warm sun")
        check(over.shadowRadius > day.shadowRadius * 4 && over.sunIntensity < day.sunIntensity / 3 && over.envIntensity > day.envIntensity, "overcast: soft shadows, sky-dominated light")
        check(night.windowGlow > 1 && night.exposure > day.exposure + 0.8 && day.windowGlow == 0, "night: glowing windows and higher exposure")
        let sd = day.sunDirection(northAngle: 0)
        check(abs(sd.length - 1) < 1e-9 && abs(asin(sd.z) * 180 / .pi - day.sunAltitude) < 1e-6 && sd.x < 0 && sd.y < 0, "daylight sun from the south-west at its altitude")

        // Sky radiance model.
        let sun = BeautyLighting.sceneKitSun(day, northAngle: 0)
        let zen = BeautySky.radiance(SIMD3(0, 1, 0), sun: sun, sky: .daylight)
        let hor = BeautySky.radiance(simd_normalize(SIMD3(-sun.x, 0.02, -sun.z)), sun: sun, sky: .daylight)
        check(zen.z > zen.x * 2.5 && hor.x > zen.x * 2, "clear sky: deep blue zenith, pale horizon")
        check(simd_length(BeautySky.radiance(sun, sun: sun, sky: .daylight)) > 20, "clear sky: HDR solar disc")
        let away = simd_normalize(SIMD3(-sun.x, max(0.3, sun.y), -sun.z))
        let near = simd_normalize(sun + SIMD3(0.12, 0, 0.12))
        check(simd_length(BeautySky.radiance(near, sun: sun, sky: .daylight)) > simd_length(BeautySky.radiance(away, sun: sun, sky: .daylight)), "clear sky brightens towards the sun")
        let gsun = BeautyLighting.sceneKitSun(gold, northAngle: 0)
        let gToward = BeautySky.radiance(simd_normalize(SIMD3(gsun.x, 0.03, gsun.z)), sun: gsun, sky: .golden)
        let gAway = BeautySky.radiance(simd_normalize(SIMD3(-gsun.x, 0.03, -gsun.z)), sun: gsun, sky: .golden)
        check(gToward.x > gToward.z * 1.8 && gAway.z > gAway.x * 0.9 && gToward.x > gAway.x * 1.5, "golden hour: warm horizon at the sun, cool opposite")
        let oz = BeautySky.radiance(SIMD3(0, 1, 0), sun: sun, sky: .overcast), oh = BeautySky.radiance(simd_normalize(SIMD3(1, 0.02, 0)), sun: sun, sky: .overcast)
        check(oz.y > oh.y * 1.8 && abs(oz.x - oz.z) < 0.3 * oz.y, "overcast: neutral sky about three times brighter at the zenith")
        let nz = BeautySky.radiance(SIMD3(0.3, 0.9, 0.3), sun: sun, sky: .night)
        check(simd_length(nz) * 30 < simd_length(zen), "night sky is dark")
        check(BeautySky.radiance(SIMD3(0, -1, 0), sun: sun, sky: .daylight).y < hor.y, "ground half darker than the horizon")

        // RGBE encoding round trip and the cached .hdr files.
        let px: [Float] = [0, 0, 0, 0.5, 0.25, 0.125, 12, 3, 1, 0.001, 0.002, 0.003, 60, 55, 50, 1, 1, 1]
        let enc = BeautySky.rgbe(px, width: 3, height: 2)
        if let dec = BeautySky.decodeRGBE(enc), dec.w == 3, dec.h == 2 {
            var ok = true
            for i in 0..<6 {
                let m = max(px[i * 3], px[i * 3 + 1], px[i * 3 + 2])
                for c in 0..<3 where abs(px[i * 3 + c] - dec.px[i * 3 + c]) > m / 100 + 1e-7 { ok = false }
            }
            check(ok, "RGBE (.hdr) encoding keeps HDR values within 1% of the pixel's peak")
        } else { check(false, "RGBE (.hdr) round trip decodes") }
        let t0 = Date()
        if let u = BeautySky.url(.golden, sun: gsun, width: 256) {
            let src = CGImageSourceCreateWithURL(u as CFURL, nil)
            let img = src.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            check(img?.width == 256 && img?.height == 128, "procedural sky .hdr opens with ImageIO (\(img?.width ?? 0)×\(img?.height ?? 0))")
            check((img?.bitsPerComponent ?? 8) >= 16, "sky .hdr loads as high dynamic range (\(img?.bitsPerComponent ?? 0) bits per component)")
            check(BeautySky.url(.golden, sun: gsun, width: 256) == u, "sky files are cached")
        } else { check(false, "procedural sky .hdr is written") }
        check(Date().timeIntervalSince(t0) < 10, "sky generation is fast")

        // Noise and ground.
        let a = BeautyNoise.value(0.25, 0.75, period: 8), b = BeautyNoise.value(8.25, 16.75, period: 8)
        check(abs(a - b) < 1e-5 && (0...1).contains(BeautyNoise.fbm(3.3, 1.7, octaves: 5)), "value noise is periodic and bounded")
        let g = BeautyGround.texture()
        check(g.size.width == 512 && BeautyGround.material(size: 1_000_000).diffuse.maxAnisotropy == 16, "meadow ground texture and anisotropic material")

        // Realistic scene with a preset: glowing glass at night, HDR environment, fog, soft shadows.
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0))))
        var og = OpeningGeom(kind: .window, hostWall: w, offset: 3000, width: 1800, height: 1400)
        og.sill = 900
        _ = d.addElement(.opening(og))
        d.setVariable(BeautyPreset.variable, BeautyPreset.night.rawValue)
        let bn = Scene3DBuilder()
        bn.update(doc: d, style: "Realistic")
        var glass: SCNMaterial?
        bn.modelRoot.enumerateHierarchy { n, _ in if let m = n.geometry?.materials.first, m.name == "Glass" { glass = m } }
        check(bn.beautyPreset == .night && bn.beautyExplicit, "drawing preset reaches the Realistic scene")
        check((glass?.emission.intensity ?? 0) > 1 && glass?.lightingModel == .physicallyBased, "night: windows glow")
        check(bn.scene.lightingEnvironment.contents is URL && bn.scene.background.contents is URL, "HDR sky lights the scene and fills the background")
        check(bn.scene.fogEndDistance > bn.scene.fogStartDistance && bn.scene.fogStartDistance > 10, "horizon haze fades the ground")
        check((bn.sunNode.light?.intensity ?? 0) < 200 && (bn.groundNode.geometry?.materials.first?.diffuse.contents as? NSImage)?.size.width == 512, "night: moonlight, meadow ground")
        d.setVariable(BeautyPreset.variable, BeautyPreset.daylight.rawValue)
        bn.update(doc: d, style: "Realistic")
        glass = nil
        bn.modelRoot.enumerateHierarchy { n, _ in if let m = n.geometry?.materials.first, m.name == "Glass" { glass = m } }
        let em = (glass?.emission.contents as? NSColor)?.usingColorSpace(.sRGB)
        check(em == nil || (em!.redComponent + em!.greenComponent + em!.blueComponent) * (glass?.emission.intensity ?? 0) < 0.01, "daylight: windows do not glow")
        check((glass?.transparency ?? 1) < 1 && (glass?.transparency ?? 0) >= 0.6 && glass?.transparencyMode == .dualLayer, "daylight glass: tinted, reflective, partly transparent")
        check((bn.sunNode.light?.shadowRadius ?? 0) > 0 && (bn.sunNode.light?.shadowSampleCount ?? 0) >= 8 && bn.sunNode.light?.castsShadow == true, "soft sun shadows in the viewport")
        bn.update(doc: d, style: "Shaded")
        check(bn.scene.fogEndDistance == 0 && !(bn.scene.background.contents is URL), "other styles keep their plain backgrounds")

        // Camera response.
        let cam = SCNCamera()
        BeautyLighting.configure(cam, .goldenHour, quality: .final(supersample: 2))
        check(cam.wantsHDR && cam.bloomIntensity > 0 && cam.screenSpaceAmbientOcclusionIntensity > 0 && cam.bloomBlurRadius == 20 && cam.whitePoint > 1, "final camera: HDR tone mapping, bloom scaled to supersampling, SSAO")

        // Vertical correction (lens shift): target stays centred, verticals parallel.
        let c = Camera(eye: Vec3(0, -20000, 1500), target: Vec3(0, 0, 3500), fov: 40)
        if let s = BeautyRenderer.shiftProjection(camera: c, aspect: 16.0 / 9) {
            // Target in level-camera view space: 20 m ahead, 2 m up.
            func ndcY(_ y: Double, _ z: Double) -> Double {
                let m = s.projection
                let cy = y * Double(m.m22) + z * Double(m.m32), cw = z * Double(m.m34)
                return cy / cw
            }
            check(abs(ndcY(2, -20)) < 1e-9 && s.target.z == c.eye.z, "lens shift keeps the camera level and the target centred")
            let bottom = Double(s.projection.m11) * 3 / 20, top = Double(s.projection.m11) * 3 / 40
            check(abs(bottom - top * 2) < 1e-9, "vertical edges stay vertical (x independent of height)")
        } else { check(false, "eye-level camera gets lens shift") }
        check(BeautyRenderer.shiftProjection(camera: Camera(eye: Vec3(0, -20000, 15000), target: Vec3(0, 0, 0), fov: 40), aspect: 1.5) == nil, "aerial cameras keep natural perspective")
        check(BeautyRenderer.supersample(width: 3840, height: 2160, requested: 4) == 3 && BeautyRenderer.supersample(width: 1920, height: 1080, requested: 2) == 2
              && BeautyRenderer.supersample(width: 7680, height: 4320, requested: 2) == 1, "supersampling limited to a 12k frame")
        let sp = BeautyRenderer.splitCameraAnswer("Front Door 1920 1080 a b.png", cameras: ["Front", "Front Door"])
        check(sp.camera == "Front Door" && sp.rest == ["1920", "1080", "a", "b.png"] && BeautyRenderer.splitCameraAnswer("current", cameras: []).camera == "Current", "RENDERSAVE splits camera names from the size and path")
        check(BeautyRenderer.resolve("~/x", base: nil).path.hasSuffix("/x.png") && BeautyRenderer.resolve("r/a.png", base: URL(fileURLWithPath: "/tmp")).path == "/tmp/r/a.png", "RENDERSAVE path resolution")

        // Downsampling averages (box filter at least).
        if let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            ctx.setFillColor(.black); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 4))
            if let big = ctx.makeImage(), let small = BeautyRenderer.downsample(big, width: 2, height: 2) { check(small.width == 2 && small.height == 2, "supersampled frames filter down") }
        }

        // Commands and menus.
        let names = Set(CommandCatalog.coverageMenus.flatMap(\.1).flatMap(\.names))
        check(BeautyCommands.all.allSatisfy { names.contains($0.name) && CommandRegistry.shared.lookup($0.name) != nil }, "RENDERPRESET and RENDERSAVE are registered with menu entries")
        let core = CommandRegistry(); core.ensureBuiltins()
        check(BeautyCommands.all.flatMap { [$0.name] + $0.aliases }.allSatisfy { core.lookup($0) == nil }, "photographic render commands do not shadow core commands")
        let m = AppModel()
        var e2 = ArchiDocument()
        let w2 = e2.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        _ = w2
        e2.namedViews = [NamedView(name: "Street", center: Vec2(2000, 0), height: 8000, camera: Camera(eye: Vec3(2000, -9000, 1600), target: Vec3(2000, 0, 1600), fov: 45))]
        m.editor.replaceDocument(e2, url: nil)
        var done = false
        var log: [String] = []
        Task { @MainActor in _ = await m.editor.run("RENDERPRESET Goldenhour"); done = true }
        spin(10) { done }
        check(BeautyPreset.current(m.doc) == .goldenHour && m.viewStyle == "Realistic", "RENDERPRESET stores the preset and shows the Realistic view")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest-beauty-\(ProcessInfo.processInfo.processIdentifier).png")
        try? FileManager.default.removeItem(at: out)
        done = false
        Task { @MainActor in log = await m.editor.run("RENDERSAVE Daylight Street 96 64 \(out.path)"); done = true }
        spin(60) { done }
        let rep = (try? Data(contentsOf: out)).flatMap { NSBitmapImageRep(data: $0) }
        check(rep?.pixelsWide == 96 && rep?.pixelsHigh == 64, "RENDERSAVE writes a PNG of the requested size (\(rep?.pixelsWide ?? 0)×\(rep?.pixelsHigh ?? 0)) \(rep == nil ? log.suffix(3).joined(separator: " | ") : "")")
        if let rep, let top = rep.colorAt(x: 48, y: 2), let low = rep.colorAt(x: 48, y: 60) {
            check(top.blueComponent > top.redComponent && abs(top.brightnessComponent - low.brightnessComponent) > 0.02, "rendered image shows sky above ground")
        }
        try? FileManager.default.removeItem(at: out)
    }
}
