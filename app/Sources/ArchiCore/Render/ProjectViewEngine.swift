// Oanarina Archi Tool — GPL-3.0-or-later
// Project views at draw time: view-specific annotations (detailing), crop regions and annotation crop (DOC-016),
// dependent views and matchlines (DOC-013/014), scope boxes (BIM-008), linework overrides (DOC-027), and 3D
// axonometric views refitted to the model (DOC-009). The model side lives in Model/ProjectViews.swift.
import Foundation

public enum ProjectViews {
    public static let currentKey = "CURRENTVIEW"
    /// Entities created while a view is current get this prop (view-specific detailing).
    public static let ownerProp = "ownerView"
    /// First entity id created after the current view was opened (older annotations stay shared by all views).
    static let markKey = "VIEWIDMARK"
    /// View variables saved with each view.
    public static var settingKeys: [String] { ViewTemplate.keys + ["VIEWTEMPLATE", "VRTOP", "VRCUT", "VRBOTTOM", "VRDEPTH", "UNDERLAY", "CEILINGS", "CROPSHOW", "ISOLATEASSEMBLY", "PARTSVISIBILITY", "SECTIONBOX"] }

    // MARK: Model operations

    public static func capture(_ doc: ArchiDocument) -> [String: String] {
        var s: [String: String] = [:]
        for k in settingKeys { if let v = doc.variable(k) { s[k] = v } }
        return s
    }

    /// Creates (or replaces) a view from the current view settings.
    @discardableResult
    public static func create(_ name: String, kind: String = "plan", level: Int? = nil, doc: inout ArchiDocument) -> ProjectView {
        var v = ProjectView(name: name, kind: kind, level: kind == "3d" ? nil : (level ?? doc.currentLevel), settings: capture(doc))
        if kind == "ceiling" { v.settings["RCP"] = "1" }
        if let i = doc.viewIndex(name) { v.linework = doc.views[i].linework; doc.views[i] = v } else { doc.views.append(v) }
        return v
    }

    /// The view whose annotations and settings a view uses (a dependent view shares its parent's).
    public static func owner(_ v: ProjectView, doc: ArchiDocument) -> ProjectView {
        var cur = v, n = 0
        while let p = cur.parent, let pv = doc.view(named: p), n < 16 { cur = pv; n += 1 }
        return cur
    }

    /// Makes a view current: the current view's settings are stored back, the target's applied (level too).
    @discardableResult
    public static func open(_ name: String, doc: inout ArchiDocument) -> Bool {
        guard let target = doc.view(named: name) else { return false }
        if let cur = doc.currentView, let ci = doc.viewIndex(owner(cur, doc: doc).name) { doc.views[ci].settings = capture(doc) }
        else if let d = try? JSONEncoder().encode(capture(doc)), let s = String(data: d, encoding: .utf8) { doc.setVariable(modelKey, s) }
        let src = owner(target, doc: doc)
        for k in settingKeys { doc.variables[k] = nil }
        doc.variables["RCP"] = nil
        for (k, v) in src.settings { doc.setVariable(k, v) }
        if let l = target.level ?? src.level, doc.level(l) != nil { doc.currentLevel = l }
        doc.setVariable(currentKey, target.name)
        doc.setVariable(markKey, "\(doc.nextID)")
        return true
    }

    /// Leaves project views (the plain model view: every shared annotation, no crop).
    public static func close(doc: inout ArchiDocument) {
        if let cur = doc.currentView, let ci = doc.viewIndex(owner(cur, doc: doc).name) { doc.views[ci].settings = capture(doc) }
        doc.variables[currentKey] = nil; doc.variables[markKey] = nil
        // Back to the model's own view settings (saved when the first view was opened).
        if let s = doc.variable(modelKey), let d = s.data(using: .utf8), let m = try? JSONDecoder().decode([String: String].self, from: d) {
            for k in settingKeys { doc.variables[k] = nil }
            doc.variables["RCP"] = nil
            for (k, v) in m { doc.setVariable(k, v) }
            doc.variables[modelKey] = nil
        }
    }
    static let modelKey = "MODELVIEWSETTINGS"

    public enum DuplicateMode: String, CaseIterable { case plain, withDetailing, dependent }

