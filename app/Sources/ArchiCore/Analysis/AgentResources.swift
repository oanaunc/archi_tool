// Oanarina Archi Tool — GPL-3.0-or-later
// Model Context Protocol extras shared by archi-cli and the app's agent server: resources (the document, schedules,
// takeoff, markups, plans as SVG), prompt templates, more analysis tools (egress, accessibility, energy balance,
// bill of quantities, takeoff by phase, compare, markups, BCF, exchange validation) and batch job specifications.
import Foundation

// MARK: - Resources

public enum AgentResources {
    public struct Content { public var uri: String; public var mimeType: String; public var text: String }

    static let scheduleKinds = ["walls", "doors", "windows", "rooms", "slabs", "all"]

    /// Concrete resources for the current document.
    public static func list(_ doc: ArchiDocument) -> [[String: Any]] {
        var out: [[String: Any]] = [
            ["uri": "archi://document/summary", "name": "Document summary", "mimeType": "application/json", "description": "Project info, units, layers, levels and object counts."],
            ["uri": "archi://document", "name": "Document (.archi JSON)", "mimeType": "application/json", "description": "The whole document in the native .archi format."],
            ["uri": "archi://takeoff", "name": "Quantity takeoff", "mimeType": "text/csv", "description": "Quantities per category, type and material (SI units)."],
            ["uri": "archi://takeoff/phases", "name": "Takeoff by phase and level", "mimeType": "text/csv", "description": "Quantities per construction phase, work (new/demolished) and level."],
            ["uri": "archi://markups", "name": "Markups", "mimeType": "application/json", "description": "Review comments with author, date, status and linked elements."],
            ["uri": "archi://levels", "name": "Levels", "mimeType": "application/json", "description": "Levels with elevations and heights."],
            ["uri": "archi://layers", "name": "Layers", "mimeType": "application/json", "description": "Layers with colour, linetype, visibility."],
        ]
        for k in scheduleKinds { out.append(["uri": "archi://schedules/\(k)", "name": "Schedule: \(k)", "mimeType": "text/csv", "description": "Element schedule (\(k))."]) }
        for l in doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
            out.append(["uri": "archi://plan/\(l.id)", "name": "Plan: \(l.name)", "mimeType": "image/svg+xml", "description": "2D plan of level \(l.name) as SVG (layers as groups)."])
        }
        return out
    }

    public static let templates: [[String: Any]] = [
        ["uriTemplate": "archi://schedules/{kind}", "name": "Schedule", "mimeType": "text/csv", "description": "Schedule of walls, doors, windows, rooms, slabs or all."],
        ["uriTemplate": "archi://element/{id}", "name": "Element or entity", "mimeType": "application/json", "description": "One BIM element or drafting entity by id."],
        ["uriTemplate": "archi://plan/{level}", "name": "Plan SVG", "mimeType": "image/svg+xml", "description": "2D plan of a level id."],
    ]

    static func json(_ o: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    public static func summary(_ doc: ArchiDocument) -> [String: Any] {
        var byType: [String: Int] = [:], byElement: [String: Int] = [:]
        for e in doc.entities { byType[e.typeName, default: 0] += 1 }
        for e in doc.elements { byElement[e.typeName, default: 0] += 1 }
        let b = GeometryOps.bounds(of: doc)
        return ["name": doc.info.name, "number": doc.info.number, "author": doc.info.author, "units": doc.units.rawValue,
                "latitude": doc.info.latitude, "longitude": doc.info.longitude, "layers": doc.layers.count, "levels": doc.levels.count,
                "entities": byType, "elements": byElement, "markups": Markups.list(doc).count,
                "bounds": b.isEmpty ? NSNull() : ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]] as Any]
    }

    public static func read(_ uri: String, doc: ArchiDocument) throws -> Content {
        func c(_ mime: String, _ text: String) -> Content { Content(uri: uri, mimeType: mime, text: text) }
        let path = uri.hasPrefix("archi://") ? String(uri.dropFirst(8)) : uri
        let parts = path.split(separator: "/").map(String.init)
        switch parts.first ?? "" {
        case "document":
            if parts.count > 1 && parts[1] == "summary" { return c("application/json", json(summary(doc))) }
            return c("application/json", String(decoding: try ArchiFile.encode(doc), as: UTF8.self))
        case "takeoff":
            if parts.count > 1 && parts[1] == "phases" { return c("text/csv", PhaseLevelTakeoff.compute(doc).csv) }
            return c("text/csv", QuantityTakeoff.compute(doc).csv)
        case "schedules":
            let k = parts.count > 1 ? parts[1].lowercased() : "all"
            guard ScheduleExporter.kinds.contains(k) else { throw AgentTools.ToolError(message: "unknown schedule \(k)") }
            return c("text/csv", ScheduleExporter.csv(doc: doc, kind: k))
        case "markups":
            return c("application/json", json(Markups.list(doc).map(AgentExtraTools.markupJSON)))
        case "levels":
            return c("application/json", json(doc.levels.map { ["id": $0.id, "name": $0.name, "elevation": $0.elevation, "height": $0.height] }))
        case "layers":
            return c("application/json", json(doc.layers.map { ["name": $0.name, "color": $0.color.hex, "linetype": $0.linetype, "lineweight": $0.lineweight,
                                                                  "visible": $0.visible, "frozen": $0.frozen, "locked": $0.locked] }))
        case "element":
            guard parts.count > 1, let id = Int(parts[1]) else { throw AgentTools.ToolError(message: "archi://element/{id} needs a numeric id") }
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let el = doc.element(id) { return c("application/json", String(decoding: try enc.encode(el), as: UTF8.self)) }
            if let e = doc.entity(id) { return c("application/json", String(decoding: try enc.encode(e), as: UTF8.self)) }
            throw AgentTools.ToolError(message: "no element or entity #\(id)")
        case "plan":
            let lv = parts.count > 1 ? Int(parts[1]) ?? doc.currentLevel : doc.currentLevel
            guard doc.level(lv) != nil else { throw AgentTools.ToolError(message: "no level \(lv)") }
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: lv))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            let ppu = 1200 / max(b.width, b.height, 1e-9)
            return c("image/svg+xml", SVGExporter.exportLayered(doc: doc, entries: entries, bounds: b.expanded(by: max(b.width, b.height) * 0.02), background: .white, pixelsPerUnit: ppu))
        default:
            throw AgentTools.ToolError(message: "unknown resource \(uri)")
        }
    }
}

