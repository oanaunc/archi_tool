// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Texture mapping per material (VIS-062) and texture positioning (VIS-063): Box (per-face planar, the default),
/// Planar (top projection), Cylindrical and Spherical (around the object's centre, real-world size), UV (fitted
/// once over the object); then an offset, rotation and scale move the texture on the faces. Stored in the drawing
/// as MATMAP:<material> = "mode;offsetX,offsetY;rotationDegrees;scale".
enum TextureMapping {
    enum Mode: String, CaseIterable { case box = "Box", planar = "Planar", cylindrical = "Cylindrical", spherical = "Spherical", uv = "UV" }

    struct Settings: Equatable {
        var mode: Mode = .box
        var offset = Vec2.zero       // mm
        var rotation = 0.0           // degrees
        var scale = 1.0
        var isDefault: Bool { self == Settings() }
        var stored: String { "\(mode.rawValue);\(fmt(offset.x)),\(fmt(offset.y));\(fmt(rotation));\(fmt(scale))" }
        init() {}
        init?(stored s: String) {
            let p = s.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard let m = Mode.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(p.first ?? "") == .orderedSame }) else { return nil }
            mode = m
            if p.count > 1 { let o = p[1].split(separator: ",").compactMap { Double($0) }; if o.count == 2 { offset = Vec2(o[0], o[1]) } }
            if p.count > 2, let r = Double(p[2]) { rotation = r }
            if p.count > 3, let k = Double(p[3]), k > 0 { scale = k }
        }
    }

    static func key(_ material: String) -> String { "MATMAP:" + material.uppercased() }
    static func settings(_ material: String, doc: ArchiDocument) -> Settings { doc.variable(key(material)).flatMap(Settings.init(stored:)) ?? Settings() }
    static func store(_ s: Settings, material: String, in doc: inout ArchiDocument) {
        if s.isDefault { doc.variables[key(material)] = nil } else { doc.setVariable(key(material), s.stored) }
    }

    /// The mesh with UVs (metres of texture space, like the core's) for the material's mapping.
    static func apply(_ mesh: Mesh, material: String, doc: ArchiDocument) -> Mesh {
        let s = settings(material, doc: doc)
        guard !s.isDefault, !mesh.positions.isEmpty else { return mesh }
        var m = mesh
        m.uvs = uvs(mesh, s)
        return m
    }

    static func uvs(_ mesh: Mesh, _ s: Settings) -> [Vec2] {
        let b = mesh.bounds, c = b.center
        var raw: [Vec2]
        switch s.mode {
        case .box:
            raw = mesh.uvs.count == mesh.positions.count ? mesh.uvs : mesh.positions.map { Vec2($0.x, $0.y) / 1000 }
        case .planar:
            raw = mesh.positions.map { Vec2($0.x, $0.y) / 1000 }
        case .cylindrical:
            let r = max(max(b.size.x, b.size.y) / 2, 1)
            raw = mesh.positions.map { p in Vec2(atan2(p.y - c.y, p.x - c.x) * r, p.z) / 1000 }
        case .spherical:
            let r = max(b.size.length / 2, 1)
            raw = mesh.positions.map { p in
                let d = p - c, l = max(d.length, 1e-9)
                return Vec2(atan2(d.y, d.x) * r, asin(max(-1, min(1, d.z / l))) * r) / 1000
            }
        case .uv:
            let w = max(b.size.x, 1e-9), h = max(max(b.size.y, b.size.z), 1e-9)
            raw = mesh.positions.map { p in Vec2((p.x - b.min.x) / w, (abs(b.size.y) >= abs(b.size.z) ? (p.y - b.min.y) : (p.z - b.min.z)) / h) }
        }
        let a = s.rotation * .pi / 180, ca = cos(a), sa = sin(a)
        let o = s.mode == .uv ? s.offset / max(1, s.offset.length > 0 ? 1000 : 1) : s.offset / 1000
        return raw.map { q in
            let t = q - o
            return Vec2(t.x * ca + t.y * sa, -t.x * sa + t.y * ca) / s.scale
        }
    }
}
