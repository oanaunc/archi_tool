// Oanarina Archi Tool — GPL-3.0-or-later
// Room acoustics (Sabine reverberation time), embodied carbon from material quantities, and isovists (visibility
// polygons in plan).
import Foundation

// MARK: - Reverberation time

public struct ReverbRow: Hashable {
    public var id: EntityID
    public var number: String
    public var name: String
    public var volume: Double        // m³
    public var absorption: Double    // m² Sabine
    public var rt60: Double          // s
}

public enum Acoustics {
    /// Absorption coefficients at 500 Hz by material keyword (typical published values).
    public static let alpha: [(String, Double)] = [
        ("acoustic", 0.7), ("carpet", 0.3), ("curtain", 0.5), ("mineral wool", 0.8), ("insulation", 0.6), ("wood", 0.1), ("timber", 0.1),
        ("glass", 0.04), ("concrete", 0.02), ("brick", 0.03), ("plaster", 0.03), ("gypsum", 0.05), ("plasterboard", 0.05), ("tile", 0.02), ("stone", 0.02),
    ]
    public static func coefficient(_ material: String?, fallback: Double, doc: ArchiDocument) -> Double {
        guard let m = material else { return fallback }
        if let v = doc.variable("ALPHA:" + m).flatMap(Double.init) { return v }
        let n = m.lowercased()
        return alpha.first { n.contains($0.0) }?.1 ?? fallback
    }

    /// RT60 = 0.161·V / A per room. Floor/ceiling/wall coefficients come from ALPHA:floor/ceiling/wall (defaults 0.05,
    /// 0.05, 0.04), the materials of a ceiling element over the room and of the bounding walls; windows and doors use glass
    /// and wood; room prop "absorption" adds m² Sabine (furniture, people).
    public static func reverberation(_ doc: ArchiDocument, level: Int? = nil) -> [ReverbRow] {
        let u = doc.units.mm / 1000
        var rows: [ReverbRow] = []
        for el in doc.elements where level == nil || el.level == level {
            guard case .space(let s) = el.geometry, el.props["areaScheme"] == nil, s.boundary.count >= 3 else { continue }
            let floorA = abs(GeometryOps.signedArea(s.boundary)) * u * u
            let per = ScheduleExporter.perimeter(s.boundary) * u
            let h = s.height * u
            let vol = floorA * h
            guard vol > 0 else { continue }
            func v(_ n: String, _ d: Double) -> Double { doc.variable("ALPHA:" + n).flatMap(Double.init) ?? d }
            // Ceiling material from a ceiling element whose outline contains the room's centroid.
            let c = GeometryOps.centroid(s.boundary)
            var ceilMat: String? = nil
            for e in doc.elements where e.level == el.level && e.props["kind"] == "ceiling" { if case .slab(let sl) = e.geometry, GeometryOps.pointInPolygon(c, sl.boundary) { ceilMat = e.material } }
            var A = floorA * v("floor", 0.05) + floorA * (ceilMat.map { coefficient($0, fallback: 0.05, doc: doc) } ?? v("ceiling", 0.05))
            // Openings in bounding walls.
            var openA = 0.0
            for w in RoomOpenings.windows(of: el, doc: doc, includeDoors: false) { openA += w.glazed; A += w.glazed * coefficient("glass", fallback: 0.04, doc: doc) }
            let doors = doorArea(el, doc: doc)
            openA += doors; A += doors * coefficient("wood", fallback: 0.1, doc: doc)
            A += max(0, per * h - openA) * v("wall", 0.04)
            A += el.props["absorption"].flatMap(Double.init) ?? 0
            rows.append(ReverbRow(id: el.id, number: s.number, name: s.name, volume: vol, absorption: A, rt60: A > 0 ? 0.161 * vol / A : 0))
        }
        return rows.sorted { ($0.number, $0.name, $0.id) < ($1.number, $1.name, $1.id) }
    }

