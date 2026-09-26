// Oanarina Archi Tool — GPL-3.0-or-later
// Read-only analysis tools for agents (MCP server in archi-cli, local agent server): each returns JSON-compatible
// dictionaries. Tool definitions carry MCP input schemas.
import Foundation

public enum AgentTools {
    public struct ToolError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    static func schema(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var s: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { s["required"] = required }
        return s
    }
    static let levelProp: [String: Any] = ["type": "integer", "description": "Level id (omit for all levels)"]
    static let formatProp: [String: Any] = ["type": "string", "enum": ["json", "csv"]]

    /// MCP tool definitions (name, title, description, inputSchema): read-only tools of this file and AgentExtraTools.
    public static var definitions: [[String: Any]] { baseDefinitions + AgentExtraTools.definitions }

    static let baseDefinitions: [[String: Any]] = [
        ["name": "heat_loss", "title": "Heat loss",
         "description": "Design heat loss of the envelope (U·A·ΔT of exterior walls, windows, doors, curtain walls, roofs, ground floor) plus ventilation, and annual heating demand from degree days. U-values come from wall-type layers and material conductivities (LAMBDA:/UVALUE: variables override).",
         "inputSchema": schema(["indoor": ["type": "number"], "outdoor": ["type": "number"], "airChanges": ["type": "number"], "degreeDays": ["type": "number"],
                                "thermalBridge": ["type": "number"], "format": formatProp])],
        ["name": "u_values", "title": "U-values", "description": "U-value (EN ISO 6946) and layers of walls, slabs, roofs and openings (all, or the given ids).",
         "inputSchema": schema(["ids": ["type": "array", "items": ["type": "integer"]]])],
        ["name": "daylight", "title": "Daylight factor", "description": "Average daylight factor (%) and window-to-floor ratio of each room from its windows.",
         "inputSchema": schema(["level": levelProp, "format": formatProp])],
        ["name": "code_check", "title": "Code check",
         "description": "Checks rooms (area, height, width, window-to-floor ratio), stairs (riser, tread, 2R+T, width, flight length), ramps and doors against code rules: `rules` (JSON object, see CODERULES), a rules file `path`, or the drawing's rules. Each issue has element ids and a zoom box.",
         "inputSchema": schema(["rules": ["type": "object"], "path": ["type": "string"]])],
        ["name": "level_areas", "title": "Areas by level", "description": "Gross floor area and net room area per level with the net/gross ratio.",
         "inputSchema": schema(["format": formatProp])],
        ["name": "schedule", "title": "Schedule", "description": "Element schedule as rows: walls, doors, windows, rooms, slabs or all.",
         "inputSchema": schema(["kind": ["type": "string", "enum": ["walls", "doors", "windows", "rooms", "slabs", "all"]], "format": formatProp], required: ["kind"])],
        ["name": "structural_model", "title": "Structural analytical model",
         "description": "Analytical model (nodes, members with sections, wall/slab panels, supports, loads) from columns, beams, walls and slabs; `solve`: also run the built-in linear frame analysis (displacements, reactions).",
         "inputSchema": schema(["solve": ["type": "boolean"], "deadLoad": ["type": "number"], "liveLoad": ["type": "number"]])],
        ["name": "energy_extras", "title": "Acoustics and embodied carbon",
         "description": "Room reverberation times (Sabine RT60) and embodied carbon (kgCO2e) of the materials.",
         "inputSchema": schema(["level": levelProp])],
        ["name": "sun_path", "title": "Sun path", "description": "Hourly sun azimuth/altitude between sunrise and sunset for a date at the project location (local time with `utcOffset`).",
         "inputSchema": schema(["date": ["type": "string", "description": "YYYY-MM-DD"], "utcOffset": ["type": "number"], "latitude": ["type": "number"], "longitude": ["type": "number"]], required: ["date"])],
        ["name": "plan_svg", "title": "Plan as SVG",
         "description": "Render-free image of a level's 2D plan (walls, doors, windows, rooms, annotations) as SVG text, fitted to `width` pixels; optional `path` also writes the file.",
         "inputSchema": schema(["level": ["type": "integer"], "width": ["type": "integer"], "background": ["type": "string", "description": "#RRGGBB (default white)"], "path": ["type": "string"]])],
        ["name": "ids_check", "title": "Check IDS",
         "description": "Checks the model's IFC export (or `ifcPath`) against an Information Delivery Specification file (`idsPath`): entity, attribute, property and material requirements per specification.",
         "inputSchema": schema(["idsPath": ["type": "string"], "ifcPath": ["type": "string"]], required: ["idsPath"])],
        ["name": "ifc_validate", "title": "Validate IFC",
         "description": "Validates an IFC file (`path`) or the model's own IFC export (`schema` IFC2X3 / IFC4 / IFC4X3_ADD2, `modelView` ReferenceView / DesignTransferView): syntax, schema, references, GlobalIds, attribute kinds, EXPRESS WHERE rules (codes WR-<Entity>.<Rule>), units, spatial containment. For the model's own export each issue lists the drawing `elements` to zoom to.",
         "inputSchema": schema(["path": ["type": "string"], "schema": ["type": "string", "enum": ["IFC2X3", "IFC4", "IFC4X3_ADD2"]],
                                "modelView": ["type": "string", "enum": ["ReferenceView", "DesignTransferView"]]])],
        ["name": "validate_file", "title": "Validate exchange file",
         "description": "Validates a file on disk: IFC / IfcZIP / ifcXML (schema and WHERE rules), DXF (group-code audit and read-back), gbXML (XSD requirements), .archi (round trip plus its IFC and DXF exports; `schema` picks the IFC schema). Returns valid, counts and issues with locations.",
         "inputSchema": schema(["path": ["type": "string"], "schema": ["type": "string", "enum": ["IFC2X3", "IFC4", "IFC4X3_ADD2"]]], required: ["path"])],
    ]

