// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import PDFKit
import SceneKit
import Metal
import ArchiCore

/// Checks of round 11: clipboard interoperability, file drops, Spotlight/Finder/Versions file extras, paper zoom,
/// Ctrl-click sub-objects, outliner window, accessibility and keyboard-only drawing, and the command coverage.
@MainActor
extension AppSelfTests {
    static func round11Checks(_ check: (Bool, String) -> Void) {
        artworkChecks(check)
        clipboardInteropChecks(check)
        fileExtrasChecks(check)
        paperZoomChecks(check)
        outlinerAndSubObjectChecks(check)
        accessibilityChecks(check)
        viewportShadowChecks(check)
        syncChecks(check)
        ducsChecks(check)
        scriptedComponentChecks(check)
        mechanismPlaybackChecks(check)
        localizationChecks(check)
        let names = Set(CommandCatalog.coverageMenus.flatMap(\.1).flatMap(\.names))
        check(AppCommandsRound11.all.allSatisfy { names.contains($0.name) }, "round 11 commands have menu entries")
    }

    private static func sampleDoc() -> (ArchiDocument, EntityID, EntityID) {
        var d = ArchiDocument()
        let a = d.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 0))), layer: "0")
        let b = d.add(.circle(CircleGeom(Vec2(5000, 3000), 1000)), layer: "0")
        d.info.name = "Selftest House"
        return (d, a, b)
    }

    private static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiSelfTest11-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Thumbnails and PDF pictures of drawings.
    static func artworkChecks(_ check: (Bool, String) -> Void) {
        let (d, a, _) = sampleDoc()
        guard let img = Artwork.thumbnail(d, size: 128) else { check(false, "thumbnail renders"); return }
        let rep = NSBitmapImageRep(cgImage: img)
        var dark = 0
        for y in 0..<128 { for x in 0..<128 { if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.7 { dark += 1 } } }
        check(img.width == 128 && dark > 20, "thumbnail shows the drawing in dark ink on white (\(dark) dark samples)")
        check(Artwork.thumbnail(ArchiDocument(), size: 64) != nil && Artwork.thumbnail(d, size: 4) == nil, "thumbnail of an empty drawing; invalid size refused")
        guard let pdf = Artwork.pdf(d, ids: [a]) else { check(false, "PDF picture of a line"); return }
        let doc = PDFDocument(data: pdf.data)
        let box = doc?.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
        // 10 m at 1:50 = 200 mm = 566.9 pt (+ 24 pt margins).
        check(doc?.pageCount == 1 && pdf.ratio == 50 && abs(box.width - (10000 / 50 * Plotter.pointsPerMM + 24)) < 0.5, "PDF picture at a standard scale (1:\(fmt(pdf.ratio, 0)), \(fmt(Double(box.width), 1)) pt)")
        check(Artwork.pdf(d, ids: [999_999]) == nil, "PDF picture of nothing is refused")
    }

    /// IO-064 / IO-065: pasting from other apps, copying pictures, dropping files.
    static func clipboardInteropChecks(_ check: (Bool, String) -> Void) {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.oanarina.archi.selftest.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let m = AppModel()
        var d0 = ArchiDocument(); d0.info.name = "Paste target"
        m.editor.replaceDocument(d0, url: nil)

        // Plain text from another app → text object; one undo step.
        pb.clearContents(); pb.setString("Room 1.01 Living", forType: .string)
        check(ExternalPaste.content(pb)?.type == "text", "clipboard: plain text recognised")
        let tIDs = ExternalPaste.paste(pb, into: m, at: Vec2(100, 200)) ?? []
        if let id = tIDs.first, case .text(let t)? = m.doc.entity(id)?.geometry {
            check(t.content == "Room 1.01 Living" && t.position.isClose(Vec2(100, 200), tol: 1e-9), "clipboard: text pasted at the point")
        } else { check(false, "clipboard: text pasted") }
        m.editor.undo()
        check(m.doc.entities.isEmpty, "clipboard: paste is one undo step")

        // SVG vectors.
        pb.clearContents()
        pb.setData(Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50"><line x1="0" y1="0" x2="100" y2="0" stroke="black"/><rect x="10" y="10" width="30" height="20" fill="none" stroke="black"/></svg>"#.utf8), forType: ExternalPaste.svgType)
        check(ExternalPaste.content(pb)?.type == "svg", "clipboard: SVG recognised")
        let sIDs = ExternalPaste.paste(pb, into: m, at: Vec2(1000, 1000)) ?? []
        check(sIDs.count >= 2, "clipboard: SVG pasted as \(sIDs.count) drawing object(s)")

        // A picture (PNG) from another app → image entity whose file exists.
        let (sd, sa, _) = sampleDoc()
        if let img = Artwork.thumbnail(sd, size: 64), let png = Artwork.png(img) {
            pb.clearContents(); pb.setData(png, forType: .png)
            let iIDs = ExternalPaste.paste(pb, into: m, at: Vec2(0, 0)) ?? []
            if let id = iIDs.first, case .image(let im)? = m.doc.entity(id)?.geometry {
                check(FileManager.default.fileExists(atPath: im.path) && im.size.x > 0, "clipboard: picture pasted as an image (\(im.path.hasSuffix(".png") ? "PNG" : im.path))")
                try? FileManager.default.removeItem(atPath: im.path)
            } else { check(false, "clipboard: picture pasted") }
            // TIFF (Preview, screenshots) is converted to PNG.
            pb.clearContents(); pb.setData(NSBitmapImageRep(cgImage: img).tiffRepresentation ?? Data(), forType: .tiff)
            check(ExternalPaste.content(pb)?.type == "png", "clipboard: TIFF converted to PNG")
        } else { check(false, "clipboard: sample picture") }

        // Archi objects on the pasteboard are not "external"; copied objects also carry PDF and PNG pictures.
        let clip = DraftClipboard.capture([sa], from: sd, base: .zero)
        pb.clearContents()
        if let data = try? JSONEncoder().encode(ClipboardPayload(clip)) {
            pb.setData(data, forType: ClipboardPayload.type)
            pb.setString(String(data: data, encoding: .utf8) ?? "", forType: .string)
        }
        check(ExternalPaste.content(pb) == nil, "clipboard: Archi objects are pasted natively")
        ExternalPaste.addPictures(clip, to: pb, source: sd)
        check(pb.data(forType: .pdf).flatMap { PDFDocument(data: $0) }?.pageCount == 1 && (pb.data(forType: .png)?.count ?? 0) > 100, "copy: objects also on the clipboard as PDF and PNG pictures")
        pb.clearContents()
        pb.setString(String(data: (try? JSONEncoder().encode(ClipboardPayload(clip))) ?? Data(), encoding: .utf8) ?? "", forType: .string)
        check(ExternalPaste.content(pb) == nil, "clipboard: Archi objects as JSON text are not pasted as text")
        pb.clearContents()
        check(!ExternalPaste.hasContent(pb), "clipboard: empty pasteboard has nothing to paste")

        // Dropped files: SVG imported and a picture attached side by side at the drop point; unsupported files skipped.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let svg = dir.appendingPathComponent("Plan.svg"), txt = dir.appendingPathComponent("notes.xyzunknown")
        try? #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><line x1="0" y1="0" x2="10" y2="10" stroke="black"/></svg>"#.write(to: svg, atomically: true, encoding: .utf8)
        try? "x".write(to: txt, atomically: true, encoding: .utf8)
        var pic: URL?
        if let img = Artwork.thumbnail(sd, size: 32), let png = Artwork.png(img) { let u = dir.appendingPathComponent("Photo.png"); try? png.write(to: u); pic = u }
        check(FileDrop.accepts([svg]) && !FileDrop.accepts([txt]) && ExternalContent.dropAction(for: dir.appendingPathComponent("a.archi")) == .open, "drop: accepted file types")
        let before = m.doc.entities.count
        let ids = FileDrop.perform([svg] + (pic.map { [$0] } ?? []) + [txt], at: Vec2(5000, 5000), model: m)
        let hasImage = ids.contains { if case .image? = m.doc.entity($0)?.geometry { return true }; return false }
        check(ids.count >= 2 && hasImage && m.doc.entities.count == before + ids.count && m.editor.selection == Set(ids), "drop: SVG imported and picture attached (\(ids.count) objects, selected)")
        m.editor.undo()
        check(m.doc.entities.count == before, "drop: one undo step")
    }

    /// IO-002 / IO-006 / IO-007: Versions, Finder preview icons and Spotlight attributes of saved drawings.
    static func fileExtrasChecks(_ check: (Bool, String) -> Void) {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var (d, _, _) = sampleDoc()
        d.info.author = "Oana"
        let url = dir.appendingPathComponent("Spotlight Test.archi")
        guard (try? ArchiFile.encode(d).write(to: url)) != nil else { check(false, "write test drawing"); return }
        let n = SpotlightXattr.write(SpotlightMetadata.attributes(d), to: url)
        check(n >= 8 && SpotlightXattr.read("kMDItemTitle", from: url) as? String == "Selftest House"
              && (SpotlightXattr.read("kMDItemKeywords", from: url) as? [String])?.contains("0") == true
              && SpotlightXattr.read("kMDItemAuthors", from: url) as? [String] == ["Oana"]
              && SpotlightXattr.read("org.oanarina.archi.entityCount", from: url) as? Int == 2, "Spotlight attributes written as metadata xattrs (\(n))")
        check(SpotlightXattr.read("kMDItemNoSuchKey", from: url) == nil, "missing Spotlight attribute reads nil")
        check(SaveExtras.setFinderIcon(d, url: url, level: nil), "Finder preview icon set from the plan")
        check((try? ArchiFile.decode(Data(contentsOf: url)))?.entities.count == 2, "drawing still reads after metadata and icon (lossless)")

        // Saving through the window's file controller applies the extras.
        let m = AppModel()
        m.editor.replaceDocument(d, url: nil)
        let url2 = dir.appendingPathComponent("Saved.archi")
        let wasVersions = SaveExtras.versions, wasIcons = SaveExtras.finderPreview
        SaveExtras.versions = true; SaveExtras.finderPreview = true
        defer { SaveExtras.versions = wasVersions; SaveExtras.finderPreview = wasIcons }
        check(m.files.write(to: url2) && SpotlightXattr.read("kMDItemTitle", from: url2) as? String == "Selftest House", "save writes Spotlight metadata")
        // Versions: each save keeps one; pruning keeps the newest.
        check(FileVersions.pruneIndices(count: 5, keep: 3) == [3, 4] && FileVersions.pruneIndices(count: 2, keep: 3).isEmpty, "versions pruning keeps the newest")
        m.editor.transaction("Add") { $0.add(.line(LineGeom(Vec2(0, 5000), Vec2(1000, 5000))), layer: "0") }
        _ = m.files.write(to: url2)
        let vs = FileVersions.list(url2)
        check(vs.count >= 2, "saves kept \(vs.count) macOS version(s)")
        if let oldest = vs.last {
            let copy = try? FileVersions.copy(oldest, of: url2)
            let cd = copy.flatMap { try? ArchiFile.decode(Data(contentsOf: $0)) }
            check(cd?.entities.count == 2, "a version opens as a copy with its own content")
            try? FileVersions.restore(oldest, url: url2, model: nil)
            check((try? ArchiFile.decode(Data(contentsOf: url2)))?.entities.count == 2 && FileVersions.list(url2).count >= vs.count, "restoring a version keeps the replaced state as a version")
            if let c = copy { try? FileManager.default.removeItem(at: c) }
        }
        for v in FileVersions.list(url2) { try? v.remove() }
    }

    /// VIS-005: ZOOM nXP.
    static func paperZoomChecks(_ check: (Bool, String) -> Void) {
        check(PaperZoom.factor("1/100XP") == 0.01 && PaperZoom.factor("1:50") == 0.02 && PaperZoom.factor("0.5xp") == 0.5 && PaperZoom.factor(" 2x ") == 2,
              "nXP parsing (1/100XP, 1:50, 0.5xp, 2x)")
        check(PaperZoom.factor("abc") == nil && PaperZoom.factor("1/0") == nil && PaperZoom.factor("-1xp") == nil && PaperZoom.factor("") == nil, "invalid nXP refused")
        check(abs(PaperZoom.viewportScale(factor: 0.01, units: .millimeters) - 100) < 1e-9 && abs(PaperZoom.viewportScale(factor: 0.01, units: .meters) - 0.1) < 1e-9,
              "1/100XP viewport scale: 100 mm or 0.1 m of model per paper mm")
        let ppm = PaperZoom.screenPointsPerMM()
        check(ppm > 1 && ppm < 20 && abs(PaperZoom.canvasScale(factor: 0.01, units: .millimeters, pointsPerScreenMM: 4) - 0.04) < 1e-12, "true-size screen scale (\(fmt(Double(ppm), 2)) pt/mm)")
        // On the plan: 1:100 → 1 m of model is 10 mm on screen.
        let m = AppModel()
        let (d, _, _) = sampleDoc()
        m.editor.replaceDocument(d, url: nil)
        let c = PlanCanvasView(model: m)
        c.setFrameSize(NSSize(width: 800, height: 600))
        c.zoom(toRect: CGRect(x: 0, y: 0, width: 20000, height: 15000), recordHistory: false)
        let target = PaperZoom.canvasScale(factor: 0.01, units: d.units, pointsPerScreenMM: ppm)
        c.zoomBy(target / c.scale)
        let mmOnScreen = Double((c.toView(Vec2(1000, 0)).x - c.toView(.zero).x) / ppm)
        check(abs(mmOnScreen - 10) < 1e-6, "ZOOM 1/100XP on the plan: 1 m = \(fmt(mmOnScreen, 3)) mm on screen")
        PaperZoom.installZoomHook()
        check(ZoomHooks.paperZoom != nil, "core ZOOM passes nXP input to the app (ZoomHooks.paperZoom)")
    }

    /// M3D-103 outliner window items and M3D-052 Ctrl-click sub-object command line.
    static func outlinerAndSubObjectChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        let s1 = d.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(100, 100, 100))), layer: "0")
        let s2 = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(300, 0, 0), size: Vec3(100, 100, 100))), layer: "0")
        let ln = d.add(.line(LineGeom(Vec2(0, 0), Vec2(1, 1))), layer: "0")
        check(Viewport3DController.subObjectLine(id: s1, point: Vec3(50, 0, 50), doc: d) == "SUBOBJECT #\(s1) Face *50,0,50" && Viewport3DController.subObjectLine(id: ln, point: .zero, doc: d) == nil,
              "Ctrl-click on a solid starts SUBOBJECT on the face under the cursor (world point)")
        d.setVariable("SUBOBJECTMODE", "Edge")
        check(Viewport3DController.subObjectLine(id: s1, point: Vec3(0, 0, 0), doc: d)?.contains(" Edge ") == true, "Ctrl-click follows SUBOBJECTMODE")
        guard let g = SketchComponents.make("Table", ids: [s1, s2], base: .zero, group: false, doc: &d) else { check(false, "component made"); return }
        let items = OutlinerItem.items(Outliner.tree(d))
        let top = items.first { $0.node.id == g }
        check(top != nil && (top?.children?.count ?? 0) == 2 && top?.symbol == "cube", "outliner window: component with its 2 solids")
        check(OutlinerItem.filtered(items, "table").count == 1 && OutlinerItem.filtered(items, "zzz").isEmpty && OutlinerItem.filtered(items, "").count == items.count, "outliner filter by name")
        check(Set(items.map(\.id)).count == items.count, "outliner item ids unique")
    }

    /// SYS-028 / SYS-029: spoken summary, status toggles, keyboard crosshair and keyboard selection.
    static func accessibilityChecks(_ check: (Bool, String) -> Void) {
        let m = AppModel()
        var (d, a, _) = sampleDoc()
        d.layers.append(Layer(name: "WALLS"))
        m.editor.replaceDocument(d, url: nil)
        let s0 = A11y.summary(m)
        check(s0.contains("2 drawing objects") && s0.contains("Nothing selected") && s0.contains("Ready for a command"), "spoken summary of the drawing")
        m.editor.selection = [a]
        check(A11y.summary(m).contains("Selected: 1 line"), "spoken summary names the selection")
        m.editor.selection = []
        check(A11y.label("Zoom Extents — fits the drawing (Z E)") == "Zoom Extents" && A11y.label("Undo (Cmd-Z)") == "Undo" && A11y.label("Layers") == "Layers", "icon buttons get short spoken names from their tooltips")
        check(["GRID", "SNAP", "ORTHO", "POLAR", "OTRACK", "OSNAP", "DYN", "LWT"].allSatisfy { A11y.toggleNames[$0] != nil }, "status bar toggles have spoken names")
        let saved = KeyboardCursor.step
        KeyboardCursor.step = 10
        defer { KeyboardCursor.step = saved }
        check(KeyboardCursor.offset(keyCode: 124, shift: false, option: false) == CGVector(dx: 10, dy: 0) && KeyboardCursor.offset(keyCode: 125, shift: true, option: false) == CGVector(dx: 0, dy: -100)
              && KeyboardCursor.offset(keyCode: 126, shift: false, option: true) == CGVector(dx: 0, dy: 1) && KeyboardCursor.offset(keyCode: 0, shift: false, option: false) == nil, "arrow key crosshair steps")
        // A vertical line 10 px right of the view centre: Option-→ moves the crosshair onto it, Tab selects it.
        let c = PlanCanvasView(model: m)
        c.setFrameSize(NSSize(width: 800, height: 600))
        c.zoom(toRect: CGRect(x: -1000, y: -1000, width: 20000, height: 15000), recordHistory: false)
        let w = c.toWorld(CGPoint(x: 410, y: 300))
        let v = m.editor.doc.add(.line(LineGeom(Vec2(w.x, w.y - 500), Vec2(w.x, w.y + 500))), layer: "0")
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
        }
        let right = String(UnicodeScalar(UInt16(NSRightArrowFunctionKey)).map(Character.init) ?? " ")
        if let e1 = key(124, right, [.option, .function]), let e2 = key(48, "\t") {
            let moved = c.handleKeyboardCursor(e1)
            check(moved && c.keyboardCursorActive && c.keyboardCursorWorld.isClose(w, tol: 1e-6), "Option-→ moves the crosshair by the step")
            check(c.handleKeyboardCursor(e2) && m.editor.selection == [v], "Tab selects the object under the keyboard crosshair")
            m.editor.selection = []
            check(key(124, right).map { !c.handleKeyboardCursor($0) } ?? false, "plain arrows while idle are left to nudge/history")
        } else { check(false, "key events") }
    }

    /// VIS-050: the viewport sun points along the solar direction and its shadow falls where geometry says
    /// (a 3 m column, sun at 45°: the shadow reaches 3 m away from the sun; the mirrored spot stays lit).
    static func viewportShadowChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        _ = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(-6000, -6000, -200), size: Vec3(12000, 12000, 200))), layer: "0")
        _ = d.add(.solid(SolidGeom(kind: .box, origin: Vec3(-250, -250, 0), size: Vec3(500, 500, 3000))), layer: "0")
        let b = Scene3DBuilder()
        b.update(doc: d, style: "Shaded")
        let dir = SunPosition.direction(altitude: .pi / 4, azimuth: .pi * 0.4, northAngleDegrees: 0).normalized
        b.setSun(direction: dir)
        let front = b.sunNode.worldFront
        let expect = Scene3DBuilder.world(dir * -1000)
        let dot = Double(front.x * expect.x + front.y * expect.y + front.z * expect.z) / max(1e-12, Double(Viewport3DController.length(expect)) * Double(Viewport3DController.length(front)))
        let errDeg = acos(min(1, max(-1, dot))) * 180 / .pi
        check(errDeg < 0.1 && abs(dir.z - sin(Double.pi / 4)) < 1e-9, "viewport sun direction matches the solar position (error \(fmt(errDeg, 4))°)")
        guard let light = b.sunNode.light, let device = MTLCreateSystemDefaultDevice() else { check(false, "sun light and Metal device"); return }
        light.castsShadow = true
        light.intensity = 1200
        b.ambientNode.light?.intensity = 150
        check(light.type == .directional && light.shadowMode == .deferred, "viewport shadows: directional sun, deferred shadow maps")
        let cam = SCNNode(), c = SCNCamera()
        c.usesOrthographicProjection = true; c.orthographicScale = 5; c.zNear = 1; c.zFar = 60
        c.screenSpaceAmbientOcclusionIntensity = 0; c.wantsHDR = false
        cam.camera = c
        cam.position = SCNVector3(0, 25, 0)
        cam.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
        b.scene.rootNode.addChildNode(cam)
        let r = SCNRenderer(device: device, options: nil)
        r.scene = b.scene; r.pointOfView = cam; r.autoenablesDefaultLighting = false
        let N = 256
        let img = r.snapshot(atTime: 0, with: CGSize(width: N, height: N), antialiasingMode: .none)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { check(false, "shadow render"); return }
        // Model point (mm) → pixel (top-left origin) of the top-down orthographic view (5 m half height).
        func px(_ p: Vec2) -> (Int, Int) {
            let s = Double(rep.pixelsHigh) / 2 / 5000
            return (Int(Double(rep.pixelsWide) / 2 + p.x * s), Int(Double(rep.pixelsHigh) / 2 - p.y * s))
        }
        func lum(_ p: Vec2) -> Double {
            let (x, y) = px(p)
            guard let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return -1 }
            return Double(0.2126 * col.redComponent + 0.7152 * col.greenComponent + 0.0722 * col.blueComponent)
        }
        // Shadow of the column's mid-height axis point; the same distance towards the sun is lit.
        let h = Vec2(dir.x, dir.y) * (1500 / dir.z)
        let inShadow = lum(Vec2(0, 0) - h), lit = lum(Vec2(0, 0) + h * 1.2)
        let beyond = lum(Vec2(0, 0) - Vec2(dir.x, dir.y).normalized * (3000 / tan(Double.pi / 4) + 900))
        check(inShadow >= 0 && lit > 0 && lit - inShadow > 0.1, "viewport shadow falls away from the sun (shadow \(fmt(inShadow, 3)) < lit \(fmt(lit, 3)))")
        check(beyond > inShadow + 0.05, "shadow length matches height / tan(altitude) (beyond the tip \(fmt(beyond, 3)))")
    }

    /// COL-013: a drawing changed on disk by sync or another user reloads (no local edits) or merges (local edits).
    static func syncChecks(_ check: (Bool, String) -> Void) {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Shared.archi")
        var d = ArchiDocument()
        let a = d.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))), layer: "0")
        guard (try? ArchiFile.encode(d).write(to: url)) != nil else { check(false, "write shared drawing"); return }
        let m = AppModel()
        guard m.files.load(url) else { check(false, "open shared drawing"); return }
        defer { SyncWatcher.untrack(m) }
        check(SyncWatcher.isTracking(m), "sync: opened drawing is watched")
        check(SyncWatcher.poll().allSatisfy { $0 == .none }, "sync: unchanged file does nothing")
        // Another user adds a circle; this window has no edits → reload.
        var theirs = d
        let c = theirs.add(.circle(CircleGeom(Vec2(5000, 0), 300)), layer: "0")
        try? ArchiFile.encode(theirs).write(to: url)
        check(SyncWatcher.poll().contains(.reloaded) && m.doc.entity(c) != nil && !m.isDirty, "sync: clean window reloads the newer file")
        // Now both edit: we move the line, they add a text → merged, nothing lost.
        m.editor.transaction("Edit") { doc in if let i = doc.entityIndex(a) { doc.entities[i].geometry = .line(LineGeom(Vec2(0, 100), Vec2(1000, 100))) } }
        var theirs2 = theirs
        let t = theirs2.add(.text(TextGeom(position: Vec2(0, 2000), height: 250, content: "Their note")), layer: "0")
        try? ArchiFile.encode(theirs2).write(to: url)
        let out = SyncWatcher.poll()
        let merged = out.contains { if case .merged(let n, 0) = $0 { return n >= 1 }; return false }
        var ours = false
        if case .line(let lg)? = m.doc.entity(a)?.geometry { ours = lg.a.y == 100 }
        check(merged && ours && m.doc.entity(t) != nil && m.doc.entity(c) != nil && m.isDirty, "sync: unsaved edits merged with the disk version (ours kept, theirs added)")
        m.editor.undo()
        check(m.doc.entity(t) == nil, "sync: the merge is one undo step")
        // Our own save is not treated as an outside change.
        _ = m.files.write(to: url)
        check(SyncWatcher.poll().allSatisfy { $0 == .none }, "sync: own saves are not outside changes")
    }

    /// PRC-036: the plan shows the dynamic-UCS face axes at the crosshair.
    static func ducsChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        _ = d.add(.solid(SolidGeom(kind: .box, origin: .zero, size: Vec3(1000, 1000, 500))), layer: "0")
        d.setVariable(DynamicUCS.variable, "1")
        let ed = Editor(document: d)
        guard let f = DUCSOverlay.face(editor: ed, cursor: Vec2(500, 500)) else { check(false, "DUCS face found under the crosshair"); return }
        check(abs(f.normal.z - 1) < 1e-9 && abs(f.origin.z - 500) < 1e-6, "DUCS face found under the crosshair on the box top")
        let segs = DUCSOverlay.segments(f, at: Vec2(100, 200), length: 50)
        check(segs.count == 2 && segs.allSatisfy { $0.0.isClose(Vec2(100, 200), tol: 1e-6) && abs($0.0.distance(to: $0.1) - 50) < 1e-6 }
              && abs(segs[0].1.x - segs[0].0.x) > 49, "DUCS on a horizontal face: X and Y axes drawn at the crosshair (normal vertical, hidden)")
        ed.doc.setVariable(DynamicUCS.variable, "0")
        check(DUCSOverlay.face(editor: ed, cursor: Vec2(500, 500)) == nil, "no DUCS face when DUCS is off")
    }

    /// PAR-016: the Customizer edits the parameters of GDL-like scripted BIM objects (validated, regenerated, undoable).
    static func scriptedComponentChecks(_ check: (Bool, String) -> Void) {
        let m = AppModel()
        var d = ArchiDocument()
        let code = "// Table width\nw = 1200; // [600:100:3000]\ncube([w, 800, 740]);"
        guard let id = ScriptedComponents.place(script: code, at: Vec2(0, 0), doc: &d) else { check(false, "scripted component placed"); return }
        m.editor.replaceDocument(d, url: nil)
        let t = Customizer.target(m.doc, selection: [id])
        check(t?.id == id && t?.solid == nil && SCADCustomizer.parameters(t?.script ?? "").first?.name == "w", "customizer targets a scripted BIM object")
        func width() -> Double? { if case .component(let g)? = m.doc.element(id)?.geometry { return g.size.x }; return nil }
        let w0 = width()
        let err = Customizer.set("w", "2000", id: id, editor: m.editor)
        check(err == nil && w0.map { abs($0 - 1200) < 1 } == true && width().map { abs($0 - 2000) < 1 } == true, "customizer regenerates the scripted object (width \(fmt(w0 ?? 0)) → \(fmt(width() ?? 0)))")
        check(Customizer.set("w", "5000", id: id, editor: m.editor) != nil && width().map { abs($0 - 2000) < 1 } == true, "out-of-range value refused, object unchanged")
        m.editor.undo()
        check(width().map { abs($0 - 1200) < 1 } == true, "parameter edit undoes in one step")
    }

    /// M3D-088: mechanism playback frame sequencing and overlay.
    static func mechanismPlaybackChecks(_ check: (Bool, String) -> Void) {
        let once = (0..<5).map { MechanismPlayback.frame(tick: $0, count: 3, mode: .once) }
        check(once == [0, 1, 2, nil, nil], "mechanism playback Once")
        check((0..<7).map { MechanismPlayback.frame(tick: $0, count: 3, mode: .bounce)! } == [0, 1, 2, 1, 0, 1, 2], "mechanism playback Bounce")
        check(MechanismPlayback.frame(tick: 4, count: 3, mode: .loop) == 1 && MechanismPlayback.frame(tick: 3 * MechanismPlayback.maxLoops, count: 3, mode: .loop) == nil
              && MechanismPlayback.frame(tick: 0, count: 0, mode: .loop) == nil, "mechanism playback Loop ends after \(MechanismPlayback.maxLoops) loops")
        let poses = [0.0, 45, 90].map { deg -> [Entity] in
            let e = Vec2(cos(deg * .pi / 180), sin(deg * .pi / 180)) * 1000
            return [Entity(id: 1, layer: "0", geometry: .line(LineGeom(.zero, e)))]
        }
        let p = MechanismPlayback(poses: poses, mode: .once, model: nil)
        let first = p.items(doc: ArchiDocument())
        p.advance(); p.advance()
        var endX: Double?
        for it in p.items(doc: ArchiDocument()) { if case .stroke(let pts, _, _) = it { endX = pts.map(\.x).max() } }
        check(!first.isEmpty && endX.map { abs($0) < 1e-6 } == true, "playback overlay shows the current pose (90° arm vertical)")
        p.advance()
        check(p.items(doc: ArchiDocument()).isEmpty && p.current == nil, "playback ends after the last pose")
    }

    /// SYS-026: ribbon tabs, panels and main tools in six languages.
    static func localizationChecks(_ check: (Bool, String) -> Void) {
        check(L10n.t("Wall", "ro") == "Perete" && L10n.t("Wall", "de") == "Wand" && L10n.t("Wall", "fr") == "Mur" && L10n.t("Wall", "en") == "Wall", "ribbon tool names translated")
        check(L10n.t("No such ribbon text", "ro") == "No such ribbon text" && L10n.t("Wall", "xx") == "Wall", "untranslated text and unknown languages fall back to English")
        check(L10n.resolved("auto", preferred: ["de-CH", "en-US"]) == "de" && L10n.resolved("auto", preferred: ["ja-JP"]) == "en" && L10n.resolved("it") == "it", "Auto follows the macOS language list")
        check(L10n.table.values.allSatisfy { $0.count == 5 && $0.allSatisfy { !$0.isEmpty } }, "every translation row has Romanian, German, French, Spanish and Italian")
        let tabs = RibbonTab.allCases.map(\.rawValue)
        let main = (CommandCatalog.draw + CommandCatalog.modify + CommandCatalog.text + CommandCatalog.dimensions + CommandCatalog.build + CommandCatalog.spaces).map(\.title)
        check(["ro", "de", "fr", "es", "it"].allSatisfy { lang in (tabs + main).allSatisfy { L10n.table[$0] != nil } && L10n.coverage(lang, of: tabs) == 1 }, "all ribbon tabs and main tools have translations")
    }
}
