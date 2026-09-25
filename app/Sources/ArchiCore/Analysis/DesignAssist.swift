// Oanarina Archi Tool — GPL-3.0-or-later
// Design assistants (rule-based, run locally): automatic plan dimensioning (SCR-029), room naming and numbering from
// area, shape, fixtures and doors (SCR-030), and a model QA assistant that explains model-checker findings and applies
// safe fixes (SCR-033). Bulk edits ask for confirmation and are one undo step.
import Foundation

// MARK: - Auto-dimensioning (whole plan; AUTODIMWALLS dimensions single walls)

public enum PlanDimensions {
    /// Exterior dimension chains on the four sides of a level's plan: openings row (wall ends and opening edges), walls
    /// row (wall ends / corners) and the overall dimension. `offset` and `spacing` in drawing units.
    public static func dimensions(_ doc: ArchiDocument, level: Int, offset: Double, spacing: Double, style: String) -> [DimensionGeom] {
        let walls: [(BIMElement, WallGeom, [Vec2])] = doc.elements.compactMap { el in
            guard el.level == level, case .wall(let w) = el.geometry, w.length > geomEpsilon else { return nil }
            return (el, w, DXFWriter.wallOutline(w))
        }
        guard !walls.isEmpty else { return [] }
        var box = BBox2.empty
        for w in walls { for p in w.2 { box.add(p) } }
        let tol = max(walls.map(\.1.thickness).max() ?? 0, 1)
        var out: [DimensionGeom] = []
        // side: 0 bottom, 1 top, 2 left, 3 right.
        for side in 0..<4 {
            let horizontal = side < 2
            func along(_ p: Vec2) -> Double { horizontal ? p.x : p.y }
            func across(_ p: Vec2) -> Double { horizontal ? p.y : p.x }
            let outward: Double = side % 2 == 0 ? -1 : 1
            let edge = side == 0 ? box.min.y : side == 1 ? box.max.y : side == 2 ? box.min.x : box.max.x
            // Walls parallel to this side that are not hidden behind another wall further out.
            let cands = walls.filter { w in
                let d = w.1.direction
                return horizontal ? abs(d.y) < 0.2 : abs(d.x) < 0.2
            }
            var visible: [(BIMElement, WallGeom, [Vec2])] = []
            for w in cands {
                let a0 = w.2.map(along).min()!, a1 = w.2.map(along).max()!
                let pos = w.2.map(across).reduce(0, +) / Double(w.2.count)
                let hidden = cands.contains { o in
                    guard o.0.id != w.0.id else { return false }
                    let b0 = o.2.map(along).min()!, b1 = o.2.map(along).max()!
                    let opos = o.2.map(across).reduce(0, +) / Double(o.2.count)
                    let overlap = min(a1, b1) - max(a0, b0)
                    return overlap > (a1 - a0) * 0.5 && (opos - pos) * outward > tol / 2
                }
                if !hidden { visible.append(w) }
            }
            guard !visible.isEmpty else { continue }
            var wallPts: [Double] = [], openPts: [Double] = []
            for (el, w, outline) in visible {
                wallPts += [outline.map(along).min()!, outline.map(along).max()!]
                for o in doc.elements {
                    guard case .opening(let op) = o.geometry, op.hostWall == el.id else { continue }
                    let c = w.centerStart + w.direction * op.offset
                    for e in [c - w.direction * (op.width / 2), c + w.direction * (op.width / 2)] { openPts.append(along(e)) }
                }
            }
            func unique(_ v: [Double]) -> [Double] {
                var out: [Double] = []
                for x in v.sorted() where out.last.map({ abs($0 - x) > 1e-6 * max(1, abs(x)) + 1e-9 }) ?? true { out.append(x) }
                return out
            }
            // Corners: the facade runs to the outer face of the perpendicular walls (box extent) when a wall ends there.
            let lo = horizontal ? box.min.x : box.min.y, hi = horizontal ? box.max.x : box.max.y
            wallPts = wallPts.map { abs($0 - lo) <= tol ? lo : abs($0 - hi) <= tol ? hi : $0 }
            let rowWalls = unique(wallPts), rowOpen = unique(wallPts + openPts)
            func point(_ a: Double, _ c: Double) -> Vec2 { horizontal ? Vec2(a, c) : Vec2(c, a) }
            let rot = horizontal ? 0.0 : Double.pi / 2
            func chain(_ xs: [Double], row: Int) {
                guard xs.count >= 2 else { return }
                let line = edge + outward * (offset + Double(row) * spacing)
                for i in 0..<(xs.count - 1) where xs[i + 1] - xs[i] > 1e-6 {
                    out.append(DimensionGeom(kind: .linear, points: [point(xs[i], edge), point(xs[i + 1], edge), point((xs[i] + xs[i + 1]) / 2, line)], rotation: rot, style: style))
                }
            }
            var row = 0
            if rowOpen.count > rowWalls.count { chain(rowOpen, row: row); row += 1 }
            if rowWalls.count > 2 { chain(rowWalls, row: row); row += 1 }
            chain([rowWalls.first!, rowWalls.last!], row: row)
        }
        return out
    }

