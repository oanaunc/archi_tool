// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import PDFKit
import ArchiCore

// MARK: - Artwork: thumbnails and PDF pictures of a drawing (Finder icons, clipboard for other apps)

@MainActor
enum Artwork {
    /// Paper draw entries of a document, optionally only those of some objects.
    static func entries(_ doc: ArchiDocument, ids: Set<EntityID>? = nil, level: Int? = nil) -> [DrawEntry] {
        var o = DrawOptions(level: level)
        o.forPaper = true
        var d = doc
        if let ids { d.entities = d.entities.filter { ids.contains($0.id) } }
        let all = DrawListBuilder.entries(doc: d, options: o)
        guard let ids else { return all }
        return all.filter { $0.id.map(ids.contains) ?? false }
    }

    /// Square bitmap of the drawing on white, fitted with a 5 % margin (nil for an invalid size).
    static func thumbnail(_ doc: ArchiDocument, size: Int = 512, level: Int? = nil, ids: Set<EntityID>? = nil) -> CGImage? {
        guard size >= 16, size <= 4096,
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let side = CGFloat(size)
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let ents = entries(doc, ids: ids, level: level)
        let b = ents.unionBounds
        if !b.isEmpty, max(b.width, b.height) > 1e-12 {
            let s = side * 0.9 / CGFloat(max(b.width, b.height))
            let t = CGAffineTransform(translationX: -b.center.x, y: -b.center.y)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: side / 2, y: side / 2))
            let r = PlotRenderer(transform: t, devicePerMM: side / 400, paper: true, minLineWidth: max(1, side / 256))
            r.draw(ents, in: ctx)
        }
        return ctx.makeImage()
    }

    static func png(_ img: CGImage) -> Data? { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) }

    /// Vector PDF of the objects at the largest standard scale that fits 280 mm (small pieces at 1:1). Returns the ratio 1:n.
    static func pdf(_ doc: ArchiDocument, ids: Set<EntityID>? = nil, level: Int? = nil) -> (data: Data, ratio: Double)? {
        let ents = entries(doc, ids: ids, level: level)
        let b = ents.unionBounds
        guard !b.isEmpty else { return nil }
        let mm = doc.units.mm
        let needed = max(b.width, b.height) * mm / 280
        let ratio = Plotter.standardRatios.first { $0 >= needed } ?? ceil(needed / 1000) * 1000
        let perUnit = Plotter.pointsPerMM * CGFloat(mm / ratio)
        let margin: CGFloat = 12
        var box = CGRect(x: 0, y: 0, width: CGFloat(b.width) * perUnit + 2 * margin, height: CGFloat(b.height) * perUnit + 2 * margin)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        let t = CGAffineTransform(translationX: -b.min.x, y: -b.min.y)
            .concatenating(CGAffineTransform(scaleX: perUnit, y: perUnit))
            .concatenating(CGAffineTransform(translationX: margin, y: margin))
        PlotRenderer(transform: t, devicePerMM: Plotter.pointsPerMM, paper: true, minLineWidth: 0.12).draw(ents, in: ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return (data as Data, ratio)
    }
}

// MARK: - Clipboard interoperability (IO-064)

/// Copy: objects also go to the pasteboard as a vector PDF and a PNG so other apps (Mail, Pages, Keynote, Preview)
/// paste a picture. Paste: content other apps put on the clipboard (SVG, PDF, images, DXF text, plain text, copied
/// Finder files) is imported through the core `ExternalContent`.
@MainActor
enum ExternalPaste {
    static let maxPictureObjects = 20_000
    static let svgType = NSPasteboard.PasteboardType("public.svg-image")
    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    static let dxfType = NSPasteboard.PasteboardType("com.autodesk.dxf")
    static let heicType = NSPasteboard.PasteboardType("public.heic")

