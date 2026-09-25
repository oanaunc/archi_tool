// Oanarina Archi Tool — GPL-3.0-or-later
// Parametric drawing: geometric constraints (GEOMCONSTRAINT, GC*), dimensional constraints (DIMCONSTRAINT), AUTOCONSTRAIN,
// DELCONSTRAINT, CONSTRAINTLIST and the PARAMETERS manager. Constraints live in the document (variable GEOMCONSTRAINTS) and
// are re-solved after every edit (DocumentUpdaters), so constrained geometry follows the objects the user moves.
import Foundation

extension Editor {
    /// Picks a constrainable point (endpoint, vertex, centre) near a picked point, optionally on another entity than `exclude`.
    func pickConstraintPoint(_ msg: String, exclude: EntityID? = nil) async throws -> CRef? {
        while true {
            guard let p = try await getPoint(msg).point else { return nil }
            var best: (CRef, Double)?
            for e in doc.entities where doc.isEditable(layer: e.layer) && Constraints.params(e.geometry) != nil {
                for (part, q) in Constraints.points(e.geometry) {
                    var d = q.distance(to: p)
                    if e.id == exclude { d += pickTolerance * 0.5 + 1e-9 }   // prefer another entity at a shared point
                    if d <= pickTolerance, d < (best?.1 ?? .infinity) { best = (CRef(e.id, part), d) }
                }
            }
            if let b = best, !(b.0.entity == exclude && Constraints.points(doc.entity(b.0.entity)!.geometry).count <= 1) { return b.0 }
            print("No constrainable point (line end, vertex or centre) found there.")
        }
    }
    /// Picks a line or polyline segment.
    func pickConstraintSegment(_ msg: String, keywords: [String] = []) async throws -> (CRef?, String?) {
        let isSeg: @MainActor (EntityID) -> Bool = { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .line?, .polyline?: return true; default: return false } }
        switch try await pickObject(msg, keywords: keywords, filter: isSeg) {
        case .pick(let pk):
            guard let g = doc.entity(pk.id)?.geometry, let part = Constraints.segmentPart(g, near: pk.point) else { return (nil, nil) }
            return (CRef(pk.id, part), nil)
        case .keyword(let k): return (nil, k)
        case .none: return (nil, nil)
        }
    }
    func pickConstraintCircle(_ msg: String) async throws -> CRef? {
        let isCirc: @MainActor (EntityID) -> Bool = { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .circle?, .arc?: return true; default: return false } }
        guard case .pick(let pk) = try await pickObject(msg, filter: isCirc) else { return nil }
        return CRef(pk.id, 0)
    }
    /// A segment or a circle/arc.
    func pickConstraintCurve(_ msg: String) async throws -> CRef? {
        let ok: @MainActor (EntityID) -> Bool = { [unowned self] id in
            switch self.doc.entity(id)?.geometry { case .line?, .polyline?, .circle?, .arc?: return true; default: return false } }
        guard case .pick(let pk) = try await pickObject(msg, filter: ok), let g = doc.entity(pk.id)?.geometry else { return nil }
        return CRef(pk.id, Constraints.segmentPart(g, near: pk.point) ?? 0)
    }

    /// Adds a constraint and solves, holding the entities in `hold` (the first object picked stays, the others move).
    /// Throws when the constraint over-constrains the drawing or cannot be satisfied.
    @discardableResult
    func addConstraint(_ c0: GeoConstraint, hold: Set<EntityID>) throws -> GeoConstraint {
        var set = ConstraintSet.load(doc)
        var c = c0
        c.id = set.nextID
        if !c.reference && Constraints.isRedundant(c, doc: doc) {
            throw CommandError.invalid("Adding this constraint would over-constrain the geometry (it is redundant with existing constraints).")
        }
        set.nextID += 1
        set.constraints.append(c)
        var d = doc
        set.save(&d)
        let others = Set(set.constraints.flatMap { $0.refs.map(\.entity) }).subtracting(c.refs.map(\.entity))
        let rep = Constraints.solve(&d, prefer: hold.union(others.subtracting(c.refs.map(\.entity))))
        if let r = rep, !r.converged { throw CommandError.invalid("The constraint cannot be satisfied with the existing constraints (residual \(fmt(r.residual, 6))).") }
        doc = d
        return c
    }

    func reportFreedom() {
        let f = Constraints.freedom(doc: doc)
        if f.parameters > 0 { print("Constrained geometry: \(f.dof) degree(s) of freedom left" + (f.dof == 0 ? " (fully constrained)." : ".")) }
    }
}

