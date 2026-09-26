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
    /// The preview can be turned 90° while dragging (Space / `Editor.rotateDrag90`, MOD-029).
    public var rotatable = false
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
    /// How often each command was started (autocomplete ranking; the app may persist it).
    public var usage: [String: Int] = [:]
    /// Also suggest commands containing the typed text in the middle of their name (INPUTSEARCHOPTIONS mid-string search).
    public var midStringSearch = true

    /// Names and aliases starting with the prefix (autocomplete), most used first; then names containing it (3+ letters).
    public func complete(_ prefix: String) -> [String] {
        let p = prefix.uppercased()
        guard !p.isEmpty else { return [] }
        let names = Array(Set(commands.keys.filter { $0.hasPrefix(p) } + aliasMap.keys.filter { $0.hasPrefix(p) }))
        func uses(_ n: String) -> Int { usage[aliasMap[n] ?? n] ?? 0 }
        // Most used first; a command's full name before its aliases; then shorter names.
        func alias(_ n: String) -> Int { commands[n] == nil ? 1 : 0 }
        var out = names.sorted { (-uses($0), alias($0), $0.count, $0) < (-uses($1), alias($1), $1.count, $1) }
        if midStringSearch && p.count >= 3 {
            let mid = commands.keys.filter { !$0.hasPrefix(p) && $0.contains(p) }
            out += mid.sorted { (-uses($0), $0.count, $0) < (-uses($1), $1.count, $1) }
        }
        return out
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
    /// Object snap tracking (OTRACK, F11): alignment paths from acquired snap points.
    public var objectSnapTracking = true
    /// Isometric drafting (ISODRAFT / SNAPSTYL 1): ortho and grid snap follow the isometric axes.
    public var isometric = false
    /// Current isometric plane (ISOPLANE / SNAPISOPAIR): 0 left, 1 top, 2 right.
    public var isoPlane = 0
    /// Geometric centre snap (GCEN): centroids of closed polylines, shown with the centre marker.
    public var geometricCenterSnap = false
    /// Apparent / extended intersection snap (APPINT, OSMODE 2048).
    public var apparentIntersectionSnap = false
    /// Axis lock (PRC-028, arrow keys while drawing): points are projected on the line through the base point at this
    /// angle (radians). Session state, not saved.
    public var axisLock: Double? = nil
    public init() {}

    private enum Keys: String, CodingKey {
        case ortho, gridSnap, gridSpacing, showGrid, objectSnap, snapModes, polarTracking, polarIncrement, dynamicInput, lineweightDisplay
        case textHeight, wallThickness, wallHeight, wallJustification, offsetDistance, filletRadius, chamferDistance, objectSnapTracking
        case isometric, isoPlane, geometricCenterSnap, apparentIntersectionSnap
    }
    /// Tolerant decoding: settings saved by older builds (missing keys) keep the defaults for the new fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = DraftSettings()
        ortho = try c.decodeIfPresent(Bool.self, forKey: .ortho) ?? d.ortho
        gridSnap = try c.decodeIfPresent(Bool.self, forKey: .gridSnap) ?? d.gridSnap
        gridSpacing = try c.decodeIfPresent(Double.self, forKey: .gridSpacing) ?? d.gridSpacing
        showGrid = try c.decodeIfPresent(Bool.self, forKey: .showGrid) ?? d.showGrid
        objectSnap = try c.decodeIfPresent(Bool.self, forKey: .objectSnap) ?? d.objectSnap
        snapModes = (try? c.decodeIfPresent(Set<SnapKind>.self, forKey: .snapModes)) ?? d.snapModes
        polarTracking = try c.decodeIfPresent(Bool.self, forKey: .polarTracking) ?? d.polarTracking
        polarIncrement = try c.decodeIfPresent(Double.self, forKey: .polarIncrement) ?? d.polarIncrement
        dynamicInput = try c.decodeIfPresent(Bool.self, forKey: .dynamicInput) ?? d.dynamicInput
        lineweightDisplay = try c.decodeIfPresent(Bool.self, forKey: .lineweightDisplay) ?? d.lineweightDisplay
        textHeight = try c.decodeIfPresent(Double.self, forKey: .textHeight) ?? d.textHeight
        wallThickness = try c.decodeIfPresent(Double.self, forKey: .wallThickness) ?? d.wallThickness
        wallHeight = try c.decodeIfPresent(Double.self, forKey: .wallHeight) ?? d.wallHeight
        wallJustification = (try? c.decodeIfPresent(WallJustification.self, forKey: .wallJustification)) ?? d.wallJustification
        offsetDistance = try c.decodeIfPresent(Double.self, forKey: .offsetDistance) ?? d.offsetDistance
        filletRadius = try c.decodeIfPresent(Double.self, forKey: .filletRadius) ?? d.filletRadius
        chamferDistance = try c.decodeIfPresent(Double.self, forKey: .chamferDistance) ?? d.chamferDistance
        objectSnapTracking = try c.decodeIfPresent(Bool.self, forKey: .objectSnapTracking) ?? d.objectSnapTracking
        isometric = try c.decodeIfPresent(Bool.self, forKey: .isometric) ?? d.isometric
        isoPlane = try c.decodeIfPresent(Int.self, forKey: .isoPlane) ?? d.isoPlane
        geometricCenterSnap = try c.decodeIfPresent(Bool.self, forKey: .geometricCenterSnap) ?? d.geometricCenterSnap
        apparentIntersectionSnap = try c.decodeIfPresent(Bool.self, forKey: .apparentIntersectionSnap) ?? d.apparentIntersectionSnap
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(ortho, forKey: .ortho); try c.encode(gridSnap, forKey: .gridSnap); try c.encode(gridSpacing, forKey: .gridSpacing)
        try c.encode(showGrid, forKey: .showGrid); try c.encode(objectSnap, forKey: .objectSnap); try c.encode(snapModes, forKey: .snapModes)
        try c.encode(polarTracking, forKey: .polarTracking); try c.encode(polarIncrement, forKey: .polarIncrement); try c.encode(dynamicInput, forKey: .dynamicInput)
        try c.encode(lineweightDisplay, forKey: .lineweightDisplay); try c.encode(textHeight, forKey: .textHeight); try c.encode(wallThickness, forKey: .wallThickness)
        try c.encode(wallHeight, forKey: .wallHeight); try c.encode(wallJustification, forKey: .wallJustification); try c.encode(offsetDistance, forKey: .offsetDistance)
        try c.encode(filletRadius, forKey: .filletRadius); try c.encode(chamferDistance, forKey: .chamferDistance); try c.encode(objectSnapTracking, forKey: .objectSnapTracking)
        try c.encode(isometric, forKey: .isometric); try c.encode(isoPlane, forKey: .isoPlane)
        if geometricCenterSnap { try c.encode(geometricCenterSnap, forKey: .geometricCenterSnap) }
        if apparentIntersectionSnap { try c.encode(apparentIntersectionSnap, forKey: .apparentIntersectionSnap) }
    }
}

