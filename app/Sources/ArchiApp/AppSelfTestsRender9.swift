// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// APPSELFTEST checks of render passes, regions and tiled large renders (VIS-072, VIS-074, VIS-075).
extension AppSelfTests {
    static func renderPassChecks(_ check: (Bool, String) -> Void) {
        guard MTLCreateSystemDefaultDevice() != nil else { check(false, "Metal device for renders"); return }
        var d = ArchiDocument()
        d.materials = Material.library
        _ = d.addElement(.slab(SlabGeom(boundary: [Vec2(-4000, -4000), Vec2(8000, -4000), Vec2(8000, 8000), Vec2(-4000, 8000)])), material: "Concrete")
        _ = d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0))), material: "Brick")
        _ = d.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 5000))), material: "Plaster")
        let camNode = SCNNode()
        camNode.position = Scene3DBuilder.world(Vec3(-7000, -9000, 6000))
        camNode.look(at: Scene3DBuilder.world(Vec3(3000, 2000, 1000)), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        let view = camNode.transform
        var s = RenderSettings()
        s.width = 320; s.height = 200; s.antialias = false; s.ambientOcclusion = 0; s.bloom = 0; s.shadowQuality = .medium

        func diff(_ a: (w: Int, h: Int, rgba: [UInt8]), _ b: (w: Int, h: Int, rgba: [UInt8]), ox: Int = 0, oy: Int = 0) -> Double {
            var sum = 0.0, n = 0
            guard ox + b.w <= a.w, oy + b.h <= a.h else { return 999 }
            for y in 0..<b.h { for x in 0..<b.w {
                let i = (y * b.w + x) * 4, j = ((y + oy) * a.w + (x + ox)) * 4
                for k in 0..<3 { sum += abs(Double(a.rgba[j + k]) - Double(b.rgba[i + k])) }; n += 3
            } }
            return n > 0 ? sum / Double(n) : 999
        }
        guard let full = RenderEngine.renderAdvanced(doc: d, settings: s, tile: 4096, camera: view).flatMap(RenderEngine.pixels),
              let tiled = RenderEngine.renderAdvanced(doc: d, settings: s, tile: 96, camera: view).flatMap(RenderEngine.pixels) else { check(false, "renders"); return }
        check(full.w == 320 && full.h == 200 && tiled.w == 320 && tiled.h == 200, "tiled render has the frame size")
        let dt = diff(full, tiled)
        check(dt < 4, "tiled render matches the single render (mean difference \(fmt(dt, 2)))")
        if let reg = RenderEngine.renderAdvanced(doc: d, settings: s, region: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), camera: view).flatMap(RenderEngine.pixels) {
            let dr = diff(full, reg, ox: 80, oy: 100)
            check(reg.w == 160 && reg.h == 50 && dr < 4, "render region equals that part of the frame (\(reg.w)×\(reg.h), difference \(fmt(dr, 2)))")
        } else { check(false, "render region") }
        var big = s; big.width = 10000; big.height = 6000
        if let corner = RenderEngine.renderAdvanced(doc: d, settings: big, region: CGRect(x: 0.45, y: 0.45, width: 0.05, height: 0.05), camera: view).flatMap(RenderEngine.pixels) {
            check(corner.w == 384 && corner.h == 216, "8K frame (size clamped to 7680×4320) rendered by region/tiles (\(corner.w)×\(corner.h))")
        } else { check(false, "8K region render") }

        // VIS-032 sketchy style, VIS-080 non-photorealistic renders.
        check(VisualStyleNames.canonical("sketchy") == "Sketchy" && VisualStyleNames.canonical("hand drawn") == "Sketchy", "Sketchy is its own visual style")
        let sk = Scene3DBuilder(); sk.update(doc: d, style: "Sketchy")
        var skLines = 0, skConst = true
        sk.modelRoot.enumerateHierarchy { n, _ in
            guard n.name != "ground", let g = n.geometry else { return }
            if g.elements.first?.primitiveType == .line { skLines += g.elements[0].primitiveCount }
            else if g.materials.contains(where: { $0.lightingModel != .constant }) { skConst = false }
        }
        let plainLines = MeshBuilder.build(doc: d).reduce(0) { $0 + $1.edges.reduce(0) { $0 + max(0, $1.count - 1) } }
        check(skLines > plainLines * 4 && skConst, "sketchy: double, wavy strokes (\(skLines) vs \(plainLines) edges) over flat paper faces")
        check(SketchyStyle.strokes(Vec3(0, 0, 0), Vec3(3000, 0, 0)) == SketchyStyle.strokes(Vec3(0, 0, 0), Vec3(3000, 0, 0)) && SketchyStyle.strokes(Vec3(0, 0, 0), Vec3(3000, 0, 0)).count == 2, "sketch strokes are deterministic")
        if let a = RenderEngine.renderNPR(doc: d, settings: s, style: .sketch, camera: view).flatMap(RenderEngine.pixels),
           let b = RenderEngine.renderNPR(doc: d, settings: s, style: .sketch, camera: view).flatMap(RenderEngine.pixels) {
            var paper = 0, ink = 0
            for i in stride(from: 0, to: a.rgba.count, by: 4) { let l = Int(a.rgba[i]) + Int(a.rgba[i + 1]) + Int(a.rgba[i + 2]); if l > 690 { paper += 1 } else if l < 450 { ink += 1 } }
            check(a.rgba == b.rgba && paper > a.w * a.h / 3 && ink > 100, "sketch render: ink lines on paper, identical each time (paper \(paper), ink \(ink))")
        } else { check(false, "sketch render") }
        if let wc = RenderEngine.renderNPR(doc: d, settings: s, style: .watercolour, camera: view).flatMap(RenderEngine.pixels),
           let ph = RenderEngine.renderAdvanced(doc: d, settings: s, camera: view).flatMap(RenderEngine.pixels) {
            func distinct(_ p: (w: Int, h: Int, rgba: [UInt8])) -> Int { var c = Set<UInt32>(); for i in stride(from: 0, to: p.rgba.count, by: 4) { c.insert(UInt32(p.rgba[i]) << 16 | UInt32(p.rgba[i + 1]) << 8 | UInt32(p.rgba[i + 2])) }; return c.count }
            let dw = distinct(wc), dp = distinct(ph)
            check(wc.w == ph.w && dw < dp && diff(ph, wc) > 5, "watercolour render: washes of fewer colours than the photo (\(dw) vs \(dp))")
        } else { check(false, "watercolour render") }

        // VIS-048 stereo panorama: over-under, left eye on top; zero separation equals the mono panorama.
        let peye = Vec3(3000, -2000, 1600)
        if let st = RenderEngine.stereoPanorama(doc: d, settings: s, eye: peye, width: 256, ipd: 64, slices: 8),
           let mono = RenderEngine.panorama(doc: d, settings: s, eye: peye, width: 256),
           let z = RenderEngine.stereoPanorama(doc: d, settings: s, eye: peye, width: 256, ipd: 0, slices: 8),
           let sp = RenderEngine.pixels(NSImage(cgImage: st, size: .zero)), let mp = RenderEngine.pixels(NSImage(cgImage: mono, size: .zero)), let zp = RenderEngine.pixels(NSImage(cgImage: z, size: .zero)) {
            let top = (w: sp.w, h: sp.h / 2, rgba: Array(sp.rgba[0..<(sp.rgba.count / 2)])), bottom = (w: sp.w, h: sp.h / 2, rgba: Array(sp.rgba[(sp.rgba.count / 2)...]))
            let ztop = (w: zp.w, h: zp.h / 2, rgba: Array(zp.rgba[0..<(zp.rgba.count / 2)]))
            let dz = diff(mp, ztop), dLR = diff(top, bottom)
            check(st.width == 256 && st.height == 256, "stereo panorama: two 2:1 eyes over-under")
            check(dz < 2 && dLR > 0.05 && dLR < 25, "stereo panorama: eyes differ by parallax only (L/R \(fmt(dLR, 2)), mono vs zero-separation \(fmt(dz, 2)))")
        } else { check(false, "stereo panorama renders") }
        let o1 = RenderEngine.odsOffset(longitude: 0, heading: 0, ipdMetres: 0.064, eye: 1)
        check(abs(Double(o1.x) - 0.032) < 1e-9 && abs(Double(o1.z)) < 1e-9, "looking forward (−Z) the right eye sits 32 mm to +X")

        // VIS-044 construction sequence (4D).
        var ph = ArchiDocument()
        ph.phases = ["Existing", "Structure", "Upper"]
        ph.levels.append(Level(id: 5, name: "L1", elevation: 3000))
        let pOld = ph.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        let pDemo = ph.addElement(.wall(WallGeom(start: Vec2(0, 2000), end: Vec2(4000, 2000))))
        let pNew1 = ph.addElement(.slab(SlabGeom(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 4000), Vec2(0, 4000)])))
        let pNew2 = ph.addElement(.wall(WallGeom(start: Vec2(0, 4000), end: Vec2(4000, 4000))))
        let pUp = ph.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(0, 4000))), level: 5)
        func setPhase(_ id: EntityID, _ c: String, _ dm: String? = nil) { if let i = ph.elementIndex(id) { ph.elements[i].props["phaseCreated"] = c; ph.elements[i].props["phaseDemolished"] = dm } }
        setPhase(pOld, "Existing"); setPhase(pDemo, "Existing", "Structure"); setPhase(pNew1, "Structure"); setPhase(pNew2, "Structure"); setPhase(pUp, "Upper")
        let f0 = PhasingAnimation.frame(0, framesPerPhase: 4, doc: ph), f3 = PhasingAnimation.frame(3, framesPerPhase: 4, doc: ph)
        let f4 = PhasingAnimation.frame(4, framesPerPhase: 4, doc: ph), f7 = PhasingAnimation.frame(7, framesPerPhase: 4, doc: ph), f11 = PhasingAnimation.frame(11, framesPerPhase: 4, doc: ph)
        check(f0.phase == 0 && f3.ids == [pOld, pDemo].sorted() && f0.ids.count <= f3.ids.count, "4D: phase 1 builds the existing walls")
        check(f4.phase == 1 && f4.ids.contains(pNew1) && !f4.ids.contains(pNew2) && f7.ids == [pOld, pNew1, pNew2].sorted(), "4D: the slab (lowest) comes before the wall, the demolished wall is gone at the end of its phase")
        check(f11.ids == [pOld, pNew1, pNew2, pUp].sorted() && PhasingAnimation.frame(11, framesPerPhase: 4, doc: ph) == f11, "4D: final frame is the complete model, reproducibly")
        let vidURL = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest-4d.mp4")
        var vs = RenderSettings(); vs.width = 160; vs.height = 90; vs.antialias = false
        var vidDone = false, vidErr: Error?
        Task { @MainActor in
            do { try await PhasingAnimation.video(doc: ph, settings: vs, secondsPerPhase: 0.1, camera: Camera(eye: Vec3(-6000, -8000, 7000), target: Vec3(2000, 2000, 1000)), to: vidURL) { _ in } } catch { vidErr = error }
            vidDone = true
        }
        spin(60) { vidDone }
        let vsize = (try? FileManager.default.attributesOfItem(atPath: vidURL.path)[.size] as? Int) ?? 0
        check(vidDone && vidErr == nil && vsize > 1000, "4D video written (\(vsize) bytes)")
        var sd4 = ph
        Scheduler.save(Scheduler.generate(sd4, start: "2026-10-01"), in: &sd4)
        if let ws = Scheduler.load(sd4), let tm = try? Scheduler.cpm(ws), let end = tm.values.map(\.ef).max(), end > 1 {
            let first = PhasingAnimation.scheduleFrame(day: -1, schedule: ws, timing: tm, doc: sd4), last = PhasingAnimation.scheduleFrame(day: end, schedule: ws, timing: tm, doc: sd4)
            check(first.count < last.count && last == sd4.elements.map(\.id).sorted(), "4D from the work schedule: nothing scheduled built before day 1, everything at the end (\(first.count) → \(last.count))")
        } else { check(false, "work schedule for 4D") }

        // RENDERTOFILE from the command line (pass, size, file).
        let rm = AppModel(); rm.editor.replaceDocument(d, url: nil)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest-id.png")
        try? FileManager.default.removeItem(at: out)
        var done = false
        Task { @MainActor in _ = await rm.editor.run("RENDERTOFILE 64x40 MaterialID  \(out.path)"); done = true }
        spin(20) { done }
        let rep = NSImage(contentsOf: out).flatMap { $0.tiffRepresentation }.flatMap(NSBitmapImageRep.init(data:))
        check(rep?.pixelsWide == 64 && rep?.pixelsHigh == 40, "RENDERTOFILE writes a 64×40 material ID pass")

        // Passes.
        let palette = RenderEngine.materialIDColors(d)
        if let id = RenderEngine.renderAdvanced(doc: d, settings: s, pass: .materialID, camera: view).flatMap(RenderEngine.pixels) {
            var colors = Set<UInt32>()
            for i in stride(from: 0, to: id.rgba.count, by: 4) { colors.insert(UInt32(id.rgba[i]) << 16 | UInt32(id.rgba[i + 1]) << 8 | UInt32(id.rgba[i + 2])) }
            let known = Set(palette.map { UInt32(($0.color.r * 255).rounded()) << 16 | UInt32(($0.color.g * 255).rounded()) << 8 | UInt32(($0.color.b * 255).rounded()) }).union([0])
            let matched = colors.filter { c in known.contains { k in abs(Int(c >> 16) - Int(k >> 16)) <= 2 && abs(Int((c >> 8) & 255) - Int((k >> 8) & 255)) <= 2 && abs(Int(c & 255) - Int(k & 255)) <= 2 } }
            check(colors.count >= 3 && matched.count == colors.count, "material ID pass: flat colours from the material palette (\(colors.count) colours, unmatched \(colors.subtracting(matched).prefix(4).map { String($0, radix: 16) }), palette \(known.prefix(6).map { String($0, radix: 16) }))")
        } else { check(false, "material ID pass") }
        if let nrm = RenderEngine.renderAdvanced(doc: d, settings: s, pass: .normal, camera: view).flatMap(RenderEngine.pixels) {
            var colors = Set<UInt32>()
            for i in stride(from: 0, to: nrm.rgba.count, by: 4) where Int(nrm.rgba[i]) + Int(nrm.rgba[i + 1]) + Int(nrm.rgba[i + 2]) > 0 { colors.insert(UInt32(nrm.rgba[i]) << 16 | UInt32(nrm.rgba[i + 1]) << 8 | UInt32(nrm.rgba[i + 2])) }
            check(colors.count >= 3, "normal pass: one colour per surface orientation (\(colors.count))")
        } else { check(false, "normal pass") }
        if let dep = RenderEngine.renderAdvanced(doc: d, settings: s, pass: .depth, camera: view).flatMap(RenderEngine.pixels) {
            var grey = true, lo = 255, hi = 0
            for i in stride(from: 0, to: dep.rgba.count, by: 4) {
                if abs(Int(dep.rgba[i]) - Int(dep.rgba[i + 1])) > 2 || abs(Int(dep.rgba[i]) - Int(dep.rgba[i + 2])) > 2 { grey = false }
                if dep.rgba[i] > 0 { lo = min(lo, Int(dep.rgba[i])); hi = max(hi, Int(dep.rgba[i])) }
            }
            check(grey && hi - lo > 40, "depth pass: grey levels by distance (range \(lo)–\(hi), grey \(grey))")
            // Near surfaces are brighter: the slab's front corner (bottom of frame) vs the far wall top.
            let near = Int(dep.rgba[((dep.h - 5) * dep.w + dep.w / 2) * 4]), far = Int(dep.rgba[((dep.h / 3) * dep.w + dep.w * 2 / 3) * 4])
            check(near > far, "depth pass: nearer is brighter (\(near) > \(far))")
        } else { check(false, "depth pass") }
        if let al = RenderEngine.renderAdvanced(doc: d, settings: s, pass: .alpha, camera: view).flatMap(RenderEngine.pixels) {
            var white = 0, black = 0
            for i in stride(from: 0, to: al.rgba.count, by: 4) { if al.rgba[i] > 250 { white += 1 } else if al.rgba[i] < 5 { black += 1 } }
            check(white > 1000 && black > 1000, "alpha pass: model white on black background")
        } else { check(false, "alpha pass") }
    }
}
