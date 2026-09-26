// Oanarina Archi Tool — GPL-3.0-or-later
// Parametric solid modelling commands: CYLINDER (elliptical, 3P/2P, axis endpoint), EXTRUDE (taper, direction, path,
// both sides), associative REVOLVE, FOLLOWME, SWEEP3D/HELIXSWEEP, PAD, POCKET, HOLE, GROOVE/REVOLUTION,
// PATTERNFEATURE, MIRRORFEATURE, SPLITSOLID, GFUSE, SOLIDEDIT, OFFSETSOLID and CSGTREE.
import Foundation

enum FeatureCommands9 {
    /// Registered through ArchitectureCommands.all.
    static var all: [CommandDef] { [followMe, sweep3D, pad, pocket, hole, groove(subtract: true), groove(subtract: false),
                                    patternFeature, mirrorFeature, splitSolid, generalFuse, solidEdit, offsetSolid, csgTree, scale3D, shapeBinder] }

    // MARK: SHAPEBINDER (M3D-029)

    static var shapeBinder: CommandDef {
        CommandDef("SHAPEBINDER", aliases: ["BINDER", "SUBSHAPEBINDER"], category: "3D", summary: "Sub-shape binder: an associative copy of another body (Solid) or of one of its faces (Face, as a surface), optionally displaced; it follows the source when that changes.") { ed in
            let (sid, s) = try await requireSolid(ed, "Select the source body")
            let k = try await ed.getKeyword("Bind [Solid/Face]", ["Solid", "Face"], defaultValue: "Solid") ?? "Solid"
            var pick = Vec2.zero, fm = 0
            if k == "Face" {
                var mode = "top"
                while true {
                    let r = try await ed.getPoint("Pick a point on the \(mode) face or [Top/Bottom/Side]", keywords: ["Top", "Bottom", "Side"])
                    if case .keyword(let m) = r { mode = m.lowercased(); continue }
                    guard let p = r.point else { return }
                    guard PlanarFaces.pick(PlanarFaces.analyse(s), at: p, mode: mode) != nil else { ed.print("No \(mode) face there."); continue }
                    pick = p; fm = ShapeBinders.faceModes.firstIndex(of: mode) ?? 0
                    break
                }
            }
            var off = Vec3.zero
            if let b = try await ed.getPoint("Displacement base point <none>").point {
                let q = try await ed.requirePoint("Displacement second point", base: b) { x in [.line(LineGeom(b, x))] }
                off = Vec3(q.x - b.x, q.y - b.y, 0)
            }
            off.z = try await ed.getDistance("Vertical displacement", defaultValue: 0).value ?? 0
            let src = SolidSource(kind: .binder, profiles: [sid], params: [k == "Face" ? 1 : 0, pick.x, pick.y, Double(fm), off.x, off.y, off.z])
            guard let r = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The binder is empty.") }
            let id = ed.addEntity(.solid(AssociativeSolids.attach(r, source: src, doc: ed.doc)))
            if k == "Face", let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["surface"] = "Face binder" }
            ed.print("Binder #\(id) of #\(sid) (\(k.lowercased())).")
        }
    }

    // MARK: SCALE3D (M3D-106)

    static var scale3D: CommandDef {
        CommandDef("SCALE3D", aliases: ["SCALENU", "SCALEXYZ"], category: "3D", summary: "Non-uniform scale of solids about a base point: separate X, Y and Z factors (negative factors mirror).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to scale")
            guard !ids.isEmpty else { return }
            let b = try await ed.requirePoint("Specify base point")
            let bz = try await ed.getDistance("Specify base point elevation", defaultValue: z(ed)).value ?? 0
            let fx = try await ed.getReal("Scale factor X", defaultValue: 1).value ?? 1
            let fy = try await ed.getReal("Scale factor Y", defaultValue: fx).value ?? fx
            let fz = try await ed.getReal("Scale factor Z", defaultValue: 1).value ?? 1
            guard abs(fx) > 1e-12, abs(fy) > 1e-12, abs(fz) > 1e-12 else { throw CommandError.invalid("Scale factors must not be zero.") }
            let o = Vec3(b.x, b.y, bz)
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                let r = SolidOps.mapped(s, mirroring: fx * fy * fz < 0) { p in Vec3(o.x + (p.x - o.x) * fx, o.y + (p.y - o.y) * fy, o.z + (p.z - o.z) * fz) }
                ModelingCommands.replace(ed, id, with: r)
            }
            ed.selection = []
            ed.print("\(ids.count) solid(s) scaled by \(fmt(fx)) × \(fmt(fy)) × \(fmt(fz)).")
        }
    }

    /// Full CYLINDER / EXTRUDE / REVOLVE (M3D-003, M3D-014, M3D-016). They replace the basic versions in
    /// DrawCommands.swift once those definitions are removed there (command names must stay unique).
    static var drawOverrides: [CommandDef] { [cylinder, extrude, revolve] }

    // MARK: Helpers

    @MainActor static func z(_ ed: Editor) -> Double { PrimitiveCommands.z(ed) }

    /// Elevation of a sketch entity: its "elevation" property, else the current elevation.
    @MainActor static func sketchZ(_ ed: Editor, _ id: EntityID) -> Double {
        ed.doc.entity(id)?.props["elevation"].flatMap(Double.init) ?? z(ed)
    }

    @MainActor static func pickSolid(_ ed: Editor, _ msg: String, keywords: [String] = []) async throws -> Editor.PickAnswer {
        try await ed.pickObject(msg, keywords: keywords, filter: { ModelingCommands.solidOf(ed.doc, $0) != nil })
    }

    @MainActor static func requireSolid(_ ed: Editor, _ msg: String) async throws -> (EntityID, SolidGeom) {
        guard case .pick(let pk) = try await pickSolid(ed, msg), let s = ModelingCommands.solidOf(ed.doc, pk.id) else { throw CommandError.cancelled }
        return (pk.id, s)
    }

    @MainActor static func pickProfile(_ ed: Editor, _ msg: String) async throws -> (EntityID, [Vec2]) {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { ModelingCommands.loop(ed.doc, $0) != nil }), let l = ModelingCommands.loop(ed.doc, pk.id) else { throw CommandError.cancelled }
        return (pk.id, l)
    }

    /// Copies an entity's props onto new solids created from it (split pieces keep layer, colour and material).
    @MainActor static func addLike(_ ed: Editor, _ src: Entity, _ s: SolidGeom) -> EntityID {
        var e = src; e.id = 0; e.geometry = .solid(s)
        return ed.doc.add(e)
    }

    static func topZ(_ s: SolidGeom, at p: Vec2) -> Double? {
        if let f = FacePushPull.pick(s, at: p, mode: "top"), let t = f.triangles.first {
            let n = f.normal
            guard abs(n.z) > 1e-9 else { return nil }
            return t.0.z - (n.x * (p.x - t.0.x) + n.y * (p.y - t.0.y)) / n.z
        }
        return nil
    }

    /// Equal-area polygon of an ellipse (radii scaled so the polygon area equals π·a·b).
    static func ellipsePolygon(center c: Vec2, rx: Double, ry: Double, rotation: Double, segments n: Int) -> [Vec2] {
        let k = (2 * Double.pi / (Double(n) * sin(2 * .pi / Double(n)))).squareRoot()
        return (0..<n).map { i in
            let a = 2 * Double.pi * Double(i) / Double(n)
            return c + Vec2(rx * k * cos(a), ry * k * sin(a)).rotated(by: rotation)
        }
    }

    // MARK: CYLINDER (M3D-003)

    static var cylinder: CommandDef {
        CommandDef("CYLINDER", aliases: ["CYL"], category: "Draw", summary: "Creates a 3D solid cylinder: centre, 3P, 2P or Elliptical base; height, 2Point or Axis endpoint.") { ed in
            var center = Vec2.zero, rx = 0.0, ry = 0.0, rot = 0.0, elliptical = false
            let a = try await ed.getPoint("Specify center point of base or [3P/2P/Elliptical]", keywords: ["3P", "2P", "Elliptical"])
            switch a {
            case .point(let c):
                center = c
                let r = try await ed.getDistance("Specify base radius or [Diameter]", base: c, keywords: ["Diameter"]) { p in [.circle(CircleGeom(c, c.distance(to: p)))] }
                switch r {
                case .value(let v): rx = v
                case .keyword: rx = (try await ed.getDistance("Specify diameter", base: c).value ?? 0) / 2
                default: return
                }
                ry = rx
            case .keyword("3P"):
                let p1 = try await ed.requirePoint("Specify first point")
                let p2 = try await ed.requirePoint("Specify second point", base: p1)
                let p3 = try await ed.requirePoint("Specify third point", base: p2)
                guard let cc = CommandHelpers.circleFrom3(p1, p2, p3) else { throw CommandError.invalid("The three points are collinear.") }
                center = cc.center; rx = cc.radius; ry = rx
            case .keyword("2P"):
                let p1 = try await ed.requirePoint("Specify first end point of diameter")
                let p2 = try await ed.requirePoint("Specify second end point of diameter", base: p1) { p in [.circle(CircleGeom((p1 + p) / 2, p1.distance(to: p) / 2))] }
                center = (p1 + p2) / 2; rx = p1.distance(to: p2) / 2; ry = rx
            case .keyword("Elliptical"):
                let e1 = try await ed.requirePoint("Specify endpoint of first axis")
                let e2 = try await ed.requirePoint("Specify other endpoint of first axis", base: e1) { p in [.line(LineGeom(e1, p))] }
                guard e1.distance(to: e2) > 1e-9 else { throw CommandError.invalid("The axis has zero length.") }
                center = (e1 + e2) / 2; rx = e1.distance(to: e2) / 2; rot = (e2 - e1).angle
                guard let o = try await ed.getDistance("Specify endpoint of other axis (half-length)", base: center).value else { return }
                ry = o; elliptical = true
            default: return
            }
            guard rx > 1e-9, ry > 1e-9 else { throw CommandError.invalid("Radius must be positive.") }
            let z0 = z(ed)
            var hAns = try await ed.getDistance("Specify height or [2Point/Axis endpoint]", base: center, defaultValue: ed.variableDouble("BOXHEIGHT", 1000), keywords: ["2Point", "Axis"])
            var axisEnd: Vec3? = nil
            if case .keyword("2Point") = hAns {
                let p = try await ed.requirePoint("Specify first point")
                let q = try await ed.requirePoint("Specify second point", base: p)
                hAns = .value(p.distance(to: q))
            } else if case .keyword("Axis") = hAns {
                let p = try await ed.requirePoint("Specify axis endpoint (plan position)", base: center)
                let dz = try await ed.getDistance("Specify rise of the axis endpoint", defaultValue: 0).value ?? 0
                axisEnd = Vec3(p.x, p.y, z0 + dz)
            }
            if let e = axisEnd {
                let b = Vec3(center.x, center.y, z0)
                guard e.distance(to: b) > 1e-9 else { throw CommandError.invalid("The axis has zero length.") }
                let n = max(24, min(96, GeometryOps.segments(radius: max(rx, ry), sweep: 2 * .pi)))
                let prof = ellipsePolygon(center: .zero, rx: rx, ry: ry, rotation: 0, segments: n)
                guard let s = ModelingCommands.sweepSolid(prof, path: [b, e], closedPath: false) else { throw CommandError.invalid("Could not build the cylinder.") }
                let id = ed.addEntity(.solid(s))
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["primitive"] = "cylinder"; ed.doc.entities[i].props["radius"] = fmt(rx) }
                ed.print("Cylinder along axis: length \(fmt(e.distance(to: b))).")
                return
            }
            guard let h = hAns.value, abs(h) > 1e-9 else { throw CommandError.invalid("Height must not be zero.") }
            ed.doc.setVariable("BOXHEIGHT", fmt(abs(h)))
            if elliptical && abs(rx - ry) > 1e-9 {
                let n = max(48, min(128, GeometryOps.segments(radius: max(rx, ry), sweep: 2 * .pi)))
                let loop = ellipsePolygon(center: center, rx: rx, ry: ry, rotation: rot, segments: n)
                let id = ed.addEntity(.solid(ModelingCommands.extrusion(loop, z: z0, height: h)))
                if let i = ed.doc.entityIndex(id) {
                    ed.doc.entities[i].props["primitive"] = "ellipticalCylinder"
                    ed.doc.entities[i].props["radiusX"] = fmt(rx); ed.doc.entities[i].props["radiusY"] = fmt(ry)
                }
                return
            }
            ed.addEntity(.solid(SolidGeom(kind: .cylinder, origin: Vec3(center.x, center.y, h < 0 ? z0 + h : z0), size: Vec3(rx, rx, abs(h)))))
        }
    }

    // MARK: EXTRUDE (M3D-014)

    static var extrude: CommandDef {
        CommandDef("EXTRUDE", aliases: ["EXT"], category: "Draw", summary: "Extrudes closed 2D objects into 3D solids: height, Direction (oblique), Path, Taper angle, Both sides (symmetric).") { ed in
            let ids = try await ed.getEntitySelection("Select objects to extrude")
            let profiles = ids.compactMap { id in ModelingCommands.loop(ed.doc, id).map { (id, $0) } }
            guard !profiles.isEmpty else { throw CommandError.invalid("No closed profiles selected.") }
            var taper = 0.0, both = false, shift = Vec2.zero
            var height: Double? = nil
            var pathID: EntityID? = nil
            while height == nil && pathID == nil {
                let tag = (taper != 0 ? " taper \(fmt(deg(taper)))°" : "") + (both ? " both sides" : "") + (shift != .zero ? " shifted \(shift.description)" : "")
                let r = try await ed.getDistance("Specify height of extrusion\(tag) or [Direction/Path/Taper/Both]", defaultValue: ed.variableDouble("BOXHEIGHT", 1000), keywords: ["Direction", "Path", "Taper", "Both"])
                switch r {
                case .value(let v): height = v
                case .keyword("Taper"): taper = try await ed.getAngle("Specify angle of taper for extrusion", defaultValue: taper).value ?? taper
                case .keyword("Both"): both.toggle()
                case .keyword("Direction"):
                    let p = try await ed.requirePoint("Specify start point of direction (plan)")
                    let q = try await ed.requirePoint("Specify end point of direction (plan)", base: p) { x in [.line(LineGeom(p, x))] }
                    shift = q - p
                case .keyword("Path"):
                    guard case .pick(let pk) = try await ed.pickObject("Select extrusion path", filter: { id in ModelingCommands.path(ed.doc, id) != nil && !profiles.contains { $0.0 == id } }) else { return }
                    pathID = pk.id
                default: return
                }
            }
            let keep = ed.variableDouble("DELOBJ", 1) == 0
            var n = 0
            for (pid, loop) in profiles {
                let z0 = sketchZ(ed, pid)
                var s: SolidGeom?
                if let path = pathID {
                    guard let pth = FeatureSources.path3(ed.doc, path) else { continue }
                    s = ModelingCommands.sweepSolid(loop, path: pth.points, closedPath: pth.closed)
                    if keep, let x = s { s = AssociativeSolids.attach(x, source: SolidSource(kind: .sweep3D, profiles: [pid], path: path), doc: ed.doc) }
                } else if let h0 = height {
                    guard abs(h0) > 1e-9 else { throw CommandError.invalid("Height must not be zero.") }
                    let zb = both ? z0 - abs(h0) : z0
                    let h = both ? 2 * abs(h0) : h0
                    if shift != .zero {
                        // Oblique extrusion: the top is the profile moved by the direction vector.
                        var l = loop
                        if GeometryOps.signedArea(l) < 0 { l.reverse() }
                        let top = l.map { $0 + shift }
                        s = try? SolidOps.closedLoft(h > 0 ? [(pts: l, z: zb), (pts: top, z: zb + h)] : [(pts: top, z: zb + h), (pts: l, z: zb)])
                    } else if both && taper != 0 {
                        // Symmetric tapered: two tapered halves joined at the sketch plane.
                        if let up = FeatureSources.extrudeSolid(loop, z: z0, height: abs(h0), taper: taper),
                           let dn = FeatureSources.extrudeSolid(loop, z: z0, height: -abs(h0), taper: taper) { s = CSG.apply(.union, up, dn) }
                    } else {
                        s = FeatureSources.extrudeSolid(loop, z: zb, height: h, taper: taper)
                        if keep, let x = s, shift == .zero {
                            s = AssociativeSolids.attach(x, source: SolidSource(kind: .extrude, profiles: [pid], params: [zb, h, taper]), doc: ed.doc)
                        }
                    }
                }
                guard let solid = s else { ed.print("#\(pid): the extrusion failed (taper too steep for the profile?)."); continue }
                ed.addEntity(.solid(solid)); n += 1
            }
            if let h = height { ed.doc.setVariable("BOXHEIGHT", fmt(abs(h))) }
            if !keep && n > 0 { ed.doc.remove(ids: Set(profiles.map(\.0))) }
            ed.selection = []
            ed.print("\(n) solid(s) created.")
        }
    }

    // MARK: REVOLVE (M3D-016)

    static var revolve: CommandDef {
        CommandDef("REVOLVE", aliases: ["REV"], category: "Draw", summary: "Revolves closed 2D objects about an axis into 3D solids (associative: the solid regenerates when the profile is edited; DELOBJ 1 deletes profiles).") { ed in
            let ids = try await ed.getEntitySelection("Select objects to revolve")
            let profiles = ids.compactMap { id in ModelingCommands.loop(ed.doc, id).map { (id, $0) } }
            guard !profiles.isEmpty else { throw CommandError.invalid("No closed profiles selected.") }
            let a = try await ed.requirePoint("Specify axis start point")
            let b = try await ed.requirePoint("Specify axis endpoint", base: a) { p in [.line(LineGeom(a, p))] }
            guard a.distance(to: b) > 1e-9 else { throw CommandError.invalid("Axis has zero length.") }
            let ang = try await ed.getAngle("Specify angle of revolution", defaultValue: 2 * .pi).value ?? 2 * .pi
            let keep = ed.variableDouble("DELOBJ", 0) == 0
            var n = 0
            for (pid, loop) in profiles {
                let z0 = sketchZ(ed, pid)
                guard var s = FeatureSources.revolveSolid(loop, axisA: a, axisB: b, angle: ang, z: z0) else {
                    ed.print("#\(pid): the profile crosses the axis."); continue
                }
                if keep { s = AssociativeSolids.attach(s, source: SolidSource(kind: .revolve, profiles: [pid], params: [a.x, a.y, b.x, b.y, ang, z0]), doc: ed.doc) }
                let id = ed.addEntity(.solid(s))
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["revolveAxis"] = "localY" }
                n += 1
            }
            if !keep && n > 0 { ed.doc.remove(ids: Set(profiles.map(\.0))) }
            ed.selection = []
            ed.print("\(n) revolved solid(s) created.")
        }
    }

    // MARK: FOLLOWME (M3D-020) and SWEEP3D (M3D-021)

    static var followMe: CommandDef {
        CommandDef("FOLLOWME", aliases: ["FOLLOW"], category: "3D", summary: "SketchUp-style follow me: sweeps a profile along a path keeping its position relative to the path start (x = offset left of the path, y = height); associative.") { ed in
            let (pid, loop) = try await pickProfile(ed, "Select the profile (face) to follow the path")
            guard case .pick(let pk) = try await ed.pickObject("Select the path", filter: { $0 != pid && ModelingCommands.path(ed.doc, $0) != nil }),
                  let pth = FeatureSources.path3(ed.doc, pk.id) else { return }
            let start = pth.points[0].xy
            let ref = try await ed.getPoint("Specify the profile point that sits on the path <path start>").point ?? start
            guard var s = FeatureSources.followMe(loop, reference: ref, path: pth.points, closed: pth.closed) else { throw CommandError.invalid("Follow me failed (path too short?).") }
            s = AssociativeSolids.attach(s, source: SolidSource(kind: .followMe, profiles: [pid], path: pk.id, params: [ref.x, ref.y]), doc: ed.doc)
            ed.addEntity(.solid(s))
            ed.print("Follow me: volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        }
    }

    static var sweep3D: CommandDef {
        CommandDef("SWEEP3D", aliases: ["HELIXSWEEP", "SWEEPHELIX"], category: "3D", summary: "Sweeps a closed profile (centred on the path) along a 3D path such as a helix (or a new Helix); associative with profile and path.") { ed in
            let (pid, loop) = try await pickProfile(ed, "Select closed profile")
            let r = try await ed.pickObject("Select 3D path (helix, 3D polyline) or [Helix]", keywords: ["Helix"], filter: { $0 != pid && ModelingCommands.path(ed.doc, $0) != nil })
            var pathID: EntityID
            switch r {
            case .pick(let pk): pathID = pk.id
            case .keyword:
                let c = try await ed.requirePoint("Specify helix centre")
                let rad = try await ed.getPositive("Specify helix radius", base: c, defaultValue: 500)
                let pitch = try await ed.getPositive("Specify pitch (rise per turn)", defaultValue: 200)
                let turns = try await ed.getReal("Enter number of turns", defaultValue: 3).value ?? 3
                guard turns > 0, turns <= 200 else { throw CommandError.invalid("Enter between 0 and 200 turns.") }
                let ccw = (try await ed.getKeyword("Twist [CW/CCW]", ["CW", "CCW"], defaultValue: "CCW") ?? "CCW") == "CCW"
                var e = Helix.entity(center: c, baseRadius: rad, topRadius: rad, turns: turns, height: pitch * turns, ccw: ccw, layer: ed.doc.currentLayer)
                e.props["elevation"] = nil
                pathID = ed.doc.add(e)
            default: return
            }
            let base = try await ed.getDistance("Specify base elevation of the path", defaultValue: z(ed)).value ?? 0
            guard let pth = FeatureSources.path3(ed.doc, pathID, z: base),
                  var s = ModelingCommands.sweepSolid(loop, path: pth.points, closedPath: pth.closed) else { throw CommandError.invalid("The sweep failed.") }
            s = AssociativeSolids.attach(s, source: SolidSource(kind: .sweep3D, profiles: [pid], path: pathID, elevation: base), doc: ed.doc)
            ed.addEntity(.solid(s))
            ed.print("Swept solid: volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        }
    }

    // MARK: PAD / POCKET (M3D-022)

    static var pad: CommandDef {
        CommandDef("PAD", aliases: ["BOSS", "PADFEATURE"], category: "3D", summary: "PartDesign pad: extrudes a sketch profile (optionally tapered) and adds it to a solid, or creates a new body; regenerates when the sketch changes.") { ed in
            let (pid, _) = try await pickProfile(ed, "Select sketch profile")
            let t = try await pickSolid(ed, "Select the body to add to or [New]", keywords: ["New"])
            var taper = 0.0
            var len: Double? = nil
            while len == nil {
                let r = try await ed.getDistance("Specify pad length\(taper != 0 ? " (taper \(fmt(deg(taper)))°)" : "") or [Taper]", defaultValue: ed.variableDouble("PADLENGTH", 100), keywords: ["Taper"])
                switch r {
                case .value(let v): len = v
                case .keyword: taper = try await ed.getAngle("Specify taper angle", defaultValue: 0).value ?? 0
                default: return
                }
            }
            guard let h = len, abs(h) > 1e-9 else { throw CommandError.invalid("The length must not be zero.") }
            ed.doc.setVariable("PADLENGTH", fmt(abs(h)))
            let src = SolidSource(kind: .extrude, profiles: [pid], params: [sketchZ(ed, pid), h, taper])
            if case .pick(let pk) = t, let base = ModelingCommands.solidOf(ed.doc, pk.id) {
                guard let r = FeatureSources.addFeature(.union, to: base, source: src, name: "Pad", doc: ed.doc) else { throw CommandError.invalid("The pad failed.") }
                ModelingCommands.replace(ed, pk.id, with: r)
                ed.print("Pad added to #\(pk.id): volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
            } else {
                guard let s = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The pad failed (taper too steep?).") }
                ed.addEntity(.solid(AssociativeSolids.attach(s, source: src, doc: ed.doc)))
                ed.print("New body: volume " + ModelingCommands.volumeText(CSG.volume(s), units: ed.doc.units) + ".")
            }
        }
    }

    static var pocket: CommandDef {
        CommandDef("POCKET", aliases: ["POCKETFEATURE", "CUTEXTRUDE"], category: "3D", summary: "PartDesign pocket: cuts a sketch profile into a solid by a depth (downwards from the sketch) or Through all; regenerates when the sketch changes.") { ed in
            let (pid, _) = try await pickProfile(ed, "Select sketch profile")
            let (sid, base) = try await requireSolid(ed, "Select the body to cut")
            let zs = sketchZ(ed, pid)
            let box = ModelingCommands.bounds(base)
            let r = try await ed.getDistance("Specify pocket depth or [Through/Reversed]", defaultValue: ed.variableDouble("POCKETDEPTH", 50), keywords: ["Through", "Reversed"])
            var h: Double
            switch r {
            case .value(let v): h = -abs(v); ed.doc.setVariable("POCKETDEPTH", fmt(abs(v)))
            case .keyword("Through"): h = -(zs - box.min.z + max(1, box.size.z * 0.01))
            case .keyword("Reversed"): h = abs(try await ed.getDistance("Specify pocket depth (upwards)", defaultValue: 50).value ?? 50)
            default: return
            }
            guard abs(h) > 1e-9 else { throw CommandError.invalid("The depth must not be zero.") }
            // The cut starts slightly outside the sketch plane so coplanar faces are removed cleanly.
            let over = (h < 0 ? 1.0 : -1.0) * max(1e-3, abs(h) * 1e-3)
            let src = SolidSource(kind: .extrude, profiles: [pid], params: [zs + over, h - over, 0])
            guard let res = FeatureSources.addFeature(.subtract, to: base, source: src, name: "Pocket", doc: ed.doc) else { throw CommandError.invalid("The pocket removes the whole body.") }
            ModelingCommands.replace(ed, sid, with: res)
            ed.print("Pocket cut in #\(sid): volume " + ModelingCommands.volumeText(CSG.volume(res), units: ed.doc.units) + ".")
        }
    }

    // MARK: HOLE (M3D-023)

    static var hole: CommandDef {
        CommandDef("HOLE", aliases: ["HOLEFEATURE", "DRILL"], category: "3D", summary: "Hole features at sketch points or circles: diameter, depth or Through, Simple / Counterbore / Countersink, optional thread designation; follow their sketch.") { ed in
            let (sid, base0) = try await requireSolid(ed, "Select the body")
            ed.selection = []
            let ids = try await ed.getEntitySelection("Select hole centres (points or circles)").filter { FeatureSources.holeCentre(ed.doc, $0) != nil }
            guard !ids.isEmpty else { throw CommandError.invalid("Select points or circles as hole centres.") }
            let fromCircle = ids.contains { if case .circle? = ed.doc.entity($0)?.geometry { return true }; return false }
            var dia = ed.variableDouble("HOLEDIA", 10)
            if !fromCircle || ids.contains(where: { if case .point? = ed.doc.entity($0)?.geometry { return true }; return false }) {
                dia = try await ed.getPositive("Specify hole diameter", defaultValue: dia)
                ed.doc.setVariable("HOLEDIA", fmt(dia))
            }
            let box = ModelingCommands.bounds(base0)
            let dr = try await ed.getDistance("Specify depth or [Through]", defaultValue: ed.variableDouble("HOLEDEPTH", 20), keywords: ["Through"])
            var depth = 0.0, through = false
            switch dr { case .value(let v): depth = abs(v); ed.doc.setVariable("HOLEDEPTH", fmt(depth)); case .keyword: through = true; default: return }
            let tk = try await ed.getKeyword("Hole type [Simple/Counterbore/Countersink]", ["Simple", "Counterbore", "Countersink"], defaultValue: "Simple") ?? "Simple"
            var type = FeatureSources.HoleType.simple, d2 = 0.0, depth2 = 0.0, angle = rad(90)
            if tk == "Counterbore" {
                type = .counterbore
                d2 = try await ed.getPositive("Specify counterbore diameter", defaultValue: dia * 1.8)
                depth2 = try await ed.getPositive("Specify counterbore depth", defaultValue: dia * 0.6)
            } else if tk == "Countersink" {
                type = .countersink
                d2 = try await ed.getPositive("Specify countersink diameter", defaultValue: dia * 2)
                angle = try await ed.getAngle("Specify countersink angle", defaultValue: rad(90)).value ?? rad(90)
            }
            let thread = try await ed.getWord("Thread designation (e.g. M10) or . for none", defaultValue: ".") ?? "."
            var s = base0
            var n = 0
            for id in ids {
                guard let (c, _) = FeatureSources.holeCentre(ed.doc, id) else { continue }
                let top = topZ(s, at: c) ?? box.max.z
                let dp = through ? top - box.min.z + max(1, box.size.z * 0.01) : depth
                let src = SolidSource(kind: .hole, profiles: [id], params: [dia, dp, Double(type.rawValue), d2, depth2, angle, top])
                let name = "Hole \(tk)" + (thread != "." && !thread.isEmpty ? " \(thread)" : "")
                guard let r = FeatureSources.addFeature(.subtract, to: s, source: src, name: name, doc: ed.doc) else { continue }
                s = r; n += 1
            }
            guard n > 0 else { throw CommandError.invalid("No hole could be cut.") }
            ModelingCommands.replace(ed, sid, with: s)
            if thread != ".", !thread.isEmpty, let i = ed.doc.entityIndex(sid) { ed.doc.entities[i].props["thread"] = thread }
            ed.print("\(n) hole(s) cut in #\(sid).")
        }
    }

    // MARK: GROOVE / REVOLUTION (M3D-024)

    static func groove(subtract: Bool) -> CommandDef {
        CommandDef(subtract ? "GROOVE" : "REVOLUTION", aliases: subtract ? ["GROOVEFEATURE", "REVOLVECUT"] : ["REVOLUTIONFEATURE", "REVOLVEADD"], category: "3D",
                   summary: subtract ? "PartDesign groove: revolves a sketch profile about an axis and subtracts it from a body (follows the sketch)."
                                     : "PartDesign revolution: revolves a sketch profile about an axis and adds it to a body (follows the sketch).") { ed in
            let (sid, base) = try await requireSolid(ed, "Select the body")
            let (pid, loop) = try await pickProfile(ed, "Select sketch profile")
            let a = try await ed.requirePoint("Specify axis start point")
            let b = try await ed.requirePoint("Specify axis endpoint", base: a) { p in [.line(LineGeom(a, p))] }
            let ang = try await ed.getAngle("Specify angle", defaultValue: 2 * .pi).value ?? 2 * .pi
            let z0 = sketchZ(ed, pid)
            guard FeatureSources.revolveSolid(loop, axisA: a, axisB: b, angle: ang, z: z0) != nil else { throw CommandError.invalid("The profile must lie on one side of the axis.") }
            let src = SolidSource(kind: .revolve, profiles: [pid], params: [a.x, a.y, b.x, b.y, ang, z0])
            guard let r = FeatureSources.addFeature(subtract ? .subtract : .union, to: base, source: src, name: subtract ? "Groove" : "Revolution", doc: ed.doc) else {
                throw CommandError.invalid("The \(subtract ? "groove" : "revolution") failed.")
            }
            ModelingCommands.replace(ed, sid, with: r)
            ed.print("\(subtract ? "Groove" : "Revolution") applied to #\(sid): volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    // MARK: PATTERNFEATURE / MIRRORFEATURE (M3D-026, M3D-027)

    @MainActor static func pickFeature(_ ed: Editor, _ s: SolidGeom) async throws -> Int? {
        guard let h = s.history, !h.features.isEmpty else { return nil }
        for line in SolidHistoryEngine.describe(h) { ed.print(line) }
        let r = try await ed.getWord("Feature number <\(h.features.count)> or [Body]", defaultValue: "\(h.features.count)", keywords: ["Body"])
        if r == "Body" { return nil }
        guard let k = Int(r ?? ""), k >= 1, k <= h.features.count else { throw CommandError.invalid("No such feature.") }
        return k - 1
    }

    static var patternFeature: CommandDef {
        CommandDef("PATTERNFEATURE", aliases: ["LINEARPATTERN", "POLARPATTERN", "FEATUREPATTERN"], category: "3D", summary: "Repeats a feature (or the whole body) in a Linear (columns × rows) or Polar pattern; instances follow the feature's sketch.") { ed in
            let (sid, s) = try await requireSolid(ed, "Select the body")
            let fi = try await pickFeature(ed, s)
            let kind = try await ed.getKeyword("Pattern type [Linear/Polar]", ["Linear", "Polar"], defaultValue: "Linear") ?? "Linear"
            let pattern: FeaturePattern
            if kind == "Polar" {
                let c = try await ed.requirePoint("Specify centre of the pattern (vertical axis)")
                guard let n = try await ed.getInteger("Enter number of items", defaultValue: 6), n >= 2 else { throw CommandError.invalid("At least two items.") }
                let a = try await ed.getAngle("Specify angle to fill", defaultValue: 2 * .pi).value ?? 2 * .pi
                pattern = FeaturePattern(polar: n, center: c, angle: abs(a) < 1e-9 ? 2 * .pi : a)
            } else {
                guard let n = try await ed.getInteger("Enter number of columns", defaultValue: 3), n >= 1 else { return }
                let dx = n > 1 ? (try await ed.getDistance("Specify distance between columns (X)", defaultValue: 100).value ?? 100) : 0
                let rows = try await ed.getInteger("Enter number of rows", defaultValue: 1) ?? 1
                let dy = rows > 1 ? (try await ed.getDistance("Specify distance between rows (Y)", defaultValue: 100).value ?? 100) : 0
                let dz = try await ed.getDistance("Specify rise per column (Z)", defaultValue: 0).value ?? 0
                guard n * max(rows, 1) >= 2 else { throw CommandError.invalid("The pattern needs at least two items.") }
                pattern = FeaturePattern(linear: n, step: Vec3(dx, 0, dz), count2: max(rows, 1), step2: Vec3(0, dy, 0))
            }
            var h = s.history ?? SolidHistory(base: s)
            if let k = fi { h.features[k].pattern = pattern }
            else { h.features.append(SolidFeature(op: .union, tool: SolidFeature.bodyTool, name: "Body pattern", pattern: pattern)) }
            guard var r = SolidHistoryEngine.evaluate(h) else { throw CommandError.invalid("The pattern removed the whole body.") }
            r.history = h; r.source = s.source
            ModelingCommands.replace(ed, sid, with: r)
            ed.print("Pattern applied: volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    static var mirrorFeature: CommandDef {
        CommandDef("MIRRORFEATURE", aliases: ["FEATUREMIRROR", "MIRRORED"], category: "3D", summary: "Mirrors a feature (or the whole body) about a vertical plane through two points or the XY plane at a height; stays parametric.") { ed in
            let (sid, s) = try await requireSolid(ed, "Select the body")
            let fi = try await pickFeature(ed, s)
            let a = try await ed.getPoint("Specify first point of mirror plane or [XY]", keywords: ["XY"])
            let m: FeatureMirror
            switch a {
            case .point(let p):
                let q = try await ed.requirePoint("Specify second point of mirror plane", base: p) { x in [.line(LineGeom(p, x))] }
                guard p.distance(to: q) > 1e-9 else { throw CommandError.invalid("The mirror line has zero length.") }
                m = FeatureMirror(a: p, b: q)
            case .keyword: m = FeatureMirror(z: try await ed.getDistance("Specify height of the XY mirror plane", defaultValue: 0).value ?? 0)
            default: return
            }
            var h = s.history ?? SolidHistory(base: s)
            if let k = fi { h.features[k].mirror = m }
            else { h.features.append(SolidFeature(op: .union, tool: SolidFeature.bodyTool, name: "Body mirror", mirror: m)) }
            guard var r = SolidHistoryEngine.evaluate(h) else { throw CommandError.invalid("The mirror removed the whole body.") }
            r.history = h; r.source = s.source
            ModelingCommands.replace(ed, sid, with: r)
            ed.print("Mirror applied: volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    // MARK: SPLITSOLID / GFUSE (M3D-033)

    static var splitSolid: CommandDef {
        CommandDef("SPLITSOLID", aliases: ["SPLITBODY", "BOOLEANFRAGMENTS"], category: "3D", summary: "Splits solids by other solids into the parts inside and outside the tools (separate bodies).") { ed in
            let targets = try await ModelingCommands.selectSolids(ed, "Select solids to split")
            guard !targets.isEmpty else { return }
            ed.selection = []
            let tools = try await ModelingCommands.selectSolids(ed, "Select cutting solids").filter { !targets.contains($0) }
            guard !tools.isEmpty else { throw CommandError.invalid("Select at least one cutting solid.") }
            let keep = try await ed.getYesNo("Keep the cutting solids?", defaultValue: true)
            var made = 0
            for t in targets {
                guard let e = ed.doc.entity(t), case .solid(let s0) = e.geometry else { continue }
                var parts = [s0]
                for tid in tools { guard let ts = ModelingCommands.solidOf(ed.doc, tid) else { continue }; parts = parts.flatMap { SolidSplit.split($0, by: ts) } }
                guard parts.count > 1 else { continue }
                ModelingCommands.replace(ed, t, with: parts[0])
                for p in parts.dropFirst() { _ = addLike(ed, e, p) }
                made += parts.count
            }
            if !keep { ed.doc.remove(ids: Set(tools)) }
            ed.selection = []
            ed.print(made == 0 ? "The tools do not cut the solids." : "\(made) part(s) after splitting.")
        }
    }

    static var generalFuse: CommandDef {
        CommandDef("GFUSE", aliases: ["GENERALFUSE", "FRAGMENT"], category: "3D", summary: "General fuse: cuts overlapping solids into non-overlapping pieces (overlaps become their own solids).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to fuse")
            guard ids.count >= 2, let first = ed.doc.entity(ids[0]) else { throw CommandError.invalid("Select at least two solids.") }
            let solids = ids.compactMap { ModelingCommands.solidOf(ed.doc, $0) }
            let pieces = SolidSplit.generalFuse(solids)
            guard !pieces.isEmpty else { throw CommandError.invalid("General fuse produced nothing.") }
            ed.doc.remove(ids: Set(ids))
            for p in pieces { _ = addLike(ed, first, p) }
            ed.selection = []
            ed.print("\(solids.count) solids → \(pieces.count) pieces.")
        }
    }

    // MARK: SOLIDEDIT / OFFSETSOLID (M3D-041, M3D-046)

    static var solidEdit: CommandDef {
        CommandDef("SOLIDEDIT", aliases: ["SOLED"], category: "3D", summary: "Edits solid faces: Extrude, Move, Offset, Taper or Copy a face (picked Top/Bottom/Side in plan); Body Offset or Separate.") { ed in
            let what = try await ed.getKeyword("Enter a solids editing option [Face/Body]", ["Face", "Body"], defaultValue: "Face") ?? "Face"
            if what == "Body" {
                let op = try await ed.getKeyword("Body option [Offset/Separate]", ["Offset", "Separate"], defaultValue: "Offset") ?? "Offset"
                let (sid, s) = try await requireSolid(ed, "Select a 3D solid")
                if op == "Separate" {
                    guard let e = ed.doc.entity(sid) else { return }
                    let parts = SolidCheck.separate(s)
                    guard parts.count > 1 else { ed.print("The solid is a single body."); return }
                    ModelingCommands.replace(ed, sid, with: parts[0])
                    for p in parts.dropFirst() { _ = addLike(ed, e, p) }
                    ed.print("\(parts.count) bodies.")
                    return
                }
                let d = try await ed.getDistance("Specify offset distance (negative shrinks)", defaultValue: 10).value ?? 10
                guard let r = PlanarFaces.offsetSolid(s, distance: d) else { throw CommandError.invalid("The offset would change the solid's topology.") }
                ModelingCommands.replace(ed, sid, with: r)
                ed.print("Body offset by \(fmt(d)).")
                return
            }
            let op = try await ed.getKeyword("Enter a face editing option [Extrude/Move/Offset/Taper/Copy]", ["Extrude", "Move", "Offset", "Taper", "Copy"], defaultValue: "Offset") ?? "Offset"
            let (sid, s) = try await requireSolid(ed, "Select a 3D solid")
            let an = PlanarFaces.analyse(s)
            var mode = "top"
            var face: Int? = nil
            while face == nil {
                let r = try await ed.getPoint("Pick a point on the \(mode) face or [Top/Bottom/Side]", keywords: ["Top", "Bottom", "Side"])
                switch r {
                case .point(let p):
                    face = PlanarFaces.pick(an, at: p, mode: mode)
                    if face == nil { ed.print("No \(mode) face there.") }
                case .keyword(let k): mode = k.lowercased()
                default: return
                }
            }
            let f = face!
            var result: SolidGeom?
            switch op {
            case "Extrude":
                let d = try await ed.getDistance("Specify height of extrusion (negative pushes in)", defaultValue: 100).value ?? 100
                let tris = an.faceOf.indices.filter { an.faceOf[$0] == f }.map { k in (an.vertices[an.triangles[3 * k]], an.vertices[an.triangles[3 * k + 1]], an.vertices[an.triangles[3 * k + 2]]) }
                let pf = FacePushPull.face(tris, seed: 0)
                result = FacePushPull.apply(s, face: pf, distance: d)
            case "Move":
                let a = try await ed.requirePoint("Specify base point")
                let b = try await ed.requirePoint("Specify second point", base: a) { x in [.line(LineGeom(a, x))] }
                let dz = try await ed.getDistance("Specify vertical move", defaultValue: 0).value ?? 0
                result = PlanarFaces.moveFaces(s, analysis: an, faces: [f], by: Vec3(b.x - a.x, b.y - a.y, dz))
            case "Offset":
                let d = try await ed.getDistance("Specify the offset distance", defaultValue: 100).value ?? 100
                result = PlanarFaces.offsetFace(s, analysis: an, face: f, distance: d)
            case "Taper":
                let a = try await ed.getAngle("Specify the taper angle", defaultValue: rad(10)).value ?? rad(10)
                result = PlanarFaces.taperFace(s, analysis: an, face: f, angle: a)
            case "Copy":
                var tris: [Tri3] = []
                for k in an.faceOf.indices where an.faceOf[k] == f { tris.append((an.vertices[an.triangles[3 * k]], an.vertices[an.triangles[3 * k + 1]], an.vertices[an.triangles[3 * k + 2]])) }
                let w = MeshTools.weld(tris, tolerance: 1e-6)
                var b = BBox3.empty; w.vertices.forEach { b.add($0) }
                let id = ed.addEntity(.solid(SolidGeom(kind: .mesh, origin: b.min, meshVertices: w.vertices, meshTriangles: w.triangles)))
                if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["surface"] = "Face copy" }
                ed.print("Face copied as a surface (area \(fmt(an.area(ofFace: f)))).")
                return
            default: return
            }
            guard var r = result else { throw CommandError.invalid("The face edit would invert the solid.") }
            if op != "Extrude" { r.history = nil }
            ModelingCommands.replace(ed, sid, with: r)
            ed.print("Face \(op.lowercased()): volume " + ModelingCommands.volumeText(CSG.volume(r), units: ed.doc.units) + ".")
        }
    }

    static var offsetSolid: CommandDef {
        CommandDef("OFFSETSOLID", aliases: ["SOLIDOFFSET", "OFFSETBODY"], category: "3D", summary: "Offsets solids: every face moves outwards (or inwards, negative) by the distance.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select solids to offset")
            guard !ids.isEmpty else { return }
            let d = try await ed.getDistance("Specify offset distance (negative shrinks)", defaultValue: ed.variableDouble("OFFSETSOLIDDIST", 10)).value ?? 10
            ed.doc.setVariable("OFFSETSOLIDDIST", fmt(d))
            var n = 0
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                guard let r = PlanarFaces.offsetSolid(s, distance: d) else { ed.print("#\(id): the offset would change the topology."); continue }
                ModelingCommands.replace(ed, id, with: r); n += 1
            }
            ed.selection = []
            ed.print("\(n) solid(s) offset by \(fmt(d)).")
        }
    }

    // MARK: CSGTREE (M3D-095)

    static let csgLayer = "CSG-PRIMITIVES"

    static var csgTree: CommandDef {
        CommandDef("CSGTREE", aliases: ["COMB", "REGION3D", "CSGCOMB"], category: "3D", summary: "BRL-CAD style combination: 'u #1 - #2 + #3 u #4' (u union, - subtract, + intersect); the result regenerates when a member changes. List / Edit existing trees.") { ed in
            let r = try await ed.getWord("Enter combination (e.g. u #1 - #2 + #3) or [List/Edit]", keywords: ["List", "Edit"])
            guard let text = r else { return }
            if text == "List" || text == "Edit" {
                guard case .pick(let pk) = try await ed.pickObject("Select a combination", filter: { ModelingCommands.solidOf(ed.doc, $0)?.source?.kind == .csgTree }),
                      let s = ModelingCommands.solidOf(ed.doc, pk.id), var src = s.source, let ex = src.expression else { return }
                if text == "List" {
                    for l in CSGTrees.describe(ex, name: { id in
                        guard let e = ed.doc.entity(id), case .solid(let m) = e.geometry else { return "#\(id) (missing)" }
                        return "#\(id) \(m.kind.rawValue)" + (m.source?.kind == .csgTree ? " (combination)" : "")
                    }) { ed.print(l) }
                    return
                }
                guard let ne = try await ed.getString("New combination", defaultValue: ex), let groups = CSGTrees.parse(ne) else { throw CommandError.invalid("Invalid combination.") }
                let ids = CSGTrees.ids(ne)
                guard ids.allSatisfy({ ModelingCommands.solidOf(ed.doc, $0) != nil && $0 != pk.id }) else { throw CommandError.invalid("Every member must be another solid.") }
                src.profiles = ids; src.expression = CSGTrees.format(groups)
                guard let res = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The combination is empty.") }
                ModelingCommands.replace(ed, pk.id, with: AssociativeSolids.attach(res, source: src, doc: ed.doc))
                ed.print("Combination updated.")
                return
            }
            guard let groups = CSGTrees.parse(text) else { throw CommandError.invalid("Invalid combination: use u, - and + between solid ids, e.g. u #1 - #2.") }
            let ids = CSGTrees.ids(text)
            guard ids.allSatisfy({ ModelingCommands.solidOf(ed.doc, $0) != nil }) else { throw CommandError.invalid("Every member must be a 3D solid.") }
            let src = SolidSource(kind: .csgTree, profiles: ids, expression: CSGTrees.format(groups))
            guard let res = FeatureSources.build(src, doc: ed.doc) else { throw CommandError.invalid("The combination is empty.") }
            let hide = try await ed.getYesNo("Hide the member primitives?", defaultValue: true)
            let id = ed.addEntity(.solid(AssociativeSolids.attach(res, source: src, doc: ed.doc)))
            if hide {
                if ed.doc.layer(named: csgLayer) == nil { var l = Layer(name: csgLayer); l.visible = false; l.description = "CSG member primitives"; ed.doc.layers.append(l) }
                for m in ids { if let i = ed.doc.entityIndex(m) { ed.doc.entities[i].props["csgLayer"] = ed.doc.entities[i].layer; ed.doc.entities[i].layer = csgLayer } }
            }
            ed.selection = []
            ed.print("Combination #\(id): \(CSGTrees.format(groups)) — volume " + ModelingCommands.volumeText(CSG.volume(res), units: ed.doc.units) + ".")
        }
    }
}
