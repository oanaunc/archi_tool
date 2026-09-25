// Oanarina Archi Tool — GPL-3.0-or-later
// Import/export commands: KML/KMZ with geolocation, layered SVG, raster images (world files, two-point scaling) and
// gbXML/COBie schema checks.
import Foundation

public enum MoreIOCommands {
    public static var all: [CommandDef] { [kmlOut, svgLayersOut, imageImport, imageScale, exchangeCheck, eTransmit, batch] }

    static var eTransmit: CommandDef {
        CommandDef("ETRANSMIT", aliases: ["PACKANDGO", "TRANSMIT", "ARCHIVEPACKAGE"], category: "File",
                   summary: "Packs the drawing with its referenced images, material textures and external references (paths rewritten) and a transmittal report into a ZIP.", modifies: false) { ed in
            let name = (ed.fileURL?.deletingPathExtension().lastPathComponent).flatMap { $0.isEmpty ? nil : $0 } ?? "Drawing"
            var url = try await IOCommands.path(ed, "Enter package file name <\(name).zip>")
            if url.pathExtension.isEmpty { url.appendPathExtension("zip") }
            let (data, rep) = ETransmit.pack(ed.doc, documentURL: ed.fileURL, name: name)
            do { try data.write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write \(url.path)") }
            ed.print("Packed \(name).archi with \(rep.files.count) referenced file(s) into \(url.path).")
            if !rep.missing.isEmpty { ed.print("Missing: " + rep.missing.joined(separator: ", ")) }
        }
    }

    static var batch: CommandDef {
        CommandDef("BATCH", aliases: ["BATCHJOBS", "SCRIPTPRO", "RUNBATCH"], category: "Tools",
                   summary: "Runs a JSON batch job file over many drawings: open/import, command lines or a script, outputs in any export format, analysis reports and save (the open drawing is not changed).", modifies: false) { ed in
            let url = try await IOCommands.path(ed, "Enter batch job file (.json)")
            let parsed: (jobs: [BatchJob], stopOnError: Bool)
            do { parsed = try BatchJob.parse(try Data(contentsOf: url)) } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read \(url.lastPathComponent)") }
            let r = await BatchRunner.run(parsed.jobs, stopOnError: parsed.stopOnError, base: url.deletingLastPathComponent(), progress: { ed.print($0) })
            ed.print("Batch: \(r["succeeded"] as? Int ?? 0) succeeded, \(r["failed"] as? Int ?? 0) failed.")
        }
    }

    static var kmlOut: CommandDef {
        CommandDef("KMLOUT", aliases: ["KMZOUT", "KMLEXPORT", "KMZEXPORT", "GOOGLEEARTH"], category: "File",
                   summary: "Exports KML or KMZ placed at the project location (GEOGRAPHICLOCATION / project latitude, longitude, north angle): extruded walls, slabs, roofs and rooms by level, linework by layer; KMZ also carries the 3D model (COLLADA).", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter KML/KMZ file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("kmz") }
            let f = url.pathExtension.lowercased() == "kml" ? "kml" : "kmz"
            do { _ = try FileImport.export(ed.doc, to: url, format: f) } catch { throw CommandError.invalid("Cannot write \(url.path)") }
            ed.print("Wrote \(url.path) at \(fmt(ed.doc.info.latitude, 6)), \(fmt(ed.doc.info.longitude, 6)).")
        }
    }

    static var svgLayersOut: CommandDef {
        CommandDef("SVGLAYERSOUT", aliases: ["SVGOUTLAYERS", "SVGEXPORTLAYERS", "LAYEREDSVG"], category: "File",
                   summary: "Exports the current level's plan as SVG with one group (Inkscape/Illustrator layer) per drawing layer.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter SVG file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("svg") }
            do { _ = try FileImport.export(ed.doc, to: url, format: "svglayers") } catch { throw CommandError.invalid("Cannot write \(url.path)") }
            ed.print("Wrote \(url.path).")
        }
    }

