// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import SwiftUI
import UniformTypeIdentifiers
import ArchiCore

/// What a new window should show.
struct DocumentRequest: Codable, Hashable {
    enum Kind: String, Codable { case start, blankMetric, blankImperial, building, open, sample }
    var kind: Kind
    var path: String?
    var nonce = UUID()
    init(kind: Kind, path: String? = nil) { self.kind = kind; self.path = path }
}

/// Opens document windows from anywhere (menus, host actions, Finder).
@MainActor
enum WindowRouter {
    static var openWindow: ((DocumentRequest) -> Void)?
    /// Files the app was asked to open before a window was ready.
    static var pendingURLs: [URL] = []
    static func open(_ r: DocumentRequest) {
        if let o = openWindow { o(r) } else if let p = r.path { pendingURLs.append(URL(fileURLWithPath: p)) }
    }
    static func openFile(_ url: URL) {
        if let m = AppModel.all.first(where: { $0.isEmptyDocument && !$0.isDirty && $0.editor.fileURL == nil }) {
            if m.files.load(url) { m.window?.makeKeyAndOrderFront(nil); return }
        }
        open(DocumentRequest(kind: .open, path: url.path))
    }
}

/// Recently opened/saved documents (most recent first).
enum RecentFiles {
    private static let key = "RecentDocuments"
    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func add(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        let limit = MainActor.assumeIsolated { AppPreferences.shared.recentLimit }
        UserDefaults.standard.set(Array(list.prefix(max(1, limit))), forKey: key)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    static func remove(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.path }
        UserDefaults.standard.set(list, forKey: key)
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSDocumentController.shared.clearRecentDocuments(nil)
    }
}

enum ExportFormat {
    static let all: [(ext: String, title: String, symbol: String)] = [
        ("pdf", "PDF", "doc.richtext"), ("dxf", "DXF", "doc.text"), ("svg", "SVG", "photo"), ("png", "PNG (300 dpi)", "photo.artframe"),
        ("obj", "OBJ + MTL", "cube"), ("stl", "STL", "cube.transparent"), ("glb", "glTF Binary (GLB)", "shippingbox"), ("ifc", "IFC4", "building.columns"),
    ]
}

extension UTType {
    static let archiDocument = UTType(filenameExtension: "archi") ?? .json
    static let dxfDrawing = UTType(filenameExtension: "dxf") ?? .data
}

struct ExportError: LocalizedError { var errorDescription: String? }

/// Keeps SwiftUI's window delegate while adding "save changes?" on close.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    /// Strong: SwiftUI's own delegate must stay alive while we stand in for it.
    var original: NSWindowDelegate?
    weak var model: AppModel?
    init(original: NSWindowDelegate?, model: AppModel) { self.original = original; self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let ok = MainActor.assumeIsolated { () -> Bool in
            guard let m = self.model else { return true }
            return m.files.confirmClose()
        }
        if !ok { return false }
        return original?.windowShouldClose?(sender) ?? true
    }
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { self.model?.autosave?.stop() }
        original?.windowWillClose?(notification)
    }
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let o = original, o.responds(to: aSelector) { return o }
        return super.forwardingTarget(for: aSelector)
    }
}

/// File dialogs, document I/O and the EditorHost implementation for one window.
@MainActor
final class FileController: EditorHost {
    private weak var model: AppModel?
    private var closeGuard: WindowCloseGuard?

    init(model: AppModel) { self.model = model }

    nonisolated func perform(_ action: HostAction, editor: Editor) {
        MainActor.assumeIsolated { self.handle(action) }
    }

