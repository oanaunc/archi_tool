// Oanarina Archi Tool — GPL-3.0-or-later
// Generative design (SCR-034): a seeded genetic algorithm that optimises floor layouts for weighted objectives.
// A genome is a room order (permutation), the cut direction of every slicing step and the footprint proportion
// (for a fixed gross area). Objectives, all minimised: daylight (habitable rooms without an outside wall), room
// proportions (aspect beyond 1:2), required adjacencies not met (rooms that must share a wall ≥ 1.2 m), orientation
// (rooms that should face a compass direction but do not) and envelope compactness (perimeter / √area − 4).
// The run is deterministic for a seed; results are the Pareto front ordered by the weighted score.
import Foundation

public enum GenerativeDesign {
    public struct Objectives: Hashable {
        public var daylight: Double = 0, proportion: Double = 0, adjacency: Double = 0, orientation: Double = 0, compactness: Double = 0
        public func weighted(_ w: Weights) -> Double {
            daylight * w.daylight + proportion * w.proportion + adjacency * w.adjacency + orientation * w.orientation + compactness * w.compactness
        }
        func dominates(_ o: Objectives) -> Bool {
            let a = [daylight, proportion, adjacency, orientation, compactness], b = [o.daylight, o.proportion, o.adjacency, o.orientation, o.compactness]
            return zip(a, b).allSatisfy { $0 <= $1 + 1e-12 } && zip(a, b).contains { $0 < $1 - 1e-12 }
        }
    }
    public struct Weights: Hashable {
        public var daylight = 10.0, proportion = 3.0, adjacency = 6.0, orientation = 2.0, compactness = 4.0
        public init() {}
    }
    public struct Brief {
        public var rooms: [BriefRoom]
        /// Pairs of room names (case-insensitive prefix match) that must share a wall.
        public var adjacent: [(String, String)] = []
        /// Room name prefix → compass direction ("N", "E", "S", "W") its outside wall should face.
        public var facing: [String: String] = [:]
        public init(rooms: [BriefRoom], adjacent: [(String, String)] = [], facing: [String: String] = [:]) { self.rooms = rooms; self.adjacent = adjacent; self.facing = facing }
    }
    public struct Options {
        public var population = 48, generations = 60, seed: UInt64 = 1
        public var minAspect = 0.5, maxAspect = 2.0     // footprint width / depth
        public var weights = Weights()
        public var northAngle = 0.0                     // degrees, plan north from +Y (CCW)
        public init() {}
    }
    public struct Design {
        public var option: PlanOption
        public var objectives: Objectives
        public var score: Double
        public var width: Double, depth: Double
    }

    struct Genome { var order: [Int]; var vertical: [Bool]; var aspect: Double }

    /// Small deterministic PRNG (SplitMix64).
    struct RNG { var s: UInt64
        mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    }

    static func decode(_ g: Genome, brief: Brief, area: Double, origin: Vec2, unitsPerM2: Double) -> (PlanOption, Double, Double) {
        let W = (area * g.aspect).squareRoot(), D = area / W
        let total = brief.rooms.reduce(0) { $0 + $1.area }
        let k = area / (total * unitsPerM2)
        let list = g.order.map { BriefRoom(name: brief.rooms[$0].name, area: brief.rooms[$0].area * unitsPerM2 * k) }
        var rooms: [PlanOption.Room] = [], cuts: [(Vec2, Vec2)] = []
        var gene = 0
        func slice(_ l: [BriefRoom], _ r: BBox2) {
            guard l.count > 1 else { if let x = l.first { rooms.append(PlanOption.Room(name: x.name, rect: r)) }; return }
            let t = l.reduce(0) { $0 + $1.area }
            var acc = 0.0, best = 1, bd = Double.infinity
            for i in 1..<l.count { acc += l[i - 1].area; let d = abs(acc - t / 2); if d < bd { bd = d; best = i } }
            let a = Array(l[..<best]), b = Array(l[best...])
            let fa = a.reduce(0) { $0 + $1.area } / t
            let v = gene < g.vertical.count ? g.vertical[gene] : r.width > r.height
            gene += 1
            if v {
                let x = r.min.x + r.width * fa
                cuts.append((Vec2(x, r.min.y), Vec2(x, r.max.y)))
                slice(a, BBox2(min: r.min, max: Vec2(x, r.max.y))); slice(b, BBox2(min: Vec2(x, r.min.y), max: r.max))
            } else {
                let y = r.min.y + r.height * fa
                cuts.append((Vec2(r.min.x, y), Vec2(r.max.x, y)))
                slice(a, BBox2(min: r.min, max: Vec2(r.max.x, y))); slice(b, BBox2(min: Vec2(r.min.x, y), max: r.max))
            }
        }
        slice(list, BBox2(min: origin, max: origin + Vec2(W, D)))
        return (PlanOption(rooms: rooms, cuts: cuts, score: 0, notes: []), W, D)
    }

