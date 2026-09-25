// Oanarina Archi Tool — GPL-3.0-or-later
// COLLADA 1.4.1 (Khronos) export/import of triangle meshes, and CityJSON 1.x (cityjson.org) city model import.
import Foundation

public enum ColladaExporter {
    /// COLLADA document: one geometry + node per mesh group, Phong materials from the model's materials, metres, Z up.
    public static func export(_ groups: [MeshGroup], materials: [Material], unitMM: Double = 1) -> String {
        func e(_ s: String) -> String { XLSX.esc(s) }
        var usedMats: [String: String] = [:]
        var geoms: [String] = [], nodes: [String] = []
        for (gi, g) in groups.enumerated() {
            let tris = MeshExport.triangles(g.mesh)
            guard !tris.isEmpty else { continue }
            let id = "g\(gi)"
            let mat = MeshExport.material(g.material, in: materials)
            let mid = "m-" + MeshExport.safeName(mat.name)
            usedMats[mid] = mat.name
            let pos = g.mesh.positions.flatMap { [$0.x, $0.y, $0.z] }.map { fmt($0 * unitMM / 1000, 6) }.joined(separator: " ")
            var gx = "<geometry id=\"\(id)\" name=\"\(e(MeshExport.groupName(g, index: gi)))\"><mesh>"
            gx += "<source id=\"\(id)-pos\"><float_array id=\"\(id)-pos-a\" count=\"\(g.mesh.positions.count * 3)\">\(pos)</float_array>"
            gx += "<technique_common><accessor source=\"#\(id)-pos-a\" count=\"\(g.mesh.positions.count)\" stride=\"3\"><param name=\"X\" type=\"float\"/><param name=\"Y\" type=\"float\"/><param name=\"Z\" type=\"float\"/></accessor></technique_common></source>"
            gx += "<vertices id=\"\(id)-vtx\"><input semantic=\"POSITION\" source=\"#\(id)-pos\"/></vertices>"
            gx += "<triangles count=\"\(tris.count / 3)\" material=\"mat\"><input semantic=\"VERTEX\" source=\"#\(id)-vtx\" offset=\"0\"/><p>\(tris.map(String.init).joined(separator: " "))</p></triangles>"
            gx += "</mesh></geometry>"
            geoms.append(gx)
            nodes.append("<node id=\"n\(gi)\" name=\"\(e(MeshExport.groupName(g, index: gi)))\"><instance_geometry url=\"#\(id)\"><bind_material><technique_common><instance_material symbol=\"mat\" target=\"#\(mid)\"/></technique_common></bind_material></instance_geometry></node>")
        }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        var x = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<COLLADA xmlns=\"http://www.collada.org/2005/11/COLLADASchema\" version=\"1.4.1\">\n"
        x += "<asset><contributor><authoring_tool>Oanarina Archi Tool</authoring_tool></contributor><created>\(iso.string(from: Date()))</created><modified>\(iso.string(from: Date()))</modified><unit name=\"meter\" meter=\"1\"/><up_axis>Z_UP</up_axis></asset>\n"
        x += "<library_effects>"
        for (mid, name) in usedMats.sorted(by: { $0.key < $1.key }) {
            let m = MeshExport.material(name, in: materials)
            x += "<effect id=\"\(mid)-fx\"><profile_COMMON><technique sid=\"common\"><phong><diffuse><color>\(fmt(m.color.r, 4)) \(fmt(m.color.g, 4)) \(fmt(m.color.b, 4)) 1</color></diffuse>"
            x += "<transparency><float>\(fmt(1 - max(0, min(1, m.transparency)), 4))</float></transparency></phong></technique></profile_COMMON></effect>"
        }
        x += "</library_effects>\n<library_materials>"
        for (mid, name) in usedMats.sorted(by: { $0.key < $1.key }) { x += "<material id=\"\(mid)\" name=\"\(e(name))\"><instance_effect url=\"#\(mid)-fx\"/></material>" }
        x += "</library_materials>\n<library_geometries>\n" + geoms.joined(separator: "\n") + "\n</library_geometries>\n"
        x += "<library_visual_scenes><visual_scene id=\"Scene\" name=\"Scene\">\n" + nodes.joined(separator: "\n") + "\n</visual_scene></library_visual_scenes>\n"
        x += "<scene><instance_visual_scene url=\"#Scene\"/></scene>\n</COLLADA>\n"
        return x
    }
}

