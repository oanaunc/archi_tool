// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import simd
import ArchiCore

// MARK: - Progressive path tracer (VIS-070), denoiser (VIS-071), light mix (VIS-078)
//
// A CPU path tracer over the same triangle meshes as the viewport (`MeshBuilder`): binned-SAH BVH, GGX microfacet +
// Lambert BRDF with one-sample MIS, next-event estimation for the sun and placed lights, physically based dielectric
// glass with Fresnel reflection/refraction (VIS-065), PBR maps (albedo, normal, roughness, metallic, AO, bump; VIS-061),
// emissive materials, a procedural sky and an optional ground plane. Radiance is accumulated in separate light groups
// (sun, sky, artificial) so the mix can be changed after rendering. An edge-avoiding à-trous filter guided by albedo,
// normal and depth buffers denoises the result.

typealias PTVec = SIMD3<Float>

@inline(__always) func ptLum(_ c: PTVec) -> Float { c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722 }

/// Deterministic random numbers (PCG hash): the same seed gives the same image.
struct PTRandom {
    var state: UInt32
    init(seed: UInt32) { state = seed &* 747796405 &+ 2891336453; _ = next() }
    @inline(__always) mutating func next() -> Float {
        state = state &* 747796405 &+ 2891336453
        var w = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277803737
        w = (w >> 22) ^ w
        return Float(w >> 8) * (1.0 / 16777216.0)
    }
    static func hash(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
        var h = a &* 0x9E3779B1 ^ (b &+ 0x7F4A7C15) &* 0x85EBCA77 ^ (c &+ 0x165667B1) &* 0xC2B2AE3D
        h ^= h >> 15; h = h &* 0x2C1B3C6D; h ^= h >> 12; h = h &* 0x297A2D39; h ^= h >> 15
        return h
    }
}

/// A texture in linear floating point (colour maps are converted from sRGB, data maps are kept as stored).
final class PTTexture: @unchecked Sendable {
    let width: Int, height: Int
    let pixels: [PTVec]
    init(width: Int, height: Int, pixels: [PTVec]) { self.width = width; self.height = height; self.pixels = pixels }

    /// Bilinear sample with wrap-around (texture repeats).
    func sample(_ u: Float, _ v: Float) -> PTVec {
        guard width > 0, height > 0 else { return PTVec(repeating: 1) }
        let x = (u - u.rounded(.down)) * Float(width) - 0.5, y = (1 - (v - v.rounded(.down))) * Float(height) - 0.5
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Float(x0), fy = y - Float(y0)
        @inline(__always) func px(_ i: Int, _ j: Int) -> PTVec {
            let ii = ((i % width) + width) % width, jj = ((j % height) + height) % height
            return pixels[jj * width + ii]
        }
        let a = px(x0, y0) * (1 - fx) + px(x0 + 1, y0) * fx
        let b = px(x0, y0 + 1) * (1 - fx) + px(x0 + 1, y0 + 1) * fx
        return a * (1 - fy) + b * fy
    }

    static func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }

    static func from(cgImage: CGImage, maxSize: Int = 1024, linearize: Bool) -> PTTexture? {
        let s = min(1, Double(maxSize) / Double(max(cgImage.width, cgImage.height)))
        let w = max(1, Int(Double(cgImage.width) * s)), h = max(1, Int(Double(cgImage.height) * s))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var px = [PTVec](repeating: .zero, count: w * h)
        for i in 0..<(w * h) {
            var c = PTVec(Float(bytes[i * 4]), Float(bytes[i * 4 + 1]), Float(bytes[i * 4 + 2])) / 255
            if linearize { c = PTVec(srgbToLinear(c.x), srgbToLinear(c.y), srgbToLinear(c.z)) }
            px[i] = c
        }
        return PTTexture(width: w, height: h, pixels: px)
    }

    static func from(image: NSImage, maxSize: Int = 1024, linearize: Bool) -> PTTexture? {
        var r = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return nil }
        return from(cgImage: cg, maxSize: maxSize, linearize: linearize)
    }
}

struct PTMaterial {
    var albedo = PTVec(repeating: 0.8)
    var roughness: Float = 0.8
    var metalness: Float = 0
    var transmission: Float = 0
    var ior: Float = 1.5
    var emission = PTVec.zero
    var albedoMap = -1, roughnessMap = -1, metalMap = -1, normalMap = -1, aoMap = -1, bumpMap = -1
    var bumpStrength: Float = 0
    var normalStrength: Float = 1
    /// Texture repeats per UV unit (1000 / tile size in mm).
    var uvScale: Float = 1
    /// Animated water normals (VIS-083).
    var water = false
    /// Snow cover on up-facing faces (0…1, VIS-058) and wetness (rain).
    var snow: Float = 0
    var wet: Float = 0
}

struct PTTri { var p0: PTVec; var e1: PTVec; var e2: PTVec; var mat: Int32 }
struct PTShade { var n0: PTVec; var n1: PTVec; var n2: PTVec; var uv0: SIMD2<Float>; var uv1: SIMD2<Float>; var uv2: SIMD2<Float>; var tangent: PTVec; var bitangent: PTVec; var ng: PTVec }
struct PTNode { var bmin: PTVec; var bmax: PTVec; var start: Int32; var count: Int32; var right: Int32 }

struct PTPointLight { var position: PTVec; var intensity: PTVec; var direction: PTVec?; var cosOuter: Float; var cosInner: Float }

