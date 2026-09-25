// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

public struct RoomRow: Hashable {
    public var id: EntityID
    public var number: String
    public var name: String
    public var level: String
    /// Area inside the room boundary minus enclosed columns (m²).
    public var netArea: Double
    /// Area to the centre lines of the bounding walls (m²) — adjacent rooms' gross areas tile the floor.
    public var grossArea: Double
    public var perimeter: Double
    public var height: Double
    public var volume: Double
}

public enum RoomSchedule {
    public static func compute(_ doc: ArchiDocument, level: Int? = nil) -> [RoomRow] {
        let u = doc.units.mm / 1000
        var rows: [RoomRow] = []
        for el in doc.elements where level == nil || el.level == level {
            guard case .space(let s) = el.geometry, s.boundary.count >= 3 else { continue }
            let boundary = s.boundary
            let area = abs(GeometryOps.signedArea(boundary))
            var columns = 0.0
            for c in doc.elements where c.level == el.level {
                guard case .column(let col) = c.geometry, GeometryOps.pointInPolygon(col.position, boundary) else { continue }
                columns += col.round ? Double.pi * col.width * col.width / 4 : col.width * col.depth
            }
            let net = max(0, area - columns)
            let gross = abs(GeometryOps.signedArea(grossBoundary(boundary, level: el.level, doc: doc)))
            rows.append(RoomRow(id: el.id, number: s.number, name: s.name, level: doc.level(el.level)?.name ?? "\(el.level)",
                                netArea: net * u * u, grossArea: gross * u * u, perimeter: ScheduleExporter.perimeter(boundary) * u,
                                height: s.height * u, volume: net * s.height * u * u * u))
        }
        return rows.sorted { ($0.level, $0.number, $0.name, $0.id) < ($1.level, $1.number, $1.name, $1.id) }
    }

    /// Room boundary pushed out to the centre lines of walls running along its edges.
    public static func grossBoundary(_ boundary: [Vec2], level: Int, doc: ArchiDocument) -> [Vec2] {
        var pts = boundary
        if pts.count > 1, pts[0].isClose(pts[pts.count - 1]) { pts.removeLast() }
        guard pts.count >= 3 else { return pts }
        if GeometryOps.signedArea(pts) < 0 { pts.reverse() }
        let walls: [WallGeom] = doc.elements.compactMap { e in
            guard e.level == level, case .wall(let w) = e.geometry, abs(w.bulge) < 1e-9, w.length > 1e-9 else { return nil }
            return w
        }
        let n = pts.count
        var offs = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            let d = (b - a).normalized
            guard d.length > 0.5 else { continue }
            let out = Vec2(d.y, -d.x)   // outward for a counter-clockwise loop
            let mid = (a + b) / 2
            var best: Double?
            for w in walls {
                let wd = w.direction
                guard abs(wd.cross(d)) < 0.01 else { continue }
                // Signed distance from the edge to the wall centre line, measured outward.
                let dist = (w.centerStart - mid).dot(out)
                guard dist > -1e-6, abs(dist - w.thickness / 2) <= max(0.1 * w.thickness, 1e-3) else { continue }
                // The wall must overlap the edge along its direction.
                let t0 = (w.centerStart - a).dot(d), t1 = (w.centerEnd - a).dot(d)
                let len = (b - a).length
                guard max(t0, t1) > 1e-6, min(t0, t1) < len - 1e-6 else { continue }
                best = max(best ?? 0, dist)
            }
            offs[i] = best ?? 0
        }
        // Intersect consecutive offset edges.
        var out: [Vec2] = []
        for i in 0..<n {
            let ip = (i + n - 1) % n
            let a0 = pts[ip], a1 = pts[i], b1 = pts[(i + 1) % n]
            let dA = (a1 - a0).normalized, dB = (b1 - a1).normalized
            let nA = Vec2(dA.y, -dA.x) * offs[ip], nB = Vec2(dB.y, -dB.x) * offs[i]
            if let x = GeometryOps.lineIntersection(a0 + nA, a1 + nA, a1 + nB, b1 + nB) { out.append(x) }
            else { out.append(a1 + nB) }
        }
        return out
    }

    public static func table(_ rows: [RoomRow]) -> [[String]] {
        var t = [["number", "name", "level", "net_area_m2", "gross_area_m2", "perimeter_m", "height_m", "volume_m3"]]
        for r in rows { t.append([r.number, r.name, r.level, fmt(r.netArea, 2), fmt(r.grossArea, 2), fmt(r.perimeter, 2), fmt(r.height, 2), fmt(r.volume, 2)]) }
        t.append(["", "TOTAL", "", fmt(rows.reduce(0) { $0 + $1.netArea }, 2), fmt(rows.reduce(0) { $0 + $1.grossArea }, 2), "", "", fmt(rows.reduce(0) { $0 + $1.volume }, 2)])
        return t
    }
    public static func csv(_ rows: [RoomRow]) -> String { CSVText.make(table(rows)) }
}
