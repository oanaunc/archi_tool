// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Selection tools: quick select, filters, select similar, invert, by layer/type, chains, named sets.
enum SelectionCommands {
    static var all: [CommandDef] { [qselect, filter, selectSimilar, invert, byLayer, byType, chain, intersecting, selset] }

    /// Candidate objects: every selectable entity and element of the current level.
    @MainActor static func candidates(_ ed: Editor) -> [EntityID] {
        ed.doc.entities.filter { ed.isSelectable($0.id) }.map(\.id)
            + ed.doc.elements.filter { ed.isSelectable($0.id) && $0.level == ed.doc.currentLevel }.map(\.id)
    }

    /// Applies a result to the selection: New replaces, Append adds, Exclude removes.
    @MainActor static func applyResult(_ ed: Editor, _ ids: [EntityID], mode: String) {
        switch mode {
        case "Append": ed.selection.formUnion(ids)
        case "Exclude": ed.selection.subtract(ids)
        default: ed.selection = Set(ids)
        }
        ed.previousSelection = ed.selection
        ed.print("\(ids.count) object(s) matched; \(ed.selection.count) selected.")
    }

    static var qselect: CommandDef {
        CommandDef("QSELECT", aliases: ["QSEL"], category: "Select", summary: "Quick select: objects of a type whose property matches a value (e.g. QSELECT Circle radius > 50).", modifies: false) { ed in
            guard let type = try await ed.getWord("Enter object type (Circle, Line, Text, Insert, Wall… or * for all)", defaultValue: "*") else { return }
            guard let prop = try await ed.getWord("Enter property (layer, color, radius, length, area, height, contents, name… or * for type only)", defaultValue: "*") else { return }
            var ids = candidates(ed).filter { ObjectQuery.typeMatches($0, type, doc: ed.doc) }
            if prop != "*" {
                let opWord = try await ed.getWord("Enter operator [= != > < >= <=]", defaultValue: "=") ?? "="
                // "radius>50" typed as one token is also accepted.
                var criterion: ObjectQuery.Criterion
                if let op = ObjectQuery.Criterion.op(opWord) {
                    guard let value = try await ed.getWord("Enter value") else { return }
                    criterion = ObjectQuery.Criterion(prop, op, value)
                } else if let c = ObjectQuery.Criterion(parse: prop + opWord) {
                    criterion = c
                } else { throw CommandError.invalid("Unknown operator \(opWord).") }
                ids = ids.filter { criterion.matches($0, doc: ed.doc) }
            }
            let mode = try await ed.getKeyword("How to apply", ["New", "Append", "Exclude"], defaultValue: "New") ?? "New"
            applyResult(ed, ids, mode: mode)
        }
    }

    static var filter: CommandDef {
        CommandDef("FILTER", aliases: ["FI", "SELECTFILTER"], category: "Select", summary: "Selects objects matching a filter expression (type=circle & radius>50 | layer=A-*); filters can be saved by name.") { ed in
            let k = try await ed.getWord("Enter filter expression or [Save/Use/Delete/List]", keywords: ["Save", "Use", "Delete", "List"]) ?? ""
            var expr = k
            switch k {
            case "List":
                let names = ed.doc.variables.keys.filter { $0.hasPrefix("FILTER:") }.sorted()
                if names.isEmpty { ed.print("No saved filters.") }
                for n in names { ed.print("  \(n.dropFirst(7)): \(ed.doc.variables[n] ?? "")") }
                return
            case "Save":
                guard let n = try await ed.getWord("Enter filter name"), UserAliases.isValidName(n.uppercased()) else { throw CommandError.invalid("Invalid name.") }
                guard let e = try await ed.getString("Enter filter expression"), ObjectQuery.Filter(parse: e) != nil else { throw CommandError.invalid("Invalid filter expression.") }
                ed.transactionlessSetVariable("FILTER:" + n, e)
                ed.print("Filter \(n.uppercased()) saved."); return
            case "Delete":
                guard let n = try await ed.getWord("Enter filter name") else { return }
                ed.transactionlessSetVariable("FILTER:" + n, nil); return
            case "Use":
                guard let n = try await ed.getWord("Enter filter name"), let e = ed.doc.variable("FILTER:" + n) else { throw CommandError.invalid("Filter not found.") }
                expr = e
            default:
                if expr.isEmpty { return }
            }
            guard let f = ObjectQuery.Filter(parse: expr) else { throw CommandError.invalid("Invalid filter expression. Use property op value, e.g. type=circle & radius>=50 | layer=A-*.") }
            let pool = ed.selection.isEmpty ? candidates(ed) : Array(ed.selection)
            applyResult(ed, pool.filter { f.matches($0, doc: ed.doc) }, mode: "New")
        }
    }

