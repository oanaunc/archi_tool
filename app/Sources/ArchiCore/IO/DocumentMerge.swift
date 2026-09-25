// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Merges an imported document into an existing one (IMPORT-style commands).
public enum DocumentMerge {
    public struct Result {
        public var entityIDs: [EntityID] = []
        public var elementIDs: [EntityID] = []
        public var addedLevels: [String] = []
        public var allIDs: [EntityID] { entityIDs + elementIDs }
        public init() {}
    }

    /// Copies layers, linetypes, materials, wall types, blocks, levels, entities and BIM elements of `src` into `dst`
    /// with fresh IDs. Levels are matched by name (then by elevation within 1 unit); hosted openings follow their walls.
    /// `offset` moves everything in plan; `scale` converts src units to dst units.
    @discardableResult
    public static func merge(_ src: ArchiDocument, into dst: inout ArchiDocument, offset: Vec2 = .zero, scale: Double = 1) -> Result {
        var res = Result()
        for l in src.layers where dst.layer(named: l.name) == nil { dst.layers.append(l) }
        for lt in src.linetypes where dst.linetype(lt.name) == nil { dst.linetypes.append(lt) }
        for m in src.materials where dst.material(m.name) == nil { dst.materials.append(m) }
        for wt in src.wallTypes where !dst.wallTypes.contains(where: { $0.name == wt.name }) { dst.wallTypes.append(wt) }
        for ts in src.textStyles where !dst.textStyles.contains(where: { $0.name == ts.name }) { dst.textStyles.append(ts) }
        for ds in src.dimStyles where !dst.dimStyles.contains(where: { $0.name == ds.name }) { dst.dimStyles.append(ds) }

        let t = Transform2D.translation(offset) * Transform2D.scale(scale, scale)
        let identity = offset == .zero && abs(scale - 1) < 1e-12
        func map(_ g: Geometry) -> Geometry { identity ? g : GeometryOps.transform(g, t) }

        // Blocks (renamed on conflict).
        var blockName: [String: String] = [:]
        for name in src.blocks.keys.sorted() {
            guard var b = src.blocks[name] else { continue }
            var n = name
            if let existing = dst.blocks[n], existing != b {
                var k = 1
                while dst.blocks["\(name)_\(k)"] != nil { k += 1 }
                n = "\(name)_\(k)"
            }
            blockName[name] = n
            if dst.blocks[n] == nil {
                b.name = n
                if abs(scale - 1) > 1e-12 {
                    let s = Transform2D.scale(scale, scale)
                    b.basePoint = s.apply(b.basePoint)
                    b.entities = b.entities.map { var e = $0; e.geometry = GeometryOps.transform(e.geometry, s); return e }
                }
                b.entities = b.entities.map { var e = $0; e.id = dst.allocateID(); return e }
                dst.blocks[n] = b
            }
        }
        // Rename nested inserts inside copied blocks.
        for (old, new) in blockName where old != new {
            for k in dst.blocks.keys {
                guard var b = dst.blocks[k] else { continue }
                var changed = false
                for i in b.entities.indices { if case .insert(var ins) = b.entities[i].geometry, ins.block == old, blockName.values.contains(k) { ins.block = new; b.entities[i].geometry = .insert(ins); changed = true } }
                if changed { dst.blocks[k] = b }
            }
        }

        // Levels.
        var levelMap: [Int: Int] = [:]
        for lv in src.levels {
            if let m = dst.levels.first(where: { $0.name.caseInsensitiveCompare(lv.name) == .orderedSame }) ?? dst.levels.first(where: { abs($0.elevation - lv.elevation * scale) < 1 }) {
                levelMap[lv.id] = m.id
            } else {
                let nid = (dst.levels.map(\.id).max() ?? -1) + 1
                dst.levels.append(Level(id: nid, name: lv.name, elevation: lv.elevation * scale, height: lv.height * scale))
                dst.levels.sort { $0.elevation < $1.elevation }
                levelMap[lv.id] = nid
                res.addedLevels.append(lv.name)
            }
        }

        for e in src.entities {
            var n = e
            n.id = dst.allocateID()
            n.geometry = map(e.geometry)
            if case .insert(var ins) = n.geometry, let nb = blockName[ins.block] { ins.block = nb; n.geometry = .insert(ins) }
            if case .solid(var s) = n.geometry, !identity {
                s.meshVertices = s.meshVertices.map { v in let q = t.apply(v.xy); return Vec3(q.x, q.y, v.z * scale) }
                if s.kind != .mesh { let q = t.apply(s.origin.xy); s.origin = Vec3(q.x, q.y, s.origin.z * scale) }
                n.geometry = .solid(s)
            }
            dst.ensureLayer(n.layer)
            dst.entities.append(n)
            res.entityIDs.append(n.id)
        }

        var idMap: [EntityID: EntityID] = [:]
        for el in src.elements { idMap[el.id] = dst.allocateID() }
        for el in src.elements {
            var n = el
            n.id = idMap[el.id]!
            n.level = levelMap[el.level] ?? dst.currentLevel
            n.geometry = transform(el.geometry, t, scale: scale, identity: identity)
            if case .opening(var o) = n.geometry {
                guard let h = idMap[o.hostWall] else { continue }
                o.hostWall = h; n.geometry = .opening(o)
            }
            dst.ensureLayer(n.layer)
            dst.elements.append(n)
            res.elementIDs.append(n.id)
        }
        return res
    }

    /// Moves/scales a BIM geometry in plan (heights scale too).
    static func transform(_ g: BIMGeometry, _ t: Transform2D, scale s: Double, identity: Bool) -> BIMGeometry {
        guard !identity else { return g }
        let P = t.apply
        switch g {
        case .wall(var w): w.start = P(w.start); w.end = P(w.end); w.thickness *= s; w.height *= s; w.baseOffset *= s; return .wall(w)
        case .slab(var sl): sl.boundary = sl.boundary.map(P); sl.holes = sl.holes.map { $0.map(P) }; sl.thickness *= s; sl.topOffset *= s; sl.slopeOrigin = sl.slopeOrigin.map(P); return .slab(sl)
        case .column(var c): c.position = P(c.position); c.width *= s; c.depth *= s; c.height *= s; c.baseOffset *= s; return .column(c)
        case .beam(var b): b.start = P(b.start); b.end = P(b.end); b.width *= s; b.depth *= s; b.topOffset *= s; return .beam(b)
        case .opening(var o): o.offset *= s; o.width *= s; o.height *= s; o.sill *= s; o.frameWidth *= s; o.depth *= s; return .opening(o)
        case .roof(var r): r.boundary = r.boundary.map(P); r.thickness *= s; r.overhang *= s; r.baseOffset *= s; return .roof(r)
        case .stair(var st): st.start = P(st.start); st.width *= s; st.totalRise *= s; st.treadDepth *= s; return .stair(st)
        case .railing(var r): r.path = r.path.map(P); r.height *= s; r.baseOffset *= s; return .railing(r)
        case .space(var sp): sp.boundary = sp.boundary.map(P); sp.height *= s; return .space(sp)
        case .curtainWall(var c): c.start = P(c.start); c.end = P(c.end); c.height *= s; c.baseOffset *= s; c.gridU *= s; c.gridV *= s; c.mullionSize *= s
            c.uLines = c.uLines?.map { $0 * s }; c.vLines = c.vLines?.map { $0 * s }; return .curtainWall(c)
        case .component(var c): c.position = P(c.position); c.size = c.size * s; c.baseOffset *= s; return .component(c)
        case .gridLine(var gl): gl.start = P(gl.start); gl.end = P(gl.end); return .gridLine(gl)
        }
    }
}
