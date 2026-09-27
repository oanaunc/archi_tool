// Oanarina Archi Tool — GPL-3.0-or-later
// 3D view data for the Windows shell (docs/ENGINE-PROTOCOL.md "3D view"): everything the Mac 3D viewport reads from the
// document besides the meshes — saved cameras (Front / Aerial / Corner …), section box and plane, projection, visual
// style, render preset, PBR material maps with texture paths, water materials, weather and season, object animations
// with door leaves, levels — plus the plane caps of the live section (ArchiApp/Viewport3DExtras.swift updateCaps,
// AppAlgorithms.swift SectionCap) and the 3D gizmo edits (ArchiApp/Viewport3DTools.swift GizmoMath, Studio3D.swift ZMove).
import Foundation

public enum EngineView3DMethods {
    public static let all: [String] = ["view3d.info", "view3d.setVariable", "view3d.setCamera", "view3d.sectionCaps", "view3d.transform", "view3d.sun",
                                       "view3d.saveCamera", "view3d.deleteCamera", "view3d.saveImage"]
    /// Drawing variables the shell may set, with the undo label of the Mac control that sets them.
    static let variables: [String: String] = [
        "SECTIONBOX": "Section Box", "SECTIONPLANE": "Clipping Plane", "PERSPECTIVE": "Projection", "SUNSTUDY": "Sun Study",
        "RENDERPRESET": "RENDERPRESET", "WEATHER": "WEATHER", "OBJANIM": "ANIMATE",
    ]
    static let styles = ["Wireframe", "Hidden Line", "Shaded", "Shaded with Edges", "Conceptual", "Realistic", "X-Ray", "Sketchy"]

    /// VSCURRENT keywords (and shell names) → visual style name of the Mac 3D view.
    public static func styleName(_ s: String) -> String {
        let k = s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        switch k {
        case "2dwireframe", "wireframe", "3dwireframe": return "Wireframe"
        case "hidden", "hiddenline": return "Hidden Line"
        case "shaded": return "Shaded"
        case "shadedwithedges", "shadededges": return "Shaded with Edges"
        case "conceptual": return "Conceptual"
        case "realistic": return "Realistic"
        case "xray": return "X-Ray"
        case "sketchy": return "Sketchy"
        default: return styles.first { $0.caseInsensitiveCompare(s) == .orderedSame } ?? "Shaded with Edges"
        }
    }
}

/// Per-session state of the shell's 3D view that the Mac keeps in its view controller (not in the drawing).
@MainActor
final class EngineView3DState {
    /// Keyed by session; the weak reference tells a new session apart from a released one at the same address.
    final class Entry { weak var session: EngineSession?; let state: EngineView3DState; init(_ s: EngineSession, _ st: EngineView3DState) { session = s; state = st } }
    static var bySession: [ObjectIdentifier: Entry] = [:]
    /// Current 3D camera as the shell last reported it (model mm): SAVECAMERA, PANORAMA Camera, FOV.
    var camera: Camera?
    var style = "Shaded with Edges"
    var isolate: Int?
    var explodeGap = 0.0
    var gizmo = "Off"
    var measure = false
    var binaryCounter = 0
}

extension EngineSession {
    var view3d: EngineView3DState {
        let k = ObjectIdentifier(self)
        if let e = EngineView3DState.bySession[k], e.session === self { return e.state }
        EngineView3DState.bySession = EngineView3DState.bySession.filter { $0.value.session != nil }
        let s = EngineView3DState()
        EngineView3DState.bySession[k] = EngineView3DState.Entry(self, s)
        return s
    }

    /// Records the visual style the engine asked the shell for (VSCURRENT, RENDER, RENDERPRESET).
    func view3dStyleChanged(_ s: String) { view3d.style = EngineView3DMethods.styleName(s) }

    func view3dCall(_ method: String, _ p: EngineJSON) async throws -> EngineJSON {
        switch method {
        case "view3d.info": return view3dInfo()
        case "view3d.setVariable": return try view3dSetVariable(p)
        case "view3d.setCamera": return try view3dSetCamera(p)
        case "view3d.sectionCaps": return try view3dSectionCaps(p)
        case "view3d.transform": return try view3dTransform(p)
        case "view3d.sun": return try view3dSun(p)
        case "view3d.saveCamera": return try view3dSaveCamera(p)
        case "view3d.deleteCamera": return try view3dDeleteCamera(p)
        case "view3d.saveImage": return try view3dSaveImage(p)
        default: throw EngineError(EngineError.methodNotFound, "Method not found: " + method)
        }
    }

    // MARK: view3d.info

    static func cameraJSON(_ name: String?, _ c: Camera) -> EngineJSON {
        var o = EngineObject()
        if let name { o.set("name", name) }
        o.set("eye", EngineJSON.point3(c.eye))
        o.set("target", EngineJSON.point3(c.target))
        o.set("fov", c.fov)
        o.set("orthographic", c.orthographic)
        return o.json
    }

