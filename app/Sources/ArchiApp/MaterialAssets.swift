// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

// MARK: - PBR texture maps (VIS-061)

/// PBR maps of a material beyond its albedo texture (`Material.texture`): tangent-space normal, roughness, metallic,
/// ambient occlusion and displacement. Stored in the drawing as MATMAPS:<NAME> (JSON), paths absolute or relative to
/// the drawing folder like the albedo texture. Used by the Realistic viewport, SceneKit renders and the path tracer.
struct MaterialMaps: Codable, Equatable {
    var normal: String?
    var roughness: String?
    var metallic: String?
    var ao: String?
    var displacement: String?
    var normalStrength = 1.0
    /// Displacement height in millimetres (0 = bump only).
    var displacementScale = 0.0

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        normal = try c.decodeIfPresent(String.self, forKey: .normal)
        roughness = try c.decodeIfPresent(String.self, forKey: .roughness)
        metallic = try c.decodeIfPresent(String.self, forKey: .metallic)
        ao = try c.decodeIfPresent(String.self, forKey: .ao)
        displacement = try c.decodeIfPresent(String.self, forKey: .displacement)
        normalStrength = try c.decodeIfPresent(Double.self, forKey: .normalStrength) ?? 1
        displacementScale = try c.decodeIfPresent(Double.self, forKey: .displacementScale) ?? 0
    }

    var isEmpty: Bool { [normal, roughness, metallic, ao, displacement].allSatisfy { $0 == nil } }
    static let slots: [(title: String, key: WritableKeyPath<MaterialMaps, String?>)] =
        [("Normal", \.normal), ("Roughness", \.roughness), ("Metallic", \.metallic), ("AO", \.ao), ("Displacement", \.displacement)]

    static func key(_ material: String) -> String { "MATMAPS:" + material.uppercased() }
    static func load(_ material: String, doc: ArchiDocument) -> MaterialMaps {
        guard let s = doc.variable(key(material)), let m = try? JSONDecoder().decode(MaterialMaps.self, from: Data(s.utf8)) else { return MaterialMaps() }
        return m
    }
    static func store(_ m: MaterialMaps, material: String, in doc: inout ArchiDocument) {
        if m.isEmpty && m.normalStrength == 1 && m.displacementScale == 0 { doc.variables[key(material)] = nil; return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(m) { doc.setVariable(key(material), String(decoding: d, as: UTF8.self)) }
    }

    /// Applies the maps to a physically based SceneKit material (texture repeat and scale like the albedo).
    @MainActor static func apply(_ m: SCNMaterial, material src: ArchiCore.Material, doc: ArchiDocument) -> Bool {
        let maps = load(src.name, doc: doc)
        guard !maps.isEmpty else { return false }
        let k = CGFloat(1000 / max(src.textureScale, 1))
        func set(_ p: SCNMaterialProperty, _ path: String?, intensity: CGFloat = 1) {
            guard let img = MaterialTextures.image(path) else { return }
            p.contents = img
            p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear
            p.contentsTransform = SCNMatrix4MakeScale(k, k, 1)
            p.intensity = intensity
        }
        set(m.normal, maps.normal, intensity: CGFloat(max(0, maps.normalStrength)))
        set(m.roughness, maps.roughness)
        set(m.metalness, maps.metallic)
        set(m.ambientOcclusion, maps.ao)
        if maps.displacementScale > 0 { set(m.displacement, maps.displacement, intensity: CGFloat(maps.displacementScale)) }
        return true
    }

    /// Displacement needs a tessellated mesh in SceneKit.
    @MainActor static func tessellator(material: String, doc: ArchiDocument) -> SCNGeometryTessellator? {
        let maps = load(material, doc: doc)
        guard maps.displacement != nil, maps.displacementScale > 0 else { return nil }
        let t = SCNGeometryTessellator()
        t.edgeTessellationFactor = 16; t.insideTessellationFactor = 16
        t.isAdaptive = true; t.maximumEdgeLength = 0.05
        return t
    }
}

// MARK: - Material assets: identity, graphics, appearance, physical/thermal (VIS-068)

