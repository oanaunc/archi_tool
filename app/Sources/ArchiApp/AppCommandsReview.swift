// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import ArchiCore

/// App commands of the review, 3D tool, render queue, camera path, block library and printing panels. Registered like
/// core commands (command line, ribbon, scripts, agents).
@MainActor
enum AppCommandsReview {
    static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppModels.model(for: ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    private static func show3D(_ m: AppModel) { if m.mode == .plan || m.mode == .sheet { m.mode = .model } }

    static var all: [CommandDef] {
        [
            CommandDef("MARKUPPANEL", aliases: ["ISSUES", "MARKUPMANAGER"], category: "Collaborate", summary: "Opens the markup/issue panel: filter open/resolved, reply, resolve, zoom to, link to the selection, BCF.", modifies: false) { ed in
                MarkupWindow.show(model: try ui(ed))
            },
            CommandDef("COMPAREPANEL", aliases: ["COMPAREOVERLAY"], category: "Collaborate", summary: "Compares with another version and draws the differences over the plan (added green, removed red, modified yellow).", modifies: false) { ed in
                CompareWindow.show(model: try ui(ed))
            },
            CommandDef("REVCLOUDPANEL", aliases: ["SHEETCLOUDS"], category: "Output", summary: "Sheet revision clouds: add a cloud with a revision triangle around a viewport or an area of a sheet, list, open, delete.", modifies: false) { ed in
                RevisionCloudWindow.show(model: try ui(ed))
            },
            CommandDef("BLOCKPALETTE", aliases: ["BLOCKSPANEL", "CONTENTLIBRARY"], category: "Blocks", summary: "Block library panel: library folders with thumbnails, search, favourites and recents; drag blocks onto the drawing.", modifies: false) { ed in
                BlockLibraryWindow.show(model: try ui(ed))
            },
            CommandDef("MEASURE3D", aliases: ["3DMEASURE", "DIST3D"], category: "Inquiry", summary: "Measures in the 3D view: click two points on the model for distance and ΔX/ΔY/ΔZ.", modifies: false) { ed in
                let m = try ui(ed)
                let cur = Measure3DState.shared.active
                let k = try await ed.getKeyword("Measure in 3D [On/Off]", ["On", "Off"], defaultValue: cur ? "Off" : "On") ?? "On"
                show3D(m)
                Measure3DState.shared.set(k == "On")
                ed.print(k == "On" ? "Click two points on the model in the 3D view." : "3D measuring is off.")
            },
            CommandDef("GIZMO3D", aliases: ["GIZMO", "3DGIZMO"], category: "3D", summary: "Shows a move (X/Y arrows) or rotate (ring) gizmo on the selection in the 3D view; drag it to transform (one undo step).", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Gizmo [Move/Rotate/Off]", ["Move", "Rotate", "Off"], defaultValue: Gizmo3DState.shared.mode == .off ? "Move" : "Off") ?? "Off"
                show3D(m)
                Gizmo3DState.shared.mode = Gizmo3DState.Mode(rawValue: k) ?? .off
                if Gizmo3DState.shared.mode != .off && ed.selection.isEmpty { ed.print("Select objects to show the gizmo.") }
            },
            CommandDef("CAMERAPATHEDIT", aliases: ["ANIMPATH", "CAMPATHS"], category: "View", summary: "Camera path editor: keys from the 3D view or saved cameras at times, timeline scrubbing and playback, video export.", modifies: false) { ed in
                CameraPathWindow.show(model: try ui(ed))
            },
            CommandDef("RENDERQUEUE", aliases: ["BATCHRENDER", "RENDERHISTORY"], category: "View", summary: "Render queue: add the current view or saved cameras, render them in turn to PNG files; render history with thumbnails.", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Render queue [Show/Current/Cameras/Run]", ["Show", "Current", "Cameras", "Run"], defaultValue: "Show") ?? "Show"
                let q = RenderQueue.shared
                switch k {
                case "Current": q.add(name: "\(m.doc.info.name) – view \(q.jobs.count + 1)", camera: Viewport3DController.active?.currentCamera, preset: nil)
                case "Cameras":
                    let cams = m.doc.namedViews.filter { $0.camera != nil }
                    for v in cams { q.add(name: "\(m.doc.info.name) – \(v.name)", camera: v.camera, preset: nil) }
                    ed.print("Queued \(cams.count) saved camera(s).")
                case "Run": q.start(model: m)
                default: break
                }
                RenderQueueWindow.show(model: m)
            },
            CommandDef("CLIPPLANES", aliases: ["CLIPPLANE", "CLIPPINGPLANE"], category: "View", summary: "Clipping plane panel in the 3D view: horizontal or vertical cut, live offset slider, flip, remove.", modifies: false) { ed in
                let m = try ui(ed)
                show3D(m)
                ClipPlaneState.shared.visible = true
            },
            CommandDef("SHARE", aliases: ["SHAREDRAWING", "SENDTO"], category: "Collaborate", summary: "Shares the drawing through the macOS share sheet (Mail, Messages, AirDrop, Notes…): Project (.archi), Pdf of the drawing or active sheet, or Both.", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Share [Project/Pdf/Both]", ["Project", "Pdf", "Both"], defaultValue: "Both") ?? "Both"
                let urls = try ShareSheet.files(model: m, project: k != "Pdf", pdf: k != "Project")
                ShareSheet.present(urls, model: m)
                ed.print("Sharing \(urls.map(\.lastPathComponent).joined(separator: ", ")).")
            },
            CommandDef("PRINTSETUP", aliases: ["PRINTOPTIONS", "QUICKPRINT"], category: "Output", summary: "Prints with printer, paper, tray (input slot), media, scaling (fit, 1:1, percent) and copies.", modifies: false) { ed in
                PrintSetupWindow.show(model: try ui(ed))
            },
        ]
    }
}


/// macOS share sheet for the drawing (COL-020): writes a snapshot of the project and/or a PDF to a temporary folder
/// (the open document is not changed) and shows the system sharing picker.
@MainActor
enum ShareSheet {
    static func files(model: AppModel, project: Bool, pdf: Bool) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        var base = model.doc.info.name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Drawing" }
        var out: [URL] = []
        if project {
            let u = dir.appendingPathComponent(base).appendingPathExtension(ArchiFile.fileExtension)
            try ArchiFile.encode(model.doc).write(to: u, options: .atomic)
            out.append(u)
        }
        if pdf {
            let u = dir.appendingPathComponent(base).appendingPathExtension("pdf")
            let layout: Int? = model.mode == .sheet && model.doc.layouts.indices.contains(model.activeLayout) ? model.activeLayout : nil
            try Plotter.exportPDF(model: model, to: u, layoutIndex: layout)
            out.append(u)
        }
        return out
    }
    static func present(_ urls: [URL], model: AppModel) {
        guard !urls.isEmpty, let v = model.window?.contentView else { NSWorkspace.shared.activateFileViewerSelecting(urls); return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: NSRect(x: v.bounds.maxX - 60, y: v.bounds.maxY - 40, width: 1, height: 1), of: v, preferredEdge: .minY)
    }
}
