// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArchiCore

/// Paper-space layout editor: sheets with scaled model viewports, title block, north arrow and scale bar.
struct SheetView: View {
    @ObservedObject var model: AppModel
    @State private var sheetName = ""
    init(model: AppModel) { self.model = model }

    private var layoutIndex: Int {
        let n = model.doc.layouts.count
        return n == 0 ? -1 : min(max(model.activeLayout, 0), n - 1)
    }
    private var layout: ArchiCore.Layout? { layoutIndex >= 0 ? model.doc.layouts[layoutIndex] : nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if layout != nil {
                SheetCanvas(model: model, layoutIndex: layoutIndex, revision: model.revision)
            } else {
                VStack(spacing: 12) {
                    Text("No sheets yet").font(.title3).foregroundStyle(.secondary)
                    Button("New A3 Sheet") { newSheet(PaperSize.standard[1]) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.16))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if !model.doc.layouts.isEmpty {
                Picker("Sheet", selection: Binding(get: { layoutIndex }, set: { model.activeLayout = $0 })) {
                    ForEach(Array(model.doc.layouts.enumerated()), id: \.offset) { i, l in Text(l.name).tag(i) }
                }.frame(maxWidth: 200)
                TextField("Name", text: $sheetName, onCommit: renameSheet)
                    .frame(width: 130).textFieldStyle(.roundedBorder)
                    .onAppear { sheetName = layout?.name ?? "" }
                    .onChange(of: layoutIndex) { _ in sheetName = layout?.name ?? "" }
                Picker("Paper", selection: Binding(get: { layout?.paper.name ?? "A3" }, set: setPaper)) {
                    ForEach(PaperSize.standard, id: \.name) { p in Text("\(p.name) (\(fmt(p.width, 0))×\(fmt(p.height, 0)))").tag(p.name) }
                }.frame(maxWidth: 190)
            }
            Menu("New Sheet") {
                ForEach(PaperSize.standard, id: \.name) { p in
                    Button("\(p.name) landscape") { newSheet(p) }
                }
                Divider()
                ForEach(PaperSize.standard.prefix(5), id: \.name) { p in
                    Button("\(p.name) portrait") { newSheet(PaperSize(name: p.name + " portrait", width: p.height, height: p.width)) }
                }
            }.fixedSize()
            Menu("Add Viewport") {
                Section("Plan of \(model.doc.level(model.doc.currentLevel)?.name ?? "current level")") {
                    ForEach([50.0, 100, 200], id: \.self) { s in Button("Plan 1:\(Int(s))") { addViewport(.plan, scale: s) } }
                }
                Section("Elevations (1:100)") {
                    Button("North") { addViewport(.elevationNorth, scale: 100) }
                    Button("South") { addViewport(.elevationSouth, scale: 100) }
                    Button("East") { addViewport(.elevationEast, scale: 100) }
                    Button("West") { addViewport(.elevationWest, scale: 100) }
                }
                Section("Section") {
                    Button("Section A-A 1:100") { addViewport(.section, scale: 100) }
                    Button("Section A-A 1:50") { addViewport(.section, scale: 50) }
                }
            }.fixedSize().disabled(layout == nil)
            if let l = layout, !l.viewports.isEmpty {
                Menu("Viewports") {
                    ForEach(Array(l.viewports.enumerated()), id: \.offset) { i, vp in
                        let locked = ViewportLock.isLocked(model.doc, layoutIndex: layoutIndex, viewport: i)
                        Menu((locked ? "🔒 " : "") + SheetComposer.viewTitle(vp, doc: model.doc) + "  " + SheetComposer.ratioText(vp.scale, units: model.doc.units)) {
                            ForEach([20.0, 50, 100, 200, 500], id: \.self) { s in
                                Button("Scale 1:\(Int(s))") { setViewportScale(i, s) }.disabled(locked)
                            }
                            Divider()
                            Button(locked ? "Unlock Viewport" : "Lock Viewport") {
                                let li = layoutIndex
                                model.editor.transaction(locked ? "Unlock Viewport" : "Lock Viewport") { ViewportLock.set(&$0, layoutIndex: li, viewport: i, locked: !locked) }
                            }
                            Button("Remove", role: .destructive) { removeViewport(i) }.disabled(locked)
                        }
                    }
                }.fixedSize()
            }
            Spacer()
            Button { let i = layoutIndex; model.editor.transaction("View Titles") { SheetSet.refreshViewTitles(&$0, i) } } label: { Label("View Titles", systemImage: "textformat.size") }
                .disabled(layout?.viewports.isEmpty ?? true)
                .help("Editable view titles under every viewport (SHEETVIEWTITLES)")
            Button { model.showPanels = true; model.panelTab = .sheets } label: { Label("Sheet Set", systemImage: "rectangle.stack") }
                .help("Sheet set manager: numbering, order, revisions, sheet index (SHEETSET)")
            Button { model.sheet = .titleBlock(layoutIndex) } label: { Label("Title Block", systemImage: "list.bullet.rectangle.portrait") }.disabled(layout == nil)
                .help("Edit the title block (TITLEBLOCK)")
            Button { model.sheet = .pageSetup(layoutIndex) } label: { Label("Page Setup", systemImage: "doc.badge.gearshape") }.disabled(layout == nil)
                .help("Paper, plot style and plot stamp (PAGESETUP)")
            Button { PlotPreviewWindow.show(model: model) } label: { Label("Preview", systemImage: "eye") }.disabled(layout == nil)
            Button { Plotter.publish(model: model, path: nil) } label: { Label("Publish", systemImage: "doc.on.doc") }.disabled(model.doc.layouts.isEmpty)
                .help("All sheets in one PDF (PUBLISH)")
            Button { exportPDF() } label: { Label("PDF", systemImage: "doc.richtext") }.disabled(layout == nil)
            Button { Plotter.printDrawing(model: model) } label: { Label("Print", systemImage: "printer") }.disabled(layout == nil)
            if model.doc.layouts.count > 1 {
                Button(role: .destructive) { deleteSheet() } label: { Image(systemName: "trash") }.help("Delete this sheet")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .controlSize(.small)
    }

    // MARK: Actions (each is one undo step)

    private func newSheet(_ paper: PaperSize) {
        model.editor.transaction("New Sheet") { d in
            var n = d.layouts.count + 1
            while d.layouts.contains(where: { $0.name == "Sheet \(n)" }) { n += 1 }
            d.layouts.append(ArchiCore.Layout(name: "Sheet \(n)", paper: paper))
        }
        model.activeLayout = model.doc.layouts.count - 1
        sheetName = layout?.name ?? ""
    }

    private func renameSheet() {
        let i = layoutIndex, name = sheetName.trimmingCharacters(in: .whitespaces)
        guard i >= 0, !name.isEmpty, name != model.doc.layouts[i].name else { return }
        model.editor.transaction("Rename Sheet") { $0.layouts[i].name = name }
    }

    private func setPaper(_ name: String) {
        let i = layoutIndex
        guard i >= 0, let p = PaperSize.standard.first(where: { $0.name == name }) else { return }
        model.editor.transaction("Paper Size") { $0.layouts[i].paper = p }
    }

    private func deleteSheet() {
        let i = layoutIndex
        guard i >= 0, model.doc.layouts.count > 1 else { return }
        model.editor.transaction("Delete Sheet") { $0.layouts.remove(at: i) }
        model.activeLayout = max(0, i - 1)
    }

    private func removeViewport(_ v: Int) {
        let i = layoutIndex
        guard i >= 0 else { return }
        guard !ViewportLock.isLocked(model.doc, layoutIndex: i, viewport: v) else { model.editor.print("The viewport is locked (VPLOCK Off to unlock)."); return }
        model.editor.transaction("Remove Viewport") { d in
            if d.layouts[i].viewports.indices.contains(v) { d.layouts[i].viewports.remove(at: v); ViewportLock.removed(&d, layoutIndex: i, viewport: v) }
        }
    }

    private func setViewportScale(_ v: Int, _ ratio: Double) {
        let i = layoutIndex
        guard i >= 0 else { return }
        let scale = ratio / model.doc.units.mm
        guard !ViewportLock.isLocked(model.doc, layoutIndex: i, viewport: v) else { model.editor.print("The viewport is locked (VPLOCK Off to unlock)."); return }
        model.editor.transaction("Viewport Scale") { d in
            guard d.layouts[i].viewports.indices.contains(v) else { return }
            var vp = d.layouts[i].viewports[v]
            let entries = SheetComposer.viewportEntries(doc: d, vp: vp)
            let b = entries.unionBounds
            let area = SheetComposer.drawingArea(d.layouts[i].paper)
            vp.scale = scale
            if !b.isEmpty {
                vp.size = Vec2(min(b.width / scale + 16, area.width), min(b.height / scale + 16, area.height))
                vp.origin = Vec2(min(vp.origin.x, area.max.x - vp.size.x), min(vp.origin.y, area.max.y - vp.size.y))
            }
            d.layouts[i].viewports[v] = vp
        }
    }

    private func addViewport(_ kind: ViewKind, scale ratio: Double) {
        let i = layoutIndex
        guard i >= 0 else { return }
        let doc = model.doc
        let scale = ratio / doc.units.mm
        var vp = Viewport(origin: .zero, size: Vec2(100, 80), viewCenter: .zero, scale: scale, view: kind,
                          level: kind == .plan || kind == .ceiling ? doc.currentLevel : nil)
        let b = SheetComposer.viewportEntries(doc: doc, vp: vp).unionBounds
        let area = SheetComposer.drawingArea(doc.layouts[i].paper)
        if !b.isEmpty {
            vp.viewCenter = b.center
            vp.size = Vec2(min(max(b.width / scale + 16, 40), area.width), min(max(b.height / scale + 16, 30), area.height))
        } else {
            vp.size = Vec2(min(160, area.width), min(110, area.height))
        }
        // Flow placement: to the right of existing viewports, then wrap below.
        let existing = doc.layouts[i].viewports
        var x = area.min.x, y = area.max.y - vp.size.y
        if let last = existing.last {
            x = last.origin.x + last.size.x + 12
            y = last.origin.y + last.size.y - vp.size.y
            if x + vp.size.x > area.max.x {
                x = area.min.x
                y = (existing.map { $0.origin.y }.min() ?? area.max.y) - 14 - vp.size.y
            }
        }
        vp.origin = Vec2(max(area.min.x, min(x, area.max.x - vp.size.x)), max(area.min.y, min(y, area.max.y - vp.size.y)))
        model.editor.transaction("Add Viewport") { $0.layouts[i].viewports.append(vp) }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (layout?.name ?? "Sheet") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Plotter.exportPDF(model: model, to: url, layoutIndex: layoutIndex) }
        catch { NSAlert(error: error).runModal() }
    }
}

// MARK: - Canvas

private struct SheetCanvas: NSViewRepresentable {
    let model: AppModel
    let layoutIndex: Int
    let revision: Int
    func makeNSView(context: Context) -> SheetCanvasNSView {
        let v = SheetCanvasNSView()
        v.model = model
        v.layoutIndex = layoutIndex
        return v
    }
    func updateNSView(_ v: SheetCanvasNSView, context: Context) {
        v.model = model
        if v.layoutIndex != layoutIndex { v.layoutIndex = layoutIndex; v.needsFit = true; v.selectedViewport = nil }
        v.needsDisplay = true
    }
}

final class SheetCanvasNSView: NSView {
    weak var model: AppModel?
    var layoutIndex = 0
    /// Device points per paper millimetre.
    var zoom: CGFloat = 1
    /// Device position of the paper's lower-left corner.
    var pan = CGPoint.zero
    var needsFit = true
    var selectedViewport: Int?
    private var cache: [String: [DrawEntry]] = [:]
    private var cacheStamp = -1
    private var dragStart: CGPoint?
    private var dragMode: DragMode = .none
    private var dragOffset = CGSize.zero
    private var lastPaperSize: Vec2?
    private enum DragMode { case none, pan, moveViewport(Int) }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var layout: ArchiCore.Layout? {
        guard let m = model, m.doc.layouts.indices.contains(layoutIndex) else { return nil }
        return m.doc.layouts[layoutIndex]
    }

