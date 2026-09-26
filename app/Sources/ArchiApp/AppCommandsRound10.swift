// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import SceneKit
import ArchiCore

/// Commands of round 10: path tracer, denoiser and light mix, PBR maps, material assets, procedural and photo
/// materials, weather and seasons, water, scatter vegetation, object animation, SpaceMouse and ribbon customisation.
@MainActor
enum AppCommandsRound10 {
    private static func ui(_ ed: Editor) throws -> AppModel {
        guard let m = AppCommands.model(ed) else { throw CommandError.invalid("This command needs a document window.") }
        return m
    }
    private static func number(_ ed: Editor, _ msg: String, _ def: Double) async throws -> Double {
        try await ed.getDistance("\(msg) <\(fmt(def))>", defaultValue: def).value ?? def
    }
    private static func text(_ ed: Editor, _ msg: String, _ def: String) async throws -> String {
        let s = try await ed.getString("\(msg) <\(def)>", defaultValue: def) ?? def
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return t.isEmpty ? def : t
    }
    private static func fileURL(_ ed: Editor, _ msg: String, ext: String, def: String) async throws -> URL {
        var p = (try await text(ed, msg, def) as NSString).expandingTildeInPath
        if (p as NSString).pathExtension.isEmpty { p += "." + ext }
        return URL(fileURLWithPath: p)
    }
    private static func materialName(_ ed: Editor, _ msg: String = "Material name") async throws -> String {
        let def = ed.doc.materials.first?.name ?? "Concrete"
        let n = try await text(ed, msg, def)
        guard let m = ed.doc.materials.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) else { throw CommandError.invalid("No material named \(n).") }
        return m.name
    }
    private static func defaultPath(_ ed: Editor, _ suffix: String, _ ext: String) -> String {
        (ed.fileURL?.deletingPathExtension().path ?? (NSHomeDirectory() + "/Desktop/" + (ed.doc.info.name.isEmpty ? "Drawing" : ed.doc.info.name))) + suffix + "." + ext
    }
    /// Closed boundaries from selected closed polylines/circles (drawing units → mm).
    private static func boundaries(_ ed: Editor, _ ids: [EntityID]) -> [[Vec2]] {
        let ents: [Entity] = ids.compactMap { ed.doc.entity($0) }
        return ents.compactMap { (e: Entity) -> [Vec2]? in
            switch e.geometry {
            case .polyline(let p) where p.closed || (p.vertices.count > 3 && p.vertices[0].p.isClose(p.vertices[p.vertices.count - 1].p, tol: 1e-6)):
                return GeometryOps.tessellate(e.geometry, doc: ed.doc).first
            case .circle, .ellipse:
                return GeometryOps.tessellate(e.geometry, doc: ed.doc).first
            default: return nil
            }
        }.filter { $0.count >= 3 }
    }

    /// Light mix weights saved in the drawing (LIGHTMIX = "sun,sky,artificial").
    static func lightMix(_ doc: ArchiDocument) -> PTLightMix {
        var m = PTLightMix()
        let v = (doc.variable("LIGHTMIX") ?? "").split(separator: ",").compactMap { Float($0) }
        if v.count == 3 { m.sun = v[0]; m.sky = v[1]; m.artificial = v[2] }
        return m
    }

    static var all: [CommandDef] {
        [
            // MARK: Path tracer, denoiser, light mix (VIS-070/071/078)
            CommandDef("PATHTRACE", aliases: ["PTRENDER", "RENDERPT", "PATHTRACER", "RAYTRACE"], category: "View", summary: "Progressive path-traced render of the 3D view (GGX materials, glass refraction, PBR maps, sun, sky, lights): Window, or File with size, samples and denoising.", modifies: false) { ed in
                let m = try ui(ed)
                let k = try await ed.getKeyword("Path trace [Window/File]", ["Window", "File"], defaultValue: "Window") ?? "Window"
                if k == "Window" { PathTraceWindow.show(model: m); PathTraceWindow.controller?.mix = lightMix(ed.doc); return }
                let url = try await fileURL(ed, "Image file", ext: "png", def: defaultPath(ed, " path traced", "png"))
                let w = Int(try await number(ed, "Width (px)", 1280)), h = Int(try await number(ed, "Height (px)", 720))
                let spp = Int(try await number(ed, "Samples per pixel", 64))
                let dn = (try await ed.getKeyword("Denoise [Yes/No]", ["Yes", "No"], defaultValue: "Yes") ?? "Yes") == "Yes"
                guard w >= 8, h >= 8, w <= 8192, h <= 8192, spp >= 1, spp <= 100_000 else { throw CommandError.invalid("Size 8–8192 px and 1+ samples.") }
                let r = try await PathTraceFile.render(doc: ed.doc, camera: Viewport3DController.active?.currentCamera, width: w, height: h, samples: spp, denoise: dn, mix: lightMix(ed.doc), to: url)
                ed.print("Path traced \(w)×\(h), \(r.samples) samples\(dn ? ", denoised" : "") in \(fmt(r.seconds, 1)) s → \(url.path)")
            },
            CommandDef("LIGHTMIX", aliases: ["LIGHTGROUPS", "RENDERLIGHTMIX"], category: "View", summary: "Light mix of path-traced renders: weights of the Sun, Sky and Artificial light groups, changeable after rendering (saved in the drawing).") { ed in
                var mix = lightMix(ed.doc)
                mix.sun = Float(try await number(ed, "Sun weight", Double(mix.sun)))
                mix.sky = Float(try await number(ed, "Sky weight", Double(mix.sky)))
                mix.artificial = Float(try await number(ed, "Artificial lights weight", Double(mix.artificial)))
                guard [mix.sun, mix.sky, mix.artificial].allSatisfy({ $0 >= 0 && $0 <= 100 }) else { throw CommandError.invalid("Weights 0–100.") }
                ed.doc.setVariable("LIGHTMIX", "\(fmt(Double(mix.sun), 3)),\(fmt(Double(mix.sky), 3)),\(fmt(Double(mix.artificial), 3))")
                PathTraceWindow.controller?.mix = mix
                ed.print("Light mix: sun \(fmt(Double(mix.sun), 2)), sky \(fmt(Double(mix.sky), 2)), artificial \(fmt(Double(mix.artificial), 2)).")
            },
            // MARK: Materials (VIS-060/061/066/067/068)
            CommandDef("MATMAPS", aliases: ["PBRMAPS", "MATERIALMAPS"], category: "View", summary: "PBR texture maps of a material: Normal, Roughness, Metallic, AO and Displacement images, normal strength and displacement height; List/Clear.") { ed in
                let name = try await materialName(ed)
                var maps = MaterialMaps.load(name, doc: ed.doc)
                let k = try await ed.getKeyword("Map [Normal/Roughness/Metallic/AO/Displacement/Strength/Height/List/Clear]", ["Normal", "Roughness", "Metallic", "AO", "Displacement", "Strength", "Height", "List", "Clear"], defaultValue: "List") ?? "List"
                switch k {
                case "List":
                    ed.print("\(name): albedo \(ed.doc.material(name)?.texture ?? "—")")
                    for s in MaterialMaps.slots { ed.print("  \(s.title): \(maps[keyPath: s.key] ?? "—")") }
                    ed.print("  Normal strength \(fmt(maps.normalStrength, 2)), displacement \(fmt(maps.displacementScale, 1)) mm")
                    return
                case "Clear": maps = MaterialMaps()
                case "Strength": maps.normalStrength = max(0, try await number(ed, "Normal strength", maps.normalStrength))
                case "Height": maps.displacementScale = max(0, try await number(ed, "Displacement height (mm)", maps.displacementScale))
                default:
                    guard let slot = MaterialMaps.slots.first(where: { $0.title == k }) else { return }
                    let p = try await text(ed, "\(k) image path (. = none)", maps[keyPath: slot.key] ?? ".")
                    if p == "." { maps[keyPath: slot.key] = nil } else {
                        let full = (p as NSString).expandingTildeInPath
                        guard MaterialTextures.url(full).map({ FileManager.default.fileExists(atPath: $0.path) }) ?? false || FileManager.default.fileExists(atPath: full) else { throw CommandError.invalid("File not found: \(full)") }
                        maps[keyPath: slot.key] = full
                        if k == "Displacement" && maps.displacementScale == 0 { maps.displacementScale = 5 }
                    }
                }
                MaterialMaps.store(maps, material: name, in: &ed.doc)
                ed.print("\(name): PBR maps updated.")
            },
            CommandDef("MATASSET", aliases: ["MATERIALASSETS", "MATIDENTITY", "MATPHYSICAL"], category: "View", summary: "Material assets kept apart from the render appearance: Identity (description, manufacturer, mark, cost), Graphics (shading colour, surface pattern) and Physical/thermal (density, conductivity, specific heat); List.") { ed in
                let name = try await materialName(ed)
                var a = MaterialAssetSet.load(name, doc: ed.doc)
                let k = try await ed.getKeyword("Asset [Identity/Graphics/Physical/List]", ["Identity", "Graphics", "Physical", "List"], defaultValue: "List") ?? "List"
                switch k {
                case "Identity":
                    a.description = try await text(ed, "Description", a.description.isEmpty ? name : a.description)
                    a.manufacturer = try await text(ed, "Manufacturer (. = none)", a.manufacturer.isEmpty ? "." : a.manufacturer); if a.manufacturer == "." { a.manufacturer = "" }
                    a.mark = try await text(ed, "Mark (. = none)", a.mark.isEmpty ? "." : a.mark); if a.mark == "." { a.mark = "" }
                    let c = try await number(ed, "Cost per unit (0 = none)", a.cost ?? 0); a.cost = c > 0 ? c : nil
                case "Graphics":
                    let own = try await ed.getKeyword("Shaded views use [Render/Own] colour", ["Render", "Own"], defaultValue: a.useRenderAppearance ? "Render" : "Own") ?? "Render"
                    a.useRenderAppearance = own == "Render"
                    if !a.useRenderAppearance {
                        let h = try await text(ed, "Shading colour (#RRGGBB)", a.shadingColor ?? (ed.doc.material(name)?.color.hexRGB ?? "#CCCCCC"))
                        guard RGBA(hexString: h) != nil else { throw CommandError.invalid("Use a colour like #A0B0C0.") }
                        a.shadingColor = h.hasPrefix("#") ? h.uppercased() : "#" + h.uppercased()
                    }
                    let pat = try await text(ed, "Surface pattern (. = none)", a.surfacePattern ?? ".")
                    a.surfacePattern = pat == "." ? nil : pat.uppercased()
                case "Physical":
                    a.density = try await number(ed, "Density (kg/m³)", a.density ?? 1000)
                    a.conductivity = try await number(ed, "Thermal conductivity (W/m·K)", a.conductivity ?? 1)
                    a.specificHeat = try await number(ed, "Specific heat (J/kg·K)", a.specificHeat ?? 1000)
                    guard (a.density ?? 0) > 0, (a.conductivity ?? 0) > 0, (a.specificHeat ?? 0) > 0 else { throw CommandError.invalid("Values must be positive.") }
                default:
                    ed.print("\(name) — identity: \(a.description.isEmpty ? "—" : a.description)\(a.manufacturer.isEmpty ? "" : ", " + a.manufacturer)\(a.mark.isEmpty ? "" : ", mark " + a.mark)\(a.cost.map { ", cost " + fmt($0, 2) } ?? "")")
                    ed.print("  graphics: \(a.useRenderAppearance ? "render appearance" : "shading " + (a.shadingColor ?? "?"))\(a.surfacePattern.map { ", pattern " + $0 } ?? "")")
                    ed.print("  physical: ρ \(a.density.map { fmt($0, 0) } ?? "—") kg/m³, λ \(a.conductivity.map { fmt($0, 3) } ?? "—") W/mK, c \(a.specificHeat.map { fmt($0, 0) } ?? "—") J/kgK\(a.thermalResistance(thickness: 100).map { ", R(100 mm) " + fmt($0, 3) + " m²K/W" } ?? "")")
                    return
                }
                MaterialAssetSet.store(a, material: name, in: &ed.doc)
                ed.print("\(name): \(k.lowercased()) asset saved.")
            },
            CommandDef("PROCMATERIAL", aliases: ["PROCEDURALMATERIAL", "PROCTEXTURE", "MATPROCEDURAL"], category: "View", summary: "Procedural seamless material (Wood, Brick, Tile, Marble, Stone, Concrete, Terrazzo) with albedo, normal and roughness maps from colours, courses, joint width and a seed.") { ed in
                let kinds = ProceduralMaterial.Kind.allCases.map(\.rawValue)
                let ks = try await ed.getKeyword("Pattern [\(kinds.joined(separator: "/"))]", kinds, defaultValue: "Brick") ?? "Brick"
                var p = ProceduralMaterial.Params(kind: ProceduralMaterial.Kind(rawValue: ks) ?? .brick)
                let name = try await text(ed, "Material name", "Procedural " + ks)
                let c1 = try await text(ed, "Main colour (#RRGGBB)", p.color1.hexRGB), c2 = try await text(ed, "Second colour / joints (#RRGGBB)", p.color2.hexRGB)
                guard let a = RGBA(hexString: c1), let b = RGBA(hexString: c2) else { throw CommandError.invalid("Use colours like #A0522D.") }
                p.color1 = a; p.color2 = b
                p.tileSize = max(10, try await number(ed, "Tile size (mm)", p.tileSize))
                if [.brick, .tile, .stone, .wood].contains(p.kind) {
                    p.rows = max(1, min(64, Int(try await number(ed, "Rows / courses per tile", Double(p.rows)))))
                    if p.kind != .wood { p.columns = max(1, min(64, Int(try await number(ed, "Columns per tile", Double(p.columns))))) }
                    p.joint = max(0, min(0.2, try await number(ed, "Joint width (fraction of tile)", p.joint)))
                }
                p.seed = UInt64(max(0, try await number(ed, "Seed", 1)))
                let m = try ProceduralMaterial.create(p, name: name, in: &ed.doc)
                ed.print("Material \(m.name): \(ks.lowercased()) \(p.rows)×\(p.columns), tile \(fmt(p.tileSize, 0)) mm, seed \(p.seed) (albedo, normal and roughness maps).")
            },
            CommandDef("MATFROMIMAGE", aliases: ["MATPHOTO", "PHOTOMATERIAL", "IMAGETOMATERIAL"], category: "View", summary: "Creates a seamless PBR material from a photo: de-lit albedo, normal, roughness and AO maps derived from the image, at a real-world tile size.") { ed in
                let path = (try await text(ed, "Photo file", "~/Desktop/texture.jpg") as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: path) else { throw CommandError.invalid("File not found: \(path)") }
                let name = try await text(ed, "Material name", (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).capitalized)
                let tile = max(10, try await number(ed, "Real-world size of the photo (mm)", 1000))
                let m = try PhotoMaterial.create(from: URL(fileURLWithPath: path), name: name, tileSize: tile, in: &ed.doc)
                ed.print("Material \(m.name) from \(URL(fileURLWithPath: path).lastPathComponent): roughness \(fmt(m.roughness, 2)), tile \(fmt(tile, 0)) mm, normal/roughness/AO maps.")
            },
            // MARK: Environment (VIS-058/082/083)
            CommandDef("WEATHER", aliases: ["RAIN", "SNOW", "WEATHERFX"], category: "View", summary: "Weather in the 3D view and renders: Clear, Rain, Snow or Fog with an intensity, snow cover on up-facing faces and wet surfaces.") { ed in
                var w = WeatherSettings.load(ed.doc)
                let k = try await ed.getKeyword("Weather [Clear/Rain/Snow/Fog]", WeatherSettings.Kind.allCases.map(\.rawValue), defaultValue: w.kind.rawValue) ?? w.kind.rawValue
                w.kind = WeatherSettings.Kind(rawValue: k) ?? .clear
                if w.kind != .clear {
                    w.intensity = min(1, max(0, try await number(ed, "Intensity (0–1)", w.intensity)))
                    if w.kind == .snow { w.snowCover = min(1, max(0, try await number(ed, "Snow cover (0–1)", w.snowCover > 0 ? w.snowCover : w.intensity * 0.8))) }
                } else { w.snowCover = 0 }
                w.store(in: &ed.doc)
                ed.print("Weather: \(w.kind.rawValue)\(w.kind == .clear ? "" : " \(fmt(w.intensity, 2))")\(w.snow > 0 ? ", snow cover \(fmt(w.snow, 2))" : ""), \(w.season.rawValue.lowercased()).")
            },
            CommandDef("SEASON", aliases: ["SEASONS"], category: "View", summary: "Season of the vegetation in the 3D view and renders: Spring, Summer, Autumn or Winter colours for grass, trees and plants.") { ed in
                var w = WeatherSettings.load(ed.doc)
                let k = try await ed.getKeyword("Season [Spring/Summer/Autumn/Winter]", WeatherSettings.Season.allCases.map(\.rawValue), defaultValue: w.season.rawValue) ?? w.season.rawValue
                w.season = WeatherSettings.Season(rawValue: k) ?? .summer
                w.store(in: &ed.doc)
                ed.print("Season: \(w.season.rawValue).")
            },
            CommandDef("WATER", aliases: ["WATERSURFACE", "POND", "POOLWATER"], category: "Architecture", summary: "Water surface with animated waves (viewport and renders) inside a closed polyline or picked points, at a surface elevation and depth.") { ed in
                let mm = ed.doc.units.mm
                let k = try await ed.getKeyword("Boundary [Select/Points]", ["Select", "Points"], defaultValue: "Select") ?? "Select"
                var pts: [Vec2] = []
                if k == "Select" {
                    let ids = try await ed.getSelection("Select closed polylines or circles")
                    pts = boundaries(ed, ids).first ?? []
                } else {
                    let p0 = try await ed.requirePoint("First point")
                    pts = [p0]
                    while true {
                        let last = pts.last!
                        guard let p = try await ed.getPoint("Next point (Enter to close)", base: last, preview: { q in [.polyline(PolylineGeom(points: pts + [q], closed: true))] }).point else { break }
                        pts.append(p)
                    }
                }
                guard pts.count >= 3 else { throw CommandError.invalid("Needs a closed boundary with 3+ points.") }
                let lz = (ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) / mm
                let z = try await number(ed, "Water surface elevation", lz - 100 / mm)
                let d = max(1, try await number(ed, "Depth", 1500 / mm))
                WaterSurface.ensureMaterial(in: &ed.doc)
                ed.doc.ensureLayer(WaterSurface.layer)
                guard let e = WaterSurface.entity(boundary: pts, elevation: z, depth: d) else { throw CommandError.invalid("The boundary has no area.") }
                let id = ed.doc.add(e)
                ed.print("Water #\(id): \(fmt(abs(GeometryOps.signedArea(pts)) * mm * mm / 1e6, 2)) m² at elevation \(fmt(z, 0)).")
            },
            CommandDef("SCATTER", aliases: ["SCATTERPLANTS", "VEGETATION", "GRASSSCATTER"], category: "Architecture", summary: "Scatters Grass, Flowers, Shrubs or Trees over closed boundaries with Poisson-disk spacing at a density per m² (reproducible seed); shown in the viewport and renders.") { ed in
                let mm = ed.doc.units.mm
                let kinds = Scatter.Kind.allCases.map(\.rawValue)
                let ks = try await ed.getKeyword("Scatter [\(kinds.joined(separator: "/"))]", kinds, defaultValue: "Grass") ?? "Grass"
                let kind = Scatter.Kind(rawValue: ks) ?? .grass
                let ids = try await ed.getSelection("Select closed boundaries")
                let bs = boundaries(ed, ids).map { $0.map { $0 * mm } }
                guard !bs.isEmpty else { throw CommandError.invalid("Select closed polylines or circles.") }
                let dens = try await number(ed, "Density (plants per m²)", kind.density)
                guard dens > 0, dens <= 2000 else { throw CommandError.invalid("Density 0–2000 per m².") }
                let h = try await number(ed, "Plant height", kind.height / mm) * mm
                let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
                let z = try await number(ed, "Base elevation", lz / mm) * mm
                let seed = UInt64(max(0, try await number(ed, "Seed", 1)))
                // Boundaries inside another one are holes (pools, paths).
                let outers = bs.filter { b in !bs.contains { o in o != b && Scatter.inside(b[0], o) } }
                Scatter.ensureMaterials(kind, in: &ed.doc)
                ed.doc.ensureLayer(Scatter.layer)
                var total = 0
                for (i, o) in outers.enumerated() {
                    let holes = bs.filter { b in b != o && Scatter.inside(b[0], o) }
                    let r = Scatter.entities(kind, boundary: o, holes: holes, density: dens, z: z, height: h, seed: seed &+ UInt64(i))
                    // Mesh vertices are in mm; convert back to drawing units.
                    for var e in r.entities {
                        if mm != 1, case .solid(var s) = e.geometry { s.meshVertices = s.meshVertices.map { $0 / mm }; e.geometry = .solid(s) }
                        _ = ed.doc.add(e)
                    }
                    total += r.count
                }
                ed.print("Scattered \(total) \(ks.lowercased()) over \(outers.count) area(s).")
            },
            // MARK: Object animation (VIS-045)
            CommandDef("ANIMATE", aliases: ["OBJANIMATE", "OBJECTANIMATION", "DOORANIMATE"], category: "View", summary: "Object animation saved in the drawing: Door swings, Rotate about a pivot, Move by a vector (start time, duration, there and back); Play/Stop in 3D, List, Delete, Clear, Render a frame.") { ed in
                var anims = ObjectAnimations.load(ed.doc)
                let mm = ed.doc.units.mm
                let k = try await ed.getKeyword("Animate [Door/Rotate/Move/Play/Stop/List/Delete/Clear/Frame]", ["Door", "Rotate", "Move", "Play", "Stop", "List", "Delete", "Clear", "Frame"], defaultValue: "Door") ?? "Door"
                switch k {
                case "Play":
                    let m = try ui(ed)
                    if m.mode == .plan || m.mode == .sheet { m.mode = .model }
                    guard !anims.isEmpty else { throw CommandError.invalid("No animations. Use ANIMATE Door, Rotate or Move first.") }
                    AnimationPlayer.play(model: m)
                    ed.print("Playing \(anims.count) animation(s), \(fmt(ObjectAnimations.duration(anims), 1)) s loop. ANIMATE Stop ends.")
                    return
                case "Stop": AnimationPlayer.stop(); return
                case "List":
                    if anims.isEmpty { ed.print("No animations."); return }
                    for a in anims { ed.print("  \(a.id): \(a.kind.rawValue) #\(a.target)\(a.name.isEmpty ? "" : " \"\(a.name)\"") — \(fmt(a.angle, 0))°, move \(fmt(a.offset.length / mm, 0)), \(fmt(a.start, 1))–\(fmt(a.end, 1)) s\(a.pingPong ? " (there and back)" : "")") }
                    return
                case "Delete":
                    let n = try await ed.getInteger("Animation number to delete") ?? -1
                    guard anims.contains(where: { $0.id == n }) else { throw CommandError.invalid("No animation \(n).") }
                    anims.removeAll { $0.id == n }
                case "Clear": anims = []
                case "Frame":
                    let t = try await number(ed, "Time (s)", 1)
                    let url = try await fileURL(ed, "Image file", ext: "png", def: defaultPath(ed, " frame", "png"))
                    let spp = Int(try await number(ed, "Samples per pixel", 32))
                    let r = try await PathTraceFile.render(doc: ed.doc, camera: Viewport3DController.active?.currentCamera, width: 960, height: 540, samples: max(1, spp), denoise: true, time: Float(t), to: url)
                    ed.print("Frame at \(fmt(t, 2)) s (\(r.samples) samples) → \(url.path)")
                    return
                default:
                    let ids = try await ed.getSelection(k == "Door" ? "Select doors" : "Select objects")
                    guard !ids.isEmpty else { return }
                    let start = max(0, try await number(ed, "Start time (s)", 0))
                    let dur = max(0.05, try await number(ed, "Duration (s)", 2))
                    let back = (try await ed.getKeyword("There and back [Yes/No]", ["Yes", "No"], defaultValue: "Yes") ?? "Yes") == "Yes"
                    if k == "Door" {
                        let ang = try await number(ed, "Opening angle (degrees)", 90)
                        var n = 0
                        for id in ids {
                            guard let el = ed.doc.element(id), !ObjectAnimations.doorLeaves(el, doc: ed.doc).isEmpty else { continue }
                            anims.removeAll { $0.target == id && $0.kind == .door }
                            var new = ObjectAnimations.door(el, doc: ed.doc, id: ObjectAnimations.nextID(anims), angle: ang, start: start, duration: dur)
                            for i in new.indices { new[i].pingPong = back }
                            anims += new; n += 1
                        }
                        guard n > 0 else { throw CommandError.invalid("Select single or double swing doors in straight walls.") }
                        ed.print("\(n) door(s) animated.")
                    } else if k == "Rotate" {
                        let p = try await ed.requirePoint("Pivot point (vertical axis)")
                        let ang = try await number(ed, "Rotation angle (degrees)", 90)
                        for id in ids { anims.append(ObjectAnimation(id: ObjectAnimations.nextID(anims), target: id, kind: .rotate, pivot: Vec3(p.x * mm, p.y * mm, 0), angle: ang, start: start, duration: dur, pingPong: back)) }
                    } else {
                        let a = try await ed.requirePoint("Base point")
                        let b = try await ed.requirePoint("Second point", base: a) { q in [.line(LineGeom(a, q))] }
                        let dz = try await number(ed, "Vertical movement", 0)
                        let off = Vec3((b.x - a.x) * mm, (b.y - a.y) * mm, dz * mm)
                        for id in ids { anims.append(ObjectAnimation(id: ObjectAnimations.nextID(anims), target: id, kind: .move, offset: off, start: start, duration: dur, pingPong: back)) }
                    }
                }
                ObjectAnimations.store(anims, in: &ed.doc)
                ed.print("\(anims.count) animation(s), total \(fmt(ObjectAnimations.duration(anims), 1)) s.")
            },
            // MARK: Node packages (SCR-015)
            CommandDef("NODEPACKAGE", aliases: ["NODEPACKAGES", "NODEPKG"], category: "Tools", summary: "Custom node packages (.archinodes): Create one from the drawing's node graph (a snippet per group), Install a file, Insert a snippet into the graph, List, Remove.") { ed in
                let k = try await ed.getKeyword("Node packages [List/Create/Install/Insert/Remove]", ["List", "Create", "Install", "Insert", "Remove"], defaultValue: "List") ?? "List"
                switch k {
                case "Create":
                    guard let g = NodeGraph.load(ed.doc), !g.nodes.isEmpty else { throw CommandError.invalid("The drawing has no node graph. Build one in the Node Editor first.") }
                    let name = try await text(ed, "Package name", "My Nodes")
                    let url = try await fileURL(ed, "Package file", ext: NodePackage.fileExtension, def: NSHomeDirectory() + "/Desktop/" + NodePackages.fileName(name))
                    let pkg = NodePackages.make(from: g, name: name, author: NSFullUserName())
                    try pkg.data().write(to: url)
                    try NodePackages.install(pkg)
                    ed.print("Package \(pkg.name): \(pkg.snippets.map(\.name).joined(separator: ", ")) → \(url.path) (installed).")
                case "Install":
                    let url = try await fileURL(ed, "Package file", ext: NodePackage.fileExtension, def: NSHomeDirectory() + "/Desktop/My Nodes.archinodes")
                    let p = try NodePackages.install(url)
                    ed.print("Installed \(p.name) \(p.version): \(p.snippets.count) snippet(s).")
                case "Insert":
                    let pkgs = NodePackages.installed()
                    guard !pkgs.isEmpty else { throw CommandError.invalid("No node packages installed.") }
                    let pn = try await text(ed, "Package", pkgs[0].name)
                    guard let p = NodePackages.package(named: pn) else { throw CommandError.invalid("No package \(pn).") }
                    let sn = try await text(ed, "Snippet", p.snippets.first?.name ?? "")
                    guard let s = p.snippets.first(where: { $0.name.caseInsensitiveCompare(sn) == .orderedSame }) else { throw CommandError.invalid("No snippet \(sn) in \(p.name).") }
                    var g = NodeGraph.load(ed.doc) ?? NodeGraph()
                    let map = g.insert(s.graph, x: (g.nodes.map(\.x).max() ?? -220) + 260, y: 40)
                    g.store(in: &ed.doc)
                    ed.print("Inserted \(s.name): \(map.count) node(s). Open the Node Editor to connect and bake it.")
                case "Remove":
                    let pn = try await text(ed, "Package", NodePackages.installed().first?.name ?? "")
                    guard NodePackages.package(named: pn) != nil else { throw CommandError.invalid("No package \(pn).") }
                    try NodePackages.remove(NodePackages.package(named: pn)!.name); ed.print("Removed \(pn).")
                default:
                    let pkgs = NodePackages.installed()
                    if pkgs.isEmpty { ed.print("No node packages installed.") }
                    for p in pkgs { ed.print("  \(p.name) \(p.version)\(p.author.isEmpty ? "" : " by " + p.author): \(p.snippets.map(\.name).joined(separator: ", "))") }
                }
            },
            ARQuickLook.command,
            CommandLineAppearance.command,
            CommandDef("CUSTOMIZERPANEL", aliases: ["PARAMPANEL", "SCADPANEL"], category: "3D", summary: "Customizer panel: sliders, check boxes and choices for the parameters of the selected scripted object (OpenSCAD customizer comments), regenerating it on change.", modifies: false) { ed in
                CustomizerWindow.show(model: try ui(ed))
            },
            // MARK: Display (VIS-009/010)
            CommandDef("REDRAW", aliases: ["REDRAWALL", "RA"], category: "View", summary: "Refreshes the screen from the display cache (fast; REGEN rebuilds the cache).", modifies: false) { ed in
                ed.host?.perform(.setView("redraw"), editor: ed)
            },
            CommandDef("GRAPHICSTYLES", aliases: ["STYLESMANAGER", "GSTYLES"], category: "Settings", summary: "Graphic styles manager: line styles and their layers, lineweights by view scale, pen sets and graphic override filters in one dialog.", modifies: false) { ed in
                GraphicStylesWindow.show(model: try ui(ed))
            },
            // MARK: Devices and UI (VIS-024, APP-016)
            CommandDef("SPACEMOUSE", aliases: ["3DMOUSE", "NDOF", "3DCONNEXION"], category: "View", summary: "3Dconnexion SpaceMouse: On/Off, Object (orbit) or Fly mode, Sensitivity, Status. Axes move the 3D camera; button 1 fits the view.", modifies: false) { ed in
                let sm = SpaceMouse.shared
                let k = try await ed.getKeyword("SpaceMouse [On/Off/Object/Fly/Sensitivity/Status]", ["On", "Off", "Object", "Fly", "Sensitivity", "Status"], defaultValue: "Status") ?? "Status"
                switch k {
                case "On": SpaceMouse.enabledPreference = true; sm.start()
                case "Off": SpaceMouse.enabledPreference = false; sm.stop()
                case "Object", "Fly": var c = sm.config; c.mode = SpaceMouse.Mode(rawValue: k) ?? .object; sm.config = c
                case "Sensitivity":
                    var c = sm.config
                    c.sensitivity = min(10, max(0.05, try await number(ed, "Sensitivity (0.05–10)", c.sensitivity))); sm.config = c
                default: break
                }
                ed.print("SpaceMouse \(sm.isRunning ? "on" : "off"), \(sm.config.mode.rawValue) mode, sensitivity \(fmt(sm.config.sensitivity, 2)); devices: \(sm.devices.isEmpty ? "none connected" : sm.devices.joined(separator: ", ")).")
            },
            CommandDef("CUI", aliases: ["CUSTOMIZE", "RIBBONCUSTOMIZE", "-CUI"], category: "Settings", summary: "Customizes the ribbon: Dialog, Add a panel of commands to a tab, Remove, Hide/Show a built-in panel, List, Export/Import a customisation file, Reset.", modifies: false) { ed in
                var c = RibbonCustom.current
                let k = try await ed.getKeyword("CUI [Dialog/Add/Remove/Hide/Show/List/Export/Import/Reset]", ["Dialog", "Add", "Remove", "Hide", "Show", "List", "Export", "Import", "Reset"], defaultValue: "Dialog") ?? "Dialog"
                switch k {
                case "Dialog": CUIWindow.show(); return
                case "Add":
                    let tabs = RibbonTab.allCases.map(\.rawValue)
                    let tab = try await ed.getKeyword("Tab [\(tabs.joined(separator: "/"))]", tabs, defaultValue: "Home") ?? "Home"
                    let title = try await text(ed, "Panel title", "My Tools")
                    let list = try await text(ed, "Commands (comma separated)", "LINE, CIRCLE")
                    let cmds = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
                    let bad = cmds.filter { ed.registry.lookup(String($0.split(separator: " ").first ?? "")) == nil }
                    guard bad.isEmpty else { throw CommandError.invalid("Unknown command(s): " + bad.joined(separator: ", ")) }
                    guard !cmds.isEmpty else { return }
                    c.panels.removeAll { $0.tab == tab && $0.title == title }
                    c.panels.append(CustomRibbonPanel(title: title, tab: tab, commands: cmds))
                case "Remove":
                    let title = try await text(ed, "Panel title", c.panels.last?.title ?? "")
                    guard c.panels.contains(where: { $0.title == title }) else { throw CommandError.invalid("No custom panel \(title).") }
                    c.panels.removeAll { $0.title == title }
                case "Hide", "Show":
                    let title = try await text(ed, "Built-in panel title", "Selection")
                    if k == "Hide" { if !c.hiddenPanels.contains(title) { c.hiddenPanels.append(title) } } else { c.hiddenPanels.removeAll { $0 == title } }
                case "Export":
                    let url = try await fileURL(ed, "Customisation file", ext: "json", def: NSHomeDirectory() + "/Desktop/Ribbon.archicui.json")
                    try RibbonCustom.export(to: url); ed.print("Ribbon customisation exported to \(url.path)."); return
                case "Import":
                    let url = try await fileURL(ed, "Customisation file", ext: "json", def: NSHomeDirectory() + "/Desktop/Ribbon.archicui.json")
                    let unknown = try RibbonCustom.importFile(url)
                    ed.print("Imported \(RibbonCustom.current.panels.count) panel(s)\(unknown.isEmpty ? "" : "; unknown commands: " + unknown.joined(separator: ", "))."); return
                case "Reset": c = RibbonCustomization()
                default:
                    if c.panels.isEmpty && c.hiddenPanels.isEmpty { ed.print("Ribbon not customised.") }
                    for p in c.panels { ed.print("  \(p.tab) ▸ \(p.title): \(p.commands.joined(separator: ", "))") }
                    if !c.hiddenPanels.isEmpty { ed.print("  Hidden: " + c.hiddenPanels.joined(separator: ", ")) }
                    return
                }
                RibbonCustom.current = c
                ed.print("Ribbon: \(c.panels.count) custom panel(s), \(c.hiddenPanels.count) hidden.")
            },
        ]
    }

    static func startDevices() {
        if SpaceMouse.enabledPreference { SpaceMouse.shared.start() }
    }
}

