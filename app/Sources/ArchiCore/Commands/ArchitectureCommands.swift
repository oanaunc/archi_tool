// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum ArchitectureCommands {
    static var all: [CommandDef] { walls + openings + horizontals + structure + spaces + management + extendedBIM + documentation + multiStorey + sheetViews + ModelingCommands.all + BIMExtCommands.all + BIMDetailCommands.all + BIMSystemCommands.all }

    static func wallPreview(_ w: WallGeom) -> Geometry { .polyline(PolylineGeom(points: CommandHelpers.wallRect(w), closed: true)) }
    static func footprintPreview(_ pts: [Vec2]) -> Geometry { .polyline(PolylineGeom(points: pts, closed: true)) }

    static func isWall(_ doc: ArchiDocument, _ id: EntityID) -> Bool { if case .wall? = doc.element(id)?.geometry { return true }; return false }

    /// Counter-clockwise copy of a polygon.
    static func ccw(_ p: [Vec2]) -> [Vec2] { GeometryOps.signedArea(p) < 0 ? p.reversed() : p }

    /// Polygon input: points (with Close/Undo) until Enter. Returns nil if fewer than 3 points.
    @MainActor static func polygonInput(_ ed: Editor, first: Vec2) async throws -> [Vec2]? {
        var pts = [first]
        while true {
            let cur = pts
            let a = try await ed.getPoint("Specify next point", base: pts.last, keywords: pts.count >= 3 ? ["Close", "Undo"] : ["Undo"]) { c in [footprintPreview(cur + [c])] }
            switch a {
            case .point(let p): if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
            case .keyword("Undo"): if pts.count > 1 { pts.removeLast() }
            default:
                let s = CommandHelpers.simplify(pts)
                return s.count >= 3 && abs(GeometryOps.signedArea(s)) > 1e-9 ? s : nil
            }
        }
    }

    /// Boundary picked from a closed drawing object.
    @MainActor static func selectBoundary(_ ed: Editor) async throws -> [Vec2]? {
        guard case .pick(let pk) = try await ed.pickObject("Select a closed polyline, circle or ellipse", filter: { ed.doc.entity($0) != nil }),
              let e = ed.doc.entity(pk.id), let loop = CommandHelpers.closedLoop(e.geometry) else { ed.print("Not a closed object."); return nil }
        return CommandHelpers.loopPoints(loop)
    }

    /// Outer boundary of the walls around a picked point (inner faces offset by the wall thickness).
    @MainActor static func wallsBoundary(_ ed: Editor, outside: Bool) async throws -> [Vec2]? {
        let p = try await ed.requirePoint("Pick a point inside the walls")
        guard let inner = RoomBounding.boundary(at: p, doc: ed.doc, level: ed.doc.currentLevel) else { ed.print("No closed wall loop found around that point."); return nil }
        guard outside else { return inner }
        let t = ed.doc.elements.compactMap { el -> Double? in if el.level == ed.doc.currentLevel, case .wall(let w) = el.geometry { return w.thickness }; return nil }.max() ?? 0
        return CommandHelpers.offsetPolygon(ccw(inner), t)
    }

    static func wallMaterial(_ doc: ArchiDocument, _ type: String?) -> String? {
        guard let t = type, let wt = doc.wallTypes.first(where: { $0.name == t }) else { return nil }
        return (wt.plies.first { $0.function == "Structure" } ?? wt.plies.first)?.material
    }

    // MARK: - Walls
    static var walls: [CommandDef] { [
        CommandDef("WALL", aliases: ["WA"], category: "Architecture", summary: "Draws a chain of joined walls (thickness, height, justification, type, arcs).") { ed in
            var s = ed.settings
            var wallType: String? = ed.doc.variable("WALLTYPE")
            var baseOffset = ed.variableDouble("WALLBASEOFFSET", 0)
            var topSpec = ed.doc.variable("WALLTOPLEVEL") ?? ""
            var topOffset = ed.variableDouble("WALLTOPOFFSET", 0)
            @MainActor func options(_ k: String) async throws {
                switch k {
                case "Top":
                    let t = try await ed.getWord("Top constraint: level name, Next (level above) or Unconnected", defaultValue: topSpec.isEmpty ? "Unconnected" : topSpec) ?? "Unconnected"
                    if t.lowercased().hasPrefix("u") && levelLookup(ed, t) == nil { topSpec = "" }
                    else if t.lowercased() == "next" || t.lowercased() == "n" { topSpec = "next" }
                    else if let l = levelLookup(ed, t) { topSpec = l.name }
                    else { ed.print("Level \(t) not found."); return }
                    if !topSpec.isEmpty { topOffset = try await ed.getDistance("Specify top offset from the level", defaultValue: topOffset).value ?? topOffset }
                    ed.doc.setVariable("WALLTOPLEVEL", topSpec); ed.doc.setVariable("WALLTOPOFFSET", fmt(topOffset))
                case "Thickness": s.wallThickness = try await ed.getPositive("Specify wall thickness", defaultValue: s.wallThickness); wallType = nil
                case "Height": s.wallHeight = try await ed.getPositive("Specify wall height", defaultValue: s.wallHeight)
                case "Justify":
                    let j = try await ed.getKeyword("Enter justification", ["Center", "Left", "Right"], defaultValue: s.wallJustification.rawValue.capitalized) ?? "Center"
                    s.wallJustification = WallJustification(rawValue: j.lowercased()) ?? .center
                case "Type":
                    let names = ed.doc.wallTypes.map(\.name)
                    guard let n = try await ed.getWord("Enter wall type name or [?]", defaultValue: wallType ?? names.first) else { return }
                    if n == "?" { ed.print("Wall types: " + ed.doc.wallTypes.map { "\"\($0.name)\" (\(fmt($0.thickness)))" }.joined(separator: ", ")); return }
                    guard let wt = ed.doc.wallTypes.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { ed.print("Wall type \(n) not found."); return }
                    wallType = wt.name; s.wallThickness = wt.thickness
                case "Base": baseOffset = try await ed.getDistance("Specify base offset from level", defaultValue: baseOffset).value ?? baseOffset
                default: break
                }
                ed.settings.wallThickness = s.wallThickness; ed.settings.wallHeight = s.wallHeight; ed.settings.wallJustification = s.wallJustification
                if let t = wallType { ed.doc.setVariable("WALLTYPE", t) } else { ed.doc.variables.removeValue(forKey: "WALLTYPE") }
                ed.doc.setVariable("WALLBASEOFFSET", fmt(baseOffset))
            }
            @MainActor func topID() -> Int? { topLevelID(ed.doc, spec: topSpec, from: ed.doc.currentLevel) }
            @MainActor func geom(_ a: Vec2, _ b: Vec2, bulge: Double = 0) -> WallGeom {
                var w = WallGeom(start: a, end: b, thickness: s.wallThickness, height: s.wallHeight, baseOffset: baseOffset, justification: s.wallJustification, bulge: bulge, wallType: wallType)
                if let t = topID(), let l = ed.doc.level(t) {
                    let h = l.elevation + topOffset - (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) - baseOffset
                    if h > 1e-6 { w.topLevel = t; w.topOffset = topOffset; w.height = h }
                }
                return w
            }
            var first: Vec2
            while true {
                let topText = topID().flatMap { ed.doc.level($0)?.name }.map { ", Top = up to \($0)" + (abs(topOffset) > 1e-9 ? " \(fmt(topOffset))" : "") } ?? ""
                ed.print("Current settings: Thickness = \(fmt(s.wallThickness)), Height = \(fmt(s.wallHeight)), Justify = \(s.wallJustification.rawValue)\(wallType.map { ", Type = \($0)" } ?? "")\(topText)")
                let a = try await ed.getPoint("Specify start point", keywords: ["Thickness", "Height", "Justify", "Type", "Base", "Top"])
                switch a {
                case .point(let p): first = p
                case .keyword(let k): try await options(k); continue
                default: return
                }
                break
            }
            var start = first
            var created: [EntityID] = []
            @MainActor func add(_ w: WallGeom) {
                let id = ed.doc.addElement(.wall(w), material: wallMaterial(ed.doc, wallType))
                if let prev = created.last, let pi = ed.doc.elementIndex(prev), let ni = ed.doc.elementIndex(id) {
                    ed.doc.elements[pi].props["joinEnd"] = "\(id)"; ed.doc.elements[ni].props["joinStart"] = "\(prev)"
                }
                created.append(id); start = w.end
            }
            while true {
                var kws = ["Arc", "Undo", "Thickness", "Height", "Justify", "Top"]
                if created.count >= 2 { kws.insert("Close", at: 1) }
                let st = start
                let a = try await ed.getPoint("Specify next point", base: start, keywords: kws) { c in c.distance(to: st) > 1e-9 ? [wallPreview(geom(st, c))] : [] }
                switch a {
                case .point(let p):
                    guard p.distance(to: start) > 1e-6 else { ed.print("Zero-length wall ignored."); continue }
                    add(geom(start, p))
                case .keyword("Arc"):
                    let m = try await ed.requirePoint("Specify point on arc", base: start)
                    let e = try await ed.requirePoint("Specify end point of arc", base: m) { c in [wallPreview(geom(st, c, bulge: CommandHelpers.bulge3(st, m, c)))] }
                    let b = CommandHelpers.bulge3(start, m, e)
                    guard e.distance(to: start) > 1e-6 else { continue }
                    add(geom(start, e, bulge: b))
                case .keyword("Close"):
                    add(geom(start, first))
                    if let f = created.first, let l = created.last, let fi = ed.doc.elementIndex(f), let li = ed.doc.elementIndex(l) {
                        ed.doc.elements[fi].props["joinStart"] = "\(l)"; ed.doc.elements[li].props["joinEnd"] = "\(f)"
                    }
                    ed.print("\(created.count) wall(s) created.")
                    return
                case .keyword("Undo"):
                    if let l = created.popLast(), let el = ed.doc.element(l), case .wall(let w) = el.geometry { ed.doc.remove(ids: [l]); start = w.start }
                    if let l = created.last, let i = ed.doc.elementIndex(l) { ed.doc.elements[i].props["joinEnd"] = nil }
                case .keyword(let k): try await options(k)
                default:
                    if !created.isEmpty { ed.print("\(created.count) wall(s) created.") }
                    return
                }
            }
        },
        CommandDef("CURTAINWALL", aliases: ["CW", "CURTAIN"], category: "Architecture", summary: "Draws glazed curtain walls with mullion grids.") { ed in
            var h = ed.settings.wallHeight
            var gu = ed.variableDouble("CWGRIDU", 1200), gv = ed.variableDouble("CWGRIDV", 1500)
            var start: Vec2
            while true {
                let a = try await ed.getPoint("Specify start point", keywords: ["Height", "GridU", "GridV"])
                switch a {
                case .point(let p): start = p
                case .keyword("Height"): h = try await ed.getPositive("Specify height", defaultValue: h); continue
                case .keyword("GridU"): gu = try await ed.getPositive("Specify vertical mullion spacing", defaultValue: gu); ed.doc.setVariable("CWGRIDU", fmt(gu)); continue
                case .keyword("GridV"): gv = try await ed.getPositive("Specify horizontal mullion spacing", defaultValue: gv); ed.doc.setVariable("CWGRIDV", fmt(gv)); continue
                default: return
                }
                break
            }
            var n = 0
            while true {
                let st = start
                guard let p = try await ed.getPoint("Specify next point", base: start, preview: { c in [wallPreview(WallGeom(start: st, end: c, thickness: 60))] }).point else { break }
                guard p.distance(to: start) > 1e-6 else { continue }
                ed.doc.addElement(.curtainWall(CurtainWallGeom(start: start, end: p, height: h, gridU: gu, gridV: gv)))
                start = p; n += 1
            }
            ed.print("\(n) curtain wall(s) created.")
        },
        CommandDef("WALLBYLINES", aliases: ["WALLFROMLINES", "WBL"], category: "Architecture", summary: "Converts selected lines, arcs and polylines into walls.") { ed in
            let ids = try await ed.getEntitySelection("Select lines, arcs or polylines")
            guard !ids.isEmpty else { return }
            let th = try await ed.getPositive("Specify wall thickness", defaultValue: ed.settings.wallThickness)
            let h = try await ed.getPositive("Specify wall height", defaultValue: ed.settings.wallHeight)
            let jk = try await ed.getKeyword("Justification (line is the wall's)", ["Center", "Left", "Right"], defaultValue: "Center") ?? "Center"
            let just = WallJustification(rawValue: jk.lowercased()) ?? .center
            let del = try await ed.getYesNo("Delete source objects?", defaultValue: false)
            var n = 0
            var used = Set<EntityID>()
            for id in ids {
                guard let e = ed.doc.entity(id), let v = CommandHelpers.polylineVertices(e.geometry) else { continue }
                if case .ellipse = e.geometry { continue }
                if case .spline = e.geometry { continue }
                let segs = v.closed ? v.vertices.count : v.vertices.count - 1
                var chain: [EntityID] = []
                for i in 0..<max(segs, 0) {
                    let a = v.vertices[i], b = v.vertices[(i + 1) % v.vertices.count]
                    guard a.p.distance(to: b.p) > 1e-6 else { continue }
                    let wid = ed.doc.addElement(.wall(WallGeom(start: a.p, end: b.p, thickness: th, height: h, justification: just, bulge: a.bulge)))
                    if let prev = chain.last, let pi = ed.doc.elementIndex(prev), let ni = ed.doc.elementIndex(wid) {
                        ed.doc.elements[pi].props["joinEnd"] = "\(wid)"; ed.doc.elements[ni].props["joinStart"] = "\(prev)"
                    }
                    chain.append(wid); n += 1
                }
                if !chain.isEmpty { used.insert(id) }
            }
            if del { ed.doc.remove(ids: used) }
            ed.selection = []
            ed.print("\(n) wall(s) created.")
        },
        CommandDef("WALLJOIN", aliases: ["WJ", "WALLCLEANUP"], category: "Architecture", summary: "Joins wall ends that nearly meet (extends/trims them to their intersection).") { ed in
            ed.selection = ed.selection.filter { isWall(ed.doc, $0) }
            var ids = try await ed.getSelection("Select walls (Enter = all walls on this level)").filter { isWall(ed.doc, $0) }
            if ids.isEmpty { ids = ed.doc.elements.filter { $0.level == ed.doc.currentLevel && isWall(ed.doc, $0.id) }.map(\.id) }
            var n = 0
            for i in 0..<ids.count { for j in (i + 1)..<max(ids.count, i + 1) {
                guard let ai = ed.doc.elementIndex(ids[i]), let bi = ed.doc.elementIndex(ids[j]),
                      case .wall(var a) = ed.doc.elements[ai].geometry, case .wall(var b) = ed.doc.elements[bi].geometry,
                      abs(a.bulge) < 1e-9, abs(b.bulge) < 1e-9 else { continue }
                let tol = max(a.thickness, b.thickness) * 1.5
                let x = GeometryOps.lineIntersection(a.start, a.end, b.start, b.end)
                var changed = false
                for ea in [true, false] { for eb in [true, false] {
                    let pa = ea ? a.start : a.end, pb = eb ? b.start : b.end
                    guard pa.distance(to: pb) <= tol, !pa.isClose(pb, tol: 1e-6) || (x != nil && !pa.isClose(x!, tol: 1e-6)) else { continue }
                    let target = x.flatMap { $0.distance(to: pa) <= tol * 2 ? $0 : nil } ?? (pa + pb) / 2
                    if ea { a.start = target } else { a.end = target }
                    if eb { b.start = target } else { b.end = target }
                    changed = true
                } }
                if changed && a.length > 1e-6 && b.length > 1e-6 {
                    ed.doc.elements[ai].geometry = .wall(a); ed.doc.elements[bi].geometry = .wall(b); n += 1
                }
            } }
            ed.selection = []
            ed.print("\(n) wall join(s) cleaned up.")
        },
    ] }

    // MARK: - Doors / windows / openings
    @MainActor static func placeOpening(_ ed: Editor, _ kind: OpeningKind) async throws {
        let key = kind.rawValue.uppercased()
        var width = ed.variableDouble(key + "WIDTH", kind == .door ? 900 : (kind == .window ? 1200 : 1000))
        var height = ed.variableDouble(key + "HEIGHT", kind == .door ? 2100 : (kind == .window ? 1200 : 2100))
        var sill = ed.variableDouble(key + "SILL", kind == .window ? 900 : 0)
        var doorStyle = DoorStyle(rawValue: ed.doc.variable("DOORSTYLE") ?? "") ?? .single
        var windowStyle = WindowStyle(rawValue: ed.doc.variable("WINDOWSTYLE") ?? "") ?? .casement
        var flip = false
        var n = 0
        var typeName: String? = kind == .opening ? nil : ed.doc.variable(key + "TYPE").flatMap { ed.doc.openingType($0)?.kind == kind ? $0 : nil }
        if let t = ed.doc.openingType(typeName) { width = t.width; height = t.height; sill = t.sill; doorStyle = t.doorStyle; windowStyle = t.windowStyle }
        @MainActor func save() {
            ed.doc.setVariable(key + "WIDTH", fmt(width)); ed.doc.setVariable(key + "HEIGHT", fmt(height)); ed.doc.setVariable(key + "SILL", fmt(sill))
            ed.doc.setVariable("DOORSTYLE", doorStyle.rawValue); ed.doc.setVariable("WINDOWSTYLE", windowStyle.rawValue)
        }
        while true {
            var kws = ["Width", "Height", "Sill", "Flip"]
            if kind != .opening { kws.insert("Style", at: 3); kws.append("Type") }
            ed.print("\(kind.rawValue.capitalized): " + (typeName.map { "Type = \($0), " } ?? "") + "Width = \(fmt(width)), Height = \(fmt(height)), Sill = \(fmt(sill))" + (kind == .door ? ", Style = \(doorStyle.rawValue)" : kind == .window ? ", Style = \(windowStyle.rawValue)" : ""))
            let a = try await ed.pickObject("Select wall location for the \(kind.rawValue)", keywords: kws) { isWall(ed.doc, $0) }
            switch a {
            case .keyword("Width"): width = try await ed.getPositive("Specify width", defaultValue: width); typeName = nil
            case .keyword("Height"): height = try await ed.getPositive("Specify height", defaultValue: height); typeName = nil
            case .keyword("Sill"): sill = try await ed.getPositive("Specify sill height", defaultValue: sill, allowZero: true); typeName = nil
            case .keyword("Type"):
                let types = ed.doc.openingTypes.filter { $0.kind == kind }
                guard let w = try await ed.getWord("Enter \(kind.rawValue) type name or [?]", defaultValue: typeName ?? types.first?.name) else { break }
                if w == "?" { ed.print("Types: " + types.map { "\"\($0.name)\"" }.joined(separator: ", ")); break }
                guard let t = types.first(where: { $0.name.caseInsensitiveCompare(w) == .orderedSame }) ?? types.first(where: { $0.name.lowercased().hasPrefix(w.lowercased()) }) else { ed.print("Type \(w) not found."); break }
                typeName = t.name; width = t.width; height = t.height; sill = t.sill; doorStyle = t.doorStyle; windowStyle = t.windowStyle
                ed.doc.setVariable(key + "TYPE", t.name)
            case .keyword("Flip"): flip.toggle(); ed.print("Hand \(flip ? "flipped" : "normal").")
            case .keyword("Style"):
                if kind == .door {
                    let s = try await ed.getWord("Door style [\(DoorStyle.allCases.map(\.rawValue).joined(separator: "/"))]", defaultValue: doorStyle.rawValue) ?? ""
                    if let d = DoorStyle.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(s.lowercased()) }) { doorStyle = d } else { ed.print("Unknown style.") }
                } else {
                    let s = try await ed.getWord("Window style [\(WindowStyle.allCases.map(\.rawValue).joined(separator: "/"))]", defaultValue: windowStyle.rawValue) ?? ""
                    if let w = WindowStyle.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) ?? WindowStyle.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(s.lowercased()) }) { windowStyle = w } else { ed.print("Unknown style.") }
                }
            case .pick(let pk):
                guard let host = ed.doc.element(pk.id), case .wall(let w) = host.geometry else { continue }
                let len = w.length
                guard len >= width else { ed.print("The wall (\(fmt(len))) is shorter than the \(kind.rawValue) width (\(fmt(width)))."); continue }
                guard sill + height <= w.height + 1e-6 else { ed.print("The \(kind.rawValue) is taller than the wall."); continue }
                let dir = w.direction
                let along = max(width / 2, min(len - width / 2, (pk.point - w.centerStart).dot(dir)))
                let overlaps = ed.doc.elements.contains { el in
                    guard case .opening(let o) = el.geometry, o.hostWall == pk.id else { return false }
                    return abs(o.offset - along) < (o.width + width) / 2 - 1e-6
                }
                if overlaps { ed.print("The \(kind.rawValue) would overlap an existing opening."); continue }
                let facing = dir.cross(pk.point - w.centerStart) < 0
                var o = OpeningGeom(kind: kind, hostWall: pk.id, offset: along, width: width, height: height, sill: sill, flipHand: flip, flipFacing: facing, doorStyle: doorStyle, windowStyle: windowStyle,
                                    typeName: typeName, mark: kind == .opening ? nil : nextMark(ed.doc, kind))
                if let t = ed.doc.openingType(typeName) { o.frameWidth = t.frameWidth }
                let oid = ed.doc.addElement(.opening(o), level: host.level, material: ed.doc.openingType(typeName)?.material,
                                            name: typeName ?? (kind == .door ? "Door \(fmt(width))x\(fmt(height))" : (kind == .window ? "Window \(fmt(width))x\(fmt(height))" : "Opening")))
                if ed.doc.variable("AUTOTAG") == "1", kind != .opening { addTag(ed, oid, field: "mark") }
                n += 1
            default:
                save()
                if n > 0 { ed.print("\(n) \(kind.rawValue)(s) placed.") }
                return
            }
            save()
        }
    }

    static var openings: [CommandDef] { [
        CommandDef("DOOR", aliases: ["DOORS"], category: "Architecture", summary: "Places doors in walls (default 900×2100).") { ed in try await placeOpening(ed, .door) },
        CommandDef("WINDOW", aliases: ["WIN"], category: "Architecture", summary: "Places windows in walls (default 1200×1200, sill 900).") { ed in try await placeOpening(ed, .window) },
        CommandDef("OPENING", aliases: ["WALLOPENING"], category: "Architecture", summary: "Cuts empty openings in walls.") { ed in try await placeOpening(ed, .opening) },
    ] }

    // MARK: - Slabs, ceilings, roofs
    @MainActor static func slab(_ ed: Editor, ceiling: Bool) async throws {
        let key = ceiling ? "CEILING" : "SLAB"
        var th = ed.variableDouble(key + "THICK", ceiling ? 20 : 200)
        var off = ed.variableDouble(key + "OFFSET", ceiling ? 2700 : 0)
        var boundary: [Vec2]? = nil
        while boundary == nil {
            let a = try await ed.getPoint("Specify first point of \(ceiling ? "ceiling" : "slab") boundary", keywords: ceiling ? ["Select", "Walls", "Thickness", "Offset", "Room"] : ["Select", "Walls", "Thickness", "Offset"])
            switch a {
            case .keyword("Room"):
                // Ceiling by room: the room outline at the room's height.
                let p = try await ed.requirePoint("Pick a point inside a room")
                guard let room = ed.doc.elements.first(where: { el in
                    if el.level == ed.doc.currentLevel, el.props["areaScheme"] == nil, case .space(let sp) = el.geometry { return GeometryOps.pointInPolygon(p, sp.boundary) }; return false }),
                      case .space(let sp) = room.geometry else { ed.print("No room there."); continue }
                boundary = sp.boundary; off = sp.height
            case .point(let p): guard let b = try await polygonInput(ed, first: p) else { throw CommandError.invalid("A boundary needs at least three points.") }; boundary = b
            case .keyword("Select"): boundary = try await selectBoundary(ed)
            case .keyword("Walls"): boundary = try await wallsBoundary(ed, outside: !ceiling)
            case .keyword("Thickness"): th = try await ed.getPositive("Specify thickness", defaultValue: th)
            case .keyword("Offset"): off = try await ed.getDistance(ceiling ? "Specify height of ceiling above level" : "Specify top offset from level", defaultValue: off).value ?? off
            default: return
            }
        }
        ed.doc.setVariable(key + "THICK", fmt(th)); ed.doc.setVariable(key + "OFFSET", fmt(off))
        let b = ccw(boundary!)
        let id = ed.doc.addElement(.slab(SlabGeom(boundary: b, thickness: th, topOffset: ceiling ? off + th : off)), name: ceiling ? "Ceiling" : "Floor")
        if ceiling, let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["kind"] = "ceiling"; ed.doc.elements[i].props["ceilingHeight"] = fmt(off); ed.doc.elements[i].material = "Plaster" }
        let per = CommandHelpers.polylineLength(b + [b[0]])
        ed.print("\(ceiling ? "Ceiling" : "Slab") created: " + CommandHelpers.areaMessage(area: abs(GeometryOps.signedArea(b)), perimeter: per, units: ed.doc.units))
    }

    static var horizontals: [CommandDef] { [
        CommandDef("SLAB", aliases: ["FLOOR", "SB"], category: "Architecture", summary: "Creates a floor slab from points, a closed object or the walls around a point.") { ed in try await slab(ed, ceiling: false) },
        CommandDef("CEILING", aliases: ["CEIL"], category: "Architecture", summary: "Creates a ceiling from points, a closed object or the walls around a point.") { ed in try await slab(ed, ceiling: true) },
        CommandDef("ROOF", aliases: ["RF"], category: "Architecture", summary: "Creates a flat, shed, gable or hip roof from a footprint.") { ed in
            var kind = RoofKind(rawValue: ed.doc.variable("ROOFKIND") ?? "") ?? .gable
            var pitch = ed.variableDouble("ROOFPITCH", 30)
            var overhang = ed.variableDouble("ROOFOVERHANG", 500)
            var th = ed.variableDouble("ROOFTHICK", 250)
            var base = ed.currentLevelHeight
            var boundary: [Vec2]? = nil
            while boundary == nil {
                ed.print("Roof: Kind = \(kind.rawValue), Pitch = \(fmt(pitch))°, Overhang = \(fmt(overhang)), Base = \(fmt(base))")
                let a = try await ed.getPoint("Specify first point of roof footprint", keywords: ["Select", "Walls", "Kind", "Pitch", "Overhang", "Base", "Thickness"])
                switch a {
                case .point(let p): guard let b = try await polygonInput(ed, first: p) else { throw CommandError.invalid("A footprint needs at least three points.") }; boundary = b
                case .keyword("Select"): boundary = try await selectBoundary(ed)
                case .keyword("Walls"): boundary = try await wallsBoundary(ed, outside: true)
                case .keyword("Kind"):
                    let k = try await ed.getKeyword("Roof kind", ["Flat", "Shed", "Gable", "Hip"], defaultValue: kind.rawValue.capitalized) ?? "Gable"
                    kind = RoofKind(rawValue: k.lowercased()) ?? .gable
                case .keyword("Pitch"):
                    if let v = try await ed.getReal("Specify roof pitch in degrees", defaultValue: pitch).value, v >= 0, v < 80 { pitch = v } else { ed.print("Pitch must be between 0 and 80°.") }
                case .keyword("Overhang"): overhang = try await ed.getPositive("Specify overhang", defaultValue: overhang, allowZero: true)
                case .keyword("Base"): base = try await ed.getDistance("Specify eave height above level", defaultValue: base).value ?? base
                case .keyword("Thickness"): th = try await ed.getPositive("Specify roof thickness", defaultValue: th)
                default: return
                }
            }
            ed.doc.setVariable("ROOFKIND", kind.rawValue); ed.doc.setVariable("ROOFPITCH", fmt(pitch)); ed.doc.setVariable("ROOFOVERHANG", fmt(overhang)); ed.doc.setVariable("ROOFTHICK", fmt(th))
            let b = ccw(boundary!)
            // Gable/shed: the longest edge is an eave.
            var eave = 0, longest = 0.0
            for i in 0..<b.count { let l = b[i].distance(to: b[(i + 1) % b.count]); if l > longest + 1e-9 { longest = l; eave = i } }
            ed.doc.addElement(.roof(RoofGeom(boundary: b, kind: kind, pitch: kind == .flat ? 0 : pitch, thickness: th, overhang: overhang, baseOffset: base, eaveEdge: eave)), name: "Roof")
            ed.print("\(kind.rawValue.capitalized) roof created over " + CommandHelpers.areaText(abs(GeometryOps.signedArea(b)), units: ed.doc.units) + ".")
        },
    ] }

    // MARK: - Stairs, railings, columns, beams
    static var structure: [CommandDef] { [
        CommandDef("STAIR", aliases: ["STAIRS"], category: "Architecture", summary: "Creates straight, L, U or spiral stairs between levels (width, rise or top level, risers, tread, landings).") { ed in
            var width = ed.variableDouble("STAIRWIDTH", 1000)
            var topLevel = topLevelID(ed.doc, spec: "next", from: ed.doc.currentLevel)
            let baseElev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            var rise = topLevel.flatMap { ed.doc.level($0) }.map { $0.elevation - baseElev } ?? ed.currentLevelHeight
            if rise <= 1e-6 { rise = ed.currentLevelHeight; topLevel = nil }
            var tread = ed.variableDouble("STAIRTREAD", 280)
            var risers: Int? = nil
            var kind = StairKind(rawValue: ed.doc.variable("STAIRKIND") ?? "") ?? .straight
            var landingAt: Int? = nil
            var landingDepth: Double? = nil
            var winders: Int? = ed.doc.variable("STAIRWINDERS").flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            var clockwise: Bool? = ed.doc.variable("STAIRHAND") == "Right" ? true : nil
            var innerRadius: Double? = nil
            var start: Vec2
            while true {
                let rc = risers ?? max(2, Int((rise / 175).rounded()))
                let top = topLevel.flatMap { ed.doc.level($0)?.name }.map { " up to \($0)" } ?? ""
                let land = landingAt.map { ", Landing after \($0) risers" } ?? ""
                let wind = (kind == .lShape || kind == .uShape) ? (winders.map { ", \($0) winders" } ?? "") : ""
                let hand = (kind != .straight && clockwise == true) ? ", turning right" : ""
                ed.print("Stair: \(kind.rawValue), Width = \(fmt(width)), Rise = \(fmt(rise))\(top), Risers = \(rc) (\(fmt(rise / Double(rc), 1)) each), Tread = \(fmt(tread))\(land)\(wind)\(hand)")
                let a = try await ed.getPoint("Specify start point of stair (bottom, center of first riser)", keywords: ["Width", "Rise", "Risers", "Tread", "Kind", "Top", "Landing", "Winders", "Hand", "Column"])
                switch a {
                case .point(let p): start = p
                case .keyword("Width"): width = try await ed.getPositive("Specify stair width", defaultValue: width); continue
                case .keyword("Rise"): rise = try await ed.getPositive("Specify total rise", defaultValue: rise); risers = nil; topLevel = nil; continue
                case .keyword("Top"):
                    guard let n = try await ed.getWord("Enter the level the stair arrives at", defaultValue: topLevel.flatMap { ed.doc.level($0)?.name }),
                          let l = levelLookup(ed, n), l.elevation > baseElev + 1e-6 else { ed.print("Choose a level above the current one."); continue }
                    topLevel = l.id; rise = l.elevation - baseElev; risers = nil; continue
                case .keyword("Risers"): if let n = try await ed.getInteger("Specify number of risers", defaultValue: rc), n >= 2, n <= 200 { risers = n } else { ed.print("Enter 2 to 200 risers.") }; continue
                case .keyword("Tread"): tread = try await ed.getPositive("Specify tread depth", defaultValue: tread); continue
                case .keyword("Kind"):
                    let k = try await ed.getKeyword("Stair kind", ["Straight", "LShape", "UShape", "Spiral"], defaultValue: "Straight") ?? "Straight"
                    kind = StairKind.allCases.first { $0.rawValue.lowercased() == k.lowercased() } ?? .straight; continue
                case .keyword("Landing"):
                    let def = landingAt ?? (rc + 1) / 2
                    guard let n = try await ed.getInteger("Risers before the landing (0 = none)", defaultValue: def) else { continue }
                    if n <= 0 { landingAt = nil; landingDepth = nil; continue }
                    guard n >= 2, n < rc else { ed.print("The landing must come after 2 to \(rc - 1) risers."); continue }
                    landingAt = n
                    landingDepth = try await ed.getPositive("Specify landing depth", defaultValue: landingDepth ?? width)
                    continue
                case .keyword("Winders"):
                    let def = winders ?? (kind == .uShape ? 6 : 3)
                    guard let n = try await ed.getInteger("Number of winder treads at the turn (0 = flat landing; L: 2–6, U: 3–10)", defaultValue: def) else { continue }
                    winders = n > 0 ? n : nil
                    if n > 0 && kind == .straight { kind = .lShape; ed.print("Kind set to LShape (winders need a turn).") }
                    continue
                case .keyword("Hand"):
                    let h = try await ed.getKeyword("Turn / wind direction", ["Left", "Right"], defaultValue: clockwise == true ? "Right" : "Left") ?? "Left"
                    clockwise = h == "Right" ? true : nil; continue
                case .keyword("Column"):
                    innerRadius = try await ed.getPositive("Specify spiral column (inner) radius", defaultValue: innerRadius ?? max(100, width * 0.15)); continue
                default: return
                }
                break
            }
            let rc = risers ?? max(2, Int((rise / 175).rounded()))
            let preview: (Vec2) -> [Geometry] = { c in
                let s = StairGeom(start: start, direction: (c - start).angle, width: width, totalRise: rise, riserCount: rc, treadDepth: tread, kind: kind, landingDepth: landingDepth, landingAt: landingAt,
                                  winders: winders, clockwise: clockwise, innerRadius: innerRadius)
                return StairShapes.layout(s).treads.map { footprintPreview($0.poly) }
            }
            let dir = try await ed.getAngle("Specify direction of travel (up)", base: start, defaultValue: 0, preview: preview).value ?? 0
            ed.doc.setVariable("STAIRWIDTH", fmt(width)); ed.doc.setVariable("STAIRTREAD", fmt(tread)); ed.doc.setVariable("STAIRKIND", kind.rawValue)
            ed.doc.setVariable("STAIRWINDERS", "\(winders ?? 0)"); ed.doc.setVariable("STAIRHAND", clockwise == true ? "Right" : "Left")
            let s = StairGeom(start: start, direction: dir, width: width, totalRise: rise, riserCount: rc, treadDepth: tread, kind: kind,
                              landingDepth: landingDepth, landingAt: landingAt, topLevel: topLevel, winders: winders, clockwise: clockwise, innerRadius: innerRadius)
            ed.doc.addElement(.stair(s), name: "Stair")
            ed.print("Stair created: \(rc) risers of \(fmt(s.riserHeight, 1))" + (topLevel.flatMap { ed.doc.level($0)?.name }.map { ", arriving at \($0)" } ?? "") + ".")
            for issue in BIMConstraints.stairIssues(s, units: ed.doc.units) { ed.print("Note: " + issue) }
        },
        CommandDef("RAILING", aliases: ["RAIL"], category: "Architecture", summary: "Draws a railing along a path.") { ed in
            var h = ed.variableDouble("RAILHEIGHT", 1000)
            var pts: [Vec2] = []
            while pts.isEmpty {
                let a = try await ed.getPoint("Specify start point of railing path", keywords: ["Height"])
                switch a {
                case .point(let p): pts = [p]
                case .keyword: h = try await ed.getPositive("Specify railing height", defaultValue: h)
                default: return
                }
            }
            while true {
                let cur = pts
                guard let p = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(PolylineGeom(points: cur + [c]))] }).point else { break }
                if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
            }
            guard pts.count >= 2 else { throw CommandError.invalid("A railing needs at least two points.") }
            ed.doc.setVariable("RAILHEIGHT", fmt(h))
            ed.doc.addElement(.railing(RailingGeom(path: pts, height: h)), name: "Railing")
        },
        CommandDef("COLUMN", aliases: ["COLUMNS"], category: "Architecture", summary: "Places structural columns (rectangular or round).") { ed in
            var w = ed.variableDouble("COLWIDTH", 300), d = ed.variableDouble("COLDEPTH", 300)
            var round = ed.doc.variable("COLROUND") == "1"
            var rot = 0.0
            var h = ed.currentLevelHeight
            var n = 0
            while true {
                let (cw, cd, cr, crot, ch) = (w, d, round, rot, h)
                let a = try await ed.getPoint("Specify column location", keywords: ["Width", "Depth", "Round", "Rotation", "Height"]) { c in
                    [footprintPreview(CommandHelpers.footprint(BIMElement(geometry: .column(ColumnGeom(position: c, width: cw, depth: cd, height: ch, rotation: crot, round: cr))), doc: ArchiDocument()))] }
                switch a {
                case .point(let p):
                    ed.doc.addElement(.column(ColumnGeom(position: p, width: w, depth: round ? w : d, height: h, rotation: rot, round: round)), name: round ? "Column Ø\(fmt(w))" : "Column \(fmt(w))x\(fmt(d))")
                    n += 1
                case .keyword("Width"): w = try await ed.getPositive(round ? "Specify diameter" : "Specify width", defaultValue: w)
                case .keyword("Depth"): d = try await ed.getPositive("Specify depth", defaultValue: d)
                case .keyword("Round"): round = try await ed.getYesNo("Round column?", defaultValue: !round)
                case .keyword("Rotation"): rot = try await ed.getAngle("Specify rotation", defaultValue: rot).value ?? rot
                case .keyword("Height"): h = try await ed.getPositive("Specify height", defaultValue: h)
                default:
                    ed.doc.setVariable("COLWIDTH", fmt(w)); ed.doc.setVariable("COLDEPTH", fmt(d)); ed.doc.setVariable("COLROUND", round ? "1" : "0")
                    if n > 0 { ed.print("\(n) column(s) placed.") }
                    return
                }
            }
        },
        CommandDef("BEAM", category: "Architecture", summary: "Draws structural beams between points.") { ed in
            var w = ed.variableDouble("BEAMWIDTH", 200), dp = ed.variableDouble("BEAMDEPTH", 400)
            var top = ed.currentLevelHeight
            var start: Vec2
            while true {
                let a = try await ed.getPoint("Specify beam start point", keywords: ["Width", "Depth", "Top"])
                switch a {
                case .point(let p): start = p
                case .keyword("Width"): w = try await ed.getPositive("Specify beam width", defaultValue: w); continue
                case .keyword("Depth"): dp = try await ed.getPositive("Specify beam depth", defaultValue: dp); continue
                case .keyword("Top"): top = try await ed.getDistance("Specify top of beam above level", defaultValue: top).value ?? top; continue
                default: return
                }
                break
            }
            ed.doc.setVariable("BEAMWIDTH", fmt(w)); ed.doc.setVariable("BEAMDEPTH", fmt(dp))
            var n = 0
            while true {
                let st = start
                guard let p = try await ed.getPoint("Specify beam end point", base: start, preview: { c in [wallPreview(WallGeom(start: st, end: c, thickness: w))] }).point else { break }
                guard p.distance(to: start) > 1e-6 else { continue }
                ed.doc.addElement(.beam(BeamGeom(start: start, end: p, width: w, depth: dp, topOffset: top)), name: "Beam \(fmt(w))x\(fmt(dp))")
                start = p; n += 1
            }
            ed.print("\(n) beam(s) created.")
        },
    ] }

    // MARK: - Rooms, grids, components, levels
    static func nextGridLabel(_ doc: ArchiDocument, numeric: Bool) -> String {
        let labels = doc.elements.compactMap { el -> String? in if case .gridLine(let g) = el.geometry { return g.label }; return nil }
        if numeric { return "\((labels.compactMap { Int($0) }.max() ?? 0) + 1)" }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ").map(String.init)
        func index(_ s: String) -> Int? {
            guard !s.isEmpty, s.allSatisfy({ $0.isLetter }) else { return nil }
            var v = 0
            for ch in s.uppercased() { guard let i = letters.firstIndex(of: String(ch)) else { return nil }; v = v * letters.count + i + 1 }
            return v
        }
        var n = (labels.compactMap(index).max() ?? 0) + 1
        var s = ""
        while n > 0 { let r = (n - 1) % letters.count; s = letters[r] + s; n = (n - 1) / letters.count }
        return s
    }

    static let componentPresets: [(String, String, Vec3)] = [
        ("Bed", "Furniture", Vec3(1600, 2000, 500)), ("Sofa", "Furniture", Vec3(2000, 900, 800)), ("Table", "Furniture", Vec3(1600, 900, 750)),
        ("Chair", "Furniture", Vec3(450, 500, 900)), ("WC", "Plumbing", Vec3(380, 700, 800)), ("Sink", "Plumbing", Vec3(600, 450, 850)),
        ("Bath", "Plumbing", Vec3(700, 1700, 550)), ("Kitchen", "Casework", Vec3(2400, 600, 900)), ("Wardrobe", "Casework", Vec3(1200, 600, 2200)),
        ("Desk", "Furniture", Vec3(1400, 700, 750)), ("Car", "Entourage", Vec3(1800, 4500, 1500)),
    ]

    /// Level id for a top-constraint spec: "" = none, "next" = the level above `from`, otherwise a level name or id.
    static func topLevelID(_ doc: ArchiDocument, spec: String, from: Int) -> Int? {
        if spec.isEmpty { return nil }
        if spec.lowercased() == "next" {
            let e = doc.level(from)?.elevation ?? 0
            return doc.levels.filter { $0.elevation > e + 1e-9 }.min { $0.elevation < $1.elevation }?.id
        }
        if let l = doc.levels.first(where: { $0.name.caseInsensitiveCompare(spec) == .orderedSame }) { return l.id }
        if let i = Int(spec), doc.level(i) != nil { return i }
        return nil
    }

    @MainActor static func levelLookup(_ ed: Editor, _ s: String) -> Level? {
        if let l = ed.doc.levels.first(where: { $0.name.caseInsensitiveCompare(s) == .orderedSame }) { return l }
        if let i = Int(s), let l = ed.doc.level(i) { return l }
        return nil
    }

    static var spaces: [CommandDef] { [
        CommandDef("ROOM", aliases: ["SPACE", "RM"], category: "Architecture", summary: "Places rooms bounded by walls (pick inside) or by points; reports area.") { ed in
            var name = ed.doc.variable("ROOMNAME") ?? "Room"
            var height = ed.variableDouble("ROOMHEIGHT", max(ed.currentLevelHeight - 300, 2000))
            var numberOverride: String? = nil
            let levelIndex = (ed.doc.levels.firstIndex { $0.id == ed.doc.currentLevel } ?? 0) + 1
            @MainActor func nextNumber() -> String {
                let nums = ed.doc.elements.compactMap { el -> Int? in if el.level == ed.doc.currentLevel, case .space(let s) = el.geometry { return Int(s.number) }; return nil }
                return "\(max(nums.max() ?? levelIndex * 100, levelIndex * 100) + 1)"
            }
            @MainActor func place(_ b: [Vec2]) {
                let poly = ccw(b)
                let num = numberOverride ?? nextNumber()
                numberOverride = nil
                ed.doc.addElement(.space(SpaceGeom(boundary: poly, name: name, number: num, height: height)), name: name)
                ed.print("Room \(num) \"\(name)\": " + CommandHelpers.areaMessage(area: abs(GeometryOps.signedArea(poly)), perimeter: CommandHelpers.polylineLength(poly + [poly[0]]), units: ed.doc.units))
            }
            while true {
                let a = try await ed.getPoint("Pick a point inside a room", keywords: ["Points", "Name", "Number", "Height"])
                switch a {
                case .point(let p):
                    if ed.doc.elements.contains(where: { el in
                        if el.level == ed.doc.currentLevel, el.props["areaScheme"] == nil, case .space(let s) = el.geometry { return GeometryOps.pointInPolygon(p, s.boundary) }; return false }) {
                        ed.print("A room is already placed there."); continue
                    }
                    guard let b = RoomBounding.boundary(at: p, doc: ed.doc, level: ed.doc.currentLevel, extraCurves: separators(ed.doc, level: ed.doc.currentLevel)) else { ed.print("No enclosing walls found (use Points)."); continue }
                    place(b)
                    if let last = ed.doc.elements.indices.last { ed.doc.elements[last].props["seedX"] = fmt(p.x, 6); ed.doc.elements[last].props["seedY"] = fmt(p.y, 6) }
                case .keyword("Points"):
                    let f = try await ed.requirePoint("Specify first point")
                    guard let b = try await polygonInput(ed, first: f) else { ed.print("A room needs at least three points."); continue }
                    place(b)
                case .keyword("Name"): name = try await ed.getWord("Enter room name", defaultValue: name) ?? name; ed.doc.setVariable("ROOMNAME", name)
                case .keyword("Number"): numberOverride = try await ed.getWord("Enter room number", defaultValue: nextNumber())
                case .keyword("Height"): height = try await ed.getPositive("Specify room height", defaultValue: height); ed.doc.setVariable("ROOMHEIGHT", fmt(height))
                default: return
                }
            }
        },
        CommandDef("GRID", aliases: ["GRIDLINE", "GR"], category: "Architecture", summary: "Places structural grid lines, auto-labelled 1,2,3 (vertical) and A,B,C (horizontal).") { ed in
            var label: String? = nil
            while true {
                let a = try await ed.getPoint("Specify grid line start point", keywords: ["Label"])
                switch a {
                case .keyword: label = try await ed.getWord("Enter label for the next grid line"); continue
                case .point(let s):
                    let e = try await ed.requirePoint("Specify grid line end point", base: s) { c in [.line(LineGeom(s, c))] }
                    guard e.distance(to: s) > 1e-6 else { continue }
                    let vertical = abs(e.y - s.y) > abs(e.x - s.x)
                    let l = label ?? nextGridLabel(ed.doc, numeric: vertical)
                    if ed.doc.elements.contains(where: { if case .gridLine(let g) = $0.geometry { return g.label == l }; return false }) { ed.print("Note: grid label \(l) is already used.") }
                    ed.doc.addElement(.gridLine(GridLineGeom(start: s, end: e, label: l)), name: "Grid \(l)")
                    ed.print("Grid \(l) created.")
                    label = nil
                default: return
                }
            }
        },
        CommandDef("COMPONENT", aliases: ["FURNITURE", "COMP", "FURN"], category: "Architecture", summary: "Places parametric furniture, fixtures, casework, cars and plants from the library (or a custom box); size flexes the family.") { ed in
            let def = ed.doc.variable("COMPONENT") ?? "Chair"
            var fam: ComponentFamily? = nil
            var k = def
            while true {
                guard let w = try await ed.getWord("Enter component type or [?/Custom]", defaultValue: def, keywords: ["?", "Custom"]) else { return }
                if w == "?" {
                    for c in Set(ComponentLibrary.families.map(\.category)).sorted() {
                        ed.print("\(c): " + ComponentLibrary.families.filter { $0.category == c }.map { "\($0.name.replacingOccurrences(of: " ", with: "")) (\(fmt($0.size.x))×\(fmt($0.size.y))×\(fmt($0.size.z)))" }.joined(separator: ", "))
                    }
                    continue
                }
                if w.caseInsensitiveCompare("Custom") == .orderedSame { k = "Custom"; break }
                guard let f = ComponentLibrary.family(w) else { ed.print("Unknown component \"\(w)\" (enter ? for the list)."); continue }
                fam = f; k = f.name.replacingOccurrences(of: " ", with: ""); break
            }
            ed.doc.setVariable("COMPONENT", k)
            var cat = fam?.category ?? "Furniture", size = fam?.size ?? Vec3(600, 600, 750)
            let base = fam?.baseOffset ?? 0
            if fam == nil {
                cat = try await ed.getWord("Enter category", defaultValue: "Furniture") ?? "Furniture"
                size.x = try await ed.getPositive("Specify width", defaultValue: size.x)
                size.y = try await ed.getPositive("Specify depth", defaultValue: size.y)
                size.z = try await ed.getPositive("Specify height", defaultValue: size.z)
            }
            if fam != nil { ComponentLibrary.ensureMaterials(&ed.doc) }
            var rot = 0.0
            var n = 0
            let famID = fam?.id
            while true {
                let (r, sz) = (rot, size)
                let a = try await ed.getPoint("Specify insertion point (center)", keywords: ["Rotation", "Size"]) { c in
                    let g = ComponentGeom(category: cat, position: c, rotation: r, size: sz, family: famID)
                    if let f = fam { return ComponentLibrary.worldSymbol(f, g).map { .polyline(PolylineGeom(points: $0.points, closed: $0.closed)) } }
                    return [footprintPreview(PlanRepresentation.componentPoly(g))] }
                switch a {
                case .point(let p):
                    ed.doc.addElement(.component(ComponentGeom(category: cat, position: p, rotation: rot, size: size, baseOffset: base, family: famID)), name: fam?.name ?? cat)
                    n += 1
                case .keyword("Rotation"): rot = try await ed.getAngle("Specify rotation angle", defaultValue: rot).value ?? rot
                case .keyword("Size"):
                    size.x = try await ed.getPositive("Specify width", defaultValue: size.x)
                    size.y = try await ed.getPositive("Specify depth", defaultValue: size.y)
                    size.z = try await ed.getPositive("Specify height", defaultValue: size.z)
                default: if n > 0 { ed.print("\(n) \((fam?.name ?? cat).lowercased())(s) placed.") }; return
                }
            }
        },
        CommandDef("LEVEL", aliases: ["LEVELS", "LV"], category: "Architecture", summary: "Lists, creates, sets, renames and deletes levels; sets elevation and height.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["List", "New", "Set", "Rename", "Delete", "Elevation", "Height"], defaultValue: "List") ?? "List"
            @MainActor func pickLevel(_ msg: String) async throws -> Level {
                let cur = ed.doc.level(ed.doc.currentLevel)?.name ?? ""
                guard let s = try await ed.getWord(msg, defaultValue: cur), let l = levelLookup(ed, s) else { throw CommandError.invalid("Level not found.") }
                return l
            }
            switch k {
            case "New":
                let top = ed.doc.levels.map { $0.elevation + $0.height }.max() ?? 0
                let name = try await ed.getWord("Enter level name", defaultValue: "Level \(ed.doc.levels.count)") ?? "Level"
                guard levelLookup(ed, name) == nil else { throw CommandError.invalid("Level \(name) already exists.") }
                let elev = try await ed.getDistance("Specify elevation", defaultValue: top).value ?? top
                let h = try await ed.getPositive("Specify floor-to-floor height", defaultValue: 3000)
                let id = (ed.doc.levels.map(\.id).max() ?? -1) + 1
                ed.doc.levels.append(Level(id: id, name: name, elevation: elev, height: h))
                ed.doc.levels.sort { $0.elevation < $1.elevation }
                ed.doc.currentLevel = id
                ed.print("Level \"\(name)\" created at \(fmt(elev)) and made current.")
            case "Set":
                let l = try await pickLevel("Enter level name or number to make current")
                ed.doc.currentLevel = l.id; ed.selection = []
                ed.print("Current level: \(l.name)")
            case "Rename":
                let l = try await pickLevel("Enter level to rename")
                guard let n = try await ed.getWord("Enter new name"), !n.isEmpty else { return }
                guard levelLookup(ed, n) == nil || levelLookup(ed, n)?.id == l.id else { throw CommandError.invalid("Level \(n) already exists.") }
                if let i = ed.doc.levels.firstIndex(where: { $0.id == l.id }) { ed.doc.levels[i].name = n }
            case "Delete":
                let l = try await pickLevel("Enter level to delete")
                guard ed.doc.levels.count > 1 else { throw CommandError.invalid("Cannot delete the only level.") }
                let count = ed.doc.elements.filter { $0.level == l.id }.count
                if count > 0 { guard try await ed.getYesNo("Level has \(count) element(s). Delete them too?", defaultValue: false) else { return } }
                ed.doc.remove(ids: Set(ed.doc.elements.filter { $0.level == l.id }.map(\.id)))
                ed.doc.levels.removeAll { $0.id == l.id }
                if ed.doc.currentLevel == l.id { ed.doc.currentLevel = ed.doc.levels[0].id }
                ed.print("Level \(l.name) deleted.")
            case "Elevation":
                let l = try await pickLevel("Enter level")
                guard let v = try await ed.getDistance("Specify elevation", defaultValue: l.elevation).value else { return }
                if let i = ed.doc.levels.firstIndex(where: { $0.id == l.id }) { ed.doc.levels[i].elevation = v }
                ed.doc.levels.sort { $0.elevation < $1.elevation }
                let n = BIMConstraints.sync(&ed.doc)
                if n > 0 { ed.print("\(n) constrained wall(s)/stair(s) updated.") }
            case "Height":
                let l = try await pickLevel("Enter level")
                let v = try await ed.getPositive("Specify floor-to-floor height", defaultValue: l.height)
                if let i = ed.doc.levels.firstIndex(where: { $0.id == l.id }) { ed.doc.levels[i].height = v }
                BIMConstraints.sync(&ed.doc)
            default:
                for l in ed.doc.levels {
                    let n = ed.doc.elements.filter { $0.level == l.id }.count
                    ed.print("\(l.id == ed.doc.currentLevel ? "*" : " ") [\(l.id)] \(l.name): elevation \(fmt(l.elevation)), height \(fmt(l.height)), \(n) element(s)")
                }
            }
        },
    ] }

    // MARK: - Massing, schedules, properties
    static func fallbackSchedule(_ doc: ArchiDocument, _ kind: String) -> String {
        var rows: [[String]] = []
        func q(_ s: String) -> String { s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let lvl: (Int) -> String = { id in doc.level(id)?.name ?? "\(id)" }
        switch kind {
        case "walls":
            rows = [["ID", "Level", "Type", "Length", "Thickness", "Height"]]
            for el in doc.elements { if case .wall(let w) = el.geometry { rows.append(["\(el.id)", lvl(el.level), w.wallType ?? "Generic", fmt(w.length, 1), fmt(w.thickness), fmt(w.height)]) } }
        case "doors", "windows":
            rows = [["ID", "Level", "Name", "Width", "Height", "Sill", "Host"]]
            for el in doc.elements { if case .opening(let o) = el.geometry, o.kind.rawValue + "s" == kind { rows.append(["\(el.id)", lvl(el.level), el.name, fmt(o.width), fmt(o.height), fmt(o.sill), "\(o.hostWall)"]) } }
        case "rooms":
            rows = [["Number", "Name", "Level", "Area (m²)", "Perimeter", "Height"]]
            for el in doc.elements { if case .space(let s) = el.geometry {
                rows.append([s.number, s.name, lvl(el.level), fmt(abs(GeometryOps.signedArea(s.boundary)) * doc.units.mm * doc.units.mm / 1e6, 2), fmt(CommandHelpers.polylineLength(s.boundary + [s.boundary.first ?? .zero]), 0), fmt(s.height)]) } }
        case "slabs":
            rows = [["ID", "Level", "Name", "Area (m²)", "Thickness"]]
            for el in doc.elements { if case .slab(let s) = el.geometry { rows.append(["\(el.id)", lvl(el.level), el.name, fmt(abs(GeometryOps.signedArea(s.boundary)) * doc.units.mm * doc.units.mm / 1e6, 2), fmt(s.thickness)]) } }
        default:
            rows = [["ID", "Type", "Level", "Name", "Layer", "Material"]]
            for el in doc.elements { rows.append(["\(el.id)", el.typeName, lvl(el.level), el.name, el.layer, el.material ?? ""]) }
        }
        return rows.map { $0.map(q).joined(separator: ",") }.joined(separator: "\n")
    }

    /// Schedules with marks, types, type parameters, room volumes, area schemes and keynotes (nil = use ScheduleExporter).
    static func scheduleCSV(_ doc: ArchiDocument, _ kind: String) -> String? {
        func q(_ s: String) -> String { s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let lvl: (Int) -> String = { id in doc.level(id)?.name ?? "\(id)" }
        let m2 = doc.units.mm * doc.units.mm / 1e6, m3 = pow(doc.units.mm, 3) / 1e9
        var rows: [[String]] = []
        switch kind {
        case "doors", "windows":
            let want: OpeningKind = kind == "doors" ? .door : .window
            let keys = Array(Set(doc.openingTypes.filter { $0.kind == want }.flatMap { $0.params.keys })).sorted()
            rows = [["Mark", "Level", "Type", "Width", "Height", "Sill", "Style", "Host"] + keys]
            var items: [(String, [String])] = []
            for el in doc.elements {
                guard case .opening(let o) = el.geometry, o.kind == want else { continue }
                let t = doc.openingType(o.typeName)
                let style = want == .door ? o.doorStyle.rawValue : o.windowStyle.rawValue
                let mark = o.mark ?? "\(el.id)"
                items.append((mark, [mark, lvl(el.level), o.typeName ?? el.name, fmt(o.width), fmt(o.height), fmt(o.sill), style, "\(o.hostWall)"] + keys.map { t?.params[$0] ?? "" }))
            }
            rows += items.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.map(\.1)
        case "rooms":
            rows = [["Number", "Name", "Level", "Area (m²)", "Perimeter", "Height", "Volume (m³)"]]
            for el in doc.elements {
                guard case .space(let s) = el.geometry, el.props["areaScheme"] == nil else { continue }
                let a = abs(GeometryOps.signedArea(s.boundary))
                rows.append([s.number, s.name, lvl(el.level), fmt(a * m2, 2), fmt(CommandHelpers.polylineLength(s.boundary + [s.boundary.first ?? .zero]), 0), fmt(s.height), fmt(a * s.height * m3, 2)])
            }
        case "areas":
            rows = [["Scheme", "Name", "Level", "Area (m²)"]]
            var totals: [String: Double] = [:]
            for el in doc.elements {
                guard case .space(let s) = el.geometry, let sc = el.props["areaScheme"] else { continue }
                let a = abs(GeometryOps.signedArea(s.boundary)) * m2
                totals[sc, default: 0] += a
                rows.append([sc, s.name, lvl(el.level), fmt(a, 2)])
            }
            for (k, v) in totals.sorted(by: { $0.key < $1.key }) { rows.append([k, "Total", "", fmt(v, 2)]) }
        case "types":
            let keys = Array(Set(doc.openingTypes.flatMap { $0.params.keys })).sorted()
            rows = [["Type", "Kind", "Width", "Height", "Sill", "Style", "Count"] + keys]
            for t in doc.openingTypes {
                let n = doc.elements.filter { if case .opening(let o) = $0.geometry { return o.typeName == t.name }; return false }.count
                rows.append([t.name, t.kind.rawValue, fmt(t.width), fmt(t.height), fmt(t.sill), t.kind == .door ? t.doorStyle.rawValue : t.windowStyle.rawValue, "\(n)"] + keys.map { t.params[$0] ?? "" })
            }
        case "keynotes":
            rows = [["Key", "Description", "Count"]]
            for (k, v) in doc.keynotes.sorted(by: { $0.key < $1.key }) { rows.append([k, v, "\(doc.elements.filter { $0.props["keynote"] == k }.count)"]) }
        default: return nil
        }
        return rows.map { $0.map(q).joined(separator: ",") }.joined(separator: "\n")
    }

    static func parseCSV(_ s: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cur = "", inQ = false
        var chars = Array(s), i = 0
        while i < chars.count {
            let c = chars[i]
            if inQ {
                if c == "\"" { if i + 1 < chars.count && chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { inQ = false } } else { cur.append(c) }
            } else {
                switch c {
                case "\"": inQ = true
                case ",", ";": row.append(cur); cur = ""
                case "\n": row.append(cur); cur = ""; rows.append(row); row = []
                case "\r": break
                default: cur.append(c)
                }
            }
            i += 1
        }
        if !cur.isEmpty || !row.isEmpty { row.append(cur); rows.append(row) }
        chars = []
        return rows
    }

    static var management: [CommandDef] { [
        CommandDef("BUILDING", aliases: ["MASS", "QUICKBUILDING"], category: "Architecture", summary: "Quick massing: a rectangle becomes walls, floor slabs and a roof on one or more storeys.") { ed in
            var th = ed.settings.wallThickness
            var storeys = 1
            var roofKind = RoofKind(rawValue: ed.doc.variable("ROOFKIND") ?? "") ?? .gable
            var c1: Vec2
            while true {
                let a = try await ed.getPoint("Specify first corner of building", keywords: ["Thickness", "Storeys", "Roof"])
                switch a {
                case .point(let p): c1 = p
                case .keyword("Thickness"): th = try await ed.getPositive("Specify wall thickness", defaultValue: th); continue
                case .keyword("Storeys"): if let n = try await ed.getInteger("Enter number of storeys", defaultValue: storeys), n >= 1, n <= 100 { storeys = n }; continue
                case .keyword("Roof"):
                    let k = try await ed.getKeyword("Roof kind", ["Flat", "Shed", "Gable", "Hip", "None"], defaultValue: roofKind.rawValue.capitalized) ?? "Gable"
                    if k == "None" { ed.doc.setVariable("BUILDINGROOF", "none") } else { roofKind = RoofKind(rawValue: k.lowercased()) ?? .gable; ed.doc.setVariable("BUILDINGROOF", "yes") }
                    continue
                default: return
                }
                break
            }
            let c2 = try await ed.requirePoint("Specify opposite corner", base: c1) { c in [.polyline(PolylineGeom(points: BBox2(points: [c1, c]).corners, closed: true))] }
            let box = BBox2(points: [c1, c2])
            guard box.width > th * 2, box.height > th * 2 else { throw CommandError.invalid("The building is too small for the wall thickness.") }
            let baseLevel = ed.doc.level(ed.doc.currentLevel) ?? Level(id: 0, name: "Ground Floor", elevation: 0)
            var levelIDs: [Int] = []
            var elev = baseLevel.elevation
            var height = baseLevel.height
            for s in 0..<storeys {
                if s == 0 { levelIDs.append(baseLevel.id); continue }
                elev += height
                if let l = ed.doc.levels.first(where: { abs($0.elevation - elev) < 1 }) { levelIDs.append(l.id); height = l.height }
                else {
                    let id = (ed.doc.levels.map(\.id).max() ?? -1) + 1
                    ed.doc.levels.append(Level(id: id, name: "Level \(s + 1)", elevation: elev, height: height)); levelIDs.append(id)
                }
            }
            ed.doc.levels.sort { $0.elevation < $1.elevation }
            let corners = box.corners
            let outer = CommandHelpers.offsetPolygon(corners, th / 2)
            var walls = 0
            for lid in levelIDs {
                let h = ed.doc.level(lid)?.height ?? 3000
                var ids: [EntityID] = []
                for i in 0..<4 { ids.append(ed.doc.addElement(.wall(WallGeom(start: corners[i], end: corners[(i + 1) % 4], thickness: th, height: h)), level: lid)); walls += 1 }
                for i in 0..<4 {
                    if let a = ed.doc.elementIndex(ids[i]) { ed.doc.elements[a].props["joinEnd"] = "\(ids[(i + 1) % 4])"; ed.doc.elements[a].props["joinStart"] = "\(ids[(i + 3) % 4])" }
                }
                ed.doc.addElement(.slab(SlabGeom(boundary: outer, thickness: 200, topOffset: 0)), level: lid, name: "Floor")
            }
            var roofMsg = ""
            if ed.doc.variable("BUILDINGROOF") != "none", let top = levelIDs.last {
                let h = ed.doc.level(top)?.height ?? 3000
                var eave = 0
                if box.height > box.width { eave = 1 }
                ed.doc.addElement(.roof(RoofGeom(boundary: outer, kind: roofKind, pitch: roofKind == .flat ? 0 : ed.variableDouble("ROOFPITCH", 30), overhang: ed.variableDouble("ROOFOVERHANG", 500), baseOffset: h, eaveEdge: eave)), level: top, name: "Roof")
                roofMsg = " and a \(roofKind.rawValue) roof"
            }
            ed.print("Building created: \(walls) walls, \(levelIDs.count) floor slab(s)\(roofMsg). Footprint " + CommandHelpers.areaText(abs(GeometryOps.signedArea(outer)), units: ed.doc.units) + ".")
        },
        CommandDef("SCHEDULE", aliases: ["SCH"], category: "Architecture", summary: "Creates a schedule table (walls, doors, windows, rooms, slabs) or prints it.") { ed in
            let k = try await ed.getKeyword("Enter schedule type", ["Walls", "Doors", "Windows", "Rooms", "Slabs", "Types", "Areas", "Keynotes", "Lighting", "Systems", "All"], defaultValue: "Rooms") ?? "Rooms"
            let kind = k.lowercased()
            // Schedules count what SCHEDULEFILTER selects (default: what the views show — worksets, design options, systems).
            let sd = ModelSets.scheduleModel(ed.doc)
            var rows: [[String]]
            if kind == "lighting" { rows = LightingFixtures.scheduleRows(doc: sd) }
            else if kind == "systems" { rows = MEPNetworks.scheduleRows(doc: sd) }
            else {
                var csv = scheduleCSV(sd, kind) ?? ScheduleExporter.csv(doc: sd, kind: kind)
                if csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { csv = fallbackSchedule(sd, kind) }
                rows = parseCSV(csv).filter { !$0.allSatisfy { $0.isEmpty } }
            }
            guard let p = try await ed.getPoint("Specify insertion point (Enter = print to command line)").point else {
                for r in rows { ed.print(r.joined(separator: "\t")) }
                return
            }
            let th = ed.settings.textHeight
            let cols = rows.map(\.count).max() ?? 1
            var widths = Array(repeating: th * 4, count: cols)
            for r in rows { for (i, c) in r.enumerated() { widths[i] = max(widths[i], Double(c.count) * th * 0.75 + th * 1.5) } }
            let cells = [["\(k) schedule"] + Array(repeating: "", count: cols - 1)] + rows.map { $0 + Array(repeating: "", count: cols - $0.count) }
            ed.addEntity(.table(TableGeom(origin: p, columnWidths: widths, rowHeight: th * 2, cells: cells, textHeight: th)), layer: ed.annotationLayer("TEXTLAYER"))
            ed.print("Schedule with \(max(rows.count - 1, 0)) row(s) created.")
        },
        CommandDef("SETPROP", aliases: ["SP", "SETPROPERTY"], category: "Architecture", summary: "Sets any property of objects: SETPROP #12 height 2800.") { ed in
            var ids = Array(ed.selection)
            if ids.isEmpty {
                guard case .pick(let pk) = try await ed.pickObject("Select object") else { return }
                ids = [pk.id]
            }
            guard let first = ids.first else { return }
            let names = PropertyAccess.properties(of: first, in: ed.doc).filter { !$0.readOnly }.map(\.name)
            guard let name = try await ed.getWord("Enter property name or [?]") else { return }
            if name == "?" {
                for p in PropertyAccess.properties(of: first, in: ed.doc) { ed.print("  \(p.name) = \(p.value)\(p.readOnly ? " (read-only)" : "")") }
                return
            }
            let current = PropertyAccess.properties(of: first, in: ed.doc).first { $0.name.lowercased() == name.lowercased() }?.value
            guard let value = try await ed.getWord("Enter new value for \(name)", defaultValue: current) else { return }
            var ok = 0, failed = 0
            var doc = ed.doc
            for id in ids { if PropertyAccess.set(name, value, of: id, in: &doc) { ok += 1 } else { failed += 1 } }
            ed.doc = doc
            if ok > 0 { ed.print("\(name) = \(value) set on \(ok) object(s).") }
            if failed > 0 { ed.print("\(failed) object(s) do not accept \(name) = \(value). Settable: " + names.joined(separator: ", ")) }
        },
        CommandDef("PROPERTIES", aliases: ["PR", "PROPS", "GETPROP"], category: "Architecture", summary: "Shows the properties of the selected object(s).", modifies: false) { ed in
            ed.host?.perform(.showPanel("Properties"), editor: ed)
            var ids = Array(ed.selection)
            if ids.isEmpty, ed.host == nil || ed.activeCommand != nil {
                if case .pick(let pk) = try await ed.pickObject("Select object") { ids = [pk.id] }
            }
            for id in ids.sorted().prefix(20) {
                ed.print("#\(id):")
                for p in PropertyAccess.properties(of: id, in: ed.doc) { ed.print("  \(p.name) = \(p.value)\(p.readOnly ? " (read-only)" : "")") }
            }
        },
    ] }
}

// MARK: - Extended BIM tools: ramps, sloped slabs, foundations, niches, sweeps, curtain grids, rooms, areas, phases

extension ArchitectureCommands {
    static var extendedBIM: [CommandDef] { [rampCommand, slabSlopeCommand, foundationCommand, nicheCommand, wallSweepCommand, curtainGridCommand,
                                            roomSeparatorCommand, roomUpdateCommand, areaPlanCommand, phaseCommand] }

    @MainActor static func elements(_ ed: Editor, _ msg: String, _ pred: @escaping (BIMGeometry) -> Bool) async throws -> [EntityID] {
        ed.selection = ed.selection.filter { id in ed.doc.element(id).map { pred($0.geometry) } ?? false }
        let ids = try await ed.getSelection(msg)
        return ids.filter { id in ed.doc.element(id).map { pred($0.geometry) } ?? false }
    }

    static func isSlab(_ g: BIMGeometry) -> Bool { if case .slab = g { return true }; return false }
    static func isWallGeom(_ g: BIMGeometry) -> Bool { if case .wall = g { return true }; return false }

    static var rampCommand: CommandDef {
        CommandDef("RAMP", category: "Architecture", summary: "Creates a sloped ramp (straight or along a path with turns), with landings between flights; warns above 1:12.") { ed in
            var width = ed.variableDouble("RAMPWIDTH", 1200), rise = ed.variableDouble("RAMPRISE", 500), th = ed.variableDouble("RAMPTHICK", 200)
            var maxRise = ed.variableDouble("RAMPMAXRISE", 0), landing = ed.variableDouble("RAMPLANDING", 1500)
            var start: Vec2
            var usePath = false
            while true {
                ed.print("Ramp: Width = \(fmt(width)), Rise = \(fmt(rise)), Thickness = \(fmt(th))" + (maxRise > 0 ? ", Landings every \(fmt(maxRise)) rise (\(fmt(landing)) long)" : ""))
                let a = try await ed.getPoint("Specify bottom of ramp (center of the start edge)", keywords: ["Width", "Rise", "Thickness", "Landings", "Path", "Top"])
                switch a {
                case .point(let p): start = p
                case .keyword("Width"): width = try await ed.getPositive("Specify ramp width", defaultValue: width); continue
                case .keyword("Rise"): rise = try await ed.getPositive("Specify total rise", defaultValue: rise); continue
                case .keyword("Top"):
                    guard let n = try await ed.getWord("Enter the level the ramp arrives at"), let l = levelLookup(ed, n),
                          l.elevation > (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) + 1e-6 else { ed.print("Choose a level above the current one."); continue }
                    rise = l.elevation - (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0); continue
                case .keyword("Thickness"): th = try await ed.getPositive("Specify ramp thickness", defaultValue: th); continue
                case .keyword("Landings"):
                    maxRise = try await ed.getPositive("Specify maximum rise of one flight (0 = no landings)", defaultValue: maxRise > 0 ? maxRise : 500, allowZero: true)
                    if maxRise > 0 { landing = try await ed.getPositive("Specify landing length", defaultValue: landing) }
                    continue
                case .keyword("Path"): usePath = true; continue
                default: return
                }
                break
            }
            var path = [start]
            let w = width
            if usePath {
                while true {
                    let cur = path
                    guard let p = try await ed.getPoint("Specify next point of the ramp center line", base: path.last, preview: { c in [.polyline(PolylineGeom(points: cur + [c]))] }).point else { break }
                    if p.distance(to: path.last!) > 1e-6 { path.append(p) }
                }
            } else {
                path.append(try await ed.requirePoint("Specify top of ramp", base: start) { c in
                    let n = (c - start).normalized.perp * (w / 2)
                    return [footprintPreview([start - n, c - n, c + n, start + n])]
                })
            }
            guard path.count >= 2 else { throw CommandError.invalid("The ramp needs a length.") }
            ed.doc.setVariable("RAMPWIDTH", fmt(width)); ed.doc.setVariable("RAMPRISE", fmt(rise)); ed.doc.setVariable("RAMPTHICK", fmt(th))
            ed.doc.setVariable("RAMPMAXRISE", fmt(maxRise)); ed.doc.setVariable("RAMPLANDING", fmt(landing))
            guard let pieces = RampLayout.build(path: path, width: width, rise: rise, thickness: th, maxRise: maxRise, landingLength: landing) else {
                throw CommandError.invalid("The ramp is too short for its turns and landings.")
            }
            var group: EntityID? = nil
            var run = 0.0
            for pc in pieces {
                let id = ed.doc.addElement(.slab(pc.slab), name: pc.landing ? "Ramp Landing" : "Ramp")
                if let i = ed.doc.elementIndex(id) {
                    ed.doc.elements[i].props["kind"] = pc.landing ? "landing" : "ramp"
                    if pieces.count > 1 { ed.doc.elements[i].props["rampGroup"] = "\(group ?? id)" }
                }
                if group == nil { group = id }
                if !pc.landing, pc.slab.boundary.count == 4 { run += pc.slab.boundary[0].distance(to: pc.slab.boundary[1]) }
            }
            guard run > 1e-9 else { throw CommandError.invalid("The ramp needs a length.") }
            let flights = pieces.filter { !$0.landing }.count, landings = pieces.count - flights
            ed.print("Ramp created: run \(fmt(run)), rise \(fmt(rise)), gradient 1:\(fmt(run / rise, 1)) (\(fmt(rise / run * 100, 1))%)" + (pieces.count > 1 ? ", \(flights) flight(s) and \(landings) landing(s)." : "."))
            if rise / run > 1.0 / 12 + 1e-9 { ed.print("Warning: steeper than 1:12 — accessible ramps usually need 1:12 or less.") }
        }
    }

    static var slabSlopeCommand: CommandDef {
        CommandDef("SLABSLOPE", aliases: ["SLOPEARROW", "SLOPE"], category: "Architecture", summary: "Slopes a slab by a slope arrow (low point, high point, rise) or angle; Flat resets.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select slab", filter: { ed.doc.element($0).map { isSlab($0.geometry) } ?? false }),
                  let i = ed.doc.elementIndex(pk.id), case .slab(var s) = ed.doc.elements[i].geometry else { return }
            let a = try await ed.getPoint("Specify low point of slope arrow", keywords: ["Flat", "Angle"])
            switch a {
            case .keyword("Flat"): s.slope = 0; s.slopeOrigin = nil
            case .keyword("Angle"):
                guard let v = try await ed.getReal("Specify slope angle in degrees", defaultValue: 2).value, abs(v) < 80 else { throw CommandError.invalid("Slope must be under 80°.") }
                let dir = try await ed.getAngle("Specify direction of rise", defaultValue: s.slopeDirection).value ?? 0
                s.slope = v; s.slopeDirection = dir; s.slopeOrigin = s.slopeOrigin ?? s.boundary.first
            case .point(let lo):
                let hi = try await ed.requirePoint("Specify high point of slope arrow", base: lo) { c in [.line(LineGeom(lo, c))] }
                let d = lo.distance(to: hi)
                guard d > 1e-6 else { throw CommandError.invalid("The arrow needs a length.") }
                guard let rise = try await ed.getDistance("Specify rise between the points", defaultValue: d * 0.02).value else { return }
                s.slope = deg(atan(rise / d)); s.slopeDirection = (hi - lo).angle; s.slopeOrigin = lo
            default: return
            }
            ed.doc.elements[i].geometry = .slab(s)
            ed.print(s.isSloped ? "Slab sloped \(fmt(s.slope, 2))° (\(fmt(tan(rad(s.slope)) * 100, 2))%)." : "Slab made level.")
        }
    }

    static var foundationCommand: CommandDef {
        CommandDef("FOUNDATION", aliases: ["FOOTING", "FNDN"], category: "Structure", summary: "Creates strip footings under walls, isolated footings under columns, or pads from points.") { ed in
            var width = ed.variableDouble("FOOTWIDTH", 600), depth = ed.variableDouble("FOOTDEPTH", 400)
            while true {
                ed.print("Footing: Width = \(fmt(width)), Depth = \(fmt(depth))")
                let k = try await ed.getKeyword("Foundation under", ["Wall", "Column", "Pad", "Width", "Depth"], defaultValue: "Wall") ?? "Wall"
                switch k {
                case "Width": width = try await ed.getPositive("Specify footing width", defaultValue: width); continue
                case "Depth": depth = try await ed.getPositive("Specify footing depth", defaultValue: depth); continue
                default: break
                }
                ed.doc.setVariable("FOOTWIDTH", fmt(width)); ed.doc.setVariable("FOOTDEPTH", fmt(depth))
                ed.doc.ensureLayer("S-FNDN")
                var n = 0
                switch k {
                case "Wall":
                    for id in try await elements(ed, "Select walls", isWallGeom) {
                        guard let el = ed.doc.element(id), case .wall(let w) = el.geometry else { continue }
                        let outline = PlanRepresentation.wallOutline(id, doc: ed.doc)
                        guard outline.count >= 3 else { continue }
                        let b = CommandHelpers.offsetPolygon(ccw(outline), max(width - w.thickness, 0) / 2)
                        let fid = ed.doc.addElement(.slab(SlabGeom(boundary: ccw(b), thickness: depth, topOffset: w.baseOffset)), level: el.level, layer: "S-FNDN", material: "Concrete", name: "Strip Footing \(fmt(width))x\(fmt(depth))")
                        if let i = ed.doc.elementIndex(fid) { ed.doc.elements[i].props["kind"] = "foundation"; ed.doc.elements[i].props["host"] = "\(id)" }
                        n += 1
                    }
                case "Column":
                    for id in try await elements(ed, "Select columns", { if case .column = $0 { return true }; return false }) {
                        guard let el = ed.doc.element(id), case .column(let c) = el.geometry else { continue }
                        let s = max(width, max(c.width, c.depth) + 200)
                        let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
                        let b = [Vec2(-s / 2, -s / 2), Vec2(s / 2, -s / 2), Vec2(s / 2, s / 2), Vec2(-s / 2, s / 2)].map(t.apply)
                        let fid = ed.doc.addElement(.slab(SlabGeom(boundary: b, thickness: depth, topOffset: c.baseOffset)), level: el.level, layer: "S-FNDN", material: "Concrete", name: "Isolated Footing \(fmt(s))x\(fmt(s))x\(fmt(depth))")
                        if let i = ed.doc.elementIndex(fid) { ed.doc.elements[i].props["kind"] = "foundation"; ed.doc.elements[i].props["host"] = "\(id)" }
                        n += 1
                    }
                default:
                    let f = try await ed.requirePoint("Specify first point of pad")
                    guard let b = try await polygonInput(ed, first: f) else { throw CommandError.invalid("A pad needs at least three points.") }
                    let fid = ed.doc.addElement(.slab(SlabGeom(boundary: ccw(b), thickness: depth, topOffset: 0)), layer: "S-FNDN", material: "Concrete", name: "Foundation Pad")
                    if let i = ed.doc.elementIndex(fid) { ed.doc.elements[i].props["kind"] = "foundation" }
                    n = 1
                }
                ed.selection = []
                ed.print("\(n) footing(s) created.")
                return
            }
        }
    }

    static var nicheCommand: CommandDef {
        CommandDef("NICHE", aliases: ["RECESS"], category: "Architecture", summary: "Cuts a recess of a given depth into one face of a wall.") { ed in
            var width = ed.variableDouble("NICHEWIDTH", 800), height = ed.variableDouble("NICHEHEIGHT", 1200)
            var sill = ed.variableDouble("NICHESILL", 900), depth = ed.variableDouble("NICHEDEPTH", 100)
            var n = 0
            while true {
                ed.print("Niche: Width = \(fmt(width)), Height = \(fmt(height)), Sill = \(fmt(sill)), Depth = \(fmt(depth))")
                let a = try await ed.pickObject("Pick the wall face where the niche opens", keywords: ["Width", "Height", "Sill", "Depth"]) { isWall(ed.doc, $0) }
                switch a {
                case .keyword("Width"): width = try await ed.getPositive("Specify width", defaultValue: width)
                case .keyword("Height"): height = try await ed.getPositive("Specify height", defaultValue: height)
                case .keyword("Sill"): sill = try await ed.getPositive("Specify sill height", defaultValue: sill, allowZero: true)
                case .keyword("Depth"): depth = try await ed.getPositive("Specify niche depth", defaultValue: depth)
                case .pick(let pk):
                    guard let host = ed.doc.element(pk.id), case .wall(let w) = host.geometry else { continue }
                    guard depth < w.thickness else { ed.print("The niche must be shallower than the wall (\(fmt(w.thickness))); use OPENING to cut through."); continue }
                    guard w.length >= width, sill + height <= w.height + 1e-6 else { ed.print("The niche does not fit in the wall."); continue }
                    let dir = w.direction
                    let along = max(width / 2, min(w.length - width / 2, (pk.point - w.centerStart).dot(dir)))
                    let left = dir.cross(pk.point - w.centerStart) > 0
                    let o = OpeningGeom(kind: .opening, hostWall: pk.id, offset: along, width: width, height: height, sill: sill, flipFacing: left, depth: depth)
                    ed.doc.addElement(.opening(o), level: host.level, layer: "A-WALL", name: "Niche \(fmt(width))x\(fmt(height))x\(fmt(depth))")
                    n += 1
                default:
                    ed.doc.setVariable("NICHEWIDTH", fmt(width)); ed.doc.setVariable("NICHEHEIGHT", fmt(height)); ed.doc.setVariable("NICHESILL", fmt(sill)); ed.doc.setVariable("NICHEDEPTH", fmt(depth))
                    if n > 0 { ed.print("\(n) niche(s) created.") }
                    return
                }
            }
        }
    }

    static var wallSweepCommand: CommandDef {
        CommandDef("WALLSWEEP", aliases: ["SWEEPWALL", "CORNICE", "SKIRTING"], category: "Architecture", summary: "Adds cornices, skirting boards or string courses along wall faces (or removes them).") { ed in
            let mode = try await ed.getKeyword("Wall sweep", ["Add", "Remove"], defaultValue: "Add") ?? "Add"
            if mode == "Remove" {
                var n = 0
                for id in try await elements(ed, "Select walls", isWallGeom) {
                    guard let i = ed.doc.elementIndex(id), case .wall(var w) = ed.doc.elements[i].geometry, !w.sweeps.isEmpty else { continue }
                    n += w.sweeps.count; w.sweeps = []; ed.doc.elements[i].geometry = .wall(w)
                }
                ed.selection = []; ed.print("\(n) sweep(s) removed."); return
            }
            let profile = (try await ed.getKeyword("Profile", ["Rect", "Cornice", "Skirting", "Cove"], defaultValue: ed.doc.variable("SWEEPPROFILE") ?? "Cornice") ?? "Cornice")
            let isBase = profile == "Skirting"
            let depth = try await ed.getPositive("Specify projection from the face", defaultValue: isBase ? 15 : 80)
            let height = try await ed.getPositive("Specify profile height", defaultValue: isBase ? 100 : 200)
            let side = try await ed.getKeyword("Face", ["Left", "Right", "Both"], defaultValue: "Both") ?? "Both"
            let elevInput = try await ed.getDistance("Specify bottom of the profile above the wall base (Enter = \(isBase ? "floor" : "wall top"))").value
            ed.doc.setVariable("SWEEPPROFILE", profile)
            var n = 0
            for id in try await elements(ed, "Select walls", isWallGeom) {
                guard let i = ed.doc.elementIndex(id), case .wall(var w) = ed.doc.elements[i].geometry else { continue }
                let elev = elevInput ?? (isBase ? 0 : max(w.height - height, 0))
                for sd in (side == "Both" ? [1.0, -1.0] : [side == "Left" ? 1.0 : -1.0]) {
                    w.sweeps.append(WallSweep(profile: profile.lowercased(), depth: depth, height: height, elevation: elev, side: sd))
                    n += 1
                }
                ed.doc.elements[i].geometry = .wall(w)
            }
            ed.selection = []
            ed.print("\(n) sweep(s) added.")
        }
    }

    static var curtainGridCommand: CommandDef {
        CommandDef("CWGRID", aliases: ["CURTAINGRID"], category: "Architecture", summary: "Edits a curtain wall grid: add/remove grid lines, panels (glass, solid, spandrel, louvre, empty, door, double door), mullion types, uniform spacing.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select curtain wall", filter: { if case .curtainWall? = ed.doc.element($0)?.geometry { return true }; return false }),
                  let idx = ed.doc.elementIndex(pk.id), case .curtainWall(var g) = ed.doc.elements[idx].geometry else { return }
            let len = g.length
            guard len > 1e-9 else { return }
            let d = (g.end - g.start) / len
            @MainActor func along(_ p: Vec2) -> Double { min(max((p - g.start).dot(d), 0), len) }
            while true {
                ed.print("Grid: \(g.uPositions.count) vertical, \(g.vPositions.count) horizontal line(s).")
                let k = try await ed.getKeyword("Grid option", ["AddVertical", "AddHorizontal", "Remove", "Panel", "Uniform", "Mullion", "eXit"], defaultValue: "eXit") ?? "eXit"
                switch k {
                case "AddVertical":
                    let p = try await ed.requirePoint("Specify position along the wall")
                    g.uLines = (g.uPositions + [along(p)]).sorted()
                case "AddHorizontal":
                    guard let z = try await ed.getDistance("Specify height above the base").value, z > 0, z < g.height else { ed.print("Height must be inside the wall."); continue }
                    g.vLines = (g.vPositions + [z]).sorted()
                case "Remove":
                    let which = try await ed.getKeyword("Remove", ["Vertical", "Horizontal"], defaultValue: "Vertical") ?? "Vertical"
                    if which == "Vertical" {
                        let x = along(try await ed.requirePoint("Pick near the vertical grid line"))
                        var u = g.uPositions
                        if let i = u.indices.min(by: { abs(u[$0] - x) < abs(u[$1] - x) }) { u.remove(at: i) }
                        g.uLines = u
                    } else {
                        guard let z = try await ed.getDistance("Specify height of the line to remove").value else { continue }
                        var v = g.vPositions
                        if let i = v.indices.min(by: { abs(v[$0] - z) < abs(v[$1] - z) }) { v.remove(at: i) }
                        g.vLines = v
                    }
                case "Panel":
                    let x = along(try await ed.requirePoint("Pick the panel column in plan"))
                    guard let z = try await ed.getDistance("Specify a height inside the panel", defaultValue: g.height / 2).value else { continue }
                    let xs = [0] + g.uPositions + [len], zs = [0] + g.vPositions + [g.height]
                    guard let ci = (0..<(xs.count - 1)).first(where: { x >= xs[$0] && x <= xs[$0 + 1] }),
                          let ri = (0..<(zs.count - 1)).first(where: { z >= zs[$0] && z <= zs[$0 + 1] }) else { ed.print("No panel there."); continue }
                    let t = try await ed.getKeyword("Panel type", ["Glass", "Solid", "SPandrel", "Louvre", "Empty", "Door", "DOUbledoor"], defaultValue: "Solid") ?? "Solid"
                    if (t == "Door" || t == "DOUbledoor") && ri != 0 { ed.print("Doors go in the bottom row of panels."); continue }
                    if t == "Glass" { g.panels["\(ci),\(ri)"] = nil } else { g.panels["\(ci),\(ri)"] = t.lowercased() }
                    ed.print("Panel \(ci + 1),\(ri + 1) set to \(t.lowercased() == "doubledoor" ? "double door" : t.lowercased()).")
                case "Mullion":
                    let which = try await ed.getKeyword("Mullions to change", ["Interior", "Border", "All"], defaultValue: "All") ?? "All"
                    let cur = CurtainMullion.normalized(which == "Border" ? (g.borderProfile ?? g.mullionProfile) : g.mullionProfile)
                    let t = try await ed.getKeyword("Mullion type", ["Rect", "Round", "Fin", "Capped", "Tee"], defaultValue: cur.capitalized) ?? "Rect"
                    let type = t.lowercased()
                    switch which {
                    case "Interior": g.mullionProfile = type; if g.borderProfile == nil { g.borderProfile = cur }
                    case "Border": g.borderProfile = type
                    default: g.mullionProfile = type; g.borderProfile = nil
                    }
                    g.mullionSize = try await ed.getPositive("Specify mullion face width", defaultValue: g.mullionSize)
                    let dep = try await ed.getPositive("Specify mullion depth", defaultValue: CurtainMullion.depth(g))
                    g.mullionDepth = abs(dep - g.mullionSize * 1.5) < 1e-9 ? nil : dep
                    ed.print("Mullions: interior \(CurtainMullion.type(g, border: false)), border \(CurtainMullion.type(g, border: true)), \(fmt(g.mullionSize))×\(fmt(CurtainMullion.depth(g))).")
                case "Uniform":
                    g.gridU = try await ed.getPositive("Specify vertical line spacing", defaultValue: g.gridU)
                    g.gridV = try await ed.getPositive("Specify horizontal line spacing", defaultValue: g.gridV)
                    g.uLines = nil; g.vLines = nil; g.panels = [:]
                default:
                    ed.doc.elements[idx].geometry = .curtainWall(g)
                    return
                }
                ed.doc.elements[idx].geometry = .curtainWall(g)
            }
        }
    }

    static let separatorLayer = "A-AREA-SEPR"

    static var roomSeparatorCommand: CommandDef {
        CommandDef("ROOMSEPARATOR", aliases: ["ROOMSEP", "RSL"], category: "Architecture", summary: "Draws room separation lines (virtual room boundaries used by ROOM, SLAB Walls, ROOMUPDATE).") { ed in
            if ed.doc.layer(named: separatorLayer) == nil {
                ed.doc.layers.append(Layer(name: separatorLayer, color: RGBA(0.55, 0.75, 1.0), linetype: "Dashed", lineweight: 0.13, plot: false, description: "Room separation lines"))
            }
            var prev = try await ed.requirePoint("Specify first point of separation line")
            var n = 0
            while true {
                let p0 = prev
                guard let p = try await ed.getPoint("Specify next point", base: prev, preview: { c in [.line(LineGeom(p0, c))] }).point else { break }
                guard p.distance(to: prev) > 1e-6 else { continue }
                let id = ed.doc.add(.line(LineGeom(prev, p)), layer: separatorLayer)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["level"] = "\(ed.doc.currentLevel)" }
                prev = p; n += 1
            }
            ed.print("\(n) room separation line(s) drawn.")
        }
    }

    /// Separation curves for a level (layers named like *SEP*; lines tagged with another level are skipped).
    static func separators(_ doc: ArchiDocument, level: Int) -> [Geometry] {
        doc.entities.filter { e in
            e.layer.uppercased().contains("SEP") && doc.isVisible(layer: e.layer) && (e.props["level"].flatMap(Int.init).map { $0 == level } ?? true)
        }.map(\.geometry)
    }

    static var roomUpdateCommand: CommandDef {
        CommandDef("ROOMUPDATE", aliases: ["UPDATEROOMS", "RU"], category: "Architecture", summary: "Recomputes the boundaries and areas of rooms placed by picking, after walls or separation lines changed.") { ed in
            var changed = 0, lost = 0
            for (i, el) in ed.doc.elements.enumerated() {
                guard case .space(var s) = el.geometry, el.props["areaScheme"] == nil,
                      let x = el.props["seedX"].flatMap(Double.init), let y = el.props["seedY"].flatMap(Double.init) else { continue }
                guard let b = RoomBounding.boundary(at: Vec2(x, y), doc: ed.doc, level: el.level, extraCurves: separators(ed.doc, level: el.level)) else { lost += 1; continue }
                let nb = ccw(b)
                if nb != s.boundary { s.boundary = nb; ed.doc.elements[i].geometry = .space(s); changed += 1 }
            }
            ed.print("\(changed) room(s) updated." + (lost > 0 ? " \(lost) room(s) are no longer enclosed (kept unchanged)." : ""))
        }
    }

    static var areaPlanCommand: CommandDef {
        CommandDef("AREAPLAN", aliases: ["AREABOUNDARY", "GROSSAREA"], category: "Architecture", summary: "Creates area plan boundaries (Gross, Rentable or custom schemes) and reports totals per scheme.") { ed in
            var scheme = ed.doc.variable("AREASCHEME") ?? "Gross"
            ed.doc.ensureLayer("A-AREA-PLAN")
            var n = 0
            while true {
                let a = try await ed.getPoint("Pick inside the building [scheme \(scheme)]", keywords: ["Scheme", "Points", "Report"])
                var boundary: [Vec2]? = nil
                switch a {
                case .point(let p):
                    // Gross area measures to the outside face of exterior walls.
                    guard let inner = RoomBounding.boundary(at: p, doc: ed.doc, level: ed.doc.currentLevel) else { ed.print("No enclosing walls found (use Points)."); continue }
                    if scheme.lowercased() == "gross" {
                        let t = ed.doc.elements.compactMap { el -> Double? in if el.level == ed.doc.currentLevel, case .wall(let w) = el.geometry { return w.thickness }; return nil }.max() ?? 0
                        boundary = CommandHelpers.offsetPolygon(ccw(inner), t)
                    } else { boundary = inner }
                case .keyword("Scheme"): scheme = try await ed.getWord("Enter area scheme name (Gross, Rentable, …)", defaultValue: scheme) ?? scheme; ed.doc.setVariable("AREASCHEME", scheme); continue
                case .keyword("Points"):
                    let f = try await ed.requirePoint("Specify first point")
                    boundary = try await polygonInput(ed, first: f)
                case .keyword("Report"):
                    var totals: [String: Double] = [:]
                    for el in ed.doc.elements where el.level == ed.doc.currentLevel { if case .space(let s) = el.geometry, let sc = el.props["areaScheme"] { totals[sc, default: 0] += abs(GeometryOps.signedArea(s.boundary)) } }
                    if totals.isEmpty { ed.print("No area boundaries on this level.") }
                    for (k, v) in totals.sorted(by: { $0.key < $1.key }) { ed.print("\(k): " + CommandHelpers.areaText(v, units: ed.doc.units)) }
                    continue
                default:
                    if n > 0 { ed.print("\(n) area(s) created.") }
                    return
                }
                guard let b = boundary, b.count >= 3 else { continue }
                let id = ed.doc.addElement(.space(SpaceGeom(boundary: ccw(b), name: "\(scheme) Area", number: "", height: 0)), layer: "A-AREA-PLAN", name: "\(scheme) Area")
                if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["areaScheme"] = scheme }
                ed.print("\(scheme) area: " + CommandHelpers.areaText(abs(GeometryOps.signedArea(b)), units: ed.doc.units))
                n += 1
            }
        }
    }

    static var phaseCommand: CommandDef {
        CommandDef("PHASE", aliases: ["PHASES", "PHASING"], category: "Architecture", summary: "Manages construction phases: list, new, current phase, filter, created/demolished phase of objects.") { ed in
            let k = try await ed.getKeyword("Phase option", ["List", "New", "Current", "Filter", "Created", "Demolish", "Clear"], defaultValue: "List") ?? "List"
            @MainActor func pickPhase(_ msg: String, _ def: String?) async throws -> String {
                guard let s = try await ed.getWord(msg + " [" + ed.doc.phases.joined(separator: "/") + "]", defaultValue: def),
                      let i = Phasing.phaseIndex(s, ed.doc) ?? ed.doc.phases.firstIndex(where: { $0.lowercased().hasPrefix(s.lowercased()) }) else { throw CommandError.invalid("Unknown phase.") }
                return ed.doc.phases[i]
            }
            let cur = ed.doc.phases.isEmpty ? nil : ed.doc.phases[Phasing.currentPhase(ed.doc)]
            switch k {
            case "New":
                guard let n = try await ed.getWord("Enter new phase name"), !n.isEmpty else { return }
                guard Phasing.phaseIndex(n, ed.doc) == nil else { throw CommandError.invalid("Phase \(n) already exists.") }
                ed.doc.phases.append(n); ed.doc.setVariable("PHASE", n)
                ed.print("Phase \"\(n)\" added and made current.")
            case "Current":
                let p = try await pickPhase("Enter phase to show", cur)
                ed.doc.setVariable("PHASE", p); ed.print("Views show phase \(p).")
            case "Filter":
                let f = try await ed.getKeyword("Phase filter", ["All", "Complete", "New", "Demolition", "None"], defaultValue: Phasing.filter(ed.doc).rawValue.capitalized) ?? "All"
                ed.doc.setVariable("PHASEFILTER", f.lowercased()); ed.print("Phase filter: \(f).")
            case "Created", "Demolish", "Clear":
                let ids = try await ed.getSelection("Select objects")
                guard !ids.isEmpty else { return }
                let p: String? = k == "Clear" ? nil : try await pickPhase(k == "Created" ? "Phase created" : "Phase demolished", cur)
                let key = k == "Demolish" ? "phaseDemolished" : "phaseCreated"
                for id in ids {
                    if let i = ed.doc.elementIndex(id) {
                        if k == "Clear" { ed.doc.elements[i].props["phaseCreated"] = nil; ed.doc.elements[i].props["phaseDemolished"] = nil } else { ed.doc.elements[i].props[key] = p }
                    } else if let i = ed.doc.entityIndex(id) {
                        if k == "Clear" { ed.doc.entities[i].props["phaseCreated"] = nil; ed.doc.entities[i].props["phaseDemolished"] = nil } else { ed.doc.entities[i].props[key] = p }
                    }
                }
                ed.selection = []
                ed.print("\(ids.count) object(s) " + (k == "Clear" ? "cleared of phasing." : "set: \(key) = \(p!)."))
            default:
                let c = Phasing.currentPhase(ed.doc)
                for (i, p) in ed.doc.phases.enumerated() {
                    let made = ed.doc.elements.filter { Phasing.phaseIndex($0.props["phaseCreated"], ed.doc) == i }.count
                    let demo = ed.doc.elements.filter { Phasing.phaseIndex($0.props["phaseDemolished"], ed.doc) == i }.count
                    ed.print("\(i == c ? "*" : " ") \(p): \(made) created, \(demo) demolished")
                }
                ed.print("Filter: \(Phasing.filter(ed.doc).rawValue)")
            }
        }
    }
}

