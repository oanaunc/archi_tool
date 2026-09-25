// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// 3D modelling commands: solid booleans (BSP CSG), slice, interference, press/pull, loft, sweep, pipe,
/// and site topography (surface from points/contours, contours, building pads).
enum ModelingCommands {
    static var all: [CommandDef] { booleans + forming + site + SolidEditCommands.all + SurfaceCommands.all + FeatureCommands.all + PrimitiveCommands.all }

    static func solidOf(_ doc: ArchiDocument, _ id: EntityID) -> SolidGeom? {
        if case .solid(let s)? = doc.entity(id)?.geometry { return s }
        return nil
    }

    @MainActor static func selectSolids(_ ed: Editor, _ msg: String) async throws -> [EntityID] {
        ed.selection = ed.selection.filter { solidOf(ed.doc, $0) != nil }
        let ids = try await ed.getSelection(msg)
        // Selections are sets: order them by drawing order so results are deterministic.
        let s = ids.filter { solidOf(ed.doc, $0) != nil }.sorted { (ed.doc.entityIndex($0) ?? 0) < (ed.doc.entityIndex($1) ?? 0) }
        if s.count < ids.count { ed.print("\(ids.count - s.count) non-solid object(s) ignored.") }
        return s
    }

    /// Replaces entity `id` with a mesh solid (keeping layer, color and properties).
    @MainActor static func replace(_ ed: Editor, _ id: EntityID, with s: SolidGeom) {
        guard let i = ed.doc.entityIndex(id) else { return }
        ed.doc.entities[i].geometry = .solid(s)
    }

    static func volumeText(_ v: Double, units: Units) -> String {
        let m3 = v * pow(units.mm, 3) / 1e9
        return String(format: "%.4f m³", m3)
    }

    static func bounds(_ s: SolidGeom) -> BBox3 { MeshTools.mesh(of: s).bounds }

    // MARK: Booleans