public enum ColladaImporter {
    /// Mesh solids from a COLLADA file (triangles, polylist, polygons; node matrix/translate/rotate/scale; unit and up axis).
    public static func entities(_ data: Data, unitMM: Double = 1, layer: String = "IMPORT-DAE") throws -> [Entity] {
        let p = DAEParser()
        let x = XMLParser(data: data)
        x.delegate = p
        guard x.parse() else { throw PointCloud.CloudError.invalid("Invalid COLLADA: \(x.parserError?.localizedDescription ?? "")") }
        let k = p.meter * 1000 / unitMM
        var out: [Entity] = []
        func visit(_ n: DAEParser.Node, _ parent: [Double]) {
            let m = DAEParser.mul(parent, n.matrix)
            for (url, mats) in n.geometries {
                guard let g = p.geometries[url] else { continue }
                var verts: [Vec3] = []
                var remap: [Int: Int] = [:]
                var tris: [Int] = []
                for (pi, prim) in g.prims.enumerated() {
                    _ = pi
                    for i in prim.indices {
                        guard i >= 0, i < g.positions.count else { continue }
                        if let j = remap[i] { tris.append(j); continue }
                        let v = g.positions[i]
                        var w = Vec3(m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3], m[4] * v.x + m[5] * v.y + m[6] * v.z + m[7], m[8] * v.x + m[9] * v.y + m[10] * v.z + m[11])
                        if p.upAxis == "Y_UP" { w = Vec3(w.x, -w.z, w.y) } else if p.upAxis == "X_UP" { w = Vec3(w.y, w.z, w.x) }
                        remap[i] = verts.count; tris.append(verts.count); verts.append(w * k)
                    }
                }
                tris = Array(tris.prefix(tris.count / 3 * 3))
                guard !tris.isEmpty else { continue }
                var props = ["name": n.name.isEmpty ? g.name : n.name]
                if let mname = mats.values.first.flatMap({ p.materialNames[$0] ?? $0 }) { props["material"] = mname }
                out.append(Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: verts, meshTriangles: tris)), props: props))
            }
            for c in n.children { visit(c, m) }
        }
        let id: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        for n in p.roots { visit(n, id) }
        if out.isEmpty {
            // No scene: import every geometry once.
            for (url, _) in p.geometries.sorted(by: { $0.key < $1.key }) { visit(DAEParser.Node(name: url, matrix: id, geometries: [(url, [:])], children: []), id) }
        }
        if out.isEmpty { throw MeshImportError.empty("COLLADA") }
        return out
    }
}

final class DAEParser: NSObject, XMLParserDelegate {
    struct Prim { var indices: [Int] }
    struct Geometry { var name: String; var positions: [Vec3] = []; var prims: [Prim] = [] }
    final class Node { var name: String; var matrix: [Double]; var geometries: [(String, [String: String])]; var children: [Node]
        init(name: String, matrix: [Double], geometries: [(String, [String: String])], children: [Node]) { self.name = name; self.matrix = matrix; self.geometries = geometries; self.children = children } }
    var meter = 1.0
    var upAxis = "Y_UP"
    var geometries: [String: Geometry] = [:]
    var materialNames: [String: String] = [:]
    var roots: [Node] = []
    // parse state
    var text = ""
    var arrays: [String: [Double]] = [:]
    var sourceArray: [String: String] = [:]     // source id → float_array id
    var curSource: String?
    var vertexSource: [String: String] = [:]    // vertices id → position source id
    var curVertices: String?
    var curGeom: String?
    var inputs: [(semantic: String, source: String, offset: Int)] = []
    var vcount: [Int] = []
    var primKind = ""
    var pLists: [[Int]] = []
    var nodeStack: [Node] = []
    var inVisualScene = false
    var curMaterialInstance: [String: String] = [:]

