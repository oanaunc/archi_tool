// Oanarina Archi Tool — GPL-3.0-or-later
// Natural-language commands (SCR-026): English requests such as "draw a 4 m wall north of grid A", "add a 900 wide door
// in the middle of the last wall", "draw a room 4 by 3 m at 0,0 named Kitchen" or "move the selection 2 m east" are parsed
// by rules (no network, no model download) into edit actions. The command shows what it understood and asks before
// applying; the whole request is one undo step.
import Foundation

public enum NLAction: Equatable {
    case line(Vec2, Vec2)
    case circle(Vec2, Double)
    case rectangle(Vec2, Double, Double)
    case wall(Vec2, Vec2, thickness: Double?, height: Double?)
    case opening(OpeningKind, wall: EntityID?, width: Double?, height: Double?, offset: Double?)
    case room(Vec2, Double, Double, name: String)
    case move(Vec2), copy(Vec2), rotate(Double, Vec2?)
    case erase
    case layer(String)
    case zoomExtents
}

public enum NaturalLanguage {
    public struct Parsed { public var actions: [NLAction]; public var summary: String }
    public struct NLError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    static let directions: [String: Vec2] = ["north": Vec2(0, 1), "south": Vec2(0, -1), "east": Vec2(1, 0), "west": Vec2(-1, 0),
                                             "up": Vec2(0, 1), "down": Vec2(0, -1), "right": Vec2(1, 0), "left": Vec2(-1, 0)]

    /// Tokens: words, numbers with units ("4m", "4 m", "900mm", "3.5 metres", "3'6\""), coordinates "x,y".
    static func tokens(_ s: String) -> [String] {
        var t = s.lowercased()
        for (a, b) in [("millimetres", "mm"), ("millimeters", "mm"), ("centimetres", "cm"), ("centimeters", "cm"), ("metres", "m"), ("meters", "m"), ("metre", "m"), ("meter", "m"),
                       ("degrees", "deg"), ("degree", "deg")] {
            t = t.replacingOccurrences(of: "\\b" + a + "\\b", with: " " + b, options: .regularExpression)
        }
        for (a, b) in [("°", " deg"), ("×", " by "), (" x ", " by ")] { t = t.replacingOccurrences(of: a, with: b) }
        var out: [String] = []
        for raw in t.split(whereSeparator: { " \t\n;".contains($0) }) {
            var w = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            // "4m" → "4", "m"; keep coordinates "1,2" together.
            if let r = w.range(of: #"^-?\d+(\.\d+)?(mm|cm|m|deg)$"#, options: .regularExpression) {
                let unit = w[r].drop { "-0123456789.".contains($0) }
                out.append(String(w.dropLast(unit.count))); out.append(String(unit)); continue
            }
            if w.hasSuffix(",") && !w.dropLast().contains(",") { w = String(w.dropLast()) }
            if !w.isEmpty { out.append(w) }
        }
        // "4 by 3 m": the unit after the second number applies to the first too.
        var i = 0
        while i + 3 < out.count {
            if Double(out[i]) != nil, out[i + 1] == "by", Double(out[i + 2]) != nil, ["m", "cm", "mm"].contains(out[i + 3]) { out.insert(out[i + 3], at: i + 1); i += 4 } else { i += 1 }
        }
        return out
    }

