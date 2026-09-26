// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Equality constraint dimensions (ANN-046, Revit "EQ"): a chain of dimensions between three or more objects whose
/// spacing is kept equal. The first and last objects are the anchors; after every edit the objects in between are
/// moved (along the chain direction only) back to equal spacing, and the associative dimensions follow them.
///
/// Each dimension of a chain carries props `eqGroup` (group number), `eqRefs` ("id,id,…" in chain order), `eqDir`
/// (chain direction angle, radians) and `eqShow` ("EQ" label or "value").
public enum EqualityDimensions {
    public static let groupProp = "eqGroup"
    public static let refsProp = "eqRefs"
    public static let dirProp = "eqDir"
    public static let showProp = "eqShow"

    /// Reference point of an object for EQ spacing (line midpoint, circle/arc centre, point, insert, text).
    public static func refKey(_ g: Geometry) -> String? {
        switch g {
        case .line: return "2"
        case .arc: return "2"
        case .circle, .ellipse, .point, .text, .insert: return "0"
        case .polyline(let p) where !p.vertices.isEmpty: return "0"
        default: return nil
        }
    }
    public static func refPoint(_ g: Geometry) -> Vec2? { refKey(g).flatMap { DimAssociation.point(g, key: $0) } }

    public static func groups(_ doc: ArchiDocument) -> [Int: [Int]] {
        var out: [Int: [Int]] = [:]
        for (i, e) in doc.entities.enumerated() { if let g = e.props[groupProp].flatMap(Int.init) { out[g, default: []].append(i) } }
        return out
    }

    /// Creates an EQ chain: the objects are sorted along `direction`, the middle ones are respaced immediately, and one
    /// associative linear dimension per gap is added with its dimension line through `location`. Returns the new ids.
    @discardableResult
    public static func create(_ ids: [EntityID], direction dir0: Vec2, location: Vec2, doc: inout ArchiDocument, style: String? = nil) -> [EntityID] {
        let dir = dir0.lengthSquared > 1e-18 ? dir0.normalized : Vec2(1, 0)
        var refs = ids.compactMap { id -> (EntityID, Vec2)? in doc.entity(id).flatMap { refPoint($0.geometry) }.map { (id, $0) } }
        guard refs.count >= 3 else { return [] }
        refs.sort { $0.1.dot(dir) < $1.1.dot(dir) }
        let group = (groups(doc).keys.max() ?? 0) + 1
        let order = refs.map(\.0)
        respace(order, dir: dir, doc: &doc)
        var out: [EntityID] = []
        for k in 0..<(order.count - 1) {
            guard let a = doc.entity(order[k]), let b = doc.entity(order[k + 1]),
                  let pa = refPoint(a.geometry), let pb = refPoint(b.geometry), let ka = refKey(a.geometry), let kb = refKey(b.geometry) else { continue }
            var d = DimensionGeom(kind: .linear, points: [pa, pb, location], rotation: dir.angle, textOverride: "EQ", style: style ?? doc.currentDimStyle)
            d.rotation = dir.angle
            var e = Entity(geometry: .dimension(d))
            e.props[DimAssociation.prop] = "0=\(order[k]):\(ka);1=\(order[k + 1]):\(kb)"
            e.props[groupProp] = String(group)
            e.props[refsProp] = order.map(String.init).joined(separator: ",")
            e.props[dirProp] = fmt(dir.angle, 12)
            e.props[showProp] = "EQ"
            out.append(doc.add(e))
        }
        return out
    }

    /// Moves the objects between the first and the last to equal spacing along `dir`. Returns true when something moved.
    @discardableResult
    static func respace(_ order: [EntityID], dir: Vec2, doc: inout ArchiDocument) -> Bool {
        guard order.count >= 3, let f = doc.entity(order[0]).flatMap({ refPoint($0.geometry) }),
              let l = doc.entity(order[order.count - 1]).flatMap({ refPoint($0.geometry) }) else { return false }
        let s0 = f.dot(dir), s1 = l.dot(dir)
        let n = Double(order.count - 1)
        var changed = false
        for k in 1..<(order.count - 1) {
            guard let i = doc.entityIndex(order[k]), let p = refPoint(doc.entities[i].geometry) else { continue }
            let target = s0 + (s1 - s0) * Double(k) / n
            let delta = target - p.dot(dir)
            guard abs(delta) > 1e-9 else { continue }
            doc.entities[i].geometry = GeometryOps.transform(doc.entities[i].geometry, Transform2D.translation(dir * delta))
            changed = true
        }
        return changed
    }

    /// Displayed text of an EQ dimension: "EQ" or the measured value.
    public static func setDisplay(_ show: String, group: Int, doc: inout ArchiDocument) {
        for i in doc.entities.indices where doc.entities[i].props[groupProp] == String(group) {
            guard case .dimension(var d) = doc.entities[i].geometry else { continue }
            d.textOverride = show == "EQ" ? "EQ" : nil
            doc.entities[i].geometry = .dimension(d)
            doc.entities[i].props[showProp] = show == "EQ" ? "EQ" : "value"
        }
    }

    /// Removes the EQ relation of a group (the dimensions stay as ordinary associative dimensions showing values).
    public static func dissolve(_ group: Int, doc: inout ArchiDocument) {
        setDisplay("value", group: group, doc: &doc)
        for i in doc.entities.indices where doc.entities[i].props[groupProp] == String(group) {
            for k in [groupProp, refsProp, dirProp, showProp] { doc.entities[i].props[k] = nil }
        }
    }

    /// Keeps every EQ chain equally spaced (DocumentUpdaters, before the associative dimensions update).
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        let gs = groups(doc)
        guard !gs.isEmpty else { return false }
        var changed = false
        for (g, idx) in gs.sorted(by: { $0.key < $1.key }) {
            guard let first = idx.first else { continue }
            let p = doc.entities[first].props
            let order = (p[refsProp] ?? "").split(separator: ",").compactMap { Int($0) }
            let ang = p[dirProp].flatMap(Double.init) ?? 0
            if order.count < 3 || order.contains(where: { doc.entity($0) == nil }) { dissolve(g, doc: &doc); changed = true; continue }
            if respace(order, dir: Vec2.polar(1, ang), doc: &doc) { changed = true }
        }
        return changed
    }
}
