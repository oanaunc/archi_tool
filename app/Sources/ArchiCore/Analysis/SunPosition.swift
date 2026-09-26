// Oanarina Archi Tool — GPL-3.0-or-later
// Solar position after the NOAA Solar Calculator (Meeus, "Astronomical Algorithms"); accuracy about ±0.01°
// for dates 1800–2100. Refraction correction as in the NOAA spreadsheet.
import Foundation

public struct SunPosition: Hashable {
    /// Degrees clockwise from true north.
    public var azimuth: Double
    /// Degrees above the horizon (refraction-corrected when requested).
    public var altitude: Double
    public var declination: Double
    /// Equation of time in minutes.
    public var equationOfTime: Double
    /// Hour angle in degrees (negative before solar noon).
    public var hourAngle: Double
    public var isUp: Bool { altitude > -0.833 }
}

public enum SolarCalculator {
    static func julianDay(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 + 2440587.5 }

    struct Ephemeris { var decl: Double; var eot: Double }

    static func ephemeris(jd: Double) -> Ephemeris {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mr = rad(m)
        let c = sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * mr) * (0.019993 - 0.000101 * t) + sin(3 * mr) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = deg(asin(sin(rad(eps)) * sin(rad(lambda))))
        let y = pow(tan(rad(eps / 2)), 2)
        let l0r = rad(l0)
        let eot = 4 * deg(y * sin(2 * l0r) - 2 * e * sin(mr) + 4 * e * y * sin(mr) * cos(2 * l0r) - 0.5 * y * y * sin(4 * l0r) - 1.25 * e * e * sin(2 * mr))
        return Ephemeris(decl: decl, eot: eot)
    }

    /// Sun position for a UTC instant at latitude/longitude (degrees, east positive).
    public static func position(date: Date, latitude: Double, longitude: Double, refraction: Bool = true) -> SunPosition {
        let jd = julianDay(date)
        let eph = ephemeris(jd: jd)
        let minutesUTC = (jd + 0.5 - (jd + 0.5).rounded(.down)) * 1440
        var tst = (minutesUTC + eph.eot + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if tst < 0 { tst += 1440 }
        var ha = tst / 4 - 180
        if ha < -180 { ha += 360 }
        let lat = rad(latitude), dec = rad(eph.decl), h = rad(ha)
        let cosZ = max(-1, min(1, sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(h)))
        let zen = acos(cosZ)
        var alt = 90 - deg(zen)
        // Azimuth from north, clockwise.
        var az = deg(atan2(sin(h), cos(h) * sin(lat) - tan(dec) * cos(lat))) + 180
        az = az.truncatingRemainder(dividingBy: 360); if az < 0 { az += 360 }
        if refraction { alt += refractionCorrection(alt) }
        return SunPosition(azimuth: az, altitude: alt, declination: eph.decl, equationOfTime: eph.eot, hourAngle: ha)
    }

    /// Atmospheric refraction in degrees for an apparent geometric elevation (NOAA approximation).
    public static func refractionCorrection(_ e: Double) -> Double {
        if e > 85 { return 0 }
        let te = tan(rad(e))
        let arcsec: Double
        if e > 5 { arcsec = 58.1 / te - 0.07 / pow(te, 3) + 0.000086 / pow(te, 5) }
        else if e > -0.575 { arcsec = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711))) }
        else { arcsec = -20.772 / te }
        return arcsec / 3600
    }

    /// Sunrise, solar noon and sunset (UTC) for the UTC calendar day of `date`. Sunrise/sunset are nil in polar day/night.
    public static func sunTimes(date: Date, latitude: Double, longitude: Double) -> (sunrise: Date?, noon: Date, sunset: Date?) {
        let jd0 = (julianDay(date) - 0.5).rounded(.down) + 0.5   // 0h UTC of that day
        let dayStart = Date(timeIntervalSince1970: (jd0 - 2440587.5) * 86400)
        func noonMinutes() -> Double {
            var n = 720 - 4 * longitude
            for _ in 0..<3 { n = 720 - 4 * longitude - ephemeris(jd: jd0 + n / 1440).eot }
            return n
        }
        let noon = noonMinutes()
        func event(_ rising: Bool) -> Double? {
            var t = noon
            for _ in 0..<4 {
                let eph = ephemeris(jd: jd0 + t / 1440)
                let lat = rad(latitude), dec = rad(eph.decl)
                let c = (cos(rad(90.833)) / (cos(lat) * cos(dec))) - tan(lat) * tan(dec)
                guard c >= -1 && c <= 1 else { return nil }
                let ha = deg(acos(c))
                let n = 720 - 4 * longitude - eph.eot
                t = rising ? n - 4 * ha : n + 4 * ha
            }
            return t
        }
        let rise = event(true).map { dayStart.addingTimeInterval($0 * 60) }
        let set = event(false).map { dayStart.addingTimeInterval($0 * 60) }
        return (rise, dayStart.addingTimeInterval(noon * 60), set)
    }

    /// Unit vector pointing to the sun in model coordinates (Z up) for a plan whose north is rotated `northAngle` degrees
    /// counter-clockwise from +Y (ProjectInfo.northAngle).
    public static func direction(_ p: SunPosition, northAngle: Double = 0) -> Vec3 {
        let alt = rad(p.altitude), az = rad(p.azimuth)
        // Azimuth is clockwise from north; north is +Y rotated by northAngle.
        let planAngle = .pi / 2 - az + rad(northAngle)
        return Vec3(cos(alt) * cos(planAngle), cos(alt) * sin(planAngle), sin(alt))
    }

    /// Parses "YYYY-MM-DD" and "HH:MM[:SS]" in a fixed UTC offset (hours).
    public static func date(_ day: String, _ time: String, utcOffset: Double) -> Date? {
        let d = day.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).compactMap { Int($0) }
        let t = time.split(separator: ":").compactMap { Double($0) }
        guard d.count == 3, !t.isEmpty else { return nil }
        var c = DateComponents()
        c.year = d[0]; c.month = d[1]; c.day = d[2]
        c.hour = 0; c.minute = 0; c.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let base = cal.date(from: c), (1...12).contains(d[1]), (1...31).contains(d[2]) else { return nil }
        let secs = t[0] * 3600 + (t.count > 1 ? t[1] * 60 : 0) + (t.count > 2 ? t[2] : 0)
        return base.addingTimeInterval(secs - utcOffset * 3600)
    }
}

