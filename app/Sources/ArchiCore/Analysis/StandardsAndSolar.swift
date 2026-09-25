// Oanarina Archi Tool — GPL-3.0-or-later
// Drawing standards checker (layers, properties by layer, text heights/styles, linetypes; rules in JSON) and clear-sky
// solar irradiation on envelope surfaces (Meinel beam model, isotropic diffuse and ground reflection).
import Foundation

public struct DrawingStandards: Codable, Hashable {
    public var name: String = "Drawing standard"
    /// Regular expression every layer name must match (e.g. AIA "^[A-Z]-[A-Z]{4}(-[A-Z0-9]{4})*$").
    public var layerPattern: String? = nil
    public var requiredLayers: [String] = []
    public var noEntitiesOnLayer0 = true
    /// Colour / linetype / lineweight must be ByLayer.
    public var colorByLayer = true
    public var linetypeByLayer = false
    public var lineweightByLayer = false
    /// Allowed plotted text heights (mm on paper) at `plotScale` (1:n); empty = any.
    public var textHeights: [Double] = [1.8, 2.5, 3.5, 5, 7, 10]
    public var plotScale: Double = 100
    public var textStyles: [String] = []
    public var linetypes: [String] = []
    public init() {}

    enum K: String, CodingKey { case name, layerPattern, requiredLayers, noEntitiesOnLayer0, colorByLayer, linetypeByLayer, lineweightByLayer, textHeights, plotScale, textStyles, linetypes }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Drawing standard"
        layerPattern = try c.decodeIfPresent(String.self, forKey: .layerPattern)
        requiredLayers = try c.decodeIfPresent([String].self, forKey: .requiredLayers) ?? []
        noEntitiesOnLayer0 = try c.decodeIfPresent(Bool.self, forKey: .noEntitiesOnLayer0) ?? false
        colorByLayer = try c.decodeIfPresent(Bool.self, forKey: .colorByLayer) ?? false
        linetypeByLayer = try c.decodeIfPresent(Bool.self, forKey: .linetypeByLayer) ?? false
        lineweightByLayer = try c.decodeIfPresent(Bool.self, forKey: .lineweightByLayer) ?? false
        textHeights = try c.decodeIfPresent([Double].self, forKey: .textHeights) ?? []
        plotScale = try c.decodeIfPresent(Double.self, forKey: .plotScale) ?? 100
        textStyles = try c.decodeIfPresent([String].self, forKey: .textStyles) ?? []
        linetypes = try c.decodeIfPresent([String].self, forKey: .linetypes) ?? []
    }
    public static func fromJSON(_ text: String) throws -> DrawingStandards {
        do { return try JSONDecoder().decode(DrawingStandards.self, from: Data(text.utf8)) }
        catch { throw CodeRules.RulesError.invalid("\(error)") }
    }
    public var json: String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
    public static func from(_ doc: ArchiDocument) -> DrawingStandards {
        if let t = doc.variable("DRAWINGSTANDARDS"), let s = try? fromJSON(t) { return s }
        return DrawingStandards()
    }
}

