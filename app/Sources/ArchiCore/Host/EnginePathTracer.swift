// Oanarina Archi Tool — GPL-3.0-or-later
// The Mac app's progressive path tracer (ArchiApp/PathTracer.swift, PathTracerUI.swift: VIS-070 path tracing, VIS-071
// denoiser, VIS-078 light mix) as portable Swift for archi-engine: binned-SAH BVH, GGX + Lambert with one-sample MIS,
// next-event estimation for the sun and placed lights, dielectric glass, PBR maps (albedo, normal, roughness, metallic,
// AO, bump; baseline JPEG and PNG textures), emissive materials, procedural sky, ground plane, light groups, à-trous
// denoiser, ACES tone mapping. Same numbers as the Mac, SIMD from the standard library instead of the simd module.
// Also the data passes of RENDERTOFILE (Alpha, Depth, Normal, Material ID) by casting primary rays.
import Foundation
import Dispatch

typealias EPTVec = SIMD3<Float>

@inline(__always) func eptDot(_ a: EPTVec, _ b: EPTVec) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
@inline(__always) func eptCross(_ a: EPTVec, _ b: EPTVec) -> EPTVec { EPTVec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
@inline(__always) func eptLength2(_ a: EPTVec) -> Float { eptDot(a, a) }
@inline(__always) func eptLength(_ a: EPTVec) -> Float { eptDot(a, a).squareRoot() }
@inline(__always) func eptNormalize(_ a: EPTVec) -> EPTVec { let l = eptLength(a); return l > 0 ? a / l : a }
@inline(__always) func eptMin(_ a: EPTVec, _ b: EPTVec) -> EPTVec { EPTVec(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)) }
@inline(__always) func eptMax(_ a: EPTVec, _ b: EPTVec) -> EPTVec { EPTVec(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)) }
@inline(__always) func eptLum(_ c: EPTVec) -> Float { c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722 }
@inline(__always) func eptVec(_ v: Vec3) -> EPTVec { EPTVec(Float(v.x), Float(v.y), Float(v.z)) }

/// Deterministic random numbers (PCG hash): the same seed gives the same image.
struct EPTRandom {
    var state: UInt32
    init(seed: UInt32) { state = seed &* 747796405 &+ 2891336453; _ = next() }
    @inline(__always) mutating func next() -> Float {
        state = state &* 747796405 &+ 2891336453
        var w = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277803737
        w = (w >> 22) ^ w
        return Float(w >> 8) * (1.0 / 16777216.0)
    }
    static func hash(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
        let x = a &* 0x9E3779B1
        let y = (b &+ 0x7F4A7C15) &* 0x85EBCA77
        let z = (c &+ 0x165667B1) &* 0xC2B2AE3D
        var h = x ^ y ^ z
        h ^= h >> 15; h = h &* 0x2C1B3C6D; h ^= h >> 12; h = h &* 0x297A2D39; h ^= h >> 15
        return h
    }
}

/// A texture in linear floating point (colour maps converted from sRGB, data maps kept as stored).
final class EPTTexture: @unchecked Sendable {
    let width: Int, height: Int
    let pixels: [EPTVec]
    init(width: Int, height: Int, pixels: [EPTVec]) { self.width = width; self.height = height; self.pixels = pixels }

    func sample(_ u: Float, _ v: Float) -> EPTVec {
        guard width > 0, height > 0 else { return EPTVec(repeating: 1) }
        let x = (u - u.rounded(.down)) * Float(width) - 0.5, y = (1 - (v - v.rounded(.down))) * Float(height) - 0.5
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Float(x0), fy = y - Float(y0)
        func px(_ i: Int, _ j: Int) -> EPTVec {
            let ii = ((i % width) + width) % width, jj = ((j % height) + height) % height
            return pixels[jj * width + ii]
        }
        let a = px(x0, y0) * (1 - fx) + px(x0 + 1, y0) * fx
        let b = px(x0, y0 + 1) * (1 - fx) + px(x0 + 1, y0 + 1) * fx
        return a * (1 - fy) + b * fy
    }

    static func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }

    /// Loads a JPEG (baseline) or PNG / BMP (grey) file, reduced to at most `maxSize` pixels.
    static func load(_ url: URL, maxSize: Int = 1024, linearize: Bool) -> EPTTexture? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        var w = 0, h = 0
        var rgb: [UInt8] = []
        if d.count > 2 && d[d.startIndex] == 0xFF && d[d.startIndex + 1] == 0xD8 {
            guard let j = try? JPEGDecoder.decode(d) else { return nil }
            w = j.width; h = j.height; rgb = j.rgb
        } else if let r = try? RasterImage.decode(d) {
            w = r.width; h = r.height
            rgb = [UInt8](repeating: 0, count: w * h * 3)
            for i in 0..<(w * h) { rgb[i * 3] = r.gray[i]; rgb[i * 3 + 1] = r.gray[i]; rgb[i * 3 + 2] = r.gray[i] }
        } else { return nil }
        guard w > 0, h > 0 else { return nil }
        let step = max(1, Int((Double(max(w, h)) / Double(maxSize)).rounded(.up)))
        let ow = max(1, w / step), oh = max(1, h / step)
        var px = [EPTVec](repeating: .zero, count: ow * oh)
        for y in 0..<oh {
            for x in 0..<ow {
                var s = EPTVec.zero
                for yy in 0..<step {
                    for xx in 0..<step {
                        let sx = min(w - 1, x * step + xx), sy = min(h - 1, y * step + yy)
                        let o = (sy * w + sx) * 3
                        s += EPTVec(Float(rgb[o]), Float(rgb[o + 1]), Float(rgb[o + 2]))
                    }
                }
                var c = s / Float(step * step * 255)
                if linearize { c = EPTVec(srgbToLinear(c.x), srgbToLinear(c.y), srgbToLinear(c.z)) }
                px[y * ow + x] = c
            }
        }
        return EPTTexture(width: ow, height: oh, pixels: px)
    }
}

struct EPTMaterial {
    var albedo = EPTVec(repeating: 0.8)
    var roughness: Float = 0.8
    var metalness: Float = 0
    var transmission: Float = 0
    var ior: Float = 1.5
    var emission = EPTVec.zero
    var albedoMap = -1, roughnessMap = -1, metalMap = -1, normalMap = -1, aoMap = -1, bumpMap = -1
    var bumpStrength: Float = 0
    var normalStrength: Float = 1
    var uvScale: Float = 1
    var water = false
    var snow: Float = 0
    var wet: Float = 0
    var name = ""
}

struct EPTTri { var p0: EPTVec; var e1: EPTVec; var e2: EPTVec; var mat: Int32 }
struct EPTShade { var n0: EPTVec; var n1: EPTVec; var n2: EPTVec; var uv0: SIMD2<Float>; var uv1: SIMD2<Float>; var uv2: SIMD2<Float>; var tangent: EPTVec; var bitangent: EPTVec; var ng: EPTVec }
struct EPTNode { var bmin: EPTVec; var bmax: EPTVec; var start: Int32; var count: Int32; var right: Int32 }
struct EPTPointLight { var position: EPTVec; var intensity: EPTVec; var direction: EPTVec?; var cosOuter: Float; var cosInner: Float }

/// Camera: eye, target, Z up, vertical field of view in degrees.
struct EPTCamera {
    var eye: EPTVec; var target: EPTVec; var fovDegrees: Float = 45; var orthographic = false
    init(eye: EPTVec, target: EPTVec, fovDegrees: Float = 45, orthographic: Bool = false) { self.eye = eye; self.target = target; self.fovDegrees = fovDegrees; self.orthographic = orthographic }
    init(_ c: Camera) { self.init(eye: eptVec(c.eye), target: eptVec(c.target), fovDegrees: Float(c.fov), orthographic: c.orthographic) }
    var basis: (f: EPTVec, r: EPTVec, u: EPTVec) {
        let f = eptNormalize(target - eye)
        var up = EPTVec(0, 0, 1)
        if abs(eptDot(f, up)) > 0.999 { up = EPTVec(0, 1, 0) }
        let r = eptNormalize(eptCross(f, up))
        return (f, r, eptCross(r, f))
    }
    /// Ray through normalized image coordinates (0…1, y down).
    func ray(_ sx: Float, _ sy: Float, aspect: Float) -> (EPTVec, EPTVec) {
        let (f, r, u) = basis
        let h = tanf(fovDegrees * .pi / 360)
        let px = (sx * 2 - 1) * h * aspect, py = (1 - sy * 2) * h
        if orthographic {
            let d = eptLength(target - eye)
            return (eye + r * (px * d) + u * (py * d), f)
        }
        return (eye, eptNormalize(f + r * px + u * py))
    }
}

