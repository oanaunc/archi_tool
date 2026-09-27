// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Shared helpers for 3D exchange formats. Meshes are in millimetres, Z up.
enum MeshExport {
    /// Model (mm, Z-up) → exchange space (m, Y-up).
    static func yUp(_ p: Vec3, unitMM: Double = 1) -> Vec3 { let k = unitMM / 1000; return Vec3(p.x * k, p.z * k, -p.y * k) }
    static func yUpNormal(_ n: Vec3) -> Vec3 { Vec3(n.x, n.z, -n.y) }

    static func safeName(_ s: String) -> String {
        let t = s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_" }
        return t.isEmpty ? "material" : String(t)
    }

    static func material(_ name: String, in list: [Material]) -> Material {
        list.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? Material(name: name.isEmpty ? "Default" : name, color: RGBA(0.8, 0.8, 0.8))
    }

    static func groupName(_ g: MeshGroup, index: Int) -> String {
        g.id.map { "\(safeName(g.kind))_\($0)" } ?? "\(safeName(g.kind))_\(index)"
    }

    /// Valid triangle indices (drops out-of-range and incomplete triangles).
    static func triangles(_ m: Mesh) -> [UInt32] {
        let n = UInt32(m.positions.count)
        var out: [UInt32] = []
        out.reserveCapacity(m.indices.count)
        var i = 0
        while i + 2 < m.indices.count {
            let a = m.indices[i], b = m.indices[i + 1], c = m.indices[i + 2]
            if a < n && b < n && c < n { out += [a, b, c] }
            i += 3
        }
        return out
    }

    static func num(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        return fmt(v, 6)
    }
}

public enum OBJExporter {
    /// Wavefront OBJ + MTL (metres, Y up). The OBJ has no `mtllib` line: the caller prepends
    /// `mtllib <name>.mtl` for the file name it chooses, or uses `export(_:materials:mtlFileName:)`.
    public static func export(_ groups: [MeshGroup], materials: [Material]) -> (obj: String, mtl: String) {
        export(groups, materials: materials, mtlFileName: nil)
    }

    public static func export(_ groups: [MeshGroup], materials: [Material], mtlFileName: String?) -> (obj: String, mtl: String) {
        export(groups, materials: materials, mtlFileName: mtlFileName, unitMM: 1)
    }

