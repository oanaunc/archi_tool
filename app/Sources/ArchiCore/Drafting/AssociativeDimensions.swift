// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Associative dimensions: definition points attached to characteristic points of objects follow them.
/// Stored in prop "dimAssoc" as "index=entity:key;…" where key is a characteristic point of the object:
/// line 0 start, 1 end, 2 middle; arc 0 start, 1 end, 2 centre, 3 middle; circle 0 centre, 1–4 quadrants;
/// ellipse 0 centre; polyline vertex i; point / text / insert 0; "r<angle>" = point on a circle/arc at that angle
/// (radius and diameter dimensions keep their direction when the radius changes).
/// Unattached points (dimension line, text) move with the average displacement of the attached ones.
public enum DimAssociation {
    public static let prop = "dimAssoc"

    public static func keyPoints(_ g: Geometry) -> [(key: String, point: Vec2)] {
        switch g {
        case .point(let p): return [("0", p)]
        case .line(let l): return [("0", l.a), ("1", l.b), ("2", (l.a + l.b) / 2)]
        case .arc(let a): return [("0", a.startPoint), ("1", a.endPoint), ("2", a.center), ("3", a.midPoint)]
        case .circle(let c): return [("0", c.center)] + (0..<4).map { ("\($0 + 1)", c.center + Vec2.polar(c.radius, Double($0) * .pi / 2)) }
        case .ellipse(let e): return [("0", e.center)]
        case .polyline(let p): return p.vertices.enumerated().map { ("\($0.offset)", $0.element.p) }
        case .text(let t): return [("0", t.position)]
        case .insert(let i): return [("0", i.position)]
        default: return []
        }
    }
    public static func point(_ g: Geometry, key: String) -> Vec2? {
        // "f<fraction>": a point at that fraction of the curve length (points picked along an object).
        if key.hasPrefix("f"), let f = Double(key.dropFirst()) { return Modify.point(on: g, atFraction: f, doc: nil) }
        if key.hasPrefix("r"), let a = Double(key.dropFirst()) {
            switch g {
            case .circle(let c): return c.center + Vec2.polar(c.radius, a)
            case .arc(let c): return c.center + Vec2.polar(c.radius, a)
            default: return nil
            }
        }
        return keyPoints(g).first { $0.key == key }?.point
    }

    public static func parse(_ s: String?) -> [Int: (EntityID, String)] {
        var out: [Int: (EntityID, String)] = [:]
        for part in (s ?? "").split(separator: ";") {
            let kv = part.split(separator: "="), ref = kv.count == 2 ? kv[1].split(separator: ":") : []
            if kv.count == 2, ref.count == 2, let i = Int(kv[0]), let id = Int(ref[0]) { out[i] = (id, String(ref[1])) }
        }
        return out
    }
    static func text(_ m: [Int: (EntityID, String)]) -> String? {
        m.isEmpty ? nil : m.keys.sorted().map { "\($0)=\(m[$0]!.0):\(m[$0]!.1)" }.joined(separator: ";")
    }