// MARK: - Prompts

public enum AgentPrompts {
    public static let definitions: [[String: Any]] = [
        ["name": "review_model", "title": "Review the model",
         "description": "Audit the open model: modelling errors, code rules, accessibility, egress distances and open markups, with a prioritised fix list.",
         "arguments": [["name": "focus", "description": "Optional focus, e.g. 'bathrooms' or 'level 1'", "required": false]]],
        ["name": "quantity_report", "title": "Quantity and cost report",
         "description": "Bill of quantities with unit rates for the model, grouped by trade, with totals.",
         "arguments": [["name": "currency", "description": "Currency code (EUR, RON, USD…)", "required": false],
                       ["name": "vat", "description": "VAT percent", "required": false]]],
        ["name": "energy_advice", "title": "Energy advice",
         "description": "Energy balance of the envelope (losses, solar gains per orientation) with improvement suggestions.",
         "arguments": [["name": "target", "description": "Target heating need in kWh/m²a", "required": false]]],
        ["name": "draw_room", "title": "Draw a room",
         "description": "Draw a rectangular room with walls, a door, a window and a room tag using commands.",
         "arguments": [["name": "name", "description": "Room name", "required": true], ["name": "width", "description": "Width (mm)", "required": true],
                       ["name": "depth", "description": "Depth (mm)", "required": true], ["name": "origin", "description": "Lower-left corner x,y (mm)", "required": false]]],
        ["name": "resolve_markups", "title": "Work through markups",
         "description": "Go through the open review markups, fix what they ask and resolve them.", "arguments": [[String: Any]]()],
    ]