    static var booleans: [CommandDef] { [
        CommandDef("UNION", aliases: ["UNI"], category: "3D", summary: "Combines selected 3D solids into one.") { ed in
            var ids = try await selectSolids(ed, "Select solids to unite")
            guard ids.count >= 2 else { throw CommandError.invalid("Select at least two solids.") }
            // A solid with a feature history survives so its history continues.
            if let h = ids.firstIndex(where: { solidOf(ed.doc, $0)?.history != nil }), h > 0 { ids.insert(ids.remove(at: h), at: 0) }
            var acc = solidOf(ed.doc, ids[0])!
            for id in ids.dropFirst() {
                guard let s = solidOf(ed.doc, id), let r = boolean(ed, .union, acc, s) else { continue }
                acc = r
            }
            replace(ed, ids[0], with: acc)
            ed.doc.remove(ids: Set(ids.dropFirst()))
            ed.selection = []
            ed.print("\(ids.count) solids united: volume " + volumeText(CSG.volume(acc), units: ed.doc.units) + ".")
        },
        CommandDef("SUBTRACT", aliases: ["SU"], category: "3D", summary: "Subtracts solids from other solids.") { ed in
            let base = try await selectSolids(ed, "Select solids to subtract from")
            guard !base.isEmpty else { return }
            ed.selection = []
            let tools = try await selectSolids(ed, "Select solids to subtract").filter { !base.contains($0) }
            guard !tools.isEmpty else { throw CommandError.invalid("Nothing to subtract.") }
            var removed = Set(tools)
            for b in base {
                guard var s = solidOf(ed.doc, b) else { continue }
                var empty = false
                for t in tools {
                    guard let ts = solidOf(ed.doc, t) else { continue }
                    if let r = boolean(ed, .subtract, s, ts) { s = r } else { empty = true; break }
                }
                if empty { removed.insert(b); ed.print("#\(b) was entirely removed.") } else { replace(ed, b, with: s) }
            }
            ed.doc.remove(ids: removed)
            ed.selection = []
            ed.print("Subtracted \(tools.count) solid(s) from \(base.count).")
        },
        CommandDef("INTERSECT", aliases: ["INTERSECTSOLIDS"], category: "3D", summary: "Keeps only the common volume of the selected solids.") { ed in
            let ids = try await selectSolids(ed, "Select solids to intersect")
            guard ids.count >= 2 else { throw CommandError.invalid("Select at least two solids.") }
            var acc: SolidGeom? = solidOf(ed.doc, ids[0])
            for id in ids.dropFirst() {
                guard let a = acc, let s = solidOf(ed.doc, id) else { break }
                acc = boolean(ed, .intersect, a, s)
            }
            if let r = acc {
                replace(ed, ids[0], with: r)
                ed.doc.remove(ids: Set(ids.dropFirst()))
                ed.print("Intersection volume " + volumeText(CSG.volume(r), units: ed.doc.units) + ".")
            } else {
                ed.doc.remove(ids: Set(ids))
                ed.print("The solids do not overlap; all were removed (use UNDO to restore).")
            }
            ed.selection = []
        },
        CommandDef("SLICE", aliases: ["SL3D"], category: "3D", summary: "Cuts solids with a vertical plane through two points or a horizontal plane (XY) at a height.") { ed in
            let ids = try await selectSolids(ed, "Select solids to slice")
            guard !ids.isEmpty else { return }
            var box = BBox3.empty
            for id in ids { let b = bounds(solidOf(ed.doc, id)!); box.add(b.min); box.add(b.max) }
            let big = max(box.size.x, box.size.y, box.size.z, 1) * 4
            let a = try await ed.getPoint("Specify first point on the vertical slicing plane", keywords: ["XY"])
            var cutter: SolidGeom
            var other: SolidGeom
            switch a {
            case .keyword:
                guard let z = try await ed.getDistance("Specify height of the horizontal plane", defaultValue: box.center.z).value else { return }
                let keep = try await ed.getKeyword("Keep", ["Above", "Below", "Both"], defaultValue: "Both") ?? "Both"
                let lo = Vec3(box.min.x - big, box.min.y - big, box.min.z - big)
                let below = SolidGeom(kind: .box, origin: lo, size: Vec3(box.size.x + 2 * big, box.size.y + 2 * big, z - lo.z))
                let above = SolidGeom(kind: .box, origin: Vec3(lo.x, lo.y, z), size: Vec3(box.size.x + 2 * big, box.size.y + 2 * big, box.max.z + big - z))
                cutter = keep == "Below" ? below : above; other = keep == "Below" ? above : below
                if keep == "Both" { try sliceBoth(ed, ids, above, below); return }
            case .point(let p):
                let q = try await ed.requirePoint("Specify second point on the plane", base: p) { c in [.line(LineGeom(p, c))] }
                guard q.distance(to: p) > 1e-9 else { return }
                let d = (q - p).normalized, n = d.perp
                let side = try await ed.getPoint("Specify a point on the side to keep (Enter = keep both)", base: q).point
                func half(_ s: Double) -> SolidGeom {
                    let c = (p + q) / 2
                    let r = [c - d * big * 2, c + d * big * 2, c + d * big * 2 + n * (s * big * 2), c - d * big * 2 + n * (s * big * 2)]
                    let prof = GeometryOps.signedArea(r) < 0 ? r.reversed() : r
                    return SolidGeom(kind: .extrusion, origin: Vec3(prof[0].x, prof[0].y, box.min.z - big), profile: prof.map { $0 - prof[0] }, height: box.size.z + 2 * big)
                }
                let left = half(1), right = half(-1)
                guard let sp = side else { try sliceBoth(ed, ids, left, right); return }
                let keepLeft = d.cross(sp - p) > 0
                cutter = keepLeft ? left : right; other = keepLeft ? right : left
            default: return
            }
            _ = other
            var n = 0
            for id in ids {
                guard let s = solidOf(ed.doc, id) else { continue }
                if let r = CSG.apply(.intersect, s, cutter) { replace(ed, id, with: r) } else { ed.doc.remove(ids: [id]) }
                n += 1
            }
            ed.selection = []
            ed.print("\(n) solid(s) sliced.")
        },
        CommandDef("INTERFERE", aliases: ["INF", "CLASH"], category: "3D", summary: "Finds overlapping volumes between two sets of solids and can create them as new solids.") { ed in
            let a = try await selectSolids(ed, "Select first set of solids")
            ed.selection = []
            var b = try await selectSolids(ed, "Select second set of solids (Enter = check the first set against itself)")
            if b.isEmpty { b = a }
            var hits: [(EntityID, EntityID, SolidGeom)] = []
            for x in a { for y in b where x < y || !a.contains(y) || !b.contains(x) {
                guard x != y, let sx = solidOf(ed.doc, x), let sy = solidOf(ed.doc, y) else { continue }
                let bx = bounds(sx), by = bounds(sy)
                guard bx.min.x <= by.max.x, by.min.x <= bx.max.x, bx.min.y <= by.max.y, by.min.y <= bx.max.y, bx.min.z <= by.max.z, by.min.z <= bx.max.z else { continue }
                if let r = CSG.apply(.intersect, sx, sy), CSG.volume(r) > 1e-9 { hits.append((x, y, r)) }
            } }
            ed.selection = []
            guard !hits.isEmpty else { ed.print("No interference found."); return }
            for h in hits { ed.print("#\(h.0) × #\(h.1): " + volumeText(CSG.volume(h.2), units: ed.doc.units)) }
            if try await ed.getYesNo("Create interference solids?", defaultValue: true) {
                if ed.doc.layer(named: "INTERFERENCE") == nil { ed.doc.layers.append(Layer(name: "INTERFERENCE", color: RGBA(1, 0.2, 0.2))) }
                for h in hits { ed.doc.add(.solid(h.2), layer: "INTERFERENCE") }
            }
        },
    ] }

