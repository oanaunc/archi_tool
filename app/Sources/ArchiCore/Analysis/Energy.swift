// Oanarina Archi Tool — GPL-3.0-or-later
// Building physics estimates: thermal transmittance of layered constructions (EN ISO 6946 simple method), steady-state
// design heat loss (transmission + ventilation, EN 12831-style simplified), annual heating demand from degree days,
// and the average daylight factor of rooms (BRE / Littlefair formula).
import Foundation

/// Thermal properties: conductivity λ (W/m·K) by material and U-values (W/m²·K) by component. Defaults come from
/// typical EN ISO 10456 design values; the drawing overrides them with variables LAMBDA:<material> and
/// UVALUE:<wall type | wall | roof | floor | window | door | curtainWall>, or an element's "uValue" prop.
public enum ThermalLibrary {
    public static let conductivity: [(String, Double)] = [
        ("insulation", 0.035), ("mineral wool", 0.035), ("rock wool", 0.036), ("glass wool", 0.035), ("eps", 0.035), ("xps", 0.034),
        ("pir", 0.023), ("pur", 0.025), ("cellulose", 0.04), ("cork", 0.045), ("wood fibre", 0.045),
        ("reinforced concrete", 2.3), ("aerated concrete", 0.16), ("lightweight concrete", 0.5), ("concrete", 2.0), ("screed", 1.4),
        ("brick", 0.77), ("clay block", 0.25), ("block", 1.1), ("stone", 2.3), ("granite", 2.8), ("marble", 2.8), ("limestone", 1.7),
        ("plasterboard", 0.25), ("gypsum", 0.25), ("plaster", 0.57), ("render", 0.87), ("mortar", 1.0),
        ("clt", 0.13), ("timber", 0.13), ("wood", 0.13), ("plywood", 0.13), ("osb", 0.13),
        ("steel", 50), ("aluminium", 160), ("aluminum", 160), ("copper", 380), ("glass", 1.0),
        ("tile", 1.3), ("ceramic", 1.3), ("bitumen", 0.23), ("membrane", 0.2), ("gravel", 2.0), ("soil", 1.5), ("earth", 1.5), ("grass", 1.5),
        ("carpet", 0.06), ("linoleum", 0.17), ("rubber", 0.17),
    ]
    public static let defaultU: [String: Double] = ["window": 1.3, "door": 1.8, "curtainWall": 1.6, "skylight": 1.4]

    /// λ of a material (W/m·K): LAMBDA:<name> variable, else the first library keyword the name contains, else nil.
    public static func lambda(_ material: String, doc: ArchiDocument) -> Double? {
        if let v = doc.variable("LAMBDA:" + material).flatMap(Double.init), v > 0 { return v }
        let n = material.lowercased()
        return conductivity.first { n.contains($0.0) }?.1
    }

    /// Surface resistances (m²K/W) by heat-flow direction (EN ISO 6946 Table 7): horizontal, upward (roofs), downward (floors).
    public static func surfaceResistance(_ component: String) -> (rsi: Double, rse: Double) {
        switch component {
        case "roof": return (0.10, 0.04)
        case "floor": return (0.17, 0.04)
        default: return (0.13, 0.04)
        }
    }

    public struct Layer: Hashable { public var material: String; public var thickness: Double; public var lambda: Double?
        public init(material: String, thickness: Double, lambda: Double?) { self.material = material; self.thickness = thickness; self.lambda = lambda } }

    /// U = 1 / (Rsi + Σ d/λ + Rse); thicknesses in metres. Layers with unknown λ count as 1.0 W/m·K (reported by the caller).
    public static func uValue(_ layers: [Layer], component: String = "wall") -> Double {
        let (rsi, rse) = surfaceResistance(component)
        let r = rsi + rse + layers.reduce(0) { $0 + max($1.thickness, 0) / max($1.lambda ?? 1.0, 1e-6) }
        return 1 / r
    }
}

public struct ConstructionU: Hashable {
    public var u: Double
    public var layers: [ThermalLibrary.Layer]
    /// Where the value came from: "layers", "override", "default".
    public var source: String
    public var assumed: [String]
}

