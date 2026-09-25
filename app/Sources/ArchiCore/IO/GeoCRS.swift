// Oanarina Archi Tool — GPL-3.0-or-later
// Coordinate reference systems for geographic exchange (GeoJSON, shapefiles, OSM): WGS84 geographic, Web Mercator
// (EPSG:3857), UTM zones on WGS84 (EPSG:326xx north / 327xx south, transverse Mercator after Snyder, "Map
// Projections — A Working Manual", USGS PP 1395, eqs. 8-9 … 8-25) and ETRS89/UTM (EPSG:258xx, same ellipsoid to < 1 mm).
import Foundation

public enum GeoCRS: Equatable, CustomStringConvertible {
    case wgs84
    case webMercator
    case utm(zone: Int, north: Bool)
    /// Projected metres with no georeference (local engineering coordinates).
    case local

    static let a = 6_378_137.0
    static let f = 1 / 298.257223563
    static let k0 = 0.9996

    public var description: String {
        switch self {
        case .wgs84: return "EPSG:4326"
        case .webMercator: return "EPSG:3857"
        case .utm(let z, let n): return "EPSG:\(n ? 32600 + z : 32700 + z)"
        case .local: return "local"
        }
    }
    public var isGeographic: Bool { self == .wgs84 }

    /// Parses "EPSG:32635", "urn:ogc:def:crs:EPSG::3857", "http://www.opengis.net/def/crs/EPSG/0/4326", "CRS84", "UTM35N", "local".
    public static func parse(_ s0: String) -> GeoCRS? {
        let s = s0.trimmingCharacters(in: .whitespaces).uppercased()
        if s.isEmpty { return nil }
        if s == "LOCAL" || s == "METRES" || s == "METERS" { return .local }
        if s.hasSuffix("CRS84") || s == "WGS84" || s == "WGS 84" { return .wgs84 }
        if s.hasPrefix("UTM") {
            let body = s.dropFirst(3).trimmingCharacters(in: .whitespaces)
            let digits = body.prefix { $0.isNumber }
            guard let z = Int(digits), (1...60).contains(z) else { return nil }
            return .utm(zone: z, north: !body.dropFirst(digits.count).hasPrefix("S"))
        }
        // Trailing number = EPSG code.
        let code = Int(String(s.reversed().prefix { $0.isNumber }.reversed()))
        guard let c = code else { return nil }
        switch c {
        case 4326, 4258, 4979: return .wgs84
        case 3857, 900913, 3785: return .webMercator
        case 32601...32660: return .utm(zone: c - 32600, north: true)
        case 32701...32760: return .utm(zone: c - 32700, north: false)
        case 25828...25838: return .utm(zone: c - 25800, north: true) // ETRS89 / UTM
        default: return nil
        }
    }

    /// UTM zone of a longitude/latitude.
    public static func utmZone(lon: Double, lat: Double) -> GeoCRS {
        var z = Int(((lon + 180) / 6).rounded(.down)) + 1
        z = min(max(z, 1), 60)
        return .utm(zone: z, north: lat >= 0)
    }

    /// Projected metres (easting, northing) → (lon, lat) degrees.
    public func toLonLat(_ x: Double, _ y: Double) -> (lon: Double, lat: Double) {
        switch self {
        case .wgs84, .local: return (x, y)
        case .webMercator:
            let lon = x / GeoCRS.a * 180 / .pi
            let lat = (2 * atan(exp(y / GeoCRS.a)) - .pi / 2) * 180 / .pi
            return (lon, lat)
        case .utm(let zone, let north):
            let a = GeoCRS.a, f = GeoCRS.f, k0 = GeoCRS.k0
            let e2 = f * (2 - f), ep2 = e2 / (1 - e2)
            let lon0 = Double(zone * 6 - 183) * .pi / 180
            let xx = x - 500_000, yy = north ? y : y - 10_000_000
            let m = yy / k0
            let mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256))
            let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))
            let phi1 = mu + (3 * e1 / 2 - 27 * pow(e1, 3) / 32) * sin(2 * mu) + (21 * e1 * e1 / 16 - 55 * pow(e1, 4) / 32) * sin(4 * mu)
                + (151 * pow(e1, 3) / 96) * sin(6 * mu) + (1097 * pow(e1, 4) / 512) * sin(8 * mu)
            let s1 = sin(phi1), c1 = cos(phi1), t1 = tan(phi1)
            let n1 = a / sqrt(1 - e2 * s1 * s1)
            let r1 = a * (1 - e2) / pow(1 - e2 * s1 * s1, 1.5)
            let cc = ep2 * c1 * c1, tt = t1 * t1
            let d = xx / (n1 * k0)
            let lat = phi1 - (n1 * t1 / r1) * (d * d / 2 - (5 + 3 * tt + 10 * cc - 4 * cc * cc - 9 * ep2) * pow(d, 4) / 24
                + (61 + 90 * tt + 298 * cc + 45 * tt * tt - 252 * ep2 - 3 * cc * cc) * pow(d, 6) / 720)
            let lon = lon0 + (d - (1 + 2 * tt + cc) * pow(d, 3) / 6 + (5 - 2 * cc + 28 * tt - 3 * cc * cc + 8 * ep2 + 24 * tt * tt) * pow(d, 5) / 120) / c1
            return (lon * 180 / .pi, lat * 180 / .pi)
        }
    }

    /// (lon, lat) degrees → projected metres (easting, northing).
    public func fromLonLat(_ lon: Double, _ lat: Double) -> (x: Double, y: Double) {
        switch self {
        case .wgs84, .local: return (lon, lat)
        case .webMercator:
            let la = max(min(lat, 85.05112878), -85.05112878) * .pi / 180
            return (GeoCRS.a * lon * .pi / 180, GeoCRS.a * log(tan(.pi / 4 + la / 2)))
        case .utm(let zone, let north):
            let a = GeoCRS.a, f = GeoCRS.f, k0 = GeoCRS.k0
            let e2 = f * (2 - f), ep2 = e2 / (1 - e2)
            let phi = lat * .pi / 180, lam = lon * .pi / 180, lam0 = Double(zone * 6 - 183) * .pi / 180
            let s = sin(phi), c = cos(phi), t = tan(phi)
            let n = a / sqrt(1 - e2 * s * s)
            let tt = t * t, cc = ep2 * c * c, aa = c * (lam - lam0)
            let m = a * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * pow(e2, 3) / 256) * phi - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * pow(e2, 3) / 1024) * sin(2 * phi)
                + (15 * e2 * e2 / 256 + 45 * pow(e2, 3) / 1024) * sin(4 * phi) - (35 * pow(e2, 3) / 3072) * sin(6 * phi))
            let x = k0 * n * (aa + (1 - tt + cc) * pow(aa, 3) / 6 + (5 - 18 * tt + tt * tt + 72 * cc - 58 * ep2) * pow(aa, 5) / 120) + 500_000
            var y = k0 * (m + n * t * (aa * aa / 2 + (5 - tt + 9 * cc + 4 * cc * cc) * pow(aa, 4) / 24 + (61 - 58 * tt + tt * tt + 600 * cc - 330 * ep2) * pow(aa, 6) / 720))
            if !north { y += 10_000_000 }
            return (x, y)
        }
    }
}