    static var command: CommandDef {
        CommandDef("AUTODIMPLAN", aliases: ["DIMPLAN", "PLANDIMS", "AUTODIMOVERALL"], category: "Annotate",
                   summary: "Dimensions the current level's plan automatically: exterior chains on all four sides (openings, walls, overall) on layer A-ANNO-DIMS; asks before adding them (one undo step).") { ed in
            let lv = ed.doc.currentLevel
            let ds = ed.doc.dimStyle
            let unit = ed.doc.units.mm
            let off = try await ed.getDistance("Distance of the first chain from the facade", defaultValue: 1000 / unit).value ?? 1000 / unit
            let sp = try await ed.getDistance("Spacing between chains", defaultValue: 600 / unit).value ?? 600 / unit
            let dims = dimensions(ed.doc, level: lv, offset: off, spacing: sp, style: ds.name)
            guard !dims.isEmpty else { throw CommandError.invalid("No walls on this level to dimension.") }
            guard try await ed.getYesNo("Add \(dims.count) dimensions?", defaultValue: true) else { ed.print("Nothing added."); return }
            if ed.doc.layer(named: "A-ANNO-DIMS") == nil { ed.doc.layers.append(Layer(name: "A-ANNO-DIMS", color: RGBA(0.3, 0.8, 1))) }
            var ids: [EntityID] = []
            for d in dims { var e = Entity(layer: "A-ANNO-DIMS", geometry: .dimension(d)); e.props["autoDim"] = "\(lv)"; ids.append(ed.doc.add(e)) }
            ed.selection = Set(ids)
            ed.print("Added \(dims.count) dimensions.")
        }
    }
}

// MARK: - Room naming

public enum RoomNaming {
    public struct Suggestion: Hashable { public var id: EntityID; public var old: String; public var name: String; public var number: String; public var reason: String }

    static let fixtureWords: [(String, [String])] = [
        ("wc", ["toilet", "wc", "lavatory"]), ("bath", ["bath", "shower", "tub"]), ("bed", ["bed"]), ("kitchen", ["stove", "cooker", "oven", "fridge", "refrigerator", "kitchen", "hob"]),
        ("sink", ["sink", "basin"]), ("sofa", ["sofa", "couch", "armchair", "tv"]), ("desk", ["desk", "office chair"]), ("dining", ["dining", "table"]),
        ("washer", ["washing machine", "washer", "dryer", "boiler"]),
    ]

