// Oanarina Archi Tool — GPL-3.0-or-later
// Associative model content added in round 7: spreadsheet-driven parameters (PAR-029), reporting parameters (PAR-025),
// stair / railing type builders (PAR-018), stacked walls (BIM-022), parts divided from compound walls (BIM-127) and
// expressions on any property (PAR-030). All regenerate from their sources after every edit (BIMUpdaters.run).
import Foundation

public enum Round7Updaters {
    public static func hasContent(_ doc: ArchiDocument) -> Bool {
        doc.globalParameters.contains { $0.cell != nil }
            || doc.families.contains { $0.parameters.contains { $0.reporting != nil } }
            || !doc.railingTypes.isEmpty
            || doc.elements.contains { el in
                el.props["stairType"] != nil || el.props["railingType"] != nil || el.props["stack"] != nil || el.props["stackOf"] != nil
                    || el.props["partOf"] != nil || el.props.keys.contains { $0.hasPrefix(Expressions.prefix) }
            }
            || doc.entities.contains { e in e.props.keys.contains { $0.hasPrefix(Expressions.prefix) } || e.props["materialTagOf"] != nil || e.props["repeatDetail"] != nil || e.props["repeatOf"] != nil || e.props["cvGrid"] != nil }
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard hasContent(doc) else { return false }
        var changed = false
        if SpreadsheetParameters.updateAll(&doc) { changed = true }
        if ReportingParameters.updateAll(&doc) { changed = true }
        if SystemTypes.updateAll(&doc) { changed = true }
        if StackedWalls.updateAll(&doc) { changed = true }
        if WallParts.updateAll(&doc) { changed = true }
        if Expressions.updateAll(&doc) { changed = true }
        if MaterialTags.updateAll(&doc) { changed = true }
        if RepeatingDetails.updateAll(&doc) { changed = true }
        if MeshOps.updateSurfaces(&doc) { changed = true }
        return changed
    }
}

// MARK: - PAR-029 spreadsheet-driven parameters

public enum SpreadsheetParameters {
    /// "B3" → (row 2, column 1). Columns A…Z, AA…; rows from 1.
    public static func parseCell(_ s: String) -> (row: Int, col: Int)? {
        let t = s.uppercased().trimmingCharacters(in: .whitespaces)
        var col = 0, i = t.startIndex
        while i < t.endIndex, let a = t[i].asciiValue, a >= 65, a <= 90 { col = col * 26 + Int(a - 64); i = t.index(after: i) }
        guard col > 0, let row = Int(t[i...]), row >= 1 else { return nil }
        return (row - 1, col - 1)
    }

    /// Table entity by "#id" or by its props name / tableName.
    public static func table(_ ref: String, doc: ArchiDocument) -> TableGeom? {
        let r = ref.trimmingCharacters(in: .whitespaces)
        func tg(_ e: Entity?) -> TableGeom? { if case .table(let t)? = e?.geometry { return t }; return nil }
        if r.hasPrefix("#"), let id = Int(r.dropFirst()) { return tg(doc.entity(id)) }
        let all = doc.entities + doc.layouts.flatMap(\.entities)
        return tg(all.first { e in
            guard case .table = e.geometry else { return false }
            return [e.props["name"], e.props["tableName"], e.props["scheduleName"]].contains { $0?.caseInsensitiveCompare(r) == .orderedSame }
        })
    }

    /// Value of a binding "Table!B3".
    public static func value(_ binding: String, doc: ArchiDocument) -> String? {
        guard let bang = binding.lastIndex(of: "!") else { return nil }
        guard let t = table(String(binding[..<bang]), doc: doc), let rc = parseCell(String(binding[binding.index(after: bang)...])),
              t.cells.indices.contains(rc.row), t.cells[rc.row].indices.contains(rc.col) else { return nil }
        return t.cells[rc.row][rc.col].trimmingCharacters(in: .whitespaces)
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.globalParameters.indices {
            guard let b = doc.globalParameters[i].cell, let v = value(b, doc: doc) else { continue }
            let clean = doc.globalParameters[i].kind.isNumeric ? (Double(v.replacingOccurrences(of: ",", with: ".")).map { fmt($0, 6) } ?? v) : v
            if doc.globalParameters[i].value != clean || doc.globalParameters[i].formula != nil {
                doc.globalParameters[i].value = clean; doc.globalParameters[i].formula = nil; changed = true
            }
        }
        return changed
    }
}