    /// Duplicates a view (DOC-015): plain (settings and crop only), with detailing (its annotations are copied and owned
    /// by the copy), or as a dependent view (shares settings and annotations of the parent).
    @discardableResult
    public static func duplicate(_ name: String, as newName: String, mode: DuplicateMode, doc: inout ArchiDocument) -> ProjectView? {
        guard let src = doc.view(named: name), doc.view(named: newName) == nil, !newName.isEmpty else { return nil }
        var v = src
        v.name = newName
        switch mode {
        case .plain: v.parent = nil; v.linework = []
        case .withDetailing:
            v.parent = nil
            let owner = self.owner(src, doc: doc).name
            for e in doc.entities where e.props[ownerProp]?.caseInsensitiveCompare(owner) == .orderedSame {
                var c = e; c.props[ownerProp] = newName
                doc.add(c)
            }
        case .dependent: v.parent = src.parent ?? src.name; v.linework = []
        }
        doc.views.append(v)
        return v
    }

    /// Splits a view into cols × rows dependent views (DOC-013) over its crop (or the plan extents). Neighbouring crops
    /// overlap by `overlap`; matchlines run along the shared cell edges. Returns the new view names.
    public static func splitDependent(_ name: String, cols: Int, rows: Int, overlap: Double, doc: inout ArchiDocument) -> [String] {
        guard let src = doc.view(named: name), cols >= 1, rows >= 1, cols * rows >= 2 else { return [] }
        var box = BBox2(points: effectiveCrop(src, doc: doc) ?? [])
        if box.isEmpty {
            var d = doc; d.currentLevel = src.level ?? doc.currentLevel
            for el in doc.elements where el.level == (src.level ?? doc.currentLevel) { box.add(PlanRepresentation.bounds(el, doc: doc)) }
            if box.isEmpty { box = GeometryOps.bounds(of: doc) }
        }
        guard !box.isEmpty, box.width > 1e-9, box.height > 1e-9 else { return [] }
        let dx = box.width / Double(cols), dy = box.height / Double(rows)
        var names: [String] = []
        for r in 0..<rows {
            for c in 0..<cols {
                var cell = BBox2(min: box.min + Vec2(Double(c) * dx, Double(r) * dy), max: box.min + Vec2(Double(c + 1) * dx, Double(r + 1) * dy))
                cell = BBox2(min: cell.min - Vec2(c > 0 ? overlap / 2 : 0, r > 0 ? overlap / 2 : 0),
                             max: cell.max + Vec2(c < cols - 1 ? overlap / 2 : 0, r < rows - 1 ? overlap / 2 : 0))
                let letter = String(UnicodeScalar(UInt8(65 + (r * cols + c) % 26)))
                var n = "\(src.name) - Dependent \(letter)"
                var k = 2
                while doc.view(named: n) != nil { n = "\(src.name) - Dependent \(letter)\(k)"; k += 1 }
                var v = ProjectView(name: n, kind: src.kind, level: src.level, settings: [:], crop: cell.corners, cropActive: true,
                                    annotationCrop: src.annotationCrop, parent: src.parent ?? src.name)
                v.settings["MATCHCELL"] = "\(c),\(r)"
                doc.views.append(v); names.append(n)
            }
        }
        return names
    }

    /// Crop polygon in effect for a view (scope box, else its own crop when active).
    public static func effectiveCrop(_ v: ProjectView, doc: ArchiDocument) -> [Vec2]? {
        if let sb = doc.scopeBox(named: v.scopeBox) { return sb.corners }
        guard v.cropActive, let c = v.crop, c.count >= 3 else { return nil }
        return GeometryOps.signedArea(c) < 0 ? c.reversed() : c
    }

    /// Crop rectangle from two corners, stored on a view (and activated).
    public static func setCrop(_ name: String, a: Vec2, b: Vec2, annotationOffset: Double? = nil, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.viewIndex(name) else { return false }
        let box = BBox2(points: [a, b])
        guard box.width > 1e-9, box.height > 1e-9 else { return false }
        doc.views[i].crop = box.corners; doc.views[i].cropActive = true
        if let o = annotationOffset { doc.views[i].annotationCrop = o }
        return true
    }

    // MARK: Matchlines

    public struct Matchline: Hashable { public var a: Vec2; public var b: Vec2; public var from: String; public var to: String }

