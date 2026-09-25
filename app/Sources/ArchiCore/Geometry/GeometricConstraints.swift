// Oanarina Archi Tool — GPL-3.0-or-later
// Parametric geometric and dimensional constraints on 2D drafting entities (in the spirit of SolveSpace / CAD Sketcher /
// AutoCAD parametric drawing), solved with a damped, weighted minimum-norm Newton–Raphson (Gauss–Newton) iteration.
import Foundation

/// Kinds of constraints. Geometric kinds relate points, segments and circles; dimensional kinds carry a value.
public enum ConstraintKind: String, Codable, CaseIterable {
    // Geometric
    case coincident, horizontal, vertical, parallel, perpendicular, collinear, equal, fixed, concentric, tangent, pointOnCurve, midpoint, symmetric
    // Dimensional (value in drawing units; angles in radians)
    case distance, horizontalDistance, verticalDistance, length, angle, radius, diameter

    public var isDimensional: Bool {
        switch self { case .distance, .horizontalDistance, .verticalDistance, .length, .angle, .radius, .diameter: return true; default: return false }
    }
}

/// Reference to part of an entity. Its meaning depends on the constraint: a point (line 0/1 = start/end, circle/arc 0 = centre,
/// arc 1/2 = start/end point, polyline i = vertex i, point 0), a segment (line 0, polyline i = segment from vertex i),
/// or a whole circle/arc (part ignored).
public struct CRef: Codable, Hashable {
    public var entity: EntityID; public var part: Int
    public init(_ entity: EntityID, _ part: Int = 0) { self.entity = entity; self.part = part }
}

public struct GeoConstraint: Codable, Hashable {
    public var id: Int
    public var kind: ConstraintKind
    /// Operands in order (see `ConstraintKind` docs in `Constraints.arity`).
    public var refs: [CRef]
    /// Dimensional value (lengths in drawing units, angles in radians); `fixed` stores the anchor in `anchor`.
    public var value: Double?
    /// Expression driving the value (parameter names, other constraint names, arithmetic); nil = the literal `value`.
    public var expression: String?
    /// Name of a dimensional constraint (d1, ang1, rad1…), usable in other expressions.
    public var name: String?
    /// Reference (driven) dimension: reports the measurement, never drives geometry.
    public var reference: Bool
    public var anchor: Vec2?
    public init(id: Int, kind: ConstraintKind, refs: [CRef], value: Double? = nil, expression: String? = nil, name: String? = nil, reference: Bool = false, anchor: Vec2? = nil) {
        self.id = id; self.kind = kind; self.refs = refs; self.value = value; self.expression = expression; self.name = name; self.reference = reference; self.anchor = anchor
    }
    private enum K: String, CodingKey { case id, kind, refs, value, expression, name, reference, anchor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(Int.self, forKey: .id); kind = try c.decode(ConstraintKind.self, forKey: .kind)
        refs = try c.decodeIfPresent([CRef].self, forKey: .refs) ?? []
        value = try c.decodeIfPresent(Double.self, forKey: .value); expression = try c.decodeIfPresent(String.self, forKey: .expression)
        name = try c.decodeIfPresent(String.self, forKey: .name); reference = try c.decodeIfPresent(Bool.self, forKey: .reference) ?? false
        anchor = try c.decodeIfPresent(Vec2.self, forKey: .anchor)
    }
}