// MARK: - Types, tags, keynotes, marks, sections and drawing views, schedules

extension ArchitectureCommands {
    static var documentation: [CommandDef] { [openingTypeCommand, tagCommand, tagAllCommand, marksCommand, keynoteCommand, sectionCommand, viewDrawCommand, viewUpdateCommand] }

    static func isOpening(_ g: BIMGeometry) -> Bool { if case .opening = g { return true }; return false }

    /// Next free mark for doors ("D01"…) or windows ("W01"…).
    static func nextMark(_ doc: ArchiDocument, _ kind: OpeningKind) -> String {
        let prefix = kind == .window ? "W" : "D"
        var used = Set<Int>()
        for el in doc.elements { if case .opening(let o) = el.geometry, let m = o.mark, m.hasPrefix(prefix), let v = Int(m.dropFirst(prefix.count)) { used.insert(v) } }
        var i = 1
        while used.contains(i) { i += 1 }
        return prefix + String(format: "%02d", i)
    }

    static let tagLayer = "A-ANNO-TAGS"

    /// Places a live tag for an element (text entity with props tagOf/tagField, resolved at draw time).
    @MainActor @discardableResult
    static func addTag(_ ed: Editor, _ id: EntityID, field: String, at pos: Vec2? = nil) -> EntityID? {
        guard let el = ed.doc.element(id) else { return nil }
        if ed.doc.layer(named: tagLayer) == nil { ed.doc.layers.append(Layer(name: tagLayer, color: RGBA(0.85, 0.85, 0.85), lineweight: 0.18)) }
        let u = 1 / ed.doc.units.mm
        var p = pos ?? Annotations.anchor(el, doc: ed.doc)
        if pos == nil, case .opening(let o) = el.geometry, let host = ed.doc.element(o.hostWall), let f = WallFrame(host) {
            // Beside the wall, on the side away from a door swing.
            let side: Double = o.kind == .door ? (o.flipFacing ? 1 : -1) : (o.flipFacing ? -1 : 1)
            p = f.pt(o.offset, side * (f.h + 450 * u))
        }
        let content = Annotations.tagText(el, field: field, doc: ed.doc)
        let tid = ed.doc.add(.text(TextGeom(position: p, height: 180 * u, content: content, halign: .center, valign: .middle)), layer: tagLayer)
        if let i = ed.doc.entityIndex(tid) {
            ed.doc.entities[i].props["tagOf"] = "\(id)"; ed.doc.entities[i].props["tagField"] = field; ed.doc.entities[i].props["level"] = "\(el.level)"
        }
        if case .space = el.geometry, let i = ed.doc.elementIndex(id), field == "room" { ed.doc.elements[i].props["tag"] = "0" }
        return tid
    }