enum ConstraintCommands {
    static let geometricKeywords = ["Horizontal", "Vertical", "Perpendicular", "PArallel", "Tangent", "COincident", "CONcentric",
                                    "COLlinear", "Symmetric", "Equal", "Fix", "Midpoint", "OnCurve"]

    /// Asks for the operands of a geometric constraint and adds it.
    @MainActor static func geometric(_ kind: ConstraintKind, _ ed: Editor) async throws {
        var refs: [CRef] = []
        var hold: Set<EntityID> = []
        var anchor: Vec2? = nil
        var value: Double? = nil
        switch kind {
        case .coincident:
            guard let a = try await ed.pickConstraintPoint("Select first point") else { return }
            guard let b = try await ed.pickConstraintPoint("Select second point", exclude: a.entity) else { return }
            guard a != b else { throw CommandError.invalid("Select two different points.") }
            refs = [a, b]; hold = [a.entity]
        case .horizontal, .vertical:
            let (s, k) = try await ed.pickConstraintSegment("Select an object or", keywords: ["2Points"])
            if k == "2Points" {
                guard let a = try await ed.pickConstraintPoint("Select first point"), let b = try await ed.pickConstraintPoint("Select second point", exclude: a.entity) else { return }
                refs = [a, b]; hold = [a.entity]
            } else if let s = s { refs = [s] } else { return }
        case .parallel, .perpendicular, .collinear:
            guard let a = try await ed.pickConstraintSegment("Select first object").0 else { return }
            guard let b = try await ed.pickConstraintSegment("Select second object").0 else { return }
            guard a != b else { throw CommandError.invalid("Select two different segments.") }
            refs = [a, b]; hold = [a.entity]
        case .equal:
            guard let a = try await ed.pickConstraintCurve("Select first object") else { return }
            guard let b = try await ed.pickConstraintCurve("Select second object") else { return }
            let ga = ed.doc.entity(a.entity)!.geometry, gb = ed.doc.entity(b.entity)!.geometry
            let segA = Constraints.segment(ga, part: a.part) != nil && ({ if case .line = ga { return true }; if case .polyline = ga { return true }; return false })()
            let segB = Constraints.segment(gb, part: b.part) != nil && ({ if case .line = gb { return true }; if case .polyline = gb { return true }; return false })()
            guard segA == segB, a != b else { throw CommandError.invalid("Select two segments or two circles/arcs.") }
            refs = [a, b]; hold = [a.entity]
        case .fixed:
            guard let a = try await ed.pickConstraintPoint("Select point to fix") else { return }
            anchor = Constraints.point(ed.doc.entity(a.entity)!.geometry, part: a.part)
            refs = [a]; hold = [a.entity]
        case .concentric:
            guard let a = try await ed.pickConstraintCircle("Select first circle or arc"), let b = try await ed.pickConstraintCircle("Select second circle or arc") else { return }
            guard a.entity != b.entity else { throw CommandError.invalid("Select two different circles or arcs.") }
            refs = [a, b]; hold = [a.entity]
        case .tangent:
            guard let a = try await ed.pickConstraintCurve("Select first object"), let b = try await ed.pickConstraintCurve("Select second object") else { return }
            let ga = ed.doc.entity(a.entity)!.geometry, gb = ed.doc.entity(b.entity)!.geometry
            func isCirc(_ g: Geometry) -> Bool { if case .circle = g { return true }; if case .arc = g { return true }; return false }
            switch (isCirc(ga), isCirc(gb)) {
            case (false, true): refs = [a, b]
            case (true, false): refs = [b, a]
            case (true, true):
                refs = [a, b]
                let ca = DrawCommands.curve(ga)!, cb = DrawCommands.curve(gb)!
                if case .circle(let o1, let r1) = ca, case .circle(let o2, let r2) = cb { value = o1.distance(to: o2) < max(r1, r2) ? 1 : 0 }
            default: throw CommandError.invalid("Tangency needs a circle or arc.")
            }
            hold = [a.entity]
        case .pointOnCurve:
            guard let p = try await ed.pickConstraintPoint("Select point") else { return }
            guard let c = try await ed.pickConstraintCurve("Select curve (line, polyline segment, circle or arc)") else { return }
            guard c.entity != p.entity else { throw CommandError.invalid("Select a curve of another object.") }
            refs = [p, c]; hold = [c.entity]
        case .midpoint:
            guard let p = try await ed.pickConstraintPoint("Select point") else { return }
            guard let s = try await ed.pickConstraintSegment("Select line or polyline segment").0, s.entity != p.entity else { return }
            refs = [p, s]; hold = [s.entity]
        case .symmetric:
            guard let a = try await ed.pickConstraintPoint("Select first point"), let b = try await ed.pickConstraintPoint("Select second point", exclude: a.entity) else { return }
            guard let s = try await ed.pickConstraintSegment("Select symmetry line").0 else { return }
            refs = [a, b, s]; hold = [a.entity, s.entity]
        default: return
        }
        let c = try ed.addConstraint(GeoConstraint(id: 0, kind: kind, refs: refs, value: value, anchor: anchor), hold: hold)
        ed.print("\(kind.rawValue.capitalized) constraint #\(c.id) applied.")
        ed.reportFreedom()
    }

