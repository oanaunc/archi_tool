// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for the additional exchange formats: DWG (through an installed converter), STEP, PLY, point clouds,
// shapefiles, OpenStreetMap, elevation grids, HP-GL/2, XLSX schedules and IfcZIP.
import Foundation

public enum ExchangeCommands {
    public static var all: [CommandDef] { [dwgIn, dwgOut, dwgConverter, stepIn, stepOut, plyOut, pointCloudImport, shpImport, osmImport, demImport,
                                           hpglOut, xlsxOut, xlsxIn, ifcZipOut, gbxmlOut, cobieOut, daeOut, cityJSONImport, idsCheck] }

    @MainActor static func addEntities(_ ed: Editor, _ ents: [Entity]) -> [EntityID] {
        var ids: [EntityID] = []
        for e in ents { ed.doc.ensureLayer(e.layer); ids.append(ed.doc.add(e)) }
        ed.selection = Set(ids)
        return ids
    }

    @MainActor static func fail(_ url: URL, _ error: Error) -> CommandError {
        if let c = error as? CommandError { return c }
        return CommandError.invalid("Cannot read \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
    }

    static var dwgIn: CommandDef {
        CommandDef("DWGIN", aliases: ["DWGIMPORT", "IMPORTDWG"], category: "File",
                   summary: "Imports a DWG drawing through an installed converter (ODA File Converter or LibreDWG); explains how to get one if none is installed.") { ed in
            let url = try await IOCommands.path(ed, "Enter DWG file name")
            guard DWGConverter.find(override: ed.doc.variable("DWGCONVERTER")) != nil else { throw CommandError.invalid(DWGConverter.guidance) }
            try IOCommands.runImport(ed, url, format: "dwg")
        }
    }

    static var dwgOut: CommandDef {
        CommandDef("DWGOUT", aliases: ["DWGEXPORT", "SAVEASDWG"], category: "File",
                   summary: "Writes a DWG file (DXF converted by the installed ODA File Converter or LibreDWG).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter DWG file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("dwg") }
            guard let tool = DWGConverter.find(override: ed.doc.variable("DWGCONVERTER")) else { throw CommandError.invalid(DWGConverter.guidance) }
            let v = tool.kind == .oda ? (try await ed.getKeyword("DWG version [2018/2013/2010/2007/2004/2000]", ["2018", "2013", "2010", "2007", "2004", "2000"], defaultValue: "2018") ?? "2018") : "2018"
            try IOCommands.write(ed, url, "DWG", { try DWGConverter.write(ed.doc, to: url, version: v, converter: ed.doc.variable("DWGCONVERTER")) })
        }
    }

    static var dwgConverter: CommandDef {
        CommandDef("DWGCONVERTER", aliases: ["DWGSETUP", "ODACONVERTER"], category: "File",
                   summary: "Shows or sets the DWG converter used by DWGIN/DWGOUT (path to ODAFileConverter or dwg2dxf; stored in the drawing).") { ed in
            if let t = DWGConverter.find(override: ed.doc.variable("DWGCONVERTER")) { ed.print("DWG converter: \(t.path) (\(t.kind == .oda ? "ODA File Converter" : "LibreDWG")).") }
            else { ed.print("No DWG converter found. " + DWGConverter.guidance) }
            guard let p = try await ed.getWord("Enter converter path <keep>"), !p.isEmpty else { return }
            let path = (p as NSString).expandingTildeInPath
            guard let t = DWGConverter.tool(at: path) else { throw CommandError.invalid("\(path) is not an executable file.") }
            ed.doc.setVariable("DWGCONVERTER", path)
            ed.print("DWG converter set to \(t.path).")
        }
    }

    static var stepIn: CommandDef {
        CommandDef("STEPIN", aliases: ["STEPIMPORT", "STPIN", "IMPORTSTEP"], category: "File",
                   summary: "Imports polyhedral geometry from a STEP (AP203/AP214/AP242) file as mesh solids (planar faces; curved B-rep surfaces are skipped).") { ed in
            let url = try await IOCommands.path(ed, "Enter STEP file name")
            try IOCommands.runImport(ed, url, format: "step")
        }
    }

    static var stepOut: CommandDef {
        CommandDef("STEPOUT", aliases: ["STEPEXPORT", "STPOUT", "EXPORTSTEP"], category: "File",
                   summary: "Exports the 3D model as STEP AP214 faceted B-reps (one solid per element, millimetres, with colours).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter STEP file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("step") }
            try IOCommands.write(ed, url, "STEP", { try FileImport.export(ed.doc, to: url, format: "step") })
        }
    }

    static var plyOut: CommandDef {
        CommandDef("PLYOUT", aliases: ["PLYEXPORT", "EXPORTPLY"], category: "File",
                   summary: "Exports the 3D model as an ASCII PLY mesh (millimetres, Z up, vertex colours from materials).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter PLY file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("ply") }
            try IOCommands.write(ed, url, "PLY", { try FileImport.export(ed.doc, to: url, format: "ply") })
        }
    }

    static let unitNames = ["Meters", "Centimeters", "Millimeters", "Feet", "Inches"]
    static let mmPer: [String: Double] = ["Meters": 1000, "Centimeters": 10, "Millimeters": 1, "Inches": 25.4, "Feet": 304.8]

    static var pointCloudImport: CommandDef {
        CommandDef("POINTCLOUDIMPORT", aliases: ["PCIMPORT", "IMPORTCLOUD", "XYZIMPORT", "PTSIMPORT", "POINTCLOUD"], category: "File",
                   summary: "Imports a point cloud (XYZ, PTS or PLY ASCII/binary) as point entities with colours, decimated to a point budget and/or a voxel grid.") { ed in
            let url = try await IOCommands.path(ed, "Enter point cloud file name (.xyz, .pts, .ply, .txt)")
            let u = try await ed.getKeyword("Specify file units", unitNames, defaultValue: "Meters") ?? "Meters"
            var o = PointCloudOptions(scale: (mmPer[u] ?? 1000) / ed.doc.units.mm)
            o.maxPoints = try await ed.getInteger("Maximum number of points (0 = all)", defaultValue: o.maxPoints) ?? o.maxPoints
            o.voxel = try await ed.getPositive("Voxel size for thinning (0 = off)", defaultValue: 0, allowZero: true)
            do {
                let r = try PointCloudStream.load(url, options: o)
                let ids = addEntities(ed, r.entities)
                ed.print("Imported \(ids.count) of \(r.sampled ? "about " : "")\(r.total) points from \(url.lastPathComponent) on layer \(o.layer)\(r.sampled ? " (large file sampled out of core)" : "").")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw fail(url, error) }
        }
    }

    static var shpImport: CommandDef {
        CommandDef("SHPIMPORT", aliases: ["SHAPEFILEIMPORT", "IMPORTSHP", "SHPIN"], category: "File",
                   summary: "Imports an ESRI shapefile (.shp with .dbf attributes and .prj CRS: WGS84, UTM, Web Mercator) as points/polylines; elevation attributes become contour elevations.") { ed in
            let url = try await IOCommands.path(ed, "Enter shapefile name (.shp)")
            var o = GISImportOptions()
            o.masses = try await ed.getYesNo("Extrude polygons with a height attribute as masses?", defaultValue: false)
            do {
                let ents = try Shapefile.load(url, doc: ed.doc, options: o)
                guard !ents.isEmpty else { throw CommandError.invalid("No shapes in \(url.lastPathComponent).") }
                let ids = addEntities(ed, ents)
                ed.print("Imported \(ids.count) features from \(url.lastPathComponent).")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw fail(url, error) }
        }
    }

    static var osmImport: CommandDef {
        CommandDef("OSMIMPORT", aliases: ["OPENSTREETMAP", "IMPORTOSM", "OSMIN"], category: "File",
                   summary: "Imports an OpenStreetMap .osm extract around the project location: building outlines (optionally extruded to their height), roads, water and areas.") { ed in
            let url = try await IOCommands.path(ed, "Enter OSM file name (.osm)")
            var o = GISImportOptions()
            o.masses = try await ed.getYesNo("Create 3D building masses?", defaultValue: true)
            do {
                let ents = try OSMImporter.entities(try Data(contentsOf: url), doc: ed.doc, options: o)
                guard !ents.isEmpty else { throw CommandError.invalid("No buildings, roads or areas in \(url.lastPathComponent).") }
                let ids = addEntities(ed, ents)
                ed.print("Imported \(ents.filter { $0.layer == "OSM-BUILDINGS" }.count) buildings (\(ids.count) objects) around \(fmt(ed.doc.info.latitude, 5)), \(fmt(ed.doc.info.longitude, 5)).")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw fail(url, error) }
        }
    }

    static var demImport: CommandDef {
        CommandDef("DEMIMPORT", aliases: ["ASCIIGRID", "GRIDTERRAIN", "ELEVATIONIMPORT", "ASCIMPORT"], category: "Site",
                   summary: "Creates a toposurface from an ESRI ASCII elevation grid (.asc, metres), subsampled to a point budget.") { ed in
            let url = try await IOCommands.path(ed, "Enter ASCII grid file name (.asc)")
            let maxPts = try await ed.getInteger("Maximum number of terrain points", defaultValue: 20_000) ?? 20_000
            let iv = try await ed.getPositive("Specify contour interval", defaultValue: ed.variableDouble("CONTOURINTERVAL", 1000 / ed.doc.units.mm))
            do {
                let g = try ElevationGrid.parse(try FileImport.readText(url))
                let e = try ElevationGrid.topo(g, unitMM: ed.doc.units.mm, interval: iv, maxPoints: max(maxPts, 4))
                let id = addEntities(ed, [e]).first ?? 0
                ed.doc.setVariable("CONTOURINTERVAL", fmt(iv))
                ed.print("Toposurface #\(id) from a \(g.ncols)×\(g.nrows) grid (\(fmt(g.cell, 2)) m cells, lower-left \(fmt(g.xll, 2)), \(fmt(g.yll, 2)) placed at 0,0).")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch { throw fail(url, error) }
        }
    }

    static var hpglOut: CommandDef {
        CommandDef("HPGLOUT", aliases: ["PLTOUT", "HPGLEXPORT", "HPGL"], category: "File",
                   summary: "Writes the current level's plan as HP-GL/2 (.plt) for plotters and cutters, at a plot scale.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter PLT file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("plt") }
            let sc = try await ed.getPositive("Plot scale 1:", defaultValue: Double(ed.doc.variable("PLOTSCALE") ?? "") ?? 100)
            let entries = DrawListBuilder.entries(doc: ed.doc, options: DrawOptions(level: ed.doc.currentLevel))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            let text = HPGLExporter.export(entries, bounds: b, scale: sc, unitMM: ed.doc.units.mm)
            try IOCommands.write(ed, url, "HP-GL/2", { try text.write(to: url, atomically: true, encoding: .ascii) })
            ed.print("Plot size \(fmt(b.width * ed.doc.units.mm / sc, 0)) × \(fmt(b.height * ed.doc.units.mm / sc, 0)) mm at 1:\(fmt(sc)).")
        }
    }

    static var xlsxOut: CommandDef {
        CommandDef("XLSXOUT", aliases: ["XLSXEXPORT", "SCHEDULEXLSX", "EXPORTXLSX"], category: "File",
                   summary: "Writes the schedules (walls, doors, windows, rooms, slabs, takeoff, areas by level) to an Excel .xlsx workbook.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter XLSX file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("xlsx") }
            try IOCommands.write(ed, url, "XLSX", { try XLSX.schedules(ed.doc).write(to: url, options: .atomic) })
        }
    }

    static var xlsxIn: CommandDef {
        CommandDef("XLSXIN", aliases: ["XLSXIMPORT", "IMPORTXLSX", "EXCELIN"], category: "File",
                   summary: "Places the sheets of an .xlsx workbook as table entities.") { ed in
            let url = try await IOCommands.path(ed, "Enter XLSX file name")
            let p = try await ed.requirePoint("Specify insertion point")
            do {
                let sheets = try XLSX.read(try Data(contentsOf: url))
                let ents = XLSXTables.entities(sheets, unitMM: ed.doc.units.mm, origin: p)
                guard !ents.isEmpty else { throw CommandError.invalid("The workbook has no data.") }
                let ids = addEntities(ed, ents)
                ed.print("Placed \(ids.count) table(s) from \(sheets.count) sheet(s).")
            } catch { throw fail(url, error) }
        }
    }

    static var ifcZipOut: CommandDef {
        CommandDef("IFCZIPOUT", aliases: ["IFCZIPEXPORT", "EXPORTIFCZIP"], category: "File",
                   summary: "Exports the model as IfcZIP (compressed IFC4).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter IfcZIP file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("ifczip") }
            try IOCommands.write(ed, url, "IfcZIP", { try FileImport.export(ed.doc, to: url, format: "ifczip") })
        }
    }

    static var gbxmlOut: CommandDef {
        CommandDef("GBXMLOUT", aliases: ["GBXMLEXPORT", "EXPORTGBXML", "ENERGYMODELOUT"], category: "File",
                   summary: "Exports the energy model as gbXML 0.37: spaces, exterior/interior walls with windows and doors, roofs, floors, constructions with U-values.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter gbXML file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("xml") }
            try IOCommands.write(ed, url, "gbXML", { try FileImport.export(ed.doc, to: url, format: "gbxml") })
        }
    }

    static var cobieOut: CommandDef {
        CommandDef("COBIEOUT", aliases: ["COBIEEXPORT", "EXPORTCOBIE", "COBIE"], category: "File",
                   summary: "Exports a COBie 2.4 spreadsheet (.xlsx): contact, facility, floors, spaces, types, components (doors, windows, equipment) and attributes.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter COBie file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("xlsx") }
            try IOCommands.write(ed, url, "COBie", { try FileImport.export(ed.doc, to: url, format: "cobie") })
        }
    }

    static var daeOut: CommandDef {
        CommandDef("DAEOUT", aliases: ["COLLADAOUT", "COLLADAEXPORT", "EXPORTDAE"], category: "File",
                   summary: "Exports the 3D model as COLLADA 1.4.1 (.dae, metres, Z up, Phong materials).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter DAE file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("dae") }
            try IOCommands.write(ed, url, "COLLADA", { try FileImport.export(ed.doc, to: url, format: "dae") })
        }
    }

    static var cityJSONImport: CommandDef {
        CommandDef("CITYJSONIMPORT", aliases: ["CITYJSONIN", "CITYMODELIMPORT", "IMPORTCITYJSON"], category: "File",
                   summary: "Imports a CityJSON city model (buildings, terrain, roads … at their highest LoD) as mesh solids per city object with attributes.") { ed in
            let url = try await IOCommands.path(ed, "Enter CityJSON file name")
            try IOCommands.runImport(ed, url, format: "cityjson")
        }
    }

    static var idsCheck: CommandDef {
        CommandDef("IDSCHECK", aliases: ["IDSVALIDATE", "CHECKIDS"], category: "File",
                   summary: "Checks the model's IFC export (or an IFC file) against an Information Delivery Specification (.ids): entity, attribute, property and material requirements.", modifies: false) { ed in
            let idsURL = try await IOCommands.path(ed, "Enter IDS file name")
            let p = try await ed.getWord("Enter IFC file name <current model>")
            do {
                let specs = try IDSValidator.parse(try Data(contentsOf: idsURL))
                let ifc = (p?.isEmpty ?? true) ? IFCExporter.export(doc: ed.doc, meshes: MeshBuilder.build(doc: ed.doc)) : try FileImport.readText(IOCommands.resolve(ed, p!))
                let results = try IDSValidator.validate(ids: specs, ifc: ifc)
                var failedGuids = Set<String>()
                let f = try STEPParser.parse(ifc)
                for r in results {
                    ed.print("\(r.passed ? "PASS" : "FAIL") \(r.specification): \(r.applicable) applicable, \(r.failed.count) failing" + (r.notes.isEmpty ? "" : " (\(r.notes.joined(separator: "; ")))"))
                    for (sid, why) in r.failed.sorted(by: { $0.key < $1.key }).prefix(20) {
                        let e = f.entities[sid]
                        if let g = e?[0].string { failedGuids.insert(g) }
                        ed.print("   #\(sid) \(e?.type ?? "") \(e?[2].string ?? ""): \(why.joined(separator: "; "))")
                    }
                }
                // Select the model elements that failed (element GUIDs as exported).
                ed.selection = Set(ed.doc.elements.filter { failedGuids.contains($0.props["ifcGuid"] ?? IFCExporter.guid("element:\($0.id)")) }.map(\.id))
                ed.print("\(results.filter(\.passed).count) of \(results.count) specification(s) pass.")
            } catch { throw fail(idsURL, error) }
        }
    }
}
