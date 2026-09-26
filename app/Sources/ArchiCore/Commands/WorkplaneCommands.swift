// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Work planes and project coordinates: reference planes (RP, PRC-038), UCS icon (UCSICON, PRC-034), plan view of the UCS
/// (PLAN, PRC-037), true north and plan orientation (TRUENORTH / PLANORIENT, PRC-039), project base point and survey point
/// (BASEPOINT / SURVEYPOINT, PRC-040) and axis locking (AXISLOCK, PRC-028).
enum WorkplaneCommands {
    static var all: [CommandDef] { [referencePlane, ucsIcon, plan, trueNorth, planOrient, basePoint, surveyPoint, axisLock] }

    @MainActor static func setTwist(_ ed: Editor, degrees d0: Double) {
        var d = d0.truncatingRemainder(dividingBy: 360); if d < 0 { d += 360 }
        if d < 1e-9 || d > 360 - 1e-9 { ed.doc.variables["VIEWTWIST"] = nil } else { ed.doc.setVariable("VIEWTWIST", fmt(d, 6)) }
    }

    // MARK: Reference planes
    static var referencePlane: CommandDef {
        CommandDef("RP", aliases: ["REFPLANE", "REFERENCEPLANE"], category: "Settings", summary: "Draws a named reference plane (work plane) or lists, renames, deletes one or makes it the current UCS.") { ed in
            while true {
                let a = try await ed.getPoint("Specify start point", keywords: ["List", "Set", "Rename", "Delete"])
                switch a {
                case .point(let p0):
                    let p1 = try await ed.requirePoint("Specify end point", base: p0) { c in [.line(LineGeom(p0, c))] }
                    let def = ReferencePlanes.nextName(ed.doc)
                    var name = try await ed.getString("Enter name", defaultValue: def) ?? def
                    name = name.trimmingCharacters(in: .whitespaces); if name.isEmpty { name = def }
                    guard ReferencePlanes.find(name, in: ed.doc) == nil else { throw CommandError.invalid("A reference plane named \(name) already exists.") }
                    guard let e = ReferencePlanes.make(name: name, from: p0, to: p1) else { throw CommandError.invalid("Points coincide.") }
                    ReferencePlanes.ensureLayer(&ed.doc)
                    ed.doc.add(e)
                    ed.print("Reference plane \"\(name)\" created.")
                    return
                case .keyword("List"):
                    let all = ReferencePlanes.all(ed.doc)
                    if all.isEmpty { ed.print("No reference planes.") }
                    for r in all { ed.print("  \(r.name): \(fmt(r.a.x)),\(fmt(r.a.y)) → \(fmt(r.b.x)),\(fmt(r.b.y))  (#\(r.id))") }
                    return
                case .keyword("Set"):
                    guard let n = try await ed.getString("Enter reference plane name"), let f = ReferencePlanes.frame(n, in: ed.doc) else { throw CommandError.invalid("Reference plane not found.") }
                    f.apply(to: &ed.doc)
                    ed.print("Work plane set to \"\(n)\" (UCS origin \(fmt(f.origin.x)),\(fmt(f.origin.y)), X axis \(fmt(deg(f.angle)))°).")
                    return
                case .keyword("Rename"):
                    guard let o = try await ed.getString("Enter reference plane name"), let r = ReferencePlanes.find(o, in: ed.doc),
                          let n = try await ed.getString("Enter new name"), !n.isEmpty else { throw CommandError.invalid("Reference plane not found.") }
                    guard ReferencePlanes.find(n, in: ed.doc) == nil else { throw CommandError.invalid("Name in use.") }
                    if let i = ed.doc.entityIndex(r.id) { ed.doc.entities[i].props[ReferencePlanes.prop] = n }
                    return
                case .keyword("Delete"):
                    guard let n = try await ed.getString("Enter reference plane name"), let r = ReferencePlanes.find(n, in: ed.doc) else { throw CommandError.invalid("Reference plane not found.") }
                    ed.doc.remove(ids: [r.id])
                    return
                default: return
                }
            }
        }
    }

    // MARK: UCS icon
    static var ucsIcon: CommandDef {
        CommandDef("UCSICON", category: "Settings", summary: "Controls the UCS icon: ON, OFF, Noorigin (lower-left corner) or ORigin (at the UCS origin when visible).") { ed in
            let cur = UCSIcon.mode(ed.doc)
            guard let k = try await ed.getKeyword("Enter an option", ["ON", "OFF", "Noorigin", "ORigin"], defaultValue: cur.on ? "ON" : "OFF") else { return }
            var m = cur
            switch k {
            case "ON": m.on = true
            case "OFF": m.on = false
            case "Noorigin": m.atOrigin = false
            default: m.atOrigin = true
            }
            UCSIcon.setMode(m, &ed.doc)
            ed.print("UCS icon \(m.on ? "on" : "off")\(m.on ? (m.atOrigin ? ", at origin" : ", in the corner") : "").")
        }
    }

