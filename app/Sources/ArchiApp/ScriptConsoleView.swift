// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// JavaScript console: editor, Run (⌘↩), output, examples, load/save .js.
struct ScriptConsoleView: View {
    @ObservedObject var model: AppModel
    @AppStorage("archi.script.code") private var code = ScriptExamples.all[3].code
    @State private var lines: [ConsoleLine] = []
    @State private var running = false
    @State private var showAPI = false
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "archi.script.history") ?? []
    @State private var selectedText = ""
    init(model: AppModel) { self.model = model }

    struct ConsoleLine: Identifiable { enum Kind { case input, output, value, error, warning }
        let id = UUID(); let kind: Kind; let text: String }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { run() } label: { Label(running ? "Running…" : "Run", systemImage: "play.fill") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(running)
                    .help("Run script (⌘↩)")
                Button { runSelection() } label: { Label("Run Selection", systemImage: "text.cursor") }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(running || selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Run only the selected code (⇧⌘↩)")
                Menu("Examples") {
                    ForEach(ScriptExamples.all, id: \.name) { ex in Button(ex.name) { code = ex.code } }
                }.fixedSize()
                Menu("Snippets") {
                    Section("Built-in") {
                        ForEach(ScriptSnippets.builtIn, id: \.0) { name, body in Button(name) { insertSnippet(body) } }
                    }
                    let user = ScriptSnippets.user
                    if !user.isEmpty {
                        Section("My Snippets") {
                            ForEach(user.keys.sorted(), id: \.self) { k in Button(k) { insertSnippet(user[k] ?? "") } }
                        }
                        Menu("Delete Snippet") {
                            ForEach(user.keys.sorted(), id: \.self) { k in Button(k) { ScriptSnippets.remove(k); lines.append(ConsoleLine(kind: .output, text: "Snippet \"\(k)\" deleted.")) } }
                        }
                    }
                    Divider()
                    Button("Save Selection as Snippet…") { saveSnippet() }
                        .disabled(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.fixedSize().help("Insert a code snippet at the cursor (⌃Space or Esc completes the archi API)")
                Menu("Library") {
                    let scripts = ScriptLibrary.scripts()
                    if scripts.isEmpty { Text("The library is empty") }
                    ForEach(scripts, id: \.self) { u in
                        Menu(u.lastPathComponent) {
                            Button("Open in Editor") { if let t = try? String(contentsOf: u, encoding: .utf8) { code = t } }
                            Button("Run") { model.runScriptFile(u) }
                        }
                    }
                    Divider()
                    Button("Save Editor to Library…") { saveToLibrary() }
                    Button("Save as startup.js") { saveToLibrary(name: "startup.js") }
                    Button("Open Library Folder") { ScriptLibrary.revealFolder() }
                }.fixedSize()
                Menu {
                    if history.isEmpty { Text("No scripts run yet") }
                    ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                        Button(String(h.split(separator: "\n").first ?? "").prefix(60) + (h.contains("\n") ? " …" : "")) { code = h }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .fixedSize().help("Recently run scripts")
                Button { open() } label: { Image(systemName: "folder") }.help("Open .js file")
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }.help("Save as .js file")
                Button { showAPI.toggle() } label: { Image(systemName: "book") }.help("archi API reference")
                    .popover(isPresented: $showAPI, arrowEdge: .bottom) { ScriptAPIReference(insert: { code += (code.hasSuffix("\n") || code.isEmpty ? "" : "\n") + $0 }) }
                Spacer()
                Button { ScriptEngine.forModel(model).reset(); lines.append(ConsoleLine(kind: .output, text: "JavaScript context reset.")) } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Reset the JavaScript context")
                Button { lines.removeAll() } label: { Image(systemName: "trash") }.help("Clear output")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            VSplitView {
                CodeEditor(text: $code, onRun: run, onSelection: { selectedText = $0 })
                    .frame(minHeight: 120)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(lines) { l in
                                Text(l.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(color(l.kind))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onTapGesture(count: 2) { if l.kind == .error { goToLine(l.text) } }
                                    .help(l.kind == .error && l.text.contains("(line ") ? "Double-click to go to the line" : "")
                                    .id(l.id)
                            }
                        }.padding(8)
                    }
                    .background(Color(white: 0.09))
                    .contextMenu { Button("Copy Output") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string) } }
                    .onChange(of: lines.count) { _ in if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .frame(minHeight: 80)
            }
        }
    }

    private func color(_ k: ConsoleLine.Kind) -> Color {
        switch k {
        case .input: return Color(red: 0.961, green: 0.773, blue: 0.094)
        case .output: return Color(white: 0.88)
        case .value: return Color(white: 0.6)
        case .error: return Color(red: 1, green: 0.42, blue: 0.38)
        case .warning: return Color(red: 1, green: 0.8, blue: 0.35)
        }
    }

    /// Error lines mentioning "(line N" jump to that line in the editor.
    private func goToLine(_ text: String) {
        guard let r = text.range(of: "(line "), let n = Int(text[r.upperBound...].prefix { $0.isNumber }), let tv = ScriptTextView.active else { return }
        let ns = tv.string as NSString
        var loc = 0
        for _ in 1..<max(n, 1) { let lr = ns.lineRange(for: NSRange(location: loc, length: 0)); loc = NSMaxRange(lr); if loc >= ns.length { break } }
        let lr = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(lr); tv.scrollRangeToVisible(lr); tv.showFindIndicator(for: lr)
    }

    private func runSelection() { run(source: selectedText) }

    private func insertSnippet(_ body: String) {
        if let tv = ScriptTextView.active, tv.window != nil { tv.insertAtCursor(body) }
        else { code += (code.hasSuffix("\n") || code.isEmpty ? "" : "\n") + body }
    }

    private func saveSnippet() {
        let a = NSAlert()
        a.messageText = "Save Snippet"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        tf.stringValue = "My snippet \(ScriptSnippets.user.count + 1)"
        a.accessoryView = tf
        a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        ScriptSnippets.save(n, selectedText)
        lines.append(ConsoleLine(kind: .output, text: "Snippet \"\(n)\" saved."))
    }

    private func saveToLibrary(name: String? = nil) {
        var n = name
        if n == nil {
            let a = NSAlert()
            a.messageText = "Save to Script Library"
            let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
            tf.stringValue = "my-script.js"
            a.accessoryView = tf
            a.addButton(withTitle: "Save"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            n = tf.stringValue
        }
        do {
            let u = try ScriptLibrary.save(name: n ?? "script.js", code: code)
            lines.append(ConsoleLine(kind: .output, text: "Saved to the library: \(u.lastPathComponent)"))
        } catch { lines.append(ConsoleLine(kind: .error, text: "✖ " + error.localizedDescription)) }
    }

    private func run() { run(source: code) }

    private func run(source: String) {
        guard !running else { return }
        let src = source
        guard !src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.removeAll { $0 == src }
        history.insert(src, at: 0)
        if history.count > 15 { history.removeLast(history.count - 15) }
        UserDefaults.standard.set(history, forKey: "archi.script.history")
        running = true
        let engine = ScriptEngine.forModel(model)
        engine.onOutput = { line in
            lines.append(ConsoleLine(kind: line.hasPrefix("✖") ? .error : line.hasPrefix("⚠") ? .warning : .output, text: line))
            if lines.count > 3000 { lines.removeFirst(1000) }
        }
        let firstLine = src.split(separator: "\n").first.map(String.init) ?? ""
        lines.append(ConsoleLine(kind: .input, text: "▶ " + firstLine + (src.contains("\n") ? " …" : "")))
        Task { @MainActor in
            let r = await engine.evaluate(src)
            // Output lines are streamed through onOutput; wait for queued main-thread deliveries.
            await Task.yield()
            if let v = r.value, v != "null" { lines.append(ConsoleLine(kind: .value, text: "⇐ " + v)) }
            running = false
        }
    }

    private func open() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.javaScript, .plainText]
        guard p.runModal() == .OK, let url = p.url, let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        code = s
    }

    private func save() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.javaScript]
        p.nameFieldStringValue = "script.js"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try code.write(to: url, atomically: true, encoding: .utf8) }
        catch { lines.append(ConsoleLine(kind: .error, text: "✖ " + error.localizedDescription)) }
    }
}

