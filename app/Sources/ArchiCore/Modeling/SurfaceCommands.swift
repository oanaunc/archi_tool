// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Mesh surface commands (REVSURF, TABSURF, RULESURF, EDGESURF) and mesh repair / decimation.
enum SurfaceCommands {
    static var all: [CommandDef] { surfaces + meshTools }

    /// 3D points of a curve entity (its "elevation" property gives Z).
    static func curve(_ doc: ArchiDocument, _ id: EntityID) -> (points: [Vec3], closed: Bool)? {
        guard let p = ModelingCommands.path(doc, id) else { return nil }
        let z = doc.entity(id)?.props["elevation"].flatMap(Double.init) ?? 0
        return (p.points.map { Vec3($0.x, $0.y, z) }, p.closed)
    }

    @MainActor static func pickCurve(_ ed: Editor, _ msg: String, excluding: Set<EntityID> = []) async throws -> (EntityID, [Vec3], Bool)? {
        guard case .pick(let pk) = try await ed.pickObject(msg, filter: { curve(ed.doc, $0) != nil && !excluding.contains($0) }), let c = curve(ed.doc, pk.id) else { return nil }
        return (pk.id, c.points, c.closed)
    }

    @MainActor static func addSurface(_ ed: Editor, _ r: (vertices: [Vec3], triangles: [Int]), what: String) throws {
        guard !r.triangles.isEmpty else { throw CommandError.invalid("The \(what) surface is empty.") }
        var b = BBox3.empty
        r.vertices.forEach { b.add($0) }
        let s = SolidGeom(kind: .mesh, origin: b.min, meshVertices: r.vertices, meshTriangles: r.triangles)
        let id = ed.addEntity(.solid(s))
        if let i = ed.doc.entityIndex(id) { ed.doc.entities[i].props["surface"] = what }
        ed.print("\(what) created: \(r.triangles.count / 3) faces, area " + String(format: "%.3f", SurfaceTools.area(r) * pow(ed.doc.units.mm, 2) / 1e6) + " m².")
    }

    static var surfaces: [CommandDef] { [
        CommandDef("REVSURF", aliases: ["REVOLVEDSURFACE"], category: "3D", summary: "Revolved mesh surface: rotates a path curve about an axis line (start angle, included angle; SURFTAB1 segments).") { ed in
            guard let (pid, prof, _) = try await pickCurve(ed, "Select object to revolve") else { return }
            guard case .pick(let ax) = try await ed.pickObject("Select object that defines the axis of revolution", filter: { id in
                if id == pid { return false }; if case .line? = ed.doc.entity(id)?.geometry { return true }; if case .polyline? = ed.doc.entity(id)?.geometry { return true }; return false }),
                  let axis = curve(ed.doc, ax.id), axis.points.count >= 2 else { return }
            let a = axis.points.first!, b = axis.points.last!
            let start = try await ed.getAngle("Specify start angle", defaultValue: 0).value ?? 0
            let sweep = try await ed.getAngle("Specify included angle (+ = ccw, − = cw)", defaultValue: 2 * .pi).value ?? 2 * .pi
            let n = Int(ed.variableDouble("SURFTAB1", 32))
            try addSurface(ed, SurfaceTools.revolve(prof, axisFrom: a, to: b, start: start, sweep: abs(sweep) < 1e-9 ? 2 * .pi : sweep, segments: max(3, n)), what: "Revolved surface")
        },
        CommandDef("TABSURF", aliases: ["TABULATEDSURFACE"], category: "3D", summary: "Tabulated mesh surface: sweeps a path curve along a direction vector (a line) or straight up by a height.") { ed in
            guard let (pid, path, _) = try await pickCurve(ed, "Select object for path curve") else { return }
            let r = try await ed.pickObject("Select object for direction vector", keywords: ["Height"], filter: { id in
                if id == pid { return false }; if case .line? = ed.doc.entity(id)?.geometry { return true }; return false })
            var v = Vec3(0, 0, 0)
            switch r {
            case .keyword("Height"): v = Vec3(0, 0, try await ed.getDistance("Specify height", defaultValue: 1000).value ?? 1000)
            case .pick(let pk):
                guard case .line(let l)? = ed.doc.entity(pk.id)?.geometry else { return }
                // The vector points away from the end nearest the pick point.
                let (p0, p1) = pk.point.distance(to: l.a) <= pk.point.distance(to: l.b) ? (l.a, l.b) : (l.b, l.a)
                v = Vec3(p1.x - p0.x, p1.y - p0.y, 0)
            default: return
            }
            try addSurface(ed, SurfaceTools.tabulate(path, vector: v), what: "Tabulated surface")
        },
        CommandDef("RULESURF", aliases: ["RULEDSURFACE"], category: "3D", summary: "Ruled mesh surface between two curves (SURFTAB1 rulings).") { ed in
            guard let (a, pa, ca) = try await pickCurve(ed, "Select first defining curve") else { return }
            guard let (_, pb, cb) = try await pickCurve(ed, "Select second defining curve", excluding: [a]) else { return }
            guard ca == cb else { throw CommandError.invalid("Both curves must be open or both closed.") }
            let n = Int(ed.variableDouble("SURFTAB1", 32))
            try addSurface(ed, SurfaceTools.ruled(pa, pb, count: max(2, n), closed: ca), what: "Ruled surface")
        },
        CommandDef("EDGESURF", aliases: ["EDGESURFACE", "COONS"], category: "3D", summary: "Coons patch mesh bounded by four edge curves that touch end to end (SURFTAB1 × SURFTAB2).") { ed in
            var ids = Set<EntityID>(), curves: [[Vec3]] = []
            for i in 1...4 {
                guard let (id, p, _) = try await pickCurve(ed, "Select object \(i) for surface edge", excluding: ids) else { return }
                ids.insert(id); curves.append(p)
            }
            let m = Int(ed.variableDouble("SURFTAB1", 16)), n = Int(ed.variableDouble("SURFTAB2", 16))
            let tol = max(1e-3, 1 / ed.doc.units.mm)
            guard let r = SurfaceTools.coons(curves, m: max(2, m), n: max(2, n), tolerance: tol) else { throw CommandError.invalid("The four edges must touch end to end to form a closed loop.") }
            try addSurface(ed, r, what: "Edge surface")
        },
    ] }