/// Revit-style material assets kept separately from the render appearance (`Material` colour/texture/PBR):
/// identity data for schedules, graphics used by the shaded/conceptual views and drafting, and physical/thermal
/// properties used by analysis. Stored as MATASSET:<NAME> (JSON; missing fields keep their defaults).
struct MaterialAssetSet: Codable, Equatable {
    // Identity
    var description = ""
    var manufacturer = ""
    var model = ""
    var mark = ""
    var keynote = ""
    var url = ""
    var cost: Double?
    // Graphics
    var useRenderAppearance = true
    var shadingColor: String?
    var surfacePattern: String?
    var cutColor: String?
    // Physical / thermal
    var density: Double?            // kg/m³
    var conductivity: Double?       // W/(m·K)
    var specificHeat: Double?       // J/(kg·K)
    var emissivity: Double?
    var compressiveStrength: Double? // MPa
    var youngsModulus: Double?       // GPa

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: k) ?? "" }
        description = try s(.description); manufacturer = try s(.manufacturer); model = try s(.model); mark = try s(.mark); keynote = try s(.keynote); url = try s(.url)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        useRenderAppearance = try c.decodeIfPresent(Bool.self, forKey: .useRenderAppearance) ?? true
        shadingColor = try c.decodeIfPresent(String.self, forKey: .shadingColor)
        surfacePattern = try c.decodeIfPresent(String.self, forKey: .surfacePattern)
        cutColor = try c.decodeIfPresent(String.self, forKey: .cutColor)
        density = try c.decodeIfPresent(Double.self, forKey: .density)
        conductivity = try c.decodeIfPresent(Double.self, forKey: .conductivity)
        specificHeat = try c.decodeIfPresent(Double.self, forKey: .specificHeat)
        emissivity = try c.decodeIfPresent(Double.self, forKey: .emissivity)
        compressiveStrength = try c.decodeIfPresent(Double.self, forKey: .compressiveStrength)
        youngsModulus = try c.decodeIfPresent(Double.self, forKey: .youngsModulus)
    }

    static func key(_ material: String) -> String { "MATASSET:" + material.uppercased() }

    /// Stored assets, or typical physical values for well-known material names.
    static func load(_ material: String, doc: ArchiDocument) -> MaterialAssetSet {
        if let s = doc.variable(key(material)), let a = try? JSONDecoder().decode(MaterialAssetSet.self, from: Data(s.utf8)) { return a }
        return defaults(for: material)
    }
    static func store(_ a: MaterialAssetSet, material: String, in doc: inout ArchiDocument) {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(a) { doc.setVariable(key(material), String(decoding: d, as: UTF8.self)) }
    }

    /// Typical physical/thermal properties (EN ISO 10456 order of magnitude) by material name.
    static func defaults(for name: String) -> MaterialAssetSet {
        var a = MaterialAssetSet()
        let n = name.lowercased()
        let table: [(String, Double, Double, Double, Double?)] = [
            ("concrete", 2400, 2.0, 1000, 30), ("brick", 1800, 0.77, 840, 20), ("plaster", 1200, 0.57, 1000, nil), ("gypsum", 900, 0.25, 1000, nil),
            ("wood", 500, 0.13, 1600, 24), ("timber", 500, 0.13, 1600, 24), ("glass", 2500, 1.0, 750, nil), ("steel", 7850, 50, 450, 355),
            ("aluminium", 2700, 160, 880, 200), ("stone", 2600, 2.3, 1000, 60), ("insulation", 30, 0.035, 1450, nil), ("tile", 2300, 1.3, 840, nil),
            ("water", 1000, 0.6, 4180, nil), ("grass", 1500, 1.5, 1800, nil), ("roof", 2000, 1.0, 800, nil),
        ]
        if let t = table.first(where: { n.contains($0.0) }) {
            a.density = t.1; a.conductivity = t.2; a.specificHeat = t.3; a.compressiveStrength = t.4
            a.emissivity = n.contains("aluminium") || n.contains("steel") ? 0.2 : 0.9
        }
        return a
    }

    /// Thermal resistance R = d / λ (m²K/W) of a layer of the given thickness (mm).
    func thermalResistance(thickness mm: Double) -> Double? {
        guard let k = conductivity, k > 0, mm > 0 else { return nil }
        return mm / 1000 / k
    }
    /// Mass per square metre (kg/m²) of a layer.
    func arealMass(thickness mm: Double) -> Double? { density.map { $0 * mm / 1000 } }

    /// Colour used by non-realistic views when the graphics asset does not follow the render appearance.
    static func shadingColor(_ material: String, doc: ArchiDocument) -> RGBA? {
        let a = load(material, doc: doc)
        guard !a.useRenderAppearance, let h = a.shadingColor, let c = RGBA(hexString: h) else { return nil }
        return c
    }
}

