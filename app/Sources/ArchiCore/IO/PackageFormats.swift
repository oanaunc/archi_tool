// Oanarina Archi Tool — GPL-3.0-or-later
// 3MF (3D Manufacturing Format core spec 1.3) export/import and USD (usda text / usdz package) export.
import Foundation

/// Welded triangle list of a mesh group (degenerate triangles removed).
struct WeldedMesh {
    var positions: [Vec3] = []
    var normals: [Vec3] = []
    var triangles: [Int] = []
    init(_ m: Mesh, weld: Bool, tolerance: Double = 1e-6) {
        let tris = MeshExport.triangles(m)
        var map: [Int: Int] = [:]
        var keyMap: [String: Int] = [:]
        let hasN = m.normals.count == m.positions.count
        func idx(_ i: Int) -> Int {
            if let j = map[i] { return j }
            let p = m.positions[i]
            if weld {
                let k = "\(Int((p.x / tolerance).rounded())),\(Int((p.y / tolerance).rounded())),\(Int((p.z / tolerance).rounded()))"
                if let j = keyMap[k] { map[i] = j; return j }
                keyMap[k] = positions.count
            }
            map[i] = positions.count
            positions.append(p)
            normals.append(hasN ? m.normals[i].normalized : Vec3(0, 0, 1))
            return positions.count - 1
        }
        var t = 0
        while t + 2 < tris.count {
            let a = idx(Int(tris[t])), b = idx(Int(tris[t + 1])), c = idx(Int(tris[t + 2]))
            t += 3
            if a != b && b != c && a != c { triangles += [a, b, c] }
        }
    }
}

public enum ThreeMFExporter {
    /// 3MF package (ZIP). `unitScale` = millimetres per model unit.
    public static func export(_ groups: [MeshGroup], materials: [Material], name: String = "Model", unitScale: Double = 1) -> Data {
        let model = modelXML(groups, materials: materials, name: name, unitScale: unitScale)
        let types = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>
        """
        return ZipArchive.write([
            .init(name: "[Content_Types].xml", data: Data(types.utf8)),
            .init(name: "_rels/.rels", data: Data(rels.utf8)),
            .init(name: "3D/3dmodel.model", data: Data(model.utf8)),
        ], compress: true)
    }

    public static func modelXML(_ groups: [MeshGroup], materials: [Material], name: String, unitScale: Double) -> String {
        let f = { (v: Double) -> String in MeshExport.num(v) }
        var matNames: [String] = []
        var objects = ""
        var items = ""
        var nextID = 2
        for (gi, g) in groups.enumerated() {
            let w = WeldedMesh(g.mesh, weld: true, tolerance: 1e-4)
            guard !w.triangles.isEmpty else { continue }
            let mat = MeshExport.material(g.material, in: materials)
            var pindex = matNames.firstIndex(of: mat.name) ?? -1
            if pindex < 0 { matNames.append(mat.name); pindex = matNames.count - 1 }
            let id = nextID; nextID += 1
            var s = "<object id=\"\(id)\" type=\"model\" name=\"\(SVGExporter.xml(MeshExport.groupName(g, index: gi)))\" pid=\"1\" pindex=\"\(pindex)\"><mesh><vertices>"
            for p in w.positions { let q = p * unitScale; s += "<vertex x=\"\(f(q.x))\" y=\"\(f(q.y))\" z=\"\(f(q.z))\"/>" }
            s += "</vertices><triangles>"
            var t = 0
            while t + 2 < w.triangles.count { s += "<triangle v1=\"\(w.triangles[t])\" v2=\"\(w.triangles[t + 1])\" v3=\"\(w.triangles[t + 2])\"/>"; t += 3 }
            s += "</triangles></mesh></object>\n"
            objects += s
            items += "<item objectid=\"\(id)\"/>"
        }
        var bm = "<basematerials id=\"1\">"
        for n in matNames {
            let m = MeshExport.material(n, in: materials)
            let a = Int((max(0, min(1, 1 - m.transparency)) * 255).rounded())
            bm += "<base name=\"\(SVGExporter.xml(n))\" displaycolor=\"\(m.color.hex)\(String(format: "%02X", a))\"/>"
        }
        if matNames.isEmpty { bm += "<base name=\"Default\" displaycolor=\"#CCCCCCFF\"/>" }
        bm += "</basematerials>\n"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
        <metadata name="Title">\(SVGExporter.xml(name))</metadata>
        <metadata name="Application">Oanarina Archi Tool</metadata>
        <resources>
        \(bm)\(objects)</resources>
        <build>\(items)</build>
        </model>

        """
    }
}