/// All constraints of a drawing, persisted as JSON in the document variable GEOMCONSTRAINTS.
public struct ConstraintSet: Codable, Hashable {
    public var constraints: [GeoConstraint] = []
    public var nextID = 1
    /// User parameters (name → expression), shared by dimensional constraint expressions.
    public var parameters: [String: String] = [:]
    /// Entity parameters after the last solve (used to hold objects the user just moved).
    public var snapshot: [String: [Double]] = [:]
    public init() {}
    private enum K: String, CodingKey { case constraints, nextID, parameters, snapshot }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        constraints = try c.decodeIfPresent([GeoConstraint].self, forKey: .constraints) ?? []
        nextID = try c.decodeIfPresent(Int.self, forKey: .nextID) ?? (constraints.map(\.id).max() ?? 0) + 1
        parameters = try c.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
        snapshot = try c.decodeIfPresent([String: [Double]].self, forKey: .snapshot) ?? [:]
    }

    public static let variable = "GEOMCONSTRAINTS"
    public static func load(_ doc: ArchiDocument) -> ConstraintSet {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8), let cs = try? JSONDecoder().decode(ConstraintSet.self, from: d) else { return ConstraintSet() }
        return cs
    }
    public func save(_ doc: inout ArchiDocument) {
        if constraints.isEmpty && parameters.isEmpty { doc.variables[ConstraintSet.variable] = nil; return }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(self), let s = String(data: d, encoding: .utf8) { doc.setVariable(ConstraintSet.variable, s) }
    }
    public func constraints(of id: EntityID) -> [GeoConstraint] { constraints.filter { $0.refs.contains { $0.entity == id } } }
    public func named(_ n: String) -> GeoConstraint? { constraints.first { $0.name?.caseInsensitiveCompare(n) == .orderedSame } }
    /// Next free name with a prefix (d1, d2…).
    public func freshName(_ prefix: String) -> String {
        var i = 1
        while named("\(prefix)\(i)") != nil || parameters.keys.contains(where: { $0.caseInsensitiveCompare("\(prefix)\(i)") == .orderedSame }) { i += 1 }
        return "\(prefix)\(i)"
    }
}

public struct SolveReport: Equatable {
    public var converged: Bool
    public var residual: Double
    public var iterations: Int
    /// Remaining degrees of freedom of the constrained entities.
    public var dof: Int
    public var parameters: Int
    public var equations: Int
    /// IDs of constraints whose equations are redundant with earlier ones (over-constrained).
    public var redundant: [Int]
}

/// Constraint evaluation and solving.
public enum Constraints {
    // MARK: Entity parameters
    /// Numeric parameters of a constrainable entity (nil for other geometry).
    public static func params(_ g: Geometry) -> [Double]? {
        switch g {
        case .point(let p): return [p.x, p.y]
        case .line(let l): return [l.a.x, l.a.y, l.b.x, l.b.y]
        case .circle(let c): return [c.center.x, c.center.y, c.radius]
        case .arc(let a): return [a.center.x, a.center.y, a.radius, a.start, a.end]
        case .polyline(let p): return p.vertices.flatMap { [$0.p.x, $0.p.y] }
        default: return nil
        }
    }
    public static func apply(_ v: [Double], to g: Geometry) -> Geometry {
        switch g {
        case .point: return .point(Vec2(v[0], v[1]))
        case .line: return .line(LineGeom(Vec2(v[0], v[1]), Vec2(v[2], v[3])))
        case .circle: return .circle(CircleGeom(Vec2(v[0], v[1]), abs(v[2])))
        case .arc: return .arc(ArcGeom(Vec2(v[0], v[1]), abs(v[2]), normAngle(v[3]), normAngle(v[4])))
        case .polyline(var p):
            for i in p.vertices.indices where 2 * i + 1 < v.count { p.vertices[i].p = Vec2(v[2 * i], v[2 * i + 1]) }
            return .polyline(p)
        default: return g
        }
    }

    enum Shape { case point, line, circle, arc, polyline(count: Int, closed: Bool) }
    static func shape(_ g: Geometry) -> Shape? {
        switch g {
        case .point: return .point
        case .line: return .line
        case .circle: return .circle
        case .arc: return .arc
        case .polyline(let p): return .polyline(count: p.vertices.count, closed: p.closed)
        default: return nil
        }
    }

