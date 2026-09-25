// Oanarina Archi Tool — GPL-3.0-or-later
// Model groups (Revit "model groups", furniture/room groups): a named definition of building elements placed as
// repeated instances. Instance elements carry props group = name, groupInstance = n, groupX/groupY/groupRot; editing
// one instance and running MODELGROUP Update pushes the change to the definition and every other instance.
import Foundation

public struct ModelGroup: Codable, Hashable {
    public var name: String
    /// Elements relative to the group origin (hosted openings reference hosts by their index in `elements`, as −(index+1)).
    public var elements: [BIMElement]
    public init(name: String, elements: [BIMElement]) { self.name = name; self.elements = elements }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), elements: try c.decodeIfPresent([BIMElement].self, forKey: .elements) ?? [])
    }
}

public enum ModelGroups {
    static let keys = ["group", "groupInstance", "groupX", "groupY", "groupRot"]

    /// Instance members: instance number → element ids.
    public static func instances(_ name: String, doc: ArchiDocument) -> [Int: [EntityID]] {
        var out: [Int: [EntityID]] = [:]
        for el in doc.elements where el.props["group"]?.caseInsensitiveCompare(name) == .orderedSame {
            out[el.props["groupInstance"].flatMap(Int.init) ?? 0, default: []].append(el.id)
        }
        return out
    }

    static func placement(_ el: BIMElement) -> (Vec2, Double) {
        (Vec2(el.props["groupX"].flatMap(Double.init) ?? 0, el.props["groupY"].flatMap(Double.init) ?? 0), el.props["groupRot"].flatMap(Double.init) ?? 0)
    }

    /// Definition elements from world elements placed at `origin`/`rotation` (inverse transform, ids made local).
    static func definition(from els: [BIMElement], origin: Vec2, rotation: Double) -> [BIMElement] {
        let inv = Transform2D.rotation(-rotation) * Transform2D.translation(-origin)
        let index = Dictionary(els.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return els.map { el in
            var e = el
            e.geometry = CommandHelpers.transform(el.geometry, inv)
            if case .opening(var o) = e.geometry, let hi = index[o.hostWall] { o.hostWall = -(hi + 1); e.geometry = .opening(o) }
            for k in keys { e.props[k] = nil }
            e.id = 0
            return e
        }
    }

    /// Creates a group from elements (openings hosted by walls outside the selection are left out). Tags them as instance 1.
    @discardableResult
    public static func create(_ name: String, ids: [EntityID], origin: Vec2, doc: inout ArchiDocument) -> Int {
        var els = ids.compactMap { doc.element($0) }
        let set = Set(els.map(\.id))
        // Include openings of grouped walls; drop openings whose host is not in the group.
        for el in doc.elements where !set.contains(el.id) { if case .opening(let o) = el.geometry, set.contains(o.hostWall) { els.append(el) } }
        let hostSet = Set(els.map(\.id))
        els = els.filter { if case .opening(let o) = $0.geometry { return hostSet.contains(o.hostWall) }; return true }
        guard !els.isEmpty else { return 0 }
        let def = ModelGroup(name: name, elements: definition(from: els, origin: origin, rotation: 0))
        if let i = doc.modelGroups.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { doc.modelGroups[i] = def } else { doc.modelGroups.append(def) }
        for el in els {
            guard let i = doc.elementIndex(el.id) else { continue }
            doc.elements[i].props["group"] = name; doc.elements[i].props["groupInstance"] = "1"
            doc.elements[i].props["groupX"] = fmt(origin.x, 9); doc.elements[i].props["groupY"] = fmt(origin.y, 9); doc.elements[i].props["groupRot"] = "0"
        }
        return els.count
    }

    /// Places an instance of a group. Returns the new element ids.
    @discardableResult
    public static func place(_ name: String, at p: Vec2, rotation: Double = 0, level: Int? = nil, instance: Int? = nil, doc: inout ArchiDocument) -> [EntityID] {
        guard let def = doc.modelGroups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return [] }
        let n = instance ?? ((instances(def.name, doc: doc).keys.max() ?? 0) + 1)
        let t = Transform2D.translation(p) * Transform2D.rotation(rotation)
        var newIDs: [EntityID] = []
        for d in def.elements {
            var e = d
            e.id = doc.allocateID()
            e.geometry = CommandHelpers.transform(d.geometry, t)
            if case .opening(var o) = e.geometry, o.hostWall < 0 {
                let k = -o.hostWall - 1
                guard k < newIDs.count else { continue }
                o.hostWall = newIDs[k]; e.geometry = .opening(o)
            }
            if let l = level { e.level = l }
            e.props["group"] = def.name; e.props["groupInstance"] = "\(n)"
            e.props["groupX"] = fmt(p.x, 9); e.props["groupY"] = fmt(p.y, 9); e.props["groupRot"] = fmt(rotation, 12)
            doc.ensureLayer(e.layer)
            doc.elements.append(e)
            newIDs.append(e.id)
        }
        return newIDs
    }

    /// Redefines a group from one edited instance and rebuilds every other instance. Returns the number of instances updated.
    @discardableResult
    public static func update(fromInstanceOf id: EntityID, doc: inout ArchiDocument) -> Int {
        guard let el = doc.element(id), let name = el.props["group"], let inst = el.props["groupInstance"].flatMap(Int.init) else { return 0 }
        let all = instances(name, doc: doc)
        guard let mine = all[inst] else { return 0 }
        let els = mine.compactMap { doc.element($0) }
        let (o, r) = placement(el)
        guard let gi = doc.modelGroups.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return 0 }
        doc.modelGroups[gi].elements = definition(from: els, origin: o, rotation: r)
        var n = 0
        for (k, ids) in all where k != inst {
            guard let first = ids.first.flatMap({ doc.element($0) }) else { continue }
            let (p, rot) = placement(first)
            let level = first.level
            doc.remove(ids: Set(ids))
            place(name, at: p, rotation: rot, level: level, instance: k, doc: &doc)
            n += 1
        }
        return n
    }

    /// Detaches an instance (its elements become ordinary elements).
    public static func ungroup(instanceOf id: EntityID, doc: inout ArchiDocument) -> Int {
        guard let el = doc.element(id), let name = el.props["group"], let inst = el.props["groupInstance"].flatMap(Int.init), let ids = instances(name, doc: doc)[inst] else { return 0 }
        for i in ids { if let k = doc.elementIndex(i) { for key in keys { doc.elements[k].props[key] = nil } } }
        return ids.count
    }
}