    /// A boolean that records a feature history when SOLIDHIST = 1 or the base solid already has one.
    @MainActor static func boolean(_ ed: Editor, _ op: SolidFeature.Op, _ a: SolidGeom, _ b: SolidGeom) -> SolidGeom? {
        if a.history != nil || ed.doc.variable("SOLIDHIST") == "1" { return SolidHistoryEngine.record(op, base: a, tool: b) }
        let o: CSG.Operation = op == .union ? .union : (op == .subtract ? .subtract : .intersect)
        return CSG.apply(o, a, b)
    }

    @MainActor static func sliceBoth(_ ed: Editor, _ ids: [EntityID], _ a: SolidGeom, _ b: SolidGeom) throws {
        var n = 0
        for id in ids {
            guard let s = solidOf(ed.doc, id), let e = ed.doc.entity(id) else { continue }
            let ra = CSG.apply(.intersect, s, a), rb = CSG.apply(.intersect, s, b)
            if let r = ra { replace(ed, id, with: r) } else { ed.doc.remove(ids: [id]) }
            if let r = rb { var c = e; c.geometry = .solid(r); if ra == nil { c.id = 0 }; ed.doc.add(c) }
            n += 1
        }
        ed.selection = []
        ed.print("\(n) solid(s) sliced into two parts.")
    }

    // MARK: Forming

    /// Closed loop points of an entity (polylines, circles, ellipses, closed splines).
    static func loop(_ doc: ArchiDocument, _ id: EntityID) -> [Vec2]? {
        guard let e = doc.entity(id), let l = CommandHelpers.closedLoop(e.geometry) else { return nil }
        var p = RG.dedupe(CommandHelpers.loopPoints(l), closed: true)
        guard p.count >= 3, abs(GeometryOps.signedArea(p)) > 1e-9 else { return nil }
        if GeometryOps.signedArea(p) < 0 { p.reverse() }
        return p
    }

    /// Open or closed path points of an entity.
    static func path(_ doc: ArchiDocument, _ id: EntityID) -> (points: [Vec2], closed: Bool)? {
        guard let e = doc.entity(id) else { return nil }
        let closed: Bool
        switch e.geometry {
        case .polyline(let p): closed = p.closed
        case .circle: closed = true
        case .ellipse(let el): closed = el.isFull
        case .spline(let s): closed = s.closed
        case .line, .arc: closed = false
        default: return nil
        }
        guard let pts = GeometryOps.tessellate(e.geometry, doc: doc).first(where: { $0.count >= 2 }) else { return nil }
        return (RG.dedupe(pts, closed: closed), closed)
    }

    static func extrusion(_ loop: [Vec2], z: Double, height h: Double) -> SolidGeom {
        let o = loop[0]
        return SolidGeom(kind: .extrusion, origin: Vec3(o.x, o.y, h < 0 ? z + h : z), profile: loop.map { $0 - o }, height: abs(h))
    }