// MARK: - Code editor

private struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var onRun: () -> Void
    var onSelection: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let old = scroll.documentView as! NSTextView
        let tv = ScriptTextView(frame: old.frame)
        tv.autoresizingMask = old.autoresizingMask
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = tv
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.allowsUndo = true
        tv.isRichText = false
        tv.usesFindBar = true
        tv.backgroundColor = NSColor(white: 0.115, alpha: 1)
        tv.insertionPointColor = NSColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1)
        tv.textColor = NSColor(white: 0.9, alpha: 1)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.delegate = context.coordinator
        tv.onRun = onRun
        tv.string = text
        context.coordinator.highlight(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? ScriptTextView else { return }
        tv.onRun = onRun
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ p: CodeEditor) { parent = p }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            let r = tv.selectedRange()
            let sel = r.length > 0 ? (tv.string as NSString).substring(with: r) : ""
            let cb = parent.onSelection
            DispatchQueue.main.async { cb(sel) }
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
            // Typing "archi." or the opening quote of archi.run(" pops up the completion list.
            let loc = tv.selectedRange().location
            let ns = tv.string as NSString
            if loc >= 6, ns.substring(with: NSRange(location: loc - 6, length: 6)) == "archi." {
                DispatchQueue.main.async { tv.complete(nil) }
            } else if loc >= 11, ns.substring(with: NSRange(location: loc - 11, length: 11)) == "archi.run(\"" {
                DispatchQueue.main.async { tv.complete(nil) }
            }
        }

        static let keywords = try! NSRegularExpression(pattern: "\\b(const|let|var|function|return|if|else|for|while|do|of|in|new|break|continue|switch|case|default|try|catch|finally|throw|typeof|class|this|true|false|null|undefined)\\b")
        static let numbers = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")
        static let strings = try! NSRegularExpression(pattern: "\"(\\\\.|[^\"\\\\])*\"|'(\\\\.|[^'\\\\])*'|`[^`]*`")
        static let comments = try! NSRegularExpression(pattern: "//[^\\n]*|/\\*[\\s\\S]*?\\*/")
        static let api = try! NSRegularExpression(pattern: "\\b(archi|console|Math)\\b")

        func highlight(_ tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            let full = NSRange(location: 0, length: ts.length)
            let s = ts.string
            ts.beginEditing()
            ts.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor(white: 0.9, alpha: 1)], range: full)
            func paint(_ re: NSRegularExpression, _ c: NSColor) {
                for m in re.matches(in: s, range: full) { ts.addAttribute(.foregroundColor, value: c, range: m.range) }
            }
            paint(Coordinator.numbers, NSColor(srgbRed: 0.72, green: 0.6, blue: 1, alpha: 1))
            paint(Coordinator.keywords, NSColor(srgbRed: 1, green: 0.45, blue: 0.6, alpha: 1))
            paint(Coordinator.api, NSColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1))
            paint(Coordinator.strings, NSColor(srgbRed: 0.6, green: 0.85, blue: 0.5, alpha: 1))
            paint(Coordinator.comments, NSColor(white: 0.5, alpha: 1))
            ts.endEditing()
        }
    }
}

