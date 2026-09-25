// Oanarina Archi Tool — GPL-3.0-or-later
// Pure logic used by the app's animation, panorama, section-plane, plot-style and bump-map features.
// Foundation + ArchiCore only, so APPSELFTEST can check it without a window.
import Foundation
import ArchiCore

// MARK: - Camera path (walkthrough animation from saved cameras)

enum CameraPath {
    /// Centripetal-free uniform Catmull-Rom point on the segment p1→p2.
    static func catmullRom(_ p0: Vec3, _ p1: Vec3, _ p2: Vec3, _ p3: Vec3, _ u: Double) -> Vec3 {
        let u2 = u * u, u3 = u2 * u
        let a = p1 * 2
        let b = (p2 - p0) * u
        let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2
        let d = (p1 * 3 - p0 - p2 * 3 + p3) * u3
        return (a + b + c + d) * 0.5
    }

    /// Camera at parameter t ∈ [0, 1] along a smooth path through the key cameras (equal time per segment).
    /// Eye and target follow Catmull-Rom splines through the keys; the field of view is interpolated linearly.
    static func sample(_ keys: [Camera], t: Double) -> Camera? {
        guard let first = keys.first else { return nil }
        guard keys.count > 1 else { return first }
        let segs = Double(keys.count - 1)
        let x = min(max(t, 0), 1) * segs
        let i = min(Int(x), keys.count - 2)
        let u = x - Double(i)
        func at(_ k: Int) -> Camera { keys[min(max(k, 0), keys.count - 1)] }
        let eye = catmullRom(at(i - 1).eye, at(i).eye, at(i + 1).eye, at(i + 2).eye, u)
        let target = catmullRom(at(i - 1).target, at(i).target, at(i + 1).target, at(i + 2).target, u)
        let fov = at(i).fov + (at(i + 1).fov - at(i).fov) * u
        return Camera(eye: eye, target: target, fov: fov, orthographic: false)
    }

    /// Total eye path length (model units), sampled.
    static func length(_ keys: [Camera], samples: Int = 200) -> Double {
        guard keys.count > 1 else { return 0 }
        var l = 0.0, prev = keys[0].eye
        for s in 1...samples { let p = sample(keys, t: Double(s) / Double(samples))!.eye; l += (p - prev).length; prev = p }
        return l
    }
}

// MARK: - Equirectangular panorama from six cube faces

enum Panorama {
    /// Cube faces in SceneKit world space (Y up): viewing direction and up vector of each 90° camera.
    static let faces: [(front: Vec3, up: Vec3)] = [
        (Vec3(1, 0, 0), Vec3(0, 1, 0)), (Vec3(-1, 0, 0), Vec3(0, 1, 0)),
        (Vec3(0, 1, 0), Vec3(0, 0, 1)), (Vec3(0, -1, 0), Vec3(0, 0, -1)),
        (Vec3(0, 0, 1), Vec3(0, 1, 0)), (Vec3(0, 0, -1), Vec3(0, 1, 0)),
    ]

