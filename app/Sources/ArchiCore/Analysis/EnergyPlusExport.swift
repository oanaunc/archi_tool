// Oanarina Archi Tool — GPL-3.0-or-later
// EnergyPlus model export and run (ANL-024): rooms become thermal zones, their outlines become wall / floor / roof
// surfaces (BuildingSurface:Detailed, outward vertex order per GlobalGeometryRules UpperLeftCorner / Counterclockwise /
// World) with boundary conditions from the envelope (exterior walls outdoors, lowest floors on the ground, top roofs
// outdoors, everything between rooms adiabatic), windows as FenestrationSurface:Detailed in their host surfaces,
// constructions from the wall types' layers (conductivity table, density and heat capacity by material), ideal-loads
// HVAC templates with a dual thermostat, site location from the project. The IDF targets EnergyPlus 9.4 (newer versions
// convert it with IDFVersionUpdater). ENERGYPLUS Run launches an installed EnergyPlus with a weather file.
import Foundation

public enum EnergyPlusExport {
    public struct ExportError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    public struct Surface {
        public var name: String; public var type: String; public var construction: String; public var zone: String; public var boundary: String; public var vertices: [Vec3]
        /// The adjacent zone's surface for interzone surfaces (boundary "Surface").
        public var boundaryObject: String = ""
    }
    public struct Window { public var name: String; public var host: String; public var vertices: [Vec3] }
    public struct Model {
        public var zones: [(name: String, height: Double, volume: Double, origin: Vec3)]; public var surfaces: [Surface]; public var windows: [Window]; public var idf: String
        /// Room element of each zone (by zone name) and zone floor areas (m²).
        public var zoneRooms: [String: EntityID] = [:]
        public var zoneAreas: [String: Double] = [:]
    }

