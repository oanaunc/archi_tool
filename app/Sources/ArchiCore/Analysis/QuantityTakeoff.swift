// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// One aggregated quantity line (SI units: m, m², m³).
public struct TakeoffLine: Hashable {
    public var category: String
    /// Type / size key (wall type, "900 x 2100", slab thickness …).
    public var key: String
    public var material: String
    public var count: Int = 0
    public var length: Double = 0
    public var area: Double = 0
    public var volume: Double = 0
    /// Openings deducted from wall areas (m²).
    public var deducted: Double = 0
    public var ids: [EntityID] = []
    public init(category: String, key: String, material: String) { self.category = category; self.key = key; self.material = material }
    /// Quantity for a measure name: count, length, area, volume.
    public func quantity(_ measure: String) -> Double {
        switch measure.lowercased() {
        case "count", "each", "ea", "nr": return Double(count)
        case "length", "m", "lm": return length
        case "area", "m2", "sqm": return area
        case "volume", "m3", "cum": return volume
        default: return 0
        }
    }
}

/// Material quantities (net volumes and areas by material; wall types split per ply).
public struct MaterialQuantity: Hashable {
    public var material: String
    public var area: Double
    public var volume: Double
}

public struct Takeoff {
    public var lines: [TakeoffLine]
    public var materials: [MaterialQuantity]
    public func lines(_ category: String) -> [TakeoffLine] { lines.filter { $0.category == category } }
    public func total(_ category: String, _ measure: String) -> Double { lines(category).reduce(0) { $0 + $1.quantity(measure) } }

    public var table: [[String]] {
        var rows = [["category", "type", "material", "count", "length_m", "area_m2", "volume_m3", "deducted_m2"]]
        for l in lines {
            rows.append([l.category, l.key, l.material, "\(l.count)", fmt(l.length, 3), fmt(l.area, 3), fmt(l.volume, 3), fmt(l.deducted, 3)])
        }
        return rows
    }
    public var csv: String { CSVText.make(table) }
    public var materialCSV: String {
        CSVText.make([["material", "area_m2", "volume_m3"]] + materials.map { [$0.material, fmt($0.area, 3), fmt($0.volume, 3)] })
    }
    /// Plain-text report for the command line.
    public var report: String {
        var s = ""
        for l in lines {
            var q: [String] = ["\(l.count)×"]
            if l.length > 0 { q.append("\(fmt(l.length, 2)) m") }
            if l.area > 0 { q.append("\(fmt(l.area, 2)) m²") }
            if l.volume > 0 { q.append("\(fmt(l.volume, 3)) m³") }
            s += "\(l.category.padding(toLength: 10, withPad: " ", startingAt: 0)) \(l.key) [\(l.material)]: \(q.joined(separator: ", "))\n"
        }
        return s
    }
}