    /// Adds PDF/PNG pictures of copied objects (from the drawing that holds them).
    static func addPictures(_ clip: DraftClipboard, to pb: NSPasteboard, source: ArchiDocument? = nil) {
        guard !clip.isEmpty, clip.entities.count + clip.elements.count <= maxPictureObjects else { return }
        let ids = Set(clip.entities.map(\.id) + clip.elements.map(\.id))
        let doc = source ?? AppModel.all.sorted { ($0.window?.isKeyWindow ?? false) && !($1.window?.isKeyWindow ?? false) }
            .first { m in ids.contains { m.doc.entity($0) != nil || m.doc.element($0) != nil } }?.doc
        guard let doc, let pdf = Artwork.pdf(doc, ids: ids, level: nil) else { return }
        pb.setData(pdf.data, forType: .pdf)
        if let img = Artwork.thumbnail(doc, size: 1024, ids: ids), let png = Artwork.png(img) { pb.setData(png, forType: .png) }
    }

    /// Files copied in the Finder.
    static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    /// Content from another app, most specific first (nil when the pasteboard holds Archi objects or nothing usable).
    static func content(_ pb: NSPasteboard) -> (data: Data, type: String)? {
        guard pb.data(forType: ClipboardPayload.type) == nil else { return nil }
        let types = pb.types ?? []
        if types.contains(svgType), let d = pb.data(forType: svgType), !d.isEmpty { return (d, "svg") }
        if types.contains(dxfType), let d = pb.data(forType: dxfType), !d.isEmpty { return (d, "dxf") }
        if types.contains(.pdf), let d = pb.data(forType: .pdf), !d.isEmpty { return (d, "pdf") }
        if types.contains(.png), let d = pb.data(forType: .png), !d.isEmpty { return (d, "png") }
        if types.contains(jpegType), let d = pb.data(forType: jpegType), !d.isEmpty { return (d, "jpeg") }
        for t in [NSPasteboard.PasteboardType.tiff, heicType] where types.contains(t) {
            // Other bitmap formats are converted to PNG (read everywhere).
            if let d = pb.data(forType: t), let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) { return (png, "png") }
        }
        if let s = pb.string(forType: .string) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if (try? JSONDecoder().decode(ClipboardPayload.self, from: Data(t.utf8))) != nil { return nil }
            if t.hasPrefix("<svg") || (t.hasPrefix("<?xml") && t.contains("<svg")) { return (Data(t.utf8), "svg") }
            return (Data(t.utf8), "text")
        }
        return nil
    }

    /// Cheap check (types only, no conversion) used by menu validation.
    static func hasContent(_ pb: NSPasteboard) -> Bool {
        let types = pb.types ?? []
        guard !types.contains(ClipboardPayload.type) else { return false }
        if types.contains(.fileURL) { return !fileURLs(pb).isEmpty }
        if !Set(types).isDisjoint(with: [svgType, dxfType, .pdf, .png, jpegType, .tiff, heicType]) { return true }
        return content(pb) != nil
    }

    /// Where pasted pictures are kept: "<drawing> assets" next to a saved drawing, else Application Support.
    static func assetFolder(_ fileURL: URL?) -> URL {
        if let u = fileURL {
            return u.deletingLastPathComponent().appendingPathComponent(u.deletingPathExtension().lastPathComponent + " assets", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Oanarina Archi Tool/Pasted", isDirectory: true)
    }

    /// Pastes content from other apps at `p` as one undo step. Returns the new object ids (nil = nothing to paste).
    @discardableResult
    static func paste(_ pb: NSPasteboard, into model: AppModel, at p: Vec2) -> [EntityID]? {
        let files = fileURLs(pb)
        if !files.isEmpty { return FileDrop.perform(files, at: p, model: model) }
        guard let c = content(pb) else { return nil }
        var r: ExternalContent.Result?
        do {
            try model.editor.transaction("Paste \(c.type.uppercased())") { d in
                r = try ExternalContent.insert(c.data, type: c.type, into: &d, at: p, assetFolder: assetFolder(model.editor.fileURL), name: "Pasted")
            }
        } catch {
            model.editor.print("Cannot paste: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            return []
        }
        guard let r else { return [] }
        model.editor.selection = Set(r.ids)
        model.editor.print("Pasted \(r.summary).")
        model.showStart = false
        return r.ids
    }
}

// MARK: - Drag and drop of files (IO-065)

/// Files dropped on the plan, the 3D view or copied in the Finder: drawings open, scripts run, images and PDFs are
/// attached, exchange formats (DXF, SVG, IFC, OBJ, STL, 3MF, GeoJSON, points …) are imported at the drop point.
@MainActor
enum FileDrop {
    static func urls(_ pb: NSPasteboard) -> [URL] { ExternalPaste.fileURLs(pb) }
    static func accepts(_ urls: [URL]) -> Bool { urls.contains { ExternalContent.dropAction(for: $0) != .unsupported } }

    @discardableResult
    static func perform(_ urls: [URL], at p: Vec2, model: AppModel) -> [EntityID] {
        var rest: [URL] = []
        for u in urls {
            switch ExternalContent.dropAction(for: u) {
            case .open: model.files.openURL(u)
            case .runScript: model.runScriptFile(u)
            case .unsupported: model.editor.print("\(u.lastPathComponent): not a file type Archi Tool can import.")
            default: rest.append(u)
            }
        }
        guard !rest.isEmpty else { return [] }
        var res: [(url: URL, result: ExternalContent.Result?, error: String?)] = []
        model.editor.transaction(rest.count == 1 ? "Drop \(rest[0].lastPathComponent)" : "Drop \(rest.count) files") { d in
            res = ExternalContent.drop(rest, into: &d, at: p)
        }
        let ids = res.flatMap { $0.result?.ids ?? [] }
        if !ids.isEmpty { model.editor.selection = Set(ids) }
        for x in res { model.editor.print("\(x.url.lastPathComponent): " + (x.result?.summary ?? x.error ?? "")) }
        model.showStart = false
        return ids
    }
}

// MARK: - Spotlight metadata, Finder thumbnails and macOS Versions (IO-007, IO-006, IO-002)

/// Spotlight indexes `com.apple.metadata:` extended attributes (binary property lists), so a saved drawing is
/// found by its title, layers, text, rooms, author and client without a separate importer plug-in.
enum SpotlightXattr {
    static let prefix = "com.apple.metadata:"
    static let maxText = 256 * 1024

    /// Writes the attributes that are property-list values; returns how many were written.
    @discardableResult
    static func write(_ attrs: [String: Any], to url: URL) -> Int {
        var n = 0
        for (k, v0) in attrs {
            var v = v0
            if let s = v as? String, s.utf8.count > maxText { v = String(s.prefix(maxText / 4)) }
            guard PropertyListSerialization.propertyList(v, isValidFor: .binary),
                  let data = try? PropertyListSerialization.data(fromPropertyList: v, format: .binary, options: 0) else { continue }
            let ok = data.withUnsafeBytes { raw in setxattr(url.path, prefix + k, raw.baseAddress, data.count, 0, 0) } == 0
            if ok { n += 1 }
        }
        return n
    }

    static func read(_ key: String, from url: URL) -> Any? {
        let name = prefix + key
        let len = getxattr(url.path, name, nil, 0, 0, 0)
        guard len > 0 else { return nil }
        var data = Data(count: len)
        let r = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, len, 0, 0) }
        guard r == len else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}

/// Things done after every save of an .archi file.
@MainActor
enum SaveExtras {
    static let finderPreviewKey = "finderPreviewIcons", versionsKey = "fileVersionsOnSave"
    static var finderPreview: Bool {
        get { UserDefaults.standard.object(forKey: finderPreviewKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: finderPreviewKey) }
    }
    static var versions: Bool {
        get { UserDefaults.standard.object(forKey: versionsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: versionsKey) }
    }

    /// Finder icon showing the plan (the file's thumbnail in Finder, Open panels and Quick Look's icon view).
    @discardableResult
    static func setFinderIcon(_ doc: ArchiDocument, url: URL, level: Int?) -> Bool {
        guard let img = Artwork.thumbnail(doc, size: 512, level: level) else { return false }
        let ns = NSImage(cgImage: img, size: NSSize(width: 512, height: 512))
        return NSWorkspace.shared.setIcon(ns, forFile: url.path, options: [])
    }

    /// Spotlight attributes, Finder preview icon and a macOS version of the saved file.
    static func afterSave(_ doc: ArchiDocument, url: URL, level: Int?) {
        SpotlightXattr.write(SpotlightMetadata.attributes(doc), to: url)
        if versions { FileVersions.add(url) }
        if finderPreview { setFinderIcon(doc, url: url, level: level) }
    }
}

/// macOS document Versions (the same store as "Browse All Versions…" in Apple apps): every save adds a version,
/// older ones can be listed, opened as a copy or restored.
@MainActor
enum FileVersions {
    static let keepKey = "fileVersionsKeep"
    static var keep: Int {
        get { max(1, UserDefaults.standard.object(forKey: keepKey) as? Int ?? 50) }
        set { UserDefaults.standard.set(max(1, min(1000, newValue)), forKey: keepKey) }
    }

    /// Saved versions of a file, newest first.
    static func list(_ url: URL) -> [NSFileVersion] {
        (NSFileVersion.otherVersionsOfItem(at: url) ?? []).sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    /// Indices (newest-first order) of versions to discard to keep at most `keep`.
    static func pruneIndices(count: Int, keep: Int) -> [Int] { count > keep ? Array(max(0, keep)..<count) : [] }

    @discardableResult
    static func add(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do { _ = try NSFileVersion.addOfItem(at: url, withContentsOf: url, options: []) } catch { return false }
        let vs = list(url)
        for i in pruneIndices(count: vs.count, keep: keep) { try? vs[i].remove() }
        return true
    }

    static func label(_ v: NSFileVersion) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium
        return (v.modificationDate.map { f.string(from: $0) } ?? "Unknown date") + (v.localizedNameOfSavingComputer.map { " — \($0)" } ?? "")
    }

    /// A copy of a version in the temporary folder (opened in its own window, never overwriting the store).
    static func copy(_ v: NSFileVersion, of url: URL) throws -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiVersions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " (" + f.string(from: v.modificationDate ?? Date()) + ")." + url.pathExtension)
        if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
        try FileManager.default.copyItem(at: v.url, to: dst)
        return dst
    }

    /// Replaces the file with a version (the current state is kept as a version first) and reloads the window.
    static func restore(_ v: NSFileVersion, url: URL, model: AppModel?) throws {
        add(url)
        _ = try v.replaceItem(at: url, options: [])
        if let model { _ = model.files.load(url) }
    }
}

