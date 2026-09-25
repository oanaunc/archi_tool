// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 2D region Booleans, isometric drafting, multilines, drafting symbols (north arrow, scale bar, break line), conics, nudge.
enum DraftAidCommands {
    static var all: [CommandDef] { booleans + [isoDraft, isoPlane, mline, mlstyle, northArrow, scaleBar, breakLine, parabola, hyperbola, nudge, textReadable, sketch, arcText] }

    // MARK: Region Booleans
    @MainActor static func regionLoops(_ ed: Editor, _ ids: [EntityID]) -> [(EntityID, [[Vec2]])] {
        ids.compactMap { id in ed.doc.entity(id).flatMap { e in PolygonBoolean.loops(of: e.geometry, doc: ed.doc).map { (id, $0) } } }
    }
    @MainActor static func replace(_ ed: Editor, sources: [EntityID], with loops: [[Vec2]]) -> Int {
        guard let first = sources.first.flatMap({ ed.doc.entity($0) }) else { return 0 }
        ed.doc.remove(ids: Set(sources))
        for l in loops {
            var e = first; e.props = [:]
            e.geometry = .polyline(PolylineGeom(points: l, closed: true))
            ed.doc.add(e)
        }
        return loops.count
    }
    static var booleans: [CommandDef] { [
        CommandDef("REGIONUNION", aliases: ["UNION2D", "PUNION"], category: "Modify", summary: "Unites closed 2D regions (closed polylines, circles, ellipses, hatches) into closed polylines.") { ed in
            let r = regionLoops(ed, try await ed.getEntitySelection("Select regions to unite"))
            guard r.count >= 2 else { throw CommandError.invalid("Select at least two closed objects.") }
            let acc = r.dropFirst().reduce(r[0].1) { PolygonBoolean.apply(.union, $0, $1.1) }
            let n = replace(ed, sources: r.map(\.0), with: acc)
            ed.selection = []; ed.print("\(r.count) regions united into \(n) boundary(ies), area \(fmt(PolygonBoolean.area(acc), 4)).")
        },
        CommandDef("REGIONSUBTRACT", aliases: ["SUBTRACT2D", "PSUBTRACT"], category: "Modify", summary: "Subtracts closed 2D regions from others (result as closed polylines; holes become separate polylines).") { ed in
            let a = regionLoops(ed, try await ed.getEntitySelection("Select regions to subtract from"))
            guard !a.isEmpty else { return }
            ed.selection = []
            let b = regionLoops(ed, try await ed.getEntitySelection("Select regions to subtract")).filter { x in !a.contains { $0.0 == x.0 } }
            guard !b.isEmpty else { return }
            let base = a.dropFirst().reduce(a[0].1) { PolygonBoolean.apply(.union, $0, $1.1) }
            let res = b.reduce(base) { PolygonBoolean.apply(.subtract, $0, $1.1) }
            let n = replace(ed, sources: a.map(\.0) + b.map(\.0), with: res)
            ed.selection = []; ed.print("\(n) boundary(ies), area \(fmt(PolygonBoolean.area(res), 4)).")
        },
        CommandDef("REGIONINTERSECT", aliases: ["INTERSECT2D", "PINTERSECT"], category: "Modify", summary: "Keeps the common area of closed 2D regions (as closed polylines).") { ed in
            let r = regionLoops(ed, try await ed.getEntitySelection("Select regions to intersect"))
            guard r.count >= 2 else { throw CommandError.invalid("Select at least two closed objects.") }
            let acc = r.dropFirst().reduce(r[0].1) { PolygonBoolean.apply(.intersect, $0, $1.1) }
            if acc.isEmpty { ed.print("The regions do not overlap; nothing changed."); return }
            let n = replace(ed, sources: r.map(\.0), with: acc)
            ed.selection = []; ed.print("\(n) boundary(ies), area \(fmt(PolygonBoolean.area(acc), 4)).")
        },
    ] }