extension RGBA {
    /// Parses "#RRGGBB" / "RRGGBB".
    init?(hexString s: String) {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    var hexRGB: String { String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
}

// MARK: - Image helpers

enum MapImages {
    /// Writes RGBA8 pixels (row 0 at the top) as a PNG file.
    static func writePNG(_ rgba: [UInt8], width w: Int, height h: Int, to url: URL) throws {
        guard w > 0, h > 0, rgba.count == w * h * 4, let prov = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw CommandError.invalid("Could not encode the image.") }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CommandError.invalid("Could not encode the PNG.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }
    static func gray(_ v: [Double]) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: v.count * 4)
        for (i, x) in v.enumerated() { let b = UInt8(max(0, min(255, (x * 255).rounded()))); out[i * 4] = b; out[i * 4 + 1] = b; out[i * 4 + 2] = b }
        return out
    }
    /// RGBA8 pixels of an image file (row 0 at the top), scaled to at most `maxSize`.
    static func rgba(of url: URL, maxSize: Int = 1024) -> (px: [UInt8], w: Int, h: Int)? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        var r = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil) else { return nil }
        let s = min(1, Double(maxSize) / Double(max(cg.width, cg.height)))
        let w = max(1, Int(Double(cg.width) * s)), h = max(1, Int(Double(cg.height) * s))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { b in
            guard let ctx = CGContext(data: b.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        return ok ? (px, w, h) : nil
    }
    /// Box blur with wrap-around (separable, radius in pixels).
    static func blur(_ v: [Double], width w: Int, height h: Int, radius r: Int) -> [Double] {
        guard r > 0, w > 0, h > 0 else { return v }
        var tmp = v, out = v
        let k = Double(2 * r + 1)
        for y in 0..<h {
            var s = 0.0
            for x in -r...r { s += v[y * w + ((x % w) + w) % w] }
            for x in 0..<w {
                tmp[y * w + x] = s / k
                s += v[y * w + ((x + r + 1) % w)] - v[y * w + (((x - r) % w) + w) % w]
            }
        }
        for x in 0..<w {
            var s = 0.0
            for y in -r...r { s += tmp[(((y % h) + h) % h) * w + x] }
            for y in 0..<h {
                out[y * w + x] = s / k
                s += tmp[((y + r + 1) % h) * w + x] - tmp[(((y - r) % h) + h) % h * w + x]
            }
        }
        return out
    }
}

// MARK: - Procedural materials (VIS-066)

/// Seamless procedural textures with matching height and roughness maps: wood, brick, tile, marble, stone
/// (flagstone), concrete and terrazzo. The same parameters and seed always give the same pixels.
enum ProceduralMaterial {
    enum Kind: String, CaseIterable, Codable { case wood = "Wood", brick = "Brick", tile = "Tile", marble = "Marble", stone = "Stone", concrete = "Concrete", terrazzo = "Terrazzo" }

    struct Params: Codable, Equatable {
        var kind: Kind = .brick
        var color1 = RGBA(0.62, 0.30, 0.22)
        var color2 = RGBA(0.80, 0.78, 0.74)
        /// Real-world size of one texture tile (mm).
        var tileSize = 1000.0
        var rows = 8
        var columns = 4
        /// Joint (mortar/grout) width as a fraction of the tile.
        var joint = 0.012
        var variation = 0.12
        var seed: UInt64 = 1
        var pixels = 512

