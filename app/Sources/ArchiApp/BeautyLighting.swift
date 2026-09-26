// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import simd
import ArchiCore

// MARK: - Presets

/// Photographic lighting presets for the Realistic viewport and final renders (RENDERPRESET, RENDERSAVE):
/// sun, procedural HDR sky (image-based lighting and background), shadows, exposure, bloom and glass/emissive looks.
enum BeautyPreset: String, CaseIterable, Codable {
    case daylight = "Daylight", goldenHour = "Golden hour", overcast = "Overcast", night = "Night"

    /// Drawing variable holding the preset of the Realistic viewport (and the default of renders).
    static let variable = "RENDERPRESET"
    /// Single-word keywords for the command line.
    static let keywords = ["Daylight", "Goldenhour", "Overcast", "Night"]

    var keyword: String { BeautyPreset.keywords[BeautyPreset.allCases.firstIndex(of: self) ?? 0] }

    /// Parses a preset name leniently ("golden hour", "Golden-Hour", "golden", "sunset", "cloudy", "dusk"…).
    static func named(_ s: String) -> BeautyPreset? {
        let k = s.lowercased().filter { $0.isLetter }
        switch k {
        case "daylight", "day", "sunny", "clear", "clearsky", "noon": return .daylight
        case "goldenhour", "golden", "sunset", "sunrise", "evening", "warm": return .goldenHour
        case "overcast", "cloudy", "soft", "grey", "gray": return .overcast
        case "night", "dusk", "dark", "nightlights", "bluehour": return .night
        default: return nil
        }
    }

    /// The preset stored in the drawing (nil when none was chosen).
    static func current(_ doc: ArchiDocument) -> BeautyPreset? { doc.variable(variable).flatMap(named) }

    var look: BeautyLook {
        switch self {
        case .daylight:
            return BeautyLook(sky: .daylight, sunAltitude: 46, sunAzimuth: 222, sunColor: SIMD3(1.0, 0.955, 0.89), sunIntensity: 3300,
                              shadowRadius: 2.5, shadowAlpha: 0.94, envIntensity: 1.05, ambient: 0, exposure: 0.6, whitePoint: 1.7,
                              bloom: 0.10, bloomThreshold: 1.1, saturation: 1.06, contrast: 0.06, ao: 0.85, windowGlow: 0, artificial: 0, lampGlow: 0.3)
        case .goldenHour:
            return BeautyLook(sky: .golden, sunAltitude: 11, sunAzimuth: 228, sunColor: SIMD3(1.0, 0.66, 0.38), sunIntensity: 3400,
                              shadowRadius: 5, shadowAlpha: 0.9, envIntensity: 0.95, ambient: 0, exposure: 0.75, whitePoint: 1.7,
                              bloom: 0.22, bloomThreshold: 0.95, saturation: 1.1, contrast: 0.08, ao: 0.9, windowGlow: 0.12, artificial: 0.3, lampGlow: 1.0)
        case .overcast:
            return BeautyLook(sky: .overcast, sunAltitude: 58, sunAzimuth: 200, sunColor: SIMD3(0.93, 0.96, 1.0), sunIntensity: 420,
                              shadowRadius: 22, shadowAlpha: 0.7, envIntensity: 1.55, ambient: 0, exposure: 0.8, whitePoint: 1.5,
                              bloom: 0.05, bloomThreshold: 1.3, saturation: 0.98, contrast: 0.1, ao: 1.25, windowGlow: 0, artificial: 0.05, lampGlow: 0.4)
        case .night:
            return BeautyLook(sky: .night, sunAltitude: 38, sunAzimuth: 135, sunColor: SIMD3(0.62, 0.72, 1.0), sunIntensity: 70,
                              shadowRadius: 6, shadowAlpha: 0.85, envIntensity: 1.0, ambient: 8, exposure: 1.6, whitePoint: 1.2,
                              bloom: 0.55, bloomThreshold: 0.75, saturation: 1.0, contrast: 0.05, ao: 0.8, windowGlow: 1.6, artificial: 1.6, lampGlow: 3.0)
        }
    }
}

