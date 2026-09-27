// Oanarina Archi Tool — GPL-3.0-or-later
// archi-engine methods behind the Windows 2D canvas: the parts of the Mac PlanCanvasView (ArchiApp/CanvasView.swift) and
// SheetCanvasNSView (SheetView.swift) that read or edit the drawing — view state (UCS, twist, isometric, dynamic UCS),
// object snap tracking and dynamic-input fields at the cursor, grip hover menus / previews / modes / typed values,
// lasso, selection cycling and wall chains, double-click editing, temporary dimensions, door / window flip arrows,
// arrow-key nudging, tool-palette click-to-place and drag-and-drop (blocks, components, commands, materials, files),
// and sheet viewports (lock, clip, move, scale, remove). Every edit is one undo step with the Mac label.
// See docs/ENGINE-PROTOCOL.md, "Canvas".
import Foundation

/// Protocol methods of the 2D canvas (listed in engine.hello "methods").
public enum EngineCanvasMethods {
    public static let all: [String] = [
        "canvas.state", "canvas.view", "canvas.doubleClick",
        "grips.actions", "grips.preview", "grips.edit", "grips.typed",
        "select.lasso", "select.modify", "select.chain", "select.nudge", "pick.candidates",
        "text.edit", "tempdims.get", "tempdims.set", "flips.get", "flips.apply",
        "palette.items", "place.preview", "place.drop", "file.drop",
        "sheet.viewports", "sheet.viewport",
    ]
}

/// Canvas state the engine keeps per session (the shell's plan view, a maximised sheet viewport).
@MainActor
final class EngineCanvasState {
    var viewCenter: Vec2?
    var viewScale: Double?
    var visible: BBox2?
    var maximized: (layout: Int, viewport: Int)?
    /// Right-drag marking menu on (RADIALMENU; the shell sends its stored preference with canvas.view).
    var radialMenu = true
    weak var owner: Editor?
    static var sessions: [ObjectIdentifier: EngineCanvasState] = [:]
    static func of(_ ed: Editor) -> EngineCanvasState {
        let k = ObjectIdentifier(ed)
        if let s = sessions[k], s.owner === ed { return s }
        sessions = sessions.filter { $0.value.owner != nil }
        let s = EngineCanvasState()
        s.owner = ed
        sessions[k] = s
        return s
    }
}

/// Drag-and-drop / palette payload prefixes (ArchiApp ToolPalette.swift ToolDrop), shared with the Windows shell.
public enum EngineToolDrop {
    public static let blockPrefix = "archi-block:"
    public static let componentPrefix = "archi-component:"
    public static let commandPrefix = "archi-command:"
    public static let materialPrefix = "archi-material:"
    public static let libraryBlockPrefix = "archi-libblock:"
    public static func accepts(_ s: String) -> Bool {
        [blockPrefix, componentPrefix, commandPrefix, materialPrefix, libraryBlockPrefix].contains { s.hasPrefix($0) }
    }
    static func angle(_ turns: Int) -> Double { Double(((turns % 4) + 4) % 4) * .pi / 2 }
}

/// Walls joined end to end (ArchiApp AppNavigation.swift WallChain, SEL-022): Tab over a wall selects the chain.
enum EngineWallChain {
    static func ids(from start: EntityID, doc: ArchiDocument, tolerance: Double = 1) -> [EntityID] {
        guard let first = doc.element(start), case .wall = first.geometry else { return [] }
        var walls: [(EntityID, WallGeom)] = []
        for el in doc.elements where el.level == first.level {
            if case .wall(let w) = el.geometry { walls.append((el.id, w)) }
        }
        var seen: Set<EntityID> = [start]
        var queue = [start]
        while let id = queue.popLast() {
            guard let w = walls.first(where: { $0.0 == id })?.1 else { continue }
            for (oid, ow) in walls where !seen.contains(oid) && touches(w, ow, tolerance) {
                seen.insert(oid)
                queue.append(oid)
            }
        }
        return seen.sorted()
    }
    static func touches(_ a: WallGeom, _ b: WallGeom, _ tol: Double) -> Bool {
        for p in [a.start, a.end] {
            for q in [b.start, b.end] where p.distance(to: q) <= tol { return true }
            if onSegment(p, b.start, b.end, tol) { return true }
        }
        for q in [b.start, b.end] where onSegment(q, a.start, a.end, tol) { return true }
        return false
    }
    static func onSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ tol: Double) -> Bool {
        let ab = b - a
        let l2 = ab.lengthSquared
        guard l2 > 1e-18 else { return p.distance(to: a) <= tol }
        let t = (p - a).dot(ab) / l2
        guard t >= -1e-9, t <= 1 + 1e-9 else { return false }
        return p.distance(to: a + ab * t) <= tol
    }
}

/// Door / window / wall flip arrows (ArchiApp AppNavigation.swift FlipControls, SEL-036).
enum EngineFlips {
    struct Control { var id: EntityID; var kind: String; var point: Vec2; var direction: Vec2 }

    static func controls(_ el: BIMElement, doc: ArchiDocument, gap: Double) -> [Control] {
        guard case .opening(let o) = el.geometry, let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { return [] }
        let dir = w.direction
        guard dir != .zero else { return [] }
        let c = w.centerStart + dir * o.offset
        let side: Double = o.flipFacing ? -1 : 1
        let n = dir.perp * side
        let facing = Control(id: el.id, kind: "facing", point: c + n * (w.thickness / 2 + gap), direction: n)
        guard o.kind == .door else { return [facing] }
        let h: Double = o.flipHand ? -1 : 1
        let along = dir * (h * (o.width / 2 + gap))
        let hand = Control(id: el.id, kind: "hand", point: c + along - n * (w.thickness / 2 + gap), direction: dir * h)
        return [facing, hand]
    }
    static func wallControl(_ el: BIMElement, gap: Double) -> Control? {
        guard case .wall(let w) = el.geometry, w.direction != .zero else { return nil }
        let mid = (w.centerStart + w.centerEnd) / 2
        let n = w.direction.perp
        return Control(id: el.id, kind: "wall", point: mid + n * (w.thickness / 2 + gap), direction: n)
    }
    static func flipWall(_ id: EntityID, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.elementIndex(id), case .wall(var w) = doc.elements[i].geometry else { return false }
        let len = w.start.distance(to: w.end)
        swap(&w.start, &w.end)
        w.bulge = -w.bulge
        doc.elements[i].geometry = .wall(w)
        for j in doc.elements.indices {
            guard case .opening(var o) = doc.elements[j].geometry, o.hostWall == id else { continue }
            o.offset = len - o.offset
            o.flipFacing.toggle()
            o.flipHand.toggle()
            doc.elements[j].geometry = .opening(o)
        }
        return true
    }
    static func apply(id: EntityID, kind: String, doc: inout ArchiDocument) -> Bool {
        if kind == "wall" { return flipWall(id, doc: &doc) }
        guard let i = doc.elementIndex(id), case .opening(var o) = doc.elements[i].geometry else { return false }
        if kind == "facing" { o.flipFacing.toggle() } else if kind == "hand" { o.flipHand.toggle() } else { return false }
        doc.elements[i].geometry = .opening(o)
        return true
    }
}