    /// Parses a request against the drawing (for grids, "last wall", units, selection).
    public static func parse(_ text: String, doc: ArchiDocument, selection: Set<EntityID>) throws -> Parsed {
        let t = tokens(text)
        guard !t.isEmpty else { throw NLError(message: "Say what to do, e.g. \"draw a 4 m wall from 0,0 going east\".") }
        let u = doc.units.mm
        let defaultUnitMM: Double = u  // bare numbers are drawing units unless a unit follows
        func has(_ w: String...) -> Bool { w.contains { t.contains($0) } }
        func number(_ i: Int) -> Double? { i < t.count ? Double(t[i]) : nil }
        /// Length at token i with an optional unit after it → drawing units.
        func length(at i: Int) -> Double? {
            guard let v = number(i) else { return nil }
            let unit = i + 1 < t.count ? t[i + 1] : ""
            switch unit { case "m": return v * 1000 / u; case "cm": return v * 10 / u; case "mm": return v / u; default: return v * defaultUnitMM / u }
        }
        func point(after words: [String]) -> Vec2? {
            for (i, w) in t.enumerated() where words.contains(w) && i + 1 < t.count {
                if let p = coord(t[i + 1]) { return p }
            }
            return nil
        }
        func coord(_ s: String) -> Vec2? {
            let parts = s.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? Vec2(parts[0], parts[1]) : nil
        }
        func allLengths() -> [(Int, Double)] { t.indices.compactMap { i in (coord(t[i]) == nil ? length(at: i) : nil).map { (i, $0) } } }
        func direction() -> Vec2? { t.compactMap { directions[$0] }.first }
        func named() -> String? {
            if let i = t.firstIndex(where: { $0 == "named" || $0 == "called" }), i + 1 < t.count {
                // Original casing from the text.
                let words = text.split(separator: " ")
                if let j = words.firstIndex(where: { ["named", "called"].contains($0.lowercased()) }), j + 1 < words.count {
                    return words[(j + 1)...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".!?\"'"))
                }
                return t[i + 1].capitalized
            }
            return nil
        }
        func lastWall() -> EntityID? {
            if let s = selection.first(where: { doc.element($0)?.typeName == "wall" }) { return s }
            return doc.elements.last { $0.typeName == "wall" }?.id
        }
        func wallRef() -> EntityID? {
            if let i = t.firstIndex(of: "wall"), i + 1 < t.count, let n = Int(t[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: "#"))), doc.element(n)?.typeName == "wall" { return n }
            for w in t where w.hasPrefix("#") { if let n = Int(w.dropFirst()), doc.element(n)?.typeName == "wall" { return n } }
            return lastWall()
        }
        let verbs = Set(t.prefix(3))

        // Selection edits.
        if has("delete", "erase", "remove") {
            guard !selection.isEmpty else { throw NLError(message: "Select the objects to delete first.") }
            return Parsed(actions: [.erase], summary: "Delete \(selection.count) selected object(s)")
        }
        if has("zoom") { return Parsed(actions: [.zoomExtents], summary: "Zoom to the drawing extents") }
        if (has("layer")) && has("set", "use", "make", "switch", "change") && !has("draw", "add") {
            let words = text.split(separator: " ").map(String.init)
            guard let i = words.lastIndex(where: { $0.lowercased() == "layer" || $0.lowercased() == "to" }), i + 1 < words.count else { throw NLError(message: "Which layer?") }
            let name = words[i + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".!?\"'"))
            return Parsed(actions: [.layer(name)], summary: "Make layer \(name) current")
        }
        if verbs.contains("move") || verbs.contains("copy") {
            guard !selection.isEmpty else { throw NLError(message: "Select the objects to \(verbs.contains("move") ? "move" : "copy") first.") }
            guard let (_, d) = allLengths().first, let dir = direction() else { throw NLError(message: "Say how far and which way, e.g. \"move the selection 2 m east\".") }
            let v = dir * d
            return Parsed(actions: [verbs.contains("move") ? .move(v) : .copy(v)], summary: "\(verbs.contains("move") ? "Move" : "Copy") \(selection.count) object(s) by (\(fmt(v.x)), \(fmt(v.y)))")
        }
        if verbs.contains("rotate") {
            guard !selection.isEmpty else { throw NLError(message: "Select the objects to rotate first.") }
            guard let i = t.firstIndex(where: { Double($0) != nil }), let a = Double(t[i]) else { throw NLError(message: "Say the angle, e.g. \"rotate the selection 90 degrees\".") }
            let sign: Double = has("clockwise", "cw") && !has("counterclockwise", "anticlockwise", "ccw") ? -1 : 1
            return Parsed(actions: [.rotate(sign * a * .pi / 180, point(after: ["about", "around"]))], summary: "Rotate \(selection.count) object(s) by \(fmt(sign * a))°")
        }

        // Openings.
        for (word, kind) in [("door", OpeningKind.door), ("window", .window), ("opening", .opening)] where t.contains(word) && has("add", "insert", "put", "place", "create", "draw") {
            guard let w = wallRef(), case .wall(let wg) = doc.element(w)?.geometry else { throw NLError(message: "There is no wall to put the \(word) in.") }
            var width: Double?, height: Double?, offset: Double?
            for (i, v) in allLengths() {
                let next = t[min(i + 1, t.count)...].prefix(3)
                if next.contains("wide") || next.contains("width") { width = v }
                else if next.contains("high") || next.contains("tall") || next.contains("height") { height = v }
                else if (i > 0 && ["at", "offset"].contains(t[i - 1])) || next.contains("from") { offset = v }
                else if width == nil { width = v }
            }
            if has("middle", "centre", "center") { offset = wg.length / 2 }
            return Parsed(actions: [.opening(kind, wall: w, width: width, height: height, offset: offset)],
                          summary: "Add a \(word)" + (width.map { " \(fmt($0)) wide" } ?? "") + " in wall #\(w)" + (offset.map { " at \(fmt($0)) from its start" } ?? " in the middle"))
        }

        guard has("draw", "add", "create", "make", "place", "put", "build") else {
            throw NLError(message: "Not understood. Try: draw a line/circle/rectangle/wall/room …, add a door/window …, move/copy/rotate/delete the selection, zoom extents, set layer X.")
        }
        let lengths = allLengths()
        let start = point(after: ["from", "at", "centered", "centred", "starting", "origin"]) ?? .zero
        let end = point(after: ["to"])

        if t.contains("wall") || t.contains("walls") {
            var thickness: Double?, height: Double?, length: Double?
            for (i, v) in lengths {
                let next = t[(i + 1)...].prefix(3)
                if next.contains("thick") || next.contains("thickness") { thickness = v }
                else if next.contains("high") || next.contains("tall") || next.contains("height") { height = v }
                else if length == nil { length = v }
            }
            // "north of grid A": along the grid, on its north side (or along a north-south grid, going north).
            if let gi = t.firstIndex(of: "grid"), gi + 1 < t.count {
                let label = t[gi + 1].uppercased()
                guard let g = doc.elements.first(where: { if case .gridLine(let gl) = $0.geometry { return gl.label.uppercased() == label }; return false }),
                      case .gridLine(let gl) = g.geometry else { throw NLError(message: "There is no grid \(label).") }
                let side = direction() ?? Vec2(0, 1)
                let th = thickness ?? 200 / u
                let L = length ?? gl.start.distance(to: gl.end)
                let sideName = t.first { directions[$0] != nil } ?? "north"
                var dirv = (gl.end - gl.start).normalized, a0 = gl.start
                // Walls along a grid run west → east / south → north.
                if dirv.x < -1e-9 || (abs(dirv.x) <= 1e-9 && dirv.y < 0) { dirv = dirv * -1; a0 = gl.end }
                if abs(dirv.dot(side)) < 0.5 {
                    // Grid across the side: the wall runs along the grid with its face on the grid line.
                    let a = a0 + side * (th / 2)
                    return Parsed(actions: [.wall(a, a + dirv * L, thickness: thickness, height: height)], summary: "Wall \(fmt(L)) long along grid \(label), on its \(sideName) side")
                }
                let a = side.dot(gl.end - gl.start) >= 0 ? gl.start : gl.end
                return Parsed(actions: [.wall(a, a + side * L, thickness: thickness, height: height)], summary: "Wall \(fmt(L)) long on grid \(label), going \(sideName)")
            }
            let a = start
            let b: Vec2
            if let e = end { b = e }
            else if let L = length { b = a + (direction() ?? Vec2(1, 0)) * L }
            else { throw NLError(message: "Give the wall's length or end point, e.g. \"draw a 4 m wall from 0,0 going north\".") }
            return Parsed(actions: [.wall(a, b, thickness: thickness, height: height)], summary: "Wall from (\(fmt(a.x)), \(fmt(a.y))) to (\(fmt(b.x)), \(fmt(b.y)))" + (thickness.map { ", \(fmt($0)) thick" } ?? ""))
        }
        if has("room", "space") {
            let dims = lengths.map(\.1)
            guard dims.count >= 2 else { throw NLError(message: "Give the room size, e.g. \"draw a room 4 by 3 m at 0,0 named Kitchen\".") }
            // "4 by 3 m": the unit after the second number applies to both.
            let w = dims[0], h = dims[1]
            let name = named() ?? "Room"
            return Parsed(actions: [.room(start, w, h, name: name)], summary: "Room \(name) \(fmt(w)) × \(fmt(h)) at (\(fmt(start.x)), \(fmt(start.y)))")
        }
        if has("circle") {
            var r = lengths.first?.1
            if has("diameter"), let d = r { r = d / 2 }
            guard let radius = r, radius > 0 else { throw NLError(message: "Give the radius, e.g. \"draw a circle radius 500 at 0,0\".") }
            return Parsed(actions: [.circle(start, radius)], summary: "Circle radius \(fmt(radius)) at (\(fmt(start.x)), \(fmt(start.y)))")
        }
        if has("rectangle", "rect", "box", "square") {
            let dims = lengths.map(\.1)
            guard let w = dims.first else { throw NLError(message: "Give the size, e.g. \"draw a rectangle 2 by 1 m at 0,0\".") }
            let h = dims.count > 1 ? dims[1] : w
            let ww = w
            return Parsed(actions: [.rectangle(start, ww, h)], summary: "Rectangle \(fmt(ww)) × \(fmt(h)) at (\(fmt(start.x)), \(fmt(start.y)))")
        }
        if has("line") {
            if let e = end { return Parsed(actions: [.line(start, e)], summary: "Line from (\(fmt(start.x)), \(fmt(start.y))) to (\(fmt(e.x)), \(fmt(e.y)))") }
            guard let L = lengths.first?.1 else { throw NLError(message: "Give the line's length or end point.") }
            let e = start + (direction() ?? Vec2(1, 0)) * L
            return Parsed(actions: [.line(start, e)], summary: "Line \(fmt(L)) long to (\(fmt(e.x)), \(fmt(e.y)))")
        }
        throw NLError(message: "Not understood: say what to draw (line, circle, rectangle, wall, room) or add (door, window).")
    }

    /// Applies parsed actions to the editor's document. Returns created ids.
    @MainActor @discardableResult
    public static func apply(_ p: Parsed, editor ed: Editor) throws -> [EntityID] {
        var d = ed.doc
        var created: [EntityID] = []
        let u = d.units.mm
        let sel = ed.selection
        for a in p.actions {
            switch a {
            case .line(let x, let y): created.append(d.add(.line(LineGeom(x, y)), layer: d.currentLayer))
            case .circle(let c, let r): created.append(d.add(.circle(CircleGeom(c, r)), layer: d.currentLayer))
            case .rectangle(let o, let w, let h):
                created.append(d.add(.polyline(PolylineGeom(points: [o, o + Vec2(w, 0), o + Vec2(w, h), o + Vec2(0, h)], closed: true)), layer: d.currentLayer))
            case .wall(let x, let y, let th, let h):
                guard x.distance(to: y) > geomEpsilon else { throw NLError(message: "The wall would have no length.") }
                created.append(d.addElement(.wall(WallGeom(start: x, end: y, thickness: th ?? 200 / u, height: h ?? (d.level(d.currentLevel)?.height ?? 3000 / u)))))
            case .opening(let kind, let wid, let w0, let h0, let off0):
                guard let wid, case .wall(let w) = d.element(wid)?.geometry else { throw NLError(message: "No host wall.") }
                let width = w0 ?? (kind == .window ? 1200 / u : 900 / u)
                let height = h0 ?? (kind == .window ? 1200 / u : 2100 / u)
                let off = off0 ?? w.length / 2
                guard width < w.length, off - width / 2 >= -1e-9, off + width / 2 <= w.length + 1e-9 else { throw NLError(message: "The \(kind.rawValue) (\(fmt(width)) wide at \(fmt(off))) does not fit in wall #\(wid) (\(fmt(w.length)) long).") }
                created.append(d.addElement(.opening(OpeningGeom(kind: kind, hostWall: wid, offset: off, width: width, height: height, sill: kind == .window ? 900 / u : 0)), level: d.element(wid)?.level))
            case .room(let o, let w, let h, let name):
                created.append(d.addElement(.space(SpaceGeom(boundary: [o, o + Vec2(w, 0), o + Vec2(w, h), o + Vec2(0, h)], name: name)), name: name))
            case .move(let v), .copy(let v):
                let t = Transform2D.translation(v)
                if case .copy = a {
                    for id in sel.sorted() {
                        if let e = d.entity(id) { var c = e; c.geometry = GeometryOps.transform(e.geometry, t); created.append(d.add(c)) }
                        else if let el = d.element(id), el.typeName != "door", el.typeName != "window", el.typeName != "opening" {
                            var c = el; c.geometry = CommandHelpers.transform(el.geometry, t)
                            let nid = d.allocateID(); c.id = nid; d.elements.append(c); created.append(nid)
                        }
                    }
                } else {
                    for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, t) }
                    for i in d.elements.indices where sel.contains(d.elements[i].id) { d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, t) }
                }
            case .rotate(let ang, let about):
                var b = BBox2.empty
                for id in sel { if let e = d.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: d)) } else if let el = d.element(id) { b.add(PlanRepresentation.bounds(el, doc: d)) } }
                let t = Transform2D.rotation(ang, around: about ?? (b.isEmpty ? .zero : b.center))
                for i in d.entities.indices where sel.contains(d.entities[i].id) { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, t) }
                for i in d.elements.indices where sel.contains(d.elements[i].id) { d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, t) }
            case .erase: d.remove(ids: sel)
            case .layer(let n): d.ensureLayer(n); d.currentLayer = d.layer(named: n)?.name ?? n
            case .zoomExtents: ed.host?.perform(.zoomExtents, editor: ed)
            }
        }
        ed.doc = d
        if !created.isEmpty { ed.selection = Set(created) }
        return created
    }

    static var command: CommandDef {
        CommandDef("ASK", aliases: ["NLCOMMAND", "SAY", "NATURAL"], category: "Scripting",
                   summary: "Natural-language request, e.g. \"draw a 4 m wall north of grid A\", \"add a door 900 wide in the middle of the last wall\", \"move the selection 2 m east\": shows what was understood and asks before applying (one undo step).") { ed in
            guard let text = try await ed.getString("What should I do?"), !text.isEmpty else { return }
            let p: Parsed
            do { p = try parse(text, doc: ed.doc, selection: ed.selection) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            ed.print("Understood: \(p.summary).")
            guard try await ed.getYesNo("Apply?", defaultValue: true) else { ed.print("Nothing changed."); return }
            do { try apply(p, editor: ed) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }
}
