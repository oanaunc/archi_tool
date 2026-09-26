// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import AppKit
import ArchiCore

// Logic behind the navigation / selection / sheet additions of the app (APP, SEL, SHT, VIS). Everything here is
// UI-independent enough to be exercised by AppSelfTests.

// MARK: - Chained walls (SEL-022)

/// Walls joined end to end (Tab over a wall selects the whole chain, like Revit).
enum WallChain {
    /// The chain containing `start`: walls on the same level whose end points meet (within `tolerance`, or half the
    /// thicker wall when that is larger) or whose end lies on the other wall's axis (T-junction). Sorted ids.
    static func ids(from start: EntityID, doc: ArchiDocument, tolerance: Double = 1) -> [EntityID] {
        guard let first = doc.element(start), case .wall = first.geometry else { return [] }
        let walls: [(EntityID, WallGeom)] = doc.elements.compactMap { el in
            guard el.level == first.level, case .wall(let w) = el.geometry else { return nil }
            return (el.id, w)
        }
        func touches(_ a: WallGeom, _ b: WallGeom) -> Bool {
            let tol = tolerance
            for p in [a.start, a.end] {
                for q in [b.start, b.end] where p.distance(to: q) <= tol { return true }
                if pointOnSegment(p, b.start, b.end, tol) { return true }
            }
            for q in [b.start, b.end] where pointOnSegment(q, a.start, a.end, tol) { return true }
            return false
        }
        var seen: Set<EntityID> = [start], queue = [start]
        while let id = queue.popLast() {
            guard let w = walls.first(where: { $0.0 == id })?.1 else { continue }
            for (oid, ow) in walls where !seen.contains(oid) && touches(w, ow) { seen.insert(oid); queue.append(oid) }
        }
        return seen.sorted()
    }

    static func pointOnSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ tol: Double) -> Bool {
        let ab = b - a, l2 = ab.lengthSquared
        guard l2 > 1e-18 else { return p.distance(to: a) <= tol }
        let t = (p - a).dot(ab) / l2
        guard t >= -1e-9, t <= 1 + 1e-9 else { return false }
        return p.distance(to: a + ab * t) <= tol
    }
}

// MARK: - Grip modes on the selection (SEL-034 / SEL-038)

/// Move / Rotate / Scale / Mirror grip modes act on the whole selection about the hot grip (base point); Copy keeps
/// the originals. Stretch is handled per object by the core grip editor.
@MainActor
enum GripModeEdit {
    static let keywords: [String: GripMode] = ["ST": .stretch, "STRETCH": .stretch, "MO": .move, "MOVE": .move, "RO": .rotate, "ROTATE": .rotate,
                                               "SC": .scale, "SCALE": .scale, "MI": .mirror, "MIRROR": .mirror]

    /// Reference length for drag scaling: half the larger side of the selection bounds (dragging that far = factor 1).
    static func reference(_ ids: [EntityID], doc: ArchiDocument) -> Double {
        var b = BBox2.empty
        for id in ids {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            else if let el = doc.element(id) { for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) } }
        }
        return b.isEmpty ? 1 : max(max(b.width, b.height) / 2, 1e-6)
    }

    /// Transform of a typed value in a grip mode: Move = distance toward the cursor, Rotate = degrees, Scale = factor.
    static func typedTransform(_ mode: GripMode, base: Vec2, cursor: Vec2, value: Double) -> Transform2D? {
        switch mode {
        case .move:
            let d = (cursor - base).normalized
            return d == .zero ? .translation(Vec2(value, 0)) : .translation(d * value)
        case .rotate: return .rotation(rad(value), around: base)
        case .scale: return value > 1e-12 ? .translation(base) * .scale(value, value) * .translation(-base) : nil
        case .mirror, .stretch: return nil
        }
    }

    /// Applies a transform to the objects (copies with `copy`) as one undo step. Locked objects are skipped. Returns the ids
    /// changed or created.
    @discardableResult
    static func apply(_ ed: Editor, ids: [EntityID], _ t: Transform2D, copy: Bool, label: String) -> [EntityID] {
        let targets = ed.expandGroups(ids).filter { ed.isSelectable($0) }
        guard !targets.isEmpty else { return [] }
        var out: [EntityID] = []
        ed.transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) {
                    let g = GeometryOps.transform(d.entities[i].geometry, t)
                    if copy { var n = d.entities[i]; n.geometry = g; out.append(d.add(n)) } else { d.entities[i].geometry = g; out.append(id) }
                } else if let i = d.elementIndex(id) {
                    let g = CommandHelpers.transform(d.elements[i].geometry, t)
                    if copy { var n = d.elements[i]; n.id = d.allocateID(); n.geometry = g; d.elements.append(n); out.append(n.id) }
                    else { d.elements[i].geometry = g; out.append(id) }
                }
            }
        }
        return out
    }
}

// MARK: - Shortcut menus (APP-023)

enum ShortcutMenu {
    enum Action: Equatable { case run(String), properties, quickProperties, deselect, selectAll, undo, redo, zoomExtents, repeatLast, separator, submenu(String, [Item]) }
    struct Item: Equatable { var title: String; var action: Action; var enabled = true }

    /// Items of the canvas right-click menu: with a selection the edit commands come first (AutoCAD "Edit" menu).
    static func items(hasSelection: Bool, lastCommand: String?, recentInput: [String], canUndo: Bool, canRedo: Bool, undoLabel: String? = nil, redoLabel: String? = nil) -> [Item] {
        var out: [Item] = [Item(title: lastCommand.map { "Repeat \($0)" } ?? "Repeat", action: .repeatLast, enabled: lastCommand != nil)]
        var recent: [String] = []
        for r in recentInput.reversed() where !recent.contains(r) && !r.isEmpty { recent.append(r); if recent.count == 8 { break } }
        out.append(Item(title: "Recent Input", action: .submenu("Recent Input", recent.map { Item(title: $0, action: .run($0)) }), enabled: !recent.isEmpty))
        out.append(Item(title: "", action: .separator))
        if hasSelection {
            for (t, c) in [("Move", "MOVE"), ("Copy Selection", "COPY"), ("Rotate", "ROTATE"), ("Scale", "SCALE"), ("Mirror", "MIRROR"), ("Erase", "ERASE")] {
                out.append(Item(title: t, action: .run(c)))
            }
            out.append(Item(title: "", action: .separator))
            out.append(Item(title: "Isolate Objects", action: .run("ISOLATEOBJECTS")))
            out.append(Item(title: "Select Similar", action: .run("SELECTSIMILAR")))
            out.append(Item(title: "Deselect All", action: .deselect))
        } else {
            out.append(Item(title: "Pan", action: .run("PAN")))
            out.append(Item(title: "Zoom Window", action: .run("ZOOM W")))
            out.append(Item(title: "Zoom Extents", action: .zoomExtents))
            out.append(Item(title: "Select All", action: .selectAll))
        }
        out.append(Item(title: "Quick Select…", action: .run("QSELECTDIALOG")))
        out.append(Item(title: "", action: .separator))
        out.append(Item(title: undoLabel.map { "Undo \($0)" } ?? "Undo", action: .undo, enabled: canUndo))
        out.append(Item(title: redoLabel.map { "Redo \($0)" } ?? "Redo", action: .redo, enabled: canRedo))
        out.append(Item(title: "", action: .separator))
        out.append(Item(title: "Quick Properties", action: .quickProperties, enabled: hasSelection))
        out.append(Item(title: "Properties", action: .properties))
        return out
    }
}