    /// Direction for an equirectangular pixel: u ∈ [0, 1) longitude (0.5 = -Z, the "forward" view), v ∈ [0, 1] from the zenith down.
    static func direction(u: Double, v: Double) -> Vec3 {
        let lon = (u - 0.5) * 2 * .pi, lat = (0.5 - v) * .pi
        return Vec3(cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
    }

    /// Face index and image coordinates (s right, t down, both 0…1) where a direction lands.
    static func lookup(_ d: Vec3) -> (face: Int, s: Double, t: Double) {
        var best = 0, bestDot = -Double.infinity
        for (i, f) in faces.enumerated() { let k = d.dot(f.front); if k > bestDot { bestDot = k; best = i } }
        let f = faces[best]
        let right = f.front.cross(f.up)
        let x = d.dot(right) / bestDot, y = d.dot(f.up) / bestDot
        return (best, min(max((x + 1) / 2, 0), 1), min(max((1 - y) / 2, 0), 1))
    }

    /// Resamples six square RGBA8 face buffers (size × size, row 0 at the top) into an equirectangular RGBA8 image.
    static func equirect(faces buf: [[UInt8]], faceSize n: Int, width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        guard buf.count == 6, n > 0 else { return out }
        for y in 0..<h {
            for x in 0..<w {
                let d = direction(u: (Double(x) + 0.5) / Double(w), v: (Double(y) + 0.5) / Double(h))
                let (fi, s, t) = lookup(d)
                let px = min(n - 1, Int(s * Double(n))), py = min(n - 1, Int(t * Double(n)))
                let src = (py * n + px) * 4, dst = (y * w + x) * 4
                let f = buf[fi]
                guard src + 3 < f.count else { continue }
                out[dst] = f[src]; out[dst + 1] = f[src + 1]; out[dst + 2] = f[src + 2]; out[dst + 3] = 255
            }
        }
        return out
    }
}

// MARK: - Section plane caps

enum SectionCap {
    /// Cut outlines (closed loops, model coordinates) of a triangle soup with the plane through `point` with normal `n`.
    static func loops(_ tris: [(Vec3, Vec3, Vec3)], point p0: Vec3, normal n0: Vec3, tolerance: Double = 1e-4) -> [[Vec3]] {
        let n = n0.normalized
        guard n.length > 0.5 else { return [] }
        func key(_ v: Vec3) -> [Int64] { [Int64((v.x / tolerance).rounded()), Int64((v.y / tolerance).rounded()), Int64((v.z / tolerance).rounded())] }
        var segs: [(Vec3, Vec3)] = []
        for (a, b, c) in tris {
            let da = (a - p0).dot(n), db = (b - p0).dot(n), dc = (c - p0).dot(n)
            var pts: [Vec3] = []
            for (u, du, v, dv) in [(a, da, b, db), (b, db, c, dc), (c, dc, a, da)] {
                if (du < 0 && dv > 0) || (du > 0 && dv < 0) { pts.append(u + (v - u) * (du / (du - dv))) }
                else if abs(du) < 1e-12 && abs(dv) >= 1e-12 { pts.append(u) }
            }
            // Deduplicate (a vertex on the plane is reported by two edges).
            var uniq: [Vec3] = []
            for q in pts where !uniq.contains(where: { key($0) == key(q) }) { uniq.append(q) }
            if uniq.count == 2 { segs.append((uniq[0], uniq[1])) }
        }
        // Chain segments by shared endpoints.
        var adj: [[Int64]: [Int]] = [:]
        for (i, s) in segs.enumerated() { adj[key(s.0), default: []].append(i); adj[key(s.1), default: []].append(i) }
        var used = [Bool](repeating: false, count: segs.count)
        var loops: [[Vec3]] = []
        for i in segs.indices where !used[i] {
            used[i] = true
            var loop = [segs[i].0, segs[i].1]
            var closed = false
            while true {
                let endKey = key(loop.last!)
                if endKey == key(loop[0]) && loop.count > 2 { loop.removeLast(); closed = true; break }
                guard let j = adj[endKey]?.first(where: { !used[$0] }) else { break }
                used[j] = true
                let s = segs[j]
                loop.append(key(s.0) == endKey ? s.1 : s.0)
            }
            if closed { loop = simplify(loop) }
            if closed && loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Removes collinear and repeated points from a closed loop (robust triangulation).
    static func simplify(_ l: [Vec3]) -> [Vec3] {
        var pts = l
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in pts.indices {
                let a = pts[(i + pts.count - 1) % pts.count], p = pts[i], b = pts[(i + 1) % pts.count]
                let u = p - a, v = b - p
                if u.length < 1e-9 || v.length < 1e-9 || u.cross(v).length <= 1e-9 * u.length * v.length {
                    pts.remove(at: i); changed = true; break
                }
            }
        }
        return pts
    }

    /// Triangulated cap faces (model coordinates) for the loops: nested loops alternate solid / hole (even-odd).
    static func triangles(_ loops: [[Vec3]], normal n0: Vec3) -> [(Vec3, Vec3, Vec3)] {
        let n = n0.normalized
        let (u, v) = Mesh.basis(n)
        let origin = loops.first?.first ?? .zero
        let flat = loops.map { l in l.map { q -> Vec2 in let d = q - origin; return Vec2(d.dot(u), d.dot(v)) } }
        func inside(_ p: Vec2, _ poly: [Vec2]) -> Bool {
            var c = false, j = poly.count - 1
            for i in 0..<poly.count {
                let a = poly[i], b = poly[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
                j = i
            }
            return c
        }
        let depth = flat.indices.map { i in flat.indices.filter { j in j != i && !flat[i].isEmpty && inside(flat[i][0], flat[j]) }.count }
        var out: [(Vec3, Vec3, Vec3)] = []
        for i in flat.indices where depth[i] % 2 == 0 {
            let holes = flat.indices.filter { j in depth[j] == depth[i] + 1 && inside(flat[j][0], flat[i]) }.map { flat[$0] }
            let r = Triangulator.triangulateWithPoints(flat[i], holes: holes)
            func back(_ q: Vec2) -> Vec3 { origin + u * q.x + v * q.y }
            for (a, b, c) in r.triangles { out.append((back(r.points[a]), back(r.points[b]), back(r.points[c]))) }
        }
        return out
    }
}

// MARK: - Plot style tables (colour-dependent, CTB-like)

/// A colour-dependent plot style table: each ACI colour maps to a pen (output colour, lineweight, screening).
struct PlotStyleTable: Codable, Hashable {
    struct Pen: Codable, Hashable {
        /// Output colour (0xRRGGBB); nil = use the object colour.
        var color: UInt32?
        /// Plotted lineweight in mm; nil = use the object lineweight.
        var lineweight: Double?
        /// Screening (ink intensity) in percent: 100 = full, 0 = white.
        var screening: Double = 100
        init(color: UInt32? = nil, lineweight: Double? = nil, screening: Double = 100) { self.color = color; self.lineweight = lineweight; self.screening = screening }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            color = try c.decodeIfPresent(UInt32.self, forKey: .color)
            lineweight = try c.decodeIfPresent(Double.self, forKey: .lineweight)
            screening = try c.decodeIfPresent(Double.self, forKey: .screening) ?? 100
        }
    }
    var name: String
    /// ACI index → pen. Index 0 is the pen for colours that are not ACI colours (true colours).
    var pens: [Int: Pen] = [:]

    static let variablePrefix = "PLOTSTYLE:"

    func pen(for c: RGBA) -> Pen? {
        if let i = PlotStyleTable.aciIndex(c), let p = pens[i] { return p }
        return pens[0]
    }

    /// Resolved plotted colour and lineweight for an object colour/lineweight.
    func resolve(color c: RGBA, lineweight w: Double) -> (RGBA, Double) {
        guard let p = pen(for: c) else { return (c, w) }
        var out = p.color.map { RGBA(Double($0 >> 16 & 255) / 255, Double($0 >> 8 & 255) / 255, Double($0 & 255) / 255, c.a) } ?? c
        let k = min(max(p.screening, 0), 100) / 100
        if k < 1 { out = RGBA(1 - (1 - out.r) * k, 1 - (1 - out.g) * k, 1 - (1 - out.b) * k, out.a) }
        return (out, p.lineweight ?? w)
    }

    /// The ACI index of an exact ACI colour (black counts as ACI 7, which plots black on paper), else nil.
    static func aciIndex(_ c: RGBA) -> Int? {
        func same(_ a: RGBA, _ b: RGBA) -> Bool { abs(a.r - b.r) < 0.004 && abs(a.g - b.g) < 0.004 && abs(a.b - b.b) < 0.004 }
        if c.r < 0.004 && c.g < 0.004 && c.b < 0.004 { return 7 }
        for i in 1...255 where same(aciColor(i), c) { return i }
        return nil
    }

    // Built-in tables.
    static let monochrome: PlotStyleTable = {
        var t = PlotStyleTable(name: "monochrome.ctb")
        for i in 0...255 { t.pens[i] = Pen(color: 0x000000) }
        return t
    }()
    static let grayscale: PlotStyleTable = {
        var t = PlotStyleTable(name: "grayscale.ctb")
        for i in 1...255 {
            let c = aciColor(i)
            let l = i == 7 ? 0 : min(0.75, 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
            let v = UInt32((l * 255).rounded())
            t.pens[i] = Pen(color: v << 16 | v << 8 | v)
        }
        return t
    }()
    /// Architectural pen table: ACI 1–9 plot black with graded lineweights (red thin … white/black heavy), 8/9 grey screened.
    static let archiPens: PlotStyleTable = {
        var t = PlotStyleTable(name: "archi pens.ctb")
        let w: [Int: Double] = [1: 0.13, 2: 0.18, 3: 0.25, 4: 0.35, 5: 0.50, 6: 0.70, 7: 0.25, 8: 0.13, 9: 0.09]
        for (i, lw) in w { t.pens[i] = Pen(color: 0x000000, lineweight: lw, screening: i == 8 ? 50 : (i == 9 ? 30 : 100)) }
        return t
    }()
    static let builtIn: [PlotStyleTable] = [monochrome, grayscale, archiPens]

    /// Built-in and document tables.
    static func all(_ doc: ArchiDocument) -> [PlotStyleTable] {
        let custom = doc.variables.filter { $0.key.hasPrefix(variablePrefix) }.sorted { $0.key < $1.key }
            .compactMap { try? JSONDecoder().decode(PlotStyleTable.self, from: Data($0.value.utf8)) }
        return builtIn.filter { b in !custom.contains { $0.name.lowercased() == b.name.lowercased() } } + custom
    }
    static func named(_ name: String?, in doc: ArchiDocument) -> PlotStyleTable? {
        guard let n = name?.lowercased(), !n.isEmpty else { return nil }
        return all(doc).first { $0.name.lowercased() == n }
    }
    func store(in doc: inout ArchiDocument) {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(self) { doc.variables[PlotStyleTable.variablePrefix + name.uppercased()] = String(decoding: d, as: UTF8.self) }
    }
}

// MARK: - Bump (normal) map from texture luminance

enum BumpMap {
    /// Tangent-space normal map (RGBA8, row 0 at the top) from a grey height map (0…1) with a Sobel filter.
    /// `strength` scales the slopes; 0 gives a flat map (128, 128, 255).
    static func normals(height hmap: [Double], width w: Int, height h: Int, strength: Double) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        guard w > 0, h > 0, hmap.count >= w * h else { return out }
        func hv(_ x: Int, _ y: Int) -> Double { hmap[((y % h + h) % h) * w + ((x % w + w) % w)] }   // wraps (tiling textures)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (hv(x + 1, y - 1) + 2 * hv(x + 1, y) + hv(x + 1, y + 1)) - (hv(x - 1, y - 1) + 2 * hv(x - 1, y) + hv(x - 1, y + 1))
                let dy = (hv(x - 1, y + 1) + 2 * hv(x, y + 1) + hv(x + 1, y + 1)) - (hv(x - 1, y - 1) + 2 * hv(x, y - 1) + hv(x + 1, y - 1))
                // Image rows go down, tangent-space +Y goes up: flip dy.
                let n = Vec3(-dx * strength, dy * strength, 1).normalized
                let i = (y * w + x) * 4
                out[i] = UInt8(max(0, min(255, ((n.x * 0.5 + 0.5) * 255).rounded())))
                out[i + 1] = UInt8(max(0, min(255, ((n.y * 0.5 + 0.5) * 255).rounded())))
                out[i + 2] = UInt8(max(0, min(255, ((n.z * 0.5 + 0.5) * 255).rounded())))
                out[i + 3] = 255
            }
        }
        return out
    }

