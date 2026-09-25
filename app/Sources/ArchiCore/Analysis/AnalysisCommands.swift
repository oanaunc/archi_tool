// Oanarina Archi Tool — GPL-3.0-or-later
// Analysis commands: quantity takeoff, cost estimate, room schedule, sun position, clash detection, model check.
import Foundation

public enum AnalysisCommands {
    public static var all: [CommandDef] { [takeoff, costEstimate, unitPrice, roomSchedule, sunPosition, clashDetect, checkModel] + BuildingAnalysisCommands.all }

    @MainActor static func level(_ ed: Editor) async throws -> Int? {
        let names = ed.doc.levels.map { "\($0.id)=\($0.name)" }.joined(separator: ", ")
        let r = try await ed.getWord("Enter level id (\(names)) or [All/Current]", defaultValue: "All", keywords: ["All", "Current"]) ?? "All"
        if r == "All" { return nil }
        if r == "Current" { return ed.doc.currentLevel }
        guard let i = Int(r), ed.doc.level(i) != nil else { throw CommandError.invalid("No level \(r).") }
        return i
    }

    @MainActor static func saveCSV(_ ed: Editor, _ text: String, prompt: String = "Enter CSV file name to save <none>") async throws {
        guard let p = try await ed.getWord(prompt), !p.isEmpty else { return }
        var url = IOCommands.resolve(ed, p)
        if url.pathExtension.isEmpty { url.appendPathExtension("csv") }
        do { try text.write(to: url, atomically: true, encoding: .utf8); ed.print("Wrote \(url.path).") }
        catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
    }

    /// Lets the user zoom to numbered results (needs the app window; ignored headless).
    @MainActor static func zoomLoop(_ ed: Editor, _ items: [(ids: [EntityID], box: BBox2)]) async throws {
        guard ed.host != nil, !items.isEmpty else { return }
        for _ in 0..<1000 {
            guard let n = try await ed.getInteger("Enter number to zoom to <done>"), n >= 1 else { return }
            guard n <= items.count else { ed.print("Enter 1 to \(items.count)."); continue }
            let it = items[n - 1]
            ed.selection = Set(it.ids)
            if !it.box.isEmpty { ed.host?.perform(.zoomWindow(it.box), editor: ed) }
        }
    }

    static var takeoff: CommandDef {
        CommandDef("TAKEOFF", aliases: ["QTO", "QUANTITIES"], category: "Analysis",
                   summary: "Quantity takeoff: wall areas/volumes (net of openings) per type and material, slabs, roofs, columns, beams, door/window counts; optional CSV.", modifies: false) { ed in
            let lv = try await level(ed)
            let t = QuantityTakeoff.compute(ed.doc, level: lv)
            guard !t.lines.isEmpty else { ed.print("No BIM elements to measure."); return }
            for l in t.report.split(separator: "\n") { ed.print(String(l)) }
            if !t.materials.isEmpty {
                ed.print("Materials: " + t.materials.map { "\($0.material) \(fmt($0.volume, 3)) m³" }.joined(separator: "; "))
            }
            try await saveCSV(ed, t.csv)
        }
    }

