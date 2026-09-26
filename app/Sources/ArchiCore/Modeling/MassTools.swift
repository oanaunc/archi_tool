// Oanarina Archi Tool — GPL-3.0-or-later
// Conceptual masses (M3D-096/097/098, BIM-027): any closed solid used as a mass gives mass floors (its plan section at
// every level), and building elements by face: walls along the mass faces on every storey, floor slabs and a roof.
import Foundation

public enum MassTools {
    /// Plan section of a triangle mesh at height z: closed loops, outer CCW and holes CW (collinear points removed).
    public static func section(_ tris: [(Vec3, Vec3, Vec3)], z: Double) -> [[Vec2]] {
        var segs: [(Vec2, Vec2)] = []
        for t in tris {
            let v = [t.0, t.1, t.2]
            var pts: [Vec2] = []
            for k in 0..<3 {
                let a = v[k], b = v[(k + 1) % 3]
                if (a.z - z) * (b.z - z) < 0 { let f = (z - a.z) / (b.z - a.z); pts.append(Vec2(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)) }
            }
            if pts.count == 2, pts[0].distance(to: pts[1]) > 1e-9 { segs.append((pts[0], pts[1])) }
        }
        guard !segs.isEmpty else { return [] }
        var box = BBox2.empty
        for s in segs { box.add(s.0); box.add(s.1) }
        let q = max(box.width, box.height, 1e-6) * 1e-8
        func key(_ p: Vec2) -> [Int64] { [Int64((p.x / q).rounded()), Int64((p.y / q).rounded())] }
        var adj: [[Int64]: [Int]] = [:]
        for (i, s) in segs.enumerated() { adj[key(s.0), default: []].append(i); adj[key(s.1), default: []].append(i) }
        var used = [Bool](repeating: false, count: segs.count)
        var loops: [[Vec2]] = []
        for start in segs.indices where !used[start] {
            used[start] = true
            var chain = [segs[start].0, segs[start].1]
            while true {
                let k = key(chain[chain.count - 1])
                guard let n = adj[k]?.first(where: { !used[$0] }) else { break }
                used[n] = true
                chain.append(key(segs[n].0) == k ? segs[n].1 : segs[n].0)
            }
            if chain.count >= 4, key(chain[0]) == key(chain[chain.count - 1]) {
                chain.removeLast()
                let s = CommandHelpers.simplify(chain)
                if s.count >= 3, abs(GeometryOps.signedArea(s)) > 1e-6 { loops.append(s) }
            }
        }
        return PolygonBoolean.normalize(loops)
    }

    static func triangles(_ s: SolidGeom) -> [(Vec3, Vec3, Vec3)] { MeshTools.triangles(MeshTools.mesh(of: s)) }

    /// Vertical extent of a solid.
    public static func zRange(_ s: SolidGeom) -> (Double, Double)? {
        let zs = MeshTools.mesh(of: s).positions.map(\.z)
        guard let a = zs.min(), let b = zs.max(), b - a > 1e-9 else { return nil }
        return (a, b)
    }

    /// Mass floors (M3D-097): for every level whose elevation lies within the mass, the plan section just above it,
    /// as (level id, regions (outer + holes), gross area in drawing units²).
    public static func floors(_ s: SolidGeom, levels: [Level]) -> [(level: Int, regions: [(outer: [Vec2], holes: [[Vec2]])], area: Double)] {
        guard let (z0, z1) = zRange(s) else { return [] }
        let tris = triangles(s)
        let eps = max((z1 - z0) * 1e-6, 1e-6)
        var out: [(level: Int, regions: [(outer: [Vec2], holes: [[Vec2]])], area: Double)] = []
        for l in levels.sorted(by: { $0.elevation < $1.elevation }) where l.elevation >= z0 - eps && l.elevation < z1 - eps {
            let loops = section(tris, z: max(l.elevation, z0) + eps * 10)
            let outers = loops.filter { GeometryOps.signedArea($0) > 0 }
            let holes = loops.filter { GeometryOps.signedArea($0) < 0 }
            let regions = outers.map { o in (outer: o, holes: holes.filter { GeometryOps.pointInPolygon($0[0], o) }) }
            let area = loops.reduce(0) { $0 + GeometryOps.signedArea($1) }
            if !regions.isEmpty { out.append((l.id, regions, area)) }
        }
        return out
    }

    public struct Conversion { public var walls: [EntityID] = []; public var slabs: [EntityID] = []; public var roofs: [EntityID] = [] }

    /// Building elements by face (M3D-098, BIM-027): on every storey the mass occupies, walls along the section edges
    /// (outer face on the mass face), a floor slab per region, and a flat roof over the top section.
    @discardableResult
    public static func convert(_ s: SolidGeom, massID: EntityID?, doc: inout ArchiDocument, wallThickness th: Double, slabThickness st: Double,
                               walls makeWalls: Bool = true, slabs makeSlabs: Bool = true, roof makeRoof: Bool = true) -> Conversion {
        var r = Conversion()
        guard let (z0, z1) = zRange(s) else { return r }
        let levels = doc.levels.sorted { $0.elevation < $1.elevation }
        let fl = floors(s, levels: levels)
        func tag(_ id: EntityID) { if let m = massID, let i = doc.elementIndex(id) { doc.elements[i].props["fromMass"] = "\(m)" } }
        for f in fl {
            guard let lv = doc.level(f.level) else { continue }
            let next = levels.first { $0.elevation > lv.elevation + 1e-6 }
            let top = min(next?.elevation ?? (lv.elevation + lv.height), z1)
            let h = top - max(lv.elevation, z0)
            let base = max(lv.elevation, z0) - lv.elevation
            if makeSlabs {
                for reg in f.regions {
                    let id = doc.addElement(.slab(SlabGeom(boundary: reg.outer, holes: reg.holes.map { Array($0.reversed()) }, thickness: st, topOffset: base)), level: lv.id, name: "Mass Floor")
                    tag(id); r.slabs.append(id)
                }
            }
            if makeWalls, h > 1e-6 {
                for reg in f.regions {
                    for loop in [reg.outer] + reg.holes {
                        var ids: [EntityID] = []
                        for i in loop.indices {
                            let a = loop[i], b = loop[(i + 1) % loop.count]
                            guard a.distance(to: b) > 1e-6 else { continue }
                            let id = doc.addElement(.wall(WallGeom(start: a, end: b, thickness: th, height: h, baseOffset: base, justification: .right)), level: lv.id)
                            tag(id); ids.append(id)
                        }
                        for (k, id) in ids.enumerated() {
                            guard let j = doc.elementIndex(id) else { continue }
                            doc.elements[j].props["joinEnd"] = "\(ids[(k + 1) % ids.count])"; doc.elements[j].props["joinStart"] = "\(ids[(k + ids.count - 1) % ids.count])"
                        }
                        r.walls += ids
                    }
                }
            }
        }
        if makeRoof {
            let eps = max((z1 - z0) * 1e-6, 1e-6)
            let loops = section(triangles(s), z: z1 - eps * 10)
            let lv = levels.last { $0.elevation <= z1 - eps } ?? levels.first
            if let lv = lv {
                for o in loops where GeometryOps.signedArea(o) > 0 {
                    let id = doc.addElement(.roof(RoofGeom(boundary: o, kind: .flat, pitch: 0, thickness: st, overhang: 0, baseOffset: z1 - lv.elevation - st)), level: lv.id, name: "Mass Roof")
                    tag(id); r.roofs.append(id)
                }
            }
        }
        return r
    }
}
