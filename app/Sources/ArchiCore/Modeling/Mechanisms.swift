// Oanarina Archi Tool — GPL-3.0-or-later
// Linkages and mechanism simulation (M3D-088, in the spirit of SolveSpace): a named driving dimension of the
// constraint system is stepped through a range; after every step the constraint solver re-solves the sketch starting
// from the previous pose (so the mechanism stays on its assembly branch). The frames record a traced point and any
// other measured dimensions; the command draws the trace path, optional ghost poses, and stops at a lock-up.
import Foundation

public enum Mechanisms {
    public struct Frame: Hashable {
        public var value: Double
        public var converged: Bool
        public var point: Vec2?
        public var measures: [String: Double]
    }

    /// Steps the named dimensional constraint from `from` to `to` (drawing units; radians for angles) in `steps`
    /// steps. Stops at the first step the solver cannot satisfy (lock-up). Returns the frames and the last solved
    /// document (with the ghost poses' geometry available through `poses`).
    public static func simulate(_ doc0: ArchiDocument, driver: String, from: Double, to: Double, steps: Int, trace: CRef? = nil,
                                measure: [String] = [], keepPoses: Bool = false) -> (frames: [Frame], doc: ArchiDocument, poses: [[Entity]])? {
        var doc = doc0
        var set = ConstraintSet.load(doc)
        guard let di = set.constraints.firstIndex(where: { $0.name?.caseInsensitiveCompare(driver) == .orderedSame }), set.constraints[di].kind.isDimensional, steps >= 1 else { return nil }
        let ids = Set(set.constraints.flatMap { $0.refs.map(\.entity) })
        var frames: [Frame] = [], poses: [[Entity]] = []
        for i in 0...steps {
            let v = from + (to - from) * Double(i) / Double(steps)
            set = ConstraintSet.load(doc)
            set.constraints[di].value = v; set.constraints[di].expression = nil; set.constraints[di].reference = false
            set.save(&doc)
            let r = Constraints.solve(&doc)
            let ok = r?.converged ?? false
            var f = Frame(value: v, converged: ok, point: nil, measures: [:])
            if let t = trace, let e = doc.entity(t.entity) { f.point = Constraints.point(e.geometry, part: t.part) }
            let cs = ConstraintSet.load(doc)
            for n in measure { if let c = cs.named(n), let m = Constraints.measure(c, doc: doc) { f.measures[n] = m } }
            frames.append(f)
            if !ok { break }
            if keepPoses { poses.append(ids.sorted().compactMap { doc.entity($0) }) }
        }
        return (frames, doc, poses)
    }
}

enum MechanismCommands {
    static var all: [CommandDef] { [mechanism] }

    static var mechanism: CommandDef {
        CommandDef("MECHANISM", aliases: ["LINKAGE", "ANIMATEDIM", "DRIVEDIM"], category: "Parametric", summary: "Mechanism simulation: steps a named driving dimension (angles in degrees) through a range, re-solving the constraints each step; draws the path of a traced point, optional ghost poses, reports lock-up and the range of other dimensions.") { ed in
            let set = ConstraintSet.load(ed.doc)
            guard let name = try await ed.getWord("Driving dimension name", defaultValue: set.constraints.first { $0.name != nil && $0.kind.isDimensional }?.name),
                  let c = set.named(name), c.kind.isDimensional else { throw CommandError.invalid("No dimensional constraint with that name.") }
            let isAngle = c.kind == .angle
            let cur = Constraints.displayValue(c, set: set, doc: ed.doc) ?? c.value ?? 0
            let k = isAngle ? 180 / Double.pi : 1
            let a = try await ed.getReal("From value" + (isAngle ? " (degrees)" : ""), defaultValue: cur * k).value ?? cur * k
            let b = try await ed.getReal("To value" + (isAngle ? " (degrees)" : ""), defaultValue: cur * k + (isAngle ? 360 : 100)).value ?? cur * k
            let n = max(1, min(3600, try await ed.getInteger("Number of steps", defaultValue: 72) ?? 72))
            var trace: CRef? = nil
            if case .pick(let pk) = try await ed.pickObject("Select the object whose point to trace (Enter = none)", filter: { ed.doc.entity($0) != nil }) {
                let part = try await ed.getInteger("Point number (0 = start/centre, 1 = end…)", defaultValue: 1) ?? 1
                trace = CRef(pk.id, part)
            }
            let ghosts = max(0, try await ed.getInteger("Ghost poses to draw (0 = none)", defaultValue: 0) ?? 0)
            let keep = try await ed.getYesNo("Keep the final pose?", defaultValue: false)
            let others = set.constraints.compactMap(\.name).filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            guard let r = Mechanisms.simulate(ed.doc, driver: name, from: a / k, to: b / k, steps: n, trace: trace, measure: others, keepPoses: ghosts > 0) else { return }
            let ok = r.frames.filter(\.converged)
            if keep { ed.doc = r.doc }
            if ed.doc.layer(named: "MECHANISM") == nil { ed.doc.layers.append(Layer(name: "MECHANISM", color: RGBA(0.96, 0.77, 0.09), linetype: "Continuous", lineweight: 0.18, plot: false, description: "Mechanism traces")) }
            let pts = ok.compactMap(\.point)
            if pts.count >= 2 {
                var e = Entity(layer: "MECHANISM", geometry: .polyline(PolylineGeom(points: pts)))
                e.props["mechanismTrace"] = name
                ed.doc.add(e)
            }
            if ghosts > 0, !r.poses.isEmpty {
                let every = max(1, r.poses.count / ghosts)
                for (i, pose) in r.poses.enumerated() where i % every == 0 {
                    for pe in pose { var g = pe; g.id = 0; g.layer = "MECHANISM"; g.props = ["mechanismFrame": "\(i)"]; ed.doc.add(g) }
                }
            }
            let last = ok.last?.value ?? a / k
            if ok.count < r.frames.count { ed.print("Lock-up at \(fmt(r.frames.last!.value * k)): the mechanism moves from \(fmt(a)) to \(fmt(last * k)).") }
            else { ed.print("Full range \(fmt(a)) to \(fmt(b)) in \(n) steps.") }
            for o in others {
                let vals = ok.compactMap { $0.measures[o] }
                guard let lo = vals.min(), let hi = vals.max() else { continue }
                let ok2 = set.named(o)?.kind == .angle ? 180 / Double.pi : 1
                ed.print("  \(o): \(fmt(lo * ok2)) to \(fmt(hi * ok2))")
            }
        }
    }
}