    public static func get(_ name: String, arguments a: [String: String], doc: ArchiDocument) throws -> [String: Any] {
        func msg(_ text: String) -> [String: Any] { ["role": "user", "content": ["type": "text", "text": text]] }
        let s = AgentResources.summary(doc)
        let context = "Model: \(doc.info.name) (\(doc.units.rawValue)), \(doc.elements.count) BIM elements, \(doc.entities.count) entities, \(doc.levels.count) levels. Summary: \(AgentResources.json(s))"
        switch name {
        case "review_model":
            let focus = a["focus"].map { " Focus on: \($0)." } ?? ""
            let checks = ModelChecker.check(doc).prefix(20).map { "- " + $0.description }.joined(separator: "\n")
            return ["description": "Review the model", "messages": [msg("""
            Review this building model as an architect preparing for a permit submission.\(focus)
            Use the tools check_model, code_check, accessibility and egress (per level), and read archi://markups for open comments.
            For each problem give the element ids, why it matters and the concrete fix (commands or property changes); order by severity.
            \(context)
            Current model checker findings:
            \(checks.isEmpty ? "(none)" : checks)
            """)]]
        case "quantity_report":
            let cur = a["currency"] ?? doc.variable("COSTCURRENCY") ?? "EUR"
            let t = QuantityTakeoff.compute(doc)
            return ["description": "Quantity and cost report", "messages": [msg("""
            Prepare a bill of quantities in \(cur)\(a["vat"].map { " with \($0) % VAT" } ?? "").
            Call bill_of_quantities with unit rates you propose for each takeoff line below (state them as assumptions), then present the bill by trade with subtotals and the grand total.
            \(context)
            Takeoff:
            \(t.report)
            """)]]
        case "energy_advice":
            let eb = EnergyBalance.compute(doc, options: EnergyBalanceOptions.from(doc))
            let target = a["target"].flatMap(Double.init)
            return ["description": "Energy advice", "messages": [msg("""
            Assess the heating energy balance of this design\(target.map { " against a target of \(fmt($0, 0)) kWh/m²a" } ?? "").
            Explain which envelope parts dominate the losses (use u_values and heat_loss), how the solar gains per orientation help, and list the three most effective improvements with estimated savings.
            \(context)
            Energy balance:
            \(eb.report)
            """)]]
        case "draw_room":
            guard let n = a["name"], let w = a["width"].flatMap(Double.init), let d = a["depth"].flatMap(Double.init), w > 0, d > 0 else {
                throw AgentTools.ToolError(message: "draw_room needs name, width and depth (mm)")
            }
            let o = (a["origin"] ?? "0,0").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let x = o.count > 0 ? o[0] : 0, y = o.count > 1 ? o[1] : 0
            return ["description": "Draw a room", "messages": [msg("""
            Draw a room named "\(n)" of \(fmt(w, 0)) × \(fmt(d, 0)) mm with its lower-left inner corner at \(fmt(x, 0)),\(fmt(y, 0)).
            Use run_command: WALL for the four walls (closed), DOOR and WINDOW in suitable walls, then ROOM inside to create and tag the space. Check the result with list_elements and fix anything missing.
            \(context)
            """)]]
        case "resolve_markups":
            let open = Markups.list(doc).filter { !$0.isResolved }
            let list = open.map { "- [\($0.id.prefix(8))] \($0.author): \($0.title.isEmpty ? "" : $0.title + " — ")\($0.comment) (elements \($0.elements.map(String.init).joined(separator: ", ")))" }.joined(separator: "\n")
            return ["description": "Work through markups", "messages": [msg("""
            Work through the open review markups one by one: inspect the linked elements, make the change requested, then resolve the markup with markup_update (status resolved, with a reply explaining the change).
            \(context)
            Open markups:
            \(list.isEmpty ? "(none)" : list)
            """)]]
        default:
            throw AgentTools.ToolError(message: "unknown prompt \(name)")
        }
    }
}

// MARK: - More tools

public enum AgentExtraTools {
    static func schema(_ props: [String: Any], required: [String] = []) -> [String: Any] { AgentTools.schema(props, required: required) }
    static let levelProp: [String: Any] = ["type": "integer", "description": "Level id (default: current level)"]
    static let formatProp: [String: Any] = ["type": "string", "enum": ["json", "csv"]]