final class ScriptTextView: NSTextView {
    var onRun: (() -> Void)?
    /// The editor that last had focus (snippets insert at its cursor).
    static weak var active: ScriptTextView?
    override func becomeFirstResponder() -> Bool { ScriptTextView.active = self; return super.becomeFirstResponder() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onRun?(); return }
        // ⌃Space or Esc: complete the archi API / command names.
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 49 && f == .control) || (event.keyCode == 53 && f.isEmpty) { complete(nil); return }
        super.keyDown(with: event)
    }
    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let ns = string as NSString
        let prefix = ns.substring(with: charRange)
        let before = ns.substring(to: charRange.location)
        let list = ScriptCompletion.candidates(prefix: prefix, before: before)
        index.pointee = list.isEmpty ? -1 : 0
        return list
    }
    /// Inserts text at the cursor (snippets), keeping undo.
    func insertAtCursor(_ text: String) {
        window?.makeFirstResponder(self)
        insertText(text, replacementRange: selectedRange())
    }
    override func insertTab(_ sender: Any?) { insertText("  ", replacementRange: selectedRange()) }
    override func insertNewline(_ sender: Any?) {
        // Keep the current line's indentation.
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lineRange)
        var indent = String(line.prefix { $0 == " " || $0 == "\t" })
        if line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{") { indent += "  " }
        super.insertNewline(sender)
        insertText(indent, replacementRange: selectedRange())
    }
}

