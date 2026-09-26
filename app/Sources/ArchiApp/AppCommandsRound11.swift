// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SwiftUI
import ArchiCore

/// Commands of round 11: macOS Versions, paste from other apps and copy as picture, paper-relative zoom,
/// outliner window, accessibility read-out and the Finder/Spotlight file extras.
@MainActor
enum AppCommandsRound11 {
    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    private static func savedURL(_ ed: Editor) throws -> URL {
        guard let u = ed.fileURL, u.pathExtension.lowercased() == ArchiFile.fileExtension, FileManager.default.fileExists(atPath: u.path) else {
            throw CommandError.invalid("Save the drawing as an .archi file first.")
        }
        return u
    }

    static var all: [CommandDef] {
        [
            // MARK: macOS Versions (IO-002)
            CommandDef("FILEVERSIONS", aliases: ["BROWSEVERSIONS", "MACVERSIONS", "REVERTTO"], category: "File", summary: "macOS Versions of the saved file (every save keeps one): Browse window, List, Restore a version, Open a copy, Save a version now, Keep count.", modifies: false) { ed in
                let url = try savedURL(ed)
                let k = try await ed.getKeyword("Versions [Browse/List/Restore/Open/Save/Keep]", ["Browse", "List", "Restore", "Open", "Save", "Keep"], defaultValue: "Browse") ?? "Browse"
                let vs = FileVersions.list(url)
                switch k {
                case "List":
                    if vs.isEmpty { ed.print("No saved versions of \(url.lastPathComponent)."); return }
                    for (i, v) in vs.enumerated() { ed.print("  \(i + 1). \(FileVersions.label(v))") }
                case "Restore", "Open":
                    guard !vs.isEmpty else { throw CommandError.invalid("No saved versions of \(url.lastPathComponent).") }
                    guard let n = try await ed.getInteger("Version number (1 = newest) <1>", defaultValue: 1), vs.indices.contains(n - 1) else { throw CommandError.invalid("Enter 1–\(vs.count).") }
                    if k == "Open" {
                        let u = try FileVersions.copy(vs[n - 1], of: url)
                        WindowRouter.open(DocumentRequest(kind: .open, path: u.path))
                        ed.print("Opened a copy of the version of \(FileVersions.label(vs[n - 1])).")
                    } else {
                        try FileVersions.restore(vs[n - 1], url: url, model: AppCommands.model(ed))
                        ed.print("Restored the version of \(FileVersions.label(vs[n - 1])); the previous file is kept as a version.")
                    }
                case "Save":
                    ed.print(FileVersions.add(url) ? "Version of \(url.lastPathComponent) saved (\(FileVersions.list(url).count) in all)." : "Versions are not available on this volume.")
                case "Keep":
                    guard let n = try await ed.getInteger("Versions to keep per file <\(FileVersions.keep)>", defaultValue: FileVersions.keep), (1...1000).contains(n) else { throw CommandError.invalid("Enter 1–1000.") }
                    FileVersions.keep = n
                    ed.print("Keeping up to \(n) versions per file.")
                default:
                    VersionsWindow.show(model: try ui(ed), url: url)
                }
            },
            // MARK: Finder preview and Spotlight metadata (IO-006, IO-007)
            CommandDef("FILEPREVIEW", aliases: ["FINDERPREVIEW", "SPOTLIGHTINFO", "FILEMETADATA"], category: "File", summary: "Finder preview icon and Spotlight metadata of the saved drawing: Update now, Icons on/off, Versions on/off, Show the indexed metadata.", modifies: false) { ed in
                let k = try await ed.getKeyword("File preview [Update/Icons/Versions/Show]", ["Update", "Icons", "Versions", "Show"], defaultValue: "Update") ?? "Update"
                switch k {
                case "Icons":
                    let on = (try await ed.getKeyword("Finder preview icons on save [On/Off] <\(SaveExtras.finderPreview ? "On" : "Off")>", ["On", "Off"], defaultValue: SaveExtras.finderPreview ? "On" : "Off") ?? "On") == "On"
                    SaveExtras.finderPreview = on
                    ed.print("Finder preview icons \(on ? "on" : "off").")
                case "Versions":
                    let on = (try await ed.getKeyword("Keep a macOS version on every save [On/Off] <\(SaveExtras.versions ? "On" : "Off")>", ["On", "Off"], defaultValue: SaveExtras.versions ? "On" : "Off") ?? "On") == "On"
                    SaveExtras.versions = on
                    ed.print("Versions on save \(on ? "on" : "off").")
                case "Show":
                    let url = try savedURL(ed)
                    for key in ["kMDItemTitle", "kMDItemKeywords", "kMDItemAuthors", "org.oanarina.archi.levels", "org.oanarina.archi.rooms", "org.oanarina.archi.entityCount", "org.oanarina.archi.elementCount"] {
                        if let v = SpotlightXattr.read(key, from: url) { ed.print("  \(key): \(v is [Any] ? (v as! [Any]).map { "\($0)" }.joined(separator: ", ") : "\(v)")") }
                    }
                default:
                    let url = try savedURL(ed)
                    let n = SpotlightXattr.write(SpotlightMetadata.attributes(ed.doc), to: url)
                    let icon = SaveExtras.setFinderIcon(ed.doc, url: url, level: ed.doc.currentLevel)
                    ed.print("\(n) Spotlight attribute(s) written\(icon ? ", Finder preview icon updated" : "").")
                }
            },
            // MARK: Clipboard interoperability (IO-064)
            CommandDef("PASTESPECIAL", aliases: ["PASTESPEC", "PASTEEXTERNAL", "PASTEFROMAPP"], category: "Edit", summary: "Pastes what another app copied — SVG or PDF vectors, pictures, DXF text, plain text or Finder files — at an insertion point.") { ed in
                let m = try ui(ed)
                guard ExternalPaste.hasContent(.general) else { throw CommandError.invalid("The clipboard holds nothing from another app (use PASTECLIP for drawing objects).") }
                let p = try await ed.requirePoint("Specify insertion point")
                // The edit runs as its own transaction after the command so the pasted objects are one undo step.
                Task { @MainActor in
                    var n = 0
                    while !m.editor.isIdle && n < 100 { await Task.yield(); n += 1 }
                    ExternalPaste.paste(.general, into: m, at: p)
                }
            },
            CommandDef("COPYPICTURE", aliases: ["COPYASPDF", "COPYIMAGE", "COPYPDF"], category: "Edit", summary: "Copies the selected objects (or the whole drawing) to the clipboard as a vector PDF and a PNG picture for other apps.", modifies: false) { ed in
                let ids = try await ed.getSelection("Select objects <all>")
                let set: Set<EntityID>? = ids.isEmpty ? nil : Set(ids)
                guard let pdf = Artwork.pdf(ed.doc, ids: set, level: set == nil ? ed.doc.currentLevel : nil) else { throw CommandError.invalid("Nothing to copy.") }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(pdf.data, forType: .pdf)
                if let img = Artwork.thumbnail(ed.doc, size: 1600, level: set == nil ? ed.doc.currentLevel : nil, ids: set), let png = Artwork.png(img) { pb.setData(png, forType: .png) }
                ed.selection = []
                ed.print("Copied \(set.map { "\($0.count) object(s)" } ?? "the drawing") as a PDF at 1:\(fmt(pdf.ratio, 0)) and a PNG picture.")
            },
            // MARK: Zoom relative to paper units (VIS-005)
            CommandDef("ZOOMXP", aliases: ["ZXP", "ZOOMPAPER", "ZOOMSCALEXP"], category: "View", summary: "ZOOM nXP: in a sheet sets the selected viewport to 1:n (1/100XP); on the plan shows the drawing at that paper scale at true size on the screen.", modifies: false) { ed in
                guard let s = try await ed.getString("Enter scale relative to paper space (nXP, e.g. 1/100XP or 1:50) <1/100XP>", defaultValue: "1/100XP") else { return }
                try await PaperZoom.apply(ed, s)
            },
            // MARK: Outliner window (M3D-103)
            CommandDef("OUTLINERPANEL", aliases: ["OUTLINERWINDOW", "SHOWOUTLINER"], category: "3D", summary: "Outliner window: the tree of groups, components, blocks and model groups; click selects, double-click zooms, filter by name.", modifies: false) { ed in
                OutlinerWindow.show(model: try ui(ed))
            },
            // MARK: Accessibility (SYS-028 / SYS-029)
            CommandDef("SPEAKDRAWING", aliases: ["DESCRIBEDRAWING", "VOICEOVERSUMMARY", "A11YSUMMARY"], category: "Help", summary: "Describes the drawing, the selection and the current prompt (spoken by VoiceOver, printed on the command line).", modifies: false) { ed in
                let m = try ui(ed)
                let t = A11y.summary(m)
                ed.print(t)
                A11y.announce(t, force: true)
            },
            CommandDef("KEYBOARDNAV", aliases: ["KEYCURSOR", "KEYBOARDHELP"], category: "Help", summary: "Keyboard-only drawing: arrow keys move the crosshair at prompts (Shift ×10, Option ÷10; Option-arrows when idle), Return picks, Tab selects under the crosshair; sets the step.", modifies: false) { ed in
                let cur = KeyboardCursor.step
                guard let v = try await ed.getInteger("Crosshair step in screen pixels <\(cur)>", defaultValue: cur), (1...200).contains(v) else { throw CommandError.invalid("Enter 1–200 pixels.") }
                KeyboardCursor.step = v
                for l in KeyboardCursor.help { ed.print("  " + l) }
            },
            MechanismPlayback.command,
            L10n.command,
        ]
    }
}