public enum CSVText {
    public static func escape(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
    public static func make(_ rows: [[String]]) -> String { rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n" }
}

public enum QuantityTakeoff {
    /// Quantities of BIM elements, optionally for one level. Wall areas are net of hosted openings (one face).
    public static func compute(_ doc: ArchiDocument, level: Int? = nil) -> Takeoff {
        let doc = ModelSets.scheduleModel(doc)   // SCHEDULEFILTER: worksets, design options, phases
        let u = doc.units.mm / 1000        // model units → m
        let a2 = u * u, v3 = u * u * u
        var lines: [String: TakeoffLine] = [:]
        var order: [String] = []
        var mats: [String: (Double, Double)] = [:]
        func line(_ c: String, _ k: String, _ m: String) -> String {
            let key = c + "\u{1}" + k + "\u{1}" + m
            if lines[key] == nil { lines[key] = TakeoffLine(category: c, key: k, material: m); order.append(key) }
            return key
        }
        func mat(_ name: String, area: Double, volume: Double) {
            let n = name.isEmpty ? "(none)" : name
            let cur = mats[n] ?? (0, 0)
            mats[n] = (cur.0 + area, cur.1 + volume)
        }
        func mm(_ v: Double) -> String { fmt(v * doc.units.mm, 0) }
        let els = doc.elements.filter { level == nil || $0.level == level }
        for el in els {
            let m = el.material ?? ""
            switch el.geometry {
            case .wall(let w):
                let len = ScheduleExporter.wallLength(w)
                var openings = 0.0
                for o in doc.elements { if case .opening(let og) = o.geometry, og.hostWall == el.id, !og.isNiche {
                    let top = min(og.sill + og.height, w.height), bottom = max(og.sill, 0)
                    openings += max(0, min(og.width, len)) * max(0, top - bottom)
                } }
                let gross = len * max(w.height, 0)
                let net = max(0, gross - openings)
                let key = line("wall", w.wallType ?? "Generic \(mm(w.thickness)) mm", m)
                lines[key]!.count += 1; lines[key]!.length += len * u; lines[key]!.area += net * a2
                lines[key]!.volume += net * w.thickness * v3; lines[key]!.deducted += openings * a2; lines[key]!.ids.append(el.id)
                if let tn = w.wallType, let wt = doc.wallTypes.first(where: { $0.name == tn }), !wt.plies.isEmpty {
                    let scaleT = wt.thickness > 0 ? w.thickness / wt.thickness : 1
                    for p in wt.plies { mat(p.material, area: net * a2, volume: net * p.thickness * scaleT * v3) }
                } else { mat(m, area: net * a2, volume: net * w.thickness * v3) }
            case .slab(let s):
                let plan = ScheduleExporter.slabArea(s)
                let surf = plan / max(cos(rad(s.slope)), 0.05)
                let key = line("slab", "\(mm(s.thickness)) mm", m)
                lines[key]!.count += 1; lines[key]!.area += surf * a2; lines[key]!.volume += plan * s.thickness * v3
                lines[key]!.length += (ScheduleExporter.perimeter(s.boundary) + s.holes.reduce(0) { $0 + ScheduleExporter.perimeter($1) }) * u
                lines[key]!.ids.append(el.id)
                mat(m, area: surf * a2, volume: plan * s.thickness * v3)
            case .column(let c):
                let sec = c.round ? Double.pi * c.width * c.width / 4 : c.width * c.depth
                let key = line("column", c.round ? "Ø\(mm(c.width))" : "\(mm(c.width)) x \(mm(c.depth))", m)
                lines[key]!.count += 1; lines[key]!.length += c.height * u; lines[key]!.volume += sec * c.height * v3; lines[key]!.ids.append(el.id)
                mat(m, area: 0, volume: sec * c.height * v3)
            case .beam(let b):
                let len = b.start.distance(to: b.end)
                let key = line("beam", "\(mm(b.width)) x \(mm(b.depth))", m)
                lines[key]!.count += 1; lines[key]!.length += len * u; lines[key]!.volume += len * b.width * b.depth * v3; lines[key]!.ids.append(el.id)
                mat(m, area: 0, volume: len * b.width * b.depth * v3)
            case .opening(let o):
                let cat = o.kind == .opening ? (o.isNiche ? "niche" : "opening") : o.kind.rawValue
                let key = line(cat, o.typeName ?? "\(mm(o.width)) x \(mm(o.height))", m)
                lines[key]!.count += 1; lines[key]!.area += o.width * o.height * a2; lines[key]!.ids.append(el.id)
            case .roof(let r):
                let plan = abs(GeometryOps.signedArea(r.boundary))
                let surf = r.kind == .flat ? plan : plan / max(cos(rad(r.pitch)), 0.05)
                let key = line("roof", "\(r.kind.rawValue) \(fmt(r.pitch, 1))°", m)
                lines[key]!.count += 1; lines[key]!.area += surf * a2; lines[key]!.volume += surf * r.thickness * v3
                lines[key]!.length += ScheduleExporter.perimeter(r.boundary) * u; lines[key]!.ids.append(el.id)
                mat(m, area: surf * a2, volume: surf * r.thickness * v3)
            case .stair(let s):
                let key = line("stair", "\(s.kind.rawValue) \(s.riserCount) risers", m)
                lines[key]!.count += 1; lines[key]!.length += s.runLength * u; lines[key]!.ids.append(el.id)
            case .railing(let r):
                let key = line("railing", "h \(mm(r.height))", m)
                lines[key]!.count += 1; lines[key]!.length += ScheduleExporter.perimeter(r.path, closed: false) * u; lines[key]!.ids.append(el.id)
            case .curtainWall(let c):
                let len = c.length
                let key = line("curtainWall", "h \(mm(c.height))", m)
                lines[key]!.count += 1; lines[key]!.length += len * u; lines[key]!.area += len * c.height * a2; lines[key]!.ids.append(el.id)
                mat(m, area: len * c.height * a2, volume: 0)
            case .space(let s):
                let key = line("space", s.name.isEmpty ? "Room" : s.name, "")
                let a = abs(GeometryOps.signedArea(s.boundary))
                lines[key]!.count += 1; lines[key]!.area += a * a2; lines[key]!.volume += a * s.height * v3
                lines[key]!.length += ScheduleExporter.perimeter(s.boundary) * u; lines[key]!.ids.append(el.id)
            case .component(let c):
                let key = line("component", c.block ?? c.category, m)
                lines[key]!.count += 1; lines[key]!.ids.append(el.id)
            case .gridLine: break
            }
        }
        let catOrder = ["wall", "curtainWall", "slab", "roof", "column", "beam", "door", "window", "opening", "niche", "stair", "railing", "component", "space"]
        let sorted = order.map { lines[$0]! }.sorted {
            let a = catOrder.firstIndex(of: $0.category) ?? 99, b = catOrder.firstIndex(of: $1.category) ?? 99
            return a != b ? a < b : ($0.key, $0.material) < ($1.key, $1.material)
        }
        let mq = mats.map { MaterialQuantity(material: $0.key, area: $0.value.0, volume: $0.value.1) }.sorted { $0.material < $1.material }
        return Takeoff(lines: sorted, materials: mq)
    }
}
