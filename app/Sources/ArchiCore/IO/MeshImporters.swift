// Oanarina Archi Tool — GPL-3.0-or-later
// Wavefront OBJ and STL (ASCII + binary) import as mesh solids.
import Foundation

public struct MeshImportOptions {
    /// Millimetres (drawing units) per file unit. OBJ files from this app are in metres (1000); STL is usually mm (1).
    public var scale: Double
    /// The file is Y-up (OBJ/glTF convention) and is rotated to Z-up.
    public var yUp: Bool
    public var layer: String
    /// One solid per OBJ object/group (else one solid for the whole file).
    public var splitObjects = true
    public init(scale: Double = 1, yUp: Bool = false, layer: String = "IMPORT-MESH") { self.scale = scale; self.yUp = yUp; self.layer = layer }
    public static var obj: MeshImportOptions { MeshImportOptions(scale: 1000, yUp: true, layer: "IMPORT-OBJ") }
    public static var stl: MeshImportOptions { MeshImportOptions(scale: 1, yUp: false, layer: "IMPORT-STL") }
}

public enum MeshImportError: Error, LocalizedError {
    case empty(String)
    public var errorDescription: String? { if case .empty(let f) = self { return "No triangles found in the \(f) file." }; return nil }
}

public enum MeshImporter {
    static func map(_ p: Vec3, _ o: MeshImportOptions) -> Vec3 {
        let q = o.yUp ? Vec3(p.x, -p.z, p.y) : p
        return q * o.scale
    }

    /// Wavefront OBJ: v/f (polygons fan-triangulated, negative indices), o/g groups, usemtl → props["material"].
    public static func obj(_ text: String, options: MeshImportOptions = .obj) throws -> [Entity] {
        var verts: [Vec3] = []
        struct Part { var name: String; var material: String?; var tris: [Int] = [] }
        var parts: [Part] = [Part(name: "mesh", material: nil)]
        var currentMaterial: String?
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let key = f.first else { continue }
            switch key {
            case "v":
                guard f.count >= 4, let x = Double(f[1]), let y = Double(f[2]), let z = Double(f[3]) else { continue }
                verts.append(Vec3(x, y, z))
            case "o", "g":
                guard options.splitObjects else { continue }
                let n = f.dropFirst().joined(separator: " ")
                if parts[parts.count - 1].tris.isEmpty { parts[parts.count - 1].name = n.isEmpty ? parts[parts.count - 1].name : n }
                else { parts.append(Part(name: n.isEmpty ? "mesh" : n, material: currentMaterial)) }
            case "usemtl":
                currentMaterial = f.dropFirst().joined(separator: " ")
                if parts[parts.count - 1].tris.isEmpty { parts[parts.count - 1].material = currentMaterial }
                else if options.splitObjects, parts[parts.count - 1].material != currentMaterial {
                    parts.append(Part(name: parts[parts.count - 1].name, material: currentMaterial))
                }
            case "f":
                var idx: [Int] = []
                for tok in f.dropFirst() {
                    guard let s = tok.split(separator: "/", omittingEmptySubsequences: false).first, let i = Int(s) else { continue }
                    let k = i > 0 ? i - 1 : verts.count + i
                    if k >= 0 && k < verts.count { idx.append(k) }
                }
                guard idx.count >= 3 else { continue }
                for j in 1..<(idx.count - 1) { parts[parts.count - 1].tris += [idx[0], idx[j], idx[j + 1]] }
            default: continue
            }
        }
        var out: [Entity] = []
        for p in parts where !p.tris.isEmpty {
            // Compact the vertex list per part.
            var remap: [Int: Int] = [:]
            var pv: [Vec3] = []
            var tris: [Int] = []
            tris.reserveCapacity(p.tris.count)
            for i in p.tris {
                if let j = remap[i] { tris.append(j) } else { remap[i] = pv.count; tris.append(pv.count); pv.append(map(verts[i], options)) }
            }
            var props = ["name": p.name]
            if let m = p.material, !m.isEmpty { props["material"] = m }
            out.append(Entity(layer: options.layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: pv, meshTriangles: tris)), props: props))
        }
        if out.isEmpty { throw MeshImportError.empty("OBJ") }
        return out
    }

    /// STL, ASCII or binary (detected). Vertices are welded.
    public static func stl(_ data: Data, options: MeshImportOptions = .stl) throws -> [Entity] {
        let bytes = [UInt8](data)
        var tris: [Vec3] = []
        var name = "stl"
        let isBinary: Bool = {
            guard bytes.count >= 84 else { return false }
            let n = Int(bytes[80]) | Int(bytes[81]) << 8 | Int(bytes[82]) << 16 | Int(bytes[83]) << 24
            if 84 + n * 50 == bytes.count { return true }
            let head = String(decoding: bytes.prefix(5), as: UTF8.self).lowercased()
            return head != "solid"
        }()
        if isBinary {
            let n = Int(bytes[80]) | Int(bytes[81]) << 8 | Int(bytes[82]) << 16 | Int(bytes[83]) << 24
            func f32(_ o: Int) -> Double {
                let u = UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16 | UInt32(bytes[o + 3]) << 24
                return Double(Float(bitPattern: u))
            }
            var o = 84
            for _ in 0..<n {
                guard o + 50 <= bytes.count else { break }
                for k in 0..<3 { let b = o + 12 + k * 12; tris.append(Vec3(f32(b), f32(b + 4), f32(b + 8))) }
                o += 50
            }
        } else {
            let text = String(decoding: bytes, as: UTF8.self)
            for raw in text.split(whereSeparator: { $0.isNewline }) {
                let f = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard let k = f.first else { continue }
                if k == "solid", f.count > 1 { name = f.dropFirst().joined(separator: " ") }
                if k == "vertex", f.count >= 4, let x = Double(f[1]), let y = Double(f[2]), let z = Double(f[3]) { tris.append(Vec3(x, y, z)) }
            }
        }
        tris = Array(tris.prefix(tris.count / 3 * 3))
        guard !tris.isEmpty else { throw MeshImportError.empty("STL") }
        var weld: [String: Int] = [:]
        var pv: [Vec3] = []
        var idx: [Int] = []
        idx.reserveCapacity(tris.count)
        for p in tris {
            let q = map(p, options)
            let key = "\(Int((q.x * 1000).rounded())),\(Int((q.y * 1000).rounded())),\(Int((q.z * 1000).rounded()))"
            if let i = weld[key] { idx.append(i) } else { weld[key] = pv.count; idx.append(pv.count); pv.append(q) }
        }
        // Drop degenerate triangles.
        var clean: [Int] = []
        var i = 0
        while i + 2 < idx.count {
            if idx[i] != idx[i + 1] && idx[i + 1] != idx[i + 2] && idx[i] != idx[i + 2] { clean += [idx[i], idx[i + 1], idx[i + 2]] }
            i += 3
        }
        guard !clean.isEmpty else { throw MeshImportError.empty("STL") }
        return [Entity(layer: options.layer, geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: pv, meshTriangles: clean)), props: ["name": name])]
    }
}
