// Oanarina Archi Tool — GPL-3.0-or-later
// Building checks: structural load takedown per column (tributary areas, dead/live loads, EN 1990 combinations),
// rainwater runoff from roofs (EN 12056-3 style design flow, downpipes, harvest), parking provision against
// requirements, and fire compartment areas with the fire rating of compartment walls.
import Foundation

// MARK: - Load takedown

public struct TakedownOptions: Hashable {
    /// Superimposed dead load (finishes, services, partitions) kN/m².
    public var superimposedDead = 1.5
    /// Default imposed (live) load kN/m² where no room usage applies (EN 1991-1-1 category A floors: 2.0).
    public var live = 2.0
    /// Imposed load on roofs (category H) kN/m².
    public var roofLive = 0.75
    /// Partial factors (EN 1990 6.10): 1.35 G + 1.5 Q.
    public var gammaG = 1.35, gammaQ = 1.5
    /// Grid cell for tributary areas (mm, drawing units converted); 0 = automatic.
    public var cell = 0.0
    /// Walls at least this thick (mm) are load bearing unless marked (prop loadBearing = 0/1).
    public var bearingWallThickness = 200.0
    public init() {}
    public static func from(_ doc: ArchiDocument) -> TakedownOptions {
        var o = TakedownOptions()
        if let v = doc.variable("LOADSDL").flatMap(Double.init) { o.superimposedDead = v }
        if let v = doc.variable("LOADLIVE").flatMap(Double.init) { o.live = v }
        if let v = doc.variable("LOADROOF").flatMap(Double.init) { o.roofLive = v }
        return o
    }
    /// Imposed load of a room by usage (EN 1991-1-1 Table 6.2 categories), or its prop "liveLoad".
    public func liveLoad(_ space: BIMElement) -> Double {
        if let v = space.props["liveLoad"].flatMap(Double.init) { return v }
        guard case .space(let s) = space.geometry else { return live }
        let n = (s.name + " " + (space.props["usage"] ?? "")).lowercased()
        let table: [([String], Double)] = [
            (["storage", "archive", "plant", "store"], 7.5), (["parking", "garage"], 2.5),
            (["assembly", "hall", "auditorium", "church", "gym", "dance", "stage"], 5.0), (["shop", "retail", "store"], 5.0),
            (["restaurant", "cafe", "canteen", "classroom", "school", "lecture"], 3.0),
            (["office", "meeting", "conference", "reception"], 3.0),
            (["corridor", "stair", "lobby", "hall", "landing", "balcony"], 3.0),
            (["bed", "living", "kitchen", "bath", "wc", "toilet", "dining", "flat", "apartment", "room"], 2.0),
        ]
        for (keys, q) in table where keys.contains(where: { n.contains($0) }) { return q }
        return live
    }
}

public struct TakedownRow: Hashable {
    public var column: EntityID
    public var level: Int
    public var levelName: String
    /// Tributary floor area carried at this level, m².
    public var area: Double
    /// Loads added at this level (kN): slab self weight + superimposed dead + column self weight; imposed.
    public var dead: Double
    public var live: Double
    /// Accumulated down to (and including) this level, kN.
    public var totalDead: Double
    public var totalLive: Double
    public var uls: Double
    public var sls: Double
    /// Axial stress under ULS, MPa (N/mm²).
    public var stress: Double
    /// Column this one carries (directly above), if any.
    public var above: EntityID?
}

public struct TakedownReport {
    public var rows: [TakedownRow]
    /// Tributary area carried by bearing walls, m² (floor area not reaching a column).
    public var wallArea: Double
    public var table: [[String]] {
        [["column", "level", "area_m2", "dead_kN", "live_kN", "sum_dead_kN", "sum_live_kN", "ULS_kN", "SLS_kN", "stress_MPa", "above"]] + rows.map {
            ["#\($0.column)", $0.levelName, fmt($0.area, 2), fmt($0.dead, 1), fmt($0.live, 1), fmt($0.totalDead, 1), fmt($0.totalLive, 1), fmt($0.uls, 1), fmt($0.sls, 1),
             fmt($0.stress, 2), $0.above.map { "#\($0)" } ?? ""]
        }
    }
}

