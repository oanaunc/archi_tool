// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

// In-place text editor (ANN-003): double-clicking a text object opens an editor over the text on the canvas at its
// drawn size, with bold, italic, underline, font, height and colour. The formatting is stored as whole-text props
// (font/bold/italic/underline) that the canvas, PDF plots and the layered PDF draw, plus the equivalent MTEXT string
// ("mtext" prop), which the DXF writer exports and the DXF reader turns back into the same props.

/// What the editor changes on a text entity (a plain value, applied as one undo step).
struct TextEditState: Equatable {
    var content: String
    var height: Double
    var format: AppRenderInfo.TextFormat
    var color: ColorRef

    init?(entity e: Entity) {
        guard case .text(let t) = e.geometry else { return nil }
        content = t.content.replacingOccurrences(of: "\\P", with: "\n")
        height = t.height
        format = AppRenderInfo.TextFormat(props: e.props) ?? AppRenderInfo.TextFormat()
        color = e.color
    }

    var errors: [String] {
        var out: [String] = []
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("text is empty") }
        if !(height > 0) || !height.isFinite { out.append("height must be positive") }
        return out
    }

    /// Writes the edit to the entity; false when the entity is gone or the edit is invalid.
    @discardableResult
    func apply(id: EntityID, to d: inout ArchiDocument) -> Bool {
        guard errors.isEmpty, let k = d.entityIndex(id), case .text(var t) = d.entities[k].geometry else { return false }
        t.content = content
        t.height = height
        d.entities[k].geometry = .text(t)
        d.entities[k].color = color
        var props = d.entities[k].props
        format.write(to: &props)
        if !format.isPlain {
            // DXF exchange: the MTEXT string with the same whole-text formatting (read back by DXFReader).
            let family = format.font ?? TextStyleFonts.style(t.style, doc: d)?.font ?? "Helvetica"
            props["mtext"] = MTextFormatting.encode(content, font: (format.bold || format.italic || format.font != nil) ? family : nil,
                                                     bold: format.bold, italic: format.italic, underline: format.underline)
        }
        d.entities[k].props = props
        return true
    }
}

@MainActor
final class InPlaceTextEditor: NSView, NSTextViewDelegate {
    private(set) static weak var current: InPlaceTextEditor?

    private weak var model: AppModel?
    private let id: EntityID
    private let original: TextEditState
    private(set) var state: TextEditState
    private let singleLine: Bool
    private let screenPerUnit: CGFloat
    private let styleFont: String
    let textView = NSTextView()
    private let scroll = NSScrollView()
    private let boldButton = NSButton(title: "B", target: nil, action: nil)
    private let italicButton = NSButton(title: "I", target: nil, action: nil)
    private let underlineButton = NSButton(title: "U", target: nil, action: nil)
    private let fontPopup = NSPopUpButton()
    private let heightField = NSTextField()
    private let colorWell = NSColorWell()
    private let byLayer = NSButton(checkboxWithTitle: "ByLayer", target: nil, action: nil)
    private var finished = false

    /// Opens the editor on a text entity of the canvas. Returns false for non-text objects.
    @discardableResult
    static func begin(canvas: PlanCanvasView, model: AppModel, id: EntityID) -> Bool {
        guard let e = model.doc.entity(id), case .text(let t) = e.geometry, let st = TextEditState(entity: e) else { return false }
        current?.commit()
        let styleFont = TextStyleFonts.style(t.style, doc: model.doc)?.font ?? "Helvetica"
        let ed = InPlaceTextEditor(model: model, id: id, state: st, singleLine: t.width <= 0 && !t.content.contains("\n") && !t.content.contains("\\P"),
                                   screenPerUnit: canvas.scale, styleFont: styleFont)
        canvas.addSubview(ed)
        ed.layout(at: canvas.toView(t.position), text: t, in: canvas.bounds)
        canvas.window?.makeFirstResponder(ed.textView)
        ed.textView.selectAll(nil)
        current = ed
        return true
    }

