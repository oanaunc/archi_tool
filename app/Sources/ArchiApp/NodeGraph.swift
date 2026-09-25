// Oanarina Archi Tool — GPL-3.0-or-later
// Visual programming graph (in the spirit of Sverchok / Dynamo): typed nodes connected by links, evaluated
// deterministically in dependency order with list broadcasting. Pure value types (Foundation + ArchiCore only).
import Foundation
import ArchiCore

enum NodePortType: String, Codable { case number, point, geometry }

/// The data flowing along a link: always a list (single values are one-element lists).
enum NodeValue: Equatable {
    case numbers([Double])
    case points([Vec3])
    case geometry([Geometry])

    var count: Int {
        switch self { case .numbers(let a): return a.count; case .points(let a): return a.count; case .geometry(let a): return a.count }
    }
    var summary: String {
        switch self {
        case .numbers(let a): return a.count == 1 ? fmt(a[0], 3) : "\(a.count) numbers"
        case .points(let a): return a.count == 1 ? "(\(fmt(a[0].x, 1)), \(fmt(a[0].y, 1)), \(fmt(a[0].z, 1)))" : "\(a.count) points"
        case .geometry(let a): return "\(a.count) object\(a.count == 1 ? "" : "s")"
        }
    }
}

enum NodeKind: String, Codable, CaseIterable, Identifiable {
    case number, range, series, point, line, circle, rectangle, polygon, polyline, extrude, move, rotate, array, polarArray, merge
    var id: String { rawValue }

    struct Port { let name: String; let type: NodePortType; let defaultValue: Double }

    var title: String {
        switch self {
        case .number: return "Number"
        case .range: return "Range"
        case .series: return "Series"
        case .point: return "Point"
        case .line: return "Line"
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        case .polygon: return "Polygon"
        case .polyline: return "Polyline"
        case .extrude: return "Extrude"
        case .move: return "Move"
        case .rotate: return "Rotate"
        case .array: return "Array"
        case .polarArray: return "Polar Array"
        case .merge: return "Merge"
        }
    }
    var category: String {
        switch self {
        case .number, .range, .series: return "Numbers"
        case .point, .line, .circle, .rectangle, .polygon, .polyline: return "Geometry"
        case .extrude: return "Solids"
        case .move, .rotate, .array, .polarArray, .merge: return "Transform"
        }
    }
    var output: NodePortType {
        switch self {
        case .number, .range, .series: return .number
        case .point: return .point
        default: return .geometry
        }
    }
    var inputs: [Port] {
        switch self {
        case .number: return []
        case .range: return [Port(name: "start", type: .number, defaultValue: 0), Port(name: "stop", type: .number, defaultValue: 10000), Port(name: "count", type: .number, defaultValue: 5)]
        case .series: return [Port(name: "start", type: .number, defaultValue: 0), Port(name: "step", type: .number, defaultValue: 1000), Port(name: "count", type: .number, defaultValue: 5)]
        case .point: return [Port(name: "x", type: .number, defaultValue: 0), Port(name: "y", type: .number, defaultValue: 0), Port(name: "z", type: .number, defaultValue: 0)]
        case .line: return [Port(name: "start", type: .point, defaultValue: 0), Port(name: "end", type: .point, defaultValue: 1000)]
        case .circle: return [Port(name: "center", type: .point, defaultValue: 0), Port(name: "radius", type: .number, defaultValue: 500)]
        case .rectangle: return [Port(name: "center", type: .point, defaultValue: 0), Port(name: "width", type: .number, defaultValue: 2000), Port(name: "height", type: .number, defaultValue: 1000)]
        case .polygon: return [Port(name: "center", type: .point, defaultValue: 0), Port(name: "radius", type: .number, defaultValue: 1000), Port(name: "sides", type: .number, defaultValue: 6)]
        case .polyline: return [Port(name: "points", type: .point, defaultValue: 0), Port(name: "closed", type: .number, defaultValue: 0)]
        case .extrude: return [Port(name: "profile", type: .geometry, defaultValue: 0), Port(name: "height", type: .number, defaultValue: 3000), Port(name: "base z", type: .number, defaultValue: 0)]
        case .move: return [Port(name: "geometry", type: .geometry, defaultValue: 0), Port(name: "dx", type: .number, defaultValue: 0), Port(name: "dy", type: .number, defaultValue: 0)]
        case .rotate: return [Port(name: "geometry", type: .geometry, defaultValue: 0), Port(name: "angle°", type: .number, defaultValue: 45), Port(name: "center", type: .point, defaultValue: 0)]
        case .array: return [Port(name: "geometry", type: .geometry, defaultValue: 0), Port(name: "columns", type: .number, defaultValue: 3), Port(name: "rows", type: .number, defaultValue: 2),
                             Port(name: "dx", type: .number, defaultValue: 3000), Port(name: "dy", type: .number, defaultValue: 3000)]
        case .polarArray: return [Port(name: "geometry", type: .geometry, defaultValue: 0), Port(name: "count", type: .number, defaultValue: 6), Port(name: "center", type: .point, defaultValue: 0),
                                  Port(name: "angle°", type: .number, defaultValue: 360)]
        case .merge: return [Port(name: "a", type: .geometry, defaultValue: 0), Port(name: "b", type: .geometry, defaultValue: 0), Port(name: "c", type: .geometry, defaultValue: 0)]
        }
    }
}