    static func doorArea(_ room: BIMElement, doc: ArchiDocument) -> Double {
        guard case .space(let sp) = room.geometry else { return 0 }
        let u = doc.units.mm / 1000
        var a = 0.0
        for el in doc.elements {
            guard case .opening(let o) = el.geometry, o.kind == .door, let host = doc.element(o.hostWall), host.level == room.level, case .wall(let w) = host.geometry else { continue }
            let c = w.centerStart + w.direction * o.offset, off = w.thickness / 2 + 100 / doc.units.mm
            if GeometryOps.pointInPolygon(c + w.direction.perp * off, sp.boundary) || GeometryOps.pointInPolygon(c - w.direction.perp * off, sp.boundary) { a += o.width * o.height * u * u }
        }
        return a
    }
}

// MARK: - Embodied carbon

public struct CarbonRow: Hashable {
    public var material: String
    public var volume: Double     // m³
    public var mass: Double       // kg
    public var factor: Double     // kgCO2e/kg
    public var carbon: Double { mass * factor }
    public var assumed: Bool
}

public enum EmbodiedCarbon {
    /// Density (kg/m³) and cradle-to-gate factor (kgCO2e/kg), typical ICE database values.
    public static let table: [(String, Double, Double)] = [
        ("reinforced concrete", 2400, 0.18), ("concrete", 2400, 0.13), ("screed", 2100, 0.15), ("aerated", 600, 0.28),
        ("brick", 1800, 0.21), ("block", 1400, 0.09), ("stone", 2600, 0.08), ("granite", 2700, 0.1),
        ("clt", 480, 0.44), ("glulam", 500, 0.51), ("timber", 500, 0.26), ("wood", 500, 0.26), ("plywood", 600, 0.68),
        ("steel", 7850, 1.55), ("aluminium", 2700, 8.2), ("aluminum", 2700, 8.2), ("copper", 8900, 2.7),
        ("glass", 2500, 1.44), ("plasterboard", 800, 0.39), ("gypsum", 1100, 0.13), ("plaster", 1100, 0.13), ("render", 1800, 0.2),
        ("mineral wool", 30, 1.28), ("glass wool", 20, 1.35), ("eps", 20, 3.29), ("xps", 35, 3.3), ("insulation", 30, 1.28),
        ("tile", 2000, 0.78), ("bitumen", 1100, 0.43), ("grass", 0, 0),
    ]

    /// Material rows from the quantity takeoff. CARBON:<material> overrides the factor (kgCO2e/kg) and DENSITY:<material> the density.
    public static func compute(_ doc: ArchiDocument, level: Int? = nil) -> [CarbonRow] {
        QuantityTakeoff.compute(doc, level: level).materials.compactMap { mq -> CarbonRow? in
            guard mq.volume > 0 else { return nil }
            let n = mq.material.lowercased()
            let hit = table.first { n.contains($0.0) }
            let density = doc.variable("DENSITY:" + mq.material).flatMap(Double.init) ?? hit?.1 ?? 2000
            let factor = doc.variable("CARBON:" + mq.material).flatMap(Double.init) ?? hit?.2 ?? 0.2
            let assumed = hit == nil && doc.variable("CARBON:" + mq.material) == nil
            return CarbonRow(material: mq.material, volume: mq.volume, mass: mq.volume * density, factor: factor, assumed: assumed)
        }.sorted { $0.carbon > $1.carbon }
    }

    public static func table(_ rows: [CarbonRow]) -> [[String]] {
        [["material", "volume_m3", "mass_kg", "factor_kgCO2e_per_kg", "kgCO2e", "assumed"]] +
            rows.map { [$0.material, fmt($0.volume, 3), fmt($0.mass, 0), fmt($0.factor, 3), fmt($0.carbon, 0), $0.assumed ? "yes" : ""] } +
            [["TOTAL", fmt(rows.reduce(0) { $0 + $1.volume }, 3), fmt(rows.reduce(0) { $0 + $1.mass }, 0), "", fmt(rows.reduce(0) { $0 + $1.carbon }, 0), ""]]
    }
}