public enum StandardsCheck {
    public static func check(_ doc: ArchiDocument, standards s: DrawingStandards = DrawingStandards()) -> [ModelIssue] {
        var out: [ModelIssue] = []
        func box(_ ids: [EntityID]) -> BBox2 {
            var b = BBox2.empty
            for id in ids.prefix(200) { if let e = doc.entity(id) { b = b.union(GeometryOps.bounds(e.geometry, doc: doc)) } }
            return b.isEmpty ? b : b.expanded(by: max(b.width, b.height) * 0.1 + 100 / doc.units.mm)
        }
        func issue(_ sev: IssueSeverity, _ c: String, _ m: String, _ ids: [EntityID]) { out.append(ModelIssue(severity: sev, code: c, message: m, ids: ids, bounds: box(ids))) }
        let byLayer = Dictionary(grouping: doc.entities, by: { $0.layer.uppercased() })
        if let pat = s.layerPattern, let re = try? NSRegularExpression(pattern: pat) {
            for l in doc.layers where l.name != "0" && l.name.uppercased() != "DEFPOINTS" {
                if re.firstMatch(in: l.name, range: NSRange(l.name.startIndex..., in: l.name)) == nil {
                    issue(.warning, "STD-LAYER-NAME", "Layer '\(l.name)' does not match the naming pattern \(pat)", (byLayer[l.name.uppercased()] ?? []).map(\.id))
                }
            }
        }
        for r in s.requiredLayers where doc.layer(named: r) == nil { issue(.warning, "STD-LAYER-MISSING", "Required layer '\(r)' is missing", []) }
        if s.noEntitiesOnLayer0, let z = byLayer["0"], !z.isEmpty {
            let drawn = z.filter { $0.props["attdef"] == nil }
            if !drawn.isEmpty { issue(.warning, "STD-LAYER-0", "\(drawn.count) object(s) are on layer 0", drawn.map(\.id)) }
        }
        let paperHeights = s.textHeights.map { $0 * s.plotScale / doc.units.mm }
        var colorIDs: [EntityID] = [], ltIDs: [EntityID] = [], lwIDs: [EntityID] = [], heightIDs: [EntityID] = [], styleIDs: [EntityID] = [], badLt: [EntityID] = []
        let allowedStyles = Set(s.textStyles.map { $0.lowercased() }), allowedLt = Set(s.linetypes.map { $0.lowercased() } + ["bylayer", "byblock", "continuous"])
        for e in doc.entities {
            if s.colorByLayer, e.color != .byLayer, e.color != .byBlock { colorIDs.append(e.id) }
            if let lt = e.linetype, lt.lowercased() != "bylayer" {
                if s.linetypeByLayer { ltIDs.append(e.id) }
                if !s.linetypes.isEmpty && !allowedLt.contains(lt.lowercased()) { badLt.append(e.id) }
            }
            if s.lineweightByLayer, e.lineweight != nil { lwIDs.append(e.id) }
            if case .text(let t) = e.geometry {
                if !paperHeights.isEmpty && !paperHeights.contains(where: { abs($0 - t.height) <= $0 * 0.01 }) { heightIDs.append(e.id) }
                if !allowedStyles.isEmpty && !allowedStyles.contains(t.style.lowercased()) { styleIDs.append(e.id) }
            }
        }
        if !colorIDs.isEmpty { issue(.info, "STD-COLOR-BYLAYER", "\(colorIDs.count) object(s) override the layer colour", colorIDs) }
        if !ltIDs.isEmpty { issue(.info, "STD-LINETYPE-BYLAYER", "\(ltIDs.count) object(s) override the layer linetype", ltIDs) }
        if !lwIDs.isEmpty { issue(.info, "STD-LINEWEIGHT-BYLAYER", "\(lwIDs.count) object(s) override the layer lineweight", lwIDs) }
        if !badLt.isEmpty { issue(.warning, "STD-LINETYPE", "\(badLt.count) object(s) use linetypes outside the standard", badLt) }
        if !heightIDs.isEmpty { issue(.warning, "STD-TEXT-HEIGHT", "\(heightIDs.count) text(s) are not \(s.textHeights.map { fmt($0, 2) }.joined(separator: "/")) mm at 1:\(fmt(s.plotScale))", heightIDs) }
        if !styleIDs.isEmpty { issue(.warning, "STD-TEXT-STYLE", "\(styleIDs.count) text(s) use styles outside \(s.textStyles.joined(separator: ", "))", styleIDs) }
        return out
    }
}

// MARK: - Solar irradiation

public enum SolarRadiation {
    /// Clear-sky irradiance (W/m²) on a surface with outward normal given by `azimuth` (° clockwise from north) and
    /// `tilt` (0 = horizontal facing up, 90 = vertical) for a sun position: beam (Meinel: 1353·0.7^(AM^0.678)),
    /// isotropic diffuse (10 % of beam normal) and ground reflection (albedo).
    public static func irradiance(sun p: SunPosition, azimuth: Double, tilt: Double, albedo: Double = 0.2) -> Double {
        guard p.altitude > 0 else { return 0 }
        let alt = rad(p.altitude)
        let am = 1 / (sin(alt) + 0.50572 * pow(p.altitude + 6.07995, -1.6364))
        let dni = 1353 * pow(0.7, pow(am, 0.678))
        let dhi = 0.1 * dni
        let ghi = dni * sin(alt) + dhi
        let t = rad(tilt), az = rad(azimuth), saz = rad(p.azimuth)
        let cosInc = sin(alt) * cos(t) + cos(alt) * sin(t) * cos(saz - az)
        return dni * max(0, cosInc) + dhi * (1 + cos(t)) / 2 + albedo * ghi * (1 - cos(t)) / 2
    }

    /// Daily irradiation (kWh/m²) for a local date, integrated in `stepMinutes` steps.
    public static func daily(day: String, latitude: Double, longitude: Double, utcOffset: Double, azimuth: Double, tilt: Double, stepMinutes: Double = 10) -> Double {
        var wh = 0.0
        var m = stepMinutes / 2
        while m < 1440 {
            if let d = SolarCalculator.date(day, String(format: "%02d:%02d:%02d", Int(m / 60), Int(m.truncatingRemainder(dividingBy: 60)), Int((m * 60).truncatingRemainder(dividingBy: 60))), utcOffset: utcOffset) {
                wh += irradiance(sun: SolarCalculator.position(date: d, latitude: latitude, longitude: longitude), azimuth: azimuth, tilt: tilt) * stepMinutes / 60
            }
            m += stepMinutes
        }
        return wh / 1000
    }

