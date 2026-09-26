// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import JavaScriptCore
import ArchiCore

/// Checks of round 12: object styles dialog (LAY-033), text style width factor/obliquing in the renderers (ANN-004),
/// exact image adjustment on screen and in plots (DRW-086), ambient occlusion in the viewport and renders (VIS-033),
/// material fill patterns dialog (ANN-072) and the menu coverage of the new commands.
@MainActor
extension AppSelfTests {
    static func round12Checks(_ check: (Bool, String) -> Void) {
        let names = Set(CommandCatalog.coverageMenus.flatMap(\.1).flatMap(\.names))
        check(AppCommandsRound12.all.allSatisfy { names.contains($0.name) }, "round 12 commands have menu entries")
        check(["OBJECTSTYLES", "AMBIENTOCCLUSION", "FLOORPATTERN"].allSatisfy { names.contains($0) }, "round 12 core commands have menu entries")
        objectStyleFormChecks(check)
        // Menu-bar localisation (SYS-026).
        check(L10n.menuTable.values.allSatisfy { $0.count == 5 && !$0.contains("") }, "menu translations have all five languages")
        let menus = ["Draw", "Modify", "Annotate", "Architecture", "Model", "Analyze", "Tools"]
        check(["ro", "de", "fr", "es", "it"].allSatisfy { l in menus.allSatisfy { L10n.t($0, l) != $0 || $0 == "Architecture" && l == "fr" || $0 == "Model" && l == "ro" } },
              "menu bar titles are translated in every language")
        check(L10n.t("Tools", "de") == "Werkzeuge" && L10n.t("Object Styles…", "it") == "Stili oggetto…" && L10n.t("Tools", "en") == "Tools", "menu item translations")
        textStyleShapeChecks(check)
        imageAdjustChecks(check)
        occlusionChecks(check)
        materialPatternFormChecks(check)
        inPlaceTextEditorChecks(check)
        webXRChecks(check)
        automationIntegrationChecks(check)
        localModelChecks(check)
        spatialPickChecks(check)
        crashReportChecks(check)
    }

