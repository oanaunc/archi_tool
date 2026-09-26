// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for project views (DOC-009/010/013/014/015/016/027, BIM-008, VIS-039): PROJECTVIEW, VIEWCROP, SCOPEBOX,
// LINEWORK, MATCHLINE, AXONVIEW and CAMERAVIEW.
import Foundation

enum Round7ViewCommands {
    static var all: [CommandDef] { [projectView, viewCrop, scopeBox, linework, matchline, axonView, cameraView, viewSectionBox] }

    @MainActor static func viewName(_ ed: Editor, _ msg: String) async throws -> ProjectView {
        let def = ed.doc.variable(ProjectViews.currentKey)
        guard let n = try await ed.getWord(msg, defaultValue: def), let v = ed.doc.view(named: n) else { throw CommandError.invalid("View not found.") }
        return v
    }

    static var projectView: CommandDef {
        CommandDef("PROJECTVIEW", aliases: ["PVIEW", "VIEWS", "VIEWBROWSER"], category: "View",
                   summary: "Project views: New (plan / ceiling / 3D), Open, Close, Duplicate (plain, with detailing, as dependent), Split into dependent views, Rename, Delete, List.") { ed in
            let k = try await ed.getKeyword("View option", ["List", "New", "Open", "Close", "Duplicate", "Split", "Rename", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "New":
                let kind = (try await ed.getKeyword("View kind", ["Plan", "Ceiling", "3D"], defaultValue: "Plan") ?? "Plan").lowercased()
                let lvl = ed.doc.level(ed.doc.currentLevel)?.name ?? "Level"
                let def = kind == "3d" ? "3D View \(ed.doc.views.filter { $0.kind == "3d" }.count + 1)" : "\(lvl)\(kind == "ceiling" ? " - Ceiling" : "")"
                guard let n = try await ed.getWord("View name", defaultValue: def), !n.isEmpty else { return }
                if ed.doc.view(named: n) != nil { throw CommandError.invalid("A view named \(n) exists.") }
                ProjectViews.create(n, kind: kind, doc: &ed.doc)
                if kind == "3d", let i = ed.doc.viewIndex(n) { ed.doc.views[i].axonometric = "SW" }
                ProjectViews.open(n, doc: &ed.doc)
                ed.print("View \(n) created and opened.")
            case "Open":
                let v = try await viewName(ed, "View to open")
                ProjectViews.open(v.name, doc: &ed.doc)
                if v.kind == "3d" { ed.host?.perform(.setView("named:" + v.name), editor: ed) }
                else if let c = ProjectViews.effectiveCrop(v, doc: ed.doc) { ed.host?.perform(.zoomWindow(BBox2(points: c).expanded(by: 500 / ed.doc.units.mm)), editor: ed) }
                ed.print("View \(v.name) is current.")
            case "Close":
                ProjectViews.close(doc: &ed.doc)
                ed.print("Project views closed: the model view shows shared annotations only.")
            case "Duplicate":
                let v = try await viewName(ed, "View to duplicate")
                let m = try await ed.getKeyword("Duplicate mode", ["Plain", "Detailing", "Dependent"], defaultValue: "Plain") ?? "Plain"
                let mode: ProjectViews.DuplicateMode = m == "Detailing" ? .withDetailing : (m == "Dependent" ? .dependent : .plain)
                var def = "\(v.name) Copy 1", i = 2
                while ed.doc.view(named: def) != nil { def = "\(v.name) Copy \(i)"; i += 1 }
                guard let n = try await ed.getWord("New view name", defaultValue: def) else { return }
                guard ProjectViews.duplicate(v.name, as: n, mode: mode, doc: &ed.doc) != nil else { throw CommandError.invalid("Cannot duplicate (name taken?).") }
                let copied = ed.doc.entities.filter { $0.props[ProjectViews.ownerProp] == n }.count
                ed.print("View \(n) created\(mode == .withDetailing ? " with \(copied) annotation(s)" : mode == .dependent ? " as a dependent of \(v.parent ?? v.name)" : "").")
            case "Split":
                let v = try await viewName(ed, "View to split into dependent views")
                let c = try await ed.getInteger("Columns", defaultValue: 2) ?? 2
                let r = try await ed.getInteger("Rows", defaultValue: 1) ?? 1
                let o = try await ed.getPositive("Overlap", defaultValue: 1000 / ed.doc.units.mm, allowZero: true)
                let names = ProjectViews.splitDependent(v.name, cols: c, rows: r, overlap: o, doc: &ed.doc)
                guard !names.isEmpty else { throw CommandError.invalid("Nothing to split (need at least two cells and a non-empty view).") }
                ed.print("\(names.count) dependent views: \(names.joined(separator: ", ")). Matchlines: \(ProjectViews.matchlines(ed.doc, family: v.parent ?? v.name).count).")
            case "Rename":
                let v = try await viewName(ed, "View to rename")
                guard let n = try await ed.getWord("New name"), !n.isEmpty, ed.doc.view(named: n) == nil, let i = ed.doc.viewIndex(v.name) else { throw CommandError.invalid("Invalid or duplicate name.") }
                ed.doc.views[i].name = n
                for j in ed.doc.views.indices where ed.doc.views[j].parent == v.name { ed.doc.views[j].parent = n }
                for j in ed.doc.entities.indices where ed.doc.entities[j].props[ProjectViews.ownerProp] == v.name { ed.doc.entities[j].props[ProjectViews.ownerProp] = n }
                if ed.doc.variable(ProjectViews.currentKey) == v.name { ed.doc.setVariable(ProjectViews.currentKey, n) }
                if let k = ed.doc.namedViews.firstIndex(where: { $0.name == v.name }) { ed.doc.namedViews[k].name = n }
                ed.print("Renamed to \(n).")
            case "Delete":
                let v = try await viewName(ed, "View to delete")
                let kids = Set(ed.doc.views.filter { $0.parent == v.name }.map(\.name))
                ed.doc.views.removeAll { $0.name == v.name || kids.contains($0.name) }
                ed.doc.entities.removeAll { $0.props[ProjectViews.ownerProp] == v.name }
                ed.doc.namedViews.removeAll { $0.name == v.name }
                if ed.doc.variable(ProjectViews.currentKey).map({ $0 == v.name || kids.contains($0) }) ?? false { ed.doc.variables[ProjectViews.currentKey] = nil }
                ed.print("View \(v.name) deleted\(kids.isEmpty ? "" : " with \(kids.count) dependent view(s)").")
            default:
                if ed.doc.views.isEmpty { ed.print("No project views. PROJECTVIEW New creates one."); return }
                let cur = ed.doc.variable(ProjectViews.currentKey)
                for v in ed.doc.views {
                    var s = "  \(v.name == cur ? "*" : " ") \(v.name) [\(v.kind)]"
                    if let l = v.level { s += " level \(ed.doc.level(l)?.name ?? "\(l)")" }
                    if let p = v.parent { s += ", dependent of \(p)" }
                    if ProjectViews.effectiveCrop(v, doc: ed.doc) != nil { s += ", cropped" }
                    if let sb = v.scopeBox { s += ", scope box \(sb)" }
                    if !v.linework.isEmpty { s += ", \(v.linework.count) linework override(s)" }
                    if let a = v.axonometric { s += ", axonometric \(a)" }
                    ed.print(s)
                }
            }
        }
    }

    static var viewCrop: CommandDef {
        CommandDef("VIEWCROP", aliases: ["CROPREGION", "CROPVIEW", "ANNOTATIONCROP"], category: "View",
                   summary: "Crop region of the current project view: Window, Polygon, On, Off, Annotation crop offset, Show / Hide the crop boundary.") { ed in
            guard let v = ed.doc.currentView, let i = ed.doc.viewIndex(v.name) else { throw CommandError.invalid("No project view is current (PROJECTVIEW Open).") }
            let k = try await ed.getKeyword("Crop option", ["Window", "Polygon", "On", "Off", "Annotation", "Show", "Hide"], defaultValue: "Window") ?? "Window"
            switch k {
            case "Window":
                let a = try await ed.requirePoint("Specify first corner of the crop region")
                let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                guard ProjectViews.setCrop(v.name, a: a, b: b, doc: &ed.doc) else { throw CommandError.invalid("The crop region needs an area.") }
                ed.print("Crop region set.")
            case "Polygon":
                let a = try await ed.requirePoint("Specify first point of the crop boundary")
                guard let pts = try await ArchitectureCommands.polygonInput(ed, first: a) else { throw CommandError.invalid("A crop boundary needs 3 points.") }
                ed.doc.views[i].crop = ArchitectureCommands.ccw(pts); ed.doc.views[i].cropActive = true
                ed.print("Crop boundary with \(pts.count) points set.")
            case "On":
                guard v.crop != nil else { throw CommandError.invalid("The view has no crop region yet (VIEWCROP Window).") }
                ed.doc.views[i].cropActive = true
            case "Off": ed.doc.views[i].cropActive = false
            case "Annotation":
                let d = try await ed.getDistance("Annotation crop offset beyond the crop region (negative = off)", defaultValue: v.annotationCrop ?? 500 / ed.doc.units.mm).value ?? 0
                ed.doc.views[i].annotationCrop = d < 0 ? nil : d
            case "Show": ed.doc.setVariable("CROPSHOW", "1")
            case "Hide": ed.doc.setVariable("CROPSHOW", "0")
            default: break
            }
        }
    }

    static var scopeBox: CommandDef {
        CommandDef("SCOPEBOX", aliases: ["SCOPEBOXES"], category: "View",
                   summary: "Scope boxes: New (two corners, rotation), Grids (assign grids — they are trimmed to the box), View (crop a project view by the box), Delete, List.") { ed in
            let k = try await ed.getKeyword("Scope box option", ["List", "New", "Grids", "View", "Delete"], defaultValue: "List") ?? "List"
            switch k {
            case "New":
                let def = "Scope Box \(ed.doc.scopeBoxes.count + 1)"
                guard let n = try await ed.getWord("Scope box name", defaultValue: def), !n.isEmpty, ed.doc.scopeBox(named: n) == nil else { throw CommandError.invalid("Invalid or duplicate name.") }
                let a = try await ed.requirePoint("Specify first corner")
                let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                let box = BBox2(points: [a, b])
                guard box.width > 1e-9, box.height > 1e-9 else { throw CommandError.invalid("The box needs an area.") }
                let r = try await ed.getAngle("Rotation", base: box.center, defaultValue: 0).value ?? 0
                ed.doc.scopeBoxes.append(ScopeBox(name: n, center: box.center, width: box.width, depth: box.height, rotation: r))
                ed.print("Scope box \(n) created.")
            case "Grids":
                guard let n = try await ed.getWord("Scope box name", defaultValue: ed.doc.scopeBoxes.first?.name), ed.doc.scopeBox(named: n) != nil else { throw CommandError.invalid("Scope box not found.") }
                var ids = try await ArchitectureCommands.elements(ed, "Select grid lines (Enter = all grids)") { if case .gridLine = $0 { return true }; return false }
                if ids.isEmpty { ids = ed.doc.elements.filter { if case .gridLine = $0.geometry { return true }; return false }.map(\.id) }
                for id in ids { if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["scopeBox"] = n } }
                ProjectViews.updateAll(&ed.doc)
                ed.print("\(ids.count) grid(s) follow scope box \(n).")
            case "View":
                let v = try await viewName(ed, "Project view")
                guard let n = try await ed.getWord("Scope box name (None = remove)", defaultValue: ed.doc.scopeBoxes.first?.name), let i = ed.doc.viewIndex(v.name) else { return }
                if n.lowercased() == "none" { ed.doc.views[i].scopeBox = nil; ed.print("Scope box removed."); return }
                guard ed.doc.scopeBox(named: n) != nil else { throw CommandError.invalid("Scope box not found.") }
                ed.doc.views[i].scopeBox = n
                ed.print("View \(v.name) is cropped by \(n).")
            case "Delete":
                guard let n = try await ed.getWord("Scope box name"), ed.doc.scopeBox(named: n) != nil else { throw CommandError.invalid("Scope box not found.") }
                ed.doc.scopeBoxes.removeAll { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                for i in ed.doc.elements.indices where ed.doc.elements[i].props["scopeBox"]?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.elements[i].props["scopeBox"] = nil }
                for i in ed.doc.views.indices where ed.doc.views[i].scopeBox?.caseInsensitiveCompare(n) == .orderedSame { ed.doc.views[i].scopeBox = nil }
            default:
                if ed.doc.scopeBoxes.isEmpty { ed.print("No scope boxes.") }
                for sb in ed.doc.scopeBoxes {
                    let g = ed.doc.elements.filter { $0.props["scopeBox"] == sb.name }.count
                    ed.print("  \(sb.name): \(fmt(sb.width)) × \(fmt(sb.depth)) at \(sb.center), \(g) grid(s)")
                }
            }
        }
    }