    public struct SurfaceRow: Hashable {
        public var id: EntityID
        public var kind: String
        public var azimuth: Double
        public var tilt: Double
        public var area: Double           // m²
        public var kWhPerM2: Double
        public var kWh: Double { area * kWhPerM2 }
    }

    /// Exterior walls (net of openings), windows and roofs with their daily clear-sky irradiation.
    public static func surfaces(_ doc: ArchiDocument, day: String, utcOffset: Double) -> [SurfaceRow] {
        let u = doc.units.mm / 1000
        let lat = doc.info.latitude, lon = doc.info.longitude
        var cache: [String: Double] = [:]
        func daily(_ az: Double, _ tilt: Double) -> Double {
            let key = "\(fmt(az, 1))/\(fmt(tilt, 1))"
            if let v = cache[key] { return v }
            let v = SolarRadiation.daily(day: day, latitude: lat, longitude: lon, utcOffset: utcOffset, azimuth: az, tilt: tilt)
            cache[key] = v; return v
        }
        // Outward direction of a wall: away from the level's wall centroid.
        var centroid: [Int: Vec2] = [:]
        for lv in Set(doc.elements.map(\.level)) {
            var pts: [Vec2] = []
            for e in doc.elements where e.level == lv { if case .wall(let w) = e.geometry { pts += [w.centerStart, w.centerEnd] } }
            if !pts.isEmpty { centroid[lv] = pts.reduce(.zero, +) / Double(pts.count) }
        }
        func azimuth(_ dir: Vec2) -> Double {
            var a = 90 - deg(atan2(dir.y, dir.x)) - doc.info.northAngle
            a = a.truncatingRemainder(dividingBy: 360); if a < 0 { a += 360 }
            return a
        }
        var rows: [SurfaceRow] = []
        for el in doc.elements {
            switch el.geometry {
            case .wall(let w):
                guard w.length > 1e-9, Thermal.isExterior(el, doc: doc) else { continue }
                let mid = (w.centerStart + w.centerEnd) / 2
                var n = w.direction.perp
                if let c = centroid[el.level], (mid - c).dot(n) < 0 { n = n * -1 }
                let az = azimuth(n)
                var openings = 0.0
                for oe in doc.elements { if case .opening(let o) = oe.geometry, o.hostWall == el.id, !o.isNiche {
                    let a = o.width * o.height * u * u
                    openings += a
                    if o.kind == .window { rows.append(SurfaceRow(id: oe.id, kind: "window", azimuth: az, tilt: 90, area: a, kWhPerM2: daily(az, 90))) }
                } }
                rows.append(SurfaceRow(id: el.id, kind: "wall", azimuth: az, tilt: 90, area: max(0, w.length * w.height * u * u - openings), kWhPerM2: daily(az, 90)))
            case .roof(let r):
                let plan = abs(GeometryOps.signedArea(r.boundary)) * u * u
                if r.kind == .flat || r.boundary.count < 3 {
                    rows.append(SurfaceRow(id: el.id, kind: "roof", azimuth: 180, tilt: 0, area: plan, kWhPerM2: daily(180, 0)))
                } else {
                    // Pitched: the planes face away from the eave edges; average over the edge orientations weighted by edge length.
                    var b = r.boundary
                    if GeometryOps.signedArea(b) < 0 { b.reverse() }
                    let edges: [Int] = r.kind == .hip ? Array(b.indices) : (r.kind == .shed ? [r.eaveEdge % b.count] : [r.eaveEdge % b.count, (r.eaveEdge + b.count / 2) % b.count])
                    let total = edges.reduce(0.0) { $0 + b[$1].distance(to: b[($1 + 1) % b.count]) }
                    let surf = plan / max(cos(rad(r.pitch)), 0.05)
                    var kwh = 0.0
                    for i in edges {
                        let a = b[i], c = b[(i + 1) % b.count]
                        let outward = Vec2((c - a).y, -(c - a).x).normalized
                        kwh += daily(azimuth(outward), r.pitch) * a.distance(to: c) / max(total, 1e-9)
                    }
                    rows.append(SurfaceRow(id: el.id, kind: "roof", azimuth: -1, tilt: r.pitch, area: surf, kWhPerM2: kwh))
                }
            default: continue
            }
        }
        return rows
    }
}
