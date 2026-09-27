// Oanarina Archi Tool — GPL-3.0-or-later
// Portable versions of the Mac 3D view commands (ArchiApp/AppCommands.swift SECTIONBOX, SUNSTUDY, ORBITSELECTION,
// SAVECAMERA, CAMERA; AppCommandsExtra.swift SECTIONPLANE, PANORAMA; AppCommandsReview.swift MEASURE3D, GIZMO3D;
// AppCommandsStudio.swift MOVEZ, LEVELVIEW3D, FOV, VIEWIMAGE; AppCommandsRound9.swift FLY, LOOKAROUND, POSITIONCAMERA,
// TWOPOINT, NAVSWHEEL, STEREOPANORAMA; AppCommandsRound10.swift WEATHER, SEASON, ANIMATE): same names, aliases, prompts,
// keywords and messages. What the Mac does in its 3D view controller the engine asks the Windows shell to do with a
// `host` notification {"action":"view3d","op":…} (docs/ENGINE-PROTOCOL.md "3D view"). Registered by archi-engine only.
import Foundation

enum EngineView3DCommands {
    static var all: [CommandDef] {
        [sectionBox, sectionPlane, clipPlanes, sunStudy, orbitSelection, saveCamera, camera, measure3D, gizmo3D, moveZ, levelView3D, fov,
         fly, lookAround, positionCamera, twoPoint, steeringWheel, weather, season, animate, panorama, stereoPanorama, viewImage]
    }

    // MARK: Helpers

    @MainActor static func view3d(_ ed: Editor, _ op: String, _ fields: [(String, EngineJSON)] = []) throws {
        try EngineUICommands.host(ed, "view3d", [("op", .string(op))] + fields)
    }
    @MainActor static func show3D(_ ed: Editor) { ed.host?.perform(.show3D, editor: ed) }
    @MainActor static func state(_ ed: Editor) throws -> EngineView3DState { try EngineUICommands.session(ed).view3d }

    static func number(_ ed: Editor, _ msg: String, _ def: Double) async throws -> Double {
        try await ed.getDistance(msg + " <" + fmt(def) + ">", defaultValue: def).value ?? def
    }
    /// A number typed as text (AppCommandsStudio.number): Enter keeps the default.
    static func typedNumber(_ ed: Editor, _ msg: String, defaultValue: Double? = nil) async throws -> Double? {
        guard let s = try await ed.getString(msg, defaultValue: defaultValue.map { fmt($0, 6) }), !s.trimmingCharacters(in: .whitespaces).isEmpty else { return defaultValue }
        if let v = Double(s.trimmingCharacters(in: .whitespaces)) { return v }
        throw CommandError.invalid("Requires a number.")
    }
    @MainActor static func defaultPath(_ ed: Editor, _ ext: String, suffix: String = "") -> String {
        let base = ed.fileURL?.deletingPathExtension().path ?? (NSHomeDirectory() + "/Desktop/" + (ed.doc.info.name.isEmpty ? "Drawing" : ed.doc.info.name))
        return base + suffix + "." + ext
    }
    static func path(_ ed: Editor, _ msg: String, ext: String, def: String) async throws -> String? {
        guard let s = try await ed.getString(msg + " <" + def + ">", defaultValue: def) else { return nil }
        var p = (s.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as NSString).expandingTildeInPath
        if p.isEmpty { return nil }
        if !p.lowercased().hasSuffix("." + ext) { p += "." + ext }
        return p
    }
    /// Bounds of the model meshes (MeshBuilder, model mm).
    @MainActor static func extents(_ doc: ArchiDocument, only ids: Set<EntityID>? = nil) -> BBox3 {
        var b = BBox3.empty
        for g in MeshBuilder.build(doc: doc) {
            if let ids { guard let id = g.id, ids.contains(id) else { continue } }
            for p in g.mesh.positions { b.add(p) }
        }
        return b
    }
    static func around(_ b: BBox3) -> (min: Vec3, max: Vec3) {
        let pad = max(100, b.size.length * 0.02)
        return (b.min - Vec3(pad, pad, pad), b.max + Vec3(pad, pad, pad))
    }
    static func boxString(on: Bool, _ lo: Vec3, _ hi: Vec3) -> String {
        let nums: [Double] = [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]
        let flag = on ? "on" : "off"
        return flag + ";" + nums.map { fmt($0, 1) }.joined(separator: ",")
    }
    static func planeString(on: Bool, _ p: Vec3, _ n: Vec3) -> String {
        let pt: [Double] = [p.x, p.y, p.z], nv: [Double] = [n.x, n.y, n.z]
        let a = pt.map { fmt($0, 3) }.joined(separator: ","), b = nv.map { fmt($0, 6) }.joined(separator: ",")
        return (on ? "on" : "off") + ";" + a + ";" + b
    }

