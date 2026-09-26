// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 3D point input (CMD-026): typed x,y,z, cylindrical d<a,z and spherical d<a<b keep their Z; picked points lie on the
/// current work plane (Z = `defaultZ`).
extension Editor {
    public func getPoint3(_ msg: String, base: Vec3? = nil, keywords: [String] = [], defaultZ: Double = 0) async throws -> (point: Vec3?, keyword: String?) {
        InputParser.lastParsedZ = nil
        if let b = base { InputParser.lastZ = b.z }
        let a = try await getPoint(msg, base: base.map { Vec2($0.x, $0.y) }, keywords: keywords)
        switch a {
        case .point(let p):
            // A picked point on a 3D object snap (3DOSNAP) keeps the Z of the snapped feature.
            // With dynamic UCS on, a point picked over a solid lies on the face under it.
            let z = InputParser.lastParsedZ ?? Snap3D.elevation(at: p, doc: doc) ?? DynamicUCS.elevation(at: p, doc: doc) ?? defaultZ
            InputParser.lastParsedZ = nil
            InputParser.lastZ = z
            return (Vec3(p.x, p.y, z), nil)
        case .keyword(let k): return (nil, k)
        case .none: return (nil, nil)
        }
    }
    public func requirePoint3(_ msg: String, base: Vec3? = nil, defaultZ: Double = 0) async throws -> Vec3 {
        guard let p = try await getPoint3(msg, base: base, defaultZ: defaultZ).point else { throw CommandError.cancelled }
        return p
    }
}