public enum LoadTakedown {
    /// Loads per column: every slab is split into tributary cells, each carried by the nearest support (column or
    /// load-bearing wall) that holds that slab (column top within 500 mm of the slab soffit/top, or the slab on the next
    /// level). Cells take the imposed load of the room they are in. Columns stacked within 300 mm carry the column above.
    public static func compute(_ doc: ArchiDocument, options o: TakedownOptions = TakedownOptions()) -> TakedownReport {
        let u = doc.units.mm / 1000 // metres per drawing unit
        let levels = doc.levels.sorted { $0.elevation < $1.elevation }
        func elev(_ l: Int) -> Double { doc.level(l)?.elevation ?? 0 }
        struct Col { var id: EntityID; var level: Int; var p: Vec2; var top: Double; var base: Double; var area: Double; var height: Double; var material: String? }
        var cols: [Col] = []
        for el in doc.elements {
            guard case .column(let c) = el.geometry else { continue }
            let a = c.round ? Double.pi * c.width * c.width / 4 : c.width * c.depth
            let base = elev(el.level) + c.baseOffset
            cols.append(Col(id: el.id, level: el.level, p: c.position, top: base + c.height, base: base, area: a, height: c.height, material: el.material))
        }
        struct WallSup { var a: Vec2; var b: Vec2; var top: Double; var level: Int }
        var walls: [WallSup] = []
        for el in doc.elements {
            guard case .wall(let w) = el.geometry else { continue }
            let flag = el.props["loadBearing"] ?? el.props["LoadBearing"] ?? el.props["Pset_WallCommon.LoadBearing"]
            let bearing = flag.map { ["1", "true", "yes", "t", ".t."].contains($0.lowercased()) } ?? (w.thickness * doc.units.mm >= o.bearingWallThickness)
            guard bearing else { continue }
            walls.append(WallSup(a: w.start, b: w.end, top: elev(el.level) + w.baseOffset + w.height, level: el.level))
        }
        var tribArea: [EntityID: Double] = [:], dead: [EntityID: Double] = [:], live: [EntityID: Double] = [:]
        var wallArea = 0.0
        let tol = 500 / doc.units.mm
        for el in doc.elements {
            guard case .slab(let sl) = el.geometry, sl.boundary.count >= 3 else { continue }
            if el.props["kind"] == "ceiling" { continue }
            let top = elev(el.level) + sl.topOffset
            let soffit = top - sl.thickness
            // Supports: columns/walls whose top meets the slab; else the ones on the level below.
            var supCols = cols.indices.filter { abs(cols[$0].top - soffit) <= tol || abs(cols[$0].top - top) <= tol }
            var supWalls = walls.indices.filter { abs(walls[$0].top - soffit) <= tol || abs(walls[$0].top - top) <= tol }
            if supCols.isEmpty && supWalls.isEmpty, let li = levels.firstIndex(where: { $0.id == el.level }), li > 0 {
                let below = levels[li - 1].id
                supCols = cols.indices.filter { cols[$0].level == below }
                supWalls = walls.indices.filter { walls[$0].level == below }
            }
            guard !supCols.isEmpty || !supWalls.isEmpty else { continue }
            let box = BBox2(points: sl.boundary)
            let areaAll = abs(GeometryOps.signedArea(sl.boundary))
            let cell = o.cell > 0 ? o.cell / doc.units.mm : max(sqrt(areaAll / 6000), 50 / doc.units.mm)
            let isRoof = el.props["roof"] == "1" || el.props["kind"] == "roof" || !levels.contains { $0.elevation > elev(el.level) + 1e-6 }
            let spaces = doc.elements.filter { if case .space = $0.geometry { return $0.level == el.level }; return false }
            let mat = StructMaterial.of(el.material)
            let selfWeight = mat.weight * sl.thickness * u // kN/m²
            let cellA = cell * cell * u * u
            var y = box.min.y + cell / 2
            while y < box.max.y {
                var x = box.min.x + cell / 2
                while x < box.max.x {
                    let p = Vec2(x, y)
                    defer { x += cell }
                    guard GeometryOps.pointInPolygon(p, sl.boundary), !sl.holes.contains(where: { GeometryOps.pointInPolygon(p, $0) }) else { continue }
                    var best = Double.infinity, bestCol: Int? = nil
                    for i in supCols { let d = cols[i].p.distance(to: p); if d < best { best = d; bestCol = i } }
                    var wallBetter = false
                    for i in supWalls where GeometryOps.distance(point: p, segA: walls[i].a, segB: walls[i].b) < best { wallBetter = true; break }
                    if wallBetter || bestCol == nil { wallArea += cellA; continue }
                    let q: Double
                    if isRoof { q = o.roofLive } else if let s = spaces.first(where: { if case .space(let g) = $0.geometry { return GeometryOps.pointInPolygon(p, g.boundary) }; return false }) { q = o.liveLoad(s) } else { q = o.live }
                    let id = cols[bestCol!].id
                    tribArea[id, default: 0] += cellA
                    dead[id, default: 0] += (selfWeight + o.superimposedDead) * cellA
                    live[id, default: 0] += q * cellA
                }
                y += cell
            }
        }
        // Stack columns from the top down.
        let order = cols.indices.sorted { cols[$0].base > cols[$1].base }
        var totalD: [EntityID: Double] = [:], totalL: [EntityID: Double] = [:]
        var rows: [TakedownRow] = []
        let stackTol = 300 / doc.units.mm
        for i in order {
            let c = cols[i]
            let own = StructMaterial.of(c.material).weight * c.area * c.height * u * u * u
            let d = (dead[c.id] ?? 0) + own, l = live[c.id] ?? 0
            // Column directly above: base within tolerance of this top.
            let above = cols.filter { $0.id != c.id && abs($0.base - c.top) <= tol && $0.p.distance(to: c.p) <= stackTol }.min { $0.p.distance(to: c.p) < $1.p.distance(to: c.p) }
            var td = d, tl = l
            if let a = above { td += totalD[a.id] ?? 0; tl += totalL[a.id] ?? 0 }
            totalD[c.id] = td; totalL[c.id] = tl
            let uls = o.gammaG * td + o.gammaQ * tl
            let areaMM2 = c.area * doc.units.mm * doc.units.mm
            rows.append(TakedownRow(column: c.id, level: c.level, levelName: doc.level(c.level)?.name ?? "\(c.level)", area: tribArea[c.id] ?? 0,
                                    dead: d, live: l, totalDead: td, totalLive: tl, uls: uls, sls: td + tl, stress: areaMM2 > 0 ? uls * 1000 / areaMM2 : 0, above: above?.id))
        }
        rows.sort { ($0.level, $0.column) < ($1.level, $1.column) }
        return TakedownReport(rows: rows, wallArea: wallArea)
    }
}

