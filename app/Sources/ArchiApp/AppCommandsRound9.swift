// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Window arrangement of the open drawings (APP-002): tiled side by side, stacked, cascaded or as tabs.
enum WindowArrangement {
    enum Mode: String, CaseIterable { case vertical = "Vertical", horizontal = "Horizontal", cascade = "Cascade" }
    static func frames(count n: Int, in r: CGRect, mode: Mode) -> [CGRect] {
        guard n > 0 else { return [] }
        switch mode {
        case .vertical:
            let w = r.width / CGFloat(n)
            return (0..<n).map { CGRect(x: r.minX + CGFloat($0) * w, y: r.minY, width: w, height: r.height) }
        case .horizontal:
            let h = r.height / CGFloat(n)
            return (0..<n).map { CGRect(x: r.minX, y: r.maxY - CGFloat($0 + 1) * h, width: r.width, height: h) }
        case .cascade:
            let step: CGFloat = 28
            let w = max(r.width - step * CGFloat(n - 1), r.width * 0.6), h = max(r.height - step * CGFloat(n - 1), r.height * 0.6)
            return (0..<n).map { CGRect(x: r.minX + CGFloat($0) * step, y: r.maxY - h - CGFloat($0) * step, width: w, height: h) }
        }
    }
}

/// Commands of round 9: first-person navigation, steering wheel and two-point perspective, lights, fog, emissive
/// materials, billboards, layered PDF and shade plot, web viewer, assistant, render prompts, marking menu, window
/// arrangement and hyperlinks.
@MainActor
enum AppCommandsRound9 {
    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    /// The window's 3D view, switching to it when a plan or sheet is shown.
    static func view3D(_ ed: Editor) async throws -> Viewport3DController {
        let m = try ui(ed)
        if m.mode == .plan || m.mode == .sheet { m.mode = .model }
        for _ in 0..<30 {
            if let c = m.viewport3D { return c }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CommandError.invalid("Open the 3D view first.")
    }
    private static func number(_ ed: Editor, _ msg: String, _ def: Double) async throws -> Double {
        try await ed.getDistance("\(msg) <\(fmt(def))>", defaultValue: def).value ?? def
    }
    private static func path(_ ed: Editor, _ msg: String, ext: String, def: String) async throws -> URL? {
        guard let s = try await ed.getString("\(msg) <\(def)>", defaultValue: def) else { return nil }
        var p = (s.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath
        if p.isEmpty { return nil }
        if !p.lowercased().hasSuffix("." + ext) { p += "." + ext }
        return URL(fileURLWithPath: p)
    }
    private static func defaultPath(_ ed: Editor, _ ext: String, suffix: String = "") -> String {
        let base = ed.fileURL?.deletingPathExtension().path ?? (NSHomeDirectory() + "/Desktop/" + (ed.doc.info.name.isEmpty ? "Drawing" : ed.doc.info.name))
        return base + suffix + "." + ext
    }

    static var all: [CommandDef] {
        [
            // MARK: Navigation (VIS-017/018/019/020/023)
            CommandDef("FLY", aliases: ["FLYMODE", "3DFLYMODE"], category: "View", summary: "Free flight in 3D: W A S D along the view direction, Q/E down/up, drag to look (no gravity or collisions).", modifies: false) { ed in
                let c = try await view3D(ed); c.startNavigation(.fly)
            },
            CommandDef("LOOKAROUND", aliases: ["LOOK", "LOOKAROUNDTOOL"], category: "View", summary: "Looks around from the current eye point (drag or arrow keys turn the head; the camera does not move).", modifies: false) { ed in
                let c = try await view3D(ed); c.startNavigation(.look)
            },
            CommandDef("POSITIONCAMERA", aliases: ["POSCAM", "EYEPOINT"], category: "View", summary: "Places the camera at a plan point at eye height looking towards a second point, then looks around (SketchUp style).", modifies: false) { ed in
                let eye = try await ed.requirePoint("Specify eye position")
                let tgt = try await ed.requirePoint("Specify direction to look", base: eye) { p in [.line(LineGeom(eye, p))] }
                guard eye.distance(to: tgt) > 1e-6 else { throw CommandError.invalid("Pick two different points.") }
                let h = try await number(ed, "Eye height", 1600 / ed.doc.units.mm)
                let c = try await view3D(ed)
                let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
                c.positionCamera(eye: eye * ed.doc.units.mm, target: tgt * ed.doc.units.mm, eyeHeight: h * ed.doc.units.mm, levelElevation: lz)
                c.startNavigation(.look)
                ed.print("Eye at \(fmt(eye.x, 0)),\(fmt(eye.y, 0)), height \(fmt(h, 0)). Drag to look around; Esc exits.")
            },
            CommandDef("TWOPOINT", aliases: ["TWOPOINTPERSPECTIVE", "2PT", "VERTICALS"], category: "View", summary: "Two-point perspective: levels the 3D camera so vertical lines stay vertical, shifting the lens to keep the framing (On/Off).", modifies: false) { ed in
                let c = try await view3D(ed)
                let k = try await ed.getKeyword("Two-point perspective [On/Off]", ["On", "Off"], defaultValue: c.twoPointShift == nil ? "On" : "Off") ?? "On"
                c.setTwoPoint(k == "On")
                ed.print(k == "On" ? "Two-point perspective: verticals are vertical (lens shift \(fmt(Double(c.twoPointShift ?? 0), 3)))." : "Three-point perspective restored.")
            },
            CommandDef("NAVSWHEEL", aliases: ["STEERINGWHEEL", "WHEEL", "SWHEEL"], category: "View", summary: "Steering wheel in 3D: Zoom, Orbit, Pan, Rewind (outer ring), Center, Walk, Up/Down, Look (inner ring).", modifies: false) { ed in
                let c = try await view3D(ed)
                let k = try await ed.getKeyword("Steering wheel [On/Off]", ["On", "Off"], defaultValue: c.showWheel ? "Off" : "On") ?? "On"
                c.showWheel = k == "On"
            },
            // MARK: Lighting (VIS-053/054/055/056/084)
            CommandDef("LIGHT", aliases: ["LIGHTS", "POINTLIGHT", "SPOTLIGHT", "ARTIFICIALLIGHT"], category: "View", summary: "Places point, spot, area, line or IES lights (lumens, colour temperature, beam) that light the 3D view and renders; List, On/Off.") { ed in
                let k = try await ed.getKeyword("Light [Point/Spot/Area/Line/IES/List/On/Off]", ["Point", "Spot", "Area", "Line", "IES", "List", "On", "Off"], defaultValue: "Point") ?? "Point"
                switch k {
                case "List":
                    let ls = SceneLights.all(ed.doc)
                    if ls.isEmpty { ed.print(ed.doc.variable(SceneLights.variable) == "0" ? "Artificial lights are off." : "No lights."); return }
                    for l in ls { ed.print("  #\(l.id) \(l.kind.rawValue) at \(fmt(l.position.x, 0)),\(fmt(l.position.y, 0)),\(fmt(l.position.z, 0)) — \(fmt(l.lumens, 0)) lm, \(fmt(l.cct, 0)) K" + (l.kind == .spot || l.kind == .ies ? ", beam \(fmt(l.beam, 0))°" : "")) }
                    return
                case "On", "Off":
                    ed.doc.setVariable(SceneLights.variable, k == "On" ? "1" : "0"); ed.print("Artificial lights \(k.lowercased()).")
                    return
                default: break
                }
                let kind = SceneLights.Kind(rawValue: k) ?? .point
                let mm = ed.doc.units.mm
                let p = try await ed.requirePoint(kind == .area || kind == .line ? "Specify light centre" : "Specify light location")
                var target: Vec2?
                if kind == .spot || kind == .ies { target = try await ed.requirePoint("Specify target", base: p) { q in [.line(LineGeom(p, q))] } }
                let lz = (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) / mm
                let h = try await number(ed, "Height above level", 2400 / mm)
                var profile: IESProfile?, iesPath: String?
                if kind == .ies {
                    guard let f = try await ed.getString("IES file path"), !f.isEmpty else { return }
                    let pth = (f.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath
                    guard let txt = try? String(contentsOfFile: pth, encoding: .isoLatin1), let pr = IESProfile.parse(txt) else { throw CommandError.invalid("Not an IES (LM-63) file: \(pth)") }
                    profile = pr; iesPath = pth
                    ed.print("IES: \(fmt(pr.maxCandela, 0)) cd peak, \(fmt(pr.declaredLumens ?? pr.integratedLumens, 0)) lm, beam \(fmt(pr.beamAngle, 0))°.")
                }
                let lm = try await number(ed, "Luminous flux (lm)", profile.map { $0.declaredLumens ?? $0.integratedLumens } ?? (kind == .area ? 3000 : 800))
                let cct = try await number(ed, "Colour temperature (K)", 3000)
                var beam = profile?.beamAngle ?? 60, size = Vec2(600, 600)
                if kind == .spot { beam = try await number(ed, "Beam angle (degrees)", 45) }
                if kind == .area { size = Vec2(try await number(ed, "Width", 600 / mm) * mm, try await number(ed, "Length", 600 / mm) * mm) }
                if kind == .line { size = Vec2(20, try await number(ed, "Length", 1200 / mm) * mm) }
                guard lm >= 0, cct >= 1000, cct <= 20000, beam > 0, beam <= 179 else { throw CommandError.invalid("Values out of range.") }
                let z = (lz + h) * mm
                let l = SceneLights.Light(id: 0, kind: kind, position: Vec3(p.x, p.y, z), target: target.map { Vec3($0.x, $0.y, lz * mm) }, lumens: lm, cct: cct,
                                          beam: min(max(beam, 1), 170), size: size, ies: iesPath, on: true)
                ed.doc.ensureLayer(SceneLights.layer)
                let id = ed.doc.add(SceneLights.entity(l))
                ed.print("\(kind.rawValue) light #\(id): \(fmt(lm, 0)) lm, \(fmt(cct, 0)) K.")
            },
            CommandDef("FOG", aliases: ["ATMOSPHERE", "HAZE", "RENDERENVIRONMENT"], category: "View", summary: "Fog / atmospheric haze in the 3D view and renders: On/Off, start and end distance, colour and falloff (saved in the drawing).") { ed in
                var f = FogSettings.load(ed.doc)
                let k = try await ed.getKeyword("Fog [On/Off/Settings]", ["On", "Off", "Settings"], defaultValue: f.on ? "Settings" : "On") ?? "On"
                if k == "Off" { f.on = false; f.store(&ed.doc); ed.print("Fog off."); return }
                f.on = true
                if k == "Settings" || k == "On" {
                    let mm = ed.doc.units.mm
                    f.start = try await number(ed, "Fog starts at distance", f.start / mm) * mm
                    f.end = max(f.start + 1, try await number(ed, "Fully opaque at distance", f.end / mm) * mm)
                    if let c = try await AppCommandsNav.word(ed, "Colour (#RRGGBB) <\(f.color.hex)>"), c.hasPrefix("#"), c.count == 7 { f.color = RGBA(hex: c) }
                    f.density = min(max(try await number(ed, "Falloff exponent (1 linear, 2 quadratic)", f.density), 0.1), 4)
                }
                f.store(&ed.doc)
                ed.print("Fog from \(fmt(f.start / ed.doc.units.mm, 0)) to \(fmt(f.end / ed.doc.units.mm, 0)), \(f.color.hex).")
            },
            CommandDef("MATEMISSIVE", aliases: ["EMISSIVE", "SELFILLUM", "MATEMIT"], category: "View", summary: "Makes a material self-illuminated (luminance factor 0–20; 0 turns it off): screens, lamps, signs glow in 3D and renders.") { ed in
                let names = ed.doc.materials.map(\.name)
                guard !names.isEmpty else { throw CommandError.invalid("The drawing has no materials.") }
                ed.print("Materials: " + names.joined(separator: ", "))
                guard let n = try await AppCommandsNav.word(ed, "Material name"), let mat = ed.doc.material(n.trimmingCharacters(in: .whitespaces)) else { throw CommandError.invalid("No such material.") }
                let v = try await number(ed, "Luminance factor", Emissive.strength(mat.name, doc: ed.doc) > 0 ? Emissive.strength(mat.name, doc: ed.doc) : 2)
                guard v >= 0, v <= 20 else { throw CommandError.invalid("Use 0–20.") }
                if v == 0 { ed.doc.variables[Emissive.key(mat.name)] = nil } else { ed.doc.setVariable(Emissive.key(mat.name), fmt(v)) }
                ed.print(v == 0 ? "\(mat.name) is no longer emissive." : "\(mat.name) glows with factor \(fmt(v)).")
            },
            CommandDef("MATMAPPING", aliases: ["TEXTUREMAPPING", "UVMAPPING", "MATERIALMAPPING", "POSITIONTEXTURE"], category: "View", summary: "Texture mapping of a material: Box, Planar, Cylindrical, Spherical or UV, and texture positioning (offset, rotation, scale) on its faces; Reset.") { ed in
                let names = ed.doc.materials.map(\.name)
                guard !names.isEmpty else { throw CommandError.invalid("The drawing has no materials.") }
                guard let n = try await AppCommandsNav.word(ed, "Material name"), let mat = ed.doc.material(n) else { throw CommandError.invalid("No such material.") }
                var st = TextureMapping.settings(mat.name, doc: ed.doc)
                let modes = TextureMapping.Mode.allCases.map(\.rawValue)
                let k = try await ed.getKeyword("Mapping [\(modes.joined(separator: "/"))/Reset]", modes + ["Reset"], defaultValue: st.mode.rawValue) ?? st.mode.rawValue
                if k == "Reset" { TextureMapping.store(TextureMapping.Settings(), material: mat.name, in: &ed.doc); ed.print("\(mat.name): default box mapping."); return }
                st.mode = TextureMapping.Mode(rawValue: k) ?? .box
                let mm = ed.doc.units.mm
                st.offset = Vec2(try await number(ed, "Offset X", st.offset.x / mm) * mm, try await number(ed, "Offset Y", st.offset.y / mm) * mm)
                st.rotation = try await number(ed, "Rotation (degrees)", st.rotation)
                st.scale = try await number(ed, "Scale factor", st.scale)
                guard st.scale > 0 else { throw CommandError.invalid("The scale must be positive.") }
                TextureMapping.store(st, material: mat.name, in: &ed.doc)
                ed.print("\(mat.name): \(st.mode.rawValue) mapping, offset \(fmt(st.offset.x / mm)),\(fmt(st.offset.y / mm)), rotation \(fmt(st.rotation))°, scale \(fmt(st.scale)).")
            },
            CommandDef("BILLBOARD", aliases: ["CUTOUT", "IMAGECUTOUT", "ENTOURAGE"], category: "View", summary: "Places a 2D cutout that always faces the camera in 3D and renders: Person, Tree, Shrub or an image file (PNG with transparency).") { ed in
                let k = try await ed.getKeyword("Cutout [Person/Tree/Shrub/File]", ["Person", "Tree", "Shrub", "File"], defaultValue: "Person") ?? "Person"
                var src = k.lowercased()
                if k == "File" {
                    guard let f = try await ed.getString("Image file path"), !f.isEmpty else { return }
                    src = (f.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath
                    guard NSImage(contentsOfFile: src) != nil else { throw CommandError.invalid("Cannot read image \(src).") }
                }
                let p = try await ed.requirePoint("Specify base point")
                let mm = ed.doc.units.mm
                let def = (k == "Tree" ? 6000 : k == "Shrub" ? 1200 : 1750) / mm
                let h = try await number(ed, "Height", def)
                guard h > 0 else { throw CommandError.invalid("Height must be positive.") }
                let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
                ed.doc.ensureLayer(Billboards.layer)
                let id = ed.doc.add(Billboards.entity(source: src, at: Vec3(p.x, p.y, lz), height: h * mm))
                ed.print("Billboard #\(id) (\(k.lowercased()), \(fmt(h, 0)) high).")
            },
            // MARK: Output (SHT-024/025/039, VIS-087)
            CommandDef("EXPORTPDF", aliases: ["PDFEXPORT", "PDFOUT", "LAYEREDPDF"], category: "Output", summary: "Vector PDF with one PDF layer (OCG) per drawing layer, searchable text and hyperlinks: current sheet, model or all sheets, at true scale.", modifies: false) { ed in
                let m = AppCommands.model(ed)
                let hasSheets = !ed.doc.layouts.isEmpty
                let def = m?.mode == .sheet && hasSheets ? "Current" : "Model"
                let k = try await ed.getKeyword("Export [Current/Model/All]", ["Current", "Model", "All"], defaultValue: def) ?? def
                var pages: [LayeredPDF.Page] = []
                var note = ""
                switch k {
                case "All":
                    guard hasSheets else { throw CommandError.invalid("The drawing has no sheets.") }
                    pages = ed.doc.layouts.indices.compactMap { LayeredPDF.sheetPage(doc: ed.doc, layoutIndex: $0) }
                case "Current":
                    guard hasSheets else { throw CommandError.invalid("The drawing has no sheets.") }
                    let li = AppCommandsNav.sheetIndex(ed) ?? 0
                    if let p = LayeredPDF.sheetPage(doc: ed.doc, layoutIndex: li) { pages = [p] }
                default:
                    let (p, ratio) = LayeredPDF.modelPage(doc: ed.doc, level: ed.doc.currentLevel)
                    pages = [p]; note = " at 1:\(fmt(ratio, 0))"
                }
                if LayerNotify.isOn(ed.doc), !LayerNotify.unreconciled(ed.doc).isEmpty { ed.print("⚠ Plotting with unreconciled layers: \(LayerNotify.unreconciled(ed.doc).joined(separator: ", ")).") }
                guard let url = try await path(ed, "PDF file", ext: "pdf", def: defaultPath(ed, "pdf")) else { return }
                let o = try LayeredPDF.write(doc: ed.doc, pages: pages, title: ed.doc.info.name, to: url)
                PlotLog.record(drawing: ed.doc.info.name, output: "Layered PDF\(note)", sheets: pages.map(\.name).joined(separator: ", "), style: "OCG", file: url.path)
                ed.print("\(pages.count) page(s)\(note), \(o.layers.count) PDF layer(s), \(o.links) link(s): \(url.path)")
            },
            CommandDef("TITLEBLOCKDESIGN", aliases: ["TBDESIGN", "CUSTOMTITLEBLOCK", "TITLEBLOCKBLOCK"], category: "Output", summary: "Custom title blocks: Create a starter block (edit it with BEDIT: lines, logo images, {field} texts or attributes), Use a block on all or the current sheet, or go back to the Builtin one.") { ed in
                let k = try await ed.getKeyword("Title block [Create/Use/Builtin/Fields]", ["Create", "Use", "Builtin", "Fields"], defaultValue: "Create") ?? "Create"
                switch k {
                case "Fields":
                    ed.print("Fields: " + CustomTitleBlock.fieldNames.map { "{\($0)}" }.joined(separator: " ") + " and custom fields (SHEETFIELD). Attribute tags with these names work too.")
                    return
                case "Builtin":
                    for key in ed.doc.variables.keys where key.hasPrefix(CustomTitleBlock.variable) { ed.doc.variables[key] = nil }
                    ed.print("Built-in title block on all sheets.")
                    return
                case "Create":
                    if ed.doc.blocks[CustomTitleBlock.starterName] == nil { ed.doc.blocks[CustomTitleBlock.starterName] = CustomTitleBlock.starter() }
                    ed.doc.setVariable(CustomTitleBlock.variable, CustomTitleBlock.starterName)
                    ed.print("Block \(CustomTitleBlock.starterName) is the title block of all sheets. Edit it with BEDIT \(CustomTitleBlock.starterName).")
                default:
                    guard let n = try await AppCommandsNav.word(ed, "Block name"), let name = ed.doc.blocks.keys.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("No such block.") }
                    let scope = try await ed.getKeyword("Apply to [All/Current]", ["All", "Current"], defaultValue: "All") ?? "All"
                    if scope == "Current", let li = AppCommandsNav.sheetIndex(ed) {
                        ed.doc.setVariable(CustomTitleBlock.variable + ":" + ed.doc.layouts[li].name.uppercased(), name)
                        ed.print("\(name) is the title block of \(ed.doc.layouts[li].name).")
                    } else {
                        ed.doc.setVariable(CustomTitleBlock.variable, name)
                        ed.print("\(name) is the title block of all sheets.")
                    }
                }
            },
            CommandDef("SHADEPLOT", aliases: ["VPSHADEPLOT", "VIEWPORTSHADE"], category: "Output", summary: "Shade plot of a 3D (axonometric / perspective) sheet viewport: As Displayed, Wireframe, Hidden or Rendered, and the saved 3D view it shows.") { ed in
                guard let li = AppCommandsNav.sheetIndex(ed) else { throw CommandError.invalid("The drawing has no sheets.") }
                let layout = ed.doc.layouts[li]
                let threeD = layout.viewports.indices.filter { ShadePlot.is3D(layout.viewports[$0]) }
                guard !threeD.isEmpty else { throw CommandError.invalid("\(layout.name) has no axonometric or perspective viewport (MVIEW, then set its view).") }
                let def = (AppCommands.model(ed)?.selectedSheetViewport).flatMap { threeD.contains($0) ? $0 + 1 : nil } ?? threeD[0] + 1
                guard let n = try await ed.getInteger("Viewport number (\(threeD.map { String($0 + 1) }.joined(separator: ", ")))", defaultValue: def), threeD.contains(n - 1) else { throw CommandError.invalid("Not a 3D viewport.") }
                let cur = ShadePlot.mode(ed.doc, layout.viewports[n - 1])
                let names = ShadePlot.Mode.allCases.map { $0.rawValue.replacingOccurrences(of: " ", with: "") }
                let k = try await ed.getKeyword("Shade plot [\(names.joined(separator: "/"))/Camera]", names + ["Camera"], defaultValue: cur.rawValue.replacingOccurrences(of: " ", with: "")) ?? "Hidden"
                if k == "Camera" {
                    let views = ed.doc.views.filter { $0.kind == "3d" && $0.camera != nil }.map(\.name) + ed.doc.namedViews.filter { $0.camera != nil }.map(\.name)
                    ed.print("3D views: " + (views.isEmpty ? "none (CAMERAVIEW, AXONVIEW or SAVECAMERA)" : views.joined(separator: ", ")))
                    guard let v = try await ed.getString("3D view name (Enter for the default isometric)", defaultValue: ""), !v.isEmpty else { ed.doc.variables[ShadePlot.cameraKey(layout.name, n - 1)] = nil; return }
                    guard views.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else { throw CommandError.invalid("No 3D view \(v).") }
                    ed.doc.setVariable(ShadePlot.cameraKey(layout.name, n - 1), v)
                    ed.print("Viewport \(n) shows \(v).")
                    return
                }
                let mode = ShadePlot.Mode.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "") == k } ?? .hidden
                ShadePlot.setMode(mode, layout: layout.name, index: n - 1, &ed.doc)
                ed.print("Viewport \(n) of \(layout.name): shade plot \(mode.rawValue).")
            },
            CommandDef("WEBVIEWEREXPORT", aliases: ["WEBEXPORT", "EXPORTWEB", "WEBVIEWER"], category: "Output", summary: "Exports the 3D model as one standalone HTML file with a WebGL viewer (orbit, pan, zoom, views) that opens in any browser.", modifies: false) { ed in
                let s = WebViewerExport.scene(doc: ed.doc)
                guard s.triangles > 0 else { throw CommandError.invalid("The model has no 3D content.") }
                guard let url = try await path(ed, "HTML file", ext: "html", def: defaultPath(ed, "html", suffix: "-3D")) else { return }
                try WebViewerExport.html(doc: ed.doc).write(to: url, atomically: true, encoding: .utf8)
                ed.print("Web viewer: \(s.batches.count) material(s), \(s.triangles) triangles → \(url.path)")
            },
            CommandDef("RENDERTOFILE", aliases: ["RENDERFILE", "RENDEROUT", "RENDERPASS"], category: "View", summary: "Renders to an image file: any size up to 7680×4320 (tiled), a pass (Beauty, Alpha, Depth, Normal, Material ID), a style (Photographic, Sketch, Watercolour) and an optional region of the frame.", modifies: false) { ed in
                let res = try await AppCommandsNav.word(ed, "Resolution WxH (up to 7680x4320) <1920x1080>") ?? "1920x1080"
                let wh = res.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard wh.count == 2, wh[0] >= 16, wh[1] >= 16, wh[0] <= Int(RenderEngine.maxSize.width), wh[1] <= Int(RenderEngine.maxSize.height) else { throw CommandError.invalid("Use a size from 16x16 to 7680x4320.") }
                let passes = RenderPass.allCases.map { $0.rawValue.replacingOccurrences(of: " ", with: "") }
                let k = try await ed.getKeyword("Pass [\(passes.joined(separator: "/"))]", passes, defaultValue: "Beauty") ?? "Beauty"
                let pass = RenderPass.allCases.first { $0.rawValue.replacingOccurrences(of: " ", with: "") == k } ?? .beauty
                var npr = NPRStyle.photo
                if pass == .beauty { npr = NPRStyle(rawValue: try await ed.getKeyword("Style [Photographic/Sketch/Watercolour]", NPRStyle.allCases.map(\.rawValue), defaultValue: "Photographic") ?? "Photographic") ?? .photo }
                let rg = try await AppCommandsNav.word(ed, "Region x0,y0,x1,y1 as fractions of the frame (top-left origin) or Enter for all") ?? ""
                var region: CGRect?
                let r = rg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if r.count == 4 {
                    guard r[2] > r[0], r[3] > r[1], r.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { throw CommandError.invalid("Region fractions must be 0–1 with x1 > x0 and y1 > y0.") }
                    region = CGRect(x: r[0], y: r[1], width: r[2] - r[0], height: r[3] - r[1])
                }
                guard let url = try await path(ed, "PNG file", ext: "png", def: defaultPath(ed, "png", suffix: pass == .beauty ? "-render" : "-" + k.lowercased())) else { return }
                var st = RenderSettings()
                if let pr = RenderPreset.all.first(where: { $0.name == UserDefaults.standard.string(forKey: "render.lastPreset") }) { pr.apply(to: &st) }
                st.width = wh[0]; st.height = wh[1]
                guard let img = npr != .photo ? RenderEngine.renderNPR(doc: ed.doc, settings: st, style: npr) : RenderEngine.renderAdvanced(doc: ed.doc, settings: st, pass: pass, region: region),
                      let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { throw CommandError.invalid("Rendering failed (Metal unavailable).") }
                try png.write(to: url)
                ed.print("\(pass.rawValue) \(rep.pixelsWide)×\(rep.pixelsHigh)\(region == nil ? "" : " (region of \(wh[0])×\(wh[1]))") → \(url.path)")
                if pass == .materialID { for (n, c) in RenderEngine.materialIDColors(ed.doc) { ed.print("  \(c.hex)  \(n)") } }
            },
            CommandDef("STEREOPANORAMA", aliases: ["STEREO360", "ODSPANORAMA", "VRPANORAMA"], category: "View", summary: "Stereo 360° panorama for VR viewers: left and right eye equirectangular images over-under (omni-directional stereo), from the 3D camera or a plan point.", modifies: false) { ed in
                let m = AppCommands.model(ed)
                let k = try await ed.getKeyword("Eye position [Camera/Point]", ["Camera", "Point"], defaultValue: m?.viewport3D == nil ? "Point" : "Camera") ?? "Camera"
                var eye: Vec3
                if k == "Point" {
                    let p = try await ed.requirePoint("Eye position in plan")
                    eye = Vec3(p.x, p.y, (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) + 1600 / max(ed.doc.units.mm, 1e-9))
                } else {
                    guard let c = m?.viewport3D?.currentCamera else { throw CommandError.invalid("Open the 3D view first, or use Point.") }
                    eye = c.eye
                }
                guard let w = try await ed.getInteger("Width in pixels (each eye is width × width/2) <4096>", defaultValue: 4096), w >= 256 else { return }
                let ipd = try await number(ed, "Eye separation (interpupillary distance)", 64 / ed.doc.units.mm)
                guard let url = try await path(ed, "Image file (.jpg/.png)", ext: "jpg", def: defaultPath(ed, "jpg", suffix: "-360-stereo")) else { return }
                guard let img = RenderEngine.stereoPanorama(doc: ed.doc, settings: RenderSettings(), eye: eye, width: min(w, 8192), ipd: ipd) else { throw CommandError.invalid("Rendering failed (Metal unavailable).") }
                try RenderEngine.write(img, to: url)
                ed.print("Saved \(img.width)×\(img.height) stereo panorama (left eye on top) to \(url.path)")
            },
            CommandDef("PHASEANIMATION", aliases: ["PHASEVIDEO", "4DVIDEO", "4DANIMATION"], category: "View", summary: "Construction sequence (4D) video from the phases (new elements appear bottom-up, demolished ones disappear) or from the work schedule (day by day), captioned (MP4).", modifies: false) { ed in
                let hasSchedule = Scheduler.load(ed.doc) != nil, hasPhases = Phasing.isActive(ed.doc) && !ed.doc.phases.isEmpty
                guard hasSchedule || hasPhases else { throw CommandError.invalid("No phased elements and no work schedule (PHASE / WORKSCHEDULE Generate).") }
                let src = try await ed.getKeyword("Sequence from [Phases/Schedule]", ["Phases", "Schedule"], defaultValue: hasSchedule ? "Schedule" : "Phases") ?? "Phases"
                let secs = try await number(ed, src == "Schedule" ? "Seconds per working day" : "Seconds per phase", src == "Schedule" ? 0.5 : 4)
                guard secs > 0, secs <= 120 else { throw CommandError.invalid("Use 0–120 s.") }
                guard let url = try await path(ed, "Video file", ext: "mp4", def: defaultPath(ed, "mp4", suffix: "-4D")) else { return }
                var st = RenderSettings(); st.width = 1280; st.height = 720
                let cam = AppCommands.model(ed)?.viewport3D?.currentCamera
                if src == "Schedule" { try await PhasingAnimation.scheduleVideo(doc: ed.doc, settings: st, secondsPerDay: secs, camera: cam, to: url) { _ in } }
                else {
                    guard hasPhases else { throw CommandError.invalid("No phased elements.") }
                    try await PhasingAnimation.video(doc: ed.doc, settings: st, secondsPerPhase: secs, camera: cam, to: url) { _ in }
                }
                ed.print("4D video (\(src.lowercased())) → \(url.path)")
            },
            CommandDef("HYPERLINK", aliases: ["LINK", "URL", "-HYPERLINK"], category: "Annotate", summary: "Attaches a URL (web page or file) to objects; exported PDFs make them clickable. Empty removes the link.") { ed in
                let ids = try await ed.getSelection("Select objects")
                guard !ids.isEmpty else { return }
                let cur = ids.lazy.compactMap { ed.doc.entity($0)?.props["hyperlink"] ?? ed.doc.element($0)?.props["hyperlink"] }.first ?? ""
                guard let u = try await ed.getString("Enter hyperlink (URL) <\(cur)>", defaultValue: cur) else { return }
                let url = u.trimmingCharacters(in: .whitespaces)
                for id in ids {
                    if let i = ed.doc.entities.firstIndex(where: { $0.id == id }) { ed.doc.entities[i].props["hyperlink"] = url.isEmpty ? nil : url }
                    if let i = ed.doc.elementIndex(id) { ed.doc.elements[i].props["hyperlink"] = url.isEmpty ? nil : url }
                }
                ed.print(url.isEmpty ? "Hyperlink removed from \(ids.count) object(s)." : "\(ids.count) object(s) link to \(url).")
            },
            // MARK: Assistant and render prompts (SCR-027/032/035)
            CommandDef("ASSISTANT", aliases: ["AI", "AICHAT", "CHAT", "ASKAI"], category: "Scripting", summary: "AI assistant panel: Claude or a local model (Ollama) edits the drawing with commands; bulk changes ask for confirmation; everything is undoable.", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Assistant [Panel/Ask]", ["Panel", "Ask"], defaultValue: "Panel") ?? "Panel"
                AssistantWindow.show(model: m)
                if k == "Ask", let q = try await ed.getString("Ask the assistant"), !q.isEmpty { AssistantWindow.session(m).send(q) }
            },
            CommandDef("RENDERPROMPT", aliases: ["AIRENDER", "RENDERSTYLE", "PROMPTRENDER"], category: "View", summary: "Styles the render from a description (e.g. “golden hour, soft shadows, warm, 4K”): saves it as the “Prompt” render preset and opens the render window.", modifies: false) { ed in
                guard let text = try await ed.getString("Describe the render"), !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                var s = RenderSettings()
                let applied = RenderPrompt.apply(text, to: &s)
                guard !applied.isEmpty else { throw CommandError.invalid("No render style recognised (try: sunset, overcast, night, clay, soft shadows, warm, moody, depth of field, 4K).") }
                var p = RenderPreset.from(s, name: "Prompt: " + String(text.prefix(40)))
                p.hour = Double(Calendar.current.component(.hour, from: s.date)) + Double(Calendar.current.component(.minute, from: s.date)) / 60
                var custom = RenderPreset.custom.filter { !$0.name.hasPrefix("Prompt: ") }
                custom.append(p); RenderPreset.custom = custom
                UserDefaults.standard.set(p.name, forKey: "render.lastPreset")
                ed.print("Render style: " + applied.joined(separator: ", ") + ".")
                if let m = AppCommands.model(ed), !AppSelfTests.headless { RenderController.renderImage(model: m) }
            },
            CommandDef("GRAPHPLAYER", aliases: ["PLAYER", "RUNGRAPH", "PLAYGRAPH"], category: "Scripting", summary: "Graph player: runs a saved node graph with its exposed Number inputs (clamped to their ranges) and bakes the result; Window opens the player panel.") { ed in
                let all = GraphPlayer.graphs(ed.doc)
                guard !all.isEmpty else { throw CommandError.invalid("No saved node graphs (NODEEDITOR).") }
                ed.print("Graphs: " + all.map(\.name).joined(separator: ", "))
                let n = try await AppCommandsNav.word(ed, "Graph name or Window <\(all[0].name)>") ?? all[0].name
                if n.caseInsensitiveCompare("Window") == .orderedSame || n.caseInsensitiveCompare("W") == .orderedSame { GraphPlayerWindow.show(model: try ui(ed)); return }
                guard let g = all.first(where: { $0.name.caseInsensitiveCompare(n.trimmingCharacters(in: .whitespaces)) == .orderedSame })?.graph else { throw CommandError.invalid("No graph \(n).") }
                var values: [String: Double] = [:]
                for inp in GraphPlayer.inputs(g) {
                    values[inp.name] = try await ed.getDistance("\(inp.name) (\(fmt(inp.min)) – \(fmt(inp.max))) <\(fmt(inp.value))>", defaultValue: inp.value).value ?? inp.value
                }
                let r = GraphPlayer.run(g, values: values, into: &ed.doc)
                for (id, e) in r.errors { ed.print("  node \(id): \(e)") }
                ed.print("Baked \(r.ids.count) object(s).")
            },
            // MARK: UI (APP-002, APP-022)
            CommandDef("SYSWINDOWS", aliases: ["ARRANGEWINDOWS", "TILEWINDOWS", "WINDOWS"], category: "View", summary: "Arranges the open drawing windows: Vertical (side by side), Horizontal, Cascade, Tabs or Separate windows.", modifies: false) { ed in
                let k = try await ed.getKeyword("Arrange [Vertical/Horizontal/Cascade/Tabs/Separate]", ["Vertical", "Horizontal", "Cascade", "Tabs", "Separate"], defaultValue: "Vertical") ?? "Vertical"
                let wins = AppModel.all.compactMap(\.window)
                guard !wins.isEmpty else { throw CommandError.invalid("No document windows.") }
                switch k {
                case "Tabs":
                    guard let first = wins.first else { return }
                    for w in wins.dropFirst() where w.tabGroup !== first.tabGroup { first.addTabbedWindow(w, ordered: .above) }
                case "Separate":
                    for w in wins where (w.tabbedWindows?.count ?? 0) > 1 { w.moveTabToNewWindow(nil) }
                default:
                    for w in wins where (w.tabbedWindows?.count ?? 0) > 1 { w.moveTabToNewWindow(nil) }
                    guard let screen = (NSApp.keyWindow ?? wins[0]).screen ?? NSScreen.main else { return }
                    let frames = WindowArrangement.frames(count: wins.count, in: screen.visibleFrame, mode: WindowArrangement.Mode(rawValue: k) ?? .vertical)
                    for (w, f) in zip(wins, frames) { if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }; w.setFrame(f, display: true, animate: false); w.orderFront(nil) }
                }
                ed.print("\(wins.count) window(s) arranged: \(k.lowercased()).")
            },
            CommandDef("RADIALMENU", aliases: ["MARKINGMENU", "PIEMENU"], category: "View", summary: "Right-drag marking menu with the 8 most used commands for the context (On/Off/List).", modifies: false) { ed in
                let k = try await ed.getKeyword("Marking menu [On/Off/List]", ["On", "Off", "List"], defaultValue: "List") ?? "List"
                if k == "List" {
                    let c = RadialMenu.context(ed.doc, selection: ed.selection)
                    ed.print("Marking menu (\(RadialMenu.enabled ? "on" : "off")), \(c.rawValue): " + RadialMenu.items(c).map(\.command).joined(separator: ", "))
                } else { RadialMenu.enabled = k == "On"; ed.print("Marking menu \(k.lowercased()): right-drag in the drawing.") }
            },
        ]
    }
}
