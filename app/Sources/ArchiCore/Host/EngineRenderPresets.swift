// Oanarina Archi Tool — GPL-3.0-or-later
// The photographic lighting presets of the Mac app (ArchiApp/BeautyLighting.swift, RENDERPRESET) as portable data, so
// the Windows three.js viewport lights the model with exactly the same values. Keep the numbers in step with
// BeautyPreset.look on the Mac.
import Foundation

public struct EngineLook: Equatable {
    public var preset: String
    public var keyword: String
    public var sky: String
    /// Sun (moon) altitude above the horizon and azimuth clockwise from project north, degrees.
    public var sunAltitude: Double
    public var sunAzimuth: Double
    /// Linear RGB.
    public var sunColor: [Double]
    public var sunIntensity: Double
    public var shadowRadius: Double
    public var shadowAlpha: Double
    public var envIntensity: Double
    public var ambient: Double
    public var exposure: Double
    public var whitePoint: Double
    public var bloom: Double
    public var bloomThreshold: Double
    public var saturation: Double
    public var contrast: Double
    public var ao: Double
    public var windowGlow: Double
    public var artificial: Double
    public var lampGlow: Double
}

public enum EngineRenderPresets {
    /// Drawing variable holding the preset (same as the Mac BeautyPreset.variable).
    public static let variable = "RENDERPRESET"
    public static let names = ["Daylight", "Golden hour", "Overcast", "Night"]
    public static let keywords = ["Daylight", "Goldenhour", "Overcast", "Night"]

    /// Lenient preset names, as BeautyPreset.named.
    public static func named(_ s: String) -> String? {
        let k = s.lowercased().filter { $0.isLetter }
        switch k {
        case "daylight", "day", "sunny", "clear", "clearsky", "noon": return "Daylight"
        case "goldenhour", "golden", "sunset", "sunrise", "evening", "warm": return "Golden hour"
        case "overcast", "cloudy", "soft", "grey", "gray": return "Overcast"
        case "night", "dusk", "dark", "nightlights", "bluehour": return "Night"
        default: return nil
        }
    }

    /// The preset stored in the drawing (Daylight when none was chosen).
    public static func current(_ doc: ArchiDocument) -> String { doc.variable(variable).flatMap(named) ?? "Daylight" }

    public static func look(_ name: String) -> EngineLook {
        switch named(name) ?? "Daylight" {
        case "Golden hour":
            return EngineLook(preset: "Golden hour", keyword: "Goldenhour", sky: "golden", sunAltitude: 11, sunAzimuth: 228, sunColor: [1.0, 0.66, 0.38],
                              sunIntensity: 3400, shadowRadius: 5, shadowAlpha: 0.9, envIntensity: 0.95, ambient: 0, exposure: 0.75, whitePoint: 1.7,
                              bloom: 0.22, bloomThreshold: 0.95, saturation: 1.1, contrast: 0.08, ao: 0.9, windowGlow: 0.12, artificial: 0.3, lampGlow: 1.0)
        case "Overcast":
            return EngineLook(preset: "Overcast", keyword: "Overcast", sky: "overcast", sunAltitude: 58, sunAzimuth: 200, sunColor: [0.93, 0.96, 1.0],
                              sunIntensity: 420, shadowRadius: 22, shadowAlpha: 0.7, envIntensity: 1.55, ambient: 0, exposure: 0.8, whitePoint: 1.5,
                              bloom: 0.05, bloomThreshold: 1.3, saturation: 0.98, contrast: 0.1, ao: 1.25, windowGlow: 0, artificial: 0.05, lampGlow: 0.4)
        case "Night":
            return EngineLook(preset: "Night", keyword: "Night", sky: "night", sunAltitude: 38, sunAzimuth: 135, sunColor: [0.62, 0.72, 1.0],
                              sunIntensity: 70, shadowRadius: 6, shadowAlpha: 0.85, envIntensity: 1.0, ambient: 8, exposure: 1.6, whitePoint: 1.2,
                              bloom: 0.55, bloomThreshold: 0.75, saturation: 1.0, contrast: 0.05, ao: 0.8, windowGlow: 1.6, artificial: 1.6, lampGlow: 3.0)
        default:
            return EngineLook(preset: "Daylight", keyword: "Daylight", sky: "daylight", sunAltitude: 46, sunAzimuth: 222, sunColor: [1.0, 0.955, 0.89],
                              sunIntensity: 3300, shadowRadius: 2.5, shadowAlpha: 0.94, envIntensity: 1.05, ambient: 0, exposure: 0.6, whitePoint: 1.7,
                              bloom: 0.10, bloomThreshold: 1.1, saturation: 1.06, contrast: 0.06, ao: 0.85, windowGlow: 0, artificial: 0, lampGlow: 0.3)
        }
    }

