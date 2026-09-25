// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

// MARK: - File locations (Settings ▸ General ▸ File locations)

enum FileLocations {
    static var appSupport: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Oanarina Archi Tool", isDirectory: true)
    }
    static var defaultTemplates: URL { appSupport.appendingPathComponent("Templates", isDirectory: true) }
    static var defaultScripts: URL { appSupport.appendingPathComponent("Scripts", isDirectory: true) }
    static var thumbnails: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Oanarina Archi Tool/Thumbnails", isDirectory: true)
    }
    static var templates: URL {
        if let p = UserDefaults.standard.string(forKey: "pref.templatesFolder"), !p.isEmpty { return URL(fileURLWithPath: p, isDirectory: true) }
        return defaultTemplates
    }
    /// Default folder of export/publish panels (nil = next to the drawing).
    static var exportFolder: URL? {
        guard let p = UserDefaults.standard.string(forKey: "pref.exportFolder"), !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p, isDirectory: true)
    }
}

// MARK: - Templates

struct DrawingTemplate: Identifiable, Hashable {
    /// "builtin:<kind>" or a file path.
    var id: String
    var name: String
    var subtitle: String
    var symbol: String
    var url: URL? { id.hasPrefix("builtin:") ? nil : URL(fileURLWithPath: id) }
}

@MainActor
enum TemplateLibrary {
    /// Template files: the .archi format under its own extension (.archi files in the folder work too).
    static let fileExtension = "architemplate"
    static let builtIn: [DrawingTemplate] = [
        DrawingTemplate(id: "builtin:metric", name: "Metric", subtitle: "Millimetres, standard layers", symbol: "square.and.pencil"),
        DrawingTemplate(id: "builtin:metricArchitectural", name: "Metric Architectural", subtitle: "AIA-style layers, 1:20–1:200 dimension styles", symbol: "ruler"),
        DrawingTemplate(id: "builtin:imperial", name: "Imperial", subtitle: "Inches, architectural dimensions", symbol: "ruler.fill"),
        DrawingTemplate(id: "builtin:building", name: "Building", subtitle: "Levels, structural grid and sheets", symbol: "building.2"),
    ]