public enum ThreeMFImporter {
    /// Reads the model part of a 3MF package into mesh solids (drawing units = mm × `scale`).
    public static func entities(_ data: Data, layer: String = "IMPORT-3MF", scale: Double = 1) throws -> [Entity] {
        let entries = try ZipArchive.read(data)
        var modelPath = "3D/3dmodel.model"
        if let rels = entries.first(where: { $0.name == "_rels/.rels" }), let s = String(data: rels.data, encoding: .utf8),
           let r = s.range(of: "Target=\"") {
            let rest = s[r.upperBound...]
            if let e = rest.firstIndex(of: "\"") { modelPath = String(rest[..<e]).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        }
        guard let model = entries.first(where: { $0.name == modelPath }) ?? entries.first(where: { $0.name.hasSuffix(".model") }) else {
            throw MeshImportError.empty("3MF")
        }
        let d = ThreeMFParser()
        let p = XMLParser(data: model.data)
        p.delegate = d
        _ = p.parse()
        let k = d.unitMM * scale
        var out: [Entity] = []
        func emit(_ objID: String, _ m: [Double], depth: Int) {
            guard depth < 16, let o = d.objects[objID] else { return }
            if !o.tris.isEmpty {
                let v = o.verts.map { p -> Vec3 in
                    Vec3(m[0] * p.x + m[3] * p.y + m[6] * p.z + m[9], m[1] * p.x + m[4] * p.y + m[7] * p.z + m[10], m[2] * p.x + m[5] * p.y + m[8] * p.z + m[11]) * k
                }
                var props: [String: String] = [:]
                if !o.name.isEmpty { props["name"] = o.name }
                if let mat = o.material { props["material"] = mat }
                out.append(Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: v, meshTriangles: o.tris)), props: props))
            }
            for (cid, cm) in o.components { emit(cid, ThreeMFParser.compose(m, cm), depth: depth + 1) }
        }
        for (oid, m) in d.items { emit(oid, m, depth: 0) }
        if out.isEmpty { throw MeshImportError.empty("3MF") }
        return out
    }
}

final class ThreeMFParser: NSObject, XMLParserDelegate {
    struct Obj { var name = ""; var material: String?; var verts: [Vec3] = []; var tris: [Int] = []; var components: [(String, [Double])] = [] }
    var objects: [String: Obj] = [:]
    var items: [(String, [Double])] = []
    var unitMM = 1.0
    var cur: String?
    var baseMaterials: [String: [String]] = [:]
    var curBase: String?
    static let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]

    static func matrix(_ s: String?) -> [Double] {
        let v = (s ?? "").split(separator: " ").compactMap { Double($0) }
        return v.count == 12 ? v : identity
    }
    /// 3MF matrices are row-vector (p' = p·M); compose child-then-parent.
    static func compose(_ parent: [Double], _ child: [Double]) -> [Double] {
        func row(_ m: [Double], _ r: Int) -> [Double] { [m[r * 3], m[r * 3 + 1], m[r * 3 + 2]] }
        var out = [Double](repeating: 0, count: 12)
        for r in 0..<4 {
            let cr = row(child, r)
            for c in 0..<3 {
                out[r * 3 + c] = cr[0] * parent[c] + cr[1] * parent[3 + c] + cr[2] * parent[6 + c] + (r == 3 ? parent[9 + c] : 0)
            }
        }
        return out
    }

    func parser(_ parser: XMLParser, didStartElement name0: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        let name = name0.split(separator: ":").last.map(String.init) ?? name0
        switch name {
        case "model":
            switch (a["unit"] ?? "millimeter").lowercased() {
            case "micron": unitMM = 0.001
            case "centimeter": unitMM = 10
            case "inch": unitMM = 25.4
            case "foot": unitMM = 304.8
            case "meter": unitMM = 1000
            default: unitMM = 1
            }
        case "basematerials": curBase = a["id"]; if let b = curBase { baseMaterials[b] = [] }
        case "base": if let b = curBase { baseMaterials[b, default: []].append(a["name"] ?? "Material") }
        case "object":
            guard let id = a["id"] else { return }
            cur = id
            var o = Obj(name: a["name"] ?? "")
            if let pid = a["pid"], let list = baseMaterials[pid] { let i = Int(a["pindex"] ?? "0") ?? 0; if i >= 0 && i < list.count { o.material = list[i] } }
            objects[id] = o
        case "vertex":
            guard let c = cur else { return }
            objects[c]?.verts.append(Vec3(Double(a["x"] ?? "") ?? 0, Double(a["y"] ?? "") ?? 0, Double(a["z"] ?? "") ?? 0))
        case "triangle":
            guard let c = cur, let v1 = Int(a["v1"] ?? ""), let v2 = Int(a["v2"] ?? ""), let v3 = Int(a["v3"] ?? "") else { return }
            let n = objects[c]?.verts.count ?? 0
            if [v1, v2, v3].allSatisfy({ $0 >= 0 && $0 < n }) { objects[c]?.tris += [v1, v2, v3] }
        case "component":
            guard let c = cur, let oid = a["objectid"] else { return }
            objects[c]?.components.append((oid, ThreeMFParser.matrix(a["transform"])))
        case "item":
            if let oid = a["objectid"] { items.append((oid, ThreeMFParser.matrix(a["transform"]))) }
        default: break
        }
    }
    func parser(_ parser: XMLParser, didEndElement name0: String, namespaceURI: String?, qualifiedName: String?) {
        let name = name0.split(separator: ":").last.map(String.init) ?? name0
        if name == "object" { cur = nil }
        if name == "basematerials" { curBase = nil }
    }
}