    // MARK: PLAN
    static var plan: CommandDef {
        CommandDef("PLAN", category: "View", summary: "Shows the plan view of the current UCS, a named UCS or the world (rotates the 2D display so the UCS X axis is horizontal).") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Current", "Ucs", "World"], defaultValue: "Current") ?? "Current"
            var f = UCSFrame.current(ed.doc)
            switch k {
            case "World": f = .world
            case "Ucs":
                guard let n = try await ed.getWord("Enter name of UCS"), let g = ed.doc.variable("UCS:" + n).flatMap(UCSFrame.init(text:)) else { throw CommandError.invalid("UCS not found.") }
                f = g
            default: break
            }
            setTwist(ed, degrees: -deg(f.angle))
            ed.host?.perform(.show2D, editor: ed)
            ed.host?.perform(.zoomExtents, editor: ed)
            ed.print("Plan view of the \(k == "World" ? "world" : "UCS") (X axis \(fmt(deg(f.angle)))°).")
        }
    }

    // MARK: True north
    static var trueNorth: CommandDef {
        CommandDef("TRUENORTH", aliases: ["NORTHROTATION", "ROTATETRUENORTH"], category: "Settings", summary: "Sets true north relative to project north (angle counter-clockwise from up, or Align to a picked direction).") { ed in
            let sc = SharedCoordinates.current(ed.doc)
            let a = try await ed.getReal("Specify angle of true north from project north (degrees, counter-clockwise)", defaultValue: sc.northAngle, keywords: ["Align"])
            var d: Double
            if case .keyword("Align") = a {
                let p0 = try await ed.requirePoint("Specify base point")
                let p1 = try await ed.requirePoint("Specify point towards true north", base: p0) { c in [.line(LineGeom(p0, c))] }
                guard p0.distance(to: p1) > 1e-9 else { throw CommandError.invalid("Points coincide.") }
                d = deg((p1 - p0).angle) - 90
            } else { guard let v = a.value else { return }; d = v }
            d = d.truncatingRemainder(dividingBy: 360); if d > 180 { d -= 360 }; if d <= -180 { d += 360 }
            var s = sc; s.northAngle = d
            s.apply(to: &ed.doc)
            if (ed.doc.variable("PLANORIENT") ?? "").lowercased().hasPrefix("t") { setTwist(ed, degrees: -d) }
            ed.print("True north is \(fmt(d, 4))° from project north.")
        }
    }
    static var planOrient: CommandDef {
        CommandDef("PLANORIENT", aliases: ["ORIENTATION"], category: "View", summary: "Orients the plan to Project north (up) or True north (display rotation only).") { ed in
            let cur = (ed.doc.variable("PLANORIENT") ?? "Project").lowercased().hasPrefix("t") ? "True" : "Project"
            guard let k = try await ed.getKeyword("Enter orientation", ["Project", "True"], defaultValue: cur) else { return }
            ed.doc.setVariable("PLANORIENT", k)
            setTwist(ed, degrees: k == "True" ? -ed.doc.info.northAngle : 0)
            ed.print("Plan oriented to \(k.lowercased()) north.")
        }
    }

    // MARK: Project base point / survey point
    @MainActor static func listCoordinates(_ ed: Editor) {
        let s = SharedCoordinates.current(ed.doc)
        ed.print("Project base point: \(fmt(s.basePoint.x, 4)),\(fmt(s.basePoint.y, 4))   shared E \(fmt(s.easting, 4)) N \(fmt(s.northing, 4))   elevation \(fmt(s.elevation, 4))")
        let sp = s.surveyPoint
        ed.print("Survey point (shared 0,0): \(fmt(sp.x, 4)),\(fmt(sp.y, 4))   true north \(fmt(s.northAngle, 4))° from project north")
    }
    static var basePoint: CommandDef {
        CommandDef("PROJECTBASEPOINT", aliases: ["PBP", "SHAREDCOORDINATES"], category: "Settings", summary: "Project base point: its location, shared coordinates (easting/northing) and elevation; List or Reset.") { ed in
            var s = SharedCoordinates.current(ed.doc)
            let a = try await ed.getPoint("Specify project base point location", keywords: ["Shared", "Elevation", "List", "Reset"])
            switch a {
            case .point(let p): s.basePoint = p
            case .keyword("Shared"):
                let t = try await ed.getWord("Enter shared coordinates of the base point (easting,northing)", defaultValue: "\(fmt(s.easting)),\(fmt(s.northing))") ?? ""
                let v = t.split(separator: ",").compactMap { InputParser.parseNumber(String($0)) }
                guard v.count == 2 else { throw CommandError.invalid("Enter easting,northing.") }
                s.easting = v[0]; s.northing = v[1]
            case .keyword("Elevation"): s.elevation = try await ed.getReal("Enter elevation of the base point", defaultValue: s.elevation).value ?? s.elevation
            case .keyword("Reset"): let n = s.northAngle; s = SharedCoordinates(); s.northAngle = n
            case .keyword("List"): listCoordinates(ed); return
            default: return
            }
            s.apply(to: &ed.doc)
            listCoordinates(ed)
        }
    }
    static var surveyPoint: CommandDef {
        CommandDef("SURVEYPOINT", aliases: ["SURVEY"], category: "Settings", summary: "Places the survey point: a location and its shared coordinates (the base point's shared coordinates follow).") { ed in
            var s = SharedCoordinates.current(ed.doc)
            let p = try await ed.requirePoint("Specify survey point location")
            let t = try await ed.getWord("Enter shared coordinates of this point (easting,northing)", defaultValue: "0,0") ?? "0,0"
            let v = t.split(separator: ",").compactMap { InputParser.parseNumber(String($0)) }
            guard v.count == 2 else { throw CommandError.invalid("Enter easting,northing.") }
            // Keep the rotation and base point; solve the base point's shared coordinates so that p → (e, n).
            let local = (p - s.basePoint).rotated(by: -rad(s.northAngle))
            s.easting = v[0] - local.x; s.northing = v[1] - local.y
            s.apply(to: &ed.doc)
            listCoordinates(ed)
        }
    }

    // MARK: Axis lock
    static var axisLock: CommandDef {
        CommandDef("AXISLOCK", aliases: ["LOCKAXIS"], category: "Settings", summary: "Locks point input to the UCS X or Y axis, an angle, or turns the lock Off (arrow keys while drawing).", modifies: false) { ed in
            guard let k = try await ed.getKeyword("Lock to", ["X", "Y", "Angle", "Off"], defaultValue: ed.settings.axisLock == nil ? "X" : "Off") else { return }
            switch k {
            case "Off": ed.lockAxis(nil)
            case "Angle":
                guard let a = try await ed.getAngle("Specify axis angle").value else { return }
                ed.settings.axisLock = a
            default: ed.lockAxis(k)
            }
            ed.print(ed.settings.axisLock.map { "Axis locked at \(fmt(deg($0), 4))°." } ?? "Axis lock off.")
        }
    }
}

