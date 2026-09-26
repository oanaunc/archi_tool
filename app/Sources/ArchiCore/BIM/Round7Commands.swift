// Oanarina Archi Tool — GPL-3.0-or-later
// Round 7 building and documentation commands: WALLRECT / WALLPOLYGON (BIM-012), STOREFRONT (BIM-032), STACKEDWALL
// (BIM-022), PARTS (BIM-127), ASSEMBLY (BIM-124/126), STORY (BIM-003), STRUCTCOLUMN (BIM-077), STRUCTURAL (BIM-086),
// STAIRTYPE / RAILTYPEDEF (PAR-018), EXPRESSION (PAR-030), PARAMCELL (PAR-029), REPORTPARAM (PAR-025), FAMILYLOCK
// (PAR-026), TRANSFERSTANDARDS (PAR-032), DETAILCOMPONENT / REPEATDETAIL / INSULATION (DOC-037/038/039), MATERIALTAG
// (DOC-032) and SCHEDULECELLS (DOC-052).
import Foundation

enum Round7Commands {
    static var all: [CommandDef] {
        [wallRect, wallPolygon, storefront, stackedWall, parts, assembly, story, structColumn, structural, stairType, railTypeDef,
         expression, paramCell, reportParam, familyLock, transferStandards, detailComponent, repeatDetail, insulation, materialTag, scheduleCells]
    }

    @MainActor static func wallTemplate(_ ed: Editor) -> (WallGeom, String?) {
        let wt = ed.doc.variable("WALLTYPE").flatMap { n in ed.doc.wallTypes.first { $0.name == n } }
        var w = WallGeom(start: .zero, end: Vec2(1, 0), thickness: wt?.thickness ?? ed.settings.wallThickness, height: ed.settings.wallHeight,
                         baseOffset: ed.variableDouble("WALLBASEOFFSET", 0), justification: ed.settings.wallJustification)
        w.wallType = wt?.name
        return (w, ArchitectureCommands.wallMaterial(ed.doc, wt?.name))
    }

    // MARK: BIM-012

    static var wallRect: CommandDef {
        CommandDef("WALLRECT", aliases: ["WALLRECTANGLE", "RECTWALL", "WALLBOX"], category: "Architecture",
                   summary: "Draws four joined walls around a rectangle (two corners; Justify sets whether the rectangle is the inside, centre or outside face).") { ed in
            var (tpl, mat) = wallTemplate(ed)
            let jk = try await ed.getKeyword("Rectangle is the wall [Inside/Center/Outside] face", ["Inside", "Center", "Outside"], defaultValue: ed.doc.variable("WALLRECTJUST") ?? "Center") ?? "Center"
            ed.doc.setVariable("WALLRECTJUST", jk)
            // Walls run counter-clockwise, so the left face is inside.
            tpl.justification = jk == "Inside" ? .left : (jk == "Outside" ? .right : .center)
            let a = try await ed.requirePoint("Specify first corner")
            let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
            let box = BBox2(points: [a, b])
            guard box.width > tpl.thickness, box.height > tpl.thickness else { throw CommandError.invalid("The rectangle is too small for the wall thickness.") }
            let t = tpl, m = mat
            let ids = WallLoops.create(box.corners, template: t, material: m, doc: &ed.doc)
            ed.print("\(ids.count) walls created.")
        }
    }

    static var wallPolygon: CommandDef {
        CommandDef("WALLPOLYGON", aliases: ["POLYWALL", "WALLPOLY", "WALLLOOP"], category: "Architecture",
                   summary: "Draws a closed loop of joined walls: a regular polygon (centre, sides, radius), points, or a picked closed polyline.") { ed in
            let (tpl, mat) = wallTemplate(ed)
            let k = try await ed.getKeyword("Loop from [Regular polygon/Points/Object]", ["Regular", "Points", "Object"], defaultValue: "Regular") ?? "Regular"
            var loop: [Vec2] = []
            switch k {
            case "Points":
                let a = try await ed.requirePoint("Specify first point")
                loop = try await ArchitectureCommands.polygonInput(ed, first: a) ?? []
            case "Object":
                loop = try await ArchitectureCommands.selectBoundary(ed) ?? []
            default:
                let n = try await ed.getInteger("Number of sides", defaultValue: Int(ed.variableDouble("WALLPOLYSIDES", 6))) ?? 6
                guard n >= 3, n <= 64 else { throw CommandError.invalid("Sides must be 3–64.") }
                ed.doc.setVariable("WALLPOLYSIDES", "\(n)")
                let c = try await ed.requirePoint("Specify centre")
                let ins = (try await ed.getKeyword("[Inscribed/Circumscribed]", ["Inscribed", "Circumscribed"], defaultValue: "Inscribed") ?? "Inscribed") == "Inscribed"
                let rp = try await ed.getPoint("Specify radius (point sets the rotation)", base: c) { p in
                    [.polyline(PolylineGeom(points: WallLoops.regularPolygon(center: c, sides: n, radius: c.distance(to: p), inscribed: ins, rotation: (p - c).angle), closed: true))] }
                guard let p = rp.point, c.distance(to: p) > 1e-6 else { return }
                loop = WallLoops.regularPolygon(center: c, sides: n, radius: c.distance(to: p), inscribed: ins, rotation: (p - c).angle - (ins ? 0 : .pi / Double(n)))
            }
            guard loop.count >= 3 else { throw CommandError.invalid("A wall loop needs at least 3 points.") }
            let ids = WallLoops.create(loop, template: tpl, material: mat, doc: &ed.doc)
            ed.print("\(ids.count) joined walls created.")
        }
    }

    // MARK: BIM-032

