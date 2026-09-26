// Oanarina Archi Tool — GPL-3.0-or-later
// Escalators (BIM-074) and section plane objects (M3D-038).
import Foundation

enum BIMMoreCommands {
    static var all: [CommandDef] { [escalator, sectionObject, gridSystem, radialGrid, wallFlip, splitWall, openingFlip, globalParam, zone, pset, classify, viewRange, underlay, revealHidden, tempHide, tempIsolate, geolocation, roofShape] }

    @MainActor static func gridLabelStarts(_ ed: Editor) -> (Int, Int) {
        let labels = ed.doc.elements.compactMap { el -> String? in if case .gridLine(let g) = el.geometry { return g.label }; return nil }
        let n = (labels.compactMap { Int($0) }.max() ?? 0) + 1
        var l = 0
        while labels.contains(GridSystems.letter(l)) { l += 1 }
        return (n, l)
    }

    @MainActor static func addGrids(_ ed: Editor, _ gs: [GridLineGeom]) -> [EntityID] {
        gs.map { ed.doc.addElement(.gridLine($0), name: "Grid \($0.label)") }
    }

    static var gridSystem: CommandDef {
        CommandDef("GRIDSYSTEM", aliases: ["GRIDGEN", "RECTGRID", "GRIDARRAY"], category: "Architecture", summary: "Creates a rectangular grid system from spacing lists (e.g. 3*6000 4500): numbered grids along X, lettered along Y.") { ed in
            let u = 1 / ed.doc.units.mm
            let o = try await ed.requirePoint("Specify origin (grid 1 / A intersection)")
            guard let xs = GridSystems.spacings(try await ed.getString("Spacings along X (e.g. 3*6000 4500)", defaultValue: ed.doc.variable("GRIDSYSX") ?? "3*\(fmt(6000 * u))") ?? "") else { throw CommandError.invalid("Use spacings like 3*6000 4500.") }
            guard let ys = GridSystems.spacings(try await ed.getString("Spacings along Y", defaultValue: ed.doc.variable("GRIDSYSY") ?? "2*\(fmt(6000 * u))") ?? "") else { throw CommandError.invalid("Use spacings like 2*6000.") }
            let ov = try await ed.getPositive("Overhang beyond the outer grids", defaultValue: 1500 * u, allowZero: true)
            let rot = try await ed.getAngle("Rotation", base: o, defaultValue: 0).value ?? 0
            ed.doc.setVariable("GRIDSYSX", xs.map { fmt($0) }.joined(separator: " ")); ed.doc.setVariable("GRIDSYSY", ys.map { fmt($0) }.joined(separator: " "))
            let (n, l) = gridLabelStarts(ed)
            let ids = addGrids(ed, GridSystems.rectangular(origin: o, xs: xs, ys: ys, overhang: ov, rotation: rot, firstNumber: n, firstLetter: l))
            ed.selection = Set(ids)
            ed.print("\(xs.count + 1) × \(ys.count + 1) grid system created (\(ids.count) grid lines).")
        }
    }

    static var radialGrid: CommandDef {
        CommandDef("RADIALGRID", aliases: ["GRIDRADIAL", "POLARGRID"], category: "Architecture", summary: "Creates a radial grid system: centre, start angle, angular spacings (e.g. 6*15), inner radius and radial spacings; numbered radial grids and lettered arc grids.") { ed in
            let u = 1 / ed.doc.units.mm
            let c = try await ed.requirePoint("Specify centre of the radial grid")
            let a0 = try await ed.getAngle("Start angle", base: c, defaultValue: 0).value ?? 0
            guard let angs = GridSystems.spacings(try await ed.getString("Angular spacings in degrees (e.g. 6*15)", defaultValue: "6*15") ?? "") else { throw CommandError.invalid("Use spacings like 6*15.") }
            let r0 = try await ed.getPositive("Inner radius", defaultValue: 3000 * u, allowZero: true)
            guard let rs = GridSystems.spacings(try await ed.getString("Radial spacings (e.g. 2*6000)", defaultValue: "2*\(fmt(6000 * u))") ?? "") else { throw CommandError.invalid("Use spacings like 2*6000.") }
            let ov = try await ed.getPositive("Overhang", defaultValue: 1500 * u, allowZero: true)
            let (n, l) = gridLabelStarts(ed)
            guard let gs = GridSystems.radial(center: c, startAngle: a0, angles: angs.map { $0 * .pi / 180 }, innerRadius: r0, radii: rs, overhang: ov, firstNumber: n, firstLetter: l) else {
                throw CommandError.invalid("The total angle (with overhang) must stay below 360°.")
            }
            let ids = addGrids(ed, gs)
            ed.selection = Set(ids)
            ed.print("Radial grid created: \(angs.count + 1) radial and \(gs.count - angs.count - 1) arc grid line(s).")
        }
    }

    static func isWall(_ doc: ArchiDocument, _ id: EntityID) -> Bool { if case .wall? = doc.element(id)?.geometry { return true }; return false }

    static var wallFlip: CommandDef {
        CommandDef("WALLFLIP", aliases: ["FLIPWALL", "WALLREVERSE"], category: "Architecture", summary: "Flips walls: swaps the interior and exterior faces (layer order) keeping the wall, its openings and door swings in place.") { ed in
            let ids = try await ed.getSelection("Select walls to flip").filter { isWall(ed.doc, $0) }
            guard !ids.isEmpty else { throw CommandError.invalid("Select walls.") }
            var n = 0
            for id in ids where WallTools.flip(&ed.doc, wall: id) { n += 1 }
            ed.print("\(n) wall(s) flipped.")
        }
    }