    // MARK: Isometric drafting
    static var isoDraft: CommandDef {
        CommandDef("ISODRAFT", category: "Settings", summary: "Isometric drafting: Orthographic (off), isoLeft, isoTop, isoRight — ortho and grid snap follow the isometric axes.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["Orthographic", "isoLeft", "isoTop", "isoRight"], defaultValue: ed.settings.isometric ? "Orthographic" : "isoLeft") ?? "Orthographic"
            switch k {
            case "Orthographic": ed.settings.isometric = false
            case "isoTop": ed.settings.isometric = true; ed.settings.isoPlane = 1
            case "isoRight": ed.settings.isometric = true; ed.settings.isoPlane = 2
            default: ed.settings.isometric = true; ed.settings.isoPlane = 0
            }
            ed.print(ed.settings.isometric ? "<Isoplane \(["Left", "Top", "Right"][ed.settings.isoPlane])>" : "<Isometric drafting off>")
        }
    }
    static var isoPlane: CommandDef {
        CommandDef("ISOPLANE", category: "Settings", summary: "Sets the current isometric plane: Left, Top, Right or Toggle to the next.") { ed in
            let k = try await ed.getKeyword("Enter isometric plane setting", ["Left", "Top", "Right", "Toggle"], defaultValue: "Toggle") ?? "Toggle"
            switch k {
            case "Left": ed.settings.isoPlane = 0
            case "Top": ed.settings.isoPlane = 1
            case "Right": ed.settings.isoPlane = 2
            default: ed.settings.isoPlane = (ed.settings.isoPlane + 1) % 3
            }
            ed.print("<Isoplane \(["Left", "Top", "Right"][ed.settings.isoPlane])>")
        }
    }

    // MARK: Multilines
    static var mline: CommandDef {
        CommandDef("MLINE", aliases: ["ML"], category: "Draw", summary: "Draws multiple parallel lines (multiline style, scale, Top/Zero/Bottom justification), grouped.") { ed in
            var style = Multiline.style(ed.doc.variable("CMLSTYLE") ?? "STANDARD", ed.doc) ?? .standard
            var scale = ed.variableDouble("CMLSCALE", 20)
            var just = Multiline.Justification(rawValue: (ed.doc.variable("CMLJUST") ?? "top").lowercased()) ?? .top
            var pts: [Vec2] = []
            ed.print("Current settings: Justification = \(just.rawValue.capitalized), Scale = \(fmt(scale)), Style = \(style.name)")
            var closed = false
            loop: while true {
                let kws = pts.isEmpty ? ["Justification", "Scale", "STyle"] : pts.count >= 3 ? ["Undo", "Close"] : ["Undo"]
                let prev = pts, st = style, sc = scale, j = just
                let a = try await ed.getPoint(pts.isEmpty ? "Specify start point" : "Specify next point", base: pts.last, keywords: kws) { c in
                    Multiline.geometry(prev + [c], style: st, scale: sc, justification: j, closed: false)
                }
                switch a {
                case .point(let p): pts.append(p)
                case .keyword("Justification"):
                    let k = try await ed.getKeyword("Enter justification type", ["Top", "Zero", "Bottom"], defaultValue: just.rawValue.capitalized) ?? "Top"
                    just = Multiline.Justification(rawValue: k.lowercased()) ?? .top; ed.doc.setVariable("CMLJUST", just.rawValue.capitalized)
                case .keyword("Scale"):
                    if let v = try await ed.getReal("Enter mline scale", defaultValue: scale).value, v != 0 { scale = v; ed.doc.setVariable("CMLSCALE", fmt(v)) }
                case .keyword("STyle"):
                    guard let n = try await ed.getWord("Enter mline style name or [?]", defaultValue: style.name) else { continue }
                    if n == "?" { ed.print(Multiline.styles(ed.doc).map(\.name).joined(separator: ", ")); continue }
                    guard let s = Multiline.style(n, ed.doc) else { ed.print("Multiline style \(n) not found."); continue }
                    style = s; ed.doc.setVariable("CMLSTYLE", s.name)
                case .keyword("Undo"): _ = pts.popLast()
                case .keyword("Close"): closed = true; break loop
                default: break loop
                }
            }
            guard pts.count >= 2 else { return }
            let geoms = Multiline.geometry(pts, style: style, scale: scale, justification: just, closed: closed)
            var n = 1
            while ed.doc.entities.contains(where: { $0.props["group"] == "MLINE\(n)" }) { n += 1 }
            for (k, g) in geoms.enumerated() {
                let id = ed.addEntity(g)
                guard let i = ed.doc.entityIndex(id) else { continue }
                ed.doc.entities[i].props["group"] = "MLINE\(n)"
                if k < style.elements.count {
                    let el = style.elements[k]
                    if el.color.lowercased() != "bylayer", let c = ColorRef.parse(el.color) { ed.doc.entities[i].color = c }
                    if el.linetype.lowercased() != "bylayer", ed.doc.linetype(el.linetype) != nil { ed.doc.entities[i].linetype = el.linetype }
                }
            }
        }
    }
    static var mlstyle: CommandDef {
        CommandDef("MLSTYLE", aliases: ["-MLSTYLE"], category: "Draw", summary: "Multiline styles: New (element offsets, caps), Set current, List, Delete.") { ed in
            let k = try await ed.getKeyword("Enter an option", ["?", "New", "Set", "Delete"], defaultValue: "?") ?? "?"
            switch k {
            case "?":
                for s in Multiline.styles(ed.doc) {
                    ed.print("  \(s.name == (ed.doc.variable("CMLSTYLE") ?? "STANDARD") ? "*" : " ")\(s.name): offsets \(s.elements.map { fmt($0.offset) }.joined(separator: ", "))\(s.startCap ? ", start cap" : "")\(s.endCap ? ", end cap" : "")")
                }
            case "New":
                guard let n = try await ed.getWord("Enter new style name"), BlockCommands.validName(n) else { throw CommandError.invalid("Invalid name.") }
                guard let o = try await ed.getWord("Enter element offsets (comma separated, e.g. 0.5,0,-0.5)") else { return }
                let offs = o.split(separator: ",").compactMap { InputParser.parseNumber(String($0).trimmingCharacters(in: .whitespaces)) }
                guard !offs.isEmpty else { throw CommandError.invalid("At least one numeric offset is required.") }
                let caps = try await ed.getKeyword("End caps", ["None", "Start", "End", "Both"], defaultValue: "None") ?? "None"
                Multiline.save(MLStyle(name: n, elements: offs.map { MLStyle.Element(offset: $0) }, startCap: caps == "Start" || caps == "Both", endCap: caps == "End" || caps == "Both"), &ed.doc)
                ed.doc.setVariable("CMLSTYLE", n)
            case "Set":
                guard let n = try await ed.getWord("Enter style name"), let s = Multiline.style(n, ed.doc) else { throw CommandError.invalid("Style not found.") }
                ed.doc.setVariable("CMLSTYLE", s.name)
            case "Delete":
                guard let n = try await ed.getWord("Enter style name"), n.uppercased() != "STANDARD" else { throw CommandError.invalid("STANDARD cannot be deleted.") }
                let rest = Multiline.styles(ed.doc).filter { $0.name.caseInsensitiveCompare(n) != .orderedSame && $0 != .standard }
                VarJSON.save(rest, &ed.doc, Multiline.variable, empty: rest.isEmpty)
            default: return
            }
        }
    }