    /// Suggested name for a room from what is inside it and its shape.
    public static func classify(_ el: BIMElement, doc: ArchiDocument) -> (name: String, reason: String) {
        guard case .space(let s) = el.geometry, s.boundary.count >= 3 else { return ("Room", "no outline") }
        let m = doc.units.mm / 1000
        let area = abs(GeometryOps.signedArea(s.boundary)) * m * m
        var tags = Set<String>()
        for c in doc.elements where c.level == el.level {
            guard case .component(let comp) = c.geometry, GeometryOps.pointInPolygon(comp.position, s.boundary) else { continue }
            let text = (c.name + " " + comp.category + " " + (comp.block ?? "")).lowercased()
            for (tag, words) in fixtureWords where words.contains(where: { text.contains($0) }) { tags.insert(tag) }
        }
        for e in doc.entities {
            guard case .insert(let ins) = e.geometry, GeometryOps.pointInPolygon(ins.position, s.boundary) else { continue }
            let text = ins.block.lowercased()
            for (tag, words) in fixtureWords where words.contains(where: { text.contains($0) }) { tags.insert(tag) }
        }
        if tags.contains("wc") { return tags.contains("bath") ? ("Bathroom", "toilet and bath/shower") : ("WC", "toilet") }
        if tags.contains("bath") { return ("Bathroom", "bath/shower") }
        if tags.contains("kitchen") { return (area >= 18 ? "Kitchen / Dining" : "Kitchen", "cooking fixtures") }
        if tags.contains("bed") { return ("Bedroom", "bed") }
        if tags.contains("sofa") { return ("Living room", "sofa") }
        if tags.contains("desk") { return ("Office", "desk") }
        if tags.contains("washer") { return ("Utility room", "washing machine / boiler") }
        if tags.contains("dining") { return ("Dining room", "dining table") }
        // Shape and openings.
        let b = BBox2(points: s.boundary)
        let short = min(b.width, b.height) * m, long = max(b.width, b.height) * m
        var windows = 0, doors = 0, exteriorDoor = false
        for o in doc.elements {
            guard case .opening(let op) = o.geometry, let host = doc.element(op.hostWall), host.level == el.level, case .wall(let w) = host.geometry else { continue }
            let c = w.centerStart + w.direction * op.offset
            let near = GeometryOps.distance(from: c, toPolyline: s.boundary + [s.boundary[0]]) <= w.thickness / 2 + 50 / doc.units.mm
            guard near else { continue }
            if op.kind == .window { windows += 1 } else { doors += 1; if Thermal.isExterior(host, doc: doc) { exteriorDoor = true } }
        }
        if area < 3 { return ("Storage", "small (\(fmt(area, 1)) m²)") }
        if short < 1.6 && long / max(short, 0.01) >= 3 { return ("Corridor", "narrow and long") }
        if exteriorDoor && area < 12 { return ("Entrance hall", "entrance door") }
        if windows == 0 { return (area < 6 ? "Storage" : "Room", "no windows") }
        if area >= 20 { return ("Living room", "largest daylit room (\(fmt(area, 1)) m²)") }
        if area >= 8 { return ("Bedroom", "daylit room \(fmt(area, 1)) m²") }
        return ("Study", "small daylit room")
    }