    static func kind(for keyword: String) -> ConstraintKind? {
        switch keyword {
        case "Horizontal": return .horizontal
        case "Vertical": return .vertical
        case "Perpendicular": return .perpendicular
        case "PArallel": return .parallel
        case "Tangent": return .tangent
        case "COincident": return .coincident
        case "CONcentric": return .concentric
        case "COLlinear": return .collinear
        case "Symmetric": return .symmetric
        case "Equal": return .equal
        case "Fix": return .fixed
        case "Midpoint": return .midpoint
        case "OnCurve": return .pointOnCurve
        default: return nil
        }
    }

    /// Asks for a value or expression ("500", "d1*2", "w", "width=d1+100"); returns (literal, expression, name, reference).
    @MainActor static func askValue(_ ed: Editor, current: Double, name: String, isAngle: Bool) async throws -> (Double?, String?, String, Bool) {
        let set = ConstraintSet.load(ed.doc)
        let def = "\(name)=\(fmt(current))"
        guard var t = try await ed.getWord("Enter value or expression, or [Reference]", defaultValue: def, keywords: ["Reference"]) else { return (current, nil, name, false) }
        if t == "Reference" { return (nil, nil, name, true) }
        var nm = name
        if let eq = t.firstIndex(of: "=") {
            let lhs = t[..<eq].trimmingCharacters(in: .whitespaces)
            if !lhs.isEmpty && lhs.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) && lhs.first!.isLetter { nm = lhs }
            t = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        if set.named(nm) != nil || (set.parameters.keys.contains { $0.caseInsensitiveCompare(nm) == .orderedSame }) {
            throw CommandError.invalid("The name \"\(nm)\" is already used.")
        }
        if let v = InputParser.parseNumber(t) {
            guard isAngle || v > 0 || !(v < 0) else { throw CommandError.invalid("Value must be positive.") }
            return (isAngle ? rad(v) : v, nil, nm, false)
        }
        guard Constraints.evaluate(t, set: set, doc: ed.doc) != nil else { throw CommandError.invalid("Cannot evaluate \"\(t)\" (unknown name or invalid expression).") }
        return (nil, t, nm, false)
    }

