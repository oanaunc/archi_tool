// Oanarina Archi Tool — GPL-3.0-or-later
// Point clouds (XYZ, PTS, PLY ASCII/binary) as point entities with decimation, PLY meshes (import/export),
// OFF and AMF mesh import.
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct PointCloudOptions {
    /// Drawing units per file unit (1000 for metres into a millimetre drawing).
    public var scale: Double = 1000
    /// Keep at most this many points (evenly sampled after the voxel filter); 0 = no limit.
    public var maxPoints = 200_000
    /// Voxel size in drawing units: one point per voxel (0 = off).
    public var voxel: Double = 0
    public var layer = "POINTCLOUD"
    public init(scale: Double = 1000, maxPoints: Int = 200_000, voxel: Double = 0) { self.scale = scale; self.maxPoints = maxPoints; self.voxel = voxel }
}

public struct CloudPoint: Hashable {
    public var p: Vec3
    public var color: (UInt8, UInt8, UInt8)?
    public var intensity: Double?
    public init(_ p: Vec3, color: (UInt8, UInt8, UInt8)? = nil, intensity: Double? = nil) { self.p = p; self.color = color; self.intensity = intensity }
    public static func == (a: CloudPoint, b: CloudPoint) -> Bool { a.p == b.p && a.color?.0 == b.color?.0 && a.color?.1 == b.color?.1 && a.color?.2 == b.color?.2 && a.intensity == b.intensity }
    public func hash(into h: inout Hasher) { h.combine(p) }
}

