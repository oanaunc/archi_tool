// Oanarina Archi Tool — GPL-3.0-or-later
// Seasonal heating energy balance (EN ISO 13790 seasonal method): transmission and ventilation losses from degree days,
// solar gains per window orientation, internal gains and the gain utilisation factor. Climate data come from a table of
// typical heating degree days (base 18 °C) and heating-season length by latitude, overridable per project.
import Foundation

public struct ClimateData: Hashable {
    /// Heating degree days (K·d, base 18 °C) and heating season length (days).
    public var degreeDays: Double
    public var heatingDays: Double
    /// Fraction of clear-sky irradiation reaching the ground on average in the heating season.
    public var clearness: Double
    public var source: String

    /// Typical continental/maritime values by absolute latitude (°): (lat, HDD18, heating days).
    public static let latitudeTable: [(Double, Double, Double)] = [
        (0, 0, 0), (15, 0, 0), (20, 150, 30), (25, 500, 90), (30, 1000, 120), (35, 1500, 150), (40, 2200, 180),
        (45, 2900, 200), (50, 3400, 220), (55, 4000, 245), (60, 4800, 270), (65, 5800, 300), (70, 7000, 330), (80, 9000, 365), (90, 10000, 365),
    ]

    /// Linear interpolation in the latitude table.
    public static func fromLatitude(_ lat: Double) -> ClimateData {
        let a = min(90, abs(lat))
        let t = latitudeTable
        var hdd = t.last!.1, days = t.last!.2
        for i in 0..<(t.count - 1) where a >= t[i].0 && a <= t[i + 1].0 {
            let f = (a - t[i].0) / (t[i + 1].0 - t[i].0)
            hdd = t[i].1 + f * (t[i + 1].1 - t[i].1); days = t[i].2 + f * (t[i + 1].2 - t[i].2)
            break
        }
        return ClimateData(degreeDays: hdd, heatingDays: days, clearness: 0.45, source: "latitude table (\(fmt(a, 1))°)")
    }

    /// Project climate: HDD / HEATINGDAYS / CLEARNESS variables override the latitude table.
    public static func from(_ doc: ArchiDocument) -> ClimateData {
        var c = fromLatitude(doc.info.latitude)
        if let v = doc.variable("HDD").flatMap(Double.init) { c.degreeDays = v; c.source = "project HDD" }
        if let v = doc.variable("HEATINGDAYS").flatMap(Double.init) { c.heatingDays = v }
        if let v = doc.variable("CLEARNESS").flatMap(Double.init) { c.clearness = v }
        return c
    }

    /// Months (1…12) of the heating season with the number of heating days in each, centred on mid-winter
    /// (15 January in the northern hemisphere, 15 July in the southern).
    public func seasonMonths(latitude: Double) -> [(month: Int, days: Double)] {
        let lengths = [31.0, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let center = latitude >= 0 ? 1 : 7
        var order = [center]
        for k in 1...6 { order.append((center - 1 + k) % 12 + 1); if k < 6 { order.append((center - 1 - k + 12) % 12 + 1) } }
        var left = max(0, min(365, heatingDays))
        var out: [(Int, Double)] = []
        for m in order where left > 0 {
            let d = min(lengths[m - 1], left)
            out.append((m, d)); left -= d
        }
        return out.sorted { $0.0 < $1.0 }
    }
}

public struct EnergyBalanceOptions {
    public var indoor = 20.0
    public var airChanges = 0.5
    public var thermalBridge = 0.05
    public var groundFactor = 0.5
    /// Total solar energy transmittance of the glazing, glazed fraction of the window (1 − frame), shading factor.
    public var gValue = 0.6
    public var frameFactor = 0.7
    public var shading = 0.9
    /// Internal gains (W/m² of floor).
    public var internalGains = 4.0
    /// Effective heat capacity per floor area (J/K·m², medium construction 165 000).
    public var heatCapacity = 165_000.0
    public var year = 2025
    public init() {}
    public static func from(_ doc: ArchiDocument) -> EnergyBalanceOptions {
        var o = EnergyBalanceOptions()
        func v(_ n: String) -> Double? { doc.variable(n).flatMap(Double.init) }
        o.indoor = v("HEATINDOOR") ?? o.indoor; o.airChanges = v("AIRCHANGES") ?? o.airChanges; o.thermalBridge = v("THERMALBRIDGE") ?? o.thermalBridge
        o.groundFactor = v("GROUNDFACTOR") ?? o.groundFactor; o.gValue = v("GVALUE") ?? o.gValue; o.frameFactor = v("FRAMEFACTOR") ?? o.frameFactor
        o.shading = v("SHADINGFACTOR") ?? o.shading; o.internalGains = v("INTERNALGAINS") ?? o.internalGains; o.heatCapacity = v("HEATCAPACITY") ?? o.heatCapacity
        return o
    }
}

public struct SolarGainRow: Hashable {
    /// Compass orientation (N, NE, E, SE, S, SW, W, NW; "H" for horizontal glazing).
    public var orientation: String
    public var windows: [EntityID]
    /// Window area (m²), heating-season irradiation (kWh/m²) and usable solar gain (kWh).
    public var area: Double
    public var irradiation: Double
    public var gain: Double
}

public struct EnergyBalance {
    public var climate: ClimateData
    public var transmissionH: Double      // W/K
    public var ventilationH: Double       // W/K
    public var floorArea: Double          // m²
    public var losses: Double             // kWh
    public var solarRows: [SolarGainRow]
    public var internalGains: Double      // kWh
    public var utilisation: Double
    public var timeConstant: Double       // h
    public var solarGains: Double { solarRows.reduce(0) { $0 + $1.gain } }
    public var gains: Double { solarGains + internalGains }
    /// Heating need (kWh/a) and per floor area (kWh/m²a).
    public var heatingNeed: Double { max(0, losses - utilisation * gains) }
    public var specificNeed: Double { floorArea > 0 ? heatingNeed / floorArea : 0 }