    func view3dInfo() -> EngineJSON {
        let doc = editor.doc
        let st = view3d
        var o = EngineObject()
        o.set("cameras", EngineJSON.array(doc.namedViews.compactMap { v in v.camera.map { EngineSession.cameraJSON(v.name, $0) } }))
        o.set("currentCamera", st.camera.map { EngineSession.cameraJSON(nil, $0) } ?? .null)
        var vars = EngineObject()
        let keys = ["SECTIONBOX", "SECTIONPLANE", "PERSPECTIVE", "RENDERPRESET", "SUNSTUDY", "WEATHER", "OBJANIM", "FOG", "FOGSTART", "FOGEND", "FOGCOLOR", "FOGDENSITY", "ARTIFICIALLIGHTS", "SUBOBJECTMODE"]
        for k in keys { if let v = doc.variable(k) { vars.set(k, v) } }
        o.set("variables", vars.json)
        o.set("sectionBox", EngineView3DData.boxJSON(doc.variable("SECTIONBOX")))
        o.set("sectionPlane", EngineView3DData.planeJSON(doc.variable("SECTIONPLANE")))
        o.set("perspective", doc.variable("PERSPECTIVE") != "0")
        o.set("visualStyle", st.style)
        o.set("renderPreset", EngineJSON.optString(doc.variable(EngineRenderPresets.variable).flatMap { EngineRenderPresets.named($0) }))
        o.set("materialMaps", EngineView3DData.materialMaps(doc))
        o.set("water", EngineJSON.strings(doc.materials.map(\.name).filter { EngineView3DData.isWater($0, doc: doc) }))
        o.set("weather", EngineView3DData.weather(doc))
        o.set("fog", EngineView3DData.fog(doc))
        o.set("animations", EngineView3DData.animations(doc))
        o.set("northAngle", doc.info.northAngle)
        o.set("units", doc.units.rawValue)
        o.set("unitMM", doc.units.mm)
        var lv: [EngineJSON] = []
        for l in doc.levels.sorted(by: { ($0.elevation, $0.id) < ($1.elevation, $1.id) }) {
            var x = EngineObject()
            x.set("id", l.id); x.set("name", l.name); x.set("elevation", l.elevation); x.set("height", l.height)
            lv.append(x.json)
        }
        o.set("levels", EngineJSON.array(lv))
        o.set("currentLevel", doc.currentLevel)
        var lvView = EngineObject()
        lvView.set("isolate", st.isolate.map { EngineJSON.int($0) } ?? .null)
        lvView.set("explodeGap", st.explodeGap)
        o.set("levelView", lvView.json)
        o.set("gizmo", st.gizmo)
        o.set("measure", st.measure)
        o.set("site", EngineView3DData.site(doc))
        return o.json
    }

    // MARK: view3d.setVariable / setCamera

    func view3dSetVariable(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name").uppercased()
        var value: String? = nil
        if let v = p["value"], !v.isNull {
            if let t = v.stringValue { value = t } else if let d = v.doubleValue { value = fmt(d) }
        }
        if name == "VSCURRENT" {
            let s = EngineView3DMethods.styleName(value ?? "Shaded with Edges")
            view3d.style = s
            var o = EngineObject(); o.set("name", name); o.set("value", s); o.set("changed", false)
            return o.json
        }
        guard let label = EngineView3DMethods.variables[name] else {
            throw EngineError.params("'\(name)' is not a 3D view variable (SECTIONBOX, SECTIONPLANE, PERSPECTIVE, SUNSTUDY, RENDERPRESET, WEATHER, OBJANIM, VSCURRENT)")
        }
        if let v = value, !EngineView3DData.valid(name, v) { throw EngineError.params("invalid value for \(name): \(v)") }
        let old = editor.doc.variable(name)
        let changed = old != value
        if changed { editor.transaction(label) { d in if let v = value { d.setVariable(name, v) } else { d.variables[name] = nil } } }
        var o = EngineObject()
        o.set("name", name)
        o.set("value", EngineJSON.optString(value))
        o.set("changed", changed)
        return o.json
    }

    func view3dSetCamera(_ p: EngineJSON) throws -> EngineJSON {
        guard let e = EngineView3DData.vec3(p["eye"]), let t = EngineView3DData.vec3(p["target"]) else { throw EngineError.params("missing 'eye' / 'target' ([x,y,z], model mm)") }
        let fov = p["fov"]?.doubleValue ?? 45
        view3d.camera = Camera(eye: e, target: t, fov: min(max(fov, 1), 170), orthographic: p["orthographic"]?.boolValue ?? false)
        var o = EngineObject(); o.set("ok", true)
        return o.json
    }

    // MARK: view3d.saveCamera / deleteCamera (CameraStore.save, CamerasMenu Delete)

