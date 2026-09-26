// Oanarina Archi Tool — GPL-3.0-or-later
// Clash groups and status (ANL-036): clash-detection results kept in the drawing between runs. Each clash has a stable
// key (the element pair), a status (new → active → reviewed → approved / resolved), an assignee, a group and the
// dates it was found and resolved; re-running the test marks clashes that disappeared as resolved and clashes that
// came back as active. Clashes are grouped by element-type pair, by level or by proximity, and every report row
// carries a zoom box and a CLASHMANAGE Zoom <n> / archi://element/<id> link.
import Foundation

public struct ClashRecord: Codable, Hashable {
    public enum Status: String, Codable, CaseIterable { case new, active, reviewed, approved, resolved }
    public var number: Int
    public var a: EntityID, b: EntityID
    public var kinds: String
    public var point: Vec3
    public var box: BBox3
    public var status: Status
    public var assignee: String
    public var group: String
    public var found: String
    public var resolved: String?
    public var note: String
    public var key: String { ClashRecord.key(a, b) }
    static func key(_ a: EntityID, _ b: EntityID) -> String { "\(min(a, b))-\(max(a, b))" }
}

public enum ClashManager {
    static let variable = "CLASHRESULTS"

    public static func all(_ doc: ArchiDocument) -> [ClashRecord] { (VarJSON.load(doc, variable, as: [ClashRecord].self) ?? []).sorted { $0.number < $1.number } }
    static func save(_ r: [ClashRecord], _ doc: inout ArchiDocument) { VarJSON.save(r, &doc, variable, empty: r.isEmpty) }

    public struct RunSummary: Hashable { public var new = 0, active = 0, resolved = 0, total = 0 }

    /// Runs clash detection and merges the result with the stored records.
    @discardableResult
    public static func run(_ doc: inout ArchiDocument, options: ClashOptions = ClashOptions(), date: String = Markups.now()) -> RunSummary {
        let found = ClashDetector.detect(doc, options: options)
        var recs = all(doc)
        var byKey: [String: Int] = [:]
        for (i, r) in recs.enumerated() { byKey[r.key] = i }
        var seen = Set<String>()
        var s = RunSummary()
        var next = (recs.map(\.number).max() ?? 0) + 1
        for c in found {
            let k = ClashRecord.key(c.a, c.b)
            guard seen.insert(k).inserted else { continue }
            if let i = byKey[k] {
                recs[i].point = c.point; recs[i].box = c.bounds
                if recs[i].status == .resolved { recs[i].status = .active; recs[i].resolved = nil; s.active += 1 }
                else if recs[i].status == .new { recs[i].status = .active; s.active += 1 }
                else if recs[i].status == .active { s.active += 1 }
            } else {
                recs.append(ClashRecord(number: next, a: c.a, b: c.b, kinds: "\(c.kindA) × \(c.kindB)", point: c.point, box: c.bounds, status: .new,
                                        assignee: "", group: "", found: date, resolved: nil, note: ""))
                next += 1; s.new += 1
            }
        }
        for i in recs.indices where !seen.contains(recs[i].key) && recs[i].status != .resolved {
            recs[i].status = .resolved; recs[i].resolved = date; s.resolved += 1
        }
        s.total = recs.filter { $0.status != .resolved }.count
        save(recs, &doc)
        return s
    }

    public enum Grouping: String, CaseIterable { case type, level, proximity }

    /// Assigns group names: element-type pair, level of the first element, or clusters of clashes closer than `distance`.
    public static func group(_ doc: inout ArchiDocument, by g: Grouping, distance: Double = 1000) {
        var recs = all(doc)
        switch g {
        case .type: for i in recs.indices { recs[i].group = recs[i].kinds }
        case .level:
            for i in recs.indices {
                let l = doc.element(recs[i].a)?.level ?? doc.element(recs[i].b)?.level
                recs[i].group = l.flatMap { doc.level($0)?.name } ?? "No level"
            }
        case .proximity:
            // Single-linkage clustering of the clash points.
            var parent = Array(recs.indices)
            func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
            for i in recs.indices { for j in recs.indices where j > i && (recs[i].point - recs[j].point).length <= distance { parent[find(i)] = find(j) } }
            var names: [Int: String] = [:]
            for i in recs.indices {
                let r = find(i)
                if names[r] == nil { names[r] = "Cluster \(names.count + 1)" }
                recs[i].group = names[r]!
            }
        }
        save(recs, &doc)
    }

    @discardableResult
    public static func update(_ doc: inout ArchiDocument, numbers: [Int], status: ClashRecord.Status? = nil, assignee: String? = nil, note: String? = nil, date: String = Markups.now()) -> Int {
        var recs = all(doc), n = 0
        for i in recs.indices where numbers.contains(recs[i].number) {
            if let s = status { recs[i].status = s; recs[i].resolved = s == .resolved ? date : nil }
            if let a = assignee { recs[i].assignee = a }
            if let t = note { recs[i].note = t }
            n += 1
        }
        save(recs, &doc)
        return n
    }

    /// Plan zoom box of a clash (its overlap box, padded).
    public static func zoomBox(_ r: ClashRecord) -> BBox2 {
        let b = BBox2(min: r.box.min.xy, max: r.box.max.xy)
        let pad = max(b.width, b.height, 1) * 0.5 + 500
        return b.expanded(by: pad)
    }

