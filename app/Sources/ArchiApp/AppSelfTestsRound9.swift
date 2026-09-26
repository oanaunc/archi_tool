// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import PDFKit
import ArchiCore

/// APPSELFTEST checks for round 9: navigation, lights, output, assistant, marking menu, windows, layer notification.
extension AppSelfTests {
    static func round9Checks(_ check: (Bool, String) -> Void) {
        func close(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }
        func run(_ m: AppModel, _ line: String) {
            var done = false
            Task { @MainActor in _ = await m.editor.run(line); done = true }
            spin(10) { done }
        }

        // Commands: registered, in a menu, not shadowing core commands.
        let core = CommandRegistry(); core.ensureBuiltins()
        let clashes = AppCommandsRound9.all.flatMap { [$0.name] + $0.aliases }.filter { core.lookup($0) != nil }
        check(clashes.isEmpty, "round 9 commands do not shadow core commands: \(clashes.joined(separator: ", "))")
        for d in AppCommandsRound9.all { check(CommandCatalog.appRound9.contains { $0.names.contains(d.name) }, "\(d.name) has a menu entry") }

        // APP-002: two documents are independent (edits and undo).
        let m1 = AppModel(), m2 = AppModel()
        run(m1, "LINE 0,0 1000,0 ")
        check(m1.doc.entities.count == 1 && m2.doc.entities.isEmpty, "an edit in one document does not affect another")
        m2.editor.undo()
        check(m1.doc.entities.count == 1, "undo in another document leaves this one unchanged")
        m1.editor.undo()
        check(m1.doc.entities.isEmpty, "undo is per document")
        let tiles = WindowArrangement.frames(count: 2, in: CGRect(x: 0, y: 0, width: 1600, height: 1000), mode: .vertical)
        check(tiles.count == 2 && tiles[0].maxX == tiles[1].minX && tiles[1].maxX == 1600 && tiles[0].height == 1000, "two windows tiled side by side")
        let rows = WindowArrangement.frames(count: 3, in: CGRect(x: 0, y: 0, width: 1600, height: 900), mode: .horizontal)
        check(rows.count == 3 && close(rows[0].minY, 600, 1e-9) && close(rows[2].minY, 0, 1e-9), "windows stacked top to bottom")

        // APP-022: marking menu sectors and context items.
        check(RadialMenu.sector(dx: 0, dy: 40) == 0 && RadialMenu.sector(dx: 40, dy: 0) == 2 && RadialMenu.sector(dx: 0, dy: -40) == 4 && RadialMenu.sector(dx: -40, dy: 0) == 6
              && RadialMenu.sector(dx: 30, dy: 30) == 1 && RadialMenu.sector(dx: 3, dy: 3) == nil, "marking menu sectors N/NE/E/S/W and dead zone")
        for c in [RadialMenu.Context.drafting, .objects, .building] {
            let items = RadialMenu.items(c)
            check(items.count == 8 && items.allSatisfy { CommandRegistry.shared.lookup($0.command) != nil && NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil } && Set(items.map(\.command)).count == 8,
                  "\(c.rawValue) marking menu: 8 distinct commands with icons")
            check(items.allSatisfy { RadialMenu.tooltip($0).contains("—") }, "\(c.rawValue) marking menu tooltips")
        }
        var rd = ArchiDocument()
        let rl = rd.add(.line(LineGeom(.zero, Vec2(10, 0))))
        let rw = rd.addElement(.wall(WallGeom(start: .zero, end: Vec2(1000, 0))))
        check(RadialMenu.context(rd, selection: []) == .drafting && RadialMenu.context(rd, selection: [rl]) == .objects && RadialMenu.context(rd, selection: [rw]) == .building, "marking menu context")

        // VIS-049: NOAA solar position (NREL SPA reference: 2003-10-17 12:30:30 −7 h, 39.742476 N, 105.1786 W → az 194.340°, el 39.888°).
        let sun = SunPosition.compute(dayOfYear: 290, localHour: 12 + 30.5 / 60, latitude: 39.742476, longitude: -105.1786, utcOffsetHours: -7, year: 2003)
        check(close(sun.azimuth * 180 / .pi, 194.34, 0.5) && close(sun.altitude * 180 / .pi, 39.888, 0.5), "sun azimuth \(fmt(sun.azimuth * 180 / .pi, 3))° / altitude \(fmt(sun.altitude * 180 / .pi, 3))° match the reference within 0.5°")

        // VIS-017 walk: collisions with walls, gravity onto the floor.
        var wd = ArchiDocument()
        _ = wd.addElement(.slab(SlabGeom(boundary: [Vec2(-5000, -5000), Vec2(10000, -5000), Vec2(10000, 10000), Vec2(-5000, 10000)])))
        _ = wd.addElement(.wall(WallGeom(start: Vec2(-5000, 3000), end: Vec2(10000, 3000))))
        let wc = Viewport3DController()
        wc.builder.update(doc: wd, style: "Shaded")
        var fall: CGFloat = 0
        var eye = SCNVector3(1, 5, 0)
        for _ in 0..<80 { eye = WalkPhysics.step(eye: eye, move: SCNVector3(0, 0, 0), fallSpeed: &fall, dt: 0.05, ray: wc.collisionRay) }
        check(close(Double(eye.y), 1.6, 0.02), "walk: gravity lands the eye 1.6 m above the slab (eye \(fmt(Double(eye.y), 3)))")
        for _ in 0..<40 { eye = WalkPhysics.step(eye: eye, move: SCNVector3(0, 0, -0.2), fallSpeed: &fall, dt: 0.05, ray: wc.collisionRay) }
        check(eye.z < -2.0 && eye.z > -2.9, "walk: the wall stops the walker in front of it (z \(fmt(Double(eye.z), 3)))")
        let slid = WalkPhysics.step(eye: eye, move: SCNVector3(0.2, 0, -0.2), fallSpeed: &fall, dt: 0.05, ray: wc.collisionRay)
        check(slid.x > eye.x + 0.15 && close(Double(slid.z), Double(eye.z), 1e-6), "walk: diagonal move slides along the wall")
        var stepDoc = wd
        _ = stepDoc.addElement(.slab(SlabGeom(boundary: [Vec2(4000, -3000), Vec2(6000, -3000), Vec2(6000, -1000), Vec2(4000, -1000)], thickness: 200, topOffset: 200)))
        let sc = Viewport3DController(); sc.builder.update(doc: stepDoc, style: "Shaded")
        var se = SCNVector3(3.5, 1.6, 2.0); var sf: CGFloat = 0
        for _ in 0..<20 { se = WalkPhysics.step(eye: se, move: SCNVector3(0.1, 0, 0), fallSpeed: &sf, dt: 0.05, ray: sc.collisionRay) }
        check(se.x > 4.5 && close(Double(se.y), 1.8, 0.02), "walk: steps up a 200 mm platform (eye \(fmt(Double(se.y), 3)))")

        // VIS-018 fly and VIS-020 look around with a live SceneKit view.
        let nm = AppModel(); nm.editor.replaceDocument(wd, url: nil)
        let nc = Viewport3DController()
        let nv = ArchiSCNView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        nc.attach(nv); nc.sync(model: nm)
        nc.cameraNode.position = SCNVector3(0, 1.6, 0); nc.cameraNode.eulerAngles = SCNVector3(0.5, 0, 0)
        nc.startNavigation(.fly)
        nv.pressedKeys = ["w"]
        nc.lastTick = Date().addingTimeInterval(-0.1); nc.walkStep()
        check(nc.isWalking && nc.navMode == .fly && nc.cameraNode.position.y > 1.65 && nc.cameraNode.position.z < -0.05, "fly: W moves along the view direction, climbing (y \(fmt(Double(nc.cameraNode.position.y), 3)))")
        nc.startNavigation(.look)
        let lp = nc.cameraNode.position
        nc.lastTick = Date().addingTimeInterval(-0.1); nc.walkStep()
        check(nc.navMode == .look && Viewport3DController.length(Viewport3DController.sub(nc.cameraNode.position, lp)) < 1e-6, "look around: movement keys do not move the eye")
        nc.look(dx: 100, dy: 0)
        check(Viewport3DController.length(Viewport3DController.sub(nc.cameraNode.position, lp)) < 1e-6, "look around: dragging turns the head in place")
        nv.pressedKeys = []
        if nc.isWalking { nc.toggleWalk() }
        nc.positionCamera(eye: Vec2(1000, 2000), target: Vec2(5000, 2000), eyeHeight: 1600, levelElevation: 0)
        let pw = Scene3DBuilder.world(Vec3(1000, 2000, 1600))
        check(Viewport3DController.length(Viewport3DController.sub(nc.cameraNode.position, pw)) < 1e-6 && nc.cameraNode.worldFront.x > 0.99, "position camera: eye at 1.6 m looking east")

        // VIS-023 two-point perspective.
        nc.apply(camera: Camera(eye: Vec3(-8000, -8000, 9000), target: Vec3(0, 0, 0), fov: 45), animated: false)
        let size = CGSize(width: 1600, height: 1000)
        let tgtW = Scene3DBuilder.world(Vec3(0, 0, 0))
        nc.setTwoPoint(true, viewport: size)
        check(abs(nc.cameraNode.worldFront.y) < 1e-6 && nc.twoPointShift != nil, "two-point: the camera is level")
        if let a = nc.ndc(SCNVector3(2, 0, -1), size: size), let b = nc.ndc(SCNVector3(2, 6, -1), size: size), let t = nc.ndc(tgtW, size: size) {
            check(close(Double(a.x), Double(b.x), 1e-5), "two-point: vertical lines stay vertical (\(a.x) vs \(b.x))")
            check(close(Double(t.y), 0, 1e-3) && close(Double(t.x), 0, 1e-3), "two-point: the target stays centred (lens shift)")
        } else { check(false, "two-point projection") }
        nc.setTwoPoint(false)
        check(nc.twoPointShift == nil, "two-point off")

        // VIS-019 steering wheel.
        let s0 = SteeringWheel.size
        check(SteeringWheel.wedge(at: CGPoint(x: s0 / 2, y: s0 / 2)) == nil && SteeringWheel.wedge(at: CGPoint(x: s0 / 2, y: 5)) == .zoom
              && SteeringWheel.wedge(at: CGPoint(x: s0 / 2, y: s0 / 2 - SteeringWheel.innerRadius - 3)) == .center && SteeringWheel.wedge(at: CGPoint(x: s0 - 5, y: s0 / 2)) == .pan
              && SteeringWheel.wedge(at: CGPoint(x: 5, y: s0 / 2)) == .rewind && SteeringWheel.wedge(at: CGPoint(x: s0 / 2, y: s0 - 5)) == .orbit, "steering wheel wedges")
        check(SteeringWheel.Wedge.allCases.allSatisfy { SteeringWheel.wedge(at: SteeringWheel.labelPoint($0)) == $0 }, "each wedge label sits on its wedge")
        nc.wheelCenter(on: SCNVector3(0, 0, 0))
        nc.pushCameraHistory()
        let d0 = Viewport3DController.length(nc.cameraNode.position)
        nc.wheel(.zoom, dx: 0, dy: 50)
        let d1 = Viewport3DController.length(nc.cameraNode.position)
        nc.wheel(.orbit, dx: 40, dy: 10)
        let d2 = Viewport3DController.length(nc.cameraNode.position)
        check(d1 < d0 * 0.8 && close(Double(d2), Double(d1), 1e-3), "wheel: zoom approaches the pivot, orbit keeps the distance")
        nc.wheel(.upDown, dx: 0, dy: 50)
        check(nc.wheelRewind() && close(Double(Viewport3DController.length(nc.cameraNode.position)), Double(d0), 1e-3), "wheel: rewind restores the camera")

        // VIS-035 section box face grips: drag a face to cut live, release to store.
        var sbd = wd
        SectionBox(on: true, min: Vec3(-1000, -1000, -500), max: Vec3(7000, 5000, 4000)).store(in: &sbd)
        nm.editor.replaceDocument(sbd, url: nil)
        nc.sync(model: nm)
        nc.apply(camera: Camera(eye: Vec3(20000, -16000, 14000), target: Vec3(3000, 2000, 1500), fov: 45), animated: false)
        let grips = nc.boxGripNodes
        let base = SectionBox.load(nm.doc)!
        check(grips.count == 6 && grips.allSatisfy { g in SectionBox.Face.allCases.contains { Viewport3DController.length(Viewport3DController.sub(g.position, Scene3DBuilder.world(base.center($0)))) < 1e-6 } }, "section box: a grip on each face")
        check(base.moved(.maxX, by: 500).max.x == 7500 && base.moved(.minZ, by: -100000).min.z == base.max.z - SectionBox.minimumSize && base.moved(.minY, by: 200).min.y == -1200, "section box: face moves along its normal, never inverted")
        let c0 = nv.projectPoint(Scene3DBuilder.world(base.center(.maxX))), c1 = nv.projectPoint(Scene3DBuilder.world(base.center(.maxX) + Vec3(1000, 0, 0)))
        let from = CGPoint(x: c0.x, y: c0.y), to = CGPoint(x: c0.x + (c1.x - c0.x) * 0.5, y: c0.y + (c1.y - c0.y) * 0.5)
        let amt = nc.sectionBoxDragAmount(base, .maxX, from: from, to: to)
        check(close(amt, 500, 5), "section box: drag distance on screen → face offset (\(fmt(amt, 1)) mm)")
        check(nc.sectionBoxFace(at: from) == .maxX, "section box: the +X grip is picked under the cursor")
        nc.sectionBoxDragPreview(base, .maxX, amount: amt)
        check(close(nc.sectionBoxApplied?.max.x ?? 0, 7000 + amt, 1e-6) && SectionBox.load(nm.doc)?.max.x == 7000, "section box: live cut while dragging, drawing unchanged")
        nc.sectionBoxDragCommit(base, .maxX, amount: amt)
        check(close(SectionBox.load(nm.doc)?.max.x ?? 0, 7000 + amt, 0.1), "section box: release stores the box")
        nm.editor.undo()
        check(SectionBox.load(nm.doc)?.max.x == 7000, "section box drag is undoable")

        // VIS-039 camera objects: a placed camera (project 3D view) drives the 3D view.
        var cd = wd
        cd.views.append(ProjectView(name: "Camera 1", kind: "3d", camera: Camera(eye: Vec3(-6000, -6000, 1600), target: Vec3(2000, 2000, 1600), fov: 55)))
        nm.editor.replaceDocument(cd, url: nil)
        nm.pendingHostAction = .setView("named:Camera 1")
        nc.sync(model: nm)
        let ce = Scene3DBuilder.world(Vec3(-6000, -6000, 1600))
        spin(1) { false }
        check(nm.pendingHostAction == nil && Viewport3DController.length(Viewport3DController.sub(nc.cameraNode.position, ce)) < 1e-3, "camera object: VIEW/CAMERAVIEW restore the placed camera in 3D")
        nc.walkStep() // no-op when not navigating

        // VIS-053 / VIS-054 lights, VIS-055 emissive, VIS-056 fog, VIS-084 billboards.
        var ld = wd
        ld.ensureLayer(SceneLights.layer)
        _ = ld.add(SceneLights.entity(SceneLights.Light(id: 0, kind: .point, position: Vec3(0, 0, 2400), target: nil, lumens: 800, cct: 2700, beam: 60, size: Vec2(1, 1), ies: nil, on: true)))
        _ = ld.add(SceneLights.entity(SceneLights.Light(id: 0, kind: .spot, position: Vec3(1000, 0, 2400), target: Vec3(1000, 0, 0), lumens: 500, cct: 4000, beam: 40, size: Vec2(1, 1), ies: nil, on: true)))
        _ = ld.add(SceneLights.entity(SceneLights.Light(id: 0, kind: .area, position: Vec3(2000, 0, 2700), target: nil, lumens: 3000, cct: 5000, beam: 60, size: Vec2(600, 1200), ies: nil, on: true)))
        _ = ld.addElement(.component(ComponentGeom(category: "Lighting", position: Vec2(3000, 1000), size: Vec3(300, 300, 100), baseOffset: 2600)))
        let lb = Scene3DBuilder(); lb.update(doc: ld, style: "Realistic")
        let types = lb.lightNodes.compactMap { $0.light?.type }
        check(types.count == 4 && types.filter { $0 == .omni }.count == 1 && types.filter { $0 == .spot }.count == 2 && types.contains(.area), "lights: point, spot, area and a light fixture in the scene (\(types.map(\.rawValue)))")
        if let pl = lb.lightNodes.first(where: { $0.light?.type == .omni })?.light { check(pl.intensity == 800 && pl.temperature == 2700, "light intensity in lumens and colour temperature") }
        if let sp = lb.lightNodes.first(where: { $0.light?.type == .spot && $0.light?.intensity == 500 }) {
            check(sp.worldFront.y < -0.99 && sp.light?.spotOuterAngle == 40, "spot aims at its target with its beam angle")
        } else { check(false, "spot light node") }
        if let json = try? JSONEncoder().encode(ld), let back = try? JSONDecoder().decode(ArchiDocument.self, from: json) {
            check(SceneLights.all(back) == SceneLights.all(ld), "lights survive save and reopen")
        }
        var off = ld; off.setVariable(SceneLights.variable, "0")
        lb.update(doc: off, style: "Realistic")
        check(lb.lightNodes.isEmpty, "artificial lights off")
        let lm = AppModel(); lm.editor.replaceDocument(wd, url: nil)
        let n0 = lm.doc.entities.count
        run(lm, "LIGHT Spot 1000,1000 1000,2000 2400 1200 3500 35 ")
        let placed = lm.doc.entities.last.flatMap(SceneLights.light)
        check(lm.doc.entities.count == n0 + 1 && placed?.kind == .spot && placed?.lumens == 1200 && placed?.beam == 35 && close(placed?.position.z ?? 0, 2400, 1e-9), "LIGHT places a spot from the command line")
        lm.editor.undo()
        check(lm.doc.entities.count == n0, "LIGHT is undoable")

        let ies = """
        IESNA:LM-63-2002
        [TEST] synthetic
        TILT=NONE
        1 1000 1 3 1 1 2 0 0 0
        1 1 50
        0 90 180
        0
        100 100 100
        """
        if let pr = IESProfile.parse(ies) {
            check(close(pr.integratedLumens, 400 * .pi, 400 * .pi * 0.01) && pr.declaredLumens == 1000 && pr.maxCandela == 100, "IES: isotropic 100 cd integrates to 400π lm (\(fmt(pr.integratedLumens, 1)))")
        } else { check(false, "IES parse") }
        let spotIES = "TILT=NONE\n1 -1 2 4 1 1 2 0 0 0\n1 1 20\n0 30 45 90\n0\n500 500 200 0\n"
        if let sp = IESProfile.parse(spotIES) { check(sp.maxCandela == 1000 && close(sp.beamAngle, 85, 1) && sp.declaredLumens == nil, "IES: beam angle at half peak (\(fmt(sp.beamAngle, 1))°), multiplier, absolute photometry") }
        else { check(false, "IES spot parse") }
        let iesURL = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest.ies")
        try? ies.write(to: iesURL, atomically: true, encoding: .ascii)
        let iesNode = SceneLights.node(SceneLights.Light(id: 1, kind: .ies, position: Vec3(0, 0, 2400), target: nil, lumens: 1000, cct: 3000, beam: 90, size: Vec2(1, 1), ies: iesURL.path, on: true))
        check(iesNode.light?.type == .IES && iesNode.light?.iesProfileURL == iesURL, "IES light uses the photometric file")

        var ed = wd
        ed.materials = Material.library
        ed.setVariable(Emissive.key("Brick"), "3")
        let eb = Scene3DBuilder(); eb.update(doc: ed, style: "Shaded")
        let em = eb.material(for: "Brick", doc: ed), plain = eb.material(for: "Concrete", doc: ed)
        let brick = Material.library.first { $0.name == "Brick" }!.color
        let ec = (em.emission.contents as? NSColor)?.usingColorSpace(.sRGB), pc = (plain.emission.contents as? NSColor)?.usingColorSpace(.sRGB)
        check(em.emission.intensity == 3 && ec.map { close(Double($0.redComponent), brick.r, 0.01) } == true && (pc == nil || pc!.brightnessComponent < 0.01), "emissive material glows (factor 3), others do not")

        let emm = AppModel(); var emd = wd; emd.materials = Material.library; emm.editor.replaceDocument(emd, url: nil)
        run(emm, "MATEMISSIVE Brick 4 ")
        check(Emissive.strength("Brick", doc: emm.doc) == 4, "MATEMISSIVE sets the glow from the command line")
        emm.editor.undo()
        check(Emissive.strength("Brick", doc: emm.doc) == 0, "MATEMISSIVE is undoable")
        run(emm, "FOG On 3000 40000 #C0C8D0 2 ")
        check(FogSettings.load(emm.doc).on && FogSettings.load(emm.doc).start == 3000 && FogSettings.load(emm.doc).end == 40000 && FogSettings.load(emm.doc).density == 2, "FOG from the command line")

        // VIS-062 texture mapping, VIS-063 texture positioning.
        var quad = Mesh()
        quad.positions = [Vec3(1000, 0, 0), Vec3(0, 1000, 0), Vec3(-1000, 0, 500), Vec3(0, -1000, 500)]
        quad.normals = Array(repeating: Vec3(0, 0, 1), count: 4); quad.uvs = Array(repeating: .zero, count: 4); quad.indices = [0, 1, 2, 0, 2, 3]
        var ts = TextureMapping.Settings(); ts.mode = .planar
        check(TextureMapping.uvs(quad, ts)[1].isClose(Vec2(0, 1), tol: 1e-9), "planar mapping: top projection in metres")
        ts.mode = .cylindrical
        let cyl = TextureMapping.uvs(quad, ts)
        check(close(cyl[1].x, .pi / 2, 1e-9) && close(cyl[2].y, 0.5, 1e-9), "cylindrical mapping: arc length around the axis, height up")
        ts.mode = .spherical
        check(TextureMapping.uvs(quad, ts).allSatisfy { $0.x.isFinite && $0.y.isFinite }, "spherical mapping")
        ts.mode = .uv
        let uvf = TextureMapping.uvs(quad, ts)
        check(uvf.allSatisfy { $0.x >= -1e-9 && $0.x <= 1 + 1e-9 && $0.y >= -1e-9 && $0.y <= 1 + 1e-9 }, "UV mapping fitted to 0–1")
        ts = TextureMapping.Settings(); ts.mode = .planar; ts.rotation = 90; ts.offset = Vec2(1000, 0); ts.scale = 2
        let pos = TextureMapping.uvs(quad, ts)[0]   // (1,0) m − offset (1,0) = 0
        check(pos.isClose(.zero, tol: 1e-9) && TextureMapping.uvs(quad, ts)[1].isClose(Vec2(0.5, 0.5), tol: 1e-9), "texture positioning: offset, rotation and scale")
        check(TextureMapping.Settings(stored: ts.stored) == ts && TextureMapping.Settings(stored: "bogus") == nil, "mapping settings round trip")
        let tm = AppModel(); var tmd = wd; tmd.materials = Material.library; tm.editor.replaceDocument(tmd, url: nil)
        run(tm, "MATMAPPING Brick Cylindrical 100 0 45 2 ")
        let tset = TextureMapping.settings("Brick", doc: tm.doc)
        check(tset.mode == .cylindrical && tset.offset == Vec2(100, 0) && tset.rotation == 45 && tset.scale == 2, "MATMAPPING from the command line")
        let tb3 = Scene3DBuilder(); tb3.update(doc: tm.doc, style: "Realistic")
        let before = tb3.modelRoot.childNodes.map { ObjectIdentifier($0) }
        run(tm, "MATMAPPING Concrete Planar 0 0 0 1 ")
        tb3.update(doc: tm.doc, style: "Realistic")
        check(tm.doc.elements.contains { $0.material == "Concrete" } ? tb3.modelRoot.childNodes.map { ObjectIdentifier($0) } != before : true, "changing a mapping rebuilds the affected objects")
        tm.editor.undo()
        check(TextureMapping.settings("Concrete", doc: tm.doc).isDefault, "MATMAPPING is undoable")

        var fd = wd
        var fog = FogSettings(); fog.on = true; fog.start = 2000; fog.end = 30000; fog.store(&fd)
        let fb = Scene3DBuilder(); fb.update(doc: fd, style: "Realistic")
        check(close(Double(fb.scene.fogStartDistance), 2, 1e-9) && close(Double(fb.scene.fogEndDistance), 30, 1e-9) && FogSettings.load(fd).on && FogSettings.load(fd).end == 30000, "fog distances in the scene and saved in the drawing")
        fog.on = false; fog.store(&fd); fb.update(doc: fd, style: "Realistic")
        check(fb.scene.fogEndDistance == 0, "fog off")

        var bd = wd
        _ = bd.add(Billboards.entity(source: "person", at: Vec3(1000, 1000, 0), height: 1750))
        _ = bd.add(Billboards.entity(source: "tree", at: Vec3(5000, 1000, 0), height: 6000))
        let bb = Scene3DBuilder(); bb.update(doc: bd, style: "Shaded")
        let bn = bb.billboardNodes
        check(bn.count == 2 && bn.allSatisfy { ($0.constraints?.first as? SCNBillboardConstraint) != nil }, "billboards face the camera")
        if let p = bn.first(where: { $0.name == "billboard:\(bd.entities[0].id)" }), let pl = p.geometry as? SCNPlane {
            check(close(Double(pl.height), 1.75, 1e-9) && close(Double(p.position.y), 0.875, 1e-9) && Billboards.image("person") != nil, "person cutout 1.75 m standing on the floor")
        } else { check(false, "person billboard node") }

        // VIS-087 web viewer.
        let html = WebViewerExport.html(doc: wd)
        let tris = MeshBuilder.build(doc: wd).reduce(0) { $0 + $1.mesh.indices.count / 3 }
        if let a = html.range(of: "<script id=\"model\" type=\"application/json\">"), let b = html.range(of: "</script>", range: a.upperBound..<html.endIndex),
           let s = try? JSONDecoder().decode(WebViewerExport.Scene.self, from: Data(html[a.upperBound..<b.lowerBound].utf8)) {
            check(s.triangles == tris && tris > 0 && html.contains("webgl2") && !html.contains("src=\"http"), "web viewer: standalone HTML with all \(tris) triangles")
        } else { check(false, "web viewer embeds the model") }

        // SHT-024 / SHT-025 layered vector PDF, fonts, hyperlinks.
        var pd = ArchiDocument()
        pd.layers.append(Layer(name: "A-WALL", color: RGBA(1, 0, 0)))
        pd.layers.append(Layer(name: "A-HIDDEN", visible: true))
        let line = pd.add(.line(LineGeom(.zero, Vec2(10000, 0))), layer: "A-WALL")
        _ = pd.add(.text(TextGeom(position: Vec2(0, 1000), height: 250, content: "Ground floor")), layer: "A-HIDDEN")
        if let i = pd.entities.firstIndex(where: { $0.id == line }) { pd.entities[i].props["hyperlink"] = "https://example.org/wall" }
        let (page, ratio) = LayeredPDF.modelPage(doc: pd, level: nil, ratio: 100)
        let r0 = page.parts[0].renderer
        check(ratio == 100 && close(Double(r0.point(Vec2(10000, 0)).x - r0.point(.zero).x), 100 * 72 / 25.4, 1e-6), "PDF: 10 m at 1:100 is 100 mm on paper")
        var hiddenDoc = pd
        if let i = hiddenDoc.layers.firstIndex(where: { $0.name == "A-HIDDEN" }) { hiddenDoc.layers[i].visible = false }
        let raw = LayeredPDF.build(doc: pd, pages: [page], title: "Test", compress: false)
        check(raw.layers == ["A-WALL", "A-HIDDEN"] && raw.contents[0].contains("/OC /L0 BDC") && raw.contents[0].contains("/OC /L1 BDC") && raw.links == 1, "PDF: one optional content group per layer and a link (layers \(raw.layers), links \(raw.links))")
        let pdf = LayeredPDF.build(doc: pd, pages: [page], title: "Test")
        if let d = PDFDocument(data: pdf.data), let p0 = d.page(at: 0) {
            let bx = p0.bounds(for: .mediaBox)
            let paper = PageSetup.load(pd, layoutIndex: nil).modelPaperSize
            check(d.pageCount == 1 && close(Double(bx.width), paper.width * 72 / 25.4, 0.01), "PDF opens (compressed) with the paper size")
            check((p0.string ?? "").contains("Ground floor"), "PDF text is real text (searchable)")
            check(p0.annotations.contains { ($0.url?.absoluteString ?? ($0.action as? PDFActionURL)?.url?.absoluteString) == "https://example.org/wall" }, "PDF hyperlink annotation (\(p0.annotations.map { $0.type ?? "?" }))")
        } else { check(false, "layered PDF opens in PDFKit") }
        if let prov = CGDataProvider(data: pdf.data as CFData), let cg = CGPDFDocument(prov), let cat = cg.catalog {
            var oc: CGPDFDictionaryRef?, arr: CGPDFArrayRef?
            let ok = CGPDFDictionaryGetDictionary(cat, "OCProperties", &oc) && oc != nil && CGPDFDictionaryGetArray(oc!, "OCGs", &arr)
            check(ok && arr.map { CGPDFArrayGetCount($0) } == raw.layers.count, "PDF catalog lists the layers (OCGs)")
        } else { check(false, "PDF catalog") }
        let hb = LayeredPDF.build(doc: hiddenDoc, pages: [page], title: "T", compress: false)
        check(String(data: hb.data, encoding: .isoLatin1)?.contains("/OFF [") == true && !(String(data: hb.data, encoding: .isoLatin1)?.contains("/OFF []") ?? true), "PDF: hidden layers start off")

        // SHT-039 shade plot of 3D viewports.
        var sd = wd
        sd.materials = Material.library
        sd.layouts = [ArchiCore.Layout(name: "A201", viewports: [Viewport(origin: Vec2(20, 20), size: Vec2(200, 150), viewCenter: Vec2(2500, 2500), scale: 100, view: .axonometric)])]
        let vp = sd.layouts[0].viewports[0]
        let hidden = SheetComposer.viewportEntries(doc: sd, vp: vp)
        let fills = hidden.flatMap(\.items).compactMap { if case .fill(_, let c) = $0 { return c }; return nil }
        let strokes = hidden.flatMap(\.items).filter { if case .stroke = $0 { return true }; return false }
        check(!fills.isEmpty && fills.allSatisfy { $0 == RGBA(1, 1, 1) } && !strokes.isEmpty, "shade plot Hidden: white faces hide back edges")
        check(close(hidden.unionBounds.center.x, 2500, 1) && close(hidden.unionBounds.center.y, 2500, 1), "3D viewport is centred on its view centre")
        ShadePlot.setMode(.wireframe, layout: "A201", index: 0, &sd)
        let wire = SheetComposer.viewportEntries(doc: sd, vp: vp)
        check(!wire.isEmpty && !wire.flatMap(\.items).contains { if case .fill = $0 { return true }; return false }, "shade plot Wireframe: edges only")
        ShadePlot.setMode(.asDisplayed, layout: "A201", index: 0, &sd)
        let shaded = SheetComposer.viewportEntries(doc: sd, vp: vp).flatMap(\.items).compactMap { if case .fill(_, let c) = $0 { return c }; return nil }
        check(shaded.contains { $0 != RGBA(1, 1, 1) }, "shade plot As Displayed: shaded faces")
        ShadePlot.setMode(.rendered, layout: "A201", index: 0, &sd)
        let rendered = SheetComposer.viewportEntries(doc: sd, vp: vp)
        if case .image(let im)? = rendered.first?.items.first { check(FileManager.default.fileExists(atPath: im.path) && close(im.origin.x + im.size.x / 2, 2500, 1), "shade plot Rendered: a render placed in the viewport") }
        else { check(false, "shade plot Rendered image") }
        check(LayeredPDF.sheetPage(doc: sd, layoutIndex: 0).map { LayeredPDF.build(doc: sd, pages: [$0], title: "S").data.count > 1000 } == true, "sheet with a 3D viewport exports to PDF")

        // SCR-027 / SCR-035 assistant.
        let anth = #"{"content":[{"type":"text","text":"Adding a wall."},{"type":"tool_use","id":"t1","name":"run_commands","input":{"commands":["WALL 0,0 5000,0 "]}}]}"#
        let oai = #"{"choices":[{"message":{"content":"","tool_calls":[{"type":"function","function":{"name":"run_commands","arguments":"{\"commands\":[\"LINE 0,0 100,0 \",\"CIRCLE 0,0 50\"]}"}}]}}]}"#
        let fenced = #"{"choices":[{"message":{"content":"Sure:\n```archi\nLINE 0,0 10,0 \n```\nDone."}}]}"#
        check(AssistantProtocol.parse(Data(anth.utf8))?.commands == ["WALL 0,0 5000,0 "] && AssistantProtocol.parse(Data(anth.utf8))?.text == "Adding a wall.", "assistant: Claude tool use parsed")
        check(AssistantProtocol.parse(Data(oai.utf8))?.commands == ["LINE 0,0 100,0 ", "CIRCLE 0,0 50"], "assistant: local model tool calls parsed")
        check(AssistantProtocol.parse(Data(fenced.utf8))?.commands == ["LINE 0,0 10,0 "], "assistant: fenced command block for models without tools")
        check(AssistantProtocol.parse(Data(#"{"error":{"message":"bad key"}}"#.utf8))?.text == "Error: bad key", "assistant: API errors shown")
        let sys = AssistantProtocol.systemPrompt(pd, selection: [line])
        let body = AssistantProtocol.anthropicBody(model: "m", system: sys, messages: [AssistantMessage(role: .user, text: "hi")])
        check(sys.contains("A-WALL") && sys.contains("#\(line)") && sys.contains("WALL") && (body["tools"] as? [[String: Any]])?.first?["name"] as? String == "run_commands"
              && JSONSerialization.isValidJSONObject(body) && JSONSerialization.isValidJSONObject(AssistantProtocol.openAIBody(model: "m", system: sys, messages: [])), "assistant: context and request bodies")
        check(AssistantSession.isLocalEndpoint("http://127.0.0.1:11434/v1/chat/completions") && AssistantSession.isLocalEndpoint("http://localhost:1234/v1/chat/completions")
              && !AssistantSession.isLocalEndpoint("https://api.example.com/v1/chat/completions"), "local model endpoint must be on this Mac")
        let am = AppModel()
        am.editor.transaction("t") { d in for i in 0..<10 { _ = d.add(.line(LineGeom(Vec2(0, Double(i) * 100), Vec2(1000, Double(i) * 100)))) } }
        let session = AssistantSession(model: am)
        var imp: AssistantImpact?
        Task { @MainActor in imp = await AssistantImpact.assess(["LINE 0,0 500,500 "], doc: am.doc) }
        spin(10) { imp != nil }
        check(imp?.added == 1 && imp?.removed == 0 && imp?.isBulk(session.config) == false && am.doc.entities.count == 10, "assistant: impact measured on a copy")
        let eraseAll = "ERASE " + am.doc.entities.map { "#\($0.id)" }.joined(separator: " ") + "  "
        var proposed = false
        Task { @MainActor in await session.propose([eraseAll]); proposed = true }
        spin(10) { proposed }
        check(session.pending != nil && session.pending?.impact.removed == 10 && am.doc.entities.count == 10, "assistant: bulk deletion waits for confirmation")
        var applied = false
        if let p = session.pending { Task { @MainActor in await session.apply(p.commands); applied = true } }
        spin(10) { applied }
        check(am.doc.entities.isEmpty && session.pending == nil, "assistant: confirmed change applied")
        am.editor.undo()
        check(am.doc.entities.count == 10, "assistant edits are undoable")
        proposed = false
        Task { @MainActor in await session.propose(["LINE 0,0 10,10 "]); proposed = true }
        spin(10) { proposed }
        check(session.pending == nil && am.doc.entities.count == 11, "assistant: small change applied directly")

        // SCR-032 render prompts.
        var rs = RenderSettings()
        let ap = RenderPrompt.apply("Golden hour with soft shadows, warm tones, 4K", to: &rs)
        check(rs.environment == .sunset && rs.shadowSoftness == 10 && rs.width == 3840 && Calendar.current.component(.hour, from: rs.date) == 19 && ap.count >= 3, "render prompt: golden hour, soft shadows, 4K")
        var rs2 = RenderSettings()
        _ = RenderPrompt.apply("moody night, clay model, depth of field", to: &rs2)
        check(rs2.environment == .studio && rs2.clay && rs2.depthOfField, "render prompt: clay, depth of field")
        var rs3 = RenderSettings()
        check(RenderPrompt.apply(json: Data(#"{"environment":"Overcast","width":1024,"height":768,"hour":9.5,"clay":true}"#.utf8), to: &rs3)
              && rs3.environment == .overcast && rs3.width == 1024 && rs3.clay && Calendar.current.component(.minute, from: rs3.date) == 30, "render prompt: JSON styling from an assistant")
        var preset = RenderPreset.from(rs, name: "p"); preset.hour = 7.25
        var rs4 = RenderSettings(); preset.apply(to: &rs4)
        check(Calendar.current.component(.hour, from: rs4.date) == 7 && Calendar.current.component(.minute, from: rs4.date) == 15, "render preset carries the sun hour")

        // LAY-020 new layer notification.
        let ln = AppModel()
        var lnd = ArchiDocument(); LayerNotify.setOn(true, &lnd)
        ln.editor.replaceDocument(lnd, url: nil)
        ln.checkLayerNotify()
        ln.editor.transaction("Add layer") { d in d.layers.append(Layer(name: "X-IMPORTED")); _ = d.add(.line(LineGeom(.zero, Vec2(1, 1))), layer: "X-IMPORTED") }
        check(ln.layerNotice?.contains("X-IMPORTED") == true && ModelNotifications.items(ln.doc).contains { $0.code == "LAYER-UNRECONCILED" }, "new layer notification in the command line and Alerts")
        run(ln, "LAYRECONCILE  ")
        check(LayerNotify.unreconciled(ln.doc).isEmpty && !ModelNotifications.items(ln.doc).contains { $0.code == "LAYER-UNRECONCILED" } && ln.layerNotice == nil, "reconciled layers clear the notification")

        // SCR-014 graph player.
        let gp = AppModel()
        gp.editor.transaction("t") { d in NodeGraph.sample.store(in: &d, name: "Columns") }
        let ins = GraphPlayer.inputs(NodeGraph.sample)
        check(ins.count == 1 && ins[0].value == 3000 && ins[0].min == 500 && ins[0].max == 12000, "graph player: Number nodes are the exposed inputs")
        run(gp, "GRAPHPLAYER Columns 5000 ")
        let solids = gp.doc.entities.compactMap { e -> SolidGeom? in if case .solid(let s) = e.geometry, e.props[NodeGraphBake.tag] != nil { return s }; return nil }
        check(solids.count == 6 && solids.allSatisfy { close($0.height, 5000, 1e-9) }, "graph player runs the graph with the input (6 columns 5000 high)")
        let first = gp.doc.entities.map(\.geometry)
        run(gp, "GRAPHPLAYER Columns 5000 ")
        check(gp.doc.entities.map(\.geometry) == first, "graph player is deterministic")
        var clampDoc = ArchiDocument()
        GraphPlayer.run(NodeGraph.sample, values: [ins[0].name: 99999], into: &clampDoc)
        check(clampDoc.entities.compactMap { if case .solid(let s) = $0.geometry { return s.height }; return nil }.allSatisfy { $0 == 12000 }, "graph player clamps inputs to their range")
        gp.editor.undo()
        check(gp.doc.entities.map(\.geometry) == first, "graph player run is one undo step")

        // APP-027 project browser opens project views, cameras and sheets.
        let pb = AppModel()
        var pbd = wd
        pbd.levels.append(Level(id: 7, name: "Upper", elevation: 3000, height: 3000))
        pbd.views = [ProjectView(name: "Upper Plan", kind: "plan", level: 7), ProjectView(name: "Street Camera", kind: "3d", camera: Camera(eye: Vec3(-5000, -9000, 1600), target: Vec3(3000, 2000, 1600), fov: 55))]
        pbd.layouts = [ArchiCore.Layout(name: "A101")]
        pb.editor.replaceDocument(pbd, url: nil)
        ProjectBrowser.openView("Upper Plan", model: pb)
        check(pb.doc.currentLevel == 7 && pb.mode == .plan && pb.doc.variable(ProjectViews.currentKey) == "Upper Plan", "browser: a plan view opens on its level")
        ProjectBrowser.openView("Street Camera", model: pb)
        check(pb.mode == .model && pb.pendingHostAction == .setView("named:Street Camera"), "browser: a camera view opens in 3D at its camera")
        ProjectBrowser.openSheet(0, model: pb)
        check(pb.mode == .sheet && pb.activeLayout == 0, "browser: a sheet opens")

        // APP-049 units and precision.
        check(UnitFormat.linear(42, units: .inches, type: .architectural, precision: 0) == "3'-6\"" && UnitFormat.linear(42.5, units: .inches, type: .architectural, precision: 4) == "3'-6 1/2\"", "architectural units: 3'-6\" and 3'-6 1/2\"")
        check(UnitFormat.linear(3.5, units: .feet, type: .architectural, precision: 0) == "3'-6\"" && UnitFormat.linear(1066.8, units: .millimeters, type: .architectural, precision: 0) == "3'-6\"", "architectural from feet and millimetres")
        check(UnitFormat.linear(42, units: .inches, type: .engineering, precision: 2) == "3'-6.00\"" && UnitFormat.linear(42.5, units: .inches, type: .fractional, precision: 3) == "42 1/2\""
              && UnitFormat.linear(1500, units: .millimeters, type: .scientific, precision: 2) == "1.50E+03" && UnitFormat.linear(2.345, units: .millimeters, type: .decimal, precision: 2) == "2.35", "engineering, fractional, scientific, decimal")
        check(UnitFormat.linear(11.999, units: .inches, type: .architectural, precision: 2) == "1'-0\"" && UnitFormat.linear(-18, units: .inches, type: .architectural, precision: 0) == "-1'-6\"", "architectural rounding carries and negatives")
        check(UnitFormat.angle(.pi / 4 + 0.5 * .pi / 180, type: .dms, precision: 2) == "45d30'" && UnitFormat.angle(.pi / 2, type: .grads, precision: 0) == "100g" && UnitFormat.angle(.pi / 4, type: .surveyor, precision: 1) == "N 45d0' E", "angular units: DMS, grads, surveyor")
        let um = AppModel()
        run(um, "LUNITS 4 ")
        check(UnitFormat.linearType(um.doc) == .architectural, "LUNITS switches the display to architectural (stored in the drawing)")

        // SHT-014 custom title block.
        let tbm = AppModel()
        var tbd = ArchiDocument(); tbd.info.name = "Cedar House"
        tbd.layouts = [ArchiCore.Layout(name: "Plans"), ArchiCore.Layout(name: "Sections")]
        tbm.editor.replaceDocument(tbd, url: nil)
        func sheetTexts(_ i: Int) -> [String] { SheetComposer.decorations(doc: tbm.doc, layout: tbm.doc.layouts[i], layoutIndex: i).flatMap(\.items).compactMap { if case .text(let t, _, _) = $0 { return t.content }; return nil } }
        check(sheetTexts(0).contains("OANARINA ARCHI TOOL"), "built-in title block by default")
        run(tbm, "TITLEBLOCKDESIGN Create ")
        let t0 = sheetTexts(0)
        check(!t0.contains("OANARINA ARCHI TOOL") && t0.contains("Cedar House") && t0.contains("Plans") && t0.contains("A-101  rev —"), "custom title block with field values (\(t0.prefix(6)))")
        var blk = tbm.doc.blocks[CustomTitleBlock.starterName]!
        blk.entities.append(Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(-170, 44), height: 2, content: "PROJECT")), props: ["attdef": "project"]))
        tbm.editor.transaction("edit block") { $0.blocks[CustomTitleBlock.starterName] = blk }
        check(sheetTexts(1).filter { $0 == "Cedar House" }.count == 2 && sheetTexts(1).contains("Sections"), "attribute tags and placeholders filled per sheet")
        let frame = SheetComposer.decorations(doc: tbm.doc, layout: tbm.doc.layouts[0], layoutIndex: 0).unionBounds
        check(close(frame.max.x, tbm.doc.layouts[0].paper.width - SheetComposer.margin, 0.5), "custom title block anchored at the frame corner")
        run(tbm, "TITLEBLOCKDESIGN Builtin ")
        check(sheetTexts(0).contains("OANARINA ARCHI TOOL"), "back to the built-in title block")

        // SHT-038 large format: custom page sizes and roll paper.
        let pt = 72 / 25.4
        let a1 = CGSize(width: 841 * pt, height: 594 * pt), a0 = CGSize(width: 1189 * pt, height: 841 * pt), wide = CGSize(width: 3000 * pt, height: 1200 * pt)
        check(PrintOptions.page(for: a1, mode: .printer, rollWidthMM: 914) == nil && PrintOptions.page(for: a1, mode: .drawing, rollWidthMM: 914).map { $0.size == a1 && $0.scale == 1 } == true, "custom page the size of the drawing")
        if let r = PrintOptions.page(for: a1, mode: .roll, rollWidthMM: 914) { check(close(Double(r.size.width), 914 * pt, 1e-6) && close(Double(r.size.height), 594 * pt, 1e-6) && r.scale == 1, "A1 on a 914 mm roll: long side across, 594 mm used") } else { check(false, "roll A1") }
        if let r = PrintOptions.page(for: a0, mode: .roll, rollWidthMM: 914) { check(close(Double(r.size.height), 1189 * pt, 1e-6) && r.scale == 1, "A0 on a 914 mm roll: 1189 mm long at true size") } else { check(false, "roll A0") }
        if let r = PrintOptions.page(for: wide, mode: .roll, rollWidthMM: 914) { check(close(Double(r.scale), 914.0 / 1200, 1e-6) && close(Double(r.size.height), 3000 * 914.0 / 1200 * pt, 1e-3), "oversize drawing scaled to the roll width") } else { check(false, "roll oversize") }
        let legacyPrint = #"{"printer":"","paper":"","tray":"","mediaType":"","scaling":"Fit to Paper","percent":100,"copies":2,"showSystemDialog":false}"#
        check((try? JSONDecoder().decode(PrintOptions.self, from: Data(legacyPrint.utf8)))?.copies == 2, "print options saved before large-format settings still load")

        // HYPERLINK.
        let hm = AppModel()
        hm.editor.transaction("t") { d in _ = d.add(.line(LineGeom(.zero, Vec2(100, 0)))) }
        let hid = hm.doc.entities[0].id
        run(hm, "HYPERLINK #\(hid)  https://www.oanarinaldi.com ")
        check(hm.doc.entities[0].props["hyperlink"] == "https://www.oanarinaldi.com", "HYPERLINK attaches a URL")
    }
}