        init(kind: Kind = .brick) {
            self.kind = kind
            switch kind {
            case .wood: color1 = RGBA(0.62, 0.43, 0.26); color2 = RGBA(0.45, 0.29, 0.16); rows = 6; columns = 1; joint = 0.003; variation = 0.1
            case .brick: break
            case .tile: color1 = RGBA(0.90, 0.90, 0.88); color2 = RGBA(0.62, 0.62, 0.60); rows = 4; columns = 4; joint = 0.008; variation = 0.04; tileSize = 1200
            case .marble: color1 = RGBA(0.93, 0.92, 0.90); color2 = RGBA(0.45, 0.45, 0.48); rows = 1; columns = 1; joint = 0; variation = 0.05
            case .stone: color1 = RGBA(0.62, 0.59, 0.53); color2 = RGBA(0.40, 0.38, 0.35); rows = 5; columns = 5; joint = 0.015; variation = 0.15
            case .concrete: color1 = RGBA(0.70, 0.70, 0.68); color2 = RGBA(0.55, 0.55, 0.53); rows = 1; columns = 1; joint = 0; variation = 0.06
            case .terrazzo: color1 = RGBA(0.88, 0.87, 0.84); color2 = RGBA(0.35, 0.33, 0.32); rows = 1; columns = 1; joint = 0; variation = 0.25
            }
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            self.init(kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .brick)
            color1 = try c.decodeIfPresent(RGBA.self, forKey: .color1) ?? color1
            color2 = try c.decodeIfPresent(RGBA.self, forKey: .color2) ?? color2
            tileSize = try c.decodeIfPresent(Double.self, forKey: .tileSize) ?? tileSize
            rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? rows
            columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? columns
            joint = try c.decodeIfPresent(Double.self, forKey: .joint) ?? joint
            variation = try c.decodeIfPresent(Double.self, forKey: .variation) ?? variation
            seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? seed
            pixels = try c.decodeIfPresent(Int.self, forKey: .pixels) ?? pixels
        }
    }

    struct Maps { var albedo: [UInt8]; var height: [Double]; var roughness: [Double]; var size: Int }

    // Periodic value noise (period in lattice cells) so every map tiles.
    static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F ^ seed &* 0x165667B19E3779F9
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    static func noise(_ u: Double, _ v: Double, period p: Int, seed: UInt64) -> Double {
        let x = u * Double(p), y = v * Double(p)
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ i: Int, _ j: Int) -> Double { hash(((i % p) + p) % p, ((j % p) + p) % p, seed) }
        let a = h(x0, y0) * (1 - sx) + h(x0 + 1, y0) * sx
        let b = h(x0, y0 + 1) * (1 - sx) + h(x0 + 1, y0 + 1) * sx
        return a * (1 - sy) + b * sy
    }
    static func fbm(_ u: Double, _ v: Double, base: Int, octaves: Int = 4, seed: UInt64) -> Double {
        var s = 0.0, a = 0.5, p = base, norm = 0.0
        for o in 0..<octaves { s += a * noise(u, v, period: p, seed: seed &+ UInt64(o)); norm += a; a *= 0.5; p *= 2 }
        return s / norm
    }