// MARK: - Contextual ribbon tabs (APP-015)

struct ContextTab: Equatable {
    var title: String
    var items: [CmdItem]
}

enum ContextualRibbon {
    private static func c(_ t: String, _ s: String, _ n: String...) -> CmdItem { CmdItem(title: t, symbol: s, names: n) }
    private static let common = [c("Move", "arrow.up.and.down.and.arrow.left.and.right", "MOVE"), c("Copy", "plus.square.on.square", "COPY"),
                                 c("Rotate", "arrow.clockwise", "ROTATE"), c("Mirror", "arrow.left.and.right.righttriangle.left.righttriangle.right", "MIRROR"),
                                 c("Match Props", "paintbrush.pointed", "MATCHPROP"), c("Select Similar", "square.on.square.intersection.dashed", "SELECTSIMILAR")]

    /// Category of the selection: all objects of one kind, or nil for mixed / empty selections.
    static func category(_ doc: ArchiDocument, _ sel: Set<EntityID>) -> String? {
        guard !sel.isEmpty else { return nil }
        var kinds: Set<String> = []
        for id in sel {
            if let e = doc.entity(id) {
                switch e.geometry {
                case .text: kinds.insert("Text"); case .dimension: kinds.insert("Dimension"); case .hatch: kinds.insert("Hatch")
                case .insert: kinds.insert("Block Reference"); case .polyline: kinds.insert("Polyline"); case .table: kinds.insert("Table")
                case .image: kinds.insert("Image"); case .leader: kinds.insert("Leader"); case .solid: kinds.insert("Solid")
                default: kinds.insert("Geometry")
                }
            } else if let el = doc.element(id) {
                switch el.geometry {
                case .wall, .curtainWall: kinds.insert("Wall"); case .opening(let o): kinds.insert(o.kind == .window ? "Window" : "Door")
                case .slab: kinds.insert("Floor"); case .roof: kinds.insert("Roof"); case .stair: kinds.insert("Stair"); case .space: kinds.insert("Room")
                case .column: kinds.insert("Column"); case .beam: kinds.insert("Beam"); default: kinds.insert("Element")
                }
            }
            if kinds.count > 1 { return nil }
        }
        return kinds.first
    }

    /// The contextual tab for a selection ("Modify Wall", "Text Editor", "Hatch Editor", …), nil when none applies.
    static func tab(_ doc: ArchiDocument, _ sel: Set<EntityID>) -> ContextTab? {
        guard let k = category(doc, sel) else { return nil }
        let specific: [CmdItem]
        let title: String
        switch k {
        case "Wall":
            title = "Modify Wall"
            specific = [c("Door", "door.left.hand.open", "DOOR"), c("Window", "window.vertical.closed", "WINDOW"), c("Opening", "rectangle.dashed", "OPENING", "WALLOPENING"),
                        c("Dimension Walls", "rectangle.split.3x1", "AUTODIMWALLS"), c("Offset", "square.on.square.dashed", "OFFSET"), c("Properties", "slider.horizontal.3", "PROPERTIES")]
        case "Door", "Window":
            title = "Modify \(k)"
            specific = [c("Properties", "slider.horizontal.3", "PROPERTIES"), c("Set Property", "slider.horizontal.below.rectangle", "SETPROP"), c("Opening Parts", "door.left.hand.closed", "OPENINGPARTS")]
        case "Text":
            title = "Text Editor"
            specific = [c("Edit Text", "pencil", "TEXTEDIT"), c("Text Style", "textformat", "TEXTSTYLE"), c("Justify", "text.justify", "JUSTIFYTEXT"),
                        c("Scale Text", "textformat.size", "SCALETEXT"), c("Spelling", "textformat.abc.dottedunderline", "SPELL"), c("Find & Replace", "magnifyingglass", "FIND")]
        case "Hatch":
            title = "Hatch Editor"
            specific = [c("Edit Hatch", "square.grid.3x3.fill", "HATCHEDIT"), c("Recreate Boundary", "square.dashed", "HATCHGENERATEBOUNDARY"), c("Send to Back", "square.3.layers.3d.down.right", "HATCHTOBACK")]
        case "Dimension":
            title = "Dimension"
            specific = [c("Edit Dimension", "pencil", "DIMEDIT"), c("Move Text", "text.cursor", "DIMTEDIT"), c("Dimension Style", "ruler", "DIMSTYLE"),
                        c("Break", "scissors", "DIMBREAK"), c("Space", "arrow.up.and.down.text.horizontal", "DIMSPACE"), c("Reassociate", "link", "DIMREASSOCIATE")]
        case "Block Reference":
            title = "Block Reference"
            specific = [c("Edit Attributes", "character.textbox", "ATTEDIT"), c("Replace Block", "arrow.triangle.swap", "BLOCKREPLACE"), c("Count", "number.circle", "BCOUNT"), c("Explode", "burst", "EXPLODE")]
        case "Polyline":
            title = "Polyline"
            specific = [c("Edit Polyline", "point.topleft.down.curvedto.point.bottomright.up", "PEDIT"), c("Join", "link", "JOIN"), c("Reverse", "arrow.left.arrow.right", "REVERSE"), c("Explode", "burst", "EXPLODE")]
        case "Table":
            title = "Table Cell"
            specific = [c("Edit Table", "tablecells", "TABLEEDIT"), c("Export Table", "square.and.arrow.up", "TABLEEXPORT")]
        case "Room":
            title = "Modify Room"
            specific = [c("Room Finishes", "square.grid.3x3.topleft.filled", "ROOMFINISH"), c("Color Fill", "paintbrush", "COLORFILL"), c("Properties", "slider.horizontal.3", "PROPERTIES")]
        default:
            title = "Modify \(k)"
            specific = [c("Properties", "slider.horizontal.3", "PROPERTIES")]
        }
        return ContextTab(title: title, items: specific + common)
    }
}

// MARK: - Model / layout tabs (APP-013)