public enum SnapKind: String, Codable, CaseIterable, Hashable {
    case endpoint, midpoint, center, node, quadrant, intersection, `extension`, insertion, perpendicular, tangent, nearest, parallel, grid
}

/// The drawing session: document, selection, undo, command execution. Shared by UI, scripts, agents and CLI.
@MainActor
public final class Editor {
    public var doc: ArchiDocument {
        didSet {
            changeCount += 1
            // Hatch patterns saved in the drawing (HPPAT:<name>) are available to every renderer.
            if doc.variables != oldValue.variables { HatchPatterns.register(doc: doc) }
            onChange?()
        }
    }
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
    /// Monitored system variables (SYSVARMONITOR) changed by the last command.
    public var onSysVarChange: (([String]) -> Void)?
    /// Every line echoed to the command history.
    public var onLog: ((String) -> Void)?
    public private(set) var log: [String] = []

    public private(set) var activeCommand: CommandDef?
    public private(set) var request: InputRequest?
    private var continuation: CheckedContinuation<CommandInput, Never>?
    private var queuedInputs: [String] = []
    public private(set) var lastCommand: String?
    public var lastPoint: Vec2? {
        get { relativeZeroLock ?? storedLastPoint }
        set { storedLastPoint = newValue }
    }
    private var storedLastPoint: Vec2?
    /// Locked relative zero (PRC-029): while set, relative input (@dx,dy) is measured from it instead of the last point.
    public var relativeZeroLock: Vec2?
    /// Last cursor position reported by the UI (world coordinates) — used for direct distance entry.
    public var cursor: Vec2?
    private var commandTask: Task<Void, Never>?
    /// Quarter-turn rotation applied to the current rotatable drag preview (radians, a multiple of π/2).
    public internal(set) var dragRotation: Double = 0
    /// Set by ARRAYCLASSIC: the array commands make separate copies whatever ARRAYASSOCIATIVITY says.
    public internal(set) var forceClassicArray = false

