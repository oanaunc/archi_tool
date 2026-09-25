// Oanarina Archi Tool — GPL-3.0-or-later
// Wavefront MTL materials (colour, opacity, shininess, diffuse texture maps) for OBJ import, and USD (USDA text, and
// USDZ packages holding USDA) mesh import with UsdPreviewSurface materials and textures.
import Foundation

public enum MTLReader {
    /// Parses MTL text. Texture maps (map_Kd) are resolved against `baseURL` and stored as absolute paths.
    /// Kd → colour, d / Tr → transparency, Ns (0–1000) → roughness, Pm / Ka-less metals → metalness.
    public static func materials(_ text: String, baseURL: URL? = nil) -> [Material] {
        var out: [Material] = []
        var cur: Material?
        func flush() { if let m = cur { out.append(m) }; cur = nil }
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let key = f.first?.lowercased() else { continue }
            let nums = f.dropFirst().compactMap { Double($0) }
            switch key {
            case "newmtl":
                flush()
                let name = f.dropFirst().joined(separator: " ")
                cur = Material(name: name.isEmpty ? "Material" : name, color: RGBA(0.8, 0.8, 0.8))
            case "kd":
                if nums.count >= 3 { cur?.color = RGBA(max(0, min(1, nums[0])), max(0, min(1, nums[1])), max(0, min(1, nums[2]))) }
            case "d":
                if let v = nums.last { cur?.transparency = max(0, min(1, 1 - v)) }
            case "tr":
                if let v = nums.last { cur?.transparency = max(0, min(1, v)) }
            case "ns":
                if let v = nums.first { cur?.roughness = max(0.02, min(1, 1 - sqrt(max(0, min(v, 1000)) / 1000))) }
            case "pr":
                if let v = nums.first { cur?.roughness = max(0, min(1, v)) }
            case "pm":
                if let v = nums.first { cur?.metalness = max(0, min(1, v)) }
            case "map_kd":
                // Options (-s u v w, -o …, -bm …) precede the file name: the name is the last token(s) after the options.
                var i = 1
                var scaleU: Double?
                while i < f.count, f[i].hasPrefix("-") {
                    let opt = f[i].lowercased()
                    let argc = ["-s": 3, "-o": 3, "-t": 3, "-mm": 2, "-bm": 1, "-boost": 1, "-texres": 1, "-clamp": 1, "-blendu": 1, "-blendv": 1, "-imfchan": 1, "-cc": 1][opt] ?? 1
                    if opt == "-s", i + 1 < f.count { scaleU = Double(f[i + 1]) }
                    i += 1
                    var k = 0
                    while k < argc, i < f.count, !f[i].hasPrefix("-") || Double(f[i]) != nil { i += 1; k += 1 }
                }
                guard i < f.count else { break }
                let file = f[i...].joined(separator: " ").replacingOccurrences(of: "\\", with: "/")
                let expanded = (file as NSString).expandingTildeInPath
                let path = expanded.hasPrefix("/") ? expanded : (baseURL?.appendingPathComponent(file).standardizedFileURL.path ?? file)
                cur?.texture = path
                // Texture repeat: -s u scales UVs; one tile per metre by default for imported models.
                if let s = scaleU, s > 0 { cur?.textureScale = 1000 / s }
            default: break
            }
        }
        flush()
        return out
    }

    /// "mtllib" file names referenced by OBJ text.
    public static func libraries(inOBJ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("mtllib") else { continue }
            let rest = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { out.append(rest) }
        }
        return out
    }

    /// OBJ file with its MTL libraries: mesh entities (props["material"]) and the materials they use.
    public static func importOBJ(_ url: URL, options: MeshImportOptions = .obj) throws -> (entities: [Entity], materials: [Material]) {
        let text = try FileImport.readText(url)
        let ents = try MeshImporter.obj(text, options: options)
        var mats: [Material] = []
        let dir = url.deletingLastPathComponent()
        for lib in libraries(inOBJ: text) {
            let u = lib.hasPrefix("/") ? URL(fileURLWithPath: lib) : dir.appendingPathComponent(lib)
            guard let t = try? FileImport.readText(u) else { continue }
            for m in materials(t, baseURL: u.deletingLastPathComponent()) where !mats.contains(where: { $0.name == m.name }) { mats.append(m) }
        }
        let used = Set(ents.compactMap { $0.props["material"] })
        return (ents, mats.filter { used.contains($0.name) })
    }
}

