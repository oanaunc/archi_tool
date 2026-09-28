// Oanarina Archi Tool — GPL-3.0-or-later
// Data behind the Mac workspace panels and windows that the Windows shell draws itself: the Alerts panel
// (ModelNotifications, StudioPanels.swift), the Navigator overview map (NavigatorPanel), the Content panel
// (DesignCenter, AppNavigation.swift / AppNavigationViews.swift), the Outliner window (AppCommandsRound11.swift),
// section and elevation tiles of the tiled views (TiledViews.swift ProjectionTile), the status-bar macro buttons
// (MacroButtonBar), plugin commands as one undo step (UndoStep, AppCommandsStudio.swift) and the AI assistant's
// drawing context, trial run and apply (Assistant.swift). See docs/ENGINE-PROTOCOL.md "Panels and workspace".
import Foundation

/// Model warnings of the Alerts panel (the Mac ModelNotifications.items).
public enum EngineAlerts {
    public struct Item {
        public var severity: IssueSeverity
        public var code: String
        public var message: String
        public var ids: [EntityID]
        public var bounds: BBox2
        public var level: Int?
        /// Stable key used to dismiss an item (the Mac Item.id).
        public var key: String {
            let idText = ids.map { String($0) }.joined(separator: ",")
            return code + ":" + idText + ":" + message
        }
    }

    static func elementBounds(_ el: BIMElement, doc: ArchiDocument) -> BBox2 {
        var b = BBox2.empty
        for p in ElementGrips.points(el, doc: doc) { b.add(p) }
        return b
    }

    public static func items(_ doc: ArchiDocument) -> [Item] {
        var out: [Item] = []
        for i in ModelChecker.check(doc) {
            let level = i.ids.lazy.compactMap { doc.element($0)?.level }.first
            out.append(Item(severity: i.severity, code: i.code, message: i.message, ids: i.ids, bounds: i.bounds, level: level))
        }
        for el in doc.elements {
            guard let e = el.props["familyErrors"] else { continue }
            let name = el.name.isEmpty ? el.typeName : el.name
            out.append(Item(severity: .warning, code: "FAMILY", message: name + ": " + e, ids: [el.id], bounds: elementBounds(el, doc: doc), level: el.level))
        }
        for e in doc.entities {
            if case .insert(let g) = e.geometry, doc.blocks[g.block] == nil {
                out.append(Item(severity: .error, code: "BLOCK-MISSING", message: "Block " + g.block + " is not defined", ids: [e.id],
                                bounds: GeometryOps.bounds(e.geometry, doc: doc), level: nil))
            }
            if doc.layer(named: e.layer) == nil {
                out.append(Item(severity: .info, code: "LAYER-MISSING", message: "Layer " + e.layer + " is not in the layer table", ids: [e.id],
                                bounds: GeometryOps.bounds(e.geometry, doc: doc), level: nil))
            }
        }
        if LayerNotify.isOn(doc) {
            let u = LayerNotify.unreconciled(doc)
            if !u.isEmpty {
                var ids: [EntityID] = []
                for e in doc.entities where u.contains(where: { $0.caseInsensitiveCompare(e.layer) == .orderedSame }) { ids.append(e.id) }
                var b = BBox2.empty
                for id in ids.prefix(200) { if let e = doc.entity(id) { b = b.union(GeometryOps.bounds(e.geometry, doc: doc)) } }
                let plural = u.count == 1 ? "" : "s"
                out.append(Item(severity: .warning, code: "LAYER-UNRECONCILED", message: "Unreconciled new layer" + plural + ": " + u.joined(separator: ", ") + " (LAYRECONCILE)",
                                ids: Array(ids.prefix(50)), bounds: b, level: nil))
            }
        }
        return out.sorted { a, b in a.severity != b.severity ? a.severity < b.severity : a.code < b.code }
    }
}

