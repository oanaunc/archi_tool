// Oanarina Archi Tool — GPL-3.0-or-later
// Climate-based daylight (ANL-022): annual spatial daylight autonomy sDA300/50% and annual sunlight exposure
// ASE1000,250h (IES LM-83 metrics) for every room, from hourly EnergyPlus weather (EPW) data or a clear-sky year.
// Engine: work-plane grid points (0.75 m) per room; for each point the sky component is integrated over the 145
// Tregenza sky patches with the CIE overcast luminance distribution scaled to the hour's diffuse horizontal
// illuminance, rays leaving through window openings / curtain walls and blocked by walls of any level and the ceiling;
// the direct sun is traced for every occupied hour (08–18 local standard time); an internally reflected component
// uses the BRE split-flux formula. Simplifications: no dynamic blinds, no exterior obstructions other than walls.
import Foundation

public struct ClimateHour: Hashable {
    public var month: Int, day: Int, hour: Int         // hour 1…24 (hour ending, local standard time)
    public var directNormal: Double                     // lux
    public var diffuseHorizontal: Double                // lux
    public init(month: Int, day: Int, hour: Int, directNormal: Double, diffuseHorizontal: Double) {
        self.month = month; self.day = day; self.hour = hour; self.directNormal = directNormal; self.diffuseHorizontal = diffuseHorizontal
    }
}

public struct HourlyClimate: Hashable {
    public var city: String
    public var latitude: Double, longitude: Double, timeZone: Double
    public var hours: [ClimateHour]

    public struct ParseError: Error, LocalizedError { public let message: String; public var errorDescription: String? { "EPW: " + message } }

    /// Parses an EnergyPlus weather file. Illuminance fields missing (9999…) are derived from irradiance with
    /// luminous efficacies of 100 lm/W (direct) and 120 lm/W (diffuse).
    public static func parseEPW(_ text: String) throws -> HourlyClimate {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let loc = lines.first, loc.hasPrefix("LOCATION") else { throw ParseError(message: "missing LOCATION header") }
        let f = loc.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count >= 10, let lat = Double(f[6]), let lon = Double(f[7]), let tz = Double(f[8]) else { throw ParseError(message: "bad LOCATION header") }
        var hours: [ClimateHour] = []
        for l in lines.dropFirst(8) {
            let v = l.split(separator: ",", omittingEmptySubsequences: false)
            guard v.count >= 19, let m = Int(v[1]), let d = Int(v[2]), let h = Int(v[3]) else { continue }
            func num(_ i: Int) -> Double? { Double(v[i].trimmingCharacters(in: .whitespaces)) }
            var dn = num(17) ?? 999999, dh = num(18) ?? 999999
            if dn >= 999900 || dn < 0 { dn = max(0, (num(14) ?? 0) >= 9999 ? 0 : (num(14) ?? 0) * 100) }
            if dh >= 999900 || dh < 0 { dh = max(0, (num(15) ?? 0) >= 9999 ? 0 : (num(15) ?? 0) * 120) }
            hours.append(ClimateHour(month: m, day: d, hour: h, directNormal: dn, diffuseHorizontal: dh))
        }
        guard hours.count >= 24 else { throw ParseError(message: "no hourly data") }
        return HourlyClimate(city: f[1], latitude: lat, longitude: lon, timeZone: tz, hours: hours)
    }

    /// A clear-sky year (ASHRAE clear-sky model, illuminance via luminous efficacy) when no weather file is available.
    public static func clearSky(latitude: Double, longitude: Double, timeZone: Double, clearness: Double = 0.6) -> HourlyClimate {
        var hours: [ClimateHour] = []
        let days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        for (mi, n) in days.enumerated() {
            for d in 1...n {
                for h in 1...24 {
                    let local = Double(h) - 0.5
                    var comps = DateComponents(); comps.year = 2021; comps.month = mi + 1; comps.day = d
                    let date = cal.date(from: comps)!.addingTimeInterval((local - timeZone) * 3600)
                    let s = SolarCalculator.position(date: date, latitude: latitude, longitude: longitude)
                    var dn = 0.0, dh = 0.0
                    if s.altitude > 0 {
                        let doy = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
                        let a = 1160 + 75 * sin(2 * .pi * (doy - 275) / 365), k = 0.174 + 0.035 * sin(2 * .pi * (doy - 100) / 365), c = 0.095 + 0.04 * sin(2 * .pi * (doy - 100) / 365)
                        let dni = a * exp(-k / sin(s.altitude * .pi / 180))
                        dn = dni * 100 * clearness
                        dh = (c * dni + dni * (1 - clearness) * 0.3) * 120
                    }
                    hours.append(ClimateHour(month: mi + 1, day: d, hour: h, directNormal: dn, diffuseHorizontal: dh))
                }
            }
        }
        return HourlyClimate(city: "Clear sky", latitude: latitude, longitude: longitude, timeZone: timeZone, hours: hours)
    }
}

