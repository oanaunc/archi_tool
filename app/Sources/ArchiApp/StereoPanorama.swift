// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Omni-directional stereo 360° panoramas (VIS-048) for VR headsets and phone viewers: two equirectangular images
/// stacked over-under (left eye on top). Each vertical slice of longitudes is rendered from eyes offset sideways
/// by half the interpupillary distance, perpendicular to that slice's viewing direction, so the parallax is right
/// wherever the viewer looks; only the cube faces a slice needs are rendered.
@MainActor
extension RenderEngine {
    /// World-space (metres) sideways offset of an eye for a panorama longitude (radians, 0 = the view centre).
    static func odsOffset(longitude lon: Double, heading: Double, ipdMetres: Double, eye: Double) -> SCNVector3 {
        let ch = cos(heading), sh = sin(heading)
        let f0 = Vec3(sin(lon), 0, -cos(lon))
        let f = Vec3(f0.x * ch - f0.z * sh, 0, f0.x * sh + f0.z * ch)
        let right = Vec3(-f.z, 0, f.x)
        let k = eye * ipdMetres / 2
        return SCNVector3(right.x * k, 0, right.z * k)
    }

    static func stereoPanorama(doc: ArchiDocument, settings: RenderSettings, eye: Vec3, heading: Double = 0, width: Int, ipd: Double = 64, slices: Int = 24) -> CGImage? {
        let w = max(256, width - width % 2), h = w / 2
        let face = max(64, w / 4)
        let n = max(1, min(slices, 360))
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
        let ch = cos(heading), sh = sin(heading)
        func rot(_ v: Vec3) -> Vec3 { Vec3(v.x * ch - v.z * sh, v.y, v.x * sh + v.z * ch) }
        func unrot(_ v: Vec3) -> Vec3 { Vec3(v.x * ch + v.z * sh, v.y, -v.x * sh + v.z * ch) }
        let ipdM = ipd * doc.units.mm * 0.001
        var out = [UInt8](repeating: 0, count: w * h * 2 * 4)
        for (row, eyeSign) in [(0, -1.0), (1, 1.0)] {
            for k in 0..<n {
                let x0 = k * w / n, x1 = (k + 1) * w / n
                guard x1 > x0 else { continue }
                let lonC = ((Double(x0 + x1) / 2) / Double(w) - 0.5) * 2 * .pi
                let off = odsOffset(longitude: lonC, heading: heading, ipdMetres: ipdM, eye: eyeSign)
                let pos = SCNVector3(e.x + off.x, e.y, e.z + off.z)
                // Faces this slice samples (pixel directions are in the unrotated panorama frame).
                var needed = Set<Int>()
                for y in stride(from: 0, to: h, by: max(1, h / 64)) { for x in [x0, (x0 + x1) / 2, x1 - 1] {
                    needed.insert(Panorama.lookup(Panorama.direction(u: (Double(x) + 0.5) / Double(w), v: (Double(y) + 0.5) / Double(h))).face)
                } }
                needed.insert(Panorama.lookup(Panorama.direction(u: (Double(x0) + 0.5) / Double(w), v: 0.0005)).face)
                needed.insert(Panorama.lookup(Panorama.direction(u: (Double(x0) + 0.5) / Double(w), v: 0.9995)).face)
                var buffers = [[UInt8]](repeating: [], count: 6)
                for fi in needed.sorted() {
                    let f = Panorama.faces[fi]
                    let fr = rot(f.front), up = rot(f.up)
                    cam.position = pos
                    cam.look(at: SCNVector3(pos.x + CGFloat(fr.x), pos.y + CGFloat(fr.y), pos.z + CGFloat(fr.z)), up: SCNVector3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
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
                    buffers[fi] = px
                }
                for y in 0..<h {
                    for x in x0..<x1 {
                        let d = Panorama.direction(u: (Double(x) + 0.5) / Double(w), v: (Double(y) + 0.5) / Double(h))
                        let (fi, s, t) = Panorama.lookup(d)
                        let buf = buffers[fi]
                        guard !buf.isEmpty else { continue }
                        let px = min(face - 1, Int(s * Double(face))), py = min(face - 1, Int(t * Double(face)))
                        let src = (py * face + px) * 4, dst = ((row * h + y) * w + x) * 4
                        out[dst] = buf[src]; out[dst + 1] = buf[src + 1]; out[dst + 2] = buf[src + 2]; out[dst + 3] = 255
                    }
                }
            }
        }
        _ = unrot
        guard let prov = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: w, height: h * 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
