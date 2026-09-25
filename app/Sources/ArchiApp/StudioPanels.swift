// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - Shared panel window helper

/// Floating utility panels keyed by name; `present: false` builds the content off screen (self-tests).
@MainActor
enum StudioWindows {
    private static var windows: [String: NSPanel] = [:]
    static func show<V: View>(_ key: String, title: String, size: NSSize, present: Bool = true, @ViewBuilder content: () -> V) {
        let hc = NSHostingController(rootView: AnyView(content().preferredColorScheme(Theme.colorScheme)))
        if let w = windows[key] { w.contentViewController = hc } else {
            let w = ReviewUI.panel(title, key: "ArchiStudio.\(key)", size: size, content: EmptyView())
            w.contentViewController = hc
            windows[key] = w
        }
        if present { windows[key]?.makeKeyAndOrderFront(nil) }
        else { hc.view.frame = NSRect(origin: .zero, size: size); hc.view.layoutSubtreeIfNeeded() }
    }
    static func isOpen(_ key: String) -> Bool { windows[key]?.contentViewController != nil }
    static func close(_ key: String) { windows[key]?.orderOut(nil); windows[key]?.contentViewController = nil }
}

// MARK: - Selection info (APP-037)

enum SelectionInfo {
    struct Row: Hashable { var type: String; var count: Int; var ids: [EntityID] }
    struct Summary { var rows: [Row]; var layers: [String: Int]; var length: Double; var area: Double; var total: Int }
    static func summarize(_ doc: ArchiDocument, _ ids: Set<EntityID>) -> Summary {
        var byType: [String: [EntityID]] = [:], layers: [String: Int] = [:]
        var length = 0.0, area = 0.0
        for e in doc.entities where ids.contains(e.id) {
            byType[e.typeName, default: []].append(e.id); layers[e.layer, default: 0] += 1
            length += GeometryOps.length(e.geometry, doc: doc)
            area += GeometryOps.area(e.geometry, doc: doc) ?? 0
        }
        for el in doc.elements where ids.contains(el.id) {
            byType[el.typeName, default: []].append(el.id); layers[el.layer, default: 0] += 1
        }
        let rows = byType.map { Row(type: $0.key, count: $0.value.count, ids: $0.value.sorted()) }.sorted { ($0.count, $1.type) > ($1.count, $0.type) }
        return Summary(rows: rows, layers: layers, length: length, area: area, total: rows.reduce(0) { $0 + $1.count })
    }
}

struct SelectionInfoPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let s = SelectionInfo.summarize(model.doc, model.editor.selection)
        VStack(alignment: .leading, spacing: 6) {
            Text(s.total == 0 ? "Nothing selected" : "\(s.total) object(s) selected").font(Theme.fontBold)
            ForEach(s.rows, id: \.self) { r in
                HStack {
                    Text(r.type).frame(width: 120, alignment: .leading)
                    Text("\(r.count)").font(Theme.mono).frame(width: 40, alignment: .trailing)
                    Spacer()
                    Button("Only") { model.editor.selection = Set(r.ids) }.buttonStyle(FlatButtonStyle(compact: true)).help("Keep only the \(r.type) objects selected")
                    Button("Remove") { model.editor.selection.subtract(r.ids) }.buttonStyle(FlatButtonStyle(compact: true)).help("Remove the \(r.type) objects from the selection")
                }
            }
            if s.total > 0 {
                HSeparator()
                Text("Layers: " + s.layers.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                if s.length > 0 { Text("Total length \(fmt(s.length, 2))").font(Theme.mono) }
                if s.area > 0 { Text("Total area \(fmt(s.area, 2))").font(Theme.mono) }
                HStack {
                    Button("Zoom to Selection") {
                        var b = BBox2.empty
                        for id in model.editor.selection { if let e = model.doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: model.doc)) } }
                        for el in model.doc.elements where model.editor.selection.contains(el.id) { for p in GripEditor.grips(el, doc: model.doc) { b.add(p) } }
                        ReviewUI.zoom(model: model, to: b)
                    }.buttonStyle(FlatButtonStyle(compact: true))
                    Button("Clear") { model.editor.selection = [] }.buttonStyle(FlatButtonStyle(compact: true))
                }
            }
            Spacer()
        }
        .font(Theme.font).foregroundStyle(Theme.text).padding(10).frame(minWidth: 220, minHeight: 200, alignment: .topLeading).background(Theme.panel)
    }
}

