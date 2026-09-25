// Oanarina Archi Tool — GPL-3.0-or-later
// Spatial index (SYS-015): a static R-tree packed with the Sort-Tile-Recursive algorithm (Leutenegger, Lopez & Edgington
// 1997) over the plan bounding boxes of drawing objects and building elements. Window queries (viewport culling, crossing
// selection), point picks with tolerance and nearest-object search run in O(log n + k) instead of scanning every object.
import Foundation

public struct SpatialIndex {
    public struct Item: Hashable {
        public var id: EntityID
        public var box: BBox2
        public init(id: EntityID, box: BBox2) { self.id = id; self.box = box }
    }
    struct Node { var box: BBox2; var start: Int; var count: Int; var leaf: Bool }

    public private(set) var items: [Item] = []
    var nodes: [Node] = []
    var root = -1
    public let nodeCapacity: Int
    public var count: Int { items.count }
    public var bounds: BBox2 { root >= 0 ? nodes[root].box : .empty }
    /// Height of the tree (1 = only leaves).
    public private(set) var depth = 0

    public init(items: [Item], nodeCapacity: Int = 16) {
        self.nodeCapacity = max(2, nodeCapacity)
        self.items = items.filter { !$0.box.isEmpty && $0.box.min.x.isFinite && $0.box.max.y.isFinite }
        build()
    }

    /// Index of a document's drawing objects (all, or those on visible layers) and building elements (optionally of one level).
    public init(doc: ArchiDocument, level: Int? = nil, includeElements: Bool = true, visibleLayersOnly: Bool = false, nodeCapacity: Int = 16) {
        var list: [Item] = []
        list.reserveCapacity(doc.entities.count + doc.elements.count)
        let hidden = visibleLayersOnly ? Set(doc.layers.filter { !$0.visible || $0.frozen }.map { $0.name.lowercased() }) : []
        for e in doc.entities where hidden.isEmpty || !hidden.contains(e.layer.lowercased()) {
            list.append(Item(id: e.id, box: GeometryOps.bounds(e.geometry, doc: doc)))
        }
        if includeElements {
            for el in doc.elements where level == nil || el.level == level! {
                list.append(Item(id: el.id, box: PlanRepresentation.bounds(el, doc: doc)))
            }
        }
        self.init(items: list, nodeCapacity: nodeCapacity)
    }

    mutating func build() {
        nodes = []; root = -1; depth = 0
        guard !items.isEmpty else { return }
        let m = nodeCapacity
        // Leaves: sort-tile the items.
        items = SpatialIndex.tile(items, capacity: m, box: { $0.box })
        var level: [Int] = []
        var i = 0
        while i < items.count {
            let n = min(m, items.count - i)
            var b = BBox2.empty
            for k in i..<(i + n) { b.add(items[k].box) }
            nodes.append(Node(box: b, start: i, count: n, leaf: true))
            level.append(nodes.count - 1)
            i += n
        }
        depth = 1
        // Upper levels: tile the nodes of the level below; children of a parent are stored contiguously.
        while level.count > 1 {
            let tiled = SpatialIndex.tile(level, capacity: m, box: { nodes[$0].box })
            // Copy children to a contiguous run so a parent can refer to them by range.
            var next: [Int] = []
            var j = 0
            while j < tiled.count {
                let n = min(m, tiled.count - j)
                let first = nodes.count
                var b = BBox2.empty
                for k in j..<(j + n) { let c = nodes[tiled[k]]; nodes.append(c); b.add(c.box) }
                nodes.append(Node(box: b, start: first, count: n, leaf: false))
                next.append(nodes.count - 1)
                j += n
            }
            level = next
            depth += 1
        }
        root = level[0]
    }

    /// Sort-Tile-Recursive ordering: sort by centre x, cut into √(n/m) vertical slices, sort each slice by centre y.
    static func tile<T>(_ list: [T], capacity m: Int, box: (T) -> BBox2) -> [T] {
        let n = list.count
        guard n > m else { return list }
        let leaves = (n + m - 1) / m
        let slices = Int(ceil(sqrt(Double(leaves))))
        let perSlice = slices * m
        let byX = list.map { ($0, box($0).center) }.sorted { $0.1.x < $1.1.x }
        var out: [T] = []
        out.reserveCapacity(n)
        var s = 0
        while s < n {
            let e = min(n, s + perSlice)
            out.append(contentsOf: byX[s..<e].sorted { $0.1.y < $1.1.y }.map(\.0))
            s = e
        }
        return out
    }