    static func density(_ material: String) -> (rho: Double, c: Double) {
        let n = material.lowercased()
        let table: [(String, Double, Double)] = [("insulation", 30, 1030), ("wool", 30, 1030), ("eps", 25, 1450), ("xps", 35, 1450), ("pir", 32, 1400),
            ("concrete", 2300, 900), ("screed", 2000, 840), ("brick", 1800, 840), ("block", 1400, 840), ("stone", 2500, 800), ("plaster", 1200, 1000),
            ("gypsum", 900, 1000), ("board", 900, 1000), ("timber", 500, 1600), ("wood", 500, 1600), ("clt", 470, 1600), ("steel", 7800, 450), ("glass", 2500, 750)]
        if let t = table.first(where: { n.contains($0.0) }) { return (t.1, t.2) }
        return (1500, 1000)
    }
    static func idfName(_ s: String) -> String { s.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ";", with: " ").replacingOccurrences(of: "!", with: " ") }
    static func f(_ v: Double) -> String { let s = fmt(v, 4); return s == "-0" ? "0" : s }

    public static func build(_ doc: ArchiDocument, northAxis: Double? = nil) throws -> Model {
        let m = doc.units.mm / 1000
        let rooms = doc.elements.compactMap { el -> (BIMElement, SpaceGeom)? in if case .space(let s) = el.geometry, s.boundary.count >= 3, el.props["areaScheme"] == nil { return (el, s) }; return nil }
        guard !rooms.isEmpty else { throw ExportError(message: "EnergyPlus zones come from rooms: add rooms (ROOM / SPACE) first.") }
        let levels = doc.levels.sorted { $0.elevation < $1.elevation }
        let lowest = rooms.map { $0.0.level }.min { (doc.level($0)?.elevation ?? 0) < (doc.level($1)?.elevation ?? 0) }
        // Wall constructions.
        var materials: [String: (thick: Double, lambda: Double, rho: Double, c: Double)] = [:]
        var constructions: [String: [String]] = [:]
        func layerMat(_ name: String, _ thick: Double) -> String {
            let key = idfName("\(name) \(fmt(thick * 1000, 0))mm")
            if materials[key] == nil {
                let lam = ThermalLibrary.lambda(name, doc: doc) ?? 1.0
                let dc = density(name)
                materials[key] = (thick, lam, dc.rho, dc.c)
            }
            return key
        }
        func construction(forWall w: WallGeom?) -> String {
            if let t = w?.wallType, let wt = doc.wallTypes.first(where: { $0.name == t }), !wt.plies.isEmpty {
                let name = idfName("WT " + t)
                if constructions[name] == nil { constructions[name] = wt.plies.map { layerMat($0.material, $0.thickness * m) } }
                return name
            }
            let th = (w?.thickness ?? 250 / m / 1000) * m
            let name = idfName("Wall \(fmt(th * 1000, 0))mm")
            if constructions[name] == nil { constructions[name] = [layerMat("Brick", max(th, 0.05))] }
            return name
        }
        constructions["Interior Wall"] = [layerMat("Gypsum board", 0.0125), layerMat("Mineral wool", 0.05), layerMat("Gypsum board", 0.0125)]
        constructions["Ground Floor"] = [layerMat("Screed", 0.06), layerMat("XPS insulation", 0.1), layerMat("Reinforced concrete", 0.2)].reversed()
        constructions["Intermediate Floor"] = [layerMat("Screed", 0.05), layerMat("Reinforced concrete", 0.2)]
        constructions["Roof"] = [layerMat("Bitumen membrane", 0.01), layerMat("Mineral wool insulation", 0.2), layerMat("Reinforced concrete", 0.2)]
        let windowU = doc.variable("UVALUE:window").flatMap(Double.init) ?? ThermalLibrary.defaultU["window"] ?? 1.3
        let extWalls = doc.elements.filter { Thermal.isExterior($0, doc: doc) }.compactMap { el -> (BIMElement, WallGeom)? in if case .wall(let w) = el.geometry { return (el, w) }; return nil }
        var zones: [(String, Double, Double, Vec3)] = [], surfaces: [Surface] = [], windows: [Window] = []
        var usedNames = Set<String>()
        func unique(_ s: String) -> String { var n = idfName(s), k = 2; while usedNames.contains(n) { n = idfName("\(s) \(k)"); k += 1 }; usedNames.insert(n); return n }
        var zoneRooms: [String: EntityID] = [:], zoneAreas: [String: Double] = [:]
        for (el, s) in rooms {
            let lv = doc.level(el.level)
            let z0 = (lv?.elevation ?? 0) * m
            let h = (s.height > 0 ? s.height : (lv?.height ?? 3000 / m / 1000)) * m
            var poly = s.boundary.map { $0 * m }
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            let zname = unique("\(s.number.isEmpty ? "" : s.number + " ")\(s.name.isEmpty ? "Zone" : s.name)")
            let area = abs(GeometryOps.signedArea(poly))
            zones.append((zname, h, area * h, Vec3(0, 0, 0)))
            zoneRooms[zname.uppercased()] = el.id; zoneAreas[zname.uppercased()] = area
            let levelAbove = levels.first { $0.elevation > (lv?.elevation ?? 0) + 1e-6 }
            let roomAbove = levelAbove.map { la in rooms.contains { $0.0.level == la.id && GeometryOps.pointInPolygon(GeometryOps.centroid(s.boundary), $0.1.boundary) } } ?? false
            // Walls: one surface per outline edge; exterior when an exterior wall runs along it.
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                guard a.distance(to: b) > 1e-6 else { continue }
                let mid = (a + b) / 2 / m
                let host = extWalls.first { w in
                    Thermal.segDist(mid, w.1.centerStart, w.1.centerEnd) <= w.1.thickness / 2 + 50 / doc.units.mm && abs((b - a).normalized.cross(w.1.direction)) < 0.05
                }
                let cons = host != nil ? construction(forWall: host?.1) : "Interior Wall"
                let sname = unique("\(zname) Wall \(i + 1)")
                // Viewed from outside (right of a→b): upper-left = (a, top), counterclockwise.
                let verts = [Vec3(a.x, a.y, z0 + h), Vec3(a.x, a.y, z0), Vec3(b.x, b.y, z0), Vec3(b.x, b.y, z0 + h)]
                surfaces.append(Surface(name: sname, type: "Wall", construction: cons, zone: zname, boundary: host != nil ? "Outdoors" : "Adiabatic", vertices: verts))
                guard let (hel, hw) = host else { continue }
                for o in doc.elements {
                    guard case .opening(let op) = o.geometry, op.kind == .window, op.hostWall == hel.id else { continue }
                    let c = (hw.centerStart + hw.direction * op.offset) * m
                    let dir = (b - a).normalized, L = a.distance(to: b)
                    let t = (c - a).dot(dir)
                    guard t >= -1e-6, t <= L + 1e-6, abs((c - a).cross(dir)) <= hw.thickness * m / 2 + 0.06 else { continue }
                    let w2 = op.width * m / 2
                    let t0 = max(0.02, t - w2), t1 = min(L - 0.02, t + w2)
                    guard t1 - t0 > 0.05 else { continue }
                    let zs = z0 + op.sill * m, zt = min(z0 + h - 0.02, zs + op.height * m)
                    guard zt - zs > 0.05 else { continue }
                    let p0 = a + dir * t0, p1 = a + dir * t1
                    windows.append(Window(name: unique("\(sname) Window"), host: sname, vertices: [Vec3(p0.x, p0.y, zt), Vec3(p0.x, p0.y, zs), Vec3(p1.x, p1.y, zs), Vec3(p1.x, p1.y, zt)]))
                }
            }
            // Floor (viewed from below: the plan outline clockwise) and roof/ceiling (counter-clockwise from above).
            let onGround = el.level == lowest
            surfaces.append(Surface(name: unique("\(zname) Floor"), type: "Floor", construction: onGround ? "Ground Floor" : "Intermediate Floor", zone: zname,
                                    boundary: onGround ? "Ground" : "Adiabatic", vertices: poly.reversed().map { Vec3($0.x, $0.y, z0) }))
            surfaces.append(Surface(name: unique("\(zname) \(roomAbove ? "Ceiling" : "Roof")"), type: roomAbove ? "Ceiling" : "Roof", construction: roomAbove ? "Intermediate Floor" : "Roof", zone: zname,
                                    boundary: roomAbove ? "Adiabatic" : "Outdoors", vertices: poly.map { Vec3($0.x, $0.y, z0 + h) }))
        }
        pairInterzone(&surfaces, constructions: &constructions, unique: unique)
        // IDF text.
        var o = "! \(doc.info.name) — EnergyPlus input exported by Oanarina Archi Tool\n"
        func obj(_ type: String, _ fields: [String]) { o += type + ",\n" + fields.enumerated().map { "    " + $0.element + ($0.offset == fields.count - 1 ? ";" : ",") }.joined(separator: "\n") + "\n\n" }
        obj("Version", ["9.4"])
        obj("SimulationControl", ["No", "No", "No", "No", "Yes"])
        obj("Building", [idfName(doc.info.name), f(northAxis ?? -doc.info.northAngle), "Suburbs", "0.04", "0.4", "FullExterior", "25", "6"])
        obj("Timestep", ["4"])
        let tz = Double(doc.variable("UTCOFFSET") ?? "") ?? (doc.info.longitude / 15).rounded()
        obj("Site:Location", [idfName(doc.info.name), f(doc.info.latitude), f(doc.info.longitude), f(tz), f(doc.info.elevation)])
        obj("RunPeriod", ["Annual", "1", "1", "", "12", "31", "", "", "Yes", "Yes", "No", "Yes", "Yes"])
        obj("GlobalGeometryRules", ["UpperLeftCorner", "Counterclockwise", "World"])
        obj("ScheduleTypeLimits", ["Temperature", "-60", "200", "CONTINUOUS"])
        let heat = Double(doc.variable("HEATINGSETPOINT") ?? "") ?? 20, cool = Double(doc.variable("COOLINGSETPOINT") ?? "") ?? 26
        obj("Schedule:Constant", ["Heating Setpoint", "Temperature", f(heat)])
        obj("Schedule:Constant", ["Cooling Setpoint", "Temperature", f(cool)])
        for (k, v) in materials.sorted(by: { $0.key < $1.key }) { obj("Material", [k, "MediumRough", f(v.thick), f(v.lambda), f(v.rho), f(v.c)]) }
        obj("WindowMaterial:SimpleGlazingSystem", ["Glazing", f(windowU), "0.6"])
        for (k, v) in constructions.sorted(by: { $0.key < $1.key }) { obj("Construction", [k] + v) }
        obj("Construction", ["Window", "Glazing"])
        for z in zones { obj("Zone", [z.0, "0", "0", "0", "0", "1", "1", f(z.1), f(z.2)]) }
        for s in surfaces {
            obj("BuildingSurface:Detailed", [s.name, s.type, s.construction, s.zone, s.boundary, s.boundaryObject, s.boundary == "Outdoors" ? "SunExposed" : "NoSun", s.boundary == "Outdoors" ? "WindExposed" : "NoWind",
                                             "autocalculate", "\(s.vertices.count)"] + s.vertices.flatMap { [f($0.x), f($0.y), f($0.z)] })
        }
        for w in windows { obj("FenestrationSurface:Detailed", [w.name, "Window", "Window", w.host, "", "autocalculate", "", "1", "4"] + w.vertices.flatMap { [f($0.x), f($0.y), f($0.z)] }) }
        obj("HVACTemplate:Thermostat", ["Thermostat", "Heating Setpoint", "", "Cooling Setpoint", ""])
        for z in zones { obj("HVACTemplate:Zone:IdealLoadsAirSystem", [z.0, "Thermostat"]) }
        obj("Output:Variable", ["*", "Zone Ideal Loads Supply Air Total Heating Energy", "Hourly"])
        obj("Output:Variable", ["*", "Zone Ideal Loads Supply Air Total Cooling Energy", "Hourly"])
        obj("Output:Table:SummaryReports", ["AllSummary"])
        obj("OutputControl:Table:Style", ["CommaAndHTML"])
        return Model(zones: zones.map { (name: $0.0, height: $0.1, volume: $0.2, origin: $0.3) }, surfaces: surfaces, windows: windows, idf: o,
                     zoneRooms: zoneRooms, zoneAreas: zoneAreas)
    }

    /// An installed EnergyPlus executable (/Applications/EnergyPlus-*/energyplus, or ENERGYPLUS variable / PATH).
    public static func findEnergyPlus(_ doc: ArchiDocument) -> URL? {
        let fm = FileManager.default
        if let v = doc.variable("ENERGYPLUS"), fm.isExecutableFile(atPath: v) { return URL(fileURLWithPath: v) }
        for dir in ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []).filter({ $0.hasPrefix("EnergyPlus") }).sorted().reversed() {
            let p = "/Applications/\(dir)/energyplus"
            if fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        for p in ["/usr/local/bin/energyplus", "/opt/homebrew/bin/energyplus"] where fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    /// Runs EnergyPlus (expanding the HVAC templates) and returns the output folder and the total site energy (kWh) from
    /// the tabular report when found.
    public static func run(idf: URL, weather: URL, outDir: URL, energyPlus: URL) throws -> (status: Int32, siteEnergyKWh: Double?) {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = energyPlus
        p.arguments = ["-w", weather.path, "-d", outDir.path, "-x", "-r", idf.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        var total: Double?
        if let t = try? String(contentsOf: outDir.appendingPathComponent("eplustbl.csv"), encoding: .utf8) {
            for line in t.split(separator: "\n") where line.contains("Total Site Energy") {
                let cols = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if cols.count > 2, let gj = Double(cols[2]) { total = gj * 277.7778; break }   // GJ → kWh
            }
        }
        return (p.terminationStatus, total)
    }

    /// Interzone surfaces: walls of two zones facing each other (antiparallel, within 0.6 m, same height) are split where
    /// they overlap and linked as "Surface" pairs; a ceiling over the identical floor of the zone above is linked with it.
    /// The second side of a pair gets the construction with its layers reversed, as EnergyPlus requires.
    static func pairInterzone(_ surfaces: inout [Surface], constructions: inout [String: [String]], unique: (String) -> String) {
        func reversed(_ c: String) -> String {
            guard let l = constructions[c], l.count > 1 else { return c }
            let n = c + " Reversed"
            if constructions[n] == nil { constructions[n] = l.reversed() }
            return n
        }
        struct Piece { var a: Int; var b: Int; var ia: (Double, Double); var ib: (Double, Double) }
        let walls = surfaces.indices.filter { surfaces[$0].type == "Wall" && surfaces[$0].boundary == "Adiabatic" && surfaces[$0].vertices.count == 4 }
        func seg(_ i: Int) -> (a: Vec2, b: Vec2, z0: Double, z1: Double) {
            let v = surfaces[i].vertices
            return (Vec2(v[1].x, v[1].y), Vec2(v[2].x, v[2].y), v[1].z, v[0].z)
        }
        var pieces: [Piece] = []
        for (n, i) in walls.enumerated() {
            let A = seg(i), LA = A.a.distance(to: A.b)
            guard LA > 1e-6 else { continue }
            let dA = (A.b - A.a) / LA
            for j in walls[(n + 1)...] where surfaces[j].zone != surfaces[i].zone {
                let B = seg(j), LB = B.a.distance(to: B.b)
                guard LB > 1e-6, abs(A.z0 - B.z0) < 0.05, abs(A.z1 - B.z1) < 0.05 else { continue }
                let dB = (B.b - B.a) / LB
                guard dA.dot(dB) < -0.999, abs((B.a - A.a).cross(dA)) <= 0.6 else { continue }
                let s0 = max(0, min((B.a - A.a).dot(dA), (B.b - A.a).dot(dA))), s1 = min(LA, max((B.a - A.a).dot(dA), (B.b - A.a).dot(dA)))
                guard s1 - s0 > 0.1 else { continue }
                func tB(_ s: Double) -> Double { (A.a + dA * s - B.a).dot(dB) }
                pieces.append(Piece(a: i, b: j, ia: (s0, s1), ib: (max(0, tB(s1)), min(LB, tB(s0)))))
            }
        }
        if !pieces.isEmpty {
            var names: [Int: (String, String)] = [:]
            for (k, p) in pieces.enumerated() {
                names[k] = (unique("\(surfaces[p.a].name) to \(surfaces[p.b].zone)"), unique("\(surfaces[p.b].name) to \(surfaces[p.a].zone)"))
            }
            var replace: [Int: [Surface]] = [:]
            for i in Set(pieces.flatMap { [$0.a, $0.b] }) {
                let S = seg(i), L = S.a.distance(to: S.b), d = (S.b - S.a) / L
                var ivs: [(Double, Double, String?, String?, Bool)] = []   // (u, v, own name, partner, second side)
                for (k, p) in pieces.enumerated() {
                    if p.a == i { ivs.append((p.ia.0, p.ia.1, names[k]!.0, names[k]!.1, false)) }
                    if p.b == i { ivs.append((p.ib.0, p.ib.1, names[k]!.1, names[k]!.0, true)) }
                }
                ivs.sort { $0.0 < $1.0 }
                var out: [Surface] = []
                var t = 0.0, part = 1
                func piece(_ u: Double, _ v: Double, _ name: String?, _ partner: String?, _ second: Bool) {
                    let pu = S.a + d * u, pv = S.a + d * v
                    var sf = surfaces[i]
                    sf.vertices = [Vec3(pu.x, pu.y, S.z1), Vec3(pu.x, pu.y, S.z0), Vec3(pv.x, pv.y, S.z0), Vec3(pv.x, pv.y, S.z1)]
                    if let name, let partner {
                        sf.name = name; sf.boundary = "Surface"; sf.boundaryObject = partner
                        if second { sf.construction = reversed(sf.construction) }
                    } else { sf.name = unique("\(surfaces[i].name) part \(part)"); part += 1 }
                    out.append(sf)
                }
                for iv in ivs {
                    if iv.0 - t > 0.01 { piece(t, iv.0, nil, nil, false) }
                    piece(max(iv.0, t), iv.1, iv.2, iv.3, iv.4)
                    t = max(t, iv.1)
                }
                if L - t > 0.01 { piece(t, L, nil, nil, false) }
                replace[i] = out
            }
            var ns: [Surface] = []
            for (i, sf) in surfaces.enumerated() { if let r = replace[i] { ns += r } else { ns.append(sf) } }
            surfaces = ns
        }
        // Ceiling ↔ floor of the zone above.
        func centroid(_ v: [Vec3]) -> Vec2 { GeometryOps.centroid(v.map { Vec2($0.x, $0.y) }) }
        func area(_ v: [Vec3]) -> Double { abs(GeometryOps.signedArea(v.map { Vec2($0.x, $0.y) })) }
        for c in surfaces.indices where surfaces[c].type == "Ceiling" && surfaces[c].boundary == "Adiabatic" {
            let cz = surfaces[c].vertices.first?.z ?? 0
            guard let f = surfaces.indices.first(where: { k in
                let s = surfaces[k]
                let gap = (s.vertices.first?.z ?? 0) - cz   // the floor above lies on the slab over the ceiling
                return s.type == "Floor" && s.boundary == "Adiabatic" && s.zone != surfaces[c].zone && gap > -0.05 && gap < 0.8 &&
                    abs(area(s.vertices) - area(surfaces[c].vertices)) <= 0.02 * area(s.vertices) && centroid(s.vertices).distance(to: centroid(surfaces[c].vertices)) < 0.2
            }) else { continue }
            surfaces[c].boundary = "Surface"; surfaces[c].boundaryObject = surfaces[f].name
            surfaces[f].boundary = "Surface"; surfaces[f].boundaryObject = surfaces[c].name
            surfaces[f].construction = reversed(surfaces[c].construction)
        }
    }

    /// Results of a finished EnergyPlus run read from its output folder.
    public struct Results: Hashable {
        public var completed = false
        public var severe = 0, warnings = 0, fatal = 0
        /// Total site energy (kWh) and energy use intensity (kWh/m²) from the tabular report.
        public var siteEnergyKWh: Double?
        public var euiKWhPerM2: Double?
        /// Annual end uses (kWh) by name (Heating, Cooling, Interior Lighting…), summed over fuels.
        public var endUses: [String: Double] = [:]
        /// Hours with heating / cooling setpoints not met (occupied).
        public var unmetHeatingHours: Double?, unmetCoolingHours: Double?
        /// Per zone (upper-case zone name): annual heating and cooling energy (kWh) and peak loads (kW) of the ideal loads system.
        public var zones: [String: (heatKWh: Double, coolKWh: Double, peakHeatKW: Double, peakCoolKW: Double)] = [:]
        public static func == (a: Results, b: Results) -> Bool { a.completed == b.completed && a.siteEnergyKWh == b.siteEnergyKWh && a.endUses == b.endUses && Set(a.zones.keys) == Set(b.zones.keys) }
        public func hash(into h: inout Hasher) { h.combine(completed); h.combine(siteEnergyKWh) }
    }

    /// Splits a CSV line (quoted fields kept together).
    static func csvFields(_ line: Substring) -> [String] {
        var out: [String] = [], cur = "", q = false
        for c in line {
            if c == "\"" { q.toggle() } else if c == "," && !q { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(c) }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// Reads eplusout.err (completion, severe errors), eplustbl.csv (site energy, EUI, end uses, unmet hours) and
    /// eplusout.csv (hourly ideal-loads energy per zone).
    public static func results(_ dir: URL) -> Results {
        var r = Results()
        if let err = try? String(contentsOf: dir.appendingPathComponent("eplusout.err"), encoding: .utf8) {
            r.completed = err.contains("EnergyPlus Completed Successfully")
            for l in err.split(separator: "\n") {
                if l.contains("** Severe  **") { r.severe += 1 } else if l.contains("** Warning **") { r.warnings += 1 } else if l.contains("**  Fatal  **") { r.fatal += 1 }
            }
        }
        if let t = try? String(contentsOf: dir.appendingPathComponent("eplustbl.csv"), encoding: .utf8) {
            var section = "", header: [String] = []
            for line in t.split(separator: "\n", omittingEmptySubsequences: false) {
                let f = csvFields(line)
                if f.allSatisfy({ $0.isEmpty }) { continue }
                if f.count == 1 || (f.count >= 1 && f.dropFirst().allSatisfy({ $0.isEmpty }) && !f[0].isEmpty) { section = f[0]; header = []; continue }
                guard f.count >= 3 else { continue }
                if f[0].isEmpty && f[1].isEmpty { header = f; continue }
                let name = f[1]
                if name.hasPrefix("Total Site Energy"), let gj = Double(f[2]) {
                    r.siteEnergyKWh = gj * 277.7778
                    if f.count > 3, let mj = Double(f[3]) { r.euiKWhPerM2 = mj / 3.6 }
                }
                if section.hasPrefix("End Uses"), !header.isEmpty, !name.isEmpty, !name.hasPrefix("Total") {
                    var sum = 0.0
                    for (i, h) in header.enumerated() where i >= 2 && i < f.count && h.contains("[GJ]") { sum += (Double(f[i]) ?? 0) * 277.7778 }
                    if sum > 0 { r.endUses[name, default: 0] += sum }
                }
                if name.hasPrefix("Time Setpoint Not Met During Occupied Heating"), let v = Double(f[2]) { r.unmetHeatingHours = v }
                if name.hasPrefix("Time Setpoint Not Met During Occupied Cooling"), let v = Double(f[2]) { r.unmetCoolingHours = v }
            }
        }
        if let csv = try? String(contentsOf: dir.appendingPathComponent("eplusout.csv"), encoding: .utf8) {
            let lines = csv.split(separator: "\n")
            if let head = lines.first {
                let cols = csvFields(head)
                var map: [(col: Int, zone: String, heat: Bool)] = []
                for (i, c) in cols.enumerated() {
                    let u = c.uppercased()
                    guard u.contains("ZONE IDEAL LOADS SUPPLY AIR TOTAL"), u.contains("[J]") else { continue }
                    var zone = String(u.split(separator: ":").first ?? "")
                    zone = zone.replacingOccurrences(of: " IDEAL LOADS AIR SYSTEM", with: "").replacingOccurrences(of: " IDEAL LOADS AIR", with: "").trimmingCharacters(in: .whitespaces)
                    map.append((i, zone, u.contains("HEATING")))
                }
                var acc: [String: (Double, Double, Double, Double)] = [:]
                for l in lines.dropFirst() {
                    let f = csvFields(l)
                    for m in map where m.col < f.count {
                        guard let j = Double(f[m.col]) else { continue }
                        var z = acc[m.zone] ?? (0, 0, 0, 0)
                        let kwh = j / 3.6e6
                        if m.heat { z.0 += kwh; z.2 = max(z.2, kwh) } else { z.1 += kwh; z.3 = max(z.3, kwh) }
                        acc[m.zone] = z
                    }
                }
                for (k, v) in acc { r.zones[k] = (v.0, v.1, v.2, v.3) }   // hourly values: kWh per hour = kW
            }
        }
        return r
    }

    /// Writes zone results onto the rooms (props energyHeating_kWh, energyCooling_kWh, peakHeating_kW, peakCooling_kW, per m²).
    @discardableResult
    public static func applyResults(_ r: Results, model: Model, to doc: inout ArchiDocument) -> Int {
        var n = 0
        for (zone, v) in r.zones {
            guard let id = model.zoneRooms[zone], let i = doc.elements.firstIndex(where: { $0.id == id }) else { continue }
            let a = max(model.zoneAreas[zone] ?? 0, 1e-9)
            doc.elements[i].props["energyHeating_kWh"] = fmt(v.heatKWh, 1)
            doc.elements[i].props["energyCooling_kWh"] = fmt(v.coolKWh, 1)
            doc.elements[i].props["energyHeating_kWh_m2"] = fmt(v.heatKWh / a, 2)
            doc.elements[i].props["energyCooling_kWh_m2"] = fmt(v.coolKWh / a, 2)
            doc.elements[i].props["peakHeating_kW"] = fmt(v.peakHeatKW, 2)
            doc.elements[i].props["peakCooling_kW"] = fmt(v.peakCoolKW, 2)
            n += 1
        }
        return n
    }

    static var command: CommandDef {
        CommandDef("ENERGYPLUS", aliases: ["EPLUS", "IDFEXPORT", "ENERGYSIM"], category: "Analyze",
                   summary: "EnergyPlus simulation: Export an IDF (rooms as zones, envelope surfaces, windows, layered constructions, ideal-loads HVAC, location) or Run an installed EnergyPlus on it with an EPW weather file: site energy, EUI, end uses, unmet hours and per-room heating/cooling energy and peak loads (written to the rooms).") { ed in
            let k = try await ed.getKeyword("Enter an option [Export/Run]", ["Export", "Run"], defaultValue: "Export") ?? "Export"
            let model: Model
            do { model = try build(ed.doc) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            var url = try await IOCommands.path(ed, "Enter IDF file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("idf") }
            try IOCommands.write(ed, url, "EnergyPlus input", { try model.idf.write(to: url, atomically: true, encoding: .utf8) })
            ed.print("\(model.zones.count) zone(s), \(model.surfaces.count) surface(s), \(model.windows.count) window(s).")
            guard k == "Run" else { return }
            guard let ep = findEnergyPlus(ed.doc) else { throw CommandError.invalid("EnergyPlus is not installed (energyplus.net; or set the ENERGYPLUS variable to its executable).") }
            let w = try await IOCommands.path(ed, "Enter EPW weather file")
            let out = url.deletingPathExtension().appendingPathExtension("eplus")
            do {
                let r = try run(idf: url, weather: w, outDir: out, energyPlus: ep)
                ed.print("EnergyPlus finished with status \(r.status); results in \(out.path)." + (r.siteEnergyKWh.map { " Total site energy \(fmt($0, 0)) kWh." } ?? ""))
                let res = results(out)
                ed.print(res.completed ? "Completed: \(res.warnings) warning(s), \(res.severe) severe error(s)." : "EnergyPlus did not complete (\(res.fatal) fatal, \(res.severe) severe error(s)); see eplusout.err.")
                if let e = res.euiKWhPerM2 { ed.print("Energy use intensity \(fmt(e, 1)) kWh/m²·a.") }
                for (k, v) in res.endUses.sorted(by: { $0.value > $1.value }) { ed.print("  \(k): \(fmt(v, 0)) kWh") }
                if let h = res.unmetHeatingHours, let c = res.unmetCoolingHours { ed.print("Unmet hours: heating \(fmt(h, 0)), cooling \(fmt(c, 0)).") }
                var d = ed.doc
                let n = applyResults(res, model: model, to: &d)
                if n > 0 { ed.doc = d; ed.print("Zone loads written to \(n) room(s) (energyHeating_kWh, energyCooling_kWh, peak loads).") }
            } catch { throw CommandError.invalid("EnergyPlus could not run: \(error.localizedDescription)") }
        }
    }
}