    // MARK: Section box / plane, sun study, cameras

    static var sectionBox: CommandDef {
        CommandDef("SECTIONBOX", aliases: ["SBOX", "3DSECTIONBOX"], category: "View", summary: "Section box in 3D: On/Off/Selection/Level/Reset; the box is saved with the drawing.") { ed in
            let k = try await ed.getKeyword("Section box [On/Off/Selection/Level/Reset/Panel]", ["On", "Off", "Selection", "Level", "Reset", "Panel"], defaultValue: "Panel") ?? "Panel"
            show3D(ed)
            let ext = extents(ed.doc)
            guard !ext.isEmpty else { throw CommandError.invalid("The model has no 3D content.") }
            let a0 = around(ext)
            var box: (on: Bool, min: Vec3, max: Vec3) = (true, a0.min, a0.max)
            if let b = EngineView3DData.parseBox(ed.doc.variable("SECTIONBOX")) { box = b }
            switch k {
            case "On": box.on = true
            case "Off": box.on = false
            case "Reset": box = (true, a0.min, a0.max)
            case "Level":
                guard let l = ed.doc.level(ed.doc.currentLevel) else { return }
                box.on = true
                box.min.z = max(ext.min.z - 100, l.elevation - 50)
                box.max.z = l.elevation + l.height * 0.9
            case "Selection":
                let b = extents(ed.doc, only: ed.selection)
                guard !b.isEmpty else { throw CommandError.invalid("Select building elements first.") }
                let a = around(b); box = (true, a.min, a.max)
            default:
                try view3d(ed, "sectionBoxPanel")
                return
            }
            ed.doc.setVariable("SECTIONBOX", boxString(on: box.on, box.min, box.max))
            ed.print(box.on ? "Section box on." : "Section box off.")
        }
    }

    static var sectionPlane: CommandDef {
        CommandDef("SECTIONPLANE", aliases: ["SPLANE", "CUTPLANE", "LIVESECTION"], category: "View",
                   summary: "Live section plane in 3D with cap faces: Horizontal at a height, Vertical through two plan points, Flip, Off.") { ed in
            let k = try await ed.getKeyword("Section plane [Horizontal/Vertical/Flip/Off]", ["Horizontal", "Vertical", "Flip", "Off"], defaultValue: "Horizontal") ?? "Horizontal"
            var plane: (Vec3, Vec3)?
            switch k {
            case "Off":
                if let p = EngineView3DData.parsePlane(ed.doc.variable("SECTIONPLANE")) { ed.doc.setVariable("SECTIONPLANE", planeString(on: false, p.point, p.normal)) }
                ed.print("Section plane off."); return
            case "Flip":
                guard let p = EngineView3DData.parsePlane(ed.doc.variable("SECTIONPLANE")) else { throw CommandError.invalid("No section plane yet.") }
                plane = (p.point, p.normal * -1)
            case "Vertical":
                let a = try await ed.requirePoint("First point of the cut line")
                let b = try await ed.requirePoint("Second point (the left side is removed)", base: a, preview: { p in [.line(LineGeom(a, p))] })
                let d = b - a
                guard d.length > 1e-9 else { throw CommandError.invalid("The two points coincide.") }
                let left = Vec2(-d.y, d.x).normalized
                plane = (Vec3(a.x, a.y, 0), Vec3(left.x, left.y, 0))
            default:
                let lvl = ed.doc.level(ed.doc.currentLevel)
                let def = (lvl?.elevation ?? 0) + 1200 / max(ed.doc.units.mm, 1e-9)
                guard let z = try await ed.getDistance("Cut height", defaultValue: def).value else { return }
                plane = (Vec3(0, 0, z), Vec3(0, 0, 1))
            }
            if let p = plane { ed.doc.setVariable("SECTIONPLANE", planeString(on: true, p.0, p.1)) }
            show3D(ed)
            ed.print("Section plane " + (k == "Flip" ? "flipped" : "on") + ". SECTIONPLANE Off removes it.")
        }
    }