// MARK: - Rainwater

public struct RainwaterOptions: Hashable {
    /// Design rainfall intensity, l/(s·m²) (0.03 ≈ 300 l/(s·ha)).
    public var intensity = 0.03
    /// Annual rainfall, mm, for harvesting.
    public var annualRainfall = 600.0
    /// Harvest yield (losses, first flush).
    public var harvestYield = 0.8
    public init() {}
    public static func from(_ doc: ArchiDocument) -> RainwaterOptions {
        var o = RainwaterOptions()
        if let v = doc.variable("RAININTENSITY").flatMap(Double.init) { o.intensity = v }
        if let v = doc.variable("ANNUALRAINFALL").flatMap(Double.init) { o.annualRainfall = v }
        return o
    }
    /// Vertical rainwater pipe capacities (l/s) by nominal diameter, filling 0.33 (EN 12056-3 Table 8).
    public static let downpipes: [(dn: Int, capacity: Double)] = [(50, 0.7), (60, 1.2), (70, 1.8), (80, 2.6), (90, 3.5), (100, 4.6), (110, 6.0), (125, 8.1), (150, 13.0), (200, 28.0)]
}

public struct RainwaterRow: Hashable {
    public var element: EntityID
    public var kind: String
    public var planArea: Double      // m² (roofs incl. overhang)
    public var coefficient: Double
    public var flow: Double          // l/s
    public var downpipes: Int
    public var downpipeDN: Int
    public var gutterLength: Double  // m
    public var harvest: Double       // m³/year
}

