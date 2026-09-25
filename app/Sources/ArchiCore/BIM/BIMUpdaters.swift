// Oanarina Archi Tool — GPL-3.0-or-later
// Associative BIM content regenerated from the model: automatic wall/grid dimensions, area-scheme boundaries,
// associative sweeps and solid feature histories. `BIMUpdaters.run` is the single entry point (call it after edits,
// e.g. from DocumentUpdaters); the plan/3D builders also apply it to what they draw so views are never stale.
import Foundation

public enum BIMUpdaters {
    /// Regenerates every associative BIM object. Returns true if the document changed.
    @discardableResult
    public static func run(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        if AreaSchemes.updateAll(&doc) { changed = true }
        if AutoDimensions.updateAll(&doc) { changed = true }
        if AssociativeSolids.updateAll(&doc) { changed = true }
        if FamilyInstances.updateAll(&doc) { changed = true }
        return changed
    }

    /// True when the document holds associative content (fast path for the view builders).
    public static func hasAssociative(_ doc: ArchiDocument) -> Bool {
        doc.elements.contains { $0.props["areaAuto"] == "1" }
            || doc.entities.contains { e in
                if case .solid(let s) = e.geometry { return s.source != nil }
                return e.props["autoDimSet"] != nil || e.props["autoDimGrids"] != nil
            }
            || !doc.families.isEmpty
    }

    private static let lock = NSLock()
    private static var cached: (input: ArchiDocument, output: ArchiDocument)?

    /// The document with associative content regenerated (memoised on the input; unchanged documents return as is).
    public static func regenerated(_ doc: ArchiDocument) -> ArchiDocument {
        guard hasAssociative(doc) else { return doc }
        lock.lock()
        if let c = cached, c.input == doc { lock.unlock(); return c.output }
        lock.unlock()
        var d = doc
        run(&d)
        lock.lock(); cached = (doc, d); lock.unlock()
        return d
    }
}

// MARK: - Associative automatic dimensions