/// Design Center (ADCENTER): definitions of another drawing that can be copied into this one.
public enum EngineDesignCenter {
    public static let kinds = ["Blocks", "Layers", "Linetypes", "Text Styles", "Dimension Styles", "Materials"]
    public static let symbols = ["square.on.square.dashed", "square.3.layers.3d", "line.3.horizontal", "textformat", "ruler", "paintpalette"]

    public static func names(_ kind: String, in doc: ArchiDocument) -> [String] {
        switch kind {
        case "Blocks": return doc.blocks.keys.filter { !$0.hasPrefix("*") }.sorted()
        case "Layers": return doc.layers.map(\.name)
        case "Linetypes": return doc.linetypes.map(\.name)
        case "Text Styles": return doc.textStyles.map(\.name)
        case "Dimension Styles": return doc.dimStyles.map(\.name)
        case "Materials": return doc.materials.map(\.name)
        default: return []
        }
    }

    static func has(_ names: [String], _ n: String) -> Bool { names.contains { $0.caseInsensitiveCompare(n) == .orderedSame } }

    /// Copies the named definitions (blocks bring nested blocks, their layers and linetypes); existing names are kept.
    /// Returns the names actually added (DesignCenter.copy).
    @discardableResult
    public static func copy(_ kind: String, _ names: [String], from src: ArchiDocument, into dst: inout ArchiDocument) -> [String] {
        var added: [String] = []
        switch kind {
        case "Blocks":
            var todo = names
            var seen: Set<String> = []
            while let n = todo.popLast() {
                guard !seen.contains(n), let b = src.blocks[n] else { continue }
                seen.insert(n)
                for e in b.entities {
                    if case .insert(let i) = e.geometry { todo.append(i.block) }
                    if dst.layer(named: e.layer) == nil, let l = src.layer(named: e.layer) { dst.layers.append(l) }
                    if let lt = e.linetype, !has(dst.linetypes.map(\.name), lt),
                       let def = src.linetypes.first(where: { $0.name.caseInsensitiveCompare(lt) == .orderedSame }) { dst.linetypes.append(def) }
                }
                if dst.blocks[n] == nil { dst.blocks[n] = b; added.append(n) }
            }
        case "Layers":
            for n in names where dst.layer(named: n) == nil { if let l = src.layer(named: n) { dst.layers.append(l); added.append(l.name) } }
        case "Linetypes":
            for n in names where !has(dst.linetypes.map(\.name), n) { if let l = src.linetypes.first(where: { $0.name == n }) { dst.linetypes.append(l); added.append(n) } }
        case "Text Styles":
            for n in names where !has(dst.textStyles.map(\.name), n) { if let s = src.textStyles.first(where: { $0.name == n }) { dst.textStyles.append(s); added.append(n) } }
        case "Dimension Styles":
            for n in names where !has(dst.dimStyles.map(\.name), n) { if let s = src.dimStyles.first(where: { $0.name == n }) { dst.dimStyles.append(s); added.append(n) } }
        case "Materials":
            for n in names where dst.material(n) == nil { if let m = src.material(n) { dst.materials.append(m); added.append(n) } }
        default: break
        }
        return added
    }
}

/// The AI assistant's system prompt and the measured impact of its command lines (AssistantProtocol / AssistantImpact).
public enum EngineAssistant {
    public static let toolName = "run_commands"
    public static let toolDescription = "Runs Oanarina Archi Tool command lines on the open drawing, in order. Each string is one command line exactly as typed on the command line, e.g. \"LINE 0,0 1000,0 \", \"WALL 0,0 5000,0 \" or \"ERASE #12 \". Inputs are separated by spaces; a trailing space ends the command."

    static func typeName(_ g: Geometry) -> String {
        let s = String(describing: g)
        return s.split(separator: "(").first.map(String.init) ?? "entity"
    }

    static func counts(_ d: [String: Int]) -> String {
        d.keys.sorted().map { k in k + " " + String(d[k] ?? 0) }.joined(separator: ", ")
    }

