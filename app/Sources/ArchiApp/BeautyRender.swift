// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import UniformTypeIdentifiers
import ImageIO
import CoreImage
import ArchiCore

// MARK: - Offscreen photographic renderer

/// Final-quality offscreen renders: photographic preset, a saved camera (with architectural vertical correction),
/// 4× multisampling plus supersampling filtered down with high-quality resampling, written as PNG.
@MainActor
enum BeautyRenderer {
    /// Largest side of the supersampled frame.
    static let maxSupersampledSide = 12_288

    /// Supersampling factor that fits the size (requested factor, reduced so the frame stays within the limit).
    static func supersample(width: Int, height: Int, requested: Int) -> Int {
        var k = max(1, min(requested, 4))
        while k > 1 && max(width, height) * k > maxSupersampledSide { k -= 1 }
        return k
    }

    /// Snapshot at `supersample`× the size, then filtered down to width × height.
    static func snapshot(_ r: SCNRenderer, width: Int, height: Int, supersample: Int, antialias: Bool = true) -> NSImage {
        let k = self.supersample(width: width, height: height, requested: supersample)
        let big = r.snapshot(atTime: 0, with: CGSize(width: width * k, height: height * k), antialiasingMode: antialias ? .multisampling4X : .none)
        guard k > 1, let cg = big.cgImage(forProposedRect: nil, context: nil, hints: nil), let small = downsample(cg, width: width, height: height) else { return big }
        return NSImage(cgImage: small, size: NSSize(width: width, height: height))
    }