public enum Rainwater {
    /// Runoff coefficient: pitched roofs 1.0, flat roofs 0.8, green roofs (prop green=1 or material "Grass") 0.3; prop runoff overrides.
    static func coefficient(_ el: BIMElement, pitched: Bool) -> Double {
        if let v = el.props["runoff"].flatMap(Double.init) { return v }
        if el.props["green"] == "1" || (el.material ?? "").lowercased().contains("grass") { return 0.3 }
        return pitched ? 1.0 : 0.8
    }

    /// Design flow Q = C·i·A per roof (and flat roof slabs: prop roof=1 or slabs on the top level), downpipes at DN100
    /// (or the smallest single pipe that suffices), eave gutter length and annual harvestable volume.
    public static func compute(_ doc: ArchiDocument, options o: RainwaterOptions = RainwaterOptions()) -> [RainwaterRow] {
        let m = doc.units.mm / 1000
        let topLevel = doc.levels.max { $0.elevation < $1.elevation }?.id
        var rows: [RainwaterRow] = []
        func row(_ el: BIMElement, _ kind: String, area: Double, perimeter: Double, gutter: Double, pitched: Bool) {
            let c = coefficient(el, pitched: pitched)
            let q = c * o.intensity * area
            let cap100 = RainwaterOptions.downpipes.first { $0.dn == 100 }!.capacity
            let single = RainwaterOptions.downpipes.first { $0.capacity >= q }
            let n = single != nil && q <= cap100 ? 1 : max(1, Int((q / cap100).rounded(.up)))
            let dn = n == 1 ? (single?.dn ?? 100) : 100
            rows.append(RainwaterRow(element: el.id, kind: kind, planArea: area, coefficient: c, flow: q, downpipes: n, downpipeDN: max(dn, 60),
                                     gutterLength: gutter, harvest: area * o.annualRainfall / 1000 * c * o.harvestYield))
            _ = perimeter
        }
        for el in doc.elements {
            switch el.geometry {
            case .roof(let r) where r.boundary.count >= 3:
                let a = abs(GeometryOps.signedArea(r.boundary)) * m * m
                var per = 0.0
                for i in r.boundary.indices { per += r.boundary[i].distance(to: r.boundary[(i + 1) % r.boundary.count]) }
                let ov = r.overhang * m
                let area = a + per * m * ov + 4 * ov * ov
                // Gutters along eaves: gable/shed roofs drain to the eave edges, hip roofs all round, flat roofs to outlets.
                let n = r.boundary.count
                let edge = { (i: Int) -> Double in r.boundary[i].distance(to: r.boundary[(i + 1) % n]) * m + 2 * ov }
                let gutter: Double
                switch r.kind {
                case .gable: gutter = edge(r.eaveEdge % n) + (n == 4 ? edge((r.eaveEdge + 2) % n) : 0)
                case .shed: gutter = edge(r.eaveEdge % n)
                case .flat: gutter = 0
                default: gutter = per * m + 8 * ov
                }
                row(el, "roof (\(r.kind.rawValue))", area: area, perimeter: per * m, gutter: gutter, pitched: r.kind != .flat && r.pitch > 5)
            case .slab(let s) where s.boundary.count >= 3:
                let isRoof = el.props["roof"] == "1" || el.props["kind"] == "roof" || (el.level == topLevel && doc.levels.count > 1 && el.props["kind"] == nil)
                guard isRoof else { continue }
                let a = max(abs(GeometryOps.signedArea(s.boundary)) - s.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }, 0) * m * m
                row(el, "flat roof slab", area: a, perimeter: 0, gutter: 0, pitched: s.slope > 5)
            default: continue
            }
        }
        return rows
    }
}

// MARK: - Parking

public struct ParkingRule: Hashable {
    /// Usage keyword matched in room names (or prop usage); "*" = gross floor area of all rooms.
    public var usage: String
    /// One space per `perArea` m² (0 = per room/unit, then `perUnit` spaces each).
    public var perArea: Double
    public var perUnit: Double
    public init(usage: String, perArea: Double = 0, perUnit: Double = 0) { self.usage = usage; self.perArea = perArea; self.perUnit = perUnit }
    /// "office=35;retail=25;apartment=unit:1;*=100" (area per space, or unit:n spaces per room).
    public static func parse(_ s: String) -> [ParkingRule] {
        s.split(whereSeparator: { $0 == ";" || $0 == "," }).compactMap { part -> ParkingRule? in
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2, !kv[0].isEmpty else { return nil }
            if kv[1].lowercased().hasPrefix("unit:"), let n = Double(kv[1].dropFirst(5)) { return ParkingRule(usage: kv[0].lowercased(), perUnit: n) }
            guard let a = Double(kv[1]), a > 0 else { return nil }
            return ParkingRule(usage: kv[0].lowercased(), perArea: a)
        }
    }
    public static let defaults = parse("office=35;retail=25;shop=25;restaurant=10;apartment=unit:1;flat=unit:1;dwelling=unit:1;classroom=unit:0.5")
}