/// Window listing the versions of the front drawing.
@MainActor
enum VersionsWindow {
    private static var panel: NSPanel?
    static func show(model: AppModel, url: URL) {
        panel?.close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Versions — \(url.lastPathComponent)"
        p.isReleasedWhenClosed = false
        p.appearance = Theme.appearance
        p.contentViewController = NSHostingController(rootView: VersionsBrowser(model: model, url: url).preferredColorScheme(Theme.colorScheme))
        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

struct VersionsBrowser: View {
    let model: AppModel
    let url: URL
    @State private var versions: [NSFileVersion] = []
    @State private var selection: Int?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Each save keeps a version (up to \(FileVersions.keep)). Open a copy to compare, or restore it.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
            List(selection: $selection) {
                ForEach(Array(versions.enumerated()), id: \.offset) { i, v in
                    Text(FileVersions.label(v)).tag(i).accessibilityLabel("Version \(i + 1), \(FileVersions.label(v))")
                }
            }
            .frame(minHeight: 240)
            HStack {
                Button("Open Copy") { if let i = selection, versions.indices.contains(i) { openCopy(versions[i]) } }.disabled(selection == nil)
                Button("Restore…") { if let i = selection, versions.indices.contains(i) { restore(versions[i]) } }.disabled(selection == nil)
                Spacer()
                Button("Save Version Now") { message = FileVersions.add(url) ? "Version saved." : "Versions are not available on this volume."; reload() }
            }
            if !message.isEmpty { Text(message).font(Theme.fontSmall).foregroundStyle(Theme.textDim) }
        }
        .padding(12)
        .onAppear(perform: reload)
    }

    private func reload() { versions = FileVersions.list(url) }
    private func openCopy(_ v: NSFileVersion) {
        do { let u = try FileVersions.copy(v, of: url); WindowRouter.open(DocumentRequest(kind: .open, path: u.path)) }
        catch { message = error.localizedDescription }
    }
    private func restore(_ v: NSFileVersion) {
        let a = NSAlert()
        a.messageText = "Restore the version of \(FileVersions.label(v))?"
        a.informativeText = model.isDirty ? "Unsaved changes in the window are lost; the saved file is kept as a version." : "The current file is kept as a version."
        a.addButton(withTitle: "Restore"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try FileVersions.restore(v, url: url, model: model); message = "Restored."; reload() }
        catch { message = error.localizedDescription }
    }
}
