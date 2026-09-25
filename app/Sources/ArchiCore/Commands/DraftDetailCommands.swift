// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Detail drafting: jogged dimensions, gradients, hatch origin, revision stamps, text masks/frames, FLATTEN, CHSPACE,
/// spline editing and blending, TRACE, ROTATE90, TXTEXP, ordinate re-base, instance selection, dynamic block parameters,
/// script DELAY/RESUME.
enum DraftDetailCommands {
    static var all: [CommandDef] {
        [dimJogged, dimJogLine, gradient, hatchOrigin, revStamp, textMask, textUnmask, textFrame, flatten, chspace,
         splinedit, blend, trace, rotate90, txtexp, ordinateRebase, selectInstances, bparameter, dynProp, resetBlock,
         delay, resume, macro] + more
    }

    @MainActor static func geometry(_ ed: Editor, _ id: EntityID) -> Geometry? { ed.doc.entity(id)?.geometry }

    // MARK: - DIMJOGGED / DIMJOGLINE

    static var dimJogged: CommandDef {
        CommandDef("DIMJOGGED", aliases: ["DJO", "JOG"], category: "Annotate", summary: "Creates a jogged radius dimension for large arcs and circles (overridden centre, jog).") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select arc or circle", filter: { id in
                switch ed.doc.entity(id)?.geometry { case .arc?, .circle?: return true; default: return false }
            }), let g = geometry(ed, pk.id) else { return }
            let c: Vec2, r: Double
            switch g { case .arc(let a): (c, r) = (a.center, a.radius); case .circle(let k): (c, r) = (k.center, k.radius); default: return }
            let style = ed.doc.dimStyle(ed.doc.currentDimStyle)
            let co = try await ed.requirePoint("Specify center location override")
            @MainActor func make(_ loc: Vec2, _ jog: Vec2) -> DimensionGeom {
                let w = (loc - c).lengthSquared > 1e-18 ? (loc - c).normalized : Vec2(1, 0)
                let d = DimensionGeom(kind: .radius, points: [c, c + w * r, loc], style: ed.doc.currentDimStyle)
                return DimensionRenderer.withJogs(d, [co, jog], style: style)
            }
            let loc = try await ed.requirePoint("Specify dimension line location", base: co) { p in [.dimension(make(p, (co + p) / 2))] }
            let jog = try await ed.getPoint("Specify jog location", base: loc) { p in [.dimension(make(loc, p))] }.point ?? (co + loc) / 2
            ed.addDimension(make(loc, jog))
        }
    }

    static var dimJogLine: CommandDef {
        CommandDef("DIMJOGLINE", aliases: ["DJL"], category: "Annotate", summary: "Adds or removes a jog line on a linear or aligned dimension (the value is not to scale).") { ed in
            let a = try await ed.pickObject("Select dimension to add jog or [Remove]", keywords: ["Remove"]) { id in
                if case .dimension(let d)? = ed.doc.entity(id)?.geometry { return d.kind == .linear || d.kind == .aligned }; return false
            }
            switch a {
            case .keyword:
                guard case .pick(let pk) = try await ed.pickObject("Select jog to remove", filter: { if case .dimension(let d)? = ed.doc.entity($0)?.geometry { return !DimensionRenderer.jogs(d).isEmpty }; return false }),
                      let i = ed.doc.entityIndex(pk.id), case .dimension(let d) = ed.doc.entities[i].geometry else { return }
                ed.doc.entities[i].geometry = .dimension(DimensionRenderer.withJogs(d, [], style: ed.doc.dimStyle(d.style)))
                ed.print("Jog removed.")
            case .pick(let pk):
                guard let i = ed.doc.entityIndex(pk.id), case .dimension(let d) = ed.doc.entities[i].geometry else { return }
                let style = ed.doc.dimStyle(d.style)
                let prim = DimensionRenderer.primitives(DimensionRenderer.withoutBreaks(d), style: style)
                let mid = prim.text.map { t in t.position } ?? DimensionRenderer.definitionPoints(d).reduce(Vec2.zero, +) / Double(max(1, DimensionRenderer.definitionPoints(d).count))
                let j = try await ed.getPoint("Specify jog location (or press ENTER)", preview: { p in [.dimension(DimensionRenderer.withJogs(d, [p], style: style))] }).point
                // Default: halfway between the text and the first extension line, on the dimension line.
                let p1 = DimensionRenderer.definitionPoints(d).first ?? mid
                ed.doc.entities[i].geometry = .dimension(DimensionRenderer.withJogs(d, [j ?? (mid + p1) / 2], style: style))
            default: return
            }
        }
    }

    // MARK: - GRADIENT / hatch origin

    static var gradient: CommandDef {
        CommandDef("GRADIENT", aliases: ["GD"], category: "Draw", summary: "Fills an enclosed area or selected objects with a gradient fill (linear, cylinder, spherical, curved; one or two colours).") { ed in
            var type = ed.doc.variable("GFNAME") ?? "LINEAR"
            var colors = ed.doc.variable("GFCOLORS") ?? "5,2"
            var angle = ed.variableDouble("GFANG", 0)
            var centered = ed.doc.variable("GFSHIFT") != "1"
            @MainActor func make(_ loops: [[PolyVertex]]) {
                let first = colors.split(separator: ",").first.map(String.init).flatMap(ColorRef.parse)
                let id = ed.addEntity(.hatch(HatchGeom(loops: loops, pattern: "SOLID", fill: first)))
                guard let i = ed.doc.entityIndex(id) else { return }
                ed.doc.entities[i].props[DraftRendering.gradientProp] = type
                ed.doc.entities[i].props[DraftRendering.gradientColorsProp] = colors
                ed.doc.entities[i].props[DraftRendering.gradientAngleProp] = fmt(angle)
                if !centered { ed.doc.entities[i].props[DraftRendering.gradientCenteredProp] = "0" }
            }
            while true {
                let a = try await ed.getPoint("Pick internal point", keywords: ["Select", "Type", "Colors", "Angle", "Centered"])
                switch a {
                case .point(let p):
                    guard let region = RegionFinder.region(at: p, curves: DrawCommands.hatchCurves(ed), doc: ed.doc) else { ed.print("Valid hatch boundary not found."); continue }
                    make([region.outer] + region.holes)
                    ed.print("Gradient created: area = \(CommandHelpers.areaText(region.area, units: ed.doc.units)).")
                case .keyword("Select"):
                    let ids = try await ed.getEntitySelection("Select objects")
                    var loops = ids.compactMap { ed.doc.entity($0).flatMap { CommandHelpers.closedLoop($0.geometry) } }
                    if loops.isEmpty { loops = Modify.join(ids.compactMap { ed.doc.entity($0)?.geometry }).compactMap { CommandHelpers.closedLoop($0) } }
                    guard !loops.isEmpty else { ed.print("No closed boundary in the selection."); continue }
                    loops.sort { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) > abs(GeometryOps.signedArea(CommandHelpers.loopPoints($1))) }
                    make(loops); ed.selection = []
                case .keyword("Type"):
                    let t = try await ed.getKeyword("Enter gradient type", ["LINEAR", "CYLINDER", "INVCYLINDER", "SPHERICAL", "INVSPHERICAL", "HEMISPHERICAL", "INVHEMISPHERICAL", "CURVED", "INVCURVED"], defaultValue: type) ?? type
                    type = t.uppercased(); ed.doc.setVariable("GFNAME", type)
                case .keyword("Colors"):
                    guard let c = try await ed.getWord("Enter one or two colors (e.g. 5,2 or #203040,#F5C518)", defaultValue: colors) else { continue }
                    let parts = c.split(separator: ",").map(String.init)
                    guard (1...2).contains(parts.count), parts.allSatisfy({ ColorRef.parse($0) != nil }) else { ed.print("Invalid colors."); continue }
                    colors = c; ed.doc.setVariable("GFCOLORS", c)
                case .keyword("Angle"):
                    angle = deg(try await ed.getAngle("Specify gradient angle", defaultValue: rad(angle)).value ?? rad(angle)); ed.doc.setVariable("GFANG", fmt(angle))
                case .keyword("Centered"):
                    centered = try await ed.getYesNo("Centered gradient?", defaultValue: centered); ed.doc.setVariable("GFSHIFT", centered ? "0" : "1")
                default: return
                }
            }
        }
    }

    static var hatchOrigin: CommandDef {
        CommandDef("HATCHSETORIGIN", aliases: ["HATCHORIGIN"], category: "Modify", summary: "Sets the pattern origin of hatches: a point, a corner or the centre of the hatch extents, or the default (0,0).") { ed in
            let ids = try await ed.getEntitySelection("Select hatch objects").filter { if case .hatch? = ed.doc.entity($0)?.geometry { return true }; return false }
            ed.selection = []
            guard !ids.isEmpty else { throw CommandError.invalid("No hatches selected.") }
            let a = try await ed.getPoint("Specify new origin point or [BottomLeft/BottomRight/TopLeft/TopRight/Center/Default]",
                                          keywords: ["BottomLeft", "BottomRight", "TopLeft", "TopRight", "Center", "Default"])
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .hatch(let h) = ed.doc.entities[i].geometry else { continue }
                let b = BBox2(points: h.loops.flatMap { $0.map(\.p) })
                let o: Vec2?
                switch a {
                case .point(let p): o = p
                case .keyword("BottomLeft"): o = b.min
                case .keyword("BottomRight"): o = Vec2(b.max.x, b.min.y)
                case .keyword("TopLeft"): o = Vec2(b.min.x, b.max.y)
                case .keyword("TopRight"): o = b.max
                case .keyword("Center"): o = b.center
                case .keyword("Default"): o = nil
                default: return
                }
                ed.doc.entities[i].props[DraftRendering.hatchOriginProp] = o.map(DraftProps.text)
            }
            ed.print("Origin set for \(ids.count) hatch(es).")
        }
    }

    // MARK: - Revision stamps

    static var revStamp: CommandDef {
        CommandDef("REVSTAMP", aliases: ["REVTRIANGLE", "REVTAG", "REVISION"], category: "Annotate", summary: "Revision stamps: a numbered revision triangle, or a new row in the revision table; advances the drawing revision (REVNUMBER).") { ed in
            let cur = ed.doc.variable("REVNUMBER")
            let k = try await ed.getKeyword("Enter an option", ["Triangle", "Table", "Set"], defaultValue: "Triangle") ?? "Triangle"
            @MainActor func setRevision(_ r: String) {
                ed.doc.setVariable("REVNUMBER", r)
                if let n = ed.doc.variable("CTAB"), let li = ed.doc.layouts.firstIndex(where: { $0.name == n }) { ed.doc.layouts[li].titleBlock["revision"] = r }
            }
            switch k {
            case "Set":
                guard let r = try await ed.getWord("Enter current revision", defaultValue: cur ?? "0") else { return }
                setRevision(r)
            case "Table":
                let next = RevisionSymbols.next(after: cur)
                let rev = try await ed.getWord("Enter revision", defaultValue: next) ?? next
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                let date = try await ed.getWord("Enter date", defaultValue: df.string(from: Date())) ?? ""
                let by = try await ed.getWord("Enter initials", defaultValue: ed.doc.info.author.isEmpty ? "-" : ed.doc.info.author) ?? ""
                let desc = try await ed.getString("Enter description", defaultValue: "") ?? ""
                let row = [rev, date, by, desc]
                if let i = ed.doc.entities.firstIndex(where: { $0.props["revisionTable"] == "1" }), case .table(var t) = ed.doc.entities[i].geometry {
                    t.cells.append(row); ed.doc.entities[i].geometry = .table(t)
                } else {
                    let p = try await ed.requirePoint("Specify insertion point of the revision table")
                    let id = ed.addEntity(.table(RevisionSymbols.table(origin: p, textHeight: ed.settings.textHeight, rows: [row])), layer: ed.annotationLayer("TEXTLAYER"))
                    if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["revisionTable"] = "1" }
                }
                setRevision(rev)
                ed.print("Revision \(rev) recorded.")
            default:
                let label = try await ed.getWord("Enter revision label", defaultValue: cur ?? RevisionSymbols.next(after: nil)) ?? "1"
                let size = try await ed.getPositive("Specify triangle size", defaultValue: ed.settings.textHeight * 3)
                while let p = try await ed.getPoint("Specify location of revision triangle", preview: { c in RevisionSymbols.triangle(center: c, size: size, label: label) }).point {
                    DraftAidCommands.group(ed, RevisionSymbols.triangle(center: p, size: size, label: label), prefix: "REV")
                }
                if cur == nil { setRevision(label) }
            }
        }
    }

    // MARK: - Text masks and frames

    @MainActor static func textSelection(_ ed: Editor) async throws -> [EntityID] {
        let ids = try await ed.getEntitySelection("Select text objects").filter { if case .text? = ed.doc.entity($0)?.geometry { return true }; return false }
        ed.selection = []
        guard !ids.isEmpty else { throw CommandError.invalid("No text selected.") }
        return ids
    }

    static var textMask: CommandDef {
        CommandDef("TEXTMASK", aliases: ["BACKGROUNDMASK", "TMASK"], category: "Annotate", summary: "Hides objects behind text with a background mask (offset factor, background or a colour).") { ed in
            let ids = try await textSelection(ed)
            let f = try await ed.getReal("Enter border offset factor (1 = tight)", defaultValue: ed.variableDouble("TEXTMASKOFFSET", 1.5)).value ?? 1.5
            guard f >= 1, f <= 5 else { throw CommandError.invalid("The offset factor must be between 1 and 5.") }
            let c = try await ed.getWord("Enter mask color [Background] or a color", defaultValue: "Background") ?? "Background"
            let isBackground = ["background", "b", "bg"].contains(c.lowercased())
            guard isBackground || ColorRef.parse(c) != nil else { throw CommandError.invalid("Invalid color.") }
            ed.doc.setVariable("TEXTMASKOFFSET", fmt(f))
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                ed.doc.entities[i].props[DraftRendering.textMaskProp] = fmt(f)
                ed.doc.entities[i].props[DraftRendering.maskColorProp] = isBackground ? nil : c
            }
            ed.print("\(ids.count) text object(s) masked.")
        }
    }

    static var textUnmask: CommandDef {
        CommandDef("TEXTUNMASK", aliases: ["TUNMASK"], category: "Annotate", summary: "Removes background masks from text.") { ed in
            let ids = try await textSelection(ed)
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DraftRendering.textMaskProp] = nil; ed.doc.entities[i].props[DraftRendering.maskColorProp] = nil } }
            ed.print("\(ids.count) text object(s) unmasked.")
        }
    }

    static var textFrame: CommandDef {
        CommandDef("TEXTFRAME", aliases: ["TFRAME", "TEXTBORDER"], category: "Annotate", summary: "Draws or removes a frame around text.") { ed in
            let ids = try await textSelection(ed)
            let on = try await ed.getKeyword("Frame", ["ON", "OFF"], defaultValue: "ON") ?? "ON"
            for id in ids { if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props[DraftRendering.textFrameProp] = on == "ON" ? "1" : nil } }
        }
    }

    // MARK: - FLATTEN / CHSPACE

    static var flatten: CommandDef {
        CommandDef("FLATTEN", category: "Modify", summary: "Converts objects to flat 2D geometry at elevation 0 (3D solids become their plan outlines).") { ed in
            let ids = try await ed.getEntitySelection("Select objects to convert")
            ed.selection = []
            guard !ids.isEmpty else { return }
            let n = Flatten.apply(Set(ids), &ed.doc)
            ed.print("\(n) object(s) flattened.")
        }
    }

    static var chspace: CommandDef {
        CommandDef("CHSPACE", aliases: ["CHANGESPACE"], category: "Modify", summary: "Moves objects between model space and a layout's paper space through a viewport, keeping their size on the sheet.") { ed in
            guard !ed.doc.layouts.isEmpty else { throw CommandError.invalid("The drawing has no layouts.") }
            let li = FileViewCommands.currentLayoutIndex(ed) ?? 0
            guard !ed.doc.layouts[li].viewports.isEmpty else { throw CommandError.invalid("Layout \(ed.doc.layouts[li].name) has no viewports.") }
            let k = try await ed.getKeyword("Move objects to [Paper/Model]", ["Paper", "Model"], defaultValue: "Paper") ?? "Paper"
            if k == "Model" {
                let list = ed.doc.layouts[li].entities.map(\.id)
                guard !list.isEmpty else { throw CommandError.invalid("The layout has no paper-space objects.") }
                let w = try await ed.getWord("Enter paper-space object IDs (#1,#2…) or [All]", defaultValue: "All", keywords: ["All"]) ?? "All"
                let ids = w == "All" ? Set(list) : Set(w.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: " #"))) })
                let vi = (try await ed.getInteger("Viewport number", defaultValue: 1) ?? 1) - 1
                let n = ChangeSpace.paperToModel(ids, layout: li, viewport: vi, &ed.doc)
                ed.print("\(n) object(s) moved to model space.")
                return
            }
            let ids = try await ed.getEntitySelection("Select objects")
            ed.selection = []
            guard !ids.isEmpty else { return }
            let box = ed.selectionBounds(ids)
            let vi = ChangeSpace.viewport(for: box, in: ed.doc.layouts[li]) ?? 0
            let n = ChangeSpace.modelToPaper(Set(ids), layout: li, viewport: vi, &ed.doc)
            ed.print("\(n) object(s) moved to paper space of \(ed.doc.layouts[li].name) (viewport \(vi + 1)).")
        }
    }

    // MARK: - SPLINEDIT / BLEND

    static var splinedit: CommandDef {
        CommandDef("SPLINEDIT", aliases: ["SPE"], category: "Modify", summary: "Edits splines: Close/Open, Fit data (Add/Delete/Move), control vertices, Convert to CV form or Polyline, Reverse, Undo.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select spline", filter: { if case .spline? = ed.doc.entity($0)?.geometry { return true }; return false }) else { return }
            let id = pk.id
            var undo: [ArchiDocument] = []
            @MainActor func spline() -> SplineGeom? { if case .spline(let s)? = ed.doc.entity(id)?.geometry { return s }; return nil }
            @MainActor func set(_ s: SplineGeom) { undo.append(ed.doc); if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].geometry = .spline(s) } }
            while let s = spline() {
                let k = try await ed.getKeyword("Enter an option", [s.closed ? "Open" : "Close", "Fit", "Edit", "Cv", "Polyline", "Reverse", "Undo", "eXit"], defaultValue: "eXit") ?? "eXit"
                switch k {
                case "Close", "Open": var x = s; x.closed = k == "Close"; set(x)
                case "Reverse": if case .spline(let r) = Modify.reverse(.spline(s)) { set(r) }
                case "Cv":
                    guard let c = SplineTools.controlForm(s) else { ed.print("The spline already uses control vertices."); continue }
                    set(c); ed.print("Converted to \(c.controlPoints.count) control vertices.")
                case "Polyline":
                    let pts = GeometryOps.splinePoints(s, samplesPerSpan: Int(ed.variableDouble("PLINECONVERTSEGS", 16)))
                    undo.append(ed.doc)
                    ed.replaceEntity(id, with: [.polyline(PolylineGeom(points: s.closed && pts.count > 2 && pts.first!.isClose(pts.last!, tol: 1e-9) ? Array(pts.dropLast()) : pts, closed: s.closed))])
                    return
                case "Fit", "Edit":
                    let isCV = s.controlPoints.count >= 2
                    if k == "Fit" && isCV { ed.print("The spline has no fit data; use Edit vertex."); continue }
                    if k == "Edit" && !isCV { ed.print("The spline is defined by fit points; use Fit data or Cv."); continue }
                    while let cur = spline() {
                        let o = try await ed.getKeyword("Enter a \(k == "Fit" ? "fit data" : "vertex editing") option", ["Add", "Delete", "Move", "eXit"], defaultValue: "eXit") ?? "eXit"
                        switch o {
                        case "Add":
                            guard let p = try await ed.getPoint("Specify point to add").point else { continue }
                            set(SplineTools.addPoint(cur, p))
                        case "Delete":
                            guard let p = try await ed.getPoint("Specify point to delete").point, let i = SplineTools.nearestPoint(cur, p),
                                  let n = SplineTools.deletePoint(cur, at: i) else { ed.print("Cannot delete: a spline needs at least two points."); continue }
                            set(n)
                        case "Move":
                            guard let p = try await ed.getPoint("Specify point to move").point, let i = SplineTools.nearestPoint(cur, p) else { continue }
                            let from = SplineTools.editPoints(cur)[i]
                            guard let q = try await ed.getPoint("Specify new location", base: from, preview: { c in SplineTools.movePoint(cur, at: i, to: c).map { [.spline($0)] } ?? [] }).point,
                                  let n = SplineTools.movePoint(cur, at: i, to: q) else { continue }
                            set(n)
                        default: break
                        }
                        if o == "eXit" { break }
                    }
                case "Undo": if let d = undo.popLast() { ed.doc = d }
                default: return
                }
            }
        }
    }

    static var blend: CommandDef {
        CommandDef("BLEND", aliases: ["BLENDCURVES", "BL"], category: "Draw", summary: "Creates a tangent (or smooth) spline joining the ends of two open curves.") { ed in
            var smooth = ed.doc.variable("BLENDCONTINUITY") == "Smooth"
            @MainActor func isCurve(_ id: EntityID) -> Bool {
                switch ed.doc.entity(id)?.geometry { case .line?, .arc?, .spline?: return true; case .polyline(let p)?: return !p.closed; default: return false }
            }
            var first: Editor.Pick? = nil
            while first == nil {
                switch try await ed.pickObject("Select first object or [CONtinuity]", keywords: ["CONtinuity"], filter: isCurve) {
                case .pick(let p): first = p
                case .keyword:
                    let c = try await ed.getKeyword("Enter continuity", ["Tangent", "Smooth"], defaultValue: smooth ? "Smooth" : "Tangent") ?? "Tangent"
                    smooth = c == "Smooth"; ed.doc.setVariable("BLENDCONTINUITY", c)
                default: return
                }
            }
            guard let a = first, case .pick(let b) = try await ed.pickObject("Select second object", filter: { isCurve($0) && $0 != a.id }),
                  let ga = geometry(ed, a.id), let gb = geometry(ed, b.id) else { return }
            let sa = SplineTools.nearestEndIsStart(ga, to: a.point, doc: ed.doc), sb = SplineTools.nearestEndIsStart(gb, to: b.point, doc: ed.doc)
            guard let ea = SplineTools.endTangent(ga, atStart: sa, doc: ed.doc), let eb = SplineTools.endTangent(gb, atStart: sb, doc: ed.doc) else {
                throw CommandError.invalid("Cannot find the curve ends.")
            }
            guard ea.point.distance(to: eb.point) > 1e-9 else { throw CommandError.invalid("The ends already meet.") }
            ed.addEntity(.spline(SplineTools.blend(ea.point, ea.dir, eb.point, eb.dir, smooth: smooth)))
        }
    }

    // MARK: - TRACE / ROTATE90 / TXTEXP

    static var trace: CommandDef {
        CommandDef("TRACE", category: "Draw", summary: "Draws solid lines of a given width (a wide polyline).") { ed in
            let w = try await ed.getPositive("Specify trace width", defaultValue: ed.variableDouble("TRACEWID", 50))
            ed.doc.setVariable("TRACEWID", fmt(w))
            var pts = [try await ed.requirePoint("Specify start point")]
            while let p = try await ed.getPoint("Specify next point", base: pts.last, preview: { c in [.polyline(PolylineGeom((pts + [c]).map { PolyVertex($0) }, width: w))] }).point {
                if !p.isClose(pts.last!, tol: 1e-9) { pts.append(p) }
            }
            guard pts.count >= 2 else { return }
            ed.addEntity(.polyline(PolylineGeom(pts.map { PolyVertex($0) }, closed: false, width: w)))
        }
    }

    static var rotate90: CommandDef {
        CommandDef("ROTATE90", aliases: ["R90", "ROT90"], category: "Modify", summary: "Rotates the selection 90° counter-clockwise (or [Clockwise]) about its centre or a base point.") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            let c = ed.selectionBounds(ids).center
            let a = try await ed.getPoint("Specify base point or [Clockwise] <centre>", keywords: ["Clockwise"])
            var base = c, ang = Double.pi / 2
            switch a {
            case .point(let p): base = p
            case .keyword: ang = -.pi / 2
            default: break
            }
            ed.transformObjects(ids, .rotation(ang, around: base), copy: false)
            ed.selection = []
        }
    }

    static var txtexp: CommandDef {
        CommandDef("TXTEXP", aliases: ["TEXTEXPLODE", "EXPLODETEXT"], category: "Modify", summary: "Explodes text into single-letter text objects.") { ed in
            let ids = try await textSelection(ed)
            var n = 0
            for id in ids {
                guard case .text(let t)? = ed.doc.entity(id)?.geometry else { continue }
                let letters = TextExplode.letters(t)
                guard !letters.isEmpty else { continue }
                ed.replaceEntity(id, with: letters.map { .text($0) })
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["field"] = nil }
                n += letters.count
            }
            ed.print("\(n) letter(s) created.")
        }
    }

    // MARK: - Ordinate re-base, instance selection

    static var ordinateRebase: CommandDef {
        CommandDef("DIMREBASE", aliases: ["ORDINATEREBASE", "ORDREBASE"], category: "Annotate", summary: "Changes the datum (origin) of ordinate dimensions.") { ed in
            let ids = try await ed.getEntitySelection("Select ordinate dimensions").filter { if case .dimension(let d)? = ed.doc.entity($0)?.geometry { return d.kind == .ordinate }; return false }
            ed.selection = []
            guard !ids.isEmpty else { throw CommandError.invalid("No ordinate dimensions selected.") }
            let o = try await ed.requirePoint("Specify new datum point")
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .dimension(var d) = ed.doc.entities[i].geometry else { continue }
                let n = DimensionRenderer.definitionCount(d.kind)
                while d.points.count < n { d.points.append(.zero) }
                d.points[2] = o
                ed.doc.entities[i].geometry = .dimension(d)
            }
            ed.print("\(ids.count) ordinate dimension(s) re-based.")
        }
    }

    /// Key identifying "the same kind of instance": block for references, type for openings/walls, name for other elements.
    static func instanceKey(_ id: EntityID, doc: ArchiDocument) -> String? {
        if let e = doc.entity(id) {
            if case .insert(let ins) = e.geometry {
                return "insert:" + (e.props[DynamicBlocks.baseProp] ?? e.props["visBase"] ?? ins.block).lowercased()
            }
            return nil
        }
        guard let el = doc.element(id) else { return nil }
        switch el.geometry {
        case .opening(let o): return "opening:\(o.kind):" + (o.typeName ?? "\(fmt(o.width))x\(fmt(o.height))").lowercased()
        case .wall(let w): return "wall:" + (w.wallType ?? fmt(w.thickness)).lowercased()
        default: return "\(el.typeName):" + (el.props["type"] ?? el.name).lowercased()
        }
    }

    static var selectInstances: CommandDef {
        CommandDef("SELECTINSTANCES", aliases: ["SELINST", "SELECTALLINSTANCES"], category: "Select", summary: "Selects every instance of the same block, opening type, wall type or element type as the picked object.", modifies: false) { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select an instance", filter: { instanceKey($0, doc: ed.doc) != nil }),
                  let key = instanceKey(pk.id, doc: ed.doc) else { return }
            let all = (ed.doc.entities.map(\.id) + ed.doc.elements.map(\.id)).filter { ed.isSelectable($0) && instanceKey($0, doc: ed.doc) == key }
            ed.selection = Set(all)
            ed.previousSelection = Set(all)
            ed.print("\(all.count) instance(s) selected.")
        }
    }

    // MARK: - Dynamic blocks

    static var bparameter: CommandDef {
        CommandDef("BPARAMETER", aliases: ["BPARAM", "DYNPARAM"], category: "Blocks", summary: "Adds dynamic parameters to a block: Stretch (a length that stretches the objects in a frame) or Array (a count repeating objects); List, Delete.") { ed in
            guard let name = try await ed.getWord("Enter block name"), let b = ed.doc.blocks[name] else { throw CommandError.invalid("Block not found.") }
            var ps = DynamicBlocks.params(name, ed.doc)
            let k = try await ed.getKeyword("Enter parameter type", ["Stretch", "Array", "List", "Delete"], defaultValue: "Stretch") ?? "Stretch"
            switch k {
            case "List":
                if ps.isEmpty { ed.print("Block \(name) has no dynamic parameters.") }
                for p in ps { ed.print("  \(p.name): \(p.kind.rawValue), base \(fmt(p.base))") }
                return
            case "Delete":
                guard let n = try await ed.getWord("Enter parameter name") else { return }
                ps.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
            default:
                guard let n = try await ed.getWord("Enter parameter name", defaultValue: k == "Stretch" ? "Distance" : "Count"), !n.contains("="), !n.contains(";"), !n.contains("|") else { throw CommandError.invalid("Invalid name.") }
                ed.print("Points are in block coordinates (base point \(b.basePoint)).")
                let c1 = try await ed.requirePoint(k == "Stretch" ? "Specify first corner of the stretch frame" : "Specify first corner around the objects to repeat")
                let c2 = try await ed.requirePoint("Specify opposite corner", base: c1)
                let win = BBox2(points: [c1, c2])
                if k == "Stretch" {
                    let s = try await ed.requirePoint("Specify parameter start point")
                    let e = try await ed.requirePoint("Specify parameter end point", base: s)
                    guard s.distance(to: e) > 1e-9 else { throw CommandError.invalid("The parameter needs a length.") }
                    ps.removeAll { $0.name == n }
                    ps.append(.init(name: n, kind: .stretch, window: win, vector: (e - s).normalized, base: s.distance(to: e)))
                } else {
                    let s = try await ed.requirePoint("Specify spacing base point")
                    let e = try await ed.requirePoint("Specify spacing second point", base: s)
                    guard s.distance(to: e) > 1e-9 else { throw CommandError.invalid("The spacing must not be zero.") }
                    ps.removeAll { $0.name == n }
                    ps.append(.init(name: n, kind: .array, window: win, vector: e - s, base: 1))
                }
            }
            DynamicBlocks.setParams(name, ps, &ed.doc)
            DynamicBlocks.regenerate(name, &ed.doc)
            ed.print("Block \(name): \(ps.count) dynamic parameter(s).")
        }
    }

    static var dynProp: CommandDef {
        CommandDef("DYNPROP", aliases: ["BDYNSET", "DYNVALUE"], category: "Blocks", summary: "Sets dynamic parameter values of block references (stretch lengths, array counts).") { ed in
            let ids = try await ed.getEntitySelection("Select block references").filter { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }
            ed.selection = []
            guard let first = ids.first, let e = ed.doc.entity(first), case .insert(let ins) = e.geometry else { throw CommandError.invalid("No block references selected.") }
            let block = e.props[DynamicBlocks.baseProp] ?? ins.block
            let ps = DynamicBlocks.params(block, ed.doc)
            guard !ps.isEmpty else { throw CommandError.invalid("Block \(block) has no dynamic parameters.") }
            var vals = DynamicBlocks.values(e.props)
            for p in ps {
                let cur = vals[p.name] ?? p.base
                guard let v = try await ed.getReal("Enter \(p.name) (\(p.kind == .array ? "count" : "length"))", defaultValue: cur).value else { continue }
                if p.kind == .array && (v < 1 || v > 1000) { throw CommandError.invalid("The count must be between 1 and 1000.") }
                if p.kind == .stretch && v <= 0 { throw CommandError.invalid("The length must be positive.") }
                vals[p.name] = p.kind == .array ? v.rounded() : v
            }
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .insert(let x) = ed.doc.entities[i].geometry, (ed.doc.entities[i].props[DynamicBlocks.baseProp] ?? x.block) == block else { continue }
                _ = DynamicBlocks.apply(vals, toInsert: i, &ed.doc)
            }
        }
    }

    static var resetBlock: CommandDef {
        CommandDef("RESETBLOCK", aliases: ["BRESET"], category: "Blocks", summary: "Resets block references to their block definition (dynamic values and visibility state).") { ed in
            let ids = try await ed.getEntitySelection("Select block references").filter { if case .insert? = ed.doc.entity($0)?.geometry { return true }; return false }
            ed.selection = []
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                if ed.doc.entities[i].props[DynamicBlocks.baseProp] != nil { _ = DynamicBlocks.apply(nil, toInsert: i, &ed.doc); n += 1 }
                if ed.doc.entities[i].props["visBase"] != nil { BlockVisibility.apply(nil, toInsert: i, &ed.doc); n += 1 }
            }
            ed.print("\(ids.count) block reference(s) reset\(n == 0 ? " (nothing to change)" : "").")
        }
    }

    // MARK: - Scripts: DELAY, RESUME, MACRO

    static var delay: CommandDef {
        CommandDef("DELAY", category: "Tools", summary: "Pauses a script for the given number of milliseconds (up to 32767).", modifies: false) { ed in
            guard let ms = try await ed.getInteger("Enter delay time (in milliseconds)", defaultValue: 0), ms >= 0 else { throw CommandError.invalid("Requires a non-negative integer.") }
            let t = min(ms, 32767)
            if t > 0 { try? await Task.sleep(nanoseconds: UInt64(t) * 1_000_000) }
        }
    }

    static var resume: CommandDef {
        CommandDef("RESUME", category: "Tools", summary: "Continues a script that was interrupted with Escape.", modifies: false) { ed in
            guard let rest = ed.pendingScript, !rest.isEmpty else { ed.print("No interrupted script."); return }
            ed.pendingScript = nil
            ed.print("Resuming script: \(rest.count) line(s).")
            Task { @MainActor in
                var n = 0
                while !ed.isIdle && n < 100000 { await Task.yield(); n += 1 }
                await ed.runScriptLines(rest)
            }
        }
    }

    static var macro: CommandDef {
        CommandDef("MACRO", aliases: ["RUNMACRO"], category: "Tools", summary: "Runs a menu macro: spaces or ; = Enter, \\ = pause for your input, ^C^C = cancel first (e.g. ^C^CLINE \\ @1000,0 ;).", modifies: false) { ed in
            guard let m = try await ed.getString("Enter macro"), !m.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            Task { @MainActor in
                var n = 0
                while !ed.isIdle && n < 100000 { await Task.yield(); n += 1 }
                ed.runMacro(m)
            }
        }
    }
}