    static func mul(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: 16)
        for i in 0..<4 { for j in 0..<4 { var s = 0.0; for k in 0..<4 { s += a[i * 4 + k] * b[k * 4 + j] }; r[i * 4 + j] = s } }
        return r
    }
    func parser(_ parser: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch n {
        case "unit": meter = a["meter"].flatMap(Double.init) ?? 1
        case "geometry": curGeom = a["id"]; if let g = curGeom { geometries[g] = Geometry(name: a["name"] ?? g) }
        case "source": curSource = a["id"]
        case "float_array": break
        case "accessor": if let s = curSource, let src = a["source"] { sourceArray[s] = String(src.dropFirst()) }
        case "vertices": curVertices = a["id"]
        case "input":
            let src = String((a["source"] ?? "").dropFirst())
            if let v = curVertices, a["semantic"] == "POSITION" { vertexSource[v] = src }
            else if !primKind.isEmpty { inputs.append((a["semantic"] ?? "", src, a["offset"].flatMap(Int.init) ?? 0)) }
        case "triangles", "polylist", "polygons", "trifans", "tristrips": primKind = n; inputs = []; vcount = []; pLists = []
        case "material": if let id = a["id"] { materialNames[id] = a["name"] ?? id }
        case "visual_scene": inVisualScene = true
        case "node" where inVisualScene:
            let nd = Node(name: a["name"] ?? a["id"] ?? "", matrix: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], geometries: [], children: [])
            if let parent = nodeStack.last { parent.children.append(nd) } else { roots.append(nd) }
            nodeStack.append(nd)
        case "instance_geometry": if let u = a["url"] { nodeStack.last?.geometries.append((String(u.dropFirst()), [:])); curMaterialInstance = [:] }
        case "instance_material":
            if let s = a["symbol"], let t = a["target"], let nd = nodeStack.last, !nd.geometries.isEmpty { nd.geometries[nd.geometries.count - 1].1[s] = String(t.dropFirst()) }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func nums() -> [Double] { text.split(whereSeparator: { $0 == " " || $0.isNewline || $0 == "\t" }).compactMap { Double($0) } }
    func parser(_ parser: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
        switch n {
        case "up_axis": upAxis = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        case "float_array": if let s = curSource { arrays[s] = nums() }
        case "source": curSource = nil
        case "vertices": curVertices = nil
        case "vcount": vcount = nums().map { Int($0) }
        case "p": pLists.append(nums().map { Int($0) })
        case "triangles", "polylist", "polygons", "trifans", "tristrips":
            defer { primKind = "" }
            guard let g = curGeom, let vin = inputs.first(where: { $0.semantic == "VERTEX" }) else { return }
            if geometries[g]!.positions.isEmpty, let posSrc = vertexSource[vin.source], let arr = arrays[posSrc] ?? arrays[sourceArray[posSrc] ?? ""] {
                geometries[g]!.positions = stride(from: 0, to: arr.count - 2, by: 3).map { Vec3(arr[$0], arr[$0 + 1], arr[$0 + 2]) }
            }
            let stride = (inputs.map(\.offset).max() ?? 0) + 1
            var tris: [Int] = []
            func verts(_ p: [Int]) -> [Int] { Swift.stride(from: vin.offset, to: p.count, by: stride).map { p[$0] } }
            switch primKind {
            case "triangles": for p in pLists { tris += verts(p) }
            case "polylist":
                let v = pLists.first.map(verts) ?? []
                var i = 0
                for c in vcount { if c >= 3 && i + c <= v.count { for j in 1..<(c - 1) { tris += [v[i], v[i + j], v[i + j + 1]] } }; i += c }
            case "polygons", "trifans":
                for p in pLists { let v = verts(p); if v.count >= 3 { for j in 1..<(v.count - 1) { tris += [v[0], v[j], v[j + 1]] } } }
            default: // tristrips
                for p in pLists { let v = verts(p); if v.count >= 3 { for j in 0..<(v.count - 2) { tris += j % 2 == 0 ? [v[j], v[j + 1], v[j + 2]] : [v[j + 1], v[j], v[j + 2]] } } }
            }
            geometries[g]!.prims.append(Prim(indices: tris))
        case "geometry": curGeom = nil
        case "matrix":
            let m = nums()
            if m.count == 16, let nd = nodeStack.last { nd.matrix = DAEParser.mul(nd.matrix, m) }
        case "translate":
            let t = nums()
            if t.count == 3, let nd = nodeStack.last { nd.matrix = DAEParser.mul(nd.matrix, [1, 0, 0, t[0], 0, 1, 0, t[1], 0, 0, 1, t[2], 0, 0, 0, 1]) }
        case "scale":
            let s = nums()
            if s.count == 3, let nd = nodeStack.last { nd.matrix = DAEParser.mul(nd.matrix, [s[0], 0, 0, 0, 0, s[1], 0, 0, 0, 0, s[2], 0, 0, 0, 0, 1]) }
        case "rotate":
            let r = nums()
            if r.count == 4, let nd = nodeStack.last {
                let l = max((r[0] * r[0] + r[1] * r[1] + r[2] * r[2]).squareRoot(), 1e-12)
                let (x, y, z) = (r[0] / l, r[1] / l, r[2] / l), a = r[3] * .pi / 180, c = cos(a), s = sin(a), t = 1 - c
                nd.matrix = DAEParser.mul(nd.matrix, [t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0,
                                                      t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0,
                                                      t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0, 0, 0, 0, 1])
            }
        case "node": if inVisualScene, !nodeStack.isEmpty { nodeStack.removeLast() }
        case "visual_scene": inVisualScene = false
        default: break
        }
        text = ""
    }
}

