// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac UI-layer commands for graphic standards, clipboard and sharing: GRAPHICSTYLES and
// NODEPACKAGE (AppCommandsRound10.swift), OBJECTSTYLESDIALOG, IMAGEADJUSTDIALOG and MATPATTERNDIALOG
// (AppCommandsRound12.swift), VISUALSTYLES and LWDISPLAYSCALE (AppCommandsNav.swift), PASTESPECIAL, COPYPICTURE and
// SPEAKDRAWING (AppCommandsRound11.swift), SHARE (AppCommandsReview.swift) and ARQUICKLOOK (AppCommandsRound10.swift).
// Same names, aliases, prompts and messages; where the Mac shows a window, uses the pasteboard, the share sheet or
// VoiceOver, the engine asks the Windows shell with a `host` notification (docs/ENGINE-PROTOCOL.md "Graphic standards,
// clipboard and sharing"). Registered by archi-engine only (EngineSession.registerPortableAppCommands).
import Foundation

enum EngineStandardsCommands {
    static var all: [CommandDef] {
        [graphicStyles, objectStylesDialog, matPatternDialog, imageAdjustDialog, visualStyles, lwDisplayScale, pasteSpecial, copyPicture, share,
         speakDrawing, nodePackage, arQuickLook]
    }

    @MainActor static func host(_ ed: Editor, _ action: String, _ fields: [(String, EngineJSON)] = []) throws {
        try EngineUICommands.host(ed, action, fields)
    }
    @MainActor static func pref(_ key: String) -> String? { EngineSession.uiPreferences[key] }
    @MainActor static func word(_ ed: Editor, _ msg: String) async throws -> String? {
        let t = (try await ed.getWord(msg) ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    // MARK: Graphic standards dialogs

    static var graphicStyles: CommandDef {
        CommandDef("GRAPHICSTYLES", aliases: ["STYLESMANAGER", "GSTYLES"], category: "Settings",
                   summary: "Graphic styles manager: line styles and their layers, lineweights by view scale, pen sets and graphic override filters in one dialog.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            try EngineUICommands.dialog(ed, "graphicStyles")
        }
    }

    static var objectStylesDialog: CommandDef {
        CommandDef("OBJECTSTYLESDIALOG", aliases: ["OBJECTSTYLESDLG", "OSTYLESDIALOG"], category: "Manage",
                   summary: "Object Styles dialog: projection/cut line weights, line colour, cut fill and cut pattern per BIM category for every plan and section.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            try EngineUICommands.dialog(ed, "objectStyles")
        }
    }

    static var matPatternDialog: CommandDef {
        CommandDef("MATPATTERNDIALOG", aliases: ["MATERIALPATTERNSDIALOG", "FILLPATTERNSDIALOG"], category: "Annotate",
                   summary: "Material Fill Patterns dialog: cut and surface pattern of every material; bound hatches and floor patterns update.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            try EngineUICommands.dialog(ed, "matPatterns")
        }
    }

    @MainActor static func images(_ ed: Editor, _ ids: [EntityID]) -> [EntityID] {
        ids.filter { id in
            if case .image? = ed.doc.entity(id)?.geometry { return true }
            return false
        }.sorted()
    }

    static var imageAdjustDialog: CommandDef {
        CommandDef("IMAGEADJUSTDIALOG", aliases: ["IMAGEADJUSTDLG", "IADDIALOG"], category: "Blocks",
                   summary: "Image Adjust dialog: brightness, contrast and fade of the selected raster images with a preview (exact on screen and in PDF plots).", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            var ids = images(ed, Array(ed.selection))
            if ids.isEmpty {
                let sel = try await ed.getSelection("Select images")
                ids = images(ed, sel)
            }
            guard !ids.isEmpty else { throw CommandError.invalid("Select one or more images.") }
            try EngineUICommands.dialog(ed, "imageAdjust", [("ids", .ints(ids))])
        }
    }

    // MARK: Visual styles and lineweight display

    static var visualStyles: CommandDef {
        CommandDef("VISUALSTYLES", aliases: ["VSM", "VISUALSTYLEMANAGER"], category: "View",
                   summary: "Visual styles manager: New/Edit a custom style from a base (edges, edge colour, face opacity, shadows, background), Delete, List, Current.", modifies: true) { ed in
            guard let k = try await ed.getKeyword("Enter option [New/Edit/Delete/List/Current]", ["New", "Edit", "Delete", "List", "Current"], defaultValue: "List") else { return }
            switch k {
            case "List":
                ed.print("Built-in: " + EngineVisualStyle.builtIn.joined(separator: ", "))
                for v in EngineVisualStyle.all(ed.doc) { ed.print(v.listLine) }
            case "Delete":
                guard let n = try await word(ed, "Style to delete") else { return }
                guard EngineVisualStyle.delete(n, in: &ed.doc) else { throw CommandError.invalid("No custom style " + n + ".") }
                ed.print("Deleted " + n + ".")
            case "Current":
                guard let n = try await word(ed, "Style name") else { return }
                let s = try EngineUICommands.session(ed)
                let custom = EngineVisualStyle.named(n, in: ed.doc)
                guard custom != nil || EngineVisualStyle.resolve(n) != nil else { throw CommandError.invalid("Unknown style " + n + ".") }
                let base = custom.map { $0.base } ?? EngineVisualStyle.resolve(n) ?? "Shaded with Edges"
                s.view3dStyleChanged(base)
                try host(ed, "visualStyle", [("name", .string(custom?.name ?? base)), ("base", .string(base)), ("custom", custom?.json ?? .null)])
            default:
                guard let n = try await word(ed, "Style name") else { return }
                if k == "Edit" && EngineVisualStyle.named(n, in: ed.doc) == nil { throw CommandError.invalid("No custom style " + n + ".") }
                var v = EngineVisualStyle.named(n, in: ed.doc) ?? EngineVisualStyle(name: n, base: "Shaded")
                let bases = ["Wireframe", "Hidden", "Shaded", "shadedwithEdges", "Conceptual", "Realistic", "Xray"]
                if let b = try await ed.getKeyword("Base [Wireframe/Hidden/Shaded/shadedwithEdges/Conceptual/Realistic/Xray]", bases, defaultValue: v.base.replacingOccurrences(of: " ", with: "")) { v.base = b }
                let edgeDefault = v.edges.map { $0 ? "Yes" : "No" } ?? "Base"
                if let e = try await ed.getKeyword("Edges [Yes/No/Base]", ["Yes", "No", "Base"], defaultValue: edgeDefault) { v.edges = e == "Base" ? nil : e == "Yes" }
                let opacity = Int(((v.faceOpacity ?? 1) * 100).rounded())
                if let o = try await ed.getInteger("Face opacity % (1–100)", defaultValue: opacity) { v.faceOpacity = o >= 100 ? nil : Double(min(max(o, 1), 100)) / 100 }
                let shadowDefault = v.shadows.map { $0 ? "Yes" : "No" } ?? "Base"
                if let s = try await ed.getKeyword("Shadows [Yes/No/Base]", ["Yes", "No", "Base"], defaultValue: shadowDefault) { v.shadows = s == "Base" ? nil : s == "Yes" }
                if let c = try await word(ed, "Edge colour #RRGGBB (Enter = base)"), let hex = EngineStd.hexNumber(c) { v.edgeColor = hex }
                guard EngineVisualStyle.save(v, in: &ed.doc) else { throw CommandError.invalid("Invalid style (built-in names cannot be redefined).") }
                ed.print("Visual style \(v.name) saved. VISUALSTYLES Current \(v.name) shows it.")
            }
        }
    }

    static var lwDisplayScale: CommandDef {
        CommandDef("LWDISPLAYSCALE", aliases: ["LWSCALE"], category: "Settings",
                   summary: "Screen display scale of lineweights (0.1–5, default 1); plotted widths are never changed.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let cur = pref("lwDisplayScale").flatMap(Double.init).map { min(max($0, 0.1), 5) } ?? 1
            guard let v = try await ed.getDistance("Lineweight display scale <" + fmt(cur, 2) + ">", defaultValue: cur).value else { return }
            guard v >= 0.1 && v <= 5 else { throw CommandError.invalid("Requires a value from 0.1 to 5.") }
            EngineSession.uiPreferences["lwDisplayScale"] = fmt(v, 4)
            try host(ed, "preference", [("key", .string("lwDisplayScale")), ("value", .number(v))])
            ed.print("Lineweight display scale " + fmt(v, 2) + ".")
        }
    }

    // MARK: Clipboard

    static var pasteSpecial: CommandDef {
        CommandDef("PASTESPECIAL", aliases: ["PASTESPEC", "PASTEEXTERNAL", "PASTEFROMAPP"], category: "Edit",
                   summary: "Pastes what another app copied — SVG or PDF vectors, pictures, DXF text, plain text or Explorer files — at an insertion point.") { ed in
            _ = try EngineUICommands.session(ed)
            // The shell tells the engine whether the Windows clipboard holds content from another app (ui.prefs).
            guard pref("clipboardExternal") != "0" else { throw CommandError.invalid("The clipboard holds nothing from another app (use PASTECLIP for drawing objects).") }
            let p = try await ed.requirePoint("Specify insertion point")
            // The shell reads the clipboard and calls clipboard.paste (or file.drop for copied files): one undo step.
            try host(ed, "pasteSpecial", [("x", .number(p.x)), ("y", .number(p.y))])
        }
    }

    static var copyPicture: CommandDef {
        CommandDef("COPYPICTURE", aliases: ["COPYASPDF", "COPYIMAGE", "COPYPDF"], category: "Edit",
                   summary: "Copies the selected objects (or the whole drawing) to the clipboard as a vector PDF and a PNG picture for other apps.", modifies: false) { ed in
            let s = try EngineUICommands.session(ed)
            let ids = try await ed.getSelection("Select objects <all>")
            let set: Set<EntityID>? = ids.isEmpty ? nil : Set(ids)
            guard let pic = EngineStd.picture(ed.doc, ids: set, level: set == nil ? ed.doc.currentLevel : nil) else { throw CommandError.invalid("Nothing to copy.") }
            let data = try s.pictureJSON(pic)
            var fields: [(String, EngineJSON)] = []
            for f in data.fields ?? [] { fields.append((f.key, f.value)) }
            try host(ed, "copyPicture", fields)
            ed.selection = []
            let what = set.map { String($0.count) + " object(s)" } ?? "the drawing"
            ed.print("Copied \(what) as a PDF at 1:\(fmt(pic.ratio, 0)) and a PNG picture.")
        }
    }

    // MARK: Sharing

    static var share: CommandDef {
        CommandDef("SHARE", aliases: ["SHAREDRAWING", "SENDTO"], category: "Collaborate",
                   summary: "Shares the drawing through the Windows share sheet (Mail, Teams, Nearby Sharing…): Project (.archi), Pdf of the drawing or active sheet, or Both.", modifies: false) { ed in
            let s = try EngineUICommands.session(ed)
            let k = try await ed.getKeyword("Share [Project/Pdf/Both]", ["Project", "Pdf", "Both"], defaultValue: "Both") ?? "Both"
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiShare-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let base = EngineStd.safeName(ed.doc.info.name, fallback: "Drawing")
            var out: [URL] = []
            if k != "Pdf" {
                let u = dir.appendingPathComponent(base + "." + ArchiFile.fileExtension)
                try ArchiFile.encode(ed.doc).write(to: u, options: .atomic)
                out.append(u)
            }
            if k != "Project" {
                let u = dir.appendingPathComponent(base + ".pdf")
                var o = EngineObject()
                o.set("what", s.activeSheetIndex.map { "sheet:" + String($0) } ?? "model")
                let plot = try s.plotPages(o.json, layered: true)
                let pdf = EnginePDF.document(plot.pages, doc: ed.doc, title: plot.title, layered: true)
                try pdf.data.write(to: u, options: .atomic)
                out.append(u)
            }
            try host(ed, "share", [("paths", EngineJSON.strings(out.map(\.path)))])
            ed.print("Sharing " + out.map(\.lastPathComponent).joined(separator: ", ") + ".")
        }
    }

    /// AR Quick Look on the Mac (USDZ to Preview or an iPhone): on Windows the model is exported as a real-scale glTF
    /// binary, which the Windows 3D viewer opens (its "Mixed reality" view places it in the room) or the share sheet sends.
    static var arQuickLook: CommandDef {
        CommandDef("ARQUICKLOOK", aliases: ["ARVIEW", "USDZPREVIEW", "ARPREVIEW"], category: "View",
                   summary: "AR view: exports the model as a real-scale glTF (GLB) and Previews it in the Windows 3D viewer (mixed reality) or Shares it to a phone or tablet.", modifies: false) { ed in
            _ = try EngineUICommands.session(ed)
            let k = try await ed.getKeyword("AR Quick Look [Preview/Share]", ["Preview", "Share"], defaultValue: "Preview") ?? "Preview"
            let name = EngineStd.safeName(ed.doc.info.name, fallback: "Model")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ARQuickLook", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name + ".glb")
            let groups = MeshBuilder.build(doc: ed.doc)
            guard groups.contains(where: { !$0.mesh.positions.isEmpty }) else { throw CommandError.invalid("The model has no 3D content.") }
            let data = GLTFExporter.exportGLB(groups, materials: ed.doc.materials, unitMM: ed.doc.units.mm, textureRoot: ed.fileURL?.deletingLastPathComponent())
            try data.write(to: url, options: .atomic)
            if k == "Share" { try host(ed, "share", [("paths", EngineJSON.strings([url.path]))]) } else { try host(ed, "openFile", [("path", .string(url.path))]) }
            ed.print("glTF at real-world scale (" + fmt(ed.doc.units.mm / 1000, 4) + " m per unit): " + url.path)
        }
    }

    // MARK: Accessibility

    static var speakDrawing: CommandDef {
        CommandDef("SPEAKDRAWING", aliases: ["DESCRIBEDRAWING", "VOICEOVERSUMMARY", "A11YSUMMARY"], category: "Help",
                   summary: "Describes the drawing, the selection and the current prompt (spoken by Narrator / Windows speech, printed on the command line).", modifies: false) { ed in
            let s = try EngineUICommands.session(ed)
            let t = s.drawingDescription()
            ed.print(t)
            try host(ed, "speak", [("text", .string(t))])
        }
    }

    // MARK: Node packages

    static var nodePackage: CommandDef {
        CommandDef("NODEPACKAGE", aliases: ["NODEPACKAGES", "NODEPKG"], category: "Tools",
                   summary: "Custom node packages (.archinodes): Create one from the drawing's node graph (a snippet per group), Install a file, Insert a snippet into the graph, List, Remove.") { ed in
            let k = try await ed.getKeyword("Node packages [List/Create/Install/Insert/Remove]", ["List", "Create", "Install", "Insert", "Remove"], defaultValue: "List") ?? "List"
            let ext = EngineNodePackage.fileExtension
            switch k {
            case "Create":
                guard let g = NodeGraph.load(ed.doc), !g.nodes.isEmpty else { throw CommandError.invalid("The drawing has no node graph. Build one in the Node Editor first.") }
                let name = try await EngineUICommands.text(ed, "Package name", "My Nodes")
                let def = EngineStd.desktop().appendingPathComponent(EngineNodePackages.fileName(name)).path
                let url = EngineUICommands.filePath(try await EngineUICommands.text(ed, "Package file", def), ext: ext)
                let pkg = EngineNodePackages.make(from: g, name: name, author: EngineStd.userName())
                try pkg.data().write(to: url)
                try EngineNodePackages.install(pkg)
                let names = pkg.snippets.map(\.name).joined(separator: ", ")
                ed.print("Package \(pkg.name): \(names) → \(url.path) (installed).")
            case "Install":
                let def = EngineStd.desktop().appendingPathComponent("My Nodes." + ext).path
                let url = EngineUICommands.filePath(try await EngineUICommands.text(ed, "Package file", def), ext: ext)
                let p = try EngineNodePackages.install(url)
                ed.print("Installed \(p.name) \(p.version): \(p.snippets.count) snippet(s).")
            case "Insert":
                let pkgs = EngineNodePackages.installed()
                guard let firstPkg = pkgs.first else { throw CommandError.invalid("No node packages installed.") }
                let pn = try await EngineUICommands.text(ed, "Package", firstPkg.name)
                guard let p = EngineNodePackages.package(named: pn) else { throw CommandError.invalid("No package " + pn + ".") }
                let sn = try await EngineUICommands.text(ed, "Snippet", p.snippets.first?.name ?? "")
                guard let snip = p.snippets.first(where: { $0.name.caseInsensitiveCompare(sn) == .orderedSame }) else { throw CommandError.invalid("No snippet \(sn) in \(p.name).") }
                var g = NodeGraph.load(ed.doc) ?? NodeGraph()
                let x = (g.nodes.map(\.x).max() ?? -220) + 260
                let map = EngineNodePackages.insert(snip.graph, into: &g, x: x, y: 40)
                g.store(in: &ed.doc)
                ed.print("Inserted \(snip.name): \(map.count) node(s). Open the Node Editor to connect and bake it.")
            case "Remove":
                let pn = try await EngineUICommands.text(ed, "Package", EngineNodePackages.installed().first?.name ?? "")
                guard let p = EngineNodePackages.package(named: pn) else { throw CommandError.invalid("No package " + pn + ".") }
                try EngineNodePackages.remove(p.name)
                ed.print("Removed " + pn + ".")
            default:
                let pkgs = EngineNodePackages.installed()
                if pkgs.isEmpty { ed.print("No node packages installed.") }
                for p in pkgs {
                    let by = p.author.isEmpty ? "" : " by " + p.author
                    let names = p.snippets.map(\.name).joined(separator: ", ")
                    ed.print("  \(p.name) \(p.version)\(by): \(names)")
                }
            }
        }
    }
}

extension EngineSession {
    /// Graphic standards, clipboard and sharing commands (part of `registerPortableAppCommands`).
    public static func registerStandardsCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in EngineStandardsCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
    }
}