struct GraphNode: Codable, Identifiable, Hashable {
    var id: Int
    var kind: NodeKind
    var x: Double
    var y: Double
    /// Values of unconnected number inputs (and "value"/"min"/"max" of a Number node); point inputs use "<name>.x/.y/.z".
    var params: [String: Double] = [:]

    func param(_ key: String, _ fallback: Double) -> Double { params[key] ?? fallback }
}

struct GraphLink: Codable, Hashable {
    var from: Int
    var to: Int
    var port: String
}

struct NodeGraph: Codable, Equatable {
    var nodes: [GraphNode] = []
    var links: [GraphLink] = []
    var nextID = 1

    static let variableKey = "NODEGRAPH"

    // MARK: Editing

    @discardableResult
    mutating func add(_ kind: NodeKind, x: Double, y: Double) -> Int {
        var n = GraphNode(id: nextID, kind: kind, x: x, y: y)
        if kind == .number { n.params = ["value": 1000, "min": 0, "max": 10000] }
        nodes.append(n)
        nextID += 1
        return n.id
    }

    mutating func remove(_ id: Int) {
        nodes.removeAll { $0.id == id }
        links.removeAll { $0.from == id || $0.to == id }
    }

    func node(_ id: Int) -> GraphNode? { nodes.first { $0.id == id } }

    /// Connects an output to an input (replacing the input's link). Refuses type mismatches and cycles.
    @discardableResult
    mutating func connect(from: Int, to: Int, port: String) -> Bool {
        guard from != to, let a = node(from), let b = node(to), let p = b.kind.inputs.first(where: { $0.name == port }) else { return false }
        guard NodeGraph.compatible(a.kind.output, p.type) else { return false }
        if depends(from, on: to) { return false }
        links.removeAll { $0.to == to && $0.port == port }
        links.append(GraphLink(from: from, to: to, port: port))
        return true
    }

    mutating func disconnect(to: Int, port: String) { links.removeAll { $0.to == to && $0.port == port } }

    static func compatible(_ out: NodePortType, _ input: NodePortType) -> Bool { out == input }

    /// True when `a` (transitively) takes input from `b`.
    func depends(_ a: Int, on b: Int) -> Bool {
        var stack = [a], seen: Set<Int> = []
        while let n = stack.popLast() {
            if n == b { return true }
            guard seen.insert(n).inserted else { continue }
            stack += links.filter { $0.to == n }.map(\.from)
        }
        return false
    }

    /// Geometry nodes whose output feeds nothing: their results are previewed and baked.
    var outputNodes: [Int] {
        let used = Set(links.map(\.from))
        return nodes.filter { $0.kind.output == .geometry && !used.contains($0.id) }.map(\.id)
    }

    // MARK: Evaluation

    struct Evaluation {
        var values: [Int: NodeValue] = [:]
        var errors: [Int: String] = [:]
        /// Geometry of the output nodes, in node order.
        var output: [Geometry] = []
    }

    /// Nodes in dependency order (inputs first). Nodes on a cycle are left out.
    var order: [Int] {
        var result: [Int] = [], state: [Int: Int] = [:]   // 1 visiting, 2 done
        func visit(_ n: Int) -> Bool {
            if state[n] == 2 { return true }
            if state[n] == 1 { return false }
            state[n] = 1
            for l in links where l.to == n { if !visit(l.from) { return false } }
            state[n] = 2; result.append(n); return true
        }
        for n in nodes.sorted(by: { $0.id < $1.id }) { _ = visit(n.id) }
        return result
    }