    /// `unitMM`: millimetres per drawing unit of the mesh positions (MeshBuilder works in drawing units).
    public static func export(_ groups: [MeshGroup], materials: [Material], mtlFileName: String?, unitMM: Double) -> (obj: String, mtl: String) {
        var obj = "# Oanarina Archi Tool OBJ export (units: metres, Y up)\n"
        if let m = mtlFileName { obj += "mtllib \(m)\n" }
        var used: [String] = []
        var vBase = 1, vtBase = 1, vnBase = 1
        let f = MeshExport.num
        for (gi, g) in groups.enumerated() {
            let m = g.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
            let hasN = m.normals.count == m.positions.count
            let hasT = m.uvs.count == m.positions.count
            obj += "o \(MeshExport.groupName(g, index: gi))\ng \(MeshExport.safeName(g.kind))\n"
            for p in m.positions { let q = MeshExport.yUp(p, unitMM: unitMM); obj += "v \(f(q.x)) \(f(q.y)) \(f(q.z))\n" }
            if hasT { for t in m.uvs { obj += "vt \(f(t.x)) \(f(t.y))\n" } }
            if hasN { for nn in m.normals { let q = MeshExport.yUpNormal(nn.normalized); obj += "vn \(f(q.x)) \(f(q.y)) \(f(q.z))\n" } }
            let mat = MeshExport.material(g.material, in: materials)
            let mname = MeshExport.safeName(mat.name)
            if !used.contains(mname) { used.append(mname) }
            obj += "usemtl \(mname)\n"
            var i = 0
            while i + 2 < tris.count {
                var face = "f"
                for k in 0..<3 {
                    let idx = Int(tris[i + k])
                    let v = vBase + idx
                    switch (hasT, hasN) {
                    case (true, true): face += " \(v)/\(vtBase + idx)/\(vnBase + idx)"
                    case (true, false): face += " \(v)/\(vtBase + idx)"
                    case (false, true): face += " \(v)//\(vnBase + idx)"
                    case (false, false): face += " \(v)"
                    }
                }
                obj += face + "\n"
                i += 3
            }
            vBase += m.positions.count
            if hasT { vtBase += m.uvs.count }
            if hasN { vnBase += m.normals.count }
        }
        var mtl = "# Oanarina Archi Tool MTL export\n"
        for name in used {
            let mat = materials.first { MeshExport.safeName($0.name) == name } ?? Material(name: name, color: RGBA(0.8, 0.8, 0.8))
            let c = mat.color
            let spec = 0.04 + 0.96 * mat.metalness * (1 - mat.roughness)
            let ns = max(1, min(1000, pow(2, (1 - mat.roughness) * 10)))
            mtl += "\nnewmtl \(name)\n"
            mtl += "Ka \(f(c.r * 0.2)) \(f(c.g * 0.2)) \(f(c.b * 0.2))\n"
            mtl += "Kd \(f(c.r)) \(f(c.g)) \(f(c.b))\n"
            mtl += "Ks \(f(spec)) \(f(spec)) \(f(spec))\n"
            mtl += "Ns \(f(ns))\n"
            let d = max(0, min(1, 1 - mat.transparency))
            mtl += "d \(f(d))\nTr \(f(1 - d))\n"
            mtl += "illum \(mat.transparency > 0 ? 4 : 2)\n"
            // PBR extension (understood by Blender and others)
            mtl += "Pr \(f(mat.roughness))\nPm \(f(mat.metalness))\n"
            if let tex = mat.texture, !tex.isEmpty {
                let s = mat.textureScale > 0 ? 1000 / mat.textureScale : 1
                mtl += "map_Kd -s \(f(s)) \(f(s)) 1 \(tex)\n"
            }
        }
        return (obj, mtl)
    }
}

public enum STLExporter {
    /// ASCII STL (millimetres, Z up — the usual 3D-printing convention).
    public static func export(_ groups: [MeshGroup], name: String) -> String {
        let solidName = MeshExport.safeName(name.isEmpty ? "model" : name)
        var out = "solid \(solidName)\n"
        let f = { (v: Double) -> String in
            guard v.isFinite else { return "0" }
            return String(format: "%.6e", v)
        }
        for g in groups {
            let m = g.mesh
            let tris = MeshExport.triangles(m)
            var i = 0
            while i + 2 < tris.count {
                let a = m.positions[Int(tris[i])], b = m.positions[Int(tris[i + 1])], c = m.positions[Int(tris[i + 2])]
                i += 3
                let n = (b - a).cross(c - a).normalized
                if n.length < 0.5 { continue } // degenerate
                out += "  facet normal \(f(n.x)) \(f(n.y)) \(f(n.z))\n    outer loop\n"
                for p in [a, b, c] { out += "      vertex \(f(p.x)) \(f(p.y)) \(f(p.z))\n" }
                out += "    endloop\n  endfacet\n"
            }
        }
        out += "endsolid \(solidName)\n"
        return out
    }
}

public enum GLTFExporter {
    /// glTF 2.0 binary (.glb): one node + mesh per group, PBR metallic-roughness materials, metres, Y up.
    public static func exportGLB(_ groups: [MeshGroup], materials: [Material]) -> Data { exportGLB(groups, materials: materials, unitMM: 1) }

    /// `unitMM`: millimetres per drawing unit of the mesh positions.
    public static func exportGLB(_ groups: [MeshGroup], materials: [Material], unitMM: Double) -> Data {
        exportGLB(groups, materials: materials, unitMM: unitMM, textureRoot: nil)
    }