    /// Compact description of the drawing for the system prompt.
    public static func context(_ doc: ArchiDocument, selection: Set<EntityID>) -> String {
        var byType: [String: Int] = [:]
        for e in doc.entities { byType[typeName(e.geometry), default: 0] += 1 }
        var byEl: [String: Int] = [:]
        for e in doc.elements { byEl[e.typeName, default: 0] += 1 }
        var levelText: [String] = []
        for l in doc.levels { levelText.append(l.name + " (id " + String(l.id) + ", elev " + fmt(l.elevation, 0) + ")") }
        let levels = levelText.isEmpty ? "none" : levelText.joined(separator: ", ")
        let unitsText = String(describing: doc.units)
        var s = "Drawing: " + doc.info.name + ". Units: " + unitsText + " (" + fmt(doc.units.mm, 4) + " mm per unit). Current layer: " + doc.currentLayer
        s += ". Current level id: " + String(doc.currentLevel) + ".\n"
        s += "Levels: " + levels + ".\n"
        s += "Layers: " + doc.layers.prefix(60).map(\.name).joined(separator: ", ") + ".\n"
        s += "Entities: " + counts(byType) + ".\n"
        s += "Building elements: " + counts(byEl) + ".\n"
        let sel = selection.sorted().prefix(40).map { "#" + String($0) }.joined(separator: " ")
        s += "Selection: " + (selection.isEmpty ? "none" : sel) + ".\n"
        return s
    }

    public static func systemPrompt(_ doc: ArchiDocument, selection: Set<EntityID>, registry: CommandRegistry) -> String {
        var cats: [String: [String]] = [:]
        for c in registry.sorted where !c.summary.hasPrefix("System variable") { cats[c.category, default: []].append(c.name) }
        var lines: [String] = []
        for k in cats.keys.sorted() { lines.append(k + ": " + (cats[k] ?? []).joined(separator: " ")) }
        var s = "You are the assistant inside Oanarina Archi Tool, a CAD/BIM application for Windows and macOS with an AutoCAD-style command line. "
        s += "Make changes only by calling " + toolName + " with command lines (or, if you cannot call tools, put them one per line in a ```archi fenced block). "
        s += "Coordinates are x,y in drawing units; @dx,dy is relative; d<angle is polar; #ID picks an object by id. End each command with a space. "
        s += "Answer questions about the drawing in plain text. Keep edits minimal and explain what you did.\n"
        s += context(doc, selection: selection)
        s += "Commands by category:\n" + lines.joined(separator: "\n")
        return s
    }

    public struct Impact {
        public var added = 0, removed = 0, modified = 0
        public var output: [String] = []
        public var total: Int { added + removed + modified }
        public var summary: String { String(added) + " added, " + String(modified) + " modified, " + String(removed) + " deleted" }
        public func isBulk(bulkLimit: Int, deleteLimit: Int) -> Bool { total > bulkLimit || removed > deleteLimit }
    }

    public static func diff(_ a: ArchiDocument, _ b: ArchiDocument) -> Impact {
        var r = Impact()
        var ea: [EntityID: Entity] = [:]
        for e in a.entities { ea[e.id] = e }
        var eb: [EntityID: Entity] = [:]
        for e in b.entities { eb[e.id] = e }
        var la: [EntityID: BIMElement] = [:]
        for e in a.elements { la[e.id] = e }
        var lb: [EntityID: BIMElement] = [:]
        for e in b.elements { lb[e.id] = e }
        for (k, v) in eb { if let o = ea[k] { if o != v { r.modified += 1 } } else { r.added += 1 } }
        for k in ea.keys where eb[k] == nil { r.removed += 1 }
        for (k, v) in lb { if let o = la[k] { if o != v { r.modified += 1 } } else { r.added += 1 } }
        for k in la.keys where lb[k] == nil { r.removed += 1 }
        return r
    }

    /// Runs the commands on a scratch editor holding a copy of the drawing.
    @MainActor public static func assess(_ commands: [String], doc: ArchiDocument, selection: Set<EntityID>, registry: CommandRegistry) async -> Impact {
        let scratch = Editor(document: doc, registry: registry)
        scratch.selection = selection
        var out: [String] = []
        for c in commands { out += await scratch.run(c) }
        var r = diff(doc, scratch.doc)
        r.output = out
        return r
    }
}

