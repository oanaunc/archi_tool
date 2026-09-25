// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for MEP runs, structure (beam systems, braces, trusses, steel profiles), site (parking, paths, sub-regions,
// retaining walls, property lines, spot elevations), worksets, design options, room finishes, colour fills,
// reflected ceiling plans, automatic wall dimensions and opening sub-parts.
import Foundation

/// Room finish parameters (props finishFloor / finishBase / finishWall / finishCeiling) and the finish schedule.
public enum RoomFinishes {
    public static let keys = ["finishFloor", "finishBase", "finishWall", "finishCeiling"]
    public static let header = ["Number", "Name", "Area", "Floor", "Base", "Walls", "Ceiling"]

    /// Schedule rows (header first) for rooms, sorted by level then number/name.
    public static func rows(_ doc: ArchiDocument, level: Int? = nil) -> [[String]] {
        var rooms: [(BIMElement, SpaceGeom)] = []
        for el in ModelSets.visibleModel(doc).elements { if case .space(let g) = el.geometry, level == nil || el.level == level { rooms.append((el, g)) } }
        rooms.sort { a, b in
            if a.0.level != b.0.level { return a.0.level < b.0.level }
            let ka = a.1.number.isEmpty ? a.1.name : a.1.number, kb = b.1.number.isEmpty ? b.1.name : b.1.number
            return ka.localizedStandardCompare(kb) == .orderedAscending
        }
        return [header] + rooms.map { el, g in
            [g.number, g.name.isEmpty ? el.name : g.name, PlanRepresentation.formatArea(abs(GeometryOps.signedArea(g.boundary)), doc)] + keys.map { el.props[$0] ?? "" }
        }
    }
}

enum BIMExtCommands {
    static var all: [CommandDef] { mep + structure + site + sets + documentation }

    static func isComponent(_ g: BIMGeometry) -> Bool { if case .component = g { return true }; return false }
    static func isSpace(_ g: BIMGeometry) -> Bool { if case .space = g { return true }; return false }

    // MARK: - MEP runs

    /// Draws a run (pipe, conduit, duct, cable tray, retaining wall) along picked points.
    @MainActor static func run(_ ed: Editor, family id: String) async throws {
        guard let fam = ComponentLibrary.runFamily(id) else { return }
        let u = 1 / ed.doc.units.mm
        let vk = "RUN_" + id.uppercased().replacingOccurrences(of: "-", with: "")
        var w = ed.variableDouble(vk + "_W", fam.size.x * u), h = ed.variableDouble(vk + "_H", fam.size.z * u)
        var elev = ed.variableDouble(vk + "_Z", fam.baseOffset * u)
        var slope = 0.0
        var system: String? = ed.doc.variable(vk + "_SYS").flatMap { $0.isEmpty ? nil : $0 }
        let round = id == "pipe" || id == "conduit"
        var pts: [Vec2] = [], zs: [Double] = []
        let label = fam.name.lowercased()
        while pts.isEmpty {
            let sizeText = round ? "Diameter = \(fmt(w))" : (id == "retaining-wall" ? "Thickness = \(fmt(w)), Height = \(fmt(h))" : "Width = \(fmt(w)), Height = \(fmt(h))")
            ed.print("\(fam.name): \(sizeText), " + (id == "retaining-wall" ? "Base" : "Elevation") + " = \(fmt(elev))" + (slope != 0 ? ", Slope = \(fmt(slope, 2))%" : ""))
            var kws = ["Size", "Elevation"]
            if id == "pipe" { kws += ["Fixture", "Slope"] }
            if id != "retaining-wall" { kws.append("sYstem") }
            if let s = system { ed.print("System: \(s)" + (RunFamilies.systems.first { $0.code == s }.map { " (\($0.name))" } ?? "")) }
            let a = try await ed.getPoint("Specify start point of the \(label)", keywords: kws)
            switch a {
            case .point(let p): pts = [p]; zs = [0]
            case .keyword("Size"):
                w = try await ed.getPositive(round ? "Specify diameter" : (id == "retaining-wall" ? "Specify stem thickness" : "Specify width"), defaultValue: w)
                if !round { h = try await ed.getPositive("Specify height", defaultValue: h) }
            case .keyword("Elevation"): elev = try await ed.getDistance(id == "retaining-wall" ? "Specify base above the level" : "Specify centreline elevation above the level", defaultValue: elev).value ?? elev
            case .keyword("Slope"): slope = try await ed.getReal("Specify fall in percent (0 = level)", defaultValue: slope).value ?? slope
            case .keyword("sYstem"):
                let codes = RunFamilies.systems.map(\.code)
                guard let s = try await ed.getWord("Enter system [\(codes.joined(separator: "/"))/None]", defaultValue: system ?? (id == "duct" ? "SA" : (id == "pipe" ? "DCW" : "POWER"))) else { continue }
                system = s.lowercased() == "none" ? nil : (codes.first { $0.caseInsensitiveCompare(s) == .orderedSame } ?? s.uppercased())
            case .keyword("Fixture"):
                guard case .pick(let pk) = try await ed.pickObject("Select plumbing fixture", filter: { ed.doc.element($0).map { isComponent($0.geometry) } ?? false }),
                      let fe = ed.doc.element(pk.id), case .component(let fg) = fe.geometry, let ff = ComponentLibrary.family(fg.family) else { continue }
                let cons = ComponentLibrary.worldConnectors(ff, fg, z0: fg.baseOffset).filter { $0.system != "POWER" }
                guard !cons.isEmpty else { ed.print("That fixture has no pipe connectors."); continue }
                let systems = Array(Set(cons.map(\.system))).sorted()
                let sys = systems.count == 1 ? systems[0] : (try await ed.getKeyword("Connector system", systems, defaultValue: systems.contains("SAN") ? "SAN" : systems[0]) ?? systems[0])
                guard let c = cons.first(where: { $0.system == sys }) else { continue }
                pts = [c.position.xy]; zs = [0]; elev = c.position.z; system = sys
                if c.diameter > 0 { w = c.diameter * u }
                ed.print("Starting at the \(sys) connector (\(fmt(c.diameter)) mm) of \(fe.name.isEmpty ? "the fixture" : fe.name), elevation \(fmt(elev)).")
            default: return
            }
        }
        let fall = slope / 100
        while true {
            let (cur, curZ) = (pts, zs)
            let a = try await ed.getPoint("Specify next point", base: pts.last, keywords: pts.count >= 2 ? ["Rise", "Undo"] : ["Rise"]) { c in
                [.polyline(PolylineGeom(points: RG.dedupe(cur + [c], closed: false), closed: false))]
            }
            _ = curZ
            switch a {
            case .point(let p):
                guard !p.isClose(pts.last!, tol: 1e-9) else { continue }
                let z = zs.last! - fall * p.distance(to: pts.last!)
                pts.append(p); zs.append(z)
            case .keyword("Rise"):
                guard let dz = try await ed.getDistance("Specify vertical rise (negative = drop)").value, abs(dz) > 1e-9 else { continue }
                pts.append(pts.last!); zs.append(zs.last! + dz)
            case .keyword("Undo"): if pts.count > 1 { pts.removeLast(); zs.removeLast() }
            default:
                guard pts.count >= 2 else { ed.print("A run needs at least two points."); return }
                let o = pts[0]
                let hasZ = zs.contains { abs($0) > 1e-9 }
                let size = Vec3(w, w, round ? w : h)
                let g = ComponentGeom(category: fam.category, position: o, rotation: 0, size: size, baseOffset: elev, family: fam.id,
                                      path: pts.map { $0 - o }, pathZ: hasZ ? zs : nil)
                let layer = id == "retaining-wall" ? "C-SITE" : (fam.category == "Electrical" ? "E-CABL" : (fam.category == "Mechanical" ? "M-DUCT" : "P-PIPE"))
                let eid = ed.doc.addElement(.component(g), layer: layer, material: nil, name: fam.name)
                if id == "retaining-wall", let i = ed.doc.elementIndex(eid) { ed.doc.elements[i].material = "Concrete" }
                if let s = system, let i = ed.doc.elementIndex(eid) { ed.doc.elements[i].props["system"] = s }
                ed.doc.setVariable(vk + "_SYS", system ?? "")
                ed.doc.setVariable(vk + "_W", fmt(w)); ed.doc.setVariable(vk + "_H", fmt(h)); ed.doc.setVariable(vk + "_Z", fmt(elev))
                let fittings = max(0, pts.count - 2)
                ed.print("\(fam.name) created: \(fmt(RunFamilies.length(g), 0)) long" + (id == "pipe" || id == "conduit" ? ", \(fittings) elbow(s)" : (id == "duct" ? ", \(fittings) bend(s)" : "")) + ".")
                return
            }
        }
    }

