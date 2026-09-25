// Oanarina Archi Tool — GPL-3.0-or-later
// Construction sequencing (ANL-017, 4D) and resource planning (ANL-018): a work schedule of tasks linked to model elements
// (generated from the model by level and trade with quantity-based durations, or edited), critical path method on a
// working-day calendar, 4D state of every element at a date, Gantt chart (SVG) and CSV, labour / equipment resources
// with daily histograms, over-allocation and cost. The schedule is stored in the drawing (variable WORKSCHEDULE) and is
// exported to IFC as IfcWorkSchedule / IfcTask / IfcRelSequence / IfcRelAssignsToProcess.
import Foundation

public struct ScheduleTask: Codable, Hashable {
    public var id: Int
    public var name: String
    /// Working days.
    public var duration: Int
    /// Finish-to-start predecessors.
    public var predecessors: [Int]
    /// Working days between the predecessors' finish and the start (or after the project start without predecessors).
    public var lag: Int
    public var elements: [EntityID]
    /// Resource name → units assigned (workers / machines).
    public var resources: [String: Double]
    public var trade: String
    public var level: Int?
    public var quantity: Double
    public var unit: String
    public init(id: Int, name: String, duration: Int, predecessors: [Int] = [], lag: Int = 0, elements: [EntityID] = [], resources: [String: Double] = [:],
                trade: String = "", level: Int? = nil, quantity: Double = 0, unit: String = "") {
        self.id = id; self.name = name; self.duration = duration; self.predecessors = predecessors; self.lag = lag; self.elements = elements
        self.resources = resources; self.trade = trade; self.level = level; self.quantity = quantity; self.unit = unit
    }
}

public struct ScheduleResource: Codable, Hashable {
    public var name: String
    public var kind: String          // labour / equipment
    public var costPerDay: Double    // per unit
    public var available: Double     // units available per day
    public init(name: String, kind: String, costPerDay: Double, available: Double) { self.name = name; self.kind = kind; self.costPerDay = costPerDay; self.available = available }
}

public struct WorkSchedule: Codable, Hashable {
    public var name: String
    /// Start date yyyy-MM-dd.
    public var start: String
    public var tasks: [ScheduleTask]
    public var resources: [ScheduleResource]
    /// Working weekdays (Calendar weekday numbers, 1 = Sunday): Monday–Friday by default.
    public var workdays: [Int] = [2, 3, 4, 5, 6]
    public init(name: String, start: String, tasks: [ScheduleTask] = [], resources: [ScheduleResource] = []) { self.name = name; self.start = start; self.tasks = tasks; self.resources = resources }
}

public struct TaskTiming: Hashable {
    /// Working-day offsets from the project start: task occupies days es ..< ef.
    public var es: Int, ef: Int, ls: Int, lf: Int
    public var totalFloat: Int { ls - es }
    public var critical: Bool { totalFloat == 0 }
}

public enum Scheduler {
    public struct ScheduleError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    public static let variable = "WORKSCHEDULE"