/// Tiles of the tiled views (TileKind): section and elevations are projections of the model.
public enum EngineTiles {
    public static let kinds = ["Plan", "3D", "Section", "North", "South", "East", "West"]
    public static func viewKind(_ name: String) -> ViewKind? {
        switch name.lowercased() {
        case "section": return .section
        case "north": return .elevationNorth
        case "south": return .elevationSouth
        case "east": return .elevationEast
        case "west": return .elevationWest
        default: return nil
        }
    }
}

extension EngineSession {
    /// Before-state of a plugin command's undo group (UndoStep.begin), per session.
    static var undoGroups: [ObjectIdentifier: (ArchiDocument, UndoHistory)] = [:]

    func callWorkspace(_ method: String, _ p: EngineJSON) async throws -> EngineJSON? {
        switch method {
        case "alerts.get": return alertsGet(p)
        case "navigator.get": return navigatorGet(p)
        case "content.kinds": return contentKinds()
        case "content.scan": return try contentScan(p)
        case "content.add": return try contentAdd(p)
        case "outliner.get": return outlinerGet(p)
        case "view.projection": return try projection(p)
        case "macro.buttons": return macroButtons()
        case "macro.run": return try await macroRun(p)
        case "undo.begin": return undoBegin()
        case "undo.end": return undoEnd(p)
        case "assistant.context": return assistantContext()
        case "assistant.assess": return try await assistantAssess(p)
        case "assistant.apply": return try await assistantApply(p)
        default: return nil
        }
    }

    // MARK: Alerts

    func alertsGet(_ p: EngineJSON) -> EngineJSON {
        let showInfo = p["showInfo"]?.boolValue ?? false
        let dismissed = Set((p["dismissed"]?.arrayValue ?? []).compactMap { $0.stringValue })
        let all = EngineAlerts.items(editor.doc)
        var out: [EngineJSON] = []
        var warnings = 0
        for it in all {
            if it.severity != .info { warnings += 1 }
            if dismissed.contains(it.key) { continue }
            if !showInfo && it.severity == .info { continue }
            var o = EngineObject()
            o.set("key", it.key)
            o.set("severity", it.severity.rawValue)
            o.set("code", it.code)
            o.set("message", it.message)
            o.set("ids", EngineJSON.ints(it.ids))
            o.set("bounds", it.bounds.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(it.bounds))
            o.set("level", it.level.map { EngineJSON.int($0) } ?? .null)
            out.append(o.json)
        }
        var o = EngineObject()
        o.set("items", EngineJSON.array(out))
        o.set("count", out.count)
        o.set("warnings", warnings)
        o.set("total", all.count)
        return o.json
    }

    // MARK: Navigator

    /// Overview map: every entity tessellated (first 20 000) and the outlines of the current level's elements,
    /// as flat [x0,y0,x1,y1…] polylines, with the drawing extents.
    func navigatorGet(_ p: EngineJSON) -> EngineJSON {
        let doc = editor.doc
        let limit = max(1, p["limit"]?.intValue ?? 20000)
        var lines: [EngineJSON] = []
        var ext = BBox2.empty
        for e in doc.entities.prefix(limit) {
            for pl in GeometryOps.tessellate(e.geometry, doc: doc) where pl.count > 1 {
                var flat: [EngineJSON] = []
                for q in pl { flat.append(.number(q.x)); flat.append(.number(q.y)); ext.add(q) }
                lines.append(.array(flat))
            }
        }
        for el in doc.elements where el.level == doc.currentLevel {
            let g = ElementGrips.points(el, doc: doc)
            guard g.count > 1 else { continue }
            var flat: [EngineJSON] = []
            for q in g { flat.append(.number(q.x)); flat.append(.number(q.y)); ext.add(q) }
            lines.append(.array(flat))
        }
        let box = GeometryOps.bounds(of: doc)
        var o = EngineObject()
        o.set("lines", EngineJSON.array(lines))
        o.set("extents", box.isEmpty ? (ext.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(ext)) : EngineDrawJSON.rect(box))
        o.set("level", doc.currentLevel)
        return o.json
    }

