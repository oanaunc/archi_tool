// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for building details: layered floor/roof types, floor finishes, wall joins and layer wrapping, shafts and
// slab/roof openings, skylights, dormers, roof edges, railing types, elevators, model groups and opening trim.
import Foundation

enum BIMDetailCommands {
    static var all: [CommandDef] {
        [slabType, floorFinish, wallJoinEdit, wallWrap, shaft, slabOpening, skylight, dormer, roofEdge, railingType, elevator, modelGroup, openingTrim]
    }

    static func isRoof(_ g: BIMGeometry) -> Bool { if case .roof = g { return true }; return false }
    static func isSlabOrRoof(_ g: BIMGeometry) -> Bool { if case .slab = g { return true }; if case .roof = g { return true }; return false }
    static func isRailing(_ g: BIMGeometry) -> Bool { if case .railing = g { return true }; return false }

    // MARK: Layered types

    static var slabType: CommandDef {
        CommandDef("SLABTYPE", aliases: ["FLOORTYPE", "ROOFTYPE", "FLOORTYPES"], category: "Architecture", summary: "Layered floor/roof types: list, create (plies top-down), assign to slabs and roofs (thickness follows the build-up), or delete.") { ed in
            let k = try await ed.getKeyword("Floor/roof type option", ["List", "New", "Assign", "Delete"], defaultValue: "List") ?? "List"
            let mm = ed.doc.units.mm
            switch k {
            case "New":
                guard let name = try await ed.getWord("Enter type name") , !name.isEmpty else { return }
                let usage = try await ed.getKeyword("Usage", ["Floor", "Roof"], defaultValue: "Floor") ?? "Floor"
                var plies: [WallType.Ply] = []
                while true {
                    guard let mat = try await ed.getWord("Ply \(plies.count + 1) material (top first, Enter when done)"), !mat.isEmpty else { break }
                    guard ed.doc.material(mat) != nil else { ed.print("Unknown material \(mat)."); continue }
                    let t = try await ed.getPositive("Ply thickness", defaultValue: 50 / mm)
                    let fn = try await ed.getKeyword("Function", ["Finish", "Screed", "Thermal", "Membrane", "Structure", "Ceiling"], defaultValue: plies.isEmpty ? "Finish" : "Structure") ?? "Structure"
                    plies.append(WallType.Ply(material: ed.doc.material(mat)!.name, thickness: t, function: fn))
                }
                guard !plies.isEmpty else { throw CommandError.invalid("A type needs at least one ply.") }
                let t = SlabType(name: name, plies: plies, usage: usage.lowercased())
                if let i = ed.doc.slabTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { ed.doc.slabTypes[i] = t } else { ed.doc.slabTypes.append(t) }
                ed.print("\(name): \(plies.count) plies, \(fmt(t.thickness * mm)) mm.")
            case "Assign":
                let ids = try await ArchitectureCommands.elements(ed, "Select slabs and roofs", isSlabOrRoof)
                guard !ids.isEmpty else { return }
                let names = ed.doc.slabTypes.map(\.name)
                guard let n = try await ed.getWord("Enter type name [\(names.joined(separator: "/"))]", defaultValue: names.first), let t = ed.doc.slabType(n) else { throw CommandError.invalid("Unknown type.") }
                for id in ids {
                    guard let i = ed.doc.elementIndex(id) else { continue }
                    ed.doc.elements[i].props["slabType"] = t.name
                    switch ed.doc.elements[i].geometry {
                    case .slab(var s): s.thickness = t.thickness; ed.doc.elements[i].geometry = .slab(s)
                    case .roof(var r): r.thickness = t.thickness; ed.doc.elements[i].geometry = .roof(r)
                    default: break
                    }
                    if let top = t.plies.first(where: { $0.function == "Structure" }) { ed.doc.elements[i].material = top.material }
                }
                ed.selection = []
                ed.print("\(t.name) assigned to \(ids.count) element(s) (\(fmt(t.thickness * mm)) mm).")
            case "Delete":
                guard let n = try await ed.getWord("Enter type name"), let i = ed.doc.slabTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return }
                let used = ed.doc.elements.filter { $0.props["slabType"]?.caseInsensitiveCompare(n) == .orderedSame }.count
                guard used == 0 else { throw CommandError.invalid("\(n) is used by \(used) element(s).") }
                ed.doc.slabTypes.remove(at: i); ed.print("\(n) deleted.")
            default:
                for t in ed.doc.slabTypes {
                    ed.print("\(t.name) [\(t.usage)] \(fmt(t.thickness * mm)) mm: " + t.plies.map { "\($0.material) \(fmt($0.thickness * mm)) (\($0.function))" }.joined(separator: ", "))
                }
            }
        }
    }

    static var floorFinish: CommandDef {
        CommandDef("FLOORFINISH", aliases: ["FINISHFLOOR", "TILEFLOOR"], category: "Architecture", summary: "Places a floor finish layer in rooms (material, thickness, tile pattern in plan).") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select rooms", BIMExtCommands.isSpace)
            guard !ids.isEmpty else { return }
            let u = 1 / ed.doc.units.mm
            let mat = try await ed.getWord("Finish material", defaultValue: ed.doc.variable("FINISHMATERIAL") ?? "Tiles") ?? "Tiles"
            guard let m = ed.doc.material(mat) else { throw CommandError.invalid("Unknown material \(mat).") }
            let t = try await ed.getPositive("Finish thickness", defaultValue: ed.variableDouble("FINISHTHICKNESS", 15 * u))
            let tile = try await ed.getWord("Tile size (600x600, 300x600, None)", defaultValue: ed.doc.variable("FINISHTILE") ?? "600x600") ?? "None"
            ed.doc.setVariable("FINISHMATERIAL", m.name); ed.doc.setVariable("FINISHTHICKNESS", fmt(t)); ed.doc.setVariable("FINISHTILE", tile)
            var n = 0
            for id in ids {
                guard let room = ed.doc.element(id), case .space(let s) = room.geometry, s.boundary.count >= 3 else { continue }
                // Replace an existing finish of this room.
                ed.doc.elements.removeAll { $0.props["finishOf"] == "\(id)" }
                let fid = ed.doc.addElement(.slab(SlabGeom(boundary: s.boundary, thickness: t, topOffset: t)), level: room.level, layer: "A-FLOR-FNSH", material: m.name, name: "Floor finish")
                if let i = ed.doc.elementIndex(fid) {
                    ed.doc.elements[i].props["kind"] = "finish"; ed.doc.elements[i].props["finishOf"] = "\(id)"
                    if tile.lowercased() != "none" { ed.doc.elements[i].props["finishTile"] = tile }
                }
                if let r = ed.doc.elementIndex(id) { ed.doc.elements[r].props["floorFinish"] = m.name }
                n += 1
            }
            ed.selection = []
            ed.print("\(n) floor finish(es) of \(m.name) \(fmt(t / u)) mm placed.")
        }
    }

    // MARK: Walls

    static var wallJoinEdit: CommandDef {
        CommandDef("WALLJOINEDIT", aliases: ["EDITWALLJOINS", "JOINTYPE", "WALLJOINTYPE"], category: "Architecture", summary: "Edits a wall join: pick near a wall end, then Miter, Butt (this wall stops at the other), Square off, or Disallow the join.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select a wall near the end to edit", filter: { ArchitectureCommands.isWall(ed.doc, $0) }),
                  let el = ed.doc.element(pk.id), case .wall(let w) = el.geometry else { return }
            let atStart = pk.point.distance(to: w.start) <= pk.point.distance(to: w.end)
            let key = atStart ? "joinStart" : "joinEnd"
            let cur = el.props[key].map { $0.capitalized } ?? "Miter"
            let k = try await ed.getKeyword("Join type at the \(atStart ? "start" : "end")", ["Miter", "Butt", "Square", "Disallow", "Allow"], defaultValue: cur == "None" ? "Disallow" : cur) ?? "Miter"
            guard let i = ed.doc.elementIndex(pk.id) else { return }
            switch k {
            case "Butt": ed.doc.elements[i].props[key] = "butt"
            case "Square": ed.doc.elements[i].props[key] = "square"
            case "Disallow": ed.doc.elements[i].props[key] = "none"
            default: ed.doc.elements[i].props[key] = nil
            }
            ed.print("Wall #\(pk.id) \(atStart ? "start" : "end"): \(k == "Allow" ? "Miter" : k).")
        }
    }

    static var wallWrap: CommandDef {
        CommandDef("WALLWRAP", aliases: ["LAYERWRAP", "WRAPINSERTS"], category: "Architecture", summary: "Wraps the finish layers of compound walls into door/window openings (all walls or selected walls) and around free wall Ends.") { ed in
            let k = try await ed.getKeyword("Layer wrapping at inserts [On/Off/Select] or at free [Ends]", ["On", "Off", "Select", "Ends"], defaultValue: ed.doc.variable("WALLWRAP") == "1" ? "On" : "Off") ?? "On"
            if k == "Ends" {
                // Wrapping at wall ends (BIM-015): the finish layers turn around free wall ends.
                let on = try await ed.getYesNo("Wrap finish layers around free wall ends?", defaultValue: ed.doc.variable("WALLWRAPENDS") != "1")
                ed.doc.setVariable("WALLWRAPENDS", on ? "1" : "0")
                ed.print("Layer wrapping at wall ends \(on ? "on" : "off").")
                return
            }
            if k == "Select" {
                let ids = try await ArchitectureCommands.elements(ed, "Select walls", ArchitectureCommands.isWallGeom)
                let on = try await ed.getYesNo("Wrap these walls?", defaultValue: true)
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["wrapInserts"] = on ? "1" : "0" } }
                ed.selection = []
                ed.print("\(ids.count) wall(s) \(on ? "wrap" : "do not wrap") at inserts.")
                return
            }
            ed.doc.setVariable("WALLWRAP", k == "On" ? "1" : "0")
            ed.print("Layer wrapping at inserts \(k == "On" ? "on" : "off") for all walls.")
        }
    }

    // MARK: Shafts and openings

    static var shaft: CommandDef {
        CommandDef("SHAFT", aliases: ["SHAFTOPENING", "VERTICALSHAFT"], category: "Architecture", summary: "Creates a shaft that cuts every floor and roof between a base and a top level (associative: move it and the holes follow).") { ed in
            let f = try await ed.requirePoint("Specify first corner of the shaft (or polygon start)")
            guard let pts = try await ArchitectureCommands.polygonInput(ed, first: f) else { throw CommandError.invalid("A shaft needs at least three points.") }
            let lv = ed.doc.levels.sorted { $0.elevation < $1.elevation }
            let names = lv.map(\.name)
            let bn = try await ed.getWord("Base level [\(names.joined(separator: "/"))]", defaultValue: ed.doc.level(ed.doc.currentLevel)?.name ?? names.first)
            let tn = try await ed.getWord("Top level", defaultValue: names.last)
            let base = lv.first { $0.name.caseInsensitiveCompare(bn ?? "") == .orderedSame }?.id
            let top = lv.first { $0.name.caseInsensitiveCompare(tn ?? "") == .orderedSame }?.id
            Shafts.add(pts, base: base, top: top, doc: &ed.doc)
            let n = ed.doc.elements.filter { el in isSlabOrRoof(el.geometry) && !Shafts.holes(for: el, doc: ed.doc).isEmpty }.count
            ed.print("Shaft created; it cuts \(n) floor/roof element(s).")
        }
    }

    static var slabOpening: CommandDef {
        CommandDef("SLABOPENING", aliases: ["FLOOROPENING", "ROOFOPENING", "VERTICALOPENING"], category: "Architecture", summary: "Cuts a vertical opening in one floor or roof (sketched outline; associative with its host).") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select the floor or roof", filter: { id in ed.doc.element(id).map { isSlabOrRoof($0.geometry) } ?? false }) else { return }
            let f = try await ed.requirePoint("Specify first point of the opening")
            guard let pts = try await ArchitectureCommands.polygonInput(ed, first: f) else { throw CommandError.invalid("An opening needs at least three points.") }
            Shafts.add(pts, base: nil, top: nil, host: pk.id, doc: &ed.doc)
            ed.print("Opening cut in #\(pk.id).")
        }
    }

    static var skylight: CommandDef {
        CommandDef("SKYLIGHT", aliases: ["ROOFWINDOW", "ROOFLIGHT"], category: "Architecture", summary: "Places a skylight / roof window in a roof: framed glazing in the roof plane that cuts the roof.") { ed in
            let u = 1 / ed.doc.units.mm
            guard case .pick(let pk) = try await ed.pickObject("Select the roof", filter: { id in ed.doc.element(id).map { isRoof($0.geometry) } ?? false }), let roof = ed.doc.element(pk.id) else { return }
            let w = try await ed.getPositive("Skylight width", defaultValue: ed.variableDouble("SKYLIGHTW", 780 * u))
            let l = try await ed.getPositive("Skylight length (along the slope)", defaultValue: ed.variableDouble("SKYLIGHTL", 1180 * u))
            ed.doc.setVariable("SKYLIGHTW", fmt(w)); ed.doc.setVariable("SKYLIGHTL", fmt(l))
            var n = 0
            while true {
                guard let p = try await ed.getPoint("Specify skylight centre (Enter to finish)").point else { break }
                guard let fc = RoofDetails.face(at: p, roof: roof, doc: ed.doc) else { ed.print("That point is not on the roof."); continue }
                let slope = atan(fc.grad.length)
                let rot = fc.grad.length > 1e-12 ? fc.grad.angle - .pi / 2 : 0
                let g = ComponentGeom(category: "Windows", position: p, rotation: rot, size: Vec3(w, l * cos(slope), 150 * u), baseOffset: 0, family: nil)
                let id = ed.doc.addElement(.component(g), level: roof.level, layer: "A-GLAZ", material: "Aluminium", name: "Skylight")
                if let i = ed.doc.elementIndex(id) {
                    ed.doc.elements[i].props["kind"] = "skylight"; ed.doc.elements[i].props["host"] = "\(roof.id)"
                    ed.doc.elements[i].props["slopeLength"] = fmt(l)
                }
                n += 1
            }
            ed.print("\(n) skylight(s) placed.")
        }
    }

    static var dormer: CommandDef {
        CommandDef("DORMER", aliases: ["DORMERS", "ROOFDORMER"], category: "Architecture", summary: "Builds a dormer on a sloped roof: front and cheek walls, a gable or shed dormer roof, and the opening in the main roof.") { ed in
            let u = 1 / ed.doc.units.mm
            guard case .pick(let pk) = try await ed.pickObject("Select the sloped roof", filter: { id in
                if case .roof(let r)? = ed.doc.element(id)?.geometry { return r.kind != .flat }; return false }), let roof = ed.doc.element(pk.id), case .roof(let rg) = roof.geometry else { return }
            let p = try await ed.requirePoint("Specify the middle of the dormer front (on the roof)")
            guard let fc = RoofDetails.face(at: p, roof: roof, doc: ed.doc), fc.grad.length > 1e-9 else { throw CommandError.invalid("Pick a sloped part of the roof.") }
            let w = try await ed.getPositive("Dormer width", defaultValue: ed.variableDouble("DORMERW", 1800 * u))
            let h = try await ed.getPositive("Front wall height", defaultValue: ed.variableDouble("DORMERH", 1500 * u))
            let kind = try await ed.getKeyword("Dormer roof", ["Gable", "Shed"], defaultValue: "Gable") ?? "Gable"
            ed.doc.setVariable("DORMERW", fmt(w)); ed.doc.setVariable("DORMERH", fmt(h))
            let ids = Dormers.build(roof: roof, rg: rg, at: p, width: w, frontHeight: h, gable: kind == "Gable", doc: &ed.doc)
            guard !ids.isEmpty else { throw CommandError.invalid("The dormer does not fit on the roof there.") }
            ed.print("Dormer built (\(ids.count) elements: walls, roof and roof opening).")
        }
    }

    static var roofEdge: CommandDef {
        CommandDef("ROOFEDGE", aliases: ["FASCIA", "GUTTER", "SOFFIT", "ROOFEDGES"], category: "Architecture", summary: "Adds fascia boards, gutters (profile) and soffits along the eaves of roofs.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select roofs", isRoof)
            guard !ids.isEmpty else { return }
            let mm = ed.doc.units.mm
            let fascia = try await ed.getPositive("Fascia depth (0 = none)", defaultValue: ed.variableDouble("FASCIADEPTH", 200 / mm), allowZero: true)
            let gutter = try await ed.getPositive("Gutter size (0 = none)", defaultValue: ed.variableDouble("GUTTERSIZE", 125 / mm), allowZero: true)
            var prof = "gutter-half-round"
            if gutter > 0 { prof = try await ed.getKeyword("Gutter profile", ["HalfRound", "Ogee", "Box"], defaultValue: "HalfRound").map { ["HalfRound": "gutter-half-round", "Ogee": "gutter-ogee", "Box": "gutter-box"][$0] ?? "gutter-half-round" } ?? prof }
            let soffit = try await ed.getYesNo("Soffit under the overhang?", defaultValue: true)
            ed.doc.setVariable("FASCIADEPTH", fmt(fascia)); ed.doc.setVariable("GUTTERSIZE", fmt(gutter))
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                ed.doc.elements[i].props["fascia"] = fascia > 0 ? fmt(fascia * mm) : nil
                ed.doc.elements[i].props["gutter"] = gutter > 0 ? fmt(gutter * mm) : nil
                ed.doc.elements[i].props["gutterProfile"] = gutter > 0 ? prof : nil
                ed.doc.elements[i].props["soffit"] = soffit ? "1" : nil
            }
            ed.selection = []
            ed.print("Roof edges set on \(ids.count) roof(s).")
        }
    }

    // MARK: Railings, elevators, groups, trim

    static var railingType: CommandDef {
        CommandDef("RAILINGTYPE", aliases: ["RAILTYPE", "BALUSTERS", "HANDRAIL"], category: "Architecture", summary: "Sets the railing type of selected railings: preset (Balusters, Glass, Cable, Bars, Wooden, Handrail) or handrail profile, baluster spacing and extensions.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select railings", isRailing)
            guard !ids.isEmpty else { return }
            let names = RailingTypes.presets.map(\.name)
            let k = try await ed.getKeyword("Railing type", names + ["Custom", "Generic"], defaultValue: "Balusters") ?? "Balusters"
            var custom: (String, Double, Double, Double)? = nil
            if k == "Custom" {
                let prof = try await ed.getWord("Handrail profile [\(ProfileLibrary.names(ed.doc).prefix(8).joined(separator: "/"))…]", defaultValue: "round") ?? "round"
                let size = try await ed.getPositive("Handrail size", defaultValue: 50 / ed.doc.units.mm)
                let sp = try await ed.getPositive("Baluster spacing (0 = none)", defaultValue: 120 / ed.doc.units.mm, allowZero: true)
                let ext = try await ed.getPositive("Handrail extension at the ends", defaultValue: 0, allowZero: true)
                custom = (prof, size * ed.doc.units.mm, sp * ed.doc.units.mm, ext * ed.doc.units.mm)
            }
            for id in ids {
                guard let i = ed.doc.elementIndex(id), case .railing(var g) = ed.doc.elements[i].geometry else { continue }
                if k == "Generic" { g = RailingGeom(path: g.path, height: g.height, baseOffset: g.baseOffset) }
                else if let c = custom {
                    g.railProfile = c.0; g.railSize = c.1; g.infill = c.2 > 0 ? "balusters" : "none"; g.balusterSpacing = c.2 > 0 ? c.2 : nil
                    g.extensionLength = c.3 > 0 ? c.3 : nil; g.postSpacing = g.postSpacing ?? 1200
                } else { _ = RailingTypes.apply(preset: k, to: &g) }
                ed.doc.elements[i].geometry = .railing(g)
                ed.doc.elements[i].props["railingType"] = k == "Generic" ? nil : k
            }
            ed.selection = []
            ed.print("Railing type \(k) set on \(ids.count) railing(s).")
        }
    }

    static var elevator: CommandDef {
        CommandDef("ELEVATOR", aliases: ["LIFT", "ELEVATORSHAFT"], category: "Architecture", summary: "Places an elevator: car, shaft walls up to a top level and a shaft opening through the floors.") { ed in
            let u = 1 / ed.doc.units.mm
            let p = try await ed.requirePoint("Specify the centre of the elevator car")
            let w = try await ed.getPositive("Car width", defaultValue: ed.variableDouble("LIFTW", 1100 * u))
            let d = try await ed.getPositive("Car depth", defaultValue: ed.variableDouble("LIFTD", 1400 * u))
            let rot = try await ed.getAngle("Door facing angle (0 = doors face −Y)", base: p, defaultValue: 0).value ?? 0
            let lv = ed.doc.levels.sorted { $0.elevation < $1.elevation }
            let cur = ed.doc.level(ed.doc.currentLevel) ?? lv.first!
            let tn = try await ed.getWord("Top level [\(lv.map(\.name).joined(separator: "/"))]", defaultValue: lv.last?.name)
            let top = lv.first { $0.name.caseInsensitiveCompare(tn ?? "") == .orderedSame } ?? lv.last!
            let walls = try await ed.getYesNo("Shaft walls?", defaultValue: true)
            ed.doc.setVariable("LIFTW", fmt(w)); ed.doc.setVariable("LIFTD", fmt(d))
            let ids = Elevators.build(at: p, carWidth: w, carDepth: d, rotation: rot, base: cur, top: top, walls: walls, doc: &ed.doc)
            ed.print("Elevator placed (\(ids.count) elements) serving \(cur.name) to \(top.name).")
        }
    }

    static var modelGroup: CommandDef {
        CommandDef("MODELGROUP", aliases: ["BIMGROUP", "FURNITUREGROUP", "GROUPBIM"], category: "Architecture", summary: "Model groups: create a named group of elements, place instances, update all instances from an edited one, list, or ungroup.") { ed in
            let k = try await ed.getKeyword("Model group option", ["Create", "Place", "Update", "List", "Ungroup"], defaultValue: "Create") ?? "Create"
            switch k {
            case "Create":
                let ids = try await ed.getSelection("Select elements to group").filter { ed.doc.element($0) != nil }
                guard !ids.isEmpty else { throw CommandError.invalid("Select building elements.") }
                guard let name = try await ed.getWord("Group name", defaultValue: "Group \(ed.doc.modelGroups.count + 1)"), !name.isEmpty else { return }
                let o = try await ed.requirePoint("Specify group origin")
                let n = ModelGroups.create(name, ids: ids, origin: o, doc: &ed.doc)
                ed.selection = []
                ed.print("Group \"\(name)\" created with \(n) element(s).")
            case "Place":
                let names = ed.doc.modelGroups.map(\.name)
                guard !names.isEmpty else { throw CommandError.invalid("No model groups.") }
                guard let name = try await ed.getWord("Group name [\(names.joined(separator: "/"))]", defaultValue: names.last) else { return }
                var n = 0
                while true {
                    guard let p = try await ed.getPoint("Specify insertion point (Enter to finish)").point else { break }
                    let r = try await ed.getAngle("Rotation", base: p, defaultValue: 0).value ?? 0
                    if ModelGroups.place(name, at: p, rotation: r, level: ed.doc.currentLevel, doc: &ed.doc).isEmpty { throw CommandError.invalid("Unknown group \(name).") }
                    n += 1
                }
                ed.print("\(n) instance(s) of \(name) placed.")
            case "Update":
                guard case .pick(let pk) = try await ed.pickObject("Select an element of the edited instance", filter: { ed.doc.element($0)?.props["group"] != nil }) else { return }
                let n = ModelGroups.update(fromInstanceOf: pk.id, doc: &ed.doc)
                ed.print("Group updated; \(n) other instance(s) rebuilt.")
            case "Ungroup":
                guard case .pick(let pk) = try await ed.pickObject("Select an element of the instance", filter: { ed.doc.element($0)?.props["group"] != nil }) else { return }
                ed.print("\(ModelGroups.ungroup(instanceOf: pk.id, doc: &ed.doc)) element(s) ungrouped.")
            default:
                for g in ed.doc.modelGroups { ed.print("\(g.name): \(g.elements.count) element(s), \(ModelGroups.instances(g.name, doc: ed.doc).count) instance(s)") }
                if ed.doc.modelGroups.isEmpty { ed.print("No model groups.") }
            }
        }
    }

    static var openingTrim: CommandDef {
        CommandDef("OPENINGTRIM", aliases: ["CASING", "ARCHITRAVE", "LINTEL", "SILLBOARD"], category: "Architecture", summary: "Sets door/window casings (architraves), an interior window board and a lintel with bearings on selected openings.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select doors and windows", ArchitectureCommands.isOpening)
            guard !ids.isEmpty else { return }
            let casing = try await ed.getReal("Casing width in mm (0 = none)", defaultValue: 70).value ?? 70
            let sill = try await ed.getReal("Interior window board projection in mm (0 = none)", defaultValue: 0).value ?? 0
            let lintel = try await ed.getReal("Lintel height in mm (0 = none)", defaultValue: 200).value ?? 200
            let bearing = try await ed.getReal("Lintel bearing in mm", defaultValue: 150).value ?? 150
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                ed.doc.elements[i].props["casing"] = casing > 0 ? fmt(casing) : nil
                ed.doc.elements[i].props["sillBoard"] = sill > 0 ? fmt(sill) : nil
                ed.doc.elements[i].props["lintel"] = lintel > 0 ? fmt(lintel) : nil
                ed.doc.elements[i].props["lintelBearing"] = lintel > 0 ? fmt(bearing) : nil
            }
            ed.selection = []
            ed.print("Trim set on \(ids.count) opening(s).")
        }
    }
}

