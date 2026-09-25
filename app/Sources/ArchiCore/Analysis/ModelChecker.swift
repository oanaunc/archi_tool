// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public enum IssueSeverity: String, Codable, Comparable {
    case error, warning, info
    var rank: Int { self == .error ? 0 : (self == .warning ? 1 : 2) }
    public static func < (a: IssueSeverity, b: IssueSeverity) -> Bool { a.rank < b.rank }
}

public struct ModelIssue: Hashable {
    public var severity: IssueSeverity
    /// Stable rule code, e.g. "WALL-HEIGHT".
    public var code: String
    public var message: String
    public var ids: [EntityID]
    /// Region to zoom to.
    public var bounds: BBox2
    public var description: String { "[\(severity.rawValue.uppercased())] \(code): \(message) (" + ids.map { "#\($0)" }.joined(separator: ", ") + ")" }
}

/// Model audit: wall and opening sanity, overlapping/duplicate objects, room validation, level references.
public enum ModelChecker {
    public struct Options {
        /// Length tolerance in drawing units.
        public var tolerance: Double = 1
        /// Room names treated as "unnamed".
        public var placeholderRoomNames: Set<String> = ["", "room", "space", "untitled"]
        public init() {}
    }

    public static func check(_ doc: ArchiDocument, options: Options = Options()) -> [ModelIssue] {
        var out: [ModelIssue] = []
        let tol = options.tolerance
        func box(_ pts: [Vec2]) -> BBox2 { let b = BBox2(points: pts); return b.isEmpty ? b : b.expanded(by: max(b.width, b.height) * 0.1 + 100 / doc.units.mm) }
        func issue(_ s: IssueSeverity, _ c: String, _ m: String, _ ids: [EntityID], _ pts: [Vec2]) { out.append(ModelIssue(severity: s, code: c, message: m, ids: ids, bounds: box(pts))) }
        let levelIDs = Set(doc.levels.map(\.id))

        var walls: [(BIMElement, WallGeom)] = []
        for el in doc.elements {
            if !levelIDs.contains(el.level) { issue(.error, "LEVEL-MISSING", "\(el.typeName) is on level \(el.level), which does not exist", [el.id], elementPoints(el, doc)) }
            switch el.geometry {
            case .wall(let w):
                walls.append((el, w))
                if w.length <= tol { issue(.error, "WALL-LENGTH", "Wall has zero length", [el.id], [w.start]) }
                if w.height <= tol { issue(.error, "WALL-HEIGHT", "Wall has no height (\(fmt(w.height)))", [el.id], [w.start, w.end]) }
                if w.thickness <= tol { issue(.error, "WALL-THICKNESS", "Wall has no thickness", [el.id], [w.start, w.end]) }
            case .slab(let s):
                if s.boundary.count < 3 || abs(GeometryOps.signedArea(s.boundary)) <= tol * tol { issue(.error, "SLAB-EMPTY", "Slab boundary has no area", [el.id], s.boundary) }
                if s.thickness <= tol { issue(.warning, "SLAB-THICKNESS", "Slab has no thickness", [el.id], s.boundary) }
            case .column(let c):
                if c.height <= tol { issue(.error, "COLUMN-HEIGHT", "Column has no height", [el.id], [c.position]) }
            case .opening(let o):
                guard let host = doc.element(o.hostWall), case .wall(let w) = host.geometry else {
                    issue(.error, "OPENING-HOST", "\(o.kind.rawValue.capitalized) has no host wall (#\(o.hostWall) missing)", [el.id], []); continue
                }
                let len = ScheduleExporter.wallLength(w)
                let at = w.centerStart + w.direction * o.offset
                if o.width > len + tol {
                    issue(.error, "OPENING-WIDER", "\(o.kind.rawValue.capitalized) is wider (\(fmt(o.width))) than its host wall (\(fmt(len)))", [el.id, host.id], [w.start, w.end])
                } else if o.offset - o.width / 2 < -tol || o.offset + o.width / 2 > len + tol {
                    issue(.warning, "OPENING-OUTSIDE", "\(o.kind.rawValue.capitalized) extends past the end of its host wall", [el.id, host.id], [at, w.start, w.end])
                }
                if o.sill + o.height > w.height + tol {
                    issue(.warning, "OPENING-TALLER", "\(o.kind.rawValue.capitalized) top (\(fmt(o.sill + o.height))) is above the wall height (\(fmt(w.height)))", [el.id, host.id], [at])
                }
                if o.width <= tol || o.height <= tol { issue(.error, "OPENING-SIZE", "\(o.kind.rawValue.capitalized) has no width or height", [el.id], [at]) }
            default: break
            }
        }

        // Overlapping openings in the same wall.
        var byHost: [EntityID: [(BIMElement, OpeningGeom)]] = [:]
        for el in doc.elements { if case .opening(let o) = el.geometry { byHost[o.hostWall, default: []].append((el, o)) } }
        for (hid, ops) in byHost.sorted(by: { $0.key < $1.key }) where ops.count > 1 {
            guard let host = doc.element(hid), case .wall(let w) = host.geometry else { continue }
            for i in 0..<ops.count { for j in (i + 1)..<ops.count {
                let a = ops[i].1, b = ops[j].1
                let alongOverlap = min(a.offset + a.width / 2, b.offset + b.width / 2) - max(a.offset - a.width / 2, b.offset - b.width / 2)
                let vertOverlap = min(a.sill + a.height, b.sill + b.height) - max(a.sill, b.sill)
                if alongOverlap > tol && vertOverlap > tol {
                    issue(.error, "OPENING-OVERLAP", "Openings overlap in wall #\(hid)", [ops[i].0.id, ops[j].0.id], [w.centerStart + w.direction * a.offset, w.centerStart + w.direction * b.offset])
                }
            } }
        }

        // Overlapping / duplicate walls (collinear, same level, overlapping along their length).
        for i in 0..<walls.count { for j in (i + 1)..<walls.count {
            let (ea, a) = walls[i], (eb, b) = walls[j]
            guard ea.level == eb.level, abs(a.bulge) < 1e-9, abs(b.bulge) < 1e-9, a.length > tol, b.length > tol else { continue }
            let d = a.direction
            guard abs(d.cross(b.direction)) < 1e-3 else { continue }
            let off = abs((b.centerStart - a.centerStart).cross(d))
            guard off < (a.thickness + b.thickness) / 2 - tol else { continue }
            let t0 = (b.centerStart - a.centerStart).dot(d), t1 = (b.centerEnd - a.centerStart).dot(d)
            let overlap = min(a.length, max(t0, t1)) - max(0, min(t0, t1))
            guard overlap > tol else { continue }
            // Vertical overlap too.
            let za = (a.baseOffset, a.baseOffset + a.height), zb = (b.baseOffset, b.baseOffset + b.height)
            guard min(za.1, zb.1) - max(za.0, zb.0) > tol else { continue }
            let dup = off < tol && abs(overlap - a.length) < tol && abs(overlap - b.length) < tol
            issue(dup ? .error : .warning, dup ? "WALL-DUPLICATE" : "WALL-OVERLAP",
                  dup ? "Duplicate walls" : "Walls overlap for \(fmt(overlap)) along their length", [ea.id, eb.id], [a.start, a.end, b.start, b.end])
        } }

        // Rooms.
        var rooms: [(BIMElement, SpaceGeom)] = []
        for el in doc.elements { if case .space(let s) = el.geometry { rooms.append((el, s)) } }
        var numbers: [String: [EntityID]] = [:]
        for (el, s) in rooms {
            let c = s.boundary.count >= 3 ? GeometryOps.centroid(s.boundary) : (s.boundary.first ?? .zero)
            if options.placeholderRoomNames.contains(s.name.trimmingCharacters(in: .whitespaces).lowercased()) {
                issue(.warning, "ROOM-UNNAMED", "Room has no name", [el.id], s.boundary + [c])
            }
            if s.number.trimmingCharacters(in: .whitespaces).isEmpty { issue(.info, "ROOM-UNNUMBERED", "Room \"\(s.name)\" has no number", [el.id], s.boundary) }
            else { numbers["\(el.level)|\(s.number)", default: []].append(el.id) }
            if s.boundary.count < 3 || abs(GeometryOps.signedArea(s.boundary)) <= tol * tol {
                issue(.error, "ROOM-AREA", "Room \"\(s.name)\" has no area", [el.id], s.boundary)
            } else if selfIntersects(s.boundary) {
                issue(.error, "ROOM-BOUNDARY", "Room \"\(s.name)\" boundary crosses itself", [el.id], s.boundary)
            }
            if s.height <= tol { issue(.warning, "ROOM-HEIGHT", "Room \"\(s.name)\" has no height", [el.id], s.boundary) }
        }
        for (k, ids) in numbers.sorted(by: { $0.key < $1.key }) where ids.count > 1 {
            let num = k.split(separator: "|", maxSplits: 1).last.map(String.init) ?? k
            issue(.warning, "ROOM-NUMBER-DUPLICATE", "Room number \(num) is used \(ids.count) times", ids, ids.flatMap { doc.element($0).map { elementPoints($0, doc) } ?? [] })
        }
        for i in 0..<rooms.count { for j in (i + 1)..<rooms.count where rooms[i].0.level == rooms[j].0.level {
            let a = rooms[i].1.boundary, b = rooms[j].1.boundary
            guard a.count >= 3, b.count >= 3, BBox2(points: a).intersects(BBox2(points: b)) else { continue }
            if polygonsOverlap(a, b, tol: tol) {
                issue(.warning, "ROOM-OVERLAP", "Rooms \"\(rooms[i].1.name)\" and \"\(rooms[j].1.name)\" overlap", [rooms[i].0.id, rooms[j].0.id], a + b)
            }
        } }

        // Duplicate drafting entities (same geometry on the same layer).
        var seen: [String: EntityID] = [:]
        for e in doc.entities {
            let k = "\(e.layer.lowercased())|\(e.geometry.hashValue)"
            if let first = seen[k], let fe = doc.entity(first), fe.geometry == e.geometry {
                issue(.warning, "ENTITY-DUPLICATE", "Duplicate \(e.typeName) on layer \(e.layer)", [first, e.id], GeometryOps.bounds(e.geometry, doc: doc).isEmpty ? [] : [GeometryOps.bounds(e.geometry, doc: doc).min, GeometryOps.bounds(e.geometry, doc: doc).max])
            } else { seen[k] = e.id }
        }
        return out.sorted { ($0.severity, $0.code, $0.ids.first ?? 0) < ($1.severity, $1.code, $1.ids.first ?? 0) }
    }

