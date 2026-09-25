// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Headless import/export by file extension, used by the IO commands, the CLI and agents.
public enum FileImport {
    public static let importFormats = ["archi", "dxf", "dwg", "ifc", "ifczip", "svg", "obj", "usda", "usdz", "usd", "stl", "3mf", "gltf", "glb", "ply", "off", "amf", "dae", "stp", "step",
                                       "geojson", "cityjson", "shp", "osm", "asc", "xlsx", "csv", "tsv", "txt", "xyz", "pts", "las", "igs", "iges", "fbx", "pdf", "dwfx", "dwf", "dgn",
                                       "png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif", "avif"]
    public static let exportFormats = ["3mf", "usda", "usdz", "geojson", "dxf12", "points", "stp", "step", "ply", "plt", "hpgl", "xlsx", "ifczip", "dwg", "analytical", "opensees", "tcl", "laser", "igs", "iges", "fbx", "html", "dgn", "gbxml", "cobie", "dae",
                                       "kml", "kmz", "bcfzip", "bcf", "boq", "svglayers"]

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
        case "json":
            // CityJSON files are JSON too ("type": "CityJSON").
            if override == nil, let h = try? FileHandle(forReadingFrom: url), let head = try? h.read(upToCount: 4096) {
                try? h.close()
                if String(decoding: head, as: UTF8.self).replacingOccurrences(of: " ", with: "").contains("\"type\":\"CityJSON\"") { return "cityjson" }
            }
            return "geojson"
        case "cityjson", "jsonl": return "cityjson"
        case "tsv", "txt", "csv", "points": return "csv"
        case "pts": return "pointcloud"
        case "xyz":
            // Laser-scan exports (many rows or colour columns) are point clouds; short survey lists stay point tables.
            if override == nil, let text = try? readText(url) {
                let lines = text.split(whereSeparator: { $0.isNewline })
                let wide = lines.prefix(20).contains { $0.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == ";" }).compactMap { Double($0) }.count >= 6 }
                return lines.count > 5000 || wide ? "pointcloud" : "csv"
            }
            return "csv"
        case "step", "stp", "p21": return "step"
        case "glb": return "gltf"
        case "tif", "tiff", "png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "avif": return "image"
        case "dem": return f
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
        case "ifczip":
            let r = try IFCImporter.importFile(try IFCZip.read(try Data(contentsOf: url)))
            return (r.doc, r.summary)
        case "dwg":
            let d = try DWGConverter.read(url, converter: reference.variable("DWGCONVERTER"))
            return (d, "\(d.entities.count) entities, \(d.blocks.count) blocks (converted from DWG)")
        case "gltf":
            let ents = try GLTFImporter.entities(try Data(contentsOf: url), baseURL: url.deletingLastPathComponent(), scale: 1000 / reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) glTF meshes")
        case "ply":
            let data = try Data(contentsOf: url)
            let ply = try PointCloud.parsePLY(data)
            if let mesh = PointCloud.mesh(fromPLY: ply, scale: 1000 / reference.units.mm) {
                return (entityDoc([mesh], native: true), "PLY mesh (\(ply.faces.count) faces)")
            }
            let ents = PointCloud.entities(ply.points, options: PointCloudOptions(scale: 1000 / reference.units.mm))
            return (entityDoc(ents, native: true), "\(ents.count) of \(ply.points.count) PLY points")
        case "dgn":
            let r = try DGN.read(try Data(contentsOf: url))
            return (entityDoc(r.entities), "\(r.entities.count) DGN elements" + (r.is3D ? " (3D file, Z dropped)" : ""))
        case "dwfx", "dwf":
            let ents = try DWFxImporter.entities(try Data(contentsOf: url))
            return (entityDoc(ents), "\(ents.count) DWFx objects")
        case "pdf":
            let pdf = try PDFFile(try Data(contentsOf: url))
            var ents: [Entity] = []
            var o = PDFImportOptions(); o.unitsPerPoint = 25.4 / 72
            for n in 1...max(1, pdf.pages.count) where n <= pdf.pages.count {
                // Pages side by side, 20 mm apart.
                o.origin = Vec2(ents.isEmpty ? 0 : (ents.map { GeometryOps.bounds($0.geometry, doc: nil).max.x }.max() ?? 0) + 20, 0)
                ents += try PDFImport.entities(pdf, page: n, options: o)
            }
            return (entityDoc(ents), "\(ents.count) PDF objects from \(pdf.pages.count) page(s)")
        case "fbx":
            let r = try FBX.entities(try Data(contentsOf: url))
            var d = entityDoc(r.entities)
            d.ensureLayer("IMPORT-FBX")
            for m in r.materials { if let i = d.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(m.name) == .orderedSame }) { d.materials[i] = m } else { d.materials.append(m) } }
            return (d, "\(r.entities.count) FBX meshes, \(r.materials.count) materials")
        case "igs", "iges":
            let ents = try IGES.read(try readText(url))
            return (entityDoc(ents), "\(ents.count) IGES curves")
        case "las":
            let r = try LASReader.entities(try Data(contentsOf: url), options: PointCloudOptions(scale: 1000 / reference.units.mm))
            return (entityDoc(r.entities, native: true), "\(r.entities.count) of \(r.total) LAS points")
        case "laz":
            throw PointCloud.CloudError.invalid("LAZ is compressed: decompress it to LAS first (laszip -i file.laz -o file.las).")
        case "pointcloud":
            let r = try PointCloud.load(try Data(contentsOf: url), ext: url.pathExtension, options: PointCloudOptions(scale: 1000 / reference.units.mm))
            return (entityDoc(r.entities, native: true), "\(r.entities.count) of \(r.total) points")
        case "off":
            let e = try PointCloud.off(try readText(url))
            return (entityDoc([e]), "OFF mesh")
        case "amf":
            let ents = try PointCloud.amf(try Data(contentsOf: url), unitMM: reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) AMF objects")
        case "dae":
            let ents = try ColladaImporter.entities(try Data(contentsOf: url), unitMM: reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) COLLADA meshes")
        case "cityjson":
            let ents = try CityJSONImporter.entities(try Data(contentsOf: url), doc: reference)
            return (entityDoc(ents, native: true), "\(ents.count) city objects")
        case "step":
            let ents = try STEPImporter.entities(try readText(url), unitMM: reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) STEP shells")
        case "shp":
            let ents = try Shapefile.load(url, doc: reference)
            return (entityDoc(ents, native: true), "\(ents.count) shapefile features")
        case "osm":
            var o = GISImportOptions(); o.masses = true
            let ents = try OSMImporter.entities(try Data(contentsOf: url), doc: reference, options: o)
            return (entityDoc(ents, native: true), "\(ents.filter { $0.layer == "OSM-BUILDINGS" }.count) buildings, \(ents.count) OSM features")
        case "asc":
            let g = try ElevationGrid.parse(try readText(url))
            let e = try ElevationGrid.topo(g, unitMM: reference.units.mm)
            return (entityDoc([e], native: true), "toposurface from a \(g.ncols)×\(g.nrows) grid (\(fmt(g.cell, 2)) m cells)")
        case "xlsx":
            let sheets = try XLSX.read(try Data(contentsOf: url))
            let ents = XLSXTables.entities(sheets, unitMM: reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) table(s) from \(sheets.count) sheet(s)")
        case "svg":
            let ents = try SVGImporter.entities(try readText(url))
            return (entityDoc(ents), "\(ents.count) SVG entities")
        case "obj":
            // Materials (colour, opacity, textures) come from the OBJ's mtllib files next to it.
            let r = try MTLReader.importOBJ(url)
            var d = entityDoc(r.entities)
            for m in r.materials { if let i = d.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(m.name) == .orderedSame }) { d.materials[i] = m } else { d.materials.append(m) } }
            return (d, "\(r.entities.count) OBJ meshes" + (r.materials.isEmpty ? "" : ", \(r.materials.count) materials (\(r.materials.filter { $0.texture != nil }.count) textured)"))
        case "usd", "usda", "usdz":
            let r = try USDImporter.read(url)
            var d = entityDoc(r.entities)
            d.ensureLayer("IMPORT-USD")
            for m in r.materials { if let i = d.materials.firstIndex(where: { $0.name.caseInsensitiveCompare(m.name) == .orderedSame }) { d.materials[i] = m } else { d.materials.append(m) } }
            return (d, "\(r.entities.count) USD meshes, \(r.materials.count) materials")
        case "stl":
            let ents = try MeshImporter.stl(try Data(contentsOf: url))
            return (entityDoc(ents), "STL mesh (\(ents.first.map { if case .solid(let s) = $0.geometry { return s.meshTriangles.count / 3 }; return 0 } ?? 0) triangles)")
        case "3mf":
            let ents = try ThreeMFImporter.entities(try Data(contentsOf: url), scale: 1 / reference.units.mm)
            return (entityDoc(ents, native: true), "\(ents.count) 3MF objects")
        case "geojson":
            let ents = try GeoJSON.entities(try readText(url), doc: reference)
            return (entityDoc(ents, native: true), "\(ents.count) GeoJSON features")
        case "image":
            // Georeferenced with a world file when present, else 10 mm per pixel at the origin.
            let (im, geo) = try ImagePlacement.load(url, doc: reference)
            var d = entityDoc([Entity(layer: "IMAGES", geometry: .image(im))], native: true)
            d.ensureLayer("IMAGES")
            return (d, "image \(fmt(im.size.x, 0)) × \(fmt(im.size.y, 0))" + (geo ? " (georeferenced by world file)" : ""))
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

    /// Mesh group in millimetres (MeshBuilder works in drawing units).
    static func scaled(_ g: MeshGroup, _ unitMM: Double) -> MeshGroup {
        guard abs(unitMM - 1) > 1e-12 else { return g }
        var c = g
        c.mesh.positions = g.mesh.positions.map { $0 * unitMM }
        return c
    }

    /// Writes the extra exchange formats (3mf, usda, usdz, geojson, dxf12, points csv). Returns false for other formats.
    @discardableResult
    public static func export(_ doc: ArchiDocument, to url: URL, format: String) throws -> Bool {
        let unitMM = doc.units.mm
        switch format.lowercased() {
        case "3mf": try ThreeMFExporter.export(MeshBuilder.build(doc: doc), materials: doc.materials, name: doc.info.name, unitScale: unitMM).write(to: url, options: .atomic)
        case "usda", "usd": try USDExporter.usda(MeshBuilder.build(doc: doc), materials: doc.materials, metersPerUnit: unitMM / 1000, name: doc.info.name).write(to: url, atomically: true, encoding: .utf8)
        case "usdz": try USDExporter.usdz(MeshBuilder.build(doc: doc), materials: doc.materials, metersPerUnit: unitMM / 1000, name: doc.info.name,
                                          textureRoot: doc.variable("TEXTUREROOT").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? url.deletingLastPathComponent()).write(to: url, options: .atomic)
        case "geojson": try GeoJSON.export(doc).write(to: url, atomically: true, encoding: .utf8)
        case "dxf12", "r12": try DXFWriter.write(doc, version: .r12).write(to: url, atomically: true, encoding: .utf8)
        case "points": try PointTable.exportPoints(doc).write(to: url, atomically: true, encoding: .utf8)
        case "stp", "step": try STEPExporter.export(MeshBuilder.build(doc: doc).map { scaled($0, unitMM) }, materials: doc.materials, name: doc.info.name, author: doc.info.author).write(to: url, atomically: true, encoding: .utf8)
        case "ply": try PointCloud.exportPLY(MeshBuilder.build(doc: doc).map { scaled($0, unitMM) }, materials: doc.materials).write(to: url, atomically: true, encoding: .utf8)
        case "plt", "hpgl":
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: doc.currentLevel))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            let scale = Double(doc.variable("PLOTSCALE") ?? "") ?? 100
            // PLOTROLL = roll width in mm (large-format plotters); PLOTMARGIN = margin mm.
            let roll = Double(doc.variable("PLOTROLL") ?? "").flatMap { $0 > 0 ? HPGLExporter.RollMedia(width: $0, margin: Double(doc.variable("PLOTMARGIN") ?? "") ?? 10) : nil }
            try HPGLExporter.export(entries, bounds: b, scale: scale, unitMM: unitMM, roll: roll).write(to: url, atomically: true, encoding: .ascii)
        case "xlsx": try XLSX.schedules(doc).write(to: url, options: .atomic)
        case "ifczip":
            let ifc = IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc))
            try IFCZip.write(ifc, name: url.deletingPathExtension().lastPathComponent + ".ifc").write(to: url, options: .atomic)
        case "dwg": try DWGConverter.write(doc, to: url, converter: doc.variable("DWGCONVERTER"))
        case "gbxml": try GBXMLExporter.export(doc).write(to: url, atomically: true, encoding: .utf8)
        case "cobie": try COBieExporter.export(doc).write(to: url, options: .atomic)
        case "dae": try ColladaExporter.export(MeshBuilder.build(doc: doc), materials: doc.materials, unitMM: unitMM).write(to: url, atomically: true, encoding: .utf8)
        case "kml": try KMLExporter.kml(doc, options: KMLOptions()).write(to: url, atomically: true, encoding: .utf8)
        case "kmz": try KMLExporter.kmz(doc).write(to: url, options: .atomic)
        case "bcf", "bcfzip": try BCF.export(doc, projectFile: url.deletingPathExtension().lastPathComponent + ".ifc").write(to: url, options: .atomic)
        case "boq":
            let boq = BillOfQuantities.build(QuantityTakeoff.compute(doc), table: CostTable.fromVariables(doc), options: BoQOptions.from(doc))
            if url.pathExtension.lowercased() == "xlsx" { try boq.xlsx.write(to: url, options: .atomic) } else { try boq.csv.write(to: url, atomically: true, encoding: .utf8) }
        case "svglayers":
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: doc.currentLevel))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            try SVGExporter.exportLayered(doc: doc, entries: entries, bounds: b.expanded(by: max(b.width, b.height) * 0.02), background: nil).write(to: url, atomically: true, encoding: .utf8)
        case "html", "htm", "viewer": try ViewerExport.html(doc).write(to: url, atomically: true, encoding: .utf8)
        case "dgn": try DGN.write(doc).write(to: url, options: .atomic)
        case "fbx": try FBX.export(MeshBuilder.build(doc: doc), materials: doc.materials, unitMM: unitMM, name: doc.info.name).write(to: url, options: .atomic)
        case "igs", "iges": try IGES.export(doc).write(to: url, atomically: true, encoding: .ascii)
        case "laser", "lasersvg", "cnc":
            try LaserExporter.export(doc, options: LaserOptions.from(doc)).svg.write(to: url, atomically: true, encoding: .utf8)
        case "opensees", "tcl":
            try StructuralLoads.openSeesTcl(StructuralAnalysis.model(doc, options: AnalyticalOptions.from(doc)), name: doc.info.name).write(to: url, atomically: true, encoding: .utf8)
        case "analytical":
            let m = StructuralAnalysis.model(doc, options: AnalyticalOptions.from(doc))
            try JSONSerialization.data(withJSONObject: m.json(name: doc.info.name), options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        default: return false
        }
        return true
    }
}