/// Camera: eye, target, Z up, vertical field of view in degrees (like the viewport's SceneKit camera).
struct PTCamera {
    var eye: PTVec; var target: PTVec; var fovDegrees: Float = 45; var orthographic = false
    init(eye: PTVec, target: PTVec, fovDegrees: Float = 45, orthographic: Bool = false) { self.eye = eye; self.target = target; self.fovDegrees = fovDegrees; self.orthographic = orthographic }
    init(_ c: Camera) { self.init(eye: PTVec(Float(c.eye.x), Float(c.eye.y), Float(c.eye.z)), target: PTVec(Float(c.target.x), Float(c.target.y), Float(c.target.z)), fovDegrees: Float(c.fov), orthographic: c.orthographic) }
    /// Ray through normalized image coordinates (0…1, y down).
    func ray(_ sx: Float, _ sy: Float, aspect: Float) -> (PTVec, PTVec) {
        let f = simd_normalize(target - eye)
        var up = PTVec(0, 0, 1)
        if abs(simd_dot(f, up)) > 0.999 { up = PTVec(0, 1, 0) }
        let r = simd_normalize(simd_cross(f, up)), u = simd_cross(r, f)
        let h = tanf(fovDegrees * .pi / 360)
        let px = (sx * 2 - 1) * h * aspect, py = (1 - sy * 2) * h
        if orthographic {
            let d = simd_length(target - eye)
            return (eye + r * (px * d) + u * (py * d), f)
        }
        return (eye, simd_normalize(f + r * px + u * py))
    }
}

/// Sky and sun model (radiance in lux-like units; the image is exposed automatically or by EV).
struct PTEnvironment {
    var zenith = PTVec(0.26, 0.45, 0.85) * 9000
    var horizon = PTVec(0.80, 0.87, 0.95) * 11000
    var ground = PTVec(0.35, 0.33, 0.30) * 3000
    var sunDirection = simd_normalize(PTVec(-0.45, -0.7, 0.75))
    var sunIrradiance = PTVec(1, 0.96, 0.9) * 90000
    /// Angular radius of the sun disc (radians): soft shadow penumbra.
    var sunRadius: Float = 0.0047

    func radiance(_ d: PTVec) -> PTVec {
        if d.z >= 0 {
            let t = powf(min(d.z, 1), 0.45)
            return horizon * (1 - t) + zenith * t
        }
        let t = min(-d.z * 4, 1)
        return horizon * 0.4 * (1 - t) + ground * t
    }

    static func uniform(_ v: Float) -> PTEnvironment {
        var e = PTEnvironment(); e.zenith = PTVec(repeating: v); e.horizon = PTVec(repeating: v); e.ground = PTVec(repeating: v); e.sunIrradiance = .zero
        return e
    }

    /// Preset skies matching the render dialog's environments, lit by the sun at an altitude/azimuth.
    static func preset(_ env: RenderSettings.Environment, sun: Vec3, altitude: Double) -> PTEnvironment {
        var e = PTEnvironment()
        e.sunDirection = simd_normalize(PTVec(Float(sun.x), Float(sun.y), Float(max(sun.z, 0.02))))
        let s = Float(max(0, sin(altitude)))
        let day = min(1, s * 3 + 0.05)
        switch env {
        case .overcast:
            e.zenith = PTVec(repeating: 0.8) * 9000 * day; e.horizon = PTVec(repeating: 0.9) * 9000 * day; e.ground = PTVec(repeating: 0.4) * 3000 * day
            e.sunIrradiance = PTVec(1, 1, 1) * 8000 * s
        case .sunset:
            e.zenith = PTVec(0.18, 0.22, 0.45) * 5000; e.horizon = PTVec(1.0, 0.62, 0.35) * 7000; e.ground = PTVec(0.25, 0.2, 0.18) * 2000
            e.sunIrradiance = PTVec(1, 0.7, 0.45) * 40000 * max(s, 0.1)
        case .studio:
            e.zenith = PTVec(repeating: 0.95) * 10000; e.horizon = PTVec(repeating: 0.8) * 10000; e.ground = PTVec(repeating: 0.55) * 6000
            e.sunIrradiance = PTVec(repeating: 1) * 30000
        case .night:
            e.zenith = PTVec(0.02, 0.03, 0.07) * 40; e.horizon = PTVec(0.08, 0.1, 0.16) * 40; e.ground = PTVec(repeating: 0.03) * 20
            e.sunIrradiance = .zero
        default:
            e.zenith = e.zenith * day; e.horizon = e.horizon * day; e.ground = e.ground * day
            let warm = PTVec(1, 0.72 + 0.26 * min(1, s * 2), 0.5 + 0.42 * min(1, s * 2))
            e.sunIrradiance = warm * 100000 * s
        }
        return e
    }
}

/// Scene data: triangles, shading data, BVH, materials, textures, lights, environment.
final class PTScene: @unchecked Sendable {
    var tris: [PTTri] = []
    var shade: [PTShade] = []
    var nodes: [PTNode] = []
    var materials: [PTMaterial] = [PTMaterial()]
    var textures: [PTTexture] = []
    var lights: [PTPointLight] = []
    var environment = PTEnvironment()
    /// Optional infinite ground plane (z = groundZ) using `groundMaterial`.
    var groundZ: Float? = nil
    var groundMaterial = 0
    /// Time (s) for animated water.
    var time: Float = 0
    var boundsMin = PTVec(repeating: .greatestFiniteMagnitude), boundsMax = PTVec(repeating: -.greatestFiniteMagnitude)

    var sceneSize: Float { tris.isEmpty ? 1000 : simd_length(boundsMax - boundsMin) }

