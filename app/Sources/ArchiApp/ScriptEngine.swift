// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import JavaScriptCore
import Combine
import ArchiCore

// MARK: - JSON bridge (shared by scripts and the agent server)

/// Converts between loose JSON (from scripts/agents) and core model types.
/// Geometry objects use the `.archi` Codable format; missing fields get defaults and points may be `[x, y]`.
enum ArchiJSON {
    struct BridgeError: Error, LocalizedError { let message: String; var errorDescription: String? { message } }
    static func fail(_ m: String) -> BridgeError { BridgeError(message: m) }

    static func object<T: Encodable>(_ v: T) -> Any {
        let enc = JSONEncoder()
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let d = try? enc.encode(v), let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) else { return NSNull() }
        return o
    }

    static func decode<T: Decodable>(_ t: T.Type, from obj: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed])
        let dec = JSONDecoder()
        dec.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        do { return try dec.decode(t, from: data) }
        catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, _): throw fail("missing field '\(k.stringValue)'")
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
                throw fail("\(c.debugDescription) at \(c.codingPath.map { $0.stringValue }.joined(separator: "."))")
            @unknown default: throw fail("\(e)")
            }
        }
    }

    static func jsonString(_ obj: Any, pretty: Bool = false) -> String {
        guard JSONSerialization.isValidJSONObject(obj) || obj is String || obj is NSNumber || obj is NSNull,
              let d = try? JSONSerialization.data(withJSONObject: obj, options: pretty ? [.fragmentsAllowed, .prettyPrinted, .sortedKeys] : [.fragmentsAllowed, .sortedKeys]) else { return "\(obj)" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    // MARK: Normalisation

    static let plainNumberArrays: Set<String> = ["knots", "weights", "columnWidths", "meshTriangles", "cells", "dash", "pattern"]

    static func isNumber(_ v: Any) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) != CFBooleanGetTypeID()
    }

    /// Turns `[x, y]` / `[x, y, z]` arrays into `{x, y(, z)}` objects, recursively.
    static func normalize(_ v: Any, key: String? = nil) -> Any {
        if let k = key, plainNumberArrays.contains(k) { return v }
        if let a = v as? [Any] {
            if (2...3).contains(a.count), a.allSatisfy(isNumber) {
                let n = a.map { ($0 as! NSNumber).doubleValue }
                return n.count == 2 ? ["x": n[0], "y": n[1]] : ["x": n[0], "y": n[1], "z": n[2]]
            }
            return a.map { normalize($0, key: key) }
        }
        if let d = v as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, x) in d { out[k] = normalize(x, key: k) }
            return out
        }
        return v
    }

    /// Polyline vertices may be points (`{x,y}`, `[x,y]`, `[x,y,bulge]`) or `{p, bulge}`.
    static func vertices(_ v: Any) -> Any {
        guard let a = v as? [Any] else { return v }
        return a.map { item -> Any in
            guard let d = item as? [String: Any] else { return item }
            if d["p"] != nil { var o = d; if o["bulge"] == nil { o["bulge"] = 0 }; return o }
            if let x = d["x"], let y = d["y"] { return ["p": ["x": x, "y": y], "bulge": d["bulge"] ?? d["z"] ?? 0] }
            return item
        }
    }

    static let geometryDefaults: [String: Geometry] = [
        "point": .point(.zero), "line": .line(LineGeom(.zero, .zero)), "circle": .circle(CircleGeom(.zero, 1)),
        "arc": .arc(ArcGeom(.zero, 1, 0, .pi)), "ellipse": .ellipse(EllipseGeom(center: .zero, majorAxis: Vec2(1, 0), ratio: 0.5)),
        "polyline": .polyline(PolylineGeom([])), "spline": .spline(SplineGeom(controlPoints: [])),
        "text": .text(TextGeom(position: .zero, height: 250, content: "")), "dimension": .dimension(DimensionGeom(kind: .linear, points: [])),
        "hatch": .hatch(HatchGeom(loops: [])), "insert": .insert(InsertGeom(block: "", position: .zero)),
        "leader": .leader(LeaderGeom(points: [], text: "")), "image": .image(ImageGeom(path: "", origin: .zero, size: Vec2(1000, 1000))),
        "table": .table(TableGeom(origin: .zero, columnWidths: [], rowHeight: 500, cells: [])),
        "solid": .solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 1000))),
    ]
    static let elementDefaults: [String: BIMGeometry] = [
        "wall": .wall(WallGeom(start: .zero, end: .zero)), "slab": .slab(SlabGeom(boundary: [])), "column": .column(ColumnGeom(position: .zero)),
        "beam": .beam(BeamGeom(start: .zero, end: .zero)),
        "door": .opening(OpeningGeom(kind: .door, hostWall: 0, offset: 0, width: 900, height: 2100)),
        "window": .opening(OpeningGeom(kind: .window, hostWall: 0, offset: 0, width: 1200, height: 1200, sill: 900)),
        "opening": .opening(OpeningGeom(kind: .opening, hostWall: 0, offset: 0, width: 900, height: 2100)),
        "roof": .roof(RoofGeom(boundary: [])), "stair": .stair(StairGeom(start: .zero)), "railing": .railing(RailingGeom(path: [])),
        "space": .space(SpaceGeom(boundary: [])), "curtainWall": .curtainWall(CurtainWallGeom(start: .zero, end: .zero)),
        "component": .component(ComponentGeom(position: .zero)), "grid": .gridLine(GridLineGeom(start: .zero, end: .zero, label: "A")),
    ]
    static let typeAliases = ["pline": "polyline", "lwpolyline": "polyline", "mtext": "text", "room": "space", "gridline": "grid",
                              "curtainwall": "curtainWall", "block": "insert", "box": "solid"]

    static func mergedWithDefaults(_ raw: [String: Any], defaults: (String) -> Any?) throws -> [String: Any] {
        guard var type = raw["type"] as? String else { throw fail("object needs a \"type\"") }
        type = typeAliases[type.lowercased()] ?? type
        guard let def = defaults(type) as? [String: Any] else { throw fail("unknown type \"\(type)\"") }
        var d = normalize(raw) as! [String: Any]
        d["type"] = def["type"]
        if type == "polyline", d["vertices"] == nil, let pts = d["points"] { d["vertices"] = pts }
        if type == "text", d["content"] == nil, let t = d["text"] { d["content"] = t }
        if let v = d["vertices"] { d["vertices"] = vertices(v) }
        if let loops = d["loops"] as? [Any] { d["loops"] = loops.map { vertices($0) } }
        var out = def
        for (k, v) in d { out[k] = v }
        return out
    }

    static func geometry(from raw: [String: Any]) throws -> Geometry {
        let m = try mergedWithDefaults(raw) { t in geometryDefaults[t].map { object($0) } }
        return try decode(Geometry.self, from: m)
    }

    static func bimGeometry(from raw: [String: Any]) throws -> BIMGeometry {
        let m = try mergedWithDefaults(raw) { t in elementDefaults[t].map { object($0) } }
        return try decode(BIMGeometry.self, from: m)
    }

    static func stringDict(_ v: Any?) -> [String: String] {
        guard let d = v as? [String: Any] else { return [:] }
        return d.mapValues { "\($0)" }
    }
    static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }
    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue ?? (v as? String).flatMap(Int.init) }
    static func ids(_ v: Any?) -> [EntityID] {
        if let n = int(v) { return [n] }
        return (v as? [Any])?.compactMap { int($0) } ?? []
    }
    static func point(_ v: Any?) -> Vec2? {
        if let a = v as? [Any], a.count >= 2, let x = double(a[0]), let y = double(a[1]) { return Vec2(x, y) }
        if let d = v as? [String: Any], let x = double(d["x"]), let y = double(d["y"]) { return Vec2(x, y) }
        return nil
    }
    static func points(_ v: Any?) -> [Vec2] { (v as? [Any])?.compactMap { point($0) } ?? [] }

    /// An entity from `{type, ...geometry}` or `{geometry: {...}, layer, color, linetype, lineweight, props}`.
    static func entity(from obj: Any, doc: ArchiDocument) throws -> Entity {
        guard let d = obj as? [String: Any] else { throw fail("entity must be an object") }
        let g = try geometry(from: (d["geometry"] as? [String: Any]) ?? d)
        var e = Entity(layer: d["layer"] as? String ?? doc.currentLayer, geometry: g)
        if let c = d["color"] { e.color = ColorRef.parse("\(c)") ?? .byLayer }
        e.linetype = d["linetype"] as? String
        e.lineweight = double(d["lineweight"])
        e.props = stringDict(d["props"])
        return e
    }

    struct ElementSpec { var geometry: BIMGeometry; var level: Int?; var layer: String?; var material: String?; var name: String; var props: [String: String] }

    static func element(from obj: Any, doc: ArchiDocument) throws -> ElementSpec {
        guard let d = obj as? [String: Any] else { throw fail("element must be an object") }
        let g = try bimGeometry(from: (d["geometry"] as? [String: Any]) ?? d)
        if case .opening(let o) = g {
            guard let host = doc.element(o.hostWall), case .wall = host.geometry else { throw fail("hostWall \(o.hostWall) is not a wall") }
        }
        let level = int(d["level"])
        if let l = level, doc.level(l) == nil { throw fail("level \(l) does not exist") }
        return ElementSpec(geometry: g, level: level, layer: d["layer"] as? String, material: d["material"] as? String,
                           name: d["name"] as? String ?? "", props: stringDict(d["props"]))
    }

    @discardableResult
    static func add(_ s: ElementSpec, to doc: inout ArchiDocument) -> EntityID {
        let id = doc.addElement(s.geometry, level: s.level, layer: s.layer, material: s.material, name: s.name)
        if !s.props.isEmpty, let i = doc.elementIndex(id) { doc.elements[i].props = s.props }
        return id
    }

    /// Applies a patch to an entity or element. Top-level keys other than the object's own
    /// properties are treated as geometry fields.
    static func patch(_ doc: inout ArchiDocument, id: EntityID, _ p: [String: Any]) throws {
        if let i = doc.entityIndex(id) {
            var e = doc.entities[i]
            var g = object(e.geometry) as? [String: Any] ?? [:]
            var gChanged = false
            for (k, v) in p {
                switch k {
                case "id": continue
                case "layer": if let s = v as? String { doc.ensureLayer(s); e.layer = s }
                case "color": e.color = ColorRef.parse("\(v)") ?? e.color
                case "linetype": e.linetype = v is NSNull ? nil : v as? String
                case "lineweight": e.lineweight = double(v)
                case "props": for (pk, pv) in stringDict(v) { e.props[pk] = pv }
                case "geometry": if let gd = v as? [String: Any] { for (gk, gv) in gd { g[gk] = gv }; gChanged = true }
                default: g[k] = v; gChanged = true
                }
            }
            if gChanged { e.geometry = try geometry(from: g) }
            doc.entities[i] = e
        } else if let i = doc.elementIndex(id) {
            var el = doc.elements[i]
            var g = object(el.geometry) as? [String: Any] ?? [:]
            var gChanged = false
            for (k, v) in p {
                switch k {
                case "id": continue
                case "level": if let l = int(v) { guard doc.level(l) != nil else { throw fail("level \(l) does not exist") }; el.level = l }
                case "name": el.name = "\(v)"
                case "layer": if let s = v as? String { doc.ensureLayer(s); el.layer = s }
                case "material": el.material = v is NSNull ? nil : v as? String
                case "props": for (pk, pv) in stringDict(v) { el.props[pk] = pv }
                case "geometry": if let gd = v as? [String: Any] { for (gk, gv) in gd { g[gk] = gv }; gChanged = true }
                default: g[k] = v; gChanged = true
                }
            }
            if gChanged { el.geometry = try bimGeometry(from: g) }
            doc.elements[i] = el
        } else {
            throw fail("no object with id \(id)")
        }
    }

    static func entities(_ doc: ArchiDocument, type: String?, layer: String?) -> [Any] {
        let t = type.map { typeAliases[$0.lowercased()] ?? $0.lowercased() }
        return doc.entities.filter { e in
            (t == nil || e.typeName == t) && (layer == nil || e.layer.caseInsensitiveCompare(layer!) == .orderedSame)
        }.map { object($0) }
    }

    static func elements(_ doc: ArchiDocument, type: String?, level: Int?) -> [Any] {
        let t = type.map { typeAliases[$0.lowercased()] ?? $0 }
        return doc.elements.filter { e in
            (t == nil || e.typeName.caseInsensitiveCompare(t!) == .orderedSame) && (level == nil || e.level == level)
        }.map { object($0) }
    }

    static func documentJSON(_ doc: ArchiDocument) -> Any {
        guard let d = try? ArchiFile.encode(doc), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return object(doc) }
        return o["document"] ?? o
    }

    static func summary(_ doc: ArchiDocument) -> [String: Any] {
        var byType: [String: Int] = [:]
        for e in doc.entities { byType[e.typeName, default: 0] += 1 }
        var byElement: [String: Int] = [:]
        for e in doc.elements { byElement[e.typeName, default: 0] += 1 }
        let b = GeometryOps.bounds(of: doc)
        return [
            "project": object(doc.info), "units": doc.units.rawValue, "currentLayer": doc.currentLayer, "currentLevel": doc.currentLevel,
            "layers": doc.layers.map { $0.name }, "levels": doc.levels.map { ["id": $0.id, "name": $0.name, "elevation": $0.elevation, "height": $0.height] },
            "entityCount": doc.entities.count, "entitiesByType": byType, "elementCount": doc.elements.count, "elementsByType": byElement,
            "layouts": doc.layouts.map { $0.name }, "materials": doc.materials.map { $0.name }, "wallTypes": doc.wallTypes.map { $0.name },
            "bounds": b.isEmpty ? NSNull() : ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]] as Any,
        ]
    }
}