// MARK: - PAR-025 reporting parameters

public enum ReportingParameters {
    /// Measured value of a reporting source for an element.
    public static func measure(_ source: String, of el: BIMElement, doc: ArchiDocument) -> Double? {
        let parts = source.lowercased().split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let field = parts[1]
        switch parts[0] {
        case "host":
            guard let hid = (el.props["host"] ?? el.props["hostWall"]).flatMap({ Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }), let host = doc.element(hid) else {
                if case .opening(let o) = el.geometry, let host = doc.element(o.hostWall) { return number(host, field) }
                return nil
            }
            return number(host, field)
        case "level":
            guard let l = doc.level(el.level) else { return nil }
            switch field { case "elevation": return l.elevation; case "height": return l.height; default: return nil }
        case "self": return number(el, field)
        default: return nil
        }
    }

    static func number(_ el: BIMElement, _ field: String) -> Double? {
        if case .component(let c) = el.geometry {
            switch field { case "x": return c.position.x; case "y": return c.position.y; case "rotation": return c.rotation * 180 / .pi
            case "width": return c.size.x; case "depth": return c.size.y; case "height": return c.size.z; default: break }
        }
        return PropertyAccess.getProperty(el, field).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let reporting = doc.families.filter { $0.parameters.contains { $0.reporting != nil } }
        guard !reporting.isEmpty else { return false }
        for i in doc.elements.indices {
            let el = doc.elements[i]
            let fname: String?
            if case .component(let c) = el.geometry { fname = c.family } else { fname = el.props["family"] }
            guard let def = reporting.first(where: { $0.name.caseInsensitiveCompare(fname ?? "") == .orderedSame }) else { continue }
            for p in def.parameters {
                guard let src = p.reporting, let v = measure(src, of: el, doc: doc) else { continue }
                let s = fmt(v, 6)
                if doc.elements[i].props["fp." + p.name] != s { doc.elements[i].props["fp." + p.name] = s; changed = true }
            }
        }
        return changed
    }
}

// MARK: - PAR-018 stair and railing types

public enum SystemTypes {
    /// Stair geometry with a type's rules applied (riser count from the maximum riser, tread from the minimum going).
    public static func apply(_ t: StairType, to g0: StairGeom) -> StairGeom {
        var g = g0
        g.width = t.width
        if t.maxRiser > 0, g.totalRise > 0 { g.riserCount = max(2, Int((g.totalRise / t.maxRiser - 1e-9).rounded(.up))) }
        if t.minTread > 0 { g.treadDepth = t.minTread }
        if let l = t.landingDepth { g.landingDepth = l }
        return g
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.elements.indices {
            let el = doc.elements[i]
            if case .stair(let g) = el.geometry, let t = doc.stairType(named: el.props["stairType"]) {
                let ng = apply(t, to: g)
                if ng != g { doc.elements[i].geometry = .stair(ng); changed = true }
                if let m = t.material, doc.elements[i].material != m { doc.elements[i].material = m; changed = true }
            }
            if case .railing(let g) = el.geometry {
                var tname = el.props["railingType"]
                // Stair railings follow the railing type of their stair's type.
                if tname == nil, let sid = el.props["hostStair"].flatMap(Int.init), let st = doc.element(sid), let t = doc.stairType(named: st.props["stairType"]) { tname = t.railingType }
                guard let rt = doc.railingType(named: tname) else { continue }
                var ng = g
                rt.apply(to: &ng)
                if ng != g { doc.elements[i].geometry = .railing(ng); changed = true }
            }
        }
        return changed
    }
}