public struct ParkingReport {
    public struct Line: Hashable { public var usage: String; public var rooms: Int; public var area: Double; public var required: Double }
    public var lines: [Line]
    public var required: Int
    public var provided: Int
    public var accessibleRequired: Int
    public var accessibleProvided: Int
    public var ok: Bool { provided >= required && accessibleProvided >= accessibleRequired }
    public var text: String {
        var s = lines.map { "\($0.usage): \($0.rooms) rooms, \(fmt($0.area, 1)) m² → \(fmt($0.required, 2)) spaces" }
        s.append("Required \(required) spaces (\(accessibleRequired) accessible); provided \(provided) (\(accessibleProvided) accessible) — \(ok ? "OK" : "NOT MET")")
        return s.joined(separator: "\n")
    }
}

public enum ParkingCheck {
    /// Accessible spaces required: 1 per 25 up to 100, then 1 per 50 (ADA 208.2 style), at least 1 when any are required.
    public static func accessibleRequired(_ total: Int) -> Int {
        if total <= 0 { return 0 }
        if total <= 100 { return max(1, Int((Double(total) / 25).rounded(.up))) }
        return 4 + Int((Double(total - 100) / 50).rounded(.up))
    }

    /// Provided spaces are "parking" components (PARKINGLOT) or elements with prop parking=1 (accessible: prop accessible=1
    /// or a width ≥ 3300 mm). Required spaces follow the rules (variable PARKINGRULES, default office 1/35 m², retail 1/25 m²,
    /// dwellings 1 per unit…), rounded up.
    public static func check(_ doc: ArchiDocument, rules: [ParkingRule]? = nil) -> ParkingReport {
        let rs = rules ?? doc.variable("PARKINGRULES").map(ParkingRule.parse) ?? ParkingRule.defaults
        let m2 = pow(doc.units.mm / 1000, 2)
        var lines: [String: ParkingReport.Line] = [:]
        for el in doc.elements {
            guard case .space(let s) = el.geometry else { continue }
            let n = (s.name + " " + (el.props["usage"] ?? "")).lowercased()
            guard let r = rs.first(where: { $0.usage != "*" && n.contains($0.usage) }) ?? rs.first(where: { $0.usage == "*" }) else { continue }
            let a = abs(GeometryOps.signedArea(s.boundary)) * m2
            var l = lines[r.usage] ?? ParkingReport.Line(usage: r.usage, rooms: 0, area: 0, required: 0)
            l.rooms += 1; l.area += a
            l.required += r.perArea > 0 ? a / r.perArea : r.perUnit
            lines[r.usage] = l
        }
        var provided = 0, accessible = 0
        for el in doc.elements {
            var isParking = el.props["parking"] == "1"
            var width = 0.0
            if case .component(let c) = el.geometry, (c.family ?? "").lowercased().hasPrefix("parking") { isParking = true; width = min(c.size.x, c.size.y) * doc.units.mm }
            guard isParking else { continue }
            provided += 1
            if el.props["accessible"] == "1" || width >= 3300 || (el.name.lowercased().contains("accessible")) { accessible += 1 }
        }
        let total = lines.values.reduce(0) { $0 + $1.required }
        let req = max(0, Int((total - 1e-9).rounded(.up)))
        return ParkingReport(lines: lines.values.sorted { $0.usage < $1.usage }, required: req, provided: provided,
                             accessibleRequired: accessibleRequired(req), accessibleProvided: accessible)
    }
}

// MARK: - Fire compartments

public struct FireCompartment: Hashable {
    public var name: String
    public var rooms: [EntityID]
    public var levels: [Int]
    public var area: Double        // m²
    public var limit: Double       // m²
    public var ok: Bool { area <= limit + 1e-9 }
}

