// Oanarina Archi Tool — GPL-3.0-or-later
// Import/export commands for the exchange formats in ArchiCore/IO. They work headless (CLI, scripts, agents).
import Foundation

public enum IOCommands {
    public static var all: [CommandDef] { [importFile, ifcImport, svgImport, meshImport, geoJSONImport, geoJSONExport, pointsImport, pointsExport,
                                           export3MF, usdExport, dxfR12Out, dxfOutVersion, ifcXMLOut, lazConverter, Presentation.command, DocSite.command, SurveyCodes.command] + ExchangeCommands.all + MoreIOCommands.all + CollabCommands.all + LifecycleCommands.all + FileSignature.commands }

    /// Resolves a path typed on the command line (~, relative to the drawing's folder, else the working directory).
    @MainActor static func resolve(_ ed: Editor, _ path: String) -> URL {
        let p = (path.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) as NSString).expandingTildeInPath
        if PathSupport.isAbsolute(p) { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        if let dir = ed.fileURL?.deletingLastPathComponent() { return dir.appendingPathComponent(p) }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(p)
    }

    @MainActor static func path(_ ed: Editor, _ msg: String) async throws -> URL {
        guard let p = try await ed.getWord(msg), !p.isEmpty else { throw CommandError.invalid("A file name is required.") }
        return resolve(ed, p)
    }