    /// Matchlines between the dependent views of a family (parent + children): along the middle of each overlap strip.
    public static func matchlines(_ doc: ArchiDocument, family parent: String) -> [Matchline] {
        let kids = doc.views.filter { $0.parent?.caseInsensitiveCompare(parent) == .orderedSame }
        var out: [Matchline] = []
        for i in kids.indices {
            for j in kids.indices where j > i {
                guard let ca = effectiveCrop(kids[i], doc: doc), let cb = effectiveCrop(kids[j], doc: doc) else { continue }
                let A = BBox2(points: ca), B = BBox2(points: cb)
                let lo = Vec2(max(A.min.x, B.min.x), max(A.min.y, B.min.y)), hi = Vec2(min(A.max.x, B.max.x), min(A.max.y, B.max.y))
                let w = hi.x - lo.x, h = hi.y - lo.y
                let tol = max(A.width, A.height) * 1e-6
                guard w >= -tol, h >= -tol, max(w, h) > tol * 10 else { continue }
                if w <= h { let x = (lo.x + hi.x) / 2; out.append(Matchline(a: Vec2(x, lo.y), b: Vec2(x, hi.y), from: kids[i].name, to: kids[j].name)) }
                else { let y = (lo.y + hi.y) / 2; out.append(Matchline(a: Vec2(lo.x, y), b: Vec2(hi.x, y), from: kids[i].name, to: kids[j].name)) }
            }
        }
        return out
    }

    static func matchlineEntries(_ doc: ArchiDocument, view v: ProjectView, options: DrawOptions) -> [DrawEntry] {
        guard doc.variable("MATCHLINES") != "0" else { return [] }
        let fam = v.parent ?? v.name
        let u = 1 / doc.units.mm
        let lines = matchlines(doc, family: fam).filter { v.parent == nil || $0.from == v.name || $0.to == v.name }
        guard !lines.isEmpty else { return [] }
        let col = options.forPaper ? RGBA.black : RGBA(0.85, 0.3, 0.85)
        let dash = [1200 * u, -300 * u, 150 * u, -300 * u]
        var items: [DrawItem] = []
        for m in lines {
            items.append(.stroke(points: [m.a, m.b], closed: false, style: StrokeStyle(color: col, lineweight: 0.7, dash: dash)))
            let other = v.parent == nil ? "\(m.from) / \(m.to)" : (m.from == v.name ? m.to : m.from)
            let d = (m.b - m.a).normalized
            var ang = d.angle
            if ang > .pi / 2 + 1e-9 || ang < -.pi / 2 - 1e-9 { ang += .pi }
            let t = TextGeom(position: m.a.lerp(m.b, 0.5) + d.perp * (250 * u), height: 200 * u, content: "MATCH LINE - SEE \(other.uppercased())", rotation: ang, halign: .center)
            items.append(.text(t, font: "Helvetica", color: col))
        }
        return [DrawEntry(id: nil, items: items)]
    }

    // MARK: Scope boxes

    static func scopeBoxEntries(_ doc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        guard !doc.scopeBoxes.isEmpty, !options.forPaper, doc.variable("SCOPEBOXES") != "0" else { return [] }
        let u = 1 / doc.units.mm
        let col = RGBA(0.95, 0.55, 0.1)
        var items: [DrawItem] = []
        for sb in doc.scopeBoxes {
            if let ls = sb.levels, let l = options.level, !ls.contains(l) { continue }
            let c = sb.corners
            items.append(.stroke(points: c, closed: true, style: StrokeStyle(color: col, lineweight: 0.25, dash: [600 * u, -200 * u, 100 * u, -200 * u])))
            items.append(.text(TextGeom(position: c[3] + Vec2(150 * u, -350 * u).rotated(by: sb.rotation), height: 200 * u, content: sb.name, rotation: sb.rotation), font: "Helvetica", color: col))
        }
        return items.isEmpty ? [] : [DrawEntry(id: nil, items: items)]
    }