@MainActor
enum LayoutTabs {
    /// "Model" followed by every sheet, in sheet order.
    static func titles(_ doc: ArchiDocument) -> [String] { ["Model"] + doc.layouts.map(\.name) }
    /// Index of the shown tab: 0 = model, i + 1 = layout i.
    static func current(_ model: AppModel) -> Int {
        model.mode == .sheet && model.doc.layouts.indices.contains(model.activeLayout) ? model.activeLayout + 1 : 0
    }
    /// Shows a tab; the choice is kept in CTAB (saved with the drawing, restored on open).
    static func select(_ model: AppModel, _ index: Int) {
        if index <= 0 || !model.doc.layouts.indices.contains(index - 1) {
            if model.mode == .sheet { model.mode = .plan }
        } else {
            model.activeLayout = index - 1
            model.mode = .sheet
        }
        model.syncCurrentTab()
        model.revision &+= 1
    }
    /// Re-opens the tab stored in CTAB (called after a drawing is opened).
    static func restore(_ model: AppModel) {
        guard let t = model.doc.variable("CTAB"), let i = model.doc.layouts.firstIndex(where: { $0.name.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        model.activeLayout = i
        model.mode = .sheet
    }
    /// Adds a sheet (next free "Layout n" name) and shows it.
    static func addLayout(_ model: AppModel) {
        var n = model.doc.layouts.count + 1
        while model.doc.layouts.contains(where: { $0.name == "Layout\(n)" }) { n += 1 }
        let name = "Layout\(n)"
        model.editor.transaction("New Layout") { $0.layouts.append(ArchiCore.Layout(name: name)) }
        select(model, model.doc.layouts.count)
    }
}

// MARK: - Progress of long operations (APP-044)

/// Long operations report progress here; the status bar shows the active ones with a Cancel button.
@MainActor
final class ProgressCenter: ObservableObject {
    static let shared = ProgressCenter()
    struct Job: Identifiable, Equatable { let id: Int; var title: String; var fraction: Double?; var cancelled = false; var detail = "" }
    @Published private(set) var jobs: [Job] = []
    private var next = 1

    @discardableResult func begin(_ title: String, indeterminate: Bool = false) -> Int {
        let id = next; next += 1
        jobs.append(Job(id: id, title: title, fraction: indeterminate ? nil : 0))
        return id
    }
    func update(_ id: Int, fraction: Double?, detail: String? = nil) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].fraction = fraction.map { min(max($0, 0), 1) }
        if let detail { jobs[i].detail = detail }
    }
    func cancel(_ id: Int) { if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].cancelled = true } }
    func isCancelled(_ id: Int) -> Bool { jobs.first { $0.id == id }?.cancelled ?? true }
    func end(_ id: Int) { jobs.removeAll { $0.id == id } }
    var current: Job? { jobs.last }

    /// Lets the window repaint and the Cancel button be clicked during a synchronous loop on the main thread.
    static func pumpEvents() {
        guard let app = NSApp as NSApplication? else { return }
        while let e = app.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { app.sendEvent(e) }
        RunLoop.main.run(mode: .default, before: Date())
    }

    /// Runs `count` steps, reporting progress and yielding to the run loop between steps so the Cancel button works.
    /// Returns the number of steps completed (less than `count` when cancelled).
    @discardableResult
    func run(_ title: String, count: Int, step: @MainActor (Int) async throws -> Void) async rethrows -> Int {
        let id = begin(title)
        defer { end(id) }
        for i in 0..<count {
            if isCancelled(id) { return i }
            update(id, fraction: Double(i) / Double(max(count, 1)), detail: "\(i + 1) of \(count)")
            try await step(i)
            await Task.yield()
        }
        update(id, fraction: 1)
        return count
    }
}

// MARK: - Annotation scale (APP-042)

@MainActor
enum AnnotationScaleControl {
    static func current(_ doc: ArchiDocument) -> String { doc.variable("CANNOSCALE") ?? "1:1" }
    static func list(_ doc: ArchiDocument) -> [String] {
        var l = Annotative.scaleList(doc)
        let c = current(doc)
        if !l.contains(c) { l.insert(c, at: 0) }
        return l
    }
    /// Sets CANNOSCALE (one undo step) and refreshes the drawing; false for an unreadable scale.
    @discardableResult static func set(_ model: AppModel, _ scale: String) -> Bool {
        guard Annotative.factor(scale) != nil else { return false }
        model.editor.transaction("Annotation Scale") { $0.setVariable("CANNOSCALE", scale) }
        model.canvas?.invalidateCache()
        model.revision &+= 1
        return true
    }
}

// MARK: - Object inspector (APP-033)

enum ObjectInspector {
    /// Read-only dump of every stored value of an object: ids, type, layer and style, properties and raw geometry JSON.
    static func report(_ id: EntityID, doc: ArchiDocument) -> [(String, String)] {
        var out: [(String, String)] = [("ID", "#\(id)")]
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let e = doc.entity(id) {
            out.append(("GUID", IFCExporter.guid("entity:\(id)")))
            out += [("Type", e.typeName), ("Layer", e.layer), ("Color", e.color.text), ("Linetype", e.linetype ?? "ByLayer"),
                    ("Lineweight", e.lineweight.map { fmt($0) + " mm" } ?? "ByLayer")]
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            if !b.isEmpty { out.append(("Extents", "(\(fmt(b.min.x, 2)), \(fmt(b.min.y, 2))) – (\(fmt(b.max.x, 2)), \(fmt(b.max.y, 2)))")) }
            for (k, v) in e.props.sorted(by: { $0.key < $1.key }) { out.append(("prop." + k, v)) }
            if let d = try? enc.encode(e.geometry), let s = String(data: d, encoding: .utf8) { out.append(("Geometry", s)) }
        } else if let el = doc.element(id) {
            let g = el.props["ifcGuid"].flatMap { IFCExporter.isValidGuid($0) ? $0 : nil } ?? IFCExporter.guid("element:\(id)")
            out.append(("GUID", g))
            out += [("Type", el.typeName), ("Name", el.name), ("Level", doc.level(el.level)?.name ?? "\(el.level)"), ("Layer", el.layer), ("Material", el.material ?? "—")]
            for (k, v) in el.props.sorted(by: { $0.key < $1.key }) { out.append(("prop." + k, v)) }
            if let d = try? enc.encode(el.geometry), let s = String(data: d, encoding: .utf8) { out.append(("Geometry", s)) }
        } else { return [] }
        return out
    }
    static func text(_ id: EntityID, doc: ArchiDocument) -> String { report(id, doc: doc).map { "\($0.0): \($0.1)" }.joined(separator: "\n") }
}

// MARK: - Design center (APP-031)