    static let maxItems = 20_000

    func evaluate() -> Evaluation {
        var ev = Evaluation()
        for id in order {
            guard let n = node(id) else { continue }
            do { ev.values[id] = try compute(n, ev.values) }
            catch let e as NodeError { ev.errors[id] = e.message }
            catch { ev.errors[id] = "\(error)" }
        }
        for id in outputNodes { if case .geometry(let g)? = ev.values[id] { ev.output += g } }
        return ev
    }

    struct NodeError: Error { let message: String }

    private func input(_ n: GraphNode, _ p: NodeKind.Port, _ values: [Int: NodeValue]) throws -> NodeValue? {
        if let l = links.first(where: { $0.to == n.id && $0.port == p.name }) {
            guard let v = values[l.from] else { throw NodeError(message: "Input \(p.name) has no value (upstream error).") }
            return v
        }
        switch p.type {
        case .number: return .numbers([n.param(p.name, p.defaultValue)])
        case .point:
            let d = p.defaultValue
            return .points([Vec3(n.param(p.name + ".x", d), n.param(p.name + ".y", 0), n.param(p.name + ".z", 0))])
        case .geometry: return nil
        }
    }

    private func numbers(_ n: GraphNode, _ name: String, _ values: [Int: NodeValue]) throws -> [Double] {
        guard let p = n.kind.inputs.first(where: { $0.name == name }), case .numbers(let a)? = try input(n, p, values) else { return [] }
        return a
    }
    private func points(_ n: GraphNode, _ name: String, _ values: [Int: NodeValue]) throws -> [Vec3] {
        guard let p = n.kind.inputs.first(where: { $0.name == name }), case .points(let a)? = try input(n, p, values) else { return [] }
        return a
    }
    private func geometry(_ n: GraphNode, _ name: String, _ values: [Int: NodeValue]) throws -> [Geometry] {
        guard let p = n.kind.inputs.first(where: { $0.name == name }), case .geometry(let a)? = try input(n, p, values) else { return [] }
        return a
    }

    /// Longest-list broadcasting: item i of each list, repeating the last item of shorter lists.
    static func pick<T>(_ a: [T], _ i: Int) -> T? { a.isEmpty ? nil : a[min(i, a.count - 1)] }
    static func broadcastCount(_ counts: [Int]) -> Int { counts.contains(0) ? 0 : (counts.max() ?? 0) }

