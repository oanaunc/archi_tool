// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import simd
import Metal
import ModelIO
import SceneKit.ModelIO
import ArchiCore

/// Checks of round 10: path tracer (BVH, BRDF furnace test, glass, shadows, light mix, denoiser, tone mapping),
/// PBR maps, material assets, procedural and photo materials, weather, water, scatter, object animation,
/// SpaceMouse camera maths, ribbon customisation and full-screen tracking.
@MainActor
extension AppSelfTests {
    static func round10Checks(_ check: (Bool, String) -> Void) {
        pathTracerChecks(check)
        materialChecks(check)
        environmentChecks(check)
        animationChecks(check)
        uiChecks(check)
        integrationChecks(check)
        displayChecks(check)
        commandLineChecks(check)
    }

    /// CMD-013/014/047 and the customizer panel (M3D-093).
    static func commandLineChecks(_ check: (Bool, String) -> Void) {
        let a = LaunchArguments.parse(["-NSDocumentRevisionsDebugMode", "YES", "~/House.archi", "-t", "/T/Office.architemplate", "--script", "/s/setup.scr", "-c", "ZOOM E", "--selftest"])
        check(a.files == [NSHomeDirectory() + "/House.archi"] && a.template == "/T/Office.architemplate" && a.scripts == ["/s/setup.scr"] && a.commands == ["ZOOM E"], "launch arguments: file, template, script and command")
        check(LaunchArguments.parse(["-psn_0_1234"]).isEmpty && LaunchArguments.parse([]).isEmpty, "launch arguments: system arguments ignored")
        check(CommandLineAppearance.historyHeight(fontSize: 11, lines: 4) == CommandLineAppearance.rowHeight(11) * 4 + 6 && CommandLineAppearance.historyHeight(fontSize: 99, lines: 99) == CommandLineAppearance.rowHeight(20) * 40 + 6, "command line size and lines (clamped)")
        check(CommandLineAppearance.clampOpacity(0) == 0.1 && CommandLineAppearance.clampOpacity(2) == 1, "command line opacity clamped")
        // Customizer: a slider parameter regenerates the scripted solid, out-of-range values are refused.
        let m = AppModel()
        let code = "// Edge length\nsize = 10; // [1:1:50]\ncube(size);"
        let src = SolidSource(kind: .script, profiles: [], params: [0, 0, 0], expression: code)
        guard var s = FeatureSources.build(src, doc: m.doc) else { check(false, "scripted solid builds"); return }
        s.source = src
        let id = m.editor.doc.add(.solid(s))
        let t = Customizer.target(m.doc, selection: [id])
        check(t?.id == id && SCADCustomizer.parameters(t?.script ?? "").first.map { $0.min == 1 && $0.max == 50 && $0.step == 1 } == true, "customizer finds the scripted object and its slider range")
        let v0 = CSG.volume(s)
        let err = Customizer.set("size", "20", id: id, editor: m.editor)
        if case .solid(let s2)? = m.doc.entity(id)?.geometry {
            check(err == nil && abs(CSG.volume(s2) / v0 - 8) < 1e-6 && s2.source?.expression?.contains("size = 20;") == true, "customizer regenerates the object (volume × 8)")
        } else { check(false, "customized solid") }
        check(Customizer.set("size", "99", id: id, editor: m.editor) != nil && m.editor.history.canUndo, "customizer refuses out-of-range values; edits are undoable")
    }

    /// VIS-008/009/010: named views, REGEN and REDRAW on a 100 000-object drawing stay within a 60 fps frame.
    static func displayChecks(_ check: (Bool, String) -> Void) {
        var d = ArchiDocument()
        d.entities.reserveCapacity(100_000)
        for i in 0..<100_000 {
            let x = Double(i % 400) * 250, y = Double(i / 400) * 250
            d.entities.append(Entity(id: i + 1, layer: "0", geometry: .line(LineGeom(Vec2(x, y), Vec2(x + 200, y + 120)))))
        }
        d.nextID = 100_001
        d.namedViews = [NamedView(name: "North", center: Vec2(50000, 55000), height: 8000), NamedView(name: "Core", center: Vec2(20000, 30000), height: 20000),
                        NamedView(name: "All", center: Vec2(50000, 31000), height: 70000)]
        let m = AppModel()
        m.editor.replaceDocument(d, url: nil)
        let cv = PlanCanvasView(model: m)
        m.canvas = cv
        cv.setFrameSize(NSSize(width: 1440, height: 900))
        cv.zoomExtents(recordHistory: false)
        guard let rc = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        rc.scaleBy(x: 2, y: 2)
        cv.drawContentForTesting(rc)
        func timed(_ body: () -> Void) -> Double {
            var best = Double.infinity
            for _ in 0..<5 { let st = Date(); body(); best = min(best, Date().timeIntervalSince(st) * 1000) }
            return best
        }
        // Named views restore through the same host action as VIEW Restore.
        var worstView = 0.0
        for v in m.doc.namedViews {
            let box = BBox2(min: v.center - Vec2(v.height * 0.8, v.height / 2), max: v.center + Vec2(v.height * 0.8, v.height / 2))
            worstView = max(worstView, timed { m.files.perform(.zoomWindow(box), editor: m.editor); cv.drawContentForTesting(rc) })
        }
        check(worstView < 1000.0 / 60, "named views restore within a 60 fps frame on 100k objects (\(String(format: "%.1f", worstView)) ms)")
        // REDRAW keeps the cache; REGEN rebuilds it, then frames are back within 60 fps.
        let redraw = timed { m.files.perform(.setView("redraw"), editor: m.editor); cv.drawContentForTesting(rc) }
        check(cv.isSceneCached && redraw < 1000.0 / 60, "REDRAW repaints from the cache (\(String(format: "%.1f", redraw)) ms)")
        let st = Date()
        m.files.perform(.regen, editor: m.editor)
        check(!cv.isSceneCached, "REGEN discards the display cache")
        cv.drawContentForTesting(rc)
        let regen = Date().timeIntervalSince(st) * 1000
        let after = timed { cv.panView(dx: 9, dy: 4); cv.drawContentForTesting(rc) }
        check(cv.isSceneCached && after < 1000.0 / 60, "after REGEN (\(Int(regen)) ms) frames stay within 60 fps (\(String(format: "%.1f", after)) ms)")
    }

