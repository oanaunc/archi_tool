// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import ArchiCore

// MARK: - Properties palette logic (APP-024, APP-025)

@MainActor
enum PropertiesPalette {
    struct Row: Identifiable, Equatable { var id: String { name }; var name: String; var value: String; var readOnly: Bool }

    /// Properties common to all selected objects; differing values show *VARIES*.
    static func rows(_ ids: [EntityID], doc: ArchiDocument, limit: Int = 300) -> [Row] {
        var result: [Row] = []
        var first = true
        for id in ids.prefix(limit) {
            let ps = PropertyAccess.properties(of: id, in: doc)
            if first { result = ps.map { Row(name: $0.name, value: $0.value, readOnly: $0.readOnly) }; first = false; continue }
            let names = Set(ps.map(\.name))
            result.removeAll { !names.contains($0.name) }
            for p in ps {
                if let k = result.firstIndex(where: { $0.name == p.name }) {
                    if result[k].value != p.value { result[k].value = "*VARIES*" }
                    if p.readOnly { result[k].readOnly = true }
                }
            }
        }
        if ids.count > 1 { result.removeAll { $0.name == "id" } }
        return result
    }

    /// Sets one property on every object as a single undo step. Returns the number of objects that refused the value.
    @discardableResult
    static func apply(_ ed: Editor, _ name: String, _ value: String, ids: [EntityID]) -> Int {
        var failed = 0
        ed.transaction("Properties") { d in
            for id in ids where !PropertyAccess.set(name, value, of: id, in: &d) { failed += 1 }
        }
        return failed
    }

    /// Key properties shown by Quick Properties: general ones first, then up to 6 type-specific ones.
    static func quickRows(_ ids: [EntityID], doc: ArchiDocument) -> [Row] {
        let all = rows(ids, doc: doc, limit: 100)
        let general = ["layer", "color", "linetype", "lineweight", "name", "level", "material"]
        let g = all.filter { general.contains($0.name.lowercased()) }
        let rest = all.filter { !general.contains($0.name.lowercased()) && $0.name != "id" && !$0.readOnly }.prefix(6)
        return g + rest
    }
}

/// Compact property editor of the selection (QP): shown over the canvas while objects are selected, dockable in the
/// panel column, floatable in its own window (Quick Props panel tab).
struct QuickPropertiesView: View {
    @ObservedObject var model: AppModel
    var compact = false
    var body: some View {
        let ids = model.selectedIDs
        let rows = PropertiesPalette.quickRows(ids, doc: model.doc)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ids.isEmpty ? "No selection" : "\(ids.count) selected").font(Theme.fontBold).foregroundStyle(Theme.text)
                Spacer()
                if compact {
                    IconButton(symbol: "sidebar.right", help: "Dock in the panels (Quick Props tab)") { model.showQuickProperties = false; model.showPanels = true; model.panelTab = .quick }
                    IconButton(symbol: "macwindow.on.rectangle", help: "Float in a window") { model.showQuickProperties = false; FloatingPanels.float(.quick, model: model) }
                    IconButton(symbol: "xmark", help: "Hide Quick Properties (QP)") { model.showQuickProperties = false }
                }
            }
            ForEach(rows) { r in
                HStack(spacing: 6) {
                    Text(r.name.capitalized).font(Theme.fontSmall).foregroundStyle(Theme.textDim).frame(width: 78, alignment: .leading).lineLimit(1)
                    if r.readOnly { Text(r.value).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1) }
                    else { PropertyField(value: r.value) { v in let f = PropertiesPalette.apply(model.editor, r.name, v, ids: ids); if f > 0 { model.editor.print("Invalid value for \(r.name).") } } }
                }
            }
            if !compact && ids.isEmpty { Text("Select objects to edit their key properties.").font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .padding(8)
        .frame(width: compact ? 260 : nil, alignment: .topLeading)
    }
}

// MARK: - Model / layout tabs and file tabs (APP-013, APP-012)