    /// Adds a triangle mesh (model millimetres) with a material index.
    func add(_ mesh: Mesh, material: Int) {
        let p = mesh.positions.map { PTVec(Float($0.x), Float($0.y), Float($0.z)) }
        let hasN = mesh.normals.count == p.count, hasUV = mesh.uvs.count == p.count
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            i += 3
            guard a < p.count, b < p.count, c < p.count else { continue }
            let e1 = p[b] - p[a], e2 = p[c] - p[a]
            let cr = simd_cross(e1, e2)
            let area = simd_length(cr)
            guard area > 1e-9 else { continue }
            let ng = cr / area
            func n(_ k: Int) -> PTVec { hasN ? simd_normalize(PTVec(Float(mesh.normals[k].x), Float(mesh.normals[k].y), Float(mesh.normals[k].z))) : ng }
            func uv(_ k: Int) -> SIMD2<Float> { hasUV ? SIMD2(Float(mesh.uvs[k].x), Float(mesh.uvs[k].y)) : .zero }
            let uva = uv(a), uvb = uv(b), uvc = uv(c)
            let d1 = uvb - uva, d2 = uvc - uva
            let det = d1.x * d2.y - d1.y * d2.x
            var t = simd_normalize(e1), bt = simd_normalize(simd_cross(ng, t))
            if abs(det) > 1e-12 {
                let tt = (e1 * d2.y - e2 * d1.y) / det, bb = (e2 * d1.x - e1 * d2.x) / det
                if simd_length(tt) > 1e-12 && simd_length(bb) > 1e-12 { t = simd_normalize(tt); bt = simd_normalize(bb) }
            }
            tris.append(PTTri(p0: p[a], e1: e1, e2: e2, mat: Int32(material)))
            shade.append(PTShade(n0: n(a), n1: n(b), n2: n(c), uv0: uva, uv1: uvb, uv2: uvc, tangent: t, bitangent: bt, ng: ng))
            for q in [p[a], p[b], p[c]] { boundsMin = simd_min(boundsMin, q); boundsMax = simd_max(boundsMax, q) }
        }
    }

    // MARK: BVH (binned SAH)

    func buildBVH() {
        nodes.removeAll(keepingCapacity: true)
        guard !tris.isEmpty else { return }
        var idx = Array(0..<tris.count)
        let cent = tris.map { $0.p0 + ($0.e1 + $0.e2) / 3 }
        let lo = tris.map { simd_min($0.p0, simd_min($0.p0 + $0.e1, $0.p0 + $0.e2)) }
        let hi = tris.map { simd_max($0.p0, simd_max($0.p0 + $0.e1, $0.p0 + $0.e2)) }
        nodes.reserveCapacity(tris.count * 2)
        func area(_ a: PTVec, _ b: PTVec) -> Float { let d = simd_max(b - a, .zero); return d.x * d.y + d.y * d.z + d.z * d.x }
        func build(_ s: Int, _ e: Int) -> Int {
            var bmin = PTVec(repeating: .greatestFiniteMagnitude), bmax = -bmin, cmin = bmin, cmax = -bmin
            for k in s..<e { let t = idx[k]; bmin = simd_min(bmin, lo[t]); bmax = simd_max(bmax, hi[t]); cmin = simd_min(cmin, cent[t]); cmax = simd_max(cmax, cent[t]) }
            let me = nodes.count
            nodes.append(PTNode(bmin: bmin, bmax: bmax, start: Int32(s), count: Int32(e - s), right: -1))
            let n = e - s
            if n <= 4 { return me }
            let ext = cmax - cmin
            let axis = ext.x > ext.y ? (ext.x > ext.z ? 0 : 2) : (ext.y > ext.z ? 1 : 2)
            guard ext[axis] > 1e-6 else { return me }
            let bins = 12
            var bc = [Int](repeating: 0, count: bins)
            var blo = [PTVec](repeating: PTVec(repeating: .greatestFiniteMagnitude), count: bins), bhi = [PTVec](repeating: PTVec(repeating: -.greatestFiniteMagnitude), count: bins)
            func bin(_ t: Int) -> Int { min(bins - 1, Int(Float(bins) * (cent[t][axis] - cmin[axis]) / ext[axis])) }
            for k in s..<e { let t = idx[k]; let b = bin(t); bc[b] += 1; blo[b] = simd_min(blo[b], lo[t]); bhi[b] = simd_max(bhi[b], hi[t]) }
            var best = Float.greatestFiniteMagnitude, split = -1
            for sIdx in 1..<bins {
                var l0 = PTVec(repeating: .greatestFiniteMagnitude), l1 = -l0, r0 = l0, r1 = -l0, nl = 0, nr = 0
                for b in 0..<sIdx where bc[b] > 0 { l0 = simd_min(l0, blo[b]); l1 = simd_max(l1, bhi[b]); nl += bc[b] }
                for b in sIdx..<bins where bc[b] > 0 { r0 = simd_min(r0, blo[b]); r1 = simd_max(r1, bhi[b]); nr += bc[b] }
                guard nl > 0, nr > 0 else { continue }
                let cost = area(l0, l1) * Float(nl) + area(r0, r1) * Float(nr)
                if cost < best { best = cost; split = sIdx }
            }
            var mid: Int
            if split < 0 {
                mid = (s + e) / 2
                let sub = idx[s..<e].sorted { cent[$0][axis] < cent[$1][axis] }
                idx.replaceSubrange(s..<e, with: sub)
            } else {
                var i = s, j = e - 1
                while i <= j { if bin(idx[i]) < split { i += 1 } else { idx.swapAt(i, j); j -= 1 } }
                mid = i
                if mid == s || mid == e { mid = (s + e) / 2 }
            }
            _ = build(s, mid)
            let r = build(mid, e)
            nodes[me].count = 0
            nodes[me].right = Int32(r)
            return me
        }
        _ = build(0, tris.count)
        let order = idx
        tris = order.map { tris[$0] }
        shade = order.map { shade[$0] }
    }

    // MARK: Intersection

    struct Hit { var t: Float; var tri: Int; var u: Float; var v: Float }

    @inline(__always) private static func slab(_ o: PTVec, _ inv: PTVec, _ n: PTNode, _ tMax: Float) -> Bool {
        let t0 = (n.bmin - o) * inv, t1 = (n.bmax - o) * inv
        let tn = simd_min(t0, t1), tf = simd_max(t0, t1)
        let a = max(max(tn.x, tn.y), max(tn.z, 0)), b = min(min(tf.x, tf.y), min(tf.z, tMax))
        return a <= b
    }

    /// Closest hit (tri = -1 for the ground plane).
    func intersect(_ o: PTVec, _ d: PTVec, tMax: Float = .greatestFiniteMagnitude, stack: UnsafeMutablePointer<Int32>) -> Hit? {
        var best = Hit(t: tMax, tri: -2, u: 0, v: 0)
        if let gz = groundZ, abs(d.z) > 1e-8 {
            let t = (gz - o.z) / d.z
            if t > 1e-3 && t < best.t { best = Hit(t: t, tri: -1, u: 0, v: 0) }
        }
        if !nodes.isEmpty {
            let inv = PTVec(1 / (abs(d.x) < 1e-12 ? 1e-12 : d.x), 1 / (abs(d.y) < 1e-12 ? 1e-12 : d.y), 1 / (abs(d.z) < 1e-12 ? 1e-12 : d.z))
            nodes.withUnsafeBufferPointer { nb in
                tris.withUnsafeBufferPointer { tb in
                    var sp = 0
                    stack[sp] = 0; sp += 1
                    while sp > 0 {
                        sp -= 1
                        let ni = Int(stack[sp])
                        let n = nb[ni]
                        guard PTScene.slab(o, inv, n, best.t) else { continue }
                        if n.count > 0 {
                            for k in Int(n.start)..<Int(n.start + n.count) {
                                let tr = tb[k]
                                let p = simd_cross(d, tr.e2)
                                let det = simd_dot(tr.e1, p)
                                if abs(det) < 1e-12 { continue }
                                let id = 1 / det
                                let s = o - tr.p0
                                let u = simd_dot(s, p) * id
                                if u < 0 || u > 1 { continue }
                                let q = simd_cross(s, tr.e1)
                                let v = simd_dot(d, q) * id
                                if v < 0 || u + v > 1 { continue }
                                let t = simd_dot(tr.e2, q) * id
                                if t > 1e-3 && t < best.t { best = Hit(t: t, tri: k, u: u, v: v) }
                            }
                        } else if sp + 2 < 128 {
                            stack[sp] = n.right; sp += 1
                            stack[sp] = Int32(ni + 1); sp += 1
                        }
                    }
                }
            }
        }
        return best.tri == -2 ? nil : best
    }

    /// Light transmitted along a shadow ray (0 when an opaque surface blocks it; glass tints it).
    func transmittance(_ o: PTVec, _ d: PTVec, tMax: Float, stack: UnsafeMutablePointer<Int32>) -> PTVec {
        if let gz = groundZ, abs(d.z) > 1e-8 { let t = (gz - o.z) / d.z; if t > 1e-3 && t < tMax { return .zero } }
        guard !nodes.isEmpty else { return PTVec(repeating: 1) }
        var T = PTVec(repeating: 1)
        let inv = PTVec(1 / (abs(d.x) < 1e-12 ? 1e-12 : d.x), 1 / (abs(d.y) < 1e-12 ? 1e-12 : d.y), 1 / (abs(d.z) < 1e-12 ? 1e-12 : d.z))
        var blocked = false
        nodes.withUnsafeBufferPointer { nb in
            tris.withUnsafeBufferPointer { tb in
                var sp = 0
                stack[sp] = 0; sp += 1
                while sp > 0 && !blocked {
                    sp -= 1
                    let ni = Int(stack[sp])
                    let n = nb[ni]
                    guard PTScene.slab(o, inv, n, tMax) else { continue }
                    if n.count > 0 {
                        for k in Int(n.start)..<Int(n.start + n.count) {
                            let tr = tb[k]
                            let p = simd_cross(d, tr.e2)
                            let det = simd_dot(tr.e1, p)
                            if abs(det) < 1e-12 { continue }
                            let id = 1 / det
                            let s = o - tr.p0
                            let u = simd_dot(s, p) * id
                            if u < 0 || u > 1 { continue }
                            let q = simd_cross(s, tr.e1)
                            let v = simd_dot(d, q) * id
                            if v < 0 || u + v > 1 { continue }
                            let t = simd_dot(tr.e2, q) * id
                            if t > 1e-3 && t < tMax {
                                let m = materials[Int(tr.mat)]
                                if m.transmission < 0.01 { blocked = true; break }
                                let tint = PTVec(repeating: 1) * 0.5 + m.albedo * 0.5
                                T *= tint * sqrtf(m.transmission)
                            }
                        }
                    } else if sp + 2 < 128 {
                        stack[sp] = n.right; sp += 1
                        stack[sp] = Int32(ni + 1); sp += 1
                    }
                }
            }
        }
        return blocked ? .zero : T
    }
}

