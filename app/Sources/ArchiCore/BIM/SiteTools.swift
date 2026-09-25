// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Surveyor's quadrant bearings (N 45°30'00" E) relative to project north (ProjectInfo.northAngle, CCW from +Y).
public enum Bearings {
    /// Azimuth (degrees clockwise from project north, 0…360) of a plan direction.
    public static func azimuth(_ v: Vec2, northAngle: Double = 0) -> Double {
        let r = v.rotated(by: -northAngle * .pi / 180)
        var a = atan2(r.x, r.y) * 180 / .pi
        if a < 0 { a += 360 }
        return a >= 360 - 1e-12 ? 0 : a
    }

    static func dms(_ deg: Double) -> String {
        var total = Int((deg * 3600).rounded())
        let d = total / 3600; total -= d * 3600
        let m = total / 60, s = total - m * 60
        return String(format: "%d°%02d'%02d\"", d, m, s)
    }

    /// Quadrant bearing text of a direction.
    public static func format(_ v: Vec2, northAngle: Double = 0) -> String {
        let az = azimuth(v, northAngle: northAngle)
        let (ns, ang, ew): (String, Double, String)
        switch az {
        case ..<90.0000001: (ns, ang, ew) = ("N", az, "E")
        case ..<180.0000001: (ns, ang, ew) = ("S", 180 - az, "E")
        case ..<270.0: (ns, ang, ew) = ("S", az - 180, "W")
        default: (ns, ang, ew) = ("N", 360 - az, "W")
        }
        return "\(ns) \(dms(ang)) \(ew)"
    }