    public static func load(_ doc: ArchiDocument) -> WorkSchedule? {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkSchedule.self, from: d)
    }
    public static func save(_ s: WorkSchedule, in doc: inout ArchiDocument) {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        if let d = try? e.encode(s) { doc.setVariable(variable, String(decoding: d, as: UTF8.self)) }
    }

    /// Productivity per crew-day (quantity units) and the crew for each trade.
    public static let productivity: [String: (rate: Double, unit: String, crew: [String: Double])] = [
        "Foundations": (8, "m³", ["Concrete crew": 4, "Excavator": 1]),
        "Structure": (5, "m³", ["Concrete crew": 4, "Crane": 1]),
        "Walls": (20, "m²", ["Masonry crew": 3]),
        "Floor slabs": (12, "m³", ["Concrete crew": 5, "Crane": 1]),
        "Stairs": (0.5, "pcs", ["Concrete crew": 3]),
        "Roof": (40, "m²", ["Carpentry crew": 3, "Crane": 1]),
        "Doors and windows": (6, "pcs", ["Glazing crew": 2]),
        "Curtain walls": (15, "m²", ["Glazing crew": 3, "Crane": 1]),
    ]
    public static let defaultResources: [ScheduleResource] = [
        ScheduleResource(name: "Concrete crew", kind: "labour", costPerDay: 280, available: 8),
        ScheduleResource(name: "Masonry crew", kind: "labour", costPerDay: 260, available: 6),
        ScheduleResource(name: "Carpentry crew", kind: "labour", costPerDay: 270, available: 4),
        ScheduleResource(name: "Glazing crew", kind: "labour", costPerDay: 290, available: 3),
        ScheduleResource(name: "Crane", kind: "equipment", costPerDay: 900, available: 1),
        ScheduleResource(name: "Excavator", kind: "equipment", costPerDay: 650, available: 1),
    ]

    /// Trade and quantity (m, m², m³ or pieces) of an element.
    public static func trade(_ el: BIMElement, doc: ArchiDocument) -> (trade: String, quantity: Double, unit: String)? {
        let m = doc.units.mm / 1000
        switch el.geometry {
        case .slab(let s):
            let v = ScheduleExporter.slabArea(s) * m * m * s.thickness * m
            return ((el.props["kind"] ?? "") == "foundation" ? "Foundations" : "Floor slabs", v, "m³")
        case .column(let c): return ("Structure", (c.round ? .pi * c.width * c.width / 4 : c.width * c.depth) * m * m * c.height * m, "m³")
        case .beam(let b): return ("Structure", b.width * b.depth * m * m * b.start.distance(to: b.end) * m, "m³")
        case .wall(let w): return ("Walls", w.length * w.height * m * m, "m²")
        case .stair: return ("Stairs", 1, "pcs")
        case .roof(let r): return ("Roof", abs(GeometryOps.signedArea(r.boundary)) * m * m, "m²")
        case .opening(let o): return o.kind == .opening ? nil : ("Doors and windows", 1, "pcs")
        case .curtainWall(let c): return ("Curtain walls", c.start.distance(to: c.end) * c.height * m * m, "m²")
        default: return nil
        }
    }

    /// Generates tasks per level and trade, in construction order: (per level) foundations → floor slab → structure →
    /// walls → stairs → doors/windows; the roof after the top walls.
    public static func generate(_ doc: ArchiDocument, start: String) -> WorkSchedule {
        var groups: [String: (level: Int, els: [EntityID], q: Double, unit: String)] = [:]
        for el in doc.elements {
            guard let t = trade(el, doc: doc) else { continue }
            let key = "\(t.trade)|\(el.level)"
            groups[key, default: (el.level, [], 0, t.unit)].els.append(el.id)
            groups[key]!.q += t.quantity
        }
        let order = ["Foundations", "Floor slabs", "Structure", "Walls", "Curtain walls", "Stairs", "Doors and windows", "Roof"]
        let levels = doc.levels.sorted { $0.elevation < $1.elevation }
        func levelName(_ id: Int) -> String { doc.level(id)?.name ?? "Level \(id)" }
        var tasks: [ScheduleTask] = []
        var lastStructural: Int?   // task id of the previous structural step (chain)
        var perLevelWalls: [Int: Int] = [:]
        for lv in levels {
            for trade in order {
                guard let g = groups["\(trade)|\(lv.id)"], !g.els.isEmpty else { continue }
                let p = productivity[trade]!
                let dur = max(1, Int(ceil(g.q / p.rate - 1e-9)))
                let id = tasks.count + 1
                var preds: [Int] = []
                switch trade {
                case "Foundations", "Structure", "Walls", "Curtain walls", "Floor slabs", "Roof":
                    if let l = lastStructural { preds = [l] }
                case "Stairs", "Doors and windows":
                    if let w = perLevelWalls[lv.id] ?? lastStructural { preds = [w] }
                default: break
                }
                tasks.append(ScheduleTask(id: id, name: "\(levelName(lv.id)) — \(trade)", duration: dur, predecessors: preds, elements: g.els.sorted(),
                                          resources: p.crew, trade: trade, level: lv.id, quantity: g.q, unit: p.unit))
                if ["Foundations", "Structure", "Walls", "Curtain walls", "Floor slabs", "Roof"].contains(trade) { lastStructural = id }
                if trade == "Walls" || trade == "Curtain walls" { perLevelWalls[lv.id] = id }
            }
        }
        return WorkSchedule(name: doc.info.name + " schedule", start: start, tasks: tasks, resources: defaultResources)
    }

    /// Critical path method (finish-to-start with lag). Throws on unknown predecessors or cycles.
    public static func cpm(_ s: WorkSchedule) throws -> [Int: TaskTiming] {
        let byID = Dictionary(s.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for t in s.tasks { for p in t.predecessors where byID[p] == nil { throw ScheduleError(message: "Task \(t.id) depends on unknown task \(p).") } }
        // Topological order (Kahn).
        var indeg = Dictionary(uniqueKeysWithValues: s.tasks.map { ($0.id, $0.predecessors.count) })
        var succ: [Int: [Int]] = [:]
        for t in s.tasks { for p in t.predecessors { succ[p, default: []].append(t.id) } }
        var queue = s.tasks.filter { $0.predecessors.isEmpty }.map(\.id).sorted()
        var topo: [Int] = []
        while !queue.isEmpty {
            let n = queue.removeFirst(); topo.append(n)
            for m in succ[n] ?? [] { indeg[m]! -= 1; if indeg[m] == 0 { queue.append(m) } }
        }
        guard topo.count == s.tasks.count else { throw ScheduleError(message: "The task dependencies contain a cycle.") }
        var es: [Int: Int] = [:], ef: [Int: Int] = [:]
        for id in topo {
            let t = byID[id]!
            // Lag: after the predecessors, or a delayed start for tasks without predecessors.
            let start = t.predecessors.map { (ef[$0] ?? 0) + t.lag }.max() ?? t.lag
            es[id] = max(0, start); ef[id] = es[id]! + max(0, t.duration)
        }
        let end = ef.values.max() ?? 0
        var lf: [Int: Int] = [:], ls: [Int: Int] = [:]
        for id in topo.reversed() {
            let t = byID[id]!
            let f = (succ[id] ?? []).map { (ls[$0] ?? end) - byID[$0]!.lag }.min() ?? end
            lf[id] = f; ls[id] = f - max(0, t.duration)
        }
        return Dictionary(uniqueKeysWithValues: s.tasks.map { ($0.id, TaskTiming(es: es[$0.id]!, ef: ef[$0.id]!, ls: ls[$0.id]!, lf: lf[$0.id]!)) })
    }

    static func dayFormatter() -> DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); return f
    }
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    /// Calendar date of a working-day offset (0 = the first working day on or after the start).
    public static func date(_ s: WorkSchedule, workday: Int) -> Date {
        let cal = utc
        var d = dayFormatter().date(from: s.start) ?? cal.startOfDay(for: Date())
        let work = Set(s.workdays.isEmpty ? [2, 3, 4, 5, 6] : s.workdays)
        func isWork(_ x: Date) -> Bool { work.contains(cal.component(.weekday, from: x)) }
        while !isWork(d) { d = cal.date(byAdding: .day, value: 1, to: d)! }
        var n = workday
        while n > 0 { d = cal.date(byAdding: .day, value: 1, to: d)!; if isWork(d) { n -= 1 } }
        return d
    }
    /// Working-day offset of a calendar date (days before the start count as -1).
    public static func workday(_ s: WorkSchedule, of date: Date) -> Int {
        var lo = 0, hi = 1
        while Scheduler.date(s, workday: hi) <= date { hi *= 2; if hi > 1 << 20 { break } }
        if Scheduler.date(s, workday: 0) > date { return -1 }
        while lo < hi - 1 { let mid = (lo + hi) / 2; if Scheduler.date(s, workday: mid) <= date { lo = mid } else { hi = mid } }
        return lo
    }

    public enum ElementState: String { case notStarted = "not started", inProgress = "in progress", complete }

    /// 4D: state of each scheduled element at the end of a working day.
    public static func states(_ s: WorkSchedule, timing: [Int: TaskTiming], day: Int) -> [EntityID: ElementState] {
        var out: [EntityID: ElementState] = [:]
        for t in s.tasks {
            guard let tm = timing[t.id] else { continue }
            let st: ElementState = day >= tm.ef - 1 && tm.ef > tm.es ? .complete : day >= tm.es ? .inProgress : .notStarted
            for e in t.elements { out[e] = st }
        }
        return out
    }

    /// Daily resource usage (units per working day) over the project.
    public static func histogram(_ s: WorkSchedule, timing: [Int: TaskTiming]) -> [String: [Double]] {
        let end = timing.values.map(\.ef).max() ?? 0
        var h: [String: [Double]] = [:]
        for t in s.tasks {
            guard let tm = timing[t.id] else { continue }
            for (r, u) in t.resources {
                if h[r] == nil { h[r] = Array(repeating: 0, count: end) }
                for d in tm.es..<tm.ef where d < end { h[r]![d] += u }
            }
        }
        return h
    }

    /// Days on which a resource is used above its availability: resource → [(day, used, available)].
    public static func overallocations(_ s: WorkSchedule, timing: [Int: TaskTiming]) -> [String: [(day: Int, used: Double, available: Double)]] {
        var out: [String: [(Int, Double, Double)]] = [:]
        for (r, days) in histogram(s, timing: timing) {
            let avail = s.resources.first { $0.name == r }?.available ?? .infinity
            for (d, u) in days.enumerated() where u > avail + 1e-9 { out[r, default: []].append((d, u, avail)) }
        }
        return out.mapValues { $0.map { (day: $0.0, used: $0.1, available: $0.2) } }
    }

    /// Resource cost: Σ units × days × cost per day, per resource and total.
    public static func cost(_ s: WorkSchedule) -> (byResource: [String: Double], total: Double) {
        var c: [String: Double] = [:]
        for t in s.tasks {
            for (r, u) in t.resources { c[r, default: 0] += u * Double(t.duration) * (s.resources.first { $0.name == r }?.costPerDay ?? 0) }
        }
        return (c, c.values.reduce(0, +))
    }

    /// Resource levelling (serial, priority = early start then float): delays tasks until their resources fit (a task that
    /// alone needs more than is available runs on its own).
    public static func level(_ s: WorkSchedule) throws -> WorkSchedule {
        var out = s
        let base = try cpm(s)
        let avail = Dictionary(uniqueKeysWithValues: s.resources.map { ($0.name, $0.available) })
        var used: [String: [Int: Double]] = [:]
        var finish: [Int: Int] = [:]
        let order = s.tasks.sorted { (base[$0.id]!.es, base[$0.id]!.totalFloat, $0.id) < (base[$1.id]!.es, base[$1.id]!.totalFloat, $1.id) }
        var remaining = order
        var startOf: [Int: Int] = [:]
        var guardN = 0
        while !remaining.isEmpty && guardN < 100_000 {
            guardN += 1
            guard let i = remaining.firstIndex(where: { t in t.predecessors.allSatisfy { finish[$0] != nil } }) else { break }
            let t = remaining.remove(at: i)
            var d = max(t.predecessors.map { finish[$0]! + t.lag }.max() ?? 0, 0)
            func fits(_ d0: Int) -> Bool {
                for day in d0..<(d0 + t.duration) { for (r, u) in t.resources where (used[r]?[day] ?? 0) + u > max(avail[r] ?? .infinity, u) + 1e-9 { return false } }
                return true
            }
            while !fits(d) && d < 100_000 { d += 1 }
            for day in d..<(d + t.duration) { for (r, u) in t.resources { used[r, default: [:]][day, default: 0] += u } }
            startOf[t.id] = d; finish[t.id] = d + t.duration
        }
        // Encode the levelled starts as lags on the first predecessor (or a start lag).
        for k in out.tasks.indices {
            let t = out.tasks[k]
            guard let st = startOf[t.id] else { continue }
            let natural = t.predecessors.map { finish[$0]! }.max() ?? 0
            out.tasks[k].lag = max(0, st - natural)
            if t.predecessors.isEmpty && st > 0 { out.tasks[k].lag = st }
        }
        return out
    }

    public static func csv(_ s: WorkSchedule, timing: [Int: TaskTiming]) -> String {
        let f = dayFormatter()
        var rows = [["Id", "Task", "Trade", "Quantity", "Unit", "Duration (d)", "Start", "Finish", "Total float (d)", "Critical", "Predecessors", "Elements", "Resources"]]
        for t in s.tasks {
            guard let tm = timing[t.id] else { continue }
            rows.append(["\(t.id)", t.name, t.trade, fmt(t.quantity, 2), t.unit, "\(t.duration)", f.string(from: date(s, workday: tm.es)),
                         f.string(from: date(s, workday: max(tm.es, tm.ef - 1))), "\(tm.totalFloat)", tm.critical ? "yes" : "no",
                         t.predecessors.map(String.init).joined(separator: " "), "\(t.elements.count)",
                         t.resources.sorted { $0.key < $1.key }.map { "\($0.key) ×\(fmt($0.value, 1))" }.joined(separator: "; ")])
        }
        return CSVText.make(rows)
    }

    /// Gantt chart: one bar per task (critical in red), weeks along the top, dependency arrows.
    public static func ganttSVG(_ s: WorkSchedule, timing: [Int: TaskTiming]) -> String {
        let end = max(1, timing.values.map(\.ef).max() ?? 1)
        let dayW = 14.0, rowH = 22.0, left = 300.0, top = 40.0
        let W = left + Double(end) * dayW + 20, H = top + Double(s.tasks.count) * rowH + 20
        func esc(_ x: String) -> String { x.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let f = dayFormatter()
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(Int(W))\" height=\"\(Int(H))\" font-family=\"Helvetica\" font-size=\"11\">\n"
        svg += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n<text x=\"8\" y=\"18\" font-size=\"14\" font-weight=\"bold\">\(esc(s.name))</text>\n"
        for wk in stride(from: 0, to: end, by: 5) {
            let x = left + Double(wk) * dayW
            svg += "<line x1=\"\(fmt(x, 1))\" y1=\"\(Int(top - 8))\" x2=\"\(fmt(x, 1))\" y2=\"\(Int(H - 20))\" stroke=\"#dddddd\"/>"
            svg += "<text x=\"\(fmt(x + 2, 1))\" y=\"\(Int(top - 12))\" fill=\"#666666\">\(f.string(from: date(s, workday: wk)))</text>\n"
        }
        var rowOf: [Int: Int] = [:]
        for (i, t) in s.tasks.enumerated() {
            rowOf[t.id] = i
            guard let tm = timing[t.id] else { continue }
            let y = top + Double(i) * rowH
            svg += "<text x=\"8\" y=\"\(fmt(y + 15, 1))\">\(esc(t.name)) (\(t.duration) d)</text>"
            svg += "<rect class=\"task\" data-id=\"\(t.id)\" x=\"\(fmt(left + Double(tm.es) * dayW, 1))\" y=\"\(fmt(y + 4, 1))\" width=\"\(fmt(max(Double(t.duration), 0.3) * dayW, 1))\" height=\"\(fmt(rowH - 8, 1))\" rx=\"3\" fill=\"\(tm.critical ? "#d9412b" : "#F5C518")\"/>\n"
        }
        for t in s.tasks {
            guard let tm = timing[t.id], let r = rowOf[t.id] else { continue }
            for p in t.predecessors {
                guard let pt = timing[p], let pr = rowOf[p] else { continue }
                let x1 = left + Double(pt.ef) * dayW, y1 = top + Double(pr) * rowH + rowH / 2
                let x2 = left + Double(tm.es) * dayW, y2 = top + Double(r) * rowH + rowH / 2
                svg += "<path d=\"M\(fmt(x1, 1)),\(fmt(y1, 1)) H\(fmt(max(x1 + 4, x2 - 4), 1)) V\(fmt(y2, 1)) H\(fmt(x2, 1))\" fill=\"none\" stroke=\"#555555\" stroke-width=\"0.8\"/>\n"
            }
        }
        return svg + "</svg>\n"
    }
}