    static var imageImport: CommandDef {
        CommandDef("IMAGEIMPORT", aliases: ["IMPORTIMAGE", "RASTERIMPORT", "GEOIMAGE"], category: "Insert",
                   summary: "Inserts a PNG/JPEG/GIF/BMP/TIFF/WebP image at its pixel aspect ratio; with a world file (.pgw/.jgw/.tfw/.wld) it is georeferenced (world units WORLDUNITMM, local origin GEOORIGIN).") { ed in
            let url = try await IOCommands.path(ed, "Enter image file name")
            guard let data = try? Data(contentsOf: url), let px = ImageHeader.size(data) else { throw CommandError.invalid("\(url.lastPathComponent) is not a readable image.") }
            let hasWorld = WorldFile.candidates(for: url).contains { FileManager.default.fileExists(atPath: $0.path) }
            var im: ImageGeom
            if hasWorld, try await ed.getYesNo("World file found: place georeferenced?", defaultValue: true) {
                im = try ImagePlacement.load(url, doc: ed.doc).0
            } else {
                let p = try await ed.requirePoint("Specify insertion point")
                let w = try await ed.getPositive("Specify width <\(px.width) px at 10 mm>", base: p, defaultValue: Double(px.width) * 10 / ed.doc.units.mm)
                im = ImagePlacement.placed(path: url.path, pixels: px, origin: p, width: w)
            }
            var d = ed.doc
            d.ensureLayer("IMAGES")
            let id = d.add(Entity(layer: "IMAGES", geometry: .image(im), props: ["pixels": "\(px.width)x\(px.height)"]))
            ed.doc = d
            ed.selection = [id]
            ed.print("Image \(px.width)×\(px.height) px placed, \(fmt(im.size.x, 1)) × \(fmt(im.size.y, 1)) units.")
        }
    }

    static var imageScale: CommandDef {
        CommandDef("IMAGESCALE", aliases: ["SCALEIMAGE", "IMAGECALIBRATE", "CALIBRATE"], category: "Modify",
                   summary: "Calibrates an image: pick two points on it and enter their real distance; the image is scaled about the first point.") { ed in
            guard let id = try await ed.getEntity("Select image"), let e = ed.doc.entity(id), case .image(let im) = e.geometry else { throw CommandError.invalid("Select an image.") }
            let a = try await ed.requirePoint("Specify first point on the image")
            let b = try await ed.requirePoint("Specify second point on the image", base: a)
            let cur = a.distance(to: b)
            guard cur > 1e-9 else { throw CommandError.invalid("The points must be different.") }
            let dist = try await ed.getPositive("Enter the real distance between the points <\(fmt(cur, 2))>", defaultValue: cur)
            guard let out = ImagePlacement.scaled(im, p1: a, p2: b, distance: dist), let i = ed.doc.entityIndex(id) else { return }
            ed.doc.entities[i].geometry = .image(out)
            ed.print("Image scaled by \(fmt(dist / cur, 6)).")
        }
    }

    static var exchangeCheck: CommandDef {
        CommandDef("EXCHANGECHECK", aliases: ["GBXMLCHECK", "COBIECHECK", "VALIDATEEXPORT"], category: "File",
                   summary: "Checks the gbXML or COBie export (or a given file) against the schema's required elements, enumerations and references.", modifies: false) { ed in
            let f = try await ed.getKeyword("Format [Gbxml/Cobie]", ["Gbxml", "Cobie"], defaultValue: "Gbxml") ?? "Gbxml"
            let p = try await ed.getWord("Enter file to check <this model's export>")
            let issues: [ExchangeIssue]
            do {
                if f == "Gbxml" {
                    issues = GBXMLValidator.validate(try p.map { try FileImport.readText(IOCommands.resolve(ed, $0)) } ?? GBXMLExporter.export(ed.doc))
                } else {
                    issues = COBieValidator.validate(try XLSX.read(try p.map { try Data(contentsOf: IOCommands.resolve(ed, $0)) } ?? COBieExporter.export(ed.doc)))
                }
            } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "Cannot read the file.") }
            if issues.isEmpty { ed.print("\(f == "Gbxml" ? "gbXML" : "COBie") meets the schema requirements."); return }
            for i in issues.prefix(200) { ed.print(i.description) }
            ed.print("\(issues.count) issue(s).")
        }
    }
}
