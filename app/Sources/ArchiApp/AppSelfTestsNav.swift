// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import AppKit
import SceneKit
import PDFKit
import Network
import ArchiCore

/// Self-test checks of the navigation, selection, sheet, view and help additions (APP, SEL, SHT, VIS, SCR).
@MainActor
extension AppSelfTests {
    /// True when run with --selftest (no windows): checks that spin the run loop (scripts, HTTP) only run then.
    static var headless = false

    static func spin(_ timeout: TimeInterval, until done: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !done() && Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    static func navChecks(_ check: (Bool, String) -> Void) {
        // Commands: registered, reachable from a menu, not shadowing core commands.
        let core = CommandRegistry(); core.ensureBuiltins()
        let clashes = AppCommandsNav.all.flatMap { [$0.name] + $0.aliases }.filter { core.lookup($0) != nil }
        check(clashes.isEmpty, "navigation commands do not shadow core commands: \(clashes.joined(separator: ", "))")
        for d in AppCommandsNav.all { check(CommandCatalog.navigationItems.contains { $0.names.contains(d.name) }, "\(d.name) is on the Navigation & Sheets menu") }

        // SEL-022: Tab chain of joined walls (corner joins and a T-junction), not the separate wall.
        var wd = ArchiDocument()
        let w1 = wd.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0))))
        let w2 = wd.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 4000))))
        let w3 = wd.addElement(.wall(WallGeom(start: Vec2(6000, 4000), end: Vec2(0, 4000))))
        let w4 = wd.addElement(.wall(WallGeom(start: Vec2(0, 4000), end: Vec2(0, 0))))
        let wt = wd.addElement(.wall(WallGeom(start: Vec2(3000, 0), end: Vec2(3000, -2000))))
        let wx = wd.addElement(.wall(WallGeom(start: Vec2(20000, 0), end: Vec2(25000, 0))))
        check(WallChain.ids(from: w3, doc: wd) == [w1, w2, w3, w4, wt].sorted(), "wall chain: 4 corner-joined walls and the T wall")
        check(WallChain.ids(from: wx, doc: wd) == [wx] && WallChain.ids(from: 999_999, doc: wd).isEmpty, "separate wall is its own chain; unknown id empty")

        // SEL-034 grip modes on the selection, Copy, one undo step; typed values.
        var gd = ArchiDocument()
        let l1 = gd.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))), layer: "0")
        let ged = Editor(document: gd)
        GripModeEdit.apply(ged, ids: [l1], Grips.modeTransform(.rotate, base: .zero, to: Vec2(0, 5), reference: 1)!, copy: false, label: "Grip Rotate")
        if case .line(let lg)? = ged.doc.entity(l1)?.geometry { check(lg.b.isClose(Vec2(0, 1000), tol: 1e-6), "grip rotate 90° about the base") } else { check(false, "rotated line") }
        ged.undo()
        let copies = GripModeEdit.apply(ged, ids: [l1], GripModeEdit.typedTransform(.move, base: .zero, cursor: Vec2(0, 10), value: 500)!, copy: true, label: "Grip Move Copy")
        check(copies.count == 1 && copies[0] != l1 && ged.doc.entities.count == 2, "grip move with Copy adds a copy")
        if let c = copies.first, case .line(let lg)? = ged.doc.entity(c)?.geometry { check(lg.a.isClose(Vec2(0, 500), tol: 1e-9), "typed 500 moves toward the cursor") }
        let sc = GripModeEdit.typedTransform(.scale, base: Vec2(0, 0), cursor: .zero, value: 2)!
        check(sc.apply(Vec2(1000, 0)).isClose(Vec2(2000, 0), tol: 1e-9) && GripModeEdit.typedTransform(.mirror, base: .zero, cursor: .zero, value: 1) == nil, "typed scale factor; mirror needs a point")
        check(abs(GripModeEdit.reference([l1], doc: ged.doc) - 500) < 1e-9, "scale reference is half the selection size")
        check(GripModeEdit.keywords["MO"] == .move && GripModeEdit.keywords["SC"] == .scale && GripMode.mirror.next == .stretch, "grip mode keywords and cycle")

        // Canvas: twist, pick (locked layers), grips through the core, typed grip input, lasso.
        let model = AppModel()
        var cd = ArchiDocument()
        cd.layers.append(Layer(name: "LOCKED")); cd.layers[cd.layers.count - 1].locked = true
        let a = cd.add(.line(LineGeom(Vec2(0, 0), Vec2(1000, 0))), layer: "0")
        let b = cd.add(.line(LineGeom(Vec2(0, 500), Vec2(1000, 500))), layer: "LOCKED")
        let c = cd.add(.circle(CircleGeom(Vec2(3000, 3000), 200)), layer: "0")
        model.editor.replaceDocument(cd, url: nil)
        let canvas = PlanCanvasView(model: model)
        canvas.setFrameSize(NSSize(width: 800, height: 600))
        canvas.zoom(toRect: CGRect(x: -500, y: -500, width: 4500, height: 4500), recordHistory: false)
        check(canvas.pick(at: Vec2(500, 0)) == a && canvas.pick(at: Vec2(500, 500)) == nil, "pick selects unlocked objects only (SEL-001)")
        let p0 = Vec2(1234, -567)
        canvas.setTwist(.pi / 2)
        check(canvas.toWorld(canvas.toView(p0)).isClose(p0, tol: 1e-6), "twisted view: toWorld ∘ toView = identity")
        let o = canvas.toView(.zero), ex = canvas.toView(Vec2(1000, 0))
        check(abs(ex.x - o.x) < 1e-6 && ex.y > o.y, "90° twist shows world +X pointing up")
        check(canvas.pick(at: Vec2(500, 0)) == a, "pick works in a twisted view")
        canvas.setTwist(0)
        check(ViewTwist.normalized(-90) == 270 && ViewTwist.normalized(720) == 0, "twist angle normalisation")
        // Grip stretch via the core grip model (index 2 = end point of a line), typed point.
        check(canvas.makeGripHot(a, index: 2), "grip made hot")
        check(canvas.handleGripInput("2000,0"), "typed point accepted by the hot grip")
        if case .line(let lg)? = model.doc.entity(a)?.geometry { check(lg.b.isClose(Vec2(2000, 0), tol: 1e-9), "grip stretch to a typed point (SEL-033)") } else { check(false, "stretched line") }
        // Typed distance toward the cursor (SEL-038).
        canvas.makeGripHot(a, index: 2); canvas.setCursorPoint(Vec2(2000, 800))
        _ = canvas.handleGripInput("250")
        if case .line(let lg)? = model.doc.entity(a)?.geometry { check(lg.b.isClose(Vec2(2000, 250), tol: 1e-6), "typed grip distance 250 toward the cursor (got \(lg.b))") }
        // Space / keywords cycle modes; typed rotate.
        model.editor.selection = [a]
        canvas.makeGripHot(a, index: 0)
        _ = canvas.handleGripInput("")
        check(canvas.hotGripState?.mode == .move, "Enter/Space cycles Stretch → Move")
        _ = canvas.handleGripInput("RO")
        check(canvas.hotGripState?.mode == .rotate, "RO keyword selects Rotate")
        _ = canvas.handleGripInput("90")
        if case .line(let lg)? = model.doc.entity(a)?.geometry { check(lg.a.isClose(.zero, tol: 1e-6) && lg.b.isClose(Vec2(-250, 2000), tol: 1e-6), "typed 90° grip rotation (got \(lg.b))") }
        check(canvas.hotGripState == nil, "grip released after the edit")
        // Multi-functional grip option through the core (SEL-035): add a vertex to a polyline.
        model.editor.transaction("t") { d in _ = d.add(.polyline(PolylineGeom([PolyVertex(Vec2(0, 2000)), PolyVertex(Vec2(1000, 2000)), PolyVertex(Vec2(1000, 3000))])), layer: "0") }
        if let pid = model.doc.entities.last?.id, let pe = model.doc.entity(pid), let mid = Grips.grips(pe.geometry).first(where: { $0.kind == .midpoint }) {
            check(model.editor.gripAction(pid, grip: mid, action: .addVertex, to: Vec2(500, 2300), snap: false), "add-vertex grip option")
            if case .polyline(let pg)? = model.doc.entity(pid)?.geometry { check(pg.vertices.count == 4, "polyline has 4 vertices after Add Vertex") }
        } else { check(false, "polyline midpoint grip") }
        // Lasso around the circle only (clockwise = window).
        model.editor.selection = []
        let loop = [Vec2(2600, 2600), Vec2(2600, 3400), Vec2(3400, 3400), Vec2(3400, 2600)].map { canvas.toView($0) }
        let got = canvas.lassoSelect(loop)
        check(got == [c] && model.editor.selection == [c], "lasso window selects the circle only (SEL-007)")
        model.editor.selection = []
        check(canvas.lassoSelect([Vec2(-100, -100), Vec2(3000, 600), Vec2(-100, 600)].map { canvas.toView($0) }).isEmpty == false, "lasso crossing touches the line")
        check(!model.editor.selection.contains(b), "lasso never selects locked objects")

        // SEL-036: flip arrows of a selected door flip its swing (one undo step each).
        var fd = ArchiDocument()
        let fw = fd.addElement(.wall(WallGeom(start: .zero, end: Vec2(5000, 0))))
        let door = fd.addElement(.opening(OpeningGeom(kind: .door, hostWall: fw, offset: 2500, width: 900, height: 2100)))
        let fm = AppModel()
        fm.editor.replaceDocument(fd, url: nil)
        let fc = PlanCanvasView(model: fm)
        fc.setFrameSize(NSSize(width: 800, height: 600))
        fc.zoom(toRect: CGRect(x: -500, y: -3000, width: 6000, height: 6000), recordHistory: false)
        fm.editor.selection = [door]
        fc.refreshGrips()
        let ctrls = FlipControls.controls(fm.doc.element(door)!, doc: fm.doc, gap: 100)
        check(ctrls.map(\.kind) == [.facing, .hand], "door has facing and hand flip arrows")
        if let fz = FlipControls.controls(fm.doc.element(door)!, doc: fm.doc, gap: Double(16 / fc.scale)).first, let hit = fc.flipHit(fc.toView(fz.point)) {
            fm.editor.transaction("Flip Facing") { FlipControls.apply(hit, doc: &$0) }
            if case .opening(let o)? = fm.doc.element(door)?.geometry { check(o.flipFacing && !o.flipHand, "clicking the door flip arrow flips the swing") }
            fm.editor.undo()
            if case .opening(let o)? = fm.doc.element(door)?.geometry { check(!o.flipFacing, "flip is one undo step") }
        } else { check(false, "flip arrow hit under the cursor") }
        check(!FlipControls.apply(FlipControls.Control(id: fw, kind: .facing, point: .zero, direction: Vec2(1, 0)), doc: &fd), "walls have no opening flip")
        // Wall flip keeps the hosted door in place; slab edge grip; roof slope grip.
        var wf = fm.doc
        check(FlipControls.wallControl(wf.element(fw)!, gap: 100) != nil && FlipControls.flipWall(fw, doc: &wf), "wall flip arrow")
        if case .wall(let w)? = wf.element(fw)?.geometry, case .opening(let o)? = wf.element(door)?.geometry {
            check(w.start == Vec2(5000, 0) && abs(o.offset - 2500) < 1e-9 && o.flipFacing, "flipped wall keeps its door in place, facing flipped with it")
        } else { check(false, "flipped wall") }
        let sq = [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 3000), Vec2(0, 3000)]
        check(BIMGrips.moved(sq, grip: 4 + 1, from: Vec2(4000, 1500), to: Vec2(4500, 1500)) == [Vec2(0, 0), Vec2(4500, 0), Vec2(4500, 3000), Vec2(0, 3000)], "slab edge grip moves the whole edge")
        let roof = RoofGeom(boundary: sq, pitch: 45)
        if let g = BIMGrips.slopeGrip(roof, unit: 1000) {
            check(g.isClose(Vec2(2000, 1000), tol: 1e-6), "45° slope grip 1 m inside the eave")
            check(abs(BIMGrips.pitch(roof, dragTo: Vec2(2000, 1732.0508), unit: 1000) - 30) < 0.01, "dragging the slope grip to 1.732 m gives 30°")
        } else { check(false, "roof slope grip") }
        var rd = ArchiDocument(); let rid = rd.addElement(.roof(roof))
        let rg = GripEditor.grips(rd.element(rid)!, doc: rd)
        check(rg.count == 9, "roof grips: 4 vertices, 4 edges, 1 slope")
        if case .roof(let r2) = GripEditor.moved(rd.element(rid)!, grip: 8, from: rg[8], to: Vec2(2000, 577.35), doc: rd) { check(abs(r2.pitch - 60) < 0.01, "slope grip edit through the grip editor") }

        // APP-023 shortcut menu.
        let items = ShortcutMenu.items(hasSelection: true, lastCommand: "LINE", recentInput: ["LINE", "CIRCLE", "LINE", "MOVE"], canUndo: true, canRedo: false)
        let titles = items.map(\.title)
        check(["Move", "Copy Selection", "Rotate", "Erase", "Properties"].allSatisfy(titles.contains) && titles.first == "Repeat LINE", "selection shortcut menu: Repeat, Move, Copy, Rotate, Erase, Properties")
        if case .submenu(_, let rec)? = items.first(where: { $0.title == "Recent Input" })?.action { check(rec.map(\.title) == ["MOVE", "LINE", "CIRCLE"], "recent input newest first without duplicates") } else { check(false, "recent input submenu") }
        let runs = (items + ShortcutMenu.items(hasSelection: false, lastCommand: nil, recentInput: [], canUndo: false, canRedo: false)).compactMap { i -> String? in if case .run(let l) = i.action { return l }; return nil }
        check(runs.allSatisfy { CommandRegistry.shared.lookup(String($0.split(separator: " ")[0])) != nil }, "every shortcut menu command exists")

        // APP-015 contextual tabs.
        check(ContextualRibbon.tab(wd, [w1])?.title == "Modify Wall", "selecting a wall shows Modify Wall")
        var td = ArchiDocument()
        let t1 = td.add(.text(TextGeom(position: .zero, height: 250, content: "A")), layer: "0")
        let h1 = td.add(.line(LineGeom(.zero, Vec2(1, 1))), layer: "0")
        check(ContextualRibbon.tab(td, [t1])?.title == "Text Editor" && ContextualRibbon.tab(td, [t1, h1]) == nil && ContextualRibbon.tab(td, []) == nil, "text tab; mixed selection has none")
        for k in [ContextualRibbon.tab(wd, [w1]), ContextualRibbon.tab(td, [t1])].compactMap({ $0 }) {
            let missing = k.items.filter { i in !i.names.contains { CommandRegistry.shared.lookup($0) != nil } }.map(\.title)
            check(missing.isEmpty, "\(k.title) tab commands exist: missing \(missing)")
        }

        // APP-013 model/layout tabs, CTAB kept with the drawing.
        model.editor.transaction("Sheets") { $0.layouts = [ArchiCore.Layout(name: "A101"), ArchiCore.Layout(name: "A102")] }
        check(LayoutTabs.titles(model.doc) == ["Model", "A101", "A102"], "tabs: Model then sheets")
        LayoutTabs.select(model, 2)
        check(model.mode == .sheet && model.activeLayout == 1 && model.doc.variable("CTAB") == "A102" && LayoutTabs.current(model) == 2, "selecting a layout tab shows it and sets CTAB")
        LayoutTabs.select(model, 0)
        check(model.mode == .plan && model.doc.variable("CTAB") == "Model", "Model tab returns to model space")
        model.editor.doc.setVariable("CTAB", "A101"); LayoutTabs.restore(model)
        check(model.mode == .sheet && model.activeLayout == 0, "CTAB restores the tab when the drawing opens")
        model.mode = .plan

        // APP-044 progress.
        let pc = ProgressCenter.shared
        let job = pc.begin("Test")
        pc.update(job, fraction: 1.7, detail: "x")
        check(pc.current?.fraction == 1 && pc.current?.detail == "x" && !pc.isCancelled(job), "progress clamps and reports")
        pc.cancel(job)
        check(pc.isCancelled(job), "cancel is immediate")
        pc.end(job)
        check(pc.current?.id != job && pc.isCancelled(job), "ended job disappears")

        // APP-042 annotation scale.
        check(AnnotationScaleControl.set(model, "1:50") && model.doc.variable("CANNOSCALE") == "1:50" && Annotative.currentScale(model.doc) == 50, "annotation scale set from the status bar")
        check(!AnnotationScaleControl.set(model, "abc") && AnnotationScaleControl.list(model.doc).contains("1:50"), "invalid scale refused")
        model.editor.undo()
        check(model.doc.variable("CANNOSCALE") != "1:50", "annotation scale change is undoable")

        // APP-024 properties palette: 50 objects change layer in one undo step; *VARIES*.
        var pd = ArchiDocument()
        var ids: [EntityID] = []
        for i in 0..<50 { ids.append(pd.add(.line(LineGeom(Vec2(0, Double(i) * 10), Vec2(100, Double(i) * 10))), layer: i % 2 == 0 ? "0" : "A-WALL")) }
        let ped = Editor(document: pd)
        check(PropertiesPalette.rows(ids, doc: ped.doc).first { $0.name.lowercased() == "layer" }?.value == "*VARIES*", "*VARIES* for differing layers")
        let undoBefore = ped.history.canUndo
        check(PropertiesPalette.apply(ped, "layer", "A-DOOR", ids: ids) == 0 && ped.doc.entities.allSatisfy { $0.layer == "A-DOOR" }, "layer of 50 objects changed")
        ped.undo()
        check(!undoBefore && !ped.history.canUndo && ped.doc.entities.filter { $0.layer == "A-DOOR" }.isEmpty, "one undo step restores all 50")
        check(!PropertiesPalette.quickRows([ids[0]], doc: pd).isEmpty, "quick properties rows")

        // APP-033 inspector.
        let rep = ObjectInspector.report(a, doc: model.doc)
        check(rep.first?.1 == "#\(a)" && rep.contains { $0.0 == "GUID" && $0.1.count == 22 } && rep.contains { $0.0 == "Geometry" } && ObjectInspector.report(-5, doc: model.doc).isEmpty, "inspector: ID, 22-char GUID, geometry")

        // APP-031 design center.
        var src = ArchiDocument()
        src.layers.append(Layer(name: "FURN"))
        src.blocks["Leg"] = Block(name: "Leg", basePoint: .zero, entities: [Entity(layer: "FURN", geometry: .circle(CircleGeom(.zero, 20)))])
        src.blocks["Table"] = Block(name: "Table", basePoint: .zero, entities: [Entity(layer: "0", geometry: .insert(InsertGeom(block: "Leg", position: .zero)))])
        var dst = ArchiDocument()
        let added = DesignCenter.copy(.blocks, ["Table"], from: src, into: &dst)
        check(Set(added) == ["Table", "Leg"] && dst.layer(named: "FURN") != nil, "design center brings nested blocks and their layers")
        check(DesignCenter.copy(.layers, ["FURN", "0"], from: src, into: &dst).isEmpty && DesignCenter.names(.blocks, in: src) == ["Leg", "Table"], "existing names are kept")

        // SHT-005: a 1:100 viewport shows a 10 m wall as 100 mm on paper.
        let vp100 = Viewport(origin: Vec2(20, 20), size: Vec2(200, 150), viewCenter: Vec2(5000, 0), scale: SheetTools.scale(ratio: 100, units: .millimeters))
        let tr = SheetComposer.modelToPaper(vp100)
        let pa = CGPoint(x: 0, y: 0).applying(tr), pb = CGPoint(x: 10000, y: 0).applying(tr)
        check(abs(hypot(pb.x - pa.x, pb.y - pa.y) - 100) < 1e-9 && SheetTools.paperPoint(Vec2(10000, 0), in: vp100).distance(to: SheetTools.paperPoint(.zero, in: vp100)) == 100, "1:100 viewport: 10 m wall = 100 mm")
        check(SheetTools.modelPoint(SheetTools.paperPoint(Vec2(123, 456), in: vp100), in: vp100).isClose(Vec2(123, 456), tol: 1e-9) && SheetTools.scale(ratio: 50, units: .meters) == 0.05, "paper ↔ model round trip; scale in metres")
        check(abs(SheetTools.modelWindow(vp100).width - 20000) < 1e-9, "maximised viewport window (VPMAX)")

        // SHT-009 align.
        var al = ArchiCore.Layout(name: "S", viewports: [Viewport(origin: Vec2(20, 50), size: Vec2(100, 100), viewCenter: .zero, scale: 100),
                                                         Viewport(origin: Vec2(150, 60), size: Vec2(100, 100), viewCenter: Vec2(0, 3000), scale: 50)])
        check(SheetTools.align(&al, base: 0, basePoint: Vec2(0, 0), other: 1, otherPoint: Vec2(0, 0), .horizontal), "align viewports")
        check(abs(SheetTools.paperPoint(.zero, in: al.viewports[0]).y - SheetTools.paperPoint(.zero, in: al.viewports[1]).y) < 1e-9, "aligned points share the paper height")
        check(!SheetTools.align(&al, base: 0, basePoint: .zero, other: 0, otherPoint: .zero, .vertical), "same viewport refused")

        // SHT-004 / SHT-008 clip and polygonal viewports; SHT-011 grid; SHT-020 placeholders; SHT-021 fields; SHT-040 page setups.
        var sd = ArchiDocument()
        sd.layouts = [ArchiCore.Layout(name: "A101", viewports: [vp100, vp100]), ArchiCore.Layout(name: "Future")]
        let tri = [Vec2(30, 30), Vec2(150, 30), Vec2(30, 140)]
        SheetTools.setClip(&sd, layoutIndex: 0, viewport: 1, tri)
        check(SheetTools.clip(sd, layout: "A101", viewport: 1)?.count == 3 && sd.layouts[0].viewports[1].origin == Vec2(30, 30) && sd.layouts[0].viewports[1].size == Vec2(120, 110), "clip stored, frame fitted")
        check(SheetTools.modelPoint(Vec2(90, 85), in: sd.layouts[0].viewports[1]).isClose(SheetTools.modelPoint(Vec2(90, 85), in: vp100), tol: 1e-6), "clipping keeps the model where it was on paper")
        SheetTools.viewportRemoved(&sd, layoutIndex: 0, viewport: 0); sd.layouts[0].viewports.remove(at: 0)
        check(SheetTools.clip(sd, layout: "A101", viewport: 0) != nil && SheetTools.clip(sd, layout: "A101", viewport: 1) == nil, "clip follows the viewport when an earlier one is removed")
        let pi = SheetTools.addPolygonal(&sd, layoutIndex: 0, [Vec2(200, 20), Vec2(260, 20), Vec2(280, 80), Vec2(220, 100)], center: .zero, scale: 100, level: nil)
        check(pi == 1 && SheetTools.clip(sd, layout: "A101", viewport: 1)?.count == 4, "polygonal viewport")
        SheetTools.setClip(&sd, layoutIndex: 0, viewport: 1, nil)
        check(SheetTools.clip(sd, layout: "A101", viewport: 1) == nil, "clip removed")
        sd.setVariable(SheetTools.gridKey("A101"), "10")
        check(SheetTools.gridSpacing(sd, layout: "a101") == 10 && SheetTools.snap(Vec2(23, 47), spacing: 10) == Vec2(20, 50) && SheetTools.snap(Vec2(23, 47), spacing: 0) == Vec2(23, 47), "sheet guide grid snapping")
        SheetTools.setPlaceholder(&sd, 1, true)
        check(SheetTools.publishable(sd) == [0] && SheetTools.isPlaceholder(sd.layouts[1]), "placeholder sheet is not published")
        let idxTable = SheetSet.indexTable(sd, origin: .zero)
        check(idxTable.cells.count == 3, "placeholder sheet still listed in the sheet index")
        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest-\(UUID().uuidString).pdf")
        do { try Plotter.writeSheetsPDF(doc: sd, to: pdfURL) } catch { check(false, "publish PDF: \(error)") }
        check(PDFDocument(url: pdfURL)?.pageCount == 1, "published PDF has 1 page (placeholder skipped)")
        try? FileManager.default.removeItem(at: pdfURL)
        SheetTools.setProjectField(&sd, "clientref", "CR-9")
        SheetTools.setSheetField(&sd, 0, "Phase", "Planning")
        SheetTools.setSheetField(&sd, 1, "ClientRef", "OVERRIDE")
        check(SheetTools.fields(sd, layout: sd.layouts[0]).map(\.0) == ["CLIENTREF", "PHASE"] && SheetTools.fields(sd, layout: sd.layouts[1]).first?.1 == "OVERRIDE", "project and sheet fields")
        func texts(_ d: ArchiDocument, _ i: Int) -> [String] {
            SheetComposer.decorations(doc: d, layout: d.layouts[i], layoutIndex: i).flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil }
        }
        check(texts(sd, 0).contains("CR-9") && texts(sd, 0).contains("Planning"), "custom fields drawn on the title block")
        sd.info.name = "Villa Nova"
        check(texts(sd, 0).contains("Villa Nova") && texts(sd, 1).contains("Villa Nova"), "project name updates every title block (SHT-013)")
        sd.setVariable("TITLEBLOCKLOGO", "/tmp/logo.png")
        let imgs = SheetComposer.decorations(doc: sd, layout: sd.layouts[0], layoutIndex: 0).flatMap(\.items).compactMap { i -> ImageGeom? in if case .image(let g) = i { return g }; return nil }
        check(imgs.count == 1 && imgs[0].path == "/tmp/logo.png" && imgs[0].size == Vec2(26, 11), "title block logo (SHT-014)")
        sd.variables["TITLEBLOCKLOGO"] = nil
        var srcPS = ArchiDocument(); srcPS.layouts = [ArchiCore.Layout(name: "Office A1", paper: PaperSize.standard[0])]
        var ps = PageSetup(); ps.colorMode = .monochrome; ps.lineweightScale = 1.5; ps.store(in: &srcPS, layoutIndex: 0)
        let setups = SheetTools.pageSetups(srcPS)
        check(setups.count == 1 && setups[0].0 == "Office A1", "page setups listed from another drawing")
        SheetTools.applyPageSetup(setups[0].1, to: &sd, layouts: [0, 1], paper: srcPS.layouts[0].paper)
        check(PageSetup.load(sd, layoutIndex: 1).colorMode == .monochrome && sd.layouts[0].paper == PaperSize.standard[0], "page setup imported with paper (PSETUPIN)")

        // VIS-025…031 visual styles: names and what the 3D builder produces.
        for k in ["2dwireframe", "Wireframe", "Hidden", "Realistic", "Conceptual", "Shaded", "shadedwithEdges", "Xray", "Sketchy"] {
            check(Scene3DBuilder.visualStyles.contains(VisualStyleNames.canonical(k)), "VSCURRENT \(k) maps to a 3D style")
        }
        check(VisualStyleNames.canonical("Hidden") == "Hidden Line" && VisualStyleNames.canonical("shadedwithEdges") == "Shaded with Edges", "style names")
        var vd = ArchiDocument()
        _ = vd.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        for style in Scene3DBuilder.visualStyles {
            let bld = Scene3DBuilder()
            bld.update(doc: vd, style: style)
            var tris = 0, lines = 0, lighting: Set<String> = []
            bld.modelRoot.enumerateHierarchy { n, _ in
                guard n.name != "ground", n.parent?.name != "ground", let g = n.geometry else { return }
                for e in g.elements { if e.primitiveType == .triangles { tris += 1; for m in g.materials { lighting.insert(m.lightingModel.rawValue) } } else if e.primitiveType == .line { lines += 1 } }
            }
            let info = "(tris \(tris), lines \(lines), lighting \(lighting.sorted()))"
            switch style {
            case "Wireframe": check(tris == 0 && lines > 0, "wireframe: edges only \(info)")
            case "Hidden Line": check(tris > 0 && lines > 0 && lighting == [SCNMaterial.LightingModel.constant.rawValue], "hidden line: flat white faces hide back edges")
            case "Shaded": check(tris > 0 && lines == 0 && lighting == [SCNMaterial.LightingModel.blinn.rawValue], "shaded: lit faces, no edges \(info)")
            case "Shaded with Edges": check(tris > 0 && lines > 0, "shaded with edges")
            case "Conceptual": check(tris > 0 && lines > 0 && lighting == [SCNMaterial.LightingModel.constant.rawValue], "conceptual: consistent colours with edges \(info)")
            case "X-Ray": check(tris > 0 && lines > 0, "x-ray: faces and edges")
            default: check(tris > 0, "\(style): faces")
            }
        }

        // VIS-034 custom visual styles: base + overrides, stored in the drawing, applied by the 3D builder.
        var csd = ArchiDocument()
        _ = csd.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))))
        check(!VisualStyleDef.save(VisualStyleDef(name: "Shaded", base: "Shaded"), in: &csd) && !VisualStyleDef.save(VisualStyleDef(name: "X", base: "Nope"), in: &csd), "built-in names and unknown bases refused")
        check(VisualStyleDef.save(VisualStyleDef(name: "Ghost", base: "shaded", edges: true, edgeColor: 0xFF0000, faceOpacity: 0.3, shadows: false), in: &csd), "custom style saved")
        check(VisualStyleDef.named("ghost", in: csd)?.base == "Shaded" && VisualStyleDef.menuNames(csd).last == "Ghost", "custom style listed with a canonical base")
        let gb = Scene3DBuilder()
        gb.update(doc: csd, style: "Ghost")
        var gTris = 0, gLines = 0, gOpacity: CGFloat = 1
        gb.modelRoot.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            for e in g.elements { if e.primitiveType == .triangles { gTris += 1; gOpacity = min(gOpacity, g.materials.first?.transparency ?? 1) } else if e.primitiveType == .line { gLines += 1 } }
        }
        check(gb.style == "Shaded" && gTris > 0 && gLines > 0 && gOpacity < 0.35 && gb.sunNode.light?.castsShadow == false, "Ghost: shaded base with edges, 30 % faces, no shadows")
        check(VisualStyleDef.delete("GHOST", in: &csd) && VisualStyleDef.all(csd).isEmpty && csd.variable(VisualStyleDef.variable) == nil, "custom style deleted")

        // APP-007 tiled views: arrangement and per-tile views persist; section / elevation tiles project the model.
        let oldArr = TiledViewsState.arrangement, oldKinds = TiledViewsState.kinds
        TiledViewsState.arrangement = .four
        TiledViewsState.setKind(.east, at: 3)
        check(TiledViewsState.arrangement == .four && TiledViewsState.kinds[3] == .east && TiledViewsState.kinds.count == 4, "tile arrangement and views are remembered")
        let tileModel = AppModel(); tileModel.editor.replaceDocument(vd, url: nil)
        let pt = ProjectionTileView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        pt.model = tileModel; pt.kind = .elevationSouth
        let pe = pt.entries()
        pt.fit()
        check(!pe.entries.isEmpty && !pe.bounds.isEmpty && pt.fitted, "elevation tile projects the wall")
        let z0 = pt.zoom
        pt.zoom(by: 2, about: CGPoint(x: 200, y: 150))
        check(abs(pt.zoom - 2 * z0) < 1e-9, "tiles zoom independently")
        TiledViewsState.arrangement = oldArr; TiledViewsState.kinds = oldKinds

        // SHT-028 plot area and SHT-029 fit: extents, window, limits; standard or exact ratio; old setups decode.
        var pad = ArchiDocument()
        _ = pad.add(.line(LineGeom(Vec2(0, 0), Vec2(40000, 20000))), layer: "0")
        let parea = BBox2(min: Vec2(0, 0), max: Vec2(400, 200))
        var pset = PageSetup()
        let fe = Plotter.modelFrame(doc: pad, setup: pset, extents: BBox2(min: .zero, max: Vec2(40000, 20000)), area: parea)
        check(fe.ratio == 100 && fe.box.width == 40000, "extents fit at 1:100")
        pset.exactFit = true
        let fx = Plotter.modelFrame(doc: pad, setup: pset, extents: BBox2(min: .zero, max: Vec2(30000, 15000)), area: parea)
        check(abs(fx.ratio - 75) < 1e-9, "exact fit 1:75 instead of a standard scale")
        pset.plotArea = .window; pset.setWindow(BBox2(min: Vec2(1000, 1000), max: Vec2(5000, 3000))); pset.exactFit = false
        let fwin = Plotter.modelFrame(doc: pad, setup: pset, extents: .empty, area: parea)
        check(fwin.box.center.isClose(Vec2(3000, 2000), tol: 1e-9) && fwin.ratio == 10, "window plot area at 1:10")
        pset.plotArea = .limits; pad.setVariable("LIMMIN", "0,0"); pad.setVariable("LIMMAX", "84000,59400")
        check(Plotter.modelFrame(doc: pad, setup: pset, extents: .empty, area: parea).box.width == 84000, "limits plot area")
        pset.modelScale = 50
        check(Plotter.modelFrame(doc: pad, setup: pset, extents: .empty, area: parea).ratio == 50, "fixed plot scale wins")
        check((try? JSONDecoder().decode(PageSetup.self, from: Data(#"{"colorMode":"Color"}"#.utf8)))?.plotArea == .extents, "older page setups default to extents")
        let rt = try? JSONDecoder().decode(PageSetup.self, from: JSONEncoder().encode(pset))
        check(rt == pset, "plot area and window round-trip")

        // SHT-036: sheet SVG at true size, viewport content mapped to paper and clipped to the frame.
        var svgDoc = ArchiDocument()
        svgDoc.info.name = "Svg House"
        _ = svgDoc.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 0))), layer: "A-WALL")
        _ = svgDoc.add(.line(LineGeom(Vec2(0, 0), Vec2(0, 90000))), layer: "0")
        svgDoc.layouts = [ArchiCore.Layout(name: "A101", paper: PaperSize.standard[1], viewports: [Viewport(origin: Vec2(50, 100), size: Vec2(200, 100), viewCenter: Vec2(5000, 0), scale: 100)])]
        let es = SheetSVG.entries(doc: svgDoc, layoutIndex: 0)
        let strokes = es.flatMap(\.items).compactMap { i -> [Vec2]? in if case .stroke(let p, _, _) = i { return p }; return nil }
        check(strokes.contains { $0.count == 2 && $0[0].isClose(Vec2(100, 150), tol: 1e-6) && $0[1].isClose(Vec2(200, 150), tol: 1e-6) }, "wall line mapped to paper: 10 m = 100 mm at 1:100")
        check(!strokes.contains { $0.contains { $0.y > 200 + 1e-6 && $0.x > 99 && $0.x < 101 } }, "long line clipped to the viewport frame")
        if let svg = SheetSVG.svg(doc: svgDoc, layoutIndex: 0) {
            check(svg.contains("width=\"\(fmt(420 * SheetSVG.pxPerMM, 3))\"") && svg.contains("Svg House") && svg.contains("A-WALL"), "sheet SVG: A3 at 96 dpi, title block, layers")
        } else { check(false, "sheet SVG") }
        check(SheetSVG.clipPolygon([Vec2(-5, -5), Vec2(5, -5), Vec2(5, 5), Vec2(-5, 5)], BBox2(min: .zero, max: Vec2(10, 10))).count == 4 && SheetSVG.clipSegment(Vec2(-1, 20), Vec2(11, 20), BBox2(min: .zero, max: Vec2(10, 10))) == nil, "polygon and segment clipping")

        // SHT-031 named plot styles: layer style, object override, table chosen per page setup.
        var nd = ArchiDocument()
        let nl1 = nd.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "A-WALL")
        let nl2 = nd.add(.line(LineGeom(.zero, Vec2(0, 100))), layer: "A-WALL")
        let nl3 = nd.add(.line(LineGeom(.zero, Vec2(50, 50))), layer: "0")
        NamedPlotStyles.setLayerStyle("A-WALL", "Screened 50%", &nd)
        nd.entities[nd.entityIndex(nl2)!].props[NamedPlotStyles.prop] = "Heavy"
        let smap = NamedPlotStyles.styleMap(nd)
        check(smap[nl1] == "Screened 50%" && smap[nl2] == "Heavy" && smap[nl3] == "Normal", "named styles: layer, object override, Normal")
        var nps = PageSetup(); nps.namedStyleTable = NamedPlotStyles.defaultName
        var nr = PlotRenderer(transform: .identity, devicePerMM: 1, paper: true)
        nr.apply(nps, doc: nd)
        let p1 = nr.entryPen?(nl1), p2 = nr.entryPen?(nl2)
        check(p1?.screening == 50 && p2?.lineweight == 0.7 && nr.penTable == nil, "renderer resolves pens from named styles")
        var nr2 = nr; nr2.activePen = p1
        let scol = nr2.color(RGBA(0, 0, 0))
        check(abs((scol.components?[0] ?? 0) - 0.5) < 0.01, "screened 50% plots black as mid grey")
        var nr3 = nr; nr3.activePen = p2
        check(abs(nr3.width(ArchiCore.StrokeStyle(color: RGBA(0, 0, 0), lineweight: 0.25)) - 0.7) < 1e-9, "Heavy plots 0.7 mm")
        check((try? JSONDecoder().decode(PageSetup.self, from: JSONEncoder().encode(nps)))?.namedStyleTable == NamedPlotStyles.defaultName, "page setup keeps the named table")

        // LAY-002 layer manager: on/off and plot flags reach display and plots; every column round-trips through .archi.
        var lyd = ArchiDocument()
        lyd.layers.append(Layer(name: "NOTES")); lyd.layers.append(Layer(name: "HIDDEN"))
        let nid = lyd.add(.line(LineGeom(.zero, Vec2(100, 0))), layer: "NOTES")
        let hid = lyd.add(.line(LineGeom(.zero, Vec2(0, 100))), layer: "HIDDEN")
        lyd.layers[lyd.layerIndex("HIDDEN")!].visible = false
        lyd.layers[lyd.layerIndex("NOTES")!].plot = false
        lyd.layers[lyd.layerIndex("NOTES")!].transparency = 0.5
        lyd.layers[lyd.layerIndex("NOTES")!].description = "Working notes"
        let screen = Set(DrawListBuilder.entries(doc: lyd, options: DrawOptions(level: lyd.currentLevel)).compactMap(\.id))
        var po = DrawOptions(level: lyd.currentLevel); po.forPaper = true
        let paperIDs = Set(DrawListBuilder.entries(doc: lyd, options: po).compactMap(\.id))
        check(screen.contains(nid) && !screen.contains(hid), "layer off hides its objects on screen")
        check(!paperIDs.contains(nid) && !paperIDs.contains(hid), "no-plot and off layers do not plot")
        let rtd = (try? ArchiFile.encode(lyd)).flatMap { try? ArchiFile.decode($0) }
        let rl = rtd?.layer(named: "NOTES")
        check(rl?.plot == false && rl?.transparency == 0.5 && rl?.description == "Working notes" && rtd?.layer(named: "HIDDEN")?.visible == false, "layer columns round-trip through .archi")

        // LAY-019 layer tree: groups by prefix, bulk toggles in one undo step, current layer never frozen.
        let tg = LayerTree.groups(["0", "A-WALL", "A-DOOR", "S-GRID", "HOUSE|A-WALL", "HOUSE|S-GRID", "Notes"])
        check(tg.map(\.name) == ["(Standard)", "A", "S", "HOUSE|", "Notes"] && tg[1].layers == ["A-WALL", "A-DOOR"] && tg[3].layers.count == 2, "layer groups by discipline prefix and xref")
        let ted = Editor(document: ArchiDocument())
        ted.transaction("cur") { $0.currentLayer = "A-WALL" }
        var frozenCount = 0
        ted.transaction("Layer Group A") { frozenCount = LayerTree.setAll(&$0, group: "A", \.frozen, true) }
        check(frozenCount >= 1 && ted.doc.layer(named: "A-DOOR")?.frozen == true && ted.doc.layer(named: "A-WALL")?.frozen == false, "group freeze skips the current layer")
        ted.undo()
        check(ted.doc.layer(named: "A-DOOR")?.frozen == false, "group toggle is one undo step")

        // APP-052 settings export / import through a plist (machine-specific keys stay behind).
        let suite = "archi.selftest.\(UUID().uuidString)", suite2 = suite + ".b"
        if let src = UserDefaults(suiteName: suite), let dst = UserDefaults(suiteName: suite2) {
            src.set("Graphite", forKey: "theme.canvas"); src.set(["ZOOM", "LINE"], forKey: "quickAccess"); src.set("x", forKey: "NSWindow Frame Main"); src.set("abc", forKey: "agentToken")
            let surl = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).plist")
            try? SettingsTransfer.write(to: surl, from: src, domain: suite)
            let n = (try? SettingsTransfer.read(from: surl, into: dst)) ?? -1
            check(n == 2 && dst.string(forKey: "theme.canvas") == "Graphite" && dst.stringArray(forKey: "quickAccess") == ["ZOOM", "LINE"] && dst.string(forKey: "agentToken") == nil, "settings round-trip without window frames or tokens")
            try? FileManager.default.removeItem(at: surl)
            src.removePersistentDomain(forName: suite); dst.removePersistentDomain(forName: suite2)
        } else { check(false, "settings suites") }

        // APP-001 window state and APP-020 pinch zoom about the cursor.
        let wm = AppModel()
        let oldPanels = UserDefaults.standard.object(forKey: WindowStateMemory.panelsKey), oldTab = UserDefaults.standard.string(forKey: WindowStateMemory.tabKey)
        wm.panelTab = .layers; wm.showPanels = false
        let wm2 = AppModel(); WindowStateMemory.restore(wm2)
        check(wm2.panelTab == .layers && !wm2.showPanels, "panel column state restored in new windows (tab \(wm2.panelTab), panels \(wm2.showPanels), stored \(String(describing: UserDefaults.standard.object(forKey: WindowStateMemory.panelsKey))) \(String(describing: UserDefaults.standard.string(forKey: WindowStateMemory.tabKey))))")
        UserDefaults.standard.set(oldPanels, forKey: WindowStateMemory.panelsKey); UserDefaults.standard.set(oldTab, forKey: WindowStateMemory.tabKey)
        let under = CGPoint(x: 600, y: 120), before = canvas.toWorld(under)
        canvas.zoomBy(1.37, about: under)
        check(canvas.toWorld(under).isClose(before, tol: 1e-6), "pinch / wheel zoom keeps the point under the cursor")

        // APP-012 file tab hover preview.
        let ftm = AppModel(); ftm.editor.replaceDocument(vd, url: nil)
        check(FileTabs.preview(ftm).map { $0.size.width > 10 } == true && FileTabs.summary(ftm).contains("1 building element"), "file tab preview image and summary")

        // APP-003 / APP-004 window tabs and full screen.
        let tw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let oldPref = WindowTabs.preferTabs
        UserDefaults.standard.set(true, forKey: WindowTabs.preferKey); WindowTabs.configure(tw)
        check(tw.tabbingIdentifier == "OanarinaArchiDocument" && tw.tabbingMode == .preferred && tw.collectionBehavior.contains(.fullScreenPrimary), "drawing windows tab together and go full screen")
        UserDefaults.standard.set(false, forKey: WindowTabs.preferKey); WindowTabs.configure(tw)
        check(tw.tabbingMode == .automatic, "tabs on request only when the preference is off")
        UserDefaults.standard.set(oldPref, forKey: WindowTabs.preferKey)

        // APP-055 / APP-057 / APP-058 / APP-059 help.
        check(["F1", "F3", "F7", "F8", "F9", "F10", "F11", "F12"].allSatisfy { k in FunctionKeys.table.contains { $0.key == k } } && FunctionKeys.name(99) == "F3", "function key table")
        let sp = HelpPages.shortcutsPage()
        check(FunctionKeys.table.allSatisfy { sp.contains("<code>\($0.key)</code>") }, "function keys documented in the help")
        let idx = HelpPages.index(.shared)
        check(CommandRegistry.shared.sorted.allSatisfy { idx.contains("archi-help:cmd/\($0.name)\"") }, "help index links every command")
        check(HelpPages.command("l", .shared)?.contains("<code>LINE</code>") == true && HelpPages.command("NOPE_NOT_A_CMD", .shared) == nil, "command page by alias")
        let missingTut = HelpPages.tutorials.flatMap(\.steps).map { String($0.1.split(separator: " ")[0]) }.filter { CommandRegistry.shared.lookup($0) == nil }
        check(missingTut.isEmpty, "tutorial steps run real commands: missing \(missingTut)")
        model.commandInput = "circle"
        check(HelpPages.contextRoute(model) == "cmd/CIRCLE" && HelpPages.contextRoute(nil) == "index", "F1 opens the typed command's page")
        model.commandInput = ""
        check(HelpPages.html("cmd/LINE", .shared).contains("archi-run:LINE"), "command page has a Run link")

        // APP-021 / APP-018: every ribbon and menu button has a valid SF Symbol and a tooltip text from its command.
        let allItems = CommandCatalog.curatedItems + CommandCatalog.navigationItems
        let badSymbols = Set(allItems.filter { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) == nil }.map(\.symbol)).sorted()
        check(badSymbols.isEmpty, "SF Symbols exist: invalid \(badSymbols.joined(separator: ", "))")
        check(allItems.allSatisfy { i in i.names.contains { CommandRegistry.shared.lookup($0).map { !$0.summary.isEmpty } ?? false } }, "every button has a tooltip summary")

        // SHT-002 paper sizes: ISO, ANSI, ARCH and custom sizes; a sheet plots on its paper.
        let names = PaperCatalog.builtIn.map(\.name)
        check(["A0", "A1", "A2", "A3", "A4", "ANSI A", "ANSI B", "ANSI C", "ANSI D", "ANSI E", "ARCH A", "ARCH B", "ARCH C", "ARCH D", "ARCH E", "ARCH E1"].allSatisfy(names.contains), "ISO, ANSI and ARCH paper sizes")
        var pdoc = ArchiDocument()
        check(PaperCatalog.addCustom(&pdoc, name: "Roll 914", width: 1500, height: 914) != nil && PaperCatalog.addCustom(&pdoc, name: "A3", width: 100, height: 100) == nil
              && PaperCatalog.addCustom(&pdoc, name: "Tiny", width: 10, height: 10) == nil, "custom paper sizes validated")
        check(PaperCatalog.find("roll 914", doc: pdoc)?.width == 1500 && PaperCatalog.find("ANSI D portrait")?.width == 558.8, "paper lookup incl. custom and portrait")
        pdoc.layouts = [ArchiCore.Layout(name: "Big", paper: PaperCatalog.find("ANSI D")!)]
        let purl = FileManager.default.temporaryDirectory.appendingPathComponent("archi-paper-\(UUID().uuidString).pdf")
        try? Plotter.writePDF(doc: pdoc, to: purl, layoutIndex: 0, level: nil)
        if let pg = PDFDocument(url: purl)?.page(at: 0) {
            let b = pg.bounds(for: .mediaBox)
            check(abs(b.width - 863.6 * 72 / 25.4) < 0.5 && abs(b.height - 558.8 * 72 / 25.4) < 0.5, "ANSI D sheet plots on 34 × 22 in")
        } else { check(false, "ANSI D sheet PDF") }
        try? FileManager.default.removeItem(at: purl)

        // APP-044 progress while publishing: cancelling stops after the current page and removes the partial file.
        var pubDoc = ArchiDocument(); pubDoc.layouts = [ArchiCore.Layout(name: "1"), ArchiCore.Layout(name: "2"), ArchiCore.Layout(name: "3")]
        let curl = FileManager.default.temporaryDirectory.appendingPathComponent("archi-cancel-\(UUID().uuidString).pdf")
        var calls: [Int] = []
        let cancelled: Bool
        do { try Plotter.publishPDF(doc: pubDoc, layouts: [0, 1, 2], to: curl, bookmarks: true) { k, _ in calls.append(k); return k < 1 }; cancelled = false } catch { cancelled = true }
        check(cancelled && calls == [0, 1] && !FileManager.default.fileExists(atPath: curl.path), "publish reports each page and cancels cleanly")

        // VIS-012 / 013 / 015 / 016: the 3D viewport, orbit target, standard views, stored projection.
        var d3 = ArchiDocument()
        let wall3 = d3.addElement(.wall(WallGeom(start: .zero, end: Vec2(6000, 0))))
        let m3 = AppModel(); m3.editor.replaceDocument(d3, url: nil)
        let vc = Viewport3DController()
        vc.sync(model: m3)
        check(!vc.builder.bounds.isEmpty, "3D viewport builds the model")
        vc.setView("Top", animated: false)
        let fTop = vc.cameraNode.worldFront
        check(fTop.y < -0.99, "Top view looks straight down (\(fTop))")
        vc.setView("Front", animated: false)
        check(vc.cameraNode.worldFront.z < -0.99, "Front view looks north")
        vc.setView("Right", animated: false)
        check(vc.cameraNode.worldFront.x < -0.99, "Right view looks west")
        vc.setView("Iso", animated: false)
        let fi = vc.cameraNode.worldFront
        check(fi.x > 0.3 && fi.y < -0.3 && fi.z < -0.3, "SW isometric looks down towards north-east")
        m3.editor.doc.setVariable("PERSPECTIVE", "0"); vc.sync(model: m3)
        check(vc.isOrtho && vc.cameraNode.camera?.usesOrthographicProjection == true, "PERSPECTIVE 0 → parallel projection")
        m3.editor.doc.setVariable("PERSPECTIVE", "1"); vc.sync(model: m3)
        check(!vc.isOrtho && vc.cameraNode.camera?.usesOrthographicProjection == false, "PERSPECTIVE 1 → perspective")
        check(vc.orbitSelection([wall3], frame: false), "orbit around the selected wall")

        // SHT-010: a plan dragged onto a sheet becomes a viewport at the view scale, centred on the drop point.
        var vdoc = ArchiDocument()
        _ = vdoc.add(.line(LineGeom(Vec2(0, 0), Vec2(10000, 6000))), layer: "0")
        vdoc.layouts = [ArchiCore.Layout(name: "A101")]
        let payload = ViewDrop.string(.plan, level: vdoc.currentLevel)
        check(ViewDrop.parse(payload).map { $0.0 == .plan && $0.1 == vdoc.currentLevel } == true && ViewDrop.parse("chair") == nil, "view drag payload")
        let vi = ViewDrop.place(payload, at: Vec2(200, 150), layoutIndex: 0, doc: &vdoc)
        if let vi, let v = vdoc.layouts[0].viewports.indices.contains(vi) ? vdoc.layouts[0].viewports[vi] : nil {
            check(v.scale == 100 && v.level == vdoc.currentLevel && (v.origin + v.size / 2).isClose(Vec2(200, 150), tol: 1e-9) && abs(v.size.x - 120) < 1e-9, "dropped plan: 1:100 viewport at the drop point sized to the model")
        } else { check(false, "view dropped on the sheet") }
        vdoc.setVariable("VIEWSCALE:\(vdoc.currentLevel)", "1:50")
        check(ViewDrop.viewScale(vdoc, level: vdoc.currentLevel) == 50 && ViewDrop.place("archi-view:section:", at: Vec2(100, 100), layoutIndex: 0, doc: &vdoc) != nil, "view scale per level; sections drop too")

        // PRC-019: every Shift+right-click snap override entry feeds a token the point prompt understands.
        let tokens = PlanCanvasView.snapOverrideItems.compactMap { $0.0 == nil ? nil : $0.1 }
        check(tokens.count >= 17 && tokens.allSatisfy { t in
            InputParser.snapKind(override: t) != nil || ["NON", "GCEN"].contains(t) || InputParser.pointModifiers.contains(t) || t.hasPrefix("'")
        }, "snap override menu tokens are valid point-prompt input")

        // LAY-025: PSLTSCALE keeps dash lengths constant on paper across viewport scales; 0 keeps model lengths.
        var ld = ArchiDocument()
        _ = ld.add(.line(LineGeom(.zero, Vec2(20000, 0))), layer: "S-GRID")
        func paperDash(_ ratio: Double) -> Double? {
            let vp = Viewport(origin: .zero, size: Vec2(100, 100), viewCenter: .zero, scale: ratio)
            for e in SheetComposer.viewportEntries(doc: ld, vp: vp) { for it in e.items { if case .stroke(_, _, let st) = it, let d = st.dash.first(where: { $0 > 0 }) { return d / ratio } } }
            return nil
        }
        if let a50 = paperDash(50), let a100 = paperDash(100) {
            check(abs(a50 - a100) < 1e-9, "PSLTSCALE 1: same dash length on paper at 1:50 and 1:100")
            ld.setVariable("PSLTSCALE", "0")
            if let b50 = paperDash(50), let b100 = paperDash(100) { check(abs(b50 / b100 - 2) < 1e-9, "PSLTSCALE 0: model-space dashes shrink at 1:100") }
        } else { check(false, "dashed grid line in the viewport") }

        // LAY-027: lineweight display scale changes screen widths only.
        let oldLW = LineweightDisplay.scale
        LineweightDisplay.scale = 1
        let lw1 = canvas.params.width(0.5)
        LineweightDisplay.scale = 2
        let lw2 = canvas.params.width(0.5)
        LineweightDisplay.scale = 99
        check(abs(lw2 - 2 * lw1) < 1e-9 && LineweightDisplay.scale == 5, "lineweight display scale doubles screen widths; clamped to 5")
        LineweightDisplay.scale = oldLW

        perfChecks(check)
        if headless { scriptingChecks(check) }
    }

    /// VIS-001…010: drawing a 100 000-line plan from the display cache, at extents and zoomed in, within a 60 fps frame.
    static func perfChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        d.entities.reserveCapacity(100_000)
        for i in 0..<100_000 {
            let x = Double(i % 400) * 250, y = Double(i / 400) * 250
            d.entities.append(Entity(id: i + 1, layer: "0", geometry: .line(LineGeom(Vec2(x, y), Vec2(x + 200, y + 120)))))
        }
        d.nextID = 100_001
        let t0 = Date()
        let scene = RenderScene(DrawListBuilder.entries(doc: d, options: DrawOptions(level: d.currentLevel)))
        let build = Date().timeIntervalSince(t0) * 1000
        let w = 1440, h = 900
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { check(false, "bitmap context"); return }
        func frame(_ box: CGRect) -> Double {
            let s = min(CGFloat(w) / box.width, CGFloat(h) / box.height)
            let t = CGAffineTransform(translationX: CGFloat(w) / 2, y: CGFloat(h) / 2).scaledBy(x: s, y: s).translatedBy(x: -box.midX, y: -box.midY)
            let vis = CGRect(x: 0, y: 0, width: w, height: h).applying(t.inverted())
            // Best of 7 frames: other processes on the machine must not make the check flaky.
            var best = Double.infinity
            for _ in 0..<7 {
                let start = Date()
                ctx.saveGState(); ctx.setFillColor(gray: 0.1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.concatenate(t); scene.draw(in: ctx, visible: vis, scale: s, params: RenderParams()); ctx.restoreGState()
                best = min(best, Date().timeIntervalSince(start) * 1000)
            }
            return best
        }
        let zoomed = frame(CGRect(x: scene.bounds.midX - 5000, y: scene.bounds.midY - 3000, width: 10000, height: 6000))
        check(scene.entries.count == 100_000, "100k-line display cache (built in \(Int(build)) ms)")
        check(zoomed < 1000.0 / 60, "zoomed-in frame of a 100k drawing within 16.7 ms (\(String(format: "%.1f", zoomed)) ms)")

        // The canvas itself: full frames while zooming, panning, zooming to a window and back.
        let m = AppModel()
        m.editor.replaceDocument(d, url: nil)
        let cv = PlanCanvasView(model: m)
        cv.setFrameSize(NSSize(width: w, height: h))
        cv.zoomExtents(recordHistory: false)
        func timed(_ body: () -> Void) -> Double {
            var best = Double.infinity
            for _ in 0..<5 { let st = Date(); body(); best = min(best, Date().timeIntervalSince(st) * 1000) }
            return best
        }
        // Retina-sized target, like the canvas layer on a 2× display.
        guard let rc = CGContext(data: nil, width: 2 * w, height: 2 * h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        rc.scaleBy(x: 2, y: 2)
        let full = timed { cv.drawContentForTesting(rc) }
        cv.zoomBy(1.25)
        let zoomFrame = timed { cv.zoomBy(1.01); cv.drawContentForTesting(rc) }
        let panFrame = timed { cv.panView(dx: 12, dy: -7); cv.drawContentForTesting(rc) }
        let winFrame = timed { cv.zoom(toRect: CGRect(x: 1000, y: 1000, width: 20000, height: 12000)); cv.drawContentForTesting(rc) }
        let prevFrame = timed { cv.zoomPrevious(); cv.drawContentForTesting(rc) }
        let worst = max(zoomFrame, panFrame, winFrame, prevFrame)
        check(worst < 1000.0 / 60, "100k drawing: zoom \(String(format: "%.1f", zoomFrame)), pan \(String(format: "%.1f", panFrame)), window \(String(format: "%.1f", winFrame)), previous \(String(format: "%.1f", prevFrame)) ms per frame (< 16.7)")
        check(full < 1000.0 / 60, "100k drawing: extents frame \(String(format: "%.1f", full)) ms")
    }

    /// SCR-001 (JavaScript console archi.run) and SCR-016/017 (agent HTTP server) — headless only (spins the run loop).
    static func scriptingChecks(_ check: (Bool, String) -> Void) {
        let model = AppModel()
        let engine = ScriptEngine(model: model)
        var result: ScriptResult?
        Task { @MainActor in result = await engine.evaluate("archi.run(\"LINE 0,0 100,0 \"); archi.entities().length") }
        spin(15) { result != nil }
        let lines = model.doc.entities.filter { if case .line = $0.geometry { return true }; return false }
        check(result?.error == nil && lines.count == 1, "archi.run(\"LINE 0,0 100,0 \") adds a line from the console (error: \(result?.error ?? "none"), lines \(lines.count))")
        if case .line(let l)? = lines.first?.geometry { check(l.b.isClose(Vec2(100, 0), tol: 1e-9), "console line ends at 100,0") }

        // Running the same multi-line script twice must not fail on its own top-level const/let.
        let twice = "const w = [1, 2, 3];\nlet total = w.length;\ntotal"
        var rerun1: ScriptResult?, rerun2: ScriptResult?
        Task { @MainActor in rerun1 = await engine.evaluate(twice); rerun2 = await engine.evaluate(twice) }
        spin(10) { rerun2 != nil }
        check(rerun1?.error == nil && rerun2?.error == nil && rerun2?.value == "3", "console: a script with const/let runs a second time (error: \(rerun2?.error ?? "none"), value \(rerun2?.value ?? "nil"))")

        // SCR-009: every archi member is documented, and the reference examples run.
        var keys: ScriptResult?
        Task { @MainActor in keys = await engine.evaluate("Object.keys(archi).join(',')") }
        spin(10) { keys != nil }
        let members = (keys?.value ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        let undocumented = members.filter { m in !ScriptAPIReference.entries.contains { $0.0.contains("archi.\(m)(") || $0.0.contains("/ \(m)(") } }
        check(!members.isEmpty && undocumented.isEmpty, "archi API fully documented: missing \(undocumented) of \(members.count)")
        check(HelpPages.scriptingPage().contains("archi.wall(x1, y1, x2, y2, opts)"), "API reference in the help browser")
        let exModel = AppModel()
        let exEngine = ScriptEngine(model: exModel)
        var failures: [String] = []
        for (sig, _, ex) in ScriptAPIReference.entries where !ex.contains("graph") && !sig.contains("panel") && !sig.contains("registerCommand") && !sig.hasPrefix("console") {
            var r: ScriptResult?
            Task { @MainActor in r = await exEngine.evaluate(ex) }
            spin(10) { r != nil }
            if let e = r?.error { failures.append("\(sig): \(e)") } else if r == nil { failures.append("\(sig): timeout") }
        }
        check(failures.isEmpty, "reference examples run: \(failures.joined(separator: "; "))")

        // SHT-003 / SHT-001: MVIEW places a rectangular 1:100 viewport on the sheet from the command line.
        let mv = AppModel()
        mv.editor.transaction("t") { d in _ = d.add(.line(LineGeom(.zero, Vec2(10000, 0))), layer: "0"); d.layouts = [ArchiCore.Layout(name: "A101")]; d.setVariable("CTAB", "A101") }
        var mvDone = false
        Task { @MainActor in _ = await mv.editor.run("MVIEW 20,20 220,170 1:100 Plan Ground"); mvDone = true }
        spin(10) { mvDone }
        if let v = mv.doc.layouts.first?.viewports.first {
            check(v.origin == Vec2(20, 20) && v.size == Vec2(200, 150) && v.scale == 100, "MVIEW places a 200 × 150 mm viewport at 1:100")
        } else { check(false, "MVIEW viewport") }

        guard !AgentServer.shared.isRunning else { return }
        let port: UInt16 = 47893
        do { try AgentServer.shared.start(model: model, port: port) } catch { check(false, "agent server starts: \(error)"); return }
        defer { AgentServer.shared.stop() }
        func rpc(_ method: String, _ params: [String: Any]) -> [String: Any]? {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/rpc")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(AgentServer.shared.token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
            var out: [String: Any]?, done = false
            URLSession.shared.dataTask(with: req) { data, _, _ in
                out = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async { done = true }
            }.resume()
            spin(10) { done }
            return out
        }
        spin(0.3) { false }
        let before = model.doc.entities.count
        let r1 = rpc("run_command", ["command": "CIRCLE 500,500 250"])
        check(r1?["result"] != nil && model.doc.entities.count == before + 1, "run_command via HTTP adds geometry (SCR-016)")
        let r2 = rpc("list_entities", [:])
        check(((r2?["result"] as? [Any])?.count ?? -1) == model.doc.entities.count, "list_entities returns every entity")
        let r3 = rpc("add_entity", ["entity": ["type": "line", "a": [0, 0], "b": [0, 900]]])
        check(((r3?["result"] as? [String: Any])?["ids"] as? [Any])?.count == 1, "add_entity returns the new id")
        let r4 = rpc("get_document_summary", [:])
        check(r4?["result"] is [String: Any], "get_document_summary")
        let r5 = rpc("undo", [:])
        check(r5?["result"] != nil && model.doc.entities.count == before + 1, "undo via the agent API")
        let r6 = rpc("no_such_method", [:])
        check(((r6?["error"] as? [String: Any])?["code"] as? Int) != nil, "unknown methods return a JSON-RPC error")
        let methods = (rpc("list_methods", [:])?["result"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        check(["run_command", "get_document", "list_entities", "add_entity", "update_entity", "delete", "add_element", "export", "screenshot"].allSatisfy(methods.contains), "agent API lists every documented method (SCR-017)")
        let res = rpc("list_resources", [:])?["result"] as? [[String: Any]] ?? []
        check(!res.isEmpty && res.contains { $0["uri"] as? String == "archi://document/summary" }, "agent server lists document resources")
        let rr = rpc("read_resource", ["uri": "archi://document/summary"])?["result"] as? [String: Any]
        check((rr?["text"] as? String)?.isEmpty == false, "agent server reads a resource")
        let tl = (rpc("list_tools", [:])?["result"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        check(tl.contains("level_areas"), "agent server lists the shared tools")
        let la = rpc("call_tool", ["name": "level_areas", "arguments": [String: Any]()])
        check(la?["result"] != nil, "agent server calls a tool (level_areas)")
        check(rpc("list_prompts", [:])?["result"] is [Any], "agent server lists prompts")
    }
}

/// One-shot JSON HTTP server on 127.0.0.1 for self-tests (a stand-in for a local model server, SCR-035).
final class MockHTTPServer {
    var replies: [String] = []
    var requests: [[String: Any]] = []
    let listener: NWListener
    init?() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { return nil }
        listener = l
        l.newConnectionHandler = { [weak self] c in c.start(queue: .main); self?.read(c, Data()) }
        l.start(queue: .main)
    }
    var port: UInt16? { listener.port?.rawValue }
    func read(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, _ in
            guard let self else { return }
            var b = buf; if let data { b.append(data) }
            if let r = b.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: b[..<r.lowerBound], as: UTF8.self).lowercased()
                let len = head.components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
                if b.count - r.upperBound >= len {
                    if let j = try? JSONSerialization.jsonObject(with: b[r.upperBound...]) as? [String: Any] { self.requests.append(j) }
                    let body = self.replies.isEmpty ? #"{"error":{"message":"no reply"}}"# : self.replies.removeFirst()
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                    c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
                    return
                }
            }
            if done { c.cancel() } else { self.read(c, b) }
        }
    }
}