// MARK: - Notifications centre (APP-038)

/// Non-modal list of model warnings (model check, family errors, missing references) with zoom-to.
enum ModelNotifications {
    struct Item: Hashable, Identifiable {
        var id: String { code + ":" + ids.map(String.init).joined(separator: ",") + ":" + message }
        var severity: IssueSeverity; var code: String; var message: String; var ids: [EntityID]; var bounds: BBox2; var level: Int?
    }
    static func items(_ doc: ArchiDocument) -> [Item] {
        var out = ModelChecker.check(doc).map { i in
            Item(severity: i.severity, code: i.code, message: i.message, ids: i.ids, bounds: i.bounds, level: i.ids.lazy.compactMap { doc.element($0)?.level }.first)
        }
        for el in doc.elements {
            if let e = el.props["familyErrors"] {
                var b = BBox2.empty
                for p in GripEditor.grips(el, doc: doc) { b.add(p) }
                out.append(Item(severity: .warning, code: "FAMILY", message: "\(el.name.isEmpty ? el.typeName : el.name): \(e)", ids: [el.id], bounds: b, level: el.level))
            }
        }
        for e in doc.entities {
            if case .insert(let g) = e.geometry, doc.blocks[g.block] == nil {
                out.append(Item(severity: .error, code: "BLOCK-MISSING", message: "Block \(g.block) is not defined", ids: [e.id], bounds: GeometryOps.bounds(e.geometry, doc: doc), level: nil))
            }
            if doc.layer(named: e.layer) == nil {
                out.append(Item(severity: .info, code: "LAYER-MISSING", message: "Layer \(e.layer) is not in the layer table", ids: [e.id], bounds: GeometryOps.bounds(e.geometry, doc: doc), level: nil))
            }
        }
        return out.sorted { ($0.severity, $0.code) < ($1.severity, $1.code) }
    }
}