    /// Suggestions for the rooms of a level (all, or only unnamed / default-named ones): names made unique per level
    /// ("Bedroom 1", "Bedroom 2") and numbers level × 100 + n in reading order (top-left first).
    public static func suggest(_ doc: ArchiDocument, level: Int, onlyUnnamed: Bool) -> [Suggestion] {
        let rooms = doc.elements.filter { $0.level == level && $0.typeName == "space" && $0.props["areaScheme"] == nil }
        let placeholder: Set<String> = ["", "room", "space", "untitled"]
        let lvIndex = doc.levels.sorted { $0.elevation < $1.elevation }.firstIndex { $0.id == level } ?? 0
        let ordered = rooms.sorted { a, b in
            guard case .space(let sa) = a.geometry, case .space(let sb) = b.geometry else { return a.id < b.id }
            let ca = GeometryOps.centroid(sa.boundary), cb = GeometryOps.centroid(sb.boundary)
            return abs(ca.y - cb.y) > 1000 / doc.units.mm ? ca.y > cb.y : ca.x < cb.x
        }
        var raw: [(BIMElement, String, String, String)] = []
        for (i, r) in ordered.enumerated() {
            guard case .space(let s) = r.geometry else { continue }
            let n = String(format: "%d%02d", lvIndex, i + 1)
            if onlyUnnamed && !placeholder.contains(s.name.trimmingCharacters(in: .whitespaces).lowercased()) {
                raw.append((r, s.name, s.name, s.number.isEmpty ? n : s.number)); continue
            }
            let c = classify(r, doc: doc)
            raw.append((r, s.name, c.name, s.number.isEmpty || !onlyUnnamed ? n : s.number))
        }
        // Unique names for repeated generic kinds.
        var counts: [String: Int] = [:]
        for x in raw { counts[x.2, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var out: [Suggestion] = []
        for (r, old, name, num) in raw {
            var nm = name
            if counts[name]! > 1 && ["Bedroom", "Bathroom", "WC", "Storage", "Room", "Corridor", "Study"].contains(name) { seen[name, default: 0] += 1; nm = "\(name) \(seen[name]!)" }
            let reason = classify(r, doc: doc).reason
            out.append(Suggestion(id: r.id, old: old, name: nm, number: num, reason: reason))
        }
        return out
    }

    static var command: CommandDef {
        CommandDef("AUTONAMEROOMS", aliases: ["ROOMNAMING", "AUTOTAGROOMS", "NAMEROOMS"], category: "Architecture",
                   summary: "Names and numbers rooms of the current level from their fixtures (toilet, bath, bed, kitchen…), shape, windows and doors; Unnamed only or All; lists the suggestions and asks before applying (one undo step).") { ed in
            let scope = try await ed.getKeyword("Rooms to name [Unnamed/All]", ["Unnamed", "All"], defaultValue: "Unnamed") ?? "Unnamed"
            let sug = suggest(ed.doc, level: ed.doc.currentLevel, onlyUnnamed: scope == "Unnamed")
            let changes = sug.filter { s in
                guard case .space(let g) = ed.doc.element(s.id)?.geometry else { return false }
                return g.name != s.name || g.number != s.number
            }
            guard !changes.isEmpty else { ed.print("Nothing to rename."); return }
            for s in changes { ed.print("  #\(s.id): \(s.old.isEmpty ? "(unnamed)" : s.old) → \(s.number) \(s.name) — \(s.reason)") }
            guard try await ed.getYesNo("Apply \(changes.count) room name(s)?", defaultValue: true) else { ed.print("No rooms renamed."); return }
            for s in changes {
                guard let i = ed.doc.elementIndex(s.id), case .space(var g) = ed.doc.elements[i].geometry else { continue }
                g.name = s.name; g.number = s.number
                ed.doc.elements[i].geometry = .space(g)
                ed.doc.elements[i].name = s.name
            }
            ed.selection = Set(changes.map(\.id))
            ed.print("Renamed \(changes.count) room(s).")
        }
    }
}

// MARK: - Model QA assistant

public enum ModelQA {
    public struct Advice: Hashable {
        public var issue: ModelIssue
        public var explanation: String
        public var suggestion: String
        /// Whether `fix` can repair it automatically.
        public var fixable: Bool
    }

    static let texts: [String: (String, String)] = [
        "LEVEL-MISSING": ("The element refers to a level that was deleted, so it is not drawn in any plan and is skipped by schedules.", "Move it to the current level."),
        "WALL-LENGTH": ("A wall with the same start and end point has no geometry; it can break joins and exports.", "Delete the wall (and its openings)."),
        "WALL-HEIGHT": ("A wall without height does not appear in 3D, sections or quantities.", "Give it the level height."),
        "WALL-THICKNESS": ("A wall without thickness has no cut and no volume.", "Set the default wall thickness (200 mm)."),
        "WALL-DUPLICATE": ("Two identical walls double every quantity and cause z-fighting in 3D.", "Delete the second wall."),
        "WALL-OVERLAP": ("Walls overlapping along their length double quantities where they overlap.", "Trim or join the walls (JOIN / TRIM)."),
        "SLAB-EMPTY": ("A slab whose outline has no area has no volume and cannot be exported.", "Delete the slab."),
        "SLAB-THICKNESS": ("A slab without thickness has no volume.", "Set 200 mm."),
        "COLUMN-HEIGHT": ("A column without height does not appear in 3D or the analytical model.", "Give it the level height."),
        "OPENING-HOST": ("The door/window lost its host wall; it cannot be drawn or cut.", "Delete the opening."),
        "OPENING-WIDER": ("The opening is wider than its wall.", "Make it 100 mm narrower than the wall."),
        "OPENING-OUTSIDE": ("Part of the opening lies beyond the end of its wall.", "Slide it back inside the wall."),
        "OPENING-TALLER": ("The head of the opening is above the top of the wall.", "Reduce its height to fit the wall."),
        "OPENING-SIZE": ("An opening without width or height cuts nothing.", "Delete the opening."),
        "OPENING-OVERLAP": ("Two openings overlap in the same wall, so the cut is ambiguous.", "Move one of them (select and MOVE / change its offset)."),
        "ROOM-UNNAMED": ("Unnamed rooms make schedules and room tags meaningless.", "Name it from its fixtures and shape (AUTONAMEROOMS)."),
        "ROOM-UNNUMBERED": ("Rooms without numbers cannot be referenced in schedules and finishes.", "Number it."),
        "ROOM-NUMBER-DUPLICATE": ("Two rooms share a number on the same level.", "Renumber the rooms of the level."),
        "ROOM-HEIGHT": ("A room without height has no volume (heat loss, acoustics).", "Give it the level height."),
        "ROOM-AREA": ("The room outline has no area.", "Redraw the room (ROOM / SPACE)."),
        "ROOM-BOUNDARY": ("The room outline crosses itself, so its area is wrong.", "Redraw the outline."),
        "ROOM-OVERLAP": ("Overlapping rooms count the same floor area twice.", "Adjust the room boundaries."),
        "ENTITY-DUPLICATE": ("Identical objects on top of each other plot twice and double counts.", "Delete the duplicate (OVERKILL)."),
    ]
    static let fixableCodes: Set<String> = ["LEVEL-MISSING", "WALL-LENGTH", "WALL-HEIGHT", "WALL-THICKNESS", "WALL-DUPLICATE", "SLAB-EMPTY", "SLAB-THICKNESS",
                                            "COLUMN-HEIGHT", "OPENING-HOST", "OPENING-WIDER", "OPENING-OUTSIDE", "OPENING-TALLER", "OPENING-SIZE",
                                            "ROOM-UNNAMED", "ROOM-UNNUMBERED", "ROOM-NUMBER-DUPLICATE", "ROOM-HEIGHT", "ENTITY-DUPLICATE"]

    public static func advise(_ doc: ArchiDocument) -> [Advice] {
        ModelChecker.check(doc).map { i in
            let t = texts[i.code] ?? ("\(i.message).", "Inspect the objects (ZOOM to them).")
            return Advice(issue: i, explanation: t.0, suggestion: t.1, fixable: fixableCodes.contains(i.code))
        }
    }

    /// Applies the automatic fix of an issue to the document. Returns false when it cannot be fixed automatically.
    @discardableResult
    public static func fix(_ i: ModelIssue, in d: inout ArchiDocument) -> Bool {
        let u = d.units.mm
        func levelHeight(_ el: BIMElement) -> Double { d.level(el.level)?.height ?? 3000 / u }
        func edit(_ id: EntityID, _ body: (inout BIMElement) -> Void) { if let k = d.elementIndex(id) { body(&d.elements[k]) } }
        guard let first = i.ids.first else { return false }
        switch i.code {
        case "LEVEL-MISSING": let lv = d.currentLevel; for id in i.ids { edit(id) { $0.level = lv } }
        case "WALL-LENGTH", "SLAB-EMPTY", "OPENING-HOST", "OPENING-SIZE":
            let hosted = Set(d.elements.compactMap { el -> EntityID? in if case .opening(let o) = el.geometry, i.ids.contains(o.hostWall) { return el.id }; return nil })
            d.remove(ids: Set(i.ids).union(hosted))
        case "WALL-DUPLICATE": d.remove(ids: Set(i.ids.dropFirst()))
        case "ENTITY-DUPLICATE": d.remove(ids: Set(i.ids.dropFirst()))
        case "WALL-HEIGHT": for id in i.ids { edit(id) { el in if case .wall(var w) = el.geometry { w.height = levelHeight(el); el.geometry = .wall(w) } } }
        case "WALL-THICKNESS": for id in i.ids { edit(id) { el in if case .wall(var w) = el.geometry { w.thickness = 200 / u; el.geometry = .wall(w) } } }
        case "SLAB-THICKNESS": for id in i.ids { edit(id) { el in if case .slab(var s) = el.geometry { s.thickness = 200 / u; el.geometry = .slab(s) } } }
        case "COLUMN-HEIGHT": for id in i.ids { edit(id) { el in if case .column(var c) = el.geometry { c.height = levelHeight(el); el.geometry = .column(c) } } }
        case "ROOM-HEIGHT": for id in i.ids { edit(id) { el in if case .space(var s) = el.geometry { s.height = levelHeight(el) - 300 / u; el.geometry = .space(s) } } }
        case "OPENING-WIDER", "OPENING-OUTSIDE", "OPENING-TALLER":
            guard let el = d.element(first), case .opening(var o) = el.geometry, let host = d.element(o.hostWall), case .wall(let w) = host.geometry else { return false }
            if i.code == "OPENING-WIDER" { o.width = max(w.length - 100 / u, 10 / u) }
            if i.code == "OPENING-TALLER" { o.height = max(w.height - o.sill, 10 / u) }
            o.offset = min(max(o.offset, o.width / 2), w.length - o.width / 2)
            edit(first) { $0.geometry = .opening(o) }
        case "ROOM-UNNAMED", "ROOM-UNNUMBERED", "ROOM-NUMBER-DUPLICATE":
            guard let lv = d.element(first)?.level else { return false }
            let sug = RoomNaming.suggest(d, level: lv, onlyUnnamed: i.code != "ROOM-NUMBER-DUPLICATE")
            for s in sug where i.ids.contains(s.id) || i.code == "ROOM-NUMBER-DUPLICATE" {
                edit(s.id) { el in
                    guard case .space(var g) = el.geometry else { return }
                    if i.code == "ROOM-UNNAMED" { g.name = s.name; el.name = s.name }
                    if i.code != "ROOM-UNNAMED" || g.number.isEmpty { g.number = s.number }
                    el.geometry = .space(g)
                }
            }
        default: return false
        }
        return true
    }

    static var command: CommandDef {
        CommandDef("QAASSIST", aliases: ["MODELQA", "EXPLAINWARNINGS", "FIXMODEL"], category: "Analyze",
                   summary: "Model QA assistant: explains each model-checker finding (why it matters, what to do), Zoom to one, or Fix one / all fixable issues automatically after confirmation (one undo step).") { ed in
            let adv = advise(ed.doc)
            guard !adv.isEmpty else { ed.print("The model checker found no issues."); return }
            for (n, a) in adv.enumerated() {
                ed.print("\(n + 1). \(a.issue.description)")
                ed.print("   Why: \(a.explanation)")
                ed.print("   Fix: \(a.suggestion)\(a.fixable ? " (automatic)" : "")")
            }
            let k = try await ed.getKeyword("Enter an option [Fix/FixAll/Zoom/Done]", ["Fix", "FixAll", "Zoom", "Done"], defaultValue: "Done") ?? "Done"
            switch k {
            case "Zoom", "Fix":
                let n = try await ed.getInteger("Issue number <1>", defaultValue: 1) ?? 1
                guard n >= 1, n <= adv.count else { throw CommandError.invalid("No issue \(n).") }
                let a = adv[n - 1]
                if k == "Zoom" { ReviewCommands.zoomTo(ed, a.issue.bounds, ids: a.issue.ids); return }
                guard a.fixable else { throw CommandError.invalid("Issue \(n) needs a manual fix: \(a.suggestion)") }
                var d = ed.doc
                fix(a.issue, in: &d)
                ed.doc = d
                ed.print("Fixed: \(a.issue.code).")
            case "FixAll":
                let fixable = adv.filter(\.fixable)
                guard !fixable.isEmpty else { ed.print("No issue can be fixed automatically."); return }
                guard try await ed.getYesNo("Apply \(fixable.count) automatic fix(es)?", defaultValue: true) else { return }
                var d = ed.doc
                var done = 0
                // Re-check after each fix: ids may change (deleted duplicates).
                for _ in 0..<fixable.count {
                    guard let next = advise(d).first(where: \.fixable) else { break }
                    if fix(next.issue, in: &d) { done += 1 } else { break }
                }
                ed.doc = d
                ed.print("Applied \(done) fix(es); \(advise(d).count) issue(s) remain.")
            default: break
            }
        }
    }
}