public struct FireCompartmentReport {
    public var compartments: [FireCompartment]
    /// Walls separating rooms of different compartments without the required fire rating (prop fireRating / FireRating /
    /// Pset_WallCommon.FireRating, minutes or "EI 60").
    public var unratedWalls: [EntityID]
    public var requiredRating: Int
    public var text: String {
        var s = compartments.map { "\($0.name): \($0.rooms.count) rooms, \(fmt($0.area, 1)) m² (limit \(fmt($0.limit, 0)) m²) — \($0.ok ? "OK" : "TOO LARGE")" }
        if !unratedWalls.isEmpty { s.append("\(unratedWalls.count) compartment walls below \(requiredRating) min: " + unratedWalls.map { "#\($0)" }.joined(separator: ", ")) }
        return s.joined(separator: "\n")
    }
}

public enum FireCompartments {
    /// Rating in minutes from "EI 60", "REI90", "60", "1h".
    public static func minutes(_ s: String?) -> Int? {
        guard let s = s?.uppercased(), !s.isEmpty else { return nil }
        let digits = s.filter(\.isNumber)
        guard let n = Int(digits) else { return nil }
        return s.contains("H") && !s.contains("EI") && n < 10 ? n * 60 : n
    }
    static func rating(_ el: BIMElement, doc: ArchiDocument) -> Int? {
        if let v = minutes(el.props["fireRating"] ?? el.props["FireRating"] ?? el.props["Pset_WallCommon.FireRating"]) { return v }
        if case .wall(let w) = el.geometry, let tn = w.wallType, let v = minutes(doc.variable("FIRERATING:" + tn)) { return v }
        return nil
    }

    /// Rooms are grouped by prop fireCompartment (else one compartment per level). Limit: variable FIREMAXAREA (default
    /// 2500 m²), doubled when FIRESPRINKLERS=1; prop fireLimit on a room overrides for its compartment. Walls whose two
    /// sides lie in rooms of different compartments need FIRERATINGREQ minutes (default 60).
    public static func check(_ doc: ArchiDocument) -> FireCompartmentReport {
        let m2 = pow(doc.units.mm / 1000, 2)
        var limit = doc.variable("FIREMAXAREA").flatMap(Double.init) ?? 2500
        if doc.variable("FIRESPRINKLERS") == "1" { limit *= 2 }
        let req = doc.variable("FIRERATINGREQ").flatMap { Int($0) } ?? 60
        var comps: [String: FireCompartment] = [:]
        var roomComp: [EntityID: String] = [:]
        let rooms = doc.elements.filter { if case .space = $0.geometry { return true }; return false }
        for el in rooms {
            guard case .space(let s) = el.geometry else { continue }
            let name = el.props["fireCompartment"] ?? "Level \(doc.level(el.level)?.name ?? "\(el.level)")"
            var c = comps[name] ?? FireCompartment(name: name, rooms: [], levels: [], area: 0, limit: limit)
            c.rooms.append(el.id)
            if !c.levels.contains(el.level) { c.levels.append(el.level) }
            c.area += abs(GeometryOps.signedArea(s.boundary)) * m2
            if let l = el.props["fireLimit"].flatMap(Double.init) { c.limit = l }
            comps[name] = c
            roomComp[el.id] = name
        }
        var unrated: [EntityID] = []
        for el in doc.elements {
            guard case .wall(let w) = el.geometry, w.length > 0 else { continue }
            let mid = (w.start + w.end) / 2
            let n = (w.end - w.start).normalized.perp
            let off = w.thickness / 2 + 100 / doc.units.mm
            func comp(_ p: Vec2) -> String? {
                for r in rooms where r.level == el.level { if case .space(let s) = r.geometry, GeometryOps.pointInPolygon(p, s.boundary) { return roomComp[r.id] } }
                return nil
            }
            guard let a = comp(mid + n * off), let b = comp(mid - n * off), a != b else { continue }
            if (rating(el, doc: doc) ?? 0) < req { unrated.append(el.id) }
        }
        return FireCompartmentReport(compartments: comps.values.sorted { $0.name < $1.name }, unratedWalls: unrated, requiredRating: req)
    }
}