struct LayoutTabsBar: View {
    @ObservedObject var model: AppModel
    @State private var renaming: Int?
    @State private var newName = ""
    var body: some View {
        let titles = LayoutTabs.titles(model.doc)
        let cur = LayoutTabs.current(model)
        HStack(spacing: 1) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                Button { LayoutTabs.select(model, i) } label: {
                    HStack(spacing: 4) {
                        if i == 0 { Image(systemName: "square.grid.3x3").font(.system(size: 9)) }
                        else if SheetTools.isPlaceholder(model.doc.layouts[i - 1]) { Image(systemName: "doc.badge.ellipsis").font(.system(size: 9)) }
                        Text(t).font(.system(size: 10.5, weight: cur == i ? .semibold : .regular)).lineLimit(1)
                    }
                    .foregroundStyle(cur == i ? Theme.text : Theme.textDim)
                    .padding(.horizontal, 10).frame(height: 20)
                    .background(cur == i ? Theme.panel : Color.clear)
                    .overlay(alignment: .top) { if cur == i { Rectangle().fill(Theme.accent).frame(height: 2) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(i == 0 ? "Model space" : "Sheet \(t) — right-click for options")
                .contextMenu {
                    if i > 0 {
                        Button("Rename…") { rename(i - 1) }
                        Button("Duplicate") { let k = i - 1; model.editor.transaction("Duplicate Layout") { _ = SheetSet.duplicate(&$0, k) } }
                        Button(SheetTools.isPlaceholder(model.doc.layouts[i - 1]) ? "Make Real Sheet" : "Make Placeholder") {
                            let k = i - 1, on = !SheetTools.isPlaceholder(model.doc.layouts[k])
                            model.editor.transaction("Placeholder Sheet") { SheetTools.setPlaceholder(&$0, k, on) }
                        }
                        Button("Move Left") { let k = i - 1; if k > 0 { model.editor.transaction("Move Layout") { SheetSet.move(&$0, from: k, to: k - 1) }; LayoutTabs.select(model, i - 1) } }.disabled(i == 1)
                        Button("Move Right") { let k = i - 1; if k < model.doc.layouts.count - 1 { model.editor.transaction("Move Layout") { SheetSet.move(&$0, from: k, to: k + 1) }; LayoutTabs.select(model, i + 1) } }.disabled(i == titles.count - 1)
                        Divider()
                        Button("Page Setup…") { model.sheet = .pageSetup(i - 1) }
                        Button("Delete", role: .destructive) {
                            let k = i - 1
                            model.editor.transaction("Delete Layout") { $0.layouts.remove(at: k) }
                            LayoutTabs.select(model, 0)
                        }
                    }
                    Button("New Layout") { LayoutTabs.addLayout(model) }
                }
            }
            IconButton(symbol: "plus", help: "New layout (sheet)") { LayoutTabs.addLayout(model) }
            Spacer()
        }
        .padding(.leading, 6)
        .frame(height: 22)
        .background(Theme.ribbonTabBar)
    }
    private func rename(_ k: Int) {
        let a = NSAlert(); a.messageText = "Rename Layout"; a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); tf.stringValue = model.doc.layouts[k].name; a.accessoryView = tf
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = tf.stringValue.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !model.doc.layouts.contains(where: { $0.name == n }) else { return }
        let old = model.doc.layouts[k].name
        model.editor.transaction("Rename Layout") { d in
            // Settings keyed by sheet name follow the rename.
            for (key, v) in d.variables where key.hasSuffix(":" + old.uppercased()) || key.contains(":" + old.uppercased() + ":") {
                d.variables[key] = nil
                d.variables[key.replacingOccurrences(of: ":" + old.uppercased(), with: ":" + n.uppercased())] = v
            }
            d.layouts[k].name = n
        }
        model.syncCurrentTab()
    }
}

/// File tab bar (FILETAB): one tab per open drawing; hover shows a summary, click brings the window forward.
struct FileTabsBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var registry = OpenDocuments.shared
    @State private var hovered: Int?
    var body: some View {
        HStack(spacing: 1) {
            ForEach(registry.models.indices, id: \.self) { i in
                let m = registry.models[i]
                let current = m === model
                HStack(spacing: 5) {
                    Image(systemName: "doc").font(.system(size: 9))
                    Text(m.displayName + (m.isDirty ? " •" : "")).font(.system(size: 10.5, weight: current ? .semibold : .regular)).lineLimit(1)
                    if !current {
                        Button { m.window?.performClose(nil) } label: { Image(systemName: "xmark").font(.system(size: 8)) }.buttonStyle(.plain).help("Close \(m.displayName)")
                    }
                }
                .foregroundStyle(current ? Theme.text : Theme.textDim)
                .padding(.horizontal, 10).frame(height: 22)
                .background(current ? Theme.panel : Color.clear)
                .overlay(alignment: .bottom) { if current { Rectangle().fill(Theme.accent).frame(height: 2) } }
                .contentShape(Rectangle())
                .onTapGesture { m.window?.makeKeyAndOrderFront(nil) }
                .onHover { h in hovered = h ? i : (hovered == i ? nil : hovered) }
                .popover(isPresented: Binding(get: { hovered == i }, set: { if !$0 && hovered == i { hovered = nil } }), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let img = FileTabs.preview(m) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 240, height: 150).background(Color.white) }
                        Text(FileTabs.summary(m)).font(Theme.fontSmall).foregroundStyle(Theme.textDim).frame(width: 240, alignment: .leading)
                    }
                    .padding(8)
                }
            }
            IconButton(symbol: "plus", help: "New drawing (⌘N)") { WindowRouter.open(DocumentRequest(kind: .blankMetric)) }
            Spacer()
        }
        .padding(.leading, 6)
        .frame(height: 24)
        .background(Theme.ribbonTabBar)
        .onAppear { registry.refresh() }
    }
}