/// Everything a preset sets (colours are linear RGB).
struct BeautyLook: Equatable {
    enum Sky: String { case daylight, golden, overcast, night }
    var sky: Sky
    /// Sun (or moon) altitude above the horizon and azimuth clockwise from project north, degrees.
    var sunAltitude: Double
    var sunAzimuth: Double
    var sunColor: SIMD3<Float>
    var sunIntensity: Double
    /// Penumbra radius in shadow-map texels and the shadow opacity.
    var shadowRadius: Double
    var shadowAlpha: Double
    var envIntensity: Double
    var ambient: Double
    var exposure: Double
    var whitePoint: Double
    var bloom: Double
    var bloomThreshold: Double
    var saturation: Double
    var contrast: Double
    var ao: Double
    /// Emission of glazing (lit interiors) and the scale of artificial lights / emissive lamps.
    var windowGlow: Double
    var artificial: Double
    var lampGlow: Double

    /// Direction towards the sun in model coordinates (X east, Y north, Z up).
    func sunDirection(northAngle: Double) -> Vec3 {
        SunPosition.direction(altitude: sunAltitude * .pi / 180, azimuth: sunAzimuth * .pi / 180, northAngleDegrees: northAngle)
    }
}

/// Interactive viewport or final render (shadow maps, samples, sky resolution).
enum BeautyQuality: Equatable {
    case interactive
    case final(supersample: Int)
    var isFinal: Bool { if case .final = self { return true }; return false }
    var shadowMap: CGFloat { isFinal ? 8192 : 4096 }
    var shadowSamples: Int { isFinal ? 32 : 8 }
    var cascades: Int { isFinal ? 4 : 2 }
    var skyWidth: Int { isFinal ? 2048 : 1024 }
}

// MARK: - Procedural noise

