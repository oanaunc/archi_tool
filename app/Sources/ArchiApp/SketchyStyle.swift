// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import CoreImage
import ArchiCore

/// Sketchy / hand-drawn visual style (VIS-032) and non-photorealistic renders (VIS-080). Edges are drawn as two
/// slightly wavy strokes that overshoot the corners; the wobble is derived from the edge's coordinates, so the same
/// model always draws the same way (viewport, image export and renders agree).
enum SketchyStyle {
    static let paper = NSColor(srgbRed: 0.975, green: 0.965, blue: 0.94, alpha: 1)
    static let ink = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.19, alpha: 1)

    /// Deterministic pseudo-random value in −1…1 from a point and a salt.
    static func noise(_ p: Vec3, _ salt: Int) -> Double {
        var h: UInt64 = 1469598103934665603 &+ UInt64(bitPattern: Int64(salt))
        for v in [p.x, p.y, p.z] { h = (h ^ UInt64(bitPattern: Int64((v * 10).rounded()))) &* 1099511628211 }
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        return Double(h % 20001) / 10000 - 1
    }

    /// Strokes of one edge segment: two passes, overshooting the ends and bowing sideways, in model millimetres.
    static func strokes(_ a: Vec3, _ b: Vec3) -> [[Vec3]] {
        let d = b - a, len = d.length
        guard len > 1e-6 else { return [] }
        let u = d / len
        var side = u.cross(Vec3.unitZ)
        if side.length < 0.1 { side = u.cross(Vec3(1, 0, 0)) }
        side = side.normalized
        let up = u.cross(side).normalized
        let amp = min(25, max(2, len * 0.008))
        var out: [[Vec3]] = []
        for pass in 0..<2 {
            let over = min(60, len * 0.04) * (0.6 + 0.4 * abs(noise(a, pass * 7 + 1)))
            let s0 = a - u * over * (pass == 0 ? 1 : 0.5), s1 = b + u * over * (pass == 0 ? 0.5 : 1)
            let bow = side * (amp * noise(b, pass * 13 + 3)) + up * (amp * 0.5 * noise(a + b, pass * 17 + 5))
            let n = max(3, min(12, Int(len / 400)))
            out.append((0...n).map { i in
                let t = Double(i) / Double(n)
                let base = s0 + (s1 - s0) * t
                return base + bow * (4 * t * (1 - t)) + side * (amp * 0.15 * noise(base, pass))
            })
        }
        return out
    }

    static func edgeGeometry(_ g: MeshGroup) -> SCNGeometry? {
        var verts: [SCNVector3] = [], idx: [UInt32] = []
        for poly in g.edges where poly.count >= 2 {
            for k in 0..<(poly.count - 1) {
                for st in strokes(poly[k], poly[k + 1]) {
                    let base = UInt32(verts.count)
                    verts += st.map { SCNVector3($0.x, $0.y, $0.z) }
                    for i in 0..<(st.count - 1) { idx += [base + UInt32(i), base + UInt32(i + 1)] }
                }
            }
        }
        guard !idx.isEmpty else { return nil }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
    }
}

/// Non-photorealistic render styles (VIS-080).
enum NPRStyle: String, CaseIterable { case photo = "Photographic", sketch = "Sketch", watercolour = "Watercolour" }

@MainActor
extension RenderEngine {
    /// Sketch: the Sketchy style from the render camera. Watercolour: the photographic render softened, posterized
    /// into washes on paper, with the sketch lines on top.
    static func renderNPR(doc: ArchiDocument, settings s: RenderSettings, style: NPRStyle, camera override: SCNMatrix4? = nil) -> NSImage? {
        if style == .photo { return renderAdvanced(doc: doc, settings: s, camera: override) }
        guard let sketch = sketchImage(doc: doc, settings: s, camera: override) else { return nil }
        if style == .sketch { return sketch }
        var flat = s; flat.depthOfField = false
        guard let photo = renderAdvanced(doc: doc, settings: flat, camera: override),
              let pc = photo.cgImage(forProposedRect: nil, context: nil, hints: nil), let sc = sketch.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var img = CIImage(cgImage: pc)
        let extent = img.extent
        img = img.applyingFilter("CIMedianFilter")
        img = img.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(1.5, extent.width / 600)]).cropped(to: extent)
        img = img.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 7])
        img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.8, kCIInputBrightnessKey: 0.08, kCIInputContrastKey: 0.85])
        let paper = CIImage(color: CIColor(red: 0.975, green: 0.965, blue: 0.94)).cropped(to: extent)
        img = img.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: paper])
        img = CIImage(cgImage: sc).applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: img])
        guard let out = ci.createCGImage(img, from: extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    static func sketchImage(doc: ArchiDocument, settings s: RenderSettings, camera override: SCNMatrix4?) -> NSImage? {
        let (ref, cam) = makeScene(doc: doc, settings: s)
        if let t = override { cam.transform = t }
        let b = Scene3DBuilder()
        b.update(doc: doc, style: "Sketchy")
        b.groundNode.isHidden = true
        b.extrasRoot.isHidden = true
        let node = SCNNode()
        let c = SCNCamera()
        if let src = cam.camera { c.fieldOfView = src.fieldOfView; c.usesOrthographicProjection = src.usesOrthographicProjection; c.orthographicScale = src.orthographicScale }
        c.automaticallyAdjustsZRange = true
        node.camera = c
        node.transform = cam.worldTransform
        b.scene.rootNode.addChildNode(node)
        _ = ref
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene; r.pointOfView = node; r.autoenablesDefaultLighting = false
        return r.snapshot(atTime: 0, with: CGSize(width: min(max(s.width, 16), 7680), height: min(max(s.height, 16), 4320)), antialiasingMode: .multisampling4X)
    }
}