    static var storefront: CommandDef {
        CommandDef("STOREFRONT", aliases: ["SHOPFRONT", "GLAZEDPARTITION", "PARTITIONGLASS"], category: "Architecture",
                   summary: "Storefront curtain walls (bays, transom, capped mullions, entrance door) or glazed Partitions (slim mullions, full-height door).") { ed in
            let kind = try await ed.getKeyword("Preset", ["Storefront", "Partition"], defaultValue: "Storefront") ?? "Storefront"
            let part = kind == "Partition"
            let a = try await ed.requirePoint("Specify start point")
            let b = try await ed.requirePoint("Specify end point", base: a) { c in [.line(LineGeom(a, c))] }
            let h = try await ed.getPositive("Height", defaultValue: part ? ed.currentLevelHeight - 300 : ed.variableDouble("STOREFRONTH", 3000))
            let bay = try await ed.getPositive("Bay width", defaultValue: part ? 1000 : 1500)
            let tr = part ? nil : Optional(try await ed.getPositive("Transom height (0 = none)", defaultValue: 2250, allowZero: true))
            let d = try await ed.getKeyword("Door [Single/Double/None]", ["Single", "Double", "None"], defaultValue: "Single") ?? "Single"
            var bays: [Int] = []
            if d != "None" { bays = [(try await ed.getInteger("Door bay (1 = first, 0 = middle)", defaultValue: 0) ?? 0) - 1] }
            guard let g = Storefronts.make(start: a, end: b, height: h, bay: bay, transom: (tr ?? 0) > 0 ? tr : nil, doorBays: bays.map { $0 < 0 ? -1 : $0 }, doubleDoor: d == "Double", partition: part) else {
                throw CommandError.invalid("The storefront needs a length.") }
            let id = ed.doc.addElement(.curtainWall(g), material: "Glass", name: kind)
            if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["curtainPreset"] = kind.lowercased() }
            ed.print("\(kind): \((g.uLines?.count ?? 0) + 1) bays\(d == "None" ? "" : ", \(d.lowercased()) door").")
        }
    }

    // MARK: BIM-022

    static var stackedWall: CommandDef {
        CommandDef("STACKEDWALL", aliases: ["STACKWALL", "WALLSTACK"], category: "Architecture",
                   summary: "Makes walls stacked walls: segments of wall types bottom-up (\"Type:height; Type:*\"), regenerated when the base wall changes; Off removes the stack.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select base walls") { if case .wall = $0 { return true }; return false }
            guard !ids.isEmpty else { return }
            let names = ed.doc.wallTypes.map(\.name)
            ed.print("Wall types: \(names.joined(separator: ", "))")
            guard let spec = try await ed.getString("Stack bottom-up \"Type:height; Type:*\" (Off = remove)", defaultValue: ed.doc.variable("WALLSTACK")) else { return }
            var n = 0
            if spec.lowercased() == "off" {
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["stack"] = nil; ed.doc.elements[i].props["stackHeight"] = nil; n += 1 } }
                StackedWalls.updateAll(&ed.doc); ed.print("\(n) stack(s) removed."); return
            }
            let segs = StackedWalls.parse(spec)
            guard segs.count >= 2 else { throw CommandError.invalid("A stack needs at least two segments.") }
            for s in segs where !names.contains(where: { $0.caseInsensitiveCompare(s.type) == .orderedSame }) { throw CommandError.invalid("Unknown wall type \(s.type).") }
            ed.doc.setVariable("WALLSTACK", spec)
            for id in ids {
                guard let i = ed.doc.elementIndex(id), ed.doc.elements[i].props["stackOf"] == nil, case .wall(let w) = ed.doc.elements[i].geometry else { continue }
                ed.doc.elements[i].props["stack"] = spec
                ed.doc.elements[i].props["stackHeight"] = fmt(BIMConstraints.wallHeight(ed.doc.elements[i], doc: ed.doc) + 0 * w.height, 6)
                n += 1
            }
            StackedWalls.updateAll(&ed.doc)
            ed.print("\(n) stacked wall(s): \(segs.map(\.type).joined(separator: " / ")).")
        }
    }

    // MARK: BIM-127

    static var parts: CommandDef {
        CommandDef("PARTS", aliases: ["CREATEPARTS", "DIVIDEPARTS"], category: "Architecture",
                   summary: "Divides compound walls into parts (one per layer, cut by the host's openings), Merge restores the wall, Material overrides a part, Show Parts/Original.") { ed in
            let k = try await ed.getKeyword("Parts option", ["Create", "Merge", "Material", "Show"], defaultValue: "Create") ?? "Create"
            switch k {
            case "Merge":
                let ids = try await ArchitectureCommands.elements(ed, "Select divided walls or parts") { if case .wall = $0 { return true }; return false }
                var hosts = Set<EntityID>()
                for id in ids { if let el = ed.doc.element(id) { hosts.insert(el.props["partOf"].flatMap(Int.init) ?? id) } }
                let n = hosts.reduce(0) { $0 + WallParts.merge($1, doc: &ed.doc) }
                ed.print("\(n) part(s) merged back into \(hosts.count) wall(s).")
            case "Material":
                let ids = try await ArchitectureCommands.elements(ed, "Select parts") { if case .wall = $0 { return true }; return false }.filter { ed.doc.element($0)?.props["partOf"] != nil }
                guard !ids.isEmpty, let m = try await ed.getWord("Material (ByHost = the layer's)", defaultValue: "ByHost") else { return }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["partMaterial"] = m.lowercased() == "byhost" ? nil : (ed.doc.material(m)?.name ?? m) } }
                WallParts.updateAll(&ed.doc)
            case "Show":
                let v = try await ed.getKeyword("Show [Parts/Original]", ["Parts", "Original"], defaultValue: "Parts") ?? "Parts"
                if v == "Original" { ed.doc.setVariable("PARTSVISIBILITY", "original") } else { ed.doc.variables["PARTSVISIBILITY"] = nil }
            default:
                let ids = try await ArchitectureCommands.elements(ed, "Select compound walls") { if case .wall = $0 { return true }; return false }
                var made = 0, skipped = 0
                for id in ids { let p = WallParts.divide(id, doc: &ed.doc); if p.isEmpty { skipped += 1 } else { made += p.count } }
                ed.print("\(made) part(s) created\(skipped > 0 ? "; \(skipped) wall(s) skipped (single layer)" : "").")
            }
        }
    }

    // MARK: BIM-124 / BIM-126

    static var assembly: CommandDef {
        CommandDef("ASSEMBLY", aliases: ["ASSEMBLIES", "CREATEASSEMBLY", "AGGREGATE"], category: "Architecture",
                   summary: "Assemblies (element aggregation): Create from selected elements, Add, Remove, Disassemble, Views (isolated plan and 3D views), List.") { ed in
            let k = try await ed.getKeyword("Assembly option", ["List", "Create", "Add", "Remove", "Disassemble", "Views"], defaultValue: "List") ?? "List"
            switch k {
            case "Create", "Add":
                let ids = try await ArchitectureCommands.elements(ed, "Select elements") { _ in true }
                guard !ids.isEmpty else { return }
                let def = k == "Add" ? Assemblies.names(ed.doc).first : "Assembly \(Assemblies.names(ed.doc).count + 1)"
                guard let n = try await ed.getWord("Assembly name", defaultValue: def), !n.isEmpty else { return }
                if k == "Create" && !Assemblies.members(n, doc: ed.doc).isEmpty { throw CommandError.invalid("Assembly \(n) exists (use Add).") }
                var type: String? = nil
                if k == "Create" { type = try await ed.getWord("Assembly type (naming category)", defaultValue: "Generic") }
                let c = Assemblies.create(n, ids: ids, type: type, doc: &ed.doc)
                ed.print("\(c) element(s) in assembly \(n).")
            case "Remove":
                let ids = try await ArchitectureCommands.elements(ed, "Select elements to remove from their assembly") { _ in true }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["assembly"] = nil } }
                ed.print("\(ids.count) element(s) removed.")
            case "Disassemble":
                guard let n = try await ed.getWord("Assembly name", defaultValue: Assemblies.names(ed.doc).first) else { return }
                ed.print("\(Assemblies.disassemble(n, doc: &ed.doc)) element(s) released.")
            case "Views":
                guard let n = try await ed.getWord("Assembly name", defaultValue: Assemblies.names(ed.doc).first) else { return }
                let vs = Assemblies.createViews(n, doc: &ed.doc)
                guard !vs.isEmpty else { throw CommandError.invalid("Assembly \(n) has no members.") }
                ProjectViews.updateAll(&ed.doc)
                ed.print("Assembly views: \(vs.joined(separator: ", ")) (PROJECTVIEW Open shows them).")
            default:
                let ns = Assemblies.names(ed.doc)
                if ns.isEmpty { ed.print("No assemblies.") }
                for n in ns {
                    let ms = Assemblies.members(n, doc: ed.doc)
                    ed.print("  \(n) [\(ed.doc.variable("ASSEMBLYTYPE." + n) ?? "Generic")]: \(ms.count) member(s) — \(Set(ms.map { VisibilityGraphics.category($0) }).sorted().joined(separator: ", "))")
                }
            }
        }
    }

    // MARK: BIM-003

    static var story: CommandDef {
        CommandDef("STORY", aliases: ["STOREY", "STORYSETTINGS", "STOREYSETTINGS"], category: "Architecture",
                   summary: "Storey settings: Height (moves the storeys above), Insert above / below, Delete, Computation height (walls that bound rooms), Elevation display (project / survey / relative), List.") { ed in
            let k = try await ed.getKeyword("Storey option", ["List", "Height", "Insert", "Delete", "Computation", "Elevation"], defaultValue: "List") ?? "List"
            let cur = ed.doc.currentLevel
            switch k {
            case "Height":
                let h = try await ed.getPositive("Storey height", defaultValue: ed.currentLevelHeight)
                let prop = try await ed.getYesNo("Move the storeys above?", defaultValue: true)
                StoreySettings.setHeight(cur, h, propagate: prop, doc: &ed.doc)
                ed.print("Storey height \(fmt(h))\(prop ? "; storeys above moved" : "").")
            case "Insert":
                let above = (try await ed.getKeyword("Insert [Above/Below]", ["Above", "Below"], defaultValue: "Above") ?? "Above") == "Above"
                let h = try await ed.getPositive("New storey height", defaultValue: ed.currentLevelHeight)
                let n = try await ed.getWord("Name", defaultValue: "Level \((ed.doc.levels.map(\.id).max() ?? 0) + 1)")
                guard let id = StoreySettings.insert(relativeTo: cur, above: above, height: h, name: n, doc: &ed.doc) else { throw CommandError.invalid("Cannot insert a storey here.") }
                ed.print("Storey \(ed.doc.level(id)?.name ?? "") inserted at \(fmt(ed.doc.level(id)?.elevation ?? 0)).")
            case "Delete":
                guard ed.doc.levels.count > 1 else { throw CommandError.invalid("The last storey cannot be deleted.") }
                let n = ed.doc.elements.filter { $0.level == cur }.count
                guard try await ed.getYesNo("Delete \(ed.doc.level(cur)?.name ?? "") and its \(n) element(s)?", defaultValue: false) else { return }
                StoreySettings.delete(cur, doc: &ed.doc)
            case "Computation":
                let v = try await ed.getDistance("Computation height above the level (negative = off)", defaultValue: ed.doc.level(cur)?.computationHeight ?? BIMConstraints.cutHeight(ed.doc)).value ?? -1
                if let i = ed.doc.levels.firstIndex(where: { $0.id == cur }) { ed.doc.levels[i].computationHeight = v < 0 ? nil : v }
            case "Elevation":
                let m = try await ed.getKeyword("Elevation display [Project/Survey/Relative]", ["Project", "Survey", "Relative"], defaultValue: "Project") ?? "Project"
                ed.doc.setVariable("LEVELELEVBASE", m.lowercased())
                if m == "Relative", let r = try await ed.getWord("Reference level", defaultValue: ed.doc.levels.min { $0.elevation < $1.elevation }?.name) { ed.doc.setVariable("LEVELELEVREF", r) }
            default:
                for l in ed.doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
                    ed.print("  \(l.id == cur ? "*" : " ") \(l.name): elevation \(fmt(l.elevation)) (shown \(fmt(StoreySettings.displayElevation(l, doc: ed.doc)))), height \(fmt(l.height))\(l.computationHeight.map { ", computation \(fmt($0))" } ?? "")")
                }
            }
        }
    }

    // MARK: BIM-077 / BIM-086

    static var structColumn: CommandDef {
        CommandDef("STRUCTCOLUMN", aliases: ["STRUCTURALCOLUMN", "SCOLUMN", "STEELCOLUMN"], category: "Structure",
                   summary: "Places structural columns with a profile (HEA/IPE/RHS/CHS… or RECT / ROUND concrete), from the level to the next level (or a height), at points or at every grid intersection.") { ed in
            let spec = try await ed.getString("Profile (e.g. HEA200, SHS 150x8, RECT 300x300, ROUND 400)", defaultValue: ed.doc.variable("STRUCTCOLPROFILE") ?? "HEA200") ?? "HEA200"
            guard let sec = StructuralProfiles.section(spec) else { throw CommandError.invalid("Unknown profile \(spec).") }
            ed.doc.setVariable("STRUCTCOLPROFILE", spec)
            let concrete = sec.shape == .rect || sec.shape == .round
            let u = 1 / ed.doc.units.mm
            let next = ArchitectureCommands.topLevelID(ed.doc, spec: "next", from: ed.doc.currentLevel)
            let defH = next.flatMap { ed.doc.level($0) }.map { $0.elevation - (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) } ?? ed.currentLevelHeight
            let h = try await ed.getPositive("Height (to the next level)", defaultValue: defH)
            let mat = try await ed.getWord("Material", defaultValue: concrete ? "Concrete" : "Steel") ?? "Steel"
            @MainActor func place(_ p: Vec2, grids: (Int, Int)?) {
                let g = ColumnGeom(position: p, width: sec.b * u, depth: sec.h * u, height: h, round: sec.shape == .round || sec.shape == .chs, profile: concrete ? nil : sec.name)
                let id = ed.doc.addElement(.column(g), layer: "S-COLS", material: ed.doc.material(mat)?.name ?? mat, name: "Column \(sec.name)")
                guard let i = ed.doc.elementIndex(id) else { return }
                ed.doc.elements[i].props["loadBearing"] = "1"; ed.doc.elements[i].props["structural"] = "1"
                if let t = next, abs(defH - h) < 1e-6 { ed.doc.elements[i].props["topLevel"] = "\(t)" }
                if let gp = grids { ed.doc.elements[i].props[GridHosting.prop] = "\(gp.0),\(gp.1)" }
            }
            var n = 0
            while true {
                let a = try await ed.getPoint("Specify column location", keywords: ["Grids"])
                switch a {
                case .point(let p):
                    let pair = GridHosting.hostPair(at: p, doc: ed.doc, tolerance: u)
                    place(p, grids: pair.map { ($0.a, $0.b) }); n += 1
                case .keyword:
                    let tol = u
                    for x in GridHosting.allIntersections(ed.doc, among: Set(ed.doc.elements.filter { if case .gridLine = $0.geometry { return true }; return false }.map(\.id)), tolerance: tol) {
                        let taken = ed.doc.elements.contains { el in if el.level == ed.doc.currentLevel, case .column(let c) = el.geometry { return c.position.distance(to: x.point) <= tol }; return false }
                        if !taken { place(x.point, grids: (x.a, x.b)); n += 1 }
                    }
                default:
                    ed.print("\(n) structural column(s) \(sec.name) placed."); return
                }
            }
        }
    }

    static var structural: CommandDef {
        CommandDef("STRUCTURAL", aliases: ["STRUCTURALUSAGE", "LOADBEARING"], category: "Structure",
                   summary: "Structural usage of walls, slabs, columns and beams: Bearing, Shear, Combined or Non-bearing (drives the analytical model and schedules).") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select walls, slabs, columns or beams") { g in
                switch g { case .wall, .slab, .column, .beam, .roof: return true; default: return false } }
            guard !ids.isEmpty else { return }
            let k = try await ed.getKeyword("Structural usage", ["Bearing", "Shear", "Combined", "Nonbearing"], defaultValue: "Bearing") ?? "Bearing"
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                ed.doc.elements[i].props["structuralUsage"] = k.lowercased()
                ed.doc.elements[i].props["structural"] = k == "Nonbearing" ? "0" : "1"
                ed.doc.elements[i].props["loadBearing"] = k == "Nonbearing" || k == "Shear" ? "0" : "1"
            }
            ed.print("\(ids.count) element(s) set to \(k.lowercased()).")
        }
    }

    // MARK: PAR-018

    static var stairType: CommandDef {
        CommandDef("STAIRTYPE", aliases: ["STAIRTYPES"], category: "Architecture",
                   summary: "Stair types (max riser, min going, width, landing, material, railing type): New / Edit (every stair of the type follows), Assign to stairs, List, Delete.") { ed in
            let k = try await ed.getKeyword("Stair type option", ["List", "New", "Edit", "Assign", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "New", "Edit":
                let def = k == "Edit" ? ed.doc.stairTypes.first?.name : "Stair Type \(ed.doc.stairTypes.count + 1)"
                guard let n = try await ed.getWord("Type name", defaultValue: def), !n.isEmpty else { return }
                var t = ed.doc.stairType(named: n) ?? StairType(name: n)
                if k == "New" && ed.doc.stairType(named: n) != nil { throw CommandError.invalid("Type \(n) exists (use Edit).") }
                if k == "Edit" && ed.doc.stairType(named: n) == nil { throw CommandError.invalid("Type \(n) not found.") }
                t.maxRiser = try await ed.getPositive("Maximum riser", defaultValue: t.maxRiser)
                t.minTread = try await ed.getPositive("Minimum going (tread)", defaultValue: t.minTread)
                t.width = try await ed.getPositive("Width", defaultValue: t.width)
                let l = try await ed.getDistance("Landing depth (0 = stair width)", defaultValue: t.landingDepth ?? 0).value ?? 0
                t.landingDepth = l > 0 ? l : nil
                let m = try await ed.getWord("Material", defaultValue: t.material ?? "Concrete")
                t.material = m.flatMap { ed.doc.material($0)?.name ?? $0 }
                let r = try await ed.getWord("Railing type (None)", defaultValue: t.railingType ?? "None")
                t.railingType = (r ?? "None").lowercased() == "none" ? nil : r
                if let i = ed.doc.stairTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { ed.doc.stairTypes[i] = t } else { ed.doc.stairTypes.append(t) }
                SystemTypes.updateAll(&ed.doc)
                let users = ed.doc.elements.filter { $0.props["stairType"]?.caseInsensitiveCompare(n) == .orderedSame }.count
                ed.print("Stair type \(n) saved\(users > 0 ? "; \(users) stair(s) updated" : "").")
            case "Assign":
                let ids = try await ArchitectureCommands.elements(ed, "Select stairs") { if case .stair = $0 { return true }; return false }
                guard !ids.isEmpty, let n = try await ed.getWord("Type name", defaultValue: ed.doc.stairTypes.first?.name), let t = ed.doc.stairType(named: n) else { throw CommandError.invalid("Stair type not found.") }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["stairType"] = t.name } }
                SystemTypes.updateAll(&ed.doc)
                for id in ids { if let el = ed.doc.element(id), case .stair(let g) = el.geometry { ed.print("  #\(id): \(g.riserCount) risers of \(fmt(g.riserHeight)), going \(fmt(g.treadDepth))") } }
            case "Delete":
                guard let n = try await ed.getWord("Type name") else { return }
                ed.doc.stairTypes.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                for i in ed.doc.elements.indices where ed.doc.elements[i].props["stairType"]?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.elements[i].props["stairType"] = nil }
            default:
                for t in ed.doc.stairTypes { ed.print("  \(t.name): riser ≤ \(fmt(t.maxRiser)), going ≥ \(fmt(t.minTread)), width \(fmt(t.width))\(t.railingType.map { ", railing \($0)" } ?? "")") }
            }
        }
    }

    static var railTypeDef: CommandDef {
        CommandDef("RAILTYPEDEF", aliases: ["RAILINGTYPES", "RAILTYPEBUILDER"], category: "Architecture",
                   summary: "Named railing types (height, handrail profile and size, infill, balusters, posts, extensions): New / Edit (railings of the type follow), Assign, List, Delete.") { ed in
            let k = try await ed.getKeyword("Railing type option", ["List", "New", "Edit", "Assign", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "New", "Edit":
                guard let n = try await ed.getWord("Type name", defaultValue: k == "Edit" ? ed.doc.railingTypes.first?.name : "Railing Type \(ed.doc.railingTypes.count + 1)"), !n.isEmpty else { return }
                if k == "New" && ed.doc.railingType(named: n) != nil { throw CommandError.invalid("Type \(n) exists (use Edit).") }
                var t = ed.doc.railingType(named: n) ?? RailingTypeDef(name: n)
                if k == "Edit" && ed.doc.railingType(named: n) == nil { throw CommandError.invalid("Type \(n) not found.") }
                t.height = try await ed.getPositive("Height", defaultValue: t.height)
                t.railProfile = try await ed.getKeyword("Handrail profile", ["round", "rect", "oval", "mushroom", "handrail-rect"], defaultValue: t.railProfile) ?? t.railProfile
                t.railSize = try await ed.getPositive("Handrail size", defaultValue: t.railSize)
                t.infill = try await ed.getKeyword("Infill", ["balusters", "glass", "cables", "bars", "none"], defaultValue: t.infill) ?? t.infill
                t.balusterSpacing = try await ed.getPositive("Baluster spacing", defaultValue: t.balusterSpacing, allowZero: true)
                t.balusterSize = try await ed.getPositive("Baluster size", defaultValue: t.balusterSize, allowZero: true)
                t.postSpacing = try await ed.getPositive("Post spacing", defaultValue: t.postSpacing, allowZero: true)
                t.bottomRail = try await ed.getYesNo("Bottom rail?", defaultValue: t.bottomRail)
                t.extensionLength = try await ed.getPositive("Handrail extension", defaultValue: t.extensionLength, allowZero: true)
                if let i = ed.doc.railingTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) { ed.doc.railingTypes[i] = t } else { ed.doc.railingTypes.append(t) }
                SystemTypes.updateAll(&ed.doc)
                ed.print("Railing type \(n) saved.")
            case "Assign":
                let ids = try await ArchitectureCommands.elements(ed, "Select railings") { if case .railing = $0 { return true }; return false }
                guard !ids.isEmpty, let n = try await ed.getWord("Type name", defaultValue: ed.doc.railingTypes.first?.name), let t = ed.doc.railingType(named: n) else { throw CommandError.invalid("Railing type not found.") }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["railingType"] = t.name } }
                SystemTypes.updateAll(&ed.doc)
            case "Delete":
                guard let n = try await ed.getWord("Type name") else { return }
                ed.doc.railingTypes.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                for i in ed.doc.elements.indices where ed.doc.elements[i].props["railingType"]?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.elements[i].props["railingType"] = nil }
            default:
                if ed.doc.railingTypes.isEmpty { ed.print("No railing types.") }
                for t in ed.doc.railingTypes { ed.print("  \(t.name): h \(fmt(t.height)), \(t.railProfile) \(fmt(t.railSize)), \(t.infill) @ \(fmt(t.balusterSpacing))") }
            }
        }
    }

    // MARK: PAR-030 / PAR-029 / PAR-025 / PAR-026

    static var expression: CommandDef {
        CommandDef("EXPRESSION", aliases: ["EXPR", "PROPEXPR", "SETEXPR"], category: "Manage",
                   summary: "Binds a property of selected objects to an expression over their own properties, other objects (id12.height, Name.length) and global parameters; Clear removes it; List shows them.") { ed in
            let k = try await ed.getKeyword("Expression option", ["Set", "Clear", "List"], defaultValue: "Set") ?? "Set"
            if k == "List" {
                var n = 0
                for el in ed.doc.elements { for (p, e) in el.props where p.hasPrefix(Expressions.prefix) { ed.print("  #\(el.id).\(p.dropFirst(Expressions.prefix.count)) = \(e)\(el.props["exprError"].map { "  [\($0)]" } ?? "")"); n += 1 } }
                for en in ed.doc.entities { for (p, e) in en.props where p.hasPrefix(Expressions.prefix) { ed.print("  #\(en.id).\(p.dropFirst(Expressions.prefix.count)) = \(e)"); n += 1 } }
                if n == 0 { ed.print("No expressions.") }
                return
            }
            let ids = try await ed.getSelection("Select objects")
            guard !ids.isEmpty, let prop = try await ed.getWord("Property (e.g. height, thickness, width)"), !prop.isEmpty else { return }
            if k == "Clear" {
                for id in ids {
                    if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[Expressions.prefix + prop] = nil; ed.doc.elements[i].props["exprError"] = nil }
                    if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[Expressions.prefix + prop] = nil; ed.doc.entities[i].props["exprError"] = nil }
                }
                return
            }
            guard let expr = try await ed.getString("Expression"), !expr.isEmpty else { return }
            let globals = GlobalParameters.values(ed.doc)
            for id in ids {
                guard Expressions.evaluate(expr, for: id, doc: ed.doc, globals: globals) != nil else { throw CommandError.invalid("Cannot evaluate \(expr) for #\(id).") }
                if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[Expressions.prefix + prop] = expr }
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[Expressions.prefix + prop] = expr }
            }
            Expressions.updateAll(&ed.doc)
            ed.print("\(ids.count) object(s): \(prop) = \(expr).")
        }
    }

    static var paramCell: CommandDef {
        CommandDef("PARAMCELL", aliases: ["PARAMLINK", "SPREADSHEETPARAM", "BINDCELL"], category: "Manage",
                   summary: "Drives a global parameter from a spreadsheet cell (a table in the drawing, e.g. Params!B3 or #12!B3); None removes the link.") { ed in
            guard let n = try await ed.getWord("Global parameter", defaultValue: ed.doc.globalParameters.first?.name) else { return }
            guard let gi = ed.doc.globalParameters.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Global parameter not found (GLOBALPARAM creates one).") }
            guard let b = try await ed.getWord("Cell (Table!B3, or None)", defaultValue: ed.doc.globalParameters[gi].cell) else { return }
            if b.lowercased() == "none" { ed.doc.globalParameters[gi].cell = nil; ed.print("Link removed."); return }
            guard let v = SpreadsheetParameters.value(b, doc: ed.doc) else { throw CommandError.invalid("Cell \(b) not found (tables are named by props name, or #id).") }
            ed.doc.globalParameters[gi].cell = b
            var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
            ed.print("\(ed.doc.globalParameters[gi].name) = \(v) (from \(b)).")
        }
    }

    static var reportParam: CommandDef {
        CommandDef("REPORTPARAM", aliases: ["REPORTINGPARAM", "REPORTINGPARAMETER"], category: "Manage",
                   summary: "Makes a family parameter a reporting parameter measured from the model (host.thickness, host.height, host.length, level.elevation, level.height, self.rotation…).") { ed in
            guard let fn = try await ed.getWord("Family", defaultValue: ed.doc.families.first?.name), let fi = ed.doc.familyIndex(fn) else { throw CommandError.invalid("Family not found.") }
            guard let pn = try await ed.getWord("Parameter") else { return }
            let src = try await ed.getWord("Measured value (host.thickness, level.elevation, self.rotation, None)", defaultValue: "host.thickness") ?? "none"
            if let pi = ed.doc.families[fi].parameters.firstIndex(where: { $0.name.caseInsensitiveCompare(pn) == .orderedSame }) {
                ed.doc.families[fi].parameters[pi].reporting = src.lowercased() == "none" ? nil : src
                ed.doc.families[fi].parameters[pi].formula = nil
            } else {
                guard src.lowercased() != "none" else { return }
                var p = FamilyParameter(pn, .length, value: "0"); p.reporting = src
                ed.doc.families[fi].parameters.append(p)
            }
            var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
            ed.print("\(fn).\(pn) reports \(src).")
        }
    }

    static var familyLock: CommandDef {
        CommandDef("FAMILYLOCK", aliases: ["FAMLOCK", "FAMILYEQ", "PARAMLOCK"], category: "Manage",
                   summary: "Family constraints: Lock a reference plane to a parameter (dimension label), EQ planes equally spaced, Plane (add a reference plane).") { ed in
            guard let fn = try await ed.getWord("Family", defaultValue: ed.doc.families.first?.name), let fi = ed.doc.familyIndex(fn) else { throw CommandError.invalid("Family not found.") }
            let k = try await ed.getKeyword("Constraint", ["Lock", "EQ", "Plane", "List"], defaultValue: "Lock") ?? "Lock"
            var f = ed.doc.families[fi]
            switch k {
            case "Plane":
                guard let n = try await ed.getWord("Plane name"), let ax = try await ed.getKeyword("Axis", ["x", "y", "z"], defaultValue: "x"),
                      let off = try await ed.getString("Offset (expression)", defaultValue: "0") else { return }
                f.referencePlanes.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                f.referencePlanes.append(FamilyReferencePlane(n, axis: ax, offset: off))
            case "Lock":
                guard let pl = try await ed.getWord("Reference plane"), let pn = try await ed.getWord("Parameter") else { return }
                let base = try await ed.getWord("Measured from plane (Enter = origin)", defaultValue: "")
                guard FamilyConstraints.lock(pl, to: pn, from: (base ?? "").isEmpty ? nil : base, family: &f) else { throw CommandError.invalid("Plane or parameter not found.") }
            case "EQ":
                guard let s = try await ed.getString("Planes in order, comma separated (first and last stay)") else { return }
                let names = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard FamilyConstraints.equalize(names, family: &f) else { throw CommandError.invalid("EQ needs 3+ existing planes on one axis.") }
            default:
                for p in f.referencePlanes { ed.print("  \(p.name) [\(p.axis)] = \(p.offset)") }
                return
            }
            let r = FamilyEngine.evaluate(f, doc: ed.doc)
            guard r.errors.isEmpty else { throw CommandError.invalid("Constraint rejected: \(r.errors.joined(separator: "; "))") }
            ed.doc.families[fi] = f
            var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
            ed.print("Family \(fn) updated.")
        }
    }

    // MARK: PAR-032

    static var transferStandards: CommandDef {
        CommandDef("TRANSFERSTANDARDS", aliases: ["TRANSFERPROJECTSTANDARDS", "COPYSTANDARDS", "TPS"], category: "Manage",
                   summary: "Copies types, styles and settings (wall/slab/opening/stair/railing types, materials, layers, linetypes, text and dimension styles, view templates, families, parameters, schedules, keynotes) from another .archi file.") { ed in
            guard let path = try await ed.getString("Source .archi file") else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let data = try? Data(contentsOf: url), let src = try? ArchiFile.decode(data) else { throw CommandError.invalid("Cannot read \(path).") }
            ed.print("Categories: All or \(ProjectStandards.categories.joined(separator: ", "))")
            let spec = try await ed.getString("Categories (comma separated)", defaultValue: "All") ?? "All"
            var cats = Set<String>()
            if spec.lowercased() == "all" { cats = Set(ProjectStandards.categories.filter { $0 != "units" }) }
            else { for s in spec.split(separator: ",") { guard let c = ProjectStandards.category(s.trimmingCharacters(in: .whitespaces)) else { throw CommandError.invalid("Unknown category \(s).") }; cats.insert(c) } }
            let over = (try await ed.getKeyword("Duplicate types [Overwrite/New only]", ["Overwrite", "New"], defaultValue: "New") ?? "New") == "Overwrite"
            let counts = ProjectStandards.transfer(from: src, into: &ed.doc, categories: cats, overwrite: over)
            if counts.isEmpty { ed.print("Nothing to copy.") }
            for (k, v) in counts.sorted(by: { $0.key < $1.key }) { ed.print("  \(k): \(v)") }
        }
    }

    // MARK: DOC-037 / DOC-038 / DOC-039 / DOC-032

    static var detailComponent: CommandDef {
        CommandDef("DETAILCOMPONENT", aliases: ["DETAILCOMP", "DC", "COMPONENT2D"], category: "Annotate",
                   summary: "Places a 2D detail component (lumber, studs, brick, CMU, plywood, gypsum, steel sections) in the current view.") { ed in
            ed.print("Components: \(DetailComponents.catalogue.map(\.name).joined(separator: ", "))")
            guard let n = try await ed.getString("Component", defaultValue: ed.doc.variable("DETAILCOMP") ?? "Lumber 38x89"), let bn = DetailComponents.ensureBlock(n, doc: &ed.doc) else { throw CommandError.invalid("Unknown component.") }
            ed.doc.setVariable("DETAILCOMP", n)
            var k = 0
            while let p = try await ed.getPoint("Specify insertion point").point {
                let r = try await ed.getAngle("Rotation", base: p, defaultValue: 0).value ?? 0
                ed.doc.ensureLayer("A-DETL")
                let id = ed.doc.add(Entity(layer: "A-DETL", geometry: .insert(InsertGeom(block: bn, position: p, rotation: r)), props: ["detail": "component"]))
                _ = id; k += 1
            }
            ed.print("\(k) detail component(s) placed.")
        }
    }

    static var repeatDetail: CommandDef {
        CommandDef("REPEATDETAIL", aliases: ["REPEATINGDETAIL", "RDETAIL"], category: "Annotate",
                   summary: "Repeating detail: a component arrayed along a path (brick courses, blocking); editing the path or spacing regenerates it.") { ed in
            guard let n = try await ed.getString("Component", defaultValue: ed.doc.variable("REPEATCOMP") ?? "Brick 215x65"), let c = DetailComponents.find(n) else { throw CommandError.invalid("Unknown component.") }
            ed.doc.setVariable("REPEATCOMP", c.name)
            let a = try await ed.requirePoint("Specify start of the path")
            let b = try await ed.requirePoint("Specify end of the path", base: a) { p in [.line(LineGeom(a, p))] }
            guard a.distance(to: b) > 1e-9 else { return }
            let sp = try await ed.getPositive("Spacing", defaultValue: (c.w + (c.kind == "brick" ? 10 : 0)) / ed.doc.units.mm)
            ed.doc.ensureLayer("A-DETL")
            if ed.doc.layer(named: "A-DETL-PATH") == nil { var l = Layer(name: "A-DETL-PATH"); l.plot = false; l.color = RGBA(0.5, 0.5, 0.5); ed.doc.layers.append(l) }
            let id = ed.doc.add(Entity(layer: "A-DETL-PATH", geometry: .line(LineGeom(a, b)), props: ["repeatDetail": c.name, "repeatSpacing": fmt(sp, 6), "detail": "path"]))
            RepeatingDetails.updateAll(&ed.doc)
            ed.print("Repeating detail #\(id): \(ed.doc.entities.filter { $0.props["repeatOf"] == "\(id)" }.count) × \(c.name).")
        }
    }

    static var insulation: CommandDef {
        CommandDef("INSULATION", aliases: ["BATT", "INSUL", "BATTINSULATION"], category: "Annotate",
                   summary: "Draws the batt insulation symbol along a line at a given width (associative: stretch the line to extend it).") { ed in
            let w = try await ed.getPositive("Insulation width", defaultValue: ed.variableDouble("INSULWIDTH", 100 / ed.doc.units.mm))
            ed.doc.setVariable("INSULWIDTH", fmt(w))
            let a = try await ed.requirePoint("Specify start point")
            let b = try await ed.requirePoint("Specify end point", base: a) { p in [.polyline(PolylineGeom(points: DetailComponents.insulation(a: a, b: p, width: w)))] }
            guard a.distance(to: b) > 1e-9 else { return }
            ed.doc.ensureLayer("A-DETL")
            ed.doc.add(Entity(layer: "A-DETL", geometry: .line(LineGeom(a, b)), props: ["insulation": fmt(w, 6), "detail": "insulation"]))
        }
    }

    static var materialTag: CommandDef {
        CommandDef("MATERIALTAG", aliases: ["MATTAG", "TAGMATERIAL"], category: "Annotate",
                   summary: "Tags the material under a picked point (the layer of a compound wall, a slab's finish, or the element material); the tag follows material changes.") { ed in
            var n = 0
            while true {
                guard case .pick(let pk) = try await ed.pickObject("Pick a point on an element", filter: { ed.doc.element($0) != nil }), let el = ed.doc.element(pk.id) else { break }
                let m = MaterialTags.material(at: pk.point, of: el, doc: ed.doc) ?? "?"
                let p2 = try await ed.requirePoint("Specify tag location", base: pk.point) { c in [.line(LineGeom(pk.point, c))] }
                let th = ed.variableDouble("TEXTSIZE", 150 / ed.doc.units.mm)
                ed.doc.ensureLayer("A-ANNO-TEXT")
                ed.doc.add(Entity(layer: "A-ANNO-TEXT", geometry: .leader(LeaderGeom(points: [pk.point, p2, p2 + Vec2(th * 2, 0)], text: m, textHeight: th)),
                                  props: ["materialTagOf": "\(el.id)", "materialTagAt": "\(fmt(pk.point.x, 6)),\(fmt(pk.point.y, 6))"]))
                n += 1
            }
            if n > 0 { ed.print("\(n) material tag(s).") }
        }
    }

    // MARK: DOC-052

    static var scheduleCells: CommandDef {
        CommandDef("SCHEDULECELLS", aliases: ["SCHEDULEHIGHLIGHT", "CONDITIONALFORMAT"], category: "Annotate",
                   summary: "Conditional formatting of schedules: highlight the Row or only the Cell of a field when \"field op value\" holds (shown in placed schedules); Clear.") { ed in
            guard let n = try await ed.getWord("Schedule", defaultValue: ed.doc.schedules.first?.name), let si = ed.doc.schedules.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Schedule not found.") }
            let k = try await ed.getKeyword("Highlight [Row/Cell/Clear]", ["Row", "Cell", "Clear"], defaultValue: "Cell") ?? "Cell"
            if k == "Clear" { ed.doc.schedules[si].highlights = []; var d = ed.doc; Schedules.updateAll(&d); ed.doc = d; return }
            guard let r = try await ed.getString("Rule \"field op value\" (e.g. Area > 20)") else { return }
            let parts = r.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3, ["<", "<=", ">", ">=", "=", "==", "!=", "<>", "contains"].contains(parts[1].lowercased()) else { throw CommandError.invalid("Use \"field op value\".") }
            let c = RGBA(hex: try await ed.getWord("Color (#RRGGBB)", defaultValue: "#FFD54F") ?? "#FFD54F")
            var h = ScheduleHighlight(field: parts[0], op: parts[1], value: parts[2], color: c)
            h.cellOnly = k == "Cell" ? true : nil
            ed.doc.schedules[si].highlights.append(h)
            var d = ed.doc; Schedules.updateAll(&d); ed.doc = d
            let t = Schedules.evaluate(ed.doc.schedules[si], doc: ed.doc)
            ed.print("\(t.rows.filter { $0.highlight != nil || !$0.cellHighlights.isEmpty }.count) row(s) highlighted.")
        }
    }
}