    /// Read-only analysis tools.
    public static let definitions: [[String: Any]] = [
        ["name": "egress", "title": "Egress distances",
         "description": "Longest walking distance from every room to the nearest exit (doors in exterior walls or marked exit=1, stairs on upper levels) on a grid around walls and columns, against the limit (EGRESSMAX, default 45 m). Returns the route from the farthest point.",
         "inputSchema": schema(["level": levelProp, "maxDistance": ["type": "number"], "format": formatProp])],
        ["name": "accessibility", "title": "Accessibility check",
         "description": "Door clear widths (default ≥ 850 mm) and wheelchair turning circles (default Ø1500 mm) in bathrooms, clear of fixtures.",
         "inputSchema": schema(["level": ["type": "integer"], "minDoorWidth": ["type": "number"], "turningDiameter": ["type": "number"]])],
        ["name": "energy_balance", "title": "Energy balance",
         "description": "Seasonal heating need (EN ISO 13790): transmission and ventilation losses from degree days (latitude table or HDD), solar gains per window orientation, internal gains, utilisation factor.",
         "inputSchema": schema(["hdd": ["type": "number"], "heatingDays": ["type": "number"], "format": formatProp])],
        ["name": "bill_of_quantities", "title": "Bill of quantities",
         "description": "Priced bill of quantities grouped by trade with numbered items, subtotals, contingency and VAT. Rates as for cost_estimate (`prices` object, `path` JSON, or COST: variables).",
         "inputSchema": schema(["prices": ["type": "object"], "path": ["type": "string"], "currency": ["type": "string"], "vat": ["type": "number"], "contingency": ["type": "number"], "format": formatProp])],
        ["name": "takeoff_by_phase", "title": "Takeoff by phase and level",
         "description": "Quantities per construction phase (new work and demolition) and level.", "inputSchema": schema(["format": formatProp])],
        ["name": "compare", "title": "Compare with another version",
         "description": "Differences between another .archi/.dxf/.ifc file (`path`, the older version) and the open document: added, removed, modified objects by id and geometry. `overlayPath` writes a colour-coded overlay .archi.",
         "inputSchema": schema(["path": ["type": "string"], "overlayPath": ["type": "string"], "format": formatProp], required: ["path"])],
        ["name": "markups", "title": "List markups", "description": "Review markups (comments) with status, author, date, linked elements and view.",
         "inputSchema": schema(["status": ["type": "string", "enum": ["open", "resolved", "all"]]])],
        ["name": "validate_exchange", "title": "Validate gbXML/COBie",
         "description": "Checks the model's gbXML or COBie export (or a file `path`) against the schema's required elements, enumerations and references.",
         "inputSchema": schema(["format": ["type": "string", "enum": ["gbxml", "cobie"]], "path": ["type": "string"]], required: ["format"])],
        ["name": "daylight_annual", "title": "Climate-based daylight (sDA/ASE)",
         "description": "Spatial daylight autonomy sDA300/50% and annual sunlight exposure ASE1000,250h (IES LM-83) of every room from an EPW weather file (`epwPath`) or a clear-sky year at the project location.",
         "inputSchema": schema(["epwPath": ["type": "string"], "gridSpacing": ["type": "number", "description": "mm, default 600"], "format": formatProp])],
        ["name": "generative_design", "title": "Generative layout design",
         "description": "Optimises floor layouts for a room programme (`program`: \"Living 25, Kitchen 12, …\" in m²) and gross area with a genetic algorithm: daylight, proportions, required adjacencies (`adjacent`: \"Kitchen-Living, …\"), orientation (`facing`: \"Living:S\"), compactness. Returns the Pareto-optimal designs (rooms with rectangles); build one with the GENDESIGN command.",
         "inputSchema": schema(["program": ["type": "string"], "adjacent": ["type": "string"], "facing": ["type": "string"], "area": ["type": "number", "description": "m²"],
                                "seed": ["type": "integer"], "generations": ["type": "integer"], "limit": ["type": "integer"]], required: ["program"])],
        ["name": "wind_case", "title": "Wind study case (OpenFOAM)",
         "description": "Writes an OpenFOAM simpleFoam wind-study case for the model into the folder `path` (wind `speed` m/s at 10 m, `direction` it comes from in degrees, terrain `roughness` z0 m).",
         "inputSchema": schema(["path": ["type": "string"], "speed": ["type": "number"], "direction": ["type": "number"], "roughness": ["type": "number"]], required: ["path"])],
        ["name": "file_check", "title": "Save round-trip check",
         "description": "Whether saving and reopening the document gives an identical model; lists any section that would change, plus the file-format version.",
         "inputSchema": schema([:])],
    ]

    /// Tools that change the document (run inside an undoable transaction by the server).
    public static let mutatingDefinitions: [[String: Any]] = [
        ["name": "markup_add", "title": "Add markup",
         "description": "Adds a review markup: a cloud around `min`–`max` (drawing units) with a comment, optional title, linked element ids and author.",
         "inputSchema": schema(["comment": ["type": "string"], "title": ["type": "string"], "min": ["type": "array", "items": ["type": "number"]], "max": ["type": "array", "items": ["type": "number"]],
                                "elements": ["type": "array", "items": ["type": "integer"]], "author": ["type": "string"]], required: ["comment"])],
        ["name": "markup_update", "title": "Update markup",
         "description": "Resolves or reopens a markup (`status`), adds a `reply`, or deletes it (`delete`: true). `id` is the markup id (or its number in the list).",
         "inputSchema": schema(["id": ["type": "string"], "status": ["type": "string", "enum": ["open", "resolved"]], "reply": ["type": "string"], "author": ["type": "string"], "delete": ["type": "boolean"]], required: ["id"])],
        ["name": "bcf_import", "title": "Import BCF", "description": "Imports the topics of a BCF 2.x .bcfzip as markups (camera, selection by IFC GlobalId, comments).",
         "inputSchema": schema(["path": ["type": "string"]], required: ["path"])],
    ]