    /// Report rows with zoom links (command and resource URI).
    public static func report(_ doc: ArchiDocument, includeResolved: Bool = false) -> [[String: Any]] {
        all(doc).filter { includeResolved || $0.status != .resolved }.map { r in
            let z = zoomBox(r)
            return ["number": r.number, "elements": [r.a, r.b], "kinds": r.kinds, "status": r.status.rawValue, "assignee": r.assignee, "group": r.group,
                    "found": r.found, "resolved": r.resolved ?? "", "note": r.note, "point": [r.point.x, r.point.y, r.point.z],
                    "zoom": ["min": [z.min.x, z.min.y], "max": [z.max.x, z.max.y]], "zoomCommand": "CLASHMANAGE Zoom \(r.number)",
                    "links": ["archi://element/\(r.a)", "archi://element/\(r.b)"]]
        }
    }

    public static func csv(_ doc: ArchiDocument) -> String {
        var rows = [["#", "group", "status", "assignee", "id_a", "id_b", "kinds", "x", "y", "z", "found", "resolved", "zoom"]]
        for r in all(doc) {
            let z = zoomBox(r)
            rows.append(["\(r.number)", r.group, r.status.rawValue, r.assignee, "\(r.a)", "\(r.b)", r.kinds, fmt(r.point.x, 1), fmt(r.point.y, 1), fmt(r.point.z, 1),
                         r.found, r.resolved ?? "", "ZOOM W \(fmt(z.min.x, 0)),\(fmt(z.min.y, 0)) \(fmt(z.max.x, 0)),\(fmt(z.max.y, 0))"])
        }
        return CSVText.make(rows)
    }

    static var command: CommandDef {
        CommandDef("CLASHMANAGE", aliases: ["CLASHMANAGER", "CLASHGROUPS", "CLASHSTATUS"], category: "Analysis",
                   summary: "Manages clash results kept in the drawing: Run (detect; disappeared clashes become resolved), List, Group (Type/Level/Proximity), Status, Assign, Zoom to a clash (selects both elements), Csv export.") { ed in
            let k = try await ed.getKeyword("Option [Run/List/Group/Status/Assign/Zoom/Csv]", ["Run", "List", "Group", "Status", "Assign", "Zoom", "Csv"], defaultValue: "List") ?? "List"
            @MainActor func numbers(_ s: String?) -> [Int] {
                guard let s, !s.isEmpty else { return [] }
                if s.lowercased() == "all" { return all(ed.doc).map(\.number) }
                return s.split(separator: ",").flatMap { p -> [Int] in
                    let r = p.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    return r.count == 2 && r[0] <= r[1] ? Array(r[0]...r[1]) : r
                }
            }
            switch k {
            case "Run":
                var o = ClashOptions()
                o.tolerance = try await ed.getReal("Clash tolerance <1>", defaultValue: 1).value ?? 1
                let s = run(&ed.doc, options: o)
                ed.print("\(s.total) open clash(es): \(s.new) new, \(s.active) active, \(s.resolved) resolved since the last run.")
            case "Group":
                let g = try await ed.getKeyword("Group by [Type/Level/Proximity]", ["Type", "Level", "Proximity"], defaultValue: "Type") ?? "Type"
                let d = g == "Proximity" ? (try await ed.getReal("Cluster distance <\(fmt(2000 / ed.doc.units.mm, 0))>", defaultValue: 2000 / ed.doc.units.mm).value ?? 2000) : 0
                group(&ed.doc, by: Grouping(rawValue: g.lowercased())!, distance: d)
                let groups = Dictionary(grouping: all(ed.doc), by: \.group)
                for (n, rs) in groups.sorted(by: { $0.key < $1.key }) { ed.print("\(n): \(rs.count)") }
            case "Status":
                let n = numbers(try await ed.getWord("Clash numbers (1,3,5-8 or All)"))
                let s = try await ed.getKeyword("Status [New/Active/Reviewed/Approved/Resolved]", ClashRecord.Status.allCases.map { $0.rawValue.capitalized }, defaultValue: "Reviewed") ?? "Reviewed"
                ed.print("\(update(&ed.doc, numbers: n, status: ClashRecord.Status(rawValue: s.lowercased()))) clash(es) set to \(s.lowercased()).")
            case "Assign":
                let n = numbers(try await ed.getWord("Clash numbers (1,3,5-8 or All)"))
                let who = try await ed.getString("Assign to") ?? ""
                ed.print("\(update(&ed.doc, numbers: n, assignee: who)) clash(es) assigned to \(who).")
            case "Zoom":
                guard let n = try await ed.getInteger("Clash number"), let r = all(ed.doc).first(where: { $0.number == n }) else { throw CommandError.invalid("No such clash.") }
                ed.selection = [r.a, r.b]
                ed.host?.perform(.zoomWindow(zoomBox(r)), editor: ed)
                ed.print("Clash \(n): \(r.kinds) #\(r.a) × #\(r.b), \(r.status.rawValue)\(r.assignee.isEmpty ? "" : ", assigned to \(r.assignee)").")
            case "Csv":
                let url = try await IOCommands.path(ed, "CSV file name")
                do { try csv(ed.doc).write(to: url, atomically: true, encoding: .utf8) } catch { throw CommandError.invalid("Cannot write \(url.path)") }
                ed.print("Wrote \(url.path).")
            default:
                let rs = all(ed.doc)
                if rs.isEmpty { ed.print("No clash results: CLASHMANAGE Run."); return }
                for r in rs { ed.print("\(r.number). [\(r.status.rawValue)] \(r.group.isEmpty ? "" : r.group + " · ")\(r.kinds) #\(r.a) × #\(r.b)\(r.assignee.isEmpty ? "" : " → \(r.assignee)")  (CLASHMANAGE Zoom \(r.number))") }
            }
        }
    }
}