    public init(document: ArchiDocument = ArchiDocument(), registry: CommandRegistry = .shared) {
        self.doc = document
        self.registry = registry
        registry.ensureBuiltins()
        HatchPatterns.register(doc: document)
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
        recorder?.lines.append(line)
        actionRecorder?.lines.append(line)
        recordHistory(line, atPrompt: activeCommand != nil)
        inSubmit = true
        defer { inSubmit = false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if activeCommand == nil {
            if trimmed.isEmpty { if let l = lastCommand { start(l) }; return }
            var tokens = tokenize(trimmed)
            let name = Editor.unmark(tokens.removeFirst())
            queuedInputs.append(contentsOf: tokens)
            start(name)
            return
        }
        if trimmed.isEmpty { feed(.enter); return }
        // Transparent command ('ZOOM, 'PAN, 'SETVAR...) run inside the active command.
        if trimmed.hasPrefix("'"), request?.kinds != [.string] {
            var tokens = tokenize(String(trimmed.dropFirst()))
            let name = Editor.unmark(tokens.removeFirst())
            if runTransparent(name, inputs: tokens) { return }
        }
        if request?.kinds == [.string] || (request?.kinds.contains(.string) == true && !(request?.kinds.contains(.point) ?? false)) {
            feed(.text(line.trimmingCharacters(in: .whitespaces))); return
        }
        let tokens = tokenize(trimmed)
        queuedInputs.append(contentsOf: tokens.dropFirst())
        feedToken(tokens[0])
    }

    /// Splits a command line into inputs; quoted strings stay together.
    /// A quoted empty string (""), ";" or an extra space (double space) is an empty token, i.e. Enter. Other quoted tokens are marked so a
    /// text prompt takes exactly that token (unquoted text prompts take the rest of the line).
    func tokenize(_ s: String) -> [String] {
        var out: [String] = [], cur = "", inQuote = false, quoted = false
        func flush() {
            if quoted { out.append(cur.isEmpty ? "" : Editor.quoteMark + cur) } else if !cur.isEmpty { out.append(cur) }
            cur = ""; quoted = false
        }
        var prevSpace = false
        for ch in s {
            if ch == "\"" { inQuote.toggle(); quoted = true; prevSpace = false; continue }
            if ch == " " && !inQuote {
                // Like AutoCAD scripts, each extra space is an Enter ("ERASE L  CIRCLE…").
                if prevSpace && cur.isEmpty && !quoted { out.append("") } else { flush() }
                prevSpace = true; continue
            }
            prevSpace = false
            cur.append(ch)
        }
        flush()
        return out.isEmpty ? [""] : out
    }
    static let quoteMark = "\u{2}"
    static func unmark(_ t: String) -> String { t.hasPrefix(quoteMark) ? String(t.dropFirst(quoteMark.count)) : t }

    /// Starts a command by name or alias.
    public func start(_ name: String) {
        registry.ensureBuiltins()
        guard let def = registry.lookup(name) else {
            if let expansion = UserAliases.expansion(for: name, doc: doc) {
                let rest = queuedInputs
                queuedInputs.removeAll()
                if let target = registry.lookup(expansion) {
                    queuedInputs = rest
                    start(target.name)
                } else {
                    // A macro: its tokens (";" = Enter) followed by whatever was typed after the alias.
                    let macroTokens = UserAliases.macroTokens(expansion)
                    guard let first = macroTokens.first else { return }
                    queuedInputs = Array(macroTokens.dropFirst()) + rest
                    start(first)
                }
                return
            }
            // A system variable typed as a command ("USERI1 5", "DIMTXT").
            if SysVarCatalog.info(name) != nil, registry.lookup("SETVAR") != nil {
                queuedInputs.insert(name, at: 0)
                start("SETVAR")
                return
            }
            var msg = "Unknown command \"\(name.uppercased())\". Press F1 or type HELP."
            let sugg = CommandSuggestions.suggest(name, registry: registry)
            if !sugg.isEmpty { msg += " Did you mean: " + sugg.joined(separator: ", ") + "?" }
            print(msg)
            queuedInputs.removeAll()
            return
        }
        if activeCommand != nil { cancelCommand() }
        activeCommand = def
        dynamicFace = nil
        lastCommand = def.name
        registry.usage[def.name, default: 0] += 1
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
            if def.modifies && self.doc.variable("CONSTRAINTINFER") == "1" && (def.category == "Draw" || def.category == "Modify") {
                let newIDs = Set(self.doc.entities.map(\.id)).subtracting(before.entities.map(\.id))
                if !newIDs.isEmpty { ConstraintCommands.inferConstraints(self, newIDs: newIDs) }
            }
            if def.name != "LAYERP" && (self.doc.layers != before.layers || self.doc.currentLayer != before.currentLayer) {
                self.layerPrevious.append((before.layers, before.currentLayer))
                if self.layerPrevious.count > 50 { self.layerPrevious.removeFirst() }
            }
            if self.doc.layers != before.layers, let m = LayerNotify.message(before: before, after: self.doc) { self.print(m) }
            if def.modifies && AnnotativeText.anyStyle(self.doc) && self.doc.entities.count > before.entities.count {
                var d = self.doc
                if AnnotativeText.applyToNew(&d, old: Set(before.entities.map(\.id))) > 0 { self.doc = d }
            }
            if def.modifies && self.doc.variable("DIMASSOC") != "0" && self.doc.entities.count > before.entities.count {
                // New dimensions attach to the objects they were snapped to (DIMASSOC 2).
                let old = Set(before.entities.map(\.id))
                let tol = max(self.pickTolerance * 1e-3, 1e-6)
                var d = self.doc
                for i in d.entities.indices where !old.contains(d.entities[i].id) && d.entities[i].props[DimAssociation.prop] == nil {
                    if case .dimension = d.entities[i].geometry { DimAssociation.associate(&d.entities[i], doc: d, tol: tol) }
                    if case .leader = d.entities[i].geometry, d.entities[i].props[LeaderAssociation.prop] == nil { LeaderAssociation.associate(&d.entities[i], doc: d, tol: tol) }
                }
                if d != self.doc { self.doc = d }
            }
            if def.modifies && self.doc != before {
                var d = self.doc
                if DocumentUpdaters.run(&d) { self.doc = d }
                // Editing-time statistics (TIME, ANL-011): record activity after every modifying command.
                EditTime.touch(&d)
                self.doc = d
                if !self.undoGroupActive { self.history.record(def.name, before: before) }
                self.isDirty = true
            }
            let monitored = SysVarMonitor.changes(from: before, to: self.doc)
            if !monitored.isEmpty && self.doc.variable(SysVarMonitor.notifyVariable) != "0" {
                for c in monitored { self.print("System variable \(c.name) changed: \(c.old) → \(c.new)") }
                self.onSysVarChange?(monitored.map(\.name))
            }
            self.activeCommand = nil
            self.dynamicFace = nil
            self.request = nil
            Snap.tracker.active = false
            Snap.tracker.clear()
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
            if continuation != nil && (queuedInputs.isEmpty || pausedForUser) { feed(.enter) }
            guardCount += 1
        }
        if activeCommand != nil { cancelCommand() }
    }