    public static var names: Set<String> { Set(definitions.compactMap { $0["name"] as? String }) }
    public static var mutatingNames: Set<String> { Set(mutatingDefinitions.compactMap { $0["name"] as? String }) }

    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }
    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
    static func r(_ v: Double, _ d: Int = 3) -> Double { Double(fmt(v, d)) ?? v }
    static func pt(_ p: Vec2) -> [Double] { [r(p.x, 1), r(p.y, 1)] }

    public static func markupJSON(_ m: Markup) -> [String: Any] {
        var o: [String: Any] = ["id": m.id, "status": m.status, "author": m.author, "date": m.date, "title": m.title, "comment": m.comment,
                                "elements": m.elements, "view": ["center": pt(m.viewCenter), "height": r(m.viewHeight, 1)],
                                "replies": m.replies.map { ["author": $0.author, "date": $0.date, "text": $0.text] }, "entities": m.entityIDs]
        if let c = m.camera { o["camera"] = ["eye": [c.eye.x, c.eye.y, c.eye.z], "target": [c.target.x, c.target.y, c.target.z], "fov": c.fov, "orthographic": c.orthographic] }
        return o
    }

    public static func call(_ name: String, _ a: [String: Any], doc: ArchiDocument, resolve: (String) -> URL) throws -> Any {
        let csv = (a["format"] as? String) == "csv"
        switch name {
        case "egress":
            var o = EgressOptions.from(doc)
            if let v = num(a["maxDistance"]) { o.maxDistance = v }
            let res = EgressAnalysis.compute(doc, level: int(a["level"]) ?? doc.currentLevel, options: o)
            if csv { return CSVText.make(res.table) }
            return ["maxDistance_m": o.maxDistance, "exits": res.exits, "cell": res.cell, "failures": res.failures.count,
                    "rooms": res.rows.map { ["id": $0.id, "number": $0.number, "name": $0.name, "distance_m": $0.distance.map { r($0, 2) as Any } ?? NSNull(),
                                           "ok": $0.ok, "farthest": pt($0.farthest), "route": $0.path.map(pt)] }]
        case "accessibility":
            var o = AccessibilityOptions.from(doc)
            if let v = num(a["minDoorWidth"]) { o.minDoorClear = v }
            if let v = num(a["turningDiameter"]) { o.turningDiameter = v }
            let res = Accessibility.check(doc, level: int(a["level"]), options: o)
            return ["count": res.issues.count, "issues": res.issues.map(AgentTools.issueJSON),
                    "bathrooms": res.turning.map { ["id": $0.id, "name": $0.name, "turningDiameter_mm": r($0.diameter, 0), "center": pt($0.center), "ok": $0.ok] }]
        case "energy_balance":
            var cl = ClimateData.from(doc)
            if let v = num(a["hdd"]) { cl.degreeDays = v; cl.source = "argument" }
            if let v = num(a["heatingDays"]) { cl.heatingDays = v }
            let eb = EnergyBalance.compute(doc, climate: cl, options: EnergyBalanceOptions.from(doc))
            if csv { return CSVText.make(eb.table) }
            return ["degreeDays": cl.degreeDays, "heatingDays": cl.heatingDays, "climateSource": cl.source, "losses_kWh": r(eb.losses, 0),
                    "solarGains_kWh": r(eb.solarGains, 0), "internalGains_kWh": r(eb.internalGains, 0), "utilisation": r(eb.utilisation),
                    "heatingNeed_kWh": r(eb.heatingNeed, 0), "specificNeed_kWh_m2": r(eb.specificNeed, 1), "floorArea_m2": r(eb.floorArea, 2),
                    "solarByOrientation": eb.solarRows.map { ["orientation": $0.orientation, "area_m2": r($0.area, 2), "irradiation_kWh_m2": r($0.irradiation, 1), "gain_kWh": r($0.gain, 0), "windows": $0.windows] }]
        case "bill_of_quantities":
            var table = CostTable.fromVariables(doc)
            if let pr = a["prices"] as? [String: Any] { table = try CostTable.fromJSON(String(decoding: try JSONSerialization.data(withJSONObject: pr), as: UTF8.self)) }
            else if let p = a["path"] as? String { table = try CostTable.fromJSON(try FileImport.readText(resolve(p))) }
            guard !table.prices.isEmpty else { throw AgentTools.ToolError(message: "no unit rates: pass 'prices' or 'path', or set COST:<category>:<measure> variables") }
            var o = BoQOptions.from(doc)
            if let v = num(a["vat"]) { o.vat = v }
            if let v = num(a["contingency"]) { o.contingency = v }
            if let c = a["currency"] as? String { o.currency = c }
            let boq = BillOfQuantities.build(QuantityTakeoff.compute(doc), table: table, options: o)
            if csv { return boq.csv }
            return ["currency": boq.currency, "net": boq.net, "contingency": boq.contingency, "vat": boq.vat, "total": boq.total,
                    "sections": boq.sections.map { s in ["number": s.number, "title": s.title, "subtotal": s.subtotal,
                                                         "items": s.items.map { ["ref": $0.ref, "description": $0.description, "unit": $0.unit, "quantity": $0.quantity, "rate": $0.rate, "amount": $0.amount] }] as [String: Any] },
                    "unpriced": boq.unpriced.map { "\($0.category) \($0.key)" }]
        case "takeoff_by_phase":
            let t = PhaseLevelTakeoff.compute(doc)
            if csv { return t.csv }
            return ["groups": t.groups.map { g in ["phase": g.phase, "work": g.work, "level": g.level, "levelName": g.levelName,
                                                   "lines": g.lines.map { ["category": $0.category, "type": $0.key, "material": $0.material, "count": $0.count, "length_m": r($0.length), "area_m2": r($0.area), "volume_m3": r($0.volume)] }] as [String: Any] }]
        case "compare":
            guard let p = a["path"] as? String else { throw AgentTools.ToolError(message: "missing 'path'") }
            let (old, _) = try FileImport.load(resolve(p))
            let d = DocumentCompare.compare(old, doc)
            if let op = a["overlayPath"] as? String { try ArchiFile.encode(DocumentCompare.overlay(old, doc, diff: d)).write(to: resolve(op), options: .atomic) }
            if csv { return d.csv }
            return ["added": d.count(.added), "removed": d.count(.removed), "modified": d.count(.modified), "unchanged": d.count(.unchanged),
                    "layersAdded": d.layersAdded, "layersRemoved": d.layersRemoved, "levelsAdded": d.levelsAdded, "levelsRemoved": d.levelsRemoved,
                    "changes": d.differences.prefix(2000).map { ["change": $0.kind.rawValue, "object": $0.object, "type": $0.type, "id": $0.id, "oldId": $0.oldID as Any? ?? NSNull(), "fields": $0.fields, "layer": $0.layer] }]
        case "daylight_annual":
            let climate: HourlyClimate
            if let p = a["epwPath"] as? String { climate = try HourlyClimate.parseEPW(FileImport.readText(resolve(p))) }
            else { climate = HourlyClimate.clearSky(latitude: doc.info.latitude, longitude: doc.info.longitude, timeZone: Double(doc.variable("UTCOFFSET") ?? "") ?? (doc.info.longitude / 15).rounded()) }
            var o = ClimateDaylight.Options()
            if let g = num(a["gridSpacing"]), g > 50 { o.gridSpacing = g }
            let rows = ClimateDaylight.json(ClimateDaylight.analyse(doc, climate: climate, options: o))
            if csv { return CSVText.make([["id", "room", "level", "sDA300_50", "ASE1000_250", "meanAutonomy", "points", "passesLM83"]] + rows.map { r in ["id", "room", "level", "sDA300_50", "ASE1000_250", "meanAutonomy", "points", "passesLM83"].map { "\(r[$0] ?? "")" } }) }
            return ["climate": climate.city, "latitude": climate.latitude, "longitude": climate.longitude, "rooms": rows]
        case "generative_design":
            guard let prog = a["program"] as? String else { throw AgentTools.ToolError(message: "missing 'program'") }
            let rooms = PlanGenerator.parseBrief(prog)
            guard !rooms.isEmpty else { throw AgentTools.ToolError(message: "no rooms in 'program'") }
            var o = GenerativeDesign.Options()
            o.northAngle = doc.info.northAngle
            if let sd = int(a["seed"]), sd > 0 { o.seed = UInt64(sd) }
            if let g = int(a["generations"]), g > 0 { o.generations = min(g, 500) }
            let u = doc.units.mm
            let area = (num(a["area"]) ?? rooms.reduce(0) { $0 + $1.area }) * 1_000_000 / (u * u)
            let ds = GenerativeDesign.run(GenerativeDesign.Brief(rooms: rooms, adjacent: GenerativeDesign.parseAdjacency(a["adjacent"] as? String ?? ""),
                                                                 facing: GenerativeDesign.parseFacing(a["facing"] as? String ?? "")), area: area, unitMM: u, options: o)
            return ["designs": ds.prefix(int(a["limit"]) ?? 5).map { d in
                ["score": r(d.score, 4), "width_m": r(d.width * u / 1000, 3), "depth_m": r(d.depth * u / 1000, 3),
                 "objectives": ["noDaylight": d.objectives.daylight, "proportion": r(d.objectives.proportion, 3), "adjacencyMisses": d.objectives.adjacency,
                                "orientationMisses": d.objectives.orientation, "compactness": r(d.objectives.compactness, 4)],
                 "rooms": d.option.rooms.map { ["name": $0.name, "min": pt($0.rect.min), "max": pt($0.rect.max), "area_m2": r($0.area * u * u / 1_000_000, 2)] }] as [String: Any]
            }]
        case "wind_case":
            guard let p = a["path"] as? String else { throw AgentTools.ToolError(message: "missing 'path'") }
            var o = WindStudy.Options.from(doc)
            if let v = num(a["speed"]) { o.speed = v }
            if let v = num(a["direction"]) { o.direction = v }
            if let v = num(a["roughness"]) { o.roughness = v }
            let files = try WindStudy.writeCase(doc, to: resolve(p), options: o)
            return ["folder": resolve(p).path, "files": files]
        case "file_check":
            let diffs = try ArchiFile.roundTripDifferences(doc)
            return ["lossless": diffs.isEmpty, "changedSections": diffs, "formatVersion": ArchiDocument.currentFormatVersion]
        case "markups":
            let st = (a["status"] as? String) ?? "all"
            return ["markups": Markups.list(doc).filter { st == "all" || $0.status == st }.map(markupJSON)]
        case "validate_exchange":
            let format = (a["format"] as? String ?? "").lowercased()
            let issues: [ExchangeIssue]
            if format == "gbxml" {
                let text = try (a["path"] as? String).map { try FileImport.readText(resolve($0)) } ?? GBXMLExporter.export(doc)
                issues = GBXMLValidator.validate(text)
            } else if format == "cobie" {
                let data = try (a["path"] as? String).map { try Data(contentsOf: resolve($0)) } ?? COBieExporter.export(doc)
                issues = COBieValidator.validate(try XLSX.read(data))
            } else { throw AgentTools.ToolError(message: "format must be gbxml or cobie") }
            return ["valid": issues.isEmpty, "count": issues.count, "issues": issues.prefix(500).map { ["code": $0.code, "message": $0.message] }]
        default:
            throw AgentTools.ToolError(message: "unknown tool \(name)")
        }
    }

    /// Document-changing tools; the caller wraps this in an undoable transaction.
    public static func mutate(_ name: String, _ a: [String: Any], doc: inout ArchiDocument, resolve: (String) -> URL) throws -> Any {
        switch name {
        case "markup_add":
            guard let comment = a["comment"] as? String, !comment.isEmpty else { throw AgentTools.ToolError(message: "missing 'comment'") }
            let ids = (a["elements"] as? [Any])?.compactMap(int) ?? []
            func v(_ x: Any?) -> Vec2? { guard let l = x as? [Any], l.count >= 2, let a = num(l[0]), let b = num(l[1]) else { return nil }; return Vec2(a, b) }
            var lo = v(a["min"]), hi = v(a["max"])
            if lo == nil || hi == nil {
                var b = BBox2.empty
                for id in ids { if let el = doc.element(id) { b.add(PlanRepresentation.bounds(el, doc: doc)) } else if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) } }
                if b.isEmpty { b = GeometryOps.bounds(of: doc) }
                if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
                let pad = max(b.width, b.height, 1) * 0.1
                lo = b.min - Vec2(pad, pad); hi = b.max + Vec2(pad, pad)
            }
            let level = ids.compactMap { doc.element($0)?.level }.first
            let id = Markups.add(&doc, rect: (lo!, hi!), title: a["title"] as? String ?? "", comment: comment, author: a["author"] as? String, elements: ids, level: level)
            return markupJSON(Markups.find(doc, id)!)
        case "markup_update":
            guard let key = a["id"] as? String ?? int(a["id"]).map(String.init), let m = Markups.find(doc, key) else { throw AgentTools.ToolError(message: "no markup \(a["id"] ?? "")") }
            if (a["delete"] as? Bool) == true { Markups.remove(&doc, m.id); return ["deleted": m.id] }
            if let r = a["reply"] as? String, !r.isEmpty { Markups.reply(&doc, m.id, text: r, author: a["author"] as? String) }
            if let s = a["status"] as? String { Markups.setStatus(&doc, m.id, resolved: s == "resolved", by: a["author"] as? String) }
            return markupJSON(Markups.find(doc, m.id)!)
        case "bcf_import":
            guard let p = a["path"] as? String else { throw AgentTools.ToolError(message: "missing 'path'") }
            let topics = try BCF.read(try Data(contentsOf: resolve(p)))
            let ids = BCF.importTopics(topics, into: &doc)
            return ["imported": ids.count, "markups": ids]
        default:
            throw AgentTools.ToolError(message: "unknown tool \(name)")
        }
    }
}