    public static func compass(_ azimuth: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        var a = azimuth.truncatingRemainder(dividingBy: 360); if a < 0 { a += 360 }
        return names[Int((a + 22.5) / 45) % 8]
    }

    /// Gain utilisation factor η = (1 − γ^a)/(1 − γ^(a+1)), a = 1 + τ/15 (EN ISO 13790 12.2.1.1).
    public static func utilisation(gamma: Double, timeConstant tau: Double) -> Double {
        let a = 1 + tau / 15
        guard gamma > 0 else { return 1 }
        if abs(gamma - 1) < 1e-9 { return a / (a + 1) }
        return (1 - pow(gamma, a)) / (1 - pow(gamma, a + 1))
    }

    public static func compute(_ doc: ArchiDocument, climate: ClimateData? = nil, options o: EnergyBalanceOptions = EnergyBalanceOptions()) -> EnergyBalance {
        let cl = climate ?? ClimateData.from(doc)
        var ho = HeatLossOptions()
        ho.indoor = o.indoor; ho.airChanges = o.airChanges; ho.thermalBridge = o.thermalBridge; ho.groundFactor = o.groundFactor; ho.degreeDays = cl.degreeDays
        let hl = HeatLoss.compute(doc, options: ho)
        let losses = (hl.transmission + hl.ventilation) * cl.degreeDays * 24 / 1000
        // Seasonal irradiation per window orientation: clear-sky daily sums on the 15th of each heating month × days × clearness.
        var byOrientation: [String: (ids: [EntityID], area: Double, kwh: Double)] = [:]
        var winArea: [EntityID: (Double, String)] = [:]
        var irr: [String: Double] = [:]
        let utc = (doc.info.longitude / 15).rounded()
        for (m, days) in cl.seasonMonths(latitude: doc.info.latitude) {
            let day = String(format: "%04d-%02d-15", o.year, m)
            for r in SolarRadiation.surfaces(doc, day: day, utcOffset: utc) where r.kind == "window" {
                let name = r.tilt < 45 ? "H" : compass(r.azimuth)
                winArea[r.id] = (r.area, name)
                irr["\(r.id)", default: 0] += r.kWhPerM2 * days * cl.clearness
            }
        }
        for (id, v) in winArea.sorted(by: { $0.key < $1.key }) {
            let i = irr["\(id)"] ?? 0
            var cur = byOrientation[v.1] ?? ([], 0, 0)
            cur.ids.append(id); cur.area += v.0; cur.kwh += i * v.0
            byOrientation[v.1] = cur
        }
        let order = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "H"]
        let rows = order.compactMap { k -> SolarGainRow? in
            guard let v = byOrientation[k], v.area > 0 else { return nil }
            return SolarGainRow(orientation: k, windows: v.ids, area: v.area, irradiation: v.kwh / v.area,
                                gain: v.kwh * o.gValue * o.frameFactor * o.shading)
        }
        let internalKWh = o.internalGains * hl.floorArea * cl.heatingDays * 24 / 1000
        let h = hl.transmission + hl.ventilation
        let tau = h > 0 ? o.heatCapacity * hl.floorArea / (h * 3600) : 0
        let gainsTotal = rows.reduce(0) { $0 + $1.gain } + internalKWh
        let eta = losses > 0 ? utilisation(gamma: gainsTotal / losses, timeConstant: tau) : 0
        return EnergyBalance(climate: cl, transmissionH: hl.transmission, ventilationH: hl.ventilation, floorArea: hl.floorArea, losses: losses,
                             solarRows: rows, internalGains: internalKWh, utilisation: eta, timeConstant: tau)
    }

    public var table: [[String]] {
        var t = [["item", "orientation", "area_m2", "irradiation_kWh_m2", "kWh"]]
        t.append(["transmission losses", "", "", "", fmt(transmissionH * climate.degreeDays * 24 / 1000, 0)])
        t.append(["ventilation losses", "", "", "", fmt(ventilationH * climate.degreeDays * 24 / 1000, 0)])
        for r in solarRows { t.append(["solar gain", r.orientation, fmt(r.area, 2), fmt(r.irradiation, 1), fmt(r.gain, 0)]) }
        t.append(["internal gains", "", "", "", fmt(internalGains, 0)])
        t.append(["utilisation factor", "", "", "", fmt(utilisation, 3)])
        t.append(["heating need", "", fmt(floorArea, 1), "", fmt(heatingNeed, 0)])
        return t
    }

    public var report: String {
        var s = "Climate: \(fmt(climate.degreeDays, 0)) K·d, \(fmt(climate.heatingDays, 0)) heating days (\(climate.source))\n"
        s += "Losses: \(fmt(losses, 0)) kWh (H = \(fmt(transmissionH, 1)) + \(fmt(ventilationH, 1)) W/K)\n"
        for r in solarRows { s += "  Solar \(r.orientation): \(fmt(r.area, 2)) m² × \(fmt(r.irradiation, 0)) kWh/m² → \(fmt(r.gain, 0)) kWh\n" }
        s += "Gains: solar \(fmt(solarGains, 0)) kWh + internal \(fmt(internalGains, 0)) kWh, utilisation η = \(fmt(utilisation, 3)) (τ = \(fmt(timeConstant, 1)) h)\n"
        s += "Heating need: \(fmt(heatingNeed, 0)) kWh/a"
        if floorArea > 0 { s += " = \(fmt(specificNeed, 1)) kWh/m²a over \(fmt(floorArea, 1)) m²" }
        return s
    }
}