struct NotificationsPanel: View {
    @ObservedObject var model: AppModel
    @State private var showInfo = false
    @State private var dismissed: Set<String> = []
    var body: some View {
        let all = ModelNotifications.items(model.doc).filter { !dismissed.contains($0.id) && (showInfo || $0.severity != .info) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(all.isEmpty ? "No warnings" : "\(all.count) notification(s)").font(Theme.fontBold)
                Spacer()
                Toggle("Info", isOn: $showInfo).toggleStyle(.checkbox)
                if !dismissed.isEmpty { Button("Restore dismissed") { dismissed = [] }.buttonStyle(FlatButtonStyle(compact: true)) }
            }
            List(all) { it in
                HStack(alignment: .top) {
                    Image(systemName: it.severity == .error ? "xmark.octagon.fill" : it.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(it.severity == .error ? Theme.danger : it.severity == .warning ? Theme.accent : Theme.textDim)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(it.message).lineLimit(2)
                        Text(it.code + (it.ids.isEmpty ? "" : " · " + it.ids.prefix(6).map { "#\($0)" }.joined(separator: " "))).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Button { dismissed.insert(it.id) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Dismiss")
                }
                .contentShape(Rectangle())
                .onTapGesture { NotificationsPanel.zoom(model, it) }
                .help("Click to zoom to the objects and select them")
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .font(Theme.font).foregroundStyle(Theme.text).padding(10).frame(minWidth: 220, minHeight: 240).background(Theme.panel)
    }
    /// Selects the offending objects and zooms to them on their level.
    static func zoom(_ model: AppModel, _ it: ModelNotifications.Item) {
        model.editor.selection = Set(it.ids.filter { model.doc.contains($0) })
        ReviewUI.zoom(model: model, to: it.bounds, level: it.level)
    }
}

// MARK: - Navigator (APP-032)

enum NavigatorMap {
    /// Maps a world point into a map of `size` showing `extent` (uniform scale, centred). Returns (scale, offset).
    static func fit(_ extent: BBox2, in size: CGSize, margin: CGFloat = 8) -> (scale: Double, ox: Double, oy: Double) {
        let w = max(extent.width, 1e-9), h = max(extent.height, 1e-9)
        let s = min((Double(size.width) - 2 * Double(margin)) / w, (Double(size.height) - 2 * Double(margin)) / h)
        return (s, (Double(size.width) - w * s) / 2 - extent.min.x * s, (Double(size.height) - h * s) / 2 - extent.min.y * s)
    }
    /// Drawing extents grown to include the visible view (a default square for an empty drawing).
    static func extent(_ docBox: BBox2, view: BBox2) -> BBox2 {
        var ext = docBox
        if !view.isEmpty { ext.add(view.min); ext.add(view.max) }
        return ext.isEmpty ? BBox2(min: .zero, max: Vec2(10000, 10000)) : ext
    }
    static func toMap(_ p: Vec2, _ f: (scale: Double, ox: Double, oy: Double), height: CGFloat) -> CGPoint {
        CGPoint(x: p.x * f.scale + f.ox, y: Double(height) - (p.y * f.scale + f.oy))
    }
    static func toWorld(_ q: CGPoint, _ f: (scale: Double, ox: Double, oy: Double), height: CGFloat) -> Vec2 {
        Vec2((Double(q.x) - f.ox) / f.scale, (Double(height) - Double(q.y) - f.oy) / f.scale)
    }
}

struct NavigatorPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            GeometryReader { geo in
                let size = geo.size
                let view = model.canvas?.visibleWorldBox ?? .empty
                let f = NavigatorMap.fit(NavigatorMap.extent(GeometryOps.bounds(of: model.doc), view: view), in: size)
                Canvas { ctx, sz in
                    ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(Theme.canvas))
                    var path = Path()
                    for e in model.doc.entities.prefix(20000) {
                        for pl in GeometryOps.tessellate(e.geometry, doc: model.doc) where pl.count > 1 {
                            path.addLines(pl.map { NavigatorMap.toMap($0, f, height: sz.height) })
                        }
                    }
                    for el in model.doc.elements where el.level == model.doc.currentLevel {
                        let g = GripEditor.grips(el, doc: model.doc)
                        if g.count > 1 { path.addLines(g.map { NavigatorMap.toMap($0, f, height: sz.height) }) }
                    }
                    ctx.stroke(path, with: .color(Theme.textDim), lineWidth: 0.6)
                    if !view.isEmpty {
                        let a = NavigatorMap.toMap(view.min, f, height: sz.height), b = NavigatorMap.toMap(view.max, f, height: sz.height)
                        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                        ctx.fill(Path(r), with: .color(Theme.accent.opacity(0.12)))
                        ctx.stroke(Path(r), with: .color(Theme.accent), lineWidth: 1.5)
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    model.canvas?.centre(on: NavigatorMap.toWorld(v.location, f, height: size.height))
                })
                .help("Drag to move the view rectangle")
            }
        }
        .frame(minWidth: 240, minHeight: 180).background(Theme.panel)
    }
}

// MARK: - What's new (APP-060)

enum WhatsNew {
    static let lastSeenKey = "whatsNew.lastSeenVersion"
    static let notes: [(String, [String])] = [
        ("3D", ["Move gizmo with a Z arrow: drag objects up and down (walls, slabs, columns, components, solids) — GIZMO3D, MOVEZ",
                "Isolate one level or explode levels vertically in the 3D view — LEVELVIEW3D", "Field of view / focal length — FOV",
                "Export the 3D view as PNG, JPEG or TIFF, optionally with a transparent background — VIEWIMAGE"]),
        ("Families", ["Family Editor panel: parameters with formulas, forms (box, extrusion, blend, revolve, sweep, swept blend, voids, arrays), types table, reference planes and profiles, live 3D preview and flexing — FAMILYPANEL"]),
        ("Drafting", ["Click a block or component in the tool palette to place it; Space rotates the preview 90°", "Space while dragging a grip rotates the object 90° about the grip"]),
        ("Sheets", ["Export a sheet as PNG, JPEG or TIFF at any resolution — SHEETIMAGE"]),
        ("Panels", ["Selection info — SELECTIONINFO", "Notifications centre with zoom-to — NOTIFICATIONS", "Navigator overview map — NAVIGATOR"]),
        ("Scripting", ["Event hooks: archi.on(\"selectionChanged\" | \"documentChanged\" | \"elementAdded\" | \"elementRemoved\" | \"saved\" | \"commandEnded\", fn)",
                       "Script panels: archi.panel({title, items}) with buttons, numbers and text fields", "Plug-in commands are one undo step"]),
    ]
    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    /// Shown after an update (a different version than last time); a fresh install records the version silently.
    static func shouldShow(current: String, lastSeen: String?) -> Bool { lastSeen != nil && lastSeen != current }
    @MainActor static func checkOnLaunch(model: AppModel) {
        let d = UserDefaults.standard
        let last = d.string(forKey: lastSeenKey)
        d.set(currentVersion, forKey: lastSeenKey)
        if shouldShow(current: currentVersion, lastSeen: last) { StudioWindows.show("whatsnew", title: "What's New", size: NSSize(width: 520, height: 460)) { WhatsNewView() } }
    }
}

