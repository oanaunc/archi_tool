// Oanarina Archi Tool — GPL-3.0-or-later
// Rhino 3DM commands (IO-044): RHINOIN imports a .3dm file, RHINOOUT exports the drawing and model as .3dm.
import Foundation

extension ExchangeCommands {
    static var rhinoIn: CommandDef {
        CommandDef("RHINOIN", aliases: ["3DMIN", "3DMIMPORT", "IMPORT3DM", "RHINOIMPORT"], category: "File",
                   summary: "Imports a Rhino .3dm file (versions 2–8): meshes, B-reps (render meshes or tessellated trimmed faces), extrusions, surfaces, curves, points and blocks, with layers, colours, materials and units.") { ed in
            let url = try await IOCommands.path(ed, "Enter Rhino 3DM file name")
            let mode = try await ed.getKeyword("B-rep faces from", ["RenderMeshes", "Tessellate"], defaultValue: "RenderMeshes") ?? "RenderMeshes"
            var d = ed.doc
            do {
                let data = try Data(contentsOf: url)
                let (src, summary) = try Rhino3DM.document(data, reference: d, options: Rhino3DM.ImportOptions(useRenderMeshes: mode == "RenderMeshes"))
                let res = DocumentMerge.merge(src, into: &d, offset: .zero, scale: 1)
                ed.doc = d
                ed.selection = Set(res.allIDs)
                ed.print("Imported \(url.lastPathComponent): \(summary).")
                ed.host?.perform(.zoomExtents, editor: ed)
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid("Cannot import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        }
    }

    static var rhinoOut: CommandDef {
        CommandDef("RHINOOUT", aliases: ["3DMOUT", "3DMEXPORT", "EXPORT3DM", "RHINOEXPORT"], category: "File",
                   summary: "Exports a Rhino .3dm (version 4) file in the drawing units: the 3D model as meshes coloured by material, drafting curves as exact lines, arcs, polylines and NURBS, with layers.", modifies: false) { ed in
            var url = try await IOCommands.path(ed, "Enter Rhino 3DM file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("3dm") }
            let (data, rep) = Rhino3DM.exportWithReport(ed.doc)
            do { try data.write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write \(url.path)") }
            ed.print("Wrote \(url.path): \(rep.meshes) meshes, \(rep.curves) curves, \(rep.layers) layers" + (rep.skipped > 0 ? " (\(rep.skipped) text/dimension/point objects not exported)." : "."))
        }
    }
}