    static var mep: [CommandDef] { [
        CommandDef("MEPPIPE", aliases: ["PIPERUN", "PIPING"], category: "MEP", summary: "Draws pipes along points with elbow fittings at bends; can start at a plumbing fixture connector, slope and rise.") { ed in try await run(ed, family: "pipe") },
        CommandDef("DUCT", aliases: ["DUCTRUN", "DUCTWORK"], category: "MEP", summary: "Draws rectangular ducts along points with flanged bends.") { ed in try await run(ed, family: "duct") },
        CommandDef("CABLETRAY", aliases: ["TRAYRUN"], category: "MEP", summary: "Draws cable trays (open U-channel with rungs in plan) along points.") { ed in try await run(ed, family: "cabletray") },
        CommandDef("CONDUIT", aliases: ["CONDUITRUN"], category: "MEP", summary: "Draws electrical conduit along points with elbows.") { ed in try await run(ed, family: "conduit") },
        CommandDef("MEPCONNECTORS", aliases: ["CONNECTORS", "FIXTURECONNECTORS"], category: "MEP", summary: "Lists plumbing/electrical connection points of fixtures and shows or hides them in plan.") { ed in
            let k = try await ed.getKeyword("Connectors", ["List", "Show", "Hide"], defaultValue: "List") ?? "List"
            switch k {
            case "Show": ed.doc.setVariable("MEPCONNECTORS", "1"); ed.print("Connection points shown in plan.")
            case "Hide": ed.doc.setVariable("MEPCONNECTORS", "0"); ed.print("Connection points hidden.")
            default:
                var n = 0
                for el in ed.doc.elements {
                    guard case .component(let g) = el.geometry, let f = ComponentLibrary.family(g.family) else { continue }
                    let elev = ed.doc.level(el.level)?.elevation ?? 0
                    let cs = ComponentLibrary.worldConnectors(f, g, z0: elev + g.baseOffset)
                    guard !cs.isEmpty else { continue }
                    n += cs.count
                    ed.print("#\(el.id) \(f.name): " + cs.map { "\($0.system)" + ($0.diameter > 0 ? " Ø\(fmt($0.diameter))" : "") + " at \(fmt($0.position.x, 0)),\(fmt($0.position.y, 0)),\(fmt($0.position.z, 0))" }.joined(separator: "; "))
                }
                ed.print(n == 0 ? "No fixtures with connectors." : "\(n) connector(s).")
            }
        },
    ] }

    // MARK: - Structure