    static var clipPlanes: CommandDef {
        CommandDef("CLIPPLANES", aliases: ["CLIPPLANE", "CLIPPINGPLANE"], category: "View", summary: "Clipping plane panel in the 3D view: horizontal or vertical cut, live offset slider, flip, remove.", modifies: false) { ed in
            show3D(ed)
            try view3d(ed, "clipPlanePanel")
        }
    }

    static var sunStudy: CommandDef {
        CommandDef("SUNSTUDY", aliases: ["SUN", "SUNPROPERTIES"], category: "View", summary: "Sun study panel in the 3D view: date and time sliders with a day animation.", modifies: false) { ed in
            show3D(ed)
            try view3d(ed, "sunStudy")
        }
    }

    static var orbitSelection: CommandDef {
        CommandDef("ORBITSELECTION", aliases: ["ORBITSEL", "3DORBITSEL", "ZOOMSELECTED3D"], category: "View", summary: "Orbits around (and zooms to) the selected elements in 3D.", modifies: false) { ed in
            guard !ed.selection.isEmpty else { throw CommandError.invalid("Select objects first.") }
            guard !extents(ed.doc, only: ed.selection).isEmpty else { throw CommandError.invalid("The selection has no 3D geometry.") }
            show3D(ed)
            try view3d(ed, "orbitSelection", [("ids", EngineJSON.ints(ed.selection.sorted()))])
        }
    }