public enum Thermal {
    /// U-value of a BIM element's construction (walls use their wall type plies; slabs/roofs their material and thickness).
    public static func uValue(_ el: BIMElement, doc: ArchiDocument, component: String? = nil) -> ConstructionU? {
        let comp = component ?? category(el)
        if let v = el.props["uValue"].flatMap(Double.init), v > 0 { return ConstructionU(u: v, layers: [], source: "override", assumed: []) }
        let mm = doc.units.mm / 1000
        func layered(_ layers: [ThermalLibrary.Layer], typeKey: String?) -> ConstructionU {
            if let k = typeKey, let v = doc.variable("UVALUE:" + k).flatMap(Double.init), v > 0 { return ConstructionU(u: v, layers: layers, source: "override", assumed: []) }
            if let v = doc.variable("UVALUE:" + comp).flatMap(Double.init), v > 0 { return ConstructionU(u: v, layers: layers, source: "override", assumed: []) }
            return ConstructionU(u: ThermalLibrary.uValue(layers, component: comp), layers: layers, source: "layers",
                                 assumed: layers.filter { $0.lambda == nil }.map(\.material))
        }
        switch el.geometry {
        case .wall(let w):
            if let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), !wt.plies.isEmpty {
                let k = wt.thickness > 0 ? w.thickness / wt.thickness : 1
                return layered(wt.plies.map { ThermalLibrary.Layer(material: $0.material, thickness: $0.thickness * k * mm, lambda: ThermalLibrary.lambda($0.material, doc: doc)) }, typeKey: tn)
            }
            let m = el.material ?? "Concrete"
            return layered([ThermalLibrary.Layer(material: m, thickness: w.thickness * mm, lambda: ThermalLibrary.lambda(m, doc: doc))], typeKey: w.wallType)
        case .slab(let s):
            let m = el.material ?? "Concrete"
            return layered([ThermalLibrary.Layer(material: m, thickness: s.thickness * mm, lambda: ThermalLibrary.lambda(m, doc: doc))], typeKey: nil)
        case .roof(let r):
            let m = el.material ?? "Concrete"
            return layered([ThermalLibrary.Layer(material: m, thickness: r.thickness * mm, lambda: ThermalLibrary.lambda(m, doc: doc))], typeKey: nil)
        case .opening(let o):
            let key = o.kind == .door ? "door" : "window"
            if let t = o.typeName, let v = doc.variable("UVALUE:" + t).flatMap(Double.init), v > 0 { return ConstructionU(u: v, layers: [], source: "override", assumed: []) }
            let v = doc.variable("UVALUE:" + key).flatMap(Double.init) ?? ThermalLibrary.defaultU[key] ?? 1.3
            return ConstructionU(u: v, layers: [], source: doc.variable("UVALUE:" + key) != nil ? "override" : "default", assumed: [])
        case .curtainWall:
            let v = doc.variable("UVALUE:curtainWall").flatMap(Double.init) ?? ThermalLibrary.defaultU["curtainWall"]!
            return ConstructionU(u: v, layers: [], source: "default", assumed: [])
        default: return nil
        }
    }

    static func category(_ el: BIMElement) -> String {
        switch el.geometry {
        case .wall: return "wall"
        case .slab: return "floor"
        case .roof: return "roof"
        case .curtainWall: return "curtainWall"
        case .opening(let o): return o.kind == .door ? "door" : "window"
        default: return el.typeName
        }
    }

    /// Whether a wall is part of the envelope: props isExternal, else its type name, else geometry (rooms on one side only,
    /// or — without rooms — lying on the convex hull of the level's walls).
    public static func isExterior(_ el: BIMElement, doc: ArchiDocument) -> Bool {
        guard case .wall(let w) = el.geometry else { return false }
        if let v = el.props["isExternal"] ?? el.props["IsExternal"] { return ["1", "true", "yes"].contains(v.lowercased()) }
        let t = (w.wallType ?? "").lowercased()
        if t.contains("exterior") || t.contains("external") || t.contains("facade") || t.contains("façade") { return true }
        if t.contains("partition") || t.contains("interior") || t.contains("internal") { return false }
        let u = doc.units.mm
        let rooms = doc.elements.compactMap { e -> [Vec2]? in
            guard e.level == el.level, e.props["areaScheme"] == nil, case .space(let s) = e.geometry, s.boundary.count >= 3 else { return nil }
            return s.boundary
        }
        let mid = (w.centerStart + w.centerEnd) / 2, n = w.direction.perp
        let off = w.thickness / 2 + 150 / u
        if !rooms.isEmpty {
            let a = rooms.contains { GeometryOps.pointInPolygon(mid + n * off, $0) }
            let b = rooms.contains { GeometryOps.pointInPolygon(mid - n * off, $0) }
            if a != b { return true }
            if a && b { return false }
        }
        // Convex hull of the level's wall ends.
        var pts: [Vec2] = []
        for e in doc.elements where e.level == el.level { if case .wall(let ww) = e.geometry { pts += [ww.centerStart, ww.centerEnd] } }
        let hull = convexHull(pts)
        guard hull.count >= 3 else { return true }
        let tol = w.thickness + 1 / u
        for i in 0..<hull.count {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            if segDist(mid, a, b) <= tol && segDist(w.centerStart, a, b) <= tol && segDist(w.centerEnd, a, b) <= tol { return true }
        }
        return false
    }

    /// Distance from p to the segment ab.
    public static func segDist(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let d = b - a, l2 = d.lengthSquared
        guard l2 > 1e-18 else { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(d) / l2))
        return p.distance(to: a + d * t)
    }

    /// Andrew's monotone chain (counter-clockwise).
    public static func convexHull(_ p0: [Vec2]) -> [Vec2] {
        let p = Array(Set(p0.map { [$0.x, $0.y] })).map { Vec2($0[0], $0[1]) }.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard p.count >= 3 else { return p }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in p { while lower.count >= 2 && (lower[lower.count - 1] - lower[lower.count - 2]).cross(q - lower[lower.count - 2]) <= 0 { lower.removeLast() }; lower.append(q) }
        for q in p.reversed() { while upper.count >= 2 && (upper[upper.count - 1] - upper[upper.count - 2]).cross(q - upper[upper.count - 2]) <= 0 { upper.removeLast() }; upper.append(q) }
        return Array(lower.dropLast() + upper.dropLast())
    }
}

