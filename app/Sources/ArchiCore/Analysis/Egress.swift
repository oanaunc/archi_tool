// Oanarina Archi Tool — GPL-3.0-or-later
// Egress travel distance (shortest walking path on a grid from every point of every room to the nearest exit, walls
// and columns blocking, doors passable) and accessibility checks (door clear widths, wheelchair turning circles in
// bathrooms).
import Foundation

public struct EgressOptions {
    /// Grid cell (drawing units); 0 = 250 mm.
    public var cell = 0.0
    /// Maximum travel distance to an exit (m).
    public var maxDistance = 45.0
    public init() {}
    public static func from(_ doc: ArchiDocument) -> EgressOptions {
        var o = EgressOptions()
        if let v = doc.variable("EGRESSMAX").flatMap(Double.init), v > 0 { o.maxDistance = v }
        if let v = doc.variable("EGRESSCELL").flatMap(Double.init), v > 0 { o.cell = v }
        return o
    }
}

public struct EgressRow: Hashable {
    public var id: EntityID
    public var number: String
    public var name: String
    /// Longest travel distance from a point of the room to an exit (m); nil when some part of the room has no way out.
    public var distance: Double?
    public var farthest: Vec2
    /// Walking route from the farthest point to the exit (drawing units).
    public var path: [Vec2]
    public var ok: Bool
}

public struct EgressResult {
    public var rows: [EgressRow]
    public var exits: [EntityID]
    public var cell: Double
    public var maxDistance: Double
    public var failures: [EgressRow] { rows.filter { !$0.ok } }
    public var table: [[String]] {
        [["number", "name", "travel_m", "limit_m", "status"]] + rows.map {
            [$0.number, $0.name, $0.distance.map { fmt($0, 2) } ?? "no exit", fmt(maxDistance, 1), $0.ok ? "OK" : "FAIL"]
        }
    }
}

public enum EgressAnalysis {
    /// Exits on a level: doors marked props exit=1, doors in exterior walls, and (above the lowest level) stairs.
    public static func exits(_ doc: ArchiDocument, level: Int) -> [EntityID] {
        let lowest = doc.levels.min { $0.elevation < $1.elevation }?.id ?? level
        return doc.elements.filter { el in
            if el.props["exit"] == "0" { return false }
            switch el.geometry {
            case .opening(let o):
                guard o.kind == .door, let h = doc.element(o.hostWall), h.level == level else { return false }
                return el.props["exit"] == "1" || Thermal.isExterior(h, doc: doc)
            case .stair: return el.level == level && (level != lowest || el.props["exit"] == "1")
            default: return false
            }
        }.map(\.id)
    }

    struct Grid {
        var origin: Vec2, cell: Double, nx: Int, ny: Int
        func center(_ i: Int, _ j: Int) -> Vec2 { origin + Vec2((Double(i) + 0.5) * cell, (Double(j) + 0.5) * cell) }
        func index(_ p: Vec2) -> (Int, Int) { (Int(((p.x - origin.x) / cell).rounded(.down)), Int(((p.y - origin.y) / cell).rounded(.down))) }
        func range(_ b: BBox2) -> (ClosedRange<Int>, ClosedRange<Int>)? {
            let a = index(b.min), c = index(b.max)
            let i0 = max(0, a.0), j0 = max(0, a.1), i1 = min(nx - 1, c.0), j1 = min(ny - 1, c.1)
            guard i0 <= i1, j0 <= j1 else { return nil }
            return (i0...i1, j0...j1)
        }
    }