/// Sheet viewport locks and clips as the Mac stores them (ArchiApp PlotExtras.swift ViewportLock, AppNavigation.swift SheetTools).
enum EngineViewports {
    static func lockKey(_ layout: String) -> String { "VPLOCK:" + layout.uppercased() }
    static func locked(_ doc: ArchiDocument, _ li: Int) -> Set<Int> {
        guard doc.layouts.indices.contains(li), let s = doc.variables[lockKey(doc.layouts[li].name)] else { return [] }
        return Set(s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }
    static func isLocked(_ doc: ArchiDocument, _ li: Int, _ vi: Int) -> Bool { locked(doc, li).contains(vi) }
    static func setLocked(_ doc: inout ArchiDocument, _ li: Int, _ vi: Int, _ on: Bool) {
        guard doc.layouts.indices.contains(li) else { return }
        var l = locked(doc, li)
        if on { l.insert(vi) } else { l.remove(vi) }
        let n = doc.layouts[li].viewports.count
        let list = l.filter { $0 >= 0 && $0 < n }.sorted().map(String.init)
        doc.variables[lockKey(doc.layouts[li].name)] = list.isEmpty ? nil : list.joined(separator: ",")
    }
    static func clipKey(_ layout: String, _ i: Int) -> String { "VPCLIP:\(layout.uppercased()):\(i)" }
    static func clip(_ doc: ArchiDocument, _ li: Int, _ vi: Int) -> [Vec2]? {
        guard doc.layouts.indices.contains(li), let s = doc.variable(clipKey(doc.layouts[li].name, vi)) else { return nil }
        var pts: [Vec2] = []
        for p in s.split(separator: ";") {
            let c = p.split(separator: ",").compactMap { Double($0) }
            if c.count == 2 { pts.append(Vec2(c[0], c[1])) }
        }
        return pts.count >= 3 ? pts : nil
    }
    static func modelPoint(_ q: Vec2, in vp: Viewport) -> Vec2 { vp.viewCenter + (q - vp.origin - vp.size / 2) * vp.scale }
    static func modelWindow(_ vp: Viewport) -> BBox2 {
        BBox2(min: vp.viewCenter - vp.size * (vp.scale / 2), max: vp.viewCenter + vp.size * (vp.scale / 2))
    }
    static func setClip(_ doc: inout ArchiDocument, _ li: Int, _ vi: Int, _ pts: [Vec2]?) {
        guard doc.layouts.indices.contains(li), doc.layouts[li].viewports.indices.contains(vi) else { return }
        let key = clipKey(doc.layouts[li].name, vi)
        guard let pts, pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-9 else { doc.variables[key] = nil; return }
        doc.variables[key] = pts.map { "\(fmt($0.x, 4)),\(fmt($0.y, 4))" }.joined(separator: ";")
        var vp = doc.layouts[li].viewports[vi]
        let b = BBox2(points: pts)
        let c = modelPoint(b.center, in: vp)
        vp.origin = b.min
        vp.size = Vec2(b.width, b.height)
        vp.viewCenter = c
        doc.layouts[li].viewports[vi] = vp
    }
    /// Keeps lock and clip indices valid after viewport `vi` of sheet `li` was removed (call after removing it).
    static func removed(_ doc: inout ArchiDocument, _ li: Int, _ vi: Int) {
        guard doc.layouts.indices.contains(li) else { return }
        let name = doc.layouts[li].name
        var l: [Int] = []
        for k in locked(doc, li) where k != vi { l.append(k > vi ? k - 1 : k) }
        doc.variables[lockKey(name)] = l.isEmpty ? nil : l.sorted().map(String.init).joined(separator: ",")
        doc.variables[clipKey(name, vi)] = nil
        let old = doc.layouts[li].viewports.count + 1
        guard vi + 1 < old else { return }
        for j in (vi + 1)..<old {
            doc.variables[clipKey(name, j - 1)] = doc.variables[clipKey(name, j)]
            doc.variables[clipKey(name, j)] = nil
        }
    }
    static func gridSpacing(_ doc: ArchiDocument, _ layout: String) -> Double {
        doc.variable("SHEETGRID:\(layout.uppercased())").flatMap(Double.init).map { max($0, 0) } ?? 0
    }
    static func ratioText(_ scale: Double, units: Units) -> String {
        let r = scale * units.mm
        if r >= 1 { return "1:" + fmt(r, 2) }
        return fmt(1 / max(r, 1e-12), 2) + ":1"
    }
}

extension EngineSession {
    func callCanvas(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "canvas.state": return canvasState()
        case "canvas.view": return canvasView(p)
        case "canvas.doubleClick": return try canvasDoubleClick(p)
        case "grips.actions": return try gripActionsJSON(p)
        case "grips.preview": return try gripPreviewJSON(p)
        case "grips.edit": return try gripEditJSON(p)
        case "grips.typed": return try gripTypedJSON(p)
        case "select.lasso": return try await selectLasso(p)
        case "select.modify": return selectModify(p)
        case "select.chain": return try selectChain(p)
        case "select.nudge": return selectNudge(p)
        case "pick.candidates": return try pickCandidatesJSON(p)
        case "text.edit": return try textEdit(p)
        case "tempdims.get": return tempDimsJSON(p)
        case "tempdims.set": return try tempDimsSet(p)
        case "flips.get": return flipsJSON(p)
        case "flips.apply": return try flipsApply(p)
        case "palette.items": return paletteItems()
        case "place.preview": return try placePreview(p)
        case "place.drop": return try await placeDrop(p)
        case "file.drop": return try await fileDrop(p)
        case "sheet.viewports": return try sheetViewports(p)
        case "sheet.viewport": return try sheetViewportEdit(p)
        default: return nil
        }
    }

    // MARK: View state