/// Sky and sun model (radiance in lux-like units).
struct EPTEnvironment {
    var zenith = EPTVec(0.26, 0.45, 0.85) * 9000
    var horizon = EPTVec(0.80, 0.87, 0.95) * 11000
    var ground = EPTVec(0.35, 0.33, 0.30) * 3000
    var sunDirection = eptNormalize(EPTVec(-0.45, -0.7, 0.75))
    var sunIrradiance = EPTVec(1, 0.96, 0.9) * 90000
    var sunRadius: Float = 0.0047

    func radiance(_ d: EPTVec) -> EPTVec {
        if d.z >= 0 {
            let t = powf(min(d.z, 1), 0.45)
            return horizon * (1 - t) + zenith * t
        }
        let t = min(-d.z * 4, 1)
        return horizon * 0.4 * (1 - t) + ground * t
    }

    /// Preset skies of the render dialog's environments lit by the sun (PTEnvironment.preset).
    static func preset(_ env: String, sun: Vec3, altitude: Double) -> EPTEnvironment {
        var e = EPTEnvironment()
        e.sunDirection = eptNormalize(EPTVec(Float(sun.x), Float(sun.y), Float(max(sun.z, 0.02))))
        let s = Float(max(0, sin(altitude)))
        let day = min(1, s * 3 + 0.05)
        switch env {
        case "Overcast":
            e.zenith = EPTVec(repeating: 0.8) * 9000 * day; e.horizon = EPTVec(repeating: 0.9) * 9000 * day; e.ground = EPTVec(repeating: 0.4) * 3000 * day
            e.sunIrradiance = EPTVec(1, 1, 1) * 8000 * s
        case "Sunset":
            e.zenith = EPTVec(0.18, 0.22, 0.45) * 5000; e.horizon = EPTVec(1.0, 0.62, 0.35) * 7000; e.ground = EPTVec(0.25, 0.2, 0.18) * 2000
            e.sunIrradiance = EPTVec(1, 0.7, 0.45) * 40000 * max(s, 0.1)
        case "Studio":
            e.zenith = EPTVec(repeating: 0.95) * 10000; e.horizon = EPTVec(repeating: 0.8) * 10000; e.ground = EPTVec(repeating: 0.55) * 6000
            e.sunIrradiance = EPTVec(repeating: 1) * 30000
        case "Night":
            e.zenith = EPTVec(0.02, 0.03, 0.07) * 40; e.horizon = EPTVec(0.08, 0.1, 0.16) * 40; e.ground = EPTVec(repeating: 0.03) * 20
            e.sunIrradiance = .zero
        default:
            e.zenith = e.zenith * day; e.horizon = e.horizon * day; e.ground = e.ground * day
            let k = min(1, s * 2)
            let warm = EPTVec(1, 0.72 + 0.26 * k, 0.5 + 0.42 * k)
            e.sunIrradiance = warm * 100000 * s
        }
        return e
    }
}

/// Scene data: triangles, shading data, BVH, materials, textures, lights, environment.
final class EPTScene: @unchecked Sendable {
    var tris: [EPTTri] = []
    var shade: [EPTShade] = []
    var nodes: [EPTNode] = []
    var materials: [EPTMaterial] = [EPTMaterial()]
    var textures: [EPTTexture] = []
    var lights: [EPTPointLight] = []
    var environment = EPTEnvironment()
    var groundZ: Float? = nil
    var groundMaterial = 0
    var time: Float = 0
    var boundsMin = EPTVec(repeating: .greatestFiniteMagnitude), boundsMax = EPTVec(repeating: -.greatestFiniteMagnitude)

    var sceneSize: Float { tris.isEmpty ? 1000 : eptLength(boundsMax - boundsMin) }

