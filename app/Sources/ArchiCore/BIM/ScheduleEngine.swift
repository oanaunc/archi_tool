// Oanarina Archi Tool — GPL-3.0-or-later
// Schedules (DOC-041…053): evaluate ScheduleDefinitions into tables (fields, calculated/percentage fields, filters,
// sorting, grouping, totals, conditional highlights, embedded rows, key schedules), edit values back into the model,
// export/import CSV and XLSX, material takeoffs, sheet/view/note lists, and associative tables on sheets.
import Foundation

public enum Schedules {
    public enum RowKind: String { case item, groupHeader, groupTotal, grandTotal, embedded }
    public struct Row: Hashable {
        public var kind: RowKind
        public var elementID: EntityID?
        public var cells: [String]
        public var highlight: RGBA?
        /// Cell-only highlights (column index → colour).
        public var cellHighlights: [Int: RGBA] = [:]
    }
    public struct Table: Hashable {
        public var name: String
        public var headings: [String]
        public var rows: [Row]
        /// Headings followed by every row's cells.
        public var grid: [[String]] { [headings] + rows.map(\.cells) }
    }

    public static let categories = ["walls", "doors", "windows", "openings", "rooms", "areas", "slabs", "columns", "beams", "roofs", "stairs", "railings",
                                    "curtainWalls", "components", "elements", "materials", "sheets", "views", "annotations", "keys", "parts", "assemblies"]

    /// Category name from user input (singular/plural, any case); nil when unknown.
    public static func category(_ s: String) -> String? {
        let k = s.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = categories.first(where: { $0.lowercased() == k || $0.lowercased() == k + "s" || $0.lowercased().dropLast() == k }) { return c }
        switch k { case "all": return "elements"; case "material", "takeoff", "materialtakeoff": return "materials"; case "notes", "blocks": return "annotations"
        case "spaces", "space": return "rooms"; default: return nil }
    }

    /// Default columns for a category.
    public static func defaultFields(_ category: String) -> [ScheduleField] {
        func f(_ n: [String]) -> [ScheduleField] { n.map { ScheduleField(name: $0) } }
        switch category {
        case "walls": return f(["ID", "Level", "Type", "Length", "thickness", "height", "Area"])
        case "doors", "windows", "openings": return f(["mark", "Level", "Type", "width", "height", "sill", "Count"])
        case "rooms": return f(["number", "Name", "Level", "Area", "Perimeter", "height"])
        case "areas": return f(["Name", "Level", "Area"])
        case "slabs", "roofs": return f(["ID", "Level", "Type", "Area", "thickness", "Volume"])
        case "materials": return f(["Material", "Category", "ID", "Area", "Volume"])
        case "sheets": return f(["Number", "Name", "Views", "Revision"])
        case "views": return f(["Name", "Kind", "Sheet", "Scale"])
        case "annotations": return f(["Block", "Layer", "Count"])
        case "keys": return f(["Key"])
        case "parts": return f(["ID", "partOf", "Level", "Material", "thickness", "Area", "Volume"])
        case "assemblies": return f(["Name", "Type", "Members", "Categories", "Count"])
        default: return f(["ID", "Category", "Level", "Name", "Count"])
        }
    }

    // MARK: Objects

    /// One schedulable thing: a building element, a material portion of one (takeoff), a sheet, a view or a block insert.
    struct Obj {
        var id: EntityID?
        var element: BIMElement?
        var values: [String: String] = [:]   // precomputed (lower-cased names)
    }

    static func matches(_ el: BIMElement, _ category: String) -> Bool {
        if category == "parts" { return el.props["partOf"] != nil }
        if category == "walls", el.props["partOf"] != nil { return false }
        switch (category, el.geometry) {
        case ("walls", .wall), ("slabs", .slab), ("columns", .column), ("beams", .beam), ("roofs", .roof), ("stairs", .stair),
             ("railings", .railing), ("curtainWalls", .curtainWall), ("components", .component): return true
        case ("doors", .opening(let o)): return o.kind == .door
        case ("windows", .opening(let o)): return o.kind == .window
        case ("openings", .opening): return true
        case ("rooms", .space): return el.props["areaScheme"] == nil
        case ("areas", .space): return el.props["areaScheme"] != nil
        case ("elements", let g): if case .gridLine = g { return false }; return true
        default: return false
        }
    }