    static var linework: CommandDef {
        CommandDef("LINEWORK", aliases: ["LINEWORKOVERRIDE", "LWO"], category: "View",
                   summary: "Overrides the line style of individual element edges in the current project view (Invisible, Hidden, Thin, Wide, Medium, Color, or Reset).") { ed in
            guard let v = ed.doc.currentView, let vi = ed.doc.viewIndex(ProjectViews.owner(v, doc: ed.doc).name) else { throw CommandError.invalid("No project view is current (PROJECTVIEW Open).") }
            let style = try await ed.getKeyword("Line style", ["Invisible", "Hidden", "Thin", "Medium", "Wide", "Color", "Reset"], defaultValue: ed.doc.variable("LINEWORKSTYLE") ?? "Invisible") ?? "Invisible"
            ed.doc.setVariable("LINEWORKSTYLE", style)
            if style == "Reset" {
                let all = try await ed.getYesNo("Remove every override of this view?", defaultValue: false)
                if all { let n = ed.doc.views[vi].linework.count; ed.doc.views[vi].linework = []; ed.print("\(n) override(s) removed."); return }
            }
            var color: RGBA? = nil
            if style == "Color" { color = RGBA(hex: try await ed.getWord("Color (#RRGGBB)", defaultValue: "#FF0000") ?? "#FF0000") }
            var n = 0
            while let p = try await ed.getPoint("Pick an edge").point {
                guard var o = ProjectViews.pickEdge(ed.doc, at: p, tolerance: ed.pickTolerance) else { ed.print("No element edge there."); continue }
                ed.doc.views[vi].linework.removeAll { $0.element == o.element && $0.a.isClose(o.a, tol: 1e-6) && $0.b.isClose(o.b, tol: 1e-6) }
                if style == "Reset" { n += 1; continue }
                switch style {
                case "Invisible": o.invisible = true
                case "Hidden": o.linetype = "Hidden"
                case "Thin": o.lineweight = 0.13
                case "Medium": o.lineweight = 0.35
                case "Wide": o.lineweight = 0.7
                case "Color": o.color = color
                default: continue
                }
                ed.doc.views[vi].linework.append(o); n += 1
            }
            if n > 0 { ed.print("\(n) edge(s) overridden in \(ed.doc.views[vi].name).") }
        }
    }

