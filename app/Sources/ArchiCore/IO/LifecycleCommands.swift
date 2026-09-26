// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for the file life cycle and new exchange formats: Save a Copy, file upgrades, round-trip checks, templates,
// Spotlight metadata, PDF underlays, pasted/dropped content, OpenCASCADE BREP and E57 point clouds.
import Foundation

public enum LifecycleCommands {
    public static var all: [CommandDef] { [saveCopy, upgradeFile, saveCheck, templateOut, templateIn, fileMetadata, pdfAttach, pdfUnderlays,
                                           dropImport, brepOut, brepIn, e57In, e57Out, CoEdit.command, BCFServerCommands.command, ConflictCopies.command] }

    static func fail(_ e: Error) -> CommandError { CommandError.invalid((e as? LocalizedError)?.errorDescription ?? "\(e)") }

    static var saveCopy: CommandDef {
        CommandDef("SAVECOPY", aliases: ["SAVEACOPY", "COPYSAVE"], category: "File",
                   summary: "Saves a copy of the drawing under another name or format (.archi, .architemplate, .dxf, .ifc, …); the open drawing keeps its name and unsaved state.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter copy file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("archi") }
            do { try ArchiFile.saveCopy(ed.doc, to: url) } catch { throw fail(error) }
            ed.print("Saved a copy as \(url.path).")
        }
    }

