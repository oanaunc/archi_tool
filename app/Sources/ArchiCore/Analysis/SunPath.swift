// Oanarina Archi Tool — GPL-3.0-or-later
// Sun path diagram (polar, equidistant altitude rings) drawn as 2D entities: horizon and altitude circles, compass
// rays and labels (rotated with project north), the sun's daily path for a date with hour marks, and optionally the
// solstice/equinox paths for reference.
import Foundation

public struct SunPathOptions {
    public var center: Vec2 = .zero
    public var radius: Double = 5000
    public var latitude: Double = 44.43
    public var longitude: Double = 26.10
    /// Hours east of UTC for the hour labels (local clock time).
    public var utcOffset: Double = 2
    public var northAngle: Double = 0
    /// Also draw 21 June, 21 March/September and 21 December.
    public var referencePaths = true
    public var layer = "A-SUNPATH"
    public var textHeight: Double = 200
    public init() {}
}

public enum SunPathDiagram {
    /// Plan point for a sun direction: altitude 90° at the centre, 0° on the horizon circle.
    public static func point(azimuth: Double, altitude: Double, options o: SunPathOptions) -> Vec2 {
        let r = o.radius * (90 - max(0, min(90, altitude))) / 90
        let a = .pi / 2 - rad(azimuth) + rad(o.northAngle)
        return o.center + Vec2(cos(a), sin(a)) * r
    }

    /// Sun positions (every `stepMinutes`) between sunrise and sunset of a local calendar date "YYYY-MM-DD".
    public static func path(day: String, options o: SunPathOptions, stepMinutes: Double = 10) -> [(time: Double, pos: SunPosition)] {
        var out: [(Double, SunPosition)] = []
        var m = 0.0
        while m <= 24 * 60 {
            let hh = Int(m / 60), mm = Int(m.truncatingRemainder(dividingBy: 60))
            if let d = SolarCalculator.date(day, String(format: "%02d:%02d", hh, mm), utcOffset: o.utcOffset) {
                let p = SolarCalculator.position(date: d, latitude: o.latitude, longitude: o.longitude)
                if p.altitude >= 0 { out.append((m / 60, p)) }
            }
            m += stepMinutes
        }
        return out
    }

    /// Diagram entities for `day` (local date).
    public static func entities(day: String, options o: SunPathOptions) -> [Entity] {
        var out: [Entity] = []
        func add(_ g: Geometry, color: ColorRef = .byLayer, props: [String: String] = [:]) { out.append(Entity(layer: o.layer, color: color, geometry: g, props: props)) }
        // Altitude rings every 15° (horizon bold) and labels.
        for alt in stride(from: 0.0, to: 90.0, by: 15) {
            add(.circle(CircleGeom(o.center, o.radius * (90 - alt) / 90)), color: alt == 0 ? .byLayer : .aci(8), props: ["sunpath": "altitude", "altitude": fmt(alt)])
            if alt > 0 { add(.text(TextGeom(position: point(azimuth: 180, altitude: alt, options: o) + Vec2(o.textHeight * 0.3, 0), height: o.textHeight * 0.7, content: "\(Int(alt))°", valign: .middle)), color: .aci(8)) }
        }
        // Azimuth rays every 30° and compass labels.
        for az in stride(from: 0.0, to: 360.0, by: 30) {
            add(.line(LineGeom(o.center, point(azimuth: az, altitude: 0, options: o))), color: .aci(8), props: ["sunpath": "azimuth", "azimuth": fmt(az)])
            let names: [Double: String] = [0: "N", 90: "E", 180: "S", 270: "W"]
            let lp = point(azimuth: az, altitude: 0, options: o) + (point(azimuth: az, altitude: 0, options: o) - o.center).normalized * o.textHeight * 1.2
            add(.text(TextGeom(position: lp, height: names[az] != nil ? o.textHeight * 1.4 : o.textHeight * 0.8, content: names[az] ?? "\(Int(az))°", halign: .center, valign: .middle)))
        }
        // Reference paths (solstices, equinox) of the same year.
        let year = day.split(separator: "-").first.map(String.init) ?? "2025"
        if o.referencePaths {
            for (d, label) in [("\(year)-06-21", "21 Jun"), ("\(year)-03-20", "20 Mar / 22 Sep"), ("\(year)-12-21", "21 Dec")] where d != day {
                let pts = path(day: d, options: o).map { point(azimuth: $0.pos.azimuth, altitude: $0.pos.altitude, options: o) }
                guard pts.count >= 2 else { continue }
                add(.polyline(PolylineGeom(points: pts)), color: .aci(9), props: ["sunpath": "reference", "date": d])
                let mid = pts[pts.count / 2]
                add(.text(TextGeom(position: mid + Vec2(0, o.textHeight * 0.6), height: o.textHeight * 0.7, content: label, halign: .center, valign: .bottom)), color: .aci(9))
            }
        }
        // The day's path with hour marks.
        let p = path(day: day, options: o, stepMinutes: 5)
        let pts = p.map { point(azimuth: $0.pos.azimuth, altitude: $0.pos.altitude, options: o) }
        if pts.count >= 2 { add(.polyline(PolylineGeom(points: pts)), color: .aci(30), props: ["sunpath": "path", "date": day]) }
        for (t, pos) in p where abs(t - t.rounded()) < 1e-6 {
            let q = point(azimuth: pos.azimuth, altitude: pos.altitude, options: o)
            add(.circle(CircleGeom(q, o.textHeight * 0.25)), color: .aci(30), props: ["sunpath": "hour", "hour": "\(Int(t))", "azimuth": fmt(pos.azimuth, 2), "altitude": fmt(pos.altitude, 2)])
            add(.text(TextGeom(position: q + Vec2(0, o.textHeight * 0.5), height: o.textHeight * 0.7, content: "\(Int(t))h", halign: .center, valign: .bottom)), color: .aci(30))
        }
        add(.text(TextGeom(position: o.center + Vec2(0, -o.radius - o.textHeight * 3.5), height: o.textHeight, content: "Sun path \(day)  \(fmt(o.latitude, 3))°, \(fmt(o.longitude, 3))°  (UTC\(o.utcOffset >= 0 ? "+" : "")\(fmt(o.utcOffset)))", halign: .center, valign: .top)))
        return out
    }
}