// MARK: - Script engine

struct ScriptResult {
    var output: [String]
    var value: String?
    var error: String?
}

/// JavaScriptCore scripting with an `archi` object. Scripts run on a background queue;
/// every model access hops synchronously to the main actor, so the UI stays responsive
/// and each mutating call is one undo step.
final class ScriptEngine {
    private let queue = DispatchQueue(label: "com.oanarina.archi.script", qos: .userInitiated)
    private var context: JSContext!
    private weak var model: AppModel?
    private var output: [String] = []
    private var lastException: String?
    /// Source being evaluated (for error excerpts).
    private var currentSource = ""
    /// File name used for commands registered by console scripts (script.<name> plugin id).
    var scriptName = "console.js"
    /// Called on the main thread for every printed line.
    var onOutput: ((String) -> Void)?

    init(model: AppModel) {
        self.model = model
        queue.sync { self.setupContext() }
    }

    /// Watches the document window for the event hooks (called once by `forModel`).
    @MainActor func startHooks(_ model: AppModel) {
        hookSink = model.$revision.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.checkEvents() }
        }
    }

    func reset() { queue.async { self.setupContext() } }

    // MARK: Event hooks (SCR-007)

    /// Events scripts can subscribe to with archi.on(name, fn).
    static let hookEvents = ["selectionChanged", "documentChanged", "elementAdded", "elementRemoved", "saved", "commandEnded"]
    /// Handlers by event (touched on the script queue only).
    private var handlers: [String: [JSValue]] = [:]
    /// Events with at least one handler (written on the script queue, read on the main thread; never read with
    /// queue.sync from the main thread, which could deadlock against a script waiting for the main thread).
    private let hookLock = NSLock()
    private var hookedStore = Set<String>()
    private var hooked: Set<String> {
        get { hookLock.lock(); defer { hookLock.unlock() }; return hookedStore }
        set { hookLock.lock(); hookedStore = newValue; hookLock.unlock() }
    }
    private var hookSink: AnyCancellable?
    private var lastSelection: Set<EntityID>?
    private var lastChange = -1
    private var lastIDs: Set<EntityID> = []
    private var lastDirty = false
    private var lastCommand: String?
    private var dispatching = false

    /// Compares the document with the last seen state and calls the subscribed handlers (on the script queue).
    /// Changes made by the handlers themselves do not fire events again.
    @MainActor func checkEvents() {
        guard let m = model else { return }
        let ed = m.editor
        let hk = hooked
        guard !hk.isEmpty else { lastSelection = nil; lastChange = -1; return }
        var fire: [(String, Any)] = []
        let sel = ed.selection
        if let last = lastSelection, last != sel, hk.contains("selectionChanged") { fire.append(("selectionChanged", sel.sorted())) }
        if lastChange >= 0 && ed.changeCount != lastChange {
            if hk.contains("documentChanged") { fire.append(("documentChanged", ["changeCount": ed.changeCount, "entities": ed.doc.entities.count, "elements": ed.doc.elements.count])) }
            if hk.contains("elementAdded") || hk.contains("elementRemoved") {
                let ids = Set(ed.doc.entities.map(\.id)).union(ed.doc.elements.map(\.id))
                let added = ids.subtracting(lastIDs).sorted(), removed = lastIDs.subtracting(ids).sorted()
                if !added.isEmpty, hk.contains("elementAdded") { fire.append(("elementAdded", added)) }
                if !removed.isEmpty, hk.contains("elementRemoved") { fire.append(("elementRemoved", removed)) }
                lastIDs = ids
            }
        } else if lastChange < 0, hk.contains("elementAdded") || hk.contains("elementRemoved") {
            lastIDs = Set(ed.doc.entities.map(\.id)).union(ed.doc.elements.map(\.id))
        }
        if lastDirty && !ed.isDirty && ed.fileURL != nil && hk.contains("saved") { fire.append(("saved", ed.fileURL?.path ?? "")) }
        let cmd = ed.activeCommand?.name
        if let c = lastCommand, cmd == nil, hk.contains("commandEnded") { fire.append(("commandEnded", c)) }
        lastSelection = sel; lastChange = ed.changeCount; lastDirty = ed.isDirty; lastCommand = cmd
        guard !fire.isEmpty, !dispatching else { return }
        dispatching = true
        queue.async {
            for (ev, arg) in fire {
                for h in self.handlers[ev] ?? [] {
                    self.lastException = nil
                    _ = h.call(withArguments: [arg])
                    if let e = self.lastException { self.emit("✖ in \(ev) handler: \(e)") }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Re-baseline after the handlers so their own edits do not trigger another round.
                    if let ed = self.model?.editor {
                        self.lastSelection = ed.selection; self.lastChange = ed.changeCount; self.lastDirty = ed.isDirty; self.lastCommand = ed.activeCommand?.name
                        if !self.hooked.isDisjoint(with: ["elementAdded", "elementRemoved"]) { self.lastIDs = Set(ed.doc.entities.map(\.id)).union(ed.doc.elements.map(\.id)) }
                    }
                    self.dispatching = false
                }
            }
        }
    }

    /// Calls a global script function with one argument on the script queue (buttons of script panels).
    func callGlobal(_ name: String, argument: Any) {
        queue.async {
            guard let f = self.context.objectForKeyedSubscript(name), f.isObject, f.hasProperty("call") else { self.emit("✖ No function \(name)() in the script."); return }
            self.lastException = nil
            _ = f.call(withArguments: [argument])
        }
    }

    /// Evaluates pure JavaScript synchronously (no calls back into the document: those would wait for the main
    /// thread). Used by the self-tests to register hooks and read results.
    func evaluateNow(_ code: String) -> String? {
        queue.sync {
            lastException = nil
            let v = context.evaluateScript(code)
            if lastException != nil { return nil }
            return v.flatMap { $0.isUndefined ? nil : $0.toString() }
        }
    }

    func evaluate(_ code: String) async -> ScriptResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ScriptResult, Never>) in
            queue.async {
                self.output = []
                self.lastException = nil
                self.currentSource = code
                let t0 = Date()
                var v = self.context.evaluateScript(code)
                // Running the same script again redeclares its top-level const/let in the shared context
                // ("Can't create duplicate variable"). Give the rerun its own block scope instead of failing.
                if let e = self.lastException, e.contains("duplicate variable"), code.contains("\n") {
                    self.output = []
                    self.lastException = nil
                    v = self.context.evaluateScript("{\n" + code + "\n}")
                }
                let ms = Date().timeIntervalSince(t0) * 1000
                if self.lastException == nil && code.contains("\n") { self.emit("✓ finished in \(ms < 10 ? String(format: "%.1f", ms) : String(Int(ms.rounded()))) ms") }
                var value: String?
                if let v, !v.isUndefined, self.lastException == nil { value = self.describe(v) }
                cont.resume(returning: ScriptResult(output: self.output, value: value, error: self.lastException))
            }
        }
    }

    // MARK: Plumbing

    private final class Box<T> { var value: T; init(_ v: T) { value = v } }

    /// Runs `body` on the main actor and waits for it. Only call from the script queue.
    private func onMain<T>(_ body: @MainActor () throws -> T) throws -> T {
        let box = Box<Result<T, Error>?>(nil)
        DispatchQueue.main.sync { MainActor.assumeIsolated { box.value = Result { try body() } } }
        return try box.value!.get()
    }

    private func emit(_ line: String) {
        output.append(line)
        let cb = onOutput
        DispatchQueue.main.async { cb?(line) }
    }

    private func describe(_ v: JSValue) -> String {
        if v.isObject && !v.isInstance(of: NSClassFromString("NSDate")),
           let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [v, NSNull(), 2]), json.isString {
            return json.toString()
        }
        return v.toString()
    }

    private func throwJS(_ message: String) {
        guard let ctx = JSContext.current() else { return }
        ctx.exception = JSValue(newErrorFromMessage: message, in: ctx)
    }

    /// Wraps an API call: converts Swift errors into JS exceptions and results into JS values.
    private func call(_ body: () throws -> Any?) -> Any? {
        do { return try body() ?? NSNull() }
        catch { throwJS((error as? LocalizedError)?.errorDescription ?? "\(error)"); return nil }
    }

    private func arg(_ v: JSValue?) -> Any? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        return v.toObject()
    }

    @MainActor private func editor() throws -> Editor {
        guard let m = model else { throw ArchiJSON.fail("the document was closed") }
        return m.editor
    }

    // MARK: API

    private func setupContext() {
        handlers = [:]; hooked = []
        let ctx = JSContext()!
        ctx.name = "Oanarina Archi Tool"
        ctx.exceptionHandler = { [weak self] _, ex in
            guard let self, let ex else { return }
            var msg = ex.toString() ?? "Error"
            var lineNo: Int?, col: Int?
            if let line = ex.objectForKeyedSubscript("line"), line.isNumber { lineNo = Int(line.toInt32()) }
            if let c = ex.objectForKeyedSubscript("column"), c.isNumber { col = Int(c.toInt32()) }
            if let l = lineNo { msg += " (line \(l)\(col.map { ", column \($0)" } ?? ""))" }
            self.lastException = msg
            self.emit("✖ " + msg)
            // Debugger output: the offending source line with a caret, then the JavaScript call stack.
            if let l = lineNo { for x in ScriptDiagnostics.excerpt(source: self.currentSource, line: l, column: col) { self.emit("✖ " + x) } }
            let stack = ex.objectForKeyedSubscript("stack")?.toString() ?? ""
            for f in ScriptDiagnostics.frames(stack) { self.emit("✖    at " + f) }
        }
        let archi = JSValue(newObjectIn: ctx)!
        func def<F>(_ name: String, _ block: F) { archi.setObject(unsafeBitCast(block, to: AnyObject.self), forKeyedSubscript: name as NSString) }

        let printFn: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            self?.emit(args.map { self?.describe($0) ?? "" }.joined(separator: " "))
        }
        def("print", printFn)
        let console = JSValue(newObjectIn: ctx)!
        for n in ["log", "info", "debug"] { console.setObject(unsafeBitCast(printFn, to: AnyObject.self), forKeyedSubscript: n as NSString) }
        let warnFn: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            self?.emit("⚠ " + args.map { self?.describe($0) ?? "" }.joined(separator: " "))
        }
        let errorFn: @convention(block) () -> Void = { [weak self] in
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            self?.emit("✖ " + args.map { self?.describe($0) ?? "" }.joined(separator: " "))
        }
        console.setObject(unsafeBitCast(warnFn, to: AnyObject.self), forKeyedSubscript: "warn" as NSString)
        console.setObject(unsafeBitCast(errorFn, to: AnyObject.self), forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
        ctx.evaluateScript(ScriptDiagnostics.consolePrelude)

        let run: @convention(block) (JSValue) -> Any? = { [weak self] v in
            guard let self else { return nil }
            return self.call {
                let text = v.isUndefined ? "" : v.toString() ?? ""
                return try self.runCommands(text)
            }
        }
        def("run", run)

        // Event hooks: archi.on("selectionChanged", function(ids) {...}), archi.off(name).
        def("on", { [weak self] (name: JSValue, fn: JSValue) -> Any? in
            guard let self else { return nil }
            let n = name.toString() ?? ""
            guard ScriptEngine.hookEvents.contains(n) else { self.throwJS("unknown event '\(n)' (\(ScriptEngine.hookEvents.joined(separator: ", ")))"); return nil }
            guard fn.isObject, fn.hasProperty("call") else { self.throwJS("archi.on needs a function"); return nil }
            self.handlers[n, default: []].append(fn)
            self.hooked.insert(n)
            return self.handlers[n]?.count ?? 0
        } as @convention(block) (JSValue, JSValue) -> Any?)
        // Script-defined UI panels (SCR-008).
        def("panel", { [weak self] (v: JSValue) -> Any? in
            guard let self else { return nil }
            let o = self.arg(v) ?? NSNull()
            return self.call {
                let spec = try ScriptPanelSpec.parse(o)
                return try self.onMain { () -> Any in
                    guard let m = self.model else { throw ArchiJSON.fail("the document was closed") }
                    _ = ScriptPanels.show(spec, model: m)
                    return spec.title
                }
            }
        } as @convention(block) (JSValue) -> Any?)
        def("off", { [weak self] (name: JSValue) -> Any? in
            guard let self else { return nil }
            if name.isUndefined { self.handlers = [:]; self.hooked = [] } else if let n = name.toString() { self.handlers[n] = nil; self.hooked.remove(n) }
            return true
        } as @convention(block) (JSValue) -> Any?)

        def("doc", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in ArchiJSON.documentJSON(try self!.editor().doc) } }
        } as @convention(block) () -> Any?)

        def("summary", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in ArchiJSON.summary(try self!.editor().doc) } }
        } as @convention(block) () -> Any?)

        def("entities", { [weak self] (f: JSValue) -> Any? in
            guard let self else { return nil }
            let filter = self.arg(f) as? [String: Any]
            return self.call { try self.onMain { () -> Any in ArchiJSON.entities(try self.editor().doc, type: filter?["type"] as? String, layer: filter?["layer"] as? String) } }
        } as @convention(block) (JSValue) -> Any?)

        def("elements", { [weak self] (f: JSValue) -> Any? in
            guard let self else { return nil }
            let filter = self.arg(f) as? [String: Any]
            return self.call { try self.onMain { () -> Any in ArchiJSON.elements(try self.editor().doc, type: filter?["type"] as? String, level: ArchiJSON.int(filter?["level"])) } }
        } as @convention(block) (JSValue) -> Any?)

        def("get", { [weak self] (idv: JSValue) -> Any? in
            guard let self else { return nil }
            let id = Int(idv.toInt32())
            return self.call { try self.onMain { () -> Any in
                let d = try self.editor().doc
                if let e = d.entity(id) { return ArchiJSON.object(e) }
                if let e = d.element(id) { return ArchiJSON.object(e) }
                return NSNull()
            } }
        } as @convention(block) (JSValue) -> Any?)

        def("add", { [weak self] (o: JSValue) -> Any? in
            guard let self else { return nil }
            let obj = self.arg(o)
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                let list = (obj as? [Any]) ?? [obj as Any]
                var ids: [EntityID] = []
                try ed.transaction("Script Add") { d in
                    for item in list { ids.append(d.add(try ArchiJSON.entity(from: item, doc: d))) }
                }
                return obj is [Any] ? ids as Any : (ids.first as Any)
            } }
        } as @convention(block) (JSValue) -> Any?)

        def("addElement", { [weak self] (o: JSValue) -> Any? in
            guard let self else { return nil }
            let obj = self.arg(o)
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                let list = (obj as? [Any]) ?? [obj as Any]
                var ids: [EntityID] = []
                try ed.transaction("Script Add Element") { d in
                    for item in list { ids.append(ArchiJSON.add(try ArchiJSON.element(from: item, doc: d), to: &d)) }
                }
                return obj is [Any] ? ids as Any : (ids.first as Any)
            } }
        } as @convention(block) (JSValue) -> Any?)

        // Node graphs (visual programming) from scripts: evaluate a graph object, or bake its output into the drawing.
        func graph(_ v: JSValue) throws -> NodeGraph {
            guard let o = self.arg(v), JSONSerialization.isValidJSONObject(o) else { throw ArchiJSON.fail("expected a node graph object") }
            do { return try JSONDecoder().decode(NodeGraph.self, from: try JSONSerialization.data(withJSONObject: o)) }
            catch { throw ArchiJSON.fail("not a node graph: \(error.localizedDescription)") }
        }
        def("evaluateGraph", { [weak self] (g: JSValue) -> Any? in
            guard let self else { return nil }
            return self.call {
                let gr = try graph(g)
                return try self.onMain { () -> Any in
                    let ev = gr.evaluate()
                    return ["objects": ev.output.count, "elements": ev.elementOutput.count,
                            "errors": Dictionary(uniqueKeysWithValues: ev.errors.map { ("\($0.key)", $0.value) }),
                            "geometry": ev.output.map { ArchiJSON.object($0) }] as [String: Any]
                }
            }
        } as @convention(block) (JSValue) -> Any?)
        def("bakeGraph", { [weak self] (g: JSValue) -> Any? in
            guard let self else { return nil }
            return self.call {
                let gr = try graph(g)
                return try self.onMain { () -> Any in
                    let ev = gr.evaluate()
                    var ids: [EntityID] = []
                    try self.editor().transaction("Bake Node Graph") { d in ids = NodeGraphBake.bake(ev.output, elements: ev.elementOutput, into: &d) }
                    return ids
                }
            }
        } as @convention(block) (JSValue) -> Any?)

        def("update", { [weak self] (idv: JSValue, p: JSValue) -> Any? in
            guard let self else { return nil }
            let id = Int(idv.toInt32()), patch = self.arg(p) as? [String: Any] ?? [:]
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                try ed.transaction("Script Update") { d in try ArchiJSON.patch(&d, id: id, patch) }
                return ed.doc.entity(id).map { ArchiJSON.object($0) } ?? ed.doc.element(id).map { ArchiJSON.object($0) } ?? NSNull()
            } }
        } as @convention(block) (JSValue, JSValue) -> Any?)

        def("remove", { [weak self] (v: JSValue) -> Any? in
            guard let self else { return nil }
            let ids = Set(ArchiJSON.ids(self.arg(v)))
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                let before = ed.doc.entities.count + ed.doc.elements.count
                ed.transaction("Script Delete") { $0.remove(ids: ids) }
                ed.selection.subtract(ids)
                return before - ed.doc.entities.count - ed.doc.elements.count
            } }
        } as @convention(block) (JSValue) -> Any?)

        def("select", { [weak self] (v: JSValue) -> Any? in
            guard let self else { return nil }
            let ids = ArchiJSON.ids(self.arg(v))
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                ed.selection = Set(ids.filter { ed.doc.contains($0) })
                return Array(ed.selection).sorted()
            } }
        } as @convention(block) (JSValue) -> Any?)

        def("selection", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in Array(try self!.editor().selection).sorted() } }
        } as @convention(block) () -> Any?)

        def("setVar", { [weak self] (n: JSValue, v: JSValue) -> Any? in
            guard let self else { return nil }
            let name = n.toString() ?? "", value = v.toString() ?? ""
            return self.call { try self.onMain { () -> Any in
                try self.editor().transaction("Set Variable") { $0.setVariable(name, value) }
                return value
            } }
        } as @convention(block) (JSValue, JSValue) -> Any?)

        def("getVar", { [weak self] (n: JSValue) -> Any? in
            guard let self else { return nil }
            let name = n.toString() ?? ""
            return self.call { try self.onMain { () -> Any in (try self.editor().doc.variable(name)).map { $0 as Any } ?? NSNull() } }
        } as @convention(block) (JSValue) -> Any?)

        def("layers", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in ArchiJSON.object(try self!.editor().doc.layers) } }
        } as @convention(block) () -> Any?)

        def("levels", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in ArchiJSON.object(try self!.editor().doc.levels) } }
        } as @convention(block) () -> Any?)

        // Building helpers.
        def("wall", { [weak self] (x1: JSValue, y1: JSValue, x2: JSValue, y2: JSValue, o: JSValue) -> Any? in
            guard let self else { return nil }
            let a = Vec2(x1.toDouble(), y1.toDouble()), b = Vec2(x2.toDouble(), y2.toDouble())
            let opts = self.arg(o) as? [String: Any] ?? [:]
            return self.call { try self.onMain { () -> Any in
                let ed = try self.editor()
                guard a.distance(to: b) > 1e-6 else { throw ArchiJSON.fail("wall start and end coincide") }
                let s = ed.settings
                let w = WallGeom(start: a, end: b, thickness: ArchiJSON.double(opts["thickness"]) ?? s.wallThickness,
                                 height: ArchiJSON.double(opts["height"]) ?? s.wallHeight, baseOffset: ArchiJSON.double(opts["baseOffset"]) ?? 0,
                                 justification: WallJustification(rawValue: opts["justification"] as? String ?? "") ?? s.wallJustification,
                                 bulge: ArchiJSON.double(opts["bulge"]) ?? 0, wallType: opts["wallType"] as? String)
                return try self.addElement(ed, .wall(w), opts, label: "Script Wall")
            } }
        } as @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue) -> Any?)

        func opening(_ kind: OpeningKind) -> @convention(block) (JSValue, JSValue, JSValue) -> Any? {
            return { [weak self] (w: JSValue, off: JSValue, o: JSValue) -> Any? in
                guard let self else { return nil }
                let wallID = Int(w.toInt32()), offset = off.toDouble()
                let opts = self.arg(o) as? [String: Any] ?? [:]
                return self.call { try self.onMain { () -> Any in
                    let ed = try self.editor()
                    guard let host = ed.doc.element(wallID), case .wall(let wg) = host.geometry else { throw ArchiJSON.fail("\(wallID) is not a wall") }
                    let isWin = kind == .window
                    let width = ArchiJSON.double(opts["width"]) ?? (isWin ? 1200 : 900)
                    guard offset - width / 2 >= -1e-6, offset + width / 2 <= wg.length + 1e-6 else {
                        throw ArchiJSON.fail("opening does not fit in the wall (length \(fmt(wg.length)))")
                    }
                    var g = OpeningGeom(kind: kind, hostWall: wallID, offset: offset, width: width,
                                        height: ArchiJSON.double(opts["height"]) ?? (isWin ? 1200 : 2100),
                                        sill: ArchiJSON.double(opts["sill"]) ?? (isWin ? 900 : 0))
                    g.flipHand = opts["flipHand"] as? Bool ?? false
                    g.flipFacing = opts["flipFacing"] as? Bool ?? false
                    if let s = opts["style"] as? String {
                        if let d = DoorStyle(rawValue: s) { g.doorStyle = d }
                        if let w = WindowStyle(rawValue: s) { g.windowStyle = w }
                    }
                    var o2 = opts; o2["level"] = host.level
                    return try self.addElement(ed, .opening(g), o2, label: "Script \(kind.rawValue.capitalized)")
                } }
            }
        }
        def("door", opening(.door))
        def("window", opening(.window))
        def("opening", opening(.opening))

        def("slab", { [weak self] (p: JSValue, o: JSValue) -> Any? in
            guard let self else { return nil }
            let pts = ArchiJSON.points(self.arg(p)), opts = self.arg(o) as? [String: Any] ?? [:]
            return self.call { try self.onMain { () -> Any in
                guard pts.count >= 3 else { throw ArchiJSON.fail("a slab needs at least 3 points") }
                let g = SlabGeom(boundary: pts, holes: (opts["holes"] as? [Any])?.map { ArchiJSON.points($0) } ?? [],
                                 thickness: ArchiJSON.double(opts["thickness"]) ?? 200, topOffset: ArchiJSON.double(opts["topOffset"]) ?? 0)
                return try self.addElement(try self.editor(), .slab(g), opts, label: "Script Slab")
            } }
        } as @convention(block) (JSValue, JSValue) -> Any?)

        def("room", { [weak self] (p: JSValue, n: JSValue, o: JSValue) -> Any? in
            guard let self else { return nil }
            let pts = ArchiJSON.points(self.arg(p)), name = n.isUndefined ? "Room" : (n.toString() ?? "Room")
            let opts = self.arg(o) as? [String: Any] ?? [:]
            return self.call { try self.onMain { () -> Any in
                guard pts.count >= 3 else { throw ArchiJSON.fail("a room needs at least 3 points") }
                let g = SpaceGeom(boundary: pts, name: name, number: opts["number"].map { "\($0)" } ?? "", height: ArchiJSON.double(opts["height"]) ?? 2700)
                return try self.addElement(try self.editor(), .space(g), opts, label: "Script Room")
            } }
        } as @convention(block) (JSValue, JSValue, JSValue) -> Any?)

        def("column", { [weak self] (x: JSValue, y: JSValue, o: JSValue) -> Any? in
            guard let self else { return nil }
            let p = Vec2(x.toDouble(), y.toDouble()), opts = self.arg(o) as? [String: Any] ?? [:]
            return self.call { try self.onMain { () -> Any in
                let size = ArchiJSON.double(opts["size"])
                let g = ColumnGeom(position: p, width: ArchiJSON.double(opts["width"]) ?? size ?? 300, depth: ArchiJSON.double(opts["depth"]) ?? size ?? 300,
                                   height: ArchiJSON.double(opts["height"]) ?? 3000, rotation: rad(ArchiJSON.double(opts["rotation"]) ?? 0),
                                   round: opts["round"] as? Bool ?? false)
                return try self.addElement(try self.editor(), .column(g), opts, label: "Script Column")
            } }
        } as @convention(block) (JSValue, JSValue, JSValue) -> Any?)

        def("undo", { [weak self] () -> Any? in self?.call { try self?.onMain { () -> Any in try self!.editor().undo(); return true } } } as @convention(block) () -> Any?)
        def("redo", { [weak self] () -> Any? in self?.call { try self?.onMain { () -> Any in try self!.editor().redo(); return true } } } as @convention(block) () -> Any?)
        def("commands", { [weak self] () -> Any? in
            self?.call { try self?.onMain { () -> Any in CommandRegistry.shared.sorted.map { ["name": $0.name, "aliases": $0.aliases, "category": $0.category, "summary": $0.summary] } } }
        } as @convention(block) () -> Any?)

        // archi.registerCommand(name, fn | "fnName", {aliases, summary, category, modifies}) — SCR-006: the script
        // becomes a run-time plugin (PluginRegistry) and the command re-evaluates it and calls the function.
        def("registerCommand", { [weak self] (n: JSValue, f: JSValue, o: JSValue) -> Any? in
            guard let self else { return nil }
            guard n.isString, let name = n.toString()?.uppercased(), !name.isEmpty else { self.throwJS("registerCommand(name, function[, options]) needs a command name"); return nil }
            var fname = ""
            if f.isString { fname = f.toString() ?? "" } else if f.isObject, let nm = f.objectForKeyedSubscript("name"), nm.isString { fname = nm.toString() ?? "" }
            guard !fname.isEmpty else { self.throwJS("registerCommand: pass a named global function (or its name) for \(name)"); return nil }
            let opts = (o.isObject ? o.toObject() as? [String: Any] : nil) ?? [:]
            let cmd = PluginCommand(name: name, aliases: ((opts["aliases"] as? [Any])?.compactMap { $0 as? String } ?? []).map { $0.uppercased() },
                                    summary: opts["summary"] as? String ?? "", function: fname,
                                    category: opts["category"] as? String ?? "Scripts", modifies: opts["modifies"] as? Bool ?? true)
            // Plugin runs append a call after a marker; keep only the script itself as the command's source.
            let source = self.currentSource.components(separatedBy: AppPlugins.callMarker).first ?? self.currentSource
            let url = URL(fileURLWithPath: self.scriptName)
            return self.call { try self.onMain { () -> Any in try PluginRegistry.shared.registerScriptCommand(cmd, source: source, sourceURL: url) } }
        } as @convention(block) (JSValue, JSValue, JSValue) -> Any?)

        ctx.setObject(archi, forKeyedSubscript: "archi" as NSString)
        context = ctx
    }

    @MainActor private func addElement(_ ed: Editor, _ g: BIMGeometry, _ opts: [String: Any], label: String) throws -> Any {
        let level = ArchiJSON.int(opts["level"])
        if let l = level, ed.doc.level(l) == nil { throw ArchiJSON.fail("level \(l) does not exist") }
        var id = 0
        ed.transaction(label) { d in
            id = ArchiJSON.add(ArchiJSON.ElementSpec(geometry: g, level: level, layer: opts["layer"] as? String, material: opts["material"] as? String,
                                                     name: opts["name"] as? String ?? "", props: ArchiJSON.stringDict(opts["props"])), to: &d)
        }
        return id
    }

    /// Runs command lines (newline-separated) to completion on the main actor, blocking the script queue.
    private func runCommands(_ text: String) throws -> [String] {
        var all: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let sem = DispatchSemaphore(value: 0)
            let box = Box<[String]>([])
            let m = model
            DispatchQueue.main.async {
                Task { @MainActor in
                    if let ed = m?.editor {
                        if !ed.isIdle { ed.cancel(); await ed.waitIdle() }
                        box.value = await ed.run(line)
                    } else { box.value = ["Error: the document was closed"] }
                    sem.signal()
                }
            }
            if sem.wait(timeout: .now() + 120) == .timedOut { throw ArchiJSON.fail("command timed out: \(line)") }
            all += box.value
        }
        return all
    }
}