/// UCS icon display settings (PRC-034): UCSICON bit 1 = on, bit 2 = at the origin when it is on screen.
public enum UCSIcon {
    public struct Mode: Equatable { public var on: Bool; public var atOrigin: Bool }
    public static func mode(_ doc: ArchiDocument) -> Mode {
        let v = doc.variable("UCSICON").flatMap(Int.init) ?? 3
        return Mode(on: v & 1 != 0, atOrigin: v & 2 != 0)
    }
    public static func setMode(_ m: Mode, _ doc: inout ArchiDocument) {
        doc.setVariable("UCSICON", "\((m.on ? 1 : 0) | (m.atOrigin ? 2 : 0))")
    }
    /// Where to draw the icon (world point) given the visible area: the UCS origin when "at origin" and visible, otherwise
    /// the lower-left corner inset by `inset`. Nil when the icon is off.
    public static func anchor(_ doc: ArchiDocument, visible: BBox2, inset: Double) -> Vec2? {
        let m = mode(doc)
        guard m.on, !visible.isEmpty else { return nil }
        let o = UCSFrame.current(doc).origin
        let inner = BBox2(min: visible.min + Vec2(inset, inset), max: visible.max - Vec2(inset, inset))
        if m.atOrigin, !inner.isEmpty, inner.contains(o) { return o }
        return visible.min + Vec2(inset, inset)
    }
    /// Icon strokes (X and Y arrows with letters) of length `size` at `anchor`, along the current UCS axes.
    public static func geometry(_ doc: ArchiDocument, at anchor: Vec2, size: Double) -> [Geometry] {
        let f = UCSFrame.current(doc)
        let x = f.vectorToWorld(Vec2(1, 0)), y = f.vectorToWorld(Vec2(0, 1))
        func arrow(_ d: Vec2) -> [Geometry] {
            let tip = anchor + d * size, back = tip - d * (size * 0.18), n = d.perp * (size * 0.07)
            return [.line(LineGeom(anchor, tip)), .polyline(PolylineGeom(points: [back + n, tip, back - n], closed: true))]
        }
        var out = arrow(x) + arrow(y)
        let h = size * 0.2
        out.append(.text(TextGeom(position: anchor + x * (size * 1.08) - y * (h / 2), height: h, content: "X", rotation: f.angle)))
        out.append(.text(TextGeom(position: anchor + y * (size * 1.08) - x * (h / 2), height: h, content: "Y", rotation: f.angle)))
        if f.isWorld { out.append(.polyline(PolylineGeom(points: [anchor + x * (size * 0.15), anchor + (x + y) * (size * 0.15), anchor + y * (size * 0.15)]))) }
        return out
    }
}

extension Editor {
    /// Locks point input to an axis of the current UCS ("X", "Y") or unlocks it (nil); arrow keys call this (PRC-028).
    /// Locking the axis that is already locked unlocks it, like SketchUp.
    public func lockAxis(_ axis: String?) {
        guard let a = axis?.uppercased() else { settings.axisLock = nil; return }
        let u = UCSFrame.current(doc).angle
        let ang = a == "Y" ? u + .pi / 2 : u
        if let cur = settings.axisLock, abs(normAngle(cur - ang)) < 1e-9 || abs(normAngle(cur - ang) - 2 * .pi) < 1e-9 { settings.axisLock = nil }
        else { settings.axisLock = ang }
    }
}