// MARK: - Paper-relative zoom maths

enum PaperZoom {
    /// "1/100XP", "0.01xp", "1:100", "1/50" → paper/model factor (0.01).
    static func factor(_ s0: String) -> Double? {
        var s = s0.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("xp") { s.removeLast(2) } else if s.hasSuffix("x") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        var v: Double?
        for sep in [":", "/"] where s.contains(sep) {
            let p = s.split(separator: Character(sep)).map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count == 2, let a = p[0], let b = p[1], b != 0 { v = a / b }
            break
        }
        if v == nil, !s.contains(":"), !s.contains("/") { v = Double(s) }
        guard let f = v, f.isFinite, f > 0, f <= 1000 else { return nil }
        return f
    }
    /// Viewport scale (model units per paper mm) for a paper/model factor.
    static func viewportScale(factor f: Double, units: Units) -> Double { (1 / f) / units.mm }
    /// Canvas scale (screen points per drawing unit) that shows the drawing at paper scale `f`, true size.
    static func canvasScale(factor f: Double, units: Units, pointsPerScreenMM: CGFloat) -> CGFloat { pointsPerScreenMM * CGFloat(units.mm * f) }
    /// Screen points per physical millimetre of the main display (72 dpi when unknown).
    @MainActor static func screenPointsPerMM() -> CGFloat {
        guard let s = NSScreen.main, let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 72 / 25.4 }
        let mm = CGDisplayScreenSize(CGDirectDisplayID(n.uint32Value))
        guard mm.width > 10 else { return 72 / 25.4 }
        return s.frame.width / mm.width
    }
}

