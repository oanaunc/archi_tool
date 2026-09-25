// Oanarina Archi Tool — GPL-3.0-or-later
// Review and collaboration: drawing/model compare (diff of two documents by id and geometry, report and a colour-coded
// overlay document) and markups (comments with author, date, status, replies, linked view and elements) stored in the
// document itself as entities on the MARKUP layer.
import Foundation

// MARK: - Compare

public enum ChangeKind: String, Codable, CaseIterable { case added, removed, modified, unchanged }

public struct DocumentChange: Hashable {
    public var kind: ChangeKind
    /// Id in the new document (added/modified/unchanged) or the old one (removed).
    public var id: EntityID
    /// Id in the old document when different (renumbered objects).
    public var oldID: EntityID?
    /// "entity" or "element".
    public var object: String
    public var type: String
    public var layer: String
    public var level: Int?
    /// Changed aspects: geometry, layer, color, linetype, lineweight, props, level, material, name, id.
    public var fields: [String]
    public var bounds: BBox2
}

public struct DocumentDiff {
    public var changes: [DocumentChange]
    public var layersAdded: [String]
    public var layersRemoved: [String]
    public var levelsAdded: [String]
    public var levelsRemoved: [String]
    public func count(_ k: ChangeKind) -> Int { changes.filter { $0.kind == k }.count }
    public var differences: [DocumentChange] { changes.filter { $0.kind != .unchanged } }
    public var isIdentical: Bool { differences.isEmpty && layersAdded.isEmpty && layersRemoved.isEmpty && levelsAdded.isEmpty && levelsRemoved.isEmpty }

    public var report: String {
        var s = "Compare: \(count(.added)) added, \(count(.removed)) removed, \(count(.modified)) modified, \(count(.unchanged)) unchanged"
        if !layersAdded.isEmpty { s += "\nLayers added: " + layersAdded.joined(separator: ", ") }
        if !layersRemoved.isEmpty { s += "\nLayers removed: " + layersRemoved.joined(separator: ", ") }
        if !levelsAdded.isEmpty { s += "\nLevels added: " + levelsAdded.joined(separator: ", ") }
        if !levelsRemoved.isEmpty { s += "\nLevels removed: " + levelsRemoved.joined(separator: ", ") }
        for c in differences { s += "\n  \(c.kind.rawValue) \(c.type) #\(c.id)" + (c.fields.isEmpty ? "" : " (" + c.fields.joined(separator: ", ") + ")") + " on \(c.layer)" }
        return s
    }
    public var table: [[String]] {
        [["change", "object", "type", "id", "old_id", "layer", "level", "fields"]] + differences.map {
            [$0.kind.rawValue, $0.object, $0.type, "\($0.id)", $0.oldID.map { "\($0)" } ?? "", $0.layer, $0.level.map { "\($0)" } ?? "", $0.fields.joined(separator: " ")]
        }
    }
    public var csv: String { CSVText.make(table) }
}

public enum DocumentCompare {
    public static let layerNames: [ChangeKind: String] = [.added: "DIFF-ADDED", .removed: "DIFF-REMOVED", .modified: "DIFF-MODIFIED", .unchanged: "DIFF-UNCHANGED"]
    public static let layerColors: [ChangeKind: RGBA] = [.added: RGBA(0.1, 0.8, 0.2), .removed: RGBA(0.9, 0.15, 0.1), .modified: RGBA(0.96, 0.77, 0.09), .unchanged: RGBA(0.55, 0.55, 0.55)]
    public static let previousLayer = "DIFF-PREVIOUS"

    static func entityFields(_ a: Entity, _ b: Entity) -> [String] {
        var f: [String] = []
        if a.geometry != b.geometry { f.append("geometry") }
        if a.layer != b.layer { f.append("layer") }
        if a.color != b.color { f.append("color") }
        if a.linetype != b.linetype { f.append("linetype") }
        if a.lineweight != b.lineweight { f.append("lineweight") }
        if a.props.filter({ $0.key != "dxfHandle" }) != b.props.filter({ $0.key != "dxfHandle" }) { f.append("props") }
        return f
    }
    static func elementFields(_ a: BIMElement, _ b: BIMElement) -> [String] {
        var f: [String] = []
        if a.geometry != b.geometry { f.append("geometry") }
        if a.level != b.level { f.append("level") }
        if a.layer != b.layer { f.append("layer") }
        if a.material != b.material { f.append("material") }
        if a.name != b.name { f.append("name") }
        if a.props != b.props { f.append("props") }
        return f
    }