    static var saveCamera: CommandDef {
        CommandDef("SAVECAMERA", aliases: ["CAMSAVE", "NEWCAMERA"], category: "View", summary: "Saves the current 3D camera by name (restored with CAMERA).") { ed in
            guard let c = try state(ed).camera else { throw CommandError.invalid("Open the 3D view first.") }
            let def = "Camera " + String(ed.doc.namedViews.filter { $0.camera != nil }.count + 1)
            guard let n0 = try await ed.getString("Enter camera name <" + def + ">", defaultValue: def), !n0.isEmpty else { return }
            let name = n0.trimmingCharacters(in: .whitespaces)
            let center = Vec2(c.target.x, c.target.y)
            let h = max(1000, (c.eye - c.target).length)
            ed.doc.namedViews.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.camera != nil }
            ed.doc.namedViews.append(NamedView(name: name, center: center, height: h, camera: c))
            ed.print("Camera “" + name + "” saved.")
        }
    }

    static var camera: CommandDef {
        CommandDef("CAMERA", aliases: ["CAM", "RESTORECAMERA"], category: "View", summary: "Restores a saved 3D camera (or lists them).", modifies: false) { ed in
            let cams = ed.doc.namedViews.filter { $0.camera != nil }
            guard !cams.isEmpty else { throw CommandError.invalid("No saved cameras. Use SAVECAMERA.") }
            guard let n = try await ed.getString("Enter camera name [" + cams.map(\.name).joined(separator: "/") + "]") else { return }
            let name = n.trimmingCharacters(in: .whitespaces)
            guard let v = cams.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }), let cam = v.camera else { throw CommandError.invalid("Camera \"" + n + "\" not found.") }
            show3D(ed)
            try view3d(ed, "camera", [("name", .string(v.name)), ("camera", EngineSession.cameraJSON(v.name, cam))])
        }
    }

    // MARK: Measure, gizmo, Z move, levels

    static var measure3D: CommandDef {
        CommandDef("MEASURE3D", aliases: ["3DMEASURE", "DIST3D"], category: "Inquiry", summary: "Measures in the 3D view: click two points on the model for distance and ΔX/ΔY/ΔZ.", modifies: false) { ed in
            let st = try state(ed)
            let k = try await ed.getKeyword("Measure in 3D [On/Off]", ["On", "Off"], defaultValue: st.measure ? "Off" : "On") ?? "On"
            show3D(ed)
            st.measure = k == "On"
            if st.measure { st.gizmo = "Off" }
            try view3d(ed, "measure", [("on", .bool(st.measure))])
            ed.print(k == "On" ? "Click two points on the model in the 3D view." : "3D measuring is off.")
        }
    }

    static var gizmo3D: CommandDef {
        CommandDef("GIZMO3D", aliases: ["GIZMO", "3DGIZMO"], category: "3D", summary: "Shows a move (X/Y/Z arrows), rotate (ring) or uniform scale gizmo on the selection in the 3D view; drag it to transform (one undo step).", modifies: false) { ed in
            let st = try state(ed)
            let k = try await ed.getKeyword("Gizmo [Move/Rotate/Scale/Off]", ["Move", "Rotate", "Scale", "Off"], defaultValue: st.gizmo == "Off" ? "Move" : "Off") ?? "Off"
            show3D(ed)
            st.gizmo = k
            if k != "Off" { st.measure = false }
            try view3d(ed, "gizmo", [("mode", .string(k))])
            if k != "Off" && ed.selection.isEmpty { ed.print("Select objects to show the gizmo.") }
        }
    }

    static var moveZ: CommandDef {
        CommandDef("MOVEZ", aliases: ["ZMOVE", "MOVEUP"], category: "3D", summary: "Moves objects up or down: element base/top offsets and door/window sills change, solids move (one undo step).") { ed in
            let ids = try await ed.getSelection()
            guard !ids.isEmpty else { return }
            guard let dz = try await typedNumber(ed, "Vertical distance (negative = down)") else { return }
            let r = EngineGizmo.moveZ(ed, ids: ids, dz: dz, label: "MOVEZ")
            let tail = r.skipped > 0 ? "; \(r.skipped) have no height to change." : "."
            ed.print("Moved \(r.moved) object(s) by \(fmt(dz, 2)) along Z\(tail)")
        }
    }

    static var levelView3D: CommandDef {
        CommandDef("LEVELVIEW3D", aliases: ["ISOLATELEVEL3D", "EXPLODELEVELS"], category: "View", summary: "3D view by level: show All levels, Isolate one level, or Explode levels apart by a gap.", modifies: false) { ed in
            let st = try state(ed)
            let k = try await ed.getKeyword("Levels in 3D [All/Isolate/Explode]", ["All", "Isolate", "Explode"], defaultValue: "Isolate") ?? "All"
            show3D(ed)
            switch k {
            case "Isolate":
                let names = ed.doc.levels.map(\.name)
                let cur = ed.doc.level(ed.doc.currentLevel)?.name ?? names.first ?? ""
                let n = try await ed.getString("Level [" + names.joined(separator: "/") + "]", defaultValue: cur) ?? cur
                guard let l = ed.doc.levels.first(where: { $0.name.caseInsensitiveCompare(n) == .orderedSame }) ?? Int(n).flatMap({ ed.doc.level($0) }) else { throw CommandError.invalid("Unknown level " + n + ".") }
                st.isolate = l.id
                ed.print("Showing only " + l.name + " in 3D.")
            case "Explode":
                let g = try await typedNumber(ed, "Gap between levels", defaultValue: 3000 / max(ed.doc.units.mm, 1e-9)) ?? 0
                st.explodeGap = max(0, g)
                ed.print(g > 0 ? "Levels exploded by " + fmt(g, 0) + "." : "Levels are not exploded.")
            default:
                st.isolate = nil; st.explodeGap = 0
                ed.print("All levels shown.")
            }
            try view3d(ed, "levels", [("isolate", st.isolate.map { EngineJSON.int($0) } ?? .null), ("explodeGap", .number(st.explodeGap * ed.doc.units.mm))])
        }
    }

    // MARK: Camera and navigation

    static func focal(_ fov: Double) -> Double { 12 / tan(min(max(fov, 15), 120) * .pi / 360) }
    static func fovOf(_ f: Double) -> Double { min(max(2 * atan(12 / max(f, 1e-6)) * 180 / .pi, 15), 120) }

    static var fov: CommandDef {
        CommandDef("FOV", aliases: ["FIELDOFVIEW", "LENS"], category: "View", summary: "Sets the 3D camera field of view in degrees (15–120), or a Lens length in mm (35 mm equivalent).", modifies: false) { ed in
            let st = try state(ed)
            show3D(ed)
            guard let c = st.camera else { throw CommandError.invalid("Open the 3D view first.") }
            let s = try await ed.getString("Field of view in degrees or [Lens] <" + fmt(c.fov, 1) + ">", defaultValue: "") ?? ""
            if s.trimmingCharacters(in: .whitespaces).isEmpty { return }
            var v: Double
            if s.uppercased().hasPrefix("L") {
                guard let f = try await typedNumber(ed, "Lens length in mm <" + fmt(focal(c.fov), 0) + ">", defaultValue: focal(c.fov)), f > 0 else { return }
                v = fovOf(f)
            } else {
                guard let d = Double(s) else { throw CommandError.invalid("Requires a number of degrees or L.") }
                v = min(max(d, 15), 120)
            }
            st.camera?.fov = v
            try view3d(ed, "fov", [("fov", .number(v))])
            let lens = focal(v)
            ed.print("Field of view \(fmt(v, 1))° (\(fmt(lens, 0)) mm lens).")
        }
    }

    static var fly: CommandDef {
        CommandDef("FLY", aliases: ["FLYMODE", "3DFLYMODE"], category: "View", summary: "Free flight in 3D: W A S D along the view direction, Q/E down/up, drag to look (no gravity or collisions).", modifies: false) { ed in
            show3D(ed); try view3d(ed, "navigate", [("mode", .string("fly"))])
        }
    }

    static var lookAround: CommandDef {
        CommandDef("LOOKAROUND", aliases: ["LOOK", "LOOKAROUNDTOOL"], category: "View", summary: "Looks around from the current eye point (drag or arrow keys turn the head; the camera does not move).", modifies: false) { ed in
            show3D(ed); try view3d(ed, "navigate", [("mode", .string("look"))])
        }
    }

    static var positionCamera: CommandDef {
        CommandDef("POSITIONCAMERA", aliases: ["POSCAM", "EYEPOINT"], category: "View", summary: "Places the camera at a plan point at eye height looking towards a second point, then looks around (SketchUp style).", modifies: false) { ed in
            let eye = try await ed.requirePoint("Specify eye position")
            let tgt = try await ed.requirePoint("Specify direction to look", base: eye) { p in [.line(LineGeom(eye, p))] }
            guard eye.distance(to: tgt) > 1e-6 else { throw CommandError.invalid("Pick two different points.") }
            let h = try await number(ed, "Eye height", 1600 / ed.doc.units.mm)
            let mm = ed.doc.units.mm
            let lz = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            let z = lz + h * mm
            show3D(ed)
            let cam = Camera(eye: Vec3(eye.x * mm, eye.y * mm, z), target: Vec3(tgt.x * mm, tgt.y * mm, z), fov: 60)
            try view3d(ed, "positionCamera", [("camera", EngineSession.cameraJSON(nil, cam)), ("mode", .string("look"))])
            ed.print("Eye at \(fmt(eye.x, 0)),\(fmt(eye.y, 0)), height \(fmt(h, 0)). Drag to look around; Esc exits.")
        }
    }

    static var twoPoint: CommandDef {
        CommandDef("TWOPOINT", aliases: ["TWOPOINTPERSPECTIVE", "2PT", "VERTICALS"], category: "View", summary: "Two-point perspective: levels the 3D camera so vertical lines stay vertical, shifting the lens to keep the framing (On/Off).", modifies: false) { ed in
            show3D(ed)
            let k = try await ed.getKeyword("Two-point perspective [On/Off]", ["On", "Off"], defaultValue: "On") ?? "On"
            // The shell prints the Mac message with the lens shift it applied.
            try view3d(ed, "twoPoint", [("on", .bool(k == "On"))])
        }
    }

    static var steeringWheel: CommandDef {
        CommandDef("NAVSWHEEL", aliases: ["STEERINGWHEEL", "WHEEL", "SWHEEL"], category: "View", summary: "Steering wheel in 3D: Zoom, Orbit, Pan, Rewind (outer ring), Center, Walk, Up/Down, Look (inner ring).", modifies: false) { ed in
            show3D(ed)
            let k = try await ed.getKeyword("Steering wheel [On/Off]", ["On", "Off"], defaultValue: "On") ?? "On"
            try view3d(ed, "wheel", [("on", .bool(k == "On"))])
        }
    }

    // MARK: Weather, seasons, object animation

    static var weather: CommandDef {
        CommandDef("WEATHER", aliases: ["RAIN", "SNOW", "WEATHERFX"], category: "View", summary: "Weather in the 3D view and renders: Clear, Rain, Snow or Fog with an intensity, snow cover on up-facing faces and wet surfaces.") { ed in
            var w = ed.doc.variable(EngineWeather.variable).flatMap(EngineWeather.init(stored:)) ?? EngineWeather()
            let k = try await ed.getKeyword("Weather [Clear/Rain/Snow/Fog]", EngineWeather.kinds, defaultValue: w.kind) ?? w.kind
            w.kind = EngineWeather.kinds.contains(k) ? k : "Clear"
            if w.kind != "Clear" {
                w.intensity = min(1, max(0, try await number(ed, "Intensity (0–1)", w.intensity)))
                if w.kind == "Snow" { w.snowCover = min(1, max(0, try await number(ed, "Snow cover (0–1)", w.snowCover > 0 ? w.snowCover : w.intensity * 0.8))) }
            } else { w.snowCover = 0 }
            store(w, in: ed)
            let level = w.kind == "Clear" ? "" : " " + fmt(w.intensity, 2)
            var msg = "Weather: \(w.kind)\(level)"
            if w.snow > 0 { msg += ", snow cover " + fmt(w.snow, 2) }
            ed.print(msg + ", " + w.season.lowercased() + ".")
        }
    }

    @MainActor static func store(_ w: EngineWeather, in ed: Editor) {
        if w == EngineWeather() { ed.doc.variables[EngineWeather.variable] = nil } else { ed.doc.setVariable(EngineWeather.variable, w.stored) }
    }

    static var season: CommandDef {
        CommandDef("SEASON", aliases: ["SEASONS"], category: "View", summary: "Season of the vegetation in the 3D view and renders: Spring, Summer, Autumn or Winter colours for grass, trees and plants.") { ed in
            var w = ed.doc.variable(EngineWeather.variable).flatMap(EngineWeather.init(stored:)) ?? EngineWeather()
            let k = try await ed.getKeyword("Season [Spring/Summer/Autumn/Winter]", EngineWeather.seasons, defaultValue: w.season) ?? w.season
            w.season = EngineWeather.seasons.contains(k) ? k : "Summer"
            store(w, in: ed)
            ed.print("Season: " + w.season + ".")
        }
    }

    static var animate: CommandDef {
        CommandDef("ANIMATE", aliases: ["OBJANIMATE", "OBJECTANIMATION", "DOORANIMATE"], category: "View", summary: "Object animation saved in the drawing: Door swings, Rotate about a pivot, Move by a vector (start time, duration, there and back); Play/Stop in 3D, List, Delete, Clear, Render a frame.") { ed in
            var anims = EngineAnimations.load(ed.doc)
            let mm = ed.doc.units.mm
            let k = try await ed.getKeyword("Animate [Door/Rotate/Move/Play/Stop/List/Delete/Clear/Frame]", ["Door", "Rotate", "Move", "Play", "Stop", "List", "Delete", "Clear", "Frame"], defaultValue: "Door") ?? "Door"
            switch k {
            case "Play":
                guard !anims.isEmpty else { throw CommandError.invalid("No animations. Use ANIMATE Door, Rotate or Move first.") }
                show3D(ed)
                try view3d(ed, "animate", [("play", .bool(true))])
                let total = EngineAnimations.duration(anims)
                ed.print("Playing \(anims.count) animation(s), \(fmt(total, 1)) s loop. ANIMATE Stop ends.")
                return
            case "Stop": try view3d(ed, "animate", [("play", .bool(false))]); return
            case "List":
                if anims.isEmpty { ed.print("No animations."); return }
                for a in anims { ed.print(EngineAnimations.describe(a, mm: mm)) }
                return
            case "Delete":
                let n = try await ed.getInteger("Animation number to delete") ?? -1
                guard anims.contains(where: { $0.id == n }) else { throw CommandError.invalid("No animation " + String(n) + ".") }
                anims.removeAll { $0.id == n }
            case "Clear": anims = []
            case "Frame":
                let t = try await number(ed, "Time (s)", 1)
                let def = defaultPath(ed, "png", suffix: " frame")
                guard let url = try await path(ed, "Image file", ext: "png", def: def) else { return }
                let spp = Int(try await number(ed, "Samples per pixel", 32))
                show3D(ed)
                try view3d(ed, "animationFrame", [("time", .number(t)), ("path", .string(url)), ("samples", .int(max(1, spp)))])
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
                        guard let el = ed.doc.element(id) else { continue }
                        let leaves = EngineDoorLeaves.leaves(el, doc: ed.doc)
                        if leaves.isEmpty { continue }
                        anims.removeAll { $0.target == id && $0.kind == "Door" }
                        let first = EngineAnimations.nextID(anims)
                        for (i, l) in leaves.enumerated() {
                            let name = "Door " + String(el.id) + (i > 0 ? " leaf 2" : "")
                            anims.append(EngineAnimation(id: first + i, target: el.id, kind: "Door", pivot: Vec3(l.hinge.x, l.hinge.y, 0), angle: ang * l.sign,
                                                         offset: .zero, start: start, duration: dur, pingPong: back, name: name))
                        }
                        n += 1
                    }
                    guard n > 0 else { throw CommandError.invalid("Select single or double swing doors in straight walls.") }
                    ed.print(String(n) + " door(s) animated.")
                } else if k == "Rotate" {
                    let p = try await ed.requirePoint("Pivot point (vertical axis)")
                    let ang = try await number(ed, "Rotation angle (degrees)", 90)
                    for id in ids { anims.append(EngineAnimation(id: EngineAnimations.nextID(anims), target: id, kind: "Rotate", pivot: Vec3(p.x * mm, p.y * mm, 0), angle: ang, offset: .zero, start: start, duration: dur, pingPong: back, name: "")) }
                } else {
                    let a = try await ed.requirePoint("Base point")
                    let b = try await ed.requirePoint("Second point", base: a) { q in [.line(LineGeom(a, q))] }
                    let dz = try await number(ed, "Vertical movement", 0)
                    let off = Vec3((b.x - a.x) * mm, (b.y - a.y) * mm, dz * mm)
                    for id in ids { anims.append(EngineAnimation(id: EngineAnimations.nextID(anims), target: id, kind: "Move", pivot: .zero, angle: 90, offset: off, start: start, duration: dur, pingPong: back, name: "")) }
                }
            }
            EngineAnimations.store(anims, in: &ed.doc)
            ed.print(String(anims.count) + " animation(s), total " + fmt(EngineAnimations.duration(anims), 1) + " s.")
        }
    }

    // MARK: Images

    @MainActor static func eyePosition(_ ed: Editor) async throws -> Vec3 {
        let hasView = (try? state(ed).camera) != nil
        let k = try await ed.getKeyword("Eye position [Camera/Point]", ["Camera", "Point"], defaultValue: hasView ? "Camera" : "Point") ?? "Camera"
        if k == "Point" {
            let p = try await ed.requirePoint("Eye position in plan")
            let base = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            return Vec3(p.x, p.y, base + 1600 / max(ed.doc.units.mm, 1e-9))
        }
        guard let c = try state(ed).camera else { throw CommandError.invalid("Open the 3D view first, or use Point.") }
        return c.eye
    }

    static var panorama: CommandDef {
        CommandDef("PANORAMA", aliases: ["360", "PANO", "RENDER360"], category: "View",
                   summary: "Renders a 360° equirectangular panorama (PNG/JPEG) from the 3D camera position or a picked plan point.", modifies: false) { ed in
            let eye = try await eyePosition(ed)
            guard let w = try await ed.getInteger("Width in pixels (height = width / 2)", defaultValue: 4096), w >= 256 else { return }
            let def = defaultPath(ed, "jpg", suffix: " 360")
            let s = try await ed.getString("Output file (.jpg/.png) <choose>", defaultValue: "") ?? ""
            let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            show3D(ed)
            try view3d(ed, "panorama", [("eye", EngineJSON.point3(eye)), ("width", .int(min(w, 8192))), ("stereo", .bool(false)),
                                        ("path", t.isEmpty ? .null : .string((t as NSString).expandingTildeInPath)), ("suggested", .string(def))])
        }
    }

    static var stereoPanorama: CommandDef {
        CommandDef("STEREOPANORAMA", aliases: ["STEREO360", "ODSPANORAMA", "VRPANORAMA"], category: "View", summary: "Stereo 360° panorama for VR viewers: left and right eye equirectangular images over-under (omni-directional stereo), from the 3D camera or a plan point.", modifies: false) { ed in
            let eye = try await eyePosition(ed)
            guard let w = try await ed.getInteger("Width in pixels (each eye is width × width/2) <4096>", defaultValue: 4096), w >= 256 else { return }
            let ipd = try await number(ed, "Eye separation (interpupillary distance)", 64 / ed.doc.units.mm)
            guard let url = try await path(ed, "Image file (.jpg/.png)", ext: "jpg", def: defaultPath(ed, "jpg", suffix: "-360-stereo")) else { return }
            show3D(ed)
            try view3d(ed, "panorama", [("eye", EngineJSON.point3(eye)), ("width", .int(min(w, 8192))), ("stereo", .bool(true)),
                                        ("ipd", .number(ipd * ed.doc.units.mm)), ("path", .string(url))])
        }
    }

    static var viewImage: CommandDef {
        CommandDef("VIEWIMAGE", aliases: ["VIEWPORTIMAGE", "SAVEIMG3D"], category: "View", summary: "Saves the 3D view as a PNG, JPEG or TIFF at a chosen size, optionally with a transparent background.", modifies: false) { ed in
            show3D(ed)
            let w = try await ed.getInteger("Image width in pixels", defaultValue: 1920) ?? 1920
            let h = try await ed.getInteger("Image height in pixels", defaultValue: 1080) ?? 1080
            guard (16...16384).contains(w), (16...16384).contains(h) else { throw CommandError.invalid("Width and height must be 16–16384 pixels.") }
            let fk = try await ed.getKeyword("Format [Png/Jpeg/Tiff]", ["Png", "Jpeg", "Tiff"], defaultValue: "Png") ?? "Png"
            let clear = fk == "Jpeg" ? false : try await ed.getKeyword("Transparent background? [Yes/No]", ["Yes", "No"], defaultValue: "No") == "Yes"
            let s = try await ed.getString("File name (Enter = choose)", defaultValue: "") ?? ""
            let t = s.trimmingCharacters(in: .whitespaces)
            let ext = fk == "Jpeg" ? "jpg" : fk.lowercased()
            var p: String? = nil
            if !t.isEmpty { p = (t as NSString).expandingTildeInPath; if (p! as NSString).pathExtension.isEmpty { p! += "." + ext } }
            try view3d(ed, "viewImage", [("width", .int(w)), ("height", .int(h)), ("format", .string(fk.uppercased())), ("transparent", .bool(clear)),
                                         ("path", p.map { EngineJSON.string($0) } ?? .null), ("suggested", .string(defaultPath(ed, ext, suffix: " 3D")))])
        }
    }
}