    static var selectSimilar: CommandDef {
        CommandDef("SELECTSIMILAR", aliases: ["SELSIM"], category: "Select", summary: "Selects all objects similar to the selected ones (type, plus the properties in SELECTSIMILARMODE).") { ed in
            var seeds = Array(ed.selection)
            if seeds.isEmpty {
                while true {
                    let a = try await ed.pickObject("Select objects or [SEttings]", keywords: ["SEttings"])
                    switch a {
                    case .pick(let pk): seeds.append(pk.id); ed.selection.insert(pk.id); continue
                    case .keyword:
                        let cur = Int(ed.doc.variable("SELECTSIMILARMODE") ?? "") ?? ObjectQuery.SimilarMode.default.rawValue
                        ed.print("Similar based on: " + describe(ObjectQuery.SimilarMode(rawValue: cur)))
                        let v = try await ed.getWord("Enter properties to match (Color,Layer,Linetype,LTscale,Lineweight,Style,Name) or a SELECTSIMILARMODE value", defaultValue: "\(cur)") ?? "\(cur)"
                        guard let m = parseMode(v) else { throw CommandError.invalid("Invalid settings.") }
                        ed.doc.setVariable("SELECTSIMILARMODE", "\(m.rawValue)")
                        continue
                    default: break
                    }
                    break
                }
            }
            guard !seeds.isEmpty else { return }
            let mode = ObjectQuery.SimilarMode(rawValue: Int(ed.doc.variable("SELECTSIMILARMODE") ?? "") ?? ObjectQuery.SimilarMode.default.rawValue)
            let ids = candidates(ed).filter { c in seeds.contains { ObjectQuery.similar($0, c, mode: mode, doc: ed.doc) } }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) selected.")
        }
    }
    static func describe(_ m: ObjectQuery.SimilarMode) -> String {
        let names: [(ObjectQuery.SimilarMode, String)] = [(.color, "Color"), (.layer, "Layer"), (.linetype, "Linetype"), (.ltscale, "LTscale"), (.lineweight, "Lineweight"), (.plotStyle, "Plotstyle"), (.style, "Style"), (.name, "Name")]
        let s = names.filter { m.contains($0.0) }.map(\.1)
        return s.isEmpty ? "type only" : "type, " + s.joined(separator: ", ")
    }
    static func parseMode(_ v: String) -> ObjectQuery.SimilarMode? {
        if let n = Int(v), (0...255).contains(n) { return ObjectQuery.SimilarMode(rawValue: n) }
        var m = ObjectQuery.SimilarMode()
        for p in v.split(whereSeparator: { $0 == "," || $0 == " " }) {
            switch p.lowercased() {
            case "color", "c": m.insert(.color)
            case "layer", "la": m.insert(.layer)
            case "linetype", "lt": m.insert(.linetype)
            case "ltscale", "lts": m.insert(.ltscale)
            case "lineweight", "lw": m.insert(.lineweight)
            case "plotstyle": m.insert(.plotStyle)
            case "style", "s": m.insert(.style)
            case "name", "n": m.insert(.name)
            case "none", "type": break
            default: return nil
            }
        }
        return m
    }

    static var invert: CommandDef {
        CommandDef("SELECTINVERT", aliases: ["INVSEL", "SELINV"], category: "Select", summary: "Inverts the selection (selects every other selectable object).", modifies: false) { ed in
            let cur = ed.selection
            let ids = candidates(ed).filter { !cur.contains($0) }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) selected.")
        }
    }

    static var byLayer: CommandDef {
        CommandDef("SELECTLAYER", aliases: ["SELLAYER", "LAYSEL"], category: "Select", summary: "Selects every object on the given layer(s) (wildcards allowed) or on the layer of a picked object.", modifies: false) { ed in
            let a = try await ed.getWord("Enter layer name(s) or [Pick]", defaultValue: "Pick", keywords: ["Pick"]) ?? "Pick"
            var pats: [String]
            if a == "Pick" {
                guard case .pick(let pk) = try await ed.pickObject("Select object on the layer") else { return }
                pats = [ed.doc.entity(pk.id)?.layer ?? ed.doc.element(pk.id)?.layer ?? ""]
            } else { pats = a.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            let ids = candidates(ed).filter { id in
                let l = ed.doc.entity(id)?.layer ?? ed.doc.element(id)?.layer ?? ""
                return pats.contains { ObjectQuery.wildcard(l.lowercased(), $0.lowercased()) }
            }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) selected on \(pats.joined(separator: ", ")).")
        }
    }

    static var byType: CommandDef {
        CommandDef("SELECTTYPE", aliases: ["SELTYPE"], category: "Select", summary: "Selects objects by type or category (Line, Circle, Text, Annotation, Curve, Wall, Door, Element…); several types separated by commas.", modifies: false) { ed in
            guard let t = try await ed.getWord("Enter object type(s)") else { return }
            let types = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let pool = ed.selection.isEmpty ? candidates(ed) : Array(ed.selection)
            let ids = pool.filter { id in types.contains { ObjectQuery.typeMatches(id, $0, doc: ed.doc) } }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) selected.")
        }
    }

    static var chain: CommandDef {
        CommandDef("SELECTCHAIN", aliases: ["SELCHAIN", "SELECTCONTOUR"], category: "Select", summary: "Selects the chain (contour) of curves connected end-to-end with the picked one.", modifies: false) { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select a curve of the contour", filter: { ed.doc.entity($0) != nil }) else { return }
            let tol = max(ed.variableDouble("CHAINTOL", 1e-6), 1e-9)
            let ids = SelectionTools.chain(from: pk.id, doc: ed.doc, tolerance: tol).filter { ed.isSelectable($0) }
            ed.selection = Set(ids)
            ed.print("\(ids.count) object(s) in the contour.")
        }
    }

    static var intersecting: CommandDef {
        CommandDef("SELECTINTERSECTING", aliases: ["SELINT"], category: "Select", summary: "Selects every object that intersects the picked one.", modifies: false) { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select object", filter: { ed.doc.entity($0) != nil }), let e = ed.doc.entity(pk.id) else { return }
            var ids = [pk.id]
            let b = GeometryOps.bounds(e.geometry, doc: ed.doc)
            for o in ed.doc.entities where o.id != e.id && ed.isSelectable(o.id) && GeometryOps.bounds(o.geometry, doc: ed.doc).intersects(b.expanded(by: 1e-6)) {
                if !Intersections.of(e.geometry, o.geometry, doc: ed.doc).isEmpty { ids.append(o.id) }
            }
            ed.selection = Set(ids)
            ed.print("\(ids.count - 1) intersecting object(s) selected.")
        }
    }

    static var selset: CommandDef {
        CommandDef("SELSET", aliases: ["NAMEDSELECTION"], category: "Select", summary: "Saves, restores, lists and deletes named selection sets (stored in the drawing).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Save", "Restore", "Delete", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "List":
                let names = ed.doc.variables.keys.filter { $0.hasPrefix("SELSET:") }.sorted()
                if names.isEmpty { ed.print("No named selection sets.") }
                for n in names { ed.print("  \(n.dropFirst(7)): \(SelectionTools.ids(ed.doc.variables[n] ?? "").filter { ed.doc.contains($0) }.count) object(s)") }
            case "Save":
                guard let n = try await ed.getWord("Enter selection set name"), UserAliases.isValidName(n.uppercased()) else { throw CommandError.invalid("Invalid name.") }
                let ids = try await ed.getSelection("Select objects")
                guard !ids.isEmpty else { return }
                ed.doc.setVariable("SELSET:" + n, ids.sorted().map(String.init).joined(separator: ","))
                ed.print("Selection set \(n.uppercased()) saved with \(ids.count) object(s).")
            case "Restore":
                guard let n = try await ed.getWord("Enter selection set name"), let v = ed.doc.variable("SELSET:" + n) else { throw CommandError.invalid("Selection set not found.") }
                let ids = SelectionTools.ids(v).filter { ed.doc.contains($0) && ed.isSelectable($0) }
                ed.selection = Set(ids); ed.previousSelection = Set(ids)
                ed.print("\(ids.count) object(s) selected.")
            default:
                guard let n = try await ed.getWord("Enter selection set name") else { return }
                guard ed.doc.variable("SELSET:" + n) != nil else { throw CommandError.invalid("Selection set not found.") }
                ed.doc.variables.removeValue(forKey: "SELSET:" + n.uppercased())
            }
        }
    }
}