    /// Accessors over a parameter vector.
    struct Access {
        var offset: [EntityID: Int]
        var shapes: [EntityID: Shape]
        func point(_ x: [Double], _ r: CRef) -> Vec2? {
            guard let o = offset[r.entity], let s = shapes[r.entity] else { return nil }
            switch s {
            case .point: return Vec2(x[o], x[o + 1])
            case .line: return r.part == 1 ? Vec2(x[o + 2], x[o + 3]) : Vec2(x[o], x[o + 1])
            case .circle: return Vec2(x[o], x[o + 1])
            case .arc:
                let c = Vec2(x[o], x[o + 1]), rad = x[o + 2]
                switch r.part { case 1: return c + Vec2.polar(rad, x[o + 3]); case 2: return c + Vec2.polar(rad, x[o + 4]); default: return c }
            case .polyline(let n, _):
                guard r.part >= 0, r.part < n else { return nil }
                return Vec2(x[o + 2 * r.part], x[o + 2 * r.part + 1])
            }
        }
        func segment(_ x: [Double], _ r: CRef) -> (Vec2, Vec2)? {
            guard let o = offset[r.entity], let s = shapes[r.entity] else { return nil }
            switch s {
            case .line: return (Vec2(x[o], x[o + 1]), Vec2(x[o + 2], x[o + 3]))
            case .polyline(let n, let closed):
                guard r.part >= 0, r.part < (closed ? n : n - 1) else { return nil }
                let j = (r.part + 1) % n
                return (Vec2(x[o + 2 * r.part], x[o + 2 * r.part + 1]), Vec2(x[o + 2 * j], x[o + 2 * j + 1]))
            default: return nil
            }
        }
        func circle(_ x: [Double], _ r: CRef) -> (Vec2, Double)? {
            guard let o = offset[r.entity], let s = shapes[r.entity] else { return nil }
            switch s { case .circle, .arc: return (Vec2(x[o], x[o + 1]), abs(x[o + 2])); default: return nil }
        }
    }

    // MARK: Residuals
    static func unit(_ v: Vec2) -> Vec2 { let l = v.length; return l < 1e-12 ? Vec2(1, 0) : v / l }

    /// Signed angle from segment a to segment b (radians, −π…π).
    static func angleBetween(_ a: (Vec2, Vec2), _ b: (Vec2, Vec2)) -> Double {
        let u = a.1 - a.0, v = b.1 - b.0
        return atan2(u.cross(v), u.dot(v))
    }