    func fit() {
        guard let l = layout, bounds.width > 10, bounds.height > 10 else { return }
        zoom = max(0.05, min((bounds.width - 60) / l.paper.width, (bounds.height - 60) / l.paper.height))
        pan = CGPoint(x: (bounds.width - l.paper.width * zoom) / 2, y: (bounds.height - l.paper.height * zoom) / 2)
        needsFit = false
    }

    private var paperToDevice: CGAffineTransform {
        var t = CGAffineTransform(scaleX: zoom, y: zoom)
        t = t.concatenating(CGAffineTransform(translationX: pan.x, y: pan.y))
        return t
    }
    private func toPaper(_ p: CGPoint) -> Vec2 { Vec2((p.x - pan.x) / zoom, (p.y - pan.y) / zoom) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if needsFit { fit() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.165, blue: 0.18, alpha: 1))
        ctx.fill(bounds)
        guard let model, let l = layout else { return }
        let ps = Vec2(l.paper.width, l.paper.height)
        if needsFit || lastPaperSize != ps { fit(); lastPaperSize = ps }
        var doc = model.doc
        if let mp = movePreview, case .moveViewport(let i) = dragMode, doc.layouts[layoutIndex].viewports.indices.contains(i) {
            doc.layouts[layoutIndex].viewports[i].origin = mp
        }
        if cacheStamp != model.editor.changeCount { cache.removeAll(); cacheStamp = model.editor.changeCount }
        let paperRect = CGRect(x: pan.x, y: pan.y, width: l.paper.width * zoom, height: l.paper.height * zoom)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 18, color: CGColor(gray: 0, alpha: 0.6))
        ctx.setFillColor(.white)
        ctx.fill(paperRect)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.clip(to: paperRect)
        SheetComposer.draw(doc: doc, layoutIndex: layoutIndex, in: ctx, paperToDevice: paperToDevice, devicePerMM: zoom,
                           showViewportBorders: true, selectedViewport: selectedViewport,
                           entriesFor: { [unowned self] vp in
                               let key = "\(vp.view.rawValue)|\(vp.level ?? -999)|\(vp.scale)"
                               if let c = self.cache[key] { return c }
                               let e = SheetComposer.viewportEntries(doc: doc, vp: vp)
                               self.cache[key] = e
                               return e
                           }, visible: dirtyRect, setup: PageSetup.load(doc, layoutIndex: layoutIndex))
        ctx.restoreGState()
        // Lock badges on locked viewports.
        for i in ViewportLock.locked(doc, layoutIndex: layoutIndex) where l.viewports.indices.contains(i) {
            let v = l.viewports[i]
            let p = CGPoint(x: v.origin.x + v.size.x, y: v.origin.y + v.size.y).applying(paperToDevice)
            ("🔒" as NSString).draw(at: CGPoint(x: p.x - 18, y: p.y - 18), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        // Paper size label.
        let label = "\(l.paper.name)  \(fmt(l.paper.width, 0)) × \(fmt(l.paper.height, 0)) mm  ·  \(Int(zoom / Plotter.pointsPerMM * 100))%"
        (label as NSString).draw(at: CGPoint(x: paperRect.minX, y: paperRect.maxY + 6),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.7, alpha: 1)])
    }

    private func viewportIndex(at p: CGPoint) -> Int? {
        guard let l = layout else { return nil }
        let q = toPaper(p)
        return l.viewports.indices.last { i in
            let v = l.viewports[i]
            return BBox2(min: v.origin, max: v.origin + v.size).contains(q)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 { fit(); needsDisplay = true; return }
        dragStart = p
        if !event.modifierFlags.contains(.option), let i = viewportIndex(at: p), let l = layout {
            selectedViewport = i
            if let m = model, ViewportLock.isLocked(m.doc, layoutIndex: layoutIndex, viewport: i) {
                dragMode = .pan
                needsDisplay = true
                return
            }
            dragMode = .moveViewport(i)
            let o = l.viewports[i].origin
            dragOffset = CGSize(width: o.x, height: o.y)
        } else {
            selectedViewport = nil
            dragMode = .pan
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        switch dragMode {
        case .pan:
            pan.x += event.deltaX; pan.y -= event.deltaY
            needsDisplay = true
        case .moveViewport(let i):
            guard let s = dragStart, let model, model.doc.layouts.indices.contains(layoutIndex),
                  model.doc.layouts[layoutIndex].viewports.indices.contains(i) else { return }
            // Live move without recording undo; the final move is committed on mouse up.
            let d = Vec2((p.x - s.x) / zoom, (p.y - s.y) / zoom)
            movePreview = Vec2(dragOffset.width, dragOffset.height) + d
            needsDisplay = true
        case .none: break
        }
    }
    private var movePreview: Vec2?

    override func mouseUp(with event: NSEvent) {
        if case .moveViewport(let i) = dragMode, let mp = movePreview, let model {
            let li = layoutIndex
            model.editor.transaction("Move Viewport") { d in
                if d.layouts.indices.contains(li), d.layouts[li].viewports.indices.contains(i) { d.layouts[li].viewports[i].origin = mp }
            }
        }
        movePreview = nil
        dragMode = .none; dragStart = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), let i = selectedViewport, let model {
            let li = layoutIndex
            if ViewportLock.isLocked(model.doc, layoutIndex: li, viewport: i) { NSSound.beep(); model.editor.print("The viewport is locked."); return }
            model.editor.transaction("Remove Viewport") { d in
                if d.layouts[li].viewports.indices.contains(i) { d.layouts[li].viewports.remove(at: i); ViewportLock.removed(&d, layoutIndex: li, viewport: i) }
            }
            selectedViewport = nil
            return
        }
        if event.charactersIgnoringModifiers == "f" { fit(); needsDisplay = true; return }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            zoomAt(p, factor: pow(1.15, dy * 3))
        } else {
            pan.x += event.scrollingDeltaX
            pan.y -= event.scrollingDeltaY
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        zoomAt(convert(event.locationInWindow, from: nil), factor: 1 + event.magnification)
    }

    private func zoomAt(_ p: CGPoint, factor: CGFloat) {
        let q = toPaper(p)
        zoom = min(200, max(0.05, zoom * factor))
        pan = CGPoint(x: p.x - q.x * zoom, y: p.y - q.y * zoom)
        needsDisplay = true
    }
}
