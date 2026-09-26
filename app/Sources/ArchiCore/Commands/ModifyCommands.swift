// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

extension Editor {
    /// Replaces an entity's geometry by one or more pieces (extra pieces copy its properties). Empty = delete.
    @discardableResult
    func replaceEntity(_ id: EntityID, with gs: [Geometry]) -> [EntityID] {
        guard let i = doc.entityIndex(id) else { return [] }
        if gs.isEmpty { doc.remove(ids: [id]); return [] }
        let proto = doc.entities[i]
        // Pieces of construction lines become rays or lines when they lose a far end (DRW-002/003).
        let far = ConstructionLines.farEnds(proto)
        func shaped(_ g: Geometry) -> (Geometry, String?) {
            guard !far.isEmpty else { return (g, proto.props[ConstructionLines.prop]) }
            let r = ConstructionLines.reclassify(g, farEnds: far)
            return (r.geometry, r.kind?.rawValue)
        }
        let first = shaped(gs[0])
        doc.entities[i].geometry = first.0
        if !far.isEmpty { doc.entities[i].props[ConstructionLines.prop] = first.1 }
        var out = [id]
        for g in gs.dropFirst() {
            var e = proto
            let sh = shaped(g)
            e.geometry = sh.0
            if !far.isEmpty { e.props[ConstructionLines.prop] = sh.1 }
            out.append(doc.add(e))
        }
        return out
    }

    /// Geometry of visible drawing entities (optionally only the given IDs), excluding one ID.
    func curveGeometries(_ ids: [EntityID]?, excluding: EntityID? = nil) -> [Geometry] {
        let pool = ids.map { Set($0) }
        return doc.entities.filter { e in
            e.id != excluding && doc.isVisible(layer: e.layer) && (pool?.contains(e.id) ?? true)
        }.compactMap { e in
            switch e.geometry { case .text, .table, .image, .solid, .hatch: return nil; default: return e.geometry }
        }
    }

    /// Integer or keyword answer.
    func getIntegerOrKeyword(_ msg: String, defaultValue: Int?, keywords: [String]) async throws -> (Int?, String?) {
        let r = await ask(InputRequest(msg, kinds: [.integer, .keyword], keywords: keywords, defaultValue: defaultValue.map { "\($0)" }))
        switch r {
        case .number(let d): return (Int(d.rounded()), nil)
        case .keyword(let k): return (nil, k)
        case .text(let t): if let k = InputParser.matchKeyword(t, keywords) { return (nil, k) }; return (Int(t), nil)
        case .enter: return (defaultValue, nil)
        case .cancel: throw CommandError.cancelled
        default: return (defaultValue, nil)
        }
    }
}

enum ModifyCommands {
    static var all: [CommandDef] { transforms + edits + curveEdits + arrays + properties }

    static func tangent(of g: Geometry, at p: Vec2, doc: ArchiDocument) -> Vec2 {
        var best: (Vec2, Double) = (Vec2(1, 0), .infinity)
        for pl in GeometryOps.tessellate(g, doc: doc) where pl.count > 1 {
            for i in 0..<(pl.count - 1) {
                let d = GeometryOps.distance(point: p, segA: pl[i], segB: pl[i + 1])
                if d < best.1 { best = ((pl[i + 1] - pl[i]).normalized, d) }
            }
        }
        return best.0
    }

    /// Own explode for polylines and block inserts (keeps entity layers/colors); falls back to Modify.explode.
    static func explodeEntity(_ e: Entity, doc: ArchiDocument) -> [Entity]? {
        switch e.geometry {
        case .insert(let ins):
            guard let b = doc.blocks[ins.block] else { return nil }
            let t = ins.transform * Transform2D.translation(-b.basePoint)
            var out: [Entity] = []
            for be in b.entities {
                var n = be
                if let tag = be.props["attdef"] {
                    guard case .text(var tx) = be.geometry else { continue }
                    tx.content = ins.attributes[tag] ?? be.props["default"] ?? ""
                    n.geometry = .text(tx); n.props = [:]
                }
                n.geometry = GeometryOps.transform(n.geometry, t)
                n.props["arrItem"] = nil
                if n.layer == "0" { n.layer = e.layer }
                if n.color == .byBlock { n.color = e.color }
                out.append(n)
            }
            return out
        case .polyline(let p):
            var out: [Entity] = []
            let v = p.vertices
            let segs = p.closed ? v.count : v.count - 1
            guard segs > 0 else { return nil }
            for i in 0..<segs {
                let a = v[i], b = v[(i + 1) % v.count]
                var n = e
                if abs(a.bulge) > 1e-9 { n.geometry = .arc(DrawCommands.arcFromBulge(a.p, b.p, a.bulge)) }
                else { guard a.p.distance(to: b.p) > 1e-12 else { continue }; n.geometry = .line(LineGeom(a.p, b.p)) }
                out.append(n)
            }
            return out
        default:
            guard let gs = Modify.explode(e.geometry, doc: doc) else { return nil }
            return gs.map { var n = e; n.geometry = $0; return n }
        }
    }

    /// Fillets (radius > 0) or chamfers (d2 != nil) every corner between straight segments of a polyline.
    static func filletPolyline(_ pl: PolylineGeom, radius r: Double, chamfer: (Double, Double)? = nil) -> (PolylineGeom, Int) {
        let v = pl.vertices, n = v.count
        guard n >= 3 else { return (pl, 0) }
        var out: [PolyVertex] = []
        var count = 0
        for i in 0..<n {
            let isEnd = !pl.closed && (i == 0 || i == n - 1)
            let prev = v[(i - 1 + n) % n], cur = v[i], next = v[(i + 1) % n]
            if isEnd || abs(prev.bulge) > 1e-9 || abs(cur.bulge) > 1e-9 { out.append(cur); continue }
            let d1 = (cur.p - prev.p), d2 = (next.p - cur.p)
            let l1 = d1.length, l2 = d2.length
            guard l1 > 1e-9, l2 > 1e-9 else { out.append(cur); continue }
            let u1 = d1 / l1, u2 = d2 / l2
            let turn = atan2(u1.cross(u2), u1.dot(u2))
            guard abs(turn) > 1e-6, abs(turn) < .pi - 1e-6 else { out.append(cur); continue }
            if let ch = chamfer {
                guard ch.0 <= l1 / 2 + 1e-9, ch.1 <= l2 / 2 + 1e-9, ch.0 > 0 || ch.1 > 0 else { out.append(cur); continue }
                out.append(PolyVertex(cur.p - u1 * ch.0)); out.append(PolyVertex(cur.p + u2 * ch.1)); count += 1
                continue
            }
            let t = r * tan(abs(turn) / 2)
            guard r > 0, t <= l1 / 2 + 1e-9, t <= l2 / 2 + 1e-9 else { out.append(cur); continue }
            out.append(PolyVertex(cur.p - u1 * t, bulge: tan(turn / 4)))
            out.append(PolyVertex(cur.p + u2 * t, bulge: 0))
            count += 1
        }
        var res = pl; res.vertices = out
        return (res, count)
    }

    static func stretchElement(_ g: BIMGeometry, box: BBox2, d: Vec2) -> BIMGeometry {
        func mv(_ p: Vec2) -> Vec2 { box.contains(p) ? p + d : p }
        switch g {
        case .wall(var w): w.start = mv(w.start); w.end = mv(w.end); return .wall(w)
        case .beam(var b): b.start = mv(b.start); b.end = mv(b.end); return .beam(b)
        case .curtainWall(var c): c.start = mv(c.start); c.end = mv(c.end); return .curtainWall(c)
        case .gridLine(var gl): gl.start = mv(gl.start); gl.end = mv(gl.end); return .gridLine(gl)
        case .slab(var s): s.boundary = s.boundary.map(mv); s.holes = s.holes.map { $0.map(mv) }; return .slab(s)
        case .roof(var r): r.boundary = r.boundary.map(mv); return .roof(r)
        case .space(var s): s.boundary = s.boundary.map(mv); return .space(s)
        case .railing(var r): r.path = r.path.map(mv); return .railing(r)
        case .column(var c): c.position = mv(c.position); return .column(c)
        case .component(var c): c.position = mv(c.position); return .component(c)
        case .stair(var s): s.start = mv(s.start); return .stair(s)
        case .opening: return g
        }
    }