    /// Residual equations of one constraint (empty when its operands are invalid).
    static func residuals(_ c: GeoConstraint, _ x: [Double], _ A: Access, target: Double?) -> [Double]? {
        let r = c.refs
        func P(_ i: Int) -> Vec2? { i < r.count ? A.point(x, r[i]) : nil }
        func S(_ i: Int) -> (Vec2, Vec2)? { i < r.count ? A.segment(x, r[i]) : nil }
        func C(_ i: Int) -> (Vec2, Double)? { i < r.count ? A.circle(x, r[i]) : nil }
        switch c.kind {
        case .coincident:
            guard let p = P(0), let q = P(1) else { return nil }
            return [p.x - q.x, p.y - q.y]
        case .horizontal:
            if r.count >= 2, let p = P(0), let q = P(1) { return [p.y - q.y] }
            guard let s = S(0) else { return nil }
            return [s.0.y - s.1.y]
        case .vertical:
            if r.count >= 2, let p = P(0), let q = P(1) { return [p.x - q.x] }
            guard let s = S(0) else { return nil }
            return [s.0.x - s.1.x]
        case .parallel:
            guard let a = S(0), let b = S(1) else { return nil }
            return [unit(a.1 - a.0).cross(unit(b.1 - b.0))]
        case .perpendicular:
            guard let a = S(0), let b = S(1) else { return nil }
            return [unit(a.1 - a.0).dot(unit(b.1 - b.0))]
        case .collinear:
            guard let a = S(0), let b = S(1) else { return nil }
            let d = unit(a.1 - a.0)
            return [d.cross(b.0 - a.0), d.cross(b.1 - a.0)]
        case .equal:
            if let a = S(0), let b = S(1) { return [a.0.distance(to: a.1) - b.0.distance(to: b.1)] }
            if let a = C(0), let b = C(1) { return [a.1 - b.1] }
            return nil
        case .fixed:
            guard let p = P(0), let a = c.anchor else { return nil }
            return [p.x - a.x, p.y - a.y]
        case .concentric:
            guard let a = C(0), let b = C(1) else { return nil }
            return [a.0.x - b.0.x, a.0.y - b.0.y]
        case .tangent:
            if let s = S(0), let ci = C(1) {
                let d = unit(s.1 - s.0)
                return [abs(d.cross(ci.0 - s.0)) - ci.1]
            }
            if let a = C(0), let b = C(1) {
                let dd = a.0.distance(to: b.0)
                // Internal tangency when one circle was inside the other at creation (value = 1), else external.
                return [(c.value ?? 0) > 0.5 ? dd - abs(a.1 - b.1) : dd - (a.1 + b.1)]
            }
            return nil
        case .pointOnCurve:
            guard let p = P(0), r.count >= 2 else { return nil }
            if let s = A.segment(x, r[1]) { return [unit(s.1 - s.0).cross(p - s.0)] }
            if let ci = A.circle(x, r[1]) { return [p.distance(to: ci.0) - ci.1] }
            return nil
        case .midpoint:
            guard let p = P(0), r.count >= 2, let s = A.segment(x, r[1]) else { return nil }
            let m = (s.0 + s.1) / 2
            return [p.x - m.x, p.y - m.y]
        case .symmetric:
            guard let p = P(0), let q = P(1), let s = S(2) else { return nil }
            let d = unit(s.1 - s.0), m = (p + q) / 2
            return [d.cross(m - s.0), d.dot(q - p)]
        case .distance:
            guard let t = target, let p = P(0), let q = P(1) else { return nil }
            return [p.distance(to: q) - t]
        case .horizontalDistance:
            guard let t = target, let p = P(0), let q = P(1) else { return nil }
            return [(q.x - p.x) - t]
        case .verticalDistance:
            guard let t = target, let p = P(0), let q = P(1) else { return nil }
            return [(q.y - p.y) - t]
        case .length:
            guard let t = target else { return nil }
            if let s = S(0) { return [s.0.distance(to: s.1) - t] }
            if let o = A.offset[r[0].entity], case .arc? = A.shapes[r[0].entity] {
                return [abs(x[o + 2]) * normAngle(x[o + 4] - x[o + 3]) - t]
            }
            return nil
        case .angle:
            guard let t = target, let a = S(0), let b = S(1) else { return nil }
            var d = angleBetween(a, b) - t
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            return [d]
        case .radius:
            guard let t = target, let ci = C(0) else { return nil }
            return [ci.1 - t]
        case .diameter:
            guard let t = target, let ci = C(0) else { return nil }
            return [2 * ci.1 - t]
        }
    }

    /// Current measured value of a dimensional constraint (signed the way the constraint stores it).
    public static func measure(_ c: GeoConstraint, doc: ArchiDocument) -> Double? {
        guard let (x, A) = vector(doc, ids: Set(c.refs.map(\.entity))) else { return nil }
        var zero = c; zero.reference = false
        guard let r = residuals(zero, x, A, target: 0)?.first else { return nil }
        return r
    }

    // MARK: Parameter vector
    static func vector(_ doc: ArchiDocument, ids: Set<EntityID>) -> ([Double], Access)? {
        var x: [Double] = [], off: [EntityID: Int] = [:], shapes: [EntityID: Shape] = [:]
        for id in ids.sorted() {
            guard let e = doc.entity(id), let p = params(e.geometry), let s = shape(e.geometry) else { return nil }
            off[id] = x.count; shapes[id] = s; x += p
        }
        return (x, Access(offset: off, shapes: shapes))
    }

