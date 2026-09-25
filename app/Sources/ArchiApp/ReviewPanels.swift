// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

// MARK: - Shared helpers

@MainActor
enum ReviewUI {
    /// Shows a region of the plan: switches to the plan canvas (and level) and zooms to the box with a margin.
    static func zoom(model: AppModel, to box: BBox2, level: Int? = nil) {
        guard !box.isEmpty else { return }
        if let l = level, model.doc.levels.indices.contains(l), model.doc.currentLevel != l {
            model.editor.doc.currentLevel = l
        }
        if model.mode == .model || model.mode == .sheet { model.mode = .plan }
        let m = max(box.width, box.height, 1) * 0.25
        DispatchQueue.main.async { model.canvas?.zoom(to: box.expanded(by: m)); model.revision &+= 1 }
    }

    static func panel(_ title: String, key: String, size: NSSize, content: some View) -> NSPanel {
        let w = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.isFloatingPanel = true
        w.hidesOnDeactivate = true
        w.appearance = Theme.appearance
        w.contentViewController = NSHostingController(rootView: content.preferredColorScheme(Theme.colorScheme))
        w.setFrameAutosaveName(key)
        if w.frame.origin == .zero { w.center() }
        return w
    }
}

// MARK: - Markups / issues panel (COL-011)

enum MarkupWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        let v = MarkupPanel(model: model)
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Markups", key: "ArchiMarkupPanel", size: NSSize(width: 420, height: 560), content: v)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Filtering and ordering of markups for the panel (pure, tested by the self-tests).
enum MarkupFilter: String, CaseIterable {
    case open = "Open", resolved = "Resolved", all = "All"
    func apply(_ list: [Markup], query: String = "") -> [Markup] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return list.filter { m in
            (self == .all || (self == .open) == !m.isResolved)
                && (q.isEmpty || "\(m.title) \(m.comment) \(m.author) \(m.replies.map { $0.text }.joined(separator: " "))".lowercased().contains(q))
        }
    }
}

struct MarkupPanel: View {
    @ObservedObject var model: AppModel
    @State private var filter: MarkupFilter = .open
    @State private var query = ""
    @State private var selected: String?
    @State private var reply = ""
    @State private var newComment = ""
    @State private var newTitle = ""

    private var markups: [Markup] { Markups.list(model.doc) }