public enum PointCloud {
    public enum CloudError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return m }; return nil }
    }

    // MARK: text formats

    /// XYZ (x y z [r g b] | [i] | [i r g b]) and PTS (first line = count; x y z i r g b). Separators: space, tab, comma, ';'.
    public static func parseText(_ text: String) -> [CloudPoint] {
        var out: [CloudPoint] = []
        var first = true
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == ";" }).compactMap { Double($0) }
            if first { first = false; if f.count == 1 { continue } } // PTS point count
            guard f.count >= 3 else { continue }
            var cp = CloudPoint(Vec3(f[0], f[1], f[2]))
            func rgb(_ i: Int) -> (UInt8, UInt8, UInt8)? {
                guard f.count >= i + 3 else { return nil }
                let c = f[i..<(i + 3)]
                guard c.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return nil }
                let unit = c.allSatisfy { $0 <= 1 } && c.contains { $0 != Double(Int($0)) }
                return unit ? (UInt8(c[i] * 255), UInt8(c[i + 1] * 255), UInt8(c[i + 2] * 255)) : (UInt8(c[i]), UInt8(c[i + 1]), UInt8(c[i + 2]))
            }
            switch f.count {
            case 4: cp.intensity = f[3]
            case 6: cp.color = rgb(3)
            case 7...: cp.intensity = f[3]; cp.color = rgb(4)
            default: break
            }
            out.append(cp)
        }
        return out
    }

    // MARK: PLY

    public struct PLYData {
        public var points: [CloudPoint] = []
        public var faces: [[Int]] = []
    }

    /// PLY (ascii, binary_little_endian, binary_big_endian): vertex x/y/z [red/green/blue][intensity] and face vertex lists.
    public static func parsePLY(_ data: Data) throws -> PLYData {
        let bytes = [UInt8](data)
        guard bytes.count > 10, String(decoding: bytes.prefix(3), as: UTF8.self) == "ply" else { throw CloudError.invalid("Not a PLY file.") }
        // Header
        var headerEnd = 0
        var i = 0
        let marker = Array("end_header".utf8)
        while i + marker.count <= bytes.count {
            if bytes[i] == marker[0] && Array(bytes[i..<(i + marker.count)]) == marker {
                var j = i + marker.count
                while j < bytes.count && bytes[j] != 10 { j += 1 }
                headerEnd = j + 1; break
            }
            i += 1
        }
        guard headerEnd > 0 else { throw CloudError.invalid("PLY header has no end_header.") }
        let header = String(decoding: bytes[0..<headerEnd], as: UTF8.self)
        struct Prop { var name: String; var type: String; var listCount: String? }
        struct Elem { var name: String; var count: Int; var props: [Prop] }
        var format = "ascii"
        var elems: [Elem] = []
        for l in header.split(whereSeparator: { $0.isNewline }) {
            let t = l.split(separator: " ").map(String.init)
            guard let k = t.first else { continue }
            switch k {
            case "format": if t.count > 1 { format = t[1] }
            case "element": if t.count >= 3, let n = Int(t[2]) { elems.append(Elem(name: t[1], count: n, props: [])) }
            case "property":
                guard !elems.isEmpty else { continue }
                if t.count >= 5 && t[1] == "list" { elems[elems.count - 1].props.append(Prop(name: t[4], type: t[3], listCount: t[2])) }
                else if t.count >= 3 { elems[elems.count - 1].props.append(Prop(name: t[2], type: t[1], listCount: nil)) }
            default: break
            }
        }
        var out = PLYData()
        func store(_ e: Elem, _ vals: [String: Double], list: [Int]?) {
            if e.name == "vertex" {
                var cp = CloudPoint(Vec3(vals["x"] ?? 0, vals["y"] ?? 0, vals["z"] ?? 0))
                if let r = vals["red"] ?? vals["r"], let g = vals["green"] ?? vals["g"], let b = vals["blue"] ?? vals["b"] {
                    let unit = r <= 1 && g <= 1 && b <= 1 && (e.props.first { $0.name == "red" }?.type.hasPrefix("float") ?? false)
                    let k = unit ? 255.0 : 1
                    cp.color = (UInt8(max(0, min(255, r * k))), UInt8(max(0, min(255, g * k))), UInt8(max(0, min(255, b * k))))
                }
                if let s = vals["intensity"] ?? vals["scalar_intensity"] { cp.intensity = s }
                out.points.append(cp)
            } else if e.name == "face", let l = list { out.faces.append(l) }
        }
        if format == "ascii" {
            let body = String(decoding: bytes[headerEnd...], as: UTF8.self)
            var tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).makeIterator()
            for e in elems {
                for _ in 0..<e.count {
                    var vals: [String: Double] = [:]
                    var list: [Int]? = nil
                    for p in e.props {
                        if p.listCount != nil {
                            guard let n = tokens.next().flatMap({ Int(Double($0) ?? -1) }), n >= 0 else { throw CloudError.invalid("Bad PLY list.") }
                            var l: [Int] = []
                            for _ in 0..<n { l.append(Int(Double(tokens.next() ?? "") ?? -1)) }
                            if p.name == "vertex_indices" || p.name == "vertex_index" { list = l }
                        } else { vals[p.name] = Double(tokens.next() ?? "") ?? 0 }
                    }
                    store(e, vals, list: list)
                }
            }
            return out
        }
        let big = format == "binary_big_endian"
        var o = headerEnd
        func size(_ t: String) -> Int {
            switch t { case "char", "uchar", "int8", "uint8": return 1; case "short", "ushort", "int16", "uint16": return 2; case "double", "float64": return 8; default: return 4 }
        }
        func read(_ t: String) throws -> Double {
            let n = size(t)
            guard o + n <= bytes.count else { throw CloudError.invalid("PLY data is truncated.") }
            var u: UInt64 = 0
            for k in 0..<n { u |= UInt64(bytes[o + (big ? n - 1 - k : k)]) << (8 * UInt64(k)) }
            o += n
            switch t {
            case "char", "int8": return Double(Int8(bitPattern: UInt8(u)))
            case "uchar", "uint8": return Double(u)
            case "short", "int16": return Double(Int16(bitPattern: UInt16(u)))
            case "ushort", "uint16": return Double(u)
            case "int", "int32": return Double(Int32(bitPattern: UInt32(u)))
            case "uint", "uint32": return Double(u)
            case "double", "float64": return Double(bitPattern: u)
            default: return Double(Float(bitPattern: UInt32(u)))
            }
        }
        for e in elems {
            for _ in 0..<e.count {
                var vals: [String: Double] = [:]
                var list: [Int]? = nil
                for p in e.props {
                    if let lc = p.listCount {
                        let n = Int(try read(lc))
                        guard n >= 0 && n < 1_000_000 else { throw CloudError.invalid("Bad PLY list.") }
                        var l: [Int] = []
                        l.reserveCapacity(n)
                        for _ in 0..<n { l.append(Int(try read(p.type))) }
                        if p.name == "vertex_indices" || p.name == "vertex_index" { list = l }
                    } else { vals[p.name] = try read(p.type) }
                }
                store(e, vals, list: list)
            }
        }
        return out
    }

    /// ASCII PLY of mesh groups (millimetres, Z up) with per-vertex colours from the materials.
    public static func exportPLY(_ groups: [MeshGroup], materials: [Material]) -> String {
        var verts: [String] = [], faces: [String] = []
        var base = 0
        for g in groups {
            let tris = MeshExport.triangles(g.mesh)
            guard !tris.isEmpty else { continue }
            let c = MeshExport.material(g.material, in: materials).color
            let (r, gg, b) = (Int(max(0, min(1, c.r)) * 255), Int(max(0, min(1, c.g)) * 255), Int(max(0, min(1, c.b)) * 255))
            for p in g.mesh.positions { verts.append("\(MeshExport.num(p.x)) \(MeshExport.num(p.y)) \(MeshExport.num(p.z)) \(r) \(gg) \(b)") }
            var i = 0
            while i + 2 < tris.count { faces.append("3 \(base + Int(tris[i])) \(base + Int(tris[i + 1])) \(base + Int(tris[i + 2]))"); i += 3 }
            base += g.mesh.positions.count
        }
        var s = "ply\nformat ascii 1.0\ncomment Oanarina Archi Tool (millimetres, Z up)\n"
        s += "element vertex \(verts.count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\n"
        s += "element face \(faces.count)\nproperty list uchar int vertex_indices\nend_header\n"
        return s + verts.joined(separator: "\n") + (verts.isEmpty ? "" : "\n") + faces.joined(separator: "\n") + (faces.isEmpty ? "" : "\n")
    }

    // MARK: decimation and entities

    /// Voxel filter (first point per cell) then even sampling down to `maxPoints`. Coordinates already scaled.
    public static func decimate(_ pts: [CloudPoint], voxel: Double, maxPoints: Int) -> [CloudPoint] {
        var out = pts
        if voxel > 0 {
            var seen = Set<[Int64]>()
            out = []
            for p in pts {
                let k = [Int64((p.p.x / voxel).rounded(.down)), Int64((p.p.y / voxel).rounded(.down)), Int64((p.p.z / voxel).rounded(.down))]
                if seen.insert(k).inserted { out.append(p) }
            }
        }
        if maxPoints > 0 && out.count > maxPoints {
            let step = Double(out.count) / Double(maxPoints)
            out = (0..<maxPoints).map { out[min(out.count - 1, Int(Double($0) * step))] }
        }
        return out
    }

    /// Point entities (props "z", "intensity"; true colour) from cloud points in file units.
    public static func entities(_ pts: [CloudPoint], options: PointCloudOptions = PointCloudOptions()) -> [Entity] {
        let scaled = pts.map { var q = $0; q.p = q.p * options.scale; return q }
        return decimate(scaled, voxel: options.voxel, maxPoints: options.maxPoints).map { cp in
            var e = Entity(layer: options.layer, geometry: .point(cp.p.xy))
            e.props["z"] = fmt(cp.p.z, 4)
            if let i = cp.intensity { e.props["intensity"] = fmt(i, 4) }
            if let c = cp.color { e.color = .rgb(c.0, c.1, c.2) }
            return e
        }
    }

    /// Reads .xyz/.pts/.txt/.ply as point entities (a PLY with faces too: use `mesh(fromPLY:)` for the surface).
    public static func load(_ data: Data, ext: String, options: PointCloudOptions = PointCloudOptions()) throws -> (entities: [Entity], total: Int) {
        let pts: [CloudPoint]
        if ext.lowercased() == "ply" { pts = try parsePLY(data).points }
        else { pts = parseText(String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)) }
        guard !pts.isEmpty else { throw CloudError.invalid("No points found.") }
        return (entities(pts, options: options), pts.count)
    }

    /// Mesh solid from a PLY with faces (polygons fan-triangulated); nil when it has no faces.
    public static func mesh(fromPLY d: PLYData, scale: Double, layer: String = "IMPORT-PLY") -> Entity? {
        var tris: [Int] = []
        for f in d.faces where f.count >= 3 && f.allSatisfy({ $0 >= 0 && $0 < d.points.count }) {
            for j in 1..<(f.count - 1) where f[0] != f[j] && f[j] != f[j + 1] && f[0] != f[j + 1] { tris += [f[0], f[j], f[j + 1]] }
        }
        guard !tris.isEmpty else { return nil }
        return Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: d.points.map { $0.p * scale }, meshTriangles: tris)), props: ["name": "ply"])
    }

    // MARK: OFF / AMF

    /// Object File Format (OFF / COFF / NOFF): polygons fan-triangulated.
    public static func off(_ text: String, scale: Double = 1, layer: String = "IMPORT-OFF") throws -> Entity {
        var toks: [Substring] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let l = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            toks += l.split(whereSeparator: { $0 == " " || $0 == "\t" })
        }
        guard let head = toks.first, head.hasSuffix("OFF") else { throw CloudError.invalid("Not an OFF file.") }
        var it = toks.dropFirst().makeIterator()
        func next() -> Double? { it.next().flatMap { Double($0) } }
        guard let nv = next().map(Int.init), let nf = next().map(Int.init), next() != nil, nv >= 0, nf >= 0 else { throw CloudError.invalid("Bad OFF counts.") }
        let extra = head.hasPrefix("C") ? 4 : (head.hasPrefix("N") ? 3 : 0)
        var v: [Vec3] = []
        for _ in 0..<nv {
            guard let x = next(), let y = next(), let z = next() else { throw CloudError.invalid("OFF vertex list is truncated.") }
            v.append(Vec3(x, y, z) * scale)
            for _ in 0..<extra { _ = next() }
        }
        var tris: [Int] = []
        for _ in 0..<nf {
            guard let n = next().map(Int.init), n >= 0 else { break }
            var f: [Int] = []
            for _ in 0..<n { if let i = next() { f.append(Int(i)) } }
            // Optional face colour: skip up to the end of the line is not tracked; colours are numbers after the indices.
            guard f.count >= 3, f.allSatisfy({ $0 >= 0 && $0 < v.count }) else { continue }
            for j in 1..<(f.count - 1) { tris += [f[0], f[j], f[j + 1]] }
        }
        guard !tris.isEmpty else { throw MeshImportError.empty("OFF") }
        return Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: v, meshTriangles: tris)), props: ["name": "off"])
    }

    /// Additive Manufacturing File (AMF, ISO/ASTM 52915), plain or zipped: one mesh per object, in drawing units
    /// (`unitMM` = millimetres per drawing unit).
    public static func amf(_ data: Data, unitMM: Double = 1, layer: String = "IMPORT-AMF") throws -> [Entity] {
        var xml = data
        if data.count > 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B {
            guard let e = try ZipArchive.read(data).first(where: { $0.name.lowercased().hasSuffix(".amf") || !$0.data.isEmpty }) else { throw CloudError.invalid("Empty AMF archive.") }
            xml = e.data
        }
        let p = AMFParser()
        let parser = XMLParser(data: xml)
        parser.delegate = p
        guard parser.parse() else { throw CloudError.invalid("Invalid AMF XML: \(parser.parserError?.localizedDescription ?? "")") }
        let mm: Double
        switch p.unit.lowercased() {
        case "meter": mm = 1000
        case "inch": mm = 25.4
        case "feet", "foot": mm = 304.8
        case "micron", "micrometer": mm = 0.001
        default: mm = 1
        }
        let k = mm / unitMM
        var out: [Entity] = []
        for o in p.objects where !o.tris.isEmpty {
            let valid = o.tris.allSatisfy { $0 >= 0 && $0 < o.verts.count }
            guard valid else { continue }
            out.append(Entity(layer: layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: o.verts.map { $0 * k }, meshTriangles: o.tris)),
                              props: ["name": o.name.isEmpty ? "object \(o.id)" : o.name]))
        }
        if out.isEmpty { throw MeshImportError.empty("AMF") }
        return out
    }
}

