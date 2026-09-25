// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Associative arrays (MOD-030/031/032/033): the items live in a generated block "ARRAY$n" shown by one block reference
/// whose props keep the array parameters ("arrayParams", JSON) and the source objects ("arraySource", JSON). ARRAYEDIT
/// changes the parameters and the block is rebuilt; a path array follows its path when the path is edited; EXPLODE turns
/// the array back into separate objects.
public struct ArrayParams: Codable, Equatable {
    public enum Kind: String, Codable { case rect, polar, path }
    public var kind: Kind
    // Rectangular
    public var rows = 1, columns = 1
    public var rowSpacing = 0.0, columnSpacing = 0.0
    /// Rectangular array axis angle (radians).
    public var angle = 0.0
    // Polar / path
    public var count = 1
    public var center = Vec2.zero
    public var fill = 2 * Double.pi
    public var rotateItems = true
    /// Base point of the source objects (polar without rotation, path arrays).
    public var base = Vec2.zero
    public var path: EntityID?
    public var align = true
    /// Path arrays: signature of the path geometry the array was built for (rebuilt when it changes).
    public var pathSignature: String?

    public init(kind: Kind) { self.kind = kind }

    enum K: String, CodingKey { case kind, rows, columns, rowSpacing, columnSpacing, angle, count, center, fill, rotateItems, base, path, align, pathSignature }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 1
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 1
        rowSpacing = try c.decodeIfPresent(Double.self, forKey: .rowSpacing) ?? 0
        columnSpacing = try c.decodeIfPresent(Double.self, forKey: .columnSpacing) ?? 0
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        center = try c.decodeIfPresent(Vec2.self, forKey: .center) ?? .zero
        fill = try c.decodeIfPresent(Double.self, forKey: .fill) ?? 2 * .pi
        rotateItems = try c.decodeIfPresent(Bool.self, forKey: .rotateItems) ?? true
        base = try c.decodeIfPresent(Vec2.self, forKey: .base) ?? .zero
        path = try c.decodeIfPresent(EntityID.self, forKey: .path)
        align = try c.decodeIfPresent(Bool.self, forKey: .align) ?? true
        pathSignature = try c.decodeIfPresent(String.self, forKey: .pathSignature)
    }

    public var itemCount: Int { kind == .rect ? rows * columns : count }
}

public enum AssocArray {
    public static let paramsProp = "arrayParams", sourceProp = "arraySource"

    /// Whether new arrays are associative (ARRAYASSOCIATIVITY, default on).
    public static func enabled(_ doc: ArchiDocument) -> Bool { doc.variable("ARRAYASSOCIATIVITY") != "0" }

    static func signature(_ g: Geometry) -> String {
        DynamicBlocks.hash(String(describing: g))
    }

    /// Item transforms (the first is the source position for rectangular and polar arrays).
    public static func transforms(_ p: ArrayParams, doc: ArchiDocument) -> [Transform2D] {
        switch p.kind {
        case .rect:
            let u = Vec2.polar(1, p.angle), v = u.perp
            var out: [Transform2D] = []
            for r in 0..<max(1, p.rows) { for c in 0..<max(1, p.columns) {
                out.append(.translation(u * (Double(c) * p.columnSpacing) + v * (Double(r) * p.rowSpacing)))
            } }
            return out
        case .polar:
            let n = max(1, p.count)
            guard n > 1 else { return [.identity] }
            let full = abs(abs(p.fill) - 2 * .pi) < 1e-9
            let step = full ? p.fill / Double(n) : p.fill / Double(n - 1)
            return (0..<n).map { k in
                let a = step * Double(k)
                return p.rotateItems ? .rotation(a, around: p.center) : .translation(p.base.rotated(by: a, around: p.center) - p.base)
            }
        case .path:
            guard let pid = p.path, let path = doc.entity(pid), let pl = GeometryOps.tessellate(path.geometry, doc: doc).first, pl.count > 1 else { return [.identity] }
            let n = max(1, p.count)
            let total = CommandHelpers.polylineLength(pl)
            let closed = CommandHelpers.closedLoop(path.geometry) != nil
            let (_, t0) = CommandHelpers.pointAt(pl, distance: 0)
            return (0..<n).map { k in
                let s = n == 1 ? 0 : (closed ? total * Double(k) / Double(n) : total * Double(k) / Double(n - 1))
                let (pt, t) = CommandHelpers.pointAt(pl, distance: s)
                return p.align ? Transform2D.translation(pt) * Transform2D.rotation(t.angle - t0.angle) * Transform2D.translation(-p.base)
                               : Transform2D.translation(pt - p.base)
            }
        }
    }

