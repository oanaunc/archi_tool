// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import AVFoundation
import ArchiCore

/// Video and panorama output of the renderer: walkthrough along saved cameras, sun-study time-lapse, 360° panorama.
@MainActor
extension RenderEngine {
    /// Writes `frames` rendered frames as an H.264 MP4. `setup(i, builder, camera)` positions the scene for frame i.
    static func writeVideo(doc: ArchiDocument, settings: RenderSettings, frames: Int, fps: Int, to url: URL,
                           setup: (Int, Scene3DBuilder, SCNNode) -> Void, caption: ((Int) -> String?)? = nil, progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let w = max(2, settings.width - settings.width % 2), h = max(2, settings.height - settings.height % 2)
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
        r.scene = b.scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        let n = max(1, frames)
        for i in 0..<n {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            setup(i, b, cam)
            let img = r.snapshot(atTime: Double(i) / Double(fps), with: CGSize(width: w, height: h), antialiasingMode: settings.antialias ? .multisampling4X : .none)
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
                if let text = caption?(i), !text.isEmpty { VideoCaption.draw(text, in: ctx, width: w, height: h) }
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            progress(Double(i + 1) / Double(n))
            await Task.yield()
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    /// Places a SceneKit camera node at a model-space camera.
    static func place(_ cam: SCNNode, at c: Camera) {
        cam.position = Scene3DBuilder.world(c.eye)
        cam.look(at: Scene3DBuilder.world(c.target), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        cam.camera?.fieldOfView = CGFloat(max(10, min(120, c.fov)))
        cam.camera?.usesOrthographicProjection = false
    }

    /// Walkthrough along a smooth path through the key cameras (VIS-041 / VIS-046).
    static func walkthrough(doc: ArchiDocument, settings: RenderSettings, cameras: [Camera], seconds: Double, fps: Int = 30, to url: URL,
                            progress: @escaping (Double) -> Void) async throws {
        guard cameras.count >= 2 else { throw ExportError(errorDescription: "A walkthrough needs at least two saved cameras (SAVECAMERA).") }
        let frames = max(2, Int(seconds * Double(fps)))
        try await writeVideo(doc: doc, settings: settings, frames: frames, fps: fps, to: url, setup: { i, _, cam in
            if let c = CameraPath.sample(cameras, t: Double(i) / Double(frames - 1)) { place(cam, at: c) }
        }, progress: progress)
    }

    /// Sun-study time-lapse from `fromHour` to `toHour` on one day, from the given (or current) camera (VIS-043).
    static func sunStudy(doc: ArchiDocument, settings: RenderSettings, dayOfYear: Int, fromHour: Double, toHour: Double, seconds: Double,
                         camera: Camera?, fps: Int = 30, to url: URL, progress: @escaping (Double) -> Void) async throws {
        guard toHour > fromHour else { throw ExportError(errorDescription: "The end hour must be after the start hour.") }
        let frames = max(2, Int(seconds * Double(fps)))
        let tz = (doc.info.longitude / 15).rounded()
        try await writeVideo(doc: doc, settings: settings, frames: frames, fps: fps, to: url, setup: { i, b, cam in
            if i == 0, let c = camera { place(cam, at: c) }
            let hour = fromHour + (toHour - fromHour) * Double(i) / Double(frames - 1)
            let s = SunPosition.compute(dayOfYear: dayOfYear, localHour: hour, latitude: doc.info.latitude, longitude: doc.info.longitude, utcOffsetHours: tz)
            b.setSun(direction: SunPosition.direction(altitude: s.altitude, azimuth: s.azimuth, northAngleDegrees: doc.info.northAngle))
            b.sunNode.light?.intensity = s.altitude <= 0 ? 0 : CGFloat(1800 * min(1, sin(s.altitude) * 2.2 + 0.1))
            b.sunNode.light?.color = s.altitude < 0.25 ? NSColor(srgbRed: 1, green: 0.78, blue: 0.55, alpha: 1) : NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
            b.ambientNode.light?.intensity = s.altitude <= 0 ? 90 : 260
        }, progress: progress)
    }

    /// 360° equirectangular panorama (2:1) seen from a model-space eye point: six 90° cube faces resampled (VIS-047).
    static func panorama(doc: ArchiDocument, settings: RenderSettings, eye: Vec3, heading: Double = 0, width: Int) -> CGImage? {
        let w = max(256, width - width % 2), h = w / 2
        let face = max(128, w / 4)
        var s2 = settings; s2.width = face; s2.height = face; s2.depthOfField = false
        let (b, cam) = makeScene(doc: doc, settings: s2)
        cam.camera?.fieldOfView = 90
        cam.camera?.projectionDirection = .vertical
        cam.camera?.usesOrthographicProjection = false
        cam.camera?.vignettingIntensity = 0
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        let e = Scene3DBuilder.world(eye)
        // Heading rotates the panorama about the vertical so its centre looks along the chosen plan direction.
        let ch = cos(heading), sh = sin(heading)
        func rot(_ v: Vec3) -> Vec3 { Vec3(v.x * ch - v.z * sh, v.y, v.x * sh + v.z * ch) }
        var buffers: [[UInt8]] = []
        for f in Panorama.faces {
            let fr = rot(f.front), up = rot(f.up)
            cam.position = e
            cam.look(at: SCNVector3(e.x + CGFloat(fr.x), e.y + CGFloat(fr.y), e.z + CGFloat(fr.z)), up: SCNVector3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
            let img = r.snapshot(atTime: 0, with: CGSize(width: face, height: face), antialiasingMode: .multisampling4X)
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            var px = [UInt8](repeating: 0, count: face * face * 4)
            px.withUnsafeMutableBytes { p in
                if let ctx = CGContext(data: p.baseAddress, width: face, height: face, bitsPerComponent: 8, bytesPerRow: face * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: face, height: face))
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: face, height: face))
                }
            }
            buffers.append(px)
        }
        let out = Panorama.equirect(faces: buffers, faceSize: face, width: w, height: h)
        let data = Data(out) as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Writes a CGImage as PNG or JPEG (by extension).
    static func write(_ img: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: img)
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        guard let data = jpeg ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) : rep.representation(using: .png, properties: [:]) else {
            throw ExportError(errorDescription: "Image encoding failed.")
        }
        try data.write(to: url, options: .atomic)
    }
}