    static var openingTypeCommand: CommandDef {
        CommandDef("OPENINGTYPE", aliases: ["DOORTYPE", "WINDOWTYPE", "TYPECATALOG"], category: "Architecture",
                   summary: "Door/window type catalog: list, new, set type parameters and sub-parts (mullions, transoms, threshold), formulas, apply to openings, delete, import CSV.") { ed in
            let k = try await ed.getKeyword("Type option", ["List", "New", "Set", "Formula", "Apply", "Delete", "Import"], defaultValue: "List") ?? "List"
            @MainActor func pickType(_ msg: String) async throws -> Int {
                guard let n = try await ed.getWord(msg), let i = ed.doc.openingTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame })
                        ?? ed.doc.openingTypes.firstIndex(where: { $0.name.lowercased().hasPrefix(n.lowercased()) }) else { throw CommandError.invalid("Type not found.") }
                return i
            }
            switch k {
            case "New":
                guard let name = try await ed.getWord("Enter type name"), !name.isEmpty else { return }
                guard ed.doc.openingType(name) == nil else { throw CommandError.invalid("Type \(name) already exists.") }
                let kk = try await ed.getKeyword("Kind", ["Door", "Window", "Opening"], defaultValue: "Door") ?? "Door"
                let kind = OpeningKind(rawValue: kk.lowercased()) ?? .door
                let w = try await ed.getPositive("Specify width", defaultValue: kind == .window ? 1200 : 900)
                let h = try await ed.getPositive("Specify height", defaultValue: kind == .window ? 1200 : 2100)
                let s = try await ed.getPositive("Specify sill height", defaultValue: kind == .window ? 900 : 0, allowZero: true)
                var t = OpeningType(name: name, kind: kind, width: w, height: h, sill: s)
                if kind == .door, let st = try await ed.getWord("Door style [\(DoorStyle.allCases.map(\.rawValue).joined(separator: "/"))]", defaultValue: "single"), let ds = DoorStyle.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(st.lowercased()) }) { t.doorStyle = ds }
                if kind == .window, let st = try await ed.getWord("Window style [\(WindowStyle.allCases.map(\.rawValue).joined(separator: "/"))]", defaultValue: "casement"), let ws = WindowStyle.allCases.first(where: { $0.rawValue.lowercased() == st.lowercased() }) ?? WindowStyle.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(st.lowercased()) }) { t.windowStyle = ws }
                ed.doc.openingTypes.append(t)
                ed.print("Type \"\(name)\" created.")
            case "Set":
                let i = try await pickType("Enter type name")
                guard let param = try await ed.getWord("Parameter [Width/Height/Sill/Style/Frame/Material/Name/Mullions/Transoms/Threshold or any custom name]") else { return }
                guard let value = try await ed.getWord("Enter value for \(param)") else { return }
                var t = ed.doc.openingTypes[i]
                let old = t.name
                switch param.lowercased() {
                case "width": guard let v = Double(value), v > 0 else { throw CommandError.invalid("Width must be positive.") }; t.width = v
                case "height": guard let v = Double(value), v > 0 else { throw CommandError.invalid("Height must be positive.") }; t.height = v
                case "sill": guard let v = Double(value), v >= 0 else { throw CommandError.invalid("Sill must be zero or positive.") }; t.sill = v
                case "frame", "framewidth": guard let v = Double(value), v >= 0 else { throw CommandError.invalid("Invalid frame width.") }; t.frameWidth = v
                case "material": t.material = value.isEmpty ? nil : value
                case "mullions": guard let v = Int(value), v >= 0, v <= 20 else { throw CommandError.invalid("Mullions: 0 to 20.") }; t.mullions = v
                case "transoms": guard let v = Int(value), v >= 0, v <= 20 else { throw CommandError.invalid("Transoms: 0 to 20.") }; t.transoms = v
                case "threshold": t.threshold = ["1", "yes", "true", "on", "y"].contains(value.lowercased())
                case "name":
                    guard ed.doc.openingType(value) == nil else { throw CommandError.invalid("Type \(value) already exists.") }
                    t.name = value
                case "style":
                    if let d = DoorStyle.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }), t.kind == .door { t.doorStyle = d }
                    else if let w = WindowStyle.allCases.first(where: { $0.rawValue.lowercased() == value.lowercased() }), t.kind == .window { t.windowStyle = w }
                    else { throw CommandError.invalid("Unknown style \(value).") }
                default: t.params[param] = value.isEmpty ? nil : value
                }
                ed.doc.openingTypes[i] = t
                let n = propagateType(&ed.doc, oldName: old, type: t)
                ed.print("Type \"\(t.name)\": \(param) = \(value); \(n) instance(s) updated.")
                for e in t.resolved().errors { ed.print("Formula error: " + e) }
            case "Formula":
                let i = try await pickType("Enter type name")
                guard let param = try await ed.getWord("Parameter driven by the formula (Width/Height/Sill/FrameWidth/Mullions/Transoms or a custom name)") else { return }
                let expr = try await ed.getString("Enter formula (other parameters by name, e.g. width * 1.5; empty = remove)") ?? ""
                var t = ed.doc.openingTypes[i]
                let key = t.formulas.keys.first { $0.caseInsensitiveCompare(param) == .orderedSame } ?? param
                t.formulas[key] = expr.trimmingCharacters(in: .whitespaces).isEmpty ? nil : expr
                let r = t.resolved()
                guard r.errors.isEmpty else { throw CommandError.invalid("Formula rejected: " + r.errors.joined(separator: "; ")) }
                if r.type.width <= 0 || r.type.height <= 0 { throw CommandError.invalid("The formula gives a non-positive size.") }
                ed.doc.openingTypes[i] = t
                let n = propagateType(&ed.doc, oldName: t.name, type: t)
                ed.print("Type \"\(t.name)\": \(key) = \(expr.isEmpty ? "(value)" : expr) → \(fmt(r.type.width))×\(fmt(r.type.height)), sill \(fmt(r.type.sill)); \(n) instance(s) updated.")
            case "Apply":
                let i = try await pickType("Enter type name")
                let t = ed.doc.openingTypes[i]
                let rt = t.resolved().type
                var n = 0
                for id in try await elements(ed, "Select doors/windows/openings", isOpening) {
                    guard let j = ed.doc.elementIndex(id), case .opening(var o) = ed.doc.elements[j].geometry else { continue }
                    let host = ed.doc.element(o.hostWall).flatMap { el -> WallGeom? in if case .wall(let w) = el.geometry { return w }; return nil }
                    if let w = host, rt.width > w.length + 1e-6 || rt.sill + rt.height > w.height + 1e-6 { ed.print("#\(id): type does not fit its wall, skipped."); continue }
                    if t.kind != o.kind, o.kind != .opening, t.kind != .opening, o.mark != nil { o.mark = nextMark(ed.doc, t.kind) }
                    t.apply(to: &o)
                    ed.doc.elements[j].geometry = .opening(o); ed.doc.elements[j].name = t.name
                    if let m = t.material { ed.doc.elements[j].material = m }
                    n += 1
                }
                ed.selection = []
                ed.print("Type \"\(t.name)\" applied to \(n) opening(s).")
            case "Delete":
                let i = try await pickType("Enter type to delete")
                let name = ed.doc.openingTypes[i].name
                ed.doc.openingTypes.remove(at: i)
                for j in ed.doc.elements.indices { if case .opening(var o) = ed.doc.elements[j].geometry, o.typeName == name { o.typeName = nil; ed.doc.elements[j].geometry = .opening(o) } }
                ed.print("Type \"\(name)\" deleted (instances keep their sizes).")
            case "Import":
                guard let path = try await ed.getString("Enter CSV file path (name,kind,width,height,sill,style[,param=value…])") else { return }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
                let r = importTypes(text, into: &ed.doc)
                ed.print("\(r.added) type(s) added, \(r.updated) updated, \(r.instances) instance(s) updated.")
            default:
                for t in ed.doc.openingTypes {
                    let count = ed.doc.elements.filter { if case .opening(let o) = $0.geometry { return o.typeName == t.name }; return false }.count
                    let style = t.kind == .door ? t.doorStyle.rawValue : (t.kind == .window ? t.windowStyle.rawValue : "-")
                    let r = t.resolved().type
                    var extra = r.params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                    if r.mullions > 0 { extra.append("mullions=\(r.mullions)") }
                    if r.transoms > 0 { extra.append("transoms=\(r.transoms)") }
                    if r.threshold { extra.append("threshold") }
                    extra += t.formulas.sorted { $0.key < $1.key }.map { "\($0.key):=\($0.value)" }
                    ed.print("\(t.kind.rawValue) \"\(t.name)\": \(fmt(r.width))×\(fmt(r.height)), sill \(fmt(r.sill)), \(style), \(count) placed" + (extra.isEmpty ? "" : "; " + extra.joined(separator: ", ")))
                }
            }
        }
    }

    /// Pushes type parameters to all instances of the type; returns the number of instances updated.
    @discardableResult
    static func propagateType(_ doc: inout ArchiDocument, oldName: String, type t: OpeningType) -> Int {
        var n = 0
        for j in doc.elements.indices {
            guard case .opening(var o) = doc.elements[j].geometry, o.typeName == oldName else { continue }
            t.apply(to: &o)
            doc.elements[j].geometry = .opening(o)
            if doc.elements[j].name == oldName { doc.elements[j].name = t.name }
            if let m = t.material { doc.elements[j].material = m }
            n += 1
        }
        return n
    }

    /// Imports a type lookup table (CSV rows: name,kind,width,height,sill,style[,key=value…]); header rows are skipped.
    static func importTypes(_ csv: String, into doc: inout ArchiDocument) -> (added: Int, updated: Int, instances: Int) {
        var added = 0, updated = 0, inst = 0
        for row in parseCSV(csv) {
            let c = row.map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 4, let kind = OpeningKind(rawValue: c[1].lowercased()), let w = Double(c[2]), let h = Double(c[3]), w > 0, h > 0 else { continue }
            var t = OpeningType(name: c[0], kind: kind, width: w, height: h, sill: c.count > 4 ? Double(c[4]) ?? 0 : 0)
            if c.count > 5 {
                if let d = DoorStyle(rawValue: c[5]) { t.doorStyle = d }
                if let ws = WindowStyle(rawValue: c[5]) { t.windowStyle = ws }
            }
            for kv in c.dropFirst(6) { let p = kv.split(separator: "=", maxSplits: 1).map(String.init); if p.count == 2 { t.params[p[0]] = p[1] } }
            if let i = doc.openingTypes.firstIndex(where: { $0.name.caseInsensitiveCompare(t.name) == .orderedSame }) {
                doc.openingTypes[i] = t; updated += 1
                inst += propagateType(&doc, oldName: t.name, type: t)
            } else { doc.openingTypes.append(t); added += 1 }
        }
        return (added, updated, inst)
    }

    static var tagCommand: CommandDef {
        CommandDef("TAG", aliases: ["TAGBYCATEGORY", "ELEMENTTAG"], category: "Annotate", summary: "Tags a door, window, room or element with a live label (mark, type, name, area, keynote…).") { ed in
            var field: String? = nil
            var n = 0
            while true {
                let a = try await ed.pickObject("Select element to tag", keywords: ["Field"]) { ed.doc.element($0) != nil }
                switch a {
                case .keyword: field = try await ed.getKeyword("Tag field", ["Mark", "Type", "Name", "Number", "Area", "Room", "Keynote", "Size"], defaultValue: "Mark")?.lowercased()
                case .pick(let pk):
                    guard let el = ed.doc.element(pk.id) else { continue }
                    var f = field ?? "mark"
                    if field == nil, case .space = el.geometry { f = "room" }
                    let anchor = Annotations.anchor(el, doc: ed.doc)
                    let p = try await ed.getPoint("Specify tag location (Enter = automatic)", base: anchor).point
                    if addTag(ed, pk.id, field: f, at: p) != nil { n += 1 }
                default:
                    if n > 0 { ed.print("\(n) tag(s) placed.") }
                    return
                }
            }
        }
    }

    static var tagAllCommand: CommandDef {
        CommandDef("TAGALL", aliases: ["TAGALLNOTTAGGED"], category: "Annotate", summary: "Tags every untagged door, window and/or room on the current level.") { ed in
            let k = try await ed.getKeyword("Categories", ["Doors", "Windows", "Rooms", "All"], defaultValue: "All") ?? "All"
            let tagged = Set(ed.doc.entities.compactMap { $0.props["tagOf"].flatMap(Int.init) })
            var n = 0
            for el in ed.doc.elements where el.level == ed.doc.currentLevel && !tagged.contains(el.id) {
                switch el.geometry {
                case .opening(let o) where o.kind == .door && (k == "Doors" || k == "All"): addTag(ed, el.id, field: "mark"); n += 1
                case .opening(let o) where o.kind == .window && (k == "Windows" || k == "All"): addTag(ed, el.id, field: "mark"); n += 1
                case .space where el.props["areaScheme"] == nil && (k == "Rooms" || k == "All"): addTag(ed, el.id, field: "room"); n += 1
                default: continue
                }
            }
            ed.print("\(n) tag(s) placed.")
        }
    }

    static var marksCommand: CommandDef {
        CommandDef("MARKS", aliases: ["RENUMBER", "NUMBEROPENINGS"], category: "Annotate", summary: "Renumbers door and window marks per level in reading order (D01…, W01…), or sets a mark.") { ed in
            let k = try await ed.getKeyword("Marks", ["Renumber", "Set"], defaultValue: "Renumber") ?? "Renumber"
            if k == "Set" {
                guard case .pick(let pk) = try await ed.pickObject("Select door or window", filter: { ed.doc.element($0).map { isOpening($0.geometry) } ?? false }),
                      let i = ed.doc.elementIndex(pk.id), case .opening(var o) = ed.doc.elements[i].geometry else { return }
                o.mark = try await ed.getWord("Enter mark", defaultValue: o.mark)
                ed.doc.elements[i].geometry = .opening(o)
                return
            }
            let perLevel = try await ed.getYesNo("Prefix marks with the level number?", defaultValue: false)
            var n = 0
            var counters: [OpeningKind: Int] = [:]
            for (li, lvl) in ed.doc.levels.enumerated() {
                if perLevel { counters = [:] }
                for kind in [OpeningKind.door, .window] {
                    var items: [(Int, Vec2)] = []
                    for (i, el) in ed.doc.elements.enumerated() where el.level == lvl.id {
                        if case .opening(let o) = el.geometry, o.kind == kind { items.append((i, Annotations.anchor(el, doc: ed.doc))) }
                    }
                    // Reading order: top to bottom (rows of 1 m), then left to right.
                    let row = 1000 / ed.doc.units.mm
                    items.sort { a, b in
                        let ra = (a.1.y / row).rounded(), rb = (b.1.y / row).rounded()
                        return ra != rb ? ra > rb : a.1.x < b.1.x
                    }
                    for it in items {
                        guard case .opening(var o) = ed.doc.elements[it.0].geometry else { continue }
                        counters[kind, default: 0] += 1
                        let pfx = kind == .door ? "D" : "W"
                        o.mark = pfx + (perLevel ? "\(li)" : "") + String(format: "%02d", counters[kind]!)
                        ed.doc.elements[it.0].geometry = .opening(o); n += 1
                    }
                }
            }
            ed.print("\(n) mark(s) assigned.")
        }
    }

    static var keynoteCommand: CommandDef {
        CommandDef("KEYNOTE", aliases: ["KN"], category: "Annotate", summary: "Keynotes: define keys, assign them to elements with a keynote tag, and place a keynote legend table.") { ed in
            let k = try await ed.getKeyword("Keynote option", ["Tag", "Define", "Legend", "List"], defaultValue: "Tag") ?? "Tag"
            switch k {
            case "Define":
                guard let key = try await ed.getWord("Enter key (e.g. 04.21)"), !key.isEmpty else { return }
                guard let text = try await ed.getString("Enter description", defaultValue: ed.doc.keynotes[key]) else { return }
                ed.doc.keynotes[key] = text.isEmpty ? nil : text
                ed.print(text.isEmpty ? "Key \(key) removed." : "Key \(key) = \(text)")
            case "Legend":
                let used = Set(ed.doc.elements.compactMap { $0.props["keynote"] })
                let keys = ed.doc.keynotes.keys.filter { used.isEmpty || used.contains($0) }.sorted()
                guard !keys.isEmpty else { throw CommandError.invalid("No keynotes defined.") }
                let p = try await ed.requirePoint("Specify legend insertion point")
                let th = ed.settings.textHeight
                let rows = [["Keynote Legend", ""], ["Key", "Description"]] + keys.map { [$0, ed.doc.keynotes[$0] ?? ""] }
                let w1 = max(th * 6, Double(keys.map(\.count).max() ?? 4) * th * 0.8 + th), w2 = max(th * 20, Double(rows.map { $0[1].count }.max() ?? 10) * th * 0.7 + th)
                ed.addEntity(.table(TableGeom(origin: p, columnWidths: [w1, w2], rowHeight: th * 2, cells: rows, textHeight: th)), layer: ed.annotationLayer("TEXTLAYER"))
                ed.print("Legend with \(keys.count) keynote(s) placed.")
            case "List":
                for (key, v) in ed.doc.keynotes.sorted(by: { $0.key < $1.key }) {
                    ed.print("\(key)  \(v)  (\(ed.doc.elements.filter { $0.props["keynote"] == key }.count) element(s))")
                }
            default:
                guard case .pick(let pk) = try await ed.pickObject("Select element to keynote", filter: { ed.doc.element($0) != nil }), let i = ed.doc.elementIndex(pk.id) else { return }
                guard let key = try await ed.getWord("Enter key" + (ed.doc.keynotes.isEmpty ? "" : " [" + ed.doc.keynotes.keys.sorted().prefix(12).joined(separator: "/") + "]"), defaultValue: ed.doc.elements[i].props["keynote"]) else { return }
                if ed.doc.keynotes[key] == nil {
                    if let d = try await ed.getString("New key: enter description"), !d.isEmpty { ed.doc.keynotes[key] = d }
                }
                ed.doc.elements[i].props["keynote"] = key
                let p = try await ed.getPoint("Specify keynote location", base: pk.point).point
                addTag(ed, pk.id, field: "keynote", at: p ?? pk.point)
                ed.print("Keynote \(key) — \(ed.doc.keynotes[key] ?? "(no description)")")
            }
        }
    }

    static let sectionLayer = "A-SECT"

    static var sectionCommand: CommandDef {
        CommandDef("SECTION", aliases: ["SECTIONLINE", "SECTIONMARK"], category: "View", summary: "Places a section line (A–A…) in plan; section views and sheets use the current section.") { ed in
            let a = try await ed.getPoint("Specify section start point", keywords: ["Current", "List"])
            @MainActor func markers() -> [(Int, String)] { ed.doc.entities.enumerated().compactMap { i, e in e.props["sectionMark"].map { (i, $0) } } }
            switch a {
            case .keyword("List"):
                let cur = ed.doc.variable("SECTION")
                for (_, m) in markers() { ed.print("\(m == cur ? "*" : " ") Section \(m)-\(m)") }
                return
            case .keyword("Current"):
                guard let m = try await ed.getWord("Enter section label"), markers().contains(where: { $0.1.caseInsensitiveCompare(m) == .orderedSame }) else { throw CommandError.invalid("No such section.") }
                ed.doc.setVariable("SECTION", m.uppercased()); ed.print("Current section: \(m.uppercased())")
                return
            case .point(let p0):
                let p1 = try await ed.requirePoint("Specify section end point", base: p0) { c in [.line(LineGeom(p0, c))] }
                guard p1.distance(to: p0) > 1e-6 else { return }
                let side = try await ed.getPoint("Specify viewing side (Enter = left of the line)", base: (p0 + p1) / 2).point
                var s = p0, e = p1
                if let sp = side, (p1 - p0).cross(sp - p0) < 0 { swap(&s, &e) }
                let used = Set(markers().map(\.1))
                var label = "A"
                for c in "ABCDEFGHJKLMNPQRSTUVWXYZ" where !used.contains(String(c)) { label = String(c); break }
                label = try await ed.getWord("Enter section label", defaultValue: label)?.uppercased() ?? label
                if ed.doc.layer(named: sectionLayer) == nil { ed.doc.layers.append(Layer(name: sectionLayer, color: RGBA(0.45, 0.7, 1.0), linetype: "Continuous", lineweight: 0.35)) }
                let id = ed.doc.add(.polyline(PolylineGeom(points: [s, e])), layer: sectionLayer)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["sectionMark"] = label }
                ed.doc.setVariable("SECTION", label)
                ed.print("Section \(label)-\(label) placed and made current (viewing to the left of \(fmt(s.x)),\(fmt(s.y)) → \(fmt(e.x)),\(fmt(e.y))).")
            default: return
            }
        }
    }

    /// Converts rendered view entries into block entities (polylines, solid hatches, text).
    static func entities(from entries: [DrawEntry]) -> [Entity] {
        func ref(_ c: RGBA) -> ColorRef {
            let a = max(0, min(1, c.a))
            func ch(_ v: Double) -> UInt8 { UInt8(max(0, min(255, ((v * a + (1 - a)) * 255).rounded()))) }
            return .rgb(ch(c.r), ch(c.g), ch(c.b))
        }
        var out: [Entity] = []
        for e in entries {
            for it in e.items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    guard pts.count >= 2 else { continue }
                    out.append(Entity(layer: "0", color: ref(st.color), linetype: st.dash.isEmpty ? nil : "Dashed", lineweight: st.lineweight, geometry: .polyline(PolylineGeom(points: pts, closed: closed))))
                case .fill(let loops, let c):
                    let ls = loops.filter { $0.count >= 3 }.map { $0.map { PolyVertex($0) } }
                    guard !ls.isEmpty else { continue }
                    out.append(Entity(layer: "0", color: ref(c), geometry: .hatch(HatchGeom(loops: ls, pattern: "SOLID"))))
                case .text(let t, _, let c):
                    out.append(Entity(layer: "0", color: ref(c), geometry: .text(t)))
                case .image: continue
                }
            }
        }
        return out
    }

    static func viewKind(_ s: String) -> ViewKind? {
        switch s.lowercased() {
        case "north": return .elevationNorth
        case "south": return .elevationSouth
        case "east": return .elevationEast
        case "west": return .elevationWest
        case "section": return .section
        default: return nil
        }
    }

    /// (Re)builds the block of a drawing view; returns the block name.
    @discardableResult
    static func buildViewBlock(_ doc: inout ArchiDocument, spec: String) -> String? {
        // spec: "north" | "south" | "east" | "west" | "section:A" | "legend:walls" | "solidsection:…" | "drafting:Name",
        // optionally followed by "|template=Name" (view template applied to the view).
        let (core, tpl) = ViewTemplates.split(spec)
        if let t = tpl {
            var td = ViewTemplates.applied(doc, template: t)
            guard let name = buildViewBlock(&td, spec: core), var b = td.blocks[name] else { return nil }
            b.description = "view:" + spec
            doc.blocks[name] = b
            return name
        }
        let parts = spec.split(separator: ":").map(String.init)
        if parts.first == "legend", parts.count >= 2 { return Legends.makeBlock(&doc, kind: parts[1]) }
        if parts.first == "drafting", parts.count >= 2 { let n = DraftingViews.blockName(parts[1]); return doc.blocks[n] != nil ? n : nil }
        if parts.first == "solidsection", parts.count >= 6, let x0 = Double(parts[1]), let y0 = Double(parts[2]), let x1 = Double(parts[3]), let y1 = Double(parts[4]) {
            let existing = doc.blocks.first { $0.value.description == "view:" + spec }?.key
            return SolidSections.makeBlock(&doc, a: Vec2(x0, y0), b: Vec2(x1, y1), name: existing, includeModel: parts[5] == "1")
        }
        if parts.first == "interior", parts.count == 3, let rid = Int(parts[1]), let k = Int(parts[2]), let room = doc.element(rid) {
            let entries = InteriorElevation.entries(doc: doc, room: room, index: k)
            guard !entries.isEmpty else { return nil }
            var box = BBox2.empty
            for e in entries { box.add(e.bounds) }
            let label = InteriorElevation.views(room: room, doc: doc)[k].label
            let name = "VIEW-INTERIOR-\(rid)-\(label)"
            doc.blocks[name] = Block(name: name, basePoint: box.min, entities: entities(from: entries), description: "view:" + spec)
            return name
        }
        if parts.first == "detail", parts.count == 7, let lv = Int(parts[1]), let x0 = Double(parts[2]), let y0 = Double(parts[3]), let x1 = Double(parts[4]), let y1 = Double(parts[5]) {
            let win = BBox2(points: [Vec2(x0, y0), Vec2(x1, y1)])
            guard win.width > 1e-9, win.height > 1e-9 else { return nil }
            var o = DrawOptions(level: lv)
            o.linetypeScale = 0.25
            let entries = DrawListBuilder.entries(doc: doc, options: o).filter { !$0.bounds.isEmpty && $0.bounds.intersects(win) }
            var ents = entities(from: clip(entries, to: win))
            ents.append(Entity(layer: "0", color: .byBlock, lineweight: 0.5, geometry: .polyline(PolylineGeom(points: win.corners, closed: true))))
            let name = "VIEW-DETAIL-" + parts[6]
            doc.blocks[name] = Block(name: name, basePoint: win.min, entities: ents, description: "view:" + spec)
            return name
        }
        guard let kind = viewKind(parts[0]) else { return nil }
        var sd = doc
        if kind == .section, parts.count > 1 { sd.setVariable("SECTION", parts[1]) }
        let entries = ElevationBuilder.entries(doc: sd, view: kind, sectionLine: nil)
        guard !entries.isEmpty else { return nil }
        var box = BBox2.empty
        for e in entries { box.add(e.bounds) }
        let name = kind == .section ? "VIEW-SECTION-\(parts.count > 1 ? parts[1] : "A")" : "VIEW-\(parts[0].uppercased())-ELEVATION"
        doc.blocks[name] = Block(name: name, basePoint: box.min, entities: entities(from: entries), description: "view:" + spec)
        return name
    }

    /// Clips draw entries to a rectangle (strokes and fills clipped, text kept when its anchor is inside).
    static func clip(_ entries: [DrawEntry], to win: BBox2) -> [DrawEntry] {
        let rect = win.corners
        func clipPoly(_ p: [Vec2]) -> [Vec2] {
            var q = p
            q = RG.clipHalfPlane(q, normal: Vec2(-1, 0), -win.min.x); q = RG.clipHalfPlane(q, normal: Vec2(1, 0), win.max.x)
            q = RG.clipHalfPlane(q, normal: Vec2(0, -1), -win.min.y); q = RG.clipHalfPlane(q, normal: Vec2(0, 1), win.max.y)
            return q
        }
        return entries.map { e in
            var items: [DrawItem] = []
            for it in e.items {
                switch it {
                case .stroke(let pts, let closed, let st):
                    let path = closed && pts.count > 2 ? pts + [pts[0]] : pts
                    for piece in RG.clipPolyline(path, [rect]) where piece.count >= 2 { items.append(.stroke(points: piece, closed: false, style: st)) }
                case .fill(let loops, let c):
                    // Even-odd loops are clipped separately (holes stay holes when they are inside the window).
                    let ls = loops.map(clipPoly).filter { $0.count >= 3 }
                    if !ls.isEmpty { items.append(.fill(loops: ls, color: c)) }
                case .text(let t, _, _): if win.contains(t.position) { items.append(it) }
                case .image: continue
                }
            }
            return DrawEntry(id: e.id, items: items)
        }
    }

    static var viewDrawCommand: CommandDef {
        CommandDef("VIEWDRAW", aliases: ["DRAWINGVIEW", "SECTIONVIEW", "ELEVATIONVIEW"], category: "View", summary: "Places an elevation or section of the model as a 2D drawing (with level heads and grid bubbles) in model space.") { ed in
            let k = try await ed.getKeyword("View", ["North", "South", "East", "West", "Section", "Detail"], defaultValue: "South") ?? "South"
            var spec = k.lowercased()
            if k == "Detail" {
                let a = try await ed.requirePoint("Specify first corner of the detail area")
                let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                let f = try await ed.getPositive("Specify enlargement factor", defaultValue: ed.variableDouble("DETAILSCALE", 5))
                ed.doc.setVariable("DETAILSCALE", fmt(f))
                let used = Set(ed.doc.blocks.keys.filter { $0.hasPrefix("VIEW-DETAIL-") })
                var n = 1
                while used.contains("VIEW-DETAIL-\(n)") { n += 1 }
                let w = BBox2(points: [a, b])
                spec = "detail:\(ed.doc.currentLevel):\(fmt(w.min.x, 6)):\(fmt(w.min.y, 6)):\(fmt(w.max.x, 6)):\(fmt(w.max.y, 6)):\(n)"
                guard let name = buildViewBlock(&ed.doc, spec: spec) else { throw CommandError.invalid("Nothing to show in that area.") }
                let p = try await ed.requirePoint("Specify lower-left corner of the detail view")
                ed.doc.ensureLayer("A-VIEW")
                let id = ed.doc.add(.insert(InsertGeom(block: name, position: p, scale: Vec2(f, f))), layer: "A-VIEW")
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = spec }
                ed.addEntity(.text(TextGeom(position: p + Vec2(0, -f * 60 / ed.doc.units.mm - 300 / ed.doc.units.mm), height: 300 / ed.doc.units.mm, content: "Detail \(n)  (×\(fmt(f)))")), layer: "A-VIEW")
                ed.print("\(name) placed at ×\(fmt(f)).")
                return
            }
            if k == "Section" {
                let marks = ed.doc.entities.compactMap { $0.props["sectionMark"] }
                let def = ed.doc.variable("SECTION") ?? marks.first
                if !marks.isEmpty, let m = try await ed.getWord("Enter section label [\(marks.joined(separator: "/"))]", defaultValue: def) { spec += ":" + m.uppercased() }
                else { spec += ":" + (def ?? "A") }
            }
            guard let name = buildViewBlock(&ed.doc, spec: spec) else { throw CommandError.invalid("Nothing to draw in that view.") }
            let p = try await ed.requirePoint("Specify lower-left corner of the view")
            ed.doc.ensureLayer("A-VIEW")
            let id = ed.doc.add(.insert(InsertGeom(block: name, position: p)), layer: "A-VIEW")
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = spec }
            ed.print("\(name) placed (\(ed.doc.blocks[name]?.entities.count ?? 0) objects). Use VIEWUPDATE after model changes.")
        }
    }

    static var viewUpdateCommand: CommandDef {
        CommandDef("VIEWUPDATE", aliases: ["UPDATEVIEWS"], category: "View", summary: "Regenerates all placed elevation/section drawing views from the current model.") { ed in
            var n = 0
            for (name, b) in ed.doc.blocks where b.description.hasPrefix("view:") {
                if buildViewBlock(&ed.doc, spec: String(b.description.dropFirst(5))) != nil { n += 1 } else { ed.print("\(name): view is now empty (kept).") }
            }
            ed.print("\(n) view(s) updated.")
        }
    }
}