    static func matches(_ name: String, _ key: String) -> Bool { name.lowercased().hasPrefix(key.lowercased()) }

    /// Outward compass direction of a footprint side ("S" for the bottom side when north is up).
    static func compass(of normal: Vec2, northAngle: Double) -> String {
        let n = normal.rotated(by: -northAngle * .pi / 180)   // into a frame where north = +Y
        let az = (atan2(n.x, n.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return ["N", "E", "S", "W"][Int(((az + 45) / 90).rounded(.down)) % 4]
    }

    public static func evaluate(_ o: PlanOption, brief: Brief, options: Options, unitMM: Double) -> Objectives {
        var f = BBox2.empty
        for r in o.rooms { f.add(r.rect) }
        let tol = 1e-6 * max(f.width, f.height, 1)
        var obj = Objectives()
        for r in o.rooms {
            let aspect = max(r.rect.width, r.rect.height) / max(min(r.rect.width, r.rect.height), 1e-9)
            obj.proportion += max(0, aspect - 2)
            let sides: [(Bool, Vec2)] = [(abs(r.rect.min.y - f.min.y) <= tol, Vec2(0, -1)), (abs(r.rect.max.x - f.max.x) <= tol, Vec2(1, 0)),
                                         (abs(r.rect.max.y - f.max.y) <= tol, Vec2(0, 1)), (abs(r.rect.min.x - f.min.x) <= tol, Vec2(-1, 0))]
            let outside = sides.filter(\.0).map(\.1)
            if PlanGenerator.isHabitable(r.name) && !PlanGenerator.isHall(r.name) && outside.isEmpty { obj.daylight += 1 }
            for (k, dir) in brief.facing where matches(r.name, k) {
                if !outside.contains(where: { compass(of: $0, northAngle: options.northAngle) == dir.uppercased() }) { obj.orientation += 1 }
            }
        }
        let minWall = 1200 / unitMM
        for (a, b) in brief.adjacent {
            let ra = o.rooms.filter { matches($0.name, a) }, rb = o.rooms.filter { matches($0.name, b) }
            guard !ra.isEmpty, !rb.isEmpty else { continue }
            let ok = ra.contains { x in rb.contains { y in PlanGenerator.shared(x.rect, y.rect, tol: tol).map { $0.0.distance(to: $0.1) >= minWall } ?? false } }
            if !ok { obj.adjacency += 1 }
        }
        let area = f.width * f.height
        obj.compactness = area > 0 ? 2 * (f.width + f.height) / area.squareRoot() - 4 : 0
        return obj
    }

    /// Runs the optimisation for a footprint of `area` (model units²). Returns the Pareto front, best weighted first.
    public static func run(_ brief: Brief, area: Double, origin: Vec2 = .zero, unitMM: Double, options o: Options = Options()) -> [Design] {
        let n = brief.rooms.count
        guard n >= 1, area > 0 else { return [] }
        let unitsPerM2 = 1_000_000 / (unitMM * unitMM)
        var rng = RNG(s: o.seed)
        let genes = max(0, n - 1)
        func random() -> Genome {
            var order = Array(0..<n)
            for i in stride(from: n - 1, to: 0, by: -1) { order.swapAt(i, rng.int(i + 1)) }
            return Genome(order: order, vertical: (0..<genes).map { _ in rng.unit() < 0.5 }, aspect: o.minAspect + (o.maxAspect - o.minAspect) * rng.unit())
        }
        func fitness(_ g: Genome) -> (Design) {
            let (opt, W, D) = decode(g, brief: brief, area: area, origin: origin, unitsPerM2: unitsPerM2)
            let ob = evaluate(opt, brief: brief, options: o, unitMM: unitMM)
            var p = opt; p.score = -ob.weighted(o.weights)
            return Design(option: p, objectives: ob, score: ob.weighted(o.weights), width: W, depth: D)
        }
        // Seed with the deterministic orders of the rule-based generator.
        var pop: [Genome] = [Genome(order: Array(0..<n), vertical: [], aspect: 1), Genome(order: Array(0..<n).sorted { brief.rooms[$0].area > brief.rooms[$1].area }, vertical: [], aspect: 1)]
        while pop.count < max(4, o.population) { pop.append(random()) }
        var scored = pop.map { ($0, fitness($0)) }
        var archive: [String: Design] = [:]
        func key(_ d: Design) -> String { d.option.rooms.map { "\($0.name)@\(Int($0.rect.min.x)),\(Int($0.rect.min.y)),\(Int($0.rect.width))" }.joined(separator: ";") }
        func remember(_ d: Design) { archive[key(d)] = d }
        scored.forEach { remember($0.1) }
        for _ in 0..<o.generations {
            scored.sort { $0.1.score < $1.1.score }
            var next = Array(scored.prefix(max(2, o.population / 8)).map(\.0))   // elitism
            func pick() -> Genome {
                let a = scored[rng.int(scored.count)], b = scored[rng.int(scored.count)]
                return a.1.score <= b.1.score ? a.0 : b.0
            }
            while next.count < o.population {
                let p1 = pick(), p2 = pick()
                // Order crossover (OX) on the permutation, uniform crossover on the cut genes, blend on the aspect.
                var child = Genome(order: [], vertical: [], aspect: (p1.aspect + p2.aspect) / 2)
                if n > 1 {
                    let i = rng.int(n), j = rng.int(n)
                    let (lo, hi) = (min(i, j), max(i, j))
                    var slot = [Int?](repeating: nil, count: n)
                    for k in lo...hi { slot[k] = p1.order[k] }
                    var rest = p2.order.filter { !p1.order[lo...hi].contains($0) }.makeIterator()
                    for k in 0..<n where slot[k] == nil { slot[k] = rest.next() }
                    child.order = slot.map { $0! }
                } else { child.order = p1.order }
                let v1 = p1.vertical.isEmpty ? (0..<genes).map { $0 % 2 == 0 } : p1.vertical
                let v2 = p2.vertical.isEmpty ? (0..<genes).map { $0 % 2 == 1 } : p2.vertical
                child.vertical = (0..<genes).map { rng.unit() < 0.5 ? v1[$0] : v2[$0] }
                // Mutation.
                if n > 1, rng.unit() < 0.3 { child.order.swapAt(rng.int(n), rng.int(n)) }
                if genes > 0, rng.unit() < 0.3 { let k = rng.int(genes); child.vertical[k].toggle() }
                if rng.unit() < 0.3 { child.aspect = min(o.maxAspect, max(o.minAspect, child.aspect * (0.85 + 0.3 * rng.unit()))) }
                next.append(child)
            }
            scored = next.map { ($0, fitness($0)) }
            scored.forEach { remember($0.1) }
        }
        let all = Array(archive.values)
        let front = all.filter { d in !all.contains { $0.objectives.dominates(d.objectives) } }
        return front.sorted { $0.score != $1.score ? $0.score < $1.score : key($0) < key($1) }
    }

    /// Parses "Kitchen-Dining, Hall-Living" into adjacency pairs and "Living:S, Bed:E" into facing requirements.
    public static func parseAdjacency(_ s: String) -> [(String, String)] {
        s.split(separator: ",").compactMap { p in
            let x = p.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
            return x.count == 2 && !x[0].isEmpty && !x[1].isEmpty ? (x[0], x[1]) : nil
        }
    }
    public static func parseFacing(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for p in s.split(separator: ",") {
            let x = p.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            if x.count == 2, ["N", "E", "S", "W"].contains(x[1].uppercased()) { out[x[0]] = x[1].uppercased() }
        }
        return out
    }
}
