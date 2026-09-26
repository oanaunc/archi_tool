// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Render passes (VIS-075), render regions (VIS-072) and large renders up to 8K (VIS-074). Large frames and regions
/// are rendered in tiles: each tile narrows the camera's projection to its part of the frame (an off-centre frustum),
/// so the stitched image is identical to one big render and memory stays bounded.
enum RenderPass: String, CaseIterable {
    case beauty = "Beauty", alpha = "Alpha", depth = "Depth", normal = "Normal", materialID = "Material ID"
}

@MainActor
extension RenderEngine {
    static let maxSize = CGSize(width: 7680, height: 4320)
    static let tileSize = 2048

    /// Material → flat colour of the material ID pass (golden-ratio hues in material order).
    static func materialIDColors(_ doc: ArchiDocument) -> [(name: String, color: RGBA)] {
        var names = doc.materials.map(\.name)
        for g in MeshBuilder.build(doc: doc) where !names.contains(g.material) { names.append(g.material) }
        return names.enumerated().map { i, n in
            let c = NSColor(hue: CGFloat((Double(i) * 0.618034).truncatingRemainder(dividingBy: 1)), saturation: 0.75, brightness: 0.95, alpha: 1).usingColorSpace(.sRGB)!
            return (n, RGBA(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)))
        }
    }

    /// Replaces the scene's surfaces for a data pass (flat, unlit) and hides edges, lights, billboards and ground.
    static func applyPass(_ pass: RenderPass, builder b: Scene3DBuilder, doc: ArchiDocument, camera c: SCNCamera, near: CGFloat, far: CGFloat) {
        guard pass == .depth || pass == .normal || pass == .materialID else { return }
        let ids = Dictionary(materialIDColors(doc).map { ($0.name, $0.color) }, uniquingKeysWith: { a, _ in a })
        b.scene.background.contents = NSColor.black
        b.scene.lightingEnvironment.contents = nil
        b.scene.fogEndDistance = 0
        b.extrasRoot.isHidden = true
        b.sunNode.light?.castsShadow = false
        b.sunNode.isHidden = true; b.ambientNode.isHidden = true
        c.wantsHDR = false; c.bloomIntensity = 0; c.screenSpaceAmbientOcclusionIntensity = 0; c.vignettingIntensity = 0; c.wantsDepthOfField = false
        b.modelRoot.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            if n.name == "ground" || g.elements.first?.primitiveType != .triangles { n.isHidden = true; return }
            let key = n.parent?.name ?? ""
            _ = key
            g.materials = g.materials.map { old in
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.isDoubleSided = true
                switch pass {
                case .materialID:
                    let col = ids[old.name ?? ""] ?? RGBA(0.5, 0.5, 0.5)
                    m.diffuse.contents = NSColor(srgbRed: col.r, green: col.g, blue: col.b, alpha: 1)
                case .normal:
                    m.shaderModifiers = [.fragment: "_output.color = float4(normalize(_surface.normal) * 0.5 + 0.5, 1.0);"]
                default:
                    m.shaderModifiers = [.fragment: """
                    #pragma arguments
                    float nearD;
                    float farD;
                    #pragma body
                    float d = -_surface.position.z;
                    float v = 1.0 - clamp((d - nearD) / max(farD - nearD, 0.0001), 0.0, 1.0);
                    _output.color = float4(v, v, v, 1.0);
                    """]
                    m.setValue(NSNumber(value: Double(near)), forKey: "nearD")
                    m.setValue(NSNumber(value: Double(far)), forKey: "farD")
                }
                return m
            }
        }
    }

    /// Renders a pass of the frame (or a region of it, as fractions with the origin top-left) at any size up to 8K.
    static func renderAdvanced(doc: ArchiDocument, settings s0: RenderSettings, pass: RenderPass = .beauty, region: CGRect? = nil,
                               tile: Int = 2048, camera override: SCNMatrix4? = nil) -> NSImage? {
        var s = s0
        s.width = min(max(s.width, 16), Int(maxSize.width)); s.height = min(max(s.height, 16), Int(maxSize.height))
        if pass == .alpha { s.background = .transparent }
        if pass != .beauty && pass != .alpha { s.antialias = false; s.depthOfField = false }
        let (b, cam) = makeScene(doc: doc, settings: s)
        if let t = override { cam.transform = t }
        guard var c = cam.camera, let device = MTLCreateSystemDefaultDevice() else { return nil }
        if pass == .depth || pass == .normal || pass == .materialID {
            // Data passes: a plain camera without HDR, white balance or other post effects.
            let fresh = SCNCamera()
            fresh.fieldOfView = c.fieldOfView; fresh.projectionDirection = c.projectionDirection
            fresh.usesOrthographicProjection = c.usesOrthographicProjection; fresh.orthographicScale = c.orthographicScale
            cam.camera = fresh; c = fresh
        }
        // Fixed depth range (tiles must share it).
        let sphere = b.worldSphere
        let dist = Viewport3DController.length(Viewport3DController.sub(cam.worldPosition, sphere.center))
        c.automaticallyAdjustsZRange = false
        c.zNear = Double(max(0.02, (dist - sphere.radius * 1.5) * 0.5))
        c.zFar = Double(dist + sphere.radius * 3 + 50)
        // Shadow maps fitted to the whole model (not to the frustum) so every tile casts the same shadows; no vignetting.
        if let sun = b.sunNode.light {
            sun.automaticallyAdjustsShadowProjection = false
            sun.orthographicScale = sphere.radius * 1.3
            sun.maximumShadowDistance = sphere.radius * 8
            sun.shadowCascadeCount = 1
        }
        c.vignettingIntensity = 0
        applyPass(pass, builder: b, doc: doc, camera: c, near: max(0.01, dist - sphere.radius), far: dist + sphere.radius)
        let W = s.width, H = s.height
        let rgn = (region ?? CGRect(x: 0, y: 0, width: 1, height: 1)).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rgn.isEmpty else { return nil }
        let rx0 = Int((rgn.minX * CGFloat(W)).rounded()), ry0 = Int((rgn.minY * CGFloat(H)).rounded())
        let rw = max(1, Int((rgn.maxX * CGFloat(W)).rounded()) - rx0), rh = max(1, Int((rgn.maxY * CGFloat(H)).rounded()) - ry0)
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        r.isJitteringEnabled = s.antialias
        let aa: SCNAntialiasingMode = s.antialias ? .multisampling4X : .none
        let tiled = region != nil || W > tile || H > tile
        var image: NSImage
        if !tiled {
            image = r.snapshot(atTime: 0, with: CGSize(width: W, height: H), antialiasingMode: aa)
        } else {
            c.vignettingIntensity = 0   // per-tile vignetting would show seams
            c.projectionDirection = .vertical
            let P = c.projectionTransform(withViewportSize: CGSize(width: W, height: H))
            guard let ctx = CGContext(data: nil, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            var ty = ry0
            while ty < ry0 + rh {
                let th = min(tile, ry0 + rh - ty)
                var tx = rx0
                while tx < rx0 + rw {
                    let tw = min(tile, rx0 + rw - tx)
                    let x0 = Double(tx) / Double(W) * 2 - 1, x1 = Double(tx + tw) / Double(W) * 2 - 1
                    let yTop = 1 - Double(ty) / Double(H) * 2, yBot = 1 - Double(ty + th) / Double(H) * 2
                    var M = SCNMatrix4Identity
                    M.m11 = CGFloat(2 / (x1 - x0)); M.m41 = CGFloat(-(x1 + x0) / (x1 - x0))
                    M.m22 = CGFloat(2 / (yTop - yBot)); M.m42 = CGFloat(-(yTop + yBot) / (yTop - yBot))
                    c.projectionTransform = SCNMatrix4Mult(P, M)
                    let img = r.snapshot(atTime: 0, with: CGSize(width: tw, height: th), antialiasingMode: aa)
                    if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        ctx.draw(cg, in: CGRect(x: tx - rx0, y: rh - (ty - ry0) - th, width: tw, height: th))
                    }
                    tx += tw
                }
                ty += th
            }
            guard let cg = ctx.makeImage() else { return nil }
            image = NSImage(cgImage: cg, size: NSSize(width: rw, height: rh))
        }
        if pass == .alpha { return alphaMask(image) }
        return image
    }

    /// White where the model covers the background, black elsewhere (from the alpha channel).
    static func alphaMask(_ img: NSImage) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) { let a = p[i * 4 + 3]; p[i * 4] = a; p[i * 4 + 1] = a; p[i * 4 + 2] = a; p[i * 4 + 3] = 255 }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    /// RGBA bytes of an image (tests and tools).
    static func pixels(_ img: NSImage) -> (w: Int, h: Int, rgba: [UInt8])? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, buf)
    }
}