// MARK: - Multi-storey workflows and sheet views

extension ArchitectureCommands {
    static func isElement(_ doc: ArchiDocument, _ id: EntityID, _ test: (BIMGeometry) -> Bool) -> Bool { doc.element(id).map { test($0.geometry) } ?? false }

    @MainActor static func selectWalls(_ ed: Editor, _ msg: String) async throws -> [EntityID] {
        ed.selection = ed.selection.filter { isWall(ed.doc, $0) }
        let ids = try await ed.getSelection(msg).filter { isWall(ed.doc, $0) }
        guard !ids.isEmpty else { throw CommandError.invalid("Select at least one wall.") }
        return ids
    }

    static var multiStorey: [CommandDef] { [
        CommandDef("COPYTOLEVEL", aliases: ["PASTEALIGNED", "COPYLEVELS", "CTL"], category: "Architecture", summary: "Copies selected building elements to other levels, aligned in plan (hosted doors and windows follow their walls).") { ed in
            let ids = try await ed.getSelection("Select building elements to copy")
            guard ids.contains(where: { ed.doc.element($0) != nil }) else { throw CommandError.invalid("Select building elements.") }
            let names = ed.doc.levels.sorted { $0.elevation < $1.elevation }.map(\.name).joined(separator: "/")
            let w = try await ed.getWord("Enter target levels separated by commas (\(names)) or [Above/All]", defaultValue: "Above", keywords: ["Above", "All"]) ?? "Above"
            let own = Set(ids.compactMap { ed.doc.element($0)?.level })
            let base = ed.doc.levels.filter { own.contains($0.id) }.map(\.elevation).min() ?? 0
            var targets: [Int] = []
            switch w {
            case "All": targets = ed.doc.levels.filter { !own.contains($0.id) }.map(\.id)
            case "Above": targets = ed.doc.levels.filter { $0.elevation > base + 1e-9 }.sorted { $0.elevation < $1.elevation }.prefix(1).map(\.id)
            default:
                for part in w.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
                    guard let l = levelLookup(ed, part) else { throw CommandError.invalid("Level \(part) not found.") }
                    targets.append(l.id)
                }
            }
            guard !targets.isEmpty else { throw CommandError.invalid("No target level.") }
            let made = LevelCopy.copy(&ed.doc, ids: ids, toLevels: targets)
            ed.selection = Set(made)
            ed.print("\(made.count) element(s) copied to " + targets.compactMap { ed.doc.level($0)?.name }.joined(separator: ", ") + ".")
        },
        CommandDef("WALLTOP", aliases: ["WALLCONSTRAINT", "TOPCONSTRAINT", "WT"], category: "Architecture", summary: "Sets the top constraint of walls: up to a level (with offset), the next level, or an unconnected height.") { ed in
            let ids = try await selectWalls(ed, "Select walls")
            let w = try await ed.getWord("Top constraint: level name, Next (level above) or Unconnected", defaultValue: "Next") ?? "Next"
            var spec = ""
            if w.lowercased() == "next" || w.lowercased() == "n" { spec = "next" }
            else if let l = levelLookup(ed, w) { spec = l.name }
            else if !w.lowercased().hasPrefix("u") { throw CommandError.invalid("Level \(w) not found.") }
            if spec.isEmpty {
                let h = try await ed.getPositive("Specify unconnected height", defaultValue: ed.settings.wallHeight)
                for id in ids { if let i = ed.doc.elementIndex(id), case .wall(var g) = ed.doc.elements[i].geometry { g.topLevel = nil; g.topOffset = 0; g.height = h; ed.doc.elements[i].geometry = .wall(g) } }
                ed.print("\(ids.count) wall(s) set to an unconnected height of \(fmt(h)).")
                return
            }
            let off = try await ed.getDistance("Specify top offset", defaultValue: 0).value ?? 0
            var n = 0
            for id in ids {
                guard let i = ed.doc.elementIndex(id), case .wall(var g) = ed.doc.elements[i].geometry,
                      let t = topLevelID(ed.doc, spec: spec, from: ed.doc.elements[i].level), let l = ed.doc.level(t) else { continue }
                let h = l.elevation + off - BIMConstraints.wallNominalBase(ed.doc.elements[i], doc: ed.doc)
                guard h > 1e-6 else { ed.print("#\(id): the top would be below the base; skipped."); continue }
                g.topLevel = t; g.topOffset = off; g.height = h
                ed.doc.elements[i].geometry = .wall(g); n += 1
            }
            ed.print("\(n) wall(s) now rise to their top level" + (abs(off) > 1e-9 ? " \(off > 0 ? "+" : "")\(fmt(off))" : "") + ".")
        },
        CommandDef("WALLATTACH", aliases: ["ATTACHWALL", "WALLDETACH"], category: "Architecture", summary: "Attaches the top of walls to a roof or slab soffit, or the base to a slab top; Detach removes the attachment.") { ed in
            let ids = try await selectWalls(ed, "Select walls")
            let k = try await ed.getKeyword("Attach [Top/Base/Detach]", ["Top", "Base", "Detach"], defaultValue: "Top") ?? "Top"
            if k == "Detach" {
                let which = try await ed.getKeyword("Detach [Top/Base/Both]", ["Top", "Base", "Both"], defaultValue: "Both") ?? "Both"
                for id in ids {
                    guard let i = ed.doc.elementIndex(id) else { continue }
                    if which != "Base" { ed.doc.elements[i].props["attachTopTo"] = nil; ed.doc.elements[i].props["attachTop"] = nil }
                    if which != "Top" { ed.doc.elements[i].props["attachBaseTo"] = nil }
                }
                ed.print("\(ids.count) wall(s) detached.")
                return
            }
            let top = k == "Top"
            guard case .pick(let pk) = try await ed.pickObject(top ? "Select the roof or slab to attach to" : "Select the slab (floor) to attach to", filter: { id in
                isElement(ed.doc, id) { g in
                    if case .slab = g { return true }
                    if top, case .roof = g { return true }
                    return false
                } }) else { return }
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                ed.doc.elements[i].props[top ? "attachTopTo" : "attachBaseTo"] = "\(pk.id)"
                if top { ed.doc.elements[i].props["attachTop"] = nil }
            }
            let host = ed.doc.element(pk.id)?.typeName ?? "element"
            ed.print("\(ids.count) wall(s) attached at the \(top ? "top" : "base") to \(host) #\(pk.id).")
        },
        CommandDef("ROOMBOUNDING", aliases: ["ROOMBOUND", "RBOUND"], category: "Architecture", summary: "Sets whether walls, curtain walls and columns bound rooms (used by ROOM, ROOMUPDATE and SLAB Walls).") { ed in
            let ids = try await ed.getSelection("Select walls, curtain walls or columns")
            let on = try await ed.getYesNo("Room bounding?", defaultValue: false)
            var n = 0
            for id in ids {
                guard let i = ed.doc.elementIndex(id) else { continue }
                switch ed.doc.elements[i].geometry {
                case .wall, .curtainWall: ed.doc.elements[i].props["roomBounding"] = on ? nil : "0"; n += 1
                case .column: ed.doc.elements[i].props["roomBounding"] = on ? "1" : nil; n += 1
                default: continue
                }
            }
            ed.print("\(n) element(s) are \(on ? "" : "not ")room bounding. Run ROOMUPDATE to recompute rooms.")
        },
        CommandDef("DATUMS3D", aliases: ["SHOWDATUMS", "LEVELS3D", "GRIDS3D"], category: "View", summary: "Shows or hides levels and grids (with heads) in the 3D view.") { ed in
            let cur = ed.doc.variable("DATUMS3D") == "1"
            let k = try await ed.getKeyword("Datums in 3D [ON/OFF]", ["ON", "OFF"], defaultValue: cur ? "OFF" : "ON") ?? "ON"
            ed.doc.setVariable("DATUMS3D", k == "ON" ? "1" : "0")
            ed.print("Levels and grids are \(k == "ON" ? "shown" : "hidden") in 3D.")
        },
        CommandDef("STAIRCHECK", aliases: ["CHECKSTAIRS", "STAIRRULES"], category: "Architecture", summary: "Checks stairs against riser, going, 2R+G, width, flight-length and landing rules.", modifies: false) { ed in
            var ids = ed.selection.filter { isElement(ed.doc, $0) { if case .stair = $0 { return true }; return false } }
            if ids.isEmpty { ids = Set(ed.doc.elements.filter { if case .stair = $0.geometry { return true }; return false }.map(\.id)) }
            guard !ids.isEmpty else { ed.print("No stairs."); return }
            var bad = 0
            for id in ids.sorted() {
                guard case .stair(let s)? = ed.doc.element(id)?.geometry else { continue }
                let issues = BIMConstraints.stairIssues(s, units: ed.doc.units)
                if issues.isEmpty { ed.print("Stair #\(id): OK (\(s.riserCount) × \(fmt(s.riserHeight, 1)) / \(fmt(s.treadDepth)))") }
                else { bad += 1; for i in issues { ed.print("Stair #\(id): \(i)") } }
            }
            ed.print(bad == 0 ? "All stairs comply." : "\(bad) stair(s) need attention.")
        },
    ] }

    static let symbolLayer = "A-ANNO-SYMB"

    @MainActor static func ensureSymbolLayer(_ ed: Editor) {
        if ed.doc.layer(named: symbolLayer) == nil { ed.doc.layers.append(Layer(name: symbolLayer, color: RGBA(0.961, 0.773, 0.094), lineweight: 0.25, description: "View symbols")) }
    }

    /// 4-way interior elevation marker entities (circle, four arrows, letters) at `c`, scaled by the unit.
    static func interiorMarker(at c: Vec2, views: [InteriorElevation.View], unit u: Double) -> [Geometry] {
        let r = 300 * u
        var out: [Geometry] = [.circle(CircleGeom(c, r))]
        for v in views {
            let f = v.direction, n = f.perp
            let tip = c + f * (r * 1.7)
            let tri = [tip, c + f * (r * 0.75) + n * (r * 0.75), c + f * (r * 0.75) - n * (r * 0.75)]
            out.append(.hatch(HatchGeom(loops: [tri.map { PolyVertex($0) }], pattern: "SOLID")))
            out.append(.text(TextGeom(position: c + f * (r * 0.55), height: 160 * u, content: v.label, halign: .center, valign: .middle)))
        }
        return out
    }

    /// Callout symbol: rounded boundary, leader and a bubble with the detail number over the sheet reference.
    static func calloutSymbol(_ win: BBox2, number: Int, sheet: String, bubble: Vec2, unit u: Double) -> [Geometry] {
        let r = min(250 * u, min(win.width, win.height) * 0.15)
        let c = win.corners
        var pts: [Vec2] = []
        let centers = [Vec2(c[0].x + r, c[0].y + r), Vec2(c[1].x - r, c[1].y + r), Vec2(c[2].x - r, c[2].y - r), Vec2(c[3].x + r, c[3].y - r)]
        for (k, cc) in centers.enumerated() { pts += GeometryOps.arcPoints(center: cc, radius: r, start: -Double.pi / 2 + Double(k) * .pi / 2 - .pi / 2, sweep: .pi / 2) }
        let br = 350 * u
        let corner = c.min { $0.distance(to: bubble) < $1.distance(to: bubble) }!
        let dir = (bubble - corner).normalized
        return [.polyline(PolylineGeom(points: pts, closed: true)),
                .line(LineGeom(corner, bubble - dir * br)),
                .circle(CircleGeom(bubble, br)),
                .line(LineGeom(bubble - Vec2(br, 0), bubble + Vec2(br, 0))),
                .text(TextGeom(position: bubble + Vec2(0, br * 0.45), height: br * 0.55, content: "\(number)", halign: .center, valign: .middle)),
                .text(TextGeom(position: bubble - Vec2(0, br * 0.45), height: br * 0.4, content: sheet, halign: .center, valign: .middle))]
    }

    /// View title entities under a viewport on a sheet (paper mm): number bubble, title, rule and scale.
    static func viewTitle(_ vp: Viewport, number: Int, title: String) -> [Geometry] {
        let r = 5.0
        let c = Vec2(vp.origin.x + r, vp.origin.y - r - 3)
        let scale = vp.scale >= 1 ? "1 : \(fmt(vp.scale))" : "\(fmt(1 / max(vp.scale, 1e-9))) : 1"
        let lineLen = max(min(vp.size.x - 2 * r - 4, 90), Double(title.count) * 2.4 + 6)
        return [.circle(CircleGeom(c, r)),
                .text(TextGeom(position: c, height: 3.5, content: "\(number)", halign: .center, valign: .middle)),
                .line(LineGeom(Vec2(c.x + r, c.y), Vec2(c.x + r + 2 + lineLen, c.y))),
                .text(TextGeom(position: Vec2(c.x + r + 2, c.y + 1.2), height: 3.5, content: title.uppercased(), valign: .bottom)),
                .text(TextGeom(position: Vec2(c.x + r + 2, c.y - 1.2), height: 2.5, content: scale, valign: .top))]
    }

    static func defaultTitle(_ vp: Viewport, doc: ArchiDocument) -> String {
        if !vp.title.isEmpty { return vp.title }
        let lvl = vp.level.flatMap { doc.level($0)?.name }
        switch vp.view {
        case .plan: return lvl ?? "Floor Plan"
        case .ceiling: return (lvl.map { $0 + " " } ?? "") + "Ceiling Plan"
        case .elevationNorth: return "North Elevation"
        case .elevationSouth: return "South Elevation"
        case .elevationEast: return "East Elevation"
        case .elevationWest: return "West Elevation"
        case .section: return "Section " + (doc.variable("SECTION") ?? "A")
        case .axonometric: return "Axonometric"
        case .perspective: return "Perspective"
        }
    }

    static var sheetViews: [CommandDef] { [
        CommandDef("INTERIORELEV", aliases: ["INTERIORELEVATION", "IELEV", "ROOMELEVATIONS"], category: "View", summary: "Places a 4-way interior elevation marker in a room and draws its four interior elevations (A–D).") { ed in
            let p = try await ed.requirePoint("Pick a point inside a room")
            guard let room = ed.doc.elements.first(where: { el in
                if el.level == ed.doc.currentLevel, el.props["areaScheme"] == nil, case .space(let sp) = el.geometry { return GeometryOps.pointInPolygon(p, sp.boundary) }; return false }),
                  case .space(let sp) = room.geometry else { throw CommandError.invalid("No room there (place rooms with ROOM first).") }
            let views = InteriorElevation.views(room: room, doc: ed.doc)
            let u = 1 / ed.doc.units.mm
            ensureSymbolLayer(ed)
            let marker = LabelPlacement.pole(of: sp.boundary).point
            for g in interiorMarker(at: marker, views: views, unit: u) {
                let id = ed.doc.add(g, layer: symbolLayer)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["interiorMarker"] = "\(room.id)"; ed.doc.entities[i].props["level"] = "\(room.level)" }
            }
            var at = try await ed.requirePoint("Specify lower-left corner of the first elevation")
            ed.doc.ensureLayer("A-VIEW")
            var n = 0
            let roomName = sp.name.isEmpty ? room.name : sp.name
            for k in 0..<views.count {
                let spec = "interior:\(room.id):\(k)"
                guard let name = buildViewBlock(&ed.doc, spec: spec) else { continue }
                let id = ed.doc.add(.insert(InsertGeom(block: name, position: at)), layer: "A-VIEW")
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = spec }
                ed.addEntity(.text(TextGeom(position: at + Vec2(0, -350 * u), height: 250 * u, content: "\(roomName) \(sp.number) – \(views[k].label)")), layer: "A-VIEW")
                at = at + Vec2(views[k].width + 1500 * u, 0)
                n += 1
            }
            ed.print("Interior elevation marker placed; \(n) elevation(s) drawn. Use VIEWUPDATE after model changes.")
        },
        CommandDef("CALLOUT", aliases: ["DETAILCALLOUT", "CALL"], category: "View", summary: "Draws a callout (boundary, leader and numbered bubble) in plan and places the enlarged detail view it refers to.") { ed in
            let a = try await ed.requirePoint("Specify first corner of the callout area")
            let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
            let win = BBox2(points: [a, b])
            guard win.width > 1e-6, win.height > 1e-6 else { throw CommandError.invalid("The callout needs an area.") }
            let bubble = try await ed.requirePoint("Specify callout bubble location", base: win.max)
            let f = try await ed.getPositive("Specify enlargement factor", defaultValue: ed.variableDouble("DETAILSCALE", 5))
            let sheet = try await ed.getWord("Enter sheet reference", defaultValue: ed.doc.variable("CALLOUTSHEET") ?? "-") ?? "-"
            ed.doc.setVariable("DETAILSCALE", fmt(f)); ed.doc.setVariable("CALLOUTSHEET", sheet)
            let used = Set(ed.doc.blocks.keys.filter { $0.hasPrefix("VIEW-DETAIL-") })
            var n = 1
            while used.contains("VIEW-DETAIL-\(n)") { n += 1 }
            let spec = "detail:\(ed.doc.currentLevel):\(fmt(win.min.x, 6)):\(fmt(win.min.y, 6)):\(fmt(win.max.x, 6)):\(fmt(win.max.y, 6)):\(n)"
            guard let name = buildViewBlock(&ed.doc, spec: spec) else { throw CommandError.invalid("Nothing to show in that area.") }
            let u = 1 / ed.doc.units.mm
            ensureSymbolLayer(ed)
            for g in calloutSymbol(win, number: n, sheet: sheet, bubble: bubble, unit: u) {
                let id = ed.doc.add(g, layer: symbolLayer)
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["callout"] = "\(n)"; ed.doc.entities[i].props["level"] = "\(ed.doc.currentLevel)" }
            }
            let p = try await ed.requirePoint("Specify lower-left corner of the detail view")
            ed.doc.ensureLayer("A-VIEW")
            let id = ed.doc.add(.insert(InsertGeom(block: name, position: p, scale: Vec2(f, f))), layer: "A-VIEW")
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["view"] = spec }
            ed.addEntity(.text(TextGeom(position: p + Vec2(0, -400 * u), height: 300 * u, content: "Detail \(n)  (×\(fmt(f)))")), layer: "A-VIEW")
            ed.print("Callout \(n) placed with its detail view (\(name)).")
        },
        CommandDef("VIEWTITLE", aliases: ["VIEWTITLES", "VPTITLE"], category: "Layout", summary: "Adds or refreshes view titles (number bubble, name, scale) under every viewport of a sheet.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("There are no sheets.") }
            let cur = FileViewCommands.currentLayoutIndex(ed) ?? 0
            let n = try await ed.getWord("Enter sheet name", defaultValue: ed.doc.layouts[cur].name) ?? ed.doc.layouts[cur].name
            guard let li = ed.doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("Sheet \(n) not found.") }
            ed.doc.layouts[li].entities.removeAll { $0.props["viewTitle"] != nil }
            ed.doc.ensureLayer("A-ANNO-TTLB")
            for (k, vp) in ed.doc.layouts[li].viewports.enumerated() {
                let title = defaultTitle(vp, doc: ed.doc)
                for g in viewTitle(vp, number: k + 1, title: title) {
                    var e = Entity(id: 0, layer: "A-ANNO-TTLB", color: .byLayer, geometry: g)
                    e.props["viewTitle"] = "\(k + 1)"
                    e.id = ed.doc.allocateID()
                    ed.doc.layouts[li].entities.append(e)
                }
            }
            ed.print("\(ed.doc.layouts[li].viewports.count) view title(s) on \(ed.doc.layouts[li].name).")
        },
    ] }
}