// MARK: - Heat loss

public struct HeatLossOptions {
    /// Indoor and outdoor design temperatures (°C).
    public var indoor: Double = 20
    public var outdoor: Double = -15
    /// Air changes per hour for ventilation/infiltration.
    public var airChanges: Double = 0.5
    /// Temperature correction factor for floors on the ground (EN 12831 fg ≈ 0.45–0.5).
    public var groundFactor: Double = 0.5
    /// Thermal bridge surcharge on all envelope U-values (W/m²K).
    public var thermalBridge: Double = 0.05
    /// Heating degree days (K·d) for the annual demand estimate.
    public var degreeDays: Double = 3000
    public init() {}
    /// Reads HEATINDOOR, HEATOUTDOOR, AIRCHANGES, GROUNDFACTOR, THERMALBRIDGE, HDD variables.
    public static func from(_ doc: ArchiDocument) -> HeatLossOptions {
        var o = HeatLossOptions()
        func v(_ n: String) -> Double? { doc.variable(n).flatMap(Double.init) }
        o.indoor = v("HEATINDOOR") ?? o.indoor; o.outdoor = v("HEATOUTDOOR") ?? o.outdoor; o.airChanges = v("AIRCHANGES") ?? o.airChanges
        o.groundFactor = v("GROUNDFACTOR") ?? o.groundFactor; o.thermalBridge = v("THERMALBRIDGE") ?? o.thermalBridge; o.degreeDays = v("HDD") ?? o.degreeDays
        return o
    }
}

public struct HeatLossLine: Hashable {
    public var id: EntityID
    public var component: String
    public var name: String
    /// m²
    public var area: Double
    /// W/m²K (including the thermal-bridge surcharge)
    public var u: Double
    public var factor: Double
    /// W/K
    public var h: Double { area * u * factor }
}

public struct HeatLossReport {
    public var lines: [HeatLossLine]
    /// Transmission and ventilation heat-loss coefficients (W/K).
    public var transmission: Double
    public var ventilation: Double
    public var deltaT: Double
    /// Heated volume (m³) and floor area (m²).
    public var volume: Double
    public var floorArea: Double
    public var assumedMaterials: [String]
    public var degreeDays: Double
    public var designLoad: Double { (transmission + ventilation) * deltaT }
    /// kWh per year.
    public var annualDemand: Double { (transmission + ventilation) * degreeDays * 24 / 1000 }
    public var specificLoad: Double { floorArea > 0 ? designLoad / floorArea : 0 }
    public func total(_ component: String) -> Double { lines.filter { $0.component == component }.reduce(0) { $0 + $1.h } }