    // MARK: Content (Design Center)

    func contentKinds() -> EngineJSON {
        var out: [EngineJSON] = []
        for (i, k) in EngineDesignCenter.kinds.enumerated() {
            out.append(ScriptJSON.object([("kind", .string(k)), ("symbol", .string(EngineDesignCenter.symbols[i]))]))
        }
        return .array(out)
    }

    func contentSource(_ p: EngineJSON) throws -> (ArchiDocument, String) {
        let path = try string(p, "path")
        let u = url(path)
        guard FileManager.default.fileExists(atPath: u.path) else { throw EngineError.failed("File not found: " + u.path) }
        let d: ArchiDocument
        do { d = try DocumentIO.read(u) } catch { throw EngineError.failed("Cannot read " + u.lastPathComponent + ".") }
        return (d, u.deletingPathExtension().lastPathComponent)
    }

    /// Names of every kind of definition in another drawing.
    func contentScan(_ p: EngineJSON) throws -> EngineJSON {
        let (src, name) = try contentSource(p)
        var kinds: [EngineJSON] = []
        for (i, k) in EngineDesignCenter.kinds.enumerated() {
            let names = EngineDesignCenter.names(k, in: src)
            kinds.append(ScriptJSON.object([("kind", .string(k)), ("symbol", .string(EngineDesignCenter.symbols[i])), ("names", EngineJSON.strings(names))]))
        }
        var o = EngineObject()
        o.set("name", name)
        o.set("path", try string(p, "path"))
        o.set("kinds", EngineJSON.array(kinds))
        return o.json
    }

    /// Copies definitions into the drawing: one undo step "Design Center".
    func contentAdd(_ p: EngineJSON) throws -> EngineJSON {
        let (src, _) = try contentSource(p)
        let kind = try string(p, "kind")
        guard EngineDesignCenter.kinds.contains(kind) else { throw EngineError.params("unknown kind '" + kind + "'") }
        var names = (p["names"]?.arrayValue ?? []).compactMap { $0.stringValue }
        if p["all"]?.boolValue == true { names = EngineDesignCenter.names(kind, in: src) }
        var added: [String] = []
        if !names.isEmpty { editor.transaction("Design Center") { added = EngineDesignCenter.copy(kind, names, from: src, into: &$0) } }
        let message = added.isEmpty ? "Nothing new: those names already exist here." : "Added " + String(added.count) + ": " + added.joined(separator: ", ")
        if !added.isEmpty { markChanged("document") }
        var o = EngineObject()
        o.set("added", EngineJSON.strings(added))
        o.set("message", message)
        return o.json
    }

    // MARK: Outliner

    static func outlinerSymbol(_ kind: String) -> String {
        switch kind {
        case "group": return "square.on.square.dashed"
        case "component": return "cube"
        case "block": return "square.on.square"
        case "modelGroup": return "square.3.layers.3d"
        case "modelGroupInstance": return "square.stack.3d.up"
        default: return "cube.transparent"
        }
    }

    /// Nodes whose name (or a descendant's) contains the filter (OutlinerItem.filtered).
    static func outlinerJSON(_ nodes: [Outliner.Node], filter: String, selection: Set<EntityID>) -> [EngineJSON] {
        var out: [EngineJSON] = []
        for n in nodes {
            let kids = outlinerJSON(n.children, filter: filter, selection: selection)
            let match = filter.isEmpty || n.name.lowercased().contains(filter.lowercased())
            if !match && kids.isEmpty { continue }
            let children = match ? outlinerJSON(n.children, filter: "", selection: selection) : kids
            var o = EngineObject()
            o.set("name", n.name)
            o.set("kind", n.kind)
            o.set("symbol", outlinerSymbol(n.kind))
            o.set("id", n.id.map { EngineJSON.int($0) } ?? .null)
            o.set("selected", n.id.map { selection.contains($0) } ?? false)
            o.set("children", EngineJSON.array(children))
            out.append(o.json)
        }
        return out
    }