    // MARK: Symbols
    @MainActor static func group(_ ed: Editor, _ geoms: [Geometry], prefix: String) {
        var n = 1
        while ed.doc.entities.contains(where: { $0.props["group"] == "\(prefix)\(n)" }) { n += 1 }
        for g in geoms { let id = ed.addEntity(g); if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["group"] = "\(prefix)\(n)" } }
    }
    static var northArrow: CommandDef {
        CommandDef("NORTHARROW", aliases: ["NORTH"], category: "Annotate", summary: "Places a north arrow symbol (defaults to project north).") { ed in
            let c = try await ed.requirePoint("Specify location")
            let size = try await ed.getPositive("Specify size", base: c, defaultValue: ed.settings.textHeight * 6)
            let def = .pi / 2 + rad(ed.doc.info.northAngle)
            let a = try await ed.getAngle("Specify north direction", base: c, defaultValue: def).value ?? def
            group(ed, DraftSymbols.northArrow(center: c, size: size, angle: a), prefix: "NORTH")
        }
    }
    static var scaleBar: CommandDef {
        CommandDef("SCALEBAR", category: "Annotate", summary: "Places a graphic scale bar (segments, segment length, labels in m or drawing units).") { ed in
            let o = try await ed.requirePoint("Specify start point")
            let count = try await ed.getInteger("Enter number of segments", defaultValue: 4) ?? 4
            guard count >= 1 && count <= 100 else { throw CommandError.invalid("Requires 1-100 segments.") }
            let seg = try await ed.getPositive("Specify segment length", base: o, defaultValue: 1000)
            let h = try await ed.getPositive("Specify bar height", defaultValue: max(seg / 10, ed.settings.textHeight * 0.6))
            let unit = try await ed.getKeyword("Label units", ["Meters", "Drawing"], defaultValue: ed.doc.units == .millimeters ? "Meters" : "Drawing") ?? "Drawing"
            let factor = unit == "Meters" ? ed.doc.units.mm / 1000 : 1
            group(ed, DraftSymbols.scaleBar(origin: o, segment: seg, count: count, height: h, labelFactor: factor, unitLabel: unit == "Meters" ? "m" : ed.doc.units.abbreviation), prefix: "SCALEBAR")
        }
    }
    static var breakLine: CommandDef {
        CommandDef("BREAKLINE", aliases: ["BREAKLINESYMBOL"], category: "Annotate", summary: "Draws a break line with a zig-zag symbol (size, extension).") { ed in
            let a = try await ed.requirePoint("Specify first point of break line")
            var size = ed.variableDouble("BREAKLINESIZE", ed.settings.textHeight * 2)
            let b = try await ed.requirePoint("Specify second point of break line", base: a) { c in [.polyline(PolylineGeom(points: DraftSymbols.breakLine(a, c, size: size)))] }
            let s = try await ed.getDistance("Specify location of break symbol or [Size]", base: a, keywords: ["Size"])
            var at = 0.5
            switch s {
            case .keyword:
                size = try await ed.getPositive("Break line symbol size", defaultValue: size); ed.doc.setVariable("BREAKLINESIZE", fmt(size))
            case .value(let v): at = v / max(a.distance(to: b), 1e-9)
            case .none: break
            }
            let ext = ed.variableDouble("BREAKLINEEXT", 0)
            ed.addEntity(.polyline(PolylineGeom(points: DraftSymbols.breakLine(a, b, size: size, at: at, extension: ext))))
        }
    }

    // MARK: Conics
    static var parabola: CommandDef {
        CommandDef("PARABOLA", category: "Draw", summary: "Draws a parabola from its vertex, focus and half-width (as a smooth polyline).") { ed in
            let v = try await ed.requirePoint("Specify vertex")
            let f = try await ed.requirePoint("Specify focus", base: v)
            guard v.distance(to: f) > 1e-9 else { throw CommandError.invalid("The focus must differ from the vertex.") }
            let w = try await ed.getPositive("Specify half-width across the axis", base: v, defaultValue: v.distance(to: f) * 4)
            ed.addEntity(.polyline(PolylineGeom(points: DraftSymbols.parabola(vertex: v, focus: f, halfWidth: w))))
        }
    }
    static var hyperbola: CommandDef {
        CommandDef("HYPERBOLA", category: "Draw", summary: "Draws a hyperbola branch from centre, vertex, conjugate semi-axis and half-height (as a smooth polyline).") { ed in
            let c = try await ed.requirePoint("Specify centre")
            let v = try await ed.requirePoint("Specify vertex", base: c)
            guard c.distance(to: v) > 1e-9 else { throw CommandError.invalid("The vertex must differ from the centre.") }
            let b = try await ed.getPositive("Specify conjugate semi-axis (b)", defaultValue: c.distance(to: v))
            let h = try await ed.getPositive("Specify half-height", defaultValue: b * 3)
            let both = try await ed.getYesNo("Draw both branches?", defaultValue: false)
            ed.addEntity(.polyline(PolylineGeom(points: DraftSymbols.hyperbola(center: c, vertex: v, b: b, halfHeight: h))))
            if both { ed.addEntity(.polyline(PolylineGeom(points: DraftSymbols.hyperbola(center: c, vertex: c * 2 - v, b: b, halfHeight: h)))) }
        }
    }

    // MARK: Freehand and arc text
    static var sketch: CommandDef {
        CommandDef("SKETCH", category: "Draw", summary: "Freehand sketch: records the points of a drag (record increment, Type polyline/line/spline) until Enter.") { ed in
            var inc = ed.variableDouble("SKETCHINC", max(ed.pickTolerance, 1e-6))
            var type = ed.doc.variable("SKPOLY") ?? "1"
            var pts: [Vec2] = []
            var strokes: [[Vec2]] = []
            while true {
                let kws = pts.isEmpty ? ["Type", "Increment", "Pen"] : ["Pen"]
                let a = try await ed.getPoint(pts.isEmpty ? "Specify sketch or [Type/Increment/Pen]" : "Specify sketch", keywords: kws) { c in
                    let q = pts + [c]; return q.count >= 2 ? [.polyline(PolylineGeom(points: q))] : []
                }
                switch a {
                case .point(let p): pts.append(p)
                case .keyword("Type"):
                    let k = try await ed.getKeyword("Enter sketch type", ["Line", "Polyline", "Spline"], defaultValue: type == "0" ? "Line" : type == "2" ? "Spline" : "Polyline") ?? "Polyline"
                    type = k == "Line" ? "0" : k == "Spline" ? "2" : "1"; ed.doc.setVariable("SKPOLY", type)
                case .keyword("Increment"):
                    inc = try await ed.getPositive("Specify sketch increment", defaultValue: inc); ed.doc.setVariable("SKETCHINC", fmt(inc))
                case .keyword("Pen"):
                    if pts.count >= 2 { strokes.append(pts) }; pts = []
                default:
                    if pts.count >= 2 { strokes.append(pts) }
                    var n = 0
                    for st in strokes {
                        let f = Sketch.filter(st, increment: inc)
                        guard f.count >= 2 else { continue }
                        switch type {
                        case "0": for i in 0..<(f.count - 1) { ed.addEntity(.line(LineGeom(f[i], f[i + 1]))) }
                        case "2": ed.addEntity(.spline(SplineGeom(degree: 3, controlPoints: [], fitPoints: f)))
                        default: ed.addEntity(.polyline(PolylineGeom(points: f)))
                        }
                        n += 1
                    }
                    ed.print("\(n) sketch stroke(s) recorded.")
                    return
                }
            }
        }
    }
    static var arcText: CommandDef {
        CommandDef("ARCTEXT", category: "Annotate", summary: "Places text along an arc (convex or concave side, height, offset), one character per text object, grouped.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select an arc", filter: { if case .arc? = ed.doc.entity($0)?.geometry { return true }; return false }),
                  case .arc(let arc)? = ed.doc.entity(pk.id)?.geometry else { return }
            let h = try await ed.getPositive("Specify text height", defaultValue: ed.settings.textHeight)
            let side = try await ed.getKeyword("Place text on", ["Convex", "Concave"], defaultValue: "Convex") ?? "Convex"
            let off = try await ed.getDistance("Specify offset from arc", defaultValue: h * 0.25).value ?? h * 0.25
            guard let text = try await ed.getString("Enter text"), !text.isEmpty else { return }
            let ts = ArcText.layout(text, arc: arc, height: h, outside: side == "Convex", offset: off)
            guard !ts.isEmpty else { throw CommandError.invalid("Cannot place the text on this arc.") }
            group(ed, ts.map { .text($0) }, prefix: "ARCTEXT")
        }
    }

    // MARK: Nudge and text reading direction
    static var nudge: CommandDef {
        CommandDef("NUDGE", category: "Modify", summary: "Moves the selection by small steps: Left/Right/Up/Down (× count), or a vector dx,dy (arrow-key nudging).", modifies: false) { ed in
            guard !ed.selection.isEmpty else { throw CommandError.invalid("Select objects first.") }
            let k = try await ed.getWord("Enter direction [Left/Right/Up/Down] or dx,dy", defaultValue: "Right", keywords: ["Left", "Right", "Up", "Down"]) ?? "Right"
            let s = ed.nudgeStep()
            var d: Vec2
            switch k {
            case "Left": d = Vec2(-s, 0)
            case "Right": d = Vec2(s, 0)
            case "Up": d = Vec2(0, s)
            case "Down": d = Vec2(0, -s)
            default:
                let p = k.split(separator: ",").compactMap { InputParser.parseNumber(String($0)) }
                guard p.count == 2 else { throw CommandError.invalid("Requires a direction or dx,dy.") }
                d = Vec2(p[0], p[1])
            }
            ed.print("\(ed.nudgeSelection(by: d)) object(s) nudged.")
        }
    }
    static var textReadable: CommandDef {
        CommandDef("TEXTREADABLE", aliases: ["TEXTFLIP"], category: "Annotate", summary: "Turns upside-down text (rotated between 90° and 270°) by 180° so it reads left-to-right, keeping its position.") { ed in
            let ids = try await ed.getEntitySelection("Select text objects")
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .text(var t) = ed.doc.entities[i].geometry else { continue }
                let r = normAngle(t.rotation)
                guard r > .pi / 2 + 1e-9 && r < 3 * .pi / 2 - 1e-9 else { continue }
                // Keep the visual centre: flip about the text box centre.
                let box = GeometryOps.textBoxCorners(t)
                let c = box.reduce(Vec2.zero, +) / Double(max(box.count, 1))
                t.rotation = normAngle(r - .pi)
                t.position = c * 2 - t.position
                switch t.halign { case .left: t.halign = .right; case .right: t.halign = .left; default: break }
                switch t.valign { case .top: t.valign = .bottom; case .bottom, .baseline: t.valign = .top; default: break }
                ed.doc.entities[i].geometry = .text(t)
                n += 1
            }
            ed.selection = []
            ed.print("\(n) text object(s) made readable.")
        }
    }
}