    // MARK: Expressions
    /// Evaluates a value expression: numbers, arithmetic, user parameters and names of other dimensional constraints.
    /// Angles typed in expressions are degrees for angle constraints (the caller converts).
    public static func evaluate(_ expr: String, set: ConstraintSet, doc: ArchiDocument, depth: Int = 0) -> Double? {
        if let v = InputParser.parseNumber(expr) { return v }
        guard depth < 16 else { return nil }
        var s = expr
        // Replace identifiers (longest first) with their values.
        var names: [(String, Double)] = []
        for (k, v) in set.parameters { if let x = evaluate(v, set: set, doc: doc, depth: depth + 1) { names.append((k, x)) } }
        for c in set.constraints where c.name != nil && c.kind.isDimensional {
            guard let n = c.name else { continue }
            if let v = displayValue(c, set: set, doc: doc, depth: depth + 1) { names.append((n, v)) }
        }
        names.sort { $0.0.count > $1.0.count }
        for (n, v) in names {
            s = replaceIdentifier(s, n, "(\(v))")
        }
        return CommandHelpers.evaluate(s)
    }
    static func replaceIdentifier(_ s: String, _ name: String, _ with: String) -> String {
        let chars = Array(s), n = Array(name.lowercased())
        var out = "", i = 0
        func isId(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        while i < chars.count {
            if i + n.count <= chars.count, String(chars[i..<(i + n.count)]).lowercased() == String(n),
               (i == 0 || !isId(chars[i - 1])), (i + n.count == chars.count || !isId(chars[i + n.count])),
               !(i + n.count < chars.count && chars[i + n.count] == "(") {
                out += with; i += n.count
            } else { out.append(chars[i]); i += 1 }
        }
        return out
    }
    /// Value shown to the user: lengths in units, angles in degrees.
    public static func displayValue(_ c: GeoConstraint, set: ConstraintSet, doc: ArchiDocument, depth: Int = 0) -> Double? {
        if c.reference { return measure(c, doc: doc).map { c.kind == .angle ? deg($0) : $0 } }
        if let e = c.expression, let v = evaluate(e, set: set, doc: doc, depth: depth) { return v }
        guard let v = c.value else { return nil }
        return c.kind == .angle ? deg(v) : v
    }
    /// Target value used by the solver (radians for angles).
    static func target(_ c: GeoConstraint, set: ConstraintSet, doc: ArchiDocument) -> Double? {
        guard c.kind.isDimensional else { return c.value }
        guard let v = displayValue(c, set: set, doc: doc) else { return nil }
        return c.kind == .angle ? rad(v) : v
    }

    // MARK: Solving
    /// Solves all driving constraints of the document in place. Entities changed since the last solve are held (weighted) so the
    /// rest of the sketch follows them. Returns nil when there is nothing to solve.
    @discardableResult
    public static func solve(_ doc: inout ArchiDocument, prefer moved: Set<EntityID>? = nil, maxIterations: Int = 100) -> SolveReport? {
        var set = ConstraintSet.load(doc)
        // Drop constraints on deleted or incompatible entities.
        let before = set.constraints.count
        set.constraints.removeAll { c in c.refs.contains { doc.entity($0.entity).flatMap { params($0.geometry) } == nil } }
        let driving = set.constraints.filter { !$0.reference }
        let ids = Set(driving.flatMap { $0.refs.map(\.entity) })
        guard !ids.isEmpty, let (x0, A) = vector(doc, ids: ids) else {
            if set.constraints.count != before { set.snapshot = [:]; set.save(&doc) }
            return nil
        }
        // Weights: moved entities (different from the snapshot) are held.
        var w = [Double](repeating: 1, count: x0.count)
        for id in ids {
            guard let o = A.offset[id], let e = doc.entity(id), let p = params(e.geometry) else { continue }
            let changed = moved.map { $0.contains(id) } ?? (set.snapshot["\(id)"].map { $0.count != p.count || zip($0, p).contains { abs($0 - $1) > 1e-9 } } ?? false)
            if changed { for k in 0..<p.count { w[o + k] = 1e8 } }
            // Angles of arcs and radii scale differently from coordinates; keep them movable but not preferred.
        }
        let targets = driving.map { target($0, set: set, doc: doc) }
        func F(_ x: [Double]) -> [Double] {
            var out: [Double] = []
            for (i, c) in driving.enumerated() { if let r = residuals(c, x, A, target: targets[i]) { out += r } }
            return out
        }
        let scale = max(1, x0.map { abs($0) }.max() ?? 1)
        let tol = 1e-10 * scale
        /// Newton iterations with per-parameter weights (infinite weight = frozen).
        func iterate(_ w: [Double]) -> ([Double], [Double], Int) {
            var x = x0, f = F(x0), it = 0
            var norm = f.map { $0 * $0 }.reduce(0, +).squareRoot()
            var lambda = 1e-9
            while it < maxIterations && (f.map { abs($0) }.max() ?? 0) > tol {
                it += 1
                let J = jacobian(F, x, f)
                guard let dx = minNormStep(J, f, w, lambda: lambda) else { break }
                var t = 1.0, accepted = false
                for _ in 0..<30 {
                    let xn = zip(x, dx).map { $0 + t * $1 }
                    let fn = F(xn)
                    let nn = fn.map { $0 * $0 }.reduce(0, +).squareRoot()
                    if nn < norm || nn <= tol { x = xn; f = fn; norm = nn; accepted = true; break }
                    t *= 0.5
                }
                if !accepted { lambda = lambda * 100 + 1e-6; if lambda > 1e6 { break } } else { lambda = max(lambda / 10, 1e-12) }
            }
            return (x, f, it)
        }
        func ok(_ f: [Double]) -> Bool { (f.map { abs($0) }.max() ?? 0) <= max(tol, 1e-7 * scale) }
        // First keep the held entities exactly where they are; if that cannot be solved, let them move a little.
        var (x, f, it) = iterate(w.map { $0 > 1 ? .infinity : $0 })
        if !ok(f) && w.contains(where: { $0 > 1 }) { (x, f, it) = iterate(w) }
        let converged = ok(f)
        let (rank, redundant) = rankAnalysis(driving, x, A, targets: targets)
        if converged {
            for id in ids {
                guard let o = A.offset[id], let i = doc.entityIndex(id), let p = params(doc.entities[i].geometry) else { continue }
                let nv = Array(x[o..<(o + p.count)])
                if zip(nv, p).contains(where: { abs($0 - $1) > 1e-12 }) { doc.entities[i].geometry = apply(nv, to: doc.entities[i].geometry) }
            }
        }
        // Refresh the snapshot of every constrained entity (so the next edit is detected against the solved state).
        var snap: [String: [Double]] = [:]
        for id in Set(set.constraints.flatMap { $0.refs.map(\.entity) }) { if let e = doc.entity(id), let p = params(e.geometry) { snap["\(id)"] = p } }
        set.snapshot = snap
        set.save(&doc)
        return SolveReport(converged: converged, residual: f.map { abs($0) }.max() ?? 0, iterations: it, dof: x.count - rank,
                           parameters: x.count, equations: f.count, redundant: redundant)
    }

    /// Runs the solver when constrained entities changed since the last solve (DocumentUpdaters). Returns true if the document changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard doc.variable(ConstraintSet.variable) != nil else { return false }
        let set = ConstraintSet.load(doc)
        var dirty = false
        for c in set.constraints {
            for r in c.refs {
                guard let e = doc.entity(r.entity), let p = params(e.geometry) else { dirty = true; break }
                if let s = set.snapshot["\(r.entity)"], s.count == p.count, !zip(s, p).contains(where: { abs($0 - $1) > 1e-9 }) { continue }
                dirty = true; break
            }
            if dirty { break }
        }
        guard dirty else { return false }
        let before = doc
        solve(&doc)
        return doc != before
    }