    func canvasState() -> EngineJSON {
        let doc = editor.doc
        let ucs = UCSFrame.current(doc)
        var u = EngineObject()
        u.set("origin", EngineJSON.point(ucs.origin))
        u.set("angle", ucs.angle)
        u.set("world", ucs.isWorld)
        let icon = UCSIcon.mode(doc)
        var ic = EngineObject()
        ic.set("on", icon.on)
        ic.set("atOrigin", icon.atOrigin)
        var o = EngineObject()
        o.set("ucs", u.json)
        o.set("ucsIcon", ic.json)
        o.set("twist", doc.variable("VIEWTWIST").flatMap(Double.init) ?? 0)
        o.set("isometric", editor.settings.isometric)
        o.set("isoPlane", editor.settings.isoPlane)
        o.set("ducs", DynamicUCS.isOn(doc))
        o.set("doubleClickEditing", editor.doubleClickEditing)
        o.set("grips", editor.gripsEnabled)
        o.set("gripObjectLimit", editor.gripObjectLimit)
        o.set("selectionPreview", doc.variable("SELECTIONPREVIEW").flatMap(Int.init) ?? 3)
        o.set("dynamicInput", editor.settings.dynamicInput)
        o.set("dynMode", editor.dynamicInputMode)
        o.set("lastCommand", EngineJSON.optString(editor.lastCommand))
        o.set("canUndo", editor.history.canUndo)
        o.set("canRedo", editor.history.canRedo)
        o.set("undoLabel", EngineJSON.optString(editor.history.undoLabel))
        o.set("redoLabel", EngineJSON.optString(editor.history.redoLabel))
        o.set("currentSheet", EngineJSON.optString(doc.variable("CTAB")))
        let st = EngineCanvasState.of(editor)
        if let m = st.maximized { o.set("maximizedViewport", EngineJSON.ints([m.layout, m.viewport])) }
        return o.json
    }

    /// `canvas.view {center, scale, rect?}`: the shell's plan view (VPMIN keeps the centre; UCS icon anchor).
    func canvasView(_ p: EngineJSON) -> EngineJSON {
        let st = EngineCanvasState.of(editor)
        if let c = p["center"]?.arrayValue, c.count == 2, let x = c[0].doubleValue, let y = c[1].doubleValue { st.viewCenter = Vec2(x, y) }
        if let s = p["scale"]?.doubleValue, s > 0 { st.viewScale = s; updatePixels(EngineJSON.object([EngineJSONField("pixelsPerUnit", .number(s))])) }
        if let r = rect(p["rect"]) { st.visible = r }
        if let b = p["radialMenu"]?.boolValue { st.radialMenu = b }
        var o = EngineObject()
        o.set("ok", true)
        return o.json
    }

    /// Extra fields of `input.cursor`: tracking points / vectors (OTRACK), the dynamic-input fields and the dynamic-UCS
    /// axes at the crosshair, as the Mac canvas overlay draws them.
    func canvasCursorExtras(_ o: inout EngineObject, point: Vec2) {
        let tr = Snap.tracker
        if tr.active, !(tr.points.isEmpty && tr.lines.isEmpty) {
            var t = EngineObject()
            t.set("points", EngineJSON.array(tr.points.map { EngineJSON.point($0) }))
            var ls: [EngineJSON] = []
            for l in tr.lines {
                var lo = EngineObject()
                lo.set("from", EngineJSON.point(l.from))
                lo.set("to", EngineJSON.point(l.to))
                ls.append(lo.json)
            }
            t.set("lines", EngineJSON.array(ls))
            o.set("tracking", t.json)
        } else {
            o.set("tracking", EngineJSON.null)
        }
        if let f = editor.dynamicInputFields(cursor: point) {
            var d = EngineObject()
            if let l = f.length { d.set("length", l) }
            if let a = f.angle { d.set("angle", a) }
            d.set("x", f.x)
            d.set("y", f.y)
            d.set("relative", f.relative)
            d.set("onFace", f.onFace)
            o.set("dynamic", d.json)
        }
        guard let req = editor.request, req.kinds.contains(.point) else { return }
        let face = editor.dynamicFaceFrame ?? DynamicUCS.activeFace(at: point, doc: editor.doc)?.rotatedX(to: UCSFrame.current(editor.doc).angle)
        guard let f = face else { return }
        let len = 36 / max(pixelsPerUnit, 1e-12)
        let origin = f.planePoint(point).map { Vec2($0.x, $0.y) } ?? point
        var segs: [EngineJSON] = []
        let axes: [(Vec3, String)] = [(f.xAxis, "#f24033"), (f.yAxis, "#4dd94d"), (f.normal, "#4d8cff")]
        for (axis, col) in axes {
            let d = Vec2(axis.x, axis.y)
            guard d.length > 0.05 else { continue }
            var s = EngineObject()
            s.set("from", EngineJSON.point(origin))
            s.set("to", EngineJSON.point(origin + d * len))
            s.set("color", col)
            segs.append(s.json)
        }
        o.set("ducs", EngineJSON.array(segs))
    }

    // MARK: Grips

    func gripTarget(_ p: EngineJSON) throws -> (id: EntityID, index: Int, origin: Vec2) {
        guard let id = p["id"]?.intValue, let index = p["index"]?.intValue else { throw EngineError.params("missing 'id' / 'index'") }
        let pts = editor.objectGrips(id)
        guard pts.indices.contains(index) else { throw EngineError.params("object \(id) has no grip \(index)") }
        return (id, index, pts[index])
    }
    func gripMode(_ p: EngineJSON) -> GripMode { p["mode"]?.stringValue.flatMap { GripMode.keyword($0) } ?? .stretch }
    func gripAction(_ p: EngineJSON) -> GripAction? {
        guard let s = p["action"]?.stringValue, !s.isEmpty else { return nil }
        if let a = GripAction(rawValue: s) { return a }
        return GripAction.allCases.first { $0.title.caseInsensitiveCompare(s) == .orderedSame }
    }

    /// `grips.actions {id, index}`: the multi-functional grip menu (SEL-035); empty when the grip has one option.
    func gripActionsJSON(_ p: EngineJSON) throws -> EngineJSON {
        let g = try gripTarget(p)
        var out: [EngineJSON] = []
        for a in editor.gripActions(g.id, index: g.index) {
            var o = EngineObject()
            o.set("action", a.rawValue)
            o.set("title", a.title)
            o.set("immediate", a == .removeVertex || a == .convertToLine)
            out.append(o.json)
        }
        return .array(out)
    }