    static func generate(_ p: Params) -> Maps {
        let n = max(16, min(p.pixels, 2048))
        var albedo = [UInt8](repeating: 255, count: n * n * 4)
        var height = [Double](repeating: 0, count: n * n)
        var rough = [Double](repeating: 0.8, count: n * n)
        let rows = max(1, p.rows), cols = max(1, p.columns), j = max(0, p.joint)
        func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> (Double, Double, Double) { (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t) }
        for y in 0..<n {
            for x in 0..<n {
                let u = (Double(x) + 0.5) / Double(n), v = (Double(y) + 0.5) / Double(n)
                var c: (Double, Double, Double) = (p.color1.r, p.color1.g, p.color1.b)
                var hgt = 0.5, r = 0.8
                let grain = fbm(u, v, base: 8, seed: p.seed)
                switch p.kind {
                case .brick, .tile:
                    let row = Int(v * Double(rows)) % rows
                    let off = p.kind == .brick && row % 2 == 1 ? 0.5 : 0
                    let cu = u * Double(cols) + off, cv = v * Double(rows)
                    let col = Int(floor(cu)) % cols
                    let fu = cu - floor(cu), fv = cv - floor(cv)
                    // Joint distance in tile units (aspect-corrected).
                    let du = min(fu, 1 - fu) / Double(cols), dv = min(fv, 1 - fv) / Double(rows)
                    let d = min(du, dv)
                    let tone = (hash(col, row, p.seed) - 0.5) * p.variation * 2
                    if d < j / 2 {
                        c = (p.color2.r, p.color2.g, p.color2.b); hgt = 0.1; r = 0.95
                        let k = (grain - 0.5) * 0.08; c = (c.0 + k, c.1 + k, c.2 + k)
                    } else {
                        let k = tone + (grain - 0.5) * p.variation
                        c = (p.color1.r + k, p.color1.g + k, p.color1.b + k * 0.9)
                        let bevel = min(1, (d - j / 2) / max(j, 0.002))
                        hgt = 0.35 + 0.55 * bevel + (grain - 0.5) * 0.1
                        r = p.kind == .tile ? 0.22 + grain * 0.1 : 0.82 + grain * 0.1
                    }
                case .wood:
                    let board = Int(v * Double(rows)) % rows
                    let bshift = hash(board, 7, p.seed)
                    let fv = v * Double(rows) - floor(v * Double(rows))
                    let warp = fbm(u, v, base: 4, seed: p.seed &+ 11) * 3
                    let ring = (fv * 3 + warp + bshift * 5 + u * 0.0).truncatingRemainder(dividingBy: 1)
                    let t = pow(abs(sin(ring * .pi)), 3) * 0.7 + (grain - 0.5) * 0.3
                    c = mix(p.color1, p.color2, max(0, min(1, t + (bshift - 0.5) * p.variation * 2)))
                    let seam = min(fv, 1 - fv) / Double(rows) < j / 2
                    if seam { c = (c.0 * 0.5, c.1 * 0.5, c.2 * 0.5); hgt = 0.2 } else { hgt = 0.6 - t * 0.2 }
                    r = 0.5 + t * 0.2
                case .marble:
                    let w = fbm(u, v, base: 4, octaves: 5, seed: p.seed) * 4
                    let vein = pow(1 - abs(sin((u * 2 + v * 1 + w) * .pi)), 12)
                    c = mix(p.color1, p.color2, min(1, vein * 0.9 + (grain - 0.5) * p.variation))
                    hgt = 0.5; r = 0.12 + vein * 0.1
                case .stone:
                    // Periodic Voronoi flagstones: cells = rows × columns jittered points; joints where F2 − F1 is small.
                    let gx = Double(cols), gy = Double(rows)
                    var f1 = 9.0, f2 = 9.0, cell = (0, 0)
                    let cx = Int(floor(u * gx)), cy = Int(floor(v * gy))
                    for oy in -1...1 { for ox in -1...1 {
                        let ix = cx + ox, iy = cy + oy
                        let wx = ((ix % cols) + cols) % cols, wy = ((iy % rows) + rows) % rows
                        let px = (Double(ix) + 0.15 + 0.7 * hash(wx, wy, p.seed)) / gx, py = (Double(iy) + 0.15 + 0.7 * hash(wx, wy, p.seed &+ 3)) / gy
                        let d = ((u - px) * (u - px) + (v - py) * (v - py)).squareRoot()
                        if d < f1 { f2 = f1; f1 = d; cell = (wx, wy) } else if d < f2 { f2 = d }
                    } }
                    let edge = (f2 - f1) / 2
                    let tone = (hash(cell.0, cell.1, p.seed &+ 5) - 0.5) * p.variation * 2
                    if edge < j { c = (p.color2.r, p.color2.g, p.color2.b); hgt = 0.1; r = 0.95 }
                    else { let k = tone + (grain - 0.5) * p.variation; c = (p.color1.r + k, p.color1.g + k, p.color1.b + k); hgt = 0.4 + min(1, (edge - j) / 0.02) * 0.4 + (grain - 0.5) * 0.15; r = 0.85 }
                case .concrete:
                    let k = (grain - 0.5) * p.variation * 2 + (fbm(u, v, base: 64, octaves: 2, seed: p.seed &+ 9) - 0.5) * 0.08
                    c = (p.color1.r + k, p.color1.g + k, p.color1.b + k)
                    // Small pores.
                    let pore = noise(u, v, period: 128, seed: p.seed &+ 21) > 0.93
                    hgt = pore ? 0.2 : 0.5 + (grain - 0.5) * 0.2; r = 0.88
                    if pore { c = (c.0 * 0.7, c.1 * 0.7, c.2 * 0.7) }
                case .terrazzo:
                    let chip = noise(u, v, period: 48, seed: p.seed &+ 31)
                    let k = (grain - 0.5) * 0.05
                    if chip > 0.72 {
                        let hue = hash(Int(u * 48), Int(v * 48), p.seed)
                        c = mix(p.color2, RGBA(0.72, 0.52, 0.40), hue)
                    } else { c = (p.color1.r + k, p.color1.g + k, p.color1.b + k) }
                    hgt = 0.5; r = 0.2
                }
                let i = y * n + x
                albedo[i * 4] = UInt8(max(0, min(255, (c.0 * 255).rounded())))
                albedo[i * 4 + 1] = UInt8(max(0, min(255, (c.1 * 255).rounded())))
                albedo[i * 4 + 2] = UInt8(max(0, min(255, (c.2 * 255).rounded())))
                height[i] = max(0, min(1, hgt)); rough[i] = max(0.02, min(1, r))
            }
        }
        return Maps(albedo: albedo, height: height, roughness: rough, size: n)
    }