    static var costEstimate: CommandDef {
        CommandDef("COSTESTIMATE", aliases: ["COST", "ESTIMATE"], category: "Analysis",
                   summary: "Cost estimate from the takeoff and unit rates (UNITPRICE drawing rates or a JSON table); optional CSV.", modifies: false) { ed in
            let src = try await ed.getWord("Enter unit price JSON file <drawing rates>")
            var table = CostTable.fromVariables(ed.doc)
            if let p = src, !p.isEmpty {
                let url = IOCommands.resolve(ed, p)
                do { table = try CostTable.fromJSON(try FileImport.readText(url)) }
                catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.path)") }
            }
            guard !table.prices.isEmpty else { throw CommandError.invalid("No unit rates: use UNITPRICE or give a JSON price table.") }
            let est = CostEstimate.compute(QuantityTakeoff.compute(ed.doc), table: table)
            for l in est.report.split(separator: "\n") { ed.print(String(l)) }
            try await saveCSV(ed, est.csv)
        }
    }

    static var unitPrice: CommandDef {
        CommandDef("UNITPRICE", aliases: ["COSTRATE", "RATE"], category: "Analysis",
                   summary: "Stores a unit rate in the drawing (COST:<category>[:<type>]:<measure>) used by COSTESTIMATE.") { ed in
            let cats = ["wall", "slab", "roof", "column", "beam", "door", "window", "opening", "stair", "railing", "curtainWall", "component", "space"]
            guard let c = try await ed.getWord("Enter category (\(cats.joined(separator: ", ")))"), !c.isEmpty else { return }
            let type = try await ed.getWord("Enter type (e.g. \"Generic 200 mm\") or <all types>")
            let m = try await ed.getKeyword("Enter measure [Count/Length/Area/Volume]", ["Count", "Length", "Area", "Volume"], defaultValue: "Area") ?? "Area"
            guard case .value(let price) = try await ed.getReal("Enter price per unit") else { throw CommandError.invalid("A price is required.") }
            var key = "COST:\(c)"
            if let t = type, !t.isEmpty { key += ":\(t)" }
            key += ":\(m)"
            ed.doc.setVariable(key, fmt(price, 4))
            if ed.doc.variable("COSTCURRENCY") == nil { ed.doc.setVariable("COSTCURRENCY", "EUR") }
            ed.print("\(key.uppercased()) = \(fmt(price, 4)) \(ed.doc.variable("COSTCURRENCY") ?? "")")
        }
    }

    static var roomSchedule: CommandDef {
        CommandDef("ROOMSCHEDULE", aliases: ["ROOMAREAS", "AREASCHEDULE"], category: "Analysis",
                   summary: "Room area schedule with net (minus columns) and gross (to wall centre lines) areas, perimeter and volume; optional CSV.", modifies: false) { ed in
            let lv = try await level(ed)
            let rows = RoomSchedule.compute(ed.doc, level: lv)
            guard !rows.isEmpty else { ed.print("No rooms."); return }
            for r in rows {
                ed.print("\(r.number.isEmpty ? "-" : r.number) \(r.name) [\(r.level)]: net \(fmt(r.netArea, 2)) m², gross \(fmt(r.grossArea, 2)) m², perimeter \(fmt(r.perimeter, 2)) m")
            }
            ed.print("Total: net \(fmt(rows.reduce(0) { $0 + $1.netArea }, 2)) m², gross \(fmt(rows.reduce(0) { $0 + $1.grossArea }, 2)) m²")
            try await saveCSV(ed, RoomSchedule.csv(rows))
        }
    }

    static var sunPosition: CommandDef {
        CommandDef("SUNPOSITION", aliases: ["SUNPOS", "SUNCALC"], category: "Analysis",
                   summary: "Sun azimuth/altitude, sunrise and sunset for a date, time and the project location; stores SUNAZIMUTH/SUNALTITUDE.") { ed in
            let now = Date()
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
            let c = cal.dateComponents([.year, .month, .day], from: now)
            let today = String(format: "%04d-%02d-%02d", c.year ?? 2025, c.month ?? 6, c.day ?? 21)
            let day = try await ed.getWord("Enter date (YYYY-MM-DD)", defaultValue: ed.doc.variable("SUNDATE") ?? today) ?? today
            let time = try await ed.getWord("Enter local time (HH:MM)", defaultValue: ed.doc.variable("SUNTIME") ?? "12:00") ?? "12:00"
            let defOff = Double(ed.doc.variable("UTCOFFSET") ?? "") ?? Double(TimeZone.current.secondsFromGMT()) / 3600
            let off = try await ed.getReal("Enter UTC offset in hours", defaultValue: defOff).value ?? defOff
            let lat = try await ed.getReal("Enter latitude", defaultValue: ed.doc.info.latitude).value ?? ed.doc.info.latitude
            let lon = try await ed.getReal("Enter longitude (east positive)", defaultValue: ed.doc.info.longitude).value ?? ed.doc.info.longitude
            guard abs(lat) <= 90, abs(lon) <= 180 else { throw CommandError.invalid("Latitude must be within ±90 and longitude within ±180.") }
            guard let date = SolarCalculator.date(day, time, utcOffset: off) else { throw CommandError.invalid("Use a date like 2025-06-21 and a time like 14:30.") }
            let p = SolarCalculator.position(date: date, latitude: lat, longitude: lon)
            let times = SolarCalculator.sunTimes(date: date.addingTimeInterval(off * 3600 - 0), latitude: lat, longitude: lon)
            func local(_ d: Date?) -> String {
                guard let d = d else { return "—" }
                let s = Int((d.timeIntervalSince1970 + off * 3600).rounded())
                let m = ((s % 86400) + 86400) % 86400
                return String(format: "%02d:%02d", m / 3600, (m % 3600) / 60)
            }
            ed.print("Sun at \(day) \(time) (UTC\(off >= 0 ? "+" : "")\(fmt(off))) at \(fmt(lat, 4)), \(fmt(lon, 4)): azimuth \(fmt(p.azimuth, 2))°, altitude \(fmt(p.altitude, 2))°\(p.isUp ? "" : " (below the horizon)")")
            ed.print("Sunrise \(local(times.sunrise)), solar noon \(local(times.noon)), sunset \(local(times.sunset)); declination \(fmt(p.declination, 2))°, equation of time \(fmt(p.equationOfTime, 2)) min")
            ed.doc.setVariable("SUNDATE", day); ed.doc.setVariable("SUNTIME", time); ed.doc.setVariable("UTCOFFSET", fmt(off))
            ed.doc.setVariable("SUNAZIMUTH", fmt(p.azimuth, 3)); ed.doc.setVariable("SUNALTITUDE", fmt(p.altitude, 3))
        }
    }

    static var clashDetect: CommandDef {
        CommandDef("CLASHDETECT", aliases: ["CLASHES", "CLASHTEST"], category: "Analysis",
                   summary: "Finds hard clashes between elements and 3D solids (touching and hosted/joined elements are ignored); lists, selects and zooms.", modifies: false) { ed in
            var o = ClashOptions()
            o.tolerance = try await ed.getReal("Enter clash tolerance (penetration)", defaultValue: 1).value ?? 1
            if !ed.selection.isEmpty {
                let k = try await ed.getKeyword("Test [Selection/All]", ["Selection", "All"], defaultValue: "All") ?? "All"
                if k == "Selection" { o.setA = ed.selection }
            }
            let clashes = ClashDetector.detect(ed.doc, options: o)
            guard !clashes.isEmpty else { ed.print("No clashes found."); ed.selection = []; return }
            for (i, c) in clashes.enumerated() { ed.print("\(i + 1). \(c.description)") }
            ed.print("\(clashes.count) clash\(clashes.count == 1 ? "" : "es").")
            ed.selection = Set(clashes.flatMap { [$0.a, $0.b] })
            try await saveCSV(ed, ClashDetector.csv(clashes), prompt: "Enter CSV report file name <none>")
            try await zoomLoop(ed, clashes.map { c in
                let b = BBox2(min: c.bounds.min.xy, max: c.bounds.max.xy)
                return ([c.a, c.b], b.expanded(by: max(b.width, b.height, 500 / ed.doc.units.mm)))
            })
        }
    }

    static var checkModel: CommandDef {
        CommandDef("CHECKMODEL", aliases: ["MODELCHECK", "AUDITMODEL", "BIMAUDIT"], category: "Analysis",
                   summary: "Checks the model: walls without height, openings wider than or outside their host, overlapping/duplicate walls and rooms, unnamed or duplicate rooms, missing levels.", modifies: false) { ed in
            let issues = ModelChecker.check(ed.doc)
            guard !issues.isEmpty else { ed.print("No issues found."); return }
            for (i, it) in issues.enumerated() { ed.print("\(i + 1). \(it.description)") }
            let e = issues.filter { $0.severity == .error }.count, w = issues.filter { $0.severity == .warning }.count
            ed.print("\(issues.count) issue\(issues.count == 1 ? "" : "s"): \(e) error\(e == 1 ? "" : "s"), \(w) warning\(w == 1 ? "" : "s").")
            ed.selection = Set(issues.flatMap(\.ids).filter { ed.doc.contains($0) })
            try await zoomLoop(ed, issues.map { ($0.ids, $0.bounds) })
        }
    }
}