// MARK: - 3D view: file drops and Ctrl-click sub-objects

extension Viewport3DController {
    /// Files dropped on the 3D view land at the model point under the cursor (IO-065).
    func dropFiles(_ urls: [URL], at p: CGPoint) -> Bool {
        guard let model, FileDrop.accepts(urls) else { return false }
        let at = modelPoint(at: p).map { Vec2($0.point.x, $0.point.y) } ?? .zero
        FileDrop.perform(urls, at: at, model: model)
        return true
    }

    /// Sub-object command line for a Ctrl-click on a solid (face / edge / vertex by SUBOBJECTMODE), nil elsewhere.
    static func subObjectLine(id: EntityID, point q: Vec3, doc: ArchiDocument) -> String? {
        guard let e = doc.entity(id), case .solid = e.geometry else { return nil }
        let mode = doc.variable("SUBOBJECTMODE") ?? "Face"
        return "SUBOBJECT #\(id) \(["Face", "Edge", "Vertex"].contains(mode) ? mode : "Face") *\(fmt(q.x, 6)),\(fmt(q.y, 6)),\(fmt(q.z, 6))"
    }

    /// Ctrl-click (M3D-052): starts sub-object editing of what is under the cursor; the action prompt stays interactive.
    func subObjectPick(at p: CGPoint) -> Bool {
        guard let model, model.has("SUBOBJECT"), let hit = modelPoint(at: p), let id = hit.id,
              let line = Self.subObjectLine(id: id, point: hit.point, doc: model.doc) else { return false }
        model.runCommand(line)
        return true
    }
}