    static func key(_ material: String) -> String { "MATPROC:" + material.uppercased() }

    /// Writes albedo, normal and roughness PNGs and adds (or updates) the material with its PBR maps.
    @MainActor static func create(_ p: Params, name: String, in doc: inout ArchiDocument) throws -> ArchiCore.Material {
        let maps = generate(p)
        guard let folder = PatternTextures.folder?.appendingPathComponent("Procedural", isDirectory: true) else { throw CommandError.invalid("No materials folder.") }
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let a = folder.appendingPathComponent(safe + "_albedo.png"), nm = folder.appendingPathComponent(safe + "_normal.png"), r = folder.appendingPathComponent(safe + "_roughness.png")
        try MapImages.writePNG(maps.albedo, width: maps.size, height: maps.size, to: a)
        try MapImages.writePNG(BumpMap.normals(height: maps.height, width: maps.size, height: maps.size, strength: 3), width: maps.size, height: maps.size, to: nm)
        try MapImages.writePNG(MapImages.gray(maps.roughness.map { $0 / 2 }), width: maps.size, height: maps.size, to: r)
        let meanR = maps.roughness.reduce(0, +) / Double(max(maps.roughness.count, 1))
        var m = doc.material(name) ?? ArchiCore.Material(name: name, color: RGBA(1, 1, 1))
        m.color = RGBA(1, 1, 1); m.texture = a.path; m.textureScale = max(1, p.tileSize); m.roughness = min(1, max(0.02, meanR))
        if p.kind == .brick { m.cutPattern = "ANSI31" } else if p.kind == .concrete { m.cutPattern = "AR-CONC" } else if p.kind == .wood { m.cutPattern = "ANSI32" }
        if let i = doc.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.materials[i] = m } else { doc.materials.append(m) }
        var mm = MaterialMaps.load(name, doc: doc)
        mm.normal = nm.path; mm.roughness = r.path
        MaterialMaps.store(mm, material: name, in: &doc)
        if let d = try? JSONEncoder().encode(p) { doc.setVariable(key(name), String(decoding: d, as: UTF8.self)) }
        return m
    }
}

// MARK: - Material from a photo (VIS-067)

/// Turns a photo of a surface into a tileable PBR material: large-scale lighting is removed from the albedo
/// ("de-lighting"), the image is made seamless by cross-blending with a half-offset copy, and height, normal,
/// roughness and ambient-occlusion maps are derived from the de-lit luminance.
enum PhotoMaterial {
    struct Result {
        var albedo: [UInt8]; var normal: [UInt8]; var roughness: [Double]; var ao: [Double]; var height: [Double]
        var width: Int; var heightPx: Int; var meanColor: RGBA; var meanRoughness: Double
    }

    static func luminance(_ px: [UInt8], _ i: Int) -> Double { (0.2126 * Double(px[i * 4]) + 0.7152 * Double(px[i * 4 + 1]) + 0.0722 * Double(px[i * 4 + 2])) / 255 }