/// Browses another drawing's named content and copies definitions into the current drawing (ADCENTER).
enum DesignCenter {
    enum Kind: String, CaseIterable, Identifiable { case blocks = "Blocks", layers = "Layers", linetypes = "Linetypes", textStyles = "Text Styles", dimStyles = "Dimension Styles", materials = "Materials"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .blocks: return "square.on.square.dashed"; case .layers: return "square.3.layers.3d"; case .linetypes: return "line.3.horizontal"
            case .textStyles: return "textformat"; case .dimStyles: return "ruler"; case .materials: return "paintpalette" }
        }
    }

    static func names(_ k: Kind, in doc: ArchiDocument) -> [String] {
        switch k {
        case .blocks: return doc.blocks.keys.filter { !$0.hasPrefix("*") }.sorted()
        case .layers: return doc.layers.map(\.name)
        case .linetypes: return doc.linetypes.map(\.name)
        case .textStyles: return doc.textStyles.map(\.name)
        case .dimStyles: return doc.dimStyles.map(\.name)
        case .materials: return doc.materials.map(\.name)
        }
    }

    /// Copies the named definitions (blocks bring nested blocks and their layers). Existing names are kept unchanged.
    /// Returns the names actually added.
    @discardableResult
    static func copy(_ k: Kind, _ names: [String], from src: ArchiDocument, into dst: inout ArchiDocument) -> [String] {
        var added: [String] = []
        func has<T>(_ list: [T], _ n: String, _ name: (T) -> String) -> Bool { list.contains { name($0).caseInsensitiveCompare(n) == .orderedSame } }
        switch k {
        case .blocks:
            var todo = names, seen: Set<String> = []
            while let n = todo.popLast() {
                guard !seen.contains(n), let b = src.blocks[n] else { continue }
                seen.insert(n)
                for e in b.entities {
                    if case .insert(let i) = e.geometry { todo.append(i.block) }
                    if dst.layer(named: e.layer) == nil, let l = src.layer(named: e.layer) { dst.layers.append(l) }
                    if let lt = e.linetype, !has(dst.linetypes, lt, \.name), let def = src.linetypes.first(where: { $0.name.caseInsensitiveCompare(lt) == .orderedSame }) { dst.linetypes.append(def) }
                }
                if dst.blocks[n] == nil { dst.blocks[n] = b; added.append(n) }
            }
        case .layers:
            for n in names where dst.layer(named: n) == nil { if let l = src.layer(named: n) { dst.layers.append(l); added.append(l.name) } }
        case .linetypes:
            for n in names where !has(dst.linetypes, n, \.name) { if let l = src.linetypes.first(where: { $0.name == n }) { dst.linetypes.append(l); added.append(n) } }
        case .textStyles:
            for n in names where !has(dst.textStyles, n, \.name) { if let s = src.textStyles.first(where: { $0.name == n }) { dst.textStyles.append(s); added.append(n) } }
        case .dimStyles:
            for n in names where !has(dst.dimStyles, n, \.name) { if let s = src.dimStyles.first(where: { $0.name == n }) { dst.dimStyles.append(s); added.append(n) } }
        case .materials:
            for n in names where dst.material(n) == nil { if let m = src.material(n) { dst.materials.append(m); added.append(n) } }
        }
        return added
    }
}

// MARK: - Sheets: viewport scale, alignment, maximise, clip, guide grid, placeholders, custom fields, page setup import

enum SheetTools {
    // Viewport maths (SHT-005, SHT-009).

    /// Paper point (mm) of a model point seen through a viewport.
    static func paperPoint(_ p: Vec2, in vp: Viewport) -> Vec2 { vp.origin + vp.size / 2 + (p - vp.viewCenter) / max(vp.scale, 1e-12) }
    /// Model point under a paper point of a viewport.
    static func modelPoint(_ q: Vec2, in vp: Viewport) -> Vec2 { vp.viewCenter + (q - vp.origin - vp.size / 2) * vp.scale }
    /// Model window shown by a viewport.
    static func modelWindow(_ vp: Viewport) -> BBox2 {
        BBox2(min: vp.viewCenter - vp.size * (vp.scale / 2), max: vp.viewCenter + vp.size * (vp.scale / 2))
    }
    /// Viewport scale (model units per paper mm) for a ratio "1:n" in real millimetres.
    static func scale(ratio n: Double, units: Units) -> Double { n / units.mm }

    enum Alignment: String { case horizontal = "Horizontal", vertical = "Vertical" }
    /// MVSETUP Align: pans viewport `j` so that model point `pj` lines up with model point `pi` of viewport `i` on paper.
    static func align(_ layout: inout ArchiCore.Layout, base i: Int, basePoint pi: Vec2, other j: Int, otherPoint pj: Vec2, _ a: Alignment) -> Bool {
        guard layout.viewports.indices.contains(i), layout.viewports.indices.contains(j), i != j else { return false }
        let target = paperPoint(pi, in: layout.viewports[i])
        var vj = layout.viewports[j]
        let now = paperPoint(pj, in: vj)
        let delta = target - now
        let paperShift = a == .horizontal ? Vec2(0, delta.y) : Vec2(delta.x, 0)
        vj.viewCenter = vj.viewCenter - paperShift * vj.scale
        layout.viewports[j] = vj
        return true
    }

    // Maximised viewports (SHT-007).

    /// After editing the model through a maximised viewport, VPMIN keeps the new view centre (unless locked).
    static func restoreCenter(_ vp: inout Viewport, planCenter: Vec2) { vp.viewCenter = planCenter }

    // Viewport clipping / polygonal viewports (SHT-004, SHT-008). Stored per sheet and viewport as paper points.

    static func clipKey(_ layout: String, _ i: Int) -> String { "VPCLIP:\(layout.uppercased()):\(i)" }
    static func clip(_ doc: ArchiDocument, layout: String, viewport i: Int) -> [Vec2]? {
        guard let s = doc.variable(clipKey(layout, i)) else { return nil }
        let pts = s.split(separator: ";").compactMap { p -> Vec2? in
            let c = p.split(separator: ",").compactMap { Double($0) }
            return c.count == 2 ? Vec2(c[0], c[1]) : nil
        }
        return pts.count >= 3 ? pts : nil
    }
    /// Sets (or with nil / fewer than 3 points removes) a viewport's clip boundary; the viewport frame is fitted to it.
    static func setClip(_ doc: inout ArchiDocument, layoutIndex li: Int, viewport i: Int, _ pts: [Vec2]?) {
        guard doc.layouts.indices.contains(li), doc.layouts[li].viewports.indices.contains(i) else { return }
        let key = clipKey(doc.layouts[li].name, i)
        guard let pts, pts.count >= 3, abs(GeometryOps.signedArea(pts)) > 1e-9 else { doc.variables[key] = nil; return }
        doc.variables[key] = pts.map { "\(fmt($0.x, 4)),\(fmt($0.y, 4))" }.joined(separator: ";")
        // Keep the same model point under the frame centre while the frame shrinks/grows to the boundary.
        var vp = doc.layouts[li].viewports[i]
        let b = BBox2(points: pts)
        let newCenterModel = modelPoint(b.center, in: vp)
        vp.origin = b.min; vp.size = Vec2(b.width, b.height); vp.viewCenter = newCenterModel
        doc.layouts[li].viewports[i] = vp
    }
    /// Renumbers clip boundaries after viewport `i` of a sheet was removed.
    static func viewportRemoved(_ doc: inout ArchiDocument, layoutIndex li: Int, viewport i: Int) {
        guard doc.layouts.indices.contains(li) else { return }
        let name = doc.layouts[li].name
        doc.variables[clipKey(name, i)] = nil
        let old = doc.layouts[li].viewports.count + 1
        guard i + 1 < old else { return }
        for j in (i + 1)..<old { doc.variables[clipKey(name, j - 1)] = doc.variables[clipKey(name, j)]; doc.variables[clipKey(name, j)] = nil }
    }
    /// Adds a polygonal viewport (MVIEW Polygonal) showing `center` at `scale`.
    @discardableResult
    static func addPolygonal(_ doc: inout ArchiDocument, layoutIndex li: Int, _ pts: [Vec2], center: Vec2, scale: Double, level: Int?) -> Int? {
        guard doc.layouts.indices.contains(li), pts.count >= 3 else { return nil }
        let b = BBox2(points: pts)
        doc.layouts[li].viewports.append(Viewport(origin: b.min, size: Vec2(b.width, b.height), viewCenter: center, scale: scale, level: level))
        let i = doc.layouts[li].viewports.count - 1
        setClip(&doc, layoutIndex: li, viewport: i, pts)
        return i
    }