    func view3dSaveCamera(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw EngineError.params("empty camera name") }
        if p["eye"] != nil { _ = try view3dSetCamera(p) }
        guard let c = view3d.camera else { throw EngineError.failed("Open the 3D view first.") }
        let center = Vec2(c.target.x, c.target.y)
        let h = max(1000, (c.eye - c.target).length)
        editor.transaction("Save Camera") { d in
            d.namedViews.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.camera != nil }
            d.namedViews.append(NamedView(name: name, center: center, height: h, camera: c))
        }
        editor.print("Camera “" + name + "” saved.")
        return view3dInfo()["cameras"] ?? .array([])
    }

    func view3dDeleteCamera(_ p: EngineJSON) throws -> EngineJSON {
        let name = try string(p, "name")
        guard editor.doc.namedViews.contains(where: { $0.name == name && $0.camera != nil }) else { throw EngineError.params("no saved camera named " + name) }
        editor.transaction("Delete Camera") { d in d.namedViews.removeAll { $0.name == name && $0.camera != nil } }
        return view3dInfo()["cameras"] ?? .array([])
    }

    // MARK: view3d.saveImage (renders, panoramas and view images made by the shell)

    /// Writes base64 image data the shell rendered to `path` (relative to the session folder), creating folders.
    func view3dSaveImage(_ p: EngineJSON) throws -> EngineJSON {
        let path = try string(p, "path")
        guard let b64 = p["data"]?.stringValue, let data = Data(base64Encoded: b64) else { throw EngineError.params("missing base64 'data'") }
        let u = url(path)
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: u, options: .atomic)
        } catch { throw EngineError.failed("Cannot write " + u.path + ": " + EngineSession.describe(error)) }
        var o = EngineObject()
        o.set("path", u.path)
        o.set("bytes", data.count)
        return o.json
    }

    // MARK: view3d.sectionCaps

    /// Cap faces where the section plane cuts the model: `{point, normal}` or the drawing's SECTIONPLANE.
    func view3dSectionCaps(_ p: EngineJSON) throws -> EngineJSON {
        var point = EngineView3DData.vec3(p["point"])
        var normal = EngineView3DData.vec3(p["normal"])
        if point == nil || normal == nil, let pl = EngineView3DData.parsePlane(editor.doc.variable("SECTIONPLANE")), pl.on {
            point = pl.point; normal = pl.normal
        }
        var o = EngineObject()
        o.set("color", "#8c1f1a")
        guard let pt = point, let n0 = normal, n0.length > 1e-9 else {
            o.set("triangleCount", 0); o.set("positions", ""); return o.json
        }
        let n = n0.normalized
        let offset = n * -0.5
        var floats: [Float] = []
        for g in MeshBuilder.build(doc: editor.doc) where !g.mesh.isEmpty {
            let m = g.mesh
            let tris = EngineSectionCap.triangles(of: m)
            let loops = EngineSectionCap.loops(tris, point: pt, normal: n)
            if loops.isEmpty { continue }
            for (a, b, c) in EngineSectionCap.triangles(loops, normal: n) {
                for q in [a + offset, b + offset, c + offset] { floats.append(Float(q.x)); floats.append(Float(q.y)); floats.append(Float(q.z)) }
            }
        }
        o.set("normal", EngineJSON.point3(n))
        o.set("triangleCount", floats.count / 9)
        o.set("positions", EngineMeshJSON.base64(floats))
        return o.json
    }

    // MARK: view3d.transform (the 3D gizmo's commit)

    /// Applies a gizmo drag to the selection (or `ids`) as one undo step: `op` = move (axis 0 = X, 1 = Y, 3 = Z),
    /// rotate (radians about Z through `pivot`) or scale (uniform in plan about `pivot`).
    func view3dTransform(_ p: EngineJSON) throws -> EngineJSON {
        let op = (p["op"]?.stringValue ?? "move").lowercased()
        let amount = try number(p, "amount")
        let ids = p["ids"]?.arrayValue?.compactMap { $0.intValue } ?? Array(editor.selection).sorted()
        let pivot = p["pivot"]?.vec2 ?? .zero
        let axis = p["axis"]?.intValue ?? 0
        var o = EngineObject()
        var msg = ""
        var n = 0
        switch op {
        case "scale":
            guard amount > 0 else { throw EngineError.params("scale factor must be positive") }
            guard abs(amount - 1) > 1e-9 else { break }
            n = EngineGizmo.apply(editor, ids: ids, .scale(amount, amount, around: pivot), label: "Scale (3D gizmo)")
            msg = "Scaled \(n) object(s) by \(fmt(amount, 4)) in plan."
        case "rotate":
            guard abs(amount) > 1e-9 else { break }
            n = EngineGizmo.apply(editor, ids: ids, .rotation(amount, around: pivot), label: "Rotate (3D gizmo)")
            let deg = amount * 180 / .pi
            msg = "Rotated \(n) object(s) by \(fmt(deg, 2))°."
        case "move", "movez":
            guard abs(amount) > 1e-9 else { break }
            if op == "movez" || axis == 3 {
                let r = EngineGizmo.moveZ(editor, ids: ids, dz: amount, label: "Move Z (3D gizmo)")
                n = r.moved
                msg = "Moved \(r.moved) object(s) by \(fmt(amount, 2)) along Z"
                msg += r.skipped > 0 ? "; " + String(r.skipped) + " object(s) have no height to change." : "."
            } else {
                let t: Transform2D = axis == 1 ? .translation(Vec2(0, amount)) : .translation(Vec2(amount, 0))
                n = EngineGizmo.apply(editor, ids: ids, t, label: "Move (3D gizmo)")
                let axisName = axis == 1 ? "Y" : "X"
                msg = "Moved \(n) object(s) by \(fmt(amount, 2)) along \(axisName)."
            }
        default: throw EngineError.params("op must be move, movez, rotate or scale")
        }
        if !msg.isEmpty { editor.print(msg) }
        o.set("changed", n)
        o.set("message", msg)
        return o.json
    }

    // MARK: view3d.sun (sun study)

    /// Sun direction for a day of the year and local hour at the site (the Mac sun study panel).
    func view3dSun(_ p: EngineJSON) throws -> EngineJSON {
        let doc = editor.doc
        let day = p["day"]?.intValue ?? 172
        let hour = p["hour"]?.doubleValue ?? 15
        let s = EngineSunStudy.compute(dayOfYear: day, localHour: hour, latitude: doc.info.latitude, longitude: doc.info.longitude,
                                       utcOffsetHours: (doc.info.longitude / 15).rounded())
        var o = EngineObject()
        o.set("day", day); o.set("hour", hour)
        o.set("altitude", s.altitude * 180 / .pi)
        o.set("azimuth", s.azimuth * 180 / .pi)
        o.set("aboveHorizon", s.altitude > 0)
        let dir = EngineRenderPresets.sunDirection(altitude: s.altitude * 180 / .pi, azimuth: s.azimuth * 180 / .pi, northAngleDegrees: doc.info.northAngle)
        o.set("direction", EngineJSON.point3(dir))
        let altDeg = s.altitude * 180 / .pi, azDeg = s.azimuth * 180 / .pi
        let above = "Altitude \(fmt(altDeg, 1))°, azimuth \(fmt(azDeg, 1))° · site \(fmt(doc.info.latitude, 2))°, \(fmt(doc.info.longitude, 2))°"
        o.set("text", s.altitude <= 0 ? "Sun below the horizon" : above)
        return o.json
    }
}

