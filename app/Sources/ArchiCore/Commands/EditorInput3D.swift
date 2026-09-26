// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 3D point input (CMD-026): typed x,y,z, cylindrical d<a,z and spherical d<a<b keep their Z; picked points lie on the
/// current work plane (Z = `defaultZ`).
///
/// Dynamic UCS (PRC-036, DUCS): the first point picked over a face of a 3D solid makes that face the temporary work
/// plane for the rest of the command (`dynamicFace`). Later picked points lie on that plane (or on the face under the
/// cursor), and typed coordinates are read in the face's coordinate system — X along the face's horizontal edge
/// direction (the UCS X on horizontal faces), Y up the face, Z along its normal — so "@1000,0" on a roof slope runs
/// along the slope. The dynamic-input tooltip shows the same face coordinates.
extension Editor {
    public func getPoint3(_ msg: String, base: Vec3? = nil, keywords: [String] = [], defaultZ: Double = 0) async throws -> (point: Vec3?, keyword: String?) {
        InputParser.lastParsedZ = nil
        InputParser.lastTypedLocal = nil
        if let b = base { InputParser.lastZ = b.z }
        let a = try await getPoint(msg, base: base.map { Vec2($0.x, $0.y) }, keywords: keywords)
        switch a {
        case .point(let p):
            let typedZ = InputParser.lastParsedZ, typed = InputParser.lastTypedLocal
            InputParser.lastParsedZ = nil; InputParser.lastTypedLocal = nil
            let r = resolvePoint3(p, typedZ: typedZ, typed: typed, base: base, defaultZ: defaultZ)
            InputParser.lastZ = r.z
            return (r, nil)
        case .keyword(let k): return (nil, k)
        case .none: return (nil, nil)
        }
    }
    public func requirePoint3(_ msg: String, base: Vec3? = nil, defaultZ: Double = 0) async throws -> Vec3 {
        guard let p = try await getPoint3(msg, base: base, defaultZ: defaultZ).point else { throw CommandError.cancelled }
        return p
    }

    /// The active dynamic-UCS face with its X axis following the current UCS on horizontal faces.
    public var dynamicFaceFrame: DynamicUCS.Face? { dynamicFace?.rotatedX(to: UCSFrame.current(doc).angle) }

    /// 3D point for a 2D answer: typed points keep their Z (or are re-read on the dynamic face); picked points land on a
    /// 3D object snap, the face under the cursor (DUCS) or the active dynamic face plane.
    func resolvePoint3(_ p: Vec2, typedZ: Double?, typed: (local: Vec3, relative: Bool)?, base: Vec3?, defaultZ: Double) -> Vec3 {
        if let tz = typedZ {
            // Typed input: on a sloped dynamic face the typed values are face coordinates.
            if let f = dynamicFaceFrame, !f.isHorizontal, let t = typed {
                if t.relative, let b = base ?? lastPoint.map({ Vec3($0.x, $0.y, InputParser.lastZ) }) { return b + f.vectorToWorld(t.local) }
                if !t.relative { return f.toWorld(t.local) }
            }
            if let f = dynamicFaceFrame, f.isHorizontal, let t = typed, !t.relative { return Vec3(p.x, p.y, f.origin.z + t.local.z) }
            return Vec3(p.x, p.y, tz)
        }
        if let z = Snap3D.elevation(at: p, doc: doc) { return Vec3(p.x, p.y, z) }
        if let f = DynamicUCS.activeFace(at: p, doc: doc) {
            if dynamicFace == nil && activeCommand != nil { dynamicFace = f }
            return f.origin
        }
        if let f = dynamicFace, let q = f.planePoint(p) { return q }
        return Vec3(p.x, p.y, defaultZ)
    }

    /// Elevation for a plan point picked as the base of a new 3D object: the horizontal face under it when DUCS is on
    /// (the face becomes the command's dynamic UCS), otherwise `fallback`.
    public func dynamicBaseElevation(at p: Vec2, fallback: Double) -> Double {
        if let f = DynamicUCS.activeFace(at: p, doc: doc) {
            if dynamicFace == nil && activeCommand != nil { dynamicFace = f }
            return f.origin.z
        }
        if let f = dynamicFace, let q = f.planePoint(p) { return q.z }
        return fallback
    }
}
