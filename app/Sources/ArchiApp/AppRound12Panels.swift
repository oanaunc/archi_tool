// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import ArchiCore

// Dialogs of round 12: object styles (LAY-033), text styles with width factor and obliquing (ANN-004), image
// adjustment (DRW-086), ambient occlusion (VIS-033) and material fill patterns (ANN-072). Each dialog edits a plain
// form value (testable headless) and applies it to the document as one undo step.

enum Round12Panels {
    private static var panels: [String: NSPanel] = [:]
    @MainActor static func show<V: View>(_ id: String, title: String, size: NSSize, _ view: V) {
        panels[id]?.close()
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = title
        p.isReleasedWhenClosed = false
        p.appearance = Theme.appearance
        p.contentViewController = NSHostingController(rootView: view.preferredColorScheme(Theme.colorScheme))
        p.center()
        p.makeKeyAndOrderFront(nil)
        panels[id] = p
    }
    @MainActor static func isOpen(_ id: String) -> Bool { panels[id]?.isVisible == true }
    @MainActor static func close(_ id: String) { panels[id]?.close(); panels[id] = nil }
}

private func num(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    return t.isEmpty ? nil : Double(t)
}
private func str(_ v: Double?) -> String { v.map { fmt($0, 3) } ?? "" }

// MARK: - Object styles (LAY-033)

struct ObjectStylesForm: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { category }
        var category: String
        var cut = "", projection = ""
        var color: RGBA?
        var fill: RGBA?
        var pattern = ""
    }
    var rows: [Row]

    init(doc: ArchiDocument) {
        let all = ObjectStyles.all(doc)
        let cats = ObjectStyles.categories + all.keys.sorted().filter { !ObjectStyles.categories.contains($0) }
        rows = cats.map { c in
            let s = all[c] ?? ObjectStyle()
            return Row(category: c, cut: str(s.cutLineweight), projection: str(s.projectionLineweight), color: s.color, fill: s.cutFill, pattern: s.cutPattern ?? "")
        }
    }

    /// Invalid entries (non-numeric or negative lineweights).
    var errors: [String] {
        rows.flatMap { r -> [String] in
            var e: [String] = []
            if !r.cut.trimmingCharacters(in: .whitespaces).isEmpty, (num(r.cut) ?? -1) <= 0 { e.append("\(r.category): cut lineweight") }
            if !r.projection.trimmingCharacters(in: .whitespaces).isEmpty, (num(r.projection) ?? -1) <= 0 { e.append("\(r.category): projection lineweight") }
            return e
        }
    }

    var styles: [String: ObjectStyle] {
        var out: [String: ObjectStyle] = [:]
        for r in rows {
            let s = ObjectStyle(projectionLineweight: num(r.projection).flatMap { $0 > 0 ? $0 : nil }, cutLineweight: num(r.cut).flatMap { $0 > 0 ? $0 : nil },
                                color: r.color, cutFill: r.fill, cutPattern: r.pattern.isEmpty ? nil : r.pattern)
            if !s.isEmpty { out[r.category] = s }
        }
        return out
    }

    func apply(to doc: inout ArchiDocument) { ObjectStyles.setAll(styles, doc: &doc) }
}

struct ObjectStylesPanel: View {
    let model: AppModel
    @State var form: ObjectStylesForm
    @State private var message = ""
    static let lineweights = ["", "0.13", "0.18", "0.25", "0.35", "0.5", "0.7", "1", "1.4", "2"]