// MARK: - Examples

enum ScriptExamples {
    struct Example { let name: String; let code: String }
    static let all: [Example] = [
        Example(name: "Draw a spiral", code: """
// Archimedean spiral as one polyline (units: mm)
const pts = [];
for (let i = 0; i <= 720; i += 5) {
  const t = i * Math.PI / 180;
  const r = 200 + 40 * t;
  pts.push([r * Math.cos(t), r * Math.sin(t)]);
}
const id = archi.add({ type: "polyline", points: pts, layer: "0", color: "yellow" });
archi.print("Spiral", id, "with", pts.length, "vertices");
archi.run("ZOOM E");
"""),
        Example(name: "Grid of columns", code: """
// Structural grid with columns at every intersection
const nx = 5, ny = 4, bay = 6000;
for (let i = 0; i < nx; i++)
  archi.addElement({ type: "grid", start: [i * bay, -1500], end: [i * bay, (ny - 1) * bay + 1500], label: String.fromCharCode(65 + i) });
for (let j = 0; j < ny; j++)
  archi.addElement({ type: "grid", start: [-1500, j * bay], end: [(nx - 1) * bay + 1500, j * bay], label: String(j + 1) });
let n = 0;
for (let i = 0; i < nx; i++)
  for (let j = 0; j < ny; j++) { archi.column(i * bay, j * bay, { size: 400, height: 3000 }); n++; }
archi.print(n, "columns placed");
"""),
        Example(name: "Parametric tower", code: """
// Twisting tower: rotated floor slabs around a concrete core
const floors = 24, h = 3200, w = 24000, twist = 2.5; // degrees per floor
function square(size, angleDeg) {
  const a = angleDeg * Math.PI / 180, s = size / 2, pts = [];
  for (const [x, y] of [[-s, -s], [s, -s], [s, s], [-s, s]])
    pts.push([x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)]);
  return pts;
}
for (let i = 0; i < floors; i++)
  archi.slab(square(w - i * 250, i * twist), { thickness: 300, topOffset: i * h, level: 0 });
archi.add({ type: "solid", kind: "box", origin: [-4000, -4000, 0], size: [8000, 8000, floors * h + 2000], layer: "A-ELEMENTS" });
archi.print("Tower with", floors, "floors, height", (floors * h / 1000).toFixed(1), "m");
"""),
        Example(name: "House walls", code: """
// Simple house: four walls, a door, windows, a floor slab and a room
const W = 10000, D = 8000, t = 300;
const walls = [
  archi.wall(0, 0, W, 0, { thickness: t, height: 2800 }),
  archi.wall(W, 0, W, D, { thickness: t, height: 2800 }),
  archi.wall(W, D, 0, D, { thickness: t, height: 2800 }),
  archi.wall(0, D, 0, 0, { thickness: t, height: 2800 }),
];
archi.door(walls[0], 2000, { width: 1000, height: 2100 });
archi.window(walls[0], 6500, { width: 2400, height: 1400, sill: 800 });
archi.window(walls[1], 4000, { width: 1600 });
archi.window(walls[2], 5000, { width: 3000, height: 1600, sill: 600 });
archi.slab([[0, 0], [W, 0], [W, D], [0, D]], { thickness: 250, topOffset: 0 });
archi.room([[150, 150], [W - 150, 150], [W - 150, D - 150], [150, D - 150]], "Living");
archi.print("House created:", archi.elements().length, "elements");
"""),
        Example(name: "Inspect the document", code: """
// Summaries and queries
const s = archi.summary();
archi.print("Project:", s.project.name, "·", s.entityCount, "entities,", s.elementCount, "elements");
for (const w of archi.elements({ type: "wall" }))
  archi.print("wall", w.id, "length", Math.hypot(w.geometry.end.x - w.geometry.start.x, w.geometry.end.y - w.geometry.start.y).toFixed(0));
archi.layers().map(l => l.name);
"""),
    ]
}