// MARK: - Isovist

public enum Isovist {
    /// Obstruction segments on a level at eye height: wall faces with gaps at doors/openings, and at windows whose
    /// glazing spans the eye height when `seeThroughWindows`.
    public static func obstacles(_ doc: ArchiDocument, level: Int, eyeHeight: Double, seeThroughWindows: Bool = false) -> [(Vec2, Vec2)] {
        var segs: [(Vec2, Vec2)] = []
        for el in doc.elements where el.level == level {
            switch el.geometry {
            case .wall(let w):
                guard w.length > 1e-9, w.baseOffset < eyeHeight, w.baseOffset + w.height > eyeHeight else { continue }
                if abs(w.bulge) > 1e-9 {
                    let o = DXFWriter.wallOutline(w)
                    for i in 0..<o.count { segs.append((o[i], o[(i + 1) % o.count])) }
                    continue
                }
                // Gaps along the wall (distance from the centre start).
                var gaps: [(Double, Double)] = []
                for oe in doc.elements { if case .opening(let og) = oe.geometry, og.hostWall == el.id, !og.isNiche {
                    let z0 = w.baseOffset + og.sill, z1 = z0 + og.height
                    let open = og.kind != .window || seeThroughWindows
                    if open && z0 <= eyeHeight && z1 >= eyeHeight { gaps.append((og.offset - og.width / 2, og.offset + og.width / 2)) }
                } }
                gaps.sort { $0.0 < $1.0 }
                var runs: [(Double, Double)] = []
                var s = 0.0
                for g in gaps { if g.0 > s { runs.append((s, g.0)) }; s = max(s, g.1) }
                if s < w.length { runs.append((s, w.length)) }
                let d = w.direction, n = d.perp * (w.thickness / 2)
                for r in runs {
                    let a = w.centerStart + d * r.0, b = w.centerStart + d * r.1
                    segs += [(a + n, b + n), (a - n, b - n), (a + n, a - n), (b + n, b - n)]
                }
            case .curtainWall(let c):
                if !seeThroughWindows { segs.append((c.start, c.end)) }
            case .column(let c):
                guard c.baseOffset < eyeHeight, c.baseOffset + c.height > eyeHeight else { continue }
                if c.round {
                    let k = 16
                    let pts = (0..<k).map { c.position + Vec2.polar(c.width / 2, 2 * .pi * Double($0) / Double(k)) }
                    for i in 0..<k { segs.append((pts[i], pts[(i + 1) % k])) }
                } else {
                    let t = Transform2D.translation(c.position) * Transform2D.rotation(c.rotation)
                    let pts = [Vec2(-c.width / 2, -c.depth / 2), Vec2(c.width / 2, -c.depth / 2), Vec2(c.width / 2, c.depth / 2), Vec2(-c.width / 2, c.depth / 2)].map(t.apply)
                    for i in 0..<4 { segs.append((pts[i], pts[(i + 1) % 4])) }
                }
            default: continue
            }
        }
        return segs
    }

    /// Visibility polygon from `eye` by ray casting (`rays` directions) up to `maxDistance`.
    public static func polygon(from eye: Vec2, obstacles: [(Vec2, Vec2)], maxDistance: Double, rays: Int = 720) -> [Vec2] {
        var pts: [Vec2] = []
        pts.reserveCapacity(rays)
        for i in 0..<rays {
            let a = 2 * Double.pi * Double(i) / Double(rays)
            let d = Vec2(cos(a), sin(a))
            var t = maxDistance
            for (p, q) in obstacles {
                let e = q - p
                let den = d.cross(e)
                guard abs(den) > 1e-12 else { continue }
                let w = p - eye
                let s = w.cross(e) / den        // along the ray
                let r = w.cross(d) / den        // along the segment
                if s > 1e-9 && s < t && r >= -1e-9 && r <= 1 + 1e-9 { t = s }
            }
            pts.append(eye + d * t)
        }
        return pts
    }
}