    /// Sweep of a closed profile (centered on its centroid; x → left of travel, y → up) along a 3D path, as a mesh solid.
    static func sweepSolid(_ profile: [Vec2], path: [Vec3], closedPath: Bool) -> SolidGeom? {
        let c = GeometryOps.centroid(profile)
        var acc = MeshAcc()
        SweepMesh.sweep(profile.map { $0 - c }, along: path, closedPath: closedPath, into: &acc)
        guard !acc.mesh.isEmpty else { return nil }
        return MeshTools.solid(from: MeshTools.triangles(acc.mesh), tolerance: 1e-6)
    }

    static var forming: [CommandDef] { [
        CommandDef("PRESSPULL", aliases: ["PP", "PUSHPULL"], category: "3D", summary: "Extrudes the area around a picked point (with islands as holes), a closed object, or changes an extrusion's height.") { ed in
            let z0 = ed.variableDouble("ELEVATION", 0)
            let a = try await ed.getPoint("Pick inside a bounded area or on a closed object / extrusion")
            guard let p = a.point else { return }
            var profile: [Vec2]? = nil, holes: [[Vec2]] = []
            var source: EntityID? = nil
            if let id = ed.pickFiltered(at: p, filter: { ed.doc.entity($0) != nil }) {
                if case .solid(let s)? = ed.doc.entity(id)?.geometry, s.kind != .extrusion && s.kind != .box || s.history != nil {
                    try await pushPullFace(ed, id, s, at: p, mode: "top")
                    return
                }
                if case .solid(var s)? = ed.doc.entity(id)?.geometry, s.kind == .extrusion || s.kind == .box {
                    let cur = s.kind == .box ? s.size.z : s.height
                    guard let h = try await ed.getDistance("Specify new height", defaultValue: cur).value, abs(h) > 1e-9 else { return }
                    if s.kind == .box { s.size.z = h } else { s.height = abs(h) }
                    replace(ed, id, with: s)
                    ed.print("Height changed to \(fmt(h)).")
                    return
                }
                if let l = loop(ed.doc, id) { profile = l; source = id }
            }
            if profile == nil {
                // Inside the plan outline of a solid: push/pull its top face (the highest one under the point).
                var best: (EntityID, SolidGeom, Double)? = nil
                for e in ed.doc.entities where ed.doc.isEditable(layer: e.layer) {
                    guard case .solid(let s) = e.geometry, let f = FacePushPull.pick(s, at: p, mode: "top") else { continue }
                    let n = f.normal, t = f.triangles[0].0
                    let z = t.z - (n.x * (p.x - t.x) + n.y * (p.y - t.y)) / max(n.z, 1e-9)
                    if z > (best?.2 ?? -.infinity) { best = (e.id, s, z) }
                }
                if let b = best {
                    if b.1.kind == .extrusion || b.1.kind == .box, b.1.history == nil {
                        var s = b.1
                        let cur = s.kind == .box ? s.size.z : s.height
                        guard let h = try await ed.getDistance("Specify new height", defaultValue: cur).value, abs(h) > 1e-9 else { return }
                        if s.kind == .box { s.size.z = h } else { s.height = abs(h) }
                        replace(ed, b.0, with: s)
                        ed.print("Height changed to \(fmt(h)).")
                        return
                    }
                    try await pushPullFace(ed, b.0, b.1, at: p, mode: "top")
                    return
                }
            }
            if profile == nil {
                let curves = ed.doc.entities.filter { ed.doc.isVisible(layer: $0.layer) && $0.props["sectionMark"] == nil }.map(\.geometry)
                guard let r = RegionFinder.region(at: p, curves: curves, doc: ed.doc) else { throw CommandError.invalid("No bounded area found at that point.") }
                profile = r.outerPoints
                holes = r.holes.map { CommandHelpers.loopPoints($0) }
            }
            var prof = profile!
            if GeometryOps.signedArea(prof) < 0 { prof.reverse() }
            let pr = prof
            guard let h = try await ed.getDistance("Specify extrusion height", defaultValue: ed.variableDouble("BOXHEIGHT", 1000),
                                                   preview: { c in [.polyline(PolylineGeom(points: pr, closed: true))] }).value, abs(h) > 1e-9 else { return }
            var s = extrusion(prof, z: z0, height: h)
            for hl in holes where hl.count >= 3 {
                var hp = hl
                if GeometryOps.signedArea(hp) < 0 { hp.reverse() }
                let cut = extrusion(hp, z: (h < 0 ? z0 + h : z0) - abs(h), height: abs(h) * 3)
                if let r = CSG.apply(.subtract, s, cut) { s = r }
            }
            ed.addEntity(.solid(s))
            if let src = source, ed.variableDouble("DELOBJ", 0) != 0 { ed.doc.remove(ids: [src]) }
            ed.print("Solid created: volume " + volumeText(CSG.volume(s), units: ed.doc.units) + (holes.isEmpty ? "" : " (\(holes.count) hole(s))") + ".")
        },
        CommandDef("LOFT", category: "3D", summary: "Creates a solid through closed cross-sections at given heights (in selection order).") { ed in
            ed.selection = []
            var profiles: [(EntityID, [Vec2])] = []
            while true {
                guard case .pick(let pk) = try await ed.pickObject("Select cross-section \(profiles.count + 1) (Enter when done)", filter: { loop(ed.doc, $0) != nil }) else { break }
                if profiles.contains(where: { $0.0 == pk.id }) { continue }
                profiles.append((pk.id, loop(ed.doc, pk.id)!))
            }
            guard profiles.count >= 2 else { throw CommandError.invalid("Select at least two cross-sections.") }
            var z = ed.variableDouble("ELEVATION", 0)
            var heights: [Double] = []
            for (i, p) in profiles.enumerated() {
                if let e = ed.doc.entity(p.0)?.props["elevation"].flatMap(Double.init) { heights.append(e); z = e; continue }
                let def = i == 0 ? z : z + 1000
                guard let v = try await ed.getDistance("Specify height of cross-section \(i + 1)", defaultValue: def).value else { return }
                heights.append(v); z = v
            }
            guard zip(heights, heights.dropFirst()).allSatisfy({ abs($0.1 - $0.0) > 1e-9 }) else { throw CommandError.invalid("Consecutive cross-sections need different heights.") }
            let count = min(256, max(24, profiles.map { $0.1.count }.max()! * 4))
            var rings = zip(profiles, heights).map { p, h in SweepMesh.resample(p.1, count: count).map { Vec3($0.x, $0.y, h) } }
            if heights[1] < heights[0] { rings = rings.map { $0.reversed() } }
            var acc = MeshAcc()
            SweepMesh.loft(rings, into: &acc)
            guard !acc.mesh.isEmpty else { throw CommandError.invalid("Loft failed.") }
            var s = MeshTools.solid(from: MeshTools.triangles(acc.mesh), tolerance: 1e-6)
            // Associative loft: regenerates when a cross-section is edited (unless the sections are deleted).
            if ed.variableDouble("DELOBJ", 0) == 0 && ed.doc.variable("SWEEPASSOC") != "0" {
                s = AssociativeSolids.attach(s, source: SolidSource(kind: .loft, profiles: profiles.map(\.0), heights: heights), doc: ed.doc)
            }
            ed.addEntity(.solid(s))
            if ed.variableDouble("DELOBJ", 0) != 0 { ed.doc.remove(ids: Set(profiles.map(\.0))) }
            ed.print("Loft created through \(profiles.count) sections: volume " + volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        },
        CommandDef("SWEEP", category: "3D", summary: "Sweeps closed profiles along a path (profile X to the left of travel, Y up).") { ed in
            let ids = try await ed.getEntitySelection("Select closed profiles to sweep")
            let profs = ids.compactMap { id in loop(ed.doc, id).map { (id, $0) } }
            guard !profs.isEmpty else { throw CommandError.invalid("No closed profiles selected.") }
            ed.selection = []
            guard case .pick(let pk) = try await ed.pickObject("Select sweep path", filter: { path(ed.doc, $0) != nil && !profs.map(\.0).contains($0) }),
                  let pth = path(ed.doc, pk.id) else { return }
            var twist = 0.0, scale = 1.0
            var z = ed.variableDouble("ELEVATION", 0)
            while true {
                let r = try await ed.getDistance("Specify path elevation" + (twist != 0 || scale != 1 ? " (twist \(fmt(twist * 180 / .pi))°, end scale \(fmt(scale)))" : ""), defaultValue: z, keywords: ["Twist", "Scale"])
                switch r {
                case .keyword("Twist"): twist = try await ed.getAngle("Specify total twist angle", defaultValue: twist).value ?? twist
                case .keyword("Scale"):
                    let s = try await ed.getReal("Specify end scale factor", defaultValue: scale).value ?? scale
                    if s > 0 { scale = s } else { ed.print("The scale must be positive.") }
                case .value(let v): z = v
                default: break
                }
                if case .keyword = r { continue }
                break
            }
            var n = 0
            let assoc = ed.variableDouble("DELOBJ", 0) == 0 && ed.doc.variable("SWEEPASSOC") != "0"
            for (pid, p) in profs {
                let path3 = pth.points.map { Vec3($0.x, $0.y, z) }
                var made: SolidGeom?
                if twist != 0 || scale != 1 {
                    let c = GeometryOps.centroid(p)
                    let m = SurfaceTools.twistedSweep(p.map { $0 - c }, along: path3, twist: twist, endScale: scale, closedPath: pth.closed)
                    if !m.isEmpty { made = MeshTools.solid(from: MeshTools.triangles(m), tolerance: 1e-6) }
                } else { made = sweepSolid(p, path: path3, closedPath: pth.closed) }
                guard var s = made else { continue }
                // Associative sweep: remembers its profile and path and regenerates when they change (SWEEPASSOC = 0 turns it off).
                if assoc { s = AssociativeSolids.attach(s, source: SolidSource(kind: .sweep, profiles: [pid], path: pk.id, elevation: z, twist: twist, endScale: scale), doc: ed.doc) }
                ed.addEntity(.solid(s)); n += 1
            }
            if ed.variableDouble("DELOBJ", 0) != 0 { ed.doc.remove(ids: Set(profs.map(\.0))) }
            ed.print("\(n) swept solid(s) created.")
        },
        CommandDef("PIPE", aliases: ["TUBE"], category: "3D", summary: "Creates a round pipe (optionally hollow) along a path.") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select pipe path", filter: { path(ed.doc, $0) != nil }), let pth = path(ed.doc, pk.id) else { return }
            let r = try await ed.getPositive("Specify outer radius", defaultValue: ed.variableDouble("PIPERADIUS", 50))
            let wall = try await ed.getPositive("Specify wall thickness (0 = solid)", defaultValue: 0, allowZero: true)
            let z = try await ed.getDistance("Specify path elevation", defaultValue: ed.variableDouble("ELEVATION", 0)).value ?? 0
            ed.doc.setVariable("PIPERADIUS", fmt(r))
            let path3 = pth.points.map { Vec3($0.x, $0.y, z) }
            guard var s = pipeSolid(path3, closed: pth.closed, radius: r, wall: wall) else { throw CommandError.invalid("Path too short.") }
            // Associative pipe: follows its path when it is edited (SWEEPASSOC = 0 turns it off).
            if ed.doc.variable("SWEEPASSOC") != "0" {
                s = AssociativeSolids.attach(s, source: SolidSource(kind: .pipe, profiles: [], path: pk.id, elevation: z, heights: [r, wall]), doc: ed.doc)
            }
            ed.addEntity(.solid(s))
            ed.print("Pipe created: volume " + volumeText(CSG.volume(s), units: ed.doc.units) + ".")
        },
    ] }