// MARK: - API reference

struct ScriptAPIReference: View {
    var insert: (String) -> Void
    static let entries: [(String, String, String)] = [
        ("archi.run(line)", "Runs a command line exactly like typing it; returns the log lines.", "archi.run(\"CIRCLE 0,0 500\");"),
        ("archi.print(...values)", "Prints to the console and the command history.", "archi.print(\"Hello\");"),
        ("archi.add(entity)", "Adds a 2D/3D entity: {type:'line'|'circle'|'polyline'|'text'|'solid'…}. Returns its id.", "archi.add({ type: \"line\", a: [0, 0], b: [1000, 0] });"),
        ("archi.addElement(element)", "Adds a building element: wall, slab, column, grid, room…", "archi.addElement({ type: \"grid\", start: [0, -1000], end: [0, 9000], label: \"A\" });"),
        ("archi.wall(x1, y1, x2, y2, opts)", "Wall between two points (thickness, height, level). Returns the wall id.", "const w = archi.wall(0, 0, 6000, 0, { thickness: 200, height: 3000 });"),
        ("archi.door(wallId, offset, opts)", "Door hosted in a wall at an offset from its start.", "archi.door(w, 1500, { width: 900 });"),
        ("archi.window(wallId, offset, opts)", "Window hosted in a wall (width, height, sill).", "archi.window(w, 3500, { width: 1200, sill: 900 });"),
        ("archi.opening(wallId, offset, opts)", "Plain wall opening.", "archi.opening(w, 5000, { width: 1000, height: 2100 });"),
        ("archi.slab(points, opts)", "Floor slab from a boundary (thickness, topOffset, level).", "archi.slab([[0,0],[6000,0],[6000,4000],[0,4000]], { thickness: 250 });"),
        ("archi.room(points, name)", "Room / space with a name tag and area.", "archi.room([[0,0],[6000,0],[6000,4000],[0,4000]], \"Office\");"),
        ("archi.column(x, y, opts)", "Column at a point (size, height).", "archi.column(0, 0, { size: 400 });"),
        ("archi.entities(filter?)", "Lists entities; filter by {type, layer}.", "archi.entities({ type: \"circle\" }).length;"),
        ("archi.elements(filter?)", "Lists building elements; filter by {type, level}.", "archi.elements({ type: \"wall\" });"),
        ("archi.get(id)", "One entity or element as JSON.", "archi.get(1);"),
        ("archi.update(id, changes)", "Changes properties of an entity or element.", "archi.update(1, { layer: \"A-WALL\" });"),
        ("archi.remove(ids)", "Deletes entities/elements.", "archi.remove([1, 2]);"),
        ("archi.select(ids) / archi.selection()", "Sets or reads the selection.", "archi.select(archi.elements({ type: \"wall\" }).map(e => e.id));"),
        ("archi.layers() / archi.levels()", "Layers and levels of the document.", "archi.layers().map(l => l.name);"),
        ("archi.setVar(name, value) / getVar(name)", "System variables (saved in the drawing).", "archi.setVar(\"LTSCALE\", \"2\");"),
        ("archi.doc() / archi.summary()", "The whole document as JSON / a short summary.", "archi.summary();"),
        ("archi.undo() / archi.redo()", "Undo and redo.", "archi.undo();"),
        ("archi.commands()", "All command names with aliases and summaries.", "archi.commands().length;"),
        ("archi.evaluateGraph(graph) / archi.bakeGraph(graph)", "Evaluates a node graph object (Node Editor ▸ Graphs ▸ Export as Script) or bakes its output (one undo step).", "archi.bakeGraph(graph).length;"),
        ("archi.on(event, fn) / archi.off(event?)", "Event hooks: selectionChanged (ids), documentChanged ({changeCount}), elementAdded (ids), elementRemoved (ids), saved (path), commandEnded (name). Edits made inside a handler do not fire the hooks again.", "archi.on(\"elementAdded\", ids => archi.print(\"added\", ids.length));"),
        ("archi.panel({title, items})", "Script-defined panel: items {type:'number'|'field'|'toggle'|'text'|'button', name, label, value, min, max, call:'fnName' | command:'LINE'}. Buttons call the global function with the field values.", "function build(v) { archi.print(v.rise); }\narchi.panel({ title: \"Stairs\", items: [{ type: \"number\", name: \"rise\", label: \"Rise\", value: 175 }, { type: \"button\", label: \"Build\", call: \"build\" }] });"),
        ("console.warn / console.error / console.assert / console.time / console.timeEnd / console.count / console.trace", "Debug output: warnings and errors are coloured; errors show the source line and the call stack.", "console.time(\"walls\"); /* … */ console.timeEnd(\"walls\");"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("archi API").font(.system(size: 13, weight: .semibold)).padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ScriptAPIReference.entries, id: \.0) { sig, doc, ex in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(sig).font(.system(size: 11.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                                Spacer()
                                Button("Insert") { insert(ex) }.buttonStyle(FlatButtonStyle(compact: true))
                            }
                            Text(doc).font(Theme.fontSmall).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                            Text(ex).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textDim).textSelection(.enabled)
                        }
                    }
                    Text("Full reference: docs/SCRIPTING.md (Help ▸ User Guide).").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .padding(12)
            }
        }
        .frame(width: 460, height: 480)
        .background(Theme.panel)
    }
}