// MARK: - Dormers and elevators

public enum Dormers {
    /// Builds a dormer on a sloped roof face at p (front middle): front wall, two cheek walls, a dormer roof and a hosted
    /// opening in the main roof. Elements share props dormer = <front wall id>. Returns the created ids.
    @discardableResult
    public static func build(roof: BIMElement, rg: RoofGeom, at p: Vec2, width w: Double, frontHeight h: Double, gable: Bool, doc: inout ArchiDocument) -> [EntityID] {
        guard let fc = RoofDetails.face(at: p, roof: roof, doc: doc), fc.grad.length > 1e-9 else { return [] }
        let u = 1 / doc.units.mm
        let d = fc.grad.normalized, a = d.perp
        let k = fc.grad.length
        let elev = doc.level(roof.level)?.elevation ?? 0
        let roofTop = fc.zUnder + fc.tv                      // absolute top of the main roof at the front
        let wallTop = roofTop + h
        // Depth: where the dormer top meets the main roof surface (roof rises k per unit along d).
        let depth = h / k
        let t = 150 * u
        let front0 = p - a * (w / 2), front1 = p + a * (w / 2)
        let back0 = front0 + d * depth, back1 = front1 + d * depth
        // Check the dormer lies on the roof.
        let r = RoofShapes.faces(rg)
        guard [front0, front1, back0, back1].allSatisfy({ GeometryOps.pointInPolygon($0, r.footprint) }) else { return [] }
        var ids: [EntityID] = []
        let base = fc.zUnder - elev
        func wall(_ s: Vec2, _ e: Vec2, height: Double) -> EntityID {
            doc.addElement(.wall(WallGeom(start: s, end: e, thickness: t, height: height, baseOffset: base)), level: roof.level, name: "Dormer wall")
        }
        let fw = wall(front0, front1, height: wallTop - fc.zUnder)
        ids.append(fw)
        ids.append(wall(front0, back0, height: wallTop - fc.zUnder))
        ids.append(wall(front1, back1, height: wallTop - fc.zUnder))
        // Dormer roof: gable with its ridge along the slope (eaves on the cheeks) or a shed falling to the front.
        let ov = 200 * u
        let b = [front0 - d * ov, front1 - d * ov, back1, back0]
        let dr: RoofGeom
        if gable { dr = RoofGeom(boundary: b, kind: .gable, pitch: 35, thickness: rg.thickness, overhang: ov, baseOffset: wallTop - elev, eaveEdge: 1) }
        else { dr = RoofGeom(boundary: b, kind: .shed, pitch: 10, thickness: rg.thickness, overhang: ov, baseOffset: wallTop - elev, eaveEdge: 0) }
        ids.append(doc.addElement(.roof(dr), level: roof.level, material: roof.material, name: "Dormer roof"))
        // Opening in the main roof inside the dormer walls.
        let inner = [front0 + a * (t / 2), front1 - a * (t / 2), back1 - a * (t / 2), back0 + a * (t / 2)]
        ids.append(Shafts.add(inner, base: nil, top: nil, host: roof.id, doc: &doc))
        for id in ids {
            if let i = doc.elementIndex(id) { doc.elements[i].props["dormer"] = "\(fw)" }
            if let i = doc.entityIndex(id) { doc.entities[i].props["dormer"] = "\(fw)" }
        }
        return ids
    }
}