    var body: some View {
        let all = markups
        let shown = filter.apply(all, query: query)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Picker("", selection: $filter) { ForEach(MarkupFilter.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                Text("\(all.filter { !$0.isResolved }.count) open · \(all.filter(\.isResolved).count) resolved").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            }.padding(8)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
                TextField("Search comments, authors, replies", text: $query).textFieldStyle(.plain).font(Theme.font)
            }.padding(6).darkField().padding(.horizontal, 8)
            List(selection: $selected) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { _, m in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: m.isResolved ? "checkmark.circle.fill" : "exclamationmark.bubble.fill")
                            .foregroundStyle(m.isResolved ? Color.green : Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title.isEmpty ? m.comment : m.title).font(Theme.fontBold).lineLimit(1)
                            Text("\(m.author) · \(String(m.date.prefix(10)))\(m.replies.isEmpty ? "" : " · \(m.replies.count) repl\(m.replies.count == 1 ? "y" : "ies")")")
                                .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                        }
                    }
                    .tag(m.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { zoom(m) }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 160)
            HSeparator()
            if let id = selected, let m = all.first(where: { $0.id == id }) { detail(m) } else { addForm }
        }
        .background(Theme.panel)
        .frame(minWidth: 360, minHeight: 420)
    }

    private func detail(_ m: Markup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !m.title.isEmpty { Text(m.title).font(Theme.fontBold) }
            Text(m.comment).font(Theme.font).textSelection(.enabled)
            Text("\(m.author) · \(m.date)\(m.elements.isEmpty ? "" : " · linked: " + m.elements.map { "#\($0)" }.joined(separator: ", "))").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            ForEach(Array(m.replies.enumerated()), id: \.offset) { _, r in
                Text("↳ \(r.author) (\(String(r.date.prefix(10)))): \(r.text)").font(Theme.fontSmall).foregroundStyle(Theme.text)
            }
            HStack {
                TextField("Reply…", text: $reply).textFieldStyle(.plain).padding(4).darkField().onSubmit { sendReply(m) }
                Button("Reply") { sendReply(m) }.buttonStyle(FlatButtonStyle(compact: true)).disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 6) {
                Button(m.isResolved ? "Reopen" : "Resolve") {
                    model.editor.transaction(m.isResolved ? "Reopen Markup" : "Resolve Markup") { Markups.setStatus(&$0, m.id, resolved: !m.isResolved) }
                    model.revision &+= 1
                }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Zoom To") { zoom(m) }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Select Linked") { model.editor.selection = Set(m.elements.filter { model.doc.element($0) != nil || model.doc.entity($0) != nil }); model.revision &+= 1 }
                    .buttonStyle(FlatButtonStyle(compact: true)).disabled(m.elements.isEmpty)
                Spacer()
                Button("Delete") {
                    model.editor.transaction("Delete Markup") { Markups.remove(&$0, m.id) }
                    selected = nil; model.revision &+= 1
                }.buttonStyle(FlatButtonStyle(compact: true))
                Button("New…") { selected = nil }.buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .padding(8)
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New markup").font(Theme.fontBold)
            TextField("Title (optional)", text: $newTitle).textFieldStyle(.plain).padding(4).darkField()
            TextField("Comment", text: $newComment).textFieldStyle(.plain).padding(4).darkField()
            HStack {
                Button("Around Selection") { addAroundSelection() }.buttonStyle(FlatButtonStyle(compact: true))
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || model.editor.selection.isEmpty)
                    .help("Clouds the selected objects and links them to the markup")
                Button("Draw Cloud…") { model.mode = model.mode == .model ? .plan : model.mode; model.runCommand("MARKUP Add") }.buttonStyle(FlatButtonStyle(compact: true))
                    .help("Pick two corners on the plan, then type the comment on the command line")
                Spacer()
                Button("Export BCF…") { model.runCommand("BCFOUT") }.buttonStyle(FlatButtonStyle(compact: true))
                Button("Import BCF…") { model.runCommand("BCFIN") }.buttonStyle(FlatButtonStyle(compact: true))
            }
        }
        .padding(8)
    }

    private func sendReply(_ m: Markup) {
        let t = reply.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        model.editor.transaction("Reply to Markup") { Markups.reply(&$0, m.id, text: t) }
        reply = ""; model.revision &+= 1
    }

    private func addAroundSelection() {
        let doc = model.doc
        var b = BBox2.empty
        for id in model.editor.selection {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            if let el = doc.element(id) { b.add(PlanRepresentation.bounds(el, doc: doc)) }
        }
        guard !b.isEmpty else { return }
        let m = max(b.width, b.height, 100) * 0.1
        let ids = model.editor.selection.sorted()
        var mid = ""
        let c = newComment, t = newTitle
        model.editor.transaction("Add Markup") { d in mid = Markups.add(&d, rect: (b.min - Vec2(m, m), b.max + Vec2(m, m)), title: t, comment: c, elements: ids, level: d.currentLevel) }
        newComment = ""; newTitle = ""; selected = mid; filter = .open
        model.revision &+= 1
    }

    private func zoom(_ m: Markup) {
        let h = m.viewHeight > 0 ? m.viewHeight : m.bounds.height
        let box = m.bounds.isEmpty ? BBox2(min: m.viewCenter - Vec2(h * 0.8, h / 2), max: m.viewCenter + Vec2(h * 0.8, h / 2)) : m.bounds
        ReviewUI.zoom(model: model, to: box, level: m.level)
        model.editor.selection = Set(m.entityIDs)
    }
}

// MARK: - Drawing compare overlay (COL-012)