    /// Adds a triangle mesh (model millimetres) with a material index.
    func add(_ mesh: Mesh, material: Int) {
        let p = mesh.positions.map { eptVec($0) }
        let hasN = mesh.normals.count == p.count, hasUV = mesh.uvs.count == p.count
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            i += 3
            guard a < p.count, b < p.count, c < p.count else { continue }
            let e1 = p[b] - p[a], e2 = p[c] - p[a]
            let cr = eptCross(e1, e2)
            let area = eptLength(cr)
            guard area > 1e-9 else { continue }
            let ng = cr / area
            func n(_ k: Int) -> EPTVec { hasN ? eptNormalize(eptVec(mesh.normals[k])) : ng }
            func uv(_ k: Int) -> SIMD2<Float> { hasUV ? SIMD2(Float(mesh.uvs[k].x), Float(mesh.uvs[k].y)) : .zero }
            let uva = uv(a), uvb = uv(b), uvc = uv(c)
            let d1 = uvb - uva, d2 = uvc - uva
            let det = d1.x * d2.y - d1.y * d2.x
            var t = eptNormalize(e1)
            var bt = eptNormalize(eptCross(ng, t))
            if abs(det) > 1e-12 {
                let tt = (e1 * d2.y - e2 * d1.y) / det
                let bb = (e2 * d1.x - e1 * d2.x) / det
                if eptLength(tt) > 1e-12 && eptLength(bb) > 1e-12 { t = eptNormalize(tt); bt = eptNormalize(bb) }
            }
            tris.append(EPTTri(p0: p[a], e1: e1, e2: e2, mat: Int32(material)))
            shade.append(EPTShade(n0: n(a), n1: n(b), n2: n(c), uv0: uva, uv1: uvb, uv2: uvc, tangent: t, bitangent: bt, ng: ng))
            for q in [p[a], p[b], p[c]] { boundsMin = eptMin(boundsMin, q); boundsMax = eptMax(boundsMax, q) }
        }
    }

    // MARK: BVH (binned SAH)

    func buildBVH() {
        nodes.removeAll(keepingCapacity: true)
        guard !tris.isEmpty else { return }
        var idx = Array(0..<tris.count)
        let cent = tris.map { $0.p0 + ($0.e1 + $0.e2) / 3 }
        let lo = tris.map { eptMin($0.p0, eptMin($0.p0 + $0.e1, $0.p0 + $0.e2)) }
        let hi = tris.map { eptMax($0.p0, eptMax($0.p0 + $0.e1, $0.p0 + $0.e2)) }
        nodes.reserveCapacity(tris.count * 2)
        func area(_ a: EPTVec, _ b: EPTVec) -> Float { let d = eptMax(b - a, .zero); return d.x * d.y + d.y * d.z + d.z * d.x }
        let big = EPTVec(repeating: .greatestFiniteMagnitude)
        func build(_ s: Int, _ e: Int) -> Int {
            var bmin = big, bmax = -big, cmin = big, cmax = -big
            for k in s..<e {
                let t = idx[k]
                bmin = eptMin(bmin, lo[t]); bmax = eptMax(bmax, hi[t]); cmin = eptMin(cmin, cent[t]); cmax = eptMax(cmax, cent[t])
            }
            let me = nodes.count
            nodes.append(EPTNode(bmin: bmin, bmax: bmax, start: Int32(s), count: Int32(e - s), right: -1))
            let n = e - s
            if n <= 4 { return me }
            let ext = cmax - cmin
            let axis = ext.x > ext.y ? (ext.x > ext.z ? 0 : 2) : (ext.y > ext.z ? 1 : 2)
            guard ext[axis] > 1e-6 else { return me }
            let bins = 12
            var bc = [Int](repeating: 0, count: bins)
            var blo = [EPTVec](repeating: big, count: bins)
            var bhi = [EPTVec](repeating: -big, count: bins)
            func bin(_ t: Int) -> Int { min(bins - 1, Int(Float(bins) * (cent[t][axis] - cmin[axis]) / ext[axis])) }
            for k in s..<e {
                let t = idx[k]
                let bb = bin(t)
                bc[bb] += 1; blo[bb] = eptMin(blo[bb], lo[t]); bhi[bb] = eptMax(bhi[bb], hi[t])
            }
            var best = Float.greatestFiniteMagnitude, split = -1
            for sIdx in 1..<bins {
                var l0 = big, l1 = -big, r0 = big, r1 = -big, nl = 0, nr = 0
                for q in 0..<sIdx where bc[q] > 0 { l0 = eptMin(l0, blo[q]); l1 = eptMax(l1, bhi[q]); nl += bc[q] }
                for q in sIdx..<bins where bc[q] > 0 { r0 = eptMin(r0, blo[q]); r1 = eptMax(r1, bhi[q]); nr += bc[q] }
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

    @inline(__always) static func slab(_ o: EPTVec, _ inv: EPTVec, _ n: EPTNode, _ tMax: Float) -> Bool {
        let t0 = (n.bmin - o) * inv, t1 = (n.bmax - o) * inv
        let tn = eptMin(t0, t1), tf = eptMax(t0, t1)
        let a = max(max(tn.x, tn.y), max(tn.z, 0)), b = min(min(tf.x, tf.y), min(tf.z, tMax))
        return a <= b
    }
    @inline(__always) static func inverse(_ d: EPTVec) -> EPTVec {
        EPTVec(1 / (abs(d.x) < 1e-12 ? 1e-12 : d.x), 1 / (abs(d.y) < 1e-12 ? 1e-12 : d.y), 1 / (abs(d.z) < 1e-12 ? 1e-12 : d.z))
    }

    /// Closest hit (tri = -1 for the ground plane).
    func intersect(_ o: EPTVec, _ d: EPTVec, tMax: Float = .greatestFiniteMagnitude, stack: UnsafeMutablePointer<Int32>, ground: Bool = true) -> Hit? {
        var best = Hit(t: tMax, tri: -2, u: 0, v: 0)
        if ground, let gz = groundZ, abs(d.z) > 1e-8 {
            let t = (gz - o.z) / d.z
            if t > 1e-3 && t < best.t { best = Hit(t: t, tri: -1, u: 0, v: 0) }
        }
        if !nodes.isEmpty {
            let inv = EPTScene.inverse(d)
            nodes.withUnsafeBufferPointer { nb in
                tris.withUnsafeBufferPointer { tb in
                    var sp = 0
                    stack[sp] = 0; sp += 1
                    while sp > 0 {
                        sp -= 1
                        let ni = Int(stack[sp])
                        let n = nb[ni]
                        guard EPTScene.slab(o, inv, n, best.t) else { continue }
                        if n.count > 0 {
                            for k in Int(n.start)..<Int(n.start + n.count) {
                                let tr = tb[k]
                                let p = eptCross(d, tr.e2)
                                let det = eptDot(tr.e1, p)
                                if abs(det) < 1e-12 { continue }
                                let id = 1 / det
                                let s = o - tr.p0
                                let u = eptDot(s, p) * id
                                if u < 0 || u > 1 { continue }
                                let q = eptCross(s, tr.e1)
                                let v = eptDot(d, q) * id
                                if v < 0 || u + v > 1 { continue }
                                let t = eptDot(tr.e2, q) * id
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
    func transmittance(_ o: EPTVec, _ d: EPTVec, tMax: Float, stack: UnsafeMutablePointer<Int32>) -> EPTVec {
        if let gz = groundZ, abs(d.z) > 1e-8 { let t = (gz - o.z) / d.z; if t > 1e-3 && t < tMax { return .zero } }
        guard !nodes.isEmpty else { return EPTVec(repeating: 1) }
        var T = EPTVec(repeating: 1)
        let inv = EPTScene.inverse(d)
        var blocked = false
        nodes.withUnsafeBufferPointer { nb in
            tris.withUnsafeBufferPointer { tb in
                var sp = 0
                stack[sp] = 0; sp += 1
                while sp > 0 && !blocked {
                    sp -= 1
                    let ni = Int(stack[sp])
                    let n = nb[ni]
                    guard EPTScene.slab(o, inv, n, tMax) else { continue }
                    if n.count > 0 {
                        for k in Int(n.start)..<Int(n.start + n.count) {
                            let tr = tb[k]
                            let p = eptCross(d, tr.e2)
                            let det = eptDot(tr.e1, p)
                            if abs(det) < 1e-12 { continue }
                            let id = 1 / det
                            let s = o - tr.p0
                            let u = eptDot(s, p) * id
                            if u < 0 || u > 1 { continue }
                            let q = eptCross(s, tr.e1)
                            let v = eptDot(d, q) * id
                            if v < 0 || u + v > 1 { continue }
                            let t = eptDot(tr.e2, q) * id
                            if t > 1e-3 && t < tMax {
                                let m = materials[Int(tr.mat)]
                                if m.transmission < 0.01 { blocked = true; break }
                                let tint = EPTVec(repeating: 1) * 0.5 + m.albedo * 0.5
                                T *= tint * m.transmission.squareRoot()
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

enum EPTShading {
    static func fresnelDielectric(cosI: Float, eta: Float) -> Float {
        let f0 = powf((eta - 1) / (eta + 1), 2)
        let sin2t = (1 / (eta * eta)) * max(0, 1 - cosI * cosI)
        if eta < 1 && sin2t > 1 { return 1 }
        let c = eta < 1 ? max(0, 1 - sin2t).squareRoot() : cosI
        return f0 + (1 - f0) * powf(1 - c, 5)
    }
    static func refract(_ d: EPTVec, _ n: EPTVec, _ eta: Float) -> EPTVec? {
        let cosI = -eptDot(d, n)
        let k = 1 - eta * eta * (1 - cosI * cosI)
        if k < 0 { return nil }
        return eptNormalize(d * eta + n * (eta * cosI - k.squareRoot()))
    }
    static func reflect(_ d: EPTVec, _ n: EPTVec) -> EPTVec { d - n * (2 * eptDot(d, n)) }
    static func basis(_ n: EPTVec) -> (EPTVec, EPTVec) {
        let a = abs(n.x) > 0.9 ? EPTVec(0, 1, 0) : EPTVec(1, 0, 0)
        let t = eptNormalize(eptCross(a, n))
        return (t, eptCross(n, t))
    }
    static func cosineSample(_ n: EPTVec, _ u1: Float, _ u2: Float) -> EPTVec {
        let r = u1.squareRoot(), phi = 2 * Float.pi * u2
        let (t, b) = basis(n)
        let z = max(0, 1 - u1).squareRoot()
        return eptNormalize(t * (r * cosf(phi)) + b * (r * sinf(phi)) + n * z)
    }
    static func ggxHalf(_ n: EPTVec, alpha: Float, _ u1: Float, _ u2: Float) -> EPTVec {
        let phi = 2 * Float.pi * u2
        let cosT = ((1 - u1) / (1 + (alpha * alpha - 1) * u1)).squareRoot()
        let sinT = max(0, 1 - cosT * cosT).squareRoot()
        let (t, b) = basis(n)
        return eptNormalize(t * (sinT * cosf(phi)) + b * (sinT * sinf(phi)) + n * cosT)
    }
    static func ggxD(_ nh: Float, _ a: Float) -> Float {
        let a2 = a * a, d = nh * nh * (a2 - 1) + 1
        return a2 / (Float.pi * d * d)
    }
    /// GGX specular + Lambert diffuse BRDF (without the cosine term).
    static func brdf(n: EPTVec, v: EPTVec, l: EPTVec, albedo: EPTVec, roughness: Float, metalness: Float) -> EPTVec {
        let nl = eptDot(n, l), nv = eptDot(n, v)
        guard nl > 0, nv > 0 else { return .zero }
        let h = eptNormalize(v + l)
        let nh = max(eptDot(n, h), 0), vh = max(eptDot(v, h), 0)
        let a = max(roughness * roughness, 0.0025)
        let D = ggxD(nh, a)
        let k = a / 2
        let g1 = nv / (nv * (1 - k) + k)
        let g2 = nl / (nl * (1 - k) + k)
        let G = g1 * g2
        let f0 = EPTVec(repeating: 0.04) * (1 - metalness) + albedo * metalness
        let F = f0 + (EPTVec(repeating: 1) - f0) * powf(1 - vh, 5)
        let spec = F * (D * G / (4 * nv * nl))
        let diff = (EPTVec(repeating: 1) - F) * (1 - metalness) * albedo / Float.pi
        return diff + spec
    }
    static func specularProbability(nv: Float, albedo: EPTVec, metalness: Float, roughness: Float) -> Float {
        let f0 = 0.04 * (1 - metalness) + eptLum(albedo) * metalness
        let f = f0 + (1 - f0) * powf(1 - max(nv, 0), 5)
        let d = (1 - metalness) * eptLum(albedo) * (1 - f)
        return min(0.9, max(0.1, f / max(f + d, 1e-4)))
    }
    static func waterNormal(x: Float, y: Float, time: Float, amplitude: Float = 0.08) -> EPTVec {
        let waves: [(EPTVec, Float, Float)] = [(EPTVec(1, 0.3, 0), 1 / 900, 1.1), (EPTVec(-0.4, 1, 0), 1 / 610, 1.7), (EPTVec(0.7, -0.7, 0), 1 / 350, 2.3), (EPTVec(0.2, 0.9, 0), 1 / 170, 3.1)]
        var gx: Float = 0, gy: Float = 0
        for (dir, k, w) in waves {
            let d = eptNormalize(dir)
            let ph = (d.x * x + d.y * y) * k * 2 * .pi + time * w
            let c = cosf(ph) * amplitude / Float(waves.count) * 2 * .pi
            gx += d.x * c; gy += d.y * c
        }
        return eptNormalize(EPTVec(-gx, -gy, 1))
    }
}

// MARK: - Render session

struct EPTSettings {
    var width = 640
    var height = 400
    var maxBounces = 6
    var camera = EPTCamera(eye: EPTVec(-8000, -10000, 6000), target: EPTVec(0, 0, 1500))
    var seed: UInt32 = 1
    var clampIndirect: Float = 0
}

/// Light group weights after rendering (sun, sky, artificial).
struct EPTLightMix: Equatable {
    var sun: Float = 1, sky: Float = 1, artificial: Float = 1
}

/// Progressive rendering: each pass adds one sample per pixel into light-group sums and first-hit guide buffers.
final class EPTSession: @unchecked Sendable {
    let scene: EPTScene
    let settings: EPTSettings
    let width: Int, height: Int
    private(set) var groups: [[EPTVec]]
    private(set) var albedo: [EPTVec]
    private(set) var normal: [EPTVec]
    private(set) var depth: [Float]
    private(set) var samples = 0
    let lock = NSLock()

    init(scene: EPTScene, settings: EPTSettings) {
        self.scene = scene; self.settings = settings
        width = max(1, settings.width); height = max(1, settings.height)
        let n = width * height
        groups = Array(repeating: [EPTVec](repeating: .zero, count: n), count: 3)
        albedo = [EPTVec](repeating: .zero, count: n); normal = [EPTVec](repeating: .zero, count: n); depth = [Float](repeating: 0, count: n)
    }

    /// Adds one sample to every pixel (rows in parallel).
    func renderPass() {
        let w = width, h = height, pass = UInt32(samples)
        let aspect = Float(w) / Float(h)
        let g0 = UnsafeMutablePointer<EPTVec>.allocate(capacity: w * h * 3)
        let aov = UnsafeMutablePointer<EPTVec>.allocate(capacity: w * h * 2)
        let dep = UnsafeMutablePointer<Float>.allocate(capacity: w * h)
        defer { g0.deallocate(); aov.deallocate(); dep.deallocate() }
        let seed = settings.seed
        DispatchQueue.concurrentPerform(iterations: h) { y in
            let stack = UnsafeMutablePointer<Int32>.allocate(capacity: 128)
            defer { stack.deallocate() }
            for x in 0..<w {
                var rng = EPTRandom(seed: EPTRandom.hash(UInt32(x), UInt32(y), pass &* 9781 &+ seed))
                let (o, d) = settings.camera.ray((Float(x) + rng.next()) / Float(w), (Float(y) + rng.next()) / Float(h), aspect: aspect)
                let r = trace(o, d, &rng, stack)
                let i = y * w + x
                g0[i * 3] = r.sun; g0[i * 3 + 1] = r.sky; g0[i * 3 + 2] = r.artificial
                aov[i * 2] = r.albedo; aov[i * 2 + 1] = r.normal; dep[i] = r.depth
            }
        }
        lock.lock()
        for i in 0..<(w * h) {
            groups[0][i] += g0[i * 3]; groups[1][i] += g0[i * 3 + 1]; groups[2][i] += g0[i * 3 + 2]
            albedo[i] += aov[i * 2]; normal[i] += aov[i * 2 + 1]; depth[i] += dep[i]
        }
        samples += 1
        lock.unlock()
    }

    struct PathResult { var sun = EPTVec.zero, sky = EPTVec.zero, artificial = EPTVec.zero, albedo = EPTVec.zero, normal = EPTVec.zero, depth: Float = 0 }
    struct Surface { var n: EPTVec; var ng: EPTVec; var albedo: EPTVec; var roughness: Float; var metalness: Float; var ao: Float; var mat: EPTMaterial }

    func surface(_ hit: EPTScene.Hit, _ p: EPTVec, _ d: EPTVec) -> Surface {
        let sc = scene
        if hit.tri < 0 {
            let m = sc.materials[sc.groundMaterial]
            var alb = m.albedo
            if m.albedoMap >= 0 { alb *= sc.textures[m.albedoMap].sample(p.x / 1000 * m.uvScale, p.y / 1000 * m.uvScale) }
            return Surface(n: EPTVec(0, 0, 1), ng: EPTVec(0, 0, 1), albedo: alb, roughness: m.roughness, metalness: m.metalness, ao: 1, mat: m)
        }
        let s = sc.shade[hit.tri]
        let m = sc.materials[Int(sc.tris[hit.tri].mat)]
        let w = 1 - hit.u - hit.v
        var n = eptNormalize(s.n0 * w + s.n1 * hit.u + s.n2 * hit.v)
        let uv = (s.uv0 * w + s.uv1 * hit.u + s.uv2 * hit.v) * m.uvScale
        var alb = m.albedo, rough = m.roughness, metal = m.metalness, ao: Float = 1
        if m.albedoMap >= 0 { alb *= sc.textures[m.albedoMap].sample(uv.x, uv.y) }
        if m.roughnessMap >= 0 { rough *= sc.textures[m.roughnessMap].sample(uv.x, uv.y).x * 2; rough = min(max(rough, 0.02), 1) }
        if m.metalMap >= 0 { metal = min(1, metal + sc.textures[m.metalMap].sample(uv.x, uv.y).x) }
        if m.aoMap >= 0 { ao = sc.textures[m.aoMap].sample(uv.x, uv.y).x }
        if m.normalMap >= 0 {
            let t = sc.textures[m.normalMap].sample(uv.x, uv.y) * 2 - EPTVec(repeating: 1)
            let tn = eptNormalize(EPTVec(t.x * m.normalStrength, t.y * m.normalStrength, max(t.z, 0.05)))
            let T = eptNormalize(s.tangent - n * eptDot(n, s.tangent))
            let nt = eptCross(n, T)
            let B = nt * (eptDot(nt, s.bitangent) < 0 ? -1 : 1)
            n = eptNormalize(T * tn.x + B * tn.y + n * tn.z)
        }
        if m.bumpMap >= 0 && m.bumpStrength > 0 {
            let tex = sc.textures[m.bumpMap]
            let e: Float = 1 / Float(max(tex.width, 1))
            let h0 = tex.sample(uv.x, uv.y).x, hu = tex.sample(uv.x + e, uv.y).x, hv = tex.sample(uv.x, uv.y + e).x
            let du = (hu - h0) / e * m.bumpStrength * 0.02, dv = (hv - h0) / e * m.bumpStrength * 0.02
            n = eptNormalize(n - s.tangent * du - s.bitangent * dv)
        }
        if m.water { n = eptNormalize(n + EPTShading.waterNormal(x: p.x, y: p.y, time: sc.time) - EPTVec(0, 0, 1)) }
        if m.snow > 0 {
            let k = m.snow * min(max((n.z - 0.5) / 0.4, 0), 1)
            alb = alb * (1 - k) + EPTVec(repeating: 0.92) * k
            rough = rough * (1 - k) + 0.75 * k
        }
        if m.wet > 0 { rough *= 1 - 0.7 * m.wet; alb *= 1 - 0.3 * m.wet }
        return Surface(n: n, ng: s.ng, albedo: alb, roughness: rough, metalness: metal, ao: ao, mat: m)
    }

    func trace(_ o0: EPTVec, _ d0: EPTVec, _ rng: inout EPTRandom, _ stack: UnsafeMutablePointer<Int32>) -> PathResult {
        var res = PathResult()
        var o = o0, d = d0
        var beta = EPTVec(repeating: 1)
        let sc = scene, env = sc.environment
        let eps = max(0.5, sc.sceneSize * 2e-6)
        let cosSun = cosf(env.sunRadius)
        for bounce in 0...settings.maxBounces {
            guard let hit = sc.intersect(o, d, stack: stack) else {
                res.sky += beta * env.radiance(d)
                if bounce == 0 { res.albedo = EPTVec(repeating: 1); res.normal = -d; res.depth = 1e9 }
                break
            }
            let p = o + d * hit.t
            let sf = surface(hit, p, d)
            var ng = sf.ng, n = sf.n
            if eptDot(ng, d) > 0 { ng = -ng }
            if eptDot(n, ng) < 0 { n = eptNormalize(n - ng * (2 * eptDot(n, ng))) }
            if bounce == 0 { res.albedo = sf.albedo; res.normal = n; res.depth = hit.t }
            if eptLength2(sf.mat.emission) > 0 { res.artificial += beta * sf.mat.emission }
            let v = -d
            if sf.mat.transmission > 0 && rng.next() < sf.mat.transmission {
                let entering = eptDot(d, sf.ng) < 0
                let eta = entering ? 1 / sf.mat.ior : sf.mat.ior
                var m = n
                if sf.roughness > 0.05 {
                    m = EPTShading.ggxHalf(n, alpha: sf.roughness * sf.roughness, rng.next(), rng.next())
                    if eptDot(m, v) < 0 { m = n }
                }
                let cosI = max(eptDot(v, m), 0)
                let F = EPTShading.fresnelDielectric(cosI: cosI, eta: 1 / eta)
                if rng.next() < F {
                    d = EPTShading.reflect(d, m)
                    o = p + ng * eps
                } else if let t = EPTShading.refract(d, m, eta) {
                    d = t
                    o = p - ng * eps
                    beta *= EPTVec(repeating: 1) * 0.3 + sf.albedo * 0.7
                } else {
                    d = EPTShading.reflect(d, m); o = p + ng * eps
                }
                continue
            }
            let alb = sf.albedo * sf.ao
            let po = p + ng * eps
            if eptLength2(env.sunIrradiance) > 0 {
                let (t, b) = EPTShading.basis(env.sunDirection)
                let ct = 1 - rng.next() * (1 - cosSun)
                let st = max(0, 1 - ct * ct).squareRoot()
                let ph = 2 * Float.pi * rng.next()
                let l = eptNormalize(env.sunDirection * ct + t * (st * cosf(ph)) + b * (st * sinf(ph)))
                let nl = eptDot(n, l)
                if nl > 0 && eptDot(ng, l) > 0 {
                    let tr = sc.transmittance(po, l, tMax: .greatestFiniteMagnitude, stack: stack)
                    if eptLength2(tr) > 0 {
                        let f = EPTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: max(sf.roughness, 0.08), metalness: sf.metalness)
                        res.sun += beta * tr * f * env.sunIrradiance * nl
                    }
                }
            }
            for lt in sc.lights {
                let dl = lt.position - po
                let dist2 = eptLength2(dl)
                guard dist2 > 1 else { continue }
                let dist = dist2.squareRoot()
                let l = dl / dist
                let nl = eptDot(n, l)
                guard nl > 0 else { continue }
                var cone: Float = 1
                if let dir = lt.direction {
                    let c = eptDot(-l, dir)
                    if c <= lt.cosOuter { continue }
                    cone = min(1, (c - lt.cosOuter) / max(lt.cosInner - lt.cosOuter, 1e-4))
                }
                let tr = sc.transmittance(po, l, tMax: dist - eps, stack: stack)
                if eptLength2(tr) == 0 { continue }
                let dm = dist / 1000
                let f = EPTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: max(sf.roughness, 0.08), metalness: sf.metalness)
                res.artificial += beta * tr * f * lt.intensity * (cone * nl / (dm * dm))
            }
            let nv = max(eptDot(n, v), 1e-4)
            let pS = EPTShading.specularProbability(nv: nv, albedo: alb, metalness: sf.metalness, roughness: sf.roughness)
            let a = max(sf.roughness * sf.roughness, 0.0025)
            var l: EPTVec
            if rng.next() < pS {
                let h = EPTShading.ggxHalf(n, alpha: a, rng.next(), rng.next())
                l = EPTShading.reflect(d, h)
            } else {
                l = EPTShading.cosineSample(n, rng.next(), rng.next())
            }
            let nl = eptDot(n, l)
            if nl <= 0 || eptDot(ng, l) <= 0 { break }
            let h = eptNormalize(v + l)
            let nh = max(eptDot(n, h), 1e-4), vh = max(eptDot(v, h), 1e-4)
            let pdfS = pS * EPTShading.ggxD(nh, a) * nh / (4 * vh)
            let pdf = pdfS + (1 - pS) * nl / Float.pi
            guard pdf > 1e-6 else { break }
            beta *= EPTShading.brdf(n: n, v: v, l: l, albedo: alb, roughness: sf.roughness, metalness: sf.metalness) * (nl / pdf)
            if settings.clampIndirect > 0 { let lm = eptLum(beta); if lm > settings.clampIndirect { beta *= settings.clampIndirect / lm } }
            if bounce >= 3 {
                let q = min(0.95, max(beta.x, max(beta.y, beta.z)))
                if rng.next() > q { break }
                beta /= q
            }
            o = po; d = l
        }
        func finite(_ v: EPTVec) -> EPTVec { v.x.isFinite && v.y.isFinite && v.z.isFinite ? v : .zero }
        res.sun = finite(res.sun); res.sky = finite(res.sky); res.artificial = finite(res.artificial)
        return res
    }

    /// Mean radiance per pixel with the light mix applied (HDR).
    func compose(_ mix: EPTLightMix = EPTLightMix()) -> [EPTVec] {
        lock.lock(); defer { lock.unlock() }
        let n = width * height, k = 1 / Float(max(samples, 1))
        let w0 = mix.sun * k, w1 = mix.sky * k, w2 = mix.artificial * k
        var out = [EPTVec](repeating: .zero, count: n)
        for i in 0..<n { out[i] = groups[0][i] * w0 + groups[1][i] * w1 + groups[2][i] * w2 }
        return out
    }
    var meanAlbedo: [EPTVec] { lock.lock(); defer { lock.unlock() }; let k = 1 / Float(max(samples, 1)); return albedo.map { $0 * k } }
    var meanNormal: [EPTVec] { lock.lock(); defer { lock.unlock() }; return normal.map { eptLength($0) > 0 ? eptNormalize($0) : $0 } }
    var meanDepth: [Float] { lock.lock(); defer { lock.unlock() }; let k = 1 / Float(max(samples, 1)); return depth.map { $0 * k } }
}

// MARK: - Denoiser (edge-avoiding à-trous, Dammertz et al. 2010)

enum EPTDenoiser {
    static func denoise(color: [EPTVec], albedo: [EPTVec], normal: [EPTVec], depth: [Float], width w: Int, height h: Int,
                        iterations: Int = 5, colorSigma: Float = 0.6, normalPower: Float = 64, albedoSigma: Float = 0.1, depthSigma: Float = 0.02) -> [EPTVec] {
        let n = w * h
        guard n > 0, color.count == n, albedo.count == n, normal.count == n, depth.count == n else { return color }
        let alb = albedo.map { eptMax($0, EPTVec(repeating: 0.02)) }
        var cur = (0..<n).map { color[$0] / alb[$0] }
        let kernel: [Float] = [1.0 / 16, 1.0 / 4, 3.0 / 8, 1.0 / 4, 1.0 / 16]
        var meanL: Float = 0
        for c in cur { meanL += eptLum(c) }
        meanL = max(meanL / Float(n), 1e-6)
        for it in 0..<max(1, iterations) {
            let step = 1 << it
            let sc = colorSigma * meanL / Float(1 << it) * 2
            var next = cur
            next.withUnsafeMutableBufferPointer { out in
                cur.withUnsafeBufferPointer { inp in
                    let outp = out.baseAddress!
                    let inpp = inp.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: h) { y in
                        for x in 0..<w {
                            let i = y * w + x
                            let ci = inpp[i], ni = normal[i], ai = albedo[i], zi = depth[i]
                            var sum = EPTVec.zero, ws: Float = 0
                            for ky in -2...2 {
                                let yy = y + ky * step
                                guard yy >= 0 && yy < h else { continue }
                                for kx in -2...2 {
                                    let xx = x + kx * step
                                    guard xx >= 0 && xx < w else { continue }
                                    let j = yy * w + xx
                                    let cj = inpp[j]
                                    let wc = expf(-eptLength2(ci - cj) / max(sc * sc, 1e-12))
                                    let wn = powf(max(0, eptDot(ni, normal[j])), normalPower)
                                    let wa = expf(-eptLength2(ai - albedo[j]) / (albedoSigma * albedoSigma))
                                    let wz = expf(-abs(zi - depth[j]) / (depthSigma * max(zi, 1) * Float(step) + 1e-6))
                                    let wgt = kernel[kx + 2] * kernel[ky + 2] * wc * wn * wa * wz
                                    sum += cj * wgt; ws += wgt
                                }
                            }
                            outp[i] = ws > 1e-12 ? sum / ws : ci
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

enum EPTToneMap {
    static func autoExposure(_ hdr: [EPTVec]) -> Float {
        var s: Double = 0, c = 0
        for v in hdr { let l = eptLum(v); if l.isFinite && l > 0 { s += log(Double(l) + 1e-4); c += 1 } }
        guard c > 0 else { return 1 }
        let avg = Float(exp(s / Double(c)))
        return 0.18 / max(avg, 1e-6)
    }
    @inline(__always) static func aces(_ x: Float) -> Float { min(1, max(0, (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14))) }
    @inline(__always) static func linearToSRGB(_ c: Float) -> Float { c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055 }
    @inline(__always) static func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, linearToSRGB(aces(v)) * 255 + 0.5))) }

    /// 8-bit sRGB RGB pixels from HDR radiance: exposure (auto × 2^EV), ACES filmic curve, sRGB transfer.
    static func rgb(_ hdr: [EPTVec], ev: Float = 0, auto: Bool = true) -> [UInt8] {
        let k = (auto ? autoExposure(hdr) : 1) * powf(2, ev)
        var out = [UInt8](repeating: 255, count: hdr.count * 3)
        for (i, v) in hdr.enumerated() {
            let c = v * k
            out[i * 3] = byte(c.x); out[i * 3 + 1] = byte(c.y); out[i * 3 + 2] = byte(c.z)
        }
        return out
    }
}

// MARK: - PNG (RGB 8-bit)

enum EnginePNG {
    /// RGB (3 bytes per pixel, rows top to bottom) as a PNG file.
    static func rgb(_ px: [UInt8], width w: Int, height h: Int) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((w * 3 + 1) * h)
        for y in 0..<h {
            raw.append(0)
            raw.append(contentsOf: px[(y * w * 3)..<((y + 1) * w * 3)])
        }
        let z = EnginePDF.zlib(Data(raw)) ?? Data()
        func be(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ t: String, _ d: [UInt8]) -> [UInt8] {
            let td = Array(t.utf8) + d
            let c = RasterImage.crc(td)
            return be(d.count) + td + be(Int(c))
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be(w) + be(h) + [8, 2, 0, 0, 0])
        out += chunk("IDAT", [UInt8](z))
        out += chunk("IEND", [])
        return Data(out)
    }
}

// MARK: - Scene from a drawing (PTSceneBuilder)

enum EPTSceneBuilder {
    struct Options {
        var environment = "Clear Sky"
        var environmentIntensity = 1.3
        var day = 172
        var hour = 15.0
        var ground = true
        var clay = false
        var folder: URL?
        /// Level of detail of the meshes (0 = full, as the Mac; MeshLOD levels for quick previews and tests).
        var lod = 0
        /// Seconds into the object animations (ANIMATE Frame, as PTSceneBuilder.Options.time): water waves, moved
        /// objects and swinging door leaves.
        var time = 0.0
    }

    static func isVegetation(_ material: String) -> Bool {
        let n = material.lowercased()
        return ["grass", "lawn", "leaf", "leaves", "foliage", "tree", "hedge", "shrub", "plant", "ivy", "moss"].contains { n.contains($0) }
    }
    static func seasonTint(_ c: RGBA, _ season: String) -> RGBA {
        func mix(_ t: RGBA, _ k: Double) -> RGBA { RGBA(c.r + (t.r - c.r) * k, c.g + (t.g - c.g) * k, c.b + (t.b - c.b) * k, c.a) }
        switch season {
        case "Spring": return mix(RGBA(0.55, 0.78, 0.30), 0.35)
        case "Autumn": return mix(RGBA(0.78, 0.45, 0.14), 0.6)
        case "Winter": return mix(RGBA(0.45, 0.40, 0.33), 0.7)
        default: return c
        }
    }

    /// Texture mapping per material (MATMAP:<material> = "mode;ox,oy;rotation;scale", TextureMapping.swift).
    static func mapped(_ mesh: Mesh, material: String, doc: ArchiDocument) -> Mesh {
        guard let s = doc.variable("MATMAP:" + material.uppercased()), !mesh.positions.isEmpty else { return mesh }
        let p = s.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        let modes = ["Box", "Planar", "Cylindrical", "Spherical", "UV"]
        guard let mode = modes.first(where: { $0.caseInsensitiveCompare(p.first ?? "") == .orderedSame }) else { return mesh }
        var offset = Vec2.zero, rotation = 0.0, scale = 1.0
        if p.count > 1 { let o = p[1].split(separator: ",").compactMap { Double($0) }; if o.count == 2 { offset = Vec2(o[0], o[1]) } }
        if p.count > 2, let r = Double(p[2]) { rotation = r }
        if p.count > 3, let k = Double(p[3]), k > 0 { scale = k }
        if mode == "Box" && offset == .zero && rotation == 0 && scale == 1 { return mesh }
        var b = BBox3.empty
        for q in mesh.positions { b.add(q) }
        let c = b.center
        var raw: [Vec2] = []
        switch mode {
        case "Planar": raw = mesh.positions.map { Vec2($0.x, $0.y) / 1000 }
        case "Cylindrical":
            let r = max(max(b.size.x, b.size.y) / 2, 1)
            raw = mesh.positions.map { q in Vec2(atan2(q.y - c.y, q.x - c.x) * r, q.z) / 1000 }
        case "Spherical":
            let r = max(b.size.length / 2, 1)
            raw = mesh.positions.map { q in
                let d = q - c
                let l = max(d.length, 1e-9)
                return Vec2(atan2(d.y, d.x) * r, asin(max(-1, min(1, d.z / l))) * r) / 1000
            }
        case "UV":
            let w = max(b.size.x, 1e-9), h = max(max(b.size.y, b.size.z), 1e-9)
            let useY = abs(b.size.y) >= abs(b.size.z)
            raw = mesh.positions.map { q in Vec2((q.x - b.min.x) / w, (useY ? (q.y - b.min.y) : (q.z - b.min.z)) / h) }
        default:
            raw = mesh.uvs.count == mesh.positions.count ? mesh.uvs : mesh.positions.map { Vec2($0.x, $0.y) / 1000 }
        }
        let a = rotation * .pi / 180, ca = cos(a), sa = sin(a)
        let o = mode == "UV" ? offset / (offset.length > 0 ? 1000 : 1) : offset / 1000
        var m = mesh
        m.uvs = raw.map { q in
            let t = q - o
            return Vec2(t.x * ca + t.y * sa, -t.x * sa + t.y * ca) / scale
        }
        return m
    }

    static func material(_ name: String, doc: ArchiDocument, scene: EPTScene, cache: inout [String: Int], options: Options, weather: EngineWeather) -> EPTMaterial {
        let src = doc.material(name) ?? Material(name: name, color: RGBA(0.8, 0.8, 0.8))
        var c = src.color
        if isVegetation(name) { c = seasonTint(c, weather.season) }
        func lin(_ v: Double) -> Float { EPTTexture.srgbToLinear(Float(v)) }
        var m = EPTMaterial()
        m.name = name
        m.albedo = EPTVec(lin(c.r), lin(c.g), lin(c.b))
        m.roughness = Float(min(max(src.roughness, 0.02), 1))
        m.metalness = Float(min(max(src.metalness, 0), 1))
        m.transmission = Float(min(max(src.transparency, 0), 0.98))
        m.uvScale = Float(1000 / max(src.textureScale, 1))
        if m.transmission > 0.3 { m.roughness = min(m.roughness, 0.08) }
        if EngineView3DData.isWater(name, doc: doc) { m.water = true; m.ior = 1.33; m.transmission = max(m.transmission, 0.85); m.roughness = 0.02 }
        let k = doc.variable("MATEMIT:" + name.uppercased()).flatMap(Double.init).map { min(max($0, 0), 20) } ?? 0
        if k > 0 { m.emission = m.albedo * Float(k) * 3000 }
        if options.clay && m.transmission < 0.3 { var cm = EPTMaterial(); cm.albedo = EPTVec(repeating: 0.8); cm.roughness = 0.85; cm.name = name; return cm }
        func tex(_ path: String?, linear: Bool) -> Int {
            guard let p = path, !p.isEmpty else { return -1 }
            let key = p + (linear ? "|L" : "|D")
            if let i = cache[key] { return i }
            let expanded = (p as NSString).expandingTildeInPath
            var u = URL(fileURLWithPath: expanded)
            let absolute = expanded.hasPrefix("/") || expanded.hasPrefix("\\") || (expanded.count > 1 && Array(expanded)[1] == ":")
            if !absolute, let f = options.folder { u = f.appendingPathComponent(p) }
            guard let t = EPTTexture.load(u, maxSize: 1024, linearize: linear) else { cache[key] = -1; return -1 }
            scene.textures.append(t)
            cache[key] = scene.textures.count - 1
            return scene.textures.count - 1
        }
        m.albedoMap = tex(src.texture, linear: true)
        if m.albedoMap >= 0 { m.albedo = EPTVec(lin(src.color.r * 0.25 + 0.75), lin(src.color.g * 0.25 + 0.75), lin(src.color.b * 0.25 + 0.75)) }
        if let s = doc.variable("MATMAPS:" + name.uppercased()), let j = try? EngineJSON.parse(s) {
            m.normalMap = tex(j["normal"]?.stringValue, linear: false)
            m.normalStrength = Float(j["normalStrength"]?.doubleValue ?? 1)
            m.roughnessMap = tex(j["roughness"]?.stringValue, linear: false)
            m.metalMap = tex(j["metallic"]?.stringValue, linear: false)
            m.aoMap = tex(j["ao"]?.stringValue, linear: false)
            m.bumpMap = tex(j["displacement"]?.stringValue, linear: false)
            m.bumpStrength = Float(max(j["displacementScale"]?.doubleValue ?? 0, 0) / 10)
        }
        if m.normalMap < 0, m.bumpMap < 0, let t = src.texture {
            let bs = doc.variables["MATBUMP:" + name.uppercased()].flatMap(Double.init).map { max(0, min($0, 5)) } ?? 0.4
            if bs > 0 { m.bumpMap = tex(t, linear: false); m.bumpStrength = Float(bs) * 0.5 }
        }
        m.snow = Float(weather.snow); m.wet = Float(weather.wetness)
        return m
    }

    /// Kelvin → linear RGB of a black body (max 1).
    static func kelvinRGB(_ k: Double) -> EPTVec {
        let t = k / 100
        var r: Double, g: Double
        if t <= 66 { r = 255; g = 99.47 * log(t) - 161.12 } else { r = 329.7 * pow(t - 60, -0.1332); g = 288.1 * pow(t - 60, -0.0755) }
        let b: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5 * log(t - 10) - 305.04)
        func c(_ v: Double) -> Float { EPTTexture.srgbToLinear(Float(min(max(v, 0), 255) / 255)) }
        return EPTVec(c(r), c(g), c(b))
    }

    static func build(doc: ArchiDocument, camera: Camera?, options o: Options) -> (EPTScene, EPTCamera) {
        let scene = EPTScene()
        var cache: [String: Int] = [:]
        var matIndex: [String: Int] = [:]
        let weather = doc.variable(EngineWeather.variable).flatMap(EngineWeather.init(stored:)) ?? EngineWeather()
        let anims = EngineObjectAnimation.load(doc)
        for g in MeshBuilder.build(doc: doc) where !g.mesh.isEmpty {
            let mi: Int
            if let i = matIndex[g.material] { mi = i } else {
                scene.materials.append(material(g.material, doc: doc, scene: scene, cache: &cache, options: o, weather: weather))
                mi = scene.materials.count - 1
                matIndex[g.material] = mi
            }
            var mesh = g.mesh
            if o.lod > 0 && mesh.triangleCount > 0 {
                let lg = MeshLOD.build(g)
                mesh = lg.levels[min(o.lod, lg.levels.count - 1)]
            }
            let m = mapped(mesh, material: g.material, doc: doc)
            // Object animation at the render time (VIS-045): whole objects move; door leaves swing.
            if !anims.isEmpty, let parts = EngineObjectAnimation.meshes(m, group: g, anims: anims, doc: doc, time: o.time) {
                for part in parts { scene.add(part, material: mi) }
            } else {
                scene.add(m, material: mi)
            }
        }
        if o.ground {
            var gm = EPTMaterial()
            gm.albedo = EPTVec(0.32, 0.31, 0.29); gm.roughness = 0.95; gm.snow = Float(weather.snow); gm.wet = Float(weather.wetness); gm.name = "Ground"
            scene.materials.append(gm)
            scene.groundMaterial = scene.materials.count - 1
            let base = Float(doc.levels.map(\.elevation).min() ?? 0)
            scene.groundZ = scene.tris.isEmpty ? base : min(base, scene.boundsMin.z) - 1
        }
        scene.time = Float(o.time)
        scene.buildBVH()
        let info = doc.info
        let s = EngineOutputFormat.sun(day: o.day, hour: o.hour, latitude: info.latitude, longitude: info.longitude, tz: (info.longitude / 15).rounded())
        let dir = EngineOutputFormat.sunDirection(altitude: s.0, azimuth: s.1, north: info.northAngle)
        scene.environment = EPTEnvironment.preset(o.environment, sun: dir, altitude: s.0)
        let ei = Float(o.environmentIntensity / 1.3)
        scene.environment.zenith *= ei; scene.environment.horizon *= ei; scene.environment.ground *= ei
        if weather.kind == "Rain" || weather.kind == "Fog" || weather.kind == "Snow" {
            let k = Float(1 - 0.85 * weather.intensity)
            scene.environment.sunIrradiance *= k
            let grey = EPTVec(repeating: eptLum(scene.environment.horizon))
            scene.environment.zenith = scene.environment.zenith * k + grey * (1 - k)
        }
        for l in EngineMeshJSON.lights(doc).arrayValue ?? [] {
            guard let p = EngineOutputFormat.vec3(l["position"]) else { continue }
            let cd = Float((l["lumens"]?.doubleValue ?? 800) / (4 * .pi))
            let col = kelvinRGB(l["cct"]?.doubleValue ?? 3000)
            var pl = EPTPointLight(position: eptVec(p), intensity: col * cd, direction: nil, cosOuter: -1, cosInner: -1)
            let kind = l["kind"]?.stringValue ?? "point"
            if let t = EngineOutputFormat.vec3(l["target"]), kind == "spot" || kind == "ies" {
                let d = t - p
                if d.length > 1e-6 {
                    let beam = Float(l["beam"]?.doubleValue ?? 60)
                    pl.direction = eptNormalize(eptVec(d))
                    pl.cosOuter = cosf(beam * .pi / 360); pl.cosInner = cosf(beam * 0.7 * .pi / 360)
                    pl.intensity *= 2 / max(1 - pl.cosOuter, 0.05) / 2
                }
            }
            scene.lights.append(pl)
        }
        var cam: EPTCamera
        if let c = camera { cam = EPTCamera(c) } else {
            let c = (scene.boundsMin + scene.boundsMax) / 2
            let r = max(scene.sceneSize / 2, 1000)
            cam = EPTCamera(eye: c + eptNormalize(EPTVec(-1, -1.3, 0.8)) * r * 2.6, target: c, fovDegrees: 45)
        }
        return (scene, cam)
    }
}

// MARK: - Background job for the engine session

/// A path-trace render running on a background thread while the engine keeps answering requests.
final class EnginePathTraceJob: @unchecked Sendable {
    let session: EPTSession
    let target: Int
    let started = Date()
    private let lock = NSLock()
    private var cancelled = false
    private var finishedFlag = false
    var mix = EPTLightMix()
    var denoise = true
    var ev: Float = 0
    var triangles: Int { session.scene.tris.count }

    init(session: EPTSession, target: Int) { self.session = session; self.target = max(1, target) }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return finishedFlag }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    func start() {
        let t = Thread { [self] in
            for _ in 0..<target {
                if isCancelled { break }
                session.renderPass()
            }
            lock.lock(); finishedFlag = true; lock.unlock()
        }
        t.stackSize = 8 << 20
        t.start()
    }

    /// Runs `n` passes on the calling thread (files and tests).
    func runSync() {
        for _ in 0..<target { session.renderPass() }
        lock.lock(); finishedFlag = true; lock.unlock()
    }

    /// Tone-mapped RGB of the current state (denoised when finished or stopped, as the Mac window does).
    func image(final: Bool) -> [UInt8] {
        let s = session
        var hdr = s.compose(mix)
        if denoise && final {
            hdr = EPTDenoiser.denoise(color: hdr, albedo: s.meanAlbedo, normal: s.meanNormal, depth: s.meanDepth, width: s.width, height: s.height)
        }
        return EPTToneMap.rgb(hdr, ev: ev)
    }
}

// MARK: - Engine methods (Path Tracer window, PATHTRACE, LIGHTMIX, RENDERTOFILE passes)

extension EngineSession {
    /// The light mix stored in the drawing (LIGHTMIX = "sun,sky,artificial").
    func storedLightMix() -> EPTLightMix {
        var m = EPTLightMix()
        if let s = editor.doc.variable("LIGHTMIX") {
            let v = s.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            if v.count == 3 { m.sun = v[0]; m.sky = v[1]; m.artificial = v[2] }
        }
        return m
    }

    func pathTraceScene(_ p: EngineJSON) -> (EPTScene, EPTCamera) {
        var o = EPTSceneBuilder.Options()
        o.folder = editor.fileURL?.deletingLastPathComponent()
        if let e = p["environment"]?.stringValue { o.environment = e }
        if let v = p["environmentIntensity"]?.doubleValue { o.environmentIntensity = v }
        if let d = p["day"]?.intValue { o.day = min(max(d, 1), 366) }
        if let h = p["hour"]?.doubleValue { o.hour = h }
        if let c = p["clay"]?.boolValue { o.clay = c }
        if let g = p["ground"]?.boolValue { o.ground = g }
        if let l = p["lod"]?.intValue { o.lod = max(0, l) }
        if let t = p["time"]?.doubleValue { o.time = t }
        var cam: Camera? = p["camera"].flatMap { EngineOutputFormat.camera(from: $0) }
        if cam == nil, let name = p["cameraName"]?.stringValue { cam = editor.doc.namedViews.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.camera }
        if cam == nil { cam = view3d.camera }
        return EPTSceneBuilder.build(doc: editor.doc, camera: cam, options: o)
    }

    func pathTraceStart(_ p: EngineJSON) throws -> EngineJSON {
        output.tracer?.cancel()
        let w = p["width"]?.intValue ?? 960, h = p["height"]?.intValue ?? 540
        let spp = p["samples"]?.intValue ?? 64
        guard w >= 8, h >= 8, w <= 8192, h <= 8192, spp >= 1, spp <= 100_000 else { throw EngineError.params("Size 8–8192 px and 1+ samples.") }
        let (scene, cam) = pathTraceScene(p)
        var s = EPTSettings()
        s.width = w; s.height = h; s.camera = cam
        let job = EnginePathTraceJob(session: EPTSession(scene: scene, settings: s), target: spp)
        job.mix = storedLightMix()
        if let m = p["mix"] { job.mix = mix(from: m, base: job.mix) }
        job.denoise = p["denoise"]?.boolValue ?? true
        job.ev = Float(p["ev"]?.doubleValue ?? 0)
        output.tracer = job
        if p["sync"]?.boolValue == true { job.runSync() } else { job.start() }
        var o = EngineObject()
        o.set("triangles", scene.tris.count)
        o.set("lights", scene.lights.count)
        o.set("textures", scene.textures.count)
        o.set("width", w)
        o.set("height", h)
        o.set("target", spp)
        o.set("status", String(scene.tris.count) + " triangles, " + String(scene.lights.count) + " lights")
        return o.json
    }

    func mix(from j: EngineJSON, base: EPTLightMix) -> EPTLightMix {
        var m = base
        if let v = j["sun"]?.doubleValue { m.sun = Float(v) }
        if let v = j["sky"]?.doubleValue { m.sky = Float(v) }
        if let v = j["artificial"]?.doubleValue { m.artificial = Float(v) }
        return m
    }

    func pathTraceStatus(_ p: EngineJSON) throws -> EngineJSON {
        guard let job = output.tracer else {
            return .object([EngineJSONField("running", .bool(false)), EngineJSONField("samples", .int(0)), EngineJSONField("status", .string(""))])
        }
        if let m = p["mix"] { job.mix = mix(from: m, base: job.mix) }
        if let d = p["denoise"]?.boolValue { job.denoise = d }
        if let e = p["ev"]?.doubleValue { job.ev = Float(e) }
        let running = !job.finished && !job.isCancelled
        let secs = Date().timeIntervalSince(job.started)
        var o = EngineObject()
        o.set("running", running)
        o.set("samples", job.session.samples)
        o.set("target", job.target)
        o.set("seconds", secs)
        o.set("width", job.session.width)
        o.set("height", job.session.height)
        o.set("status", String(job.session.samples) + " samples · " + fmt(secs, 1) + " s · " + String(job.triangles) + " triangles")
        if p["image"]?.boolValue ?? true, job.session.samples > 0 {
            let px = job.image(final: !running)
            o.set("image", "data:image/png;base64," + EnginePNG.rgb(px, width: job.session.width, height: job.session.height).base64EncodedString())
        }
        return o.json
    }

    func pathTraceStop() -> EngineJSON {
        output.tracer?.cancel()
        return .object([EngineJSONField("stopped", .bool(true))])
    }

    func pathTraceSave(_ p: EngineJSON) throws -> EngineJSON {
        guard let job = output.tracer, job.session.samples > 0 else { throw EngineError.failed("Nothing rendered yet.") }
        let dest = url(try string(p, "path"))
        let px = job.image(final: true)
        do { try EnginePNG.rgb(px, width: job.session.width, height: job.session.height).write(to: dest) } catch { throw EngineError.failed("Cannot write " + dest.path + ".") }
        return .object([EngineJSONField("path", .string(dest.path))])
    }

    /// Light mix of the window (not stored; LIGHTMIX stores it in the drawing).
    func pathTraceMix(_ p: EngineJSON) throws -> EngineJSON {
        if let job = output.tracer { job.mix = mix(from: p, base: job.mix) }
        let m = output.tracer?.mix ?? storedLightMix()
        return .object([EngineJSONField("sun", .number(Double(m.sun))), EngineJSONField("sky", .number(Double(m.sky))), EngineJSONField("artificial", .number(Double(m.artificial)))])
    }

    /// Offline path-traced render to a PNG (PATHTRACE File): renders synchronously.
    func pathTraceFile(path: String, width: Int, height: Int, samples: Int, denoise: Bool) throws -> (Int, Double) {
        var p = EngineObject()
        p.set("width", width); p.set("height", height); p.set("samples", samples); p.set("denoise", denoise); p.set("sync", true)
        _ = try pathTraceStart(p.json)
        guard let job = output.tracer else { throw EngineError.failed("Could not make the image.") }
        let px = job.image(final: true)
        try EnginePNG.rgb(px, width: width, height: height).write(to: url(path))
        return (job.session.samples, Date().timeIntervalSince(job.started))
    }

    // MARK: Data passes (RENDERTOFILE Alpha, Depth, Normal, Material ID)

    /// Material → flat colour of the material ID pass (golden-ratio hues in material order, HSB 0.75 / 0.95).
    static func materialIDColors(_ doc: ArchiDocument) -> [(String, RGBA)] {
        var names = doc.materials.map(\.name)
        for g in MeshBuilder.build(doc: doc) where !names.contains(g.material) { names.append(g.material) }
        var out: [(String, RGBA)] = []
        for (i, n) in names.enumerated() {
            let hue = (Double(i) * 0.618034).truncatingRemainder(dividingBy: 1)
            out.append((n, EngineSession.hsb(hue, 0.75, 0.95)))
        }
        return out
    }
    static func hsb(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
        let i = Int(h * 6) % 6
        let f = h * 6 - floor(h * 6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return RGBA(v, t, p)
        case 1: return RGBA(q, v, p)
        case 2: return RGBA(p, v, t)
        case 3: return RGBA(p, q, v)
        case 4: return RGBA(t, p, v)
        default: return RGBA(v, p, q)
        }
    }

    /// `render.pass {pass, width, height, camera?, region?, path}`: a data pass by primary rays.
    func renderPass(_ p: EngineJSON) throws -> EngineJSON {
        let pass = p["pass"]?.stringValue ?? "Depth"
        guard ["Alpha", "Depth", "Normal", "Material ID", "MaterialID"].contains(pass) else { throw EngineError.params("pass Alpha, Depth, Normal or Material ID") }
        let W = p["width"]?.intValue ?? 1920, H = p["height"]?.intValue ?? 1080
        guard W >= 16, H >= 16, W <= 7680, H <= 4320 else { throw EngineError.failed("Use a size from 16x16 to 7680x4320.") }
        var q = EngineObject()
        for f in p.fields ?? [] { q.set(f.key, f.value) }
        q.set("ground", false)
        let (scene, cam) = pathTraceScene(q.json)
        var rx0 = 0, ry0 = 0, rw = W, rh = H
        if let r = p["region"]?.arrayValue?.compactMap(\.doubleValue), r.count == 4 {
            rx0 = Int((r[0] * Double(W)).rounded()); ry0 = Int((r[1] * Double(H)).rounded())
            rw = max(1, Int((r[2] * Double(W)).rounded()) - rx0); rh = max(1, Int((r[3] * Double(H)).rounded()) - ry0)
        }
        let doc = editor.doc
        var ids: [String: RGBA] = [:]
        for (n, c) in EngineSession.materialIDColors(doc) where ids[n] == nil { ids[n] = c }
        let center = (scene.boundsMin + scene.boundsMax) / 2
        let radius = max(scene.sceneSize / 2, 1)
        let dist = eptLength(cam.eye - center)
        let near = max(10, dist - radius), far = dist + radius
        let (f, r, u) = cam.basis
        let aspect = Float(W) / Float(H)
        var out = [UInt8](repeating: 0, count: rw * rh * 3)
        let stack = UnsafeMutablePointer<Int32>.allocate(capacity: 128)
        defer { stack.deallocate() }
        for y in 0..<rh {
            for x in 0..<rw {
                let (o, d) = cam.ray((Float(rx0 + x) + 0.5) / Float(W), (Float(ry0 + y) + 0.5) / Float(H), aspect: aspect)
                let i = (y * rw + x) * 3
                guard let hit = scene.intersect(o, d, stack: stack, ground: false), hit.tri >= 0 else { continue }
                var c = EPTVec.zero
                switch pass {
                case "Alpha": c = EPTVec(repeating: 1)
                case "Depth":
                    let z = hit.t * eptDot(d, f)
                    let v = 1 - min(max((z - near) / max(far - near, 1e-4), 0), 1)
                    c = EPTVec(repeating: v)
                case "Normal":
                    var n = scene.shade[hit.tri].ng
                    if eptDot(n, d) > 0 { n = -n }
                    c = EPTVec(eptDot(n, r), eptDot(n, u), -eptDot(n, f)) * 0.5 + EPTVec(repeating: 0.5)
                default:
                    let m = scene.materials[Int(scene.tris[hit.tri].mat)]
                    let col = ids[m.name] ?? RGBA(0.5, 0.5, 0.5)
                    c = EPTVec(Float(col.r), Float(col.g), Float(col.b))
                }
                out[i] = UInt8(max(0, min(255, (c.x * 255).rounded())))
                out[i + 1] = UInt8(max(0, min(255, (c.y * 255).rounded())))
                out[i + 2] = UInt8(max(0, min(255, (c.z * 255).rounded())))
            }
        }
        let dest = url(try string(p, "path"))
        do { try EnginePNG.rgb(out, width: rw, height: rh).write(to: dest) } catch { throw EngineError.failed("Cannot write " + dest.path + ".") }
        var o = EngineObject()
        o.set("path", dest.path)
        o.set("width", rw)
        o.set("height", rh)
        if pass.hasPrefix("Material") {
            var list: [EngineJSON] = []
            for (n, c) in EngineSession.materialIDColors(doc) { list.append(.object([EngineJSONField("name", .string(n)), EngineJSONField("color", .string(EngineOutputFormat.hex(c)))])) }
            o.set("materials", EngineJSON.array(list))
        }
        return o.json
    }
}
