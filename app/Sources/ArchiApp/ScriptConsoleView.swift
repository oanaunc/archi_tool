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
    init(model: AppModel) { self.model = model }

    struct ConsoleLine: Identifiable { enum Kind { case input, output, value, error }
        let id = UUID(); let kind: Kind; let text: String }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { run() } label: { Label(running ? "Running…" : "Run", systemImage: "play.fill") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(running)
                    .help("Run script (⌘↩)")
                Menu("Examples") {
                    ForEach(ScriptExamples.all, id: \.name) { ex in Button(ex.name) { code = ex.code } }
                }.fixedSize()
                Button { open() } label: { Image(systemName: "folder") }.help("Open .js file")
                Button { save() } label: { Image(systemName: "square.and.arrow.down") }.help("Save as .js file")
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
                CodeEditor(text: $code, onRun: run)
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
                                    .id(l.id)
                            }
                        }.padding(8)
                    }
                    .background(Color(white: 0.09))
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
        }
    }

    private func run() {
        guard !running else { return }
        let src = code
        guard !src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        running = true
        let engine = ScriptEngine.forModel(model)
        engine.onOutput = { line in
            lines.append(ConsoleLine(kind: line.hasPrefix("✖") ? .error : .output, text: line))
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

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
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

private final class ScriptTextView: NSTextView {
    var onRun: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onRun?(); return }
        super.keyDown(with: event)
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