public enum SelectionTools {
    static func ids(_ s: String) -> [EntityID] { s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    /// End points of an open curve (nil for closed curves and non-curves).
    public static func endPoints(_ g: Geometry) -> (Vec2, Vec2)? {
        switch g {
        case .line(let l): return (l.a, l.b)
        case .arc(let a): return (a.startPoint, a.endPoint)
        case .polyline(let p) where !p.closed && p.vertices.count >= 2: return (p.vertices[0].p, p.vertices[p.vertices.count - 1].p)
        case .spline(let s) where !s.closed:
            let pts = GeometryOps.splinePoints(s)
            guard let a = pts.first, let b = pts.last else { return nil }
            return (a, b)
        case .ellipse(let e) where !e.isFull: return (e.point(at: e.start), e.point(at: e.end))
        default: return nil
        }
    }

    /// Entities connected end-to-end (within tolerance) with the start entity.
    public static func chain(from start: EntityID, doc: ArchiDocument, tolerance: Double) -> [EntityID] {
        guard let s = doc.entity(start) else { return [] }
        guard endPoints(s.geometry) != nil else { return [start] }
        var ends: [(EntityID, Vec2, Vec2)] = []
        for e in doc.entities { if let (a, b) = endPoints(e.geometry) { ends.append((e.id, a, b)) } }
        var result: Set<EntityID> = [start]
        var frontier: [Vec2] = []
        if let (a, b) = endPoints(s.geometry) { frontier = [a, b] }
        while let p = frontier.popLast() {
            for (id, a, b) in ends where !result.contains(id) {
                if a.distance(to: p) <= tolerance { result.insert(id); frontier.append(b) }
                else if b.distance(to: p) <= tolerance { result.insert(id); frontier.append(a) }
            }
        }
        return doc.entities.map(\.id).filter { result.contains($0) }
    }
}

extension Editor {
    /// Sets or removes a document variable (the surrounding command records undo).
    func transactionlessSetVariable(_ name: String, _ value: String?) {
        if let v = value { doc.setVariable(name, v) } else { doc.variables.removeValue(forKey: name.uppercased()) }
    }
}