/// A compare result shown over the plan canvas: outlines of added (green), removed (red, from the other version) and
/// modified (yellow) objects. Kept per window; cleared when the panel is closed or the overlay is switched off.
@MainActor
final class CompareOverlay: ObservableObject {
    static var byModel: [ObjectIdentifier: CompareOverlay] = [:]
    static func of(_ m: AppModel) -> CompareOverlay { if let o = byModel[ObjectIdentifier(m)] { return o }; let o = CompareOverlay(); byModel[ObjectIdentifier(m)] = o; return o }

    struct Shape { var kind: ChangeKind; var polylines: [[Vec2]]; var bounds: BBox2; var change: DocumentChange }
    @Published var other: URL?
    @Published var diff: DocumentDiff?
    @Published var visible = true
    @Published var kinds: Set<ChangeKind> = [.added, .removed, .modified]
    private(set) var shapes: [Shape] = []

    /// Plan outlines of each change: entity geometry tessellated, element plan outlines; removed objects come from `old`.
    static func shapes(_ d: DocumentDiff, old: ArchiDocument, new: ArchiDocument) -> [Shape] {
        var out: [Shape] = []
        for c in d.differences {
            let doc = c.kind == .removed ? old : new
            let id = c.kind == .removed ? c.id : c.id
            var polys: [[Vec2]] = []
            if c.object == "entity", let e = doc.entity(id) { polys = Array(GeometryOps.tessellate(e.geometry, doc: doc).prefix(200)) }
            else if c.object == "element", let el = doc.element(id) {
                let b = PlanRepresentation.bounds(el, doc: doc)
                if !b.isEmpty { polys = [[b.min, Vec2(b.max.x, b.min.y), b.max, Vec2(b.min.x, b.max.y), b.min]] }
            }
            if polys.isEmpty, !c.bounds.isEmpty { let b = c.bounds; polys = [[b.min, Vec2(b.max.x, b.min.y), b.max, Vec2(b.min.x, b.max.y), b.min]] }
            out.append(Shape(kind: c.kind, polylines: polys, bounds: c.bounds, change: c))
        }
        return out
    }

    func load(_ url: URL, model: AppModel) throws {
        let old = try FileImport.load(url, reference: model.doc).0
        let d = DocumentCompare.compare(old, model.doc)
        other = url; diff = d; visible = true
        shapes = Self.shapes(d, old: old, new: model.doc)
    }
    func clear() { other = nil; diff = nil; shapes = [] }

    /// Draws the overlay in world coordinates (called by the plan canvas inside its world transform).
    func draw(_ ctx: CGContext, scale: CGFloat) {
        guard visible, !shapes.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineWidth(2.5 / scale)
        for s in shapes where kinds.contains(s.kind) {
            let c = DocumentCompare.layerColors[s.kind] ?? RGBA(1, 1, 1)
            ctx.setStrokeColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.95))
            if s.kind == .removed { ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale]) } else { ctx.setLineDash(phase: 0, lengths: []) }
            for p in s.polylines where p.count >= 2 {
                ctx.beginPath(); ctx.move(to: CGPoint(x: p[0].x, y: p[0].y))
                for q in p.dropFirst() { ctx.addLine(to: CGPoint(x: q.x, y: q.y)) }
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}