// MARK: - More detail commands

extension DraftDetailCommands {
    static var more: [CommandDef] { [patLoad, ellipseQuad, selectPrevious, deselect, spotCoord, objectScale] }

    static var patLoad: CommandDef {
        CommandDef("PATLOAD", aliases: ["HATCHPATLOAD", "LOADPAT"], category: "Draw", summary: "Loads hatch patterns from an AutoCAD .pat file into the drawing (saved with it).") { ed in
            guard let path = try await ed.getWord("Enter .pat file path") else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else { throw CommandError.invalid("Cannot read \(url.path).") }
            let pats = HatchPatterns.parsePat(text)
            guard !pats.isEmpty else { throw CommandError.invalid("No hatch patterns found in \(url.lastPathComponent).") }
            var n = 0
            for p in pats where HatchPatterns.register(name: p.name, definition: p.text) {
                ed.doc.setVariable("HPPAT:" + p.name, p.text); n += 1
            }
            ed.print("\(n) pattern(s) loaded: " + pats.map(\.name).joined(separator: ", "))
        }
    }

    static var ellipseQuad: CommandDef {
        CommandDef("ELLIPSEQUAD", aliases: ["ELQ", "ELLIPSEPARALLELOGRAM", "ISOCIRCLE"], category: "Draw", summary: "Draws the ellipse inscribed in a parallelogram (e.g. an isometric circle): three corners, or a 4-sided closed polyline.") { ed in
            let a = try await ed.getPoint("Specify first corner or [Object]", keywords: ["Object"])
            var q: [Vec2]
            switch a {
            case .keyword:
                guard case .pick(let pk) = try await ed.pickObject("Select a closed 4-sided polyline"), case .polyline(let p)? = ed.doc.entity(pk.id)?.geometry,
                      p.vertices.count == 4 else { throw CommandError.invalid("Select a closed polyline with four vertices.") }
                q = p.vertices.map(\.p)
            case .point(let p0):
                let p1 = try await ed.requirePoint("Specify second corner (adjacent)", base: p0)
                let p3 = try await ed.requirePoint("Specify third corner (adjacent to the first)", base: p0) { c in
                    InscribedEllipse.inParallelogram(p0, p1, p1 + (c - p0), c).map { [.ellipse($0), .polyline(PolylineGeom(points: [p0, p1, p1 + (c - p0), c], closed: true))] } ?? [] }
                q = [p0, p1, p1 + (p3 - p0), p3]
            default: return
            }
            guard let e = InscribedEllipse.inParallelogram(q[0], q[1], q[2], q[3]) else { throw CommandError.invalid("The four corners must form a parallelogram.") }
            ed.addEntity(.ellipse(e))
        }
    }