    static var meshTools: [CommandDef] { [
        CommandDef("MESHREPAIR", aliases: ["REPAIRMESH", "FIXMESH", "MESHCLEAN"], category: "3D", summary: "Repairs meshes/solids: welds vertices, removes degenerate and duplicate faces, fixes orientation, fills holes.") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select meshes or solids to repair")
            guard !ids.isEmpty else { return }
            let tol = try await ed.getPositive("Specify weld tolerance", defaultValue: ed.variableDouble("MESHWELDTOL", 0.01))
            let fill = try await ed.getYesNo("Fill holes?", defaultValue: true)
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                let (v, t): ([Vec3], [Int])
                if s.kind == .mesh { (v, t) = (s.meshVertices, s.meshTriangles) } else { let w = MeshTools.weld(MeshTools.triangles(MeshTools.mesh(of: s)), tolerance: 1e-9); (v, t) = (w.vertices, w.triangles) }
                let r = MeshTools.repair(vertices: v, triangles: t, tolerance: tol, fillHoles: fill)
                var b = BBox3.empty
                r.vertices.forEach { b.add($0) }
                ModelingCommands.replace(ed, id, with: SolidGeom(kind: .mesh, origin: b.isEmpty ? s.origin : b.min, meshVertices: r.vertices, meshTriangles: r.triangles))
                ed.print("#\(id): " + r.report.description + (SolidOps.isClosedManifold(vertices: r.vertices, triangles: r.triangles) ? "; closed." : "; still open."))
            }
            ed.doc.setVariable("MESHWELDTOL", fmt(tol))
        },
        CommandDef("MESHDECIMATE", aliases: ["DECIMATE", "MESHREDUCE", "SIMPLIFYMESH"], category: "3D", summary: "Reduces the triangle count of meshes/solids to a percentage (vertex clustering).") { ed in
            let ids = try await ModelingCommands.selectSolids(ed, "Select meshes or solids to decimate")
            guard !ids.isEmpty else { return }
            let pct = try await ed.getReal("Specify target percentage of triangles to keep", defaultValue: ed.variableDouble("DECIMATEPCT", 50)).value ?? 50
            guard pct > 0, pct < 100 else { throw CommandError.invalid("Enter a percentage between 0 and 100.") }
            for id in ids {
                guard let s = ModelingCommands.solidOf(ed.doc, id) else { continue }
                let w = s.kind == .mesh ? (s.meshVertices, s.meshTriangles) : { let x = MeshTools.weld(MeshTools.triangles(MeshTools.mesh(of: s)), tolerance: 1e-9); return (x.vertices, x.triangles) }()
                let r = MeshTools.decimate(vertices: w.0, triangles: w.1, ratio: pct / 100)
                ModelingCommands.replace(ed, id, with: SolidGeom(kind: .mesh, origin: s.origin, meshVertices: r.vertices, meshTriangles: r.triangles))
                ed.print("#\(id): \(w.1.count / 3) → \(r.triangles.count / 3) triangles.")
            }
            ed.doc.setVariable("DECIMATEPCT", fmt(pct))
        },
    ] }
}

extension SurfaceTools {
    /// Surface area of an indexed mesh.
    public static func area(_ r: (vertices: [Vec3], triangles: [Int])) -> Double {
        var a = 0.0, i = 0
        while i + 2 < r.triangles.count {
            let p = r.vertices[r.triangles[i]], q = r.vertices[r.triangles[i + 1]], s = r.vertices[r.triangles[i + 2]]
            a += (q - p).cross(s - p).length / 2; i += 3
        }
        return a
    }
}