    static var splitWall: CommandDef {
        CommandDef("SPLITWALL", aliases: ["WALLSPLIT", "SPLITELEMENT"], category: "Architecture", summary: "Splits a wall at a picked point (repeatable) or by Levels into one wall per storey; hosted openings follow their piece.") { ed in
            let r = try await ed.pickObject("Select wall at the split point", keywords: ["Levels"], filter: { isWall(ed.doc, $0) })
            switch r {
            case .pick(let pk):
                guard let nid = WallTools.split(&ed.doc, wall: pk.id, at: pk.point) else { throw CommandError.invalid("Cannot split there (wall end or inside an opening).") }
                ed.selection = [pk.id, nid]
                ed.print("Wall split into #\(pk.id) and #\(nid).")
            case .keyword:
                let ids = try await ed.getSelection("Select walls to split by levels").filter { isWall(ed.doc, $0) }
                var made = 0
                for id in ids { made += WallTools.splitByLevels(&ed.doc, wall: id).count - 1 }
                ed.print(made == 0 ? "No wall crosses a level." : "\(made) storey piece(s) created.")
            default: return
            }
        }
    }

    static var openingFlip: CommandDef {
        CommandDef("OPENINGFLIP", aliases: ["FLIPDOOR", "FLIPWINDOW", "DOORFLIP", "FLIPOPENING"], category: "Architecture", summary: "Flips doors and windows: Hand (hinge side), Facing (swing / exterior side) or Both.") { ed in
            let ids = try await ed.getSelection("Select doors or windows").filter { if case .opening? = ed.doc.element($0)?.geometry { return true }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("Select doors or windows.") }
            let k = try await ed.getKeyword("Flip", ["Hand", "Facing", "Both"], defaultValue: "Facing") ?? "Facing"
            var n = 0
            for id in ids where WallTools.flipOpening(&ed.doc, id, hand: k != "Facing", facing: k != "Hand") { n += 1 }
            ed.print("\(n) opening(s) flipped (\(k.lowercased())).")
        }
    }