// MARK: - Shading helpers

enum PTShading {
    /// Schlick Fresnel for a dielectric interface (cosine of the incident angle, relative index of refraction).
    static func fresnelDielectric(cosI: Float, eta: Float) -> Float {
        let f0 = powf((eta - 1) / (eta + 1), 2)
        // Total internal reflection when leaving the denser medium.
        let sin2t = (1 / (eta * eta)) * max(0, 1 - cosI * cosI)
        if eta < 1 && sin2t > 1 { return 1 }
        let c = eta < 1 ? sqrtf(max(0, 1 - sin2t)) : cosI
        return f0 + (1 - f0) * powf(1 - c, 5)
    }

    /// Refracts direction `d` (unit, pointing at the surface) through normal `n` (facing against d) with ratio n1/n2.
    static func refract(_ d: PTVec, _ n: PTVec, _ eta: Float) -> PTVec? {
        let cosI = -simd_dot(d, n)
        let k = 1 - eta * eta * (1 - cosI * cosI)
        if k < 0 { return nil }
        return simd_normalize(d * eta + n * (eta * cosI - sqrtf(k)))
    }

    static func reflect(_ d: PTVec, _ n: PTVec) -> PTVec { d - n * (2 * simd_dot(d, n)) }

    static func basis(_ n: PTVec) -> (PTVec, PTVec) {
        let a = abs(n.x) > 0.9 ? PTVec(0, 1, 0) : PTVec(1, 0, 0)
        let t = simd_normalize(simd_cross(a, n))
        return (t, simd_cross(n, t))
    }