    /// Nearest characteristic point of a drafting object within `tol` (excluding some objects).
    public static func findRef(_ p: Vec2, doc: ArchiDocument, tol: Double, exclude: Set<EntityID> = []) -> (EntityID, String)? {
        var best: (EntityID, String, Double)?
        for e in doc.entities where !exclude.contains(e.id) {
            if case .dimension = e.geometry { continue }
            for (k, q) in keyPoints(e.geometry) {
                let d = q.distance(to: p)
                if d <= tol, d < (best?.2 ?? .infinity) { best = (e.id, k, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }
    /// A circle or arc whose centre is at p (radius/diameter dimensions).
    static func circleAt(_ c: Vec2, doc: ArchiDocument, tol: Double) -> EntityID? {
        doc.entities.first { e in
            switch e.geometry { case .circle(let g): return g.center.isClose(c, tol: tol); case .arc(let g): return g.center.isClose(c, tol: tol); default: return false }
        }?.id
    }

    /// Attaches the definition points of a dimension to nearby objects. Returns the number of attached points.
    @discardableResult
    public static func associate(_ e: inout Entity, doc: ArchiDocument, tol: Double) -> Int {
        guard case .dimension(let d) = e.geometry else { return 0 }
        let p = DimensionRenderer.definitionPoints(d)
        var m: [Int: (EntityID, String)] = [:]
        switch d.kind {
        case .linear, .aligned:
            for i in 0..<min(2, p.count) { if let r = findRef(p[i], doc: doc, tol: tol) { m[i] = r } }
        case .radius, .diameter:
            if p.count >= 2, let c = circleAt(p[0], doc: doc, tol: tol) {
                m[0] = (c, "c"); m[1] = (c, "r\(fmt((p[1] - p[0]).angle, 12))")
            }
        case .angular:
            for i in 0..<min(3, p.count) { if let r = findRef(p[i], doc: doc, tol: tol) { m[i] = r } }
        case .arcLength:
            if p.count >= 3, let c = circleAt(p[0], doc: doc, tol: tol), let g = doc.entity(c)?.geometry, case .arc = g {
                m[0] = (c, "2"); m[1] = (c, "0"); m[2] = (c, "1")
            }
        case .ordinate:
            if let first = p.first, let r = findRef(first, doc: doc, tol: tol) { m[0] = r }
        }
        e.props[prop] = text(m)
        return m.count
    }

    /// Fraction key of the point of `g` nearest `p` ("f<fraction of length>").
    public static func fractionKey(_ g: Geometry, near p: Vec2) -> String? {
        guard let path = Modify.curvePath(g, doc: nil), path.length > 1e-12 else { return nil }
        return "f" + fmt(path.length(at: path.closest(p).s) / path.length, 12)
    }

    static func resolve(_ ref: (EntityID, String), doc: ArchiDocument) -> Vec2? {
        guard let g = doc.entity(ref.0)?.geometry else { return nil }
        // "i<id>": intersection of this line's carrier with another line's (vertex of an angular dimension between lines).
        if ref.1.hasPrefix("i"), let other = Int(ref.1.dropFirst()), case .line(let a) = g, case .line(let b)? = doc.entity(other)?.geometry {
            return GeometryOps.lineIntersection(a.a, a.b, b.a, b.b)
        }
        if ref.1 == "c" {
            switch g { case .circle(let c): return c.center; case .arc(let a): return a.center; default: return nil }
        }
        return point(g, key: ref.1)
    }

    /// Recomputes attached definition points. Returns the new geometry and the remaining attachments (nil when unchanged).
    static func recompute(_ e: Entity, doc: ArchiDocument) -> (Geometry, String?)? {
        guard case .dimension(let d) = e.geometry else { return nil }
        let m = parse(e.props[prop])
        guard !m.isEmpty else { return nil }
        var pts = d.points
        var alive = m
        var moves: [Vec2] = []
        for (i, ref) in m where i < pts.count {
            guard let q = resolve(ref, doc: doc) else { alive[i] = nil; continue }
            moves.append(q - pts[i]); pts[i] = q
        }
        let avg = moves.isEmpty ? Vec2.zero : moves.reduce(Vec2.zero, +) / Double(moves.count)
        let defs = DimensionRenderer.definitionCount(d.kind)
        if avg.length > 0 { for i in 0..<min(defs, pts.count) where m[i] == nil { pts[i] = pts[i] + avg } }
        // Jog markers (zero-radius pairs after the definition points) travel with the dimension.
        if avg.length > 0, pts.count > defs {
            var i = defs
            while i + 1 < pts.count { if pts[i] == pts[i + 1] { pts[i] = pts[i] + avg; pts[i + 1] = pts[i] }; i += 2 }
        }
        var nd = d; nd.points = pts
        let newText = text(alive)
        if nd == d && newText == e.props[prop] { return nil }
        return (.dimension(nd), newText)
    }

    /// Keeps associative dimensions attached (DocumentUpdaters). Returns true if the document changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props[prop] != nil {
            if let (g, t) = recompute(doc.entities[i], doc: doc) { doc.entities[i].geometry = g; doc.entities[i].props[prop] = t; changed = true }
        }
        return changed
    }
}

// MARK: - Associative leaders (ANN-047, ANN-049)

/// Leaders and multileaders whose arrowhead touches an object stay attached to it: prop "leaderAssoc" = "id:key" (a
/// characteristic point, see `DimAssociation.keyPoints`) or "id:f<fraction>" (a point at that fraction of the curve
/// length). When the object changes, the whole leader (arrowhead, landing, text) moves with the arrowhead's new location.
public enum LeaderAssociation {
    public static let prop = "leaderAssoc"

    /// Attaches a leader's arrowhead to the object under it (within `tol`). Returns true when attached.
    @discardableResult
    public static func associate(_ e: inout Entity, doc: ArchiDocument, tol: Double) -> Bool {
        guard case .leader(let l) = e.geometry, let head = l.points.first else { return false }
        if let r = DimAssociation.findRef(head, doc: doc, tol: tol, exclude: [e.id]) {
            e.props[prop] = "\(r.0):\(r.1)"; return true
        }
        var best: (Entity, Double)?
        for o in doc.entities where o.id != e.id {
            switch o.geometry { case .dimension, .leader, .text, .hatch, .table, .image: continue; default: break }
            let d = GeometryOps.distance(from: head, to: o.geometry, doc: doc)
            if d <= tol, d < (best?.1 ?? .infinity) { best = (o, d) }
        }
        guard let (o, _) = best, let path = Modify.curvePath(o.geometry, doc: doc), path.length > 1e-12 else { return false }
        let s = path.closest(head).s
        e.props[prop] = "\(o.id):f\(fmt(path.length(at: s) / path.length, 12))"
        return true
    }

    static func resolve(_ v: String, doc: ArchiDocument) -> Vec2?? {
        let parts = v.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = Int(parts[0]) else { return .some(nil) }
        guard let g = doc.entity(id)?.geometry else { return .some(nil) }
        if parts[1].hasPrefix("f"), let f = Double(parts[1].dropFirst()) { return .some(Modify.point(on: g, atFraction: f, doc: doc)) }
        return .some(DimAssociation.point(g, key: parts[1]))
    }

    /// Moves attached leaders with their objects; drops attachments to erased objects. Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            guard let v = doc.entities[i].props[prop], case .leader(var l) = doc.entities[i].geometry, let head = l.points.first else { continue }
            guard let r = resolve(v, doc: doc), let p = r else { doc.entities[i].props[prop] = nil; changed = true; continue }
            let d = p - head
            guard d.length > 1e-9 else { continue }
            l.points = l.points.map { $0 + d }
            doc.entities[i].geometry = .leader(l)
            changed = true
        }
        return changed
    }
}