    public static func compute(_ doc: ArchiDocument, level: Int, options: EgressOptions = EgressOptions()) -> EgressResult {
        let u = doc.units.mm / 1000
        let els = doc.elements.filter { $0.level == level }
        let rooms = els.filter { if case .space(let s) = $0.geometry { return $0.props["areaScheme"] == nil && s.boundary.count >= 3 }; return false }
        let exitIDs = exits(doc, level: level)
        var bounds = BBox2.empty
        for e in els {
            switch e.geometry {
            case .wall(let w): DXFWriter.wallOutline(w).forEach { bounds.add($0) }
            case .space(let s): s.boundary.forEach { bounds.add($0) }
            case .stair(let s): bounds.add(s.start)
            default: break
            }
        }
        guard !bounds.isEmpty, !rooms.isEmpty else { return EgressResult(rows: [], exits: exitIDs, cell: 0, maxDistance: options.maxDistance) }
        var cell = options.cell > 0 ? options.cell : 250 / doc.units.mm
        let pad = cell * 2
        bounds = BBox2(min: bounds.min - Vec2(pad, pad), max: bounds.max + Vec2(pad, pad))
        while (bounds.width / cell) * (bounds.height / cell) > 1_500_000 { cell *= 1.5 }
        let g = Grid(origin: bounds.min, cell: cell, nx: Int((bounds.width / cell).rounded(.up)), ny: Int((bounds.height / cell).rounded(.up)))
        var blocked = [Bool](repeating: false, count: g.nx * g.ny)
        var sources: [Int] = []
        let exitSet = Set(exitIDs)
        // Walls with passable gaps at doors and full-height openings.
        for e in els {
            guard case .wall(let w) = e.geometry, w.length > 1e-9 else { continue }
            let outline = DXFWriter.wallOutline(w)
            var gaps: [(Double, Double, Bool)] = []
            for oe in doc.elements { if case .opening(let o) = oe.geometry, o.hostWall == e.id, !o.isNiche, o.kind != .window, o.sill < 300 / doc.units.mm {
                gaps.append((o.offset - o.width / 2, o.offset + o.width / 2, exitSet.contains(oe.id)))
            } }
            let d = w.direction, nrm = d.perp
            let straight = abs(w.bulge) < 1e-9
            // Straight walls block every cell within half a cell of their centre line (thin walls never leak).
            let half = max(w.thickness / 2, g.cell / 2)
            let len = w.centerStart.distance(to: w.centerEnd)
            guard let (ri, rj) = g.range(BBox2(points: outline).expanded(by: g.cell)) else { continue }
            for j in rj { for i in ri {
                let p = g.center(i, j)
                let t = (p - w.centerStart).dot(d)
                if straight {
                    guard abs((p - w.centerStart).dot(nrm)) <= half, t >= -half, t <= len + half else { continue }
                } else {
                    guard GeometryOps.pointInPolygon(p, outline) else { continue }
                }
                if straight, let gap = gaps.first(where: { t >= $0.0 && t <= $0.1 }) {
                    if gap.2 { sources.append(j * g.nx + i) }
                    continue
                }
                blocked[j * g.nx + i] = true
            } }
        }
        for e in els {
            switch e.geometry {
            case .column(let c):
                let r = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
                let pts = c.round ? (0..<16).map { c.position + Vec2.polar(c.width / 2, 2 * .pi * Double($0) / 16) }
                    : [Vec2(-c.width / 2, -c.depth / 2), Vec2(c.width / 2, -c.depth / 2), Vec2(c.width / 2, c.depth / 2), Vec2(-c.width / 2, c.depth / 2)].map(r.apply)
                guard let (ri, rj) = g.range(BBox2(points: pts)) else { continue }
                for j in rj { for i in ri where GeometryOps.pointInPolygon(g.center(i, j), pts) { blocked[j * g.nx + i] = true } }
            case .stair(let s) where exitSet.contains(e.id):
                let (i, j) = g.index(s.start)
                if i >= 0, j >= 0, i < g.nx, j < g.ny { sources.append(j * g.nx + i); blocked[j * g.nx + i] = false }
            default: break
            }
        }
        // Dijkstra from all exit cells (8-connected, no corner cutting).
        var dist = [Double](repeating: .infinity, count: g.nx * g.ny)
        var parent = [Int](repeating: -1, count: g.nx * g.ny)
        var heap = MinHeap()
        for s in Set(sources) { dist[s] = 0; heap.push((0, s)) }
        let steps: [(Int, Int, Double)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 2.0.squareRoot()), (1, -1, 2.0.squareRoot()), (-1, 1, 2.0.squareRoot()), (-1, -1, 2.0.squareRoot())]
        while let (d0, k) = heap.pop() {
            guard d0 <= dist[k] else { continue }
            let i = k % g.nx, j = k / g.nx
            for (di, dj, w) in steps {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < g.nx, b < g.ny else { continue }
                let n = b * g.nx + a
                if blocked[n] { continue }
                if di != 0 && dj != 0 && (blocked[j * g.nx + a] || blocked[b * g.nx + i]) { continue }
                let nd = d0 + w * g.cell
                if nd < dist[n] { dist[n] = nd; parent[n] = k; heap.push((nd, n)) }
            }
        }
        var rows: [EgressRow] = []
        for r in rooms {
            guard case .space(let s) = r.geometry, let (ri, rj) = g.range(BBox2(points: s.boundary)) else { continue }
            var worst = -1.0, worstK = -1, unreachable = false, any = false
            for j in rj { for i in ri {
                let k = j * g.nx + i
                guard !blocked[k], GeometryOps.pointInPolygon(g.center(i, j), s.boundary) else { continue }
                any = true
                if dist[k].isInfinite { unreachable = true; continue }
                if dist[k] > worst { worst = dist[k]; worstK = k }
            } }
            guard any else { continue }
            var path: [Vec2] = []
            var k = worstK, guardN = 0
            while k >= 0 && guardN < g.nx * g.ny { path.append(g.center(k % g.nx, k / g.nx)); k = parent[k]; guardN += 1 }
            path = simplify(path)
            let meters = worst >= 0 ? worst * u : nil
            let ok = !unreachable && meters.map { $0 <= options.maxDistance } ?? false
            rows.append(EgressRow(id: r.id, number: s.number, name: s.name, distance: unreachable ? nil : meters, farthest: path.first ?? GeometryOps.centroid(s.boundary),
                                  path: path, ok: ok))
        }
        rows.sort { ($0.number, $0.name, $0.id) < ($1.number, $1.name, $1.id) }
        return EgressResult(rows: rows, exits: exitIDs, cell: g.cell, maxDistance: options.maxDistance)
    }

    /// Drops collinear intermediate points of a grid path.
    static func simplify(_ p: [Vec2]) -> [Vec2] {
        guard p.count > 2 else { return p }
        var out = [p[0]]
        for i in 1..<(p.count - 1) {
            let a = out.last!, b = p[i], c = p[i + 1]
            if abs((b - a).cross(c - b)) > 1e-9 { out.append(b) }
        }
        out.append(p.last!)
        return out
    }

    struct MinHeap {
        var a: [(Double, Int)] = []
        mutating func push(_ x: (Double, Int)) {
            a.append(x); var i = a.count - 1
            while i > 0 { let p = (i - 1) / 2; if a[p].0 <= a[i].0 { break }; a.swapAt(p, i); i = p }
        }
        mutating func pop() -> (Double, Int)? {
            guard !a.isEmpty else { return nil }
            let top = a[0]; a[0] = a[a.count - 1]; a.removeLast()
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < a.count && a[l].0 < a[m].0 { m = l }
                if r < a.count && a[r].0 < a[m].0 { m = r }
                if m == i { break }
                a.swapAt(i, m); i = m
            }
            return top
        }
    }
}