    static var matchline: CommandDef {
        CommandDef("MATCHLINE", aliases: ["MATCHLINES"], category: "View", summary: "Matchlines between dependent views: On / Off / List.", modifies: true) { ed in
            let k = try await ed.getKeyword("Matchlines", ["List", "On", "Off"], defaultValue: "List") ?? "List"
            switch k {
            case "On": ed.doc.setVariable("MATCHLINES", "1")
            case "Off": ed.doc.setVariable("MATCHLINES", "0")
            default:
                let parents = Set(ed.doc.views.compactMap(\.parent))
                var n = 0
                for p in parents.sorted() { for m in ProjectViews.matchlines(ed.doc, family: p) { ed.print("  \(p): \(m.from) | \(m.to)  \(m.a) → \(m.b)"); n += 1 } }
                if n == 0 { ed.print("No matchlines (PROJECTVIEW Split creates dependent views).") }
            }
        }
    }

    static var axonView: CommandDef {
        CommandDef("AXONVIEW", aliases: ["AXONVIEWSAVE", "SAVE3DVIEW", "AXONOMETRIC"], category: "View",
                   summary: "Saves a 3D axonometric view (SW / SE / NE / NW isometric, Top, or Custom azimuth/elevation) that refits to the model after every change.") { ed in
            let p = try await ed.getKeyword("Direction", ["SW", "SE", "NE", "NW", "Top", "Custom"], defaultValue: "SW") ?? "SW"
            var preset = p
            if p == "Custom" {
                let az = try await ed.getReal("Azimuth in degrees (from +X, counter-clockwise)", defaultValue: 225).value ?? 225
                let el = try await ed.getReal("Elevation in degrees", defaultValue: 30).value ?? 30
                guard abs(el) <= 90 else { throw CommandError.invalid("Elevation must be within ±90°.") }
                preset = "axo:\(fmt(az)),\(fmt(el))"
            }
            guard let n = try await ed.getWord("View name", defaultValue: "3D \(p)"), !n.isEmpty else { return }
            var v = ed.doc.view(named: n) ?? ProjectView(name: n, kind: "3d")
            guard v.kind == "3d" else { throw CommandError.invalid("\(n) is not a 3D view.") }
            v.axonometric = preset; v.camera = ProjectViews.axonCamera(preset, doc: ed.doc)
            if let i = ed.doc.viewIndex(n) { ed.doc.views[i] = v } else { ed.doc.views.append(v) }
            ProjectViews.updateAll(&ed.doc)
            ed.host?.perform(.setView("named:" + n), editor: ed)
            ed.print("Axonometric view \(n) saved (VIEWDRAW Camera places it as a drawing).")
        }
    }

