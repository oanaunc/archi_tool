// Oanarina Archi Tool — GPL-3.0-or-later
// JSON encoding of the 3D model (MeshBuilder groups) for the Windows shell's three.js viewport: little-endian base64
// Float32 / Uint32 buffers in model units, Z up; materials resolved to colour, opacity, roughness, metalness, texture.
import Foundation

/// Collects mesh buffers into one binary file instead of base64 strings (model.meshes {"binary": path}); each buffer is
/// then described by {"offset", "length"} in bytes (4-byte aligned, little-endian).
public final class EngineBinarySink {
    public private(set) var data = Data()
    public init() {}
    func add(_ d: Data) -> EngineJSON {
        var o = EngineObject()
        o.set("offset", data.count)
        o.set("length", d.count)
        data.append(d)
        return o.json
    }
}

public enum EngineMeshJSON {
    /// How the buffers of a binary transfer are laid out (model.meshes {"binary": …} → "layout").
    public static var binaryLayout: EngineJSON {
        var b = EngineObject()
        b.set("positions", "float32 x,y,z per vertex")
        b.set("normals", "float32 x,y,z per vertex")
        b.set("uvs", "float32 u,v per vertex")
        b.set("indices", "uint32, 3 per triangle")
        b.set("edges", "float32 x0,y0,z0,x1,y1,z1 per segment")
        var o = EngineObject()
        o.set("byteOrder", "little-endian")
        o.set("alignment", 4)
        o.set("units", "model millimetres, Z up")
        o.set("buffers", b.json)
        o.set("reference", "each buffer field is {offset, length} in bytes from the start of the file")
        return o.json
    }
    static func bytes(_ floats: [Float]) -> Data {
        let a = floats.map { $0.bitPattern.littleEndian }
        return a.withUnsafeBytes { buf in buf.baseAddress.map { Data(bytes: $0, count: buf.count) } ?? Data() }
    }
    static func bytes(_ ints: [UInt32]) -> Data {
        let a = ints.map { $0.littleEndian }
        return a.withUnsafeBytes { buf in buf.baseAddress.map { Data(bytes: $0, count: buf.count) } ?? Data() }
    }
    static func buffer(_ d: Data, _ sink: EngineBinarySink?) -> EngineJSON {
        if let sink { return sink.add(d) }
        return .string(d.base64EncodedString())
    }

