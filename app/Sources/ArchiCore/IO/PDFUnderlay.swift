// Oanarina Archi Tool — GPL-3.0-or-later
// PDF underlays (IO-015): a PDF page attached by reference. The page's vectors and text are read into a block
// ("PDF_<file>_p<page>") shown through one block reference on a faded, locked "PDF-UNDERLAY" layer, so object snaps
// (endpoint, midpoint, intersection…) work on the underlay while it cannot be edited by accident. The reference keeps
// the source path and page: RELOAD re-reads a changed PDF, DETACH removes the reference and its definition.
import Foundation

public enum PDFUnderlay {
    public static let layer = "PDF-UNDERLAY"

    public struct Info: Hashable {
        public var id: EntityID
        public var path: String
        public var page: Int
        public var block: String
        public var scale: Double
        public var objects: Int
    }

    static func blockName(_ url: URL, page: Int) -> String {
        let base = url.deletingPathExtension().lastPathComponent.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "PDF_\(String(base))_p\(page)"
    }

    /// Page content in drawing units at `scale` (drawing scale 1:scale), lower-left corner at the origin; entities on layer 0.
    static func content(_ url: URL, page: Int, scale: Double, unitMM: Double) throws -> [Entity] {
        let pdf: PDFFile
        do { pdf = try PDFFile(Data(contentsOf: url)) } catch { throw DocumentIO.IOError(message: "Cannot read \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        guard page >= 1, page <= pdf.pages.count else { throw DocumentIO.IOError(message: "\(url.lastPathComponent) has \(pdf.pages.count) page(s)") }
        var o = PDFImportOptions()
        o.unitsPerPoint = 25.4 / 72 * scale / unitMM
        var ents = try PDFImport.entities(pdf, page: page, options: o)
        for i in ents.indices { ents[i].props["pdfLayer"] = ents[i].layer; ents[i].layer = "0" }
        return ents
    }

    /// Attaches a page and returns the id of the block reference.
    @discardableResult
    public static func attach(_ url: URL, page: Int = 1, into doc: inout ArchiDocument, at: Vec2 = .zero, scale: Double = 1, fade: Double = 0.5) throws -> EntityID {
        let ents = try content(url, page: page, scale: scale, unitMM: doc.units.mm)
        guard !ents.isEmpty else { throw DocumentIO.IOError(message: "Page \(page) has no vector content") }
        var name = blockName(url, page: page)
        if let b = doc.blocks[name], !b.description.hasPrefix("PDF underlay") { name += "_u" }
        var ids = 1
        doc.blocks[name] = Block(name: name, basePoint: .zero, entities: ents.map { var e = $0; e.id = ids; ids += 1; return e },
                                 description: "PDF underlay: \(url.path)#\(page)")
        if doc.layer(named: layer) == nil {
            doc.layers.append(Layer(name: layer, color: RGBA(0.6, 0.6, 0.6), lineweight: 0.13, locked: true, transparency: min(0.9, max(0, fade)),
                                    description: "PDF underlays"))
        }
        return doc.add(Entity(layer: layer, geometry: .insert(InsertGeom(block: name, position: at)),
                              props: ["underlay": "pdf", "path": url.path, "page": "\(page)", "scale": fmt(scale, 6)]))
    }

    public static func list(_ doc: ArchiDocument) -> [Info] {
        doc.entities.compactMap { e in
            guard e.props["underlay"] == "pdf", case .insert(let ins) = e.geometry else { return nil }
            return Info(id: e.id, path: e.props["path"] ?? "", page: Int(e.props["page"] ?? "") ?? 1, block: ins.block,
                        scale: Double(e.props["scale"] ?? "") ?? 1, objects: doc.blocks[ins.block]?.entities.count ?? 0)
        }
    }

    /// Re-reads the PDF of an underlay (all references to the same page update). Returns the new object count.
    @discardableResult
    public static func reload(_ id: EntityID, in doc: inout ArchiDocument) throws -> Int {
        guard let u = list(doc).first(where: { $0.id == id }) else { throw DocumentIO.IOError(message: "#\(id) is not a PDF underlay") }
        let ents = try content(URL(fileURLWithPath: u.path), page: u.page, scale: u.scale, unitMM: doc.units.mm)
        var n = 1
        doc.blocks[u.block]?.entities = ents.map { var e = $0; e.id = n; n += 1; return e }
        return ents.count
    }

    /// Removes the reference; the page definition goes when nothing else uses it.
    public static func detach(_ id: EntityID, in doc: inout ArchiDocument) {
        guard let u = list(doc).first(where: { $0.id == id }) else { return }
        doc.entities.removeAll { $0.id == id }
        let used = doc.entities.contains { if case .insert(let i) = $0.geometry { return i.block == u.block }; return false }
            || doc.blocks.values.contains { $0.entities.contains { if case .insert(let i) = $0.geometry { return i.block == u.block }; return false } }
        if !used { doc.blocks.removeValue(forKey: u.block) }
    }

    /// Sets the fading (layer transparency 0…0.9) of all underlays.
    public static func setFade(_ f: Double, in doc: inout ArchiDocument) {
        if let i = doc.layerIndex(layer) { doc.layers[i].transparency = min(0.9, max(0, f)) }
    }
}