public enum USDExporter {
    /// USD ASCII layer (Z up). `metersPerUnit` = size of one drawing unit in metres (0.001 for millimetres).
    public static func usda(_ groups: [MeshGroup], materials: [Material], metersPerUnit: Double = 0.001, name: String = "Model") -> String {
        usda(groups, materials: materials, metersPerUnit: metersPerUnit, name: name, textures: [:])
    }

    /// `textures`: material name → texture path inside the package; textured meshes get box-projected `st` coordinates
    /// with one texture tile per `Material.textureScale` millimetres.
    public static func usda(_ groups: [MeshGroup], materials: [Material], metersPerUnit: Double, name: String, textures: [String: String]) -> String {
        let f = { (v: Double) -> String in MeshExport.num(v) }
        var used: Set<String> = []
        func ident(_ s: String) -> String {
            var t = String(s.map { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII || $0 == "_" ? $0 : "_" })
            if t.isEmpty || t.first!.isNumber { t = "_" + t }
            var u = t, k = 1
            while used.contains(u) { u = "\(t)_\(k)"; k += 1 }
            used.insert(u)
            return u
        }
        let root = ident(name.isEmpty ? "Model" : name)
        var matIDs: [String: String] = [:]
        var matBlock = ""
        for g in groups where matIDs[g.material] == nil {
            let m = MeshExport.material(g.material, in: materials)
            let id = ident("M_" + m.name)
            matIDs[g.material] = id
            if let tex = textures[m.name] {
                matBlock += """
                    def Material "\(id)"
                    {
                        token outputs:surface.connect = </\(root)/Materials/\(id)/PBR.outputs:surface>
                        def Shader "PBR"
                        {
                            uniform token info:id = "UsdPreviewSurface"
                            color3f inputs:diffuseColor.connect = </\(root)/Materials/\(id)/Texture.outputs:rgb>
                            float inputs:roughness = \(f(m.roughness))
                            float inputs:metallic = \(f(m.metalness))
                            float inputs:opacity = \(f(max(0, min(1, 1 - m.transparency))))
                            token outputs:surface
                        }
                        def Shader "StReader"
                        {
                            uniform token info:id = "UsdPrimvarReader_float2"
                            token inputs:varname = "st"
                            float2 outputs:result
                        }
                        def Shader "Texture"
                        {
                            uniform token info:id = "UsdUVTexture"
                            asset inputs:file = @\(tex)@
                            float2 inputs:st.connect = </\(root)/Materials/\(id)/StReader.outputs:result>
                            token inputs:wrapS = "repeat"
                            token inputs:wrapT = "repeat"
                            float3 outputs:rgb
                        }
                    }

            """
                continue
            }
            matBlock += """
                    def Material "\(id)"
                    {
                        token outputs:surface.connect = </\(root)/Materials/\(id)/PBR.outputs:surface>
                        def Shader "PBR"
                        {
                            uniform token info:id = "UsdPreviewSurface"
                            color3f inputs:diffuseColor = (\(f(m.color.r)), \(f(m.color.g)), \(f(m.color.b)))
                            float inputs:roughness = \(f(m.roughness))
                            float inputs:metallic = \(f(m.metalness))
                            float inputs:opacity = \(f(max(0, min(1, 1 - m.transparency))))
                            token outputs:surface
                        }
                    }

            """
        }
        var meshes = ""
        for (gi, g) in groups.enumerated() {
            let w = WeldedMesh(g.mesh, weld: false)
            guard !w.triangles.isEmpty else { continue }
            let id = ident(MeshExport.groupName(g, index: gi))
            let m = MeshExport.material(g.material, in: materials)
            let pts = w.positions.map { "(\(f($0.x)), \(f($0.y)), \(f($0.z)))" }.joined(separator: ", ")
            let nrm = w.normals.map { "(\(f($0.x)), \(f($0.y)), \(f($0.z)))" }.joined(separator: ", ")
            let counts = Array(repeating: "3", count: w.triangles.count / 3).joined(separator: ", ")
            let idx = w.triangles.map(String.init).joined(separator: ", ")
            // Box projection: the dominant normal axis picks the plane; one tile per textureScale mm.
            var stLine = ""
            if textures[m.name] != nil {
                let k = metersPerUnit * 1000 / max(m.textureScale, 1e-9)
                var sts: [String] = []
                var t = 0
                while t + 2 < w.triangles.count {
                    let a = w.positions[w.triangles[t]], b = w.positions[w.triangles[t + 1]], c = w.positions[w.triangles[t + 2]]
                    let nn = (b - a).cross(c - a)
                    let ax = abs(nn.x), ay = abs(nn.y), az = abs(nn.z)
                    for p in [a, b, c] {
                        let uv = az >= ax && az >= ay ? (p.x, p.y) : (ax >= ay ? (p.y, p.z) : (p.x, p.z))
                        sts.append("(\(f(uv.0 * k)), \(f(uv.1 * k)))")
                    }
                    t += 3
                }
                let st = sts.joined(separator: ", ")
                stLine = "\n            texCoord2f[] primvars:st = [\(st)] (\n                interpolation = \"faceVarying\"\n            )"
            }
            meshes += """
                def Mesh "\(id)" (
                    prepend apiSchemas = ["MaterialBindingAPI"]
                )
                {
                    uniform bool doubleSided = 1
                    int[] faceVertexCounts = [\(counts)]
                    int[] faceVertexIndices = [\(idx)]
                    point3f[] points = [\(pts)]
                    normal3f[] normals = [\(nrm)] (
                        interpolation = "vertex"
                    )
                    color3f[] primvars:displayColor = [(\(f(m.color.r)), \(f(m.color.g)), \(f(m.color.b)))]\(stLine)
                    uniform token subdivisionScheme = "none"
                    rel material:binding = </\(root)/Materials/\(matIDs[g.material]!)>
                }

            """
        }
        return """
        #usda 1.0
        (
            defaultPrim = "\(root)"
            doc = "Oanarina Archi Tool"
            metersPerUnit = \(f(metersPerUnit))
            upAxis = "Z"
        )

        def Xform "\(root)" (
            kind = "component"
        )
        {
            def Scope "Materials"
            {
        \(matBlock)    }

        \(meshes)}

        """
    }

