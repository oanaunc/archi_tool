// Oanarina Archi Tool — GPL-3.0-or-later
// The archi-cli MCP tools that `archi-engine --mcp` lacked: run_batch (BatchRunner), cost_estimate (CostTable /
// CostEstimate), clash (ClashDetector) and sun_position (SolarCalculator), with the same names, schemas and results as
// app/Sources/archi-cli/main.swift, so Claude Desktop and Claude Code get the same tools on Windows and Linux.
import Foundation

extension EngineMCPServer {
    static func extraTools() -> [EngineJSON] {
        var t: [EngineJSON] = []
        let jobsProp = ScriptJSON.object([("type", .string("array")), ("items", prop("object"))])
        t.append(tool("run_batch", "Run batch jobs",
                      "Runs batch jobs headless (each on its own document): open or import files, run command lines or a .scr script, write outputs in any export format, write tool reports (JSON/CSV) and save. Pass `path` to a jobs JSON file or `jobs` inline: [{\"input\":\"a.archi\",\"commands\":[\"WALL 0,0 5000,0 \"],\"outputs\":[\"a.dxf\",{\"path\":\"a.ifc\"}],\"reports\":[{\"tool\":\"takeoff\",\"path\":\"q.csv\",\"arguments\":{\"format\":\"csv\"}}],\"save\":\"out.archi\"}]. The open document is not changed.",
                      schema([("path", prop("string")), ("jobs", jobsProp), ("stopOnError", prop("boolean"))])))
        t.append(tool("cost_estimate", "Cost estimate",
                      "Cost of the takeoff from unit rates: `prices` (object like {\"currency\":\"EUR\",\"wall:area\":45,\"door:count\":350} or {\"prices\":[{category,type,measure,price}]}), a JSON file `path`, or the drawing's COST:<category>[:<type>]:<measure> variables.",
                      schema([("prices", prop("object")), ("path", prop("string")), ("format", enumProp(formatJSONCSV))])))
        t.append(tool("clash", "Clash detection",
                      "Hard clashes between BIM elements and 3D solids (mesh bounding boxes then triangle-triangle tests; touching, hosted and joined elements ignored). Optional `ids` limits one side of each pair.",
                      schema([("tolerance", prop("number")), ("ids", intArray()), ("includeSpaces", prop("boolean"))])))
        t.append(tool("sun_position", "Sun position",
                      "Sun azimuth (clockwise from north) and altitude, sunrise/sunset for an ISO date-time (e.g. 2025-06-21T14:30:00+03:00) at the project location or given latitude/longitude.",
                      schema([("datetime", prop("string")), ("latitude", prop("number")), ("longitude", prop("number"))], required: ["datetime"])))
        return t
    }

    static let extraToolNames: Set<String> = ["run_batch", "cost_estimate", "clash", "sun_position"]

    func resolvePath(_ p: String) -> URL { session.url(p) }

    /// Runs one of the extra tools; nil for other names.
    func callExtraTool(_ name: String, _ a: EngineJSON) async throws -> EngineJSON? {
        let doc = session.editor.doc
        switch name {
        case "cost_estimate": return try costEstimate(a, doc: doc)
        case "clash": return clash(a, doc: doc)
        case "sun_position": return try sunPosition(a, doc: doc)
        case "run_batch": return try await runBatch(a)
        default: return nil
        }
    }

    func costEstimate(_ a: EngineJSON, doc: ArchiDocument) throws -> EngineJSON {
        var table = CostTable.fromVariables(doc)
        if let pr = a["prices"], pr.fields != nil {
            table = try CostTable.fromJSON(pr.serialized)
        } else if let p = a["path"]?.stringValue {
            table = try CostTable.fromJSON(try FileImport.readText(resolvePath(p)))
        }
        guard !table.prices.isEmpty else { throw EngineError.failed("no unit rates: pass 'prices' or 'path', or set COST:<category>:<measure> variables") }
        let est = CostEstimate.compute(QuantityTakeoff.compute(doc), table: table)
        if a["format"]?.stringValue == "csv" { return .string(est.csv) }
        var lines: [EngineJSON] = []
        for l in est.lines {
            var o = EngineObject()
            o.set("category", l.line.category)
            o.set("type", EngineJSON.optString(l.line.key))
            o.set("measure", l.measure)
            o.set("quantity", l.quantity)
            o.set("unitPrice", l.unitPrice)
            o.set("total", l.total)
            lines.append(o.json)
        }
        var unpriced: [EngineJSON] = []
        for l in est.unpriced { unpriced.append(ScriptJSON.object([("category", .string(l.category)), ("type", EngineJSON.optString(l.key))])) }
        var o = EngineObject()
        o.set("currency", est.currency)
        o.set("total", est.total)
        o.set("lines", EngineJSON.array(lines))
        o.set("unpriced", EngineJSON.array(unpriced))
        return o.json
    }