// MARK: - BIM-022 stacked walls

/// A stacked wall is a base wall (props stack = "Type A:1200; Type B:*") whose upper segments are generated walls
/// (props stackOf = base id, stackIndex) on the same line, stacked by base offset. The base takes the first type and
/// height; "*" means the rest of the total height (props stackHeight, default the level height).
public enum StackedWalls {
    public struct Segment: Hashable { public var type: String; public var height: Double? }

    public static func parse(_ s: String) -> [Segment] {
        s.split(separator: ";").compactMap { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if let c = t.lastIndex(of: ":") {
                let h = t[t.index(after: c)...].trimmingCharacters(in: .whitespaces)
                return Segment(type: t[..<c].trimmingCharacters(in: .whitespaces), height: h == "*" ? nil : Double(h))
            }
            return Segment(type: t, height: nil)
        }
    }

    /// Heights of the segments for a total height (one "*" segment takes the rest; several share it).
    public static func heights(_ segs: [Segment], total: Double) -> [Double] {
        let fixed = segs.compactMap(\.height).reduce(0, +)
        let free = segs.filter { $0.height == nil }.count
        let rest = free > 0 ? max(total - fixed, 0) / Double(free) : 0
        return segs.map { $0.height ?? rest }
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let masters = doc.elements.filter { $0.props["stack"] != nil }
        // Orphaned segments.
        let orphan = Set(doc.elements.filter { el in el.props["stackOf"].flatMap(Int.init).map { id in !masters.contains { $0.id == id } } ?? false }.map(\.id))
        if !orphan.isEmpty { doc.remove(ids: orphan); changed = true }
        for m in masters {
            guard let mi = doc.elementIndex(m.id), case .wall(var base) = m.geometry else { continue }
            let segs = parse(m.props["stack"] ?? "")
            guard !segs.isEmpty else { continue }
            let total = m.props["stackHeight"].flatMap(Double.init) ?? (base.height + 0)
            let hs = heights(segs, total: total)
            // Base segment.
            let wt0 = doc.wallTypes.first { $0.name.caseInsensitiveCompare(segs[0].type) == .orderedSame }
            var nb = base
            nb.height = max(hs[0], 1); nb.wallType = wt0?.name ?? base.wallType; nb.thickness = wt0?.thickness ?? base.thickness
            nb.topLevel = nil
            if nb != base { base = nb; doc.elements[mi].geometry = .wall(nb); changed = true }
            if m.props["stackHeight"] == nil { doc.elements[mi].props["stackHeight"] = fmt(total, 6); changed = true }
            var z = base.baseOffset + base.height
            var existing = doc.elements.filter { $0.props["stackOf"] == "\(m.id)" }
            for k in 1..<max(segs.count, 1) where k < segs.count {
                let wt = doc.wallTypes.first { $0.name.caseInsensitiveCompare(segs[k].type) == .orderedSame }
                var g = base
                g.baseOffset = z; g.height = max(hs[k], 1); g.wallType = wt?.name; g.thickness = wt?.thickness ?? base.thickness
                g.sweeps = []; g.profile = nil
                z += g.height
                if let ei = existing.firstIndex(where: { $0.props["stackIndex"] == "\(k)" }), let di = doc.elementIndex(existing[ei].id) {
                    if doc.elements[di].geometry != .wall(g) || doc.elements[di].level != m.level {
                        doc.elements[di].geometry = .wall(g); doc.elements[di].level = m.level; changed = true
                    }
                    existing.remove(at: ei)
                } else {
                    let id = doc.addElement(.wall(g), level: m.level, layer: m.layer, material: wt?.plies.first?.material ?? m.material)
                    if let di = doc.elementIndex(id) { doc.elements[di].props["stackOf"] = "\(m.id)"; doc.elements[di].props["stackIndex"] = "\(k)" }
                    changed = true
                }
            }
            if !existing.isEmpty { doc.remove(ids: Set(existing.map(\.id))); changed = true }
        }
        return changed
    }