    func handle(_ action: HostAction) {
        guard let model else { return }
        switch action {
        case .zoomExtents: model.zoomExtents()
        case .zoomWindow(let b): model.mode = model.mode == .model ? .plan : model.mode; model.canvas?.zoom(to: b)
        case .zoomScale(let f): model.canvas?.zoomBy(CGFloat(f))
        case .pan(let v): model.canvas?.panWorld(v)
        case .regen: model.canvas?.invalidateCache(); model.pendingHostAction = action; model.revision &+= 1
        case .show2D: model.mode = .plan
        case .show3D: model.mode = .model
        case .showSplit: model.mode = .split
        case .render: RenderController.renderImage(model: model)
        case .walkthrough:
            model.walkMode = true
            if model.mode == .plan || model.mode == .sheet { model.mode = .model }
            model.pendingHostAction = action
            model.revision &+= 1
        case .open(let p):
            if let p { openURL(URL(fileURLWithPath: p)) } else { openPanel() }
        case .save(let p):
            if let p { _ = write(to: URL(fileURLWithPath: p)) } else { _ = save() }
        case .saveAs(let p):
            if let p { _ = write(to: URL(fileURLWithPath: p)) } else { _ = saveAs() }
        case .newDocument: WindowRouter.open(DocumentRequest(kind: .start))
        case .export(let format, let path): export(format: format, path: path)
        case .plot(let path):
            if let path {
                do { try Plotter.exportPDF(model: model, to: URL(fileURLWithPath: path), layoutIndex: model.mode == .sheet ? model.activeLayout : nil)
                    model.editor.print("Plotted to \(path)") } catch { showError(error) }
            } else { Plotter.printDrawing(model: model) }
        case .importFile(let p):
            if let p { importFile(URL(fileURLWithPath: p)) } else { importPanel() }
        case .showPanel(let name): showPanel(name)
        case .setViewStyle(let s):
            model.viewStyle = s
            model.pendingHostAction = action
            model.revision &+= 1
        case .setView("zoomPrevious"):
            model.canvas?.zoomPrevious()
        case .setView(let v) where v.hasPrefix("layout:"):
            let name = String(v.dropFirst("layout:".count))
            if let i = model.doc.layouts.firstIndex(where: { $0.name == name }) { model.activeLayout = i; model.mode = .sheet }
            model.revision &+= 1
        case .setView("model") where model.mode == .sheet:
            model.mode = .plan
            model.revision &+= 1
        case .setView(let v):
            model.viewDirection = v
            if model.mode == .plan && v.lowercased() != "top" && v.lowercased() != "plan" { model.mode = .model }
            model.pendingHostAction = action
            model.revision &+= 1
        case .message(let m): message(m)
        }
    }

    func showPanel(_ name: String) {
        guard let model else { return }
        switch name.lowercased() {
        case "layers", "layer": model.showPanels = true; model.panelTab = .layers
        case "properties", "props", "property": model.showPanels = true; model.panelTab = .properties
        case "levels", "level": model.showPanels = true; model.panelTab = .levels
        case "browser", "project", "projectbrowser": model.showPanels = true; model.panelTab = .browser
        case "materials", "material": model.showPanels = true; model.panelTab = .materials
        case "console", "script", "js", "javascript": model.showScriptConsole = true
        case "commands", "help": model.sheet = .commandReference
        case "units": model.sheet = .units
        case "drafting", "dsettings", "settings": model.sheet = .drafting
        case "schedule", "schedules": model.sheet = .schedule("all")
        case "viewcube", "navvcube", "cube":
            model.showViewCube.toggle()
            if model.showViewCube && (model.mode == .plan || model.mode == .sheet) { model.mode = .model }
        case "history", "undohistory": model.showPanels = true; model.panelTab = .history
        case "tools", "toolpalettes", "palettes": model.showPanels = true; model.panelTab = .tools
        case "options", "preferences": PreferencesWindow.show()
        case "quickselect", "qselect": model.sheet = .quickSelect
        case "layerstates", "layerstate": model.sheet = .layerStates
        case "pagesetup": model.sheet = .pageSetup(model.mode == .sheet ? model.activeLayout : -1)
        case "preview", "plotpreview": PlotPreviewWindow.show(model: model)
        case "sectionbox": model.showSectionBoxPanel = true
        case "sunstudy", "sun": model.showSunStudy = true
        case "commandsearch", "search": model.showCommandSearch = true
        default: model.showPanels = true
        }
    }

    // MARK: Alerts