    // Guide grid (SHT-011): spacing in paper mm per sheet, 0 = off.

    static func gridKey(_ layout: String) -> String { "SHEETGRID:\(layout.uppercased())" }
    static func gridSpacing(_ doc: ArchiDocument, layout: String) -> Double { doc.variable(gridKey(layout)).flatMap(Double.init).map { max($0, 0) } ?? 0 }
    static func snap(_ p: Vec2, spacing s: Double) -> Vec2 { s > 0 ? Vec2((p.x / s).rounded() * s, (p.y / s).rounded() * s) : p }

    // Placeholder sheets (SHT-020): listed in the sheet set and index, never plotted or published.

    static let placeholderKey = "placeholder"
    static func isPlaceholder(_ l: ArchiCore.Layout) -> Bool { l.titleBlock[placeholderKey] == "1" }
    static func setPlaceholder(_ doc: inout ArchiDocument, _ i: Int, _ on: Bool) {
        guard doc.layouts.indices.contains(i) else { return }
        doc.layouts[i].titleBlock[placeholderKey] = on ? "1" : nil
    }
    /// Sheets that plot / publish.
    static func publishable(_ doc: ArchiDocument) -> [Int] { doc.layouts.indices.filter { !isPlaceholder(doc.layouts[$0]) } }

    // Custom sheet and project fields (SHT-021). Project fields: variables "PROJFIELD:<label>"; sheet fields: title block
    // keys "custom:<label>" (override the project value on that sheet).

    static let projectPrefix = "PROJFIELD:"
    static let sheetPrefix = "custom:"
    static func projectFields(_ doc: ArchiDocument) -> [(String, String)] {
        doc.variables.filter { $0.key.hasPrefix(projectPrefix) }.map { (String($0.key.dropFirst(projectPrefix.count)), $0.value) }.sorted { $0.0 < $1.0 }
    }
    static func setProjectField(_ doc: inout ArchiDocument, _ label: String, _ value: String?) {
        let k = projectPrefix + label.uppercased()
        doc.variables[k] = (value?.isEmpty ?? true) ? nil : value
    }
    static func setSheetField(_ doc: inout ArchiDocument, _ i: Int, _ label: String, _ value: String?) {
        guard doc.layouts.indices.contains(i) else { return }
        doc.layouts[i].titleBlock[sheetPrefix + label.uppercased()] = (value?.isEmpty ?? true) ? nil : value
    }
    /// Fields shown on a sheet: project fields overridden by the sheet's own, sorted by label.
    static func fields(_ doc: ArchiDocument, layout: ArchiCore.Layout) -> [(String, String)] {
        var d: [String: String] = [:]
        for (k, v) in projectFields(doc) { d[k] = v }
        for (k, v) in layout.titleBlock where k.hasPrefix(sheetPrefix) { d[String(k.dropFirst(sheetPrefix.count))] = v }
        return d.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // Page setup import (SHT-040).

    /// Named page setups of a drawing: "*Model*" and one per sheet that has its own settings.
    static func pageSetups(_ doc: ArchiDocument) -> [(String, PageSetup)] {
        var out: [(String, PageSetup)] = []
        if doc.variables[PageSetup.modelKey] != nil { out.append(("*Model*", PageSetup.load(doc, layoutIndex: nil))) }
        for (i, l) in doc.layouts.enumerated() where doc.variables[PageSetup.key(doc, layoutIndex: i)] != nil { out.append((l.name, PageSetup.load(doc, layoutIndex: i))) }
        return out
    }
    /// Applies a page setup to sheets (nil index = model space). Paper size comes along for sheets when `paper` is given.
    static func applyPageSetup(_ ps: PageSetup, to doc: inout ArchiDocument, layouts: [Int?], paper: PaperSize? = nil) {
        for li in layouts {
            ps.store(in: &doc, layoutIndex: li)
            if let li, let paper, doc.layouts.indices.contains(li) { doc.layouts[li].paper = paper }
        }
    }
}

// MARK: - 2D view twist (VIS-011)

enum ViewTwist {
    static let variable = "VIEWTWIST"
    /// Stored plan view rotation in degrees (display only; model coordinates never change).
    static func degrees(_ doc: ArchiDocument) -> Double { doc.variable(variable).flatMap(Double.init) ?? 0 }
    static func normalized(_ d: Double) -> Double { var a = d.truncatingRemainder(dividingBy: 360); if a < 0 { a += 360 }; return a < 1e-9 || a > 360 - 1e-9 ? 0 : a }
}

// MARK: - Visual style names (VIS-025…VIS-031)

enum VisualStyleNames {
    /// Maps command keywords and menu titles ("Hidden", "2dwireframe", "Xray", "shadedwithEdges", "Conceptual") to the
    /// styles the 3D builder implements.
    static func canonical(_ s: String) -> String { resolve(s) ?? "Shaded with Edges" }
    /// The built-in style a name or keyword denotes, nil when unknown.
    static func resolve(_ s: String) -> String? {
        let k = s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        switch k {
        case "wireframe", "2dwireframe", "3dwireframe", "wire": return "Wireframe"
        case "hidden", "hiddenline", "hide": return "Hidden Line"
        case "shaded", "flat", "gouraud", "shade": return "Shaded"
        case "shadedwithedges", "shadededges", "flatwithedges", "gouraudwithedges", "edges": return "Shaded with Edges"
        case "realistic", "textured", "materials": return "Realistic"
        case "xray", "transparent": return "X-Ray"
        case "conceptual", "consistentcolors", "consistentcolours", "consistent": return "Conceptual"
        case "sketchy", "sketch", "handdrawn", "hand": return "Sketchy"
        default: return Scene3DBuilder.visualStyles.first { $0.caseInsensitiveCompare(s) == .orderedSame }
        }
    }
}

// MARK: - Function keys (APP-055)

enum FunctionKeys {
    /// AutoCAD-compatible function keys: key code → (name, what it toggles / opens).
    static let table: [(key: String, code: UInt16, action: String)] = [
        ("F1", 122, "Help (the running command's page)"), ("F2", 120, "Command history panel"), ("F3", 99, "Object snap on/off"),
        ("F7", 98, "Grid display"), ("F8", 100, "Ortho mode"), ("F9", 101, "Grid snap"), ("F10", 109, "Polar tracking"),
        ("F11", 103, "Object snap tracking"), ("F12", 111, "Dynamic input"),
    ]
    static func name(_ code: UInt16) -> String? { table.first { $0.code == code }?.key }
}

extension BBox2 { var cgRect: CGRect { isEmpty ? .null : CGRect(x: min.x, y: min.y, width: width, height: height) } }

// MARK: - Flip controls of doors and windows (SEL-036)

/// Revit-style flip arrows shown on a selected door or window: one flips the facing (swing side), one the hand.
enum FlipControls {
    enum Kind: String { case facing, hand, wall }
    struct Control: Equatable { var id: EntityID; var kind: Kind; var point: Vec2; var direction: Vec2 }