/// Open drawings for the file tab bar (refreshed when windows open, close or change title).
@MainActor
final class OpenDocuments: ObservableObject {
    static let shared = OpenDocuments()
    @Published private(set) var models: [AppModel] = []
    private var timer: Timer?
    func refresh() {
        let now = AppModel.all
        if now.map(ObjectIdentifier.init) != models.map(ObjectIdentifier.init) { models = now }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { OpenDocuments.shared.refresh() } }
        }
    }
}

@MainActor
enum FileTabs {
    static let key = "showFileTabs"
    static var visible: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key); for m in AppModel.all { m.revision &+= 1 } }
    }
    private static var previews: [ObjectIdentifier: (stamp: Int, image: NSImage)] = [:]
    /// Plan thumbnail of an open drawing for the tab hover preview (cached per document revision).
    static func preview(_ m: AppModel) -> NSImage? {
        let k = ObjectIdentifier(m)
        if let c = previews[k], c.stamp == m.editor.changeCount { return c.image }
        guard !m.isEmptyDocument, let data = Plotter.planPNG(doc: m.doc, level: m.doc.currentLevel, width: 480, height: 300, paper: true), let img = NSImage(data: data) else { return nil }
        previews[k] = (m.editor.changeCount, img)
        return img
    }
    /// Hover text of a file tab: path, objects, sheets and state.
    static func summary(_ m: AppModel) -> String {
        let d = m.doc
        var s = m.editor.fileURL?.path ?? "Not saved yet"
        s += "\n\(d.entities.count) drafting object(s), \(d.elements.count) building element(s), \(d.layouts.count) sheet(s), \(d.levels.count) level(s)"
        if m.isDirty { s += "\nUnsaved changes" }
        return s
    }
}

// MARK: - Contextual ribbon strip (APP-015)

/// Accent-coloured contextual tab shown above the ribbon content for the selected object type.
struct ContextualRibbonStrip: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let t = ContextualRibbon.tab(model.doc, model.editor.selection) {
            HStack(spacing: 2) {
                Text(t.title.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.5).foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 8).frame(height: 22).background(Theme.accent)
                ForEach(t.items.filter { model.command($0.names) != nil }) { item in
                    let r = model.command(item.names)!
                    Button { model.runCommand(r) } label: { Label(item.title, systemImage: item.symbol).font(.system(size: 10.5)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.text).padding(.horizontal, 6)
                        .help(model.editor.registry.lookup(r).map { "\($0.name) — \($0.summary)" } ?? r)
                }
                Spacer()
            }
            .frame(height: 22)
            .background(Theme.accent.opacity(0.14))
        }
    }
}

// MARK: - Status bar items (APP-042, APP-044, APP-025)

struct AnnotationScaleMenu: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            ForEach(AnnotationScaleControl.list(model.doc), id: \.self) { s in
                Button { AnnotationScaleControl.set(model, s) } label: { if s == AnnotationScaleControl.current(model.doc) { Label(s, systemImage: "checkmark") } else { Text(s) } }
            }
            Divider()
            Button("Edit Scale List…") { model.runCommand("SCALELISTEDIT") }
        } label: {
            HStack(spacing: 3) { Image(systemName: "a.magnify"); Text(AnnotationScaleControl.current(model.doc)) }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Annotation scale (CANNOSCALE): annotative text and dimensions are sized for this scale")
    }
}

struct ProgressStatusView: View {
    @ObservedObject var center = ProgressCenter.shared
    var body: some View {
        if let j = center.current {
            HStack(spacing: 5) {
                if let f = j.fraction { ProgressView(value: f).frame(width: 80) } else { ProgressView().controlSize(.mini) }
                Text(j.title + (j.detail.isEmpty ? "" : " · " + j.detail)).lineLimit(1)
                Button { center.cancel(j.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Cancel \(j.title)")
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Inspector (APP-033) and design center (APP-031) panels

struct InspectorPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let ids = model.selectedIDs
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if ids.isEmpty { Text("Select an object to list all of its data (LIST).").font(Theme.font).foregroundStyle(Theme.textDim) }
                ForEach(ids.prefix(20), id: \.self) { id in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(ObjectInspector.report(id, doc: model.doc).enumerated()), id: \.offset) { _, kv in
                            HStack(alignment: .top, spacing: 6) {
                                Text(kv.0).font(Theme.fontSmall).foregroundStyle(Theme.textDim).frame(width: 78, alignment: .leading)
                                Text(kv.1).font(.system(size: 10, design: kv.0 == "Geometry" ? .monospaced : .default)).foregroundStyle(Theme.text).textSelection(.enabled)
                            }
                        }
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(ObjectInspector.text(id, doc: model.doc), forType: .string) }
                            .buttonStyle(FlatButtonStyle()).controlSize(.small)
                    }
                    .padding(6).background(RoundedRectangle(cornerRadius: 4).fill(Theme.hover))
                }
                if ids.count > 20 { Text("… and \(ids.count - 20) more").font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
            }
            .padding(8)
        }
    }
}