    /// Parses "N45d30'15\"E", "N 45°30' E", "S12.5W", "N45-30-00E" into a unit plan direction (project north applied).
    public static func parse(_ s0: String, northAngle: Double = 0) -> Vec2? {
        let s = s0.uppercased().replacingOccurrences(of: " ", with: "")
        guard let f = s.first, f == "N" || f == "S", let l = s.last, l == "E" || l == "W" else { return nil }
        let body = s.dropFirst().dropLast()
        let parts = body.split(whereSeparator: { "D°'\"-:".contains($0) || $0 == "′" || $0 == "″" }).compactMap { Double($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let ang = parts[0] + (parts.count > 1 ? parts[1] / 60 : 0) + (parts.count > 2 ? parts[2] / 3600 : 0)
        guard ang >= 0, ang <= 90 else { return nil }
        let az: Double
        switch (f, l) {
        case ("N", "E"): az = ang
        case ("S", "E"): az = 180 - ang
        case ("S", "W"): az = 180 + ang
        default: az = 360 - ang
        }
        let r = az * .pi / 180
        return Vec2(sin(r), cos(r)).rotated(by: northAngle * .pi / 180)
    }

    /// Distance text in metres (or feet for imperial documents).
    public static func distanceText(_ d: Double, units: Units) -> String {
        switch units {
        case .inches, .feet: return String(format: "%.2f'", d * units.mm / 304.8)
        default: return String(format: "%.3f m", d * units.mm / 1000)
        }
    }

    /// Bearing/distance labels of a property line polyline: one (text, position, rotation) per segment, and the
    /// enclosed area label for a closed boundary.
    public static func labels(_ pts: [Vec2], closed: Bool, doc: ArchiDocument, height th: Double) -> [TextGeom] {
        var out: [TextGeom] = []
        let n = pts.count
        guard n >= 2 else { return [] }
        let segs = closed ? n : n - 1
        let ccw = GeometryOps.signedArea(pts) >= 0
        for i in 0..<segs {
            let a = pts[i], b = pts[(i + 1) % n]
            let len = a.distance(to: b)
            guard len > 1e-9 else { continue }
            let d = (b - a) / len
            // Labels go outside a closed boundary.
            let outside = closed ? (ccw ? -d.perp : d.perp) : d.perp
            let rot = DimensionRenderer.readable(d.angle)
            let mid = (a + b) / 2
            out.append(TextGeom(position: mid + outside * (th * 0.8), height: th, content: format(d, northAngle: doc.info.northAngle), rotation: rot, halign: .center, valign: .middle))
            out.append(TextGeom(position: mid - outside * (th * 0.8), height: th * 0.85, content: distanceText(len, units: doc.units), rotation: rot, halign: .center, valign: .middle))
        }
        if closed && n >= 3 {
            let a = abs(GeometryOps.signedArea(pts)) * doc.units.mm * doc.units.mm / 1e6
            let c = LabelPlacement.pole(of: pts).point
            let txt = doc.units == .feet || doc.units == .inches ? String(format: "AREA %.0f ft²  (%.3f ac)", a * 10.7639, a / 4046.86) : String(format: "AREA %.1f m²  (%.4f ha)", a, a / 10_000)
            out.append(TextGeom(position: c, height: th * 1.1, content: txt, halign: .center, valign: .middle))
        }
        return out
    }
}

/// Parking bays along a row.
public enum ParkingLayout {
    public struct Stall: Hashable { public var center: Vec2; public var rotation: Double }

    /// Stalls of width `w` and depth `depth` at `angle` (degrees, 90 = perpendicular) along the row a→b,
    /// on the left of a→b (the row line is the aisle edge). Double rows mirror across an aisle of `aisle`.
    public static func stalls(from a: Vec2, to b: Vec2, width w: Double, depth: Double, angle: Double = 90, double: Bool = false, aisle: Double = 6000) -> [Stall] {
        let L = a.distance(to: b)
        guard L > 1e-9, w > 1e-9, depth > 1e-9 else { return [] }
        let al = min(max(angle, 30), 90) * .pi / 180
        let d = (b - a) / L
        func row(_ origin: Vec2, _ dir: Vec2, left: Bool) -> [Stall] {
            let n = left ? dir.perp : -dir.perp
            // Stall axis tilted from the row by the parking angle, leaning in the travel direction.
            let s = (dir * cos(al) + n * sin(al)).normalized
            let pitch = w / sin(al)
            // The tilted bay leans forward by depth·cos(angle) along the row.
            let usable = L - depth * abs(cos(al))
            let count = max(0, Int((usable / pitch + 1e-9).rounded(.down)))
            var out: [Stall] = []
            for i in 0..<count {
                let front = origin + dir * (pitch * (Double(i) + 0.5))
                out.append(Stall(center: front + s * (depth / 2), rotation: s.angle - .pi / 2))
            }
            return out
        }
        var out = row(a, d, left: true)
        if double {
            // Opposite side of the aisle, bays facing the aisle.
            let o = a - d.perp * aisle
            out += row(o, d, left: false)
        }
        return out
    }
}

/// Spot elevations: the highest top surface under a point (slab tops incl. slopes, roof faces, toposurfaces).
public enum SpotElevation {
    public static func value(at p: Vec2, doc: ArchiDocument, level: Int? = nil) -> Double {
        var best: Double? = nil
        func consider(_ z: Double) { best = max(best ?? z, z) }
        for el in doc.elements where doc.isVisible(layer: el.layer) {
            if let l = level, el.level != l { continue }
            let elev = doc.level(el.level)?.elevation ?? 0
            switch el.geometry {
            case .slab(let s) where el.props["kind"] != "ceiling":
                if GeometryOps.pointInPolygon(p, s.boundary) && !s.holes.contains(where: { GeometryOps.pointInPolygon(p, $0) }) { consider(elev + s.topHeight(at: p)) }
            case .roof(let r):
                let f = RoofShapes.faces(r)
                if r.kind == .flat || f.faces.isEmpty {
                    if f.footprint.count >= 3, GeometryOps.pointInPolygon(p, f.footprint) { consider(elev + r.baseOffset + r.thickness) }
                } else {
                    let tv = r.thickness / max(cos(min(r.pitch, 85) * .pi / 180), 0.05)
                    for face in f.faces where GeometryOps.pointInPolygon(p, face.poly) { consider(elev + r.baseOffset + face.height(p) + tv) }
                }
            default: continue
            }
        }
        for e in doc.entities where e.props["topo"] == "1" && doc.isVisible(layer: e.layer) {
            if case .solid(let s) = e.geometry, let z = Terrain.elevation(at: p, vertices: s.meshVertices, triangles: s.meshTriangles) { consider(z) }
        }
        return best ?? (doc.level(level ?? doc.currentLevel)?.elevation ?? 0)
    }

    /// Uphill direction and gradient (rise/run) of the topmost sloped surface under a point (nil when level or nothing there).
    public static func slope(at p: Vec2, doc: ArchiDocument, level: Int? = nil) -> (uphill: Vec2, grade: Double)? {
        var best: (z: Double, dir: Vec2, g: Double)? = nil
        func consider(_ z: Double, _ grad: Vec2) { if best == nil || z > best!.z { best = (z, grad.length > 1e-12 ? grad.normalized : Vec2(1, 0), grad.length) } }
        for el in doc.elements where doc.isVisible(layer: el.layer) {
            if let l = level, el.level != l { continue }
            let elev = doc.level(el.level)?.elevation ?? 0
            switch el.geometry {
            case .slab(let s) where el.props["kind"] != "ceiling":
                guard GeometryOps.pointInPolygon(p, s.boundary) else { continue }
                let g = s.isSloped ? Vec2(cos(s.slopeDirection), sin(s.slopeDirection)) * tan(s.slope * .pi / 180) : .zero
                consider(elev + s.topHeight(at: p), g)
            case .roof(let r) where r.kind != .flat:
                for face in RoofShapes.faces(r).faces where GeometryOps.pointInPolygon(p, face.poly) { consider(elev + r.baseOffset + face.height(p), face.grad) }
            default: continue
            }
        }
        for e in doc.entities where e.props["topo"] == "1" {
            guard case .solid(let s) = e.geometry, let z = Terrain.elevation(at: p, vertices: s.meshVertices, triangles: s.meshTriangles) else { continue }
            let h = 10 / doc.units.mm
            let zx = Terrain.elevation(at: p + Vec2(h, 0), vertices: s.meshVertices, triangles: s.meshTriangles) ?? z
            let zy = Terrain.elevation(at: p + Vec2(0, h), vertices: s.meshVertices, triangles: s.meshTriangles) ?? z
            consider(z, Vec2((zx - z) / h, (zy - z) / h))
        }
        guard let b = best, b.g > 1e-9 else { return nil }
        return (b.dir, b.g)
    }

    /// "8.3% (1:12.0)" style gradient label.
    public static func slopeText(_ grade: Double) -> String {
        grade > 1e-9 ? String(format: "%.1f%% (1:%@)", grade * 100, fmt(1 / grade, 1)) : "0%"
    }

    /// "+3.150" style label (metres for metric documents).
    public static func text(_ z: Double, units: Units) -> String {
        switch units {
        case .inches, .feet:
            let ft = z * units.mm / 304.8
            return (ft >= 0 ? "+" : "−") + String(format: "%.2f'", abs(ft))
        default:
            let m = z * units.mm / 1000
            return (m >= 0 ? "+" : "−") + String(format: "%.3f", abs(m))
        }
    }
}

/// Beam systems: parallel beams filling a boundary.
public enum BeamSystemLayout {
    /// Beam axes parallel to `angle` (radians) at `spacing`, clipped to the polygon, centred so both edge gaps are equal.
    public static func lines(boundary: [Vec2], angle: Double, spacing: Double) -> [(Vec2, Vec2)] {
        let poly = RG.dedupe(boundary, closed: true)
        guard poly.count >= 3, spacing > 1e-9 else { return [] }
        let d = Vec2.polar(1, angle), n = d.perp
        let ts = poly.map { $0.dot(n) }, ss = poly.map { $0.dot(d) }
        guard let t0 = ts.min(), let t1 = ts.max(), let s0 = ss.min(), let s1 = ss.max(), t1 - t0 > 1e-9 else { return [] }
        let count = Int(((t1 - t0) / spacing - 1e-9).rounded(.down))
        guard count >= 1 else { return [] }
        let first = t0 + ((t1 - t0) - Double(count - 1) * spacing) / 2
        var out: [(Vec2, Vec2)] = []
        for k in 0..<count {
            let t = first + Double(k) * spacing
            let a = d * (s0 - 1) + n * t, b = d * (s1 + 1) + n * t
            out += RG.clipSegment(a, b, [poly]).filter { $0.0.distance(to: $0.1) > 1e-6 }
        }
        return out
    }
}