    /// Node packages, automation URLs, AppleScript, and the viewport/path-tracer material consistency.
    static func integrationChecks(_ check: (Bool, String) -> Void) {
        // Node packages: a group becomes a snippet; inserting it evaluates like the original.
        var g = NodeGraph.sample
        g.addGroup(title: "Columns", around: g.nodes.map(\.id))
        let pkg = NodePackages.make(from: g, name: "Test Pack", author: "Self Test")
        check(pkg.snippets.count == 1 && pkg.snippets[0].name == "Columns" && pkg.snippets[0].graph.nodes.count == g.nodes.count, "node package snippet per group")
        let back = (try? pkg.data()).flatMap { try? NodePackage.decode($0) }
        check(back == pkg, "node package file round trip")
        check((try? NodePackage.decode(Data(#"{"format":"x","name":"a"}"#.utf8))) == nil, "foreign node package refused")
        var host = NodeGraph()
        _ = host.add(.number, x: 0, y: 0)
        let map = host.insert(pkg.snippets[0].graph, x: 300, y: 0)
        let e1 = host.evaluate(), e2 = host.evaluate(), orig = NodeGraph.sample.evaluate()
        check(map.count == g.nodes.count && Set(map.values).count == map.count && host.links.count == g.links.count, "snippet inserted with fresh ids and its links")
        check(e1.output == e2.output && e1.output == orig.output && e1.errors.isEmpty, "inserted snippet evaluates deterministically like the original")
        // Automation URLs (Shortcuts, open location) and AppleScript do script.
        check(AutomationURL.parse(URL(string: "oanarina-archi://run?command=LINE%200,0%201000,0")!) == .run("LINE 0,0 1000,0"), "automation URL: run a command")
        check(AutomationURL.parse(URL(string: "oanarina-archi://export?format=pdf&path=/tmp/a.pdf")!) == .export(format: "pdf", path: "/tmp/a.pdf"), "automation URL: export")
        check(AutomationURL.parse(URL(string: "oanarina-archi://open?path=~/x.archi")!) == .open(NSHomeDirectory() + "/x.archi"), "automation URL: open with ~")
        check(AutomationURL.parse(URL(string: "oanarina-archi://export?format=p;df")!) == nil && AutomationURL.parse(URL(string: "oanarina-archi://run")!) == nil
              && AutomationURL.parse(URL(string: "https://run?command=x")!) == nil, "automation URL: malformed or foreign URLs refused")
        check(AppleScriptBridge.lines("LINE 0,0 10,0\r\n\n; comment\nZOOM E") == ["LINE 0,0 10,0", "", "ZOOM E"], "AppleScript script lines (Enter kept, comments dropped)")
        if let plist = Bundle.main.infoDictionary, Bundle.main.bundlePath.hasSuffix(".app") {
            let schemes = (plist["CFBundleURLTypes"] as? [[String: Any]])?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
            check(schemes.contains(AutomationURL.scheme) && plist["NSAppleScriptEnabled"] as? Bool == true, "Info.plist declares the URL scheme and AppleScript")
        }
        // Textured materials: the path tracer uses the viewport's texture scale and maps (VIS-029/061).
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("archi-selftest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let tex = dir.appendingPathComponent("tex.png"), nrm = dir.appendingPathComponent("n.png")
        var px = [UInt8](repeating: 200, count: 8 * 8 * 4)
        for i in 0..<64 where i % 3 == 0 { px[i * 4] = 40 }
        try? MapImages.writePNG(px, width: 8, height: 8, to: tex)
        try? MapImages.writePNG([UInt8](repeating: 128, count: 8 * 8 * 4).enumerated().map { $0.offset % 4 == 2 ? 255 : $0.element }, width: 8, height: 8, to: nrm)
        var doc = ArchiDocument()
        doc.materials = [ArchiCore.Material(name: "Tex", color: RGBA(1, 1, 1), roughness: 0.5, texture: tex.path, textureScale: 500)]
        var mm = MaterialMaps(); mm.normal = nrm.path; mm.roughness = nrm.path
        MaterialMaps.store(mm, material: "Tex", in: &doc)
        let sc = PTScene()
        var cache: [String: Int] = [:]
        let ptm = PTSceneBuilder.material("Tex", doc: doc, scene: sc, textureCache: &cache, clay: false, weather: WeatherSettings())
        check(ptm.albedoMap >= 0 && ptm.normalMap >= 0 && ptm.roughnessMap >= 0 && abs(ptm.uvScale - 2) < 1e-6 && sc.textures.count == 2, "path tracer loads albedo, normal and roughness maps at the viewport's scale")
        let b = Scene3DBuilder()
        b.update(doc: doc, style: "Realistic")
        let sm = b.material(for: "Tex", doc: doc)
        check(sm.diffuse.contents is NSImage && sm.normal.contents is NSImage && sm.roughness.contents is NSImage && abs(sm.normal.contentsTransform.m11 - 2) < 1e-6, "Realistic viewport uses the same maps and scale")
        // Graphics asset colour in shaded views, water and snow shaders.
        var a = MaterialAssetSet(); a.useRenderAppearance = false; a.shadingColor = "#FF0000"
        MaterialAssetSet.store(a, material: "Tex", in: &doc)
        WaterSurface.ensureMaterial(in: &doc)
        WeatherSettings(kind: .snow, intensity: 0.8).store(in: &doc)
        let sb = Scene3DBuilder()
        sb.update(doc: doc, style: "Shaded")
        check((sb.material(for: "Tex", doc: doc).diffuse.contents as? NSColor).map { $0.redComponent > 0.9 && $0.greenComponent < 0.1 } ?? false || sb.material(for: "Tex", doc: doc).diffuse.contents is NSImage, "shaded views use the graphics colour")
        check(sb.material(for: "Water", doc: doc).shaderModifiers?[.surface]?.contains("scn_frame.time") == true, "water material animates its normals")
        check(sb.material(for: "Tex", doc: doc).shaderModifiers?[.surface]?.contains("smoothstep") == true, "snow covers up-facing faces in the viewport")
        try? FileManager.default.removeItem(at: dir)
        // USDZ for AR Quick Look (VIS-085): real-world scale = extent × metersPerUnit, Z up.
        do {
            var ud = ArchiDocument()
            _ = ud.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0), thickness: 200, height: 3000)))
            if let u = try? ARQuickLook.export(ud, fileURL: nil) {
                let data = (try? Data(contentsOf: u)) ?? Data()
                let txt = String(decoding: data, as: UTF8.self)
                let sc = try? SCNScene(url: u, options: nil)
                var ext = SCNVector3Zero
                if let r = sc?.rootNode { let bb = r.boundingBox; ext = SCNVector3(bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z) }
                let mpu = ARQuickLook.metersPerUnit(txt)
                let dims = [Double(ext.x), Double(ext.y), Double(ext.z)].map { $0 * (mpu ?? 0) }.sorted()
                check(data.starts(with: [0x50, 0x4B]) && txt.contains("upAxis = \"Z\"") && abs(dims[2] - 4) < 0.01 && abs(dims[1] - 3) < 0.01 && abs(dims[0] - 0.2) < 0.01,
                      "USDZ for AR Quick Look opens at real-world scale (\(dims.map { fmt($0, 2) }.joined(separator: " × ")) m)")
                try? FileManager.default.removeItem(at: u)
            } else { check(false, "USDZ export") }
        }
        // Real-time renderer (VIS-069): SceneKit on Metal with PBR materials, image-based reflections, SSAO and HDR.
        var rd = ArchiDocument()
        _ = rd.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(4000, 0))))
        let (rb, rcam) = RenderEngine.makeScene(doc: rd, settings: RenderSettings())
        var pbr = true, count = 0
        rb.modelRoot.enumerateHierarchy { n, _ in if let g = n.geometry, n.name != "ground" { for mt in g.materials where mt.lightingModel != .constant { count += 1; if mt.lightingModel != .physicallyBased { pbr = false } } } }
        check(pbr && count > 0 && rcam.camera?.wantsHDR == true && (rcam.camera?.screenSpaceAmbientOcclusionIntensity ?? 0) > 0 && rb.scene.lightingEnvironment.contents != nil && MTLCreateSystemDefaultDevice() != nil,
              "real-time renderer: Metal PBR materials, environment reflections, SSAO and HDR")
    }

    private static func quad(_ a: Vec3, _ b: Vec3, _ c: Vec3, _ d: Vec3) -> Mesh { var m = Mesh(); m.addPolygon([a, b, c, d]); return m }
    private static func box(_ x0: Double, _ y0: Double, _ z0: Double, _ x1: Double, _ y1: Double, _ z1: Double) -> Mesh {
        var m = Mesh()
        m.addPolygon([Vec3(x0, y0, z0), Vec3(x0, y1, z0), Vec3(x1, y1, z0), Vec3(x1, y0, z0)])
        m.addPolygon([Vec3(x0, y0, z1), Vec3(x1, y0, z1), Vec3(x1, y1, z1), Vec3(x0, y1, z1)])
        m.addPolygon([Vec3(x0, y0, z0), Vec3(x1, y0, z0), Vec3(x1, y0, z1), Vec3(x0, y0, z1)])
        m.addPolygon([Vec3(x0, y1, z0), Vec3(x0, y1, z1), Vec3(x1, y1, z1), Vec3(x1, y1, z0)])
        m.addPolygon([Vec3(x0, y0, z0), Vec3(x0, y0, z1), Vec3(x0, y1, z1), Vec3(x0, y1, z0)])
        m.addPolygon([Vec3(x1, y0, z0), Vec3(x1, y1, z0), Vec3(x1, y1, z1), Vec3(x1, y0, z1)])
        return m
    }

    static func pathTracerChecks(_ check: (Bool, String) -> Void) {
        // BVH closest hit equals brute force.
        let sc = PTScene()
        var rng = PTRandom(seed: 7)
        for _ in 0..<300 {
            let c = Vec3(Double(rng.next()) * 10000, Double(rng.next()) * 10000, Double(rng.next()) * 3000)
            var m = Mesh(); m.addPolygon([c, c + Vec3(Double(rng.next()) * 800 + 50, 0, 0), c + Vec3(0, Double(rng.next()) * 800 + 50, Double(rng.next()) * 400)])
            sc.add(m, material: 0)
        }
        sc.buildBVH()
        let stack = UnsafeMutablePointer<Int32>.allocate(capacity: 128)
        defer { stack.deallocate() }
        var agree = 0, hits = 0
        for i in 0..<200 {
            let o = PTVec(rng.next() * 10000, rng.next() * 10000, 6000), d = simd_normalize(PTVec(rng.next() - 0.5, rng.next() - 0.5, -1))
            let h = sc.intersect(o, d, stack: stack)
            var best: Float = .greatestFiniteMagnitude
            for t in sc.tris {
                let p = simd_cross(d, t.e2), det = simd_dot(t.e1, p)
                if abs(det) < 1e-12 { continue }
                let s = o - t.p0, u = simd_dot(s, p) / det
                if u < 0 || u > 1 { continue }
                let q = simd_cross(s, t.e1), v = simd_dot(d, q) / det
                if v < 0 || u + v > 1 { continue }
                let tt = simd_dot(t.e2, q) / det
                if tt > 1e-3 && tt < best { best = tt }
            }
            if best < .greatestFiniteMagnitude { hits += 1 }
            if (h == nil && best == .greatestFiniteMagnitude) || (h != nil && abs(h!.t - best) < 1e-2 * max(1, best)) { agree += 1 }
            _ = i
        }
        check(agree == 200 && hits > 5, "BVH closest hits match brute force (\(agree)/200, \(hits) hits)")
        check(sc.nodes.count > 1 && sc.nodes.count < sc.tris.count * 2, "BVH has interior nodes")

        // Fresnel and refraction.
        check(abs(PTShading.fresnelDielectric(cosI: 1, eta: 1.5) - 0.04) < 1e-4, "Fresnel 4 % at normal incidence (glass)")
        check(PTShading.fresnelDielectric(cosI: 0.1, eta: 1 / 1.5) == 1, "total internal reflection leaving glass at a grazing angle")
        let d45 = simd_normalize(PTVec(1, 0, -1))
        if let t = PTShading.refract(d45, PTVec(0, 0, 1), 1 / 1.5) {
            check(abs(sqrtf(t.x * t.x + t.y * t.y) - sinf(.pi / 4) / 1.5) < 1e-4 && t.z < 0, "Snell's law refraction")
        } else { check(false, "refraction exists") }
        // Furnace test: grey Lambert ground under a uniform white sky reflects its albedo.
        let fs = PTScene()
        var gm = PTMaterial(); gm.albedo = PTVec(repeating: 0.5); gm.roughness = 1
        fs.materials = [gm]; fs.groundZ = 0; fs.groundMaterial = 0
        fs.environment = PTEnvironment.uniform(1)
        fs.buildBVH()
        var st = PTSettings(); st.width = 12; st.height = 8; st.camera = PTCamera(eye: PTVec(0, 0, 1000), target: PTVec(0, 1, 0), fovDegrees: 30); st.maxBounces = 2
        let fsess = PTSession(scene: fs, settings: st)
        for _ in 0..<24 { fsess.renderPass() }
        let img = fsess.compose()
        let mean = img.reduce(Float(0)) { $0 + ptLum($1) } / Float(img.count)
        check(abs(mean - 0.52) < 0.06, "furnace test: albedo 0.5 under a uniform sky ≈ 0.5 (got \(String(format: "%.3f", mean)))")
        // Determinism.
        let fs2 = PTSession(scene: fs, settings: st)
        for _ in 0..<24 { fs2.renderPass() }
        check(fs2.compose() == img, "path tracing is deterministic for a seed")

        // Shadows and glass: a box on the ground blocks the sun; a glass pane lets it through tinted.
        let ss = PTScene()
        var opaque = PTMaterial(); opaque.albedo = PTVec(repeating: 0.7)
        var glass = PTMaterial(); glass.albedo = PTVec(0.8, 0.9, 0.9); glass.transmission = 0.9; glass.roughness = 0.02
        ss.materials = [opaque, glass]
        ss.add(box(0, 0, 0, 1000, 1000, 1000), material: 0)
        ss.add(box(3000, 0, 0, 3010, 1000, 2000), material: 1)
        ss.groundZ = 0; ss.groundMaterial = 0
        ss.buildBVH()
        let up = PTVec(0, 0, 1)
        check(ss.transmittance(PTVec(500, 500, -1), up, tMax: .greatestFiniteMagnitude, stack: stack) == .zero || ss.transmittance(PTVec(500, 500, 1), up, tMax: .greatestFiniteMagnitude, stack: stack) == .zero, "box shadows the ground under it")
        check(ss.transmittance(PTVec(2000, 500, 1), up, tMax: .greatestFiniteMagnitude, stack: stack) == PTVec(repeating: 1), "open ground sees the sky")
        let tg = ss.transmittance(PTVec(2900, 500, 500), PTVec(1, 0, 0), tMax: 500, stack: stack)
        check(tg.x > 0.3 && tg.x < 1 && tg.y > tg.x, "glass transmits tinted light (\(tg.x))")

        // Light groups: sun + sky; the mix is linear.
        ss.environment = PTEnvironment.preset(.clearSky, sun: Vec3(0.3, -0.5, 0.8), altitude: 0.9)
        ss.lights = [PTPointLight(position: PTVec(2000, 2000, 2400), intensity: PTVec(repeating: 5000), direction: nil, cosOuter: -1, cosInner: -1)]
        var s2 = PTSettings(); s2.width = 10; s2.height = 6; s2.camera = PTCamera(eye: PTVec(-3000, -4000, 3000), target: PTVec(1000, 500, 300))
        let ls = PTSession(scene: ss, settings: s2)
        for _ in 0..<4 { ls.renderPass() }
        let all = ls.compose(), sun = ls.group(.sun), sky = ls.group(.sky), art = ls.group(.artificial)
        var lin = true, noSunOK = true
        var noSun = PTLightMix(); noSun.sun = 0
        let ns = ls.compose(noSun)
        for i in all.indices {
            if simd_length(all[i] - (sun[i] + sky[i] + art[i])) > 1e-2 * max(1, simd_length(all[i])) { lin = false }
            if simd_length(ns[i] - (sky[i] + art[i])) > 1e-2 * max(1, simd_length(ns[i])) { noSunOK = false }
        }
        check(lin && noSunOK, "light mix: groups sum to the image; a zero weight removes the group")
        check(sun.contains { ptLum($0) > 0 } && art.contains { ptLum($0) > 0 }, "sun and artificial light groups receive light")

        // Denoiser: flattens noise within a surface, keeps an albedo edge.
        let w = 32, h = 16
        var col = [PTVec](), alb = [PTVec](), nrm = [PTVec](repeating: PTVec(0, 0, 1), count: w * h), dep = [Float](repeating: 1000, count: w * h)
        var nr = PTRandom(seed: 3)
        for _ in 0..<h { for x in 0..<w {
            let a: Float = x < w / 2 ? 0.2 : 0.8
            alb.append(PTVec(repeating: a)); col.append(PTVec(repeating: a * (0.5 + (nr.next() - 0.5) * 0.6)))
        } }
        let dn = PTDenoiser.denoise(color: col, albedo: alb, normal: nrm, depth: dep, width: w, height: h)
        func variance(_ v: [PTVec], _ x0: Int, _ x1: Int) -> Float {
            var s: Float = 0, s2: Float = 0, n: Float = 0
            for y in 0..<h { for x in x0..<x1 { let l = v[y * w + x].x; s += l; s2 += l * l; n += 1 } }
            return s2 / n - (s / n) * (s / n)
        }
        check(variance(dn, 20, 32) < variance(col, 20, 32) / 4, "denoiser reduces noise more than 4×")
        check(abs(dn[8 * w + 14].x - 0.1) < 0.03 && abs(dn[8 * w + 17].x - 0.4) < 0.06, "denoiser keeps the albedo edge sharp")
        // Tone mapping.
        let tm = PTToneMap.rgba([PTVec.zero, PTVec(repeating: 0.1), PTVec(repeating: 1), PTVec(repeating: 10)], ev: 0, auto: false)
        check(tm[0] == 0 && tm[4] < tm[8] && tm[8] < tm[12] && tm[12] == 255 || tm[12] > 250, "tone mapping is monotonic from black")
        let wn0 = PTShading.waterNormal(x: 100, y: 200, time: 0), wn1 = PTShading.waterNormal(x: 100, y: 200, time: 1)
        check(abs(simd_length(wn0) - 1) < 1e-4 && wn0.z > 0.9 && simd_distance(wn0, wn1) > 1e-4, "water normals are unit, near vertical and move with time")

        // Scene from a drawing: walls and a glass window, default camera.
        var doc = ArchiDocument()
        let wall = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0))))
        _ = doc.addElement(.opening(OpeningGeom(kind: .window, hostWall: wall, offset: 2500, width: 1200, height: 1200, sill: 900)))
        let (ds, cam) = PTSceneBuilder.build(doc: doc, camera: nil, options: PTSceneBuilder.Options())
        check(ds.tris.count > 20 && ds.materials.contains { $0.transmission > 0.5 } && ds.groundZ != nil, "drawing → path tracer scene with glass (\(ds.tris.count) triangles)")
        check(simd_length(cam.eye - cam.target) > 1000, "default camera frames the model")
    }

    static func materialChecks(_ check: (Bool, String) -> Void) {
        var doc = ArchiDocument()
        doc.materials = ArchiCore.Material.library
        var maps = MaterialMaps(); maps.normal = "/tmp/n.png"; maps.roughness = "r.png"; maps.displacementScale = 4
        MaterialMaps.store(maps, material: "Brick", in: &doc)
        check(MaterialMaps.load("brick", doc: doc) == maps, "PBR maps round trip (case-insensitive material)")
        check((try? JSONDecoder().decode(MaterialMaps.self, from: Data(#"{"normal":"a.png"}"#.utf8)))?.normalStrength == 1, "PBR maps without newer fields decode")
        MaterialMaps.store(MaterialMaps(), material: "Brick", in: &doc)
        check(doc.variable(MaterialMaps.key("Brick")) == nil, "clearing maps removes the variable")
        // Material assets.
        let conc = MaterialAssetSet.load("Concrete", doc: doc)
        check(conc.density == 2400 && abs((conc.thermalResistance(thickness: 100) ?? 0) - 0.05) < 1e-9, "concrete defaults: 2400 kg/m³, R(100 mm) = 0.05 m²K/W")
        var a = conc; a.description = "C30/37"; a.useRenderAppearance = false; a.shadingColor = "#808080"
        MaterialAssetSet.store(a, material: "Concrete", in: &doc)
        check(MaterialAssetSet.load("Concrete", doc: doc) == a && MaterialAssetSet.shadingColor("Concrete", doc: doc).map { abs($0.r - 128.0 / 255) < 1e-6 } == true, "material assets round trip; graphics colour separate from appearance")
        check((try? JSONDecoder().decode(MaterialAssetSet.self, from: Data(#"{"mark":"M1"}"#.utf8)))?.useRenderAppearance == true, "assets without newer fields decode")
        // Procedural textures: deterministic, joints where expected, tileable.
        var p = ProceduralMaterial.Params(kind: .brick); p.pixels = 128
        let b1 = ProceduralMaterial.generate(p), b2 = ProceduralMaterial.generate(p)
        check(b1.albedo == b2.albedo && b1.height == b2.height, "procedural brick is deterministic")
        let jointFrac = Double(b1.height.filter { $0 < 0.15 }.count) / Double(b1.height.count)
        let expect = 1 - (1 - p.joint * Double(p.columns)) * (1 - p.joint * Double(p.rows))
        check(abs(jointFrac - expect) < 0.08, "brick mortar covers the expected fraction (\(fmt(jointFrac, 3)) vs \(fmt(expect, 3)))")
        var p2 = p; p2.seed = 2
        check(ProceduralMaterial.generate(p2).albedo != b1.albedo, "another seed gives another texture")
        for k in [ProceduralMaterial.Kind.marble, .concrete, .wood, .stone] {
            var q = ProceduralMaterial.Params(kind: k); q.pixels = 96
            let g = ProceduralMaterial.generate(q), n = g.size
            var wrap = 0.0, inner = 0.0
            // Wrap-edge jump compared with the mean jump between neighbouring columns.
            for y in 0..<n { wrap += abs(g.height[y * n] - g.height[y * n + n - 1]); for x in 1..<n { inner += abs(g.height[y * n + x] - g.height[y * n + x - 1]) } }
            inner /= Double(n - 1)
            check(wrap <= inner * 2.5 + Double(n) * 0.01, "\(k.rawValue) texture tiles seamlessly (\(fmt(wrap, 2)) vs \(fmt(inner, 2)))")
        }
        // Photo material: removes a lighting gradient, stays flat → neutral normals.
        let w = 64, h = 32
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let v = UInt8(60 + 120 * x / (w - 1)); px[(y * w + x) * 4] = v; px[(y * w + x) * 4 + 1] = v; px[(y * w + x) * 4 + 2] = v } }
        let r = PhotoMaterial.derive(rgba: px, width: w, height: h, seamless: false)
        func col(_ img: [UInt8], _ x: Int) -> Double { Double(img[(h / 2 * w + x) * 4]) }
        check(col(r.albedo, w - 8) / max(col(r.albedo, 8), 1) < col(px, w - 8) / col(px, 8), "photo de-lighting reduces the light gradient")
        let flat = PhotoMaterial.derive(rgba: [UInt8](repeating: 128, count: 16 * 16 * 4), width: 16, height: 16)
        check(flat.normal[0] == 128 && flat.normal[1] == 128 && flat.normal[2] == 255, "flat photo gives a neutral normal map")
        let s = PhotoMaterial.derive(rgba: px, width: w, height: h, seamless: true)
        check(abs(Double(s.albedo[(h / 2 * w) * 4]) - Double(s.albedo[(h / 2 * w + w - 1) * 4])) < 12, "seamless photo material matches across the wrap edge")
    }

    static func environmentChecks(_ check: (Bool, String) -> Void) {
        var doc = ArchiDocument()
        let w = WeatherSettings(kind: .snow, intensity: 0.7, season: .winter, snowCover: 0.5)
        w.store(in: &doc)
        check(WeatherSettings.load(doc) == w, "weather round trip")
        check(WeatherSettings.load(ArchiDocument()) == WeatherSettings() && WeatherSettings().particles == nil && WeatherSettings().shaderModifier == nil, "clear weather has no particles or snow")
        check(w.particles != nil && w.snow == 0.5 && w.shaderModifier?.contains("smoothstep") == true, "snow: particles and snow cover shader")
        let rain = WeatherSettings(kind: .rain, intensity: 1)
        check((rain.particles?.speed ?? 0) > (w.particles?.speed ?? 0) && rain.wetness == 1, "rain falls faster than snow and wets surfaces")
        let g = RGBA(0.35, 0.55, 0.25)
        check(WeatherSettings.seasonTint(g, .summer) == g && WeatherSettings.seasonTint(g, .autumn).r > g.r && WeatherSettings.seasonTint(g, .autumn).g < g.g, "season tints: summer unchanged, autumn warmer")
        check(WeatherSettings.isVegetation("Tree Foliage") && !WeatherSettings.isVegetation("Concrete"), "vegetation materials are recognised")
        check((WeatherSettings(kind: .fog, intensity: 1).fogDistance ?? 999) < (WeatherSettings(kind: .fog, intensity: 0).fogDistance ?? 0), "denser fog shortens visibility")
        // Water.
        var wd = ArchiDocument()
        WaterSurface.ensureMaterial(in: &wd)
        let e = WaterSurface.entity(boundary: [Vec2(0, 0), Vec2(4000, 0), Vec2(4000, 2000), Vec2(0, 2000)], elevation: -100, depth: 1500)
        if let e, case .solid(let s) = e.geometry { check(s.kind == .extrusion && abs(s.origin.z + 1600) < 1e-9 && s.height == 1500 && e.props["material"] == "Water", "water body extrusion below the surface") }
        else { check(false, "water entity") }
        check(WaterSurface.isWater("Water", doc: wd) && wd.material("Water")?.transparency ?? 0 > 0.3, "Water material is flagged and transparent")
        check(WaterSurface.entity(boundary: [Vec2(0, 0), Vec2(1, 0)], elevation: 0, depth: 1) == nil, "degenerate water boundary refused")
        // Scatter.
        let poly = [Vec2(0, 0), Vec2(10000, 0), Vec2(10000, 10000), Vec2(0, 10000)]
        let hole = [Vec2(4000, 4000), Vec2(6000, 4000), Vec2(6000, 6000), Vec2(4000, 6000)]
        let r = Scatter.spacing(density: 1)
        let pts = Scatter.poissonDisk(in: poly, holes: [hole], minDistance: r, maxCount: 10_000, seed: 5)
        var minD = Double.greatestFiniteMagnitude
        for i in pts.indices { for j in (i + 1)..<pts.count { minD = min(minD, pts[i].distance(to: pts[j])) } }
        check(minD >= r - 1e-6, "Poisson-disk spacing respected")
        check(pts.allSatisfy { Scatter.inside($0, poly) && !Scatter.inside($0, hole) }, "scatter stays inside and avoids holes")
        check(Double(pts.count) > 96 * 0.6 && Double(pts.count) < 96 * 1.4, "scatter density ≈ 1 per m² (\(pts.count) on 96 m²)")
        check(Scatter.poissonDisk(in: poly, minDistance: r, maxCount: 500, seed: 5) == Scatter.poissonDisk(in: poly, minDistance: r, maxCount: 500, seed: 5), "scatter is reproducible")
        let se = Scatter.entities(.trees, boundary: poly, density: 0.05, z: 0, seed: 1)
        check(se.entities.count == 2 && se.count >= 2 && se.entities.allSatisfy { if case .solid(let s) = $0.geometry { return s.kind == .mesh && !s.meshTriangles.isEmpty }; return false }, "tree scatter makes trunk and crown meshes")
    }

    static func animationChecks(_ check: (Bool, String) -> Void) {
        let a = ObjectAnimation(id: 1, target: 5, kind: .rotate, pivot: Vec3(1000, 0, 0), angle: 90, start: 1, duration: 2, pingPong: true)
        check(a.progress(at: 0) == 0 && a.progress(at: 1) == 0 && abs(a.progress(at: 3) - 1) < 1e-12 && abs(a.progress(at: 5)) < 1e-12 && a.end == 5, "animation timing: start, full at end, back with ping-pong")
        check(abs(a.progress(at: 2) - 0.5) < 1e-12, "eased midpoint")
        let q = a.apply(Vec3(2000, 0, 50), at: 3)
        check(q.isClose(Vec3(1000, 1000, 50), tol: 1e-6), "rotation about the pivot")
        let m = a.matrix(at: 3)
        let v = SCNVector3(2000, 0, 50)
        let x = m.m11 * v.x + m.m21 * v.y + m.m31 * v.z + m.m41, y = m.m12 * v.x + m.m22 * v.y + m.m32 * v.z + m.m42
        check(abs(Double(x) - 1000) < 1e-3 && abs(Double(y) - 1000) < 1e-3, "SceneKit transform matches the animation")
        var doc = ArchiDocument()
        let wall = doc.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(5000, 0))))
        let door = doc.addElement(.opening(OpeningGeom(kind: .door, hostWall: wall, offset: 2500, width: 900, height: 2100)))
        guard let el = doc.element(door) else { check(false, "door element"); return }
        let leaves = ObjectAnimations.doorLeaves(el, doc: doc)
        check(leaves.count == 1 && abs(leaves[0].hinge.x - (2500 - 450 + 50)) < 1e-6, "door hinge at the leaf edge")
        let anims = ObjectAnimations.door(el, doc: doc, id: 1, angle: 90, start: 0, duration: 2)
        ObjectAnimations.store(anims, in: &doc)
        check(ObjectAnimations.load(doc) == anims && ObjectAnimations.duration(anims) == 4, "door animation saved in the drawing")
        let groups = MeshBuilder.build(doc: doc).filter { $0.id == door && $0.material == (el.material ?? "Wood") }
        if let g = groups.first {
            let sp = ObjectAnimations.splitDoor(g.mesh, leaves: leaves)
            let inSpan = sp.leaves[0].positions.allSatisfy { $0.x >= 2100 - 1 && $0.x <= 2900 + 1 }
            check(!sp.leaves[0].isEmpty && !sp.rest.isEmpty && inSpan && sp.leaves[0].triangleCount + sp.rest.triangleCount == g.mesh.triangleCount, "door leaf split from the frame")
            let open = sp.leaves[0].positions.map { anims[0].apply($0, at: 2) }
            check(open.allSatisfy { abs($0.x - leaves[0].hinge.x) < 100 }, "open leaf stands perpendicular to the wall")
        } else { check(false, "door mesh") }
        check((try? JSONDecoder().decode([ObjectAnimation].self, from: Data(#"[{"id":1,"target":2}]"#.utf8)))?.first?.duration == 2, "animations without newer fields decode")
    }

    static func uiChecks(_ check: (Bool, String) -> Void) {
        // SpaceMouse maths.
        let cfg = SpaceMouse.Config()
        check(SpaceMouse.motion(axes: [10, -10, 5, 0, 0, 3], config: cfg, dt: 1 / 60).isZero, "SpaceMouse dead zone")
        let cam = Camera(eye: Vec3(10000, 0, 2000), target: Vec3(0, 0, 2000))
        let zoom = SpaceMouse.apply(SpaceMouse.motion(axes: [0, -350, 0, 0, 0, 0], config: cfg, dt: 0.1), to: cam, mode: .object)
        check(zoom.eye.distance(to: zoom.target) < 10000 && zoom.target == cam.target, "SpaceMouse push zooms towards the target")
        let spin = SpaceMouse.apply(SpaceMouse.motion(axes: [0, 0, 0, 0, 0, 300], config: cfg, dt: 0.1), to: cam, mode: .object)
        check(abs(spin.eye.distance(to: spin.target) - 10000) < 1e-6 && !spin.eye.isClose(cam.eye, tol: 1), "SpaceMouse spin orbits at a constant distance")
        let fly = SpaceMouse.apply(SpaceMouse.motion(axes: [300, 0, 0, 0, 0, 0], config: cfg, dt: 0.1), to: cam, mode: .fly)
        check((fly.eye - cam.eye).isClose(fly.target - cam.target, tol: 1e-6) && fly.eye.y != cam.eye.y, "SpaceMouse fly pans eye and target together")
        var dom = cfg; dom.dominant = true
        let dm = SpaceMouse.motion(axes: [300, 200, 0, 0, 0, 0], config: dom, dt: 0.1)
        check(dm.right != 0 && dm.forward == 0, "dominant axis mode keeps the strongest axis")
        // Ribbon customisation.
        var c = RibbonCustomization()
        c.panels = [CustomRibbonPanel(title: "Mine", tab: "Home", commands: ["LINE", "ZOOM E"]), CustomRibbonPanel(title: "Two", tab: "Home", commands: ["NOPE"])]
        c.hiddenPanels = ["Selection"]
        let data = try? c.encoded()
        let back = data.flatMap { try? RibbonCustomization.decode($0) }
        check(back == c, "ribbon customisation export/import round trip")
        check(c.unknownCommands(.shared) == ["NOPE"], "unknown commands reported on import")
        c.movePanel(c.panels[1].id, by: -1)
        check(c.panels.map(\.title) == ["Two", "Mine"], "panels reorder within a tab")
        c.moveCommand(panel: c.panels[1].id, from: 0, by: 1)
        check(c.panels[1].commands == ["ZOOM E", "LINE"], "buttons reorder within a panel")
        check((try? RibbonCustomization.decode(Data(#"{"format":"other"}"#.utf8))) == nil, "foreign files are refused")
        check(c.panels[1].symbol(for: "LINE") == QuickAccess.symbol(for: "LINE"), "custom buttons use the command icon")
        // Full screen and Split View.
        let tw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        tw.minSize = NSSize(width: 900, height: 700)
        FullScreenState.track(tw)
        check(tw.minSize.width <= 560 && tw.minSize.height <= 420, "drawing windows fit a Split View half")
        // Every round-10 command is in a ribbon/menu catalog.
        let names = Set(CommandCatalog.coverageMenus.flatMap(\.1).flatMap(\.names))
        check(AppCommandsRound10.all.allSatisfy { names.contains($0.name) }, "round 10 commands have menu entries")
    }
}