struct DesignCenterPanel: View {
    @ObservedObject var model: AppModel
    @State private var source: ArchiDocument?
    @State private var sourceName = ""
    @State private var kind: DesignCenter.Kind = .blocks
    @State private var chosen: Set<String> = []
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu(sourceName.isEmpty ? "Choose Drawing" : sourceName) {
                    ForEach(AppModel.all.filter { $0 !== model }.indices, id: \.self) { i in
                        let m = AppModel.all.filter { $0 !== model }[i]
                        Button("Open window: \(m.displayName)") { load(m.doc, m.displayName) }
                    }
                    Divider()
                    Button("Drawing File…") { openFile() }
                }
                .fixedSize()
            }
            Picker("", selection: $kind) { ForEach(DesignCenter.Kind.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }.labelsHidden()
            if let src = source {
                List(DesignCenter.names(kind, in: src), id: \.self, selection: $chosen) { n in Text(n).font(Theme.font) }
                    .frame(minHeight: 200)
                HStack {
                    Button("Add to Drawing") { add(Array(chosen)) }.disabled(chosen.isEmpty).buttonStyle(FlatButtonStyle(prominent: true))
                    Button("Add All") { add(DesignCenter.names(kind, in: src)) }.buttonStyle(FlatButtonStyle())
                }
            } else {
                Text("Browse the blocks, layers, linetypes, styles and materials of another drawing and add them to this one (ADCENTER).")
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
            Spacer()
        }
        .padding(8)
        .onChange(of: kind) { _ in chosen = [] }
    }
    private func load(_ d: ArchiDocument, _ name: String) { source = d; sourceName = name; chosen = []; message = "" }
    private func openFile() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension: "archi") ?? .data]
        guard p.runModal() == .OK, let u = p.url, let data = try? Data(contentsOf: u), let d = try? ArchiFile.decode(data) else { return }
        load(d, u.deletingPathExtension().lastPathComponent)
    }
    private func add(_ names: [String]) {
        guard let src = source else { return }
        var added: [String] = []
        let k = kind
        model.editor.transaction("Design Center") { added = DesignCenter.copy(k, names, from: src, into: &$0) }
        message = added.isEmpty ? "Nothing new: those names already exist here." : "Added \(added.count): " + added.joined(separator: ", ")
    }
}

// MARK: - Help browser (APP-057, APP-058, APP-059, APP-055)