    init(model: AppModel) { self.model = model; _form = State(initialValue: ObjectStylesForm(doc: model.doc)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category-wide graphics for every plan and section: projection and cut line weights (mm), line colour, cut fill and cut pattern. Empty = default.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Category").frame(width: 96, alignment: .leading)
                Text("Projection").frame(width: 78, alignment: .leading)
                Text("Cut").frame(width: 78, alignment: .leading)
                Text("Line colour").frame(width: 96, alignment: .leading)
                Text("Cut fill").frame(width: 96, alignment: .leading)
                Text("Cut pattern")
            }.font(Theme.fontSmall.bold())
            ScrollView {
                VStack(spacing: 4) {
                    ForEach($form.rows) { $r in
                        HStack {
                            Text(r.category.capitalized).frame(width: 96, alignment: .leading)
                            weightField($r.projection)
                            weightField($r.cut)
                            optionalColor($r.color)
                            optionalColor($r.fill)
                            Picker("", selection: $r.pattern) {
                                Text("Default").tag("")
                                ForEach(HatchPatterns.allNames, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(width: 120)
                        }
                        .accessibilityElement(children: .contain).accessibilityLabel("\(r.category) object style")
                    }
                }
            }
            HStack {
                Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Reset All") { form = ObjectStylesForm(doc: ArchiDocument()) }
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(minWidth: 640, minHeight: 420).background(Theme.panel)
    }

    private func weightField(_ b: Binding<String>) -> some View {
        HStack(spacing: 2) {
            TextField("", text: b).frame(width: 46)
            Menu("") { ForEach(Self.lineweights, id: \.self) { w in Button(w.isEmpty ? "Default" : w) { b.wrappedValue = w } } }
                .menuStyle(.borderlessButton).frame(width: 22)
        }.frame(width: 78, alignment: .leading)
    }

    private func optionalColor(_ b: Binding<RGBA?>) -> some View {
        HStack(spacing: 4) {
            Toggle("", isOn: Binding(get: { b.wrappedValue != nil }, set: { b.wrappedValue = $0 ? (b.wrappedValue ?? RGBA(0.5, 0.5, 0.5)) : nil })).labelsHidden()
            ColorPicker("", selection: Binding(get: { (b.wrappedValue ?? RGBA(0.5, 0.5, 0.5)).color },
                                               set: { b.wrappedValue = RGBA(NSColor($0).usingColorSpace(.sRGB) ?? .gray) }), supportsOpacity: false)
                .labelsHidden().disabled(b.wrappedValue == nil)
        }.frame(width: 96, alignment: .leading)
    }

    private func apply() {
        guard form.errors.isEmpty else { message = "Check: " + form.errors.joined(separator: ", "); return }
        let f = form
        model.editor.transaction("Object Styles") { f.apply(to: &$0) }
        message = "\(f.styles.count) categor\(f.styles.count == 1 ? "y" : "ies") styled."
    }
}

// MARK: - Text styles (ANN-004)

struct TextStyleForm: Equatable {
    var name: String
    var font: String
    var height: String
    var widthFactor: String
    /// Obliquing angle in degrees (stored in radians).
    var obliqueDegrees: String

    init(_ s: TextStyle) {
        name = s.name; font = s.font; height = fmt(s.height, 4)
        widthFactor = fmt(TextStyleFonts.widthFactor(s), 3)
        obliqueDegrees = fmt(TextStyleFonts.obliqueRadians(s) * 180 / .pi, 2)
    }

    var errors: [String] {
        var e: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { e.append("name") }
        if (num(height) ?? -1) < 0 { e.append("height ≥ 0") }
        if !((num(widthFactor) ?? 0) >= 0.01 && (num(widthFactor) ?? 0) <= 100) { e.append("width factor 0.01–100") }
        if abs(num(obliqueDegrees) ?? 999) > 85 { e.append("oblique −85…85°") }
        return e
    }

    var style: TextStyle? {
        guard errors.isEmpty else { return nil }
        return TextStyle(name: name.trimmingCharacters(in: .whitespaces), font: font, height: num(height) ?? 0,
                         widthFactor: num(widthFactor) ?? 1, oblique: (num(obliqueDegrees) ?? 0) * .pi / 180)
    }

    /// Replaces the style `original` (or adds it); renames text that used the old name.
    func apply(original: String?, to doc: inout ArchiDocument) -> Bool {
        guard let s = style else { return false }
        if let o = original, let i = doc.textStyles.firstIndex(where: { $0.name == o }) {
            if doc.textStyles.contains(where: { $0.name.caseInsensitiveCompare(s.name) == .orderedSame && $0.name != o }) { return false }
            doc.textStyles[i] = s
            if o != s.name {
                for k in doc.entities.indices { if case .text(var t) = doc.entities[k].geometry, t.style == o { t.style = s.name; doc.entities[k].geometry = .text(t) } }
            }
        } else {
            guard !doc.textStyles.contains(where: { $0.name.caseInsensitiveCompare(s.name) == .orderedSame }) else { return false }
            doc.textStyles.append(s)
        }
        return true
    }
}

struct TextStylesPanel: View {
    let model: AppModel
    @State private var selected: String
    @State private var form: TextStyleForm
    @State private var message = ""
    @State private var creating = false

    init(model: AppModel) {
        self.model = model
        let s = model.doc.textStyles.first ?? TextStyle(name: "Standard")
        _selected = State(initialValue: s.name)
        _form = State(initialValue: TextStyleForm(s))
    }

    private var fonts: [String] { ["Helvetica", "Helvetica Neue", "Arial", "Arial Narrow", "Avenir Next", "Futura", "Gill Sans", "Menlo", "Times New Roman", "Georgia", TextStyleFonts.strokeFontName, "romans.shx", "simplex.shx", "isocp.shx"] }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading) {
                List(selection: Binding(get: { selected }, set: { if let v = $0 { pick(v) } })) {
                    ForEach(model.doc.textStyles.map(\.name), id: \.self) { Text($0).tag($0) }
                }.frame(width: 150)
                HStack {
                    Button("New") { creating = true; form = TextStyleForm(TextStyle(name: uniqueName())); message = "New style: set it up and Apply." }
                    Button("Current") { model.editor.transaction("Current text style") { $0.setVariable("TEXTSTYLE", selected) }; message = "\(selected) is current." }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Form {
                    TextField("Name", text: $form.name)
                    Picker("Font", selection: $form.font) {
                        ForEach(Array(Set(fonts + [form.font])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Height (0 = set on placement)", text: $form.height)
                    TextField("Width factor", text: $form.widthFactor)
                    TextField("Oblique angle (°)", text: $form.obliqueDegrees)
                }
                Text("Preview").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                preview.frame(maxWidth: .infinity, minHeight: 70).background(Theme.field)
                HStack {
                    Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    Spacer()
                    Button("Apply") { apply() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(12).frame(minWidth: 560, minHeight: 360).background(Theme.panel)
    }

    private var preview: some View {
        let wf = CGFloat(num(form.widthFactor) ?? 1), ob = CGFloat((num(form.obliqueDegrees) ?? 0) * .pi / 180)
        return Text("AaBb 123 Plan")
            .font(.custom(TextStyleFonts.isStrokeFont(form.font) ? "Helvetica" : form.font, size: 28))
            .foregroundStyle(Theme.text)
            .transformEffect(CGAffineTransform(a: max(0.01, min(wf, 10)), b: 0, c: -tan(max(-1.48, min(ob, 1.48))), d: 1, tx: 0, ty: 0))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).clipped()
    }

    private func uniqueName() -> String {
        var i = 1
        while model.doc.textStyles.contains(where: { $0.name == "Style \(i)" }) { i += 1 }
        return "Style \(i)"
    }
    private func pick(_ name: String) {
        selected = name; creating = false; message = ""
        if let s = model.doc.textStyles.first(where: { $0.name == name }) { form = TextStyleForm(s) }
    }
    private func apply() {
        guard form.errors.isEmpty else { message = "Check: " + form.errors.joined(separator: ", "); return }
        let f = form, orig: String? = creating ? nil : selected
        var ok = false
        model.editor.transaction("Text Style") { d in ok = f.apply(original: orig, to: &d) }
        if ok { selected = f.name.trimmingCharacters(in: .whitespaces); creating = false; message = "Saved \(selected)." } else { message = "A style with that name exists." }
    }
}

// MARK: - Image adjustment (DRW-086)

struct ImageAdjustPanel: View {
    let model: AppModel
    let ids: [EntityID]
    @State private var brightness: Double
    @State private var contrast: Double
    @State private var fade: Double
    @State private var thumb: CGImage?
    @State private var message = ""

    init(model: AppModel, ids: [EntityID]) {
        self.model = model; self.ids = ids
        let a = ids.first.flatMap { model.doc.entity($0) }.map(ImageDisplay.adjustment) ?? ImageDisplay.Adjustment()
        _brightness = State(initialValue: a.brightness); _contrast = State(initialValue: a.contrast); _fade = State(initialValue: a.fade)
        if let id = ids.first, case .image(let im)? = model.doc.entity(id)?.geometry { _thumb = State(initialValue: RenderScene.cgImage(im.path)) }
    }

    private var adjustment: ImageDisplay.Adjustment { ImageDisplay.Adjustment(brightness: brightness, contrast: contrast, fade: fade) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(ids.count) image\(ids.count == 1 ? "" : "s") — the same result on screen, in PDF plots and after reopening.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            if let t = thumb, let a = AppRenderInfo.adjust(t, adjustment, background: RGBA(1, 1, 1)) ?? Optional(t) {
                Image(decorative: a, scale: 1).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 180)
            }
            slider("Brightness", $brightness)
            slider("Contrast", $contrast)
            slider("Fade", $fade)
            HStack {
                Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Reset") { brightness = 50; contrast = 50; fade = 0 }
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(minWidth: 380, minHeight: 300).background(Theme.panel)
    }

    private func slider(_ label: String, _ v: Binding<Double>) -> some View {
        HStack { Text(label).frame(width: 80, alignment: .leading); Slider(value: v, in: 0...100); Text("\(Int(v.wrappedValue.rounded()))").frame(width: 32) }
    }

    private func apply() {
        let a = adjustment, ids = ids
        var n = 0
        model.editor.transaction("Image Adjust") { d in n = ImageAdjustPanel.apply(a, ids: ids, to: &d) }
        message = "\(n) image\(n == 1 ? "" : "s") adjusted."
    }

    static func apply(_ a: ImageDisplay.Adjustment, ids: [EntityID], to d: inout ArchiDocument) -> Int {
        var n = 0
        for id in ids {
            guard let i = d.entityIndex(id), case .image = d.entities[i].geometry else { continue }
            ImageDisplay.setAdjustment(a, on: &d.entities[i]); n += 1
        }
        return n
    }
}

// MARK: - Ambient occlusion (VIS-033)

struct AOForm: Equatable {
    var intensity: Double
    var radius: Double
    var samples: Int
    init(doc: ArchiDocument) {
        let s = AmbientOcclusion.settings(doc)
        intensity = s?.intensity ?? 0
        radius = s?.radius ?? 1000 / max(doc.units.mm, 1e-9)
        samples = s?.samples ?? 24
    }
    func apply(to d: inout ArchiDocument) {
        if intensity < 1e-9 { d.variables["AOINTENSITY"] = nil } else { d.setVariable("AOINTENSITY", fmt(min(intensity, 2), 4)) }
        d.setVariable("AORADIUS", fmt(max(radius, 1e-6), 6))
        d.setVariable("AOSAMPLES", "\(min(max(samples, 4), 256))")
    }
    /// SceneKit screen-space occlusion for the viewport: intensity and radius in scene metres (the scene is scaled 1:1000).
    static func viewport(_ doc: ArchiDocument) -> (intensity: CGFloat, radius: CGFloat)? {
        guard let s = AmbientOcclusion.settings(doc) else { return nil }
        return (CGFloat(0.9 * s.intensity), CGFloat(max(0.02, s.radius * 0.001)))
    }
}

struct AOPanel: View {
    let model: AppModel
    @State var form: AOForm
    @State private var message = ""
    init(model: AppModel) { self.model = model; _form = State(initialValue: AOForm(doc: model.doc)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Darkens corners, reveals and overhangs in the 3D viewport, renders, shaded elevations, sections and their PDF/SVG exports.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Intensity").frame(width: 80, alignment: .leading); Slider(value: $form.intensity, in: 0...2); Text(fmt(form.intensity, 2)).frame(width: 36) }
            HStack { Text("Radius").frame(width: 80, alignment: .leading); TextField("", value: $form.radius, format: .number).frame(width: 90); Text(model.doc.units.rawValue) }
            Stepper("Rays per point: \(form.samples)", value: $form.samples, in: 4...256, step: 4)
            HStack {
                Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Off") { form.intensity = 0; apply() }
                Button("Apply") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(minWidth: 380, minHeight: 200).background(Theme.panel)
    }
    private func apply() {
        let f = form
        model.editor.transaction("Ambient Occlusion") { f.apply(to: &$0) }
        message = f.intensity < 1e-9 ? "Ambient occlusion off." : "Ambient occlusion \(fmt(f.intensity, 2))."
    }
}

// MARK: - Material fill patterns (ANN-072)

struct MaterialPatternForm: Equatable {
    struct Row: Equatable, Identifiable { var id: String { name }; var name: String; var cut: String; var surface: String }
    var rows: [Row]
    init(doc: ArchiDocument) {
        rows = doc.materials.map { m in
            Row(name: m.name, cut: MaterialPatterns.pattern(m.name, kind: .cut, doc: doc) ?? "", surface: MaterialPatterns.pattern(m.name, kind: .surface, doc: doc) ?? "")
        }
    }
    /// Writes changed patterns and refreshes the bound hatches; returns the number of changed patterns.
    func apply(to d: inout ArchiDocument) -> Int {
        var n = 0
        let before = MaterialPatternForm(doc: d)
        for r in rows {
            guard let old = before.rows.first(where: { $0.name == r.name }) else { continue }
            if old.cut != r.cut, MaterialPatterns.setPattern(r.name, kind: .cut, pattern: r.cut.isEmpty ? nil : r.cut, doc: &d) { n += 1 }
            if old.surface != r.surface, MaterialPatterns.setPattern(r.name, kind: .surface, pattern: r.surface.isEmpty ? nil : r.surface, doc: &d) { n += 1 }
        }
        if n > 0 { _ = MaterialPatterns.updateAll(&d); _ = FloorPatterns.updateAll(&d) }
        return n
    }
}

struct MaterialPatternsPanel: View {
    let model: AppModel
    @State var form: MaterialPatternForm
    @State private var message = ""
    init(model: AppModel) { self.model = model; _form = State(initialValue: MaterialPatternForm(doc: model.doc)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cut patterns fill materials cut in plan and section; surface patterns fill floors and faces seen in projection. Hatches bound to a material follow.")
                .font(Theme.fontSmall).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Material").frame(width: 160, alignment: .leading); Text("Cut pattern").frame(width: 150, alignment: .leading); Text("Surface pattern") }.font(Theme.fontSmall.bold())
            ScrollView {
                VStack(spacing: 4) {
                    ForEach($form.rows) { $r in
                        HStack {
                            Text(r.name).frame(width: 160, alignment: .leading).lineLimit(1)
                            picker($r.cut).frame(width: 150)
                            picker($r.surface).frame(width: 150)
                        }
                    }
                }
            }
            HStack {
                Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Apply") {
                    let f = form; var n = 0
                    model.editor.transaction("Material Patterns") { n = f.apply(to: &$0) }
                    message = "\(n) pattern\(n == 1 ? "" : "s") changed."
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12).frame(minWidth: 520, minHeight: 360).background(Theme.panel)
    }
    private func picker(_ b: Binding<String>) -> some View {
        Picker("", selection: b) {
            Text("None").tag("")
            ForEach(Array(Set(HatchPatterns.allNames + [b.wrappedValue].filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
        }.labelsHidden()
    }
}