public enum ClimateDaylight {
    public struct Options {
        public var gridSpacing = 600.0          // mm
        public var workPlane = 750.0            // mm
        public var edgeOffset = 300.0           // mm kept clear along the walls
        public var transmittance = 0.6
        public var threshold = 300.0            // lux (sDA)
        public var fraction = 0.5               // of occupied hours (sDA)
        public var aseThreshold = 1000.0        // lux (ASE)
        public var aseHours = 250               // hours (ASE)
        public var firstHour = 8, lastHour = 18 // occupied, local standard time
        public var interReflection = true
        public var maxPointsPerRoom = 400
        public init() {}
    }

    public struct PointResult: Hashable { public var p: Vec2; public var autonomy: Double; public var sunHours: Int }
    public struct RoomResult {
        public var id: EntityID
        public var name: String
        public var level: Int
        public var sDA: Double           // % of points
        public var ASE: Double           // % of points
        public var meanAutonomy: Double  // mean % of occupied hours ≥ threshold
        public var points: [PointResult]
        public var passesLM83: Bool { sDA >= 55 && ASE <= 10 }
    }

    struct Glazing { var a: Vec2; var b: Vec2; var s0: Double; var s1: Double; var z0: Double; var z1: Double }
    struct Obstacle { var a: Vec2; var b: Vec2; var z0: Double; var z1: Double; var glazing: [Glazing] }

    static func obstacles(_ doc: ArchiDocument) -> [Obstacle] {
        var out: [Obstacle] = []
        var byWall: [EntityID: Int] = [:]
        let mm = doc.units.mm
        for el in doc.elements {
            let lev = (doc.level(el.level)?.elevation ?? 0) * mm
            switch el.geometry {
            case .wall(let w):
                byWall[el.id] = out.count
                out.append(Obstacle(a: w.start * mm, b: w.end * mm, z0: lev + w.baseOffset * mm, z1: lev + (w.baseOffset + w.height) * mm, glazing: []))
            case .curtainWall(let c):
                let len = c.start.distance(to: c.end) * mm
                let z0 = lev + c.baseOffset * mm, z1 = z0 + c.height * mm
                out.append(Obstacle(a: c.start * mm, b: c.end * mm, z0: z0, z1: z1, glazing: [Glazing(a: c.start * mm, b: c.end * mm, s0: 0, s1: len, z0: z0, z1: z1)]))
            default: break
            }
        }
        for el in doc.elements {
            guard case .opening(let o) = el.geometry, o.kind == .window || o.kind == .opening, let wi = byWall[o.hostWall] else { continue }
            let z0 = out[wi].z0 + o.sill * mm
            out[wi].glazing.append(Glazing(a: out[wi].a, b: out[wi].b, s0: (o.offset - o.width / 2) * mm, s1: (o.offset + o.width / 2) * mm, z0: z0, z1: z0 + o.height * mm))
        }
        return out
    }

