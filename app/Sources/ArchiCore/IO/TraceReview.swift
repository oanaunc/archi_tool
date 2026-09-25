// Oanarina Archi Tool — GPL-3.0-or-later
// Trace review overlays (COL-012, like AutoCAD's Trace): a named, author-stamped overlay layer ("TRACE-<name>") for
// review sketches and comments that sits over the drawing without changing it. Each trace remembers its view window,
// level and linked elements; it can be entered (becomes the current layer), shown/hidden, zoomed to (view + selection of
// the linked elements), closed, merged into the drawing (Import) or deleted. Metadata: drawing variable TRACES (JSON).
import Foundation

public struct TraceOverlay: Codable, Hashable {
    public var name: String
    public var author: String
    public var created: String
    public var comment: String
    /// View window (model coordinates) the trace was made on.
    public var viewMin: Vec2, viewMax: Vec2
    public var level: Int
    public var elements: [EntityID]
    public var status: String      // open / closed
    public var layer: String { TraceReview.layerName(name) }
    public var view: BBox2 { BBox2(min: viewMin, max: viewMax) }
}

public enum TraceReview {
    public static let variable = "TRACES"
    public static let previousLayerVariable = "TRACEPREVLAYER"
    public static func layerName(_ name: String) -> String {
        "TRACE-" + name.uppercased().map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }.reduce("") { $0 + String($1) }
    }

    public static func list(_ doc: ArchiDocument) -> [TraceOverlay] {
        guard let s = doc.variable(variable), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TraceOverlay].self, from: d)) ?? []
    }
    public static func save(_ traces: [TraceOverlay], in doc: inout ArchiDocument) {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        if traces.isEmpty { doc.variables[variable] = nil; return }
        if let d = try? enc.encode(traces), let s = String(data: d, encoding: .utf8) { doc.setVariable(variable, s) }
    }
    public static func find(_ doc: ArchiDocument, _ name: String) -> TraceOverlay? {
        list(doc).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Creates a trace and its overlay layer (magenta, 50 % transparent). Returns nil when the name is taken.
    @discardableResult
    public static func create(_ doc: inout ArchiDocument, name: String, author: String, comment: String, view: BBox2, level: Int, elements: [EntityID], date: Date = Date()) -> TraceOverlay? {
        var all = list(doc)
        guard !name.isEmpty, !all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        let f = ISO8601DateFormatter()
        let t = TraceOverlay(name: name, author: author, created: f.string(from: date), comment: comment, viewMin: view.min, viewMax: view.max,
                             level: level, elements: elements, status: "open")
        all.append(t)
        save(all, in: &doc)
        if doc.layer(named: t.layer) == nil {
            var l = Layer(name: t.layer, color: RGBA(1, 0, 1))
            l.transparency = 0.5
            l.plot = false
            l.description = "Trace \(name) by \(author)"
            doc.layers.append(l)
        }
        return t
    }

    /// Objects drawn on the trace's layer.
    public static func entities(_ doc: ArchiDocument, _ t: TraceOverlay) -> [Entity] {
        doc.entities.filter { $0.layer.caseInsensitiveCompare(t.layer) == .orderedSame }
    }

    /// Moves the trace's objects to `layer` (they become part of the drawing). Returns how many moved.
    @discardableResult
    public static func importInto(_ doc: inout ArchiDocument, _ t: TraceOverlay, layer: String) -> Int {
        doc.ensureLayer(layer)
        var n = 0
        for i in doc.entities.indices where doc.entities[i].layer.caseInsensitiveCompare(t.layer) == .orderedSame {
            doc.entities[i].layer = layer
            doc.entities[i].props["fromTrace"] = t.name
            n += 1
        }
        return n
    }

    /// Deletes the trace, its objects and its layer.
    public static func delete(_ doc: inout ArchiDocument, _ name: String) {
        guard let t = find(doc, name) else { return }
        doc.entities.removeAll { $0.layer.caseInsensitiveCompare(t.layer) == .orderedSame }
        doc.layers.removeAll { $0.name.caseInsensitiveCompare(t.layer) == .orderedSame }
        if doc.currentLayer.caseInsensitiveCompare(t.layer) == .orderedSame { doc.currentLayer = doc.variable(previousLayerVariable) ?? "0" }
        save(list(doc).filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }, in: &doc)
    }

    public static func update(_ doc: inout ArchiDocument, _ name: String, _ body: (inout TraceOverlay) -> Void) {
        var all = list(doc)
        guard let i = all.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        body(&all[i])
        save(all, in: &doc)
    }

    static var command: CommandDef {
        CommandDef("TRACEREVIEW", aliases: ["TRACES", "TRACEOVERLAY", "REVIEWTRACE"], category: "Collaborate",
                   summary: "Trace review overlays: New (named overlay layer over the drawing, linked to the view and selected elements), Enter/Exit (draw on it), Show/Hide, Zoom (restores its view and selects its elements), List, Close, Import (merge its sketches into the drawing), Delete.") { ed in
            let k = try await ed.getKeyword("Enter an option [New/Enter/Exit/Show/Hide/Zoom/List/Close/Import/Delete]",
                                            ["New", "Enter", "Exit", "Show", "Hide", "Zoom", "List", "Close", "Import", "Delete"], defaultValue: "List") ?? "List"
            @MainActor func pick() async throws -> TraceOverlay {
                let all = list(ed.doc)
                guard let last = all.last else { throw CommandError.invalid("No traces (TRACEREVIEW New).") }
                let n = try await ed.getWord("Trace name <\(last.name)>", defaultValue: last.name) ?? last.name
                guard let t = find(ed.doc, n) else { throw CommandError.invalid("No trace \(n).") }
                return t
            }
            @MainActor func setVisible(_ t: TraceOverlay, _ on: Bool) {
                if let i = ed.doc.layerIndex(t.layer) { ed.doc.layers[i].visible = on; if on { ed.doc.layers[i].frozen = false } }
            }
            switch k {
            case "New":
                let n = list(ed.doc).count + 1
                let name = try await ed.getWord("Trace name <Trace \(n)>", defaultValue: "Trace \(n)") ?? "Trace \(n)"
                guard find(ed.doc, name) == nil else { throw CommandError.invalid("A trace named \(name) exists.") }
                let comment = try await ed.getString("Comment <none>", defaultValue: "") ?? ""
                let a = try await ed.requirePoint("Specify first corner of the reviewed view")
                let b = try await ed.requirePoint("Specify opposite corner", base: a, preview: { p in [.polyline(PolylineGeom(points: [a, Vec2(p.x, a.y), p, Vec2(a.x, p.y)], closed: true))] })
                let author = ed.doc.variable("USERNAME") ?? (ed.doc.info.author.isEmpty ? NSUserName() : ed.doc.info.author)
                let linked = Array(ed.selection).filter { ed.doc.element($0) != nil || ed.doc.entity($0) != nil }.sorted()
                var d = ed.doc
                guard let t = create(&d, name: name, author: author, comment: comment, view: BBox2(points: [a, b]), level: d.currentLevel, elements: linked) else { throw CommandError.invalid("Cannot create trace \(name).") }
                d.setVariable(previousLayerVariable, d.currentLayer)
                d.currentLayer = t.layer
                ed.doc = d
                ed.print("Trace \(name) created by \(author) on layer \(t.layer) (\(linked.count) linked element(s)); you are drawing on it — TRACEREVIEW Exit to return.")
            case "Enter":
                let t = try await pick()
                setVisible(t, true)
                if ed.doc.currentLayer.caseInsensitiveCompare(t.layer) != .orderedSame { ed.doc.setVariable(previousLayerVariable, ed.doc.currentLayer) }
                ed.doc.currentLayer = t.layer
                ReviewCommands.zoomTo(ed, t.view, ids: t.elements)
                ed.print("Drawing on trace \(t.name).")
            case "Exit":
                ed.doc.currentLayer = ed.doc.variable(previousLayerVariable).flatMap { ed.doc.layer(named: $0)?.name } ?? "0"
                ed.print("Current layer \(ed.doc.currentLayer).")
            case "Show", "Hide":
                let t = try await pick()
                setVisible(t, k == "Show")
            case "Zoom":
                let t = try await pick()
                if ed.doc.level(t.level) != nil { ed.doc.currentLevel = t.level }
                setVisible(t, true)
                ReviewCommands.zoomTo(ed, t.view, ids: t.elements)
                ed.print("Trace \(t.name) by \(t.author), \(t.created): \(t.comment.isEmpty ? "(no comment)" : t.comment) — \(t.elements.count) linked element(s), \(entities(ed.doc, t).count) sketch object(s).")
            case "Close":
                let t = try await pick()
                update(&ed.doc, t.name) { $0.status = "closed" }
                setVisible(t, false)
                ed.print("Trace \(t.name) closed.")
            case "Import":
                let t = try await pick()
                let target = try await ed.getWord("Layer to move the trace objects to <\(ed.doc.variable(previousLayerVariable) ?? "0")>", defaultValue: ed.doc.variable(previousLayerVariable) ?? "0") ?? "0"
                let n = importInto(&ed.doc, t, layer: target)
                ed.print("\(n) object(s) from trace \(t.name) moved to layer \(target).")
            case "Delete":
                let t = try await pick()
                delete(&ed.doc, t.name)
                ed.print("Trace \(t.name) deleted.")
            default:
                let all = list(ed.doc)
                if all.isEmpty { ed.print("No traces.") }
                for t in all {
                    let vis = ed.doc.layer(named: t.layer)?.visible ?? false
                    ed.print("\(t.name) [\(t.status)\(vis ? ", shown" : ", hidden")] by \(t.author) \(t.created) — \(entities(ed.doc, t).count) object(s), \(t.elements.count) linked: \(t.comment)")
                }
            }
        }
    }
}