/// Hash-based value noise and fractal sums (periodic when `period` > 0), shared by the sky and the ground texture.
enum BeautyNoise {
    @inline(__always) static func hash(_ x: Int32, _ y: Int32, _ seed: Int32 = 0) -> Float {
        var h = UInt32(bitPattern: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    @inline(__always) static func value(_ x: Float, _ y: Float, period: Int32 = 0, seed: Int32 = 0) -> Float {
        let fx0 = x.rounded(.down), fy0 = y.rounded(.down)
        var x0 = Int32(clamping: Int(fx0)), y0 = Int32(clamping: Int(fy0))
        let fx = x - fx0, fy = y - fy0
        var x1 = x0 &+ 1, y1 = y0 &+ 1
        if period > 0 {
            x0 = ((x0 % period) + period) % period; y0 = ((y0 % period) + period) % period
            x1 = ((x1 % period) + period) % period; y1 = ((y1 % period) + period) % period
        }
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let a = hash(x0, y0, seed), b = hash(x1, y0, seed), c = hash(x0, y1, seed), d = hash(x1, y1, seed)
        return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy
    }

    /// Fractal Brownian motion in 0…1.
    static func fbm(_ x: Float, _ y: Float, octaves: Int, period: Int32 = 0, seed: Int32 = 0) -> Float {
        var sum: Float = 0, amp: Float = 0.5, norm: Float = 0, f: Float = 1
        var p = period
        for o in 0..<octaves {
            sum += amp * value(x * f, y * f, period: p, seed: seed &+ Int32(o) &* 17)
            norm += amp; amp *= 0.5; f *= 2; p = p > 0 ? p * 2 : 0
        }
        return sum / max(norm, 1e-6)
    }
}

// MARK: - Procedural HDR sky

/// Analytic skies (clear daylight with clouds, golden hour, CIE-like overcast, night with stars and moon), written as
/// Radiance .hdr equirectangular maps so SceneKit uses them as HDR image-based lighting and as the background.
enum BeautySky {
    @inline(__always) private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t)
    }
    @inline(__always) private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    /// Linear radiance of the sky in direction `d` (SceneKit world, Y up; unit) for the sun direction `s` (unit).
    /// `px`/`py` pixel indices seed the stars.
    static func radiance(_ d: SIMD3<Float>, sun s: SIMD3<Float>, sky: BeautyLook.Sky, px: Int = 0, py: Int = 0) -> SIMD3<Float> {
        let up = max(d.y, 0)
        let cosA = max(-1, min(1, simd_dot(d, s)))
        let ang = acos(cosA)
        // Horizontal sunward factor (for golden-hour horizon colours).
        let dh = SIMD2<Float>(d.x, d.z), sh = SIMD2<Float>(s.x, s.z)
        let sunward: Float = (simd_length(dh) > 1e-4 && simd_length(sh) > 1e-4) ? simd_dot(simd_normalize(dh), simd_normalize(sh)) * 0.5 + 0.5 : 0.5
        // Cloud-layer coordinates (plane above the camera).
        let cp = SIMD2<Float>(d.x, d.z) / (d.y + 0.12)

        var col: SIMD3<Float>
        let ground: SIMD3<Float>
        var horizon: SIMD3<Float>
        switch sky {
        case .daylight:
            let zen = SIMD3<Float>(0.05, 0.17, 0.66), hor = SIMD3<Float>(0.62, 0.75, 0.94)
            horizon = hor
            col = mix(zen, hor, pow(1 - up, 3.2))
            let glow = SIMD3<Float>(1.0, 0.93, 0.80) * (0.30 * exp(-ang * 2.2) + 1.1 * exp(-ang * 14))
            col += glow
            if d.y > 0.005 {
                let n = BeautyNoise.fbm(cp.x * 1.3 + 11, cp.y * 1.3 - 7, octaves: 6, seed: 3)
                let cover = smooth(0.50, 0.78, n) * smooth(0.01, 0.22, d.y)
                let shade = 0.72 + 0.4 * BeautyNoise.fbm(cp.x * 3.1 + 5, cp.y * 3.1 + 2, octaves: 4, seed: 9)
                let lit = SIMD3<Float>(1.05, 1.05, 1.08) * shade + glow * 0.8
                col = mix(col, lit, cover * 0.9)
            }
            if ang < 0.012 { col += SIMD3<Float>(1.0, 0.96, 0.9) * 45 }
            ground = SIMD3<Float>(0.15, 0.145, 0.13)
        case .golden:
            let zen = SIMD3<Float>(0.09, 0.13, 0.30)
            let warm = SIMD3<Float>(1.15, 0.56, 0.24), cool = SIMD3<Float>(0.42, 0.44, 0.58)
            let hor = mix(cool, warm, pow(sunward, 2.5))
            horizon = hor
            col = mix(zen, hor, pow(1 - up, 2.6))
            let glow = SIMD3<Float>(1.0, 0.52, 0.22) * (0.7 * exp(-ang * 2.8) + 2.6 * exp(-ang * 16))
            col += glow
            if d.y > 0.005 {
                let n = BeautyNoise.fbm(cp.x * 1.1 - 3, cp.y * 1.1 + 13, octaves: 6, seed: 5)
                let cover = smooth(0.56, 0.8, n) * smooth(0.01, 0.25, d.y)
                let lit = mix(SIMD3<Float>(0.32, 0.26, 0.36), SIMD3<Float>(1.35, 0.66, 0.42), pow(sunward, 1.5)) + glow * 0.9
                col = mix(col, lit, cover * 0.85)
            }
            if ang < 0.014 { col += SIMD3<Float>(1.0, 0.62, 0.32) * 30 }
            ground = SIMD3<Float>(0.07, 0.058, 0.05)
        case .overcast:
            let base = SIMD3<Float>(0.78, 0.81, 0.86) * 1.12
            col = base * ((1 + 2 * up) / 3)
            horizon = base / 3 * 1.05
            let n = BeautyNoise.fbm(cp.x * 0.9, cp.y * 0.9, octaves: 5, seed: 7)
            col *= 0.82 + 0.34 * n
            col += SIMD3<Float>(0.26, 0.26, 0.25) * exp(-ang * 2.2) * smooth(-0.1, 0.2, d.y)
            ground = SIMD3<Float>(0.11, 0.11, 0.105)
        case .night:
            let zen = SIMD3<Float>(0.0025, 0.0045, 0.013), hor = SIMD3<Float>(0.018, 0.024, 0.045)
            horizon = hor
            col = mix(zen, hor, pow(1 - up, 3))
            col += SIMD3<Float>(0.055, 0.036, 0.02) * pow(1 - up, 12)            // distant town glow
            col += SIMD3<Float>(0.03, 0.04, 0.07) * exp(-ang * 5)                // moon halo
            if d.y > 0.04 {
                let h = BeautyNoise.hash(Int32(px), Int32(py), 77)
                if h > 0.9975 { col += SIMD3<Float>(0.9, 0.93, 1.0) * ((h - 0.9975) / 0.0025) * 1.4 * smooth(0.04, 0.3, d.y) }
            }
            if ang < 0.011 { col += SIMD3<Float>(0.9, 0.94, 1.0) * 5 }
            ground = SIMD3<Float>(0.006, 0.006, 0.007)
        }
        if d.y < 0 {
            let haze = exp(d.y * 18)
            return mix(ground, horizon * 0.75, haze)
        }
        return col
    }

