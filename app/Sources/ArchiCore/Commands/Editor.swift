// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// What the active command is asking for.
public struct InputRequest {
    public enum Kind: Hashable { case point, distance, angle, integer, string, selection, entity, keyword }
    public var message: String
    public var kinds: Set<Kind>
    public var keywords: [String]
    public var defaultValue: String?
    /// Rubber-band base point (for relative input, ortho, direct distance entry).
    public var base: Vec2?
    /// Live preview geometry for the given cursor position.
    public var preview: ((Vec2) -> [Geometry])?
    public var allowEmpty: Bool
    public init(_ message: String, kinds: Set<Kind>, keywords: [String] = [], defaultValue: String? = nil, base: Vec2? = nil,
                allowEmpty: Bool = true, preview: ((Vec2) -> [Geometry])? = nil) {
        self.message = message; self.kinds = kinds; self.keywords = keywords; self.defaultValue = defaultValue
        self.base = base; self.allowEmpty = allowEmpty; self.preview = preview
    }
    /// Prompt line as shown on the command line, e.g. "Specify next point [Close/Undo] <10>:".
    public var promptText: String {
        var s = message
        if !keywords.isEmpty { s += " [" + keywords.joined(separator: "/") + "]" }
        if let d = defaultValue { s += " <\(d)>" }
        return s + ":"
    }
}

public enum CommandInput: Equatable {
    case point(Vec2)
    case number(Double)
    case text(String)
    case keyword(String)
    case selection([EntityID])
    case enter
    case cancel
}

public enum CommandError: Error, Equatable {
    case cancelled
    case invalid(String)
}

/// Actions the editor asks its host (the Mac UI, or the CLI) to perform.
public enum HostAction: Equatable {
    case zoomExtents, zoomWindow(BBox2), zoomScale(Double), pan(Vec2), regen
    case show2D, show3D, showSplit, render, walkthrough
    case open(String?), save(String?), saveAs(String?), newDocument, export(format: String, path: String?), plot(path: String?), importFile(String?)
    case showPanel(String), setViewStyle(String), setView(String), message(String)
}

public protocol EditorHost: AnyObject {
    func perform(_ action: HostAction, editor: Editor)
}

public struct CommandDef {
    public var name: String
    public var aliases: [String]
    public var category: String
    public var summary: String
    /// Whether the command changes the document (records undo).
    public var modifies: Bool
    public var run: @MainActor (Editor) async throws -> Void
    public init(_ name: String, aliases: [String] = [], category: String, summary: String, modifies: Bool = true, run: @escaping @MainActor (Editor) async throws -> Void) {
        self.name = name.uppercased(); self.aliases = aliases.map { $0.uppercased() }; self.category = category; self.summary = summary; self.modifies = modifies; self.run = run
    }
}

public final class CommandRegistry {
    public static let shared = CommandRegistry()
    public private(set) var commands: [String: CommandDef] = [:]
    private var aliasMap: [String: String] = [:]
    private var registeredBuiltins = false
    public init() {}
    public func register(_ c: CommandDef) {
        commands[c.name] = c
        for a in c.aliases { aliasMap[a] = c.name }
    }
    public func register(_ cs: [CommandDef]) { cs.forEach(register) }
    public func lookup(_ name: String) -> CommandDef? {
        let n = name.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "_.-'"))
        if let c = commands[n] { return c }
        if let a = aliasMap[n] { return commands[a] }
        return nil
    }
    public var sorted: [CommandDef] { commands.values.sorted { $0.name < $1.name } }
    /// Names and aliases starting with the prefix (autocomplete).
    public func complete(_ prefix: String) -> [String] {
        let p = prefix.uppercased()
        guard !p.isEmpty else { return [] }
        let names = commands.keys.filter { $0.hasPrefix(p) } + aliasMap.keys.filter { $0.hasPrefix(p) }
        return Array(Set(names)).sorted { ($0.count, $0) < ($1.count, $1) }
    }
    public func ensureBuiltins() {
        guard !registeredBuiltins else { return }
        registeredBuiltins = true
        BuiltinCommands.registerAll(self)
    }
}