    init(model: AppModel, id: EntityID, state: TextEditState, singleLine: Bool, screenPerUnit: CGFloat, styleFont: String) {
        self.model = model; self.id = id; self.original = state; self.state = state
        self.singleLine = singleLine; self.screenPerUnit = screenPerUnit; self.styleFont = styleFont
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.nsPanel.withAlphaComponent(0.96).cgColor
        layer?.borderColor = Theme.nsAccent.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        setAccessibilityLabel("In-place text editor")
        build()
        refreshControls()
        applyFormatting()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    static let toolbarHeight: CGFloat = 30

    /// Point size showing the text at its drawn height (cap height = height × zoom), within a legible range.
    var pointSize: CGFloat {
        let family = fontFamily
        let cap = max(0.5, (NSFont(name: family, size: 100)?.capHeight ?? 72) / 100)
        return min(96, max(9, CGFloat(state.height) * screenPerUnit / cap))
    }
    private var fontFamily: String { RenderScene.fontName(state.format.font ?? styleFont) }

    private func layout(at p: CGPoint, text t: TextGeom, in bounds: CGRect) {
        let fs = pointSize
        let lineH = fs * 1.3
        let lines = max(1, state.content.components(separatedBy: "\n").count)
        let natural = (state.content as NSString).size(withAttributes: [.font: NSFont(name: fontFamily, size: fs) ?? .systemFont(ofSize: fs)]).width
        var w = t.width > 0 ? CGFloat(t.width) * screenPerUnit : natural + 40
        w = min(max(w, 360), max(360, bounds.width - 20))
        let h = CGFloat(lines) * lineH + 14 + Self.toolbarHeight
        var x = p.x - 6
        switch t.halign { case .center: x -= w / 2; case .right: x -= w; default: break }
        // Baseline of the first line on the text's insertion point.
        var y = p.y - (h - Self.toolbarHeight) + lineH * 0.75 + 7
        x = min(max(bounds.minX + 4, x), bounds.maxX - w - 4)
        y = min(max(bounds.minY + 4, y), bounds.maxY - h - 4)
        frame = CGRect(x: x, y: y, width: w, height: h)
        scroll.frame = CGRect(x: 2, y: 2, width: w - 4, height: h - Self.toolbarHeight - 4)
    }

    // MARK: Controls

    private func build() {
        scroll.documentView = textView
        scroll.hasVerticalScroller = !singleLine
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.string = state.content
        textView.setAccessibilityLabel("Text")
        addSubview(scroll)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 4
        for (b, tip, font) in [(boldButton, "Bold", NSFont.boldSystemFont(ofSize: 12)),
                               (italicButton, "Italic", NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)),
                               (underlineButton, "Underline", NSFont.systemFont(ofSize: 12))] {
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .texturedRounded
            b.font = font
            b.toolTip = tip
            b.setAccessibilityLabel(tip)
            b.target = self; b.action = #selector(toggleFormat(_:))
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            bar.addArrangedSubview(b)
        }
        fontPopup.addItem(withTitle: "Style font (\(RenderScene.fontName(styleFont)))")
        fontPopup.menu?.addItem(.separator())
        for f in NSFontManager.shared.availableFontFamilies { fontPopup.addItem(withTitle: f) }
        fontPopup.target = self; fontPopup.action = #selector(fontChanged)
        fontPopup.controlSize = .small
        fontPopup.toolTip = "Font"
        fontPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        bar.addArrangedSubview(fontPopup)
        heightField.controlSize = .small
        heightField.toolTip = "Text height (drawing units)"
        heightField.setAccessibilityLabel("Text height")
        heightField.target = self; heightField.action = #selector(heightChanged)
        heightField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        bar.addArrangedSubview(heightField)
        colorWell.target = self; colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "Text colour"
        colorWell.widthAnchor.constraint(equalToConstant: 34).isActive = true
        bar.addArrangedSubview(colorWell)
        byLayer.target = self; byLayer.action = #selector(byLayerChanged)
        byLayer.controlSize = .small
        bar.addArrangedSubview(byLayer)
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed))
        ok.controlSize = .small; ok.toolTip = "Apply (⌘↩)"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.controlSize = .small; cancel.toolTip = "Discard (Esc)"
        bar.addArrangedSubview(ok); bar.addArrangedSubview(cancel)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight - 6),
        ])
    }

    private func refreshControls() {
        boldButton.state = state.format.bold ? .on : .off
        italicButton.state = state.format.italic ? .on : .off
        underlineButton.state = state.format.underline ? .on : .off
        if let f = state.format.font, fontPopup.itemTitles.contains(f) { fontPopup.selectItem(withTitle: f) } else { fontPopup.selectItem(at: 0) }
        heightField.stringValue = fmt(state.height, 4)
        byLayer.state = state.color == .byLayer ? .on : .off
        if case .rgb(let r, let g, let b) = state.color { colorWell.color = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }
        else if case .aci(let i) = state.color { let c = aciColor(i); colorWell.color = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
    }

    /// Font of the editor text (family, traits, drawn size).
    var displayFont: NSFont {
        var f = NSFont(name: fontFamily, size: pointSize) ?? .systemFont(ofSize: pointSize)
        let fm = NSFontManager.shared
        if state.format.bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if state.format.italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    private var displayColor: NSColor {
        switch state.color {
        case .rgb(let r, let g, let b): return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        case .aci(let i): let c = aciColor(i); return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        default: return NSColor(Theme.text)
        }
    }

    /// Applies the whole-text formatting to the editor's text and typing attributes (what you see is what is drawn).
    func applyFormatting() {
        var attrs: [NSAttributedString.Key: Any] = [.font: displayFont, .foregroundColor: displayColor]
        if state.format.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let ts = textView.textStorage { ts.setAttributes(attrs, range: NSRange(location: 0, length: ts.length)) }
        textView.typingAttributes = attrs
        textView.insertionPointColor = displayColor
    }

    @objc private func toggleFormat(_ b: NSButton) {
        switch b {
        case boldButton: state.format.bold = b.state == .on
        case italicButton: state.format.italic = b.state == .on
        default: state.format.underline = b.state == .on
        }
        applyFormatting()
        window?.makeFirstResponder(textView)
    }
    @objc private func fontChanged() {
        state.format.font = fontPopup.indexOfSelectedItem <= 0 ? nil : fontPopup.titleOfSelectedItem
        applyFormatting()
    }
    @objc private func heightChanged() {
        if let v = Double(heightField.stringValue.replacingOccurrences(of: ",", with: ".")), v > 0 { state.height = v; applyFormatting() }
        else { heightField.stringValue = fmt(state.height, 4); NSSound.beep() }
    }
    @objc private func colorChanged() {
        let c = RGBA(colorWell.color.usingColorSpace(.sRGB) ?? .white)
        state.color = .rgb(UInt8((c.r * 255).rounded()), UInt8((c.g * 255).rounded()), UInt8((c.b * 255).rounded()))
        byLayer.state = .off
        applyFormatting()
    }
    @objc private func byLayerChanged() {
        state.color = byLayer.state == .on ? .byLayer : original.color == .byLayer ? .rgb(255, 255, 255) : original.color
        applyFormatting()
    }
    @objc private func okPressed() { commit() }
    @objc private func cancelPressed() { cancel() }

    // MARK: Keys

    func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            if singleLine || NSApp.currentEvent?.modifierFlags.contains(.command) == true { commit(); return true }
        }
        return false
    }
    func textDidEndEditing(_ n: Notification) {
        // Clicking elsewhere keeps the edit (as AutoCAD's in-place editor does), unless focus moved to our own controls.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished, let w = self.window else { return }
            if let r = w.firstResponder as? NSView, r.isDescendant(of: self) { return }
            self.commit()
        }
    }
    override func cancelOperation(_ sender: Any?) { cancel() }

    // MARK: Finish

    func commit() {
        guard !finished else { return }
        heightChanged()
        state.content = textView.string
        finished = true
        let st = state, id = id
        if st != original, st.errors.isEmpty, let m = model {
            m.editor.transaction("Edit Text") { d in st.apply(id: id, to: &d) }
        } else if !st.errors.isEmpty { NSSound.beep() }
        close()
    }
    func cancel() { finished = true; close() }
    private func close() {
        let canvas = superview
        removeFromSuperview()
        if Self.current === self { Self.current = nil }
        (canvas as? PlanCanvasView)?.focus()
        (canvas as? PlanCanvasView)?.invalidateCache()
    }

    /// Test hook: set the editor text as if typed.
    func setText(_ s: String) { textView.string = s; applyFormatting() }
    /// Test hook: toggles a format button as a click would.
    func click(_ which: String) {
        let b = which == "bold" ? boldButton : which == "italic" ? italicButton : underlineButton
        b.state = b.state == .on ? .off : .on
        toggleFormat(b)
    }
}
