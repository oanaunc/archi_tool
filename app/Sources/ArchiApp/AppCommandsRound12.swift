// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import ArchiCore

/// Commands of round 12: dialogs for object styles, text styles, image adjustment, ambient occlusion and material
/// fill patterns (the command-line forms live in the core: OBJECTSTYLES, STYLE, IMAGEADJUST, AMBIENTOCCLUSION, MATPATTERN).
@MainActor
enum AppCommandsRound12 {
    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }

    static var all: [CommandDef] {
        [
            CommandDef("OBJECTSTYLESDIALOG", aliases: ["OBJECTSTYLESDLG", "OSTYLESDIALOG"], category: "Manage", summary: "Object Styles dialog: projection/cut line weights, line colour, cut fill and cut pattern per BIM category for every plan and section.", modifies: false) { ed in
                let m = try ui(ed)
                Round12Panels.show("objectStyles", title: "Object Styles", size: NSSize(width: 700, height: 520), ObjectStylesPanel(model: m))
            },
            CommandDef("TEXTSTYLEDIALOG", aliases: ["TEXTSTYLEMANAGER", "STYLEDIALOG"], category: "Annotate", summary: "Text Style manager: font, height, width factor and oblique angle with a live preview; renaming a style updates its text.", modifies: false) { ed in
                let m = try ui(ed)
                Round12Panels.show("textStyles", title: "Text Styles", size: NSSize(width: 600, height: 400), TextStylesPanel(model: m))
            },
            CommandDef("IMAGEADJUSTDIALOG", aliases: ["IMAGEADJUSTDLG", "IADDIALOG"], category: "Blocks", summary: "Image Adjust dialog: brightness, contrast and fade of the selected raster images with a preview (exact on screen and in PDF plots).", modifies: false) { ed in
                let m = try ui(ed)
                var ids = ed.selection.filter { if case .image? = ed.doc.entity($0)?.geometry { return true }; return false }.sorted()
                if ids.isEmpty {
                    let sel = try await ed.getSelection("Select images")
                    ids = sel.filter { if case .image? = ed.doc.entity($0)?.geometry { return true }; return false }.sorted()
                }
                guard !ids.isEmpty else { throw CommandError.invalid("Select one or more images.") }
                Round12Panels.show("imageAdjust", title: "Image Adjust", size: NSSize(width: 420, height: 380), ImageAdjustPanel(model: m, ids: ids))
            },
            CommandDef("AODIALOG", aliases: ["AMBIENTOCCLUSIONDIALOG", "AOPANEL"], category: "View", summary: "Ambient Occlusion dialog: intensity, radius and rays per point for the 3D viewport, renders and shaded views.", modifies: false) { ed in
                let m = try ui(ed)
                Round12Panels.show("ao", title: "Ambient Occlusion", size: NSSize(width: 420, height: 220), AOPanel(model: m))
            },
            CommandDef("TEXTEDITINPLACE", aliases: ["MTEDIT", "INPLACETEXT", "TEXTFORMAT"], category: "Annotate", summary: "In-place text editor on the canvas: bold, italic, underline, font, height and colour (also opened by double-clicking text); exported to PDF and DXF MTEXT.", modifies: false) { ed in
                let m = try ui(ed)
                guard let id = try await ed.getEntity("Select text"), case .text? = ed.doc.entity(id)?.geometry else { throw CommandError.invalid("Select a text object.") }
                guard let c = m.canvas, c.window != nil else { throw CommandError.invalid("Show the 2D plan to edit text in place.") }
                InPlaceTextEditor.begin(canvas: c, model: m, id: id)
            },
            CommandDef("VRVIEW", aliases: ["WEBXR", "VREXPORT", "HEADSETVIEW"], category: "View", summary: "VR headset viewing: writes the model as a WebXR page (life-size, floor on the room floor, pinch/trigger steps forward) for Apple Vision Pro, Meta Quest or OpenXR browsers; Open, Reveal (AirDrop) or just Save.", modifies: false) { ed in
                let s = WebViewerExport.scene(doc: ed.doc)
                guard s.triangles > 0 else { throw CommandError.invalid("The model has no 3D content.") }
                let k = try await ed.getKeyword("After saving [Open/Reveal/Save]", ["Open", "Reveal", "Save"], defaultValue: "Reveal") ?? "Reveal"
                let base = ed.fileURL?.deletingPathExtension().lastPathComponent ?? (ed.doc.info.name.isEmpty ? "Model" : ed.doc.info.name)
                let dir = ed.fileURL?.deletingLastPathComponent() ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                let url = dir.appendingPathComponent(base + "-VR.html")
                try WebViewerExport.html(doc: ed.doc).write(to: url, atomically: true, encoding: .utf8)
                ed.print("VR page: \(s.triangles) triangles → \(url.path). Open it in the headset's browser (AirDrop to Vision Pro, or host it over HTTPS) and choose Enter VR.")
                if k == "Open" { NSWorkspace.shared.open(url) } else if k == "Reveal" { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            },
            CommandDef("CRASHREPORTS", aliases: ["CRASHREPORT", "CRASHLOG"], category: "Settings", summary: "Opt-in crash reports: On, Off, Status, Show the saved reports (reviewed and sent only by you), Clear.", modifies: false) { ed in
                let k = try await ed.getKeyword("Crash reports [On/Off/Status/Show/Clear]", ["On", "Off", "Status", "Show", "Clear"], defaultValue: "Status") ?? "Status"
                switch k {
                case "On": CrashReporter.enabled = true; ed.print("Crash reports on: a report is saved if the app quits unexpectedly (nothing is sent automatically).")
                case "Off": CrashReporter.enabled = false; ed.print("Crash reports off.")
                case "Show":
                    let p = CrashReporter.pendingReports()
                    if p.isEmpty { ed.print("No saved crash reports.") } else { NSWorkspace.shared.activateFileViewerSelecting(p); ed.print("\(p.count) crash report(s) in \(CrashReporter.folder.path).") }
                case "Clear":
                    let p = CrashReporter.pendingReports()
                    for u in p { try? FileManager.default.removeItem(at: u) }
                    ed.print("\(p.count) crash report(s) removed.")
                default: ed.print("Crash reports \(CrashReporter.enabled ? "on" : "off"); \(CrashReporter.pendingReports().count) saved. \(CrashReporter.environment()).")
                }
            },
            CommandDef("MATPATTERNDIALOG", aliases: ["MATERIALPATTERNSDIALOG", "FILLPATTERNSDIALOG"], category: "Annotate", summary: "Material Fill Patterns dialog: cut and surface pattern of every material; bound hatches and floor patterns update.", modifies: false) { ed in
                let m = try ui(ed)
                Round12Panels.show("matPatterns", title: "Material Fill Patterns", size: NSSize(width: 560, height: 420), MaterialPatternsPanel(model: m))
            },
        ]
    }
}