    /// Grids assigned to a scope box (props scopeBox) are trimmed to it (straight grids keep their line). True if changed.
    static func trimGrids(_ doc: inout ArchiDocument) -> Bool {
        guard !doc.scopeBoxes.isEmpty else { return false }
        var changed = false
        for i in doc.elements.indices {
            guard let sbName = doc.elements[i].props["scopeBox"], let sb = doc.scopeBox(named: sbName),
                  case .gridLine(var g) = doc.elements[i].geometry, g.isStraight, g.start.distance(to: g.end) > 1e-9 else { continue }
            let d = (g.end - g.start).normalized
            // Parametric range of the infinite line inside the convex box.
            var t0 = -Double.infinity, t1 = Double.infinity
            let c = sb.corners
            var ok = true
            for k in 0..<4 {
                let p = c[k], q = c[(k + 1) % 4]
                let n = Vec2((q - p).y, -(q - p).x) // outward normal (CCW corners)
                let den = n.dot(d), num = n.dot(p - g.start)
                if abs(den) < 1e-12 { if num < 0 { ok = false; break }; continue }
                let t = num / den
                if den > 0 { t1 = min(t1, t) } else { t0 = max(t0, t) }
            }
            guard ok, t1 - t0 > 1e-6 else { continue }
            let ns = g.start + d * t0, ne = g.start + d * t1
            if !ns.isClose(g.start, tol: 1e-6) || !ne.isClose(g.end, tol: 1e-6) {
                g.start = ns; g.end = ne; doc.elements[i].geometry = .gridLine(g); changed = true
            }
        }
        return changed
    }

    // MARK: Axonometric 3D views