// MARK: - Document data

enum EngineView3DData {
    static func vec3(_ j: EngineJSON?) -> Vec3? {
        guard let a = j?.arrayValue, a.count == 3, let x = a[0].doubleValue, let y = a[1].doubleValue, let z = a[2].doubleValue,
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        return Vec3(x, y, z)
    }

    static func numbers(_ s: Substring) -> [Double] { s.split(separator: ",").compactMap { Double($0) }.filter(\.isFinite) }

    static func parseBox(_ s: String?) -> (on: Bool, min: Vec3, max: Vec3)? {
        guard let s else { return nil }
        let parts = s.split(separator: ";")
        guard parts.count == 2 else { return nil }
        let n = numbers(parts[1])
        guard n.count == 6 else { return nil }
        let lo = Vec3(min(n[0], n[3]), min(n[1], n[4]), min(n[2], n[5]))
        let hi = Vec3(max(n[0], n[3]), max(n[1], n[4]), max(n[2], n[5]))
        return (parts[0] == "on", lo, hi)
    }

    static func parsePlane(_ s: String?) -> (on: Bool, point: Vec3, normal: Vec3)? {
        guard let s else { return nil }
        let parts = s.split(separator: ";")
        guard parts.count == 3 else { return nil }
        let p = numbers(parts[1]), n = numbers(parts[2])
        guard p.count == 3, n.count == 3 else { return nil }
        let nv = Vec3(n[0], n[1], n[2])
        guard nv.length > 1e-9 else { return nil }
        return (parts[0] == "on", Vec3(p[0], p[1], p[2]), nv.normalized)
    }

    static func boxJSON(_ s: String?) -> EngineJSON {
        guard let b = parseBox(s) else { return .null }
        var o = EngineObject()
        o.set("on", b.on); o.set("min", EngineJSON.point3(b.min)); o.set("max", EngineJSON.point3(b.max))
        return o.json
    }

    static func planeJSON(_ s: String?) -> EngineJSON {
        guard let p = parsePlane(s) else { return .null }
        var o = EngineObject()
        o.set("on", p.on); o.set("point", EngineJSON.point3(p.point)); o.set("normal", EngineJSON.point3(p.normal))
        return o.json
    }