    private func compute(_ n: GraphNode, _ v: [Int: NodeValue]) throws -> NodeValue {
        func cap(_ c: Int) throws -> Int {
            guard c <= NodeGraph.maxItems else { throw NodeError(message: "More than \(NodeGraph.maxItems) items.") }
            return c
        }
        switch n.kind {
        case .number:
            return .numbers([n.param("value", 1000)])
        case .range:
            let s = try numbers(n, "start", v).first ?? 0, e = try numbers(n, "stop", v).first ?? 0
            let c = try cap(Int((try numbers(n, "count", v).first ?? 0).rounded()))
            guard c >= 1 else { throw NodeError(message: "Count must be at least 1.") }
            return .numbers(c == 1 ? [s] : (0..<c).map { s + (e - s) * Double($0) / Double(c - 1) })
        case .series:
            let s = try numbers(n, "start", v).first ?? 0, st = try numbers(n, "step", v).first ?? 0
            let c = try cap(Int((try numbers(n, "count", v).first ?? 0).rounded()))
            guard c >= 1 else { throw NodeError(message: "Count must be at least 1.") }
            return .numbers((0..<c).map { s + st * Double($0) })
        case .point:
            let xs = try numbers(n, "x", v), ys = try numbers(n, "y", v), zs = try numbers(n, "z", v)
            let c = try cap(NodeGraph.broadcastCount([xs.count, ys.count, zs.count]))
            return .points((0..<c).map { Vec3(NodeGraph.pick(xs, $0)!, NodeGraph.pick(ys, $0)!, NodeGraph.pick(zs, $0)!) })
        case .line:
            let a = try points(n, "start", v), b = try points(n, "end", v)
            let c = try cap(NodeGraph.broadcastCount([a.count, b.count]))
            return .geometry((0..<c).compactMap { i in
                let p = NodeGraph.pick(a, i)!.xy, q = NodeGraph.pick(b, i)!.xy
                return p.distance(to: q) < 1e-9 ? nil : .line(LineGeom(p, q))
            })
        case .circle:
            let cs = try points(n, "center", v), rs = try numbers(n, "radius", v)
            let c = try cap(NodeGraph.broadcastCount([cs.count, rs.count]))
            return .geometry((0..<c).compactMap { i in
                let r = NodeGraph.pick(rs, i)!
                return r > 1e-9 ? .circle(CircleGeom(NodeGraph.pick(cs, i)!.xy, r)) : nil
            })
        case .rectangle:
            let cs = try points(n, "center", v), ws = try numbers(n, "width", v), hs = try numbers(n, "height", v)
            let c = try cap(NodeGraph.broadcastCount([cs.count, ws.count, hs.count]))
            return .geometry((0..<c).compactMap { i in
                let o = NodeGraph.pick(cs, i)!.xy, w = abs(NodeGraph.pick(ws, i)!) / 2, h = abs(NodeGraph.pick(hs, i)!) / 2
                guard w > 1e-9, h > 1e-9 else { return nil }
                return .polyline(PolylineGeom(points: [o + Vec2(-w, -h), o + Vec2(w, -h), o + Vec2(w, h), o + Vec2(-w, h)], closed: true))
            })
        case .polygon:
            let cs = try points(n, "center", v), rs = try numbers(n, "radius", v), ss = try numbers(n, "sides", v)
            let c = try cap(NodeGraph.broadcastCount([cs.count, rs.count, ss.count]))
            return .geometry((0..<c).compactMap { i in
                let o = NodeGraph.pick(cs, i)!.xy, r = NodeGraph.pick(rs, i)!, k = max(3, min(256, Int(NodeGraph.pick(ss, i)!.rounded())))
                guard r > 1e-9 else { return nil }
                return .polyline(PolylineGeom(points: (0..<k).map { o + Vec2(cos(2 * .pi * Double($0) / Double(k) + .pi / 2), sin(2 * .pi * Double($0) / Double(k) + .pi / 2)) * r }, closed: true))
            })
        case .polyline:
            let pts = try points(n, "points", v).map(\.xy)
            guard pts.count >= 2 else { throw NodeError(message: "Needs at least 2 points.") }
            let closed = (try numbers(n, "closed", v).first ?? 0) >= 0.5
            return .geometry([.polyline(PolylineGeom(points: pts, closed: closed && pts.count >= 3))])
        case .extrude:
            let gs = try geometry(n, "profile", v), hs = try numbers(n, "height", v), zs = try numbers(n, "base z", v)
            guard !gs.isEmpty else { throw NodeError(message: "Connect a closed profile (circle, rectangle, polygon, closed polyline).") }
            let c = try cap(NodeGraph.broadcastCount([gs.count, hs.count, zs.count]))
            var out: [Geometry] = []
            for i in 0..<c {
                guard let loop = NodeGraph.profile(NodeGraph.pick(gs, i)!), loop.count >= 3 else { continue }
                let h = NodeGraph.pick(hs, i)!, z = NodeGraph.pick(zs, i)!
                guard abs(h) > 1e-9 else { continue }
                let o = loop[0]
                out.append(.solid(SolidGeom(kind: .extrusion, origin: Vec3(o.x, o.y, h < 0 ? z + h : z), profile: loop.map { $0 - o }, height: abs(h))))
            }
            if out.isEmpty { throw NodeError(message: "No closed profile to extrude.") }
            return .geometry(out)
        case .move:
            let gs = try geometry(n, "geometry", v), dx = try numbers(n, "dx", v), dy = try numbers(n, "dy", v)
            let c = try cap(NodeGraph.broadcastCount([gs.count, dx.count, dy.count]))
            return .geometry((0..<c).map { GeometryOps.transform(NodeGraph.pick(gs, $0)!, .translation(Vec2(NodeGraph.pick(dx, $0)!, NodeGraph.pick(dy, $0)!))) })
        case .rotate:
            let gs = try geometry(n, "geometry", v), a = try numbers(n, "angle°", v), cs = try points(n, "center", v)
            let c = try cap(NodeGraph.broadcastCount([gs.count, a.count, cs.count]))
            return .geometry((0..<c).map { GeometryOps.transform(NodeGraph.pick(gs, $0)!, .rotation(NodeGraph.pick(a, $0)! * .pi / 180, around: NodeGraph.pick(cs, $0)!.xy)) })
        case .array:
            let gs = try geometry(n, "geometry", v)
            let cols = max(1, Int((try numbers(n, "columns", v).first ?? 1).rounded())), rows = max(1, Int((try numbers(n, "rows", v).first ?? 1).rounded()))
            let dx = try numbers(n, "dx", v).first ?? 0, dy = try numbers(n, "dy", v).first ?? 0
            _ = try cap(gs.count * cols * rows)
            var out: [Geometry] = []
            for r in 0..<rows { for k in 0..<cols { for g in gs { out.append(GeometryOps.transform(g, .translation(Vec2(Double(k) * dx, Double(r) * dy)))) } } }
            return .geometry(out)
        case .polarArray:
            let gs = try geometry(n, "geometry", v)
            let count = max(1, Int((try numbers(n, "count", v).first ?? 1).rounded()))
            let center = (try points(n, "center", v).first ?? .zero).xy
            let total = (try numbers(n, "angle°", v).first ?? 360) * .pi / 180
            _ = try cap(gs.count * count)
            // A full circle spaces items by total/count; a partial arc puts the last item at the end angle.
            let full = abs(abs(total) - 2 * .pi) < 1e-6
            let step = count == 1 ? 0 : (full ? total / Double(count) : total / Double(count - 1))
            var out: [Geometry] = []
            for i in 0..<count { for g in gs { out.append(GeometryOps.transform(g, .rotation(step * Double(i), around: center))) } }
            return .geometry(out)
        case .merge:
            var out: [Geometry] = []
            for p in ["a", "b", "c"] { out += try geometry(n, p, v) }
            return .geometry(out)
        }
    }