// MARK: - Outliner window

struct OutlinerItem: Identifiable, Hashable {
    let id: String
    let node: Outliner.Node
    let children: [OutlinerItem]?
    static func items(_ nodes: [Outliner.Node], path: String = "") -> [OutlinerItem] {
        nodes.enumerated().map { i, n in
            let p = path + "/\(i)"
            return OutlinerItem(id: p, node: n, children: n.children.isEmpty ? nil : items(n.children, path: p))
        }
    }
    /// Items whose name (or a descendant's) contains the filter text.
    static func filtered(_ items: [OutlinerItem], _ q: String) -> [OutlinerItem] {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return items }
        return items.compactMap { it in
            let kids = filtered(it.children ?? [], t)
            if it.node.name.localizedCaseInsensitiveContains(t) { return it }
            return kids.isEmpty ? nil : OutlinerItem(id: it.id, node: it.node, children: kids)
        }
    }
    var symbol: String {
        switch node.kind {
        case "group": return "square.on.square.dashed"
        case "component": return "cube"
        case "block": return "square.on.square"
        case "modelGroup": return "square.3.layers.3d"
        case "modelGroupInstance": return "square.stack.3d.up"
        default: return "cube.transparent"
        }
    }
}

@MainActor
enum OutlinerWindow {
    private static var panel: NSPanel?
    static func show(model: AppModel) {
        if let p = panel, p.isVisible { p.makeKeyAndOrderFront(nil); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Outliner"
        p.isFloatingPanel = true
        p.isReleasedWhenClosed = false
        p.appearance = Theme.appearance
        p.contentViewController = NSHostingController(rootView: OutlinerView(model: model).preferredColorScheme(Theme.colorScheme))
        p.setFrameAutosaveName("ArchiOutliner")
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

struct OutlinerView: View {
    @ObservedObject var model: AppModel
    @State private var filter = ""
    var body: some View {
        let items = OutlinerItem.filtered(OutlinerItem.items(Outliner.tree(model.doc)), filter)
        VStack(spacing: 6) {
            TextField("Filter by name", text: $filter).textFieldStyle(.roundedBorder).accessibilityLabel("Filter outliner by name")
            if items.isEmpty {
                Text("No groups or components. Use MAKEGROUP or MAKECOMPONENT.").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                Spacer()
            } else {
                List(items, children: \.children) { it in
                    HStack(spacing: 6) {
                        Image(systemName: it.symbol).foregroundStyle(it.node.id.map { model.editor.selection.contains($0) } == true ? Theme.accent : Theme.textDim)
                        Text(it.node.name).lineLimit(1)
                        Spacer()
                        Text(it.node.kind).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { select(it, zoom: true) }
                    .onTapGesture { select(it, zoom: false) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(it.node.kind) \(it.node.name)")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .padding(8)
    }
    private func select(_ it: OutlinerItem, zoom: Bool) {
        guard let id = it.node.id else { return }
        model.editor.selection = [id]
        model.revision &+= 1
        if zoom, let e = model.doc.entity(id) { model.canvas?.zoom(to: GeometryOps.bounds(e.geometry, doc: model.doc)) }
    }
}

// MARK: - Accessibility (SYS-028)

@MainActor
enum A11y {
    private static var lastPrompt = ""

    /// Spoken description of the window: view, level, contents, selection and prompt.
    static func summary(_ m: AppModel) -> String {
        let d = m.doc
        var parts: [String] = []
        let view = m.mode == .sheet ? "Sheet \(d.layouts.indices.contains(m.activeLayout) ? d.layouts[m.activeLayout].name : "")" : (m.mode == .model ? "3D view" : "Plan")
        parts.append(view + (d.levels.isEmpty ? "" : ", level \(d.level(d.currentLevel)?.name ?? "")") + ", layer \(d.currentLayer).")
        parts.append("\(d.entities.count) drawing object\(d.entities.count == 1 ? "" : "s"), \(d.elements.count) building element\(d.elements.count == 1 ? "" : "s").")
        let sel = m.editor.selection
        if !sel.isEmpty {
            var kinds: [String: Int] = [:]
            for id in sel {
                if let e = d.entity(id) { kinds[e.typeName, default: 0] += 1 } else if let el = d.element(id) { kinds[el.typeName, default: 0] += 1 }
            }
            parts.append("Selected: " + kinds.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") + ".")
        } else { parts.append("Nothing selected.") }
        if let r = m.editor.request { parts.append("Prompt: \(r.message)" + (r.keywords.isEmpty ? "" : ", options \(r.keywords.joined(separator: ", "))") + ".") }
        else { parts.append("Ready for a command.") }
        let c = m.cursorWorld
        parts.append("Crosshair at \(fmt(c.x, 2)), \(fmt(c.y, 2)).")
        return parts.joined(separator: " ")
    }

    static func announce(_ text: String, force: Bool = false) {
        guard force || NSWorkspace.shared.isVoiceOverEnabled, let el = NSApp.mainWindow ?? NSApp.keyWindow else { return }
        NSAccessibility.post(element: el, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Speaks a new command prompt (VoiceOver only).
    static func promptChanged(_ m: AppModel) {
        let p = m.editor.request?.message ?? ""
        guard p != lastPrompt else { return }
        lastPrompt = p
        if !p.isEmpty { announce(p) }
    }

    /// Short spoken name from a tooltip ("Zoom Extents — fits the drawing (Z E)" → "Zoom Extents").
    nonisolated static func label(_ help: String) -> String {
        var t = help
        for sep in [" — ", " - ", " (", ": ", ". "] { if let r = t.range(of: sep), r.lowerBound > t.startIndex { t = String(t[..<r.lowerBound]) } }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " .…"))
        return t.isEmpty ? help : t
    }

    /// Accessibility names of the status bar toggles.
    static let toggleNames: [String: String] = [
        "GRID": "Grid display", "SNAP": "Snap to grid", "ORTHO": "Ortho mode", "POLAR": "Polar tracking", "OTRACK": "Object snap tracking",
        "OSNAP": "Object snap", "DYN": "Dynamic input", "LWT": "Show lineweights",
    ]
}

// MARK: - Keyboard crosshair (SYS-029)

@MainActor
enum KeyboardCursor {
    static let stepKey = "keyboardCursorStep"
    static var step: Int {
        get { max(1, UserDefaults.standard.object(forKey: stepKey) as? Int ?? 10) }
        set { UserDefaults.standard.set(max(1, min(200, newValue)), forKey: stepKey) }
    }
    /// Screen offset for an arrow key (123 ←, 124 →, 125 ↓, 126 ↑) with Shift (×10) / Option (÷10).
    static func offset(keyCode: UInt16, shift: Bool, option: Bool) -> CGVector? {
        var s = CGFloat(step)
        if shift { s *= 10 }
        if option { s = max(1, s / 10) }
        switch keyCode {
        case 123: return CGVector(dx: -s, dy: 0)
        case 124: return CGVector(dx: s, dy: 0)
        case 125: return CGVector(dx: 0, dy: -s)
        case 126: return CGVector(dx: 0, dy: s)
        default: return nil
        }
    }
    static let help = [
        "Type a command name and Return; answer prompts by typing (coordinates, @relative, distances, keyword letters).",
        "At a point prompt the arrow keys move the crosshair (Shift ×10, Option ÷10); Return picks the snapped point.",
        "With no command running, Option-arrows move the crosshair and Tab selects the object under it (Tab also answers Select objects prompts).",
        "SPEAKDRAWING describes the drawing, selection and prompt (VoiceOver reads new prompts automatically).",
    ]
}

// MARK: - Ribbon / menu entries for the commands of round 11

extension CommandCatalog {
    private static func c11(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }
    /// Components, datums, sub-objects, surfaces and terrain of round 11 (core).
    static let modelRound11: [CmdItem] = [
        c11("Make Component", "cube", "MAKECOMPONENT"), c11("Make Group", "square.on.square.dashed", "MAKEGROUP"), c11("Make Unique", "square.on.square", "MAKEUNIQUE"),
        c11("Component to BIM", "building.2", "COMPONENTTOBIM"), c11("Outliner", "list.bullet.indent", "OUTLINER"), c11("Outliner Window", "sidebar.left", "OUTLINERPANEL"),
        c11("Datum Plane/Axis/Point", "scope", "DATUM"), c11("Sub-object Edit", "cube.transparent", "SUBOBJECT"), c11("Imprint", "square.and.pencil", "IMPRINT"),
        c11("Offset Face", "square.dashed.inset.filled", "OFFSETFACE"), c11("Blend Surface", "point.topleft.down.curvedto.point.bottomright.up", "SURFBLEND"),
        c11("Surface Analysis", "waveform.path", "SURFANALYSIS"), c11("Sandbox Terrain", "mountain.2", "SANDBOX"),
    ]
    /// Images, links, tags, materials and structure of round 11 (core).
    static let insertRound11: [CmdItem] = [
        c11("Clip Image", "crop", "IMAGECLIP"), c11("Adjust Image", "slider.horizontal.3", "IMAGEADJUST"), c11("Image Frame", "rectangle.dashed", "IMAGEFRAME"),
        c11("Link Model", "link", "RVTLINK"), c11("Copy/Monitor", "arrow.triangle.2.circlepath", "COPYMONITOR"), c11("Tag Label", "tag", "TAGLABEL"),
        c11("Material Hatch", "square.grid.3x3.fill", "MATHATCH"), c11("Material Patterns", "square.grid.3x3", "MATPATTERN"),
        c11("Rebar", "line.3.horizontal", "REBAR"), c11("Steel Connection", "square.split.bottomrightquarter", "STEELCONNECTION"),
    ]
    /// App commands of round 11.
    static let appRound11: [CmdItem] = [
        c11("Browse Versions", "clock.arrow.circlepath", "FILEVERSIONS"), c11("File Preview & Spotlight", "doc.text.magnifyingglass", "FILEPREVIEW"),
        c11("Paste from Other App", "doc.on.clipboard", "PASTESPECIAL"), c11("Copy as Picture", "photo.on.rectangle", "COPYPICTURE"),
        c11("Zoom to Paper Scale", "1.magnifyingglass", "ZOOMXP"), c11("Describe Drawing", "speaker.wave.2", "SPEAKDRAWING"),
        c11("Keyboard Navigation", "keyboard", "KEYBOARDNAV"), c11("Play Mechanism", "play.circle", "MECHANISMPLAY"), c11("Language", "globe", "LANGUAGE"),
    ]
    static var coverageMenus7: [(String, [CmdItem])] {
        [("Components & Surfaces", modelRound11), ("Images, Links & Structure", insertRound11), ("Files, Clipboard & Access", appRound11)] + coverageMenus8
    }
}

// MARK: - Dynamic UCS display on the plan (PRC-036)

@MainActor
enum DUCSOverlay {
    /// The active dynamic face of the running command, else the face under the crosshair when DUCS is on.
    static func face(editor ed: Editor, cursor: Vec2) -> DynamicUCS.Face? {
        ed.dynamicFaceFrame ?? DynamicUCS.activeFace(at: cursor, doc: ed.doc)?.rotatedX(to: UCSFrame.current(ed.doc).angle)
    }
    /// Plan segments of the face axes at the crosshair: X red, Y green, normal blue (projected; vertical axes vanish).
    static func segments(_ f: DynamicUCS.Face, at p: Vec2, length L: Double) -> [(Vec2, Vec2, RGBA)] {
        let o = f.planePoint(p).map { Vec2($0.x, $0.y) } ?? p
        var out: [(Vec2, Vec2, RGBA)] = []
        for (axis, col) in [(f.xAxis, RGBA(0.95, 0.25, 0.2)), (f.yAxis, RGBA(0.3, 0.85, 0.3)), (f.normal, RGBA(0.3, 0.55, 1))] {
            let d = Vec2(axis.x, axis.y)
            if d.length > 0.05 { out.append((o, o + d * L, col)) }
        }
        return out
    }
    static func draw(_ segs: [(Vec2, Vec2, RGBA)], ctx: CGContext, scale: CGFloat) {
        ctx.saveGState()
        ctx.setLineWidth(2 / scale)
        for (a, b, c) in segs {
            ctx.setStrokeColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.95))
            ctx.move(to: CGPoint(x: a.x, y: a.y)); ctx.addLine(to: CGPoint(x: b.x, y: b.y)); ctx.strokePath()
        }
        if let o = segs.first?.0 {
            let r = 4 / scale
            ctx.setStrokeColor(CGColor(srgbRed: 0.961, green: 0.773, blue: 0.094, alpha: 1))
            ctx.strokeEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r))
        }
        ctx.restoreGState()
    }
}

// MARK: - Mechanism playback (M3D-088)

/// Plays the poses of a mechanism simulation as an animated overlay on the plan (the drawing is not changed).
@MainActor
final class MechanismPlayback {
    enum Mode: String, CaseIterable { case once = "Once", loop = "Loop", bounce = "Bounce" }
    static var byModel: [ObjectIdentifier: MechanismPlayback] = [:]

    let poses: [[Entity]]
    let mode: Mode
    private(set) var tick = 0
    private var timer: Timer?
    private weak var model: AppModel?
    static let maxLoops = 20

    init(poses: [[Entity]], mode: Mode, model: AppModel?) { self.poses = poses; self.mode = mode; self.model = model }

    /// Pose shown at a tick (nil = finished).
    static func frame(tick: Int, count n: Int, mode: Mode) -> Int? {
        guard n > 0, tick >= 0 else { return nil }
        switch mode {
        case .once: return tick < n ? tick : nil
        case .loop: return tick < n * maxLoops ? tick % n : nil
        case .bounce:
            guard n > 1 else { return tick < maxLoops ? 0 : nil }
            let period = 2 * (n - 1)
            guard tick < period * maxLoops else { return nil }
            let t = tick % period
            return t < n ? t : period - t
        }
    }
    var current: Int? { Self.frame(tick: tick, count: poses.count, mode: mode) }

    /// Overlay items of the current pose (accent colour).
    func items(doc: ArchiDocument) -> [DrawItem] {
        guard let i = current else { return [] }
        return DrawListBuilder.previewItems(poses[i].map(\.geometry), doc: doc, color: RGBA(0.961, 0.773, 0.094))
    }
    static func items(for model: AppModel) -> [DrawItem]? { byModel[ObjectIdentifier(model)]?.items(doc: model.doc) }

    func start(fps: Double) {
        guard let model else { return }
        MechanismPlayback.byModel[ObjectIdentifier(model)]?.stop()
        MechanismPlayback.byModel[ObjectIdentifier(model)] = self
        timer = Timer.scheduledTimer(withTimeInterval: 1 / max(1, min(120, fps)), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }
    func advance() {
        tick += 1
        if current == nil { stop() } else { model?.canvas?.needsDisplayOverlay() }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let m = model, MechanismPlayback.byModel[ObjectIdentifier(m)] === self { MechanismPlayback.byModel[ObjectIdentifier(m)] = nil; m.canvas?.needsDisplayOverlay() }
    }

    static var command: CommandDef {
        CommandDef("MECHANISMPLAY", aliases: ["ANIMATEMECHANISM", "PLAYMECHANISM", "MECHANISMANIMATE"], category: "Parametric", summary: "Animates a mechanism on the plan: steps a named driving dimension through a range (re-solving the constraints) and plays the poses Once, in a Loop or Bounce; Stop ends it. The drawing is not changed.", modifies: false) { ed in
            guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
            if let p = byModel[ObjectIdentifier(m)] {
                if (try await ed.getKeyword("Mechanism is playing [Stop/Restart] <Stop>", ["Stop", "Restart"], defaultValue: "Stop") ?? "Stop") == "Stop" { p.stop(); ed.print("Mechanism playback stopped."); return }
                p.stop()
            }
            let set = ConstraintSet.load(ed.doc)
            guard let name = try await ed.getString("Driving dimension name", defaultValue: set.constraints.first { $0.name != nil && $0.kind.isDimensional }?.name)?.trimmingCharacters(in: .whitespaces),
                  let c = set.named(name), c.kind.isDimensional else { throw CommandError.invalid("No dimensional constraint with that name.") }
            let isAngle = c.kind == .angle
            let cur = Constraints.displayValue(c, set: set, doc: ed.doc) ?? c.value ?? 0
            let k = isAngle ? 180 / Double.pi : 1
            func real(_ msg: String, _ def: Double) async throws -> Double {
                let t = (try await ed.getString("\(msg) <\(fmt(def))>", defaultValue: fmt(def)) ?? "").trimmingCharacters(in: .whitespaces)
                if t.isEmpty { return def }
                guard let v = Double(t), v.isFinite else { throw CommandError.invalid("Enter a number.") }
                return v
            }
            let a = try await real("From value" + (isAngle ? " (degrees)" : ""), cur * k)
            let b = try await real("To value" + (isAngle ? " (degrees)" : ""), cur * k + (isAngle ? 360 : 100))
            let n = max(1, min(1440, try await ed.getInteger("Number of frames", defaultValue: 72) ?? 72))
            let fps = Double(max(1, min(120, try await ed.getInteger("Frames per second", defaultValue: 24) ?? 24)))
            let mode = Mode(rawValue: try await ed.getKeyword("Playback [Once/Loop/Bounce]", Mode.allCases.map(\.rawValue), defaultValue: "Loop") ?? "Loop") ?? .loop
            guard let r = Mechanisms.simulate(ed.doc, driver: name, from: a / k, to: b / k, steps: n, keepPoses: true), !r.poses.isEmpty else { throw CommandError.invalid("The mechanism cannot move from its current pose.") }
            let locked = r.frames.count > r.poses.count
            MechanismPlayback(poses: r.poses, mode: mode, model: m).start(fps: fps)
            ed.print("Playing \(r.poses.count) pose(s) at \(fmt(fps, 0)) fps (\(mode.rawValue.lowercased()))" + (locked ? "; lock-up at \(fmt((r.frames.last?.value ?? 0) * k))." : ".") + " MECHANISMPLAY again stops.")
        }
    }
}


@MainActor extension PaperZoom {
    /// ZOOM nXP: in a sheet sets the selected viewport to 1:n; on the plan shows the drawing at that paper scale at true size.
    static func apply(_ ed: Editor, _ s: String) async throws {
        let m = try AppCommandsExtra.ui(ed)
        guard let f = PaperZoom.factor(s) else { throw CommandError.invalid("Enter a scale such as 1/100XP, 0.01XP or 1:100.") }
        if m.mode == .sheet, let vi = m.selectedSheetViewport, m.doc.layouts.indices.contains(m.activeLayout), m.doc.layouts[m.activeLayout].viewports.indices.contains(vi) {
            let li = m.activeLayout
            m.editor.transaction("Viewport scale") { d in d.layouts[li].viewports[vi].scale = PaperZoom.viewportScale(factor: f, units: d.units) }
            m.revision &+= 1
            ed.print("Viewport \(vi + 1) at 1:\(fmt(1 / f, 2)).")
            return
        }
        guard let c = m.canvas else { throw CommandError.invalid("Open the plan view.") }
        let target = PaperZoom.canvasScale(factor: f, units: ed.doc.units, pointsPerScreenMM: PaperZoom.screenPointsPerMM())
        c.zoomBy(target / c.scale)
        ed.print("Plan shown at 1:\(fmt(1 / f, 2)) on paper, true size on this screen.")
    }
    /// Lets the core ZOOM command accept nXP.
    static func installZoomHook() {
        ZoomHooks.paperZoom = { ed, s in
            guard PaperZoom.factor(s) != nil else { return false }
            try await PaperZoom.apply(ed, s)
            return true
        }
    }
}