    static func valid(_ name: String, _ v: String) -> Bool {
        switch name {
        case "SECTIONBOX": return parseBox(v) != nil
        case "SECTIONPLANE": return parsePlane(v) != nil
        case "PERSPECTIVE": return v == "0" || v == "1"
        case "RENDERPRESET": return EngineRenderPresets.named(v) != nil
        case "SUNSTUDY":
            let p = v.split(separator: ",").compactMap { Double($0) }
            return p.count == 2 && (1...366).contains(p[0]) && (0...24).contains(p[1])
        case "WEATHER": return EngineWeather(stored: v) != nil
        case "OBJANIM": return (try? EngineJSON.parse(v))?.arrayValue != nil
        default: return true
        }
    }

    /// MATMAPS:<NAME> of every material (JSON of MaterialMaps) with the albedo texture and scale beside the maps.
    static func materialMaps(_ doc: ArchiDocument) -> EngineJSON {
        var o = EngineObject()
        for m in doc.materials {
            let key = m.name.uppercased()
            guard let s = doc.variable("MATMAPS:" + key), let j = try? EngineJSON.parse(s), var fields = j.fields else { continue }
            if let t = m.texture, !t.isEmpty { fields.append(EngineJSONField("texture", .string(t))); fields.append(EngineJSONField("textureScale", .number(m.textureScale))) }
            if !fields.contains(where: { $0.key == "normalStrength" }) { fields.append(EngineJSONField("normalStrength", .number(1))) }
            o.set(key, EngineJSON.object(fields))
        }
        return o.json
    }

    /// Water surfaces (WaterSurface.isWater): MATWATER:<name> = 1, or the material named "Water".
    static func isWater(_ material: String, doc: ArchiDocument) -> Bool {
        if let v = doc.variable("MATWATER:" + material.uppercased()) { return v == "1" }
        return material.caseInsensitiveCompare("Water") == .orderedSame
    }

    static func weather(_ doc: ArchiDocument) -> EngineJSON {
        let w = doc.variable(EngineWeather.variable).flatMap(EngineWeather.init(stored:)) ?? EngineWeather()
        var o = EngineObject()
        o.set("kind", w.kind); o.set("intensity", w.intensity); o.set("season", w.season); o.set("snowCover", w.snowCover)
        o.set("wetness", w.wetness); o.set("snow", w.snow)
        o.set("fogDistance", w.fogDistance.map { EngineJSON.number($0) } ?? .null)
        if let p = w.particles {
            var q = EngineObject()
            q.set("birthRatePerM2", p.0); q.set("speed", p.1); q.set("size", p.2); q.set("life", p.3); q.set("stretch", p.4)
            o.set("particles", q.json)
        } else { o.set("particles", EngineJSON.null) }
        return o.json
    }

    static func fog(_ doc: ArchiDocument) -> EngineJSON {
        var o = EngineObject()
        o.set("on", doc.variable("FOG") == "1")
        let start = max(0, doc.variable("FOGSTART").flatMap(Double.init) ?? 5000)
        o.set("start", start)
        o.set("end", max(start + 1, doc.variable("FOGEND").flatMap(Double.init) ?? 60000))
        o.set("color", doc.variable("FOGCOLOR").flatMap { $0.hasPrefix("#") ? $0 : nil } ?? "#c7ccd6")
        o.set("density", min(max(doc.variable("FOGDENSITY").flatMap(Double.init) ?? 1, 0.1), 4))
        return o.json
    }

    static func site(_ doc: ArchiDocument) -> EngineJSON {
        var o = EngineObject()
        o.set("latitude", doc.info.latitude); o.set("longitude", doc.info.longitude)
        let s = doc.variable("SUNSTUDY")?.split(separator: ",").compactMap { Double($0) } ?? []
        o.set("day", s.count == 2 ? Int(s[0]) : 172)
        o.set("hour", s.count == 2 ? s[1] : 15)
        return o.json
    }

    /// OBJANIM with each door animation's leaf (hinge span along the wall) so the shell can split the door mesh.
    static func animations(_ doc: ArchiDocument) -> EngineJSON {
        guard let s = doc.variable("OBJANIM"), let arr = (try? EngineJSON.parse(s))?.arrayValue else { return .array([]) }
        var leafIndex: [Int: Int] = [:]
        var out: [EngineJSON] = []
        for a in arr {
            guard var fields = a.fields else { continue }
            if a["kind"]?.stringValue == "Door", let t = a["target"]?.intValue {
                let k = leafIndex[t, default: 0]
                leafIndex[t] = k + 1
                fields.append(EngineJSONField("leafIndex", .int(k)))
                let leaves = doc.element(t).map { EngineDoorLeaves.leaves($0, doc: doc) } ?? []
                if leaves.indices.contains(k) { fields.append(EngineJSONField("leaf", EngineDoorLeaves.json(leaves[k]))) }
            }
            out.append(.object(fields))
        }
        return .array(out)
    }
}