    static func jacobian(_ F: ([Double]) -> [Double], _ x: [Double], _ f0: [Double]) -> [[Double]] {
        let m = f0.count, n = x.count
        var J = [[Double]](repeating: [Double](repeating: 0, count: n), count: m)
        var xp = x
        for j in 0..<n {
            let h = 1e-7 * max(1, abs(x[j]))
            xp[j] = x[j] + h; let fp = F(xp)
            xp[j] = x[j] - h; let fm = F(xp)
            xp[j] = x[j]
            guard fp.count == m, fm.count == m else { continue }
            for i in 0..<m { J[i][j] = (fp[i] - fm[i]) / (2 * h) }
        }
        return J
    }

    /// Weighted minimum-norm Newton step: dx = W⁻¹Jᵀ (J W⁻¹ Jᵀ + λI)⁻¹ (−f).
    static func minNormStep(_ J: [[Double]], _ f: [Double], _ w: [Double], lambda: Double) -> [Double]? {
        let m = f.count, n = w.count
        guard m > 0 else { return [Double](repeating: 0, count: n) }
        var M = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        for i in 0..<m { for k in i..<m {
            var s = 0.0
            for j in 0..<n where w[j].isFinite { s += J[i][j] * J[k][j] / w[j] }
            M[i][k] = s; M[k][i] = s
        } }
        var diagMax = 0.0
        for i in 0..<m { diagMax = max(diagMax, M[i][i]) }
        for i in 0..<m { M[i][i] += lambda * max(diagMax, 1e-12) + 1e-14 }
        guard let y = solveLinear(M, f.map { -$0 }) else { return nil }
        var dx = [Double](repeating: 0, count: n)
        for j in 0..<n where w[j].isFinite { var s = 0.0; for i in 0..<m { s += J[i][j] * y[i] }; dx[j] = s / w[j] }
        return dx
    }

