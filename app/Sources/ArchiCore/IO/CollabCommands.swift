// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for document history and collaboration: VERSIONS (checkpoints, restore, diff), RECOVER (repair a damaged
// drawing), RECOVERYFILES (autosave copies and change journals), JOURNAL (periodic autosave journal), MODELMERGE
// (three-way merge), STANDARDS (office standards package), IFCOPTIONS, PLUGINS (plugin manager) and SCRIPT2JS.
import Foundation

public enum CollabCommands {
    public static var all: [CommandDef] { [versions, recover, drawingRecovery, journal, modelMerge, standards, ifcOptions, ifcMap, plugins, scriptToJS, TraceReview.command, gitVersions, CentralModel.command, LaserExporter.command, ViewerExport.command, DWFxImporter.command] + PointCloudCommands.all + LispInterpreter.commands + PDFImport.commands + DGN.commands }

    @MainActor static func requireFile(_ ed: Editor) throws -> URL {
        guard let u = ed.fileURL else { throw CommandError.invalid("Save the drawing first: versions are stored next to the file.") }
        return u
    }

    static var versions: CommandDef {
        CommandDef("VERSIONS", aliases: ["CHECKPOINT", "DOCVERSIONS", "VERSIONHISTORY"], category: "Collaborate",
                   summary: "Version history saved next to the drawing: Save a named checkpoint, List, Restore a version (undoable), Diff two versions (or a version and the current drawing), Delete, Prune.") { ed in
            let url = try requireFile(ed)
            let k = try await ed.getKeyword("Enter an option [Save/List/Restore/Diff/Delete/Prune]", ["Save", "List", "Restore", "Diff", "Delete", "Prune"], defaultValue: "List") ?? "List"
            @MainActor func pick(_ msg: String, allowCurrent: Bool = false) async throws -> Int? {
                let list = DocumentVersions.list(for: url)
                guard let last = list.last else { throw CommandError.invalid("No versions saved yet (VERSIONS Save).") }
                if allowCurrent {
                    let n = try await ed.getInteger("\(msg) or 0 for the current drawing <0>", defaultValue: 0) ?? 0
                    if n == 0 { return nil }
                    guard list.contains(where: { $0.number == n }) else { throw CommandError.invalid("No version \(n).") }
                    return n
                }
                let n = try await ed.getInteger("\(msg) <\(last.number)>", defaultValue: last.number) ?? last.number
                guard list.contains(where: { $0.number == n }) else { throw CommandError.invalid("No version \(n).") }
                return n
            }
            do {
                switch k {
                case "Save":
                    let msg = try await ed.getString("Checkpoint message <none>", defaultValue: "") ?? ""
                    if let v = try DocumentVersions.save(ed.doc, documentURL: url, message: msg) { ed.print("Saved version \(v.number): \(v.message)") }
                    else { ed.print("No changes since the last version.") }
                case "List":
                    let list = DocumentVersions.list(for: url)
                    if list.isEmpty { ed.print("No versions saved yet.") }
                    let f = ISO8601DateFormatter()
                    for v in list { ed.print("v\(v.number)  \(f.string(from: v.date))  \(v.author)  \(v.entities) objects, \(v.elements) elements  — \(v.message)") }
                case "Restore":
                    guard let n = try await pick("Enter version to restore") else { return }
                    let d = try DocumentVersions.load(n, documentURL: url)
                    ed.doc = d
                    ed.selection = []
                    ed.print("Restored version \(n) (U to undo).")
                case "Diff":
                    guard let a = try await pick("Enter older version") else { return }
                    let b = try await pick("Enter newer version", allowCurrent: true)
                    let diff = try DocumentVersions.diff(from: a, to: b, documentURL: url, current: ed.doc)
                    for l in diff.report.split(separator: "\n").prefix(300) { ed.print(String(l)) }
                    ed.selection = Set(diff.differences.filter { $0.kind != .removed }.map(\.id).filter { ed.doc.contains($0) })
                case "Delete":
                    guard let n = try await pick("Enter version to delete") else { return }
                    try DocumentVersions.delete(n, documentURL: url)
                    ed.print("Deleted version \(n).")
                default:
                    let keep = try await ed.getInteger("Number of newest versions to keep <10>", defaultValue: 10) ?? 10
                    try DocumentVersions.prune(keep: keep, documentURL: url)
                    ed.print("\(DocumentVersions.list(for: url).count) versions kept.")
                }
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }

    static var recover: CommandDef {
        CommandDef("RECOVER", aliases: ["RECOVERFILE", "OPENRECOVER"], category: "File",
                   summary: "Opens a damaged .archi drawing, repairing it: truncated files are closed after the last complete object, undecodable objects and settings are dropped, and the model is audited.", modifies: false) { ed in
            let url = try await IOCommands.path(ed, "Enter drawing file name to recover")
            let d: ArchiDocument, rep: RecoveryReport
            do { (d, rep) = try ArchiFile.recover(Data(contentsOf: url)) }
            catch { throw CommandError.invalid("Cannot recover \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            ed.replaceDocument(d, url: url)
            ed.isDirty = !rep.isClean
            for l in rep.text.split(separator: "\n") { ed.print(String(l)) }
            ed.print("Recovered \(url.lastPathComponent): \(d.entities.count) objects, \(d.elements.count) elements." + (rep.isClean ? "" : " Save to keep the repairs."))
            ed.host?.perform(.zoomExtents, editor: ed)
        }
    }

    static var drawingRecovery: CommandDef {
        CommandDef("RECOVERYFILES", aliases: ["JOURNALRECOVERY", "RECOVERJOURNAL"], category: "File",
                   summary: "Lists the autosave copies and change journals left by a crash or forced quit, and opens one (Open n) or deletes them (Clear).", modifies: false) { ed in
            let files = RecoveryFiles.list()
            if files.isEmpty { ed.print("No recovery files."); return }
            let f = ISO8601DateFormatter()
            for (i, r) in files.enumerated() { ed.print("\(i + 1). \(r.name)  [\(r.kind)]  \(f.string(from: r.date))") }
            let k = try await ed.getKeyword("Enter an option [Open/Clear/Exit]", ["Open", "Clear", "Exit"], defaultValue: "Exit") ?? "Exit"
            switch k {
            case "Open":
                let n = try await ed.getInteger("Enter number <1>", defaultValue: 1) ?? 1
                guard n >= 1 && n <= files.count else { throw CommandError.invalid("No recovery file \(n).") }
                do {
                    let (d, msg) = try RecoveryFiles.open(files[n - 1])
                    ed.replaceDocument(d, url: nil)
                    ed.isDirty = true
                    ed.print("Recovered \(files[n - 1].name): \(msg). Save it under a name to keep it.")
                    ed.host?.perform(.zoomExtents, editor: ed)
                } catch { throw CommandError.invalid("Cannot open the recovery file: \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            case "Clear":
                guard try await ed.getYesNo("Delete all \(files.count) recovery files?", defaultValue: false) else { return }
                for r in files where r.kind == "journal" || r.kind == "autosave" {
                    try? FileManager.default.removeItem(at: r.url)
                    if r.kind == "autosave" { try? FileManager.default.removeItem(at: r.url.deletingPathExtension().appendingPathExtension("json")) }
                }
                ed.print("Recovery files deleted.")
            default: break
            }
        }
    }

    static var journal: CommandDef {
        CommandDef("JOURNAL", aliases: ["AUTOSAVEJOURNAL", "CHANGEJOURNAL"], category: "File",
                   summary: "Change journal for crash recovery: On (record every change every n seconds to the recovery folder), Off, Now (record immediately), Status.", modifies: false) { ed in
            let k = try await ed.getKeyword("Enter an option [On/Off/Now/Status]", ["On", "Off", "Now", "Status"], defaultValue: "Status") ?? "Status"
            let cur = AutosaveJournal.session(for: ed)
            switch k {
            case "On":
                let s = try await ed.getInteger("Interval in seconds <60>", defaultValue: 60) ?? 60
                cur?.stop(keep: false)
                do {
                    let j = try AutosaveJournal(editor: ed, interval: TimeInterval(max(s, 1)))
                    j.start()
                    ed.doc.setVariable("JOURNALINTERVAL", "\(max(s, 1))")
                    ed.print("Journal on: \(j.journal.url.path) every \(max(s, 1)) s.")
                } catch { throw CommandError.invalid("Cannot start the journal: \(error.localizedDescription)") }
            case "Off":
                guard let j = cur else { ed.print("The journal is off."); return }
                j.stop(keep: false)
                ed.print("Journal off (recovery file removed).")
            case "Now":
                guard let j = cur else { throw CommandError.invalid("The journal is off (JOURNAL On).") }
                ed.print(j.tick() ? "Change recorded (\(j.journal.recordCount) since start)." : "No changes to record.")
            default:
                if let j = cur { ed.print("Journal on: \(j.journal.url.path), \(j.journal.recordCount) changes recorded, every \(Int(j.interval)) s.") }
                else { ed.print("The journal is off.") }
            }
        }
    }

    static var modelMerge: CommandDef {
        CommandDef("MODELMERGE", aliases: ["MERGE3", "MERGEBRANCH"], category: "Collaborate",
                   summary: "Three-way merge: combines another branch of the drawing (theirs) into this one using their common ancestor (base); non-conflicting changes of both sides are kept, conflicts keep ours and are listed.") { ed in
            let base = try await IOCommands.path(ed, "Enter the common ancestor (base) drawing")
            let theirs = try await IOCommands.path(ed, "Enter the other branch (theirs)")
            let b: ArchiDocument, t: ArchiDocument
            do { b = try DocumentIO.read(base); t = try DocumentIO.read(theirs) }
            catch { throw CommandError.invalid("Cannot read: \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            let r = ThreeWayMerge.merge(base: b, ours: ed.doc, theirs: t)
            ed.doc = r.doc
            ed.selection = []
            for l in r.report.split(separator: "\n").prefix(300) { ed.print(String(l)) }
            let conflictIDs = r.conflicts.compactMap { c -> EntityID? in c.key.hasPrefix("#") ? Int(c.key.dropFirst()) : nil }.filter { ed.doc.contains($0) }
            if !conflictIDs.isEmpty { ed.selection = Set(conflictIDs); ed.print("Conflicting objects are selected.") }
        }
    }

    static var standards: CommandDef {
        CommandDef("STANDARDS", aliases: ["STANDARDSPACKAGE", "OFFICESTANDARDS"], category: "Collaborate",
                   summary: "Office standards package (.archistd): Export this drawing's layers, linetypes, styles, materials, types, view templates and hatch patterns; Import (add, optionally overwrite); Check deviations.") { ed in
            let k = try await ed.getKeyword("Enter an option [Export/Import/Check]", ["Export", "Import", "Check"], defaultValue: "Export") ?? "Export"
            var url = try await IOCommands.path(ed, "Enter standards file name")
            if url.pathExtension.isEmpty { url.appendPathExtension("archistd") }
            do {
                switch k {
                case "Export":
                    let p = StandardsPackage(name: url.deletingPathExtension().lastPathComponent, from: ed.doc)
                    try p.encoded().write(to: url, options: .atomic)
                    ed.print("Wrote standards \(url.path): \(p.layers.count) layers, \(p.dimStyles.count) dimension styles, \(p.materials.count) materials, \(p.wallTypes.count) wall types.")
                case "Import":
                    let p = try StandardsPackage.decode(Data(contentsOf: url))
                    let ow = try await ed.getYesNo("Overwrite existing definitions with the same name?", defaultValue: false)
                    var d = ed.doc
                    let r = p.apply(to: &d, overwrite: ow)
                    ed.doc = d
                    ed.print("Standards \(p.name): \(r.added) definitions added, \(r.updated) updated.")
                default:
                    let p = try StandardsPackage.decode(Data(contentsOf: url))
                    let dev = p.deviations(in: ed.doc)
                    if dev.isEmpty { ed.print("The drawing follows \(p.name).") }
                    for l in dev.prefix(300) { ed.print(l) }
                }
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid("\(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
        }
    }

    static var ifcOptions: CommandDef {
        CommandDef("IFCOPTIONS", aliases: ["IFCEXPORTOPTIONS", "IFCSETTINGS"], category: "File",
                   summary: "IFC export settings saved in the drawing: schema (IFC2X3 Coordination View 2.0, IFC4 or IFC4X3), model view definition (ReferenceView = tessellated or DesignTransferView), base quantities (Qto_*) and georeferencing (IfcMapConversion).") { ed in
            let cur = IFCExportOptions.from(ed.doc)
            let curName = cur.schema == .ifc4 ? "IFC4" : cur.schema == .ifc4x3 ? "IFC4X3" : "IFC2X3"
            let sch = try await ed.getKeyword("Schema [IFC2X3/IFC4/IFC4X3] <\(curName)>", ["IFC2X3", "IFC4", "IFC4X3"], defaultValue: curName) ?? "IFC4"
            if sch != "IFC2X3" {
                let mvd = try await ed.getKeyword("Model view [ReferenceView/DesignTransferView]", ["ReferenceView", "DesignTransferView"], defaultValue: cur.effectiveView == .designTransferView ? "DesignTransferView" : "ReferenceView") ?? "ReferenceView"
                ed.doc.setVariable("IFCMVD", mvd)
            }
            let q = try await ed.getYesNo("Export base quantities (Qto_*)?", defaultValue: cur.quantities)
            ed.doc.setVariable("IFCSCHEMA", sch)
            ed.doc.setVariable("IFCQUANTITIES", q ? "1" : "0")
            if sch != "IFC2X3" {
                let geo = try await ed.getYesNo("Georeference with IfcMapConversion (project latitude/longitude, GEOCRS)?", defaultValue: cur.georeference)
                ed.doc.setVariable("IFCGEOREF", geo ? "1" : "0")
            }
            let o = IFCExportOptions.from(ed.doc)
            ed.print("IFC export: \(o.schema.rawValue), \(o.effectiveView.rawValue), quantities \(o.quantities ? "on" : "off")" + (o.schema == .ifc2x3 ? "." : ", georeference \(o.georeference ? "on" : "off")."))
        }
    }

    static var ifcMap: CommandDef {
        CommandDef("IFCMAP", aliases: ["IFCMAPPING", "IFCCLASSMAP"], category: "File",
                   summary: "IFC class mapping for export: Set a component category or element type to an IFC class and predefined type (e.g. Plumbing → IfcSanitaryTerminal.WASHHANDBASIN), List, Remove, Clear. Element props IfcExportAs override the table.") { ed in
            let k = try await ed.getKeyword("Enter an option [Set/List/Remove/Clear]", ["Set", "List", "Remove", "Clear"], defaultValue: "List") ?? "List"
            switch k {
            case "Set":
                guard let cat = try await ed.getWord("Category or element type (component category, wall, slab, column, beam, roof, stair, railing, curtainWall)"), !cat.isEmpty else { return }
                guard let cls = try await ed.getWord("IFC class[.PREDEFINEDTYPE]"), !cls.isEmpty else { return }
                guard let m = IFCClassMap.parse(cls) else { throw CommandError.invalid("\(cls) is not a supported IFC element class (\(IFCClassMap.supported.keys.sorted().prefix(12).joined(separator: ", "))…).") }
                ed.doc.setVariable("IFCMAP:" + cat, m.description)
                ed.print("\(cat) → \(m.description)")
            case "Remove":
                guard let cat = try await ed.getWord("Category to remove"), !cat.isEmpty else { return }
                ed.doc.variables = ed.doc.variables.filter { $0.key.caseInsensitiveCompare("IFCMAP:" + cat) != .orderedSame }
            case "Clear":
                ed.doc.variables = ed.doc.variables.filter { !$0.key.uppercased().hasPrefix("IFCMAP:") }
                ed.print("IFC class mapping cleared.")
            default:
                let rows = IFCClassMap.table(ed.doc)
                if rows.isEmpty { ed.print("No IFC class mapping (defaults: \(IFCClassMap.defaults.map { "\($0.key) → \($0.value)" }.sorted().joined(separator: ", ")).") }
                for r in rows { ed.print("\(r.key) → \(r.value.description)") }
            }
        }
    }

    static var gitVersions: CommandDef {
        CommandDef("GITVERSION", aliases: ["GIT", "GITCOMMIT", "GITLOG"], category: "Collaborate",
                   summary: "Git versioning of the drawing as a line-per-object .archit file next to it: Commit (with message), Log, Diff two revisions (or a revision and the drawing) object by object, Checkout a revision (undoable).") { ed in
            guard let base = ed.fileURL else { throw CommandError.invalid("Save the drawing first: the .archit file is written next to it.") }
            let file = base.deletingPathExtension().appendingPathExtension(ArchiText.fileExtension)
            let k = try await ed.getKeyword("Enter an option [Commit/Log/Diff/Checkout]", ["Commit", "Log", "Diff", "Checkout"], defaultValue: "Log") ?? "Log"
            do {
                switch k {
                case "Commit":
                    let msg = try await ed.getString("Commit message", defaultValue: "") ?? ""
                    let author = ed.doc.variable("USERNAME") ?? (ed.doc.info.author.isEmpty ? NSUserName() : ed.doc.info.author)
                    if let h = try GitVersioning.commit(ed.doc, file: file, message: msg, author: author) { ed.print("Committed \(h.prefix(10)) \(file.lastPathComponent).") }
                    else { ed.print("No changes to commit.") }
                case "Log":
                    let log = try GitVersioning.log(file: file)
                    if log.isEmpty { ed.print("No commits yet (GITVERSION Commit).") }
                    for c in log { ed.print("\(c.hash.prefix(10))  \(c.date)  \(c.author)  \(c.message)") }
                case "Diff":
                    let a = try await ed.getWord("Older revision <HEAD>", defaultValue: "HEAD") ?? "HEAD"
                    let b = try await ed.getWord("Newer revision or . for the drawing <.>", defaultValue: ".") ?? "."
                    let changes: [ArchiText.Change]
                    if b == "." { changes = ArchiText.diff(try GitVersioning.text(file: file, revision: a), try ArchiText.encode(ed.doc)) }
                    else { changes = try GitVersioning.diff(file: file, from: a, to: b) }
                    ed.print("\(changes.filter { $0.kind == .added }.count) added, \(changes.filter { $0.kind == .removed }.count) removed, \(changes.filter { $0.kind == .modified }.count) modified.")
                    for c in changes.prefix(300) { ed.print("  " + c.description) }
                    ed.selection = Set(changes.filter { $0.kind != .removed && ($0.object == "entity" || $0.object == "element") }.compactMap { Int($0.key) }.filter { ed.doc.contains($0) })
                default:
                    let r = try await ed.getWord("Revision to check out <HEAD>", defaultValue: "HEAD") ?? "HEAD"
                    ed.doc = try GitVersioning.document(file: file, revision: r)
                    ed.selection = []
                    ed.print("Checked out \(r) (U to undo).")
                }
            } catch let e as CommandError { throw e }
            catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
        }
    }

    static var plugins: CommandDef {
        CommandDef("PLUGINS", aliases: ["PLUGINMANAGER", "APPLOAD"], category: "Manage",
                   summary: "Plugin manager: List plugins (folders with plugin.json + JavaScript), Reload and register their commands, Enable/Disable, Info, New (scaffold a plugin, optionally from a recorded script), Folder.", modifies: false) { ed in
            let reg = PluginRegistry.shared
            if let f = ed.doc.variable("PLUGINFOLDER"), !f.isEmpty {
                let u = URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
                if !reg.folders.contains(u) { reg.folders.append(u) }
            }
            let k = try await ed.getKeyword("Enter an option [List/Reload/Enable/Disable/Info/New/Folder]", ["List", "Reload", "Enable", "Disable", "Info", "New", "Folder"], defaultValue: "List") ?? "List"
            switch k {
            case "Reload", "List":
                if k == "Reload" || reg.plugins.isEmpty {
                    reg.reload()
                    let names = reg.register(into: ed.registry)
                    if !names.isEmpty { ed.print("Registered: " + names.joined(separator: ", ")) }
                }
                if reg.plugins.isEmpty { ed.print("No plugins in " + reg.folders.map(\.path).joined(separator: ", ")) }
                for p in reg.plugins {
                    ed.print("\(p.enabled ? "●" : "○") \(p.manifest.name) \(p.manifest.version) [\(p.id)] — " + p.manifest.commands.map(\.name).joined(separator: ", "))
                }
                for pr in reg.problems { ed.print("  ! " + pr) }
            case "Enable", "Disable":
                if reg.plugins.isEmpty { reg.reload() }
                guard let n = try await ed.getString("Plugin name or id"), !n.isEmpty else { return }
                do { try reg.setEnabled(n, k == "Enable") } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
                if k == "Enable" { reg.register(into: ed.registry) }
                ed.print("\(n) \(k == "Enable" ? "enabled" : "disabled").")
            case "Info":
                if reg.plugins.isEmpty { reg.reload() }
                guard let n = try await ed.getString("Plugin name or id"), let p = reg.plugin(n) else { throw CommandError.invalid("No such plugin.") }
                ed.print("\(p.manifest.name) \(p.manifest.version) by \(p.manifest.author.isEmpty ? "unknown" : p.manifest.author) — \(p.manifest.description)")
                ed.print("Folder: \(p.directory.path); entry: \(p.manifest.main); permissions: \(p.manifest.permissions.joined(separator: ", "))")
                for c in p.manifest.commands { ed.print("  \(c.name)\(c.aliases.isEmpty ? "" : " (" + c.aliases.joined(separator: ", ") + ")") → \(c.function)(): \(c.summary)") }
            case "New":
                guard let name = try await ed.getString("Plugin name"), !name.isEmpty else { return }
                guard let cmd = try await ed.getWord("Command name"), !cmd.isEmpty else { return }
                let scr = try await ed.getWord("Script file to replay (.scr) <none>", defaultValue: "") ?? ""
                var lines: [String]? = nil
                if !scr.isEmpty {
                    let u = IOCommands.resolve(ed, scr)
                    guard let t = try? FileImport.readText(u) else { throw CommandError.invalid("Cannot read \(u.path)") }
                    lines = t.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                } else if let rec = ed.recorder, !rec.lines.isEmpty { lines = rec.lines }
                do {
                    let dir = try PluginRegistry.scaffold(in: reg.folders.first ?? PluginRegistry.defaultFolder, name: name, command: cmd.uppercased(), script: lines, registry: ed.registry)
                    ed.print("Created plugin \(dir.path) (PLUGINS Reload to register \(cmd.uppercased())).")
                } catch { throw CommandError.invalid("Cannot create the plugin: \(error.localizedDescription)") }
            default:
                guard let p = try await ed.getWord("Plugin folder <\(reg.folders.first?.path ?? "")>", defaultValue: reg.folders.first?.path ?? "") else { return }
                let u = IOCommands.resolve(ed, p)
                ed.doc.setVariable("PLUGINFOLDER", u.path)
                reg.folders = [u] + reg.folders.filter { $0 != u }
                reg.reload()
                let names = reg.register(into: ed.registry)
                ed.print("Plugin folder \(u.path): \(reg.plugins.count) plugins" + (names.isEmpty ? "." : ", registered " + names.joined(separator: ", ")))
            }
        }
    }

    static var scriptToJS: CommandDef {
        CommandDef("SCRIPT2JS", aliases: ["SCRTOJS", "RECORDTOJS"], category: "Manage",
                   summary: "Converts a command script (.scr, or the running SCRIPTRECORD recording) into JavaScript calling archi.run() per command.", modifies: false) { ed in
            let src = try await ed.getWord("Enter script file (.scr) or [Recording]", defaultValue: nil, keywords: ["Recording"]) ?? ""
            let text: String, name: String
            if src.caseInsensitiveCompare("Recording") == .orderedSame || src.uppercased() == "R" {
                guard let rec = ed.recorder, !rec.lines.isEmpty else { throw CommandError.invalid("Nothing is being recorded (SCRIPTRECORD).") }
                text = rec.lines.joined(separator: "\n"); name = "Recording"
            } else {
                let u = IOCommands.resolve(ed, src)
                guard let t = try? FileImport.readText(u) else { throw CommandError.invalid("Cannot read \(u.path)") }
                text = t; name = u.deletingPathExtension().lastPathComponent
            }
            let js = ScriptConverter.javaScriptFile(fromScript: text, name: name, registry: ed.registry)
            let outName = try await ed.getWord("Enter JavaScript file name <\(name).js>", defaultValue: "\(name).js") ?? "\(name).js"
            var out = IOCommands.resolve(ed, outName)
            if out.pathExtension.isEmpty { out.appendPathExtension("js") }
            try IOCommands.write(ed, out, "JavaScript") { try js.write(to: out, atomically: true, encoding: .utf8) }
            ed.print("\(js.components(separatedBy: "archi.run(").count - 1) commands converted.")
        }
    }
}
