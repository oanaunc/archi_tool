// Oanarina Archi Tool — GPL-3.0-or-later
// Reading/writing a document by file format (shared by archi-cli, batch jobs and the BATCH command) and the batch job
// runner: each job opens or imports files into its own editor, runs command lines or a script, writes outputs and tool
// reports, and saves.
import Foundation

public enum DocumentIO {
    public struct IOError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }

    /// Opens a file as a document (.archi/.json natively, .dxf, anything FileImport reads).
    public static func read(_ url: URL) throws -> ArchiDocument {
        switch url.pathExtension.lowercased() {
        case "dxf": return try DXFReader.read(try FileImport.readText(url))
        case "archi", "json": return try ArchiFile.decode(Data(contentsOf: url))
        case "archiz": return try ArchiPackage.read(url)
        case "archit": return try ArchiText.decode(FileImport.readText(url))
        default: return try FileImport.load(url).0
        }
    }

    /// Writes the document; the format comes from `format` or the extension.
    public static func write(_ doc: ArchiDocument, to url: URL, format: String? = nil, level: Int? = nil) throws {
        let f = (format ?? url.pathExtension).lowercased()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        func text(_ s: String) throws { try s.write(to: url, atomically: true, encoding: .utf8) }
        let mm = doc.units.mm
        switch f {
        case "archi": try ArchiFile.save(doc, to: url, backup: doc.variable("ISAVEBAK") != "0")
        case "json": try ArchiFile.encode(doc).write(to: url, options: .atomic)
        case "archiz": _ = try ArchiPackage.write(doc, to: url)
        case "archit": try text(ArchiText.encode(doc))
        case "dxf": try text(DXFWriter.write(doc))
        case "svg":
            let entries = DrawListBuilder.entries(doc: doc, options: DrawOptions(level: level ?? doc.currentLevel))
            var b = entries.reduce(BBox2.empty) { $0.union($1.bounds) }
            if b.isEmpty { b = BBox2(min: .zero, max: Vec2(1000, 1000)) }
            try text(SVGExporter.exportLayered(doc: doc, entries: entries, bounds: b.expanded(by: max(b.width, b.height) * 0.02), background: nil, pixelsPerUnit: 1))
        case "ifc": try text(IFCExporter.export(doc: doc, meshes: MeshBuilder.build(doc: doc)))
        case "obj":
            let r = OBJExporter.export(MeshBuilder.build(doc: doc), materials: doc.materials, mtlFileName: url.deletingPathExtension().lastPathComponent + ".mtl", unitMM: mm)
            try text(r.obj)
            try r.mtl.write(to: url.deletingPathExtension().appendingPathExtension("mtl"), atomically: true, encoding: .utf8)
        case "stl": try text(STLExporter.export(MeshBuilder.build(doc: doc).map { FileImport.scaled($0, mm) }, name: doc.info.name))
        case "glb", "gltf": try GLTFExporter.exportGLB(MeshBuilder.build(doc: doc), materials: doc.materials, unitMM: mm).write(to: url, options: .atomic)
        case "csv": try text(ScheduleExporter.csv(doc: doc, kind: "all"))
        case "takeoff": try text(QuantityTakeoff.compute(doc).csv)
        case "pdf": throw IOError(message: "PDF output needs the app (Core Graphics); export SVG instead")
        default:
            guard try FileImport.export(doc, to: url, format: f == "usd" ? "usda" : f) else { throw IOError(message: "unsupported output format '\(f)'") }
        }
    }
}

public enum BatchRunner {
    /// Runs the jobs (each on its own editor and document); relative paths resolve against `base`. Returns a
    /// JSON-compatible summary: jobs[{name, ok, error?, written[], commandErrors, logTail, entities, elements}], failed, succeeded.
    @MainActor
    public static func run(_ jobs: [BatchJob], stopOnError: Bool, base: URL, host: EditorHost? = nil, progress: ((String) -> Void)? = nil) async -> [String: Any] {
        func url(_ p: String) -> URL {
            let e = (p as NSString).expandingTildeInPath
            return e.hasPrefix("/") ? URL(fileURLWithPath: e) : base.appendingPathComponent(e)
        }
        var results: [[String: Any]] = []
        var failed = 0
        for job in jobs {
            var r: [String: Any] = ["name": job.name]
            var written: [String] = []
            let ed = Editor()
            ed.host = host
            do {
                if let i = job.input {
                    let u = url(i)
                    ed.replaceDocument(try DocumentIO.read(u), url: u.pathExtension.lowercased() == "archi" ? u : nil)
                }
                for imp in job.imports {
                    var d = ed.doc
                    _ = try FileImport.importFile(url(imp), into: &d)
                    ed.doc = d
                }
                var lines = job.commands
                if let sp = job.script { lines += BatchJob.scriptLines(try String(contentsOf: url(sp), encoding: .utf8)) }
                var log: [String] = []
                for l in lines {
                    for c in l.components(separatedBy: .newlines) where !c.trimmingCharacters(in: .whitespaces).isEmpty { log += await ed.run(c) }
                }
                r["logTail"] = Array(log.suffix(20))
                r["commandErrors"] = log.filter { $0.hasPrefix("Error") || $0.contains("Unknown command") }.count
                for o in job.outputs {
                    let u = url(o.path)
                    try DocumentIO.write(ed.doc, to: u, format: o.format, level: o.level)
                    written.append(u.path)
                }
                for rep in job.reports {
                    let u = url(rep.path)
                    var args: [String: Any] = rep.arguments
                    if u.pathExtension.lowercased() == "csv" && args["format"] == nil { args["format"] = "csv" }
                    let out: Any
                    switch rep.tool {
                    case "takeoff": out = (args["format"] as? String) == "csv" ? QuantityTakeoff.compute(ed.doc).csv : QuantityTakeoff.compute(ed.doc).table
                    case "check_model": out = ModelChecker.check(ed.doc).map(AgentTools.issueJSON)
                    case "room_schedule": out = RoomSchedule.csv(RoomSchedule.compute(ed.doc))
                    default: out = try AgentTools.call(rep.tool, args, doc: ed.doc, resolve: url)
                    }
                    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let text: String
                    if let str = out as? String { text = str }
                    else { text = String(decoding: try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self) }
                    try text.write(to: u, atomically: true, encoding: .utf8)
                    written.append(u.path)
                }
                if let sv = job.save {
                    let u = url(sv)
                    try DocumentIO.write(ed.doc, to: u, format: "archi")
                    written.append(u.path)
                }
                r["ok"] = true
                r["entities"] = ed.doc.entities.count; r["elements"] = ed.doc.elements.count
            } catch {
                failed += 1
                r["ok"] = false
                r["error"] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            r["written"] = written
            progress?("\(job.name): \((r["ok"] as? Bool) == true ? "ok" : "FAILED — \(r["error"] ?? "")") (\(written.count) file(s))")
            results.append(r)
            if failed > 0 && stopOnError { break }
        }
        return ["jobs": results, "failed": failed, "succeeded": results.count - failed]
    }
}