    @MainActor static func dimensional(_ mode: String, _ ed: Editor) async throws {
        var kind: ConstraintKind
        var refs: [CRef] = []
        var hold: Set<EntityID> = []
        var prefix = "d"
        switch mode {
        case "Linear", "Horizontal", "Vertical", "Aligned":
            var a: CRef? = nil, b: CRef? = nil
            if mode == "Aligned" {
                let first = try await ed.getPoint("Specify first constraint point or", keywords: ["Object"])
                if case .keyword("Object") = first {
                    guard let s = try await ed.pickConstraintSegment("Select line or polyline segment").0 else { return }
                    kind = .length; refs = [s]
                    break
                }
                guard let p = first.point else { return }
                a = nearestRef(ed, p)
            } else {
                a = try await ed.pickConstraintPoint("Specify first constraint point")
            }
            guard let aa = a else { throw CommandError.invalid("No constrainable point there.") }
            b = try await ed.pickConstraintPoint("Specify second constraint point", exclude: aa.entity)
            guard let bb = b, bb != aa else { return }
            let pa = Constraints.point(ed.doc.entity(aa.entity)!.geometry, part: aa.part)!, pb = Constraints.point(ed.doc.entity(bb.entity)!.geometry, part: bb.part)!
            var k: ConstraintKind = .distance
            switch mode {
            case "Horizontal": k = .horizontalDistance
            case "Vertical": k = .verticalDistance
            case "Linear": k = abs(pb.x - pa.x) >= abs(pb.y - pa.y) ? .horizontalDistance : .verticalDistance
            default: k = .distance
            }
            // Keep the stored value positive: order the points along the measured axis.
            let swap = (k == .horizontalDistance && pb.x < pa.x) || (k == .verticalDistance && pb.y < pa.y)
            refs = swap ? [bb, aa] : [aa, bb]
            kind = k; hold = [aa.entity]
        case "ANgular":
            guard let s1 = try await ed.pickConstraintSegment("Select first line").0, let s2 = try await ed.pickConstraintSegment("Select second line").0, s1 != s2 else { return }
            let g1 = Constraints.segment(ed.doc.entity(s1.entity)!.geometry, part: s1.part)!, g2 = Constraints.segment(ed.doc.entity(s2.entity)!.geometry, part: s2.part)!
            let a = Constraints.angleBetween(g1, g2)
            refs = a < 0 ? [s2, s1] : [s1, s2]
            kind = .angle; hold = [refs[0].entity]; prefix = "ang"
        case "Radius", "Diameter":
            guard let c = try await ed.pickConstraintCircle("Select arc or circle") else { return }
            refs = [c]; kind = mode == "Radius" ? .radius : .diameter; prefix = mode == "Radius" ? "rad" : "dia"
        case "RAtio", "Ratio", "DIfference", "Difference":
            guard let s1 = try await ed.pickConstraintSegment("Select first line (driven length)").0,
                  let s2 = try await ed.pickConstraintSegment("Select second line (reference length)").0, s1 != s2 else { return }
            kind = mode.uppercased().hasPrefix("R") ? .ratio : .lengthDifference
            refs = [s1, s2]; hold = [s2.entity]; prefix = kind == .ratio ? "ratio" : "diff"
            if kind == .lengthDifference, let m = Constraints.measure(GeoConstraint(id: 0, kind: kind, refs: refs), doc: ed.doc), m < 0 {
                refs = [s2, s1]; hold = [s1.entity]
            }
        default: return
        }
        let probe = GeoConstraint(id: 0, kind: kind, refs: refs)
        guard let cur = Constraints.measure(probe, doc: ed.doc) else { throw CommandError.invalid("Cannot measure the selected geometry.") }
        let set = ConstraintSet.load(ed.doc)
        let (lit, expr, name, reference) = try await askValue(ed, current: kind == .angle ? deg(cur) : cur, name: set.freshName(prefix), isAngle: kind == .angle)
        var c = GeoConstraint(id: 0, kind: kind, refs: refs, value: reference ? cur : lit, expression: expr, name: name, reference: reference)
        if c.value == nil && expr == nil { c.value = cur }
        c = try ed.addConstraint(c, hold: hold)
        let shown = Constraints.displayValue(c, set: ConstraintSet.load(ed.doc), doc: ed.doc) ?? 0
        ed.print("\(reference ? "Reference" : "Dimensional") constraint \(name) = \(fmt(shown))\(kind == .angle ? "°" : "")\(expr.map { " (\($0))" } ?? "") applied.")
        ed.reportFreedom()
    }

    @MainActor static func nearestRef(_ ed: Editor, _ p: Vec2) -> CRef? {
        var best: (CRef, Double)?
        for e in ed.doc.entities where ed.doc.isEditable(layer: e.layer) && Constraints.params(e.geometry) != nil {
            for (part, q) in Constraints.points(e.geometry) {
                let d = q.distance(to: p)
                if d <= ed.pickTolerance, d < (best?.1 ?? .infinity) { best = (CRef(e.id, part), d) }
            }
        }
        return best?.0
    }