    /// Reads a material's PNG/JPEG texture (absolute path, or relative to `root`, else to the working directory).
    static func textureData(_ m: Material, root: URL?) -> (data: Data, mime: String)? {
        guard let t = m.texture, !t.isEmpty else { return nil }
        let ext = (t as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else { return nil }
        let expanded = (t as NSString).expandingTildeInPath
        let url = PathSupport.isAbsolute(expanded) ? URL(fileURLWithPath: expanded) : (root ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent(t)
        guard let data = try? Data(contentsOf: url), ImageHeader.size(data) != nil else { return nil }
        return (data, ext == "png" ? "image/png" : "image/jpeg")
    }

    /// glTF 2.0 binary with the materials' textures embedded (images in the binary chunk, baseColorTexture, repeat
    /// sampler). Meshes without UVs get box-projected TEXCOORD_0 with one texture tile per `Material.textureScale` mm.
    public static func exportGLB(_ groups: [MeshGroup], materials: [Material], unitMM: Double, textureRoot: URL?) -> Data {
        var bin = Data()
        var images: [[String: Any]] = []
        var textures: [[String: Any]] = []
        var textureIndex: [String: Int] = [:]
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var meshes: [[String: Any]] = []
        var nodes: [[String: Any]] = []
        var mats: [[String: Any]] = []
        var matIndex: [String: Int] = [:]

        func align() { while bin.count % 4 != 0 { bin.append(0) } }
        func appendFloats(_ vals: [Float]) -> Int {
            align()
            let offset = bin.count
            var v = vals
            for i in v.indices { v[i] = Float(bitPattern: v[i].bitPattern.littleEndian) }
            v.withUnsafeBufferPointer { bin.append(Data(buffer: $0)) }
            return offset
        }
        func appendUInt32(_ vals: [UInt32]) -> Int {
            align()
            let offset = bin.count
            let v = vals.map { $0.littleEndian }
            v.withUnsafeBufferPointer { bin.append(Data(buffer: $0)) }
            return offset
        }
        func materialIndex(_ name: String) -> Int {
            let key = name.lowercased()
            if let i = matIndex[key] { return i }
            let m = MeshExport.material(name, in: materials)
            let alpha = max(0, min(1, 1 - m.transparency))
            var pbr: [String: Any] = [
                "baseColorFactor": [m.color.r, m.color.g, m.color.b, alpha].map { max(0, min(1, $0)) },
                "metallicFactor": max(0, min(1, m.metalness)),
                "roughnessFactor": max(0, min(1, m.roughness)),
            ]
            if let t = textureData(m, root: textureRoot) {
                align()
                let off = bin.count
                bin.append(t.data)
                bufferViews.append(["buffer": 0, "byteOffset": off, "byteLength": t.data.count])
                images.append(["bufferView": bufferViews.count - 1, "mimeType": t.mime, "name": MeshExport.safeName(m.name)])
                textures.append(["source": images.count - 1, "sampler": 0])
                textureIndex[key] = textures.count - 1
                pbr["baseColorTexture"] = ["index": textures.count - 1, "texCoord": 0]
                // The texture carries the colour: keep only the alpha of the base colour factor.
                pbr["baseColorFactor"] = [1.0, 1.0, 1.0, alpha]
            }
            var mat: [String: Any] = ["name": m.name, "pbrMetallicRoughness": pbr, "doubleSided": true]
            if alpha < 1 { mat["alphaMode"] = "BLEND" }
            pbr = [:]
            mats.append(mat)
            matIndex[key] = mats.count - 1
            return mats.count - 1
        }

        for (gi, g) in groups.enumerated() {
            let m = g.mesh
            let tris = MeshExport.triangles(m)
            guard !tris.isEmpty else { continue }
            var pos: [Float] = []; pos.reserveCapacity(m.positions.count * 3)
            var mn = Vec3(.infinity, .infinity, .infinity), mx = Vec3(-.infinity, -.infinity, -.infinity)
            for p in m.positions {
                let q = MeshExport.yUp(p, unitMM: unitMM)
                let fq = Vec3(Double(Float(q.x)), Double(Float(q.y)), Double(Float(q.z)))
                pos += [Float(q.x), Float(q.y), Float(q.z)]
                mn = Vec3(min(mn.x, fq.x), min(mn.y, fq.y), min(mn.z, fq.z)); mx = Vec3(max(mx.x, fq.x), max(mx.y, fq.y), max(mx.z, fq.z))
            }
            var attributes: [String: Int] = [:]
            let posOff = appendFloats(pos)
            bufferViews.append(["buffer": 0, "byteOffset": posOff, "byteLength": pos.count * 4, "target": 34962])
            accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5126, "count": m.positions.count, "type": "VEC3",
                              "min": [mn.x, mn.y, mn.z], "max": [mx.x, mx.y, mx.z]])
            attributes["POSITION"] = accessors.count - 1
            if m.normals.count == m.positions.count {
                var nrm: [Float] = []; nrm.reserveCapacity(pos.count)
                for n in m.normals {
                    var q = MeshExport.yUpNormal(n).normalized
                    if q.length < 0.5 { q = Vec3(0, 1, 0) }
                    nrm += [Float(q.x), Float(q.y), Float(q.z)]
                }
                let off = appendFloats(nrm)
                bufferViews.append(["buffer": 0, "byteOffset": off, "byteLength": nrm.count * 4, "target": 34962])
                accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5126, "count": m.normals.count, "type": "VEC3"])
                attributes["NORMAL"] = accessors.count - 1
            }
            let mi = materialIndex(g.material)
            var uvs = m.uvs
            if uvs.count != m.positions.count, textureIndex[g.material.lowercased()] != nil {
                // Box projection: the dominant normal axis picks the plane; one tile per textureScale mm.
                let mat = MeshExport.material(g.material, in: materials)
                let kk = unitMM / max(mat.textureScale, 1e-9)
                uvs = m.positions.enumerated().map { i, p in
                    let n = i < m.normals.count ? m.normals[i] : Vec3(0, 0, 1)
                    let ax = abs(n.x), ay = abs(n.y), az = abs(n.z)
                    let uv = az >= ax && az >= ay ? Vec2(p.x, p.y) : (ax >= ay ? Vec2(p.y, p.z) : Vec2(p.x, p.z))
                    return uv * kk
                }
            }
            if uvs.count == m.positions.count {
                var uv: [Float] = []; uv.reserveCapacity(uvs.count * 2)
                for t in uvs { uv += [Float(t.x), Float(1 - t.y)] }
                let off = appendFloats(uv)
                bufferViews.append(["buffer": 0, "byteOffset": off, "byteLength": uv.count * 4, "target": 34962])
                accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5126, "count": uvs.count, "type": "VEC2"])
                attributes["TEXCOORD_0"] = accessors.count - 1
            }
            let idxOff = appendUInt32(tris)
            bufferViews.append(["buffer": 0, "byteOffset": idxOff, "byteLength": tris.count * 4, "target": 34963])
            accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5125, "count": tris.count, "type": "SCALAR"])
            let prim: [String: Any] = ["attributes": attributes, "indices": accessors.count - 1, "material": mi, "mode": 4]
            let name = MeshExport.groupName(g, index: gi)
            meshes.append(["name": name, "primitives": [prim]])
            var node: [String: Any] = ["name": name, "mesh": meshes.count - 1]
            if let id = g.id { node["extras"] = ["archiId": id, "kind": g.kind, "material": g.material] }
            nodes.append(node)
        }
        align()

        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Oanarina Archi Tool"],
            "scene": 0,
            "scenes": [["name": "Model", "nodes": Array(0..<nodes.count)]],
        ]
        if !nodes.isEmpty {
            json["nodes"] = nodes; json["meshes"] = meshes; json["materials"] = mats
            json["accessors"] = accessors; json["bufferViews"] = bufferViews
            json["buffers"] = [["byteLength": bin.count]]
            if !images.isEmpty {
                json["images"] = images; json["textures"] = textures
                json["samplers"] = [["magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497]]
            }
        }
        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        var out = Data()
        func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { out.append(contentsOf: $0) } }
        let hasBin = !bin.isEmpty && !nodes.isEmpty
        let total = 12 + 8 + jsonData.count + (hasBin ? 8 + bin.count : 0)
        u32(0x4654_6C67) // "glTF"
        u32(2)
        u32(UInt32(total))
        u32(UInt32(jsonData.count)); u32(0x4E4F_534A) // "JSON"
        out.append(jsonData)
        if hasBin {
            u32(UInt32(bin.count)); u32(0x004E_4942) // "BIN\0"
            out.append(bin)
        }
        return out
    }
}