    /// Built-in templates followed by the .archi files in the templates folder.
    static func all() -> [DrawingTemplate] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: FileLocations.templates, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == ArchiFile.fileExtension || $0.pathExtension.lowercased() == TemplateLibrary.fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return builtIn + files.map { DrawingTemplate(id: $0.path, name: $0.deletingPathExtension().lastPathComponent, subtitle: "Templates folder", symbol: "doc.badge.gearshape") }
    }

    /// Metric architectural template: extra layers, scale-specific dimension and text styles.
    static func metricArchitectural() -> ArchiDocument {
        var d = ArchiDocument()
        d.info.name = "Untitled Project"
        let extra: [Layer] = [
            Layer(name: "A-COLS", color: RGBA(0.8, 0.8, 0.8), lineweight: 0.5), Layer(name: "A-FLOR", color: RGBA(0.7, 0.7, 0.7), lineweight: 0.25),
            Layer(name: "A-ROOF", color: RGBA(0.85, 0.6, 0.4), lineweight: 0.35), Layer(name: "A-STRS", color: RGBA(0.6, 0.8, 0.6), lineweight: 0.25),
            Layer(name: "A-CLNG", color: RGBA(0.6, 0.6, 0.9), lineweight: 0.18), Layer(name: "A-FURN", color: RGBA(0.75, 0.65, 0.95), lineweight: 0.18),
            Layer(name: "A-EQPM", color: RGBA(0.9, 0.7, 0.9), lineweight: 0.18), Layer(name: "A-DETL", color: RGBA(0.9, 0.9, 0.6), lineweight: 0.25),
            Layer(name: "A-PATT", color: RGBA(0.5, 0.5, 0.5), lineweight: 0.09), Layer(name: "A-ANNO-SYMB", color: RGBA(1, 0.85, 0.3), lineweight: 0.18),
            Layer(name: "A-ANNO-NPLT", color: RGBA(0.5, 0.7, 1), lineweight: 0.13, plot: false, description: "Construction lines (not plotted)"),
            Layer(name: "C-PROP", color: RGBA(0.4, 0.9, 0.4), linetype: "Phantom", lineweight: 0.35), Layer(name: "L-PLNT", color: RGBA(0.3, 0.75, 0.35), lineweight: 0.18),
        ]
        for l in extra where d.layer(named: l.name) == nil { d.layers.append(l) }
        d.dimStyles = [DimStyle(name: "Standard")] + [20.0, 50, 100, 200].map { s in
            DimStyle(name: "Architectural 1:\(Int(s))", textHeight: 2.5 * s, arrowSize: 1.5 * s, arrow: .architecturalTick,
                     extensionOffset: 1 * s, extensionExtend: 1.5 * s, textGap: 0.8 * s)
        }
        d.currentDimStyle = "Architectural 1:100"
        d.textStyles = [TextStyle(name: "Standard"), TextStyle(name: "Notes 1:100", font: "Helvetica", height: 250),
                        TextStyle(name: "Titles 1:100", font: "Helvetica-Bold", height: 500), TextStyle(name: "Notes 1:50", font: "Helvetica", height: 125)]
        d.setVariable("LTSCALE", "10")
        d.setVariable("DIMSCALE", "1")
        return d
    }

    /// Opens a template as a new untitled drawing in the given window.
    static func apply(_ t: DrawingTemplate, to m: AppModel) {
        switch t.id {
        case "builtin:metric": m.newDocument(.blankMetric)
        case "builtin:imperial": m.newDocument(.blankImperial)
        case "builtin:building": m.newDocument(.building)
        case "builtin:metricArchitectural":
            m.newDocument(.blankMetric)
            var d = metricArchitectural()
            d.units = .millimeters
            m.editor.replaceDocument(d, url: nil)
            m.editor.print("New drawing from the Metric Architectural template (\(d.layers.count) layers, \(d.dimStyles.count) dimension styles).")
        default:
            guard let u = t.url else { return }
            do {
                var d = try FileController.readDocument(u)
                d.info.name = "Untitled Project"
                m.newDocument(d.units == .inches || d.units == .feet ? .blankImperial : .blankMetric)
                m.editor.replaceDocument(d, url: nil)
                m.editor.isDirty = false
                m.editor.print("New drawing from template \(t.name).")
            } catch { m.files.showError(error) }
        }
        m.showStart = false
        m.revision &+= 1
        m.zoomExtents()
    }

    /// Writes the drawing into the templates folder. Returns the file.
    @discardableResult
    static func save(_ doc: ArchiDocument, name: String) throws -> URL {
        let dir = FileLocations.templates
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent(safe).appendingPathExtension(fileExtension)
        try ArchiFile.encode(doc).write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Document thumbnails (start screen, recent files)

@MainActor
enum DocumentThumbnails {
    private static var memory: [String: NSImage] = [:]

    /// Plan picture of a drawing (current level), drawn with display colours on the canvas colour.
    static func render(_ doc: ArchiDocument, size: CGSize = CGSize(width: 320, height: 200)) -> NSImage? {
        let w = Int(size.width * 2), h = Int(size.height * 2)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(Theme.nsCanvas.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let level = doc.levels.isEmpty ? nil : doc.currentLevel
        var entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: level))
        if entries.isEmpty { entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: nil)) }
        let b = entries.unionBounds
        guard !b.isEmpty, b.width + b.height > 0 else { return NSImage(cgImage: ctx.makeImage()!, size: size) }
        let margin = 0.08
        let s = min(Double(w) * (1 - 2 * margin) / max(b.width, 1e-9), Double(h) * (1 - 2 * margin) / max(b.height, 1e-9))
        let t = CGAffineTransform(translationX: -b.center.x, y: -b.center.y)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: CGFloat(w) / 2, y: CGFloat(h) / 2))
        var r = PlotRenderer(transform: t, devicePerMM: 1.2, paper: false, minLineWidth: 0.6)
        r.lineweightScale = 1
        r.draw(entries, in: ctx)
        guard let img = ctx.makeImage() else { return nil }
        return NSImage(cgImage: img, size: size)
    }


    /// Cached thumbnail of a drawing file (memory, then disk, else rendered and stored). Hasher is seeded per launch,
    /// so disk files are keyed by a stable FNV hash instead.
    static func thumbnail(for url: URL) -> NSImage? {
        guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        let key = stableKey(url.path + "|\(Int(mtime.timeIntervalSince1970))")
        if let i = memory[key] { return i }
        let file = FileLocations.thumbnails.appendingPathComponent(key + ".png")
        if let i = NSImage(contentsOf: file) { memory[key] = i; return i }
        guard url.pathExtension.lowercased() == ArchiFile.fileExtension || url.pathExtension.lowercased() == "dxf",
              let doc = try? FileController.readDocument(url), let img = render(doc) else { return nil }
        memory[key] = img
        try? FileManager.default.createDirectory(at: FileLocations.thumbnails, withIntermediateDirectories: true)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: file, options: .atomic)
        }
        return img
    }

    /// FNV-1a 64-bit hex (stable across launches).
    static func stableKey(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}

/// Thumbnail loaded after the view appears (does not block the start screen).
struct ThumbnailView: View {
    let url: URL?
    var document: ArchiDocument? = nil
    var symbol = "building.columns"
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.canvas)
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Theme.textFaint) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url?.path ?? "doc") {
            await Task.yield()
            if let d = document { image = DocumentThumbnails.render(d) }
            else if let u = url { image = DocumentThumbnails.thumbnail(for: u) }
        }
    }
}

extension AppModel {
    /// Zooms the plan (or orbits the 3D view) to the selection.
    func zoomToSelection() {
        let doc = self.doc
        var b = BBox2.empty
        for e in selectedEntities { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
        for el in selectedElements { for p in CommandHelpers.footprint(el, doc: doc) { b.add(p) } }
        guard !b.isEmpty else { return }
        if mode == .model { viewport3D?.orbitSelection(editor.selection, frame: true); return }
        let pad = max(b.width, b.height) * 0.15 + 100
        canvas?.zoom(to: b.expanded(by: pad))
    }
}
