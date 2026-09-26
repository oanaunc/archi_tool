// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for building physics, sun path, area schedules, structural model, code checks, acoustics, embodied
// carbon, isovists and IFC validation.
import Foundation

public enum BuildingAnalysisCommands {
    public static var all: [CommandDef] { [uValue, heatLoss, daylight, sunPath, levelAreas, analyticalModel, frameAnalysis, codeCheck, codeRules,
                                           reverb, carbon, isovist, ifcValidate, standardsCheck, solarRadiation] }

    @MainActor static func printTable(_ ed: Editor, _ t: [[String]]) {
        guard let head = t.first else { return }
        let widths = head.indices.map { c in t.map { c < $0.count ? $0[c].count : 0 }.max() ?? 0 }
        for row in t { ed.print(row.enumerated().map { $0.element.padding(toLength: max(widths[$0.offset], $0.element.count), withPad: " ", startingAt: 0) }.joined(separator: "  ")) }
    }

    static var uValue: CommandDef {
        CommandDef("UVALUE", aliases: ["UVAL", "THERMAL", "LAMBDA"], category: "Analysis",
                   summary: "U-value (EN ISO 6946) of selected walls, slabs, roofs and openings from their layers; Lambda sets a material's conductivity, Set a type's U-value.", modifies: false) { ed in
            let k = try await ed.getKeyword("Enter an option [Select/Lambda/Set]", ["Select", "Lambda", "Set"], defaultValue: "Select") ?? "Select"
            switch k {
            case "Lambda":
                guard let m = try await ed.getWord("Enter material name"), !m.isEmpty else { return }
                let cur = ThermalLibrary.lambda(m, doc: ed.doc)
                guard case .value(let v) = try await ed.getReal("Enter conductivity λ in W/m·K", defaultValue: cur), v > 0 else { throw CommandError.invalid("λ must be positive.") }
                ed.doc.setVariable("LAMBDA:" + m, fmt(v, 4))
                ed.print("λ(\(m)) = \(fmt(v, 4)) W/m·K")
            case "Set":
                guard let t = try await ed.getWord("Enter wall type, opening type or wall/roof/floor/window/door/curtainWall"), !t.isEmpty else { return }
                guard case .value(let v) = try await ed.getReal("Enter U-value in W/m²·K"), v > 0 else { throw CommandError.invalid("U must be positive.") }
                ed.doc.setVariable("UVALUE:" + t, fmt(v, 4))
                ed.print("U(\(t)) = \(fmt(v, 4)) W/m²·K")
            default:
                let ids = try await ed.getSelection("Select walls, slabs, roofs or openings")
                var n = 0
                for id in ids {
                    guard let el = ed.doc.element(id), let cu = Thermal.uValue(el, doc: ed.doc) else { continue }
                    n += 1
                    ed.print("#\(id) \(el.typeName)\(el.name.isEmpty ? "" : " \(el.name)"): U = \(fmt(cu.u, 3)) W/m²·K (\(cu.source))")
                    for l in cu.layers { ed.print("   \(l.material): \(fmt(l.thickness * 1000, 1)) mm, λ = \(l.lambda.map { fmt($0, 3) } ?? "1.0 (assumed)") W/m·K, R = \(fmt(l.thickness / (l.lambda ?? 1), 3)) m²K/W") }
                }
                if n == 0 { ed.print("No walls, slabs, roofs or openings selected.") }
            }
        }
    }