extension CommandCatalog {
    private static func c13(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }
    /// Ribbon/menu entries of round 12 (core commands added by the other areas and the app dialogs above).
    static let round12Items: [CmdItem] = [
        c13("Object Styles…", "square.3.layers.3d.middle.filled", "OBJECTSTYLESDIALOG"), c13("Object Styles (command)", "list.bullet.indent", "OBJECTSTYLES"),
        c13("Text Styles…", "textformat", "TEXTSTYLEDIALOG"), c13("Image Adjust…", "slider.horizontal.3", "IMAGEADJUSTDIALOG"),
        c13("Ambient Occlusion…", "circle.lefthalf.filled.righthalf.striped.horizontal", "AODIALOG"), c13("Ambient Occlusion (command)", "circle.bottomhalf.filled", "AMBIENTOCCLUSION"),
        c13("Crash Reports", "ladybug", "CRASHREPORTS"), c13("VR Headset View", "eyeglasses", "VRVIEW"), c13("Edit Text In Place", "character.cursor.ibeam", "TEXTEDITINPLACE"), c13("Material Fill Patterns…", "square.grid.3x3.square", "MATPATTERNDIALOG"), c13("Floor Pattern", "square.grid.4x3.fill", "FLOORPATTERN"),
    ]
    /// Core commands the other areas added during round 12 (exchange formats and the like).
    static let round12Core: [CmdItem] = [
        c13("Rhino 3DM In", "square.and.arrow.down.on.square", "RHINOIN"), c13("Rhino 3DM Out", "square.and.arrow.up.on.square", "RHINOOUT"),
    ]
    static var coverageMenus9: [(String, [CmdItem])] { [("Styles, Patterns & Occlusion", round12Items), ("Exchange More", round12Core)] }
}