    static var globalParam: CommandDef {
        CommandDef("GLOBALPARAM", aliases: ["GLOBALPARAMS", "GLOBALPARAMETERS", "PROJECTPARAM"], category: "Manage", summary: "Global parameters: New/Set a value or =formula, Bind element dimensions (wall height, thickness, opening width…) to an expression, Unbind, List, Delete; bound elements and family formulas update when a value changes.") { ed in
            let k = try await ed.getKeyword("Global parameter option", ["New", "Set", "Bind", "Unbind", "List", "Delete", "Project", "Shared"], defaultValue: "List") ?? "List"
            if k == "Project" {
                // Project parameters bound to categories (PAR-023).
                let op = try await ed.getKeyword("Project parameter option", ["New", "Value", "Delete", "List"], defaultValue: "List") ?? "List"
                switch op {
                case "New":
                    guard let n = try await ed.getWord("Parameter name"), !n.isEmpty, n.first!.isLetter else { throw CommandError.invalid("Names start with a letter.") }
                    let kw = try await ed.getKeyword("Type", ["Text", "Length", "Number", "Integer", "Area", "YesNo", "Material"], defaultValue: "Text") ?? "Text"
                    let kind: FamilyParameterKind = kw == "YesNo" ? .yesNo : (FamilyParameterKind(rawValue: kw.lowercased()) ?? .text)
                    let cats = try await ed.getWord("Categories (comma-separated; All)", defaultValue: "All") ?? "All"
                    let v = try await ed.getWord("Default value or =formula", defaultValue: "") ?? ""
                    var p = ProjectParameter(name: n, kind: kind, categories: cats.lowercased() == "all" ? [] : cats.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    if v.hasPrefix("=") { p.formula = String(v.dropFirst()) } else { p.value = v }
                    ed.doc.projectParameters.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                    ed.doc.projectParameters.append(p)
                    ed.print("Project parameter \(n) added to " + (p.categories.isEmpty ? "all categories" : p.categories.joined(separator: ", ")) + ".")
                case "Value":
                    guard let n = try await ed.getWord("Parameter name"), let p = ProjectParameters.parameter(n, doc: ed.doc) else { throw CommandError.invalid("Unknown project parameter.") }
                    let ids = try await ed.getSelection("Select elements")
                    let v = try await ed.getWord("Value (empty = default)", defaultValue: "") ?? ""
                    var c = 0
                    for id in ids { if let i = ed.doc.elementIndex(id), ProjectParameters.applies(p, to: ed.doc.elements[i]) { ed.doc.elements[i].props[p.name] = v.isEmpty ? nil : v; c += 1 } }
                    ed.print("\(p.name) set on \(c) element(s).")
                case "Delete":
                    guard let n = try await ed.getWord("Parameter name"), let i = ed.doc.projectParameters.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Unknown project parameter.") }
                    ed.doc.projectParameters.remove(at: i); ed.print("\(n) removed.")
                default:
                    if ed.doc.projectParameters.isEmpty { ed.print("No project parameters.") }
                    for p in ed.doc.projectParameters { ed.print("  \(p.name) [\(p.kind.rawValue)] " + (p.categories.isEmpty ? "all" : p.categories.joined(separator: ",")) + (p.formula.map { " = \($0)" } ?? (p.value.isEmpty ? "" : " default \(p.value)")) + (p.guid.map { " (shared \($0.prefix(8)))" } ?? "")) }
                }
                var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
                return
            }
            if k == "Shared" {
                // Shared parameter files (PAR-022): export definitions, or import and bind them to categories.
                let op = try await ed.getKeyword("Shared parameters", ["Export", "Import"], defaultValue: "Import") ?? "Import"
                let url = try await IOCommands.path(ed, "Shared parameter file (.txt)")
                if op == "Export" {
                    var ps = ed.doc.projectParameters
                    for i in ps.indices where ps[i].guid == nil { ps[i].guid = UUID().uuidString }
                    ed.doc.projectParameters = ps
                    try IOCommands.write(ed, url, "shared parameters", { try ProjectParameters.sharedFile(ps).write(to: url, atomically: true, encoding: .utf8) })
                } else {
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(url.path).") }
                    let defs = ProjectParameters.parseShared(text)
                    guard !defs.isEmpty else { throw CommandError.invalid("No parameter definitions in \(url.lastPathComponent).") }
                    let names = try await ed.getWord("Parameters to add (comma-separated; All)", defaultValue: "All") ?? "All"
                    let pick = names.lowercased() == "all" ? defs : defs.filter { d in names.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(d.name) == .orderedSame } }
                    let cats = try await ed.getWord("Categories (comma-separated; All)", defaultValue: "All") ?? "All"
                    let n = ProjectParameters.bind(pick, categories: cats.lowercased() == "all" ? [] : cats.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, doc: &ed.doc)
                    ed.print("\(pick.count) shared parameter(s) bound (\(n) new).")
                }
                return
            }
            @MainActor func show() { let v = GlobalParameters.values(ed.doc); for p in ed.doc.globalParameters { ed.print("  \(p.name) = \(v[p.name.lowercased()].map { fmt($0) } ?? p.value)" + (p.formula.map { "  (= \($0))" } ?? "") + "  used by \(GlobalParameters.dependents(p.name, doc: ed.doc).count)") } }
            switch k {
            case "New", "Set":
                guard let n = try await ed.getWord("Parameter name"), !n.isEmpty, n.first!.isLetter else { throw CommandError.invalid("Names start with a letter.") }
                let existing = ed.doc.globalParameters.firstIndex { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                if k == "Set", existing == nil { throw CommandError.invalid("No global parameter \(n).") }
                let kind: FamilyParameterKind = existing.map { ed.doc.globalParameters[$0].kind } ?? .length
                let v = try await ed.getString("Value or =formula", defaultValue: existing.map { ed.doc.globalParameters[$0].formula.map { "=" + $0 } ?? ed.doc.globalParameters[$0].value } ?? "0") ?? "0"
                let p = FamilyParameter(existing.map { ed.doc.globalParameters[$0].name } ?? n, kind, value: v.hasPrefix("=") ? "0" : v, formula: v.hasPrefix("=") ? String(v.dropFirst()) : nil, instance: false)
                var trial = ed.doc.globalParameters
                if let i = existing { trial[i] = p } else { trial.append(p) }
                let errs = FamilyExpr.resolve(FamilyDefinition(name: "Global", parameters: trial)).errors
                guard errs.isEmpty else { throw CommandError.invalid(errs.joined(separator: "; ")) }
                ed.doc.globalParameters = trial
                var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
                ed.print("\(p.name) = \(fmt(GlobalParameters.values(ed.doc)[p.name.lowercased()] ?? 0)); \(GlobalParameters.dependents(p.name, doc: ed.doc).count) bound element(s) updated.")
            case "Bind":
                let ids = try await ed.getSelection("Select walls, slabs, openings or columns")
                guard let f = try await ed.getWord("Field [height/thickness/baseOffset/topOffset/width/depth/sill]"), !f.isEmpty else { return }
                guard let expr = try await ed.getString("Expression over global parameters"), !expr.isEmpty else { return }
                var vals = GlobalParameters.values(ed.doc)
                for p in ed.doc.projectParameters where p.kind.isNumeric { vals[p.name.lowercased()] = Double(p.value) ?? 1 }
                guard FamilyExpr.evaluate(expr, vals) != nil else { throw CommandError.invalid("\"\(expr)\" does not evaluate (unknown parameter?).") }
                var n = 0
                for id in ids {
                    guard let i = ed.doc.elementIndex(id), let canon = GlobalParameters.field(f, for: ed.doc.elements[i].geometry) else { continue }
                    ed.doc.elements[i].props["gp." + canon] = expr; n += 1
                }
                var d = ed.doc; BIMUpdaters.run(&d); ed.doc = d
                ed.print("\(n) element(s) bound (\(f) = \(expr)).")
            case "Unbind":
                let ids = try await ed.getSelection("Select elements")
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props = ed.doc.elements[i].props.filter { !$0.key.hasPrefix("gp.") } } }
                ed.print("Bindings removed from \(ids.count) element(s).")
            case "Delete":
                guard let n = try await ed.getWord("Parameter name"), let i = ed.doc.globalParameters.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Unknown global parameter.") }
                let deps = GlobalParameters.dependents(n, doc: ed.doc)
                guard deps.isEmpty else { throw CommandError.invalid("\(n) drives \(deps.count) element(s); unbind them first.") }
                ed.doc.globalParameters.remove(at: i); ed.print("\(n) deleted.")
            default:
                if ed.doc.globalParameters.isEmpty { ed.print("No global parameters.") } else { show() }
            }
        }
    }

    static var zone: CommandDef {
        CommandDef("ZONE", aliases: ["ZONES", "ROOMZONE"], category: "Architecture", summary: "Zones: Assign rooms to a named fire/HVAC/department/security zone, Remove, List zone areas, or draw zone Outlines (rooms merged across the walls).") { ed in
            let k = try await ed.getKeyword("Zone option", ["Assign", "Remove", "List", "Outline"], defaultValue: "Assign") ?? "Assign"
            let isRoom: (EntityID) -> Bool = { if case .space? = ed.doc.element($0)?.geometry { return true }; return false }
            switch k {
            case "Assign", "Remove":
                let ids = try await ed.getSelection("Select rooms").filter(isRoom)
                guard !ids.isEmpty else { throw CommandError.invalid("Select rooms.") }
                let t = try await ed.getKeyword("Zone type", Zones.types, defaultValue: ed.doc.variable("ZONETYPE") ?? "Fire") ?? "Fire"
                ed.doc.setVariable("ZONETYPE", t)
                if k == "Remove" { ed.print("\(Zones.assign(&ed.doc, rooms: ids, type: t, name: "")) room(s) removed from their \(t) zone."); return }
                guard let n = try await ed.getWord("Zone name", defaultValue: "\(t) 1"), !n.isEmpty else { return }
                ed.print("\(Zones.assign(&ed.doc, rooms: ids, type: t, name: n)) room(s) in \(t) zone \(n).")
            case "Outline":
                let t = try await ed.getKeyword("Zone type", Zones.types, defaultValue: ed.doc.variable("ZONETYPE") ?? "Fire") ?? "Fire"
                let gap = try await ed.getPositive("Wall gap to bridge", defaultValue: ed.variableDouble("ZONEGAP", 400 / ed.doc.units.mm))
                ed.doc.setVariable("ZONEGAP", fmt(gap))
                let layer = "A-ZONE-" + t.uppercased()
                ed.doc.ensureLayer(layer)
                ed.doc.remove(ids: Set(ed.doc.entities.filter { $0.props["zoneOutline"]?.hasPrefix(t + ":") ?? false }.map(\.id)))
                var n = 0
                for z in Zones.all(ed.doc, type: t) {
                    for l in Zones.outline(z, doc: ed.doc, gap: gap) {
                        let id = ed.doc.add(.polyline(PolylineGeom(points: l, closed: true)), layer: layer)
                        if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["zoneOutline"] = "\(t):\(z.name)"; ed.doc.entities[i].lineweight = 0.7 }
                        n += 1
                    }
                    if let big = Zones.outline(z, doc: ed.doc, gap: gap).max(by: { abs(GeometryOps.signedArea($0)) < abs(GeometryOps.signedArea($1)) }) {
                        let c = LabelPlacement.pole(of: big).point
                        let id = ed.doc.add(.text(TextGeom(position: c, height: 300 / ed.doc.units.mm, content: "\(z.name)  \(fmt(z.area * pow(ed.doc.units.mm, 2) / 1e6, 2)) m²", halign: .center, valign: .middle)), layer: layer)
                        if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["zoneOutline"] = "\(t):\(z.name)" }
                    }
                }
                ed.print("\(n) \(t) zone outline(s) drawn on \(layer).")
            default:
                let zs = Zones.all(ed.doc)
                if zs.isEmpty { ed.print("No zones."); return }
                for z in zs { ed.print("\(z.type) \(z.name): \(z.rooms.count) room(s), \(fmt(z.area * pow(ed.doc.units.mm, 2) / 1e6, 2)) m²") }
            }
        }
    }

    static var pset: CommandDef {
        CommandDef("PSET", aliases: ["PSETS", "PROPERTYSET", "PROPERTYSETS"], category: "Manage", summary: "Property sets (IFC Psets): Set Pset.Property values (typed by templates), Apply a template's defaults, List an element's sets, Remove, Check values, and custom Templates (New/Add/Delete/List).") { ed in
            let k = try await ed.getKeyword("Property set option", ["Set", "Apply", "List", "Remove", "Check", "Template"], defaultValue: "List") ?? "List"
            switch k {
            case "Set":
                let ids = try await ed.getSelection("Select elements").filter { ed.doc.element($0) != nil }
                guard let full = try await ed.getWord("Property as Pset.Property (e.g. Pset_WallCommon.FireRating)"), let dot = full.firstIndex(of: "."), dot != full.startIndex else { throw CommandError.invalid("Use Pset.Property.") }
                guard let v = try await ed.getString("Value") else { return }
                var n = 0, errs: [String] = []
                for id in ids { if let e = PropertySets.set(&ed.doc, id, pset: String(full[..<dot]), property: String(full[full.index(after: dot)...]), value: v) { errs.append("#\(id): \(e)") } else { n += 1 } }
                ed.print("\(n) element(s) set." + (errs.isEmpty ? "" : " " + errs.joined(separator: "; ")))
            case "Apply":
                let names = ed.doc.allPsetTemplates.map(\.name)
                guard let tn = try await ed.getWord("Template [\(names.joined(separator: "/"))]"), let t = ed.doc.psetTemplate(tn) else { throw CommandError.invalid("Unknown template.") }
                let ids = try await ed.getSelection("Select elements (Enter = all applicable)")
                let target = ids.isEmpty ? ed.doc.elements.map(\.id) : ids
                ed.print("\(t.name) applied to \(PropertySets.apply(&ed.doc, template: t, to: target)) element(s).")
            case "Remove":
                let ids = try await ed.getSelection("Select elements")
                guard let w = try await ed.getWord("Pset or Pset.Property to remove"), !w.isEmpty else { return }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props = ed.doc.elements[i].props.filter { !($0.key == w || $0.key.hasPrefix(w + ".")) } } }
                ed.print("Removed \(w) from \(ids.count) element(s).")
            case "Check":
                let issues = PropertySets.check(ed.doc)
                if issues.isEmpty { ed.print("All property values match their templates.") } else { issues.forEach { ed.print($0) } }
            case "Template":
                let t = try await ed.getKeyword("Template option", ["New", "Add", "Delete", "List"], defaultValue: "List") ?? "List"
                switch t {
                case "New":
                    guard let n = try await ed.getWord("Template name (e.g. CPset_Acoustics)"), !n.isEmpty, !n.contains(".") else { throw CommandError.invalid("A name without dots.") }
                    let ap = try await ed.getString("Applies to (wall door window slab… separated by commas; Enter = all)", defaultValue: "") ?? ""
                    ed.doc.psetTemplates.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                    ed.doc.psetTemplates.append(PsetTemplate(name: n, applicableTo: ap.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)))
                    ed.print("Template \(n) created.")
                case "Add":
                    guard let n = try await ed.getWord("Template name"), let i = ed.doc.psetTemplates.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Unknown custom template (PSET Template New).") }
                    guard let pn = try await ed.getWord("Property name"), !pn.isEmpty else { return }
                    let kind = try await ed.getKeyword("Type", PsetProperty.Kind.allCases.map { $0.rawValue.capitalized }, defaultValue: "Label") ?? "Label"
                    let pk = PsetProperty.Kind(rawValue: kind.lowercased()) ?? .label
                    let d = try await ed.getString("Default value (Enter = none)", defaultValue: "") ?? ""
                    let prop = PsetProperty(pn, pk, defaultValue: d.isEmpty ? nil : d)
                    if !d.isEmpty, prop.normalize(d) == nil { throw CommandError.invalid("The default is not a \(pk.rawValue).") }
                    ed.doc.psetTemplates[i].properties.removeAll { $0.name.caseInsensitiveCompare(pn) == .orderedSame }
                    ed.doc.psetTemplates[i].properties.append(prop)
                    ed.print("\(ed.doc.psetTemplates[i].name).\(pn) (\(pk.rawValue)) added.")
                case "Delete":
                    guard let n = try await ed.getWord("Template name"), ed.doc.psetTemplates.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Unknown custom template.") }
                    ed.doc.psetTemplates.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                    ed.print("Template \(n) deleted (values stay on the elements).")
                default:
                    for t in ed.doc.allPsetTemplates { ed.print("\(t.name) [\(t.applicableTo.isEmpty ? "all" : t.applicableTo.joined(separator: ","))]: " + t.properties.map { "\($0.name):\($0.kind.rawValue)" }.joined(separator: ", ")) }
                }
            default:
                guard case .pick(let pk) = try await ed.pickObject("Select an element", filter: { ed.doc.element($0) != nil }), let el = ed.doc.element(pk.id) else { return }
                let sets = PropertySets.sets(el)
                if sets.isEmpty { ed.print("#\(el.id) has no property sets.") }
                for (n, props) in sets.sorted(by: { $0.key < $1.key }) { ed.print("\(n): " + props.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")) }
            }
        }
    }

    static var classify: CommandDef {
        CommandDef("CLASSIFY", aliases: ["CLASSIFICATION", "CLASSCODE"], category: "Manage", summary: "Classification codes: Auto-classify by element kind (Uniformat II, NL-SfB), Set a code in any system (Uniclass 2015, OmniClass…), List, Clear.") { ed in
            let k = try await ed.getKeyword("Classification option", ["Auto", "Set", "List", "Clear"], defaultValue: "Auto") ?? "Auto"
            let sys = try await ed.getWord("System [\(Classification.systems.joined(separator: "/"))]", defaultValue: ed.doc.variable("CLASSSYSTEM") ?? "Uniformat") ?? "Uniformat"
            ed.doc.setVariable("CLASSSYSTEM", sys)
            let key = Classification.key(sys)
            switch k {
            case "Auto":
                let ids = try await ed.getSelection("Select elements (Enter = all)")
                let over = try await ed.getYesNo("Overwrite existing codes?", defaultValue: false)
                let n = Classification.autoClassify(&ed.doc, system: sys, ids: ids.isEmpty ? nil : ids, overwrite: over)
                ed.print("\(n) element(s) classified in \(sys)." + (["uniformat", "nlsfb"].contains(sys.lowercased()) ? "" : " (No automatic table for \(sys): use Set.)"))
            case "Set":
                let ids = try await ed.getSelection("Select elements").filter { ed.doc.element($0) != nil }
                guard let code = try await ed.getWord("Code (e.g. Ss_25_10_30)"), !code.isEmpty else { return }
                let title = try await ed.getString("Title (Enter = none)", defaultValue: "") ?? ""
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[key] = code; ed.doc.elements[i].props[key + "Title"] = title.isEmpty ? nil : title } }
                ed.print("\(ids.count) element(s) set to \(sys) \(code).")
            case "Clear":
                let ids = try await ed.getSelection("Select elements")
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[key] = nil; ed.doc.elements[i].props[key + "Title"] = nil } }
                ed.print("\(sys) codes cleared on \(ids.count) element(s).")
            default:
                var groups: [String: Int] = [:]
                for el in ed.doc.elements { if let c = el.props[key] { groups[c + (el.props[key + "Title"].map { " " + $0 } ?? ""), default: 0] += 1 } }
                if groups.isEmpty { ed.print("No \(sys) codes.") }
                for (c, n) in groups.sorted(by: { $0.key < $1.key }) { ed.print("  \(c): \(n)") }
                ed.print("\(ed.doc.elements.filter { $0.props[key] == nil && $0.typeName != "grid" }.count) element(s) unclassified.")
            }
        }
    }

    static var viewRange: CommandDef {
        CommandDef("VIEWRANGE", aliases: ["VR", "PLANRANGE"], category: "View", summary: "Plan view range relative to the level: Top, Cut plane, Bottom and View depth; elements above the top are left out and those below the bottom (down to the view depth, also from lower levels) are drawn as beyond. Off restores the default.") { ed in
            let u = 1 / ed.doc.units.mm
            let cur = ViewRange.range(ed.doc) ?? ViewRange.Range(top: 2300 * u, cut: 1200 * u, bottom: 0, depth: 0)
            let r = try await ed.getDistance("Top of the view range", defaultValue: cur.top, keywords: ["Off", "Region"])
            if case .keyword("Region") = r {
                // Plan regions (DOC-012): a local view range inside a boundary of the current level's plan.
                let f = try await ed.requirePoint("Specify first point of the plan region")
                guard let poly = try await ArchitectureCommands.polygonInput(ed, first: f) else { throw CommandError.invalid("A plan region needs at least three points.") }
                let top = try await ed.getDistance("Top of the region's view range", defaultValue: cur.top).value ?? cur.top
                let cut = try await ed.getDistance("Cut plane", defaultValue: min(cur.cut, top)).value ?? cur.cut
                let bottom = try await ed.getDistance("Bottom", defaultValue: cur.bottom).value ?? cur.bottom
                let depth = try await ed.getDistance("View depth", defaultValue: min(cur.depth, bottom)).value ?? bottom
                guard top >= cut, cut >= bottom, bottom >= depth else { throw CommandError.invalid("Use top ≥ cut ≥ bottom ≥ view depth.") }
                let id = PlanRegions.add(poly, range: ViewRange.Range(top: top, cut: cut, bottom: bottom, depth: depth), level: ed.doc.currentLevel, doc: &ed.doc)
                ed.print("Plan region #\(id) created (cut \(fmt(cut)), bottom \(fmt(bottom))).")
                return
            }
            if case .keyword = r { ViewRange.store(nil, in: &ed.doc); ed.print("View range off."); return }
            guard let top = r.value else { return }
            let cut = try await ed.getDistance("Cut plane", defaultValue: min(cur.cut, top)).value ?? cur.cut
            let bottom = try await ed.getDistance("Bottom", defaultValue: cur.bottom).value ?? cur.bottom
            let depth = try await ed.getDistance("View depth (at or below the bottom)", defaultValue: min(cur.depth, bottom)).value ?? bottom
            guard top >= cut, cut >= bottom, bottom >= depth else { throw CommandError.invalid("Use top ≥ cut ≥ bottom ≥ view depth.") }
            ViewRange.store(ViewRange.Range(top: top, cut: cut, bottom: bottom, depth: depth), in: &ed.doc)
            ed.print("View range: top \(fmt(top)), cut \(fmt(cut)), bottom \(fmt(bottom)), depth \(fmt(depth)).")
        }
    }

    static var underlay: CommandDef {
        CommandDef("UNDERLAY", aliases: ["UNDERLAYLEVEL", "HALFTONELEVEL"], category: "View", summary: "Shows another level halftone under the current plan (None to turn off).") { ed in
            let names = ed.doc.levels.map(\.name)
            guard let n = try await ed.getWord("Underlay level [\(names.joined(separator: "/"))/None]", defaultValue: "None") else { return }
            if n.caseInsensitiveCompare("None") == .orderedSame || n.caseInsensitiveCompare("Off") == .orderedSame { ed.doc.variables["UNDERLAY"] = nil; ed.print("Underlay off."); return }
            guard let l = ed.doc.levels.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame || "\($0.id)" == n }) else { throw CommandError.invalid("Unknown level.") }
            ed.doc.setVariable("UNDERLAY", "\(l.id)")
            ed.print("\(l.name) shown as underlay.")
        }
    }

    static var revealHidden: CommandDef {
        CommandDef("REVEALHIDDEN", aliases: ["REVEAL", "SHOWHIDDEN"], category: "View", summary: "Reveal hidden elements: On draws temporarily hidden objects in magenta, Off stops, Unhide restores objects by id (#12,#15) or All.") { ed in
            let k = try await ed.getKeyword("Reveal hidden", ["On", "Off", "Unhide"], defaultValue: ed.doc.variable("REVEALHIDDEN") == "1" ? "Off" : "On") ?? "On"
            switch k {
            case "Unhide":
                guard let w = try await ed.getWord("Object ids (#12,#15) or All", defaultValue: "All") else { return }
                let ids: Set<EntityID>? = w.caseInsensitiveCompare("All") == .orderedSame ? nil : Set(w.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0.drop { $0 == "#" }) })
                ed.print("\(ViewRange.unhide(ids, in: &ed.doc)) object(s) restored.")
            default:
                ed.doc.variables["REVEALHIDDEN"] = k == "On" ? "1" : nil
                let h = HiddenObjects.load(ed.doc)
                ed.print(k == "On" ? "Revealing \(h.entities.count + h.elements.count) hidden object(s) in magenta." : "Reveal hidden off.")
            }
        }
    }

    static let categoryWords = ["wall", "door", "window", "opening", "slab", "column", "beam", "roof", "stair", "railing", "space", "curtainWall", "component", "grid"]

    static var tempHide: CommandDef {
        CommandDef("TEMPHIDE", aliases: ["HH", "HIDECATEGORY", "HC"], category: "View", summary: "Temporarily hides the selected elements, or a whole Category (wall, door, component…) on the current level; UNISOLATEOBJECTS or REVEALHIDDEN Unhide restores them.") { ed in
            let r = try await ed.getKeyword("Hide [Selection/Category]", ["Selection", "Category"], defaultValue: ed.selection.isEmpty ? "Category" : "Selection") ?? "Selection"
            if r == "Category" {
                guard let c = try await ed.getWord("Category [\(categoryWords.joined(separator: "/"))]"), categoryWords.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame }) else { throw CommandError.invalid("Unknown category.") }
                ed.print("\(ViewRange.hideCategory([c], level: ed.doc.currentLevel, in: &ed.doc)) \(c) element(s) hidden.")
            } else {
                let ids = try await ed.getSelection("Select objects to hide")
                ed.selection = []
                ed.print("\(HiddenObjects.hide(Set(ids), in: &ed.doc)) object(s) hidden.")
            }
        }
    }

    static var tempIsolate: CommandDef {
        CommandDef("TEMPISOLATE", aliases: ["HI", "ISOLATECATEGORY", "IC"], category: "View", summary: "Temporarily isolates element categories on the current level: every other category is hidden until UNISOLATEOBJECTS.") { ed in
            guard let c = try await ed.getString("Categories to keep (e.g. wall door window)") else { return }
            let keep = c.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            guard !keep.isEmpty, keep.allSatisfy({ k in categoryWords.contains { $0.caseInsensitiveCompare(k) == .orderedSame } }) else { throw CommandError.invalid("Use categories from: \(categoryWords.joined(separator: " ")).") }
            let others = categoryWords.filter { w in !keep.contains { $0.caseInsensitiveCompare(w) == .orderedSame } }
            ed.print("\(ViewRange.hideCategory(others, level: ed.doc.currentLevel, in: &ed.doc)) element(s) hidden; \(keep.joined(separator: ", ")) isolated.")
        }
    }

    static var geolocation: CommandDef {
        CommandDef("GEOLOCATION", aliases: ["GEOLOC", "LOCATION", "SITELOCATION"], category: "Manage", summary: "Project geolocation: City preset, or Set latitude, longitude, site elevation, time zone and true north (used by sun studies, energy and exports); List shows it.") { ed in
            let k = try await ed.getKeyword("Location option", ["City", "Set", "North", "List"], defaultValue: "List") ?? "List"
            switch k {
            case "City":
                guard let n = try await ed.getWord("City [\(SiteLocation.cities.map(\.name).joined(separator: "/"))]"), let c = SiteLocation.city(n) else { throw CommandError.invalid("Unknown city (use Set for coordinates).") }
                _ = SiteLocation.set(&ed.doc, latitude: c.latitude, longitude: c.longitude, elevation: c.elevation, timeZone: c.timeZone)
                ed.doc.info.address = ed.doc.info.address.isEmpty ? c.name : ed.doc.info.address
            case "Set":
                let lat = try await ed.getReal("Latitude (degrees, north positive)", defaultValue: ed.doc.info.latitude).value ?? ed.doc.info.latitude
                let lon = try await ed.getReal("Longitude (degrees, east positive)", defaultValue: ed.doc.info.longitude).value ?? ed.doc.info.longitude
                let el = try await ed.getReal("Site elevation above sea level (m)", defaultValue: ed.doc.info.elevation).value ?? ed.doc.info.elevation
                let tz = try await ed.getWord("Time zone (e.g. Europe/Bucharest, Enter = keep)", defaultValue: ed.doc.info.timeZone ?? "")
                if let e = SiteLocation.set(&ed.doc, latitude: lat, longitude: lon, elevation: el, timeZone: (tz ?? "").isEmpty ? nil : tz) { throw CommandError.invalid(e) }
            case "North":
                let a = try await ed.getReal("True north angle from project up (degrees, counter-clockwise)", defaultValue: ed.doc.info.northAngle).value ?? ed.doc.info.northAngle
                ed.doc.info.northAngle = a
            default: break
            }
            ed.print("Location: " + SiteLocation.describe(ed.doc) + ".")
        }
    }

    static var roofShape: CommandDef {
        CommandDef("ROOFSHAPE", aliases: ["ROOFFORM", "MANSARD", "GAMBREL", "DOMEROOF", "BARRELROOF"], category: "Architecture", summary: "Changes roofs into Mansard or Gambrel (two pitches with a break) forms, a Dome or a Barrel vault, or back to Plain.") { ed in
            let ids = try await ed.getSelection("Select roofs").filter { if case .roof? = ed.doc.element($0)?.geometry { return true }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("Select roofs.") }
            let k = try await ed.getKeyword("Roof form", ["Mansard", "Gambrel", "Dome", "Barrel", "Plain"], defaultValue: "Mansard") ?? "Mansard"
            var prof: RoofProfile? = nil
            var lower: Double? = nil
            switch k {
            case "Mansard", "Gambrel":
                lower = try await ed.getReal("Lower (steep) pitch in degrees", defaultValue: 60).value ?? 60
                let up = try await ed.getReal("Upper pitch in degrees", defaultValue: 20).value ?? 20
                let br = try await ed.getPositive("Break distance from the eave (plan)", defaultValue: 1200 / ed.doc.units.mm)
                guard (1...85).contains(lower!), (0...85).contains(up), up < lower! else { throw CommandError.invalid("Use an upper pitch below the lower one (1–85°).") }
                prof = RoofProfile(form: k == "Mansard" ? .mansard : .gambrel, upperPitch: up, breakDistance: br)
            case "Dome", "Barrel":
                lower = try await ed.getReal("Rise as a pitch (45° = half circle)", defaultValue: 45).value ?? 45
                guard (5...85).contains(lower!) else { throw CommandError.invalid("Use 5–85°.") }
                prof = RoofProfile(form: k == "Dome" ? .dome : .barrel)
            default: break
            }
            for id in ids {
                guard let i = ed.doc.elementIndex(id), case .roof(var r) = ed.doc.elements[i].geometry else { continue }
                r.profile = prof
                if let p = lower { r.pitch = p }
                if prof?.form == .mansard || prof?.form == .dome { r.kind = .hip } else if prof != nil { r.kind = .gable }
                ed.doc.elements[i].geometry = .roof(r)
            }
            ed.print("\(ids.count) roof(s) set to \(k.lowercased()).")
        }
    }

    static var escalator: CommandDef {
        CommandDef("ESCALATOR", aliases: ["ESCALATORS", "MOVINGSTAIR"], category: "Architecture", summary: "Places an escalator from its bottom comb in a travel direction up to the level above (30°/35°, step width 600/800/1000), checks EN 115 rise/inclination/speed rules and cuts the upper floor; Check re-validates existing escalators.") { ed in
            let u = 1 / ed.doc.units.mm
            let first = try await ed.getPoint("Specify bottom (comb) point of the escalator", keywords: ["Check"])
            if case .keyword = first {
                var n = 0
                for el in ed.doc.elements { if let issues = Escalators.check(el) {
                    n += 1
                    ed.print("#\(el.id) \(el.name): " + (issues.isEmpty ? "complies." : issues.joined(separator: " ")))
                    if let i = ed.doc.elementIndex(el.id) { ed.doc.elements[i].props["escalatorCheck"] = issues.isEmpty ? "OK" : issues.joined(separator: " ") }
                } }
                if n == 0 { ed.print("No escalators in the model.") }
                return
            }
            guard let p = first.point else { return }
            let dir = try await ed.getAngle("Specify travel direction (upwards)", base: p, defaultValue: .pi / 2).value ?? .pi / 2
            let lv = ed.doc.levels.sorted { $0.elevation < $1.elevation }
            let cur = ed.doc.level(ed.doc.currentLevel)
            let above = lv.first { $0.elevation > (cur?.elevation ?? 0) + 1e-6 }
            let defRise = above.map { $0.elevation - (cur?.elevation ?? 0) } ?? (cur?.height ?? 4000 * u)
            let rise = try await ed.getPositive("Rise", defaultValue: defRise)
            let ang = try await ed.getKeyword("Inclination", ["30", "35"], defaultValue: rise * ed.doc.units.mm <= 6000 ? "30" : "30") ?? "30"
            let sw = try await ed.getKeyword("Step width", ["600", "800", "1000"], defaultValue: "1000") ?? "1000"
            let speed = try await ed.getReal("Speed m/s", defaultValue: 0.5).value ?? 0.5
            let a = Double(ang) ?? 30, stepW = (Double(sw) ?? 1000) * u
            let issues = Escalators.check(rise: rise * ed.doc.units.mm, angleDeg: a, stepWidth: stepW * ed.doc.units.mm, speed: speed)
            let top = above.flatMap { l in abs(l.elevation - (cur?.elevation ?? 0) - rise) < 1e-6 * max(1, rise) ? l.id : nil }
            let r = Escalators.place(&ed.doc, start: p, direction: dir, rise: rise, angleDeg: a, stepWidth: stepW, level: ed.doc.currentLevel, topLevel: top, speed: speed)
            ed.selection = [r.escalator]
            let len = Escalators.length(rise: rise, angleDeg: a, landing: Escalators.defaultLanding * u)
            ed.print("Escalator #\(r.escalator): rise \(fmt(rise)), length \(fmt(len)), \(ang)°" + (r.opening != nil ? ", floor opening cut above." : ".")
                     + (issues.isEmpty ? " Complies with the rules." : " Warnings: " + issues.joined(separator: " ")))
        }
    }

    static var sectionObject: CommandDef {
        CommandDef("SECTIONOBJECT", aliases: ["SECTIONPLANEOBJ", "SPOBJECT", "SECTIONPLANES"], category: "3D", summary: "Section plane objects: Add a named vertical plane (its plan trace can be moved), make it Live (clips the 3D view with caps), Flip, Generate/update its 2D section block, Slice solids into closed halves, List, Off, Delete.") { ed in
            let k = try await ed.getKeyword("Section object option", ["Add", "Live", "Off", "Flip", "Generate", "Slice", "List", "Delete"], defaultValue: "Add") ?? "Add"
            @MainActor func pick() async throws -> SectionPlaneObjects.Plane {
                let planes = SectionPlaneObjects.all(ed.doc)
                guard !planes.isEmpty else { throw CommandError.invalid("No section plane objects (SECTIONOBJECT Add).") }
                if planes.count == 1 { return planes[0] }
                guard let n = try await ed.getWord("Section plane [\(planes.map(\.name).joined(separator: "/"))]", defaultValue: planes.last!.name),
                      let p = SectionPlaneObjects.named(n, ed.doc) ?? Int(n.drop { $0 == "#" }).flatMap({ id in planes.first { $0.id == id } }) else { throw CommandError.invalid("Unknown section plane.") }
                return p
            }
            switch k {
            case "Add":
                let a = try await ed.requirePoint("First point of the section line")
                let b = try await ed.requirePoint("Second point (the view looks to the left)", base: a) { c in [.line(LineGeom(a, c))] }
                let name = try await ed.getWord("Name", defaultValue: "SP\(SectionPlaneObjects.all(ed.doc).count + 1)")
                let model = try await ed.getYesNo("Include the building model in generated sections?", defaultValue: false)
                guard let id = SectionPlaneObjects.add(&ed.doc, name: name, a: a, b: b, includeModel: model) else { throw CommandError.invalid("The two points coincide.") }
                ed.selection = [id]
                ed.print("Section plane \(ed.doc.entity(id)?.props["sectionPlane"] ?? "") added (#\(id)).")
            case "Live":
                let p = try await pick()
                SectionPlaneObjects.setLive(&ed.doc, p.id)
                ed.print("\(p.name) is live: the 3D view is cut and capped along it.")
            case "Off":
                SectionPlaneObjects.setLive(&ed.doc, nil)
                ed.print("Live sectioning off.")
            case "Flip":
                let p = try await pick()
                SectionPlaneObjects.flip(&ed.doc, p.id)
                var d = ed.doc; SectionPlaneObjects.updateAll(&d); ed.doc = d
                ed.print("\(p.name) flipped.")
            case "Generate":
                let p = try await pick()
                guard let bn = SectionPlaneObjects.generate(&ed.doc, p.id) else { throw CommandError.invalid("The plane does not cut or see any solid.") }
                if !ed.doc.entities.contains(where: { if case .insert(let ins) = $0.geometry { return ins.block == bn }; return false }) {
                    let at = try await ed.requirePoint("Specify lower-left corner of the section drawing")
                    ed.doc.ensureLayer("A-VIEW")
                    ed.doc.add(.insert(InsertGeom(block: bn, position: at)), layer: "A-VIEW")
                }
                ed.print("\(bn) generated (\(ed.doc.blocks[bn]?.entities.count ?? 0) objects); it follows the plane when it moves.")
            case "Slice":
                let p = try await pick()
                var ids = try await ed.getSelection("Select solids to cut (Enter = all)")
                ids = ids.filter { if case .solid? = ed.doc.entity($0)?.geometry { return true }; return false }
                if ids.isEmpty { ids = ed.doc.entities.compactMap { if case .solid = $0.geometry { return $0.id }; return nil } }
                let n = SectionPlaneObjects.slice(&ed.doc, p.id, solids: ids)
                ed.selection = []
                ed.print("\(n.count) solid(s) cut by \(p.name).")
            case "Delete":
                let p = try await pick()
                if p.live { SectionPlaneObjects.setLive(&ed.doc, nil) }
                ed.doc.remove(ids: [p.id])
                ed.print("\(p.name) deleted" + (p.block.map { " (block \($0) kept)" } ?? "") + ".")
            default:
                let planes = SectionPlaneObjects.all(ed.doc)
                if planes.isEmpty { ed.print("No section plane objects.") }
                for p in planes {
                    ed.print("\(p.name) #\(p.id): \(fmt(p.a.x)),\(fmt(p.a.y)) → \(fmt(p.b.x)),\(fmt(p.b.y))" + (p.live ? "  LIVE" : "") + (p.block.map { "  block \($0)" } ?? ""))
                }
            }
        }
    }
}