    /// Per-material bump strength (document variable MATBUMP:<name>; default 0.4 for textured materials).
    static func strength(_ material: String, doc: ArchiDocument) -> Double {
        if let s = doc.variables["MATBUMP:" + material.uppercased()], let v = Double(s) { return max(0, min(v, 5)) }
        return 0.4
    }
}

// MARK: - Seeded random numbers (node graph)

/// Small deterministic generator (SplitMix64) so graphs evaluate identically every time.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

extension Vec3 {
    /// Component-wise closeness (app-side helper for checks).
    func isClose(_ o: Vec3, tol: Double) -> Bool { abs(x - o.x) <= tol && abs(y - o.y) <= tol && abs(z - o.z) <= tol }
}

// MARK: - Procedural physical sky (image-based lighting that follows the sun)

enum SkyModel {
    /// Linear RGB radiance-like colour of the sky in direction `d` (Y up) for a sun direction `sun` (Y up), 0…~4.
    /// A compact analytic model: Rayleigh-like zenith/horizon gradient that reddens and darkens as the sun sets,
    /// a Mie-like glow around the sun, a bright solar disc, and a darker ground below the horizon.
    static func color(_ d0: Vec3, sun s0: Vec3) -> (Double, Double, Double) {
        let d = d0.normalized, s = s0.normalized
        let alt = asin(max(-1, min(1, s.y)))
        let day = max(0, min(1, (alt + 0.1) / 0.35))              // 0 at night … 1 in daylight
        let warm = max(0, min(1, 1 - alt / 0.4))                    // low sun → warm horizon
        if d.y < 0 {
            let g = 0.18 * day + 0.02
            return (g * 1.05, g, g * 0.92)
        }
        let h = pow(1 - d.y, 3)                                      // 1 at the horizon, 0 at the zenith
        let zen = (0.18 * day + 0.01, 0.36 * day + 0.015, 0.78 * day + 0.04)
        let hor = (0.75 * day + 0.25 * warm * day + 0.03, 0.82 * day - 0.2 * warm * day + 0.03, 0.9 * day - 0.45 * warm * day + 0.05)
        var r = zen.0 + (hor.0 - zen.0) * h, g = zen.1 + (hor.1 - zen.1) * h, b = zen.2 + (hor.2 - zen.2) * h
        let cosA = max(-1, min(1, d.dot(s)))
        let angle = acos(cosA)
        let glow = exp(-angle * 4.5) * 0.9 * day
        r += glow * (1.0); g += glow * (0.85 - 0.25 * warm); b += glow * (0.65 - 0.35 * warm)
        if angle < 0.012 && s.y > -0.02 { r += 4; g += 3.6 * (1 - 0.3 * warm); b += 3.2 * (1 - 0.5 * warm) }   // solar disc
        return (r, g, b)
    }

    /// Equirectangular RGBA8 sky (tone-mapped), same pixel convention as `Panorama.direction`.
    static func equirect(sun: Vec3, width w: Int, height h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let d = Panorama.direction(u: (Double(x) + 0.5) / Double(w), v: (Double(y) + 0.5) / Double(h))
                let (r, g, b) = color(d, sun: sun)
                func tone(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (pow(v / (1 + v) * 1.6, 1 / 2.2) * 255).rounded()))) }
                let i = (y * w + x) * 4
                out[i] = tone(r); out[i + 1] = tone(g); out[i + 2] = tone(b)
            }
        }
        return out
    }
}