    /// Direction towards the sun in model coordinates (X east, Y north, Z up), as the Mac SunPosition.direction.
    public static func sunDirection(altitude: Double, azimuth: Double, northAngleDegrees: Double) -> Vec3 {
        let alt = altitude * .pi / 180, az = azimuth * .pi / 180
        let d = Vec2(sin(az), cos(az)).rotated(by: northAngleDegrees * .pi / 180) * cos(alt)
        return Vec3(d.x, d.y, sin(alt))
    }

    public static func json(_ l: EngineLook, northAngle: Double) -> EngineJSON {
        var o = EngineObject()
        o.set("preset", l.preset)
        o.set("keyword", l.keyword)
        o.set("sky", l.sky)
        o.set("sunAltitude", l.sunAltitude)
        o.set("sunAzimuth", l.sunAzimuth)
        o.set("sunDirection", EngineJSON.point3(sunDirection(altitude: l.sunAltitude, azimuth: l.sunAzimuth, northAngleDegrees: northAngle)))
        o.set("sunColor", EngineJSON.numbers(l.sunColor))
        o.set("sunIntensity", l.sunIntensity)
        o.set("shadowRadius", l.shadowRadius)
        o.set("shadowAlpha", l.shadowAlpha)
        o.set("envIntensity", l.envIntensity)
        o.set("ambient", l.ambient)
        o.set("exposure", l.exposure)
        o.set("whitePoint", l.whitePoint)
        o.set("bloom", l.bloom)
        o.set("bloomThreshold", l.bloomThreshold)
        o.set("saturation", l.saturation)
        o.set("contrast", l.contrast)
        o.set("ao", l.ao)
        o.set("windowGlow", l.windowGlow)
        o.set("artificial", l.artificial)
        o.set("lampGlow", l.lampGlow)
        o.set("northAngle", northAngle)
        o.set("presets", EngineJSON.strings(names))
        return o.json
    }
}

extension EngineRenderPresets {
    /// Portable RENDERPRESET (the Mac command lives in ArchiApp/BeautyRender.swift): same prompt, keywords, messages and
    /// undo step; the shell switches its 3D view to Realistic on the "setViewStyle" host notification.
    public static var command: CommandDef {
        CommandDef("RENDERPRESET", aliases: ["LIGHTINGPRESET", "BEAUTYPRESET", "PHOTOLOOK"], category: "View",
                   summary: "Photographic lighting preset of the Realistic view and renders: Daylight, Golden hour, Overcast or Night (glowing windows); Off returns to the default look.") { ed in
            let cur = look(current(ed.doc)).keyword
            guard let k = try await ed.getKeyword("Lighting preset [Daylight/Goldenhour/Overcast/Night/Off]", keywords + ["Off"], defaultValue: cur) else { return }
            if k == "Off" {
                ed.doc.variables[variable] = nil
                ed.print("Photographic preset off: the Realistic view uses the default daylight look.")
            } else {
                guard let p = named(k) else { throw CommandError.invalid("Unknown preset \(k).") }
                ed.doc.setVariable(variable, p)
                let l = look(p)
                var msg = "Lighting preset " + p + ": sun " + fmt(l.sunAltitude, 0) + "° high from " + fmt(l.sunAzimuth, 0) + "°, exposure " + fmt(l.exposure, 1) + " EV"
                if l.windowGlow > 0 { msg += ", lit windows" }
                ed.print(msg + ".")
            }
            ed.host?.perform(.setViewStyle("Realistic"), editor: ed)
        }
    }
}

extension EngineSession {
    /// Registers portable versions of commands that the Mac app defines in its UI layer (so the engine process offers
    /// them too). Only commands missing from the registry are added; the Mac app never calls this.
    public static func registerPortableAppCommands(_ registry: CommandRegistry = .shared) {
        registry.ensureBuiltins()
        for c in [EngineRenderPresets.command] where registry.lookup(c.name) == nil { registry.register(c) }
        // Settings, Quick Select, layer states and filters, workspaces, ribbon customisation, page setup, templates.
        for c in EngineUICommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        for c in EngineUICommands.overrides { registry.register(c) }
        // Help and window chrome: About, command search, clean screen, history panel, start screen, sample, what's new.
        for c in EngineHelpCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        // Self test, help browser, VR headset page and SpaceMouse (EngineSystemCommands.swift).
        for c in EngineSystemCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        // 3D view: section box / plane, cameras, gizmo, measure, levels, navigation, weather, animation, panoramas.
        for c in EngineView3DCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        // Render, materials and environment: lights, fog, water, scatter, billboards, PBR maps, 4D video, mechanisms.
        for c in EngineRenderCommands.all where registry.lookup(c.name) == nil { registry.register(c) }
        // Sheets (MVIEWPOLY, MVSETUP, SHEETIMAGE, TITLEBLOCKDESIGN, PSETUPIN, ZOOMXP …), DRAWINGRECOVERY and FILEVERSIONS.
        registerSheetCommands(registry)
        // Graphic standards, clipboard and sharing (GRAPHICSTYLES, VISUALSTYLES, PASTESPECIAL, COPYPICTURE, SHARE …).
        registerStandardsCommands(registry)
    }
}