public enum Elevators {
    /// Elevator car (family "elevator") on the base level, shaft walls up to the top level and a shaft opening through
    /// the floors in between (the pit floor stays). Returns the created ids.
    @discardableResult
    public static func build(at p: Vec2, carWidth w: Double, carDepth d: Double, rotation: Double, base: Level, top: Level, walls: Bool, doc: inout ArchiDocument) -> [EntityID] {
        let u = 1 / doc.units.mm
        var ids: [EntityID] = []
        let car = doc.addElement(.component(ComponentGeom(category: "Vertical Circulation", position: p, rotation: rotation, size: Vec3(w, d, 2300 * u), family: "elevator")),
                                 level: base.id, material: "Steel", name: "Elevator")
        ids.append(car)
        // Shaft: clearances 200 each side and at the back, 100 at the door side.
        let t = Transform2D.translation(p) * Transform2D.rotation(rotation)
        let x0 = -w / 2 - 200 * u, x1 = w / 2 + 200 * u, y0 = -d / 2 - 100 * u, y1 = d / 2 + 200 * u
        let rect = [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)].map(t.apply)
        // Cut floors above the base level up to the top level.
        let above = doc.levels.filter { $0.elevation > base.elevation + 1e-6 }.min { $0.elevation < $1.elevation }
        ids.append(Shafts.add(rect, base: above?.id ?? top.id, top: top.id, doc: &doc))
        if walls {
            let th = 200 * u
            let outer = RG.offsetPolygon(GeometryOps.signedArea(rect) > 0 ? rect : rect.reversed(), th / 2)
            for i in 0..<4 {
                var wg = WallGeom(start: outer[i], end: outer[(i + 1) % 4], thickness: th, height: max(top.elevation + top.height - base.elevation, 1))
                wg.topLevel = top.id; wg.topOffset = top.height
                let id = doc.addElement(.wall(wg), level: base.id, material: "Concrete", name: "Shaft wall")
                ids.append(id)
                // Door opening on the front wall at every level served.
                if i == 0 {
                    for l in doc.levels where l.elevation >= base.elevation - 1e-6 && l.elevation <= top.elevation + 1e-6 {
                        let o = OpeningGeom(kind: .door, hostWall: id, offset: outer[0].distance(to: outer[1]) / 2, width: min(900 * u, w), height: 2100 * u,
                                            sill: l.elevation - base.elevation, doorStyle: .sliding)
                        ids.append(doc.addElement(.opening(o), level: base.id, name: "Elevator door"))
                    }
                }
            }
        }
        for id in ids { if let i = doc.elementIndex(id) { doc.elements[i].props["elevator"] = "\(car)" }; if let i = doc.entityIndex(id) { doc.entities[i].props["elevator"] = "\(car)" } }
        return ids
    }
}