    /// Whether a ray from `p` (mm, absolute) in unit direction `d` escapes the building through glazing; returns the
    /// number of glazings crossed (nil = blocked).
    static func escapes(_ p: Vec3, _ d: Vec3, ceiling: Double, obstacles: [Obstacle]) -> Int? {
        let h = (d.x * d.x + d.y * d.y).squareRoot()
        guard h > 1e-9, d.z > 0 else { return nil }
        let dir = Vec2(d.x / h, d.y / h), slope = d.z / h
        var hits: [(t: Double, i: Int, s: Double)] = []
        for (i, o) in obstacles.enumerated() {
            let e = o.b - o.a
            let den = dir.cross(e)
            if abs(den) < 1e-12 { continue }
            let w = o.a - p.xy
            let t = w.cross(e) / den, u = w.cross(dir) / den
            if t > 1e-6, u >= -1e-9, u <= 1 + 1e-9 { hits.append((t, i, u * e.length)) }
        }
        hits.sort { $0.t < $1.t }
        let tCeil = (ceiling - p.z) / slope
        var crossed = 0
        for (k, hit) in hits.enumerated() {
            let z = p.z + hit.t * slope
            let o = obstacles[hit.i]
            if k == 0 || crossed == 0 { if hit.t > tCeil { return nil } }
            if z < o.z0 || z > o.z1 { continue }
            if o.glazing.contains(where: { hit.s >= $0.s0 && hit.s <= $0.s1 && z >= $0.z0 && z <= $0.z1 }) { crossed += 1; continue }
            return nil
        }
        return crossed > 0 ? crossed : nil
    }

    /// The 145 Tregenza sky patches: direction and CIE-overcast horizontal weight (sums to 1).
    static let skyPatches: [(dir: Vec3, weight: Double)] = {
        let bands: [(alt: Double, count: Int)] = [(6, 30), (18, 30), (30, 24), (42, 24), (54, 18), (66, 12), (78, 6)]
        var out: [(Vec3, Double)] = []
        for b in bands {
            let a0 = (b.alt - 6) * .pi / 180, a1 = (b.alt + 6) * .pi / 180, a = b.alt * .pi / 180
            let omega = 2 * .pi * (sin(a1) - sin(a0)) / Double(b.count)
            for k in 0..<b.count {
                let az = 2 * .pi * (Double(k) + 0.5) / Double(b.count)
                out.append((Vec3(cos(a) * cos(az), cos(a) * sin(az), sin(a)), (1 + 2 * sin(a)) / 3 * sin(a) * omega))
            }
        }
        let omegaZ = 2 * .pi * (1 - sin(84 * Double.pi / 180))
        out.append((Vec3(0, 0, 1), 1.0 * omegaZ))
        let total = out.reduce(0) { $0 + $1.1 }
        return out.map { ($0.0, $0.1 / total) }
    }()

    public static func analyse(_ doc: ArchiDocument, climate: HourlyClimate, options o: Options = Options(), rooms: Set<EntityID>? = nil) -> [RoomResult] {
        let obs = obstacles(doc)
        let mm = doc.units.mm
        // Occupied hours and sun directions (model coordinates).
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        struct Hour { var sun: Vec3?; var dni: Double; var dhi: Double }
        var hours: [Hour] = []
        for h in climate.hours where h.hour > o.firstHour && h.hour <= o.lastHour {
            var comps = DateComponents(); comps.year = 2021; comps.month = h.month; comps.day = h.day
            guard let day = cal.date(from: comps) else { continue }
            let date = day.addingTimeInterval((Double(h.hour) - 0.5 - climate.timeZone) * 3600)
            let s = SolarCalculator.position(date: date, latitude: climate.latitude, longitude: climate.longitude)
            hours.append(Hour(sun: s.altitude > 0 ? SolarCalculator.direction(s, northAngle: doc.info.northAngle) : nil, dni: h.directNormal, dhi: h.diffuseHorizontal))
        }
        let occupied = max(1, hours.count)
        var out: [RoomResult] = []
        for el in doc.elements {
            guard case .space(let sp) = el.geometry, sp.boundary.count >= 3, rooms?.contains(el.id) ?? true else { continue }
            let lev = (doc.level(el.level)?.elevation ?? 0) * mm
            let poly = sp.boundary.map { $0 * mm }
            let ceiling = lev + sp.height * mm
            let z0 = lev + o.workPlane
            let pts = sensorGrid(poly, o)
            // Internally reflected component (BRE split-flux), as a fraction of the diffuse horizontal illuminance.
            var irc = 0.0
            if o.interReflection {
                let area = abs(GeometryOps.signedArea(poly)), perim = zip(poly, poly.dropFirst() + [poly[0]]).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                let surfaces = 2 * area + perim * sp.height * mm
                var glass = 0.0
                for ob in obs where ob.z1 > lev && ob.z0 < ceiling {
                    for g in ob.glazing where near(ob, poly) { glass += (g.s1 - g.s0) * (min(g.z1, ceiling) - max(g.z0, lev)) }
                }
                let R = 0.5
                irc = surfaces > 0 ? o.transmittance * glass * (39 * 0.3 + 5 * 0.7) / (surfaces * (1 - R)) / 100 : 0
            }
            var results: [PointResult] = []
            for q in pts {
                let p = Vec3(q.x, q.y, z0)
                var sky = 0.0
                for patch in skyPatches { if let n = escapes(p, patch.dir, ceiling: ceiling, obstacles: obs) { sky += patch.weight * pow(o.transmittance, Double(n)) } }
                var ok = 0, sunHours = 0
                for hr in hours {
                    var e = hr.dhi * (sky + irc)
                    var direct = 0.0
                    if let s = hr.sun, hr.dni > 0, let n = escapes(p, s, ceiling: ceiling, obstacles: obs) { direct = hr.dni * s.z * pow(o.transmittance, Double(n)) }
                    e += direct
                    if e >= o.threshold { ok += 1 }
                    if direct >= o.aseThreshold { sunHours += 1 }
                }
                results.append(PointResult(p: q / mm, autonomy: Double(ok) / Double(occupied), sunHours: sunHours))
            }
            let n = Double(max(1, results.count))
            out.append(RoomResult(id: el.id, name: sp.number.isEmpty ? sp.name : "\(sp.number) \(sp.name)", level: el.level,
                                  sDA: 100 * Double(results.filter { $0.autonomy >= o.fraction }.count) / n,
                                  ASE: 100 * Double(results.filter { $0.sunHours > o.aseHours }.count) / n,
                                  meanAutonomy: 100 * results.reduce(0) { $0 + $1.autonomy } / n, points: results))
        }
        return out
    }