    /// Point a grip drag goes to: the core grip stretch (snaps, ortho/polar from the grip) or, for element grips and
    /// grip modes, running snaps / grid snap / ortho from the hot grip — as CanvasView.updateCursorPoint.
    func gripPoint(_ id: EntityID, index: Int, origin: Vec2, raw: Vec2, mode: GripMode, action: GripAction?) -> (Vec2, SnapResult?) {
        let s = editor.settings
        let tol = 10 / max(pixelsPerUnit, 1e-12)
        if mode == .stretch, action == nil, let e = editor.doc.entity(id) {
            let gs = Grips.grips(e.geometry)
            if gs.indices.contains(index) {
                let p = editor.gripDragPoint(id, grip: gs[index], cursor: raw, tolerance: tol)
                var hit: SnapResult?
                if s.objectSnap, let r = Snap.find(cursor: raw, doc: editor.doc, settings: s, tolerance: tol, base: gs[index].point), r.point.isClose(p, tol: 1e-9) { hit = r }
                return (p, hit)
            }
        }
        if s.objectSnap, let r = Snap.find(cursor: raw, doc: editor.doc, settings: s, tolerance: tol, base: origin), r.entity != id { return (r.point, r) }
        var p = raw
        if s.gridSnap, s.gridSpacing > 0 {
            let g = s.gridSpacing
            p = Vec2((p.x / g).rounded() * g, (p.y / g).rounded() * g)
        }
        return (Snap.constrain(base: origin, cursor: p, settings: s), nil)
    }

    static func snapJSON(_ s: SnapResult?) -> EngineJSON {
        guard let s else { return .null }
        var so = EngineObject()
        so.set("kind", s.kind.rawValue)
        so.set("point", EngineJSON.point(s.point))
        if let e = s.entity { so.set("entity", e) }
        return so.json
    }

    /// Plan outline of an element for previews (PlanRepresentation, else its footprint).
    func elementPreviewItems(_ el: BIMElement) -> [DrawItem] {
        let items = PlanRepresentation.items(el, doc: editor.doc)
        if !items.isEmpty { return items }
        let fp = CommandHelpers.footprint(el, doc: editor.doc)
        guard fp.count >= 2 else { return [] }
        return [.stroke(points: fp, closed: fp.count > 2, style: StrokeStyle(color: EngineSession.previewColor, lineweight: 0.25))]
    }
    func previewDrawItems(_ geoms: [Geometry], _ els: [BIMElement]) -> [DrawItem] {
        var items = DrawListBuilder.previewItems(geoms, doc: editor.doc, color: EngineSession.previewColor)
        if items.isEmpty {
            for g in geoms {
                for pl in GeometryOps.tessellate(g, doc: editor.doc) where !pl.isEmpty {
                    items.append(.stroke(points: pl, closed: false, style: StrokeStyle(color: EngineSession.previewColor, lineweight: 0.25)))
                }
            }
        }
        for el in els { items += elementPreviewItems(el) }
        return items
    }

    /// `grips.preview {id, index, x, y, mode?, action?, turns?, snap?=true}` → `{point, snap, items, reference}`.
    func gripPreviewJSON(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        let g = try gripTarget(p)
        let raw = try rawPoint(p)
        let mode = gripMode(p)
        let action = gripAction(p)
        let turns = p["turns"]?.intValue ?? 0
        var point = raw
        var snap: SnapResult?
        if p["snap"]?.boolValue ?? true {
            let r = gripPoint(g.id, index: g.index, origin: g.origin, raw: raw, mode: mode, action: action)
            point = r.0
            snap = r.1
        }
        let reference = p["reference"]?.doubleValue ?? editor.gripReference(editor.gripTargets(g.id))
        let pv = editor.gripPreview(g.id, index: g.index, from: g.origin, to: point, mode: mode, action: action, turns: turns, reference: reference)
        var o = EngineObject()
        o.set("point", EngineJSON.point(point))
        o.set("origin", EngineJSON.point(g.origin))
        o.set("snap", EngineSession.snapJSON(snap))
        o.set("reference", reference)
        o.set("items", EngineDrawJSON.items(previewDrawItems(pv.geometry, pv.elements)))
        return o.json
    }

    /// `grips.edit {id, index, x, y, mode?, action?, copy?, turns?, snap?=false, reference?}` → `{changed, grips}`.
    func gripEditJSON(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        let g = try gripTarget(p)
        let raw = try rawPoint(p)
        let mode = gripMode(p)
        let action = gripAction(p)
        var point = raw
        if p["snap"]?.boolValue ?? false { point = gripPoint(g.id, index: g.index, origin: g.origin, raw: raw, mode: mode, action: action).0 }
        var changed: [EntityID] = []
        if let a = action, a != .stretch, mode == .stretch, let e = editor.doc.entity(g.id) {
            let gs = Grips.grips(e.geometry)
            let copy = p["copy"]?.boolValue ?? false
            if !copy, gs.indices.contains(g.index), editor.gripAction(g.id, grip: gs[g.index], action: a, to: point, snap: false) { changed = [g.id] }
            else if copy { changed = editor.gripEdit(g.id, index: g.index, from: g.origin, to: point, mode: .stretch, action: a, copy: true) }
        } else {
            changed = editor.gripEdit(g.id, index: g.index, from: g.origin, to: point, mode: mode, action: action, copy: p["copy"]?.boolValue ?? false,
                                      turns: p["turns"]?.intValue ?? 0, snap: false, reference: p["reference"]?.doubleValue)
        }
        var o = EngineObject()
        o.set("changed", EngineJSON.ints(changed))
        o.set("grips", gripsJSON())
        return o.json
    }

    /// `grips.typed {id, index, mode, value, x, y, copy?}`: a value typed while the grip is hot (SEL-038).
    func gripTypedJSON(_ p: EngineJSON) throws -> EngineJSON {
        let g = try gripTarget(p)
        let cursor = try rawPoint(p)
        guard let v = p["value"]?.doubleValue ?? p["value"]?.stringValue.flatMap({ InputParser.parseNumber($0) }) else { throw EngineError.params("missing number 'value'") }
        let changed = editor.gripTypedValue(g.id, index: g.index, mode: gripMode(p), value: v, cursor: cursor, copy: p["copy"]?.boolValue ?? false)
        var o = EngineObject()
        o.set("changed", EngineJSON.ints(changed))
        o.set("grips", gripsJSON())
        return o.json
    }

    // MARK: Selection

    func points(_ v: EngineJSON?) -> [Vec2] {
        var out: [Vec2] = []
        for q in v?.arrayValue ?? [] {
            if let a = q.arrayValue, a.count >= 2, let x = a[0].doubleValue, let y = a[1].doubleValue { out.append(Vec2(x, y)) }
            else if let x = q["x"]?.doubleValue, let y = q["y"]?.doubleValue { out.append(Vec2(x, y)) }
        }
        return out
    }

    /// `select.lasso {points, remove?, crossing?}` (world points): clockwise = window, counter-clockwise = crossing (SEL-007).
    func selectLasso(_ p: EngineJSON) async throws -> EngineJSON {
        let loop = points(p["points"])
        guard loop.count >= 3 else { throw EngineError.params("a lasso needs at least 3 points") }
        let crossing = p["crossing"]?.boolValue
        let mode = SelectionGeometry.lassoMode(loop)
        if let req = editor.request, req.kinds.contains(.selection) {
            let ids = editor.expandGroups(editor.select(lasso: loop, crossing: crossing)).sorted()
            editor.feed(.selection(ids))
            await settle()
            var o = selectionResult()
            o.set("mode", mode == .crossingPolygon ? "crossing" : "window")
            return o.json
        }
        let found = editor.applyLasso(loop, remove: p["remove"]?.boolValue ?? false, crossing: crossing)
        var o = selectionResult()
        o.set("found", EngineJSON.ints(found.sorted()))
        o.set("mode", mode == .crossingPolygon ? "crossing" : "window")
        return o.json
    }