    func clash(_ a: EngineJSON, doc: ArchiDocument) -> EngineJSON {
        var opts = ClashOptions()
        if let t = ScriptJSON.double(a["tolerance"]) { opts.tolerance = t }
        let ids = ScriptJSON.ids(a["ids"])
        if !ids.isEmpty { opts.setA = Set(ids) }
        if let s = ScriptJSON.bool(a["includeSpaces"]) { opts.includeSpaces = s }
        let cs = ClashDetector.detect(doc, options: opts)
        var out: [EngineJSON] = []
        for c in cs {
            var o = EngineObject()
            o.set("a", c.a)
            o.set("kindA", c.kindA)
            o.set("b", c.b)
            o.set("kindB", c.kindB)
            o.set("point", EngineJSON.point3(c.point))
            o.set("contained", c.contained)
            o.set("min", EngineJSON.point3(c.bounds.min))
            o.set("max", EngineJSON.point3(c.bounds.max))
            out.append(o.json)
        }
        return ScriptJSON.object([("count", .int(cs.count)), ("clashes", .array(out))])
    }

    static func isoDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: s)
    }

    func sunPosition(_ a: EngineJSON, doc: ArchiDocument) throws -> EngineJSON {
        guard let s = a["datetime"]?.stringValue else { throw EngineError.params("missing 'datetime'") }
        guard let dt = EngineMCPServer.isoDate(s) else { throw EngineError.params("datetime must be ISO 8601, e.g. 2025-06-21T14:30:00+03:00") }
        let lat = ScriptJSON.double(a["latitude"]) ?? doc.info.latitude
        let lon = ScriptJSON.double(a["longitude"]) ?? doc.info.longitude
        let p = SolarCalculator.position(date: dt, latitude: lat, longitude: lon)
        let t = SolarCalculator.sunTimes(date: dt, latitude: lat, longitude: lon)
        let out = ISO8601DateFormatter()
        let dir = SolarCalculator.direction(p, northAngle: doc.info.northAngle)
        var o = EngineObject()
        o.set("azimuth", p.azimuth)
        o.set("altitude", p.altitude)
        o.set("declination", p.declination)
        o.set("equationOfTime_min", p.equationOfTime)
        o.set("sunriseUTC", EngineJSON.optString(t.sunrise.map { out.string(from: $0) }))
        o.set("solarNoonUTC", out.string(from: t.noon))
        o.set("sunsetUTC", EngineJSON.optString(t.sunset.map { out.string(from: $0) }))
        o.set("direction", EngineJSON.point3(dir))
        o.set("latitude", lat)
        o.set("longitude", lon)
        return o.json
    }

    func runBatch(_ a: EngineJSON) async throws -> EngineJSON {
        var spec: Data
        var base = session.baseDirectory
        if let p = a["path"]?.stringValue {
            let u = resolvePath(p)
            spec = try Data(contentsOf: u)
            base = u.deletingLastPathComponent()
        } else if let jobs = a["jobs"], jobs.arrayValue != nil {
            let stop = a["stopOnError"]?.boolValue ?? false
            spec = Data(ScriptJSON.object([("jobs", jobs), ("stopOnError", .bool(stop))]).serialized.utf8)
        } else {
            throw EngineError.params("pass 'path' or 'jobs'")
        }
        let parsed = try BatchJob.parse(spec)
        let r = await BatchRunner.run(parsed.jobs, stopOnError: parsed.stopOnError, base: base)
        return ScriptJSON.fromAny(r)
    }
}