    func outlinerGet(_ p: EngineJSON) -> EngineJSON {
        let f = (p["filter"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        let nodes = EngineSession.outlinerJSON(Outliner.tree(editor.doc), filter: f, selection: editor.selection)
        var o = EngineObject()
        o.set("nodes", EngineJSON.array(nodes))
        o.set("empty", nodes.isEmpty)
        return o.json
    }

    // MARK: Tiles

    /// Projection entries per session, view and drawing revision (a Cedar House elevation has ~600 000 fills).
    static var projectionCache: [ObjectIdentifier: (kind: ViewKind, stamp: Int, entries: [DrawEntry], bounds: BBox2)] = [:]

    func projectionEntries(_ kind: ViewKind) -> ([DrawEntry], BBox2) {
        let key = ObjectIdentifier(self)
        if let c = EngineSession.projectionCache[key], c.kind == kind, c.stamp == editor.changeCount { return (c.entries, c.bounds) }
        let vp = Viewport(origin: .zero, size: Vec2(1, 1), viewCenter: .zero, scale: 1, view: kind)
        let es = EnginePlot.viewportEntries(doc: editor.doc, vp: vp)
        var b = BBox2.empty
        for e in es { b.add(e.bounds) }
        EngineSession.projectionCache[key] = (kind, editor.changeCount, es, b)
        return (es, b)
    }

    /// Hidden-line projection of the model for a tile (Section, North, South, East, West) with the view title
    /// (ProjectionTileView). With `width` and `height` (pixels) the engine paints it on white paper
    /// (DrawRaster, the portable rasteriser) for the world window `rect` (default: the whole projection with a margin)
    /// and returns a base64 PNG — the entries of a real model are far too many to send; without them, the draw items.
    func projection(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "view")
        guard let kind = EngineTiles.viewKind(name) else { throw EngineError.params("view must be Section, North, South, East or West") }
        let (es, b) = projectionEntries(kind)
        let vp = Viewport(origin: .zero, size: Vec2(1, 1), viewCenter: .zero, scale: 1, view: kind)
        var o = EngineObject()
        o.set("view", name)
        o.set("title", EngineSheets.viewTitle(vp, doc: editor.doc))
        o.set("bounds", b.isEmpty ? EngineJSON.null : EngineDrawJSON.rect(b))
        if let w = p["width"]?.intValue, let h = p["height"]?.intValue {
            let pw = min(max(w, 16), 4096)
            let ph = min(max(h, 16), 4096)
            var win = rect(p["rect"]) ?? b.expanded(by: max(b.width, b.height) * 0.05)
            if win.isEmpty { win = BBox2(min: Vec2(0, 0), max: Vec2(10000, 10000)) }
            let sx = Double(pw) / max(win.width, 1e-9)
            let sy = Double(ph) / max(win.height, 1e-9)
            let ppu = min(sx, sy)
            let cx = (win.min.x + win.max.x) / 2
            let cy = (win.min.y + win.max.y) / 2
            let halfW = Double(pw) / ppu / 2
            let halfH = Double(ph) / ppu / 2
            var r = DrawRaster(image: RGBAImage(width: pw, height: ph), origin: Vec2(cx - halfW, cy + halfH), scale: ppu)
            r.lineweightScale = 2.2 * max(1, p["dpr"]?.doubleValue ?? 1)
            r.minWidth = 0.6
            r.subsamples = 2
            r.textStyles = editor.doc.textStyles
            let view = BBox2(min: Vec2(cx - halfW, cy - halfH), max: Vec2(cx + halfW, cy + halfH))
            r.draw(es.filter { $0.bounds.isEmpty || view.intersects($0.bounds) })
            o.set("rect", EngineDrawJSON.rect(view))
            o.set("width", pw)
            o.set("height", ph)
            o.set("png", r.image.pngData().base64EncodedString())
            return o.json
        }
        var items: [EngineJSON] = []
        let limit = max(1, p["limit"]?.intValue ?? 200000)
        for e in es {
            for it in e.items where items.count < limit { items.append(EngineDrawJSON.item(it, id: e.id)) }
        }
        o.set("items", EngineJSON.array(items))
        o.set("truncated", items.count >= limit)
        return o.json
    }

    // MARK: Macro buttons

    func macroButtons() -> EngineJSON {
        var out: [EngineJSON] = []
        for b in MacroButtons.all(editor.doc) {
            var o = EngineObject()
            o.set("name", b.name)
            o.set("macro", b.macro)
            o.set("icon", b.icon)
            o.set("tooltip", b.tooltip)
            o.set("group", b.group)
            out.append(o.json)
        }
        return .array(out)
    }

    /// Runs a macro button (Editor.runMacro: ^C^C cancels, ";" is Enter, "\" pauses for input).
    func macroRun(_ p: EngineJSON) async throws -> EngineJSON {
        let m = try string(p, "macro")
        editor.runMacro(m)
        await settle()
        return promptState()
    }

    // MARK: Undo groups (plugin commands are one undo step)

    func undoBegin() -> EngineJSON {
        EngineSession.undoGroups[ObjectIdentifier(self)] = (editor.doc, editor.history)
        return ScriptJSON.object([("ok", .bool(true))])
    }

    /// Collapses the edits since undo.begin into one step named `label`; false when nothing changed.
    func undoEnd(_ p: EngineJSON) -> EngineJSON {
        let key = ObjectIdentifier(self)
        guard let (before, history) = EngineSession.undoGroups.removeValue(forKey: key) else { return ScriptJSON.object([("collapsed", .bool(false))]) }
        let label = p["label"]?.stringValue ?? "Plugin"
        var h = history
        if editor.doc == before {
            editor.history = h
            return ScriptJSON.object([("collapsed", .bool(false))])
        }
        h.record(label, before: before)
        editor.history = h
        markChanged("document")
        return ScriptJSON.object([("collapsed", .bool(true)), ("label", .string(label))])
    }

    // MARK: Assistant

    func assistantContext() -> EngineJSON {
        var o = EngineObject()
        o.set("system", EngineAssistant.systemPrompt(editor.doc, selection: editor.selection, registry: editor.registry))
        o.set("context", EngineAssistant.context(editor.doc, selection: editor.selection))
        o.set("toolName", EngineAssistant.toolName)
        o.set("toolDescription", EngineAssistant.toolDescription)
        return o.json
    }

    func commandList(_ p: EngineJSON) throws -> [String] {
        let list = (p["commands"]?.arrayValue ?? []).compactMap { $0.stringValue }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !list.isEmpty else { throw EngineError.params("missing 'commands'") }
        return list
    }

    /// What the commands would change, measured on a copy of the drawing; `bulk` with the given limits.
    func assistantAssess(_ p: EngineJSON) async throws -> EngineJSON {
        let cmds = try commandList(p)
        let r = await EngineAssistant.assess(cmds, doc: editor.doc, selection: editor.selection, registry: editor.registry)
        let bulkLimit = p["bulkLimit"]?.intValue ?? 25
        let deleteLimit = p["deleteLimit"]?.intValue ?? 5
        var o = EngineObject()
        o.set("added", r.added)
        o.set("removed", r.removed)
        o.set("modified", r.modified)
        o.set("total", r.total)
        o.set("summary", r.summary)
        o.set("bulk", r.isBulk(bulkLimit: bulkLimit, deleteLimit: deleteLimit))
        o.set("output", EngineJSON.strings(r.output))
        return o.json
    }

    /// Runs the commands on the drawing as normal, undoable commands.
    func assistantApply(_ p: EngineJSON) async throws -> EngineJSON {
        let cmds = try commandList(p)
        var out: [String] = []
        for c in cmds { out += await runLines(c) }
        markChanged("document")
        var o = EngineObject()
        o.set("count", cmds.count)
        o.set("output", EngineJSON.strings(out))
        return o.json
    }
}
