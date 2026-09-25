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
    public struct Surface { public var name: String; public var type: String; public var construction: String; public var zone: String; public var boundary: String; public var vertices: [Vec3] }
    public struct Window { public var name: String; public var host: String; public var vertices: [Vec3] }
    public struct Model { public var zones: [(name: String, height: Double, volume: Double, origin: Vec3)]; public var surfaces: [Surface]; public var windows: [Window]; public var idf: String }

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
        for (el, s) in rooms {
            let lv = doc.level(el.level)
            let z0 = (lv?.elevation ?? 0) * m
            let h = (s.height > 0 ? s.height : (lv?.height ?? 3000 / m / 1000)) * m
            var poly = s.boundary.map { $0 * m }
            if GeometryOps.signedArea(poly) < 0 { poly.reverse() }
            let zname = unique("\(s.number.isEmpty ? "" : s.number + " ")\(s.name.isEmpty ? "Zone" : s.name)")
            let area = abs(GeometryOps.signedArea(poly))
            zones.append((zname, h, area * h, Vec3(0, 0, 0)))
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
            obj("BuildingSurface:Detailed", [s.name, s.type, s.construction, s.zone, s.boundary, "", s.boundary == "Outdoors" ? "SunExposed" : "NoSun", s.boundary == "Outdoors" ? "WindExposed" : "NoWind",
                                             "autocalculate", "\(s.vertices.count)"] + s.vertices.flatMap { [f($0.x), f($0.y), f($0.z)] })
        }
        for w in windows { obj("FenestrationSurface:Detailed", [w.name, "Window", "Window", w.host, "", "autocalculate", "", "1", "4"] + w.vertices.flatMap { [f($0.x), f($0.y), f($0.z)] }) }
        obj("HVACTemplate:Thermostat", ["Thermostat", "Heating Setpoint", "", "Cooling Setpoint", ""])
        for z in zones { obj("HVACTemplate:Zone:IdealLoadsAirSystem", [z.0, "Thermostat"]) }
        obj("Output:Variable", ["*", "Zone Ideal Loads Supply Air Total Heating Energy", "Hourly"])
        obj("Output:Variable", ["*", "Zone Ideal Loads Supply Air Total Cooling Energy", "Hourly"])
        obj("Output:Table:SummaryReports", ["AllSummary"])
        obj("OutputControl:Table:Style", ["CommaAndHTML"])
        return Model(zones: zones.map { (name: $0.0, height: $0.1, volume: $0.2, origin: $0.3) }, surfaces: surfaces, windows: windows, idf: o)
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

    static var command: CommandDef {
        CommandDef("ENERGYPLUS", aliases: ["EPLUS", "IDFEXPORT", "ENERGYSIM"], category: "Analyze",
                   summary: "EnergyPlus simulation: Export an IDF (rooms as zones, envelope surfaces, windows, layered constructions, ideal-loads HVAC, location) or Run an installed EnergyPlus on it with an EPW weather file (total site energy reported).", modifies: false) { ed in
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
            } catch { throw CommandError.invalid("EnergyPlus could not run: \(error.localizedDescription)") }
        }
    }
}