/// WeatherSettings of ArchiApp/SceneEffects.swift (WEATHER = "kind;intensity;season;snowCover").
struct EngineWeather: Equatable {
    static let variable = "WEATHER"
    static let kinds = ["Clear", "Rain", "Snow", "Fog"]
    static let seasons = ["Spring", "Summer", "Autumn", "Winter"]
    var kind = "Clear"
    var intensity = 0.5
    var season = "Summer"
    var snowCover = 0.0

    init() {}
    init?(stored s: String) {
        let p = s.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        guard let k = EngineWeather.kinds.first(where: { $0.caseInsensitiveCompare(p.first ?? "") == .orderedSame }) else { return nil }
        kind = k
        if p.count > 1, let v = Double(p[1]) { intensity = min(max(v, 0), 1) }
        if p.count > 2, let se = EngineWeather.seasons.first(where: { $0.caseInsensitiveCompare(p[2]) == .orderedSame }) { season = se }
        if p.count > 3, let v = Double(p[3]) { snowCover = min(max(v, 0), 1) }
    }
    var stored: String { "\(kind);\(fmt(intensity, 3));\(season);\(fmt(snowCover, 3))" }
    var wetness: Double { kind == "Rain" ? intensity : 0 }
    var snow: Double { snowCover > 0 ? snowCover : (kind == "Snow" ? intensity * 0.8 : 0) }
    var fogDistance: Double? {
        switch kind {
        case "Fog": return 30 + 400 * (1 - intensity)
        case "Rain": return 300 + 1500 * (1 - intensity)
        case "Snow": return 150 + 800 * (1 - intensity)
        default: return nil
        }
    }
    /// Drops or flakes per second per m², fall speed (m/s), size (m), lifespan (s), stretch.
    var particles: (Double, Double, Double, Double, Double)? {
        switch kind {
        case "Rain": return (40 * intensity, 6 + 3 * intensity, 0.006, 2.2, 12)
        case "Snow": return (12 * intensity, 0.8 + 0.4 * intensity, 0.02 + 0.015 * intensity, 12, 0)
        default: return nil
        }
    }
}

/// Door hinge geometry of ObjectAnimations.doorLeaves (ArchiApp/SceneEffects.swift): straight walls, single/double swing.
enum EngineDoorLeaves {
    struct Leaf { var hinge: Vec2; var sign: Double; var s0: Double; var s1: Double; var cs: Vec2; var dir: Vec2; var normal: Vec2; var wallHalf: Double }

    static func leaves(_ el: BIMElement, doc: ArchiDocument) -> [Leaf] {
        guard case .opening(let o) = el.geometry, o.kind == .door, o.doorStyle == .single || o.doorStyle == .double,
              let host = doc.element(o.hostWall), case .wall(let w) = host.geometry, abs(w.bulge) < 1e-9 else { return [] }
        let cs = w.centerStart, ce = w.centerEnd
        let len = cs.distance(to: ce)
        guard len > 1e-6 else { return [] }
        let dir = (ce - cs) / len
        let nrm = Vec2(-dir.y, dir.x)
        let fw = min(max(o.frameWidth, 0), o.width / 4, o.height / 4)
        let a = o.offset - o.width / 2 + fw
        let b = o.offset + o.width / 2 - fw
        let side: Double = o.flipFacing ? -1 : 1
        let h = max(w.thickness, 0) / 2
        let inset = 25 * (doc.units.mm > 0 ? 1 / doc.units.mm : 1)
        let tmid = side * (h - inset)
        func leaf(_ s0: Double, _ s1: Double, hingeAtStart: Bool) -> Leaf {
            let hs = hingeAtStart ? s0 : s1
            let hinge = cs + dir * hs + nrm * tmid
            let sign: Double = (hingeAtStart ? 1 : -1) * side
            return Leaf(hinge: hinge, sign: sign, s0: s0, s1: s1, cs: cs, dir: dir, normal: nrm, wallHalf: h)
        }
        if o.doorStyle == .double {
            let mid = (a + b) / 2
            return [leaf(a, mid, hingeAtStart: true), leaf(mid, b, hingeAtStart: false)]
        }
        return [leaf(a, b, hingeAtStart: !o.flipHand)]
    }

    static func json(_ l: Leaf) -> EngineJSON {
        var o = EngineObject()
        o.set("hinge", EngineJSON.point(l.hinge)); o.set("sign", l.sign); o.set("s0", l.s0); o.set("s1", l.s1)
        o.set("origin", EngineJSON.point(l.cs)); o.set("dir", EngineJSON.point(l.dir)); o.set("normal", EngineJSON.point(l.normal))
        o.set("wallHalf", l.wallHalf)
        return o.json
    }
}