    static var selectPrevious: CommandDef {
        CommandDef("SELECTPREVIOUS", aliases: ["SELPREV", "PSELECT"], category: "Select", summary: "Selects the previous selection set again (only objects still selectable).", modifies: false) { ed in
            let ids = ed.previousSelection.filter { ed.isSelectable($0) }
            ed.selection = ids
            ed.print("\(ids.count) object(s) selected.")
        }
    }

    static var deselect: CommandDef {
        CommandDef("DESELECT", aliases: ["SELECTNONE", "DESELECTALL"], category: "Select", summary: "Clears the selection (keeps it as the previous selection).", modifies: false) { ed in
            if !ed.selection.isEmpty { ed.previousSelection = ed.selection }
            ed.selection = []
        }
    }

    static var spotCoord: CommandDef {
        CommandDef("SPOTCOORD", aliases: ["SPOTCOORDINATE", "COORDLABEL"], category: "Annotate", summary: "Labels the coordinates (N/E) of a point with a leader that updates when it is moved.") { ed in
            let p = try await ed.requirePoint("Select point to label")
            let q = try await ed.requirePoint("Specify leader landing location", base: p) { c in [.line(LineGeom(p, c))] }
            let dec = Int(ed.variableDouble("SPOTCOORDDEC", 0))
            let h = ed.variableDouble("DIMTXT", ed.settings.textHeight * 0.8)
            let id = ed.addEntity(.leader(LeaderGeom(points: [p, q], text: "", textHeight: h)), layer: ed.annotationLayer("DIMLAYER"))
            guard let i = ed.doc.entityIndex(id) else { return }
            ed.doc.entities[i].props["field"] = "N %<Northing(\(id)):\(dec)>%\nE %<Easting(\(id)):\(dec)>%"
            ed.doc.entities[i].props["spotCoordinate"] = "1"
            var d = ed.doc; Fields.updateAll(&d, ids: [id]); ed.doc = d
            if case .leader(let l)? = ed.doc.entity(id)?.geometry { ed.print(l.text.replacingOccurrences(of: "\n", with: "  ")) }
        }
    }
}