public struct DraftSettings: Codable, Hashable {
    public var ortho = false
    public var gridSnap = false
    public var gridSpacing = 100.0
    public var showGrid = true
    public var objectSnap = true
    public var snapModes: Set<SnapKind> = [.endpoint, .midpoint, .center, .intersection, .perpendicular, .quadrant, .node, .insertion]
    public var polarTracking = true
    public var polarIncrement = 45.0
    public var dynamicInput = true
    public var lineweightDisplay = true
    public var textHeight = 250.0
    public var wallThickness = 200.0
    public var wallHeight = 3000.0
    public var wallJustification: WallJustification = .center
    public var offsetDistance = 100.0
    public var filletRadius = 0.0
    public var chamferDistance = 0.0
    public init() {}
}

public enum SnapKind: String, Codable, CaseIterable, Hashable {
    case endpoint, midpoint, center, node, quadrant, intersection, `extension`, insertion, perpendicular, tangent, nearest, parallel, grid
}

/// The drawing session: document, selection, undo, command execution. Shared by UI, scripts, agents and CLI.
@MainActor
public final class Editor {
    public var doc: Document { didSet { changeCount += 1; onChange?() } }
    public private(set) var changeCount = 0
    public var history = UndoHistory()
    public var selection: Set<EntityID> = [] { didSet { onSelectionChange?() } }
    public var settings = DraftSettings()
    public var fileURL: URL?
    public var isDirty = false
    public weak var host: EditorHost?
    public var registry: CommandRegistry

    public var onChange: (() -> Void)?
    public var onSelectionChange: (() -> Void)?
    public var onPromptChange: (() -> Void)?
    /// Every line echoed to the command history.
    public var onLog: ((String) -> Void)?
    public private(set) var log: [String] = []

    public private(set) var activeCommand: CommandDef?
    public private(set) var request: InputRequest?
    private var continuation: CheckedContinuation<CommandInput, Never>?
    private var queuedInputs: [String] = []
    public private(set) var lastCommand: String?
    public var lastPoint: Vec2?
    /// Last cursor position reported by the UI (world coordinates) — used for direct distance entry.
    public var cursor: Vec2?
    private var commandTask: Task<Void, Never>?

    public init(document: Document = Document(), registry: CommandRegistry = .shared) {
        self.doc = document
        self.registry = registry
        registry.ensureBuiltins()
    }

    // MARK: Logging
    public func print(_ s: String) {
        log.append(s)
        if log.count > 5000 { log.removeFirst(1000) }
        onLog?(s)
    }

    // MARK: Command line entry
    public var isIdle: Bool { activeCommand == nil }
    public var promptText: String { request?.promptText ?? "Command:" }

    /// Submits one line typed on the command line (or from a script).
    /// Spaces separate successive inputs, like AutoCAD, except when a text string is requested.
    public func submit(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if activeCommand == nil {
            if trimmed.isEmpty { if let l = lastCommand { start(l) }; return }
            var tokens = tokenize(trimmed)
            let name = tokens.removeFirst()
            queuedInputs.append(contentsOf: tokens)
            start(name)
            return
        }
        if trimmed.isEmpty { feed(.enter); return }
        if request?.kinds == [.string] || (request?.kinds.contains(.string) == true && !(request?.kinds.contains(.point) ?? false)) {
            feed(.text(line.trimmingCharacters(in: .whitespaces))); return
        }
        let tokens = tokenize(trimmed)
        queuedInputs.append(contentsOf: tokens.dropFirst())
        feedToken(tokens[0])
    }

    /// Splits a command line into inputs; quoted strings stay together.
    func tokenize(_ s: String) -> [String] {
        var out: [String] = [], cur = "", inQuote = false
        for ch in s {
            if ch == "\"" { inQuote.toggle(); continue }
            if ch == " " && !inQuote { if !cur.isEmpty { out.append(cur); cur = "" } ; continue }
            cur.append(ch)
        }
        if !cur.isEmpty { out.append(cur) }
        return out.isEmpty ? [""] : out
    }