    static func objects(_ def: ScheduleDefinition, doc: ArchiDocument) -> [Obj] {
        switch def.category {
        case "materials": return takeoff(doc)
        case "sheets":
            return doc.layouts.enumerated().map { i, l in
                Obj(id: nil, element: nil, values: ["number": l.titleBlock["sheetNumber"] ?? l.titleBlock["Sheet"] ?? "\(i + 1)", "name": l.titleBlock["sheetName"] ?? l.name,
                                                    "views": "\(l.viewports.count)", "revision": l.titleBlock["revision"] ?? "", "paper": l.paper.name, "count": "1"])
            }
        case "views":
            var out: [Obj] = doc.namedViews.map { v in Obj(id: nil, element: nil, values: ["name": v.name, "kind": v.camera == nil ? "2D view" : "3D view", "sheet": "", "scale": "", "count": "1"]) }
            for l in doc.layouts {
                for (k, vp) in l.viewports.enumerated() {
                    let name = vp.title.isEmpty ? "\(l.name) viewport \(k + 1)" : vp.title
                    out.append(Obj(id: nil, element: nil, values: ["name": name, "kind": vp.view.rawValue, "sheet": l.name, "scale": "1:\(fmt(vp.scale))",
                                                                   "level": vp.level.flatMap { doc.level($0)?.name } ?? "", "count": "1"]))
                }
            }
            return out
        case "annotations":
            return doc.entities.compactMap { e in
                guard case .insert(let ins) = e.geometry else { return nil }
                var v: [String: String] = ["block": ins.block, "layer": e.layer, "count": "1"]
                for (k, a) in ins.attributes { v[k.lowercased()] = a }
                return Obj(id: e.id, element: nil, values: v)
            }
        case "assemblies":
            // One row per assembly (BIM-124): member count, categories and total volume.
            let els = ModelSets.scheduleModel(doc).elements.filter { $0.props["assembly"] != nil }
            return Dictionary(grouping: els, by: { $0.props["assembly"]! }).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { name, ms in
                let cats = Set(ms.map { VisibilityGraphics.category($0) }).sorted().joined(separator: ", ")
                return Obj(id: nil, element: nil, values: ["name": name, "assembly": name, "members": "\(ms.count)", "categories": cats, "count": "1",
                                                           "type": doc.variable("ASSEMBLYTYPE." + name) ?? ""])
            }
        case "keys":
            return def.keys.keys.sorted().map { k in
                var v: [String: String] = ["key": k, "count": "1"]
                for (n, x) in def.keys[k] ?? [:] { v[n.lowercased()] = x }
                return Obj(id: nil, element: nil, values: v)
            }
        default:
            return ModelSets.scheduleModel(doc).elements.filter { matches($0, def.category) }.map { Obj(id: $0.id, element: $0) }
        }
    }

