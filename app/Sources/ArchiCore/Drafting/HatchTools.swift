// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Hatch services: associative hatches that follow their boundary objects, separating multi-area hatches, recreating
/// boundaries.
///
/// An associative hatch carries props:
/// - "hatchBoundary": comma-separated IDs of the boundary objects;
/// - "hatchAssoc": "pick" (area found around an internal point) or "select" (closed objects selected as loops);
/// - "hatchSeed": for "pick", the internal point as fractions "u,v" of the boundary objects' bounding box;
/// - "hatchSig": fingerprint of the boundary geometry at the last update (the hatch is rebuilt when it changes).
public enum AssociativeHatch {
    public static let boundaryProp = "hatchBoundary", modeProp = "hatchAssoc", seedProp = "hatchSeed", sigProp = "hatchSig"

    static func ids(_ e: Entity) -> [EntityID] {
        (e.props[boundaryProp] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
    public static func isAssociative(_ e: Entity) -> Bool { e.props[boundaryProp] != nil }

    /// Stable fingerprint (FNV-1a) of the boundary objects' geometry.
    static func signature(_ ids: [EntityID], doc: ArchiDocument) -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        var h: UInt64 = 0xcbf29ce484222325
        for id in ids {
            let bytes = doc.entity(id).flatMap { try? enc.encode($0.geometry) } ?? Data("missing\(id)".utf8)
            for b in bytes { h ^= UInt64(b); h = h &* 0x100000001b3 }
        }
        return String(h, radix: 16)
    }
    static func bounds(_ ids: [EntityID], doc: ArchiDocument) -> BBox2 {
        var b = BBox2.empty
        for id in ids { if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) } }
        return b
    }

    /// Objects whose curves carry the given loops (every loop point within `tol` of the object), searched among `candidates`.
    public static func boundaryObjects(of loops: [[PolyVertex]], candidates: [Entity], doc: ArchiDocument) -> [EntityID] {
        var pts: [Vec2] = []
        for l in loops { pts += CommandHelpers.loopPoints(l) }
        guard !pts.isEmpty else { return [] }
        var box = BBox2.empty; pts.forEach { box.add($0) }
        let tol = max(box.width, box.height, 1) * 1e-6
        var out: [EntityID] = []
        for e in candidates {
            switch e.geometry { case .text, .dimension, .insert, .table, .image, .solid, .point, .hatch: continue; default: break }
            let eb = GeometryOps.bounds(e.geometry, doc: doc)
            guard !eb.isEmpty, eb.intersects(box.expanded(by: tol)) else { continue }
            if pts.contains(where: { GeometryOps.distance(from: $0, to: e.geometry, doc: doc) <= tol }) { out.append(e.id) }
        }
        return out
    }

    /// Makes a hatch associative to boundary objects.
    public static func attach(_ doc: inout ArchiDocument, hatch: EntityID, boundary: [EntityID], seed: Vec2?) {
        guard let i = doc.entityIndex(hatch), !boundary.isEmpty else { return }
        var p = doc.entities[i].props
        p[boundaryProp] = boundary.map(String.init).joined(separator: ",")
        p[modeProp] = seed == nil ? "select" : "pick"
        if let s = seed {
            let b = bounds(boundary, doc: doc)
            let u = b.width > 0 ? (s.x - b.min.x) / b.width : 0.5, v = b.height > 0 ? (s.y - b.min.y) / b.height : 0.5
            p[seedProp] = "\(fmt(u, 10)),\(fmt(v, 10))"
        } else { p[seedProp] = nil }
        p[sigProp] = signature(boundary, doc: doc)
        doc.entities[i].props = p
    }
    public static func detach(_ e: inout Entity) {
        for k in [boundaryProp, modeProp, seedProp, sigProp] { e.props[k] = nil }
    }

    static func sortLoops(_ loops: [[PolyVertex]]) -> [[PolyVertex]] {
        loops.sorted { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0))) > abs(GeometryOps.signedArea(CommandHelpers.loopPoints($1))) }
    }

    /// A point inside the hatch's first area (inside its outer loop, outside its holes).
    static func interiorPoint(_ h: HatchGeom) -> Vec2? {
        guard let outer = h.loops.first else { return nil }
        let op = CommandHelpers.loopPoints(outer)
        guard op.count >= 3 else { return nil }
        let holes = h.loops.dropFirst().map(CommandHelpers.loopPoints)
        func ok(_ p: Vec2) -> Bool { GeometryOps.pointInPolygon(p, op) && !holes.contains { GeometryOps.pointInPolygon(p, $0) } }
        let c = GeometryOps.centroid(op)
        if ok(c) { return c }
        let b = BBox2(points: op)
        for k in 1...12 {
            let n = 2 * k
            for i in 0..<n { for j in 0..<n {
                let p = Vec2(b.min.x + b.width * (Double(i) + 0.5) / Double(n), b.min.y + b.height * (Double(j) + 0.5) / Double(n))
                if ok(p) { return p }
            } }
        }
        return nil
    }

    /// Rebuilds the loops of an associative hatch from its boundary. Returns nil when unchanged; `.some(nil)` when the boundary
    /// was lost (the hatch keeps its shape and loses associativity).
    static func recompute(_ e: Entity, doc: ArchiDocument) -> HatchGeom?? {
        guard case .hatch(let h) = e.geometry else { return nil }
        let bids = ids(e).filter { doc.entity($0) != nil }
        guard !bids.isEmpty else { return .some(nil) }
        var loops: [[PolyVertex]] = []
        if e.props[modeProp] == "select" {
            loops = bids.compactMap { doc.entity($0).flatMap { CommandHelpers.closedLoop($0.geometry) } }
            if loops.isEmpty { loops = Modify.join(bids.compactMap { doc.entity($0)?.geometry }).compactMap { CommandHelpers.closedLoop($0) } }
            loops = sortLoops(loops)
        } else {
            let curves = bids.compactMap { doc.entity($0)?.geometry }
            var seeds: [Vec2] = []
            if let s = e.props[seedProp]?.split(separator: ","), s.count == 2, let u = Double(s[0]), let v = Double(s[1]) {
                let b = bounds(bids, doc: doc)
                if !b.isEmpty { seeds.append(Vec2(b.min.x + u * b.width, b.min.y + v * b.height)) }
            }
            if let ip = interiorPoint(h) { seeds.append(ip) }
            for s in seeds { if let r = RegionFinder.region(at: s, curves: curves, doc: doc) { loops = [r.outer] + r.holes; break } }
        }
        guard !loops.isEmpty else { return .some(nil) }
        var nh = h; nh.loops = loops
        return nh == h ? nil : .some(nh)
    }

    /// Updates every associative hatch whose boundary changed (DocumentUpdaters). Returns true if the document changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices where doc.entities[i].props[boundaryProp] != nil {
            let e = doc.entities[i]
            let bids = ids(e)
            let sig = signature(bids, doc: doc)
            guard sig != e.props[sigProp] else { continue }
            switch recompute(e, doc: doc) {
            case .none: break
            case .some(.none): detach(&doc.entities[i])
            case .some(.some(let nh)): doc.entities[i].geometry = .hatch(nh)
            }
            if doc.entities[i].props[boundaryProp] != nil {
                // Forget boundary objects that were erased.
                let alive = bids.filter { doc.entity($0) != nil }
                if alive.count != bids.count { doc.entities[i].props[boundaryProp] = alive.map(String.init).joined(separator: ",") }
                doc.entities[i].props[sigProp] = signature(alive, doc: doc)
            }
            changed = true
        }
        return changed
    }
}