final class AMFParser: NSObject, XMLParserDelegate {
    struct Obj { var id = ""; var name = ""; var verts: [Vec3] = []; var tris: [Int] = [] }
    var unit = "millimeter"
    var objects: [Obj] = []
    var text = ""
    var cur: Vec3 = .zero
    var tri: [Int] = []
    var inMetadataName = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch name.lowercased() {
        case "amf": unit = a["unit"] ?? "millimeter"
        case "object": objects.append(Obj(id: a["id"] ?? "\(objects.count)"))
        case "coordinates": cur = .zero
        case "triangle": tri = []
        case "metadata": inMetadataName = a["type"]?.lowercased() == "name"
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !objects.isEmpty else { return }
        switch name.lowercased() {
        case "x": cur.x = v ?? 0
        case "y": cur.y = v ?? 0
        case "z": cur.z = v ?? 0
        case "coordinates": objects[objects.count - 1].verts.append(cur)
        case "v1", "v2", "v3": tri.append(Int(v ?? -1))
        case "triangle": if tri.count == 3 { objects[objects.count - 1].tris += tri }
        case "metadata": if inMetadataName { objects[objects.count - 1].name = text.trimmingCharacters(in: .whitespacesAndNewlines) }; inMetadataName = false
        default: break
        }
        text = ""
    }
}
