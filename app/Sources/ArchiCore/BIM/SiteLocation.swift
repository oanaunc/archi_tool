// Oanarina Archi Tool — GPL-3.0-or-later
// Project geolocation (BIM-118): latitude/longitude, site elevation, time zone and true north, with a small city table.
import Foundation

public enum SiteLocation {
    public struct City: Hashable { public var name: String; public var latitude: Double; public var longitude: Double; public var elevation: Double; public var timeZone: String }

    public static let cities: [City] = [
        City(name: "Bucharest", latitude: 44.4268, longitude: 26.1025, elevation: 70, timeZone: "Europe/Bucharest"),
        City(name: "London", latitude: 51.5074, longitude: -0.1278, elevation: 11, timeZone: "Europe/London"),
        City(name: "Paris", latitude: 48.8566, longitude: 2.3522, elevation: 35, timeZone: "Europe/Paris"),
        City(name: "Berlin", latitude: 52.5200, longitude: 13.4050, elevation: 34, timeZone: "Europe/Berlin"),
        City(name: "Rome", latitude: 41.9028, longitude: 12.4964, elevation: 21, timeZone: "Europe/Rome"),
        City(name: "Madrid", latitude: 40.4168, longitude: -3.7038, elevation: 667, timeZone: "Europe/Madrid"),
        City(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041, elevation: -2, timeZone: "Europe/Amsterdam"),
        City(name: "Vienna", latitude: 48.2082, longitude: 16.3738, elevation: 190, timeZone: "Europe/Vienna"),
        City(name: "Athens", latitude: 37.9838, longitude: 23.7275, elevation: 70, timeZone: "Europe/Athens"),
        City(name: "Istanbul", latitude: 41.0082, longitude: 28.9784, elevation: 39, timeZone: "Europe/Istanbul"),
        City(name: "NewYork", latitude: 40.7128, longitude: -74.0060, elevation: 10, timeZone: "America/New_York"),
        City(name: "LosAngeles", latitude: 34.0522, longitude: -118.2437, elevation: 71, timeZone: "America/Los_Angeles"),
        City(name: "Chicago", latitude: 41.8781, longitude: -87.6298, elevation: 181, timeZone: "America/Chicago"),
        City(name: "MexicoCity", latitude: 19.4326, longitude: -99.1332, elevation: 2240, timeZone: "America/Mexico_City"),
        City(name: "SaoPaulo", latitude: -23.5505, longitude: -46.6333, elevation: 760, timeZone: "America/Sao_Paulo"),
        City(name: "Tokyo", latitude: 35.6762, longitude: 139.6503, elevation: 40, timeZone: "Asia/Tokyo"),
        City(name: "Singapore", latitude: 1.3521, longitude: 103.8198, elevation: 15, timeZone: "Asia/Singapore"),
        City(name: "Dubai", latitude: 25.2048, longitude: 55.2708, elevation: 5, timeZone: "Asia/Dubai"),
        City(name: "Mumbai", latitude: 19.0760, longitude: 72.8777, elevation: 14, timeZone: "Asia/Kolkata"),
        City(name: "Sydney", latitude: -33.8688, longitude: 151.2093, elevation: 58, timeZone: "Australia/Sydney"),
        City(name: "Cairo", latitude: 30.0444, longitude: 31.2357, elevation: 23, timeZone: "Africa/Cairo"),
        City(name: "CapeTown", latitude: -33.9249, longitude: 18.4241, elevation: 25, timeZone: "Africa/Johannesburg"),
    ]

    public static func city(_ n: String) -> City? {
        let k = n.lowercased().filter { $0.isLetter }
        return cities.first { $0.name.lowercased() == k }
    }

    /// UTC offset (hours) of the project's time zone at a date, falling back to the UTCOFFSET variable and then longitude/15.
    public static func utcOffset(_ doc: ArchiDocument, at date: Date = Date()) -> Double {
        if let tz = doc.info.timeZone.flatMap(TimeZone.init(identifier:)) { return Double(tz.secondsFromGMT(for: date)) / 3600 }
        if let v = doc.variable("UTCOFFSET").flatMap(Double.init) { return v }
        return (doc.info.longitude / 15).rounded()
    }

    /// Validates and stores a location. Returns an error message for out-of-range values.
    public static func set(_ doc: inout ArchiDocument, latitude: Double, longitude: Double, elevation: Double? = nil, timeZone: String? = nil, north: Double? = nil) -> String? {
        guard (-90...90).contains(latitude) else { return "Latitude must be within ±90°." }
        guard (-180...180).contains(longitude) else { return "Longitude must be within ±180°." }
        if let tz = timeZone, TimeZone(identifier: tz) == nil { return "Unknown time zone \(tz)." }
        doc.info.latitude = latitude; doc.info.longitude = longitude
        if let e = elevation { doc.info.elevation = e }
        if let tz = timeZone { doc.info.timeZone = tz; doc.setVariable("UTCOFFSET", fmt(utcOffset(doc), 2)) }
        if let n = north { doc.info.northAngle = n }
        return nil
    }

    /// "44.4268° N, 26.1025° E" style text.
    public static func describe(_ doc: ArchiDocument) -> String {
        let i = doc.info
        return "\(fmt(abs(i.latitude), 4))° \(i.latitude >= 0 ? "N" : "S"), \(fmt(abs(i.longitude), 4))° \(i.longitude >= 0 ? "E" : "W"), elevation \(fmt(i.elevation, 1)) m, "
            + "time zone \(i.timeZone ?? "UTC\(fmt(utcOffset(doc), 2))"), true north \(fmt(i.northAngle, 2))°"
    }
}