    /// Material takeoff (DOC-044): the volume of every element per material, from the 3D model (compound walls give one
    /// row per ply material, openings are cut out), with the face area of layered walls/slabs.
    static func takeoff(_ doc: ArchiDocument) -> [Obj] {
        let m2 = doc.units.mm * doc.units.mm / 1e6, m3 = m2 * doc.units.mm / 1000
        var out: [Obj] = []
        for el in ModelSets.scheduleModel(doc).elements {
            switch el.geometry { case .space, .gridLine: continue; default: break }
            var vol: [String: Double] = [:]
            for g in MeshBuilder.groups(for: el, doc: doc) where !g.mesh.isEmpty {
                vol[g.material, default: 0] += abs(MeshTools.signedVolume(g.mesh))
            }
            var plyThickness: [String: Double] = [:]
            if case .wall(let w) = el.geometry, let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }) {
                for p in wt.plies { plyThickness[p.material, default: 0] += p.thickness * (w.thickness / max(wt.thickness, 1e-9)) }
            } else if case .wall(let w) = el.geometry { plyThickness[vol.keys.first ?? ""] = w.thickness }
            if case .slab(let s) = el.geometry { for k in vol.keys { plyThickness[k] = plyThickness[k] ?? s.thickness } }
            for (mat, v) in vol.sorted(by: { $0.key < $1.key }) where v > 1e-9 {
                var vals: [String: String] = ["material": mat, "category": el.typeName, "volume": fmt(v * m3, 3), "count": "1",
                                              "level": doc.level(el.level)?.name ?? "\(el.level)", "name": el.name]
                if let t = plyThickness[mat], t > 1e-9 { vals["area"] = fmt(v / t * m2, 2); vals["thickness"] = fmt(t) }
                out.append(Obj(id: el.id, element: el, values: vals))
            }
        }
        return out
    }

    // MARK: Values

    static let readOnlyComputed: Set<String> = ["id", "count", "category", "area", "volume", "length", "perimeter", "host"]

    static func name(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespaces) }

    /// Key-schedule value for an element (DOC-045): the key parameter's value selects a row of a key schedule.
    static func keyValue(_ field: String, _ el: BIMElement, doc: ArchiDocument) -> String? {
        for d in doc.schedules where d.category == "keys" {
            guard let kp = d.keyParameter, let key = el.props[kp] ?? el.props.first(where: { name($0.key) == name(kp) })?.value,
                  let row = d.keys[key], let v = row.first(where: { name($0.key) == field })?.value else { continue }
            return v
        }
        return nil
    }

    /// Text value of a field for an object (empty when not applicable).
    static func value(_ field0: String, _ o: Obj, doc: ArchiDocument) -> String {
        let field = name(field0)
        if let v = o.values[field] { return v }
        guard let el = o.element else { return "" }
        let m2 = doc.units.mm * doc.units.mm / 1e6
        switch field {
        case "id": return "\(el.id)"
        case "count": return "1"
        case "category": return el.typeName
        case "level": return doc.level(el.level)?.name ?? "\(el.level)"
        case "type", "typename":
            switch el.geometry {
            case .opening(let o): return o.typeName ?? el.name
            case .wall(let w): return w.wallType ?? "Generic"
            default: return el.props["slabType"] ?? el.props["family"] ?? el.name
            }
        case "name":
            if case .space(let s) = el.geometry { return s.name }
            return el.name
        case "number": if case .space(let s) = el.geometry { return s.number }
        case "mark": if case .opening(let o) = el.geometry { return o.mark ?? el.props["mark"] ?? "" }
        case "host":
            // Hosted components / openings: the host's category and id.
            if case .opening(let o) = el.geometry { return doc.element(o.hostWall).map { "\($0.typeName) #\($0.id)" } ?? "" }
            if let h = el.props["host"].flatMap(Int.init), let he = doc.element(h) { return "\(he.props["kind"] == "ceiling" ? "ceiling" : he.typeName) #\(he.id)" }
            return ""
        case "material":
            if let m = el.material { return m }
            if case .wall(let w) = el.geometry, let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }) { return wt.plies.map(\.material).joined(separator: " / ") }
            return ""
        case "area":
            switch el.geometry {
            case .space(let s): return fmt(abs(GeometryOps.signedArea(s.boundary)) * m2, 2)
            case .slab(let s): return fmt((abs(GeometryOps.signedArea(s.boundary)) - s.holes.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }) * m2, 2)
            case .roof(let r): return fmt(abs(GeometryOps.signedArea(r.boundary)) / max(cos(r.pitch * .pi / 180), 0.05) * m2, 2)
            case .wall(let w):
                let h = BIMConstraints.wallHeight(el, doc: doc)
                let openings = doc.elements.reduce(0.0) { acc, e in if case .opening(let o) = e.geometry, o.hostWall == el.id { return acc + o.width * o.height }; return acc }
                return fmt(max(w.length * h - openings, 0) * m2, 2)
            case .opening(let o): return fmt(o.width * o.height * m2, 2)
            case .curtainWall(let c): return fmt(c.length * c.height * m2, 2)
            default: return ""
            }
        case "volume":
            if case .space(let s) = el.geometry { return fmt(abs(GeometryOps.signedArea(s.boundary)) * s.height * m2 * doc.units.mm / 1000, 2) }
            let v = MeshBuilder.groups(for: el, doc: doc).reduce(0.0) { $0 + abs(MeshTools.signedVolume($1.mesh)) }
            return v > 0 ? fmt(v * m2 * doc.units.mm / 1000, 3) : ""
        case "length":
            switch el.geometry {
            case .wall(let w): return fmt(w.length)
            case .beam(let b): return fmt(b.start.distance(to: b.end))
            case .curtainWall(let c): return fmt(c.length)
            case .railing(let r): return fmt(CommandHelpers.polylineLength(r.path))
            default: return ""
            }
        case "image", "typeimage":
            // Type images (DOC-048): shown as pictures in placed schedules.
            let t = value("type", o, doc: doc)
            return doc.variable("TYPEIMAGE." + t).map { "img:" + $0 } ?? ""
        case "perimeter":
            switch el.geometry {
            case .space(let s): return fmt(CommandHelpers.polylineLength(s.boundary + [s.boundary.first ?? .zero]))
            case .slab(let s): return fmt(CommandHelpers.polylineLength(s.boundary + [s.boundary.first ?? .zero]))
            default: return ""
            }
        default: break
        }
        if let p = PropertyAccess.properties(of: el.id, in: doc).first(where: { name($0.name) == field }) { return p.value }
        if let v = el.props.first(where: { name($0.key) == field })?.value { return v }
        if let v = ProjectParameters.value(field, of: el, doc: doc) { return v }
        return keyValue(field, el, doc: doc) ?? ""
    }

    /// Sets a field of an element from a schedule cell (DOC-042). False for read-only fields or invalid values.
    @discardableResult
    public static func setValue(_ field0: String, _ value: String, of id: EntityID, doc: inout ArchiDocument) -> Bool {
        let field = name(field0)
        guard !readOnlyComputed.contains(field), let i = doc.elementIndex(id) else { return false }
        let v = value.trimmingCharacters(in: .whitespaces)
        switch field {
        case "level":
            guard let l = doc.levels.first(where: { $0.name.caseInsensitiveCompare(v) == .orderedSame }) ?? Int(v).flatMap({ doc.level($0) }) else { return false }
            doc.elements[i].level = l.id; return true
        case "type", "typename":
            switch doc.elements[i].geometry {
            case .opening: return PropertyAccess.set("typeName", v, of: id, in: &doc)
            case .wall: return PropertyAccess.set("wallType", v, of: id, in: &doc)
            default: doc.elements[i].name = v; return true
            }
        case "name":
            if case .space(var s) = doc.elements[i].geometry { s.name = v; doc.elements[i].geometry = .space(s); return true }
            doc.elements[i].name = v; return true
        case "number":
            if case .space(var s) = doc.elements[i].geometry { s.number = v; doc.elements[i].geometry = .space(s); return true }
        case "mark":
            if case .opening(var o) = doc.elements[i].geometry { o.mark = v.isEmpty ? nil : v; doc.elements[i].geometry = .opening(o); return true }
        case "image", "typeimage":
            let t = Schedules.value("type", Obj(id: id, element: doc.elements[i]), doc: doc)
            let path = v.hasPrefix("img:") ? String(v.dropFirst(4)) : v
            if path.isEmpty { doc.variables["TYPEIMAGE." + t.uppercased()] = nil } else { doc.setVariable("TYPEIMAGE." + t, path) }
            return true
        default: break
        }
        if let p = PropertyAccess.properties(of: id, in: doc).first(where: { name($0.name) == field }) {
            return !p.readOnly && PropertyAccess.set(p.name, v, of: id, in: &doc)
        }
        // Custom parameter (instance props), keeping an existing key's spelling.
        let key = doc.elements[i].props.keys.first { name($0) == field } ?? field0.trimmingCharacters(in: .whitespaces)
        doc.elements[i].props[key] = v.isEmpty ? nil : v
        return true
    }

    // MARK: Evaluation

    static func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) }

    static func compare(_ a: String, _ op: String, _ b: String) -> Bool {
        if let x = num(a), let y = num(b) {
            switch op { case "=", "==": return abs(x - y) < 1e-9; case "!=", "<>": return abs(x - y) >= 1e-9; case ">": return x > y; case "<": return x < y
            case ">=": return x >= y - 1e-9; case "<=": return x <= y + 1e-9; default: break }
        }
        let l = a.lowercased(), r = b.lowercased()
        switch op.lowercased() {
        case "=", "==": return l == r
        case "!=", "<>": return l != r
        case ">": return l > r
        case "<": return l < r
        case ">=": return l >= r
        case "<=": return l <= r
        case "contains": return l.contains(r)
        case "begins", "beginswith": return l.hasPrefix(r)
        default: return false
        }
    }

    static let autoTotal: Set<String> = ["area", "volume", "length", "count", "perimeter"]

    static func isTotalled(_ f: ScheduleField) -> Bool { f.total ?? (autoTotal.contains(name(f.name)) || f.formula != nil) }

    static func format(_ v: Double, _ f: ScheduleField) -> String {
        if let d = f.decimals { return String(format: "%.\(max(0, min(d, 8)))f", v) }
        return fmt(v, 3)
    }

    /// Evaluates a schedule definition against the document.
    public static func evaluate(_ def: ScheduleDefinition, doc: ArchiDocument) -> Table {
        let fields = def.fields.isEmpty ? defaultFields(def.category) : def.fields
        var objs = objects(def, doc: doc)
        // Raw (non-calculated) values.
        func raw(_ o: Obj) -> [String] { fields.map { $0.isCalculated ? "" : value($0.name, o, doc: doc) } }
        var rows: [(obj: Obj, cells: [String])] = objs.map { ($0, raw($0)) }
        // Filters (on any field, scheduled or not).
        rows = rows.filter { r in def.filters.allSatisfy { flt in
            let v = fields.firstIndex { name($0.name) == name(flt.field) || name($0.title) == name(flt.field) }.map { r.cells[$0] } ?? value(flt.field, r.obj, doc: doc)
            return compare(v, flt.op, flt.value) } }
        objs = rows.map(\.obj)
        // Calculated fields (formulas over the row's numeric fields).
        for (k, f) in fields.enumerated() where f.formula != nil {
            for i in rows.indices {
                var vars: [String: Double] = [:]
                for (j, g) in fields.enumerated() where j != k { if let x = num(rows[i].cells[j]) { vars[name(g.name).replacingOccurrences(of: " ", with: "_")] = x; vars[name(g.title).replacingOccurrences(of: " ", with: "_")] = x } }
                let expr = f.formula!.lowercased()
                rows[i].cells[k] = FamilyExpr.evaluate(expr, vars).map { format($0, f) } ?? "?"
            }
        }
        for (k, f) in fields.enumerated() where f.percentOf != nil {
            guard let j = fields.firstIndex(where: { name($0.name) == name(f.percentOf!) || name($0.title) == name(f.percentOf!) }) else { continue }
            let total = rows.reduce(0) { $0 + (num($1.cells[j]) ?? 0) }
            for i in rows.indices { rows[i].cells[k] = total > 0 ? String(format: "%.\(f.decimals ?? 1)f%%", (num(rows[i].cells[j]) ?? 0) / total * 100) : "" }
        }
        // Sorting (group field first).
        let groupIdx = def.groupBy.flatMap { g in fields.firstIndex { name($0.name) == name(g) || name($0.title) == name(g) } }
        func groupValue(_ r: (obj: Obj, cells: [String])) -> String { groupIdx.map { r.cells[$0] } ?? def.groupBy.map { value($0, r.obj, doc: doc) } ?? "" }
        var keys: [(field: String, desc: Bool)] = def.sort.map { ($0.field, $0.descending) }
        if let g = def.groupBy, !keys.contains(where: { name($0.field) == name(g) }) { keys.insert((g, false), at: 0) }
        func cell(_ r: (obj: Obj, cells: [String]), _ fname: String) -> String {
            fields.firstIndex { name($0.name) == name(fname) || name($0.title) == name(fname) }.map { r.cells[$0] } ?? value(fname, r.obj, doc: doc)
        }
        if !keys.isEmpty {
            rows.sort { a, b in
                for k in keys {
                    let x = cell(a, k.field), y = cell(b, k.field)
                    if x == y { continue }
                    let less: Bool
                    if let p = num(x), let q = num(y) { less = p < q } else { less = x.localizedStandardCompare(y) == .orderedAscending }
                    return k.desc ? !less : less
                }
                return (a.obj.id ?? 0) < (b.obj.id ?? 0)
            }
        }
        func totals(_ rs: [(obj: Obj, cells: [String])], label: String) -> [String] {
            var out = Array(repeating: "", count: fields.count)
            for (k, f) in fields.enumerated() where isTotalled(f) && f.percentOf == nil {
                let s = rs.reduce(0.0) { $0 + (num($1.cells[k]) ?? 0) }
                out[k] = name(f.name) == "count" ? "\(rs.count)" : format(s, f)
            }
            if let first = out.indices.first(where: { out[$0].isEmpty }) { out[first] = label }
            return out
        }
        func highlight(_ r: (obj: Obj, cells: [String])) -> RGBA? {
            def.highlights.first { h in h.cellOnly != true && compare(cell(r, h.field), h.op, h.value) }?.color
        }
        // Cell-only conditional formatting (DOC-052): the tested field's cell.
        func cellHL(_ r: (obj: Obj, cells: [String])) -> [Int: RGBA] {
            var out: [Int: RGBA] = [:]
            for h in def.highlights where h.cellOnly == true && compare(cell(r, h.field), h.op, h.value) {
                if let k = fields.firstIndex(where: { name($0.name) == name(h.field) }), out[k] == nil { out[k] = h.color }
            }
            return out
        }
        var out: [Row] = []
        func emitItems(_ rs: [(obj: Obj, cells: [String])]) {
            for r in rs {
                out.append(Row(kind: .item, elementID: r.obj.id, cells: r.cells, highlight: highlight(r), cellHighlights: cellHL(r)))
                if let emb = def.embedded, let el = r.obj.element { out += embeddedRows(emb, host: el, doc: doc, width: fields.count) }
            }
        }
        if def.groupBy != nil {
            var groups: [(String, [(obj: Obj, cells: [String])])] = []
            for r in rows {
                let g = groupValue(r)
                if let i = groups.firstIndex(where: { $0.0 == g }) { groups[i].1.append(r) } else { groups.append((g, [r])) }
            }
            for (g, rs) in groups {
                if def.itemize {
                    out.append(Row(kind: .groupHeader, elementID: nil, cells: [g.isEmpty ? "(none)" : g] + Array(repeating: "", count: max(fields.count - 1, 0)), highlight: nil))
                    emitItems(rs)
                    if def.totals { out.append(Row(kind: .groupTotal, elementID: nil, cells: totals(rs, label: "\(g): \(rs.count)"), highlight: nil)) }
                } else {
                    // One line per group: the group value, shared values, and totals.
                    var c = totals(rs, label: "")
                    for (k, f) in fields.enumerated() where !isTotalled(f) {
                        let vals = Set(rs.map { $0.cells[k] })
                        c[k] = vals.count == 1 ? vals.first! : (k == groupIdx ? g : "<varies>")
                    }
                    out.append(Row(kind: .item, elementID: nil, cells: c, highlight: rs.first.flatMap(highlight)))
                }
            }
        } else if def.itemize {
            emitItems(rows)
        } else {
            // Not itemized without grouping: identical rows merge (Revit behaviour).
            var merged: [([String], [(obj: Obj, cells: [String])])] = []
            let keyCols = fields.indices.filter { !isTotalled(fields[$0]) }
            for r in rows {
                let key = keyCols.map { r.cells[$0] }
                if let i = merged.firstIndex(where: { $0.0 == key }) { merged[i].1.append(r) } else { merged.append((key, [r])) }
            }
            for (_, rs) in merged {
                var c = totals(rs, label: "")
                for k in keyCols { c[k] = rs[0].cells[k] }
                out.append(Row(kind: .item, elementID: nil, cells: c, highlight: rs.first.flatMap(highlight)))
            }
        }
        if def.totals { out.append(Row(kind: .grandTotal, elementID: nil, cells: totals(rows, label: "Total: \(rows.count)"), highlight: nil)) }
        return Table(name: def.name, headings: fields.map(\.title), rows: out)
    }

    /// Embedded rows (DOC-051): doors/windows of a room (openings whose wall passes along the room boundary and whose
    /// centre is next to it), or the openings hosted by a wall.
    static func embeddedRows(_ category: String, host: BIMElement, doc: ArchiDocument, width: Int) -> [Row] {
        guard let cat = self.category(category) else { return [] }
        var hits: [BIMElement] = []
        for el in doc.elements where matches(el, cat) {
            guard case .opening(let o) = el.geometry, let wall = doc.element(o.hostWall), case .wall(let w) = wall.geometry else { continue }
            switch host.geometry {
            case .wall: if o.hostWall == host.id { hits.append(el) }
            case .space(let s):
                let d = w.direction, c = w.centerStart + d * o.offset, n = d.perp * (w.thickness / 2 + 50 / doc.units.mm)
                if GeometryOps.pointInPolygon(c + n, s.boundary) || GeometryOps.pointInPolygon(c - n, s.boundary) { hits.append(el) }
            default: break
            }
        }
        return hits.map { el in
            var cells = Array(repeating: "", count: max(width, 2))
            if case .opening(let o) = el.geometry { cells[0] = "  " + (o.mark ?? "#\(el.id)"); cells[1] = "\(o.typeName ?? el.name) \(fmt(o.width))×\(fmt(o.height))" }
            return Row(kind: .embedded, elementID: el.id, cells: cells, highlight: nil)
        }
    }

    // MARK: Editing, export and import

    /// Edits one cell of an evaluated schedule: `row` is the index of an item row (0-based, headings excluded).
    public static func edit(_ def: ScheduleDefinition, row: Int, field: String, value: String, doc: inout ArchiDocument) -> Bool {
        let t = evaluate(def, doc: doc)
        let items = t.rows.filter { $0.kind == .item || $0.kind == .embedded }
        guard row >= 0, row < items.count, let id = items[row].elementID else { return false }
        let fields = def.fields.isEmpty ? defaultFields(def.category) : def.fields
        let fname = fields.first { name($0.title) == name(field) || name($0.name) == name(field) }?.name ?? field
        if fields.first(where: { name($0.name) == name(fname) })?.isCalculated == true { return false }
        if def.category == "materials" { return false }
        return setValue(fname, value, of: id, doc: &doc)
    }

    /// CSV of a table with an element ID column first, so the exported file can be edited and read back.
    public static func csv(_ t: Table, withIDs: Bool = true) -> String {
        func q(_ s: String) -> String { s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        var lines = [(withIDs ? ["ElementID"] : []) + t.headings]
        for r in t.rows { lines.append((withIDs ? [r.elementID.map { "\($0)" } ?? ""] : []) + r.cells) }
        return lines.map { $0.map(q).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    public static func xlsx(_ t: Table) -> Data {
        XLSX.write([XLSX.Sheet(name: t.name, rows: [["ElementID"] + t.headings] + t.rows.map { [$0.elementID.map { "\($0)" } ?? ""] + $0.cells })])
    }

    /// Applies an edited export (CSV/XLSX rows with the ElementID column and headings) back to the model: every
    /// changed, editable cell of an item row updates its element. Returns (cells changed, messages for rejected cells).
    public static func applyEdits(_ def: ScheduleDefinition, rows grid: [[String]], doc: inout ArchiDocument) -> (changed: Int, rejected: [String]) {
        guard let head = grid.first, let idCol = head.firstIndex(where: { name($0) == "elementid" || name($0) == "id" }) else { return (0, ["No ElementID column."]) }
        let fields = def.fields.isEmpty ? defaultFields(def.category) : def.fields
        let current = evaluate(def, doc: doc)
        var byID: [EntityID: [String]] = [:]
        for r in current.rows where r.kind == .item || r.kind == .embedded { if let id = r.elementID, byID[id] == nil { byID[id] = r.cells } }
        var changed = 0
        var rejected: [String] = []
        for r in grid.dropFirst() {
            guard idCol < r.count, let id = Int(r[idCol].trimmingCharacters(in: .whitespaces)), let cur = byID[id] else { continue }
            for (c, h) in head.enumerated() where c != idCol && c < r.count {
                guard let k = fields.firstIndex(where: { name($0.title) == name(h) || name($0.name) == name(h) }), k < cur.count else { continue }
                let newV = r[c].trimmingCharacters(in: .whitespaces)
                if newV == cur[k] || (num(newV) != nil && num(cur[k]) != nil && abs(num(newV)! - num(cur[k])!) < 1e-9) { continue }
                if fields[k].isCalculated || readOnlyComputed.contains(name(fields[k].name)) || def.category == "materials" {
                    rejected.append("#\(id) \(h): read-only"); continue
                }
                if setValue(fields[k].name, newV, of: id, doc: &doc) { changed += 1 } else { rejected.append("#\(id) \(h) = \(newV): invalid") }
            }
        }
        return (changed, rejected)
    }

    /// Parses CSV text into rows (RFC 4180 quotes).
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cur = ""
        var inQ = false
        var it = Array(text).makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            if inQ {
                if ch == "\"" { if let n = it.next() { if n == "\"" { cur.append("\"") } else { inQ = false; pending = n } } else { inQ = false } }
                else { cur.append(ch) }
            } else {
                switch ch {
                case "\"": inQ = true
                case ",": row.append(cur); cur = ""
                case "\r": continue
                case "\n", "\r\n": row.append(cur); cur = ""; rows.append(row); row = []   // CRLF is one Character in Swift
                default: cur.append(ch)
                }
            }
        }
        if !cur.isEmpty || !row.isEmpty { row.append(cur); rows.append(row) }
        return rows
    }

    // MARK: Placement on sheets (DOC-053)

    public static let placedProp = "schedule"

    /// Table segments of a schedule: title and heading rows on every segment, at most `maxRows` data rows each.
    static func segments(_ t: Table, maxRows: Int) -> [[[String]]] {
        let n = max(maxRows, 1)
        let body = t.rows.map(\.cells)
        let cols = max(t.headings.count, 1)
        let title = [t.name] + Array(repeating: "", count: cols - 1)
        if body.isEmpty { return [[title, t.headings]] }
        return stride(from: 0, to: body.count, by: n).map { i in [title, t.headings] + body[i..<min(i + n, body.count)] }
    }

    static func tableGeoms(_ t: Table, origin: Vec2, maxRows: Int, textHeight th: Double) -> [TableGeom] {
        let segs = segments(t, maxRows: maxRows)
        let cols = max(t.headings.count, 1)
        var widths = Array(repeating: th * 4, count: cols)
        for r in [t.headings] + t.rows.map(\.cells) { for (i, c) in r.enumerated() where i < cols { widths[i] = max(widths[i], Double(c.count) * th * 0.75 + th * 1.5) } }
        let total = widths.reduce(0, +), gap = th * 4
        let n = max(maxRows, 1)
        return segs.enumerated().map { k, cells in
            var g = TableGeom(origin: origin + Vec2(Double(k) * (total + gap), 0), columnWidths: widths, rowHeight: th * 2, cells: cells, textHeight: th)
            // Conditional formatting: highlighted rows and cells as cell fills (title and heading rows come first).
            var fills: [String: RGBA] = [:]
            for j in 0..<max(cells.count - 2, 0) where k * n + j < t.rows.count {
                let row = t.rows[k * n + j]
                if let c = row.highlight { for col in 0..<cols { fills["\(j + 2),\(col)"] = c } }
                for (col, c) in row.cellHighlights { fills["\(j + 2),\(col)"] = c }
            }
            if !fills.isEmpty { g.fills = fills }
            return g
        }
    }

    /// Places a schedule as associative table(s) on a sheet (layout index) or in model space (nil), split into side-by-side
    /// columns of at most `maxRows` rows. Replaces an earlier placement of the same schedule on that sheet.
    @discardableResult
    public static func place(_ def: ScheduleDefinition, doc: inout ArchiDocument, layout: Int?, at p: Vec2, maxRows: Int, textHeight: Double, layer: String = "A-ANNO-SCHD") -> Int {
        let t = evaluate(def, doc: doc)
        let geoms = tableGeoms(t, origin: p, maxRows: maxRows, textHeight: textHeight)
        func tag(_ g: TableGeom, _ k: Int) -> Entity {
            Entity(id: 0, layer: layer, geometry: .table(g), props: [placedProp: def.name, "scheduleSeg": "\(k)", "scheduleMaxRows": "\(maxRows)",
                                                                      "scheduleOrigin": "\(fmt(p.x, 6)),\(fmt(p.y, 6))", "scheduleTextHeight": fmt(textHeight, 6)])
        }
        if let li = layout, doc.layouts.indices.contains(li) {
            doc.layouts[li].entities.removeAll { $0.props[placedProp] == def.name }
            for (k, g) in geoms.enumerated() { var e = tag(g, k); e.id = doc.allocateID(); doc.layouts[li].entities.append(e) }
        } else {
            doc.entities.removeAll { $0.props[placedProp] == def.name }
            doc.ensureLayer(layer)
            for (k, g) in geoms.enumerated() { doc.add(tag(g, k)) }
        }
        return geoms.count
    }

    /// Placed schedules follow the model: tables are re-evaluated (and re-split) after every edit. Key schedules push their
    /// values into elements carrying a key. Returns true if anything changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        guard !doc.schedules.isEmpty else { return false }
        var changed = false
        // Key schedules: elements with a key get the key's parameter values (DOC-045).
        for d in doc.schedules where d.category == "keys" {
            guard let kp = d.keyParameter else { continue }
            for i in doc.elements.indices {
                guard let key = doc.elements[i].props[kp], let row = d.keys[key] else { continue }
                for (n, v) in row where doc.elements[i].props[n] != v { doc.elements[i].props[n] = v; changed = true }
            }
        }
        func refresh(_ ents: [Entity]) -> [Entity]? {
            let names = Set(ents.compactMap { $0.props[placedProp] })
            guard !names.isEmpty else { return nil }
            var out = ents
            var any = false
            for n in names {
                guard let def = doc.schedules.first(where: { $0.name == n }), let first = ents.first(where: { $0.props[placedProp] == n }) else { continue }
                let maxRows = first.props["scheduleMaxRows"].flatMap(Int.init) ?? 30
                let th = first.props["scheduleTextHeight"].flatMap(Double.init) ?? 2.5
                let o = first.props["scheduleOrigin"]?.split(separator: ",").compactMap { Double($0) }
                let origin = (o?.count == 2) ? Vec2(o![0], o![1]) : { if case .table(let g) = first.geometry { return g.origin }; return .zero }()
                let geoms = tableGeoms(evaluate(def, doc: doc), origin: origin, maxRows: maxRows, textHeight: th)
                let old = ents.filter { $0.props[placedProp] == n }.sorted { (Int($0.props["scheduleSeg"] ?? "0") ?? 0) < (Int($1.props["scheduleSeg"] ?? "0") ?? 0) }
                let oldGeoms = old.compactMap { e -> TableGeom? in if case .table(let g) = e.geometry { return g }; return nil }
                if oldGeoms == geoms { continue }
                any = true
                out.removeAll { $0.props[placedProp] == n }
                for (k, g) in geoms.enumerated() {
                    var e = k < old.count ? old[k] : first
                    if k >= old.count { e.id = doc.allocateID() }
                    e.geometry = .table(g); e.props["scheduleSeg"] = "\(k)"
                    out.append(e)
                }
            }
            return any ? out : nil
        }
        if let e = refresh(doc.entities) { doc.entities = e; changed = true }
        for li in doc.layouts.indices { if let e = refresh(doc.layouts[li].entities) { doc.layouts[li].entities = e; changed = true } }
        return changed
    }
}
