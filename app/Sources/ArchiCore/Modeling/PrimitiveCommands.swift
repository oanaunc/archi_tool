// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for the extra primitives and solid utilities in SolidPrimitives.swift.
import Foundation

enum PrimitiveCommands {
    static var all: [CommandDef] { [wedge, pyramid, torus, prism, polyhedron, polysolid, hull, thicken, planeSurf, separate, check, mesh, convToMesh, convToSolid, linearExtrude] }

    @MainActor static func z(_ ed: Editor) -> Double { ed.variableDouble("ELEVATION", ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0) }

    @MainActor static func add(_ ed: Editor, _ s: SolidGeom?, _ what: String) throws {
        guard let s = s else { throw CommandError.invalid("Invalid \(what) dimensions.") }
        let id = ed.addEntity(.solid(s))
        ed.selection = [id]
        ed.print("\(what) created: volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
    }

    static var mesh: CommandDef {
        CommandDef("MESH", aliases: ["MESHPRIMITIVE", "MESHBOX"], category: "3D", summary: "Faceted mesh primitives with divisions (MESHDIVISIONS): Box, Cylinder, Cone, Sphere, Torus, Wedge, Pyramid.") { ed in
            let k = try await ed.getKeyword("Mesh primitive", ["Box", "Cylinder", "Cone", "Sphere", "Torus", "Wedge", "Pyramid"], defaultValue: ed.doc.variable("MESHTYPE") ?? "Box") ?? "Box"
            ed.doc.setVariable("MESHTYPE", k)
            let div = try await ed.getInteger("Divisions", defaultValue: Int(ed.variableDouble("MESHDIVISIONS", 3))) ?? 3
            guard div >= 1 else { throw CommandError.invalid("At least one division.") }
            ed.doc.setVariable("MESHDIVISIONS", "\(div)")
            let zz = z(ed)
            var s: SolidGeom?
            switch k {
            case "Box":
                let a = try await ed.requirePoint("Specify first corner")
                let b = try await ed.requirePoint("Specify other corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                let h = try await ed.getDistance("Specify height", defaultValue: max(abs(b.x - a.x), 1)).value ?? 1000
                let bb = BBox2(points: [a, b])
                s = SolidPrimitives.meshBox(origin: Vec3(bb.min.x, bb.min.y, min(zz, zz + h)), size: Vec3(bb.width, bb.height, abs(h)), divisions: div)
            case "Sphere":
                let c = try await ed.requirePoint("Specify center point")
                let r = try await ed.getPositive("Specify radius", base: c, defaultValue: 500)
                s = SolidPrimitives.meshSphere(center: Vec3(c.x, c.y, zz), radius: r, segments: max(6, div * 4))
            case "Torus":
                let c = try await ed.requirePoint("Specify center point")
                let R = try await ed.getPositive("Specify radius", base: c, defaultValue: 1000)
                let r = try await ed.getPositive("Specify tube radius", defaultValue: R / 4)
                s = SolidPrimitives.torus(center: Vec3(c.x, c.y, zz + r), radius: R, tube: r, segments: max(3, div * 4), tubeSegments: max(3, div * 2))
            case "Wedge":
                let a = try await ed.requirePoint("Specify first corner")
                let b = try await ed.requirePoint("Specify other corner", base: a)
                let h = try await ed.getDistance("Specify height", defaultValue: 1000).value ?? 1000
                s = SolidPrimitives.wedge(corner: Vec3(min(a.x, b.x), min(a.y, b.y), zz), length: abs(b.x - a.x), width: abs(b.y - a.y), height: h)
            default:
                let c = try await ed.requirePoint("Specify center point of base")
                let r = try await ed.getPositive("Specify base radius", base: c, defaultValue: 500)
                let h = try await ed.getDistance("Specify height", defaultValue: 1000).value ?? 1000
                let sides = k == "Pyramid" ? max(3, div + 2) : max(6, div * 4)
                s = k == "Cylinder" ? SolidPrimitives.prism(center: Vec3(c.x, c.y, zz), sides: sides, radius: r, height: h)
                                    : SolidPrimitives.pyramid(center: Vec3(c.x, c.y, zz), sides: sides, radius: r, height: h)
            }
            guard let sg = s else { throw CommandError.invalid("Invalid dimensions.") }
            let id = ed.addEntity(.solid(sg))
            if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["mesh"] = k.lowercased() }
            ed.selection = [id]
            ed.print("Mesh \(k.lowercased()) created: \(sg.meshTriangles.count / 3) faces.")
        }
    }

    static var convToMesh: CommandDef {
        CommandDef("CONVTOMESH", aliases: ["TOMESH", "SOLIDTOMESH"], category: "3D", summary: "Converts parametric solids (box, cylinder, extrusion, revolve…) into editable triangle meshes.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to convert")
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .solid(let s) = ed.doc.entities[i].geometry, s.kind != .mesh else { continue }
                ed.doc.entities[i].geometry = .solid(MeshTools.solid(from: SolidCheck.triangles(s), tolerance: 1e-6))
                ed.doc.entities[i].props["mesh"] = "converted"
                n += 1
            }
            ed.print("\(n) solid(s) converted to meshes.")
        }
    }

    static var convToSolid: CommandDef {
        CommandDef("CONVTOSOLID", aliases: ["TOSOLID", "MESHTOSOLID"], category: "3D", summary: "Converts closed meshes into solids (cleaned and oriented); open meshes are refused (MESHREPAIR can close them).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select meshes to convert")
            var n = 0, open = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .solid(let s) = ed.doc.entities[i].geometry else { continue }
                let t = SolidCheck.clean(SolidCheck.triangles(s))
                let r = SolidCheck.report(t)
                guard r.closed, let sg = SolidPrimitives.solid(t) else { open += 1; continue }
                ed.doc.entities[i].geometry = .solid(sg)
                ed.doc.entities[i].props["mesh"] = nil; ed.doc.entities[i].props["surface"] = nil
                n += 1
            }
            ed.print("\(n) mesh(es) converted to solids." + (open > 0 ? " \(open) open mesh(es) skipped." : ""))
        }
    }

    static var linearExtrude: CommandDef {
        CommandDef("LINEAREXTRUDE", aliases: ["TWISTEXTRUDE", "LEXTRUDE"], category: "3D", summary: "OpenSCAD-style linear extrude of closed profiles: height, twist angle and top scale (slices follow the twist).") { ed in
            let ids = try await ed.getSelection("Select closed profiles").filter { ModelingCommands.loop(ed.doc, $0) != nil }
            guard !ids.isEmpty else { throw CommandError.invalid("Select closed profiles.") }
            let h = try await ed.getDistance("Height", defaultValue: 1000).value ?? 1000
            let tw = try await ed.getReal("Twist angle in degrees", defaultValue: 0).value ?? 0
            let sc = try await ed.getReal("Top scale", defaultValue: 1).value ?? 1
            guard sc >= 0 else { throw CommandError.invalid("The scale cannot be negative.") }
            var n = 0
            for id in ids {
                guard let l = ModelingCommands.loop(ed.doc, id), let s = SolidPrimitives.linearExtrude(l, z: ed.doc.entity(id)?.props["elevation"].flatMap(Double.init) ?? z(ed), height: h, twist: tw * .pi / 180, scale: sc) else { continue }
                ed.addEntity(.solid(s)); n += 1
            }
            if ed.variableDouble("DELOBJ", 0) != 0 { ed.doc.remove(ids: Set(ids)) }
            ed.print("\(n) profile(s) extruded.")
        }
    }

    static var wedge: CommandDef {
        CommandDef("WEDGE", aliases: ["WE"], category: "3D", summary: "Creates a wedge solid: base rectangle by two corners (or Length), height; the top slopes down along X.") { ed in
            let a = try await ed.requirePoint("Specify first corner")
            let r = try await ed.getPoint("Specify other corner", base: a, keywords: ["Length"]) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
            var l: Double, w: Double
            switch r {
            case .point(let q): l = q.x - a.x; w = q.y - a.y
            case .keyword:
                l = try await ed.getPositive("Specify length", base: a, defaultValue: 1000)
                w = try await ed.getPositive("Specify width", base: a, defaultValue: l)
            default: return
            }
            let h = try await ed.getDistance("Specify height", defaultValue: max(abs(l), abs(w))).value ?? 1000
            // Normalise a corner picked to the left/below: keep the sloping direction along +X from the high edge.
            var c = a
            if w < 0 { c.y += w; w = -w }
            try add(ed, SolidPrimitives.wedge(corner: Vec3(c.x, c.y, z(ed)), length: l, width: w, height: h), "Wedge")
        }
    }

    static var pyramid: CommandDef {
        CommandDef("PYRAMID", aliases: ["PYR"], category: "3D", summary: "Creates a pyramid or frustum with N sides: base centre, base radius, height (Top radius for a frustum).") { ed in
            let n = try await ed.getInteger("Number of sides", defaultValue: 4) ?? 4
            guard n >= 3 else { throw CommandError.invalid("At least 3 sides.") }
            let c = try await ed.requirePoint("Specify center point of base")
            let rr = try await ed.getDistance("Specify base radius", base: c, preview: { p in [.polyline(PolylineGeom(points: RG.circle(c, c.distance(to: p), segments: n), closed: true))] })
            guard let r = rr.value, r > 0 else { return }
            let rot = 0.0
            var top = 0.0
            var hv: Double?
            while hv == nil {
                let h = try await ed.getDistance("Specify height", defaultValue: r, keywords: ["Top"])
                if case .keyword = h { top = try await ed.getPositive("Specify top radius", defaultValue: r / 2, allowZero: true); continue }
                guard let v = h.value else { return }
                hv = v
            }
            try add(ed, SolidPrimitives.pyramid(center: Vec3(c.x, c.y, z(ed)), sides: n, radius: r, topRadius: top, height: hv!, rotation: rot), top > 0 ? "Frustum" : "Pyramid")
        }
    }

    static var torus: CommandDef {
        CommandDef("TORUS", aliases: ["TOR"], category: "3D", summary: "Creates a torus: centre, radius of the torus, radius of the tube.") { ed in
            let c = try await ed.requirePoint("Specify center point")
            let R = try await ed.getPositive("Specify radius", base: c, defaultValue: 1000)
            let r = try await ed.getPositive("Specify tube radius", defaultValue: R / 4)
            guard r < R else { throw CommandError.invalid("The tube radius must be smaller than the torus radius.") }
            try add(ed, SolidPrimitives.torus(center: Vec3(c.x, c.y, z(ed) + r), radius: R, tube: r), "Torus")
        }
    }

    static var prism: CommandDef {
        CommandDef("PRISM", aliases: ["REGULARPRISM", "HOLLOWPRISM"], category: "3D", summary: "Regular prism (N sides) or tube (inner radius > 0): centre, circumradius, height.") { ed in
            let n = try await ed.getInteger("Number of sides (64 or more = round)", defaultValue: 6) ?? 6
            guard n >= 3 else { throw CommandError.invalid("At least 3 sides.") }
            let c = try await ed.requirePoint("Specify center point")
            let rr = try await ed.getDistance("Specify radius", base: c, preview: { p in [.polyline(PolylineGeom(points: RG.circle(c, c.distance(to: p), segments: n), closed: true))] })
            guard let r = rr.value, r > 0 else { return }
            let ri = try await ed.getPositive("Specify inner radius (0 = solid)", defaultValue: 0, allowZero: true)
            let h = try await ed.getDistance("Specify height", defaultValue: r).value ?? r
            try add(ed, SolidPrimitives.prism(center: Vec3(c.x, c.y, z(ed)), sides: n, radius: r, height: h, innerRadius: ri), ri > 0 ? "Tube" : "Prism")
        }
    }

    static var polyhedron: CommandDef {
        CommandDef("POLYHEDRON", aliases: ["POLYHEDRA"], category: "3D", summary: "Solid from points (x,y,z) and faces (point numbers from 1, e.g. 1,2,3,4) like OpenSCAD polyhedron().") { ed in
            var pts: [Vec3] = []
            while true {
                guard let s = try await ed.getString("Point \(pts.count + 1) as x,y,z (Enter when done)"), !s.isEmpty else { break }
                let c = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard c.count >= 2 else { throw CommandError.invalid("Enter x,y,z.") }
                pts.append(Vec3(c[0], c[1], c.count > 2 ? c[2] : 0))
            }
            guard pts.count >= 4 else { throw CommandError.invalid("A polyhedron needs at least 4 points.") }
            var faces: [[Int]] = []
            while true {
                guard let s = try await ed.getString("Face \(faces.count + 1) as point numbers 1,2,3… (Enter when done)"), !s.isEmpty else { break }
                faces.append(s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)).map { $0 - 1 } })
            }
            guard let sg = SolidPrimitives.polyhedron(points: pts, faces: faces) else { throw CommandError.invalid("The faces do not close a volume.") }
            try add(ed, sg, "Polyhedron")
        }
    }

    static var polysolid: CommandDef {
        CommandDef("POLYSOLID", aliases: ["PSOLID"], category: "3D", summary: "Draws a wall-like solid along points or converts a line/polyline/arc (Object); Height, Width, Justify.") { ed in
            var h = ed.variableDouble("PSOLHEIGHT", 2500 / ed.doc.units.mm), w = ed.variableDouble("PSOLWIDTH", 200 / ed.doc.units.mm)
            var just = ed.doc.variable("PSOLJUSTIFY") ?? "Center"
            var pts: [Vec2] = []
            var closed = false
            loop: while true {
                let r = try await ed.getPoint("Specify start point [Object/Height/Width/Justify] (height \(fmt(h)), width \(fmt(w)), \(just))", keywords: ["Object", "Height", "Width", "Justify"])
                switch r {
                case .keyword("Height"): h = try await ed.getPositive("Specify height", defaultValue: h)
                case .keyword("Width"): w = try await ed.getPositive("Specify width", defaultValue: w)
                case .keyword("Justify"): just = try await ed.getKeyword("Justification", ["Left", "Center", "Right"], defaultValue: just) ?? just
                case .keyword("Object"):
                    guard case .pick(let pk) = try await ed.pickObject("Select a line, polyline, arc or circle", filter: { ModelingCommands.path(ed.doc, $0) != nil }),
                          let p = ModelingCommands.path(ed.doc, pk.id) else { return }
                    pts = p.points; closed = p.closed
                    break loop
                case .point(let p):
                    pts = [p]
                    while true {
                        let last = pts.last!
                        let n = try await ed.getPoint("Specify next point", base: last, keywords: pts.count >= 3 ? ["Close", "Undo"] : ["Undo"]) { c in [.polyline(PolylineGeom(points: pts + [c]))] }
                        switch n {
                        case .point(let q): pts.append(q)
                        case .keyword("Undo"): if pts.count > 1 { pts.removeLast() }
                        case .keyword("Close"): closed = true; break loop
                        default: break loop
                        }
                    }
                default: return
                }
            }
            ed.doc.setVariable("PSOLHEIGHT", fmt(h)); ed.doc.setVariable("PSOLWIDTH", fmt(w)); ed.doc.setVariable("PSOLJUSTIFY", just)
            guard pts.count >= 2 else { throw CommandError.invalid("Specify at least two points.") }
            try add(ed, SolidPrimitives.polysolid(path: pts, z: z(ed), width: w, height: h, justify: just, closed: closed), "Polysolid")
        }
    }

    static var hull: CommandDef {
        CommandDef("HULL", aliases: ["CONVEXHULL", "HULL3D"], category: "3D", summary: "Convex hull solid of the selected solids (and points/curves at their elevation), like OpenSCAD hull().") { ed in
            let ids = try await ed.getSelection("Select solids, points or curves")
            var pts: [Vec3] = []
            for id in ids {
                guard let e = ed.doc.entity(id) else { continue }
                if case .solid(let s) = e.geometry { pts += MeshTools.mesh(of: s).positions; continue }
                let zz = e.props["elevation"].flatMap(Double.init) ?? 0
                if case .point(let p) = e.geometry { pts.append(Vec3(p.x, p.y, zz)); continue }
                for l in GeometryOps.tessellate(e.geometry, doc: ed.doc) { pts += l.map { Vec3($0.x, $0.y, zz) } }
            }
            guard let s = SolidPrimitives.hull(pts) else { throw CommandError.invalid("The hull needs points that are not all in one plane.") }
            let keep = try await ed.getYesNo("Keep the source objects?", defaultValue: true)
            if !keep { ed.doc.remove(ids: Set(ids)) }
            try add(ed, s, "Hull")
        }
    }

    static var thicken: CommandDef {
        CommandDef("THICKEN", aliases: ["THICK"], category: "3D", summary: "Turns surfaces into solids by offsetting them along their normals (negative = other side).") { ed in
            let ids = try await ed.getSelection("Select surfaces to thicken").filter {
                if case .solid(let s)? = ed.doc.entity($0)?.geometry { return s.kind == .mesh }; return false }
            guard !ids.isEmpty else { throw CommandError.invalid("Select mesh surfaces.") }
            let t = try await ed.getDistance("Specify thickness", defaultValue: ed.variableDouble("THICKNESS3D", 100 / ed.doc.units.mm)).value ?? 100
            ed.doc.setVariable("THICKNESS3D", fmt(t))
            var n = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .solid(let s) = ed.doc.entities[i].geometry,
                      let r = SolidPrimitives.thicken(vertices: s.meshVertices, triangles: s.meshTriangles, thickness: t) else { continue }
                ed.doc.entities[i].geometry = .solid(r)
                ed.doc.entities[i].props["surface"] = nil
                n += 1
            }
            ed.print("\(n) surface(s) thickened.")
        }
    }

    static var planeSurf: CommandDef {
        CommandDef("PLANESURF", aliases: ["PLANARSURFACE", "PSURF"], category: "3D", summary: "Planar surface from a closed boundary (Object, with inner loops as holes) or from two corners of a rectangle.") { ed in
            let r = try await ed.getPoint("Specify first corner", keywords: ["Object"])
            var outer: [Vec2] = [], holes: [[Vec2]] = []
            var zz = z(ed)
            switch r {
            case .point(let a):
                let b = try await ed.requirePoint("Specify other corner", base: a) { c in [.polyline(PolylineGeom(points: BBox2(points: [a, c]).corners, closed: true))] }
                outer = BBox2(points: [a, b]).corners
            case .keyword:
                let ids = try await ed.getSelection("Select closed boundaries")
                let loops = ids.compactMap { ModelingCommands.loop(ed.doc, $0) }.sorted { abs(GeometryOps.signedArea($0)) > abs(GeometryOps.signedArea($1)) }
                guard let o = loops.first else { throw CommandError.invalid("No closed boundary selected.") }
                outer = o
                holes = loops.dropFirst().filter { GeometryOps.pointInPolygon($0[0], o) }
                if let e = ids.first.flatMap({ ed.doc.entity($0) }), let el = e.props["elevation"].flatMap(Double.init) { zz = el }
            default: return
            }
            guard let s = SolidPrimitives.planarSurface(outer, holes: holes, z: zz) else { throw CommandError.invalid("The boundary has no area.") }
            try SurfaceCommands.addSurface(ed, s, what: "Planar surface")
        }
    }

    static var separate: CommandDef {
        CommandDef("SEPARATE", aliases: ["SOLIDSEPARATE", "SOLIDCLEAN"], category: "3D", summary: "Separates solids into their disjoint bodies and cleans them (duplicate/degenerate faces, consistent outward orientation).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids")
            var made = 0
            for id in ids {
                guard let i = ed.doc.entityIndex(id), case .solid(let s) = ed.doc.entities[i].geometry else { continue }
                let cleaned = SolidCheck.clean(SolidCheck.triangles(s))
                guard let c = SolidPrimitives.solid(cleaned) else { continue }
                let parts = SolidCheck.separate(c)
                guard let first = parts.first else { continue }
                ed.doc.entities[i].geometry = .solid(first)
                for p in parts.dropFirst() { var e = ed.doc.entities[i]; e.geometry = .solid(p); e.id = 0; _ = ed.doc.add(e); made += 1 }
            }
            ed.print("\(ids.count) solid(s) cleaned" + (made > 0 ? ", \(made) extra body(ies) separated." : "."))
        }
    }

    static var check: CommandDef {
        CommandDef("SOLIDCHECK", aliases: ["CHECKSOLID", "VALIDATESOLID", "CHECKGEOMETRY"], category: "3D", summary: "Validates solids: open or non-manifold edges, inconsistent orientation, degenerate faces, volume and bodies.", modifies: false) { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to check")
            var bad = 0
            for id in ids {
                guard case .solid(let s)? = ed.doc.entity(id)?.geometry else { continue }
                let r = SolidCheck.report(SolidCheck.triangles(s))
                if !r.valid { bad += 1 }
                ed.print("#\(id): " + r.summary)
            }
            ed.print(bad == 0 ? "All \(ids.count) solid(s) are valid." : "\(bad) of \(ids.count) solid(s) have problems (SEPARATE cleans orientation and duplicates).")
        }
    }
}
