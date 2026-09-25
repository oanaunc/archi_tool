// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

enum ArchitectureCommands {
    static var all: [CommandDef] { walls + openings + horizontals + structure + spaces + management }

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
        guard let inner = RegionFinder.roomBoundary(at: p, doc: ed.doc, level: ed.doc.currentLevel) else { ed.print("No closed wall loop found around that point."); return nil }
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
            @MainActor func options(_ k: String) async throws {
                switch k {
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
            func geom(_ a: Vec2, _ b: Vec2, bulge: Double = 0) -> WallGeom {
                WallGeom(start: a, end: b, thickness: s.wallThickness, height: s.wallHeight, baseOffset: baseOffset, justification: s.wallJustification, bulge: bulge, wallType: wallType)
            }
            var first: Vec2
            while true {
                ed.print("Current settings: Thickness = \(fmt(s.wallThickness)), Height = \(fmt(s.wallHeight)), Justify = \(s.wallJustification.rawValue)\(wallType.map { ", Type = \($0)" } ?? "")")
                let a = try await ed.getPoint("Specify start point", keywords: ["Thickness", "Height", "Justify", "Type", "Base"])
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
                var kws = ["Arc", "Undo", "Thickness", "Height", "Justify"]
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
        @MainActor func save() {
            ed.doc.setVariable(key + "WIDTH", fmt(width)); ed.doc.setVariable(key + "HEIGHT", fmt(height)); ed.doc.setVariable(key + "SILL", fmt(sill))
            ed.doc.setVariable("DOORSTYLE", doorStyle.rawValue); ed.doc.setVariable("WINDOWSTYLE", windowStyle.rawValue)
        }
        while true {
            var kws = ["Width", "Height", "Sill", "Flip"]
            if kind != .opening { kws.insert("Style", at: 3) }
            ed.print("\(kind.rawValue.capitalized): Width = \(fmt(width)), Height = \(fmt(height)), Sill = \(fmt(sill))" + (kind == .door ? ", Style = \(doorStyle.rawValue)" : kind == .window ? ", Style = \(windowStyle.rawValue)" : ""))
            let a = try await ed.pickObject("Select wall location for the \(kind.rawValue)", keywords: kws) { isWall(ed.doc, $0) }
            switch a {
            case .keyword("Width"): width = try await ed.getPositive("Specify width", defaultValue: width)
            case .keyword("Height"): height = try await ed.getPositive("Specify height", defaultValue: height)
            case .keyword("Sill"): sill = try await ed.getPositive("Specify sill height", defaultValue: sill, allowZero: true)
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
                let o = OpeningGeom(kind: kind, hostWall: pk.id, offset: along, width: width, height: height, sill: sill, flipHand: flip, flipFacing: facing, doorStyle: doorStyle, windowStyle: windowStyle)
                ed.doc.addElement(.opening(o), level: host.level, name: kind == .door ? "Door \(fmt(width))x\(fmt(height))" : (kind == .window ? "Window \(fmt(width))x\(fmt(height))" : "Opening"))
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
            let a = try await ed.getPoint("Specify first point of \(ceiling ? "ceiling" : "slab") boundary", keywords: ["Select", "Walls", "Thickness", "Offset"])
            switch a {
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
        if ceiling, let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["kind"] = "ceiling"; ed.doc.elements[i].material = "Plaster" }
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
        CommandDef("STAIR", aliases: ["STAIRS"], category: "Architecture", summary: "Creates a straight stair (width, rise, risers, tread).") { ed in
            var width = ed.variableDouble("STAIRWIDTH", 1000)
            var rise = ed.currentLevelHeight
            var tread = ed.variableDouble("STAIRTREAD", 280)
            var risers: Int? = nil
            var kind = StairKind(rawValue: ed.doc.variable("STAIRKIND") ?? "") ?? .straight
            var start: Vec2
            while true {
                let rc = risers ?? max(2, Int((rise / 175).rounded()))
                ed.print("Stair: Width = \(fmt(width)), Rise = \(fmt(rise)), Risers = \(rc) (\(fmt(rise / Double(rc), 1)) each), Tread = \(fmt(tread))")
                let a = try await ed.getPoint("Specify start point of stair (bottom, center of first riser)", keywords: ["Width", "Rise", "Risers", "Tread", "Kind"])
                switch a {
                case .point(let p): start = p
                case .keyword("Width"): width = try await ed.getPositive("Specify stair width", defaultValue: width); continue
                case .keyword("Rise"): rise = try await ed.getPositive("Specify total rise", defaultValue: rise); risers = nil; continue
                case .keyword("Risers"): if let n = try await ed.getInteger("Specify number of risers", defaultValue: rc), n >= 2, n <= 200 { risers = n } else { ed.print("Enter 2 to 200 risers.") }; continue
                case .keyword("Tread"): tread = try await ed.getPositive("Specify tread depth", defaultValue: tread); continue
                case .keyword("Kind"):
                    let k = try await ed.getKeyword("Stair kind", ["Straight", "LShape", "UShape", "Spiral"], defaultValue: "Straight") ?? "Straight"
                    kind = StairKind.allCases.first { $0.rawValue.lowercased() == k.lowercased() } ?? .straight; continue
                default: return
                }
                break
            }
            let rc = risers ?? max(2, Int((rise / 175).rounded()))
            let preview: (Vec2) -> [Geometry] = { c in
                let s = StairGeom(start: start, direction: (c - start).angle, width: width, totalRise: rise, riserCount: rc, treadDepth: tread, kind: kind)
                return [footprintPreview(CommandHelpers.footprint(BIMElement(geometry: .stair(s)), doc: ArchiDocument()))]
            }
            let dir = try await ed.getAngle("Specify direction of travel (up)", base: start, defaultValue: 0, preview: preview).value ?? 0
            ed.doc.setVariable("STAIRWIDTH", fmt(width)); ed.doc.setVariable("STAIRTREAD", fmt(tread)); ed.doc.setVariable("STAIRKIND", kind.rawValue)
            let s = StairGeom(start: start, direction: dir, width: width, totalRise: rise, riserCount: rc, treadDepth: tread, kind: kind)
            ed.doc.addElement(.stair(s), name: "Stair")
            ed.print("Stair created: \(rc) risers of \(fmt(s.riserHeight, 1)), run \(fmt(s.runLength)).")
            let rh = s.riserHeight
            if rh > 190 || rh < 140 || 2 * rh + tread < 600 || 2 * rh + tread > 650 { ed.print("Note: riser/tread proportions are outside the usual comfort range (2R + T ≈ 630).") }
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
                        if el.level == ed.doc.currentLevel, case .space(let s) = el.geometry { return GeometryOps.pointInPolygon(p, s.boundary) }; return false }) {
                        ed.print("A room is already placed there."); continue
                    }
                    let separators = ed.doc.entities.filter { $0.layer.uppercased().contains("SEP") && ed.doc.isVisible(layer: $0.layer) }.map(\.geometry)
                    guard let b = RegionFinder.roomBoundary(at: p, doc: ed.doc, level: ed.doc.currentLevel, extraCurves: separators) else { ed.print("No enclosing walls found (use Points)."); continue }
                    place(b)
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
        CommandDef("COMPONENT", aliases: ["FURNITURE", "COMP", "FURN"], category: "Architecture", summary: "Places furniture, fixtures and other components from presets or custom sizes.") { ed in
            let names = componentPresets.map(\.0) + ["Custom"]
            let k = try await ed.getKeyword("Enter component type", names, defaultValue: ed.doc.variable("COMPONENT") ?? "Chair") ?? "Chair"
            ed.doc.setVariable("COMPONENT", k)
            var cat = "Furniture", size = Vec3(600, 600, 750)
            if let p = componentPresets.first(where: { $0.0 == k }) { cat = p.1; size = p.2 }
            else {
                cat = try await ed.getWord("Enter category", defaultValue: "Furniture") ?? "Furniture"
                size.x = try await ed.getPositive("Specify width", defaultValue: size.x)
                size.y = try await ed.getPositive("Specify depth", defaultValue: size.y)
                size.z = try await ed.getPositive("Specify height", defaultValue: size.z)
            }
            var rot = 0.0
            var n = 0
            while true {
                let (r, sz) = (rot, size)
                let a = try await ed.getPoint("Specify insertion point (center)", keywords: ["Rotation", "Size"]) { c in
                    [footprintPreview(CommandHelpers.footprint(BIMElement(geometry: .component(ComponentGeom(category: cat, position: c, rotation: r, size: sz))), doc: ArchiDocument()))] }
                switch a {
                case .point(let p):
                    ed.doc.addElement(.component(ComponentGeom(category: cat, position: p, rotation: rot, size: size)), name: k == "Custom" ? cat : k)
                    n += 1
                case .keyword("Rotation"): rot = try await ed.getAngle("Specify rotation angle", defaultValue: rot).value ?? rot
                case .keyword("Size"):
                    size.x = try await ed.getPositive("Specify width", defaultValue: size.x)
                    size.y = try await ed.getPositive("Specify depth", defaultValue: size.y)
                    size.z = try await ed.getPositive("Specify height", defaultValue: size.z)
                default: if n > 0 { ed.print("\(n) \(k.lowercased())(s) placed.") }; return
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
            case "Height":
                let l = try await pickLevel("Enter level")
                let v = try await ed.getPositive("Specify floor-to-floor height", defaultValue: l.height)
                if let i = ed.doc.levels.firstIndex(where: { $0.id == l.id }) { ed.doc.levels[i].height = v }
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
            let k = try await ed.getKeyword("Enter schedule type", ["Walls", "Doors", "Windows", "Rooms", "Slabs", "All"], defaultValue: "Rooms") ?? "Rooms"
            let kind = k.lowercased()
            var csv = ScheduleExporter.csv(doc: ed.doc, kind: kind)
            if csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { csv = fallbackSchedule(ed.doc, kind) }
            let rows = parseCSV(csv).filter { !$0.allSatisfy { $0.isEmpty } }
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