extension CommandCatalog {
    private static func c10(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }
    /// Rendering, materials, environment and device commands of round 10.
    static let renderRound10: [CmdItem] = [
        c10("Path Tracer", "camera.aperture", "PATHTRACE"), c10("Light Mix", "slider.horizontal.3", "LIGHTMIX"), c10("PBR Maps", "square.stack.3d.up", "MATMAPS"),
        c10("Material Assets", "info.square", "MATASSET"), c10("Procedural Material", "square.grid.3x3.fill", "PROCMATERIAL"), c10("Material from Photo", "photo", "MATFROMIMAGE"),
        c10("Weather", "cloud.rain", "WEATHER"), c10("Season", "leaf", "SEASON"), c10("Water", "drop.triangle", "WATER"), c10("Scatter Plants", "camera.macro", "SCATTER"),
        c10("Animate Objects", "play.circle", "ANIMATE"), c10("SpaceMouse", "rotate.3d", "SPACEMOUSE"), c10("Customize Ribbon", "rectangle.3.group", "CUI"),
        c10("Node Packages", "shippingbox", "NODEPACKAGE"), c10("Graphic Styles", "paintpalette", "GRAPHICSTYLES"), c10("Redraw", "arrow.clockwise.circle", "REDRAW"), c10("AR Quick Look", "arkit", "ARQUICKLOOK"),
        c10("Command Line Options", "terminal", "CMDLINEOPTIONS"), c10("Customizer Panel", "slider.horizontal.below.square.filled.and.square", "CUSTOMIZERPANEL"),
    ]
    static var coverageMenus6: [(String, [CmdItem])] { [("Render, Materials & Environment", renderRound10)] + coverageMenus7 }
}

