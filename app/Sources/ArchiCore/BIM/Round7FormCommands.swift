// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for round 7 element forms: ROOFEXTRUSION (BIM-057), ROOFSHAPEPOINTS (BIM-063), STAIRSKETCH (BIM-066),
// SLABEDGE (BIM-051) and TYPEIMAGE (DOC-048).
import Foundation

enum Round7FormCommands {
    static var all: [CommandDef] { [roofExtrusion, roofShapePoints, stairSketch, slabEdge, typeImage] }

    static var roofExtrusion: CommandDef {
        CommandDef("ROOFEXTRUSION", aliases: ["ROOFBYEXTRUSION", "EXTRUDEDROOF", "ROOFEXTRUDE"], category: "Architecture",
                   summary: "Roof by extrusion: pick an open polyline drawn as the roof profile (x = across, y = height), then the start, direction and length of the extrusion and the eave height.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select the profile (open polyline or line)", filter: { ed.doc.entity($0) != nil }),
                  let e = ed.doc.entity(pk.id), let pl = GeometryOps.tessellate(e.geometry, doc: ed.doc).first, pl.count >= 2 else { throw CommandError.invalid("Not a profile.") }
            let p0 = pl.min { $0.x < $1.x }!
            let prof = pl.map { Vec2($0.x - p0.x, $0.y - p0.y) }.sorted { $0.x < $1.x }
            for i in 1..<prof.count where prof[i].x - prof[i - 1].x < 1e-9 { throw CommandError.invalid("The profile must advance across its width (no vertical segments).") }
            let o = try await ed.requirePoint("Specify start of the extrusion (profile origin)")
            let dp = try await ed.requirePoint("Specify direction of the profile width", base: o) { c in [.line(LineGeom(o, c))] }
            guard dp.distance(to: o) > 1e-9 else { return }
            let ang = (dp - o).angle
            let depth = try await ed.getPositive("Extrusion length (to the left of the direction)", base: o, defaultValue: 10000 / ed.doc.units.mm)
            let eave = try await ed.getDistance("Eave height above the level", defaultValue: ed.currentLevelHeight).value ?? ed.currentLevelHeight
            let th = try await ed.getPositive("Roof thickness", defaultValue: 250 / ed.doc.units.mm)
            let ex = RoofExtrusion(origin: o, direction: ang, profile: prof, depth: depth)
            var g = RoofGeom(boundary: ex.footprint, kind: .gable, pitch: 0, thickness: th, overhang: 0, baseOffset: eave, eaveEdge: 0)
            let maxSlope = zip(prof, prof.dropFirst()).map { abs(atan(($1.y - $0.y) / ($1.x - $0.x))) * 180 / .pi }.max() ?? 0
            g.pitch = maxSlope
            g.extrusion = ex
            let id = ed.doc.addElement(.roof(g), name: "Extruded roof")
            if ed.variableDouble("DELOBJ", 1) != 0, (try await ed.getYesNo("Delete the profile?", defaultValue: false)) { ed.doc.remove(ids: [pk.id]) }
            ed.print("Roof by extrusion #\(id): \(prof.count - 1) face(s), ridge +\(fmt(prof.map(\.y).max() ?? 0)).")
        }
    }

    static var roofShapePoints: CommandDef {
        CommandDef("ROOFSHAPEPOINTS", aliases: ["SHAPEEDIT", "DRAINAGEPOINTS", "ROOFFALLS", "SUBELEMENTS"], category: "Architecture",
                   summary: "Shape editing of flat roofs: Add points with a height (drainage falls, ridges) or raise the corners, List, Reset; the roof top becomes a triangulated surface.") { ed in
            let ids = try await ArchitectureCommands.elements(ed, "Select a flat roof") { if case .roof(let r) = $0 { return r.kind == .flat }; return false }
            guard let id = ids.first, let i = ed.doc.elementIndex(id), case .roof(var g) = ed.doc.elements[i].geometry else { throw CommandError.invalid("Select a flat roof.") }
            let k = try await ed.getKeyword("Shape option", ["Add", "Reset", "List"], defaultValue: "Add") ?? "Add"
            switch k {
            case "Reset": g.shapePoints = nil
            case "List":
                for p in g.shapePoints ?? [] { ed.print("  \(p.xy): \(fmt(p.z))") }
                return
            default:
                var pts = g.shapePoints ?? []
                while let p = try await ed.getPoint("Specify point (Enter = done)").point {
                    let dz = try await ed.getReal("Height above the flat top (negative = drain)", defaultValue: ed.variableDouble("SHAPEPOINTZ", -50)).value ?? 0
                    ed.doc.setVariable("SHAPEPOINTZ", fmt(dz))
                    pts.removeAll { $0.xy.distance(to: p) < 1e-6 }
                    pts.append(Vec3(p.x, p.y, dz))
                }
                g.shapePoints = pts.isEmpty ? nil : pts
            }
            ed.doc.elements[i].geometry = .roof(g)
            ed.print("\(g.shapePoints?.count ?? 0) shape point(s); \(RoofShapes.faces(g).faces.count) roof face(s).")
        }
    }

    static var stairSketch: CommandDef {
        CommandDef("STAIRSKETCH", aliases: ["STAIRBYSKETCH", "SKETCHSTAIR"], category: "Architecture",
                   summary: "Stair by sketch: select riser lines (bottom to top by the walking line), give the total rise; the riser/going rules are checked (max riser, min going, 2R+G).") { ed in
            let ids = try await ed.getEntitySelection("Select riser lines")
            var rs: [[Vec2]] = ids.compactMap { id in if case .line(let l)? = ed.doc.entity(id)?.geometry { return [l.a, l.b] }; return nil }
            guard rs.count >= 2 else { throw CommandError.invalid("Select at least two riser lines.") }
            // Order the risers along the walking direction (from the first line's midpoint towards the farthest one).
            let mids = rs.map { ($0[0] + $0[1]) / 2 }
            let c = mids.reduce(Vec2.zero, +) / Double(mids.count)
            // Deterministic ends: ties go to the lower-left midpoint.
            func less(_ a: Vec2, _ b: Vec2, from o: Vec2) -> Bool {
                let da = a.distance(to: o), db = b.distance(to: o)
                if abs(da - db) > 1e-9 { return da < db }
                return a.x != b.x ? a.x > b.x : a.y > b.y
            }
            let far = mids.max { less($0, $1, from: c) }!
            let first = mids.max { less($0, $1, from: far) }!
            rs.sort { (($0[0] + $0[1]) / 2).distance(to: first) < (($1[0] + $1[1]) / 2).distance(to: first) }
            if let flip = try await ed.getKeyword("Walking direction [Forward/Reverse]", ["Forward", "Reverse"], defaultValue: "Forward"), flip == "Reverse" { rs.reverse() }
            let rise = try await ed.getPositive("Total rise", defaultValue: ed.currentLevelHeight)
            let m0 = (rs[0][0] + rs[0][1]) / 2, m1 = (rs[1][0] + rs[1][1]) / 2
            var g = StairGeom(start: m0, direction: (m1 - m0).angle, width: rs[0][0].distance(to: rs[0][1]), totalRise: rise, riserCount: rs.count,
                              treadDepth: Round7Shapes.goings(rs).reduce(0, +) / Double(rs.count - 1))
            g.sketchRisers = rs
            let id = ed.doc.addElement(.stair(g), name: "Sketched stair")
            let issues = Round7Shapes.check(g, units: ed.doc.units, maxRiser: ed.variableDouble("STAIRMAXRISER", 190), minGoing: ed.variableDouble("STAIRMINGOING", 250))
            if issues.isEmpty { ed.print("Stair #\(id): \(rs.count) risers of \(fmt(g.riserHeight)), goings OK.") }
            for s in issues { ed.print("  ⚠ \(s)") }
            if let i = ed.doc.elementIndex(id), !issues.isEmpty { ed.doc.elements[i].props["stairWarnings"] = issues.joined(separator: " ") }
            if (try await ed.getYesNo("Delete the sketch lines?", defaultValue: true)) { ed.doc.remove(ids: Set(ids)) }
        }
    }

    static var slabEdge: CommandDef {
        CommandDef("SLABEDGE", aliases: ["SLABEDGES", "CURB", "UPSTAND", "BALCONYEDGE"], category: "Architecture",
                   summary: "Slab edges: an Upstand (curb, balcony upstand) or Fascia profile along a picked slab edge or All edges; Clear removes them.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Pick a slab near the edge", filter: { if case .slab? = ed.doc.element($0)?.geometry { return true }; return false }),
                  let i = ed.doc.elementIndex(pk.id), case .slab(var g) = ed.doc.elements[i].geometry else { return }
            let k = try await ed.getKeyword("Edge [Upstand/Fascia/Clear]", ["Upstand", "Fascia", "Clear"], defaultValue: "Upstand") ?? "Upstand"
            if k == "Clear" { g.edges = nil; ed.doc.elements[i].geometry = .slab(g); return }
            let all = (try await ed.getKeyword("Apply to [Picked edge/All edges]", ["Picked", "All"], defaultValue: "Picked") ?? "Picked") == "All"
            var b = RG.dedupe(g.boundary, closed: true)
            if GeometryOps.signedArea(b) < 0 { b.reverse() }
            let edge = all ? -1 : (b.indices.min { GeometryOps.distance(from: pk.point, toPolyline: [b[$0], b[($0 + 1) % b.count]]) < GeometryOps.distance(from: pk.point, toPolyline: [b[$1], b[($1 + 1) % b.count]]) } ?? 0)
            if GeometryOps.signedArea(g.boundary) < 0 { g.boundary = b }
            let u = 1 / ed.doc.units.mm
            let w = try await ed.getPositive("Width", defaultValue: (k == "Upstand" ? 150 : 50) * u)
            let h = try await ed.getPositive("Height", defaultValue: (k == "Upstand" ? 1000 : 400) * u)
            let m = try await ed.getWord("Material", defaultValue: ed.doc.elements[i].material ?? "Concrete")
            var es = g.edges ?? []
            es.removeAll { $0.edge == edge }
            es.append(SlabEdge(edge: edge, kind: k.lowercased(), width: w, height: h, material: m.flatMap { ed.doc.material($0)?.name ?? $0 }))
            g.edges = es
            ed.doc.elements[i].geometry = .slab(g)
            ed.print("\(k) on \(all ? "all edges" : "edge \(edge + 1)").")
        }
    }

    static var typeImage: CommandDef {
        CommandDef("TYPEIMAGE", aliases: ["SCHEDULEIMAGE", "TYPEPICTURE"], category: "Manage",
                   summary: "Assigns an image file to a type (wall/opening/family type); schedules with an Image field show it in placed tables.") { ed in
            guard let t = try await ed.getWord("Type name") else { return }
            guard let path = try await ed.getString("Image file (None = remove)") else { return }
            if path.lowercased() == "none" { ed.doc.variables["TYPEIMAGE." + t.uppercased()] = nil; return }
            ed.doc.setVariable("TYPEIMAGE." + t, path)
            var d = ed.doc; Schedules.updateAll(&d); ed.doc = d
            ed.print("Image of \(t): \(path).")
        }
    }
}