    static func cosineSample(_ n: PTVec, _ u1: Float, _ u2: Float) -> PTVec {
        let r = sqrtf(u1), phi = 2 * Float.pi * u2
        let (t, b) = basis(n)
        return simd_normalize(t * (r * cosf(phi)) + b * (r * sinf(phi)) + n * sqrtf(max(0, 1 - u1)))
    }

    /// GGX half-vector sample around `n`.
    static func ggxHalf(_ n: PTVec, alpha: Float, _ u1: Float, _ u2: Float) -> PTVec {
        let phi = 2 * Float.pi * u2
        let cosT = sqrtf((1 - u1) / (1 + (alpha * alpha - 1) * u1)), sinT = sqrtf(max(0, 1 - cosT * cosT))
        let (t, b) = basis(n)
        return simd_normalize(t * (sinT * cosf(phi)) + b * (sinT * sinf(phi)) + n * cosT)
    }

    static func ggxD(_ nh: Float, _ a: Float) -> Float {
        let a2 = a * a, d = nh * nh * (a2 - 1) + 1
        return a2 / (Float.pi * d * d)
    }

    /// GGX specular + Lambert diffuse BRDF (without the cosine term).
    static func brdf(n: PTVec, v: PTVec, l: PTVec, albedo: PTVec, roughness: Float, metalness: Float) -> PTVec {
        let nl = simd_dot(n, l), nv = simd_dot(n, v)
        guard nl > 0, nv > 0 else { return .zero }
        let h = simd_normalize(v + l)
        let nh = max(simd_dot(n, h), 0), vh = max(simd_dot(v, h), 0)
        let a = max(roughness * roughness, 0.0025)
        let D = ggxD(nh, a)
        let k = a / 2
        let G = (nv / (nv * (1 - k) + k)) * (nl / (nl * (1 - k) + k))
        let f0 = PTVec(repeating: 0.04) * (1 - metalness) + albedo * metalness
        let F = f0 + (PTVec(repeating: 1) - f0) * powf(1 - vh, 5)
        let spec = F * (D * G / (4 * nv * nl))
        let diff = (PTVec(repeating: 1) - F) * (1 - metalness) * albedo / Float.pi
        return diff + spec
    }

    /// Probability of sampling the specular lobe.
    static func specularProbability(nv: Float, albedo: PTVec, metalness: Float, roughness: Float) -> Float {
        let f0 = 0.04 * (1 - metalness) + ptLum(albedo) * metalness
        let f = f0 + (1 - f0) * powf(1 - max(nv, 0), 5)
        let d = (1 - metalness) * ptLum(albedo) * (1 - f)
        return min(0.9, max(0.1, f / max(f + d, 1e-4)))
    }

    /// Water surface normal: sum of travelling sine waves (VIS-083). Unit length, z up.
    static func waterNormal(x: Float, y: Float, time: Float, amplitude: Float = 0.08) -> PTVec {
        let waves: [(PTVec, Float, Float)] = [(PTVec(1, 0.3, 0), 1 / 900, 1.1), (PTVec(-0.4, 1, 0), 1 / 610, 1.7), (PTVec(0.7, -0.7, 0), 1 / 350, 2.3), (PTVec(0.2, 0.9, 0), 1 / 170, 3.1)]
        var gx: Float = 0, gy: Float = 0
        for (dir, k, w) in waves {
            let d = simd_normalize(dir)
            let ph = (d.x * x + d.y * y) * k * 2 * .pi + time * w
            let c = cosf(ph) * amplitude / Float(waves.count) * 2 * .pi
            gx += d.x * c; gy += d.y * c
        }
        return simd_normalize(PTVec(-gx, -gy, 1))
    }
}

// MARK: - Render session

struct PTSettings {
    var width = 640
    var height = 400
    var maxBounces = 6
    var camera = PTCamera(eye: PTVec(-8000, -10000, 6000), target: PTVec(0, 0, 1500))
    var seed: UInt32 = 1
    var clampIndirect: Float = 0 // 0 = off; otherwise max luminance of indirect samples (fireflies)
}

/// Light groups accumulated separately (VIS-078).
enum PTLightGroup: Int, CaseIterable { case sun = 0, sky = 1, artificial = 2
    var title: String { ["Sun", "Sky", "Artificial"][rawValue] }
}

/// Weights of the light groups after rendering.
struct PTLightMix: Equatable {
    var sun: Float = 1, sky: Float = 1, artificial: Float = 1
    var sunTint = PTVec(repeating: 1), skyTint = PTVec(repeating: 1), artificialTint = PTVec(repeating: 1)
    func weight(_ g: PTLightGroup) -> PTVec {
        switch g { case .sun: return sunTint * sun; case .sky: return skyTint * sky; case .artificial: return artificialTint * artificial }
    }
}

/// Progressive rendering: each pass adds one sample per pixel. Buffers: per light group radiance sums and first-hit
/// albedo, normal and depth (the denoiser's guides).
final class PTSession: @unchecked Sendable {
    let scene: PTScene
    let settings: PTSettings
    let width: Int, height: Int
    private(set) var groups: [[PTVec]]
    private(set) var albedo: [PTVec]
    private(set) var normal: [PTVec]
    private(set) var depth: [Float]
    private(set) var samples = 0

    init(scene: PTScene, settings: PTSettings) {
        self.scene = scene; self.settings = settings
        width = max(1, settings.width); height = max(1, settings.height)
        let n = width * height
        groups = Array(repeating: [PTVec](repeating: .zero, count: n), count: PTLightGroup.allCases.count)
        albedo = [PTVec](repeating: .zero, count: n); normal = [PTVec](repeating: .zero, count: n); depth = [Float](repeating: 0, count: n)
    }