/// SectionCap of ArchiApp/AppAlgorithms.swift: cut outlines of a triangle soup with a plane and their triangulation.
enum EngineSectionCap {
    static func triangles(of m: Mesh) -> [(Vec3, Vec3, Vec3)] {
        var tris: [(Vec3, Vec3, Vec3)] = []
        tris.reserveCapacity(m.indices.count / 3)
        var i = 0
        let n = m.positions.count
        while i + 2 < m.indices.count {
            let a = Int(m.indices[i]), b = Int(m.indices[i + 1]), c = Int(m.indices[i + 2])
            i += 3
            if a < n && b < n && c < n { tris.append((m.positions[a], m.positions[b], m.positions[c])) }
        }
        return tris
    }

    static func loops(_ tris: [(Vec3, Vec3, Vec3)], point p0: Vec3, normal n0: Vec3, tolerance: Double = 1e-4) -> [[Vec3]] {
        let n = n0.normalized
        guard n.length > 0.5 else { return [] }
        func key(_ v: Vec3) -> [Int64] { [Int64((v.x / tolerance).rounded()), Int64((v.y / tolerance).rounded()), Int64((v.z / tolerance).rounded())] }
        var segs: [(Vec3, Vec3)] = []
        for (a, b, c) in tris {
            let da = (a - p0).dot(n), db = (b - p0).dot(n), dc = (c - p0).dot(n)
            if (da > 0 && db > 0 && dc > 0) || (da < 0 && db < 0 && dc < 0) { continue }
            var pts: [Vec3] = []
            for (u, du, v, dv) in [(a, da, b, db), (b, db, c, dc), (c, dc, a, da)] {
                if (du < 0 && dv > 0) || (du > 0 && dv < 0) { pts.append(u + (v - u) * (du / (du - dv))) }
                else if abs(du) < 1e-12 && abs(dv) >= 1e-12 { pts.append(u) }
            }
            var uniq: [Vec3] = []
            for q in pts where !uniq.contains(where: { key($0) == key(q) }) { uniq.append(q) }
            if uniq.count == 2 { segs.append((uniq[0], uniq[1])) }
        }
        var adj: [[Int64]: [Int]] = [:]
        for (i, s) in segs.enumerated() { adj[key(s.0), default: []].append(i); adj[key(s.1), default: []].append(i) }
        var used = [Bool](repeating: false, count: segs.count)
        var loops: [[Vec3]] = []
        for i in segs.indices where !used[i] {
            used[i] = true
            var loop = [segs[i].0, segs[i].1]
            var closed = false
            while true {
                let endKey = key(loop.last!)
                if endKey == key(loop[0]) && loop.count > 2 { loop.removeLast(); closed = true; break }
                guard let j = adj[endKey]?.first(where: { !used[$0] }) else { break }
                used[j] = true
                let s = segs[j]
                loop.append(key(s.0) == endKey ? s.1 : s.0)
            }
            if closed { loop = simplify(loop) }
            if closed && loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    static func simplify(_ l: [Vec3]) -> [Vec3] {
        var pts = l
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in pts.indices {
                let a = pts[(i + pts.count - 1) % pts.count], p = pts[i], b = pts[(i + 1) % pts.count]
                let u = p - a, v = b - p
                if u.length < 1e-9 || v.length < 1e-9 || u.cross(v).length <= 1e-9 * u.length * v.length {
                    pts.remove(at: i); changed = true; break
                }
            }
        }
        return pts
    }

    static func inside(_ p: Vec2, _ poly: [Vec2]) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { c.toggle() }
            }
            j = i
        }
        return c
    }

    static func triangles(_ loops: [[Vec3]], normal n0: Vec3) -> [(Vec3, Vec3, Vec3)] {
        let n = n0.normalized
        let (u, v) = Mesh.basis(n)
        let origin = loops.first?.first ?? .zero
        let flat: [[Vec2]] = loops.map { l in l.map { q in let d = q - origin; return Vec2(d.dot(u), d.dot(v)) } }
        var depth: [Int] = []
        for i in flat.indices {
            var k = 0
            for j in flat.indices where j != i && !flat[i].isEmpty && inside(flat[i][0], flat[j]) { k += 1 }
            depth.append(k)
        }
        var out: [(Vec3, Vec3, Vec3)] = []
        for i in flat.indices where depth[i] % 2 == 0 {
            var holes: [[Vec2]] = []
            for j in flat.indices where depth[j] == depth[i] + 1 && inside(flat[j][0], flat[i]) { holes.append(flat[j]) }
            let r = Triangulator.triangulateWithPoints(flat[i], holes: holes)
            for (a, b, c) in r.triangles {
                let pa = origin + u * r.points[a].x + v * r.points[a].y
                let pb = origin + u * r.points[b].x + v * r.points[b].y
                let pc = origin + u * r.points[c].x + v * r.points[c].y
                out.append((pa, pb, pc))
            }
        }
        return out
    }
}