    /// In plan only the segment cut by the cut plane is drawn (the topmost when the stack is lower than the cut).
    public static func shownInPlan(_ el: BIMElement, doc: ArchiDocument) -> Bool {
        guard el.props["stack"] != nil || el.props["stackOf"] != nil, case .wall(let w) = el.geometry else { return true }
        let masterID = el.props["stackOf"].flatMap(Int.init) ?? el.id
        let cut = BIMConstraints.cutHeight(doc)
        if w.baseOffset <= cut + 1e-9, cut < w.baseOffset + w.height - 1e-9 { return true }
        let family = doc.elements.filter { $0.id == masterID || $0.props["stackOf"] == "\(masterID)" }
        let anyCut = family.contains { f in if case .wall(let g) = f.geometry { return g.baseOffset <= cut + 1e-9 && cut < g.baseOffset + g.height - 1e-9 }; return false }
        if anyCut { return false }
        let top = family.max { a, b in
            func t(_ e: BIMElement) -> Double { if case .wall(let g) = e.geometry { return g.baseOffset + g.height }; return 0 }
            return t(a) < t(b)
        }
        return top?.id == el.id
    }
}

// MARK: - BIM-127 parts

/// Parts divided from a compound wall: one single-ply wall per layer of its wall type (props partOf = host id,
/// partIndex). The host keeps hosting doors and windows but is no longer drawn (props hasParts = 1); every part is cut
/// by the host's openings. Parts follow the host's line, height and type after each edit; a part's material can be
/// overridden (props partMaterial).
public enum WallParts {
    /// Part geometries for a wall (empty when its type has fewer than two plies).
    public static func parts(of w: WallGeom, doc: ArchiDocument) -> [(geom: WallGeom, material: String)] {
        guard let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), wt.plies.count >= 2 else { return [] }
        let total = wt.thickness
        guard total > 1e-9, w.length > 1e-9 else { return [] }
        let d = w.direction, n = d.perp
        // Left face first (left of the direction of the wall), measured from the centre line.
        var t = w.centerOffset + total / 2
        var out: [(WallGeom, String)] = []
        for p in wt.plies {
            let mid = t - p.thickness / 2
            var g = w
            g.start = w.start + n * (mid - w.centerOffset) + n * w.centerOffset
            g.end = w.end + n * (mid - w.centerOffset) + n * w.centerOffset
            g.justification = .center; g.thickness = p.thickness; g.wallType = nil; g.sweeps = []
            out.append((g, p.material))
            t -= p.thickness
        }
        return out
    }

    /// Divides a wall into parts; returns the part ids (empty when not compound).
    @discardableResult
    public static func divide(_ id: EntityID, doc: inout ArchiDocument) -> [EntityID] {
        guard let hi = doc.elementIndex(id), case .wall(let w) = doc.elements[hi].geometry, doc.elements[hi].props["partOf"] == nil else { return [] }
        let ps = parts(of: w, doc: doc)
        guard !ps.isEmpty else { return [] }
        doc.elements[hi].props["hasParts"] = "1"
        _ = updateAll(&doc)
        return doc.elements.filter { $0.props["partOf"] == "\(id)" }.map(\.id)
    }

    /// Removes the parts of a wall (the host is drawn again).
    public static func merge(_ id: EntityID, doc: inout ArchiDocument) -> Int {
        let ids = Set(doc.elements.filter { $0.props["partOf"] == "\(id)" }.map(\.id))
        doc.remove(ids: ids)
        if let i = doc.elementIndex(id) { doc.elements[i].props["hasParts"] = nil }
        return ids.count
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let hosts = doc.elements.filter { $0.props["hasParts"] == "1" }
        let hostIDs = Set(hosts.map(\.id))
        let orphans = Set(doc.elements.filter { el in el.props["partOf"].flatMap(Int.init).map { !hostIDs.contains($0) } ?? false }.map(\.id))
        if !orphans.isEmpty { doc.remove(ids: orphans); changed = true }
        for h in hosts {
            guard case .wall(let w) = h.geometry else { continue }
            let ps = parts(of: w, doc: doc)
            var existing = doc.elements.filter { $0.props["partOf"] == "\(h.id)" }
            for (k, p) in ps.enumerated() {
                if let ei = existing.firstIndex(where: { $0.props["partIndex"] == "\(k)" }), let di = doc.elementIndex(existing[ei].id) {
                    let mat = doc.elements[di].props["partMaterial"] ?? p.material
                    if doc.elements[di].geometry != .wall(p.geom) || doc.elements[di].material != mat || doc.elements[di].level != h.level {
                        doc.elements[di].geometry = .wall(p.geom); doc.elements[di].material = mat; doc.elements[di].level = h.level; changed = true
                    }
                    existing.remove(at: ei)
                } else {
                    let id = doc.addElement(.wall(p.geom), level: h.level, layer: h.layer, material: p.material, name: "\(h.name.isEmpty ? "Wall \(h.id)" : h.name) part \(k + 1)")
                    if let di = doc.elementIndex(id) {
                        doc.elements[di].props["partOf"] = "\(h.id)"; doc.elements[di].props["partIndex"] = "\(k)"
                        for key in ["phaseCreated", "phaseDemolished", "workset", "assembly"] { if let v = h.props[key] { doc.elements[di].props[key] = v } }
                    }
                    changed = true
                }
            }
            if !existing.isEmpty { doc.remove(ids: Set(existing.map(\.id))); changed = true }
        }
        return changed
    }
}