    /// Adds one sample to every pixel (rows in parallel).
    func renderPass() {
        let w = width, h = height, pass = UInt32(samples)
        let aspect = Float(w) / Float(h)
        let g0 = UnsafeMutablePointer<PTVec>.allocate(capacity: w * h * 3)
        let aov = UnsafeMutablePointer<PTVec>.allocate(capacity: w * h * 2)
        let dep = UnsafeMutablePointer<Float>.allocate(capacity: w * h)
        defer { g0.deallocate(); aov.deallocate(); dep.deallocate() }
        DispatchQueue.concurrentPerform(iterations: h) { y in
            let stack = UnsafeMutablePointer<Int32>.allocate(capacity: 128)
            defer { stack.deallocate() }
            for x in 0..<w {
                var rng = PTRandom(seed: PTRandom.hash(UInt32(x), UInt32(y), pass &* 9781 &+ settings.seed))
                let (o, d) = settings.camera.ray((Float(x) + rng.next()) / Float(w), (Float(y) + rng.next()) / Float(h), aspect: aspect)
                let r = trace(o, d, &rng, stack)
                let i = y * w + x
                g0[i * 3] = r.sun; g0[i * 3 + 1] = r.sky; g0[i * 3 + 2] = r.artificial
                aov[i * 2] = r.albedo; aov[i * 2 + 1] = r.normal; dep[i] = r.depth
            }
        }
        let n = w * h
        for i in 0..<n {
            groups[0][i] += g0[i * 3]; groups[1][i] += g0[i * 3 + 1]; groups[2][i] += g0[i * 3 + 2]
            albedo[i] += aov[i * 2]; normal[i] += aov[i * 2 + 1]; depth[i] += dep[i]
        }
        samples += 1
    }

    struct PathResult { var sun = PTVec.zero, sky = PTVec.zero, artificial = PTVec.zero, albedo = PTVec.zero, normal = PTVec.zero, depth: Float = 0 }

    /// Surface properties at a hit (after textures and maps).
    private struct Surface { var n: PTVec; var ng: PTVec; var albedo: PTVec; var roughness: Float; var metalness: Float; var ao: Float; var mat: PTMaterial }

    private func surface(_ hit: PTScene.Hit, _ p: PTVec, _ d: PTVec) -> Surface {
        let sc = scene
        if hit.tri < 0 {
            let m = sc.materials[sc.groundMaterial]
            var alb = m.albedo
            if m.albedoMap >= 0 { alb *= sc.textures[m.albedoMap].sample(p.x / 1000 * m.uvScale, p.y / 1000 * m.uvScale) }
            return Surface(n: PTVec(0, 0, 1), ng: PTVec(0, 0, 1), albedo: alb, roughness: m.roughness, metalness: m.metalness, ao: 1, mat: m)
        }
        let s = sc.shade[hit.tri]
        let m = sc.materials[Int(sc.tris[hit.tri].mat)]
        let w = 1 - hit.u - hit.v
        var n = simd_normalize(s.n0 * w + s.n1 * hit.u + s.n2 * hit.v)
        let uv = (s.uv0 * w + s.uv1 * hit.u + s.uv2 * hit.v) * m.uvScale
        var alb = m.albedo, rough = m.roughness, metal = m.metalness, ao: Float = 1
        if m.albedoMap >= 0 { alb *= sc.textures[m.albedoMap].sample(uv.x, uv.y) }
        if m.roughnessMap >= 0 { rough *= sc.textures[m.roughnessMap].sample(uv.x, uv.y).x * 2; rough = min(max(rough, 0.02), 1) }
        if m.metalMap >= 0 { metal = min(1, metal + sc.textures[m.metalMap].sample(uv.x, uv.y).x) }
        if m.aoMap >= 0 { ao = sc.textures[m.aoMap].sample(uv.x, uv.y).x }
        if m.normalMap >= 0 {
            let t = sc.textures[m.normalMap].sample(uv.x, uv.y) * 2 - PTVec(repeating: 1)
            let tn = simd_normalize(PTVec(t.x * m.normalStrength, t.y * m.normalStrength, max(t.z, 0.05)))
            let T = simd_normalize(s.tangent - n * simd_dot(n, s.tangent))
            let B = simd_cross(n, T) * (simd_dot(simd_cross(n, T), s.bitangent) < 0 ? -1 : 1)
            n = simd_normalize(T * tn.x + B * tn.y + n * tn.z)
        }
        if m.bumpMap >= 0 && m.bumpStrength > 0 {
            let tex = sc.textures[m.bumpMap], e: Float = 1 / Float(max(tex.width, 1))
            let h0 = tex.sample(uv.x, uv.y).x, hu = tex.sample(uv.x + e, uv.y).x, hv = tex.sample(uv.x, uv.y + e).x
            let du = (hu - h0) / e * m.bumpStrength * 0.02, dv = (hv - h0) / e * m.bumpStrength * 0.02
            n = simd_normalize(n - s.tangent * du - s.bitangent * dv)
        }
        if m.water { n = simd_normalize(n + PTShading.waterNormal(x: p.x, y: p.y, time: sc.time) - PTVec(0, 0, 1)) }
        if m.snow > 0 {
            let k = m.snow * min(max((n.z - 0.5) / 0.4, 0), 1)
            alb = alb * (1 - k) + PTVec(repeating: 0.92) * k
            rough = rough * (1 - k) + 0.75 * k
        }
        if m.wet > 0 { rough *= 1 - 0.7 * m.wet; alb *= 1 - 0.3 * m.wet }
        return Surface(n: n, ng: s.ng, albedo: alb, roughness: rough, metalness: metal, ao: ao, mat: m)
    }

