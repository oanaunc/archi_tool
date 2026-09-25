// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// AutoCAD-style command line: history, prompt with clickable keywords, input with autocomplete.
struct CommandLineView: View {
    @ObservedObject var model: AppModel
    @State private var suggestionIndex = 0
    @State private var suggestionNavigated = false
    @State private var suggestionsDismissed = false
    @State private var historyIndex: Int?
    @State private var expanded = false

    private struct Suggestion: Hashable { var name: String; var command: String; var summary: String }

    private var suggestions: [Suggestion] {
        let t = model.commandInput.trimmingCharacters(in: .whitespaces)
        guard model.editor.isIdle, !suggestionsDismissed, !t.isEmpty, !t.contains(" "), t.first?.isLetter == true else { return [] }
        let reg = model.editor.registry
        return reg.complete(t).prefix(9).compactMap { n in
            guard let d = reg.lookup(n) else { return nil }
            return Suggestion(name: n, command: d.name, summary: d.summary)
        }
    }

    var body: some View {
        let sugg = suggestions
        VStack(spacing: 0) {
            history
            HSeparator()
            inputRow
                .overlay(alignment: .topLeading) {
                    if !sugg.isEmpty {
                        suggestionList(sugg)
                            .offset(x: 30, y: -CGFloat(sugg.count) * 22 - 8)
                    }
                }
        }
        .background(Theme.panel)
        .zIndex(2)
        .onChange(of: model.commandInput) { _ in
            suggestionIndex = 0
            suggestionNavigated = false
            if model.commandInput.isEmpty { suggestionsDismissed = false; historyIndex = nil }
        }
    }

    // MARK: History

    private var history: some View {
        let lines = Array(model.commandLog.suffix(200).enumerated())
        return ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines, id: \.offset) { i, line in
                            Text(line)
                                .font(Theme.mono)
                                .foregroundStyle(color(for: line))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 15)
                                .id(i)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .onChange(of: model.commandLog.count) { _ in
                    if let last = lines.indices.last { proxy.scrollTo(min(last + 1, 199), anchor: .bottom) }
                }
                .onAppear { if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) } }
            }
            IconButton(symbol: expanded ? "chevron.down" : "chevron.up", help: expanded ? "Shrink command history" : "Expand command history") {
                expanded.toggle()
            }
            .padding(4)
        }
        .frame(height: expanded ? 240 : 64)
        .background(Theme.canvas.opacity(0.55))
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("Command: ") { return Theme.text }
        let l = line.lowercased()
        if l.hasPrefix("unknown command") || l.hasPrefix("invalid") || l.hasPrefix("error") || l.contains("cannot") { return Color(hex: 0xF0883E) }
        if line.hasSuffix(":") || line.contains("]:") || line.contains(">:") { return Theme.textDim }
        if line.hasPrefix("*") { return Theme.textDim }
        return Theme.text.opacity(0.88)
    }

    // MARK: Prompt + input

    private var inputRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right.2")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(model.editor.isIdle ? Theme.textDim : Theme.accent)
                .frame(width: 18)
            promptView
            CommandTextField(text: $model.commandInput, focusToken: model.commandFocusToken,
                             placeholder: model.editor.isIdle ? "Type a command" : "",
                             spaceSubmits: { spaceSubmits($0) }, handler: handle)
                .frame(maxWidth: .infinity)
            if !model.editor.isIdle {
                Button { model.cancelCommand() } label: { Text("Esc").font(Theme.fontSmall) }
                    .buttonStyle(FlatButtonStyle(compact: true))
                    .help("Cancel the current command (Esc)")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(Theme.field)
    }

    @ViewBuilder private var promptView: some View {
        if let req = model.editor.request {
            HStack(spacing: 4) {
                Text(req.message).font(Theme.mono).foregroundStyle(Theme.text).lineLimit(1)
                if !req.keywords.isEmpty {
                    Text("[").font(Theme.mono).foregroundStyle(Theme.textDim)
                    ForEach(req.keywords, id: \.self) { kw in
                        Button { model.editor.submit(kw); model.canvas?.focus() } label: {
                            Text(kw)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.accent.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("Choose \(kw)")
                    }
                    Text("]").font(Theme.mono).foregroundStyle(Theme.textDim)
                }
                if let d = req.defaultValue { Text("<\(d)>").font(Theme.mono).foregroundStyle(Theme.textDim) }
                Text(":").font(Theme.mono).foregroundStyle(Theme.textDim)
            }
            .fixedSize()
        } else {
            Text(model.editor.isIdle ? "Command:" : model.promptText)
                .font(Theme.mono).foregroundStyle(Theme.textDim).fixedSize()
        }
    }

    private func suggestionList(_ items: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { i, s in
                HStack(spacing: 8) {
                    Image(systemName: "terminal").font(.system(size: 9)).foregroundStyle(i == suggestionIndex ? Theme.accentText : Theme.textDim)
                    Text(s.name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if s.name != s.command { Text("→ \(s.command)").font(Theme.fontSmall).opacity(0.75) }
                    Spacer(minLength: 12)
                    Text(s.summary).font(Theme.fontSmall).lineLimit(1).opacity(0.8)
                }
                .foregroundStyle(i == suggestionIndex ? Theme.accentText : Theme.text)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(i == suggestionIndex ? Theme.accent : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.commandInput = ""
                    model.submitLine(s.command)
                }
            }
        }
        .frame(width: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x2B2C31)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.separator, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }

    // MARK: Key handling

    private func spaceSubmits(_ text: String) -> Bool {
        if text.filter({ $0 == "\"" }).count % 2 == 1 { return false }
        if let r = model.editor.request, r.kinds.contains(.string), !r.kinds.contains(.point) { return false }
        return true
    }

    private func handle(_ cmd: CommandTextField.Action) -> Bool {
        let sugg = suggestions
        switch cmd {
        case .submit(let text):
            var line = text
            if suggestionNavigated, sugg.indices.contains(suggestionIndex) { line = sugg[suggestionIndex].command }
            model.commandInput = ""
            historyIndex = nil
            model.submitLine(line)
            return true
        case .cancel:
            if !sugg.isEmpty { suggestionsDismissed = true; return true }
            model.cancelCommand()
            model.canvas?.focus()
            return true
        case .up:
            if !sugg.isEmpty { suggestionIndex = (suggestionIndex - 1 + sugg.count) % sugg.count; suggestionNavigated = true; return true }
            let h = model.inputHistory
            guard !h.isEmpty else { return true }
            let i = max(0, (historyIndex ?? h.count) - 1)
            historyIndex = i
            model.commandInput = h[i]
            suggestionsDismissed = true
            return true
        case .down:
            if !sugg.isEmpty { suggestionIndex = (suggestionIndex + 1) % sugg.count; suggestionNavigated = true; return true }
            let h = model.inputHistory
            guard let cur = historyIndex else { return true }
            if cur + 1 < h.count { historyIndex = cur + 1; model.commandInput = h[cur + 1]; suggestionsDismissed = true }
            else { historyIndex = nil; model.commandInput = "" }
            return true
        case .tab:
            if sugg.indices.contains(suggestionIndex) { model.commandInput = sugg[suggestionIndex].name; suggestionsDismissed = true }
            return true
        case .deleteEmpty:
            if model.editor.isIdle && !model.editor.selection.isEmpty {
                if model.has("ERASE") { model.runCommand("ERASE") } else { model.deleteSelection() }
                return true
            }
            return false
        }
    }
}