// MARK: - CityJSON

public enum CityJSONImporter {
    /// City objects (buildings, terrain, roads…) as mesh solids per object on layers CITY-<type>, attributes as props.
    /// Projected coordinates (EPSG with a supported CRS) are placed around the project location; others are shifted so
    /// the dataset's lower corner lands at the origin.
    public static func entities(_ data: Data, doc: ArchiDocument, lod: Double? = nil) throws -> [Entity] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (root["type"] as? String) == "CityJSON" else {
            throw GISImportError.invalid("Not a CityJSON file.")
        }
        func d(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
        let tr = root["transform"] as? [String: Any]
        let sc = (tr?["scale"] as? [Any])?.compactMap(d) ?? [1, 1, 1], tl = (tr?["translate"] as? [Any])?.compactMap(d) ?? [0, 0, 0]
        let raw = (root["vertices"] as? [[Any]]) ?? []
        let verts: [Vec3] = raw.map { v in
            let c = v.compactMap(d)
            guard c.count >= 3, sc.count >= 3, tl.count >= 3 else { return .zero }
            return Vec3(c[0] * sc[0] + tl[0], c[1] * sc[1] + tl[1], c[2] * sc[2] + tl[2])
        }
        guard !verts.isEmpty else { throw GISImportError.invalid("The CityJSON file has no vertices.") }
        var crs: GeoCRS = .local
        if let md = root["metadata"] as? [String: Any], let rs = md["referenceSystem"] as? String, let c = GeoCRS.parse(rs.replacingOccurrences(of: "/0/", with: ":")) { crs = c }
        let minX = verts.map(\.x).min() ?? 0, minY = verts.map(\.y).min() ?? 0
        let mapper = GeoMapper(crs: crs, origin: (doc.info.latitude, doc.info.longitude), unitMM: doc.units.mm, shift: crs == .local ? Vec2(minX, minY) : .zero)
        let k = 1000 / doc.units.mm
        let mapped = verts.map { v -> Vec3 in let p = mapper.map(v.x, v.y); return Vec3(p.x, p.y, v.z * k) }
        var out: [Entity] = []
        let objects = (root["CityObjects"] as? [String: Any]) ?? [:]
        for (oid, ov) in objects.sorted(by: { $0.key < $1.key }) {
            guard let o = ov as? [String: Any] else { continue }
            let type = (o["type"] as? String) ?? "CityObject"
            let surfaceTypes: Set<String> = ["MultiSurface", "CompositeSurface", "Solid", "MultiSolid", "CompositeSolid"]
            let geoms = ((o["geometry"] as? [[String: Any]]) ?? []).filter { surfaceTypes.contains(($0["type"] as? String) ?? "") }
            // Highest LoD (or the requested one).
            let chosen: [[String: Any]] = {
                let lods = geoms.compactMap { g -> Double? in (g["lod"] as? String).flatMap(Double.init) ?? d(g["lod"]) }
                guard let want = lod ?? lods.max() else { return geoms }
                return geoms.filter { ((($0["lod"] as? String).flatMap(Double.init) ?? d($0["lod"])) ?? want) == want }
            }()
            var tris: [Int] = []
            var local: [Vec3] = []
            var index: [Int: Int] = [:]
            func vid(_ i: Int) -> Int? {
                guard i >= 0, i < mapped.count else { return nil }
                if let j = index[i] { return j }
                index[i] = local.count; local.append(mapped[i]); return local.count - 1
            }
            func surface(_ s: [[Int]]) {
                guard let outerIdx = s.first, outerIdx.count >= 3 else { return }
                let outer = outerIdx.compactMap { i in i < mapped.count ? mapped[i] : nil }
                // Plane of the polygon (Newell), project, triangulate with holes.
                var n = Vec3.zero
                for i in 0..<outer.count { let a = outer[i], b = outer[(i + 1) % outer.count]; n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)) }
                guard n.length > 1e-12 else { return }
                n = n * (1 / n.length)
                let uu0 = (abs(n.z) < 0.9 ? Vec3(0, 0, 1) : Vec3(1, 0, 0)).cross(n), uu = uu0 * (1 / uu0.length), vv = n.cross(uu)
                func proj(_ i: Int) -> Vec2 { let q = mapped[i] - outer[0]; return Vec2(q.dot(uu), q.dot(vv)) }
                let allIdx = s.map { $0.filter { $0 >= 0 && $0 < mapped.count } }
                let rings2 = allIdx.map { $0.map(proj) }
                let tri = Triangulator.triangulateWithPoints(rings2[0], holes: Array(rings2.dropFirst()))
                let flat = allIdx.flatMap { $0 }, flat2 = rings2.flatMap { $0 }
                var map: [Int] = []
                for p in tri.points {
                    var best = 0, bd = Double.infinity
                    for (j, q) in flat2.enumerated() { let dd = (p - q).lengthSquared; if dd < bd { bd = dd; best = j } }
                    map.append(best < flat.count ? flat[best] : flat[0])
                }
                for t in tri.triangles {
                    guard let a = vid(map[t.0]), let b = vid(map[t.1]), let c = vid(map[t.2]), a != b, b != c, a != c else { continue }
                    let ok = (local[b] - local[a]).cross(local[c] - local[a]).dot(n) >= 0
                    tris += ok ? [a, b, c] : [a, c, b]
                }
            }
            func walk(_ v: Any, depth: Int) {
                // A surface is [[Int]] (rings of ints); deeper arrays are shells/solids.
                if let s = v as? [[NSNumber]] { surface(s.map { $0.map(\.intValue) }); return }
                if let arr = v as? [Any], depth < 6 { arr.forEach { walk($0, depth: depth + 1) } }
            }
            for g in chosen { walk(g["boundaries"] ?? [], depth: 0) }
            guard !tris.isEmpty else { continue }
            var props: [String: String] = ["cityId": oid, "cityType": type]
            for (ak, av) in (o["attributes"] as? [String: Any]) ?? [:] where !(av is NSNull) { props[ak] = (av as? String) ?? "\(av)" }
            out.append(Entity(layer: "CITY-" + type.uppercased(), geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: local, meshTriangles: tris)), props: props))
        }
        if out.isEmpty { throw GISImportError.invalid("No city object geometry found.") }
        return out
    }
}
