// Oanarina Archi Tool — GPL-3.0-or-later
// Floor plan options from a room programme (SCR-028): rooms with target areas are laid into a rectangular footprint by
// recursive slicing (balanced area split, cut across the longer side) with several orderings; every option is scored
// (room proportions, daylight for habitable rooms, circulation via the hall) and the chosen one is built as exterior and
// interior walls, rooms, doors connecting every room (spanning tree preferring the hall) and windows.
import Foundation

public struct BriefRoom: Hashable { public var name: String; public var area: Double
    public init(name: String, area: Double) { self.name = name; self.area = area } }

public struct PlanOption {
    public struct Room { public var name: String; public var rect: BBox2; public var area: Double { rect.width * rect.height } }
    public var rooms: [Room]
    /// Interior wall lines (slicing cuts), model units.
    public var cuts: [(Vec2, Vec2)]
    public var score: Double
    public var notes: [String]
}

public enum PlanGenerator {
    /// Parses "Living 25, Kitchen 12, Bedroom 14" (areas in m²; "x2" repeats: "Bedroom 12 x2").
    public static func parseBrief(_ s: String) -> [BriefRoom] {
        var out: [BriefRoom] = []
        for part in s.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }) {
            let words = part.split(separator: " ").map(String.init)
            var name: [String] = [], area: Double?, times = 1
            for w in words {
                let t = w.lowercased().replacingOccurrences(of: "m2", with: "").replacingOccurrences(of: "m²", with: "")
                if t.hasPrefix("x"), let n = Int(t.dropFirst()), n > 0 { times = n; continue }
                if let v = Double(t), area == nil { area = v; continue }
                name.append(w)
            }
            guard let a = area, a > 0, !name.isEmpty else { continue }
            for _ in 0..<min(times, 50) { out.append(BriefRoom(name: name.joined(separator: " "), area: a)) }
        }
        return out
    }

    static func isHall(_ n: String) -> Bool { let l = n.lowercased(); return l.contains("hall") || l.contains("corridor") || l.contains("entr") || l.contains("lobby") }
    static func isHabitable(_ n: String) -> Bool {
        let l = n.lowercased()
        return !(isHall(n) || l.contains("bath") || l.contains("wc") || l.contains("toilet") || l.contains("storage") || l.contains("store") || l.contains("utility") || l.contains("closet") || l.contains("pantry"))
    }

    /// Options for a W × D footprint (model units) with its lower-left corner at `origin`, best first.
    public static func options(_ brief: [BriefRoom], width W: Double, depth D: Double, origin: Vec2 = .zero, unitsPerM2: Double) -> [PlanOption] {
        guard !brief.isEmpty, W > 0, D > 0 else { return [] }
        let total = brief.reduce(0) { $0 + $1.area }
        let scale = W * D / (total * unitsPerM2)
        let base = brief.map { BriefRoom(name: $0.name, area: $0.area * unitsPerM2 * scale) }
        var orders: [[BriefRoom]] = []
        let desc = base.sorted { $0.area > $1.area }
        orders.append(desc)
        orders.append(base)
        // Hall in the middle of the list (sliced into the centre).
        let halls = desc.filter { isHall($0.name) }, rest = desc.filter { !isHall($0.name) }
        if !halls.isEmpty { var o = rest; o.insert(contentsOf: halls, at: rest.count / 2); orders.append(o) }
        // Wet rooms together.
        let wet = desc.filter { !isHabitable($0.name) && !isHall($0.name) }
        orders.append(desc.filter { isHabitable($0.name) } + halls + wet)
        orders.append(desc.enumerated().sorted { ($0.offset % 2, $0.offset) < ($1.offset % 2, $1.offset) }.map(\.element))
        var out: [PlanOption] = []
        var seen = Set<String>()
        for o in orders {
            for firstVertical in [true, false] {
                var rooms: [PlanOption.Room] = [], cuts: [(Vec2, Vec2)] = []
                slice(o, BBox2(min: origin, max: origin + Vec2(W, D)), preferVertical: firstVertical, rooms: &rooms, cuts: &cuts)
                let key = rooms.map { "\($0.name)@\(Int($0.rect.min.x)),\(Int($0.rect.min.y))" }.sorted().joined(separator: ";")
                guard seen.insert(key).inserted else { continue }
                var opt = PlanOption(rooms: rooms, cuts: cuts, score: 0, notes: [])
                score(&opt, footprint: BBox2(min: origin, max: origin + Vec2(W, D)))
                if scale < 0.9 { opt.notes.append("The brief is \(fmt((1 / scale - 1) * 100, 0)) % larger than the footprint; rooms were scaled down.") }
                out.append(opt)
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    /// Recursive slicing: split the list where the area is closest to half, cut the rectangle across its longer side.
    static func slice(_ list: [BriefRoom], _ r: BBox2, preferVertical: Bool, rooms: inout [PlanOption.Room], cuts: inout [(Vec2, Vec2)]) {
        guard list.count > 1 else { if let x = list.first { rooms.append(PlanOption.Room(name: x.name, rect: r)) }; return }
        let total = list.reduce(0) { $0 + $1.area }
        var acc = 0.0, best = 1, bestDiff = Double.infinity
        for i in 1..<list.count {
            acc += list[i - 1].area
            let d = abs(acc - total / 2)
            if d < bestDiff { bestDiff = d; best = i }
        }
        let a = Array(list[..<best]), b = Array(list[best...])
        let fa = a.reduce(0) { $0 + $1.area } / total
        let vertical = abs(r.width - r.height) < 1e-6 * max(r.width, 1) ? preferVertical : r.width > r.height
        if vertical {
            let x = r.min.x + r.width * fa
            cuts.append((Vec2(x, r.min.y), Vec2(x, r.max.y)))
            slice(a, BBox2(min: r.min, max: Vec2(x, r.max.y)), preferVertical: !preferVertical, rooms: &rooms, cuts: &cuts)
            slice(b, BBox2(min: Vec2(x, r.min.y), max: r.max), preferVertical: !preferVertical, rooms: &rooms, cuts: &cuts)
        } else {
            let y = r.min.y + r.height * fa
            cuts.append((Vec2(r.min.x, y), Vec2(r.max.x, y)))
            slice(a, BBox2(min: r.min, max: Vec2(r.max.x, y)), preferVertical: !preferVertical, rooms: &rooms, cuts: &cuts)
            slice(b, BBox2(min: Vec2(r.min.x, y), max: r.max), preferVertical: !preferVertical, rooms: &rooms, cuts: &cuts)
        }
    }

    /// Length along which two rectangles touch.
    static func shared(_ a: BBox2, _ b: BBox2, tol: Double) -> (Vec2, Vec2)? {
        if abs(a.max.x - b.min.x) <= tol || abs(b.max.x - a.min.x) <= tol {
            let x = abs(a.max.x - b.min.x) <= tol ? a.max.x : a.min.x
            let y0 = max(a.min.y, b.min.y), y1 = min(a.max.y, b.max.y)
            return y1 - y0 > tol ? (Vec2(x, y0), Vec2(x, y1)) : nil
        }
        if abs(a.max.y - b.min.y) <= tol || abs(b.max.y - a.min.y) <= tol {
            let y = abs(a.max.y - b.min.y) <= tol ? a.max.y : a.min.y
            let x0 = max(a.min.x, b.min.x), x1 = min(a.max.x, b.max.x)
            return x1 - x0 > tol ? (Vec2(x0, y), Vec2(x1, y)) : nil
        }
        return nil
    }

    static func score(_ o: inout PlanOption, footprint f: BBox2) {
        var s = 100.0
        let tol = 1e-6 * max(f.width, f.height)
        for r in o.rooms {
            let aspect = max(r.rect.width, r.rect.height) / max(min(r.rect.width, r.rect.height), 1e-9)
            if aspect > 2 { s -= (aspect - 2) * 8 }
            let exterior = abs(r.rect.min.x - f.min.x) <= tol || abs(r.rect.max.x - f.max.x) <= tol || abs(r.rect.min.y - f.min.y) <= tol || abs(r.rect.max.y - f.max.y) <= tol
            if isHabitable(r.name) && !exterior { s -= 25; o.notes.append("\(r.name) has no outside wall (no daylight).") }
        }
        if let hall = o.rooms.firstIndex(where: { isHall($0.name) }) {
            let n = o.rooms.indices.filter { $0 != hall && shared(o.rooms[hall].rect, o.rooms[$0].rect, tol: tol).map { $0.0.distance(to: $0.1) >= 900 } == true }.count
            s += Double(n) * 4
        }
        o.score = s
    }

    public struct BuildResult { public var walls: [EntityID]; public var rooms: [EntityID]; public var doors: [EntityID]; public var windows: [EntityID] }

    /// Builds an option on a level: walls (exterior thickness `ext`, interior `int`), rooms, doors, windows.
    public static func build(_ o: PlanOption, into d: inout ArchiDocument, level: Int, exterior ext: Double, interior int: Double, height: Double, unitMM: Double) -> BuildResult {
        var res = BuildResult(walls: [], rooms: [], doors: [], windows: [])
        var f = BBox2.empty
        for r in o.rooms { f.add(r.rect) }
        let corners = [f.min, Vec2(f.max.x, f.min.y), f.max, Vec2(f.min.x, f.max.y)]
        var extWalls: [(EntityID, Vec2, Vec2)] = []
        for i in 0..<4 {
            let id = d.addElement(.wall(WallGeom(start: corners[i], end: corners[(i + 1) % 4], thickness: ext, height: height)), level: level, name: "Exterior wall")
            if let k = d.elementIndex(id) { d.elements[k].props["isExternal"] = "1" }
            extWalls.append((id, corners[i], corners[(i + 1) % 4])); res.walls.append(id)
        }
        var intWalls: [(EntityID, Vec2, Vec2)] = []
        for c in o.cuts {
            let id = d.addElement(.wall(WallGeom(start: c.0, end: c.1, thickness: int, height: height)), level: level, name: "Partition")
            if let k = d.elementIndex(id) { d.elements[k].props["isExternal"] = "0" }
            intWalls.append((id, c.0, c.1)); res.walls.append(id)
        }
        for (n, r) in o.rooms.enumerated() {
            let b = [r.rect.min, Vec2(r.rect.max.x, r.rect.min.y), r.rect.max, Vec2(r.rect.min.x, r.rect.max.y)]
            res.rooms.append(d.addElement(.space(SpaceGeom(boundary: b, name: r.name, number: String(format: "%03d", n + 1), height: height - 300 / unitMM)), level: level, name: r.name))
        }
        let tol = 1e-6 * max(f.width, f.height, 1)
        /// Wall that contains a segment, and the offset of a point along it.
        func host(_ p: Vec2, in walls: [(EntityID, Vec2, Vec2)]) -> (EntityID, Double, Double)? {
            for w in walls {
                let dir = w.2 - w.1, L = dir.length
                guard L > 0 else { continue }
                let t = (p - w.1).dot(dir) / (L * L)
                if t >= 0, t <= 1, abs((p - w.1).cross(dir)) / L <= tol * 10 { return (w.0, t * L, L) }
            }
            return nil
        }
        // Doors: spanning tree over room adjacencies, hall first (breadth-first from the hall or the largest room).
        let doorW = 900 / unitMM
        var adj: [Int: [(Int, Vec2, Vec2)]] = [:]
        for i in o.rooms.indices { for j in o.rooms.indices where j > i {
            if let s = shared(o.rooms[i].rect, o.rooms[j].rect, tol: tol), s.0.distance(to: s.1) >= doorW + 200 / unitMM {
                adj[i, default: []].append((j, s.0, s.1)); adj[j, default: []].append((i, s.0, s.1))
            }
        } }
        let startRoom = o.rooms.firstIndex { isHall($0.name) } ?? o.rooms.indices.max { o.rooms[$0].area < o.rooms[$1].area } ?? 0
        var visited: Set<Int> = [startRoom], queue = [startRoom]
        while !queue.isEmpty {
            let r = queue.removeFirst()
            // Hall-like neighbours first, then larger rooms.
            for (n, a, b) in (adj[r] ?? []).sorted(by: { (isHall(o.rooms[$0.0].name) ? 0 : 1, -o.rooms[$0.0].area) < (isHall(o.rooms[$1.0].name) ? 0 : 1, -o.rooms[$1.0].area) }) where !visited.contains(n) {
                visited.insert(n); queue.append(n)
                let mid = (a + b) / 2
                if let (w, off, L) = host(mid, in: intWalls) {
                    res.doors.append(d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: min(max(off, doorW / 2 + 1), L - doorW / 2 - 1), width: doorW, height: 2100 / unitMM)), level: level))
                }
            }
        }
        // Entrance door on the start room's exterior side; windows for habitable rooms on their longest exterior edge.
        for (i, r) in o.rooms.enumerated() {
            let edges = [(r.rect.min, Vec2(r.rect.max.x, r.rect.min.y)), (Vec2(r.rect.max.x, r.rect.min.y), r.rect.max), (r.rect.max, Vec2(r.rect.min.x, r.rect.max.y)), (Vec2(r.rect.min.x, r.rect.max.y), r.rect.min)]
            let outside = edges.filter { e in host((e.0 + e.1) / 2, in: extWalls) != nil }.sorted { $0.0.distance(to: $0.1) > $1.0.distance(to: $1.1) }
            guard let e = outside.first else { continue }
            let mid = (e.0 + e.1) / 2
            guard let (w, off, _) = host(mid, in: extWalls) else { continue }
            let len = e.0.distance(to: e.1)
            if i == startRoom {
                res.doors.append(d.addElement(.opening(OpeningGeom(kind: .door, hostWall: w, offset: off, width: 1000 / unitMM, height: 2100 / unitMM)), level: level))
            } else if isHabitable(r.name) {
                let ww = min(1500 / unitMM, len * 0.4)
                res.windows.append(d.addElement(.opening(OpeningGeom(kind: .window, hostWall: w, offset: off, width: ww, height: 1400 / unitMM, sill: 900 / unitMM)), level: level))
            }
        }
        return res
    }

    static var command: CommandDef {
        CommandDef("PLANGEN", aliases: ["PLANFROMBRIEF", "GENERATEPLAN", "SPACEPLAN"], category: "Architecture",
                   summary: "Generates floor plan options from a room programme (\"Living 25, Kitchen 12, Bedroom 14 x2, Bath 6, Hall 8\" in m²) inside a W × D footprint: lists scored options, builds the chosen one (walls, rooms, doors, windows) after confirmation, one undo step.") { ed in
            guard let text = try await ed.getString("Room programme (name area m², …)"), !text.isEmpty else { return }
            let brief = parseBrief(text)
            guard brief.count >= 1 else { throw CommandError.invalid("No rooms understood: write e.g. Living 25, Kitchen 12, Bath 6.") }
            let u = ed.doc.units.mm
            let total = brief.reduce(0) { $0 + $1.area }
            let defW = (total.squareRoot() * 1.2 * 1000 / u).rounded()
            let W = try await ed.getDistance("Footprint width", defaultValue: defW).value ?? defW
            let defD = (total * 1_000_000 / (u * u) / W).rounded()
            let D = try await ed.getDistance("Footprint depth", defaultValue: defD).value ?? defD
            let origin = try await ed.getPoint("Lower-left corner <0,0>").point ?? .zero
            let opts = options(brief, width: W, depth: D, origin: origin, unitsPerM2: 1_000_000 / (u * u))
            guard !opts.isEmpty else { throw CommandError.invalid("No layout found.") }
            for (i, o) in opts.prefix(6).enumerated() {
                ed.print("Option \(i + 1): score \(fmt(o.score, 1)) — " + o.rooms.map { "\($0.name) \(fmt($0.area * u * u / 1_000_000, 1)) m² (\(fmt($0.rect.width * u / 1000, 1))×\(fmt($0.rect.height * u / 1000, 1)))" }.joined(separator: ", "))
                for n in Set(o.notes).sorted() { ed.print("   note: \(n)") }
            }
            let k = try await ed.getInteger("Option to build <1>", defaultValue: 1) ?? 1
            guard k >= 1, k <= min(opts.count, 6) else { throw CommandError.invalid("No option \(k).") }
            guard try await ed.getYesNo("Build option \(k) (\(opts[k - 1].rooms.count) rooms)?", defaultValue: true) else { return }
            var d = ed.doc
            let h = d.level(d.currentLevel)?.height ?? 3000 / u
            let r = build(opts[k - 1], into: &d, level: d.currentLevel, exterior: 300 / u, interior: 100 / u, height: h, unitMM: u)
            ed.doc = d
            ed.selection = Set(r.walls + r.rooms + r.doors + r.windows)
            ed.print("Built \(r.rooms.count) rooms, \(r.walls.count) walls, \(r.doors.count) doors, \(r.windows.count) windows.")
        }
    }
}