    /// Average horizon colour seen around the scene (linear), used for the distance fog that fades the ground.
    static func horizonColor(_ sky: BeautyLook.Sky, sun: SIMD3<Float>) -> SIMD3<Float> {
        var acc = SIMD3<Float>(0, 0, 0)
        for i in 0..<16 {
            let a = Float(i) / 16 * 2 * .pi
            acc += radiance(simd_normalize(SIMD3<Float>(sin(a), 0.035, -cos(a))), sun: sun, sky: sky)
        }
        return acc / 16
    }

    /// Linear RGB float pixels (row 0 at the top), equirectangular with the `Panorama.direction` convention.
    static func pixels(sky: BeautyLook.Sky, sun: SIMD3<Float>, width w: Int, height h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h * 3)
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: h) { y in
                let v = (Double(y) + 0.5) / Double(h)
                for x in 0..<w {
                    let d = Panorama.direction(u: (Double(x) + 0.5) / Double(w), v: v)
                    let c = radiance(SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)), sun: sun, sky: sky, px: x, py: y)
                    let i = (y * w + x) * 3
                    base[i] = c.x; base[i + 1] = c.y; base[i + 2] = c.z
                }
            }
        }
        return out
    }

    /// Radiance RGBE (.hdr) file bytes, flat scanlines.
    static func rgbe(_ px: [Float], width w: Int, height h: Int) -> Data {
        var d = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\nSOFTWARE=Oanarina Archi Tool\n\n-Y \(h) +X \(w)\n".utf8)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let r = max(0, px[i * 3]), g = max(0, px[i * 3 + 1]), b = max(0, px[i * 3 + 2])
            let m = max(r, max(g, b))
            if m < 1e-32 { continue }
            let e = frexp(m).1
            let scale = ldexp(Float(1), -e) * 256
            bytes[i * 4] = UInt8(min(255, r * scale)); bytes[i * 4 + 1] = UInt8(min(255, g * scale))
            bytes[i * 4 + 2] = UInt8(min(255, b * scale)); bytes[i * 4 + 3] = UInt8(clamping: e + 128)
            // A flat scanline must not start like an RLE marker (2, 2, width-high-byte).
            if i % w == 0 && bytes[i * 4] == 2 && bytes[i * 4 + 1] == 2 { bytes[i * 4] = 3 }
        }
        d.append(contentsOf: bytes)
        return d
    }

    /// Decodes RGBE bytes written by `rgbe` (tests).
    static func decodeRGBE(_ data: Data) -> (w: Int, h: Int, px: [Float])? {
        guard let marker = data.range(of: Data("\n\n".utf8)) else { return nil }
        guard let lineEnd = data[marker.upperBound...].firstIndex(of: 0x0A) else { return nil }
        let res = String(decoding: data[marker.upperBound..<lineEnd], as: UTF8.self).split(separator: " ")
        guard res.count == 4, let h = Int(res[1]), let w = Int(res[3]) else { return nil }
        let body = data[(lineEnd + 1)...]
        guard body.count == w * h * 4 else { return nil }
        var px = [Float](repeating: 0, count: w * h * 3)
        let b = Array(body)
        for i in 0..<(w * h) where b[i * 4 + 3] != 0 {
            let f = ldexp(Float(1), Int(b[i * 4 + 3]) - 136)
            px[i * 3] = (Float(b[i * 4]) + 0.5) * f; px[i * 3 + 1] = (Float(b[i * 4 + 1]) + 0.5) * f; px[i * 3 + 2] = (Float(b[i * 4 + 2]) + 0.5) * f
        }
        return (w, h, px)
    }

    static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let u = base.appendingPathComponent("Oanarina Archi Tool/Skies", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// URL of the cached .hdr sky for the look and sun (created on first use).
    @MainActor static func url(_ sky: BeautyLook.Sky, sun: SIMD3<Float>, width: Int) -> URL? {
        let key = "v3-\(sky.rawValue)-\(width)-" + [sun.x, sun.y, sun.z].map { String(format: "%.2f", $0) }.joined(separator: "_")
        let u = cacheFolder.appendingPathComponent(key + ".hdr")
        if FileManager.default.fileExists(atPath: u.path) { return u }
        let h = width / 2
        let data = rgbe(pixels(sky: sky, sun: sun, width: width, height: h), width: width, height: h)
        do { try data.write(to: u, options: .atomic) } catch { return nil }
        return u
    }
}