    /// Escape from the user: cancels the running command and interrupts a running script (RESUME continues it).
    public func cancel() {
        if scriptDepth > 0 { scriptInterrupted = true }
        cancelCommand()
    }

    /// Cancels the running command without interrupting a script.
    func cancelCommand() {
        queuedInputs.removeAll()
        if continuation != nil { feed(.cancel) } else { commandTask?.cancel() }
    }

    /// Feeds a typed token, parsing it against the current request.
    public func feedToken(_ raw: String) {
        guard let req = request else { return }
        let token = Editor.unmark(raw)
        if token == ";" { feed(.enter); return }
        if req.kinds.contains(.point), let m = InputParser.pointModifier(token), !req.keywords.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) {
            feed(.keyword(Editor.modifierPrefix + m)); return
        }
        if req.kinds.contains(.point), let o = InputParser.snapOverride(token, keywords: req.keywords) {
            feed(.keyword(Editor.modifierPrefix + "SNAP:" + o)); return
        }
        switch parse(token, req) {
        case .success(let input): feed(input)
        case .failure(let msg):
            print(msg.message)
            print(req.promptText)
        }
    }

    /// Feeds an input (from the UI: clicks, Enter, Escape; or parsed text).
    public func feed(_ input: CommandInput) {
        guard let c = continuation else { return }
        if !inSubmit {
            if let rec = recorder { rec.record(input, world: UCSFrame.current(doc).isWorld) }
            if let rec = actionRecorder { rec.record(input, world: UCSFrame.current(doc).isWorld) }
        }
        continuation = nil
        switch input {
        case .point(let p): lastPoint = p; Snap.tracker.clear()
        default: break
        }
        c.resume(returning: input)
    }

    // MARK: Primitives used by commands
    /// Asks for input; the command suspends until the user (or a script) answers.
    public func ask(_ req: InputRequest) async -> CommandInput {
        let r = await askRaw(req)
        if case .keyword(let k) = r, k.hasPrefix(Editor.modifierPrefix) {
            return await resolvePointModifier(String(k.dropFirst(Editor.modifierPrefix.count)), req)
        }
        return r
    }

    static let modifierPrefix = "\u{1}"

    /// Parses a token against a request with the document's units and UCS.
    func parse(_ token: String, _ req: InputRequest) -> Result<CommandInput, InputParser.ParseFailure> {
        InputParser.context = ParseContext(units: doc.units, ucs: UCSFrame.current(doc), shared: SharedCoordinates.current(doc))
        return InputParser.parse(token, request: req, lastPoint: lastPoint, cursor: cursor, ortho: settings.ortho)
    }

    func askRaw(_ req: InputRequest) async -> CommandInput {
        request = req
        Snap.tracker.active = req.kinds.contains(.point)
        onPromptChange?()
        if queuedInputs.first == MacroPause.mark {
            // Macro pause: this prompt is answered by the user; the rest of the macro continues afterwards.
            queuedInputs.removeFirst()
            pausedForUser = true
            print(req.promptText)
            let r = await withCheckedContinuation { (c: CheckedContinuation<CommandInput, Never>) in self.continuation = c }
            pausedForUser = false
            request = nil
            return r
        }
        var consumed = false
        while !queuedInputs.isEmpty && queuedInputs.first != MacroPause.mark {
            consumed = true
            var t = queuedInputs.removeFirst()
            let wasQuoted = t.hasPrefix(Editor.quoteMark)
            t = Editor.unmark(t)
            if t == ";" && !wasQuoted { t = "" }
            if req.kinds == [.string] && !queuedInputs.isEmpty && !t.isEmpty && !wasQuoted {
                // The rest of the line is the string, up to an explicit Enter ("", ; or a double space), which stays queued.
                var rest: [String] = []
                while let n = queuedInputs.first, !n.isEmpty, n != ";" { rest.append(Editor.unmark(queuedInputs.removeFirst())) }
                if !rest.isEmpty { t += " " + rest.joined(separator: " ") }
            }
            if req.kinds == [.string] { print("\(req.promptText) \(t)"); return t.isEmpty ? .enter : .text(t) }
            print("\(req.promptText) \(t)")
            if t.isEmpty { return .enter }
            if req.kinds.contains(.point), let m = InputParser.pointModifier(t), !req.keywords.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                return .keyword(Editor.modifierPrefix + m)
            }
            if req.kinds.contains(.point), let o = InputParser.snapOverride(t, keywords: req.keywords) {
                return .keyword(Editor.modifierPrefix + "SNAP:" + o)
            }
            if let r = try? parse(t, req).get() {
                if case .point(let p) = r { lastPoint = p }
                return r
            }
            // Invalid scripted input: report it and answer the same prompt with the next token, as when typed.
            print("Invalid input \"\(t)\".")
            if queuedInputs.isEmpty { print(req.promptText) }
        }
        if !consumed { print(req.promptText) }
        let r = await withCheckedContinuation { (c: CheckedContinuation<CommandInput, Never>) in self.continuation = c }
        request = nil
        return r
    }

    /// FROM, M2P, TT and point filters (.X/.Y) — asked in place of the requested point.
    func resolvePointModifier(_ m: String, _ req: InputRequest) async -> CommandInput {
        func pt(_ msg: String, base: Vec2? = nil) async -> Vec2? {
            let r = await ask(InputRequest(msg, kinds: [.point], base: base))
            if case .point(let p) = r { return p }
            return nil
        }
        if m.hasPrefix("SNAP:") { return await resolveSnapOverride(String(m.dropFirst(5)), req) }
        switch m {
        case "FROM":
            guard let b = await pt("Base point") else { return .cancel }
            lastPoint = b
            guard let p = await pt("<Offset>", base: b) else { return .cancel }
            lastPoint = p; return .point(p)
        case "M2P":
            guard let a = await pt("First point of mid") else { return .cancel }
            guard let b = await pt("Second point of mid", base: a) else { return .cancel }
            let p = a.lerp(b, 0.5); lastPoint = p; return .point(p)
        case "TT":
            guard let t = await pt("Specify temporary OTRACK point") else { return .cancel }
            lastPoint = t
            var r = req; r.base = t
            return await ask(r)
        case "INTOF":
            // Manual intersection: the intersection of two picked objects nearest the second pick (extensions if they do not cross).
            guard let a = await pt("First object for intersection") else { return .cancel }
            guard let ida = pickFiltered(at: a, filter: { self.doc.entity($0) != nil }), let ga = doc.entity(ida)?.geometry else { print("No object found."); return .cancel }
            guard let b = await pt("Second object for intersection") else { return .cancel }
            guard let idb = pickFiltered(at: b, filter: { self.doc.entity($0) != nil && $0 != ida }), let gb = doc.entity(idb)?.geometry else { print("No second object found."); return .cancel }
            var xs = Intersections.of(ga, gb, doc: doc)
            if xs.isEmpty { xs = Intersections.of(ga, gb, doc: doc, extended: true) }
            guard let p = xs.min(by: { $0.distance(to: b) < $1.distance(to: b) }) else { print("The objects do not intersect."); return .cancel }
            lastPoint = p; return .point(p)
        case "RH", "RV":
            // Restrict: keep the last point's Y (horizontal) or X (vertical) and take the other coordinate from the next point.
            guard let base = lastPoint ?? req.base else { print("No last point to restrict from."); return await ask(req) }
            guard let a = await pt(m == "RH" ? "(horizontal from last point)" : "(vertical from last point)", base: base) else { return .cancel }
            let p = m == "RH" ? Vec2(a.x, base.y) : Vec2(base.x, a.y)
            lastPoint = p; return .point(p)
        case ".X", ".Y":
            guard let a = await pt("\(m.lowercased()) of") else { return .cancel }
            guard let b = await pt(m == ".X" ? "(need Y)" : "(need X)") else { return .cancel }
            let p = m == ".X" ? Vec2(a.x, b.y) : Vec2(b.x, a.y)
            lastPoint = p; return .point(p)
        default: // .XY/.XZ/.YZ/.Z: 2D input keeps X and Y of the picked point.
            guard let a = await pt("\(m.lowercased()) of") else { return .cancel }
            lastPoint = a; return .point(a)
        }
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
        // PICKFIRST 0: commands ignore the pre-selection (verb-noun only).
        if !selection.isEmpty && doc.variable("PICKFIRST") == "0" { selection = [] }
        if !selection.isEmpty {
            let ids = expandGroups(Array(selection).filter { isSelectable($0) })
            print("\(ids.count) found")
            return ids
        }
        var picked: Set<EntityID> = []
        var removing = false
        func apply(_ ids: [EntityID]) {
            let ok = expandGroups(ids.filter { isSelectable($0) })
            if removing { picked.subtract(ok) } else { picked.formUnion(ok) }
            selection = picked
            print("\(ok.count) found\(removing ? ", \(ok.count) removed" : ""), \(picked.count) total")
        }
        while true {
            let r = await ask(InputRequest(removing ? "Remove objects" : msg, kinds: [.selection], keywords: Editor.selectionKeywords))
            switch r {
            case .selection(let ids): apply(ids)
            case .keyword(let k):
                switch k {
                case "All": apply(doc.allIDs)
                case "Last": if let l = (doc.entities.map(\.id) + doc.elements.map(\.id)).filter({ isSelectable($0) }).max() { apply([l]) }
                case "Previous": apply(Array(previousSelection))
                case "Add": removing = false
                case "Remove": removing = true
                case "Window", "Crossing", "BOX":
                    guard case .point(let a) = await ask(InputRequest("Specify first corner", kinds: [.point])) else { continue }
                    guard case .point(let b) = await ask(InputRequest("Specify opposite corner", kinds: [.point], base: a)) else { continue }
                    let crossing = k == "Crossing" || (k == "BOX" && b.x < a.x)
                    apply(select(in: BBox2(points: [a, b]), crossing: crossing))
                case "WPolygon", "CPolygon", "Fence":
                    var pts: [Vec2] = []
                    while true {
                        let r2 = await ask(InputRequest(pts.isEmpty ? "First \(k == "Fence" ? "fence" : "polygon") point" : "Specify endpoint of line", kinds: [.point], keywords: pts.isEmpty ? [] : ["Undo"], base: pts.last))
                        if case .point(let p) = r2 { pts.append(p) }
                        else if case .keyword("Undo") = r2 { _ = pts.popLast() }
                        else if case .cancel = r2 { selection = []; throw CommandError.cancelled }
                        else { break }
                    }
                    let mode: SelectionGeometry.Mode = k == "Fence" ? .fence : (k == "WPolygon" ? .windowPolygon : .crossingPolygon)
                    apply(SelectionGeometry.select(doc: doc, polygon: pts, mode: mode, level: doc.currentLevel))
                case "Group":
                    if let g = try await getWord("Enter group name") {
                        apply(doc.entities.filter { $0.props["group"]?.caseInsensitiveCompare(g) == .orderedSame }.map(\.id))
                    }
                default: break
                }
            case .enter:
                previousSelection = picked
                return Array(picked)
            case .cancel: selection = []; throw CommandError.cancelled
            default: break
            }
        }
    }

    public static let selectionKeywords = ["All", "Last", "Previous", "Window", "Crossing", "BOX", "WPolygon", "CPolygon", "Fence", "Add", "Remove", "Group"]

    /// Adds the other members of groups (entity prop "group") when PICKSTYLE is on (default).
    public func expandGroups(_ ids: [EntityID]) -> [EntityID] {
        guard doc.variable("PICKSTYLE") != "0" else { return ids }
        let groups = Set(ids.compactMap { doc.entity($0)?.props["group"] ?? doc.element($0)?.props["group"] }.filter { BlockTools.isSelectable($0, doc) })
        guard !groups.isEmpty else { return ids }
        var out = ids
        let have = Set(ids)
        for e in doc.entities where !have.contains(e.id) {
            if let g = e.props["group"], groups.contains(g), isSelectable(e.id) { out.append(e.id) }
        }
        for el in doc.elements where !have.contains(el.id) {
            if let g = el.props["group"], groups.contains(g), isSelectable(el.id) { out.append(el.id) }
        }
        return out
    }
    public var previousSelection: Set<EntityID> = []
    /// True while a prompt waits for the user at a macro pause ("\\").
    public var pausedForUser = false
    /// Script nesting depth, interruption flag and the lines left when a script was interrupted (RESUME).
    public var scriptDepth = 0
    public var scriptInterrupted = false
    public var pendingScript: [String]?

    /// Runs a menu/button macro: tokens separated by spaces, ";" = Enter, "\\" = pause for user input, leading ^C^C cancels.
    public func runMacro(_ macro: String) {
        if activeCommand != nil && macro.hasPrefix("^C") { cancelCommand() }
        let tokens = UserAliases.macroTokens(macro)
        guard let first = tokens.first(where: { !$0.isEmpty && $0 != MacroPause.mark }) else { return }
        let idx = tokens.firstIndex(of: first)!
        queuedInputs = Array(tokens[(idx + 1)...])
        start(first.hasPrefix("_") ? String(first.dropFirst()) : first)
    }

    // MARK: Script recording, undo groups, transparent commands
    /// Active script recorder (SCRIPTRECORD); typed lines and UI inputs are captured as script lines.
    public var recorder: ScriptRecorder?
    /// Action macro recorder (ACTRECORD … ACTSTOP).
    public var actionRecorder: ScriptRecorder?
    /// Background work started by a command (ACTPLAY, SCRIPT) that outlives it; awaitable by scripts and tests.
    public var backgroundTask: Task<Void, Never>?
    /// Command lines typed while no command was running (most recent last).
    public private(set) var commandHistory: [String] = []
    /// Values typed at prompts (recent input), most recent last.
    public private(set) var recentInputs: [String] = []
    /// When set, every command line is also appended to this file (persistent command history).
    public static var historyFile: URL?
    public static let historyLimit = 1000

    func recordHistory(_ line: String, atPrompt: Bool) {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if atPrompt {
            recentInputs.removeAll { $0 == t }
            recentInputs.append(t)
            if recentInputs.count > 200 { recentInputs.removeFirst(recentInputs.count - 200) }
            return
        }
        commandHistory.append(t)
        if commandHistory.count > Editor.historyLimit { commandHistory.removeFirst(commandHistory.count - Editor.historyLimit) }
        if let url = Editor.historyFile { CommandHistoryFile.append(t, to: url) }
    }
    /// Replaces the in-memory command history (e.g. loaded from the history file).
    public func setCommandHistory(_ lines: [String]) { commandHistory = Array(lines.suffix(Editor.historyLimit)) }
    public func clearHistory() { commandHistory = []; recentInputs = [] }
    /// History entry `back` steps before the latest (1 = previous command line), optionally only those starting with a prefix.
    public func historyEntry(back: Int, prefix: String = "") -> String? {
        let h = prefix.isEmpty ? commandHistory : commandHistory.filter { $0.uppercased().hasPrefix(prefix.uppercased()) }
        guard back >= 1, back <= h.count else { return nil }
        return h[h.count - back]
    }

    /// The last script recorded with SCRIPTRECORD when no file was given.
    public var lastRecordedScript: String?
    /// Objects removed by the last ERASE (restored by OOPS).
    public var lastErased: (entities: [Entity], elements: [BIMElement])?
    /// Active solve-based drag (see `beginDragSolve` / `dragSolve(point:)` / `endDragSolve`).
    public internal(set) var constraintDrag: ConstraintDragState?
    /// Layer settings before each command that changed them (LAYERP), most recent last.
    public var layerPrevious: [(layers: [Layer], current: String)] = []
    /// Selection cycling state (SELECTIONCYCLING): last pick point and index into the overlapping candidates.
    public var pickCycle: (point: Vec2, index: Int)?
    /// Modes of a one-shot snap override while its "of" prompt is active (see EditorSnapOverride.swift).
    var activeSnapOverride: Set<SnapKind>?
    private var inSubmit = false
    /// Set by UNDO BEgin: commands inside the group are recorded as one undo step at UNDO End.
    public var undoGroupActive = false
    var undoGroupStart: ArchiDocument?
    var undoMarks: [Int] = []
    /// Closes an UNDO BEgin group: everything since BEgin becomes one undo step.
    func endUndoGroup() {
        undoGroupActive = false
        if let start = undoGroupStart, start != doc { history.record("Group", before: start); isDirty = true }
        undoGroupStart = nil
    }
    public private(set) var transparentCommand: CommandDef?

    /// Runs a non-modifying command (ZOOM, PAN, SETVAR, DIST...) inside the active one, then restores its prompt.
    /// Returns false when the command cannot run transparently.
    @discardableResult
    public func runTransparent(_ name: String, inputs: [String] = []) -> Bool {
        guard let def = registry.lookup(name) else { print("Unknown command \"\(name.uppercased())\"."); return true }
        guard activeCommand != nil, transparentCommand == nil, let savedCont = continuation, let savedReq = request else { return false }
        guard !def.modifies || Editor.transparentAllowed.contains(def.name) else {
            print("** \(def.name) cannot be used transparently. **"); print(savedReq.promptText); return true
        }
        let savedQueue = queuedInputs
        continuation = nil
        queuedInputs = inputs
        transparentCommand = def
        print(">>\(def.name)")
        Task { @MainActor in
            do { try await def.run(self) } catch CommandError.invalid(let m) { self.print(m) } catch { self.print("*Cancel*") }
            self.transparentCommand = nil
            self.queuedInputs = savedQueue
            self.request = savedReq
            self.continuation = savedCont
            self.print("Resuming \(self.activeCommand?.name ?? "") command.")
            self.print(savedReq.promptText)
            self.onPromptChange?()
        }
        return true
    }
    /// Setting commands that change only settings/variables may run transparently.
    static let transparentAllowed: Set<String> = ["SETVAR", "ORTHO", "OSNAP", "SNAP", "GRIDDISPLAY", "UCS", "CANNOSCALE"]

    /// Suspends until the running command waits for input with nothing queued, or finishes.
    public func waitForInputOrIdle() async {
        var n = 0
        while activeCommand != nil && !(continuation != nil && queuedInputs.isEmpty && transparentCommand == nil) && n < 10000 {
            await Task.yield(); n += 1
        }
    }

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
    /// Dynamic UCS (PRC-036): the solid face that became the temporary work plane of the running command.
    public var dynamicFace: DynamicUCS.Face?

    public func isSelectable(_ id: EntityID) -> Bool {
        if let e = doc.entity(id) { return doc.isEditable(layer: e.layer) }
        if let e = doc.element(id) { return doc.isEditable(layer: e.layer) }
        return false
    }

    /// Topmost selectable object near a point: nearest wins; at equal distance the one drawn on top (later in draw order).
    /// Only objects that are displayed in the current view and lie on unlocked, visible, thawed layers are considered.
    public func pick(at p: Vec2, tolerance: Double) -> EntityID? {
        var best: (EntityID, Double)?
        let f = PickFilter(doc)
        for e in doc.entities where f.pickable(e) {
            let d = GeometryOps.distance(from: p, to: e.geometry, doc: doc)
            if d <= tolerance, d <= (best?.1 ?? .infinity) + 1e-12 * max(1, tolerance) { best = (e.id, min(d, best?.1 ?? d)) }
        }
        for el in doc.elements where f.pickable(el) {
            let d = PlanRepresentation.distance(from: p, to: el, doc: doc)
            if d <= tolerance, d < (best?.1 ?? .infinity) { best = (el.id, d) }
        }
        return best?.0
    }

    /// Objects inside a window (fully) or crossing it.
    public func select(in box: BBox2, crossing: Bool) -> [EntityID] {
        var out: [EntityID] = []
        let f = PickFilter(doc)
        for e in doc.entities where f.pickable(e) {
            let b = GeometryOps.bounds(e.geometry, doc: doc)
            if b.isEmpty { continue }
            if box.contains(b) || (crossing && box.intersects(b) && GeometryOps.crosses(e.geometry, box: box, doc: doc)) { out.append(e.id) }
        }
        for el in doc.elements where f.pickable(el) {
            let b = PlanRepresentation.bounds(el, doc: doc)
            if b.isEmpty { continue }
            if box.contains(b) || (crossing && box.intersects(b)) { out.append(el.id) }
        }
        return out
    }

    // MARK: Direct edits (scripts, UI panels)
    public func transaction(_ label: String, _ body: (inout ArchiDocument) throws -> Void) rethrows {
        let before = doc
        var d = doc
        try body(&d)
        if d != before { DocumentUpdaters.run(&d); history.record(label, before: before); doc = d; isDirty = true }
    }
    public func undo() {
        if let (d, label) = history.undo(current: doc) { doc = d; selection = selection.filter { doc.contains($0) }; print("Undo \(label)") }
        else { print("Nothing to undo.") }
    }
    public func redo() {
        if let (d, label) = history.redo(current: doc) { doc = d; print("Redo \(label)") }
        else { print("Nothing to redo.") }
    }
    public func replaceDocument(_ d: ArchiDocument, url: URL?) {
        history = UndoHistory(); selection = []; doc = d; fileURL = url; isDirty = false
    }
}