    func trace(_ o0: PTVec, _ d0: PTVec, _ rng: inout PTRandom, _ stack: UnsafeMutablePointer<Int32>) -> PathResult {
        var res = PathResult()
        var o = o0, d = d0
        var beta = PTVec(repeating: 1)
        let sc = scene, env = sc.environment
        let eps = max(0.5, sc.sceneSize * 2e-6)
        let cosSun = cosf(env.sunRadius)
        for bounce in 0...settings.maxBounces {
            guard let hit = sc.intersect(o, d, stack: stack) else {
                res.sky += beta * env.radiance(d)
                if bounce == 0 { res.albedo = PTVec(repeating: 1); res.normal = -d; res.depth = 1e9 }
                break
            }
            let p = o + d * hit.t
            let sf = surface(hit, p, d)
            // Shading normals face the viewer.
            var ng = sf.ng, n = sf.n
            if simd_dot(ng, d) > 0 { ng = -ng }
            if simd_dot(n, ng) < 0 { n = simd_normalize(n - ng * (2 * simd_dot(n, ng))) }
            if bounce == 0 { res.albedo = sf.albedo; res.normal = n; res.depth = hit.t }
            if simd_length_squared(sf.mat.emission) > 0 { res.artificial += beta * sf.mat.emission }
            let v = -d
            // Dielectric (glass, water): Fresnel reflection or refraction, rough glass via GGX microfacets.
            if sf.mat.transmission > 0 && rng.next() < sf.mat.transmission {
                let entering = simd_dot(d, sf.ng) < 0
                let eta = entering ? 1 / sf.mat.ior : sf.mat.ior
                var m = n
                if sf.roughness > 0.05 { m = PTShading.ggxHalf(n, alpha: sf.roughness * sf.roughness, rng.next(), rng.next()); if simd_dot(m, v) < 0 { m = n } }
                let cosI = max(simd_dot(v, m), 0)
                let F = PTShading.fresnelDielectric(cosI: cosI, eta: 1 / eta)
                if rng.next() < F {
                    d = PTShading.reflect(d, m)
                    o = p + ng * eps
                } else if let t = PTShading.refract(d, m, eta) {
                    d = t
                    o = p - ng * eps
                    beta *= PTVec(repeating: 1) * 0.3 + sf.albedo * 0.7
                } else {
                    d = PTShading.reflect(d, m); o = p + ng * eps
                }
                continue
            }
            let alb = sf.albedo * sf.ao
            let po = p + ng * eps
            // Next-event estimation: sun (sampled over its disc) and placed lights.
            if simd_length_squared(env.sunIrradiance) > 0 {
                let (t, b) = PTShading.basis(env.sunDirection)
                let ct = 1 - rng.next() * (1 - cosSun), st = sqrtf(max(0, 1 - ct * ct)), ph = 2 * Float.pi * rng.next()
                let l = simd_normalize(env.sunDirection * ct + t * (st * cosf(ph)) + b * (st * sinf(ph)))
                let nl = simd_dot(n, l)
                if nl > 0 && simd_dot(ng, l) > 0 {
                    let tr = sc.transmittance(po, l, tMax: .greatestFiniteMagnitude, stack: stack)
                    if simd_length_squared(tr) > 0 {
                        res.sun += beta * tr * PTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: max(sf.roughness, 0.08), metalness: sf.metalness) * env.sunIrradiance * nl
                    }
                }
            }
            for lt in sc.lights {
                let dl = lt.position - po
                let dist2 = simd_length_squared(dl)
                guard dist2 > 1 else { continue }
                let dist = sqrtf(dist2), l = dl / dist
                let nl = simd_dot(n, l)
                guard nl > 0 else { continue }
                var cone: Float = 1
                if let dir = lt.direction {
                    let c = simd_dot(-l, dir)
                    if c <= lt.cosOuter { continue }
                    cone = min(1, (c - lt.cosOuter) / max(lt.cosInner - lt.cosOuter, 1e-4))
                }
                let tr = sc.transmittance(po, l, tMax: dist - eps, stack: stack)
                if simd_length_squared(tr) == 0 { continue }
                let dm = dist / 1000
                res.artificial += beta * tr * PTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: max(sf.roughness, 0.08), metalness: sf.metalness) * lt.intensity * (cone * nl / (dm * dm))
            }
            // Continue the path: one-sample MIS between the diffuse and specular lobes.
            let nv = max(simd_dot(n, v), 1e-4)
            let pS = PTShading.specularProbability(nv: nv, albedo: alb, metalness: sf.metalness, roughness: sf.roughness)
            let a = max(sf.roughness * sf.roughness, 0.0025)
            var l: PTVec
            if rng.next() < pS {
                let h = PTShading.ggxHalf(n, alpha: a, rng.next(), rng.next())
                l = PTShading.reflect(d, h)
            } else {
                l = PTShading.cosineSample(n, rng.next(), rng.next())
            }
            let nl = simd_dot(n, l)
            if nl <= 0 || simd_dot(ng, l) <= 0 { break }
            let h = simd_normalize(v + l)
            let nh = max(simd_dot(n, h), 1e-4), vh = max(simd_dot(v, h), 1e-4)
            let pdf = pS * PTShading.ggxD(nh, a) * nh / (4 * vh) + (1 - pS) * nl / Float.pi
            guard pdf > 1e-6 else { break }
            beta *= PTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: sf.roughness, metalness: sf.metalness) * (nl / pdf)
            if settings.clampIndirect > 0 { let lm = ptLum(beta); if lm > settings.clampIndirect { beta *= settings.clampIndirect / lm } }
            // Russian roulette after three bounces.
            if bounce >= 3 {
                let q = min(0.95, max(beta.x, max(beta.y, beta.z)))
                if rng.next() > q { break }
                beta /= q
            }
            o = po; d = l
        }
        func finite(_ v: PTVec) -> PTVec { v.x.isFinite && v.y.isFinite && v.z.isFinite ? v : .zero }
        res.sun = finite(res.sun); res.sky = finite(res.sky); res.artificial = finite(res.artificial)
        return res
    }

    /// Mean radiance per pixel with the light mix applied (HDR).
    func compose(_ mix: PTLightMix = PTLightMix()) -> [PTVec] {
        let n = width * height, k = 1 / Float(max(samples, 1))
        let w0 = mix.weight(.sun) * k, w1 = mix.weight(.sky) * k, w2 = mix.weight(.artificial) * k
        var out = [PTVec](repeating: .zero, count: n)
        for i in 0..<n { out[i] = groups[0][i] * w0 + groups[1][i] * w1 + groups[2][i] * w2 }
        return out
    }
    /// Mean light group radiance (for tests and light-mix previews).
    func group(_ g: PTLightGroup) -> [PTVec] { let k = 1 / Float(max(samples, 1)); return groups[g.rawValue].map { $0 * k } }
    var meanAlbedo: [PTVec] { let k = 1 / Float(max(samples, 1)); return albedo.map { $0 * k } }
    var meanNormal: [PTVec] { normal.map { simd_length($0) > 0 ? simd_normalize($0) : $0 } }
    var meanDepth: [Float] { let k = 1 / Float(max(samples, 1)); return depth.map { $0 * k } }
}