    static var cameraView: CommandDef {
        CommandDef("CAMERAVIEW", aliases: ["PLACECAMERA", "CAMERAOBJ", "PERSPECTIVEVIEW"], category: "View",
                   summary: "Places a camera object (eye, target, heights, lens) saved as a perspective 3D view; cameras show in plan with their field of view.") { ed in
            let eye = try await ed.requirePoint("Specify camera location")
            let tgt = try await ed.requirePoint("Specify target location", base: eye) { c in [.line(LineGeom(eye, c))] }
            guard eye.distance(to: tgt) > 1e-6 else { throw CommandError.invalid("Camera and target must differ.") }
            let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            let eh = try await ed.getDistance("Eye height", defaultValue: 1600 / ed.doc.units.mm).value ?? 1600
            let th = try await ed.getDistance("Target height", defaultValue: eh).value ?? eh
            let lens = try await ed.getPositive("Lens length in mm (35 mm film)", defaultValue: ed.variableDouble("CAMERALENS", 35))
            ed.doc.setVariable("CAMERALENS", fmt(lens))
            let fov = CameraObjects.fov(lens: lens)
            var k = 1
            while ed.doc.view(named: "Camera \(k)") != nil { k += 1 }
            guard let n = try await ed.getWord("Camera name", defaultValue: "Camera \(k)"), !n.isEmpty else { return }
            let cam = Camera(eye: Vec3(eye.x, eye.y, lz + eh), target: Vec3(tgt.x, tgt.y, lz + th), fov: fov, orthographic: false)
            var v = ProjectView(name: n, kind: "3d", camera: cam)
            v.settings["CAMERALEVEL"] = "\(ed.doc.currentLevel)"
            if let i = ed.doc.viewIndex(n) { ed.doc.views[i] = v } else { ed.doc.views.append(v) }
            ProjectViews.updateAll(&ed.doc)
            ed.print("Camera \(n): lens \(fmt(lens)) mm, field of view \(fmt(fov, 1))°.")
        }
    }
}