// MARK: - Validation against published reference results (ANL-019)

/// A published solar-position result used to validate the calculator.
public struct SolarReference: Hashable {
    public var name: String
    public var source: String
    public var day: String, time: String, utcOffset: Double
    public var latitude: Double, longitude: Double
    /// Expected values; nil when the source does not give them.
    public var zenith: Double?, azimuth: Double?, declination: Double?, equationOfTime: Double?
    /// Expected local sunrise / sunset "HH:MM:SS".
    public var sunrise: String?, sunset: String?
}

public struct SolarValidationLine: Hashable {
    public var reference: String
    public var quantity: String
    public var expected: Double
    public var computed: Double
    public var tolerance: Double
    public var unit: String
    public var deviation: Double { computed - expected }
    public var passes: Bool { abs(deviation) <= tolerance }
}

extension SolarCalculator {
    /// Reference cases: the NREL Solar Position Algorithm worked example (Reda & Andreas, NREL/TP-560-34302, 2004)
    /// and the solar coordinates / equation of time examples 25.a and 28.a of Meeus, Astronomical Algorithms (1998).
    public static let references: [SolarReference] = [
        SolarReference(name: "NREL SPA example (Golden, CO)", source: "Reda & Andreas 2004, Table A5.1",
                       day: "2003-10-17", time: "12:30:30", utcOffset: -7, latitude: 39.742476, longitude: -105.1786,
                       zenith: 50.11162, azimuth: 194.34024, declination: nil, equationOfTime: 14.641503,
                       sunrise: "06:12:43", sunset: "17:20:19"),
        SolarReference(name: "Meeus example 25.a / 28.a", source: "Meeus, Astronomical Algorithms, 2nd ed.",
                       day: "1992-10-13", time: "00:00:00", utcOffset: 0, latitude: 0, longitude: 0,
                       zenith: nil, azimuth: nil, declination: -7.78507, equationOfTime: 13.71,
                       sunrise: nil, sunset: nil),
    ]

    /// Compares the calculator with every reference result. Tolerances: 0.05° for angles (the NREL case includes
    /// topocentric parallax and a site-pressure refraction the NOAA algorithm does not model), 0.1 min for the
    /// equation of time and 2 min for sunrise/sunset.
    public static func validate(_ refs: [SolarReference] = references) -> [SolarValidationLine] {
        var out: [SolarValidationLine] = []
        func seconds(_ s: String) -> Double? {
            let p = s.split(separator: ":").compactMap { Double($0) }
            guard p.count >= 2 else { return nil }
            return p[0] * 3600 + p[1] * 60 + (p.count > 2 ? p[2] : 0)
        }
        for r in refs {
            guard let date = SolarCalculator.date(r.day, r.time, utcOffset: r.utcOffset) else { continue }
            let p = position(date: date, latitude: r.latitude, longitude: r.longitude)
            if let z = r.zenith { out.append(.init(reference: r.name, quantity: "zenith", expected: z, computed: 90 - p.altitude, tolerance: 0.05, unit: "°")) }
            if let a = r.azimuth { out.append(.init(reference: r.name, quantity: "azimuth", expected: a, computed: p.azimuth, tolerance: 0.05, unit: "°")) }
            if let d = r.declination { out.append(.init(reference: r.name, quantity: "declination", expected: d, computed: p.declination, tolerance: 0.01, unit: "°")) }
            if let e = r.equationOfTime { out.append(.init(reference: r.name, quantity: "equation of time", expected: e, computed: p.equationOfTime, tolerance: 0.1, unit: "min")) }
            let t = sunTimes(date: date.addingTimeInterval(r.utcOffset * 3600), latitude: r.latitude, longitude: r.longitude)
            func localMinutes(_ d: Date?) -> Double? {
                guard let d else { return nil }
                let s = (d.timeIntervalSince1970 + r.utcOffset * 3600).truncatingRemainder(dividingBy: 86400)
                return (s < 0 ? s + 86400 : s) / 60
            }
            if let s = r.sunrise.flatMap(seconds), let c = localMinutes(t.sunrise) {
                out.append(.init(reference: r.name, quantity: "sunrise", expected: s / 60, computed: c, tolerance: 2, unit: "min"))
            }
            if let s = r.sunset.flatMap(seconds), let c = localMinutes(t.sunset) {
                out.append(.init(reference: r.name, quantity: "sunset", expected: s / 60, computed: c, tolerance: 2, unit: "min"))
            }
        }
        return out
    }
}