// MARK: - Accessibility

public struct AccessibilityOptions {
    /// Minimum clear door width (mm) and wheelchair turning circle diameter (mm).
    public var minDoorClear = 850.0
    public var turningDiameter = 1500.0
    /// Room names (lower case substrings) treated as bathrooms.
    public var bathroomNames = ["bath", "wc", "toilet", "washroom", "restroom", "shower", "lavatory", "baie", "sanitar", "bad", "aseo", "baño"]
    public init() {}
    public static func from(_ doc: ArchiDocument) -> AccessibilityOptions {
        var o = AccessibilityOptions()
        if let v = doc.variable("A11YDOORWIDTH").flatMap(Double.init), v > 0 { o.minDoorClear = v }
        if let v = doc.variable("A11YTURNING").flatMap(Double.init), v > 0 { o.turningDiameter = v }
        return o
    }
}

public struct TurningRow: Hashable {
    public var id: EntityID
    public var name: String
    /// Largest free circle (mm) and its centre.
    public var diameter: Double
    public var center: Vec2
    public var ok: Bool
}

public enum Accessibility {
    /// Clear opening of a door (mm): leaf width minus the frame on both sides; double doors report the wider leaf.
    public static func clearWidth(_ o: OpeningGeom, unitMM: Double) -> Double {
        let clear = max(0, o.width - 2 * o.frameWidth) * unitMM
        return o.doorStyle == .double ? clear / 2 : clear
    }