extension ScriptEngine {
    private static let engines = NSMapTable<AppModel, ScriptEngine>.weakToStrongObjects()
    /// The console's engine for a document window (kept for the window's lifetime so JS globals persist).
    @MainActor static func forModel(_ m: AppModel) -> ScriptEngine {
        if let e = engines.object(forKey: m) { return e }
        let e = ScriptEngine(model: m)
        e.startHooks(m)
        engines.setObject(e, forKey: m)
        return e
    }
}


/// Script debugging helpers: error excerpts with a caret, readable stack frames, and console extras
/// (assert, time/timeEnd, trace, count) installed in every script context.
enum ScriptDiagnostics {
    /// The source line `line` (1-based) with its neighbours and a caret under `column`.
    static func excerpt(source: String, line: Int, column: Int?, context: Int = 1) -> [String] {
        let lines = source.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { return [] }
        var out: [String] = []
        let w = String(min(lines.count, line + context)).count
        for i in max(1, line - context)...min(lines.count, line + context) {
            let n = String(i).leftPadded(to: w)
            out.append("\(i == line ? ">" : " ") \(n) | \(lines[i - 1])")
            if i == line, let c = column, c >= 1 { out.append("  " + String(repeating: " ", count: w) + " | " + String(repeating: " ", count: min(c - 1, 400)) + "^") }
        }
        return out
    }
    /// Stack frames ("fn@file:line:col" lines) without the global-code noise.
    static func frames(_ stack: String) -> [String] {
        stack.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "global code" }
    }
    static let consolePrelude = """
    (function(){
      var timers = {}, counts = {};
      console.assert = function(c){ if(!c){ var a = Array.prototype.slice.call(arguments, 1); console.error.apply(null, ["Assertion failed:"].concat(a)); } };
      console.time = function(l){ timers[l || "default"] = Date.now(); };
      console.timeEnd = function(l){ l = l || "default"; if (timers[l] !== undefined){ console.log(l + ": " + (Date.now() - timers[l]) + " ms"); delete timers[l]; } else { console.warn("No timer " + l); } };
      console.count = function(l){ l = l || "default"; counts[l] = (counts[l] || 0) + 1; console.log(l + ": " + counts[l]); };
      console.trace = function(){ var s = (new Error()).stack || ""; console.log.apply(null, ["Trace:"].concat(Array.prototype.slice.call(arguments)));
        s.split("\\n").slice(1).forEach(function(f){ if (f && f !== "global code") console.log("   at " + f); }); };
    })();
    """
}