    /// Compares `old` with `new` by object id; with `matchGeometry`, an object removed under one id and added under
    /// another with the same geometry and layer (e.g. after an export/import round trip) counts as unchanged.
    public static func compare(_ old: ArchiDocument, _ new: ArchiDocument, matchGeometry: Bool = true) -> DocumentDiff {
        var changes: [DocumentChange] = []
        let oldE = Dictionary(old.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newE = Dictionary(new.entities.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldB = Dictionary(old.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newB = Dictionary(new.elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func eb(_ e: Entity, _ d: ArchiDocument) -> BBox2 { GeometryOps.bounds(e.geometry, doc: d) }
        var addedE: [Entity] = [], removedE: [Entity] = [], addedB: [BIMElement] = [], removedB: [BIMElement] = []
        for e in new.entities {
            if let o = oldE[e.id] {
                let f = entityFields(o, e)
                var b = eb(e, new); if f.contains("geometry") { b.add(eb(o, old)) }
                changes.append(DocumentChange(kind: f.isEmpty ? .unchanged : .modified, id: e.id, object: "entity", type: e.typeName, layer: e.layer, fields: f, bounds: b))
            } else { addedE.append(e) }
        }
        for e in old.entities where newE[e.id] == nil { removedE.append(e) }
        for el in new.elements {
            if let o = oldB[el.id] {
                let f = elementFields(o, el)
                var b = PlanRepresentation.bounds(el, doc: new); if f.contains("geometry") { b.add(PlanRepresentation.bounds(o, doc: old)) }
                changes.append(DocumentChange(kind: f.isEmpty ? .unchanged : .modified, id: el.id, object: "element", type: el.typeName, layer: el.layer, level: el.level, fields: f, bounds: b))
            } else { addedB.append(el) }
        }
        for el in old.elements where newB[el.id] == nil { removedB.append(el) }
        if matchGeometry {
            var pool = removedE
            addedE = addedE.filter { a in
                guard let i = pool.firstIndex(where: { $0.geometry == a.geometry && $0.layer == a.layer }) else { return true }
                let o = pool.remove(at: i)
                let f = entityFields(o, a).filter { $0 != "geometry" && $0 != "layer" }
                changes.append(DocumentChange(kind: f.isEmpty ? .unchanged : .modified, id: a.id, oldID: o.id, object: "entity", type: a.typeName, layer: a.layer, fields: ["id"] + f, bounds: eb(a, new)))
                return false
            }
            removedE = pool
            var poolB = removedB
            addedB = addedB.filter { a in
                // Hosted openings match on everything but the host id.
                func same(_ o: BIMElement) -> Bool {
                    if case .opening(var x) = o.geometry, case .opening(let y) = a.geometry { x.hostWall = y.hostWall; return x == y && o.level == a.level }
                    return o.geometry == a.geometry && o.level == a.level
                }
                guard let i = poolB.firstIndex(where: same) else { return true }
                let o = poolB.remove(at: i)
                let f = elementFields(o, a).filter { $0 != "geometry" && $0 != "level" }
                changes.append(DocumentChange(kind: f.isEmpty ? .unchanged : .modified, id: a.id, oldID: o.id, object: "element", type: a.typeName, layer: a.layer, level: a.level, fields: ["id"] + f,
                                              bounds: PlanRepresentation.bounds(a, doc: new)))
                return false
            }
            removedB = poolB
        }
        for e in addedE { changes.append(DocumentChange(kind: .added, id: e.id, object: "entity", type: e.typeName, layer: e.layer, fields: [], bounds: eb(e, new))) }
        for e in removedE { changes.append(DocumentChange(kind: .removed, id: e.id, object: "entity", type: e.typeName, layer: e.layer, fields: [], bounds: eb(e, old))) }
        for e in addedB { changes.append(DocumentChange(kind: .added, id: e.id, object: "element", type: e.typeName, layer: e.layer, level: e.level, fields: [], bounds: PlanRepresentation.bounds(e, doc: new))) }
        for e in removedB { changes.append(DocumentChange(kind: .removed, id: e.id, object: "element", type: e.typeName, layer: e.layer, level: e.level, fields: [], bounds: PlanRepresentation.bounds(e, doc: old))) }
        let rank: [ChangeKind: Int] = [.removed: 0, .added: 1, .modified: 2, .unchanged: 3]
        changes.sort { (rank[$0.kind]!, $0.object, $0.id) < (rank[$1.kind]!, $1.object, $1.id) }
        let ol = Set(old.layers.map(\.name)), nl = Set(new.layers.map(\.name))
        let ov = Set(old.levels.map(\.name)), nv = Set(new.levels.map(\.name))
        return DocumentDiff(changes: changes, layersAdded: nl.subtracting(ol).sorted(), layersRemoved: ol.subtracting(nl).sorted(),
                            levelsAdded: nv.subtracting(ov).sorted(), levelsRemoved: ov.subtracting(nv).sorted())
    }

    /// Overlay: the new document with every object moved to a DIFF-* layer coloured by its change (added green,
    /// removed red, modified yellow, unchanged grey), plus removed objects and the previous geometry of modified ones
    /// (DIFF-PREVIOUS, dashed red) copied from the old document with fresh ids. Original layers are kept in props "sourceLayer".
    public static func overlay(_ old: ArchiDocument, _ new: ArchiDocument, diff: DocumentDiff? = nil) -> ArchiDocument {
        let d = diff ?? compare(old, new)
        var out = new
        for (k, n) in layerNames {
            if let i = out.layerIndex(n) { out.layers[i].color = layerColors[k]! } else { out.layers.append(Layer(name: n, color: layerColors[k]!)) }
        }
        if out.layerIndex(previousLayer) == nil { out.layers.append(Layer(name: previousLayer, color: layerColors[.removed]!, linetype: out.linetype("Dashed") != nil ? "Dashed" : "Continuous")) }
        var kindOf: [String: ChangeKind] = [:]
        for c in d.changes where c.kind != .removed { kindOf["\(c.object)#\(c.id)"] = c.kind }
        for i in out.entities.indices {
            let k = kindOf["entity#\(out.entities[i].id)"] ?? .unchanged
            out.entities[i].props["sourceLayer"] = out.entities[i].layer
            out.entities[i].props["change"] = k.rawValue
            out.entities[i].layer = layerNames[k]!; out.entities[i].color = .byLayer
        }
        for i in out.elements.indices {
            let k = kindOf["element#\(out.elements[i].id)"] ?? .unchanged
            out.elements[i].props["sourceLayer"] = out.elements[i].layer
            out.elements[i].props["change"] = k.rawValue
            out.elements[i].layer = layerNames[k]!
        }
        // Old objects: removed ones and the previous state of modified geometry.
        var copyE: [(Entity, String)] = [], copyB: [(BIMElement, String)] = []
        for c in d.changes {
            let wantOld = c.kind == .removed || (c.kind == .modified && c.fields.contains("geometry"))
            guard wantOld else { continue }
            let oid = c.kind == .removed ? c.id : (c.oldID ?? c.id)
            let layer = c.kind == .removed ? layerNames[.removed]! : previousLayer
            if c.object == "entity", let e = old.entity(oid) { copyE.append((e, layer)) }
            if c.object == "element", let e = old.element(oid) { copyB.append((e, layer)) }
        }
        var idMap: [EntityID: EntityID] = [:]
        for (e, layer) in copyE {
            var n = e; n.id = out.allocateID(); n.props["sourceLayer"] = e.layer; n.props["change"] = layer == previousLayer ? "previous" : "removed"
            n.layer = layer; n.color = .byLayer
            out.entities.append(n)
        }
        for (el, _) in copyB { idMap[el.id] = out.allocateID() }
        for (el, layer) in copyB {
            var n = el; n.id = idMap[el.id]!; n.props["sourceLayer"] = el.layer; n.props["change"] = layer == previousLayer ? "previous" : "removed"; n.layer = layer
            if case .opening(var o) = n.geometry {
                // Hosts: a copied old wall, else the same wall id when it still exists in the new document.
                if let h = idMap[o.hostWall] { o.hostWall = h } else if out.element(o.hostWall) == nil { continue }
                n.geometry = .opening(o)
            }
            out.elements.append(n)
        }
        out.setVariable("COMPARESUMMARY", "\(d.count(.added)) added, \(d.count(.removed)) removed, \(d.count(.modified)) modified")
        return out
    }
}

// MARK: - Markups

public struct Markup: Hashable {
    public var id: String
    public var author: String
    public var date: String
    /// "open" or "resolved".
    public var status: String
    public var title: String
    public var comment: String
    public var elements: [EntityID]
    public var viewCenter: Vec2
    public var viewHeight: Double
    public var camera: Camera?
    public var level: Int?
    /// (author, date, text) replies in order.
    public var replies: [(author: String, date: String, text: String)]
    /// Entity ids of the cloud and the note.
    public var entityIDs: [EntityID]
    public var bounds: BBox2
    public var isResolved: Bool { status == "resolved" }

    public static func == (a: Markup, b: Markup) -> Bool { a.id == b.id && a.status == b.status && a.comment == b.comment && a.replies.count == b.replies.count && a.entityIDs == b.entityIDs }
    public func hash(into h: inout Hasher) { h.combine(id); h.combine(status); h.combine(comment) }
}

public enum Markups {
    public static let layer = "MARKUP"

    public static func now() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    /// Default author: USERNAME variable, the project author, else the login name.
    public static func author(_ doc: ArchiDocument) -> String {
        if let u = doc.variable("USERNAME"), !u.isEmpty { return u }
        if !doc.info.author.isEmpty { return doc.info.author }
        return NSUserName()
    }

    /// Revision cloud around a rectangle (closed polyline of bulged arcs).
    public static func cloud(_ a: Vec2, _ b: Vec2, arc: Double) -> PolylineGeom {
        let lo = Vec2(min(a.x, b.x), min(a.y, b.y)), hi = Vec2(max(a.x, b.x), max(a.y, b.y))
        let corners = [lo, Vec2(hi.x, lo.y), hi, Vec2(lo.x, hi.y)]
        var verts: [PolyVertex] = []
        for i in 0..<4 {
            let p = corners[i], q = corners[(i + 1) % 4]
            let n = max(1, Int((p.distance(to: q) / max(arc, 1e-9)).rounded()))
            for k in 0..<n { verts.append(PolyVertex(p + (q - p) * (Double(k) / Double(n)), bulge: -0.6)) }
        }
        return PolylineGeom(verts, closed: true)
    }

    /// Adds a markup (cloud + note) and returns its id. `rect` corners are in drawing units.
    @discardableResult
    public static func add(_ doc: inout ArchiDocument, rect: (Vec2, Vec2), title: String = "", comment: String, author: String? = nil, date: String? = nil,
                           elements: [EntityID] = [], camera: Camera? = nil, level: Int? = nil, id: String? = nil, status: String = "open") -> String {
        let mid = id ?? UUID().uuidString.lowercased()
        let a = rect.0, b = rect.1
        let size = max(abs(b.x - a.x), abs(b.y - a.y), 1)
        if doc.layerIndex(layer) == nil { doc.layers.append(Layer(name: layer, color: RGBA(0.93, 0.2, 0.2), lineweight: 0.35)) }
        var props: [String: String] = ["markup": mid, "author": author ?? Markups.author(doc), "date": date ?? now(), "status": status, "comment": comment]
        if !title.isEmpty { props["title"] = title }
        if !elements.isEmpty { props["elements"] = elements.map(String.init).joined(separator: ",") }
        let c = (a + b) / 2
        props["view"] = "\(fmt(c.x, 4)),\(fmt(c.y, 4)),\(fmt(max(abs(b.y - a.y), abs(b.x - a.x) / 1.6) * 1.4, 4))"
        if let cam = camera { props["camera"] = [cam.eye.x, cam.eye.y, cam.eye.z, cam.target.x, cam.target.y, cam.target.z, cam.fov, cam.orthographic ? 1 : 0].map { fmt($0, 4) }.joined(separator: ",") }
        if let l = level { props["level"] = "\(l)" }
        let cloud = Entity(layer: layer, geometry: .polyline(cloud(a, b, arc: size / 8)), props: props)
        _ = doc.add(cloud)
        let h = size / 25
        var noteProps = ["markupNote": mid]
        noteProps["status"] = status
        _ = doc.add(Entity(layer: layer, geometry: .text(TextGeom(position: Vec2(max(a.x, b.x) + h, max(a.y, b.y)), height: h, content: noteText(props), valign: .top, width: size * 1.5)), props: noteProps))
        return mid
    }

    static func noteText(_ p: [String: String]) -> String {
        var s = (p["status"] == "resolved" ? "✓ " : "") + (p["title"].map { $0 + ": " } ?? "") + (p["comment"] ?? "")
        s += "\n— \(p["author"] ?? "") \(String((p["date"] ?? "").prefix(10)))"
        var k = 1
        while let r = p["reply\(k)"] {
            let parts = r.components(separatedBy: "\u{1F}")
            if parts.count == 3 { s += "\n↳ \(parts[0]): \(parts[2])" }
            k += 1
        }
        return s
    }

    public static func list(_ doc: ArchiDocument) -> [Markup] {
        var out: [Markup] = []
        for e in doc.entities {
            guard let mid = e.props["markup"] else { continue }
            let p = e.props
            let view = (p["view"] ?? "").split(separator: ",").compactMap { Double($0) }
            var cam: Camera?
            let cv = (p["camera"] ?? "").split(separator: ",").compactMap { Double($0) }
            if cv.count >= 8 { cam = Camera(eye: Vec3(cv[0], cv[1], cv[2]), target: Vec3(cv[3], cv[4], cv[5]), fov: cv[6], orthographic: cv[7] != 0) }
            var replies: [(String, String, String)] = []
            var k = 1
            while let r = p["reply\(k)"] {
                let parts = r.components(separatedBy: "\u{1F}")
                if parts.count == 3 { replies.append((parts[0], parts[1], parts[2])) }
                k += 1
            }
            var ids = [e.id]
            if let note = doc.entities.first(where: { $0.props["markupNote"] == mid }) { ids.append(note.id) }
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            out.append(Markup(id: mid, author: p["author"] ?? "", date: p["date"] ?? "", status: p["status"] ?? "open", title: p["title"] ?? "", comment: p["comment"] ?? "",
                              elements: (p["elements"] ?? "").split(separator: ",").compactMap { Int($0) }, viewCenter: view.count >= 2 ? Vec2(view[0], view[1]) : b.center,
                              viewHeight: view.count >= 3 ? view[2] : b.height, camera: cam, level: p["level"].flatMap(Int.init), replies: replies, entityIDs: ids, bounds: b))
        }
        return out.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    public static func find(_ doc: ArchiDocument, _ key: String) -> Markup? {
        let all = list(doc)
        if let n = Int(key), n >= 1, n <= all.count { return all[n - 1] }
        return all.first { $0.id == key || $0.id.hasPrefix(key.lowercased()) }
    }

    static func update(_ doc: inout ArchiDocument, _ mid: String, _ f: (inout [String: String]) -> Void) -> Bool {
        guard let i = doc.entities.firstIndex(where: { $0.props["markup"] == mid }) else { return false }
        f(&doc.entities[i].props)
        let p = doc.entities[i].props
        if let j = doc.entities.firstIndex(where: { $0.props["markupNote"] == mid }), case .text(var t) = doc.entities[j].geometry {
            t.content = noteText(p); doc.entities[j].geometry = .text(t); doc.entities[j].props["status"] = p["status"]
        }
        return true
    }

    @discardableResult
    public static func setStatus(_ doc: inout ArchiDocument, _ mid: String, resolved: Bool, by author: String? = nil) -> Bool {
        let who = author ?? Markups.author(doc)
        return update(&doc, mid) { p in
            p["status"] = resolved ? "resolved" : "open"
            if resolved { p["resolvedBy"] = who; p["resolvedDate"] = now() } else { p["resolvedBy"] = nil; p["resolvedDate"] = nil }
        }
    }

    @discardableResult
    public static func reply(_ doc: inout ArchiDocument, _ mid: String, text: String, author: String? = nil, date: String? = nil) -> Bool {
        let who = author ?? Markups.author(doc)
        return update(&doc, mid) { p in
            var k = 1
            while p["reply\(k)"] != nil { k += 1 }
            p["reply\(k)"] = [who, date ?? now(), text.replacingOccurrences(of: "\u{1F}", with: " ")].joined(separator: "\u{1F}")
        }
    }

    @discardableResult
    public static func remove(_ doc: inout ArchiDocument, _ mid: String) -> Bool {
        let ids = Set(doc.entities.filter { $0.props["markup"] == mid || $0.props["markupNote"] == mid }.map(\.id))
        guard !ids.isEmpty else { return false }
        doc.remove(ids: ids)
        return true
    }

    public static func table(_ doc: ArchiDocument) -> [[String]] {
        [["#", "id", "status", "author", "date", "title", "comment", "elements", "replies"]] + list(doc).enumerated().map { i, m in
            ["\(i + 1)", m.id, m.status, m.author, m.date, m.title, m.comment, m.elements.map(String.init).joined(separator: " "), "\(m.replies.count)"]
        }
    }
}
