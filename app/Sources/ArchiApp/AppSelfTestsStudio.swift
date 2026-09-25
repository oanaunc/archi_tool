// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import AppKit
import SwiftUI
import SceneKit
import ArchiCore

/// Self-test checks of the family editor, 3D Z move, levels in 3D, placement rotation, undo grouping, script hooks and
/// panels, image exports and the selection/notification/navigator panels. Panels are opened off screen, filled and
/// closed programmatically.
@MainActor
extension AppSelfTests {
    static func studioChecks(_ check: (Bool, String) -> Void) {
        // App command names never shadow core commands.
        let core = CommandRegistry(); core.ensureBuiltins()
        let clashes = AppCommandsStudio.all.flatMap { [$0.name] + $0.aliases }.filter { core.lookup($0) != nil }
        check(clashes.isEmpty, "studio commands do not shadow core commands: \(clashes.joined(separator: ", "))")

        // Z move: walls, slabs, openings and solids; stairs are skipped; one undo step.
        var zd = ArchiDocument()
        let w = zd.addElement(.wall(WallGeom(start: .zero, end: Vec2(4000, 0))), name: "W")
        let sl = zd.addElement(.slab(SlabGeom(boundary: [.zero, Vec2(1000, 0), Vec2(1000, 1000), Vec2(0, 1000)])), name: "S")
        let st = zd.addElement(.stair(StairGeom(start: .zero, direction: 0, width: 1000, totalRise: 3000, riserCount: 17, treadDepth: 280, kind: .straight)), name: "St")
        let bx = zd.add(.solid(SolidGeom(kind: .box, origin: Vec3(0, 0, 0), size: Vec3(100, 100, 100))), layer: "0")
        let zed = Editor(document: zd)
        let r = ZMove.apply(zed, ids: [w, sl, st, bx], dz: 500)
        check(r.moved == 3 && r.skipped == 1, "Z move moves 3 objects and skips the stair (got \(r.moved)/\(r.skipped))")
        if case .wall(let g)? = zed.doc.element(w)?.geometry, case .slab(let s)? = zed.doc.element(sl)?.geometry, case .solid(let so)? = zed.doc.entity(bx)?.geometry {
            let zmin = SolidOps.translated(so, by: .zero).origin.z
            check(abs(g.baseOffset - 500) < 1e-9 && abs(s.topOffset - 500) < 1e-9 && abs(zmin - 500) < 1e-9, "Z move offsets wall base, slab top and solid origin")
        } else { check(false, "Z moved geometry") }
        zed.undo()
        if case .wall(let g)? = zed.doc.element(w)?.geometry { check(abs(g.baseOffset) < 1e-9, "Z move is one undo step") }
        check(GizmoMath.axisName(3) == "Z" && abs(GizmoMath.axisDelta(drag: CGVector(dx: 0, dy: 30), axisScreen: CGVector(dx: 0, dy: 0.06)) - 500) < 1e-9, "gizmo Z arrow drag → 500 mm")

        check(abs(GizmoMath.scaleFactor(center: .zero, from: CGPoint(x: 10, y: 0), to: CGPoint(x: 0, y: 25)) - 2.5) < 1e-12
              && abs(GizmoMath.scaleFactor(center: .zero, from: CGPoint(x: 10, y: 0), to: CGPoint(x: 13, y: 0), step: 0.5) - 1.5) < 1e-12
              && GizmoMath.scaleFactor(center: .zero, from: CGPoint(x: 10, y: 0), to: .zero) == 0.01, "gizmo scale factor, snapping and limit")
        let sg = Editor(document: zd)
        if GizmoMath.apply(sg, ids: [bx], .scale(2, 2, around: .zero), label: "Scale") == 1, case .solid(let so)? = sg.doc.entity(bx)?.geometry {
            check(abs(so.size.x - 200) < 1e-6 || abs(SolidOps.volume(vertices: MeshTools.mesh(of: so).positions, triangles: MeshTools.mesh(of: so).indices.map(Int.init)) - 4_000_000) < 1, "gizmo scale doubles the solid in plan")
        } else { check(false, "gizmo scale applied") }
        // Levels in 3D.
        let lv = [Level(id: 1, name: "First", elevation: 3000), Level(id: 0, name: "Ground", elevation: 0), Level(id: 2, name: "Roof", elevation: 6000)]
        check(LevelView3D.offsets(lv, gap: 2000) == [0: 0, 1: 2000, 2: 4000], "explode offsets by level order")
        check(LevelView3D.visible(level: 1, isolate: 1) && !LevelView3D.visible(level: 0, isolate: 1) && LevelView3D.visible(level: nil, isolate: 1) && LevelView3D.visible(level: 0, isolate: nil), "isolate level visibility")
        check(abs(FieldOfView.focalLength(fov: FieldOfView.fov(focalLength: 35)) - 35) < 1e-6 && FieldOfView.clamp(500) == 120, "field of view ↔ focal length")

        // Click-to-place rotation (Space) and grip-drag quarter turns.
        check(Placement.degrees(-1) == 270 && abs(Placement.angle(5) - .pi / 2) < 1e-12, "placement quarter turns wrap")
        var pd = ArchiDocument()
        pd.blocks["Chair"] = Block(name: "Chair", basePoint: .zero, entities: [Entity(layer: "0", geometry: .line(LineGeom(.zero, Vec2(500, 0))))])
        if case .geometry(.insert(let ig))? = Placement.preview(ToolDrop.blockPrefix + "Chair", at: Vec2(10, 20), turns: 1, doc: pd) {
            check(abs(ig.rotation - .pi / 2) < 1e-12 && ig.position == Vec2(10, 20), "block placement preview rotated 90°")
        } else { check(false, "block placement preview") }
        let pm = AppModel(document: pd)
        let fam = ComponentLibrary.families[0]
        check(ToolDrop.drop(ToolDrop.componentPrefix + fam.id, at: Vec2(1000, 0), onto: nil, model: pm, rotation: Placement.angle(3)), "component placed with rotation")
        if case .component(let cg)? = pm.doc.elements.last?.geometry { check(abs(cg.rotation - 3 * .pi / 2) < 1e-12, "placed component keeps 270°") } else { check(false, "placed component") }
        pm.editor.undo()
        check(pm.doc.elements.isEmpty, "placement is one undo step")
        let turned = GripEditor.moved(.line(LineGeom(.zero, Vec2(1000, 0))), grip: 1, from: Vec2(500, 0), to: Vec2(500, 0), turns: 1)
        if case .line(let l) = turned { check(l.a.isClose(Vec2(500, -500), tol: 1e-9) && l.b.isClose(Vec2(500, 500), tol: 1e-9), "Space while dragging rotates 90° about the grip") } else { check(false, "grip turn") }

        // Undo grouping (plug-in commands are one step).
        let ud = Editor(document: ArchiDocument())
        let before = ud.history.undoStack.count
        let step = UndoStep.begin(ud)
        ud.transaction("a") { _ = $0.add(.line(LineGeom(.zero, Vec2(1, 0))), layer: "0") }
        ud.transaction("b") { _ = $0.add(.line(LineGeom(.zero, Vec2(0, 1))), layer: "0") }
        check(step.end(ud, label: "PLUGINCMD") && ud.history.undoStack.count == before + 1 && ud.history.undoLabel == "PLUGINCMD", "plug-in edits collapse into one undo step")
        ud.undo()
        check(ud.doc.entities.isEmpty, "undoing the plug-in step removes all its edits")
        check(!UndoStep.begin(ud).end(ud, label: "x"), "no change → no undo step")

        // Family editor model.
        var fd = ArchiDocument()
        let fe = FamilyEditorModel()
        fe.newFamily(.furniture, in: fd)
        check(fe.draft?.name == "Furniture" && fe.isDirty(fd), "new furniture family draft")
        fe.renameParameter(0, to: "W")
        check(fe.draft?.forms[0].dims["width"] == "W" && fe.draft?.forms[0].x == "-W/2" && fe.draft?.types["1600 x 900"]?["W"] == "1600", "renaming a parameter updates forms and types")
        check(FamilyEditorModel.replaceIdentifier("Width", with: "W", in: "Width/2 + widthX + max(width,1)") == "W/2 + widthX + max(W,1)", "identifier replacement is whole-word")
        check(FamilyEditorModel.parsePoints("max(a,b), 0; 1,2", dims: 2) == [["max(a,b)", "0"], ["1", "2"]] && FamilyEditorModel.parsePoints("1,2,3", dims: 2) == nil, "point lists respect parentheses")
        fe.previewType = "1600 x 900"
        let b0 = fe.evaluate(fd)?.bounds ?? .empty
        check(!b0.isEmpty && abs(b0.max.x - b0.min.x - 1600) < 1e-6 && abs(b0.max.y - b0.min.y - 900) < 1e-6 && abs(b0.max.z - b0.min.z - 750) < 1e-6, "family evaluates to 1600 × 900 × 750")
        fe.addType("Small"); fe.setTypeValue("Small", "W", "800")
        check(fe.previewType == "Small" && abs((fe.evaluate(fd)?.bounds.size.x ?? 0) - 800) < 1e-6, "types table value flexes the preview")
        fe.flex["Height"] = "1000"
        check(abs((fe.evaluate(fd)?.bounds.size.z ?? 0) - 1000) < 1e-6, "flex value changes the preview height")
        fe.flex = [:]
        fe.addParameter(); fe.addForm(.cylinder); fe.addPlane(axis: "x")
        check(fe.draft?.parameters.last?.name == "Param" && fe.draft?.forms.last?.dims["radius"] != nil && fe.draft?.referencePlanes.count == 1 && fe.selectedForm == (fe.draft?.forms.count ?? 0) - 1, "add parameter, cylinder form and reference plane")
        fe.removeForm(fe.selectedForm ?? 0); fe.removeParameter((fe.draft?.parameters.count ?? 1) - 1)
        check(fe.problems(fd).isEmpty, "furniture family has no problems (\(fe.problems(fd).joined(separator: "; ")))")
        let groups = fe.previewGroups(fd)
        check(!groups.isEmpty && groups.allSatisfy { $0.mesh.triangleCount > 0 }, "preview meshes built by the mesh builder")
        check(!FamilyPreviewProjection.faces(groups, doc: fd, yaw: 0.3, pitch: 0.6, size: CGSize(width: 200, height: 150)).isEmpty, "preview projection has faces")
        let fed = Editor(document: fd)
        let undo0 = fed.history.undoStack.count
        check(fe.apply(fed) && fed.doc.family(named: "Furniture") != nil && fed.history.undoStack.count == undo0 + 1, "apply adds the family as one undo step")
        fd = fed.doc
        fed.transaction("place") { d in _ = d.addElement(.component(ComponentGeom(category: "Furniture", position: .zero, size: Vec3(1, 1, 1), family: "Furniture")), name: "T"); FamilyInstances.updateAll(&d) }
        fe.setTypeValue("Small", "W", "900")
        fe.draft?.parameters[0].value = "2000"
        fe.draft?.name = "Table"
        check(fe.apply(fed) && fed.doc.family(named: "Table") != nil && fed.doc.family(named: "Furniture") == nil, "apply renames the family")
        if case .component(let cg)? = fed.doc.elements.last?.geometry { check(cg.family == "Table" && abs(cg.size.x - 2000) < 1e-6, "instances follow the rename and the new width (got \(cg.size.x))") } else { check(false, "family instance") }
        check(!fe.deleteFamily(fed) && fed.doc.family(named: "Table") != nil, "a family with instances is not deleted")
        fe.draft?.name = ""
        check(!fe.apply(fed), "empty family name refused")

        // Family editor window: open off screen, populate, close.
        let wm = AppModel(document: fed.doc)
        FamilyEditorWindow.show(model: wm, family: "Table", present: false)
        check(FamilyEditorWindow.isOpen && FamilyEditorWindow.editor.originalName == "Table", "family editor panel opens on the family")
        FamilyEditorWindow.editor.addType("Large"); FamilyEditorWindow.editor.setTypeValue("Large", "W", "2400")
        FamilyEditorWindow.show(model: wm, present: false)
        check(FamilyEditorWindow.editor.apply(wm.editor) && wm.doc.family(named: "Table")?.types["Large"]?["W"] == "2400", "panel edits applied to the drawing")
        FamilyEditorWindow.close()
        check(!FamilyEditorWindow.isOpen, "family editor panel closes")
        let pv = ImageRenderer(content: FamilyPreviewView(groups: FamilyEditorWindow.editor.previewGroups(wm.doc), doc: wm.doc).frame(width: 120, height: 90))
        if let cg = pv.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]), let rep = NSBitmapImageRep(data: data) {
            var lit = 0
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) { for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { if let c = rep.colorAt(x: x, y: y), c.brightnessComponent > 0.25 { lit += 1 } } }
            check(lit > 20, "family preview draws the model (\(lit) lit samples)")
        } else { check(false, "family preview renders") }

        // Selection info, notifications, navigator, what's new.
        var sd = ArchiDocument()
        let a1 = sd.add(.line(LineGeom(.zero, Vec2(1000, 0))), layer: "0"), a2 = sd.add(.line(LineGeom(.zero, Vec2(0, 500))), layer: "0")
        let c1 = sd.add(.circle(CircleGeom(.zero, 100)), layer: "0")
        let bad = sd.add(.insert(InsertGeom(block: "Missing", position: .zero)), layer: "0")
        let sum = SelectionInfo.summarize(sd, [a1, a2, c1])
        check(sum.total == 3 && sum.rows.first?.type == "line" && sum.rows.first?.count == 2 && abs(sum.length - (1500 + 2 * .pi * 100)) < 1e-6, "selection info counts and total length")
        let notes = ModelNotifications.items(sd)
        check(notes.contains { $0.code == "BLOCK-MISSING" && $0.ids == [bad] }, "notifications list the missing block")
        let sm = AppModel(document: sd)
        if let it = notes.first(where: { $0.code == "BLOCK-MISSING" }) { NotificationsPanel.zoom(sm, it); check(sm.editor.selection == [bad], "clicking a notification selects the object") }
        StudioWindows.show("selinfo-test", title: "t", size: NSSize(width: 300, height: 200), present: false) { SelectionInfoPanel(model: sm) }
        StudioWindows.show("notify-test", title: "t", size: NSSize(width: 300, height: 200), present: false) { NotificationsPanel(model: sm) }
        StudioWindows.show("nav-test", title: "t", size: NSSize(width: 300, height: 200), present: false) { NavigatorPanel(model: sm) }
        check(StudioWindows.isOpen("selinfo-test") && StudioWindows.isOpen("notify-test") && StudioWindows.isOpen("nav-test"), "selection, notification and navigator panels open")
        for k in ["selinfo-test", "notify-test", "nav-test"] { StudioWindows.close(k) }
        check(!StudioWindows.isOpen("nav-test"), "panels close")
        let f = NavigatorMap.fit(BBox2(min: Vec2(-1000, 0), max: Vec2(9000, 5000)), in: CGSize(width: 216, height: 116))
        let q = NavigatorMap.toMap(Vec2(4000, 2500), f, height: 116)
        check(abs(q.x - 108) < 1e-6 && abs(q.y - 58) < 1e-6 && NavigatorMap.toWorld(q, f, height: 116).isClose(Vec2(4000, 2500), tol: 1e-6), "navigator map round trip")
        check(!WhatsNew.shouldShow(current: "1.2", lastSeen: nil) && WhatsNew.shouldShow(current: "1.2", lastSeen: "1.1") && !WhatsNew.shouldShow(current: "1.2", lastSeen: "1.2"), "what's new after updates only")

        // Sheet raster export.
        var ld = ArchiDocument()
        ld.layouts = [ArchiCore.Layout(name: "A101")]
        ld.layouts[0].entities = [Entity(layer: "0", geometry: .line(LineGeom(Vec2(10, 10), Vec2(200, 150))))]
        let paper = ld.layouts[0].paper
        if let i72 = SheetImageExport.image(doc: ld, layoutIndex: 0, dpi: 72), let i144 = SheetImageExport.image(doc: ld, layoutIndex: 0, dpi: 144),
           let png = ImageExport.data(i144, format: .png), let px = ImageExport.pixelSize(png), let jpg = ImageExport.data(i72, format: .jpeg) {
            check(abs(Double(i72.size.width) - paper.width / 25.4 * 72) < 1.01 && px.0 == Int(i144.size.width) && abs(Double(px.0) - 2 * Double(i72.size.width)) < 2.01, "sheet image size follows the dpi (\(px.0)×\(px.1))")
            check(jpg.count > 100 && ImageExport.Format.from("x.TIF") == .tiff, "sheet image encodes as JPEG")
            if let rep = NSBitmapImageRep(data: png) {
                var dark = 0
                for x in 0..<rep.pixelsWide where x % 3 == 0 { for y in 0..<rep.pixelsHigh where y % 3 == 0 { if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { dark += 1 } } }
                check(dark > 10, "sheet image contains the drawn line")
            }
        } else { check(false, "sheet image export") }
        check(SheetImageExport.image(doc: ld, layoutIndex: 3, dpi: 72) == nil, "missing sheet is refused")
        var md = ArchiDocument(); _ = md.add(.line(LineGeom(.zero, Vec2(10000, 5000))), layer: "0")
        if let a = SheetImageExport.modelImage(doc: md, level: md.currentLevel, dpi: 72), let b = SheetImageExport.modelImage(doc: md, level: md.currentLevel, dpi: 144) {
            check(a.size.width > 100 && abs(b.size.width - 2 * a.size.width) <= 2, "model view image follows the dpi (\(Int(a.size.width)) → \(Int(b.size.width)))")
        } else { check(false, "model view image") }

        // 3D viewport image with a transparent background.
        var vd = ArchiDocument()
        _ = vd.add(.solid(SolidGeom(kind: .box, origin: Vec3(-500, -500, 0), size: Vec3(1000, 1000, 1000))), layer: "0")
        let vc = Viewport3DController()
        vc.builder.update(doc: vd, style: "Shaded")
        vc.cameraNode.position = SCNVector3(3, 3, 3); vc.cameraNode.look(at: SCNVector3(0, 0.5, 0))
        vc.fieldOfView = 40
        if let img = vc.viewportImage(width: 64, height: 48, transparent: true), let data = ImageExport.data(img, format: .png), let rep = NSBitmapImageRep(data: data) {
            let corner = rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, mid = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.alphaComponent ?? 0
            check(rep.pixelsWide == 64 && corner < 0.05 && mid > 0.9, "viewport image: transparent background, opaque model (corner \(corner), centre \(mid))")
        } else { check(false, "viewport image renders") }
        check(abs(vc.fieldOfView - 40) < 1e-9, "field of view set on the camera")

        // Script panels and event hooks.
        let spec = try? ScriptPanelSpec.parse(["title": "Stairs", "items": [["type": "number", "name": "rise", "label": "Rise", "value": 175, "max": 190],
                                                                            ["type": "toggle", "name": "landing", "value": true],
                                                                            ["type": "button", "label": "Build", "call": "build"]]])
        check(spec?.items.count == 3 && (ScriptPanelSpec.values(spec?.items ?? [], ["rise": "250"])["rise"] as? Double) == 190
              && (ScriptPanelSpec.values(spec?.items ?? [], [:])["landing"] as? Bool) == true, "script panel spec parses and clamps values")
        check((try? ScriptPanelSpec.parse(["items": [["type": "button", "label": "x"]]])) == nil, "a button without call or command is refused")
        let hm = AppModel(document: ArchiDocument())
        let eng = ScriptEngine.forModel(hm)
        if let spec { let ps = ScriptPanels.show(spec, model: hm, present: false); check(ps.spec.title == "Stairs" && StudioWindows.isOpen("script:Stairs"), "script panel opens"); StudioWindows.close("script:Stairs") }
        check(eng.evaluateNow("var got = -1, added = 0; archi.on('selectionChanged', function(ids){ got = ids.length; }); archi.on('elementAdded', function(ids){ added += ids.length; })") != nil, "hooks register")
        check(eng.evaluateNow("archi.on('nope', function(){})") == nil, "unknown hook event is an error")
        eng.checkEvents()
        var nid: EntityID = 0
        hm.editor.transaction("add") { nid = $0.add(.line(LineGeom(.zero, Vec2(10, 0))), layer: "0") }
        hm.editor.selection = [nid]
        eng.checkEvents()
        check(eng.evaluateNow("got + ',' + added") == "1,1", "selectionChanged and elementAdded hooks fire (got \(eng.evaluateNow("got + ',' + added") ?? "nil"))")
        _ = eng.evaluateNow("archi.off()")
        // SCR-006: archi.registerCommand exists in the app engine; argument errors are thrown before any main-thread hop.
        check(eng.evaluateNow("typeof archi.registerCommand") == "function", "archi.registerCommand is available in the app script engine")
        check(eng.evaluateNow("archi.registerCommand('', 'f')") == nil, "registerCommand without a name is an error")
        check(("function f(){}" + AppPlugins.callMarker + "\nf();").components(separatedBy: AppPlugins.callMarker).first == "function f(){}", "plug-in call marker strips the appended call")
    }
}