    /// Round pipe (optionally hollow, open ends) along a 3D path.
    static func pipeSolid(_ path3: [Vec3], closed: Bool, radius r: Double, wall: Double) -> SolidGeom? {
        guard r > 0, path3.count >= 2 else { return nil }
        let n = max(16, min(64, GeometryOps.segments(radius: r, sweep: 2 * .pi)))
        func circle(_ rr: Double) -> [Vec2] { (0..<n).map { Vec2.polar(rr, 2 * .pi * Double($0) / Double(n)) } }
        guard var s = sweepSolid(circle(r), path: path3, closedPath: closed) else { return nil }
        if wall > 0 && wall < r, let inner = sweepSolid(circle(r - wall), path: path3, closedPath: closed) {
            if closed { if let h = CSG.apply(.subtract, s, inner) { s = h } }
            else {
                // Open pipe: extend the bore beyond both ends so the ends are open.
                let a = path3[0], b = path3[1], c = path3[path3.count - 1], d = path3[path3.count - 2]
                let ext = [a + (a - b).normalized * r] + path3 + [c + (c - d).normalized * r]
                if let bore = sweepSolid(circle(r - wall), path: ext, closedPath: false), let h = CSG.apply(.subtract, s, bore) { s = h }
            }
        }
        return s
    }

