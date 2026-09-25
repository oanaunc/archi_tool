// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Headless import/export by file extension, used by the IO commands, the CLI and agents.
public enum FileImport {
    public static let importFormats = ["archi", "dxf", "ifc", "svg", "obj", "stl", "3mf", "geojson", "csv", "tsv", "txt", "xyz", "pts"]
    public static let exportFormats = ["3mf", "usda", "usdz", "geojson", "dxf12", "points"]

    public enum ImportError: Error, LocalizedError {
        case unsupported(String), unreadable(String)
        public var errorDescription: String? {
            switch self {
            case .unsupported(let f): return "Unsupported import format '\(f)' (use: \(FileImport.importFormats.joined(separator: ", ")))"
            case .unreadable(let p): return "Cannot read \(p)"
            }
        }
    }

    public static func readText(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable(url.path) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Normalised format name for a path/extension ("json" → "geojson", "tsv"/"txt"/"xyz"/"pts" → "csv").
    public static func format(for url: URL, override: String? = nil) -> String {
        let f = (override ?? url.pathExtension).lowercased()
        switch f {
        case "json": return "geojson"
        case "tsv", "txt", "xyz", "pts", "csv", "points": return "csv"
        case "ifczip": return "ifc"
        default: return f
        }
    }

    /// Reads a file into a stand-alone document plus a one-line summary.
    public static func load(_ url: URL, format: String? = nil, reference: ArchiDocument = ArchiDocument()) throws -> (ArchiDocument, String) {
        let f = self.format(for: url, override: format)
        /// Entities in millimetres (or in the reference document's units when `native`).
        func entityDoc(_ ents: [Entity], native: Bool = false) -> ArchiDocument {
            var d = ArchiDocument(); d.entities = []; d.elements = []
            d.units = native ? reference.units : .millimeters
            d.levels = reference.levels
            for e in ents { d.add(e) }
            return d
        }
        switch f {
        case "archi": let d = try ArchiFile.decode(Data(contentsOf: url)); return (d, "\(d.entities.count) entities, \(d.elements.count) elements")
        case "dxf": let d = try DXFReader.read(try readText(url)); return (d, "\(d.entities.count) entities, \(d.blocks.count) blocks")
        case "ifc":
            let r = try IFCImporter.importFile(try readText(url))
            return (r.doc, r.summary)
        case "svg":
            let ents = try SVGImporter.entities(try readText(url))
            return (entityDoc(ents), "\(ents.count) SVG entities")
        case "obj":
            let ents = try MeshImporter.obj(try readText(url))
            return (entityDoc(ents), "\(ents.count) OBJ meshes")
        case "stl":
            let ents = try MeshImporter.stl(try Data(contentsOf: url))
            return (entityDoc(ents), "STL mesh (\(ents.first.map { if case .solid(let s) = $0.geometry { return s.meshTriangles.count / 3 }; return 0 } ?? 0) triangles)")
        case "3mf":
            let ents = try ThreeMFImporter.entities(try Data(contentsOf: url), scale: 1 / reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) 3MF objects")
        case "geojson":
            let ents = try GeoJSON.entities(try readText(url), doc: reference)
            return (entityDoc(ents, native: true), "\(ents.count) GeoJSON features")
        case "csv":
            let r = PointTable.importPoints(try readText(url))
            return (entityDoc(r.entities, native: true), "\(r.entities.count) points" + (r.skipped > 0 ? " (\(r.skipped) rows skipped)" : ""))
        default: throw ImportError.unsupported(f)
        }
    }

    /// Imports a file into `doc` (merged with new IDs). Returns the merge result and a summary.
    @discardableResult
    public static func importFile(_ url: URL, into doc: inout ArchiDocument, format: String? = nil, offset: Vec2 = .zero) throws -> (DocumentMerge.Result, String) {
        let (src, summary) = try load(url, format: format, reference: doc)
        let scale = src.units.mm / doc.units.mm
        let r = DocumentMerge.merge(src, into: &doc, offset: offset, scale: scale)
        return (r, summary)
    }

    /// Writes the extra exchange formats (3mf, usda, usdz, geojson, dxf12, points csv). Returns false for other formats.
    @discardableResult
    public static func export(_ doc: ArchiDocument, to url: URL, format: String) throws -> Bool {
        let unitMM = doc.units.mm
        switch format.lowercased() {
        case "3mf": try ThreeMFExporter.export(MeshBuilder.build(doc: doc), materials: doc.materials, name: doc.info.name, unitScale: unitMM).write(to: url, options: .atomic)
        case "usda", "usd": try USDExporter.usda(MeshBuilder.build(doc: doc), materials: doc.materials, metersPerUnit: unitMM / 1000, name: doc.info.name).write(to: url, atomically: true, encoding: .utf8)
        case "usdz": try USDExporter.usdz(MeshBuilder.build(doc: doc), materials: doc.materials, metersPerUnit: unitMM / 1000, name: doc.info.name).write(to: url, options: .atomic)
        case "geojson": try GeoJSON.export(doc).write(to: url, atomically: true, encoding: .utf8)
        case "dxf12", "r12": try DXFWriter.write(doc, version: .r12).write(to: url, atomically: true, encoding: .utf8)
        case "points": try PointTable.exportPoints(doc).write(to: url, atomically: true, encoding: .utf8)
        default: return false
        }
        return true
    }
}