    @MainActor static func runImport(_ ed: Editor, _ url: URL, format: String?) throws {
        var d = ed.doc
        do {
            let (res, summary) = try FileImport.importFile(url, into: &d, format: format)
            ed.doc = d
            ed.selection = Set(res.allIDs)
            ed.print("Imported \(url.lastPathComponent): \(summary).")
            if !res.addedLevels.isEmpty { ed.print("Added levels: \(res.addedLevels.joined(separator: ", ")).") }
            ed.host?.perform(.zoomExtents, editor: ed)
        } catch let e as CommandError { throw e }
        catch { throw CommandError.invalid("Cannot import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
    }

    @MainActor static func write(_ ed: Editor, _ url: URL, _ what: String, _ body: () throws -> Void) throws {
        do { try body(); ed.print("Wrote \(what) \(url.path).") }
        catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
    }

    static var importFile: CommandDef {
        CommandDef("IMPORTFILE", aliases: ["FILEIMPORT", "IMPORTANY"], category: "File",
                   summary: "Imports a file by extension: .archi, .dxf, .ifc, .svg, .obj, .stl, .3mf, .geojson, .csv/.txt/.xyz points.") { ed in
            let url = try await path(ed, "Enter file name to import")
            try runImport(ed, url, format: nil)
        }
    }

    static var ifcImport: CommandDef {
        CommandDef("IFCIMPORT", aliases: ["IFCIN", "-IFCIMPORT"], category: "File",
                   summary: "Imports an IFC (IFC2x3/IFC4) model: walls, slabs, columns, beams, doors, windows and spaces become BIM elements; other products become meshes.") { ed in
            let url = try await path(ed, "Enter IFC file name")
            try runImport(ed, url, format: "ifc")
        }
    }

    static var svgImport: CommandDef {
        CommandDef("SVGIMPORT", aliases: ["SVGIN", "-SVGIMPORT"], category: "File",
                   summary: "Imports SVG paths, lines, polylines, polygons, circles, ellipses, rectangles and text as drawing entities.") { ed in
            let url = try await path(ed, "Enter SVG file name")
            let s = try await ed.getReal("Specify drawing units per SVG unit or [Auto]", defaultValue: nil, keywords: ["Auto"])
            var o = SVGImportOptions()
            if case .value(let v) = s, v > 0 { o.scale = v }
            o.fillsAsHatches = try await ed.getYesNo("Create solid hatches for filled shapes?", defaultValue: false)
            do {
                let ents = try SVGImporter.entities(try FileImport.readText(url), options: o)
                var src = ArchiDocument(); src.entities = []; src.elements = []; src.units = ed.doc.units
                for e in ents { src.add(e) }
                var d = ed.doc
                let r = DocumentMerge.merge(src, into: &d)
                ed.doc = d; ed.selection = Set(r.allIDs)
                ed.print("Imported \(ents.count) entities from \(url.lastPathComponent).")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw CommandError.invalid("Cannot import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        }
    }

    static var meshImport: CommandDef {
        CommandDef("MESHIMPORT", aliases: ["OBJIMPORT", "STLIMPORT", "3MFIMPORT", "OBJIN", "STLIN", "GLTFIMPORT", "GLBIMPORT", "PLYIMPORT", "OFFIMPORT", "AMFIMPORT", "DAEIMPORT", "COLLADAIMPORT"], category: "File",
                   summary: "Imports an OBJ, STL, 3MF, glTF/GLB, PLY, OFF, AMF or COLLADA (.dae) file as mesh solids (choose the file's units where the format has none).") { ed in
            let url = try await path(ed, "Enter OBJ/STL/3MF/glTF/GLB/PLY/OFF/AMF/DAE file name")
            let ext = url.pathExtension.lowercased()
            guard ["obj", "stl", "3mf", "gltf", "glb", "ply", "off", "amf", "dae"].contains(ext) else { throw CommandError.invalid("Use a .obj, .stl, .3mf, .gltf, .glb, .ply, .off, .amf or .dae file.") }
            if ["gltf", "glb", "amf", "dae"].contains(ext) {
                // Formats with defined units (glTF: metres; AMF: its unit attribute).
                do {
                    let data = try Data(contentsOf: url)
                    let ents = ext == "amf" ? try PointCloud.amf(data, unitMM: ed.doc.units.mm)
                        : ext == "dae" ? try ColladaImporter.entities(data, unitMM: ed.doc.units.mm)
                        : try GLTFImporter.entities(data, baseURL: url.deletingLastPathComponent(), scale: 1000 / ed.doc.units.mm)
                    var ids: [EntityID] = []
                    for e in ents { ed.doc.ensureLayer(e.layer); ids.append(ed.doc.add(e)) }
                    ed.selection = Set(ids)
                    let tris = ents.reduce(0) { n, e in if case .solid(let s) = e.geometry { return n + s.meshTriangles.count / 3 }; return n }
                    ed.print("Imported \(ents.count) mesh\(ents.count == 1 ? "" : "es") (\(tris) triangles) from \(url.lastPathComponent).")
                    return
                } catch { throw CommandError.invalid("Cannot import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            }
            let units = ["Meters", "Centimeters", "Millimeters", "Inches", "Feet"]
            let def = ext == "obj" ? "Meters" : "Millimeters"
            let u = ext == "3mf" ? "Millimeters" : (try await ed.getKeyword("Specify file units", units, defaultValue: def) ?? def)
            let mmPer: [String: Double] = ["Meters": 1000, "Centimeters": 10, "Millimeters": 1, "Inches": 25.4, "Feet": 304.8]
            let k = (mmPer[u] ?? 1) / ed.doc.units.mm
            do {
                let ents: [Entity]
                switch ext {
                case "obj": var o = MeshImportOptions.obj; o.scale = k; ents = try MeshImporter.obj(try FileImport.readText(url), options: o)
                case "stl": var o = MeshImportOptions.stl; o.scale = k; ents = try MeshImporter.stl(try Data(contentsOf: url), options: o)
                case "off": ents = [try PointCloud.off(try FileImport.readText(url), scale: k)]
                case "ply":
                    let ply = try PointCloud.parsePLY(try Data(contentsOf: url))
                    guard let m = PointCloud.mesh(fromPLY: ply, scale: k) else { throw CommandError.invalid("The PLY file has no faces; use POINTCLOUDIMPORT for point clouds.") }
                    ents = [m]
                default: ents = try ThreeMFImporter.entities(try Data(contentsOf: url), scale: 1 / ed.doc.units.mm)
                }
                var ids: [EntityID] = []
                for e in ents { ids.append(ed.doc.add(e)) }
                ed.selection = Set(ids)
                let tris = ents.reduce(0) { n, e in if case .solid(let s) = e.geometry { return n + s.meshTriangles.count / 3 }; return n }
                ed.print("Imported \(ents.count) mesh\(ents.count == 1 ? "" : "es") (\(tris) triangles) from \(url.lastPathComponent).")
            } catch { throw CommandError.invalid("Cannot import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        }
    }

    static var geoJSONImport: CommandDef {
        CommandDef("GEOJSONIMPORT", aliases: ["GEOJSONIN"], category: "File",
                   summary: "Imports GeoJSON features (WGS84 lon/lat are projected around the project location; projected metres are used as-is).") { ed in
            let url = try await path(ed, "Enter GeoJSON file name")
            try runImport(ed, url, format: "geojson")
        }
    }

    static var geoJSONExport: CommandDef {
        CommandDef("GEOJSONEXPORT", aliases: ["GEOJSONOUT"], category: "File", summary: "Exports 2D entities (selection or all) as GeoJSON in WGS84 or local metres.", modifies: false) { ed in
            let url = try await path(ed, "Enter GeoJSON file name")
            let k = try await ed.getKeyword("Coordinates [Geographic/Local/Utm/Webmercator/Epsg]", ["Geographic", "Local", "Utm", "Webmercator", "Epsg"], defaultValue: "Geographic") ?? "Geographic"
            var crs: GeoCRS? = nil
            switch k {
            case "Utm": crs = GeoCRS.utmZone(lon: ed.doc.info.longitude, lat: ed.doc.info.latitude)
            case "Webmercator": crs = .webMercator
            case "Epsg":
                guard let c = try await ed.getWord("Enter EPSG code (4326, 3857, 326xx, 327xx, 258xx)"), let g = GeoCRS.parse("EPSG:" + c) else { throw CommandError.invalid("Unsupported EPSG code.") }
                crs = g
            case "Local": crs = .local
            default: crs = .wgs84
            }
            let ids: Set<EntityID>? = ed.selection.isEmpty ? nil : ed.selection
            let text = GeoJSON.export(ed.doc, options: GeoJSONOptions(geographic: crs != .local, crs: crs), ids: ids)
            if let c = crs, c != .wgs84 { ed.print("Coordinates in \(c).") }
            try write(ed, url, "GeoJSON", { try text.write(to: url, atomically: true, encoding: .utf8) })
        }
    }

    static var pointsImport: CommandDef {
        CommandDef("POINTSIMPORT", aliases: ["CSVPOINTS", "PTIMPORT", "IMPORTPOINTS"], category: "File",
                   summary: "Imports survey points from CSV/TSV/TXT (X,Y[,Z][,name] with or without header, or P,N,E,Z,D).") { ed in
            let url = try await path(ed, "Enter points file name")
            var o = PointImportOptions()
            o.layout = try await ed.getKeyword("Column order [Auto/XYZ/PNEZD/PENZD/NEZ/ENZ]", ["Auto", "XYZ", "PNEZD", "PENZD", "NEZ", "ENZ"], defaultValue: "Auto")
            if o.layout == "Auto" || o.layout == "XYZ" { o.layout = nil }
            o.labels = try await ed.getYesNo("Add name labels?", defaultValue: false)
            o.labelHeight = ed.settings.textHeight
            do {
                let r = PointTable.importPoints(try FileImport.readText(url), options: o)
                guard !r.entities.isEmpty else { throw CommandError.invalid("No points found in \(url.lastPathComponent).") }
                var ids: [EntityID] = []
                for e in r.entities { ids.append(ed.doc.add(e)) }
                ed.selection = Set(ids)
                var pointCount = 0
                for e in r.entities { if case .point = e.geometry { pointCount += 1 } }
                let skippedNote: String = r.skipped > 0 ? " (\(r.skipped) rows skipped)" : ""
                ed.print("Imported \(pointCount) points\(skippedNote).")
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid("Cannot import: \(error.localizedDescription)") }
        }
    }

    static var pointsExport: CommandDef {
        CommandDef("POINTSEXPORT", aliases: ["PTEXPORT", "EXPORTPOINTS"], category: "File", summary: "Writes point entities (selection or all) to CSV: name,x,y,z,code,layer.", modifies: false) { ed in
            let url = try await path(ed, "Enter CSV file name")
            let text = PointTable.exportPoints(ed.doc, ids: ed.selection.isEmpty ? nil : ed.selection, delimiter: url.pathExtension.lowercased() == "tsv" ? "\t" : ",")
            try write(ed, url, "points", { try text.write(to: url, atomically: true, encoding: .utf8) })
        }
    }

    static var export3MF: CommandDef {
        CommandDef("EXPORT3MF", aliases: ["3MFOUT", "3MFEXPORT"], category: "File", summary: "Exports the 3D model as a 3MF package (millimetres, one object per element).", modifies: false) { ed in
            let url = try await path(ed, "Enter 3MF file name")
            try write(ed, url, "3MF", { try FileImport.export(ed.doc, to: url, format: "3mf") })
        }
    }

    static var usdExport: CommandDef {
        CommandDef("USDEXPORT", aliases: ["USDZEXPORT", "USDAEXPORT", "USDZOUT", "USDOUT"], category: "File",
                   summary: "Exports the 3D model as USD: .usda text or .usdz package (UsdPreviewSurface materials).", modifies: false) { ed in
            var url = try await path(ed, "Enter USD file name (.usdz or .usda)")
            if url.pathExtension.isEmpty { url.appendPathExtension("usdz") }
            let f = url.pathExtension.lowercased() == "usdz" ? "usdz" : "usda"
            try write(ed, url, f.uppercased(), { try FileImport.export(ed.doc, to: url, format: f) })
        }
    }

    static var dxfOutVersion: CommandDef {
        CommandDef("DXFOUTVERSION", aliases: ["DXFSAVEAS", "DXFVERSIONOUT", "DXF2018OUT"], category: "File",
                   summary: "Writes an ASCII DXF of a chosen version: R12, R2000, R2004, R2007, R2010, R2013 or R2018 (AC1032, UTF-8 text).", modifies: false) { ed in
            let names = DXFVersion.allCases.map { $0.rawValue }
            let v = try await ed.getKeyword("DXF version [" + names.joined(separator: "/") + "]", names, defaultValue: "R2018") ?? "R2018"
            guard let ver = DXFVersion.parse(v) else { throw CommandError.invalid("Unknown DXF version \(v).") }
            var url = try await path(ed, "Enter DXF file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("dxf") }
            let text = DXFWriter.write(ed.doc, version: ver)
            try write(ed, url, "DXF \(ver.rawValue)", { try text.write(to: url, atomically: true, encoding: .utf8) })
            let issues = DXFConformance.audit(text)
            if issues.isEmpty { ed.print("DXF audit: structure, handles and table references are valid.") }
            else { for i in issues.prefix(20) { ed.print("DXF audit: \(i)") } }
        }
    }

    static var ifcXMLOut: CommandDef {
        CommandDef("IFCXMLOUT", aliases: ["IFCXMLEXPORT", "EXPORTIFCXML"], category: "File",
                   summary: "Exports the building model as ifcXML (IFC4, ISO 10303-28 XML encoding); a .zip or .ifczip name writes an IfcZIP holding the ifcXML.", modifies: false) { ed in
            var url = try await path(ed, "Enter ifcXML file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("ifcXML") }
            let zip = ["zip", "ifczip"].contains(url.pathExtension.lowercased())
            try write(ed, url, "ifcXML", {
                let xml = try IFCXML.fromSTEP(IFCExporter.export(doc: ed.doc, meshes: MeshBuilder.build(doc: ed.doc)))
                if zip { try IFCZip.writeXML(xml, name: url.deletingPathExtension().lastPathComponent).write(to: url, options: .atomic) }
                else { try xml.write(to: url, atomically: true, encoding: .utf8) }
            })
        }
    }

    static var lazConverter: CommandDef {
        CommandDef("LAZCONVERTER", aliases: ["LAZSETUP", "LASZIP"], category: "File",
                   summary: "Shows or sets the LAZ decompressor used to import .laz point clouds (laszip, pdal or las2las; stored in the drawing).") { ed in
            if let t = LAZConverter.find(override: ed.doc.variable("LAZCONVERTER")) { ed.print("LAZ decompressor: \(t.path) (\(t.kind.rawValue)).") }
            else { ed.print("No LAZ decompressor found. " + LAZConverter.guidance) }
            guard let p = try await ed.getWord("Enter decompressor path <keep>"), !p.isEmpty else { return }
            let path = (p as NSString).expandingTildeInPath
            guard let t = LAZConverter.tool(at: path) else { throw CommandError.invalid("\(path) is not an executable file.") }
            ed.doc.setVariable("LAZCONVERTER", path)
            ed.print("LAZ decompressor set to \(t.path).")
        }
    }

    static var dxfR12Out: CommandDef {
        CommandDef("DXFR12OUT", aliases: ["DXFOUTR12", "SAVEASR12", "DXF12"], category: "File",
                   summary: "Writes a DXF R12 (AC1009) file for older CAD/CAM software (splines, ellipses, hatches and MText are converted).", modifies: false) { ed in
            let url = try await path(ed, "Enter DXF file name")
            try write(ed, url, "DXF R12", { try FileImport.export(ed.doc, to: url, format: "dxf12") })
        }
    }
}