// MARK: - Ground

/// Meadow ground beyond the site (seamless 8 m tile) that receives shadows and fades into the horizon fog.
@MainActor
enum BeautyGround {
    private static var cached: NSImage?
    static let tileMetres: CGFloat = 8

    static func texture() -> NSImage {
        if let c = cached { return c }
        let s = 512
        var px = [UInt8](repeating: 255, count: s * s * 4)
        let period: Int32 = 8
        px.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: s) { y in
                for x in 0..<s {
                    let u = Float(x) / Float(s) * Float(period), v = Float(y) / Float(s) * Float(period)
                    let broad = BeautyNoise.fbm(u, v, octaves: 3, period: period, seed: 21)
                    let fine = BeautyNoise.fbm(u * 8, v * 8, octaves: 3, period: period * 8, seed: 5)
                    let blade = BeautyNoise.value(u * 64, v * 16, period: period * 16, seed: 8)
                    let dry = max(0, min(1, (broad - 0.55) * 3))
                    var r = 0.20 + 0.10 * fine + 0.04 * blade, g = 0.33 + 0.12 * fine + 0.05 * blade, b = 0.12 + 0.05 * fine
                    r += dry * 0.14; g += dry * 0.07; b += dry * 0.03
                    let shade = 0.82 + 0.3 * broad
                    let i = (y * s + x) * 4
                    base[i] = UInt8(min(255, r * shade * 255)); base[i + 1] = UInt8(min(255, g * shade * 255)); base[i + 2] = UInt8(min(255, b * shade * 255))
                }
            }
        }
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: s, height: s, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: s * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return NSImage(size: NSSize(width: 1, height: 1)) }
        let img = NSImage(cgImage: cg, size: NSSize(width: s, height: s))
        cached = img
        return img
    }

    /// Physically based meadow material for a plane of `size` millimetres.
    static func material(size: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = texture()
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 16
        let k = CGFloat(size / 1000) / tileMetres
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(k, k, 1)
        m.roughness.contents = NSNumber(value: 0.95)
        m.metalness.contents = NSNumber(value: 0)
        m.writesToDepthBuffer = true
        return m
    }
}

// MARK: - Applying a look

@MainActor
enum BeautyLighting {
    static func sceneKitSun(_ look: BeautyLook, northAngle: Double) -> SIMD3<Float> {
        let d = look.sunDirection(northAngle: northAngle).normalized
        return simd_normalize(SIMD3<Float>(Float(d.x), Float(d.z), Float(-d.y)))
    }

    static func color(_ c: SIMD3<Float>) -> NSColor {
        // Linear → sRGB NSColor.
        func e(_ v: Float) -> CGFloat { let x = max(0, min(1, v)); return CGFloat(x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055) }
        return NSColor(srgbRed: e(c.x), green: e(c.y), blue: e(c.z), alpha: 1)
    }

    /// Applies the look to a Realistic scene: sun, shadows, HDR sky (lighting + background), fog and artificial lights.
    /// `placeSun`: false keeps the current sun direction (sun studies in the viewport).
    static func apply(_ preset: BeautyPreset, to b: Scene3DBuilder, doc: ArchiDocument, quality: BeautyQuality, placeSun: Bool = true) {
        let look = preset.look
        if placeSun { b.setSun(direction: look.sunDirection(northAngle: doc.info.northAngle)) }
        let f = b.sunNode.worldFront
        let sun = simd_normalize(SIMD3<Float>(Float(-f.x), Float(-f.y), Float(-f.z)))
        if let l = b.sunNode.light {
            l.color = color(look.sunColor)
            l.intensity = CGFloat(look.sunIntensity)
            l.castsShadow = true
            l.shadowMode = .deferred
            l.shadowMapSize = CGSize(width: quality.shadowMap, height: quality.shadowMap)
            l.shadowSampleCount = quality.shadowSamples
            l.shadowRadius = CGFloat(look.shadowRadius)
            l.shadowCascadeCount = quality.cascades
            l.shadowCascadeSplittingFactor = 0.25
            l.shadowColor = NSColor(white: 0, alpha: CGFloat(look.shadowAlpha))
            l.shadowBias = 1.2
            let s = b.worldSphere
            l.maximumShadowDistance = s.radius * (quality.isFinal ? 10 : 8)
        }
        b.ambientNode.light?.intensity = CGFloat(look.ambient)
        b.ambientNode.light?.color = color(SIMD3<Float>(0.8, 0.85, 1.0))
        applySky(preset, to: b, quality: quality, sun: sun)
        if b.beautyExplicit {
            if !FogSettings.load(doc).on && WeatherSettings.load(doc).fogDistance == nil { applyFog(preset, to: b, sun: sun) }
            applyArtificial(preset, to: b)
        }
    }