// MARK: - Denoiser (VIS-071)

/// Edge-avoiding à-trous wavelet filter (Dammertz et al. 2010) guided by albedo, normal and depth: noise is smoothed
/// within surfaces while texture, geometry and silhouette edges stay sharp. Lighting is filtered with the albedo
/// divided out (demodulated) and multiplied back afterwards, so textures are not blurred.
enum PTDenoiser {
    static func denoise(color: [PTVec], albedo: [PTVec], normal: [PTVec], depth: [Float], width w: Int, height h: Int,
                        iterations: Int = 5, colorSigma: Float = 0.6, normalPower: Float = 64, albedoSigma: Float = 0.1, depthSigma: Float = 0.02) -> [PTVec] {
        let n = w * h
        guard n > 0, color.count == n, albedo.count == n, normal.count == n, depth.count == n else { return color }
        let alb = albedo.map { simd_max($0, PTVec(repeating: 0.02)) }
        var cur = (0..<n).map { color[$0] / alb[$0] }
        let kernel: [Float] = [1.0 / 16, 1.0 / 4, 3.0 / 8, 1.0 / 4, 1.0 / 16]
        // Luminance scale for the colour weight (relative, so exposure does not matter).
        var meanL: Float = 0
        for c in cur { meanL += ptLum(c) }
        meanL = max(meanL / Float(n), 1e-6)
        for it in 0..<max(1, iterations) {
            let step = 1 << it
            let sc = colorSigma * meanL / Float(1 << it) * 2
            var next = cur
            next.withUnsafeMutableBufferPointer { out in
                cur.withUnsafeBufferPointer { inp in
                    DispatchQueue.concurrentPerform(iterations: h) { y in
                        for x in 0..<w {
                            let i = y * w + x
                            let ci = inp[i], ni = normal[i], ai = albedo[i], zi = depth[i]
                            var sum = PTVec.zero, ws: Float = 0
                            for ky in -2...2 {
                                let yy = y + ky * step
                                guard yy >= 0 && yy < h else { continue }
                                for kx in -2...2 {
                                    let xx = x + kx * step
                                    guard xx >= 0 && xx < w else { continue }
                                    let j = yy * w + xx
                                    let cj = inp[j]
                                    let dc = ci - cj
                                    let wc = expf(-simd_length_squared(dc) / max(sc * sc, 1e-12))
                                    let wn = powf(max(0, simd_dot(ni, normal[j])), normalPower)
                                    let da = ai - albedo[j]
                                    let wa = expf(-simd_length_squared(da) / (albedoSigma * albedoSigma))
                                    let wz = expf(-abs(zi - depth[j]) / (depthSigma * max(zi, 1) * Float(step) + 1e-6))
                                    let wgt = kernel[kx + 2] * kernel[ky + 2] * wc * wn * wa * wz
                                    sum += cj * wgt; ws += wgt
                                }
                            }
                            out[i] = ws > 1e-12 ? sum / ws : ci
                        }
                    }
                }
            }
            cur = next
        }
        return (0..<n).map { cur[$0] * alb[$0] }
    }
}

// MARK: - Tone mapping

enum PTToneMap {
    /// Exposure multiplier that maps the log-average luminance to middle grey (auto exposure).
    static func autoExposure(_ hdr: [PTVec]) -> Float {
        var s: Double = 0, c = 0
        for v in hdr { let l = ptLum(v); if l.isFinite && l > 0 { s += log(Double(l) + 1e-4); c += 1 } }
        guard c > 0 else { return 1 }
        let avg = Float(exp(s / Double(c)))
        return 0.18 / max(avg, 1e-6)
    }
    @inline(__always) static func aces(_ x: Float) -> Float { min(1, max(0, (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14))) }
    @inline(__always) static func linearToSRGB(_ c: Float) -> Float { c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055 }

    /// 8-bit sRGB pixels (RGBA) from HDR radiance: exposure (auto × 2^EV), ACES filmic curve, sRGB transfer.
    static func rgba(_ hdr: [PTVec], ev: Float = 0, auto: Bool = true) -> [UInt8] {
        let k = (auto ? autoExposure(hdr) : 1) * powf(2, ev)
        var out = [UInt8](repeating: 255, count: hdr.count * 4)
        for (i, v) in hdr.enumerated() {
            let c = v * k
            out[i * 4] = UInt8(max(0, min(255, linearToSRGB(aces(c.x)) * 255 + 0.5)))
            out[i * 4 + 1] = UInt8(max(0, min(255, linearToSRGB(aces(c.y)) * 255 + 0.5)))
            out[i * 4 + 2] = UInt8(max(0, min(255, linearToSRGB(aces(c.z)) * 255 + 0.5)))
        }
        return out
    }

    static func cgImage(_ hdr: [PTVec], width: Int, height: Int, ev: Float = 0, auto: Bool = true) -> CGImage? {
        guard hdr.count == width * height, width > 0 else { return nil }
        let px = rgba(hdr, ev: ev, auto: auto)
        let data = Data(px) as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