/// GizmoMath.apply and ZMove of the Mac 3D gizmo (ArchiApp/Viewport3DTools.swift, Studio3D.swift).
enum EngineGizmo {
    @MainActor @discardableResult
    static func apply(_ ed: Editor, ids: [EntityID], _ t: Transform2D, label: String) -> Int {
        let targets = ed.expandGroups(ids).filter { ed.isSelectable($0) }
        guard !targets.isEmpty else { return 0 }
        var n = 0
        ed.transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) { d.entities[i].geometry = GeometryOps.transform(d.entities[i].geometry, t); n += 1 }
                else if let i = d.elementIndex(id) { d.elements[i].geometry = CommandHelpers.transform(d.elements[i].geometry, t); n += 1 }
            }
        }
        return n
    }

    static func shifted(_ g: BIMGeometry, dz: Double) -> BIMGeometry? {
        switch g {
        case .wall(var w): w.baseOffset += dz; if w.topLevel != nil { w.topOffset += dz }; return .wall(w)
        case .slab(var s): s.topOffset += dz; return .slab(s)
        case .column(var c): c.baseOffset += dz; return .column(c)
        case .beam(var b): b.topOffset += dz; if let e = b.endTopOffset { b.endTopOffset = e + dz }; return .beam(b)
        case .opening(var o): o.sill += dz; return .opening(o)
        case .roof(var r): r.baseOffset += dz; return .roof(r)
        case .railing(var r): r.baseOffset += dz; return .railing(r)
        case .curtainWall(var c): c.baseOffset += dz; return .curtainWall(c)
        case .component(var c): c.baseOffset += dz; return .component(c)
        case .stair, .space, .gridLine: return nil
        }
    }

    static func shifted(_ g: Geometry, dz: Double) -> Geometry? {
        if case .solid(let s) = g { return .solid(SolidOps.translated(s, by: Vec3(0, 0, dz))) }
        return nil
    }

    @MainActor @discardableResult
    static func moveZ(_ ed: Editor, ids: [EntityID], dz: Double, label: String) -> (moved: Int, skipped: Int) {
        let targets = ed.expandGroups(ids).filter { ed.isSelectable($0) }
        guard !targets.isEmpty, abs(dz) > 1e-12 else { return (0, targets.count) }
        var n = 0, skipped = 0
        ed.transaction(label) { d in
            for id in targets {
                if let i = d.entityIndex(id) {
                    if let g = shifted(d.entities[i].geometry, dz: dz) { d.entities[i].geometry = g; n += 1 } else { skipped += 1 }
                } else if let i = d.elementIndex(id) {
                    if let g = shifted(d.elements[i].geometry, dz: dz) { d.elements[i].geometry = g; n += 1 } else { skipped += 1 }
                }
            }
        }
        return (n, skipped)
    }
}

/// SunPosition.compute of ArchiApp/RenderController.swift (NOAA solar calculator): the Mac sun study panel's sun.
enum EngineSunStudy {
    static func utcDate(year: Int, dayOfYear n: Int, localHour h: Double, utcOffsetHours tz: Double) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
        let seconds = Double(n - 1) * 86400 + (h - tz) * 3600
        return jan1.addingTimeInterval(seconds)
    }

    /// Altitude above the horizon and azimuth clockwise from true north, radians.
    static func compute(dayOfYear n: Int, localHour h: Double, latitude: Double, longitude: Double, utcOffsetHours tz: Double,
                        year: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> (altitude: Double, azimuth: Double) {
        let d = utcDate(year: year, dayOfYear: n, localHour: h, utcOffsetHours: tz)
        let p = SolarCalculator.position(date: d, latitude: latitude, longitude: longitude)
        return (p.altitude * .pi / 180, p.azimuth * .pi / 180)
    }
}

extension EngineSession {
    /// model.meshes "binary": a path (relative to the session folder), or true for a fresh temporary file
    /// (archi-engine-<pid>-meshes-<n>.bin, replaced by the next transfer of this session).
    func view3dBinaryPath(_ v: EngineJSON?) -> String? {
        guard let v, !v.isNull else { return nil }
        if case .bool(let b) = v {
            guard b else { return nil }
            let st = view3d
            let pid = ProcessInfo.processInfo.processIdentifier
            let prev = FileManager.default.temporaryDirectory.appendingPathComponent("archi-engine-\(pid)-meshes-\(st.binaryCounter).bin")
            try? FileManager.default.removeItem(at: prev)
            st.binaryCounter += 1
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("archi-engine-\(pid)-meshes-\(st.binaryCounter).bin")
            return u.path
        }
        guard let s = v.stringValue, !s.isEmpty else { return nil }
        return s
    }
}