/// Single-line NSTextField with AutoCAD key handling (Enter/Space submit, Esc cancel, arrows, Tab).
struct CommandTextField: NSViewRepresentable {
    enum Action { case submit(String), cancel, up, down, tab, deleteEmpty }
    @Binding var text: String
    var focusToken: Int
    var placeholder: String
    var spaceSubmits: (String) -> Bool
    var handler: (Action) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        tf.textColor = Theme.nsText
        tf.lineBreakMode = .byClipping
        tf.usesSingleLineMode = true
        tf.cell?.isScrollable = true
        tf.cell?.wraps = false
        tf.delegate = context.coordinator
        tf.stringValue = text
        tf.setAccessibilityLabel("Command line")
        context.coordinator.lastFocus = focusToken
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        tf.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: NSColor(hex: 0x6B6C72), .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)])
        if tf.stringValue != text {
            tf.stringValue = text
            Coordinator.caretToEnd(tf)
        }
        if context.coordinator.lastFocus != focusToken {
            context.coordinator.lastFocus = focusToken
            DispatchQueue.main.async {
                guard let w = tf.window else { return }
                if w.firstResponder !== tf.currentEditor() { w.makeFirstResponder(tf) }
                Coordinator.caretToEnd(tf)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandTextField
        var lastFocus = 0
        init(_ p: CommandTextField) { parent = p }

        static func caretToEnd(_ tf: NSTextField) {
            if let ed = tf.currentEditor() {
                let n = (tf.stringValue as NSString).length
                ed.selectedRange = NSRange(location: n, length: 0)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            var s = tf.stringValue
            if s.hasSuffix(" ") && parent.spaceSubmits(String(s.dropLast())) {
                s.removeLast()
                tf.stringValue = ""
                parent.text = ""
                _ = parent.handler(.submit(s))
                return
            }
            parent.text = s
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
                let s = textView.string
                (control as? NSTextField)?.stringValue = ""
                parent.text = ""
                return parent.handler(.submit(s))
            case #selector(NSResponder.cancelOperation(_:)): return parent.handler(.cancel)
            case #selector(NSResponder.moveUp(_:)): return parent.handler(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.handler(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.handler(.tab)
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
                if textView.string.isEmpty { return parent.handler(.deleteEmpty) }
                return false
            default: return false
            }
        }
    }
}