    /// Converts dimensions (linear, aligned, radius, diameter, angular) into dimensional constraints on the geometry they measure.
    @MainActor static func convert(_ ed: Editor) async throws {
        let ids = try await ed.getEntitySelection("Select associative dimensions to convert")
        var n = 0
        for id in ids {
            guard case .dimension(let dm)? = ed.doc.entity(id)?.geometry, dm.points.count >= 2 else { continue }
            var kind: ConstraintKind, refs: [CRef] = []
            switch dm.kind {
            case .linear, .aligned:
                guard let a = nearestRef(ed, dm.points[0]) else { continue }
                var b: CRef? = nil
                var bd = Double.infinity
                for e in ed.doc.entities where Constraints.params(e.geometry) != nil {
                    for (part, q) in Constraints.points(e.geometry) where !(e.id == a.entity && part == a.part) {
                        let d = q.distance(to: dm.points[1]); if d <= ed.pickTolerance, d < bd { bd = d; b = CRef(e.id, part) }
                    }
                }
                guard let bb = b else { continue }
                let pa = dm.points[0], pb = dm.points[1]
                if dm.kind == .aligned { kind = .distance; refs = [a, bb] }
                else {
                    let r = dm.rotation ?? (abs(pb.x - pa.x) >= abs(pb.y - pa.y) ? 0 : .pi / 2)
                    kind = abs(sin(r)) < 0.5 ? .horizontalDistance : .verticalDistance
                    let swap = (kind == .horizontalDistance && pb.x < pa.x) || (kind == .verticalDistance && pb.y < pa.y)
                    refs = swap ? [bb, a] : [a, bb]
                }
            case .radius, .diameter:
                guard let c = ed.doc.entities.first(where: { e in
                    switch e.geometry { case .circle(let g): return g.center.isClose(dm.points[0], tol: ed.pickTolerance); case .arc(let g): return g.center.isClose(dm.points[0], tol: ed.pickTolerance); default: return false } }) else { continue }
                kind = dm.kind == .radius ? .radius : .diameter; refs = [CRef(c.id, 0)]
            default: continue
            }
            let probe = GeoConstraint(id: 0, kind: kind, refs: refs)
            guard let cur = Constraints.measure(probe, doc: ed.doc) else { continue }
            let set = ConstraintSet.load(ed.doc)
            var value = cur
            if let o = dm.textOverride, let v = InputParser.parseNumber(o) { value = v }
            let name = set.freshName(kind == .radius ? "rad" : kind == .diameter ? "dia" : "d")
            do {
                try ed.addConstraint(GeoConstraint(id: 0, kind: kind, refs: refs, value: value, name: name), hold: [refs[0].entity])
                ed.doc.remove(ids: [id]); n += 1
                ed.print("Converted dimension #\(id) to \(name) = \(fmt(value)).")
            } catch CommandError.invalid(let m) { ed.print("Dimension #\(id): \(m)") }
        }
        ed.print("\(n) dimension(s) converted.")
    }

    /// Infers constraints between the selected objects: coincident ends, tangency, horizontal/vertical, parallel, perpendicular.
    /// Constraint inference while drawing (CONSTRAINTINFER = 1): constrains new objects with themselves and the objects they touch.
    @MainActor static func inferConstraints(_ ed: Editor, newIDs: Set<EntityID>) {
        let distTol = ed.variableDouble("AUTOCONSTRAINDIST", max(ed.pickTolerance * 0.05, 1e-6))
        let newPts = newIDs.compactMap { ed.doc.entity($0) }.flatMap { Constraints.points($0.geometry).map(\.point) }
        guard !newPts.isEmpty else { return }
        var ids = newIDs
        for e in ed.doc.entities where !ids.contains(e.id) && Constraints.params(e.geometry) != nil {
            if Constraints.points(e.geometry).contains(where: { q in newPts.contains { $0.distance(to: q.point) <= distTol } }) { ids.insert(e.id) }
        }
        let n = autoConstrain(ed, ids: Array(ids), distTol: distTol, angTol: rad(ed.variableDouble("AUTOCONSTRAINANGLE", 1)), involving: newIDs)
        if n > 0 { ed.print("\(n) constraint(s) inferred.") }
    }