/// Camera objects (VIS-039): lens ↔ field of view, and the plan glyph (body, lens and view cone).
public enum CameraObjects {
    /// Horizontal field of view in degrees for a lens on 36 mm wide film.
    public static func fov(lens: Double) -> Double { 2 * atan(18 / max(lens, 1e-3)) * 180 / .pi }
    public static func lens(fov: Double) -> Double { 18 / tan(max(min(fov, 179), 1) * .pi / 360) }

    static func entries(_ doc: ArchiDocument, options: DrawOptions) -> [DrawEntry] {
        guard doc.variable("CAMERAS") != "0", !options.forPaper else { return [] }
        let u = 1 / doc.units.mm
        let col = RGBA(0.2, 0.6, 1.0)
        var items: [DrawItem] = []
        for v in doc.views where v.kind == "3d" && v.axonometric == nil {
            guard let c = v.camera, !c.orthographic else { continue }
            if let l = options.level, let cl = v.settings["CAMERALEVEL"].flatMap(Int.init), cl != l { continue }
            let e = c.eye.xy, t = c.target.xy
            let d = (t - e).normalized
            guard d.length > 0.5 else { continue }
            let s = 300 * u, n = d.perp
            let body = [e - d * s - n * (s * 0.6), e - n * (s * 0.6), e + n * (s * 0.6), e - d * s + n * (s * 0.6)]
            items.append(.stroke(points: body, closed: true, style: StrokeStyle(color: col, lineweight: 0.25)))
            items.append(.stroke(points: [e - n * (s * 0.35), e + d * (s * 0.5) - n * (s * 0.6), e + d * (s * 0.5) + n * (s * 0.6), e + n * (s * 0.35)], closed: true, style: StrokeStyle(color: col, lineweight: 0.25)))
            let half = c.fov * .pi / 360, reach = e.distance(to: t)
            let l = e + d.rotated(by: half) * (reach / cos(half)), r = e + d.rotated(by: -half) * (reach / cos(half))
            items.append(.stroke(points: [l, e, r], closed: false, style: StrokeStyle(color: col, lineweight: 0.13, dash: [100 * u, -60 * u])))
            items.append(.stroke(points: [t - Vec2(80 * u, 0), t + Vec2(80 * u, 0)], closed: false, style: StrokeStyle(color: col, lineweight: 0.18)))
            items.append(.stroke(points: [t - Vec2(0, 80 * u), t + Vec2(0, 80 * u)], closed: false, style: StrokeStyle(color: col, lineweight: 0.18)))
            items.append(.text(TextGeom(position: e - d * (s * 1.4) - n * (s * 0.6), height: 150 * u, content: v.name), font: "Helvetica", color: col))
        }
        return items.isEmpty ? [] : [DrawEntry(id: nil, items: items)]
    }
}