    public var table: [[String]] {
        var t = [["component", "id", "name", "area_m2", "U_W_m2K", "factor", "H_W_K", "loss_W"]]
        for l in lines { t.append([l.component, "\(l.id)", l.name, fmt(l.area, 2), fmt(l.u, 3), fmt(l.factor, 2), fmt(l.h, 2), fmt(l.h * deltaT, 0)]) }
        t.append(["ventilation", "", "", "", "", "", fmt(ventilation, 2), fmt(ventilation * deltaT, 0)])
        t.append(["TOTAL", "", "", "", "", "", fmt(transmission + ventilation, 2), fmt(designLoad, 0)])
        return t
    }
    public var report: String {
        var s = "Design heat loss at ΔT \(fmt(deltaT, 1)) K: \(fmt(designLoad / 1000, 2)) kW"
        if floorArea > 0 { s += " (\(fmt(specificLoad, 1)) W/m² over \(fmt(floorArea, 1)) m²)" }
        s += "\n"
        for c in ["wall", "window", "door", "curtainWall", "roof", "floor"] {
            let h = total(c)
            if h > 0 { s += "  \(c): H = \(fmt(h, 1)) W/K, \(fmt(h * deltaT, 0)) W\n" }
        }
        s += "  ventilation: H = \(fmt(ventilation, 1)) W/K (\(fmt(volume, 1)) m³), \(fmt(ventilation * deltaT, 0)) W\n"
        s += "Annual heating demand ≈ \(fmt(annualDemand, 0)) kWh (\(fmt(degreeDays, 0)) K·d)"
        if !assumedMaterials.isEmpty { s += "\nUnknown conductivity (1.0 W/m·K assumed): " + assumedMaterials.joined(separator: ", ") + " — set LAMBDA:<material>." }
        return s
    }
}

public enum HeatLoss {
    public static func compute(_ doc: ArchiDocument, options o: HeatLossOptions = HeatLossOptions()) -> HeatLossReport {
        let u = doc.units.mm / 1000
        var lines: [HeatLossLine] = []
        var assumed = Set<String>()
        let lowest = doc.levels.map(\.id).min { (doc.level($0)?.elevation ?? 0) < (doc.level($1)?.elevation ?? 0) } ?? 0
        func add(_ el: BIMElement, _ comp: String, area: Double, factor: Double = 1, cu: ConstructionU?) {
            guard area > 1e-9, let c = cu else { return }
            assumed.formUnion(c.assumed)
            lines.append(HeatLossLine(id: el.id, component: comp, name: el.name.isEmpty ? el.typeName : el.name, area: area, u: c.u + o.thermalBridge, factor: factor))
        }
        for el in doc.elements {
            switch el.geometry {
            case .wall(let w):
                guard Thermal.isExterior(el, doc: doc) else { continue }
                let len = ScheduleExporter.wallLength(w)
                var openings = 0.0
                for oe in doc.elements { if case .opening(let og) = oe.geometry, og.hostWall == el.id, !og.isNiche {
                    let a = max(0, min(og.width, len)) * max(0, min(og.sill + og.height, w.height) - max(og.sill, 0))
                    openings += a
                    if og.kind != .opening { add(oe, og.kind == .door ? "door" : "window", area: a * u * u, cu: Thermal.uValue(oe, doc: doc)) }
                } }
                add(el, "wall", area: max(0, len * w.height - openings) * u * u, cu: Thermal.uValue(el, doc: doc, component: "wall"))
            case .curtainWall(let c):
                if el.props["isExternal"].map({ ["0", "false", "no"].contains($0.lowercased()) }) ?? false { continue }
                add(el, "curtainWall", area: c.length * c.height * u * u, cu: Thermal.uValue(el, doc: doc))
            case .roof(let r):
                let plan = abs(GeometryOps.signedArea(r.boundary))
                let surf = r.kind == .flat ? plan : plan / max(cos(rad(r.pitch)), 0.05)
                add(el, "roof", area: surf * u * u, cu: Thermal.uValue(el, doc: doc, component: "roof"))
            case .slab(let s):
                let kind = el.props["kind"] ?? ""
                guard kind.isEmpty || kind == "floor", el.level == lowest, !s.isSloped else { continue }
                add(el, "floor", area: ScheduleExporter.slabArea(s) * u * u, factor: o.groundFactor, cu: Thermal.uValue(el, doc: doc, component: "floor"))
            default: continue
            }
        }
        // Heated volume and floor area from rooms, else from floor slabs × level height.
        var vol = 0.0, area = 0.0
        for el in doc.elements { if case .space(let s) = el.geometry, el.props["areaScheme"] == nil { let a = abs(GeometryOps.signedArea(s.boundary)) * u * u; area += a; vol += a * s.height * u } }
        if vol == 0 {
            for el in doc.elements {
                guard case .slab(let s) = el.geometry, (el.props["kind"] ?? "").isEmpty || el.props["kind"] == "floor" else { continue }
                let a = ScheduleExporter.slabArea(s) * u * u
                area += a; vol += a * (doc.level(el.level)?.height ?? 3000) * u
            }
        }
        let ht = lines.reduce(0) { $0 + $1.h }
        let hv = 0.34 * o.airChanges * vol
        return HeatLossReport(lines: lines, transmission: ht, ventilation: hv, deltaT: o.indoor - o.outdoor, volume: vol, floorArea: area,
                              assumedMaterials: assumed.sorted(), degreeDays: o.degreeDays)
    }
}