    static func elementPoints(_ el: BIMElement, _ doc: ArchiDocument) -> [Vec2] {
        switch el.geometry {
        case .wall(let w): return [w.start, w.end]
        case .slab(let s): return s.boundary
        case .space(let s): return s.boundary
        case .roof(let r): return r.boundary
        case .column(let c): return [c.position]
        case .beam(let b): return [b.start, b.end]
        case .railing(let r): return r.path
        case .curtainWall(let c): return [c.start, c.end]
        case .component(let c): return [c.position]
        case .stair(let s): return [s.start]
        case .gridLine(let g): return [g.start, g.end]
        case .opening(let o):
            guard let h = doc.element(o.hostWall), case .wall(let w) = h.geometry else { return [] }
            return [w.centerStart + w.direction * o.offset]
        }
    }

    /// True when non-adjacent edges of the closed polygon cross.
    public static func selfIntersects(_ p: [Vec2]) -> Bool {
        let n = p.count
        guard n >= 4 else { return false }
        for i in 0..<n {
            let a0 = p[i], a1 = p[(i + 1) % n]
            for j in (i + 1)..<n {
                if j == i || (j + 1) % n == i || (i + 1) % n == j { continue }
                let b0 = p[j], b1 = p[(j + 1) % n]
                if let x = GeometryOps.segmentIntersection(a0, a1, b0, b1),
                   !(x.isClose(a0, tol: 1e-9) || x.isClose(a1, tol: 1e-9)) { return true }
            }
        }
        return false
    }