// MARK: - PAR-030 expressions on any property

/// FreeCAD-style expressions: props "expr.<property>" = expression over the element's own numeric properties, other
/// objects' properties ("id12.height" or "<Name>.height" for named objects), and global parameters. Evaluated in
/// dependency order (up to 16 passes); errors are reported in props exprError.
public enum Expressions {
    public static let prefix = "expr."

    static func numeric(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces) else { return nil }
        return Double(s.replacingOccurrences(of: "%", with: ""))
    }

    static func get(_ id: EntityID, _ field: String, doc: ArchiDocument) -> Double? {
        if let el = doc.element(id) { return ReportingParameters.number(el, field) ?? numeric(el.props[field]) }
        if let e = doc.entity(id) { return numeric(PropertyAccess.getProperty(e, field)) ?? numeric(e.props[field]) }
        return nil
    }

    static func objectID(_ name: String, doc: ArchiDocument) -> EntityID? {
        let n = name.lowercased()
        if n.hasPrefix("id"), let id = Int(n.dropFirst(2)) { return id }
        if n.hasPrefix("e"), let id = Int(n.dropFirst(1)) { return id }
        if let el = doc.elements.first(where: { !$0.name.isEmpty && $0.name.replacingOccurrences(of: " ", with: "_").lowercased() == n }) { return el.id }
        if let e = doc.entities.first(where: { ($0.props["name"] ?? "").replacingOccurrences(of: " ", with: "_").lowercased() == n }) { return e.id }
        return nil
    }

    /// Evaluates an expression for object `id`. nil when an identifier cannot be resolved.
    public static func evaluate(_ expr: String, for id: EntityID, doc: ArchiDocument, globals: [String: Double]) -> Double? {
        var vars: [String: Double] = [:]
        for ident in FamilyExpr.identifiers(expr) {
            if let dot = ident.firstIndex(of: ".") {
                let obj = String(ident[..<dot]), field = String(ident[ident.index(after: dot)...])
                if let oid = objectID(obj, doc: doc), let v = get(oid, field, doc: doc) { vars[ident] = v; continue }
                return nil
            }
            if let v = get(id, ident, doc: doc) { vars[ident] = v } else if let g = globals[ident] { vars[ident] = g } else { return nil }
        }
        return FamilyExpr.evaluate(expr, vars)
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        let targets = doc.elements.filter { $0.props.keys.contains { $0.hasPrefix(prefix) } }.map(\.id)
            + doc.entities.filter { $0.props.keys.contains { $0.hasPrefix(prefix) } }.map(\.id)
        guard !targets.isEmpty else { return false }
        let globals = GlobalParameters.values(doc)
        var changed = false
        for _ in 0..<16 {
            var passChanged = false
            for id in targets {
                let props = doc.element(id)?.props ?? doc.entity(id)?.props ?? [:]
                var errors: [String] = []
                for (k, expr) in props.sorted(by: { $0.key < $1.key }) where k.hasPrefix(prefix) {
                    let field = String(k.dropFirst(prefix.count))
                    guard let v = evaluate(expr, for: id, doc: doc, globals: globals) else { errors.append("\(field): cannot evaluate \(expr)"); continue }
                    if let cur = get(id, field, doc: doc), abs(cur - v) <= 1e-9 * max(1, abs(v)) { continue }
                    if PropertyAccess.set(field, fmt(v, 6), of: id, in: &doc) { passChanged = true }
                    else if let i = doc.elementIndex(id) { if doc.elements[i].props[field] != fmt(v, 6) { doc.elements[i].props[field] = fmt(v, 6); passChanged = true } }
                    else if let i = doc.entityIndex(id) { if doc.entities[i].props[field] != fmt(v, 6) { doc.entities[i].props[field] = fmt(v, 6); passChanged = true } }
                }
                let err = errors.isEmpty ? nil : errors.joined(separator: "; ")
                if let i = doc.elementIndex(id), doc.elements[i].props["exprError"] != err { doc.elements[i].props["exprError"] = err; passChanged = true }
                if let i = doc.entityIndex(id), doc.entities[i].props["exprError"] != err { doc.entities[i].props["exprError"] = err; passChanged = true }
            }
            if !passChanged { break }
            changed = true
        }
        return changed
    }
}