    @MainActor static func autoConstrain(_ ed: Editor, ids: [EntityID], distTol: Double, angTol: Double, involving: Set<EntityID>? = nil) -> Int {
        let ents = ids.compactMap { ed.doc.entity($0) }.filter { Constraints.params($0.geometry) != nil }
        var candidates: [(ConstraintKind, [CRef], Double?)] = []
        // Coincident ends (not centres), union-find so each cluster gets a chain of coincidences.
        var pts: [(CRef, Vec2)] = []
        for e in ents {
            switch e.geometry {
            case .circle: continue
            case .arc(let a): pts += [(CRef(e.id, 1), a.startPoint), (CRef(e.id, 2), a.endPoint)]
            default: for (part, p) in Constraints.points(e.geometry) { pts.append((CRef(e.id, part), p)) }
            }
        }
        var parent = Array(0..<pts.count)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in 0..<pts.count {
            for j in (i + 1)..<max(i + 1, pts.count) where pts[i].0.entity != pts[j].0.entity && pts[i].1.distance(to: pts[j].1) <= distTol {
                let a = find(i), b = find(j)
                if a != b { parent[b] = a; candidates.append((.coincident, [pts[i].0, pts[j].0], nil)) }
            }
        }
        // Segments.
        var segs: [(CRef, Vec2, Vec2)] = []
        for e in ents {
            switch e.geometry {
            case .line(let l): segs.append((CRef(e.id, 0), l.a, l.b))
            case .polyline(let p):
                let n = p.vertices.count
                for i in 0..<(p.closed ? n : n - 1) where abs(p.vertices[i].bulge) < 1e-12 { segs.append((CRef(e.id, i), p.vertices[i].p, p.vertices[(i + 1) % n].p)) }
            default: break
            }
        }
        // Tangency line–circle.
        for s in segs {
            for e in ents {
                let cc: (Vec2, Double)
                switch e.geometry { case .circle(let c): cc = (c.center, c.radius); case .arc(let a): cc = (a.center, a.radius); default: continue }
                let d = (s.2 - s.1).normalized
                guard d != .zero else { continue }
                if abs(abs(d.cross(cc.0 - s.1)) - cc.1) <= distTol { candidates.append((.tangent, [s.0, CRef(e.id, 0)], nil)) }
            }
        }
        var hv = Set<Int>()
        for (i, s) in segs.enumerated() {
            let a = normAngle((s.2 - s.1).angle).truncatingRemainder(dividingBy: .pi)
            if min(a, .pi - a) <= angTol { candidates.append((.horizontal, [s.0], nil)); hv.insert(i) }
            else if abs(a - .pi / 2) <= angTol { candidates.append((.vertical, [s.0], nil)); hv.insert(i) }
        }
        for i in 0..<segs.count where !hv.contains(i) {
            for j in (i + 1)..<max(i + 1, segs.count) where !hv.contains(j) {
                let u = (segs[i].2 - segs[i].1).normalized, v = (segs[j].2 - segs[j].1).normalized
                if abs(u.cross(v)) <= sin(angTol) { candidates.append((.parallel, [segs[i].0, segs[j].0], nil)) }
                else if abs(u.dot(v)) <= sin(angTol) { candidates.append((.perpendicular, [segs[i].0, segs[j].0], nil)) }
            }
        }
        var n = 0
        if let inv = involving { candidates = candidates.filter { $0.1.contains { inv.contains($0.entity) } } }
        for (k, refs, v) in candidates.prefix(400) {
            do { try ed.addConstraint(GeoConstraint(id: 0, kind: k, refs: refs, value: v), hold: [refs[0].entity]); n += 1 }
            catch { continue }
        }
        return n
    }