    /// USDZ package: an uncompressed ZIP whose single layer (model.usda) is 64-byte aligned.
    public static func usdz(_ groups: [MeshGroup], materials: [Material], metersPerUnit: Double = 0.001, name: String = "Model") -> Data {
        usdz(groups, materials: materials, metersPerUnit: metersPerUnit, name: name, textureRoot: nil)
    }

    /// USDZ with the PNG/JPEG textures of the used materials packaged under textures/ (paths absolute or relative to
    /// `textureRoot`); materials whose texture cannot be read keep their plain colour.
    public static func usdz(_ groups: [MeshGroup], materials: [Material], metersPerUnit: Double, name: String, textureRoot: URL?) -> Data {
        var textures: [String: String] = [:]
        var files: [ZipArchive.Entry] = []
        var usedNames = Set<String>()
        for mname in Set(groups.map(\.material)).sorted() {
            let m = MeshExport.material(mname, in: materials)
            guard textures[m.name] == nil, let t = m.texture, !t.isEmpty else { continue }
            let ext = (t as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg"].contains(ext) else { continue }
            let expanded = (t as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : (textureRoot ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).appendingPathComponent(t)
            guard let data = try? Data(contentsOf: url), ImageHeader.size(data) != nil else { continue }
            var n = "textures/" + MeshExport.safeName(m.name) + "." + ext
            while usedNames.contains(n) { n = "textures/" + MeshExport.safeName(m.name) + "_\(usedNames.count)." + ext }
            usedNames.insert(n)
            textures[m.name] = n
            files.append(.init(name: n, data: data))
        }
        let text = usda(groups, materials: materials, metersPerUnit: metersPerUnit, name: name, textures: textures)
        return ZipArchive.write([.init(name: "model.usda", data: Data(text.utf8))] + files, compress: false, align: 64)
    }
}