    /// Unit direction from the target towards the eye for an axonometric preset ("SW", "SE", "NE", "NW", "Top",
    /// "Front", or "axo:azimuthDeg,elevationDeg" with azimuth measured from +X counter-clockwise).
    public static func axonDirection(_ preset: String) -> Vec3? {
        let p = preset.lowercased()
        let iso = atan(1 / 2.0.squareRoot()) * 180 / .pi // 35.264°
        var az: Double, el: Double
        switch p {
        case "sw": az = 225; el = iso
        case "se": az = 315; el = iso
        case "ne": az = 45; el = iso
        case "nw": az = 135; el = iso
        case "top": az = 270; el = 89.999
        case "front", "south": az = 270; el = 0
        default:
            let parts = p.replacingOccurrences(of: "axo:", with: "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, abs(parts[1]) <= 90 else { return nil }
            az = parts[0]; el = parts[1]
        }
        let a = az * .pi / 180, e = el * .pi / 180
        return Vec3(cos(e) * cos(a), cos(e) * sin(a), sin(e))
    }

    /// Model extents in 3D (plan bounds of the elements and entities, heights from the levels).
    public static func modelBounds(_ doc: ArchiDocument) -> BBox3 {
        let b2 = GeometryOps.bounds(of: doc)
        guard !b2.isEmpty else { return .empty }
        var z0 = 0.0, z1 = 0.0
        let used = Set(doc.elements.map(\.level))
        for l in doc.levels where used.contains(l.id) || used.isEmpty { z0 = min(z0, l.elevation); z1 = max(z1, l.elevation + l.height) }
        for e in doc.entities { if case .solid(let s) = e.geometry { let mb = MeshTools.mesh(of: s).bounds; if !mb.isEmpty { z0 = min(z0, mb.min.z); z1 = max(z1, mb.max.z) } } }
        return BBox3(min: Vec3(b2.min.x, b2.min.y, z0), max: Vec3(b2.max.x, b2.max.y, max(z1, z0 + 1)))
    }

    /// Orthographic camera looking along the preset, framing the whole model.
    public static func axonCamera(_ preset: String, doc: ArchiDocument) -> Camera? {
        guard let dir = axonDirection(preset) else { return nil }
        let b = modelBounds(doc)
        guard !b.isEmpty else { return nil }
        let c = b.center, r = max(b.size.length / 2, 1)
        return Camera(eye: c + dir * (r * 3), target: c, fov: 50, orthographic: true)
    }

    /// Refits axonometric 3D views to the model and mirrors every 3D view into the named views (restored by VIEW / the
    /// 3D viewport). True if anything changed.
    static func refit3D(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.views.indices where doc.views[i].kind == "3d" {
            if let p = doc.views[i].axonometric, let cam = axonCamera(p, doc: doc), cam != doc.views[i].camera { doc.views[i].camera = cam; changed = true }
            guard let cam = doc.views[i].camera else { continue }
            let nv = NamedView(name: doc.views[i].name, center: cam.target.xy, height: max(modelBounds(doc).size.y, 1), camera: cam)
            if let k = doc.namedViews.firstIndex(where: { $0.name.caseInsensitiveCompare(nv.name) == .orderedSame }) {
                if doc.namedViews[k].camera != cam { doc.namedViews[k] = nv; changed = true }
            } else { doc.namedViews.append(nv); changed = true }
        }
        return changed
    }

    // MARK: Updater

    public static func hasContent(_ doc: ArchiDocument) -> Bool { !doc.views.isEmpty || !doc.scopeBoxes.isEmpty }

    /// Assigns new annotations to the current view, trims grids to scope boxes and refits 3D views. True if changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        if let cur = doc.currentView, let mark = doc.variable(markKey).flatMap(Int.init) {
            let owner = self.owner(cur, doc: doc).name
            for i in doc.entities.indices where doc.entities[i].id >= mark && doc.entities[i].props[ownerProp] == nil && isDetailing(doc.entities[i]) {
                doc.entities[i].props[ownerProp] = owner; changed = true
            }
        }
        if trimGrids(&doc) { changed = true }
        if refit3D(&doc) { changed = true }
        return changed
    }

    /// View-specific annotation: text, dimensions, leaders, tags, detail components, and objects on annotation layers.
    public static func isDetailing(_ e: Entity) -> Bool {
        if e.props["view"] != nil || e.props[Schedules.placedProp] != nil { return false }
        switch e.geometry {
        case .text, .dimension, .leader: return true
        case .table, .image, .solid: return false
        default: return e.props["detail"] != nil || e.layer.uppercased().contains("ANNO") || e.layer.uppercased().hasPrefix("A-DETL")
        }
    }

    /// Whether an entity is shown in the current view (annotations owned by other views are not).
    public static func shows(_ e: Entity, doc: ArchiDocument) -> Bool {
        guard let o = e.props[ownerProp] else { return true }
        guard let cur = doc.currentView else { return false }
        return owner(cur, doc: doc).name.caseInsensitiveCompare(o) == .orderedSame
    }

    // MARK: Draw-list post-processing

    static func isConvex(_ p: [Vec2]) -> Bool {
        guard p.count >= 3 else { return false }
        var sign = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count], c = p[(i + 2) % p.count]
            let z = (b - a).cross(c - b)
            if abs(z) < 1e-12 { continue }
            if sign == 0 { sign = z } else if (z > 0) != (sign > 0) { return false }
        }
        return true
    }

    static func clipLoop(_ loop: [Vec2], to crop: [Vec2], convex: Bool) -> [[Vec2]] {
        if convex {
            var q = loop
            for i in crop.indices {
                let p = crop[i], r = crop[(i + 1) % crop.count]
                let n = Vec2((r - p).y, -(r - p).x).normalized
                q = RG.clipHalfPlane(q, normal: n, n.dot(p))
                if q.count < 3 { return [] }
            }
            return [q]
        }
        return PolygonBoolean.apply(.intersect, [loop], [crop]).filter { $0.count >= 3 }
    }

    /// Clips draw items to a crop polygon.
    public static func clip(_ items: [DrawItem], to crop: [Vec2]) -> [DrawItem] {
        let convex = isConvex(crop)
        let cb = BBox2(points: crop)
        var out: [DrawItem] = []
        for it in items {
            switch it {
            case .stroke(let pts, let closed, let st):
                let pb = BBox2(points: pts)
                if cb.contains(pb), pts.allSatisfy({ GeometryOps.pointInPolygon($0, crop) }) && convex { out.append(it); continue }
                if !pb.intersects(cb) { continue }
                let path = closed && pts.count > 2 ? pts + [pts[0]] : pts
                for piece in RG.clipPolyline(path, [crop]) where piece.count >= 2 { out.append(.stroke(points: piece, closed: false, style: st)) }
            case .fill(let loops, let c):
                let ls = loops.flatMap { clipLoop($0, to: crop, convex: convex) }
                if !ls.isEmpty { out.append(.fill(loops: ls, color: c)) }
            case .text(let t, _, _): if GeometryOps.pointInPolygon(t.position, crop) { out.append(it) }
            case .image(let im): if BBox2(points: [im.origin, im.origin + im.size]).intersects(cb) { out.append(it) }
            }
        }
        return out
    }

    /// Splits strokes of an element at overridden edges and restyles (or hides) them.
    static func applyLinework(_ items: [DrawItem], overrides: [LineworkOverride], doc: ArchiDocument) -> [DrawItem] {
        guard !overrides.isEmpty else { return items }
        let tol = max(1e-6, 1 / doc.units.mm)
        func match(_ p: Vec2, _ q: Vec2) -> LineworkOverride? {
            overrides.first { o in
                let d = o.b - o.a, l = d.length
                guard l > 1e-12 else { return false }
                let u = d / l
                func on(_ x: Vec2) -> Bool { abs((x - o.a).cross(u)) <= tol && (x - o.a).dot(u) >= -tol && (x - o.a).dot(u) <= l + tol }
                return on(p) && on(q) && p.distance(to: q) > tol
            }
        }
        var out: [DrawItem] = []
        for it in items {
            guard case .stroke(let pts, let closed, let st) = it, pts.count >= 2 else { out.append(it); continue }
            let path = closed ? pts + [pts[0]] : pts
            var run: [Vec2] = [path[0]]
            var any = false
            var pieces: [DrawItem] = []
            for i in 0..<(path.count - 1) {
                let p = path[i], q = path[i + 1]
                if let o = match(p, q) {
                    any = true
                    if run.count >= 2 { pieces.append(.stroke(points: run, closed: false, style: st)) }
                    run = [q]
                    if o.invisible == true { continue }
                    var s2 = st
                    if let c = o.color { s2.color = c }
                    if let w = o.lineweight { s2.lineweight = w }
                    if let lt = o.linetype { s2.dash = doc.linetype(lt)?.pattern.map { $0 * (doc.variable("LTSCALE").flatMap(Double.init) ?? 1) } ?? [] }
                    pieces.append(.stroke(points: [p, q], closed: false, style: s2))
                } else { run.append(q) }
            }
            if !any { out.append(it); continue }
            if run.count >= 2 { pieces.append(.stroke(points: run, closed: false, style: st)) }
            out += pieces
        }
        return out
    }

    /// Applies the current project view to the draw entries of a plan: linework overrides, crop regions and annotation
    /// crop, matchlines and scope boxes.
    static func apply(_ entries: [DrawEntry], doc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        var out = entries
        out += scopeBoxEntries(doc, options: options)
        out += CameraObjects.entries(doc, options: options)
        guard let v = doc.currentView else { return out }
        let own = owner(v, doc: doc)
        let lw = own.linework + (own.name == v.name ? [] : v.linework)
        if !lw.isEmpty {
            let byEl = Dictionary(grouping: lw, by: \.element)
            out = out.map { e in
                guard let id = e.id, let os = byEl[id] else { return e }
                return DrawEntry(id: id, items: applyLinework(e.items, overrides: os, doc: doc))
            }
        }
        out += matchlineEntries(doc, view: v, options: options)
        guard let crop = effectiveCrop(v, doc: doc) else { return out }
        let annoIDs = Set(doc.entities.filter { isDetailing($0) }.map(\.id))
        let annoCrop = v.annotationCrop.map { RG.offsetPolygon(crop, $0) }
        var res: [DrawEntry] = []
        for e in out {
            let isAnno = e.id.map { annoIDs.contains($0) } ?? false
            if isAnno {
                guard let ac = annoCrop else { res.append(e); continue }
                if !e.bounds.intersects(BBox2(points: ac)) { continue }
                // Annotations are kept whole when their anchor is inside the annotation crop (Revit behaviour).
                if GeometryOps.pointInPolygon(e.bounds.center, ac) || BBox2(points: ac).contains(e.bounds) { res.append(e) }
                continue
            }
            if e.id == nil, e.items.contains(where: { if case .text(let t, _, _) = $0 { return t.content.hasPrefix("MATCH LINE") }; return false }) {
                let c = clip(e.items, to: RG.offsetPolygon(crop, 1 / doc.units.mm * 600)); if !c.isEmpty { res.append(DrawEntry(id: nil, items: c)) }; continue
            }
            if !e.bounds.isEmpty, !e.bounds.intersects(BBox2(points: crop)) { continue }
            let c = clip(e.items, to: crop)
            if !c.isEmpty { res.append(DrawEntry(id: e.id, items: c)) }
        }
        if v.settings["CROPSHOW"] == "1" || doc.variable("CROPSHOW") == "1", !options.forPaper {
            res.append(DrawEntry(id: nil, items: [.stroke(points: crop, closed: true, style: StrokeStyle(color: RGBA(0.5, 0.5, 0.5), lineweight: 0.18))]))
        }
        return res
    }

    /// Nearest element edge to a point in the drawn plan (for linework overrides).
    public static func pickEdge(_ doc: ArchiDocument, at p: Vec2, tolerance: Double) -> LineworkOverride? {
        var d = doc
        d.variables[currentKey] = nil
        let entries = DrawListBuilder.entries(doc: d, options: DrawOptions(level: doc.currentLevel))
        var best: (LineworkOverride, Double)?
        for e in entries {
            guard let id = e.id, doc.element(id) != nil, e.bounds.expanded(by: tolerance).contains(p) else { continue }
            for it in e.items {
                guard case .stroke(let pts, let closed, _) = it, pts.count >= 2 else { continue }
                let path = closed ? pts + [pts[0]] : pts
                for i in 0..<(path.count - 1) {
                    let a = path[i], b = path[i + 1]
                    let dist = GeometryOps.distance(from: p, to: .line(LineGeom(a, b)), doc: nil)
                    if dist <= tolerance, dist < (best?.1 ?? .infinity) { best = (LineworkOverride(element: id, a: a, b: b), dist) }
                }
            }
        }
        return best?.0
    }
}