@MainActor
enum HelpPages {
    struct Tutorial { var title: String; var intro: String; var steps: [(String, String)] }
    /// Bundled tutorials: each step names a command line that the "Run" link executes in the front drawing.
    static let tutorials: [Tutorial] = [
        Tutorial(title: "1 · Your first floor plan", intro: "Draw four walls, add a door and a window, tag the room and dimension the walls.", steps: [
            ("Start a new metric drawing.", "NEW"), ("Draw a 6 × 4 m rectangle of walls: click four corners, then C to close.", "WALL"),
            ("Place a door in a wall.", "DOOR"), ("Place a window.", "WINDOW"), ("Click inside the walls to create the room.", "ROOM"),
            ("Dimension all walls automatically.", "AUTODIMWALLS"), ("Zoom to everything.", "ZOOM E")]),
        Tutorial(title: "2 · Sheets and PDF", intro: "Put the plan on an A3 sheet at 1:100 and export a vector PDF.", steps: [
            ("Create a sheet.", "LAYOUT"), ("Add a viewport of the plan.", "MVIEW"), ("Fill in the title block.", "TITLEBLOCK"),
            ("Preview the plot.", "PREVIEW"), ("Publish all sheets to one PDF.", "PUBLISH")]),
        Tutorial(title: "3 · 3D, styles and rendering", intro: "Look at the model in 3D, change the visual style and render an image.", steps: [
            ("Show the 3D view.", "SHOW3D"), ("South-west isometric view.", "ISOVIEW"), ("Hidden-line style.", "VSCURRENT Hidden"),
            ("Shaded with edges.", "VSCURRENT shadedwithEdges"), ("Render the view.", "RENDER")]),
        Tutorial(title: "4 · The sample house", intro: "Open the bundled sample project: a two-storey house with levels, sheets and rooms.", steps: [
            ("Open the sample house in a new window.", "SAMPLEHOUSE"), ("Browse its sheets with the tabs under the canvas.", "LAYOUTTABS")]),
    ]

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func runLink(_ line: String) -> String { "archi-run:" + (line.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? line) }
    private static let style = """
    <style>body{font:13px -apple-system,sans-serif;background:#1e1f22;color:#e6e6e6;margin:0;padding:18px 26px;line-height:1.45}
    a{color:#F5C518;text-decoration:none}a:hover{text-decoration:underline}h1{font-size:20px}h2{font-size:15px;margin-top:22px;border-bottom:1px solid #333;padding-bottom:4px}
    code{background:#2b2c31;padding:1px 5px;border-radius:3px}nav a{margin-right:14px}table{border-collapse:collapse}td{padding:3px 10px 3px 0;vertical-align:top}
    .dim{color:#9a9ba1}.run{background:#F5C518;color:#1e1f22;padding:1px 7px;border-radius:3px;font-size:11px}input{background:#2b2c31;color:#eee;border:1px solid #444;padding:5px;width:320px;border-radius:4px}
    </style>
    """
    private static func page(_ title: String, _ body: String) -> String {
        "<!doctype html><html><head><meta charset=utf-8><title>\(esc(title))</title>\(style)</head><body><nav><a href=\"archi-help:index\">Commands</a><a href=\"archi-help:tutorials\">Tutorials</a><a href=\"archi-help:shortcuts\">Keyboard &amp; mouse</a><a href=\"archi-help:scripting\">Scripting</a></nav>\(body)</body></html>"
    }

    static func index(_ r: CommandRegistry) -> String {
        var b = "<h1>Oanarina Archi Tool help</h1><p class=dim>\(r.sorted.count) commands. Type a command name on the command line, or press F1 while a command runs to open its page.</p>"
        b += "<input id=q placeholder='Filter commands…' oninput=\"for(const e of document.querySelectorAll('tr.c'))e.style.display=e.textContent.toLowerCase().includes(this.value.toLowerCase())?'':'none'\">"
        for (cat, list) in Dictionary(grouping: r.sorted, by: \.category).sorted(by: { $0.key < $1.key }) {
            b += "<h2>\(esc(cat))</h2><table>"
            for d in list { b += "<tr class=c><td><a href=\"archi-help:cmd/\(d.name)\"><code>\(d.name)</code></a></td><td class=dim>\(esc(d.aliases.joined(separator: ", ")))</td><td>\(esc(d.summary))</td></tr>" }
            b += "</table>"
        }
        return page("Help", b)
    }

    static func command(_ name: String, _ r: CommandRegistry) -> String? {
        guard let d = r.lookup(name) else { return nil }
        var b = "<h1><code>\(d.name)</code></h1><p>\(esc(d.summary))</p><table>"
        b += "<tr><td class=dim>Aliases</td><td>\(d.aliases.isEmpty ? "—" : esc(d.aliases.joined(separator: ", ")))</td></tr>"
        b += "<tr><td class=dim>Category</td><td>\(esc(d.category))</td></tr>"
        b += "<tr><td class=dim>Where</td><td>\(esc(CommandReferenceExport.location(d, registry: r)))</td></tr>"
        b += "<tr><td class=dim>Changes the drawing</td><td>\(d.modifies ? "Yes — one undo step" : "No")</td></tr></table>"
        b += "<h2>Use it</h2><p>Command line: <code>\(d.name)</code>\(d.aliases.first.map { " or <code>\(esc($0))</code>" } ?? "") · Script: <code>archi.run(\"\(d.name) \")</code> · Agent: <code>run_command {\"command\":\"\(d.name)\"}</code></p>"
        b += "<p><a class=run href=\"\(runLink(d.name))\">Run \(d.name)</a></p>"
        b += "<h2>Input</h2><p class=dim>Points: <code>x,y</code> · <code>@dx,dy</code> · <code>@dist&lt;angle</code> · a bare number = distance along the cursor. Options: type the capital letters of a keyword. Esc cancels, Enter accepts the default.</p>"
        let related = r.sorted.filter { $0.category == d.category && $0.name != d.name }.prefix(12)
        if !related.isEmpty { b += "<h2>Related</h2><p>" + related.map { "<a href=\"archi-help:cmd/\($0.name)\">\($0.name)</a>" }.joined(separator: " · ") + "</p>" }
        return page(d.name, b)
    }