    public static func base64(_ floats: [Float]) -> String {
        let a = floats.map { $0.bitPattern.littleEndian }
        return a.withUnsafeBytes { buf in buf.baseAddress.map { Data(bytes: $0, count: buf.count) } ?? Data() }.base64EncodedString()
    }
    public static func base64(_ ints: [UInt32]) -> String {
        let a = ints.map { $0.littleEndian }
        return a.withUnsafeBytes { buf in buf.baseAddress.map { Data(bytes: $0, count: buf.count) } ?? Data() }.base64EncodedString()
    }
    public static func floats(_ v: [Vec3]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(v.count * 3)
        for p in v { out.append(Float(p.x)); out.append(Float(p.y)); out.append(Float(p.z)) }
        return out
    }
    public static func floats(_ v: [Vec2]) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(v.count * 2)
        for p in v { out.append(Float(p.x)); out.append(Float(p.y)) }
        return out
    }
    /// Decodes a base64 Float32 buffer (tests, fixtures).
    public static func decodeFloats(_ s: String) -> [Float] {
        guard let d = Data(base64Encoded: s) else { return [] }
        var out = [Float](repeating: 0, count: d.count / 4)
        for i in out.indices {
            let bits = UInt32(d[d.startIndex + i * 4]) | UInt32(d[d.startIndex + i * 4 + 1]) << 8
                | UInt32(d[d.startIndex + i * 4 + 2]) << 16 | UInt32(d[d.startIndex + i * 4 + 3]) << 24
            out[i] = Float(bitPattern: bits)
        }
        return out
    }

    /// Edge polylines as line-segment pairs (x0,y0,z0,x1,y1,z1…), the form THREE.LineSegments takes.
    static func edgeSegments(_ edges: [[Vec3]]) -> [Float] {
        var out: [Float] = []
        for e in edges where e.count >= 2 {
            for k in 1..<e.count {
                let a = e[k - 1], b = e[k]
                out += [Float(a.x), Float(a.y), Float(a.z), Float(b.x), Float(b.y), Float(b.z)]
            }
        }
        return out
    }

    /// One mesh group with its material resolved against the document.
    public static func group(_ g: MeshGroup, mesh: Mesh, doc: ArchiDocument, sink: EngineBinarySink? = nil, level: Int? = nil) -> EngineJSON {
        var o = EngineObject()
        if let id = g.id { o.set("id", id) } else { o.set("id", EngineJSON.null) }
        o.set("kind", g.kind)
        if let level { o.set("level", level) }
        o.set("material", g.material)
        let mat = doc.materials.first { $0.name == g.material }
        let color = mat?.color ?? RGBA(0.8, 0.8, 0.8)
        o.set("color", EngineDrawJSON.hex(color))
        o.set("opacity", 1 - (mat?.transparency ?? 0))
        o.set("roughness", mat?.roughness ?? 0.8)
        o.set("metalness", mat?.metalness ?? 0)
        let emit = doc.variable("MATEMIT:" + g.material.uppercased()).flatMap(Double.init) ?? 0
        if emit > 0 { o.set("emissive", min(emit, 20)) }
        o.set("vertexCount", mesh.positions.count)
        o.set("triangleCount", mesh.triangleCount)
        o.set("positions", buffer(bytes(floats(mesh.positions)), sink))
        if mesh.normals.count == mesh.positions.count { o.set("normals", buffer(bytes(floats(mesh.normals)), sink)) }
        o.set("indices", buffer(bytes(mesh.indices), sink))
        if mesh.uvs.count == mesh.positions.count, !mesh.uvs.isEmpty { o.set("uvs", buffer(bytes(floats(mesh.uvs)), sink)) }
        if let t = mat?.texture, !t.isEmpty {
            o.set("texture", t)
            o.set("textureScale", mat?.textureScale ?? 1000)
        }
        let seg = edgeSegments(g.edges)
        if !seg.isEmpty { o.set("edges", buffer(bytes(seg), sink)) }
        return o.json
    }

    /// Lights of the model: placed lights (entities with a "light" prop, as the Mac app's SceneLights) and light fixtures.
    public static func lights(_ doc: ArchiDocument) -> EngineJSON {
        guard doc.variable("ARTIFICIALLIGHTS") != "0" else { return .array([]) }
        var out: [EngineJSON] = []
        for e in doc.entities where e.props["light"] != nil && doc.isVisible(layer: e.layer) {
            guard case .point(let p) = e.geometry, e.props["lightOn"] != "0" else { continue }
            func d(_ k: String, _ def: Double) -> Double { e.props[k].flatMap { Double($0) } ?? def }
            let kind = (e.props["light"] ?? "point").lowercased()
            var o = EngineObject()
            o.set("id", e.id)
            o.set("kind", kind == "ies" ? "ies" : kind)
            o.set("position", EngineJSON.point3(Vec3(p.x, p.y, d("z", 2400))))
            if let tx = e.props["targetX"].flatMap(Double.init), let ty = e.props["targetY"].flatMap(Double.init) {
                o.set("target", EngineJSON.point3(Vec3(tx, ty, d("targetZ", 0))))
            }
            o.set("lumens", max(0, d("lumens", 800)))
            o.set("cct", min(max(d("cct", 3000), 1000), 20000))
            o.set("beam", min(max(d("beam", 60), 1), 170))
            o.set("size", EngineJSON.point(Vec2(max(d("width", 600), 1), max(d("length", 600), 1))))
            if let ies = e.props["ies"] { o.set("ies", ies) }
            out.append(o.json)
        }
        for f in LightingFixtures.renderLights(doc: doc) {
            let spot = f.spotAngle < 170
            var o = EngineObject()
            o.set("id", f.id)
            o.set("kind", spot ? "spot" : "point")
            o.set("position", EngineJSON.point3(f.position))
            if spot { o.set("target", EngineJSON.point3(f.position + f.direction * 1000)) }
            o.set("lumens", f.lumens)
            let ratio = f.color.b / max(f.color.r, 1e-6)
            o.set("cct", min(max(1800 + ratio * 4700, 1800), 12000))
            o.set("beam", min(f.spotAngle, 170))
            o.set("size", EngineJSON.point(Vec2(1, 1)))
            o.set("fixture", true)
            out.append(o.json)
        }
        return .array(out)
    }
}