// MARK: - DOC-038 repeating details

/// A repeating detail is a path line (props repeatDetail = component, repeatSpacing) that owns inserts of the component
/// (props repeatOf = path id) regenerated whenever the path or spacing changes.
public enum RepeatingDetails {
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        let paths = doc.entities.filter { $0.props["repeatDetail"] != nil }
        let pathIDs = Set(paths.map(\.id))
        let orphans = Set(doc.entities.filter { e in e.props["repeatOf"].flatMap(Int.init).map { !pathIDs.contains($0) } ?? false }.map(\.id))
        if !orphans.isEmpty { doc.remove(ids: orphans); changed = true }
        for p in paths {
            guard case .line(let l) = p.geometry, let comp = p.props["repeatDetail"], let bn = DetailComponents.ensureBlock(comp, doc: &doc),
                  let c = DetailComponents.find(comp) else { continue }
            let u = 1 / doc.units.mm
            let spacing = p.props["repeatSpacing"].flatMap(Double.init) ?? c.w * u
            let ang = (l.b - l.a).angle
            let want = DetailComponents.repeatPositions(a: l.a, b: l.b, spacing: spacing).map { InsertGeom(block: bn, position: $0, rotation: ang) }
            let have = doc.entities.filter { $0.props["repeatOf"] == "\(p.id)" }
            let haveGeo = have.compactMap { e -> InsertGeom? in if case .insert(let g) = e.geometry { return g }; return nil }
            if haveGeo == want { continue }
            doc.remove(ids: Set(have.map(\.id)))
            for g in want { doc.add(Entity(layer: p.layer, geometry: .insert(g), props: ["repeatOf": "\(p.id)", "detail": "repeat", ProjectViews.ownerProp: p.props[ProjectViews.ownerProp] ?? ""].filter { !$0.value.isEmpty })) }
            changed = true
        }
        return changed
    }
}