    func message(_ text: String) {
        switch text {
        case "quit": NSApp.terminate(nil); return
        case "close": model?.window?.performClose(nil); return
        default: break
        }
        let a = NSAlert()
        a.messageText = "Oanarina Archi Tool"
        a.informativeText = text
        a.addButton(withTitle: "OK")
        if let w = model?.window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    func showError(_ error: Error) {
        let a = NSAlert(error: error)
        a.alertStyle = .warning
        if let w = model?.window { a.beginSheetModal(for: w) } else { a.runModal() }
        model?.editor.print("Error: \(error.localizedDescription)")
    }

    // MARK: Window close guard

    func installCloseGuard(on window: NSWindow) {
        guard let model else { return }
        if let g = closeGuard, window.delegate === g { return }
        let g = WindowCloseGuard(original: window.delegate, model: model)
        closeGuard = g
        window.delegate = g
    }

    /// Asks to save a modified document. Returns false if the user cancelled.
    func confirmClose() -> Bool {
        guard let model, model.isDirty else { return true }
        let a = NSAlert()
        a.messageText = "Do you want to save the changes made to “\(model.displayName)”?"
        a.informativeText = "Your changes will be lost if you don’t save them."
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        let dont = a.addButton(withTitle: "Don’t Save")
        dont.hasDestructiveAction = true
        switch a.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    // MARK: Open

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.archiDocument, .dxfDrawing]
        p.allowsMultipleSelection = true
        p.message = "Open an Oanarina Archi project (.archi) or a DXF drawing"
        guard p.runModal() == .OK else { return }
        for url in p.urls { openURL(url) }
    }

    /// Opens in this window when it is empty, otherwise in a new window.
    func openURL(_ url: URL) {
        guard let model else { return }
        if model.isEmptyDocument && !model.isDirty && model.editor.fileURL == nil { _ = load(url) }
        else { WindowRouter.open(DocumentRequest(kind: .open, path: url.path)) }
    }

    static func readDocument(_ url: URL) throws -> ArchiDocument {
        if url.pathExtension.lowercased() == "dxf" {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
            return try DXFReader.read(text)
        }
        return try ArchiFile.decode(try Data(contentsOf: url))
    }

    @discardableResult
    func load(_ url: URL) -> Bool {
        guard let model else { return false }
        do {
            let d = try FileController.readDocument(url)
            model.editor.replaceDocument(d, url: url)
            model.showStart = false
            model.mode = .plan
            RecentFiles.add(url)
            model.editor.print("Opened \(url.lastPathComponent) — \(d.entities.count) objects, \(d.elements.count) building elements.")
            model.revision &+= 1
            model.zoomExtents()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: Save

    @discardableResult
    func save() -> Bool {
        guard let model else { return false }
        if let url = model.editor.fileURL, url.pathExtension.lowercased() == ArchiFile.fileExtension { return write(to: url) }
        return saveAs()
    }

    @discardableResult
    func saveAs() -> Bool {
        guard let model else { return false }
        let p = NSSavePanel()
        p.allowedContentTypes = [.archiDocument]
        p.nameFieldStringValue = model.displayName + "." + ArchiFile.fileExtension
        if let dir = model.editor.fileURL?.deletingLastPathComponent() { p.directoryURL = dir }
        else if let orig = model.recoveredOriginalPath {
            let u = URL(fileURLWithPath: orig)
            p.directoryURL = u.deletingLastPathComponent()
            p.nameFieldStringValue = u.deletingPathExtension().lastPathComponent + " (recovered)." + ArchiFile.fileExtension
        }
        guard p.runModal() == .OK, let url = p.url else { return false }
        return write(to: url)
    }

    func write(to url: URL) -> Bool {
        guard let model else { return false }
        var u = url
        if u.pathExtension.lowercased() == "dxf" {
            do { try DXFWriter.write(model.doc).write(to: u, atomically: true, encoding: .utf8); model.editor.print("Saved DXF \(u.lastPathComponent)"); return true }
            catch { showError(error); return false }
        }
        if u.pathExtension.lowercased() != ArchiFile.fileExtension { u = u.appendingPathExtension(ArchiFile.fileExtension) }
        do {
            let data = try ArchiFile.encode(model.doc)
            try data.write(to: u, options: .atomic)
            model.editor.fileURL = u
            model.editor.isDirty = false
            model.autosave?.discard()
            model.recoveredOriginalPath = nil
            RecentFiles.add(u)
            model.editor.print("Saved \(u.lastPathComponent)")
            model.revision &+= 1
            return true
        } catch {
            showError(error)
            return false
        }
    }

    // MARK: Import

    func importPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.dxfDrawing, .archiDocument] + FileImport.importFormats.compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = false
        p.message = "Import a drawing, model or data file (DXF, Archi, IFC, SVG, OBJ, STL, 3MF, GeoJSON, CSV/XYZ points) into the current document"
        guard p.runModal() == .OK, let url = p.url else { return }
        importFile(url)
    }