// MARK: - Batch jobs

/// Batch job file (archi-cli --batch jobs.json):
/// {"stopOnError": false, "jobs": [{"name": "a", "input": "a.archi", "import": ["survey.dxf"], "commands": ["WALL 0,0 5000,0 "],
///   "script": "setup.scr", "outputs": ["a.dxf", {"path": "a.ifc", "format": "ifc", "level": 0}], "reports": [{"tool": "takeoff", "path": "q.json"}],
///   "save": "a-out.archi"}]}. Relative paths are resolved against the job file's folder.
public struct BatchJob: Hashable {
    public struct Output: Hashable { public var path: String; public var format: String?; public var level: Int? }
    public struct Report: Hashable { public var tool: String; public var path: String; public var arguments: [String: String] }
    public var name: String
    public var input: String?
    public var imports: [String]
    public var commands: [String]
    public var script: String?
    public var outputs: [Output]
    public var reports: [Report]
    public var save: String?

    public static func parse(_ data: Data) throws -> (jobs: [BatchJob], stopOnError: Bool) {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw AgentTools.ToolError(message: "batch file is not JSON") }
        let obj = root as? [String: Any] ?? ["jobs": root]
        guard let list = obj["jobs"] as? [Any] else { throw AgentTools.ToolError(message: "batch file needs a \"jobs\" array") }
        var jobs: [BatchJob] = []
        for (i, item) in list.enumerated() {
            guard let j = item as? [String: Any] else { throw AgentTools.ToolError(message: "job \(i + 1) is not an object") }
            func strings(_ k: String) -> [String] { (j[k] as? [Any])?.compactMap { $0 as? String } ?? (j[k] as? String).map { [$0] } ?? [] }
            var outs: [Output] = []
            for o in (j["outputs"] as? [Any]) ?? (j["output"].map { [$0] } ?? []) {
                if let s = o as? String { outs.append(Output(path: s, format: nil, level: nil)) }
                else if let d = o as? [String: Any], let p = d["path"] as? String { outs.append(Output(path: p, format: d["format"] as? String, level: int(d["level"]))) }
                else { throw AgentTools.ToolError(message: "job \(i + 1): each output is a path or {path, format, level}") }
            }
            var reps: [Report] = []
            for r in (j["reports"] as? [Any]) ?? [] {
                guard let d = r as? [String: Any], let t = d["tool"] as? String, let p = d["path"] as? String else { throw AgentTools.ToolError(message: "job \(i + 1): each report needs tool and path") }
                guard AgentTools.names.contains(t) || AgentExtraTools.names.contains(t) || ["takeoff", "check_model", "room_schedule"].contains(t) else {
                    throw AgentTools.ToolError(message: "job \(i + 1): unknown report tool \(t)")
                }
                var args: [String: String] = [:]
                for (k, v) in (d["arguments"] as? [String: Any]) ?? [:] { args[k] = "\(v)" }
                reps.append(Report(tool: t, path: p, arguments: args))
            }
            let job = BatchJob(name: j["name"] as? String ?? "job \(i + 1)", input: j["input"] as? String, imports: strings("import"), commands: strings("commands"),
                               script: j["script"] as? String, outputs: outs, reports: reps, save: j["save"] as? String)
            if job.input == nil && job.imports.isEmpty && job.commands.isEmpty && job.script == nil {
                throw AgentTools.ToolError(message: "job \(i + 1) has nothing to do (input, import, commands or script)")
            }
            jobs.append(job)
        }
        return (jobs, obj["stopOnError"] as? Bool ?? false)
    }

    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }

    /// Script lines of the job's .scr file (';' comments skipped).
    public static func scriptLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix(";") }
    }
}