    static var structure: [CommandDef] { [
        CommandDef("STEELPROFILE", aliases: ["STRUCTPROFILE", "SECTIONPROFILE"], category: "Structure", summary: "Applies structural profiles (IPE, HEA, HEB, UPN, I/H/C/L/T, RHS/SHS/CHS, rectangular, round) to beams and columns, or lists them.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select beams and columns (Enter to list profiles)") { g in
                switch g { case .beam, .column: return true; default: return false } }
            if ids.isEmpty {
                ed.print("Parametric: I h×b×tw×tf, H h×b×tw×tf, C h×b×tw×tf, L a×b×t, T h×b×tw×tf, RHS h×b×t, SHS a×t, CHS d×t, RECT b×h, ROUND d.")
                ed.print("Catalogue: " + StructuralProfiles.catalogue.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: " "))
                return
            }
            guard let spec = try await ed.getString("Enter profile (e.g. IPE300, HEA200, RHS 200x100x8, CHS 168x6; None = plain)", defaultValue: ed.doc.variable("STEELPROFILE")) else { return }
            let none = ["none", "", "plain"].contains(spec.lowercased())
            let sec = StructuralProfiles.section(spec)
            if !none && sec == nil { throw CommandError.invalid("Unknown profile \"\(spec)\".") }
            let u = 1 / ed.doc.units.mm
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                switch ed.doc.elements[i].geometry {
                case .beam(var b):
                    b.profile = none ? nil : spec
                    if let s = sec { b.width = s.b * u; b.depth = s.h * u }
                    ed.doc.elements[i].geometry = .beam(b)
                case .column(var c):
                    c.profile = none ? nil : spec
                    if let s = sec { c.width = s.b * u; c.depth = s.h * u; c.round = s.shape == .chs || s.shape == .round }
                    ed.doc.elements[i].geometry = .column(c)
                default: continue
                }
                if !none && ed.doc.elements[i].material == "Concrete" { ed.doc.elements[i].material = "Steel" }
            }
            if !none { ed.doc.setVariable("STEELPROFILE", spec) }
            ed.selection = []
            ed.print("\(ids.count) member(s) set to \(none ? "plain sections" : sec!.name)" + (sec.map { String(format: " (A = %.0f mm²)", $0.area) } ?? "") + ".")
        },
        CommandDef("BEAMSYSTEM", aliases: ["BEAMSYS", "JOISTS"], category: "Structure", summary: "Fills a boundary with parallel beams at a spacing (direction, size or profile, top elevation).") { ed in
            let u = 1 / ed.doc.units.mm
            var spacing = ed.variableDouble("BEAMSYSSPACING", 1200 * u)
            var profile = ed.doc.variable("BEAMSYSPROFILE")
            var width = ed.variableDouble("BEAMWIDTH", 200 * u), depth = ed.variableDouble("BEAMDEPTH", 400 * u)
            var top = ed.variableDouble("BEAMSYSTOP", ed.currentLevelHeight)
            var boundary: [Vec2]? = nil
            while boundary == nil {
                ed.print("Beam system: Spacing = \(fmt(spacing)), " + (profile.map { "Profile = \($0)" } ?? "Size = \(fmt(width))×\(fmt(depth))") + ", Top = \(fmt(top))")
                let a = try await ed.getPoint("Specify first boundary point", keywords: ["Object", "Spacing", "Profile", "Size", "Top"])
                switch a {
                case .point(let p): boundary = try await ArchitectureCommands.polygonInput(ed, first: p); if boundary == nil { return }
                case .keyword("Object"): boundary = try await ArchitectureCommands.selectBoundary(ed); if boundary == nil { return }
                case .keyword("Spacing"): spacing = try await ed.getPositive("Specify beam spacing", defaultValue: spacing)
                case .keyword("Profile"):
                    let s = try await ed.getString("Enter profile (None = rectangular)", defaultValue: profile ?? "IPE200") ?? ""
                    if ["none", ""].contains(s.lowercased()) { profile = nil } else if StructuralProfiles.section(s) != nil { profile = s } else { ed.print("Unknown profile.") }
                case .keyword("Size"):
                    width = try await ed.getPositive("Specify beam width", defaultValue: width); depth = try await ed.getPositive("Specify beam depth", defaultValue: depth); profile = nil
                case .keyword("Top"): top = try await ed.getDistance("Specify top of beams above the level", defaultValue: top).value ?? top
                default: return
                }
            }
            let poly = ArchitectureCommands.ccw(boundary!)
            let e0 = poly[1] - poly[0]
            let ang = try await ed.getAngle("Specify beam direction", base: poly[0], defaultValue: e0.angle).value ?? e0.angle
            let lines = BeamSystemLayout.lines(boundary: poly, angle: ang, spacing: spacing)
            guard !lines.isEmpty else { throw CommandError.invalid("The boundary is narrower than the spacing.") }
            if let p = profile, let s = StructuralProfiles.section(p) { width = s.b * u; depth = s.h * u }
            var first: EntityID? = nil
            for (a, b) in lines {
                let id = ed.doc.addElement(.beam(BeamGeom(start: a, end: b, width: width, depth: depth, topOffset: top, profile: profile)), name: "Beam")
                if first == nil { first = id }
                if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["beamSystem"] = "\(first!)"; if profile != nil { ed.doc.elements[i].material = "Steel" } }
            }
            ed.doc.setVariable("BEAMSYSSPACING", fmt(spacing)); ed.doc.setVariable("BEAMSYSTOP", fmt(top))
            if let p = profile { ed.doc.setVariable("BEAMSYSPROFILE", p) } else { ed.doc.variables["BEAMSYSPROFILE"] = nil }
            ed.print("Beam system #\(first!): \(lines.count) beam(s) at \(fmt(spacing)) spacing.")
        },
        CommandDef("BRACE", aliases: ["BRACING", "DIAGONALBRACE"], category: "Structure", summary: "Places a diagonal brace between two plan points at a bottom and a top elevation (profile, default CHS).") { ed in
            let u = 1 / ed.doc.units.mm
            var spec = ed.doc.variable("BRACEPROFILE") ?? "CHS 114x5"
            var a: Vec2
            while true {
                let r = try await ed.getPoint("Specify brace start (bottom) point", keywords: ["Profile"])
                if case .keyword = r { spec = try await ed.getString("Enter profile", defaultValue: spec) ?? spec; continue }
                guard let p = r.point else { return }
                a = p; break
            }
            let b = try await ed.requirePoint("Specify brace end (top) point", base: a) { c in [.line(LineGeom(a, c))] }
            let z0 = try await ed.getDistance("Specify bottom elevation above the level", defaultValue: 0).value ?? 0
            let z1 = try await ed.getDistance("Specify top elevation above the level", defaultValue: ed.currentLevelHeight).value ?? ed.currentLevelHeight
            guard let sec = StructuralProfiles.section(spec) else { throw CommandError.invalid("Unknown profile \(spec).") }
            guard a.distance(to: b) > 1e-9 || abs(z1 - z0) > 1e-9 else { throw CommandError.invalid("The brace has no length.") }
            guard a.distance(to: b) > 1e-9 else { throw CommandError.invalid("Braces need two different plan points (use COLUMN for vertical members).") }
            let hh = sec.h * u / 2
            // topOffset is the top of the section; the axis runs from z0 to z1.
            let g = BeamGeom(start: a, end: b, width: sec.b * u, depth: sec.h * u, topOffset: z0 + hh, profile: spec, endTopOffset: z1 + hh)
            let id = ed.doc.addElement(.beam(g), material: "Steel", name: "Brace")
            if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["kind"] = "brace" }
            ed.doc.setVariable("BRACEPROFILE", spec)
            let len = Vec3(b.x - a.x, b.y - a.y, z1 - z0).length
            ed.print("Brace \(sec.name) created, length \(fmt(len, 0)).")
        },
        CommandDef("TRUSS", aliases: ["TRUSSES"], category: "Structure", summary: "Places a Pratt, Howe, Warren or Fink truss between two bearing points (height, member width, bearing elevation).") { ed in
            var kind = ed.doc.variable("TRUSSKIND") ?? "pratt"
            let u = 1 / ed.doc.units.mm
            var height = ed.variableDouble("TRUSSHEIGHT", 1500 * u), member = ed.variableDouble("TRUSSMEMBER", 100 * u)
            var elev = ed.variableDouble("TRUSSELEV", ed.currentLevelHeight)
            var a: Vec2
            while true {
                ed.print("Truss: \(kind.capitalized), Height = \(fmt(height)), Member = \(fmt(member)), Bearing = \(fmt(elev))")
                let r = try await ed.getPoint("Specify first bearing point", keywords: ["Kind", "Height", "Member", "Elevation"])
                switch r {
                case .point(let p): a = p
                case .keyword("Kind"): kind = (try await ed.getKeyword("Truss kind", ["Pratt", "Howe", "Warren", "Fink"], defaultValue: kind.capitalized) ?? "Pratt").lowercased(); continue
                case .keyword("Height"): height = try await ed.getPositive("Specify truss height", defaultValue: height); continue
                case .keyword("Member"): member = try await ed.getPositive("Specify member width", defaultValue: member); continue
                case .keyword("Elevation"): elev = try await ed.getDistance("Specify bearing elevation above the level", defaultValue: elev).value ?? elev; continue
                default: return
                }
                break
            }
            let b = try await ed.requirePoint("Specify second bearing point", base: a) { c in [.line(LineGeom(a, c))] }
            let span = a.distance(to: b)
            guard span > height * 0.5 else { throw CommandError.invalid("The span is too short for the truss height.") }
            let fid = "truss-" + kind
            guard let fam = ComponentLibrary.family(fid) else { return }
            let g = ComponentGeom(category: fam.category, position: (a + b) / 2, rotation: (b - a).angle, size: Vec3(span, member, height), baseOffset: elev, family: fid)
            ed.doc.addElement(.component(g), material: "Wood", name: fam.name)
            ed.doc.setVariable("TRUSSKIND", kind); ed.doc.setVariable("TRUSSHEIGHT", fmt(height)); ed.doc.setVariable("TRUSSMEMBER", fmt(member)); ed.doc.setVariable("TRUSSELEV", fmt(elev))
            let n = Trusses.members(kind: kind, span: span, height: height).count
            ed.print("\(fam.name) created: span \(fmt(span, 0)), \(n) members.")
        },
    ] }

    // MARK: - Site

    @MainActor static func terrainHeight(_ ed: Editor, at p: Vec2) -> Double? {
        for e in ed.doc.entities where e.props["topo"] == "1" {
            if case .solid(let s) = e.geometry, let z = Terrain.elevation(at: p, vertices: s.meshVertices, triangles: s.meshTriangles) { return z }
        }
        return nil
    }

    /// Thin slab on the site (paths, sub-regions, paving), draped at the terrain height at its centre when a toposurface exists.
    @MainActor @discardableResult
    static func siteSlab(_ ed: Editor, _ poly: [Vec2], kind: String, material: String, thickness: Double, name: String) -> EntityID {
        let elev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
        var top = 0.0
        if let z = terrainHeight(ed, at: LabelPlacement.pole(of: poly).point) { top = z - elev + 20 / ed.doc.units.mm }
        ed.doc.ensureLayer("C-SITE")
        let id = ed.doc.addElement(.slab(SlabGeom(boundary: ArchitectureCommands.ccw(poly), thickness: thickness, topOffset: top)), layer: "C-SITE", material: material, name: name)
        if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["kind"] = kind }
        return id
    }

    static var site: [CommandDef] { [
        CommandDef("PARKINGLOT", aliases: ["PARKINGROW", "CARPARK"], category: "Site", summary: "Lays out a row (or double row with aisle) of parking bays at 90°, 60° or 45° with paving.") { ed in
            let u = 1 / ed.doc.units.mm
            var w = ed.variableDouble("PARKW", 2500 * u), d = ed.variableDouble("PARKD", 5000 * u), angle = ed.variableDouble("PARKANGLE", 90)
            var double = ed.doc.variable("PARKDOUBLE") == "1", aisle = ed.variableDouble("PARKAISLE", 6000 * u)
            var a: Vec2
            while true {
                ed.print("Parking: \(fmt(w))×\(fmt(d)) at \(fmt(angle))°" + (double ? ", double row, aisle \(fmt(aisle))" : ", single row"))
                let r = try await ed.getPoint("Specify start of the row (aisle edge)", keywords: ["Width", "Depth", "Angle", "Double", "Aisle"])
                switch r {
                case .point(let p): a = p
                case .keyword("Width"): w = try await ed.getPositive("Specify bay width", defaultValue: w); continue
                case .keyword("Depth"): d = try await ed.getPositive("Specify bay depth", defaultValue: d); continue
                case .keyword("Angle"):
                    let k = try await ed.getKeyword("Parking angle", ["90", "60", "45"], defaultValue: fmt(angle)) ?? "90"
                    angle = Double(k) ?? 90; continue
                case .keyword("Double"): double = try await ed.getYesNo("Double row across an aisle?", defaultValue: !double); continue
                case .keyword("Aisle"): aisle = try await ed.getPositive("Specify aisle width", defaultValue: aisle); continue
                default: return
                }
                break
            }
            let b = try await ed.requirePoint("Specify end of the row", base: a) { c in
                ParkingLayout.stalls(from: a, to: c, width: w, depth: d, angle: angle, double: double, aisle: aisle).map { st in
                    .polyline(PolylineGeom(points: PlanRepresentation.componentPoly(ComponentGeom(position: st.center, rotation: st.rotation, size: Vec3(w, d, 5))), closed: true))
                }
            }
            let stalls = ParkingLayout.stalls(from: a, to: b, width: w, depth: d, angle: angle, double: double, aisle: aisle)
            guard !stalls.isEmpty else { throw CommandError.invalid("The row is too short for one bay.") }
            ComponentLibrary.ensureMaterials(&ed.doc)
            ed.doc.ensureLayer("C-SITE")
            for s in stalls {
                ed.doc.addElement(.component(ComponentGeom(category: "Site", position: s.center, rotation: s.rotation, size: Vec3(w, d, 5), family: "parking")), layer: "C-SITE", name: "Parking Space")
            }
            // Paving under the bays (and the aisle).
            let dir = (b - a).normalized, n = dir.perp
            let reach = d * sin(min(max(angle, 30), 90) * .pi / 180)
            let far = double ? -(aisle + reach) : 0
            let pave = [a + n * far, b + n * far, b + n * reach, a + n * reach]
            siteSlab(ed, pave, kind: "paving", material: "Stone", thickness: 100 * u, name: "Paving")
            ed.doc.setVariable("PARKW", fmt(w)); ed.doc.setVariable("PARKD", fmt(d)); ed.doc.setVariable("PARKANGLE", fmt(angle))
            ed.doc.setVariable("PARKDOUBLE", double ? "1" : "0"); ed.doc.setVariable("PARKAISLE", fmt(aisle))
            ed.print("\(stalls.count) parking bay(s) laid out.")
        },
        CommandDef("SITEPATH", aliases: ["FOOTPATH", "WALKWAY"], category: "Site", summary: "Draws a path of a given width along points as a site sub-region (draped on the toposurface).") { ed in
            let u = 1 / ed.doc.units.mm
            var w = ed.variableDouble("SITEPATHW", 1500 * u)
            var mat = ed.doc.variable("SITEPATHMAT") ?? "Stone"
            var pts: [Vec2] = []
            while pts.isEmpty {
                let r = try await ed.getPoint("Specify start of path", keywords: ["Width", "Material"])
                switch r {
                case .point(let p): pts = [p]
                case .keyword("Width"): w = try await ed.getPositive("Specify path width", defaultValue: w)
                case .keyword("Material"): mat = try await ed.getWord("Enter material", defaultValue: mat) ?? mat
                default: return
                }
            }
            while true {
                let cur = pts
                guard let p = try await ed.getPoint("Specify next point", base: pts.last) { c in [.polyline(PolylineGeom(points: cur + [c]))] }.point else { break }
                if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
            }
            guard pts.count >= 2 else { return }
            let l = PlanRepresentation.offsetPolyline(pts, w / 2), r = PlanRepresentation.offsetPolyline(pts, -w / 2)
            let id = siteSlab(ed, l + r.reversed(), kind: "path", material: mat, thickness: 50 * u, name: "Path")
            ed.doc.setVariable("SITEPATHW", fmt(w)); ed.doc.setVariable("SITEPATHMAT", mat)
            ed.print("Path #\(id) created (\(fmt(zip(pts, pts.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }, 0)) long).")
        },
        CommandDef("SUBREGION", aliases: ["SITEREGION", "LAWN"], category: "Site", summary: "Creates a site sub-region (lawn, gravel, paving) from points or a closed object, draped on the toposurface.") { ed in
            var mat = ed.doc.variable("SUBREGIONMAT") ?? "Grass"
            var poly: [Vec2]? = nil
            while poly == nil {
                let r = try await ed.getPoint("Specify first point", keywords: ["Object", "Material"])
                switch r {
                case .point(let p): poly = try await ArchitectureCommands.polygonInput(ed, first: p); if poly == nil { return }
                case .keyword("Object"): poly = try await ArchitectureCommands.selectBoundary(ed); if poly == nil { return }
                case .keyword("Material"): mat = try await ed.getWord("Enter material (Grass, Stone, Tiles, Concrete…)", defaultValue: mat) ?? mat
                default: return
                }
            }
            let id = siteSlab(ed, poly!, kind: "subregion", material: mat, thickness: 30 / ed.doc.units.mm, name: mat)
            ed.doc.setVariable("SUBREGIONMAT", mat)
            ed.print("Sub-region #\(id) (\(mat)): " + PlanRepresentation.formatArea(abs(GeometryOps.signedArea(poly!)), ed.doc) + ".")
        },
        CommandDef("RETAININGWALL", aliases: ["RETWALL"], category: "Site", summary: "Draws a cantilever retaining wall (battered stem on a footing) along points; retained side on the right of travel.") { ed in
            try await run(ed, family: "retaining-wall")
        },
        CommandDef("PROPERTYLINE", aliases: ["PROPLINE", "BOUNDARYLINE"], category: "Site", summary: "Draws property lines by points or bearings and distances; labels bearings, distances and the enclosed area.") { ed in
            var pts: [Vec2] = []
            let north = ed.doc.info.northAngle
            guard let first = try await ed.getPoint("Specify point of beginning").point else { return }
            pts = [first]
            var closed = false
            while true {
                let cur = pts
                let a = try await ed.getPoint("Specify next point", base: pts.last, keywords: pts.count >= 3 ? ["Bearing", "Close", "Undo"] : ["Bearing", "Undo"]) { c in
                    [.polyline(PolylineGeom(points: cur + [c]))] }
                switch a {
                case .point(let p): if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
                case .keyword("Bearing"):
                    guard let s = try await ed.getWord("Enter bearing (e.g. N45d30'00\"E)"), let dir = Bearings.parse(s, northAngle: north) else { ed.print("Invalid bearing."); continue }
                    guard let dist = try await ed.getDistance("Specify distance").value, dist > 0 else { continue }
                    pts.append(pts.last! + dir * dist)
                case .keyword("Close"): closed = true
                case .keyword("Undo"): if pts.count > 1 { pts.removeLast() }
                default: break
                }
                if closed { break }
                if case .none = a { break }
            }
            guard pts.count >= 2 else { return }
            if !closed, pts.count >= 3, pts.first!.isClose(pts.last!, tol: 1e-6) { pts.removeLast(); closed = true }
            if ed.doc.layer(named: "C-PROP") == nil { ed.doc.layers.append(Layer(name: "C-PROP", color: RGBA(0.95, 0.45, 0.35), linetype: "Phantom", lineweight: 0.35, description: "Property lines")) }
            let id = ed.addEntity(.polyline(PolylineGeom(points: pts, closed: closed)), layer: "C-PROP")
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["propertyLine"] = "1" }
            let n = closed ? pts.count : pts.count - 1
            for k in 0..<n {
                let a = pts[k], b = pts[(k + 1) % pts.count]
                ed.print("\(k + 1): \(Bearings.format(b - a, northAngle: north))  \(Bearings.distanceText(a.distance(to: b), units: ed.doc.units))")
            }
            if closed {
                let gap = 0.0
                _ = gap
                ed.print("Area: " + PlanRepresentation.formatArea(abs(GeometryOps.signedArea(pts)), ed.doc))
            }
        },
        CommandDef("SPOTSLOPE", aliases: ["SLOPELABEL"], category: "Annotate", summary: "Places live spot slopes (arrow pointing downhill with % and 1:n) on sloped slabs, ramps, roofs and toposurfaces.") { ed in
            let u = 1 / ed.doc.units.mm
            var n = 0
            while true {
                guard let p = try await ed.getPoint("Specify point on a sloped surface").point else { break }
                guard let s = SpotElevation.slope(at: p, doc: ed.doc, level: ed.doc.currentLevel) else { ed.print("The surface there is level."); continue }
                let len = ed.variableDouble("SPOTSLOPELEN", 1200 * u)
                let down = -s.uphill
                let id = ed.addEntity(.leader(LeaderGeom(points: [p + down * (len / 2), p - down * (len / 2)], text: SpotElevation.slopeText(s.grade), textHeight: ed.variableDouble("TEXTSIZE", 200 * u))), layer: "A-ANNO-TEXT")
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["spotSlope"] = "1"; ed.doc.entities[i].props["level"] = "\(ed.doc.currentLevel)" }
                ed.print("Spot slope " + SpotElevation.slopeText(s.grade))
                n += 1
            }
            if n > 1 { ed.print("\(n) spot slopes placed.") }
        },
        CommandDef("SPOTELEV", aliases: ["SPOTELEVATION", "SPOTLEVEL"], category: "Annotate", summary: "Places live spot elevations (slab tops, roofs, toposurface) with a leader.") { ed in
            let u = 1 / ed.doc.units.mm
            var n = 0
            while true {
                guard let p = try await ed.getPoint("Specify point to annotate").point else { break }
                let z = SpotElevation.value(at: p, doc: ed.doc, level: ed.doc.currentLevel)
                let label = SpotElevation.text(z, units: ed.doc.units)
                let q = try await ed.getPoint("Specify label location", base: p) { c in [.line(LineGeom(p, c))] }.point ?? (p + Vec2(600 * u, 600 * u))
                let id = ed.addEntity(.leader(LeaderGeom(points: [p, q], text: label, textHeight: ed.variableDouble("TEXTSIZE", 200 * u))), layer: "A-ANNO-TEXT")
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["spotElevation"] = "1"; ed.doc.entities[i].props["level"] = "\(ed.doc.currentLevel)" }
                ed.print("Spot elevation \(label)")
                n += 1
            }
            if n > 1 { ed.print("\(n) spot elevations placed.") }
        },
    ] }

    // MARK: - Worksets and design options

    static var sets: [CommandDef] { [
        CommandDef("WORKSET", aliases: ["WORKSETS"], category: "Manage", summary: "Worksets (named element sets): list, new, current, assign selection, hide/show, select members.") { ed in
            let k = try await ed.getKeyword("Workset option", ["List", "New", "Current", "Assign", "Hide", "Show", "Select"], defaultValue: "List") ?? "List"
            @MainActor func name(_ msg: String) async throws -> String? {
                guard let n = try await ed.getWord(msg, defaultValue: ed.doc.variable(Worksets.currentVariable)), !n.isEmpty else { return nil }
                return Worksets.all(ed.doc).first { $0.caseInsensitiveCompare(n) == .orderedSame } ?? n
            }
            switch k {
            case "New":
                guard let n = try await ed.getWord("Enter new workset name"), !n.isEmpty else { return }
                guard !n.contains("|") else { throw CommandError.invalid("Workset names cannot contain |.") }
                Worksets.declare(n, doc: &ed.doc); ed.doc.setVariable(Worksets.currentVariable, n)
                ed.print("Workset \"\(n)\" created and made current.")
            case "Current":
                guard let n = try await name("Enter workset to make current") else { return }
                Worksets.declare(n, doc: &ed.doc); ed.doc.setVariable(Worksets.currentVariable, n)
                ed.print("Current workset: \(n). New elements go there.")
            case "Assign":
                let ids = try await ed.getSelection("Select elements")
                guard let n = try await name("Enter workset") else { return }
                Worksets.declare(n, doc: &ed.doc)
                var c = 0
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props[Worksets.prop] = n == Worksets.defaultName ? nil : n; c += 1 } }
                ed.selection = []
                ed.print("\(c) element(s) moved to \(n).")
            case "Hide", "Show":
                guard let n = try await name("Enter workset to \(k.lowercased())") else { return }
                Worksets.setHidden(n, k == "Hide", doc: &ed.doc)
                ed.print("Workset \(n) \(k == "Hide" ? "hidden" : "shown").")
            case "Select":
                guard let n = try await name("Enter workset") else { return }
                ed.selection = Set(ed.doc.elements.filter { Worksets.name(of: $0.props).caseInsensitiveCompare(n) == .orderedSame }.map(\.id))
                ed.print("\(ed.selection.count) element(s) selected.")
            default:
                let counts = Worksets.counts(ed.doc), hidden = Worksets.hidden(ed.doc)
                let cur = ed.doc.variable(Worksets.currentVariable) ?? Worksets.defaultName
                for w in Worksets.all(ed.doc) {
                    ed.print("\(w.caseInsensitiveCompare(cur) == .orderedSame ? "*" : " ") \(w): \(counts[w] ?? 0) element(s)" + (hidden.contains(w.lowercased()) ? " (hidden)" : ""))
                }
            }
        },
        CommandDef("DESIGNOPTION", aliases: ["DESIGNOPTIONS", "DOPT"], category: "Manage", summary: "Design options: new set/option, add selection to an option, edit (new elements join it), view, primary, accept primary, list.") { ed in
            let k = try await ed.getKeyword("Design option", ["List", "New", "Add", "Edit", "View", "Primary", "Accept", "Main"], defaultValue: "List") ?? "List"
            var sets = DesignOptions.sets(ed.doc)
            @MainActor func pick(_ msg: String) async throws -> (Int, String)? {
                guard let s = try await ed.getWord(msg + " (Set:Option)"), let p = DesignOptions.parse(s) else { ed.print("Use Set:Option."); return nil }
                guard let i = sets.firstIndex(where: { $0.name.caseInsensitiveCompare(p.set) == .orderedSame }),
                      let o = sets[i].options.first(where: { $0.caseInsensitiveCompare(p.option) == .orderedSame }) else { ed.print("No option \(s)."); return nil }
                return (i, o)
            }
            switch k {
            case "New":
                guard let s = try await ed.getWord("Enter option set name, or Set:Option to add an option"), !s.isEmpty else { return }
                if let p = DesignOptions.parse(s) {
                    if let i = sets.firstIndex(where: { $0.name.caseInsensitiveCompare(p.set) == .orderedSame }) {
                        guard !sets[i].options.contains(where: { $0.caseInsensitiveCompare(p.option) == .orderedSame }) else { throw CommandError.invalid("Option exists.") }
                        sets[i].options.append(p.option)
                    } else { sets.append(DesignOptionSet(name: p.set, options: [p.option], primary: p.option)) }
                    ed.print("Option \(p.set):\(p.option) added.")
                } else {
                    guard !s.contains("|"), !sets.contains(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) else { throw CommandError.invalid("Invalid or existing set name.") }
                    sets.append(DesignOptionSet(name: s, options: ["Option 1", "Option 2"], primary: "Option 1"))
                    ed.print("Option set \(s) created with Option 1 (primary) and Option 2.")
                }
                DesignOptions.save(sets, doc: &ed.doc)
            case "Add":
                let ids = try await ed.getSelection("Select elements for the option")
                guard let (i, o) = try await pick("Enter option") else { return }
                var c = 0
                for id in ids { if let j = ed.doc.elementIndex(id) { ed.doc.elements[j].props[DesignOptions.prop] = "\(sets[i].name):\(o)"; c += 1 } }
                ed.selection = []
                ed.print("\(c) element(s) added to \(sets[i].name):\(o).")
            case "Edit":
                guard let (i, o) = try await pick("Enter option to edit") else { return }
                ed.doc.setVariable(DesignOptions.editingVariable, "\(sets[i].name):\(o)")
                var view = (ed.doc.variable(DesignOptions.viewVariable) ?? "").split(separator: "|").map(String.init).filter { DesignOptions.parse($0)?.set.caseInsensitiveCompare(sets[i].name) != .orderedSame }
                view.append("\(sets[i].name):\(o)")
                ed.doc.setVariable(DesignOptions.viewVariable, view.joined(separator: "|"))
                ed.print("Editing \(sets[i].name):\(o); new elements join it (DESIGNOPTION Main to return).")
            case "Main":
                ed.doc.variables[DesignOptions.editingVariable] = nil
                ed.print("Editing the main model.")
            case "View":
                guard let (i, o) = try await pick("Enter option to display") else { return }
                var view = (ed.doc.variable(DesignOptions.viewVariable) ?? "").split(separator: "|").map(String.init).filter { DesignOptions.parse($0)?.set.caseInsensitiveCompare(sets[i].name) != .orderedSame }
                if o.caseInsensitiveCompare(sets[i].primary) != .orderedSame { view.append("\(sets[i].name):\(o)") }
                ed.doc.setVariable(DesignOptions.viewVariable, view.joined(separator: "|"))
                ed.print("Showing \(sets[i].name):\(o).")
            case "Primary":
                guard let (i, o) = try await pick("Enter option to make primary") else { return }
                sets[i].primary = o
                DesignOptions.save(sets, doc: &ed.doc)
                ed.print("\(o) is now the primary option of \(sets[i].name).")
            case "Accept":
                guard let s = try await ed.getWord("Enter option set to accept (keeps its primary option)") else { return }
                guard let r = DesignOptions.acceptPrimary(s, doc: &ed.doc) else { throw CommandError.invalid("No option set \(s).") }
                ed.print("Primary option accepted: \(r.kept) element(s) joined the main model, \(r.removed) deleted.")
            default:
                if sets.isEmpty { ed.print("No design options."); return }
                let shown = DesignOptions.displayed(ed.doc)
                for s in sets {
                    for o in s.options {
                        let n = ed.doc.elements.filter { DesignOptions.parse($0.props[DesignOptions.prop]).map { $0.set.caseInsensitiveCompare(s.name) == .orderedSame && $0.option.caseInsensitiveCompare(o) == .orderedSame } ?? false }.count
                        let flags = (o == s.primary ? " (primary)" : "") + (shown[s.name.lowercased()]?.caseInsensitiveCompare(o) == .orderedSame ? " [shown]" : "")
                        ed.print("\(s.name):\(o) — \(n) element(s)\(flags)")
                    }
                }
            }
        },
    ] }

    // MARK: - Documentation

    static var documentation: [CommandDef] { [
        CommandDef("ROOMFINISH", aliases: ["ROOMFINISHES", "FINISHSCHEDULE"], category: "Architecture", summary: "Sets room floor/base/wall/ceiling finishes and places the room finish schedule.") { ed in
            let k = try await ed.getKeyword("Room finishes", ["Set", "Schedule", "List"], defaultValue: "Set") ?? "Set"
            switch k {
            case "Schedule":
                let p = try await ed.requirePoint("Specify schedule insertion point (top left)")
                let rows = RoomFinishes.rows(ed.doc)
                guard rows.count > 1 else { throw CommandError.invalid("No rooms.") }
                let u = 1 / ed.doc.units.mm, th = ed.variableDouble("TEXTSIZE", 200 * u)
                let widths = (0..<RoomFinishes.header.count).map { c in max(6, rows.map { $0[c].count }.max() ?? 6) }.map { Double($0) * th * 0.75 + th }
                let id = ed.addEntity(.table(TableGeom(origin: p, columnWidths: widths, rowHeight: th * 2, cells: [["ROOM FINISH SCHEDULE"] + Array(repeating: "", count: widths.count - 1)] + rows, textHeight: th)))
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["schedule"] = "roomFinishes" }
                ed.print("Room finish schedule placed (\(rows.count - 1) rooms).")
            case "List":
                for r in RoomFinishes.rows(ed.doc) { ed.print(r.joined(separator: " | ")) }
            default:
                let ids = try await ArchitectureCommands.elements(ed, "Select rooms", isSpace)
                guard !ids.isEmpty else { ed.print("No rooms selected."); return }
                let first = ed.doc.element(ids[0])!
                var vals: [String: String?] = [:]
                for (key, label) in zip(RoomFinishes.keys, ["floor", "base (skirting)", "wall", "ceiling"]) {
                    let v = try await ed.getString("Enter \(label) finish (. = clear, Enter = keep)", defaultValue: first.props[key] ?? "")
                    if let v = v, !v.isEmpty { vals[key] = v == "." ? .some(nil) : .some(v) }
                }
                for id in ids { guard let i = ed.doc.elementIndex(id) else { continue }; for (key, v) in vals { ed.doc.elements[i].props[key] = v } }
                ed.selection = []
                ed.print("Finishes set on \(ids.count) room(s).")
            }
        },
        CommandDef("COLORFILL", aliases: ["COLORSCHEME", "ROOMCOLORS", "AREACOLORS"], category: "Architecture", summary: "Colours rooms/areas by a parameter (name, department, area range, level, any property) and places a colour legend.") { ed in
            let k = try await ed.getKeyword("Colour fill", ["Scheme", "Legend", "Color", "Bin", "Off"], defaultValue: "Scheme") ?? "Scheme"
            switch k {
            case "Off": ed.doc.variables[AreaColors.variable] = nil; ed.print("Colour fill off.")
            case "Bin":
                let b = try await ed.getPositive("Specify area range width (m²)", defaultValue: ed.variableDouble("COLORFILLBIN", 10))
                ed.doc.setVariable("COLORFILLBIN", fmt(b)); ed.print("Area ranges of \(fmt(b)) m².")
            case "Color":
                guard let v = try await ed.getWord("Enter the value to colour"), let hex = try await ed.getWord("Enter colour as #RRGGBB"), AreaColors.parseHex(hex) != nil else { throw CommandError.invalid("Use #RRGGBB.") }
                var m = (ed.doc.variable("COLORFILLMAP") ?? "").split(separator: "|").map(String.init).filter { !$0.lowercased().hasPrefix(v.lowercased() + "=") }
                m.append("\(v)=\(hex)")
                ed.doc.setVariable("COLORFILLMAP", m.joined(separator: "|")); ed.print("\(v) coloured \(hex).")
            case "Legend":
                guard AreaColors.scheme(ed.doc) != nil else { throw CommandError.invalid("No colour scheme is active (COLORFILL Scheme).") }
                let p = try await ed.requirePoint("Specify legend position (top left)")
                let u = 1 / ed.doc.units.mm
                let geoms = AreaColors.legendGeometry(ed.doc, at: p, level: ed.doc.currentLevel, textHeight: ed.variableDouble("TEXTSIZE", 200 * u))
                for (g, c) in geoms {
                    let id = ed.addEntity(g, layer: "A-AREA")
                    if let c = c, let i = ed.doc.entityIndex(id) { ed.doc.entities[i].color = c }
                }
                ed.print("Colour legend placed (\(AreaColors.legend(ed.doc, level: ed.doc.currentLevel).count) entries).")
            default:
                guard let s = try await ed.getWord("Colour rooms by [Name/Number/Department/Area/Level or any property]", defaultValue: AreaColors.scheme(ed.doc) ?? "Department") else { return }
                ed.doc.setVariable(AreaColors.variable, s)
                let l = AreaColors.legend(ed.doc)
                ed.print("Colour fill by \(s): " + (l.isEmpty ? "no rooms have a value." : l.map { "\($0.value) (\($0.count))" }.joined(separator: ", ")))
            }
        },
        CommandDef("RCP", aliases: ["REFLECTEDCEILING", "CEILINGPLAN"], category: "View", summary: "Reflected ceiling plan on/off (ceilings with grids and heights, ceiling fixtures), and ceiling grid settings.") { ed in
            let k = try await ed.getKeyword("Reflected ceiling plan", ["On", "Off", "Grid"], defaultValue: ed.doc.variable("RCP") == "1" ? "Off" : "On") ?? "On"
            switch k {
            case "Grid":
                let ids = try await ArchitectureCommands.elements(ed, "Select ceilings") { if case .slab = $0 { return true }; return false }
                guard let g = try await ed.getWord("Enter grid module (600x600, 600x1200, None)", defaultValue: "600x600") else { return }
                let ang = try await ed.getAngle("Specify grid angle", defaultValue: 0).value ?? 0
                var n = 0
                for id in ids { if let i = ed.doc.elementIndex(id), ed.doc.elements[i].props["kind"] == "ceiling" { ed.doc.elements[i].props["ceilingGrid"] = g; ed.doc.elements[i].props["gridAngle"] = fmt(ang * 180 / .pi); n += 1 } }
                ed.selection = []
                ed.print("Grid \(g) set on \(n) ceiling(s).")
            case "Off": ed.doc.setVariable("RCP", "0"); ed.print("Floor plan display.")
            default: ed.doc.setVariable("RCP", "1"); ed.print("Reflected ceiling plan display (RCP Off to return).")
            }
        },
        CommandDef("AUTODIMWALLS", aliases: ["AUTODIMENSION", "WALLDIMS", "DIMWALLS"], category: "Annotate", summary: "Automatic dimension strings along wall faces through wall ends and openings, with an overall dimension.") { ed in
            let u = 1 / ed.doc.units.mm
            var ids = try await ArchitectureCommands.elements(ed, "Select walls (Enter = all walls on this level)", ArchitectureCommands.isWallGeom)
            if ids.isEmpty { ids = ed.doc.elements.filter { $0.level == ed.doc.currentLevel && ArchitectureCommands.isWallGeom($0.geometry) }.map(\.id) }
            guard !ids.isEmpty else { throw CommandError.invalid("No walls.") }
            let off = try await ed.getPositive("Specify offset from the wall face", defaultValue: ed.variableDouble("AUTODIMOFFSET", 800 * u))
            let withOpenings = try await ed.getYesNo("Dimension openings?", defaultValue: true)
            let chains = AutoDimension.wallChains(doc: ed.doc, walls: ids, offset: off, openings: withOpenings)
            var n = 0
            // Associative: the dimensions keep their walls and rebuild when walls or openings change (BIMUpdaters).
            for (g, props) in AutoDimensions.tagWallChains(chains, set: ids, offset: off, openings: withOpenings) {
                guard case .dimension(var dg) = g else { continue }
                dg.style = ed.doc.currentDimStyle
                let id = ed.addEntity(.dimension(dg), layer: "A-ANNO-DIMS")
                if let i = ed.doc.entityIndex(id) { for (k, v) in props { ed.doc.entities[i].props[k] = v } }
                n += 1
            }
            ed.doc.setVariable("AUTODIMOFFSET", fmt(off))
            ed.selection = []
            ed.print("\(n) dimension(s) on \(chains.count) wall(s).")
        },
        CommandDef("OPENINGPARTS", aliases: ["GLAZINGBARS", "WINDOWPARTS", "DOORPARTS"], category: "Architecture", summary: "Sets window mullions/transoms and door fanlights/thresholds on selected openings.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select doors and windows", ArchitectureCommands.isOpening)
            guard !ids.isEmpty else { return }
            let m = try await ed.getInteger("Number of vertical mullions (windows)", defaultValue: 0) ?? 0
            let t = try await ed.getInteger("Number of transoms (windows) / fanlight (doors, 0/1)", defaultValue: 0) ?? 0
            let th = try await ed.getYesNo("Door threshold?", defaultValue: false)
            guard m >= 0, m <= 20, t >= 0, t <= 20 else { throw CommandError.invalid("Use 0 to 20.") }
            for id in ids {
                guard let i = ed.doc.elementIndex(id), case .opening(var o) = ed.doc.elements[i].geometry else { continue }
                if o.kind == .window { o.mullions = m; o.transoms = t }
                if o.kind == .door { o.transoms = min(t, 1); o.threshold = th }
                ed.doc.elements[i].geometry = .opening(o)
            }
            ed.selection = []
            ed.print("\(ids.count) opening(s) updated.")
        },
    ] }
}