    private static let baseIntensity = NSMapTable<SCNLight, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    /// Scales placed lights and fixtures for the look (subtle by day, full at night); idempotent.
    static func applyArtificial(_ preset: BeautyPreset, to b: Scene3DBuilder) {
        for n in b.lightNodes {
            guard let l = n.light else { continue }
            let base: CGFloat
            if let v = baseIntensity.object(forKey: l) { base = CGFloat(v.doubleValue) } else { base = l.intensity; baseIntensity.setObject(NSNumber(value: Double(base)), forKey: l) }
            l.intensity = base * CGFloat(preset.look.artificial)
        }
    }

    /// HDR sky of the look as image-based lighting and background (sun direction from the sun light unless given).
    static func applySky(_ preset: BeautyPreset, to b: Scene3DBuilder, quality: BeautyQuality, sun: SIMD3<Float>? = nil) {
        let f = b.sunNode.worldFront
        let s = sun ?? simd_normalize(SIMD3<Float>(Float(-f.x), Float(-f.y), Float(-f.z)))
        b.scene.lightingEnvironment.contents = BeautySky.url(preset.look.sky, sun: s, width: 512)
        b.scene.lightingEnvironment.intensity = CGFloat(preset.look.envIntensity)
        b.scene.background.contents = BeautySky.url(preset.look.sky, sun: s, width: quality.skyWidth)
        b.scene.background.intensity = 1
    }

    /// Distance haze towards the horizon colour: fades the ground plane into the sky.
    static func applyFog(_ preset: BeautyPreset, to b: Scene3DBuilder, sun: SIMD3<Float>? = nil) {
        let f = b.sunNode.worldFront
        let s = sun ?? simd_normalize(SIMD3<Float>(Float(-f.x), Float(-f.y), Float(-f.z)))
        let r = b.worldSphere.radius
        let hc = BeautySky.horizonColor(preset.look.sky, sun: s)
        // Fog blends in the same linear HDR space as the sky: use the horizon radiance itself.
        b.scene.fogColor = color(hc)
        b.scene.fogStartDistance = max(40, r * 3)
        b.scene.fogEndDistance = max(450, r * 20)
        b.scene.fogDensityExponent = 1.6
    }

    /// Camera tone mapping, exposure, bloom, SSAO, grading and anti-aliasing helpers for the look.
    static func configure(_ c: SCNCamera, _ preset: BeautyPreset, quality: BeautyQuality) {
        let look = preset.look
        c.wantsHDR = true
        c.wantsExposureAdaptation = false
        c.exposureOffset = CGFloat(look.exposure)
        c.whitePoint = CGFloat(look.whitePoint)
        c.minimumExposure = -4; c.maximumExposure = 4
        c.bloomIntensity = CGFloat(look.bloom)
        c.bloomThreshold = CGFloat(look.bloomThreshold)
        var ss: CGFloat = 1
        if case .final(let k) = quality { ss = CGFloat(max(1, k)) }
        c.bloomBlurRadius = 10 * ss
        c.saturation = CGFloat(look.saturation)
        c.contrast = CGFloat(look.contrast)
        c.screenSpaceAmbientOcclusionIntensity = CGFloat(look.ao)
        c.screenSpaceAmbientOcclusionRadius = 0.35
        c.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        c.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        c.screenSpaceAmbientOcclusionBias = 0.03
        c.vignettingIntensity = 0.22
        c.vignettingPower = 0.55
        c.colorFringeStrength = quality.isFinal ? 0.15 : 0
        c.colorFringeIntensity = 0.4
    }