enum CompareWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        let v = ComparePanel(model: model, overlay: .of(model))
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Compare Drawings", key: "ArchiComparePanel", size: NSSize(width: 440, height: 520), content: v)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ComparePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var overlay: CompareOverlay
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Compare With…") { choose() }.buttonStyle(FlatButtonStyle())
                if let u = overlay.other { Text(u.lastPathComponent).font(Theme.font).foregroundStyle(Theme.textDim).lineLimit(1) }
                Spacer()
                if overlay.diff != nil { Button("Clear") { overlay.clear(); model.revision &+= 1 }.buttonStyle(FlatButtonStyle(compact: true)) }
            }
            if !error.isEmpty { Text(error).font(Theme.fontSmall).foregroundStyle(.red) }
            if let d = overlay.diff {
                HStack(spacing: 12) {
                    Toggle("Overlay", isOn: Binding(get: { overlay.visible }, set: { overlay.visible = $0; model.revision &+= 1 }))
                    ForEach([ChangeKind.added, .removed, .modified], id: \.self) { k in
                        Toggle(isOn: Binding(get: { overlay.kinds.contains(k) }, set: { on in if on { overlay.kinds.insert(k) } else { overlay.kinds.remove(k) }; model.revision &+= 1 })) {
                            HStack(spacing: 3) {
                                Circle().fill(color(k)).frame(width: 8, height: 8)
                                Text("\(k.rawValue.capitalized) \(d.count(k))").font(Theme.fontSmall)
                            }
                        }
                    }
                }
                .toggleStyle(.checkbox)
                if d.isIdentical { Text("The drawings are identical.").font(Theme.font).foregroundStyle(Theme.textDim) }
                if !d.layersAdded.isEmpty || !d.layersRemoved.isEmpty {
                    Text("Layers: +\(d.layersAdded.joined(separator: ", ")) −\(d.layersRemoved.joined(separator: ", "))").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                List {
                    ForEach(Array(overlay.shapes.enumerated()).filter { overlay.kinds.contains($0.element.kind) }, id: \.offset) { _, s in
                        HStack(spacing: 6) {
                            Circle().fill(color(s.kind)).frame(width: 8, height: 8)
                            Text("\(s.change.type) #\(s.change.id)").font(Theme.font)
                            Text(s.change.layer).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                            Spacer()
                            if !s.change.fields.isEmpty { Text(s.change.fields.joined(separator: ", ")).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            ReviewUI.zoom(model: model, to: s.bounds, level: s.change.level)
                            if s.kind != .removed { model.editor.selection = [s.change.id] }
                        }
                    }
                }.listStyle(.plain)
                HStack {
                    Button("Save Overlay Drawing…") { saveOverlay() }.buttonStyle(FlatButtonStyle(compact: true))
                    Button("Export CSV…") { saveCSV(d) }.buttonStyle(FlatButtonStyle(compact: true))
                }
            } else {
                Text("Choose an older version (.archi, .dxf, .ifc…) to see what changed: added objects in green, removed in red (dashed), modified in yellow, drawn over the plan.")
                    .font(Theme.font).foregroundStyle(Theme.textDim)
                Spacer()
            }
        }
        .padding(10)
        .background(Theme.panel)
        .frame(minWidth: 380, minHeight: 360)
    }

    private func color(_ k: ChangeKind) -> Color {
        let c = DocumentCompare.layerColors[k] ?? RGBA(1, 1, 1)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }
    private func choose() {
        let p = NSOpenPanel()
        p.message = "Choose the other (older) version of the drawing"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try overlay.load(u, model: model); error = ""; model.revision &+= 1 } catch { self.error = "Cannot read \(u.lastPathComponent): \(error.localizedDescription)" }
    }
    private func saveOverlay() {
        guard let u = overlay.other, let old = try? FileImport.load(u, reference: model.doc).0 else { return }
        let p = NSSavePanel(); p.nameFieldStringValue = "compare-overlay.archi"
        guard p.runModal() == .OK, let out = p.url else { return }
        do { try ArchiFile.encode(DocumentCompare.overlay(old, model.doc, diff: overlay.diff)).write(to: out, options: .atomic); model.editor.print("Wrote overlay \(out.path).") }
        catch { self.error = "Cannot write \(out.path)" }
    }
    private func saveCSV(_ d: DocumentDiff) {
        let p = NSSavePanel(); p.nameFieldStringValue = "compare.csv"
        guard p.runModal() == .OK, let out = p.url else { return }
        do { try d.csv.write(to: out, atomically: true, encoding: .utf8) } catch { self.error = "Cannot write \(out.path)" }
    }
}

// MARK: - Sheet revision clouds (SHT)

/// Revision clouds on sheets: closed cloud polylines in a layout's paper space tagged with a revision code, each with a
/// numbered revision triangle. Pure document logic (tested by the self-tests); the panel below is its UI.
enum SheetRevisionClouds {
    static let layer = "REVISION CLOUDS"
    struct Cloud: Hashable { var layout: Int; var id: EntityID; var code: String; var note: String; var bounds: BBox2 }