public enum USDImporter {
    public enum USDError: Error, LocalizedError {
        case binary, empty
        public var errorDescription: String? {
            switch self {
            case .binary: return "Binary USD (usdc) is not supported; export the file as USDA (text) or USDZ with a USDA layer."
            case .empty: return "No meshes found in the USD file."
            }
        }
    }

    /// Reads a .usda / .usd (text) or .usdz file: meshes (points, faceVertexCounts/Indices, xformOp translate/scale on
    /// the prim and its parents) become mesh solids in millimetres, Z up; UsdPreviewSurface materials become document
    /// materials (diffuse colour or texture, roughness, metallic, opacity). Textures inside a USDZ are extracted to
    /// `textureDirectory` (default: a folder next to the file).
    public static func read(_ url: URL, textureDirectory: URL? = nil) throws -> (entities: [Entity], materials: [Material]) {
        let data = try Data(contentsOf: url)
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            let entries = try ZipArchive.read(data)
            guard let layer = entries.first(where: { $0.name.lowercased().hasSuffix(".usda") || ($0.name.lowercased().hasSuffix(".usd") && $0.data.starts(with: Array("#usda".utf8))) }) else {
                throw USDError.binary
            }
            let dir = textureDirectory ?? url.deletingPathExtension().appendingPathExtension("textures")
            var files: [String: String] = [:]
            for e in entries where e.name != layer.name {
                let ext = (e.name as NSString).pathExtension.lowercased()
                guard ["png", "jpg", "jpeg"].contains(ext) else { continue }
                let out = dir.appendingPathComponent(e.name)
                try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try e.data.write(to: out, options: .atomic)
                files[e.name] = out.path
            }
            return try parse(String(decoding: layer.data, as: UTF8.self), assets: { files[$0] ?? dir.appendingPathComponent($0).path })
        }
        guard data.starts(with: Array("#usda".utf8)) else { throw USDError.binary }
        let base = url.deletingLastPathComponent()
        return try parse(String(decoding: data, as: UTF8.self), assets: { $0.hasPrefix("/") ? $0 : base.appendingPathComponent($0).path })
    }

    struct Prim {
        var type: String; var name: String; var path: String
        var translate = Vec3(0, 0, 0); var scale = Vec3(1, 1, 1)
        var points: [Vec3] = []; var counts: [Int] = []; var indices: [Int] = []
        var binding: String?
        var color: RGBA?; var roughness: Double?; var metallic: Double?; var opacity: Double?; var file: String?
        var colorConnect: String?
    }

    static func numbers(_ s: Substring) -> [Double] {
        var out: [Double] = []
        var cur = ""
        for ch in s {
            if ch.isNumber || ch == "." || ch == "-" || ch == "+" || ch == "e" || ch == "E" { cur.append(ch) }
            else { if let d = Double(cur) { out.append(d) }; cur = "" }
        }
        if let d = Double(cur) { out.append(d) }
        return out
    }

    /// Text of an attribute value: from "=" to the matching end of a [...] or (...) value (may span lines).
    static func value(_ lines: [Substring], _ i: inout Int, from line: Substring) -> Substring {
        guard let eq = line.firstIndex(of: "=") else { return "" }
        var v = line[line.index(after: eq)...]
        let trimmed = v.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.first, open == "[" || open == "(" else { return v }
        let close: Character = open == "[" ? "]" : ")"
        var depth = 0
        func balance(_ s: Substring) { for ch in s { if ch == open { depth += 1 } else if ch == close { depth -= 1 } } }
        balance(v)
        while depth > 0 && i + 1 < lines.count { i += 1; v += " " + lines[i]; balance(lines[i]) }
        return v
    }

    static func parse(_ text: String, assets: (String) -> String) throws -> (entities: [Entity], materials: [Material]) {
        var metersPerUnit = 0.01
        var zUp = false
        let lines = text.split(whereSeparator: { $0.isNewline })
        var stack: [Prim] = []
        var pendingPrim: Prim?
        var prims: [Prim] = []
        var i = 0
        var headerDone = false
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)[...]
            defer { i += 1 }
            if !headerDone {
                if line.hasPrefix("metersPerUnit") { metersPerUnit = numbers(line).first ?? metersPerUnit }
                if line.hasPrefix("upAxis") { zUp = line.contains("\"Z\"") }
                if line.hasPrefix("def ") || line.hasPrefix("over ") { headerDone = true } else { continue }
            }
            if line.hasPrefix("def ") || line.hasPrefix("over ") {
                let parts = line.split(separator: " ", maxSplits: 2)
                let type = parts.count >= 3 ? String(parts[1]) : ""
                let name = line.split(separator: "\"").dropFirst().first.map(String.init) ?? type
                let parent = stack.last?.path ?? ""
                pendingPrim = Prim(type: type, name: name, path: parent + "/" + name)
                if line.hasSuffix("{") { stack.append(pendingPrim!); pendingPrim = nil }
                continue
            }
            if line == "{" || line.hasSuffix(" {") && !line.contains("=") {
                if let p = pendingPrim { stack.append(p); pendingPrim = nil }
                continue
            }
            if line.hasPrefix("}") {
                if let p = stack.popLast() { prims.append(p); if !stack.isEmpty, p.type == "Shader" { mergeShader(p, into: &stack[stack.count - 1]) } }
                continue
            }
            guard !stack.isEmpty else { continue }
            var cur = stack[stack.count - 1]
            if line.contains("points =") && line.contains("point3f[]") {
                let n = numbers(value(lines, &i, from: line)); cur.points = stride(from: 0, to: n.count - 2, by: 3).map { Vec3(n[$0], n[$0 + 1], n[$0 + 2]) }
            } else if line.contains("faceVertexCounts") && line.contains("=") {
                cur.counts = numbers(value(lines, &i, from: line)).map { Int($0) }
            } else if line.contains("faceVertexIndices") && line.contains("=") {
                cur.indices = numbers(value(lines, &i, from: line)).map { Int($0) }
            } else if line.contains("xformOp:translate") && line.contains("=") {
                let n = numbers(value(lines, &i, from: line)); if n.count >= 3 { cur.translate = Vec3(n[0], n[1], n[2]) }
            } else if line.contains("xformOp:scale") && line.contains("=") {
                let n = numbers(value(lines, &i, from: line)); if n.count >= 3 { cur.scale = Vec3(n[0], n[1], n[2]) } else if n.count == 1 { cur.scale = Vec3(n[0], n[0], n[0]) }
            } else if line.contains("material:binding") && line.contains("<") {
                if let a = line.firstIndex(of: "<"), let b = line.lastIndex(of: ">"), a < b { cur.binding = String(line[line.index(after: a)..<b]) }
            } else if line.contains("inputs:diffuseColor.connect") {
                if let a = line.firstIndex(of: "<"), let b = line.lastIndex(of: ">"), a < b { cur.colorConnect = String(line[line.index(after: a)..<b]) }
            } else if line.contains("inputs:diffuseColor") && line.contains("=") {
                let n = numbers(value(lines, &i, from: line)); if n.count >= 3 { cur.color = RGBA(n[0], n[1], n[2]) }
            } else if line.contains("inputs:roughness") && line.contains("=") {
                cur.roughness = numbers(line.split(separator: "=").last ?? "").first
            } else if line.contains("inputs:metallic") && line.contains("=") {
                cur.metallic = numbers(line.split(separator: "=").last ?? "").first
            } else if line.contains("inputs:opacity") && line.contains("=") {
                cur.opacity = numbers(line.split(separator: "=").last ?? "").first
            } else if line.contains("inputs:file") && line.contains("@") {
                let parts = line.split(separator: "@", omittingEmptySubsequences: false)
                if parts.count >= 3 { cur.file = assets(String(parts[1])) }
            }
            stack[stack.count - 1] = cur
        }
        while let p = stack.popLast() { prims.append(p) }
        // Materials: a Material prim collects its shaders' inputs (merged when each shader closed).
        var materials: [Material] = []
        var matByPath: [String: String] = [:]
        for p in prims where p.type == "Material" {
            var m = Material(name: p.name, color: p.color ?? RGBA(0.8, 0.8, 0.8))
            if let r = p.roughness { m.roughness = max(0, min(1, r)) }
            if let r = p.metallic { m.metalness = max(0, min(1, r)) }
            if let o = p.opacity { m.transparency = max(0, min(1, 1 - o)) }
            if let f = p.file { m.texture = f }
            var n = m.name.hasPrefix("M_") ? String(m.name.dropFirst(2)) : m.name
            if n.isEmpty { n = "Material" }
            m.name = n
            materials.append(m)
            matByPath[p.path] = n
        }
        // Meshes in millimetres; transforms of the prim and its ancestors (translate then scale, innermost first).
        let byPath = Dictionary(prims.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let k = metersPerUnit * 1000
        var ents: [Entity] = []
        for p in prims where p.type == "Mesh" && !p.points.isEmpty {
            var chain: [Prim] = []
            var path = p.path
            while !path.isEmpty {
                if let q = byPath[path] { chain.append(q) }
                guard let cut = path.lastIndex(of: "/") else { break }
                path = String(path[..<cut])
            }
            func world(_ v: Vec3) -> Vec3 {
                var q = v
                for c in chain { q = Vec3(q.x * c.scale.x, q.y * c.scale.y, q.z * c.scale.z) + c.translate }
                q = q * k
                return zUp ? q : Vec3(q.x, -q.z, q.y)
            }
            let verts = p.points.map(world)
            var tris: [Int] = []
            var cursor = 0
            let counts = p.counts.isEmpty ? Array(repeating: 3, count: p.indices.count / 3) : p.counts
            for c in counts {
                guard c >= 3, cursor + c <= p.indices.count else { cursor += max(c, 0); continue }
                let f = Array(p.indices[cursor..<(cursor + c)])
                for j in 1..<(c - 1) where [f[0], f[j], f[j + 1]].allSatisfy({ $0 >= 0 && $0 < verts.count }) { tris += [f[0], f[j], f[j + 1]] }
                cursor += c
            }
            guard !tris.isEmpty else { continue }
            var props = ["name": p.name]
            if let b = p.binding, let m = matByPath[b] { props["material"] = m }
            ents.append(Entity(layer: "IMPORT-USD", geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: verts, meshTriangles: tris)), props: props))
        }
        if ents.isEmpty { throw USDError.empty }
        let used = Set(ents.compactMap { $0.props["material"] })
        return (ents, materials.filter { used.contains($0.name) })
    }

    /// Shader inputs belong to their Material: a texture reader's file becomes the material texture.
    static func mergeShader(_ s: Prim, into m: inout Prim) {
        if let c = s.color { m.color = c }
        if let r = s.roughness { m.roughness = r }
        if let r = s.metallic { m.metallic = r }
        if let o = s.opacity { m.opacity = o }
        if let f = s.file { m.file = f }
    }
}