// MARK: - Completion and snippets

/// Completion candidates for the script editor: archi API members after "archi.", command names inside
/// archi.run("…"), otherwise JavaScript keywords, globals and archi.
@MainActor
enum ScriptCompletion {
    static let apiMembers: [String] = {
        var names = ScriptAPIReference.entries.flatMap { sig, _, _ -> [String] in
            sig.components(separatedBy: " / ").compactMap { part in
                let t = part.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("archi.") || !t.contains(".") else { return nil }
                let name = t.hasPrefix("archi.") ? String(t.dropFirst(6)) : t
                return name.split(separator: "(").first.map(String.init)
            }
        }
        names += ["print", "run", "doc", "summary", "entities", "elements", "get", "add", "addElement", "update", "remove", "select", "selection",
                  "setVar", "getVar", "layers", "levels", "wall", "door", "window", "opening", "slab", "room", "column", "undo", "redo", "commands"]
        return Array(Set(names)).sorted()
    }()
    static let globals = ["archi", "console", "Math", "JSON", "Array", "Object", "Number", "String", "const", "let", "function", "return",
                          "for", "while", "if", "else", "true", "false", "null", "undefined", "Math.PI", "Math.sin", "Math.cos", "Math.sqrt", "Math.round"]

    static func candidates(prefix: String, before: String) -> [String] {
        let p = prefix.lowercased()
        if before.hasSuffix("archi.") {
            return apiMembers.filter { p.isEmpty || $0.lowercased().hasPrefix(p) }
        }
        // Inside archi.run("…: complete command names (and aliases).
        if let r = before.range(of: "archi.run(\"", options: .backwards), !before[r.upperBound...].contains("\"") {
            CommandRegistry.shared.ensureBuiltins()
            let all = CommandRegistry.shared.sorted.flatMap { [$0.name] + $0.aliases }
            return Array(Set(all.filter { p.isEmpty || $0.lowercased().hasPrefix(p) })).sorted().prefix(200).map { $0 }
        }
        guard !p.isEmpty else { return [] }
        return globals.filter { $0.lowercased().hasPrefix(p) && $0.lowercased() != p }
    }
}