/// Dimension strings created by AUTODIMWALLS / AUTODIMGRIDS keep their source ids in props and are rebuilt when the
/// walls, openings or grids move: autoDimSet = wall ids of the chain set, autoDim = wall, autoDimIdx = index in the
/// wall's chain, autoDimOffset, autoDimOpenings; autoDimGrids = grid ids, autoDimIdx, autoDimOffset.
public enum AutoDimensions {
    static func ids(_ s: String?) -> [EntityID] {
        (s ?? "").split(separator: ";").first.map { $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } } ?? []
    }

    /// Tags a chain set's dimensions for associativity.
    public static func tagWallChains(_ chains: [AutoDimension.Chain], set: [EntityID], offset: Double, openings: Bool) -> [(Geometry, [String: String])] {
        var out: [(Geometry, [String: String])] = []
        // The key identifies one chain set (same walls, offset and options) so repeated runs stay independent.
        let key = set.map(String.init).joined(separator: ",") + ";\(fmt(offset, 6));\(openings ? 1 : 0)"
        for c in chains {
            for (k, d) in c.dims.enumerated() {
                out.append((.dimension(d), ["autoDim": "\(c.wall)", "autoDimSet": key, "autoDimIdx": "\(k)", "autoDimOffset": fmt(offset, 6), "autoDimOpenings": openings ? "1" : "0"]))
            }
        }
        return out
    }

    /// Dimension chain across parallel grid lines: one dimension between each neighbouring pair and an overall one.
    public static func gridChain(doc: ArchiDocument, grids ids: [EntityID], offset: Double) -> [DimensionGeom] {
        let gs = ids.compactMap { id -> GridLineGeom? in if case .gridLine(let g)? = doc.element(id)?.geometry, g.start.distance(to: g.end) > 1e-9 { return g }; return nil }
        guard gs.count >= 2 else { return [] }
        let d = (gs[0].end - gs[0].start).normalized
        let n = d.perp
        let parallel = gs.filter { abs(($0.end - $0.start).normalized.cross(d)) < 0.02 }
        guard parallel.count >= 2 else { return [] }
        // Dimension line beyond the grid heads (the start end), offset outwards.
        let sorted = parallel.sorted { $0.start.dot(n) < $1.start.dot(n) }
        let headS = sorted.map { ($0.start - sorted[0].start).dot(d) }.min() ?? 0
        let base = sorted[0].start + d * headS
        func P(_ g: GridLineGeom) -> Vec2 {
            let t = (g.start - base).dot(n)
            return base + n * t
        }
        var out: [DimensionGeom] = []
        for i in 0..<(sorted.count - 1) {
            let a = P(sorted[i]), b = P(sorted[i + 1])
            guard a.distance(to: b) > 1e-9 else { continue }
            out.append(DimensionGeom(kind: .aligned, points: [a, b, (a + b) / 2 - d * offset]))
        }
        if sorted.count > 2 {
            let a = P(sorted[0]), b = P(sorted[sorted.count - 1])
            out.append(DimensionGeom(kind: .aligned, points: [a, b, (a + b) / 2 - d * (offset * 2)]))
        }
        return out
    }

    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var groups: [String: [Int]] = [:], gridGroups: [String: [Int]] = [:]
        for (i, e) in doc.entities.enumerated() {
            guard case .dimension = e.geometry else { continue }
            if let s = e.props["autoDimSet"] { groups[s, default: []].append(i) }
            else if let s = e.props["autoDimGrids"] { gridGroups[s, default: []].append(i) }
        }
        guard !groups.isEmpty || !gridGroups.isEmpty else { return false }
        let snap = doc
        var changed = false
        var remove = Set<EntityID>()
        var additions: [Entity] = []
        for (key, idxs) in groups {
            let set = ids(key).filter { if case .wall? = snap.element($0)?.geometry { return true }; return false }
            let first = snap.entities[idxs[0]]
            let off = first.props["autoDimOffset"].flatMap(Double.init) ?? 800 / snap.units.mm
            let withOpenings = first.props["autoDimOpenings"] != "0"
            let chains = set.isEmpty ? [] : AutoDimension.wallChains(doc: snap, walls: set, offset: off, openings: withOpenings)
            var byWall: [EntityID: [DimensionGeom]] = [:]
            for c in chains { byWall[c.wall] = c.dims }
            var seen: [EntityID: Set<Int>] = [:]
            for i in idxs {
                let e = snap.entities[i]
                guard let w = e.props["autoDim"].flatMap(Int.init), let k = e.props["autoDimIdx"].flatMap(Int.init), case .dimension(let cur) = e.geometry else { continue }
                guard let dims = byWall[w], k < dims.count else { remove.insert(e.id); changed = true; continue }
                seen[w, default: []].insert(k)
                var nd = dims[k]; nd.style = cur.style; nd.textOverride = cur.textOverride
                if nd != cur { doc.entities[i].geometry = .dimension(nd); changed = true }
            }
            // New segments (an opening was added): new dimensions like the first one of the set.
            for (w, dims) in byWall {
                for (k, d) in dims.enumerated() where !(seen[w]?.contains(k) ?? false) {
                    var e = first
                    var nd = d
                    if case .dimension(let cur) = first.geometry { nd.style = cur.style }
                    e.geometry = .dimension(nd)
                    e.props["autoDim"] = "\(w)"; e.props["autoDimIdx"] = "\(k)"
                    additions.append(e); changed = true
                }
            }
        }
        for (key, idxs) in gridGroups {
            let first = snap.entities[idxs[0]]
            let off = first.props["autoDimOffset"].flatMap(Double.init) ?? 1500 / snap.units.mm
            let dims = gridChain(doc: snap, grids: ids(key), offset: off)
            var seen = Set<Int>()
            for i in idxs {
                let e = snap.entities[i]
                guard let k = e.props["autoDimIdx"].flatMap(Int.init), case .dimension(let cur) = e.geometry else { continue }
                guard k < dims.count else { remove.insert(e.id); changed = true; continue }
                seen.insert(k)
                var nd = dims[k]; nd.style = cur.style; nd.textOverride = cur.textOverride
                if nd != cur { doc.entities[i].geometry = .dimension(nd); changed = true }
            }
            for (k, d) in dims.enumerated() where !seen.contains(k) {
                var e = first; var nd = d
                if case .dimension(let cur) = first.geometry { nd.style = cur.style }
                e.geometry = .dimension(nd); e.props["autoDimIdx"] = "\(k)"
                additions.append(e); changed = true
            }
        }
        if !remove.isEmpty { doc.entities.removeAll { remove.contains($0.id) } }
        for e in additions { doc.add(e) }
        return changed
    }
}