extension Scheduler {
    static var command: CommandDef {
        CommandDef("WORKSCHEDULE", aliases: ["SCHEDULE4D", "4D", "GANTT", "CONSTRUCTIONSEQUENCE"], category: "Analyze",
                   summary: "Construction sequencing (4D) and resources: Generate tasks from the model (by level and trade, quantity-based durations, crews), List with dates and critical path, Duration/Link to edit tasks, Simulate a date (selects the elements built by then), Resources (histogram, over-allocation, cost), Level (resource levelling), Gantt (SVG), Csv.") { ed in
            let k = try await ed.getKeyword("Enter an option [Generate/List/Duration/Link/Simulate/Resources/Level/Gantt/Csv]",
                                            ["Generate", "List", "Duration", "Link", "Simulate", "Resources", "Level", "Gantt", "Csv"], defaultValue: "List") ?? "List"
            @MainActor func current() throws -> WorkSchedule {
                guard let s = load(ed.doc) else { throw CommandError.invalid("No work schedule (WORKSCHEDULE Generate).") }
                return s
            }
            @MainActor func timing(_ s: WorkSchedule) throws -> [Int: TaskTiming] {
                do { return try cpm(s) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            }
            let f = dayFormatter()
            switch k {
            case "Generate":
                let today = f.string(from: Date())
                let start = try await ed.getWord("Project start date yyyy-MM-dd <\(today)>", defaultValue: today) ?? today
                guard f.date(from: start) != nil else { throw CommandError.invalid("Use a date like 2026-03-02.") }
                let s = generate(ed.doc, start: start)
                guard !s.tasks.isEmpty else { throw CommandError.invalid("The model has no building elements to schedule.") }
                save(s, in: &ed.doc)
                let tm = try timing(s)
                ed.print("\(s.tasks.count) tasks, \(tm.values.map(\.ef).max() ?? 0) working days, finish \(f.string(from: date(s, workday: max(0, (tm.values.map(\.ef).max() ?? 1) - 1)))).")
            case "Duration":
                var s = try current()
                let id = try await ed.getInteger("Task id") ?? 0
                guard let i = s.tasks.firstIndex(where: { $0.id == id }) else { throw CommandError.invalid("No task \(id).") }
                let d = try await ed.getInteger("Duration in working days <\(s.tasks[i].duration)>", defaultValue: s.tasks[i].duration) ?? s.tasks[i].duration
                guard d >= 0 else { throw CommandError.invalid("The duration cannot be negative.") }
                s.tasks[i].duration = d
                save(s, in: &ed.doc)
                ed.print("Task \(id): \(d) days.")
            case "Link":
                var s = try current()
                let a = try await ed.getInteger("Predecessor task id") ?? 0
                let b = try await ed.getInteger("Successor task id") ?? 0
                let lag = try await ed.getInteger("Lag in working days <0>", defaultValue: 0) ?? 0
                guard let i = s.tasks.firstIndex(where: { $0.id == b }), s.tasks.contains(where: { $0.id == a }), a != b else { throw CommandError.invalid("Unknown task.") }
                if !s.tasks[i].predecessors.contains(a) { s.tasks[i].predecessors.append(a) }
                s.tasks[i].lag = lag
                _ = try timing(s)
                save(s, in: &ed.doc)
                ed.print("Task \(b) now follows task \(a).")
            case "Simulate":
                let s = try current(); let tm = try timing(s)
                let def = f.string(from: date(s, workday: (tm.values.map(\.ef).max() ?? 1) / 2))
                let ds = try await ed.getWord("Date yyyy-MM-dd <\(def)>", defaultValue: def) ?? def
                guard let d = f.date(from: ds) else { throw CommandError.invalid("Use a date like 2026-03-02.") }
                let st = states(s, timing: tm, day: workday(s, of: d))
                let done = st.filter { $0.value == .complete }.map(\.key), doing = st.filter { $0.value == .inProgress }.map(\.key)
                ed.selection = Set(done + doing).filter { ed.doc.contains($0) }
                ed.doc.setVariable("SCHEDULEDATE", ds)
                ed.print("\(ds): \(done.count) element(s) complete, \(doing.count) in progress, \(st.count - done.count - doing.count) not started.")
                for t in s.tasks { if let x = tm[t.id], workday(s, of: d) >= x.es && workday(s, of: d) < x.ef { ed.print("  in progress: \(t.name)") } }
            case "Resources":
                let s = try current(); let tm = try timing(s)
                let h = histogram(s, timing: tm)
                for (r, days) in h.sorted(by: { $0.key < $1.key }) {
                    let avail = s.resources.first { $0.name == r }?.available ?? 0
                    ed.print("\(r): peak \(fmt(days.max() ?? 0, 1)) of \(fmt(avail, 1)) available, \(fmt(days.reduce(0, +), 1)) unit-days")
                }
                for (r, over) in overallocations(s, timing: tm).sorted(by: { $0.key < $1.key }) {
                    ed.print("Over-allocated \(r) on \(over.count) day(s), first \(f.string(from: date(s, workday: over[0].day))) (\(fmt(over[0].used, 1)) > \(fmt(over[0].available, 1))). WORKSCHEDULE Level resolves it.")
                }
                let c = cost(s)
                ed.print("Resource cost \(fmt(c.total, 0)) (" + c.byResource.sorted { $0.key < $1.key }.map { "\($0.key) \(fmt($0.value, 0))" }.joined(separator: ", ") + ").")
            case "Level":
                let s = try current()
                let lv: WorkSchedule
                do { lv = try level(s) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
                save(lv, in: &ed.doc)
                let a = try timing(s).values.map(\.ef).max() ?? 0, b = try timing(lv).values.map(\.ef).max() ?? 0
                ed.print("Levelled: \(a) → \(b) working days, \(overallocations(lv, timing: try timing(lv)).count) over-allocated resource(s).")
            case "Gantt":
                let s = try current(); let tm = try timing(s)
                var url = try await IOCommands.path(ed, "Enter SVG file name")
                if url.pathExtension.isEmpty { url.appendPathExtension("svg") }
                let svg = ganttSVG(s, timing: tm)
                try IOCommands.write(ed, url, "Gantt chart", { try svg.write(to: url, atomically: true, encoding: .utf8) })
            case "Csv":
                let s = try current(); let tm = try timing(s)
                try await AnalysisCommands.saveCSV(ed, csv(s, timing: tm), prompt: "Enter CSV file name")
            default:
                let s = try current(); let tm = try timing(s)
                for t in s.tasks {
                    guard let x = tm[t.id] else { continue }
                    ed.print("\(t.id). \(t.name): \(fmt(t.quantity, 1)) \(t.unit), \(t.duration) d, \(f.string(from: date(s, workday: x.es))) → \(f.string(from: date(s, workday: max(x.es, x.ef - 1))))\(x.critical ? "  [critical]" : "  float \(x.totalFloat) d")")
                }
            }
        }
    }
}