    /// White balance applied to the finished frame (SceneKit's camera white balance tints every frame orange on
    /// current macOS, so it is never enabled): `kelvin` is the light the camera is balanced for (6500 = neutral).
    static func whiteBalance(_ img: NSImage, kelvin: Double) -> NSImage {
        guard abs(kelvin - 6500) > 50, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let f = CIFilter(name: "CITemperatureAndTint") else { return img }
        f.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        f.setValue(CIVector(x: CGFloat(kelvin), y: 0), forKey: "inputNeutral")
        f.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        guard let out = f.outputImage, let res = CIContext().createCGImage(out, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)) else { return img }
        return NSImage(cgImage: res, size: img.size)
    }

    /// High-quality box/Lanczos reduction of a CGImage.
    static func downsample(_ cg: CGImage, width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Saved camera of the drawing by name (case-insensitive).
    static func namedCamera(_ name: String, doc: ArchiDocument) -> Camera? {
        doc.namedViews.first { $0.camera != nil && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.camera
    }

    /// Lens-shift projection keeping verticals vertical (two-point perspective) for near-level views; nil when the
    /// camera pitches more than `maxPitch` degrees (aerials keep their natural perspective).
    static func shiftProjection(camera c: Camera, aspect: Double, maxPitch: Double = 20, near: Double = 0.1, far: Double = 4000) -> (eye: Vec3, target: Vec3, projection: SCNMatrix4)? {
        let d = c.target - c.eye
        let horiz = hypot(d.x, d.y)
        guard horiz > 1, !c.orthographic else { return nil }
        let pitch = atan2(d.z, horiz)
        guard abs(pitch) * 180 / .pi <= maxPitch else { return nil }
        let fov = max(10, min(120, c.fov)) * .pi / 180
        let f = 1 / tan(fov / 2)
        // Where the original target lands on the level camera's image (NDC y), shifted back to the centre.
        let shift = tan(pitch) * f
        var m = SCNMatrix4Identity
        m.m11 = CGFloat(f / max(aspect, 1e-6)); m.m22 = CGFloat(f)
        m.m33 = CGFloat((far + near) / (near - far)); m.m34 = -1
        m.m43 = CGFloat(2 * far * near / (near - far)); m.m44 = 0
        m.m32 = CGFloat(shift)
        let levelTarget = Vec3(c.target.x, c.target.y, c.eye.z)
        return (c.eye, levelTarget, m)
    }

    /// Places the render camera on a saved camera.
    static func place(_ node: SCNNode, camera c: Camera, aspect: Double, verticalCorrection: Bool) {
        let cam = node.camera
        cam?.usesOrthographicProjection = c.orthographic
        cam?.fieldOfView = CGFloat(max(10, min(120, c.fov)))
        if verticalCorrection, let s = shiftProjection(camera: c, aspect: aspect) {
            node.position = Scene3DBuilder.world(s.eye)
            node.look(at: Scene3DBuilder.world(s.target), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            cam?.projectionTransform = s.projection
        } else {
            node.position = Scene3DBuilder.world(c.eye)
            node.look(at: Scene3DBuilder.world(c.target), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            if c.orthographic { cam?.orthographicScale = (c.target - c.eye).length * 0.00045 }
        }
    }

    struct Options {
        var preset: BeautyPreset = .daylight
        var camera: Camera?
        var width = 1920
        var height = 1080
        var supersample = 2
        var depthOfField = false
        var verticalCorrection = true
    }

    /// Renders the document with a photographic preset. Returns nil without Metal.
    static func render(doc: ArchiDocument, options o: Options) -> NSImage? {
        var s = RenderSettings()
        s.width = o.width; s.height = o.height
        s.beauty = o.preset
        s.supersample = supersample(width: o.width, height: o.height, requested: o.supersample)
        s.shadowQuality = .ultra
        s.antialias = true
        s.depthOfField = o.depthOfField
        let (b, cam) = RenderEngine.makeScene(doc: doc, settings: s)
        if let c = o.camera {
            place(cam, camera: c, aspect: Double(o.width) / Double(max(o.height, 1)), verticalCorrection: o.verticalCorrection)
            if o.depthOfField { cam.camera?.focusDistance = CGFloat((c.target - c.eye).length * 0.001) }
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene
        r.pointOfView = cam
        r.autoenablesDefaultLighting = false
        r.isJitteringEnabled = true
        return snapshot(r, width: o.width, height: o.height, supersample: s.supersample)
    }

    static func pngData(_ img: NSImage) -> Data? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        return rep.representation(using: .png, properties: [:])
    }

    /// Renders and writes a PNG (folders are created). Returns the pixel size written.
    @discardableResult
    static func renderPNG(doc: ArchiDocument, options: Options, to url: URL) throws -> (width: Int, height: Int) {
        guard let img = render(doc: doc, options: options) else { throw CommandError.invalid("Rendering needs Metal, which is not available.") }
        guard let data = pngData(img) else { throw CommandError.invalid("Could not encode the PNG.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        let rep = NSBitmapImageRep(data: data)
        return (rep?.pixelsWide ?? options.width, rep?.pixelsHigh ?? options.height)
    }

    /// Splits "Front 1920 1080 out.png" into the camera (longest leading run of words naming a saved camera, or
    /// Current) and the remaining tokens.
    static func splitCameraAnswer(_ answer: String, cameras: [String]) -> (camera: String, rest: [String]) {
        let words = answer.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return ("Current", []) }
        let names = cameras + ["Current"]
        for k in stride(from: words.count, through: 1, by: -1) {
            let cand = words[0..<k].joined(separator: " ")
            if let n = names.first(where: { $0.caseInsensitiveCompare(cand) == .orderedSame }) { return (n, Array(words[k...])) }
        }
        return (words[0], Array(words.dropFirst()))
    }

    /// Resolves a command-line path: `~`, absolute, or relative to the drawing folder (else the home folder).
    static func resolve(_ path: String, base: URL?) -> URL {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.count >= 2, (p.hasPrefix("\"") && p.hasSuffix("\"")) || (p.hasPrefix("'") && p.hasSuffix("'")) { p = String(p.dropFirst().dropLast()) }
        p = (p as NSString).expandingTildeInPath
        if !p.lowercased().hasSuffix(".png") { p += ".png" }
        if p.hasPrefix("/") { return URL(fileURLWithPath: p) }
        return (base ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(p)
    }
}

// MARK: - Commands

@MainActor
enum BeautyCommands {
    static var all: [CommandDef] {
        [
            CommandDef("RENDERPRESET", aliases: ["LIGHTINGPRESET", "BEAUTYPRESET", "PHOTOLOOK"], category: "View",
                       summary: "Photographic lighting preset of the Realistic view and renders: Daylight, Golden hour, Overcast or Night (glowing windows); Off returns to the default look.") { ed in
                let cur = BeautyPreset.current(ed.doc)?.keyword ?? "Daylight"
                guard let k = try await ed.getKeyword("Lighting preset [Daylight/Goldenhour/Overcast/Night/Off]", BeautyPreset.keywords + ["Off"], defaultValue: cur) else { return }
                if k == "Off" {
                    ed.doc.variables[BeautyPreset.variable] = nil
                    ed.print("Photographic preset off: the Realistic view uses the default daylight look.")
                } else {
                    guard let p = BeautyPreset.named(k) else { throw CommandError.invalid("Unknown preset \(k).") }
                    ed.doc.setVariable(BeautyPreset.variable, p.rawValue)
                    let l = p.look
                    ed.print("Lighting preset \(p.rawValue): sun \(fmt(l.sunAltitude, 0))° high from \(fmt(l.sunAzimuth, 0))°, exposure \(fmt(l.exposure, 1)) EV\(l.windowGlow > 0 ? ", lit windows" : "").")
                }
                if let m = AppCommands.model(ed), m.viewStyle != "Realistic" { m.viewStyle = "Realistic" }
            },
            CommandDef("RENDERSAVE", aliases: ["RENDERPNG", "RSAVE"], category: "Output",
                       summary: "Renders offscreen to a PNG without the render window: RENDERSAVE <preset> <camera|Current> <width> <height> <path> (4× MSAA + supersampling, vertical correction for eye-level cameras).", modifies: false) { ed in
                let cur = BeautyPreset.current(ed.doc)?.keyword ?? "Daylight"
                guard let k = try await ed.getKeyword("Preset [Daylight/Goldenhour/Overcast/Night]", BeautyPreset.keywords, defaultValue: cur), let preset = BeautyPreset.named(k) else { return }
                let cams = ed.doc.namedViews.filter { $0.camera != nil }.map(\.name)
                // A string answer takes the rest of the line: "Front 1920 1080 out.png" is split after the camera name.
                let answer = (try await ed.getString("Camera [\((cams + ["Current"]).joined(separator: "/"))]", defaultValue: "Current") ?? "Current")
                    .trimmingCharacters(in: .whitespaces)
                let parsed = BeautyRenderer.splitCameraAnswer(answer, cameras: cams)
                let camName = parsed.camera
                var rest = parsed.rest
                var camera: Camera?
                if camName.caseInsensitiveCompare("Current") != .orderedSame {
                    guard let c = BeautyRenderer.namedCamera(camName, doc: ed.doc) else {
                        throw CommandError.invalid("No saved camera named \(camName). Saved cameras: \(cams.isEmpty ? "none (SAVECAMERA)" : cams.joined(separator: ", ")).")
                    }
                    camera = c
                }
                func nextInt(_ prompt: String, _ def: Int) async throws -> Int {
                    if !rest.isEmpty { let t = rest.removeFirst(); guard let v = Int(t) else { throw CommandError.invalid("\(t) is not a whole number of pixels.") }; return v }
                    return try await ed.getInteger(prompt, defaultValue: def) ?? def
                }
                let w = try await nextInt("Width in pixels", 1920)
                let h = try await nextInt("Height in pixels", 1080)
                guard w >= 16, h >= 16, w <= Int(RenderEngine.maxSize.width), h <= Int(RenderEngine.maxSize.height) else {
                    throw CommandError.invalid("Use a size from 16×16 to \(Int(RenderEngine.maxSize.width))×\(Int(RenderEngine.maxSize.height)).")
                }
                let base = ed.fileURL?.deletingPathExtension().lastPathComponent ?? "Render"
                let defPath = "\(base) \(preset.rawValue) \(camName).png"
                let path: String
                if !rest.isEmpty { path = rest.joined(separator: " ") }
                else { guard let p = try await ed.getString("PNG file", defaultValue: defPath), !p.isEmpty else { return }; path = p }
                let url = BeautyRenderer.resolve(path, base: ed.fileURL?.deletingLastPathComponent())
                if let dir = ed.fileURL?.deletingLastPathComponent() { MaterialTextures.documentFolder = MaterialTextures.documentFolder ?? dir }
                let t0 = Date()
                var o = BeautyRenderer.Options()
                o.preset = preset; o.camera = camera; o.width = w; o.height = h
                o.supersample = w * h <= 1920 * 1080 ? 3 : 2
                let size = try BeautyRenderer.renderPNG(doc: ed.doc, options: o, to: url)
                ed.print("Rendered \(preset.rawValue), \(camera == nil ? "current view" : camName), \(size.width)×\(size.height) (\(BeautyRenderer.supersample(width: w, height: h, requested: o.supersample))× supersampled) in \(fmt(Date().timeIntervalSince(t0), 1)) s → \(url.path)")
            },
        ]
    }
}

extension CommandCatalog {
    /// Ribbon/menu entries of the photographic render commands (menu bar Tools and the ribbon More menus).
    static var beautyMenus: [(String, [CmdItem])] {
        [("Photographic Render", [CmdItem(title: "Lighting Preset", symbol: "sun.haze", names: ["RENDERPRESET"]),
                                  CmdItem(title: "Golden Hour Look", symbol: "sunset", names: ["RENDERPRESET"], args: "Goldenhour"),
                                  CmdItem(title: "Night Look", symbol: "moon.stars", names: ["RENDERPRESET"], args: "Night"),
                                  CmdItem(title: "Render to PNG", symbol: "photo.on.rectangle.angled", names: ["RENDERSAVE"])])]
    }
}

// MARK: - Headless sample renders (--render-cedar)

/// `--render-cedar [folder]`: opens the bundled Cedar House sample (or `--render-doc <file>`), renders its saved cameras
/// with the Golden hour and Daylight presets (plus a Night and an Overcast view) to PNG files and exits.
/// `--render-size WxH` (default 1920x1080), `--render-supersample N` (default 2).
@MainActor
enum BeautyCLI {
    static let jobs: [(camera: String, preset: BeautyPreset)] = [
        ("Front", .goldenHour), ("Corner", .goldenHour), ("Aerial", .goldenHour),
        ("Front", .daylight), ("Corner", .daylight), ("Aerial", .daylight),
        ("Front", .night), ("Corner", .overcast),
    ]

    static func slug(_ s: String) -> String {
        s.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined().split(separator: "-").joined(separator: "-")
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-cedar") else { return }
        func value(_ flag: String) -> String? {
            guard let k = args.firstIndex(of: flag), k + 1 < args.count, !args[k + 1].hasPrefix("--") else { return nil }
            return args[k + 1]
        }
        let outArg = i + 1 < args.count && !args[i + 1].hasPrefix("--") ? args[i + 1] : "build/renders"
        let out = outArg.hasPrefix("/") ? URL(fileURLWithPath: outArg, isDirectory: true)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(outArg, isDirectory: true)
        let docURL = value("--render-doc").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? Bundle.main.url(forResource: "Cedar House", withExtension: "archi", subdirectory: "Samples")
        var w = 1920, h = 1080
        if let s = value("--render-size") { let p = s.lowercased().split(separator: "x").compactMap { Int($0) }; if p.count == 2 { w = p[0]; h = p[1] } }
        let ss = value("--render-supersample").flatMap(Int.init) ?? 2
        guard let docURL, let data = try? Data(contentsOf: docURL), let doc = try? ArchiFile.decode(data) else {
            print("render-cedar: cannot open the Cedar House sample"); exit(2)
        }
        MaterialTextures.documentFolder = docURL.deletingLastPathComponent()
        var failed = 0
        let t0 = Date()
        for j in jobs {
            guard let cam = BeautyRenderer.namedCamera(j.camera, doc: doc) else { print("missing camera \(j.camera)"); failed += 1; continue }
            var o = BeautyRenderer.Options()
            o.preset = j.preset; o.camera = cam; o.width = w; o.height = h; o.supersample = ss
            let url = out.appendingPathComponent("cedar-house-\(slug(j.camera))-\(slug(j.preset.rawValue)).png")
            let t = Date()
            do {
                let s = try BeautyRenderer.renderPNG(doc: doc, options: o, to: url)
                print("rendered \(url.path) \(s.width)x\(s.height) in \(fmt(Date().timeIntervalSince(t), 1)) s")
            } catch { print("FAILED \(url.lastPathComponent): \(error)"); failed += 1 }
        }
        print("render-cedar: \(jobs.count - failed)/\(jobs.count) images in \(fmt(Date().timeIntervalSince(t0), 1)) s")
        exit(failed == 0 ? 0 : 1)
    }
}
