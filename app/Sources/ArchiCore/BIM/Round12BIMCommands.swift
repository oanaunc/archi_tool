// Oanarina Archi Tool — GPL-3.0-or-later
// Round 12 commands: object styles (LAY-033), non-uniform scale handles (M3D-106) and baked ambient occlusion (VIS-033).
import Foundation

enum Round12Commands {
    static var all: [CommandDef] { [objectStyles, ambientOcclusion] + Round12ModelingCommands.all }

    static var objectStyles: CommandDef {
        CommandDef("OBJECTSTYLES", aliases: ["OBJSTYLES", "OBJECTSTYLE", "CATEGORYSTYLES"], category: "Manage", summary: "Object styles: project-wide projection/cut line weights, line colour, cut fill and cut pattern per BIM category (wall, door, window, slab, column…); every plan and section follows. List, Reset, or set e.g. \"cut:0.7;proj:0.35;color:red;fill:0.3,0.3,0.3;pattern:ANSI31\".") { ed in
            var all = ObjectStyles.all(ed.doc)
            guard let c = try await ed.getWord("Category (" + ObjectStyles.categories.joined(separator: ", ") + "; List; Reset)", defaultValue: "List") else { return }
            switch c.lowercased() {
            case "list":
                if all.isEmpty { ed.print("No object styles: categories use the default line weights (cut 0.5, projection 0.25).") }
                for (k, s) in all.sorted(by: { $0.key < $1.key }) { ed.print("\(k): \(ObjectStyles.describe(s))") }
                return
            case "reset":
                ObjectStyles.setAll([:], doc: &ed.doc)
                ed.print("Object styles reset to defaults.")
                return
            default: break
            }
            let key = VisibilityGraphics.norm(c)
            guard ObjectStyles.categories.contains(key) else { throw CommandError.invalid("Unknown category \(c). Use " + ObjectStyles.categories.joined(separator: ", ") + ".") }
            let cur = all[key].map(ObjectStyles.describe) ?? "(defaults)"
            guard let spec = try await ed.getWord("Style for \(key) now \(cur) (cut:0.7; proj:0.35; color:red or r,g,b; fill:r,g,b; pattern:ANSI31 — joined by ';'; Reset)") else { return }
            if spec.lowercased() == "reset" { all[key] = nil }
            else {
                guard let s = ObjectStyles.parse(spec) else { throw CommandError.invalid("Use cut:<mm>, proj:<mm>, color:<name or r,g,b>, fill:<r,g,b>, pattern:<name>, joined by ';'.") }
                all[key] = (all[key] ?? ObjectStyle()).merged(s)
            }
            ObjectStyles.setAll(all, doc: &ed.doc)
            ed.print("\(key): \(all[key].map(ObjectStyles.describe) ?? "(defaults)").")
        }
    }

    static var ambientOcclusion: CommandDef {
        CommandDef("AMBIENTOCCLUSION", aliases: ["AOCCLUSION", "AOBAKE", "AOSETTINGS"], category: "View", summary: "Ambient occlusion baked on the model: Intensity (0 = off … 2), Radius and Samples; shaded elevations, sections, axonometrics and perspectives (and their PDF/SVG exports) darken corners and overhangs; Report prints the average occlusion.") { ed in
            let k = try await ed.getKeyword("Ambient occlusion [Intensity/Radius/Samples/Off/Report]", ["Intensity", "Radius", "Samples", "Off", "Report"], defaultValue: "Intensity") ?? "Intensity"
            let cur = AmbientOcclusion.settings(ed.doc) ?? AmbientOcclusion.Settings(radius: 1000 / ed.doc.units.mm)
            switch k {
            case "Off": ed.doc.variables["AOINTENSITY"] = nil; ed.print("Ambient occlusion off.")
            case "Radius":
                let r = try await ed.getPositive("Occlusion radius", defaultValue: cur.radius)
                ed.doc.setVariable("AORADIUS", fmt(r, 6))
                if AmbientOcclusion.settings(ed.doc) == nil { ed.doc.setVariable("AOINTENSITY", "1") }
                ed.print("Occlusion radius \(fmt(r)).")
            case "Samples":
                guard let n = try await ed.getInteger("Rays per point (4–256)", defaultValue: cur.samples), n >= 4, n <= 256 else { throw CommandError.invalid("Use 4 to 256 rays.") }
                ed.doc.setVariable("AOSAMPLES", "\(n)")
                ed.print("\(n) rays per point.")
            case "Report":
                let s = AmbientOcclusion.settings(ed.doc) ?? cur
                let groups = MeshBuilder.build(doc: ed.doc)
                let ao = AmbientOcclusion.bake(groups, settings: s)
                let all = ao.flatMap { $0 }
                guard !all.isEmpty else { ed.print("Nothing to shade."); return }
                ed.print("Ambient occlusion over \(all.count) vertices: mean \(fmt(all.reduce(0, +) / Double(all.count), 3)), max \(fmt(all.max() ?? 0, 3)).")
            default:
                guard let v = try await ed.getReal("Intensity (0 = off, up to 2)", defaultValue: max(cur.intensity, 1)).value, v >= 0, v <= 2 else { throw CommandError.invalid("Use 0 to 2.") }
                if v < 1e-9 { ed.doc.variables["AOINTENSITY"] = nil } else { ed.doc.setVariable("AOINTENSITY", fmt(v, 4)) }
                ed.print(v < 1e-9 ? "Ambient occlusion off." : "Ambient occlusion intensity \(fmt(v)).")
            }
        }
    }
}