public enum HatchTools {
    /// Splits a hatch into one hatch per separate area (each outer loop with the holes directly inside it).
    public static func separate(_ h: HatchGeom) -> [HatchGeom] {
        let pts = h.loops.map(CommandHelpers.loopPoints)
        guard h.loops.count > 1 else { return [h] }
        let areas = pts.map { abs(GeometryOps.signedArea($0)) }
        // Parent = smallest loop containing this loop.
        var parent = [Int?](repeating: nil, count: pts.count)
        for i in pts.indices {
            guard let probe = pts[i].first else { continue }
            var best: Int? = nil
            for j in pts.indices where j != i && areas[j] > areas[i] && pts[j].count >= 3 && GeometryOps.pointInPolygon(probe, pts[j]) {
                if best == nil || areas[j] < areas[best!] { best = j }
            }
            parent[i] = best
        }
        func depth(_ i: Int) -> Int { var d = 0, k = parent[i]; while let p = k, d < 64 { d += 1; k = parent[p] }; return d }
        var out: [HatchGeom] = []
        for i in pts.indices where depth(i) % 2 == 0 {
            var g = h
            g.loops = [h.loops[i]] + pts.indices.filter { parent[$0] == i }.map { h.loops[$0] }
            out.append(g)
        }
        return out.sorted { abs(GeometryOps.signedArea(CommandHelpers.loopPoints($0.loops[0]))) > abs(GeometryOps.signedArea(CommandHelpers.loopPoints($1.loops[0]))) }
    }

    /// Closed polylines along every loop of a hatch (HATCHGENERATEBOUNDARY).
    public static func boundaryPolylines(_ h: HatchGeom) -> [PolylineGeom] {
        h.loops.filter { $0.count >= 2 }.map { PolylineGeom($0, closed: true) }
    }
}
