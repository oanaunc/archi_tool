// Oanarina Archi Tool — GPL-3.0-or-later
// Point cloud commands: POINTCLOUDVIEW (section-box clipping and octree level-of-detail thinning of the displayed
// points), PCPLANE (snap to the nearest scan point and fit the local plane), SCANTOBIM (RANSAC planes → walls and slabs).
import Foundation

public enum PointCloudCommands {
    public static var all: [CommandDef] { [view, plane, scanToBIM] }
    public static let hiddenLayer = "POINTCLOUD-HIDDEN"

    /// Point entities of clouds (points with a "z" prop), on any layer.
    static func cloud(_ doc: ArchiDocument) -> [(index: Int, p: Vec3)] {
        doc.entities.enumerated().compactMap { i, e in
            guard case .point(let p) = e.geometry, let z = e.props["z"].flatMap(Double.init) else { return nil }
            return (i, Vec3(p.x, p.y, z))
        }
    }

    static var view: CommandDef {
        CommandDef("POINTCLOUDVIEW", aliases: ["PCVIEW", "POINTCLOUDCLIP", "PCCLIP"], category: "Insert",
                   summary: "Point cloud display: Clip to a section box (min/max corners with Z range), Density (octree level of detail: keep at most N points shown, evenly over the cloud), Reset (show all). Hidden points move to layer POINTCLOUD-HIDDEN.") { ed in
            let k = try await ed.getKeyword("Enter an option [Clip/Density/Reset]", ["Clip", "Density", "Reset"], defaultValue: "Clip") ?? "Clip"
            var d = ed.doc
            if d.layer(named: hiddenLayer) == nil { var l = Layer(name: hiddenLayer); l.visible = false; d.layers.append(l) }
            // Every cloud point back to its original layer first.
            for i in d.entities.indices where d.entities[i].layer == hiddenLayer { d.entities[i].layer = d.entities[i].props["pcLayer"] ?? "POINTCLOUD"; d.entities[i].props["pcLayer"] = nil }
            let pts = cloud(d)
            guard !pts.isEmpty else { throw CommandError.invalid("No point cloud in the drawing (IMPORTFILE a .las, .xyz, .pts or .ply).") }
            var keep = Set<Int>()
            switch k {
            case "Reset":
                ed.doc = d; ed.print("All \(pts.count) points shown."); return
            case "Clip":
                let a = try await ed.requirePoint("Specify first corner of the section box")
                let b = try await ed.requirePoint("Specify opposite corner", base: a, preview: { p in [.polyline(PolylineGeom(points: [a, Vec2(p.x, a.y), p, Vec2(a.x, p.y)], closed: true))] })
                let zs = pts.map(\.p.z)
                let z0 = try await ed.getReal("Bottom of the box (Z)", defaultValue: zs.min() ?? 0).value ?? (zs.min() ?? 0)
                let z1 = try await ed.getReal("Top of the box (Z)", defaultValue: zs.max() ?? 0).value ?? (zs.max() ?? 0)
                let box = BBox3(min: Vec3(min(a.x, b.x), min(a.y, b.y), min(z0, z1)), max: Vec3(max(a.x, b.x), max(a.y, b.y), max(z0, z1)))
                let oct = PointOctree(points: pts.map(\.p))
                keep = Set(oct.points(in: box))
                d.setVariable("POINTCLOUDCLIP", "\(fmt(box.min.x, 3)),\(fmt(box.min.y, 3)),\(fmt(box.min.z, 3)),\(fmt(box.max.x, 3)),\(fmt(box.max.y, 3)),\(fmt(box.max.z, 3))")
            default:
                let n = try await ed.getInteger("Maximum points to show <\(min(pts.count, 50_000))>", defaultValue: min(pts.count, 50_000)) ?? 50_000
                guard n > 0 else { throw CommandError.invalid("The budget must be positive.") }
                keep = Set(PointOctree(points: pts.map(\.p)).lod(budget: n))
            }
            var hidden = 0
            for (j, item) in pts.enumerated() where !keep.contains(j) {
                d.entities[item.index].props["pcLayer"] = d.entities[item.index].layer
                d.entities[item.index].layer = hiddenLayer
                hidden += 1
            }
            ed.doc = d
            ed.print("\(pts.count - hidden) of \(pts.count) points shown.")
        }
    }