    static func tutorialsPage(_ r: CommandRegistry) -> String {
        var b = "<h1>Tutorials and sample project</h1>"
        for t in tutorials {
            b += "<h2>\(esc(t.title))</h2><p>\(esc(t.intro))</p><ol>"
            for (text, line) in t.steps { b += "<li>\(esc(text)) <code>\(esc(line))</code> <a class=run href=\"\(runLink(line))\">Run</a></li>" }
            b += "</ol>"
        }
        return page("Tutorials", b)
    }

    static func shortcutsPage() -> String {
        var b = "<h1>Keyboard and mouse</h1><h2>Function keys (AutoCAD compatible)</h2><table>"
        for f in FunctionKeys.table { b += "<tr><td><code>\(f.key)</code></td><td>\(esc(f.action))</td></tr>" }
        b += "</table><h2>Grips</h2><table><tr><td>Click a grip</td><td>Stretch; Space cycles Move, Rotate, Scale, Mirror; type a distance or MO/RO/SC/MI/ST; C = copy</td></tr>"
        b += "<tr><td>Right-click a grip</td><td>Add / remove vertex, convert to arc or line, lengthen, radius</td></tr><tr><td>Space while dragging</td><td>Rotate 90° about the grip</td></tr></table>"
        b += "<h2>Selection</h2><table><tr><td>Drag left → right</td><td>Window selection</td></tr><tr><td>Drag right → left</td><td>Crossing selection</td></tr><tr><td>⌥-drag</td><td>Lasso (clockwise = window, counter-clockwise = crossing)</td></tr><tr><td>Tab over a wall</td><td>Select the chain of joined walls</td></tr><tr><td>Right-click</td><td>Shortcut menu (Repeat, Recent Input, Move, Copy, Rotate, Erase, Properties)</td></tr></table>"
        b += "<h2>View</h2><table><tr><td>Scroll / pinch</td><td>Zoom about the cursor</td></tr><tr><td>Middle-drag, Space-drag, two-finger scroll</td><td>Pan</td></tr><tr><td>Double middle-click</td><td>Zoom extents</td></tr><tr><td><code>DVIEW TW</code></td><td>Twist (rotate) the plan display</td></tr></table>"
        return page("Keyboard and mouse", b)
    }

    static func scriptingPage() -> String {
        let b = """
        <h1>Scripting and agents</h1><h2>JavaScript console (⌥⌘J)</h2><p><code>archi.run("LINE 0,0 1000,0 ")</code> runs any command; <code>archi.entities()</code>, <code>archi.add({...})</code>, <code>archi.select([ids])</code>, <code>archi.doc()</code> read and edit the drawing.</p>
        <h2>Agent server</h2><p>JSON-RPC 2.0 over HTTP on <code>127.0.0.1:47800</code> with a per-session token (Settings ▸ Agents). Methods: <code>run_command</code>, <code>get_document</code>, <code>list_entities</code>, <code>add_entity</code>, <code>update_entity</code>, <code>delete_entities</code>, <code>add_element</code>, <code>export</code>, <code>screenshot</code>, <code>list_methods</code>.</p>
        <h2>Command scripts</h2><p><code>SCRIPT</code> runs a .scr file: one command line per line, exactly as typed.</p>
        <h2>archi API reference</h2><table>
        """ + ScriptAPIReference.entries.map { sig, doc, ex in "<tr><td><code>\(esc(sig))</code></td><td>\(esc(doc))<br><code class=dim>\(esc(ex))</code></td></tr>" }.joined() + "</table>"
        return page("Scripting", b)
    }

    /// HTML for a help route: "index", "cmd/NAME", "tutorials", "shortcuts", "scripting".
    static func html(_ route: String, _ r: CommandRegistry) -> String {
        if route.hasPrefix("cmd/") { return command(String(route.dropFirst(4)), r) ?? index(r) }
        switch route { case "tutorials": return tutorialsPage(r); case "shortcuts": return shortcutsPage(); case "scripting": return scriptingPage(); default: return index(r) }
    }
    /// Help topic for F1: the running command, else the command typed so far, else the index.
    static func contextRoute(_ model: AppModel?) -> String {
        guard let m = model else { return "index" }
        if let c = m.editor.activeCommand?.name { return "cmd/" + c }
        let typed = m.commandInput.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        if let d = m.editor.registry.lookup(typed) { return "cmd/" + d.name }
        return "index"
    }
}

@MainActor
final class HelpBrowser: NSObject, WKNavigationDelegate {
    static let shared = HelpBrowser()
    private var window: NSWindow?
    private var web: WKWebView?
    private(set) var route = "index"

    static func show(_ route: String = "index") { shared.open(route) }