    /// Ids whose boxes intersect `box` (window / crossing candidates, viewport culling).
    public func query(_ box: BBox2) -> [EntityID] {
        var out: [EntityID] = []
        visit(box) { out.append($0.id) }
        return out
    }

    /// Calls `body` for every item whose box intersects `box`.
    public func visit(_ box: BBox2, _ body: (Item) -> Void) {
        guard root >= 0, !box.isEmpty else { return }
        var stack = [root]
        while let n = stack.popLast() {
            let node = nodes[n]
            guard node.box.intersects(box) else { continue }
            if node.leaf {
                for k in node.start..<(node.start + node.count) where items[k].box.intersects(box) { body(items[k]) }
            } else {
                for k in node.start..<(node.start + node.count) { stack.append(k) }
            }
        }
    }

    /// Ids whose boxes lie completely inside `box` (window selection candidates).
    public func contained(in box: BBox2) -> [EntityID] {
        var out: [EntityID] = []
        visit(box) { if box.contains($0.box) { out.append($0.id) } }
        return out
    }

    /// Ids whose boxes are within `tolerance` of a point (pick candidates).
    public func query(point p: Vec2, tolerance: Double) -> [EntityID] {
        query(BBox2(min: p - Vec2(tolerance, tolerance), max: p + Vec2(tolerance, tolerance)))
    }

    static func boxDistance(_ p: Vec2, _ b: BBox2) -> Double {
        let dx = max(b.min.x - p.x, 0, p.x - b.max.x), dy = max(b.min.y - p.y, 0, p.y - b.max.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The `k` nearest items by exact distance (`distance` for an item, default: distance to its box), best-first search.
    public func nearest(to p: Vec2, k: Int = 1, maxDistance: Double = .infinity, distance: ((Item) -> Double)? = nil) -> [(id: EntityID, distance: Double)] {
        guard root >= 0, k > 0 else { return [] }
        // Min-heap of (lower bound, node index or -1 - item index).
        var heap: [(Double, Int)] = [(SpatialIndex.boxDistance(p, nodes[root].box), root)]
        func push(_ e: (Double, Int)) {
            heap.append(e); var i = heap.count - 1
            while i > 0 { let par = (i - 1) / 2; if heap[par].0 <= heap[i].0 { break }; heap.swapAt(par, i); i = par }
        }
        func pop() -> (Double, Int) {
            let top = heap[0]; let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last; var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1; var s = i
                    if l < heap.count && heap[l].0 < heap[s].0 { s = l }
                    if r < heap.count && heap[r].0 < heap[s].0 { s = r }
                    if s == i { break }; heap.swapAt(s, i); i = s
                }
            }
            return top
        }
        var out: [(id: EntityID, distance: Double)] = []
        while !heap.isEmpty && out.count < k {
            let (d, ref) = pop()
            if d > maxDistance { break }
            if ref < 0 {
                out.append((items[-1 - ref].id, d)); continue
            }
            let node = nodes[ref]
            for c in node.start..<(node.start + node.count) {
                if node.leaf {
                    let it = items[c]
                    let lb = SpatialIndex.boxDistance(p, it.box)
                    if lb > maxDistance { continue }
                    // Exact distance is never below the box distance, so it keeps the best-first order valid.
                    push((distance.map { max($0(it), lb) } ?? lb, -1 - c))
                } else {
                    push((SpatialIndex.boxDistance(p, nodes[c].box), c))
                }
            }
        }
        return out
    }

    /// Nearest drawing object or element to a point by true geometric distance (entities) or plan box (elements).
    public static func nearestObject(in doc: ArchiDocument, index: SpatialIndex, to p: Vec2, maxDistance: Double = .infinity) -> EntityID? {
        var byID: [EntityID: Int] = [:]
        for (i, e) in doc.entities.enumerated() { byID[e.id] = i }
        return index.nearest(to: p, maxDistance: maxDistance) { it in
            if let i = byID[it.id] { return GeometryOps.distance(from: p, to: doc.entities[i].geometry, doc: doc) }
            return boxDistance(p, it.box)
        }.first?.id
    }
}