extension DraftDetailCommands {
    static var objectScale: CommandDef {
        CommandDef("OBJECTSCALE", aliases: ["-OBJECTSCALE", "AISCALEADD"], category: "Annotate", summary: "Adds or deletes annotation scales of annotative objects (shown only at their scales when ANNOALLVISIBLE is 0).") { ed in
            let ids = try await ed.getEntitySelection("Select annotative objects")
            ed.selection = []
            guard !ids.isEmpty else { return }
            while let k = try await ed.getKeyword("Enter an option", ["Add", "Delete", "List", "?"], defaultValue: nil) {
                switch k {
                case "List", "?":
                    for id in ids { ed.print("#\(id): " + (ed.doc.entity(id)?.props[DraftRendering.annoScalesProp] ?? "(all scales)")) }
                default:
                    guard let w = try await ed.getWord("Enter scale (e.g. 1:50) or [Current]", defaultValue: ed.doc.variable("CANNOSCALE") ?? "1:1", keywords: ["Current"]) else { continue }
                    let sc = w == "Current" ? (ed.doc.variable("CANNOSCALE") ?? "1:1") : w
                    guard let f = Annotative.factor(sc) else { ed.print("Invalid scale."); continue }
                    for id in ids {
                        guard let i = ed.doc.entityIndex(id) else { continue }
                        var list = (ed.doc.entities[i].props[DraftRendering.annoScalesProp] ?? "").split(separator: ";").map(String.init)
                        list.removeAll { Annotative.factor($0).map { abs($0 - f) < 1e-9 * max(1, f) } ?? true }
                        if k == "Add" { list.append(sc) }
                        list.sort { (Annotative.factor($0) ?? 0) < (Annotative.factor($1) ?? 0) }
                        ed.doc.entities[i].props[DraftRendering.annoScalesProp] = list.isEmpty ? nil : list.joined(separator: ";")
                        if ed.doc.entities[i].props["annotative"] == nil { _ = Annotative.makeAnnotative(&ed.doc.entities[i], doc: ed.doc) }
                    }
                }
            }
        }
    }
}