    /// Starts a command by name or alias.
    public func start(_ name: String) {
        registry.ensureBuiltins()
        guard let def = registry.lookup(name) else {
            print("Unknown command \"\(name.uppercased())\". Press F1 or type HELP.")
            queuedInputs.removeAll()
            return
        }
        if activeCommand != nil { cancel() }
        activeCommand = def
        lastCommand = def.name
        print("Command: \(def.name)")
        let before = doc
        commandTask = Task { @MainActor in
            do {
                try await def.run(self)
            } catch CommandError.cancelled {
                self.print("*Cancel*")
            } catch CommandError.invalid(let m) {
                self.print(m)
            } catch {
                self.print("Error: \(error)")
            }
            if def.modifies && self.doc != before {
                self.history.record(def.name, before: before)
                self.isDirty = true
            }
            self.activeCommand = nil
            self.request = nil
            self.continuation = nil
            self.queuedInputs.removeAll()
            self.onPromptChange?()
            self.onChange?()
        }
    }

    /// Runs a command to completion with the given inputs (scripts / agents). Returns the log lines produced.
    @discardableResult
    public func run(_ line: String) async -> [String] {
        let start = log.count
        submit(line)
        await waitIdle()
        return Array(log[min(start, log.count)...])
    }

    /// Waits until the command finishes; unanswered prompts are answered with Enter.
    public func waitIdle() async {
        var guardCount = 0
        while activeCommand != nil && guardCount < 10000 {
            await Task.yield()
            if continuation != nil && queuedInputs.isEmpty { feed(.enter) }
            guardCount += 1
        }
        if activeCommand != nil { cancel() }
    }

    public func cancel() {
        queuedInputs.removeAll()
        if continuation != nil { feed(.cancel) } else { commandTask?.cancel() }
    }

    /// Feeds a typed token, parsing it against the current request.
    public func feedToken(_ token: String) {
        guard let req = request else { return }
        switch InputParser.parse(token, request: req, lastPoint: lastPoint, cursor: cursor, ortho: settings.ortho) {
        case .success(let input): feed(input)
        case .failure(let msg):
            print(msg.message)
            print(req.promptText)
        }
    }

    /// Feeds an input (from the UI: clicks, Enter, Escape; or parsed text).
    public func feed(_ input: CommandInput) {
        guard let c = continuation else { return }
        continuation = nil
        switch input {
        case .point(let p): lastPoint = p
        default: break
        }
        c.resume(returning: input)
    }

    // MARK: Primitives used by commands
    /// Asks for input; the command suspends until the user (or a script) answers.
    public func ask(_ req: InputRequest) async -> CommandInput {
        request = req
        onPromptChange?()
        if let base = req.base { _ = base }
        let pre: [String] = queuedInputs
        if !pre.isEmpty {
            var t = queuedInputs.removeFirst()
            if req.kinds == [.string] && !queuedInputs.isEmpty { t += " " + queuedInputs.joined(separator: " "); queuedInputs.removeAll() }
            if req.kinds == [.string] { print("\(req.promptText) \(t)"); return t.isEmpty ? .enter : .text(t) }
            print("\(req.promptText) \(t)")
            if t.isEmpty { return .enter }
            if let r = try? InputParser.parse(t, request: req, lastPoint: lastPoint, cursor: cursor, ortho: settings.ortho).get() {
                if case .point(let p) = r { lastPoint = p }
                return r
            }
            print("Invalid input \"\(t)\".")
        } else {
            print(req.promptText)
        }
        let r = await withCheckedContinuation { (c: CheckedContinuation<CommandInput, Never>) in self.continuation = c }
        request = nil
        return r
    }

