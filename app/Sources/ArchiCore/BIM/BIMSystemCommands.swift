// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for MEP systems, lighting fixtures, area schemes, associative grid dimensions, the family editor
// (families, profiles, door/window builder), view templates, legends, drafting views and view graphics.
import Foundation

enum BIMSystemCommands {
    static var all: [CommandDef] {
        [mepSystem, lightData, lightSchedule, areaScheme, autoDimGrids, bimUpdate, family, profile, viewTemplate, legend, draftingView, viewGraphics]
    }

    static func isComponent(_ g: BIMGeometry) -> Bool { if case .component = g { return true }; return false }

    // MARK: MEP systems

    static var mepSystem: CommandDef {
        CommandDef("MEPSYSTEM", aliases: ["SYSTEMS", "MEPSYSTEMS", "SYSTEMBROWSER"], category: "MEP", summary: "Connector-based systems: list connected networks, assign a system to a whole network, show only some systems, or check open ends.") { ed in
            let k = try await ed.getKeyword("System option", ["List", "Assign", "Show", "All", "Check"], defaultValue: "List") ?? "List"
            let m = ed.doc.units.mm / 1000
            switch k {
            case "Assign":
                guard case .pick(let pk) = try await ed.pickObject("Select a pipe, duct or fixture of the network", filter: { id in ed.doc.element(id).map { isComponent($0.geometry) } ?? false }) else { return }
                let codes = RunFamilies.systems.map(\.code)
                guard let s = try await ed.getWord("System [\(codes.joined(separator: "/"))]", defaultValue: "DCW"), codes.contains(s.uppercased()) else { throw CommandError.invalid("Unknown system.") }
                let n = MEPNetworks.assign(s, toNetworkOf: pk.id, doc: &ed.doc)
                ed.print("\(n) run(s) of the network set to \(s.uppercased()).")
            case "Show":
                guard let s = try await ed.getWord("Systems to show (e.g. DCW|SAN)", defaultValue: ed.doc.variable(MEPSystemFilter.variable) ?? "DCW") else { return }
                ed.doc.setVariable(MEPSystemFilter.variable, s.uppercased().replacingOccurrences(of: ",", with: "|"))
                ed.print("Showing systems \(s.uppercased()) only (MEPSYSTEM All shows everything).")
            case "All":
                ed.doc.variables[MEPSystemFilter.variable] = nil
                ed.print("All systems shown.")
            case "Check":
                let nets = MEPNetworks.networks(doc: ed.doc)
                var issues = 0
                for (i, n) in nets.enumerated() {
                    if !n.mismatched.isEmpty { ed.print("N\(i + 1) (\(n.system)): runs with another system: " + n.mismatched.map { "#\($0)" }.joined(separator: ", ")); issues += 1 }
                    if !n.openEnds.isEmpty { ed.print("N\(i + 1) (\(n.system)): \(n.openEnds.count) open end(s)"); issues += 1 }
                    if n.system.isEmpty { ed.print("N\(i + 1): no system assigned"); issues += 1 }
                }
                ed.print(issues == 0 ? "All networks are connected and consistent." : "\(issues) issue(s).")
            default:
                let nets = MEPNetworks.networks(doc: ed.doc)
                if nets.isEmpty { ed.print("No MEP runs."); return }
                for (i, n) in nets.enumerated() {
                    ed.print("N\(i + 1)  \(n.system.isEmpty ? "—" : n.system)  \(n.runs.count) run(s), \(n.fixtures.count) fixture(s), \(String(format: "%.2f", n.length * m)) m, \(n.openEnds.count) open end(s)")
                }
            }
        }
    }

    // MARK: Lighting

