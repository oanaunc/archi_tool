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

    static func resolve(_ ref: (EntityID, String), doc: ArchiDocument) -> Vec2? {
        guard let g = doc.entity(ref.0)?.geometry else { return nil }
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
