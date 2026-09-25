// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 3D solid editing commands: FILLETEDGE, CHAMFEREDGE, SHELL, MESHSMOOTH, MIRROR3D, ROTATE3D, 3DARRAY.
enum SolidEditCommands {
    static var all: [CommandDef] { [filletEdge(chamfer: false), filletEdge(chamfer: true), shell, meshSmooth, mirror3D, rotate3D, array3D] }

    static func edgeSet(_ k: String) -> SolidOps.EdgeSet {
        switch k { case "Vertical": return .vertical; case "Top": return .top; case "Bottom": return .bottom; case "Horizontal": return [.top, .bottom]; default: return .all }
    }

    static func filletEdge(chamfer: Bool) -> CommandDef {
        let name = chamfer ? "CHAMFEREDGE" : "FILLETEDGE"
        return CommandDef(name, aliases: chamfer ? ["CHAMFER3D", "CHE"] : ["FILLET3D", "FE"], category: "3D",
                          summary: chamfer ? "Bevels the edges of boxes and extruded solids (all, vertical, top or bottom edges)." : "Rounds the edges of boxes and extruded solids (all, vertical, top or bottom edges).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids")
            guard !ids.isEmpty else { return }
            let key = chamfer ? "CHAMFERDIST3D" : "FILLETRAD3D"
            let r = try await ed.getPositive(chamfer ? "Specify chamfer distance" : "Specify fillet radius", defaultValue: ed.variableDouble(key, 50 / ed.doc.units.mm))
            ed.doc.setVariable(key, fmt(r))
            let k = try await ed.getKeyword("Edges to \(chamfer ? "chamfer" : "round")", ["All", "Vertical", "Top", "Bottom", "Horizontal"], defaultValue: "All") ?? "All"
            var done = 0
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                do {
                    let res = try SolidOps.filletEdges(s, radius: r, edges: edgeSet(k), chamfer: chamfer)
                    ModelingCommands.replace(ed, id, with: res); done += 1
                } catch let e as SolidOps.OpError { ed.print("#\(id): \(e.description)") }
            }
            if done > 0 { ed.print("\(done) solid(s) \(chamfer ? "chamfered" : "filleted").") }
        }
    }

    static var shell: CommandDef {
        CommandDef("SHELL", aliases: ["SOLIDSHELL", "HOLLOW"], category: "3D", summary: "Hollows boxes and extrusions to a wall thickness, optionally removing the top face (SOLIDEDIT Shell).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to shell")
            guard !ids.isEmpty else { return }
            let t = try await ed.getPositive("Enter the shell offset distance", defaultValue: ed.variableDouble("SHELLTHICK", 20 / ed.doc.units.mm))
            ed.doc.setVariable("SHELLTHICK", fmt(t))
            let open = try await ed.getYesNo("Remove the top face?", defaultValue: true)
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                do {
                    let r = try SolidOps.shell(s, thickness: t, openTop: open)
                    ModelingCommands.replace(ed, id, with: r)
                    ed.print("#\(id) shelled: volume " + ModelingCommands.volumeText(SolidOps.volume(vertices: r.meshVertices, triangles: r.meshTriangles), units: ed.doc.units) + ".")
                } catch let e as SolidOps.OpError { ed.print("#\(id): \(e.description)") }
            }
        }
    }

    static var meshSmooth: CommandDef {
        CommandDef("MESHSMOOTH", aliases: ["SMOOTHMESH", "SUBDIVIDE", "MESHREFINE"], category: "3D", summary: "Smooths solids and meshes by Loop subdivision (1–4 levels).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids or meshes to smooth")
            guard !ids.isEmpty else { return }
            let lv = try await ed.getInteger("Enter smoothness level (1-4)", defaultValue: Int(ed.variableDouble("SMOOTHMESHLEVEL", 2))) ?? 2
            guard lv >= 1, lv <= 4 else { throw CommandError.invalid("Enter a level from 1 to 4.") }
            ed.doc.setVariable("SMOOTHMESHLEVEL", "\(lv)")
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                do {
                    let r = try SolidOps.smooth(s, levels: lv)
                    ModelingCommands.replace(ed, id, with: r)
                    ed.print("#\(id): \(r.meshTriangles.count / 3) triangles.")
                } catch let e as SolidOps.OpError { ed.print("#\(id): \(e.description)") }
            }
        }
    }

    @MainActor static func copyOrReplace(_ ed: Editor, _ id: EntityID, _ s: SolidGeom, keep: Bool) {
        if keep, var e = ed.doc.entity(id) { e.geometry = .solid(s); ed.doc.add(e) }
        else { ModelingCommands.replace(ed, id, with: s) }
    }

    static var mirror3D: CommandDef {
        CommandDef("MIRROR3D", aliases: ["3DMIRROR"], category: "3D", summary: "Mirrors solids about the XY, YZ or ZX plane through a point, or a vertical plane through two points.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to mirror")
            guard !ids.isEmpty else { return }
            let k = try await ed.getKeyword("Specify mirror plane", ["Line", "XY", "YZ", "ZX"], defaultValue: "Line") ?? "Line"
            var f: (Vec3) -> Vec3
            switch k {
            case "XY":
                let z = try await ed.getDistance("Specify the height of the mirror plane", defaultValue: 0).value ?? 0
                f = { SolidOps.reflect($0, plane: .xy, origin: Vec3(0, 0, z)) }
            case "YZ", "ZX":
                let p = try await ed.requirePoint("Specify a point on the \(k) plane")
                let pl: SolidOps.Plane = k == "YZ" ? .yz : .zx
                f = { SolidOps.reflect($0, plane: pl, origin: Vec3(p.x, p.y, 0)) }
            default:
                let a = try await ed.requirePoint("Specify first point of the mirror plane (vertical)")
                let b = try await ed.requirePoint("Specify second point", base: a) { c in [.line(LineGeom(a, c))] }
                guard a.distance(to: b) > 1e-9 else { throw CommandError.invalid("The points must differ.") }
                f = { SolidOps.reflect($0, lineA: a, lineB: b) }
            }
            let erase = try await ed.getYesNo("Delete source objects?", defaultValue: false)
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                copyOrReplace(ed, id, SolidOps.mapped(s, mirroring: true, f), keep: !erase)
            }
            ed.print("\(ids.count) solid(s) mirrored.")
        }
    }

    static var rotate3D: CommandDef {
        CommandDef("ROTATE3D", aliases: ["3DROTATE"], category: "3D", summary: "Rotates solids about an axis parallel to X, Y or Z through a point.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to rotate")
            guard !ids.isEmpty else { return }
            let axis = try await ed.getKeyword("Specify rotation axis", ["X", "Y", "Z"], defaultValue: "Z") ?? "Z"
            let p = try await ed.requirePoint("Specify a point on the axis")
            var z = 0.0
            if axis != "Z" { z = try await ed.getDistance("Specify the height of the axis", defaultValue: 0).value ?? 0 }
            guard let ang = try await ed.getAngle("Specify rotation angle", defaultValue: rad(90)).value else { return }
            for id in ids {
                guard let e = ed.doc.entity(id), let s = ModelingCommands.solidOf(ed.doc, id), let i = ed.doc.entityIndex(id) else { continue }
                if axis == "Z" { ed.doc.entities[i].geometry = GeometryOps.transform(e.geometry, Transform2D.rotation(ang, around: p)) }
                else { ModelingCommands.replace(ed, id, with: SolidOps.mapped(s, mirroring: false) { SolidOps.rotate($0, axis: Character(axis), angle: ang, origin: Vec3(p.x, p.y, z)) }) }
            }
            ed.print("\(ids.count) solid(s) rotated \(fmt(deg(ang)))° about \(axis).")
        }
    }

    /// Copy of an entity moved in plan by `t` and raised by `dz` (solids move in Z; other objects change their elevation).
    static func arrayed(_ e: Entity, _ t: Transform2D, dz: Double) -> Entity {
        var c = e
        c.geometry = GeometryOps.transform(e.geometry, t)
        if abs(dz) > 1e-12 {
            if case .solid(let s) = c.geometry { c.geometry = .solid(SolidOps.translated(s, by: Vec3(0, 0, dz))) }
            else { c.props["elevation"] = fmt((e.props["elevation"].flatMap(Double.init) ?? 0) + dz) }
        }
        return c
    }

    static var array3D: CommandDef {
        CommandDef("3DARRAY", aliases: ["ARRAY3D", "3A"], category: "3D", summary: "Creates rectangular (rows × columns × levels) or polar 3D arrays of objects.") { ed in
            let ids = try await ed.getSelection("Select objects")
            let src = ids.compactMap { ed.doc.entity($0) }
            guard !src.isEmpty else { throw CommandError.invalid("Select drawing objects or solids.") }
            let k = try await ed.getKeyword("Enter the type of array", ["Rectangular", "Polar"], defaultValue: "Rectangular") ?? "Rectangular"
            var made = 0
            if k == "Rectangular" {
                let rows = try await ed.getInteger("Enter the number of rows (---)", defaultValue: 1) ?? 1
                let cols = try await ed.getInteger("Enter the number of columns (|||)", defaultValue: 1) ?? 1
                let lvls = try await ed.getInteger("Enter the number of levels (...)", defaultValue: 1) ?? 1
                guard rows >= 1, cols >= 1, lvls >= 1, rows * cols * lvls <= 100_000 else { throw CommandError.invalid("Counts must be at least 1 (100 000 copies at most).") }
                guard rows * cols * lvls > 1 else { throw CommandError.invalid("Nothing to array.") }
                let dy = rows > 1 ? (try await ed.getDistance("Specify the distance between rows (---)").value ?? 0) : 0
                let dx = cols > 1 ? (try await ed.getDistance("Specify the distance between columns (|||)").value ?? 0) : 0
                let dz = lvls > 1 ? (try await ed.getDistance("Specify the distance between levels (...)").value ?? 0) : 0
                for l in 0..<lvls { for r in 0..<rows { for c in 0..<cols where !(l == 0 && r == 0 && c == 0) {
                    let t = Transform2D.translation(Vec2(Double(c) * dx, Double(r) * dy))
                    for e in src { ed.doc.add(arrayed(e, t, dz: Double(l) * dz)); made += 1 }
                } } }
            } else {
                guard let n = try await ed.getInteger("Enter the number of items in the array", defaultValue: 6), n >= 2, n <= 10_000 else { throw CommandError.invalid("Enter 2 to 10 000 items.") }
                let fill = try await ed.getReal("Specify the angle to fill (+=ccw, -=cw)", defaultValue: 360).value ?? 360
                let rotateItems = try await ed.getYesNo("Rotate arrayed objects?", defaultValue: true)
                let c = try await ed.requirePoint("Specify the center point of the array (axis parallel to Z)")
                let dz = try await ed.getDistance("Specify the rise between items (helical array, 0 = none)", defaultValue: 0).value ?? 0
                let full = abs(abs(fill) - 360) < 1e-9
                let step = rad(fill) / Double(full ? n : n - 1)
                for i in 1..<n {
                    let a = step * Double(i)
                    for e in src {
                        var t = Transform2D.rotation(a, around: c)
                        if !rotateItems {
                            let b = GeometryOps.bounds(e.geometry, doc: ed.doc)
                            let ctr = b.isEmpty ? c : (b.min + b.max) / 2
                            t = Transform2D.translation(ctr.rotated(by: a, around: c) - ctr)
                        }
                        ed.doc.add(arrayed(e, t, dz: dz * Double(i))); made += 1
                    }
                }
            }
            ed.print("\(made) object(s) created.")
        }
    }
}