    static var plane: CommandDef {
        CommandDef("PCPLANE", aliases: ["POINTCLOUDSNAP", "SCANPLANE", "PCSNAP"], category: "Insert",
                   summary: "Snaps to the scan point nearest a picked location and fits the plane through its neighbours: reports the point, normal, slope and fit error; a vertical plane is drawn as a line along its trace in plan.") { ed in
            let pts = cloud(ed.doc)
            guard !pts.isEmpty else { throw CommandError.invalid("No point cloud in the drawing.") }
            let oct = PointOctree(points: pts.map(\.p))
            let p = try await ed.requirePoint("Pick near a scanned surface")
            guard let hit = oct.nearest(to: Vec3(p.x, p.y, 0), planOnly: true) else { return }
            let q = pts[hit.index].p
            let r = try await ed.getDistance("Neighbourhood radius", base: p, defaultValue: 300).value ?? 300
            let nb = oct.neighbours(q, radius: r)
            guard let pl = PlaneFit.fit(nb.map { pts[$0].p }) else { throw CommandError.invalid("Not enough points around (\(nb.count)).") }
            let slope = acos(min(1, abs(pl.normal.z))) * 180 / .pi
            ed.print("Snapped to (\(fmt(q.x, 2)), \(fmt(q.y, 2)), \(fmt(q.z, 2))); plane from \(nb.count) points: normal (\(fmt(pl.normal.x, 3)), \(fmt(pl.normal.y, 3)), \(fmt(pl.normal.z, 3))), \(fmt(slope, 1))° from horizontal, RMS \(fmt(pl.rms, 2)).")
            if pl.isVertical {
                let dir = Vec2(-pl.normal.y, pl.normal.x).normalized
                let ts = nb.map { (pts[$0].p.xy - pl.centroid.xy).dot(dir) }
                let a = pl.centroid.xy + dir * (ts.min() ?? -r), b = pl.centroid.xy + dir * (ts.max() ?? r)
                let id = ed.doc.add(.line(LineGeom(a, b)), layer: "PC-PLANES")
                ed.selection = [id]
            }
        }
    }

    static var scanToBIM: CommandDef {
        CommandDef("SCANTOBIM", aliases: ["PCFITWALLS", "PLANEFIT", "SCANFIT"], category: "Architecture",
                   summary: "Detects planes in the point cloud (RANSAC) and creates walls from vertical planes and floor slabs from horizontal planes.") { ed in
            let (pts, _) = ScanToBIM.cloudPoints(ed.doc)
            let cloudPts = cloud(ed.doc).map(\.p)
            let all = cloudPts.isEmpty ? pts : cloudPts
            guard all.count >= 20 else { throw CommandError.invalid("Too few scan points (\(all.count)).") }
            let unit = ed.doc.units.mm
            let tol = try await ed.getDistance("Plane tolerance", defaultValue: 20 / unit).value ?? 20 / unit
            let minIn = try await ed.getInteger("Minimum points per plane <\(max(20, all.count / 50))>", defaultValue: max(20, all.count / 50)) ?? 20
            let t = try await ed.getDistance("Wall thickness", defaultValue: 200 / unit).value ?? 200 / unit
            // Work on at most 30 000 points (octree LOD keeps them spread out).
            let sample = all.count > 30_000 ? PointOctree(points: all).lod(budget: 30_000).map { all[$0] } : all
            let r = ScanToBIM.fit(sample, tolerance: tol, minInliers: minIn, wallThickness: t)
            var ids: [EntityID] = []
            let lvElev = ed.doc.level(ed.doc.currentLevel)?.elevation ?? 0
            for w in r.walls {
                var g = w; g.baseOffset -= lvElev
                ids.append(ed.doc.addElement(.wall(g), name: "Scanned wall"))
            }
            for s in r.slabs {
                ids.append(ed.doc.addElement(.slab(SlabGeom(boundary: s.boundary, thickness: t, topOffset: s.elevation - lvElev)), name: "Scanned floor"))
            }
            ed.selection = Set(ids)
            ed.print("\(r.planes) plane(s) found: \(r.walls.count) wall(s), \(r.slabs.count) slab(s) created.")
        }
    }
}