    /// Controls of an opening; `gap` is the distance (model units) of the arrows from the wall face / opening edge.
    static func controls(_ el: BIMElement, doc: ArchiDocument, gap: Double) -> [Control] {
        guard case .opening(let o) = el.geometry, let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else { return [] }
        let dir = w.direction
        guard dir != .zero else { return [] }
        let c = w.centerStart + dir * o.offset
        let side: Double = o.flipFacing ? -1 : 1
        let n = dir.perp * side
        let facing = Control(id: el.id, kind: .facing, point: c + n * (w.thickness / 2 + gap), direction: n)
        guard o.kind == .door else { return [facing] }
        let h: Double = o.flipHand ? -1 : 1
        let hand = Control(id: el.id, kind: .hand, point: c + dir * (h * (o.width / 2 + gap)) - n * (w.thickness / 2 + gap), direction: dir * h)
        return [facing, hand]
    }

    /// Flip arrow of a wall: flips it about its location line (start and end swap; hosted openings keep their place).
    static func wallControl(_ el: BIMElement, gap: Double) -> Control? {
        guard case .wall(let w) = el.geometry, w.direction != .zero else { return nil }
        let mid = (w.centerStart + w.centerEnd) / 2
        let n = w.direction.perp
        return Control(id: el.id, kind: .wall, point: mid + n * (w.thickness / 2 + gap), direction: n)
    }
    static func flipWall(_ id: EntityID, doc: inout ArchiDocument) -> Bool {
        guard let i = doc.elementIndex(id), case .wall(var w) = doc.elements[i].geometry else { return false }
        let len = w.start.distance(to: w.end)
        swap(&w.start, &w.end)
        w.bulge = -w.bulge
        doc.elements[i].geometry = .wall(w)
        for j in doc.elements.indices { if case .opening(var o) = doc.elements[j].geometry, o.hostWall == id { o.offset = len - o.offset; o.flipFacing.toggle(); o.flipHand.toggle(); doc.elements[j].geometry = .opening(o) } }
        return true
    }

    /// Flips the opening (one undo step when called inside a transaction). Returns false for non-openings.
    @discardableResult
    static func apply(_ c: Control, doc: inout ArchiDocument) -> Bool {
        if c.kind == .wall { return flipWall(c.id, doc: &doc) }
        guard let i = doc.elementIndex(c.id), case .opening(var o) = doc.elements[i].geometry else { return false }
        switch c.kind { case .facing: o.flipFacing.toggle(); case .hand: o.flipHand.toggle(); case .wall: break }
        doc.elements[i].geometry = .opening(o)
        return true
    }
}

// MARK: - Paper sizes (SHT-002)

/// ISO A, ANSI and ARCH paper sizes (landscape, mm) plus custom sizes stored in the drawing ("CUSTOMPAPER:<name>" = "w,h").
enum PaperCatalog {
    static let iso: [PaperSize] = [("A4", 297, 210), ("A3", 420, 297), ("A2", 594, 420), ("A1", 841, 594), ("A0", 1189, 841)].map { PaperSize(name: $0.0, width: $0.1, height: $0.2) }
    static let ansi: [PaperSize] = [("ANSI A", 279.4, 215.9), ("ANSI B", 431.8, 279.4), ("ANSI C", 558.8, 431.8), ("ANSI D", 863.6, 558.8), ("ANSI E", 1117.6, 863.6)]
        .map { PaperSize(name: $0.0, width: $0.1, height: $0.2) }
    static let arch: [PaperSize] = [("ARCH A", 304.8, 228.6), ("ARCH B", 457.2, 304.8), ("ARCH C", 609.6, 457.2), ("ARCH D", 914.4, 609.6), ("ARCH E1", 1066.8, 762), ("ARCH E", 1219.2, 914.4)]
        .map { PaperSize(name: $0.0, width: $0.1, height: $0.2) }
    /// Built-in sizes: the core list first (A4…A0, Letter, Tabloid, ARCH D), then the other ANSI / ARCH sizes.
    static var builtIn: [PaperSize] {
        var out = PaperSize.standard
        for p in iso + ansi + arch where !out.contains(where: { $0.name == p.name }) { out.append(p) }
        return out
    }
    static let prefix = "CUSTOMPAPER:"
    static func custom(_ doc: ArchiDocument) -> [PaperSize] {
        doc.variables.filter { $0.key.hasPrefix(prefix) }.compactMap { k, v in
            let c = v.split(separator: ",").compactMap { Double($0) }
            return c.count == 2 ? PaperSize(name: String(k.dropFirst(prefix.count)), width: c[0], height: c[1]) : nil
        }.sorted { $0.name < $1.name }
    }
    static func all(_ doc: ArchiDocument) -> [PaperSize] { builtIn + custom(doc).filter { c in !builtIn.contains { $0.name == c.name } } }
    /// A size by name; "… portrait" names return the rotated size.
    static func find(_ name: String, doc: ArchiDocument? = nil) -> PaperSize? {
        let list = doc.map(all) ?? builtIn
        if let p = list.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return p }
        if name.lowercased().hasSuffix(" portrait"), let p = find(String(name.dropLast(" portrait".count)), doc: doc) {
            return PaperSize(name: p.name + " portrait", width: p.height, height: p.width)
        }
        return nil
    }
    /// Adds (or replaces) a custom size of 50–5000 mm per side. Nil for invalid input.
    @discardableResult
    static func addCustom(_ doc: inout ArchiDocument, name: String, width: Double, height: Double) -> PaperSize? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, (50...5000).contains(width), (50...5000).contains(height), !builtIn.contains(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { return nil }
        doc.variables[prefix + n] = "\(fmt(width, 3)),\(fmt(height, 3))"
        return PaperSize(name: n, width: width, height: height)
    }
}