    static var all: [CommandDef] {
        var cmds: [CommandDef] = [
            CommandDef("GEOMCONSTRAINT", aliases: ["GCON", "GC"], category: "Parametric", summary: "Applies a geometric constraint: Horizontal, Vertical, Perpendicular, PArallel, Tangent, COincident, CONcentric, COLlinear, Symmetric, Equal, Fix, Midpoint, OnCurve.") { ed in
                guard let k = try await ed.getKeyword("Enter constraint type", geometricKeywords, defaultValue: "Horizontal"), let kind = kind(for: k) else { return }
                try await geometric(kind, ed)
            },
            CommandDef("DIMCONSTRAINT", aliases: ["DCON"], category: "Parametric", summary: "Applies a dimensional (driving) constraint: LInear/Horizontal/Vertical/Aligned distance, ANgular, Radius, Diameter, or Convert dimensions; values may be expressions of parameters.") { ed in
                guard let k = try await ed.getKeyword("Enter constraint option", ["LInear", "Horizontal", "Vertical", "Aligned", "ANgular", "Radius", "Diameter", "RAtio", "DIfference", "Convert"], defaultValue: "Aligned") else { return }
                if k == "Convert" { try await convert(ed); return }
                try await dimensional(k == "LInear" ? "Linear" : k, ed)
            },
            CommandDef("AUTOCONSTRAIN", aliases: ["AUTOC"], category: "Parametric", summary: "Infers and applies constraints (coincident, tangent, horizontal, vertical, parallel, perpendicular) to the selected objects within tolerances.") { ed in
                let ids = try await ed.getEntitySelection("Select objects")
                let distTol = ed.variableDouble("AUTOCONSTRAINDIST", max(ed.pickTolerance * 0.05, 1e-6))
                let angTol = rad(ed.variableDouble("AUTOCONSTRAINANGLE", 1))
                let n = autoConstrain(ed, ids: ids, distTol: distTol, angTol: angTol)
                ed.print("\(n) constraint(s) applied to \(ids.count) object(s).")
                ed.reportFreedom()
            },
            CommandDef("DELCONSTRAINT", aliases: ["DELCON"], category: "Parametric", summary: "Removes all geometric and dimensional constraints from the selected objects (or All).") { ed in
                var set = ConstraintSet.load(ed.doc)
                let before = set.constraints.count
                let s = Set(try await ed.getSelection("Select objects"))
                set.constraints.removeAll { $0.refs.contains { s.contains($0.entity) } }
                set.save(&ed.doc)
                ed.print("\(before - set.constraints.count) constraint(s) removed.")
            },
            CommandDef("CONSTRAINTBAR", aliases: ["CBAR", "CONSTRAINTGLYPHS", "SHOWCONSTRAINTS"], category: "Parametric",
                       summary: "Shows or hides constraint glyphs next to constrained objects in the plan [Show/Hide/Toggle] (CONSTRAINTBAR variable).") { ed in
                let k = try await ed.getKeyword("Constraint bars [Show/Hide/Toggle]", ["Show", "Hide", "Toggle"], defaultValue: "Toggle") ?? "Toggle"
                let on = k == "Show" ? true : (k == "Hide" ? false : !ConstraintGlyphs.isOn(ed.doc))
                ed.doc.setVariable(ConstraintGlyphs.variable, on ? "1" : "0")
                ed.print("Constraint bars \(on ? "shown" : "hidden").")
            },
            CommandDef("CONSTRAINTLIST", aliases: ["LISTCONSTRAINTS"], category: "Parametric", summary: "Lists the constraints (of the selected objects, or all) with their values and the remaining degrees of freedom.", modifies: false) { ed in
                let set = ConstraintSet.load(ed.doc)
                let sel = ed.selection
                let list = sel.isEmpty ? set.constraints : set.constraints.filter { $0.refs.contains { sel.contains($0.entity) } }
                if list.isEmpty { ed.print("No constraints."); return }
                for c in list {
                    let refs = c.refs.map { "#\($0.entity).\($0.part)" }.joined(separator: " ")
                    var line = "  #\(c.id) \(c.kind.rawValue) \(refs)"
                    if c.kind.isDimensional, let v = Constraints.displayValue(c, set: set, doc: ed.doc) {
                        line += "  \(c.name ?? "")=\(fmt(v))\(c.kind == .angle ? "°" : "")\(c.expression.map { " (\($0))" } ?? "")\(c.reference ? " [reference]" : "")"
                    }
                    ed.print(line)
                }
                let f = Constraints.freedom(doc: ed.doc)
                ed.print("\(list.count) constraint(s); \(f.dof) degree(s) of freedom on \(f.parameters) parameter(s).")
            },
            CommandDef("PARAMETERS", aliases: ["PARAM", "PARAMETERSMANAGER", "PARAMS"], category: "Parametric", summary: "Parameters manager: New/Edit/Delete/List user parameters and dimensional constraint expressions; geometry updates.") { ed in
                let k = try await ed.getKeyword("Enter an option", ["New", "Edit", "Delete", "List"], defaultValue: "List") ?? "List"
                var set = ConstraintSet.load(ed.doc)
                switch k {
                case "List":
                    for (n, e) in set.parameters.sorted(by: { $0.key < $1.key }) {
                        ed.print("  \(n) = \(e)\(InputParser.parseNumber(e) == nil ? " → \(fmt(Constraints.evaluate(e, set: set, doc: ed.doc) ?? .nan))" : "")")
                    }
                    for c in set.constraints where c.kind.isDimensional {
                        ed.print("  \(c.name ?? "#\(c.id)") = \(c.expression ?? fmt(Constraints.displayValue(c, set: set, doc: ed.doc) ?? 0))\(c.reference ? " [reference]" : "")")
                    }
                    if set.parameters.isEmpty && !set.constraints.contains(where: { $0.kind.isDimensional }) { ed.print("No parameters.") }
                    return
                case "New", "Edit":
                    guard let n = try await ed.getWord("Enter parameter name"), n.first?.isLetter == true, n.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { throw CommandError.invalid("Invalid name.") }
                    if k == "New", set.named(n) != nil || set.parameters.keys.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { throw CommandError.invalid("\"\(n)\" already exists.") }
                    guard let e = try await ed.getWord("Enter expression") else { return }
                    var trial = set
                    if let i = trial.constraints.firstIndex(where: { $0.name?.caseInsensitiveCompare(n) == .orderedSame }) {
                        guard !trial.constraints[i].reference else { throw CommandError.invalid("\(n) is a reference dimension (driven).") }
                        if let v = InputParser.parseNumber(e) { trial.constraints[i].expression = nil; trial.constraints[i].value = trial.constraints[i].kind == .angle ? rad(v) : v }
                        else { trial.constraints[i].expression = e }
                    } else {
                        let key = trial.parameters.keys.first { $0.caseInsensitiveCompare(n) == .orderedSame } ?? n
                        trial.parameters[key] = e
                    }
                    guard Constraints.evaluate(e, set: trial, doc: ed.doc) != nil else { throw CommandError.invalid("Cannot evaluate \"\(e)\" (unknown name, circular reference or invalid expression).") }
                    set = trial
                case "Delete":
                    guard let n = try await ed.getWord("Enter parameter name") else { return }
                    let lower = n.lowercased()
                    let used = set.constraints.contains { ($0.expression ?? "").lowercased().contains(lower) } || set.parameters.values.contains { $0.lowercased().contains(lower) }
                    if used { throw CommandError.invalid("\"\(n)\" is used by other expressions.") }
                    if let key = set.parameters.keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { set.parameters[key] = nil }
                    else if let i = set.constraints.firstIndex(where: { $0.name?.caseInsensitiveCompare(n) == .orderedSame }) { set.constraints.remove(at: i) }
                    else { throw CommandError.invalid("No parameter \"\(n)\".") }
                default: return
                }
                var d = ed.doc
                set.save(&d)
                if let r = Constraints.solve(&d), !r.converged { throw CommandError.invalid("The parameters cannot be satisfied (residual \(fmt(r.residual, 6))); nothing changed.") }
                ed.doc = d
            },
        ]
        // AutoCAD-style single-constraint commands.
        let singles: [(String, ConstraintKind, [String])] = [
            ("GCCOINCIDENT", .coincident, []), ("GCHORIZONTAL", .horizontal, []), ("GCVERTICAL", .vertical, []), ("GCPARALLEL", .parallel, ["GCPAR"]),
            ("GCPERPENDICULAR", .perpendicular, ["GCPERP"]), ("GCCOLLINEAR", .collinear, []), ("GCEQUAL", .equal, []), ("GCFIX", .fixed, []),
            ("GCCONCENTRIC", .concentric, []), ("GCTANGENT", .tangent, []), ("GCSYMMETRIC", .symmetric, []), ("GCMIDPOINT", .midpoint, []),
            ("GCPOINTONCURVE", .pointOnCurve, ["GCONCURVE"]),
        ]
        for (n, k, al) in singles {
            cmds.append(CommandDef(n, aliases: al, category: "Parametric", summary: "Applies the \(k.rawValue) geometric constraint.") { ed in try await geometric(k, ed) })
        }
        let dims: [(String, String)] = [("DCLINEAR", "Linear"), ("DCHORIZONTAL", "Horizontal"), ("DCVERTICAL", "Vertical"), ("DCALIGNED", "Aligned"),
                                        ("DCANGULAR", "ANgular"), ("DCRADIUS", "Radius"), ("DCDIAMETER", "Diameter"),
                                        ("DCRATIO", "RAtio"), ("DCDIFFERENCE", "DIfference")]
        for (n, m) in dims {
            cmds.append(CommandDef(n, category: "Parametric", summary: "Applies the \(m.lowercased()) dimensional constraint.") { ed in try await dimensional(m, ed) })
        }
        cmds.append(CommandDef("DCCONVERT", category: "Parametric", summary: "Converts dimensions into dimensional constraints.") { ed in try await convert(ed) })
        return cmds
    }
}