/// Section boxes of 3D views (DOC-017): the SECTIONBOX view setting ("on;xmin,ymin,zmin,xmax,ymax,zmax", shared with the
/// 3D viewport) is stored per project view, and camera drawings of the view are cut by it (with capped cut faces).
public enum SectionBoxes {
    public static let variable = "SECTIONBOX"

    public static func active(_ doc: ArchiDocument) -> BBox3? { parse(doc.variable(variable)) }

    public static func parse(_ s: String?) -> BBox3? {
        guard let s = s else { return nil }
        let parts = s.split(separator: ";")
        guard parts.count == 2, parts[0] == "on" else { return nil }
        let n = parts[1].split(separator: ",").compactMap { Double($0) }
        guard n.count == 6, n.allSatisfy(\.isFinite) else { return nil }
        return BBox3(min: Vec3(min(n[0], n[3]), min(n[1], n[4]), min(n[2], n[5])), max: Vec3(max(n[0], n[3]), max(n[1], n[4]), max(n[2], n[5])))
    }

    public static func store(_ b: BBox3?, on: Bool = true, in doc: inout ArchiDocument) {
        guard let b = b else { doc.variables[variable] = nil; return }
        doc.variables[variable] = (on ? "on" : "off") + ";" + [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z].map { fmt($0, 1) }.joined(separator: ",")
    }