    /// Materials treated as tree foliage (leaf cut-outs); clipped hedges stay solid.
    static func isFoliage(_ name: String) -> Bool {
        let n = name.lowercased()
        return (n.contains("lea") || n.contains("foliage") || n.contains("crown") || n.contains("canopy tree")) && !n.contains("hedge") && !n.contains("lead")
    }

    /// Geometry shader: pushes the surface of leaf clusters in and out with a smooth 3D noise (model millimetres),
    /// so spheres read as irregular clumps of foliage.
    static let foliageLumps = """
    #pragma body
    float3 q = _geometry.position.xyz * 0.0042;
    float n = sin(q.x * 1.7 + sin(q.y * 2.3)) * sin(q.y * 1.9 + sin(q.z * 2.1)) * sin(q.z * 2.2 + sin(q.x * 1.3));
    float3 r = _geometry.position.xyz * 0.011;
    n += 0.5 * sin(r.x * 1.3 + sin(r.z * 1.7)) * sin(r.y * 1.1 + sin(r.x * 2.3)) * sin(r.z * 1.9 + sin(r.y * 1.5));
    _geometry.position.xyz += _geometry.normal * n * 140.0;
    """

    /// Surface shader: discards texels darker than the leaf gaps (luminance of the tinted albedo).
    static let foliageCutout = """
    #pragma body
    float lum = dot(_surface.diffuse.rgb, float3(0.3, 0.59, 0.11));
    if (lum < 0.075) { discard_fragment(); }
    """

    /// Photographic material tuning of the Realistic style: glass tint and reflections, metals, anisotropic textures,
    /// normal maps from albedo textures, glowing windows and lamps at night.
    static func enhance(_ m: SCNMaterial, material src: ArchiCore.Material, preset: BeautyPreset, doc: ArchiDocument, hasMaps: Bool) {
        let look = preset.look
        let t = min(max(src.transparency, 0), 0.95)
        for p in [m.diffuse, m.normal, m.roughness, m.metalness, m.ambientOcclusion] where p.contents != nil { p.maxAnisotropy = 16; p.mipFilter = .linear }
        if t > 0.3 {
            // Glazing: slightly green-grey tinted dielectric that mirrors the sky; interiors glow at dusk and night.
            let tint = src.color
            m.diffuse.contents = NSColor(srgbRed: CGFloat(tint.r) * 0.25 + 0.08, green: CGFloat(tint.g) * 0.25 + 0.1, blue: CGFloat(tint.b) * 0.25 + 0.11, alpha: 1)
            m.roughness.contents = NSNumber(value: 0.04)
            m.metalness.contents = NSNumber(value: 0.55)
            m.transparency = CGFloat(max(0.78, 1 - t))
            m.transparencyMode = .dualLayer
            m.isDoubleSided = true
            m.writesToDepthBuffer = true
            if look.windowGlow > 0 {
                m.emission.contents = NSColor(srgbRed: 1.0, green: 0.74, blue: 0.45, alpha: 1)
                m.emission.intensity = CGFloat(look.windowGlow)
                m.transparency = 1
            }
            return
        }
        if src.metalness > 0.5 {
            m.roughness.contents = NSNumber(value: max(0.28, min(src.roughness, 0.7)))
        }
        // Normal map derived from the albedo texture when none is given.
        if !hasMaps, m.normal.contents == nil, let tex = src.texture, let img = MaterialTextures.image(tex),
           let nm = BumpTextures.normalMap(texture: tex, image: img, strength: 0.6) {
            m.normal.contents = nm
            m.normal.wrapS = .repeat; m.normal.wrapT = .repeat
            m.normal.mipFilter = .linear; m.normal.maxAnisotropy = 16
            m.normal.contentsTransform = m.diffuse.contentsTransform
            m.normal.intensity = 0.8
        }
        // Tree foliage: the dark gaps of the leaf texture are cut out, so crowns of leaf clusters get ragged,
        // see-through silhouettes (and dappled shadows) instead of smooth balls.
        if isFoliage(src.name), m.diffuse.contents != nil {
            m.shaderModifiers = [.geometry: foliageLumps, .surface: foliageCutout]
            m.roughness.contents = NSNumber(value: 0.95)
            m.isDoubleSided = true
        }
        // Emissive lamps (MATEMIT): calmer by day, brighter at night.
        if Emissive.strength(src.name, doc: doc) > 0 { m.emission.intensity = CGFloat(Emissive.strength(src.name, doc: doc) * look.lampGlow) }
    }
}