// MARK: - Lineweight display scale (LAY-027)

/// Screen scale of displayed lineweights (Lineweight Settings ▸ Adjust Display Scale); plots always use true widths.
enum LineweightDisplay {
    static let key = "lwDisplayScale"
    static var scale: Double {
        get { let v = UserDefaults.standard.double(forKey: key); return v > 0 ? v : 1 }
        set { UserDefaults.standard.set(min(max(newValue, 0.1), 5), forKey: key) }
    }
}

// MARK: - Views dragged onto sheets (SHT-010)

/// Drag payload of a project-browser view and its placement as a sheet viewport at the view's scale.
enum ViewDrop {
    static let prefix = "archi-view:"
    static func string(_ kind: ViewKind, level: Int?) -> String { prefix + kind.rawValue + ":" + (level.map(String.init) ?? "") }
    static func parse(_ s: String) -> (ViewKind, Int?)? {
        guard s.hasPrefix(prefix) else { return nil }
        let parts = s.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard let k = parts.first.flatMap({ ViewKind(rawValue: String($0)) }) else { return nil }
        return (k, parts.count > 1 ? Int(parts[1]) : nil)
    }
    /// Scale of a view (model units per paper mm): "VIEWSCALE:<level>" when set, else the annotation scale, else 1:100.
    static func viewScale(_ doc: ArchiDocument, level: Int?) -> Double {
        let ratio = level.flatMap { doc.variable("VIEWSCALE:\($0)") }.flatMap(Annotative.factor) ?? doc.variable("CANNOSCALE").flatMap(Annotative.factor).flatMap { $0 > 1 ? $0 : nil } ?? 100
        return ratio / doc.units.mm
    }
    /// Adds a viewport centred on the drop point, sized to the model extents at the view scale (clamped to the sheet's
    /// drawing area). Returns the new viewport index.
    @discardableResult
    static func place(_ s: String, at paper: Vec2, layoutIndex li: Int, doc: inout ArchiDocument) -> Int? {
        guard let (kind, level) = parse(s), doc.layouts.indices.contains(li) else { return nil }
        let scale = viewScale(doc, level: level)
        var ext = GeometryOps.bounds(of: doc)
        if ext.isEmpty { ext = BBox2(min: Vec2(-5000, -5000), max: Vec2(5000, 5000)) / doc.units.mm }
        let area = SheetComposer.drawingArea(doc.layouts[li].paper)
        let size = Vec2(min(ext.width / scale + 20, area.width), min(ext.height / scale + 20, area.height))
        var origin = paper - size / 2
        origin.x = min(max(origin.x, area.min.x), area.max.x - size.x)
        origin.y = min(max(origin.y, area.min.y), area.max.y - size.y)
        doc.layouts[li].viewports.append(Viewport(origin: origin, size: size, viewCenter: ext.center, scale: scale, view: kind, level: kind == .plan || kind == .ceiling ? level : nil))
        return doc.layouts[li].viewports.count - 1
    }
}

private extension BBox2 { static func / (b: BBox2, s: Double) -> BBox2 { BBox2(min: b.min / s, max: b.max / s) } }

// MARK: - Custom visual styles (VIS-034)

/// A named visual style: a built-in base plus overrides (edges, edge colour, face opacity, shadows, background),
/// stored in the drawing (variable VISUALSTYLES, JSON).
struct VisualStyleDef: Codable, Hashable {
    var name: String
    var base: String
    var edges: Bool?
    var edgeColor: UInt32?
    var faceOpacity: Double?
    var shadows: Bool?
    var background: UInt32?

    static let variable = "VISUALSTYLES"
    static func all(_ doc: ArchiDocument) -> [VisualStyleDef] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([VisualStyleDef].self, from: d)) ?? []
    }
    static func store(_ list: [VisualStyleDef], in doc: inout ArchiDocument) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if list.isEmpty { doc.variables[variable] = nil; return }
        if let d = try? enc.encode(list.sorted { $0.name < $1.name }), let s = String(data: d, encoding: .utf8) { doc.variables[variable] = s }
    }
    static func named(_ n: String, in doc: ArchiDocument) -> VisualStyleDef? { all(doc).first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    /// Adds or replaces a style; refuses built-in names and unknown bases.
    @discardableResult
    static func save(_ v: VisualStyleDef, in doc: inout ArchiDocument) -> Bool {
        let n = v.name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !Scene3DBuilder.visualStyles.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }),
              let base = VisualStyleNames.resolve(v.base) else { return false }
        var list = all(doc).filter { $0.name.caseInsensitiveCompare(n) != .orderedSame }
        var x = v; x.name = n; x.base = base
        list.append(x)
        store(list, in: &doc)
        return true
    }
    static func delete(_ n: String, in doc: inout ArchiDocument) -> Bool {
        let list = all(doc)
        let rest = list.filter { $0.name.caseInsensitiveCompare(n) != .orderedSame }
        guard rest.count < list.count else { return false }
        store(rest, in: &doc)
        return true
    }
    /// Every style name offered by menus: built-in then custom.
    static func menuNames(_ doc: ArchiDocument) -> [String] { Scene3DBuilder.visualStyles + all(doc).map(\.name) }
}

// MARK: - Named plot styles (SHT-031)

/// Named plot style tables (STB): style name → pen (colour, screening, lineweight). Styles are assigned to layers
/// ("PLOTSTYLENAME:LAYER:<layer>" variables) and overridden per object (prop "plotStyle"). "Normal" plots unchanged.
enum NamedPlotStyles {
    static let tablePrefix = "STB:"
    static let layerPrefix = "PLOTSTYLENAME:LAYER:"
    static let prop = "plotStyle"
    static let defaultName = "archi named.stb"
    static let defaultTable: [String: PlotStyleTable.Pen] = [
        "Normal": .init(), "Black": .init(color: 0x000000), "Screened 50%": .init(screening: 50), "Screened 25%": .init(screening: 25),
        "Heavy": .init(lineweight: 0.7), "Fine": .init(lineweight: 0.13), "Red": .init(color: 0xE0201B),
    ]