    /// Expanded items of a source set.
    public static func items(_ source: [Entity], _ p: ArrayParams, doc: ArchiDocument) -> [Entity] {
        var out: [Entity] = []
        for (k, t) in transforms(p, doc: doc).enumerated() {
            for e in source {
                var c = e
                c.geometry = GeometryOps.transform(e.geometry, t)
                DraftProps.transform(&c.props, t)
                c.props["arrItem"] = "\(k)"
                out.append(c)
            }
        }
        return out
    }

    public static func params(_ e: Entity) -> ArrayParams? {
        guard let s = e.props[paramsProp], let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ArrayParams.self, from: d)
    }
    public static func source(_ e: Entity) -> [Entity] {
        guard let s = e.props[sourceProp], let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Entity].self, from: d)) ?? []
    }
    static func json<T: Encodable>(_ v: T) -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func isArray(_ e: Entity?) -> Bool { e?.props[paramsProp] != nil }

    /// Creates an associative array from drawing entities (they are replaced by the array). Returns the array's ID.
    @discardableResult
    public static func create(_ ids: [EntityID], _ params: ArrayParams, _ doc: inout ArchiDocument) -> EntityID? {
        let src = ids.compactMap { doc.entity($0) }
        guard !src.isEmpty else { return nil }
        var p = params
        if p.kind == .path, let pid = p.path, let g = doc.entity(pid)?.geometry { p.pathSignature = signature(g) }
        var n = 1
        while doc.blocks["ARRAY$\(n)"] != nil { n += 1 }
        let name = "ARRAY$\(n)"
        doc.blocks[name] = Block(name: name, basePoint: .zero, entities: items(src, p, doc: doc), description: "Associative \(p.kind.rawValue) array")
        doc.remove(ids: Set(src.map(\.id)))
        var e = Entity(layer: src[0].layer, geometry: .insert(InsertGeom(block: name, position: .zero, scale: Vec2(1, 1), rotation: 0, attributes: [:])))
        e.props[paramsProp] = json(p)
        e.props[sourceProp] = json(src)
        return doc.add(e)
    }

    /// Replaces an array's parameters and rebuilds its items (source objects are kept relative to the array's placement).
    @discardableResult
    public static func update(_ id: EntityID, _ params: ArrayParams, _ doc: inout ArchiDocument) -> Bool {
        guard let i = doc.entityIndex(id), case .insert(let ins) = doc.entities[i].geometry, isArray(doc.entities[i]) else { return false }
        var p = params
        if p.kind == .path, let pid = p.path, let g = doc.entity(pid)?.geometry { p.pathSignature = signature(g) }
        let src = source(doc.entities[i])
        // Items are built in block coordinates; the reference's own transform places them.
        let inv = ins.transform.inverted
        var local = p
        if p.kind == .path {
            // Path arrays follow the path in world coordinates: keep the reference at identity.
            doc.entities[i].geometry = .insert(InsertGeom(block: ins.block, position: .zero, scale: Vec2(1, 1), rotation: 0, attributes: ins.attributes))
            let srcWorld = src.map { e -> Entity in var c = e; c.geometry = GeometryOps.transform(e.geometry, ins.transform); return c }
            doc.blocks[ins.block] = Block(name: ins.block, basePoint: .zero, entities: items(srcWorld, local, doc: doc), description: "Associative path array")
            doc.entities[i].props[sourceProp] = json(srcWorld)
        } else {
            local.center = inv.apply(p.center)
            doc.blocks[ins.block] = Block(name: ins.block, basePoint: .zero, entities: items(src, local, doc: doc), description: "Associative \(p.kind.rawValue) array")
        }
        doc.entities[i].props[paramsProp] = json(p)
        return true
    }

    /// Rebuilds path arrays whose path changed (DocumentUpdaters). Returns true if the document changed.
    @discardableResult
    public static func updateAll(_ doc: inout ArchiDocument) -> Bool {
        var changed = false
        for i in doc.entities.indices {
            guard doc.entities[i].props[paramsProp] != nil, let p = params(doc.entities[i]), p.kind == .path,
                  let pid = p.path, let g = doc.entity(pid)?.geometry, signature(g) != p.pathSignature else { continue }
            if update(doc.entities[i].id, p, &doc) { changed = true }
        }
        return changed
    }
}