extension Round7ViewCommands {
    /// Section box of the current 3D project view (DOC-017), for scripts: Fit to the selection / a level / the model,
    /// explicit Box corners, On or Off. The 3D viewport shows it (SECTIONBOX) and camera drawings are cut by it.
    static var viewSectionBox: CommandDef {
        CommandDef("VIEWSECTIONBOX", aliases: ["SECTIONBOXVIEW", "CROP3D"], category: "View",
                   summary: "Section box of the current 3D view: Fit (selection, level or model), Box (two corners and heights), On, Off.") { ed in
            let k = try await ed.getKeyword("Section box", ["Fit", "Box", "On", "Off"], defaultValue: "Fit") ?? "Fit"
            switch k {
            case "On", "Off":
                guard let s = ed.doc.variable(SectionBoxes.variable), let semi = s.firstIndex(of: ";") else { throw CommandError.invalid("No section box yet (VIEWSECTIONBOX Fit).") }
                ed.doc.setVariable(SectionBoxes.variable, (k == "On" ? "on" : "off") + s[semi...])
            case "Box":
                let a = try await ed.requirePoint("Specify first corner")
                let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                let z0 = try await ed.getReal("Bottom elevation", defaultValue: 0).value ?? 0
                let z1 = try await ed.getReal("Top elevation", defaultValue: z0 + ed.currentLevelHeight).value ?? z0 + 3000
                let p = BBox2(points: [a, b])
                SectionBoxes.store(BBox3(min: Vec3(p.min.x, p.min.y, min(z0, z1)), max: Vec3(p.max.x, p.max.y, max(z0, z1))), in: &ed.doc)
            default:
                var box = BBox3.empty
                let sel = ed.selection
                if !sel.isEmpty {
                    for id in sel {
                        if let el = ed.doc.element(id) { for g in MeshBuilder.groups(for: el, doc: ed.doc) where !g.mesh.isEmpty { box.add(g.mesh.bounds.min); box.add(g.mesh.bounds.max) } }
                        if let e = ed.doc.entity(id) { for g in MeshBuilder.groups(for: e, doc: ed.doc) where !g.mesh.isEmpty { box.add(g.mesh.bounds.min); box.add(g.mesh.bounds.max) } }
                    }
                } else if (try await ed.getKeyword("Fit to [Level/Model]", ["Level", "Model"], defaultValue: "Level")) == "Level" {
                    let l = ed.doc.level(ed.doc.currentLevel)
                    let b2 = ed.doc.elements.filter { $0.level == ed.doc.currentLevel }.reduce(BBox2.empty) { $0.union(PlanRepresentation.bounds($1, doc: ed.doc)) }
                    if !b2.isEmpty, let l = l { box = BBox3(min: Vec3(b2.min.x, b2.min.y, l.elevation), max: Vec3(b2.max.x, b2.max.y, l.elevation + l.height)) }
                } else { box = ProjectViews.modelBounds(ed.doc) }
                guard !box.isEmpty else { throw CommandError.invalid("Nothing to fit.") }
                let pad = 100 / ed.doc.units.mm
                SectionBoxes.store(BBox3(min: box.min - Vec3(pad, pad, pad), max: box.max + Vec3(pad, pad, pad)), in: &ed.doc)
            }
            if let v = ed.doc.currentView, let i = ed.doc.viewIndex(ProjectViews.owner(v, doc: ed.doc).name) { ed.doc.views[i].settings = ProjectViews.capture(ed.doc) }
            ed.host?.perform(.regen, editor: ed)
        }
    }
}