/// Default panorama eye point: the model centre at eye height (1.6 m) above the lowest level.
enum PanoramaDefaults {
    static func eye(_ doc: ArchiDocument) -> Vec3 {
        var b = BBox3.empty
        for g in MeshBuilder.build(doc: doc) { for p in g.mesh.positions { b.add(p) } }
        let base = doc.levels.map(\.elevation).min() ?? 0
        if b.isEmpty { return Vec3(0, 0, base + 1600) }
        return Vec3(b.center.x, b.center.y, base + 1600 * (doc.units.mm > 0 ? 1 / doc.units.mm : 1))
    }
}

/// Normal maps derived from texture luminance (cached per texture and strength).
@MainActor
enum BumpTextures {
    private static var cache: [String: NSImage] = [:]
    static func normalMap(texture: String, image: NSImage, strength: Double) -> NSImage? {
        let key = texture + "|" + fmt(strength, 2)
        if let i = cache[key] { return i }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Work at up to 512 px: enough detail for a bump, fast to filter.
        let scale = min(1, 512 / Double(max(cg.width, cg.height)))
        let w = max(4, Int(Double(cg.width) * scale)), h = max(4, Int(Double(cg.height) * scale))
        var gray = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = gray.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let px = BumpMap.normals(height: gray.map { Double($0) / 255 }, width: w, height: h, strength: strength * 4)
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let out = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let img = NSImage(cgImage: out, size: NSSize(width: w, height: h))
        cache[key] = img
        return img
    }
}

/// Physical sky environment images (cached per sun direction).
@MainActor
enum PhysicalSky {
    private static var cache: [String: NSImage] = [:]
    /// `sunModel`: direction towards the sun in model coordinates (X east, Y north, Z up).
    static func image(sun sunModel: Vec3) -> NSImage? {
        let s = Vec3(sunModel.x, sunModel.z, -sunModel.y)   // model → SceneKit world (Y up)
        let key = [s.x, s.y, s.z].map { fmt($0, 2) }.joined(separator: ",")
        if let i = cache[key] { return i }
        let w = 1024, h = 512
        let px = SkyModel.equirect(sun: s, width: w, height: h)
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        if cache.count > 32 { cache.removeAll() }
        cache[key] = img
        return img
    }
}
