// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Revision clouds (ANN-051 / ANN-052): freehand resampling, clouds attached to the objects they enclose (they move with
/// them) and the link between clouds and the revision table (each cloud carries the revision it belongs to).
public enum RevisionClouds {
    /// Entity props: revision label, attached object ids ("12,15") and the host anchor the cloud was last placed for.
    public static let revisionProp = "revision"
    public static let hostsProp = "revcloudOf"
    public static let anchorProp = "revcloudAnchor"

    /// Resamples a freehand path at `arcLength` steps (the cloud's arc chord length). The loop is closed when it ends
    /// within one arc of its start. Returns the vertices and whether the path closes.
    public static func freehand(_ path: [Vec2], arcLength: Double) -> (points: [Vec2], closed: Bool) {
        var pts: [Vec2] = []
        for p in path where pts.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { pts.append(p) }
        guard pts.count >= 2, arcLength > 1e-9 else { return (pts, false) }
        let closed = pts.count >= 3 && pts.first!.distance(to: pts.last!) <= arcLength
        if closed && pts.first!.distance(to: pts.last!) > 1e-9 { pts.append(pts[0]) }
        var out = [pts[0]]
        var carry = 0.0
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let len = a.distance(to: b)
            var t = arcLength - carry
            while t <= len + 1e-12 { out.append(a.lerp(b, t / len)); t += arcLength }
            carry = len - (t - arcLength)
        }
        if closed {
            // Drop the resampled copy of the start and a tiny last step.
            if let l = out.last, l.distance(to: out[0]) < arcLength * 0.5 { out.removeLast() }
        } else if let l = pts.last, out.last.map({ $0.distance(to: l) > arcLength * 0.25 }) ?? true { out.append(l) }
        return (out, closed)
    }

    /// Bounding rectangle (expanded by `margin`) of objects, used to enclose them in a cloud.
    public static func enclosure(_ ids: [EntityID], doc: ArchiDocument, margin: Double) -> [Vec2]? {
        let b = hostBounds(ids, doc: doc)
        guard !b.isEmpty else { return nil }
        let e = b.expanded(by: margin)
        return e.corners
    }
    static func hostBounds(_ ids: [EntityID], doc: ArchiDocument) -> BBox2 {
        var b = BBox2.empty
        for id in ids {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            else if let el = doc.element(id) { for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) } }
        }
        return b
    }
    /// Attaches a cloud entity to objects: it follows their moves from now on.
    public static func attach(_ e: inout Entity, to ids: [EntityID], doc: ArchiDocument) {
        let b = hostBounds(ids, doc: doc)
        guard !b.isEmpty else { return }
        e.props[hostsProp] = ids.map(String.init).joined(separator: ",")
        e.props[anchorProp] = DraftProps.text(b.center)
    }

    /// Moves attached clouds with their objects (the change of the hosts' bounds centre). Clouds whose objects are all
    /// deleted stay where they are. Returns true when something moved.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            guard let hs = doc.entities[i].props[hostsProp], let anchor = DraftProps.point(doc.entities[i].props[anchorProp]) else { continue }
            let ids = hs.split(separator: ",").compactMap { Int($0) }.filter { doc.entity($0) != nil || doc.element($0) != nil }
            let b = hostBounds(ids, doc: doc)
            guard !b.isEmpty else { continue }
            let d = b.center - anchor
            guard d.length > 1e-9 else { continue }
            doc.entities[i].geometry = GeometryOps.transform(doc.entities[i].geometry, .translation(d))
            doc.entities[i].props[anchorProp] = DraftProps.text(b.center)
            changed = true
        }
        return changed
    }

    /// Revision clouds per revision label.
    public static func byRevision(_ doc: ArchiDocument) -> [String: [EntityID]] {
        var out: [String: [EntityID]] = [:]
        for e in doc.entities { if let r = e.props[revisionProp], e.props["revcloud"] == "1" { out[r, default: []].append(e.id) } }
        return out
    }

    /// Makes sure the revision table (entity prop revisionTable = 1) lists every revision that has clouds; missing
    /// revisions are appended as rows (date and description left for the user). Returns the labels added.
    @discardableResult
    public static func syncTable(_ doc: inout ArchiDocument) -> [String] {
        guard let i = doc.entities.firstIndex(where: { $0.props["revisionTable"] == "1" }), case .table(var t) = doc.entities[i].geometry else { return [] }
        let have = Set(t.cells.dropFirst().compactMap { $0.first })
        let missing = byRevision(doc).keys.filter { !have.contains($0) }.sorted { a, b in
            if let x = Int(a), let y = Int(b) { return x < y }
            return a.count != b.count ? a.count < b.count : a < b
        }
        let cols = t.columnWidths.count
        for r in missing { t.cells.append([r] + Array(repeating: "", count: max(cols - 1, 0))) }
        if !missing.isEmpty { doc.entities[i].geometry = .table(t) }
        return missing
    }
}