// MARK: - Rooms and their windows

public enum RoomOpenings {
    /// Windows (and glazed doors when `includeDoors`) in walls bounding a room, with their glazed area in m².
    public static func windows(of room: BIMElement, doc: ArchiDocument, includeDoors: Bool = false) -> [(id: EntityID, glazed: Double)] {
        guard case .space(let sp) = room.geometry, sp.boundary.count >= 3 else { return [] }
        let u = doc.units.mm / 1000
        var out: [(EntityID, Double)] = []
        for el in doc.elements {
            guard case .opening(let o) = el.geometry, o.kind == .window || (includeDoors && o.kind == .door),
                  let host = doc.element(o.hostWall), host.level == room.level, case .wall(let w) = host.geometry else { continue }
            let c = w.centerStart + w.direction * o.offset
            let off = w.thickness / 2 + 100 / doc.units.mm
            guard GeometryOps.pointInPolygon(c + w.direction.perp * off, sp.boundary) || GeometryOps.pointInPolygon(c - w.direction.perp * off, sp.boundary) else { continue }
            let f = min(o.frameWidth, min(o.width, o.height) / 4)
            let glazed = max(0, o.width - 2 * f) * max(0, o.height - 2 * f) * (o.kind == .door ? 0.5 : 1)
            out.append((el.id, glazed * u * u))
        }
        return out
    }
}

public struct DaylightRow: Hashable {
    public var id: EntityID
    public var number: String
    public var name: String
    public var floorArea: Double
    public var glazedArea: Double
    /// Average daylight factor (%).
    public var daylightFactor: Double
    /// Glazed area / floor area.
    public var windowToFloor: Double
    public var windows: [EntityID]
    public var rating: String { daylightFactor >= 5 ? "well daylit" : daylightFactor >= 2 ? "adequate" : "poor" }
}

public struct DaylightOptions {
    /// Diffuse visible transmittance of the glazing.
    public var transmittance = 0.7
    /// Visible sky angle θ in degrees (≈ 65° for an unobstructed vertical window).
    public var skyAngle = 65.0
    /// Area-weighted mean reflectance of the room surfaces.
    public var reflectance = 0.5
    /// Maintenance (dirt) factor.
    public var maintenance = 0.9
    public init() {}
}

public enum Daylight {
    /// Average daylight factor DF = T·Aw·θ·M / (A·(1−R²)) (%), with A the total room surface (floor, ceiling, walls).
    public static func averageDF(glazed: Double, floorArea: Double, perimeter: Double, height: Double, options o: DaylightOptions = DaylightOptions()) -> Double {
        let surfaces = 2 * floorArea + perimeter * height
        guard surfaces > 1e-9 else { return 0 }
        return o.transmittance * glazed * o.skyAngle * o.maintenance / (surfaces * (1 - o.reflectance * o.reflectance))
    }