    /// `select.modify {remove?, add?}`: removes then adds objects (groups expanded) — selection cycling swaps one object.
    func selectModify(_ p: EngineJSON) -> EngineJSON {
        let rem = (p["remove"]?.arrayValue ?? []).compactMap(\.intValue)
        let add = (p["add"]?.arrayValue ?? []).compactMap(\.intValue).filter { editor.isSelectable($0) }
        if !rem.isEmpty { editor.selection.subtract(editor.expandGroups(rem)) }
        if !add.isEmpty { editor.selection.formUnion(editor.expandGroups(add)) }
        return selectionResult().json
    }

    /// `pick.candidates {x, y, tolerance?}`: the objects under a point, the canvas pick first (selection cycling, SEL-018).
    func pickCandidatesJSON(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        let pt = try rawPoint(p)
        let tol = p["tolerance"]?.doubleValue ?? editor.pickTolerance
        var ids: [EntityID] = []
        if let first = editor.pick(at: pt, tolerance: tol) { ids.append(first) }
        for id in editor.pickCandidates(at: pt, tolerance: tol) where !ids.contains(id) && editor.isSelectable(id) { ids.append(id) }
        var o = EngineObject()
        o.set("ids", EngineJSON.ints(ids))
        o.set("types", EngineJSON.strings(ids.map { ObjectQuery.typeName($0, doc: editor.doc) ?? "object" }))
        return o.json
    }

    /// `select.chain {id}` or `{x, y}`: adds the chain of joined walls (Tab over a wall, SEL-022).
    func selectChain(_ p: EngineJSON) throws -> EngineJSON {
        updatePixels(p)
        var id = p["id"]?.intValue
        if id == nil, let x = p["x"]?.doubleValue, let y = p["y"]?.doubleValue { id = editor.pick(at: Vec2(x, y), tolerance: editor.pickTolerance) }
        var chain: [EntityID] = []
        if let id, let el = editor.doc.element(id), case .wall = el.geometry {
            let tol = max(2 / max(pixelsPerUnit, 1e-12), 1)
            chain = EngineWallChain.ids(from: id, doc: editor.doc, tolerance: tol).filter { editor.isSelectable($0) }
            editor.selection.formUnion(chain)
        }
        var o = selectionResult()
        o.set("chain", EngineJSON.ints(chain))
        o.set("hint", "Selected \(chain.count) joined wall(s)")
        return o.json
    }

    /// `select.nudge {dx, dy}` in steps (arrow keys, MOD-028): one pixel, the snap spacing with grid snap; `big` ×10.
    func selectNudge(_ p: EngineJSON) -> EngineJSON {
        let step = editor.nudgeStep() * ((p["big"]?.boolValue ?? false) ? 10 : 1)
        let d = Vec2((p["dx"]?.doubleValue ?? 0) * step, (p["dy"]?.doubleValue ?? 0) * step)
        let n = editor.nudgeSelection(by: d)
        var o = EngineObject()
        o.set("moved", n)
        o.set("step", step)
        o.set("hint", n > 0 ? "Nudged \(n) object(s) by \(fmt(d.length, 4))" : "Nothing to nudge (locked layer?)")
        return o.json
    }

    // MARK: Double-click editing and text

    /// `canvas.doubleClick {id}` (CanvasView.editObject): text opens the in-place editor, leaders and dimensions the Edit
    /// Text dialog, anything else selects the object and shows its properties. `command` is the DBLCLKEDIT editor command.
    func canvasDoubleClick(_ p: EngineJSON) throws -> EngineJSON {
        guard let id = p["id"]?.intValue else { throw EngineError.params("missing 'id'") }
        let doc = editor.doc
        var o = EngineObject()
        o.set("id", id)
        o.set("command", EngineJSON.optString(editor.doubleClickCommand(for: id)))
        guard let e = doc.entity(id) else {
            editor.selection = [id]
            o.set("action", "properties")
            return o.json
        }
        switch e.geometry {
        case .text(let t):
            o.set("action", "textEditor")
            o.set("text", EngineDrawJSON.textGeom(t))
            o.set("content", t.content.replacingOccurrences(of: "\\P", with: "\n"))
            o.set("singleLine", t.width <= 0 && !t.content.contains("\n") && !t.content.contains("\\P"))
            let styleFont = TextStyleFonts.style(t.style, doc: doc)?.font ?? "Helvetica"
            o.set("styleFont", styleFont)
            var f = EngineObject()
            if let fn = e.props["font"], !fn.trimmingCharacters(in: .whitespaces).isEmpty { f.set("font", fn) }
            f.set("bold", e.props["bold"] == "1")
            f.set("italic", e.props["italic"] == "1")
            f.set("underline", e.props["underline"] == "1")
            o.set("format", f.json)
            o.set("color", e.color.text)
        case .leader(let l):
            o.set("action", "textDialog")
            o.set("content", l.text)
            o.set("multiline", true)
            o.set("message", "Edit the text content.")
        case .dimension(let d):
            o.set("action", "textDialog")
            o.set("content", d.textOverride ?? "")
            o.set("multiline", false)
            o.set("message", "Override the measured value (leave empty for the measurement). Use <> for the measured value.")
        default:
            editor.selection = [id]
            o.set("action", "properties")
        }
        return o.json
    }