struct WhatsNewView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("What's New in Oanarina Archi Tool \(WhatsNew.currentVersion)").font(.title3.bold())
                ForEach(WhatsNew.notes, id: \.0) { sec in
                    Text(sec.0).font(Theme.fontBold).foregroundStyle(Theme.accent)
                    ForEach(sec.1, id: \.self) { Text("• " + $0).fixedSize(horizontal: false, vertical: true) }
                }
                Text("Type HELP or a command name in the command line to learn more. Show this again with WHATSNEW.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.font).foregroundStyle(Theme.text).background(Theme.panel)
    }
}

// MARK: - Sheet raster export (SHT-035)

enum SheetImageExport {
    /// Renders a layout to a bitmap at `dpi` (white paper), the same drawing as the PDF plot.
    @MainActor static func image(doc: ArchiDocument, layoutIndex li: Int, dpi: Double) -> NSImage? {
        guard doc.layouts.indices.contains(li), dpi > 0 else { return nil }
        let layout = doc.layouts[li]
        let perMM = CGFloat(dpi / 25.4)
        let w = Int((CGFloat(layout.paper.width) * perMM).rounded()), h = Int((CGFloat(layout.paper.height) * perMM).rounded())
        guard w > 0, h > 0, w * h <= 400_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        SheetComposer.draw(doc: doc, layoutIndex: li, in: ctx, paperToDevice: CGAffineTransform(scaleX: perMM, y: perMM),
                           devicePerMM: perMM, showViewportBorders: false, setup: PageSetup.load(doc, layoutIndex: li))
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// Renders the model view of a level (the same page as the model PDF plot) at `dpi`.
    @MainActor static func modelImage(doc: ArchiDocument, level: Int?, dpi: Double) -> NSImage? {
        guard dpi > 0 else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("archi-model-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? Plotter.writePDF(doc: doc, to: tmp, layoutIndex: nil, level: level)) != nil,
              let pdf = CGPDFDocument(tmp as CFURL), let page = pdf.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let k = CGFloat(dpi / 72)
        let w = Int((box.width * k).rounded()), h = Int((box.height * k).rounded())
        guard w > 0, h > 0, w * h <= 400_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}

// MARK: - Script-defined panels (SCR-008)

/// A panel described by a script: archi.panel({title: "Stairs", items: [{type: "number", name: "rise", label: "Rise", value: 175},
/// {type: "button", label: "Build", call: "build"}, {type: "button", label: "Line", command: "LINE"}, {type: "text", text: "…"}]}).
/// Buttons call the named global function with the current field values, or run a command.
struct ScriptPanelSpec: Equatable {
    struct Item: Equatable { var type: String; var label: String; var name: String; var value: String; var call: String?; var command: String?; var min: Double?; var max: Double? }
    var title: String
    var items: [Item]
    static func parse(_ o: Any) throws -> ScriptPanelSpec {
        guard let d = o as? [String: Any] else { throw ArchiJSON.fail("archi.panel needs an object {title, items}") }
        let title = d["title"] as? String ?? "Script Panel"
        guard let arr = d["items"] as? [Any], !arr.isEmpty else { throw ArchiJSON.fail("archi.panel needs a non-empty items array") }
        var items: [Item] = []
        for (k, x) in arr.enumerated() {
            guard let i = x as? [String: Any], let t = i["type"] as? String, ["button", "number", "text", "field", "toggle"].contains(t) else {
                throw ArchiJSON.fail("item \(k + 1): type must be button, number, field, toggle or text")
            }
            let name = i["name"] as? String ?? "item\(k + 1)"
            let v: String = (i["value"] as? NSNumber).map { t == "toggle" ? ($0.boolValue ? "1" : "0") : fmt($0.doubleValue, 10) } ?? (i["value"] as? String) ?? (i["text"] as? String) ?? (t == "number" || t == "toggle" ? "0" : "")
            let it = Item(type: t, label: i["label"] as? String ?? name, name: name, value: v, call: i["call"] as? String, command: i["command"] as? String,
                          min: (i["min"] as? NSNumber)?.doubleValue, max: (i["max"] as? NSNumber)?.doubleValue)
            if t == "button" && it.call == nil && it.command == nil { throw ArchiJSON.fail("item \(k + 1): a button needs call or command") }
            items.append(it)
        }
        return ScriptPanelSpec(title: title, items: items)
    }
    /// Field values passed to button functions (numbers as numbers).
    static func values(_ items: [Item], _ state: [String: String]) -> [String: Any] {
        var out: [String: Any] = [:]
        for i in items where i.type != "button" && i.type != "text" {
            let s = state[i.name] ?? i.value
            switch i.type {
            case "number":
                var d = Double(s) ?? 0
                if let lo = i.min { d = max(d, lo) }
                if let hi = i.max { d = min(d, hi) }
                out[i.name] = d
            case "toggle": out[i.name] = s == "1"
            default: out[i.name] = s
            }
        }
        return out
    }
}

@MainActor
final class ScriptPanelState: ObservableObject {
    @Published var spec: ScriptPanelSpec
    @Published var values: [String: String] = [:]
    weak var model: AppModel?
    init(spec: ScriptPanelSpec, model: AppModel) { self.spec = spec; self.model = model }
    func press(_ i: ScriptPanelSpec.Item) {
        guard let m = model else { return }
        if let c = i.command { m.runCommand(c); return }
        if let f = i.call { ScriptEngine.forModel(m).callGlobal(f, argument: ScriptPanelSpec.values(spec.items, values)) }
    }
}

struct ScriptPanelView: View {
    @ObservedObject var st: ScriptPanelState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(st.spec.items.enumerated()), id: \.offset) { _, i in
                switch i.type {
                case "text": Text(i.value.isEmpty ? i.label : i.value).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                case "button": Button(i.label) { st.press(i) }.buttonStyle(FlatButtonStyle(prominent: true, compact: true))
                case "toggle": Toggle(i.label, isOn: Binding(get: { (st.values[i.name] ?? i.value) == "1" }, set: { st.values[i.name] = $0 ? "1" : "0" }))
                default:
                    HStack {
                        Text(i.label).frame(width: 110, alignment: .leading)
                        TextField("", text: Binding(get: { st.values[i.name] ?? i.value }, set: { st.values[i.name] = $0 })).textFieldStyle(.plain).padding(4).darkField()
                    }
                }
            }
            Spacer()
        }
        .font(Theme.font).foregroundStyle(Theme.text).padding(12).frame(minWidth: 280, minHeight: 160, alignment: .topLeading).background(Theme.panel)
    }
}

@MainActor
enum ScriptPanels {
    private(set) static var states: [String: ScriptPanelState] = [:]
    static func show(_ spec: ScriptPanelSpec, model: AppModel, present: Bool = true) -> ScriptPanelState {
        let st = states[spec.title].map { s -> ScriptPanelState in s.spec = spec; s.model = model; return s } ?? ScriptPanelState(spec: spec, model: model)
        states[spec.title] = st
        StudioWindows.show("script:" + spec.title, title: spec.title, size: NSSize(width: 320, height: max(160, CGFloat(spec.items.count) * 34 + 40)), present: present) { ScriptPanelView(st: st) }
        return st
    }
}