    func open(_ r: String) {
        route = r
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Oanarina Archi Tool Help"
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("ArchiHelpBrowser")
            let v = WKWebView(frame: w.contentView!.bounds)
            v.autoresizingMask = [.width, .height]
            v.navigationDelegate = self
            w.contentView?.addSubview(v)
            if w.frame.origin == .zero { w.center() }
            window = w; web = v
        }
        web?.loadHTMLString(HelpPages.html(r, .shared), baseURL: nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let u = action.request.url else { decisionHandler(.allow); return }
        let s = u.absoluteString
        if s.hasPrefix("archi-help:") { decisionHandler(.cancel); open(String(s.dropFirst("archi-help:".count))); return }
        if s.hasPrefix("archi-run:") {
            decisionHandler(.cancel)
            let line = String(s.dropFirst("archi-run:".count)).removingPercentEncoding ?? ""
            if let m = AppModel.all.first(where: { $0.window?.isMainWindow == true }) ?? AppModel.all.first { m.window?.makeKeyAndOrderFront(nil); m.runCommand(line) }
            return
        }
        if u.scheme == "http" || u.scheme == "https" { decisionHandler(.cancel); NSWorkspace.shared.open(u); return }
        decisionHandler(.allow)
    }
}

// MARK: - Menu / ribbon catalog of the navigation additions

extension CommandCatalog {
    private static func n(_ t: String, _ s: String, _ names: String...) -> CmdItem { CmdItem(title: t, symbol: s, names: names) }
    static let navigationItems: [CmdItem] = [
        n("File Tabs", "rectangle.topthird.inset.filled", "FILETAB"), n("Hide File Tabs", "rectangle", "FILETABCLOSE"), n("Model/Layout Tabs", "rectangle.bottomthird.inset.filled", "LAYOUTTABS"),
        n("Quick Properties", "slider.horizontal.below.rectangle", "QUICKPROPS"), n("Inspector", "list.bullet.rectangle", "INSPECT"), n("Design Center", "books.vertical.circle", "ADCENTER"),
        n("Help Browser", "questionmark.circle", "HELPWINDOW"), n("Tutorials", "graduationcap", "TUTORIALS"), n("Sample House", "house", "SAMPLEHOUSE"),
        n("Select Wall Chain", "link", "SELECTWALLCHAIN"), n("Twist View", "rotate.right", "DVIEW"), n("Perspective", "perspective", "PERSPECTIVE"),
        n("Maximise Viewport", "arrow.up.left.and.arrow.down.right", "VPMAX"), n("Restore Viewport", "arrow.down.right.and.arrow.up.left", "VPMIN"),
        n("Clip Viewport", "crop", "VPCLIP"), n("Polygonal Viewport", "pentagon", "MVIEWPOLY"), n("Align Viewports", "align.horizontal.center", "MVSETUP"),
        n("Sheet Guide Grid", "grid", "SHEETGRID"), n("Placeholder Sheet", "doc.badge.ellipsis", "SHEETPLACEHOLDER"), n("Custom Fields", "list.bullet.rectangle.portrait", "SHEETFIELD"),
        n("Import Page Setup", "square.and.arrow.down.on.square", "PSETUPIN"), n("Lineweight Display Scale", "lineweight", "LWDISPLAYSCALE"), n("Visual Styles Manager", "circle.lefthalf.filled", "VISUALSTYLES"), n("Tiled Views", "rectangle.split.2x2", "TILEDVIEWS"), n("Plot Area", "rectangle.dashed", "PLOTAREA"), n("Sheet to SVG", "square.and.arrow.up.on.square", "SHEETSVG"), n("Named Plot Styles", "paintpalette.fill", "PLOTSTYLENAME"), n("Export Settings", "square.and.arrow.up", "EXPORTSETTINGS"), n("Window Tabs", "macwindow.stack", "WINDOWTABS"), n("Full Screen", "arrow.up.left.and.arrow.down.right.square", "FULLSCREEN"), n("Import Settings", "square.and.arrow.down", "IMPORTSETTINGS"),
    ]
    /// File, template and exchange commands added by the core this round.
    static let fileExchangeItems: [CmdItem] = [
        n("Save a Copy", "doc.on.doc", "SAVECOPY"), n("Round-trip Check", "checkmark.seal", "SAVECHECK"), n("Upgrade File", "arrow.up.doc", "UPGRADEFILE"),
        n("File Metadata", "info.circle", "FILEMETADATA"), n("Save as Template File", "doc.badge.arrow.up", "TEMPLATEOUT"), n("New from Template File", "doc.badge.plus", "TEMPLATEIN"),
        n("Import Dropped File", "tray.and.arrow.down", "DROPIMPORT"), n("Attach PDF", "doc.richtext", "PDFATTACH"), n("PDF Underlays", "doc.on.clipboard", "PDFUNDERLAYS"),
        n("BREP In", "cube", "BREPIN"), n("BREP Out", "cube.fill", "BREPOUT"), n("E57 Scan In", "aqi.medium", "E57IN"), n("E57 Scan Out", "aqi.high", "E57OUT"),
    ]
    /// Analysis, generative and inquiry commands added by the core this round.
    static let analysisGenerativeItems: [CmdItem] = [
        n("Annual Daylight (sDA/ASE)", "sun.max.circle", "DAYLIGHTANNUAL"), n("Wind Study Export (CFD)", "wind", "CFDEXPORT"), n("Wind Results", "wind.circle", "WINDRESULTS"),
        n("Generative Layout", "wand.and.stars", "GENDESIGN"), n("Sketch to Walls", "scribble", "SKETCHTOWALLS"), n("Editing Time", "clock", "TIME"),
        n("Co-editing", "person.2.wave.2", "COEDIT"), n("BCF Server", "server.rack", "BCFSERVER"), n("Resolve Conflicts", "arrow.triangle.merge", "RESOLVECONFLICTS"), n("Clash Manager", "exclamationmark.triangle", "CLASHMANAGE"),
    ]
}