/// Reusable code snippets: built-in patterns plus user snippets kept in the preferences.
enum ScriptSnippets {
    static let key = "archi.script.snippets"
    static let builtIn: [(String, String)] = [
        ("Loop over selection", "for (const id of archi.selection()) {\n  const o = archi.get(id);\n  archi.print(id, o.type);\n}\n"),
        ("Walls of a rectangle", "const [w, h] = [8000, 6000];\nconst pts = [[0,0],[w,0],[w,h],[0,h]];\nfor (let i = 0; i < 4; i++) {\n  const a = pts[i], b = pts[(i + 1) % 4];\n  archi.wall(a[0], a[1], b[0], b[1], { thickness: 250, height: 3000 });\n}\n"),
        ("Grid of points", "for (let i = 0; i < 5; i++) {\n  for (let j = 0; j < 5; j++) {\n    archi.add({ type: \"point\", p: [i * 1000, j * 1000] });\n  }\n}\n"),
        ("Circle array", "const n = 12, r = 3000;\nfor (let i = 0; i < n; i++) {\n  const t = 2 * Math.PI * i / n;\n  archi.add({ type: \"circle\", center: [r * Math.cos(t), r * Math.sin(t)], radius: 200 });\n}\n"),
        ("Run commands", "archi.run(\"LAYER M A-NOTES \");\narchi.run(\"ZOOM E\");\n"),
        ("Count by type", "const counts = {};\nfor (const e of archi.entities()) counts[e.type] = (counts[e.type] || 0) + 1;\narchi.print(JSON.stringify(counts));\n"),
        ("Rename layers", "for (const l of archi.layers()) {\n  if (l.name.startsWith(\"OLD-\")) archi.run(`RENAME LA ${l.name} ${l.name.slice(4)} `);\n}\n"),
        ("Event hook", "archi.on(\"selectionChanged\", function (ids) {\n  archi.print(ids.length + \" selected\");\n});\n"),
        ("Script panel", "function offsetAll(v) {\n  archi.run(\"OFFSET \" + v.distance);\n}\narchi.panel({ title: \"Tools\", items: [\n  { type: \"number\", name: \"distance\", label: \"Distance\", value: 100, min: 1 },\n  { type: \"button\", label: \"Offset\", call: \"offsetAll\" },\n  { type: \"button\", label: \"Line\", command: \"LINE\" }\n] });\n"),
        ("Try / catch", "try {\n  \n} catch (e) {\n  archi.print(\"Error:\", e.message);\n}\n"),
    ]
    static var user: [String: String] { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
    static func save(_ name: String, _ body: String) { var u = user; u[name] = body; UserDefaults.standard.set(u, forKey: key) }
    static func remove(_ name: String) { var u = user; u[name] = nil; UserDefaults.standard.set(u, forKey: key) }
}
