// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Named reference planes (PRC-038): work planes for sketching, shown in plan as dashed lines on the
/// "Reference Planes" layer and tagged with the prop "refplane" = name. They snap like lines, can become the current UCS
/// (UCS Plane / RP Set) and are found by name from scripts.
public enum ReferencePlanes {
    public static let prop = "refplane"
    public static let layer = "Reference Planes"

    /// Entity for a new reference plane from `a` to `b` (nil when the points coincide).
    public static func make(name: String, from a: Vec2, to b: Vec2) -> Entity? {
        guard a.distance(to: b) > 1e-9 else { return nil }
        var e = Entity(id: 0, layer: layer, geometry: .line(LineGeom(a, b)))
        e.props[prop] = name
        return e
    }
    /// Adds the layer (green, dashed, not plotted) when missing.
    public static func ensureLayer(_ doc: inout ArchiDocument) {
        guard doc.layer(named: layer) == nil else { return }
        var l = Layer(name: layer, color: RGBA(0.35, 0.8, 0.45))
        if doc.linetype("DASHED") != nil { l.linetype = "DASHED" } else if doc.linetype("Dashed") != nil { l.linetype = "Dashed" }
        l.plot = false
        doc.layers.append(l)
    }
    /// All reference planes: (name, entity id, start, end).
    public static func all(_ doc: ArchiDocument) -> [(name: String, id: EntityID, a: Vec2, b: Vec2)] {
        doc.entities.compactMap { e in
            guard let n = e.props[prop], case .line(let l) = e.geometry else { return nil }
            return (n, e.id, l.a, l.b)
        }
    }
    public static func find(_ name: String, in doc: ArchiDocument) -> (name: String, id: EntityID, a: Vec2, b: Vec2)? {
        all(doc).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
    /// Unique default name "Ref Plane n".
    public static func nextName(_ doc: ArchiDocument) -> String {
        var n = 1
        while find("Ref Plane \(n)", in: doc) != nil { n += 1 }
        return "Ref Plane \(n)"
    }
    /// Work plane (UCS) of a reference plane: origin at its start, X along it.
    public static func frame(_ name: String, in doc: ArchiDocument) -> UCSFrame? {
        guard let r = find(name, in: doc) else { return nil }
        return UCSFrame(origin: r.a, angle: (r.b - r.a).angle)
    }
}

/// Shared (survey) coordinates, project base point and true north (PRC-039 / PRC-040).
/// - project base point: internal location PBPOINT ("x,y"; default origin);
/// - its shared coordinates: EASTING0 / NORTHING0 (as used by spot coordinates and fields);
/// - true north: `ProjectInfo.northAngle`, degrees counter-clockwise from project north (up);
/// - elevation of the base point: PBELEVATION.
/// shared = (E0, N0) + (p − PBP) rotated by −northAngle, so true north is +N whatever the plan rotation.
public struct SharedCoordinates: Hashable {
    public var basePoint: Vec2
    public var easting: Double
    public var northing: Double
    /// Degrees counter-clockwise from project north to true north.
    public var northAngle: Double
    public var elevation: Double
    public init(basePoint: Vec2 = .zero, easting: Double = 0, northing: Double = 0, northAngle: Double = 0, elevation: Double = 0) {
        self.basePoint = basePoint; self.easting = easting; self.northing = northing; self.northAngle = northAngle; self.elevation = elevation
    }

    public static func current(_ doc: ArchiDocument) -> SharedCoordinates {
        var s = SharedCoordinates(northAngle: doc.info.northAngle)
        if let t = doc.variable("PBPOINT") {
            let p = t.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count >= 2 { s.basePoint = Vec2(p[0], p[1]) }
        }
        s.easting = doc.variable("EASTING0").flatMap(Double.init) ?? 0
        s.northing = doc.variable("NORTHING0").flatMap(Double.init) ?? 0
        s.elevation = doc.variable("PBELEVATION").flatMap(Double.init) ?? 0
        return s
    }
    /// Writes the settings to the document (persisted in .archi files).
    public func apply(to doc: inout ArchiDocument) {
        doc.setVariable("PBPOINT", "\(fmt(basePoint.x, 8)),\(fmt(basePoint.y, 8))")
        doc.setVariable("EASTING0", fmt(easting, 8))
        doc.setVariable("NORTHING0", fmt(northing, 8))
        doc.setVariable("PBELEVATION", fmt(elevation, 8))
        doc.info.northAngle = northAngle
    }
    /// True when everything is at its default (shared = internal coordinates).
    public var isIdentity: Bool {
        basePoint.isClose(.zero, tol: 1e-12) && abs(easting) < 1e-12 && abs(northing) < 1e-12 && abs(normAngle(rad(northAngle))) < 1e-12
    }

    /// Internal (project) point → shared (easting, northing).
    public func toShared(_ p: Vec2) -> Vec2 { Vec2(easting, northing) + (p - basePoint).rotated(by: -rad(northAngle)) }
    /// Shared (easting, northing) → internal point.
    public func fromShared(_ s: Vec2) -> Vec2 { basePoint + (s - Vec2(easting, northing)).rotated(by: rad(northAngle)) }
    /// Direction of true north in the plan.
    public var trueNorth: Vec2 { Vec2.polar(1, .pi / 2 + rad(northAngle)) }
    /// Bearing (degrees clockwise from true north) of a plan direction.
    public func bearing(_ v: Vec2) -> Double {
        let a = deg(normAngle(trueNorth.angle - v.angle))
        return a >= 360 - 1e-9 ? 0 : a
    }
    /// View rotation (radians) that shows the plan oriented to true north (PLANORIENT True), 0 for project north.
    public static func viewRotation(_ doc: ArchiDocument) -> Double {
        (doc.variable("PLANORIENT") ?? "Project").lowercased().hasPrefix("t") ? -rad(doc.info.northAngle) : 0
    }
    /// Survey point: the internal location whose shared coordinates are (0, 0).
    public var surveyPoint: Vec2 { fromShared(.zero) }
}