    // MARK: Site

    static let topoLayer = "C-TOPO"

    static func parseXYZ(_ text: String) -> [Vec3] {
        var out: [Vec3] = []
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\t" }).compactMap { Double($0) }
            // One point per line (extra columns ignored), or several x,y,z triples on one typed line.
            if parts.count >= 6 && parts.count % 3 == 0 && !line.contains("\t") {
                for k in stride(from: 0, to: parts.count, by: 3) { out.append(Vec3(parts[k], parts[k + 1], parts[k + 2])) }
            } else if parts.count >= 3 { out.append(Vec3(parts[0], parts[1], parts[2])) }
        }
        return out
    }

    @MainActor static func addTopo(_ ed: Editor, _ pts: [Vec3], interval: Double) throws -> EntityID {
        guard pts.count >= 3, let s = Terrain.solid(pts) else { throw CommandError.invalid("A toposurface needs at least three points that are not collinear.") }
        if ed.doc.layer(named: topoLayer) == nil { ed.doc.layers.append(Layer(name: topoLayer, color: RGBA(0.55, 0.75, 0.45), lineweight: 0.18, description: "Topography")) }
        let id = ed.doc.add(.solid(s), layer: topoLayer)
        if let i = ed.doc.entityIndex(id) {
            ed.doc.entities[i].props["topo"] = "1"; ed.doc.entities[i].props["material"] = "Grass"
            ed.doc.entities[i].props["contourInterval"] = fmt(interval); ed.doc.entities[i].props["contourMajor"] = "5"
        }
        return id
    }

    static var site: [CommandDef] { [
        CommandDef("TOPO", aliases: ["TOPOSURFACE", "TERRAIN"], category: "Site", summary: "Creates a toposurface from points (with elevations), contour polylines, an XYZ/CSV file or typed x,y,z values.") { ed in
            let k = try await ed.getKeyword("Create from", ["Points", "Contours", "File", "Enter"], defaultValue: "Points") ?? "Points"
            let u = 1 / ed.doc.units.mm
            var pts: [Vec3] = []
            switch k {
            case "Points":
                let ids = try await ed.getEntitySelection("Select points (elevation from the point's elevation/z property, or typed)")
                for id in ids {
                    guard let e = ed.doc.entity(id), case .point(let p) = e.geometry else { continue }
                    var z = (e.props["elevation"] ?? e.props["z"]).flatMap(Double.init)
                    if z == nil { z = try await ed.getDistance("Elevation of point \(fmt(p.x)),\(fmt(p.y))", defaultValue: 0).value }
                    pts.append(Vec3(p.x, p.y, z ?? 0))
                }
            case "Contours":
                let ids = try await ed.getEntitySelection("Select contour lines (elevation from their elevation property, or typed)")
                for id in ids {
                    guard let e = ed.doc.entity(id) else { continue }
                    let lines = GeometryOps.tessellate(e.geometry, doc: ed.doc).filter { $0.count >= 2 }
                    guard !lines.isEmpty else { continue }
                    var z = e.props["elevation"].flatMap(Double.init)
                    if z == nil { z = try await ed.getDistance("Elevation of contour #\(id)", defaultValue: 0).value }
                    // Resample long segments so the triangulation follows the contour.
                    for l in lines {
                        for i in 0..<l.count {
                            pts.append(Vec3(l[i].x, l[i].y, z ?? 0))
                            if i + 1 < l.count {
                                let len = l[i].distance(to: l[i + 1]), step = 2000 * u
                                if len > step { let m = Int(len / step); for j in 1..<(m + 1) { let q = l[i].lerp(l[i + 1], Double(j) / Double(m + 1)); pts.append(Vec3(q.x, q.y, z ?? 0)) } }
                            }
                        }
                    }
                }
            case "File":
                guard let path = try await ed.getString("Enter XYZ/CSV file path") else { return }
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw CommandError.invalid("Cannot read \(path).") }
                pts = parseXYZ(text)
            default:
                while true {
                    guard let s = try await ed.getString("Enter x,y,z (Enter when done)"), !s.isEmpty else { break }
                    let v = parseXYZ(s)
                    if v.isEmpty { ed.print("Enter three numbers.") } else { pts += v }
                }
            }
            let interval = try await ed.getPositive("Specify contour interval", defaultValue: ed.variableDouble("CONTOURINTERVAL", 500 * u))
            ed.doc.setVariable("CONTOURINTERVAL", fmt(interval))
            let id = try addTopo(ed, pts, interval: interval)
            let zs = pts.map(\.z)
            ed.print("Toposurface #\(id) from \(pts.count) points, elevations \(fmt(zs.min() ?? 0)) to \(fmt(zs.max() ?? 0)).")
        },
        CommandDef("CONTOURS", aliases: ["CONTOUR"], category: "Site", summary: "Sets the contour interval and major-line spacing of toposurfaces (0 = hide contours).") { ed in
            let ids = try await selectSolids(ed, "Select toposurfaces").filter { ed.doc.entity($0)?.props["topo"] == "1" }
            guard !ids.isEmpty else { throw CommandError.invalid("No toposurface selected.") }
            let cur = ed.doc.entity(ids[0])?.props["contourInterval"].flatMap(Double.init) ?? 500
            let iv = try await ed.getPositive("Specify contour interval (0 = none)", defaultValue: cur, allowZero: true)
            let major = try await ed.getInteger("Every n-th contour is a major (labelled) line", defaultValue: 5) ?? 5
            for id in ids {
                guard let i = ed.doc.entityIndex(id) else { continue }
                ed.doc.entities[i].props["contourInterval"] = iv > 0 ? fmt(iv) : nil
                ed.doc.entities[i].props["contourMajor"] = "\(max(major, 0))"
            }
            ed.selection = []
            ed.print(iv > 0 ? "Contours every \(fmt(iv)), major every \(major)." : "Contours hidden.")
        },
        CommandDef("BUILDINGPAD", aliases: ["PAD", "SITEPAD"], category: "Site", summary: "Levels a toposurface inside a boundary to a pad elevation (cut and fill).") { ed in
            guard case .pick(let pk) = try await ed.pickObject("Select toposurface", filter: { ed.doc.entity($0)?.props["topo"] == "1" }),
                  let topo = solidOf(ed.doc, pk.id) else { return }
            let a = try await ed.getPoint("Specify first point of pad boundary", keywords: ["Select"])
            var boundary: [Vec2]? = nil
            switch a {
            case .point(let p): boundary = try await ArchitectureCommands.polygonInput(ed, first: p)
            case .keyword: boundary = try await ArchitectureCommands.selectBoundary(ed)
            default: return
            }
            guard var b = boundary, b.count >= 3 else { throw CommandError.invalid("The pad needs a closed boundary.") }
            if GeometryOps.signedArea(b) < 0 { b.reverse() }
            guard let z = try await ed.getDistance("Specify pad elevation", defaultValue: 0).value else { return }
            let box = bounds(topo)
            let above = extrusion(b, z: z, height: box.max.z - z + 1000)
            let fill = extrusion(b, z: box.min.z, height: z - box.min.z)
            let before = CSG.volume(topo)
            var s = topo
            if box.max.z > z, let r = CSG.apply(.subtract, s, above) { s = r }
            if z > box.min.z, let r = CSG.apply(.union, s, CSG.apply(.intersect, fill, SolidGeom(kind: .extrusion, origin: Vec3(0, 0, box.min.z), profile: RG.convexHull(topo.meshVertices.map(\.xy)), height: z - box.min.z + 1)) ?? fill) { s = r }
            replace(ed, pk.id, with: s)
            let after = CSG.volume(s)
            ed.print("Pad at \(fmt(z)): net " + (after >= before ? "fill " : "cut ") + volumeText(abs(after - before), units: ed.doc.units) + ".")
        },
    ] }
}