    /// Work-plane grid points (cell centres, mm) inside a room outline (mm), away from the walls; the spacing grows until
    /// the room has at most `maxPointsPerRoom` points.
    public static func sensorGrid(_ poly: [Vec2], _ o: Options) -> [Vec2] {
        var b = BBox2.empty; for q in poly { b.add(q) }
        var spacing = o.gridSpacing
        var pts: [Vec2] = []
        repeat {
            pts = []
            var y = b.min.y + spacing / 2
            while y < b.max.y {
                var x = b.min.x + spacing / 2
                while x < b.max.x {
                    let q = Vec2(x, y)
                    if GeometryOps.pointInPolygon(q, poly), distanceToBoundary(q, poly) >= min(o.edgeOffset, spacing / 2) { pts.append(q) }
                    x += spacing
                }
                y += spacing
            }
            if pts.count > o.maxPointsPerRoom { spacing *= 1.25 }
        } while pts.count > o.maxPointsPerRoom
        if pts.isEmpty { pts = [poly.reduce(Vec2.zero) { $0 + $1 } / Double(max(poly.count, 1))] }
        return pts
    }

    static func distanceToBoundary(_ p: Vec2, _ poly: [Vec2]) -> Double {
        var d = Double.infinity
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count], e = b - a
            let t = max(0, min(1, (p - a).dot(e) / max(e.lengthSquared, 1e-12)))
            d = min(d, p.distance(to: a + e * t))
        }
        return d
    }

    /// Whether a wall runs along the room boundary (within 400 mm).
    static func near(_ o: Obstacle, _ poly: [Vec2]) -> Bool {
        let m = (o.a + o.b) / 2
        return distanceToBoundary(m, poly) < 400 || distanceToBoundary(o.a, poly) < 400 && distanceToBoundary(o.b, poly) < 400
    }

    /// Report rows for agents / CSV.
    public static func json(_ r: [RoomResult]) -> [[String: Any]] {
        r.map { ["id": $0.id, "room": $0.name, "level": $0.level, "sDA300_50": (($0.sDA * 10).rounded() / 10), "ASE1000_250": (($0.ASE * 10).rounded() / 10),
                 "meanAutonomy": (($0.meanAutonomy * 10).rounded() / 10), "points": $0.points.count, "passesLM83": $0.passesLM83] }
    }
}