    public static func isBathroom(_ name: String, options: AccessibilityOptions) -> Bool {
        let n = name.lowercased()
        return options.bathroomNames.contains { n.contains($0) }
    }

    /// Largest circle inside a room that avoids components (fixtures, furniture), on a `step` grid (drawing units).
    public static func largestFreeCircle(_ boundary: [Vec2], obstacles: [[Vec2]], step: Double) -> (diameter: Double, center: Vec2) {
        let b = BBox2(points: boundary)
        guard !b.isEmpty, step > 0 else { return (0, .zero) }
        var best = 0.0, bc = GeometryOps.centroid(boundary)
        func edgeDist(_ p: Vec2, _ poly: [Vec2]) -> Double {
            var d = Double.infinity
            for i in 0..<poly.count { d = min(d, Thermal.segDist(p, poly[i], poly[(i + 1) % poly.count])) }
            return d
        }
        var y = b.min.y + step / 2
        while y < b.max.y {
            var x = b.min.x + step / 2
            while x < b.max.x {
                let p = Vec2(x, y)
                if GeometryOps.pointInPolygon(p, boundary) {
                    var r = edgeDist(p, boundary)
                    for o in obstacles where r > best {
                        if GeometryOps.pointInPolygon(p, o) { r = 0; break }
                        r = min(r, edgeDist(p, o))
                    }
                    if r > best { best = r; bc = p }
                }
                x += step
            }
            y += step
        }
        return (best * 2, bc)
    }

    public static func check(_ doc: ArchiDocument, level: Int? = nil, options o: AccessibilityOptions = AccessibilityOptions()) -> (issues: [ModelIssue], turning: [TurningRow]) {
        let mm = doc.units.mm
        var issues: [ModelIssue] = []
        for el in doc.elements {
            guard case .opening(let op) = el.geometry, op.kind == .door, let h = doc.element(op.hostWall), level == nil || h.level == level,
                  case .wall(let w) = h.geometry else { continue }
            let clear = clearWidth(op, unitMM: mm)
            if clear + 1e-6 < o.minDoorClear {
                let c = w.centerStart + w.direction * op.offset
                let r = op.width
                issues.append(ModelIssue(severity: .warning, code: "A11Y-DOOR-WIDTH",
                                         message: "Door clear width \(fmt(clear, 0)) mm is below \(fmt(o.minDoorClear, 0)) mm",
                                         ids: [el.id], bounds: BBox2(min: c - Vec2(r, r), max: c + Vec2(r, r))))
            }
            if op.threshold, (el.props["thresholdHeight"].flatMap(Double.init) ?? 20) > 20 {
                issues.append(ModelIssue(severity: .warning, code: "A11Y-THRESHOLD", message: "Door threshold higher than 20 mm", ids: [el.id], bounds: .empty))
            }
        }
        var rows: [TurningRow] = []
        for el in doc.elements where level == nil || el.level == level {
            guard case .space(let s) = el.geometry, s.boundary.count >= 3, isBathroom(s.name, options: o) else { continue }
            var obstacles: [[Vec2]] = []
            for c in doc.elements where c.level == el.level {
                guard case .component(let cg) = c.geometry, cg.path == nil, GeometryOps.pointInPolygon(cg.position, s.boundary) else { continue }
                let t = Transform2D.translation(cg.position) * Transform2D.rotation(cg.rotation)
                obstacles.append([Vec2(-cg.size.x / 2, -cg.size.y / 2), Vec2(cg.size.x / 2, -cg.size.y / 2), Vec2(cg.size.x / 2, cg.size.y / 2), Vec2(-cg.size.x / 2, cg.size.y / 2)].map(t.apply))
            }
            let f = largestFreeCircle(s.boundary, obstacles: obstacles, step: 50 / mm)
            let dia = f.diameter * mm
            let ok = dia + 1e-6 >= o.turningDiameter
            rows.append(TurningRow(id: el.id, name: s.name, diameter: dia, center: f.center, ok: ok))
            if !ok {
                issues.append(ModelIssue(severity: .warning, code: "A11Y-TURNING",
                                         message: "\(s.name): largest free turning circle Ø\(fmt(dia, 0)) mm, needs Ø\(fmt(o.turningDiameter, 0)) mm",
                                         ids: [el.id], bounds: BBox2(points: s.boundary)))
            }
        }
        return (issues, rows)
    }
}
