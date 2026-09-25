// Oanarina Archi Tool — GPL-3.0-or-later
// STRUCTLOAD (point / line / area loads) and STRUCTSUPPORT (boundary conditions) for the analytical model (ANL-032).
import Foundation

public enum StructuralLoadCommands {
    public static var all: [CommandDef] { [structLoad, structSupport] }

    @MainActor static func style(_ ed: Editor) {
        if ed.doc.layer(named: StructuralLoads.layer) == nil {
            ed.doc.layers.append(Layer(name: StructuralLoads.layer, color: RGBA(0.95, 0.35, 0.2)))
        }
    }

    static var structLoad: CommandDef {
        CommandDef("STRUCTLOAD", aliases: ["LOADADD", "STRUCTURALLOAD"], category: "Structure",
                   summary: "Adds a structural load on layer S-LOADS for the analytical model: Point (kN at a node or on a beam), Line (kN/m along beams) or Area (kN/m² over an outline); vertical downward by default, optional horizontal components and load case.") { ed in
            let k = try await ed.getKeyword("Load type [Point/Line/Area]", ["Point", "Line", "Area"], defaultValue: "Point") ?? "Point"
            let unit = k == "Point" ? "kN" : k == "Line" ? "kN/m" : "kN/m²"
            let geom: Geometry
            switch k {
            case "Point":
                geom = .point(try await ed.requirePoint("Specify load point"))
            case "Line":
                let a = try await ed.requirePoint("Specify start of line load")
                let b = try await ed.requirePoint("Specify end of line load", base: a, preview: { [.line(LineGeom(a, $0))] })
                geom = .line(LineGeom(a, b))
            default:
                var pts: [Vec2] = [try await ed.requirePoint("Specify first corner of the loaded area")]
                while true {
                    let last = pts.last!
                    let r = try await ed.getPoint("Specify next corner or [Close]", base: last, keywords: ["Close"],
                                                  preview: { p in [.polyline(PolylineGeom(points: pts + [p], closed: true))] })
                    if case .point(let p) = r { pts.append(p) } else { break }
                }
                guard pts.count >= 3 else { throw CommandError.invalid("An area load needs at least three corners.") }
                geom = .polyline(PolylineGeom(points: pts, closed: true))
            }
            let v = try await ed.getReal("Vertical load \(unit), downward positive", defaultValue: k == "Area" ? 2 : 10).value ?? 0
            let hx = try await ed.getReal("Horizontal X component \(unit) <0>", defaultValue: 0).value ?? 0
            let hy = try await ed.getReal("Horizontal Y component \(unit) <0>", defaultValue: 0).value ?? 0
            let lc = try await ed.getWord("Load case <Q>", defaultValue: "Q") ?? "Q"
            guard v != 0 || hx != 0 || hy != 0 else { throw CommandError.invalid("The load is zero.") }
            style(ed)
            var e = Entity(layer: StructuralLoads.layer, geometry: geom)
            e.props = ["structLoad": k.lowercased(), "fx": fmt(hx, 6), "fy": fmt(hy, 6), "fz": fmt(-v, 6), "loadCase": lc, "level": "\(ed.doc.currentLevel)"]
            let id = ed.doc.add(e)
            ed.print("\(k) load #\(id): \(fmt(v, 3)) \(unit) down" + (hx != 0 || hy != 0 ? ", horizontal (\(fmt(hx, 3)), \(fmt(hy, 3)))" : "") + ", case \(lc).")
        }
    }

    static var structSupport: CommandDef {
        CommandDef("STRUCTSUPPORT", aliases: ["SUPPORTADD", "BOUNDARYCONDITION"], category: "Structure",
                   summary: "Adds a support (boundary condition) for the analytical model at a node: Fixed, Pinned, Roller or a custom ux uy uz rx ry rz code (e.g. 111000).") { ed in
            let p = try await ed.requirePoint("Specify support location (a column base or member end)")
            let k = try await ed.getWord("Support type [Fixed/Pinned/Roller/Custom]", defaultValue: "Fixed", keywords: ["Fixed", "Pinned", "Roller", "Custom"]) ?? "Fixed"
            var code = k
            if k == "Custom" { code = try await ed.getWord("Fixed DOFs ux uy uz rx ry rz as six 0/1 digits <111000>", defaultValue: "111000") ?? "111000" }
            guard StructuralLoads.supportFlags(code) != nil else { throw CommandError.invalid("Unknown support \(code): use Fixed, Pinned, Roller or six 0/1 digits.") }
            style(ed)
            var e = Entity(layer: StructuralLoads.layer, geometry: .point(p))
            e.props = ["structSupport": code.lowercased(), "level": "\(ed.doc.currentLevel)"]
            let id = ed.doc.add(e)
            ed.print("Support #\(id): \(code).")
        }
    }
}