    private static func objectStyleFormChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        let w = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0))))
        func weights(_ doc: ArchiDocument) -> Set<Double> {
            Set(DrawListBuilder.entries(doc: doc, options: DrawOptions(level: doc.currentLevel)).filter { $0.id == w }.flatMap(\.items).compactMap {
                if case .stroke(_, _, let st) = $0 { return (st.lineweight * 1000).rounded() / 1000 }; return nil })
        }
        check(!weights(d).contains(1.4), "object styles: wall not drawn at 1.4 by default")
        var f = ObjectStylesForm(doc: d)
        check(f.rows.map(\.category).starts(with: ObjectStyles.categories), "object styles form lists every category")
        guard let i = f.rows.firstIndex(where: { $0.category == "wall" }) else { check(false, "object styles form has walls"); return }
        f.rows[i].cut = "abc"
        check(!f.errors.isEmpty, "object styles form rejects a non-numeric weight")
        f.rows[i].cut = "1.4"; f.rows[i].fill = RGBA(0.2, 0.3, 0.4); f.rows[i].pattern = "ANSI31"
        check(f.errors.isEmpty && f.styles.count == 1, "object styles form: one styled category")
        f.apply(to: &d)
        let s = ObjectStyles.style("wall", doc: d)
        check(s?.cutLineweight == 1.4 && s?.cutPattern == "ANSI31" && s?.cutFill == RGBA(0.2, 0.3, 0.4), "object styles dialog stores the wall style")
        check(weights(d).contains(1.4), "changing the wall cut lineweight updates the plan")
        let back = ObjectStylesForm(doc: d)
        check(back.rows.first { $0.category == "wall" }?.cut == "1.4", "object styles form reads the stored style back")
        var cleared = back
        for k in cleared.rows.indices { cleared.rows[k] = ObjectStylesForm.Row(category: cleared.rows[k].category) }
        cleared.apply(to: &d)
        check(d.variable(ObjectStyles.key) == nil, "clearing every row removes the object styles")
    }

    private static func textStyleShapeChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        var f = TextStyleForm(TextStyle(name: "Narrow"))
        f.widthFactor = "0.5"; f.obliqueDegrees = "15"
        check(f.apply(original: nil, to: &d), "text style form adds a style")
        check(!TextStyleForm(TextStyle(name: "Narrow")).apply(original: nil, to: &d), "text style form refuses a duplicate name")
        var bad = f; bad.obliqueDegrees = "90"
        check(!bad.errors.isEmpty, "text style form rejects an oblique angle of 90°")
        guard let st = d.textStyles.first(where: { $0.name == "Narrow" }) else { check(false, "narrow style stored"); return }
        check(abs(TextStyleFonts.widthFactor(st) - 0.5) < 1e-9 && abs(TextStyleFonts.obliqueRadians(st) - 15 * .pi / 180) < 1e-9, "text style stores width factor and oblique (radians)")
        let plain = TextGeom(position: .zero, height: 250, content: "WIDTH TEST", style: "Standard")
        var narrow = plain; narrow.style = "Narrow"
        let id = d.add(.text(narrow))
        AppRenderInfo.register(d)
        let a = RenderScene.layoutText(plain, font: "Helvetica", color: RGBA(1, 1, 1))
        let b = RenderScene.layoutText(narrow, font: "Helvetica", color: RGBA(1, 1, 1))
        check(a.glyph.isIdentity && abs(b.glyph.a - 0.5) < 1e-9 && abs(b.glyph.c - tan(15 * .pi / 180)) < 1e-9, "canvas text carries the style's glyph transform")
        // Box of slanted, half-width text: about half as wide plus the slant over the height.
        check(b.box.width < a.box.width * 0.75 && b.box.width > a.box.width * 0.4, "canvas text box honours the width factor")
        // Rendered ink: narrow text covers fewer pixels than plain text.
        func ink(_ t: RenderScene.TextRun) -> Int {
            guard let ctx = CGContext(data: nil, width: 1200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            ctx.translateBy(x: 20, y: 60); ctx.scaleBy(x: 0.5, y: 0.5)
            RenderScene.drawText(t, ctx: ctx, scale: 0.5, color: CGColor(gray: 1, alpha: 1))
            guard let data = ctx.data else { return 0 }
            let p = data.assumingMemoryBound(to: UInt8.self)
            var n = 0, maxX = 0
            for y in 0..<200 { for x in 0..<1200 where p[(y * ctx.bytesPerRow) + x * 4 + 3] > 128 { n += 1; maxX = max(maxX, x) } }
            return maxX
        }
        let wa = ink(a), wb = ink(b)
        check(wa > 0 && wb > 0 && Double(wb) < Double(wa) * 0.8, "narrow text style draws narrower on the canvas (\(wb) vs \(wa) px)")
        // Renaming the style updates its text.
        var r = TextStyleForm(st); r.name = "Condensed"
        check(r.apply(original: "Narrow", to: &d), "text style rename")
        if case .text(let t)? = d.entity(id)?.geometry { check(t.style == "Condensed", "renaming a text style updates its text") }
        // PDF plot with the styled text renders (no crash, non-empty output).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r12-text-\(UUID().uuidString).pdf")
        do { try Plotter.writePDF(doc: d, to: url, layoutIndex: nil, level: nil); check(((try? Data(contentsOf: url))?.count ?? 0) > 500, "PDF plot of styled text") }
        catch { check(false, "PDF plot of styled text: \(error)") }
        try? FileManager.default.removeItem(at: url)
    }

    private static func grayPNG(_ v: UInt8, size: Int = 32) -> URL? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let p = rep.bitmapData else { return nil }
        for i in 0..<(size * size) { p[i * 4] = v; p[i * 4 + 1] = v; p[i * 4 + 2] = v; p[i * 4 + 3] = 255 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r12-gray-\(v)-\(UUID().uuidString).png")
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func imageAdjustChecks(_ check: (Bool, String) -> Void) {
        guard let url = grayPNG(96) else { check(false, "image adjust: test image"); return }
        defer { try? FileManager.default.removeItem(at: url) }
        var d = ArchiDocument()
        let id = d.add(.image(ImageGeom(path: url.path, origin: .zero, size: Vec2(1000, 1000))))
        let adj = ImageDisplay.Adjustment(brightness: 60, contrast: 90, fade: 0)
        check(ImageAdjustPanel.apply(adj, ids: [id], to: &d) == 1, "image adjust dialog applies to the selected image")
        check(d.entity(id).map(ImageDisplay.adjustment) == adj, "image adjustment stored on the entity")
        // Survives save/reopen.
        if let data = try? JSONEncoder().encode(d), let back = try? JSONDecoder().decode(ArchiDocument.self, from: data) {
            check(back.entity(id).map(ImageDisplay.adjustment) == adj, "image adjustment persists after reopening")
        } else { check(false, "image adjustment document round trip") }
        func veilCount(_ doc: ArchiDocument) -> Int {
            DrawListBuilder.entries(doc: doc, options: DrawOptions(level: doc.currentLevel)).filter { $0.id == id }.flatMap(\.items).filter { if case .fill = $0 { return true }; return false }.count
        }
        AppRenderInfo.register(d)
        check(veilCount(d) > 0 && AppRenderInfo.withPixels { veilCount(d) } == 0, "with pixel processing the renderer, not veils, applies the adjustment")
        let expected = ImageDisplay.adjusted(RGBA(96.0 / 255, 96.0 / 255, 96.0 / 255), adj, background: RGBA(1, 1, 1))
        if let src = RenderScene.cgImage(url.path), let out = AppRenderInfo.adjustedImage(src, path: url.path, background: RGBA(1, 1, 1)), let m = AppRenderInfo.meanColor(out) {
            check(abs(m.r - expected.r) < 0.03, "pixel adjustment matches the reference model (\(fmt(m.r, 3)) vs \(fmt(expected.r, 3)))")
        } else { check(false, "pixel-adjusted image") }
        // End to end: a paper plot PNG shows the adjusted grey in the image's centre.
        if let png = Plotter.planPNG(doc: d, level: nil, width: 200, height: 200, paper: true), let rep = NSBitmapImageRep(data: png),
           let p = rep.bitmapData {
            // Raw 8-bit sample (the PNG is written from an sRGB context; colour conversion of the rep would re-gamma it).
            let v = Double(p[100 * rep.bytesPerRow + 100 * (rep.bitsPerPixel / 8)]) / 255
            check(abs(v - expected.r) < 0.03, "plotted image shows the exact contrast (\(fmt(v, 3)) vs \(fmt(expected.r, 3)))")
        } else { check(false, "plan PNG with an adjusted image") }
        check(!ImageDisplay.rendererAppliesPixels, "pixel mode is scoped to the app renderers")
    }

    private static func occlusionChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        var f = AOForm(doc: d)
        check(f.intensity == 0 && AOForm.viewport(d) == nil, "ambient occlusion off by default")
        f.intensity = 1.5; f.radius = 500; f.samples = 16
        f.apply(to: &d)
        let s = AmbientOcclusion.settings(d)
        check(s?.intensity == 1.5 && s?.radius == 500 && s?.samples == 16, "ambient occlusion dialog stores intensity, radius and samples")
        if let v = AOForm.viewport(d) { check(abs(v.intensity - 1.35) < 1e-6 && abs(v.radius - 0.5) < 1e-6, "viewport occlusion follows the document") }
        else { check(false, "viewport occlusion settings") }
        let (_, cam) = RenderEngine.makeScene(doc: d, settings: RenderSettings())
        check(abs((cam.camera?.screenSpaceAmbientOcclusionRadius ?? 0) - 0.5) < 1e-6 && (cam.camera?.screenSpaceAmbientOcclusionIntensity ?? 0) >= 1.35 - 1e-6, "renders use the document's ambient occlusion")
        f.intensity = 0; f.apply(to: &d)
        check(AmbientOcclusion.settings(d) == nil, "ambient occlusion dialog turns it off")
    }

    private static func materialPatternFormChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        guard let name = d.materials.first?.name else { check(false, "material library"); return }
        var f = MaterialPatternForm(doc: d)
        check(f.rows.count == d.materials.count, "material patterns form lists every material")
        f.rows[0].cut = "ANSI31"; f.rows[0].surface = "AR-CONC"
        check(f.apply(to: &d) >= 1, "material patterns dialog applies changes")
        check(MaterialPatterns.pattern(name, kind: .cut, doc: d) == "ANSI31" && MaterialPatterns.pattern(name, kind: .surface, doc: d) == "AR-CONC", "material cut and surface patterns stored")
        check(MaterialPatternForm(doc: d).apply(to: &d) == 0, "unchanged material patterns are left alone")
    }

    private static func inPlaceTextEditorChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        let id = d.add(.text(TextGeom(position: Vec2(1000, 1000), height: 250, content: "Hello")))
        guard var st = d.entity(id).flatMap(TextEditState.init) else { check(false, "text edit state"); return }
        check(st.format.isPlain && st.content == "Hello", "text edit state reads plain text")
        st.content = "Hello World"; st.height = 400; st.format.bold = true; st.format.italic = true; st.format.underline = true
        st.format.font = "Georgia"; st.color = .rgb(255, 0, 0)
        var bad = st; bad.height = 0
        check(!bad.errors.isEmpty && !bad.apply(id: id, to: &d), "in-place editor refuses a zero height")
        check(st.apply(id: id, to: &d), "in-place edit applies")
        guard let e = d.entity(id), case .text(let t) = e.geometry else { check(false, "edited text"); return }
        check(t.content == "Hello World" && t.height == 400 && e.color == .rgb(255, 0, 0), "in-place edit: content, height and colour")
        check(e.props["bold"] == "1" && e.props["italic"] == "1" && e.props["underline"] == "1" && e.props["font"] == "Georgia", "in-place edit: bold, italic, underline and font props")
        // Screen: bold italic Georgia with an underline.
        AppRenderInfo.register(d)
        check(AppRenderInfo.textFormats[id]?.bold == true, "text formats registered for the renderers")
        let run = RenderScene.layoutText(t, font: "Helvetica", color: RGBA(1, 1, 1), format: AppRenderInfo.textFormats[id])
        let psName: String = {
            guard let line = run.lines.first?.line, let r = (CTLineGetGlyphRuns(line) as? [CTRun])?.first else { return "" }
            let attrs = CTRunGetAttributes(r) as NSDictionary
            guard let f = attrs[kCTFontAttributeName] else { return "" }
            return CTFontCopyPostScriptName(f as! CTFont) as String
        }()
        check(psName.contains("Georgia") && psName.contains("Bold") && psName.contains("Italic"), "canvas draws the chosen font, bold and italic (\(psName))")
        check(run.underline, "canvas draws the underline")
        let plainRun = RenderScene.layoutText(t, font: "Helvetica", color: RGBA(1, 1, 1))
        check(!plainRun.underline, "unformatted text is not underlined")
        // Layered PDF: bold oblique face and the underline path.
        let page = LayeredPDF.modelPage(doc: d, level: nil).page
        let out = LayeredPDF.build(doc: d, pages: [page], title: "t", compress: false)
        let pdf = out.contents.joined()
        check(pdf.contains("/F4 ") && pdf.contains(" h f"), "layered PDF uses the bold oblique face and draws the underline")
        // Vector PDF plot renders it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r12-fmt-\(UUID().uuidString).pdf")
        check(((try? Plotter.writePDF(doc: d, to: url, layoutIndex: nil, level: nil)) != nil) && ((try? Data(contentsOf: url))?.count ?? 0) > 500, "PDF plot of formatted text")
        try? FileManager.default.removeItem(at: url)
        // DXF round trip: MTEXT with the same whole-text formatting.
        check(e.props["mtext"].map(DXFReader.mtextContent) == "Hello World", "MTEXT string carries the edited content")
        if let back = try? DXFReader.read(DXFWriter.write(d)),
           let be = back.entities.first(where: { if case .text(let bt) = $0.geometry { return bt.content == "Hello World" }; return false }),
           case .text(let bt) = be.geometry {
            check(be.props["bold"] == "1" && be.props["italic"] == "1" && be.props["underline"] == "1" && be.props["font"] == "Georgia" && abs(bt.height - 400) < 1e-6,
                  "DXF round trip keeps bold, italic, underline, font and height")
        } else { check(false, "DXF round trip of formatted text") }
        // Clearing the formatting removes the props and the stale MTEXT string.
        var plain = st; plain.format = AppRenderInfo.TextFormat()
        plain.apply(id: id, to: &d)
        check(d.entity(id).map { $0.props["bold"] == nil && $0.props["mtext"] == nil && $0.props["font"] == nil } == true, "clearing the formatting removes the props")

        // The editor itself on a canvas: opens over the text, toggles bold, commits one undoable edit.
        let model = AppModel()
        var cd = ArchiDocument()
        let tid = cd.add(.text(TextGeom(position: Vec2(0, 0), height: 250, content: "Door")))
        model.editor.replaceDocument(cd, url: nil)
        let canvas = PlanCanvasView(model: model)
        canvas.setFrameSize(NSSize(width: 900, height: 600))
        canvas.zoom(toRect: CGRect(x: -2000, y: -2000, width: 6000, height: 4000), recordHistory: false)
        check(InPlaceTextEditor.begin(canvas: canvas, model: model, id: tid), "in-place editor opens on text")
        guard let editor = InPlaceTextEditor.current else { check(false, "in-place editor is current"); return }
        check(editor.superview === canvas && canvas.bounds.intersects(editor.frame), "in-place editor sits on the canvas")
        let p = canvas.toView(Vec2(0, 0))
        check(editor.frame.minX <= p.x + 1 && editor.frame.maxX > p.x && editor.frame.minY <= p.y && editor.frame.maxY > p.y, "in-place editor covers the text's insertion point")
        let cap = (NSFont(name: "Helvetica", size: 100)?.capHeight ?? 72) / 100
        check(abs(editor.pointSize - min(96, max(9, 250 * canvas.scale / cap))) < 0.01, "editor shows the text at its drawn size")
        editor.click("bold"); editor.click("underline")
        check(editor.displayFont.fontDescriptor.symbolicTraits.contains(.bold), "bold button makes the editor text bold (WYSIWYG)")
        editor.setText("Front Door")
        let before = model.editor.changeCount
        editor.commit()
        check(InPlaceTextEditor.current == nil && editor.superview == nil, "committing closes the editor")
        if case .text(let et)? = model.doc.entity(tid)?.geometry {
            check(et.content == "Front Door" && model.doc.entity(tid)?.props["bold"] == "1" && model.doc.entity(tid)?.props["underline"] == "1" && model.editor.changeCount != before, "editor commit writes content and formatting")
        } else { check(false, "edited text on the canvas") }
        model.editor.undo()
        if case .text(let ut)? = model.doc.entity(tid)?.geometry { check(ut.content == "Door" && model.doc.entity(tid)?.props["bold"] == nil, "in-place edit is one undo step") }
        // Escape discards.
        check(InPlaceTextEditor.begin(canvas: canvas, model: model, id: tid), "editor reopens")
        InPlaceTextEditor.current?.setText("Discarded")
        InPlaceTextEditor.current?.cancel()
        if case .text(let ct)? = model.doc.entity(tid)?.geometry { check(ct.content == "Door", "cancel leaves the text unchanged") }
    }

    private static func webXRChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        let html = WebViewerExport.html(doc: d)
        check(html.contains("immersive-vr") && html.contains("XRWebGLLayer") && html.contains("local-floor") && html.contains("id=\"vr\""), "web viewer offers a WebXR headset session (VIS-086)")
        // The viewer script compiles (syntax check without running it).
        let scripts = html.components(separatedBy: "<script>").dropFirst().compactMap { $0.components(separatedBy: "</script>").first }
        let ctx = JSContext()
        var ok = !scripts.isEmpty
        for src in scripts {
            ctx?.setObject(src, forKeyedSubscript: "src" as NSString)
            ctx?.exceptionHandler = { _, _ in ok = false }
            _ = ctx?.evaluateScript("new Function(src)")
        }
        check(ok, "web viewer and WebXR script compile")
        // Floor placement: the lowest vertex sits at y = 0 in the VR space.
        let s = WebViewerExport.scene(doc: d)
        let minY = s.batches.flatMap { b in stride(from: 1, to: b.p.count, by: 3).map { b.p[$0] } }.min() ?? 1
        check(abs(minY) < 1e-6 || minY >= 0, "model floor at ground level for VR")
    }

    /// AppleScript "do script" (SCR-025) end to end: a real Apple event sent to this process through the Apple Event
    /// Manager reaches the handler and runs the command lines on the front drawing; the URL-scheme path used by
    /// Shortcuts' "Open URLs" (SCR-024) runs a command too.
    private static func automationIntegrationChecks(_ check: (Bool, String) -> Void) {
        guard headless else { return }   // spins the run loop: only in --selftest
        let model = AppModel()
        model.editor.replaceDocument(ArchiDocument(), url: nil)
        guard let front = AutomationURL.front() else { check(false, "automation: a front drawing"); return }
        AppleScriptBridge.shared.install()
        let before = front.doc.entities.count
        let target = NSAppleEventDescriptor.currentProcess()  // dispatched directly to the installed handler
        let ev = NSAppleEventDescriptor(eventClass: AppleScriptBridge.doScriptClass, eventID: AppleScriptBridge.doScriptID, targetDescriptor: target,
                                        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        ev.setParam(NSAppleEventDescriptor(string: "CIRCLE 0,0 300\n; a comment\nLINE 0,0 1000,0 \n"), forKeyword: keyDirectObject)
        var sent = true, err = ""
        do { _ = try ev.sendEvent(options: [.noReply], timeout: 5) } catch { sent = false; err = "\(error)" }
        spin(5) { front.doc.entities.count >= before + 2 }
        check(sent && front.doc.entities.count == before + 2, "AppleScript do script event runs command lines (SCR-025) [sent \(sent) \(err), +\(front.doc.entities.count - before)]")
        // URL scheme (Shortcuts "Open URLs", AppleScript "open location").
        if let url = URL(string: "oanarina-archi://run?command=CIRCLE%205000,0%20200"), let a = AutomationURL.parse(url) {
            let n = front.doc.entities.count
            AutomationURL.perform(a)
            spin(5) { front.doc.entities.count > n }
            check(front.doc.entities.count == n + 1, "automation URL runs a command on the front drawing (SCR-024)")
        } else { check(false, "automation URL parses") }
        // Shortcuts actions: run a script file and export a PDF through URLs.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("r12-auto-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scr = dir.appendingPathComponent("setup.scr")
        try? "CIRCLE 9000,0 150\nLINE 0,2000 3000,2000 \n".write(to: scr, atomically: true, encoding: .utf8)
        var comps = URLComponents(); comps.scheme = AutomationURL.scheme; comps.host = "script"; comps.queryItems = [URLQueryItem(name: "path", value: scr.path)]
        if let u = comps.url, let a = AutomationURL.parse(u) {
            let n = front.doc.entities.count
            AutomationURL.perform(a)
            spin(5) { front.doc.entities.count >= n + 2 }
            check(front.doc.entities.count == n + 2, "automation URL runs a script file (Shortcuts \"run script\")")
        } else { check(false, "script URL parses") }
        let pdf = dir.appendingPathComponent("Plan.pdf")
        comps.host = "export"; comps.queryItems = [URLQueryItem(name: "format", value: "pdf"), URLQueryItem(name: "path", value: pdf.path)]
        if let u = comps.url, let a = AutomationURL.parse(u) {
            AutomationURL.perform(a)
            spin(8) { FileManager.default.fileExists(atPath: pdf.path) }
            check(((try? Data(contentsOf: pdf))?.prefix(4)).map { String(decoding: $0, as: UTF8.self) } == "%PDF", "automation URL exports a PDF (Shortcuts \"export PDF\")")
        } else { check(false, "export URL parses") }
        _ = model
    }

    /// Local model (SCR-035) end to end against an OpenAI-compatible server on 127.0.0.1 (a stand-in for Ollama):
    /// small edits run as undoable commands, bulk edits wait for confirmation, the request stays on this Mac.
    private static func localModelChecks(_ check: (Bool, String) -> Void) {
        guard headless else { return }   // spins the run loop: only in --selftest
        guard let server = MockHTTPServer() else { check(false, "local model: mock server"); return }
        defer { server.listener.cancel() }
        spin(3) { server.port != nil && server.port != 0 }
        guard let port = server.port else { check(false, "local model: mock server port"); return }
        func reply(_ cmds: [String]) -> String {
            let args = String(decoding: try! JSONSerialization.data(withJSONObject: ["commands": cmds]), as: UTF8.self)
            let obj: [String: Any] = ["choices": [["message": ["content": "Done.", "tool_calls": [["type": "function", "function": ["name": AssistantProtocol.toolName, "arguments": args]]]]]]]
            return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
        }
        let model = AppModel()
        model.editor.replaceDocument(ArchiDocument(), url: nil)
        let session = AssistantSession(model: model)
        session.config = AssistantConfig(provider: .local, model: "mock", endpoint: "http://127.0.0.1:\(port)/v1/chat/completions")
        // 1. A small edit runs directly and is undoable.
        server.replies = [reply(["LINE 0,0 1000,0 ", "CIRCLE 0,0 300"])]
        session.send("draw a line and a circle")
        spin(10) { !session.busy }
        check(server.requests.count == 1 && (server.requests.first?["model"] as? String) == "mock" && ((server.requests.first?["tools"] as? [Any])?.isEmpty == false),
              "local model: OpenAI-compatible request with the command tool sent to localhost")
        check(model.doc.entities.count == 2 && session.pending == nil, "local model: small edits run on the drawing (+\(model.doc.entities.count))")
        model.editor.undo(); model.editor.undo()
        check(model.doc.entities.isEmpty, "local model edits are undoable")
        // 2. A bulk edit waits for confirmation.
        server.replies = [reply((0..<40).map { "LINE \($0 * 100),0 \($0 * 100),1000 " })]
        session.send("draw forty lines")
        spin(10) { !session.busy }
        check(session.pending?.commands.count == 40 && model.doc.entities.isEmpty, "local model: bulk change asks for confirmation first")
        session.discard()
        check(session.pending == nil && model.doc.entities.isEmpty, "local model: discarded bulk change leaves the drawing unchanged")
        // 3. Remote endpoints are refused for the local provider (privacy).
        session.config.endpoint = "https://example.com/v1/chat/completions"
        let n = server.requests.count
        session.send("hello")
        spin(5) { !session.busy }
        check(server.requests.count == n && session.messages.last?.text.contains("must be on this Mac") == true, "local model: non-local endpoints refused")
    }

    /// Canvas picking and window selection through the R-tree (SYS-015) on 100 000 objects: same results as a full
    /// scan, and fast enough for hover picking on every mouse move.
    private static func spatialPickChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        d.entities.reserveCapacity(100_000)
        for i in 0..<100_000 {
            let x = Double(i % 400) * 100, y = Double(i / 400) * 100
            _ = d.add(.line(LineGeom(Vec2(x, y), Vec2(x + 60, y + 30))), layer: "0")
        }
        let model = AppModel()
        model.editor.replaceDocument(d, url: nil)
        let canvas = PlanCanvasView(model: model)
        canvas.setFrameSize(NSSize(width: 1200, height: 800))
        canvas.zoom(toRect: CGRect(x: 0, y: 0, width: 4000, height: 2600), recordHistory: false)
        let t0 = Date()
        let scene = canvas.ensureScene()
        _ = scene.tree.count
        let build = Date().timeIntervalSince(t0)
        // Pick the middle of line k and compare with the expected id.
        var ok = true
        let t1 = Date()
        let n = 2000
        for k in 0..<n {
            let i = (k * 7919) % 100_000
            let x = Double(i % 400) * 100 + 30, y = Double(i / 400) * 100 + 15
            if canvas.pick(at: Vec2(x, y)) != d.entities[i].id { ok = false }
        }
        let per = Date().timeIntervalSince(t1) / Double(n) * 1000
        check(ok, "R-tree pick finds the right object among 100 000")
        check(per < 1.0, "pick on 100 000 objects takes \(fmt(per, 3)) ms (< 1 ms), scene + index built in \(fmt(build, 2)) s")
        // Window selection of a 10 × 10 block = 100 lines, crossing picks up the neighbours touched.
        let win = canvas.selectIDs(in: BBox2(min: Vec2(-10, -10), max: Vec2(990, 990)), crossing: false)
        check(win.count == 100, "window selection through the index (\(win.count) of 100)")
        let cross = canvas.selectIDs(in: BBox2(min: Vec2(-10, -10), max: Vec2(1020, 1020)), crossing: true)
        check(cross.count == 121, "crossing selection through the index (\(cross.count) of 121)")
        // Redraw of the whole 100 000-object scene (pan/zoom repaint, SYS-014) into a Retina-size bitmap.
        if let ctx = CGContext(data: nil, width: 2400, height: 1600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            let b = scene.bounds
            let k = min(2400 / b.width, 1600 / b.height)
            ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -b.minX, y: -b.minY)
            scene.draw(in: ctx, visible: b, scale: k, params: RenderParams())   // warm-up (merged paths)
            let t2 = Date()
            for _ in 0..<5 { scene.draw(in: ctx, visible: b, scale: k, params: RenderParams()) }
            let ms = Date().timeIntervalSince(t2) / 5 * 1000
            check(ms < 16.7, "full redraw of 100 000 objects within a 60 fps frame: \(fmt(ms, 1)) ms")
        }
    }

    /// Crash reports (SYS-025): nothing unless opted in; the signal path writes the environment and a symbolised
    /// stack; reports are redacted of home paths and file names.
    private static func crashReportChecks(_ check: (Bool, String) -> Void) {
        let wasInstalled = CrashReporter.isInstalled
        if !CrashReporter.enabled && !wasInstalled { check(!CrashReporter.isInstalled, "crash reports are off unless opted in") }
        guard !wasInstalled else { return }
        CrashReporter.install(force: true)
        let path = CrashReporter.currentReportPath
        check(CrashReporter.isInstalled && FileManager.default.fileExists(atPath: path), "crash report file prepared on install")
        check(!CrashReporter.pendingReports().contains { $0.path == path }, "the running session's report is not offered")
        CrashReporter.writeSignal(SIGSEGV)
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        check(text.contains("Signal 11") && text.contains("Oanarina Archi Tool") && text.components(separatedBy: "\n").count > 4, "signal handler writes the signal and a stack")
        CrashReporter.uninstall()
        check(!CrashReporter.isInstalled && FileManager.default.fileExists(atPath: path), "a written report survives the handler removal")
        try? FileManager.default.removeItem(atPath: path)
        let red = CrashReporter.redact("reason: cannot open \(NSHomeDirectory())/Projects/House.archi at /Volumes/Work/plans/A-101.dxf")
        check(!red.contains(NSHomeDirectory()) && !red.contains("House.archi") && !red.contains("A-101.dxf") && red.contains("<file>"), "crash reports are redacted of paths and file names")
        check(CrashReporter.issueURL("stack")?.absoluteString.hasPrefix(CrashReporter.issueURL) == true, "crash report issue link")
    }
}