    /// Mesh groups cut by the box (every face of the box clips and caps).
    public static func clip(_ groups: [MeshGroup], box b: BBox3) -> [MeshGroup] {
        let planes: [(Vec3, Vec3)] = [(b.min, Vec3(-1, 0, 0)), (b.min, Vec3(0, -1, 0)), (b.min, Vec3(0, 0, -1)),
                                      (b.max, Vec3(1, 0, 0)), (b.max, Vec3(0, 1, 0)), (b.max, Vec3(0, 0, 1))]
        return groups.compactMap { g in
            let gb = g.mesh.bounds
            if gb.isEmpty { return g }
            if gb.min.x >= b.min.x && gb.min.y >= b.min.y && gb.min.z >= b.min.z && gb.max.x <= b.max.x && gb.max.y <= b.max.y && gb.max.z <= b.max.z { return g }
            if gb.min.x > b.max.x || gb.max.x < b.min.x || gb.min.y > b.max.y || gb.max.y < b.min.y || gb.min.z > b.max.z || gb.max.z < b.min.z { return nil }
            var m = g.mesh
            for (p, n) in planes { m = PlaneClipper.clip(mesh: m, point: p, normal: n); if m.isEmpty { return nil } }
            let edges = g.edges.flatMap { e -> [[Vec3]] in
                guard e.count >= 2 else { return [] }
                return (0..<(e.count - 1)).compactMap { k in clipSegment(e[k], e[k + 1], b).map { [$0.0, $0.1] } }
            }
            return MeshGroup(id: g.id, kind: g.kind, material: g.material, mesh: m, edges: edges)
        }
    }

    static func clipSegment(_ a: Vec3, _ c: Vec3, _ b: BBox3) -> (Vec3, Vec3)? {
        var t0 = 0.0, t1 = 1.0
        let d = c - a
        for (p, q, lo, hi) in [(a.x, d.x, b.min.x, b.max.x), (a.y, d.y, b.min.y, b.max.y), (a.z, d.z, b.min.z, b.max.z)] {
            if abs(q) < 1e-15 { if p < lo || p > hi { return nil }; continue }
            var ta = (lo - p) / q, tb = (hi - p) / q
            if ta > tb { swap(&ta, &tb) }
            t0 = max(t0, ta); t1 = min(t1, tb)
            if t0 > t1 { return nil }
        }
        return (a + d * t0, a + d * t1)
    }
}