/// AR Quick Look (VIS-085): exports the model as USDZ at real-world scale (metersPerUnit from the drawing units,
/// Z up, PBR materials and textures) and previews it or shares it to an iPhone/iPad (AirDrop, Messages, Mail).
@MainActor
enum ARQuickLook {
    static func export(_ doc: ArchiDocument, fileURL: URL?) throws -> URL {
        let name = doc.info.name.isEmpty ? "Model" : doc.info.name
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ARQuickLook", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".usdz")
        let data = USDExporter.usdz(MeshBuilder.build(doc: doc), materials: doc.materials, metersPerUnit: doc.units.mm / 1000, name: name, textureRoot: fileURL?.deletingLastPathComponent())
        try data.write(to: url)
        return url
    }
    /// metersPerUnit declared in a USD layer's text.
    static func metersPerUnit(_ usd: String) -> Double? {
        guard let r = usd.range(of: "metersPerUnit = ") else { return nil }
        let tail = usd[r.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "e" || $0 == "-" }
        return Double(tail)
    }
    static var command: CommandDef {
        CommandDef("ARQUICKLOOK", aliases: ["ARVIEW", "USDZPREVIEW", "ARPREVIEW"], category: "View", summary: "AR Quick Look: exports the model as a real-scale USDZ and Previews it or Shares it to an iPhone/iPad (AirDrop) to place it in AR.", modifies: false) { ed in
            let k = try await ed.getKeyword("AR Quick Look [Preview/Share]", ["Preview", "Share"], defaultValue: "Preview") ?? "Preview"
            let url = try export(ed.doc, fileURL: ed.fileURL)
            if k == "Share", let m = AppCommands.model(ed), let v = m.window?.contentView {
                let picker = NSSharingServicePicker(items: [url])
                picker.show(relativeTo: NSRect(x: v.bounds.midX, y: v.bounds.maxY - 40, width: 1, height: 1), of: v, preferredEdge: .minY)
            } else {
                NSWorkspace.shared.open(url)
            }
            ed.print("USDZ at real-world scale (\(fmt(ed.doc.units.mm / 1000, 4)) m per unit): \(url.path)")
        }
    }
}
