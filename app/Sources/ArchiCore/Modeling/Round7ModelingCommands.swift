// Oanarina Archi Tool — GPL-3.0-or-later
// 3D modelling commands of round 7: 3DALIGN, MESHEXTRUDE, WIREFRAME, UNFOLD, MESHSECTION, MINKOWSKI, SPRING, TEXT3D,
// SURFCV, SCAD and SCADFILE.
import Foundation

enum Round7ModelingCommands {
    static var all: [CommandDef] { [align3D, meshExtrude, wireframe, unfold, meshSection, minkowski, spring, text3D, surfCV, scad, scadFile] }

    @MainActor static func point3(_ ed: Editor, _ msg: String, base: Vec2? = nil, z: Double) async throws -> Vec3? {
        guard let p = try await ed.getPoint(msg, base: base).point else { return nil }
        let h = try await ed.getReal("  Z of that point", defaultValue: z).value ?? z
        return Vec3(p.x, p.y, h)
    }

    static var align3D: CommandDef {
        CommandDef("3DALIGN", aliases: ["ALIGN3D", "3DAL"], category: "3D",
                   summary: "Aligns solids in 3D by up to three source and destination points (translation, then direction, then plane); optional scaling.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to align")
            guard !ids.isEmpty else { return }
            var zb = BBox3.empty
            for id in ids { if let s = ModelingCommands.solidOf(ed.doc, id) { let b = ModelingCommands.bounds(s); if !b.isEmpty { zb.add(b.min); zb.add(b.max) } } }
            let z0 = zb.isEmpty ? 0 : zb.min.z
            var src: [Vec3] = [], dst: [Vec3] = []
            for k in 0..<3 {
                guard let p = try await point3(ed, k == 0 ? "Specify first source point" : "Specify next source point (Enter = done)", base: src.last?.xy, z: z0) else { break }
                src.append(p)
            }
            guard !src.isEmpty else { return }
            for k in 0..<src.count {
                guard let p = try await point3(ed, "Specify destination point \(k + 1)", base: dst.last?.xy, z: PrimitiveCommands.z(ed)) else { throw CommandError.invalid("Each source point needs a destination.") }
                dst.append(p)
            }
            let scale = src.count >= 2 ? try await ed.getYesNo("Scale objects to the alignment points?", defaultValue: false) : false
            guard let f = MeshOps.alignment(source: src, dest: dst, scale: scale) else { throw CommandError.invalid("Alignment points are degenerate.") }
            for id in ids { if let s = ModelingCommands.solidOf(ed.doc, id) { ModelingCommands.replace(ed, id, with: SolidOps.mapped(s, mirroring: false, f)) } }
            ed.print("\(ids.count) solid(s) aligned.")
        }
    }

    static let directions: [String: Vec3] = ["Top": Vec3(0, 0, 1), "Bottom": Vec3(0, 0, -1), "Front": Vec3(0, -1, 0), "Back": Vec3(0, 1, 0), "Left": Vec3(-1, 0, 0), "Right": Vec3(1, 0, 0)]

    static var meshExtrude: CommandDef {
        CommandDef("MESHEXTRUDE", aliases: ["EXTRUDEFACE", "FACEEXTRUDE", "MESHFACEEXTRUDE"], category: "3D",
                   summary: "Extrudes faces of a solid or mesh (the faces facing Top/Bottom/Front/Back/Left/Right under a picked point, or All facing that way) by a distance along their normal; the result stays closed.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select a solid or mesh")
            guard let id = ids.first, let s = ModelingCommands.solidOf(ed.doc, id) else { return }
            let d = try await ed.getKeyword("Faces facing", ["Top", "Bottom", "Front", "Back", "Left", "Right"], defaultValue: "Top") ?? "Top"
            let at = try await ed.getPoint("Pick a point on the face in plan (Enter = all faces facing that way)").point
            let sel = MeshOps.faces(s, facing: directions[d]!, at: at)
            guard !sel.isEmpty else { throw CommandError.invalid("No face found.") }
            let dist = try await ed.getDistance("Extrusion distance (negative pushes in)", defaultValue: 500 / ed.doc.units.mm).value ?? 0
            guard let r = MeshOps.extrudeFaces(s, faces: sel, distance: dist) else { throw CommandError.invalid("Nothing to extrude.") }
            ModelingCommands.replace(ed, id, with: r)
            ed.print("\(sel.count) triangle(s) extruded; volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    static var wireframe: CommandDef {
        CommandDef("WIREFRAME", aliases: ["MESHWIREFRAME", "WIREFRAMEMOD", "LATTICE"], category: "3D",
                   summary: "Wireframe modifier: turns the edges of a solid or mesh into struts of a given thickness (Solidify: THICKEN).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids or meshes")
            guard !ids.isEmpty else { return }
            let w = try await ed.getPositive("Strut thickness", defaultValue: 20 / ed.doc.units.mm)
            let keep = try await ed.getYesNo("Keep the originals?", defaultValue: false)
            var n = 0
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id), let r = MeshOps.wireframe(s, thickness: w) else { continue }
                if keep { ed.addEntity(.solid(r)) } else { ModelingCommands.replace(ed, id, with: r) }
                n += 1
            }
            ed.print("\(n) wireframe(s) created.")
        }
    }

    static var unfold: CommandDef {
        CommandDef("UNFOLD", aliases: ["MESHUNFOLD", "FLATTENMESH", "PAPERMODEL"], category: "3D",
                   summary: "Unfolds a solid or mesh into a flat net for fabrication (cut lines solid, fold lines dashed), placed at a point.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select a solid or mesh")
            guard let id = ids.first, let s = ModelingCommands.solidOf(ed.doc, id) else { return }
            guard let net = MeshOps.unfold(s, gap: 100 / ed.doc.units.mm) else { throw CommandError.invalid("Nothing to unfold.") }
            let b = BBox2(points: net.cuts.flatMap { $0 })
            let p = try await ed.requirePoint("Specify lower-left corner of the net")
            let d = p - b.min
            ed.doc.ensureLayer("A-UNFOLD")
            for c in net.cuts { ed.doc.add(Entity(layer: "A-UNFOLD", geometry: .line(LineGeom(c[0] + d, c[1] + d)), props: ["unfold": "cut"])) }
            for f in net.folds { ed.doc.add(Entity(layer: "A-UNFOLD", linetype: "Dashed", geometry: .line(LineGeom(f[0] + d, f[1] + d)), props: ["unfold": "fold"])) }
            let area = net.faces.reduce(0) { $0 + abs(GeometryOps.signedArea($1)) }
            ed.print("Net: \(net.faces.count) triangles, \(net.cuts.count) cut and \(net.folds.count) fold lines, area \(fmt(area)).")
        }
    }

    static var meshSection: CommandDef {
        CommandDef("MESHSECTION", aliases: ["CROSSSECTIONS", "SLICESECTIONS", "SECTIONCURVES"], category: "3D",
                   summary: "Cross-sections of solids and meshes: section curves at one elevation or every interval between two elevations (for contours, ribs, waffle models).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids or meshes")
            guard !ids.isEmpty else { return }
            var b = BBox3.empty
            for id in ids { if let s = ModelingCommands.solidOf(ed.doc, id) { let x = ModelingCommands.bounds(s); if !x.isEmpty { b.add(x.min); b.add(x.max) } } }
            guard !b.isEmpty else { return }
            let z0 = try await ed.getReal("First elevation", defaultValue: (b.min.z + b.max.z) / 2).value ?? b.min.z
            let z1 = try await ed.getReal("Last elevation (= first for one section)", defaultValue: z0).value ?? z0
            let step = abs(z1 - z0) > 1e-9 ? try await ed.getPositive("Interval", defaultValue: abs(z1 - z0) / 10) : 1
            ed.doc.ensureLayer("A-SECTION")
            var n = 0, z = min(z0, z1)
            while z <= max(z0, z1) + 1e-9 && n < 10_000 {
                for id in ids {
                    guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                    for l in MeshOps.section(s, z: z) where l.count >= 2 {
                        let closed = l.count > 3 && l[0].isClose(l[l.count - 1], tol: 1e-6)
                        ed.doc.add(Entity(layer: "A-SECTION", geometry: .polyline(PolylineGeom(points: closed ? Array(l.dropLast()) : l, closed: closed)), props: ["elevation": fmt(z, 6), "sectionOf": "\(id)"]))
                        n += 1
                    }
                }
                z += step
                if abs(z1 - z0) < 1e-9 { break }
            }
            ed.print("\(n) section curve(s).")
        }
    }

    static var minkowski: CommandDef {
        CommandDef("MINKOWSKI", aliases: ["MINKOWSKISUM"], category: "3D",
                   summary: "Minkowski sum of two solids (e.g. a box and a sphere for rounded edges); exact for convex solids.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select two solids")
            guard ids.count >= 2, let a = ModelingCommands.solidOf(ed.doc, ids[0]), let b = ModelingCommands.solidOf(ed.doc, ids[1]) else { throw CommandError.invalid("Select two solids.") }
            // The second solid acts as the brush: centred on its bounding-box centre.
            let bc = ModelingCommands.bounds(b).center
            guard let r = MeshOps.minkowski(a, SolidOps.translated(b, by: -bc)) else { throw CommandError.invalid("Solids are too detailed for a Minkowski sum.") }
            ModelingCommands.replace(ed, ids[0], with: r)
            ed.doc.remove(ids: [ids[1]])
            ed.print("Minkowski sum: volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    static var spring: CommandDef {
        CommandDef("SPRING", aliases: ["COILSPRING", "HELIXSOLID"], category: "3D",
                   summary: "Creates a helical coil spring solid (coil radius, wire radius, pitch, turns).") { ed in
            let c = try await ed.requirePoint("Specify centre of the spring base")
            let R = try await ed.getPositive("Coil radius", base: c, defaultValue: 50 / ed.doc.units.mm)
            let r = try await ed.getPositive("Wire radius", defaultValue: R / 8)
            let p = try await ed.getPositive("Pitch (rise per turn)", defaultValue: max(4 * r, 2.1 * r))
            let n = try await ed.getReal("Turns", defaultValue: 5).value ?? 5
            guard p > 2 * r else { throw CommandError.invalid("The pitch must exceed the wire diameter.") }
            try PrimitiveCommands.add(ed, MeshOps.spring(center: Vec3(c.x, c.y, PrimitiveCommands.z(ed) + r), coilRadius: R, wireRadius: r, pitch: p, turns: n), "Spring")
        }
    }

    static var text3D: CommandDef {
        CommandDef("TEXT3D", aliases: ["3DTEXT", "EXTRUDETEXT"], category: "3D",
                   summary: "Creates extruded 3D text (single-line font strokes as solid bars).") { ed in
            guard let s = try await ed.getString("Text"), !s.isEmpty else { return }
            let p = try await ed.requirePoint("Specify start point")
            let h = try await ed.getPositive("Height", base: p, defaultValue: 300 / ed.doc.units.mm)
            let d = try await ed.getPositive("Extrusion depth", defaultValue: h / 5)
            let r = try await ed.getAngle("Rotation", base: p, defaultValue: 0).value ?? 0
            try PrimitiveCommands.add(ed, MeshOps.text3D(TextGeom(position: p, height: h, content: s, rotation: r), z: PrimitiveCommands.z(ed), depth: d, stroke: h * 0.14), "3D text")
        }
    }

    static var surfCV: CommandDef {
        CommandDef("SURFCV", aliases: ["NURBSSURF", "CVSURFACE", "SURFCVEDIT"], category: "3D",
                   summary: "B-spline (NURBS) surface from a grid of control vertices: New over a rectangle, Edit moves a CV (row, column, height), Display the CV grid.") { ed in
            let k = try await ed.getKeyword("Option", ["New", "Edit"], defaultValue: "New") ?? "New"
            if k == "Edit" {
                guard let id = (try await ed.getSelection("Select a CV surface")).first(where: { ed.doc.entity($0)?.props["cvGrid"] != nil }),
                      let i = ed.doc.entityIndex(id), var cv = MeshOps.decode(ed.doc.entities[i].props["cvGrid"]!) else { throw CommandError.invalid("Not a CV surface.") }
                while true {
                    guard let rs = try await ed.getInteger("Row (1–\(cv.count), Enter = done)") else { break }
                    guard let cs = try await ed.getInteger("Column (1–\(cv[0].count))"), rs >= 1, rs <= cv.count, cs >= 1, cs <= cv[0].count else { ed.print("Out of range."); continue }
                    let z = try await ed.getReal("Height of the CV", defaultValue: cv[rs - 1][cs - 1].z).value ?? cv[rs - 1][cs - 1].z
                    let move = try await ed.getPoint("New plan position (Enter = keep)").point
                    cv[rs - 1][cs - 1] = Vec3(move?.x ?? cv[rs - 1][cs - 1].x, move?.y ?? cv[rs - 1][cs - 1].y, z)
                }
                ed.doc.entities[i].props["cvGrid"] = MeshOps.encode(cv)
                MeshOps.updateSurfaces(&ed.doc)
                return
            }
            let a = try await ed.requirePoint("Specify first corner")
            let b = try await ed.requirePoint("Specify opposite corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
            let rows = try await ed.getInteger("CV rows", defaultValue: 4) ?? 4
            let cols = try await ed.getInteger("CV columns", defaultValue: 4) ?? 4
            guard rows >= 2, cols >= 2, rows <= 50, cols <= 50, BBox2(points: [a, b]).width > 1e-9, BBox2(points: [a, b]).height > 1e-9 else { throw CommandError.invalid("Use 2–50 CVs on a non-empty rectangle.") }
            let cv = MeshOps.grid(from: a, to: b, rows: rows, cols: cols, z: PrimitiveCommands.z(ed))
            guard let m = MeshOps.surface(cv) else { return }
            var bb = BBox3.empty; m.vertices.forEach { bb.add($0) }
            let id = ed.addEntity(.solid(SolidGeom(kind: .mesh, origin: bb.min, meshVertices: m.vertices, meshTriangles: m.triangles)))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["cvGrid"] = MeshOps.encode(cv); ed.doc.entities[i].props["cvDivisions"] = "16" }
            ed.print("CV surface \(rows)×\(cols) created (SURFCV Edit moves control vertices).")
        }
    }

    @MainActor static func addSCAD(_ ed: Editor, _ r: SCAD.Result, name: String) throws {
        for e in r.echo { ed.print("ECHO: \(e)") }
        for e in r.errors { ed.print("SCAD: \(e)") }
        let z = PrimitiveCommands.z(ed)
        var made = 0
        if !r.triangles.isEmpty, let s = SolidPrimitives.solid(r.triangles.map { ($0.0 + Vec3(0, 0, z), $0.1 + Vec3(0, 0, z), $0.2 + Vec3(0, 0, z)) }) {
            let id = ed.addEntity(.solid(s))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["scad"] = name }
            ed.print("\(name): solid, volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
            made += 1
        }
        for l in r.loops where l.count >= 3 { ed.addEntity(.polyline(PolylineGeom(points: l, closed: true))); made += 1 }
        if made == 0 && r.errors.isEmpty { ed.print("The script produced no geometry.") }
        if made == 0 && !r.errors.isEmpty { throw CommandError.invalid("Script failed.") }
    }

    static var scad: CommandDef {
        CommandDef("SCAD", aliases: ["OPENSCAD", "CSGSCRIPT"], category: "3D",
                   summary: "Evaluates an OpenSCAD-language script (cube, sphere, cylinder, polyhedron, extrudes, transforms, union/difference/intersection/hull/minkowski, modules, loops) into a solid.") { ed in
            guard let src = try await ed.getString("OpenSCAD script"), !src.isEmpty else { return }
            try addSCAD(ed, SCAD.evaluate(src), name: "script")
        }
    }

    static var scadFile: CommandDef {
        CommandDef("SCADFILE", aliases: ["SCADIN", "IMPORTSCAD"], category: "3D",
                   summary: "Imports an OpenSCAD .scad file (with include / use of neighbouring files) as a solid.") { ed in
            guard let path = try await ed.getString("File (.scad)") else { return }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let src = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
            let dir = url.deletingLastPathComponent()
            let r = SCAD.evaluate(src) { rel in try? String(contentsOf: PathSupport.isAbsolute(rel) ? URL(fileURLWithPath: rel) : dir.appendingPathComponent(rel), encoding: .utf8) }
            try addSCAD(ed, r, name: url.lastPathComponent)
        }
    }
}