    /// Adds a cloud around `rect` (paper mm) on sheet `li` for revision `code`, plus its triangle tag. Returns the cloud id.
    @discardableResult
    static func add(_ doc: inout ArchiDocument, layout li: Int, rect: BBox2, code: String, note: String = "", arc: Double = 8) -> EntityID? {
        guard doc.layouts.indices.contains(li), rect.width > 0, rect.height > 0, !code.isEmpty else { return nil }
        if doc.layerIndex(layer) == nil { doc.layers.append(Layer(name: layer, color: RGBA(0.9, 0.15, 0.1), lineweight: 0.35)) }
        let cloud = Markups.cloud(rect.min, rect.max, arc: arc)
        let id = doc.allocateID()
        var props = ["revCloud": code]
        if !note.isEmpty { props["revNote"] = note }
        doc.layouts[li].entities.append(Entity(id: id, layer: layer, geometry: .polyline(cloud), props: props))
        // Revision triangle at the top-right corner with the code inside.
        let s = 6.0, c = Vec2(rect.max.x + s * 0.8, rect.max.y + s * 0.5)
        let tri = PolylineGeom([PolyVertex(c + Vec2(-s / 2, -s * 0.29)), PolyVertex(c + Vec2(s / 2, -s * 0.29)), PolyVertex(c + Vec2(0, s * 0.58))], closed: true)
        doc.layouts[li].entities.append(Entity(id: doc.allocateID(), layer: layer, geometry: .polyline(tri), props: ["revTag": "\(id)"]))
        doc.layouts[li].entities.append(Entity(id: doc.allocateID(), layer: layer,
                                               geometry: .text(TextGeom(position: c - Vec2(0, s * 0.1), height: s * 0.4, content: code, halign: .center, valign: .middle)), props: ["revTag": "\(id)"]))
        return id
    }

    static func list(_ doc: ArchiDocument) -> [Cloud] {
        var out: [Cloud] = []
        for (li, l) in doc.layouts.enumerated() {
            for e in l.entities { if let code = e.props["revCloud"] { out.append(Cloud(layout: li, id: e.id, code: code, note: e.props["revNote"] ?? "", bounds: GeometryOps.bounds(e.geometry, doc: doc))) } }
        }
        return out
    }

    /// Removes a cloud and its tag.
    @discardableResult
    static func remove(_ doc: inout ArchiDocument, _ id: EntityID) -> Bool {
        var any = false
        for li in doc.layouts.indices {
            let n = doc.layouts[li].entities.count
            doc.layouts[li].entities.removeAll { $0.id == id || $0.props["revTag"] == "\(id)" }
            any = any || doc.layouts[li].entities.count != n
        }
        return any
    }

    /// Clouds per revision code (for the revision schedule), in code order.
    static func counts(_ doc: ArchiDocument) -> [(code: String, sheets: [String], clouds: Int)] {
        var by: [String: (Set<String>, Int)] = [:]
        for c in list(doc) { var v = by[c.code] ?? ([], 0); v.0.insert(doc.layouts[c.layout].name); v.1 += 1; by[c.code] = v }
        return by.keys.sorted { $0.count != $1.count ? $0.count < $1.count : $0 < $1 }.map { ($0, by[$0]!.0.sorted(), by[$0]!.1) }
    }
}