private extension String {
    func leftPadded(to n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}


/// Runs JavaScript plugins (PluginRegistry) in the app: plugin commands evaluate the plugin's main script in the
/// document window's script engine (full `archi` API) once the command line is free, and call the command's function.
@MainActor enum AppPlugins {
    /// Separates a plugin's source from the call appended when one of its commands runs.
    nonisolated static let callMarker = "\n;/*archi-plugin-call*/"
    static func install() {
        let reg = PluginRegistry.shared
        reg.reload()
        reg.register(into: .shared)
        PluginRegistry.evaluator = { plugin, function, ed in
            guard let m = AppModel.all.first(where: { $0.editor === ed }) else { throw CommandError.invalid("No document window to run the plugin in.") }
            let engine = ScriptEngine.forModel(m)
            let code = plugin.source + callMarker + "\nif (typeof \(function) !== 'function') { throw new Error('\(plugin.manifest.main) defines no function \(function)()'); }\n\(function)();"
            Task { @MainActor in
                await ed.waitIdle()
                // Everything the plugin does (commands, archi.add/update…) becomes one undo step named after the command.
                let step = UndoStep.begin(ed)
                let r = await engine.evaluate(code)
                await ed.waitIdle()
                step.end(ed, label: plugin.manifest.commands.first { $0.function == function }?.name ?? plugin.manifest.name)
                for l in r.output { ed.print(l) }
                if let e = r.error { ed.print("\(plugin.manifest.name): \(e)") }
            }
        }
    }
}