    /// Point, or nil on Enter. Throws on Escape. Keywords are returned through `keyword`.
    public func getPoint(_ msg: String, base: Vec2? = nil, keywords: [String] = [], preview: ((Vec2) -> [Geometry])? = nil) async throws -> PointAnswer {
        var kinds: Set<InputRequest.Kind> = [.point]
        if !keywords.isEmpty { kinds.insert(.keyword) }
        let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords, base: base, preview: preview))
        switch r {
        case .point(let p): return .point(p)
        case .keyword(let k): return .keyword(k)
        case .enter: return .none
        case .cancel: throw CommandError.cancelled
        case .number(let d):
            if let b = base { let dir = ((cursor ?? b + Vec2(1, 0)) - b).normalized; return .point(b + (dir == .zero ? Vec2(1, 0) : dir) * d) }
            return .none
        default: return .none
        }
    }

    public enum PointAnswer: Equatable { case point(Vec2), keyword(String), none
        public var point: Vec2? { if case .point(let p) = self { return p }; return nil } }

    /// Required point (Enter cancels).
    public func requirePoint(_ msg: String, base: Vec2? = nil, preview: ((Vec2) -> [Geometry])? = nil) async throws -> Vec2 {
        guard case .point(let p) = try await getPoint(msg, base: base, preview: preview) else { throw CommandError.cancelled }
        return p
    }

    /// Distance typed, or measured between base and a picked point. nil on Enter (use default).
    public func getDistance(_ msg: String, base: Vec2? = nil, defaultValue: Double? = nil, keywords: [String] = [], preview: ((Vec2) -> [Geometry])? = nil) async throws -> NumberAnswer {
        var kinds: Set<InputRequest.Kind> = [.distance, .point]
        if !keywords.isEmpty { kinds.insert(.keyword) }
        let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords, defaultValue: defaultValue.map { fmt($0) }, base: base, preview: preview))
        switch r {
        case .number(let d): return .value(d)
        case .point(let p):
            if let b = base { return .value(b.distance(to: p)) }
            let q = try await requirePoint("Specify second point", base: p)
            return .value(p.distance(to: q))
        case .keyword(let k): return .keyword(k)
        case .enter: if let d = defaultValue { return .value(d) }; return .none
        case .cancel: throw CommandError.cancelled
        default: return .none
        }
    }
    public enum NumberAnswer: Equatable { case value(Double), keyword(String), none
        public var value: Double? { if case .value(let v) = self { return v }; return nil } }

    /// Angle in radians (typed in degrees, or picked relative to base).
    public func getAngle(_ msg: String, base: Vec2? = nil, defaultValue: Double? = nil, keywords: [String] = [], preview: ((Vec2) -> [Geometry])? = nil) async throws -> NumberAnswer {
        var kinds: Set<InputRequest.Kind> = [.angle, .point]
        if !keywords.isEmpty { kinds.insert(.keyword) }
        let r = await ask(InputRequest(msg, kinds: kinds, keywords: keywords, defaultValue: defaultValue.map { fmt(deg($0)) }, base: base, preview: preview))
        switch r {
        case .number(let d): return .value(rad(d))
        case .point(let p):
            let b = base ?? lastPoint ?? .zero
            return .value((p - b).angle)
        case .keyword(let k): return .keyword(k)
        case .enter: if let d = defaultValue { return .value(d) }; return .none
        case .cancel: throw CommandError.cancelled
        default: return .none
        }
    }

    public func getInteger(_ msg: String, defaultValue: Int? = nil) async throws -> Int? {
        let r = await ask(InputRequest(msg, kinds: [.integer], defaultValue: defaultValue.map { "\($0)" }))
        switch r {
        case .number(let d): return Int(d)
        case .enter: return defaultValue
        case .cancel: throw CommandError.cancelled
        default: return defaultValue
        }
    }

    public func getString(_ msg: String, defaultValue: String? = nil) async throws -> String? {
        let r = await ask(InputRequest(msg, kinds: [.string], defaultValue: defaultValue))
        switch r {
        case .text(let s): return s
        case .keyword(let s): return s
        case .enter: return defaultValue
        case .cancel: throw CommandError.cancelled
        default: return defaultValue
        }
    }

    public func getKeyword(_ msg: String, _ keywords: [String], defaultValue: String? = nil) async throws -> String? {
        let r = await ask(InputRequest(msg, kinds: [.keyword], keywords: keywords, defaultValue: defaultValue))
        switch r {
        case .keyword(let k): return k
        case .text(let t): return keywords.first { $0.lowercased().hasPrefix(t.lowercased()) } ?? defaultValue
        case .enter: return defaultValue
        case .cancel: throw CommandError.cancelled
        default: return defaultValue
        }
    }

    /// Returns the current selection if any (noun-verb), otherwise asks the user to select objects.
    public func getSelection(_ msg: String = "Select objects") async throws -> [EntityID] {
        if !selection.isEmpty {
            let ids = Array(selection).filter { isSelectable($0) }
            print("\(ids.count) found")
            return ids
        }
        var picked: Set<EntityID> = []
        while true {
            let r = await ask(InputRequest(msg, kinds: [.selection], keywords: ["All", "Last", "Previous"]))
            switch r {
            case .selection(let ids):
                let ok = ids.filter { isSelectable($0) }
                picked.formUnion(ok); selection = picked
                print("\(ok.count) found, \(picked.count) total")
            case .keyword(let k):
                switch k {
                case "All": picked.formUnion(doc.allIDs.filter { isSelectable($0) })
                case "Last": if let l = (doc.entities.map(\.id) + doc.elements.map(\.id)).max() { picked.insert(l) }
                default: picked.formUnion(previousSelection)
                }
                selection = picked
                print("\(picked.count) total")
            case .enter:
                previousSelection = picked
                return Array(picked)
            case .cancel: selection = []; throw CommandError.cancelled
            default: break
            }
        }
    }
    public var previousSelection: Set<EntityID> = []

    public func getEntity(_ msg: String) async throws -> EntityID? {
        while true {
            let r = await ask(InputRequest(msg, kinds: [.entity, .selection]))
            switch r {
            case .selection(let ids): if let f = ids.first(where: { isSelectable($0) }) { return f }
            case .point(let p): if let id = pick(at: p, tolerance: pickTolerance) { return id }; print("Nothing found.")
            case .enter: return nil
            case .cancel: throw CommandError.cancelled
            default: return nil
            }
        }
    }

    /// World-space pick tolerance supplied by the UI (≈ 6 px).
    public var pickTolerance: Double = 10

    public func isSelectable(_ id: EntityID) -> Bool {
        if let e = doc.entity(id) { return doc.isEditable(layer: e.layer) }
        if let e = doc.element(id) { return doc.isEditable(layer: e.layer) }
        return false
    }

    /// Topmost selectable object near a point.
    public func pick(at p: Vec2, tolerance: Double) -> EntityID? {
        var best: (EntityID, Double)?
        for e in doc.entities where doc.isEditable(layer: e.layer) {
            let d = GeometryOps.distance(from: p, to: e.geometry, doc: doc)
            if d <= tolerance, d < (best?.1 ?? .infinity) { best = (e.id, d) }
        }
        for el in doc.elements where doc.isEditable(layer: el.layer) && el.level == doc.currentLevel {
            let d = PlanRepresentation.distance(from: p, to: el, doc: doc)
            if d <= tolerance, d < (best?.1 ?? .infinity) { best = (el.id, d) }
        }
        return best?.0
    }

    /// Objects inside a window (fully) or crossing it.
    public func select(in box: BBox2, crossing: Bool) -> [EntityID] {
        var out: [EntityID] = []
        for e in doc.entities where doc.isEditable(layer: e.layer) {
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            if b.isEmpty { continue }
            if box.contains(b) || (crossing && box.intersects(b) && GeometryOps.crosses(e.geometry, box: box, doc: doc)) { out.append(e.id) }
        }
        for el in doc.elements where doc.isEditable(layer: el.layer) && el.level == doc.currentLevel {
            let b = PlanRepresentation.bounds(el, doc: doc)
            if b.isEmpty { continue }
            if box.contains(b) || (crossing && box.intersects(b)) { out.append(el.id) }
        }
        return out
    }

    // MARK: Direct edits (scripts, UI panels)
    public func transaction(_ label: String, _ body: (inout Document) throws -> Void) rethrows {
        let before = doc
        var d = doc
        try body(&d)
        if d != before { history.record(label, before: before); doc = d; isDirty = true }
    }
    public func undo() {
        if let (d, label) = history.undo(current: doc) { doc = d; selection = selection.filter { doc.contains($0) }; print("Undo \(label)") }
        else { print("Nothing to undo.") }
    }
    public func redo() {
        if let (d, label) = history.redo(current: doc) { doc = d; print("Redo \(label)") }
        else { print("Nothing to redo.") }
    }
    public func replaceDocument(_ d: Document, url: URL?) {
        history = UndoHistory(); selection = []; doc = d; fileURL = url; isDirty = false
    }
}