    // MARK: - MOVE / COPY / ROTATE / SCALE / MIRROR / ALIGN / STRETCH
    static var transforms: [CommandDef] { [
        CommandDef("MOVE", aliases: ["M"], category: "Modify", summary: "Moves objects a specified distance in a specified direction.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let a = try await ed.getPoint("Specify base point", keywords: ["Displacement"])
            var t: Transform2D
            switch a {
            case .point(let b):
                // Space (or Turn90) turns the moved objects 90° about the destination point while dragging (MOD-029).
                let (s, rot) = try await ed.getRotatablePoint("Specify second point or <use first point as displacement>", base: b) { c, r in
                    ed.transformedPreview(ids, Editor.dragTransform(from: b, to: c, rotation: r)) }
                t = s.point.map { Editor.dragTransform(from: b, to: $0, rotation: rot) } ?? .translation(b)
            case .keyword:
                t = .translation(try await ed.requirePoint("Specify displacement", base: .zero) { c in ed.transformedPreview(ids, .translation(c)) })
            default: return
            }
            ed.transformObjects(ids, t, copy: false)
            ed.selection = []
            ed.print("\(ids.count) object(s) moved.")
        },
        CommandDef("COPY", aliases: ["CO", "CP"], category: "Modify", summary: "Copies objects (multiple copies, or a linear array).") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let a = try await ed.getPoint("Specify base point", keywords: ["Displacement"])
            var base: Vec2
            switch a {
            case .point(let p): base = p
            case .keyword:
                let d = try await ed.requirePoint("Specify displacement", base: .zero)
                ed.transformObjects(ids, .translation(d), copy: true); ed.selection = []; return
            default: return
            }
            var batches: [[EntityID]] = []
            while true {
                let b = base
                let (s, rot) = try await ed.getRotatablePoint("Specify second point", base: base, keywords: batches.isEmpty ? ["Array"] : ["Array", "Exit", "Undo"]) { c, r in
                    ed.transformedPreview(ids, Editor.dragTransform(from: b, to: c, rotation: r)) }
                switch s {
                case .point(let p): batches.append(ed.transformObjects(ids, Editor.dragTransform(from: base, to: p, rotation: rot), copy: true))
                case .keyword("Array"):
                    guard let n = try await ed.getInteger("Enter number of items to array", defaultValue: 3), n >= 2, n <= 10000 else { ed.print("Enter 2 or more items."); continue }
                    var fit = false
                    var s2 = try await ed.getPoint("Specify second point", base: base, keywords: ["Fit"])
                    if s2 == .keyword("Fit") { fit = true; s2 = try await ed.getPoint("Specify second point", base: base) }
                    guard let p = s2.point else { continue }
                    let step = fit ? (p - base) / Double(n - 1) : (p - base)
                    var batch: [EntityID] = []
                    for k in 1..<n { batch += ed.transformObjects(ids, .translation(step * Double(k)), copy: true) }
                    batches.append(batch)
                case .keyword("Undo"): if let l = batches.popLast() { ed.doc.remove(ids: Set(l)) }
                default: ed.selection = []; return
                }
            }
        },
        CommandDef("ROTATE", aliases: ["RO"], category: "Modify", summary: "Rotates objects around a base point.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let base = try await ed.requirePoint("Specify base point")
            var copy = false
            var angle: Double = rad(ed.variableDouble("ROTATEANG", 0))
            while true {
                let a = try await ed.getAngle("Specify rotation angle", base: base, defaultValue: angle, keywords: ["Copy", "Reference"]) { c in ed.transformedPreview(ids, .rotation((c - base).angle, around: base)) }
                switch a {
                case .value(let v): angle = v
                case .keyword("Copy"): copy = true; ed.print("Rotating a copy of the selected objects."); continue
                case .keyword("Reference"):
                    let ref = try await ed.getAngle("Specify the reference angle", base: base, defaultValue: 0).value ?? 0
                    let new = try await ed.getAngle("Specify the new angle", base: base) { c in ed.transformedPreview(ids, .rotation((c - base).angle - ref, around: base)) }.value ?? ref
                    angle = new - ref
                default: return
                }
                break
            }
            ed.doc.setVariable("ROTATEANG", fmt(deg(angle)))
            ed.transformObjects(ids, .rotation(angle, around: base), copy: copy)
            ed.selection = []
        },
        CommandDef("SCALE", aliases: ["SC"], category: "Modify", summary: "Enlarges or reduces objects around a base point.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let base = try await ed.requirePoint("Specify base point")
            var copy = false
            var factor = 1.0
            while true {
                let a = try await ed.getDistance("Specify scale factor", base: base, defaultValue: 1, keywords: ["Copy", "Reference"]) { c in
                    let f = c.distance(to: base); return f > 1e-9 ? ed.transformedPreview(ids, .scale(f, f, around: base)) : [] }
                switch a {
                case .value(let v): factor = v
                case .keyword("Copy"): copy = true; continue
                case .keyword("Reference"):
                    let ref = try await ed.getPositive("Specify reference length", defaultValue: 1)
                    let new = try await ed.getPositive("Specify new length", base: base, defaultValue: ref)
                    factor = new / ref
                default: return
                }
                break
            }
            guard factor > 1e-12, factor.isFinite else { throw CommandError.invalid("Scale factor must be positive.") }
            ed.transformObjects(ids, .scale(factor, factor, around: base), copy: copy)
            ed.selection = []
        },
        CommandDef("MIRROR", aliases: ["MI"], category: "Modify", summary: "Creates a mirrored copy of objects.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let p1 = try await ed.requirePoint("Specify first point of mirror line")
            let p2 = try await ed.requirePoint("Specify second point of mirror line", base: p1) { c in c.distance(to: p1) > 1e-9 ? ed.transformedPreview(ids, .mirror(p1, c)) : [] }
            guard p1.distance(to: p2) > 1e-9 else { throw CommandError.invalid("Mirror line points coincide.") }
            let erase = try await ed.getYesNo("Erase source objects?", defaultValue: false)
            ed.transformObjects(ids, .mirror(p1, p2), copy: !erase)
            ed.selection = []
        },
        CommandDef("ALIGN", aliases: ["AL"], category: "Modify", summary: "Aligns objects with other objects using source/destination point pairs.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let s1 = try await ed.requirePoint("Specify first source point")
            let d1 = try await ed.requirePoint("Specify first destination point", base: s1)
            guard let s2 = try await ed.getPoint("Specify second source point (Enter for move only)").point else {
                ed.transformObjects(ids, .translation(d1 - s1), copy: false); ed.selection = []; return
            }
            let d2 = try await ed.requirePoint("Specify second destination point", base: s2)
            // Optional third pair: picks the side, so the objects are mirrored when the third points lie on opposite sides.
            var mirror = false
            if let s3 = try await ed.getPoint("Specify third source point or <continue>").point {
                let d3 = try await ed.requirePoint("Specify third destination point", base: s3)
                let a = (s2 - s1).cross(s3 - s1), b = (d2 - d1).cross(d3 - d1)
                mirror = a * b < 0
            }
            let scale = try await ed.getYesNo("Scale objects based on alignment points?", defaultValue: false)
            let t = alignTransform(s1, s2, d1, d2, scale: scale, mirror: mirror)
            ed.transformObjects(ids, t, copy: false)
            ed.selection = []
        },
        CommandDef("STRETCH", aliases: ["S"], category: "Modify", summary: "Stretches objects crossed by a window; objects fully inside are moved.") { ed in
            let c1 = try await ed.requirePoint("Select objects to stretch by crossing-window. Specify first corner")
            let c2 = try await ed.requirePoint("Specify opposite corner", base: c1) { c in [.polyline(PolylineGeom(points: BBox2(points: [c1, c]).corners, closed: true))] }
            let box = BBox2(points: [c1, c2])
            let ids = ed.select(in: box, crossing: true)
            ed.print("\(ids.count) found")
            guard !ids.isEmpty else { return }
            let b = try await ed.requirePoint("Specify base point")
            func apply(_ d: Vec2, to doc: inout ArchiDocument) {
                for id in ids {
                    if let i = doc.entityIndex(id) {
                        let g = doc.entities[i].geometry
                        let bb = GeometryOps.bounds(g, doc: doc)
                        doc.entities[i].geometry = box.contains(bb) ? GeometryOps.transform(g, .translation(d)) : Modify.stretch(g, window: box, by: d)
                    } else if let i = doc.elementIndex(id) {
                        doc.elements[i].geometry = stretchElement(doc.elements[i].geometry, box: box, d: d)
                    }
                }
            }
            let snapshot = ed.doc
            let s = try await ed.getPoint("Specify second point", base: b) { c in
                var tmp = snapshot; apply(c - b, to: &tmp)
                return ids.compactMap { tmp.entity($0)?.geometry }
            }
            let d = s.point.map { $0 - b } ?? b
            var doc = ed.doc; apply(d, to: &doc); ed.doc = doc
            ed.selection = []
        },
    ] }

    // MARK: - ERASE / EXPLODE / JOIN / OFFSET / TRIM / EXTEND / FILLET / CHAMFER / BREAK
    static var edits: [CommandDef] { [
        CommandDef("ERASE", aliases: ["E", "DELETE"], category: "Modify", summary: "Removes objects from the drawing.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let set = Set(ids)
            ed.lastErased = (ed.doc.entities.filter { set.contains($0.id) }, ed.doc.elements.filter { el in
                if set.contains(el.id) { return true }
                if case .opening(let o) = el.geometry, set.contains(o.hostWall) { return true }
                return false })
            ed.doc.remove(ids: set)
            ed.selection = []
            ed.print("\(ids.count) object(s) erased.")
        },
        CommandDef("EXPLODE", aliases: ["X"], category: "Modify", summary: "Breaks compound objects (polylines, blocks, hatches, dimensions) into their parts.") { ed in
            let ids = try await ed.getSelection()
            var n = 0, skipped = 0
            for id in ids {
                guard let e = ed.doc.entity(id) else { skipped += 1; continue }
                guard let parts = explodeEntity(e, doc: ed.doc), !parts.isEmpty else { skipped += 1; continue }
                ed.doc.remove(ids: [id])
                for p in parts { ed.doc.add(p) }
                n += 1
            }
            ed.selection = []
            ed.print("\(n) object(s) exploded" + (skipped > 0 ? ", \(skipped) could not be exploded." : "."))
        },
        CommandDef("JOIN", aliases: ["J"], category: "Modify", summary: "Joins lines, arcs and polylines at their end points.") { ed in
            let ids = try await ed.getEntitySelection("Select source object or multiple objects to join at once")
            let ents = ids.compactMap { ed.doc.entity($0) }
            guard ents.count >= 2 else { throw CommandError.invalid("Select at least two objects to join.") }
            let joined = Modify.join(ents.map(\.geometry))
            guard joined.count < ents.count else { ed.print("0 objects joined."); return }
            let proto = ents[0]
            ed.doc.remove(ids: Set(ids))
            for g in joined { var e = proto; e.geometry = g; ed.doc.add(e) }
            ed.selection = []
            ed.print("\(ents.count) objects joined into \(joined.count).")
        },
        CommandDef("OFFSET", aliases: ["O"], category: "Modify", summary: "Creates parallel copies of lines, arcs, circles and polylines.") { ed in
            ed.selection = []
            var dist = ed.settings.offsetDistance
            var through = ed.doc.variable("OFFSETMODE") == "Through"
            var erase = ed.doc.variable("OFFSETERASE") == "1"
            var toCurrent = ed.doc.variable("OFFSETLAYER") == "Current"
            while true {
                let a = try await ed.getDistance("Specify offset distance", defaultValue: through ? nil : dist, keywords: ["Through", "Erase", "Layer"])
                switch a {
                case .value(let v):
                    guard v > 0 else { ed.print("Value must be positive."); continue }
                    dist = v; through = false
                case .keyword("Through"): through = true
                case .keyword("Erase"): erase = try await ed.getYesNo("Erase source object after offsetting?", defaultValue: erase); continue
                case .keyword("Layer"): toCurrent = (try await ed.getKeyword("Enter layer option for offset objects", ["Current", "Source"], defaultValue: toCurrent ? "Current" : "Source")) == "Current"; continue
                default: if through { break }; return
                }
                break
            }
            ed.settings.offsetDistance = dist
            ed.doc.setVariable("OFFSETMODE", through ? "Through" : "Distance"); ed.doc.setVariable("OFFSETERASE", erase ? "1" : "0"); ed.doc.setVariable("OFFSETLAYER", toCurrent ? "Current" : "Source")
            var created: [EntityID] = []
            while true {
                let a = try await ed.pickObject("Select object to offset", keywords: created.isEmpty ? ["Exit"] : ["Exit", "Undo"]) { ed.doc.entity($0) != nil }
                guard case .pick(let pk) = a else {
                    if a == .keyword("Undo"), let l = created.popLast() { ed.doc.remove(ids: [l]); continue }
                    return
                }
                guard let src = ed.doc.entity(pk.id) else { continue }
                let g = src.geometry
                let d = dist
                let p = try await ed.requirePoint(through ? "Specify through point" : "Specify point on side to offset") { c in
                    let dd = through ? GeometryOps.distance(from: c, to: g, doc: nil) : d
                    return Modify.offset(g, distance: dd, towards: c).map { [$0] } ?? [] }
                let dd = through ? GeometryOps.distance(from: p, to: g, doc: ed.doc) : dist
                guard dd > 1e-9, let res = Modify.offset(g, distance: dd, towards: p) else { ed.print("Unable to offset that object."); continue }
                var e = src; e.geometry = res
                if toCurrent { e.layer = ed.doc.currentLayer }
                created.append(ed.doc.add(e))
                if erase { ed.doc.remove(ids: [pk.id]) }
            }
        },
        CommandDef("TRIM", aliases: ["TR"], category: "Modify", summary: "Trims objects at cutting edges (all objects are cutting edges by default).") { ed in
            var edges: [EntityID]? = ed.selection.isEmpty ? nil : ed.selection.filter { ed.doc.entity($0) != nil }
            ed.selection = []
            var undo: [ArchiDocument] = []
            @MainActor func trimAt(_ id: EntityID, _ p: Vec2) -> Bool {
                guard let e = ed.doc.entity(id), ed.isSelectable(id) else { return false }
                guard let res = Modify.trim(e.geometry, at: p, boundaries: ed.curveGeometries(edges, excluding: id), doc: ed.doc) else { return false }
                ed.replaceEntity(id, with: res); return true
            }
            while true {
                let a = try await ed.pickObject("Select object to trim", keywords: ["cuTting", "Fence", "Erase", "Undo"]) { ed.doc.entity($0) != nil }
                switch a {
                case .pick(let pk):
                    let before = ed.doc
                    if trimAt(pk.id, pk.point) { undo.append(before) } else { ed.print("Object does not intersect a cutting edge.") }
                case .keyword("cuTting"):
                    ed.selection = []
                    let s = try await ed.getEntitySelection("Select cutting edges (Enter for all objects)")
                    edges = s.isEmpty ? nil : s
                    ed.selection = []
                case .keyword("Fence"):
                    var pts = [try await ed.requirePoint("Specify first fence point")]
                    while let q = try await ed.getPoint("Specify next fence point", base: pts.last).point { pts.append(q) }
                    let before = ed.doc
                    var n = 0
                    for i in 0..<max(0, pts.count - 1) {
                        let fence = Geometry.line(LineGeom(pts[i], pts[i + 1]))
                        for e in ed.doc.entities where ed.isSelectable(e.id) {
                            for x in Intersections.of(fence, e.geometry, doc: ed.doc) where trimAt(e.id, x) { n += 1; break }
                        }
                    }
                    if n > 0 { undo.append(before) }
                    ed.print("\(n) object(s) trimmed.")
                case .keyword("Erase"):
                    ed.selection = []
                    let s = try await ed.getSelection("Select objects to erase")
                    if !s.isEmpty { undo.append(ed.doc); ed.doc.remove(ids: Set(s)) }
                    ed.selection = []
                case .keyword("Undo"):
                    if let d = undo.popLast() { ed.doc = d } else { ed.print("Nothing to undo.") }
                default: return
                }
            }
        },
        CommandDef("EXTEND", aliases: ["EX"], category: "Modify", summary: "Extends objects to meet boundary edges (all objects by default).") { ed in
            var edges: [EntityID]? = ed.selection.isEmpty ? nil : ed.selection.filter { ed.doc.entity($0) != nil }
            ed.selection = []
            var undo: [ArchiDocument] = []
            while true {
                let a = try await ed.pickObject("Select object to extend", keywords: ["Boundary", "Undo"]) { ed.doc.entity($0) != nil }
                switch a {
                case .pick(let pk):
                    guard let e = ed.doc.entity(pk.id), let res = Modify.extend(e.geometry, at: pk.point, boundaries: ed.curveGeometries(edges, excluding: pk.id), doc: ed.doc) else {
                        ed.print("Object does not intersect an edge."); continue }
                    undo.append(ed.doc); ed.replaceEntity(pk.id, with: [res])
                case .keyword("Boundary"):
                    let s = try await ed.getEntitySelection("Select boundary edges (Enter for all objects)")
                    edges = s.isEmpty ? nil : s
                    ed.selection = []
                case .keyword("Undo"): if let d = undo.popLast() { ed.doc = d }
                default: return
                }
            }
        },
        CommandDef("FILLET", aliases: ["F"], category: "Modify", summary: "Rounds the corner between two objects (radius 0 = sharp corner).") { ed in
            ed.selection = []
            var multiple = false
            var trimMode = ed.doc.variable("TRIMMODE") != "0"
            var undo: [ArchiDocument] = []
            ed.print("Current settings: Mode = \(trimMode ? "TRIM" : "NOTRIM"), Radius = \(fmt(ed.settings.filletRadius))")
            while true {
                let a = try await ed.pickObject("Select first object", keywords: ["Undo", "Polyline", "Radius", "Trim", "Multiple"]) { ed.doc.entity($0) != nil }
                switch a {
                case .keyword("Radius"):
                    ed.settings.filletRadius = try await ed.getPositive("Specify fillet radius", defaultValue: ed.settings.filletRadius, allowZero: true)
                    ed.doc.setVariable("FILLETRAD", fmt(ed.settings.filletRadius)); continue
                case .keyword("Trim"):
                    trimMode = (try await ed.getKeyword("Enter Trim mode option", ["Trim", "No trim"], defaultValue: trimMode ? "Trim" : "No trim")) == "Trim"
                    ed.doc.setVariable("TRIMMODE", trimMode ? "1" : "0"); continue
                case .keyword("Multiple"): multiple = true; continue
                case .keyword("Undo"): if let d = undo.popLast() { ed.doc = d }; continue
                case .keyword("Polyline"):
                    guard case .pick(let pk) = try await ed.pickObject("Select 2D polyline"), let e = ed.doc.entity(pk.id), case .polyline(let pl) = e.geometry else { ed.print("Not a polyline."); continue }
                    let (res, n) = filletPolyline(pl, radius: ed.settings.filletRadius)
                    if n > 0 { undo.append(ed.doc); ed.replaceEntity(pk.id, with: [.polyline(res)]) }
                    ed.print("\(n) line(s) were filleted.")
                case .pick(let p1):
                    guard case .pick(let p2) = try await ed.pickObject("Select second object", filter: { ed.doc.entity($0) != nil }) else { return }
                    guard let e1 = ed.doc.entity(p1.id), let e2 = ed.doc.entity(p2.id) else { continue }
                    if p1.id == p2.id {
                        if case .polyline(let pl) = e1.geometry {
                            let (res, n) = filletPolyline(pl, radius: ed.settings.filletRadius)
                            if n > 0 { undo.append(ed.doc); ed.replaceEntity(p1.id, with: [.polyline(res)]) }
                        } else { ed.print("Cannot fillet an object with itself.") }
                    } else if let r = Modify.fillet(e1.geometry, pickA: p1.point, e2.geometry, pickB: p2.point, radius: ed.settings.filletRadius) {
                        undo.append(ed.doc)
                        if trimMode { ed.replaceEntity(p1.id, with: [r.first]); ed.replaceEntity(p2.id, with: [r.second]) }
                        if let arc = r.arc { var n = e1; n.geometry = arc; ed.doc.add(n) }
                    } else { ed.print("Cannot fillet these objects (radius may be too large).") }
                default: return
                }
                if !multiple { return }
            }
        },
        CommandDef("CHAMFER", aliases: ["CHA"], category: "Modify", summary: "Bevels the corner between two lines (distance or length/angle method).") { ed in
            ed.selection = []
            var d1 = ed.settings.chamferDistance
            var d2 = ed.variableDouble("CHAMFERB", d1)
            var len = ed.variableDouble("CHAMFERC", d1)
            var ang = rad(ed.variableDouble("CHAMFERD", 45))
            var method = ed.doc.variable("CHAMMODE") == "1" ? "Angle" : "Distance"
            var multiple = false
            var undo: [ArchiDocument] = []
            ed.print(method == "Distance" ? "(TRIM mode) Current chamfer Dist1 = \(fmt(d1)), Dist2 = \(fmt(d2))" : "(TRIM mode) Current chamfer Length = \(fmt(len)), Angle = \(fmt(deg(ang)))")
            func dists(_ g1: Geometry, _ g2: Geometry) -> (Double, Double) {
                guard method == "Angle" else { return (d1, d2) }
                if case .line(let a) = g1, case .line(let b) = g2 {
                    var phi = abs(atan2((a.b - a.a).cross(b.b - b.a), (a.b - a.a).dot(b.b - b.a)))
                    if phi > .pi / 2 { phi = .pi - phi }
                    let s = sin(ang + phi)
                    return (len, abs(s) > 1e-9 ? len * sin(ang) / s : len)
                }
                return (len, len * tan(ang))
            }
            while true {
                let a = try await ed.pickObject("Select first line", keywords: ["Undo", "Polyline", "Distance", "Angle", "Method", "Multiple"]) { ed.doc.entity($0) != nil }
                switch a {
                case .keyword("Distance"):
                    d1 = try await ed.getPositive("Specify first chamfer distance", defaultValue: d1, allowZero: true)
                    d2 = try await ed.getPositive("Specify second chamfer distance", defaultValue: d1, allowZero: true)
                    method = "Distance"
                    ed.settings.chamferDistance = d1; ed.doc.setVariable("CHAMFERA", fmt(d1)); ed.doc.setVariable("CHAMFERB", fmt(d2)); ed.doc.setVariable("CHAMMODE", "0"); continue
                case .keyword("Angle"):
                    len = try await ed.getPositive("Specify chamfer length on the first line", defaultValue: len, allowZero: true)
                    ang = try await ed.getAngle("Specify chamfer angle from the first line", defaultValue: ang).value ?? ang
                    method = "Angle"
                    ed.doc.setVariable("CHAMFERC", fmt(len)); ed.doc.setVariable("CHAMFERD", fmt(deg(ang))); ed.doc.setVariable("CHAMMODE", "1"); continue
                case .keyword("Method"):
                    method = try await ed.getKeyword("Enter trim method", ["Distance", "Angle"], defaultValue: method) ?? method; continue
                case .keyword("Multiple"): multiple = true; continue
                case .keyword("Undo"): if let d = undo.popLast() { ed.doc = d }; continue
                case .keyword("Polyline"):
                    guard case .pick(let pk) = try await ed.pickObject("Select 2D polyline"), let e = ed.doc.entity(pk.id), case .polyline(let pl) = e.geometry else { ed.print("Not a polyline."); continue }
                    let (res, n) = filletPolyline(pl, radius: 0, chamfer: method == "Distance" ? (d1, d2) : (len, len * tan(ang)))
                    if n > 0 { undo.append(ed.doc); ed.replaceEntity(pk.id, with: [.polyline(res)]) }
                    ed.print("\(n) line(s) were chamfered.")
                case .pick(let p1):
                    guard case .pick(let p2) = try await ed.pickObject("Select second line", filter: { ed.doc.entity($0) != nil }) else { return }
                    guard let e1 = ed.doc.entity(p1.id), let e2 = ed.doc.entity(p2.id), p1.id != p2.id else { ed.print("Select two different objects."); continue }
                    let (a1, a2) = dists(e1.geometry, e2.geometry)
                    if let r = Modify.chamfer(e1.geometry, pickA: p1.point, e2.geometry, pickB: p2.point, d1: a1, d2: a2) {
                        undo.append(ed.doc)
                        ed.replaceEntity(p1.id, with: [r.first]); ed.replaceEntity(p2.id, with: [r.second])
                        if let l = r.arc { var n = e1; n.geometry = l; ed.doc.add(n) }
                    } else { ed.print("Cannot chamfer these objects (distances may be too large).") }
                default: return
                }
                if !multiple { return }
            }
        },
        CommandDef("BREAK", aliases: ["BR"], category: "Modify", summary: "Breaks an object between two points.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            var p1 = pk.point
            var s = try await ed.getPoint("Specify second break point", base: p1, keywords: ["First"])
            if s == .keyword("First") {
                p1 = try await ed.requirePoint("Specify first break point")
                s = try await ed.getPoint("Specify second break point", base: p1)
            }
            let p2 = s.point ?? p1
            guard let res = Modify.breakAt(e.geometry, p1, p2) else { throw CommandError.invalid("Cannot break this object at those points.") }
            ed.replaceEntity(pk.id, with: res)
        },
        CommandDef("BREAKATPOINT", aliases: ["BRP"], category: "Modify", summary: "Breaks an object into two at a single point.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            let p = try await ed.requirePoint("Specify break point")
            guard let res = Modify.breakAt(e.geometry, p, p) else { throw CommandError.invalid("Cannot break this object at that point.") }
            ed.replaceEntity(pk.id, with: res)
        },
    ] }

    // MARK: - LENGTHEN / DIVIDE / MEASURE / REVERSE / PEDIT
    static var curveEdits: [CommandDef] { [
        CommandDef("LENGTHEN", aliases: ["LEN"], category: "Modify", summary: "Changes the length of lines, arcs and open polylines (Delta/Percent/Total).") { ed in
            var mode = ed.doc.variable("LENGTHENMODE") ?? "DElta"
            var value = ed.variableDouble("LENGTHENVALUE", 0)
            ed.selection = []
            loop: while true {
                let a = try await ed.pickObject("Select an object to measure", keywords: ["DElta", "Percent", "Total", "DYnamic"]) { ed.doc.entity($0) != nil }
                switch a {
                case .pick(let pk):
                    if let e = ed.doc.entity(pk.id) {
                        var msg = "Current length: \(fmt(GeometryOps.length(e.geometry, doc: ed.doc), 4))"
                        if case .arc(let arc) = e.geometry { msg += ", included angle: \(fmt(deg(arc.sweep), 4))" }
                        ed.print(msg)
                    }
                    continue
                case .keyword("DElta"):
                    guard let v = try await ed.getDistance("Enter delta length", defaultValue: value).value else { continue }
                    mode = "DElta"; value = v
                case .keyword("Percent"):
                    guard let v = try await ed.getReal("Enter percentage length", defaultValue: value == 0 ? 100 : value).value, v > 0 else { continue }
                    mode = "Percent"; value = v
                case .keyword("Total"):
                    guard let v = try await ed.getDistance("Specify total length", defaultValue: value).value, v > 0 else { continue }
                    mode = "Total"; value = v
                case .keyword("DYnamic"):
                    // Drag the picked end: the new end is the cursor projected on the end tangent (lines) or its angle (arcs).
                    while true {
                        guard case .pick(let pk) = try await ed.pickObject("Select an object to change", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
                        let g = e.geometry
                        let atStart = SplineTools.nearestEndIsStart(g, to: pk.point, doc: ed.doc)
                        guard let end = SplineTools.endTangent(g, atStart: atStart, doc: ed.doc) else { ed.print("This object cannot be lengthened."); continue }
                        @MainActor func result(_ c: Vec2) -> Geometry? {
                            Modify.lengthen(g, at: end.point, delta: dynamicDelta(g, end: end, cursor: c))
                        }
                        guard let q = try await ed.getPoint("Specify new end point", base: end.point, preview: { c in result(c).map { [$0] } ?? [] }).point else { continue }
                        guard let res = result(q) else { ed.print("This object cannot be lengthened to that point."); continue }
                        ed.replaceEntity(pk.id, with: [res])
                    }
                default: return
                }
                break loop
            }
            ed.doc.setVariable("LENGTHENMODE", mode); ed.doc.setVariable("LENGTHENVALUE", fmt(value))
            var undo: [ArchiDocument] = []
            while true {
                let a = try await ed.pickObject("Select an object to change", keywords: ["Undo"]) { ed.doc.entity($0) != nil }
                switch a {
                case .pick(let pk):
                    guard let e = ed.doc.entity(pk.id) else { continue }
                    let len = GeometryOps.length(e.geometry, doc: ed.doc)
                    let delta: Double
                    switch mode { case "Percent": delta = len * (value / 100 - 1); case "Total": delta = value - len; default: delta = value }
                    guard let res = Modify.lengthen(e.geometry, at: pk.point, delta: delta) else { ed.print("This object cannot be lengthened by that amount."); continue }
                    undo.append(ed.doc); ed.replaceEntity(pk.id, with: [res])
                case .keyword("Undo"): if let d = undo.popLast() { ed.doc = d }
                default: return
                }
            }
        },
        CommandDef("DIVIDE", aliases: ["DIV"], category: "Modify", summary: "Places points or blocks at equal intervals along an object.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object to divide", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            var (n, k) = try await ed.getIntegerOrKeyword("Enter the number of segments", defaultValue: nil, keywords: ["Block"])
            var block: String? = nil
            var align = false
            if k == "Block" {
                guard let b = try await ed.getWord("Enter name of block to insert"), ed.doc.blocks[b] != nil else { throw CommandError.invalid("Block not found.") }
                block = b
                align = try await ed.getYesNo("Align block with object?", defaultValue: true)
                n = try await ed.getInteger("Enter the number of segments")
            }
            guard let count = n, count >= 2, count <= 32767 else { throw CommandError.invalid("Requires an integer between 2 and 32767.") }
            let pts = Modify.divide(e.geometry, count: count, doc: ed.doc)
            for p in pts {
                if let b = block { ed.addEntity(.insert(InsertGeom(block: b, position: p, rotation: align ? tangent(of: e.geometry, at: p, doc: ed.doc).angle : 0))) }
                else { ed.addEntity(.point(p)) }
            }
            ed.print("\(pts.count) marker(s) placed.")
        },
        CommandDef("MEASURE", aliases: ["ME"], category: "Modify", summary: "Places points or blocks at measured intervals along an object.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object to measure", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            var block: String? = nil
            var align = false
            var ans = try await ed.getDistance("Specify length of segment", keywords: ["Block"])
            if case .keyword = ans {
                guard let b = try await ed.getWord("Enter name of block to insert"), ed.doc.blocks[b] != nil else { throw CommandError.invalid("Block not found.") }
                block = b
                align = try await ed.getYesNo("Align block with object?", defaultValue: true)
                ans = try await ed.getDistance("Specify length of segment")
            }
            guard let len = ans.value, len > 0 else { throw CommandError.invalid("Segment length must be positive.") }
            let pts = Modify.measure(e.geometry, segmentLength: len, doc: ed.doc)
            for p in pts {
                if let b = block { ed.addEntity(.insert(InsertGeom(block: b, position: p, rotation: align ? tangent(of: e.geometry, at: p, doc: ed.doc).angle : 0))) }
                else { ed.addEntity(.point(p)) }
            }
            ed.print("\(pts.count) marker(s) placed.")
        },
        CommandDef("REVERSE", category: "Modify", summary: "Reverses the vertex order of lines, polylines, splines and arcs.") { ed in
            let ids = try await ed.getEntitySelection()
            for id in ids { if let e = ed.doc.entity(id) { ed.replaceEntity(id, with: [Modify.reverse(e.geometry)]) } }
            ed.selection = []
            ed.print("\(ids.count) object(s) reversed.")
        },
        CommandDef("PEDIT", aliases: ["PE"], category: "Modify", summary: "Edits polylines: close/open, join, width, spline, decurve, reverse.") { ed in
            let a = try await ed.pickObject("Select polyline", keywords: ["Multiple"]) { ed.doc.entity($0) != nil }
            var ids: [EntityID] = []
            switch a {
            case .pick(let pk): ids = [pk.id]
            case .keyword: ids = try await ed.getEntitySelection("Select objects"); ed.selection = []
            default: return
            }
            // Convert lines/arcs to polylines if needed.
            var askedConvert: Bool? = nil
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                switch e.geometry {
                case .polyline: continue
                case .line, .arc:
                    if askedConvert == nil { askedConvert = try await ed.getYesNo("Object selected is not a polyline. Do you want to turn it into one?", defaultValue: true) }
                    if askedConvert == true, let v = CommandHelpers.polylineVertices(e.geometry) { ed.replaceEntity(id, with: [.polyline(PolylineGeom(v.vertices, closed: false))]) }
                default: continue
                }
            }
            ids = ids.filter { if case .polyline = ed.doc.entity($0)?.geometry { return true }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("No polylines selected.") }
            var undo: [ArchiDocument] = []
            @MainActor func edit(_ f: (inout PolylineGeom) -> Void) {
                undo.append(ed.doc)
                for id in ids { if let i = ed.doc.entityIndex(id), case .polyline(var p) = ed.doc.entities[i].geometry { f(&p); ed.doc.entities[i].geometry = .polyline(p) } }
            }
            while true {
                let closed: Bool = { if let id = ids.first, case .polyline(let p) = ed.doc.entity(id)?.geometry { return p.closed }; return false }()
                let k = try await ed.getKeyword("Enter an option", [closed ? "Open" : "Close", "Join", "Width", "Edit", "SEgment", "APpend", "Spline", "Decurve", "Reverse", "Addvertex", "delVertex", "Linearize", "Undo", "eXit"], defaultValue: "eXit") ?? "eXit"
                switch k {
                case "Addvertex", "delVertex":
                    guard ids.count == 1 else { ed.print("Vertex editing works on a single polyline."); continue }
                    let q = try await ed.requirePoint(k == "Addvertex" ? "Specify a point on the segment for the new vertex" : "Specify the vertex to remove")
                    guard case .polyline(let p)? = ed.doc.entity(ids[0])?.geometry,
                          let n = k == "Addvertex" ? DraftGeometry.insertVertex(p, near: q) : DraftGeometry.removeVertex(p, near: q) else { ed.print(k == "Addvertex" ? "No segment there." : "Cannot remove that vertex."); continue }
                    edit { $0 = n }
                case "Edit":
                    guard ids.count == 1 else { ed.print("Vertex editing works on a single polyline."); continue }
                    try await editVertices(ed, ids[0], undo: &undo)
                case "SEgment":
                    guard ids.count == 1, case .polyline(let p)? = ed.doc.entity(ids[0])?.geometry else { ed.print("Segment editing works on a single polyline."); continue }
                    let q = try await ed.requirePoint("Select the segment to change")
                    guard let si = PolylineEdit.nearestSegment(p, to: q) else { continue }
                    let t = try await ed.getKeyword("Segment type", ["Line", "Arc"], defaultValue: abs(p.vertices[si].bulge) > 1e-12 ? "Line" : "Arc") ?? "Line"
                    var through: Vec2? = nil
                    if t == "Arc" {
                        let a = p.vertices[si].p, b = p.vertices[(si + 1) % p.vertices.count].p
                        through = try await ed.getPoint("Specify a point on the arc", preview: { c in PolylineEdit.setSegment(p, si, arcThrough: c).map { [.polyline($0)] } ?? [] }).point
                            ?? ((a + b) / 2 + (b - a).perp * 0.5)
                    }
                    guard let n = PolylineEdit.setSegment(p, si, arcThrough: through) else { ed.print("Cannot make that arc."); continue }
                    edit { $0 = n }
                case "APpend":
                    guard ids.count == 1, case .polyline(let p)? = ed.doc.entity(ids[0])?.geometry, !p.closed, let f = p.vertices.first?.p, let l = p.vertices.last?.p else { ed.print("Append works on a single open polyline."); continue }
                    let near = try await ed.getPoint("Specify a point near the end to continue from", base: l).point ?? l
                    let atStart = near.distance(to: f) < near.distance(to: l)
                    var added: [Vec2] = []
                    var last = atStart ? f : l
                    while let q = try await ed.getPoint("Specify next point", base: last, preview: { c in [.polyline(PolylineEdit.append(p, points: added + [c], atStart: atStart))] }).point {
                        if !q.isClose(last, tol: 1e-9) { added.append(q); last = q }
                    }
                    guard !added.isEmpty else { continue }
                    edit { $0 = PolylineEdit.append($0, points: added, atStart: atStart) }
                case "Linearize":
                    let tol = ed.variableDouble("LINEARIZETOL", 0)
                    edit { $0 = DraftGeometry.linearize($0, maxDeviation: tol) }
                case "Close": edit { $0.closed = true }
                case "Open": edit { $0.closed = false }
                case "Width":
                    let w = try await ed.getPositive("Specify new width for all segments", defaultValue: 0, allowZero: true)
                    edit { $0.width = w }
                case "Decurve": edit { p in for i in p.vertices.indices { p.vertices[i].bulge = 0 } }
                case "Reverse":
                    undo.append(ed.doc)
                    for id in ids { if let e = ed.doc.entity(id) { ed.replaceEntity(id, with: [Modify.reverse(e.geometry)]) } }
                case "Spline":
                    undo.append(ed.doc)
                    for id in ids {
                        guard let e = ed.doc.entity(id), case .polyline(let p) = e.geometry else { continue }
                        ed.replaceEntity(id, with: [.spline(SplineGeom(controlPoints: [], fitPoints: p.vertices.map(\.p), closed: p.closed))])
                    }
                    return
                case "Join":
                    guard ids.count == 1, let src = ed.doc.entity(ids[0]) else { ed.print("Join works on a single polyline."); continue }
                    ed.selection = []
                    let others = try await ed.getEntitySelection("Select objects to join").filter { $0 != ids[0] }
                    ed.selection = []
                    let geoms = [src.geometry] + others.compactMap { ed.doc.entity($0)?.geometry }
                    let joined = Modify.join(geoms)
                    guard joined.count < geoms.count else { ed.print("0 segments added to polyline"); continue }
                    undo.append(ed.doc)
                    ed.doc.remove(ids: Set(others))
                    ed.replaceEntity(ids[0], with: joined)
                    ed.print("\(geoms.count - joined.count) segment(s) added to polyline")
                case "Undo": if let d = undo.popLast() { ed.doc = d }
                default: return
                }
            }
        },
    ] }

    /// ALIGN transform: s1→d1 exactly, s1s2 direction onto d1d2, optional uniform scale and mirror about the s1s2 line.
    static func alignTransform(_ s1: Vec2, _ s2: Vec2, _ d1: Vec2, _ d2: Vec2, scale: Bool, mirror: Bool) -> Transform2D {
        let ang = (d2 - d1).angle - (s2 - s1).angle
        let f = scale && s1.distance(to: s2) > 1e-9 ? d1.distance(to: d2) / s1.distance(to: s2) : 1
        var t = Transform2D.translation(d1) * Transform2D.rotation(ang) * Transform2D.scale(f, f) * Transform2D.translation(-s1)
        if mirror && s1.distance(to: s2) > 1e-9 { t = t * Transform2D.mirror(s1, s2) }
        return t
    }

    /// Length change for LENGTHEN DYnamic: arcs follow the cursor angle, other curves its projection on the end tangent.
    static func dynamicDelta(_ g: Geometry, end: (point: Vec2, dir: Vec2), cursor c: Vec2) -> Double {
        if case .arc(let a) = g {
            let ang = (c - a.center).angle
            let endAng = (end.point - a.center).angle
            // Signed angle from the picked end, positive outward (in the direction of the end tangent).
            let cross = Vec2.polar(1, endAng).cross(end.dir)
            var d = normAngle(ang - endAng)
            if d > .pi { d -= 2 * .pi }
            return d * (cross >= 0 ? 1 : -1) * a.radius
        }
        return (c - end.point).dot(end.dir)
    }

    /// PEDIT Edit vertex: a current-vertex marker walks the polyline (Next/Previous); Break, Insert, Move, Straighten,
    /// Tangent-free arcs are set with Arc (segment after the vertex).
    @MainActor static func editVertices(_ ed: Editor, _ id: EntityID, undo: inout [ArchiDocument]) async throws {
        var cur = 0
        @MainActor func poly() -> PolylineGeom? { if case .polyline(let p)? = ed.doc.entity(id)?.geometry { return p }; return nil }
        @MainActor func set(_ p: PolylineGeom) { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].geometry = .polyline(p) } }
        while let p = poly(), !p.vertices.isEmpty {
            cur = min(max(cur, 0), p.vertices.count - 1)
            ed.print("Current vertex \(cur + 1) of \(p.vertices.count) at \(p.vertices[cur].p)")
            let k = try await ed.getKeyword("Enter a vertex editing option", ["Next", "Previous", "Break", "Insert", "Move", "Straighten", "Arc", "eXit"], defaultValue: "Next") ?? "eXit"
            switch k {
            case "Next": cur = p.closed ? (cur + 1) % p.vertices.count : min(cur + 1, p.vertices.count - 1)
            case "Previous": cur = p.closed ? (cur - 1 + p.vertices.count) % p.vertices.count : max(cur - 1, 0)
            case "Move":
                let from = p.vertices[cur].p, ci = cur
                guard let q = try await ed.getPoint("Specify new location for marked vertex", base: from, preview: { c in PolylineEdit.moveVertex(p, ci, to: c).map { [.polyline($0)] } ?? [] }).point,
                      let n = PolylineEdit.moveVertex(p, cur, to: q) else { continue }
                undo.append(ed.doc); set(n)
            case "Insert":
                let ci = cur
                guard let q = try await ed.getPoint("Specify location for new vertex", base: p.vertices[cur].p, preview: { c in PolylineEdit.insertAfter(p, ci, c).map { [.polyline($0)] } ?? [] }).point,
                      let n = PolylineEdit.insertAfter(p, cur, q) else { ed.print("Cannot insert after the last vertex of an open polyline."); continue }
                undo.append(ed.doc); set(n); cur += 1
            case "Arc":
                guard cur < PolylineEdit.segmentCount(p) else { ed.print("No segment after the last vertex."); continue }
                let ci = cur
                guard let q = try await ed.getPoint("Specify a point on the arc (Enter = straight)", preview: { c in PolylineEdit.setSegment(p, ci, arcThrough: c).map { [.polyline($0)] } ?? [] }).point else {
                    if let n = PolylineEdit.setSegment(p, cur, arcThrough: nil) { undo.append(ed.doc); set(n) }
                    continue
                }
                if let n = PolylineEdit.setSegment(p, cur, arcThrough: q) { undo.append(ed.doc); set(n) }
            case "Break", "Straighten":
                let start = cur
                var other = cur
                while true {
                    let o = try await ed.getKeyword("Enter an option", ["Next", "Previous", "Go", "eXit"], defaultValue: "Go") ?? "eXit"
                    if o == "Next" { other = p.closed ? (other + 1) % p.vertices.count : min(other + 1, p.vertices.count - 1); ed.print("Second vertex \(other + 1)"); continue }
                    if o == "Previous" { other = p.closed ? (other - 1 + p.vertices.count) % p.vertices.count : max(other - 1, 0); ed.print("Second vertex \(other + 1)"); continue }
                    if o == "eXit" { other = -1 }
                    break
                }
                guard other >= 0 else { continue }
                if k == "Straighten" {
                    guard let n = PolylineEdit.straighten(p, start, other) else { ed.print("Select two different vertices."); continue }
                    undo.append(ed.doc); set(n); cur = min(start, other)
                } else {
                    let pieces = PolylineEdit.breakBetween(p, start, other)
                    undo.append(ed.doc)
                    ed.replaceEntity(id, with: pieces.map { .polyline($0) })
                    return
                }
            default: return
            }
        }
    }

    // MARK: - ARRAY
    /// Creates an associative array when ARRAYASSOCIATIVITY is on and the selection holds only drawing entities.
    @MainActor static func associativeArray(_ ed: Editor, _ ids: [EntityID], _ p: ArrayParams) -> Bool {
        guard AssocArray.enabled(ed.doc), !ed.forceClassicArray, ids.allSatisfy({ ed.doc.entity($0) != nil }) else { return false }
        return AssocArray.create(ids, p, &ed.doc) != nil
    }

    @MainActor static func rectArray(_ ed: Editor, _ ids: [EntityID]) async throws {
        let b = ed.selectionBounds(ids)
        guard let rows = try await ed.getInteger("Enter the number of rows", defaultValue: 3), rows >= 1,
              let cols = try await ed.getInteger("Enter the number of columns", defaultValue: 4), cols >= 1, rows * cols <= 100000 else {
            throw CommandError.invalid("Enter positive numbers of rows and columns.") }
        guard rows * cols > 1 else { ed.print("One element array, nothing to do."); return }
        var dy = 0.0, dx = 0.0
        if rows > 1 { dy = try await ed.getDistance("Specify the distance between rows", defaultValue: max(b.height * 1.5, 1)).value ?? max(b.height * 1.5, 1) }
        if cols > 1 { dx = try await ed.getDistance("Specify the distance between columns", defaultValue: max(b.width * 1.5, 1)).value ?? max(b.width * 1.5, 1) }
        var prm = ArrayParams(kind: .rect)
        prm.rows = rows; prm.columns = cols; prm.rowSpacing = dy; prm.columnSpacing = dx
        // Arrays containing BIM elements stay editable as a grouped BIM array (MOD-035).
        if !ed.forceClassicArray, ids.contains(where: { ed.doc.element($0) != nil }),
           let n = ed.createBIMArray(ids, rows: rows, columns: cols, rowSpacing: dy, columnSpacing: dx) {
            ed.print("BIM array \(n): \(rows * cols) items (\(rows) row(s) × \(cols) column(s)); ARRAYEDIT changes it.")
            return
        }
        if associativeArray(ed, ids, prm) { ed.print("Associative rectangular array: \(rows * cols) items (\(rows) row(s) × \(cols) column(s))."); return }
        var n = 0
        for r in 0..<rows { for c in 0..<cols where r > 0 || c > 0 {
            ed.transformObjects(ids, .translation(Vec2(Double(c) * dx, Double(r) * dy)), copy: true); n += 1
        } }
        ed.print("Rectangular array: \(n + 1) items (\(rows) row(s) × \(cols) column(s)).")
    }
    @MainActor static func polarArray(_ ed: Editor, _ ids: [EntityID]) async throws {
        let c = try await ed.requirePoint("Specify center point of array")
        guard let n = try await ed.getInteger("Enter number of items", defaultValue: 6), n >= 2, n <= 100000 else { throw CommandError.invalid("Enter 2 or more items.") }
        let fill = try await ed.getAngle("Specify the angle to fill (+ = ccw, - = cw)", defaultValue: 2 * .pi).value ?? 2 * .pi
        guard abs(fill) > 1e-9 else { throw CommandError.invalid("Angle to fill must not be zero.") }
        let rotate = try await ed.getYesNo("Rotate arrayed objects?", defaultValue: true)
        let full = abs(abs(fill) - 2 * .pi) < 1e-9
        let step = full ? fill / Double(n) : fill / Double(n - 1)
        var prm = ArrayParams(kind: .polar)
        prm.count = n; prm.center = c; prm.fill = fill; prm.rotateItems = rotate; prm.base = ed.selectionBounds(ids).center
        if associativeArray(ed, ids, prm) { ed.print("Associative polar array: \(n) items."); return }
        for k in 1..<n {
            let a = step * Double(k)
            let t: Transform2D
            if rotate { t = .rotation(a, around: c) }
            else { let ctr = ed.selectionBounds(ids).center; t = .translation(ctr.rotated(by: a, around: c) - ctr) }
            ed.transformObjects(ids, t, copy: true)
        }
        ed.print("Polar array: \(n) items.")
    }
    @MainActor static func pathArray(_ ed: Editor, _ ids: [EntityID]) async throws {
        guard case .pick(let pk) = try await ed.pickObject("Select path curve", filter: { ed.doc.entity($0) != nil && !ids.contains($0) }), let path = ed.doc.entity(pk.id) else { return }
        guard let n = try await ed.getInteger("Enter number of items along path", defaultValue: 5), n >= 2, n <= 100000 else { throw CommandError.invalid("Enter 2 or more items.") }
        let base = try await ed.getPoint("Specify base point (Enter for selection center)").point ?? ed.selectionBounds(ids).center
        let align = try await ed.getYesNo("Align arrayed items with the path?", defaultValue: true)
        guard let pl = GeometryOps.tessellate(path.geometry, doc: ed.doc).first, pl.count > 1 else { return }
        let total = CommandHelpers.polylineLength(pl)
        let closed = CommandHelpers.closedLoop(path.geometry) != nil
        let (p0, t0) = CommandHelpers.pointAt(pl, distance: 0)
        var prm = ArrayParams(kind: .path)
        prm.count = n; prm.path = path.id; prm.align = align; prm.base = base
        if associativeArray(ed, ids, prm) { ed.print("Associative path array: \(n) items."); return }
        for k in 0..<n {
            let s = closed ? total * Double(k) / Double(n) : total * Double(k) / Double(n - 1)
            let (p, t) = CommandHelpers.pointAt(pl, distance: s)
            var tr = Transform2D.translation(p - base)
            if align { tr = Transform2D.translation(p) * Transform2D.rotation(t.angle - t0.angle) * Transform2D.translation(-base) }
            if k == 0 && p.isClose(base, tol: 1e-9) && (!align || abs(t.angle - t0.angle) < 1e-12) { continue }
            ed.transformObjects(ids, tr, copy: true)
            _ = p0
        }
        ed.print("Path array: \(n) items.")
    }

    static var arrays: [CommandDef] { [
        CommandDef("ARRAY", aliases: ["AR"], category: "Modify", summary: "Creates copies of objects in a rectangular, polar or path pattern.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let k = try await ed.getKeyword("Enter array type", ["Rectangular", "PAth", "POlar"], defaultValue: "Rectangular") ?? "Rectangular"
            switch k {
            case "POlar": try await polarArray(ed, ids)
            case "PAth": try await pathArray(ed, ids)
            default: try await rectArray(ed, ids)
            }
            ed.selection = []
        },
        CommandDef("ARRAYRECT", category: "Modify", summary: "Rectangular array of objects in rows and columns.") { ed in
            let ids = try await ed.getSelection(); guard !ids.isEmpty else { return }
            try await rectArray(ed, ids); ed.selection = []
        },
        CommandDef("ARRAYPOLAR", category: "Modify", summary: "Polar array of objects around a center point.") { ed in
            let ids = try await ed.getSelection(); guard !ids.isEmpty else { return }
            try await polarArray(ed, ids); ed.selection = []
        },
        CommandDef("ARRAYPATH", category: "Modify", summary: "Array of objects evenly spaced along a path.") { ed in
            let ids = try await ed.getSelection(); guard !ids.isEmpty else { return }
            try await pathArray(ed, ids); ed.selection = []
        },
    ] }

    // MARK: - Properties / order / selection
    static func matchElement(_ src: BIMElement, _ dst: inout BIMElement) {
        dst.layer = src.layer; dst.material = src.material
        switch (src.geometry, dst.geometry) {
        case (.wall(let s), .wall(var d)): d.thickness = s.thickness; d.height = s.height; d.baseOffset = s.baseOffset; d.wallType = s.wallType; dst.geometry = .wall(d)
        case (.slab(let s), .slab(var d)): d.thickness = s.thickness; d.topOffset = s.topOffset; dst.geometry = .slab(d)
        case (.opening(let s), .opening(var d)) where s.kind == d.kind:
            d.width = s.width; d.height = s.height; d.sill = s.sill; d.doorStyle = s.doorStyle; d.windowStyle = s.windowStyle; d.frameWidth = s.frameWidth; dst.geometry = .opening(d)
        case (.column(let s), .column(var d)): d.width = s.width; d.depth = s.depth; d.height = s.height; d.round = s.round; d.baseOffset = s.baseOffset; dst.geometry = .column(d)
        case (.beam(let s), .beam(var d)): d.width = s.width; d.depth = s.depth; d.topOffset = s.topOffset; dst.geometry = .beam(d)
        case (.roof(let s), .roof(var d)): d.kind = s.kind; d.pitch = s.pitch; d.thickness = s.thickness; d.overhang = s.overhang; d.baseOffset = s.baseOffset; dst.geometry = .roof(d)
        case (.railing(let s), .railing(var d)): d.height = s.height; dst.geometry = .railing(d)
        case (.curtainWall(let s), .curtainWall(var d)): d.height = s.height; d.gridU = s.gridU; d.gridV = s.gridV; d.mullionSize = s.mullionSize; dst.geometry = .curtainWall(d)
        case (.component(let s), .component(var d)): d.category = s.category; d.size = s.size; d.block = s.block; dst.geometry = .component(d)
        case (.stair(let s), .stair(var d)): d.width = s.width; d.totalRise = s.totalRise; d.riserCount = s.riserCount; d.treadDepth = s.treadDepth; dst.geometry = .stair(d)
        case (.space(let s), .space(var d)): d.height = s.height; dst.geometry = .space(d)
        default: break
        }
    }
    /// Properties MATCHPROP transfers (MOD-064 pen/attribute pick-apply): all by default, a subset chosen with Settings
    /// (document variable MATCHPROPSET, comma-separated).
    static let matchKinds = ["Color", "Layer", "Ltype", "Ltscale", "Lineweight", "Transparency", "Material", "Text", "Dim", "Hatch", "Polyline"]
    static func matchSet(_ doc: ArchiDocument) -> Set<String> {
        guard let v = doc.variable("MATCHPROPSET") else { return Set(matchKinds) }
        return Set(v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.compactMap { k in matchKinds.first { $0.caseInsensitiveCompare(k) == .orderedSame } })
    }
    static func matchEntity(_ src: Entity, _ dst: inout Entity, only set: Set<String>? = nil) {
        let on = set ?? Set(matchKinds)
        if on.contains("Layer") { dst.layer = src.layer }
        if on.contains("Color") { dst.color = src.color }
        if on.contains("Ltype") { dst.linetype = src.linetype }
        if on.contains("Lineweight") { dst.lineweight = src.lineweight }
        if on.contains("Ltscale"), let s = src.props["ltscale"] { dst.props["ltscale"] = s }
        if on.contains("Transparency") { dst.props["transparency"] = src.props["transparency"] }
        switch (src.geometry, dst.geometry) {
        case (.text(let s), .text(var d)) where on.contains("Text"): d.height = s.height; d.style = s.style; dst.geometry = .text(d)
        case (.dimension(let s), .dimension(var d)) where on.contains("Dim"): d.style = s.style; dst.geometry = .dimension(d)
        case (.hatch(let s), .hatch(var d)) where on.contains("Hatch"): d.pattern = s.pattern; d.scale = s.scale; d.angle = s.angle; d.fill = s.fill; dst.geometry = .hatch(d)
        case (.polyline(let s), .polyline(var d)) where on.contains("Polyline"): d.width = s.width; dst.geometry = .polyline(d)
        case (.leader(let s), .leader(var d)) where on.contains("Text"): d.textHeight = s.textHeight; dst.geometry = .leader(d)
        default: break
        }
    }

    static var properties: [CommandDef] { [
        CommandDef("MATCHPROP", aliases: ["MA", "PAINTER"], category: "Modify", summary: "Applies the properties of a source object to other objects.") { ed in
            var source: Editor.PickAnswer
            while true {
                source = try await ed.pickObject("Select source object or [Settings]", keywords: ["Settings"])
                guard case .keyword("Settings") = source else { break }
                // Settings: the properties to transfer, e.g. "Color,Layer" (All / None).
                let cur = matchSet(ed.doc)
                guard let v = try await ed.getWord("Enter properties to match [All/None] (\(matchKinds.joined(separator: ",")))",
                                                   defaultValue: matchKinds.filter(cur.contains).joined(separator: ",")) else { continue }
                if v.caseInsensitiveCompare("All") == .orderedSame { ed.doc.variables["MATCHPROPSET"] = nil; continue }
                let chosen = v.caseInsensitiveCompare("None") == .orderedSame ? [] : v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let bad = chosen.filter { k in !matchKinds.contains { $0.caseInsensitiveCompare(k) == .orderedSame } }
                guard bad.isEmpty else { throw CommandError.invalid("Unknown property \(bad[0]).") }
                ed.doc.setVariable("MATCHPROPSET", chosen.joined(separator: ","))
            }
            guard case .pick(let pk) = source else { return }
            ed.selection = []
            let on = matchSet(ed.doc)
            ed.print("Current active settings: " + matchKinds.filter(on.contains).joined(separator: " "))
            let dsts = try await ed.getSelection("Select destination object(s)").filter { $0 != pk.id }
            var n = 0
            for id in dsts {
                if let se = ed.doc.entity(pk.id), let i = ed.doc.entityIndex(id) { var d = ed.doc.entities[i]; matchEntity(se, &d, only: on); ed.doc.entities[i] = d; n += 1 }
                else if let se = ed.doc.element(pk.id), let i = ed.doc.elementIndex(id) { var d = ed.doc.elements[i]; matchElement(se, &d); ed.doc.elements[i] = d; n += 1 }
                else if let se = ed.doc.entity(pk.id), let i = ed.doc.elementIndex(id), on.contains("Layer") { ed.doc.elements[i].layer = se.layer; n += 1 }
                else if let se = ed.doc.element(pk.id), let i = ed.doc.entityIndex(id), on.contains("Layer") { ed.doc.entities[i].layer = se.layer; n += 1 }
            }
            ed.selection = []
            ed.print("Properties matched on \(n) object(s).")
        },
        CommandDef("CHPROP", aliases: ["CHANGE", "CH", "-CH"], category: "Modify", summary: "Changes color, layer, linetype, lineweight or material of objects.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            while true {
                let k = try await ed.getKeyword("Enter property to change", ["Color", "LAyer", "LType", "ltScale", "LWeight", "TRansparency", "Material"]) 
                guard let key = k else { break }
                switch key {
                case "TRansparency":
                    // Object transparency (LAY-032): ByLayer, ByBlock or 0-90.
                    guard let v = try await ed.getWord("Enter new transparency value [ByLayer/ByBlock] or 0-90", defaultValue: "ByLayer"), let t = Transparency.parse(v) else { ed.print("Enter ByLayer, ByBlock or a value from 0 to 90."); continue }
                    for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[Transparency.prop] = t == "ByLayer" ? nil : t } }
                case "Color":
                    guard let v = try await ed.getWord("Enter new color (ByLayer, ByBlock, 1-255, #RRGGBB, r,g,b)", defaultValue: "ByLayer"), let c = ColorRef.parse(v) else { ed.print("Invalid color."); continue }
                    for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].color = c } }
                case "LAyer":
                    guard let v = try await ed.getWord("Enter new layer name", defaultValue: ed.doc.currentLayer) else { continue }
                    ed.doc.ensureLayer(v)
                    let name = ed.doc.layer(named: v)?.name ?? v
                    for id in ids {
                        if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].layer = name }
                        if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].layer = name }
                    }
                case "LType":
                    guard let v = try await ed.getWord("Enter new linetype name", defaultValue: "ByLayer") else { continue }
                    guard v.lowercased() == "bylayer" || ed.doc.linetype(v) != nil else { ed.print("Linetype \(v) not found. Load it with LINETYPE."); continue }
                    for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].linetype = v.lowercased() == "bylayer" ? nil : ed.doc.linetype(v)!.name } }
                case "ltScale":
                    guard let v = try await ed.getReal("Specify new linetype scale", defaultValue: 1).value, v > 0 else { continue }
                    for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["ltscale"] = fmt(v) } }
                case "LWeight":
                    guard let v = try await ed.getWord("Enter new lineweight in mm (or ByLayer)", defaultValue: "ByLayer") else { continue }
                    let w: Double? = v.lowercased() == "bylayer" ? nil : Double(v)
                    if v.lowercased() != "bylayer" && (w == nil || w! < 0) { ed.print("Invalid lineweight."); continue }
                    for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].lineweight = w } }
                case "Material":
                    guard let v = try await ed.getWord("Enter material name"), let m = ed.doc.material(v) else { ed.print("Material not found."); continue }
                    for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].material = m.name } }
                default: break
                }
            }
            ed.selection = []
        },
        CommandDef("DRAWORDER", aliases: ["DR"], category: "Modify", summary: "Changes the draw order of objects (front, back, above, under).") { ed in
            let ids = try await ed.getEntitySelection()
            guard !ids.isEmpty else { return }
            let k = try await ed.getKeyword("Enter object ordering option", ["Above", "Under", "Front", "Back"], defaultValue: "Back") ?? "Back"
            let set = Set(ids)
            let moving = ed.doc.entities.filter { set.contains($0.id) }
            var rest = ed.doc.entities.filter { !set.contains($0.id) }
            switch k {
            case "Front": rest += moving
            case "Back": rest = moving + rest
            default:
                ed.selection = []
                let refs = Set(try await ed.getEntitySelection("Select reference objects"))
                let idx = rest.indices.filter { refs.contains(rest[$0].id) }
                guard let lo = idx.min(), let hi = idx.max() else { ed.print("No reference objects."); return }
                rest.insert(contentsOf: moving, at: k == "Above" ? hi + 1 : lo)
            }
            ed.doc.entities = rest
            ed.selection = []
        },
        CommandDef("TEXTTOFRONT", category: "Modify", summary: "Brings text, dimensions and/or leaders in front of other objects (options: Text/Dimensions/Leaders/All).") { ed in
            let k = try await ed.getKeyword("Bring to front [Text/Dimensions/Leaders/All]", ["Text", "Dimensions", "Leaders", "All"], defaultValue: "All") ?? "All"
            func isAnno(_ e: Entity) -> Bool {
                switch e.geometry {
                case .text: return k == "Text" || k == "All"
                case .dimension: return k == "Dimensions" || k == "All"
                case .leader: return k == "Leaders" || k == "All"
                default: return false
                }
            }
            let front = ed.doc.entities.filter(isAnno)
            ed.doc.entities = ed.doc.entities.filter { !isAnno($0) } + front
            ed.print("\(front.count) object(s) brought to front.")
        },
        CommandDef("HATCHTOBACK", category: "Modify", summary: "Sends all hatches behind other objects.") { ed in
            func isH(_ e: Entity) -> Bool { if case .hatch = e.geometry { return true }; return false }
            ed.doc.entities = ed.doc.entities.filter(isH) + ed.doc.entities.filter { !isH($0) }
        },
        CommandDef("SELECT", category: "Modify", summary: "Selects objects and keeps them as the current selection.", modifies: false) { ed in
            ed.selection = []
            let ids = try await ed.getSelection()
            ed.selection = Set(ids)
            ed.previousSelection = Set(ids)
        },
        CommandDef("SELECTALL", aliases: ["AI_SELALL"], category: "Modify", summary: "Selects all selectable objects on unlocked layers (current level).", modifies: false) { ed in
            let ids = ed.doc.entities.map(\.id).filter { ed.isSelectable($0) } + ed.doc.elements.filter { $0.level == ed.doc.currentLevel }.map(\.id).filter { ed.isSelectable($0) }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) selected.")
        },
    ] }
}

extension Editor {
    func selectionBounds(_ ids: [EntityID]) -> BBox2 {
        var b = BBox2.empty
        for id in ids {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            else if let el = doc.element(id) { b.add(BBox2(points: CommandHelpers.footprint(el, doc: doc))) }
        }
        return b.isEmpty ? BBox2(min: .zero, max: .zero) : b
    }
}

extension Editor.PickAnswer: Equatable {
    public static func == (a: Editor.PickAnswer, b: Editor.PickAnswer) -> Bool {
        switch (a, b) {
        case (.keyword(let x), .keyword(let y)): return x == y
        case (.none, .none): return true
        case (.pick(let x), .pick(let y)): return x.id == y.id && x.point == y.point
        default: return false
        }
    }
}