    static func tables(_ doc: ArchiDocument) -> [String] {
        ([defaultName] + doc.variables.keys.filter { $0.hasPrefix(tablePrefix) }.map { String($0.dropFirst(tablePrefix.count)) }).reduce(into: [String]()) { a, n in
            if !a.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { a.append(n) }
        }
    }
    static func table(_ name: String, in doc: ArchiDocument) -> [String: PlotStyleTable.Pen]? {
        if let s = doc.variable(tablePrefix + name.uppercased()), let d = s.data(using: .utf8), let t = try? JSONDecoder().decode([String: PlotStyleTable.Pen].self, from: d) { return t }
        return name.caseInsensitiveCompare(defaultName) == .orderedSame ? defaultTable : nil
    }
    static func store(_ t: [String: PlotStyleTable.Pen], name: String, in doc: inout ArchiDocument) {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        if let d = try? enc.encode(t), let s = String(data: d, encoding: .utf8) { doc.variables[tablePrefix + name.uppercased()] = s }
    }
    static func layerStyle(_ layer: String, _ doc: ArchiDocument) -> String { doc.variable(layerPrefix + layer.uppercased()) ?? "Normal" }
    static func setLayerStyle(_ layer: String, _ style: String?, _ doc: inout ArchiDocument) {
        doc.variables[layerPrefix + layer.uppercased()] = (style == nil || style == "Normal") ? nil : style
    }
    /// Style of every object: its own ("ByLayer" or absent = the layer's).
    static func styleMap(_ doc: ArchiDocument) -> [EntityID: String] {
        var m: [EntityID: String] = [:]
        func pick(_ props: [String: String], _ layer: String) -> String {
            if let s = props[prop], s.caseInsensitiveCompare("ByLayer") != .orderedSame { return s }
            return layerStyle(layer, doc)
        }
        for e in doc.entities { m[e.id] = pick(e.props, e.layer) }
        for el in doc.elements { m[el.id] = pick(el.props, el.layer) }
        for l in doc.layouts { for e in l.entities { m[e.id] = pick(e.props, e.layer) } }
        return m
    }
    /// Plotted colour of a pen: its colour (or the object's), then screening towards white.
    static func apply(_ p: PlotStyleTable.Pen, to c: RGBA) -> RGBA {
        var out = p.color.map { RGBA(Double($0 >> 16 & 255) / 255, Double($0 >> 8 & 255) / 255, Double($0 & 255) / 255, c.a) } ?? c
        let k = min(max(p.screening, 0), 100) / 100
        if k < 1 { out = RGBA(1 - (1 - out.r) * k, 1 - (1 - out.g) * k, 1 - (1 - out.b) * k, out.a) }
        return out
    }
}

// MARK: - Settings export / import (APP-052)

/// All app preferences (the app's user-defaults domain) to a property list file, and back on another Mac.
enum SettingsTransfer {
    static var domain: String { Bundle.main.bundleIdentifier ?? "com.oanarina.archi" }
    /// Keys that belong to this Mac only (window positions, recent files, agent tokens) are not transferred.
    static func transferable(_ key: String) -> Bool {
        !(key.hasPrefix("NSWindow Frame") || key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("com.apple") || key.lowercased().contains("recent") || key.lowercased().contains("token"))
    }
    static func export(_ defaults: UserDefaults = .standard, domain: String? = nil) -> [String: Any] {
        let all = defaults.persistentDomain(forName: domain ?? SettingsTransfer.domain) ?? [:]
        return all.filter { transferable($0.key) }
    }
    static func write(to url: URL, from defaults: UserDefaults = .standard, domain: String? = nil) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: export(defaults, domain: domain), format: .xml, options: 0)
        try data.write(to: url)
    }
    /// Imports the settings of a file; returns the number of keys set.
    @discardableResult
    static func read(from url: URL, into defaults: UserDefaults = .standard) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return 0 }
        var n = 0
        for (k, v) in dict where transferable(k) { defaults.set(v, forKey: k); n += 1 }
        return n
    }
}

// MARK: - Window state (APP-001)

/// Panel column, panel tab and layout-tab visibility are remembered for new windows and after relaunch.
@MainActor
enum WindowStateMemory {
    static let panelsKey = "window.showPanels", tabKey = "window.panelTab"
    static func save(_ m: AppModel) {
        UserDefaults.standard.set(m.showPanels, forKey: panelsKey)
        UserDefaults.standard.set(m.panelTab.rawValue, forKey: tabKey)
    }
    static func restore(_ m: AppModel) {
        // Read both first: assigning one saves the other's current value.
        let v = UserDefaults.standard.object(forKey: panelsKey) as? Bool
        let t = UserDefaults.standard.string(forKey: tabKey).flatMap(PanelTab.init)
        if let t { m.panelTab = t }
        if let v { m.showPanels = v }
    }
}


// MARK: - Parametric grips of BIM elements (SEL-036)

enum BIMGrips {
    static func edgeMidpoints(_ pts: [Vec2]) -> [Vec2] {
        guard pts.count >= 2 else { return [] }
        return pts.indices.map { (pts[$0] + pts[($0 + 1) % pts.count]) / 2 }
    }
    /// Boundary after dragging grip `i`: a vertex (i < n) or edge i − n (both of its vertices move).
    static func moved(_ pts: [Vec2], grip i: Int, from o: Vec2, to p: Vec2) -> [Vec2] {
        var b = pts
        let n = pts.count
        if b.indices.contains(i) { b[i] = p }
        else if i >= n && i < 2 * n { let k = i - n, d = p - o; b[k] = b[k] + d; b[(k + 1) % n] = b[(k + 1) % n] + d }
        return b
    }
    /// Roof slope grip: on the inward normal of the eave edge at the run where the roof rises `unit` (1 m) — steeper roofs
    /// put it closer to the eave. Dragging it sets the pitch (5°–75°).
    static func slopeGrip(_ r: RoofGeom, unit: Double) -> Vec2? {
        guard let (m, n) = eave(r), r.pitch > 0.5 else { return nil }
        return m + n * (unit / tan(rad(r.pitch)))
    }
    static func pitch(_ r: RoofGeom, dragTo p: Vec2, unit: Double) -> Double {
        guard let (m, n) = eave(r) else { return r.pitch }
        let run = max((p - m).dot(n), 1e-9)
        return min(max(deg(atan(unit / run)), 5), 75)
    }
    /// Midpoint and inward unit normal of the eave edge.
    static func eave(_ r: RoofGeom) -> (Vec2, Vec2)? {
        let b = r.boundary
        guard b.count >= 3 else { return nil }
        let i = min(max(r.eaveEdge, 0), b.count - 1)
        let a = b[i], c = b[(i + 1) % b.count]
        let d = (c - a).normalized
        guard d != .zero else { return nil }
        var n = d.perp
        if GeometryOps.signedArea(b) < 0 { n = n * -1 }
        return ((a + c) / 2, n)
    }
}

// MARK: - Window tabs and full screen (APP-003, APP-004)

@MainActor
enum WindowTabs {
    static let preferKey = "openDrawingsInTabs"
    static var preferTabs: Bool {
        get { UserDefaults.standard.bool(forKey: preferKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferKey); for m in AppModel.all { if let w = m.window { configure(w) } } }
    }
    /// Document windows share one tab group (Window ▸ Merge All Windows, or always with "open in tabs"), go full screen
    /// as primary windows and tile in Split View.
    static func configure(_ w: NSWindow) {
        w.tabbingIdentifier = "OanarinaArchiDocument"
        w.tabbingMode = preferTabs ? .preferred : .automatic
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.collectionBehavior.insert(.managed)
        w.collectionBehavior.remove(.fullScreenAuxiliary)
        FullScreenState.track(w)
    }
}
