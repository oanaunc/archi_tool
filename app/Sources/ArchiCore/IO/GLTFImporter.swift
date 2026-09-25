// Oanarina Archi Tool — GPL-3.0-or-later
// glTF 2.0 import (.gltf with embedded/external buffers, .glb binary) as mesh solids. Implements the glTF 2.0
// specification (Khronos): accessors, buffer views with stride, node hierarchy (matrix or TRS), triangle lists,
// strips and fans, base-colour materials. glTF is metres and Y-up; meshes become millimetres, Z-up.
import Foundation

public enum GLTFImporter {
    public enum GLTFError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid glTF: \(m)" }; return nil }
    }

    /// Mesh solids (one per mesh primitive instance) in drawing units (`scale` = drawing units per metre).
    /// `baseURL` resolves external buffer files of a .gltf.
    public static func entities(_ data: Data, baseURL: URL? = nil, scale: Double = 1000, layer: String = "IMPORT-GLTF") throws -> [Entity] {
        let bytes = [UInt8](data)
        var json: [String: Any]
        var glbBin: Data? = nil
        func u32(_ o: Int) -> Int { o + 3 < bytes.count ? Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 : 0 }
        if bytes.count >= 12 && u32(0) == 0x4654_6C67 {
            // GLB: header, then JSON and BIN chunks.
            var o = 12
            var j: Data? = nil
            while o + 8 <= bytes.count {
                let len = u32(o), type = u32(o + 4)
                let start = o + 8, end = min(bytes.count, start + len)
                if type == 0x4E4F_534A { j = data.subdata(in: start..<end) } else if type == 0x004E_4942 { glbBin = data.subdata(in: start..<end) }
                o = start + ((len + 3) & ~3)
            }
            guard let jd = j, let obj = try? JSONSerialization.jsonObject(with: jd) as? [String: Any] else { throw GLTFError.invalid("no JSON chunk") }
            json = obj
        } else {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GLTFError.invalid("not JSON") }
            json = obj
        }
        guard let asset = json["asset"] as? [String: Any], (asset["version"] as? String)?.hasPrefix("2") ?? false else {
            throw GLTFError.invalid("only glTF 2.0 is supported")
        }

        // Buffers
        let bufferDefs = json["buffers"] as? [[String: Any]] ?? []
        var buffers: [Data] = []
        for (i, b) in bufferDefs.enumerated() {
            if let uri = b["uri"] as? String {
                if uri.hasPrefix("data:") {
                    guard let comma = uri.firstIndex(of: ","), let d = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { throw GLTFError.invalid("bad data URI in buffer \(i)") }
                    buffers.append(d)
                } else {
                    let name = uri.removingPercentEncoding ?? uri
                    guard let base = baseURL, let d = try? Data(contentsOf: base.appendingPathComponent(name)) else { throw GLTFError.invalid("missing buffer file \(name)") }
                    buffers.append(d)
                }
            } else if i == 0, let b = glbBin { buffers.append(b) }
            else { buffers.append(Data()) }
        }
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

        /// Reads an accessor as rows of doubles.
        func read(_ index: Int) throws -> [[Double]] {
            guard index >= 0, index < accessors.count else { throw GLTFError.invalid("accessor \(index) out of range") }
            let a = accessors[index]
            let count = int(a["count"]) ?? 0
            let comps: Int
            switch a["type"] as? String ?? "SCALAR" { case "VEC2": comps = 2; case "VEC3": comps = 3; case "VEC4": comps = 4; case "MAT4": comps = 16; default: comps = 1 }
            let ct = int(a["componentType"]) ?? 5126
            let size: Int
            switch ct { case 5120, 5121: size = 1; case 5122, 5123: size = 2; default: size = 4 }
            let normalized = (a["normalized"] as? Bool) ?? false
            guard let bvi = int(a["bufferView"]) else { return Array(repeating: Array(repeating: 0, count: comps), count: count) } // sparse-only / zero
            guard bvi >= 0, bvi < views.count else { throw GLTFError.invalid("bufferView \(bvi) out of range") }
            let v = views[bvi]
            let bi = int(v["buffer"]) ?? 0
            guard bi < buffers.count else { throw GLTFError.invalid("buffer \(bi) missing") }
            let buf = buffers[bi]
            let base = (int(v["byteOffset"]) ?? 0) + (int(a["byteOffset"]) ?? 0)
            let stride = max(int(v["byteStride"]) ?? 0, comps * size)
            guard count == 0 || base + (count - 1) * stride + comps * size <= buf.count else { throw GLTFError.invalid("accessor \(index) exceeds its buffer") }
            var out: [[Double]] = []
            out.reserveCapacity(count)
            buf.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<count {
                    var row = [Double](repeating: 0, count: comps)
                    for c in 0..<comps {
                        let o = base + i * stride + c * size
                        let val: Double
                        switch ct {
                        case 5120: let x = Double(Int8(bitPattern: raw[o])); val = normalized ? max(x / 127, -1) : x
                        case 5121: let x = Double(raw[o]); val = normalized ? x / 255 : x
                        case 5122: let x = Double(Int16(bitPattern: UInt16(raw[o]) | UInt16(raw[o + 1]) << 8)); val = normalized ? max(x / 32767, -1) : x
                        case 5123: let x = Double(UInt16(raw[o]) | UInt16(raw[o + 1]) << 8); val = normalized ? x / 65535 : x
                        case 5125: val = Double(UInt32(raw[o]) | UInt32(raw[o + 1]) << 8 | UInt32(raw[o + 2]) << 16 | UInt32(raw[o + 3]) << 24)
                        default: val = Double(Float(bitPattern: UInt32(raw[o]) | UInt32(raw[o + 1]) << 8 | UInt32(raw[o + 2]) << 16 | UInt32(raw[o + 3]) << 24))
                        }
                        row[c] = val
                    }
                    out.append(row)
                }
            }
            return out
        }

        // Materials
        struct Mat { var name: String; var color: RGBA? }
        let mats: [Mat] = (json["materials"] as? [[String: Any]] ?? []).enumerated().map { i, m in
            let pbr = m["pbrMetallicRoughness"] as? [String: Any]
            let f = (pbr?["baseColorFactor"] as? [Any])?.compactMap(num)
            return Mat(name: (m["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Material \(i)", color: f.flatMap { $0.count >= 3 ? RGBA($0[0], $0[1], $0[2], $0.count > 3 ? $0[3] : 1) : nil })
        }

        // Nodes and world transforms (column-major 4x4).
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        typealias M4 = [Double]
        let identity: M4 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        func mul(_ a: M4, _ b: M4) -> M4 {
            var r = [Double](repeating: 0, count: 16)
            for c in 0..<4 { for rr in 0..<4 { var s = 0.0; for k in 0..<4 { s += a[k * 4 + rr] * b[c * 4 + k] }; r[c * 4 + rr] = s } }
            return r
        }
        func local(_ n: [String: Any]) -> M4 {
            if let m = (n["matrix"] as? [Any])?.compactMap(num), m.count == 16 { return m }
            let t = (n["translation"] as? [Any])?.compactMap(num) ?? [0, 0, 0]
            let q = (n["rotation"] as? [Any])?.compactMap(num) ?? [0, 0, 0, 1]
            let s = (n["scale"] as? [Any])?.compactMap(num) ?? [1, 1, 1]
            guard t.count == 3, q.count == 4, s.count == 3 else { return identity }
            let (x, y, z, w) = (q[0], q[1], q[2], q[3])
            let r: [Double] = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
                               2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
                               2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
                               0, 0, 0, 1]
            var m = r
            for c in 0..<3 { for rr in 0..<3 { m[c * 4 + rr] *= s[c] } }
            m[12] = t[0]; m[13] = t[1]; m[14] = t[2]
            return m
        }
        func apply(_ m: M4, _ p: [Double]) -> Vec3 {
            let x = p[0], y = p.count > 1 ? p[1] : 0, z = p.count > 2 ? p[2] : 0
            return Vec3(m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13], m[2] * x + m[6] * y + m[10] * z + m[14])
        }

        var roots: [Int] = []
        if let scenes = json["scenes"] as? [[String: Any]], !scenes.isEmpty {
            let si = int(json["scene"]) ?? 0
            roots = (scenes[min(max(si, 0), scenes.count - 1)]["nodes"] as? [Any])?.compactMap(int) ?? []
        } else {
            let children = Set(nodes.flatMap { ($0["children"] as? [Any])?.compactMap(int) ?? [] })
            roots = nodes.indices.filter { !children.contains($0) }
        }

        var out: [Entity] = []
        var visited = 0
        func visit(_ ni: Int, _ parent: M4, depth: Int) throws {
            guard ni >= 0, ni < nodes.count, depth < 64 else { return }
            visited += 1
            guard visited < 100_000 else { return }
            let n = nodes[ni]
            let world = mul(parent, local(n))
            if let mi = int(n["mesh"]), mi >= 0, mi < meshes.count {
                let mesh = meshes[mi]
                let meshName = (n["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (mesh["name"] as? String) ?? "mesh \(mi)"
                for prim in mesh["primitives"] as? [[String: Any]] ?? [] {
                    let mode = int(prim["mode"]) ?? 4
                    guard [4, 5, 6].contains(mode), let attrs = prim["attributes"] as? [String: Any], let pa = int(attrs["POSITION"]) else { continue }
                    let pos = try read(pa)
                    guard !pos.isEmpty else { continue }
                    var idx: [Int] = try int(prim["indices"]).map { try read($0).map { Int($0[0]) } } ?? Array(0..<pos.count)
                    idx = idx.filter { $0 >= 0 && $0 < pos.count }
                    var tris: [Int] = []
                    switch mode {
                    case 5: if idx.count >= 3 { for i in 0..<(idx.count - 2) { tris += i % 2 == 0 ? [idx[i], idx[i + 1], idx[i + 2]] : [idx[i + 1], idx[i], idx[i + 2]] } }
                    case 6: if idx.count >= 3 { for i in 1..<(idx.count - 1) { tris += [idx[0], idx[i], idx[i + 1]] } }
                    default: tris = Array(idx.prefix(idx.count / 3 * 3))
                    }
                    // Mirroring transforms flip the winding.
                    let det = world[0] * (world[5] * world[10] - world[9] * world[6]) - world[4] * (world[1] * world[10] - world[9] * world[2]) + world[8] * (world[1] * world[6] - world[5] * world[2])
                    if det < 0 { var k = 0; while k + 2 < tris.count { tris.swapAt(k + 1, k + 2); k += 3 } }
                    var clean: [Int] = []
                    var k = 0
                    while k + 2 < tris.count { let a = tris[k], b = tris[k + 1], c = tris[k + 2]; if a != b && b != c && a != c { clean += [a, b, c] }; k += 3 }
                    guard !clean.isEmpty else { continue }
                    // Compact, transform, Y-up → Z-up, metres → drawing units.
                    var remap: [Int: Int] = [:]
                    var verts: [Vec3] = []
                    var ti: [Int] = []
                    for i in clean {
                        if let j = remap[i] { ti.append(j); continue }
                        let w = apply(world, pos[i])
                        remap[i] = verts.count; ti.append(verts.count)
                        verts.append(Vec3(w.x, -w.z, w.y) * scale)
                    }
                    var props = ["name": meshName]
                    var color = ColorRef.byLayer
                    if let m = int(prim["material"]), m >= 0, m < mats.count {
                        props["material"] = mats[m].name
                        if let c = mats[m].color {
                            color = .rgb(UInt8(max(0, min(255, (c.r * 255).rounded()))), UInt8(max(0, min(255, (c.g * 255).rounded()))), UInt8(max(0, min(255, (c.b * 255).rounded()))))
                        }
                    }
                    if let ex = n["extras"] as? [String: Any], let kind = ex["kind"] as? String { props["kind"] = kind }
                    var e = Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: verts, meshTriangles: ti)), props: props)
                    e.color = color
                    out.append(e)
                }
            }
            for c in (n["children"] as? [Any])?.compactMap(int) ?? [] { try visit(c, world, depth: depth + 1) }
        }
        for r in roots { try visit(r, identity, depth: 0) }
        if out.isEmpty { throw MeshImportError.empty("glTF") }
        return out
    }
}