    static func derive(rgba px0: [UInt8], width w: Int, height h: Int, delight: Double = 1, seamless: Bool = true) -> Result {
        let n = w * h
        var px = px0
        // Seamless: blend towards the half-offset image near the borders.
        if seamless && w > 8 && h > 8 {
            for y in 0..<h { for x in 0..<w {
                let fx = abs(Double(x) / Double(w - 1) - 0.5) * 2, fy = abs(Double(y) / Double(h - 1) - 0.5) * 2
                let t = max(0, min(1, (max(fx, fy) - 0.6) / 0.4))
                let s = t * t * (3 - 2 * t)
                let j = ((y + h / 2) % h) * w + (x + w / 2) % w, i = y * w + x
                for c in 0..<3 { px[i * 4 + c] = UInt8(max(0, min(255, (Double(px0[i * 4 + c]) * (1 - s) + Double(px0[j * 4 + c]) * s).rounded()))) }
            } }
        }
        let lum = (0..<n).map { luminance(px, $0) }
        let meanL = max(lum.reduce(0, +) / Double(max(n, 1)), 1e-4)
        let low = MapImages.blur(lum, width: w, height: h, radius: max(1, min(w, h) / 8))
        var albedo = px
        var delit = lum
        var sum = (0.0, 0.0, 0.0)
        for i in 0..<n {
            let k = pow(meanL / max(low[i], 0.02), max(0, min(delight, 1)))
            for c in 0..<3 { albedo[i * 4 + c] = UInt8(max(0, min(255, (Double(px[i * 4 + c]) * k).rounded()))) }
            albedo[i * 4 + 3] = 255
            delit[i] = min(1, lum[i] * k)
            sum.0 += Double(albedo[i * 4]); sum.1 += Double(albedo[i * 4 + 1]); sum.2 += Double(albedo[i * 4 + 2])
        }
        // Height from de-lit luminance, normalized to 0…1.
        let lo = delit.min() ?? 0, hi = delit.max() ?? 1
        let height = delit.map { hi - lo > 1e-6 ? ($0 - lo) / (hi - lo) : 0.5 }
        let normal = BumpMap.normals(height: height, width: w, height: h, strength: 2)
        let hb = MapImages.blur(height, width: w, height: h, radius: max(1, min(w, h) / 64))
        let ao = (0..<n).map { max(0.2, min(1, 1 - (hb[$0] - height[$0]) * 3)) }
        let rough = (0..<n).map { max(0.05, min(1, 0.95 - 0.45 * height[$0])) }
        let d = Double(max(n, 1)) * 255
        return Result(albedo: albedo, normal: normal, roughness: rough, ao: ao, height: height, width: w, heightPx: h,
                      meanColor: RGBA(sum.0 / d, sum.1 / d, sum.2 / d), meanRoughness: rough.reduce(0, +) / Double(max(n, 1)))
    }

    /// Creates the material (albedo texture + normal/roughness/AO maps) from an image file.
    @MainActor static func create(from url: URL, name: String, tileSize: Double, in doc: inout ArchiDocument) throws -> ArchiCore.Material {
        guard let (px, w, h) = MapImages.rgba(of: url, maxSize: 1024) else { throw CommandError.invalid("Could not read the image \(url.lastPathComponent).") }
        let r = derive(rgba: px, width: w, height: h)
        guard let folder = PatternTextures.folder?.appendingPathComponent("Photo", isDirectory: true) else { throw CommandError.invalid("No materials folder.") }
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let a = folder.appendingPathComponent(safe + "_albedo.png"), nm = folder.appendingPathComponent(safe + "_normal.png")
        let ro = folder.appendingPathComponent(safe + "_roughness.png"), ao = folder.appendingPathComponent(safe + "_ao.png")
        try MapImages.writePNG(r.albedo, width: w, height: h, to: a)
        try MapImages.writePNG(r.normal, width: w, height: h, to: nm)
        try MapImages.writePNG(MapImages.gray(r.roughness.map { $0 / 2 }), width: w, height: h, to: ro)
        try MapImages.writePNG(MapImages.gray(r.ao), width: w, height: h, to: ao)
        var m = doc.material(name) ?? ArchiCore.Material(name: name, color: RGBA(1, 1, 1))
        m.color = RGBA(1, 1, 1); m.texture = a.path; m.textureScale = max(1, tileSize); m.roughness = r.meanRoughness
        if let i = doc.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.materials[i] = m } else { doc.materials.append(m) }
        var mm = MaterialMaps.load(name, doc: doc)
        mm.normal = nm.path; mm.roughness = ro.path; mm.ao = ao.path
        MaterialMaps.store(mm, material: name, in: &doc)
        var asset = MaterialAssetSet.load(name, doc: doc)
        asset.shadingColor = r.meanColor.hexRGB
        if asset.description.isEmpty { asset.description = "From photo " + url.lastPathComponent }
        MaterialAssetSet.store(asset, material: name, in: &doc)
        return m
    }
}