    /// Closed boundary of a profile curve, or nil.
    static func profile(_ g: Geometry) -> [Vec2]? {
        switch g {
        case .circle(let c): return (0..<48).map { c.center + Vec2(cos(Double($0) / 48 * 2 * .pi), sin(Double($0) / 48 * 2 * .pi)) * c.radius }
        case .polyline(let p):
            guard p.closed || (p.vertices.count > 3 && p.vertices.first!.p.isClose(p.vertices.last!.p, tol: 1e-9)) else { return nil }
            var pts = GeometryOps.polylinePoints(p)
            if pts.count > 1, pts.first!.isClose(pts.last!, tol: 1e-9) { pts.removeLast() }
            return pts
        case .ellipse(let e): return GeometryOps.ellipsePoints(e)
        default: return nil
        }
    }

    // MARK: Persistence (document variable, JSON)

    static func load(_ doc: ArchiDocument) -> NodeGraph? {
        guard let s = doc.variables[variableKey], let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NodeGraph.self, from: d)
    }
    func store(in doc: inout ArchiDocument) {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        if let d = try? e.encode(self), let s = String(data: d, encoding: .utf8) { doc.variables[NodeGraph.variableKey] = s }
    }

    /// A starter graph: a row of columns (polygon → extrude → array).
    static var sample: NodeGraph {
        var g = NodeGraph()
        let h = g.add(.number, x: 20, y: 40); g.nodes[0].params = ["value": 3000, "min": 500, "max": 12000]
        let p = g.add(.polygon, x: 20, y: 150)
        g.nodes[1].params = ["radius": 300, "sides": 8]
        let e = g.add(.extrude, x: 240, y: 90)
        let a = g.add(.array, x: 460, y: 90)
        g.connect(from: p, to: e, port: "profile")
        g.connect(from: h, to: e, port: "height")
        g.connect(from: e, to: a, port: "geometry")
        return g
    }
}

/// Bakes graph output into the drawing: previously baked objects (tagged with the graph prop) are replaced.
enum NodeGraphBake {
    static let tag = "nodeGraph"
    static func bake(_ geometry: [Geometry], into doc: inout ArchiDocument, layer: String = "NODES") -> [EntityID] {
        doc.entities.removeAll { $0.props[tag] != nil }
        guard !geometry.isEmpty else { return [] }
        doc.ensureLayer(layer)
        return geometry.map { g in doc.add(Entity(layer: layer, geometry: g, props: [tag: "1"])) }
    }
    static func bakedCount(_ doc: ArchiDocument) -> Int { doc.entities.filter { $0.props[tag] != nil }.count }
}