    public static var names: Set<String> { Set(definitions.compactMap { $0["name"] as? String }) }

    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }
    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
    static func round(_ v: Double, _ d: Int = 4) -> Double { Double(fmt(v, d)) ?? v }

    /// Runs a tool. Returns a JSON object, or a String (CSV/SVG) when asked for text.
    public static func call(_ name: String, _ a: [String: Any], doc: ArchiDocument, resolve: (String) -> URL = { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }) throws -> Any {
        let csv = (a["format"] as? String) == "csv"
        switch name {
        case "heat_loss":
            var o = HeatLossOptions.from(doc)
            if let v = num(a["indoor"]) { o.indoor = v }
            if let v = num(a["outdoor"]) { o.outdoor = v }
            if let v = num(a["airChanges"]) { o.airChanges = v }
            if let v = num(a["degreeDays"]) { o.degreeDays = v }
            if let v = num(a["thermalBridge"]) { o.thermalBridge = v }
            let r = HeatLoss.compute(doc, options: o)
            if csv { return CSVText.make(r.table) }
            return ["deltaT_K": r.deltaT, "transmission_W_K": round(r.transmission), "ventilation_W_K": round(r.ventilation), "designLoad_W": round(r.designLoad, 1),
                    "specificLoad_W_m2": round(r.specificLoad, 2), "annualDemand_kWh": round(r.annualDemand, 0), "heatedVolume_m3": round(r.volume, 2), "floorArea_m2": round(r.floorArea, 2),
                    "byComponent": Dictionary(uniqueKeysWithValues: ["wall", "window", "door", "curtainWall", "roof", "floor"].map { ($0, round(r.total($0))) }),
                    "lines": r.lines.map { ["id": $0.id, "component": $0.component, "name": $0.name, "area_m2": round($0.area), "U": round($0.u), "factor": $0.factor, "H_W_K": round($0.h)] },
                    "assumedMaterials": r.assumedMaterials]
        case "u_values":
            let ids = Set((a["ids"] as? [Any])?.compactMap(int) ?? [])
            var out: [[String: Any]] = []
            for el in doc.elements where ids.isEmpty || ids.contains(el.id) {
                guard let cu = Thermal.uValue(el, doc: doc) else { continue }
                var o: [String: Any] = ["id": el.id, "type": el.typeName, "U_W_m2K": round(cu.u), "source": cu.source,
                                        "layers": cu.layers.map { ["material": $0.material, "thickness_m": round($0.thickness, 5), "lambda": $0.lambda.map { $0 as Any } ?? NSNull()] }]
                if case .wall = el.geometry { o["exterior"] = Thermal.isExterior(el, doc: doc) }
                out.append(o)
            }
            return ["elements": out, "count": out.count]
        case "daylight":
            let rows = Daylight.compute(doc, level: int(a["level"]))
            if csv { return CSVText.make(Daylight.table(rows)) }
            return ["rooms": rows.map { ["id": $0.id, "number": $0.number, "name": $0.name, "floor_m2": round($0.floorArea, 2), "glazing_m2": round($0.glazedArea, 3),
                                         "windowToFloor": round($0.windowToFloor), "daylightFactor_pct": round($0.daylightFactor, 2), "rating": $0.rating, "windows": $0.windows] }]
        case "code_check":
            var rules = CodeRules.from(doc)
            if let r = a["rules"] as? [String: Any] {
                rules = try CodeRules.fromJSON(String(decoding: try JSONSerialization.data(withJSONObject: r), as: UTF8.self))
            } else if let p = a["path"] as? String {
                rules = try CodeRules.fromJSON(try FileImport.readText(resolve(p)))
            }
            let issues = CodeCheck.check(doc, rules: rules)
            return ["rules": rules.name, "count": issues.count, "issues": issues.map(issueJSON)]
        case "level_areas":
            let rows = AreaSchedule.compute(doc)
            if csv { return CSVText.make(AreaSchedule.table(rows)) }
            return ["levels": rows.map { ["level": $0.level, "name": $0.name, "elevation_m": $0.elevation, "gross_m2": round($0.grossArea, 2), "net_m2": round($0.netArea, 2),
                                          "netToGross": round($0.efficiency), "rooms": $0.rooms, "grossFrom": $0.grossSource] },
                    "totalGross_m2": round(rows.reduce(0) { $0 + $1.grossArea }, 2), "totalNet_m2": round(rows.reduce(0) { $0 + $1.netArea }, 2)]
        case "schedule":
            let kind = (a["kind"] as? String) ?? "all"
            guard ScheduleExporter.kinds.contains(kind.lowercased()) else { throw ToolError(message: "kind must be one of \(ScheduleExporter.kinds.joined(separator: ", "))") }
            if csv { return ScheduleExporter.csv(doc: doc, kind: kind) }
            let t = ScheduleExporter.table(doc: doc, kind: kind)
            guard let head = t.first else { return ["rows": []] }
            return ["kind": kind, "columns": head, "rows": t.dropFirst().map { row in Dictionary(uniqueKeysWithValues: head.enumerated().map { ($0.element, $0.offset < row.count ? row[$0.offset] : "") }) }]
        case "structural_model":
            var o = AnalyticalOptions.from(doc)
            if let v = num(a["deadLoad"]) { o.deadLoad = v }
            if let v = num(a["liveLoad"]) { o.liveLoad = v }
            let m = StructuralAnalysis.model(doc, options: o)
            var out = m.json(name: doc.info.name)
            if (a["solve"] as? Bool) == true {
                do {
                    let r = try StructuralAnalysis.solve(m)
                    out["analysis"] = [
                        "maxDisplacement_m": round(r.maxDisplacement.value, 8), "maxDisplacementNode": r.maxDisplacement.node,
                        "displacements": r.displacements.sorted { $0.key < $1.key }.map { ["node": $0.key, "u": [$0.value.u.x, $0.value.u.y, $0.value.u.z].map { round($0, 9) }] },
                        "reactions": r.reactions.sorted { $0.key < $1.key }.map { ["node": $0.key, "F": [$0.value.f.x, $0.value.f.y, $0.value.f.z].map { round($0, 4) },
                                                                                   "M": [$0.value.m.x, $0.value.m.y, $0.value.m.z].map { round($0, 4) }] },
                    ] as [String: Any]
                } catch { out["analysisError"] = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
            }
            return out
        case "energy_extras":
            let lv = int(a["level"])
            let rv = Acoustics.reverberation(doc, level: lv), co = EmbodiedCarbon.compute(doc, level: lv)
            return ["rooms": rv.map { ["id": $0.id, "number": $0.number, "name": $0.name, "volume_m3": round($0.volume, 2), "absorption_m2": round($0.absorption, 3), "rt60_s": round($0.rt60, 2)] },
                    "carbon": co.map { ["material": $0.material, "volume_m3": round($0.volume, 3), "mass_kg": round($0.mass, 1), "factor_kgCO2e_kg": $0.factor, "kgCO2e": round($0.carbon, 1), "assumed": $0.assumed] },
                    "totalCarbon_kgCO2e": round(co.reduce(0) { $0 + $1.carbon }, 1)]
        case "sun_path":
            guard let day = a["date"] as? String, SolarCalculator.date(day, "12:00", utcOffset: 0) != nil else { throw ToolError(message: "date must be YYYY-MM-DD") }
            var o = SunPathOptions()
            o.latitude = num(a["latitude"]) ?? doc.info.latitude; o.longitude = num(a["longitude"]) ?? doc.info.longitude
            o.utcOffset = num(a["utcOffset"]) ?? Double(doc.variable("UTCOFFSET") ?? "") ?? (o.longitude / 15).rounded()
            let p = SunPathDiagram.path(day: day, options: o, stepMinutes: 60)
            return ["date": day, "latitude": o.latitude, "longitude": o.longitude, "utcOffset": o.utcOffset,
                    "hours": p.map { ["hour": round($0.time, 2), "azimuth": round($0.pos.azimuth, 2), "altitude": round($0.pos.altitude, 2)] }]
        case "plan_svg":
            let level = int(a["level"]) ?? doc.currentLevel
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: level))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            b = b.expanded(by: max(b.width, b.height) * 0.02)
            let width = Double(max(64, min(int(a["width"]) ?? 1200, 8000)))
            let bg = (a["background"] as? String).map { RGBA(hex: $0) } ?? .white
            return SVGExporter.export(entries: entries, bounds: b, background: bg, pixelsPerUnit: width / max(b.width, 1e-9))
        case "ids_check":
            guard let ip = a["idsPath"] as? String else { throw ToolError(message: "missing idsPath") }
            let specs = try IDSValidator.parse(try Data(contentsOf: resolve(ip)))
            let ifc = try (a["ifcPath"] as? String).map { try FileImport.readText(resolve($0)) } ?? IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc))
            let rs = try IDSValidator.validate(ids: specs, ifc: ifc)
            return ["passed": rs.allSatisfy(\.passed), "specifications": rs.map { r in
                ["name": r.specification, "passed": r.passed, "applicable": r.applicable, "notes": r.notes,
                 "failures": r.failed.sorted { $0.key < $1.key }.prefix(200).map { ["instance": $0.key, "reasons": $0.value] }] as [String: Any] }]
        case "validate_file":
            guard let p = a["path"] as? String else { throw ToolError(message: "path is required") }
            var sc = IFCExportOptions.Schema.ifc4
            if let x = (a["schema"] as? String)?.uppercased() {
                guard let v = IFCExportOptions.Schema.allCases.first(where: { $0.rawValue == x || $0.rawValue.hasPrefix(x) }) else { throw ToolError(message: "unknown IFC schema \(x)") }
                sc = v
            }
            return try FileValidation.validate(resolve(p), ifcSchema: sc).json
        case "ifc_validate":
            let text: String
            let own = a["path"] == nil
            if let p = a["path"] as? String { text = try FileImport.readText(resolve(p)) }
            else {
                var o = IFCExportOptions()
                if let sc = (a["schema"] as? String)?.uppercased() {
                    guard let v = IFCExportOptions.Schema.allCases.first(where: { $0.rawValue == sc || $0.rawValue.hasPrefix(sc) }) else { throw ToolError(message: "unknown IFC schema \(sc)") }
                    o.schema = v
                }
                if let mv = (a["modelView"] as? String)?.lowercased() { o.modelView = mv.hasPrefix("design") ? .designTransferView : .referenceView }
                text = IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc), options: o)
            }
            let issues = IFCValidator.validate(text)
            let parsed = own ? try? STEPParser.parse(text) : nil
            return ["valid": !issues.contains { $0.severity == .error }, "count": issues.count,
                    "issues": issues.map { i -> [String: Any] in
                        var o: [String: Any] = ["severity": i.severity.rawValue, "code": i.code, "message": i.message, "instances": Array(i.instances.prefix(50))]
                        if let f = parsed { o["elements"] = Array(IFCValidator.elements(for: i, in: f, doc: doc).prefix(50)) }
                        return o
                    }]
        default:
            if AgentExtraTools.names.contains(name) { return try AgentExtraTools.call(name, a, doc: doc, resolve: resolve) }
            throw ToolError(message: "unknown tool \(name)")
        }
    }

    public static func issueJSON(_ i: ModelIssue) -> [String: Any] {
        var o: [String: Any] = ["severity": i.severity.rawValue, "code": i.code, "message": i.message, "ids": i.ids]
        if !i.bounds.isEmpty { o["zoom"] = ["min": [i.bounds.min.x, i.bounds.min.y], "max": [i.bounds.max.x, i.bounds.max.y]] }
        return o
    }
}