    /// Interior overlap of two simple polygons (shared edges do not count).
    public static func polygonsOverlap(_ a: [Vec2], _ b: [Vec2], tol: Double) -> Bool {
        // Proper edge crossings.
        for i in 0..<a.count {
            let a0 = a[i], a1 = a[(i + 1) % a.count]
            for j in 0..<b.count {
                let b0 = b[j], b1 = b[(j + 1) % b.count]
                let d1 = a1 - a0, d2 = b1 - b0
                let den = d1.cross(d2)
                guard abs(den) > 1e-12 else { continue }
                let t = (b0 - a0).cross(d2) / den, u = (b0 - a0).cross(d1) / den
                let et = tol / max(d1.length, 1e-12), eu = tol / max(d2.length, 1e-12)
                if t > et && t < 1 - et && u > eu && u < 1 - eu { return true }
            }
        }
        // Containment: a vertex (nudged toward the centroid) strictly inside the other polygon.
        func inside(_ p: [Vec2], _ q: [Vec2]) -> Bool {
            let c = GeometryOps.centroid(p)
            if GeometryOps.pointInPolygon(c, p) && GeometryOps.pointInPolygon(c, q) && GeometryOps.distance(from: c, toPolyline: q + [q[0]]) > tol { return true }
            for v in p {
                let w = v + (c - v).normalized * max(tol * 2, 1e-6)
                if GeometryOps.pointInPolygon(w, p), GeometryOps.pointInPolygon(w, q), GeometryOps.distance(from: w, toPolyline: q + [q[0]]) > tol { return true }
            }
            return false
        }
        return inside(a, b) || inside(b, a)
    }
}
