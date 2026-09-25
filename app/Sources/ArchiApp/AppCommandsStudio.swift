// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import ArchiCore

/// Groups several edits (commands, script calls, transactions) into a single undo step: remember the document and the
/// history before, run the edits, then replace whatever history they recorded by one entry.
@MainActor
struct UndoStep {
    let before: ArchiDocument
    let history: UndoHistory
    static func begin(_ ed: Editor) -> UndoStep { UndoStep(before: ed.doc, history: ed.history) }
    /// Collapses the edits since `begin` into one undo step. Returns false when nothing changed.
    @discardableResult
    func end(_ ed: Editor, label: String) -> Bool {
        var h = history
        guard ed.doc != before else { ed.history = h; return false }
        h.record(label, before: before)
        ed.history = h
        return true
    }
}

/// App commands of the family editor, 3D tools (Z move, levels, field of view, image export), sheet images and the
/// selection/notification/navigator/what's-new panels. Registered like core commands (command line, ribbon, scripts, agents).
@MainActor
enum AppCommandsStudio {
    static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppModels.model(for: ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    /// Reads a number typed on the command line (negative values allowed); nil on Enter.
    static func number(_ ed: Editor, _ msg: String, defaultValue: Double? = nil) async throws -> Double? {
        guard let s = try await ed.getString(msg, defaultValue: defaultValue.map { fmt($0, 6) }), !s.trimmingCharacters(in: .whitespaces).isEmpty else { return defaultValue }
        if let v = Double(s.trimmingCharacters(in: .whitespaces)) ?? FamilyExpr.evaluate(s, [:]) { return v }
        throw CommandError.invalid("Requires a number.")
    }
    /// Output file: a typed path, or a save panel on Enter.
    static func outputURL(_ ed: Editor, _ m: AppModel, ext: String, suggested: String) async throws -> URL? {
        let s = try await ed.getString("File name (Enter = choose)", defaultValue: "") ?? ""
        let t = s.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty {
            var u = URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
            if u.pathExtension.isEmpty { u.appendPathExtension(ext) }
            return u
        }
        return m.files.exportPanel(ext: ext, suggested: suggested)
    }

    static var all: [CommandDef] {
        [
            CommandDef("FAMILYPANEL", aliases: ["FAMPANEL", "FAMILYWINDOW"], category: "Architecture", summary: "Family Editor panel: families list, parameters and formulas, forms, types table, reference planes, profiles, live 3D preview and flex; Apply is one undo step.", modifies: false) { ed in
                let m = try ui(ed)
                let names = m.doc.families.map(\.name)
                var fam: String?
                if !names.isEmpty { fam = try await ed.getString("Family to edit [\(names.joined(separator: "/"))] (Enter = current)", defaultValue: "") }
                if let f = fam, !f.isEmpty, m.doc.family(named: f) == nil { throw CommandError.invalid("Unknown family \(f).") }
                FamilyEditorWindow.show(model: m, family: fam?.isEmpty == false ? fam : nil)
            },
            CommandDef("MOVEZ", aliases: ["ZMOVE", "MOVEUP"], category: "3D", summary: "Moves objects up or down: element base/top offsets and door/window sills change, solids move (one undo step).") { ed in
                let ids = try await ed.getSelection()
                guard !ids.isEmpty else { return }
                guard let dz = try await number(ed, "Vertical distance (negative = down)") else { return }
                let r = ZMove.apply(ed, ids: ids, dz: dz, label: "MOVEZ")
                ed.print("Moved \(r.moved) object(s) by \(fmt(dz, 2)) along Z" + (r.skipped > 0 ? "; \(r.skipped) have no height to change." : "."))
            },
            CommandDef("LEVELVIEW3D", aliases: ["ISOLATELEVEL3D", "EXPLODELEVELS"], category: "View", summary: "3D view by level: show All levels, Isolate one level, or Explode levels apart by a gap.", modifies: false) { ed in
                let m = try ui(ed)
                let st = LevelView3DState.shared
                let k = try await ed.getKeyword("Levels in 3D [All/Isolate/Explode]", ["All", "Isolate", "Explode"], defaultValue: "Isolate") ?? "All"
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                switch k {
                case "Isolate":
                    let names = m.doc.levels.map(\.name)
                    let cur = m.doc.level(m.doc.currentLevel)?.name ?? names.first ?? ""
                    let n = try await ed.getString("Level [\(names.joined(separator: "/"))]", defaultValue: cur) ?? cur
                    guard let l = m.doc.levels.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) ?? Int(n).flatMap({ m.doc.level($0) }) else { throw CommandError.invalid("Unknown level \(n).") }
                    st.isolate = l.id
                    ed.print("Showing only \(l.name) in 3D.")
                case "Explode":
                    let g = try await number(ed, "Gap between levels", defaultValue: 3000 / max(m.doc.units.mm, 1e-9)) ?? 0
                    st.explodeGap = max(0, g)
                    ed.print(g > 0 ? "Levels exploded by \(fmt(g, 0))." : "Levels are not exploded.")
                default:
                    st.isolate = nil; st.explodeGap = 0
                    ed.print("All levels shown.")
                }
            },
            CommandDef("FOV", aliases: ["FIELDOFVIEW", "LENS"], category: "View", summary: "Sets the 3D camera field of view in degrees (15–120), or a Lens length in mm (35 mm equivalent).", modifies: false) { ed in
                let m = try ui(ed)
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                guard let c = Viewport3DController.active else { throw CommandError.invalid("Open the 3D view first.") }
                let s = try await ed.getString("Field of view in degrees or [Lens] <\(fmt(c.fieldOfView, 1))>", defaultValue: "") ?? ""
                if s.trimmingCharacters(in: .whitespaces).isEmpty { return }
                if s.uppercased().hasPrefix("L") {
                    guard let f = try await number(ed, "Lens length in mm <\(fmt(FieldOfView.focalLength(fov: c.fieldOfView), 0))>", defaultValue: FieldOfView.focalLength(fov: c.fieldOfView)), f > 0 else { return }
                    c.fieldOfView = FieldOfView.fov(focalLength: f)
                } else {
                    guard let v = Double(s) else { throw CommandError.invalid("Requires a number of degrees or L.") }
                    c.fieldOfView = v
                }
                ed.print("Field of view \(fmt(c.fieldOfView, 1))° (\(fmt(FieldOfView.focalLength(fov: c.fieldOfView), 0)) mm lens).")
            },
            CommandDef("VIEWIMAGE", aliases: ["VIEWPORTIMAGE", "SAVEIMG3D"], category: "View", summary: "Saves the 3D view as a PNG, JPEG or TIFF at a chosen size, optionally with a transparent background.", modifies: false) { ed in
                let m = try ui(ed)
                if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                guard let c = Viewport3DController.active else { throw CommandError.invalid("Open the 3D view first.") }
                let w = try await ed.getInteger("Image width in pixels", defaultValue: 1920) ?? 1920
                let h = try await ed.getInteger("Image height in pixels", defaultValue: 1080) ?? 1080
                guard (16...16384).contains(w), (16...16384).contains(h) else { throw CommandError.invalid("Width and height must be 16–16384 pixels.") }
                let fk = try await ed.getKeyword("Format [Png/Jpeg/Tiff]", ["Png", "Jpeg", "Tiff"], defaultValue: "Png") ?? "Png"
                let format = ImageExport.Format(rawValue: fk.uppercased()) ?? .png
                let clear = format == .jpeg ? false : try await ed.getKeyword("Transparent background? [Yes/No]", ["Yes", "No"], defaultValue: "No") == "Yes"
                guard let url = try await outputURL(ed, m, ext: format.ext, suggested: m.displayName + " 3D") else { return }
                guard let img = c.viewportImage(width: w, height: h, transparent: clear), let data = ImageExport.data(img, format: format) else { throw CommandError.invalid("Could not render the 3D view.") }
                do { try data.write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
                ed.print("Saved \(w)×\(h) \(format.rawValue) to \(url.path).")
            },
            CommandDef("SHEETIMAGE", aliases: ["LAYOUTIMAGE", "SHEETPNG"], category: "Output", summary: "Exports a sheet (layout) or the Model view of the current level as a PNG, JPEG or TIFF image at a chosen resolution (dpi).", modifies: false) { ed in
                let m = try ui(ed)
                let names = m.doc.layouts.map(\.name)
                let cur = m.mode == .sheet && m.doc.layouts.indices.contains(m.activeLayout) ? names[m.activeLayout] : "Model"
                let n = try await ed.getString("Sheet [\((names + ["Model"]).joined(separator: "/"))]", defaultValue: cur) ?? cur
                let li = names.firstIndex(where: { $0.caseInsensitiveCompare(n) == .orderedSame })
                guard li != nil || n.caseInsensitiveCompare("Model") == .orderedSame else { throw CommandError.invalid("Unknown sheet \(n).") }
                let dpi = try await ed.getInteger("Resolution in dpi", defaultValue: 150) ?? 150
                guard (36...1200).contains(dpi) else { throw CommandError.invalid("Resolution must be 36–1200 dpi.") }
                let fk = try await ed.getKeyword("Format [Png/Jpeg/Tiff]", ["Png", "Jpeg", "Tiff"], defaultValue: "Png") ?? "Png"
                let format = ImageExport.Format(rawValue: fk.uppercased()) ?? .png
                let title = li.map { names[$0] } ?? "Model"
                guard let url = try await outputURL(ed, m, ext: format.ext, suggested: title == "Model" ? m.displayName : title) else { return }
                let image = li.map { SheetImageExport.image(doc: m.doc, layoutIndex: $0, dpi: Double(dpi)) } ?? SheetImageExport.modelImage(doc: m.doc, level: m.doc.currentLevel, dpi: Double(dpi))
                guard let img = image, let data = ImageExport.data(img, format: format) else { throw CommandError.invalid("Could not render the image (too large?).") }
                do { try data.write(to: url, options: .atomic) } catch { throw CommandError.invalid("Cannot write \(url.path): \(error.localizedDescription)") }
                ed.print("Saved \(title) at \(dpi) dpi (\(Int(img.size.width))×\(Int(img.size.height)) px) to \(url.path).")
            },
            CommandDef("SELECTIONINFO", aliases: ["SELINFO", "SELECTIONPANEL"], category: "Inquiry", summary: "Selection info panel: count and types of the selected objects, layers, total length/area, keep-only/remove filters.", modifies: false) { ed in
                let m = try ui(ed)
                StudioPanelsDock.show(.selection, model: m)
            },
            CommandDef("NOTIFICATIONS", aliases: ["WARNINGS", "NOTIFYCENTER"], category: "Inquiry", summary: "Notifications centre: model warnings (overlaps, unhosted openings, family errors, missing blocks) — click one to zoom to it.", modifies: false) { ed in
                let m = try ui(ed)
                let n = ModelNotifications.items(m.doc).filter { $0.severity != .info }.count
                ed.print(n == 0 ? "No warnings." : "\(n) warning(s).")
                StudioPanelsDock.show(.alerts, model: m)
            },
            CommandDef("NAVIGATOR", aliases: ["OVERVIEW", "MINIMAP"], category: "View", summary: "Navigator: overview map of the whole drawing with the visible area; drag the rectangle to pan.", modifies: false) { ed in
                let m = try ui(ed)
                if m.mode != .plan { m.mode = .plan }
                StudioPanelsDock.show(.navigator, model: m)
            },
            CommandDef("WHATSNEW", aliases: ["RELEASENOTES"], category: "Help", summary: "Shows what is new in this version (also shown once after an update).", modifies: false) { _ in
                StudioWindows.show("whatsnew", title: "What's New", size: NSSize(width: 520, height: 460)) { WhatsNewView() }
            },
        ]
    }
}

/// Shows a panel tab: brings its floating window forward, or docks it in the side panel column.
@MainActor
enum StudioPanelsDock {
    static func show(_ tab: PanelTab, model: AppModel) {
        if FloatingPanels.isFloating(tab, model: model) { FloatingPanels.float(tab, model: model); return }
        model.showPanels = true
        model.panelTab = tab
        model.revision &+= 1
    }
}