    /// Merges another drawing into this one (new ids, missing layers/blocks/linetypes added).
    func importFile(_ url: URL) {
        guard let model else { return }
        let ext = url.pathExtension.lowercased()
        if ext != "archi" && ext != "dxf" && FileImport.importFormats.contains(ext) {
            // IFC, SVG, OBJ, STL, 3MF, GeoJSON and point tables go through the core importers (units are scaled).
            do {
                var result = DocumentMerge.Result(), summary = ""
                try model.editor.transaction("Import \(url.lastPathComponent)") { d in
                    (result, summary) = try FileImport.importFile(url, into: &d)
                }
                model.editor.selection = Set(result.allIDs)
                model.editor.print("Imported \(result.allIDs.count) object(s) from \(url.lastPathComponent). \(summary)")
                model.showStart = false
                model.zoomExtents()
            } catch { showError(error) }
            return
        }
        do {
            let src = try FileController.readDocument(url)
            var newIDs: [EntityID] = []
            model.editor.transaction("Import \(url.lastPathComponent)") { d in
                for l in src.layers where d.layer(named: l.name) == nil { d.layers.append(l) }
                for lt in src.linetypes where d.linetype(lt.name) == nil { d.linetypes.append(lt) }
                for (n, b) in src.blocks where d.blocks[n] == nil { d.blocks[n] = b }
                for s in src.textStyles where !d.textStyles.contains(where: { $0.name == s.name }) { d.textStyles.append(s) }
                for s in src.dimStyles where !d.dimStyles.contains(where: { $0.name == s.name }) { d.dimStyles.append(s) }
                for m in src.materials where d.material(m.name) == nil { d.materials.append(m) }
                var map: [EntityID: EntityID] = [:]
                for e in src.entities { let nid = d.add(e); map[e.id] = nid; newIDs.append(nid) }
                let ordered = src.elements.filter { if case .opening = $0.geometry { return false }; return true } +
                    src.elements.filter { if case .opening = $0.geometry { return true }; return false }
                for el in ordered {
                    var n = el
                    if case .opening(var o) = n.geometry {
                        guard let h = map[o.hostWall] else { continue }
                        o.hostWall = h
                        n.geometry = .opening(o)
                    }
                    n.id = d.allocateID()
                    map[el.id] = n.id
                    if d.level(n.level) == nil { n.level = d.currentLevel }
                    d.ensureLayer(n.layer)
                    d.elements.append(n)
                    newIDs.append(n.id)
                }
            }
            model.editor.selection = Set(newIDs)
            model.editor.print("Imported \(newIDs.count) object(s) from \(url.lastPathComponent).")
            model.showStart = false
            model.zoomExtents()
        } catch {
            showError(error)
        }
    }

    // MARK: Export

    func exportPanel(ext: String, suggested: String) -> URL? {
        let p = NSSavePanel()
        if let t = UTType(filenameExtension: ext) { p.allowedContentTypes = [t] }
        p.nameFieldStringValue = suggested + "." + ext
        p.canCreateDirectories = true
        if let dir = model?.editor.fileURL?.deletingLastPathComponent() { p.directoryURL = dir }
        guard p.runModal() == .OK else { return nil }
        return p.url
    }