    /// `text.edit {id, content, height?, font?, bold?, italic?, underline?, color?}`: the in-place editor / Edit Text dialog
    /// commit ("Edit Text"). Text formatting is stored as whole-text props plus the equivalent MTEXT string.
    func textEdit(_ p: EngineJSON) throws -> EngineJSON {
        guard let id = p["id"]?.intValue, let e = editor.doc.entity(id) else { throw EngineError.params("missing or unknown 'id'") }
        let content = try string(p, "content")
        var changed = false
        switch e.geometry {
        case .text(let t0):
            let h = p["height"]?.doubleValue ?? t0.height
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngineError.failed("text is empty") }
            guard h > 0, h.isFinite else { throw EngineError.failed("height must be positive") }
            var font: String? = e.props["font"]
            if let fv = p["font"] {
                let s = (fv.stringValue ?? "").trimmingCharacters(in: .whitespaces)
                font = s.isEmpty ? nil : s
            }
            let wasBold = e.props["bold"] == "1"
            let wasItalic = e.props["italic"] == "1"
            let wasUnderline = e.props["underline"] == "1"
            let bold = p["bold"]?.boolValue ?? wasBold
            let italic = p["italic"]?.boolValue ?? wasItalic
            let underline = p["underline"]?.boolValue ?? wasUnderline
            var color = e.color
            if let cs = p["color"]?.stringValue, let c = ColorRef.parse(cs) { color = c }
            var same = t0.content == content && t0.height == h
            same = same && e.color == color && e.props["font"] == font
            same = same && wasBold == bold && wasItalic == italic && wasUnderline == underline
            if !same {
                editor.transaction("Edit Text") { d in
                    guard let k = d.entityIndex(id), case .text(var t) = d.entities[k].geometry else { return }
                    t.content = content
                    t.height = h
                    d.entities[k].geometry = .text(t)
                    d.entities[k].color = color
                    var props = d.entities[k].props
                    props["font"] = font
                    props["bold"] = bold ? "1" : nil
                    props["italic"] = italic ? "1" : nil
                    props["underline"] = underline ? "1" : nil
                    props["mtext"] = nil
                    if font != nil || bold || italic || underline {
                        let family = font ?? TextStyleFonts.style(t.style, doc: d)?.font ?? "Helvetica"
                        let f: String? = (bold || italic || font != nil) ? family : nil
                        props["mtext"] = MTextFormatting.encode(content, font: f, bold: bold, italic: italic, underline: underline)
                    }
                    d.entities[k].props = props
                }
                changed = true
            }
        case .leader(let l):
            if l.text != content {
                editor.transaction("Edit Text") { d in
                    guard let k = d.entityIndex(id), case .leader(var g) = d.entities[k].geometry else { return }
                    g.text = content
                    d.entities[k].geometry = .leader(g)
                }
                changed = true
            }
        case .dimension(let dm):
            if (dm.textOverride ?? "") != content {
                editor.transaction("Edit Text") { d in
                    guard let k = d.entityIndex(id), case .dimension(var g) = d.entities[k].geometry else { return }
                    g.textOverride = content.isEmpty ? nil : content
                    d.entities[k].geometry = .dimension(g)
                }
                changed = true
            }
        default:
            throw EngineError.failed("Object \(id) has no text to edit.")
        }
        var o = EngineObject()
        o.set("changed", changed)
        return o.json
    }

    // MARK: Temporary dimensions (CMD-035)

    func tempDimsJSON(_ p: EngineJSON) -> EngineJSON {
        var ids: [EntityID] = []
        if let id = p["id"]?.intValue { ids = [id] } else if editor.selection.count == 1, let id = editor.selection.first { ids = [id] }
        var out: [EngineJSON] = []
        for id in ids where editor.isIdle {
            for (i, td) in editor.temporaryDimensions(for: id).enumerated() {
                var o = EngineObject()
                o.set("id", td.id)
                o.set("index", i)
                o.set("reference", td.reference)
                o.set("from", EngineJSON.point(td.from))
                o.set("to", EngineJSON.point(td.to))
                o.set("value", td.value)
                o.set("text", fmt(td.value, 2))
                o.set("direction", EngineJSON.point(td.direction))
                out.append(o.json)
            }
        }
        return .array(out)
    }

    func tempDimsSet(_ p: EngineJSON) throws -> EngineJSON {
        guard let id = p["id"]?.intValue, let i = p["index"]?.intValue else { throw EngineError.params("missing 'id' / 'index'") }
        guard let v = p["value"]?.doubleValue ?? p["value"]?.stringValue.flatMap({ InputParser.parseNumber($0) }) else { throw EngineError.params("missing number 'value'") }
        let tds = editor.temporaryDimensions(for: id)
        guard tds.indices.contains(i) else { throw EngineError.params("no temporary dimension \(i) on \(id)") }
        let ok = editor.applyTemporaryDimension(tds[i], value: v)
        var o = EngineObject()
        o.set("changed", ok)
        o.set("dims", tempDimsJSON(p))
        return o.json
    }

    // MARK: Flip arrows (SEL-036)

    func flipControls(gap: Double) -> [EngineFlips.Control] {
        guard editor.isIdle, editor.selection.count <= 20 else { return [] }
        var out: [EngineFlips.Control] = []
        for el in editor.doc.elements where editor.selection.contains(el.id) && editor.isSelectable(el.id) {
            out += EngineFlips.controls(el, doc: editor.doc, gap: gap)
            if let w = EngineFlips.wallControl(el, gap: gap) { out.append(w) }
        }
        return out
    }

    /// `flips.get {pixelsPerUnit?}`: flip arrows of the selected doors, windows and walls (16 px from the wall face).
    func flipsJSON(_ p: EngineJSON) -> EngineJSON {
        updatePixels(p)
        var out: [EngineJSON] = []
        for c in flipControls(gap: 16 / max(pixelsPerUnit, 1e-12)) {
            var o = EngineObject()
            o.set("id", c.id)
            o.set("kind", c.kind)
            o.set("point", EngineJSON.point(c.point))
            o.set("direction", EngineJSON.point(c.direction))
            out.append(o.json)
        }
        return .array(out)
    }

    /// `flips.apply {id, kind: facing|hand|wall}` ("Flip Facing" / "Flip Hand" / "Flip Wall").
    func flipsApply(_ p: EngineJSON) throws -> EngineJSON {
        guard let id = p["id"]?.intValue, let kind = p["kind"]?.stringValue else { throw EngineError.params("missing 'id' / 'kind'") }
        let label = kind == "facing" ? "Flip Facing" : kind == "hand" ? "Flip Hand" : "Flip Wall"
        var ok = false
        editor.transaction(label) { d in ok = EngineFlips.apply(id: id, kind: kind, doc: &d) }
        var o = EngineObject()
        o.set("changed", ok)
        o.set("flips", flipsJSON(.object([])))
        return o.json
    }

    // MARK: Tool palettes, click-to-place and drops (ToolPalette.swift, Studio3D.swift Placement)

    /// `palette.items {}`: blocks of the drawing and the component library, with line thumbnails.
    func paletteItems() -> EngineJSON {
        let doc = editor.doc
        var blocks: [EngineJSON] = []
        for n in doc.blocks.keys.filter({ !$0.hasPrefix("*") }).sorted() {
            let shapes = Array(GeometryOps.tessellate(.insert(InsertGeom(block: n, position: .zero)), doc: doc).prefix(400))
            var o = EngineObject()
            o.set("name", n)
            o.set("item", EngineToolDrop.blockPrefix + n)
            o.set("shapes", EngineJSON.array(shapes.map { EngineDrawJSON.points($0) }))
            blocks.append(o.json)
        }
        var comps: [EngineJSON] = []
        for f in ComponentLibrary.families {
            let g = ComponentGeom(category: f.category, position: .zero, size: f.size, family: f.id)
            var shapes: [EngineJSON] = []
            for l in ComponentLibrary.worldSymbol(f, g) {
                let pts = l.closed && !l.points.isEmpty ? l.points + [l.points[0]] : l.points
                shapes.append(EngineDrawJSON.points(pts))
            }
            var o = EngineObject()
            o.set("id", f.id)
            o.set("name", f.name)
            o.set("category", f.category)
            o.set("size", EngineJSON.point3(f.size))
            o.set("item", EngineToolDrop.componentPrefix + f.id)
            o.set("shapes", EngineJSON.array(shapes))
            comps.append(o.json)
        }
        var o = EngineObject()
        o.set("blocks", EngineJSON.array(blocks))
        o.set("components", EngineJSON.array(comps))
        return o.json
    }

    /// `place.preview {item, x, y, turns?}`: the palette item drawn at the cursor, rotated by Space (MOD-029).
    func placePreview(_ p: EngineJSON) throws -> EngineJSON {
        let item = try string(p, "item")
        let at = try rawPoint(p)
        let turns = p["turns"]?.intValue ?? 0
        let doc = editor.doc
        var items: [DrawItem] = []
        if item.hasPrefix(EngineToolDrop.blockPrefix) {
            let n = String(item.dropFirst(EngineToolDrop.blockPrefix.count))
            if doc.blocks[n] != nil { items = previewDrawItems([.insert(InsertGeom(block: n, position: at, rotation: EngineToolDrop.angle(turns)))], []) }
        } else if item.hasPrefix(EngineToolDrop.componentPrefix), let f = ComponentLibrary.family(String(item.dropFirst(EngineToolDrop.componentPrefix.count))) {
            let g = ComponentGeom(category: f.category, position: at, rotation: EngineToolDrop.angle(turns), size: f.size, baseOffset: f.baseOffset, family: f.id)
            let el = BIMElement(id: -1, level: doc.currentLevel, name: f.name, layer: doc.currentLayer, geometry: .component(g))
            items = previewDrawItems([], [el])
        }
        var o = EngineObject()
        o.set("items", EngineDrawJSON.items(items))
        o.set("degrees", ((turns % 4) + 4) % 4 * 90)
        return o.json
    }

    /// `place.drop {item, x, y, turns?, hit?}`: places a palette / drag item at a world point (ToolDrop.drop), one undo step.
    /// Commands (`archi-command:`) run; materials are assigned to the building element under the drop point.
    func placeDrop(_ p: EngineJSON) async throws -> EngineJSON {
        let s = try string(p, "item")
        let at = try rawPoint(p)
        let rotation = EngineToolDrop.angle(p["turns"]?.intValue ?? 0)
        var o = EngineObject()
        var ok = false
        if s.hasPrefix(EngineToolDrop.libraryBlockPrefix) {
            let key = String(s.dropFirst(EngineToolDrop.libraryBlockPrefix.count))
            let parts = key.split(separator: "\u{241F}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            var q = EngineObject()
            q.set("file", parts.first ?? key)
            if parts.count > 1, !parts[1].isEmpty { q.set("block", parts[1]) }
            q.set("x", at.x)
            q.set("y", at.y)
            let r = try libraryInsert(q.json)
            o.set("result", r)
            ok = true
        } else if s.hasPrefix(EngineToolDrop.blockPrefix) {
            let name = String(s.dropFirst(EngineToolDrop.blockPrefix.count))
            if editor.doc.blocks[name] != nil {
                var id: EntityID = 0
                editor.transaction("Insert \(name)") { d in id = d.add(.insert(InsertGeom(block: name, position: at, rotation: rotation)), layer: d.currentLayer) }
                editor.selection = [id]
                editor.print("Inserted block \(name) at \(fmt(at.x, 2)),\(fmt(at.y, 2)).")
                o.set("id", id)
                ok = true
            }
        } else if s.hasPrefix(EngineToolDrop.componentPrefix) {
            if let f = ComponentLibrary.family(String(s.dropFirst(EngineToolDrop.componentPrefix.count))) {
                var id: EntityID = 0
                let g = ComponentGeom(category: f.category, position: at, rotation: rotation, size: f.size, baseOffset: f.baseOffset, family: f.id)
                editor.transaction("Place \(f.name)") { d in
                    ComponentLibrary.ensureMaterials(&d)
                    id = d.addElement(.component(g), name: f.name)
                }
                editor.selection = [id]
                editor.print("Placed \(f.name.lowercased()) at \(fmt(at.x, 2)),\(fmt(at.y, 2)).")
                o.set("id", id)
                ok = true
            }
        } else if s.hasPrefix(EngineToolDrop.commandPrefix) {
            let line = String(s.dropFirst(EngineToolDrop.commandPrefix.count))
            let name = line.split(separator: " ").first.map(String.init) ?? line
            if editor.registry.lookup(name) != nil {
                await cancelAndWait()
                submit(line)
                await settle()
                o.set("prompt", promptState())
                ok = true
            }
        } else if s.hasPrefix(EngineToolDrop.materialPrefix) {
            let name = String(s.dropFirst(EngineToolDrop.materialPrefix.count))
            let hit = p["hit"]?.intValue ?? editor.pick(at: at, tolerance: editor.pickTolerance)
            if let hit, editor.doc.elements.contains(where: { $0.id == hit }), editor.doc.material(name) != nil {
                editor.transaction("Assign Material") { d in
                    if let i = d.elements.firstIndex(where: { $0.id == hit }) { d.elements[i].material = name }
                }
                editor.print("\(name) assigned.")
                ok = true
            } else {
                editor.print("Drop a material on a building element.")
            }
        }
        o.set("ok", ok)
        o.set("selection", EngineJSON.ints(editor.selection.sorted()))
        return o.json
    }

    /// `file.drop {paths, x, y}` (IO-065): drawings and scripts are returned for the shell to open / run; images, PDFs
    /// and exchange formats are imported at the drop point as one undo step ("Drop <file>").
    func fileDrop(_ p: EngineJSON) async throws -> EngineJSON {
        let paths = (p["paths"]?.arrayValue ?? []).compactMap(\.stringValue)
        guard !paths.isEmpty else { throw EngineError.params("missing 'paths'") }
        let at = try rawPoint(p)
        var open: [String] = [], scripts: [String] = [], unsupported: [String] = [], rest: [URL] = []
        for path in paths {
            let u = url(path)
            switch ExternalContent.dropAction(for: u) {
            case .open: open.append(u.path)
            case .runScript: scripts.append(u.path)
            case .unsupported:
                unsupported.append(u.path)
                editor.print("\(u.lastPathComponent): not a file type Archi Tool can import.")
            default: rest.append(u)
            }
        }
        var ids: [EntityID] = []
        if !rest.isEmpty {
            var res: [(url: URL, result: ExternalContent.Result?, error: String?)] = []
            let label = rest.count == 1 ? "Drop \(rest[0].lastPathComponent)" : "Drop \(rest.count) files"
            editor.transaction(label) { d in res = ExternalContent.drop(rest, into: &d, at: at) }
            for x in res {
                ids += x.result?.ids ?? []
                editor.print("\(x.url.lastPathComponent): " + (x.result?.summary ?? x.error ?? ""))
            }
            if !ids.isEmpty { editor.selection = Set(ids) }
        }
        var o = EngineObject()
        o.set("open", EngineJSON.strings(open))
        o.set("scripts", EngineJSON.strings(scripts))
        o.set("unsupported", EngineJSON.strings(unsupported))
        o.set("ids", EngineJSON.ints(ids))
        return o.json
    }

    // MARK: Sheet viewports (SheetView.swift)

    func sheetIndex(_ v: EngineJSON?) throws -> Int {
        if let v, !v.isNull { return try layoutIndex(v) }
        let ls = editor.doc.layouts
        guard !ls.isEmpty else { throw EngineError.failed("The drawing has no sheets.") }
        if let c = editor.doc.variable("CTAB"), let i = ls.firstIndex(where: { $0.name.caseInsensitiveCompare(c) == .orderedSame }) { return i }
        return 0
    }

    /// `sheet.viewports {layout?}`: viewports with lock state, polygonal clip, scale text and the sheet guide grid.
    func sheetViewports(_ p: EngineJSON) throws -> EngineJSON {
        let li = try sheetIndex(p["layout"])
        let doc = editor.doc
        let l = doc.layouts[li]
        let locked = EngineViewports.locked(doc, li)
        var vps: [EngineJSON] = []
        for (i, vp) in l.viewports.enumerated() {
            var o = EngineObject()
            o.set("index", i)
            o.set("rect", EngineDrawJSON.rect(BBox2(min: vp.origin, max: vp.origin + vp.size)))
            o.set("scale", vp.scale)
            o.set("ratioText", EngineViewports.ratioText(vp.scale, units: doc.units))
            o.set("view", vp.view.rawValue)
            o.set("level", vp.level.map { EngineJSON.int($0) } ?? .null)
            o.set("title", vp.title)
            o.set("locked", locked.contains(i))
            if let c = EngineViewports.clip(doc, li, i) { o.set("clip", EngineDrawJSON.points(c)) }
            o.set("modelWindow", EngineDrawJSON.rect(EngineViewports.modelWindow(vp)))
            vps.append(o.json)
        }
        var o = EngineObject()
        o.set("layout", l.name)
        o.set("index", li)
        var paper = EngineObject()
        paper.set("name", l.paper.name)
        paper.set("width", l.paper.width)
        paper.set("height", l.paper.height)
        o.set("paper", paper.json)
        o.set("grid", EngineViewports.gridSpacing(doc, l.name))
        o.set("viewports", EngineJSON.array(vps))
        return o.json
    }

    /// `sheet.viewport {layout?, index, op, …}`: `move {origin:[x,y]}` ("Move Viewport", snapped to the sheet guide grid),
    /// `remove` ("Remove Viewport"), `lock` / `unlock`, `scale {ratio}` ("Viewport Scale"), `removeClip`, `clip {points}`,
    /// `center {center}` (pan the view inside). Locked viewports refuse move / scale / remove / clip changes.
    func sheetViewportEdit(_ p: EngineJSON) throws -> EngineJSON {
        let li = try sheetIndex(p["layout"])
        guard let vi = p["index"]?.intValue, editor.doc.layouts[li].viewports.indices.contains(vi) else { throw EngineError.params("missing or unknown viewport 'index'") }
        let op = try string(p, "op").lowercased()
        let isLocked = EngineViewports.isLocked(editor.doc, li, vi)
        let guarded: Set<String> = ["move", "remove", "scale", "removeclip", "clip", "center"]
        if isLocked && guarded.contains(op) {
            editor.print("The viewport is locked (VPLOCK Off to unlock).")
            throw EngineError.failed("The viewport is locked (VPLOCK Off to unlock).")
        }
        switch op {
        case "move":
            let q = points(.array([p["origin"] ?? .null]))
            guard let o0 = q.first else { throw EngineError.params("missing 'origin'") }
            let s = EngineViewports.gridSpacing(editor.doc, editor.doc.layouts[li].name)
            let o = s > 0 ? Vec2((o0.x / s).rounded() * s, (o0.y / s).rounded() * s) : o0
            editor.transaction("Move Viewport") { d in
                if d.layouts.indices.contains(li), d.layouts[li].viewports.indices.contains(vi) { d.layouts[li].viewports[vi].origin = o }
            }
        case "remove":
            editor.transaction("Remove Viewport") { d in
                guard d.layouts[li].viewports.indices.contains(vi) else { return }
                d.layouts[li].viewports.remove(at: vi)
                EngineViewports.removed(&d, li, vi)
            }
        case "lock", "unlock":
            let on = op == "lock"
            editor.transaction(on ? "Lock Viewport" : "Unlock Viewport") { d in EngineViewports.setLocked(&d, li, vi, on) }
        case "scale":
            guard let ratio = p["ratio"]?.doubleValue, ratio > 0 else { throw EngineError.params("missing 'ratio'") }
            let scale = ratio / editor.doc.units.mm
            editor.transaction("Viewport Scale") { d in
                guard d.layouts[li].viewports.indices.contains(vi) else { return }
                var vp = d.layouts[li].viewports[vi]
                let old = vp.scale
                vp.scale = scale
                vp.size = vp.size * (old / scale)
                d.layouts[li].viewports[vi] = vp
            }
        case "removeclip":
            editor.transaction("Remove Clip") { d in EngineViewports.setClip(&d, li, vi, nil) }
        case "clip":
            let pts = points(p["points"])
            guard pts.count >= 3 else { throw EngineError.params("a clip boundary needs at least 3 points") }
            editor.transaction("Clip Viewport") { d in EngineViewports.setClip(&d, li, vi, pts) }
        case "center":
            guard let c = points(.array([p["center"] ?? .null])).first else { throw EngineError.params("missing 'center'") }
            editor.transaction("Pan Viewport") { d in d.layouts[li].viewports[vi].viewCenter = c }
        default:
            throw EngineError.params("unknown op '\(op)' (move, remove, lock, unlock, scale, removeClip, clip, center)")
        }
        var q = EngineObject()
        q.set("layout", .int(li))
        return try sheetViewports(q.json)
    }
}