    static var upgradeFile: CommandDef {
        CommandDef("UPGRADEFILE", aliases: ["FILEUPGRADE", "MIGRATEFILE"], category: "File",
                   summary: "Upgrades older .archi / .architemplate files (a file or every file in a folder) to the current format, keeping the originals as .vN.archi.bak.", modifies: false) { ed in
            let url = try await IOCommands.path(ed, "Enter file or folder")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { throw CommandError.invalid("\(url.path) does not exist.") }
            let files = isDir.boolValue
                ? ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter { ["archi", ArchiTemplate.fileExtension].contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
                : [url]
            var upgraded = 0
            for f in files {
                do {
                    let r = try ArchiFile.upgradeFile(f)
                    if r.from != r.to { upgraded += 1; ed.print("\(f.lastPathComponent): format \(r.from) → \(r.to)") }
                } catch { ed.print("\(f.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            }
            ed.print("\(upgraded) of \(files.count) file(s) upgraded to format \(ArchiDocument.currentFormatVersion).")
        }
    }

    static var saveCheck: CommandDef {
        CommandDef("SAVECHECK", aliases: ["ROUNDTRIPCHECK", "CHECKSAVE"], category: "File",
                   summary: "Verifies that saving and reopening the drawing gives an identical document (lists any section that would change).", modifies: false) { ed in
            let diffs: [String]
            do { diffs = try ArchiFile.roundTripDifferences(ed.doc) } catch { throw fail(error) }
            if diffs.isEmpty { ed.print("Round trip OK: the saved drawing reopens identical (\(ed.doc.entities.count) objects, \(ed.doc.elements.count) elements).") }
            else { ed.print("Round trip changes: " + diffs.joined(separator: ", ")) }
        }
    }

    static var templateOut: CommandDef {
        CommandDef("TEMPLATEOUT", aliases: ["EXPORTTEMPLATE", "WRITETEMPLATE"], category: "File",
                   summary: "Writes the drawing as a template file (.architemplate) with a name and description; everything in the drawing is kept.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter template file name")
            if url.pathExtension.lowercased() != ArchiTemplate.fileExtension { url.appendPathExtension(ArchiTemplate.fileExtension) }
            let desc = try await ed.getString("Description <none>") ?? ""
            do { try ArchiTemplate.save(ed.doc, to: url, description: desc) } catch { throw fail(error) }
            ed.print("Template written: \(url.path).")
        }
    }

    static var templateIn: CommandDef {
        CommandDef("TEMPLATEIN", aliases: ["LOADTEMPLATE", "STARTFROMTEMPLATE"], category: "File",
                   summary: "Replaces the drawing with a new untitled drawing started from a template file (undoable).") { ed in
            let url = try await IOCommands.path(ed, "Enter template file name")
            let t: ArchiTemplate.Loaded
            do { t = try ArchiTemplate.decode(Data(contentsOf: url)) } catch { throw fail(error) }
            ed.selection = []
            ed.doc = ArchiTemplate.newDocument(from: t.document)
            ed.fileURL = nil
            ed.print("New drawing from template \(t.info.name)\(t.info.description.isEmpty ? "" : " — " + t.info.description).")
        }
    }

    static var fileMetadata: CommandDef {
        CommandDef("FILEMETADATA", aliases: ["SPOTLIGHTINFO", "MDITEMS"], category: "File",
                   summary: "Lists the Spotlight metadata of the drawing or a file (title, authors, layers, levels, rooms, searchable text).", modifies: false) { ed in
            let p = try await ed.getWord("Enter file <this drawing>")
            let a: [String: Any]
            do { a = try p.map { try SpotlightMetadata.attributes(of: IOCommands.resolve(ed, $0)) } ?? SpotlightMetadata.attributes(ed.doc) } catch { throw fail(error) }
            for k in a.keys.sorted() where k != "kMDItemTextContent" {
                let v = a[k]!
                ed.print("\(k): " + ((v as? [String])?.joined(separator: ", ") ?? "\(v)"))
            }
            ed.print("kMDItemTextContent: \((a["kMDItemTextContent"] as? String ?? "").count) characters")
        }
    }

    static var pdfAttach: CommandDef {
        CommandDef("PDFATTACH", aliases: ["ATTACHPDF", "PDFUNDERLAY"], category: "Insert",
                   summary: "Attaches a PDF page as an underlay (by reference, faded and locked, with object snaps on its geometry) at a drawing scale and insertion point.") { ed in
            let url = try await IOCommands.path(ed, "Enter PDF file name")
            let page = try await ed.getInteger("Page number <1>", defaultValue: 1) ?? 1
            let scale = try await ed.getReal("Drawing scale 1: <1>", defaultValue: 1).value ?? 1
            let at = try await ed.getPoint("Insertion point (page lower-left) <0,0>").point ?? .zero
            var d = ed.doc
            let id: EntityID
            do { id = try PDFUnderlay.attach(url, page: page, into: &d, at: at, scale: scale) } catch { throw fail(error) }
            ed.doc = d
            ed.selection = [id]
            ed.print("Attached \(url.lastPathComponent) page \(page) (\(PDFUnderlay.list(d).first { $0.id == id }?.objects ?? 0) objects) on layer \(PDFUnderlay.layer).")
        }
    }

    static var pdfUnderlays: CommandDef {
        CommandDef("PDFUNDERLAYS", aliases: ["PDFRELOAD", "PDFDETACH", "PDFADJUST"], category: "Insert",
                   summary: "Manages PDF underlays: List, Reload (re-read changed PDFs), Detach, Fade (0–90 %).") { ed in
            let k = try await ed.getKeyword("Option [List/Reload/Detach/Fade]", ["List", "Reload", "Detach", "Fade"], defaultValue: "List") ?? "List"
            let list = PDFUnderlay.list(ed.doc)
            switch k {
            case "Fade":
                let f = try await ed.getReal("Fade percent <50>", defaultValue: 50).value ?? 50
                PDFUnderlay.setFade(f / 100, in: &ed.doc)
                ed.print("Underlay fade \(fmt(f, 0)) %.")
            case "Reload", "Detach":
                guard !list.isEmpty else { ed.print("No PDF underlays."); return }
                let sel = Set(ed.selection)
                var targets = list.filter { sel.contains($0.id) }
                if targets.isEmpty { targets = k == "Reload" ? list : [] }
                if targets.isEmpty, let id = try await ed.getEntity("Select underlay"), let u = list.first(where: { $0.id == id }) { targets = [u] }
                var d = ed.doc
                for u in targets {
                    if k == "Reload" {
                        do { let n = try PDFUnderlay.reload(u.id, in: &d); ed.print("Reloaded \(URL(fileURLWithPath: u.path).lastPathComponent) p\(u.page): \(n) objects.") }
                        catch { ed.print("\(u.path): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
                    } else { PDFUnderlay.detach(u.id, in: &d); ed.print("Detached #\(u.id).") }
                }
                ed.doc = d
            default:
                if list.isEmpty { ed.print("No PDF underlays."); return }
                for u in list { ed.print("#\(u.id)  \(u.path)  page \(u.page)  1:\(fmt(u.scale, 2))  \(u.objects) objects") }
            }
        }
    }

    static var dropImport: CommandDef {
        CommandDef("DROPIMPORT", aliases: ["IMPORTDROPPED", "PASTEFILE"], category: "Insert",
                   summary: "Imports files as if dropped on the canvas: images and PDFs are attached, vector/3D exchange formats merged, side by side from a point.") { ed in
            var urls: [URL] = []
            while let p = try await ed.getWord(urls.isEmpty ? "Enter file name" : "Enter file name <done>"), !p.isEmpty { urls.append(IOCommands.resolve(ed, p)) }
            guard !urls.isEmpty else { return }
            let at = try await ed.getPoint("Insertion point <0,0>").point ?? .zero
            var d = ed.doc
            let r = ExternalContent.drop(urls, into: &d, at: at)
            ed.doc = d
            ed.selection = Set(r.flatMap { $0.result?.ids ?? [] })
            for x in r { ed.print("\(x.url.lastPathComponent): " + (x.result?.summary ?? x.error ?? "")) }
        }
    }

    @MainActor static func importAs(_ ed: Editor, _ format: String, _ label: String) async throws {
        let url = try await IOCommands.path(ed, "Enter \(label) file name")
        var d = ed.doc
        let (m, s): (DocumentMerge.Result, String)
        do { (m, s) = try FileImport.importFile(url, into: &d, format: format) } catch { throw fail(error) }
        ed.doc = d
        ed.selection = Set(m.allIDs)
        ed.print("Imported \(s).")
    }

    @MainActor static func exportAs(_ ed: Editor, _ format: String, _ ext: String, _ label: String) async throws {
        var url = try await IOCommands.path(ed, "Enter \(label) file name")
        if url.pathExtension.isEmpty { url.appendPathExtension(ext) }
        do { _ = try FileImport.export(ed.doc, to: url, format: format) } catch { throw fail(error) }
        ed.print("Wrote \(url.path).")
    }

    static var brepOut: CommandDef {
        CommandDef("BREPOUT", aliases: ["BREPEXPORT", "EXPORTBREP", "OCCTOUT"], category: "File",
                   summary: "Exports the 3D model as an OpenCASCADE BREP file (shells of planar faces, millimetres) for FreeCAD, Salome and other OCCT tools.", modifies: false) { ed in
            try await exportAs(ed, "brep", "brep", "BREP")
        }
    }
    static var brepIn: CommandDef {
        CommandDef("BREPIN", aliases: ["BREPIMPORT", "IMPORTBREP", "OCCTIN"], category: "File",
                   summary: "Imports an OpenCASCADE BREP file (FreeCAD .brep/.brp) as mesh solids: stored triangulations are used, other faces are triangulated from their edges.") { ed in
            try await importAs(ed, "brep", "BREP")
        }
    }
    static var e57In: CommandDef {
        CommandDef("E57IN", aliases: ["E57IMPORT", "IMPORTE57"], category: "File",
                   summary: "Imports an ASTM E57 point cloud (all scans, poses applied, colour and intensity) as points.") { ed in
            try await importAs(ed, "e57", "E57")
        }
    }
    static var e57Out: CommandDef {
        CommandDef("E57OUT", aliases: ["E57EXPORT", "EXPORTE57"], category: "File",
                   summary: "Exports the drawing's points (with their z, colour and intensity) as an ASTM E57 point cloud.", modifies: false) { ed in
            try await exportAs(ed, "e57", "e57", "E57")
        }
    }
}