// MARK: - Object animations (ObjectAnimation / ObjectAnimations of ArchiApp/SceneEffects.swift, OBJANIM JSON)

struct EngineAnimation: Codable, Equatable {
    var id: Int
    var target: Int
    var kind: String
    var pivot: Vec3
    var angle: Double
    var offset: Vec3
    var start: Double
    var duration: Double
    var pingPong: Bool
    var name: String

    init(id: Int, target: Int, kind: String, pivot: Vec3, angle: Double, offset: Vec3, start: Double, duration: Double, pingPong: Bool, name: String) {
        self.id = id; self.target = target; self.kind = kind; self.pivot = pivot; self.angle = angle; self.offset = offset
        self.start = start; self.duration = duration; self.pingPong = pingPong; self.name = name
    }
    enum CodingKeys: String, CodingKey { case id, target, kind, pivot, angle, offset, start, duration, pingPong, name }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); target = try c.decode(Int.self, forKey: .target)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "Rotate"
        pivot = try c.decodeIfPresent(Vec3.self, forKey: .pivot) ?? .zero
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 90
        offset = try c.decodeIfPresent(Vec3.self, forKey: .offset) ?? .zero
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 2
        pingPong = try c.decodeIfPresent(Bool.self, forKey: .pingPong) ?? true
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
    var end: Double { start + max(duration, 1e-6) * (pingPong ? 2 : 1) }
}

enum EngineAnimations {
    static let variable = "OBJANIM"
    static func load(_ doc: ArchiDocument) -> [EngineAnimation] {
        guard let s = doc.variable(variable), let a = try? JSONDecoder().decode([EngineAnimation].self, from: Data(s.utf8)) else { return [] }
        return a
    }
    static func store(_ a: [EngineAnimation], in doc: inout ArchiDocument) {
        if a.isEmpty { doc.variables[variable] = nil; return }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(a) { doc.setVariable(variable, String(decoding: d, as: UTF8.self)) }
    }
    static func duration(_ a: [EngineAnimation]) -> Double { a.map(\.end).max() ?? 0 }
    static func nextID(_ a: [EngineAnimation]) -> Int { (a.map(\.id).max() ?? 0) + 1 }
    static func describe(_ a: EngineAnimation, mm: Double) -> String {
        var s = "  \(a.id): \(a.kind) #\(a.target)"
        if !a.name.isEmpty { s += " \"" + a.name + "\"" }
        let move = a.offset.length / mm
        s += " — \(fmt(a.angle, 0))°, move \(fmt(move, 0)), \(fmt(a.start, 1))–\(fmt(a.end, 1)) s"
        if a.pingPong { s += " (there and back)" }
        return s
    }
}