    /// Renders the whole window (including the 3D viewport) to a PNG — used for documentation and the website.
    func snapshotWindow(to url: URL) throws {
        guard let view = model?.window?.contentView?.superview ?? model?.window?.contentView else { throw ExportError(errorDescription: "No window.") }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ExportError(errorDescription: "Cannot capture the window.") }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        // SceneKit views are Metal-backed and are not captured by cacheDisplay: draw their snapshots on top.
        func scnViews(_ v: NSView) -> [SCNView] { (v as? SCNView).map { [$0] } ?? v.subviews.flatMap(scnViews) }
        let final = NSImage(size: view.bounds.size, flipped: false) { _ in
            img.draw(in: view.bounds)
            for sv in scnViews(view) where !sv.isHiddenOrHasHiddenAncestor {
                let r = sv.convert(sv.bounds, to: view)
                sv.snapshot().draw(in: r)
            }
            return true
        }
        guard let tiff = final.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { throw ExportError(errorDescription: "Cannot encode PNG.") }
        try png.write(to: url, options: .atomic)
    }

    func export(format: String, path: String?) {
        guard let model else { return }
        var f = format.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var kind = "all"
        if f.hasPrefix("csv") {
            let rest = f.dropFirst(3).trimmingCharacters(in: CharacterSet(charactersIn: ":-_ "))
            if !rest.isEmpty { kind = rest }
            f = "csv"
        }
        if f == "window" || f == "screenshot" {
            let url = URL(fileURLWithPath: path ?? (NSHomeDirectory() + "/Desktop/Archi Tool window.png"))
            do { try snapshotWindow(to: url); model.editor.print("Window image saved to \(url.path)") } catch { showError(error) }
            return
        }
        if f == "gltf" { f = "glb" }
        if f == "jpeg" || f == "jpg" { f = "png" }
        let supported = ["pdf", "dxf", "svg", "png", "obj", "stl", "glb", "ifc", "csv", "archi"]
        guard supported.contains(f) else { model.editor.print("Unknown export format \"\(format)\". Use one of: \(supported.joined(separator: ", "))."); return }
        let suggested = model.displayName + (f == "csv" ? "-\(kind)" : "")
        guard let url = path.map({ URL(fileURLWithPath: $0) }) ?? exportPanel(ext: f, suggested: suggested) else { return }
        let doc = model.doc
        do {
            switch f {
            case "archi":
                try ArchiFile.encode(doc).write(to: url, options: .atomic)
            case "pdf":
                try Plotter.exportPDF(model: model, to: url, layoutIndex: model.mode == .sheet ? model.activeLayout : nil)
            case "dxf":
                try DXFWriter.write(doc).write(to: url, atomically: true, encoding: .utf8)
            case "svg":
                var opts = DrawOptions(level: doc.currentLevel)
                opts.forPaper = true
                let entries = DrawListBuilder.entries(doc: doc, options: opts)
                var b = BBox2.empty
                for e in entries { b.add(e.bounds) }
                guard !b.isEmpty else { throw ExportError(errorDescription: "The drawing is empty.") }
                let m = max(b.width, b.height) * 0.03
                b = b.expanded(by: m)
                let ppu = 1600 / max(max(b.width, b.height), 1e-9)
                try SVGExporter.export(entries: entries, bounds: b, background: .white, pixelsPerUnit: ppu).write(to: url, atomically: true, encoding: .utf8)
            case "png":
                try renderPNG(to: url)
            case "obj":
                let (obj, mtl) = OBJExporter.export(meshes(), materials: doc.materials)
                let mtlURL = url.deletingPathExtension().appendingPathExtension("mtl")
                var o = obj
                if !o.contains("mtllib") { o = "mtllib \(mtlURL.lastPathComponent)\n" + o }
                try o.write(to: url, atomically: true, encoding: .utf8)
                try mtl.write(to: mtlURL, atomically: true, encoding: .utf8)
            case "stl":
                try STLExporter.export(meshes(), name: model.displayName).write(to: url, atomically: true, encoding: .utf8)
            case "glb":
                try GLTFExporter.exportGLB(meshes(), materials: doc.materials).write(to: url, options: .atomic)
            case "ifc":
                try IFCExporter.export(doc: doc, meshes: meshes()).write(to: url, atomically: true, encoding: .utf8)
            case "csv":
                try ScheduleExporter.csv(doc: doc, kind: kind).write(to: url, atomically: true, encoding: .utf8)
            default: break
            }
            model.editor.print("Exported \(f.uppercased()) to \(url.path)")
        } catch {
            showError(error)
        }
    }

    private func meshes() -> [MeshGroup] {
        guard let model else { return [] }
        let m = MeshBuilder.build(doc: model.doc)
        if m.isEmpty { model.editor.print("Note: the model has no 3D content (walls, slabs, solids…).") }
        return m
    }

    /// Renders the current level at 300 dpi (1:100 for millimetre drawings) on white paper.
    func renderPNG(to url: URL) throws {
        guard let model else { return }
        let doc = model.doc
        var opts = DrawOptions(level: doc.currentLevel)
        opts.forPaper = true
        let scene = RenderScene(DrawListBuilder.entries(doc: doc, options: opts))
        guard !scene.bounds.isNull, scene.bounds.width.isFinite else { throw ExportError(errorDescription: "The drawing is empty.") }
        let b = scene.bounds.insetBy(dx: -max(scene.bounds.width, scene.bounds.height) * 0.03, dy: -max(scene.bounds.width, scene.bounds.height) * 0.03)
        let extent = max(b.width, b.height, 1e-9)
        let paperMM = extent * CGFloat(doc.units.mm) / 100
        let longPx = min(9000, max(1600, paperMM / 25.4 * 300))
        let ppu = longPx / extent
        let w = max(1, Int((b.width * ppu).rounded(.up))), h = max(1, Int((b.height * ppu).rounded(.up)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gctx = NSGraphicsContext(bitmapImageRep: rep) else { throw ExportError(errorDescription: "Cannot create the image.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        let ctx = gctx.cgContext
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.scaleBy(x: ppu, y: ppu)
        ctx.translateBy(x: -b.midX, y: -b.midY)
        var prm = RenderParams()
        prm.lwScale = 300 / 25.4
        prm.minWidth = 1
        prm.maxWidth = 80
        scene.draw(in: ctx, visible: b, scale: ppu, params: prm)
        gctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: CGFloat(w) * 72 / 300, height: CGFloat(h) * 72 / 300)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw ExportError(errorDescription: "PNG encoding failed.") }
        try data.write(to: url, options: .atomic)
    }

    // MARK: Templates

    static func template(_ kind: DocumentRequest.Kind) -> (ArchiDocument, DraftSettings) {
        var d = ArchiDocument()
        var s = DraftSettings()
        switch kind {
        case .blankImperial:
            d.units = .inches
            d.setVariable("MEASUREMENT", "0")
            d.setVariable("LTSCALE", "0.04")
            d.dimStyles = [DimStyle(name: "Standard", textHeight: 0.18, arrowSize: 0.18, extensionOffset: 0.0625, extensionExtend: 0.18, textGap: 0.09, decimals: 2),
                           DimStyle(name: "Architectural 1/4\"", textHeight: 6, arrowSize: 4, arrow: .architecturalTick, extensionOffset: 2, extensionExtend: 4, textGap: 2)]
            d.levels = [Level(id: 0, name: "Ground Floor", elevation: 0, height: 108), Level(id: 1, name: "First Floor", elevation: 120, height: 108)]
            s.gridSpacing = 12
            s.textHeight = 6
            s.wallThickness = 8
            s.wallHeight = 108
            s.offsetDistance = 4
        case .building, .sample:
            d.info.name = kind == .sample ? "Sample House" : "New Building"
            d.levels = [Level(id: 0, name: "Level 0 — Ground", elevation: 0, height: 3000), Level(id: 1, name: "Level 1 — First", elevation: 3000, height: 3000),
                        Level(id: 2, name: "Roof", elevation: 6000, height: 3000)]
            d.currentDimStyle = "Architectural 1:100"
            d.currentLayer = "0"
            if kind == .building {
                let xs: [Double] = [0, 6000, 12000, 18000], ys: [Double] = [0, 6000, 12000]
                for (i, x) in xs.enumerated() { d.addElement(.gridLine(GridLineGeom(start: Vec2(x, -2000), end: Vec2(x, 14000), label: "\(i + 1)")), level: 0) }
                for (i, y) in ys.enumerated() { d.addElement(.gridLine(GridLineGeom(start: Vec2(-2000, y), end: Vec2(20000, y), label: String(UnicodeScalar(65 + i)!))), level: 0) }
            }
            d.layouts = d.levels.prefix(2).enumerated().map { i, l in
                Layout(name: "A10\(i + 1) — \(l.name)", paper: PaperSize.standard[1],
                       viewports: [Viewport(origin: Vec2(15, 15), size: Vec2(330, 267), viewCenter: Vec2(9000, 6000), scale: 100, view: .plan, level: l.id, title: l.name)],
                       titleBlock: ["project": d.info.name, "sheetNumber": "A10\(i + 1)", "scale": "1:100"])
            }
            d.layouts.append(Layout(name: "A201 — Elevations", paper: PaperSize.standard[1],
                                    viewports: [Viewport(origin: Vec2(15, 150), size: Vec2(330, 130), viewCenter: Vec2(9000, 3000), scale: 100, view: .elevationSouth, title: "South Elevation"),
                                                Viewport(origin: Vec2(15, 15), size: Vec2(330, 130), viewCenter: Vec2(9000, 3000), scale: 100, view: .elevationEast, title: "East Elevation")],
                                    titleBlock: ["project": d.info.name, "sheetNumber": "A201", "scale": "1:100"]))
        default: break
        }
        return (d, s)
    }
}