enum RevisionCloudWindow {
    private static var window: NSPanel?
    @MainActor static func show(model: AppModel) {
        let v = RevisionCloudPanel(model: model)
        if let w = window { w.contentViewController = NSHostingController(rootView: v.preferredColorScheme(Theme.colorScheme)); w.makeKeyAndOrderFront(nil); return }
        window = ReviewUI.panel("Revision Clouds", key: "ArchiRevCloudPanel", size: NSSize(width: 420, height: 480), content: v)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct RevisionCloudPanel: View {
    @ObservedObject var model: AppModel
    @State private var sheet = 0
    @State private var code = ""
    @State private var note = ""
    @State private var target = -1   // viewport index, -1 = custom rectangle
    @State private var rx = "20"
    @State private var ry = "20"
    @State private var rw = "60"
    @State private var rh = "40"

    var body: some View {
        let doc = model.doc
        VStack(alignment: .leading, spacing: 8) {
            if doc.layouts.isEmpty {
                Text("The drawing has no sheets. Create a layout first.").font(Theme.font).foregroundStyle(Theme.textDim)
                Spacer()
            } else {
                let li = min(max(sheet, 0), doc.layouts.count - 1)
                let revs = SheetSet.revisions(doc.layouts[li]).map(\.code)
                Picker("Sheet", selection: $sheet) { ForEach(doc.layouts.indices, id: \.self) { Text(doc.layouts[$0].name).tag($0) } }
                HStack {
                    Text("Revision").font(Theme.font)
                    TextField(revs.last ?? "A", text: $code).textFieldStyle(.plain).padding(4).darkField().frame(width: 60)
                    if !revs.isEmpty { Menu("Sheet revisions") { ForEach(revs, id: \.self) { r in Button(r) { code = r } } }.menuStyle(.borderlessButton).fixedSize() }
                    TextField("Note", text: $note).textFieldStyle(.plain).padding(4).darkField()
                }
                Picker("Around", selection: $target) {
                    Text("Rectangle (mm on paper)").tag(-1)
                    ForEach(doc.layouts[li].viewports.indices, id: \.self) { Text("Viewport \($0 + 1)").tag($0) }
                }
                if target < 0 {
                    HStack { field("x", $rx); field("y", $ry); field("w", $rw); field("h", $rh) }
                }
                Button("Add Revision Cloud") { add(li, revs: revs) }.buttonStyle(FlatButtonStyle())
                HSeparator()
                let clouds = SheetRevisionClouds.list(doc)
                Text("\(clouds.count) cloud(s)").font(Theme.fontBold)
                List {
                    ForEach(clouds, id: \.self) { c in
                        HStack {
                            Image(systemName: "cloud").foregroundStyle(.red)
                            Text("\(doc.layouts[c.layout].name) · rev \(c.code)").font(Theme.font)
                            if !c.note.isEmpty { Text(c.note).font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1) }
                            Spacer()
                            Button { model.mode = .sheet; model.activeLayout = c.layout; model.revision &+= 1 } label: { Image(systemName: "arrow.right.circle") }.buttonStyle(.plain).help("Open the sheet")
                            Button { model.editor.transaction("Delete Revision Cloud") { SheetRevisionClouds.remove(&$0, c.id) }; model.revision &+= 1 } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete the cloud and its tag")
                        }
                    }
                }.listStyle(.plain)
                ForEach(SheetRevisionClouds.counts(doc), id: \.code) { r in
                    Text("Rev \(r.code): \(r.clouds) cloud(s) on \(r.sheets.joined(separator: ", "))").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
            }
        }
        .padding(10)
        .background(Theme.panel)
        .frame(minWidth: 380, minHeight: 360)
    }

    private func field(_ label: String, _ b: Binding<String>) -> some View {
        HStack(spacing: 2) { Text(label).font(Theme.fontSmall).foregroundStyle(Theme.textDim); TextField("", text: b).textFieldStyle(.plain).padding(3).darkField().frame(width: 52) }
    }

    private func add(_ li: Int, revs: [String]) {
        let doc = model.doc
        let c = code.trimmingCharacters(in: .whitespaces).isEmpty ? (revs.last ?? "A") : code.trimmingCharacters(in: .whitespaces)
        var rect: BBox2
        if target >= 0, doc.layouts[li].viewports.indices.contains(target) {
            let v = doc.layouts[li].viewports[target]
            rect = BBox2(min: v.origin, max: v.origin + v.size).expanded(by: 3)
        } else {
            guard let x = Double(rx), let y = Double(ry), let w = Double(rw), let h = Double(rh), w > 0, h > 0 else { return }
            rect = BBox2(min: Vec2(x, y), max: Vec2(x + w, y + h))
        }
        let n = note
        model.editor.transaction("Revision Cloud") { SheetRevisionClouds.add(&$0, layout: li, rect: rect, code: c, note: n) }
        model.revision &+= 1
    }
}