    static var lightData: CommandDef {
        CommandDef("LIGHTDATA", aliases: ["PHOTOMETRY", "LUMINAIRE", "LIGHTFIXTURE"], category: "MEP", summary: "Sets photometric data of light fixtures (lumens, watts, colour temperature, beam angle) used by schedules and rendering.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select light fixtures", isComponent).filter { ed.doc.element($0).map(LightingFixtures.isLight) ?? false }
            guard let first = ids.first.flatMap({ ed.doc.element($0) }) else { throw CommandError.invalid("Select light fixtures (Lighting components).") }
            let ph = LightingFixtures.photometry(first)
            let lm = try await ed.getReal("Luminous flux (lm)", defaultValue: ph.lumens).value ?? ph.lumens
            let w = try await ed.getReal("Power (W)", defaultValue: ph.watts).value ?? ph.watts
            let k = try await ed.getReal("Colour temperature (K)", defaultValue: ph.cct).value ?? ph.cct
            let beam = try await ed.getReal("Beam angle (°)", defaultValue: ph.beamAngle).value ?? ph.beamAngle
            guard lm >= 0, w >= 0, k >= 1000, k <= 20000, beam > 0, beam <= 360 else { throw CommandError.invalid("Values out of range.") }
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                ed.doc.elements[i].props["lumens"] = fmt(lm); ed.doc.elements[i].props["watts"] = fmt(w)
                ed.doc.elements[i].props["cct"] = fmt(k); ed.doc.elements[i].props["beamAngle"] = fmt(beam)
            }
            ed.selection = []
            ed.print("Photometry set on \(ids.count) fixture(s): \(fmt(lm)) lm, \(fmt(w)) W (\(fmt(w > 0 ? lm / w : 0, 1)) lm/W), \(fmt(k)) K.")
        }
    }

    static var lightSchedule: CommandDef {
        CommandDef("LIGHTSCHEDULE", aliases: ["FIXTURESCHEDULE", "LIGHTINGSCHEDULE", "LUX"], category: "MEP", summary: "Lighting fixture schedule (mark, type, level, room, position, rotation, lm, W, K) and average illuminance per room.", modifies: false) { ed in
            let rows = LightingFixtures.scheduleRows(doc: ed.doc)
            for r in rows { ed.print(r.joined(separator: "\t")) }
            for r in LightingFixtures.roomIlluminance(doc: ed.doc) where r.fixtures > 0 {
                ed.print("\(r.name): \(fmt(r.lux, 0)) lx average (\(r.fixtures) fixture(s), \(fmt(r.wattsPerM2, 1)) W/m²)")
            }
        }
    }

    // MARK: Area schemes

    static var areaScheme: CommandDef {
        CommandDef("AREASCHEME", aliases: ["AREASCHEMES", "GIA", "NIA", "GEA", "DIN277"], category: "Architecture", summary: "Area schemes (GEA, GIA, NIA, DIN 277 BGF/NRF, Gross, Rentable): places associative area boundaries that follow the walls, lists schemes and reports totals.") { ed in
            let k = try await ed.getKeyword("Area scheme option", ["Place", "List", "Report", "Update"], defaultValue: "Place") ?? "Place"
            let m2 = pow(ed.doc.units.mm, 2) / 1e6
            switch k {
            case "List":
                for s in AreaSchemes.standard { ed.print("\(s.code)  \(s.name) (\(s.standard)): measured to \(s.rule == .exterior ? "the outside face of external walls" : s.rule == .interior ? "the inside face of external walls" : "room faces")") }
            case "Report":
                let t = AreaSchemes.totals(doc: ed.doc)
                if t.isEmpty { ed.print("No area boundaries.") }
                for r in t { ed.print("\(r.scheme): \(String(format: "%.2f", r.area * m2)) m² (\(r.count) boundary/ies)") }
            case "Update":
                var d = ed.doc
                let changed = AreaSchemes.updateAll(&d)
                ed.doc = d
                ed.print(changed ? "Area boundaries updated from the walls." : "Area boundaries are up to date.")
            default:
                let code = try await ed.getWord("Scheme [GEA/GIA/NIA/BGF/NRF/Gross/Rentable]", defaultValue: ed.doc.variable("AREASCHEME") ?? "GIA") ?? "GIA"
                let s = AreaSchemes.scheme(code)
                ed.doc.setVariable("AREASCHEME", s.code)
                var n = 0
                while true {
                    guard let p = try await ed.getPoint("Pick inside the building / room for \(s.code) (Enter to finish)").point else { break }
                    guard let id = AreaSchemes.create(s, at: p, doc: &ed.doc, level: ed.doc.currentLevel), case .space(let g)? = ed.doc.element(id)?.geometry else {
                        ed.print("No enclosing walls there."); continue
                    }
                    ed.print("\(s.code): \(String(format: "%.2f", abs(GeometryOps.signedArea(g.boundary)) * m2)) m²")
                    n += 1
                }
                if n > 0 { ed.print("\(n) \(s.code) boundary/ies placed; they follow wall changes.") }
            }
        }
    }

    // MARK: Associative dimensions and updates

    static var autoDimGrids: CommandDef {
        CommandDef("AUTODIMGRIDS", aliases: ["GRIDDIMS", "DIMGRIDS"], category: "Annotate", summary: "Associative dimension string across parallel grid lines (bay dimensions and overall), updated when grids move.") { ed in
            var ids = try await ArchitectureCommands.elements(ed, "Select grid lines (Enter = all)", { if case .gridLine = $0 { return true }; return false })
            if ids.isEmpty { ids = ed.doc.elements.filter { if case .gridLine = $0.geometry { return true }; return false }.map(\.id) }
            let off = try await ed.getPositive("Offset beyond the grid heads", defaultValue: ed.variableDouble("GRIDDIMOFFSET", 1500 / ed.doc.units.mm))
            ed.doc.setVariable("GRIDDIMOFFSET", fmt(off))
            // Group parallel grids by direction.
            var groups: [[EntityID]] = []
            for id in ids {
                guard case .gridLine(let g)? = ed.doc.element(id)?.geometry, g.start.distance(to: g.end) > 1e-9 else { continue }
                let d = (g.end - g.start).normalized
                if let i = groups.firstIndex(where: { grp in
                    if case .gridLine(let h)? = ed.doc.element(grp[0])?.geometry { return abs((h.end - h.start).normalized.cross(d)) < 0.02 }; return false }) { groups[i].append(id) }
                else { groups.append([id]) }
            }
            var n = 0
            for grp in groups where grp.count >= 2 {
                let key = grp.map(String.init).joined(separator: ",")
                for (k, d) in AutoDimensions.gridChain(doc: ed.doc, grids: grp, offset: off).enumerated() {
                    var dg = d; dg.style = ed.doc.currentDimStyle
                    let id = ed.addEntity(.dimension(dg), layer: "A-ANNO-DIMS")
                    if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["autoDimGrids"] = key; ed.doc.entities[i].props["autoDimIdx"] = "\(k)"; ed.doc.entities[i].props["autoDimOffset"] = fmt(off, 6) }
                    n += 1
                }
            }
            ed.selection = []
            ed.print("\(n) grid dimension(s) placed.")
        }
    }

    static var bimUpdate: CommandDef {
        CommandDef("BIMUPDATE", aliases: ["REGENASSOC", "UPDATEASSOCIATIVE"], category: "Architecture", summary: "Regenerates associative content: area boundaries, automatic dimensions, associative sweeps and family instances.") { ed in
            var d = ed.doc
            let changed = BIMUpdaters.run(&d)
            ed.doc = d
            ed.print(changed ? "Associative content regenerated." : "Everything is up to date.")
        }
    }

    // MARK: Family editor

    static var family: CommandDef {
        CommandDef("FAMILY", aliases: ["FAMILYEDIT", "FAMILIES", "FAM"], category: "Architecture", summary: "Family editor: new family, parameters and formulas, forms (box, cylinder, extrusion, sweep, revolve, void, nested, arrays), types, place instances, set instance values, flex, door/window builder, assign to openings.") { ed in
            let k = try await ed.getKeyword("Family option", ["New", "Param", "Form", "Profile", "Type", "Place", "Set", "Flex", "Builder", "Assign", "List", "Delete"], defaultValue: "List") ?? "List"
            @MainActor func pickFamily(_ msg: String) async throws -> Int {
                let names = ed.doc.families.map(\.name)
                guard !names.isEmpty else { throw CommandError.invalid("No families in this document (FAMILY New or Builder).") }
                guard let n = try await ed.getWord("\(msg) [\(names.joined(separator: "/"))]", defaultValue: ed.doc.variable("CURRENTFAMILY") ?? names.last), let i = ed.doc.familyIndex(n) else { throw CommandError.invalid("Unknown family.") }
                ed.doc.setVariable("CURRENTFAMILY", ed.doc.families[i].name)
                return i
            }
            switch k {
            case "New":
                guard let n = try await ed.getWord("Family name"), !n.isEmpty else { return }
                guard ed.doc.family(named: n) == nil else { throw CommandError.invalid("\(n) already exists.") }
                let cat = try await ed.getKeyword("Category", ["Generic", "Furniture", "Casework", "Lighting", "Door", "Window", "Profile"], defaultValue: "Generic") ?? "Generic"
                ed.doc.families.append(FamilyDefinition(name: n, category: cat == "Generic" ? "Generic Model" : cat,
                                                        parameters: [FamilyParameter("Width", value: "600"), FamilyParameter("Depth", value: "600"), FamilyParameter("Height", value: "750")]))
                ed.doc.setVariable("CURRENTFAMILY", n)
                ed.print("Family \(n) created with Width, Depth, Height parameters.")
            case "Param":
                let i = try await pickFamily("Family")
                guard let pn = try await ed.getWord("Parameter name"), !pn.isEmpty, pn.first!.isLetter else { throw CommandError.invalid("Names start with a letter.") }
                let kind = try await ed.getKeyword("Type", ["Length", "Angle", "Number", "Integer", "YesNo", "Text", "Material"], defaultValue: "Length") ?? "Length"
                let pk = FamilyParameterKind(rawValue: kind == "YesNo" ? "yesNo" : kind.lowercased()) ?? .length
                let v = try await ed.getString("Value or =formula", defaultValue: ed.doc.families[i].parameter(pn)?.value ?? "0") ?? "0"
                var p = FamilyParameter(pn, pk, value: v.hasPrefix("=") ? "0" : v, formula: v.hasPrefix("=") ? String(v.dropFirst()) : nil)
                p.instance = try await ed.getYesNo("Instance parameter?", defaultValue: true)
                if let j = ed.doc.families[i].parameters.firstIndex(where: { $0.name.caseInsensitiveCompare(pn) == .orderedSame }) { ed.doc.families[i].parameters[j] = p }
                else { ed.doc.families[i].parameters.append(p) }
                let r = FamilyExpr.resolve(ed.doc.families[i])
                ed.print("\(pn) = \(r.values[pn.lowercased()].map { fmt($0, 3) } ?? r.text[pn.lowercased()] ?? v)" + (r.errors.isEmpty ? "" : "  (" + r.errors.joined(separator: "; ") + ")"))
            case "Form":
                let i = try await pickFamily("Family")
                let kind = try await ed.getKeyword("Form", ["Box", "Cylinder", "Extrusion", "Sweep", "Revolve", "Nested"], defaultValue: "Box") ?? "Box"
                var f = FamilyForm(FamilyFormKind(rawValue: kind.lowercased()) ?? .box, name: "\(kind) \(ed.doc.families[i].forms.count + 1)")
                f.x = try await ed.getString("X (expression)", defaultValue: "0") ?? "0"
                f.y = try await ed.getString("Y (expression)", defaultValue: "0") ?? "0"
                f.z = try await ed.getString("Z (expression)", defaultValue: "0") ?? "0"
                switch f.kind {
                case .box:
                    for d in ["width", "depth", "height"] { f.dims[d] = try await ed.getString("\(d.capitalized) (expression)", defaultValue: d.capitalized) ?? d.capitalized }
                case .cylinder:
                    f.dims["radius"] = try await ed.getString("Radius (expression)", defaultValue: "Width/2") ?? "Width/2"
                    f.dims["height"] = try await ed.getString("Height (expression)", defaultValue: "Height") ?? "Height"
                case .extrusion, .revolve, .sweep:
                    f.profile = try await ed.getWord("Profile name (family profile or library)", defaultValue: ed.doc.families[i].profiles.first?.name ?? "rect")
                    if f.kind == .extrusion {
                        f.dims["height"] = try await ed.getString("Extrusion height (expression)", defaultValue: "Height") ?? "Height"
                        f.dims["width"] = try await ed.getString("Library profile width (expression)", defaultValue: "Width") ?? "Width"
                        f.dims["depth"] = try await ed.getString("Library profile depth (expression)", defaultValue: "Depth") ?? "Depth"
                    } else if f.kind == .revolve {
                        f.dims["angle"] = try await ed.getString("Angle in degrees (expression)", defaultValue: "360") ?? "360"
                    } else {
                        f.dims["width"] = try await ed.getString("Profile width (expression)", defaultValue: "50") ?? "50"
                        f.dims["height"] = try await ed.getString("Profile height (expression)", defaultValue: "50") ?? "50"
                        while true {
                            guard let pt = try await ed.getString("Path point \(f.path.count + 1) as x;y;z expressions (Enter when done)"), !pt.isEmpty else { break }
                            f.path.append(pt.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) })
                        }
                    }
                case .nested:
                    f.family = try await ed.getWord("Nested family name")
                    while true {
                        guard let b = try await ed.getString("Binding Param=expression (Enter when done)"), let eq = b.firstIndex(of: "=") else { break }
                        f.dims[String(b[..<eq]).trimmingCharacters(in: .whitespaces)] = String(b[b.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    }
                }
                f.void = try await ed.getYesNo("Void (cuts the other forms)?", defaultValue: false)
                if !f.void { f.material = try await ed.getWord("Material (or =Param)", defaultValue: "Wood") }
                let vis = try await ed.getString("Visible when (expression, Enter = always)", defaultValue: "") ?? ""
                f.visible = vis.isEmpty ? nil : vis
                let cnt = try await ed.getString("Array count (expression, Enter = 1)", defaultValue: "") ?? ""
                if !cnt.isEmpty {
                    f.arrayCount = cnt
                    f.arrayDX = try await ed.getString("Array step X", defaultValue: "0"); f.arrayDY = try await ed.getString("Array step Y", defaultValue: "0"); f.arrayDZ = try await ed.getString("Array step Z", defaultValue: "0")
                }
                ed.doc.families[i].forms.append(f)
                let r = FamilyEngine.evaluate(ed.doc.families[i], doc: ed.doc)
                ed.print("\(f.name) added." + (r.errors.isEmpty ? "" : " Warnings: " + r.errors.joined(separator: "; ")))
            case "Profile":
                let i = try await pickFamily("Family")
                guard let pn = try await ed.getWord("Profile name"), !pn.isEmpty else { return }
                var pts: [[String]] = []
                while true {
                    guard let pt = try await ed.getString("Vertex \(pts.count + 1) as x;y expressions (Enter when done)"), !pt.isEmpty else { break }
                    let c = pt.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                    if c.count >= 2 { pts.append(Array(c.prefix(2))) }
                }
                guard pts.count >= 3 else { throw CommandError.invalid("A profile needs at least three vertices.") }
                ed.doc.families[i].profiles.removeAll { $0.name.caseInsensitiveCompare(pn) == .orderedSame }
                ed.doc.families[i].profiles.append(FamilyProfile(name: pn, points: pts))
                ed.print("Profile \(pn) with \(pts.count) vertices added.")
            case "Type":
                let i = try await pickFamily("Family")
                guard let tn = try await ed.getWord("Type name"), !tn.isEmpty else { return }
                var vals: [String: String] = ed.doc.families[i].types[tn] ?? [:]
                while true {
                    guard let b = try await ed.getString("Param=value (Enter when done)"), let eq = b.firstIndex(of: "=") else { break }
                    vals[String(b[..<eq]).trimmingCharacters(in: .whitespaces)] = String(b[b.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                }
                ed.doc.families[i].types[tn] = vals
                ed.print("Type \(tn): " + vals.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            case "Place":
                let i = try await pickFamily("Family")
                let def = ed.doc.families[i]
                let tn = def.types.isEmpty ? nil : try await ed.getWord("Type [\(def.types.keys.sorted().joined(separator: "/"))]", defaultValue: def.types.keys.sorted().first)
                var n = 0
                while true {
                    guard let p = try await ed.getPoint("Specify insertion point (Enter to finish)").point else { break }
                    let r = try await ed.getAngle("Rotation", base: p, defaultValue: 0).value ?? 0
                    let b = FamilyEngine.evaluate(def, doc: ed.doc, props: tn.map { ["familyType": $0] } ?? [:]).bounds
                    let size = b.isEmpty ? Vec3(1, 1, 1) : Vec3(b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z)
                    let id = ed.doc.addElement(.component(ComponentGeom(category: def.category, position: p, rotation: r, size: size, family: def.name)), material: nil, name: def.name)
                    if let t = tn, let j = ed.doc.elementIndex(id) { ed.doc.elements[j].props["familyType"] = t }
                    n += 1
                }
                ed.print("\(n) instance(s) of \(def.name) placed.")
            case "Set":
                guard case .pick(let pk) = try await ed.pickObject("Select a family instance", filter: { id in
                    guard let el = ed.doc.element(id) else { return false }
                    if case .component(let g) = el.geometry, ed.doc.family(named: g.family) != nil { return true }
                    return el.props["family"].flatMap { ed.doc.family(named: $0) } != nil }), let el = ed.doc.element(pk.id) else { return }
                var fname = el.props["family"]
                if case .component(let g) = el.geometry { fname = g.family }
                guard let def = ed.doc.family(named: fname) else { return }
                let names = def.parameters.filter { $0.instance && $0.formula == nil }.map(\.name)
                guard let pn = try await ed.getWord("Parameter [\(names.joined(separator: "/"))/Type]"), !pn.isEmpty else { return }
                guard let j = ed.doc.elementIndex(pk.id) else { return }
                if pn.caseInsensitiveCompare("Type") == .orderedSame {
                    let t = try await ed.getWord("Type [\(def.types.keys.sorted().joined(separator: "/"))]")
                    ed.doc.elements[j].props["familyType"] = (t ?? "").isEmpty ? nil : t
                } else {
                    guard let p = def.parameter(pn), p.instance, p.formula == nil else { throw CommandError.invalid("\(pn) is not an instance parameter.") }
                    let cur = ed.doc.elements[j].props["fp." + p.name] ?? p.value
                    guard let v = try await ed.getString("\(p.name)", defaultValue: cur) else { return }
                    ed.doc.elements[j].props["fp." + p.name] = v
                }
                var d = ed.doc; FamilyInstances.updateAll(&d); ed.doc = d
                ed.print("Instance #\(pk.id) updated.")
            case "Flex":
                let i = try await pickFamily("Family")
                var ov: [String: String] = [:]
                while true {
                    guard let b = try await ed.getString("Param=value to test (Enter to evaluate)"), let eq = b.firstIndex(of: "=") else { break }
                    ov[String(b[..<eq]).trimmingCharacters(in: .whitespaces)] = String(b[b.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                }
                let props = Dictionary(uniqueKeysWithValues: ov.map { ("fp." + $0.key, $0.value) })
                let r = FamilyEngine.evaluate(ed.doc.families[i], doc: ed.doc, props: props)
                let res = FamilyExpr.resolve(ed.doc.families[i], overrides: ov)
                for p in ed.doc.families[i].parameters { ed.print("  \(p.name) = " + (res.values[p.name.lowercased()].map { fmt($0, 3) } ?? res.text[p.name.lowercased()] ?? "?")) }
                let b = r.bounds
                ed.print(b.isEmpty ? "No geometry." : "Size \(fmt(b.max.x - b.min.x)) × \(fmt(b.max.y - b.min.y)) × \(fmt(b.max.z - b.min.z)).")
                if !r.errors.isEmpty { ed.print("Errors: " + r.errors.joined(separator: "; ")) }
            case "Builder":
                let kind = try await ed.getKeyword("Build a", ["Door", "Window"], defaultValue: "Door") ?? "Door"
                let styles = kind == "Door" ? FamilyTemplates.doorStyles : FamilyTemplates.windowStyles
                let st = try await ed.getKeyword("Style", styles, defaultValue: styles[0]) ?? styles[0]
                guard let n = try await ed.getWord("Family name", defaultValue: "\(st) \(kind)"), !n.isEmpty else { return }
                let w = try await ed.getReal("Width (mm)", defaultValue: kind == "Door" ? 900 : 1200).value ?? 900
                let h = try await ed.getReal("Height (mm)", defaultValue: kind == "Door" ? 2100 : 1200).value ?? 2100
                var def: FamilyDefinition
                if kind == "Door" { def = FamilyTemplates.door(name: n, style: st, width: w, height: h) }
                else {
                    let c = try await ed.getInteger("Columns of lights", defaultValue: 2) ?? 2
                    let r = try await ed.getInteger("Rows of lights", defaultValue: 1) ?? 1
                    def = FamilyTemplates.window(name: n, style: st, width: w, height: h, columns: c, rows: r)
                }
                if let i = ed.doc.familyIndex(n) { ed.doc.families[i] = def } else { ed.doc.families.append(def) }
                ed.doc.setVariable("CURRENTFAMILY", n)
                ed.print("\(kind) family \(n) built (\(def.parameters.count) parameters, \(def.forms.count) forms). FAMILY Assign puts it in doors/windows.")
            case "Assign":
                let i = try await pickFamily("Door/window family")
                let ids = try await ArchitectureCommands.elements(ed, "Select doors/windows", ArchitectureCommands.isOpening)
                for id in ids { if let j = ed.doc.elementIndex(id) { ed.doc.elements[j].props["family"] = ed.doc.families[i].name } }
                ed.selection = []
                ed.print("\(ed.doc.families[i].name) assigned to \(ids.count) opening(s); they flex with the opening size.")
            case "Delete":
                let i = try await pickFamily("Family")
                let n = ed.doc.families[i].name
                let used = FamilyInstances.count(n, doc: ed.doc)
                guard used == 0 else { throw CommandError.invalid("\(n) has \(used) instance(s).") }
                ed.doc.families.remove(at: i); ed.print("\(n) deleted.")
            default:
                if ed.doc.families.isEmpty { ed.print("No families."); return }
                for f in ed.doc.families {
                    ed.print("\(f.name) [\(f.category)] \(f.parameters.count) parameter(s), \(f.forms.count) form(s), \(f.profiles.count) profile(s), \(f.types.count) type(s), \(FamilyInstances.count(f.name, doc: ed.doc)) instance(s)")
                }
            }
        }
    }

    static var profile: CommandDef {
        CommandDef("PROFILE", aliases: ["PROFILES", "PROFILEFAMILY"], category: "Architecture", summary: "Profile families for sweeps, handrails, gutters and mullions: list, create from a closed polyline (flexes with Width/Height), or delete.") { ed in
            let k = try await ed.getKeyword("Profile option", ["List", "New", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "New":
                guard case .pick(let pk) = try await ed.pickObject("Select a closed polyline", filter: { ModelingCommands.loop(ed.doc, $0) != nil }), let loop = ModelingCommands.loop(ed.doc, pk.id) else { return }
                guard let n = try await ed.getWord("Profile name"), !n.isEmpty else { return }
                guard !ProfileLibrary.isBuiltin(n), ed.doc.family(named: n) == nil else { throw CommandError.invalid("\(n) already exists.") }
                let b = BBox2(points: loop)
                ed.doc.families.append(FamilyTemplates.profile(name: n, points: loop, width: b.width * ed.doc.units.mm, height: b.height * ed.doc.units.mm))
                ed.print("Profile family \(n) (\(fmt(b.width * ed.doc.units.mm)) × \(fmt(b.height * ed.doc.units.mm)) mm) created.")
            case "Delete":
                guard let n = try await ed.getWord("Profile name"), let i = ed.doc.familyIndex(n), ed.doc.families[i].category == "Profile" else { throw CommandError.invalid("No such profile family.") }
                ed.doc.families.remove(at: i); ed.print("\(n) deleted.")
            default:
                for n in ProfileLibrary.names(ed.doc) { ed.print("  " + n + (ProfileLibrary.isBuiltin(n) ? "  (" + (ProfileLibrary.builtins.first { $0.name == n }?.use ?? "") + ")" : "  (family)")) }
            }
        }
    }

    // MARK: Views

    static var viewTemplate: CommandDef {
        CommandDef("VIEWTEMPLATE", aliases: ["VIEWTEMPLATES", "VT"], category: "View", summary: "View templates: list, apply to the current view, capture the current settings as a template, set a template value, apply to a placed drawing view, or delete.") { ed in
            let k = try await ed.getKeyword("View template option", ["List", "Apply", "None", "Capture", "Set", "View", "Delete"], defaultValue: "List") ?? "List"
            let names = ed.doc.viewTemplates.map(\.name)
            switch k {
            case "Apply":
                guard let n = try await ed.getWord("Template [\(names.joined(separator: "/"))]", defaultValue: names.first), let t = ed.doc.viewTemplate(n) else { throw CommandError.invalid("Unknown template.") }
                ed.doc.setVariable(ViewTemplates.variable, t.name)
                ed.print("View template \(t.name) applied to the model view.")
            case "None":
                ed.doc.variables[ViewTemplates.variable] = nil; ed.print("No view template.")
            case "Capture":
                guard let n = try await ed.getWord("Template name"), !n.isEmpty else { return }
                ViewTemplates.save(ViewTemplate.capture(n, from: ed.doc), doc: &ed.doc)
                ed.print("Template \(n) saved (\(ed.doc.viewTemplate(n)?.settings.count ?? 0) settings).")
            case "Set":
                guard let n = try await ed.getWord("Template [\(names.joined(separator: "/"))]", defaultValue: names.first), let i = ed.doc.viewTemplates.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Unknown template.") }
                guard let key = try await ed.getWord("Setting [\(ViewTemplate.keys.joined(separator: "/"))/HIDELAYER/SHOWLAYER]") else { return }
                let K = key.uppercased()
                if K == "HIDELAYER" || K == "SHOWLAYER" {
                    guard let l = try await ed.getWord("Layer name") else { return }
                    ed.doc.viewTemplates[i].hiddenLayers.removeAll { $0.caseInsensitiveCompare(l) == .orderedSame }
                    if K == "HIDELAYER" { ed.doc.viewTemplates[i].hiddenLayers.append(l) }
                } else {
                    let v = try await ed.getString("Value (Enter = remove)", defaultValue: ed.doc.viewTemplates[i].settings[K] ?? "") ?? ""
                    ed.doc.viewTemplates[i].settings[K] = v.isEmpty ? nil : v
                }
                ed.print("\(ed.doc.viewTemplates[i].name) updated.")
            case "View":
                guard case .pick(let pk) = try await ed.pickObject("Select a placed drawing view", filter: { ed.doc.entity($0)?.props["view"] != nil }), let e = ed.doc.entity(pk.id), let spec = e.props["view"] else { return }
                let n = try await ed.getWord("Template [\(names.joined(separator: "/"))/None]", defaultValue: names.first) ?? "None"
                let base = ViewTemplates.split(spec).spec
                let ns = n.caseInsensitiveCompare("None") == .orderedSame ? base : base + "|template=" + (ed.doc.viewTemplate(n)?.name ?? n)
                guard ArchitectureCommands.buildViewBlock(&ed.doc, spec: ns) != nil, let i = ed.doc.entityIndex(pk.id) else { throw CommandError.invalid("That view cannot be regenerated.") }
                ed.doc.entities[i].props["view"] = ns
                ed.print("View regenerated with template \(n).")
            case "Delete":
                guard let n = try await ed.getWord("Template"), let i = ed.doc.viewTemplates.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
                ed.doc.viewTemplates.remove(at: i)
                if ed.doc.variable(ViewTemplates.variable)?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.variables[ViewTemplates.variable] = nil }
                ed.print("\(n) deleted.")
            default:
                for t in ed.doc.viewTemplates {
                    ed.print("\(t.name): " + t.settings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") + (t.hiddenLayers.isEmpty ? "" : "; hides " + t.hiddenLayers.joined(separator: ", ")))
                }
            }
        }
    }

    static var legend: CommandDef {
        CommandDef("LEGEND", aliases: ["LEGENDS", "LEGENDVIEW", "BUILDUPLEGEND"], category: "View", summary: "Places a legend view: wall types, door/window types, floor/roof build-ups, components or materials (VIEWUPDATE refreshes it).") { ed in
            let k = try await ed.getKeyword("Legend", ["Walls", "Openings", "Slabs", "Components", "Materials"], defaultValue: "Walls") ?? "Walls"
            guard let name = Legends.makeBlock(&ed.doc, kind: k.lowercased()) else { throw CommandError.invalid("Nothing to show in that legend.") }
            let p = try await ed.requirePoint("Specify lower-left corner of the legend")
            ed.doc.ensureLayer("A-VIEW")
            let id = ed.doc.add(.insert(InsertGeom(block: name, position: p)), layer: "A-VIEW")
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = "legend:" + k.lowercased() }
            ed.print("\(name) placed (\(ed.doc.blocks[name]?.entities.count ?? 0) objects).")
        }
    }

    static var draftingView: CommandDef {
        CommandDef("DRAFTINGVIEW", aliases: ["DRAFTING", "DRAFTVIEW", "DETAILVIEW2D"], category: "View", summary: "Drafting views (2D only, not tied to the model): new, edit in isolation, close (store), place in the drawing, list.") { ed in
            let editing = ed.doc.variable(DraftingViews.editing)
            let k = try await ed.getKeyword("Drafting view option", ["New", "Edit", "Close", "Place", "List"], defaultValue: editing != nil ? "Close" : "List") ?? "List"
            switch k {
            case "New", "Edit":
                guard editing == nil else { throw CommandError.invalid("Close the drafting view \(editing!) first.") }
                guard let n = try await ed.getWord("Drafting view name", defaultValue: DraftingViews.names(ed.doc).first), !n.isEmpty else { return }
                if k == "New" && !DraftingViews.create(n, doc: &ed.doc) { throw CommandError.invalid("\(n) already exists.") }
                if k == "Edit" && ed.doc.blocks[DraftingViews.blockName(n)] == nil { throw CommandError.invalid("No drafting view \(n).") }
                _ = DraftingViews.beginEdit(n, doc: &ed.doc)
                ed.print("Editing drafting view \(n): only its 2D content is shown. DRAFTINGVIEW Close stores it.")
            case "Close":
                guard editing != nil else { ed.print("No drafting view is being edited."); return }
                let n = DraftingViews.endEdit(doc: &ed.doc)
                ed.print("Drafting view \(editing!) stored (\(n) object(s)).")
            case "Place":
                let names = DraftingViews.names(ed.doc)
                guard !names.isEmpty else { throw CommandError.invalid("No drafting views.") }
                guard let n = try await ed.getWord("Drafting view [\(names.joined(separator: "/"))]", defaultValue: names.first), ed.doc.blocks[DraftingViews.blockName(n)] != nil else { throw CommandError.invalid("Unknown drafting view.") }
                let p = try await ed.requirePoint("Specify insertion point")
                let sc = try await ed.getReal("Scale factor", defaultValue: 1).value ?? 1
                ed.doc.ensureLayer("A-VIEW")
                let id = ed.doc.add(.insert(InsertGeom(block: DraftingViews.blockName(n), position: p, scale: Vec2(sc, sc))), layer: "A-VIEW")
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = "drafting:" + n }
                ed.print("Drafting view \(n) placed.")
            default:
                let names = DraftingViews.names(ed.doc)
                ed.print(names.isEmpty ? "No drafting views." : names.map { "\($0) (\(ed.doc.blocks[DraftingViews.blockName($0)]?.entities.count ?? 0) objects)" }.joined(separator: "\n"))
            }
        }
    }

    static var viewGraphics: CommandDef {
        CommandDef("VIEWGRAPHICS", aliases: ["SECTIONGRAPHICS", "ELEVGRAPHICS", "DEPTHCUE", "HIDDENLINES"], category: "View", summary: "Section/elevation graphics: line weights by depth, dashed hidden lines, depth cueing, far clip and dimensions in elevations.") { ed in
            @MainActor func onOff(_ key: String, _ label: String, _ def: Bool) async throws {
                let cur = ed.doc.variable(key).map { $0 == "1" } ?? def
                let v = try await ed.getYesNo(label, defaultValue: cur)
                ed.doc.setVariable(key, v ? "1" : "0")
            }
            try await onOff("ELEVLW", "Line weights by depth (cut / projection / beyond)?", true)
            try await onOff("ELEVHIDDEN", "Show hidden lines dashed?", false)
            try await onOff("DEPTHCUE", "Depth cueing (fade with distance)?", false)
            try await onOff("ELEVDIMS", "Level and height dimensions in elevations?", false)
            let far = try await ed.getReal("Far clip distance (0 = none)", defaultValue: ed.variableDouble("ELEVFARCLIP", 0)).value ?? 0
            if far > 0 { ed.doc.setVariable("ELEVFARCLIP", fmt(far)) } else { ed.doc.variables["ELEVFARCLIP"] = nil }
            ed.print("View graphics set (VIEWUPDATE regenerates placed views).")
        }
    }
}