// MARK: - Layer tree (LAY-019)

/// Layer hierarchy from layer names: "A-WALL-EXT" is in group "A" (discipline) and sub-group "A-WALL"; xref layers
/// "HOUSE|A-WALL" group under "HOUSE|". Bulk toggles change every layer of a group in one undo step.
enum LayerTree {
    struct Group: Equatable { var name: String; var layers: [String] }
    static func key(_ layer: String) -> String {
        if let bar = layer.firstIndex(of: "|") { return String(layer[...bar]) }
        if let dash = layer.firstIndex(where: { $0 == "-" || $0 == "_" || $0 == " " }), dash != layer.startIndex { return String(layer[..<dash]) }
        return layer == "0" || layer.uppercased() == "DEFPOINTS" ? "(Standard)" : layer
    }
    static func groups(_ names: [String]) -> [Group] {
        var order: [String] = [], map: [String: [String]] = [:]
        for n in names { let k = key(n); if map[k] == nil { order.append(k) }; map[k, default: []].append(n) }
        return order.map { Group(name: $0, layers: map[$0]!) }
    }
    /// Sets a flag on every layer of a group. Returns the number of layers changed.
    @discardableResult
    static func setAll(_ doc: inout ArchiDocument, group: String, _ kp: WritableKeyPath<Layer, Bool>, _ value: Bool) -> Int {
        var n = 0
        for i in doc.layers.indices where key(doc.layers[i].name) == group && doc.layers[i][keyPath: kp] != value {
            // The current layer is never frozen (AutoCAD rule).
            if kp == \Layer.frozen && value && doc.layers[i].name.caseInsensitiveCompare(doc.currentLayer) == .orderedSame { continue }
            doc.layers[i][keyPath: kp] = value; n += 1
        }
        return n
    }
}

struct LayerGroupRow: View {
    @ObservedObject var model: AppModel
    let group: LayerTree.Group
    let open: Bool
    var toggleOpen: () -> Void
    var body: some View {
        let ls = model.doc.layers.filter { group.layers.contains($0.name) }
        let allOn = ls.allSatisfy(\.visible), allThawed = ls.allSatisfy { !$0.frozen }, allUnlocked = ls.allSatisfy { !$0.locked }
        HStack(spacing: 4) {
            Button(action: toggleOpen) { Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)) }.buttonStyle(.plain).frame(width: 16)
            bulk(allOn ? "eye" : "eye.slash", help: allOn ? "Turn the group off" : "Turn the group on") { LayerTree.setAll(&$0, group: group.name, \.visible, !allOn) }
            bulk(allThawed ? "sun.max" : "snowflake", help: allThawed ? "Freeze the group" : "Thaw the group") { LayerTree.setAll(&$0, group: group.name, \.frozen, allThawed) }
            bulk(allUnlocked ? "lock.open" : "lock.fill", help: allUnlocked ? "Lock the group" : "Unlock the group") { LayerTree.setAll(&$0, group: group.name, \.locked, allUnlocked) }
            Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(Theme.textDim).frame(width: 16)
            Text("\(group.name)  (\(group.layers.count))").font(Theme.fontBold).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8).frame(height: 24)
        .background(Theme.hover)
    }
    private func bulk(_ symbol: String, help: String, _ change: @escaping (inout ArchiDocument) -> Void) -> some View {
        Button { model.editor.transaction("Layer Group \(group.name)", change) } label: { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.plain).frame(width: 16).help(help)
    }
}