    public static func compute(_ doc: ArchiDocument, level: Int? = nil, options: DaylightOptions = DaylightOptions()) -> [DaylightRow] {
        let u = doc.units.mm / 1000
        var rows: [DaylightRow] = []
        for el in doc.elements where level == nil || el.level == level {
            guard case .space(let s) = el.geometry, el.props["areaScheme"] == nil, s.boundary.count >= 3 else { continue }
            let a = abs(GeometryOps.signedArea(s.boundary)) * u * u
            let per = ScheduleExporter.perimeter(s.boundary) * u
            let wins = RoomOpenings.windows(of: el, doc: doc)
            let g = wins.reduce(0) { $0 + $1.glazed }
            rows.append(DaylightRow(id: el.id, number: s.number, name: s.name, floorArea: a, glazedArea: g,
                                    daylightFactor: averageDF(glazed: g, floorArea: a, perimeter: per, height: s.height * u, options: options),
                                    windowToFloor: a > 0 ? g / a : 0, windows: wins.map(\.id)))
        }
        return rows.sorted { ($0.number, $0.name, $0.id) < ($1.number, $1.name, $1.id) }
    }

    public static func table(_ rows: [DaylightRow]) -> [[String]] {
        [["number", "name", "floor_m2", "glazing_m2", "window_to_floor", "daylight_factor_pct", "rating"]] +
            rows.map { [$0.number, $0.name, fmt($0.floorArea, 2), fmt($0.glazedArea, 2), fmt($0.windowToFloor, 3), fmt($0.daylightFactor, 2), $0.rating] }
    }
}

// MARK: - Area schedule by level

public struct LevelAreaRow: Hashable {
    public var level: Int
    public var name: String
    public var elevation: Double
    /// Gross floor area (m²): floor slabs, else an area plan named "gross", else the rooms' gross areas.
    public var grossArea: Double
    /// Net (usable) area of the rooms (m²).
    public var netArea: Double
    public var rooms: Int
    public var grossSource: String
    public var efficiency: Double { grossArea > 0 ? netArea / grossArea : 0 }
}

public enum AreaSchedule {
    public static func compute(_ doc: ArchiDocument) -> [LevelAreaRow] {
        let u = doc.units.mm / 1000
        let rooms = RoomSchedule.compute(doc)
        var out: [LevelAreaRow] = []
        for lv in doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
            let rs = doc.elements.filter { $0.level == lv.id }
            var gross = 0.0, source = ""
            for el in rs { if case .slab(let s) = el.geometry, (el.props["kind"] ?? "").isEmpty || el.props["kind"] == "floor" { gross += ScheduleExporter.slabArea(s) * u * u } }
            if gross > 0 { source = "slabs" }
            if gross == 0 {
                for el in rs { if case .space(let s) = el.geometry, let sc = el.props["areaScheme"], sc.lowercased().contains("gross") || sc.uppercased() == "GFA" {
                    gross += abs(GeometryOps.signedArea(s.boundary)) * u * u } }
                if gross > 0 { source = "area plan" }
            }
            let lr = rooms.filter { r in doc.element(r.id)?.level == lv.id && doc.element(r.id)?.props["areaScheme"] == nil }
            let net = lr.reduce(0) { $0 + $1.netArea }
            if gross == 0 { gross = lr.reduce(0) { $0 + $1.grossArea }; if gross > 0 { source = "rooms" } }
            guard gross > 0 || net > 0 else { continue }
            out.append(LevelAreaRow(level: lv.id, name: lv.name, elevation: lv.elevation * u, grossArea: gross, netArea: net, rooms: lr.count, grossSource: source))
        }
        return out
    }

    public static func table(_ rows: [LevelAreaRow]) -> [[String]] {
        var t = [["level", "elevation_m", "gross_m2", "net_m2", "net_to_gross", "rooms", "gross_from"]]
        for r in rows { t.append([r.name, fmt(r.elevation, 3), fmt(r.grossArea, 2), fmt(r.netArea, 2), fmt(r.efficiency, 3), "\(r.rooms)", r.grossSource]) }
        let g = rows.reduce(0) { $0 + $1.grossArea }, n = rows.reduce(0) { $0 + $1.netArea }
        t.append(["TOTAL", "", fmt(g, 2), fmt(n, 2), fmt(g > 0 ? n / g : 0, 3), "\(rows.reduce(0) { $0 + $1.rooms })", ""])
        return t
    }
}