    static var heatLoss: CommandDef {
        CommandDef("HEATLOSS", aliases: ["HEATLOAD", "ENERGY", "ENERGYCALC"], category: "Analysis",
                   summary: "Design heat loss of the envelope (U·A·ΔT of exterior walls, windows, doors, roofs, ground floor) plus ventilation, and annual heating demand; optional CSV.", modifies: false) { ed in
            var o = HeatLossOptions.from(ed.doc)
            o.indoor = try await ed.getReal("Indoor design temperature °C", defaultValue: o.indoor).value ?? o.indoor
            o.outdoor = try await ed.getReal("Outdoor design temperature °C", defaultValue: o.outdoor).value ?? o.outdoor
            o.airChanges = try await ed.getReal("Air changes per hour", defaultValue: o.airChanges).value ?? o.airChanges
            ed.doc.setVariable("HEATINDOOR", fmt(o.indoor)); ed.doc.setVariable("HEATOUTDOOR", fmt(o.outdoor)); ed.doc.setVariable("AIRCHANGES", fmt(o.airChanges, 3))
            let r = HeatLoss.compute(ed.doc, options: o)
            guard !r.lines.isEmpty else { ed.print("No exterior walls, roofs or ground floors found (mark walls with prop isExternal=1 or use exterior wall types)."); return }
            for l in r.report.split(separator: "\n") { ed.print(String(l)) }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(r.table))
        }
    }

    static var daylight: CommandDef {
        CommandDef("DAYLIGHT", aliases: ["DAYLIGHTFACTOR", "DF"], category: "Analysis",
                   summary: "Average daylight factor of each room from its windows (BRE formula: T·Aw·θ·M / A(1−R²)) and the window-to-floor ratio; optional CSV.", modifies: false) { ed in
            let lv = try await AnalysisCommands.level(ed)
            let rows = Daylight.compute(ed.doc, level: lv)
            guard !rows.isEmpty else { ed.print("No rooms."); return }
            for r in rows { ed.print("\(r.number.isEmpty ? "-" : r.number) \(r.name): DF \(fmt(r.daylightFactor, 2))% (\(r.rating)), glazing \(fmt(r.glazedArea, 2)) m² = \(fmt(r.windowToFloor * 100, 1))% of \(fmt(r.floorArea, 2)) m²") }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(Daylight.table(rows)))
        }
    }

    static var sunPath: CommandDef {
        CommandDef("SUNPATH", aliases: ["SUNPATHDIAGRAM", "SUNCHART"], category: "Analysis",
                   summary: "Draws a polar sun path diagram (altitude rings, compass, the day's path with hours, solstices/equinox) for a date at the project location.") { ed in
            let today: String = {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
                let c = cal.dateComponents([.year, .month, .day], from: Date())
                return String(format: "%04d-%02d-%02d", c.year ?? 2025, c.month ?? 6, c.day ?? 21)
            }()
            let day = try await ed.getWord("Enter date (YYYY-MM-DD)", defaultValue: ed.doc.variable("SUNDATE") ?? today) ?? today
            guard SolarCalculator.date(day, "12:00", utcOffset: 0) != nil else { throw CommandError.invalid("Use a date like 2025-06-21.") }
            var o = SunPathOptions()
            o.latitude = ed.doc.info.latitude; o.longitude = ed.doc.info.longitude; o.northAngle = ed.doc.info.northAngle
            o.utcOffset = Double(ed.doc.variable("UTCOFFSET") ?? "") ?? (o.longitude / 15).rounded()
            o.center = try await ed.requirePoint("Specify center of the diagram")
            o.radius = try await ed.getPositive("Specify radius", base: o.center, defaultValue: 5000 / ed.doc.units.mm)
            o.textHeight = o.radius / 25
            let ents = SunPathDiagram.entities(day: day, options: o)
            if ed.doc.layer(named: o.layer) == nil { ed.doc.layers.append(Layer(name: o.layer, color: RGBA(0.96, 0.77, 0.09), lineweight: 0.18, description: "Sun path diagram")) }
            var ids: [EntityID] = []
            for e in ents { ids.append(ed.doc.add(e)) }
            ed.doc.setVariable("SUNDATE", day)
            let p = SunPathDiagram.path(day: day, options: o)
            if let noon = p.max(by: { $0.pos.altitude < $1.pos.altitude }) {
                ed.print("Sun path for \(day): \(p.isEmpty ? "sun below the horizon" : "highest \(fmt(noon.pos.altitude, 1))° at \(fmt(noon.time, 2)) h, azimuth \(fmt(noon.pos.azimuth, 1))°"); \(ids.count) objects on \(o.layer).")
            } else { ed.print("The sun stays below the horizon on \(day); drew the reference diagram.") }
        }
    }

    static var levelAreas: CommandDef {
        CommandDef("LEVELAREAS", aliases: ["AREABYLEVEL", "GFA", "FLOORAREAS"], category: "Analysis",
                   summary: "Area schedule by level: gross floor area (slabs, a 'gross' area plan or rooms) and net room area with the net/gross ratio; optional CSV.", modifies: false) { ed in
            let rows = AreaSchedule.compute(ed.doc)
            guard !rows.isEmpty else { ed.print("No floor slabs or rooms."); return }
            printTable(ed, AreaSchedule.table(rows))
            try await AnalysisCommands.saveCSV(ed, CSVText.make(AreaSchedule.table(rows)))
        }
    }

    static var analyticalModel: CommandDef {
        CommandDef("ANALYTICALMODEL", aliases: ["STRUCTMODEL", "ANALYTICAL", "ANALYTICALOUT"], category: "Structure",
                   summary: "Builds the structural analytical model (nodes, members, wall/slab panels, supports, loads) from columns, beams, walls and slabs and writes it as JSON, OpenSees Tcl, SAF (.xlsx) or an IFC4 structural analysis view (.ifc).", modifies: false) { ed in
            var o = AnalyticalOptions.from(ed.doc)
            o.deadLoad = try await ed.getReal("Superimposed dead load kN/m²", defaultValue: o.deadLoad).value ?? o.deadLoad
            o.liveLoad = try await ed.getReal("Live load kN/m²", defaultValue: o.liveLoad).value ?? o.liveLoad
            ed.doc.setVariable("DEADLOAD", fmt(o.deadLoad, 3)); ed.doc.setVariable("LIVELOAD", fmt(o.liveLoad, 3))
            let m = StructuralAnalysis.model(ed.doc, options: o)
            ed.print("Analytical model: \(m.nodes.count) nodes (\(m.nodes.filter(\.isSupported).count) supported), \(m.members.count) members, \(m.panels.count) panels, \(m.nodeLoads.count) nodal loads.")
            for w in m.warnings { ed.print("Warning: " + w) }
            guard let p = try await ed.getWord("Enter file name to save (.json analytical model, .tcl OpenSees, .xlsx SAF, .ifc structural analysis view) <none>"), !p.isEmpty else { return }
            var url = IOCommands.resolve(ed, p)
            if url.pathExtension.isEmpty { url.appendPathExtension("json") }
            switch url.pathExtension.lowercased() {
            case "xlsx":
                try IOCommands.write(ed, url, "SAF model", { try StructuralExchange.saf(m, name: ed.doc.info.name, options: o).write(to: url, options: .atomic) })
                return
            case "ifc":
                let t = StructuralExchange.ifc(m, name: ed.doc.info.name, options: o, author: ed.doc.info.author)
                try IOCommands.write(ed, url, "IFC structural analysis model", { try t.write(to: url, atomically: true, encoding: .utf8) })
                return
            default: break
            }
            if url.pathExtension.lowercased() == "tcl" {
                let tcl = StructuralLoads.openSeesTcl(m, name: ed.doc.info.name)
                try IOCommands.write(ed, url, "OpenSees model", { try tcl.write(to: url, atomically: true, encoding: .utf8) })
                return
            }
            let data = try JSONSerialization.data(withJSONObject: m.json(name: ed.doc.info.name), options: [.prettyPrinted, .sortedKeys])
            try IOCommands.write(ed, url, "analytical model", { try data.write(to: url, options: .atomic) })
        }
    }

    static var frameAnalysis: CommandDef {
        CommandDef("FRAMEANALYSIS", aliases: ["FRAMESOLVE", "STRUCTANALYSIS"], category: "Structure",
                   summary: "Linear static analysis of the column/beam frame (self weight + slab loads lumped to columns): displacements and support reactions.", modifies: false) { ed in
            let m = StructuralAnalysis.model(ed.doc, options: AnalyticalOptions.from(ed.doc))
            guard !m.members.isEmpty else { throw CommandError.invalid("No columns or beams to analyse.") }
            do {
                let r = try StructuralAnalysis.solve(m)
                let (n, d) = r.maxDisplacement
                ed.print("Frame: \(m.nodes.count) nodes, \(m.members.count) members. Largest displacement \(fmt(d * 1000, 3)) mm at node \(n)" + (n > 0 ? " (\(fmt(m.nodes[n - 1].p.x, 2)), \(fmt(m.nodes[n - 1].p.y, 2)), \(fmt(m.nodes[n - 1].p.z, 2)) m)." : "."))
                var total = Vec3.zero
                for (id, rr) in r.reactions.sorted(by: { $0.key < $1.key }) {
                    total = total + rr.f
                    ed.print("  Support \(id): Fz = \(fmt(rr.f.z, 2)) kN, Fx = \(fmt(rr.f.x, 2)), Fy = \(fmt(rr.f.y, 2)), M = (\(fmt(rr.m.x, 2)), \(fmt(rr.m.y, 2)), \(fmt(rr.m.z, 2))) kNm")
                }
                ed.print("Total vertical reaction \(fmt(total.z, 2)) kN.")
                for w in m.warnings { ed.print("Warning: " + w) }
            } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }

    static var codeCheck: CommandDef {
        CommandDef("CODECHECK", aliases: ["CHECKCODE", "COMPLIANCE", "RULECHECK"], category: "Analysis",
                   summary: "Checks rooms (area, height, width, window-to-floor ratio), stairs (riser, tread, 2R+T, width, flight), ramps and doors against JSON code rules (CODERULES or a file); lists, selects and zooms.", modifies: false) { ed in
            let src = try await ed.getWord("Enter rules JSON file <drawing rules>")
            var rules = CodeRules.from(ed.doc)
            if let p = src, !p.isEmpty {
                let url = IOCommands.resolve(ed, p)
                do { rules = try CodeRules.fromJSON(try FileImport.readText(url)) }
                catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.path)") }
            }
            let issues = CodeCheck.check(ed.doc, rules: rules)
            guard !issues.isEmpty else { ed.print("No code issues (\(rules.name))."); ed.selection = []; return }
            for (i, it) in issues.enumerated() { ed.print("\(i + 1). \(it.description)") }
            ed.print("\(issues.count) issue\(issues.count == 1 ? "" : "s") against \(rules.name).")
            ed.selection = Set(issues.flatMap(\.ids).filter { ed.doc.contains($0) })
            try await AnalysisCommands.zoomLoop(ed, issues.map { ($0.ids, $0.bounds) })
        }
    }

    static var codeRules: CommandDef {
        CommandDef("CODERULES", aliases: ["RULES"], category: "Analysis",
                   summary: "Stores code rules in the drawing from a JSON file (Load), writes the current rules to a file (Save) or restores the defaults.") { ed in
            let k = try await ed.getKeyword("Enter an option [Load/Save/Defaults/List]", ["Load", "Save", "Defaults", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "Load":
                let url = try await IOCommands.path(ed, "Enter rules JSON file")
                do {
                    let r = try CodeRules.fromJSON(try FileImport.readText(url))
                    ed.doc.setVariable("CODERULES", r.json)
                    ed.print("Loaded rules '\(r.name)'.")
                } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.path)") }
            case "Save":
                var url = try await IOCommands.path(ed, "Enter rules JSON file to write")
                if url.pathExtension.isEmpty { url.appendPathExtension("json") }
                let text = CodeRules.from(ed.doc).json
                try IOCommands.write(ed, url, "code rules", { try text.write(to: url, atomically: true, encoding: .utf8) })
            case "Defaults":
                ed.doc.variables.removeValue(forKey: "CODERULES")
                ed.print("Using the default rules.")
            default:
                for l in CodeRules.from(ed.doc).json.split(separator: "\n") { ed.print(String(l)) }
            }
        }
    }

    static var reverb: CommandDef {
        CommandDef("REVERB", aliases: ["RT60", "REVERBERATION", "ACOUSTICS"], category: "Analysis",
                   summary: "Reverberation time (Sabine RT60 at 500 Hz) of each room from its volume and surface absorption; optional CSV.", modifies: false) { ed in
            let lv = try await AnalysisCommands.level(ed)
            let rows = Acoustics.reverberation(ed.doc, level: lv)
            guard !rows.isEmpty else { ed.print("No rooms."); return }
            for r in rows { ed.print("\(r.number.isEmpty ? "-" : r.number) \(r.name): V = \(fmt(r.volume, 1)) m³, A = \(fmt(r.absorption, 2)) m², RT60 = \(fmt(r.rt60, 2)) s") }
            let t = [["number", "name", "volume_m3", "absorption_m2", "rt60_s"]] + rows.map { [$0.number, $0.name, fmt($0.volume, 2), fmt($0.absorption, 2), fmt($0.rt60, 2)] }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(t))
        }
    }

    static var carbon: CommandDef {
        CommandDef("CARBON", aliases: ["EMBODIEDCARBON", "LCA", "CO2"], category: "Analysis",
                   summary: "Embodied carbon (A1–A3, kgCO2e) of the model's materials from takeoff volumes, densities and carbon factors (CARBON:/DENSITY: overrides); optional CSV.", modifies: false) { ed in
            let lv = try await AnalysisCommands.level(ed)
            let rows = EmbodiedCarbon.compute(ed.doc, level: lv)
            guard !rows.isEmpty else { ed.print("No material volumes."); return }
            printTable(ed, EmbodiedCarbon.table(rows))
            if rows.contains(where: \.assumed) { ed.print("Rows marked 'assumed' use 2000 kg/m³ and 0.2 kgCO2e/kg: set CARBON:<material> and DENSITY:<material>.") }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(EmbodiedCarbon.table(rows)))
        }
    }

    static var isovist: CommandDef {
        CommandDef("ISOVIST", aliases: ["VIEWSHED", "VISIBILITY"], category: "Analysis",
                   summary: "Draws the isovist (area visible from a point at eye height, walls block, doors and openings are see-through) and reports its area.") { ed in
            let eye = try await ed.requirePoint("Specify viewpoint")
            let u = ed.doc.units.mm
            let range = try await ed.getPositive("Maximum view distance", base: eye, defaultValue: 30000 / u)
            let glass = try await ed.getYesNo("See through windows?", defaultValue: false)
            let h = 1600 / u
            let obs = Isovist.obstacles(ed.doc, level: ed.doc.currentLevel, eyeHeight: h, seeThroughWindows: glass)
            let poly = Isovist.polygon(from: eye, obstacles: obs, maxDistance: range)
            let area = abs(GeometryOps.signedArea(poly)) * u * u / 1e6
            let layer = "A-ISOVIST"
            if ed.doc.layer(named: layer) == nil { ed.doc.layers.append(Layer(name: layer, color: RGBA(0.3, 0.7, 0.95), lineweight: 0.18, description: "Isovists")) }
            let id = ed.doc.add(Entity(layer: layer, geometry: .polyline(PolylineGeom(points: poly, closed: true)), props: ["isovist": "1", "area": fmt(area, 2)]))
            let far = poly.map { $0.distance(to: eye) }.max() ?? 0
            ed.print("Isovist #\(id): visible area \(fmt(area, 2)) m², farthest point \(fmt(far * u / 1000, 2)) m.")
        }
    }

    static var ifcValidate: CommandDef {
        CommandDef("IFCVALIDATE", aliases: ["IFCCHECK", "VALIDATEIFC"], category: "Analysis",
                   summary: "Validates an IFC file (or the model's own IFC export): syntax, schema header, references, GlobalIds, attribute counts, project/units, spatial containment.", modifies: false) { ed in
            let p = try await ed.getWord("Enter IFC file name <current model>")
            let text: String
            let own = p?.isEmpty ?? true
            if let p, !p.isEmpty { text = try FileImport.readText(IOCommands.resolve(ed, p)) }
            else { text = IFCExporter.export(doc: ed.doc, meshes: MeshBuilder.build(doc: ed.doc)) }
            let issues = IFCValidator.validate(text)
            guard !issues.isEmpty else { ed.print("IFC is valid: no issues found."); return }
            // Issues of the model's own export (or a file exported from it) link to the drawing's elements.
            let f = try? STEPParser.parse(text)
            var zoom: [(ids: [EntityID], box: BBox2)] = []
            for (i, it) in issues.enumerated() {
                let els = f.map { IFCValidator.elements(for: it, in: $0, doc: ed.doc) } ?? []
                var box = BBox2.empty
                for id in els { if let el = ed.doc.element(id) { box.add(PlanRepresentation.bounds(el, doc: ed.doc)) } }
                zoom.append((els, box))
                ed.print("\(i + 1). \(it.description)" + (els.isEmpty ? "" : " → elements " + els.prefix(8).map { "#\($0)" }.joined(separator: ", ") + (els.count > 8 ? ", …" : "")))
            }
            ed.print("\(issues.count) issue(s)." + (own ? "" : " Elements are matched by GlobalId."))
            let all = Set(zoom.flatMap(\.ids))
            if !all.isEmpty { ed.selection = all }
            try await AnalysisCommands.zoomLoop(ed, zoom)
        }
    }

    static var standardsCheck: CommandDef {
        CommandDef("STANDARDSCHECK", aliases: ["CHECKSTANDARDS", "DRAWINGSTANDARDS", "CADSTANDARDS"], category: "Analysis",
                   summary: "Checks layers (naming pattern, required layers, objects on layer 0), ByLayer properties, text heights/styles and linetypes against a JSON drawing standard (DRAWINGSTANDARDS variable or a file); lists, selects and zooms.", modifies: false) { ed in
            let src = try await ed.getWord("Enter standards JSON file <drawing standard>")
            var st = DrawingStandards.from(ed.doc)
            if let p = src, !p.isEmpty {
                let url = IOCommands.resolve(ed, p)
                do {
                    st = try DrawingStandards.fromJSON(try FileImport.readText(url))
                    if try await ed.getYesNo("Store this standard in the drawing?", defaultValue: false) { ed.doc.setVariable("DRAWINGSTANDARDS", st.json) }
                } catch let e as CommandError { throw e }
                catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.path)") }
            }
            let issues = StandardsCheck.check(ed.doc, standards: st)
            guard !issues.isEmpty else { ed.print("The drawing follows \(st.name)."); ed.selection = []; return }
            for (i, it) in issues.enumerated() { ed.print("\(i + 1). [\(it.severity.rawValue.uppercased())] \(it.code): \(it.message)") }
            ed.selection = Set(issues.flatMap(\.ids).filter { ed.doc.contains($0) })
            try await AnalysisCommands.zoomLoop(ed, issues.map { ($0.ids, $0.bounds) })
        }
    }

    static var solarRadiation: CommandDef {
        CommandDef("SOLARRADIATION", aliases: ["INSOLATION", "IRRADIATION", "SOLARGAIN"], category: "Analysis",
                   summary: "Clear-sky solar irradiation (kWh/m² per day) on exterior walls, windows and roofs for a date at the project location; optional CSV.", modifies: false) { ed in
            let day = try await ed.getWord("Enter date (YYYY-MM-DD)", defaultValue: ed.doc.variable("SUNDATE") ?? "2025-06-21") ?? "2025-06-21"
            guard SolarCalculator.date(day, "12:00", utcOffset: 0) != nil else { throw CommandError.invalid("Use a date like 2025-06-21.") }
            let off = Double(ed.doc.variable("UTCOFFSET") ?? "") ?? (ed.doc.info.longitude / 15).rounded()
            let rows = SolarRadiation.surfaces(ed.doc, day: day, utcOffset: off)
            guard !rows.isEmpty else { ed.print("No exterior walls or roofs."); return }
            for r in rows { ed.print("#\(r.id) \(r.kind)\(r.azimuth >= 0 ? " facing \(fmt(r.azimuth, 0))°" : "") tilt \(fmt(r.tilt, 0))°: \(fmt(r.kWhPerM2, 2)) kWh/m², \(fmt(r.area, 2)) m² → \(fmt(r.kWh, 1)) kWh") }
            ed.print("Total on \(day): \(fmt(rows.reduce(0) { $0 + $1.kWh }, 1)) kWh (windows \(fmt(rows.filter { $0.kind == "window" }.reduce(0) { $0 + $1.kWh }, 1)) kWh).")
            let t = [["id", "kind", "azimuth_deg", "tilt_deg", "area_m2", "kWh_per_m2_day", "kWh_day"]] + rows.map { ["\($0.id)", $0.kind, $0.azimuth >= 0 ? fmt($0.azimuth, 1) : "", fmt($0.tilt, 1), fmt($0.area, 2), fmt($0.kWhPerM2, 3), fmt($0.kWh, 2)] }
            try await AnalysisCommands.saveCSV(ed, CSVText.make(t))
        }
    }
}