    /// Dense Gaussian elimination with partial pivoting; tiny pivots are regularised (least-squares-like for rank-deficient systems).
    static func solveLinear(_ A0: [[Double]], _ b0: [Double]) -> [Double]? {
        var A = A0, b = b0
        let n = b.count
        let big = A.flatMap { $0 }.map { abs($0) }.max() ?? 1
        for col in 0..<n {
            var piv = col
            for r in col..<n where abs(A[r][col]) > abs(A[piv][col]) { piv = r }
            if abs(A[piv][col]) < 1e-13 * max(big, 1e-30) { A[col][col] = 1e-13 * max(big, 1e-30); b[col] = 0; continue }
            if piv != col { A.swapAt(piv, col); b.swapAt(piv, col) }
            for r in (col + 1)..<max(col + 1, n) {
                let fct = A[r][col] / A[col][col]
                if fct == 0 { continue }
                for k in col..<n { A[r][k] -= fct * A[col][k] }
                b[r] -= fct * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for k in (r + 1)..<max(r + 1, n) { s -= A[r][k] * x[k] }
            x[r] = s / A[r][r]
            if !x[r].isFinite { return nil }
        }
        return x
    }

    /// Rank of the Jacobian and the constraints whose rows add no rank (redundant / over-constraining), in order.
    static func rankAnalysis(_ cs: [GeoConstraint], _ x: [Double], _ A: Access, targets: [Double?]) -> (Int, [Int]) {
        var basis: [(pivot: Int, v: [Double])] = []   // reduced rows, v[pivot] == 1 and 0 at the other pivots
        var redundant: [Int] = []
        let n = x.count
        for (i, c) in cs.enumerated() {
            let F: ([Double]) -> [Double] = { residuals(c, $0, A, target: targets[i]) ?? [] }
            let f0 = F(x)
            guard !f0.isEmpty else { continue }
            let J = jacobian(F, x, f0)
            var added = false
            for row in J {
                var v = row
                for b in basis {
                    let fct = v[b.pivot]
                    if fct != 0 { for k in 0..<n { v[k] -= fct * b.v[k] } }
                }
                let ref = row.map { abs($0) }.max() ?? 0
                guard let p = v.indices.max(by: { abs(v[$0]) < abs(v[$1]) }), abs(v[p]) > 1e-6 * max(ref, 1e-12) else { continue }
                let s = v[p]
                v = v.map { $0 / s }
                v[p] = 1
                for j in basis.indices where basis[j].v[p] != 0 {
                    let fct = basis[j].v[p]
                    for k in 0..<n { basis[j].v[k] -= fct * v[k] }
                    basis[j].v[p] = 0
                }
                basis.append((p, v)); added = true
            }
            if !added { redundant.append(c.id) }
        }
        return (basis.count, redundant)
    }

    /// Whether adding `c` to the document's driving constraints over-constrains it (its equations add no independent rows).
    public static func isRedundant(_ c: GeoConstraint, doc: ArchiDocument) -> Bool {
        let set = ConstraintSet.load(doc)
        let cs = set.constraints.filter { !$0.reference } + [c]
        let ids = Set(cs.flatMap { $0.refs.map(\.entity) })
        guard let (x, A) = vector(doc, ids: ids) else { return false }
        let targets = cs.map { target($0, set: set, doc: doc) }
        let (_, red) = rankAnalysis(cs, x, A, targets: targets)
        return red.contains(c.id)
    }

    /// Degrees of freedom left on the constrained entities.
    public static func freedom(doc: ArchiDocument) -> (dof: Int, parameters: Int) {
        let set = ConstraintSet.load(doc)
        let cs = set.constraints.filter { !$0.reference }
        let ids = Set(cs.flatMap { $0.refs.map(\.entity) })
        guard !ids.isEmpty, let (x, A) = vector(doc, ids: ids) else { return (0, 0) }
        let (rank, _) = rankAnalysis(cs, x, A, targets: cs.map { target($0, set: set, doc: doc) })
        return (x.count - rank, x.count)
    }

    // MARK: Picking helpers
    /// Constrainable points of an entity with their part numbers.
    public static func points(_ g: Geometry) -> [(part: Int, point: Vec2)] {
        switch g {
        case .point(let p): return [(0, p)]
        case .line(let l): return [(0, l.a), (1, l.b)]
        case .circle(let c): return [(0, c.center)]
        case .arc(let a): return [(0, a.center), (1, a.startPoint), (2, a.endPoint)]
        case .polyline(let p): return p.vertices.enumerated().map { ($0.offset, $0.element.p) }
        default: return []
        }
    }
    /// Segment of a line/polyline nearest to a point.
    public static func segmentPart(_ g: Geometry, near p: Vec2) -> Int? {
        switch g {
        case .line: return 0
        case .polyline(let pl):
            let n = pl.vertices.count
            let segs = pl.closed ? n : n - 1
            guard segs > 0 else { return nil }
            var best = (0, Double.infinity)
            for i in 0..<segs {
                let a = pl.vertices[i].p, b = pl.vertices[(i + 1) % n].p
                let d = GeometryOps.distance(point: p, segA: a, segB: b)
                if d < best.1 { best = (i, d) }
            }
            return best.0
        default: return nil
        }
    }
    public static func segment(_ g: Geometry, part: Int) -> (Vec2, Vec2)? {
        switch g {
        case .line(let l): return (l.a, l.b)
        case .polyline(let pl):
            let n = pl.vertices.count
            guard part >= 0, part < (pl.closed ? n : n - 1) else { return nil }
            return (pl.vertices[part].p, pl.vertices[(part + 1) % n].p)
        default: return nil
        }
    }
    public static func point(_ g: Geometry, part: Int) -> Vec2? { points(g).first { $0.part == part }?.point }
}
